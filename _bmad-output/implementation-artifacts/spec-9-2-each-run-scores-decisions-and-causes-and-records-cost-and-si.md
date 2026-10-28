---
title: 'Story 9.2: Each run scores decisions and causes and records cost and size'
type: 'feature'
created: '2026-10-28'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 9.1's runs leave one `OcuTalon.Eval.Data.CaseResult` row per case. But nothing compares a row with its case's expectation, nothing totals cost and request size against NFR-3 and NFR-4, nothing stops a case file that has no expectation, and no CI job runs the set. So no run tells the author whether quality and cost hold.

**Approach:**
- **The report.** `OcuTalon.Eval.Report` (Lane A, new) builds a run's report from its rows and its case files. It scores items by outcome and incidents by cause category and element at fault; the incident scoring is built now, tested on synthetic rows, and fed by Story 9.6. It compares the shares with SM-1 and SM-2, scores the held-out cases on their own, and lists the tell-now cases decided Ignore or Digest. It also lists every decision's cost with the mean, the maximum and the $0.001 flags, and the largest request with the 100,000-token flags.
- **The repository check.** `docker/tests/test-eval-set.sh`, in the hosted `checks` job, fails the build on a case file without its kind, held-out flag, record or expectation.
- **The job.** An `evaluation` job is appended to Lane A's `.github/workflows/lane-a.yml`. It runs `eval/run.sh`:
  - the set against the CI mock, in its own throwaway;
  - the report in the job log and the step summary, with the scores recorded and not gated;
  - then the test-only cases of `eval/mock-wrong/`, which a new `ci/mock/scenarios/A/` scenario answers wrongly and which must score wrong.

## Boundaries & Constraints

**Always:**
- **Scoring**, in one place (`Report.Build`):
  - An `item` or `injection` row is right when it is decided, is not a fallback, and its `Outcome` equals `expectation.outcome`. Both kinds are SM-1's items.
  - An `incident` row is right when it is decided, is not a fallback, its `CauseCategory` equals `expectation.causeCategory`, and its `ElementAtFault` equals `expectation.elementAtFault`, ignoring case and leading and trailing spaces. The fix kind is shown but not scored.
  - A share is the right rows over all the run's rows of that kind. A row still `sent` counts as not right.
  - SM-1 is met when `right * 10 >= total * 9`, and SM-2 when `right * 5 >= total * 4`. With no row of the kind, the share and `met` are null ("not measured").
  - Held-out rows are scored again on their own (items and incidents), with no target.
  - A case that `Start` skipped is listed with its kind and reason, and counts in no score.
- **Cost and size** come from the run's `CaseResult` rows: `DecisionRef` with `CostUSD`, `TurnDecisionRef` with `TurnCostUSD`, and `LargestRequestTokens`. Each decision's model comes from `OcuTalon.Bridge.Data.Decision.Model`, which is read only.
- **The report persists nothing in IRIS:** no table, column or global. It is a `%DynamicObject` plus its Markdown text, and `Save` writes them as files.
- **The switch.** `eval/run.sh` exports `OCUTALON_EVAL=1` for its own throwaway only. No workflow, compose file or class default sets it (owner condition U-131).
- **Test-only cases.** They live only under `eval/mock-wrong/<case>/`, and only they may hold a `[[mock:<name>]]` marker. A run over `eval/` with no names never lists them, because 9.1's `CaseNames` reads only the direct subfolders that hold a `case.json`.
- **The job** follows every rule that `docker/tests/test-ci-config.sh` applies to a workflow file, as `standalone-bridge` does:
  - `[self-hosted, ocutalon]` and the same fork guard;
  - the pinned checkout with `persist-credentials: false`;
  - no secret and no `upload-artifact`;
  - `ci/iris.sh build` first, a last `if: always()` step that runs `ci/iris.sh teardown`, and a timeout.
- **`eval/run.sh`** reaches Docker only through the functions of `ci/iris.sh` and `docker/tests/lib-live.sh` (`stack_start`, `stack_ready`, `iris_script`, `check_session`, `dc exec`). It never pulls the base image and never runs warm, and its exit trap tears its own project down.
- **One source for every enumeration the check reads:**
  - the outcomes from `OcuTalon.Msg.Enum` `OUTCOME`;
  - the cause categories, fix kinds and fix category from `OcuTalon.Watch.Msg.DiagnosisPayload` `CAUSECATEGORIES`, `FIXKINDS` and `FIXCATEGORY`;
  - the case kinds from `OcuTalon.Eval.Report` `CASEKINDS`.

**Never:**
- **Never edit these files:**
  - Epic 7's files: `Watch/IncidentManager.cls`, `Watch/EvidencePack.cls`, `Watch/Notice.cls`, `Watch/Msg/DiagnosisPayload.cls`, `Agent/Diagnosis.cls`, `src/bridge/**`, `Fix/**`, `Test/Watch/**` and the existing `ci/mock/scenarios/A/*` files;
  - any Lane B class, and the `ci/mock/**` code;
  - `.github/workflows/ci.yml`, and in `lane-a.yml` the existing `standalone-bridge` job, the `on:` block and the header;
  - `docker-compose.yml`, `ci/compose.ci.yml`, `ci/iris.sh`, `docker/tests/lib-live.sh` and `docker/tests/lib-scan.sh`;
  - any existing `docker/tests/*.sh`, `test-ci-config.sh` and `test-boundaries.sh` included;
  - `CaseResult`'s properties or storage.
- **Never gate on a score in a mock run.** An SM-1 or SM-2 shortfall is reported and never fails the job.
- **Never build other stories' scope:**
  - Story 9.3's turn cases, `TurnResult` or injection key-phrase rule;
  - Story 9.6's incident path;
  - Story 9.5's release-candidate mode, its 2-of-3 rule or its result file in `eval/`.
