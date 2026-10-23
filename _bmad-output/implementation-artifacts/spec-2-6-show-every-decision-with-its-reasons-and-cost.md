---
title: 'Story 2.6: Show every decision with its reasons and cost'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: 'bc5e0b5db389d10a8eb6a7195b0127c04f8ad67f'
baseline_commit: 'bc5e0b5db389d10a8eb6a7195b0127c04f8ad67f'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      TurnCost can leave out the usage of an earlier attempt's decision when a broken session is retried.
    evidence: |-
      Conversation.Replied overwrites Turn.TurnDecisionRef with the DecisionRef of every non-busy answer, the SessionBroken answer included, and Ownership.TurnCost sums only TriageDecisionRef and TurnDecisionRef.
      Whether a SessionBroken answer carries a DecisionRef with a Usage row is Lane A's Decide (a stub in this tree); reading that code once it records decisions would settle it.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/Conversation.cls (Replied)
    severity: medium (unverified)
  - summary: >-
      No test drives the bridge's own emission of decision.recorded and turn.step into BridgeSink.
    evidence: |-
      Every BridgeSink test and the D6 and D10 sinkEvent helper call OnEvent directly. Decide is Epic 0's stub and no Lane A story that emits events is merged, so nothing in this tree calls HostSink.OnEvent from the bridge.
      When the emitter lands, add one test in which a real Decide records a decision for a session and a decision event reaches that session's stream.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls (OnEvent)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** A reply on the page shows no decision. Nothing reaches the page from the bridge: `OcuTalon.Core.BridgeSink` is Epic 0's do-nothing sink, `Ownership.TurnCost` and `RunCost` answer `{}`, and `chat.message` carries no decision, cost or check rows. `Conversation` never calls `Checks.Render`, so the user cannot see why OcuTalon answered as it did, what it cost, or what was checked.

**Approach:**
- **Server.**
  - Build `BridgeSink`: `decision.recorded` becomes a `decision` event, and `turn.step` becomes a `turn.step` event for the session's running turn.
  - Implement `TurnCost` and `RunCost` over `Usage` rows, through new `Ownership` row kinds.
  - Put each turn's shown decision, its turn cost and its check key and rows on `chat.message` (and on the `Outbound`). `Conversation` calls `Checks.Render` on a reply's `HostData`.
- **Page.**
  - The decision strip under every reply: the chip with its tooltip, the Fallback flag, confidence and cost, the reason lines, and the inline **Decision details**.
  - The indicator's step label.
  - The check rows.

## Boundaries & Constraints

**Always:**
- **BridgeSink (AD-31, AD-33).** `OcuTalon.Core.BridgeSink` overrides `OnEvent(type, ownerRef, payload)`. It is the one publisher of `decision` and `turn.step`.
  - **Never fails its caller.** It returns `$$$OK` for every input: an error or exception is logged (`$$$LOGWARNING`), and nothing is published.
  - **Locks.** It waits on no lock for more than 1 s. It publishes with `Live.Publish`'s new `lockWait` argument set to its `LOCKWAIT = 1`, and a busy stream drops the event.
  - **Owners.** It acts only when `ownerRef` is a session `Ref` (`Live.Publish.IsStream`, and not `instance` or `eval`). `eval` and `instance` publish nothing.
  - **Other types.** `approval.*` (Story 2.8) and `budget.capped` (Story 16.9) return OK and do nothing yet.
- **`decision.recorded`** (payload `{ref}`). It reads the row with `Ownership.Decision(ref, ownerRef)`, which finds nothing for another owner's row.
  - When found, it publishes `decision` on the owner's stream with `Live.Payload.Decision.FromRow(row)`, for every `Kind`. That payload holds:
    - outcome, reasons, confidence, fallback and its reason;
    - the four token counts, cost, the model's display name, agent steps and duration;
    - `ref` (the decision-message reference), the trace target (`traceHeaderId` = `TraceSessionId`), `itemId` and `itemSummary`.
  - An empty or unknown ref, or a payload that is not an object, publishes nothing.
- **`turn.step`** (payload `{decisionRef, label}`). It reads the session's queue (`Ownership.TurnQueue`). Only when the session has a `running` turn does it publish `turn.step` on the owner's stream: `{turnRef: <the running turn's Ref>, decisionRef, label}`, where `label` is the trimmed label and nothing else of the step.
  - It publishes nothing when:
    - the label is empty;
    - no turn is running;
    - the bridge context is active (`OcuTalon.Bridge.Context.Active()`) and its `ItemId` differs from the running turn's `ItemId` (an untrusted `Intake` turn of the same session).
- **New `Ownership` row kinds (AD-13 as amended).** Each has fixed SQL with the owner in its `WHERE`, and joins `TestIsolationEveryRowKind`. There is no new unchecked prepare and `ALLOW_UNCHECKED` is unchanged.
  - `decision` (`ao`): `SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE Ref = ? AND OwnerRef = ?`.
  - `turnUsage` (`oaa`): `SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND (DecisionRef = ? OR DecisionRef = ?) ORDER BY ID`.
  - `runUsage` (`oa`): `SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND RecordedAt >= ? ORDER BY ID`.
  - `runDecisions` (`oa`): the same over `OcuTalon_Bridge_Data.Decision`.
- **`TurnCost(turnRef, Output sc)` (AD-20).** It opens the turn (`Turn.RefIndexOpen`, as `SessionRef()` opens a Session) and sums `turnUsage` with the turn's own `SessionRef` as the owner. Its two refs are `TriageDecisionRef` and `TurnDecisionRef`.
  - It returns `{"inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "costUSD"}`, each 0 when the turn has no usage rows.
  - An unknown turn gives `{}` with an error in `sc`.
- **`RunCost(sessionRef, since, Output sc)`.** It sums `runUsage` and counts `runDecisions` from `since` on (an empty `since` counts all). It returns `{"decisions", "inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "costUSD", "models": [model ids, in first-use order]}`.
  - `eval` and other owners are never counted.
  - A read error gives `{}` with `sc`.
- **The shown decision of a turn.** `Turn.ShownDecisionRef()` gives:
  - for a fallback reply (`ReplyCatalogKey` set): `TurnDecisionRef`, else `TriageDecisionRef`;
  - otherwise: `TriageDecisionRef`, else `TurnDecisionRef`.

  `ChatMessage.FromRow` and `Conversation.Tell` both use it.
- **`chat.message` (AD-12; Conversation stays its one publisher).** `ChatMessage.FromRow(row)` keeps every field and adds:
  - `decision`: the shown decision's `Live.Payload.Decision.FromRow`, read with `Ownership.Decision(ref, row.SessionRef)`;
  - `turnCost`: a `Part.Cost` from `TurnCost(row.Ref)`, set only when `decision` is;
  - `checkKey`, and `checks`: a list of `Part.CheckRow` `{result, entry, finding, checkedAt}` parsed from `Turn.CheckRows`, with non-object elements skipped.

  A failed read leaves those fields empty and never fails the publish or `/state`. The snapshot's key list is unchanged.
- **Check results (AD-28).** For a reply that is not a fallback, `Conversation` parses `Reply.HostData`. When it is a JSON object with an array `checks`, `Conversation` calls `Checks.Render(checks, .rows)` through the private seam `RenderChecks`. When the key or the rows are not empty, it stores `Turn.CheckKey` and `Turn.CheckRows` (JSON) before the turn is saved done.
  - The guard has already run in `Decide`.
  - Bad JSON, no `checks`, or an error in `Render` add nothing, and the turn still ends normally.
- **`Outbound`** gains `DecisionRef` (`ShownDecisionRef()`) and `CheckKey`. `CheckRows` exists already. `Tell` sets all three.
- **The decision strip (UX-DR61, D:792).** It sits in the reply element (`data-part="reply"`), after the reply's text and its check rows. While a turn is running with a decision, it sits after the indicator.
  - **When it shows.** A turn has a strip when its `chat.message` has `decision` or its reply is a fallback.
  - **The fallback state.** It is a fallback strip when the reply is a fallback or `decision.fallback` is set.
  - **Line 1** shows:
    - the chip: `Tell now` on a fallback, otherwise the decision's outcome (`tellnow` → `tell-now`), and no chip for an unknown outcome;
    - the Fallback flag, on a fallback;
    - "Confidence 0.92", left out on a fallback or with no confidence;
    - the cost: the turn's cost (`turnCost.costUSD`), left out with no `turnCost`.

    The " · " separators are `aria-hidden`.
  - **Line 2** shows the reason lines: a fallback's reason first, as a sentence ("The model didn't answer within 60 seconds.", in `--warning-ink`), then the decision's `reasons` split into trimmed, non-empty lines.
    - The fallback reason is the turn's `fallbackReason` when the reply is a fallback, else the decision's.
    - The newest strip of the chat shows at most 3 lines. Every other strip shows its first line only, on one line with an ellipsis (mockup `.strip-2.collapsed`).
    - The text is rendered by interpolation only.
  - **The Details control** comes last when there is a decision. It is a `<button>` with the visible text "Details" and a chevron, named "Decision details", with `aria-expanded` and `aria-controls`. It opens the details inline, never as a dialog or popover. Esc on it collapses the details, and focus stays.
  - **Name and description.** The strip is `role="group"`, named by its chip's label. Its accessible description is the outcome's meaning (`CHAT_TEXTS.meaning*`), from a `hidden` element referenced by `aria-describedby`.
  - **A fallback with no decision** shows the chip, the flag and the reason, with no confidence, no cost and no Details.
- **Decision details (UX-DR62, mockup `states.html:591-599`).** The rows are, in this order:
  - Tokens: "Input 1,084 · Output (includes thinking) 312 · Cache read 0 · Cache write 0" in `mono-sm`, each count 0 when absent;
  - Model: the decision's `model`;
  - Agent steps: the count, 0 when absent;
  - Duration;
  - Decision message: the decision's `ref`, in `mono-sm`;
  - Cost: "Decision $0.0003 · Turn $0.0008" when the turn's cost is above the decision's, otherwise the decision's cost alone.

  Model, Duration and Decision message are left out when absent. The details are the shown decision's own, and the Cost row compares that decision with the turn.
- **Formats (UX-DR124, D:673).** Each formatter is node-tested.
  - **Cost** mirrors `Msg.Catalog.Cost`, including its rounding tiers. Below $0.0001 (0 included) it shows "<$0.0001"; under $0.01, 4 decimals; under $1, 3; otherwise 2. The tier is the one of the shown amount.
  - **Tokens** use en-US grouping ("1,084").
  - **Confidence** has two decimals.
  - **Duration** shows one decimal under 60 s ("3.4 s"). From 60 s it shows whole minutes and seconds ("1 min 3 s").
  - Figures are tabular (base.css sets `tabular-nums` on the body).
- **The outcome chip (UX-DR63, UX-DR15).**
  - It stays a borderless pill that cannot take focus, with its icon `aria-hidden`.
  - It gains the `appTooltip` of its meaning, for the pointer only: it shows after 300 ms and Esc dismisses it. It does this everywhere it renders, the empty chat panel included.
  - The Tooltip directive's contract line becomes: "the host carries the same text as its name, or the text also reaches assistive technology another way (the strip's description)".
