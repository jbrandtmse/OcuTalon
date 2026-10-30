---
title: 'Story 9.5: Release candidates pass the evaluation and the demo incident gate'
type: 'feature'
created: '2026-10-30'
status: 'done'
review_loop_iteration: 0
baseline_revision: '414e2cc322c4a1b5c8eb0a2b13b52dffaed48141'
baseline_commit: '414e2cc322c4a1b5c8eb0a2b13b52dffaed48141'
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

### Review Findings

Code review, 2026-10-30. Four layers ran on the full-opus tier: blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor. They reported 25 rows, which grouped into 13 entries (high 0, med 6, low 7) and 9 rejections. Every MED was patched in this pass. Each entry is listed as severity / fix-risk / footprint / disposition.

- [x] [Review][Patch] `rc-stack` runs lib-live's `ensure_web_bundle` on a checkout without the bundle. In the hosted `checks` job that means `npm --prefix web ci` and a web build, or a red rule. The stub folder now holds an `npm` that does nothing. Verified on a copy of the tree without the bundle: the rule passed and npm never ran. [docker/tests/test-eval-set.sh:1688] — med / low / in-story / fixed (blind+edge+auditor)
- [x] [Review][Patch] The real-key ending of `--release-candidate` had no executing test, and the on-mock rehearsal leaves before it. The untested parts were exit 3 on blocked, exit 0 on pass, the pair copied into `eval/`, the stop after attempt 1 met, the 900 s default and the readiness's key and model lines. Fixed with a new rule, `rc-flow`: the real script runs from a copy tree on a stub of a healthy stack, through six cases, with 8 bad samples derived from `eval/run.sh`. [docker/tests/test-eval-set.sh:1855] — med / med / in-story / fixed (verification-gap; AC1, AC3, AC4)
- [x] [Review][Patch] `Gate.Attempt` was never run on a set that `Report.Build` made, so the two classes' field names were unpinned. Added `TestAttemptReadsTheReport`: NFR-4 and the model come from the cost entries, NFR-3 from the size, and SM-1 from the items share. [src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls:1621] — med / low / in-story / fixed (verification-gap; Integration)
- [x] [Review][Patch] No test rendered a blocked result against the exact line `Verdict: blocked` that `--override` requires. `TestText` now renders three not-met attempts and asserts that line. [src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls:477] — med / low / in-story / fixed (blind+verification-gap; AC3)
- [x] [Review][Patch] The result's `commit`, `branch` and `treeClean` were read after the attempts, so a commit or checkout during a long run named a tree that was never built. They are now read before `stack_start`. [eval/run.sh:370] — med / low / in-story / fixed (blind+edge; AC4)
- [x] [Review][Patch] The push run's run 3 ran even when run 1 had not diagnosed the demo incident. A demo case that never ends makes each of the ten runs wait the whole limit (10 × 180 s), which passes `lane-a.yml`'s 30-minute job timeout. Run 3 now fails without running in that case. [eval/run.sh:626] — med / low / in-story / fixed (blind; AC5)
- [x] [Review][Defer] In `--release-candidate`, the key stays in the environment of lib-live's `ensure_web_bundle` (npm install scripts and the web build) when the checkout has no bundle. This is a veto-window item (secret handling), so it was not patched. [eval/run.sh:164] — deferred: DW-434, low / low / in-story / decision-pending owner=burndown, with the recommended one-line fix
- [x] [Review][Patch] `Test.Eval.Report`'s comments said that `NormalizeDirectory` of a missing directory returns "". Per `%Library.File` it does so only when the base cannot be entered, so the comments now state the contract. [src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls:59, :1144] — low / low / in-story / fixed (blind)
- [x] [Review][Patch] `Test.Eval.Gate`'s header said "the eight cases" of `TestVerdict`; there are nine. [src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls:17] — low / low / in-story / fixed (blind)
- [x] [Review][Patch] `TestDemoLoop`'s label and the header said "no demo snapshot" or "a snapshot that cannot be read" for a folder that has no demo case. [src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls:11, :210] — low / low / in-story / fixed (verification-gap)
- [x] [Review][Patch] The `demo_checks` comment named a `demo_pushed` function that does not exist. [eval/run.sh:326] — low / low / in-story / fixed (auditor)
- [x] [Review][Patch] `rc-guard` accepted any exit but 2 for the accepted forms, while the spec says exit 1. [docker/tests/test-eval-set.sh:1473] — low / low / in-story / fixed (auditor)
- [x] [Review][Defer] `Gate.SampleFields` repeats the sample-field loop of `DiagnosisPayload.CheckFix` (6 lines) instead of a shared `EvidencePack` helper. The spec names the sibling but gives no reason not to share it. [src/ocutalon/cls/OcuTalon/Eval/Gate.cls:118] — deferred: DW-435, low / low / out-of-footprint (`Watch/**`) / wontfix-accepted with reopen_if (reviewer, Rule 2)

