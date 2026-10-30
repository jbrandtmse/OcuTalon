---
title: 'Story 9.5: Release candidates pass the evaluation and the demo incident gate'
type: 'feature'
created: '2026-10-30'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The evaluation set runs only against the CI mock, where its scores are low by design. Nothing yet measures a release candidate on Claude Haiku 5.5, runs the demo incident 10 times, applies REL-5's two-of-three rule, or writes the result file that Story 11.4's release-notes generator reads. So a release could ship below SM-1, SM-2, NFR-3 or NFR-4, or with a demo incident that is diagnosed wrong.

**Approach:**
- A new Lane A class, `OcuTalon.Eval.Gate`, holds the gate:
  - the 10-run demo-incident gate over 9.6's `IncidentManager` path, where each run is checked against the case's expectation and the fix kind's own validation (`Fix.Kind.Check`);
  - one attempt's targets;
  - REL-5's verdict;
  - the result document.
- `Eval.Report` gains the two fields the gate reads: an incident's fix parameters, and each decision's duration.
- `eval/run.sh` gains three modes:
  - `--release-candidate`: a throwaway built from the checkout, with the real key taken from the shell through a committed compose override. Each attempt runs the set and the demo gate, up to three attempts in all, and the run writes `eval/release-candidate.json` and `.md`.
  - `--release-candidate --on-mock`: the same sequence on the CI mock, with no key and no spend.
  - `--override "<reason>"`: records the author's override in a blocked result file.
- The push-time run adds the demo gate on the mock and prints the attempt's targets. It never fails on a target.

## Boundaries & Constraints

**Always:**
- **One attempt meets every target (REL-5) only when all of these hold:**
  - SM-1: the set's `scores.items.met` is true.
  - SM-2: the set's `scores.incidents.met` is true, **and** the demo gate passes, 10 of 10.
  - NFR-3: no request over 100,000 tokens, and none of unknown size, in the set or in any demo run.
  - NFR-4: every attention decision of the set is priced and costs under $0.001. Attention decisions are Decision `Kind` `decide`, held in `Gate.NFR4KINDS`.
  - Model: every decision of the set and of the demo runs has `Model` `claude-haiku-5-5`.
  - No problem: `Report.Problems` is empty for the set and for every demo run. A run that acted is a problem.
- **Reported, never targets:** the injection, all-clear, command and stop-watching scores; diagnose and turn costs; diagnosis times.
- **A demo run passes only when all of these hold:**
  - its report has a decided `Report.DEMOCASE` entry with no fallback;
  - the entry is `right`: cause category and element at fault match;
  - its fix kind equals `expectation.fixKind` (`repair_resend`);
  - `##class(OcuTalon.Fix.Kind).Check(fixKind, fixParameters, fields)` is OK, where `fields` are the keys of `EvidencePack.FromInput(EvidencePack.Input(pack)).sample.body` for the pack built from the demo snapshot. These are the fields Decide's reply check gets.
  - its report has no problem.
- **The diagnosis time** is the diagnose Decision's `DurationMs`. It is recorded, never a pass condition.
- **The verdict (REL-5):**
  - If attempt 1 meets every target, the verdict is `pass` after one attempt.
  - Otherwise exactly attempts 2 and 3 run. The verdict is `pass` when at least 2 of the 3 attempts meet every target, else `blocked`.
  - Gate never writes `overridden`. Only `--override` does, and only on a blocked result file.
- **The key (AD-19):**
  - `--release-candidate` refuses to run (exit 2) before any container call unless `ANTHROPIC_API_KEY` is non-empty in its own environment. The message names the variable, never a value.
  - The key reaches only the throwaway's `iris` environment, by compose interpolation of the shell variable in `eval/compose.release-candidate.yml`.
  - It is never written to a file, printed, put in an IRIS session's script or stored in IRIS. The Provider step's `@{env:ANTHROPIC_API_KEY}` placeholder resolves only inside AI Hub.
- **EvalIn** is enabled only by `run.sh`'s own `export OCUTALON_EVAL=1`, inside its own throwaway (U-131). Every mode builds the image from the checkout, and its exit trap removes its stack, images and lock.
- **Where results go:**
  - Only a finished `--release-candidate` run without `--on-mock` writes into `eval/`, with a verdict of `pass` or `blocked`.
  - `--on-mock` writes `release-candidate-on-mock.json` and `.md` into the report folder only, with `onMock` true.
  - No result file holds a local path, key-like text or the report folder's path.
- **The push run** (no argument) keeps runs 1 and 2 and their checks unchanged. Run 3's checks are structural, because on the CI mock the diagnosis is a fixed scenario that answers the demo right. The attempt's targets are printed as INFO only.

**Never:**
- No new workflow, job, trigger or secret: `.github/workflows/lane-a.yml` is unchanged. The push run never fails on a target or a score.
- Without `--on-mock`, `--release-candidate` never calls `PointKeys`, `RestoreKeys` or `ReadyReason`. Neither form ever runs `eval/mock-wrong/`.
- In `eval/*.sh`:
  - no `dc config`, `convert` or `push`;
  - no code line that names the container tool;
  - no `set -x`;
  - never reads `.env`.
- No dry run, approval, `Execute` or notice. The gate only validates the parameters (AD-16).
- **No edits to these:**
  - 9.6's `IncidentManager` path;
  - `Decide`, the Provider step, `lib-live.sh`, `ci/compose.ci.yml` and the mock;
  - `Production.cls`, `ci/units.sh`, `release/**`, `docs/**` and the spine.
