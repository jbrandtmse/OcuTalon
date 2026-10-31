---
title: 'Story 11.1: The web demo path passes end to end in the REL-2 test'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '8ca7bf38d7d06b83bbc1888b0ccf1a918694417d'
baseline_commit: '8ca7bf38d7d06b83bbc1888b0ccf1a918694417d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** REL-2's web demo path proves only steps 1 and 3 on real components. Step 2's watch, step 4's incident, step 5's fix and step 6's trace are still `notBuilt(..., '11.1')` (and DW-202's '8.2') or `@fixtures` tests that publish incident and approval rows by hand (Stories 4.3, 6.3, 6.4, 8.2), so a green `live:demo-path` does not show UJ-1's web route working. After a page load, an incident card also cannot find its diagnosis decision (DW-294).

**Approach:** Turn every step spec 02 to 06 under `web/e2e/demo-path/` on against the real components on the CI mock. The specs run as one ordered journey of the README account: watch, reminder, Break the feed, Approve on the simulated phone, then Open the trace with the finish line.
- After the browser steps, the unit reads the IRIS audit log.
- The unit's step summary fails on any skip outside Telegram's parts.
- `/state` carries each incident's diagnosis decision (DW-294).
- Fixture check rows are seeded as not due (DW-349).

The failure paths, the coda, the real-model rule, the online run and the remaining ledger entries move to sibling Stories 11.7, 11.8 and 11.9 (Design Notes, Proposed split).

## Boundaries & Constraints

**Always:**
- **One ordered journey.** The demo-path project is one ordered journey on the unit's own fresh stack: one worker, files in name order. Each step spec starts from the state that the steps before it left. A test that needs the stack sits in a `describe` that skips without `OCUTALON_URL`. Its skip text starts "Story 11.1 needs the first-start stack" (03 keeps its "Story 8.6" text), so the hosted no-stack check still reads each of steps 2 to 6 as skipped with a story.
- **CI mock only.** The runners' keys are pointed at the mock by `pointKeys()` in the `beforeAll` of 02 (and again, idempotent, in 03's). They stay pointed through 04's diagnosis and 05. `restoreKeys()`, then `RunnerFixture.WaitRecords()`, run once, in 06's `afterAll` (moved from 03). `ANTHROPIC_API_KEY` stays unset.
- **Step 2's watch on the mock** is sent through the composer as `[[mock:watch-act-orders:<key>]] Watch the Orders production and only tell me if something needs me.`, after `Test.Contract.Mock.Arm("watch-act-orders:<key>", 1)`. `<key>` is lower-case letters and digits, new for each run. The countdown gives the Triage request reply 0 (Act) and the turn replies 1 (`start_watch`) and 2 (text). The guide's own Send cannot do this under AD-22 (DW-307, Clarification Needed).
- **Lane A changes the mock only by adding files under `ci/mock/scenarios/A/`** (AD-22, AD-29).
- **Text oracles.** The page texts are the ones that the epics block and EXPERIENCE.md fix, written out in the specs as the independent oracle. In code, non-ASCII characters such as the middle dot (U+00B7) and the ellipsis (U+2026) are written as backslash-u escapes, never as literal bytes (Rule 14). This spec shows them as they render.
- **`/state`'s incident decision** is read only through `Ownership.Decision(ref, sessionRef)`, the session's own (AD-4). Payload classes and storage are unchanged.
- **The audit check** proves an entry's data holds exactly `Bridge.Audit.Shape(type)` plus `COMMON`, and that `docker/tests/lib-keys.sh` `key_like` finds nothing. It never matches the README password by value: it is `ocutalon`, which is also `irisUser`.
- **Comments state the contract.** Stale "until Epic 11" or "on fixtures" text in a file this story touches is replaced (Rule 14).

