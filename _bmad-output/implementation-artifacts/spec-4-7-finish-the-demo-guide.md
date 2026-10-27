---
title: 'Story 4.7: Finish the demo guide'
type: 'feature'
created: '2026-10-26'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The demo guide stops at step 2. Story 4.4 left steps 3 to 5 with no prompt and no action, there is no finish state and no Run again, and the Break the feed box never goes back to the attention style. The server's guide view also carries neither the current run's incident trace (for Open the trace) nor the run total (for the finish line). Two ledger entries are open:
- DW-215: `Guide.Compute` reads an incident's open variant whatever its state.
- DW-146: no spec signs its Visual Trace session out.

The REL-2 demo-path parts that this epic owns are still skipped.

**Approach:**
- **Server.** `Guide.Compute` reads the open variant only while the incident is open or closed (DW-215). The `guide.state` payload gains two members:
  - `trace`: the current run's incident trace session, a `TraceTarget`, whose `traceUrl` `TraceLink` adds;
  - `run`: the `Ownership.RunCost` total, present only once the guide is finished.
- **Page.**
  - The prompt bar gets steps 3 to 5: Go to Break the feed, the waiting line, the step 4 variants with Show me, and Open the trace (which writes `trace_opened`).
  - The finish state replaces the prompt bar, with the run total, the two links, More to try and Run again (which writes `run_again`).
  - The box takes the attention style again once the guide is finished.
- **Specs.**
  - REL-2: 01's three parts turn on. The watch, reminder and trace parts stay skipped, each naming the story whose AC turns it on.
  - DW-146 (measured in this plan): every spec case that opens a trace-application page signs its trace session out when it ends.

## Boundaries & Constraints

**Always:**
- **The page decides no progress (AD-12).**
  - What steps 3 to 5 show comes only from the server's guide view: `step`, `steps`, `step4Variant`, `breakFeed`, `finished`, `trace` and `run`.
  - The page only chooses which prompt and action to render for the selected step, and the selection rules of Story 4.4 stay.
  - No link URL is built on the page. Open the trace uses `guide.trace.traceUrl`, the whole-conversation link uses `trace-view.ts` `conversationUrl(store.chat)`, and Install uses `README_URL` from `web/src/app/links.ts`.
- **The payload is the full view (AD-12, AD-26).**
  - `trace` is a `Part.TraceTarget` {`traceHeaderId` = the current run's incident `TraceHeaderId`, `traceNamespace` = `$Namespace`}. The web layer adds `traceUrl` (`Web.TraceLink.Add`) wherever it serves the guide: `/state` and `/events` already do, and the marker answer gains it here.
  - `run` is set only while `finished` is 1, so the guide is not republished on every decision before the finish.
  - Both members are absent (not empty objects) when unset, so `Blank()` and every unfinished, incident-less view keep today's JSON.
- **The finish rule stands (P24, owner-fixed value 6).** `finished` = trace opened, an approved fix, and an incident that is resolved, or closed with no open variant (`Guide.cls:103-106`, unchanged). After a fallback, a no-fix or a rejection, step 4 keeps its hint and there is no finish text.
- **Writes (AD-1).**
  - The page writes only the two UI markers, through `POST /api/v1/guide/markers` (`trace_opened`, `run_again`).
  - Run again changes only `GuideState`: the conversation, watch, reminders and incidents stay as they are.
  - Go to Break the feed only focuses the box's button. It never presses it.
- **Speaking and focus.**
  - The page speaks only through `Announcer`, and this story adds no announcement. "Step {n} of 5" stays 4.4's `advance`, the finish is not announced (EXPERIENCE's list names none), and Run again is silent.
  - Focus moves only on the user's own action (Go to Break the feed, Show me), or through `focus-rule` when an update removed the focused element. When the finish replaces the prompt bar, that element is the finish's first line. When the prompt bar replaces the finish, it is the prompt bar's action, else its text, else the bar.
  - Show me is the one tab switch a user may cause (UX-DR80): `DeviceTabs.select('phone')`.
- **Trace links keep Story 2.13's rules.** On a local install, Open the trace and the whole-conversation link show the sign-in help popover first (`TraceHelp`). `trace_opened` is written only when a Visual Trace tab is actually opened: a press while the help is not needed, or the popover's Open Visual Trace.
- **Exact texts.**
  - The texts are verbatim from the story's AC and EXPERIENCE (Design Notes, "Texts"), with straight ASCII quotes.
  - In code, U+00B7 is written `·` and U+2197 (↗) is written `↗` (Rule 14).
  - The prompts of steps 3 to 5 are shown in quotes, like steps 1 and 2 (DESIGN D:763, states mockup ST:672-675).
- **Styles and floor rules.**
  - Use DESIGN tokens only: `body-sm` and `ink-muted` with tabular figures for the run total, `button-primary` and `button-secondary`, and the `link` style (always underlined).
  - No `transition`, no fixed `height`, no `sticky`, no `IntersectionObserver`; width queries only through `LAYOUT_QUERIES`.
- **The demo-path specs follow Flow 1's web route on the CI mock or stay skipped (REL-2, AD-29).**
  - A part that depends on Lane A's unmerged incident path, or on Epic 8's stubbed reminders, is never faked with fixtures.
  - Its skip names the story whose AC turns it on.

**Never:**
- **Files we don't change** (calling or reading them is fine):
  - `docker/tests/**`: contended (Epic 15), `test-demo-path.sh` included;
  - `.github/workflows/**`, `src/bridge/**`;
  - `web/src/app/live/**`, contended (Epic 16), except the regenerated `payloads.ts`, and only once the orchestrator rules (Auto Run Result, `## Clarification Needed`);
  - `ci/mock/**`: no scenario or mock change;
  - `Core/IncidentManager*`, `Watch/**` (Lane A);
  - `Data/Ownership.cls`: `RunCost` is used as it is.
- **Out of scope:**
  - the "Use the same bridge in your own production ↗" link (Story 31.3);
  - an `expired` step 4 text (Design Notes, Decided 9);
  - the online demo's allowance, which sets prompt buttons to `aria-disabled` (Story 16.x);
  - a step 4 action in the rejected, fallback and no-fix variants (Decided 4);
  - turning the watch, reminder or trace parts of the demo path on, and any change to the mock that would make the guide's watch prompt an Act decision (Story 11.1);
  - un-stubbing Story 2.13's stubbed trace cases.
- **No canned outcome.** No fixture stands in for an incident on the demo-path stack, and no spec asserts a fallback decision as the demo path's watch step.
- **The sign-in unit gains no test case.** `guide/guide.spec.ts` and the DW-146 call sites change assertions and add the sign-out call only, and `live sign-in` must stay at about its 461-463 s (see Verification).

## I/O & Edge-Case Matrix

