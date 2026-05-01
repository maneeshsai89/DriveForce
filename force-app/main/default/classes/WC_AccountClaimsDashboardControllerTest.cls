/**
 * WC — Tests for WC_AccountClaimsDashboardController.
 */
@isTest
private class WC_AccountClaimsDashboardControllerTest {
    @isTest
    static void getClaimMetricsByAccount_null_returns_zeros() {
        WC_AccountClaimsDashboardController.Metrics m = WC_AccountClaimsDashboardController.getClaimMetricsByAccount(
            null
        );
        System.assertEquals(0, m.totalRaised);
        System.assertEquals(0, m.pendingCount);
        System.assertEquals(0, m.approvedCount);
        System.assertEquals(0, m.rejectedCount);
        System.assertEquals(0, m.claimsThisMonth);
    }

    @isTest
    static void getClaimMetricsByAccount_counts_by_approval_result() {
        Account dealer = new Account(Name = 'Dashboard Metrics Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Dashboard test part';
        prod.IsActive = true;
        prod.ProductCode = 'PART-DASH-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD dash test', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset dash test',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle dash test',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '5YJSA1E26HF000001',
            IsRecallOpen = false,
            IsTelematicsServiceActive = false,
            IsConnectedServiceActive = false,
            CurrentOwnerId = dealer.Id,
            ManufacturerWarrantyEndDate = Date.today().addYears(1),
            ActiveWarrantyCount = 1
        );
        insert veh;

        List<Id> claimIds = new List<Id>();
        for (Integer i = 0; i < 3; i++) {
            WC_CreateClaimIntakeAction.WC_Request r = new WC_CreateClaimIntakeAction.WC_Request();
            r.dealerAccountId = dealer.Id;
            r.vehicleId = veh.Id;
            r.productId = prod.Id;
            r.faultDescription = 'Dash test fault ' + i;
            r.vin = '5YJSA1E26HF000001';
            r.submissionChannel = 'Test';
            r.estimatedAmount = 100;
            r.labourHours = 1;
            r.mileageAtClaim = 1000;
            r.aiRiskScore = 10;
            List<WC_CreateClaimIntakeAction.WC_Result> results = WC_CreateClaimIntakeAction.createWC(
                new List<WC_CreateClaimIntakeAction.WC_Request>{ r }
            );
            System.assert(results[0].success, String.valueOf(results[0].errorMessage));
            claimIds.add(results[0].claimId);
        }

        List<Claim> updates = new List<Claim>{
            new Claim(Id = claimIds[0], WC_Approval_Result__c = 'Approved'),
            new Claim(Id = claimIds[1], WC_Approval_Result__c = 'Rejected')
        };
        update updates;

        WC_AccountClaimsDashboardController.Metrics m = WC_AccountClaimsDashboardController.getClaimMetricsByAccount(
            dealer.Id
        );
        System.assertEquals(3, m.totalRaised);
        System.assertEquals(1, m.pendingCount);
        System.assertEquals(1, m.approvedCount);
        System.assertEquals(1, m.rejectedCount);
        System.assertEquals(3, m.claimsThisMonth);

        List<WC_AccountClaimsDashboardController.ClaimTableRow> listRows = WC_AccountClaimsDashboardController.listClaimsForAccount(
            dealer.Id
        );
        System.assertEquals(3, listRows.size());
        System.assertEquals('Pending', listRows[0].approvalResult, 'Newest claim last in loop stays Pending');
    }

    @isTest
    static void listClaimsForAccount_null_returns_empty() {
        System.assertEquals(
            0,
            WC_AccountClaimsDashboardController.listClaimsForAccount(null).size()
        );
    }
}