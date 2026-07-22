# CLAUDE.md — material-shortage-agent

## Project context
CAP (SAP Cloud Application Programming Model) service that checks material availability
for production orders and escalates shortages beyond an auto-order limit for human approval.
Portfolio project for SAP AI-Native Application Architect interview prep. Fictional customer
context: MachBau GmbH (machine manufacturer, NRW).

Real S/4 integration via SAP API Business Hub Sandbox, entity `A_MatlStkInAcctMod`
(API_MATERIAL_STOCK_SRV) — imported via `cds import` from real OData metadata, not hand-modeled.

## Stack
- CAP with `@sap/cds-dk` latest, TypeScript only (no JavaScript, no Python)
- SQLite locally, remote OData-v2 service for S/4 sandbox stock data
- LangChain v1.x (`langchain` package) + Zod for structured LLM output
- Fiori Elements (List Report + Object Page) for the approval UI — no custom SAPUI5 unless
  Fiori Elements genuinely can't do it
- Native CAP `@mcp` protocol annotation for exposing actions as MCP tools later (this is NOT
  the same as `@cap-js/mcp-server`, which is a dev-tool MCP server for coding assistants —
  do not confuse the two)

## Architecture decisions (do not relitigate without flagging back to chat)
- **No StateGraph / interrupt() for human approval.** Approval is a disconnected, later-in-time
  action from a UI, not a paused live agent run. HITL here = two plain decoupled CAP actions
  connected by a database row and a status field, not LangGraph checkpointer/interrupt machinery.
- **Deterministic vs. generative split is non-negotiable:**
  - Stock math, auto-order-limit comparison, and the decision to auto-order vs. escalate →
    plain code. Never let the LLM decide whether it's allowed to act.
  - Drafting the escalation briefing (risk level, reasoning, recommended actions) → LLM,
    via `.withStructuredOutput()` with a Zod schema.
- Auto-order limit is value/cost-based, not quantity-based (mirrors real procurement:
  500 units of a €0.01 screw is nothing, 5 units of a €10,000 motor is a big deal).
- **Side-by-side extensibility, strictly:** `Materials` (local entity) and the remote S/4
  stock entity are NEVER fused into one CDS entity via projection — a projection can't invent
  new persisted columns (category, unitCost) on top of a remote service. They are separate
  entities, joined only at the handler/query level via the shared key (`materialNumber` /
  S/4's `Material` field). This app never writes directly into S/4 data; any real purchase
  order creation would call S/4's own API, not a local table pretending to be S/4.

## Confirmed S/4 sandbox findings (do not re-derive, already verified)
- Correct entity for stock-on-hand: `A_MatlStkInAcctMod` (NOT `A_MaterialSerialNumber`,
  which is per-serial-unit tracking — too granular; NOT the bare `A_MaterialStock` header
  without the nav property).
- Key fields confirmed from real sandbox response:
  - `Material` — join key to local `Materials.materialNumber`
  - `Plant` — part of the composite key, keep even for single-plant demo
  - `MatlWrhsStkQtyInMatlBaseUnit` — the actual on-hand quantity field
  - `MaterialBaseUnit` — unit of measure, confirm it matches seeded Materials before trusting
    the math
  - `InventorySpecialStockType` — filter to blank/'' for ordinary available inventory
  - `InventoryStockType` — only count unrestricted stock as "available" (ignore blocked/QI)
- Fields present but intentionally ignored for v0: `StorageLocation`, `Batch`, `Supplier`,
  `Customer`, `WBSElementInternalID`, `SDDocument(Item)` — these exist because S/4 segments
  stock finely (batch, project stock, consignment); not needed for this demo's granularity.
- Still to confirm: a real non-blank `Material` value's ID format/pattern (sample calls so far
  returned either serial-number-level rows or a blank-Material aggregate row) — pull
  `A_MatlStkInAcctMod?$filter=Plant eq '1010'&$top=10` next to confirm before finalizing
  `Materials.materialNumber` type/pattern.

