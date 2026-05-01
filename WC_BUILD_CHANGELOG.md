# WC — Warranty Claim build changelog

This file records every artifact added or changed for the Electra warranty claim implementation. All custom components use the **`WC_`** prefix.

---

## Use case 1 — Claim intake (dealer → structured Claim)

End-to-end intake: **VIN lookup → optional part suggestion → dealer confirms → create `Claim` + `ClaimItem` → publish `WC_WarrantyClaimSubmitted__e`.**

### Objects involved (standard + WC)

| Layer | Object | Role in intake | WC customizations |
|-------|--------|----------------|-------------------|
| Dealer | **Account** | Claim `AccountId`; must match **Vehicle.CurrentOwnerId** for create validation. | None (use standard Account). |
| Vehicle | **Vehicle** | VIN resolution; `CurrentOwnerId` → dealer; warranty dates / `AssetId`. | None; **WC_VehicleLookupAction** returns `vehicleId`, `dealerAccountId`. |
| Asset / warranty | **Asset**, **AssetWarranty** | Eligibility via `AssetWarranty.EndDate` (or manufacturer dates on Vehicle). | None; used in lookup + **WC_CreateClaimIntakeAction** active-warranty check. |
| Part | **Product2** | Claimed part on **ClaimItem.ProductId**. | **`WC_Fault_Keywords__c`**, **`WC_Model_Compatibility__c`** (catalogue / UI; part suggestion uses **Prompt Builder** + **Knowledge Data Library**, then resolves **Product2** by Id or **ProductCode**). |
| Claim header | **Claim** | Intake record; fault text in **Summary**; status **Submitted**; `EstimatedAmount`; WC channel/source/AI risk. | All **`Claim.WC_*`** fields from Phase 1. |
| Claim line | **ClaimItem** | Vehicle + product + fault; **FaultDate** set to `now` (org requires it); **AssetUsageValue** = mileage. | **`WC_Labour_Hours__c`**. |
| Automation | **WC_WarrantyClaimSubmitted__e** | Notifies Slack / downstream. | Event field payloads **WC_***. |

### Invocable actions (Agentforce wiring)

| Apex class | Label | Purpose |
|------------|-------|---------|
| `WC_VehicleLookupAction` | WC Lookup Vehicle by VIN | Input: VIN. Output: model, year, warranty, dealer name, **`vehicleId`**, **`dealerAccountId`**, `found`. |
| `WC_SuggestPartAction` | WC Suggest Part From Fault | Input: fault text, optional vehicle model. Calls **Flex prompt** (name in **`WC_Prompt_Config__mdt`**) with **Knowledge** grounding; parses JSON; returns **Product2** (optional **WC_Model_Compatibility__c** filter). |
| `WC_CreateClaimIntakeAction` | WC Create Claim Intake | Input: dealer, vehicle, product, VIN, fault, mileage, labour, estimated amount, submission channel, optional AI risk. Creates **Claim** + **ClaimItem**, publishes platform event. |

### Agentforce agent (Use Case 1)

| Artifact | Purpose |
|----------|---------|
| `aiAuthoringBundles/WC_Warranty_Claim_Intake_UC1/` | **AiAuthoringBundle** — Agent Script (`.agent`) for **WC Warranty Claim Intake**: one subagent (`warranty_claim_intake`) with three Apex actions: `apex://WC_VehicleLookupAction`, `apex://WC_SuggestPartAction`, `apex://WC_CreateClaimIntakeAction`. |

**Local validation:** `sf agent validate authoring-bundle --api-name WC_Warranty_Claim_Intake_UC1 -o <alias>`

**Deploy:** include `AiAuthoringBundle` in the package or deploy the folder:  
`sf project deploy start -d force-app/main/default/aiAuthoringBundles -o <alias> --test-level NoTestRun`

**Publish (optional):** `sf agent publish authoring-bundle --api-name WC_Warranty_Claim_Intake_UC1 -o <alias>` — creates/updates the live Agent and related Bot metadata; if the CLI call to the Einstein authoring API fails (network/org), rely on metadata deploy and finish activation in **Agent Builder**.

**Open in UI:** `sf org open agent -o <alias> --api-name <Agent_API_Name>` — the **agent** API name may differ from the bundle name after publish; check **Setup → Agents** if needed.

**Config:** In `WC_Warranty_Claim_Intake_UC1.agent`, `config.default_agent_user` is set to the Salesforce user the agent runs as (data access). Change it per org to an **integration user** with **WC_Warranty_Claim_Integration** (and Einstein/Generative AI permissions as required).

