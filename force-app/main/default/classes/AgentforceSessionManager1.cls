public class AgentforceSessionManager1 {

    // =============================================
    // GET OR CREATE SESSION FOR A PHONE NUMBER
    // =============================================
    public static Agentforce_Session__c getOrCreateSession(String phoneNumber) {

        Integer timeout = 30;

        // 1. Find existing active session
        List<Agentforce_Session__c> existing = [
            SELECT Id, Session_Id__c, Sequence_Id__c,
                   Last_Activity__c,
                   Phone_Number__c, Status__c
            FROM Agentforce_Session__c
            WHERE Phone_Number__c = :phoneNumber
              AND Status__c = 'Active'
              AND Last_Activity__c > :DateTime.now().addMinutes(-timeout)
            ORDER BY Last_Activity__c DESC
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            System.debug('Reusing session: ' + existing[0].Session_Id__c);
            return existing[0];
        }

        // 2. Expire old sessions
        expireOldSessions(phoneNumber);

        // 3. Create new session
        return createNewSession(phoneNumber);
    }

    // =============================================
    // CREATE NEW SESSION
    // =============================================
    private static Agentforce_Session__c createNewSession(String phoneNumber) {

        String sessionId = generateSessionId();
        String contactId = findContactByPhone(phoneNumber);

        Agentforce_Session__c session = new Agentforce_Session__c(
            Phone_Number__c = phoneNumber,
            Session_Id__c = sessionId,
            Sequence_Id__c = 0,
            Status__c = 'Active',
            Last_Activity__c = DateTime.now()
        );

        insert session;
        System.debug('New session created: ' + sessionId + ' for: ' + phoneNumber);
        return session;
    }

    // =============================================
    // UPDATE SESSION AFTER MESSAGE
    // =============================================
    public static void updateSession(
        Agentforce_Session__c session,
        String userMessage,
        String agentResponse
    ) {
        session.Sequence_Id__c = session.Sequence_Id__c + 1;
        session.Last_Activity__c = DateTime.now();

        // Append to conversation log
        String logEntry = '\n[' + DateTime.now().format('HH:mm:ss') + '] User: ' +
            userMessage + '\n[' + DateTime.now().format('HH:mm:ss') + '] Agent: ' +
            agentResponse;

        

        update session;
    }

    // =============================================
    // EXPIRE OLD SESSIONS
    // =============================================
    public static void expireOldSessions(String phoneNumber) {
        List<Agentforce_Session__c> oldSessions = [
            SELECT Id, Session_Id__c
            FROM Agentforce_Session__c
            WHERE Phone_Number__c = :phoneNumber
              AND Status__c = 'Active'
        ];

        for (Agentforce_Session__c s : oldSessions) {
            s.Status__c = 'Expired';
        }

        if (!oldSessions.isEmpty()) {
            update oldSessions;
        }
    }

    // =============================================
    // RESET SESSION (User typed "reset")
    // =============================================
    public static void resetSession(String phoneNumber) {
        expireOldSessions(phoneNumber);
        System.debug('Session reset for: ' + phoneNumber);
    }

    // =============================================
    // FIND CONTACT BY PHONE
    // =============================================
    private static String findContactByPhone(String phoneNumber) {
        String cleanPhone = phoneNumber.replaceAll('[^0-9+]', '');
        String phoneWithoutPlus = cleanPhone.removeStart('+');

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE Phone = :cleanPhone
               OR MobilePhone = :cleanPhone
               OR Phone = :phoneWithoutPlus
               OR MobilePhone = :phoneWithoutPlus
            LIMIT 1
        ];

        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    // =============================================
    // GENERATE UNIQUE SESSION ID
    // =============================================
    private static String generateSessionId() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return 'WA-' + h.substring(0, 8) + '-' +
               h.substring(8, 12) + '-' +
               h.substring(12, 16) + '-' +
               h.substring(16, 20) + '-' +
               h.substring(20, 32);
    }
}