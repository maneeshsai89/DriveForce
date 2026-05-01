/**
 * @description Wrapper class to deserialize WhatsApp webhook payload
 */
public class WhatsAppWebhookPayload {

    public String object_x; // 'whatsapp_business_account'
    public List<Entry> entry;

    public class Entry {
        public String id;
        public List<Change> changes;
    }

    public class Change {
        public String field;
        public Value value;
    }

    public class Value {
        public String messaging_product;
        public Metadata metadata;
        public List<WAContact> contacts;
        public List<Message> messages;
        public List<Status> statuses;
        public List<Error> errors;
    }

    public class Metadata {
        public String display_phone_number;
        public String phone_number_id;
    }

    public class WAContact {
        public Profile profile;
        public String wa_id;
    }

    public class Profile {
        public String name;
    }

    public class Message {
        public String id;
        public String from_number; // mapped from 'from' since 'from' is reserved
        public String timestamp;
        public String type;
        public TextMessage text;
        public ImageMessage image;
        public DocumentMessage document;
        public VideoMessage video;
        public AudioMessage audio;
        public LocationMessage location;
        public InteractiveMessage interactive;
        public ContextInfo context;
    }

    public class TextMessage {
        public String body;
    }

    public class ImageMessage {
        public String id;
        public String mime_type;
        public String sha256;
        public String caption;
    }

    public class DocumentMessage {
        public String id;
        public String mime_type;
        public String sha256;
        public String filename;
        public String caption;
    }

    public class VideoMessage {
        public String id;
        public String mime_type;
        public String sha256;
        public String caption;
    }

    public class AudioMessage {
        public String id;
        public String mime_type;
        public String sha256;
        public Boolean voice;
    }

    public class LocationMessage {
        public Decimal latitude;
        public Decimal longitude;
        public String name;
        public String address;
    }

    public class InteractiveMessage {
        public String type;
        public ButtonReply button_reply;
        public ListReply list_reply;
    }

    public class ButtonReply {
        public String id;
        public String title;
    }

    public class ListReply {
        public String id;
        public String title;
        public String description;
    }

    public class ContextInfo {
        public String message_id;
        public String from_number;
    }

    public class Status {
        public String id;
        public String status;
        public String timestamp;
        public String recipient_id;
        public Conversation conversation;
        public Pricing pricing;
        public List<Error> errors;
    }

    public class Conversation {
        public String id;
        public Origin origin;
    }

    public class Origin {
        public String type;
    }

    public class Pricing {
        public Boolean billable;
        public String pricing_model;
        public String category;
    }

    public class Error {
        public Integer code;
        public String title;
        public String message;
        public String error_data;
    }
}