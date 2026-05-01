/**
 * WC — Tests for WC_SlackInteractivityRest (Slack Interactivity POST).
 * Signature verification is skipped in test context; production requires Slack_Signing_Secret__c.
 */
@isTest
private class WC_SlackInteractivityRestTest {
    @isTest
    static void url_verification_json_returns_challenge() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('{"type":"url_verification","challenge":"ch_test_xyz"}');
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(200, res.statusCode, res.responseBody != null ? res.responseBody.toString() : '');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals('ch_test_xyz', (String) body.get('challenge'));
    }

    @isTest
    static void url_verification_form_payload_returns_challenge() {
        String verificationJson =
            '{"type":"url_verification","token":"x","challenge":"ch_form_abc"}';
        String encoded = EncodingUtil.urlEncode(verificationJson, 'UTF-8');
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('payload=' + encoded);
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals('ch_form_abc', (String) body.get('challenge'));
    }

    @isTest
    static void block_actions_approve_invokes_flow_when_claim_exists() {
        Id claimId = createTestClaimId();
        System.assertNotEquals(null, claimId, 'WC_CreateClaimIntakeAction should create a Claim in this org.');

        String payloadJson =
            '{"type":"block_actions","user":{"id":"U1"},"actions":[{"action_id":"wc_approve_claim","value":"' +
            String.valueOf(claimId) +
            '|Approve"}]}';
        String encoded = EncodingUtil.urlEncode(payloadJson, 'UTF-8');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('payload=' + encoded);
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(200, res.statusCode);
        Claim c = [
            SELECT WC_Approval_Result__c, WC_Approval_Channel__c, WC_Approved_At__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('Approved', c.WC_Approval_Result__c);
        System.assertEquals('Slack', c.WC_Approval_Channel__c);
        System.assertNotEquals(null, c.WC_Approved_At__c);
    }

    @isTest
    static void block_actions_reject_updates_claim() {
        Id claimId = createTestClaimId();
        System.assertNotEquals(null, claimId, 'WC_CreateClaimIntakeAction should create a Claim in this org.');

        String payloadJson =
            '{"type":"block_actions","actions":[{"action_id":"wc_reject_claim","value":"' +
            String.valueOf(claimId) +
            '|Reject"}]}';
        String encoded = EncodingUtil.urlEncode(payloadJson, 'UTF-8');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('payload=' + encoded);
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(200, res.statusCode);
        Claim c = [SELECT WC_Approval_Result__c, WC_Approved_At__c FROM Claim WHERE Id = :claimId];
        System.assertEquals('Rejected', c.WC_Approval_Result__c);
        System.assertEquals(null, c.WC_Approved_At__c);
    }

    @isTest
    static void block_actions_ask_agent_returns_ok_without_flow() {
        String payloadJson =
            '{"type":"block_actions","actions":[{"action_id":"wc_ask_agent","value":"001000000000000AAA"}]}';
        String encoded = EncodingUtil.urlEncode(payloadJson, 'UTF-8');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('payload=' + encoded);
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(200, res.statusCode);
    }

    @isTest
    static void malformed_body_returns_400() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/wc/slack/interactivity';
        req.requestBody = Blob.valueOf('not_payload=1');
        RestContext.request = req;
        RestContext.response = res;

        WC_SlackInteractivityRest.handlePost();

        System.assertEquals(400, res.statusCode);
    }

    private static Id createTestClaimId() {
        try {
            Account dealer = new Account(Name = 'Slack Interact Test Dealer');
            insert dealer;
            Product2 prod = new Product2();
            prod.Name = 'Slack interact part';
            prod.IsActive = true;
            prod.ProductCode = 'PART-SLACK-INT-01';
            prod.CurrencyIsoCode = 'USD';
            prod.CanUseQuantitySchedule = false;
            prod.CanUseRevenueSchedule = false;
            prod.IsSerialized = false;
            prod.IsCertified = false;
            prod.IsEnvrPrtcRegCompliant = false;
            prod.IsAssetizable = true;
            prod.IsSoldOnlyWithOtherProds = false;
            prod.IsShippingChargeNotApplicable = false;
            insert prod;
            VehicleDefinition vd = new VehicleDefinition(Name = 'VD slack test', ProductId = prod.Id);
            insert vd;
            Asset ast = new Asset(
                Name = 'Asset slack test',
                AccountId = dealer.Id,
                OwnerId = UserInfo.getUserId(),
                IsCompetitorProduct = false,
                IsInternal = false
            );
            insert ast;
            Vehicle veh = new Vehicle(
                Name = 'Vehicle slack test',
                AssetId = ast.Id,
                VehicleDefinitionId = vd.Id,
                VehicleIdentificationNumber = '1HGBH41JXMN109992',
                IsRecallOpen = false,
                IsTelematicsServiceActive = false,
                IsConnectedServiceActive = false,
                CurrentOwnerId = dealer.Id,
                ManufacturerWarrantyEndDate = Date.today().addYears(1),
                ActiveWarrantyCount = 1
            );
            insert veh;

            WC_CreateClaimIntakeAction.WC_Request r = new WC_CreateClaimIntakeAction.WC_Request();
            r.dealerAccountId = dealer.Id;
            r.vehicleId = veh.Id;
            r.productId = prod.Id;
            r.faultDescription = 'Test fault';
            r.vin = '1HGBH41JXMN109992';
            r.submissionChannel = 'Test';
            r.estimatedAmount = 100;
            r.labourHours = 1;
            r.mileageAtClaim = 1000;
            r.aiRiskScore = 10;

            List<WC_CreateClaimIntakeAction.WC_Result> results = WC_CreateClaimIntakeAction.createWC(
                new List<WC_CreateClaimIntakeAction.WC_Request>{ r }
            );
            if (!results.isEmpty() && results[0].success && String.isNotBlank(results[0].claimId)) {
                return results[0].claimId;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WC_SlackInteractivityRestTest skip claim setup: ' + e.getMessage());
        }
        return null;
    }
}
