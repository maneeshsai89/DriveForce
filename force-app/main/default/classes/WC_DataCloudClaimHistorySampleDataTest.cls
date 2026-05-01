/**
 * WC — Tests WC_DataCloudClaimHistorySampleData (plan size + idempotency message path).
 */
@isTest
private class WC_DataCloudClaimHistorySampleDataTest {
    @isTest
    static void claim_plan_has_expected_volume() {
        List<WC_DataCloudClaimHistorySampleData.ClaimSeed> plan = WC_DataCloudClaimHistorySampleData.buildClaimPlanForTest();
        System.assertEquals(19, plan.size(), 'Seed plan should define 19 claims for DC demos.');
    }

    @isTest
    static void seed_is_idempotent_second_call() {
        String first = WC_DataCloudClaimHistorySampleData.seedDealerClaimHistory();
        System.assert(first.contains('complete') || first.contains('already seeded'), first);

        String second = WC_DataCloudClaimHistorySampleData.seedDealerClaimHistory();
        System.assert(second.contains('already present'), second);
    }
}
