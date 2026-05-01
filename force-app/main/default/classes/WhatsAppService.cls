/**
 * @description Service class to send messages from Salesforce to WhatsApp
 *              using the WhatsApp Cloud API (Meta Business Platform)
 */
public class WhatsAppService {

    private static WhatsApp_Settings__c settings = WhatsApp_Settings__c.getOrgDefaults();

    private static final String BASE_URL = 'https://graph.facebook.com/' 
        + settings.API_Version__c + '/' 
        + settings.Phone_Number_Id__c;

    /**
     * @description Send a text message via WhatsApp
     * @param toPhone Recipient phone number (with country code, e.g., +1234567890)
     * @param messageBody Text message content
     * @return WhatsApp_Message__c record
     */
    public static void sendTextMessage(String toPhone, String messageBody) {
        
        // Build request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'recipient_type' => 'individual',
            'to' => toPhone.replace('+', ''),
            'type' => 'text',
            'text' => new Map<String, Object>{
                'preview_url' => false,
                'body' => messageBody
            }
        };

        HttpResponse response = makeCallout(JSON.serialize(requestBody), '/messages');
        System.debug(response);

        // Process response
        /*WhatsApp_Message__c msg = new WhatsApp_Message__c();
        msg.To_Number__c = toPhone;
        msg.From_Number__c = settings.Phone_Number_Id__c;
        msg.Message_Body__c = messageBody;
        msg.Message_Type__c = 'Outbound';
        msg.Timestamp__c = DateTime.now();

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messages = (List<Object>) responseMap.get('messages');
            if (messages != null && !messages.isEmpty()) {
                Map<String, Object> messageData = (Map<String, Object>) messages[0];
                msg.WhatsApp_Message_Id__c = (String) messageData.get('id');
            }
            msg.Status__c = 'Sent';
        } else {
            msg.Status__c = 'Failed';
            System.debug('WhatsApp API Error: ' + response.getBody());
        }

        // Link to Contact if exists
        msg.Contact__c = findContactByPhone(toPhone);

        insert msg;
        return msg;*/
    }

    /**
     * @description Send a template message via WhatsApp
     * @param toPhone Recipient phone number
     * @param templateName Template name configured in WhatsApp Business Manager
     * @param languageCode Language code (e.g., 'en_US')
     * @param parameters List of parameter values for the template
     * @return WhatsApp_Message__c record
     */
    public static void sendTemplateMessage(
        String toPhone, 
        String templateName, 
        String languageCode, 
        List<String> parameters
    ) {
        // Build components with parameters
        List<Object> componentParams = new List<Object>();
        if (parameters != null) {
            for (String param : parameters) {
                componentParams.add(new Map<String, Object>{
                    'type' => 'text',
                    'text' => param
                });
            }
        }

        List<Object> components = new List<Object>();
        if (!componentParams.isEmpty()) {
            components.add(new Map<String, Object>{
                'type' => 'body',
                'parameters' => componentParams
            });
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'to' => toPhone.replace('+', ''),
            'type' => 'template',
            'template' => new Map<String, Object>{
                'name' => templateName,
                'language' => new Map<String, Object>{
                    'code' => languageCode
                },
                'components' => components
            }
        };

        HttpResponse response = makeCallout(JSON.serialize(requestBody), '/messages');

        /*WhatsApp_Message__c msg = new WhatsApp_Message__c();
        msg.To_Number__c = toPhone;
        msg.From_Number__c = settings.Phone_Number_Id__c;
        msg.Message_Body__c = 'Template: ' + templateName;
        msg.Message_Type__c = 'Outbound';
        msg.Timestamp__c = DateTime.now();

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messages = (List<Object>) responseMap.get('messages');
            if (messages != null && !messages.isEmpty()) {
                Map<String, Object> messageData = (Map<String, Object>) messages[0];
                msg.WhatsApp_Message_Id__c = (String) messageData.get('id');
            }
            msg.Status__c = 'Sent';
        } else {
            msg.Status__c = 'Failed';
            System.debug('WhatsApp Template API Error: ' + response.getBody());
        }

        msg.Contact__c = findContactByPhone(toPhone);
        insert msg;
        return msg;*/
    }

    /**
     * @description Send a media message (image, document, video) via WhatsApp
     * @param toPhone Recipient phone number
     * @param mediaType Type of media (image, document, video, audio)
     * @param mediaUrl Public URL of the media
     * @param caption Optional caption for the media
     * @return WhatsApp_Message__c record
     */
    public static void sendMediaMessage(
        String toPhone, 
        String mediaType, 
        String mediaUrl, 
        String caption
    ) {
        Map<String, Object> mediaObject = new Map<String, Object>{
            'link' => mediaUrl
        };
        if (String.isNotBlank(caption)) {
            mediaObject.put('caption', caption);
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'to' => toPhone.replace('+', ''),
            'type' => mediaType,
            mediaType => mediaObject
        };

        HttpResponse response = makeCallout(JSON.serialize(requestBody), '/messages');

        /*WhatsApp_Message__c msg = new WhatsApp_Message__c();
        msg.To_Number__c = toPhone;
        msg.From_Number__c = settings.Phone_Number_Id__c;
        msg.Message_Body__c = caption != null ? caption : mediaType + ' message';
        msg.Media_URL__c = mediaUrl;
        msg.Message_Type__c = 'Outbound';
        msg.Timestamp__c = DateTime.now();

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messages = (List<Object>) responseMap.get('messages');
            if (messages != null && !messages.isEmpty()) {
                Map<String, Object> messageData = (Map<String, Object>) messages[0];
                msg.WhatsApp_Message_Id__c = (String) messageData.get('id');
            }
            msg.Status__c = 'Sent';
        } else {
            msg.Status__c = 'Failed';
        }

        msg.Contact__c = findContactByPhone(toPhone);
        insert msg;
        return msg;*/
    }

    /**
     * @description Send an interactive button message
     * @param toPhone Recipient phone number
     * @param bodyText Message body
     * @param buttons List of button maps with 'id' and 'title' keys
     * @return WhatsApp_Message__c record
     */
    public static void sendInteractiveButtonMessage(
        String toPhone, 
        String bodyText, 
        List<Map<String, String>> buttons
    ) {
        List<Object> buttonList = new List<Object>();
        for (Map<String, String> btn : buttons) {
            buttonList.add(new Map<String, Object>{
                'type' => 'reply',
                'reply' => new Map<String, Object>{
                    'id' => btn.get('id'),
                    'title' => btn.get('title')
                }
            });
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'to' => toPhone.replace('+', ''),
            'type' => 'interactive',
            'interactive' => new Map<String, Object>{
                'type' => 'button',
                'body' => new Map<String, Object>{
                    'text' => bodyText
                },
                'action' => new Map<String, Object>{
                    'buttons' => buttonList
                }
            }
        };

        HttpResponse response = makeCallout(JSON.serialize(requestBody), '/messages');

        /*WhatsApp_Message__c msg = new WhatsApp_Message__c();
        msg.To_Number__c = toPhone;
        msg.From_Number__c = settings.Phone_Number_Id__c;
        msg.Message_Body__c = bodyText;
        msg.Message_Type__c = 'Outbound';
        msg.Timestamp__c = DateTime.now();

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            msg.Status__c = 'Sent';
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> messages = (List<Object>) responseMap.get('messages');
            if (messages != null && !messages.isEmpty()) {
                Map<String, Object> messageData = (Map<String, Object>) messages[0];
                msg.WhatsApp_Message_Id__c = (String) messageData.get('id');
            }
        } else {
            msg.Status__c = 'Failed';
        }

        msg.Contact__c = findContactByPhone(toPhone);
        insert msg;
        return msg;*/
    }

    /**
     * @description Mark a message as read
     * @param messageId WhatsApp message ID to mark as read
     */
    public static void markAsRead(String messageId) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'messaging_product' => 'whatsapp',
            'status' => 'read',
            'message_id' => messageId
        };

        makeCallout(JSON.serialize(requestBody), '/messages');
    }

    /**
     * @description Helper method to make HTTP callout to WhatsApp API
     */
    private static HttpResponse makeCallout(String body, String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + 'EAAezSZC4VkZA4BRPgxEkEYOfxYbIYa8yg16hBQK8jCZCEjG23pRx8b4EpHk8w0EFl9Ug1tSWeaPt5ZCnZBICknynJAD69IqWffaQB8vG5ZCLPkSGG1R5RB7FpqZATixSSZCnf5oW1kO3abaumhsbp3gWZBzMO7qaCURAHYDSOhBFvkcKApggaZBnnaNpgTHRrw5DKxkwZDZD');
        req.setBody(body);
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('WhatsApp API Response Status: ' + res.getStatusCode());
        System.debug('WhatsApp API Response Body: ' + res.getBody());

        return res;
    }

    /**
     * @description Find Contact by phone number
     */
    private static Id findContactByPhone(String phone) {
        String cleanPhone = phone.replace('+', '').replace(' ', '').replace('-', '');
        
        List<Contact> contacts = [
            SELECT Id 
            FROM Contact 
            WHERE Phone LIKE :('%' + cleanPhone.right(10))
               OR MobilePhone LIKE :('%' + cleanPhone.right(10))
            LIMIT 1
        ];
        
        return contacts.isEmpty() ? null : contacts[0].Id;
    }
}