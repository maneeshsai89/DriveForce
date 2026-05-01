/**
 * WC — Invocable: build Slack Block Kit JSON matching the approver card layout (see slack_approver_warranty_workflow.html).
 * No HTTP — pass output into a Flow action that supports Block Kit / message JSON, or chat.postMessage via integration.
 */
public without sharing class WC_BuildSlackApproverBlocksAction {
    private static final String DAMAGE_IMAGE_TEMPLATE_DEV_NAME = 'WC_Claim_Damage_Image_Summary';
    private static final String INPUT_DAMAGE_PHOTO = 'Input:Damage_Photo';
    private static final String INPUT_DAMAGE_OPTIONAL_CTX = 'Input:Optional_Context';
    private static final String LLM_APPLICATION_NAME = 'PromptTemplateGenerationsInvocable';

    /** Test-only: skip Einstein call when a file is linked to the claim. */
    @TestVisible
    private static Boolean bypassDamageImagePromptForTest = false;

    @TestVisible
    private static String testDamageImageSummaryStub = 'Test photo summary from attachment.';

    public class WC_Request {
        @InvocableVariable(label='Claim Id' description='Claim Id (18 chars).' required=true)
        public String claimId;
        @InvocableVariable(label='Claim Name')
        public String claimName;
        @InvocableVariable(label='Dealer Name')
        public String dealerName;
        @InvocableVariable(label='VIN')
        public String vin;
        @InvocableVariable(label='Vehicle Model')
        public String vehicleModel;
        @InvocableVariable(label='Model Year')
        public String modelYear;
        @InvocableVariable(label='Warranty Hint')
        public String warrantyHint;
        @InvocableVariable(label='Fault Text')
        public String faultText;
        @InvocableVariable(label='Part Code')
        public String partCode;
        @InvocableVariable(label='Part Name')
        public String partName;
        @InvocableVariable(label='Labour Hours')
        public Decimal labourHours;
        @InvocableVariable(label='Mileage')
        public Integer mileage;
        @InvocableVariable(label='Estimated Amount')
        public Decimal estimatedAmount;
        @InvocableVariable(label='Risk Score')
        public Decimal riskScore;
        @InvocableVariable(
            label='Risk Label'
            description='Optional. Ignored when Risk Score is set (tier is derived: Low/Medium/High). If score is blank, placeholder values like "unknown" are treated as empty.'
        )
        public String riskLabel;
        @InvocableVariable(label='AI Summary')
        public String aiSummary;
        @InvocableVariable(label='Recommended Action')
        public String recommendedAction;
    }

    public class WC_Result {
        @InvocableVariable(
            label='Slack Message JSON'
            description='Full payload: {"blocks":[...]} for Slack chat.postMessage blocks field, or paste into compatible Flow action.'
        )
        public String slackMessageJson;
        @InvocableVariable(label='Blocks JSON Only' description='JSON array string of blocks only, if your connector expects blocks without wrapper.')
        public String blocksArrayJson;
    }

    @InvocableMethod(
        label='WC Build Slack Approver Block Kit'
        description='Builds Block Kit JSON (no callout) from claim + AI fields for rich Slack messages.'
    )
    public static List<WC_Result> build(List<WC_Request> requests) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW BuildSlackBlocks batchSize=' + (requests == null ? 0 : requests.size())
        );
        List<WC_Result> out = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW BuildSlackBlocks empty request list.');
            return out;
        }
        for (WC_Request req : requests) {
            out.add(buildOne(req));
        }
        return out;
    }

    private static WC_Result buildOne(WC_Request req) {
        WC_Result r = new WC_Result();
        if (req == null || String.isBlank(req.claimId)) {
            r.slackMessageJson = '{}';
            r.blocksArrayJson = '[]';
            System.debug(
                LoggingLevel.WARN,
                'WC_SLACK_FLOW BuildSlackBlocks empty claimId — returning empty blocks (downstream Slack may show nothing).'
            );
            return r;
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW BuildSlackBlocks start claimId=' +
                req.claimId +
                ' aiSummaryLen=' +
                (req.aiSummary == null ? 0 : req.aiSummary.length())
        );

        String title =
            nz(req.claimName) +
            ' · ' +
            nz(req.dealerName);
        String vehicleLine =
            nz(req.vehicleModel) +
            (String.isNotBlank(req.modelYear) ? (' · ' + req.modelYear) : '');
        String partLine =
            nz(req.partCode) +
            (String.isNotBlank(req.partName) ? (' · ' + req.partName) : req.partCode);

        List<Object> blocks = new List<Object>();
        blocks.add(
            new Map<String, Object>{
                'type' => 'header',
                'text' => new Map<String, Object>{
                    'type' => 'plain_text',
                    'text' => truncatePlain(title, 150),
                    'emoji' => true
                }
            }
        );
        blocks.add(
            new Map<String, Object>{
                'type' => 'section',
                'text' => new Map<String, Object>{
                    'type' => 'mrkdwn',
                    'text' => '*New warranty claim submitted* — prior authorisation required.'
                }
            }
        );

        List<Object> fields = new List<Object>();
        addField(fields, 'VIN', nz(req.vin));
        addField(fields, 'Vehicle', vehicleLine);
        addField(fields, 'Warranty', nz(req.warrantyHint));
        addField(fields, 'Mileage', req.mileage != null ? String.valueOf(req.mileage) : '—');
        addField(fields, 'Fault', nz(req.faultText));
        addField(fields, 'Part', partLine);
        addField(fields, 'Labour', req.labourHours != null ? String.valueOf(req.labourHours) + ' hrs' : '—');
        addField(fields, 'Est. cost', req.estimatedAmount != null ? String.valueOf(req.estimatedAmount) : '—');
        addField(fields, 'Claim Id', '`' + req.claimId + '`');

        blocks.add(new Map<String, Object>{ 'type' => 'section', 'fields' => fields });

        blocks.add(
            new Map<String, Object>{
                'type' => 'section',
                'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => buildRiskSection(req) }
            }
        );

        String ai = nz(req.aiSummary);
        if (ai.length() > 2900) {
            ai = ai.substring(0, 2897) + '...';
        }
        blocks.add(
            new Map<String, Object>{
                'type' => 'section',
                'text' => new Map<String, Object>{
                    'type' => 'mrkdwn',
                    'text' => '*AI summary*\n' + ai
                }
            }
        );

        Id claimRecordId = null;
        try {
            claimRecordId = Id.valueOf(req.claimId.trim());
        } catch (Exception ignore) {
            claimRecordId = null;
        }
        String damageDocSummary = claimRecordId != null ? summarizeLatestLinkedDamagePhoto(claimRecordId, req) : null;
        if (String.isNotBlank(damageDocSummary)) {
            String docBlock = damageDocSummary;
            if (docBlock.length() > 2900) {
                docBlock = docBlock.substring(0, 2897) + '...';
            }
            blocks.add(
                new Map<String, Object>{
                    'type' => 'section',
                    'text' => new Map<String, Object>{
                        'type' => 'mrkdwn',
                        'text' => '*Document / photo summary*\n' + escapeSlackMrkdwn(docBlock)
                    }
                }
            );
        }

        if (String.isNotBlank(req.recommendedAction)) {
            blocks.add(
                new Map<String, Object>{
                    'type' => 'context',
                    'elements' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'mrkdwn',
                            'text' => 'Recommended action: *' + req.recommendedAction + '*'
                        }
                    }
                }
            );
        }

        String approveVal = req.claimId + '|Approve';
        String rejectVal = req.claimId + '|Reject';
        blocks.add(
            new Map<String, Object>{
                'type' => 'actions',
                'block_id' => 'wc_claim_decision',
                'elements' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'button',
                        'text' => new Map<String, Object>{
                            'type' => 'plain_text',
                            'text' => 'Approve',
                            'emoji' => true
                        },
                        'style' => 'primary',
                        'action_id' => 'wc_approve_claim',
                        'value' => truncatePlain(approveVal, 2000)
                    },
                    new Map<String, Object>{
                        'type' => 'button',
                        'text' => new Map<String, Object>{
                            'type' => 'plain_text',
                            'text' => 'Reject',
                            'emoji' => true
                        },
                        'style' => 'danger',
                        'action_id' => 'wc_reject_claim',
                        'value' => truncatePlain(rejectVal, 2000)
                    }/*,
                    new Map<String, Object>{
                        'type' => 'button',
                        'text' => new Map<String, Object>{
                            'type' => 'plain_text',
                            'text' => 'Ask a question',
                            'emoji' => true
                        },
                        'action_id' => 'wc_ask_agent',
                        'value' => truncatePlain(req.claimId, 2000)
                    }*/
                }
            }
        );

        blocks.add(
            new Map<String, Object>{
                'type' => 'context',
                'elements' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'mrkdwn',
                        'text' => 'Button clicks require Slack interactivity routing to Salesforce (Slack Workflow + Run flow) unless your org maps block_actions to Flow.'
                    }
                }
            }
        );

        String blocksOnly = JSON.serialize(blocks);
        Map<String, Object> wrap = new Map<String, Object>{ 'blocks' => blocks };
        r.slackMessageJson = JSON.serialize(wrap);
        r.blocksArrayJson = blocksOnly;
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW BuildSlackBlocks done blocksArrayJsonLen=' +
                (r.blocksArrayJson == null ? 0 : r.blocksArrayJson.length()) +
                ' slackMessageJsonLen=' +
                (r.slackMessageJson == null ? 0 : r.slackMessageJson.length())
        );
        return r;
    }

    private static void addField(List<Object> fields, String label, String value) {
        fields.add(
            new Map<String, Object>{
                'type' => 'mrkdwn',
                'text' => '*' + label + '*\n' + (String.isBlank(value) ? '—' : value)
            }
        );
    }

    /**
     * When a numeric score exists, tier (Low/Medium/High) is derived from the score so Flow/AI cannot send "unknown".
     * With no score, a non-placeholder label from the flow is shown; otherwise "Not assessed".
     */
    private static String buildRiskSection(WC_Request req) {
        if (req.riskScore != null) {
            String tier = WC_ApproverContextService.riskTierLabel(req.riskScore);
            return '*Risk* · *' + tier + '* · ' + WC_ApproverContextService.formatRiskScoreFraction(req.riskScore);
        }
        String cleaned = sanitizeFlowRiskLabel(req.riskLabel);
        if (String.isNotBlank(cleaned)) {
            return '*Risk* · *' + cleaned + '*';
        }
        return '*Risk* · *' + WC_ApproverContextService.riskTierLabel(null) + '*';
    }

    private static String sanitizeFlowRiskLabel(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String t = raw.trim();
        if (t.equalsIgnoreCase('unknown')) {
            return null;
        }
        if (t.equalsIgnoreCase('n/a') || t.equalsIgnoreCase('na')) {
            return null;
        }
        if (t.equalsIgnoreCase('none')) {
            return null;
        }
        return t;
    }

    private static String nz(String s) {
        return String.isBlank(s) ? '' : s;
    }

    private static String truncatePlain(String s, Integer maxLen) {
        if (String.isBlank(s)) {
            return '';
        }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }

    /**
     * Latest file linked to the claim (by link modstamp). Runs WC_Claim_Damage_Image_Summary when a ContentDocument exists.
     * Returns null when no file, prompt failure, or blank model output.
     */
    private static String summarizeLatestLinkedDamagePhoto(Id claimId, WC_Request req) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :claimId
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if (links.isEmpty()) {
            return null;
        }
        Id docId = links[0].ContentDocumentId;

        if (Test.isRunningTest() && bypassDamageImagePromptForTest) {
            return testDamageImageSummaryStub;
        }

        try {
            ConnectApi.WrappedValue wDoc = new ConnectApi.WrappedValue();
            wDoc.value = new Map<String, String>{
                'id' => String.valueOf(docId),
                'type' => 'ContentDocument'
            };
            ConnectApi.WrappedValue wCtx = new ConnectApi.WrappedValue();
            wCtx.value = buildDamagePromptOptionalContext(req);

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put(INPUT_DAMAGE_PHOTO, wDoc);
            inputParams.put(INPUT_DAMAGE_OPTIONAL_CTX, wCtx);

            ConnectApi.EinsteinPromptTemplateGenerationsInput exec = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            exec.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            exec.additionalConfig.applicationName = LLM_APPLICATION_NAME;
            exec.additionalConfig.numGenerations = 1;
            exec.additionalConfig.enablePiiMasking = false;
            exec.isPreview = false;
            exec.inputParams = inputParams;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                DAMAGE_IMAGE_TEMPLATE_DEV_NAME,
                exec
            );
            if (gen == null || gen.generations == null || gen.generations.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'WC_SLACK_FLOW damage image prompt returned no generations template=' + DAMAGE_IMAGE_TEMPLATE_DEV_NAME
                );
                return null;
            }
            String text = gen.generations[0].text;
            return String.isBlank(text) ? null : text.trim();
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'WC_SLACK_FLOW damage image summary failed: ' + e.getMessage() + ' claimId=' + String.valueOf(claimId)
            );
            System.debug(LoggingLevel.ERROR, e);
            return null;
        }
    }

    private static String buildDamagePromptOptionalContext(WC_Request req) {
        if (req == null) {
            return '';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(req.claimName)) {
            parts.add('Claim: ' + req.claimName.trim());
        }
        if (String.isNotBlank(req.vehicleModel)) {
            parts.add('Vehicle: ' + req.vehicleModel.trim());
        }
        if (String.isNotBlank(req.faultText)) {
            parts.add('Fault reported: ' + req.faultText.trim());
        }
        return parts.isEmpty() ? '' : String.join(parts, '\n');
    }

    /** Reduce accidental Slack mrkdwn / HTML injection from model output. */
    private static String escapeSlackMrkdwn(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}