- No thinking-history smoke test (Story 30.1). The result file says `"thinkingHistorySmoke": "not run"`.
- No persistent class, storage change or `short-names.tsv` row.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| RC, attempt 1 meets every target | `--release-candidate`, key set | One attempt. Verdict `pass`. Writes `eval/release-candidate.json` and `.md`. Exit 0 | No error expected |
| RC, attempt 1 below a target | Any target not met | Attempts 2 and 3 run. `pass` (exit 0) at 2 of 3 met, else `blocked` (exit 3). The result file is written either way | No error expected |
| RC without a key | `ANTHROPIC_API_KEY` unset or empty | A `FAIL` line that names the variable. Nothing starts | Exit 2, before any container call |
| RC readiness | Stack up with the override | Every item runs, and `RunnerFixture.WaitRecords()` returns. `Bridge.Keys.Status` is 1 for TriageAgent, DiagnosisAgent and ChatAgent. In the IRIS process, `OCUTALON_MODEL_BASE_URL` is empty and `OCUTALON_MOCK_KEY_HEADER` is not 1. `AgentRunner.ResolveModel` gives `claude-haiku-5-5` for all three | Otherwise `die`: no result file, exit 1 |
| RC structural failure | A session prints nothing, a run does not start or finish, a file is not saved, or the verdict is `incomplete` | Nothing is written in `eval/` | Exit 1 |
| Demo run passes | Decided, no fallback, `data_format_change`/`OrderDate`, `repair_resend`, and `Check` OK | `pass` true, with `durationMs`, `model`, `costUSD` and `tokens` | No error expected |
| Demo run fails | Any of: wrong cause or element; another or empty fix kind; `Check` refuses (a field not in the sample, an unregistered format or one format twice); a fallback; no decided entry; a problem in the run's report; `Report.Run` refused or threw | `pass` false, with the first failing reason. The gate passes only at 10 of 10 | `DemoRun` and `Demo` never throw |
| Diagnosis time | `DurationMs` over 20,000, or none | Listed in `timing.overShare` or `timing.unknown`. Mean and maximum are taken over the known times | Not a failure |
| NFR-4 | A `decide` decision at or above 0.001, or unpriced | NFR-4 not met. Diagnose and turn costs at or above 0.001 are listed only | No error expected |
| NFR-3 | A set or demo request over 100,000 tokens, or of unknown size | NFR-3 not met. Exactly 100,000 is met | No error expected |
| Model | Any decision whose `Model` is not `claude-haiku-5-5` | The model target is not met | No error expected |
| Override | `--override "<reason>"`, and `eval/release-candidate.json` has verdict `blocked` and override null | The JSON gets verdict `overridden` and `override {reason, at}`. The `.md` line `Verdict: blocked` becomes `Verdict: overridden (blocked; the author overrode it)`, and `## Override` is appended. Exit 0 | No container call |
| Override refused | No result file; no `.md` beside it, or a `.md` without its `Verdict: blocked` line; a verdict of `pass` or `overridden`; a reason that is blank, multi-line, not printable ASCII or over 500 characters | A `FAIL` line. Both files are unchanged | Exit 2 |
| On-mock rehearsal | `--release-candidate --on-mock`, no key needed | The whole sequence on the CI mock, after `PointKeys` as the push run does. Three attempts run, since the mock is below SM-1 and SM-2 by design, and the verdict is `blocked`. Writes `release-candidate-on-mock.*` into the report folder, with `onMock` true. `eval/` is untouched | Exit 0 when every check passes |
| Push run | `bash eval/run.sh` | Runs 1 and 2 as today. Run 3 runs the demo gate: 10 runs, each passed with a time. The attempt's targets are printed as INFO | Exit 1 only on a structural check |
| Bad argument | Anything but none, `--release-candidate`, `--release-candidate --on-mock` or `--override <reason>` | A usage line | Exit 2, before any container call |

</intent-contract>

## Code Map

All class paths are under `src/ocutalon/cls/OcuTalon/` unless they say otherwise.

**Evaluation (extend)**
- `Eval/Report.cls`:
  - **The SELECT** at :166 and the row object at :169: add `FixParameters`.
  - **The incident branch** of `Score` at :387-397 builds `expected` and `got`; the entry is built at :402-409. Add `fixParameters` here.
  - **`AddDecision`** at :333-347 already opens the Decision row at :335. Add `durationMs` here.
  - **`Save`** at :268-279 and the private `Write` at :1010. Extract the shared part into `WriteFiles`.
  - **Text helpers:** `ScoreLine` :887, `Percent` :983, `Money` :989 and `Cell` :995 are private, and Gate's text reuses them.
  - **`Problems`** :179-209 and `Run` :284-299 (Start, Wait, Build, Finish), used as they are.
  - **Constants:** `DEMOCASE` :86, `FLAGUSD` :95, `FLAGTOKENS` :98.
  - **Scoring rules:** `Same` :853; a share's `met` is null with no row (:806).
- `Eval/In.cls`:
  - `FOLDER` :47; `Start` :143.
  - `Wait` :170, which polls every 0.25 s.
  - `CaseNames` :202, which lists only subfolders that hold a `case.json`, so files at the root of `eval/` are never cases.
- `Eval/Msg/IncidentCase.cls` and 9.6's eval branch of `Watch/IncidentManager.cls` form the demo gate's path. They are read-only here.

