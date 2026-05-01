/**
 * Performs Claim DML then enqueues {@link WC_SlackResponseUrlQueueable} for Slack {@code response_url}.
 * DML and HTTP callout cannot run in the same transaction; two queueables separate them.
 * <p>
 * Invoked from {@link WC_SlackClaimApprovalService#applySlackDecisionAsync} via {@link System#enqueueJob}
 * so Guest REST is not required to use {@code @future} (some orgs reject Guest → {@code @future}).
 */
public class WC_SlackClaimDecisionQueueable implements Queueable {
    private final String claimIdStr;
    private final String decision;
    private final String responseUrl;
    private final String slackMessageJson;

    public WC_SlackClaimDecisionQueueable(String claimIdStr, String decision, String responseUrl, String slackMessageJson) {
        this.claimIdStr = claimIdStr;
        this.decision = decision;
        this.responseUrl = responseUrl;
        this.slackMessageJson = slackMessageJson;
    }

    public void execute(QueueableContext context) {
        WC_SlackClaimApprovalService.applySlackDecision(claimIdStr, decision);
        if (String.isNotBlank(responseUrl)) {
            try {
                System.enqueueJob(new WC_SlackResponseUrlQueueable(responseUrl, decision, claimIdStr, slackMessageJson));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'WC_SLACK_APPROVAL enqueue WC_SlackResponseUrlQueueable failed: ' + e.getMessage());
            }
        }
    }
}
