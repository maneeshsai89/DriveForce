public class AgentforceInvocableService {

    public static AgentResponse callAgent(
        String sessionKey,
        String userMessage,
        String phoneNumber,
        String contactId,
        Integer sequenceId
    ) {
        AgentResponse response = new AgentResponse();

        try {
            String actionType = 'generateAiAgentResponse';
            String actionName = 'Electra_Warranty_Intake_Agent';


            Invocable.Action action = Invocable.Action.createCustomAction(
                actionType, actionName
            );

            // ★ Set user message
            action.setInvocationParameter('userMessage', userMessage);

            // ★ Pass session key using ALL possible parameter names
            // The agent will use whichever one it recognizes
            if (String.isNotBlank(sessionKey)) {
                safeSetParam(action, 'sessionId', sessionKey);
                safeSetParam(action, 'sessionKey', sessionKey);
                safeSetParam(action, 'conversationId', sessionKey);
                safeSetParam(action, 'externalSessionKey', sessionKey);
                safeSetParam(action, 'threadId', sessionKey);
                safeSetParam(action, 'chatSessionId', sessionKey);
            }

            List<Invocable.Action.Result> results = action.invoke();

            if (results == null || results.isEmpty()) {
                response.success = false;
                response.message = 'No response from agent.';
                return response;
            }

            Invocable.Action.Result result = results[0];

            if (result.isSuccess()) {
                Map<String, Object> outputs = result.getOutputParameters();
                System.debug('Raw outputs: ' + JSON.serialize(outputs));

                response.success = true;
                response.message = extractPlainTextResponse(outputs, userMessage);

                // ★ CAPTURE SESSION ID FROM RESPONSE ★
                response.sessionId = captureSessionId(outputs, sessionKey);

                response.outputParams = outputs;

                System.debug('Message: ' + response.message);
                System.debug('Session: ' + response.sessionId);

            } else {
                response.success = false;
                response.message = extractErrorMessage(result.getErrors());
            }

        } catch (Exception e) {
            System.debug('Agent error: ' + e.getMessage());
            response.success = false;
            response.message = 'Something went wrong';
            response.error = e.getMessage();
        }

        return response;
    }

    // =============================================
    // ★ CAPTURE SESSION ID FROM AGENT OUTPUT ★
    // =============================================
    private static String captureSessionId(
        Map<String, Object> outputs,
        String defaultSessionId
    ) {
        // Look for session-related keys in output
        List<String> sessionKeys = new List<String>{
            'sessionId',
            'sessionKey',
            'conversationId',
            'externalSessionKey',
            'threadId',
            'chatSessionId',
            'agentSessionId',
            'id'
        };

        for (String key : sessionKeys) {
            if (outputs.containsKey(key) && outputs.get(key) != null) {
                Object val = outputs.get(key);
                if (val instanceof String && String.isNotBlank((String) val)) {
                    String sessionVal = (String) val;
                    // Make sure it's not the user message or a response text
                    if (sessionVal.length() < 200) {
                        System.debug('Captured session from key "' + key + '": ' + sessionVal);
                        return sessionVal;
                    }
                }
            }
        }

        return defaultSessionId;
    }

    // =============================================
    // EXTRACT PLAIN TEXT RESPONSE
    // =============================================
    private static String extractPlainTextResponse(
        Map<String, Object> outputs,
        String userMessage
    ) {
        if (outputs == null || outputs.isEmpty()) {
            return 'I could not generate a response.';
        }

        String userMsgLower = (userMessage != null) ? userMessage.trim().toLowerCase() : '';

        // Skip these keys - they are not the response text
        Set<String> skipKeys = new Set<String>{
            'sessionId', 'sessionKey', 'conversationId',
            'externalSessionKey', 'threadId', 'chatSessionId',
            'agentSessionId', 'id', 'sequenceId', 'status',
            'success', 'error', 'errorCode', 'timestamp'
        };

        for (String key : outputs.keySet()) {
            if (skipKeys.contains(key)) continue;

            Object val = outputs.get(key);
            if (val == null) continue;

            String extracted = extractFromObject(val);

            if (String.isBlank(extracted)) continue;
            if (extracted.trim().toLowerCase() == userMsgLower) continue;
            if (isNumericValue(extracted.trim())) continue;
            if (extracted.trim() == 'true' || extracted.trim() == 'false' || extracted.trim() == 'null') continue;
            if (extracted.trim().length() < 5) continue;

            return extracted;
        }

        return 'I received your message but could not process it. Please try again.';
    }

    // =============================================
    // EXTRACT FROM ANY OBJECT TYPE
    // =============================================
    private static String extractFromObject(Object val) {
        if (val == null) return null;

        if (val instanceof List<Object>) {
            return extractFromListObject((List<Object>) val);
        }

        if (val instanceof Map<String, Object>) {
            return extractFromMapObject((Map<String, Object>) val);
        }

        if (val instanceof String) {
            return extractFromString((String) val);
        }

        if (val instanceof Integer || val instanceof Long ||
            val instanceof Double || val instanceof Decimal) {
            return null;
        }

        if (val instanceof Boolean) {
            return null;
        }

        String strVal = String.valueOf(val);
        if (isNumericValue(strVal)) return null;
        return strVal;
    }

    // =============================================
    // EXTRACT FROM STRING
    // =============================================
    private static String extractFromString(String strVal) {
        if (String.isBlank(strVal)) return null;

        String trimmed = strVal.trim();

        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof List<Object>) {
                    String result = extractFromListObject((List<Object>) parsed);
                    if (String.isNotBlank(result)) return result;
                }
            } catch (Exception e) { }
        }

        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof Map<String, Object>) {
                    String result = extractFromMapObject((Map<String, Object>) parsed);
                    if (String.isNotBlank(result)) return result;
                }
            } catch (Exception e) { }
        }

        if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length() > 2) {
            return trimmed.substring(1, trimmed.length() - 1)
                         .replace('\\n', '\n')
                         .replace('\\"', '"')
                         .trim();
        }

        return trimmed.replace('\\n', '\n').trim();
    }

    // =============================================
    // EXTRACT FROM LIST: [{"type":"Text","value":"..."}]
    // =============================================
    private static String extractFromListObject(List<Object> items) {
        if (items == null || items.isEmpty()) return null;

        List<String> messages = new List<String>();

        for (Object item : items) {
            if (item instanceof Map<String, Object>) {
                Map<String, Object> msgMap = (Map<String, Object>) item;
                String text = extractTextFromMessageMap(msgMap);
                if (String.isNotBlank(text)) {
                    messages.add(text);
                }
            }
            else if (item instanceof String) {
                String s = ((String) item).trim();
                if (String.isNotBlank(s) && !isNumericValue(s)) {
                    messages.add(s);
                }
            }
        }

        return messages.isEmpty() ? null : String.join(messages, '\n');
    }

    // =============================================
    // EXTRACT TEXT FROM MESSAGE MAP
    // {"type":"Text","value":"Hello..."}
    // =============================================
    private static String extractTextFromMessageMap(Map<String, Object> msgMap) {

        List<String> textKeys = new List<String>{
            'value', 'text', 'message', 'content',
            'body', 'response', 'output', 'answer', 'reply'
        };

        for (String key : textKeys) {
            if (msgMap.containsKey(key) && msgMap.get(key) != null) {
                Object keyVal = msgMap.get(key);

                if (keyVal instanceof String) {
                    String s = ((String) keyVal).trim();
                    if (String.isNotBlank(s) && s.length() > 1 && !isNumericValue(s)) {
                        return s.replace('\\n', '\n');
                    }
                }
                else if (keyVal instanceof Map<String, Object>) {
                    String nested = extractFromMapObject((Map<String, Object>) keyVal);
                    if (String.isNotBlank(nested)) return nested;
                }
            }
        }

        if (msgMap.containsKey('payload') && msgMap.get('payload') != null) {
            Object payload = msgMap.get('payload');
            if (payload instanceof Map<String, Object>) {
                Map<String, Object> payloadMap = (Map<String, Object>) payload;
                for (String key : textKeys) {
                    if (payloadMap.containsKey(key) && payloadMap.get(key) instanceof String) {
                        String s = ((String) payloadMap.get(key)).trim();
                        if (String.isNotBlank(s) && !isNumericValue(s)) {
                            return s.replace('\\n', '\n');
                        }
                    }
                }
            }
        }

        return null;
    }

    // =============================================
    // EXTRACT FROM MAP OBJECT
    // =============================================
    private static String extractFromMapObject(Map<String, Object> mapDetail) {
        for (String key : new List<String>{
            'value', 'text', 'message', 'content', 'body',
            'response', 'output', 'answer', 'reply', 'result'
        }) {
            if (mapDetail.containsKey(key) && mapDetail.get(key) instanceof String) {
                String s = ((String) mapDetail.get(key)).trim();
                if (String.isNotBlank(s) && s.length() > 3 && !isNumericValue(s)) {
                    return s.replace('\\n', '\n');
                }
            }
        }
        return null;
    }

    // =============================================
    // CHECK IF STRING IS NUMERIC
    // =============================================
    private static Boolean isNumericValue(String str) {
        if (String.isBlank(str)) return false;
        try {
            Decimal.valueOf(str.trim());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // =============================================
    // SAFE SET PARAMETER
    // =============================================
    private static void safeSetParam(Invocable.Action action, String name, String value) {
        try {
            if (String.isNotBlank(value)) {
                action.setInvocationParameter(name, value);
            }
        } catch (Exception e) { }
    }

    private static String extractErrorMessage(List<Invocable.Action.Error> errors) {
        List<String> msgs = new List<String>();
        if (errors != null) {
            for (Invocable.Action.Error err : errors) {
                msgs.add(err.getCode() + ': ' + err.getMessage());
            }
        }
        return msgs.isEmpty() ? 'Unknown error' : String.join(msgs, '; ');
    }

    public class AgentResponse {
        public Boolean success = false;
        public String message;
        public String sessionId;
        public String error;
        public Map<String, Object> outputParams;
    }
}