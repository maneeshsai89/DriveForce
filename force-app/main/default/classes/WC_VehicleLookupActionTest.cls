/**
 * WC — Tests for WC_VehicleLookupAction.
 */
@isTest
private class WC_VehicleLookupActionTest {
    @testSetup
    static void setupData() {
        Account dealer = new Account(Name = 'Pacific Rim Subaru');
        insert dealer;
        Product2 prod = new Product2(Name = 'Forester base trim', IsActive = true, ProductCode = 'VEH-FOR-TEST-01');
        insert prod;
        VehicleDefinition vd = new VehicleDefinition(Name = 'Forester — fifth generation', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Fleet loaner — unit 12',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = '2024 Forester Sport — evaluation',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = 'JF2SKAJC1KH123456',
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
    static void lookup_found_returns_context() {
        WC_VehicleLookupAction.WC_Request req = new WC_VehicleLookupAction.WC_Request();
        req.vin = 'JF2SKAJC1KH123456';
        List<WC_VehicleLookupAction.WC_Result> results = WC_VehicleLookupAction.lookupWC(
            new List<WC_VehicleLookupAction.WC_Request>{ req }
        );
        System.assertEquals(1, results.size(), 'One result row');
        System.assertEquals(true, results[0].found, 'Vehicle should be found');
        System.assertEquals('Pacific Rim Subaru', results[0].dealerName);
        System.assertEquals('Active', results[0].warrantyStatus);
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Pacific Rim Subaru' LIMIT 1];
        Vehicle veh = [
            SELECT Id, CurrentOwnerId
            FROM Vehicle
            WHERE VehicleIdentificationNumber = 'JF2SKAJC1KH123456'
            LIMIT 1
        ];
        System.assertEquals(veh.Id, results[0].vehicleId);
        System.assertEquals(dealer.Id, results[0].dealerAccountId);
    }

    @isTest
    static void lookup_unknown_vin_not_found() {
        WC_VehicleLookupAction.WC_Request req = new WC_VehicleLookupAction.WC_Request();
        req.vin = 'ZZZZZZZZZZZZZZZZZ';
        List<WC_VehicleLookupAction.WC_Result> results = WC_VehicleLookupAction.lookupWC(
            new List<WC_VehicleLookupAction.WC_Request>{ req }
        );
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].found);
    }

    @isTest
    static void lookup_blank_vin_not_found() {
        WC_VehicleLookupAction.WC_Request req = new WC_VehicleLookupAction.WC_Request();
        req.vin = '   ';
        List<WC_VehicleLookupAction.WC_Result> results = WC_VehicleLookupAction.lookupWC(
            new List<WC_VehicleLookupAction.WC_Request>{ req }
        );
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].found);
    }

    @isTest
    static void lookup_null_list_returns_empty() {
        System.assertEquals(0, WC_VehicleLookupAction.lookupWC(null).size());
    }
}
