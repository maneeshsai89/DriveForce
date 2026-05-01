/**
 * @description Custom deserializer for WhatsApp payload
 *              because 'from' is a reserved keyword in Apex
 */
public class WhatsAppPayloadDeserializer {

    /**
     * @description Deserialize the raw JSON replacing reserved keywords
     */
    public static WhatsAppWebhookPayload deserialize(String jsonBody) {
        // Replace 'from' key with 'from_number' to avoid Apex reserved keyword
        String sanitized = jsonBody.replace('"from":', '"from_number":');
        // Replace 'object' key (also reserved)
        sanitized = sanitized.replace('"object":', '"object_x":');

        return (WhatsAppWebhookPayload) JSON.deserialize(
            sanitized, WhatsAppWebhookPayload.class
        );
    }
}