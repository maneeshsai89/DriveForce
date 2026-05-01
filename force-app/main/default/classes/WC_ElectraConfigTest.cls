/**
 * WC — Tests for WC_ElectraConfig cron helpers.
 */
@isTest
private class WC_ElectraConfigTest {
    @isTest
    static void cron_one_time_gmt_matches_schedule_format() {
        Datetime dt = Datetime.newInstanceGmt(2026, 4, 13, 14, 5, 7);
        System.assertEquals('07 05 14 13 04 ? 2026', WC_ElectraConfig.cronForOneTimeRunGmt(dt));
    }

    @isTest
    static void cron_one_time_gmt_null_uses_now() {
        String c = WC_ElectraConfig.cronForOneTimeRunGmt(null);
        System.assertNotEquals(null, c);
        System.assert(c.contains(' ? '), c);
    }
}
