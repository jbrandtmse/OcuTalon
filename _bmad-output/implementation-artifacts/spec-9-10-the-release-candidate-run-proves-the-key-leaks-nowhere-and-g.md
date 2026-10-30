---
title: 'Story 9.10: The release-candidate run proves the key leaks nowhere and gates the maximum decision cost'
type: 'feature'
created: '2026-10-30'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 9.5's release-candidate gate was kept by the owner's delegate under veto item U-166 with three conditions that it does not yet meet:
- (a) NFR-4 must visibly be judged on the most expensive item decision, not on the mean. The gate already fails on any `decide` decision at or over $0.001, but no test pins "mean under, one decision over", and neither `release-candidate.md` nor `release-candidate.json` says which figure is gated.
- (b) Nothing proves that the model key, taken through `eval/compose.release-candidate.yml`, ends up in no file, log, output, trace or global, or that the throwaway is gone afterwards.
- (c) Nothing stops the author from committing a result pair that holds key-like text.

DW-434 adds a fourth gap: in a checkout without the web bundle, `npm ci` and the web build run with the real key in their environment.

**Approach:**
- (a) `Eval.Gate` names `maxUSD` as NFR-4's gated figure in the JSON and the Markdown. The mean of the item decisions is shown for information only. A new test pins the maximum rule.
- (b) Two pieces:
  - `eval/run.sh --release-candidate --on-mock` with `ANTHROPIC_API_KEY` set becomes the **key-path rehearsal**. The key goes through the release-candidate override into the throwaway. `ci/compose.ci.yml`, layered again after the override, keeps every model request on the CI mock. Before teardown, the run scans for the key's value in globals, stores, the trace, container logs, container files, its own logs and `eval/`.
  - A new harness, `eval/key-proof.sh`, does the rest:
    - builds a fake key from fragments and runs the rehearsal with it;
    - checks the captured output, `eval/` and the report folder;
    - proves that the teardown of the run's tag finds no project, container or volume.

    The harness runs as a new step of Epic 9's own `evaluation` job.
- (c) `eval/run.sh` scans the result pair it wrote with the key-like patterns of `docker/tests/test-boundaries.sh`. Both scripts now read those patterns from one new file, `docker/tests/lib-keys.sh`. On a match the run exits 4 and tells the author not to commit the pair. `--override` gets the same scan.
- DW-434: `eval/run.sh` builds the web bundle in a subshell without the key before `stack_start`.

## Boundaries & Constraints

**Always:**
- **NFR-4 (owner condition U-166 (a)).** NFR-4 is met only when every priced `decide` decision of the set costs under `Report.FLAGUSD` and none is unpriced. The mean never decides it.
  - `targets.nfr4` and `summary.attentionCost` carry `gated: "maxUSD"`, `maxUSD`, `maxCase`, `flagUSD`, `flagged[]`, `unpriced[]`, `priced` and `meanUSD`. `meanUSD` is the mean of the priced `decide` decisions, `$Number(sum / priced, 6)`, or null.
  - `summary.attentionCost` also carries `met` and `informationOnly: ["meanUSD"]`.
  - The format stays `ocutalon.evalResult/1`. The fields are additive.
