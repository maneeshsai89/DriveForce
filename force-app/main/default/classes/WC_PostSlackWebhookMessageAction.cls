/**
 * WC - Invocable: POST Block Kit payload to Slack Incoming Webhooks.
 * URL from Flow input or WC_Slack_Approval_Config__mdt (no Named Credential).
 */
public with sharing class WC_PostSlackWebhookMessageAction {
    public class WC_Request {
        @InvocableVariable(label='Fallback Text' description='Plain-text fallback for Slack.' required=true)
        public String fallbackText;
        @InvocableVariable(label='Blocks JSON Only' description='JSON array of Block Kit blocks.')
        public String blocksArrayJson;
        @InvocableVariable(label='Slack Message JSON' description='Optional slackMessageJson wrapper.')
        public String slackMessageJson;
        @InvocableVariable(label='Webhook URL' description='Optional. If blank, uses custom metadata.')
        public String webhookUrl;
        @InvocableVariable(
            label='Claim Id'
            description='Optional. When set, successful Slack webhook response (channel + ts) is stored on the Claim for later message updates.'
        )
        public String claimId;
    }

    public class WC_Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='HTTP Status Code')
        public Integer httpStatusCode;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Response Body')
        public String responseBody;
    }

    @InvocableMethod(
        label='WC Post Slack Webhook Message'
        description='POST Block Kit to Slack Incoming Webhook. Optional Claim Id: on success, stores Slack channel + message ts on the Claim for later chat.update.'
    )
    public static List<WC_Result> post(List<WC_Request> requests) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackWebhook batchSize=' + (requests == null ? 0 : requests.size())
        );
        List<WC_Result> results = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackWebhook empty request list.');
            return results;
        }
        for (WC_Request req : requests) {
            results.add(postOne(req));
        }
        return results;
    }

    private static WC_Result postOne(WC_Request req) {
        WC_Result res = new WC_Result();
        res.success = false;
        res.httpStatusCode = null;
        res.errorMessage = null;
        res.responseBody = null;

        if (req == null) {
            res.errorMessage = 'Request is null.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackWebhook fail: ' + res.errorMessage);
            return res;
        }
        if (String.isBlank(req.fallbackText)) {
            res.errorMessage = 'Fallback Text is required.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackWebhook fail: ' + res.errorMessage);
            return res;
        }

        Boolean urlFromFlow = String.isNotBlank(req.webhookUrl);
        String endpoint = resolveWebhookUrl(req.webhookUrl);
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackWebhook endpointResolved=' +
                String.isNotBlank(endpoint) +
                ' urlFromFlow=' +
                urlFromFlow +
                ' endpointLen=' +
                (endpoint == null ? 0 : endpoint.length()) +
                ' blocksArrayJsonLen=' +
                (req.blocksArrayJson == null ? 0 : req.blocksArrayJson.length()) +
                ' slackMessageJsonLen=' +
                (req.slackMessageJson == null ? 0 : req.slackMessageJson.length())
        );
        if (String.isBlank(endpoint)) {
            res.errorMessage = 'Webhook URL is blank. Set Flow input or WC Slack Approval Config.';
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook fail: ' + res.errorMessage);
            return res;
        }
        if (!endpoint.startsWithIgnoreCase('https://')) {
            res.errorMessage = 'Webhook URL must start with https://';
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook fail: ' + res.errorMessage);
            return res;
        }

        Object blocksPayload;
        try {
            blocksPayload = resolveBlocks(req.blocksArrayJson, req.slackMessageJson);
        } catch (Exception e) {
            res.errorMessage = 'Invalid blocks JSON: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook parse blocks: ' + res.errorMessage);
            System.debug(LoggingLevel.ERROR, e);
            return res;
        }

        Map<String, Object> body = new Map<String, Object>();
        body.put('text', req.fallbackText);
        if (blocksPayload != null) {
            body.put('blocks', blocksPayload);
        }

        String jsonBody = JSON.serialize(body);
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackWebhook POST bodyLen=' + jsonBody.length() + ' hasBlocks=' + (blocksPayload != null)
        );

        // Flow may run Generate Approver Summary (DML persist) before this action — same txn cannot call out after DML.
        // Production: defer HTTP to @future so callout runs after commit. Tests: sync callout for HttpCalloutMock assertions.
        if (Test.isRunningTest()) {
            executeSlackCallout(endpoint, jsonBody, res, req.claimId);
        } else {
            try {
                sendSlackWebhookFuture(endpoint, jsonBody, req.claimId);
                res.success = true;
                res.httpStatusCode = null;
                res.responseBody = 'Queued for Slack delivery (async after commit).';
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackWebhook queued @future endpointLen=' + endpoint.length() + ' bodyLen=' + jsonBody.length()
                );
            } catch (Exception e) {
                res.errorMessage = 'Failed to queue Slack post: ' + e.getMessage();
                System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook queue failed: ' + res.errorMessage);
                System.debug(LoggingLevel.ERROR, e);
            }
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackWebhook done success=' + res.success + ' http=' + res.httpStatusCode
        );
        return res;
    }

    /**
     * Runs after the triggering transaction commits — safe when prior steps performed DML (e.g. persist AI summary).
     */
    @future(callout=true)
    private static void sendSlackWebhookFuture(String endpoint, String jsonBody, String claimIdStr) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json; charset=UTF-8');
        httpReq.setBody(jsonBody);
        httpReq.setTimeout(120000);
        try {
            HttpResponse httpRes = new Http().send(httpReq);
            String rb = truncate(httpRes.getBody(), 4000);
            if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300) {
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackWebhook @future OK http=' + httpRes.getStatusCode() + ' body=' + rb
                );
                maybePersistSlackPointer(claimIdStr, rb);
            } else {
                System.debug(
                    LoggingLevel.ERROR,
                    'WC_SLACK_FLOW PostSlackWebhook @future Slack HTTP ' + httpRes.getStatusCode() + ': ' + rb
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook @future callout failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e);
        }
    }

    private static void maybePersistSlackPointer(String claimIdStr, String responseBody) {
        if (String.isBlank(claimIdStr) || String.isBlank(responseBody)) {
            return;
        }
        try {
            Id cid = Id.valueOf(claimIdStr.trim());
            WC_ClaimSlackMessagePointer.persistFromWebhookResponse(cid, responseBody);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackWebhook skip Claim pointer: ' + e.getMessage());
        }
    }

    private static void executeSlackCallout(String endpoint, String jsonBody, WC_Result res, String claimIdStr) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json; charset=UTF-8');
        httpReq.setBody(jsonBody);
        httpReq.setTimeout(120000);

        try {
            HttpResponse httpRes = new Http().send(httpReq);
            res.httpStatusCode = httpRes.getStatusCode();
            res.responseBody = truncate(httpRes.getBody(), 4000);
            if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300) {
                res.success = true;
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackWebhook HTTP ' + res.httpStatusCode + ' responseLen=' + (res.responseBody == null ? 0 : res.responseBody.length())
                );
                maybePersistSlackPointer(claimIdStr, res.responseBody);
            } else {
                res.errorMessage = 'Slack returned HTTP ' + httpRes.getStatusCode() + ': ' + res.responseBody;
                System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook ' + res.errorMessage);
            }
        } catch (Exception e) {
            res.errorMessage = 'Callout failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackWebhook callout: ' + res.errorMessage);
            System.debug(LoggingLevel.ERROR, e);
        }
    }

    private static String resolveWebhookUrl(String fromFlow) {
        if (String.isNotBlank(fromFlow)) {
            return fromFlow.trim();
        }
        List<WC_Slack_Approval_Config__mdt> rows = [
            SELECT Slack_Incoming_Webhook_Url__c
            FROM WC_Slack_Approval_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Slack_Incoming_Webhook_Url__c)) {
            return null;
        }
        return rows[0].Slack_Incoming_Webhook_Url__c.trim();
    }

    private static Object resolveBlocks(String blocksArrayJson, String slackMessageJson) {
        if (String.isNotBlank(blocksArrayJson)) {
            return JSON.deserializeUntyped(blocksArrayJson.trim());
        }
        if (String.isNotBlank(slackMessageJson)) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(slackMessageJson.trim());
            return root.get('blocks');
        }
        return null;
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null || maxLen == null || maxLen <= 0) {
            return s;
        }
        if (s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen);
    }
}