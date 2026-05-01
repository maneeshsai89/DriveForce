/**
 * WC — Tests for WC_CreateClaimIntakeWithAttachmentAction + WC_ClaimMediaDownloadQueueable (HttpCalloutMock).
 */
@isTest
private class WC_CreateClaimIntakeAttachTest {
    private static final String MOCK_MEDIA_URL = 'https://graph.facebook.com/v21.0/fake-media-id';

    private class MediaGetOkMock implements HttpCalloutMock {
        public HTTPResponse respond(HttpRequest req) {
            System.assertEquals('GET', req.getMethod());
            System.assert(req.getEndpoint().contains('graph.facebook.com'));
            System.assert(req.getHeader('Authorization') != null && req.getHeader('Authorization').startsWith('Bearer '));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('fake-image-bytes');
            return res;
        }
    }

    private class MediaGet404Mock implements HttpCalloutMock {
        public HTTPResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('not found');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Account dealer = new Account(Name = 'Intake Attach Dealer');
        insert dealer;
        Product2 prod = new Product2();
        prod.Name = 'Part — intake attach test';
        prod.IsActive = true;
        prod.ProductCode = 'PART-INTAKE-ATTACH-01';
        prod.CurrencyIsoCode = 'USD';
        prod.CanUseQuantitySchedule = false;
        prod.CanUseRevenueSchedule = false;
        prod.IsSerialized = false;
        prod.IsCertified = false;
        prod.IsEnvrPrtcRegCompliant = false;
        prod.IsAssetizable = true;
        prod.IsSoldOnlyWithOtherProds = false;
        prod.IsShippingChargeNotApplicable = false;
        prod.WC_Product_Amount__c = 500;
        prod.WC_Labour_Charge_per_hour__c = 40;
        insert prod;
        VehicleDefinition vd = new VehicleDefinition(Name = 'VD attach', ProductId = prod.Id);
        insert vd;
        Asset ast = new Asset(
            Name = 'Asset attach',
            AccountId = dealer.Id,
            OwnerId = UserInfo.getUserId(),
            IsCompetitorProduct = false,
            IsInternal = false,
            IsRecallOpen = false
        );
        insert ast;
        Vehicle veh = new Vehicle(
            Name = 'Vehicle attach',
            AssetId = ast.Id,
            VehicleDefinitionId = vd.Id,
            VehicleIdentificationNumber = '5YJSA1E41HF123456',
            IsRecallOpen = false,
            IsTelematicsServiceActive = false,
            IsConnectedServiceActive = false,
            CurrentOwnerId = dealer.Id,
            ManufacturerWarrantyEndDate = Date.today().addYears(1),
            ActiveWarrantyCount = 1
        );
        insert veh;
    }

    private static WC_CreateClaimIntakeWithAttachmentAction.WC_Request baseRequest() {
        Account dealer = [SELECT Id FROM Account WHERE Name = 'Intake Attach Dealer' LIMIT 1];
        Vehicle v = [
            SELECT Id
            FROM Vehicle
            WHERE VehicleIdentificationNumber = '5YJSA1E41HF123456'
            LIMIT 1
        ];
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'PART-INTAKE-ATTACH-01' LIMIT 1];
        WC_CreateClaimIntakeWithAttachmentAction.WC_Request req = new WC_CreateClaimIntakeWithAttachmentAction.WC_Request();
        req.dealerAccountId = dealer.Id;
        req.vehicleId = v.Id;
        req.productId = p.Id;
        req.faultDescription = 'Scratch panel';
        req.vin = '5YJSA1E41HF123456';
        req.submissionChannel = 'WhatsApp';
        return req;
    }

    @isTest
    static void create_without_media_url() {
        WC_CreateClaimIntakeWithAttachmentAction.WC_Request req = baseRequest();
        WC_CreateClaimIntakeWithAttachmentAction.WC_Result r = WC_CreateClaimIntakeWithAttachmentAction.createWC(
            new List<WC_CreateClaimIntakeWithAttachmentAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(false, r.attachmentQueued);
        System.assertEquals(null, r.attachmentErrorMessage);
    }

    @isTest
    static void create_with_media_url_queues_and_downloads_file() {
        Test.setMock(HttpCalloutMock.class, new MediaGetOkMock());
        WC_CreateClaimIntakeWithAttachmentAction.WC_Request req = baseRequest();
        req.mediaUrl = MOCK_MEDIA_URL;
        req.attachmentFileName = 'damage.bin';

        WC_CreateClaimIntakeWithAttachmentAction.WC_Result r;
        Test.startTest();
        r = WC_CreateClaimIntakeWithAttachmentAction.createWC(
            new List<WC_CreateClaimIntakeWithAttachmentAction.WC_Request>{ req }
        )[0];
        Test.stopTest();

        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(true, r.attachmentQueued, r.attachmentErrorMessage);

        Id claimId = Id.valueOf(r.claimId);
        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :claimId
        ];
        System.assert(links >= 1, 'File linked after queueable + mock GET');
    }

    @isTest
    static void http_non_200_does_not_insert_file() {
        Test.setMock(HttpCalloutMock.class, new MediaGet404Mock());
        WC_CreateClaimIntakeWithAttachmentAction.WC_Request req = baseRequest();
        req.mediaUrl = MOCK_MEDIA_URL;

        WC_CreateClaimIntakeWithAttachmentAction.WC_Result r;
        Test.startTest();
        r = WC_CreateClaimIntakeWithAttachmentAction.createWC(
            new List<WC_CreateClaimIntakeWithAttachmentAction.WC_Request>{ req }
        )[0];
        Test.stopTest();

        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(true, r.attachmentQueued);

        Id claimId = Id.valueOf(r.claimId);
        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :claimId
        ];
        System.assertEquals(0, links);
    }

    @isTest
    static void reject_http_media_url() {
        WC_CreateClaimIntakeWithAttachmentAction.WC_Request req = baseRequest();
        req.mediaUrl = 'http://insecure.example.com/media';

        WC_CreateClaimIntakeWithAttachmentAction.WC_Result r = WC_CreateClaimIntakeWithAttachmentAction.createWC(
            new List<WC_CreateClaimIntakeWithAttachmentAction.WC_Request>{ req }
        )[0];
        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(false, r.attachmentQueued);
        System.assert(r.attachmentErrorMessage != null && r.attachmentErrorMessage.contains('HTTPS'));
    }
}
