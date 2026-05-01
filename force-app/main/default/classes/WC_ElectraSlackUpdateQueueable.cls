/**
 * WC — Async Slack chat.update after Electra auto-approve (callout after DML).
 */
public class WC_ElectraSlackUpdateQueueable implements Queueable, Database.AllowsCallouts {
    private Id claimId;
    private String channel;
    private String ts;
    private String claimName;
    private String reason;

    public WC_ElectraSlackUpdateQueueable(
        Id claimId,
        String channel,
        String ts,
        String claimName,
        String reason
    ) {
        this.claimId = claimId;
        this.channel = channel;
        this.ts = ts;
        this.claimName = claimName;
        this.reason = reason;
    }

    public void execute(QueueableContext context) {
        WC_SlackElectraMessageService.postElectraApprovedMessage(claimId, channel, ts, claimName, reason);
    }
}
