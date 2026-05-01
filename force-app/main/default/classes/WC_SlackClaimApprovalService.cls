/**
 * WC — Applies Slack Approve/Reject to Claim (same outcome as WC_Update_Claim_From_Slack_Decision).
 * Used from WC_SlackInteractivityRest because Site Guest users cannot be granted "Run Flows".
 * DML uses AccessLevel.SYSTEM_MODE so Experience Cloud Guest does not need Claim Read/Edit in the permission set
 * (Guest licenses often disallow object permissions on Claim).
 * without sharing: sharing rules do not block update by Claim Id after Slack signature verification.
 *
 * Async entry {@link #applySlackDecisionAsync} enqueues {@link WC_SlackClaimDecisionQueueable} (not {@code @future})
 * so Experience Guest REST is not blocked by Guest → {@code @future} restrictions.
 * After DML, optionally POSTs to Slack {@code response_url} with {@code replace_original: true}: prepends a status line
 * (decision + Claim name/Id) and keeps the original Block Kit content with {@code actions} blocks removed so context
 * is preserved. Requires Remote Site {@code hooks.slack.com} and Guest callout/queue permissions as applicable.
 */
public without sharing class WC_SlackClaimApprovalService {
    /**
     * Queues claim update so Apex REST can return HTTP 200 within Slack’s 3s window.
     * Uses {@link WC_SlackClaimDecisionQueueable} (not {@code @future}) because Guest users often cannot invoke {@code @future} from REST.
     * Optional Slack UI update runs in {@link WC_SlackResponseUrlQueueable} (callouts cannot run after DML in the same transaction).
     * Synchronous path: {@link #applySlackDecision(String, String)}.
     */
    public static void applySlackDecisionAsync(String claimIdStr, String decision, String responseUrl, String slackMessageJson) {
        try {
            System.enqueueJob(new WC_SlackClaimDecisionQueueable(claimIdStr, decision, responseUrl, slackMessageJson));
            List<Claim> claimList = [SELECT ID,AccountID,Name,ClaimType,CreatedDate,ApprovedAmount,TotalClaimedAmount,WC_Rejection_Reason__c,EstimatedAmount FROM Claim where Id =:claimIdStr];
            System.enqueueJob(new SendMessageFromClaimQueueable(claimList,decision));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_APPROVAL enqueue WC_SlackClaimDecisionQueueable failed: ' + e.getMessage());
            applySlackDecision(claimIdStr, decision);
        }
    }

    public static void applySlackDecision(String claimIdStr, String decision) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_APPROVAL applySlackDecision decision=' + decision + ' claimIdStr_len=' + (claimIdStr == null ? 0 : claimIdStr.length())
        );
        if (String.isBlank(claimIdStr) || String.isBlank(decision)) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_APPROVAL skip: blank claimId or decision');
            return;
        }
        Id claimId;
        try {
            claimId = (Id) claimIdStr;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_APPROVAL skip: invalid Claim Id — ' + e.getMessage());
            return;
        }
        String resultValue;
        if ('Approve'.equals(decision)) {
            resultValue = 'Approved';
        } else if ('Reject'.equals(decision)) {
            resultValue = 'Rejected';
        } else {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_APPROVAL skip: decision not Approve/Reject');
            return;
        }
        Claim c = new Claim(
            Id = claimId,
            WC_Approval_Result__c = resultValue,
            WC_Approval_Channel__c = 'Slack'
        );
        if ('Approved'.equals(resultValue)) {
            c.WC_Approved_At__c = System.now();
        }
        List<Database.SaveResult> srs = Database.update(new List<Claim>{ c }, false, System.AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult sr : srs) {
            if (sr.isSuccess()) {
                System.debug(LoggingLevel.DEBUG, 'WC_SLACK_APPROVAL DML ok claimId=' + claimId + ' result=' + resultValue);
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'WC_SLACK_APPROVAL DML fail claimId=' + claimId + ' — ' + err.getStatusCode() + ' ' + err.getMessage()
                    );
                }
            }
        }
    }

    /**
     * Replaces the interactive message in Slack using {@code response_url}: status line + optional original blocks
     * (Slack {@code message} JSON) with {@code actions} stripped so Approve/Reject buttons disappear.
     */
    public static void postSlackResponseUrlReplace(String responseUrl, String decision, String claimIdStr, String slackMessageJson) {
        if (String.isBlank(responseUrl)) {
            return;
        }
        String claimName = resolveClaimLabel(claimIdStr);
        String statusLine = buildDecisionStatusLine(decision, claimName, claimIdStr);
        List<Object> blocks = new List<Object>();
        Map<String, Object> statusSection = new Map<String, Object>{
            'type' => 'section',
            'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => statusLine }
        };
        blocks.add(statusSection);
        List<Object> originalKept = extractSlackBlocksWithoutActions(slackMessageJson);
        if (originalKept != null && !originalKept.isEmpty()) {
            blocks.add(new Map<String, Object>{ 'type' => 'divider' });
            blocks.addAll(originalKept);
        }
        Map<String, Object> payload = new Map<String, Object>{ 'replace_original' => true, 'blocks' => blocks };
        HttpRequest req = new HttpRequest();
        req.setEndpoint(responseUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json; charset=UTF-8');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(12000);
        try {
            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            if (code < 200 || code >= 300) {
                String rb = res.getBody();
                if (rb != null && rb.length() > 500) {
                    rb = rb.substring(0, 500);
                }
                System.debug(LoggingLevel.WARN, 'WC_SLACK_APPROVAL response_url HTTP ' + code + ' body=' + (rb == null ? '' : rb));
            } else {
                System.debug(LoggingLevel.DEBUG, 'WC_SLACK_APPROVAL response_url ok HTTP ' + code);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_APPROVAL response_url callout failed: ' + e.getMessage());
        }
    }

    private static String resolveClaimLabel(String claimIdStr) {
        if (String.isBlank(claimIdStr)) {
            return '';
        }
        try {
            // Guest users often have no Claim read; align with DML system mode for label lookup
            List<Claim> rows = [
                SELECT Name
                FROM Claim
                WHERE Id = :claimIdStr
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Name)) {
                return rows[0].Name;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_APPROVAL resolveClaimLabel: ' + e.getMessage());
        }
        return claimIdStr;
    }

    private static String buildDecisionStatusLine(String decision, String claimName, String claimIdStr) {
        Boolean approved = 'Approve'.equals(decision);
        String emoji = approved ? ':white_check_mark:' : ':x:';
        String verb = approved ? '*Approved*' : '*Rejected*';
        String safeName = slackMrkdwnSafe(claimName);
        return emoji +
            ' ' +
            verb +
            ' — *' +
            safeName +
            '* · Id `' +
            String.valueOf(claimIdStr) +
            '` · Salesforce record updated.';
    }

    private static String slackMrkdwnSafe(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    /**
     * Returns {@code message.blocks} from Slack payload with {@code type=actions} blocks removed (buttons).
     */
    private static List<Object> extractSlackBlocksWithoutActions(String slackMessageJson) {
        if (String.isBlank(slackMessageJson)) {
            return null;
        }
        try {
            Map<String, Object> msg = (Map<String, Object>) JSON.deserializeUntyped(slackMessageJson);
            Object blocksObj = msg.get('blocks');
            if (!(blocksObj instanceof List<Object>)) {
                return null;
            }
            List<Object> blocks = (List<Object>) blocksObj;
            List<Object> kept = new List<Object>();
            for (Object b : blocks) {
                if (!(b instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> bm = (Map<String, Object>) b;
                String bt = (String) bm.get('type');
                if ('actions'.equals(bt)) {
                    continue;
                }
                kept.add(b);
            }
            return kept;
        } catch (Exception e) {
            return null;
        }
    }
}