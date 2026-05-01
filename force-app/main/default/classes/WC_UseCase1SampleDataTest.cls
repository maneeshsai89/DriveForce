/**
 * WC — Smoke test for WC_UseCase1SampleData (coverage for deploy).
 */
@isTest
private class WC_UseCase1SampleDataTest {
    @isTest
    static void seed_runs_twice_second_is_idempotent() {
        String first = WC_UseCase1SampleData.seedUseCase1();
        System.assert(
            first.containsIgnoreCase('created') || first.containsIgnoreCase('already'),
            first
        );
        String second = WC_UseCase1SampleData.seedUseCase1();
        System.assert(second.containsIgnoreCase('already'), second);
    }
}
