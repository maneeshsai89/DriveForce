/**
 * WC — Tests for WC_GenerateApproverSummaryAction (negative paths + test bypass).
 */
@isTest
private class WC_GenerateApproverSummaryActionTest {
    @isTest
    static void generate_blank_claim_id() {
        WC_GenerateApproverSummaryAction.WC_Request req = new WC_GenerateApproverSummaryAction.WC_Request();
        WC_GenerateApproverSummaryAction.WC_Result r = WC_GenerateApproverSummaryAction.generate(
            new List<WC_GenerateApproverSummaryAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
    }

    @isTest
    static void generate_bypass_persist() {
        Account dealer = new Account(Name = 'UC2 Gen Motors');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Part Gen';
        prod.IsActive = true;
        prod.ProductCode = 'PART-GEN-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'Gen def', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Gen asset',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Gen veh',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '2HGCM82633A008888',
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
        cr.faultDescription = 'Gen fault';
        cr.vin = '2HGCM82633A008888';
        cr.submissionChannel = 'Web';

        String claimId = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ cr }
        )[0]
            .claimId;

        WC_GenerateApproverSummaryAction.bypassPromptForTest = true;
        WC_GenerateApproverSummaryAction.WC_Request req = new WC_GenerateApproverSummaryAction.WC_Request();
        req.claimId = claimId;
        req.persistToClaim = true;

        WC_GenerateApproverSummaryAction.WC_Result r = WC_GenerateApproverSummaryAction.generate(
            new List<WC_GenerateApproverSummaryAction.WC_Request>{ req }
        )[0];
        WC_GenerateApproverSummaryAction.bypassPromptForTest = false;

        System.assertEquals(true, r.success);
        System.assertEquals(42, r.riskScore);
        Claim c = [SELECT WC_AI_Summary__c, WC_AI_Recommendation__c, WC_AI_Risk_Score__c FROM Claim WHERE Id = :claimId];
        System.assertNotEquals(null, c.WC_AI_Summary__c);
        System.assertEquals('Review', c.WC_AI_Recommendation__c);
        System.assertEquals(42, c.WC_AI_Risk_Score__c);
    }
}
