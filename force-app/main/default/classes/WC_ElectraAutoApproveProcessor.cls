/**
 * WC — Electra Automated Approver: after Slack notification, if still Pending ~1 min later and risk &lt; 50, approve in CRM and refresh Slack.
 */
public without sharing class WC_ElectraAutoApproveProcessor {
    @TestVisible
    private static final Decimal RISK_THRESHOLD_EXCLUSIVE = 50;

    public static final String DEFAULT_REASON =
        'Risk score under 50 and no manual approval within the configured wait after Slack notification.';

    public static void processDueClaims() {
        Datetime now = System.now();
        List<Claim> stubs = [
            SELECT Id
            FROM Claim
            WHERE
                WC_Approval_Result__c = 'Pending'
                AND WC_Electra_Auto_Check_At__c != null
                AND WC_Electra_Auto_Check_At__c <= :now
            LIMIT 100
        ];
        for (Claim stub : stubs) {
            processOne(stub.Id);
        }
    }

    /**
     * Generates LLM reason before lock DML; locks and re-validates before approve.
     */
    private static void processOne(Id claimId) {
        List<Claim> pre = [
            SELECT
                Id,
                Name,
                WC_Approval_Result__c,
                WC_AI_Risk_Score__c,
                WC_Slack_Channel_Id__c,
                WC_Slack_Message_Ts__c,
                WC_Electra_Auto_Check_At__c
            FROM Claim
            WHERE Id = :claimId
            LIMIT 1
        ];
        if (pre.isEmpty()) {
            return;
        }
        Claim snap = pre[0];
        if (snap.WC_Electra_Auto_Check_At__c == null) {
            return;
        }
        if (snap.WC_Approval_Result__c != 'Pending') {
            clearElectraSchedule(claimId);
            return;
        }
        Decimal risk = snap.WC_AI_Risk_Score__c;
        if (risk == null || risk >= RISK_THRESHOLD_EXCLUSIVE) {
            clearElectraSchedule(claimId);
            return;
        }

        String reason = WC_ElectraApprovalReasonGenerator.generate(claimId);

        List<Claim> rows;
        try {
            rows = [
                SELECT
                    Id,
                    Name,
                    WC_Approval_Result__c,
                    WC_AI_Risk_Score__c,
                    WC_Slack_Channel_Id__c,
                    WC_Slack_Message_Ts__c,
                    WC_Electra_Auto_Check_At__c
                FROM Claim
                WHERE Id = :claimId
                FOR UPDATE
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'WC_Electra skip lock claimId=' + claimId + ' ' + e.getMessage());
            return;
        }
        if (rows.isEmpty()) {
            return;
        }
        Claim c = rows[0];
        if (c.WC_Electra_Auto_Check_At__c == null) {
            return;
        }
        if (c.WC_Approval_Result__c != 'Pending') {
            clearElectraSchedule(claimId);
            return;
        }
        Decimal riskLocked = c.WC_AI_Risk_Score__c;
        if (riskLocked == null || riskLocked >= RISK_THRESHOLD_EXCLUSIVE) {
            clearElectraSchedule(claimId);
            return;
        }

        Claim upd = new Claim(
            Id = claimId,
            WC_Approval_Result__c = 'Approved',
            WC_Approval_Channel__c = 'Electra',
            WC_Approved_At__c = System.now(),
            WC_Electra_Auto_Notes__c = reason,
            WC_Electra_Auto_Check_At__c = null
        );
        Database.SaveResult sr = Database.update(new List<Claim>{ upd }, false, AccessLevel.SYSTEM_MODE)[0];
        if (!sr.isSuccess()) {
            for (Database.Error err : sr.getErrors()) {
                System.debug(LoggingLevel.WARN, 'WC_Electra approve DML ' + err.getStatusCode() + ' ' + err.getMessage());
            }
            return;
        }

        if (String.isNotBlank(c.WC_Slack_Channel_Id__c) && String.isNotBlank(c.WC_Slack_Message_Ts__c)) {
            try {
                System.enqueueJob(
                    new WC_ElectraSlackUpdateQueueable(
                        claimId,
                        c.WC_Slack_Channel_Id__c,
                        c.WC_Slack_Message_Ts__c,
                        c.Name,
                        reason
                    )
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'WC_Electra enqueue Slack update failed: ' + e.getMessage());
            }
        }
    }

    private static void clearElectraSchedule(Id claimId) {
        Database.update(
            new List<Claim>{ new Claim(Id = claimId, WC_Electra_Auto_Check_At__c = null) },
            false,
            AccessLevel.SYSTEM_MODE
        );
    }
}
