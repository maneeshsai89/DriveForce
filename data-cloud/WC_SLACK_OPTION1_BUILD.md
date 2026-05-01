# Option 1 — Slack notification + Approve / Reject (no Apex callouts)

This guide uses **Salesforce Flow** actions for **Send Slack Message** and **Slack Workflow Builder** (with the **Salesforce connector**) to run an autolaunched Flow that updates the **Claim**. It matches Salesforce’s documented pattern (see *Build No-Code Slack and Salesforce Automations With Flow*, Nov 2025).

**Prerequisites**

- Slack workspace connected to Salesforce (**Sales Cloud for Slack** / **Service Cloud for Slack** recommended; legacy Slack app may have fewer Flow actions—use what your org exposes).
- **Send a Slack Message** action available in Flow Builder.
- **Slack Workflow Builder** can add the **Salesforce** connector step **Run a flow** (org-dependent).

**Repo assets**

| Asset | Purpose |
|-------|---------|
| `flows/WC_Update_Claim_From_Slack_Decision.flow-meta.xml` | Autolaunched Flow: inputs `inputClaimId`, `inputDecision` (`Approve` or `Reject`), sets `WC_Approval_Result__c` and `WC_Approval_Channel__c` = Slack. |
| `WC_Slack_Approval_Config__mdt` + `Default` record | Store **Slack Channel Id** (and optional workspace id) for Flow merge fields. Replace `REPLACE_WITH_YOUR_SLACK_CHANNEL_ID` after deploy. |
| `config/slack/wc_claim_slack_plain_text_message.txt` | **Use this** when Flow has **no Block Kit** field — build the body in a **Text Template** or long **Formula** in Flow (see below). |
| `WC_BuildSlackApproverBlocksAction` | **Invocable** — outputs `slackMessageJson` / `blocksArrayJson` for Block Kit (no callout). Map fields from Get Context + Generate Summary. |
| `config/slack/wc_claim_approver_block_kit_template.json` | Static reference; **Apex builder** is preferred for escaping and limits. |

### Same look as `slack_approver_warranty_workflow.html` (HTML mock)

Slack **does not render HTML**. The demo page is a **visual mock** of what Slack shows when you send **Block Kit** (`blocks` JSON): header, field grid, AI section, action buttons.

| Approach | Delivers rich layout? | Notes |
|----------|----------------------|--------|
| **Plain text** in Flow | No — single monospace-style message | Fine for data; not the card UI. |
| **Block Kit JSON** | Yes — closest to the HTML mock | Must be passed to Slack as **`blocks`** (not the `text` field only). |
| **`WC_BuildSlackApproverBlocksAction` (Apex)** | Builds Block Kit **JSON only** — **no HTTP callout** | Flow wires outputs from `WC_GetApproverContextAction` + `WC_GenerateApproverSummaryAction` into this action; use `slackMessageJson` or `blocksArrayJson` **if** your Send action accepts it. |
| **Flow only** | Possible but painful | Huge formulas concatenating JSON — no Apex, unmaintainable. |
| **Slack `chat.postMessage` API** | Yes | Requires **Named Credential** + callout (Apex or External Service) — only if the Flow action cannot send `blocks`. |

**Bottom line:** Apex is **not** the only way to *author* Block Kit (you could build JSON in Flow), but something must **produce** Block Kit and your **integration must send it**. If the Salesforce **Send Slack Message** action has **no field for blocks/JSON**, the only way to get the exact rich format is a path that posts **`blocks`** (often the **Slack Web API** — see Salesforce Help for your Slack app edition).

---

### Block Kit is often not available in Flow (expected)

In many orgs (including with the **legacy Slack app**), **Send Slack Message** only offers a **single message / text** field — there is **no** Block Kit or “advanced JSON” toggle in Setup or Flow Builder. That is normal.

**What to do:** Do **not** rely on Block Kit from Flow. Send a **multi-line plain text** (or “mrkdwn” if your action has a **Message format** = *Mrkdwn* dropdown — if not, plain text only). Use `config/slack/wc_claim_slack_plain_text_message.txt` as a guide: in Flow, use a **Text Template** resource or one **Formula (Text)** that concatenates:

- Outputs from **Get Approver Context** (`dealerName`, `vin`, `partCode`, `riskLabel`, `riskScore`, …)  
- Output from **Generate Approver Summary** (`aiSummary`)  
- **`{!Get_Claim.Id}`** and **`{!Get_Claim.Name}`** so approvers and Slack workflows always see the **Claim Id**.

