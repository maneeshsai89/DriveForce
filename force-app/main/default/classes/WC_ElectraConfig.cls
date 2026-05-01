/**
 * WC — Reads Electra timing from WC_Slack_Approval_Config__mdt (Default).
 */
public without sharing class WC_ElectraConfig {
    public static final Integer DEFAULT_DELAY_SECONDS = 60;
    public static final Integer DEFAULT_POLL_INTERVAL_SECONDS = 60;
    public static final Integer MAX_DELAY_SECONDS = 604800;

    /** Seconds to wait after Slack notification before Electra may auto-approve. */
    public static Integer getDelaySeconds() {
        WC_Slack_Approval_Config__mdt cfg = WC_Slack_Approval_Config__mdt.getInstance('Default');
        if (cfg == null || cfg.Electra_Auto_Approve_Delay_Seconds__c == null) {
            return DEFAULT_DELAY_SECONDS;
        }
        Decimal d = cfg.Electra_Auto_Approve_Delay_Seconds__c;
        if (d < 1) {
            return 1;
        }
        if (d > MAX_DELAY_SECONDS) {
            return MAX_DELAY_SECONDS;
        }
        return Integer.valueOf(d.round());
    }

    /**
     * Target interval for the Electra Schedulable chain (seconds). Values below 60 are treated as 60
     * because many orgs do not support sub-minute recurring Apex reliably.
     */
    public static Integer getPollIntervalSeconds() {
        WC_Slack_Approval_Config__mdt cfg = WC_Slack_Approval_Config__mdt.getInstance('Default');
        if (cfg == null || cfg.Electra_Poll_Interval_Sec__c == null) {
            return DEFAULT_POLL_INTERVAL_SECONDS;
        }
        Decimal d = cfg.Electra_Poll_Interval_Sec__c;
        if (d < 60) {
            return 60;
        }
        if (d > 3600) {
            return 3600;
        }
        return Integer.valueOf(d.round());
    }

    /**
     * Single-fire cron for {@link System#schedule} at {@code runAtUtc} (GMT). Scheduled Apex in
     * Salesforce rejects wildcards, step syntax ({@code /N}), and comma lists in the seconds and
     * minutes fields; the Electra job therefore chains one-off schedules instead of a repeating cron.
     */
    public static String cronForOneTimeRunGmt(Datetime runAtUtc) {
        Datetime t = runAtUtc != null ? runAtUtc : System.now();
        return t.format('ss mm HH dd MM ? yyyy', 'GMT');
    }
}
