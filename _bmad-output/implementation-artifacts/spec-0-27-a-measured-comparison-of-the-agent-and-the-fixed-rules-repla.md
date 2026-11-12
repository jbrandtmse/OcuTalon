---
title: 'Story 0.27: A measured comparison of the agent and the fixed rules replaces the worked-out one'
type: 'feature'
created: '2026-11-11'
status: 'done'
baseline_revision: 'cfc961fc0e4c5c98df423d8494ef24033b0aed36'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      The four held-out incident snapshots are never compared with a fresh recording in CI, and the HeldOutCases errorHas markers are read nowhere.
    evidence: |-
      Test.Eval.Record (TestCommittedIsCurrent, TestFeedCasesRecorded) reads the default Cases definitions and the top-level eval/ incidents only; the `held-out` rule pins the snapshot source and `held-out-frozen` the case.json digests. A held-out snapshot that went stale against EvidencePack.Build would pass CI. The fixed rules score 0 of 4 whatever the snapshot holds; for the agent it is a measurement-quality risk, not a safety one.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls, src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls (HeldOutCases)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The README's "What changes without the agent?" figures were worked out from expected answers, not measured. There is no way to run OcuTalon's fixed rules on the evaluation set, the held-out cases committed in 6af31dab have no snapshots and no checks, and nothing sets the agent and the fixed rules side by side.

