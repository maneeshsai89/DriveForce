# Manual steps — post a warranty claim message to Slack (after deploy)

Use this checklist after metadata is deployed to **`warrantyagentorg`** (or your target org). It assumes **Salesforce ↔ Slack** is already connected and the **Salesforce (legacy)** Slack app is installed.

---

## 1. One-time org configuration

### 1.1 Slack channel id (required for Flow)

1. In **Slack**, open your approvals channel (e.g. `#warranty-approvals`).  
2. Click the channel name → scroll to **About** → copy **Channel ID** (format like `C0123456789`).  
3. In **Salesforce** → **Setup** → **Custom Metadata Types** → **WC Slack Approval Config** → **Manage Records** → **Default**.  
4. Paste the value into **Slack Channel Id** (replace `REPLACE_WITH_YOUR_SLACK_CHANNEL_ID`). Save.

### 1.1b Incoming Webhook URL (optional — Block Kit without native Slack action)

Use this if you post rich messages via **`WC Post Slack Webhook Message`** instead of **Send a Slack Message**.

1. In **Slack** → your workspace → **Apps** → add **Incoming Webhooks** (or open the app that owns the webhook) → add a webhook to the target channel and copy the **Webhook URL** (`https://hooks.slack.com/services/...`).  
2. In Salesforce → **WC Slack Approval Config** → **Default** → paste into **Slack Incoming Webhook Url**, **or** pass the URL only in Flow (input **Webhook URL** on the action — metadata can stay empty).  
3. After deploy, confirm **Setup** → **Remote Site Settings** → **Slack Incoming Webhooks** is **Active** (deploys with metadata).

### 1.2 Permission sets (users that run Flow / integration)

Assign to the **integration user** (or Flow “default workflow user”) as needed:

- **WC Warranty Claim Integration** — full access to WC Apex and Claim fields.  
- **WC Warranty Claim Integration (Agent User)** — if the Einstein agent user runs invocables.

Also assign the **Sales Cloud for Slack** / **Slack** permission sets your org uses for **Send Slack Message** in Flow (names vary; search Setup for “Slack”).

### 1.3 Einstein prompts (approver summary)

1. **Setup** → **Einstein** → **Prompt Builder**.  
2. Open **WC Approver Slack Summary** and **Publish** (metadata may deploy as Draft).  
3. Do the same for **WC Suggest Part From Knowledge** if intake still uses it.

---

## 2. Notification Flow (path 6a — Block Kit + Incoming Webhook)

Metadata includes an **autolaunched** flow **`WC_Notify_Claim_Submitted_Slack_Webhook`** (Platform Event `WC_WarrantyClaimSubmitted__e` → Get Claim → Generate Approver Summary → Get Approver Context → Build Slack Approver Block Kit → Post Slack Webhook Message). After deploy, set **Slack Incoming Webhook Url** on **WC Slack Approval Config → Default** (do not commit secrets to git). If you prefer to build manually in Flow Builder, use the table below.

Create an **autolaunched** flow (name suggestion: `WC Notify Claim Submitted Slack`) if you are not using the deployed flow.

| Order | Element | Purpose |
|------|---------|--------|
| 1 | **Start** | Trigger: **Platform Event** `WC_WarrantyClaimSubmitted__e`. |
| 2 | **Get Records** | **Claim** where `Id` = `{!$Record.WC_Claim_Id__c}` (or the event field name shown in Flow). |
| 3 | **Action** | **WC Generate Approver Summary** — `claimId` = `{!Get_Claim.Id}`, `persistToClaim` = `true`. |
| 4 | **Action** | **WC Get Approver Context** — `claimId` = `{!Get_Claim.Id}`. |
| 5 | **Action** | **WC Build Slack Approver Block Kit** — map **Get Approver Context** + summary outputs into inputs; outputs **Blocks JSON Only** / **Slack Message JSON**. |
| 6a | **Action** (pick one path) | **WC Post Slack Webhook Message** — **Fallback Text** = short plain summary; **Blocks JSON Only** = output from step 5 (API name is usually `blocksArrayJson`); **Webhook URL** = blank if stored in **WC Slack Approval Config**, or paste URL. Skip **Send a Slack Message** if you use this. |
| 6b | **Action** (alternative) | **Send a Slack Message** (native Slack action) — plain text only if you only see **Enter Message to Send**; then skip step 5 Block Kit mapping and use a text template instead. |

**Send a Slack Message** (step 6b only):

- **Slack app / workspace**: choose the connected Salesforce Slack app.  
- **Channel / conversation**: pick the channel, **or** use merge field  
  `{!$CustomMetadata.WC_Slack_Approval_Config__mdt.Default.Slack_Channel_Id__c}`  
  (some flows want a **Conversation ID** resource — pick the pattern your action shows).  
- **Enter Message to Send** (or the single message field — common in legacy Slack for Flow):  
  - This field is **plain text only**. Do **not** paste `slackMessageJson` or `blocksArrayJson` here — you will get ugly literal JSON, not a rich layout.  
  - Build a **Text Template** (or type in the box) and merge fields from **WC Get Approver Context** and **WC Generate Approver Summary** (e.g. dealer, VIN, summary text, claim Id). Use `config/slack/wc_claim_slack_plain_text_message.txt` as a starting layout.  
- **If your org ever shows a separate field for Block Kit / blocks / JSON:** then add step 5 and map **`blocksArrayJson`** first, or **`slackMessageJson`** if the connector expects a full `{"blocks":[...]}` wrapper.

**Save** and **Activate** the flow.

---

## 3. Approve / reject from Slack (separate from the message body)

Interactive buttons in Slack **do not** automatically update Salesforce unless your Slack product maps them. Use **Slack Workflow Builder** → **Salesforce** → **Run a flow** → select **`WC_Update_Claim_From_Slack_Decision`** with inputs `inputClaimId` and `inputDecision` (`Approve` or `Reject`). See **`WC_SLACK_OPTION1_BUILD.md`** Part B.

---

## 4. Smoke test

1. Submit a claim through **Use Case 1** (or run sample data) so `WC_WarrantyClaimSubmitted__e` fires.  
2. Confirm a message appears in the Slack channel.  
3. If nothing posts: check **Setup** → **Paused and Failed Flow Interviews**, Flow debug logs, and that the **Slack connection** and **channel id** are correct.

---

## 5. Deploy command (for reference)

From the repo root:

```bash
sf project deploy start -o <YourOrgAlias> -x manifest/WC_package.xml --test-level RunSpecifiedTests --tests WC_BuildSlackApproverBlocksActionTest --tests WC_PostSlackWebhookMessageActionTest --tests WC_GetApproverContextActionTest --tests WC_GenerateApproverSummaryActionTest --tests WC_ApproverSummaryLlmParserTest --tests WC_CreateClaimIntakeActionTest --tests WC_SuggestPartLlmParserTest --tests WC_SuggestPartActionTest --tests WC_VehicleLookupActionTest --tests WC_DataCloudClaimHistorySampleDataTest --tests WC_UseCase1SampleDataTest
```

**Latest deploy:** `warrantyagentorg` — **Succeeded** (metadata + components in package).

---

## Related docs

- Deeper detail: [WC_SLACK_OPTION1_BUILD.md](./WC_SLACK_OPTION1_BUILD.md)  
- Approver agent context: [USE_CASE_2_SLACK_APPROVER.md](./USE_CASE_2_SLACK_APPROVER.md)
