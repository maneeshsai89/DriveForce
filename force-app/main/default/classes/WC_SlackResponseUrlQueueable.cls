/**
 * Runs after {@link WC_SlackClaimDecisionQueueable} so DML and Slack callout are in separate transactions
 * (Salesforce forbids HTTP callouts after DML in the same transaction).
 */
public class WC_SlackResponseUrlQueueable implements Queueable, Database.AllowsCallouts {
    private final String responseUrl;
    private final String decision;
    private final String claimIdStr;
    private final String slackMessageJson;

    public WC_SlackResponseUrlQueueable(String responseUrl, String decision, String claimIdStr, String slackMessageJson) {
        this.responseUrl = responseUrl;
        this.decision = decision;
        this.claimIdStr = claimIdStr;
        this.slackMessageJson = slackMessageJson;
    }

    public void execute(QueueableContext context) {
        WC_SlackClaimApprovalService.postSlackResponseUrlReplace(responseUrl, decision, claimIdStr, slackMessageJson);
    }
}
