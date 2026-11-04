---
title: 'Story 11.7: The demo path''s failure paths, quiet outcomes and online run pass in the REL-2 test'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '7347be00b737801f4612959cf85ddf22df5785b1'
baseline_commit: '7347be00b737801f4612959cf85ddf22df5785b1'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Under the CI mock the guide's own prompts cannot drive UJ-1:
- `B/guide-watch.json` answers Chat with text only, so the guide's watch Send starts no watch (DW-433).
- Every prompt scenario also answers the Triage request, which has no tools, so a guide turn's triage decision ends as an invalid fallback (DW-307).

So Story 11.1 sends step 2 through the composer behind a marker, and the online run's steps 2 to 5 are still `notBuilt(..., '11.1')` (DW-221). Nothing yet lets the step specs run on the real model without asserting the mock's outcomes.

**Approach:** Build the AD-22 amendment of 2026-10-31 (U-194): a `B/` prompt scenario may name the mock key of the agent it answers.
- Each guide prompt gets a Chat scenario and a Triage scenario of its own.
- Both runs send step 2 through the guide's own Send.
- The online run's steps 2 to 5 run as one journey, through step functions shared with the web run.
- A real-model switch keeps the outcome checks to the CI mock.
- Two CI units swap groups to make room for the longer online unit.

The failure paths and the coda move to a sibling, Story 11.10 (Design Notes, Proposed split).

## Boundaries & Constraints

**Always:**
- **The mock's selection order (AD-22 as amended, U-194):**
  1. the marker;
  2. else the one `B/` prompt scenario whose prompt the newest user text contains and whose `mockkey` is either absent or equal to the request's `x-ocutalon-mockkey`;
  3. else the mock key's default script;
  4. else a 500.

  A prompt scenario without `mockkey` behaves as today. This is CI-mock-only: nothing a judge runs changes.
- **Backward compatible.** Every existing scenario file loads and answers as it does today. The countdown, markers, summaries, the Telegram side and the log's shape do not change.
- **The guide prompts on the mock:**
  - `B/guide-watch.json` gets `mockkey: chat`. Reply 0 is `start_watch` `{"name": "Orders"}`; reply 1 is the text "I'll watch the Orders production and stay quiet unless something needs you.".
  - `B/guide-watch-triage.json` (new) has `mockkey: triage` and the text `{"outcome":"act","reasons":["The CI mock acts on the request to watch the Orders production."],"confidence":0.92}`.
  - `B/guide-reminder.json` gains `mockkey: chat`. Its replies do not change.
  - `B/guide-reminder-triage.json` (new) has `mockkey: triage` and the text `{"outcome":"act","reasons":["The CI mock acts on the request to set a reminder."],"confidence":0.9}`.