### Tests

`WC_VehicleLookupActionTest`, `WC_SuggestPartActionTest`, `WC_SuggestPartLlmParserTest`, `WC_CreateClaimIntakeActionTest` (parser + blank-input tests run in CI; full LLM path is validated in org with Prompt Template deployed).

### Use case 2 — Slack approver notification (claim submitted → Slack + AI summary)

| Artifact | Purpose |
|----------|---------|
| `WC_ApproverContextService` | Dealer metrics from CRM (same definitions as Data Cloud CI: 30/60/90 counts, approval mix, repeat part, last prior date). |
| `WC_GetApproverContextAction` | Invocable — claim + dealer narrative + `slackPlainTextBody` for Flow / Agent. |
| `WC_GenerateApproverSummaryAction` | Invocable — Flex prompt `WC_Approver_Slack_Summary`; optional persist to `Claim.WC_AI_Summary__c` / `WC_AI_Recommendation__c`. |
| `WC_ApproverSummaryLlmParser` | JSON parse for approver prompt output. |
| `WC_Approver_Slack_Summary` | GenAi Flex template (deploy + **Publish** in org). |
| `WC_Prompt_Config.WC_Approver_Slack_Summary` | CMD for template + LLM app name. |
| `WC_BuildSlackApproverBlocksAction` | Invocable — builds Block Kit JSON (no HTTP) to approximate `slack_approver_warranty_workflow.html` in Slack. |

Setup: `data-cloud/USE_CASE_2_SLACK_APPROVER.md`, `data-cloud/WC_SLACK_OPTION1_BUILD.md`.

### Not in this use case (later)

- **MessagingSession** / Digital Engagement routing (configure in org).
- **WC_GetClaimStatus** style action (use case: status enquiry).
- **Slack approve/reject buttons** → Flow updates `Claim` (wire separately).

---

## 2026-04-13 — Einstein Prompt Builder + Data Library (part suggestion)

### Runtime behavior