- **Never** name the job's runner script `docker/tests/test-*.sh`, and never put the job in `ci.yml` or in a group of `ci/units.sh`.
- **Targets.** Never run anything that starts a production on slot B, or on any target the Verification section doesn't name.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Item right and wrong | Two decided rows. One got `digest` and expected `digest`; the other got `digest` and expected `ignore` | The first is right and the second is not. `items`: 1 of 2, share 0.5, SM-1 not met | — |
| Fallback | Decided, `Fallback` 1, `Outcome` `tellnow`, expected `tellnow` | Not right. Listed under `fallbacks` with its reason, and not in `tellNowMissed` | — |
| Undecided | A row still `sent` | Not right, and still counted in the total. `notComplete` says "not decided" | A problem |
| Incident | Two rows, both `data_format_change`. One has the element ` orderdate ` against the expected `OrderDate`; the other has `CustomerId` | The first is right and the second is not. `incidents`: 1 of 2, SM-2 not met. The fix kind is shown, not scored | — |
| No incident | A run of item rows only | `incidents`: 0 of 0, with share and `met` null | — |
| Targets | 9 of 10 items; 8 of 9 items; 8 of 10 incidents; 7 of 10 incidents | SM-1 met; not met; SM-2 met; not met | — |
| Held out | One held-out item right and one wrong | `heldOutItems`: 1 of 2. Both rows are also counted in `items` | — |
| Tell-now missed | Three rows that expected `tellnow`, decided `ignore`, `digest` and `act` | The first two are in `tellNowMissed`, the third is not | — |
| Cost | Decisions of 0.0002 (a decide), 0.0004 (its turn), 0.001 and 0.000999, and one unpriced decision | Four are priced. The mean is 0.00065 (6 decimals). The maximum is 0.001, with its case. Only the 0.001 decision is flagged. The unpriced one is under `unpriced`, in neither the mean nor the maximum | The unpriced case is a problem ("no cost") |
| Size | Rows of 100,000 and 100,001 tokens, and one empty | The largest is 100,001, with its case. Only 100,001 is flagged. The empty one is under `unknown` | The empty one is a problem ("no request size") |
| Skipped | `Start`'s `skipped` holds `orders-date-format` (an incident), an item with no `itemId`, and a case whose `case.json` cannot be read | All three are listed and none is scored. The incident is `notRunYet`, a kind EvalIn does not send yet, and is no problem | The other two are problems |
| Unscored | A row whose case file is gone, or whose kind is `all-clear` (Story 9.3) | Listed under `unscored` with the reason | A problem |
| Empty run | No row | — | The problem "the run sent no case" |
| Repository check | A `case.json` with any of: no `expectation`; `{}`; an outcome, kind or category outside the enumerations; `heldOut` that is not a boolean; an item with no `item.itemId`; an incident whose snapshot file is missing; a `name` that is not its folder's; a marker outside `eval/mock-wrong/` | `test-eval-set.sh` prints `FAIL cases` (or `FAIL markers`) with each `file: rule`, and `ci/checks.sh` exits 1 | — |
| Job | `eval/run.sh` against the CI mock | The set run has no problem and its report is printed. The mock-wrong run has one case, scored wrong. Exit 0 | A problem, a mock-wrong case scored right, a disabled EvalIn or a stack that is not ready each print `FAIL ...`, and the script exits 1 |

</intent-contract>

## Code Map