Rejected:
- (blind, verification-gap) The Auto Run Result and residual risks are stale after QA. The fix would edit the spec's own result section.
- (edge) `SampleFields` returns OK with no field. Low: `TestSampleFields` pins `OrderDate` in the fields on every CI run, and the fix adds a guard.
- (edge) The second `cp` into `eval/` fails after the first. Low: it needs a full disk between two copies, and the fix is temp-and-rename.
- (edge) `OCUTALON_EVAL_REPORT_DIR` points inside the checkout. Low: it is an operator setting, and the fix adds a guard.
- (edge) `Verdict` passes at 2 of 4 attempts. Low: `run.sh` caps the attempts at 3, and the fix adds a guard.
- (edge, verification-gap) `Test.Eval.Gate`'s folder could be "". False: with an absolute base, `NormalizeDirectory` returns "" only when the base cannot be entered (`%Library/File.cls` :106-116), and the base is the manager's Temp directory.
- (verification-gap) `SampleFields`'s guards for no plain snapshot file and an unreadable snapshot are untested. Low: they are defensive branches.
- (verification-gap) Two `TestTargets` blocks depend on the statement before them. False as a hermeticity defect: the order is fixed inside one method, `OnBeforeOneTest` clears the global, and a wrong order fails loudly.
- (auditor) The result format carries `decidedBy` and each run's `offModel[]`, which the spec's lists do not name. Low: both are additive and documented in the class doc, `offModel` is what the model target over the demo runs needs, and Story 11.4 reads neither.

## Spec Change Log