**Buttons:** You still won’t get interactive Block Kit buttons from this message unless the product adds that field. Use **Part B** (Slack Workflow Builder → **Run Salesforce flow**) for approve/reject.

---

## Part A — Notify channel when `WC_WarrantyClaimSubmitted__e` fires

1. In **Flow Builder**, create an **autolaunched** flow.  
2. **Start** → **Platform Event** → `WC_WarrantyClaimSubmitted__e`.  
3. **Get Records**: Claim where `Id = {!$Record.WC_Claim_Id__c}` (adjust if your event variable name differs).  
4. Call **Action** → `WC_GenerateApproverSummaryAction`  
   - `claimId` = `{!Get_Claim.Id}`  
   - `persistToClaim` = `true`  
5. Call **Action** → `WC_GetApproverContextAction`  
   - `claimId` = `{!Get_Claim.Id}`  
6. **(Optional — rich card like the HTML mock)** Call **Action** → `WC_BuildSlackApproverBlocksAction` and map every input from the **Get Context** and **Generate Summary** outputs (same `claimId`, `aiSummary`, dealer, VIN, risk, etc.). Use outputs **`slackMessageJson`** or **`blocksArrayJson`** only if your **Send Slack Message** step exposes a field for **Block Kit JSON** / **blocks** / **advanced payload**.  
7. **Send Slack Message** (native Slack action):  
   - **Slack app / workspace**: your connected app.  
   - **Conversation / Channel**: use `{!$CustomMetadata.WC_Slack_Approval_Config__mdt.Default.Slack_Channel_Id__c}` after you set the **Default** custom metadata record, **or** paste your Channel Id.  
   - **If you have a Block Kit / JSON / “blocks” field:** paste **`{!Build_Blocks.slackMessageJson}`** (or the `blocks` portion only — **`{!Build_Blocks.blocksArrayJson}`** — if the action expects an array) from step 6. That is how you match the **HTML mock** in Slack.  
   - **If you only have a single Message text field (typical):** use **one** long plain text — see `config/slack/wc_claim_slack_plain_text_message.txt` — with `{!Get_Claim.Name}`, `{!Get_Context.dealerName}`, `{!Get_Context.vin}`, `{!Generate_Summary.aiSummary}`, etc. (use your **exact** Action output API names).  
   - If **Message format** = *Mrkdwn*, you may use `*bold*`; otherwise plain text and line breaks only.

8. **Save** and **Activate**.

**Important:** Interactive **Block Kit buttons** in a message sent *from* Salesforce do **not** automatically update Salesforce unless your Slack–Salesforce integration routes `block_actions` to a Flow (product/version dependent). The **supported no-code** pattern for “button → Salesforce” is **Part B** (Slack Workflow calling this org’s Flow).

---

## Part B — Approve / Reject without Apex (Slack Workflow → Salesforce Flow)

Use **Slack Workflow Builder** so clicks stay in Slack and call Salesforce through the **Salesforce connector**.

### Design (recommended)

1. **Create Slack Workflow** (in Slack):  
   - **Trigger**: choose one that fits your UX:  
     - **Shortcut** (e.g. “Approve warranty claim”) opening a **form** with fields **Claim Id** (text) and **Decision** (Approve / Reject), **or**  
     - **Emoji reaction** on the notification message (e.g. ✅ / ❌) and pass **message text** into a follow-up step that **parses** Claim Id (18 characters), **or**  
     - **Buttons** inside **Slack Workflow** steps (not Block Kit from Salesforce) → **Run a flow** — Slack’s docs show interactive buttons continuing a **workflow** (see Salesforce Admin blog, Nov 2025).

2. Add step **Salesforce** → **Run a flow** (wording may be “Run autolaunched flow”):  
   - Select **`WC_Update_Claim_From_Slack_Decision`**.  
   - Map **input variables**:  
     - `inputClaimId` ← Claim Id from the form / parsed text / button payload.  
     - `inputDecision` ← exactly `Approve` or `Reject` (must match the Flow decision).

3. **Publish** the Slack workflow.  
4. Teach approvers: use the **shortcut** or **reaction** path you configured (or open the workflow from a **link** you post in the channel).

This path uses **no Apex HTTP callouts**; Salesforce’s connector invokes the Flow in your org.

---

