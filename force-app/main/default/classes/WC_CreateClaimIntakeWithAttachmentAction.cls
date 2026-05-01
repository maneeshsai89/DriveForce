/**
 * WC — Clone of {@link WC_CreateClaimIntakeAction} that optionally downloads WhatsApp/Meta media via HTTPS GET (Bearer token in
 * {@link WC_ClaimMediaDownloadQueueable}) and saves it as a Salesforce File on the new Claim. Callout runs asynchronously after intake DML commits.
 */
public without sharing class WC_CreateClaimIntakeWithAttachmentAction {
    public class WC_Request {
        @InvocableVariable(label='Dealer Account Id' description='Account Id for the dealer' required=true)
        public String dealerAccountId;
        @InvocableVariable(label='Vehicle Id' description='Salesforce Vehicle Id from lookup' required=true)
        public String vehicleId;
        @InvocableVariable(label='Product Id' description='Product2 Id for the claimed part' required=true)
        public String productId;
        @InvocableVariable(
            label='Fault Description'
            description='Customer or dealer description of the fault or symptom.'
            required=true
        )
        public String faultDescription;
        @InvocableVariable(
            label='VIN'
            description='16-character VIN; must match the vehicle from lookup.'
            required=true
        )
        public String vin;
        @InvocableVariable(
            label='Mileage At Claim'
            description='Odometer reading at time of claim, if known.'
        )
        public Decimal mileageAtClaim;
        @InvocableVariable(
            label='Labour Hours'
            description='Estimated labour hours for the repair line.'
        )
        public Decimal labourHours;
        @InvocableVariable(
            label='Estimated Amount'
            description='Optional override. If omitted, amount = Product WC_Product_Amount__c + (labour hours × WC_Labour_Charge_per_hour__c). If that computes to zero, this value is used when provided.'
        )
        public Decimal estimatedAmount;
        @InvocableVariable(label='Submission Channel' description='WhatsApp, Web, or Portal' required=true)
        public String submissionChannel;
        @InvocableVariable(
            label='AI Risk Score'
            description='Optional AI-generated risk or confidence score for the claim.'
        )
        public Decimal aiRiskScore;
        @InvocableVariable(
            label='Media URL'
            description='Optional. HTTPS URL from the agent (e.g. WhatsApp media); downloaded after Claim insert via Queueable GET + Bearer.'
        )
        public String mediaUrl;
        @InvocableVariable(
            label='Attachment File Name'
            description='Optional file name with extension for the saved File (e.g. intake-photo.jpg). Default WC_Claim_Intake_Media.jpg.'
        )
        public String attachmentFileName;
    }

    public class WC_Result {
        @InvocableVariable(label='Claim Id' description='Id of the created Claim record.')
        public String claimId;
        @InvocableVariable(label='Claim Name' description='Name of the created Claim record.')
        public String claimName;
        @InvocableVariable(label='Success' description='True if Claim and ClaimItem were created successfully.')
        public Boolean success;
        @InvocableVariable(
            label='Error Message'
            description='Populated when Success is false; explains validation or DML failure.'
        )
        public String errorMessage;
        @InvocableVariable(
            label='Media Download Queued'
            description='True when a Media URL was provided and the async download job was enqueued.'
        )
        public Boolean attachmentQueued;
        @InvocableVariable(
            label='Attachment Error Message'
            description='Validation or enqueue failure for media (Claim may still be created).'
        )
        public String attachmentErrorMessage;
    }

    @InvocableMethod(
        label='WC Create Claim Intake (with image)'
        description='Creates Claim and ClaimItem; optionally queues HTTPS download of mediaUrl (WhatsApp Bearer in WC_ClaimMediaDownloadQueueable) as a Claim File.'
    )
    public static List<WC_Result> createWC(List<WC_Request> requests) {
        List<WC_Result> results = new List<WC_Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (WC_Request req : requests) {
            results.add(createOne(req));
        }
        return results;
    }

    private static WC_Result createOne(WC_Request req) {
        WC_Result out = new WC_Result();
        out.success = false;
        out.attachmentQueued = false;
        out.attachmentErrorMessage = null;
        if (req == null) {
            out.errorMessage = 'Request was null.';
            return out;
        }
        if (
            String.isBlank(req.dealerAccountId) ||
            String.isBlank(req.vehicleId) ||
            String.isBlank(req.productId) ||
            String.isBlank(req.faultDescription) ||
            String.isBlank(req.vin)
        ) {
            out.errorMessage = 'Missing required input (dealer, vehicle, product, fault, or VIN).';
            return out;
        }
        String vinNorm = req.vin.trim().toUpperCase();
        List<Vehicle> vehicles = (List<Vehicle>) Database.queryWithBinds(
            'SELECT Id, VehicleIdentificationNumber, CurrentOwnerId, AssetId, ManufacturerWarrantyEndDate, ActiveWarrantyCount '
                + 'FROM Vehicle WHERE Id = :vid LIMIT 1',
            new Map<String, Object>{ 'vid' => req.vehicleId },
            AccessLevel.SYSTEM_MODE
        );
        if (vehicles.isEmpty()) {
            out.errorMessage = 'Vehicle not found.';
            return out;
        }
        Vehicle v = vehicles[0];
        if (v.VehicleIdentificationNumber == null || v.VehicleIdentificationNumber.toUpperCase() != vinNorm) {
            out.errorMessage = 'VIN does not match the selected vehicle.';
            return out;
        }
        if (v.CurrentOwnerId == null || v.CurrentOwnerId != req.dealerAccountId) {
            out.errorMessage = 'Dealer account does not match the vehicle current owner.';
            return out;
        }
        if (!isWarrantyActive(v)) {
            out.errorMessage = 'Vehicle warranty is not active. Claim cannot be submitted.';
            return out;
        }
        List<Account> dealers = (List<Account>) Database.queryWithBinds(
            'SELECT Name FROM Account WHERE Id = :aid LIMIT 1',
            new Map<String, Object>{ 'aid' => req.dealerAccountId },
            AccessLevel.SYSTEM_MODE
        );
        String dealerName = dealers.isEmpty() ? '' : dealers[0].Name;

        List<Product2> prods = (List<Product2>) Database.queryWithBinds(
            'SELECT Id, WC_Product_Amount__c, WC_Labour_Charge_per_hour__c FROM Product2 WHERE Id = :pid LIMIT 1',
            new Map<String, Object>{ 'pid' => req.productId },
            AccessLevel.SYSTEM_MODE
        );
        if (prods.isEmpty()) {
            out.errorMessage = 'Product not found.';
            return out;
        }
        Decimal resolvedEstimated = resolveEstimatedAmount(prods[0], req);

        Claim c = new Claim();
        c.AccountId = req.dealerAccountId;
        c.OwnerId = UserInfo.getUserId();
        c.Name = buildClaimName();
        c.Summary = req.faultDescription;
        c.IsInhabitable = false;
        c.IsDrivable = true;
        c.IsAuthoritiesNotified = false;
        c.Status = 'Submitted';
        c.EstimatedAmount = resolvedEstimated;
        c.WC_Claim_Source__c = 'Agentforce';
        c.WC_Submission_Channel__c = mapSubmissionChannel(req.submissionChannel);
        if (req.aiRiskScore != null) {
            c.WC_AI_Risk_Score__c = req.aiRiskScore;
        }
        c.WC_Claim_Effective_Date__c = Date.today();
        c.WC_Approval_Result__c = 'Pending';
        try {
            Database.insert(new List<Claim>{ c }, AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            out.errorMessage = e.getMessage();
            return out;
        }

        ClaimItem line = new ClaimItem();
        line.ClaimId = c.Id;
        line.Name = 'WC Line 1';
        line.VehicleId = req.vehicleId;
        line.ProductId = req.productId;
        line.Description = req.faultDescription;
        line.FaultDate = System.now();
        if (req.labourHours != null) {
            line.WC_Labour_Hours__c = req.labourHours;
        }
        if (req.mileageAtClaim != null) {
            Decimal m = req.mileageAtClaim;
            m = Math.max(0, Math.min(2147483647, m));
            line.AssetUsageValue = (Integer) m.round(System.RoundingMode.DOWN);
        }
        try {
            Database.insert(new List<ClaimItem>{ line }, AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            out.errorMessage = 'Claim created but line failed: ' + e.getMessage();
            out.claimId = c.Id;
            out.claimName = c.Name;
            return out;
        }

        try {
            WC_WarrantyClaimSubmitted__e evt = new WC_WarrantyClaimSubmitted__e();
            evt.WC_Claim_Id__c = c.Id;
            evt.WC_Claim_Name__c = c.Name;
            evt.WC_Dealer_Account_Id__c = req.dealerAccountId;
            evt.WC_Dealer_Name__c = dealerName;
            evt.WC_VIN__c = vinNorm;
            evt.WC_Estimated_Value__c = resolvedEstimated;
            if (req.aiRiskScore != null) {
                evt.WC_Risk_Score__c = req.aiRiskScore;
            }
            evt.WC_Recommended_Action__c = 'Review';
            evt.WC_Submitted_At__c = System.now();
            EventBus.publish(evt);
        } catch (Exception e) {
            out.errorMessage = 'Claim saved but event publish failed: ' + e.getMessage();
            out.claimId = c.Id;
            out.claimName = c.Name;
            out.success = true;
            maybeEnqueueMediaDownload(c.Id, req, out);
            return out;
        }

        out.success = true;
        out.claimId = c.Id;
        out.claimName = c.Name;
        maybeEnqueueMediaDownload(c.Id, req, out);
        return out;
    }

    private static void maybeEnqueueMediaDownload(Id claimId, WC_Request req, WC_Result out) {
        if (String.isBlank(req.mediaUrl)) {
            return;
        }
        String url = req.mediaUrl.trim();
        if (!url.toLowerCase().startsWith('https://')) {
            out.attachmentErrorMessage = 'mediaUrl must use HTTPS.';
            return;
        }
        try {
            System.enqueueJob(new WC_ClaimMediaDownloadQueueable(claimId, url, req.attachmentFileName));
            out.attachmentQueued = true;
        } catch (Exception e) {
            out.attachmentErrorMessage = 'Could not queue media download: ' + e.getMessage();
            System.debug(LoggingLevel.WARN, 'WC_CreateClaimIntakeWithAttachmentAction enqueue media: ' + e.getMessage());
        }
    }

    private static Decimal resolveEstimatedAmount(Product2 prod, WC_Request req) {
        Decimal partPrice = prod.WC_Product_Amount__c != null ? prod.WC_Product_Amount__c : 0;
        Decimal hourly = prod.WC_Labour_Charge_per_hour__c != null ? prod.WC_Labour_Charge_per_hour__c : 0;
        Decimal hrs = req.labourHours != null ? req.labourHours : 0;
        Decimal computed = partPrice + (hourly * hrs);
        if (computed == 0 && req.estimatedAmount != null) {
            return req.estimatedAmount;
        }
        return computed;
    }

    private static String buildClaimName() {
        String s =
            'WTY-' +
            Datetime.now().formatGmt('yyyyMMdd-HHmmss') +
            '-' +
            String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 100000));
        return s.length() > 80 ? s.substring(0, 80) : s;
    }

    private static String mapSubmissionChannel(String raw) {
        if (String.isBlank(raw)) {
            return 'Web';
        }
        String s = raw.trim();
        if (s.equalsIgnoreCase('WhatsApp')) {
            return 'WhatsApp';
        }
        if (s.equalsIgnoreCase('Portal')) {
            return 'Portal';
        }
        return 'Web';
    }

    private static Boolean isWarrantyActive(Vehicle v) {
        Date todayDt = Date.today();
        if (v.AssetId != null) {
            List<AssetWarranty> aws = (List<AssetWarranty>) Database.queryWithBinds(
                'SELECT EndDate FROM AssetWarranty WHERE AssetId = :astId ORDER BY EndDate DESC NULLS LAST LIMIT 1',
                new Map<String, Object>{ 'astId' => v.AssetId },
                AccessLevel.SYSTEM_MODE
            );
            if (!aws.isEmpty() && aws[0].EndDate != null) {
                return aws[0].EndDate >= todayDt;
            }
        }
        if (v.ManufacturerWarrantyEndDate != null) {
            return v.ManufacturerWarrantyEndDate >= todayDt;
        }
        if (v.ActiveWarrantyCount != null && v.ActiveWarrantyCount > 0) {
            return true;
        }
        return false;
    }
}
