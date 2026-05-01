/**
 * WC — Tests for WC_BuildSlackApproverBlocksAction.
 */
@isTest
private class WC_BuildSlackApproverBlocksActionTest {
    private static final String CLAIM_WITH_FILE_NAME = 'WTY-SLACK-BLOCK-SETUP';

    @testSetup
    static void setupClaimWithAttachment() {
        Account dealer = new Account(Name = 'Slack Blocks Dealer');
        insert dealer;
        Claim c = new Claim();
        c.AccountId = dealer.Id;
        c.OwnerId = UserInfo.getUserId();
        c.Name = CLAIM_WITH_FILE_NAME;
        c.Summary = 'Scratch on panel';
        c.IsInhabitable = false;
        c.IsDrivable = true;
        c.IsAuthoritiesNotified = false;
        c.Status = 'Submitted';
        c.EstimatedAmount = 250;
        c.WC_Claim_Source__c = 'Agentforce';
        c.WC_Submission_Channel__c = 'Web';
        c.WC_Claim_Effective_Date__c = Date.today();
        c.WC_Approval_Result__c = 'Pending';
        insert c;

        ContentVersion cv = new ContentVersion();
        cv.Title = 'damage.png';
        cv.PathOnClient = 'damage.png';
        cv.VersionData = Blob.valueOf('fake-bytes');
        cv.FirstPublishLocationId = c.Id;
        insert cv;
    }

    @isTest
    static void build_adds_document_summary_when_claim_has_file() {
        WC_BuildSlackApproverBlocksAction.bypassDamageImagePromptForTest = true;
        try {
            Claim c = [SELECT Id, Name FROM Claim WHERE Name = :CLAIM_WITH_FILE_NAME LIMIT 1];
            WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
            req.claimId = c.Id;
            req.claimName = c.Name;
            req.aiSummary = 'Summary line.';
            req.faultText = 'Dent on door';
            req.vehicleModel = 'Model X';

            WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
                new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
            )[0];
            System.assert(
                r.slackMessageJson.contains('Document / photo summary'),
                'Expected attachment summary section'
            );
            System.assert(
                r.slackMessageJson.contains(WC_BuildSlackApproverBlocksAction.testDamageImageSummaryStub),
                'Expected stubbed Einstein output'
            );
        } finally {
            WC_BuildSlackApproverBlocksAction.bypassDamageImagePromptForTest = false;
        }
    }

    @isTest
    static void build_omits_document_summary_when_claim_has_no_file() {
        Account dealer = new Account(Name = 'Slack Blocks Dealer No File');
        insert dealer;
        Claim c = new Claim();
        c.AccountId = dealer.Id;
        c.OwnerId = UserInfo.getUserId();
        c.Name = 'WTY-SLACK-NO-FILE';
        c.Summary = 'No attachment';
        c.IsInhabitable = false;
        c.IsDrivable = true;
        c.IsAuthoritiesNotified = false;
        c.Status = 'Submitted';
        c.EstimatedAmount = 100;
        c.WC_Claim_Source__c = 'Agentforce';
        c.WC_Submission_Channel__c = 'Web';
        c.WC_Claim_Effective_Date__c = Date.today();
        c.WC_Approval_Result__c = 'Pending';
        insert c;

        WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
        req.claimId = c.Id;
        req.claimName = c.Name;
        req.aiSummary = 'Summary only.';

        WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
            new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
        )[0];
        System.assert(
            !r.slackMessageJson.contains('Document / photo summary'),
            'Section should appear only when a file is linked'
        );
    }

    @isTest
    static void build_outputs_json() {
        WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
        req.claimId = UserInfo.getOrganizationId();
        req.claimName = 'WTY-TEST-1';
        req.dealerName = 'Demo Motors';
        req.vin = '1HGCM82633A009999';
        req.aiSummary = 'Summary line.';
        req.riskLabel = 'Low';
        req.riskScore = 18;

        WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
            new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
        )[0];
        System.assert(r.slackMessageJson.contains('blocks'));
        System.assert(r.blocksArrayJson.contains('wc_approve_claim'));
        System.assert(r.slackMessageJson.contains('*Low*'), 'Tier from numeric score');
        System.assert(r.slackMessageJson.contains('18/100'), 'Score fraction');
    }

    @isTest
    static void build_derives_tier_when_flow_label_says_unknown() {
        WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
        req.claimId = UserInfo.getOrganizationId();
        req.riskLabel = 'unknown';
        req.riskScore = 80;

        WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
            new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
        )[0];
        System.assert(r.slackMessageJson.contains('*High*'), 'Ignore bad label when score present');
        System.assert(r.slackMessageJson.contains('80/100'));
    }

    @isTest
    static void build_not_assessed_when_no_score_and_placeholder_label() {
        WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
        req.claimId = UserInfo.getOrganizationId();
        req.riskLabel = 'Unknown';
        req.riskScore = null;

        WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
            new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
        )[0];
        System.assert(r.slackMessageJson.contains('*Not assessed*'));
    }

    @isTest
    static void build_blank_claim_id() {
        WC_BuildSlackApproverBlocksAction.WC_Request req = new WC_BuildSlackApproverBlocksAction.WC_Request();
        WC_BuildSlackApproverBlocksAction.WC_Result r = WC_BuildSlackApproverBlocksAction.build(
            new List<WC_BuildSlackApproverBlocksAction.WC_Request>{ req }
        )[0];
        System.assertEquals('{}', r.slackMessageJson);
    }
}
