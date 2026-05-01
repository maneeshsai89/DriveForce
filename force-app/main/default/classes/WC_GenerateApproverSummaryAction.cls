/**
 * WC — Invocable: Flex prompt (WC_Approver_Slack_Summary) to produce approver AI summary + recommended action.
 * Uses dealer insight narrative from WC_ApproverContextService (same logic as Data Cloud CI on CRM data).
 */
public without sharing class WC_GenerateApproverSummaryAction {
    /** Test-only: skip Einstein call; still exercises persist path. */
    @TestVisible
    private static Boolean bypassPromptForTest = false;

    @TestVisible
    private static final String INPUT_CLAIM = 'Input:Claim_Context';
    @TestVisible
    private static final String INPUT_DEALER = 'Input:Dealer_Insights_Text';
    @TestVisible
    private static final String INPUT_RISK = 'Input:Risk_Score_Label';

    public class WC_Request {
        @InvocableVariable(label='Claim Id' description='Claim to summarise for approvers.' required=true)
        public String claimId;
        @InvocableVariable(
            label='Persist To Claim'
            description='If true, writes WC_AI_Summary__c and WC_AI_Recommendation__c on the Claim.'
        )
        public Boolean persistToClaim;
    }

    public class WC_Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='AI Summary')
        public String aiSummary;
        @InvocableVariable(label='Recommended Action')
        public String recommendedAction;
        @InvocableVariable(label='Confidence Note')
        public String confidenceNote;
        @InvocableVariable(
            label='AI Risk Score'
            description='0–100 from the prompt JSON (riskScore). Written to WC_AI_Risk_Score__c when Persist To Claim is true.'
        )
        public Decimal riskScore;
        @InvocableVariable(label='Dealer Insights Narrative')
        public String dealerInsightsNarrative;
        @InvocableVariable(label='Claim Context Block')
        public String claimContextBlock;
    }

    @InvocableMethod(
        label='WC Generate Approver Summary'
        description='Runs WC_Approver_Slack_Summary Flex prompt (summary + riskScore 0–100 + recommendation); optional persist to Claim AI fields.'
    )
    public static List<WC_Result> generate(List<WC_Request> requests) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GenerateApproverSummary batchSize=' + (requests == null ? 0 : requests.size())
        );
        List<WC_Result> out = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GenerateApproverSummary empty request list — nothing to run.');
            return out;
        }
        for (WC_Request req : requests) {
            out.add(generateOne(req));
        }
        return out;
    }

    private static WC_Result generateOne(WC_Request req) {
        WC_Result r = new WC_Result();
        r.success = false;
        if (req == null || String.isBlank(req.claimId)) {
            r.errorMessage = 'Claim Id is required.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GenerateApproverSummary fail: ' + r.errorMessage);
            return r;
        }
        Id cid;
        try {
            cid = Id.valueOf(req.claimId.trim());
        } catch (Exception e) {
            r.errorMessage = 'Invalid Claim Id.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GenerateApproverSummary fail: ' + r.errorMessage + ' raw=' + req.claimId);
            return r;
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GenerateApproverSummary start claimId=' +
                String.valueOf(cid) +
                ' persistToClaim=' +
                (req.persistToClaim == null ? 'null' : String.valueOf(req.persistToClaim))
        );
        WC_ApproverContextService.ApproverContext ctx = WC_ApproverContextService.build(cid);
        if (ctx.claimName == null) {
            r.errorMessage = 'Claim not found.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GenerateApproverSummary fail: ' + r.errorMessage + ' claimId=' + cid);
            return r;
        }
        r.dealerInsightsNarrative = ctx.dealerInsightsNarrative;
        r.claimContextBlock = ctx.claimContextBlock;

        if (Test.isRunningTest() && bypassPromptForTest) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_FLOW GenerateApproverSummary test bypass path');
            r.success = true;
            r.aiSummary = 'Test approver summary.';
            r.recommendedAction = 'Review';
            r.confidenceNote = 'Test mode.';
            r.riskScore = 42;
            Boolean persist = req.persistToClaim != null && req.persistToClaim;
            if (persist) {
                Claim upd = new Claim(Id = cid, WC_AI_Summary__c = 'Test approver summary.');
                upd.WC_AI_Recommendation__c = 'Review';
                upd.WC_AI_Risk_Score__c = 42;
                Database.update(new List<Claim>{ upd }, AccessLevel.SYSTEM_MODE);
            }
            return r;
        }

        WC_Prompt_Config__mdt cfg = WC_Prompt_Config__mdt.getInstance('WC_Approver_Slack_Summary');
        String templateName = 'WC_Approver_Slack_Summary';
        String appName = 'EinsteinGpt';
        if (cfg != null) {
            if (String.isNotBlank(cfg.Approver_Summary_Template_Name__c)) {
                templateName = cfg.Approver_Summary_Template_Name__c.trim();
            }
            if (String.isNotBlank(cfg.Llm_Application_Name__c)) {
                appName = cfg.Llm_Application_Name__c.trim();
            }
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GenerateApproverSummary prompt templateName=' +
                templateName +
                ' appName=' +
                appName +
                ' claimContextLen=' +
                (ctx.claimContextBlock == null ? 0 : ctx.claimContextBlock.length()) +
                ' dealerInsightLen=' +
                (ctx.dealerInsightsNarrative == null ? 0 : ctx.dealerInsightsNarrative.length())
        );

        try {
            ConnectApi.WrappedValue wClaim = new ConnectApi.WrappedValue();
            wClaim.value = ctx.claimContextBlock == null ? '' : ctx.claimContextBlock;
            ConnectApi.WrappedValue wDealer = new ConnectApi.WrappedValue();
            wDealer.value = ctx.dealerInsightsNarrative == null ? '' : ctx.dealerInsightsNarrative;
            ConnectApi.WrappedValue wRisk = new ConnectApi.WrappedValue();
            wRisk.value = buildRiskInputForPrompt(ctx);

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put(INPUT_CLAIM, wClaim);
            inputParams.put(INPUT_DEALER, wDealer);
            inputParams.put(INPUT_RISK, wRisk);

            ConnectApi.EinsteinPromptTemplateGenerationsInput exec = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            exec.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            exec.additionalConfig.applicationName = appName;
            exec.additionalConfig.numGenerations = 1;
            exec.additionalConfig.enablePiiMasking = false;
            exec.isPreview = false;
            exec.inputParams = inputParams;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                templateName,
                exec
            );
            if (gen == null || gen.generations == null || gen.generations.isEmpty()) {
                r.errorMessage = 'No generation returned from prompt template.';
                System.debug(
                    LoggingLevel.ERROR,
                    'WC_SLACK_FLOW GenerateApproverSummary fail: ' +
                        r.errorMessage +
                        ' template=' +
                        templateName
                );
                return r;
            }
            String llmText = gen.generations[0].text;
            System.debug(
                LoggingLevel.DEBUG,
                'WC_SLACK_FLOW GenerateApproverSummary LLM raw len=' + (llmText == null ? 0 : llmText.length())
            );
            WC_ApproverSummaryLlmParser.ParsedSummary parsed = WC_ApproverSummaryLlmParser.parse(llmText);
            r.aiSummary = parsed.summary;
            r.recommendedAction = normalizeRecommendation(parsed.recommendedAction);
            r.confidenceNote = parsed.confidenceNote;
            r.riskScore = parsed.riskScore;
            r.success = true;

            Boolean persist = req.persistToClaim != null && req.persistToClaim;
            if (persist) {
                Claim upd = new Claim(Id = cid);
                if (String.isNotBlank(r.aiSummary)) {
                    upd.WC_AI_Summary__c = trimField(r.aiSummary, 32000);
                }
                String pv = picklistValueOrNull(r.recommendedAction);
                if (pv != null) {
                    upd.WC_AI_Recommendation__c = pv;
                }
                if (parsed.riskScore != null) {
                    upd.WC_AI_Risk_Score__c = parsed.riskScore;
                }
                if (
                    upd.WC_AI_Summary__c != null ||
                    upd.WC_AI_Recommendation__c != null ||
                    upd.WC_AI_Risk_Score__c != null
                ) {
                    Database.update(new List<Claim>{ upd }, AccessLevel.SYSTEM_MODE);
                }
            }
        } catch (Exception e) {
            r.errorMessage = e.getMessage();
            System.debug(
                LoggingLevel.ERROR,
                'WC_SLACK_FLOW GenerateApproverSummary LLM exception type=' +
                    e.getTypeName() +
                    ' msg=' +
                    e.getMessage() +
                    ' line=' +
                    e.getLineNumber()
            );
            System.debug(LoggingLevel.ERROR, e);
            return r;
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GenerateApproverSummary success=' +
                r.success +
                ' aiSummaryLen=' +
                (r.aiSummary == null ? 0 : r.aiSummary.length()) +
                ' err=' +
                r.errorMessage
        );
        return r;
    }

    /**
     * Tells the model whether a CRM score already exists; it must still output riskScore in JSON (revise or replace as appropriate).
     */
    private static String buildRiskInputForPrompt(WC_ApproverContextService.ApproverContext ctx) {
        if (ctx.riskScore != null) {
            return 'Existing CRM risk score: '
                + WC_ApproverContextService.riskTierLabel(ctx.riskScore)
                + ' ('
                + WC_ApproverContextService.formatRiskScoreFraction(ctx.riskScore)
                + '). Re-evaluate and set riskScore in your JSON; you may keep, raise, or lower it based on the full context.';
        }
        return 'No prior risk score on this claim. You must derive riskScore (integer 0–100) only from the claim and dealer context above.';
    }

    private static String trimField(String s, Integer maxLen) {
        if (String.isBlank(s)) {
            return s;
        }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }

    private static String normalizeRecommendation(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String u = raw.trim();
        if (u.equalsIgnoreCase('Approve')) {
            return 'Approve';
        }
        if (u.equalsIgnoreCase('Reject')) {
            return 'Reject';
        }
        if (u.equalsIgnoreCase('Review')) {
            return 'Review';
        }
        return 'Review';
    }

    private static String picklistValueOrNull(String normalized) {
        if (normalized == null) {
            return null;
        }
        if (normalized == 'Approve' || normalized == 'Reject' || normalized == 'Review') {
            return normalized;
        }
        return null;
    }
}
