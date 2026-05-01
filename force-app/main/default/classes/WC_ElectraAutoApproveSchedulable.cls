/**
 * WC — Processes Electra auto-approvals, then reschedules itself after the CMDT poll interval using a
 * one-off GMT cron (Salesforce does not support repeating minute-level crons with valid syntax).
 */
public class WC_ElectraAutoApproveSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        WC_ElectraAutoApproveProcessor.processDueClaims();
        if (sc != null) {
            System.abortJob(sc.getTriggerId());
        }
        Integer pollSec = WC_ElectraConfig.getPollIntervalSeconds();
        Datetime next = System.now().addSeconds(pollSec);
        String cron = WC_ElectraConfig.cronForOneTimeRunGmt(next);
        System.schedule(WC_ElectraAutoApproveScheduler.JOB_NAME, cron, new WC_ElectraAutoApproveSchedulable());
    }
}