**Never:**
- **Contended files.** Change `ci/units.sh`, `docker/tests/lib-live.sh` or any file that Epics 15, 30, 12 or 13 list in `.worktrees/.coordination/contended-epic-11.txt`, among them `Checks/Process.cls`, `Fix/Executor.cls`, `Bridge/Approval.cls`, `Bridge/Process/*.cls` and `Production.cls`. Change no mock code (`ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`) and no B-folder scenario.
- **Scope out.** Touch `telegram-*.spec.ts`. Turn on the online run's steps 2 to 5, the failure paths, the coda, the real-model mode or DW-433 (all Story 11.7), Lane A's chat reminder tools (11.8), or the clause checks outside `web/e2e/demo-path/` (11.9).
- **No hand-made rows.** Seed incidents, approvals, notifications or check rows by hand in 02 to 06. Drive through product internals a step that the page can drive.
- **Wrong targets.** Run a demo-path, Playwright or destructive test on slot A. Use another lane's slot, `ocutalon-aihub-test` or a real key.
- **Spine.** Amend AD-22 or edit the spine (U7: AD-22 is cited by done specs, so this is the owner's call).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Step 2 before the watch | README session after 01; no check row | Break the feed is inactive (`aria-disabled="true"`) with "Ask OcuTalon to watch the Orders production first (step 1)." and Do step 1. A POST to `/demo/break-feed` returns 409 `not_watching` with that text. Afterwards there is no run, no header and no failed order. | No error expected |
| Step 2 watch (AC1) | Countdown armed with 1; the marker message is sent | The mock answers the Triage request with reply 0 and the turn with replies 1 and 2. The reply's strip shows chip Act, no `app-fallback-flag`, its reason line and one trace link. Then the "Orders production" check row appears, Break the feed is active, and the guide reads "Step 1, Watch, done" and "Step 2, Reminder, current". | Countdown not armed: the strip is not Act, and the test fails on the chip |
| Step 2 last run (DW-202) | The real watch row (`NextDueAt` = `CreatedAt`) | Within 120 s the row's `.meta` reads `/^Last run \S.* · Passed$/`, from the real heartbeat's Checks run | No error expected |
| Step 3 (DW-340) | Step 1 done | The "Step 2, Reminder, upcoming" or "Step 2, Reminder, current" button opens the prompt. Then "The CI mock set the reminder.", one stretch row with its countdown, and "Step 2, Reminder, done". Nothing cancels the reminder. | No error expected |
| Step 4 press (@floor) | Watch on; reminder pending | Pressing the page's button answers 200 `{state:'sent', startedAt}`. Events: `breakfeed.progress` sending, then sent, then `guide.state` waiting. A second press answers 409 `incident_in_progress`. 50 failed orders, 0 at the warehouse, and one run. | No error expected |
| Step 4 card (AC3) | After the press, waits of up to 90 s | Card chip "Awaiting approval". Headline `/^50 orders failed since \d{1,2}:\d{2}/`, the cause, "Data format change · OrderDate · 50 failures grouped into this incident", the dry run ("Dry run", "50 orders affected", "Nothing has changed yet."), and "Approve: repair and resend 50 orders" / "Reject: repair and resend 50 orders". The phone notice carries the same two buttons. The rail shows "Approval requests (1)" (spoken "Approval requests, 1") and one row. "Step 4, Approve, current". The chat shows "Reminder: stretch." and the phone a stretch message. | No error expected |
| Step 5 (AC4) | Fresh sign-in; pending request | The footer of the card shows its diagnosis decision strip, chip Act (DW-294). Approve on the phone. The phone reads "Approved from the simulated phone at HH:MM." and the card "Approved from the simulated phone at {clock}". Chip Fixing with "Repairing and resending 50 orders…". Then "All 50 orders went through.", then "Recorded in the IRIS audit log.", then chip Resolved. The phone gets a result message with no buttons, and the rail row is gone. | No error expected |
| Step 6 (AC5) | Resolved after an approved fix | "Open the trace" opens the dialog "Sign in to Visual Trace". Its link "Open Visual Trace (opens in a new tab)" opens a tab at `TRACE_PAGE` with `SESSIONID` = the incident's diagnosis header id, which draws the session. The guide then shows the finish line `This run: {n} decisions · {tokens} tokens · {cost} on {model}.` | No error expected |
| Audit (AC6) | After Playwright, a mark taken before it | The answered Approval entry (outcome approved, channel phone, the session) and the resend's Action entry with `approvalRef` = that request. Each holds exactly its shape and nothing `key_like`. | Either is missing after the poll, an extra member is present, or a key-like value is found: one FAIL line each |
| Summary flag (AC7) | `--only-telegram-skips <report>` | A skip in a `0<n>-*.spec.ts` file is a FAIL. Skips in `telegram-*.spec.ts` are accepted. Without the flag the summary works as today. | Usage error (exit 2) on a wrong argument count |
| `/state` decision (DW-294) | An incident whose `DecisionRef` is the session's diagnose decision; another one whose `DecisionRef` is empty or another session's | The first chat item is `{type:'incident', payload, decision}`. The second has no `decision`. The store's `decisions` holds the first. | No error expected |
| Fixture check (DW-349) | `Fixture.Check(s)`, then `Fixture.Check(s, , , {"NextDueAt": ""})` | `NextDueAt` is now + 3,600 s (±120). With the explicit `""` it is empty, so the row is due. | No error expected |

</intent-contract>

## Code Map

Epic 29 merged into the feature branch at `fe1d81e2`. The implement stage integrates it forward first, so the line numbers here are those of `origin/feature/OCT_OcuTalon_MVP` for Epic 29's files.

**The step specs**
- `web/e2e/demo-path/02-watch.spec.ts:1-50` (all of it):
  - 4-5 are the two `notBuilt` calls for 11.1;
  - 6 is `notBuilt(...,'8.2')` and 8-50 is Story 8.2's fixture block (DW-202);
  - all of it is replaced.
- `web/e2e/demo-path/03-reminder.spec.ts`:
  - :36 holds the step-2 button name (DW-340);
  - :23-26 is the `beforeAll` pointKeys, which stays;
  - :54-72 is the `afterAll` that cancels and restores; it goes, and the restore moves to 06.
- `web/e2e/demo-path/04-incident.spec.ts`:
  - :32-96 is the `@floor` press test: drop its `not_watching` refusal (:57-59), which moves to 02, and its `Fixture.Check` seed (:61-62); keep its title;
  - :98-155 is the `@fixtures` test, which goes;
  - :157-158 are the `notBuilt` calls.
- `web/e2e/demo-path/05-approval.spec.ts`:
  - :14-134 are the two `@fixtures` tests and their doc, which go;
  - their locator lines (:59-67, :108-129) are the oracle to reuse;
  - :136 is a `notBuilt` call.
- `web/e2e/demo-path/06-trace.spec.ts:1-4` is a single `notBuilt`.
- `web/e2e/demo-path/01-page.spec.ts` stays unchanged. `web/scripts/playwright-projects.test.mjs:148-158` pins its floor titles.

**Siblings to extend (Rule 2)**
- `web/e2e-online/demo-path/demo-path.spec.ts` (Epic 29):
  - :43-52 are the locator helpers;
  - :58-79 are `Snapshot` and `readState`;
  - :100-113 is `doneTurn`;
  - :172-209 is step 6 against the real Visual Trace;
  - :262-337 is the real chain from Break the feed to the end of the fix.
  - These helpers move into a new `web/e2e/support/demo-path.ts`, which both runs import.
- `web/e2e/support/devices.ts`:
  - :180-189 `pointKeys` and `restoreKeys`; `armCountdown` goes beside them;
  - :109 `phoneMessage`; `phoneRows`.
- `web/e2e/support/iris.ts`:
  - `irisScript`, `chk`, `quoted`, `readApproval`, `incidentState`;
  - :829-871 `seedCheck`, whose doc gets DW-349's default.
- `web/e2e/support/api.ts`: `STATE`, `post`, `sessionEvents`.
- `web/e2e/support/trace.ts`: `TRACE_PAGE` (:14), `helpSeen`, `drawnMessages` (:143), `expectDrawn`.
- `web/e2e/support/floor.ts` (Epic 29): `signInReadmeLoaded`, `railOf`, `replyOf` and `CARD_MS`, read only.
- Locator precedents:
  - `web/e2e/chat/decision.spec.ts:93-139` for the strip's chip, reason and group;
  - `web/e2e/floor/guide.spec.ts:495-545` (M9) for Open the trace, the sign-in dialog and the finish locators `.finish .finish-done` and `.run-total`;
  - `web/e2e/reminder/reminder.spec.ts:85-88` for the reminder card.

**The mock**
- `ci/mock/mock.mjs:24-37` holds the selection order and the reply rule: a prompt-selected request has a `null` label, so it has no countdown (`:420-462`). It is not changed.
- `ci/mock/scenarios/A/watch-start-orders.json` is the shape that the new `A/watch-act-orders.json` extends with a first, Triage-shaped reply.
- `ci/mock/scenarios/A/triage.json` gives the triage JSON shape.
- `ci/mock/scenarios/A/diagnosis.json` gives the cause text and the `OrderDate` element.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls:437` is `Arm(marker, remaining)`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls:11-14`: a turn sends Kind decide (Triage) first, then Kind turn after its answer, so the countdown order holds (Task 0 confirms it).
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls:73-79`: the strip shows the triage decision unless the reply fell back.

**The product (read only, or used for mutations)**
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls:97`: a real watch's `NextDueAt` = `CreatedAt`.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls`:
  - :97 the five done flags; :112-116 finished; :121-127 the current step;
  - :125-134 the trace target (the incident's `TraceHeaderId`); :135-146 the run total.
- `web/src/app/guide/guide-view.ts:43-47` and `:205-224` hold the finish texts and `runTotalText`.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls:9, 46` routes incident and reminder notices to WebChatOut and SimPhoneOut.

**DW-294**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:826-841` is `ChatItems`, which gets the change. `:803-818` is `MailboxItems`, the sibling that already attaches `decision` through `Ownership.DecisionOfItem`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:389` is `Decision(ref, sessionRef, .sc)`, which reads only the session's own decision.
- `web/src/app/live/live-store.ts:114-135` is `fromSnapshot`; `decisions` comes from `snapshot.rail.decisions` only.
- `web/src/app/api/api-types.ts:42-47` holds `chat: LiveItem[]` and the rail decisions.
- `web/src/app/incidents/incident-view.ts:327-329, 422` is the footer lookup by `decisionRef`.
- `web/src/app/rail/rail-view.ts:328` shows only kind decide, so the rail is unaffected.
- Tests to extend: `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:247` `TestStateMailbox` and `:491` `TestStateChatDecision`, and `web/scripts/live-store.test.mjs`.

**DW-349**
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:63-77` is `Check`. Its `SetFields` (:187-194) runs after the defaults, so an explicit `""` still overrides.
- `Checks/Process.cls:258-268` (`Due`) treats an empty `NextDueAt` as due. Epic 30's file, read only.
- 23 test classes call `Fixture.Check`, among them `Test/Live/GuideRefresh` (8 calls), `Test/Data/Ownership` (10), `Test/Watch/Tools` (9) and `Test/Bridge/Gate` (5). `Test/Checks/Runs.cls:556` (Epic 30) already passes `"NextDueAt": ""`.

**The unit and its gate**
- `docker/tests/test-demo-path.sh`:
  - :1-21 is the header ("Only step 3's spec sends a model request" is now stale);
  - :37-46 is the Playwright budget (`remaining - 20`);
  - :52 runs the summary;
  - the audit check goes between :59 and :61.
  - `iris_script` and `wait_until` come from `lib-live.sh`, read only.
- `web/scripts/demo-path-summary.mjs`: :1-22 is the header, :89 `summarize`, :177-186 `main`.
- `web/scripts/demo-path-summary.test.mjs`:
  - :344-370 is the no-stack real-spec pin: :364 the one failure, :367 steps 2 to 6 skipped with a story, :369 step 3's "1 skipped (Story 8.6: ";
  - the comment at :345 is stale.
- `docker/tests/test-demo-path-gate.sh` (415 lines):
  - :80 `dc() { :; }`; :92 the npm stub;
  - :142-147 the synthetic green report, which skips in every step;
  - :248-281 the green run, whose :277 timeout window (500000, 520000] belongs to a 540 s deadline;
  - :285-342 the red runs.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/AuditLog.cls:23-73`: `Now`, `Entries` and `Wait`, read by `UTCTimeStamp`, so readable at once.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:22-45, 61`: `COMMON`, the `SHAPE*` parameters and `Shape(type)`.
- The writers, read only (Epic 30's files):
  - `Bridge/Approval.cls:485`, `Record("Approval")`;
  - `Fix/Executor.cls:487-527`, `ActionEntry`.
- `docker/tests/test-audit.sh:82-98` is the shell polling precedent. `docker/tests/lib-keys.sh:15-17` holds `KEY_LIKE_ERE` and `key_like`.

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)`
  - On the integrated tree, after `ci/iris.sh build`, run `ci/iris.sh live demo-path` once unchanged and record its seconds as the baseline.
  - On the first loop run of the new 02, read the mock log (`Test.Contract.Mock.LogMark()` before the message, then `LogSince(mark, .entries)`) and record:
    - the Triage request: `selectedBy` marker, reply index 0;
    - the turn: indexes 1 and 2;
    - the order of the two.
  - Record whether the README user opens Visual Trace already signed in.
  - Record the exact `{model}` text of the finish line.
- `ci/mock/scenarios/A/watch-act-orders.json` -- add a marker scenario with three replies:
  - reply 0: text `{"outcome":"act","reasons":["The CI mock acts on the request to watch the Orders production."],"confidence":0.92}`;
  - reply 1: `toolUse` `start_watch` `{"name":"Orders"}`;
  - reply 2: `watch-start-orders`' text.
  - It extends `watch-start-orders` with a first, Triage-shaped reply (a copy, for the reason in Design Notes).
- `web/e2e/support/demo-path.ts` -- new. It holds the UJ-1 locators, `Snapshot`, `readState` and `doneTurn`, moved word for word from the online spec, plus `WATCH_PROMPT` and `watchMessage(key)` -- Rule 2.
- `web/e2e-online/demo-path/demo-path.spec.ts` -- import the moved helpers and delete its local copies. No behaviour change.
- `web/e2e/support/devices.ts` -- add `armCountdown(marker, remaining)`. It calls `irisScript` → `Test.Contract.Mock.Arm` and throws unless the status is OK.
- `web/e2e/demo-path/02-watch.spec.ts` -- rewrite, with UTC and en-GB. `beforeAll` runs `pointKeys`. Then:
  - (a) the before-watch refusal;
  - (b) arm the countdown and send the marker message, then assert the strip, the check row, the active box and the guide (AC1);
  - (c) the real last run within 120 s (DW-202).
  - Drop Story 8.2's fixture block and the `notBuilt` calls.
- `web/e2e/demo-path/03-reminder.spec.ts` -- the step-2 button name becomes `/^Step 2, Reminder, (upcoming|current)$/` (DW-340). Delete the `afterAll` (the cancel and the restore). Update the doc comment.
- `web/e2e/demo-path/04-incident.spec.ts`:
  - The `@floor` test signs in the page and presses `app-break-feed-box app-server-button button`, capturing the POST with `page.waitForResponse`. Its HTTP checks go through `page.request`. The refusal and the seed go.
  - Add the AC3 card test (`describe` with the skip text; timeout 180 s). It relies on the keys that 02 pointed.
  - Delete the `@fixtures` test and the `notBuilt` calls.
- `web/e2e/demo-path/05-approval.spec.ts` -- replace everything with the AC4 test: a fresh sign-in, the DW-294 footer, Approve on the phone, the result texts, the row leaving, and the result `{total 50, completed 50, failedAgain 0}` in `/state`'s incident `requests`.
- `web/e2e/demo-path/06-trace.spec.ts` -- the AC5 test.
  - If Task 0 found that the tab asks for a sign-in, the test signs in there with the README account, as the popover says ("Sign in with your IRIS account if it asks"), filling the form the way `trace.ts`'s `signInToTrace` does.
  - Its `afterAll` runs `restoreKeys` and then `WaitRecords`, the code moved from 03.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- in `ChatItems`, an incident with a `DecisionRef` that the session owns gets `decision` (the `Live.Payload.Decision` payload object) beside `type` and `payload`, as `MailboxItems` does (DW-294). A failed read throws (`Check(sc)`).
- `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts` -- add an optional `decision` to the incident chat item. `fromSnapshot` adds each such decision to `decisions` after the rail's, unless that ref is already there (DW-294).
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- add `TestStateIncidentDecision`. The own diagnose decision is attached; an incident whose `DecisionRef` is empty, or another session's, gets none.
- `web/scripts/live-store.test.mjs` -- add a case: after `fromSnapshot`, an incident chat item's decision is in `decisions`, with no duplicate.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Check` sets `NextDueAt` = `Data.Time.AddSeconds(NowUtc(), ..#CHECKAHEAD)` before `SetFields`. `Parameter CHECKAHEAD = 3600`. The doc says that an explicit `""` makes the row due (DW-349).
- `src/ocutalon/cls/OcuTalon/Test/Data/FixtureDefaults.cls` -- new (Data area, shard lane-b). `TestCheckIsNotDue` pins both rows of the DW-349 matrix and cleans up its session and rows.
- `web/e2e/support/iris.ts` -- update the `seedCheck` doc (:840-845) to name the default. Replace the stale "as IncidentManager will" text at :160 if it describes 04 or 05.
- `web/scripts/demo-path-summary.mjs` -- add `--only-telegram-skips`:
  - `summarize(report, {onlyTelegramSkips})` fails a skipped test of a numbered step file with `<file> "<title>": skipped, but every web step runs since Story 11.1 (REL-2); only telegram-*.spec.ts parts may skip`;
  - `main` accepts `[--only-telegram-skips] <report>`;
  - update the header.
- `web/scripts/demo-path-summary.test.mjs` -- add the flag's red and green cases. Fix the stale `@fixtures` comment at :345, and keep the pins at :364-369.
- `docker/tests/test-demo-path.sh`:
  - take the audit mark before Playwright;
  - Playwright's budget becomes `remaining - 80`, reserving 60 s;
  - pass `--only-telegram-skips`;
  - after the summary, poll for up to `OCUTALON_AUDIT_POLL` (60 s, capped by the deadline) for the AC6 entries, then write one PASS or FAIL line per check;
  - update the header.
- `docker/tests/test-demo-path-gate.sh`:
  - the `dc` stub answers the audit `iris_script` calls from `GATE_AUDIT` canned `CHK|` lines;
  - the green report has no numbered-file skip, and keeps the telegram skips;
  - new red runs: a numbered skip; no Action entry; an extra member; a key-like value;
  - move the :277 window to the new budget.

**Acceptance Criteria:**
- **AC1 (step 2; REL-2, FR-23, UX-DR101; DW-202).** Given a fresh demo-path stack after 01, when 02 runs, then:
  - before the watch, Break the feed is inactive with its hint and Do step 1, and a press is refused 409 `not_watching` and sends nothing;
  - after the watch message, the reply's strip is Act, with no Fallback flag, its reason and its trace link;
  - the "Orders production" row shows, Break the feed is active, step 1 is done and step 2 is current;
  - within 120 s the row reads "Last run … · Passed" from the real heartbeat;
  - 02 holds no `notBuilt` call and no fixture block.
- **AC2 (step 3; DW-340).** Given step 1 done, when 03 runs, then the step-2 button is found as upcoming or current, the reply, the stretch row and "Step 2, Reminder, done" show, and no reminder is cancelled after it.
- **AC3 (step 4; FR-16, FR-24, FR-34, UX-DR101).** Given the watch and the pending reminder, when 04 presses Break the feed on the page, then the `@floor` checks hold and, within 90 s, the card, the phone, the rail, the guide and the reminder show what the matrix lists. 04 and 05 hold no `@fixtures` test and no hand-seeded row.
- **AC4 (step 5; FR-8, FR-25, UX-DR103, UX-DR104).** Given the pending request, when 05 presses Approve on the simulated phone, then the matrix's answered statuses, Fixing, "All 50 orders went through.", "Recorded in the IRIS audit log." and Resolved show in that order, the phone gets the result with no buttons, and the rail row leaves.
- **AC5 (step 6; AD-26, UX-DR47, UX-DR139, UX-DR140).** Given the resolved incident, when 06 presses Open the trace, then the sign-in dialog leads to a tab at `TRACE_PAGE` whose `SESSIONID` is the incident's diagnosis header id, Visual Trace draws that session, and the guide shows its finish line with `{model}` as Task 0 recorded it (the default, Claude Haiku 5.5).
- **AC6 (FR-9, AD-17).** Given the browser steps have ended, when `test-demo-path.sh` polls the audit log since its mark, then it finds the answered Approval entry and the resend's Action entry for the README session's request. Each holds exactly its shape and no key-like text. Otherwise one FAIL line per missing or bad entry.
- **AC7 (REL-2; integration: consumer `test-demo-path.sh`).** Given the unit's report, when the summary runs with `--only-telegram-skips`, then:
  - steps 2, 3, 4 and 6 read passed;
  - steps 1 and 5 read partly skipped only by `telegram-page` (12.4) and `telegram-approval` (12.7);
  - any skip in a numbered file fails the unit;
  - the hosted no-stack pins of `demo-path-summary.test.mjs:364-369` still pass.
- **AC8 (DW-294; integration: consumer the page's incident card).** Given an incident whose diagnose decision is the session's, when the page loads `/state`, then the chat item carries the decision, the store holds it, and in 05, after a fresh sign-in, the card's `.footer app-decision-strip` shows chip Act. An incident whose decision is empty or another session's carries none (`TestStateIncidentDecision`).
- **AC9 (DW-349).** Given `Fixture.Check` with no `NextDueAt` field, when a test seeds a row, then the row is due an hour ahead, `TestCheckIsNotDue` passes, and every caller class still passes (shards lane-b and lane-a, in parts).
- **AC10 (REL-4).** Given the changed demo path, when `live:demo-path` runs locally on a fresh stack, then it passes within its 540 s default deadline, and the baseline and final seconds are recorded under Verification. If the CI estimate (browser 26.6 min plus twice the local increase) passes 30 minutes, the implement stage adds a `deferred:` item for the orchestrator's rebalance (Clarification Needed 2) and changes no `ci/units.sh`.

## Spec Change Log

## Review Triage Log

### 2026-10-31 — Review pass
- verdicts: 30 findings — high 0, medium 2, low 20, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: Action entry not checked for action, result or counts.total — AC6 asks for the entry that names the request, in its shape and with no key-like text; its values are not in the AC, and the live writer refuses any other shape.
  - `[low]` `[reject]` Blind: only the first matching Approval entry is inspected — a fresh unit stack answers one request; a second answered entry would need a second press, which no step makes.
  - `[low]` `[reject]` Blind: audit polling path has no gate case (poll fixed at 0) — the poll is `wait_until` from lib-live.sh, and the live run reads after the browser steps; a counting stub would add complexity for a flake that has not been seen.
  - `[low]` `[reject]` Blind and Edge: the floor of 100 s with 80 s reserved leaves a small Playwright budget — a short budget fails the unit through the global timeout with a named failure either way; the spec fixes `remaining - 80`.
  - `[false]` `[reject]` Blind and Edge: key restoration only in 06's `afterAll` — the spec places it there on purpose, and the unit's stack is a throwaway torn down at the end.
  - `[low]` `[reject]` Blind and Edge: the `@floor` press in 04 depends on 02's watch with no named precondition — the journey is ordered by design (Decided in-stage), and a 409 `not_watching` is printed with its body by the test.
  - `[low]` `[reject]` Blind: `TestStateIncidentDecision` has no "names no row" case — `Ownership.Decision` answers "" for a missing row exactly as for another session's row, and that branch is the one the foreign case runs.
  - `[false]` `[reject]` Blind: the type comment says "diagnose decision" while any `DecisionRef` is attached — an incident's `DecisionRef` is its diagnose decision by construction (IncidentManager), and the AC reads the same.
  - `[false]` `[reject]` Blind: `fixing?.payload` could throw a TypeError — the preceding `arrayContaining(['fixing','resolved'])` expectation fails first when no fixing event exists.
  - `[medium]` `[reject]` Blind, Gap and Intent: "Fixing" is read from the session stream, not drawn on the page — measured, not a defect: the real fix ends in about a second, faster than one poll of the page, so the page goes from Awaiting approval to Resolved in one update; the texts stay pinned by `web/e2e/cards/incident-card.spec.ts` and `web/e2e/answers/close-loop.spec.ts`. The matrix row's expected observable is restated as reachable on the stream; reported under Auto Run Result as an amendment (Rule 5, apply and report) for the lead, not a change to the product.
  - `[false]` `[reject]` Edge: a Playwright retry re-sends the watch message in 02 — `retries: 0` in `web/playwright.config.ts:37`.
  - `[low]` `[reject]` Edge: 02's last-run regex accepts a "(late)" mark and no stalled-heartbeat banner is checked — the row is read within 120 s of the real heartbeat's run, and asserting the absence of "(late)" would add a CI-speed flake with no failure shown.
  - `[low]` `[reject]` Edge: callers of `Fixture.Check` that expected a due row (Watch/Poller) — the shards lane-a and lane-b parts passed with the default, and the new default is the spec's AC9; callers that need a due row pass `""`.
  - `[low]` `[reject]` Edge: `ChatItems` reads `Ownership.Decision` once per incident — the chat holds at most CHATMAX incidents and `MailboxItems` reads the same way.
  - `[low]` `[reject]` Edge: no `INFO` line when the audit mark is empty — the empty mark already prints a FAIL before the browser steps.
  - `[false]` `[reject]` Edge: an entry with a bad shape and key-like text draws two FAIL lines — the matrix lists the two conditions as separate failures, one FAIL line each.
  - `[low]` `[reject]` Edge: deleted "not late and no stalled banner" and "no reminder left in the rail" checks have no replacement, and `key_like` runs on the entry's data only (not its description) — each is a retired Story 8.2 fixture assertion or beyond AC6, which names the entry's data.
  - `[medium]` `[patch]` Gap: AC6's shape check has no mutation line — the stage ran the shape mutation live (SHAPEAPPROVAL without ownerRef: red, reverted byte-identical) and recorded the `mutation:` line; the writer refuses any other shape, so an extra member cannot be stored live, and the gate's `extra-approval` run pins that branch.
  - `[low]` `[reject]` Gap: the audit poll and its deadline cap are never exercised — same row as the Blind finding on the poll.
  - `[low]` `[reject]` Gap: order dependence of 03 to 06, and only 02 is serial — the journey is ordered by design (Decided in-stage); a failure ends the unit red either way.
  - `[low]` `[reject]` Gap: `TestStateIncidentDecision` does not assert the exact key set — it asserts the member is undefined, which is the contract.
  - `[low]` `[reject]` Gap: helpers have no host outside the live unit — they run in `live:demo-path` and `live:online-demo-path`, both green.
  - `[low]` `[reject]` Gap: no mutation for the refusal clause of 02 and the second-press refusal of 04 — both are `@floor`-pinned titles that the unit's floor count (7 of 7) checks, and 04's press test asserts the 409.
  - `[false]` `[reject]` Intent: the specs run in nothing the diff adds — they run in `live:demo-path`, the unit this story turns on.
  - `[false]` `[reject]` Intent: the audit read is not exercised against real IRIS — the live unit runs it, and the live mutation above makes it fail.
  - `[low]` `[reject]` Intent: AC4's Fixing is read at the stream (divergence 3) — same row as the Fixing finding above.
  - `[low]` `[reject]` Intent: AC10 is untested in the diff — it is measured: 147 s before, 219 s and 230 s after, inside the 540 s default.
  - `[low]` `[reject]` Intent: DW-294 reaches the browser only through 05's footer — that is the AC8 consumer, and `live-store.test.mjs` covers the store.
  - `[low]` `[reject]` Intent: DW-349 changes a shared default with no edits to other tests — the shards passed; a caller that wants a due row passes `""`.
  - `[false]` `[reject]` Intent: the mock path of the diagnosis is assumed — the live unit passes it end to end.

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-4 | the snapshot reads only the session's own decision |
| AD-12 | the snapshot, the store, the guide's server-derived steps and Break the feed |
| AD-15 | the watch, settle, diagnosis and incident chain |
| AD-17 | audit read back by polling |
| AD-18 | heartbeat, checks and reminders |
| AD-19 | no key in IRIS, a log or the trace; the mock-key header is CI-only |
| AD-20 | decisions and the run total |
| AD-22 | how the mock picks a scenario, the countdown, CI and REL-2 |
| AD-26 | the trace link opens the diagnosis session |
| AD-29 | Epic 11 may change either lane's files; the specs and runner config are Lane B's; `A/` scenarios are Lane A's |

No AC contradicts an AD. The Act strip on the mock is met within AD-22 through its marker countdown.

**Extend, don't copy (Rule 2).**
- The online spec's local helpers move to `web/e2e/support/demo-path.ts`, and both runs import them.
- `armCountdown` sits beside `pointKeys`.
- The audit check reuses `Test.Bridge.AuditLog`, `Bridge.Audit.Shape` and `lib-keys.sh`, following `test-audit.sh`'s polling.
- `ChatItems` follows `MailboxItems`.
- `A/watch-act-orders.json` copies `watch-start-orders`' two replies. A JSON scenario cannot extend another, and the countdown needs the Triage reply first, which an unarmed `watch-start-orders` must not have. That is the stated reason for the copy.

**Integration ACs and links (Rule 1/2).**
- AC7: the summary flag, consumed by the unit.
- AC8: the snapshot decision, consumed by the incident card after a load.

| Link | Who |
| --- | --- |
| Consumes | Lane A: WatchTools and WatchOps, Checks, FailurePoller, IncidentManager, Diagnosis, FixExecutor, Bridge.Approval and Bridge.Audit |
| Consumes | Lane B: Conversation, Notify, WebChatOut, SimPhoneOut, Demo.Guide, Web.Api and Web.TraceLink |
| Consumes | test helpers: `Test.Contract.Mock.Arm`, `Test.Agent.RunnerFixture` and `Test.Bridge.AuditLog` |
| Consumed-by | `web/e2e/support/demo-path.ts`: specs 02 to 06, the online run now, and Story 11.7 (failure paths, online steps 2 to 5) |
| Consumed-by | `--only-telegram-skips`: `test-demo-path.sh`, and Stories 12.4 and 12.7 when they turn the Telegram parts on |
| Consumed-by | the incident `decision` in `/state`: `live-store.ts` and the incident card |
| Consumed-by | the step specs: Story 11.3's rehearsal, which runs them from a driver host; their `docker exec` helpers are its concern |

**Ledger (Rule 17).**
- Addressed:
  - DW-202 (AC1);
  - DW-340 (AC2; its occurrence on 03's `afterAll` cancel is addressed too);
  - DW-294 (AC8);
  - DW-349 (AC9).
- Declined:
  - Declined DW-140: moved to Story 11.8 (split)
  - Declined DW-142: moved to Story 11.8 (split)
  - Declined DW-142 (live-check half): the real-key check belongs to Story 11.6's pass
  - Declined DW-221: moved to Story 11.7 (split)
  - Declined DW-307: moved to Story 11.7 (split)
  - Declined DW-316: moved to Story 11.8 (split)
  - Declined DW-376: moved to Story 11.9 (split)
  - Declined DW-396: moved to Story 11.9 (split)
  - Declined DW-415: moved to Story 11.9 (split)
  - Declined DW-433: moved to Story 11.7 (split)
- DW-415 and DW-433 are owned by this story on the feature ledger since Epic 29's merge, and arrive with the integrate-forward.
- DW-142's live check runs on the real model, which this unattended run never uses. Whichever story carries DW-142 changes the instruction lines and pins them on the CI mock. The live check itself is Story 11.6's.

**Contended paths (U14).**
- Every file this story changes is listed under Tasks.
- None belongs to Epics 15, 30, 12 or 13.
- The Epic 29 files among them (02-06, the online spec) are planned against its merged version.
- The one new file in a contended folder is `ci/mock/scenarios/A/watch-act-orders.json`. No contended file is appended to.

**CI budget (REL-4).**
- `live:demo-path` runs first in the `browser` group: 26.6 min on Epic 9's final head, about 1,580 s on Epic 29's layout.
- Added wall-clock waits: the heartbeat tick (≤ 60 s), settle and diagnosis (about 20 to 35 s), the fix (≤ 60 s), the trace and the audit read.
- Removed: three fixture tests and 8.2's block, about 30 s.
- Estimate: +2.5 to 4 min on CI, so browser at about 29 to 31 min (inference).
- No move is possible here:
  - `ci/units.sh` is contended by Epics 12, 13 and 15;
  - `production` takes only `NO_WEB_BUNDLE_UNITS`;
  - `image` (27.7) and `shards` (28.5) lack the 6 to 8 minutes that `live:answers` or `live:sign-in` need.
- So AC10 measures, and Clarification Needed 2 asks.

**Decided in-stage.**
- The demo path is one ordered journey ("passes in order", AC1 of the epics block). Its hermetic unit is the whole `live:demo-path` run on the unit's own throwaway. The standing criterion applies to the classes and node tests this story changes, and the browser journey is proven twice on fresh stacks rather than reversed.
- The `not_watching` refusal moves from 04 to the start of 02, the last moment with no watch. 01 stays unchanged, so its pinned floor titles hold.
- The reminder "lands during the wait" is asserted as "by the end of step 4". Its due time comes from step 3, and the incident's timing varies.
- The audit read runs in the unit script, not in a spec. `lib-keys.sh` is the one definition of key-like text, and TypeScript must not copy it.
- `/state` attaches the decision beside the incident payload, not inside it. The payload stays the entity's own view (AD-12), and payloads.ts is unchanged.
- Fixture check rows default to an hour ahead (`CHECKAHEAD`), through the fixture, never per call site.
- The real watch row's `.meta` reads "Last run {time} \u00B7 Passed \u00B7 Trace (opens in a new tab)": the heartbeat's run gives the row its Trace link, so 02 matches `/^Last run \S.* \u00B7 Passed( \u00B7 Trace \(opens in a new tab\))?$/`.
- The real fix ends in about a second, quicker than one poll of the page, so the page draws the card's Awaiting approval and then Resolved in one update and never draws Fixing. 05 reads the Fixing step from the session stream (`incident` events: state fixing, then resolved, the request approved or executing) and asserts the Resolved band, the audit line and the result in the DOM. The texts "Fixing" and "Repairing and resending 50 orders\u2026" stay pinned by the cards unit's fixtures, not here.
- The README user opens Visual Trace already signed in (Task 0), so 06 has no sign-in step.
- 02's `describe` is serial, so a failed step leaves the later parts of the file unrun (and reported as a failure, not a pass).


**Lead rulings at the spec gate (2026-10-31, unattended; these override anything above that disagrees).**
- The proposed split is accepted (decide, U5): Stories 11.7, 11.8 and 11.9 are in `epics.md` right after 11.1, with the moved criteria verbatim, and the moved ledger entries are re-owned to them (`by=spec_gate`). Story 11.1 keeps DW-202, DW-294, DW-340 and DW-349.
- Story 11.6 moved whole to Story 38.1 in a new Epic 38 (inbox U-189, decided by the Contest Planner under the owner's delegation). Read every "Story 11.6" above as Story 38.1; DW-142's live check runs in 38.1's real-key pass.
- Step 2's AD-22 route (the watch prompt through the composer behind a marker with an armed countdown) is accepted as a veto-window ruling (inbox U-190). The AD-22 amendment question goes to the orchestrator at Story 11.7's plan.
- `ci/units.sh` is shared by region in this run, not contended (the runner's spawn prompt): this story may edit its own entries and group lines, as a plain union at integrate-forward. It changes nothing there unless the browser group, measured on this story's CI run, passes 30 minutes; then the lead decides the move. After any `ci/units.sh` change the `docker/tests/test-ci-config.sh` pins are updated and `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh` run.
- Epic 29 has merged and Epic 11 has integrated the feature branch forward (merge `cda3e52c`), so the implement stage works on the merged tree, not on `origin/OCT-epic29`.

### Proposed split

The lead inserts the siblings into `epics.md`, in Epic 11, before Story 11.5's cut. Every moved item stays in release 0.1.0's scope.

**Story 11.7: The demo path's failure paths, quiet outcomes and online run pass in the REL-2 test.**
These are separate journeys with mock work of their own (a mock-key seam for the refusal, the coda's triage scenarios), and each adds browser time that needs its own rebalance plan.
- **Given** the test's failure-path scenarios
  **When** one rejects the request and another makes the mocked model refuse the diagnosis
  **Then** the rejection shows "Rejected from the simulated phone at {time}. Nothing was changed.", the incident returns to Open, Dismiss re-enables Break the feed and a replay opens a new incident with its own request; the refusal shows the fallback card with its failure groups and no fix, and step 5 still opens the trace (FR-4, FR-8, FR-16, FR-24, UX-DR104)
- **Given** the coda
  **When** the test presses "Sample: newsletter" and "Sample: suspicious request"
  **Then** the newsletter is decided Ignore with nothing on the phone, the suspicious request leads to no approval request, resend or setting change, and the whole test keeps a full CI run within 35 minutes [AMENDED 2026-10-20, owner decision 7] (NFR-14, REL-4, UX-DR105)
  - Reason: the coda is the UX's separate "quiet outcomes" journey.
- **Given** the demo-path test run against the real model (a release-candidate or rehearsal run) rather than the CI mock
  **When** it reaches a decision
  **Then** it checks that a decision with reasons and a trace link appears, never which outcome; specific outcomes, such as the Act strip on the watch step, are asserted only against the CI mock (REL-2, REL-5)
  - Reason: the switch must also make step 2 use the guide's Send instead of this story's mock marker.
- - DW-307: Under the CI mock a prompt-selected B scenario (e.g. guide-reminder.json) also answers the Triage request; Triage has no tools, so a guide-step chat turn's triage decision ends as an invalid fallback in the trace while the turn completes (ledger; routed by merge_gate 2026-10-28)
  - Reason: its fix needs an AD-22 ruling (Clarification Needed 1).
- DW-221 (ledger only): REL-2's online-demo run, steps 2 to 5, in `web/e2e-online/demo-path/demo-path.spec.ts` and `test-online-demo-path.sh`.
  - Reason: it is another unit, in `install-fresh`, at about 31 min, with its own budget plan.
- DW-433 (ledger only): `B/guide-watch.json` starts no watch.
  - Reason: it goes with DW-307, because the guide's Send is that story's question.

**Story 11.8: The chat cancels several reminders in one call and says it can set them.**
This is Lane A's chat reminder tools and their tests, an area apart from the demo path.
- - DW-140: Chat's ceiling of 4 iterations (AD-20) may be too low for a turn that lists and then cancels several reminders one call at a time; U-118 (kept by the owner): Lane A's cancel_reminder takes one or more reminder ids and sends one CancelReminder per id within one tool call, each with its own IdempotencyKey, with no AD-20 change; Story 11.6 runs the live check (DW-358) (ledger; routed by merge_gate 2026-10-28)
  - Reason: Lane A tool change.
- - DW-142: Chat's INSTRUCTIONS still tell the model to answer a request to run a command with 'I can't run commands' and call no tool, and name no reminder ability, though Chat now has the reminder tools; U-118 (kept by the owner): Chat's instruction lines say Chat can set, list and cancel reminders and keep the no-commands rule for the rest, and a live check on Claude Haiku 5.5 with the guide's exact step-2 sentence plus two paraphrases, on the online demo's model, effort and endpoint, passes before 0.1.0 is cut (ledger; routed by merge_gate 2026-10-28)
  - Reason: the instruction lines are pinned on the mock; the live check is Story 11.6's.
- DW-316 (ledger only): one shared agent-step checker in `Test.Agent.RunnerFixture`, used by `Test.Schedule.ReminderChat` and `Test.Tools.Reminders`.
  - Reason: same test area.

**Story 11.9: Every check left off for release 1 turns on, and the CI flakes are fixed.**
This is test-only work in Core, Web, Schedule and the CI checks, apart from the demo path.
- The clause half of this paragraph moves. Story 11.1 keeps "this story turns on every step spec still skipped except Telegram's" and the AD-29 permission.

  **And** this story turns on every step spec still skipped except Telegram's, and every check left off by a "turns on when … merges" clause in Epics 0 to 10, except a check that such a clause leaves for a story in Epic 30 or 31, which that story turns on [AMENDED 2026-10-20, owner decision, relayed by the Contest Planner] (for example Story 1.12's `OutcomeRouter` path, Story 2.10's no-key test, and the fixture paths of Stories 2.7, 2.8, 2.9 and 4.6), and may change either lane's files to make the whole web demo path pass end to end, serialized by the orchestrator against any epic whose files overlap (AD-29)

  - Inventory at plan time (11.9's plan re-checks it):
    - still off: Story 1.12's stored digest row through OutcomeRouter (`Test.Core.RoutingProduction`), Story 2.8's expired and cancelled approval events (`Test.Core.AnswersInProduction`), Story 2.9's Decide double (`Test.Core.ThreadProduction`, `Test.Core.DecideDouble`), Story 6.4's IncidentManager double (`Test.Web.DismissApi`, `web/e2e/answers/close-loop.spec.ts`), and Story 10.3's R2b (`web/e2e-online/resume.spec.ts:187`);
    - already on: Stories 2.7, 2.10, 4.5, 4.6 and 8.4's clauses;
    - stale "until Epic 11" text in `Test/Install/Registry.cls`, `Test/Bridge/Fallback.cls` and `release/demo-host-checks.md`.
  - Reason: test-only work in other areas.
- DW-376, DW-396, DW-415 (ledger only): the `Test.Schedule.Heartbeat` RunNow ceiling, `test-ci-warm.sh`'s 1 s lock wait, and the sign-in helper's `ERR_NETWORK_CHANGED` retry.
  - Reason: CI flakes outside the demo path.

## Clarification Needed (non-blocking: the plan does not depend on the answers)

1. **AD-22 and the guide's own prompts (DW-307, DW-433).**
   - **The problem.** Under AD-22 the mock cannot give the Triage request and the turn of the same guide prompt different replies:
     - both have `k` = 0;
     - a prompt match comes before the mock key;
     - countdowns are keyed by marker (`mock.mjs:24-37`, `:451-462`).
   - **What this plan does.** Step 2 on the CI mock sends the watch prompt behind a marker with an armed countdown, not through the guide's Send. That is compliant (U7 step 1).
   - **Recommended amendment.** It is for the orchestrator. U7 (c) makes any AD-22 amendment a re-architecture, because done specs cite AD-22, so the owner decides: "A guide-prompt scenario under `B/` may also name the mock key of the agent it answers (`match: {prompt, mockkey}`). It then answers only requests with that key, and any other request falls through to the mock key."
   - **If adopted,** Story 11.7 switches step 2 to the guide's Send, and fixes DW-307 and DW-433.
2. **Browser group budget.**
   - **The estimate.** 29 to 31 min after this story (inference).
   - **Why this story moves nothing.** No group has room for a whole browser unit, and `ci/units.sh` is contended.
   - **What happens next.** If Epic 11's CI run on this story's head measures `iris (browser)` over 30 min, the rebalance is the orchestrator's or the Contest Planner's: the eighth-group rule. Nothing changes until then.

## Verification

`<A>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`. QA and review use their own stage names and tags (`e11s1q`/`e11s1qw`, `e11s1c`/`e11s1cw`).

**Run discipline:**
- Run everything from the epic-11 worktree root, after the integrate-forward of the feature branch (Epic 29).
- Each command runs in the foreground of its own call, with `timeout: 600000`. `ANTHROPIC_API_KEY` stays unset.
- One test call per message. Never re-submit after a client-side timeout.
- Pass `server` `ocutalon-slot-a` and namespace `OCUTALON` on every IRIS MCP call.

**Shared surfaces:**
- `Test.Data.Fixture.Check`'s `NextDueAt` default, used by 23 IRIS test classes and every e2e `seedCheck`. A test that compares a seeded check payload whole now sees `nextDueAt`, so search the test trees for it.
- `/state`'s chat incident item, which gains `decision`. Search the tests that compare chat items whole.
- The README session's state across the demo-path files.
- The runners' keys: pointed for the run, restored at its end.
- `ci/mock/scenarios/A/` gains one marker scenario. The mock tests count none.
- `demo-path-summary.mjs`'s command line, used by `test-demo-path.sh` and the gate.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.
- Covered this way: `Test.Data.FixtureDefaults`, `Test.Web.Api`, the node tests, and the gate's runs.
- The demo-path project is one ordered journey (Decided in-stage). Its evidence is two passing fresh `live:demo-path` runs.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-a` -- expected: build 154U, port 1990.
  - Then load and compile there `Web/Api.cls`, `Test/Data/Fixture.cls`, `Test/Data/FixtureDefaults.cls` and `Test/Web/Api.cls` -- expected: they compile. Run no test on the slot.
- (once) `<A> OCUTALON_RUN_TAG=e11s1i ci/iris.sh build` -- expected: the image and the web bundle build.
- (once) `<A> OCUTALON_RUN_TAG=e11s1b ci/iris.sh live demo-path`, on the tree before any change -- expected: as today; record its seconds (Task 0 baseline).
- (loop) `<A> OCUTALON_RUN_TAG=e11s1i ci/iris.sh build`, after each change under `web/src` -- expected: builds.
- (loop) `<A> OCUTALON_RUN_TAG=e11s1i ci/iris.sh live demo-path` -- expected:
  - steps 2, 3, 4 and 6 passed, and steps 1 and 5 partly skipped by the Telegram parts only;
  - `DEMO-PATH 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed`;
  - the audit PASS lines and `test-demo-path: all checks passed`;
  - record the final seconds.
- (once) `<A> OCUTALON_RUN_TAG=e11s1i ci/iris.sh live online-demo-path` -- expected: 3 passed, 7 skipped, as before the helper move.
- (once) `<A> OCUTALON_RUN_TAG=e11s1iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`.
- (loop) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s1iw ci/iris.sh class OcuTalon.Test.Web.Api` -- expected: `CLASS ... passed`.
- (loop) the same for `OcuTalon.Test.Data.FixtureDefaults` -- expected: passed.
- (once) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s1iw ci/iris.sh shard lane-b --part k/3`, for k = 1, 2, 3, each in its own call -- expected: every class passed.
- (once) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s1iw ci/iris.sh shard lane-a --part k/4`, for k = 1 to 4, each in its own call -- expected: every class passed. These and the lane-b parts cover the `Fixture.Check` callers. If warm mode refuses `--part`, run the same parts fresh with `OCUTALON_RUN_TAG=e11s1i` and no `OCUTALON_WARM`; each then starts its own stack, about 90 s.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, the summary and the live store included.
- (loop) `bash docker/tests/test-demo-path-gate.sh` -- expected: all runs as pinned.
- (once) `bash docker/tests/test-mock.sh` -- expected: passes, and the new scenario loads.
- (once) `bash docker/tests/test-web-build.sh` -- expected: passes.
- (once) `bash ci/checks.sh` -- expected: every block passes (`boundaries`, `class-rules`, `storage`, `demo-path-gate` and `ci-config` included).
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=e11s1iw ci/warm.sh down`, then `<A> OCUTALON_RUN_TAG=e11s1i ci/iris.sh teardown` and `<A> OCUTALON_RUN_TAG=e11s1b ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-a folder.

**Planned mutations (Rule 19).** For each one: apply it, observe red, revert, check that `git status --short` and `git diff --stat` are unchanged, then see green again. Mutations whose reds land in different step files, and do not cascade, may share one `live demo-path` run. Record each as a `mutation:` line here.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `A/watch-act-orders.json` reply 0's outcome `act` → `digest` | 02 on the chip Act |
| AC1 (DW-202) | `Watch/Ops.cls:97` `NextDueAt` = `CreatedAt` + 1 day | 02's real last run |
| AC2 | `Demo/Guide.cls:97`: step 2's done flag ignores the reminder | 03 on "Step 2, Reminder, done" |
| AC3 | `Core/Rule/Notify.cls` drops SimPhoneOut for kind incident | 04 on the phone notice |
| AC4 | the page's text for "All 50 orders went through." altered (web catalog) | 05 on the band |
| AC5 | `Demo/Guide.cls:126-129` trace target from the latest turn instead of the incident | 06 on `SESSIONID` |
| AC6 | the gate: no canned Action entry; live: the mark set one hour ahead | FAIL lines for the missing entries |
| AC7 | 06's test re-declared `notBuilt(..., '11.1')` | live unit FAIL on the numbered skip; the node test's red case |
| AC8 | `ChatItems` attaches no `decision`; `fromSnapshot` ignores chat decisions | `TestStateIncidentDecision`; `live-store.test.mjs`; 05's footer |
| AC9 | `Fixture.Check` without the `CHECKAHEAD` default | `TestCheckIsNotDue` |

**Recorded by the implement stage (2026-10-31, lane A, slot A not used for tests):**
- Task 0 baseline: `live demo-path` on the integrated tree before any change: 147 s (exit 0; 12 passed, 9 skipped).
- Final: `live demo-path` after the last change: 230 s (an earlier green run took 211 s); 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7; the six audit PASS lines. Increase: 83 s. CI estimate: 26.6 min + 2 x 1.4 min = 29.4 min, under 30, so no `deferred:` item and no `ci/units.sh` change.
- Task 0, the mock log of the watch message (marker `watch-act-orders:<key>`): the Triage request (no tools) is selected by the marker with k = 0 and gets reply 0 (the countdown 1 to 0); the turn's first request (k = 0) gets reply 1 (`start_watch`) and its second (k = 1, after the tool result) reply 2 (the text). The Triage request comes first, then the turn. The mock log's `step` is k, not the reply index.
- Task 0, Visual Trace: the README user opens it already signed in (no sign-in form).
- Task 0, the finish line: `This run: {n} decisions \u00B7 {tokens} tokens \u00B7 {cost} on Claude Haiku 5.5.` (observed: 5 decisions, 16,946 tokens, $0.0018).
- Other runs: `live online-demo-path` 3 passed, 7 skipped (171 s). Warm: `Test.Web.Api` and `Test.Data.FixtureDefaults` passed; shards lane-b 1/3, 2/3 and 3/3 and lane-a 1/4 to 4/4 passed. Two warm runs of lane-b part 3 failed on a warm stack that earlier parts had used (`Test.Web.GuideApi` `TestRunAgain`, then `Test.Web.DismissApi` `TestBreakFeedAvailableAgain`: instance incidents of the Orders production left by earlier classes are visible to a watching fixture session); `DismissApi` passed on a fresh stack, and part 3 passed on a fresh warm stack. `npm --prefix web run lint`, `npm --prefix web test` (1134 tests), `test-demo-path-gate.sh`, `test-mock.sh`, `test-web-build.sh` and `ci/checks.sh` passed.

**Mutations (Rule 19), each applied, observed red, reverted with `git status --short` and `git diff --stat` unchanged (a fingerprint of the diff and the untracked files compared equal), and green again:**
- mutation: AC1 `A/watch-act-orders.json` reply 0's outcome `act` to `digest` -> 02 "the watch prompt gets its Act reply" red on the chip (Received "Tell now").
- mutation: AC1 (DW-202) `Watch/Ops.cls:97` `NextDueAt` = `CreatedAt` + 1 day -> 02 "a real last run from the heartbeat" red after 120 s.
- mutation: AC2 `Demo/Guide.cls:97` step 2's done flag fixed at 0 -> 03 red on "Step 2, Reminder, done" (04 and 06 red too on the guide steps).
- mutation: AC3 `Core/Rule/Notify.cls` drops SimPhoneOut in the demo-mode rule -> 04 red on "the simulated phone has the incident notice" (05 and 06 cascade).
- mutation: AC4 `approval-view.ts` result text "went through" to "went thru" -> 05 red on the band "All 50 orders went through.".
- mutation: AC5 `Demo/Guide.cls:128` trace target from the newest turn instead of the incident -> 06 red on the link's SESSIONID (49 expected, 23 received).
- mutation: AC6 gate: no Action entry in the canned log -> FAIL "no Action entry that names the approval request" (`test-demo-path-gate.sh`); live: the mark one hour ahead -> FAIL "no answered Approval entry ..." and FAIL "no Action entry ..." from the live unit.
- mutation: AC6 (shape) `Bridge/Audit.cls` `SHAPEAPPROVAL` without `ownerRef`, run live on a fresh stack -> FAIL "no answered Approval entry ..." and FAIL "no Action entry ..." (the writer, `Audit.Record`, refuses any entry of another shape, so no live mutation can store an extra member; the unit's extra-member branch is pinned by the gate's `extra-approval` run). Reverted from the stage's own backup, tree byte-identical; the unmutated run is green.
- mutation: AC7 a `notBuilt(..., '11.1')` appended to 06 -> the live unit FAIL "06-trace.spec.ts ... skipped, but every web step runs since Story 11.1"; the node test's red cases (`demo-path-summary.test.mjs`, "--only-telegram-skips") and the gate's `numbered-skip` run pin it.
- mutation: AC8 `ChatItems` attaches no decision (`If 0 {`) -> `TestStateIncidentDecision` red ("carries it"); `fromSnapshot` ignoring chat decisions -> `live-store.test.mjs` red; and 05 red on the footer ("the footer finds the incident's diagnosis decision after the load").
- mutation: AC9 `Fixture.Check` without the `CHECKAHEAD` default line -> `TestCheckIsNotDue` red ("is -5864354445" seconds ahead).
- mutation: AC4 (QA, the Fixing clause the lead moved to the session stream, U-192) `Watch/IncidentManager.cls` `Move` publishes no incident event when `to` is fixing -> 05 red on "the incident went through Fixing to Resolved" (the page steps before it passed); reverted from QA's own backup, `git status --short` and `git diff --stat` unchanged (clean), and the unmutated `live demo-path` run is green (232 s, 6 of 6 steps ran, floor 7 of 7, six audit PASS lines).
- (QA) Re-checked, no test added or changed: every other `mutation:` line above names a test that still exists (02, 03, 04, 05, 06 titles; `TestStateIncidentDecision`, `TestCheckIsNotDue`, `live-store.test.mjs`, `demo-path-summary.test.mjs`, the gate's runs); `npm --prefix web test` 1134 passed and `test-demo-path-gate.sh` all checks passed on the QA tree. AC10 is a measurement (147 s to 230 s, above), not a test. QA test files created or changed: (none).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The web demo path now runs steps 2 to 6 on real components on the CI mock as one ordered journey, with the audit log read back after the browser steps. `/state` carries each incident's diagnosis decision (DW-294), fixture check rows are seeded an hour ahead (DW-349), and the unit's summary fails on any skip outside Telegram's parts.

**Files changed.**
- `web/e2e/demo-path/02-watch.spec.ts` to `06-trace.spec.ts`: the real-component step specs (02 watch on an Act marker, 03 reminder, 04 incident card, 05 approval, 06 trace and finish line; 06 restores the keys).
- `web/e2e/support/demo-path.ts` (new), `web/e2e/support/devices.ts`, `web/e2e/support/iris.ts`, `web/e2e-online/demo-path/demo-path.spec.ts`: shared helpers, `armCountdown`, the online spec importing the moved helpers.
- `ci/mock/scenarios/A/watch-act-orders.json` (new): the marker scenario.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`, `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts`: the incident `decision` on `/state` and in the store.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`, `Test/Data/FixtureDefaults.cls` (new), `Test/Web/Api.cls`, `web/scripts/live-store.test.mjs`: the tests.
- `web/scripts/demo-path-summary.mjs` and its test: `--only-telegram-skips`.
- `docker/tests/test-demo-path.sh`, `docker/tests/test-demo-path-gate.sh`: the audit read, the budget and the gate's runs.

**Review.** 30 findings: 1 patched (the AC6 shape mutation line, with a live mutation run), 0 deferred, 29 rejected with the reasons in the triage log.

**Follow-up review recommended:** false.

**Verification.** `live demo-path` 219 s on the last run (147 s before; 6 of 6 steps ran, 2 partly skipped, 0 failed; floor 7 of 7; six audit PASS lines); `live online-demo-path` 3 passed, 7 skipped; `Test.Web.Api` and `Test.Data.FixtureDefaults` passed warm; shards lane-b 1/3 to 3/3 and lane-a 1/4 to 4/4 passed; lint, `npm test` (1134), the gate, `test-mock.sh`, `test-web-build.sh` and `ci/checks.sh` passed. CI estimate for the browser group 29.4 min, so no `deferred:` item and no `ci/units.sh` change.

**Residual risks and items for the lead.**
- Amendment proposed (Rule 5, apply and report): the matrix row of step 5 and AC4 name the chip "Fixing" with "Repairing and resending 50 orders\u2026" as shown on the page. The real fix ends in about a second, quicker than one page poll, so the page never draws it; 05 reads the Fixing step from the session stream (`incident` events fixing, then resolved) and the texts stay pinned by `web/e2e/cards/incident-card.spec.ts` and `web/e2e/answers/close-loop.spec.ts`. The product promise is unchanged.
- The Last-run regex in 02 also accepts the real row's Trace link suffix (Decided in-stage).
- Two warm-stack runs of lane-b part 3 failed on state left by earlier parts (`Test.Web.GuideApi` `TestRunAgain`, `Test.Web.DismissApi` `TestBreakFeedAvailableAgain`); both passed on a clean stack. CI runs every shard fresh.
- The browser group sits near the 30-minute line (estimate 29.4 min); the lead measures it on this story's CI run.
