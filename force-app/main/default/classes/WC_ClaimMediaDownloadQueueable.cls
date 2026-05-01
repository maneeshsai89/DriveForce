/**
 * WC — Async GET on WhatsApp/Meta media URL (Bearer token), then saves binary as a Salesforce File on the Claim.
 * Runs as Queueable because callouts are not allowed after DML in the same transaction as {@link WC_CreateClaimIntakeWithAttachmentAction}.
 */
public without sharing class WC_ClaimMediaDownloadQueueable implements Queueable, Database.AllowsCallouts {
    /** Hard-coded per product owner request; rotate if leaked and prefer Named Credential for production. */
    private static final String WHATSAPP_MEDIA_BEARER_TOKEN =
        'EAAezSZC4VkZA4BRPgxEkEYOfxYbIYa8yg16hBQK8jCZCEjG23pRx8b4EpHk8w0EFl9Ug1tSWeaPt5ZCnZBICknynJAD69IqWffaQB8vG5ZCLPkSGG1R5RB7FpqZATixSSZCnf5oW1kO3abaumhsbp3gWZBzMO7qaCURAHYDSOhBFvkcKApggaZBnnaNpgTHRrw5DKxkwZDZD';

    private static final Integer MAX_MEDIA_BYTES = 10485760;
    private static final Integer CALLOUT_TIMEOUT_MS = 120000;

    private final Id claimId;
    private final String mediaUrl;
    private final String attachmentFileName;

    public WC_ClaimMediaDownloadQueueable(Id claimId, String mediaUrl, String attachmentFileName) {
        this.claimId = claimId;
        this.mediaUrl = mediaUrl;
        this.attachmentFileName = attachmentFileName;
    }

    public void execute(QueueableContext context) {
        if (claimId == null || String.isBlank(mediaUrl)) {
            System.debug(LoggingLevel.WARN, 'WC_ClaimMediaDownload skip: missing claimId or mediaUrl');
            return;
        }
        String endpoint = mediaUrl.trim();
        if (!endpoint.toLowerCase().startsWith('https://')) {
            System.debug(LoggingLevel.ERROR, 'WC_ClaimMediaDownload reject non-HTTPS URL');
            return;
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + WHATSAPP_MEDIA_BEARER_TOKEN);
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res = new Http().send(req);
            System.debug(LoggingLevel.DEBUG, 'WC_ClaimMediaDownload HTTP ' + res.getStatusCode());
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                System.debug(
                    LoggingLevel.WARN,
                    'WC_ClaimMediaDownload failed status=' +
                        res.getStatusCode() +
                        ' bodySnippet=' +
                        truncate(res.getBody(), 500)
                );
                return;
            }

            Blob binary = res.getBodyAsBlob();
            if (binary == null || binary.size() == 0) {
                System.debug(LoggingLevel.WARN, 'WC_ClaimMediaDownload empty body');
                return;
            }
            if (binary.size() > MAX_MEDIA_BYTES) {
                System.debug(
                    LoggingLevel.WARN,
                    'WC_ClaimMediaDownload too large bytes=' + binary.size()
                );
                return;
            }

            String pathOnClient = sanitizeFileName(
                String.isNotBlank(attachmentFileName) ? attachmentFileName : 'WC_Claim_Intake_Media.jpg'
            );
            ContentVersion cv = new ContentVersion();
            cv.Title = pathOnClient.contains('.') ? pathOnClient.substringBeforeLast('.') : pathOnClient;
            cv.PathOnClient = pathOnClient;
            cv.VersionData = binary;
            cv.FirstPublishLocationId = claimId;
            cv.IsMajorVersion = true;

            Database.SaveResult sr = Database.insert(cv, false, AccessLevel.SYSTEM_MODE);
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'WC_ClaimMediaDownload ContentVersion DML ' + err.getStatusCode() + ' ' + err.getMessage()
                    );
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_ClaimMediaDownload exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e);
        }
    }

    private static String sanitizeFileName(String raw) {
        if (String.isBlank(raw)) {
            return 'WC_Claim_Intake_Media.jpg';
        }
        String name = raw.trim().replace('\\', '/');
        if (name.contains('/')) {
            name = name.substringAfterLast('/');
        }
        name = name.replaceAll('[^a-zA-Z0-9._\\-]', '_');
        if (name.length() > 200) {
            name = name.substring(0, 200);
        }
        if (!name.contains('.')) {
            name += '.jpg';
        }
        return name;
    }

    private static String truncate(String s, Integer max) {
        if (s == null || max == null || max <= 0) {
            return '';
        }
        return s.length() <= max ? s : s.substring(0, max);
    }
}