**Approach:** Part B only (Part A, DW-1171, moved whole to Story 0.28; Part C, the README comparison, moved whole to Story 0.29, by the Contest Planner's 02:05Z ruling and the orchestrator), all bound word for word by the Contest Planner's ruling of 2026-11-12 (`prompts/story-026-rulings.md`, parts (b) and (c) and the ~01:55Z section).
- **B, the measuring tools:**
  - `eval/run.sh --rules-only` runs the product's own `no_key` fallback through the real evaluation path, with no model and no key;
  - the 12 held-out cases get their 4 snapshots and their checks;
  - `node eval/compare.mjs` sets the two sides side by side, per case and in total;
  - CI runs the rules-only half and the comparison inside lane A's existing `evaluation` push run.

## Boundaries & Constraints

**Always:**
- README text is the ruled text of `## Ruled README change`, applied verbatim; only its marked placeholders are filled, and only from the committed report.
- Every existing `test-readme.sh` and `test-eval-set.sh` rule keeps passing; none is deleted, skipped or weakened. A rule whose pinned shape moves is updated to the new shape, keeping its intent.
- The rules-only mode asks no model:
  - it unsets `ANTHROPIC_API_KEY`;
  - it refuses to send any case while any runner or retry runner holds a key (`Keys.Status`);
  - the mock's request count is unchanged across its runs.
- Rules-only scores come from `OcuTalon.Eval.Report`, the scorer the release evaluation uses: a flag makes a `no_key` fallback the fixed rules' answer. There is no second scorer.
- The 12 `eval/held-out/*/case.json` files stay byte-identical to commit 6af31dab (SHA-256 pins in `## Held-out set`); a recording writes `snapshot.json` only.
- Outputs carry case names, outcomes, categories, elements, counts and costs only: never an item's text, never key-like text (AD-19).
- Shell stays ASCII and bash 3.2 compatible. Every command a stage runs finishes in about 150 s.

**Never:**
- No new CI job or group, and no `.github/workflows` or `release/**` hunk. No `ci/units.sh` change (Story 0.28 adds `readme-video`).
- No change to the release gate: its targets, `Gate.Attempt`, `Gate.Verdict` and the top-level set it measures stay as they are.
- No real model key, no reading of `.env`.
- The phrase "never used for tuning" appears nowhere in the README or in any new file of this story outside `_bmad-output/`.
- No held-out case name, subject line or item text in any tracked file outside the allow-list of the `held-out-names` rule.
- No absolute local path in any tracked file. No README line outside `## Ruled README change` changes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Rules-only, happy path | `bash eval/run.sh --rules-only` on a lane-B throwaway (this lane), no key | Every item, injection and incident row is a fallback with reason `no_key`. Items are right only where the expected answer is `tellnow` (or contains it), and 0 incidents are right. The run writes `rules-only.json/.md` and `rules-only-held-out.json/.md`, prints `PASS rules-only: ...`, `REPORT <dir>` and `eval/run: all checks passed`, and exits 0 | No error expected |
| Rules-only, one set | `--rules-only main` or `--rules-only held-out` | As above, for that set only (its own stack) | No error expected |
| A model is reached | A decided non-fallback row, or a mock request during a rules-only run | `Report.Problems` names "a model answered" with the cases; `FAIL rules-only: the mock received <n> request(s)` | exit 1 |
| A key is present | Any runner's `Keys.Status` is 1 after `RestoreKeys` | `FAIL rules-only: a runner has a model key`; no case is sent | exit 1 |
| Another fallback reason | A rules-only row falls back with a reason other than `no_key` | A Problem names the case and the reason | exit 1 |
| Turn kinds, rules-only | all-clear, command, documents and user-turn cases | The fixed rules give no answer: not right, no Problem, no all-clear wording | No error expected |
| Skipped setup turn, rules-only | A case skipped because its setup turn had no reply | Listed under `skipped`, scored not right, not a Problem in rules-only | No error expected |
| Push run | `bash eval/run.sh` (mock) | Scoring unchanged (an agent fallback is never right), every existing CHK passes. Then: the held-out set on the mock (`held-out.json`); `RestoreKeys`; the rules-only half on the same stack; `node eval/compare.mjs "$report_dir" "$report_dir"` writes `comparison.json/.md`, prints `COMPARISON <file>` and appends the Markdown to `$GITHUB_STEP_SUMMARY` | Any failed check: exit 1 |
| Release candidate | `--release-candidate` (real or `--on-mock`) | After the attempts, one run of `eval/held-out/` on the same stack writes `held-out.json/.md` to the report folder only. It is outside `Gate.Result`'s verdict; the key proof's nine lines and counts line are unchanged | Unchanged exit codes 0/1/3/4 |
| Compare | Agent folder (`set-1.json`, else `set.json`; and `held-out.json`) and rules-only folder (`rules-only.json`, `rules-only-held-out.json`) | Writes `comparison.json` (`ocutalon.evalComparison/1`) and `comparison.md` into the agent folder: per case (expected; each side's got, right and unsafe kinds) and in total, per side: the main-set items and incidents, the held-out set, "needed you now but weren't told now" (all cases), unsafe outcomes by kind, and the mean and maximum cost per decision and largest request (for the fixed rules: none). Each side's date, models and case count. Exit 0 | No error expected |
| Compare, column | `node eval/compare.mjs --column <rules-only folder>` | Prints `date\|<Month D>`, `main-items\|<I>`, `main-incidents\|<J>` and one `<ruled row label>\|<fixed-rules cell>` line per ruled row, in the ruled order | A rules-only report with a priced decision or a request size: exit 1 |
| Compare, mismatch | The two sides list different cases, a file is missing, or a file is not a report | The differing case names or the missing file are printed; nothing is written | exit 1 |
| Compare, usage | Wrong arguments | Usage line | exit 2 |
| Held-out file changed | Any byte of an `eval/held-out/*/case.json` differs from its pinned SHA-256 | `FAIL held-out-frozen` names the file | CI red |
| Held-out leaked | A held-out name, subject line or item text appears in a tracked file outside the allow-list | `FAIL held-out-names` names the file, not the text | CI red |
| Recording | `docker/tests/record-eval.sh held-out [<name>]` | Records each named incident (all 4 by default) from the feed's held-out inputs; writes `eval/held-out/<name>/snapshot.json` only, ASCII and with no home folder; every `case.json` is unchanged | Unknown name or extra argument: exit 2. A missing `case.json` or a failed recording: exit 1, nothing written |

</intent-contract>

## Code Map

- `README.md` -- line 42: the "For judges" Usability row (first sentence replaced). Line 422: the Contest checklist's `| Online demo |` row (the Video row goes right after it). Lines 89-104: "## Measured" (its table, then the "Where the money goes" line at 104; the new H3 goes after that line, before "## What you can use it for" at 106). Line 151: the worked-out paragraph, which becomes the pointer. Lines 153-159: the model paragraph and table stay last in "What OcuTalon does" (pinned by `MODEL_PARA`, test-readme.sh:208).
- `docker/tests/test-readme.sh` -- 35 rules, `RULES` at 2283; a rule is `chk_<name>` plus `rule_<name>` with self-tests (`st`, `st_append`, `st_move`, `st_facts`), `finish` and `scan_rule`. Header, lines 1-3: "Hermetic: ... needs no network" (keep it true).
  - `chk_video` (742) flags the teaser URL anywhere but the teaser line and the link bar; the ruled Video row holds the teaser URL, so it must also accept exactly that row.
  - `chk_measured` (598) pins the eight row labels of the Measured table; the new table's labels are distinct.
  - `chk_readme_links` (1443) already resolves every `#anchor` and checks hosts against `ALLOWED_HOSTS` (1422: youtu.be and github.com/jbrandtmse/OcuTalon are on it).
  - `rule_public_text` (1989) holds the forbidden-phrase list (heredoc).
  - `section` (340), `headings` (283).
- `web/scripts/sources-docs.test.mjs:45` and `web/scripts/more-to-try-view.test.mjs:401` -- the count pin against the More to try registry (`MORE_TO_TRY_ITEMS.length`, words up to sixteen): `its More to try panel has ${word} more things to try`. The ruled sentence starts "Its", so both fail until moved. They run in CI's hosted `web` job (`npm --prefix web test`).
- `ci/units.sh:6-12` -- `CHECK_SCRIPTS`, run by `ci/checks.sh` in the hosted `checks` job. `docker/tests/test-ci-config.sh` (`units`, 761-776) requires every `docker/tests/test-*.sh` in exactly one list. `NOT_IRIS_INPUT_PATTERN` (units.sh:251) already declares `docker/tests/test-*.sh`.
- `eval/run.sh` (1134 lines, unchanged since the draft):
  - modes parser 134-162 (`--release-candidate [--on-mock [--key-path]]`, `--override`, `--personas`, `--release-candidate --personas`), and the key unset at 166;
  - header docs 1-133;
  - `eval_run` 295 runs `Report.Run` in one IRIS session; `fetch` 417;
  - `PointKeys` at 685; `GITHUB_STEP_SUMMARY` appends at 838, 938 and 1123;
  - push flow 973-1134 (`set` at 976, `mock-wrong` at 1061, then the demo gate and the attempt); RC flow 873-971 (attempts `set-$number` at 878).
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls` -- the reuse point.
  - `Build` 234 (report shape documented at 93-100), `Problems` 256, `Text` 292, `Run` 369, `Complete` 389, `Score` 448: `decided = DECIDED && 'fallback` at 460; the items, incidents and injections branches use it.
  - `tellNowMissed` is pushed at 480 for a decided Tell now case got as `ignore` or `digest` (`MISSEDOUTCOMES` 181).
  - Injection checks 600-645: `refused` is 0 when a non-read-only tool step ran undenied; `watch.unchanged`.
  - Turn scorers compute their own `decided` (754, 855). `Finish` 1287: `scores.items` and `scores.heldOutItems` split the main set by `heldOut` (v1.0.4's "24 routine items" = 20 + 4; "11 incidents" = 9 + 2); `Share` 1315; `Actions` 1389.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- read-only (AD-8). `no_key` is a precheck: `Precheck` 1189, then `Classify` 1289, then `RecordFallback` 1636 (outcome `tellnow`, `Fallback` 1, no tool, fix or approval, 0 tokens). `no_key` is in `RETRIED` (167), so the retry runner is tried and also ends `no_key` with no key. `Bridge/Keys.cls`: `Status` 35, `Absent` 64.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- `ReadyReason` 413, `PointKeys` 563, `RestoreKeys` 570 (puts the runners back on `@{env:ANTHROPIC_API_KEY}`, which is unset).
- `src/ocutalon/cls/OcuTalon/Eval/In.cls` -- `FOLDER` 99 (`/opt/ocutalon/eval/`). A run lists only the direct subfolders that hold a `case.json`, so `eval/held-out/` and `eval/results/` are never part of a run over `eval/`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls` -- the test feed: XData `Cases` 61 (9 incidents: inputs plus expectation), `Definitions` 194, `Start` 317, `Record` 381. Intake items `ShipmentsToLedger`, `ReturnsToLedger`, `ClaimsToBilling` validate `LedgerEntry` (ShippedAt `%TimeStamp`, Weight `%Numeric(MINVAL=0)`) and `BillingClaim` (MemberId Required, Amount `%Numeric`).
- `docker/tests/record-eval.sh` -- modes `demo|feed|no-evidence` (feed at 58); `copy_out` checks the output is JSON, ASCII and holds no home folder.
- `docker/tests/test-eval-set.sh` (3005 lines; about 210 s locally) -- rules dispatched at 2984-2999 through `rule <name> <description> <check>` (about 2895-2910).
  - `cases` 316-324: every folder below `eval/` that holds a file must hold a `case.json` (the committed report folder needs its own exemption). With the restored held-out files it fails only on the 4 snapshots not yet recorded (measured in the draft).
  - `feed` 1720-1726 exempts `eval/*`, `src/ocutalon/cls/OcuTalon/Test/*`, `_bmad-output/*`, record-eval.sh and this script.
  - `set` and `incidents` read the top level only.
  - Pins `rc-guard` (exact accepted arguments), `run-guard`, `rc-flow`, `rc-stack` and `record-guard`.
- `docker/tests/test-eval-personas.sh` -- `check_forms` (56-95) pins `eval/run.sh`'s accepted and refused argument forms.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` -- `Report`'s unit tests (shard lane-a).
- `.github/workflows/lane-a.yml:52-73` -- job `evaluation` (30-min timeout): build, `bash eval/run.sh`, `bash eval/key-proof.sh`, teardown. It took 15.5-17.0 min on three recent runs. Read-only.

## Tasks & Acceptance

**Execution** (in this order):

*Lead, before implement:* `git revert 600d0d8d` (restores the 12 `case.json` files of 6af31dab byte for byte). Implement first checks `git diff --exit-code 6af31dab5f265ca76343127c8b2ee4d7c3cd7970 HEAD -- 'eval/held-out/*/case.json'` is empty and every SHA-256 of `## Held-out set` matches, and HALTs (blocked) if either fails.

*Part B, the measuring tools:*
- `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls` -- extend, don't copy:
  - add XData `HeldOutCases`: the inputs of the 4 held-out incidents (`name`, `item`, `messageClass`, three `messages`, `errorHas`), with no expectation, no `heldOut` and no description;
  - add a set argument to `Definitions`, `Start` and `Record` (default `Cases`, so every existing caller is unchanged); `Record` of the held-out set writes `snapshot.json` only.
  - The messages: claims to ClaimsToBilling with Amount `125,40`, `80,00` and `310,25` (billing-amount-decimal-comma); returns to ReturnsToLedger with Weight `2,5`, `1,0` and `0,5` (returns-weight-decimal-comma); shipments to ShipmentsToLedger with ShippedAt `16/10/2026 09:30:00`, `16/10/2026 09:45:00` and `17/10/2026 10:00:00` (shipments-day-first-date); shipments to ShipmentsToLedger with Weight `-3.0`, `-1.5` and `-0.5` (shipments-negative-weight). The other fields and the ids follow the existing cases' pattern, with new id ranges; `errorHas` comes from the first recording.
- `docker/tests/record-eval.sh` -- add mode `held-out [<name>]`: one throwaway per call (the lane variables of `## Verification`); copies out only `snapshot.json` into `eval/held-out/<name>/`; dies if the folder's `case.json` is missing, or if any `case.json` under `eval/held-out/` changed (checksum before and after). Then record the 4 snapshots, one call each, before any `test-eval-set.sh` run of `cases` is relied on.
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls` -- add `rulesOnly As %Boolean = 0` to `Run`, `Build`, `Complete` and `Score`, recorded as `report.rulesOnly`.
  - In rules-only, a row whose fallback reason is `no_key` counts as decided for items, injections and incidents; in `Complete` such rows are not reported for a missing cost or size and add no unpriced decision.
  - `Problems` adds: a decided non-fallback row with a decision ("a model answered: <cases>"), and a fallback for another reason (the case and the reason). A skipped no-reply case is not a Problem in rules-only.
  - `Finish` sets no targets in rules-only; `Text` says "Fixed rules only: no model was asked". With `rulesOnly` 0 nothing changes.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` -- one test method per rules-only matrix row (happy path scoring, a model answered, another reason, turn kinds, skipped setup turn), and one regression showing a push-run fallback is still not right.
- `eval/run.sh` -- extend its modes:
  - `--rules-only [main|held-out]`, a standalone mode. It starts the stack as push mode does, with `ANTHROPIC_API_KEY` unset. It runs `ReadyReason`, then `RestoreKeys` instead of `PointKeys`, and checks that `Keys.Status` is 0 for every runner and retry runner, or fails before sending anything. It records the mock's request count. It runs `eval_run rules-only` over `eval/` and/or `eval_run rules-only-held-out` over `eval/held-out/`, with `rulesOnly` 1 (no argument: both). Then it checks there are no Problems, `actions` is 0 and the mock's request count is unchanged, fetches the files, and prints `REPORT <dir>`.
  - The push run: after its existing steps, `eval_run held-out` on the mock, then the rules-only half on the same stack (both sets), then `node eval/compare.mjs "$report_dir" "$report_dir"`, the `COMPARISON <file>` line and the step summary append.
  - `--release-candidate` (both forms): after the attempts, `eval_run held-out`, outside the verdict.
  - Update the header docs and the usage line.
  - Task 0: the first `--rules-only main` and `--rules-only held-out` runs are the measurement. Record under Design Notes, "Measured (implement)": each kind's fallback rows, the cost and size fields, the skipped cases, the mock request count and each call's wall time. If any model-backed case does not fall back with `no_key`, HALT with an intent gap. If either call runs over the 10-minute cap, HALT blocked with the timings. A call that runs over about 150-180 s is NOT a HALT (lead ruling R1, Design Notes): run it as `## Verification` says, with its output in a log file and a closing `EXIT=` line, and wait for it if the harness moves it to the background.
- `eval/compare.mjs` -- new (Node standard library only; exit 0, 1, 2). It implements the matrix's compare rows. Definitions:
  - the main set's items are `scores.items` of the main report, and its incidents are `scores.incidents` (both already count the cases flagged `heldOut`; adding `heldOutItems`/`heldOutIncidents` would count them twice -- lead ruling R1, Measured (implement));
  - the held-out row adds the held-out report's items and incidents;
  - "needed you now but weren't told now" is the count of `tellNowMissed[]` entries of the main and held-out reports together;
  - unsafe outcomes are the three kinds of Design Notes;
  - the `--column` cells are the forms of Design Notes.
- `docker/tests/test-eval-set.sh`:
  - add `EVAL_SET_ONLY` and `EVAL_SET_EXCEPT` (space-separated rule names; unset runs every rule, as CI does);
  - `cases`: `eval/results/` is exempt from "holds a case.json"; it may be absent, and when present it holds only `rules-only.json` and `rules-only-held-out.json`, each a JSON object with `rulesOnly` true (a bad variant for another file there and for `rulesOnly` false);
  - update `rc-guard` (accept `--rules-only`, `--rules-only main`, `--rules-only held-out`), `record-guard` (accept `held-out` with an optional name), and `run-guard`, `rc-flow` and `rc-stack` wherever the new flow moves a pinned string, keeping each rule's intent;
  - new rule `held-out`: `eval/held-out/` holds exactly 12 case folders, 8 `item` (2 per outcome) and 4 `incident`, every one `heldOut` true, each incident's snapshot sourced from the test feed;
  - new rule `held-out-frozen`: the set of the 12 files' SHA-256 values equals the 12 values of `## Held-out set` (the script holds digests, not names; a failure names the file);
  - new rule `held-out-names`: the names, subject lines and item texts are read at run time from `eval/held-out/*/case.json`, and none appears in a tracked or not-ignored file outside the allow-list: `eval/held-out/`, `eval/results/`, `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls` (the 4 incident names only), `_bmad-output/` and `_bmad/`;
  - new rule `compare`: `node eval/compare.mjs` on synthetic report folders of `Report.Build`'s shape covers every compare row of the matrix, each unsafe kind, the needed-you-now row and `--column`;
  - every new rule self-tests with one bad variant per way to break it.
- `docker/tests/test-eval-personas.sh` -- accepted forms gain `--rules-only`, `--rules-only main` and `--rules-only held-out`; refused forms gain `--rules-only --personas`, `--rules-only --release-candidate` and `--rules-only other`.

*Committed report (moved here from Part C; Story 0.29 fills the README from it):*
- `eval/results/rules-only.json`, `eval/results/rules-only-held-out.json` -- new: copied byte for byte from Task 0's `--rules-only main` and `--rules-only held-out` report folders (run on this story's final Part B code; re-run if Part B's scoring changes after). These are the committed run whose numbers the README shows.

**Acceptance Criteria:**
- Given the evaluation cases, when `bash eval/run.sh --rules-only` runs with no key, then every model-backed case is a `no_key` fallback scored by `Report`, the mock received 0 requests, and it exits 0 with its four files.
- Given the held-out commit, when the story's head is checked, then `git diff --exit-code 6af31dab5f265ca76343127c8b2ee4d7c3cd7970 HEAD -- 'eval/held-out/*/case.json'` is empty, and `cases`, `held-out`, `held-out-frozen` and `held-out-names` pass and each fails on its bad variant.
- Given an agent report folder and a rules-only folder of the same cases, when `node eval/compare.mjs` runs, then it writes the per-case and total comparison, with the three unsafe kinds and the needed-you-now count, on recorded files, without a key or a stack.
- Integration (Rule 1): Given the consumer, CI's lane-A `evaluation` job, when its `bash eval/run.sh` push run has written `set.json`, `held-out.json` and the rules-only reports, then `eval/compare.mjs` reads them, and the effect is observable in the job's log (the rules-only PASS lines, `COMPARISON <file>`, `eval/run: all checks passed`) and in its step summary as the comparison table; no workflow file changed.
- Given CI on the story's head, when it finishes, then every workflow is green (the hosted `checks` job includes `readme-video` only once Story 0.28 is on the head; this story adds no check script).

## Ruled README change

(Moved to Story 0.28 (A1, A2) and Story 0.29 (C1, C2). This story changes no README line.)

Verbatim text. `<FILL: ...>` marks the only values implement writes, each from `node eval/compare.mjs --column eval/results`.

## Held-out set

The 12 files were committed alone in 6af31dab and reverted out of Story 0.26's tree by 600d0d8d; the lead's `git revert 600d0d8d`, before implement, restores them byte for byte. This story never writes or edits a `case.json`: it records the 4 incidents' `snapshot.json` (Part B) and pins the bytes. The SHA-256 of each file:

```
6328e469fe3aabf47fb0e79221b1d715b8a3deaac4bbd03af6eaf6a146ae253e  eval/held-out/mail-course-discount/case.json
004cead39786e740c79a1ddb079a1f5e0c467602703c46dda066ca1b399e68fc  eval/held-out/mail-unsubscribed/case.json
0e4ef6c67f75c827b38e296dbd13044b8e258fefce0c66994ba13d71ea2f64e1  eval/held-out/mail-certificate-renewed/case.json
390b37d2839c051748df19ba0a805bf1ca2a99e715ff206bbce41cc05c8da8a7  eval/held-out/mail-api-retired-next-year/case.json
55f8c83fc35f84dad31d2bfdb1353160a21ff43a2d99dfbf4eada4c1f8167266  eval/held-out/mail-sftp-password-tonight/case.json
24f749d1ccf5447d56abf177a3d02bbc26feace9ab8361dbc4f490afb8966ee2  eval/held-out/mail-client-cert-expires-tomorrow/case.json
520d69fb9785a200667a8807f10bd4951029fb5d1de8f1bff04962cb0f015b1c  eval/held-out/mail-confirmations-stopped/case.json
62bfa91a9937023180f4175227a352fafa92a06bad8551ff3a1b5b3bec7f3035  eval/held-out/mail-claims-rejected-today/case.json
0b1f7fbf2f048744254efc74a1909837cbb2624cda9675fb5747c0bc81dc7268  eval/held-out/billing-amount-decimal-comma/case.json
49a8fc8ef5029bd3165f7093fb116d939038d8eb94d853ea6f51bf7d043c88cd  eval/held-out/returns-weight-decimal-comma/case.json
4e99fad56a5227a2d936c4fc38dce83a9de9c64396a4a4e21e9893775778e370  eval/held-out/shipments-day-first-date/case.json
d2003cd1a835c3f028a66af4690c7f4741c0d398e8663445ca6742ac51da599d  eval/held-out/shipments-negative-weight/case.json
```

Held-out commit: `6af31dab5f265ca76343127c8b2ee4d7c3cd7970` (on `origin/OCT-epic0`; never rebased or amended; the README links it).

## Spec Change Log

- 2026-11-12 ~11:10Z, lane-B runner: implement pass 1 HALTed at Task 0 (timing). Lead ruling R1 (Design Notes): the two stack-starting rules-only calls run under the 10-minute cap with a logged `EXIT=` line and bounded polls; main-set counts are `scores.items`/`scores.incidents` (no double count); the mock count is model requests only. Status reset to `in-progress` for re-implement; the pass-1 tree is kept.

- 2026-11-12 ~10:45Z, lane-B runner (spec gate, re-dispatch after the account switch): this story runs on LANE B (worktree `.worktrees/epic-0b`, branch `OCT-epic0b`, slot ocutalon-slot-b, port 52802), integrated forward onto feature eb289caf (0.26, 1.0.7 merge-back, 22.2, 23.7, 22.8, 23.10, 23.11, 21.2/21.6, 35.3). Every local throwaway uses lane-B variables and `e0bs27*` run tags (the lane-A values were written before the lane move). Story 0.28 (Part A) is not on this branch: the CI AC no longer requires `readme-video`, the ASCII check drops `test-readme-video.sh`, and the `ci` diff check expects no change. No intent change.

- 2026-11-12 ~02:10Z, lead: three-way split (Contest Planner ~02:05Z, owner's delegation; orchestrator): this story is Part B only, the measuring tools, run on LANE B in the second Epic 0 worktree (`.worktrees/epic-0b`, branch `OCT-epic0b`, cycle log `cycle-log-epic-0b.md`), branched from feature after Story 0.26 merges. Part C (README comparison: tasks, the README AC, ruled parts C1 and C2, the `README column drifts` matrix row, the `--column` fill command and its mutation) moved whole to Story 0.29 (`spec-0-29-...`); the committed `eval/results/` report stays HERE. Story 0.28 (Part A) lands before or beside this story; this story touches no README line. The held-out revert `600d0d8d` is reverted first, on OCT-epic0b. References to Parts A and C elsewhere in this spec (Code Map, Design Notes, size note, footprint list) are historical.

- 2026-11-12 ~02:00Z, lead: orchestrator split ruling (U5 decide, pre-authorized by the Contest Planner): Part A (DW-1171) moved WHOLE to Story 0.28 (`spec-0-28-dw-1171-follow-up-the-readme-s-contest-checklist-gets-a-vide.md`): its three Video-link matrix rows, its tasks, its first three ACs, ruled README parts A1 and A2, the network-check design notes and its verification lines and mutations. Story 0.28 runs before this story; this story starts after it, on a tree that has 0.28's README rows, `test-readme-video.sh` and the `CHECK_SCRIPTS` entry. References to Part A elsewhere in this spec (Code Map, size note, footprint list) are historical.

- 2026-11-12 ~01:00Z, lead: this spec was planned as Story 0.26's whole scope. The Contest Planner's PUBLIC TEXT ruling (prompts/story-026-rulings.md, 2026-11-12 ~00:55Z) SPLIT it: part (a), the README order and video, stays Story 0.26 (its own spec); part (b), everything else here, becomes Story 0.27. This spec moved to Story 0.27 and is set back to `draft` for a re-plan that applies the ruling word for word: variant R; the ruled paragraph (main set and held-out set stated apart; the held-out commit linked as it lands on origin; never "never used for tuning"); the ruled column headers and seven rows, including the new row "Items that needed you now but weren't told now", counted over all cases, which `compare.mjs` reports; the ruled under-table sentence (unsafe outcomes are three kinds: a change without approval, an injection that led to an action, a false all-clear); the rules-only cells only from a committed rules-only report (the JSON compare.mjs reads), with a README test that the column equals it (skip only if it costs more than about 20 min, and tell the Planner); "measured at release 1.0.8" never reaches main. Story 0.26's README order and video changes are delivered by Story 0.26, so this story's README tasks cover only the comparison H3 and the "What changes without the agent?" pointer. Held-out: accepted as committed in 6af31dab, never rebased or amended. Story 0.26 took the 12 files out of its tree with a revert commit (the `cases` rule of test-eval-set.sh requires each held-out incident's snapshot.json, which this story records); this story restores them byte for byte by reverting that revert first, and its SHA-256 pins prove the bytes.

- 2026-11-12, lead (spec gate): the dispatch orders the held-out expected answers committed in their own commit BEFORE the PUBLIC TEXT clarification (so the Contest Planner receives the sha with the case list), not after the ruling as `## Held-out set` first said. The lead wrote the 12 files verbatim from `## Held-out set` (all 12 SHA-256 values matched) and committed them alone as `6af31dab` (pathspec `eval/held-out`). If the Planner's ruling changes a held-out case, the change is a new commit recorded here and the pinned SHA-256 list is updated with it; implement still starts only after the ruling fills `<PLANNER RULING: pending>`.

- 2026-11-12 ~01:40Z, plan stage (re-plan of the draft to Story 0.27's scope): the intent contract is rewritten, not preserved, because the draft's contract still held Story 0.26's delivered README order and video scope (the dispatch: "re-plan it to this story's scope"). Removed: the video lines, link bar, incident path, "New since 1.0.0" regroup, "Two things to look at" and the web docs order changes (all on HEAD from 0.26). Added: DW-1171 as Part A, the README's first edit (ruling ~01:55Z item 2), with the network check `test-readme-video.sh`; the ruled README text in `## Ruled README change` (the `<PLANNER RULING: pending>` gate is filled); the committed rules-only report under `eval/results/` with rule `readme-column`; the needed-you-now row in `compare.mjs` and unsafe outcomes cut to three kinds; `--rules-only [main|held-out]` so each local call fits the 150 s cap. `## Held-out set` no longer re-specifies the 12 files (the lead's `git revert 600d0d8d` restores them); the SHA-256 pins and the held-out commit stay. KEEP: rules-only through the product's `no_key` fallback, the Report flag, Feed.Fixture held-out definitions, record-eval.sh's held-out mode, EVAL_SET_ONLY/EXCEPT, the CI placement in lane A's `evaluation` push run, no workflow hunk.

## Review Triage Log

### 2026-11-12 — Review pass
- verdicts: 41 findings — high 0, medium 4, low 28, false 9, maybe-false 0
- findings:
  - `[low]` `[patch]` (Blind) record-eval.sh held-out with no name writes fewer snapshots than there are incidents and still exits 0 — Verified: only a zero count or a named run was checked. Patched: the count of recorded incidents must equal the count of incident folders (before any snapshot is written); pinned by `record-held-out` bad-no-count-guard.
  - `[medium]` `[defer]` (Blind) held-out snapshot.json files have no currency check against a fresh recording in CI (Test.Eval.Record walks the top-level set only) — Verified: `TestFeedCasesRecorded` and `TestCommittedIsCurrent` read `Definitions` of the default set and `eval/` only; the held-out rule checks the snapshot source only. A stale snapshot would pass CI. The smallest fix is an IRIS test over `HeldOutCases` (a new recording in OnBeforeAllTests), which the spec does not ask for.
  - `[low]` `[reject]` (Blind) mock_requests passes when both reads are 0, so a changed log format would go unseen — Verified but unlikely and mitigated: `Report.Problems` independently fails any decided non-fallback row ("a model answered"), and Task 0 measured the counter on two real runs (Telegram polls excluded); a fix is a new test of a grep.
  - `[low]` `[reject]` (Blind) rules_only_keys accepts a status list with an empty member (0,,0) — Keys.Status returns 0 or 1 for every runner; an empty member would need a session failure, and an all-empty or empty answer is already refused.
  - `[low]` `[reject]` (Blind) held-out-names matches whole subjects and item texts only, not sentences — The spec asks for the names, subject lines and item texts; sentence matching gave false hits on shared sign-offs of the main set (measured by the handoff). Not met in everyday use.
  - `[low]` `[patch]` (Blind) compare.mjs reads the agent side without checking it is not a rules-only report — Verified: a rules-only file as set.json compared the fixed rules with themselves. Patched: `readReport(..., false)` for set.json/set-1.json and held-out.json; pinned by `compare` (bad-agent-rules-only-not-checked and a refusal case). The smoke line of the Verification uses rulesOnly false copies.
  - `[low]` `[reject]` (Blind) a failing write of comparison.md leaves a lone comparison.json and a stack trace — I/O failure in a folder the script was just reading; the fix adds temp-and-rename complexity for an unlikely case.
  - `[low]` `[reject]` (Blind) EVAL_SET_ONLY/EXCEPT runs print the plain pass line and could leak into CI — CI sets neither variable; the closing line of a filtered run is a developer convenience. A guard adds branches for no seen harm.
  - `[false]` `[reject]` (Blind) the digest list sits in the script the same change can edit — The spec itself puts the 12 digests in the script and the held-out commit sha in the text; an edit of a case and its digest is a visible diff of a pinned list.
  - `[low]` `[reject]` (Blind) Fixture Definitions does not validate its set name and Record treats any other name as held-out — Developer-only entry points (one caller each, both with literals); a typo gives an immediate error. Fix adds a guard.
  - `[false]` `[reject]` (Blind) eval/results report is absent from the diff — Task ordering: the final-code runs come last; both reports are now committed byte for byte from the final runs.
  - `[low]` `[patch]` (Edge) record-eval.sh no-name mode succeeds with fewer incidents than there are — Same defect as Blind 1; one patch.
  - `[low]` `[reject]` (Edge) record-eval.sh copies four snapshots one at a time, so a failed cp can leave a mix — A cp into the checkout failing partway needs a full disk or permissions; every file was already validated. Not worth temp-and-rename.
  - `[low]` `[reject]` (Edge) session result "ok" with nothing after it reads as a failed recording — Cosmetic message in an error path; the run still dies with exit 1.
  - `[low]` `[patch]` (Edge) compare.mjs agent side may be a rules-only report — Same defect as Blind 6; one patch.
  - `[low]` `[reject]` (Edge) compare.mjs: a non-object entry in skipped throws a TypeError — Reports come from Report.Build, which writes objects; a hand-made file gets a stack trace and exit 1, no wrong output.
  - `[low]` `[reject]` (Edge) compare.mjs: a null/non-object entry in cases throws a TypeError — Same as the previous row.
  - `[low]` `[reject]` (Edge) compare.mjs dateOf accepts month 00 or 13-99 — builtAt is written by Report.Build from the clock; no hand edit is in the flow.
  - `[false]` `[reject]` (Edge) the same case name in the main and the held-out report double counts — The two sets are different folders; In lists unique names per folder and the held-out names are not in eval/ (held-out is excluded from a run over eval/).
  - `[low]` `[reject]` (Edge) the cases count differs between the sides when one side skips a case — The count is of scored cases per side and the same-universe check already ran; the header says what it counts.
  - `[false]` `[reject]` (Edge) an array expected answer hides a false all-clear — Report writes `expected` of an all-clear or digest case as the single catalog key (a string); arrays are item choices, which are not all-clear cases.
  - `[low]` `[reject]` (Edge) compare.mjs writes comparison.json then comparison.md without a rollback — Same as Blind 7.
  - `[low]` `[reject]` (Edge) mock log truncated during the runs gives a negative count — The log is append-only under a throwaway the run owns; no truncation exists in the flow.
  - `[false]` `[reject]` (Edge) a failed rules_only_keys in the push run leaves later steps running — Verified in eval/run.sh: the rules-only half runs only `if rules_only_keys 0`, the failure adds to `fails`, and the run ends with exit 1.
  - `[low]` `[reject]` (Edge) the held-out rule passes vacuously when the outcome enumeration is empty — The `enumerations` rule fails first when the enumeration cannot be read.
  - `[low]` `[reject]` (Edge) Fixture.Definitions with an unknown set gives an obscure error — Same as Blind 10.
  - `[low]` `[reject]` (Edge) a failed Capture leaves a placeholder case.json in the recorder temp folder — The temp folder is the recorder own, emptied next run; nothing reaches the checkout.
  - `[false]` `[reject]` (Edge) a row with an empty decisionRef is not in modelAnswered — It falls to the not-complete branch ("no decision"), which is a Problem as well.
  - `[false]` `[reject]` (Edge) claim: eval/results is not in the diff — Same as Blind 11; committed.
  - `[false]` `[reject]` (Edge) claim: a digest AllClear true is never read — A digest case row has `got` = result.CatalogKey, which is the all-clear key whenever the digest says all-clear; the rules-only digests are produced by code.
  - `[low]` `[reject]` (Edge) claim: record-eval.sh can leave some snapshots written on a failed copy — Same as the copy row.
  - `[medium]` `[defer]` (VerificationGap) held-out snapshots and errorHas markers are never compared with a fresh recording — Same root cause as Blind 2.
  - `[medium]` `[patch]` (VerificationGap) the compare rule leaves the fix-run, watch-changed, digest and turn-check all-clear branches unexercised — Verified by reading check-compare.mjs. Patched: a second synthetic pair with those branches and four bad samples (bad-no-fix-runs, bad-no-watch-changed, bad-no-digest-all-clear, bad-no-turn-all-clear).
  - `[low]` `[reject]` (VerificationGap) the mock request-count command has no local test of its real grep — Same as Blind 3.
  - `[low]` `[patch]` (VerificationGap) mutation lines missing for the rules-flow variants, the held-out counts, --column, the record-eval guards and the otherFallbacks problem — Verified. Patched: lines written in the Verification; the record-eval guards got their own rule `record-held-out` (a stand-in for the throwaway, six runs and five bad samples); the otherFallbacks mutation was applied on a warm stack and went red in TestRulesOnlyModelAnswered, then restored.
  - `[low]` `[reject]` (VerificationGap) some TestRulesOnlyTurnKinds score assertions hold with rulesOnly 0 as well — The method also asserts cost, size, notComplete and Problems, which differ with the flag, and its Complete mutation went red; the extra assertions state the contract.
  - `[low]` `[reject]` (VerificationGap) ALLCLEAR_KEY in compare.mjs is a copy of the catalog key — A stable catalog key; the Report cases carry the key as written by the product. A pin test would need IRIS for a constant.
  - `[low]` `[reject]` (VerificationGap) comparison.md is appended to the step summary without the key-like scan of the other files — It is built from already scanned reports and holds case names, outcomes and counts only (checked in compare.mjs).
  - `[false]` `[reject]` (VerificationGap) the spec status and Auto Run Result are out of step with the diff — Finalize rewrites them in this pass.
  - `[low]` `[reject]` (Intent) the live rules-only run and the committed report are not shown in the diff — Resolved: both final runs (main and held-out, tags e0bs27rm and e0bs27rh) passed on the final code and eval/results/ is copied byte for byte from them.
  - `[medium]` `[defer]` (Intent) the held-out snapshots are only partially evidenced (the sourcing is pinned, the content is not re-recorded in CI) — Same root cause as Blind 2.

## Design Notes

**Governing ADs:**
- **AD-22.** The evaluation set tests the product's own path: rules-only runs through `EvalIn`, `Intake`, `Decide` and `EvalSink`, so it is not a restated answer key. CI stays in throwaways, the mock is unchanged, and the release-candidate run and key proof keep their contracts.
- **AD-8.** `no_key` is decided before sending. A fallback gives `tellnow`, with no tool, fix or approval, and an incident fallback proposes no fix.
- **AD-28.** The all-clear comes only from code, so the fixed rules can give no all-clear wording.
- **AD-19.** No key is used, and outputs hold no key-like text.
- **AD-30.** Evaluation results go to `EvalSink` and never to `Notify`.
- **AD-29.** Epic 0 may edit any lane's files; `eval/` and `OcuTalon.Eval` are Lane A's.
- No AD is amended.

**Rules-only is run, not computed.**
- With `RestoreKeys` and no key in the environment, `Keys.Absent` is 1, so `Decide.Precheck` classifies `no_key` and `RecordFallback` writes the fixed-rules decision before any request. The retry runner (`no_key` is in `RETRIED`) also has no key, so the last attempt's reason is `no_key`.
- The real path then runs end to end: `Intake` copies the fallback onto the `ItemDecision`, `IncidentManager.EvalCase` gives an empty cause, element and fix, turns get the "couldn't answer" reply with no catalog key, and digests run on code.
- (inference until Task 0 confirms it on a throwaway.)

**Measured (implement).** Task 0, `bash eval/run.sh --rules-only main` on a lane-B throwaway (tags e0bs27rm; two runs of the same code, the second after the mock-count fix below), no key:
- Every model-backed case fell back with the reason `no_key`: 59 of the 62 cases. The other 3 are the digest cases, which run on code (no decision, no cost, no size) and are scored by the digest rule (3 of 3 right). Kinds, fallback and right: item 26 / 26 / 7, incident 11 / 11 / 0, injection 6 / 6 / 1 (`heartbeat-injected-decision`), all-clear 3 / 3 / 0, command 4 / 4 / 0, documents 3 / 3 / 0, user-turn 6 / 6 / 0, digest 3 / 0 / 3. No other fallback reason, no unscored case, no case not complete, `skipped` empty (no setup turn was asked, so no skipped no-reply case in the main set), `actions` all 0, no eval watch row left, `Report.Problems` empty.
- Cost and size: `cost.priced` 0, `cost.unpriced` and `cost.decisions` empty, `size.largestTokens` null, `size.unknown` empty. No priced decision and no request size, so `--column` can print its two "none: no model request" cells.
- Scores (`scores`): items 6 of 24 (the 7 right item cases are 6 plus the precedent case `memory-noise-none`, which `scores.items` leaves out of SM-1's items), incidents 0 of 11, heldOutItems 1 of 4, heldOutIncidents 0 of 2, injections 1 of 6, allClear 3 of 6 (the digests), commands 0 of 1, `tellNowMissed` 0.
- FINDING (spec correction, applied in `eval/compare.mjs`): `scores.items` and `scores.incidents` ALREADY count the cases flagged `heldOut` (`Report.Tally` adds a held-out case to its group and to the held-out group), so the main set's items are `scores.items` (24) and its incidents `scores.incidents` (11), which are v1.0.4's 24 and 11. "scores.items plus scores.heldOutItems" would count the 4 and the 2 twice (28 and 13). The "26 items" inference above counts item-kind cases (26) and includes the two precedent cases that `scores.items` leaves out.
- The mock's request log (`requests.jsonl`) also holds the Telegram items' Bot API polls (`tokenLength` set); the first run counted 5 of them as "requests". `mock_requests` in `eval/run.sh` now counts the model requests only (`tokenLength` null); the second run: 0 model requests before and after.
- Wall time (the whole call, shell `time`): 2 min 50.7 s (first run, stack ready 135 s, restore and key check 7 s, the run 25 s) and about 3 min 5 s (second run: stack ready 147 s, keys 7 s, run 24 s, then the teardown). The stack start alone (preflight, web bundle, build, `up --wait`) is 135-147 s on this host with other lanes running, against the 81-100 s the draft assumed, so the standalone `--rules-only main` call is OVER the 165 s bound of Task 0 and the harness moves it to the background at about 180 s. The `--rules-only held-out` call was not run: it starts the same stack and would take as long. HALT (blocked), as Task 0 says.

- `--rules-only held-out` (tag e0bs27rh, no key, pass 2, before the final-code runs): 12 of 12 cases fell back with `no_key` (8 items, 4 incidents), `skipped` empty, `actions` 0, no Problems, `cost.priced` 0, `size.largestTokens` null, 0 model requests before and after. Items 2 of 8 right (the Tell now ones), incidents 0 of 4. Wall time 2 min 27 s for the whole call (it ended inside one foreground call; ruling R1's log arrangement was kept as the fallback).

**Lead ruling R1 (2026-11-12 ~11:10Z, lane-B runner, unattended `decide`; clarification round 1 of 3, implement stage, Task 0 timing HALT).**
- Question: the stack-starting `--rules-only main` / `--rules-only held-out` calls take about 2 min 50 s - 3 min 5 s on lane B (stack start 135-147 s with other lanes running), over Task 0's 165 s HALT bound, and the harness moves a call to the background at about 170-180 s.
- Choice: the 165 s bound is replaced by the owner's 10-minute cap for these two calls only. Each runs as ONE foreground call with `timeout: 600000`, its output sent to a log in the stage's scratch folder with a closing `EXIT=<code>` line; if the harness moves the call to the background, the stage waits for the `EXIT=` line in bounded foreground polls and does nothing else meanwhile (the standing rule of 2026-11-09: "If a call is moved to the background anyway, wait for it to exit in bounded foreground polls ... before anything else"). The Boundaries line "Every command a stage runs finishes in about 150 s" stays the rule for every other command.
- Rejected: (a) a warm-stack path for `--rules-only` -- new scope in `eval/run.sh`, and a warm stack is not the fresh stack the committed report and CI should come from; (b) splitting the stack start out of `eval/run.sh` -- new modes and pins for a local-only convenience; (c) deliberately backgrounding the run -- forbidden.
- Why: the limit is an implementation detail (a timeout), the owner's cap is 10 minutes and the run fits it three times over; nothing in the product, the CI job or the committed report changes.
- Also ruled (spec corrections the implement stage found, both `decide`, within intent): (1) the main set's items and incidents are `scores.items` and `scores.incidents`, which already count the `heldOut`-flagged cases (Tasks and Scoring corrected); (2) `eval/run.sh`'s mock request count counts model requests only (Telegram Bot API polls in `requests.jsonl` are not model requests): the "mock request count unchanged" check of Boundaries means model requests.
- Re-dispatch: the pass-1 work stays in the tree (uncommitted, the story's own code) and is absorbed by this pass; continue from "Not done" in `## Auto Run Result

Status: done
Blocking condition: none

Summary of the implemented change (Part B, the measuring tools; implement pass 1 and pass 2 and the review pass, one commit):
- `OcuTalon.Eval.Report` gains the `rulesOnly` flag (Run, Build, Complete, Score, Finish, Problems, Text): a `no_key` fallback is the fixed rules' answer through the same scorer; "a model answered" and "another fallback reason" are Problems.
- `eval/run.sh --rules-only [main|held-out]` starts its own stack, restores the runners' keys, refuses to send a case while any runner or retry runner holds a key, runs the sets as rules-only runs and checks the model-request count of the mock; the push run adds the held-out run on the mock, the rules-only half and `node eval/compare.mjs`; the release-candidate run adds one held-out run outside the verdict.
- `eval/compare.mjs` writes `comparison.json` and `comparison.md` (per case and in total, three unsafe kinds, needed-you-now row, cost) and prints the `--column` cells; the agent side must not be a rules-only report.
- `Feed.Fixture` gets the `HeldOutCases` set and a set argument; `docker/tests/record-eval.sh held-out [<name>]` records the 4 `snapshot.json` files and checks that no `case.json` changed and that every incident was recorded.
- `test-eval-set.sh` gains `EVAL_SET_ONLY`/`EVAL_SET_EXCEPT`, the `cases` exemption for `eval/results/`, updated guards, and the rules `held-out`, `held-out-frozen`, `held-out-names`, `compare`, `rules-flow` and `record-held-out`; `test-eval-personas.sh` gains the `--rules-only` forms.
- `eval/results/rules-only.json` and `eval/results/rules-only-held-out.json`: byte for byte from the final-code runs. Fixed rules: routine items 6 of 24, incidents 0 of 11, held-out 2 of 12, needed-you-now 0, unsafe 0, no priced decision and no request size; 0 model requests.

Files changed (all under the worktree):
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls`: the flag; `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls`: six rules-only tests; `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls`: held-out definitions.
- `eval/run.sh`, `eval/compare.mjs` (new), `eval/results/*.json` (new), `eval/held-out/*/snapshot.json` (4 new).
- `docker/tests/record-eval.sh`, `docker/tests/test-eval-set.sh`, `docker/tests/test-eval-personas.sh`.
- No README, web, `ci/`, `.github`, `release/**` or `_bmad` change; the 12 `case.json` files are byte-identical to 6af31dab (SHA-256 pins match).

Review findings: 41 rows from the four layers (see the triage log; 6 patch rows in 4 entries, 3 defer rows in 1 entry, 32 rejected): patches applied 4 (record-eval incident count, compare agent-side check, compare unsafe-branch coverage with 4 bad samples, mutation lines with the new `record-held-out` rule), deferred 1 (held-out snapshot currency, medium, in the frontmatter), rejected 32 with the reasons in the log (false claims and low findings whose fix adds guards or branches for situations the flow cannot reach).
Follow-up review recommended: false (patched: 1 medium, 3 low; no high).

Verification performed (lane B throwaways, tags e0bs27*, all torn down):
- Held-out diff against 6af31dab empty; 12 of 12 SHA-256 pins match.
- `EVAL_SET_ONLY` of `cases held-out held-out-frozen held-out-names compare record-held-out rc-guard record-guard run-guard rules-flow rc-stack` (about 68 s, also under `/bin/bash`), `EVAL_SET_EXCEPT` of that list plus `rc-flow` (about 46 s) and `rc-flow` alone (about 142 s): all rules passed. `test-eval-personas.sh` and `test-boundaries.sh` pass. `test-readme.sh` is not in this story's footprint (no README change).
- `OcuTalon.Test.Eval.Report` passes on a warm stack and on a fresh one (pass 2); `Record` and `FeedGrant` pass on the warm stack (pass 2); the otherFallbacks mutation went red and the restore went green in the review pass.
- `bash eval/run.sh --rules-only main` (2 min 16 s) and `--rules-only held-out` (1 min 57 s), each in one foreground call: all checks passed, 0 model requests; `node eval/compare.mjs --column eval/results` and the smoke run on the committed reports exit 0.
- ASCII check of the five scripts: 0 bytes outside ASCII; no `.github`, `release`, `_bmad`, `ci`, README or web hunk; no "never used for tuning" outside `_bmad-output/`.
- Not run locally by design: the full `bash eval/run.sh` push run and `eval/key-proof.sh` (CI lane A `evaluation` proves them).

Residual risks: the push run's fold (held-out on the mock, rules-only half, comparison, step summary) is pinned only on a stub (`rules-flow`) until CI's `evaluation` job runs it; the lane-A job gains about 2 to 4 minutes (inference, 30-minute timeout, 15.5-17 minutes before); the Story 0.29 `--column` row labels are pinned as `eval/compare.mjs` has them and were not checked against the ruled README text.
