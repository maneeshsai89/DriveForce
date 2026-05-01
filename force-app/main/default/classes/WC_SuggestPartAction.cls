/**
 * WC — Invocable: suggest Product2 using Einstein Prompt Builder (Flex template) grounded on Knowledge via Data Library.
 * Template name comes from WC_Prompt_Config__mdt.WC_Suggest_Part_From_Knowledge. The prompt must return JSON only (see WC_BUILD_CHANGELOG.md).
 * Resolution uses Product2 Id or ProductCode (minimal SOQL by Id/code — not text search on catalogue).
 * Product queries use AccessLevel.SYSTEM_MODE for the Einstein Service Agent user (limited license).
 */
public without sharing class WC_SuggestPartAction {
    @TestVisible
    private static final String INPUT_FAULT = 'Input:Fault_Description';
    @TestVisible
    private static final String INPUT_VEHICLE = 'Input:Vehicle_Model';

    public class WC_Request {
        @InvocableVariable(
            label='Fault Description'
            description='Free-text fault or symptom; used by the prompt to suggest a spare part.'
            required=true
        )
        public String faultDescription;
        @InvocableVariable(
            label='Vehicle Model'
            description='Optional vehicle model string to filter compatible Product2 records.'
        )
        public String vehicleModel;
    }

    public class WC_Result {
        @InvocableVariable(
            label='Suggested Product Id'
            description='Product2 Id when Match Found is true; use for ClaimItem.ProductId.'
        )
        public String suggestedProductId;
        @InvocableVariable(
            label='Product Name'
            description='Name of the resolved Product2 when Match Found is true.'
        )
        public String productName;
        @InvocableVariable(
            label='Product Code'
            description='ProductCode of the resolved Product2 when Match Found is true.'
        )
        public String productCode;
        @InvocableVariable(
            label='Match Found'
            description='True when the LLM output resolves to an active Product2 in the org.'
        )
        public Boolean matchFound;
    }

    @InvocableMethod(
        label='WC Suggest Part From Fault'
        description='Calls Flex prompt (WC_Prompt_Config__mdt) with Knowledge/Data Library grounding; parses JSON; resolves Product2 by Id or ProductCode.'
    )
    public static List<WC_Result> suggestWC(List<WC_Request> requests) {
        List<WC_Result> results = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (WC_Request req : requests) {
            results.add(suggestOne(req));
        }
        return results;
    }

    private static WC_Result suggestOne(WC_Request req) {
        WC_Result r = new WC_Result();
        r.matchFound = false;
        if (req == null || String.isBlank(req.faultDescription)) {
            return r;
        }
        String fault = req.faultDescription.trim();
        if (fault.length() > 12000) {
            fault = fault.substring(0, 12000);
        }
        String vm = String.isBlank(req.vehicleModel) ? '' : req.vehicleModel.trim();

        WC_Prompt_Config__mdt cfg = WC_Prompt_Config__mdt.getInstance('WC_Suggest_Part_From_Knowledge');
        String templateName = 'WC_Suggest_Part_From_Knowledge';
        // Default matches WC_Prompt_Config__mdt; override in metadata if your org requires another app name.
        String appName = 'EinsteinGpt';
        if (cfg != null) {
            if (String.isNotBlank(cfg.Suggest_Part_Template_Name__c)) {
                templateName = cfg.Suggest_Part_Template_Name__c.trim();
            }
            if (String.isNotBlank(cfg.Llm_Application_Name__c)) {
                appName = cfg.Llm_Application_Name__c.trim();
            }
        }

        try {
            ConnectApi.WrappedValue wFault = new ConnectApi.WrappedValue();
            wFault.value = fault;
            ConnectApi.WrappedValue wVehicle = new ConnectApi.WrappedValue();
            wVehicle.value = vm;

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put(INPUT_FAULT, wFault);
            inputParams.put(INPUT_VEHICLE, wVehicle);

            ConnectApi.EinsteinPromptTemplateGenerationsInput exec = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            exec.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            exec.additionalConfig.applicationName = appName;
            exec.additionalConfig.numGenerations = 1;
            // Trust Layer masking can change symptom text vs Prompt Builder preview; keep off unless required.
            exec.additionalConfig.enablePiiMasking = false;
            exec.isPreview = false;
            exec.inputParams = inputParams;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                templateName,
                exec
            );
            if (gen == null || gen.generations == null || gen.generations.isEmpty()) {
                return r;
            }
            String llmText = gen.generations[0].text;
            WC_SuggestPartLlmParser.ParsedSuggestion parsed = WC_SuggestPartLlmParser.parse(llmText);
            Product2 p = resolveProduct(parsed);
            if (p == null) {
                p = resolveProductByFaultKeywords(fault, vm);
            }
            if (p == null) {
                return r;
            }
            if (!passesVehicleModelGate(vm, p)) {
                return r;
            }
            r.matchFound = true;
            r.suggestedProductId = p.Id;
            r.productName = p.Name;
            r.productCode = p.ProductCode;
        } catch (Exception e) {
            r.matchFound = false;
        }
        return r;
    }

    private static Product2 resolveProduct(WC_SuggestPartLlmParser.ParsedSuggestion parsed) {
        if (parsed == null) {
            return null;
        }
        Boolean hasRef =
            String.isNotBlank(parsed.productId) || String.isNotBlank(parsed.productCode);
        if (!parsed.matchFound && !hasRef) {
            return null;
        }
        if (String.isNotBlank(parsed.productId)) {
            try {
                Id pid = Id.valueOf(parsed.productId);
                List<Product2> byId = (List<Product2>) Database.queryWithBinds(
                    'SELECT Id, Name, ProductCode, WC_Model_Compatibility__c FROM Product2 '
                        + 'WHERE Id = :pid AND IsActive = TRUE LIMIT 1',
                    new Map<String, Object>{ 'pid' => pid },
                    AccessLevel.SYSTEM_MODE
                );
                if (!byId.isEmpty()) {
                    return byId[0];
                }
            } catch (Exception e) {
                /* invalid Id */
            }
        }
        if (String.isNotBlank(parsed.productCode)) {
            List<Product2> byCode = (List<Product2>) Database.queryWithBinds(
                'SELECT Id, Name, ProductCode, WC_Model_Compatibility__c FROM Product2 '
                    + 'WHERE ProductCode = :pc AND IsActive = TRUE LIMIT 1',
                new Map<String, Object>{ 'pc' => parsed.productCode },
                AccessLevel.SYSTEM_MODE
            );
            if (!byCode.isEmpty()) {
                return byCode[0];
            }
        }
        return null;
    }

    /**
     * When the LLM returns no match (common if Data Library grounding differs from Prompt Builder preview),
     * match fault text against Product2.WC_Fault_Keywords__c (semicolon-separated phrases / words).
     */
    @TestVisible
    private static Product2 resolveProductByFaultKeywords(String fault, String vehicleModel) {
        if (String.isBlank(fault)) {
            return null;
        }
        Set<String> tokens = tokenizeForKeywordMatch(fault);
        if (tokens.isEmpty()) {
            return null;
        }
        // WC_Fault_Keywords__c is long text — cannot use in SOQL WHERE; scan a bounded active catalogue in memory.
        return scanActiveProductsForKeywordTokens(tokens, vehicleModel);
    }

    /**
     * Match fault tokens against Product2.WC_Fault_Keywords__c (long text).
     * Bounded to 200 most recently modified active products — suitable for demo/small catalogues.
     */
    private static Product2 scanActiveProductsForKeywordTokens(Set<String> tokens, String vehicleModel) {
        List<Product2> rows = (List<Product2>) Database.queryWithBinds(
            'SELECT Id, Name, ProductCode, WC_Model_Compatibility__c, WC_Fault_Keywords__c FROM Product2 '
                + 'WHERE IsActive = TRUE ORDER BY LastModifiedDate DESC LIMIT 200',
            new Map<String, Object>(),
            AccessLevel.SYSTEM_MODE
        );
        for (Product2 prod : rows) {
            if (prod.WC_Fault_Keywords__c == null) {
                continue;
            }
            String kw = prod.WC_Fault_Keywords__c.toLowerCase();
            for (String t : tokens) {
                if (kw.contains(t) && passesVehicleModelGate(vehicleModel, prod)) {
                    return prod;
                }
            }
        }
        return null;
    }

    private static Set<String> tokenizeForKeywordMatch(String fault) {
        Set<String> out = new Set<String>();
        String lower = fault.toLowerCase();
        for (String raw : lower.split('[^a-z0-9]+')) {
            String w = raw.trim();
            if (w.length() >= 3) {
                out.add(w);
            }
        }
        return out;
    }

    private static Boolean passesVehicleModelGate(String vehicleModel, Product2 p) {
        String vm = String.isBlank(vehicleModel) ? '' : vehicleModel.trim();
        if (vm.length() == 0) {
            return true;
        }
        if (p.WC_Model_Compatibility__c == null) {
            return true;
        }
        return p.WC_Model_Compatibility__c.containsIgnoreCase(vm);
    }
}