## Part C — Optional: Block Kit buttons only (if your org routes interactions)

If your **Sales Cloud for Slack** edition routes Block Kit `action_id` clicks to Salesforce (check Help for your release):

1. Send the message from Part A with buttons (`action_id` `wc_approve_claim` / `wc_reject_claim`, `value` = Claim Id).  
2. Configure the **in-product** mapping so each action invokes **`WC_Update_Claim_From_Slack_Decision`** with `inputClaimId` = button value and `inputDecision` = Approve or Reject.

If that UI is **not** available, use **Part B** only.

---

## Part D — Guide: actually **using** the Approve / Reject **buttons** on the message

The Block Kit card from **`WC_BuildSlackApproverBlocksAction`** includes three **interactive** buttons:

| Button        | `action_id`        | `value` sent to Slack (max 2000 chars) |
|---------------|--------------------|------------------------------------------|
| Approve       | `wc_approve_claim` | `{ClaimId}\|Approve`                     |
| Reject        | `wc_reject_claim`  | `{ClaimId}\|Reject`                     |
| Ask a question| `wc_ask_agent`     | `{ClaimId}`                             |

### What happens in Slack when someone clicks

1. Slack sends an HTTP **`block_actions`** payload to the **Interactivity Request URL** of the **Slack app** that owns the message (not to Incoming Webhooks, and not to Workflow Builder’s “Events” list).
2. Something on that URL must **acknowledge** the click (HTTP 200 within 3 seconds) and **update Salesforce** (or queue work) if you want the Claim updated.

So **Slack Workflow Builder → “From a link in Slack”** (or webhook, schedule, etc.) does **not** wire up these message buttons by itself. Those entries are **workflow start triggers**, not listeners for Block Kit clicks on an arbitrary posted message.

### Practical ways to “use the buttons”

**Option 1 — Salesforce for Slack (best if your org has it)**  

1. Install/connect **Sales Cloud for Slack** or **Service Cloud for Slack** and complete **Salesforce ↔ Slack** linking.  
2. In **Salesforce Setup**, search **Slack** and open the documentation for your release for **actions**, **shortcuts**, or routing **Slack interactions** to **Flow**.  
3. If your org exposes a UI to map **Slack `action_id` / interaction** → **Run autolaunched Flow**, point **Approve** / **Reject** at a flow that updates the Claim.  
4. **Payload shape:** Your deployed flow `WC_Update_Claim_From_Slack_Decision` expects **`inputClaimId`** and **`inputDecision`** separately, but the button **`value`** is a **single string** `ClaimId|Approve` or `ClaimId|Reject`. You may need a **small wrapper Flow** that accepts one text input, **splits** on `|`, then passes `inputClaimId` and `inputDecision` into **`WC_Update_Claim_From_Slack_Decision`** (or adjust the decision flow to accept the combined `value` — product-dependent).

**Option 2 — Custom Slack app + HTTPS endpoint (build)**  

1. Create a **Slack app** with **Interactivity** ON and a public **Request URL** (e.g. middleware or **Apex REST** behind a Site).  
2. Parse Slack’s JSON (`actions[0].action_id`, `actions[0].value`), then call Salesforce (**Named Credential**, **Flow invocable REST**, etc.).  
3. This is **not** no-code; it replaces what Option 1 does in-product.

**Option 3 — Don’t rely on Block Kit buttons for the Salesforce update**  

Use **Part B** (workflow link / shortcut / form) for approve/reject, and treat the Block Kit buttons as **UX only** or remove them if confusing — **Incoming Webhook** messages cannot receive button callbacks.

### Quick test in Slack (no Salesforce yet)

In **Slack API** → your app → **Interactivity** must be enabled and **Request URL** must respond `200` for clicks to stop showing “interactivity failed” in Slack. If the URL is missing or wrong, **buttons will not work** even if the message renders.

---

## Part E — **Custom Slack app**: sending messages + making buttons work

Use this when you **own the Slack app** (not only the Salesforce-managed connector). You need **two** halves: **(1) post the message** with Block Kit, **(2) receive `block_actions`** when someone clicks.

**Posting via Incoming Webhook (this repo’s send path):** Salesforce only needs the **`https://hooks.slack.com/services/...`** URL (Flow input and/or **`WC_Slack_Approval_Config__mdt`**) — **no** bot token for posting. **`WC_PostSlackWebhookMessageAction`** sends `{ "text", "blocks" }` as Slack expects. For **Approve / Reject**, you still configure **Interactivity** on the **same** Slack app that owns that webhook; the webhook URL does **not** receive button clicks.

