/**
 * WC — Schedules {@link WC_ElectraAutoApproveSchedulable} using poll interval from WC_Slack_Approval_Config__mdt.
 * The schedulable chains one-off GMT crons (see {@link WC_ElectraConfig#cronForOneTimeRunGmt}).
 * First run: {@code WC_ElectraAutoApproveScheduler.scheduleRecurringJob();}
 * After changing {@code Electra_Poll_Interval_Sec__c} in CMDT: {@code WC_ElectraAutoApproveScheduler.rescheduleRecurringJob();}
 */
public with sharing class WC_ElectraAutoApproveScheduler {
    public static final String JOB_NAME = 'WC_Electra_Auto_Approve_Every_Minute';

    /**
     * Schedules the job if none exists with {@link #JOB_NAME}. Next run is {@code now +} poll seconds
     * from CMDT (default 60s).
     */
    public static String scheduleRecurringJob() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return null;
        }
        Integer poll = WC_ElectraConfig.getPollIntervalSeconds();
        Datetime next = System.now().addSeconds(poll);
        String cron = WC_ElectraConfig.cronForOneTimeRunGmt(next);
        return System.schedule(JOB_NAME, cron, new WC_ElectraAutoApproveSchedulable());
    }

    /**
     * Aborts an existing job (if any) and schedules the next run using current CMDT poll interval.
     */
    public static String rescheduleRecurringJob() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME]) {
            System.abortJob(ct.Id);
        }
        Integer poll = WC_ElectraConfig.getPollIntervalSeconds();
        Datetime next = System.now().addSeconds(poll);
        String cron = WC_ElectraConfig.cronForOneTimeRunGmt(next);
        return System.schedule(JOB_NAME, cron, new WC_ElectraAutoApproveSchedulable());
    }

    /** @deprecated Use {@link #scheduleRecurringJob()} — name kept for existing anonymous scripts. */
    public static String scheduleEveryMinute() {
        return scheduleRecurringJob();
    }
}