## Local schema (db/schema.cds) — current shape
Entities: `Materials` (cuid; materialNumber, description, category, unitCost, leadTimeDays,
substitutes self-association by category), `ProductionOrders` (cuid+managed; orderNumber,
product, quantity, requiredByDate, status, composition of components),
`ProductionOrderComponents` (cuid; order, material, quantityRequired), `AutoOrderPolicy`
(cuid; category, autoOrderLimitValue), `Escalations` (cuid+managed; productionOrder, component,
shortfallQty, shortfallValue, riskLevel, recommendedActions as LargeString/JSON,
reasoning, status, rejectionReason), `PurchaseOrders` (cuid+managed; material, quantity,
escalation, status, source: 'agent-auto' | 'human-approved').

Known simplifications, flagged not forgotten: `substitutes` via same-category association is
a weak proxy (not true substitute relationships); `AutoOrderPolicy` is per-category not
per-material; `recommendedActions` is JSON-stringified, not a queryable child entity;
`rejectionReason` is free text, not an enum.

## Core flow
```
checkAvailability(orderId)        → deterministic, no LLM
  sufficient → auto-approve, done
  shortfall  → initiateReplenishment(orderId, component)
                 within auto-order limit → create PurchaseOrder (source: agent-auto), no LLM
                 exceeds limit           → LLM drafts briefing → Escalation row (pending-approval)

approveEscalation(escalationId)   → separate action, called anytime from Fiori UI
  → deterministic: create PurchaseOrder (source: human-approved)

rejectEscalation(escalationId, reason) → separate action
  → deterministic: status = rejected, reason stored
```

## Demo dataset intent (not yet seeded)
Five MachBau components chosen deliberately for contrasting risk profiles: hydraulic pump
(expensive, long lead time → high-risk/escalate), servo motor (mid-cost, substitutable →
good "recommend substitute" case), PCB/control board (mid-cost, supply-sensitive → escalate,
don't auto-order), steel housing (cheap per-unit, usually in stock → auto-approve case),
fasteners (trivial cost → never worth escalating). Goal: one production order shows the
agent doing three different things across its components in a single demo run.

## Code style (carried over from prior projects)
- `export const` over `interface` for simple single-use type definitions
- No labeled-argument syntax (e.g. `invoke(input: toolCall.args)`) — invalid TypeScript
- `BaseChatModel` as the model factory return type — never a union type like
  `ChatOpenAI | ChatGoogleGenerativeAI`
- Tools must return strings (`JSON.stringify` objects before returning)
- Module-level initialization only: model instances, any LangChain/LangGraph constructs must
  never be recreated inside request handlers
- Structured logging required for every action: e.g. `availability_checked`,
  `shortage_detected`, `llm_call_started`, `llm_call_completed`, `escalation_created`,
  `purchase_order_created`
- `console.log` is fine in normal service code; only forbidden inside MCP server processes
  (stdout is the protocol stream there — use `console.error`)

## LangChain/LangGraph gotchas (costly to relearn — do not reintroduce)
- `createAgent` from `langchain` package is correct; `createReactAgent` from
  `@langchain/langgraph/prebuilt` is deprecated
- Param names: `llm` → `model`, `memory` → `checkpointer`, `messageModifier` → `systemPrompt`
- `MemoryVectorStore` only imports correctly from `@langchain/classic/vectorstores/memory`
  in v1.x

## Working discipline
- Avik writes core business logic (stock math, LLM prompt/schema design, approve/reject logic)
  himself, closed-book, without reference materials.
- Claude Code handles: scaffolding, `cds import`, boilerplate config, `.http` test file
  generation, Fiori annotation scaffolding, bash/pipeline scripts.
- Do not make architecture decisions (StateGraph vs. plain actions, auto-order limit logic,
  entity model changes) unilaterally — flag back for discussion rather than assuming.
- Verification standard: real code, real persisted rows, actual `.http` response pasted —
  "it's working" is never sufficient confirmation on its own.

## Current phase / next steps
1. Confirm real `Material` ID format from `A_MatlStkInAcctMod?$filter=Plant eq '1010'&$top=10`
2. Run `cds import` on the confirmed metadata → `srv/external/`
3. Seed `db/data/*.csv` with the 5-component demo dataset
4. Draft `srv/shortage-service.cds` — action signatures only, no logic
5. Avik writes `checkAvailability` logic, tests via `.http`, no LLM yet