### 1. Slack app configuration (api.slack.com → Your Apps → your app)

| Area | What to set |
|------|-------------|
| **OAuth & Permissions — Scopes (Bot Token)** | At minimum: **`chat:write`** (to post with the Web API). If you use **Incoming Webhooks** instead, add **`incoming-webhook`** and **create a webhook** for the target channel after install. Optional: **`channels:join`** / **`groups:write`** if the bot must join private channels. |
| **Install App** | Install the app to the workspace. Copy the **Bot User OAuth Token** (`xoxb-...`) only if you call **`chat.postMessage`**. |
| **Incoming Webhooks** (optional) | If you keep using **`WC_PostSlackWebhookMessageAction`**, enable Incoming Webhooks, add a webhook, copy **`https://hooks.slack.com/services/...`** into Flow or **`WC_Slack_Approval_Config__mdt`**. This matches the Apex payload shape: top-level **`text`** + **`blocks`**. |
| **Interactivity & Shortcuts** | Turn **Interactivity** **ON**. Set **Request URL** to an HTTPS endpoint you control (see §3). Without this, **Approve / Reject / Ask** clicks will fail or show Slack errors. |

**Same app:** The app that **posts** the message (webhook or bot) should be the same app whose **Interactivity** URL receives clicks. Webhook URLs are tied to that app; Block Kit buttons on those messages resolve `block_actions` to that app’s Interactivity URL.

### 2. How you **send** the message (pick one)

**A — Incoming Webhook (matches this repo’s Apex)**  

- No `xoxb-` token in Salesforce for the send path (only the webhook URL).  
- Flow: build blocks with **`WC_BuildSlackApproverBlocksAction`** → **`WC_PostSlackWebhookMessageAction`** with **`fallbackText`**, **`blocksArrayJson`** (or **`slackMessageJson`**), and **`webhookUrl`** or metadata URL.  
- Payload Slack receives is JSON: `{ "text": "...", "blocks": [ ... ] }` — same as Slack’s webhook docs.

**B — Slack Web API `chat.postMessage` (custom app bot)**  

- **POST** `https://slack.com/api/chat.postMessage`  
- Header: **`Authorization: Bearer xoxb-...`**  
- Body includes **`channel`** (e.g. `C0123...`), **`text`** (fallback), **`blocks`** (array from **`blocksArrayJson`**).  
- Store the bot token in a **Named Credential** (recommended) or another **secured** store; this repo’s invocable does **not** implement `chat.postMessage` — you would add Apex or use **External Service** / middleware if you choose this path.

### 3. **Interactivity** — what must answer when a button is clicked

Slack POSTs **`application/x-www-form-urlencoded`** with a **`payload`** field containing JSON. Important fields:

- **`type`**: often `block_actions`  
- **`actions[0].action_id`**: `wc_approve_claim`, `wc_reject_claim`, or `wc_ask_agent`  
- **`actions[0].value`**: e.g. `001XXXXXXXXXXXXXXX|Approve` or `...|Reject`, or Claim Id only for Ask  

Your endpoint must:

1. **Verify** the request is from Slack (**signing secret**, `X-Slack-Signature` + `X-Slack-Request-Timestamp`) — do not skip this on a public URL.  
2. Respond **HTTP 200** within **3 seconds** (can return empty body or a minimal JSON acknowledgment).  
3. **Update Salesforce** asynchronously if needed: parse `value`, map to **`WC_Update_Claim_From_Slack_Decision`** (`inputClaimId` + `inputDecision`), e.g. split `ClaimId|Approve` on `|`, or call a **wrapper Flow** that does the split.

Options for the endpoint: **Heroku / AWS Lambda / Azure Function**, or **Salesforce Site + Apex REST** with a public HTTPS URL.

### 4. Quick checklist

- [ ] App installed; channel allows the app (or webhook is added to channel).  
- [ ] Message sends and shows Block Kit (webhook or `chat.postMessage`).  
- [ ] **Interactivity** ON + Request URL returns **200** for Slack’s **URL verification** challenge when you first save.  
- [ ] Click **Approve** → your service logs the payload and updates the Claim (or queues a job).  

---

## Part F — Apex REST interactivity (in-repo): `WC_SlackInteractivityRest`

