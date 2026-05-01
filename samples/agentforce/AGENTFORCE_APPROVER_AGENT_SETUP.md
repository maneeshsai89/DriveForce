# Agentforce — WC Approver Policy Agent (manual setup in org)

Use this guide if you are configuring the **warranty approver assistant** in Salesforce yourself (UI + optional metadata). Slack requires an **Employee**-type Agentforce agent, not a customer-facing Service Agent.

---

## 1. Prerequisites

| Area | What to verify |
|------|----------------|
| **Licenses** | Einstein / Agentforce entitlements for your org; users who chat with the agent need appropriate licenses per your contract. |
| **Slack** | Salesforce Slack integration installed; workspace connected; you know which **channel** approvers use (same channel as `WC_BuildSlackApproverBlocksAction` notifications). |
| **This project** | Flex prompt **`WC_Approver_Policy_QA`** deployed (GenAiPromptTemplate). Invocable **`WC_GetApproverContextAction`** available for claim context. Optional: policy PDF for Data Library — print `samples/agentforce/Warranty_Insurance_Policy_Sample.html` (simple internal doc: dealer claim volume limits for 30/60/90 days and acceptable approval-rate band). Replace numbers and text with your legal-approved policy. |
| **Permissions** | Integration user / agent user has **WC Warranty Claim Integration** or **WC Warranty Claim Integration (Agent)** so Apex invocables can run. |

---

## 2. Create the agent (Employee)

1. Open **Agentforce** / **Einstein** (exact menu: *Agentforce Agents* or *Einstein Agents* — varies by release).
2. **New Agent** → choose a template that creates an **Employee** or **internal** agent (not “Service Agent” / customer-only if your org restricts Slack to employee agents).
3. Set **Name**: e.g. `WC Approver Policy Agent`  
   **Developer Name** (if shown): `WC_Approver_Policy_Agent` (matches repo naming if you deploy metadata later).
4. Save. Open the agent’s **Agent Builder** / configuration screen.

**Why Employee:** Customer Service agents are often constrained to Experience / messaging surfaces; **Employee** agents are the usual choice for **Slack** and internal tools. If your org only lists certain templates for Slack, pick the internal/employee option.

---

## 3. Conversation variables (map to your WC build)

Add **conversation variables** on the agent so prompts and topics can use thread + claim context (aligned with `WC_Approver_Policy_QA` inputs and Slack approval cards).

| Variable API name | Type | Purpose |
|-------------------|------|---------|
| **WC_User_Question** | Text | Latest user question → maps to prompt **Input:User_Question**. |
| **WC_Claim_Id** | Text | Optional Salesforce Claim Id (18 chars) → **Input:Claim_Id**. |
| **WC_Thread_Parent_Text** | Text | Text of the **root** Slack message (approval card). Your `WC_BuildSlackApproverBlocksAction` includes a **Claim Id** line; the model can parse Id from here. |
| **WC_Claim_Context_Text** | Text | Structured claim + dealer narrative → **Input:Claim_Context_Text** (usually from **`WC_GetApproverContextAction`** output `Claim_Context_Block`). |

**Populate in practice**

- **WC_User_Question:** from the user’s message (standard agent behavior or topic mapping).
- **WC_Claim_Id / WC_Thread_Parent_Text:** map from Slack if your Slack connector exposes thread parent text; otherwise instruct users to paste Claim Id or rely on instructions to read parent message when included in context.
- **WC_Claim_Context_Text:** set by a **Flow or action** you attach: input `WC_Claim_Id` → invocable **WC Get Approver Notification Context** → pass **`Claim_Context_Block`** into this variable.

Mark variables **include in prompt** / **available to reasoning** per your UI (so the planner and Flex prompt can see them).

---

## 4. Flex prompt template `WC_Approver_Policy_QA`

1. Go to **Prompt Builder** (or **Einstein Prompt Templates**).
2. Open **`WC Approver Policy Q&A`** (`WC_Approver_Policy_QA`).
3. **Activate** a version if it is still Draft.
4. In **Agent Builder**, attach this template to the agent or topic so inputs bind:
   - **User_Question** ← `WC_User_Question`
   - **Claim_Id** ← `WC_Claim_Id`
   - **Claim_Context_Text** ← `WC_Claim_Context_Text`

(Exact “bind” UI may be *Prompt Template* selection on a topic plus input mapping.)

---

## 5. Data Library (policy PDF)

1. **Einstein** → **Data Library** (or **Agentforce Data Library**).
2. **New** → upload your **policy PDF** (e.g. exported from `Warranty_Insurance_Policy_Sample.html`).
3. **Attach** this library to the agent or to the topic that handles policy Q&A so **Answer Questions with Knowledge** / retrieval can ground answers.

