# Data Cloud — dealer claim history & calculated insights

**Full runbook (every step, every object/field, insight formulas):** [DATA_CLOUD_SETUP_GUIDE.md](./DATA_CLOUD_SETUP_GUIDE.md)

**Use Case 2 (Slack approver + AI summary):** [USE_CASE_2_SLACK_APPROVER.md](./USE_CASE_2_SLACK_APPROVER.md)

**Slack Option 1 (Flow + buttons via Slack Workflow, no Apex callouts):** [WC_SLACK_OPTION1_BUILD.md](./WC_SLACK_OPTION1_BUILD.md)

**Manual checklist — post to Slack after deploy:** [MANUAL_SLACK_POST_STEPS.md](./MANUAL_SLACK_POST_STEPS.md)

This project adds **CRM fields** and **sample data** so you can connect **Salesforce CRM → Data Cloud** and build **Calculated Insights** for approvers (e.g. later in Slack).

## CRM fields (deployed with WC package)

| Field | Object | Purpose |
|--------|--------|---------|
| `WC_Claim_Effective_Date__c` | Claim | Rolling **30 / 60 / 90** day windows and **last claim date** per dealer (Apex cannot backdate `CreatedDate`). |
| `WC_Approval_Result__c` | Claim | Picklist: **Pending**, **Approved**, **Rejected** — approval / rejection **rates** per dealer without relying on org-specific `Claim.Status` values. |

Intake (`WC_CreateClaimIntakeAction`) sets **Effective Date = today** and **Approval Result = Pending**. New claims use name prefix **`WTY-`**.

## Seed data (run in CRM org)

After deploy, execute anonymous (admin):

```bash
sf apex run -f scripts/apex/wc_datacloud_claim_history_seed.apex -o <alias>
```

Or: `WC_DataCloudClaimHistorySampleData.seedDealerClaimHistory();`

Creates:

- **3 dealers**: Summit Motors Portland, Lakeside Auto Group Seattle, Riverside Chevrolet Sacramento  
- **6 vehicles** (Aurora EV-500 naming, synthetic VINs with prefix `1HGCV1F3…`)  
- **19 claims** with varied `WC_Claim_Effective_Date__c` (last ~90 days) and `WC_Approval_Result__c`  
- **Repeat-issue pattern**: multiple battery-related lines on Portland and overlapping part usage  
- **Product codes** (for catalog linkage): `VEH-AURORA-EV500`, `PART-HV-BATT-ASM`

Idempotent: if **Summit Motors Portland** already exists, the method returns without duplicating.

Single-dealer intake seed (`WC_UseCase1SampleData`) uses **Northside Automotive Group**, VIN `1HGCM82633A004251`, products `VEH-AURORA-EV500` / `PART-HV-BATT-001`.

## Data Cloud setup (UI — org-specific names)

1. **Connect CRM**  
   Data Cloud → **Connections** → connect your **Warranty** Salesforce org.  
   Ingest at minimum: **Account**, **Claim**, **ClaimItem** (and **Vehicle** / **Product2** if you extend insights).

2. **Data space & DMOs**  
   Map ingested objects to **Data Model Objects**. Note API names (often prefixed), e.g. `ssot__Salesforce_Claim__dlm` — **your org’s names will differ**.

3. **Relationships**  
   - Claim → Account (dealer): `Claim.AccountId`  
   - ClaimItem → Claim: `ClaimItem.ClaimId`  
   - ClaimItem → Product2 (for repeat-part analysis): `ClaimItem.ProductId`

## Calculated insights to build (specifications)

Use **Calculated Insight** in Data Cloud with **dealer** = `Account.Id` (from Claim → Account). Filter claims on **`WC_Claim_Effective_Date__c`**.

### 1. Claim volume — last 30 / 60 / 90 days

- **Dimension:** Dealer (`AccountId` on Claim)  
- **Measures:** `COUNT(Claim)` with filters on `WC_Claim_Effective_Date__c` for 30, 60, 90 day lookbacks.

### 2. Last claim date per dealer

- **Dimension:** Dealer  
- **Measure:** `MAX(WC_Claim_Effective_Date__c)`.

### 3. Approval / rejection rate per dealer

- **Dimension:** Dealer  
- **Measures:** Count by `WC_Approval_Result__c` = Approved / Rejected / Pending  
- **Rate:** Approved ÷ (Approved + Rejected) where appropriate.

### 4. Repeat issues (same part, same dealer)

- **Grain:** Dealer + Product (from ClaimItem via Claim)  
- **Filter:** `WC_Claim_Effective_Date__c` in chosen window  
- **Measure:** Count claims or line items where the same `ProductId` appears more than once for that dealer.

## Deploying insights as metadata

Calculated Insight definitions are often shipped via **Data Kit** / **DevOps manifest** from Data Cloud Setup. After you create insights in a **sandbox**, use **Download manifest** / metadata retrieve for your Data Kit and add the folder to source control.

## References

- [Data 360 / Data Cloud developer guide](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/data-cloud-intro.htm)  
- [Query calculated insights (API)](https://developer.salesforce.com/docs/data/data-cloud-ref/guide/c360a-api-insights-ci-ci-name.html)
