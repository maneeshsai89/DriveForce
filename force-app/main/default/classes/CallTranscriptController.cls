/**
 * Apex controller for voice call transcript LWCs.
 * Resolves ConversationEntry turns from a VoiceCall or Conversation record,
 * and loads related VoiceCallRecording rows (audio) when available.
 */
public with sharing class CallTranscriptController {

    @AuraEnabled(cacheable=true)
    public static TranscriptResult getTranscript(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        Id conversationId = resolveConversationId(recordId);
        Id voiceCallId = resolveVoiceCallId(recordId, conversationId);

        VoiceCallSummary callSummary = loadVoiceCallSummary(voiceCallId);
        List<RecordingInfo> recordings = loadRecordings(voiceCallId);

        Conversation conv;
        if (conversationId != null) {
            List<Conversation> convList = [
                SELECT Id, StartTime, EndTime, ConversationIdentifier
                FROM Conversation
                WHERE Id = :conversationId
                LIMIT 1
            ];
            conv = convList.isEmpty() ? null : convList[0];
        }

        // Entries often key ConversationId to VoiceCall.Id; unified Conversation uses ConversationEntityId on some orgs.
        List<TranscriptEntry> turns = buildTranscriptEntries(conversationId, voiceCallId);

        return new TranscriptResult(conv, turns, callSummary, recordings);
    }

    /**
     * Platform ConversationEntry uses Message; enhanced channels may use EntryPayload / EntryContents JSON.
     * ConversationId is polymorphic (VoiceCall, MessagingSession, etc.); VoiceCall.ConversationId points at Conversation,
     * but transcript rows frequently use ConversationId = VoiceCall.Id — query both plus ConversationEntityId when present.
     */
    private static List<TranscriptEntry> buildTranscriptEntries(Id conversationRecordId, Id voiceCallId) {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.ConversationEntry.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'ActorType', 'ActorName', 'EntryType' };

        String orderField;
        if (fm.containsKey('ClientTimestamp')) {
            selectFields.add('ClientTimestamp');
            orderField = 'ClientTimestamp';
        } else if (fm.containsKey('ServerReceivedTimestamp')) {
            selectFields.add('ServerReceivedTimestamp');
            orderField = 'ServerReceivedTimestamp';
        } else {
            selectFields.add('EntryTime');
            orderField = 'EntryTime';
        }

        List<String> textFieldNames = new List<String>();
        for (String tf : new List<String>{ 'Message', 'EntryPayload', 'EntryContents' }) {
            if (fm.containsKey(tf)) {
                selectFields.add(tf);
                textFieldNames.add(tf);
            }
        }

        for (String opt : new List<String>{ 'MessageType', 'RelatedRecordId', 'Sender', 'ClientMessageIdentifier' }) {
            if (fm.containsKey(opt)) {
                selectFields.add(opt);
            }
        }

        List<Id> conversationIdIn = new List<Id>();
        if (conversationRecordId != null) {
            conversationIdIn.add(conversationRecordId);
        }
        if (voiceCallId != null && (conversationRecordId == null || voiceCallId != conversationRecordId)) {
            conversationIdIn.add(voiceCallId);
        }

        List<String> orPredicates = new List<String>();
        if (!conversationIdIn.isEmpty()) {
            orPredicates.add('ConversationId IN :conversationIdIn');
        }
        if (conversationRecordId != null && fm.containsKey('ConversationEntityId')) {
            orPredicates.add('ConversationEntityId = :conversationRecordId');
        }
        if (orPredicates.isEmpty()) {
            return new List<TranscriptEntry>();
        }

        String whereClause = '(' + String.join(orPredicates, ' OR ') + ')';
        String soql =
            'SELECT ' +
            String.join(selectFields, ',') +
            ' FROM ConversationEntry WHERE ' +
            whereClause +
            ' ORDER BY ' +
            orderField +
            ' ASC NULLS LAST LIMIT 2000';

        List<SObject> rows = Database.query(soql);
        List<TranscriptEntry> turns = new List<TranscriptEntry>();
        Set<Id> seenIds = new Set<Id>();
        for (SObject row : rows) {
            Id rowId = (Id) row.get('Id');
            if (rowId != null && seenIds.contains(rowId)) {
                continue;
            }
            if (rowId != null) {
                seenIds.add(rowId);
            }
            String text = extractTextFromRow(row, textFieldNames);
            if (String.isBlank(text)) {
                continue;
            }
            TranscriptEntry t = new TranscriptEntry();
            t.id = String.valueOf(row.get('Id'));
            String actorName = (String) row.get('ActorName');
            String actorType = (String) row.get('ActorType');
            t.speaker = String.isNotBlank(actorName) ? actorName : actorType;
            t.actorType = actorType;
            t.timestamp = (Datetime) row.get(orderField);
            t.text = text;
            turns.add(t);
        }
        return turns;
    }

    private static String extractTextFromRow(SObject row, List<String> textFieldNames) {
        for (String fn : textFieldNames) {
            String raw = (String) row.get(fn);
            String t = extractText(raw);
            if (String.isNotBlank(t)) {
                return t;
            }
        }
        return null;
    }

    private static Id resolveConversationId(Id recordId) {
        String prefix = String.valueOf(recordId).substring(0, 3);
        Schema.DescribeSObjectResult convDescribe = Conversation.SObjectType.getDescribe();
        if (prefix == convDescribe.getKeyPrefix()) {
            return recordId;
        }

        List<VoiceCall> calls = [
            SELECT Id, ConversationId
            FROM VoiceCall
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (!calls.isEmpty() && calls[0].ConversationId != null) {
            return calls[0].ConversationId;
        }
        return null;
    }

    /**
     * VoiceCall Id when record page is VoiceCall; otherwise first VoiceCall for the Conversation.
     */
    private static Id resolveVoiceCallId(Id recordId, Id conversationId) {
        String prefix = String.valueOf(recordId).substring(0, 3);
        Schema.DescribeSObjectResult vcDescribe = VoiceCall.SObjectType.getDescribe();
        if (prefix == vcDescribe.getKeyPrefix()) {
            return recordId;
        }
        if (conversationId == null) {
            return null;
        }
        List<VoiceCall> vcs = [
            SELECT Id
            FROM VoiceCall
            WHERE ConversationId = :conversationId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return vcs.isEmpty() ? null : vcs[0].Id;
    }

    private static VoiceCallSummary loadVoiceCallSummary(Id voiceCallId) {
        if (voiceCallId == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.VoiceCall.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'ConversationId' };
        if (fieldMap.containsKey('CallStartDateTime')) {
            selectFields.add('CallStartDateTime');
        }
        if (fieldMap.containsKey('CallEndDateTime')) {
            selectFields.add('CallEndDateTime');
        }
        if (fieldMap.containsKey('FromPhoneNumber')) {
            selectFields.add('FromPhoneNumber');
        }
        if (fieldMap.containsKey('ToPhoneNumber')) {
            selectFields.add('ToPhoneNumber');
        }
        String soql =
            'SELECT ' +
            String.join(selectFields, ',') +
            ' FROM VoiceCall WHERE Id = :voiceCallId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) {
            return null;
        }
        SObject vc = rows[0];
        VoiceCallSummary s = new VoiceCallSummary();
        s.id = (Id) vc.get('Id');
        s.conversationId = (Id) vc.get('ConversationId');
        if (fieldMap.containsKey('CallStartDateTime')) {
            s.callStart = (Datetime) vc.get('CallStartDateTime');
        }
        if (fieldMap.containsKey('CallEndDateTime')) {
            s.callEnd = (Datetime) vc.get('CallEndDateTime');
        }
        if (fieldMap.containsKey('FromPhoneNumber')) {
            s.fromPhone = (String) vc.get('FromPhoneNumber');
        }
        if (fieldMap.containsKey('ToPhoneNumber')) {
            s.toPhone = (String) vc.get('ToPhoneNumber');
        }
        return s;
    }

    private static List<RecordingInfo> loadRecordings(Id voiceCallId) {
        List<RecordingInfo> out = new List<RecordingInfo>();
        if (voiceCallId == null) {
            return out;
        }
        if (!Schema.getGlobalDescribe().containsKey('VoiceCallRecording')) {
            return out;
        }
        String q =
            'SELECT Id, Name, VoiceCallId, MediaContentId, DurationInSeconds, UploadDateTime ' +
            'FROM VoiceCallRecording WHERE VoiceCallId = :voiceCallId ' +
            'ORDER BY UploadDateTime ASC LIMIT 50';
        for (SObject row : Database.query(q)) {
            RecordingInfo r = new RecordingInfo();
            r.id = (Id) row.get('Id');
            r.name = (String) row.get('Name');
            r.voiceCallId = (Id) row.get('VoiceCallId');
            r.mediaContentId = (Id) row.get('MediaContentId');
            Object dur = row.get('DurationInSeconds');
            r.durationSeconds = dur == null ? null : (Decimal) dur;
            r.uploadedAt = (Datetime) row.get('UploadDateTime');
            out.add(r);
        }
        return out;
    }

    private static String extractText(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String trimmed = raw.trim();
        try {
            Object parsed = JSON.deserializeUntyped(trimmed);
            String fromJson = extractTextFromJsonValue(parsed, 0);
            if (String.isNotBlank(fromJson)) {
                return fromJson;
            }
        } catch (Exception e) {
            return trimmed;
        }
        return null;
    }

    private static final Integer MAX_JSON_DEPTH = 12;

    private static String extractTextFromJsonValue(Object val, Integer depth) {
        if (val == null || depth > MAX_JSON_DEPTH) {
            return null;
        }
        if (val instanceof String) {
            String s = (String) val;
            return String.isBlank(s) ? null : s;
        }
        if (val instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object o : (List<Object>) val) {
                String p = extractTextFromJsonValue(o, depth + 1);
                if (String.isNotBlank(p)) {
                    parts.add(p);
                }
            }
            return parts.isEmpty() ? null : String.join(parts, ' ');
        }
        if (val instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) val;
            for (
                String key : new List<String>{
                    'text',
                    'body',
                    'content',
                    'transcript',
                    'value',
                    'utterance',
                    'displayText'
                }
            ) {
                if (m.containsKey(key)) {
                    String p = extractTextFromJsonValue(m.get(key), depth + 1);
                    if (String.isNotBlank(p)) {
                        return p;
                    }
                }
            }
            for (String key : new List<String>{ 'abstractMessage', 'staticContent', 'message', 'payload' }) {
                if (m.containsKey(key)) {
                    String p = extractTextFromJsonValue(m.get(key), depth + 1);
                    if (String.isNotBlank(p)) {
                        return p;
                    }
                }
            }
            for (Object o : m.values()) {
                if (o instanceof String || o instanceof Map<String, Object> || o instanceof List<Object>) {
                    String p = extractTextFromJsonValue(o, depth + 1);
                    if (String.isNotBlank(p)) {
                        return p;
                    }
                }
            }
        }
        return null;
    }

    public class TranscriptResult {
        @AuraEnabled public Conversation conversation;
        @AuraEnabled public List<TranscriptEntry> entries;
        @AuraEnabled public VoiceCallSummary voiceCall;
        @AuraEnabled public List<RecordingInfo> recordings;

        public TranscriptResult(
            Conversation c,
            List<TranscriptEntry> e,
            VoiceCallSummary vc,
            List<RecordingInfo> recs
        ) {
            this.conversation = c;
            this.entries = e;
            this.voiceCall = vc;
            this.recordings = recs;
        }
    }

    public class TranscriptEntry {
        @AuraEnabled public String id;
        @AuraEnabled public String speaker;
        @AuraEnabled public String actorType;
        @AuraEnabled public Datetime timestamp;
        @AuraEnabled public String text;
    }

    public class VoiceCallSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public Id conversationId;
        @AuraEnabled public Datetime callStart;
        @AuraEnabled public Datetime callEnd;
        @AuraEnabled public String fromPhone;
        @AuraEnabled public String toPhone;
    }

    public class RecordingInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public Id voiceCallId;
        @AuraEnabled public Id mediaContentId;
        @AuraEnabled public Decimal durationSeconds;
        @AuraEnabled public Datetime uploadedAt;
        @AuraEnabled public String name;
    }
}