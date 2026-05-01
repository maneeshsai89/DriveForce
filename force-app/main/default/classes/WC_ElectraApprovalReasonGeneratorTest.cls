/**
 * WC — Tests for WC_ElectraApprovalReasonGenerator (bypass path; no Einstein in unit tests).
 */
@isTest
private class WC_ElectraApprovalReasonGeneratorTest {
    @isTest
    static void generate_null_claim_returns_default() {
        System.assertEquals(
            WC_ElectraAutoApproveProcessor.DEFAULT_REASON,
            WC_ElectraApprovalReasonGenerator.generate(null)
        );
    }

    @isTest
    static void generate_bypass_returns_test_string() {
        WC_ElectraApprovalReasonGenerator.bypassPromptForTest = true;
        Account dealer = new Account(Name = 'Reason Gen Dealer');
        insert dealer;
        Product2 prod = new Product2(
            Name = 'Reason part',
            IsActive = true,
            ProductCode = 'PART-REASON-01',
            CurrencyIsoCode = 'USD',
            CanUseQuantitySchedule = false,
            CanUseRevenueSchedule = false,
            IsSerialized = false,
            IsCertified = false,
            IsEnvrPrtcRegCompliant = false,
            IsAssetizable = true,
            IsSoldOnlyWithOtherProds = false,
            IsShippingChargeNotApplicable = false,
            WC_Product_Amount__c = 50,
            WC_Labour_Charge_per_hour__c = 25
        );
        insert prod;
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD reason', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset reason',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle reason',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '1HGCV1F33NA000444',
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
        r.faultDescription = 'Reason test';
        r.vin = '1HGCV1F33NA000444';
        r.submissionChannel = 'Web';
        Id claimId = WC_CreateClaimIntakeAction.createWC(new List<WC_CreateClaimIntakeAction.WC_Request>{ r })[0].claimId;

        String out = WC_ElectraApprovalReasonGenerator.generate(claimId);
        WC_ElectraApprovalReasonGenerator.bypassPromptForTest = false;

        System.assertEquals('Test Electra LLM reason.', out);
    }
}