- **The Fallback flag (UX-DR64, D:795):** an amber pill (`--fallback-flag-*`) with `life-buoy` (`aria-hidden`) and "Fallback".
- **The turn indicator (UX-DR66).** A `running` turn whose `store().turnSteps[turn.ref]` has a label shows "{label}…", with the animated dots. After 10 s it shows "{label} · 12 s", spoken "{label} · 12 seconds". Without a label it shows "Working…" as before.
  - `indicatorOf(reply)` in `chat-view.ts` composes all of these forms.
  - The live store keys `turnSteps` by `turnRef`.
  - It is not a live region.
- **Check rows (UX-DR65, D:793).** They show after the reply's text.
  - **The sentence.** The check key's sentence is `PAGE_TEXTS[checkKey]` when the generator lists it: `checks.allPassed`, `checks.everythingElsePassed` or `checks.nothingWatched`. Any other key shows no sentence (see Design Notes, `whatFailed`).
  - **One row per `checks` entry.** Each row has:
    - the icon (`circle-check`, `circle-x` or `circle-dashed`, from `--check-result-*`) and the word ("Passed", "Failed" or "Not checked");
    - the entry;
    - in muted text, the finding or reason and the time (`pageTime(checkedAt)`, the browser zone).
  - A `result` that is not `passed` or `failed` shows "Not checked", never "Passed".
  - The all-clear sentences come only from the key, never from the rows.
- **The fixed strings** are exported constants with escaped non-ASCII (Rule 14): `DECISION_TEXTS` in `decision-view.ts` and the step forms in `CHAT_TEXTS`.
- **Tests (AD-22, Rule 19).**
  - This story's browser tests that seed sign in as the new fixture user `DECISION` (`ZzDecision`, the user role). Only `chat.spec` C15 sends, as `PANEL`.
  - No spec publishes on the README session or the instance stream.
  - `%UnitTest` classes use `Test.Data.Fixture` and `Fixture.Clean(refs)` naming only their own rows.
  - Node-tested modules import only types.

