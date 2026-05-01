/**
 * WC — Tests for WC_SuggestPartAction (blank input); LLM path is org-dependent.
 */
@isTest
private class WC_SuggestPartActionTest {
    @isTest
    static void suggest_blank_fault_returns_no_match() {
        WC_SuggestPartAction.WC_Request req = new WC_SuggestPartAction.WC_Request();
        req.faultDescription = '';
        List<WC_SuggestPartAction.WC_Result> results = WC_SuggestPartAction.suggestWC(
            new List<WC_SuggestPartAction.WC_Request>{ req }
        );
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].matchFound);
    }

    @isTest
    static void suggest_null_fault_returns_no_match() {
        WC_SuggestPartAction.WC_Request req = new WC_SuggestPartAction.WC_Request();
        req.faultDescription = null;
        List<WC_SuggestPartAction.WC_Result> results = WC_SuggestPartAction.suggestWC(
            new List<WC_SuggestPartAction.WC_Request>{ req }
        );
        System.assertEquals(false, results[0].matchFound);
    }

    @isTest
    static void keyword_fallback_finds_product_by_fault_token() {
        Product2 p = new Product2();
        p.Name = 'HV battery — keyword match test';
        p.IsActive = true;
        p.ProductCode = 'PART-KEYWORD-TEST-01';
        p.CurrencyIsoCode = 'USD';
        p.CanUseQuantitySchedule = false;
        p.CanUseRevenueSchedule = false;
        p.IsSerialized = false;
        p.IsCertified = false;
        p.IsEnvrPrtcRegCompliant = false;
        p.IsAssetizable = true;
        p.IsSoldOnlyWithOtherProds = false;
        p.IsShippingChargeNotApplicable = false;
        p.WC_Fault_Keywords__c = 'battery; range; degradation';
        insert p;

        Product2 found = WC_SuggestPartAction.resolveProductByFaultKeywords(
            'loss in range of vehicle',
            ''
        );
        System.assertNotEquals(null, found, 'Token "range" should match WC_Fault_Keywords__c');
        System.assertEquals(p.Id, found.Id);
    }
}
