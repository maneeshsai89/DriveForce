# Use Case 2 — Slack approver notification (Agentforce + Einstein)

This matches the storyboard in `slack_approver_warranty_workflow.html`: after Use Case 1 submits a claim, automation notifies **#warranty-approvals** with claim fields, **risk score**, **dealer metrics** (same definitions as your Data Cloud Calculated Insights, computed in CRM for the notification path), and an **AI summary** from the Flex prompt **`WC_Approver_Slack_Summary`**.

You create the **second agent** (Approver Assistant) and **Slack** wiring manually; this repo ships the **Apex actions**, **prompt template**, and **recommended Flow**.

---

## What was added in metadata

| Artifact | Purpose |
|----------|---------|
| `WC_ApproverContextService` | Builds claim + dealer “insight” narrative (30/60/90 volumes, approval mix 90d, repeat part 180d, last prior claim date). Same logic as CI on CRM data; optional later swap to Data Cloud Query API. |
| `WC_GetApproverContextAction` | **Invocable** — outputs all fields for Slack / agent (including `slackPlainTextBody`, `dealerInsightsNarrative`). |
| `WC_GenerateApproverSummaryAction` | **Invocable** — runs **`WC_Approver_Slack_Summary`** via Einstein; optional **Persist To Claim** = writes `Claim.WC_AI_Summary__c` and `WC_AI_Recommendation__c`. |
| `WC_ApproverSummaryLlmParser` | Parses JSON from the approver prompt. |
| `genAiPromptTemplates/WC_Approver_Slack_Summary` | Flex template; **Publish** in Prompt Builder after deploy. |
| `WC_Prompt_Config.WC_Approver_Slack_Summary` | CMD: template name + `EinsteinGpt` app name. |

---

## Org setup checklist

### 1. Deploy and tests

```bash
sf project deploy start -o <alias> -x manifest/WC_package.xml --test-level RunSpecifiedTests --tests WC_GetApproverContextActionTest --tests WC_GenerateApproverSummaryActionTest --tests WC_ApproverSummaryLlmParserTest --tests WC_CreateClaimIntakeActionTest --tests WC_SuggestPartLlmParserTest --tests WC_SuggestPartActionTest --tests WC_VehicleLookupActionTest
```

### 2. Prompt template

1. **Setup → Einstein → Prompt Builder** → open **WC Approver Slack Summary**.  
2. **Publish** the template (deploy may land as **Draft**).  
3. Optional: attach a **Data Library** if you want extra grounding (metrics already come from Apex inputs).  
4. If your org uses a non-default LLM app name, set **`WC_Prompt_Config__mdt.WC_Approver_Slack_Summary.Llm_Application_Name__c`**.

### 3. Salesforce for Slack

1. Install/configure **Salesforce for Slack** (or **Einstein for Slack** where applicable).  
2. Connect the Slack workspace and authorize the **#warranty-approvals** channel (or your channel).  
3. Ensure the **integration user** used by the Flow can post to that channel.

### 4. Who “sends” Slack — Agentforce vs Flow (read this)

**Important:** Agentforce agents are **conversational runtimes**. They normally **respond** after a user (or automation) **starts a turn**. They do not sit in the background and post to Slack by themselves unless your org wires one of the patterns below.

You can still meet the requirement **“the notification is sent by the Agentforce agent”** in these ways:

| Approach | What happens | Best when |
|----------|----------------|-----------|
| **A. Same Slack app identity (most common)** | **Einstein for Slack** connects your **Approver Agent** to the workspace. An **autolaunched Flow** (triggered by `WC_WarrantyClaimSubmitted__e`) calls **`WC_GenerateApproverSummaryAction`** + **`WC_GetApproverContextAction`**, then uses the **Salesforce for Slack / Einstein for Slack** action **Send message to Slack** (or equivalent) so the message is posted **as that connected agent app** (name + avatar in `#warranty-approvals`). The **agent** is the Slack app; **Flow** is the trigger. | You want proactive “new claim” posts without building custom Slack APIs. |
| **B. Start an agent session from automation** | After the platform event, Flow (or an **orchestration**) uses **Start agent conversation** / **Invoke Einstein Agent** / **Agent API** (exact action names depend on your **Agentforce + Slack** SKU and release) with an **initial prompt** such as: *Summarise claim `{!Claim.Id}` for approvers and respond with the notification text only.* The agent uses topics + actions (`WC_GenerateApproverSummaryAction`, `WC_GetApproverContextAction`). You still need a **channel delivery** mechanism: either the **Einstein for Slack** runtime posts the agent’s reply into the channel, or a follow-up step posts the agent output. | You need the **reasoning trace** and tool use to show up as an **agent run** in analytics. |
| **C. Custom “post to Slack” agent action** | You add an invocable (or **External Service**) **Post to Slack** and register it as an **agent action**; the **first message** of a session instructs the agent to call it. Proactive delivery still requires something to **start the session** (Flow + Agent API or similar). | You need Block Kit / threading control beyond the packaged Slack action. |

**Practical recommendation:** Use **A** unless compliance requires a logged **agent session** for every notification (**B**). The repo’s Apex actions are the **tools** the Approver Agent uses when a human @mentions it; **A** reuses the same summary/context logic from Flow for the **initial proactive post** so content matches.

---

### 5. Autolaunched Flow — “notify approver on claim submitted”

**Trigger:** Platform event **`WC_WarrantyClaimSubmitted__e`** (fires from `WC_CreateClaimIntakeAction` after successful insert).

**Steps (works with pattern A or as the data prep for B):**

