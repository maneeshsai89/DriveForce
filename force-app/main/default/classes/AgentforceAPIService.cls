public class AgentforceAPIService {
    
    private static final String BASE_URL = URL.getOrgDomainUrl().toExternalForm();
    private static final String API_VERSION = 'v66.0';
    private static final String AGENT_ID = '0Xxbm000001ety5CAA'; // Replace with actual Agent ID
    
    // =============================================
    // CREATE NEW SESSION
    // =============================================
    public static String createSession() {
        
       //String endpoint = 'https://orgfarm-fb6e5c4387.my.salesforce.com/einstein/ai-agent/v1/agents/0Xxbm000001ety5CAA/sessions';
       //String endpoint = 'https://orgfarm-fb6e5c4387.my.salesforce.com/einstein/ai-agent/v1/agents/0Xxbm000001ety5CAA/sessions';

// The CORRECT endpoint might be:
//String endpoint = BASE_URL + '/services/data/v66.0/einstein/ai-runtime/sessions';

// OR for specific agent:

        //String endpoint = BASE_URL + '/services/data/v66.0/einstein/bots/' + AGENT_ID + '/sessions';
        
        //String endpoint = BASE_URL + 
            //'/services/data/' + API_VERSION + 
            //'/einstein/ai-agent/sessions';
        
        String endpoint = 'https://api.salesforce.com/einstein/ai-agent/v1/agents/0Xxbm000001ety5CAA/sessions';
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'externalSessionKey' => generateUUID(),
            'instanceConfig' => new Map<String, Object>{
                'endpoint' => BASE_URL
            },
            'streamingCapability' => new Map<String, Object>{
                'chunkTypes' => new List<String>{ 'Text' }
            },
            'bypassUser' => false,
            'agentId' => '0Xxbm000001ety5CAA'
        };
        System.debug(endpoint);
        System.debug(JSON.serialize(requestBody));
        HttpResponse res = makeCallout('POST', endpoint, JSON.serialize(requestBody));
        System.debug(res);
        
        System.debug('Create Session Status: ' + res.getStatusCode());
        System.debug('Create Session Body: ' + res.getBody());
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> responseMap = 
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseMap.get('sessionId');
        }
        
        throw new AgentforceException(
            'Failed to create session: ' + res.getStatusCode() + ' - ' + res.getBody()
        );
    }
    
    // =============================================
    // SEND MESSAGE TO EXISTING SESSION
    // =============================================
    public static String sendMessage(String sessionId, String message, Integer sequenceId) {
        String endpoint = BASE_URL + 
            '/services/data/' + API_VERSION + 
            '/einstein/ai-agent/sessions/' + sessionId + '/messages';
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'message' => new Map<String, Object>{
                'sequenceId' => sequenceId,
                'type' => 'Text',
                'text' => message
            }
        };
        
        HttpResponse res = makeCallout('POST', endpoint, JSON.serialize(requestBody));
        
        System.debug('Send Message Status: ' + res.getStatusCode());
        System.debug('Send Message Body: ' + res.getBody());
        
        if (res.getStatusCode() == 200) {
            return extractAgentResponse(res.getBody());
        }
        
        // Session expired or invalid
        if (res.getStatusCode() == 404 || res.getStatusCode() == 410) {
            throw new SessionExpiredException(
                'Session expired: ' + sessionId
            );
        }
        
        throw new AgentforceException(
            'Failed to send message: ' + res.getStatusCode() + ' - ' + res.getBody()
        );
    }
    
    // =============================================
    // END SESSION
    // =============================================
    public static void endSession(String sessionId) {
        String endpoint = BASE_URL + 
            '/services/data/' + API_VERSION + 
            '/einstein/ai-agent/sessions/' + sessionId;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'reason' => 'UserRequest'
        };
        
        try {
            makeCallout('DELETE', endpoint, JSON.serialize(requestBody));
        } catch (Exception e) {
            System.debug('End session error (non-critical): ' + e.getMessage());
        }
    }
    
    // =============================================
    // PRIVATE HELPERS
    // =============================================
    private static HttpResponse makeCallout(String method, String endpoint, String body) {
        System.debug('endpoint '+endpoint);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + getAccessToken());
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        
        if (String.isNotBlank(body) && method != 'GET') {
            req.setBody(body);
        }
        
        Http http = new Http();
        return http.send(req);
    }
    
    private static String getAccessToken() {
        // Option 1: If running in user context
        // return UserInfo.getSessionId();
        
        // Option 2: Use Connected App for server-to-server auth
        return AuthTokenService.getToken();
    }
    
    private static String extractAgentResponse(String responseBody) {
        Map<String, Object> responseMap = 
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        
        List<String> responseTexts = new List<String>();
        
        // Check for 'messages' array
        if (responseMap.containsKey('messages')) {
            List<Object> messages = (List<Object>) responseMap.get('messages');
            
            for (Object msg : messages) {
                Map<String, Object> msgMap = (Map<String, Object>) msg;
                String msgType = (String) msgMap.get('type');
                
                if (msgType == 'Text') {
                    String text = (String) msgMap.get('text');
                    if (String.isNotBlank(text)) {
                        responseTexts.add(text);
                    }
                }
                else if (msgType == 'Inform' || msgType == 'Reply') {
                    Map<String, Object> payload = 
                        (Map<String, Object>) msgMap.get('payload');
                    if (payload != null && payload.containsKey('text')) {
                        responseTexts.add((String) payload.get('text'));
                    }
                }
            }
        }
        
        // Check for direct 'text' field
        if (responseTexts.isEmpty() && responseMap.containsKey('text')) {
            responseTexts.add((String) responseMap.get('text'));
        }
        
        if (responseTexts.isEmpty()) {
            System.debug('Full response for debugging: ' + responseBody);
            return 'I apologize, I could not process that. Please try again.';
        }
        
        return String.join(responseTexts, '\n');
    }
    
    private static String generateUUID() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return h.substring(0, 8) + '-' + 
               h.substring(8, 12) + '-' + 
               h.substring(12, 16) + '-' + 
               h.substring(16, 20) + '-' + 
               h.substring(20);
    }
    
    // =============================================
    // CUSTOM EXCEPTIONS
    // =============================================
    public class AgentforceException extends Exception {}
    public class SessionExpiredException extends Exception {}
}