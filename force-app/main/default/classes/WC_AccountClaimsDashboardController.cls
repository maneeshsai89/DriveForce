/**
 * WC — Claim volume and approval-status metrics for a dealer Account (standard Claim.AccountId).
 */
public without sharing class WC_AccountClaimsDashboardController {
    public class Metrics {
        @AuraEnabled
        public Integer totalRaised { get; set; }
        @AuraEnabled
        public Integer pendingCount { get; set; }
        @AuraEnabled
        public Integer approvedCount { get; set; }
        @AuraEnabled
        public Integer rejectedCount { get; set; }
        /** Claims with CreatedDate in the current calendar month. */
        @AuraEnabled
        public Integer claimsThisMonth { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Metrics getClaimMetricsByAccount(Id accountId) {
        Metrics m = new Metrics();
        m.totalRaised = 0;
        m.pendingCount = 0;
        m.approvedCount = 0;
        m.rejectedCount = 0;
        m.claimsThisMonth = 0;
        if (accountId == null) {
            return m;
        }
        List<AggregateResult> moRows = [
            SELECT COUNT(Id) moCnt
            FROM Claim
            WHERE AccountId = :accountId AND CreatedDate = THIS_MONTH
        ];
        m.claimsThisMonth = moRows.isEmpty() ? 0 : (Integer) moRows[0].get('moCnt');
        for (AggregateResult ar : [
            SELECT WC_Approval_Result__c lbl, COUNT(Id) cnt
            FROM Claim
            WHERE AccountId = :accountId
            GROUP BY WC_Approval_Result__c
        ]) {
            String lbl = (String) ar.get('lbl');
            Integer cnt = (Integer) ar.get('cnt');
            if (cnt == null) {
                continue;
            }
            m.totalRaised += cnt;
            if (lbl == 'Pending') {
                m.pendingCount = cnt;
            } else if (lbl == 'Approved') {
                m.approvedCount = cnt;
            } else if (lbl == 'Rejected') {
                m.rejectedCount = cnt;
            }
        }
        return m;
    }

    /** Row for Account claim list (LWC datatable). */
    public class ClaimTableRow {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String approvalResult { get; set; }
        @AuraEnabled
        public Datetime createdDate { get; set; }
        @AuraEnabled
        public Date effectiveDate { get; set; }
        @AuraEnabled
        public Decimal estimatedAmount { get; set; }
        @AuraEnabled
        public String summary { get; set; }
        @AuraEnabled
        public String submissionChannel { get; set; }
        /** WC_Approval_Channel__c — channel through which the claim was decided (e.g. Slack, Electra). */
        @AuraEnabled
        public String approvalChannel { get; set; }
        /** WC_Approved_At__c — when the claim was approved or rejected. */
        @AuraEnabled
        public Datetime approvedAt { get; set; }
        @AuraEnabled
        public String vehicleVin { get; set; }
        @AuraEnabled
        public String vehicleDisplay { get; set; }
        @AuraEnabled
        public String issueDisplay { get; set; }
        @AuraEnabled
        public String processingHint { get; set; }
        /** First line ClaimItem.AssetUsageValue — mileage at claim. */
        @AuraEnabled
        public Decimal assetUsageValue { get; set; }
    }

    private static final Integer CLAIM_LIST_LIMIT = 500;

    @AuraEnabled(cacheable=true)
    public static List<ClaimTableRow> listClaimsForAccount(Id accountId) {
        List<ClaimTableRow> rows = new List<ClaimTableRow>();
        if (accountId == null) {
            return rows;
        }
        for (Claim c : [
            SELECT
                Id,
                Name,
                Status,
                WC_Approval_Result__c,
                CreatedDate,
                WC_Claim_Effective_Date__c,
                EstimatedAmount,
                Summary,
                WC_Submission_Channel__c,
                WC_Approval_Channel__c,
                WC_Approved_At__c
            FROM Claim
            WHERE AccountId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT :CLAIM_LIST_LIMIT
        ]) {
            ClaimTableRow r = new ClaimTableRow();
            r.id = c.Id;
            r.name = c.Name;
            r.status = c.Status;
            r.approvalResult = c.WC_Approval_Result__c;
            r.createdDate = c.CreatedDate;
            r.effectiveDate = c.WC_Claim_Effective_Date__c;
            r.estimatedAmount = c.EstimatedAmount;
            r.summary = c.Summary;
            r.submissionChannel = c.WC_Submission_Channel__c;
            r.approvalChannel = c.WC_Approval_Channel__c;
            r.approvedAt = c.WC_Approved_At__c;
            r.issueDisplay = '';
            r.processingHint = buildProcessingHint(c.CreatedDate, c.WC_Approval_Result__c);
            rows.add(r);
        }
        enrichClaimLines(rows);
        return rows;
    }

    private static void enrichClaimLines(List<ClaimTableRow> rows) {
        if (rows.isEmpty()) {
            return;
        }
        Set<Id> claimIds = new Set<Id>();
        for (ClaimTableRow r : rows) {
            claimIds.add(r.id);
        }
        Map<Id, ClaimItem> firstLineByClaim = new Map<Id, ClaimItem>();
        for (ClaimItem li : [
            SELECT
                ClaimId,
                Description,
                AssetUsageValue,
                Vehicle.VehicleIdentificationNumber,
                Vehicle.ModelName,
                Vehicle.ModelYear
            FROM ClaimItem
            WHERE ClaimId IN :claimIds
            ORDER BY ClaimId, CreatedDate ASC
        ]) {
            if (!firstLineByClaim.containsKey(li.ClaimId)) {
                firstLineByClaim.put(li.ClaimId, li);
            }
        }
        for (ClaimTableRow r : rows) {
            ClaimItem li = firstLineByClaim.get(r.id);
            if (li == null) {
                continue;
            }
            if (String.isNotBlank(li.Description)) {
                r.issueDisplay = li.Description;
            }
            if (li.Vehicle != null) {
                r.vehicleVin = li.Vehicle.VehicleIdentificationNumber;
                List<String> vehicleBits = new List<String>();
                if (String.isNotBlank(li.Vehicle.ModelName)) {
                    vehicleBits.add(li.Vehicle.ModelName);
                }
                if (li.Vehicle.ModelYear != null) {
                    vehicleBits.add(String.valueOf(li.Vehicle.ModelYear));
                }
                r.vehicleDisplay = String.join(vehicleBits, ' ');
            }
            if (li.AssetUsageValue != null) {
                r.assetUsageValue = li.AssetUsageValue;
            }
        }
    }

    private static String buildProcessingHint(Datetime created, String approvalResult) {
        if (created == null) {
            return '—';
        }
        if (approvalResult == 'Pending') {
            Long elapsedMs = System.now().getTime() - created.getTime();
            Long mins = elapsedMs / 60000L;
            if (mins < 1) {
                return '< 1 min (ongoing)';
            }
            return String.valueOf(mins) + ' min (ongoing)';
        }
        if (approvalResult == 'Approved' || approvalResult == 'Rejected') {
            return 'Completed';
        }
        return '—';
    }

    /** One issue category on a VIN: how many claims in the window used that primary description. */
    public class VinIssueBreakdownRow {
        @AuraEnabled
        public String issueLabel { get; set; }
        @AuraEnabled
        public Integer claimCount { get; set; }
    }

    /** Distinct Claim count per VIN from Claim lines in the rolling 30-day window (dealer dashboard insight). */
    public class FrequentVinRow {
        @AuraEnabled
        public String vin { get; set; }
        @AuraEnabled
        public Integer claimCount { get; set; }
        @AuraEnabled
        public String vehicleDisplay { get; set; }
        @AuraEnabled
        public List<VinIssueBreakdownRow> issueBreakdown { get; set; }
    }

    private class VinIssueBreakdownSorter implements Comparator<VinIssueBreakdownRow> {
        public Integer compare(VinIssueBreakdownRow a, VinIssueBreakdownRow b) {
            Integer d = (b.claimCount == null ? 0 : b.claimCount) - (a.claimCount == null ? 0 : a.claimCount);
            if (d != 0) {
                return d;
            }
            String la = a.issueLabel == null ? '' : a.issueLabel;
            String lb = b.issueLabel == null ? '' : b.issueLabel;
            return la.compareTo(lb);
        }
    }

    private class FrequentVinRowSorter implements Comparator<FrequentVinRow> {
        public Integer compare(FrequentVinRow a, FrequentVinRow b) {
            Integer diff = (b.claimCount == null ? 0 : b.claimCount) - (a.claimCount == null ? 0 : a.claimCount);
            if (diff != 0) {
                return diff;
            }
            String va = a.vin == null ? '' : a.vin;
            String vb = b.vin == null ? '' : b.vin;
            return va.compareTo(vb);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<FrequentVinRow> getFrequentVinsLast30Days(Id accountId) {
        List<FrequentVinRow> result = new List<FrequentVinRow>();
        if (accountId == null) {
            return result;
        }
        Datetime startDt = System.now().addDays(-30);
        Map<String, Set<Id>> vinToClaimIds = new Map<String, Set<Id>>();
        Map<String, String> vinToVehicle = new Map<String, String>();
        for (ClaimItem li : [
            SELECT ClaimId, Vehicle.VehicleIdentificationNumber, Vehicle.ModelName, Vehicle.ModelYear
            FROM ClaimItem
            WHERE
                Claim.AccountId = :accountId
                AND Claim.CreatedDate >= :startDt
                AND Vehicle.VehicleIdentificationNumber != NULL
            LIMIT 2000
        ]) {
            String vin = li.Vehicle.VehicleIdentificationNumber;
            if (String.isBlank(vin)) {
                continue;
            }
            if (!vinToClaimIds.containsKey(vin)) {
                vinToClaimIds.put(vin, new Set<Id>());
            }
            vinToClaimIds.get(vin).add(li.ClaimId);
            if (!vinToVehicle.containsKey(vin) && li.Vehicle != null) {
                List<String> bits = new List<String>();
                if (String.isNotBlank(li.Vehicle.ModelName)) {
                    bits.add(li.Vehicle.ModelName);
                }
                if (li.Vehicle.ModelYear != null) {
                    bits.add(String.valueOf(li.Vehicle.ModelYear));
                }
                vinToVehicle.put(vin, String.join(bits, ' '));
            }
        }
        Set<Id> allClaimIds = new Set<Id>();
        for (Set<Id> idSet : vinToClaimIds.values()) {
            allClaimIds.addAll(idSet);
        }
        Map<Id, String> firstLineDescByClaim = new Map<Id, String>();
        for (ClaimItem li : [
            SELECT ClaimId, Description
            FROM ClaimItem
            WHERE ClaimId IN :allClaimIds
            ORDER BY ClaimId, CreatedDate ASC
        ]) {
            if (!firstLineDescByClaim.containsKey(li.ClaimId)) {
                firstLineDescByClaim.put(li.ClaimId, li.Description);
            }
        }
        for (String vin : vinToClaimIds.keySet()) {
            FrequentVinRow row = new FrequentVinRow();
            row.vin = vin;
            row.claimCount = vinToClaimIds.get(vin).size();
            row.vehicleDisplay = vinToVehicle.containsKey(vin) ? vinToVehicle.get(vin) : '';
            row.issueBreakdown = buildIssueBreakdownForVin(vinToClaimIds.get(vin), firstLineDescByClaim);
            result.add(row);
        }
        result.sort(new FrequentVinRowSorter());
        List<FrequentVinRow> top = new List<FrequentVinRow>();
        Integer cap = Math.min(8, result.size());
        for (Integer i = 0; i < cap; i++) {
            top.add(result[i]);
        }
        return top;
    }

    /** Primary issue text = first ClaimItem.Description on the claim (by CreatedDate); never Claim.Summary. */
    private static List<VinIssueBreakdownRow> buildIssueBreakdownForVin(
        Set<Id> claimIds,
        Map<Id, String> firstLineDescByClaim
    ) {
        List<VinIssueBreakdownRow> out = new List<VinIssueBreakdownRow>();
        if (claimIds == null || claimIds.isEmpty()) {
            return out;
        }
        Map<String, Integer> normToCount = new Map<String, Integer>();
        Map<String, String> normToLabel = new Map<String, String>();
        for (Id cid : claimIds) {
            String raw = '';
            if (firstLineDescByClaim.containsKey(cid)) {
                String d = firstLineDescByClaim.get(cid);
                raw = String.isNotBlank(d) ? d.trim() : '';
            }
            String norm = String.isBlank(raw) ? '::none::' : raw.toLowerCase();
            String label = String.isBlank(raw) ? 'No description' : raw;
            if (!normToCount.containsKey(norm)) {
                normToCount.put(norm, 0);
                normToLabel.put(norm, label);
            }
            normToCount.put(norm, normToCount.get(norm) + 1);
        }
        for (String norm : normToCount.keySet()) {
            VinIssueBreakdownRow r = new VinIssueBreakdownRow();
            r.issueLabel = truncateUiText(normToLabel.get(norm), 200);
            r.claimCount = normToCount.get(norm);
            out.add(r);
        }
        out.sort(new VinIssueBreakdownSorter());
        return out;
    }

    private static String truncateUiText(String raw, Integer maxLen) {
        if (String.isBlank(raw) || maxLen == null || maxLen < 1) {
            return '';
        }
        String t = raw.trim();
        if (t.length() <= maxLen) {
            return t;
        }
        return t.substring(0, maxLen - 1) + '…';
    }
}