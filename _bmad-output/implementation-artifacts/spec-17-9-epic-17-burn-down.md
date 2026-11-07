---
title: 'Story 17.9: Epic 17 burn-down'
type: 'bugfix'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Three items are left in Epic 17's ledger:
- DW-771: the settings model Test checks a decide or diagnose reply against the runner's `ReplyClass`. The fixed test input cannot produce a valid `DiagnosisPayload` (it needs an evidence pack), so a working diagnosis model is reported as "Didn't answer" (fallback `invalid`).
- DW-786: `Checks.Coverage.Live` repeats `Checks.Process.Run`'s live-read logic (the not_checked reason chain, the cut rule, the state text, the failure wording and the capital letter), so the digest's coverage rows and the checks' results can drift.
- DW-728: `docs/bridge-guide.md` names `RetryItem` and `RetryOf` only in its appended "Second-model retry" section, not in its reference tables.

**Approach:**
- DW-771: in `Decide.Conclude`, a model test request (`Settings.IsTest`) of kind `decide` or `diagnose` counts as usable on any non-empty reply text and is never checked against `ReplyClass` (the spine's Conventions row "Settings model Test").
- DW-786: make `Process`'s live-read rules public class methods of `OcuTalon.Checks.Process`, extended from its private `Finding`, and have both `Process.Run` and `Coverage.Live` call them. Nothing either path produces changes.
- DW-728: add one row to each of the two guide tables, built from the guide's existing sentences.

## Boundaries & Constraints

**Always:**
- **DW-771, the model test (Conventions "Settings model Test"; AD-8, AD-19, AD-20).**
  - The rule applies only to a request that `Settings.IsTest` names (its `ItemId` starts with `test.`) and that has kind `decide` or `diagnose`.
  - Such a request is usable when its reply text is not empty once white space and control characters are stripped. `CheckReply`, the reply filter, the payload check and the user rule do not run for it.
  - Its Decision row has `Fallback` 0, outcome `tellnow`, and empty `Reasons`, `Confidence` and `Payload`, so no unvalidated model text is stored. Its answer is the row's `DecisionResponse`, so `TestAnswer` gives `{answered: true, reason: ""}`.
  - Everything before the reply is unchanged: the prechecks, the timer, `CheckSettings` (a decide or diagnose runner still needs a `ReplyClass` setting), the failure-text classification (`refusal`, `cut_off`, `empty`, `error`, `timeout`), "never retried" (AD-8), Usage owned by `instance`, no sampling parameters and no key.
  - A `turn` test (ChatAgent) is unchanged: a turn has no reply class.
  - Every request that is not a test is unchanged.
- **DW-786, one live-read helper (AD-28; Rule 2).**
  - It is a refactor with no change in behaviour. Neither path changes any result, reason, finding, word, capital letter, catalog key or part order it produces.
  - The shared rules live once, as public class methods of `OcuTalon.Checks.Process`, which already holds every `FINDING*`/`REASON*` parameter that both paths use. The rules are:
    - the not_checked reason chain (unreadable, not current, timeout, could not be read, too many to count);
    - the scoped failure count;
    - the cut rule;
    - the state text;
    - the failure wording;
    - the join with ", " and the upper-case first letter.
  - `Process.Finding` keeps its job, but is built from these methods.
  - `Coverage.Live` keeps the parts and the key choice that only it has (items in error, disabled items, queued and waiting messages, and the digest key), in today's order. It holds no copy of the shared rules.
  - The reason-to-key mapping that `Coverage.RecordRun` and `Coverage.Live` both need is one method of `Coverage`. That mapping is: timeout gives timeout; unreadable and not current give unreachable; anything else gives error.
  - `Process`'s parameter set and its values stay exactly as they are (`Test.Bridge.Gate.CheckTexts` and `Test.Eval.Cases` read them).
- **DW-728, the guide tables.** Exactly two new table rows, each the verbatim text under Design Notes. No other line of the guide changes.
- Contended files (Epic 19) may be edited only where Epic 19's branch has not changed them, and each edit is listed as a footprint extension: `Test/Bridge/SettingsApply.cls`, and `docs/bridge-guide.md` (Epic 11, which has no branch changes). Source is ASCII, and comments state the contract (Rule 14).
- Tests use the CI mock only, in lane A throwaways, and reuse the existing scenarios `invalid-reply`, `empty`, `diagnosis` and `retry-refusal`.

**Never:**
- Any edit to `Test/Bridge/{Decide,Gate,CodeRules}.cls`, `Test/Agent/{Constants,Instructions,Runners}.cls`, `ci/units.sh`, `ci/mock/**`, `docker/tests/lib-live.sh`, `Install/Registry.cls`, `Tools/Names.cls` or any other path that Epic 19's branch changed. Also no edit to any existing `Test/Checks/**` file, the spine, or a Lane B class or test (U-177).
- A new, renamed, moved or re-valued `FINDING*`/`REASON*` parameter of `Checks.Process`, or any change to a check result or digest row.
- Any guide wording beyond the two rows: in particular not the Settings intro (DW-773), nor the one-attempt rows of the DW-728 occurrence (see Design Notes).
- DW-483, or any change to the purge, `Reconcile`, `Redact`, `KeyProof` or `list_productions` (Story 30.7).
- A real provider, a real key, a real Telegram bot, the public IPM registry, or any destructive run on `ocutalon-slot-a`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Diagnosis Test, a reply that fails `DiagnosisPayload` (DW-771) | `TestRequest("DiagnosisAgent")` with `[[mock:invalid-reply]] ` before its input | `TestAnswer` `answered` 1, `reason` "". One mock request, on the agent's model, with no sampling parameter. The Decision row has `Fallback` 0 and empty `Payload`, `Reasons` and `Confidence`. Usage is owned by `instance` | none |
| Triage Test, an invalid reply (DW-771, every runner) | `TestRequest("TriageAgent")` + `invalid-reply` | `answered` 1, one mock request | none |
| Diagnosis Test as built (DW-771's symptom) | `TestRequest("DiagnosisAgent")` unmarked (the mock's `diagnosis.json`: a tool call, then a diagnosis that the check refuses) | `answered` 1, reason "" | none |
| Test, empty reply | Diagnosis Test + `[[mock:empty]]` | `answered` 0, `reason` `empty` | fallback |
| Test refused | Triage Test + `retry-refusal`, second model set | `0`/`refusal` after one request, never retried (`TestModelTestNotRetried`, unchanged) | fallback |
| Not a test (control) | The same diagnose request with an ordinary `ItemId` + `invalid-reply` | Fallback `invalid`, as today | fallback |
| Same read, both paths (DW-786) | One read (an outcome, a state, rows, a cut) fed to a `Process` run and to a `Coverage` live read, with no items in error, disabled items, queues or incidents | The same result and finding from each. The reason chain, the counts, "At least", the order and the capital are equal | not_checked as the reason |
| Guide tables (DW-728) | `docs/bridge-guide.md` | The runner-settings table has a `RetryItem` row and the Request table has a `RetryOf` row. `test-bridge-guide.sh`'s table rule flags a guide that lacks either | check FAIL |

</intent-contract>

**DW-850 (Contest Planner ruling, about 04:55Z 2026-11-07; PUBLIC TEXT, exact; re-owned to this story by the owner):** `docs/bridge-guide.md` describes what 1.0.3 does about the second-model retry. Land these EXACTLY, as one separable hunk of `docs/bridge-guide.md`, each pinned by a fixed-strings rule in `docker/tests/test-bridge-guide.sh` with a mutation shown red. Each NEW replaces the whole OLD line at the named line (the OLD text is in the lead's draft; it is the current line):
- L159, the `TimerSeconds` row, becomes:

    | `TimerSeconds` | 60 | How long `Decide` waits for the runner's reply, in whole seconds, from 12 seconds to 110 seconds. When it passes, the fallback route is taken with the reason `timeout`, unless the second-model retry is sent. The retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer. See "Timeouts" and "Second-model retry". |

- L160, the `DecisionTokenBudget` row, becomes:

    | `DecisionTokenBudget` | 0 (none) | The token budget of each attempt of a decision, checked against the attempt's estimate before it is sent. A request whose estimate is above it takes the fallback route with the reason `budget`, and is never sent. A second-model retry is checked against it again, on its own estimate. The budget is not a total over both attempts. |

- L197, the Timeouts paragraph, becomes:

    `TimerSeconds` is the one timer. A decision with a second-model retry has two attempts, which share the 110 seconds: the retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer (see "Second-model retry"). Two things depend on it, and `OcuTalon.Bridge.Timeouts` works both out so that no other place holds a second copy of a number:

- L202, the Timeouts paragraph, becomes:

    The timer can be 12 seconds at the least and 110 seconds at the most. After you change `TimerSeconds`, edit the `ProviderConfig` row so that its `http_config` is the new `Derive(timer)`'s (for a retry runner, `Derive(Timeouts.RetryTimer(timer))`'s, see "Second-model retry") and update the production, or keep the provider in the Config Store as an entry and let `Timeouts.Apply(timer)` change the timer, the entries and the runners together. Apply needs each runner's `ProviderConfig` to be `@{config:<name>}`, and restarts `Decide` and the runners.

- L273, the fallback route, becomes:

    When the model cannot give a usable answer, `Decide` does not guess. When a second model is set, `Decide` may first try the request once on it, as "Second-model retry" says, and takes the fallback route only when no retry is sent or the retry gives no usable answer either. It records one decision with the outcome `tellnow`, `Fallback` 1 and the reason (after a retry, the last attempt's), keeps no model text, and answers with it, so that the person is told. A fallback starts no tool, fix or approval. The reasons:

- After L347 (the "never retried" list of the Second-model retry section), add the bullet:

    - A model test request (its `ItemId` starts with `test.`), so that the test says whether the first model answered.

- L242, the `DecisionResponse.Model` row: NOT YET. Its ruled clause did not match the code exactly (the lead sent a correction to the Planner); leave the row as it is until the lead passes the ruled row.
- No other wording in the guide changes.

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`
  - Class doc :54-56 (the CheckReply sentence) and :110 (the test bullet).
  - `Conclude` :1324: the decide/diagnose branch calls `Interpret` at :1352. The row is built at :1370-1376 and the answer comes from `ResponseFromRow` at the end. `Interpret` :1480 and `Judge` :1501 are unchanged.
  - `TryRetry` :667 already calls `Settings.IsTest`. `CheckSettings` :885 and `CheckReplyClass` :895 stay as they are.
- `src/bridge/cls/OcuTalon/Bridge/Settings.cls`: doc only. The class doc's TestRequest/TestAnswer bullet is at :32-38, the `TestRequest` doc at :366-369 and the `TestAnswer` doc at :400-402. They should say that a test is a connection test, with no reply-class check. `TESTINPUT` :68 is unchanged.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsApply.cls` (contended folder; Epic 19's branch has not changed this file):
  - Class doc :1-22.
  - `TestModelTestEachAgent` :319, and its doc :317-318: the markers keep each test to one mock request, because `diagnosis.json` and `chat.json` begin with a tool call.
  - `TestModelTestNotRetried` :364.
  - Helpers: `Prepare` :499, `Arm` :555, `Ask` :562, `AssertSent` :579, and `..ItemIds` for the clean-up.
  - It runs the requests through `#FIXTURE` `Run`/`Drain` and the mock's `LogMark`/`LogSince`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls` :441-474: a diagnose request with `invalid-reply` is the fallback `invalid`. This is the non-test control. Run it, do not edit it.
- Scenarios, read-only: `ci/mock/scenarios/A/invalid-reply.json` (one reply that fails every payload class), `empty.json`, `diagnosis.json` and `diagnosis-unknown.json`.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`
  - Class doc :49-54 ("Result").
  - Parameters `FINDING*` :107-125 and `REASON*` :128-136.
  - `Run` :464, with the read :476, the scoped count :486-492, `cut` :493, the reason chain :503-512 and the result :513-519.
  - `Unclosed` :622 stays Process's own. `Finding` :642 is private today and holds the state text, the failure wording, the incident text, the join and the capital.
- `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`
  - Class doc :22-24.
  - `WatchRow` :270, which calls `Live` at :325.
  - `Live` :332-404 is the copy: the reason chain and key :350-360, the count :361-369, the cut and too-many :370-374, the state text :380-381, the failure wording :384-387 and the join and capital :400-401. The parts that only Live has are :382-383 and :388-398.
  - `RecordRun` :486 maps a finding to the CheckRun reason at :492. `Fill` :443. The seam `Read` :471.
- Pins that must stay green unedited:
  - `Test/Checks/Runs.cls`: `TestPassed` :201, `TestFailed` :228, `TestScope` :253, `TestNotChecked` :302, `TestWindow` :330, `TestFindingsRender` :628.
  - `Test/Digest/Coverage.cls`: `TestLiveRead` :375, `TestReasonMap` :315, `TestFailedRun` :357, `TestFixedStrings` :522.
  - `Test/Digest/Runs.cls`: `TestProcessRunRecorded` :61, `TestReasonMap` :93, `TestRecordRunReasons` :141.
  - `Test/Bridge/Gate.cls` `CheckTexts` :2133, which reads every `FINDING*`/`REASON*` parameter of Process. It is contended: run it, do not edit it.
  - `Test/Eval/Cases.cls` :214.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Runs.cls` is where the new DW-786 test goes. It already drives a shadow `Test.Checks.Probe` (`Host` :174, `Watch` :191, `Tick` :206) and `Test.Digest.CoverageProbe` (`FeedRead`, `Calls`, `Reset`). `Clean` :48 removes the fixtures.
- `docs/bridge-guide.md`: the runner-settings table :175-183 (its last row is `ReplyClass` :183), the Request table :206-223 (its last row is `Compact` :223), and "## Second-model retry" :334-339 (the source sentences).
- `docker/tests/test-bridge-guide.sh`:
  - Header :1-24.
  - `names_of`/`properties_of` :293-300 and `reference_names` :305-318.
  - The rule pattern: a rule with a break sample and a keep sample (`break_ref` :347), and one PASS/FAIL line per rule.
  - It is not contended. It is in `CHECK_SCRIPTS` already.
- Measured while planning: of every setting of `Decide`, `Adapter.Agent` and `AgentRunner`, the four AI Hub runner settings and every `Request` property (36 names), only `RetryItem` and `RetryOf` are not the first cell of a guide table row. (`DecisionResponse.Payload` is described in prose, and the new rule does not cover it.)

## Tasks & Acceptance

**Execution:**
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: in `Conclude`, a usable-reply branch for a model test of kind `decide`/`diagnose` (DW-771), as Always says. Keep `Interpret` for every other decide or diagnose. Update the class doc and the `Conclude` doc (step 1 and step 3).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Settings.cls`: doc only. The model test is a connection test: answered on any non-empty reply within the timer, with no reply-class check.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsApply.cls`: add `TestModelTestIsAConnectionTest` (DW-771). It covers the matrix rows Diagnosis Test invalid reply, Triage Test invalid reply, Diagnosis Test as built, Test empty reply, and Not a test, each with its assertions (answer, mock request count, model, no sampling parameter, the row's empty `Payload`/`Reasons`/`Confidence`, Usage owned by `instance`). Clean up through `..ItemIds` and `Arm`. Update the class doc and `TestModelTestEachAgent`'s doc.
- [ ] `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: the shared public class methods (DW-786; for example `NotCheckedReason(outcome, state, unread, cut, failures)`, `ScopedFailures(rows, sessionRef, onlineDemo)`, `IsCut(rows, limit)`, `StateText`, `FailureText`, `Joined(parts)`). `Run` and `Finding` call them. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`: `Live` calls the same methods and keeps only its own parts and key. One reason-to-key method serves `Live` and `RecordRun`. Update the doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Digest/Runs.cls`: add `TestOneLiveReadHelper` (DW-786).
  - (a) Structure, from `%Dictionary.MethodDefinition` implementations: `Coverage.Live` names no `REASON`/`FINDING` parameter of Process and contains no `$ZConvert(`. `Live`, `Process.Run` and `Process.Finding` each call the shared methods.
  - (b) Parity: for the reads unreadable, not_current, timeout, unknown state, thrown, cut with no session failure, stopped with one session failure, suspended with a cut and the session's failures, troubled with two, and running with nothing:
    - the result and finding of a shadow `Process` run (one `Tick` over a fixture check fed the read);
    - and the live row of `Build` (CoverageProbe `FeedRead` of the same read, on a watch whose latest run passed);
    - are equal.
  - Update the class doc.
- [ ] `docker/tests/test-bridge-guide.sh`: add a rule `tables` (DW-728). Every setting of `Decide`, `Adapter.Agent` and `AgentRunner`, every AI Hub runner setting, and every `Request` property is the first cell of a table row (`` | `<name>` | ``). The rule has a break sample (the `RetryItem` row removed) and a keep sample, as the other rules do, and the header gets one line for it.
- [ ] `docs/bridge-guide.md` (DW-728): append the `RetryItem` row after the `ReplyClass` row and the `RetryOf` row after the `Compact` row, verbatim from Design Notes. Nothing else changes. The rows are reused text and not new public wording, so this task is not gated. Any other word needs the Planner (see Design Notes).

- [ ] DW-850: the ruled `docs/bridge-guide.md` strings above, landed exactly as one separable hunk (L159, L160, L197, L202, L273, and the bullet after L347; not L242 yet), each pinned by a fixed-strings rule in `docker/tests/test-bridge-guide.sh`, with a mutation shown red (one character changed in a landed string). `test-bridge-guide.sh` passes.

**Acceptance Criteria:**
- Given a working diagnosis model whose reply fails `DiagnosisPayload` validation, when the settings model Test is sent to `Decide` through the running production, then `TestAnswer` reports it answered with no reason, and no model text is stored in its Decision row (DW-771).
- Given any other decide or diagnose request with the same reply, when `Decide` concludes it, then it is still the fallback `invalid`.
- Given the existing tests of `Checks.Process` and `Checks.Coverage` (Code Map pins), when they run after the refactor, then every one passes unedited. `TestOneLiveReadHelper` shows that the two paths call the one helper and give equal results for the same read (DW-786).
- Given the guide, when `bash docker/tests/test-bridge-guide.sh` runs, then every rule passes, including `tables`, and `git diff docs/bridge-guide.md` shows exactly the two added rows (DW-728).

## Spec Change Log

- 2026-11-07 lead: DW-850 added (Contest Planner ruling about 04:55Z: the bridge guide's one-attempt wording, exact strings; the Model row's clause is held for a correction).

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-8: `Decide` alone classifies, and a model test is never retried.
- AD-19: the bridge settings APIs (`TestRequest`/`TestAnswer`).
- AD-20: Usage owned by `instance`.
- AD-28: check results come only from `Checks`; the digest rows come from `Coverage.Build`.
- AD-18: the checks.
- AD-2: the bridge names no OcuTalon package; the new branch calls only `Bridge.Settings`.
- AD-5: no storage change.
- AD-22: the CI mock.
- AD-29/AD-33: Lane A owns `Decide`, `Checks` and `Digest`.
- Conventions: "Settings model Test".

No AC contradicts an AD's Rule. The Conventions row, added by the Planner's ruling of 2026-11-06, is the exception to AD-8's `invalid` that this story builds. No spine edit is needed.

**Ledger (Rule 17):**
- DW-771 is addressed by the `Conclude` task, the first six matrix rows and `TestModelTestIsAConnectionTest`.
- DW-786 is addressed by the `Process`/`Coverage` tasks, the parity row and `TestOneLiveReadHelper`.
- DW-728 is addressed by the two rows and the `tables` rule. Partly declined: the occurrence of 2026-11-05 asks to widen the fold to the one-attempt wording (the `TimerSeconds` and `DecisionTokenBudget` rows, Timeouts, the fallback route and `DecisionResponse.Model`). That would be new public text, and Story 17.9's AC says "no other wording changes". The lead's adjudication should re-own that residual, or route it to the Planner as public text.

**Decided in-stage:**
1. The spine and epics say "`DiagnosisReply`", but the class is `OcuTalon.Watch.Msg.DiagnosisPayload` (the `ReplyClass` of `DiagnosisAgent` in `Production.cls`). The test names the real class.
2. The connection rule covers `decide` and `diagnose`. A `turn` has no reply class, and its filtered-empty check is AD-28's guard, so the Chat test stays as it is.
3. A test's row keeps no model text (empty reasons, confidence and payload), because nothing validated it. Owner `instance` publishes no `decision.recorded` (`Core.BridgeSink` :19), so no page or channel sees it.
4. `CheckSettings` still requires a `ReplyClass` setting for decide and diagnose runners. It checks the configuration, not the reply.
5. The DW-786 helpers live in `Process`, beside the parameters they read, because the ledger said "make `Finding` callable". Coverage's own parameters stay in Coverage.
6. The DW-786 "same helper" pin is structural (a refactor cannot be told apart by behaviour), and the parity table pins that the outputs are equal. Both go in `Test.Digest.Runs`, which already drives both paths, so no new test class is needed and `ci/units.sh` is unchanged.
7. The DW-728 table rule covers settings and `Request` properties only. `DecisionResponse.Payload` stays in prose.

**Guide rows (DW-728), verbatim, built only from the "Second-model retry" sentences and the tables' existing `See "<section>".` form:**

```
| `RetryItem` | empty | It names the retry runner of that runner: another enabled `OcuTalon.Bridge.Operation.AgentRunner` item of the production, whose `Model` setting is the second model. An empty value means no second model. See "Second-model retry". |
```
```
| `RetryOf` | `Decide` sets it, on the one retry request it sends, to the first runner's item. A value that a caller sets is ignored. See "Second-model retry". |
```

**Integration ACs (Rule 1).**
- The shared live-read helper's consumers are in this story: `Coverage.Live`, through the digest's `Coverage.Build`, and `Process.Run`, through the `check_status` and check events. The parity row exercises the real `Build` and the real `Process` handlers.
- Consumes: Story 17.5's `Coverage.Live` and Story 5.6's `Process.Run`.
- Consumed-by: Story 18.3 (Lane B's settings page Test button reads `TestAnswer` through `SettingsOps`).

**Extend, don't copy (Rule 2).** The helpers extend `Process.Finding`. The key mapping is one method shared by `RecordRun` and `Live`. The new tests reuse the existing probes and helpers.

**Footprint (Rule 11).** These were checked on 2026-11-06 with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for N in 19, 7 and 11 (only Epic 19 has changes).
- Footprint extensions:
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsApply.cls` (an Epic 19 folder; that branch has not changed the file);
  - `docs/bridge-guide.md` (Epic 11; that branch has no changes);
  - `docker/tests/test-bridge-guide.sh` (not contended).
- In footprint: `Bridge/Process/Decide.cls`, `Bridge/Settings.cls`, `Checks/Process.cls`, `Checks/Coverage.cls` and `Test/Digest/Runs.cls`.
- Story 30.7: none of its areas are touched.

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`.
- Tags: `e17s9iw` (warm) and `e17s9i` (fresh). QA and review use their own tags.
- Run one call at a time, in the foreground, with `timeout: 600000`.
- Run `ci/warm.sh down` at the stage's end, also after a failure.
- Compile checks on `ocutalon-slot-a` use `iris_doc_load` only (`server`/`namespace` `OCUTALON`).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s9iw ci/warm.sh up`. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s9iw ci/iris.sh class <C>`, one class per call. Expected: `CLASS <C> passed` for:
  - `OcuTalon.Test.Bridge.SettingsApply`, `SettingsValues` and `SettingsStubs`;
  - `OcuTalon.Test.Digest.Runs` and `Coverage`;
  - `OcuTalon.Test.Checks.Runs`.
- (once) The same, for the consumers that must stay green unedited:
  - `OcuTalon.Test.Bridge.Decide`, `SecondModel` and `Gate` (contended, so a red there is `## Clarification Needed`, never an edit);
  - `OcuTalon.Test.Agent.Decide`;
  - `OcuTalon.Test.Digest.AllClear`, `Compose`, `NoFalseClear`, `FailRowsDigest` and `FedRowsDigest`;
  - `OcuTalon.Test.Checks.Turns` and `Snapshot`;
  - `OcuTalon.Test.Eval.Cases`.
- (once) `bash docker/tests/test-bridge-guide.sh`, then `test-class-rules.sh` and `test-boundaries.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s9i ci/iris.sh shard lane-a@Bridge`, then `shard lane-a@Checks`, then `shard lane-a@Digest`, each in its own call. Use `--part k/n` when a call nears 8 minutes. Then `ci/iris.sh teardown`. Expected: every class passes.

**Shared surfaces:**
- the Decision row and answer of a model test (`Test.Bridge.SettingsApply`);
- `Checks.Process`'s parameter set (`Test.Bridge.Gate.CheckTexts`, `Test.Eval.Cases`), which stays unchanged;
- the coverage rows and check results (`Test.Checks.Runs`, `Test.Digest.*`);
- the guide's tables (`test-bridge-guide.sh`).

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate (Rule 19).** Apply each to one file, observe red, and restore it byte for byte:
- `Conclude` checks a test against `ReplyClass` again: `SettingsApply` `TestModelTestIsAConnectionTest` goes red (the diagnosis leg and the leg with the fixed input as built).
- The test branch accepts an empty text: the empty leg goes red.
- The branch ignores `IsTest` (no decide or diagnose request is checked): the Not-a-test leg goes red, and so does `Test.Agent.Decide`.
- The branch keeps the reply as `Payload`: the row assertion goes red.
- `Coverage.Live` makes its own capital letter (`$ZConvert`) again: `Digest.Runs` `TestOneLiveReadHelper` (a) goes red.
- The shared join drops the capital: `Checks.Runs` `TestFailed` and `Digest.Coverage` `TestLiveRead` go red.
- `Process.Run` passes `cut` 0 to the reason chain: `TestOneLiveReadHelper` (b) and `Checks.Runs` go red.
- The guide loses its `RetryItem` row: `test-bridge-guide.sh` `tables` goes red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan stage only: the spec is written and checked against the READY FOR DEVELOPMENT standard. Nothing is implemented.