**What the gate calls (read-only)**
- `Fix/Kind.cls` `Check` :78-82, which calls `Fix/Kind/RepairResend.cls` `CheckParameters` :35-60: the field must be in `fields`, and the two formats must be registered, of one family and different.
- `Watch/Msg/DiagnosisPayload.cls` `CheckFix` :90-106. It takes the fields from `EvidencePack.FromInput(ReplyCheck Input).sample.body`, and the gate mirrors this.
- `Watch/EvidencePack.cls`: `Build(source, .pack)` :84, `Input` :232, `FromInput` :240, `Load(file, .snapshot)` :287.
- `eval/orders-date-format/case.json`: `snapshot` is `snapshot.json`, and the expectation is `data_format_change`, `OrderDate`, `repair_resend`. In a stack this is `/opt/ocutalon/eval/orders-date-format/snapshot.json`, the same path as `Test/Eval/Incident.cls` `SNAPSHOT` :35.
- The mock's default `ci/mock/scenarios/A/diagnosis.json` answers `fixParameters {field: OrderDate, sourceFormat: MM/DD/YYYY, targetFormat: YYYY-MM-DD}`. These are known-valid fixture values.
- Bridge `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`:
  - `DurationMs` :57, `CostUSD` :60, `Model` :63.
  - `Model` is the runner's configured model, from `Adapter/Agent.cls` :587. Haiku 5.5 is priced at $0.1 and $0.5 per million tokens (`Installer.cls` :66-69).

**The script and its stack (read-only except `eval/`)**
- `eval/run.sh`:
  - the header :2-46 and the `OCUTALON_EVAL_WAIT` guard :52-63;
  - `. ci/iris.sh`, `setup_tag` and `export OCUTALON_EVAL=1` :65-67;
  - `report_dir` :69-74;
  - `eval_run` :83-108, which prints an early `CHK|started|` line because `iris_script` re-runs a session that printed no `CHK` line;
  - `chk_value` :111, `run_started` :116, `fetch` :130-137;
  - `stack_start`/`stack_ready` :139-141;
  - the mock readiness check with `PointKeys` :143-154;
  - run 1 :156-238, run 2 :240-268, the reports :270-281 and the exit :283-287.
- `ci/iris.sh`: `setup_tag` :54, `preflight` :96-123, `stack_start` :250-253 (preflight and then `live_start`), `stack_ready` :258-270 (`dc up -d --build --wait`).
- `docker/tests/lib-live.sh`:
  - the decoy env file :84 and `LIVE_FILES` :86, which always includes `ci/compose.ci.yml`;
  - `live_add_file` :152, the public hook, which `lib-online.sh` `online_override` :43-66 uses with `${VAR}` interpolation;
  - `dc` :244-248, `live_cleanup` :266-272, `die` :279;
  - `iris_script` :308-319, which retries up to 3 times when a session prints no `CHK` line;
  - `check_session` :480, which compares CHK lines exactly.
- `ci/compose.ci.yml`:
  - the iris environment :17-22: `OCUTALON_EVAL` pass-through, the mock base URL, and `OCUTALON_MOCK_KEY_HEADER "1"`;
  - `docker/tests/compose.throwaway.yml` resets `env_file` and mounts `./eval` read-only;
  - `docker-compose.yml` builds the image from the tree. No network is internal.
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:
  - `KEYPLACEHOLDER` `@{env:ANTHROPIC_API_KEY}` :32;
  - an empty `OCUTALON_MODEL_BASE_URL` means no override (:101, :124);
  - the mock header is added only when the value is exactly 1 (:104).