---

## 6. Data Cloud retrievers (optional)

If you use **Data Cloud** for claim frequency / cohort metrics:

1. Create or reuse **retrievers** (search indexes / calculated insights) per your Data Cloud setup (`data-cloud/` docs in this repo).
2. In **Agent Builder**, add **retrievers** to the same agent or topic so hybrid questions (“is this part’s frequency unusual?”) combine PDF policy + metrics.

---

## 7. Topic: instructions (Claim Id from thread)

Create **one primary topic** (e.g. *Warranty approver policy Q&A*).

**Scope / role (example):**

- Help internal approvers with **warranty policy**, **documentation rules**, and **claim-specific** questions when a Claim Id or claim context is available.
- Use **Data Library** and **retrievers** for grounding; do not invent claim field values.

**Instructions (example — adjust to your tone):**

1. When **WC_Claim_Id** is populated, treat questions as about that claim; use **WC_Claim_Context_Text** when present (from `WC_GetApproverContextAction`).
2. When **WC_Claim_Id** is empty but **WC_Thread_Parent_Text** contains a line like `Claim Id` with a Salesforce Id in backticks (as in the WC Slack approval card), **extract the 18-character Id**, set it as the effective Claim Id for reasoning, and prefer running claim-context actions your admin configured.
3. When neither Id nor context is available, answer **only** from policy documents and retrievers; say clearly if something is not in the sources.
4. Map **WC_User_Question** to the Flex prompt **`WC_Approver_Policy_QA`** inputs as configured.

You will **add actions manually** (next section); reference them in instructions once wired (e.g. “After resolving Claim Id, call Get Approver Context to fill WC_Claim_Context_Text”).

---

## 8. Actions you add manually (recommended)

| Action | Type | Purpose |
|--------|------|--------|
| **WC Get Approver Notification Context** | Invocable (`WC_GetApproverContextAction`) | Input: Claim Id → Output: **`Claim_Context_Block`** → map to **WC_Claim_Context_Text**. |
| *(Optional)* **WC Generate Approver Summary** | Invocable (`WC_GenerateApproverSummaryAction`) | If you want the same AI summary as Slack on the Claim before Q&A. |

**Typical pattern:** Autolaunched Flow triggered by agent action: **Claim Id** in → **Get Approver Context** → set conversation variable **WC_Claim_Context_Text**.

Ensure the **running user** (or integration user) has the permission set that grants these Apex classes.

---

## 9. Global planner actions

Enable **Answer Questions with Knowledge** (or equivalent) so the agent can use **Data Library** / Knowledge grounding. This matches the standard Employee Copilot action often named *Answer Questions with Knowledge*.

---

## 10. Connect Slack

1. In **Slack app configuration** (Salesforce + Slack setup), connect the **Employee** agent to the **target workspace** and **channel** (approver channel).
2. Decide how users invoke the agent: **@mention**, **shortcut**, or **app home** — per your Slack app settings.
3. Confirm **thread context**: if the platform can pass **parent message text** into **WC_Thread_Parent_Text**, Claim Id extraction works better; if not, rely on pasted Id or future automation.

---

## 11. Testing checklist

- [ ] Ask a **generic** policy question (no Claim Id) → answer from PDF/Data Library only.
- [ ] Paste a **valid Claim Id** → context action fills **WC_Claim_Context_Text** → claim-specific answers.
- [ ] Reply in thread under an approval card (if thread parent is passed) → agent uses **Claim Id** line from card when instructions are followed.
- [ ] User without Claim access: verify integration user can still run invocables with **SYSTEM_MODE** patterns used in `WC_ApproverContextService`.

---

## 12. Related repo artifacts

| Artifact | Location |
|----------|----------|
| Flex prompt | `force-app/main/default/genAiPromptTemplates/WC_Approver_Policy_QA.genAiPromptTemplate-meta.xml` |
| Policy PDF (print to PDF) | `samples/agentforce/Warranty_Insurance_Policy_Sample.html` — dealer volume (30/60/90) + approval-rate band |
| Slack approval card (Claim Id on card) | `WC_BuildSlackApproverBlocksAction` |
| Claim context builder | `WC_ApproverContextService`, `WC_GetApproverContextAction` |

---

## 13. Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Agent not in Slack | Employee agent + Slack connection + channel allowlist. |
| No PDF grounding | Data Library attached; topic/agent uses knowledge action. |
| Claim Id never found | Thread parent not passed → map variable or paste Id; optional custom mapping `channel + thread_ts` → Claim Id. |
| Invocable fails | Permission set on running user; Claim exists. |

---

*Internal WC reference — align menu names with your org’s Salesforce release.*
