# Electra Cars — Warranty Intelligence Solution (Detailed Overview)

This document describes the warranty solution implemented for **Electra Cars**, where a very small approver team handles **more than one thousand claims per day**, historically driven largely by **email**. The solution uses **Salesforce standard automotive objects**, **Agentforce** (messaging and voice), **Slack** for approvers, **Einstein / Prompt Builder**, an **Experience Cloud–style dealer portal** (claim visibility), and patterns **aligned with Data Cloud** analytics on dealer history.

---

## 1. Business problem

- **Volume vs capacity:** Three approvers cannot sustainably triage 1000+ claims daily through unstructured email alone.
- **Consistency:** Decisions need shared context (vehicle, dealer, part, risk, history) in one place.
- **Speed:** Safe, low‑complexity claims should not wait for manual touch when policy and risk allow.
- **Dealer experience:** Dealers need transparency into **claim status and history** without flooding approvers with status requests.

---

## 2. Solution summary (conceptual)

The platform **captures** warranty intake through **conversational agents** (e.g. WhatsApp, voice), **persists** structured data on **Claim**, **ClaimItem**, **Vehicle**, and **Product2**, **notifies** approvers in **Slack** with **Block Kit** cards, **enriches** decisions with **Einstein-generated summaries and risk scores**, optionally **summarizes damage photos** from uploaded files, and **automates** straightforward approvals via **Electra** when risk is below threshold and no manual decision arrives in time. Dealers use a **portal experience** with **Lightning Web Components** to view **metrics and claim lists** tied to their **Account**.

---

## 3. Channel architecture

### 3.1 WhatsApp and messaging (Agentforce)

- **Agent authoring** (e.g. `WC_Warranty_Claim_Intake_UC1.agent`) defines the **warranty claim intake** dialogue: collect **VIN**, validate **Vehicle** and **dealer (Account)**, optionally **suggest a part** from the fault description, confirm details, then **create the claim**.
- **Invocable Apex** backs the agent:
  - **`WC_VehicleLookupAction`** — resolves VIN to **Vehicle**, **current owner / dealer**, warranty hints.
  - **`WC_SuggestPartAction`** — uses a **flex prompt** (`WC_Suggest_Part_From_Knowledge`) grounded on **Knowledge** to propose a **Product2**.
  - **`WC_CreateClaimIntakeAction`** — inserts **Claim** + **ClaimItem**, sets **WC\_** custom fields, enforces VIN/dealer/warranty rules, and publishes **`WC_WarrantyClaimSubmitted__e`** for downstream automation.
- **Submission channel** is stored on the claim (e.g. **WhatsApp**, **Web**, **Portal**) via **`WC_Submission_Channel__c`**.
- **Media (WhatsApp / Meta):** **`WC_CreateClaimIntakeWithAttachmentAction`** plus **`WC_ClaimMediaDownloadQueueable`** download **Graph / lookaside** media URLs using a **Bearer token** from **custom metadata** (`WhatsApp_Media_Bearer_Token__c`), then attach files to the **Claim** for later **Einstein** or human review.

#### WhatsApp Cloud API webhook (Meta → Salesforce)

Meta’s **WhatsApp Business Platform** sends customer traffic to a **callback URL** hosted on Salesforce (typically exposed via **Experience Cloud Site** or equivalent HTTPS endpoint). In this project:

- **`WhatsAppWebhookHandler`** (`@RestResource(urlMapping='/whatsapp/webhook/*')`) implements the webhook:
  - **GET — subscription verification:** Meta sends `hub.mode`, `hub.verify_token`, and `hub.challenge`. When `hub.mode = subscribe` and the token matches **`WhatsApp_Settings__c`** org defaults (`Verify_Token__c`), Apex returns **HTTP 200** with the **challenge** body so Meta activates the webhook.
  - **POST — events:** The raw JSON body is deserialized via **`WhatsAppPayloadDeserializer`** into **`WhatsAppWebhookPayload`** (nested `entry` → `changes` → `value`). Inbound **messages** (text, image, document, audio, interactive replies, etc.) are normalized; **delivery status** events (`sent`, `delivered`, `read`, `failed`) can be mapped for operational tracking.
