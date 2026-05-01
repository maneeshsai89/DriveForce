/**
 * WC — Flex prompt (WC_Electra_Auto_Approval_Reason) to produce Electra auto-approval audit text from claim context + AI summary.
 */
public without sharing class WC_ElectraApprovalReasonGenerator {
    @TestVisible
    private static Boolean bypassPromptForTest = false;

    private static final String INPUT_CLAIM = 'Input:Claim_Context';
    private static final String INPUT_AI = 'Input:AI_Summary';
    private static final String INPUT_RISK = 'Input:Risk_Score';

    /**
     * Returns a short justification for WC_Electra_Auto_Notes__c and Slack; falls back to {@link WC_ElectraAutoApproveProcessor#DEFAULT_REASON} on failure.
     */
    public static String generate(Id claimId) {
        if (claimId == null) {
            return WC_ElectraAutoApproveProcessor.DEFAULT_REASON;
        }
        if (Test.isRunningTest() && bypassPromptForTest) {
            return 'Test Electra LLM reason.';
        }

        WC_ApproverContextService.ApproverContext ctx = WC_ApproverContextService.build(claimId);
        if (ctx.claimName == null) {
            return WC_ElectraAutoApproveProcessor.DEFAULT_REASON;
        }

        List<Claim> rows = [
            SELECT WC_AI_Summary__c, WC_AI_Risk_Score__c
            FROM Claim
            WHERE Id = :claimId
            LIMIT 1
        ];
        String aiSummary = rows.isEmpty() || rows[0].WC_AI_Summary__c == null ? '' : rows[0].WC_AI_Summary__c;
        Decimal risk = rows.isEmpty() ? null : rows[0].WC_AI_Risk_Score__c;

        WC_Prompt_Config__mdt cfg = WC_Prompt_Config__mdt.getInstance('WC_Approver_Slack_Summary');
        String templateName = 'WC_Electra_Auto_Approval_Reason';
        String appName = 'EinsteinGpt';
        if (cfg != null) {
            if (String.isNotBlank(cfg.Electra_Reason_Template_Name__c)) {
                templateName = cfg.Electra_Reason_Template_Name__c.trim();
            }
            if (String.isNotBlank(cfg.Llm_Application_Name__c)) {
                appName = cfg.Llm_Application_Name__c.trim();
            }
        }

        try {
            ConnectApi.WrappedValue wClaim = new ConnectApi.WrappedValue();
            wClaim.value = ctx.claimContextBlock == null ? '' : ctx.claimContextBlock;
            ConnectApi.WrappedValue wAi = new ConnectApi.WrappedValue();
            wAi.value = aiSummary;
            ConnectApi.WrappedValue wRisk = new ConnectApi.WrappedValue();
            wRisk.value = risk == null ? '' : String.valueOf(risk);

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put(INPUT_CLAIM, wClaim);
            inputParams.put(INPUT_AI, wAi);
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
                return WC_ElectraAutoApproveProcessor.DEFAULT_REASON;
            }
            String llmText = gen.generations[0].text;
            String reason = parseReasonJson(llmText);
            if (String.isNotBlank(reason)) {
                return trimToNotesField(reason);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_Electra reason LLM failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e);
        }
        return WC_ElectraAutoApproveProcessor.DEFAULT_REASON;
    }

    private static String parseReasonJson(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String text = raw.trim();
        text = stripMarkdownFences(text);
        Integer start = text.indexOf('{');
        Integer endIdx = text.lastIndexOf('}');
        if (start < 0 || endIdx <= start) {
            return text.length() > 5000 ? text.substring(0, 5000) : text;
        }
        String jsonSlice = text.substring(start, endIdx + 1);
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonSlice);
            if (root.containsKey('reason') && root.get('reason') != null) {
                return String.valueOf(root.get('reason')).trim();
            }
        } catch (Exception e) {
            /* fall through */
        }
        return text.length() > 5000 ? text.substring(0, 5000) : text;
    }

    private static String stripMarkdownFences(String s) {
        if (s.startsWith('```')) {
            Integer nl = s.indexOf('\n');
            if (nl > 0) {
                s = s.substring(nl + 1);
            }
            Integer close = s.lastIndexOf('```');
            if (close > 0) {
                s = s.substring(0, close);
            }
        }
        return s.trim();
    }

    private static String trimToNotesField(String s) {
        if (String.isBlank(s)) {
            return s;
        }
        return s.length() > 5000 ? s.substring(0, 5000) : s;
    }
}
