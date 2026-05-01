/**
 * WC — Invocable: load Claim + related rows + dealer insight metrics for Slack / approver agent (Use Case 2).
 */
public without sharing class WC_GetApproverContextAction {
    public class WC_Request {
        @InvocableVariable(label='Claim Id' description='Salesforce Claim Id (18 characters).' required=true)
        public String claimId;
    }

    public class WC_Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Claim Name')
        public String claimName;
        @InvocableVariable(label='Dealer Account Id')
        public String dealerAccountId;
        @InvocableVariable(label='Dealer Name')
        public String dealerName;
        @InvocableVariable(label='VIN')
        public String vin;
        @InvocableVariable(label='Vehicle Model')
        public String vehicleModel;
        @InvocableVariable(label='Model Year')
        public String modelYear;
        @InvocableVariable(label='Warranty Hint')
        public String warrantyHint;
        @InvocableVariable(label='Fault Text')
        public String faultText;
        @InvocableVariable(label='Part Name')
        public String partName;
        @InvocableVariable(label='Part Code')
        public String partCode;
        @InvocableVariable(label='Labour Hours')
        public Decimal labourHours;
        @InvocableVariable(label='Mileage')
        public Integer mileage;
        @InvocableVariable(label='Estimated Amount')
        public Decimal estimatedAmount;
        @InvocableVariable(label='Submission Channel')
        public String submissionChannel;
        @InvocableVariable(label='Claim Source')
        public String claimSource;
        @InvocableVariable(label='Risk Score')
        public Decimal riskScore;
        @InvocableVariable(label='Risk Label')
        public String riskLabel;
        @InvocableVariable(
            label='Dealer Insights Narrative'
            description='Metrics aligned with Data Cloud CI (same CRM definitions): 30/60/90 volumes, outcomes, repeat part.'
        )
        public String dealerInsightsNarrative;
        @InvocableVariable(label='Claim Context Block' description='Single text block for prompt input.')
        public String claimContextBlock;
        @InvocableVariable(label='Slack Plain Text Body' description='Prefixed plain text for Slack or Einstein for Slack.')
        public String slackPlainTextBody;
    }

    @InvocableMethod(
        label='WC Get Approver Notification Context'
        description='Loads claim, vehicle, part, dealer, and SOQL dealer metrics for Slack / approver AI.'
    )
    public static List<WC_Result> getContext(List<WC_Request> requests) {
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GetApproverContext batchSize=' + (requests == null ? 0 : requests.size())
        );
        List<WC_Result> out = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GetApproverContext empty request list.');
            return out;
        }
        for (WC_Request req : requests) {
            out.add(getOne(req));
        }
        return out;
    }

    private static WC_Result getOne(WC_Request req) {
        WC_Result r = new WC_Result();
        r.success = false;
        if (req == null || String.isBlank(req.claimId)) {
            r.errorMessage = 'Claim Id is required.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GetApproverContext fail: ' + r.errorMessage);
            return r;
        }
        Id cid;
        try {
            cid = Id.valueOf(req.claimId.trim());
        } catch (Exception e) {
            r.errorMessage = 'Invalid Claim Id.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GetApproverContext fail: ' + r.errorMessage);
            return r;
        }
        System.debug(LoggingLevel.DEBUG, 'WC_SLACK_FLOW GetApproverContext start claimId=' + String.valueOf(cid));
        WC_ApproverContextService.ApproverContext ctx = WC_ApproverContextService.build(cid);
        if (ctx.claimName == null) {
            r.errorMessage = 'Claim not found.';
            System.debug(LoggingLevel.WARN, 'WC_SLACK_FLOW GetApproverContext fail: ' + r.errorMessage + ' id=' + cid);
            return r;
        }
        r.success = true;
        r.claimName = ctx.claimName;
        r.dealerAccountId = ctx.dealerAccountId;
        r.dealerName = ctx.dealerName;
        r.vin = ctx.vin;
        r.vehicleModel = ctx.vehicleModel;
        r.modelYear = ctx.modelYear;
        r.warrantyHint = ctx.warrantyHint;
        r.faultText = ctx.faultText;
        r.partName = ctx.partName;
        r.partCode = ctx.partCode;
        r.labourHours = ctx.labourHours;
        r.mileage = ctx.mileage;
        r.estimatedAmount = ctx.estimatedAmount;
        r.submissionChannel = ctx.submissionChannel;
        r.claimSource = ctx.claimSource;
        r.riskScore = ctx.riskScore;
        r.riskLabel = ctx.riskLabel;
        r.dealerInsightsNarrative = ctx.dealerInsightsNarrative;
        r.claimContextBlock = ctx.claimContextBlock;
        r.slackPlainTextBody = ctx.slackPlainTextBody;
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_FLOW GetApproverContext success claimName=' +
                r.claimName +
                ' riskLabel=' +
                r.riskLabel +
                ' claimContextLen=' +
                (r.claimContextBlock == null ? 0 : r.claimContextBlock.length())
        );
        return r;
    }
}
