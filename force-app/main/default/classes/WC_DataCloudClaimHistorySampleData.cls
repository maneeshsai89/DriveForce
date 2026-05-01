/**
 * WC — Seeds multiple dealers, vehicles, and historical Claims + ClaimItems for Data Cloud Calculated Insights
 * (rolling windows, last claim date, approval/rejection rates, repeat part issues).
 *
 * Uses WC_Claim_Effective_Date__c and WC_Approval_Result__c for analytics (CreatedDate is not backdated in Apex).
 *
 * Run as admin: sf apex run -f scripts/apex/wc_datacloud_claim_history_seed.apex -o <alias>
 */
public without sharing class WC_DataCloudClaimHistorySampleData {
    /** First dealer name — used for idempotent check (do not rename after seed without cleanup). */
    public static final String MARKER_DEALER_NAME = 'Summit Motors Portland';
    public static final String DEALER_NAME_SEATTLE = 'Lakeside Auto Group Seattle';
    public static final String DEALER_NAME_SACRAMENTO = 'Riverside Chevrolet Sacramento';
    public static final String PRODUCT_VEHICLE_CODE = 'VEH-AURORA-EV500';
    public static final String PRODUCT_PART_CODE = 'PART-HV-BATT-ASM';

    public class ClaimSeed {
        public Integer vehicleSlot;
        public Integer daysAgo;
        public String approvalResult;
        public Decimal estimatedAmount;
        public String summary;
        public Boolean sameRepeatFault;
    }

    /**
     * Idempotent: if marker dealer already exists, returns a message and does not duplicate.
     */
    public static String seedDealerClaimHistory() {
        List<Account> existing = [
            SELECT Id
            FROM Account
            WHERE Name = :MARKER_DEALER_NAME
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return 'Claim history seed already present. Remove Accounts: "'
                + MARKER_DEALER_NAME
                + '", "'
                + DEALER_NAME_SEATTLE
                + '", "'
                + DEALER_NAME_SACRAMENTO
                + '" to re-run.';
        }

        List<Account> dealers = new List<Account>();
        dealers.add(new Account(Name = MARKER_DEALER_NAME));
        dealers.add(new Account(Name = DEALER_NAME_SEATTLE));
        dealers.add(new Account(Name = DEALER_NAME_SACRAMENTO));
        insert dealers;

        Product2 vehicleSku = buildVehicleProduct();
        vehicleSku.ProductCode = PRODUCT_VEHICLE_CODE;
        vehicleSku.Name = 'Aurora EV-500 Premium';
        insert vehicleSku;

        Product2 partSku = buildPartProduct();
        partSku.ProductCode = PRODUCT_PART_CODE;
        partSku.Name = 'High-voltage battery assembly';
        insert partSku;

        VehicleDefinition vd = new VehicleDefinition(Name = 'Aurora EV-500 — all trims', ProductId = vehicleSku.Id);
        insert vd;

        Date startDt = Date.today().addYears(-1);
        Date endDt = Date.today().addYears(2);
        WarrantyTerm wt = new WarrantyTerm();
        wt.WarrantyTermName = '36-month standard limited warranty';
        wt.WarrantyType = 'Standard';
        wt.IsActive = true;
        wt.WarrantyDuration = 36;
        wt.WarrantyUnitOfTime = 'Months';
        wt.EffectiveStartDate = 'Purchase Date';
        wt.IsTransferable = true;
        wt.Description = 'Factory limited warranty for new vehicle retail sales.';
        insert wt;

        List<Vehicle> vehicles = new List<Vehicle>();
        // Vehicle slots 1–2 → Portland, 3–4 → Seattle, 5–6 → Sacramento
        List<Account> dealerBySlot = new List<Account>{
            dealers[0],
            dealers[0],
            dealers[1],
            dealers[1],
            dealers[2],
            dealers[2]
        };

        for (Integer slot = 1; slot <= 6; slot++) {
            Account dealer = dealerBySlot[slot - 1];
            Asset ast = new Asset(
                Name = 'Customer vehicle — registered unit ' + slot,
                AccountId = dealer.Id,
                OwnerId = UserInfo.getUserId(),
                Product2Id = vehicleSku.Id,
                IsCompetitorProduct = false,
                IsInternal = false,
                IsRecallOpen = false
            );
            insert ast;

            AssetWarranty aw = new AssetWarranty();
            aw.AssetId = ast.Id;
            aw.WarrantyTermId = wt.Id;
            aw.StartDate = startDt;
            aw.EndDate = endDt;
            insert aw;

            Vehicle veh = new Vehicle();
            veh.Name = '2024 Aurora EV-500 — Unit ' + slot;
            veh.AssetId = ast.Id;
            veh.VehicleDefinitionId = vd.Id;
            veh.VehicleIdentificationNumber = buildVin(slot);
            veh.IsRecallOpen = false;
            veh.IsTelematicsServiceActive = false;
            veh.IsConnectedServiceActive = false;
            veh.CurrentOwnerId = dealer.Id;
            veh.ManufacturerWarrantyEndDate = endDt;
            veh.ActiveWarrantyCount = 1;
            insert veh;
            vehicles.add(veh);
        }

        List<ClaimSeed> plan = buildClaimPlan();
        List<Claim> claimsToInsert = new List<Claim>();
        List<ClaimItem> itemsToInsert = new List<ClaimItem>();

        Integer seq = 0;
        for (ClaimSeed cs : plan) {
            Vehicle v = vehicles[cs.vehicleSlot - 1];

            Claim c = new Claim();
            c.AccountId = v.CurrentOwnerId;
            c.OwnerId = UserInfo.getUserId();
            c.Name =
                'WTY-' +
                String.valueOf(seq) +
                '-' +
                String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));
            c.Summary = cs.summary;
            c.IsInhabitable = false;
            c.IsDrivable = true;
            c.IsAuthoritiesNotified = false;
            c.Status = 'Submitted';
            c.EstimatedAmount = cs.estimatedAmount;
            c.WC_Claim_Source__c = 'Manual';
            c.WC_Submission_Channel__c = 'Web';
            c.WC_Claim_Effective_Date__c = Date.today().addDays(-cs.daysAgo);
            c.WC_Approval_Result__c = cs.approvalResult;
            claimsToInsert.add(c);
            seq++;
        }
        insert claimsToInsert;

        Integer idx = 0;
        for (ClaimSeed cs : plan) {
            Claim c = claimsToInsert[idx];
            Vehicle v = vehicles[cs.vehicleSlot - 1];
            ClaimItem line = new ClaimItem();
            line.ClaimId = c.Id;
            line.Name = 'Line 1';
            line.VehicleId = v.Id;
            line.ProductId = partSku.Id;
            line.Description = cs.sameRepeatFault == true ? 'Battery range degradation (recurring)' : cs.summary;
            line.FaultDate = Datetime.newInstance(c.WC_Claim_Effective_Date__c, Time.newInstance(12, 0, 0, 0));
            line.WC_Labour_Hours__c = 2 + Math.mod(idx, 5);
            itemsToInsert.add(line);
            idx++;
        }
        insert itemsToInsert;

        return 'Claim history seed complete.\n'
            + 'Dealers: '
            + MARKER_DEALER_NAME
            + ', '
            + DEALER_NAME_SEATTLE
            + ', '
            + DEALER_NAME_SACRAMENTO
            + '\n'
            + 'Vehicles: 6 (Aurora EV-500, VIN prefix 1HGCV1F3…)\n'
            + 'Claims: '
            + claimsToInsert.size()
            + ' with WC_Claim_Effective_Date__c and WC_Approval_Result__c.\n'
            + 'Connect CRM to Data Cloud and create Calculated Insights per data-cloud/README.md';
    }

    @TestVisible
    private static List<ClaimSeed> buildClaimPlanForTest() {
        return buildClaimPlan();
    }

    private static List<ClaimSeed> buildClaimPlan() {
        List<ClaimSeed> plan = new List<ClaimSeed>();
        // Portland (vehicles 1–2): repeat battery issues on vehicle 1
        add(plan, 1, 5, 'Approved', 4200, 'HV battery warning light', true);
        add(plan, 1, 18, 'Approved', 4100, 'Range loss in cold weather', true);
        add(plan, 1, 40, 'Rejected', 9000, 'Out-of-warranty battery replacement request', true);
        add(plan, 2, 12, 'Pending', 2100, 'Infotainment system reboot', false);
        add(plan, 1, 75, 'Approved', 3800, 'Battery cell imbalance reported', true);
        add(plan, 2, 8, 'Rejected', 1500, 'Cosmetic trim damage', false);
        add(plan, 1, 25, 'Pending', 3300, 'DC charging slower than expected', true);
        add(plan, 2, 55, 'Approved', 2700, 'Software update required', false);
        // Seattle (vehicles 3–4)
        add(plan, 3, 10, 'Approved', 5000, 'Drive motor noise under load', false);
        add(plan, 4, 22, 'Rejected', 1200, 'Tire wear — not covered', false);
        add(plan, 3, 45, 'Approved', 6200, 'Coolant leak at inverter', false);
        add(plan, 4, 88, 'Approved', 3000, 'Climate AC weak cooling', false);
        add(plan, 3, 3, 'Pending', 800, 'Dashboard rattle', false);
        // Sacramento (vehicles 5–6)
        add(plan, 5, 7, 'Rejected', 4000, 'Aftermarket battery voids warranty', false);
        add(plan, 6, 35, 'Approved', 4500, 'Brake actuator fault', false);
        add(plan, 5, 62, 'Approved', 5100, 'Steering calibration required', false);
        add(plan, 6, 15, 'Pending', 2200, 'Parking sensor fault', false);
        add(plan, 5, 28, 'Approved', 3900, 'Second battery-related claim on same dealer group', true);
        add(plan, 6, 50, 'Rejected', 900, 'Windshield stress crack — not covered', false);
        return plan;
    }

    private static void add(
        List<ClaimSeed> plan,
        Integer vehicleSlot,
        Integer daysAgo,
        String approvalResult,
        Decimal amount,
        String summary,
        Boolean repeatFault
    ) {
        ClaimSeed cs = new ClaimSeed();
        cs.vehicleSlot = vehicleSlot;
        cs.daysAgo = daysAgo;
        cs.approvalResult = approvalResult;
        cs.estimatedAmount = amount;
        cs.summary = summary;
        cs.sameRepeatFault = repeatFault;
        plan.add(cs);
    }

    /** 17-character VIN-style identifier (synthetic, for testing only). */
    private static String buildVin(Integer slot) {
        String suffix = String.valueOf(10000000 + slot);
        return '1HGCV1F3' + suffix;
    }

    private static Product2 buildVehicleProduct() {
        Product2 p = new Product2();
        p.IsActive = true;
        String cur = UserInfo.getDefaultCurrency();
        p.CurrencyIsoCode = String.isBlank(cur) ? 'USD' : cur;
        p.CanUseQuantitySchedule = false;
        p.CanUseRevenueSchedule = false;
        p.IsSerialized = false;
        p.IsCertified = false;
        p.IsEnvrPrtcRegCompliant = false;
        p.IsAssetizable = true;
        p.IsSoldOnlyWithOtherProds = false;
        p.IsShippingChargeNotApplicable = false;
        return p;
    }

    private static Product2 buildPartProduct() {
        Product2 p = buildVehicleProduct();
        p.WC_Model_Compatibility__c = 'Aurora EV-500; EV-500 Premium';
        p.WC_Fault_Keywords__c =
            'battery; high voltage; range; degradation; thermal; BMS; ' + PRODUCT_PART_CODE;
        return p;
    }
}
