/**
 * WC — Tests for WC_ElectraAutoApproveProcessor.
 */
@isTest
private class WC_ElectraAutoApproveProcessorTest {
    private static Id createLowRiskClaim() {
        Account dealer = new Account(Name = 'Electra Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Electra part';
        prod.IsActive = true;
        prod.ProductCode = 'PART-ELECTRA-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD electra', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset electra',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle electra',
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

        WC_CreateClaimIntakeAction.WC_Request r = new WC_CreateClaimIntakeAction.WC_Request();
        r.dealerAccountId = dealer.Id;
        r.vehicleId = veh.Id;
        r.productId = prod.Id;
        r.faultDescription = 'Electra test';
        r.vin = '1HGCV1F33NA000333';
        r.submissionChannel = 'Web';

        WC_CreateClaimIntakeAction.WC_Result out = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ r }
        )[0];
        System.assert(out.success, String.valueOf(out.errorMessage));
        return out.claimId;
    }

    private class SlackChatUpdateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(req.getEndpoint().contains('slack.com/api/chat.update'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @isTest
    static void process_approves_low_risk_due_claim() {
        WC_ElectraApprovalReasonGenerator.bypassPromptForTest = true;
        Id claimId = createLowRiskClaim();
        Claim c = new Claim(
            Id = claimId,
            WC_AI_Risk_Score__c = 40,
            WC_Electra_Auto_Check_At__c = System.now().addMinutes(-1),
            WC_Slack_Channel_Id__c = 'C0ELECTRA',
            WC_Slack_Message_Ts__c = '1234567890.000001'
        );
        update c;

        Test.setMock(HttpCalloutMock.class, new SlackChatUpdateMock());
        Test.startTest();
        WC_ElectraAutoApproveProcessor.processDueClaims();
        Test.stopTest();

        Claim r = [
            SELECT WC_Approval_Result__c, WC_Approval_Channel__c, WC_Approved_At__c, WC_Electra_Auto_Check_At__c, WC_Electra_Auto_Notes__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('Approved', r.WC_Approval_Result__c);
        System.assertEquals('Electra', r.WC_Approval_Channel__c);
        System.assertNotEquals(null, r.WC_Approved_At__c);
        System.assertEquals(null, r.WC_Electra_Auto_Check_At__c);
        System.assertEquals('Test Electra LLM reason.', r.WC_Electra_Auto_Notes__c);
    }

    @isTest
    static void process_skips_high_risk_and_clears_schedule() {
        WC_ElectraApprovalReasonGenerator.bypassPromptForTest = true;
        Id claimId = createLowRiskClaim();
        update new Claim(
            Id = claimId,
            WC_AI_Risk_Score__c = 80,
            WC_Electra_Auto_Check_At__c = System.now().addMinutes(-1)
        );

        WC_ElectraAutoApproveProcessor.processDueClaims();

        Claim r = [
            SELECT WC_Approval_Result__c, WC_Electra_Auto_Check_At__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('Pending', r.WC_Approval_Result__c);
        System.assertEquals(null, r.WC_Electra_Auto_Check_At__c);
    }

    @isTest
    static void process_skips_null_risk_and_clears_schedule() {
        WC_ElectraApprovalReasonGenerator.bypassPromptForTest = true;
        Id claimId = createLowRiskClaim();
        update new Claim(Id = claimId, WC_Electra_Auto_Check_At__c = System.now().addMinutes(-1));

        WC_ElectraAutoApproveProcessor.processDueClaims();

        Claim r = [SELECT WC_Approval_Result__c, WC_Electra_Auto_Check_At__c FROM Claim WHERE Id = :claimId];
        System.assertEquals('Pending', r.WC_Approval_Result__c);
        System.assertEquals(null, r.WC_Electra_Auto_Check_At__c);
    }
}
