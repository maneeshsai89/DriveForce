public class AgentCalloutQueueable implements Queueable, Database.AllowsCallouts {

    private String sessionRecordId;
    private String sessionKey;
    private String contactId;
    private Integer currentSequence;
    private String phoneNumber;
    private String userMessage;
    private String senderName;

    public AgentCalloutQueueable(
        String sessionRecordId,
        String sessionKey,
        String contactId,
        Integer currentSequence,
        String phoneNumber,
        String userMessage,
        String senderName
    ) {
        this.sessionRecordId = sessionRecordId;
        this.sessionKey = sessionKey;
        this.contactId = contactId;
        this.currentSequence = currentSequence;
        this.phoneNumber = phoneNumber;
        this.userMessage = userMessage;
        this.senderName = senderName;
    }

    public void execute(QueueableContext context) {
        String responseToSend = '';

        try {
            System.debug('=== Agent Callout ===');
            System.debug('Session Key: ' + sessionKey);
            System.debug('User: ' + userMessage);
            System.debug('Sequence: ' + currentSequence);

            // 1. CALL AGENT with session key
            AgentforceInvocableService.AgentResponse agentResult =
                AgentforceInvocableService.callAgent(
                    sessionKey, userMessage, phoneNumber,
                    contactId, currentSequence + 1
                );

            if (agentResult.success && String.isNotBlank(agentResult.message)) {
                responseToSend = agentResult.message;

                // ★ CAPTURE AGENT'S SESSION ID ★
                if (String.isNotBlank(agentResult.sessionId) &&
                    agentResult.sessionId != sessionKey) {
                    System.debug('Agent returned NEW session ID: ' + agentResult.sessionId);
                    this.sessionKey = agentResult.sessionId;
                }
            } else {
                responseToSend = 'Something went wrong';
            }

            // Clean response
            responseToSend = ensureCleanText(responseToSend);

            System.debug('Sending: ' + responseToSend);

            // 2. SEND TO WHATSAPP
             WhatsAppService.sendTextMessage(
                phoneNumber, 
                responseToSend
            );


            // 3. UPDATE SESSION - ★ Store agent's session ID ★
            updateSession(responseToSend);

        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            try {
                 WhatsAppService.sendTextMessage(
                phoneNumber, 
                'Something went wrong'
            );

            } catch (Exception e2) { }
        }
    }

    // =============================================
    // ENSURE CLEAN TEXT
    // =============================================
    private String ensureCleanText(String text) {
        if (String.isBlank(text)) {
            return 'I could not process your request. Please try again.';
        }

        String trimmed = text.trim();

        // Check if numeric
        try {
            Decimal.valueOf(trimmed);
            return 'I received your message but encountered an issue. Please try again.';
        } catch (Exception e) {
            // Not numeric - good
        }

        // Check if JSON
        if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
            String parsed = parseJson(trimmed);
            if (String.isNotBlank(parsed)) return parsed;
            return 'I processed your request. Please try again if needed.';
        }

        return trimmed;
    }

    private String parseJson(String jsonString) {
        try {
            Object parsed = JSON.deserializeUntyped(jsonString);

            if (parsed instanceof List<Object>) {
                List<String> texts = new List<String>();
                for (Object item : (List<Object>) parsed) {
                    if (item instanceof Map<String, Object>) {
                        Map<String, Object> mapDetail = (Map<String, Object>) item;
                        for (String key : new List<String>{'value', 'text', 'message', 'content'}) {
                            if (mapDetail.containsKey(key) && mapDetail.get(key) instanceof String) {
                                texts.add(((String) mapDetail.get(key)).trim());
                                break;
                            }
                        }
                    }
                }
                if (!texts.isEmpty()) return String.join(texts, '\n');
            }

            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> mapDetails1 = (Map<String, Object>) parsed;
                for (String key : new List<String>{'value', 'text', 'message', 'response', 'content'}) {
                    if (mapDetails1.containsKey(key) && mapDetails1.get(key) instanceof String) {
                        return ((String) mapDetails1.get(key)).trim();
                    }
                }
            }
        } catch (Exception e) { }
        return null;
    }

    // =============================================
    // ★ UPDATE SESSION WITH AGENT'S SESSION ID ★
    // =============================================
    private void updateSession(String agentResponse) {
        try {
            List<Agentforce_Session__c> sessions = [
                SELECT Id, Sequence_Id__c, Session_Id__c
                FROM Agentforce_Session__c
                WHERE Id = :sessionRecordId LIMIT 1
            ];

            if (!sessions.isEmpty()) {
                Agentforce_Session__c s = sessions[0];
                s.Sequence_Id__c = currentSequence + 1;
                s.Last_Activity__c = DateTime.now();

                // ★ Store agent's session ID for next message ★
                if (String.isNotBlank(sessionKey)) {
                    s.Session_Id__c = sessionKey;
                }

                
                update s;

                System.debug('Session updated. ID: ' + s.Session_Id__c +
                           ' Seq: ' + s.Sequence_Id__c);
            }
        } catch (Exception e) {
            System.debug('Session update error: ' + e.getMessage());
        }
    }
}