- **Persistence and Agentforce handoff:** For each inbound message, the handler creates or updates **`WhatsApp_Message__c`** rows (external id on WhatsApp message id where configured), resolves or creates an **`Agentforce_Session__c`** via **`AgentforceSessionManager1`**, then enqueues **`AgentCalloutQueueable`** so **callouts** run in a separate transaction (avoiding “pending DML” limits). That queueable drives conversation with the **same Agentforce runtime** used for messaging and uses **`WhatsAppService`** for **outbound** Cloud API calls (`graph.facebook.com`, phone number id and API version from **`WhatsApp_Settings__c`**).
- **Operational note:** Webhook endpoints must use **HTTPS**, **Remote Site** (or Named Credential) settings for Graph, and **secrets** (verify token, system/user tokens) stored in **protected custom settings or Named Credentials**—not hard-coded in source for production.

Together, the webhook is the **ingress path** from WhatsApp into Salesforce; the **published warranty agent** plus invocable Apex is the **business logic** that turns chat into **Vehicle / Claim / ClaimItem / Product2** records.

### 3.2 Voice

- **Routing model:** Inbound **voice** is configured so that conversations are **handed to the same Agentforce agent** used for **WhatsApp** (e.g. the published **warranty claim intake** definition). Dealers therefore follow **one consistent dialogue and toolset**—VIN lookup, part suggestion, confirmation, claim creation—whether they message on WhatsApp or speak on the phone.
- **Platform glue:** **Service Cloud Voice** / **Messaging** routing flows (and channel entries in the org) point voice sessions at that **single agent**, rather than maintaining a separate voice-only bot. Standard objects and **`WC_*`** intake actions remain identical across channels.


### 3.3 Dealer portal (Experience / login)

- **LWCs** such as **`wcAccountClaimsDashboard`**, **`wcAccountClaimsTable`**, and **`wcAccountClaimsHub`** provide a **dealer-facing** view of **claim volume and status**.
- **`WC_AccountClaimsDashboardController`** aggregates **Claim** data by **Account** (pending / approved / rejected / this month) and supplies **datatable rows** (name, status, amounts, submission channel, approval channel, etc.) for **self-service history** without approver email ping‑pong.

---

## 4. Approver experience: Slack

### 4.1 Event-driven notification

- On claim submission, **`WC_WarrantyClaimSubmitted__e`** triggers the autolaunched Flow **`WC_Notify_Claim_Submitted_Slack_Webhook`** (see package manifest).
- The Flow loads the **Claim**, runs **`WC_GenerateApproverSummaryAction`** (persists **`WC_AI_Summary__c`**, **`WC_AI_Recommendation__c`**, **`WC_AI_Risk_Score__c`**), loads structured context via **`WC_GetApproverContextAction`**, builds **Block Kit JSON** via **`WC_BuildSlackApproverBlocksAction`**, and posts via **`WC_PostSlackWebhookMessageAction`** or bot **`WC_PostSlackBotMessageAction`** (metadata-driven URLs/tokens).
- **Slack message pointers** (**`WC_Slack_Channel_Id__c`**, **`WC_Slack_Message_Ts__c`**) are stored on the **Claim** so messages can be **updated** after decisions.

### 4.2 Rich card content

- Blocks include **vehicle**, **fault**, **part**, **labour**, **estimate**, **risk tier/score**, **Einstein summary**, and **Approve / Reject** buttons.
- When a **file** is linked to the claim, **`WC_BuildSlackApproverBlocksAction`** can call **`WC_Claim_Damage_Image_Summary`** to add a **plain-language “Document / photo summary”** section for visual triage.

### 4.3 Interactivity and CRM updates

- **`WC_SlackInteractivityRest`** (Apex REST) verifies **Slack signing**, parses **block actions**, and uses **`WC_SlackClaimApprovalService`** (with **`SYSTEM_MODE`** where appropriate for guest-safe updates) to set **`WC_Approval_Result__c`**, **`WC_Approval_Channel__c`**, **`WC_Approved_At__c`**, etc., and to **refresh** the Slack message (remove buttons / show outcome).
- **`WC_Update_Claim_From_Slack_Decision`** Flow supports alternative routing from Slack Workflows.

