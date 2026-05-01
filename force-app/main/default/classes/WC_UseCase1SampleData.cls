/**
 * WC — Idempotent sample data for Use Case 1 (dealer → VIN lookup → part suggestion → claim intake).
 * Creates: Account (dealer), Product2 (vehicle + spare part), VehicleDefinition, Asset, WarrantyTerm,
 * AssetWarranty, Vehicle, and optionally a published Knowledge article for Prompt Builder / Data Library.
 *
 * Run as an admin: Developer Console → Execute Anonymous, or:
 *   sf apex run -f scripts/apex/wc_use_case1_sample_data.apex -o <orgAlias>
 */
public without sharing class WC_UseCase1SampleData {
    /** 17-char VIN-style id — idempotent seed lookup (synthetic, for testing only). */
    public static final String DEMO_VIN = '1HGCM82633A004251';
    public static final String DEALER_NAME = 'Northside Automotive Group';
    public static final String PRODUCT_VEHICLE_CODE = 'VEH-AURORA-EV500';
    public static final String PRODUCT_PART_CODE = 'PART-HV-BATT-001';
    public static final String WARRANTY_TERM_NAME = '36-Month Standard Limited Warranty';
    public static final String VEHICLE_DEF_NAME = 'Aurora EV-500';

    /**
     * Inserts demo rows if the demo VIN is not already present. Safe to call more than once.
     */
    public static String seedUseCase1() {
        List<Vehicle> existing = [
            SELECT Id, CurrentOwnerId, AssetId
            FROM Vehicle
            WHERE VehicleIdentificationNumber = :DEMO_VIN
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Vehicle ev = existing[0];
            String dealerInfo = '(unknown dealer)';
            try {
                if (ev.CurrentOwnerId != null) {
                    List<Account> accs = [
                        SELECT Id, Name
                        FROM Account
                        WHERE Id = :ev.CurrentOwnerId
                        LIMIT 1
                    ];
                    if (!accs.isEmpty()) {
                        dealerInfo = accs[0].Name + ' (' + String.valueOf(accs[0].Id) + ')';
                    } else {
                        dealerInfo = String.valueOf(ev.CurrentOwnerId);
                    }
                }
            } catch (Exception e) {
                dealerInfo = String.valueOf(ev.CurrentOwnerId);
            }
            List<Product2> parts = [
                SELECT Id
                FROM Product2
                WHERE ProductCode = :PRODUCT_PART_CODE
                LIMIT 1
            ];
            String partId = parts.isEmpty() ? '(not found — create part product)' : parts[0].Id;
            return 'Sample warranty data already exists.\n'
                + 'VIN: ' + DEMO_VIN + '\n'
                + 'Vehicle Id: ' + ev.Id + '\n'
                + 'Dealer: ' + dealerInfo + '\n'
                + 'Spare part Product2 (' + PRODUCT_PART_CODE + '): ' + partId;
        }

        Account dealer = new Account(Name = DEALER_NAME);
        insert dealer;

        Product2 vehicleSku = buildVehicleProduct();
        vehicleSku.ProductCode = PRODUCT_VEHICLE_CODE;
        insert vehicleSku;

        Product2 partSku = buildPartProduct();
        partSku.ProductCode = PRODUCT_PART_CODE;
        insert partSku;

        VehicleDefinition vd = new VehicleDefinition(Name = VEHICLE_DEF_NAME, ProductId = vehicleSku.Id);
        insert vd;

        Asset ast = new Asset(
            Name = 'Customer vehicle — Aurora EV-500',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            Product2Id = vehicleSku.Id,
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;

        Date startDt = Date.today().addYears(-1);
        Date endDt = Date.today().addYears(2);

        WarrantyTerm wt = new WarrantyTerm();
        wt.WarrantyTermName = WARRANTY_TERM_NAME;
        wt.WarrantyType = 'Standard';
        wt.IsActive = true;
        wt.WarrantyDuration = 36;
        wt.WarrantyUnitOfTime = 'Months';
        // Org-specific: EffectiveStartDate is a picklist (not a calendar date).
        wt.EffectiveStartDate = 'Purchase Date';
        wt.IsTransferable = true;
        wt.Description = 'Standard limited warranty coverage for retail new-vehicle sales.';
        insert wt;

        AssetWarranty aw = new AssetWarranty();
        aw.AssetId = ast.Id;
        aw.WarrantyTermId = wt.Id;
        aw.StartDate = startDt;
        aw.EndDate = endDt;
        insert aw;

        Vehicle veh = new Vehicle();
        veh.Name = '2024 Aurora EV-500 — retail delivery';
        veh.AssetId = ast.Id;
        veh.VehicleDefinitionId = vd.Id;
        veh.VehicleIdentificationNumber = DEMO_VIN;
        veh.IsRecallOpen = false;
        veh.IsTelematicsServiceActive = false;
        veh.IsConnectedServiceActive = false;
        veh.CurrentOwnerId = dealer.Id;
        veh.ManufacturerWarrantyEndDate = endDt;
        veh.ActiveWarrantyCount = 1;
        insert veh;

        String knowledgeNote = seedKnowledgeArticleIfPossible();

        return 'Sample warranty data created.\n'
            + 'VIN (17 chars): ' + DEMO_VIN + '\n'
            + 'Dealer Account Id: ' + dealer.Id + '\n'
            + 'Vehicle Id: ' + veh.Id + '\n'
            + 'Asset Id: ' + ast.Id + '\n'
            + 'WarrantyTerm Id: ' + wt.Id + '\n'
            + 'AssetWarranty Id: ' + aw.Id + '\n'
            + 'Spare part Product2 Id (' + PRODUCT_PART_CODE + '): ' + partSku.Id + '\n'
            + knowledgeNote;
    }

    private static Product2 buildVehicleProduct() {
        Product2 p = new Product2();
        p.Name = 'Aurora EV-500 (vehicle SKU)';
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
        p.Name = 'High-voltage battery assembly';
        p.WC_Model_Compatibility__c = 'Aurora EV-500; EV-500 Premium';
        p.WC_Fault_Keywords__c =
            'battery; high voltage; range; degradation; BMS; state of health; charging; thermal; '
            + PRODUCT_PART_CODE;
        return p;
    }

    /**
     * Publishes a short article so Einstein Data Library + prompts can retrieve grounding text.
     * Failure is non-fatal (permissions, validation rules, etc.).
     */
    private static String seedKnowledgeArticleIfPossible() {
        if (Test.isRunningTest()) {
            return 'Knowledge: skipped in test context.';
        }
        try {
            String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
            Knowledge__kav k = new Knowledge__kav();
            k.Title = 'High-voltage battery — Aurora EV-500 service guide';
            k.UrlName = 'hv-battery-aurora-ev500-' + suffix;
            k.Language = 'en_US';
            k.Summary =
                'Use ProductCode '
                + PRODUCT_PART_CODE
                + ' for high-voltage battery assembly replacement when the customer reports range loss, '
                + 'battery degradation, or BMS faults on Aurora EV-500. Confirm warranty via AssetWarranty end date.';
            insert k;

            Knowledge__kav persisted = [
                SELECT KnowledgeArticleId
                FROM Knowledge__kav
                WHERE Id = :k.Id
                LIMIT 1
            ];
            if (persisted.KnowledgeArticleId == null) {
                return 'Knowledge: draft inserted but KnowledgeArticleId was null (publish skipped).';
            }
            KbManagement.PublishingService.publishArticle(persisted.KnowledgeArticleId, true);
            return 'Knowledge: article published (search Title "High-voltage battery — Aurora").';
        } catch (Exception e) {
            return 'Knowledge: not created or not published (' + e.getMessage() + '). You can add an article manually to the Data Library.';
        }
    }
}