1. **Create Flow** (autolaunched) → trigger **Platform Event** `WC_WarrantyClaimSubmitted__e`.  
2. **Get Records** — `Claim` where `Id = {!$Record.WC_Claim_Id__c}` (or use event payload only; Claim Id is on the event).  
3. **Action** — `WC_GenerateApprover Summary`  
   - **Claim Id** = `{!Claim.Id}` or `{!$Record.WC_Claim_Id__c}`  
   - **Persist To Claim** = `true` (recommended so `WC_AI_Summary__c` is stored for audit).  
4. **Action** (optional) — `WC_GetApprover Context` — use outputs to build Block Kit or long text.  
5. **Slack** — **Send Slack Message** to **#warranty-approvals** using the **Einstein for Slack / Salesforce for Slack** integration tied to your **Approver Agent** so the post appears **from that agent**.  
   - Body: combine `{!Generate_Summary.aiSummary}`, claim name, dealer, VIN, risk from context variables.  
6. **(Pattern B only)** Add a step **Start / Invoke Agent** with `Claim.Id` in the prompt and ensure your Slack deployment posts the agent reply to the channel (per org docs).  
7. **Fault paths** — log errors to a custom log object or Chatter; do not block claim commit (event already published).

**Setup alignment:** In **Agent Builder**, open your **Approver Agent** → confirm **Slack** (or **Einstein for Slack**) is an **allowed channel** and the agent is **installed in the Slack workspace** and **authorized for `#warranty-approvals`**. The Flow should run as (or delegate to) a user that can act on behalf of that integration.

---

### 6. Same channel: proactive post (Flow) + approver questions (agent)

**Yes — pattern (1) supports both:** the **same** Einstein for Slack app that posts the notification can be **in the channel** so approvers **@mention** the agent and get answers.

| Concern | What to do |
|---------|------------|
| **Add the agent to `#warranty-approvals`** | In Slack: **Integrations** on the channel, or `/invite @<Your Agent App Name>` (exact name comes from the Slack app install). Ensure the app is allowed to receive messages in that channel (Einstein for Slack / app settings). |
| **Link channel in Salesforce** | In **Einstein for Slack** / **Salesforce for Slack** setup, map the **Slack workspace** and **channel** to Salesforce so the agent session can attach to the right context (follow the in-product wizard for your release). |
| **Claim context for follow-up turns** | The proactive Flow message should include **`Claim Id` or `Claim Name`** in plain text (or Block Kit) so the agent (or the user) can reference it. In **Agent instructions**, tell the agent: when the user asks about “this claim,” parse **Claim Id** from the thread or ask once if missing; then call **`WC_GetApproverContextAction`** / **`WC_GenerateApproverSummaryAction`** with that Id. |
| **Threading** | Approvers can **reply in thread** and **@mention** the agent, matching `slack_approver_warranty_workflow.html`. Configure the agent so **thread replies** are handled (Einstein for Slack usually continues the session in-thread when the app is configured for it). |

**Summary:** Flow sends the first message **as the app**; the **same Agentforce agent** behind that app **stays in the channel** for interactive Q&A using the invocable actions you attached. No conflict between (1) and conversational use — they complement each other.

---

## Second Agent (Approver Assistant) — actions to attach manually

Create a new **Agent** (e.g. **WC Warranty Approver Assistant**) for **Slack / internal approvers**, *not* the WhatsApp intake bot.

Add **topics** for:

| Topic intent | Invocable action | Inputs | Notes |
|--------------|------------------|--------|--------|
| Explain this claim / summarise | `WC_GenerateApproverSummaryAction` | `claimId`, `persistToClaim` = false | Idempotent read; can regenerate summary. |
| Show claim + dealer history for Slack | `WC_GetApproverContextAction` | `claimId` | Use `dealerInsightsNarrative` + `slackPlainTextBody`. |
| (Optional) Re-use intake lookup | `WC_VehicleLookupAction` | `vin` | If approver pastes a VIN. |

**Reasoning instructions (example):**

- When the user asks about **repeat parts**, **dealer frequency**, or **risk**, prefer outputs from **`WC_GetApproverContextAction`** (`dealerInsightsNarrative` already includes repeat-part and volume signals aligned with CI).  
- For a **short approver summary**, call **`WC_GenerateApproverSummaryAction`** with the **Claim Id** from the Slack thread context (store Claim Id in the thread’s Salesforce record or pass as session variable if your Slack app supports it).

**Slack thread behaviour (per `slack_approver_warranty_workflow.html`):**

- Approvers **@mention** the agent in thread; map **Slack thread → Messaging Session or custom wrapper** per your **Einstein for Slack** configuration.  
- Suggested prompts in the HTML (“repeat claims for same part…”) map to natural-language questions that should route to the same actions.

---

## Data Cloud Calculated Insights vs Apex metrics

- **Calculated Insights** in Data Cloud remain the **system of record** for analytics and optional **activation** back to CRM.  
- **`WC_ApproverContextService`** recomputes the **same dealer-level definitions** from **live CRM** so the Slack notification does not depend on Data Cloud sync latency.  
- To **replace** SOQL with **Data Cloud Query API** later, add a **Named Credential** + thin Apex callout and merge the JSON into `dealerInsightsNarrative`—the prompt and Slack formatting stay the same.

---

## Related files

- Storyboard: `slack_approver_warranty_workflow.html`  
- Intake agent bundle (UC1): `force-app/main/default/aiAuthoringBundles/WC_Warranty_Claim_Intake_UC1/`  
- Platform event: `WC_WarrantyClaimSubmitted__e`  
- **Slack Option 1 (Flow notify + approve/reject without Apex callouts):** [WC_SLACK_OPTION1_BUILD.md](./WC_SLACK_OPTION1_BUILD.md)
