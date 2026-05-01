/**
 * WC — Slack Web API chat.update after Electra auto-approval (requires Bot token on WC_Slack_Approval_Config__mdt).
 */
public without sharing class WC_SlackElectraMessageService {
    private static final String CHAT_UPDATE_URL = 'https://slack.com/api/chat.update';

    public static void postElectraApprovedMessage(Id claimId, String channel, String ts, String claimName, String reason) {
        String token = resolveBotToken();
        if (String.isBlank(token)) {
            System.debug(LoggingLevel.WARN, 'WC_Electra Slack chat.update skipped: Slack_Bot_Oauth_Token__c not set on Default CMDT.');
            return;
        }
        if (String.isBlank(channel) || String.isBlank(ts)) {
            return;
        }

        String safeName = slackMrkdwnSafe(claimName);
        String safeReason = slackMrkdwnSafe(reason);
        String statusText =
            ':white_check_mark: *Approved* by *Electra Automated Approver* — *' +
            safeName +
            '* · Id `' +
            String.valueOf(claimId) +
            '` · ' +
            safeReason;

        List<Object> blocks = new List<Object>();
        blocks.add(
            new Map<String, Object>{
                'type' => 'section',
                'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => statusText }
            }
        );
        blocks.add(
            new Map<String, Object>{
                'type' => 'context',
                'elements' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'mrkdwn',
                        'text' => 'Buttons removed · Salesforce Claim updated.'
                    }
                }
            }
        );

        Map<String, Object> body = new Map<String, Object>{
            'channel' => channel,
            'ts' => ts,
            'text' => 'Approved by Electra Automated Approver',
            'blocks' => blocks
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(CHAT_UPDATE_URL);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token.trim());
        req.setHeader('Content-Type', 'application/json; charset=UTF-8');
        req.setBody(JSON.serialize(body));
        req.setTimeout(120000);
        try {
            HttpResponse res = new Http().send(req);
            String rb = res.getBody();
            if (rb != null && rb.length() > 2000) {
                rb = rb.substring(0, 2000);
            }
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                System.debug(LoggingLevel.WARN, 'WC_Electra chat.update HTTP ' + res.getStatusCode() + ' ' + rb);
                return;
            }
            if (String.isNotBlank(rb) && rb.contains('"ok":false')) {
                System.debug(LoggingLevel.WARN, 'WC_Electra chat.update Slack ok=false: ' + rb);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_Electra chat.update callout failed: ' + e.getMessage());
        }
    }

    private static String resolveBotToken() {
        WC_Slack_Approval_Config__mdt cfg = WC_Slack_Approval_Config__mdt.getInstance('Default');
        if (cfg == null || String.isBlank(cfg.Slack_Bot_Oauth_Token__c)) {
            return null;
        }
        return cfg.Slack_Bot_Oauth_Token__c.trim();
    }

    private static String slackMrkdwnSafe(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}
