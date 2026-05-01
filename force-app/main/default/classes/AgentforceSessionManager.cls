public class AgentforceSessionManager {
    
    private static final Integer SESSION_TIMEOUT_MINUTES = 30;
    
    // =============================================
    // MAIN METHOD: Process WhatsApp Message
    // =============================================
    public static String processWhatsAppMessage(String phoneNumber, String incomingMessage) {
        
        System.debug('Processing message from: ' + phoneNumber);
        System.debug('Message: ' + incomingMessage);
        
        // Handle special commands
        if (incomingMessage.trim().equalsIgnoreCase('reset') || 
            incomingMessage.trim().equalsIgnoreCase('new chat')) {
            resetSession(phoneNumber);
            return 'Session reset. How can I help you today?';
        }
        
        // Get or create session for this phone number
        Agentforce_Session__c session = getOrCreateSession(phoneNumber);
        System.debug(session);
        
        try {
            // Increment sequence
            session.Sequence_Id__c = session.Sequence_Id__c + 1;
            Integer sequenceId = (Integer) session.Sequence_Id__c;
            
            // Send message to Agentforce
            String agentResponse = AgentforceAPIService.sendMessage(
                session.Session_Id__c, 
                incomingMessage, 
                sequenceId
            );
            
            // Update session activity
            session.Last_Activity__c = DateTime.now();
            update session;
            
            System.debug('Agent Response: ' + agentResponse);
            return agentResponse;
            
        } catch (AgentforceAPIService.SessionExpiredException e) {
            // Session expired - create new one and retry
            System.debug('Session expired. Creating new session...');
            
            expireSessionRecord(session);
            
            Agentforce_Session__c newSession = createNewSession(phoneNumber);
            
            String agentResponse = AgentforceAPIService.sendMessage(
                newSession.Session_Id__c, 
                incomingMessage, 
                1
            );
            
            newSession.Sequence_Id__c = 1;
            newSession.Last_Activity__c = DateTime.now();
            update newSession;
            
            return agentResponse;
            
        } catch (Exception e) {
            System.debug('Error processing message: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return 'I apologize, something went wrong. Please try again or type "reset" to start over.';
        }
    }
    
    // =============================================
    // GET OR CREATE SESSION
    // =============================================
    private static Agentforce_Session__c getOrCreateSession(String phoneNumber) {
        
        System.debug(phoneNumber);
        // Look for active session for this phone number
        List<Agentforce_Session__c> existingSessions = [
            SELECT Id, Session_Id__c, Sequence_Id__c, Last_Activity__c, 
                   Phone_Number__c, Status__c
            FROM Agentforce_Session__c
            WHERE Phone_Number__c = :phoneNumber
              AND Status__c = 'Active'
              AND Last_Activity__c > :DateTime.now().addMinutes(-SESSION_TIMEOUT_MINUTES)
            ORDER BY Last_Activity__c DESC
            LIMIT 1
        ];
        System.debug(existingSessions);
        if (!existingSessions.isEmpty()) {
            System.debug('Found existing session: ' + existingSessions[0].Session_Id__c);
            return existingSessions[0];
        }
        
        // Expire any old sessions for this number
        expireOldSessions(phoneNumber);
         System.debug('entering new session');
        // Create new session
        return createNewSession(phoneNumber);
    }
    
    // =============================================
    // CREATE NEW SESSION
    // =============================================
    private static Agentforce_Session__c createNewSession(String phoneNumber) {
        
        // Call Agentforce API to create session
        String sessionId = AgentforceAPIService.createSession();
        System.debug(sessionId);
        // Find related contact
        String contactId = findContactByPhone(phoneNumber);
        
        // Create session record
        Agentforce_Session__c newSession = new Agentforce_Session__c(
            Phone_Number__c = phoneNumber,
            Session_Id__c = sessionId,
            Sequence_Id__c = 0,
            Status__c = 'Active',
            Last_Activity__c = DateTime.now()
            //Contact__c = contactId
        );
        
        insert newSession;
        System.debug('Created new session: ' + sessionId + ' for: ' + phoneNumber);
        
        return newSession;
    }
    
    // =============================================
    // SESSION CLEANUP HELPERS
    // =============================================
    private static void expireOldSessions(String phoneNumber) {
        List<Agentforce_Session__c> oldSessions = [
            SELECT Id, Session_Id__c
            FROM Agentforce_Session__c
            WHERE Phone_Number__c = :phoneNumber
              AND Status__c = 'Active'
        ];
        
        for (Agentforce_Session__c s : oldSessions) {
            s.Status__c = 'Expired';
            // Try to end session on Agentforce side
            try {
                AgentforceAPIService.endSession(s.Session_Id__c);
            } catch (Exception e) {
                // Non-critical, continue
            }
        }
        
        if (!oldSessions.isEmpty()) {
            update oldSessions;
        }
    }
    
    private static void expireSessionRecord(Agentforce_Session__c session) {
        session.Status__c = 'Expired';
        update session;
    }
    
    public static void resetSession(String phoneNumber) {
        expireOldSessions(phoneNumber);
    }
    
    // =============================================
    // FIND CONTACT BY PHONE
    // =============================================
    private static String findContactByPhone(String phoneNumber) {
        // Clean phone number
        String cleanPhone = phoneNumber.replaceAll('[^0-9+]', '');
        
        List<Contact> contacts = [
            SELECT Id 
            FROM Contact 
            WHERE Phone = :cleanPhone 
               OR MobilePhone = :cleanPhone
               OR Phone = :cleanPhone.removeStart('+')
               OR MobilePhone = :cleanPhone.removeStart('+')
            LIMIT 1
        ];
        
        return contacts.isEmpty() ? null : contacts[0].Id;
    }
}