- **`WC_SuggestPartAction`** calls **`ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`** using the Flex template developer name from **`WC_Prompt_Config__mdt.WC_Suggest_Part_From_Knowledge.Suggest_Part_Template_Name__c`** (default **`WC_Suggest_Part_From_Knowledge`**) and **`Llm_Application_Name__c`** (default **`EinsteinGpt`**; change if your org uses another context, e.g. preview).
- **`WC_SuggestPartLlmParser`** extracts JSON from the model reply (including optional ``` fences) and reads **`matchFound`**, **`productId`**, **`productCode`**.
- Apex then loads **one** active **`Product2`** by **Id** or **ProductCode** (not catalogue text search). Optional **vehicle model** still filters against **`WC_Model_Compatibility__c`** when that field is populated on the product.

### Source metadata

- **`genAiPromptTemplates/WC_Suggest_Part_From_Knowledge.genAiPromptTemplate-meta.xml`** — **Flex** template (`einstein_gpt__flex`), **Published**, inputs **`Input:Fault_Description`** and **`Input:Vehicle_Model`**, model **`sfdc_ai__DefaultGPT4Omni`**. Matches **`WC_Prompt_Config__mdt.WC_Suggest_Part_From_Knowledge`** (same API name as the prompt).

### Org setup (Prompt Builder + Data Library)

1. Deploy the **`GenAiPromptTemplate`** component (requires **Prompt Builder** enabled and rights to deploy prompts).
2. Open **Prompt Builder** → **WC Suggest Part From Knowledge**. The metadata deploys as **Draft**; **Publish** (activate) the version before **`WC_SuggestPartAction`** calls it in production. Attach your **Einstein Data Library** so **Knowledge** (and optional **Product2** fields) ground the model.
3. Confirm merge fields **`{!$Input:Fault_Description}`** and **`{!$Input:Vehicle_Model}`** match the deployed inputs (they should if you use this file unchanged).
4. Assign users the **Einstein / Generative AI** permissions your org requires; integration users must be able to run the template.
5. If **`EinsteinGpt`** is wrong for your org, update **`WC_Prompt_Config__mdt.WC_Suggest_Part_From_Knowledge.Llm_Application_Name__c`** (e.g. after testing in Prompt Builder preview).

If a deploy fails on **`versionIdentifier`** / **`activeVersion`** (org version skew), retrieve the template from a working org once and merge, or create a **Draft** version in the UI and re-retrieve into the repo.

**Custom Metadata record name:** The CMD record developer name is **`WC_Suggest_Part_From_Knowledge`** (same as the Flex prompt). Deploys use **`manifest/destructiveChangesPost_WC_Prompt_Default.xml`** once to remove the legacy **`WC_Prompt_Config.WC_Default`** record from orgs that had it; if that delete fails (record never existed), deploy without `--post-destructive-changes`.

---

## 2026-04-13 — Phase 1: Foundation metadata + vehicle lookup

### Added

| Item | Type | Purpose |
|------|------|---------|
| `WC_BUILD_CHANGELOG.md` | Doc | This changelog (you are here). |
| `Claim` custom fields | Field | AI, channels, approval metadata, service bulletin ref (see below). |
| `ClaimItem` custom field | Field | Labour hours for warranty line. |
| `WC_WarrantyClaimSubmitted__e` | Platform event | Fires after claim intake for Slack / automation (payload fields below). |
| `WC_VehicleLookupAction` | Apex (invocable) | VIN → vehicle + warranty summary for Agentforce intake. |
| `WC_VehicleLookupActionTest` | Apex test | Unit tests for lookup action. |
| `WC_Warranty_Claim_Integration` | Permission set | Field-level access + Apex class access for integrators. |
| `manifest/WC_package.xml` | Manifest | Metadata API package listing all **WC_** components (retrieve / deploy subset). |
| `Product2.WC_Fault_Keywords__c`, `Product2.WC_Model_Compatibility__c` | Field | Part catalogue helpers for intake / Einstein (see Use Case 1). |
| `WC_SuggestPartAction` (+ Test) | Apex | Part suggestion from fault + model. |
| `WC_CreateClaimIntakeAction` (+ Test) | Apex | Create Claim + ClaimItem + publish event. |

### Manifest (`package.xml`)

| File | Purpose |
|------|---------|
| `manifest/package.xml` | Default project template (generic Apex/LWC types). |
| **`manifest/WC_package.xml`** | **WC-only** manifest: `ApexClass`, `CustomField` (Claim, ClaimItem, platform event), `CustomObject` (event), `PermissionSet`. Use with Metadata API retrieve/deploy when you want exactly this bundle. |

**Retrieve example** (from repo root):

```bash
sf project retrieve start -o warrantyagentorg -x manifest/WC_package.xml
```

**Deploy using manifest** (alternative to `--source-dir`):

```bash
sf project deploy start -o warrantyagentorg -x manifest/WC_package.xml --test-level RunSpecifiedTests --tests WC_VehicleLookupActionTest --tests WC_SuggestPartActionTest --tests WC_SuggestPartLlmParserTest --tests WC_CreateClaimIntakeActionTest
```

#### Contents of `manifest/WC_package.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>WC_CreateClaimIntakeAction</members>
        <members>WC_CreateClaimIntakeActionTest</members>
        <members>WC_SuggestPartAction</members>
        <members>WC_SuggestPartActionTest</members>
        <members>WC_SuggestPartLlmParser</members>
        <members>WC_SuggestPartLlmParserTest</members>
        <members>WC_VehicleLookupAction</members>
        <members>WC_VehicleLookupActionTest</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Claim.WC_AI_Recommendation__c</members>
        <members>Claim.WC_AI_Risk_Score__c</members>
        <members>Claim.WC_AI_Summary__c</members>
        <members>Claim.WC_Approval_Channel__c</members>
        <members>Claim.WC_Approved_By_User__c</members>
        <members>Claim.WC_Claim_Source__c</members>
        <members>Claim.WC_Dealer_Notified_At__c</members>
        <members>Claim.WC_Part_Coverage_Status__c</members>
        <members>Claim.WC_Rejection_Reason__c</members>
        <members>Claim.WC_Service_Bulletin_Ref__c</members>
        <members>Claim.WC_Submission_Channel__c</members>
        <members>ClaimItem.WC_Labour_Hours__c</members>
        <members>Product2.WC_Fault_Keywords__c</members>
        <members>Product2.WC_Model_Compatibility__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Claim_Id__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Claim_Name__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Dealer_Account_Id__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Dealer_Name__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Estimated_Value__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Recommended_Action__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Risk_Score__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_Submitted_At__c</members>
        <members>WC_WarrantyClaimSubmitted__e.WC_VIN__c</members>
        <members>WC_Prompt_Config__mdt.Llm_Application_Name__c</members>
        <members>WC_Prompt_Config__mdt.Suggest_Part_Template_Name__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>WC_WarrantyClaimSubmitted__e</members>
        <members>WC_Prompt_Config__mdt</members>
        <name>CustomObject</name>
    </types>
    <types>
        <members>WC_Prompt_Config.WC_Suggest_Part_From_Knowledge</members>
        <name>CustomMetadata</name>
    </types>
    <types>
        <members>WC_Warranty_Claim_Integration</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>WC_Suggest_Part_From_Knowledge</members>
        <name>GenAiPromptTemplate</name>
    </types>
    <version>66.0</version>
</Package>
```

### Claim fields (`WC_*__c`)

| API name | Type | Notes |
|----------|------|--------|
| `WC_AI_Risk_Score__c` | Number(3,0) | 0–100 risk score from automation. |
| `WC_AI_Summary__c` | Long Text | Approver-facing AI summary. |
| `WC_AI_Recommendation__c` | Picklist | Approve / Reject / Review. |
| `WC_Claim_Source__c` | Picklist | Agentforce / Manual / Email. |
| `WC_Submission_Channel__c` | Picklist | WhatsApp / Web / Portal. |
| `WC_Approval_Channel__c` | Picklist | Slack / Portal / API. |
| `WC_Approved_By_User__c` | Lookup(User) | Human approver. |
| `WC_Dealer_Notified_At__c` | DateTime | WhatsApp / outbound notify timestamp. |
| `WC_Service_Bulletin_Ref__c` | Text(255) | SB or knowledge reference. |
| `WC_Part_Coverage_Status__c` | Picklist | Covered / Excluded / Partial. |
| `WC_Rejection_Reason__c` | Long Text | Dealer-safe rejection reason. |

### ClaimItem fields

| API name | Type | Notes |
|----------|------|--------|
| `WC_Labour_Hours__c` | Number(4,1) | Labour hours for the line. |

### Platform event `WC_WarrantyClaimSubmitted__e` fields

| API name | Type |
|----------|------|
| `WC_Claim_Id__c` | Text(18) |
| `WC_Claim_Name__c` | Text(80) |
| `WC_Dealer_Account_Id__c` | Text(18) |
| `WC_Dealer_Name__c` | Text(255) |
| `WC_VIN__c` | Text(17) |
| `WC_Estimated_Value__c` | Currency |
| `WC_Risk_Score__c` | Number(3,0) |
| `WC_Recommended_Action__c` | Text(20) |
| `WC_Submitted_At__c` | DateTime |

### Data model alignment (this org)

- **Claim** + **ClaimItem** replace custom `WarrantyClaim__c`; **Vehicle** replaces `Vehicle__c`; **Product2** replaces `Part__c`; **AssetWarranty** + **WarrantyTerm** replace custom `Warranty__c`.
- Intake flows should create **Claim**, then **ClaimItem** with `VehicleId`, `ProductId`, `Description`, `WC_Labour_Hours__c`, and set **Claim** standard + `WC_*` fields.

### Deploy

From project root:

```bash
sf project deploy start -o warrantyagentorg --source-dir force-app/main/default --test-level RunSpecifiedTests --tests WC_VehicleLookupActionTest --tests WC_SuggestPartActionTest --tests WC_SuggestPartLlmParserTest --tests WC_CreateClaimIntakeActionTest
```

Run tests after deploy:

```bash
sf apex run test -n WC_VehicleLookupActionTest -o warrantyagentorg -r human -w 10
```

### Deployed to `warrantyagentorg` (2026-04-13)

| Result | Detail |
|--------|--------|
| Status | **Succeeded** — metadata deployed to Org Id `00Dbm00000fmDubEAE`. |
| Apex tests | **WC_VehicleLookupActionTest** — 5 methods, **100% pass** (Run Id recorded in CLI output when executed). |

### Implementation notes discovered during build

- **`Claim.WC_Approved_By_User__c`**: Lookup metadata must **not** include `relationshipOrder` (Salesforce rejects it for this field type).
- **Permission set**: `Account` read in a permission set required adding **`Contact`** read (org dependency rule).
- **`WC_VehicleLookupActionTest`**: `Vehicle.ModelName` and `Vehicle.ModelYear` are **not writeable** on insert; test data only sets required Vehicle fields. Assertions use **dealer name** and **warranty status** instead of model text.

---

### Pending (later phases)

- Autolaunched Flow `WC_Create_Warranty_Claim` (create Claim + ClaimItem + publish event).
- Additional invocable actions: part suggest, claim status, risk score, Slack approval flow.
- Agentforce topic/action wiring in Builder (manual in org).

---

*End of log — append new dated sections as the build continues.*
