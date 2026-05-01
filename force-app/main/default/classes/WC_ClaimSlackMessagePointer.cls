/**
 * WC — Persists Slack Incoming Webhook response (channel + ts) on Claim for later chat.update.
 * Isolated without sharing + SYSTEM_MODE so integration/Flow users can write without broad Claim CRUD.
 */
public without sharing class WC_ClaimSlackMessagePointer {
    /**
     * Parses Slack webhook JSON {@code {"ok":true,"channel":"C…","ts":"…"}} and updates the Claim.
     * No-ops on blank claim Id, non-JSON body, missing fields, or {@code ok} not true.
     */
    public static void persistFromWebhookResponse(Id claimId, String slackResponseBody) {
        if (claimId == null || String.isBlank(slackResponseBody)) {
            return;
        }
        String trimmed = slackResponseBody.trim();
        if (trimmed == 'ok') {
            return;
        }
        String channelId;
        String messageTs;
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(trimmed);
            Object okVal = m.get('ok');
            if (okVal != null) {
                if (okVal instanceof Boolean && !(Boolean) okVal) {
                    return;
                }
                if (okVal instanceof String && !'true'.equalsIgnoreCase((String) okVal)) {
                    return;
                }
            }
            channelId = stringVal(m.get('channel'));
            messageTs = stringVal(m.get('ts'));
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'WC_ClaimSlackMessagePointer parse skip: ' + e.getMessage());
            return;
        }
        if (String.isBlank(channelId) || String.isBlank(messageTs)) {
            return;
        }
        Integer delaySec = WC_ElectraConfig.getDelaySeconds();
        Claim c = new Claim(
            Id = claimId,
            WC_Slack_Channel_Id__c = channelId,
            WC_Slack_Message_Ts__c = messageTs,
            WC_Electra_Auto_Check_At__c = System.now().addSeconds(delaySec)
        );
        List<Database.SaveResult> srs = Database.update(new List<Claim>{ c }, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult sr : srs) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.WARN,
                        'WC_ClaimSlackMessagePointer DML ' + err.getStatusCode() + ' ' + err.getMessage()
                    );
                }
            }
        }
    }

    private static String stringVal(Object o) {
        if (o == null) {
            return null;
        }
        return String.valueOf(o).trim();
    }
}
