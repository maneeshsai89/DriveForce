/**
 * WC — Tests for WC_CreateClaimIntakeAction.
 */
@isTest
private class WC_CreateClaimIntakeActionTest {
    @testSetup
    static void setupData() {
        Account dealer = new Account(Name = 'Cascade Valley Motors');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'HV battery assembly — intake test';
        prod.IsActive = true;
        prod.ProductCode = 'PART-INTAKE-TEST-01';
        prod.CurrencyIsoCode = 'USD';
        prod.CanUseQuantitySchedule = false;
        prod.CanUseRevenueSchedule = false;
        prod.IsSerialized = false;
        prod.IsCertified = false;
        prod.IsEnvrPrtcRegCompliant = false;
        prod.IsAssetizable = true;
        prod.IsSoldOnlyWithOtherProds = false;
        prod.IsShippingChargeNotApplicable = false;
        prod.WC_Product_Amount__c = 1000;
        prod.WC_Labour_Charge_per_hour__c = 50;
        insert prod;
        VehicleDefinition vd = new VehicleDefinition(Name = 'Aurora sedan — test definition', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Service loaner — unit 1',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = '2023 Aurora sedan — intake test',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '2HGFG12609H501234',
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
    static void create_intake_success() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Cascade Valley Motors' LIMIT 1];
        Vehicle v = [
            SELECT Id
            FROM Vehicle
            WHERE VehicleIdentificationNumber = '2HGFG12609H501234'
            LIMIT 1
        ];
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'PART-INTAKE-TEST-01' LIMIT 1];

        WC_CreateClaimIntakeAction.WC_Request req = new WC_CreateClaimIntakeAction.WC_Request();
        req.dealerAccountId = dealer.Id;
        req.vehicleId = v.Id;
        req.productId = p.Id;
        req.faultDescription = 'Battery range degradation';
        req.vin = '2HGFG12609H501234';
        req.submissionChannel = 'WhatsApp';
        req.labourHours = 3.5;
        req.mileageAtClaim = 28450;
        req.aiRiskScore = 18;

        List<WC_CreateClaimIntakeAction.WC_Result> results = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ req }
        );
        System.assertEquals(1, results.size());
        System.assert(results[0].success, String.valueOf(results[0].errorMessage));
        System.assertNotEquals(null, results[0].claimId);
        System.assertNotEquals(null, results[0].claimName);

        Claim c = [
            SELECT
                Id,
                EstimatedAmount,
                WC_Claim_Source__c,
                WC_Submission_Channel__c,
                WC_AI_Risk_Score__c,
                WC_Claim_Effective_Date__c,
                WC_Approval_Result__c
            FROM Claim
            WHERE Id = :results[0].claimId
        ];
        System.assertEquals(1000 + (50 * 3.5), c.EstimatedAmount, 'WC_Product_Amount + hours × WC_Labour_Charge_per_hour');
        System.assertEquals('Agentforce', c.WC_Claim_Source__c);
        System.assertEquals('WhatsApp', c.WC_Submission_Channel__c);
        System.assertEquals(Date.today(), c.WC_Claim_Effective_Date__c);
        System.assertEquals('Pending', c.WC_Approval_Result__c);
        System.assertNotEquals(null, c.WC_AI_Risk_Score__c);
        System.assertEquals(18, c.WC_AI_Risk_Score__c.intValue());
    }

    @isTest
    static void create_intake_uses_estimated_override_when_formula_zero() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Cascade Valley Motors' LIMIT 1];
        Vehicle v = [
            SELECT Id
            FROM Vehicle
            WHERE VehicleIdentificationNumber = '2HGFG12609H501234'
            LIMIT 1
        ];
        Product2 zeroPriced = new Product2(
            Name = 'Zero-priced part — override test',
            IsActive = true,
            ProductCode = 'PART-ZERO-OVERRIDE',
            CurrencyIsoCode = 'USD',
            CanUseQuantitySchedule = false,
            CanUseRevenueSchedule = false,
            IsSerialized = false,
            IsCertified = false,
            IsEnvrPrtcRegCompliant = false,
            IsAssetizable = true,
            IsSoldOnlyWithOtherProds = false,
            IsShippingChargeNotApplicable = false,
            WC_Product_Amount__c = 0,
            WC_Labour_Charge_per_hour__c = 0
        );
        insert zeroPriced;

        WC_CreateClaimIntakeAction.WC_Request req = new WC_CreateClaimIntakeAction.WC_Request();
        req.dealerAccountId = dealer.Id;
        req.vehicleId = v.Id;
        req.productId = zeroPriced.Id;
        req.faultDescription = 'Test';
        req.vin = '2HGFG12609H501234';
        req.submissionChannel = 'Web';
        req.labourHours = 0;
        req.estimatedAmount = 999;

        List<WC_CreateClaimIntakeAction.WC_Result> results = WC_CreateClaimIntakeAction.createWC(
            new List<WC_CreateClaimIntakeAction.WC_Request>{ req }
        );
        System.assert(results[0].success, String.valueOf(results[0].errorMessage));
        Claim c = [SELECT EstimatedAmount FROM Claim WHERE Id = :results[0].claimId];
        System.assertEquals(999, c.EstimatedAmount);
    }
}