- 2026-10-30, lead spec gate: Design Notes gained "Lead gate rulings" (U-166 veto for the key path, the result format and NFR-4's reading; the AD-22 as-built bullet goes to the orchestrator with DW-431; no real-key run in any stage). No intent change.

## Review Triage Log

### 2026-10-30 — Review pass
- verdicts: 41 findings — high 0, medium 5, low 32, false 3, maybe-false 1
- findings:
  - `[low]` `[reject]` (blind) An override reason that looks like a `Verdict:` line adds a second such line — the override path refuses a blank, multi-line, non-ASCII or long reason, the JSON stays the reader's source, and a second override is refused by the JSON verdict; a guard for this is more than a correction.
  - `[low]` `[reject]` (blind) The override writes the JSON and then the Markdown, so a failed second write leaves them apart — needs a full disk or a permission fault between two writes; the fix is temp-and-rename machinery.
  - `[low]` `[reject]` (blind) The tree check does not tie the committed Markdown to the JSON — no result is committed yet, and `--override` already refuses a pair whose Markdown lacks its single `Verdict: blocked` line.
  - `[medium]` `[patch]` (blind) The model target is met with no decision observed, and a demo run can pass with no diagnose decision — confirmed in `ModelTarget`; patched with E7, E8 and E9 below.
  - `[low]` `[reject]` (blind) The `--release-candidate` loop and exit codes have no CI test — the spec names the `--on-mock` run as its evidence and forbids a new workflow or job; the rehearsal was run in this pass (exit 0, 3 attempts, blocked).
  - `[low]` `[reject]` (blind) No fail-fast on a bad key — a revoked key yields fallbacks, which the clean target counts as problems; the verdict is a plain `blocked`, and the spec asks for no probe.
  - `[low]` `[reject]` (blind) The push run adds work with no time estimate, and `attempt_run` runs after a failed demo check — the spec's Design Notes carry the time estimate; the push run measured 110 s against 99 s; a second failure line is cosmetic.
  - `[low]` `[reject]` (blind) `--override` checks less than the tree check (format, `onMock`) — the generator writes the file and the override needs a `blocked` verdict; thin audit data is the spec's `{reason, at}`.
  - `[low]` `[reject]` (blind) The override's invalid-JSON, non-object and two-line branches are untested — defensive refusals that the Matrix does not list; same as the verification-gap row on the override guards.
  - `[low]` `[reject]` (blind) `Verdict` counts can disagree with `attempts[]` when attempt 1 met — `run.sh` never passes such an input and the tests pin the pattern.
  - `[low]` `[reject]` (edge) A whitespace-only key passes the guard — the Matrix says unset or empty; a whitespace key makes fallbacks that the clean target reports.
  - `[low]` `[reject]` (edge) A finished run replaces an existing pair — by-design: a finished run is the new result (it carries its commit), and the spec says a failed run writes nothing.
  - `[maybe-false]` `[reject]` (edge) Demo runs may leave watch rows behind — `Report.Problems` already flags a run that acted; a leftover-rows check is not in the spec; it would be worth a probe only if a real run showed rows.
  - `[low]` `[reject]` (edge) No overall time bound on a release-candidate run — every wait is bounded by `OCUTALON_EVAL_WAIT`, and the run is the author's, at the terminal.
  - `[low]` `[reject]` (edge) A run passes with valid parameters for another sample field — by-design: the spec's pass rule is the case, `repair_resend` and `Fix.Kind.Check` (AD-16).
  - `[low]` `[reject]` (edge) `causeRight` takes `Report`'s lenient `Same()` — by-design: the spec says `right` is the report's own match.
  - `[medium]` `[patch]` (edge) A decided demo run with no diagnose decision has no model — same root cause as the blind row; `ModelTarget` now lists a decided run with an empty model.
  - `[medium]` `[patch]` (edge) A set with no decision at all meets the model target — `ModelTarget` now lists "(the set has no decision)".
  - `[medium]` `[patch]` (edge) NFR-4 is met with no attention decision measured — `CostTarget` now lists "(the set has no attention decision)" as unpriced.
  - `[low]` `[reject]` (edge) A JSON array or string for the set or the demo can throw in `Attempt` — `run.sh` writes both files itself with `Report.WriteFiles`.
  - `[low]` `[reject]` (edge) A Markdown reason can render as a heading — printable ASCII is what the Matrix allows, and the reason lands under its own `## Override`.
  - `[low]` `[reject]` (edge) A blocked file without the `override` key is refused as "already overridden" — the generator always writes null.
  - `[low]` `[reject]` (edge) `WriteFiles` with empty text leaves an old `.md` — no caller writes the same name with and without text.
  - `[false]` `[reject]` (edge, claim) Parameters are checked against the recorded snapshot's fields, not the live pack — the spec says so: the fields are those of the pack built from the demo snapshot, which are what Decide's reply check gets.
  - `[low]` `[reject]` (edge, claim) The causeRight match is not an exact comparison — same as the `Same()` row, by-design.
  - `[low]` `[reject]` (edge, claim) After a failed run the previous pair stays in `eval/` — by-design: a failed run writes nothing, and each pair names its commit.
  - `[low]` `[reject]` (verification-gap) The rc loop, exit codes and `eval/` isolation have no automated test — the spec's evidence is the `--on-mock` run, run again in this pass; no workflow change is allowed.
  - `[low]` `[reject]` (verification-gap) The real-key readiness `check_session` has no executing test — it needs a key; the spec makes the real leg the author's first run.
  - `[low]` `[reject]` (verification-gap) The override's `override !== null` and count guards have no isolating fixture — defensive, outside the Matrix.
  - `[low]` `[patch]` (verification-gap) `Attempt`'s null-size normalisation is unasserted — added the assertion and its mutation line.
  - `[low]` `[patch]` (verification-gap) The model target's `unpriced` list is untested — added the case and its mutation line.
  - `[medium]` `[patch]` (verification-gap) In `TestDemoRunFails`, the `{}` assertion could not tell a throw from a failure — confirmed: `Report.Problems({})` throws and `DemoRun` catches it; both lines now use `Fails` and name their reason ("the run did not finish", "the fix parameters were refused: ").
  - `[low]` `[patch]` (verification-gap) The no-sample-fields assertion would pass for any reason — folded into the row above.
  - `[low]` `[patch]` (verification-gap) AC5 has no `mutation:` line — written from the mutations demonstrated against run 3.
  - `[low]` `[reject]` (verification-gap) The tests read the shipped `eval/` mount with no "not mounted" message — they run in a throwaway and fail loudly outside it.
  - `[low]` `[reject]` (verification-gap) The tree check of `eval/release-candidate.json` is vacuous until a pair exists — its bad samples pin the checker; the first real run adds the file.
  - `[low]` `[reject]` (intent-alignment) The loop and exit codes are tested only by a manual run — same as the verification-gap row.
  - `[low]` `[reject]` (intent-alignment) The failure branches of the demo gate are exercised through synthetic reports — a mock answer is fixed; the real leg is the author's.
  - `[low]` `[reject]` (intent-alignment) The readiness block that checks the key's presence runs only in the real mode — same as the verification-gap row.
  - `[false]` `[reject]` (intent-alignment) The push run fails when the demo gate is not 10 of 10 — the spec requires exactly that structural check on the mock, and the attempt's targets stay INFO.
  - `[false]` `[reject]` (intent-alignment) `incomplete` is not named in AC3 — the spec's `Verdict` defines it and the Matrix row "RC structural failure" maps it to exit 1 with nothing written.

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

**Mutation results (implement stage, each applied, observed red and reverted; tree byte-identical afterwards).**
- mutation: AC1 `--release-candidate` accepts an empty `ANTHROPIC_API_KEY` (`-z "${ANTHROPIC_API_KEY+x}"`) -> `test-eval-set.sh` rule `rc-guard` red ("--release-candidate with the key empty is not refused with exit 2"); reverted.
- mutation: AC1 the override file loses its base-URL line -> `rc-guard` red ("the code lines are not exactly the six lines of the override"); reverted.
- mutation: AC1 `Attempt` counts a null `met` of SM-1 as met -> `Test.Eval.Gate` `TestTargets` red ("a null met of SM-1 counts as not met", and SM-2's); reverted.
- mutation: AC1 the model target accepts any model -> `TestTargets` red (set and demo-run model rows); reverted.
- mutation: AC2 `DemoRun` skips `Fix.Kind.Check` -> `TestDemoRunFails` red (a field not in the sample, an unregistered format, one format twice); reverted.
- mutation: AC2 `Demo` makes `RUNS - 1` calls -> `TestDemoLoop` red ("the run is called exactly ten times") and `eval/run.sh` run 3 red ("the demo gate is '9|10|0' with 9 run line(s)"); reverted.
- mutation: AC2 `DemoRun` drops `durationMs` -> `TestDemoTiming` and `TestDemoRunPasses` red, and `eval/run.sh` run 3 red ("10 of the 10 runs has no pass, a fallback, invalid fix parameters or no diagnosis time"); reverted.
- mutation: AC3 `Verdict` passes at 1 of 3 (`count '< 1`) -> `TestVerdict` red (`nnm`, `nmn`); reverted.
- mutation: AC3 `--override` accepts a `pass` file (the verdict check removed) -> `rc-override` red ("a result whose verdict is pass is not refused with exit 2"); reverted.
- mutation: AC4 `Result`'s summary drops `heldOutItems` (`SCORES` without it) -> `TestResult` red ("it holds all eight scores", "a held-out score keeps its figures") and `TestTargets` red; reverted.
- mutation: AC4 the real-tree result check accepts `onMock` true -> `rc-override` red (the sample `bad-json-on-mock` is not flagged); reverted.
- mutation: Integration `Report` stops setting `fixParameters` -> `Test.Eval.Report` `TestGateReadsTheReport` and `TestIncidents` red, and `eval/run.sh` run 3 red (valid 0: "the parameters of repair_resend are not a JSON object", "the demo gate is '0|10|0'"); reverted.
- mutation: AC5 `Demo` makes `RUNS - 1` calls, or `Report` stops setting `fixParameters` (the same two mutations as AC2 and the Integration row) -> `eval/run.sh` run 3 red ("the demo gate is '9|10|0' with 9 run line(s)", "the demo gate is '0|10|0'"): the push run fails on a structural check, and on the mock it stays green with the attempt's `met 0` (SM-1, SM-2 below), which it only prints as INFO.
- mutation: AC1 (review patch) `Attempt` drops the null normalisation of `size.largestTokens` -> `TestTargets` red ("a size that is not known is a JSON null in the attempt"); reverted.
- mutation: AC1 (review patch) `ModelTarget` reads only `cost.decisions`, not `cost.unpriced` -> `TestTargets` red ("another model in the unpriced list does not meet the model target"); reverted.
- mutation: AC1 (review patch) `ModelTarget` met on a set with no decision -> `TestTargets` red ("a set with no decision has nothing measured...", "an empty set reports the targets it cannot meet"); reverted.
- mutation: AC1 (review patch) `ModelTarget` met on a decided demo run with no diagnose decision -> `TestTargets` red ("a decided demo run with no diagnose decision has no model observed"); reverted.
- mutation: AC1 (review patch) `CostTarget` met on a set with no attention decision -> `TestTargets` red ("a set with no decision has nothing measured, so NFR-4 and the model are not met"); reverted.

**Measured (implement stage, tags e9s5h and e9s5hw).**
- `eval/run.sh` (push run): all checks passed, 20 PASS lines, wall 105 s (ready 89 s); 10 `CHK|demo|` lines with `repair_resend`, valid 1 and a time of 272 to 277 ms on the mock; `CHK|demogate|10|10|1`; `INFO attempt on the CI mock: met 0; below: SM-1,SM-2`. Before this story 99 s.
- `eval/run.sh --release-candidate --on-mock`: 3 attempts, `VERDICT blocked`, exit 0, wall 120 s (ready 89 s); `release-candidate-on-mock.json` and `.md` in the report folder with `onMock` true; no result file written in `eval/`.
- `Test.Eval.Run` fresh: passed (8.4 s in the class, 100 s wall). Shard `lane-a@rest --part 5/8` (holds Gate and Report): passed, 169 s wall; `--part 4/8 --reverse` (holds both): passed, 161 s wall. `bash ci/checks.sh`: all 17 blocks passed (232 s). `bash docker/tests/test-eval-set.sh`: every rule passed, 22 s.

**QA stage (tags e9s5q and e9s5qw; no key, no spend; every mutation applied, red observed, reverted, tree compared with a backup).**

Files changed by QA (QA): `docker/tests/test-eval-set.sh` (new rule `rc-stack`; `rc-guard` and `rc-override` strengthened; header updated), `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls` (new `TestDemoRunReadsTheDiagnoseDecision`), `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` (`TestSave` and `TestSaveRefusals` build their directory with `SubDirectoryName`, and `TestSave` asserts that Save makes it). No product file was changed.

Gaps found and closed:
- `rc-guard` looked for the key only in the output of the accepted forms and in the stub's calls. It now also looks in the output of every refused argument, in every file of the run's folder, and in every file of the tree written during a run (the key of the run before is overwritten by the next, so the scan is after each run).
- Nothing pinned that the real-key form lays `eval/compose.release-candidate.yml` over its stack, starts it with `OCUTALON_EVAL=1` and the key in the environment, and never calls `PointKeys`, `RestoreKeys` or `ReadyReason`, or that `--on-mock` does the opposite. The new rule `rc-stack` runs the real script with a stub of the container tool that succeeds, prints nothing and records each call, each IRIS session's input and the environment (presence of the key, never its value); the script stops at its first IRIS session. About 2 s per form.
- `--override` was not pinned to make no container call (Matrix: "No container call"). `rc-override` now runs it with a recording stub on the PATH.
- `Gate.ReadDiagnosis` was tested only with one decision in the report, so the choice of the demo case's diagnose decision (time, cost, model), the unpriced diagnose decision and an off-model decision of another kind were unpinned.
- `TestSave`: the implement stage's probe (`NormalizeDirectory("zz-out", ..Folder)` returned an empty string) is a property of the dev slot. On the throwaway (Linux) it returns the full path, and the original assertions went red under the mutation below (so the assertion could fail where the test runs); the construction is still platform-fragile, since an empty string would make Save write into the process's own directory, so it now uses `SubDirectoryName` and asserts the path is its own.

- mutation: AC1 `--release-candidate` accepts an empty `ANTHROPIC_API_KEY` (`-z "${ANTHROPIC_API_KEY+x}"`) -> `test-eval-set.sh` `rc-guard` red ("--release-candidate with the key empty is not refused with exit 2"); reverted.
- mutation: AC1 the usage line prints `$ANTHROPIC_API_KEY` -> `rc-guard` red ("the key appears in the output of the refused arguments"), 9 args; reverted.
- mutation: AC1 `eval/run.sh` writes the key to a file (`key.txt`, after the guard) -> `rc-guard` red ("a file of the tree holds the value of the key") and `rc-stack` red; reverted (the file removed).
- mutation: AC1 the real-key form no longer lays `compose.release-candidate.yml` over the stack -> `rc-stack` red ("is not layered with eval/compose.release-candidate.yml"); reverted.
- mutation: AC1 the real-key readiness session also calls `PointKeys` -> `rc-stack` red ("calls PointKeys, RestoreKeys or ReadyReason"); reverted.
- mutation: AC1 `export OCUTALON_EVAL=1` removed -> `rc-stack` red (both forms); reverted.
- mutation: AC1 `--on-mock` readiness no longer calls `PointKeys` -> `rc-stack` red ("does not point the keys at the mock"); reverted.
- mutation: AC3 `--override` accepts a non-blocked verdict (the verdict check removed) -> `rc-override` red ("a result whose verdict is pass is not refused with exit 2" and both files changed); reverted.
- mutation: AC3 `--override` calls the container tool -> `rc-override` red ("the override called the container tool") and `eval-scripts` red; reverted.
- mutation: AC2 `Gate.ReadDiagnosis` takes the last decision of the case whatever its kind (the kind test dropped) -> `Test.Eval.Gate` `TestDemoRunReadsTheDiagnoseDecision` red; reverted.
- mutation: AC2 `ReadDiagnosis` takes a diagnose decision of any case (the case test dropped) -> `TestDemoRunReadsTheDiagnoseDecision` red; reverted.
- mutation: AC1 `ReadDiagnosis` lists only a diagnose decision as off-model -> `TestDemoRunReadsTheDiagnoseDecision` red (listed, and the model target); reverted.
- mutation: AC4 `Report.WriteFiles` does not create the report directory -> `Test.Eval.Report` `TestSave` and `TestWriteFiles` red ("Save succeeds", "and makes the directory"); reverted. The same mutation was also red against the original `TestSave` on the throwaway.
- mutation: AC4 `WriteFiles` makes the directory before it checks the name -> `TestSaveRefusals` and `TestWriteFiles` red ("and no directory was made for them"); reverted.
- mutation: AC4 the directory already exists when `TestSave` asserts that it is not there yet -> `TestSave` red; reverted (test change, restored).
- mutation: AC2/AC5/Integration `Gate.Demo` makes `RUNS - 1` calls -> `eval/run.sh` push run (fresh, tag e9s5q) red ("the demo gate is '9|10|0' with 9 run line(s)"), the INFO line "below: SM-1,SM-2,Demo gate"; reverted.

Runs after the changes: `bash docker/tests/test-eval-set.sh` all rules passed (about 24 s; was 22 s); `bash ci/checks.sh` all scripts passed; warm `Test.Eval.Gate`, `Test.Eval.Report` and `Test.Bridge.CodeRules` passed. Throwaways `e9s5q` and `e9s5qw` torn down; the lane-b lock folder is empty.

**Code review stage (tags `e9s5r` and `e9s5rw`; no key, no spend).** Each mutation was applied, its red observed, and the file restored from a backup; `git status --short` and `git diff --stat` were then compared with the record taken before.
- mutation: AC3 `Gate.Text` writes a blocked verdict line as `Verdict: blocked (REL-5)` -> `Test.Eval.Gate` `TestText` red ("and it is exactly the line Verdict: blocked that eval/run.sh --override requires"); restored.
- mutation: Integration `Gate.SizeTarget` reads the set's `size.unknownCases` instead of `size.unknown` -> `Test.Eval.Report` `TestAttemptReadsTheReport` red ("a request of unknown size in the built set misses NFR-3"); restored.
- mutation: AC3 `eval/run.sh` ends a blocked verdict with exit 0 (the pass test made `[ "$verdict" = blocked ]`) -> `test-eval-set.sh` rule `rc-flow` red ("--release-candidate with a blocked verdict does not end with VERDICT blocked and exit 3 (exit 0)"); restored. A mutation that removes the text a bad sample edits (`exit 3` -> `exit 0`) stops the sample writer with "rc-flow: eval/run.sh has no text ... to edit", so the samples cannot drift silently from the script.
- mutation (kept as `rc-flow` bad samples, each flagged for its own reason on every run):
  - AC3: a blocked verdict exits 0 (`bad-blocked-exit-0`).
  - AC4: no copy into `eval/` (`bad-no-copy`); `--on-mock` goes on past its exit (`bad-on-mock-goes-on`); an incomplete verdict is kept (`bad-incomplete-kept`).
  - AC1: a 180 s default wait (`bad-wait-180`); no stop after attempt 1 meets every target (`bad-no-stop-at-1`); a readiness check without the model lines (`bad-any-model`) or without the key lines (`bad-no-key-check`).

Measured after the review patches:
- `bash docker/tests/test-eval-set.sh`: every rule passed, `rc-flow` included, in 34 s (was 24 s).
- The same check on a copy of the tree with no web bundle (the hosted `checks` condition): `rc-stack` and `rc-flow` passed, and no npm ran.
- The push run `bash eval/run.sh` (fresh): all checks passed in 105 s; run 3 gave 10 of 10, and the INFO line read "below: SM-1,SM-2".
- `--release-candidate --on-mock`: 3 attempts, `VERDICT blocked`, exit 0, in 125 s. The commit `fe2bf5ec` and branch `OCT-epic9` were read before the build, the pair was only in the report folder, and nothing was written in `eval/`.
- `--override` on a scratch copy of that generated blocked pair: exit 0, verdict `overridden`, and the reason kept.
- Warm `Test.Eval.Gate`, `Test.Eval.Report` and `Test.Bridge.CodeRules`: passed.
- `bash ci/checks.sh`: all 17 scripts passed in 4 min 2 s.
- Throwaways `e9s5r` and `e9s5rw` were torn down, and the lane-b lock folder is empty.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Eval.Gate` holds the 10-run demo-incident gate over `Report.Run`, one attempt's targets (SM-1, SM-2 with the demo gate, NFR-3, NFR-4, model, no problem), REL-5's verdict, and the result document and its text. `Eval.Report` gains `fixParameters` and `durationMs` and the shared `WriteFiles`, and its four text helpers are public. `eval/run.sh` gains `--release-candidate`, `--release-candidate --on-mock` and `--override`, and the push run gains run 3 (the demo gate, plus the attempt's targets as INFO). No real key was used and no `--release-candidate` run without `--on-mock` was made.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls` (new): the gate.
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls`: the two fields, `WriteFiles`, public helpers.
- `eval/run.sh`: the three modes, run 3, the header.
- `eval/compose.release-candidate.yml` (new): the key by interpolation, an empty base URL, mock header 0.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls`, `ZzGate.cls` (new), `Report.cls`, `Run.cls`: the tests.
- `docker/tests/test-eval-set.sh`: the `rc-guard` and `rc-override` rules.

**Review.** 41 findings from four layers: high 0, medium 5, low 32, false 3, maybe-false 1. Patches applied: 5 entries (the model and NFR-4 targets met with nothing observed, in `Gate.ModelTarget` and `Gate.CostTarget`; the weak `TestDemoRunFails` assertions; the unasserted null size; the untested `unpriced` list; the AC5 mutation line), each with a test and a demonstrated mutation. Deferred: none. Every rejected finding and its reason is in the Review Triage Log.

**Follow-up review recommended:** false (one medium entry patched, no high).

**Verification.** After the patches: `Test.Eval.Gate`, `Test.Eval.Report` and `Test.Bridge.CodeRules` passed on the warm stack; `test-eval-set.sh` all rules passed; the push run passed (110 s); the on-mock rehearsal ended with 3 attempts, `VERDICT blocked`, exit 0 and nothing written in `eval/`; `Test.Eval.Run` fresh passed; `lane-a@rest` parts 5/8 forward and 4/8 reverse passed; `bash ci/checks.sh` passed. Throwaways `e9s5i`, `e9s5iw` torn down; the lane-b lock folder is empty.

**Residual risks.** The real-key leg (key by compose interpolation to the throwaway, an empty base URL, the readiness lines with a real key, the real endpoint) is untested by design and is the author's first release-candidate run (Story 11.5). The `--release-candidate` loop and its exit codes are proved by the `--on-mock` run, not by a CI test. Pre-existing and unchanged: `Test.Eval.Report.TestSave` builds its directory with `NormalizeDirectory`, which returned an empty string in a probe, so its "directory not there yet" assertion looks vacuous.