**Conventions:**
- `S` is the signed-in session, with demo mode on.
- `V` is the server's guide view (`/state.guide`, else the latest `guide.state`).
- `T(x)` is the exact text `x` under Design Notes, "Texts".
- "Selected" is the user's step selection (4.4), which defaults to the current step.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1. Step 3 | step 3 selected; V's `breakFeed.stage` is not `sending`, `waiting` or `still_waiting` | **Prompt bar:** "Next:", the quoted T(promptBreakFeed) and a primary button T(goToBreakFeed).<br>**Press:** focus moves to the box's Break the feed button (`app-break-feed-box app-server-button button`). Nothing is pressed: no `POST /demo/break-feed` | **The box's button is inactive** (`aria-disabled`): it still takes focus (4.4's server button) |
| 2. Step 3 waiting | step 3 selected; `breakFeed.stage` is `sending`, `waiting` or `still_waiting` | **Prompt bar:** only T(waiting), with no "Next:", no quotes and no button (ST:702-704).<br>**`no_notice` or `notice_arrived`:** row 1's prompt again | none |
| 3. Step 4 | step 4 selected; `step4Variant` is `paired` or `unpaired` | **Prompt bar:** the quoted T(approvePaired) or T(approveUnpaired), and a primary button T(showMe).<br>**Press:** `DeviceTabs.select('phone')`, then focus on the newest phone message whose `approvalRef` names an approval the store holds as `pending` (`.notification[data-key]`, `tabindex="-1"`); with none, focus on the phone's feed region. Never a button inside it | none |
| 4. Step 4 variants | `step4Variant` is `rejected`, `fallback` or `no_fix` (step 4 current, `finished` 0) | **Prompt bar:** the quoted T(rejected), T(fallback) or T(noFix), with no action button.<br>**Step 5:** selectable, showing row 5 (fallback and no fix have a `trace`) | none |
| 5. Step 5 | step 5 selected; V has `trace.traceUrl` | **Prompt bar:** the quoted T(promptTrace), and the link T(openTrace).<br>**The link:** styled `button-primary`, with the `external-link` icon and a hidden " (opens in a new tab)"; `href` = `traceUrl`, `target="_blank"`, `rel="noopener noreferrer"`.<br>**A press while the help is not needed:** opens the tab, then `POST /guide/markers {"marker":"trace_opened"}`.<br>**Help needed** (local install, not seen): T(signInFor) as its name and the popover first. The popover's Open Visual Trace opens the tab and writes the marker | **The marker POST fails:** no text; step 5 stays not done and a later press writes it again |
| 6. Step 5, no trace | step 5 selected; V has no `trace` (no incident in the current run) | The quoted T(promptTrace) only. The prompt text is the focusable part (`tabindex="-1"`, as 4.4) | none |
| 7. Finish | `finished` 1 | **Replaces the prompt bar:**<br>- T(finishDone) as the first line (`tabindex="-1"`);<br>- the run total (row 8) when V has `run`;<br>- the link T(conversationLink) with a hidden ↗ (`app-trace-link`, URL `conversationUrl(store.chat)`) when there is one;<br>- the link T(installLink) with a hidden ↗ to `README_URL`;<br>- T(moreToTry);<br>- a secondary T(runAgain) (`app-server-button`).<br>**Links:** each named "... (opens in a new tab)", ↗ in `aria-hidden`, underlined.<br>**Step list:** stays.<br>**Box:** attention style.<br>**Focus:** the first line when the update removed the focused element (Open the trace, or the prompt bar's parts).<br>**Announcement:** none | **No turn with a traceUrl:** no conversation link.<br>**No `run`:** no run-total line |
| 8. Run total | V's `run` | **Format:** "This run: {n} {decision(s)} · {tokens} {token(s)} · {cost} on {models}."<br>- `n` and `tokens` use en-US separators (`formatTokens`);<br>- cost through `formatCost`;<br>- singular at exactly 1.<br>**Models:** none drops " on {models}"; two read "A and B"; three or more read "A, B and C".<br>**Example:** {3, 9850, 0.0041, ["Claude Haiku 5.5"]} → "This run: 3 decisions · 9,850 tokens · $0.0041 on Claude Haiku 5.5." | **costUSD 0:** "<$0.0001" (`formatCost`'s rule) |
| 9. Run again | press T(runAgain) | **The press:** `POST /guide/markers {"marker":"run_again"}`, busy until the answer.<br>**The 200 answer's view:** used at once, until the next live guide view arrives; the prompt bar replaces the finish at V's new current step (3 when the watch and reminder still count).<br>**Focus:** that step's action.<br>**Silent:** no announcement; `runEpoch` rises; the session's data is unchanged | **An error answer:** no text, and the finish stays (Break the feed's rule).<br>**No answer in 10 s:** the server button's notice |
| 10. Trace target | `Compute(S)` | **Set:** `trace` = {`traceHeaderId`: the current run's noticed Orders incident's `TraceHeaderId`, `traceNamespace`: `$Namespace`}.<br>**Absent:** no incident in the window; an incident noticed before the run started; `TraceHeaderId` empty or 0.<br>**Served:** `/state`, `/events` and the marker's 200 answer carry `trace.traceUrl` = `TraceLink.Url(headerId, namespace)` | none |
| 11. Run total (server) | `Compute(S)` with `finished` 1 | **`run`:** `decisions` = `RunCost.decisions`; `tokens` = `inputTokens` + `outputTokens`; `costUSD`; `models` = `Live.Payload.Decision.ModelName(id)` of each `RunCost.models` id, in order of first use.<br>**`since`:** `GuideState.RunStartedAt`, where "" counts the whole session (RunCost's convention).<br>**`finished` 0:** `run` absent | **A RunCost read fails:** Compute throws (its existing rule), and the callers answer 500 or warn as today |
| 12. DW-215 | incident `State` ≠ `open`/`closed` with `OpenVariant` in {`rejected`, `fallback`, `no_fix`} | **Variant:** the open variant is ignored, so `step4Variant` is `paired` or `unpaired`.<br>**Resolved, approved fix, trace opened:** `finished` 1, `step` 5, `step4Variant` `unpaired`.<br>**Awaiting approval:** `unpaired`, `step` 4.<br>**Open or closed with a variant:** keeps it (closed after a rejection: `rejected`, `finished` 0, step 4).<br>**Invariant:** `finished` 1 never comes with a variant in VARIANTS or with `step` 4 | none |
| 13. Box style | V | **Secondary:** step 5 current and `finished` 0.<br>**Attention:** active otherwise (`finished` 1 included).<br>**Inactive:** unchanged.<br>**"Next step":** unchanged (step 3) | none |
| 14. DW-146 | an e2e case that requested a page of `/ocutalon/trace/` while signed in | **When the case ends:** `signOutTrace` sends `GET /ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?IRISLogout=end` with the case's own cookies (`page.request` or its own `request`).<br>**V1:** the LINKS user's CSP sessions in `%SYSTEM.License:UserList` (`CSPCon`) return to the count read before the case | **`irisScript` prints nothing** (the licence is exhausted, so terminals are refused): V1 fails, saying so |
| 15. Demo path | the fresh demo-path stack | **01:** its three parts pass, tagged `@floor`.<br>**Re-pointed:** 02's two `4.7` parts to `11.1`; 03 to `8.4`; 06 to `11.1`.<br>**Summary:** STEP 1 passed, 6 of 6; floor 7 of 7; nothing else changes | none |

</intent-contract>

## Code Map

**Server: the guide (Lane B):**
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls`:
  - `:18-25` `ANSWERED`, `APPROVEDFIX`, `VARIANTS`;
  - `:43-150` `Compute`, the one derivation:
    - `:49-55` the state: epoch, `RunStartedAt`, `TraceOpened`;
    - `:71-74` the run window;
    - `:76-87` the run's incident (`NewestIncident`) and its approvals;
    - `:91-92` the variant read whatever the state (DW-215);
    - `:103-106` `finished`;
    - `:108-115` `step`;
  - `:154-157` `Blank`; `:189-209` `View`, which builds the payload.
- `src/ocutalon/cls/OcuTalon/Live/Payload/GuideState.cls:1-26`: the payload. Append `Trace` and `Run`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/TraceTarget.cls`: {`TraceHeaderId`, `TraceNamespace`}. It is shared and owned by Lane B. `payloads.mjs` already gives its interface `traceUrl?`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/Cost.cls`: the precedent part for a cost (`FromObject` of a TurnCost or RunCost object). `GuideRun` follows its shape.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:88-100` `RunCost(sessionRef, since, .sc)`. It returns {`decisions`, `inputTokens` (cache tokens included, AD-20), `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `costUSD`, `models`: ids in order of first use}, and "" for `since` counts everything. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Incident.cls:65-66` `TraceHeaderId`, the incident's own trace session (AD-26). Lane A's table, read through Ownership.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls` `ModelName(id)`: the display name, as `Web.Api.ModelName` (`Api.cls:666-669`) delegates.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls:119-149` `RefreshGuide`: computes, compares the JSON with the last event and publishes on change. Unchanged.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `:407-431` `GuideMarkers`, whose answer has no `TraceLink.Add` today (add it);
  - `:475-523` `StateBody`: `guide` `:518`, `TraceLink.Add(body)` `:520-521`;
  - `:689-690` `EventsBody` adds trace URLs to events.
- `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls:58-60` `Add`: it recurses and adds `traceUrl` to any object that has `traceHeaderId` and `traceNamespace`.

**Server tests:**
- `src/ocutalon/cls/OcuTalon/Test/Demo/Guide.cls`:
  - `:192` `TestVariant`;
  - `:248` `TestFinished`: its cases hold unchanged, and "resolved, rejected, rejected" stays `finished` 0 because no request is approved;
  - `:272` `TestCurrentStep`;
  - `:86` `TestBlankEqualsCompute`;
  - the helpers `Finishing`, `IncidentSession`, `View` and `Assert`, with `Test.Demo.GuideProbe` for the clock and Telegram seams.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `Check` `:65`, `Incident` `:81` (fields by name, `TraceHeaderId` included), `Usage` `:139`, `GuideState` `:167`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`: `:2` the header; `:696-706` the GuideState props pin; `:850-863` the Guide parts.
- `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls`: `:53` `TestTraceOpened`, `:75` `TestRunAgain`, `:170` `TestStateCarriesTheGuide`. It is an existing file in contended `Test/Web/**`, so it takes one self-contained block appended at the end, reported.

**Page (Lane B):**
- `web/src/app/guide/guide-view.ts`:
  - `:22-40` `GUIDE_TEXTS`;
  - `:88-93` `PromptView`;
  - `:96-106` `GuideView`;
  - `:108-114` `promptOf` (steps 1 and 2 only);
  - `:120-142` `guideView`;
  - `:148-157` `advance`; `:163-171` `followSelection`, both unchanged.
- `web/src/app/guide/demo-guide.ts`:
  - `:16-43` `FOCUS_KEY`, `BREAK_FEED_BUTTON`, `PROMPT_KEYS` and `FOCUS_RULE`;
  - `:115-126` the prompt bar's template;
  - `:129` the box;
  - `:262-302` the prompt styles;
  - `:374` `view`; `:414-419` `send`; `:422-429` `follow`.
- `web/src/app/feed/break-feed-view.ts:146-190` `boxView`: style `:156` (`current === 5 ? 'secondary' : 'attention'`), `nextStep` `:188`.
- `web/src/app/feed/break-feed-api.ts:1-31`: the guide-owned press (veto U-84; DW-231 moves it in Story 10.3). The marker call goes into `ApiClient` instead (Decided 11).
- `web/src/app/shared/trace-link.ts`:
  - `app-trace-link`: "Trace", the `external-link` icon and the hidden suffix;
  - while `TraceHelp.needed()`, `aria-label` = `signInName` and `aria-haspopup="dialog"`, and a press shows the popover;
  - the popover's `<a class="button button-primary">` opens the tab;
  - `press` and `close`.
- `web/src/app/shared/trace-view.ts:14-25` `TRACE_TEXTS`; `needsSignInHelp`; `:45-53` `conversationUrl(chat)`.
- `web/src/app/devices/device-tabs.ts:14-26` `DeviceTabs.select(tab)`.
- `web/src/app/phone/phone-view.ts`: `:25-39` `phoneOf`; `:41-47` `pendingApproval`, which becomes a use of the new `pendingRef`.
- `web/src/app/phone/simulated-phone.ts`: `:40` the feed (`.feed`, `role="region"`, `tabindex="0"`); `:47` a notification (`.notification`, `tabindex="-1"`, `[data-key]`).
- `web/src/app/chat/decision-view.ts`: `:72-85` `formatCost`, `:87-92` `formatTokens`. Reuse both.
- `web/src/app/links.ts:5` `README_URL` (the spine's README link row, L927).
- `web/src/app/api/api-client.ts:28-56` and `api-types.ts:32-50`: shared by entry, Epic 4's own entries only.
- `web/src/app/shared/server-button.ts` (`app-server-button`): busy, keeps focus, the 10 s notice. It gives Run again its states.
- `web/src/app/live/payloads.ts:238-247` `GuideStatePayload`: generated, in contended `live/**`. It changes only by `node web/scripts/payloads.mjs`, after the ruling.

**Source-scanning unit tests** (`web/scripts/`, run with `node --test`):
- `guide-view.test.mjs`, `break-feed-view.test.mjs`, `phone-view.test.mjs`, `trace-view.test.mjs`;
- `ux-strings.test.mjs`: `IMPORTED`, `SOURCES` and the ASCII-only rule (ASCII plus U+2026 and U+00B7 today);
- `announce-focus-sources.test.mjs`: speakers, `FOCUS_CALLS`, the `afterNextRender` allow-list and the `keepFocus` hosts;
- `floor-sources.test.mjs` (no new key handler); `page-safety.test.mjs`.

**E2E:**
- `web/e2e/guide/guide.spec.ts`, chromium project, so `live sign-in`. Fixture snapshots (`changeSnapshot`) and injected events (`liveEvents`).
  - `:189-232` Q2 asserts that "steps 3 to 5 hold no prompt", and `:535`. Both become assertions of the new prompts; no case is added.
- `web/e2e/floor/guide.spec.ts`, `live floor`:
  - M3 `:159`, whose `:187` asserts "step 3 holds no prompt yet": update it;
  - M6 `:203`; M4 `:230` (a real press);
  - the seed helpers `seedWatch` `:145` and `seedStretch` `:152`.
- `web/e2e/support/guide.ts` (`ORDERS`, `publishWatchProgress`, `dropBreakFeed`, `settleBatch`).
- `web/e2e/support/iris.ts`: `irisScript` and `chk`, `seedDecision` `:477`, `seedApproval` `:648`, `seedCheck` `:697`, `seedReminder` `:784`, `seedIncident` `:811`.
- `web/e2e/support/devices.ts`: `publishFixtureEvent` `:16`.
- `web/e2e/support/trace.ts`: `TRACE_PAGE` `:13`, `postTurn` `:48`, `signInToTrace` `:60`, `openTrace` `:71`, `drawnMessages` `:88`. Add `signOutTrace` and `traceSessions`.
- `web/e2e/trace/links.spec.ts`:
  - `opensTab` `:136-141` (real tabs: V1 `:170`/`:205`, V2 `:241`, V8 `:593`, and the others that call it);
  - `stubTraces` `:144-146`, the stubbing pattern that 4.7's own floor cases copy for their tab.
- Other real trace-application requests:
  - `web/e2e/trace/trace.spec.ts` `:128-181` (T1-T4, `openTrace`);
  - `web/e2e/sign-in/shell.spec.ts` `:155-167` (row 10; row 11 `:171-194` already signs out);
  - `web/e2e/sign-in/sign-in.spec.ts:71`, `web/e2e/api/api.spec.ts:352`, `web/e2e/session/session.spec.ts` (its `TRACE` uses).
- `web/e2e/demo-path/`:
  - `01-page.spec.ts:116-118`, `02-watch.spec.ts:4-5`, `03-reminder.spec.ts:4`, `06-trace.spec.ts:4`;
  - `not-built.ts` (the skip text "Story N.M turns this on");
  - `web/scripts/demo-path-summary.mjs` (`STORY` pattern `:30`; `@floor` must pass).

**Footprint (Rule 11), for the spec gate:**
- **Inside Epic 4's footprint:**
  - `Demo/Guide.cls`, `Test/Demo/Guide.cls`, `Web/Api.cls` (Epic 4's own `GuideMarkers`);
  - `web/src/app/{guide,feed,phone}/**`; `web/e2e/demo-path/0{1,2,3,6}-*.spec.ts`;
  - Lane B's web home: `web/src/app/{devices,shared}/**`, `web/scripts/*.test.mjs` and `web/e2e/{floor,guide,trace,sign-in,api,session,support}/**`.
- **Outside, not contended** (a footprint extension):
  - `Live/Payload/GuideState.cls`, `Live/Payload/Part/GuideRun.cls` (new);
  - `Test/Live/Payloads.cls`.
- **Shared by entry:** `web/src/app/api/{api-client,api-types}.ts`.
- **Contended:**
  - `Test/Web/GuideApi.cls`: one block appended at the end, reported;
  - `web/src/app/live/payloads.ts`: generated; needs the orchestrator's ruling (Auto Run Result).

## Tasks & Acceptance

**Execution** (in dependency order):

*Server*
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Part/GuideRun.cls` (new, `%RegisteredObject`, `%JSON.Adaptor`). Its doc: "The current run's total for the guide's finish state (AD-12, AD-20); Lane B publishes it in guide.state". Properties, in order:
  - `Decisions As %Integer(%JSONFIELDNAME = "decisions")`;
  - `Tokens As %Integer(%JSONFIELDNAME = "tokens")`;
  - `CostUSD As %Numeric(%JSONFIELDNAME = "costUSD", SCALE = 6)`;
  - `Models As list Of %String(%JSONFIELDNAME = "models", MAXLEN = 128)`.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/GuideState.cls`: append, after `TelegramRow`:
  - `Property Trace As OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME = "trace")`, with the doc "The trace step's target: the trace session of the incident noticed in the current run (AD-26); absent before one";
  - `Property Run As OcuTalon.Live.Payload.Part.GuideRun(%JSONFIELDNAME = "run")`, with the doc "The current run's total, only while the guide is finished".

  Each property is on one line from the first column (the `payloads.mjs` grammar).
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Guide.cls` (rows 10, 11 and 12):
  - **DW-215:** the variant is taken from `incident.OpenVariant` only when `incident.State` is `open` or `closed`. Add `Parameter VARIANTSTATES = "open,closed"`, documented as "the incident states whose open variant step 4 shows; the open variant is stored beside the state and means nothing in another".
  - **Trace:** when the run's `incident` has `TraceHeaderId > 0`, build a `Part.TraceTarget` with `TraceNamespace = $Namespace`.
  - **Run:** only when `finished`, `cost = Ownership.RunCost(sessionRef, epochStart, .sc)` with `..Check(sc)`, then a `GuideRun` filled as row 11 says.
  - **`View`:** gains two trailing arguments `trace` and `run`, set when they are objects. `Blank()` passes neither.
  - Update the class doc (the trace target, the run total and the variant rule).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` `GuideMarkers`:
  - The answer becomes `Set answer = ..PayloadObject(guide)`, then `TraceLink.Viewer(.viewer)` and `TraceLink.Add(answer, .viewer)`, then `Write answer.%ToJSON()`.
  - Doc: "the guide view that /state carries, with its trace URL".
- [ ] `web/src/app/live/payloads.ts`: run `node web/scripts/payloads.mjs`, which adds the `GuideRun` interface and `trace?: TraceTarget; run?: GuideRun;` to `GuideStatePayload`. **Only once the orchestrator rules** (Auto Run Result); without that ruling this task and every page task that reads `trace` or `run` wait.

*Server tests*
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/Guide.cls` (header lines updated):
  - **`TestTrace`** (row 10):
    - no incident: no `trace`;
    - the run's incident with `TraceHeaderId` 4321: `trace` = {4321, `$Namespace`};
    - an incident noticed before the run's `StartedAt`: no `trace`;
    - `TraceHeaderId` "": no `trace`;
    - the JSON of a blank session equals `Blank()`'s.
  - **`TestRunTotal`** (row 11):
    - not finished: no `run`;
    - finished, with two fixture decisions and Usage rows recorded after `RunStartedAt` (input 9000, output 850, cost 0.0041, model `claude-haiku-5-5`) and one Usage row before it: `run` = {2, 9850, 0.0041, ["Claude Haiku 5.5"]}, the earlier row not counted;
    - `RunStartedAt` "": every row counted.
  - **`TestVariantFollowsState`** (row 12, DW-215):
    - `resolved`, `awaiting_approval` and `fixing`, each with `OpenVariant` `rejected`, give `unpaired`;
    - resolved with variant `rejected`, an approved request and trace opened: `finished` 1, `step` 5;
    - closed with `rejected`: `rejected`, `finished` 0, `step` 4 with the other steps done;
    - for every fixture state of the cases above, `finished` 1 implies a variant not in VARIANTS and `step` 5.

  `TestFinished` and `TestVariant` stay as written.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`:
  - GuideState's props gain `"Trace": "OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME=trace)"` and `"Run": "OcuTalon.Live.Payload.Part.GuideRun(%JSONFIELDNAME=run)"`;
  - a pin for `OcuTalon.Live.Payload.Part.GuideRun`;
  - the header line: "Story 4.7 adds the part GuideRun".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls`: one self-contained block appended at the end (contended, reported).
  - `TestMarkerAnswerTrace`: a session whose run has a fixture incident with `TraceHeaderId`; the marker's 200 answer carries `trace.traceUrl` = `TraceLink.Url(...)`.
  - `TestStateGuideTrace`: `/state`'s `guide.trace.traceUrl` is the same.

*Page*
- [ ] `web/src/app/shared/trace-view.ts`: `TRACE_TEXTS` gains `signInFor: '{label} (shows sign-in help first)'`. Story 2.13's `signInName` stays for the default "Trace" link.
- [ ] `web/src/app/shared/trace-link.ts` (Rule 2: extend, don't copy). The defaults keep today's markup, so every existing trace link and spec stays as it is.
  - **New inputs:**
    - `text` (default `TRACE_TEXTS.trace`);
    - `appearance`: `'link'` (today's), `'button'` (`button button-primary`, the text, then the `external-link` icon), or `'arrow'` (an underlined link, the text, then `<span aria-hidden="true"> ↗</span>`).
  - **Name:** in every appearance the hidden " (opens in a new tab)" stays. While the help is needed, `aria-label` is `signInName` for the default text, else `signInFor` with `{label}` = `text`.
  - **New output `opened`:** it emits after a press that opens the tab (the help not needed) and after the popover's Open Visual Trace.
- [ ] `web/src/app/phone/phone-view.ts`: add `pendingRef(list, approvals): string | undefined`, the ref of the newest message whose `approvalRef` the store holds as `pending`. `pendingApproval` becomes `pendingRef(...) !== undefined` (Rule 2).
- [ ] `web/src/app/api/api-types.ts` and `web/src/app/api/api-client.ts` (Epic 4's own entries):
  - `type GuideMarker = 'trace_opened' | 'run_again'`;
  - `postGuideMarker(marker): Observable<GuideStatePayload>`, which is `POST ${BASE}/guide/markers {marker}`, 200 with the guide view.
- [ ] `web/src/app/feed/break-feed-view.ts` `boxView`: the style is `current === 5 && view.finished !== true ? 'secondary' : 'attention'` (row 13). Update the doc.
- [ ] `web/src/app/guide/guide-view.ts`:
  - **`GUIDE_TEXTS`:** gains every string under Design Notes, "Texts".
  - **`PromptView`:** gains `action: 'send' | 'goToBreakFeed' | 'showMe' | 'openTrace' | 'none'`, and `waiting?: true` for row 2's line.
  - **`promptOf(step, view)`:** gives rows 1 to 6. Step 3 waits while `breakFeed.stage` is `sending`, `waiting` or `still_waiting`. Step 4 shows the variant's text, with Show me only for `paired`/`unpaired`. Step 5 gives `openTrace` only with `view.trace?.traceUrl`.
  - **`GuideView`:** gains `finish?: { runTotal?: string }`, set when `view.finished === true` (the component adds the links). `guideView` omits `prompt` when `finish` is set.
  - **`runTotalText(run)`:** row 8, with `formatTokens` and `formatCost` from `chat/decision-view.ts`.
  - **The module doc:** steps 3 to 5 and the finish are 4.7's.
- [ ] `web/src/app/guide/demo-guide.ts` (rows 1-9):
  - **Prompt bar, steps 3 to 5:**
    - Go to Break the feed: `button-primary`, `data-guide-focus="action"`. It focuses `BREAK_FEED_BUTTON` in the host.
    - Show me: `button-primary`. It calls `DeviceTabs.select('phone')`, then, in `afterNextRender`, focuses `app-simulated-phone .notification[data-key="<pendingRef>"]`, else `app-simulated-phone .feed`. `pendingRef` comes from `phoneOf(snapshot, store)` and `store.approvals`.
    - Open the trace: `<app-trace-link appearance="button" [text]="texts.openTrace" [url]="trace.traceUrl" (opened)="mark('trace_opened')" data-guide-focus="action">`.
    - The waiting line: `.prompt-text`, unquoted, with no "Next:".
  - **The finish** (when `model().finish`) in place of the `.prompt` div:
    - `<p class="finish-done" tabindex="-1" data-guide-focus="finish">`;
    - the run total `<p class="run-total">` (`body-sm`, `ink-muted`, `font-variant-numeric: tabular-nums`);
    - the conversation link `app-trace-link appearance="arrow"` (when `conversationUrl(store.chat)`);
    - the install link `<a class="link" [href]="readme" target="_blank" rel="noopener noreferrer">`, with its ↗ `aria-hidden` and the hidden suffix;
    - More to try;
    - Run again: `app-server-button variant="secondary" [action]="runAgain"`, `data-guide-focus="runAgain"`.
    - Layout and weights follow DESIGN D:767 and EXPERIENCE E:589-594 over the mockups, as the resolutions at epics.md:470-471 say. No fixed height.
  - **The held answer:** `mark(marker)` posts through `ApiClient.postGuideMarker` and keeps its 200 answer as the guide view until the next live guide view (a new `store.guideState` or snapshot). `view` is the held answer, else 4.4's `guideOf`. Errors are swallowed with no text. `runAgain` returns the post's observable for the server button.
  - **`FOCUS_RULE`:**
    - `action`, `text` and `bar` hand focus to the first of `PROMPT_KEYS`, else to `finish`;
    - `finish` and `runAgain` (and the finish links) hand it to `PROMPT_KEYS`.

    The rule's doc and the class doc are updated.
- [ ] Unit tests (`web/scripts/`):
  - **`guide-view.test.mjs`:** `promptOf` for rows 1-6 (every variant; the waiting stages; a trace or none); `guideView` with `finished` (`finish` set, no `prompt`); `runTotalText` (row 8: the example, singulars, 0 cost, no model, two and three models).
  - **`break-feed-view.test.mjs`:** row 13.
  - **`phone-view.test.mjs`:** `pendingRef` (newest pending wins; answered or unknown approvals give undefined; `pendingApproval` unchanged).
  - **`trace-view.test.mjs`:** `signInFor` filled.
- [ ] Shared-surface unit tests, each edited with its reason:
  - **`ux-strings.test.mjs`:** `IMPORTED` keeps `GUIDE_TEXTS`; `SOURCES` gains every new string (`ux` for the AC and EXPERIENCE ones, `ruled` for V1's); the character rule also allows U+2197, with the reason "UX-DR47's ↗, hidden from assistive technology".
  - **`announce-focus-sources.test.mjs`:** `FOCUS_CALLS` gains `demo-guide.ts`'s exact new count, and the `afterNextRender` allow-list gains `demo-guide.ts` (Show me). No new speaker.

*E2E*
- [ ] `web/e2e/support/trace.ts` (DW-146):
  - `signOutTrace(api: APIRequestContext)`: `GET /ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?IRISLogout=end`. It ends the context's whole sign-in group, and the doc says so.
  - `traceSessions(user)`: the user's `CSPCon` from `%SYSTEM.License:UserList` through `irisScript`, matching `UserId` = `<user>@...` without regard to case, 0 when absent. It fails "the licence is exhausted: irisScript was refused" when the script prints no line.
- [ ] DW-146 call sites (row 14; assertions unchanged otherwise):
  - **`web/e2e/trace/links.spec.ts` and `web/e2e/trace/trace.spec.ts`:** `test.afterEach(({ page }) => signOutTrace(page.request))`.
  - **V1, the pin:** read `traceSessions(LINKS)` before opening its first tab; after its last tab and `signOutTrace`, expect the same count (polled up to 5 s).
  - **The other real trace-application requests:** `web/e2e/sign-in/shell.spec.ts` row 10 (`:155-167`), `web/e2e/sign-in/sign-in.spec.ts:71`, `web/e2e/api/api.spec.ts:352` and the `web/e2e/session/session.spec.ts` cases that request `TRACE` while signed in end with `signOutTrace` on the context that made the request.
  - **Leave alone:** row 11 and S7, which already sign out.
  - **Find every site with:** `grep -rn "ocutalon/trace/\|TRACE_PAGE\|openTrace(\|opensTab(" web/e2e`.
- [ ] `web/e2e/guide/guide.spec.ts` (`live sign-in`; no new case): Q2 (`:189-232`) and `:535` assert the new prompt bar for a fixture view.
  - Step 3: Go to Break the feed.
  - Step 4: the unpaired text and Show me.
  - Step 5: the prompt with no action (no `trace`).
  - The other assertions stay as they are.
- [ ] `web/e2e/floor/guide.spec.ts` (`live floor`, Chromium). M3 `:187` now asserts step 3's prompt and Go to Break the feed. New cases, each with real `guide.state` from seeded rows and publishes, and each cleaning its rows in `finally`:
  - **M7 (rows 1-2):** watch and reminder seeded, so step 3 is current.
    - Go to Break the feed moves focus to the box's button, with no POST.
    - A seeded `BreakFeedRun` in `waiting` (or a real press, as M4 does) shows only T(waiting).
  - **M8 (rows 3-4):**
    - A seeded noticed Orders incident and a pending approval, with a phone message naming it (`publishFixtureEvent`), make step 4 current.
    - The Simulated mailbox tab is selected first. Show me selects the Simulated phone tab, and focus is the notification `[data-key]`, not a button.
    - The incident switched to `open` + `rejected`, with its request `rejected`, and both republished, shows T(rejected) with no button.
  - **M9 (rows 5, 7, 8, 10, 11):** `run_again` posted first, so the run window is clean. Then seed:
    - a resolved incident with `TraceHeaderId`, and an approved request;
    - two decisions with Usage rows (9000 in, 850 out, $0.0041, `claude-haiku-5-5`);
    - one turn with a `traceUrl` (`seedTurns`, published), for the conversation link.

    Then:
    - Open the trace's `href` is the TraceLink URL. Press it, stub the tab with `context.route('**/ocutalon/trace/**')`, and handle the sign-in popover if shown.
    - The finish replaces the prompt bar, with focus on its first line.
    - The run-total line is exactly "This run: 2 decisions · 9,850 tokens · $0.0041 on Claude Haiku 5.5.".
    - The two links: names, `href`s, `target`, the hidden ↗.
    - The box's button has the attention style (`tokenColor`).
  - **M10 (row 9):** from M9's finish, press Run again.
    - The prompt bar returns at step 3, with focus on Go to Break the feed and no announcement.
    - `runEpoch` rose; the check, reminder and incident rows still exist.
- [ ] `web/e2e/demo-path/01-page.spec.ts` (row 15): replace the three `notBuilt` calls with `@floor` tests, each with `signInReadme` and `watchViolations`.
  - **"The simulated phone and the simulated mailbox, each labelled Simulated":** both tabs, each with its "Simulated" label.
  - **"The demo guide lists the steps, each with its one-click prompt":** the region "Demo guide" lists five steps with their names. Selecting each shows its prompt and action:
    - steps 1 and 2: Send;
    - step 3: Go to Break the feed;
    - step 4: the unpaired text and Show me;
    - step 5: its prompt, with Open the trace absent until the run has an incident.

    Nothing is sent.
  - **"Break the feed is marked as a demo control":** "Demo control" and the inactive button with its not-watching hint.
- [ ] `web/e2e/demo-path/02-watch.spec.ts`, `03-reminder.spec.ts`, `06-trace.spec.ts`: re-point the skips (Design Notes, Decided 6).
  - 02: both `'4.7'` → `'11.1'`.
  - 03: `'4.7'` → `'8.4'`.
  - 06: `'4.7'` → `'11.1'`.

**Acceptance Criteria:**
- **AC1.** Given step 3 is selected, when I press Go to Break the feed, then rows 1 and 2 hold: focus moves to the Break the feed control without pressing it, the prompt and the waiting text are exact, and step 3 is done when the notice arrives (4.2's derivation).
- **AC2.** Given step 4 is current, when the prompt bar renders `Guide.Compute`'s variant, then rows 3 and 4 hold: the paired, unpaired, rejected, fallback and no-fix texts, with step 5 still available. Show me selects the Simulated phone tab and focuses the pending notification's container, never a button.
- **AC3.** Given step 5 is selected, when I press Open the trace, then row 5 holds: the incident's trace link opens in a new tab (after the local sign-in help), and `trace_opened` is written, which completes step 5.
- **AC4.** Given step 5 is done after an approved fix and a resolved incident, when the finish state replaces the prompt bar, then rows 7 and 8 hold:
  - the exact lines, the run total from `Ownership.RunCost` in `body-sm`, `ink-muted` and tabular figures, the two links named as opening a new tab with the ↗ hidden, More to try and Run again;
  - no bridge link;
  - focus on the first line;
  - Break the feed in the attention style (row 13).
- **AC5.** (Integration) Given the real server, when the page renders a session's run, then rows 10 and 11 hold end to end (M9): the guide view's `trace.traceUrl` and `run` come from `Guide.Compute` and `Ownership.RunCost` through `/state`, `/events` and the marker answer, and the page shows them unchanged.
- **AC6.** Given the finish state, when I press Run again, then row 9 holds: a new run epoch, the prompt bar back, steps from the session's real data (the watch and reminder still count, steps 3 to 5 wait), and the session's conversation, watch, reminders and incidents as they were.
- **AC7.** (DW-215) Given an incident whose open variant is stale for its state, when `Guide.Compute` runs, then row 12 holds, and `finished` is never true with a step 4 variant (`TestVariantFollowsState`).
- **AC8.** (REL-2) Given the fresh demo-path stack with the CI mock, when `live demo-path` runs, then row 15 holds. 01's three parts pass as `@floor`, and the watch, reminder and trace parts stay skipped, naming Stories 11.1 and 8.4.
- **AC9.** (DW-146) Given the sign-in unit's trace specs, when each case that opened a trace-application page ends, then row 14 holds. Its trace session is signed out, and V1 shows the licence-holding CSP session released.
- **AC10.** Given the floor stack, when `live floor` runs, then M3 (edited) and M7-M10 pass with the existing floor cases. `live sign-in` passes with the same case count.

## Spec Change Log

- 2026-10-26, plan halt answered (runner): orchestrator q3 allowed (regenerated `payloads.ts`, Epic 4's lines), q4 parked (U-103, no AD-13 edit); status reset to `ready-for-dev`, no re-plan; veto V1 recorded (U-104).

## Review Triage Log

## Design Notes

**Orchestrator ruling q3 (2026-10-26; decide; policy 36abb05):** ALLOWED. This story may regenerate the contended `web/src/app/live/payloads.ts` as a shared-by-entry edit: only the three generated additions in Epic 4's own lines (the `GuideRun` interface, and `trace?: TraceTarget;` and `run?: GuideRun;` in `GuideStatePayload`), produced by `node web/scripts/payloads.mjs` and checked by `payloads.mjs --check`; never a hand edit, and no other epic's interface changes. The new part `Live/Payload/Part/GuideRun.cls` is Epic 4's. The lead reports `payloads.ts` under footprint_extensions; at integrate-forward the file is regenerated from the merged classes, never hand-merged.

**Orchestrator ruling q4 (2026-10-26):** parked as U-103 (owner): AD-13 and AD-25's capacity note are NOT amended by this story. The in-story test fix for DW-146 stays (the `signOutTrace` helper and the relative licence check, decide); the residual (a trace tab holds its licence unit until sign-out or the session timeout) is re-owned by the lead at adjudication.

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-1** (L99): REST writes only UI markers (`trace_opened`, `run_again`). Go to Break the feed presses nothing.
- **AD-4** (L155): `RunCost` and `NewestIncident` read with the caller's `SessionRef`, never one from the client.
- **AD-12** (L330):
  - `Guide.Compute` is the one source, and the page decides no progress;
  - a payload is the full view, so the run's trace target and total go into `guide.state`;
  - trace targets travel as `traceHeaderId` and `traceNamespace`, and the web layer adds the URL;
  - the finish rule (P24) is unchanged.
- **AD-13** (L345): the browser envelope for the marker POST; one sign-in group, so `?IRISLogout=end` ends the context's group (measured, Task 0).
- **AD-15** (L402): the open variant is stored beside the state and is set on moves to `open`. The transition table never moves `open` with a variant to `resolved`, so reading the variant only for `open` and `closed` matches the table and survives an overlap implementation that keeps a stale value (DW-215).
- **AD-20** (L523): `RunCost(SessionRef, since)`. Input tokens already include the cache tokens, so `tokens` = input + output.
- **AD-24** (L651) and **AD-26** (L725): the incident's own trace session (`Incident.TraceHeaderId`) is the diagnosis chain's; `TraceLink` is the one builder.
- **AD-22** (L579): the CI mock. Its prompt scenarios answer a guide prompt's triage request with the reply text, so the watch step's strip is a fallback, not Act (inference, `ci/mock/mock.mjs:269-276`). Hence Decided 6.
- **AD-29** (L765): Lane B; demo-path parts turn on only when they pass on the integration branch.
- **AD-33** (L852): `guide.state` keeps one publisher, `Live.Publish.RefreshGuide`.
- **Conventions:**
  - L908 REST;
  - L909 Live events;
  - L913 Announcements and focus (focus only on the user's action or through `focus-rule`; 4.4's ruling);
  - L926 Angular (one typed API client: `postGuideMarker`);
  - L927 README link (`README_URL`);
  - L930 Tests (floor cases only in `live:floor`; demo-path `notBuilt(title, 'N.M')` and `@floor`).
- No AC contradicts an AD's Rule, and no NFR trips Rule 5. NFR-7 and the time budget are measured in the rehearsal, not here.

**Decided in-stage** (unattended: small, reversible, within the intent):
0. **Rule blocks.** The three binding rule blocks of the dispatch were each read in full before planning: `plan-block.md`, `runtime.md` and `unattended-block.md`, in the epic-4 scratchpad folder. The committed `epic-4-context.md` was reused, not recompiled.
1. **One story, with a split line.** The page, the payload, DW-215, the floor cases, 01's turn-on and DW-146 are each moderate, and Story 4.6 converged in one pass at a comparable size. If the implement stage doesn't converge, the split line is:
   - DW-146 (the trace sign-out and its call sites) and the demo-path edits (01, 02, 03, 06) go to a sibling planned next in this epic;
   - the guide, the payload and DW-215 stay here.
2. **The trace target and the run total travel in the payload** (AD-12's full view), not in a new REST read. A read would need its own refresh triggers, busy states and a REST-surface row, and the guide would drift from its event. It is why the generated `payloads.ts` must change: see the Auto Run Result.
3. **`run` only while finished.** It is what the finish shows. Computing it on every refresh would add two reads to each trigger and republish `guide.state` on every decision before the finish. After the finish it follows the next guide refresh; a mailbox decision is not a trigger, so its cost shows at the next one.
4. **No action in the rejected, fallback and no-fix variants.** EXPERIENCE gives each step one action, and Show me has no pending notification to show there. The fallback and no-fix texts send the user to step 5, which stays selectable. No new text is needed.
5. **Step 5 without a trace shows no action.** Before the run's incident there is nothing to open, and a dimmed link would need a reason text that the UX doesn't have. 01's test asserts this.
6. **The demo-path parts that can't pass honestly are re-pointed, not faked.** Each named story's AC already turns its part on, so no AC moves.
   - **02's watch reply:** with the mock, the triage decision is a fallback (AD-22 note), and the check row needs Story 5.1's watch tool. Story 11.1 (epics.md:3432) owns the Act strip and the check row.
   - **03's reminder:** `ReminderOps` is a stub (`Schedule/ReminderOps.cls:7`, answering `not_built`), so the mock's "The CI mock set the reminder." would be a false confirmation. Story 8.4 (epics.md:3078) turns the reminder step on.
   - **06's trace:** it needs the incident (Lane A). Story 11.1 (epics.md:3439-3441) turns it on.
7. **Show me's target** is the newest phone message naming a pending approval, else the phone's feed region ("otherwise, the nearest container", UX-DR131). The phone has no Approve button until Story 6.3, so "never Approve" holds by construction, and M8 asserts that focus is not on a button.
8. **The marker answer covers the gap.** The 200 view is shown until the next live view, as the Break the feed box holds its press answer (4.4). This stops a second Run again in the poll gap. Errors add no text (Break the feed's rule; an unreachable server raises the page's banners).
9. **`expired`** keeps 4.2's `paired`/`unpaired` (epic context; 4.2 Decided 2). EXPERIENCE has no text for it, it is a local-install edge after 24 hours (E:632), and a new variant would amend Story 4.2's AC. This is noted for the lead, not built.
10. **Run-total wording.** The UX's count rule (E:187) gives a singular at 1. A run with no usage row drops " on {model}" (nothing to name). Several models are listed, joined with "and". The cost uses `formatCost`, and the tokens use `formatTokens` (Rule 2).
11. **The marker call goes into `ApiClient`.** `api-client.ts` and `api-types.ts` are shared by entry now (4.6 Decided 15), and the Angular convention is "one typed API client". Putting it beside `break-feed-api.ts` would add to DW-231's move.
12. **Where the new browser cases run.** They go in `live floor` (M7-M10), because a case added to the guide spec's chromium project would land in `live sign-in`, which is at its cap.
    - The floor stack has real `guide.state` from seeded rows (M3, M6) and a fixture user.
    - Expected (inference): about +60 to 80 s on 290-304 s, so under about 8 minutes.
    - 4.7's own cases stub their trace tabs, so they take no licence unit.
13. **DW-146's pin is relative.** V1 compares the LINKS user's `CSPCon` before and after, because one licence unit is held per user and client address, so an absolute "none" would depend on other cases.
14. **`afterEach` in the two trace files.** Each case owns its context, so ending the group after the case harms nothing. A `beforeAll` API context has its own cookies and CSP sessions, and they survive a page context's sign-out.

**Task 0 (DW-146), measured in this plan** (lane-B throwaway `e4s7p`, 2026-10-26, Apple silicon):
- **How:** a temporary spec in `web/e2e/demo-path/` (deleted after the run, tree confirmed clean) ran inside `ci/iris.sh live demo-path`. It read `$SYSTEM.License` counters, `%SYSTEM.License:UserList` and the count of `^%cspSession` through `irisScript` at each step. The stack was torn down by the unit's own trap.
- **Baseline:** `KeyLicenseUnits` 8, `LUConsumed` 1 (one `User` connection), 4 CSP sessions.
- **Signing in to `/ocutalon`** (README account) adds a CSP session and **no licence unit** (`CSPUsers` 0, LU 1). Posting a turn adds nothing.
- **The first Visual Trace tab** of a signed-in context adds **one licence unit** for that user and client address (`ocutalon@172.27.0.1,CSP,1,1,1,0`). Two more tabs of the same context add none. Closing the tabs, and then the whole browser context, releases nothing.
- **Each further distinct user** that opens a trace tab adds one unit: after users 1-6, LU 8 of 8 and `LUAvailable` 0.
- **At the limit:**
  - the 7th user's tab still drew;
  - `irisScript` (`iris session` in the container) printed nothing, refused for want of a licence;
  - users 8 and 9 signed in to `/ocutalon` (no unit needed), but their trace tabs answered **503 Service Unavailable**.
- **Signing out:** `GET ...EnsPortal.VisualTrace.zen?IRISLogout=end` with the context's cookies answered 200, and the README account's unit was released at once (its `UserList` row was gone). A following `POST /api/v1/session/end` answered 401, because the group had already ended.
- **Conclusion.** DW-146 is real, with its cause corrected. It is not "each tab" but each distinct user who opens a trace-application page, held up to the 8-hour local session timeout (`Install/Step/Web.cls:170`). With 8 units, the 7th or 8th distinct trace user starves, and `irisScript` fails with it. Signing the trace session out frees the unit at once.

**Veto-window items** (with the recommendation):
- **V1: public texts not in the UX** (each recorded `ruled` in `ux-strings`):
  - the trace links' sign-in name for a custom label, T(signInFor) "{label} (shows sign-in help first)". It is composed from Story 2.13's own words, so that the name keeps the visible label (WCAG 2.5.3);
  - the singular forms "1 decision" and "1 token";
  - the model list's " and " and ", ".

  **Recommendation: keep.**
- No schema change: `GuideState` (the table) is unchanged, and the payload additions are live-event view fields.

**Texts** (exact; the ellipsis is not used; U+00B7 is `·` and U+2197 is `↗` in code):
- **Step 3:**
  - promptBreakFeed: "Press Break the feed. The partner will send 50 orders in a new date format."
  - waiting: "Waiting for OcuTalon. The reminder may arrive first."
  - goToBreakFeed: "Go to Break the feed"
- **Step 4:**
  - approvePaired: "Approve the fix in Telegram on your phone, or on the simulated phone."
  - approveUnpaired: "Approve the fix on the simulated phone, or in the chat."
  - rejected: "Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again."
  - fallback: "OcuTalon couldn't diagnose this run, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again."
  - noFix: "OcuTalon found the cause but has no fix for it, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again."
  - showMe: "Show me"
- **Step 5:**
  - promptTrace: "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision."
  - openTrace: "Open the trace"
- **Finish:**
  - finishDone: "Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log."
  - runTotal: "This run: {n} {decisions} · {tokens} {tokensWord} · {cost} on {models}.", with "decision"/"decisions", "token"/"tokens", " on {models}" dropped when there are none, and models joined "A and B" or "A, B and C"
  - conversationLink: "See the whole conversation in Visual Trace", then a hidden " ↗"
  - installLink: "Install OcuTalon yourself", then a hidden " ↗"
  - moreToTry: "More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production."
  - runAgain: "Run again"
- **Shared:**
  - the links' hidden suffix: "(opens in a new tab)" (`TRACE_TEXTS.opensInNewTab`);
  - signInFor (V1): "{label} (shows sign-in help first)".

**Rule 2 (extend, don't copy):**
- `app-trace-link` gains `text`, `appearance` and `opened` rather than a second trace-link component. Its default markup is unchanged.
- `pendingRef` extends `pendingApproval`.
- The run total reuses `formatCost` and `formatTokens`.
- `GuideRun` follows `Part.Cost`.
- `GuideMarkers` reuses `StateBody`'s `TraceLink.Viewer`/`Add` pair (two lines).
- The floor cases reuse the seed helpers, `publishFixtureEvent` and links.spec's tab-stubbing pattern.
- `signOutTrace` is one helper beside `openTrace` in `support/trace.ts`.

**Integration ACs (Rule 1):**
- The page (consumer) reads the real `guide.state` and `/state.guide`, with `trace.traceUrl` from `TraceLink` and `run` from `Ownership.RunCost` through `Guide.Compute`. It renders Open the trace's `href` and the exact run total (AC5, M9).
- The page's markers reach the real `GuideMarkers` and `GuideState` (M9 `trace_opened`, M10 `run_again`).
- The Break the feed box reads `finished` (M9's attention style).

**Consumes:**
- Story 4.2: `Guide.Compute`, `step4Variant`, `finished`, `runEpoch`, the marker endpoint, `GuideState.RunStartedAt`.
- Story 4.4: the prompt bar, the box, `focus-rule`, the step announcements.
- Story 4.5: `DeviceTabs`, the phone's `[data-key]` notifications.
- Story 4.6: the mailbox, named by More to try.
- Story 2.13: `app-trace-link`, `TraceHelp`, `conversationUrl`.
- Story 2.6: `formatCost` and `formatTokens`.
- AD-20: `Ownership.RunCost`.

**Consumed-by:**
- **Story 11.1:** the guide's Open the trace and the finish on the real incident path (the demo-path trace step), and the watch and reminder parts re-pointed to it and to 8.4.
- **Story 8.4:** the reminder step's demo-path part.
- **Story 6.3:** Show me's target once the phone shows Approve: focus stays on the container, never Approve.
- **Story 10.3:** `paired` and its step 4 text (`TelegramState`).
- **Story 31.3:** the bridge link in the finish.
- **Stories 6.1 and 11.1:** they inherit `signOutTrace` for any real trace page they open (DW-146).

**Ledger:**
- **DW-215: addressed** (row 12, AC7, `TestVariantFollowsState`, the `Guide.cls` task). The variant counts only for `open` and `closed`. That is a third means beside the entry's two: it makes `finished` with a step 4 variant impossible, and it keeps the finish for a run that truly ended with an approved fix.
- **DW-146: addressed** (Task 0 measured above; row 14, AC9, the `support/trace.ts` task and the call-site task, with V1's pin). The tabs do hold a licence unit, per user, until signed out.

**For the lead:**
- **Clarification (blocking):** see the Auto Run Result.
- **Spine (Rule 20, a measured fact, the lead's call).** AD-13 (L373, L380) and the capacity section (L717) say "each trace window holds one more [connection] … about two minutes". Measured on build 154:
  - a trace-application session takes one licence unit per user and client address, and more windows of the same user take none;
  - `/ocutalon` itself takes none;
  - the unit is held until sign-out or the session timeout (8 hours locally, 120 s on the online demo);
  - at 8 units, trace pages answer 503 and container terminals are refused.

  Recommend a corrected sentence in AD-13's capacity note.
- **Epic context:** "Each Visual Trace window holds one for about two minutes after its last use" (Licence connections) is corrected by the same measurement.
- **Footprint:** see the Code Map's footprint list. The one contended edit made without a ruling is the block appended at the end of `Test/Web/GuideApi.cls`.
- **Demo path:** 02, 03 and 06 are re-pointed to the stories whose ACs turn them on (Decided 6). The floor count rises from 4 to 7.
- **Not built:** an `expired` step 4 text (Decided 9). It needs a UX text and a 4.2 AC amendment, if wanted.
- **A doc to update:** `docker/tests/test-demo-path.sh:12-13` (contended) says "No test sends a model request". It stays true: 4.7 adds no keyed spec.

## Verification

`<B>` means `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=implement'`.
- **Tags:** fresh `e4s7i`; warm `e4s7iw` (`<B> OCUTALON_RUN_TAG=e4s7iw ci/warm.sh up` once, and `ci/warm.sh down` at the end, after a failure too).
- **One command per foreground call** (`timeout: 600000`), and one `iris_execute_tests` per message.
- **Slot B** (`ocutalon-slot-b`, namespace `OCUTALON`, identity checked with `iris_server_info`, build 154) is for loading and compiling only: `iris_doc_load` with `baseDir` `src/ocutalon/cls`.
- **Fresh stacks only** for the live units and anything that changes what a start installs. `Guide.Compute` is called directly by the classes, so warm runs are valid for the server classes.
- **Task 0** was done in this plan (Design Notes). No further platform measurement is needed.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, including the edited guide, box, phone, trace, string and focus-source tests.
- `npm --prefix web run lint` -- expected: exit 0.
- `node web/scripts/payloads.mjs --check` -- expected: exit 0 once `payloads.ts` is regenerated (after the ruling).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s7iw ci/iris.sh class <Class>` -- expected: passed. One call each for `OcuTalon.Test.Demo.Guide`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Web.GuideApi`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Demo.BreakFeedIn` (it reads `Compute(...).BreakFeed`) and `OcuTalon.Test.Data.OwnershipGuide`.
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh build`, before any browser run that should see changed web code.
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh live floor` -- expected: PASS in all three projects (M1-M10, D1-D7 and the rest), under about 8 minutes (about 290-304 s before, plus M7-M10). Record the time.
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh live demo-path` -- expected: PASS. The summary shows STEP 1 passed (6 of 6), STEPs 2, 3 and 6 skipped naming 11.1 and 8.4, floor 7 of 7. Well under 8 minutes (about 248 s measured in this plan with the extra spec).
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh live sign-in` -- expected: PASS with the same case count (V1's pin and the edited Q2 included), at about 461-463 s. The sign-out adds one GET per trace case (inference: under 5 s). Over 470 s, keep `signOutTrace` only in the cases that opened a real trace page, and record it.

`(once)`:
- `bash docker/tests/test-web-build.sh` -- expected: the build passes, with the payload and catalog checks and the budgets under the error level.
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh live demo-switch` -- expected: PASS (its guide spec at mode 0 and mode 1; the guide keys are unchanged while `trace` and `run` are absent). Under about 8 minutes (300-321 s before).
- `bash ci/checks.sh` -- expected: exit 0.
- At the end: `<B> OCUTALON_RUN_TAG=e4s7i ci/iris.sh teardown` and `<B> OCUTALON_RUN_TAG=e4s7iw ci/warm.sh down`.

**Planned mutations (Rule 19).** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Record each as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | Go to Break the feed calls the box's press | M7 (a POST seen) |
| 1 | the waiting line also for `no_notice` | `guide-view.test.mjs` (row 2) |
| 2 | Show me without `select('phone')` | M8 (it starts on the mailbox tab: the phone tab is not selected and focus is not in the phone) |
| 2 | step 4 shows Show me for `rejected` | `guide-view.test.mjs` (row 4); M8 |
| 3 | `opened` not emitted from the popover's Open Visual Trace | M9 (no `trace_opened`; no finish) |
| 3 | Open the trace takes `conversationUrl(store.chat)` in place of `guide.trace.traceUrl` | M9 (`href` is not the incident's TraceLink URL) |
| 4 | the finish ignores `finished` and shows at step 5 | `guide-view.test.mjs`; M9 |
| 4 | `boxView` keeps `secondary` when finished | `break-feed-view.test.mjs`; M9 (attention colour) |
| 4 | `runTotalText` without the singular | `guide-view.test.mjs` (row 8) |
| 5 | `Guide.Compute` sets `run` while not finished | `TestRunTotal` |
| 5 | `run.tokens` = `inputTokens` only | `TestRunTotal`; M9 (the exact line) |
| 5 | `GuideMarkers` without `TraceLink.Add` | `TestMarkerAnswerTrace` |
| 5 | `trace` from an incident before the run window | `TestTrace` |
| 6 | Run again's answer not held (live view only) | M10 (the finish is still there right after the 200) |
| 6 | `run_again` posted as `trace_opened` | M10; `TestRunAgain` |
| 7 | the variant read for every state again | `TestVariantFollowsState` |
| 8 | `promptOf(3)` gives no action (Go to Break the feed dropped) | 01's "the demo guide lists the steps" `@floor` test, in `live demo-path` |
| 9 | `signOutTrace` sends no `IRISLogout` | V1 (the pin: `CSPCon` stays one higher) |
| 10 | `promptOf(3)` gives no prompt (4.4's behaviour) | M3 (edited) |

**Shared surfaces:**
- the `guide.state` payload: `Test.Live.Payloads`, `payloads.ts` with `payloads.mjs --check`, `demo-switch/guide.spec.ts`'s `Guide` interface, `GuideStatePayload` readers (`guide-view.ts`, `break-feed-view.ts`);
- the marker answer's JSON (`Test.Web.GuideApi`);
- the guide's prompt bar (`guide/guide.spec.ts` Q2 and `:535`, `floor/guide.spec.ts` M3);
- `boxView`'s style (`break-feed-view.test.mjs`, floor M4);
- `app-trace-link`'s defaults (`links.spec.ts`, the chat, rail and header trace links);
- `pendingApproval` (the phone's arrival rule, `phone-view.test.mjs`);
- `ApiClient`;
- the source-scan lists (`IMPORTED`, `SOURCES`, the character rule, `FOCUS_CALLS`, `afterNextRender`);
- the demo-path summary's step lines and floor count;
- the trace sessions of the sign-in unit's fixture users, which are now signed out after each trace case;
- the floor user's `GuideState` (M9 and M10 post `run_again`; later floor cases read the guide only through the current epoch's rows).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none (the plan's halt on the contended `payloads.ts` was answered by the orchestrator's ruling q3, recorded under Design Notes; the text below is the plan's record of the halt).

**The file.** `web/src/app/live/payloads.ts` is generated by `web/scripts/payloads.mjs` from the payload classes. It sits in Epic 16's contended `web/src/app/live/**`, and it is not among this dispatch's shared-by-entry files.

**Why it must change.**
- The guide's Open the trace needs the current run's incident trace (AC3; `Incident.TraceHeaderId`, which no page payload carries in this tree).
- The finish needs the `Ownership.RunCost` total (AC4).
- AD-12 puts both in the server's guide view: a payload is the full view, and trace targets travel as `traceHeaderId` and `traceNamespace` with the URL added by `TraceLink`. So `OcuTalon.Live.Payload.GuideState` (Epic 4's own class, Story 4.2) gains `Trace` and `Run`, and a new part `GuideRun` is added.
- The build's `payloads.mjs --check` then requires `payloads.ts` to be regenerated. That is three additions, and only in Epic 4's own lines: a `GuideRun` interface among the parts, and `trace?: TraceTarget;` and `run?: GuideRun;` in `GuideStatePayload`. No other epic's interface changes.

**Recommended ruling:** allow the regenerated `payloads.ts` as a shared-by-entry edit of Epic 4's own `GuideStatePayload` lines, reported as a footprint extension, with `node web/scripts/payloads.mjs` re-run at integrate-forward if Epic 16 also changes a payload. This is the same principle as the orchestrator's q1 ruling of 2026-10-26 15:35Z. On that ruling, set the status to `ready-for-dev`; no re-plan is needed.

**If refused:** the trace target and the run total would move to a new REST read (for example `GET /api/v1/guide/run`). That is a REST-surface addition (a veto item), with its own fetch triggers and busy states on the page. It needs a re-plan of the page's data flow (Decided 2 explains why the payload is preferred).

**For the spec gate.**
- **Veto item V1:** the sign-in name for custom trace-link labels, the singular forms and the model list joiners.
- **Ledger:** DW-146 and DW-215 are addressed (Design Notes, Ledger).
- **Task 0** (DW-146) was measured in this plan on the lane-B throwaway `e4s7p`, now torn down. The temporary spec was removed and the tree confirmed clean.
- **Spine:** one measured-fact correction is recommended for AD-13's licence note (For the lead).
- **Timing:**
  - the new browser cases run in `live floor` (expected under about 8 minutes);
  - `live demo-path` was measured at 248 s with an extra spec;
  - `live sign-in` gains no case.