**Built by Story 9.1 (use, don't rebuild):**
- `src/ocutalon/cls/OcuTalon/Eval/In.cls`:
  - `:28` `KINDS` = "item,injection", the kinds EvalIn sends;
  - `:39` `REASONKIND`;
  - `:58` `Start(folder, names, .runRef, .sent, .skipped)`, where `skipped` is `[{case, reason}]`;
  - `:84` `Wait(runRef, seconds)`, which returns the rows still `sent`;
  - `:97` `CaseNames`: the direct subfolders that hold a `case.json`;
  - `:191` `Scalar(object, key)`. Reuse it to read case files.
- `src/ocutalon/cls/OcuTalon/Eval/Data/CaseResult.cls`:
  - its fields are at `:23-80` (`RunRef`, `CaseName`, `State` `sent`/`decided`, `DecisionRef`, `Outcome`, `Fallback`, `FallbackReason`, `CauseCategory`, `ElementAtFault`, `FixKind`, `FixParameters`, `CostUSD`, `TurnDecisionRef`, `TurnCostUSD`, `LargestRequestTokens`);
  - `:85` `Open`, `:117` `Remove(runRef, caseName)`;
  - SQL table `OcuTalon_Eval_Data.CaseResult`. A cost that is not known is empty, never 0.
- `src/ocutalon/cls/OcuTalon/Eval/Sink.cls`: fills the row. No change.
- `eval/mail-newsletter/case.json`: an item case that expects `ignore`; the mock's default triage answers `digest`, so it scores wrong on the mock.
- `eval/orders-date-format/case.json`: an incident case that expects `data_format_change`, `OrderDate` and `repair_resend`. Until Story 9.6, `Start` skips it with `REASONKIND`.

**Read only:**
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:6`: `Parameter OUTCOME = "ignore,digest,tellnow,act";`.
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls:16,19,22`: `CAUSECATEGORIES`, `FIXKINDS` ("repair_resend") and `FIXCATEGORY` ("data_format_change"). It is Epic 7's file, so the check reads it and never edits it.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`: `:63` `Model`, `:71` `RefIndex`, so `RefIndexOpen(ref)` gives a decision's model.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls:198-213`: a fallback `ItemDecision` has `Outcome` `tellnow` and `Fallback` 1, and carries the `DecisionRef` when `Decide` answered.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:
  - `:306` `ReadyReason()` is "" once the production runs with every item and the environment is the CI mock's (`GuardReason`);
  - `:456` `PointKeys()` points each runner's Config Store entry at the placeholder `@{env:OCUTALON_MOCK_KEY_HEADER}` and restarts the runners. Without it, the throwaway's runners have no key and every decision falls back.
- `web/e2e/support/devices.ts:180`: the live units call `PointKeys` through an IRIS script in the same way. That is the pattern `eval/run.sh` follows.

**The script's recipe (read only; source it, don't edit it):**
- `release/standalone-bridge.sh`: the sibling Lane A script. It sources `ci/iris.sh`, then calls `setup_tag`, starts its stack, uses `check_session` and `pass`/`fail`/`die`, and exits 1 on a failure.
- `ci/iris.sh`:
  - `:52` `setup_tag`;
  - `:248` `stack_start <label>`, which runs the preflight (the base image is never pulled) and `live_start` (the lane lock, the project and the exit trap);
  - `:256` `stack_ready <title> <start second>`;
  - `:568`: when sourced, it defines its functions and runs nothing.
- `docker/tests/lib-live.sh`: `:243` `dc`, `:273-283` `pass`/`fail`/`die`, `:307` `iris_script <ns>` (prints only the `CHK|` lines), and `:479` `check_session`.
- `ci/compose.ci.yml:15`: passes `OCUTALON_EVAL` through from the environment of `docker compose` (default 0). The Production install step then enables `EvalIn` at the start.

**CI rules (read only):**
- `.github/workflows/lane-a.yml:23-42`: the `standalone-bridge` job, the model for the new job. Its checkout pin is `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`.
- `docker/tests/test-ci-config.sh`:
  - `:444-458`: the workflow rules (permissions, triggers, pins, persist-credentials, runners, fork guard, secrets, image actions with no `upload-artifact` in a self-hosted job, never-skipped, teardown), which apply to every workflow file;
  - `:601-653`: `units` (every `docker/tests/test-*.sh` is in exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or a group);
  - `:1648-1670`: `lane-a` (pins only `standalone-bridge`).
- `ci/units.sh:5`: `CHECK_SCRIPTS`. `NOT_IRIS_INPUT_PATTERN` already excludes `docker/tests/test-*.sh` and `lane-a.yml`. `IRIS_INPUT` claims `eval/`, so a change there runs every `ci.yml` IRIS group (Lane B's line; no change).
- `docker/tests/test-boundaries.sh:84-99`:
  - the ASCII and docker-call rules scan `docker`, `src`, `web`, `.github` and `ci`, not `eval/`;
  - the path and key-like scan (CON-5) covers every tracked file, `eval/` included.
- `docker/tests/lib-scan.sh`: `:11` `scan_files <pathspec>` and `:22` `scan_rule` (a bad sample, a good sample, then the real files).
- `docker/tests/test-demo-path-gate.sh:42,111,171`: the pattern for running Node from a check script (check `command -v node`, write an `.mjs` to `$tmp`, run `node`).

**The mock (read only, except the new A/ file):**
- `ci/mock/scenarios/A/decide-ignore.json`: the shape to follow.
- `ci/mock/scenarios.mjs:12-16,170`: a marker scenario's `match.marker` equals its `name`, which equals its file name.
- `ci/mock/test/scenarios.test.mjs:114`: row 15 loads every committed scenario with no problem. No test pins a count.

**Tests to extend or copy:**
- `src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls`:
  - `:69-89`: the properties `Folder`, `Run1`/`Run2` and `Skipped1`/`Skipped2`;
  - `:108-144` `Prepare`: run 1 is `mail-newsletter,orders-date-format,zz-missing` over `eval/`; run 2 is the fixture folder (`zz-act` expects `act` and is answered `act`, `zz-plain` expects `ignore` and is answered `digest`, and `zz-noid`, `zz-user` and `zz-badjson` are refused);
  - `:159` `WriteFixture`, `:186` `WriteCase`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Sink.cls:395,412`: `NewRun` and the synthetic `Decision` row helper (private, so copy them).
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls:105`: lists the cases of `eval/` through `CaseNames`. A nested `eval/mock-wrong/` holds no `case.json` itself, so it is not listed.

## Tasks & Acceptance

**Execution:**

**Task 0 (measurement).** No platform behaviour here is new:
- 9.1 measured that a marker in an Item's text reaches the mock (`zz-act`) and that `OCUTALON_EVAL=1` at the start enables EvalIn (row 19).
- `PointKeys` is what the live units use.

The first local `eval/run.sh` run is the measurement. Record in Verification its stack start, its ready-and-keys step and each of its two runs. Label CI's job time `(inference)` until the lead's first CI run.

1. **`ci/mock/scenarios/A/eval-tellnow-ignored.json` (new).** Write it before `ci/warm.sh up`, because warm mode refuses a change under `ci/mock`.
   - It is a marker scenario `eval-tellnow-ignored` with one reply: `status` 200 and `text` `{"outcome":"ignore","reasons":["The CI mock answers this test-only case wrongly on purpose."],"confidence":0.9}`.
   - Its shape is `decide-ignore.json`'s.
   - **Why:** AC4's wrong answer. It is a new file because Epic 7 owns the existing ones.

2. **`eval/mock-wrong/tellnow-ignored/case.json` (new).** The test-only item case in Design Notes. It expects `tellnow`, and its text holds `[[mock:eval-tellnow-ignored]]`.
   - **Why:** AC4. Expecting `tellnow` also puts it in the job's `tellNowMissed` list.

3. **`src/ocutalon/cls/OcuTalon/Eval/Report.cls` (new; class methods only; Lane A).**
   - **Parameters:** `CASEKINDS = "item,injection,all-clear,incident"`, `ITEMKINDS = "item,injection"`, `INCIDENTKIND = "incident"`, `FLAGUSD = 0.001`, `FLAGTOKENS = 100000`, and the problem texts.
   - **`Build(runRef As %String, folder As %String, skipped As %DynamicArray = "") As %DynamicObject`:**
     - It returns the report in Design Notes' shape.
     - It reads the run's rows (`%SQL.Statement` with the checked default, `ORDER BY CaseName`) and each row's `<folder>/<CaseName>/case.json`.
     - It scores the rows as the Boundaries say, and fills `tellNowMissed`, `fallbacks`, `notComplete`, `unscored`, `cost` and `size`.
     - It lists each skipped case with the `kind` read from its `case.json` (when that is readable) and `notRunYet`. `notRunYet` is true when the kind is in `CASEKINDS` and not in `OcuTalon.Eval.In`'s `KINDS`.
     - It never throws on a bad case file; such a row goes into `unscored`.
   - **`Problems(report) As %DynamicArray`:** the texts that fail a mock run:
     - no row;
     - each `notComplete` entry: not decided, or a decided row with no `DecisionRef`, no `CostUSD`, no `LargestRequestTokens`, or a `TurnDecisionRef` with no `TurnCostUSD`;
     - each skipped case that is not `notRunYet`;
     - each `unscored` row.
   - **`Text(report, title) As %String`:** Markdown with:
     - the title;
     - a scores table (right, of, share as a percentage with one decimal, target, and met, not met or not measured);
     - the held-out scores, the tell-now cases missed and the fallbacks;
     - cost: how many decisions are priced, the mean, the maximum with its case, the flagged decisions with case, kind, model and cost, and the unpriced ones;
     - size: the largest with its case and the words "estimated by the bridge", the flagged cases and the unknown ones;
     - the cases not complete;
     - the skipped cases, where a `notRunYet` case says "not run until its story";
     - one table row per case: case, kind, held out, expected, got, right.
   - **`Save(report, title, directory, name) As %Status`:** writes `<name>.json` (the report) and `<name>.md` (`Text`) into the directory, and creates the directory when it is missing.
   - **`Run(folder, names, seconds, Output report) As %Status`:** calls `Eval.In.Start`, then `Eval.In.Wait(runRef, seconds)`, then `Build(runRef, folder, skipped)`. When `Start` fails (a disabled EvalIn), it returns that error with `report` set to "".
   - **Why:** AC1, AC2 and the report of AC4.

4. **`src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` (new; warm-safe; `%UnitTest.TestCase`).**
   - **What it covers:** every Report row of the matrix, on synthetic rows: `TestItems`, `TestFallback`, `TestUndecided`, `TestIncidents`, `TestShares`, `TestHeldOut`, `TestTellNowMissed`, `TestCost`, `TestSize`, `TestSkipped`, `TestUnscored`, `TestEmptyRun`.
   - **Also:**
     - `TestOtherRun`: rows of another run are not in the report;
     - `TestText`: the score lines, a flagged decision, a tell-now case missed and a skipped reason are in the text;
     - `TestSave`: both files are written, the JSON reads back equal to the report, and the `.md` equals `Text`.
   - **Setup:**
     - run Refs `zz` plus a `NewRef()` fragment;
     - rows made with `CaseResult.Open` and then completed by setting their fields and calling `%Save`;
     - case folders under the manager's `Temp` directory (`zzreport<fragment>`);
     - one synthetic `Decision` row with a `Model`, from a helper copied from `Test.Eval.Sink`.
   - **Clean-up:** every test removes its rows, its `Decision` row and its folder in `OnAfterOneTest`.
   - **Why:** AC1 and AC2, including scoring incidents now with synthetic rows (lead's instruction).

5. **`src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls` (extend).** Add `TestReport`, guarded like the others, and add it to the class doc's test list. Change nothing else in setup or clean-up. `TestReport` builds the reports of both runs from their real rows:
   - **Run 1** (folder `Eval.In.#FOLDER`, `Skipped1`):
     - `mail-newsletter` expected `ignore` and got `digest`, so it is not right; `items` is 0 of 1;
     - its decide decision is in `cost.decisions` with a cost above 0 and a non-empty model, and `size.largestTokens` is above 0;
     - `orders-date-format` is skipped as `notRunYet`;
     - `zz-missing` is the run's only problem.
   - **Run 2** (`..Folder`, `Skipped2`):
     - `zz-act` is right and `zz-plain` is wrong, so `items` is 1 of 2 with share 0.5 and SM-1 not met;
     - `zz-act` has two decisions (decide and turn);
     - the problems are exactly the three refused cases.
   - **Why:** the Rule 1 integration criterion on the real path.

6. **`eval/run.sh` (new, mode 100755): the evaluation script.**
   - **Its header states the contract:** the usage, the variables, what it checks, and that it is the job's script.
   - **Variables:**
     - `OCUTALON_EVAL_WAIT`: the seconds each run may take, default 180. A value that is not a whole number from 1 to 3600 exits 2.
     - `OCUTALON_EVAL_REPORT_DIR`: where the report files go. The default is a new folder from `mktemp -d` under `${RUNNER_TEMP:-${TMPDIR:-/tmp}}`.
   - **Steps:**
     1. Source `ci/iris.sh`, call `setup_tag`, and `export OCUTALON_EVAL=1`.
     2. `stack_start eval`, then `stack_ready "evaluation" <start>`.
     3. `check_session` in `OCUTALON`: `RunnerFixture.ReadyReason()` is "" and `PointKeys()` is OK. Otherwise `die`.
     4. Run 1, the set: `Report.Run("/opt/ocutalon/eval/", "", <wait>, .report)`, then `Save` it to `/tmp/ocutalon-eval/` as `set`. Print `CHK` lines for the run status, the error, the number of problems, each problem, the number of cases, and each case with its right flag.
     5. Run 2, the test-only cases: `Report.Run("/opt/ocutalon/eval/mock-wrong/", ...)`, saved as `mock-wrong`. In both runs the IRIS session prints a first `CHK` line before it calls `Report.Run`: `iris_script` runs a session again when it printed no `CHK` line, and that early line keeps it from starting a second run.
     6. Copy each `.json` and `.md` out with `dc exec -T iris cat` into the report folder. Print the two `.md` texts, append them to `$GITHUB_STEP_SUMMARY` when that is set, and print `REPORT <folder>`.
   - **Checks (PASS or FAIL lines):**
     - each run started (a disabled EvalIn fails with the director's text);
     - the set has no problem;
     - the mock-wrong run has no problem, at least one case, and every case not right.
   - **Exit:** 1 when any check fails, 0 otherwise. The SM-1 and SM-2 results are printed and never checked.
   - **Why:** AC4, and the consumer of Rule 1.

7. **`.github/workflows/lane-a.yml`.** Append the job `evaluation` at the end of the file, as Design Notes shows. Leave the rest of the file as it is. **Why:** AC4 (AD-29: Lane A's file).

8. **`docker/tests/test-eval-set.sh` (new, mode 100755): the repository check (the hosted `checks` job).**
   - **How it runs:** Node scripts written to `$tmp`, as `test-demo-path-gate.sh` does; `FAIL` when `node` is missing. It uses `scan_files` and the bad/good-sample convention of `lib-scan.sh`. A failure prints `file: rule` and never the file's text. It prints one PASS or FAIL line per rule and exits 0 only when none fails.
   - **`enumerations`:** reads `OUTCOME`, `CAUSECATEGORIES`, `FIXKINDS`, `FIXCATEGORY` and `CASEKINDS` from their classes, and fails naming any that is missing.
   - **`cases`:** every `case.json` below `eval/` passes these rules, and every folder below `eval/` (not `eval/` itself) that holds a file holds a `case.json`. Each case:
     - is a JSON object;
     - has a `name` equal to its folder's name;
     - has a `kind` in `CASEKINDS`;
     - has a boolean `heldOut`;
     - has a non-empty `description` and `recordedBy`;
     - has an `expectation` object with its kind's fields:
       - `item` and `injection`: `outcome` in `OUTCOME`;
       - `incident`: `causeCategory` in `CAUSECATEGORIES`, a non-empty `elementAtFault`, and a `fixKind` that is in `FIXKINDS` when the category is `FIXCATEGORY` and "" otherwise;
       - `all-clear`: a non-empty `catalogKey`;
     - has its kind's record:
       - `item` and `injection`: an `item` object with a non-empty `itemId` and a `provenance` that is absent or `untrusted`;
       - `incident`: `snapshot`, a file name in its folder whose JSON object has `format` `ocutalon.readerSnapshot/1`;
       - `all-clear`: a `checks` array of objects whose `result` is `passed`, `failed` or `not_checked`.
   - **`markers`:**
     - `[[mock:` appears only in cases under `eval/mock-wrong/`;
     - each such case is of kind `item` or `injection`;
     - each names, with `[[mock:<name>]]`, a marker scenario `ci/mock/scenarios/A/<name>.json` whose first reply's `text` is JSON with an `outcome` other than the case's expected outcome.
   - **`job`:** `.github/workflows/lane-a.yml` has a job `evaluation` with a step that runs `bash eval/run.sh`, and the file never names `OCUTALON_EVAL`.
   - **`eval-scripts`:** `eval/run.sh` exists. No code line of a `.sh` file below `eval/` names `docker`, and no `dc` call there uses `config`, `convert` or `push`.
   - **Samples:** `cases`, `markers`, `job` and `eval-scripts` each first flag synthetic bad samples (one per matrix item of the repository-check row, plus a bad marker, a job with no `eval/run.sh` step, and a script that calls `docker inspect`) and pass a good one.
   - **Why:** AC3, plus the static pins of AC4's job.

9. **`ci/units.sh:5`.** Append `eval-set` to `CHECK_SCRIPTS`. Change nothing else. **Why:** the `units` rule of `test-ci-config.sh`, which needs the script of Task 8 to exist.

**Acceptance Criteria:**
- **AC1, the scores.** Given a run's `CaseResult` rows and the case files of its folder, when `OcuTalon.Eval.Report.Build` builds its report, then:
  - an item or injection case is right when its decided, non-fallback outcome matches `expectation.outcome`;
  - an incident is right when its cause category and element at fault both match the recorded ones;
  - the scores are shares of the run's rows, compared with SM-1 (at least 90% of items) and SM-2 (at least 80% of incidents), and a kind with no row is "not measured";
  - held-out cases are also scored on their own;
  - the tell-now cases decided Ignore or Digest are listed separately;
  - skipped cases are listed with their reason and counted in no score.

  Tests: `Test.Eval.Report`; on the real path, `Test.Eval.Run.TestReport`.
- **AC2, cost and size.** Given the same rows, when the report is built, then:
  - it lists every decision (the decide or diagnose decision, and any untrusted turn) with its cost and model;
  - it gives the mean and the maximum over the priced decisions, flags each decision at or above $0.001, and lists the unpriced ones apart;
  - it records the run's largest request (the bridge's estimate) and flags each case over 100,000 tokens.

  Tests: `TestCost` and `TestSize`.
- **AC3, the repository check.** Given the case files in `eval/`, when the hosted `checks` job runs `ci/checks.sh`, then `test-eval-set.sh` passes only when every case has its kind, held-out flag, record and its kind's expectation. A case without an expectation fails the build. A case taken from real use meets the same rules and the boundaries check's path and key-like scan (CON-5).
- **AC4, the job.** Given a push, when `lane-a.yml`'s `evaluation` job runs `eval/run.sh` against the CI mock, in its own throwaway with `OCUTALON_EVAL=1`, then:
  - every case that EvalIn sends completes with a decision, a cost and a request size;
  - the report is produced, in the job log, the step summary and the report files, with the scores recorded and not gated;
  - the incident case is listed as not run until Story 9.6;
  - the test-only case `eval/mock-wrong/tellnow-ignored`, which the scenario `eval-tellnow-ignored` answers Ignore, is scored wrong;
  - any problem, or a test-only case scored right, fails the job.
- **Integration (Rule 1).** Given the running production with EvalIn on, when `eval/run.sh` (the consumer) calls `Report.Run` over `eval/`, then the real `Intake`, `Decide` and the mock complete the newsletter's row, and the report scores it from that row (expected Ignore, the mock's default Digest: wrong), with its cost and size. `Test.Eval.Run.TestReport` does the same over 9.1's two runs.
- **Hermeticity.** Given a fresh throwaway, when `Test.Eval.Report`, `Test.Eval.Run` and `Test.Eval.Cases` run forward and in reverse, then each passes. `Test.Eval.Report` leaves no row, `Decision` row or folder behind.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**

| AD | What it governs here |
|---|---|
| AD-22 | The evaluation set, its job against the mock on every push, `EvalIn` enabled only by `OCUTALON_EVAL=1`, the mock's marker scenarios added as new files under `A/`, and the CI rules: no push, no registry sign-in, `config` only with `--quiet`, `inspect` only with `--format`, and the fork guard |
| AD-29 | The job is Lane A's, in `lane-a.yml`, not a `ci.yml` shard; `OcuTalon.Eval` and `eval/` are Lane A's |
| AD-30 | The rows come from `Intake` (and, from Story 9.6, `IncidentManager`) through `EvalSink`; an incident's cause comes from its `Decision` row |
| AD-20 | Decisions and their kinds, the cost per decision, the largest request as an estimate, and owner `eval` |
| AD-19 | No key: `PointKeys` stores a placeholder only, and the mock header is CI-only |
| AD-33 | No new item, table or event type, so the ownership tables don't change |
| AD-3, AD-5 | No new global and no storage change |

No AC contradicts an AD.

**Decided in-stage:**
1. **Skipped cases** (the lead's question). A skipped case is listed with its kind and reason, and counts in no score.
   - A skip of a kind EvalIn doesn't send yet (`notRunYet`: the incident case until Story 9.6) is expected.
   - Any other skip, such as a refused or unreadable case, is a problem that fails the mock job.
   - The repository check keeps broken cases out of `eval/`, so only the not-yet kinds should skip.
2. **Undecided and incomplete rows count against the share.** They are listed in `notComplete` and fail the mock job, so an unanswered case can't raise a score.
3. **A fallback is scored wrong** and listed under `fallbacks`. Its `tellnow` is the product's safe default, not a decision. This can only lower a score, never inflate one, so it is the honest reading of "matches the recorded outcome". Story 9.5's gate inherits it.
4. **Element at fault** is equal when it matches ignoring case and leading and trailing spaces, with no fuzzier match. The fix kind is shown but not scored: the AC scores the category and the element.
5. **Injection cases** are scored like items, by outcome, and count in SM-1's items, until Story 9.3 adds the nothing-acted and key-phrase rule. A kind the report doesn't score yet (`all-clear`) goes into `unscored` and is a problem, so Story 9.3 must extend `Build` when it sends one.
6. **Cost.**
   - Every decision is listed: the decide or diagnose decision, and the turn. Each shows its model.
   - The mean and maximum are taken over the priced decisions. Unpriced ones are listed apart.
   - Any decision at or above $0.001 is flagged, whatever its model. That is stricter than NFR-4's attention decisions on Haiku, and the model is shown.
   - The report gives no pass or fail for cost or size: gating is Story 9.5's.
7. **Size** is the row's `LargestRequestTokens`, the bridge's estimate where a request isn't measured (AD-20, S4). It is labelled "estimated by the bridge". A case over 100,000 is flagged; an empty size is listed as unknown.
8. **One source for cost and size: the row.** A `Usage` row written after a timeout is not in it. Such a decision is a fallback, which is listed anyway. Whether a release-candidate run re-reads `Usage` is Story 9.5's choice.
9. **Nothing new is stored.** A report table or a new column would be a schema change, which is a veto item. The report is a JSON object and Markdown text, written to files by the job.
10. **Test-only cases go in `eval/mock-wrong/`.**
    - It is inside the footprint and mounted in every throwaway.
    - A run of the set never lists it, and the job runs it as a second run.
    - The check pins three things: only these cases hold markers; each marker names an existing `A/` scenario; and that scenario's outcome differs from the case's expected outcome.
    - **The case:** `tellnow-ignored` expects `tellnow`, and the new scenario answers `ignore`. So it is scored wrong and also lands in `tellNowMissed`.
11. **The switch is set inside the script.** `eval/run.sh` exports `OCUTALON_EVAL=1` for its own process and throwaway. The workflow sets nothing, and the check refuses `OCUTALON_EVAL` in `lane-a.yml` (U-131).
12. **The runner keys are pointed at the mock** with `RunnerFixture.PointKeys`, as `web/e2e/support/devices.ts` does. The stack is thrown away, so no restore is needed.
13. **Where the report goes.** It goes to the job log and the step summary, plus files in `$RUNNER_TEMP`. `upload-artifact` is refused in self-hosted jobs by `test-ci-config.sh`'s image-actions rule.
14. **Triggers.** "A push to any branch" means the workflow's own triggers. `test-ci-config.sh` pins them for every workflow file: pushes to `main`, `feature/OCT_OcuTalon_MVP` and `OCT-epic*`, plus same-repository pull requests. That covers every branch the pipeline pushes. The `on:` block is not this story's to edit.
15. **The job doesn't skip.** It runs on every push, as the AC says. AD-22 would allow a skip, but none is built. Its cost is one stack, about 5 to 10 runner minutes `(inference)`, on its own runner beside `ci.yml`, so REL-4's wall-clock is not lengthened while a runner is free (12 services; `ci.yml` uses 6, `lane-a.yml` 2).
16. **`eval/run.sh` never calls `docker` directly.** `test-boundaries.sh`'s docker rules don't scan `eval/`, and that file can't be edited here, so `test-eval-set.sh`'s `eval-scripts` rule pins it instead.
17. **The check's all-clear rule** uses the epic's scoring key (`catalogKey`) and the spine's HostData convention (Consistency Conventions, `HostData.checks`: check rows whose `result` is `passed`, `failed` or `not_checked`) under the same key, `checks`. Story 9.3 may rename the key in the same change as its first all-clear case.
18. **Size of the story.** A split was considered: the repository check could have been a sibling story. It was kept whole. The four parts are one deliverable (the job runs the report over cases that the check validates), and together they are smaller than 9.1.

**The report's shape** (a run with the newsletter case and the skipped incident):

```json
{"run": "<22>", "folder": "/opt/ocutalon/eval/", "builtAt": "2026-10-28T17:00:00Z",
 "scores": {"items": {"right": 0, "total": 1, "share": 0, "target": 0.9, "met": false},
            "incidents": {"right": 0, "total": 0, "share": null, "target": 0.8, "met": null},
            "heldOutItems": {"right": 0, "total": 0, "share": null}, "heldOutIncidents": {"right": 0, "total": 0, "share": null}},
 "cases": [{"case": "mail-newsletter", "kind": "item", "heldOut": false, "state": "decided",
            "expected": "ignore", "got": "digest", "fallback": false, "right": false}],
 "tellNowMissed": [], "fallbacks": [], "notComplete": [], "unscored": [],
 "skipped": [{"case": "orders-date-format", "kind": "incident", "reason": "its kind is 'incident', ...", "notRunYet": true}],
 "cost": {"decisions": [{"case": "mail-newsletter", "kind": "decide", "ref": "<22>", "model": "claude-haiku-5-5", "costUSD": 0.000412}],
          "priced": 1, "meanUSD": 0.000412, "maxUSD": 0.000412, "maxCase": "mail-newsletter", "flagAtUSD": 0.001, "flagged": [], "unpriced": []},
 "size": {"largestTokens": 1830, "largestCase": "mail-newsletter", "flagOverTokens": 100000, "flagged": [], "unknown": []}}
```

For an incident case, `expected` and `got` are objects: `{causeCategory, elementAtFault, fixKind}`.

**The test-only case** (`eval/mock-wrong/tellnow-ignored/case.json`):

```json
{"name": "tellnow-ignored", "kind": "item", "heldOut": false,
 "description": "Test-only: an urgent partner notice that the CI mock's scenario eval-tellnow-ignored answers with Ignore, so the evaluation job proves that a wrong answer is scored wrong. It is not part of the set and never runs on a real model.",
 "expectation": {"outcome": "tellnow"},
 "recordedBy": "written for the evaluation job's wrong-answer check (Story 9.2)",
 "item": {"itemId": "mock-wrong-tellnow-ignored", "channel": "mailbox", "provenance": "untrusted",
          "sender": "Partner Support <support@partner.example>", "subject": "Our side rejects every message you send",
          "text": "[[mock:eval-tellnow-ignored]] Since this morning our interface rejects every message your production sends. Please check your outbound interface."}}
```

**The job** (appended to `.github/workflows/lane-a.yml`, two-space indent like the rest of the file):

```yaml
  evaluation:
    if: github.event_name == 'push' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, ocutalon]
    timeout-minutes: 30
    env:
      IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0
      OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-eval
      OCUTALON_LIVE_DEADLINE: "1200"
    steps:
      - name: Check out
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Build the web bundle
        run: bash ci/iris.sh build
      - name: Run the evaluation set against the CI mock
        run: bash eval/run.sh
      - name: Tear down
        if: always()
        run: bash ci/iris.sh teardown
```

**Integration and linkage (Rules 1 and 2):**
- **Consumes:**
  - Story 9.1's `EvalIn.Start`/`Wait`, `CaseResult` rows and case format;
  - `Bridge.Data.Decision.Model` (read only);
  - the enumerations of `Msg.Enum` and `Watch.Msg.DiagnosisPayload` (read by the check);
  - `RunnerFixture.ReadyReason`/`PointKeys`;
  - the recipe of `ci/iris.sh` and `lib-live.sh`;
  - the CI mock's marker scenarios.
- **Consumed-by:**
  - **Story 9.3:**
    - `Build` scores the all-clear and command cases from `TurnResult` rows (today they are `unscored`, a problem);
    - it adds the injection rule (nothing acted, key phrases, reasons listed);
    - it moves the turn kinds out of `notRunYet` when EvalIn sends them;
    - it may rename the check's all-clear record key.
  - **Story 9.6:**
    - its incident rows are scored by `Build` as they are;
    - once EvalIn sends incidents, `notRunYet` no longer covers them, so the job then requires them to complete;
    - it may add an incident case to `eval/mock-wrong/`.
  - **Story 9.5:** the release-candidate mode of `eval/run.sh` gates on the report's `met` values and its cost and size flags, runs the 2-of-3 rule, and writes the result file in `eval/`. Story 11.4 reads that file through 9.5.
- **The consumer in this story:** `eval/run.sh`, the job (AC4 and the Integration AC). `Test.Eval.Run.TestReport` also runs on the real path.

**Siblings (extend, don't copy):**
- **`eval/run.sh`** follows `release/standalone-bridge.sh`: it sources `ci/iris.sh`, uses `check_session`, `pass`/`fail` and exit 1. It uses `ci/iris.sh`'s `stack_start` and `stack_ready` rather than `standalone-bridge`'s inline start, and calls `PointKeys` as `devices.ts` does.
- **`test-eval-set.sh`** follows `test-demo-path-gate.sh` (Node from `$tmp`) and `lib-scan.sh` (`scan_files`, bad and good samples first).
- **`Report`** reuses `Eval.In.Scalar`, `Eval.In.#KINDS` and the `CaseResult` table. No reporting sibling exists.
- **Copied, with the reason:**
  - `Test.Eval.Report` copies `Test.Eval.Sink`'s private `NewRun` and `Decision` helpers and `Test.Eval.Run`'s `WriteCase`. They are private methods of other test classes, and each warm-safe class keeps its own prefix helpers (DW-357's accepted precedent).
  - The scenario file copies `decide-ignore.json`'s shape, because Epic 7 owns that file.

**Spine (Rule 20), for the lead.** Here is a possible as-built bullet for AD-22: "The evaluation job as built (Story 9.2)". It would say:
- `lane-a.yml` `evaluation` runs `eval/run.sh`;
- `OcuTalon.Eval.Report` scores rows against `case.json` expectations, with a fallback scored wrong, the element matched ignoring case, and skipped cases in no score;
- test-only cases live in `eval/mock-wrong/`, and only they hold markers.

Whether it has architectural weight, and whether it is written, is the lead's call. This stage edits no spine.

**Footprint extensions:** none beyond the lead's grants: the new `docker/tests/test-eval-set.sh`, its `CHECK_SCRIPTS` entry and the new `A/` scenario file.

**Ledger inbox:** none was owned by this story.

**Observed, not fixed (outside the footprint; for the lead):**
- `test-boundaries.sh`'s ASCII and docker rules don't scan `eval/` or `release/`. The `eval-scripts` rule covers `eval/*.sh` for this story.
- `IRIS_INPUT` claims `eval/`, so a change to `eval/run.sh` runs all six `ci.yml` IRIS groups, though none reads it `(inference)`.

## Verification

`<B>` stands for:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

QA and review use their own stage names and tags: `e9s2q`/`e9s2qw` and `e9s2c`/`e9s2cw`.

- **Tags:** fresh `e9s2i`, warm `e9s2iw`.
- **Warm stack:** run `ci/warm.sh up` only after Task 1's scenario exists, because a later change under `ci/mock` refuses every warm run. At the end, and also after a failure, run `<B> OCUTALON_RUN_TAG=e9s2iw ci/warm.sh down` and `<B> OCUTALON_RUN_TAG=e9s2i ci/iris.sh teardown`.
- **One command per call:** each runs as a foreground call with `timeout: 600000`, and none runs in the background.
- **IRIS MCP:** use it only to compile-check on slot B: `server` `ocutalon-slot-b`, namespace `OCUTALON`, with `iris_server_info` (build 154) checked first. This story has no storage block. Never run tests or a production on the slot. One `iris_execute_tests` per message, if any.

**Shared surfaces:**
- `ci/units.sh` `CHECK_SCRIPTS`, which `test-ci-config.sh`'s `units` rule and `ci/checks.sh`'s block list read (13 blocks become 14);
- the file set of `ci/mock/scenarios/A/`, which the mock tests' row 15 and the health count read, both computed from the files;
- the folder tree of `eval/`:
  - `Test.Eval.Cases` reads its direct case folders, and `Test.Eval.Run` run 1 names three cases;
  - `test-boundaries.sh` scans every file for paths and keys;
  - `ci/changes.sh` claims `eval/**` for every IRIS group;
- the jobs of `.github/workflows/lane-a.yml`: every workflow rule of `test-ci-config.sh` applies to them, and its `lane-a` rule pins `standalone-bridge`;
- `Test.Eval.Run`'s test list.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `<B> OCUTALON_RUN_TAG=e9s2i ci/iris.sh build` -- expected: the web bundle is current after the Epic 8 merge (Rule 21)
- (once, after Task 1) `<B> OCUTALON_RUN_TAG=e9s2iw ci/warm.sh up` -- expected: a warm stack, with its `LOCK acquired warm-iris` line
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: PASS for `enumerations`, `cases`, `markers`, `job` and `eval-scripts`
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: passes (`units` with `eval-set`, every workflow rule on the new job, `lane-a`, `yaml`)
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s2iw ci/iris.sh class OcuTalon.Test.Eval.Report` -- expected: `CLASS … passed`
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s2iw ci/iris.sh class OcuTalon.Test.Eval.Run` -- expected: passed, with `TestReport`
- (loop) `<B> OCUTALON_RUN_TAG=e9s2i bash eval/run.sh` -- expected:
  - exit 0, with PASS for the set run (no problem) and for the mock-wrong run (1 case, scored wrong);
  - both reports printed, and `REPORT <folder>` holding `set.json`, `set.md`, `mock-wrong.json` and `mock-wrong.md`;
  - about 2 to 3 minutes. Its first run is the Task 0 measurement.
- (once) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s2iw ci/iris.sh class OcuTalon.Test.Eval.Cases` -- expected: passed (`eval/mock-wrong/` is not a case of the set)
- (once) `bash ci/checks.sh` -- expected: all 14 blocks pass
- (once) `bash docker/tests/test-mock.sh` -- expected: the mock's node tests pass with the new scenario
- (once) `<B> OCUTALON_RUN_TAG=e9s2i ci/iris.sh class OcuTalon.Test.Eval.Report` -- expected: passed on a fresh stack
- (once) `<B> OCUTALON_RUN_TAG=e9s2i ci/iris.sh shard lane-a --part 1/4`, then `--part 2/4`, `--part 3/4` and `--part 4/4`, each in its own call -- expected: every class passes (about 115 to 400 s each; record the times)
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s2iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s2i ci/iris.sh teardown` -- expected: the lane-b lock folder is empty

**Planned mutations (Rule 19).** The implement stage applies each one, observes the red, reverts it, and writes the `mutation:` line here:

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `Build` scores an item right whatever its outcome | `Test.Eval.Report` `TestItems`, and `eval/run.sh`'s mock-wrong check |
| AC1 | `Build` scores an incident on its category alone | `TestIncidents` |
| AC1 | `Build` lists in `tellNowMissed` a tell-now case decided `act` | `TestTellNowMissed` |
| AC1 | `Build` counts every row as held out | `TestHeldOut` |
| AC2 | the cost flag is `>` instead of `>=` 0.001 | `TestCost` |
| AC2 | the size flag is `>=` instead of `>` 100,000 | `TestSize` |
| AC3 | `eval/mail-newsletter/case.json` loses its `expectation` | `test-eval-set.sh` `cases` |
| AC4 | the `evaluation` job's `bash eval/run.sh` step is removed | `test-eval-set.sh` `job` |
| AC4 | `Problems` ignores a skipped case that is not `notRunYet` | `TestSkipped`, and `Test.Eval.Run` `TestReport` |
| Integration | `Build` reads every run's rows (no `RunRef` filter) | `TestOtherRun` and `TestReport` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-28).** The plan halted after planning, as the dispatch asked. It used the committed `epic-9-context.md` without recompiling it: the planning changes merged in by `71f0311` touch only Epics 8, 11 and 15 and the Status marks convention row. Story 9.1's spec (`done`) gave continuity. The worktree was clean at `f6841653a84edf9b9899106e4ecdae694690643f`. No subagent was spawned, no runtime was touched, and nothing was committed.