This class exposes **`POST /services/apexrest/wc/slack/interactivity`**. It:

- Handles Slack **URL verification** (`url_verification` + `challenge`) for JSON or `payload=` form bodies.  
- Verifies **`X-Slack-Signature`** using **`Slack_Signing_Secret__c`** on **`WC_Slack_Approval_Config__mdt`** (`Default`).  
- On **`block_actions`** for **`wc_approve_claim`** / **`wc_reject_claim`**, calls **`WC_SlackClaimApprovalService`** (Site Guests cannot be granted **Run Flows**).  
- Ignores **`wc_ask_agent`** with HTTP 200 (no automation today).

### Public URL for Slack

Slack must reach **HTTPS** without a Salesforce session cookie. Follow **Part G** to create the site, assign the guest permission set, and paste the full REST URL into Slack. Summary:

1. Create a **Salesforce Site** or **Experience Cloud** site (published).  
2. Assign permission set **`WC Slack Interactivity Guest`** to that site’s **Guest User** (**Apex classes only** — no Claim CRUD). **Site Guest licenses** often disallow **Run Flows** and **Read/Edit Claims**; claim updates use **`Database.update(..., System.AccessLevel.SYSTEM_MODE)`** in **`WC_SlackClaimApprovalService`** so Guest does not need object/field permissions.  
3. **Request URL** in Slack → **Interactivity** = your site base URL + **`/services/apexrest/wc/slack/interactivity`** (see Part G for exact patterns).  
4. In **Custom Metadata** → **WC Slack Approval Config** → **Default**, set **Slack Signing Secret** from Slack app **Basic Information → Signing Secret**.

**Security:** Trust **Slack signing secret** + button **`value`**. **`WC_Update_Claim_From_Slack_Decision`** remains available for **Slack Workflow → Run flow** and other non-Guest callers; button clicks from the Site use the same field outcomes via Apex.

**Tests:** `WC_SlackInteractivityRestTest` (signature checks are skipped in `@isTest`; production always verifies when the secret is set).

---

## Part G — Build the Site (step-by-step)

Do this once per org. UI labels vary slightly; use Quick Find if needed.

### G.1 — Domain (if you do not have a public site URL yet)

1. **Setup** → Quick Find **Digital Experiences** → open **Settings** / **All Sites** (or **Sites** on older orgs).  
2. If prompted, **register** an Experience Cloud domain (e.g. `yourcompany.my.site.com`).  
3. Wait until the domain is **active** before publishing a site.

### G.2 — Create and publish a site

**Option A — Experience Cloud (common in current orgs)**  

1. **Setup** → **Digital Experiences** → **All Sites** → **New**.  
2. Choose a minimal template (e.g. **Build Your Own (LWR)** or **Customer Service**) — the UI matters less than having a **published** site.  
3. Name it (e.g. `WC Slack Interactivity`), complete the wizard, then **Publish** / **Activate** the site.

**Option B — Legacy Salesforce Sites**  

1. **Setup** → Quick Find **Sites** → **New**.  
2. Create the site, assign a **Site Label**, enable **Active**, and save.  
3. Add your **Site Domain** / **Custom URL** per the wizard.

You only need a site so Salesforce exposes a **public HTTPS** hostname for **Guest** access to Apex REST.

### G.3 — Guest User → permission set

1. Open your site → **Workspaces** (or **Builder**) → **Administration** (or **Site Details**).  
2. Open **Guest User** / **Public Access Settings** (wording varies).  
3. On the **Guest User** record, go to **Permission Set Assignments** → **Edit Assignments**.  
4. Assign **`WC Slack Interactivity Guest`** and save.

This permission set grants only **`WC_SlackInteractivityRest`** and **`WC_SlackClaimApprovalService`**. Claim updates do not use Guest **Claim** object permissions; they run in **system mode** DML after Slack signature verification (trust boundary: signing secret + button payload).

### G.4 — Build the Slack Interactivity URL

Append this path to your site’s **public base URL**:

```text
/services/apexrest/wc/slack/interactivity
```

**Examples (your hostname will differ):**

- Some sites: `https://wc-slack-interactivity.{your-domain}.force.com/services/apexrest/wc/slack/interactivity`  
- Experience Cloud custom domain: `https://{your-domain}.my.site.com/{optional-site-path}/s/services/apexrest/wc/slack/interactivity`  
- **Legacy Salesforce Sites** (`*.my.salesforce-sites.com`): `https://{sites-host}/{site-path}/services/apexrest/wc/slack/interactivity`  
  (e.g. `https://orgfarm-xxxx.my.salesforce-sites.com/electrawarrantyslack/services/apexrest/wc/slack/interactivity` — use your **Site path** from Setup.)

