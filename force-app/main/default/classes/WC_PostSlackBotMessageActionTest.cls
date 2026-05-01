/**
 * WC — Tests for WC_PostSlackBotMessageAction (HttpCalloutMock; no real Slack).
 */
@isTest
private class WC_PostSlackBotMessageActionTest {
    private static Id createTestClaimIdForSlackPost() {
        Account dealer = new Account(Name = 'PostSlackBot Claim Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'PostSlackBot part';
        prod.IsActive = true;
        prod.ProductCode = 'PART-POSTBOT-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD postbot', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset postbot',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle postbot',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '1HGCV1F33NA000333',
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
        cr.faultDescription = 'PostSlackBot test fault';
        cr.vin = '1HGCV1F33NA000333';
        cr.submissionChannel = 'Web';

        WC_CreateClaimIntakeAction.WC_Result out = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ cr }
        )[0];
        System.assert(out.success, String.valueOf(out.errorMessage));
        return out.claimId;
    }

    private static final String MOCK_BOT_TOKEN = 'xoxb-test-mock-token';

    private class ChatPostOkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(req.getEndpoint().contains('slack.com/api/chat.postMessage'));
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getHeader('Authorization') != null && req.getHeader('Authorization').startsWith('Bearer '));
            System.assert(req.getBody().contains('"channel"'));
            System.assert(req.getBody().contains('"text"'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true,"channel":"C0BOT01","ts":"9876543210.000002","message":{}}');
            return res;
        }
    }

    private class ChatPostSlackErrMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":false,"error":"channel_not_found"}');
            return res;
        }
    }

    private class ChatPostHttpErrMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('internal_error');
            return res;
        }
    }

    @isTest
    static void post_success_with_channel_and_blocks() {
        Test.setMock(HttpCalloutMock.class, new ChatPostOkMock());
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'Hello';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';
        req.blocksArrayJson = '[{"type":"section","text":{"type":"mrkdwn","text":"*Hi*"}}]';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success);
        System.assertEquals(200, r.httpStatusCode);
    }

    @isTest
    static void post_success_slack_message_json_wrapper() {
        Test.setMock(HttpCalloutMock.class, new ChatPostOkMock());
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'Fallback';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';
        req.slackMessageJson = '{"blocks":[{"type":"divider"}]}';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success);
    }

    @isTest
    static void post_slack_api_ok_false() {
        Test.setMock(HttpCalloutMock.class, new ChatPostSlackErrMock());
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'X';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assertEquals(200, r.httpStatusCode);
        System.assert(r.responseBody != null && r.responseBody.contains('channel_not_found'));
    }

    @isTest
    static void post_http_500() {
        Test.setMock(HttpCalloutMock.class, new ChatPostHttpErrMock());
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'X';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assertEquals(500, r.httpStatusCode);
    }

    @isTest
    static void post_missing_fallback() {
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.slackChannelId = 'C0BOT01';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Fallback'));
    }

    @isTest
    static void post_invalid_blocks_json() {
        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'T';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';
        req.blocksArrayJson = 'not-json';

        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Invalid blocks'));
    }

    @isTest
    static void slackApiOk_parses_true() {
        System.assertEquals(true, WC_PostSlackBotMessageAction.slackApiOk('{"ok":true}'));
        System.assertEquals(false, WC_PostSlackBotMessageAction.slackApiOk('{"ok":false}'));
        System.assertEquals(false, WC_PostSlackBotMessageAction.slackApiOk(''));
    }

    @isTest
    static void post_with_claim_id_persists_slack_pointer() {
        Test.setMock(HttpCalloutMock.class, new ChatPostOkMock());
        Id claimId = createTestClaimIdForSlackPost();

        WC_PostSlackBotMessageAction.WC_Request req = new WC_PostSlackBotMessageAction.WC_Request();
        req.fallbackText = 'Hello';
        req.slackBotOauthToken = MOCK_BOT_TOKEN;
        req.slackChannelId = 'C0BOT01';
        req.blocksArrayJson = '[{"type":"section","text":{"type":"mrkdwn","text":"*Hi*"}}]';
        req.claimId = claimId;

        Test.startTest();
        WC_PostSlackBotMessageAction.WC_Result r = WC_PostSlackBotMessageAction.post(
            new List<WC_PostSlackBotMessageAction.WC_Request>{ req }
        )[0];
        Test.stopTest();

        System.assertEquals(true, r.success);

        Claim c = [
            SELECT WC_Slack_Channel_Id__c, WC_Slack_Message_Ts__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('C0BOT01', c.WC_Slack_Channel_Id__c);
        System.assertEquals('9876543210.000002', c.WC_Slack_Message_Ts__c);
    }
}