---

## 5. Einstein and prompts

Flex templates (examples in repo):

| Template | Role |
|----------|------|
| **`WC_Suggest_Part_From_Knowledge`** | JSON structured **part match** from fault + optional vehicle context (Knowledge grounding). |
| **`WC_Approver_Slack_Summary`** | **Approver summary**, **recommended action**, **confidence**, **riskScore** (0–100) for Slack. |
| **`WC_Electra_Auto_Approval_Reason`** | Short **audit justification** when Electra auto-approves. |
| **`WC_Approver_Policy_QA`** | Policy / Q&A style prompt (as packaged). |
| **`WC_Claim_Damage_Image_Summary`** | **Vision** summary of **damage photo** (ContentDocument input). |

**`WC_Prompt_Config__mdt`** holds **template names** and **Einstein application name** so environments can vary without code changes.

### 5.1 Agentforce Einstein Data Library (Knowledge + insurance policy PDFs)

Grounding for warranty AI is delivered through **Einstein / Agentforce Data Libraries** configured in **Prompt Builder** (and related Agent tooling), not by hard-coding documents into prompts:

- **Knowledge articles** — Service bulletins, symptom guides, and internal write-ups are indexed in a Data Library and attached to the **part-suggestion** flex template (`WC_Suggest_Part_From_Knowledge`). The model retrieves relevant passages and maps **fault text + vehicle context** to the correct **Product2** (JSON contract enforced by invocable Apex).
- **Insurance / warranty policy PDFs** — Official policy documents (PDF) are ingested into the same or a companion library so retrieval can cite **coverage rules, exclusions, and definitions** when answering questions—without approvers opening attachments manually for every thread.
- **Slack-side answers** — The **Electra Approver** style Agentforce agent is authored to respond to **approver questions in Slack** using **claim history plus policy documents available through the Data Library** (alongside Knowledge where configured). That complements the structured Block Kit card (summary, risk, buttons) when someone asks “does this meet policy?” or similar.

Together, Data Libraries unify **tribal Knowledge**, **catalog semantics**, and **legal/policy PDF text** into one retrieval surface for Agentforce-driven intake and approver assistance.

---

## 6. Electra automated approver

- **`WC_ElectraAutoApproveProcessor`** processes claims that remain **Pending** after a scheduled check time (**`WC_Electra_Auto_Check_At__c`**), when **`WC_AI_Risk_Score__c`** is present and **strictly below 50** (configurable constant in code).
- Generates a **reason** via **`WC_ElectraApprovalReasonGenerator`** (prompt + fallback text), updates the **Claim** to **Approved** with **`WC_Approval_Channel__c = Electra`**, sets **`WC_Approved_At__c`**, clears the Electra schedule field, and enqueues **`WC_ElectraSlackUpdateQueueable`** to **`chat.update`** Slack when channel/ts exist.
- **`WC_ElectraAutoApproveScheduler`** / **`WC_ElectraAutoApproveSchedulable`** poll on an interval from **`WC_Slack_Approval_Config__mdt`** (`Electra_Poll_Interval_Sec__c`, `Electra_Auto_Approve_Delay_Seconds__c`, **`WC_ElectraConfig`**).

This reduces manual load on the three approvers for **objectively lower-risk** queue entries while keeping **audit notes** on the record.

---

## 7. Data model (standard + WC extensions)

- **Standard:** **`Account`** (dealer), **`Vehicle`**, **`Claim`**, **`ClaimItem`**, **`Product2`**, **`Asset`** (as used in tests/sample flows).
- **Custom fields on Claim** (representative): **`WC_Submission_Channel__c`**, **`WC_Approval_Result__c`**, **`WC_Approval_Channel__c`**, **`WC_Approved_At__c`**, **`WC_Time_To_Decision_Minutes__c`** (formula), **`WC_AI_*`**, Slack pointers, Electra scheduling/notes, etc.
- **Product2:** labour/part pricing and **`WC_Fault_Keywords__c`**, **`WC_Model_Compatibility__c`** to support **part suggestion** and **estimate** calculation on intake.
- **Platform event:** **`WC_WarrantyClaimSubmitted__e`** decouples **submission** from **Slack/Einstein** work.