Use **Site Details** / **URL** in Setup as the source of truth; if one pattern 404s, try the variant with **`/s/`** before **`services`**.

**Debug:** Filter logs by prefix **`WC_SLACK_INTERACT`** (REST) and **`WC_SLACK_APPROVAL`** (Claim DML). Look for **`bodySource=`**: `requestBody` is normal; **`rebuilt_from_params`** means the platform stripped the raw POST body (common on **Legacy Sites**). Signing tries several reconstructed bodies (Slack often uses **`+`** for spaces in form data; Apex **`urlEncode`** uses **`%20`**). **`signature_ok candidateIndex=`** shows which variant matched. If all fail, confirm the **Signing Secret** matches the Slack app that owns the buttons.

Paste the **full HTTPS URL** into **Slack app → Interactivity & Shortcuts → Request URL** and save. Slack will POST a **URL verification** challenge; **`WC_SlackInteractivityRest`** responds with the **`challenge`** JSON when signing verification passes.

### G.5 — Smoke test (optional)

From a machine with **curl** (replace URL):

```bash
curl -X POST "https://YOUR_SITE_BASE/services/apexrest/wc/slack/interactivity" ^
  -H "Content-Type: application/json" ^
  -d "{\"type\":\"url_verification\",\"challenge\":\"test123\"}"
```

In **production**, requests without a valid **`X-Slack-Signature`** are rejected unless you temporarily omit the signing secret (not recommended). After **Slack Signing Secret** is set in metadata, test from **Slack** by saving the Interactivity URL (Slack sends the real signature).

### G.6 — Checklist

- [ ] Site published and HTTPS works in a browser (home page may be empty — that is fine).  
- [ ] Guest User has **`WC Slack Interactivity Guest`**.  
- [ ] **Default** custom metadata has **Slack Signing Secret** (from Slack app).  
- [ ] Slack **Interactivity** URL saved without error; button click updates **Claim** approval fields.

### Calling a Flow “directly” from Slack — options

| Approach | Slack → Salesforce | Notes |
|----------|--------------------|--------|
| **This Apex REST** | POST from Slack to your org’s public REST URL | No OAuth on the Slack side; **Signing Secret** proves Slack. |
| **Salesforce REST Flow Actions API** | `POST /services/data/vXX.0/actions/custom/flow/{flowApiName}` with **OAuth 2 Bearer** | Slack cannot send a Bearer token by itself; needs **middleware** (Lambda, MuleSoft) or stored Connected App + client credentials — usually heavier than Apex REST for button clicks. |
| **Slack Workflow → Salesforce connector → Run flow** | Salesforce product connector | No custom REST; not triggered by raw `block_actions` on webhook messages (see Part B). |
| **Middleware → Platform Event** | Lambda parses payload → publishes `WC_...__e` → Flow subscriber | Extra moving parts; same security considerations. |

For **webhook-posted Block Kit buttons**, **Apex REST** (or external HTTPS) is the usual way to turn a click into a Flow run without OAuth from Slack.

---

## Custom metadata

After deploy, edit **Setup → Custom Metadata Types → WC Slack Approval Config → Default**:

- **Slack Channel Id**: from Slack (channel details → copy **Channel ID**, usually starts with `C`).  
- **Slack Signing Secret**: from Slack app **Basic Information → Signing Secret** (required for **`WC_SlackInteractivityRest`** in production).

---

## Variable names for Slack connector

The deployed Flow expects:

| Input variable API name | Type | Allowed values for decision |
|-------------------------|------|------------------------------|
| `inputClaimId` | Text | 18-character Claim Id |
| `inputDecision` | Text | `Approve` or `Reject` (case-sensitive) |

Rename in Flow Builder only if you also change the Slack **Run a flow** mapping.

---

## Testing

1. Create a test Claim via intake.  
2. Run **WC_Update_Claim_From_Slack_Decision** manually in Flow **Debug** with `inputClaimId` and `inputDecision` = `Approve`.  
3. Confirm `WC_Approval_Result__c` and `WC_Approval_Channel__c` on Claim.  
4. Then test end-to-end from Slack Workflow.