**Never:**
- **Never edit Lane A paths:** `src/bridge/**`, `Checks/**` (`Render.cls` and `ReplyGuard.cls` are read-only), `Msg/Catalog/Watch.cls`, `Test/Bridge/**` (`Test.Bridge.Ext` must stay green unedited), `Install/**` other than `Install/Step/Web.cls`, `docs/**`, `eval/**`, `release/**`, `lane-a.yml`. Never edit `Production.cls` (`HostSinkClass` already names `BridgeSink`, in Lane A's region), `docker/merge.cpf`, or `test-production.sh`'s Epic 1 fixture check.
- **Never build another story's part:**
  - 2.7: `Notify` routing, `WebChatOut`, notice cards, `Delivery`.
  - 2.8: the rail's rows (Recent decisions included) and `approval.*`.
  - 2.9: every trace link, the strip's "· Trace" included.
  - 2.10 and 2.11: banners and lost contact.
  - 2.12: announcements, the Firefox and WebKit runs, the accessibility scan and the stacked layout.
  - 4.7: the run total's text.
  - 5.7: `Checks.Render`, `ReplyGuard` and `check_status`.
  - 16.9: `budget.capped` and the daily-cap message.
  - 31.2 and 21.5: `BridgeSink`'s notices.
- **Never change:**
  - the snapshot's key list, `POST /messages`, the `decision` payload's shape, the HostSink payloads, `ALLOW_UNCHECKED`, `tokens.css` or `Web.Api.CheckView` (DW-66);
  - what `Ownership.Turns`, `TurnQueue` and `Decisions` return;
  - the pinned leading parameters of `TurnCost(turnRef)`, `RunCost(sessionRef, since)` and `Checks.Render(results, *rows)`.
- **Never show:**
  - tokens or cost per step;
  - an all-clear from anything but the key;
  - a row as "Passed" unless its result is `passed`;
  - model text as HTML.
- **Never run on slot B:** `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry`, `Test.Demo.Production`, `Test.Core.CommandsInProduction` or `Test.Core.ConversationProduction` (Rule 21).
- **Never add** a dependency.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Decision recorded | `OnEvent("decision.recorded", S, {ref: D})`, D owned by S | One `decision` event on S with `Decision.FromRow(D)` | Returns OK |
| Not S's | D owned by `eval`, `instance` or another session; ref empty or unknown; payload not an object | Nothing published anywhere | Returns OK |
| Step | `turn.step` for S with running turn T | `turn.step` `{turnRef: T, decisionRef, label}` on S; the page shows "{label}…" within 2 s | — |
| Step, no target | S has no running turn; empty label; the active context's ItemId is not T's | Nothing published | Returns OK |
| Busy stream | S's stream lock held by another job | Returns OK after about 1 s; nothing published | Logged warning |
| Reply | Done turn with a triage decision (act, 0.92, 4 reason lines), usage $0.0003 + $0.0005 | "Act" · "Confidence 0.92 · $0.0008"; 3 reason lines if newest, else 1; Details; description "OcuTalon took or requested an action" | — |
| Fallback reply | Reply decision `fallback` `timeout` | "Tell now", Fallback flag, no confidence; first line "The model didn't answer within 60 seconds." in warning-ink | — |
| No decision | Fallback turn with no decision row (stub Decide) | Tell now, Fallback, the reason line; no confidence, cost or Details | — |
| Running | `running` turn with its triage decision | The indicator, then the strip | — |
| Details | Press **Details** | Inline, `aria-expanded` true: Tokens, Model, Agent steps, Duration, Decision message, Cost ("Decision $0.0003 · Turn $0.0008", or "$0.0003" when equal); Esc collapses | — |
| Formats | 0, 0.00004, 0.0006, 0.042, 0.99996, 1.24; 1084 tokens; 0.9; 3400 ms, 63000 ms | "<$0.0001", "<$0.0001", "$0.0006", "$0.042", "$1.00", "$1.24"; "1,084"; "0.90"; "3.4 s", "1 min 3 s" | Absent counts are 0 |
| Chip | Hover the chip 300 ms; Tab through the strip | The tooltip shows the meaning; the chip is never focused | Esc hides it |
| Checks | Reply with `HostData` `{"checks": [...]}`, Render gives key K and rows | K and rows on Turn, Outbound, `chat.message`; page: K's sentence (if listed), then one row each | Unknown result: "Not checked" |
| No checks | Stub Render; no `checks`; bad JSON; a fallback reply | No key, no rows | The turn ends normally |
| TurnCost | Turn with both refs; usage rows of both, one Estimated; another session's and an eval row with the same DecisionRef | The sums of the turn owner's rows only | Unknown turn: `{}` and an error |
| RunCost | S's usage at 10:00, 10:05, 10:10; since 10:05; plus eval and another session | The sums of the last two; `decisions` since 10:05; `models` | Read error: `{}` |
| Reload | Any of the above, then reload | `/state` gives the same strip, details and rows | — |

</intent-contract>

## Code Map

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:1-6` -- an empty subclass of `OcuTalon.Bridge.Ext.HostSink` (`src/bridge/cls/OcuTalon/Bridge/Ext/HostSink.cls`, read-only):
  - `OnEvent` `:32`;
  - the type parameters `TURNSTEP`, `DECISIONRECORDED` and the others `:11-28`;
  - `RefPayload` `:38`, `TurnStepPayload` `:44`.

  The bridge does not emit events yet: `Decide` is the Epic 0 stub (`Bridge/Process/Decide.cls:9,22-25`), and no Lane A story is merged into this branch. So the tests call `OnEvent` directly, with fixture rows.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - the stubs `TurnCost` `:38-42` and `RunCost` `:44-48`;
  - the class comment (`:20`, "TurnCost and RunCost are Story 2.6's");
  - `Incident(ref, sessionRef)` `:170-177`, the pattern for `Decision(ref, sessionRef)`;
  - `TurnQueue` `:106`;
  - `Rows` `:232-275` (bind expansion `:248-256`, the refusals `:236-245`);
  - `Statement` `:280-340` (`decisions` `:311-314` is the shape of the new kinds).
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- the properties `:8-55`: `TriageDecisionRef`, `TurnDecisionRef`, `ReplyCatalogKey`, `FallbackReason`, `ItemId`; `RefIndex` `[Unique]`.
  - Add `CheckKey` (128) and `CheckRows` (`MAXLEN = ""`, JSON), each with a new storage slot after the last one.
  - Add `Method ShownDecisionRef() As %String`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
  - the header `:1-30`;
  - `Decided` `:361-372` stores `TriageDecisionRef`, then `Announce` (running);
  - `Replied` `:406-419` (`TurnDecisionRef` `:414`, Fallback `:417`, reply `:418`);
  - `Conclude` `:480-494`, `Announce` `:497-506`;
  - `Tell` `:510-526` sets `CatalogKey`/`Slots` for a fallback.

  Rules for the edit:
  - `TestSourceKeepsToItsBoundaries` (`Test/Core/ConversationTurns.cls:873`) fails on `OcuTalon.Msg.Catalog`, `SendRequestSync` or `OcuTalon.Core.Allowance` in Conversation. `OcuTalon.Checks.Render` is allowed.
  - Busy and broken replies are never parsed for checks.
- `src/ocutalon/cls/OcuTalon/Msg/Outbound.cls` -- `:6-24` (`CheckRows` `:24`, "The check rows a tool filled, as JSON"). Add `DecisionRef` (22) and `CheckKey` (128), each with a storage slot.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls`:
  - `Publish` `:52`, `LOCKWAIT = 5` `:16`, the lock `:64`;
  - `IsStream` `:43`;
  - `TYPES` `:10`, which holds `decision:Decision` and `turn.step:TurnStep`.

  Add a trailing `lockWait As %Integer = {..#LOCKWAIT}`, used in the `Lock` and in its message.
- `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` -- its properties `:6-39`, `FromRow` `:40-62` (and its doc comment). Each new property is on one line, as `payloads.mjs` reads them:
  - `Decision As OcuTalon.Live.Payload.Decision(%JSONFIELDNAME = "decision")`;
  - `TurnCost As OcuTalon.Live.Payload.Part.Cost(%JSONFIELDNAME = "turnCost")`;
  - `CheckKey As %String(%JSONFIELDNAME = "checkKey", MAXLEN = 128)`;
  - `Checks As list Of OcuTalon.Live.Payload.Part.CheckRow(%JSONFIELDNAME = "checks")`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls` -- `FromRow` `:67-91` and `ModelName` `:95-98`. It is reused, not copied.
- `src/ocutalon/cls/OcuTalon/Live/Payload/TurnStep.cls:6-9` -- add `TurnRef As %String(%JSONFIELDNAME = "turnRef", MAXLEN = 22)`.
- New: `Live/Payload/Part/Cost.cls` (the five totals) and `Part/CheckRow.cls` (`Result`, `Entry`, `Finding`, `CheckedAt`), as `Part/TraceTarget.cls` is built.

**Server tests (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - `Decision(ownerRef, kind, recordedAt)` `:109-123` (Outcome `notify`; no tokens, cost or reasons);
  - `Keep` `:292`, `Record` `:300-303` (keyed on `row.Ref`, which `Usage` lacks);
  - `Clean(refs)` `:212-238`;
  - `Turn` `:27`, `Session` `:14`.

  Callers of `Decision`: `Test/Data/Ownership.cls:204,281-284,473`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`:
  - `TestIsolationEveryRowKind` `:307` (kinds `:315`);
  - `TestRowsRefuses` `:335` (the further-argument loop `:354`);
  - `TestOrders` `:260`, `TestInstanceScope` `:124`;
  - `Seed` `:460-478`, `ReadAll` `:480-511`;
  - `Refs` `:513` reads `.Ref`.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls` -- `OnRequest` `:19-90` (new `DecisionRef` `:42`; the turn answers `:43-72`); `Script` `:95`, `Clear` `:128`. It writes no `Decision` or `Usage` rows today.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls` -- the Outbound recorder `:49-54` (it lacks `checkRows`); the overrides `Send` `:34-67` and `SetTimer` `:69`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` -- slot-safe, with the helpers `Session` `:1037`, `NewProbe` `:1049`, `Item` `:1058`, `Pump` `:1072`, `Sent`/`SentFor` `:1111-1123`, `ChatEvents` `:1141`; `TestStagesPublished` `:180` is the pattern.
- `src/ocutalon/cls/OcuTalon/Test/Core/Commands.cls:99-106` -- `TestStubs` asserts `TurnCost`/`RunCost` give `{}` (it changes).
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`:
  - the header `:1-5` ("the 25 payload and part classes");
  - `TestContracts` `:73-91` (`classes, 25`);
  - `TestFromRowBuilders` `:244-275` (a session-less row still gives the empty fields);
  - `XData Contracts` (`ChatMessage` `:389-404`, `TurnStep` `:525-531`).
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls:207-218` -- the `Outbound` oracle.
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:367` -- the `Turn` table oracle.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - `StateJob` `:919`, `Items` `:963`;
  - `TestStateSections` `:158` and `TestStateChatCapped` (2.5) are the fixture patterns.

**Read-only**
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` -- every field, `RefIndex [Unique]` `:71`, `OwnerRefIndex` `:75`.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- `DecisionRef`, `OwnerRef`, the four token counts, `CostUSD`, `Estimated`, `RecordedAt`, `Model`; `DecisionRefIndex` `:56`; no `Ref`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `FIELDS` `:10` (`ItemId`, `DecisionRef`, `HostData`), `Begin` `:45-60`; `Active()` and `Current()` are pinned in `Test/Contract/Ac.cls`.
- `src/ocutalon/cls/OcuTalon/Checks/Render.cls:8-12` -- the stub returns `""` and `[]`; pinned as `"results,*rows"` (`Ac.cls:314`).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:140-160` -- it checks only the leading parameters (`:325-326`), so trailing `Output sc` parameters pass.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:95-122` (Lane A) -- calls `BridgeSink.OnEvent(<each type>, "zz", {})`, expecting OK and no new live event. It stays green: "zz" is no session `Ref`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:49-75` -- the `checks.*` keys: `notEverything` and `notEverythingRestPassed` take `whatFailed: text`; `everythingElsePassed`, `allPassed` and `nothingWatched` take no slots.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:226-237` -- `Cost`, the server form of the cost rule; its oracle is `Test/Msg/Catalog.cls:284-299`.
- `docker/tests/test-class-rules.sh:33-35` -- `ALLOW_UNCHECKED` stays as it is.

**Page (Lane B, edit)**
- `web/src/app/chat/ocutalon-reply.ts`:
  - the template `:25-82`: the indicator branch `:28-38`, the reply branch `:39-69`, `.text` `:44-68`;
  - the `indicator` computed `:173-186`; `fallback` `:189-196`;
  - the styles `:84-164`, about 2 kB of the 4 kB budget, so the new parts are their own components.

  C2's log (`web/e2e/chat/chat.spec.ts:231-240,270`) reads `.indicator` or `.text`, and C2/C3 read `.text` (`:272,:351`). So the strip and the check rows go outside `.text`.
- `web/src/app/chat/chat-view.ts`:
  - `ReplyView` `:65-70`, `TurnView` `:73-83`;
  - `replyOf` `:114-133`;
  - `chatView(chat, outbox, runningSince, now)` `:147-175`;
  - `CHAT_TEXTS` `:18-47` (the meanings `meaningIgnore` and the others; `separator`).
- `web/src/app/chat/chat-panel.ts` -- it passes the `TurnView` (`:65-69`) and reads `store()?.chat` (`:166-187`). It now also reads `store()?.turnSteps`.
- `web/src/app/chat/outcome-chip.ts` -- `Outcome` (`'tell-now'`) `:7`, `CHIPS` `:9-14`, the template `:24`, the comment `:16-18`.
- `web/src/app/shared/tooltip.ts` -- `[appTooltip]` `:43-51`, pointer only `:65`, 300 ms `:6`, the contract line `:40`.
- `web/src/app/live/live-store.ts` -- `COLLECTIONS['turn.step']` `:51`, `fromSnapshot` `turnSteps` `:122`, `applyEvent` `:174-175`.
- `web/src/app/live/payloads.ts` (generated):
  - `ChatMessagePayload` `:71-84`, `DecisionPayload` `:117-138`, `TurnStepPayload` `:160-163`;
  - `web/scripts/payloads.mjs`: `tsType` `:103-114` maps only scalars and Parts; `generate` `:122-160` has `direct` and `parts`.
- `web/scripts/catalog.mjs`:
  - `LISTED_KEYS` `:31`, `pageText` `:91-108`, `generate` `:155-190`;
  - its options `--core --catalog --out` (header `:1-18`, `parseArgs`). It reads only `Catalog/Core.cls`.
- `web/src/app/icon/icon.ts` -- `IconName` `:4-18` and the `@switch` `:37-104`. It lacks `life-buoy`, `circle-check`, `circle-x`, `circle-dashed` and `chevron-up`.
- `web/src/app/chat/page-time.ts` -- `pageTime(iso, locale?, timeZone?)`, used for the check rows.
- `web/src/styles/tokens.css` (generated, read-only) -- `--decision-strip-*` `:317-325`, `--check-row-*` `:326-333`, `--outcome-chip-*` `:344-359`, `--fallback-flag-*` `:360-363`, `--check-result-*` `:541-546`, `--tooltip-*` `:224-230`, `--type-mono-sm-*` `:91-94`, `--warning-ink` `:28`. `shell-styles.test.mjs` fails on an undeclared `var(--x)`.
- UX:
  - `EXPERIENCE.md`: `:216` (tooltip), `:252-264` (strip, details, check row, chip, flag, indicator), `:374` (Esc), `:383` (disclosures), `:184-191` (formats), `:735-737` (the check sentences), `:745-755` (reasons);
  - `DESIGN.md`: `:791-796`, `:362-371`, `:398-402`, `:564-572`;
  - mockups: `states.html:560-600` (B2 fallback reply, B3 details) and `main-page.html:436-439` (the collapsed strip).

**Browser and CI tests (Lane B, edit)**
- `web/e2e/support/iris.ts`:
  - `fixtureUser` `:15`, `irisScript` `:39`, `chk` `:57`, `literal` `:63`;
  - `publishReminder` `:69-84`, the pattern for `sinkEvent`;
  - `quoted` `:92-114`;
  - `SeedTurn` `:121-129`, `Seeded` `:132-135`, `seedTurns` `:143-185`.
- `docker/tests/test-sign-in.sh` -- the users `:51`, the role loop `:111`, the env `:160-176`, the pass and fail lines `:186,:192`, the header `:21-22`.
- `web/e2e/chat/chat.spec.ts` -- the header rules `:6-16`, `open` `:60` (PANEL), `sendWithEnter` `:83`, `replyOf` `:91`, `holdEvents` `:103`; it gets C15.
- `web/scripts/live-store.test.mjs:189-199,285` pins `turnSteps` by `decisionRef`; `chat-view.test.mjs` (describes `:29-204`); `catalog.test.mjs`; `payloads.test.mjs`.
- `ci/units.sh:51` -- `WEB_INPUT_PATTERN`, with `docker/tests/test-ci-changes.sh:192-194` (its `paths_case` lines) and `ci/mock/test/constants.test.mjs:123-134`. The shards are by area (`:11-15`), so `Test.Core.BridgeSink` joins `lane-b` with no edit.

## Tasks & Acceptance

**Execution:**
- **Task 0** (implement stage, slot B, before `FromRow` changes; recorded under `## Verification`). A temporary `TestMeasureStateDecisions` in `Test.Web.Api`:
  - seeds a fixture session with 100 done turns, each with a triage and a turn decision and two `Usage` rows;
  - runs `/state` three times through `StateJob`;
  - logs `MEASURE` lines with the median and the body length.

  Run it on the old `FromRow` and on the new one, then remove it (`grep -rn MEASURE src/` finds none).
  - **Why.** The new `FromRow` makes three owner-checked reads per turn, about 300 per snapshot.
  - **The limit.** If the new median is over 1 s on slot B, stop with a `## Clarification Needed`, because FR-12's 2 s bound is at risk on the CI hosts. Otherwise only record it.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - add the four row kinds to `Statement` (Boundaries);
  - add `Decision(ref, sessionRef, Output sc) As OcuTalon.Bridge.Data.Decision`, `""` when not visible, in the shape of `Incident`;
  - implement `TurnCost(turnRef, Output sc)` and `RunCost(sessionRef, since, Output sc)`;
  - rewrite the class comment.

  Why: AD-20's totals under AD-13.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- add `CheckKey`, `CheckRows` and `ShownDecisionRef()`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- add the `lockWait` argument (default `LOCKWAIT`).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/Cost.cls`, `Part/CheckRow.cls` (new); `ChatMessage.cls` (four properties, `FromRow`); `TurnStep.cls` (`TurnRef`).
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - `Parameter LOCKWAIT = 1`;
  - `OnEvent`, with the private `Recorded(ownerRef, payload)` and `Step(ownerRef, payload)`;
  - `Include Ensemble` for the log;
  - a class comment that states the contract (Boundaries).
- `src/ocutalon/cls/OcuTalon/Msg/Outbound.cls` -- add `DecisionRef` and `CheckKey`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
  - `Replied`: before `Conclude` on a usable reply, call `Checked(turn, answer.HostData)`, which calls `RenderChecks(results, .rows)`. `RenderChecks` is a private seam calling `##class(OcuTalon.Checks.Render).Render`;
  - `Tell` sets `DecisionRef`, `CheckKey` and `CheckRows`;
  - the header gains the check and decision lines.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - `Decision(ownerRef, kind, recordedAt, fields As %DynamicObject = "")` sets each named property (`Ref` and `ItemId` included) after the defaults, and its default Outcome becomes `tellnow`;
  - add `Usage(decisionRef, ownerRef, fields As %DynamicObject = "")`, recorded under its `DecisionRef`: `Keep(row, ref)` and `Record(row, ref)` take an optional ref, defaulting to `row.Ref`, so `Clean(<the decision ref>)` removes the decision's usage rows too.
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` (new, slot-safe; fixture sessions and decisions, `Fixture.Clean` of its own refs):
  - `TestDecisionRecordedPublishesTheDecision`: every AC field written out, and a `turn` kind decision too;
  - `TestEvalAndInstancePublishNothing`: no `Live.Event` row holds the decision's ref (a payload search, so that a concurrent unrelated event cannot disturb it);
  - `TestAnotherSessionsDecisionPublishesNothing`;
  - `TestBadPayloadsPublishNothing`: an empty or unknown ref, a non-object payload, `approval.*`, `budget.capped` and an unknown type;
  - `TestTurnStepForTheRunningTurn`: `turnRef`, `decisionRef` and the label, trimmed;
  - `TestTurnStepWithNoRunningTurn`: no turn, a queued turn only, an empty label;
  - `TestTurnStepOfAnotherItem`: `Bridge.Context.Begin` with another `ItemId` publishes nothing, the turn's own `ItemId` publishes, and `End` follows;
  - `TestNeverWaitsMoreThanASecond`: a `Job` holds `^OcuTalonP.LiveEventC(S)`. `OnEvent` returns OK in 0.9 s to 4 s and publishes nothing, then the holder is released. The window only has to tell the 1 s wait from `Publish`'s old 5 s, so it holds on slow slot B;
  - `TestNeverFailsItsCaller`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`:
  - `decision`, `turnusage`, `runusage` and `rundecisions` join `TestIsolationEveryRowKind`, `Seed`/`ReadAll` (`Refs` uses `DecisionRef` for `Usage` rows) and `TestRowsRefuses`' loop;
  - add `TestDecisionRead`, `TestTurnCost` and `TestRunCost`, with the matrix rows' fixtures and the sums written out (no value read from the code).
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls`:
  - `Record(ownerRef, on)`: while on, each non-busy answer also writes a `Decision` row through `Fixture.Decision`. The row has the answer's `DecisionRef`, the request's owner, kind and item, and fixed fixture values (outcome or fallback as answered, reasons "zz reason one\nzz reason two", confidence 0.9, model `claude-haiku-5-5`), plus one `Usage` row (cost 0.0003 for decide, 0.0005 for turn). A second answer of the same kind for the same item (a retried turn) writes no row, because `Decision` is unique on (`ItemId`, `Kind`);
  - a turn answer `checks` (a Reply with `HostData` `{"checks":[{"zz":"result"}]}`);
  - `Written(ownerRef)`: the decision refs it wrote, which `ConversationTurns` adds to its `Fixture.Clean` list, so the rows go with the test;
  - `Clear(ownerRef)` also clears the flag and the list.

  Update the class comment.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls` -- record `decisionRef`, `checkKey` and `checkRows` for an Outbound. Override `RenderChecks`: when `^OcuTalonTest("ConversationProbe", RunNumber, "render")` holds `$ListBuild(key, rowsJSON)`, record the results given and return them; otherwise call the class it extends.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` -- add:
  - `TestDecisionOnChatMessage`: with `Record` on, running carries the triage decision and its cost; done carries the triage decision and both costs; a fallback reply's done carries the reply decision;
  - `TestOutboundCarriesTheDecision`;
  - `TestCheckRowsFromRender`: probe render, on Turn, Outbound and `chat.message`;
  - `TestStubRenderAddsNothing`: the real stub;
  - `TestNoCheckRowsWithoutResults`: a fallback reply, bad JSON and HostData with no `checks`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` -- the contracts for the four `ChatMessage` properties, `TurnStep.TurnRef`, `Part.Cost` and `Part.CheckRow` (27 classes; header). Add `TestChatMessageCarriesItsDecision`: fixture rows give `decision` = `Decision.FromRow` and `turnCost`; `CheckRows` JSON with a non-object element gives the object rows; a session-less row gives none.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls`, `Test/Data/Tables.cls` -- the new `Outbound` and `Turn` properties. `Test/Core/Commands.cls` `TestStubs` keeps the `Recipients` lines; `TurnCost` of an unknown turn gives `{}` with an error.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestStateChatDecision`: `/state`'s chat entry for a turn with fixture decisions, usage and check rows carries `decision.ref` and `outcome`, `turnCost.costUSD` (the sum, written out) and `checks`.
- `web/scripts/payloads.mjs` -- `tsType` maps a property whose type is a direct payload class (one of `direct`) to `<Short>Payload`; anything else stays refused. Add the case to `payloads.test.mjs`. Regenerate `payloads.ts`.
- `web/scripts/catalog.mjs`:
  - add `--watch <file>` (default `Msg/Catalog/Watch.cls`), read with `readEntries` and merged with Core's (a key in both fails);
  - add `checks.allPassed`, `checks.everythingElsePassed` and `checks.nothingWatched` to `LISTED_KEYS`;
  - update the header; regenerate `catalog.ts`.

  `catalog.test.mjs`: the three texts; a fixture whose Watch file lacks a listed key fails.
- `ci/units.sh` -- `WEB_INPUT_PATTERN` gains `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch\.cls$`, and its comment. `docker/tests/test-ci-changes.sh` gains the `paths_case` "the Watch catalog runs web and every group".
- `web/src/app/live/live-store.ts` -- `turnSteps` is keyed by `turnRef` (COLLECTIONS, `fromSnapshot`, comments). Update `live-store.test.mjs` `:189-199,285`.
- `web/src/app/icon/icon.ts` -- add `life-buoy`, `circle-check`, `circle-x`, `circle-dashed` and `chevron-up`, as Lucide paths like the others.
- `web/src/app/chat/decision-view.ts` (new, node-tested, types-only imports):
  - `DECISION_TEXTS`;
  - `formatCost`, `formatTokens`, `formatConfidence`, `formatDuration`;
  - `sentenceOf(text)` (capital first letter, a final ".");
  - `outcomeOf(outcome, fallback)`;
  - `reasonLines(reasons, fallbackSentence, max)`;
  - `costRow(decisionCost, turnCost)`;
  - `checkRowView(row)` → `{result: 'passed' | 'failed' | 'not-checked', word, icon}`.
- `web/src/app/chat/chat-view.ts`:
  - the `working` reply gains `step?`;
  - `TurnView` gains `decision?`, `turnCost?`, `fallbackReason?` (set when the strip is a fallback strip), `strip: boolean`, `newest: boolean` (the last turn with a strip), `checkKey?` and `checks?`;
  - `chatView(chat, outbox, runningSince, now, steps = {})`;
  - `indicatorOf(reply)` → `{text, spoken, seconds?, dots}` (moved from the component, with the step forms);
  - `CHAT_TEXTS` gains `stepWorking` "{label}…", `stepElapsed` "{label} · {n} s" and `stepElapsedSpoken` "{label} · {n} seconds".
- New standalone OnPush components, styled from tokens, each within the 4 kB budget:
  - `web/src/app/chat/fallback-flag.ts` (`app-fallback-flag`);
  - `decision-details.ts` (`app-decision-details`: inputs `decision`, `turnCost`; a `<dl>` grid as in the mockup);
  - `decision-strip.ts` (`app-decision-strip`: inputs `decision?`, `cost?`, `turnCost?`, `fallbackReason?`, `newest`; it owns the Details state and the `role="group"` name and description, and builds the fallback sentence from `catalog.ts`'s `REASON_KEYS`/`PAGE_TEXTS`);
  - `check-rows.ts` (`app-check-rows`: the sentence and the list).
- `web/src/app/chat/ocutalon-reply.ts` -- the indicator text comes from `indicatorOf`. After `.text` come `<app-check-rows>` and then `<app-decision-strip>`; while running with a decision, the strip comes after the indicator. `chat-panel.ts` passes `store()?.turnSteps`.
- `web/src/app/chat/outcome-chip.ts` -- `[appTooltip]` of its meaning, with the comment updated. `web/src/app/shared/tooltip.ts` -- the contract line (Boundaries).
- `web/scripts/decision-view.test.mjs` (new), and `chat-view.test.mjs` additions (oracles written out):
  - the cost oracle: `Test.Msg.Catalog.TestCost`'s 14 cases;
  - tokens 0, 1,084 and 1,234,567;
  - confidence 0.9 → "0.90";
  - durations 0, 3400, 59949, 59950 and 63000 ms;
  - reason lines: newest 3 of 4, older 1, the fallback first, CRLF, blank lines;
  - the cost row, equal and above;
  - `outcomeOf`: `tellnow` → `tell-now`, a fallback → `tell-now`, unknown → none;
  - `checkRowView`: passed, failed, not_checked, an unknown value and none;
  - every `DECISION_TEXTS` value equals the UX's wording, with "·" as U+00B7 and "…" as U+2026;
  - `indicatorOf` for deciding, working, working at 12 s, a step, and a step at 12 s;
  - `chatView`'s `strip`, `newest` and `fallbackReason`.
- `web/e2e/support/iris.ts`:
  - `'DECISION'` joins `fixtureUser`;
  - `SeedTurn` gains `state?: 'done' | 'running'`, `triage?`, `turn?` (a `SeedDecision` with the decision's fields), `usage?` (`{of: 'triage' | 'turn', ...counts, costUSD}`), `checkKey?` and `checks?`;
  - `Seeded` gains `decisions` (the refs per turn);
  - add `sinkEvent(user, type, payload)` (calls `BridgeSink.OnEvent` with the user's session `Ref`; CHK of its status) and `finishTurn(user, ref)`.

  Every value goes through `quoted()`, and numbers are checked with `Number.isFinite`.
- `docker/tests/test-sign-in.sh` -- the fixture user `ZzDecision` (user role, "decision fixture"): its password, the role loop, the redaction, `OCUTALON_DECISION_USER`/`_PASSWORD`, and the labels (D1-D10, C15).
- `web/e2e/chat/decision.spec.ts` (new; chromium; the user DECISION; `test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' })` as in `chat.spec`; seeds dated 2024-2025, except D2's two turns, dated 2099 so that they are the newest; `unrouteAll` after each test). It has a header rule like `chat.spec`'s, and each test asserts only its own refs. The titles name the matrix rows and ACs:
  - **D1** "a reply shows its decision strip":
    - "Act" with `zap`; no flag; "Confidence 0.92 · $0.0008" (the turn's two usage rows); the first reason line;
    - the strip's top is at or below the reply text's bottom, as the element after it;
    - `role=group` named "Act", with an accessible description containing "OcuTalon took or requested an action";
    - the separators are `aria-hidden`;
    - the strip is not a live region.
  - **D2** "the newest reply shows three reasons and older replies one": two 2099 turns with four reason lines each; the newer shows 3 lines, the older 1 with `text-overflow: ellipsis`.
  - **D3** "a fallback reply shows Tell now, the Fallback flag and its reason first": "Tell now", `life-buoy`, "Fallback"; no "Confidence"; the first line "The model didn't answer within 60 seconds." in `--warning-ink`'s color.
  - **D4** "Decision details opens inline with its figures":
    - `aria-expanded` false, then true; no `role=dialog` and no `.app-popover`;
    - the six labels and values, the tokens and the ref in JetBrains Mono, "Decision $0.0003 · Turn $0.0008";
    - Esc collapses it, and focus stays on the button;
    - a turn whose costs are equal shows "$0.0003" alone.
  - **D5** "the outcome chip has a pointer tooltip and takes no focus":
    - hover for 300 ms or more shows the tooltip with the meaning, and Esc hides it;
    - Tab from the reply never focuses the chip (`tabindex` absent, not focusable);
    - its icon is `aria-hidden`.
  - **D6** "the turn indicator shows the current step's label":
    - a seeded `running` turn with its triage decision, published, shows "Working…" with the strip after the indicator;
    - `sinkEvent('turn.step', {decisionRef, label: 'Checking the Orders production'})` gives "Checking the Orders production…" within 2 s;
    - `finishTurn` in a `finally`.
  - **D7** "check rows show under a reply, never an all-clear from the rows":
    - a turn with `checks.allPassed` and two passed rows: "Everything I checked passed.", then two "Passed" rows with `circle-check`, the entry and the time in the browser zone;
    - a turn with `checks.notEverything` and rows passed, failed (finding) and `zz_unknown`: no sentence, "Passed", "Failed" with `circle-x` and the finding, and "Not checked" with `circle-dashed`;
    - the rows come before the strip.
  - **D8** "a reload shows the same strips, details and rows": the D1, D3 and D7 shapes after a reload.
  - **D9** "the strip is no live region and moves no focus when it lands": a published turn with a decision lands; no `focusin`; `main` has no `aria-live` or `role` log, status or alert.
  - **D10** "/events serves BridgeSink's decision event": a seeded decision and `sinkEvent('decision.recorded', {ref})`. The page's next `/events` answer holds a `decision` event with that `ref` and every AC field.
- `web/e2e/chat/chat.spec.ts` -- **C15** (PANEL) "a fallback reply through the stub Decide shows the fallback strip": send with Enter; the reply's strip shows "Tell now", the Fallback flag and "The model's reply couldn't be used.", with no "Confidence", no "$" and no Details button. Update the header's list.

**Acceptance Criteria:**
- **BridgeSink: decisions (FR-1, FR-2, AD-26, AD-31).** **Given** `HostSinkClass` names `BridgeSink`, **when** `OnEvent` gets `decision.recorded` for a fixture `Decision` row of a session, **then** a `decision` event on that session's stream carries:
  - the outcome, reasons, confidence, fallback flag and reason;
  - the four token counts, cost, the model's display name, agent steps and duration;
  - the `ref`, the trace target (`TraceSessionId`), `itemId` and `itemSummary`.

  Tests: `TestDecisionRecordedPublishesTheDecision`, D10.
- **BridgeSink: steps (FR-3, AD-9).** **Given** a session with a running turn, **when** `OnEvent` gets `turn.step`, **then** `turn.step` on that session's stream carries the running turn's `turnRef` and the step's label only. Without a running turn, or for another item's step, nothing is published (`TestTurnStepForTheRunningTurn`, `TestTurnStepWithNoRunningTurn`, `TestTurnStepOfAnotherItem`).
- **BridgeSink: never fails (AD-31).**
  - **Given** any type, owner or payload, **when** `OnEvent` runs, **then** it returns OK. **Given** the stream's lock held elsewhere, **when** `OnEvent` publishes, **then** it gives up within about 1 s (`TestNeverFailsItsCaller`, `TestNeverWaitsMoreThanASecond`, `Test.Bridge.Ext` unchanged and green).
  - **Given** a fixture `Decision` owned by `eval`, **when** `OnEvent` runs, **then** no live event exists anywhere (`TestEvalAndInstancePublishNothing`).
- **Step label (UX-DR66).** **Given** a running turn, **when** a `turn.step` arrives, **then** the indicator shows "{label}…", and "{label} · N s" after 10 s (D6, `chat-view.test.mjs`).
- **The strip (FR-1, FR-2, FR-4, UX-DR61).** **Given** a reply with its decision, **when** the strip renders directly below it, **then**:
  - line 1 shows the chip, the flag if any, and "Confidence {0.00} · {cost}" with the turn's cost, from `TurnCost`; a fallback omits confidence;
  - line 2 shows up to three reason lines on the newest reply and the first on older ones, with a fallback's reason first in `warning-ink`;
  - "Decision details" comes last;
  - the description includes the outcome's meaning.

  Tests: D1, D2, D3, C15, `decision-view.test.mjs`.
- **TurnCost and RunCost (FR-2, AD-20).** **Given** fixture `Usage` rows, **when** `TurnCost` and `RunCost` run, **then**:
  - `TurnCost` sums the rows of the turn's two decisions;
  - `RunCost` sums the session's rows since a time and counts its decisions;
  - neither counts `eval` or another owner.

  Tests: `TestTurnCost`, `TestRunCost`, `TestIsolationEveryRowKind`.
- **Chip and flag (FR-1, FR-4, UX-DR15, UX-DR63, UX-DR64, UX-DR121).** **Given** a chip or a fallback, **when** it renders, **then**:
  - the chip is a borderless pill that cannot take focus, with its icon hidden, its meaning in the strip's description and a pointer tooltip;
  - every fallback shows the amber "Fallback" with `life-buoy`, with Tell now.

  Tests: D3, D5, C15.
- **Details (FR-2, UX-DR62, UX-DR127).** **Given** I expand "Decision details", **when** it opens inline (`aria-expanded`, never a dialog), **then** it shows Tokens, Model, Agent steps, Duration, Decision message and Cost, with "Decision $x · Turn $y" when the turn cost more (D4).
- **Formats (UX-DR10, UX-DR124).** **Given** any figure, **when** it renders, **then**:
  - costs follow the UX's tiers;
  - tokens have separators;
  - confidence has two decimals;
  - figures are tabular.

  Tests: `decision-view.test.mjs`, D4.
- **Check rows (FR-37, AD-28, UX-DR65, UX-DR120).** **Given** a reply whose `HostData` carries check results, **when** `Conversation` finishes the turn, **then**:
  - `Checks.Render`'s key and rows are on the Outbound and on `chat.message`;
  - the page shows one row per result ("Passed", "Failed" or "Not checked", with its icon, the entry, the finding or reason, and the time);
  - the reserved sentences appear only from the key.

  Tests: `TestCheckRowsFromRender`, `TestStubRenderAddsNothing`, D7, `catalog.test.mjs`.
- **Restart (Epic 2).** **Given** a session with decisions and check rows, **when** the page reloads, **then** every strip, details panel and row returns from `/state` (D8, `TestStateChatDecision`).

## Spec Change Log

- 2026-10-22, spec validation (lead):
  - The veto-window items are ruled as planned (inbox U-28): the `Turn` (and `Outbound`) additions, the composed page text, and the chip tooltip.
  - The spine's Conventions rows are written: "Live events" (amended) and "HostData" (new).
  - Routed through the ledger: DW-90, the `whatFailed` slot, to Story 5.7. The orchestrator writes its bullet after Epic 2 merges.
  - Closed with a probe: DW-91, `Test.Bridge.Ext`'s stale comment (Lane A's).
  - No ledger entry is owned and no decision-pending entry is built on.

## Review Triage Log

### 2026-10-22 — Review pass
- verdicts: 37 findings — high 0, medium 5, low 25, false 6, maybe-false 1
- findings:
  - Blind Hunter
    - `[medium]` `patch` `formatCost` rounds a tie on the binary double, so 0.00015 shows "$0.0001" where the server's `Msg.Catalog.Cost` shows "$0.0002" — confirmed on slot B (`$FNumber` rounds the decimal half up; `Render` of 0.00015, 0.00035, 0.00045, 0.1235, 1.005 and 0.009995 gives $0.0002, $0.0004, $0.0005, $0.124, $1.01, $0.010). Patched: `roundHalfUp` in `decision-view.ts`, the six ties in `decision-view.test.mjs` and in `Test.Msg.Catalog.TestCost`.
    - `[low]` `reject` The failing-check sentences (`checks.notEverything*`) cannot reach the page — spec-bound (Decided 12; DW-90 routes the `whatFailed` slot to Story 5.7); D7 and `catalog.test.mjs` pin the absence.
    - `[maybe-false]` `defer` `TurnCost` could drop the usage of an earlier attempt's decision when a broken session is retried (`Replied` overwrites `TurnDecisionRef`). Would settle it: whether Lane A's `Decide` records a Decision/Usage row for a `SessionBroken` answer; the stub does not. Deferred, medium (unverified).
    - `[low]` `reject` `SetDecision` drops a failed read without a log line — the spec says a failed read leaves the fields empty; the failure is a database error that `/state`'s other reads surface; a log call would add an Ensemble dependency to a payload class.
    - `[low]` `patch` The `Outbound.CheckRows` comment named raw HostData — replaced by the rows `Checks.Render` made, with their four members.
    - `[low]` `reject` A `checks.allPassed` key beside a `failed` row prints the all-clear — by design (AD-28, UX): the sentence comes only from the key and never from the rows; a contradictory pair is a `Render` fault (Story 5.7), and the mutation "All-clear from rows" pins the page's side.
    - `[low]` `reject` A reload mid-turn loses the running turn's step label — the page shows "Working…" until the next step; the snapshot's key list is fixed by the spec; cosmetic.
    - `[low]` `reject` D6's 2 s bound leaves little slack on slow hosts and its second check repeats the first — the 2 s is the AC (FR-12); the repeated check cannot fail alone.
  - Edge Case Hunter
    - `[low]` `reject` `SetDecision` swallows failures without a trace — the same root cause as the Blind Hunter's fourth finding.
    - `[false]` `reject` `TurnCost` re-reads the turn although `FromRow` holds it — `TurnCost(turnRef)` is the pinned one-argument call (Decided 9); the turns `FromRow` receives are saved rows, and an unknown turn is the only way the read fails.
    - `[low]` `reject` A step label over 1000 characters or with inner newlines — labels are fixed text from the tool (AD-9), never model text; `$ZStrip` removes the control characters at the ends.
    - `[low]` `reject` The warning logged in `OnEvent`'s `Catch` could itself throw — theoretical: `Ens.Util.Log` inserts with embedded SQL that sets SQLCODE; only a storage fault would throw.
    - `[low]` `reject` A restarted turn shows its previous attempt's step label until the next step — cosmetic and rare (a sweep restart); the fix would change the store's event rules.
    - `[low]` `reject` A reload loses the step label — the same root cause as the Blind Hunter's seventh finding.
    - `[low]` `reject` `RunCost` opens every row of a long session when `since` is empty — the four statements are fixed by the spec and AD-13; the only consumer (Story 4.7) passes the run's start.
    - `[false]` `reject` No context check when `Bridge.Context` is inactive — Decided 6 says so: with no context the running turn alone decides.
    - `[false]` `reject` `turn.step` carries `decisionRef` beside `turnRef` and the label — the AC lists `{turnRef, decisionRef, label}`; "label only" means no other step content.
    - `[false]` `reject` Details shows fewer than six rows when Model, Duration or Decision message is absent — the spec leaves those three out when absent.
    - `[low]` `reject` `DecideDouble` writes confidence 0 for a fallback answer — a test-double detail no test depends on; no named harm.
  - Verification Gap Reviewer
    - `[medium]` `patch` `ShownDecisionRef`'s fall-through arms were asserted nowhere. Patched: `TestShownDecisionRef` in `Test.Live.Payloads` (seven combinations of the two refs and the fallback key); mutation recorded (red on two assertions).
    - `[low]` `reject` `TestNeverWaitsMoreThanASecond`'s upper bound of 4 s cannot tell 1 s from 3 s — by design: the spec fixes the window (0.9 s to 4 s) to tell the 1 s wait from `Publish`'s 5 s and to hold on slow slot B.
    - `[medium]` `patch` The Digest and Tell now meanings were never read, so swapped meanings stayed green. Patched: D3 asserts the Tell now description, D5 hovers a Digest chip; red under the swap.
    - `[low]` `patch` "Decision details comes last" was asserted by nothing. Patched: D2 compares the button's place with the last reason line (newest strip) and the one line (an older strip); red when the button moves first.
    - `[medium]` `defer` No test drives the bridge's own emission into `BridgeSink`; every test calls `OnEvent` directly. The emitter (`Decide`) is Lane A's stub and out of footprint; deferred until it emits.
    - `[low]` `patch` C15 had no recorded red. Mutation recorded: the fallback-only strip dropped from `chatView` turns C15 red.
    - `[low]` `reject` `TestStubRenderAddsNothing` compares empty with empty — it pins "the real stub adds nothing"; the Checks AC's pinning test is `TestCheckRowsFromRender`, which has its mutation.
    - `[low]` `reject` D9 is named by no AC and no mutation row — it asserts a property of the Strip AC, which has mutation lines (D1, D2, D3).
    - `[low]` `reject` Sub-parts of the Decision event, Steps, Chip-and-flag and Check-rows ACs have no mutation of their own — Rule 19 asks one demonstrated mutation per AC, and each AC has several.
    - `[low]` `reject` `Test.Core.BridgeSink` counts event-log rows of its source class by id mark — no concurrent writer of BridgeSink warnings exists (the shards run serially and the stub `Decide` emits nothing); a scoped count would need a column the log lacks.
    - `[low]` `reject` `Test.Data.Ownership` cleans class-wide in `OnBeforeAllTests`/`OnAfterAllTests` — pre-existing; the new methods use fresh sessions and depend on no leftover or order.
    - `[low]` `reject` `Test.Bridge.Ext`'s "BridgeSink adds nothing" comment is stale — Lane A's file; DW-91 closed with a probe at spec validation.
    - `[low]` `patch` The `decision-view.test.mjs` title claimed "not as a literal" but asserts only the character set — title corrected (`test-boundaries.sh` enforces the literal rule).
    - `[medium]` `patch` `Holding` had no positive control, so "no event holds the Ref" could pass on a broken query. Patched: `TestDecisionRecordedPublishesTheDecision` asserts 0 before and 1 after the publish; red when `Holding` returns 0.
  - Intent Alignment Auditor
    - `[low]` `reject` The chain from the real bridge's emission through `BridgeSink` to the DOM is never joined in one test — by design: `Decide` is Epic 0's stub and no Lane A story is merged; the same gap is deferred above.
    - `[false]` `reject` Esc is bound on the whole strip, where the AC says "Esc on it" — Esc on the Details button bubbles to the strip; D4 presses it on the button; the behaviour is the same.
    - `[low]` `reject` An unknown outcome gives a group with no name, and a normal reply whose decision is itself a fallback has no DOM test — Decided 17 (unknown values fail safe); the view rules are node-tested.
    - `[false]` `reject` The fallback sentence is derived on the page from the lower-case catalog clause — Decided 13 specifies it.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-9:** step labels are fixed text from the tool, never arguments. Tokens are per turn, never per step.
- **AD-12:** full views keyed by `Ref`; the snapshot's key list and shape are unchanged.
- **AD-13 as amended:** four new row kinds, each owner-checked in its `WHERE` and in the isolation test, with no new unchecked path. Text is rendered by interpolation.
- **AD-20:** Decision and Usage, `TurnCost` and `RunCost`, and `eval` excluded.
- **AD-22:** fixture users and throwaways.
- **AD-26:** the decision's trace target is its `TraceSessionId`.
- **AD-28:** `Render` is the only source of the all-clear. Conversation calls it after the guard (which runs in `Decide`).
- **AD-29:** Lane A is read-only, and the stubs stay.
- **AD-30:** Conversation stores both refs.
- **AD-31:** BridgeSink is the only place where bridge events become live events, it never fails, and it waits at most 1 s.
- **AD-32:** the reply is the `Outbound`; the page renders from `catalog.ts`.
- **AD-33:** one publisher per event type.
- **AD-4:** sessions only through `Ownership`.
- **Conventions:** Live events, Text OcuTalon sends, Enumerations (display words live only in the web app), Times, Angular, Tests, Fonts and icons (Lucide, ISC, under the existing notice).

No AC contradicts an AD's Rule. Rule 5: FR-12's 2 s is measured in D6. Task 0 measures the snapshot's new reads. No NFR is unmeasurable as worded.

**Decided in-stage** (small, reversible, within the intent):
1. **The strip reads `chat.message`, not the `decision` events.** `/state`'s `rail.decisions` holds only the 20 newest decide decisions, so a strip that joined the events would vanish on older replies after a reload. `chat.message` embeds the shown decision as the `decision` payload itself. The `decision` events feed `store().decisions` for Story 2.8.
2. **The shown decision** is the reply decision for a fallback reply, else the attention (triage) decision. This matches mockup B2 (a fallback reply shows Tell now, the flag and the reply's reason) and UX-DR66 (the strip appears when the attention decision lands).
3. **A fallback strip** is set by the reply or the decision being a fallback. It shows Tell now (FR-4: a fallback's outcome is Tell now) and the turn's reason first. When the reply is a fallback with no decision row (Conversation's own fallback: busy retries out, an error, no answer), there is no decision message, so no confidence, cost or Details are claimed.
4. **Details are the shown decision's own figures** ("Decision details"). The Cost row sets the decision beside the turn, and line 1 carries the turn's cost (the AC).
5. **The decision-message reference** is the decision's `ref`, the `DecisionRef` that its decision message carries in Visual Trace. The AC lists it apart from the trace target (`TraceSessionId`), and the mockup calls its format illustrative (S:602).
6. **`turn.step` carries `turnRef`.** The page cannot match the bridge's `decisionRef` to a turn: `Decide` allocates it, and `Conversation` learns it only from the answer. BridgeSink adds the running turn's `Ref`, and the store keys steps by it.
   - "The step's label only" means no other step content.
   - The bridge-context `ItemId` check keeps an untrusted `Intake` turn's steps off the user's turn. Inference: the gate calls `OnEvent` in the runner's job with the context set (AD-9, AD-6), and nothing can measure this before Lane A's gate exists. With no context, the running turn alone decides.
7. **`decision` events go out for every kind, but only for session owners.** `instance` decisions publish nothing: `Ownership.Rows` refuses `instance`, no session's snapshot rail holds them, and an incident card carries its own decision (Story 6.1).
8. **`Live.Publish` gains `lockWait`,** because its 5 s wait would break AD-31's 1 s. A dropped step label or `decision` event is harmless: `chat.message` carries the strip, and a reload rebuilds it.
9. **`TurnCost(turnRef)` takes its owner from the turn row** (`RefIndexOpen`), so the pinned one-argument call keeps working. The Usage rows are still owner-checked against that session. Its callers pass refs read through `Ownership` or held by `Conversation`, never request input (its doc comment says so).
10. **`RunCost.models` holds model ids**, and its consumer maps them with `Decision.ModelName`, so `Data` does not call `Live`.
11. **Check results in `HostData`** are the array `checks`, passed to `Render` unread. A check row is `{result, entry, finding, checkedAt}`. Conversation renders checks only on a usable reply.
12. **`whatFailed`.** `checks.notEverything*` need the text slot `whatFailed`, and `Render(results, *rows)` returns no slots. The page shows no sentence for those keys: the rows still show, the failed one included, and nothing reads as an all-clear. The slot's source is Story 5.7's to settle (Consumed-by).
13. **The fallback reason as a sentence** ("The model didn't answer within 60 seconds.") follows the mockup (S:566, S:482). It is the catalog text with a capital letter and a full stop.
14. **Number formats are en-US**, matching the English text and the server's renderer. The cost rule mirrors `Msg.Catalog.Cost` exactly, 0 → "<$0.0001" included.
15. **Duration** has one decimal under a minute (mockup "3.4 s"), and minutes and seconds from 60 s, in the style of the UX's countdowns.
16. **Check-row times are page times** (the browser zone): the rows are page elements, UX-DR123.
17. **Unknown values fail safe:** an unknown outcome shows no chip, and an unknown check result shows "Not checked".
18. **The chip's tooltip shows everywhere**, the empty panel included, as the AC says of every chip. It never holds the only copy: the strip's description and the empty panel's captions carry it.
19. **`Test.Bridge.Ext`'s comment** ("BridgeSink adds nothing") goes stale but stays true for its inputs. It is Lane A's to reword, and the lead may tell Lane A.

**Veto-window items for the lead** (ruled at spec validation: kept as planned, veto inbox U-28):
1. **Stored data:** `Turn` gains `CheckKey` and `CheckRows`, so a reply's check rows survive a restart. Without them, the snapshot would lose the rows.
2. **Composed page text** not written out in the UX:
   - "{label}…" and "{label} · 12 s" (spoken "{label} · 12 seconds");
   - durations "1 min 3 s";
   - the fallback-only strip (Decided 3).

   Each composes the UX's own strings and patterns.
3. **A new behaviour of a shared surface:** every outcome chip gains the pointer tooltip.

There is no new dependency, privilege or secret. The fixture user `ZzDecision` exists only on throwaways, with the user role, as 2.5's users do.

**Spine notes for the lead (Rule 20, light path):** written by the lead at spec validation: the "Live events" row and a new "HostData" Conventions row (its fields record Stories 2.6's and 5.7's criteria; `result` is `passed`, `failed` or `not_checked`).
- The Conventions row "Live events":
  - `chat.message` carries its turn's shown decision (the `decision` payload), the turn's cost (`TurnCost`), and its check key and rows;
  - `turn.step` carries the running turn's `turnRef`, and BridgeSink publishes it only for the session's running turn.
- A Conventions row "HostData": check results are `HostData.checks`, a JSON array that `Conversation` passes to `Checks.Render` unread. A check row is `{result, entry, finding, checkedAt}`. This is the cross-lane contract Story 5.7 builds to.
- AD-31 needs no amendment: its HostSink payloads are unchanged. AD-13 needs no amendment either: its amendment provides for new row kinds.

**Integration ACs (Rule 1).**
- The reply strip reads `chat.message.decision` and `turnCost`, which `FromRow` builds with `Ownership.Decision` and `TurnCost`. Observable: the strip and Details on a real throwaway (D1, D4, D8), and in `/state` (`TestStateChatDecision`).
- The turn indicator reads the `turn.step` events that the real `BridgeSink` publishes (D6, through `sinkEvent`).
- `/events` serves BridgeSink's `decision` events (D10).
- `Conversation` calls `Checks.Render`:
  - the real stub adds nothing (`TestStubRenderAddsNothing`);
  - through its seam, the rows reach Outbound and `chat.message` (`TestCheckRowsFromRender`) and the page (D7).
- No page consumer in this story renders the `decision` events in `store().decisions`. The first consumer will be Story 2.8 (the rail's Recent decisions).
- No consumer in this story reads `RunCost`. The first consumer will be Story 4.7 (the run total).

**Consumed-by:**
- **2.7:**
  - `Outbound.DecisionRef`, `CheckKey` and `CheckRows`, for `WebChatOut` and Telegram;
  - `Ownership.Decision`, for the tell-now reason (epics:1670);
  - `app-decision-strip`, with the decision's own cost, on notice cards.
- **2.8:**
  - the `decision` events (filter `kind === 'decide'` to match the snapshot);
  - `app-decision-details`, the formatters and BridgeSink's `OnEvent` dispatch, for `approval.*`.
- **2.9:** the strip's line-1 trace link, from `decision.traceHeaderId`.
- **2.12:** the strip and Details in the accessibility scan, and the WebKit and Firefox runs.
- **4.7:** the shape of `RunCost`; strips on the guide's replies.
- **5.7 (Lane A):**
  - `Render`'s rows in the `CheckRow` shape;
  - `HostData.checks`;
  - the `whatFailed` slot of `checks.notEverything*`, which has no path through `Render(results, *rows)`. The lead routes it.
- **6.1:** `app-fallback-flag` and the strip on incident cards.
- **16.9:** BridgeSink's `budget.capped`.
- **31.2 and 21.5:** BridgeSink's notices.

**Consumes:**
- 2.1: `Tooltip`, the tokens and the icons;
- 2.2: `Ownership`, the live store, `Decision.FromRow` and `ModelName`;
- 2.4: `Conversation`, the Turn's two refs, `DecideDouble` and `ConversationProbe`;
- 2.5: the reply element, `app-outcome-chip`, `catalog.ts`, `pageTime`, `seedTurns` and PANEL;
- 0.6: `HostSink`, `Bridge.Context` and the `Render` stub;
- 0.9: the catalog classes.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- The chat's decision is the `decision` payload class (`payloads.mjs` learns nested payload classes), not a copy.
- `Ownership.Decision` follows `Incident`, and the new kinds follow `decisions`.
- `Fixture.Decision` gains fields. `Fixture.Usage` follows it.
- `sinkEvent` follows `publishReminder`, and the `seedTurns` fields extend it.
- The strip reuses `app-outcome-chip` and the `Tooltip` directive (whose contract line widens).
- The indicator text moves into `chat-view.ts`'s `indicatorOf`.
- `catalog.mjs` reads Watch with its own `readEntries`.
- **One copy is planned:** `formatCost` mirrors the ObjectScript `Msg.Catalog.Cost`, because a page formatter and a server one cannot share code across languages. They share an oracle instead: `decision-view.test.mjs` holds `Test.Msg.Catalog.TestCost`'s 14 cases.

**Ledger (Rule 17).** This story owns no ledger entries. DW-66 is untouched: `Web.Api` has no change beyond its test.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message.
- **Throwaway commands** are `OCUTALON_RUN_TAG=e2s26i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`, one piece per call with `timeout: 600000`, ending with `teardown` on the same tag. A `LOCK busy` exit 75 is Epic 1's contention: wait and run it again.
- **Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (once) Task 0: `iris_execute_tests` `OcuTalon.Test.Web.Api` with `TestMeasureStateDecisions`, before and after the `FromRow` change; then remove it. Expected: the `MEASURE` lines, recorded here. If the class nears the cap on slot B, run `ci/iris.sh class OcuTalon.Test.Web.Api` on the throwaway instead and say so.
- (loop) `iris_execute_tests` on slot B, one class per message: `OcuTalon.Test.Core.BridgeSink`, `Test.Data.Ownership`, `Test.Core.ConversationTurns`, `Test.Live.Payloads`, `Test.Web.Api`, `Test.Msg.Contracts`, `Test.Data.Tables`, `Test.Core.Commands`, `Test.Contract.Ac` and `Test.Bridge.Ext` (Lane A's, unedited). Expected: all pass, with no `zz` fixture row left.
- (loop) One call each: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `node web/scripts/payloads.mjs --check`, `node web/scripts/tokens.mjs --check`. Expected: exit 0.
- (loop) `bash docker/tests/test-web-build.sh`. Expected: exit 0, within the style budget, and no inline script.
- (loop) One call each: `bash docker/tests/test-class-rules.sh` (with `ALLOW_UNCHECKED` unchanged), `test-boundaries.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-mock.sh`. Expected: exit 0.
- (loop) Throwaway: `build`, then `live sign-in` (D1-D10, C1-C15, shell, api), then `live demo-path`, then `teardown`.
  - Expected: each passes. The demo path prints `STEP 1 page: partly skipped, 2 passed, 3 skipped (Story 4.7: …)` with `floor 2 of 2 passed`. Teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway: `shard lane-b` (it runs `Test.Live.Publish` and `Test.Core.ConversationProduction`, which slot B may not), then `teardown`. Expected: every class passes.

**Planned mutations (Rule 19).** For each, the implement stage applies the mutation, observes red, restores a byte-identical tree (`git status --short` and `git diff --stat` unchanged) and records `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Decision event | `Recorded` publishes without its `Reasons` (the payload's `Reasons` cleared) | `TestDecisionRecordedPublishesTheDecision`; D10 |
| Owner check | `Recorded` opens the row with `Decision.RefIndexOpen` (no owner) | `TestEvalAndInstancePublishNothing`, `TestAnotherSessionsDecisionPublishesNothing` |
| Isolation | `decision` without `AND OwnerRef = ?` | `TestIsolationEveryRowKind` |
| Step | `Step` publishes no `TurnRef` | `TestTurnStepForTheRunningTurn`; D6 |
| Step guard | the context `ItemId` check removed | `TestTurnStepOfAnotherItem` |
| Lock | `Publish` called without `lockWait` | `TestNeverWaitsMoreThanASecond` |
| Never fails | `OnEvent` returns an exception's status | `TestNeverFailsItsCaller` |
| Step label | `indicatorOf` ignores `step` | `chat-view.test.mjs`; D6 |
| Turn cost on line 1 | the strip shows `decision.costUSD` | D1 ("$0.0003" for "$0.0008") |
| Newest | every strip shows one line | D2 |
| Fallback | confidence shown on a fallback; the reason after the reasons | `decision-view.test.mjs`; D3, C15 |
| Shown decision | `ShownDecisionRef` always gives the triage decision | `TestDecisionOnChatMessage`; D3 |
| Description | `aria-describedby` removed | D1 |
| Tooltip / focus | the chip without `appTooltip`; the chip with `tabindex="0"` | D5 |
| Details | opened as `.app-popover`; Esc does nothing | D4 |
| Cost row | "Decision · Turn" when equal | `decision-view.test.mjs`; D4 |
| Formats | the tier from the unrounded amount (0.99996 → "$1.000"); no token grouping | `decision-view.test.mjs`; D4 |
| TurnCost | `turnUsage` without the triage ref; without the owner check | `TestTurnCost`; D1 |
| RunCost | `since` ignored; the owner check removed | `TestRunCost` |
| Checks | `Checked` not called | `TestCheckRowsFromRender` |
| Checks on a fallback | `Checked` called before the fallback test | `TestNoCheckRowsWithoutResults` |
| All-clear from rows | the page shows "Everything I checked passed." when every row passed, whatever the key | D7 |
| Unknown result | `checkRowView` maps an unknown value to passed | `decision-view.test.mjs`; D7 |
| Reload | `ChatItems` uses a `FromRow` that skips the reads | D8, `TestStateChatDecision` |
| Watch catalog | `--watch` ignored | `catalog.test.mjs`; `catalog.mjs --check` |
| Nested payload | `tsType` maps a direct payload class to `unknown` | `payloads.test.mjs` |
| Outbound | `Tell` omits `DecisionRef` | `TestOutboundCarriesTheDecision` |

**Implement-stage records.**

Task 0, on slot B (build 154), through `Test.Web.Api` with a temporary `TestMeasureStateDecisions` (100 done turns, a triage and a turn decision and two usage rows each; `/state` three times through `StateJob`). The method is removed and `grep -rn MEASURE src/` finds none:
- `MEASURE state runs ms: 3.8 2.6 2.6 median 2.6 body length 23057` (the old `FromRow`)
- `MEASURE state runs ms: 205.4 18.5 17.9 median 18.5 body length 72557` (the new `FromRow`; the first run includes the statement preparation)
- The new median is 18.5 ms, far under the 1 s limit, so there is no `## Clarification Needed`. The seeding of the 500 rows took about 260 s on slot B.

Mutations (Rule 19). Each was applied, observed red, and restored; the tree was compared with `git status --short`, `git diff --stat` and a checksum of every changed file before and after. The browser rounds were run as 5 throwaway runs of `live sign-in` (tag e2s26i), several mutations per round, each mutation on a different D-test, and each test read separately:
- mutation: `Recorded` cleared the payload's `Reasons` before publishing -> `TestDecisionRecordedPublishesTheDecision` red; D10 red (the served event had no `reasons`)
- mutation: `Recorded` opened the row with `Decision.RefIndexOpen` (no owner) -> `TestEvalAndInstancePublishNothing` and `TestAnotherSessionsDecisionPublishesNothing` red
- mutation: the `decision` kind without `AND OwnerRef = ?` (binds `a`) -> `TestIsolationEveryRowKind` red (B read A's decision and A read B's)
- mutation: `Step` set no `TurnRef` -> `TestTurnStepForTheRunningTurn` red (and the turnRef check of `TestTurnStepOfAnotherItem`); D6 red (the label never replaced "Working")
- mutation: the context `ItemId` check removed from `Step` -> `TestTurnStepOfAnotherItem` red
- mutation: `Publish` called without `lockWait` -> `TestNeverWaitsMoreThanASecond` red (it waited 5.00 s)
- mutation: `OnEvent` returned an exception's status -> `TestNeverFailsItsCaller` red
- mutation: `indicatorOf` ignored `reply.step` -> `chat-view.test.mjs` red (3 tests); D6 red
- mutation: line 1 showed `decision.costUSD` instead of the turn's cost -> D1 red (it expects the turn's `$0.0008`)
- mutation: every strip showed one line (the newest-strip count ignored) -> D2 red (3 lines expected, 1 found)
- mutation: confidence shown on a fallback -> D3 red; the fallback sentence pushed after the reasons -> `decision-view.test.mjs` red (`reasonLines`). C15 stays green for the first: its fallback has no decision, so it has no confidence to show
- mutation: `ShownDecisionRef` always gave the triage decision -> `TestDecisionOnChatMessage` red; D3 red (its details name the attention decision, not the reply decision)
- mutation: `aria-describedby` removed from the strip -> D1 red (empty description)
- mutation: the chip without `appTooltip` -> D5 and C1 red; the chip with `tabindex="0"` -> D5 and C1 red
- mutation: the details wrapper given the class `app-popover` -> D4 red (6 found, 0 expected); the Esc handler removed -> D4 red (Esc did not collapse)
- mutation: the cost row showed "Decision ... Turn ..." when equal -> `decision-view.test.mjs` red; D4 red (soft assertion on the equal-cost turn)
- mutation: the tier taken from the unrounded amount (no re-tier of 0.99996 and 0.009996), and no token grouping -> `decision-view.test.mjs` red (`formatCost`, `formatTokens`, `tokensLine`); the missing grouping also makes D4 red (soft assertion on the tokens line)
- mutation: `TurnCost` passed the reply decision's Ref for both (no triage Ref) -> `TestTurnCost` red; D1 red (also D3, D4 and D8, which read the same cost); `turnUsage` without the owner check -> `TestTurnCost` red
- mutation: `RunCost` ignored `since` -> `TestRunCost` red; `runUsage` without the owner check -> `TestRunCost` red
- mutation: `Checked` not called -> `TestCheckRowsFromRender` red
- mutation: `Checked` called before the fallback test -> `TestNoCheckRowsWithoutResults` red
- mutation: the check sentence taken from the rows when every row passed, whatever the key -> D7 red
- mutation: `checkRowView` mapped an unknown result to passed -> `decision-view.test.mjs` red (2 tests); D7 red
- mutation: `ChatItems` used a `FromRow` with the decision and cost cleared -> `TestStateChatDecision` red; D8 red (the strips are gone after the reload; D1 to D7, which load from `/state`, are red too)
- mutation: the Watch catalog not read -> `catalog.test.mjs` red (14 tests) and `catalog.mjs --check` exit 1
- mutation: `tsType` mapped a direct payload class to `unknown` -> `payloads.test.mjs` red (3 tests) and `payloads.mjs --check` exit 1
- mutation: `Tell` omitted `DecisionRef` -> `TestOutboundCarriesTheDecision` red

Review-pass mutations (Rule 19), restored byte-identical and compared with `git status --short` and `git diff --stat`:
- mutation: `formatCost` rounded the binary double (`toFixed`, with the tier test on `toFixed`) -> `decision-view.test.mjs` red ("rounds a tie up on the decimal amount": 0.00015 showed "$0.0001", the server's "$0.0002")
- mutation: the fall-through arms of `ShownDecisionRef` returned the first ref alone (`Quit ..TurnDecisionRef`, `Quit ..TriageDecisionRef`) -> `TestShownDecisionRef` red (the reply with only the reply decision, the fallback with only the triage decision)
- mutation: `Holding` returned 0 whatever the events -> `TestDecisionRecordedPublishesTheDecision` red (the positive control, "the search finds the event that holds the decision's Ref")
- mutation: the Digest and Tell now meanings swapped in `CHIPS`, the Details button moved before the reasons, and the fallback-only strip dropped from `chatView` (`strip = decision !== undefined`), applied together in one `live sign-in` run and read from its JSON report -> D3 red (the group's description), D5 red (the Digest tooltip), D2 red (the button's place), C15 red (the fallback strip with no decision); the other 108 specs passed

**Shared surfaces:**
- the `chat.message` payload: `Test.Live.Payloads`, the api.spec rows (`toMatchObject`, additive), the restart row's snapshot comparison (a one-turn stub session, which has no decision and so stays unchanged), and `chat-view.test.mjs`;
- the `turn.step` payload and the store's `turnSteps` key (`live-store.test.mjs`);
- `Outbound` (`Test.Msg.Contracts`, `ConversationProbe`), `Turn` (`Test.Data.Tables`), and `Ownership`'s row-kind list (`TestIsolationEveryRowKind`, `Seed`, `ReadAll`, `TestRowsRefuses`);
- `TurnCost` and `RunCost` (`Test.Core.Commands.TestStubs`), and `Live.Publish`'s signature (`Test.Live.Publish`, whose default is unchanged);
- `Fixture.Decision`'s callers (`Test/Data/Ownership.cls:204,281-284,473`);
- `icon.ts`'s `IconName`, `catalog.ts`'s `PAGE_TEXTS`, `payloads.ts`, `WEB_INPUT_PATTERN` (`test-ci-changes.sh`, `constants.test.mjs`);
- the reply element's DOM: C2's log and every `chat.spec` assertion on a reply's text. Search for `replyOf(` uses outside `.text`;
- `app-outcome-chip` in the empty panel (C1's exact panel: the tooltip only exists on hover);
- `test-sign-in.sh`'s users and labels, and `iris.ts`'s `fixtureUser`;
- `Test.Bridge.Ext` (Lane A, must stay green).

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` methods create their rows through `Test.Data.Fixture` and remove them with `Fixture.Clean(refs)` naming only their own rows. `TestNeverWaitsMoreThanASecond` releases its lock-holding job in its own clean-up;
- `decision.spec` seeds its own turns on its own user. Only D2 depends on "newest", and its 2099 dates make it hold whatever ran before. D6 ends its running turn in a `finally`;
- C15 asserts only its own `clientId`.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The bridge's decisions and steps now reach the page, and every reply shows its decision strip.
- **Server.** `BridgeSink` publishes `decision` and `turn.step` events (session owners only, never fails, waits at most 1 s, `Live.Publish` gained `lockWait`). `Ownership` gained the row kinds `decision`, `turnUsage`, `runUsage` and `runDecisions` and the real `TurnCost` and `RunCost`. `Turn` keeps `CheckKey`, `CheckRows` and `ShownDecisionRef()`; `Conversation` calls `Checks.Render` through `RenderChecks` on a usable reply; `Outbound` carries `DecisionRef` and `CheckKey`; `chat.message` carries the shown decision, the turn cost and the check rows.
- **Page.** The decision strip (chip with tooltip, Fallback flag, confidence and the turn's cost, reason lines, inline Decision details), the indicator's step label, and the check rows. `catalog.ts` renders the three all-clear sentences from the check key only.
- Task 0 measured `/state` with the new reads at a median of 18.5 ms on slot B (old 2.6 ms), far under 1 s.

**Files changed.**
- Server: `Core/BridgeSink.cls`, `Core/Conversation.cls`, `Data/Ownership.cls`, `Data/Turn.cls`, `Live/Publish.cls`, `Live/Payload/ChatMessage.cls`, `Live/Payload/TurnStep.cls`, new `Live/Payload/Part/Cost.cls` and `Part/CheckRow.cls`, `Msg/Outbound.cls`.
- Server tests: new `Test/Core/BridgeSink.cls` and `BridgeSinkProbe.cls`; changed `Test/Core/Commands.cls`, `ConversationProbe.cls`, `ConversationTurns.cls`, `DecideDouble.cls`, `Test/Data/Fixture.cls`, `Ownership.cls`, `Tables.cls`, `Test/Live/Payloads.cls`, `Test/Msg/Contracts.cls`, `Test/Msg/Catalog.cls`, `Test/Web/Api.cls`.
- Page: new `decision-view.ts`, `decision-strip.ts`, `decision-details.ts`, `check-rows.ts`, `fallback-flag.ts`; changed `chat-view.ts`, `ocutalon-reply.ts`, `chat-panel.ts`, `outcome-chip.ts`, `icon.ts`, `live-store.ts`, `tooltip.ts`, and the generated `payloads.ts` and `catalog.ts`; generators `payloads.mjs` and `catalog.mjs`.
- Page tests and CI: new `decision-view.test.mjs`, `e2e/chat/decision.spec.ts`, `e2e/support/page.ts`; changed `chat-view.test.mjs`, `catalog.test.mjs`, `payloads.test.mjs`, `live-store.test.mjs`, `e2e/chat/chat.spec.ts` (C15), `e2e/support/iris.ts`, `docker/tests/test-sign-in.sh`, `docker/tests/test-ci-changes.sh`, `ci/units.sh`.

**Review findings.** 37 findings from the four layers: patches applied 8, deferred 2, rejected 27 (each with its reason in the Review Triage Log).
- Patches (4 medium, 4 low): `formatCost` rounds half up on the decimal amount, as the server does (the six ties are in both oracles); `TestShownDecisionRef`; the Digest and Tell now meanings in D3 and D5; `Holding`'s positive control; "Decision details comes last" in D2; the `Outbound.CheckRows` comment; the `decision-view.test.mjs` title; and C15's recorded red.
- Deferred (frontmatter `deferred:`): `TurnCost` after a retried broken session (medium, unverified), and an integration test from the bridge's emission into `BridgeSink` (medium, Lane A's emitter).
- Rejected with a reason: the `whatFailed` slot (DW-90, Story 5.7), the all-clear key beside failing rows (AD-28), a reload losing the step label, the tolerance windows the spec fixed, theoretical log failures, and the claims that contradict Decided 6, 9, 13 and 17.

**Follow-up review recommended: true.** Four medium findings were patched. The unverified risk: `formatCost`'s new `roundHalfUp` rounds on 15 significant digits, which is exact for an amount of up to six decimals (`Usage.CostUSD` has scale 6) and under about a billion dollars; no test covers an amount outside that.

**Verification performed (after the last patch).**
- Slot B (`ocutalon-slot-b`, build 154): both trees compile with 0 errors; `Test.Core.BridgeSink` 9/9, `Test.Data.Ownership` 16/16, `Test.Core.ConversationTurns` 36/36, `Test.Live.Payloads` 7/7, `Test.Web.Api` 27/27, `Test.Msg.Contracts` 6/6, `Test.Data.Tables` 6/6, `Test.Core.Commands` 4/4, `Test.Contract.Ac` 6/6, `Test.Bridge.Ext` 3/3 (unedited), and `Test.Msg.Catalog` 22/22 after its patch; no fixture row, event or log row is left.
- Web: `npm --prefix web test` 237/237, lint exit 0, the `catalog`, `payloads` and `tokens` generators `--check` exit 0, `test-web-build.sh` passes.
- Shell checks `test-class-rules.sh` (`ALLOW_UNCHECKED` unchanged), `test-boundaries.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `test-mock.sh` pass; `bash ci/checks.sh` passes.
- Throwaway (tag e2s26i): `build`, `live sign-in` 112 passed (D1 to D10 and C1 to C15 among them), `live demo-path` (`DEMO-PATH 1 of 6 steps ran (1 partly skipped), 11 skipped, 0 failed; floor 2 of 2 passed`), `shard lane-b` 32 classes passed, and `teardown` left nothing. Epic 1's `LOCK busy` (exit 75) was waited out and rerun.
- Mutations (Rule 19): the implement stage's 27 and the review pass's four are recorded in `## Verification`, each observed red and restored byte-identical.

**Residual risks.**
- `Test.Bridge.Ext`'s comment "BridgeSink adds nothing" is stale (Lane A's file, DW-91).
- The Lucide paths of `circle-dashed` and `circle-x` were written from memory of the upstream set (the repository holds no Lucide copy to compare them with); the review agreed with them from its own recall, and nothing tests the drawn shape beyond a stroke selector.
- The `decision` events feed `store().decisions` with no page consumer until Story 2.8; the live bridge end is a stub until Lane A's `Decide` emits (deferred above).