---

## 8. Data Cloud alignment

- **`WC_ApproverContextService`** builds a **dealer insights narrative** using **SOQL aggregates** over historical **Claims** (volumes, outcomes, repeat part patterns, recency). The class header documents that these metrics are **aligned with Data Cloud Calculated Insight definitions** on the **same CRM data**, so the org can later **swap** or **augment** with **Data Cloud Query API** without changing the **approver UX**.
- **`WC_DataCloudClaimHistorySampleData`** seeds **realistic historical claims** across dealers/parts for **CI / analytics** demos (rolling windows, approval mix, repeat faults).

Files on **Claims** also feed **Einstein** multimodal prompts (damage summary) and can be integrated with **Data Cloud file ingestion** patterns where required.

---

## 9. Security, integration, and operations

- **Permission sets** (e.g. **`WC_Warranty_Claim_Integration`**, **`WC_Warranty_Claim_Integration_Agent`**, **`WC_Slack_Interactivity_Guest`**) grant **Apex**, **Flow**, and **REST** access appropriate for **integration users** and **Experience guests**.
- **Remote site settings** for **Slack**, **Meta Graph**, and **lookaside** media support **callouts**.
- **Custom metadata** **`WC_Slack_Approval_Config__mdt`** centralizes **webhook URL**, **bot token**, **signing secret**, **Electra timings**, and **WhatsApp media token** (secrets should remain **org-only**, not in source control values).

---

## 10. Outcomes for Electra Cars

- **Approvers** work from **structured Slack** cards with **AI summary, risk score, optional photo narrative**, and **one-click** decisions instead of parsing long email threads.
- **Dealers** self-serve **status and history** via the **portal components**.
- **Operations** gain **timestamps and channels** for **reporting** (e.g. time-to-decision, portal vs non-portal) and a path to **full Data Cloud** dealer intelligence.
- **Electra** automation clears a **predictable slice** of **low-risk** work **safely** and **transparently**.

---

## 11. Repository map (quick reference)

| Area | Key artifacts |
|------|-----------------|
| Intake | `WC_CreateClaimIntakeAction`, `WC_CreateClaimIntakeWithAttachmentAction`, `WC_ClaimMediaDownloadQueueable`, `WC_VehicleLookupAction`, `WC_SuggestPartAction` |
| WhatsApp webhook | `WhatsAppWebhookHandler`, `WhatsAppWebhookPayload`, `WhatsAppPayloadDeserializer`, `WhatsAppService`, `AgentCalloutQueueable`, `AgentforceSessionManager1`, `WhatsApp_Settings__c` |
| Agent | `aiAuthoringBundles/WC_Warranty_Claim_Intake_UC1/` |
| Slack | `WC_BuildSlackApproverBlocksAction`, `WC_PostSlackWebhookMessageAction`, `WC_PostSlackBotMessageAction`, `WC_SlackInteractivityRest`, `WC_SlackClaimApprovalService`, Flow `WC_Notify_Claim_Submitted_Slack_Webhook` |
| Electra | `WC_ElectraAutoApproveProcessor`, `WC_ElectraApprovalReasonGenerator`, schedulable/scheduler |
| Context / analytics | `WC_ApproverContextService`, `WC_DataCloudClaimHistorySampleData` |
| Portal UI | `lwc/wcAccountClaimsDashboard`, `wcAccountClaimsTable`, `wcAccountClaimsHub`, `WC_AccountClaimsDashboardController` |
| Prompts + grounding | `genAiPromptTemplates/WC_*.genAiPromptTemplate-meta.xml`; **Data Libraries** (Knowledge + policy PDFs) configured in Prompt Builder / Agent |
| Approver agent (Slack Q&A) | `bots/Electra_Approver_Agent/` (uses policy + claim context via Data Library) |
| Config | `WC_Prompt_Config__mdt`, `WC_Slack_Approval_Config__mdt`, `WC_WarrantyClaimSubmitted__e` |

---

*This overview reflects the metadata and Apex present in the **Warranty-Dev** project. Org-specific routing (e.g. additional voice flows, Experience Cloud site names, or Data Cloud connections) may be configured in the target Salesforce org beyond what is stored in source control.*
