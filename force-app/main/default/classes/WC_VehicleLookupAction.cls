/**
 * WC — Invocable: resolve VIN to Vehicle + basic warranty context for Agentforce intake.
 * Queries use AccessLevel.SYSTEM_MODE for the Einstein Service Agent user (limited license).
 */
public without sharing class WC_VehicleLookupAction {
    public class WC_Request {
        @InvocableVariable(label='VIN' description='16-character vehicle identification number' required=true)
        public String vin;
    }

    public class WC_Result {
        @InvocableVariable(
            label='Vehicle Model'
            description='Model name from the Vehicle record when a match is found.'
        )
        public String vehicleModel;
        @InvocableVariable(
            label='Model Year'
            description='Vehicle model year as an integer when available.'
        )
        public Integer modelYear;
        @InvocableVariable(
            label='Warranty Status'
            description='Human-readable warranty state, e.g. Active, Expired, or Unknown.'
        )
        public String warrantyStatus;
        @InvocableVariable(
            label='Warranty Expiry'
            description='Latest known warranty end date from AssetWarranty or manufacturer fields.'
        )
        public Date warrantyExpiry;
        @InvocableVariable(
            label='Dealer Name'
            description='Name of the Account that is the vehicle current owner (dealer).'
        )
        public String dealerName;
        @InvocableVariable(
            label='Mileage Cap'
            description='Optional mileage limit context when configured; may be null.'
        )
        public Decimal mileageCap;
        @InvocableVariable(
            label='Vehicle Id'
            description='Salesforce Id of the Vehicle record when Found is true.'
        )
        public String vehicleId;
        @InvocableVariable(
            label='Dealer Account Id'
            description='Salesforce Account Id for the dealer (Current Owner) when Found is true.'
        )
        public String dealerAccountId;
        @InvocableVariable(
            label='Found'
            description='True when a Vehicle with this VIN exists in the org.'
        )
        public Boolean found;
    }

    @InvocableMethod(
        label='WC Lookup Vehicle by VIN'
        description='Queries Vehicle by VIN and returns model, warranty, and dealer context.'
    )
    public static List<WC_Result> lookupWC(List<WC_Request> requests) {
        List<WC_Result> results = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (WC_Request req : requests) {
            results.add(lookupOne(req == null ? null : req.vin));
        }
        return results;
    }

    private static WC_Result lookupOne(String vin) {
        WC_Result r = new WC_Result();
        r.found = false;
        r.mileageCap = null;
        if (String.isBlank(vin)) {
            return r;
        }
        String normalized = vin.trim().toUpperCase();
        List<Vehicle> rows = (List<Vehicle>) Database.queryWithBinds(
            'SELECT Id, ModelName, ModelYear, AssetId, CurrentOwnerId, ManufacturerWarrantyEndDate, '
                + 'ActiveWarrantyCount, VehicleIdentificationNumber FROM Vehicle '
                + 'WHERE VehicleIdentificationNumber = :vin LIMIT 1',
            new Map<String, Object>{ 'vin' => normalized },
            AccessLevel.SYSTEM_MODE
        );
        if (rows.isEmpty()) {
            return r;
        }
        Vehicle v = rows[0];
        r.found = true;
        r.vehicleId = v.Id;
        if (v.CurrentOwnerId != null) {
            r.dealerAccountId = v.CurrentOwnerId;
        }
        r.vehicleModel = v.ModelName;
        if (!String.isBlank(v.ModelYear)) {
            try {
                r.modelYear = Integer.valueOf(v.ModelYear.trim());
            } catch (Exception e) {
                r.modelYear = null;
            }
        }
        Date todayDt = Date.today();
        if (v.CurrentOwnerId != null) {
            List<Account> accs = (List<Account>) Database.queryWithBinds(
                'SELECT Name FROM Account WHERE Id = :oid LIMIT 1',
                new Map<String, Object>{ 'oid' => v.CurrentOwnerId },
                AccessLevel.SYSTEM_MODE
            );
            if (!accs.isEmpty()) {
                r.dealerName = accs[0].Name;
            }
        }
        if (v.AssetId != null) {
            List<AssetWarranty> aws = (List<AssetWarranty>) Database.queryWithBinds(
                'SELECT EndDate FROM AssetWarranty WHERE AssetId = :aid ORDER BY EndDate DESC NULLS LAST LIMIT 1',
                new Map<String, Object>{ 'aid' => v.AssetId },
                AccessLevel.SYSTEM_MODE
            );
            if (!aws.isEmpty() && aws[0].EndDate != null) {
                r.warrantyExpiry = aws[0].EndDate;
                r.warrantyStatus = aws[0].EndDate >= todayDt ? 'Active' : 'Expired';
            }
        }
        if (r.warrantyExpiry == null && v.ManufacturerWarrantyEndDate != null) {
            r.warrantyExpiry = v.ManufacturerWarrantyEndDate;
        }
        if (String.isBlank(r.warrantyStatus)) {
            if (v.ManufacturerWarrantyEndDate != null) {
                r.warrantyStatus =
                    v.ManufacturerWarrantyEndDate >= todayDt ? 'Active' : 'Expired';
            } else if (v.ActiveWarrantyCount != null && v.ActiveWarrantyCount > 0) {
                r.warrantyStatus = 'Active';
            } else {
                r.warrantyStatus = 'Unknown';
            }
        }
        return r;
    }
}