- `Test/Agent/RunnerFixture.cls`: `RunningReason` :86, `GuardReason` :100 (the mock only), `WaitAllRun` :117, `WaitRecords` :168, `ReadyReason` :306, `PointKeys` :456.
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls` `Status(item)` :32 (presence only). `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls` `ResolveModel(item)` :45.
- `.github/workflows/lane-a.yml` `evaluation` :44-63 (30-minute timeout, `bash eval/run.sh`) is unchanged.

**Checks and tests**
- `docker/tests/test-eval-set.sh`:
  - the header rules :9-79 and the files at the `eval/` root, which the cases rule skips (:177);
  - `check_eval_scripts` :1161-1170;
  - `check_run_guard` :1177-1213: a stub container tool that records its calls and fails;
  - `check_record_guard` :1219-1250: the copy-tree pattern;
  - `rule` :1255, which needs bad samples with an `expect.txt` and good samples, written by the Node `mksamples` program (`variant(...)` :782-1061);
  - the rule calls :1357-1366.
- `docker/tests/test-boundaries.sh` :33-40 scans every tracked file for local paths and key-like strings, so a committed result file is checked.
- `Test/Eval/Report.cls`:
  - the synthetic-row helpers `N` :1558, `NewRun` :1564 and `WriteCase` :1573;
  - `TestIncidents` :777, `TestCost` :870, `TestSave` :1122, `TestSaveRefusals` :1239.
- `Test/Eval/ZzIn.cls` :23 and :36: the private-seam override pattern, recorded under `^OcuTalonTest`.
- `ci/units.sh` :17 puts area `Eval` in `lane-a`, and `shards-2` runs `shard:lane-a@rest`. New `Test.Eval.*` TestCases are found by area.
- **PRD** (`_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md`):
  - attention decision :134; FR-62 :1114-1137; NFR-4 :1155; NFR-7 :1161-1165; REL-5 :1296-1300; SM-1 and SM-2 :1388-1389.
- **Spine:** AD-15's time budget, with the diagnosis under 12 s, at :449.

## Tasks & Acceptance

**Execution:**

**Product**
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls` -- extend. Rationale: AC2, AC4, Rule 2.
  - Select `FixParameters`. Give each incident case entry `fixParameters`: the parsed object, or null when it is empty or not JSON.
  - Give each cost entry, priced and unpriced, `durationMs`: the Decision row's `DurationMs`, or null.
  - Extract `ClassMethod WriteFiles(directory, name, json, text = "") As %Status`, which holds `Save`'s name and folder checks and its writes. It writes `<name>.json`, and `<name>.md` only when `text` is not empty. `Save` calls it.
  - Make `ScoreLine`, `Percent`, `Money` and `Cell` public.
  - Update the class doc. No other behaviour changes.
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls` (new) -- Lane A, not persistent; it names no `OcuTalon.Test` class and calls no model. Rationale: AC1-AC4.
  - **Parameters:** `RUNS = 10`, `MODEL = "claude-haiku-5-5"`, `NFR4KINDS = "decide"`, `SHAREMS = 20000`, `TYPICALNOTICES = 35`, `DIAGNOSISBUDGETS = 12`, `REQUIRED = 2`, `OF = 3`, `FORMAT = "ocutalon.evalResult/1"`, `SMOKE = "not run"`.
  - **The demo gate:**
    - `SampleFields(folder, .fields)`: the sample-body keys, as in Always, from the `DEMOCASE` `case.json`'s snapshot.
    - `DemoRun(report, fields, number)`: one run's result object `{run, runRef, decided, fallback, reason, causeCategory, elementAtFault, fixKind, fixParameters, causeRight, fixKindRight, parametersValid, validation, durationMs, model, costUSD, tokens, problems[], pass}`. It reads only the report.
    - `Demo(folder, seconds, .gate)`: `RUNS` calls of a private seam `RunOnce(folder, seconds, .report)`, which is `Report.Run(folder, Report.#DEMOCASE, seconds, .report)`. It returns `{case, runs, required, passed, pass, fields, results[], timing{shareMs, typicalNoticeS, diagnosisBudgetS, meanMs, maxMs, overShare[], unknown[]}, problems[]}`. It catches every error per run, and gives an error status only when `SampleFields` fails.
  - **The attempt:** `Attempt(set, demo, number)` gives `{attempt, met, below[], targets{sm1, sm2, demoGate, nfr3, nfr4, model, clean}, scores, cost{meanUSD, maxUSD, maxCase, priced}, size{largestTokens, largestCase}, demo}`.
    - Each target holds `{label, met}` and its figures.
    - `below` lists the labels of the targets not met.
    - `cost` is the set's, and `size` covers the set and the demo runs.
  - **The verdict and the result:**
    - `Verdict(attempts)` gives `{verdict, attemptsRun, attemptsMet, decidedBy}`, where `verdict` is `pass`, `blocked` or `incomplete` (no attempt, or attempt 1 not met with fewer than 3 attempts).
    - `Result(attempts, context)`, where `context` is `{commit, branch, treeClean, onMock}`, gives `{format, createdAt, commit, branch, treeClean, onMock, model, verdict, rule{required, of}, attemptsRun, attemptsMet, summary, attempts[], override: null, thinkingHistorySmoke}`.
    - `summary` is `{attempt, scores (all eight), cost, attentionCost{maxUSD, maxCase, flagged}, size, demoGate{runs, passed, pass}, diagnosisTime{meanMs, maxMs, overShare, shareMs, typicalNoticeS, diagnosisBudgetS}}`. It comes from the first attempt that met every target, else from attempt 1.
  - **The text and the save:**
    - `Text(result)` writes Markdown in this order:
      1. the title;
      2. the commit, branch, tree and model line, and for `onMock` the line `On the CI mock: a rehearsal of the sequence, not a release result.`;
      3. exactly one line `Verdict: <verdict>`;
      4. the REL-5 rule line;
      5. the summary scores, built with `Report.ScoreLine`;
      6. the cost and size lines;
      7. the demo-gate table of each attempt (run, cause category, element, fix kind, parameters valid, diagnosis seconds, pass);
      8. the timing line, against NFR-7's 20 s share and the typical notice of about 35 s, with AD-15's 12 s;
      9. the attempts table (one column per target);
      10. the problems;
      11. `Thinking-history smoke test: not run.`
    - `Save(result, directory, name)` calls `Report.WriteFiles`.
- `eval/compose.release-candidate.yml` (new) -- the override, whose only code lines are below. Rationale: AC1, AD-19.
  ```
  services:
    iris:
      environment:
        ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:?the release-candidate run needs ANTHROPIC_API_KEY in its environment}
        OCUTALON_MODEL_BASE_URL: ""
        OCUTALON_MOCK_KEY_HEADER: "0"
  ```
  The header comments say: it is layered last, by `eval/run.sh --release-candidate` only, and never by CI.
- `eval/run.sh` -- Rationale: AC1-AC5. Update the header to the new contract.
  - **The arguments, and in `--release-candidate` the key,** are checked before `. ci/iris.sh`, as the Matrix's Bad-argument and RC-without-a-key rows say. In `--release-candidate`, an unset `OCUTALON_EVAL_WAIT` defaults to 900; everywhere else the default stays 180, with the same 1-3600 guard.
  - **`--override <reason>`:**
    - It never sources `ci/iris.sh`.
    - It rewrites `$root/eval/release-candidate.json` with Node, and edits `.md` as the Override rows say. The `at` field is `date -u +%Y-%m-%dT%H:%M:%SZ`. The appended section is `\n## Override\n\n<reason>\n\nRecorded at <at>.\n`.
    - It exits 2 with `FAIL node is not installed` when Node is missing.
  - **`--release-candidate`:**
    1. Check the key, then `stack_start eval`, then `live_add_file "$root/eval/compose.release-candidate.yml"`, then `stack_ready`.
    2. Run the readiness `check_session` of the Matrix row.
    3. Run attempt k = 1, and then 2 and 3 when attempt 1's `CHK|met|` is not 1. Each attempt is:
       - `eval_run set-k /opt/ocutalon/eval/ "<title>"`, requiring `CHK|run|1` and `CHK|saved|1`;
       - `demo_run demo-k`: one session that prints `CHK|started|1`, calls `Gate.Demo` with the wait, prints `CHK|demogate|<passed>|<runs>|<pass>` and one `CHK|demo|<n>|<pass>|<cause>/<element>/<fixKind>|<fallback>|<valid>|<durationMs>|<reason>` per run (pipes and line breaks translated), and saves `demo-k.json` through `Report.WriteFiles`;
       - `attempt_run k`: one session that reads `set-k.json` and `demo-k.json` with `%FromJSONFile`, calls `Gate.Attempt`, prints `CHK|met|`, `CHK|below|` and one `CHK|target|<label>|<met>` per target, and saves `attempt-k.json`.
    4. Run `verdict_run`: it reads every `attempt-k.json`, calls `Gate.Result` with:
       - `commit`, from `git rev-parse HEAD`;
       - `branch`, from `--abbrev-ref`, kept only when it matches `[A-Za-z0-9._/-]+`, else `unknown`;
       - `treeClean`, from `git status --porcelain` excluding the two result files;
       - `onMock` 0.

       It saves `release-candidate` and prints `CHK|verdict|`.
    5. Copy every file out into the report folder, then copy the result pair to `$root/eval/release-candidate.{json,md}`.
    6. Print `VERDICT <verdict>` and `RESULT eval/release-candidate.json`.
    7. Exit 0 on `pass`, 3 on `blocked`, 1 on a structural failure or `incomplete`. A structural failure or `incomplete` writes nothing in `eval/`.
  - **`--release-candidate --on-mock`:** the same sequence, with three differences:
    - no key check, and no override file;
    - the push run's readiness, with `PointKeys`;
    - `onMock` 1, and the pair is saved as `release-candidate-on-mock` in the report folder only.

    It exits 0 when every check passes, whatever the verdict.
  - **The push run (no argument):** after run 2, add run 3:
    - `demo_run demo` must have `runs` 10 and `passed` 10, and every `CHK|demo|` line must have fallback 0, valid 1 and a non-empty `durationMs`. These are structural checks: the mock's diagnosis is fixed.
    - Then `attempt_run` prints `INFO attempt on the CI mock: met <0|1>; below: <labels>` and requires a `CHK|met|` line.
    - Copy `demo.json` and `attempt.json` out with the others.

**Tests**
- `src/ocutalon/cls/OcuTalon/Test/Eval/ZzGate.cls` (new) -- Extends `OcuTalon.Eval.Gate`. `RunOnce` answers the n-th report from `^OcuTalonTest("EvalGate",n)` (JSON), and an error status for `^OcuTalonTest("EvalGate","fail",n)`. It counts its calls. Rationale: the Demo loop without a production, the `ZzIn` pattern.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls` (new TestCase) -- warm-safe and in-memory: synthetic report objects of `Report.Build`'s shape, the real demo snapshot, and no production or rows. It kills `^OcuTalonTest("EvalGate")` before and after each test. Rationale: AC1-AC4 and the Matrix.
  - `TestSampleFields`: the fields hold `OrderDate`, and equal the keys of `FromInput(Input(Build(snapshot))).sample.body`.
  - `TestDemoRunPasses`, with the mock's parameters.
  - `TestDemoRunFails`: each failure row, one at a time.
  - `TestDemoLoop` (ZzGate): exactly 10 calls; 10 good runs pass; one bad or refused run gives 9 passed and `pass` false.
  - `TestDemoTiming`: the mean, the maximum, 20,001 ms in `overShare`, 20,000 not in it, and an empty value in `unknown`.
  - `TestTargets`: each target flipped alone, each on the edge (100,000 tokens; 0.000999 USD; a null `met` counts as not met).
  - `TestNFR4Kinds`: a diagnose or turn decision at 0.002 keeps NFR-4 met but is listed; an unpriced decide does not meet it.
  - `TestVerdict`: all eight cases: `[]`, `[met]`, `[not]`, `[not,met]`, `[not,met,met]`, `[not,not,met]`, `[not,met,not]` and `[not,not,not]`.
  - `TestResult`: every field, the summary's source attempt, and `override` null.
  - `TestText`: one `Verdict: ` line, the tables, and the on-mock line only with `onMock`.
  - `TestSave`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` -- Rationale: Integration, Rule 19.
  - `TestIncidents` asserts `fixParameters`, and `TestCost` asserts `durationMs`. Add `TestWriteFiles`: there is no `.md` when the text is empty, and the refusals are `Save`'s.
  - Add `TestGateReadsTheReport`: synthetic rows (a decided incident row whose `FixParameters` are the mock's, and a diagnose Decision with `DurationMs` and `Model`), then `Build`, then `Gate.DemoRun`, which passes with that `durationMs`. This pins the field names between the two classes.
  - Update every existing assertion on the old entry shape.
- `docker/tests/test-eval-set.sh` -- two new rules. Each follows the file's convention: bad and good synthetic samples with `expect.txt`, then the real tree. Rationale: AC1, AC3, AC4.
  - **`rc-guard`:**
    - With the stub container tool, the refusals of the Matrix's Bad-argument and RC-without-a-key rows end in exit 2 with no call.
    - `--release-candidate` with `ANTHROPIC_API_KEY=zz-not-a-key-<random>` and `--release-candidate --on-mock` are accepted: they call the stub and exit 1, and that value never appears in the output.
    - `eval/compose.release-candidate.yml`'s code lines are exactly the six lines above. Its bad samples include a missing base-URL line and a literal key value.
  - **`rc-override`:**
    - `eval/run.sh` runs from a copy tree with no `ci/` (the `check_record_guard` pattern), and every Override and Override-refused row of the Matrix holds.
    - When the real tree holds `eval/release-candidate.json`, it parses; `format` is `ocutalon.evalResult/1`, `onMock` is false, and `verdict` is `pass`, `blocked` or `overridden`; a non-blank `override.reason` is there exactly when the verdict is `overridden`; and `eval/release-candidate.md` exists.
  - Update the header.

**Acceptance Criteria:**
- **AC1.** Given a checkout of the candidate and `ANTHROPIC_API_KEY` in the author's environment (or a CI secret's), when `bash eval/run.sh --release-candidate` runs, then it:
  - refuses to start without the key (exit 2, no container call);
  - builds its throwaway from the checkout with `EvalIn` enabled, and passes the key only through the override's interpolation, with an empty base URL and mock header 0;
  - requires every runner's key present and model `claude-haiku-5-5`;
  - runs the whole set and writes each attempt's report (`set-k.json` and `.md`, with scores, mean and maximum decision cost and the largest request) and its targets against SM-1, SM-2, NFR-3, NFR-4 and the model.

  Evidence: the `rc-guard` rule, `Test.Eval.Gate` `TestTargets`, and the `--on-mock` run of the same sequence. The leg against the real endpoint is the author's first release-candidate run (Design Notes).
- **AC2.** Given an attempt, when its demo gate runs, then:
  - `Report.DEMOCASE` is diagnosed 10 times through 9.6's `IncidentManager` path;
  - each run passes only on the recorded cause category and element, `repair_resend`, and parameters that `Fix.Kind.Check` accepts against the snapshot's sample fields;
  - the gate passes only at 10 of 10;
  - each run's `DurationMs` is recorded, with the mean, the maximum and the runs over NFR-7's 20 s share, beside the typical-notice target of about 35 s.

  Evidence: `Test.Eval.Gate`, and run 3 of the push run.
- **AC3.** Given attempt 1 below any target, when the run goes on, then:
  - attempts 2 and 3 run, and the verdict is `pass` at 2 of 3 met, else `blocked` (exit 3);
  - `--override "<reason>"` turns a blocked result file into `overridden` with the reason, and refuses everything else.

  Evidence: `TestVerdict`, `rc-override`, and the `--on-mock` run, which ends with 3 attempts and `blocked`.
- **AC4.** Given a finished release-candidate run, when its results are kept, then:
  - `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md` hold the commit, branch, tree state, model, verdict, every attempt, the override and `thinkingHistorySmoke` `not run`;
  - they hold the summary the release notes use: the scores and the held-out scores, the mean and maximum decision cost, the largest request, the demo gate and its times;
  - an `--on-mock` pair lands only in the report folder.

  Evidence: `TestResult`, `TestText`, `rc-override`, and the `--on-mock` run, after which `git status --short eval/` is empty.
- **AC5.** Given a push, when Lane A's evaluation job runs `bash eval/run.sh` on the mock, then run 3 records the demo gate and the attempt's targets and fails only on structural checks, and the job's other checks are unchanged (`eval/run.sh: all checks passed`).
- **Integration (Rule 1).** Given the running production on the CI mock, when `eval/run.sh`'s push run (the consumer) calls `Gate.Demo` and `Gate.Attempt`, then:
  - 10 `CHK|demo|` lines show `repair_resend` with valid parameters and a diagnosis time;
  - `CHK|demogate|10|10|1` is printed;
  - the INFO line lists the targets the mock misses;
  - the run exits 0.

## Spec Change Log

- 2026-10-30, lead spec gate: Design Notes gained "Lead gate rulings" (U-166 veto for the key path, the result format and NFR-4's reading; the AD-22 as-built bullet goes to the orchestrator with DW-431; no real-key run in any stage). No intent change.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**

| AD | What it binds here |
|---|---|
| AD-22 | The evaluation set runs on the CI mock on every push and on Claude Haiku 5.5 for each release candidate. Only `OCUTALON_EVAL=1`, exported by the evaluation script, enables EvalIn. No `docker push`, and `docker compose config` only with `--quiet`. |
| AD-19 | The model key comes only from an environment variable, never from IRIS storage or output. The base-URL override applies only when it is not empty. The mock header is added only for exactly `1`. |
| AD-15 | 9.6's `IncidentManager` path is the one diagnosis path. The 10-run gate measures diagnosis against the spine's budget of under 12 s. |
| AD-16 | The kind validates the model's parameters (`Fix.Kind.Check`). There is no dry run or Execute. |
| AD-20 | The gate reads cost, `DurationMs` and `Model` from `Decision` rows. Owner `eval` counts toward no cap. The release-candidate thinking smoke arrives with Story 30.1. |
| AD-6 | All model use goes through the bridge: the gate calls no model. |
| AD-29, AD-33 | Every touched path is Epic 9's (Lane A). There is no new table, item, event or cross-area message. |

No AC contradicts an AD's Rule. AD-22's phrase "Lane A's evaluation job sets [OCUTALON_EVAL] ... for each release candidate" holds through the job's own script. The AC itself allows "the author's environment".

**Decided in-stage:**
1. **The gate has its own class, `Eval.Gate`.** It reads `Report.DEMOCASE` (9.4's note 8) and keeps `Report` a run-scoped scorer. `Report` gains only the two fields that Gate reads.
2. **REL-5's targets are SM-1, SM-2, NFR-3 and NFR-4** (PRD :1298), with two additions:
   - SM-2 includes "all 10 runs of the demo incident" (PRD :1389);
   - the epic's rule "fails any run with a problem or one that acted" adds `clean`, and the AC's "on `claude-haiku-5-5`" adds `model`.

   NFR-7's diagnosis time is "recorded against" its target, not gated, because REL-5 does not list it.
3. **NFR-4 covers Decision `Kind` `decide` only.** The PRD defines an attention decision as "OcuTalon's choice for one item" (:134), and NFR-4 is "every attention decision" (:1155). Diagnose and turn costs are listed and flagged. Changing this is one parameter, `NFR4KINDS`. This is also listed for the lead.
4. **Attempts 2 and 3 always both run** after a first attempt below target ("runs twice more"), on the same stack. Each attempt is its own run Ref.
5. **The summary comes from the first attempt that met every target**, else from attempt 1. Every attempt's full figures stay in `attempts[]`.
6. **The override is a separate step on the written file,** so a blocked candidate is never re-run, at real cost, just to add a reason. Only `blocked` can be overridden, once, and the `.md` keeps a record that the candidate was blocked.
7. **One fixed result path, `eval/release-candidate.{json,md}`.** The cases rule skips root files. Committing the pair on the RC branch is Story 11.5's sequence: `release/**` is contended and commits are the author's.
8. **The override is a committed file in `eval/`, not generated.** It can be reviewed and pinned by `rc-guard`. It holds no secret, and `CaseNames` ignores it.
9. **Exit codes:** 0 pass, 1 structural failure, 2 refusal, 3 blocked. The real mode's wait defaults to 900 s, an implementation detail.
10. **The push run gains the demo gate (run 3).** REL-5 has the harness check its plumbing on every push, so a break in the gate shows before release day.
11. **No hook for the thinking-history smoke test,** only the inert `thinkingHistorySmoke: "not run"`. Story 30.1 adds the step to `--release-candidate` and sets the value.

**Siblings (extend, don't copy):**
- `Gate.Save` calls `Report.WriteFiles`, which is extracted from `Report.Save`.
- `Gate.Text` reuses `Report.ScoreLine`, `Cell`, `Money` and `Percent`.
- `SampleFields` and `DemoRun`'s validation follow `DiagnosisPayload.CheckFix`'s chain and call `Fix.Kind.Check`.
- `ZzGate` follows `ZzIn`/`ZzIncident`.
- `demo_run`, `attempt_run` and `verdict_run` reuse `iris_script`, `chk_value`, `fetch` and `eval_run`'s early-CHK convention. Their script lines differ, so `eval_run` is not generalised.
- `rc-override` follows `check_record_guard`, and `rc-guard` extends `check_run_guard`'s stub.

**Integration and linkage (Rules 1 and 2).**
- **Consumes:**
  - `Report.Run`, `Build` and `Problems` (9.2 to 9.8);
  - 9.6's incident path and `IncidentCase`;
  - `EvidencePack` (5.4, 9.6);
  - `Fix.Kind.Check` (7.1);
  - `Decision` rows (1.3, 1.4);
  - `RunnerFixture`, `Keys.Status` and `AgentRunner.ResolveModel`;
  - `lib-live.sh` `live_add_file`.

  The Integration AC runs against the real production on the mock.
- **Consumed-by:**
  - Story 11.5 runs `bash eval/run.sh --release-candidate` in the release-candidate sequence and commits the pair.
  - Story 11.4's generator reads `summary.scores`, `summary.cost.meanUSD`/`maxUSD`, `summary.size.largestTokens` and `override.reason`.
  - Story 30.1 adds the smoke step and `thinkingHistorySmoke`.

**Real-key leg (owner-only, for the lead).** This story proves everything up to the provider endpoint: the guard and override wiring, statically and with a stub, and the full sequence on the CI mock. The real Haiku run, with its key and spend, is the author's, at release (Story 11.5). Its first run is also the first proof that a throwaway reaches the real endpoint with the key from the shell. This is an inference: compose interpolation prefers the shell over a root `.env`, and the run refuses an empty shell variable. No CI job or repository secret is planned. Any such job would be an owner item.

**Veto-window items, for the lead's classification:**
- **(Security posture)** The key's path: shell variable, then the compose interpolation in `eval/compose.release-candidate.yml`, then the throwaway's `iris` environment, then the Provider placeholder. It is never on disk or in output.
- **(Stored format)** The new result file `ocutalon.evalResult/1`, which Story 11.4 reads.
- **(Reading of a PRD guarantee)** Decided in-stage 3: NFR-4 over `decide` decisions.

**Ledger inbox:** none. **Footprint extensions:** none. Every edited path is in Epic 9's footprint: `Eval/**`, `Test/Eval/**`, `eval/**` and `docker/tests/test-eval-set.sh`. No contended path is touched.

**Proposed spine text (for the lead), optional; no change to a Rule, Binds or Prevents line.** Add an as-built bullet after AD-22's "The first evaluation case (Story 0.10)":
> **The release-candidate run (Story 9.5).** `bash eval/run.sh --release-candidate` builds its throwaway from the checkout, layers `eval/compose.release-candidate.yml` (the shell's `ANTHROPIC_API_KEY` by interpolation, no base-URL override, no mock header), and runs the set plus `OcuTalon.Eval.Gate`'s 10-run demo gate per attempt, up to three (REL-5), writing `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md`; `--override "<reason>"` records the author's override of a blocked result.

**Lead gate rulings (2026-10-30, spec gate).**
- The three veto-window items (the key's path, the `ocutalon.evalResult/1` result format, NFR-4 over `decide` decisions) are kept as planned: one veto-window ruling, inbox U-166. Reversal of any one is a fix story.
- The proposed AD-22 as-built bullet is not written in this worktree: it sits inside AD-22's block, so the orchestrator writes it at Epic 9's merge gate with the CI as-built line (ledger DW-431). Do not edit the spine.
- No stage of this story runs `--release-candidate` without `--on-mock`, and every stage runs with `ANTHROPIC_API_KEY` unset: a real-key run (money, keys) is the owner's, at release.

**CI time (inference).**
- The `evaluation` job of `lane-a.yml` gains about 1 to 1.5 min on the runner: 10 mock diagnoses at about 1.5 to 3 s each on ARM, times about 3 on x64, plus two short sessions. That keeps it well inside its 30 minutes and REL-4's 35.
- `shards-2` gains under 10 s (`Test.Eval.Gate` is in-memory).
- The hosted `checks` job gains about 10 s for the two rules.

## Verification

`<B>` stands for:
```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

**Run discipline.**
- Tags: fresh `e9s5i`, warm `e9s5iw`. QA and review use their own stage names and tags.
- Run from the epic-9 worktree root, each command in the foreground of its own call with `timeout: 600000`.
- Make one `iris_execute_tests` call per message, and pass `server` and `namespace` on every IRIS MCP call.
- Never set `ANTHROPIC_API_KEY` to a real key, and never run `--release-candidate` without `--on-mock`: a real-key run is the author's.

**Runtime targets.**
- Slot B: `server` `ocutalon-slot-b`, namespace `OCUTALON`, for `iris_server_info` and compile checks only. Never run EvalIn or a test there.
- Every test runs on throwaways through `ci/iris.sh` or `eval/run.sh` with `<B>`.
- Tear down only `e9s5i` and `e9s5iw`.

**Shared surfaces:**
- `Report.Build`'s incident entry (`fixParameters`) and its cost entries (`durationMs`), asserted by `Test.Eval.Report` and `Test.Eval.Run`.
- `Report.Save` through `WriteFiles`, and the four helpers made public.
- `eval/run.sh`'s arguments and its `CHK` lines, including run 3, and the `run-guard` rule.
- The files at the `eval/` root, read by the cases rule, `CaseNames` and the boundaries scan.
- The evaluation job's time.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-b`. Then load and compile `Eval.Report`, `Eval.Gate`, `Test.Eval.ZzGate`, `Test.Eval.Gate` and `Test.Eval.Report` on slot B, namespace `OCUTALON`. -- expected: build 154, port 1991, every class compiles.
- (once) `<B> OCUTALON_RUN_TAG=e9s5iw ci/warm.sh up` -- expected: ready.
- (loop) Each of these in its own call: `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s5iw ci/iris.sh class OcuTalon.Test.Eval.Gate`, then `OcuTalon.Test.Eval.Report` and `OcuTalon.Test.Bridge.CodeRules`. -- expected: each passed.
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule passes, `rc-guard` and `rc-override` included.
- (once) `<B> OCUTALON_RUN_TAG=e9s5i bash eval/run.sh` -- expected:
  - `eval/run: all checks passed`;
  - 10 `CHK|demo|` lines with `repair_resend`, valid 1 and a time;
  - the INFO attempt line.

  Record the wall time (99 s before this story).
- (once) `<B> OCUTALON_RUN_TAG=e9s5i bash eval/run.sh --release-candidate --on-mock` -- expected:
  - 3 attempts, `VERDICT blocked`, exit 0;
  - `release-candidate-on-mock.json` and `.md` in the printed report folder, with `onMock` true;
  - `git status --short eval/` empty.

  Record the wall time; about 4 to 6 min is expected (inference). If it nears 9 min, stop and report it.
- (once) `<B> OCUTALON_RUN_TAG=e9s5i ci/iris.sh class OcuTalon.Test.Eval.Run` (fresh) -- expected: passed.
- (once) Use `ci/iris.sh classes lane-a@rest` to find the `--part k/8` parts that hold `Test.Eval.Gate` and `Test.Eval.Report`. Run `<B> OCUTALON_RUN_TAG=e9s5i ci/iris.sh shard lane-a@rest --part k/8` for each, then each with `--reverse`, one per call. -- expected: every class passes. Record the times.
- (once) `bash ci/checks.sh` -- expected: every block passes, including `boundaries`, `eval-set`, `class-rules` and `storage`.
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s5iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s5i ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-b folder.

**Planned mutations (Rule 19).** Apply each mutation, observe the red, then revert. Confirm that `git status --short` and `git diff --stat` are as before, then write the `mutation:` line.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `--release-candidate` accepts an empty `ANTHROPIC_API_KEY` | `rc-guard` |
| AC1 | The override file loses its base-URL line | `rc-guard` |
| AC1 | `Attempt` counts a null `met` of SM-1 as met | `Test.Eval.Gate` `TestTargets` |
| AC1 | The model target accepts any model | `TestTargets` |
| AC2 | `DemoRun` skips `Fix.Kind.Check` | `TestDemoRunFails` (a field not in the sample) |
| AC2 | `Demo` makes `RUNS - 1` calls | `TestDemoLoop`, and `eval/run.sh` run 3 |
| AC2 | `DemoRun` drops `durationMs` | `TestDemoTiming`, and `eval/run.sh` run 3 |
| AC3 | `Verdict` passes at 1 of 3 | `TestVerdict` |
| AC3 | `--override` accepts a `pass` file | `rc-override` |
| AC4 | `Result`'s summary drops `heldOutItems` | `TestResult` |
| AC4 | The real-tree result check accepts `onMock` true | `rc-override` (its bad sample) |
| Integration | `Report` stops setting `fixParameters` | `Test.Eval.Report` `TestGateReadsTheReport`, and `eval/run.sh` run 3 (valid 0) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
