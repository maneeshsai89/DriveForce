/**
 * WC — Tests for WC_PostSlackWebhookMessageAction (HttpCalloutMock; no real Slack).
 */
@isTest
private class WC_PostSlackWebhookMessageActionTest {
    private static Id createTestClaimIdForSlackPost() {
        Account dealer = new Account(Name = 'PostSlack Claim Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'PostSlack part';
        prod.IsActive = true;
        prod.ProductCode = 'PART-POSTSLACK-01';
        prod.CurrencyIsoCode = 'USD';
        prod.CanUseQuantitySchedule = false;
        prod.CanUseRevenueSchedule = false;
        prod.IsSerialized = false;
        prod.IsCertified = false;
        prod.IsEnvrPrtcRegCompliant = false;
        prod.IsAssetizable = true;
        prod.IsSoldOnlyWithOtherProds = false;
        prod.IsShippingChargeNotApplicable = false;
        prod.WC_Product_Amount__c = 100;
        prod.WC_Labour_Charge_per_hour__c = 50;
        insert prod;
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD postslack', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset postslack',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle postslack',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '1HGCV1F33NA000222',
            IsRecallOpen = false,
            IsTelematicsServiceActive = false,
            IsConnectedServiceActive = false,
            CurrentOwnerId = dealer.Id,
            ManufacturerWarrantyEndDate = Date.today().addYears(1),
            ActiveWarrantyCount = 1
        );
        insert veh;

        WC_CreateClaimIntakeAction.WC_Request cr = new WC_CreateClaimIntakeAction.WC_Request();
        cr.dealerAccountId = dealer.Id;
        cr.vehicleId = veh.Id;
        cr.productId = prod.Id;
        cr.faultDescription = 'PostSlack test fault';
        cr.vin = '1HGCV1F33NA000222';
        cr.submissionChannel = 'Web';

        WC_CreateClaimIntakeAction.WC_Result out = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ cr }
        )[0];
        System.assert(out.success, String.valueOf(out.errorMessage));
        return out.claimId;
    }

    private class SlackOkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(req.getEndpoint().contains('hooks.slack.com'));
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getBody().contains('"text"'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true,"channel":"C0MOCK01","ts":"1234567890.000001"}');
            return res;
        }
    }

    private class SlackErrMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('invalid_payload');
            return res;
        }
    }

    @isTest
    static void post_success_with_url_and_blocks() {
        Test.setMock(HttpCalloutMock.class, new SlackOkMock());
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'Hello';
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';
        req.blocksArrayJson = '[{"type":"section","text":{"type":"mrkdwn","text":"*Hi*"}}]';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success);
        System.assertEquals(200, r.httpStatusCode);
    }

    @isTest
    static void post_success_slack_message_json_wrapper() {
        Test.setMock(HttpCalloutMock.class, new SlackOkMock());
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'Fallback';
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';
        req.slackMessageJson = '{"blocks":[{"type":"divider"}]}';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success);
    }

    @isTest
    static void post_http_error() {
        Test.setMock(HttpCalloutMock.class, new SlackErrMock());
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'X';
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assertEquals(400, r.httpStatusCode);
        System.assert(String.isNotBlank(r.errorMessage));
    }

    @isTest
    static void post_missing_fallback() {
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Fallback'));
    }

    @isTest
    static void post_invalid_blocks_json() {
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'T';
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';
        req.blocksArrayJson = 'not-json';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Invalid blocks'));
    }

    @isTest
    static void post_non_https_url() {
        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'T';
        req.webhookUrl = 'http://hooks.slack.com/services/X';

        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('https'));
    }

    @isTest
    static void post_with_claim_id_persists_slack_pointer() {
        Test.setMock(HttpCalloutMock.class, new SlackOkMock());
        Id claimId = createTestClaimIdForSlackPost();

        WC_PostSlackWebhookMessageAction.WC_Request req = new WC_PostSlackWebhookMessageAction.WC_Request();
        req.fallbackText = 'Hello';
        req.webhookUrl = 'https://hooks.slack.com/services/TEST/TEST/TEST';
        req.blocksArrayJson = '[{"type":"section","text":{"type":"mrkdwn","text":"*Hi*"}}]';
        req.claimId = claimId;

        Test.startTest();
        WC_PostSlackWebhookMessageAction.WC_Result r = WC_PostSlackWebhookMessageAction.post(
            new List<WC_PostSlackWebhookMessageAction.WC_Request>{ req }
        )[0];
        Test.stopTest();

        System.assertEquals(true, r.success);

        Claim c = [
            SELECT WC_Slack_Channel_Id__c, WC_Slack_Message_Ts__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('C0MOCK01', c.WC_Slack_Channel_Id__c);
        System.assertEquals('1234567890.000001', c.WC_Slack_Message_Ts__c);
    }
}