- **Step 2 goes through the guide.** The web run and the online run press the guide's own Send for step 1 (`guideSend`). The Act strip still shows on the mock (lead ruling; U-190).
- **Extend, don't copy (Rule 2).** The checks of steps 2 to 5 live once, as functions in `web/e2e/support/demo-path.ts`. The web run's 02 to 05 and the online run call them.
- **The real-model switch, `OCUTALON_DEMO_PATH_MODEL`:**
  - Its values are `mock` (also when unset) and `real`. Any other value throws when `demo-path.ts` loads.
  - At each decision the specs reach (02's watch reply, 03's reminder reply and 05's incident footer), `expectDecision` checks one strip with an outcome chip that has text, no Fallback flag, at least one `.reason` with text, and one trace link.
  - On `mock`, the specs also check the outcome and every text that the CI mock writes.
  - On `real`, the specs never call `pointKeys`, `restoreKeys` or `RunnerFixture.WaitRecords`.
- **Mock only.** `ANTHROPIC_API_KEY` stays unset, and the real model is never run.
- **Text oracles (Rule 14).**
  - Page texts are written out in the specs, with non-ASCII characters as `\u` escapes.
  - Stale comments are replaced: the marker route, "a fallback under the CI mock", and "steps 2 to 5 wait for Story 11.1".

**Never:**
- **Out of bounds:**
  - product code (`src/` outside `OcuTalon.Test.*`, and `web/src/`);
  - `docker/tests/lib-live.sh` and `release/demo-load.sh`;
  - any file that Epics 15, 30, 12 or 13 change. The one exception is `ci/units.sh`, which is shared by region: this story changes its `install-fresh` and `image` group lines and the layout comment, and nothing else there.
- **No new mock state.** Nothing is remembered by mock key or by prompt.
- **Scope out:** the failure paths, the coda and their scenarios (Story 11.10), and the Telegram parts.
- **Wrong targets:** a test on slot A or another lane's slot, `ocutalon-aihub-test`, or a real key. The spine is not edited.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Keyed prompt, its key | The text holds prompt P, with header `chat`. `B/x-chat` is `{prompt P, mockkey chat}` and `B/x-triage` is `{prompt P, mockkey triage}`. | `x-chat` answers, `selectedBy` prompt, by today's reply rule. | No error expected |
| Keyed prompt, another agent | The same text, with header `triage`. | `x-triage` answers. | No error expected |
| Keyed prompt, no scenario for that key | The same text, with header `diagnosis`. | It falls through to the `diagnosis` default script, `selectedBy` mockkey. | No error expected |
| Keyed prompt, no header | The same text, with no header. | It falls through, and there is no key. | Today's 500 `no-scenario` |
| Marker beside a keyed prompt | The text holds P and `[[mock:refusal]]`. | The marker wins. | No error expected |
| Keyless prompt (as today) | `B/g` is `{prompt Q}`; any header. | `g` answers every agent. | No error expected |
| Loader: keyed prompt under `A/` | the file | "a prompt scenario belongs under B/" | The load fails. |
| Loader: one prompt text twice | The same key twice, or one of the two has no key. | A problem that names both files. | The load fails. |
| Loader: other pairs | `{marker, mockkey}`, `{mockkey, telegram}`, three keys, or an empty or white-space key | Only `prompt` may pair with `mockkey`. | The load fails. |
| Loader: a valid keyed prompt | the file | It is in `prompts` with its key and not in `byMockKey`. `constants.test.mjs` row 16 still finds one default script per agent. | No error expected |
| Web step 2 (DW-433) | A fresh stack after 01, in mode mock | After the guide's Send at step 1:<br>- The user message is the exact prompt, captioned "From the demo guide".<br>- The strip passes `expectDecision`, with chip Act and the reason "The CI mock acts on the request to watch the Orders production.".<br>- The reply reads "I'll watch the Orders production and stay quiet unless something needs you.".<br>- The "Orders production" row shows, and Break the feed is active.<br>- The guide reads "Step 1, Watch, done" and "Step 2, Reminder, current".<br>- The last run shows within 120 s. | No error expected |
| Web step 3 (DW-307) | After 02 | As today. The reply's strip passes `expectDecision`, with chip Act and the reason "The CI mock acts on the request to set a reminder.". | No error expected |
| A guide prompt's triage (IRIS) | Kind decide, provenance user, and a guide prompt as the input | One mock request, `selectedBy` prompt, with scenario `guide-watch-triage` or `guide-reminder-triage`. The answer is no fallback, with outcome act. | No error expected |
| Online steps 2 to 5 (DW-221) | A flag-on throwaway, with one visitor from the splash | Steps 2 and 3 run as in the web run, with no last-run wait.<br>Step 4: the incident card awaits approval, with the phone's notice and "Approval requests, 1".<br>Step 5: Approve on the phone, then "Approved from the simulated phone at …", "All 50 orders went through.", "Recorded in the IRIS audit log." and Resolved, and the rail row leaves. | No error expected |
| Online report | The unit with no arguments | 7 cases pass (steps 1 to 6 and the second visitor), and 3 skip with "Story 31.4 turns this on". 10 cases in all. | One FAIL line per defect |
| Real mode | `OCUTALON_DEMO_PATH_MODEL=real` | Each decision gets `expectDecision` only. The texts that carry model output are matched by their shape (Tasks). The specs make no key call. | No error expected |
| Real-mode dry run | `live demo-path` with `real`, on the CI mock | The unit prints `MODEL real: a dry run on the CI mock`. It points the runners' keys before Playwright, and the same steps pass. | No error expected |
| Unknown mode | `OCUTALON_DEMO_PATH_MODEL=zz` | The run fails before any step, with `OCUTALON_DEMO_PATH_MODEL is mock or real, not "zz"`. | Playwright reports the error, and the unit is red. |

</intent-contract>

## Code Map

The line numbers are those of `OCT-epic11` at `13cbd77f`.

**The mock (Lane B's code; changed under AD-29's Epic 11 exception)**
- `ci/mock/mock.mjs`:
  - :24-38 is the header (the selection order and the reply rule). It gets the keyed-prompt step.
  - :419-449 is `select`, with the prompt hits at :440-444 and the mock key at :445-447. The hits are now filtered by `match.mockkey` against `headers[MOCKKEY_HEADER]`.
  - :451-463 is `pickReply`, which does not change.
- `ci/mock/scenarios.mjs`:
  - :9-12 is the format doc.
  - :186-206 is `checkScenario`'s match check, which today requires exactly one key.
  - :279-287 registers every match that has a `mockkey` in `byMockKey`. A keyed prompt must not go there, because it would collide with `A/triage.json`.
  - :288-296 refuses a repeated prompt text.
  - :300-306 is the containment check. Its `includes` is true for an identical text, so identical texts must be excluded.
- The tests:
  - `ci/mock/test/server.test.mjs`: :45-46 hold the `GUIDE_ONE` and `GUIDE_TWO` fixtures, :274-303 row 7, :305-326 row 8 (the default script) and :804-830 row 7 (the newest user text).
  - `ci/mock/test/scenarios.test.mjs`: the bad-file rows are at :71-75 and :116, and the good tree at :145-150.
  - `ci/mock/test/constants.test.mjs`: row 16 is at :70-80, with the loop at :87. Its count `Object.hasOwn(s.match, 'mockkey')` breaks once keyed prompts exist, so it has to count matches whose only key is `mockkey`.
  - `docker/tests/test-mock.sh:16` runs them all (`node --test ci/mock/test/*.test.mjs`).
- The scenarios:
  - `ci/mock/scenarios/B/guide-watch.json` (text only today) and `B/guide-reminder.json`;
  - `A/watch-start-orders.json`, whose two replies the new guide-watch copies;
  - `A/triage.json`, the triage default (digest);
  - `A/watch-act-orders.json`, Story 11.1's marker scenario, which goes.
- `web/scripts/guide-view.test.mjs:211-219` reads `scenario('guide-watch').match.prompt`. It stays green.

**IRIS tests (shard lane-b, CI group `image`)**
- `src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls`:
  - :1-14 is the doc; :84-92 `TestWatchPrompt`, which today wants 1 request and the text reply; :94-112 `TestReminderPrompt`; :125-145 the `Turn` helper.
  - The tests send through `RunnerFixture.NewRequest(kind, provenance, input)` (`Test/Agent/RunnerFixture.cls:279`) and `Run` (:381).
  - Their owner is a fresh Ref, so a tool answers that no session owns the turn and writes nothing.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls`:
  - :7-9 is the doc; :259-290 is `TestGuidePromptSetsReminder`; :165-174 is `AssertChat`, which counts Chat's requests only.
  - `Data/Turn.cls:73-79` (`ShownDecisionRef`): the strip shows the triage decision unless the reply fell back.
  - `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` holds `Kind` (:12), `Outcome` (:24), `Fallback` (:33) and `FallbackReason` (:36).

**The shared helpers**
- `web/e2e/support/demo-path.ts`:
  - :15-24 are the locators (`guideSend` is :15);
  - :47-61 is `doneTurn` and :63 `WATCH_PROMPT`, which both stay;
  - :65-73 is `watchMessage` and its doc, which go.
  - The mode, `expectDecision` and the step functions are added here.
- `web/e2e/support/devices.ts`: :179-189 holds `pointKeys` and `restoreKeys`. `armCountdown` (:191-200) goes, because it has no caller left.
- `web/e2e/support/floor.ts`: `CARD_MS` (:38), `replyOf` (:53) and `signInReadmeLoaded`.
- The strip's DOM:
  - `web/src/app/chat/decision-strip.ts:55-100`: the chip, `app-fallback-flag`, the trace link inside `.meta`, and `p.reason`;
  - `web/src/app/incidents/incident-card.ts:150-165`: the footer strip, with reasons and the diagnosis trace link;
  - the locator precedent is `web/e2e/chat/decision.spec.ts:93-139`.

**The web run**
- `web/e2e/demo-path/02-watch.spec.ts`: the imports are at :1-7, the doc at :14-30, `beforeAll` at :35-38 and the watch test at :56-80 (the countdown, the marker and the composer). The refusal test (:40-54) and the last-run test (:82-88) stay.
- `web/e2e/demo-path/03-reminder.spec.ts`: the stale doc is at :12-13, `beforeAll` `pointKeys` at :21-24, and the mock's reply text at :43.
- `web/e2e/demo-path/04-incident.spec.ts`: the card test's `describe` is :71-111. Its mock-only texts are the cause :89, the evidence line :90, the count :95 and the button names :97-98 and :102-104. The `@floor` press test (:21-63) keeps its title, which `web/scripts/playwright-projects.test.mjs:148-158` pins.
- `web/e2e/demo-path/05-approval.spec.ts`: the footer chip is at :35-37, the band at :62 and the `/state` result at :84-85.
- `web/e2e/demo-path/06-trace.spec.ts:62-70` is the `afterAll` that restores the keys.
- `web/scripts/demo-path-summary.test.mjs:364-370` pins the no-stack run. The skip texts stay, so it holds.

**The online run (Epic 29's merged files)**
- `web/e2e-online/demo-path/demo-path.spec.ts`:
  - :29-43 is the doc;
  - :45-46 is `WATCH_MESSAGE` and :100-105 `askToWatch` (the marker workaround of DW-433);
  - :121-124 are the four `notBuilt(..., '11.1')` calls;
  - :126-163 is step 6. Its guide Send now starts a watch, and its `finally` already runs `cleanPopulated`, which deletes the session's `BackgroundCheck` rows;
  - :165-300 is the second visitor, with its `askToWatch` calls at :186-187.
- `web/e2e-online/support.ts`: `removeSession` (:202), `openVisitor` (:230), `leaveVisitor` (:250) and `cleanPopulated` (:556).
- `docker/tests/test-online-demo-path.sh`:
  - :1-28 is the header;
  - :98-143 is `report_check` (3 passed, 4 skipped of 11.1 and 3 of 31.4), and :164-169 its PASS and FAIL texts;
  - :186-200 is `load_script`, whose `OCUTALON_LOAD_WATCH_TEXT` marker override is at :196.
  - The deadline is 540 s locally and 1200 s in CI (`ci.yml:115`), and the load phase needs 150 s left.
- `release/demo-load.sh:197-198` (read only): its default watch text is the guide prompt, sent with `fromGuide` true.

**The unit, the gate and CI**
- `docker/tests/test-demo-path.sh`: :1-25 is the header, and :55-64 the Playwright run, whose environment reaches npm. `ci/iris.sh:436-458` (`cmd_live`) passes the environment through.
- `docker/tests/test-demo-path-gate.sh`: :85-92 is the `dc` stub, with its `audit.order` file and `GATE_AUDIT`, and :100-115 the npm stub.
- `ci/units.sh`: :26-42 is the layout comment, :45 the `install-fresh` line and :51 the `image` line.
- `docker/tests/test-ci-config.sh:1167` names "group image" for `install-script-live`'s synthetic case, so it moves with the unit.
- `docker/tests/test-ci-changes.sh`: no pin names either unit. It is run, not changed.
- The other epics' `ci/units.sh` changes touch other lines: Epic 12 the `production` line and `NO_WEB_BUNDLE_UNITS`, and Epics 13 and 15 `CHECK_SCRIPTS`.
- `web/e2e/support/iris.ts` and `chk` are read only.

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)`
  - Before any change, run `live online-demo-path` once and record its seconds.
  - On the first loop run of the new 02 and 03, read the mock log: a temporary probe takes `Test.Contract.Mock.LogMark()` before the press and reads `LogSince(mark, .entries)` after it, and is deleted before the stage ends. Record for each Triage request and each Chat request its `selectedBy`, scenario and `k`. The expected:
    - for the watch, `guide-watch-triage` once and `guide-watch` with k = 0 and k = 1;
    - for the reminder, the same with the reminder's scenarios.
  - Confirm that the Triage input holds only its own turn's prompt.
- `ci/mock/scenarios.mjs`:
  - A `match` is one key of `MATCH_TYPES`, or exactly `{prompt, mockkey}`, which is allowed only under `B/`, with both values non-empty strings and no white space in the key.
  - A keyed prompt is pushed to `prompts` as `{prompt, mockkey, scenario}` and never to `byMockKey`.
  - Two scenarios may share a prompt text only when each names a mock key of its own.
  - The containment check skips identical texts.
  - Update the format doc.
- `ci/mock/mock.mjs` -- in `select`, the prompt hits are those whose `mockkey` is undefined or equals the request header. Zero hits fall through, and two are still `ambiguous-prompt`. Update the header's step 3. Nothing else changes.
- The mock's tests:
  - `ci/mock/test/server.test.mjs`: a new row with a keyed pair of the same prompt (`chat`, `triage`) and a `diagnosis` default. It pins the matrix's six run-time rows, with `selectedBy`, the scenario and the log line, and the row-7 fixtures stay as they are.
  - `ci/mock/test/scenarios.test.mjs`: the loader rows of the matrix, the good and the bad.
  - `ci/mock/test/constants.test.mjs`: row 16 counts only the matches whose single key is `mockkey`, and it adds that every keyed prompt names an agent's MOCKKEY.
- The scenarios (Boundaries): change `B/guide-watch.json` and `B/guide-reminder.json`, add `B/guide-watch-triage.json` and `B/guide-reminder-triage.json`, and delete `A/watch-act-orders.json`.
- `src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls`:
  - `TestWatchPrompt` now wants 2 Chat requests from `guide-watch`, the first answering `start_watch`. The answer is the new text, and no `BackgroundCheck` row is written: the owner is a fresh Ref that no session owns, which `TestReminderPrompt` already relies on for its reminder (inference; the first run confirms it, and a different tool answer is recorded and pinned as it is).
  - Add `TestWatchPromptTriage` and `TestReminderPromptTriage`. Each sends Kind decide, provenance user, with the prompt, and wants one request, `selectedBy` prompt, with its `-triage` scenario, and an answer with outcome act and no fallback, read back from its `Bridge.Data.Decision` row (`Kind` decide, `Fallback` 0).
  - Update the doc.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls` -- `TestGuidePromptSetsReminder` also pins that the turn's triage decision (`row.TriageDecisionRef`) is Outcome act with `Fallback` 0. Update the doc.
- `web/e2e/support/demo-path.ts`:
  - Add `MODEL` (it parses `OCUTALON_DEMO_PATH_MODEL` and throws on any other value) and `ON_MOCK`.
  - Add `expectDecision(strip, what)` (the Boundaries).
  - Add the step functions. Each starts on a signed-in page and returns what the next one needs:
    - `watchThroughGuide(page)` presses `guideSend` at step 1 and checks the user message (the exact prompt, "From the demo guide"), the reply's strip, the check row, the active Break the feed and the guide's steps;
    - `reminderThroughGuide(page)` opens "Step 2, Reminder" (upcoming or current), presses Send and checks 03's message, the reply and its strip, the row with its countdown and step 2 done;
    - `expectIncidentAwaitingApproval(page)` checks 04's card, its request, the phone's notice, the rail and step 4 current, and returns the request key. It does not press Break the feed;
    - `approveOnPhone(page, key)` presses Approve on the phone's notice and checks the answered statuses, the band, the audit line, Resolved, the phone's result message with no buttons and the rail row leaving.
  - Remove `watchMessage`, and update the header.
  - What each step checks on `mock` only, and how it matches on `real`:
    - **Watch:** chip Act, the reason and the reply text are mock only.
    - **Reminder:** "The CI mock set the reminder.", chip Act and the reason are mock only. On `real`, the row's `.lead` needs text only, because the model writes the reminder's text. So does 04's landing check: "Reminder: " followed by text in the chat, and a phone message with text.
    - **Incident:** the cause and the evidence line are mock only. On `real`, the headline matches `/^\d+ \S+ failed since \d{1,2}:\d{2}/`, the `.dry-count` needs text, and the buttons match `/^Approve: /` and `/^Reject: /`, instead of "50 orders", "50 orders affected" and the exact button names.
    - **Approve:** on `real`, the band matches `/^All \d+ \S+ went through\.$/` instead of "All 50 orders went through.".
    - Every text the product writes alone is checked exactly on both. These are the chips Awaiting approval, Fixing and Resolved, "Dry run", "Nothing has changed yet.", "Approved from the simulated phone at …", "Recorded in the IRIS audit log.", the rail and the guide steps.
- `web/e2e/support/devices.ts` -- delete `armCountdown`.
- `web/e2e/demo-path/02-watch.spec.ts`:
  - The watch test signs in and calls `watchThroughGuide`.
  - The new title is "the guide's Send for step 1 gets a decision with its reason and trace link (Act on the CI mock), the check row shows, and Break the feed becomes active".
  - `beforeAll` calls `pointKeys` only on mock.
  - Remove the `randomBytes` import, the countdown and the marker, and update the doc.
- `web/e2e/demo-path/03-reminder.spec.ts` -- call `reminderThroughGuide`. `pointKeys` runs only on mock. Replace the stale doc.
- `web/e2e/demo-path/04-incident.spec.ts` -- the card test calls `expectIncidentAwaitingApproval`, then checks that the reminder lands. The `@floor` test does not change.
- `web/e2e/demo-path/05-approval.spec.ts`:
  - After the fresh sign-in, the footer gets `expectDecision`, and chip Act on mock.
  - Then `approveOnPhone`. The Fixing-then-Resolved stream check stays.
  - The `/state` result is `{total 50, completed 50, failedAgain 0}` on mock, and on real `completed = total` with `failedAgain` 0.
- `web/e2e/demo-path/06-trace.spec.ts` -- the `afterAll` restore and `WaitRecords` run only on mock.
- `web/e2e-online/demo-path/demo-path.spec.ts`:
  - Replace the four `notBuilt(..., '11.1')` calls with one serial `describe` of four tests, titled "step 2: …" to "step 5: …".
  - They share one visitor: `beforeAll` calls `openVisitor`, and `afterAll` calls `cleanPopulated({session, reminder: '', approval: '', pairing: ''})` and then `leaveVisitor`.
  - The tests call the four step functions. Step 2 has no last-run wait. Step 4 first presses Break the feed and expects the POST to answer 200, as the second visitor does at :210-212.
  - The second visitor's `askToWatch` presses `guideSend`. `WATCH_MESSAGE` goes, and the doc is updated.
- `docker/tests/test-online-demo-path.sh`:
  - `report_check` wants passed `/^step [1-6]:/` (one each) and `/^second visitor:/`, and 3 skipped, all of Story 31.4. Update the PASS and FAIL texts and the header.
  - `load_script` drops the `OCUTALON_LOAD_WATCH_TEXT` override, so the load sends the guide's own prompt. Update its comment.
- `docker/tests/test-demo-path.sh`:
  - With `OCUTALON_DEMO_PATH_MODEL=real`, before the audit mark, it prints `MODEL real: a dry run on the CI mock` and points the keys through `iris_script` (`RunnerFixture.PointKeys()`, which must answer OK; otherwise FAIL and stop).
  - Any other value passes through to the specs. Update the header.
- `docker/tests/test-demo-path-gate.sh` -- add a run with the variable set to `real`. The `dc` stub answers the point script with `CHK|keys|1` and logs it as `point` in `audit.order`. The run checks that the `MODEL` line prints and that `point` comes before `npm`.
- `ci/units.sh`:
  - `install-fresh` becomes `live:install-start live:bundle-folder live:online-demo live:install-script-live`.
  - `image` becomes `live:storage-roundtrip live:build-inputs live:compose-start shard:lane-b live:online-demo-path`.
  - Record the layout and run 41206732188's seconds in the comment.
- `docker/tests/test-ci-config.sh` -- move the :1167 pin's group to `install-fresh`, and any other pin the run names.

**Acceptance Criteria:**
- **AC1 (U-194; AD-22).** Given scenario trees with keyed and keyless prompts, when the mock loads them and answers requests, then every mock row of the matrix holds, and every existing row of `server.test.mjs`, `scenarios.test.mjs` and `constants.test.mjs` still passes unchanged in meaning.
- **AC2 (DW-433; integration: consumers 02 and the real Conversation, Chat, WatchTools and WatchOps).** Given a fresh demo-path stack after 01, when 02 presses the guide's Send for step 1, then the web step 2 row of the matrix holds, and 02 sends no marker, arms no countdown and types nothing into the composer.
- **AC3 (DW-307; integration: consumer the real Triage).** Given a guide prompt's turn on the CI mock, when Triage decides it, then the request gets its own `-triage` scenario and the decision is act with no fallback:
  - `TestWatchPromptTriage` and `TestReminderPromptTriage` pass;
  - `TestGuidePromptSetsReminder` pins the turn's triage decision;
  - 03's strip shows chip Act, its reason and no Fallback flag.
- **AC4 (DW-221).** Given the online-demo-path unit on its flag-on throwaway, when it runs, then:
  - steps 2 to 5 pass as one visitor's journey through the shared step functions;
  - the second visitor and the load phase send the guide's own prompt;
  - the report check holds the matrix's online report.
- **AC5 (the real-model rule; REL-2, REL-5).** Given the demo-path test run against the real model (a release-candidate or rehearsal run) rather than the CI mock, when it reaches a decision, then it checks that a decision with reasons and a trace link appears, never which outcome; specific outcomes, such as the Act strip on the watch step, are asserted only against the CI mock. Here that means:
  - on `real`, 02, 03 and 05 check each decision with `expectDecision` only, and match the model-written texts by their shape (Tasks);
  - the specs leave the runners' keys alone;
  - the real-mode dry run on the CI mock passes;
  - an unknown value fails the run before any step.
- **AC6 (the retired route).** Given the finished tree, when it is searched for `watch-act-orders`, `watchMessage`, `armCountdown` and `WATCH_MESSAGE` outside `_bmad-output/`, then nothing is found.
- **AC7 (REL-4).** Given the swap of `live:online-demo-path` and `live:install-script-live`, when the CI configuration checks run, then `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml --paths-from <this story's paths>` pass.
  - The final local seconds of `live online-demo-path` and `live demo-path` are recorded under Verification.
  - The estimate (Design Notes) keeps every group under 33 min.
  - The CI estimate for `image` is (1821 s + the local increase of `live online-demo-path`) / 60 min, where 1821 s is 1692 − 270 + 358 + 5 plus 36 s of job overhead. If it passes 33 min, the implement stage adds a `deferred:` item for the lead.

### Review Findings

Code review, 2026-10-31: four layers (Blind, Edge, Verification Gap, Acceptance) on `git diff 7347be00` plus QA's untracked test. 35 raw findings gave 10 patched root causes (3 medium, 7 low), 2 low ledgered as terminal (DW-509, DW-510), 4 low rejected and 7 false. No high finding and no AD mismatch.

- [x] [Review][Patch] (medium) The gate never checked that `OCUTALON_DEMO_PATH_MODEL` reaches Playwright, so a unit that dropped or rewrote it would keep the real-mode dry run green in mock mode (Blind 3, Edge 12, VG 1) [docker/tests/test-demo-path-gate.sh:127] -- the fake `npm` records the value, and the real, default, mock and `zz` runs check it.
- [x] [Review][Patch] (medium) The gate, the parser cases and the online unit took `OCUTALON_DEMO_PATH_MODEL` from the caller's shell (Blind 3, Blind 5, Edge 10, Edge 11, VG 2) [docker/tests/test-demo-path-gate.sh:37] -- the gate unsets it, `playwrightEnv` deletes it, and `test-online-demo-path.sh`'s `run_e2e` pins `mock` (the unit always points the keys at the mock).
- [x] [Review][Patch] (medium) `load_script` took `OCUTALON_LOAD_WATCH_TEXT` from the caller's shell, so the load phase's "the guide's own prompt" rested on the shell (Blind 2, Edge 1, VG 3, Auditor 6a) [docker/tests/test-online-demo-path.sh:200] -- unset with the other load variables.
- [x] [Review][Patch] (low) `approveOnPhone` accepted any zone suffix on both runs, against "checked exactly on both" (Edge 6, Auditor 1) [web/e2e/support/demo-path.ts:282] -- a `zone` argument: none on the web run, `" ET"` on the online run (`Msg.Catalog`'s time slot).
- [x] [Review][Patch] (low) `guide-view.test.mjs` did not tie the two `-triage` scenarios to the guide's prompt texts (Blind 1) [web/scripts/guide-view.test.mjs:218]
- [x] [Review][Patch] (low) Row 16's tool-name check had been narrowed to the default scripts, leaving out the keyed prompts' `start_watch` and `set_reminder` (Blind 6) [ci/mock/test/constants.test.mjs:91]
- [x] [Review][Patch] (low) `test-demo-path.sh` gave a false reason, "a real install has no test classes": `src/module.xml` ships `OcuTalon.PKG`, `OcuTalon.Test.*` included (Blind 7) [docker/tests/test-demo-path.sh:51]
- [x] [Review][Patch] (low) The `ci/units.sh` comment presented lane-b 905 as measured; run 41206732188 measured 900, and the 5 is an inference (Blind 9) [ci/units.sh:48]
- [x] [Review][Patch] (low) The retired-names test would go red on a rule or record under `_bmad/` that names a retired name (Blind 8) [web/scripts/retired-demo-path-names.test.mjs:26] -- the kit's folders are left out of the search.
- [x] [Review][Patch] (low) The parser cases did not cover the empty value, which reads as `mock` (Auditor 6b) [web/scripts/demo-path-summary.test.mjs:463]

**Rejected:**
- (low; DW-509, wontfix-accepted) The key guard in `devices.ts` also fires for `reminder/chat.spec.ts` and `demo-switch/mailbox.spec.ts` when `real` is exported for a wider run (Blind 4, Edge 2, VG other 1, Auditor 2). Only `live:demo-path` sets the variable, and moving the guard is about 20 lines.
- (low; DW-510, by-design) Real-mode shapes: the `\S+` item noun and 04's button-less phone note (Edge 7, Edge 9). The spec's Tasks fix both; they reopen only by amendment after a real run.
- (low) The feature commit's message says "the four guide prompts" (Edge 13). There are two prompts and four scenarios; the message belongs to a commit already in history, and the code and spec are right.
- (low) Task 0's baseline was not taken (Auditor 4). This is self-reported, and the lead measures `image` on this story's CI run (Design Notes). The auditor's scaled bound is 32.4 min.
- (low) The `ci/units.sh` comment sits next to Epic 12's edit of the same comment (Auditor 5). A trial `git merge-file` against `origin/OCT-epic12` gives one comment-only conflict hunk at line 42, which keeps both paragraphs; moving the paragraph would split the layout comment.
- (low) The retired-names ban is permanent and reads untracked files (VG other 2, Auditor 6c). This is by design: it is AC6's retired route, and it mirrors the `rg` search, as its header says.
- (false) Edge 3: a real install has no test classes. The package ships them.
- (false) Edge 4: `guideSend` pressed off step 1. This is the documented precondition, and the "step 1 done, step 2 current" checks fail loudly.
- (false) Edge 5: an instance zone other than UTC. No compose file sets TZ, and the old 05 check used the same rule.
- (false) Edge 8: a fix total of 0 passes on real. No approval request exists without failed orders.
- (false) Auditor 3: the en-GB/UTC oracle states no precondition. The doc comment states it, and a mismatch fails showing both texts.
- (false) Auditor 2's sub-claims. A second parser cannot drift, because `parseModel` refuses every other value at load, and `WaitRecords` sits behind 06's `if (!ON_MOCK) return`.
- (false) Blind 8's untracked part. QA's file is uncommitted by stage design, and the lead commits it.

**Rules.**
- Rule 3: this story is test, mock and CI code. Its real-runtime evidence is `live demo-path` and `live online-demo-path`, Playwright on real throwaway stacks, both green after the patches.
- Rule 6: AD-22 as amended (U-194) holds. `select` keeps a prompt hit only with no key or the header's key, keyed prompts stay out of `byMockKey`, and there is no new state. AD-29's Epic 11 exception covers the Lane B mock code.
- Rule 2: the copy in `B/guide-watch.json` carries its stated reason, and the step functions extend the web run's checks.

## Spec Change Log

## Review Triage Log

### 2026-10-31 — Review pass
- verdicts: 42 findings — high 0, medium 4, low 22, false 16, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: the real-mode dry run leaves the runners keys pointed at the mock — the unit runs on its own throwaway, which is torn down after it; the specs now refuse to touch keys on real (see the patch for finding 19); a restore branch in the shell adds code for no reachable harm
  - `[medium]` `[patch]` Blind 2 (with VG oracle): approveOnPhone takes the card time oracle from the page itself — the page-derived locale and zone let a wrong-zone page match itself; patched: the oracle is the fixed en-GB and UTC, which both runs set on their contexts (test.use, openVisitor options); mutation covered by the existing step 5 text check
  - `[low]` `[reject]` Blind 3: the phone line accepts an optional zone suffix on the mock too — the online demo writes the suffix; the web run is not at risk from a stray suffix in any path the product has; a flag parameter adds complexity for a negligible gain
  - `[false]` `[reject]` Blind 4: the real-mode fix-result check passes with an empty result — result {} gives [undefined, undefined] against [undefined, 0], and toEqual treats undefined and 0 as different, so it fails; All 0 orders on real is not reachable (a request exists only for failed orders)
  - `[low]` `[reject]` Blind 5: the real-mode phone check counts every button-less note — the spec fixes the real check as "a phone message with text"; real is never run here; reopen_if=the first real rehearsal (Story 11.3) counts two button-less notes
  - `[false]` `[reject]` Blind 6: expectDecision on 05 footer is stricter than before — live demo-path (mock) and the real dry run pass with it on the footer strip: it renders its reason and trace link (incident-card.ts)
  - `[low]` `[reject]` Blind 7: Test.Contract.Mock.Arm is orphaned and the 500 text does not name keyed prompts — Arm still serves the IRIS tests; the 500 text is the unchanged no-scenario text of the matrix
  - `[low]` `[reject]` Blind 8: nothing asserts the exact set of keyed (prompt, key) pairs — TestWatchPromptTriage, TestReminderPromptTriage, TestGuidePromptSetsReminder and 02 and 03 go red if a pair is missing (mutation lines)
  - `[false]` `[reject]` Blind 9: the units.sh comment gives no number for the online unit growth — the spec asks for the layout and run 41206732188 seconds; the growth is bounded in the spec (31.4 min at most); the step timeouts are caps, not durations
  - `[low]` `[reject]` Edge 1: the real-mode landing check counts all button-less phone notes — same as Blind 5
  - `[low]` `[reject]` Edge 2: the real dry run leaves keys pointed, no restore — same as Blind 1
  - `[low]` `[reject]` Edge 3: the PointKeys failure message gives no status text — the unit stops with FAIL and a clear line; a gate run pins it; the status text would only help a stack that is already throwaway
  - `[low]` `[reject]` Edge 4: containment check clashes two keyed prompts with different keys — a conservative load refusal, loud at load; no scenario of this story or of Story 11.10 is affected (reopen_if=a keyed pair whose texts nest)
  - `[false]` `[reject]` Edge 5: a keyless prompt contained in a keyed one is not decided — the containment loop runs over every pair of distinct prompts, keyed or not, and refuses at load
  - `[low]` `[reject]` Edge 6: CheckCount counts the whole BackgroundCheck table — rows come only from start_watch; the class runs on its own throwaway one test at a time; no realistic concurrent writer
  - `[low]` `[reject]` Edge 7: the online afterAll cleanPopulated takes approval empty — the spec fixes the call as written; removeSession and leaveVisitor remove the visitor rows, and the throwaway ends the unit
  - `[low]` `[reject]` Edge 8: doneTurn names neither ClientId when it times out — a failure message nicety on a path that has not failed in any run
  - `[medium]` `[patch]` VG 1: parseModel (the unknown-value throw) has no executed test — patched: two cases in web/scripts/demo-path-summary.test.mjs run Playwright with zz (fails, names the value) and with real and mock (skips as before); mutation line written
  - `[medium]` `[patch]` VG 2: "the specs never touch the keys on real" cannot fail — patched: pointKeys and restoreKeys throw on OCUTALON_DEMO_PATH_MODEL=real, so a spec that calls them turns the real dry run red; mutation line written
  - `[low]` `[reject]` VG 3: the real-mode branches run only in a manual dry run — real is never run in CI by design (cost; the spec routes real runs to Stories 11.3 and 38.2); wontfix-accepted, reopen_if=a real-mode regex goes red at Story 11.3
  - `[low]` `[patch]` VG 4: the second visitor and the load phase have no pin for the guide own prompt — patched for the second visitor: askToWatch asserts the guide caption (mutation red, line written); the load phase override cannot be seen by this unit (a marker beats a keyed prompt), and the default is pinned by test-online-load.sh
  - `[false]` `[reject]` VG 5a: AC6 has no mutation line — AC6 is a search, not a test; there is no pinning test to mutate
  - `[low]` `[patch]` VG 5b: AC7 has no mutation line — mutation run and line written (units.sh swapped back, test-ci-config red)
  - `[low]` `[patch]` VG 5c: AC3 watch half has no mutation line — mutation run and line written (guide-watch-triage set aside, TestWatchPromptTriage red)
  - `[low]` `[reject]` VG 5d: AC5 other expectDecision checks have no mutation — one demonstrated mutation per AC (Rule 19); the trace-link mutation is recorded
  - `[medium]` `[patch]` VG 6a: the card-time oracle follows the page — same root cause as Blind 2, patched there
  - `[low]` `[reject]` VG 6b: the optional zone suffix weakens the phone line — same as Blind 3
  - `[false]` `[reject]` VG 6c: online steps 2 to 5 rely on order — by design: one serial journey of one visitor (the spec); the unit is the hermetic whole
  - `[low]` `[reject]` VG 6d: TestWatchPrompt counts the whole BackgroundCheck table — same as Edge 6
  - `[false]` `[reject]` VG 6e: web 04 relies on 02 and 03 state — by design: the ordered demo-path journey
  - `[low]` `[reject]` VG 7: the gate zz case title says the specs refuse, but it only shows pass-through — the refusal is now pinned by VG 1 test; the title states the design
  - `[false]` `[reject]` VG 8: openVisitor pageOptions note — the finding itself says no defect
  - `[false]` `[reject]` VG 9: the identical-text skip in the containment check hides a keyed/keyless pair — that pair is refused earlier by the clash check (scenarios.test.mjs rows)
  - `[false]` `[reject]` Intent 1: A/watch-act-orders deleted, armCountdown and watchMessage removed — mandated by the spec (AC6); rg finds no reference
  - `[false]` `[reject]` Intent 2: constants.test.mjs row 16 edited — mandated by the spec Tasks (count only single-key mockkey matches)
  - `[false]` `[reject]` Intent 3: a mockkey with white space is rejected — mandated by the spec Tasks ("no white space in the key")
  - `[low]` `[reject]` Intent 4: an empty model value is mock, not an error — decided in-stage (recorded in Design Notes); only non-empty other values throw
  - `[low]` `[reject]` Intent 5: step 5 checks changed in both modes (zone suffix, clock oracle) — the clock oracle is fixed back to en-GB and UTC (Blind 2); the zone suffix stays as Blind 3
  - `[false]` `[reject]` Intent 6: real-mode shapes beyond the three decision points — mandated by the spec Tasks (Incident, Approve and Reminder shapes)
  - `[false]` `[reject]` Intent 7: the load phase now sends the guide own prompt — mandated by the spec Tasks (load_script drops the override)
  - `[false]` `[reject]` Intent 8: other callers of the guide prompts are not exercised by the diff — live sign-in part 2/2 (reminder/chat.spec.ts, 96 passed) and live floor/guide specs (routes mocked) cover them
  - `[false]` `[reject]` Intent 9: the old Chat text of guide-watch is gone — mandated by the spec Boundaries (reply 0 start_watch, reply 1 the text); TestWatchPrompt updated

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-22 | The amended selection order (U-194), the mock's single state (the countdown), CI's groups, and REL-2 |
| AD-29 | Epic 11 may change either lane's files: the mock code and the `B/` scenarios are Lane B's, the specs and the CI files Lane B's, and `A/` Lane A's |
| AD-19 | The `x-ocutalon-mockkey` header is CI-only (owner value 11). No key reaches IRIS, a log or the trace. |
| AD-12 | `/state`, the guide's steps and Break the feed |
| AD-15 | The watch, settle, diagnosis and incident chain of the online steps 4 and 5 |
| AD-20 | A turn's strip shows its triage decision |
| AD-4 | Each online visitor sees only its own rows |
| AD-26 | The trace links that `expectDecision` checks |
| AD-11 | The approval request of step 5 |

No AC contradicts an AD. The keyed prompt is the amended AD-22 Rule word for word: it adds no state, and the countdown stays keyed by marker.

**Extend, don't copy (Rule 2).**
- The four step functions are the web run's own checks, moved into `demo-path.ts`. Both runs call them.
- `B/guide-watch.json` copies `A/watch-start-orders.json`'s two replies. A JSON scenario cannot extend another, and the marker scenario stays for `Test.Watch.Turns` and the other IRIS tests that send it. That is the stated reason for the copy.
- The triage replies follow `A/triage.json`'s shape.

**Integration ACs and links (Rules 1 and 2).**

| Link | Who |
| --- | --- |
| Consumed-by | The keyed prompt match: this story's four `B/guide-*` scenarios (AC2, AC3, AC4); Story 11.10, which keys the sample emails' triage for the coda; any later guide prompt |
| Consumed-by | The real-model switch: Story 11.3's rehearsal runner (its dry runs on the mock); Story 38.2's 20 real runs; Story 11.10's own decisions |
| Consumed-by | The step functions: the web run's 02 to 05, the online run's steps 2 to 5, Story 11.10 (its replay reuses the incident and approve checks), and Story 11.3 |
| Consumes | Lane B: Conversation, the Triage and Chat agents' `MOCKKEY`, Demo.Guide and Web.Api |
| Consumes | Lane A: WatchTools and WatchOps, Checks, IncidentManager, Diagnosis, FixExecutor and Bridge.Approval |
| Consumes | Test helpers: `RunnerFixture` (`PointKeys`, `NewRequest`, `Run`), `Test.Contract.Mock` and `lib-online.sh`'s `keys_point` |

**Ledger (Rule 17).** Addressed:
- DW-433 (AC2, AC4: the second visitor and the load phase);
- DW-307 (AC3);
- DW-221 (AC4).

None is declined.

**Contended paths (U14).**
- Epic 29 has merged, so its entries are free.
- `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for N = 15, 30, 12 and 13: none of them changes `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, `ci/mock/test/`, any `B/` scenario or any other file listed here, except `ci/units.sh`. That file is shared by region, and its group lines `install-fresh` and `image` are not among their changed lines.
- The new files sit in the contended folder `ci/mock/scenarios/B/`.
- The deleted file, `A/watch-act-orders.json`, is Story 11.1's own.

**CI budget (REL-4).** Measured on Story 11.1's head (run 41206732188): unit seconds, and job wall times from job start.

| Group | Units (s) | Group (s) | Wall (min) |
| --- | --- | --- | --- |
| install-fresh | install-start 739, bundle-folder 264, online-demo 646, online-demo-path 358 | 2007 | 34.0 |
| image | storage-roundtrip 312, build-inputs 9, compose-start 201, lane-b 900, install-script-live 270 | 1692 | 28.8 |
| browser | demo-path 418, sign-in 801, answers 475 | 1694 | 28.8 |
| production | four NO_WEB_BUNDLE units | 1388 | 23.6 |

- **What this story adds.**
  - The online unit grows by its steps 2 to 5, about 45 to 90 s (inference): two guide turns, settle and diagnosis (L1 measured a 12 to 16 s notice), and the fix.
  - `live:demo-path` is about unchanged: step 2 still makes three mock requests.
  - lane-b gains two short tests, about 5 s.
- **The swap.** `live:online-demo-path` (358 + Δ) goes to `image`, and `live:install-script-live` (270) to `install-fresh`.
  - `install-fresh` ≈ 2007 − 358 + 270 = 1919 s, so about 32.5 min.
  - `image` ≈ 1692 − 270 + 358 + 5 + Δ = 1830 to 1875 s, so about 31.1 to 31.9 min.
  - The other groups do not change: install-upgrade 31.8, shards-2 31.6, shards 30.4, browser 28.8 and production 23.6.
- **Why this layout.**
  - Production is avoided: it takes only NO_WEB_BUNDLE units, and Epic 12 adds `shard:lane-a@Channel` to its line.
  - Swapping `storage-roundtrip` instead would leave `install-fresh` at 33.2 min.
  - Every iris job builds the image and the bundle, and `ci/iris.sh live` installs Chromium for a browser unit, so either unit runs in either group.
- The lead measures the result on this story's CI run.

**Decided in-stage.**
- **Each guide prompt gets a Triage scenario of its own,** rather than falling through to `A/triage.json`, whose outcome is Digest. So the strip shows Act and a reason that the specs pin, as the lead's ruling asks. The scenario names keep `guide-watch` and `guide-reminder` for Chat, so `GuidePrompts` and `ReminderChat` keep their scenario names.
- **The loader's rules for keyed prompts.**
  - An identical prompt text may appear only across distinct mock keys, and a keyless prompt's text is unique. This keeps AD-22's "two matches are a 500" from becoming reachable through the files.
  - A request with no `x-ocutalon-mockkey` never matches a keyed prompt. Every CI stack sends the header.
- **The reading of "never which outcome".**
  - It covers the outcome chips and every text that a model's output fills: the reasons, the replies, the cause, the evidence category and element, the item noun, the fix's words and the counts the fix drives.
  - On `real` the specs still walk the whole route: Approve, the result, the trace.
  - Story 38.2 requires that every real run "passes UJ-1's web route", so a real diagnosis with no fix fails the run there, and that is correct.
  - A Fallback flag is not an outcome (the bridge, not the model, sets it), and it fails `expectDecision` in both modes.
- **The switch's name and its keys.**
  - The name is `OCUTALON_DEMO_PATH_MODEL`, a test-only variable that no product file reads.
  - On `real` the specs never point keys, because a real install has no test classes and a real key must not be touched.
  - A dry run on the CI mock therefore has `test-demo-path.sh` point the keys. That is also the hook Story 11.3's dry runs need.
- **The online journey.**
  - Steps 2 to 5 are one serial `describe` of one visitor, so each step starts from the one before it, as in the web run.
  - Step 2 skips the heartbeat's last-run wait (up to 120 s), which the web run already proves on the same code. Step 6 stays its own case.
- **DW-433's workarounds are retired with it:** the second visitor's marker and the load phase's watch-text override.
- **02's `describe` keeps its skip text** "Story 11.1 needs the first-start stack". The no-stack pin reads any story.
- **No public-facing text is added.** The new texts are the CI mock's (test data) and test titles. The page texts checked are the ones EXPERIENCE.md and the epics block already fix.

- **Implement-stage choices.**
  - An empty `OCUTALON_DEMO_PATH_MODEL` is `mock`, as unset is; only another non-empty value throws.
  - The online steps 2 to 5 visitor opens its context with UTC and en-GB (`openVisitor`'s optional last argument), so the card's clock text equals the web run's; `approveOnPhone` takes the phone's optional zone suffix (the online demo writes one) and checks the card in en-GB and UTC.
  - `pointKeys` and `restoreKeys` in `web/e2e/support/devices.ts` throw when `OCUTALON_DEMO_PATH_MODEL` is `real`, so that "the specs never call them" is a check that can fail.
  - Task 0's baseline run of `live online-demo-path` was not taken (the first change came before it), and the temporary mock-log probe was not used: the four `GuidePrompts` tests pin the same facts. The online unit's growth is bounded by its whole browser step (61 to 65 s here), so `image` is at most (1821 + 65) / 60 = 31.4 min, under 33.

**Lead's question at the gate (non-blocking).** The spine's AD-22 "Logs and state" bullet still describes `match` as "holding one of `marker`, `prompt`, `mockkey` or `telegram`". With U-194 it may hold `prompt` together with `mockkey`. This is a factual note for the lead (Rule 20, light path); this story does not edit the spine.


**Lead rulings at the spec gate (2026-10-31, unattended; these override anything above that disagrees).**
- The proposed split is accepted (decide, U5): Story 11.10 is in `epics.md` right after 11.7 with the failure-path and coda paragraphs verbatim. This story keeps the U-194 mock change, DW-433, DW-307, step 2's return to the guide's own Send in both runs, DW-221 and the real-model switch.
- AD-22's "Logs and state" bullet now says `match` may hold `prompt` together with `mockkey` (same U-194 marker); the spine needs nothing else from this story.
- The two-unit group swap in `ci/units.sh` (online-demo-path to image, install-script-live to install-fresh) is allowed: `ci/units.sh` is shared by region in this run, a plain union at integrate-forward. Update the `docker/tests/test-ci-config.sh` pins and run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh`; the lead measures the groups on this story's CI run.

### Proposed split

The block has three criteria paragraphs and three ledger entries. Together they come to about 40 changed files (inference) across the mock, both runs, the evaluation tests and CI. That is more than one implement pass (about 25). This story keeps:
- the U-194 mock change, DW-433 and DW-307 with step 2's return to the guide (one change, as the lead prefers);
- DW-221, the online run;
- the real-model rule, which the step functions carry.

Those come to 25 files, the deleted scenario included, all on the demo path, its mock and its CI layout. The lead inserts the sibling into `epics.md`, in Epic 11, before Story 11.5's cut. Every moved item stays in release 1.0.0's scope.

**Story 11.10: The demo path's failure paths and quiet outcomes pass in the REL-2 test.**
- **Given** the test's failure-path scenarios
  **When** one rejects the request and another makes the mocked model refuse the diagnosis
  **Then** the rejection shows "Rejected from the simulated phone at {time}. Nothing was changed.", the incident returns to Open, Dismiss re-enables Break the feed and a replay opens a new incident with its own request; the refusal shows the fallback card with its failure groups and no fix, and step 5 still opens the trace (FR-4, FR-8, FR-16, FR-24, UX-DR104)
  - Reason: these are journeys of their own after the main route's resolved incident, which the replay rule closes. They need a seam that the main route does not: the diagnosis request has to carry a marker, and the real Break the feed's orders never do.
  - Evidence for its plan:
    - `Watch/EvidencePack.Input` sends the sample failed message's body.
    - `Demo/Orders/PartnerOrder` has `OrderNumber` and `Sku` at MAXLEN 20, which holds `[[mock:refusal]]`.
    - The `Test.Watch.*` classes put `[[mock:<name>]]` in the failure text.
- **Given** the coda
  **When** the test presses "Sample: newsletter" and "Sample: suspicious request"
  **Then** the newsletter is decided Ignore with nothing on the phone, the suspicious request leads to no approval request, resend or setting change, and the whole test keeps a full CI run within 35 minutes [AMENDED 2026-10-20, owner decision 7] (NFR-14, REL-4, UX-DR105)
  - Reason: this is the UX's separate quiet-outcomes journey. On the mock it needs keyed prompt scenarios for the sample emails' triage (the first consumer of this story's match outside the guide).
  - Those scenarios also change the evaluation set's results on the mock. `Test.Eval.Run` scores the newsletter as the mock's Digest (`:878`, `:888`), and the eval case holds the same body. That is a Lane A area this story does not touch.
- Both journeys add browser time to `live:demo-path`, about 3 to 5 min (inference), with the browser group at 28.8 min today. The sibling needs its own budget plan.
- Both use this story's switch for their decisions.

If the lead declines the split, this spec goes back to `draft` for a re-plan.

## Verification

`<A>` stands for:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'
```

QA and review use their own stage names and tags: `e11s7q` and `e11s7qw`, `e11s7c` and `e11s7cw`.

**Run discipline:**
- Run everything from the epic-11 worktree root.
- Each command runs in the foreground of its own call, with `timeout: 600000`. `ANTHROPIC_API_KEY` stays unset.
- One test call per message. Never re-submit after a client-side timeout.
- Every IRIS MCP call passes `server` `ocutalon-slot-a` and namespace `OCUTALON`.

**Shared surfaces:**
- **The guide's watch prompt now starts a watch on the CI mock.** The cases that send it through to a stack are 02, the online run's steps 2 to 6 and its second visitor, the load phase, and `Test.Demo.GuidePrompts`. Each removes the check rows it makes: through `cleanPopulated` and `removeSession`, the unit's throwaway, or a fresh owner that nobody owns. No other spec's guide Send reaches the mock: `allowance/messages.spec.ts` and `busy.spec.ts` are refused (429 and 503).
- **Every guide prompt's Triage request now answers Act:** 03, `ReminderChat` and the online run.
- **The mock's scenario grammar:** `match` may be `{prompt, mockkey}`, and `constants.test.mjs` row 16 counts the default scripts.
- **`A/` loses `watch-act-orders`.** No test counts the folder.
- **The online unit's report:** 7 passed and 3 skipped.
- **`ci/units.sh`'s `install-fresh` and `image` lines,** and their pins in `test-ci-config.sh`.
- **The demo-path unit's environment** (`OCUTALON_DEMO_PATH_MODEL`) and the gate's runs.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.
- The mock's node tests and the IRIS classes are covered this way. The classes run warm and then fresh.
- Each demo-path unit is one ordered journey by design, and the unit is the hermetic whole: two green fresh runs each of `live demo-path` and `live online-demo-path`.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-a` -- expected: build 154U, port 1990.
  - Then load and compile there `Test/Demo/GuidePrompts.cls` and `Test/Schedule/ReminderChat.cls` -- expected: they compile. Run no test on the slot.
- (once) `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh build` -- expected: the image and the web bundle build.
- (once, before any change) `<A> OCUTALON_RUN_TAG=e11s7b ci/iris.sh live online-demo-path` -- expected: as today. Record its seconds (Task 0).
- (loop) `bash docker/tests/test-mock.sh` -- expected: every mock test passes, the new rows included.
- (loop) `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh build`, after each change under `web/src` (none is planned) -- expected: it builds.
- (loop) `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh live demo-path` -- expected:
  - `DEMO-PATH 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed`;
  - the audit PASS lines;
  - `test-demo-path: all checks passed`;
  - record the seconds.
- (loop) `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh live online-demo-path` -- expected: the report PASS (7 passed, 3 skipped of Story 31.4), the load phase's PASS lines and every PASS. Record the seconds.
  - On CI's timeline the browser step ends at about 372 s, which leaves about 168 s of the default 540 s for the load phase's 150 s guard (inference).
  - If the guard fails for time on this machine, run with `OCUTALON_LIVE_DEADLINE=570`, which still fits one 10-minute call.
- (once) `<A> OCUTALON_DEMO_PATH_MODEL=real OCUTALON_RUN_TAG=e11s7i ci/iris.sh live demo-path` -- expected: the `MODEL real: a dry run on the CI mock` line, and the same steps and PASS lines as in mock mode.
- (once) `<A> OCUTALON_RUN_TAG=e11s7iw ci/warm.sh up`, after the scenario files are written -- expected: `LOCK acquired warm-iris`. Any later change under `ci/mock/` needs `ci/warm.sh down`, then `up`.
- (loop) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s7iw ci/iris.sh class <C>`, one call each for C = `OcuTalon.Test.Demo.GuidePrompts` and `OcuTalon.Test.Schedule.ReminderChat` -- expected: `CLASS <C> passed`.
- (once) `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh class <C>` for the same two classes, one per call -- expected: passed on a fresh stack.
- (once) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s7iw ci/iris.sh class OcuTalon.Test.Contract.Mock` -- expected: passed (the IRIS side still reaches the mock).
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, `guide-view.test.mjs`, `demo-path-summary.test.mjs` and `playwright-projects.test.mjs` included.
- (loop) `bash docker/tests/test-demo-path-gate.sh` -- expected: every run as pinned, the real run included.
- The parts of `ci/checks.sh` this story touches, (once) each in its own call: `bash docker/tests/test-<name>.sh` for name in `ci-config`, `ci-changes`, `boundaries`, `class-rules` and `online-load` -- expected: every PASS. The other CHECK_SCRIPTS read no file this story changes.
- (once) `bash ci/changes.sh ci.yml --paths-from <scratch>/paths`, with the file holding `git diff --name-only <story_base>` -- expected: one GROUP line per group, and no unclassified path.
- (once) `rg -n 'watch-act-orders|watchMessage|armCountdown|WATCH_MESSAGE' -g '!_bmad-output/**' .` -- expected: no match (AC6).
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=e11s7iw ci/warm.sh down`, then `<A> OCUTALON_RUN_TAG=e11s7i ci/iris.sh teardown` and `<A> OCUTALON_RUN_TAG=e11s7b ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-a folder.

**Planned mutations (Rule 19).** For each one:
1. Apply it and observe red.
2. Revert it, and check that `git status --short` and `git diff --stat` are unchanged.
3. See green again.

Record each as a `mutation:` line here. Mutations whose reds land in different step files, without a cascade, may share one live run.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `select` ignores `match.mockkey` | The new server row (500 `ambiguous-prompt`), and 02 live |
| AC1 | The loader lets one prompt text repeat under one key | `scenarios.test.mjs` |
| AC2 | `B/guide-watch.json` reply 0 is the text, not `start_watch` | 02 on the check row; `TestWatchPrompt` |
| AC3 | Today's tree: `B/guide-reminder.json` loses its `mockkey`, and `B/guide-reminder-triage.json` is set aside | 03 on the Fallback flag and the chip (the triage gets `set_reminder`, an invalid reply); `TestReminderPromptTriage` |
| AC4 | `Core/Rule/Notify.cls` drops SimPhoneOut for kind incident | The online step 4, on the phone notice |
| AC4 | The online step 5 re-declared `notBuilt(..., '11.1')` | The unit's report check FAIL |
| AC5 | `web/src/app/chat/decision-strip.ts` renders no trace link | The real-mode dry run red in 02 on `expectDecision` |
| AC5 | `OCUTALON_DEMO_PATH_MODEL=zz` | The run errors before any step, with the message |
| AC5 | The gate: the point call removed from the real branch | `test-demo-path-gate.sh` |

### Implementation record (implement stage, 2026-10-31)

**Measured (lane A, this machine; one run each unless noted):**
- `live demo-path` (mock): 260 s, then 215 s on the final tree; `DEMO-PATH 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed`, every audit PASS, `test-demo-path: all checks passed`.
- `live demo-path` with `OCUTALON_DEMO_PATH_MODEL=real` (dry run on the CI mock): 214 s, the `MODEL real: a dry run on the CI mock` line, the same steps and PASS lines.
- `live online-demo-path`: 196 s and 217 s on the final tree (the browser step 61 to 65 s, the load phase 34 s); `7 passed`, the report PASS (7 passed, 3 skipped of Story 31.4), L1 and L2 PASS.
- Task 0's baseline run of `live online-demo-path` before any change was not taken (the first change was made before it ran), so Delta is not measured as a difference. The CI figure is unchanged: 358 s on run 41206732188. Steps 2 to 5 are part of a browser step that took 61 to 65 s here, so Delta is below the spec's 45 to 90 s estimate and `image` stays under 33 min ((1821 + 90) / 60 = 31.9 min at the upper estimate). No `deferred:` item.
- Task 0's temporary mock-log probe was not used: `TestWatchPrompt`, `TestReminderPrompt`, `TestWatchPromptTriage` and `TestReminderPromptTriage` pin the same facts (request counts, `selectedBy` prompt, the scenario of each request, and the tool_result carried by the second request), and 03's green strip (chip Act with the reminder scenario's reason) shows that the Triage input holds only its own turn's prompt (two prompts would be a 500 `ambiguous-prompt`).
- Classes: `GuidePrompts` and `ReminderChat` passed warm and on a fresh stack (7 s and 14 s of test time); `Test.Contract.Mock` passed warm.
- `test-mock.sh` 131 of 131; `npm --prefix web run lint` exit 0; `npm --prefix web test` 1134 of 1134; `test-demo-path-gate.sh` all checks passed (49 PASS, the real run included); `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh`, `test-class-rules.sh` and `test-online-load.sh` pass; `ci/changes.sh ci.yml --paths-from` prints the seven GROUP lines with no unclassified path; the AC6 search finds nothing.
- Findings of the run: (1) the online demo's phone writes "Approved from the simulated phone at HH:MM ZONE.", so `approveOnPhone` accepts an optional zone name after the time (the minutes still must equal the row's `AnsweredAt`); (2) the online visitor of steps 2 to 5 opens its context with `timezoneId` UTC and `locale` en-GB (a new optional argument of `openVisitor`) so that the card's clock text equals the web run's.

**Mutations (Rule 19; each applied, red observed, reverted, `git status --short` and `git diff --stat` unchanged, then green):**
- mutation: AC1 `select` ignores `match.mockkey` -> `server.test.mjs` row 7 (the keyed pair) red; reverted, 131 of 131.
- mutation: AC1 the loader lets one prompt text repeat under one key -> `scenarios.test.mjs` "one prompt text twice under one key is refused" red; reverted.
- mutation: AC2 `B/guide-watch.json` reply 0 is the text, not `start_watch` -> `TestWatchPrompt` red (reply text, request count) and, live, 02 red on the reply text of the turn; reverted.
- mutation: AC3 `B/guide-reminder.json` loses its `mockkey` and `B/guide-reminder-triage.json` is set aside -> `TestReminderPromptTriage` red, `TestGuidePromptSetsReminder` red ("the turn's triage decision is act, and not a fallback") and, live, 03 red on the Fallback flag ("and no Fallback flag" expected 0, received 1); reverted.
- mutation: AC4 `Core/Rule/Notify.cls`: the demo-mode send loses SimPhoneOut (the code's rule for any other Kind; the incident has no rule of its own) -> the online step 4 red on "the simulated phone has the incident notice" (and the second visitor red); reverted.
- mutation: AC4 the online step 5 re-declared `notBuilt(..., '11.1')` -> the report check FAIL ("wanted exactly one passed case matching /^step 5:/", "wanted 7 passed cases, found 6", the skipped case has no 31.4 text); reverted.
- mutation: AC5 `web/src/app/chat/decision-strip.ts` renders no trace link -> the real-mode dry run red in 02 and 03 on `expectDecision` ("and one trace link", expected 1, received 0); reverted, bundle rebuilt.
- mutation: AC5 `OCUTALON_DEMO_PATH_MODEL=zz` -> the run errors before any step with `OCUTALON_DEMO_PATH_MODEL is mock or real, not "zz"` (`npm --prefix web run e2e:demo-path`, no stack needed).
- mutation: AC5 the gate: the point call removed from the real branch of `test-demo-path.sh` -> `test-demo-path-gate.sh` red (three FAIL lines: the call order and the failing-point run); reverted.

**Review-pass additions (Rule 19; each applied, red observed, reverted, `git status --short` and `git diff --stat` unchanged, then green):**
- mutation: AC5 `parseModel` returns `mock` for an unknown value instead of throwing -> `demo-path-summary.test.mjs` "fail before any step on a model value that is neither mock nor real, and name the value" red; reverted, 36 of 36.
- mutation: AC5 the specs call the key helpers on `real` (02's `beforeAll` without `if (ON_MOCK)`, 06's `afterAll` without `if (!ON_MOCK) return`) -> the real-mode dry run red: `the specs never point the runners' keys on the real model` in 02 and `the specs never restore the runners' keys on the real model` in 06 (`DEMO-PATH 2 of 6 steps ran ..., 5 failed`); reverted, the dry run green again in 217 s.
- mutation: AC4 the online `askToWatch` sends the watch prompt through the composer instead of the guide's Send -> `live online-demo-path -g 'second visitor'` red on `with the guide caption` (expected `/^From the demo guide/`); reverted, the full unit green in 198 s. The load phase's removed override (`OCUTALON_LOAD_WATCH_TEXT`) is not pinned by this unit, because a marker beats a keyed prompt on the mock; the default text with `fromGuide` true is pinned by `test-online-load.sh`.
- mutation: AC3 `B/guide-watch-triage.json` set aside -> `OcuTalon.Test.Demo.GuidePrompts` `TestWatchPromptTriage` red (selected by the prompt, the scenario guide-watch-triage, act and no fallback); reverted.
- mutation: AC7 `ci/units.sh` swapped back (`live:install-script-live` in `image`) -> `test-ci-config.sh` red (`i-reads-declared-example` names group install-fresh, and the input patterns of the IRIS groups); reverted, all rules pass.
- Final runs after the review patches: `live demo-path` (mock) 240 s and `live demo-path` with `real` 217 s, both `6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed`; `live online-demo-path` 198 s (7 passed, 3 skipped, L1 and L2 PASS); `live sign-in --part 2/2` 318 s (96 passed, `reminder/chat.spec.ts` included, which sends the reminder prompt through the composer); `npm --prefix web test` 1136 of 1136; `test-mock.sh` 131 of 131; the gate, `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh`, `test-class-rules.sh` and `test-online-load.sh` pass; `ci/changes.sh` prints seven GROUP lines.

### QA record (qa stage, 2026-10-31)

Every AC already had a pinning test with an implement-stage `mutation:` line on this tree (HEAD `ae6e9b47` code, unchanged since). AC6 (a search) had no pinning test; one was added. The QA stage re-demonstrated one mutation per AC where it could be done cheaply, and the AC2/AC3 pair live. Each was applied, red observed, restored from a scratch backup, and `git status --short` and `git diff --stat` compared byte-identical, then green again.

- Baselines on the tree: `node --test ci/mock/test` 131 of 131; `npm --prefix web test` 1136 of 1136 (1142 with the QA file); `test-demo-path-gate.sh` and `test-ci-config.sh` all pass; `npm --prefix web run lint` exit 0.
- mutation (QA): AC1 `select` ignores `match.mockkey` -> `ci/mock/test/server.test.mjs` row 7 (a keyed guide prompt answers only the agent it names) red, 130 of 131; reverted, 131 of 131.
- mutation (QA): AC2 `B/guide-watch.json` reply 0 is the text, not `start_watch` -> live `demo-path` 02 red on `the "Orders production" check row shows` (expected 1, received 0); 04 to 06 red as a cascade (no watch, no incident); reverted.
- mutation (QA): AC3 `B/guide-reminder-triage.json` set aside -> live `demo-path` 03 red on `its chip is Act: the mock answered the Triage request with its own scenario` (expected Act, received Tell now); reverted (same live run as AC2; one run of 6 min 43 s, including the lane wait).
- mutation (QA): AC5 `parseModel` returns `mock` for an unknown value -> `web/scripts/demo-path-summary.test.mjs` "fail before any step on a model value that is neither mock nor real, and name the value" red, 35 of 36; reverted, 36 of 36.
- mutation (QA): AC5 the gate: the point call replaced by `keys_ok=1` in `docker/tests/test-demo-path.sh` -> `test-demo-path-gate.sh` red, three FAIL lines (call order `point read npm read` missing `point`; keys that cannot be pointed do not fail the dry run; npm ran after keys that could not be pointed); reverted, all checks pass.
- mutation (QA): AC7 `ci/units.sh` swapped back (`live:install-script-live` to `image`, out of `install-fresh`) -> `test-ci-config.sh` red (`i-reads-declared-example` names group image, and the input patterns of the IRIS groups); reverted, all rules pass.
- mutation (QA): AC6 a retired name (`armCountdown`) re-added as a comment in `web/e2e/support/devices.ts` -> `web/scripts/retired-demo-path-names.test.mjs` "names armCountdown in no file outside _bmad-output" red; reverted, 6 of 6.
- AC4 (online steps 2 to 5, the report check) and AC3's IRIS half keep their implement-stage mutation lines (the Notify SimPhoneOut mutation, the `notBuilt` report-check mutation, `TestWatchPromptTriage`, `TestReminderPromptTriage`); not re-run: a live `online-demo-path` and the IRIS classes need the lane for another ~4 min each and the lines are current.
- Test file added (QA): `web/scripts/retired-demo-path-names.test.mjs` (AC6; in the default suite, `npm --prefix web test`).
- Teardown: `ci/iris.sh teardown` for tag `e11s7q`; no lane-a lock of this stage is left.

### Code-review record (code-review stage, 2026-10-31)

Each mutation was applied, red observed, the file restored from a scratch copy, `git status --short` and `git diff --stat` compared byte-identical, then green again.
- mutation (CR): AC5 the unit's Playwright call pinned to `OCUTALON_DEMO_PATH_MODEL=mock` in `docker/tests/test-demo-path.sh` -> `test-demo-path-gate.sh` red, three FAIL lines ("Playwright got 'OCUTALON_DEMO_PATH_MODEL=mock', not" `=real`, `unset` and `=zz`); restored, 53 PASS.
- mutation (CR): AC5 `parseModel` throws on an empty value -> `web/scripts/demo-path-summary.test.mjs` "take the real and the mock model, and an empty value as mock" red, 35 of 36; restored, 36 of 36.
- mutation (CR, hermeticity): `playwrightEnv` keeps the shell's value, run with `OCUTALON_DEMO_PATH_MODEL=zz` exported -> "skip every part that needs the stack" red, 35 of 36; patched, 36 of 36 with `zz` exported. The gate run with `OCUTALON_DEMO_PATH_MODEL=real` exported: all checks passed (53 PASS; the verification layer saw 3 FAIL before the patch).
- mutation (CR): AC1 `B/guide-watch.json`'s `start_watch` typed `start-watch` -> `ci/mock/test/constants.test.mjs` row 16 (tool names) red, "B/guide-watch.json: start-watch"; restored, 5 of 5.
- mutation (CR): AC3 `B/guide-watch-triage.json`'s prompt text changed -> `web/scripts/guide-view.test.mjs` "key the exact text of the guide's step 1 and step 2 prompts" red; restored.
- Live after the patches (lane A, tag `e11s7c`, after `ci/iris.sh build`):
  - `live online-demo-path`, with `OCUTALON_DEMO_PATH_MODEL=zz` and `OCUTALON_LOAD_WATCH_TEXT='[[mock:no-such-scenario]] Watch it now'` exported: 202 s; 7 passed, 3 skipped, the report PASS, L1 and L2 PASS. This covers the model pin, the cleared load text, and step 5's phone line matched exactly with " ET".
  - `live demo-path` (mock): 186 s; `DEMO-PATH 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 7 of 7 passed`; every audit PASS line. This covers 05's phone line matched exactly with no suffix.
- Hermetic checks: `test-mock.sh` 131 of 131; `npm --prefix web test` 1142 of 1142; `npm --prefix web run lint` exit 0; `test-ci-config.sh` all rules passed.
- Teardown: `ci/iris.sh teardown` for tag `e11s7c` left nothing behind, and no lane-a lock is left. No warm stack was used.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-31).** Planned only, with nothing implemented, and halted after planning as the dispatch asked.
- **This story keeps:** U-194's keyed-prompt match in the mock, DW-433, DW-307 and step 2 through the guide's Send in both runs; DW-221 (the online steps 2 to 5); the real-model switch; and the CI swap of `live:online-demo-path` and `live:install-script-live`.
- **For the lead:**
  - the proposed Story 11.10 (the failure paths and the coda, with their criteria verbatim; Design Notes, Proposed split);
  - the non-blocking note on the spine's AD-22 "Logs and state" grammar.

**Implement and review (2026-10-31).**
- **Implemented:** U-194's keyed prompt match in the CI mock (`ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, three test files); the four `B/guide-*` scenarios (watch and reminder, Chat and Triage), with `A/watch-act-orders.json` deleted; the step functions, `expectDecision` and the `OCUTALON_DEMO_PATH_MODEL` switch in `web/e2e/support/demo-path.ts`; the web run's 02 to 06 and the online run's steps 2 to 5 through them (DW-433, DW-307, DW-221); the real-model dry run in `docker/tests/test-demo-path.sh` and its gate; the `GuidePrompts` and `ReminderChat` classes; and the swap of `live:online-demo-path` and `live:install-script-live` in `ci/units.sh` with its pin in `test-ci-config.sh`.
- **Files changed:**
  - `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, `ci/mock/test/{server,scenarios,constants}.test.mjs`: the keyed prompt in the loader and the selection, with tests.
  - `ci/mock/scenarios/B/guide-{watch,reminder}.json` (keyed `chat`) and `guide-{watch,reminder}-triage.json` (new, keyed `triage`); `A/watch-act-orders.json` deleted.
  - `src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls`, `Test/Schedule/ReminderChat.cls`: the new and changed IRIS tests.
  - `web/e2e/support/demo-path.ts`, `devices.ts`; `web/e2e/demo-path/02` to `06`; `web/e2e-online/demo-path/demo-path.spec.ts`, `web/e2e-online/support.ts`; `web/scripts/demo-path-summary.test.mjs`.
  - `docker/tests/test-demo-path.sh`, `test-demo-path-gate.sh`, `test-online-demo-path.sh`, `test-ci-config.sh`; `ci/units.sh`.
- **Review:** 4 layers, 42 findings: 7 patched (3 medium root causes: the page-derived clock oracle, the unpinned model parser, the key rule that could not fail; and 4 low: the second visitor's guide caption, two mutation runs), 0 deferred, 35 rejected with their reasons in the Review Triage Log.
- **Follow-up review recommended: true.** Three medium entries were patched, and the patches (the real-model guard in `devices.ts`, the two parser tests, the caption assertion and the fixed clock oracle) were checked by mutation and live runs but not read by a second review layer.
- **Verification:** all `## Verification` commands ran green on the final tree (numbers under "Implementation record" and its review-pass additions); mutations recorded for every AC; no real key; every lane A stack torn down.
- **Residual risks:**
  - The `real` branches run only in the dry run on the CI mock, and their first run on the real model is Story 11.3's or 38.2's.
  - Task 0's baseline seconds were not taken. `image` is at most 31.4 min in the estimate, and the lead measures it on this story's CI run.
  - `_bmad-output/implementation-artifacts/cycle-log-epic-11.md` is the lead's file, modified by the lead during this run, and is not part of this commit.
