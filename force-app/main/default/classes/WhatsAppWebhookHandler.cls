/**
 * @description REST API endpoint to receive incoming WhatsApp messages (Webhook)
 *              This handles both webhook verification (GET) and message reception (POST)
 *              Endpoint: /services/apexrest/whatsapp/webhook/
 */
//https://orgfarm-fb6e5c4387.my.salesforce-sites.com/whatsappwebhook/services/apexrest/whatsapp/webhook
//GET
//https://orgfarm-fb6e5c4387.my.salesforce-sites.com/whatsappwebhook/services/apexrest/whatsapp/webhook
//POST
//https://orgfarm-fb6e5c4387.my.salesforce-sites.com/whatsappwebhook/services/apexrest/whatsapp/webhook
//curl -X GET "https://yourdomain.my.salesforce-sites.com/whatsappwebhook/services/apexrest/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=YOUR_VERIFY_TOKEN&hub.challenge=test_challenge_123"
@RestResource(urlMapping='/whatsapp/webhook/*')
global without sharing class WhatsAppWebhookHandler {

    /**
     * @description Handle GET request for webhook verification
     *              WhatsApp sends a verification challenge that must be echoed back
     */
    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        WhatsApp_Settings__c settings = WhatsApp_Settings__c.getOrgDefaults();

        String mode = req.params.get('hub.mode');
        String token = req.params.get('hub.verify_token');
        String challenge = req.params.get('hub.challenge');

        System.debug('Webhook Verification - Mode: ' + mode + ', Token: ' + token);

        if (mode == 'subscribe' && token == settings.Verify_Token__c) {
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(challenge);
            res.addHeader('Content-Type', 'text/plain');
            System.debug('Webhook verified successfully');
        } else {
            res.statusCode = 403;
            res.responseBody = Blob.valueOf('Verification failed');
            System.debug('Webhook verification failed');
        }
    }

    /**
     * @description Handle POST request for incoming messages and status updates
     */
    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = req.requestBody.toString();
        System.debug('WhatsApp Webhook Payload: ' + requestBody);

        try {
            //WhatsAppWebhookPayload payload = (WhatsAppWebhookPayload) 
                //JSON.deserialize(requestBody, WhatsAppWebhookPayload.class);
            WhatsAppWebhookPayload payload = WhatsAppPayloadDeserializer.deserialize(requestBody);

            if (payload.entry != null) {
                for (WhatsAppWebhookPayload.Entry entry : payload.entry) {
                    if (entry.changes != null) {
                        for (WhatsAppWebhookPayload.Change change : entry.changes) {
                            if (change.value != null) {
                                processValue(change.value);
                            }
                        }
                    }
                }
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('EVENT_RECEIVED');

        } catch (Exception e) {
            System.debug('Error processing webhook: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            // Still return 200 to prevent WhatsApp from retrying
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('EVENT_RECEIVED');

            // Log the error
            //logError(e, requestBody);
        }
    }

    /**
     * @description Process the value object from the webhook payload
     */
    private static void processValue(WhatsAppWebhookPayload.Value value) {
        // Process incoming messages
        if (value.messages != null && !value.messages.isEmpty()) {
            processIncomingMessages(value);
        }

        // Process status updates (sent, delivered, read)
        if (value.statuses != null && !value.statuses.isEmpty()) {
            processStatusUpdates(value.statuses);
        }
    }

    /**
     * @description Process incoming messages and create records in Salesforce
     */
    private static void processIncomingMessages(WhatsAppWebhookPayload.Value value) {
        List<WhatsApp_Message__c> messagesToInsert = new List<WhatsApp_Message__c>();
         String mediaUrl;

        // Build contact name map from payload
        Map<String, String> contactNameMap = new Map<String, String>();
        if (value.contacts != null) {
            for (WhatsAppWebhookPayload.WAContact contact : value.contacts) {
                if (contact.profile != null) {
                    contactNameMap.put(contact.wa_id, contact.profile.name);
                }
            }
        }

        for (WhatsAppWebhookPayload.Message msg : value.messages) {
            System.debug('msg '+msg);
            
            
            if (msg.type == 'image' && msg.image != null) 
            {
                HttpRequest req = new HttpRequest();
                req.setEndpoint('https://graph.facebook.com/v13.0/'+ msg.image.id);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + 'EAAezSZC4VkZA4BRPgxEkEYOfxYbIYa8yg16hBQK8jCZCEjG23pRx8b4EpHk8w0EFl9Ug1tSWeaPt5ZCnZBICknynJAD69IqWffaQB8vG5ZCLPkSGG1R5RB7FpqZATixSSZCnf5oW1kO3abaumhsbp3gWZBzMO7qaCURAHYDSOhBFvkcKApggaZBnnaNpgTHRrw5DKxkwZDZD');
                req.setTimeout(120000);
                Http http = new Http();
                HttpResponse res = http.send(req);
                System.debug('WhatsApp API Response Status: ' + res.getStatusCode());
                System.debug('WhatsApp API Response Body: ' + res.getBody());
                if(res.getStatusCode() == 200)
                {
                    // Deserialize JSON into a Map
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    mediaUrl = (String) jsonMap.get('url');
                    System.debug('URL: ' + mediaUrl);
                    /*if(mediaUrl != null)
                    {
                        HttpRequest req1 = new HttpRequest();
                        req1.setEndpoint(mediaUrl);
                        req1.setMethod('GET');
                        req1.setHeader('Authorization', 'Bearer ' + 'EAAezSZC4VkZA4BRPgxEkEYOfxYbIYa8yg16hBQK8jCZCEjG23pRx8b4EpHk8w0EFl9Ug1tSWeaPt5ZCnZBICknynJAD69IqWffaQB8vG5ZCLPkSGG1R5RB7FpqZATixSSZCnf5oW1kO3abaumhsbp3gWZBzMO7qaCURAHYDSOhBFvkcKApggaZBnnaNpgTHRrw5DKxkwZDZD');
                        req1.setTimeout(120000);
                        Http http1 = new Http();
                        HttpResponse res1 = http1.send(req1);
                        System.debug('WhatsApp API Response Status res1: ' + res1.getStatusCode());
                        System.debug('WhatsApp API Response Body res1: ' + res1.getBody());
                        System.debug('WhatsApp API Response Body res1: ' + res1.getBodyAsBlob());
                    }*/
                    
                }
                
            }
            
            
            WhatsApp_Message__c waMessage = new WhatsApp_Message__c();
            waMessage.WhatsApp_Message_Id__c = msg.id;
            waMessage.From_Number__c = msg.from_number;
            waMessage.To_Number__c = value.metadata != null ? value.metadata.display_phone_number : '';
            waMessage.Message_Type__c = 'Inbound';
            waMessage.Status__c = 'Received';
            
            // Set timestamp
            if (String.isNotBlank(msg.timestamp)) {
                Long ts = Long.valueOf(msg.timestamp) * 1000;
                waMessage.Timestamp__c = DateTime.newInstance(ts);
            } else {
                waMessage.Timestamp__c = DateTime.now();
            }
            
            // Process message based on type
            if (msg.type == 'text' && msg.text != null) {
                waMessage.Message_Body__c = msg.text.body;
            } else if (msg.type == 'image' && msg.image != null) {
                waMessage.Message_Body__c = msg.image.caption != null ? msg.image.caption : '[Image]';
                //waMessage.Media_URL__c = msg.image.id; // Media ID - need separate API call to download
            } else if (msg.type == 'document' && msg.document != null) {
                waMessage.Message_Body__c = msg.document.caption != null ? msg.document.caption : '[Document: ' + msg.document.filename + ']';
                //waMessage.Media_URL__c = msg.document.id;
            } else if (msg.type == 'video' && msg.video != null) {
                waMessage.Message_Body__c = msg.video.caption != null ? msg.video.caption : '[Video]';
                //waMessage.Media_URL__c = msg.video.id;
            } else if (msg.type == 'audio' && msg.audio != null) {
                waMessage.Message_Body__c = '[Audio Message]';
                //waMessage.Media_URL__c = msg.audio.id;
            } else if (msg.type == 'location' && msg.location != null) {
                waMessage.Message_Body__c = 'Location: ' + msg.location.latitude + ', ' + msg.location.longitude;
                if (msg.location.name != null) {
                    waMessage.Message_Body__c += ' (' + msg.location.name + ')';
                }
            } else if (msg.type == 'interactive' && msg.interactive != null) {
                if (msg.interactive.button_reply != null) {
                    waMessage.Message_Body__c = 'Button Reply: ' + msg.interactive.button_reply.title;
                } else if (msg.interactive.list_reply != null) {
                    waMessage.Message_Body__c = 'List Reply: ' + msg.interactive.list_reply.title;
                }
            } else if (msg.type == 'contacts') {
                waMessage.Message_Body__c = '[Contact Card]';
            } else {
                waMessage.Message_Body__c = '[' + msg.type + ' message]';
            }
            
            // Link to Salesforce Contact
            //waMessage.Contact__c = findOrCreateContact(msg.from_number, contactNameMap.get(msg.from_number));
            
            messagesToInsert.add(waMessage);
            Database.upsert(messagesToInsert, WhatsApp_Message__c.WhatsApp_Message_Id__c, false);
            
            
            
            
            String fromNumber = msg.from_number;
            String bodyMessage;
            if (msg.type == 'text' && msg.text != null) {
                bodyMessage = msg.text.body;
            } 
            if (msg.type == 'image' && msg.image != null && mediaUrl != null) 
            {
                bodyMessage =  mediaUrl;
            }
           
            
            
            
             // Get or create session
            Agentforce_Session__c session =
                AgentforceSessionManager1.getOrCreateSession(fromNumber);
            System.debug('session '+session);

            // Send first-time welcome if sequence is 0
            Boolean isFirstMessage = (session.Sequence_Id__c == 0);
            System.debug('isFirstMessage '+isFirstMessage);
            
            
            // Now chain to Queueable for the CALLOUT
            // Queueable runs in a NEW transaction = no pending DML
            System.enqueueJob(new AgentCalloutQueueable(
                session.Id,
                session.Session_Id__c,
                null,
               (Integer) session.Sequence_Id__c,
                fromNumber,
                bodyMessage,
                'Test User'
            ));
            
            
            

            

            
            
            
            
            
            
            
        }

        /*if (!messagesToInsert.isEmpty()) {
            // Use upsert to avoid duplicates
            Database.upsert(messagesToInsert, WhatsApp_Message__c.WhatsApp_Message_Id__c, false);

            // Auto-reply or trigger automation
            for (WhatsApp_Message__c waMsg : messagesToInsert) {
                processAutoResponse(waMsg);
            }
        }*/
    }

    /**
     * @description Process delivery status updates
     */
    private static void processStatusUpdates(List<WhatsAppWebhookPayload.Status> statuses) {
        Map<String, String> statusMap = new Map<String, String>();

        for (WhatsAppWebhookPayload.Status status : statuses) {
            // Map WhatsApp status to our status values
            String sfStatus;
            switch on status.status {
                when 'sent' {
                    sfStatus = 'Sent';
                }
                when 'delivered' {
                    sfStatus = 'Delivered';
                }
                when 'read' {
                    sfStatus = 'Read';
                }
                when 'failed' {
                    sfStatus = 'Failed';
                }
                when else {
                    sfStatus = status.status;
                }
            }
            statusMap.put(status.id, sfStatus);
        }

        if (!statusMap.isEmpty()) {
            /*List<WhatsApp_Message__c> messagesToUpdate = [
                SELECT Id, WhatsApp_Message_Id__c, Status__c
                FROM WhatsApp_Message__c
                WHERE WhatsApp_Message_Id__c IN :statusMap.keySet()
            ];

            for (WhatsApp_Message__c msg : messagesToUpdate) {
                msg.Status__c = statusMap.get(msg.WhatsApp_Message_Id__c);
            }

            if (!messagesToUpdate.isEmpty()) {
                update messagesToUpdate;
            }
        }*/
    }
    }

    /**
     * @description Find existing contact or create a new one
     */
    /*public static Id findOrCreateContact(String phone, String profileName) {
        String cleanPhone = phone.replace('+', '').replace(' ', '').replace('-', '');

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE Phone LIKE :('%' + cleanPhone.right(10))
               OR MobilePhone LIKE :('%' + cleanPhone.right(10))
            LIMIT 1
        ];

        if (!contacts.isEmpty()) {
            return contacts[0].Id;
        }

        // Create new Contact
        Contact newContact = new Contact();
        newContact.MobilePhone = '+' + cleanPhone;

        if (String.isNotBlank(profileName)) {
            List<String> nameParts = profileName.split(' ', 2);
            newContact.FirstName = nameParts[0];
            newContact.LastName = nameParts.size() > 1 ? nameParts[1] : nameParts[0];
        } else {
            newContact.LastName = 'WhatsApp User ' + cleanPhone.right(4);
        }

        newContact.LeadSource = 'WhatsApp';

        try {
            insert newContact;
            return newContact.Id;
        } catch (Exception e) {
            System.debug('Error creating contact: ' + e.getMessage());
            return null;
        }
    }*/

    /**
     * @description Process auto-response based on incoming message
     */
   /* private static void processAutoResponse(WhatsApp_Message__c incomingMessage) {
        // Example: Auto-acknowledge receipt
        // This runs in a future method to avoid callout-from-trigger issues
        if (incomingMessage.Message_Body__c != null) {
            String msgBody = incomingMessage.Message_Body__c.toLowerCase().trim();

            // Simple keyword-based auto-response
            if (msgBody == 'hi' || msgBody == 'hello' || msgBody == 'hey') {
                sendAutoReply(
                    incomingMessage.From_Number__c,
                    'Hello! 👋 Welcome to our service. How can we help you today?\n\n'
                    + '1️⃣ Product Information\n'
                    + '2️⃣ Order Status\n'
                    + '3️⃣ Support\n'
                    + '4️⃣ Talk to an Agent'
                );
            } else if (msgBody == '1') {
                sendAutoReply(
                    incomingMessage.From_Number__c,
                    'Please visit our website for product information: https://yourwebsite.com'
                );
            } else if (msgBody == '4') {
                sendAutoReply(
                    incomingMessage.From_Number__c,
                    'An agent will be with you shortly. Thank you for your patience! 🙏'
                );
                // Create a Case for the agent
                createSupportCase(incomingMessage);
            }
        }
    }*/

    /**
     * @description Send auto-reply via future method
     */
   /* @future(callout=true)
    private static void sendAutoReply(String toPhone, String messageBody) {
        try {
            WhatsAppService.sendTextMessage(toPhone, messageBody);
        } catch (Exception e) {
            System.debug('Error sending auto-reply: ' + e.getMessage());
        }
    }*/

    /**
     * @description Create a support case from WhatsApp message
     */
    /*private static void createSupportCase(WhatsApp_Message__c message) {
        Case supportCase = new Case();
        supportCase.Subject = 'WhatsApp Support Request from ' + message.From_Number__c;
        supportCase.Description = 'Customer reached out via WhatsApp.\n\nMessage: ' + message.Message_Body__c;
        supportCase.Origin = 'WhatsApp';
        supportCase.Status = 'New';
        supportCase.Priority = 'Medium';

        if (message.Contact__c != null) {
            supportCase.ContactId = message.Contact__c;
        }

        try {
            insert supportCase;
        } catch (Exception e) {
            System.debug('Error creating case: ' + e.getMessage());
        }
    }*/

    /**
     * @description Log errors for debugging
     */
    /*private static void logError(Exception e, String payload) {
        // You can create a custom error log object or use Platform Events
        System.debug(LoggingLevel.ERROR, 'WhatsApp Webhook Error: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
        System.debug(LoggingLevel.ERROR, 'Payload: ' + payload);
    }*/
    
    private static String retryWithNewSession(
        String phoneNumber,
        Agentforce_Session__c oldSession,
        String messageBody
    ) {
        try {
            // Expire old session
            oldSession.Status__c = 'Expired';
            update oldSession;

            // Create fresh session
            Agentforce_Session__c newSession =
                AgentforceSessionManager1.getOrCreateSession(phoneNumber);

            // Retry agent call
            AgentforceInvocableService.AgentResponse retryResult =
                AgentforceInvocableService.callAgent(
                    newSession.Session_Id__c,
                    messageBody,
                    phoneNumber,
                   null,
                    1
                );

            if (retryResult.success && String.isNotBlank(retryResult.message)) {
                return retryResult.message;
            }

        } catch (Exception e) {
            System.debug('Retry failed: ' + e.getMessage());
        }

        return 'Something went wrong';
    }

}