/**
 * WC — Tests for WC_GetApproverContextAction.
 */
@isTest
private class WC_GetApproverContextActionTest {
    @testSetup
    static void setupData() {
        Account dealer = new Account(Name = 'UC2 Context Motors');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Part UC2';
        prod.IsActive = true;
        prod.ProductCode = 'PART-UC2-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'UC2 definition', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'UC2 asset',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'UC2 vehicle',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '1HGCM82633A009999',
            IsRecallOpen = false,
            IsTelematicsServiceActive = false,
            IsConnectedServiceActive = false,
            CurrentOwnerId = dealer.Id,
            ManufacturerWarrantyEndDate = Date.today().addYears(1),
            ActiveWarrantyCount = 1
        );
        insert veh;
    }

    @isTest
    static void get_context_success() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'UC2 Context Motors' LIMIT 1];
        Vehicle v = [
            SELECT Id
            FROM Vehicle
            WHERE VehicleIdentificationNumber = '1HGCM82633A009999'
            LIMIT 1
        ];
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'PART-UC2-01' LIMIT 1];

        WC_CreateClaimIntakeAction.WC_Request cr = new WC_CreateClaimIntakeAction.WC_Request();
        cr.dealerAccountId = dealer.Id;
        cr.vehicleId = v.Id;
        cr.productId = p.Id;
        cr.faultDescription = 'Test fault UC2';
        cr.vin = '1HGCM82633A009999';
        cr.submissionChannel = 'WhatsApp';
        cr.estimatedAmount = 5000;
        cr.aiRiskScore = 22;

        WC_CreateClaimIntakeAction.WC_Result created = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ cr }
        )[0];
        System.assert(created.success, created.errorMessage);

        WC_GetApproverContextAction.WC_Request req = new WC_GetApproverContextAction.WC_Request();
        req.claimId = created.claimId;

        WC_GetApproverContextAction.WC_Result r = WC_GetApproverContextAction.getContext(
            new List<WC_GetApproverContextAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success);
        System.assertNotEquals(null, r.dealerInsightsNarrative);
        System.assertNotEquals(null, r.claimContextBlock);
        System.assertEquals('Low', r.riskLabel);
    }

    @isTest
    static void get_context_invalid_id() {
        WC_GetApproverContextAction.WC_Request req = new WC_GetApproverContextAction.WC_Request();
        req.claimId = UserInfo.getUserId();
        WC_GetApproverContextAction.WC_Result r = WC_GetApproverContextAction.getContext(
            new List<WC_GetApproverContextAction.WC_Request>{ req }
        )[0];
        System.assertEquals(false, r.success);
    }
}
