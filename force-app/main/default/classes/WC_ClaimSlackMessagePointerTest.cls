/**
 * WC — Tests for WC_ClaimSlackMessagePointer.
 */
@isTest
private class WC_ClaimSlackMessagePointerTest {
    private static Id createTestClaimId() {
        Account dealer = new Account(Name = 'Pointer Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Pointer part';
        prod.IsActive = true;
        prod.ProductCode = 'PART-POINTER-01';
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
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD pointer', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset pointer',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle pointer',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '1HGCV1F33NA000111',
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
        r.faultDescription = 'Pointer test fault';
        r.vin = '1HGCV1F33NA000111';
        r.submissionChannel = 'Web';

        WC_CreateClaimIntakeAction.WC_Result out = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ r }
        )[0];
        System.assert(out.success, String.valueOf(out.errorMessage));
        return out.claimId;
    }

    @isTest
    static void persist_writes_channel_and_ts() {
        Id claimId = createTestClaimId();

        WC_ClaimSlackMessagePointer.persistFromWebhookResponse(
            claimId,
            '{"ok":true,"channel":"C0TESTCHAN","ts":"1234567890.123456"}'
        );

        Claim row = [
            SELECT WC_Slack_Channel_Id__c, WC_Slack_Message_Ts__c, WC_Electra_Auto_Check_At__c
            FROM Claim
            WHERE Id = :claimId
        ];
        System.assertEquals('C0TESTCHAN', row.WC_Slack_Channel_Id__c);
        System.assertEquals('1234567890.123456', row.WC_Slack_Message_Ts__c);
        System.assertNotEquals(null, row.WC_Electra_Auto_Check_At__c);
        System.assert(row.WC_Electra_Auto_Check_At__c > System.now(), 'Electra check should be ~now+1m');
    }

    @isTest
    static void persist_plain_ok_string_no_op() {
        Id claimId = createTestClaimId();

        WC_ClaimSlackMessagePointer.persistFromWebhookResponse(claimId, 'ok');

        Claim row = [SELECT WC_Slack_Channel_Id__c FROM Claim WHERE Id = :claimId];
        System.assertEquals(null, row.WC_Slack_Channel_Id__c);
    }

    @isTest
    static void persist_ok_false_no_op() {
        Id claimId = createTestClaimId();

        WC_ClaimSlackMessagePointer.persistFromWebhookResponse(claimId, '{"ok":false,"channel":"C1"}');

        Claim row = [SELECT WC_Slack_Channel_Id__c FROM Claim WHERE Id = :claimId];
        System.assertEquals(null, row.WC_Slack_Channel_Id__c);
    }
}
