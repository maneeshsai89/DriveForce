/**
 * WC — Builds approver notification context: Claim + related records + SOQL "insight" metrics
 * aligned with Data Cloud Calculated Insights (dealer volumes, outcomes, repeat part, last claim date).
 * Use when Data Cloud Query API is not wired; metrics match CI definitions for the same CRM data.
 */
public without sharing class WC_ApproverContextService {
    public class ApproverContext {
        public Id claimId;
        public String claimName;
        public String dealerAccountId;
        public String dealerName;
        public String vin;
        public String vehicleModel;
        public String modelYear;
        public String warrantyHint;
        public String faultText;
        public String partName;
        public String partCode;
        public Decimal labourHours;
        public Decimal estimatedAmount;
        public Integer mileage;
        public String submissionChannel;
        public String claimSource;
        public Decimal riskScore;
        public String riskLabel;
        public String dealerInsightsNarrative;
        public String claimContextBlock;
        public String slackPlainTextBody;
    }

    public static ApproverContext build(Id claimId) {
        ApproverContext ctx = new ApproverContext();
        if (claimId == null) {
            return ctx;
        }
        ctx.claimId = claimId;
        List<Claim> claims = (List<Claim>) Database.queryWithBinds(
            'SELECT Id, Name, AccountId, Summary, EstimatedAmount, WC_Claim_Source__c, WC_Submission_Channel__c, '
                + 'WC_AI_Risk_Score__c, WC_Claim_Effective_Date__c, WC_Approval_Result__c '
                + 'FROM Claim WHERE Id = :cid LIMIT 1',
            new Map<String, Object>{ 'cid' => claimId },
            AccessLevel.SYSTEM_MODE
        );
        if (claims.isEmpty()) {
            return ctx;
        }
        Claim c = claims[0];
        ctx.claimName = c.Name;
        ctx.dealerAccountId = c.AccountId;
        ctx.faultText = c.Summary;
        ctx.estimatedAmount = c.EstimatedAmount;
        ctx.submissionChannel = c.WC_Submission_Channel__c;
        ctx.claimSource = c.WC_Claim_Source__c;
        ctx.riskScore = c.WC_AI_Risk_Score__c;
        ctx.riskLabel = riskTierLabel(c.WC_AI_Risk_Score__c);

        if (c.AccountId != null) {
            List<Account> accs = (List<Account>) Database.queryWithBinds(
                'SELECT Name FROM Account WHERE Id = :aid LIMIT 1',
                new Map<String, Object>{ 'aid' => c.AccountId },
                AccessLevel.SYSTEM_MODE
            );
            if (!accs.isEmpty()) {
                ctx.dealerName = accs[0].Name;
            }
        }

        List<ClaimItem> lines = (List<ClaimItem>) Database.queryWithBinds(
            'SELECT Id, VehicleId, ProductId, Description, AssetUsageValue, WC_Labour_Hours__c FROM ClaimItem '
                + 'WHERE ClaimId = :cid ORDER BY CreatedDate ASC LIMIT 1',
            new Map<String, Object>{ 'cid' => claimId },
            AccessLevel.SYSTEM_MODE
        );
        if (!lines.isEmpty()) {
            ClaimItem line = lines[0];
            if (line.WC_Labour_Hours__c != null) {
                ctx.labourHours = line.WC_Labour_Hours__c;
            }
            if (line.AssetUsageValue != null) {
                ctx.mileage = line.AssetUsageValue;
            }
            if (line.VehicleId != null) {
                List<Vehicle> vs = (List<Vehicle>) Database.queryWithBinds(
                    'SELECT ModelName, ModelYear, VehicleIdentificationNumber, ManufacturerWarrantyEndDate, ActiveWarrantyCount '
                        + 'FROM Vehicle WHERE Id = :vid LIMIT 1',
                    new Map<String, Object>{ 'vid' => line.VehicleId },
                    AccessLevel.SYSTEM_MODE
                );
                if (!vs.isEmpty()) {
                    Vehicle v = vs[0];
                    ctx.vin = v.VehicleIdentificationNumber;
                    ctx.vehicleModel = v.ModelName;
                    ctx.modelYear = v.ModelYear;
                    ctx.warrantyHint = buildWarrantyHint(v);
                }
            }
            if (line.ProductId != null) {
                List<Product2> prods = (List<Product2>) Database.queryWithBinds(
                    'SELECT Name, ProductCode FROM Product2 WHERE Id = :pid LIMIT 1',
                    new Map<String, Object>{ 'pid' => line.ProductId },
                    AccessLevel.SYSTEM_MODE
                );
                if (!prods.isEmpty()) {
                    ctx.partName = prods[0].Name;
                    ctx.partCode = prods[0].ProductCode;
                }
            }
        }

        if (c.AccountId != null) {
            ctx.dealerInsightsNarrative = buildDealerInsights(c.AccountId, claimId, lines);
        }

        ctx.claimContextBlock = buildClaimContextBlock(ctx, c);
        ctx.slackPlainTextBody = buildSlackPlainText(ctx, c);
        return ctx;
    }

    private static String buildWarrantyHint(Vehicle v) {
        if (v.ManufacturerWarrantyEndDate != null) {
            return 'Active — mfr end ' + String.valueOf(v.ManufacturerWarrantyEndDate);
        }
        if (v.ActiveWarrantyCount != null && v.ActiveWarrantyCount > 0) {
            return 'Active — warranty count ' + String.valueOf(v.ActiveWarrantyCount);
        }
        return 'See vehicle record';
    }

    /**
     * Maps WC_AI_Risk_Score__c (0–100 scale) to Low / Medium / High for approver UX.
     * Null score → "Not assessed" (avoid "Unknown" in Slack and email).
     */
    public static String riskTierLabel(Decimal score) {
        if (score == null) {
            return 'Not assessed';
        }
        if (score < 51) {
            return 'Low';
        }
        if (score < 65) {
            return 'Medium';
        }
        return 'High';
    }

    /** Plain-text fragment for Slack/email, e.g. "18/100" or "—" when no score. */
    public static String formatRiskScoreFraction(Decimal score) {
        if (score == null) {
            return '—';
        }
        return String.valueOf(score) + '/100';
    }

    /**
     * Dealer-level metrics mirroring CI: 30/60/90 volumes, last prior claim date, approval mix (90d),
     * repeat lines for same part (180d).
     */
    private static String buildDealerInsights(Id accountId, Id currentClaimId, List<ClaimItem> lines) {
        Date today = Date.today();
        Date d30 = today.addDays(-30);
        Date d60 = today.addDays(-60);
        Date d90 = today.addDays(-90);
        Date d180 = today.addDays(-180);

        Integer n30 = countClaimsInRange(accountId, d30, today);
        Integer n60 = countClaimsInRange(accountId, d60, today);
        Integer n90 = countClaimsInRange(accountId, d90, today);

        Date lastPrior = maxPriorEffectiveDate(accountId, currentClaimId);

        Map<String, Integer> mix = approvalMix90(accountId, d90, today);

        String repeatNote = '';
        if (!lines.isEmpty() && lines[0].ProductId != null) {
            Integer repeatLines = countLinesSamePart(accountId, lines[0].ProductId, d180, today);
            repeatNote =
                'Lines on same part (dealer, last 180d, incl. this claim line): ' +
                repeatLines +
                '. ';
        }

        String lastStr = lastPrior == null ? 'None prior' : String.valueOf(lastPrior);
        return 'Data aligned with Calculated Insights (CRM source, same definitions as Data Cloud CI).\n'
            + '- Claim volume — dealer last 30 / 60 / 90 days: '
            + n30
            + ' / '
            + n60
            + ' / '
            + n90
            + '\n'
            + '- Last prior claim effective date (excl. this Id): '
            + lastStr
            + '\n'
            + '- Outcomes last 90d — Approved: '
            + mix.get('Approved')
            + ', Rejected: '
            + mix.get('Rejected')
            + ', Pending: '
            + mix.get('Pending')
            + '\n'
            + '- '
            + repeatNote;
    }

    private static Integer countClaimsInRange(Id accountId, Date fromDate, Date toDate) {
        List<AggregateResult> ar = [
            SELECT COUNT(Id) cnt
            FROM Claim
            WHERE
                AccountId = :accountId
                AND WC_Claim_Effective_Date__c >= :fromDate
                AND WC_Claim_Effective_Date__c <= :toDate
        ];
        if (ar.isEmpty()) {
            return 0;
        }
        return (Integer) ar[0].get('cnt');
    }

    private static Date maxPriorEffectiveDate(Id accountId, Id currentClaimId) {
        List<Claim> rows = (List<Claim>) Database.queryWithBinds(
            'SELECT WC_Claim_Effective_Date__c FROM Claim WHERE AccountId = :aid AND Id != :cid '
                + 'AND WC_Claim_Effective_Date__c != NULL ORDER BY WC_Claim_Effective_Date__c DESC NULLS LAST LIMIT 1',
            new Map<String, Object>{ 'aid' => accountId, 'cid' => currentClaimId },
            AccessLevel.SYSTEM_MODE
        );
        if (rows.isEmpty() || rows[0].WC_Claim_Effective_Date__c == null) {
            return null;
        }
        return rows[0].WC_Claim_Effective_Date__c;
    }

    private static Map<String, Integer> approvalMix90(Id accountId, Date fromDate, Date toDate) {
        Map<String, Integer> out = new Map<String, Integer>{
            'Approved' => 0,
            'Rejected' => 0,
            'Pending' => 0
        };
        for (AggregateResult ar : [
            SELECT WC_Approval_Result__c lbl, COUNT(Id) cnt
            FROM Claim
            WHERE
                AccountId = :accountId
                AND WC_Claim_Effective_Date__c >= :fromDate
                AND WC_Claim_Effective_Date__c <= :toDate
                AND WC_Approval_Result__c != NULL
            GROUP BY WC_Approval_Result__c
        ]) {
            String k = (String) ar.get('lbl');
            if (k != null && out.containsKey(k)) {
                out.put(k, (Integer) ar.get('cnt'));
            }
        }
        return out;
    }

    private static Integer countLinesSamePart(Id accountId, Id productId, Date fromDate, Date toDate) {
        List<AggregateResult> ar = [
            SELECT COUNT(Id) cnt
            FROM ClaimItem
            WHERE
                ProductId = :productId
                AND ClaimId IN (
                    SELECT Id
                    FROM Claim
                    WHERE
                        AccountId = :accountId
                        AND WC_Claim_Effective_Date__c >= :fromDate
                        AND WC_Claim_Effective_Date__c <= :toDate
                )
        ];
        if (ar.isEmpty()) {
            return 0;
        }
        return (Integer) ar[0].get('cnt');
    }

    private static String buildClaimContextBlock(ApproverContext ctx, Claim c) {
        List<String> parts = new List<String>();
        parts.add('Claim: ' + String.valueOf(ctx.claimName));
        parts.add('Dealer: ' + nz(ctx.dealerName));
        parts.add('VIN: ' + nz(ctx.vin));
        parts.add('Vehicle: ' + nz(ctx.vehicleModel) + (String.isNotBlank(ctx.modelYear) ? (' · ' + ctx.modelYear) : ''));
        parts.add('Warranty: ' + nz(ctx.warrantyHint));
        parts.add('Fault: ' + nz(ctx.faultText));
        parts.add('Part: ' + nz(ctx.partName) + (String.isNotBlank(ctx.partCode) ? (' · ' + ctx.partCode) : ''));
        parts.add(
            'Labour hours: ' + (ctx.labourHours != null ? String.valueOf(ctx.labourHours) : '')
        );
        parts.add('Mileage: ' + (ctx.mileage != null ? String.valueOf(ctx.mileage) : ''));
        parts.add('Est. amount: ' + String.valueOf(ctx.estimatedAmount));
        parts.add('Channel: ' + nz(ctx.submissionChannel));
        parts.add(
            'Risk: ' + ctx.riskLabel + (ctx.riskScore != null ? (' · ' + formatRiskScoreFraction(ctx.riskScore)) : '')
        );
        return String.join(parts, '\n');
    }

    private static String buildSlackPlainText(ApproverContext ctx, Claim c) {
        String header = '*New warranty claim — prior authorisation required*\n';
        String card =
            '*Claim* '
            + nz(ctx.claimName)
            + ' · '
            + nz(ctx.dealerName)
            + '\n'
            + 'VIN: '
            + nz(ctx.vin)
            + '\n'
            + 'Vehicle: '
            + nz(ctx.vehicleModel)
            + '\n'
            + 'Fault: '
            + nz(ctx.faultText)
            + '\n'
            + 'Part: '
            + nz(ctx.partCode)
            + '\n'
            + 'Est.: '
            + String.valueOf(ctx.estimatedAmount)
            + '\n'
            + 'Risk: '
            + ctx.riskLabel
            + (ctx.riskScore != null ? (' · ' + formatRiskScoreFraction(ctx.riskScore)) : '')
            + '\n';
        return header + card;
    }

    private static String nz(String s) {
        return String.isBlank(s) ? '' : s;
    }
}
