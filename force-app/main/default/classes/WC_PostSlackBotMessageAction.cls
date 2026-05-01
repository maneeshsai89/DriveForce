/**
 * WC — Invocable: POST Block Kit via Slack Web API {@code chat.postMessage} using the bot token from
 * {@code WC_Slack_Approval_Config__mdt}. Same inputs/behavior as {@link WC_PostSlackWebhookMessageAction}
 * (optional Claim Id → persist channel + ts for {@code chat.update}), but responses include {@code ts}.
 *
 * <p>Use this when you need to edit the same message later (e.g. remove buttons). To revert to Incoming
 * Webhooks only, switch the Flow action back to {@link WC_PostSlackWebhookMessageAction}.</p>
 */
public with sharing class WC_PostSlackBotMessageAction {
    public static final String CHAT_POST_MESSAGE_URL = 'https://slack.com/api/chat.postMessage';

    public class WC_Request {
        @InvocableVariable(label='Fallback Text' description='Plain-text fallback for Slack.' required=true)
        public String fallbackText;
        @InvocableVariable(label='Blocks JSON Only' description='JSON array of Block Kit blocks.')
        public String blocksArrayJson;
        @InvocableVariable(label='Slack Message JSON' description='Optional slackMessageJson wrapper.')
        public String slackMessageJson;
        @InvocableVariable(
            label='Slack Channel Id'
            description='Optional. Channel ID (C…). If blank, uses WC Slack Approval Config → Slack Channel Id.'
        )
        public String slackChannelId;
        @InvocableVariable(
            label='Slack Bot OAuth Token'
            description='Optional. If blank, uses WC Slack Approval Config (Default) Slack Bot OAuth Token.'
        )
        public String slackBotOauthToken;
        @InvocableVariable(
            label='Claim Id'
            description='Optional. On success, stores Slack channel + message ts on the Claim for chat.update.'
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
        label='WC Post Slack Bot Message (chat.postMessage)'
        description='POST Block Kit via chat.postMessage using bot token from metadata. Same as webhook action but returns ts for later edits.'
    )
    public static List<WC_Result> post(List<WC_Request> requests) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackBot batchSize=' + (requests == null ? 0 : requests.size())
        );
        List<WC_Result> results = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackBot empty request list.');
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
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackBot fail: ' + res.errorMessage);
            return res;
        }
        if (String.isBlank(req.fallbackText)) {
            res.errorMessage = 'Fallback Text is required.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackBot fail: ' + res.errorMessage);
            return res;
        }

        String token = resolveBotToken(req.slackBotOauthToken);
        String channelId = resolveChannelId(req.slackChannelId);
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackBot tokenResolved=' +
                String.isNotBlank(token) +
                ' channelResolved=' +
                String.isNotBlank(channelId) +
                ' blocksArrayJsonLen=' +
                (req.blocksArrayJson == null ? 0 : req.blocksArrayJson.length())
        );
        if (String.isBlank(token)) {
            res.errorMessage = 'Slack Bot OAuth Token is blank. Set WC Slack Approval Config (Default).';
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot fail: ' + res.errorMessage);
            return res;
        }
        if (String.isBlank(channelId)) {
            res.errorMessage = 'Slack Channel Id is blank. Set Flow input or WC Slack Approval Config.';
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot fail: ' + res.errorMessage);
            return res;
        }

        Object blocksPayload;
        try {
            blocksPayload = resolveBlocks(req.blocksArrayJson, req.slackMessageJson);
        } catch (Exception e) {
            res.errorMessage = 'Invalid blocks JSON: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot parse blocks: ' + res.errorMessage);
            System.debug(LoggingLevel.ERROR, e);
            return res;
        }

        Map<String, Object> body = new Map<String, Object>();
        body.put('channel', channelId);
        body.put('text', req.fallbackText);
        if (blocksPayload != null) {
            body.put('blocks', blocksPayload);
        }

        String jsonBody = JSON.serialize(body);
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackBot POST bodyLen=' + jsonBody.length() + ' hasBlocks=' + (blocksPayload != null)
        );

        if (Test.isRunningTest()) {
            executeSlackCallout(token, jsonBody, res, req.claimId);
        } else {
            try {
                sendSlackBotPostFuture(token, jsonBody, req.claimId);
                res.success = true;
                res.httpStatusCode = null;
                res.responseBody = 'Queued for Slack delivery (async after commit).';
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackBot queued @future bodyLen=' + jsonBody.length()
                );
            } catch (Exception e) {
                res.errorMessage = 'Failed to queue Slack post: ' + e.getMessage();
                System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot queue failed: ' + res.errorMessage);
                System.debug(LoggingLevel.ERROR, e);
            }
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW PostSlackBot done success=' + res.success + ' http=' + res.httpStatusCode
        );
        return res;
    }

    @future(callout=true)
    private static void sendSlackBotPostFuture(String bearerToken, String jsonBody, String claimIdStr) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(CHAT_POST_MESSAGE_URL);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json; charset=UTF-8');
        httpReq.setHeader('Authorization', 'Bearer ' + bearerToken);
        httpReq.setBody(jsonBody);
        httpReq.setTimeout(120000);
        try {
            HttpResponse httpRes = new Http().send(httpReq);
            String rb = truncate(httpRes.getBody(), 4000);
            if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300 && slackApiOk(rb)) {
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackBot @future OK http=' + httpRes.getStatusCode() + ' body=' + rb
                );
                maybePersistSlackPointer(claimIdStr, rb);
            } else {
                System.debug(
                    LoggingLevel.ERROR,
                    'WC_SLACK_FLOW PostSlackBot @future Slack HTTP ' + httpRes.getStatusCode() + ': ' + rb
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot @future callout failed: ' + e.getMessage());
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
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW PostSlackBot skip Claim pointer: ' + e.getMessage());
        }
    }

    private static void executeSlackCallout(String bearerToken, String jsonBody, WC_Result res, String claimIdStr) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(CHAT_POST_MESSAGE_URL);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json; charset=UTF-8');
        httpReq.setHeader('Authorization', 'Bearer ' + bearerToken);
        httpReq.setBody(jsonBody);
        httpReq.setTimeout(120000);

        try {
            HttpResponse httpRes = new Http().send(httpReq);
            res.httpStatusCode = httpRes.getStatusCode();
            res.responseBody = truncate(httpRes.getBody(), 4000);
            if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300 && slackApiOk(res.responseBody)) {
                res.success = true;
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_FLOW PostSlackBot HTTP ' + res.httpStatusCode + ' responseLen=' + (res.responseBody == null
                        ? 0
                        : res.responseBody.length())
                );
                maybePersistSlackPointer(claimIdStr, res.responseBody);
            } else {
                res.errorMessage = 'Slack returned HTTP ' + httpRes.getStatusCode() + ': ' + res.responseBody;
                System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot ' + res.errorMessage);
            }
        } catch (Exception e) {
            res.errorMessage = 'Callout failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_FLOW PostSlackBot callout: ' + res.errorMessage);
            System.debug(LoggingLevel.ERROR, e);
        }
    }

    /**
     * Slack Web API returns HTTP 200 with {@code "ok":false} for many errors; require JSON {@code ok:true}.
     */
    @TestVisible
    private static Boolean slackApiOk(String responseBody) {
        if (String.isBlank(responseBody)) {
            return false;
        }
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(responseBody.trim());
            Object ok = m.get('ok');
            if (ok instanceof Boolean) {
                return (Boolean) ok;
            }
            if (ok instanceof String) {
                return 'true'.equalsIgnoreCase((String) ok);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_FLOW PostSlackBot slackApiOk parse: ' + e.getMessage());
        }
        return false;
    }

    private static String resolveBotToken(String fromFlow) {
        if (String.isNotBlank(fromFlow)) {
            return fromFlow.trim();
        }
        WC_Slack_Approval_Config__mdt cfg = WC_Slack_Approval_Config__mdt.getInstance('Default');
        if (cfg == null || String.isBlank(cfg.Slack_Bot_Oauth_Token__c)) {
            return null;
        }
        return cfg.Slack_Bot_Oauth_Token__c.trim();
    }

    private static String resolveChannelId(String fromFlow) {
        if (String.isNotBlank(fromFlow)) {
            return fromFlow.trim();
        }
        WC_Slack_Approval_Config__mdt cfg = WC_Slack_Approval_Config__mdt.getInstance('Default');
        if (cfg == null || String.isBlank(cfg.Slack_Channel_Id__c)) {
            return null;
        }
        return cfg.Slack_Channel_Id__c.trim();
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