- **The key-path rehearsal** is `--release-candidate --on-mock` with `ANTHROPIC_API_KEY` non-empty in the script's environment. In order:
  1. It prints `INFO --on-mock with ANTHROPIC_API_KEY set: the key goes through eval/compose.release-candidate.yml to the CI mock only, and the run proves it is stored and shown nowhere`.
  2. It calls `live_add_file "$root/eval/compose.release-candidate.yml"` and then `live_add_file "$root/ci/compose.ci.yml"`. The key comes from the override's interpolation, and the CI file sets the mock's base URL and `OCUTALON_MOCK_KEY_HEADER` again. No other file sets that header (AD-19).
  3. Its readiness requires all of these: `RunnerFixture.ReadyReason()` empty (the production runs, the environment is the mock's, every item runs); `WaitRecords()`; `Keys.Status` 1 for the three runners; `RunnerFixture.KeysAre(Provider.#KEYPLACEHOLDER)` 1; the length of `ANTHROPIC_API_KEY` in the IRIS process equal to `${#ANTHROPIC_API_KEY}` in the script; and `claude-haiku-5-5` for the three runners. Otherwise `die`.
  4. It never calls `PointKeys` or `RestoreKeys`.
  5. It then runs the same attempts, verdict and on-mock pair as 9.5's rehearsal. Before the exit lines and the teardown, it runs the key proof below.
- **The key proof (before teardown).** Each scan prints exactly one line `PASS key proof <label>: ...` or `FAIL key proof <label>: ...`. The labels are `globals`, `stores`, `trace`, `mock log`, `container logs`, `container files`, `run files` and `eval files`.
  - **Hits.** A hit names its place (a database and global, a store, a message id, a file path, a count), never the value.
  - **Controls.** Each scan also runs a positive control that must find something, so that a scan that sees nothing fails.
  - **Fail closed.** A database, global, message body or file that cannot be read fails its scan. A scan never searches for an empty value.
  - **The scans, in order:**
    1. `globals`: every node (subscripts and data) of every global of every local database that is mounted and not read-only. Control: the `Report.DEMOCASE` name is found.
    2. `stores`: `Test.Agent.KeyScan.Find(key)` is empty. Control: `Find` of the Provider placeholder names the three runners' entries.
    3. `trace`: every `Ens.MessageHeader` of every Interoperability namespace, with its body, XML-exported. Control: the `DEMOCASE` name is found in at least one message.
    4. `mock log`: the mock's log has at least one `/v1/` request, and every `/v1/` request's `keyLength` equals the key's length. This proves the key path end to end.
    5. `container logs`: `dc logs --no-color` of every service, streamed and never written to a file, has no line holding the key. Control: lines holding `"keyLength":<n>` exist.
    6. `container files`: inside `iris`, every file below `/durable`, `/tmp` and `/opt/ocutalon/mock-log` holds no key, with no unreadable file. Control: the `DEMOCASE` name is found in a file.
    7. `run files`: every file of the run's `$tmp` and of the report folder holds no key.
    8. `eval files`: every file below `$root/eval` holds no key.

    Any `FAIL` makes the run exit 1.
- **The key's value** is read only from the environment, through `awk`'s `ENVIRON`, `$SYSTEM.Util.GetEnviron`, or `printenv ... | grep -F -f /dev/stdin` inside the container. It is never:
  - an argument of any command;
  - in an IRIS session's script;
  - in a here-string or a heredoc (bash 3.2 writes those to temp files);
  - printed, or written to a file.

  The one exception is the harness's private capture of the run's output, which is scanned and then deleted.
- **The harness, `eval/key-proof.sh`:**
  - It needs `OCUTALON_RUN_TAG`, and exits 2 without it, before anything runs.
  - It unsets any `ANTHROPIC_API_KEY` it was given. It builds the fake key `sk-` `ant-` `api03-` `ocutalonfake-` plus 40 random `[A-Za-z0-9]` characters (66 in all) from fragments, so that no file holds it, and passes it only to `eval/run.sh`'s environment.
  - **Steps:**
    1. It runs `bash ci/iris.sh teardown` for the tag as a pre-clear, printed as INFO.
    2. It runs `bash eval/run.sh --release-candidate --on-mock` with the key, with `OCUTALON_EVAL_REPORT_DIR` set to a private folder. Standard output and error go to a private capture file.
    3. It then checks all of these:
       - the run exited 0;
       - the capture holds the eight `PASS key proof` lines, `VERDICT blocked` and `eval/run: all checks passed`, and no line holding the key;
       - no file below `eval/`, no file of the checkout written during the run (outside `.git/`) and no file of the report folder holds the key;
       - `git status --porcelain -- eval/` is the same as before the run;
       - a second `bash ci/iris.sh teardown` for the tag prints `0 project(s) removed, 0 leftover container(s), 0 leftover volume(s)`.
  - It prints the run's output only when the capture is clean. Otherwise it prints line numbers only.
  - Its last line is `eval/key-proof: all checks passed` (exit 0) or `eval/key-proof: <n> check(s) failed` (exit 1).
- **DW-434.** In every mode, right before `stack_start`, in this order:
  1. `preflight` (`ci/iris.sh`), so that a missing base image or Docker still stops the run before any npm work, as in 9.5. `run-guard` and `rc-guard` keep stopping there, and their stubs need no npm. `stack_start`'s own preflight then finds everything present.
  2. `( unset ANTHROPIC_API_KEY; ensure_web_bundle ) || exit 1`.
  3. `LIVE_REBUILD_WEB=0`, so that `live_start`'s own call builds nothing.

  No npm process ever has the key. The stack's compose calls keep it, because compose interpolates every file on every call and the override's `:?` refuses an unset key.
- **The key-like scan (owner condition U-166 (c)).** `docker/tests/lib-keys.sh` is the one definition: `KEY_LIKE_ERE` (the seven alternatives that `test-boundaries.sh` has today), `key_like <files>` (prints `file:line`, the same `grep -nHIE` and `cut`), and `key_value_hits` (the value scan above).
  - `test-boundaries.sh` and `eval/run.sh` source it. Neither holds the pattern itself.
  - **After the result pair is written,** `eval/run.sh` runs `key_like` on both files of the pair it wrote: `eval/release-candidate.{json,md}`, by paths relative to the root, in the real form; and the report folder's `release-candidate-on-mock.{json,md}` with `--on-mock`.
    - With no match it prints `PASS <name>: the result pair holds no key-like text`.
    - On a match it prints `FAIL <files> hold key-like text at <file:line,...>: do not commit them; remove both, find where the text came from, and run again`, keeps the files and exits 4.
  - `--override` refuses a reason that matches `KEY_LIKE_ERE`: exit 2, `FAIL the override reason holds key-like text`, both files unchanged. After writing, it runs the same scan on both files (exit 4 on a match).
- **Exit codes of `eval/run.sh`:** 0 pass (or a finished `--on-mock` run), 1 a structural failure or a failed key proof, 2 a refusal, 3 blocked, 4 the result pair holds key-like text.
- The push run and the no-key `--on-mock` rehearsal behave as in 9.5. The only addition is the rehearsal's key-like `PASS` line.

**Never:**
- **No real key and no spend.** No stage sets a real key, and none runs `--release-candidate` without `--on-mock`.
- **No outward call.** No model request leaves the compose network: `ReadyReason` (the CI mock's environment) is checked before any case runs, and `rc-stack` pins the layering.
- **No edits to these:**
  - `docker/tests/lib-live.sh` (contended), `ci/iris.sh`, `ci/units.sh`, `ci/compose.ci.yml` and the mock;
  - `eval/compose.release-candidate.yml` (its six code lines stay);
  - `OcuTalon.Bridge.Redact` (DW-386 stays on the decision sheet);
  - `Decide`, the Provider step, `IncidentManager`, `release/**`, `docs/**` and the spine;
  - any job of `lane-a.yml` other than `evaluation`.
- **No new persistent class,** table, production item, event, cross-area message or storage change.
- **In `eval/*.sh`:**
  - no code line names the container tool, except the one exempt line `. "$root/docker/tests/lib-keys.sh"`;
  - no `dc config`, `convert` or `push`;
  - no `set -x`;
  - never reads `.env`.
- **The key proof never narrows its scope** to reach a green. A hit is a finding (see Task 0).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| NFR-4: the maximum over, the mean under | Nine `decide` decisions at 0.0001 and one at 0.001 | NFR-4 is not met, and `flagged` holds the 0.001 decision. `maxUSD` 0.001, `meanUSD` 0.00019, `gated` `maxUSD`. The attempt is below target | No error expected |
| NFR-4 met | Every `decide` decision under 0.001 | Met. The text says it is judged on the maximum, and the mean line says "for information only" | No error expected |
| NFR-4 not measured | No priced `decide` decision | `maxUSD` and `meanUSD` null. The line says "not known". Not met (as 9.5) | No error expected |
| Key-path rehearsal | `--release-candidate --on-mock`, `ANTHROPIC_API_KEY` set | The INFO line; the RC override, then the CI file again; the readiness of the Always tier; 3 attempts; `VERDICT blocked`; the eight `PASS key proof` lines; the key-like PASS line. Exit 0 | Any scan hit, failed control or unreadable store gives `FAIL key proof <label>` and exit 1. A failed readiness ends in `die` |
| Rehearsal without a key | `--on-mock`, key unset or empty | As 9.5: no override, `PointKeys`, no key proof, plus the key-like PASS line | As 9.5 |
| The harness | `OCUTALON_RUN_TAG` set | The pre-clear, the rehearsal with the fake key, the post-exit checks and teardown zeros. `eval/key-proof: all checks passed`, exit 0 | No tag: exit 2, nothing run. A non-zero run, a hit, a missing PASS line, an `eval/` change or a leftover gives a FAIL line and exit 1 |
| No web bundle (DW-434) | No `web/node_modules` or `src/ocutalon/csp/index.html`, or `LIVE_REBUILD_WEB=1`; key set | `npm ci` and the build run in the subshell, with no key. `live_start` builds nothing. Compose still gets the key | An npm failure exits 1 before any stack, as today |
| Clean result pair | RC run or `--override` writes the pair; no match | The PASS line; exit as before (0, 3) | No error expected |
| Key-like result pair | A line of either file matches `KEY_LIKE_ERE` | `FAIL ... at <file:line>: do not commit them ...`. The files are kept; the text is never printed | Exit 4 |
| Key-like override reason | `--override "<reason that matches>"` | `FAIL the override reason holds key-like text`. Both files unchanged | Exit 2 |
| Shared definition | `bash docker/tests/test-boundaries.sh` | Its `keys` rules flag the same samples as today, through `lib-keys.sh` | Its FAIL lines as today |

</intent-contract>

## Code Map

Class paths are under `src/ocutalon/cls/OcuTalon/` unless they say otherwise. Line numbers are at `46bd15df5171336b42d06505544028542f92310b`.

**(a) The gate (extend)**
- `Eval/Gate.cls`:
  - the class doc :15-16 (nfr4) and :26 (summary `attentionCost`);
  - `CostTarget` :569-611, which already flags each `decide` decision at or over `FLAGUSD` (:583, :594) and computes `maxUSD`/`maxCase` (:593);
  - `Summary` :694-714, which builds `attentionCost` (:708-714);
  - `Text`'s "## Cost and size" :357-371, with the all-kinds cost line :360 and the attention line :366.
- `Eval/Report.cls` (read-only): `FLAGUSD` :98; `cost` :164, holding all kinds (`decide`, `diagnose`, `turn`), with mean and max at :820-821; `Money` :1025.
- `Test/Eval/Gate.cls`:
  - the header :1-20;
  - `TestTargets` :243, whose NFR-4 edges at :303-313 all use one decision;
  - `TestNFR4Kinds` :357, `TestResult` :395 (attention cost :421), `TestText` :440 (cost line :459);
  - `GoodSet` :535, one `decide` decision at 0.0002 (:547).
- `Test/Eval/Report.cls` `TestAttemptReadsTheReport` :1621. It builds a set with `Report.Build` from synthetic rows, then calls `Gate.Attempt`.

**(b) The run and its stack**
- `eval/run.sh`:
  - the header :2-79, the arguments :87-103, `override_result` :108-159 (the Node program :127-155), and the key check :166-169;
  - `. ci/iris.sh`, `setup_tag` and `export OCUTALON_EVAL=1` :187-189, and `report_dir` :191-196;
  - `eval_run`/`demo_run`/`attempt_run`/`verdict_run` :206-291 and `fetch` :314;
  - the commit read :371-385; `stack_start`, the override and `stack_ready` :387-390;
  - the real readiness :393-419 and the mock readiness with `PointKeys` :420-432;
  - the RC loop :436-460, the verdict :462-477, the on-mock exit :492-496, and the copy into `eval/` and the exits :497-504.
- `eval/compose.release-candidate.yml` :9-13 (read-only): the key by `${ANTHROPIC_API_KEY:?...}`, an empty base URL, and header `"0"`.
- `ci/compose.ci.yml` :17-22 (read-only): the mock base URL `http://mock:8080/v1/` and `OCUTALON_MOCK_KEY_HEADER: "1"` (pinned as the only setter by `docker/tests/test-compose-file.sh` :287-291); the `mock-log` volume :23-24, :39-40.
- `docker/tests/lib-live.sh` (read-only, contended):
  - `live_start` :58-89, where `ensure_web_bundle` runs at :88 and `LIVE_FILES` ends with `ci/compose.ci.yml` (:86);
  - `live_add_file` :152; `ensure_web_bundle` :160-188, which reads `LIVE_REBUILD_WEB` (:161) and uses relative paths from the root;
  - `dc` :244, `live_cleanup` :266-272 (`dc down -v --rmi local`, then `rm -rf "$tmp"`), `pass`/`fail`/`die` :274-284, `iris_script` :308-319 (only `CHK|` lines kept; retried when none), and `check_session` :480.
- `ci/iris.sh` (read-only): `stack_start` :250-253; `stack_ready` :258-270; `cmd_teardown` :534-568, which prints `TEARDOWN tag <tag>: <p> project(s) removed, <c> leftover container(s), <v> leftover volume(s), ...` :567 and matches the tag's project names, `-`/`_` suffixes included (:544).
- `Test/Agent/RunnerFixture.cls` (read-only): `GuardReason` :100, `WaitRecords` :168, `ReadyReason` :306, `PointKeys` :456, `KeysAre` :470.
- `Test/Agent/KeyScan.cls` (read-only):
  - `Find(value)` :174-184: Config Store entries, settings, item settings, the event log, saved AI sessions (exported, because they are stored compressed) and agent steps;
  - `KEYVARIABLE` :29.
- `Test/Contract/Mock.cls` `LogSince(mark, .entries)` :484 (mark 0 = all). Each mock log entry has `path`, `method` and `keyLength` (`ci/mock/mock.mjs` :649-666), and the mock prints the same line to stdout.
- `Install/Step/Provider.cls` `KEYPLACEHOLDER` :32. `src/bridge/cls/OcuTalon/Bridge/Keys.cls` `Status(item)`.
- **The global-walk sibling:** `Test/Web/SessionEvents.cls` `ReferenceHits` :563-601. Read-only: `Test/Web/**` is contended by Epic 29. It walks one namespace's globals restricted to named databases.
- **Platform APIs:**
  - `irislib/%SYS/GlobalQuery.cls` `DirectoryList` :224;
  - `irissys/SYS/Database.cls` `Mounted` :202, `ReadOnly` :249, `ReadOnlyMounted` :252;
  - `irissys/Config/Databases.cls` `List` :322;
  - `irislib/%SYS/Namespace.cls` `ListAll` :165;
  - `irislib/%Library/EnsembleMgr.cls` `IsEnsembleNamespace` :79;
  - `Ens.MessageHeader` and every `Ens.MessageBody` extend `%XML.Adaptor` (`irislib/Ens/MessageBody.cls` :9).
- `.github/workflows/lane-a.yml` `evaluation` :43-63: build the bundle, `bash eval/run.sh`, then teardown with `if: always()`.

**(c) The key-like patterns**
- `docker/tests/test-boundaries.sh`:
  - `key_like` :39-41, the seven alternatives;
  - the samples :147-151, built from fragments;
  - the rule :206 and the shape check :209-219, which needs `key_like` to stay a function name.
- `docker/tests/lib-scan.sh` :1-30: the header convention that the new lib follows.
- `ci/units.sh` (no edit): `IRIS_INPUT` :123 already claims `docker/tests/lib-[^/]+\.sh$` and `eval/`.

**Checks and tests**
- `docker/tests/test-eval-set.sh`:
  - the header :1-104;
  - `check_job` :1281-1314;
  - `check_eval_scripts` :1316-1326, which flags any code line with "docker";
  - `check_rc_guard` :1434, `check_rc_override` :1598 (its copy tree has no `ci/`), and `check_rc_stack` :1672-1735 (stub tool; `ENV ... key=set|unset`; an npm stub that does nothing :1689);
  - `rcf_stub` :1741 and `check_rc_flow` :1855 (bad samples are edits of the real `eval/run.sh`);
  - the rule calls :1980-1993.

## Tasks & Acceptance

**Execution:**

**Task 0 (implement stage; measure, then decide by the rules here).** The first fresh run of `eval/key-proof.sh`, once the code is in place, is also the measurement. Record each figure under `## Verification`:
- **Compose accepts the second `ci/compose.ci.yml` layer.** If it refuses, for example over a duplicate mount, switch to this fallback, record it, and re-run: `live_pop_file`, then `live_add_file` RC, then `live_add_file` CI, after asserting that the last of `LIVE_FILES` is `$root/ci/compose.ci.yml`.
- **The scan figures:**
  - the databases scanned (and those skipped as read-only), nodes and seconds;
  - the trace's message count and body classes (each XML-exportable);
  - the container-file scan's file count and seconds;
  - the whole proof's wall time.
- **If any scan finds the key,** stop. Record the place (never the value) and HALT `blocked` with "the key is stored or shown at <place>: a finding against AD-19". Never narrow a scan.
- **If the whole proof takes more than 360 s on the developer machine,** do not add the `lane-a.yml` step. The proof becomes a local proof run recorded under `## Verification`; say so in the Auto Run Result.

**Product**
- `docker/tests/lib-keys.sh` (new) -- Rationale: AC2, AC4, one definition.
  - Header in `lib-scan.sh`'s style: sourced, defines one variable and functions only. It names its users: `test-boundaries.sh`, `eval/run.sh` and `eval/key-proof.sh`.
  - `KEY_LIKE_ERE`: the exact alternatives of `test-boundaries.sh` :40.
  - `key_like() { grep -nHIE -e "$KEY_LIKE_ERE" "$@" | cut -d: -f1,2; }`.
  - `key_value_hits <file>...`: the `file:line` of each line holding the value of `ANTHROPIC_API_KEY`, read by `awk` from `ENVIRON`, never from an argument. `-` reads standard input. It returns 2 and prints nothing when the variable is unset or empty, so an empty value never reads as clean.
- `docker/tests/test-boundaries.sh` -- source `lib-keys.sh` after `lib-scan.sh`, and delete its own `key_like`. The header says where the patterns live. No other change. Rationale: AC4 (footprint extension).
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls` -- Rationale: AC1.
  - **`CostTarget`** adds `gated: "maxUSD"`, `flagUSD` (`Report.FLAGUSD`) and `meanUSD`, as in Always. The rule stays as it is.
  - **`Summary`'s `attentionCost`** is `{gated, maxUSD, maxCase, flagUSD, flagged[], unpriced[], met, meanUSD, priced, informationOnly: ["meanUSD"]}`, taken from `targets.nfr4`.
  - **`Text`'s "## Cost and size"** becomes these three lines, each followed by a blank line, then the size line as today:
    1. `NFR-4 is judged on the maximum item-decision cost: $<maxUSD> (<maxCase>), which must be under $<flagUSD>. Item decisions at or above it: <flagged>; unpriced: <unpriced>. Met: <yes|no>.` An unknown maximum reads `not known` in place of `$<maxUSD> (<maxCase>)`.
    2. `Mean item-decision cost: $<meanUSD>, for information only.` (or `not known, for information only.`).
    3. `All decisions of the set (item decisions, diagnoses and turns), for information only: <priced> priced, mean $<mean>, maximum $<max> (<case>).` (or `...: none priced.`).
  - Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls` (new; test-only, and listed here because `eval/run.sh` calls it). It is a `%UnitTest.TestCase` with public helpers, the `Test.Agent.KeyScan` pattern. Rationale: AC2.
  - **The header** says that the helpers run in throwaways only (Rule 21), read the key only from the environment, and return counts and places, never the value.
  - **`GlobalHits(value, databases = "", Output places, Output stats) As %Integer`:**
    - `databases` is a comma-separated list of database names or directories. Empty means every local database that is mounted and not read-only, enumerated in `%SYS` (`New $Namespace`).
    - It walks each global of each database's directory (`%SYS.GlobalQuery:DirectoryList`, system globals included) with an extended reference: `$Data` of the root, then `$Query(@ref, 1, data)`. A hit is a subscript or a datum that holds the value.
    - `places` lists up to 20 `<database>:^<global>` entries. `stats` is `{databases, skipped[], globals, nodes, seconds, unreadable[]}`.
    - It returns -1 for an empty value or any unreadable database or global.
  - **`TraceHits(value, after = 0, Output places, Output stats) As %Integer`:**
    - It covers every Interoperability namespace, and each `Ens.MessageHeader` with ID above `after`.
    - It exports the header and its body (`%OpenId` of `MessageBodyClassName`/`MessageBodyId`) with `XMLExportToString`. An empty body id is header only.
    - `places` lists `<namespace>:<header id>`. `stats` is `{namespaces, messages, bodyClasses[], unreadable[]}`.
    - A body that cannot be opened or exported is unreadable, and the result is then -1.
  - **`Scan() As %DynamicObject`:** `{keyLength, globals{hits, places, stats, control}, stores{places, control}, trace{hits, places, stats, control}, mock{requests, offLength}}` for the value of `KeyScan.#KEYVARIABLE`. The controls and the mock figure are as in Always. It refuses (a `reason`, nothing scanned) when the variable is empty.
  - **Tests** (warm-safe, under 2 s, each removes what it made):
    - `TestGlobalHits`: a fresh control value set under `^OcuTalonTest("KeyProof")` is found as data and as a subscript, with `GlobalHits` scoped to the database that holds that global (`%SYS.Namespace.GetGlobalDest`). A value nobody holds gives 0, and an empty value gives -1. Then it is killed.
    - `TestTraceHits`: an `OcuTalon.Eval.Msg.IncidentCase` body with the control value and an `Ens.MessageHeader` pointing at it, after a mark, are found. A value nobody holds gives 0. Both are deleted.
    - `TestScanRefusesNoKey`: with the variable unset (`KeyScan.UnsetEnv`, then restored as found), `Scan()` gives a reason and no figures.
- `eval/run.sh` -- Rationale: AC2-AC4, **DW-434**. Update the header (modes, the rehearsal, the key proof, exit code 4).
  - **DW-434:** `preflight`, the subshell pre-build and `LIVE_REBUILD_WEB=0` of Always, after the commit read and right before `stack_start`, in every mode.
  - **`. "$root/docker/tests/lib-keys.sh"`:** sourced before the `--override` branch, so that every mode has it. This is the one exempt line.
  - **The key-path rehearsal:**
    - `keypath=1` when `onmock` is 1 and `printenv ANTHROPIC_API_KEY` is not empty;
    - the INFO line; the two `live_add_file` calls before `stack_ready`;
    - its readiness `check_session`, a third branch beside the two of :393-432, whose expected lines include `CHK|keylength|${#ANTHROPIC_API_KEY}`;
    - then the 9.5 sequence.
  - **`key_proof`** (a function), run when `keypath` is 1, after the result is fetched and printed and before the exit lines:
    - one IRIS session that prints `CHK|started|1` and then the `CHK` lines of `Test.Eval.KeyProof.Scan()` (counts, places, controls);
    - `dc logs --no-color` piped into `awk`;
    - `dc exec -T iris sh -c` running a `printenv ANTHROPIC_API_KEY | grep -rlF -f /dev/stdin --` scan over the three roots, plus its control and an unreadable-file count;
    - `key_value_hits` over `$tmp`, the report folder and `$root/eval`.

    It prints the eight PASS or FAIL lines of Always, and each FAIL counts in `fails`.
  - **The key-like scan** of Always: after the copy into `eval/` (the real form), or after the fetch of the on-mock pair. Exit 4 comes after the structural checks: a run with `fails` > 0 exits 1 first.
  - **`--override`:** the reason refusal before Node runs, and the scan after the write.
  - Keep each anchor text that an `rc-flow` bad sample edits, or update the sample writer in `test-eval-set.sh` in the same change.
- `eval/key-proof.sh` (new) -- the harness of Always. Rationale: AC2, Integration.
  - Header: what it proves, its variables (`OCUTALON_RUN_TAG`, and the lane variables passed through), its exit codes, and that it runs in the `evaluation` job.
  - It sources `lib-keys.sh` for `key_value_hits`, and names no container tool.
  - A private work folder from `mktemp -d` below `${RUNNER_TEMP:-${TMPDIR:-/tmp}}` holds the capture, the report folder and a time stamp. An EXIT trap removes it.
- `.github/workflows/lane-a.yml` -- in `evaluation` only, a step after "Run the evaluation set against the CI mock" and before "Tear down": `- name: Prove the model key leaks nowhere (a fake key, on the CI mock)` / `run: bash eval/key-proof.sh`. No other change. Rationale: Integration (per Task 0's rule).

**Tests**
- `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls` -- Rationale: AC1.
  - **New `TestNFR4Maximum`:** the Matrix row (nine at 0.0001 and one at 0.001). Assert: NFR-4 not met and the attempt below; `flagged` holds that one; `maxUSD` .001; `meanUSD` .00019; `gated` `maxUSD`; and `cost.meanUSD` of the set under `FLAGUSD`. Then nine at 0.0001 and one at 0.000999: met.
  - **`TestResult`:** assert every `attentionCost` field.
  - **`TestText`:** assert the three exact lines for `GoodSet`.
  - **`TestNFR4Kinds`:** a diagnose or turn decision does not enter `meanUSD`.
  - Update the header.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` -- `TestAttemptReadsTheReport`: add a second `decide` row at `FLAGUSD`, so that the built set's mean stays under it and NFR-4 is not met with `gated` `maxUSD`. Rationale: AC1 integration (Report to Gate).
- `docker/tests/test-eval-set.sh` -- Each rule keeps the file's convention: synthetic bad samples with `expect.txt`, a good sample, then the real tree. Every key value is built from fragments at run time. Rationale: AC2-AC4, Integration.
  - **`eval-scripts`:** the exact line `. "$root/docker/tests/lib-keys.sh"` is exempt. A bad sample still flags any other code line with "docker", that line included when it is followed by more text.
  - **`job`:** `evaluation` also runs `bash eval/key-proof.sh`, after `bash eval/run.sh` and before the teardown step. A bad sample lacks it.
  - **`rc-guard`:** `--on-mock` with a key goes on to the stub (exit 1). The key appears in no output, call or file.
  - **`rc-stack`:**
    - The rehearsal with a key: the `up` call lists `eval/compose.release-candidate.yml` and, after it, `ci/compose.ci.yml` a second time. `ENV eval=1 key=set`. The first session asks `ReadyReason` and `KeysAre`, and never `PointKeys` or `RestoreKeys`. The key's value is nowhere.
    - **DW-434:** the npm stub records `key=set|unset` for each call. With `LIVE_REBUILD_WEB=1`, and in `--release-candidate` and the rehearsal with a key, there is at least one npm call, and every one is `unset`.
  - **`rc-flow`:**
    - A planted key-like line (fragments) in the stub's result Markdown: exit 4, the do-not-commit FAIL line naming `file:line` and never the text, and the files kept. This holds in the real form (`eval/`) and in `--on-mock` (the report folder).
    - The rehearsal with a key on a stub whose `KeyProof` session, logs and container scan are clean: exit 0, with the eight PASS lines.
    - A stub whose globals line reports one hit: `FAIL key proof globals` and exit 1.
  - **`rc-override`:** the copy tree also holds `docker/tests/lib-keys.sh`. A key-like reason is refused with exit 2 and both files unchanged. A result whose Markdown holds a key-like line: the override writes, then exits 4.
  - **New rule `key-proof`:** `eval/key-proof.sh` runs from a copy tree beside a stub `eval/run.sh` and a stub `ci/iris.sh`, with the stub run's behaviour set per sample.
    - The good stub passes with exit 0.
    - Each bad stub is flagged: it prints the key; writes it below `eval/`; writes it into the report folder; changes `eval/`; exits 1; lacks a `PASS key proof` line; or its teardown prints a leftover volume.
    - With no tag, exit 2 and the stub never ran.
    - The stub records the value it received, and that value is never in the harness's own output.
  - **New rule `key-like`:**
    - `eval/run.sh`, `eval/key-proof.sh` and `docker/tests/test-boundaries.sh` source `docker/tests/lib-keys.sh`.
    - None of those three holds the text `sk-ant-[` (the rule builds that needle from fragments, so the rule's own file does not hold it either).
    - Other epics' scripts that keep a two-shape subset (`test-compose-file.sh` :310, `test-install-script.sh` :856) are out of scope.
    - A bad sample is a `run.sh` that defines its own pattern.
  - Update the header (Story 9.10, the two new rules, and the changed ones).

- [ ] [Gate] `eval/run.sh`: the `--key-path` switch as the lead gate ruling describes (opt-in key path under `--on-mock`; the key unset for the whole run otherwise), `eval/key-proof.sh` passes it, and `rc-stack` pins both forms (veto U-168).

**Acceptance Criteria:**
- **AC1 (U-166 (a)).** Given a release-candidate attempt whose item decisions have a mean under $0.001 and one decision at $0.001 or more, when `Gate.Attempt` evaluates NFR-4, then:
  - NFR-4 is not met, the decision is listed in `flagged`, and the attempt is below target;
  - `release-candidate.json` names `maxUSD` as the gated figure (`summary.attentionCost.gated`), with `meanUSD` in `informationOnly`;
  - `release-candidate.md` says that NFR-4 is judged on the maximum item-decision cost and that the mean is for information only.

  Evidence: `TestNFR4Maximum`, `TestResult`, `TestText` and `TestAttemptReadsTheReport`.
- **AC2 (U-166 (b)).** Given a fake key built at run time from fragments, when `bash eval/key-proof.sh` exports it for `eval/run.sh --release-candidate --on-mock`, then:
  - the run takes the real key path: the override's interpolation, the entries holding the Provider placeholder, and a key of its length on every mock request;
  - every model request goes to the CI mock;
  - the whole string is in no global, store, trace message, container log, container file, run log, report file, file below `eval/`, file of the checkout written during the run, or line of the captured output;
  - after the run, the teardown of its tag finds 0 projects, 0 containers and 0 volumes.

  Evidence: the harness's fresh run (Task 0), the CI step (or the local proof run under Task 0's rule), and the rules `key-proof`, `rc-stack` and `rc-flow`.
- **AC3 (DW-434).** Given a checkout without the web bundle, or `LIVE_REBUILD_WEB=1`, and `ANTHROPIC_API_KEY` set, when `eval/run.sh --release-candidate` builds the bundle before its stack starts, then every npm process runs with the key unset, `live_start` builds nothing more, and the stack's compose calls still have the key. Evidence: `rc-stack`.
- **AC4 (U-166 (c)).** Given `eval/run.sh --release-candidate` (or `--override`) has written the result pair, when it checks the pair before the author commits it, then:
  - it scans both files with `lib-keys.sh`'s `key_like`, the same definition `test-boundaries.sh` sources;
  - on a match it exits 4, keeps the files and tells the author not to commit them, naming `file:line` and never the text;
  - `--override` refuses a key-like reason.

  Evidence: `rc-flow`, `rc-override` and `key-like`, and `test-boundaries.sh`'s keys rules.
- **AC5 (no regression).** Given the push run and the no-key rehearsal, when they run fresh, then their checks pass as in 9.5. The rehearsal adds only its key-like PASS line, and `git status --short eval/` stays empty.
- **Integration (Rule 1).**
  - Given a push, when Lane A's `evaluation` job (the consumer) runs `bash eval/key-proof.sh` after `bash eval/run.sh`, then the step ends with `eval/key-proof: all checks passed` and the job's teardown removes nothing of the proof. This applies unless Task 0's rule made the proof local.
  - Given `docker/tests/test-boundaries.sh` (a consumer of `lib-keys.sh`), when it runs, then its keys rules pass with the shared definition.

## Spec Change Log

- 2026-10-30, lead spec gate: the key-path rehearsal is opt-in (`--key-path`, veto U-168), overriding Decided in-stage 3; without the switch `--on-mock` unsets the key for the whole run. AD-22 text to the orchestrator (DW-431). No intent change.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**

| AD | What it binds here |
|---|---|
| AD-19 | The key comes only from the environment, through the override's interpolation, and is never stored in IRIS or shown. `OCUTALON_MOCK_KEY_HEADER` is set only by `ci/compose.ci.yml`, so the rehearsal layers that file again and adds no new setter. The placeholder resolves only inside AI Hub. |
| AD-22 | The evaluation set and its job. `OCUTALON_EVAL=1` comes only from `eval/run.sh`. No `docker push`, no `compose config` without `--quiet`, no `inspect` without `--format`. The mock logs the key's length only. |
| AD-20 | Decision kinds. NFR-4 covers `decide` decisions (9.5's `NFR4KINDS`, kept under U-166). |
| AD-26 | "The trace" is what Visual Trace shows: message headers and bodies, the event log (`KeyScan.Find`) and the rule log (in the global scan). |
| AD-6 | The rehearsal's requests go through the product's own provider path (the bridge and AI Hub), not a test shortcut. |
| AD-29, AD-33 | Lane A paths and Epic 9's footprint. No new table, item, event or cross-area message. |

No AC contradicts an AD's Rule. No NFR is unmeasurable as worded.

**Decided in-stage:**
1. **(a) is a pin and a wording change, not a rule change.** `CostTarget` already fails on any `decide` decision at or over `FLAGUSD` (:583, :594). Every existing NFR-4 test uses one decision, where the mean is the maximum, so `TestNFR4Maximum` is new. "The report text" is the result's Markdown, `release-candidate.md` (`Gate.Text`). The per-attempt `set-k.md` (`Report.Text`) gates nothing and is unchanged.
2. **The JSON fields are additive within `ocutalon.evalResult/1`,** as condition (a) requires: `gated`, `flagUSD`, `meanUSD`, `met` and `informationOnly`. There is no version bump. Story 11.4's existing fields are unchanged.
3. **The rehearsal is selected by a key in the environment under `--on-mock`,** as the AC's "When" reads (`eval/run.sh --release-candidate --on-mock` "runs with it"). There is no new switch. It is listed for the lead below.
4. **Layering `ci/compose.ci.yml` a second time** is the smallest change that keeps every request on the mock without a new file setting the mock header (pinned by `test-compose-file.sh` :287-291). Task 0 has the fallback.
5. **The fake key has the real key's shape** (`sk-ant-api03-ocutalonfake-` plus 40). Redaction and `KEY_LIKE_ERE` then treat it as the real key; Story 1.1's `KeyScan` already proves a value without that shape is stored nowhere. It is random per run and built from fragments.
6. **The scan scope:**
   - Read-only databases are skipped: they cannot receive the key.
   - The container files add the IRIS logs inside the container (`messages.log`, the after-start log), the journals and the report copies to the AC's container logs.
   - Each scan fails closed and has a positive control (Rule 19).
7. **The harness lives in `eval/`.** That means no `ci/units.sh` edit (`eval/` is already an IRIS input) and no container tool named. `ci/iris.sh teardown` for the run's tag is the removal check: it filters containers and volumes by the tag's project names. The pre-clear makes its zeros the proof's own. The harness uses the job's tag, so the job's own teardown step also covers it.
8. **CI placement: a step of the `evaluation` job** (the lead's preference), unless Task 0's 360 s rule makes the proof local.
9. **DW-434's reading of "only the stack's start sees it".** The npm processes are the only children that run without the key. The stack's compose calls (start, exec, logs, down) keep it, because compose interpolates every file on every call and 9.5's `:?` (kept under U-166) refuses an unset key.
10. **(c):**
    - Exit code 4 keeps 1's meaning ("nothing written in `eval/`").
    - The files are kept, because the AC says to tell the author not to commit them.
    - The rehearsal's pair is scanned too, so CI exercises the scan.
    - `--override` is covered because its output is what gets committed.
11. **The shared file is `docker/tests/lib-keys.sh`.** `IRIS_INPUT` already claims `lib-*.sh`, so a change to it runs every IRIS group (safe; no `ci/units.sh` edit). `eval-scripts` exempts exactly its source line.

**Siblings (Rule 2: extend, don't copy):**
- **`GlobalHits` copies the walk of `Test.Web.SessionEvents.ReferenceHits`** (:590-598, about 8 lines). The sibling is in Epic 29's contended `Test/Web/**`, so it cannot be extended here, and it enumerates one namespace's globals where the proof needs every database by directory. Once Epic 29 has merged, the walk can become one helper. No story owns that yet.
- **The `stores` scan calls `Test.Agent.KeyScan.Find`** and does not copy it.
- **The readiness reuses `RunnerFixture`'s methods** (`ReadyReason`, `WaitRecords`, `KeysAre`).
- **The mock figure reuses `Test.Contract.Mock.LogSince`.**
- **`key_value_hits` is shared** by `eval/run.sh` and `eval/key-proof.sh` through `lib-keys.sh`.
- **`key_proof` reuses** `iris_script`, `check_session`, `dc`, `pass` and `fail`.
- **The `key-proof` rule follows `check_record_guard`'s copy-tree pattern,** and the `rc-*` additions extend their stubs.

**Integration and linkage (Rules 1 and 2).**
- **Consumes:**
  - `Eval.Gate` and `eval/run.sh`'s release-candidate sequence, and `eval/compose.release-candidate.yml` (9.5);
  - `ci/compose.ci.yml`, the mock and its log (0.7, 0.11);
  - `lib-live.sh`'s `live_add_file`, `ensure_web_bundle`, `dc`, `iris_script` and `check_session`;
  - `ci/iris.sh teardown`;
  - `KeyScan.Find` (1.1), `RunnerFixture` (1.2, 1.13) and `Keys.Status`.

  The proof runs against a real throwaway, not a mock of one.
- **Consumed-by:**
  - Lane A's `evaluation` job runs `eval/key-proof.sh` (this story).
  - `docker/tests/test-boundaries.sh` sources `lib-keys.sh` (this story).
  - Story 11.5's release sequence must stop on exit 4 and not commit the pair.
  - Story 11.4's generator can read `summary.attentionCost.maxUSD` as NFR-4's figure.

**Lead gate rulings (2026-10-30, spec gate).**
- **The key-path rehearsal is opt-in (veto window, security posture; inbox U-168), overriding Decided in-stage 3.** `eval/run.sh` gains a switch `--key-path`, accepted only together with `--release-candidate --on-mock` (any other use exits 2 with a usage line). Only `--release-candidate --on-mock --key-path` with a non-empty `ANTHROPIC_API_KEY` takes the release-candidate override's key path (an empty key exits 2, as the real mode does). Without `--key-path`, `--on-mock` runs with `ANTHROPIC_API_KEY` unset for the whole run (`unset` before anything else, so neither compose nor npm nor IRIS ever sees it), whatever the caller's environment holds: exactly 9.5's behaviour, and `rc-stack`'s on-mock pin (no override, key unset) stays true even with a key exported. `eval/key-proof.sh` passes `--key-path`. Pin both: `rc-stack` runs `--on-mock` with a fake key exported and no switch, and asserts no override, key unset in every call; and with the switch, the key path. AC2's "When" reads with the switch; its intent is unchanged.
- The proposed AD-22 as-built text goes to the orchestrator with DW-431 (not written here).
- The fake key, as planned, has the real key's shape; it is built from fragments at run time and never written whole into any committed file (`test-boundaries.sh` scans the repository).

**Veto-window item, for the lead's classification (security posture).** With `--on-mock`, a key in the shell's environment now takes the release-candidate override's path into the throwaway:
- every request goes only to the CI mock, which logs only the key's length;
- an IRIS session of the run reads the key from its own environment to scan for it, and prints counts only.

This is required by U-166 (b). The design choice is that a key in the environment selects it. The alternative is an explicit opt-in switch, so that an author's stray real key never enters an `--on-mock` rehearsal. Reversing the choice is a few lines.

**Ledger inbox.**
- DW-434: addressed by `eval/run.sh`'s DW-434 item (Tasks) and pinned by `rc-stack` (AC3).
- Declined: none.
- DW-386 (`Bridge.Redact`'s patterns) is untouched and stays on the decision sheet.

**Footprint extensions:**
- `docker/tests/test-boundaries.sh` (edited; allowed by the lead);
- `docker/tests/lib-keys.sh` (new, in a folder that is not contended).

No contended path is edited: `lib-live.sh` is read-only here.

**Proposed spine text (for the lead), optional.** The AD-22 as-built bullet goes to the orchestrator with DW-431:
> **The key proof (Story 9.10).** The evaluation job also runs `bash eval/key-proof.sh`: a fake key built at run time goes through `eval/compose.release-candidate.yml` into a `--release-candidate --on-mock` run whose requests reach only the CI mock (`ci/compose.ci.yml` layered again), and the run proves the key in no global, store, trace message, log, container file, output or file under `eval/`, and its throwaway gone. The release-candidate result pair is scanned with the key-like patterns of `docker/tests/lib-keys.sh`, the one definition that `test-boundaries.sh` also reads; a match exits 4.

**CI time (inference until measured).**
- **The `evaluation` job** gains one step: a fresh stack (about 2.5 to 4 min on the runner), three on-mock attempts (about 2 min) and the scans (unknown; Task 0 measures them locally, at about a third of the runner's time). That is about 5 to 9 min, taking the job from about 4.8 to about 10 to 14 min of its 30.
- **The wall clock** does not change: the longest `ci.yml` IRIS group is 25.8 to 32.4 min, and the evaluation job runs beside it.
- **Nothing else changes in CI:** no new job, workflow, trigger or secret, and `ci.yml` is not touched.
- **The hosted `checks` job** gains about 15 s for the new rules.
- **`shards-2`** gains under 3 s (`Test.Eval.KeyProof`).

**Size.** The story carries U-166's three conditions and DW-434 by the orchestrator's split ruling, hence the `multiple-goals` warning. Each part is small except (b).

## Verification

`<B>` stands for:
```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

**Run discipline.**
- Tags: fresh `e9s10i`, warm `e9s10iw`. QA and review use their own stage names and tags.
- Run from the epic-9 worktree root, each command in the foreground of its own call with `timeout: 600000`.
- At most one `iris_execute_tests` call per message (the tests here run through `ci/iris.sh`). Pass `server` and `namespace` on every IRIS MCP call.
- Never set a real `ANTHROPIC_API_KEY`, never read `.env`, and never run `--release-candidate` without `--on-mock`. The only key is the harness's fake one. Run every other command with the key unset (`env -u ANTHROPIC_API_KEY`).

**Runtime targets.**
- Slot B: MCP server `ocutalon-slot-b`, namespace `OCUTALON`, for `iris_server_info` and compile checks only.
- Every test runs on a throwaway through `ci/iris.sh`, `eval/run.sh` or `eval/key-proof.sh` with `<B>`.
- Tear down only `e9s10i` and `e9s10iw`.

**Shared surfaces:**
- `eval/run.sh`: its modes, its exit codes (new 4) and its output lines (the rehearsal's INFO, readiness and `PASS key proof` lines, and the key-like PASS line), asserted by `rc-guard`, `rc-stack`, `rc-flow`, `rc-override`, `run-guard` and the push-run checks.
- `Gate.Text`'s cost lines and `summary.attentionCost`/`targets.nfr4`, asserted by `Test.Eval.Gate`, `Test.Eval.Report` and Story 11.4's reader.
- `test-boundaries.sh`'s `key_like`, now from `lib-keys.sh`.
- The `eval-scripts` and `job` rules.
- `lane-a.yml`'s `evaluation` steps and the job's time.
- The files at the `eval/` root (the new `key-proof.sh`), read by the cases rule and `CaseNames`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-b`. Then load and compile `Eval/Gate.cls`, `Test/Eval/KeyProof.cls`, `Test/Eval/Gate.cls` and `Test/Eval/Report.cls` on slot B, namespace `OCUTALON`. -- expected: build 154, port 1991, and every class compiles.
- (once) `<B> OCUTALON_RUN_TAG=e9s10iw ci/warm.sh up` -- expected: ready.
- (loop) Each in its own call: `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s10iw ci/iris.sh class OcuTalon.Test.Eval.Gate`, then the same for `OcuTalon.Test.Eval.KeyProof`, `OcuTalon.Test.Eval.Report` and `OcuTalon.Test.Bridge.CodeRules`. -- expected: each passed.
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule passes, `key-proof` and `key-like` included (about 50 s).
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: `test-boundaries: all rules passed`.
- (once) `bash docker/tests/test-eval-set.sh` from a scratch copy of the tree without `web/node_modules` and `src/ocutalon/csp/` (the hosted `checks` condition; the copy goes in the stage's own scratch folder, never in the worktree) -- expected:
  - every rule passes;
  - no real npm runs: `run-guard` and `rc-guard` stop at `preflight`, `rc-stack` and `rc-flow` use their npm stubs, and `key-proof` runs a stub `eval/run.sh`.
- (once) Task 0 and the proof: `<B> OCUTALON_RUN_TAG=e9s10i bash eval/key-proof.sh` (fresh) -- expected:
  - the eight `PASS key proof` lines, `VERDICT blocked`, and `eval/key-proof: all checks passed`, exit 0;
  - the teardown line with `0 project(s) removed, 0 leftover container(s), 0 leftover volume(s)`.

  Record Task 0's figures. About 3 to 5 min is expected (inference).
- (once) `<B> OCUTALON_RUN_TAG=e9s10i env -u ANTHROPIC_API_KEY bash eval/run.sh` -- expected: `eval/run: all checks passed` (AC5).
- (once) `<B> OCUTALON_RUN_TAG=e9s10i env -u ANTHROPIC_API_KEY bash eval/run.sh --release-candidate --on-mock` -- expected (AC5):
  - 3 attempts, `VERDICT blocked`, exit 0;
  - the key-like PASS line, and no `key proof` line;
  - `git status --short eval/` empty.
- (once) Use `ci/iris.sh classes lane-a@rest` to find the `--part k/8` parts that hold `Test.Eval.Gate`, `Test.Eval.KeyProof` and `Test.Eval.Report`. Run `<B> OCUTALON_RUN_TAG=e9s10i ci/iris.sh shard lane-a@rest --part k/8` for each, then each again with `--reverse`, one per call. -- expected: every class passes. Record the times.
- (once) `bash ci/checks.sh` -- expected: every block passes (`boundaries`, `eval-set`, `class-rules`, `ci-config`, `compose-file` among them), in about 4 min.
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s10iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s10i ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-b folder.

**Planned mutations (Rule 19).** Apply each mutation, observe the red, then revert. Confirm that `git status --short` and `git diff --stat` are as before, then write the `mutation:` line.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `CostTarget` judges the set's `cost.meanUSD` against `FLAGUSD` instead of each `decide` decision | `TestNFR4Maximum` |
| AC1 | `Summary` drops `gated` | `TestResult` |
| AC1 | `Text` names the mean as the gated figure | `TestText` |
| AC2 (pinning) | The rehearsal's readiness session also runs `Set ^ZzKeyProofLeak=$SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY")` | A fresh `eval/key-proof.sh`: `FAIL key proof globals` (and container files) |
| AC2 | The rehearsal calls `PointKeys` | `rc-stack`, and the fresh proof's `mock log` (`keyLength` 1) |
| AC2 | `eval/run.sh` echoes the key | `key-proof` (the captured output), and `rc-guard` |
| AC2 | `GlobalHits` checks subscripts only | `TestGlobalHits` |
| AC2 | `TraceHits` skips the body | `TestTraceHits` |
| AC2 | The harness accepts any teardown count | `key-proof` (the leftover sample) |
| AC3 | The pre-build keeps the key (no `unset`) | `rc-stack` |
| AC3 | No `LIVE_REBUILD_WEB=0` after the pre-build | `rc-stack` (a second build with the key) |
| AC4 | `eval/run.sh` skips the key-like scan | `rc-flow` (the exit 4 case) |
| AC4 | `lib-keys.sh` drops the `dop_v1_` alternative | `test-boundaries.sh` (the shapes rule) |
| AC4 | `eval/run.sh` holds its own copy of the pattern | `key-like` |
| AC4 | `--override` accepts a key-like reason | `rc-override` |
| Integration | The `evaluation` job loses the proof step | `job` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
