---
title: 'Story 11.13: The release gets draft notes'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Release 1 has no release notes generator (REL-8). Nothing lists, in plain language and by area, the stories a candidate ships since the previous release, or gathers the evaluation summary, the rehearsal's timings and the upgrade result that the author must publish with it. For 1.0.0, the first release, there is no previous tag, so its notes cover every story merged for the release.

**Approach:** Add `release/notes.sh`. It reads the candidate's sprint tracker and story titles from git, the area mapping `release/notes-areas.txt`, the evaluation result file, and the candidate record's `## Clean-machine rehearsal` and `## Upgrade harness` sections. It writes one Markdown draft at Story 11.4's `notes_path` and checks it. It only drafts: the author edits and publishes the notes.

## Boundaries & Constraints

**Always:**
- **Only a draft, and only one file.** The script writes the notes file and nothing else. It never changes the record, the evaluation result or any tracked file. It refuses an existing notes file unless `--replace` is given (exit 2, the file unchanged), so the author's edits are never overwritten by accident.
- **Claims only what the record and the result say.** Every figure comes from an input, copied or formatted, never computed into a new claim. A story is listed only when it is `done` at the candidate and not `done` at the previous tag. A missing or mismatched input writes its `Not available:` line (Design Notes) and fails its row. A mock or dry-run input makes the result `dry run`, never `draft`.
- **Result rules (no false all-clear).**
  - `fail` when any row fails;
  - otherwise `dry run` when any input is not from real mode (the evaluation's `onMock` is true, the rehearsal's `Mode:` is not `rehearsal`, or the upgrade's `Mode:` is not `release`);
  - otherwise `draft`.
  - Exit codes: 0 `draft`; 1 `fail`; 3 `dry run`; 2 a refusal, with nothing written.
  - The script reports the gates' results as their sections give them. It does not judge them: Story 11.5's gates do.
- **Plain language (NFR-24, CON-5).** No class name, `##class(` call or error code outside `## For admins and developers`. Developer stories, the per-run table and the upgrade rows go there.
- **No network, ever.** No `curl`, `wget`, `gh`, `ssh`, `nc`, `git fetch`, `git pull`, `git push`, `git ls-remote` or `git clone`. Its text holds none of the strings that Story 11.4's `no-outward` row looks for (`gh` followed by `release`, `--visibility`, the social hosts).
- **Failure detail names the place, never the text.** A scan failure gives `file:line` only.
- **The script's text keeps the rules it checks.** It never spells the name from the not-affiliated note, never says "IRIS Couch" and never says "per step". The self-test builds its planted samples by concatenation (`/Use[r]s`), as `test-boundaries.sh` does.
- **Portability.** Bash 3.2 and ASCII only (Rule 14). Mode 100755, `umask 077`, main only when executed (`[ "${BASH_SOURCE[0]}" != "$0" ] && return 0`). It runs from the repository root. It reads JSON with `node` (the file path as an argument; no environment value is read).

**Never:**
- Publish, post, tag, push, open a pull request, or write the online demo's line. Story 11.5's update hook adds that section to the draft (REL-11, AD-25).
- Write into `release/records/` from a test or a verification run. Always pass `--record`, `--eval` and `--notes` with temporary files.
- Edit `README.md` or `docker/tests/test-readme.sh` (Epic 10's; read only). Do not edit any open epic's file: `docker/tests/lib-live.sh`, `docker/tests/test-pinned-sources.sh`, `release/standalone-bridge.sh`, `release/ipm*`, `src/module.xml`, `.github/workflows/*`. The one exception is the `CHECK_SCRIPTS` line of `ci/units.sh`, which is shared by region (the 11.1 lead ruling).
- Make the generator a CI unit. Only its hermetic self-test joins `CHECK_SCRIPTS`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Options | `--version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--eval <file>] [--notes <file>] [--areas <file>] [--replace]` | Defaults: `--candidate release/<v>-rc<n>`; `--record` is `record_path <v> <rc>`; `--eval` is `eval/release-candidate.json`; `--notes` is `notes_path <v> <rc>`; `--areas` is `release/notes-areas.txt` beside the script | An unknown option; a missing `--version` or `--rc`; a version that is not `x.y.z`; an rc that is not a positive whole number; an unknown candidate; a version that differs from the candidate's `src/module.xml` `<Version>`; a shallow repository; not inside a git repository; an existing notes file without `--replace`: exit 2, one line, nothing written |
| Previous tag | `release_previous_tag <candidate> <version>` | The highest `v[0-9]*` tag merged into the candidate, skipping a tag on the candidate and `v<version>`, with a pre-release before its release. None for 1.0.0 | No error expected |
| Stories, 1.0.0 | No previous tag | Every `  <e>-<s>-<slug>: done` key of the candidate's `_bmad-output/implementation-artifacts/sprint-status.yaml` (`git show`). The intro line is "This is the first release of OcuTalon." | No `done` key: FAIL stories |
| Stories, later | Tag `v1.0.0`, candidate 1.1.0 | Only the keys `done` at the candidate and not `done` in the tag's tracker. The intro line is "Changes since v1.0.0." | No such key: FAIL stories, naming the tag. A tag with no tracker: FAIL stories |
| Titles | `### Story <e>.<s>: <title>` in the candidate's `_bmad-output/planning-artifacts/epics.md` | Each story is listed by its title, in the order of epics.md | A key with no heading: listed in the developer section by its key; its PASS line counts it |
| Areas | `release/notes-areas.txt` (Design Notes) | `story <e>.<s> <area>` wins over `epic <e> <area>`. Story number 0 and the title `Epic <n> burn-down` are developer stories unless a `story` line says otherwise. Areas appear in the order they first appear in the file, each as `## <area>` with its stories as `- <title>`. An area with no story is left out. Developer stories go to `## For admins and developers` as `- <e>.<s> <title>` | A story whose epic has no `epic` line: FAIL areas, naming each epic. A line that is not a comment, blank, `epic <n> <text>` or `story <n>.<n> <text>`: FAIL areas with `file:line` |
| Evaluation | `--eval` file, `ocutalon.evalResult/1` | The `### Evaluation` subsection (Design Notes): the `Result:` line from `verdict`, the eight scores of `summary.scores`, `summary.attentionCost.meanUSD` and `maxUSD`, `summary.size.largestTokens`, and the override line from `override.reason` | Missing, not valid JSON, another `format`, or `commit` that is not the candidate's full sha: FAIL eval, and the subsection holds only its `Not available:` line. A `null` share, cost or size reads `not measured` |
| Evaluation on the mock | `onMock` true | The subsection adds the mock note. Result `dry run` | -- |
| Rehearsal | `## Clean-machine rehearsal` of the record | Its `Result:`, `Mode:`, `Clean host:` and `Driver host:` lines and its first table, copied verbatim, in `### Clean-machine rehearsal`. Its `### Runs` table, copied verbatim, in the developer section under `### Rehearsal runs` | Missing record or section, or a `Candidate:` line without the candidate's full sha: FAIL rehearsal; `Not available:` line |
| Upgrade | `## Upgrade harness` of the record | Its `Result:`, `Mode:`, `Previous:` and `Note:` lines (those present), copied verbatim, in `### Upgrade in place`. Its table, copied verbatim, in the developer section under `### Upgrade checks` | Missing section, or a `Candidate:` line without the candidate's full sha: FAIL upgrade; `Not available:` line |
| Draft checks | The written draft | `dev-only`: `names_outside_section '## For admins and developers'` finds nothing. `public-text`: `local_path` and `key_like` find nothing | FAIL with `file:line` only. The draft is kept for the author to fix |
| Output | Any run past the refusals | One `PASS|FAIL <id> <detail>` line for each of `stories`, `areas`, `eval`, `rehearsal`, `upgrade`, `dev-only` and `public-text`, then `NOTES <file>` and `RESULT <draft|dry run|fail>` | -- |

</intent-contract>

## Code Map

**Story 11.3's and Story 11.4's interfaces (planned, built before this story; read their specs' Tasks and Design Notes):**
- `release/lib-release.sh`: `record_path <v> <rc>`; `notes_path <v> <rc>` (11.4; prints `release/records/<v>/rc<n>-notes.md`); `record_write`; the main-guard and `umask 077` conventions.
- `release/checklist.sh` (11.4): `row_public_text` runs `test-boundaries.sh`, then `local_path` and `key_like` on the notes file; `--notes` defaults to `notes_path`. It can be sourced. Its `no-outward` and `name-only-in-note` rows scan `release/*.sh`.
- `docker/tests/test-release-checklist.sh` (11.4): the synthetic-repository pattern, the stubs and the way it sources the checklist to call one row.
- `docker/tests/test-rehearsal.sh` (11.3): the static rules (mode, ASCII, `umask`, main guard).
- If `release/lib-release.sh` lacks `notes_path`, or `release/checklist.sh` is missing, stop with a `## Clarification Needed`. Never create them here.

**The record sections (planned contracts):**
- `## Clean-machine rehearsal` (11.3 Design Notes, "The record section"; 11.11 Design Notes, "The section's additions"): `Result:`, `Mode:` (`rehearsal` real, `dry run`), `Candidate:` (holds the candidate's full sha, also in a dry run's "a stand-in of <sha>"), `Clean host:`, `Driver host:`, `Run:`, `Note:`, `Specs:`, then the `| Step | Result | Detail |` table (the install row holds "first start <n> s, install included", and the bound rows follow `demo path runs`), then `### Runs` and its table. Story 11.12 adds rows and runs; the verbatim copy needs no change for them.
- `## Upgrade harness` (11.2 Design Notes, "The record section"): `Result:`, `Mode:` (`release` real; `rehearsal`, `rehearsal (uncommitted changes)` and `dry run` otherwise), `Required:`, `Candidate: <v> at <full sha>`, `Previous:`, `Note:` (1.0.0's first-release note), `Run:`, then the `| Record | Result | Detail |` table.
- 11.2's `release/upgrade-harness.sh` `resolve_previous <repo> <candidate version> [<ref>]`: its tag branch is the one-line query of `docker/tests/test-storage.sh:323-325` (`versionsort.suffix=-`, `tag --merged`, `--sort=-version:refname`, tags on HEAD removed).

**The evaluation result (built, Story 9.5):**
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls:22-30` -- the result `{format, commit, onMock, verdict, summary{scores, attentionCost{meanUSD, maxUSD}, size{largestTokens}}, override}`; `FORMAT` is `ocutalon.evalResult/1`. Verdicts: `pass`, `blocked`, `incomplete`; `eval/run.sh --override` writes `overridden` with `override{reason, at}` (`eval/run.sh:101-104`, `:162-202`).
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls:817` and `:831-846` -- each score is `{right, total, share}` (share a number to 4 places, or null), and `items` and `incidents` also carry `target` (0.9, 0.8) and `met`.
- `eval/release-candidate.json` is not git-ignored. A `--on-mock` run writes `release-candidate-on-mock.json` in its report folder only (`eval/run.sh:78-83`), which `--eval` can name.

**Siblings to reuse or extend:**
- `docker/tests/test-readme.sh:605-614` `dev_names` -- the README's developer-section rule (section `## For admins and developers`). It is a top-level script and cannot be sourced.
- `docker/tests/lib-scan.sh` (sourced by `test-readme.sh:64` and the static scanners): `local_path` (moved here by 11.4) and `scan_files`.
- `docker/tests/lib-keys.sh:15-17` `KEY_LIKE_ERE`, `key_like`.
- `docker/tests/test-storage.sh:323-325` -- the tag query.

**Facts (read at plan time):**
- `sprint-status.yaml` keys look like `  11-4-the-release-gets-draft-notes-and-a-checklist: done`; `epic-<n>` and `epic-<n>-retrospective` keys are skipped. On `origin/feature/OCT_OcuTalon_MVP` an unmerged epic's stories are `backlog`, so `done` at the candidate means merged. 141 keys are `done` on this branch.
- epics.md has 217 story headings, `### Story <e>.<s>: <title>`, in planning order (7.6 before 7.3). No title names the inspiration.
- No `v*` tag exists. `src/module.xml:6` holds `<Version>0.1.0</Version>`; Story 11.5 sets it at the cut.
- The hosted `checks` job (ubuntu-24.04) has `node`; `docker/tests/test-eval-set.sh` already uses it there.

**CI recipe:**
- `ci/units.sh:6` `CHECK_SCRIPTS`: add `release-notes` at the end. `NOT_IRIS_INPUT_PATTERN` already declares `release/` and `docker/tests/test-*.sh` non-inputs, so no IRIS group runs on this story's files.
- `docker/tests/test-ci-config.sh` checks that every `docker/tests/test-*.sh` sits in exactly one list. No pin names check scripts.

## Tasks & Acceptance

**Execution:**
- `release/lib-release.sh` -- add `release_previous_tag <ref> <version>` (the Previous tag row; the query of `test-storage.sh:323-325`, with tags on `<ref>` and `v<version>` skipped). If 11.2's `resolve_previous` holds the query inline, make it call this function, keep its behaviour, and keep `docker/tests/test-upgrade-harness.sh` green (Rule 2: one definition).
- `docker/tests/lib-scan.sh` -- add `names_outside_section <heading> <file>...`: `file:line` for each line outside the H2 section whose heading line equals `<heading>` that has a `##class(` call, an `ERROR #<digits>` code, an `<UPPER>` error name or a dotted class name. It is `test-readme.sh`'s `dev_names` rule with the heading as a parameter. Update the header's list.
- `release/notes-areas.txt` -- new, the mapping in Design Notes, with a header comment that states the line forms and the developer rules.
- `release/notes.sh` -- new. The header is the usage and Story 11.5's contract: options, inputs, the draft's shape, the rows, the result rules and the exit codes. It sources `lib-release.sh`, `docker/tests/lib-scan.sh` and `docker/tests/lib-keys.sh` from its own root.
  - Functions, each sourceable: `notes_stories <candidate> <previous>` (`id|key|title` lines), `notes_areas <areas file> <stories>` (`area|id|title` lines, `developer` as the area of a developer story), `notes_eval <file> <sha>` (the subsection), `notes_section <record> <heading>` (one `## ` section's lines), `notes_rehearsal`, `notes_upgrade`, `notes_draft` (the whole document), and `notes_result <results>`.
  - Main: parse and refuse (exit 2) before anything is written. Build the draft in a temporary file beside the notes file and `mv` it into place. Run the two draft checks on it. Print the rows, `NOTES <file>` and `RESULT <result>`, and exit.
- `docker/tests/test-release-notes.sh` -- new, hermetic: no container and no network; it needs bash, git, awk and node.
  - **A synthetic git repository** in a temporary folder holds copies of `release/notes.sh`, `release/lib-release.sh`, `release/checklist.sh`, `docker/tests/lib-scan.sh` and `docker/tests/lib-keys.sh`, a stub `docker/tests/test-boundaries.sh` (exit 0), a fixture `src/module.xml` (`1.0.0`), a fixture `epics.md` and `sprint-status.yaml` with stories in three epics (one mapped `developer`, one story `N.0`, one `Epic N burn-down`, one key without a heading), and a fixture `notes-areas.txt`. Everything is committed on `release/1.0.0-rc1`. Fixture records and evaluation results are written per case, with the candidate's sha.
  - **The base case (1.0.0):** real-mode inputs give `RESULT draft` and exit 0. The draft holds the intro line, the areas in the file's order with their titles in epics.md order, every developer story only in the developer section, the eight scores, the cost and size lines, `Override: none.`, the rehearsal and upgrade lines and tables, and the runs and upgrade tables in the developer section. The record and the result are byte for byte unchanged.
  - **A later version:** a commit with `v1.0.0` tagged and some stories `done`, then more stories `done` and `src/module.xml` at `1.1.0` on `release/1.1.0-rc1`: only the new stories, and "Changes since v1.0.0.". With no new story: FAIL stories.
  - **One case per failing input,** each in a fresh copy, expected to FAIL alone (no record fails both rehearsal and upgrade) with its `Not available:` line and `RESULT fail`, exit 1: no evaluation file; invalid JSON; another `format`; another `commit`; no record; no rehearsal section; a rehearsal `Candidate:` line with another sha; no upgrade section; an unmapped epic (named); a malformed mapping line (`file:line`).
  - **The evaluation's forms:** `overridden` with a reason gives the override line with that reason; a `null` share and a `null` cost read `not measured`.
  - **Dry run:** `onMock` true gives the mock note, `RESULT dry run` and exit 3; so does a rehearsal `Mode: dry run`, and an upgrade `Mode: rehearsal`.
  - **The draft checks:** a mapped title holding a dotted class name fails `dev-only` with `file:line`, while the same title as a developer story passes; an override reason holding a local path, and then a key-like string (both built by concatenation), fails `public-text` with `file:line` and no planted text in the output.
  - **Integration (the checklist reads the draft):** after the base case, source the copied `checklist.sh` and call `row_public_text` as `test-release-checklist.sh` does, with no `--notes` given, so it reads `notes_path 1.0.0 1`: it prints `PASS public-text`. After the local-path case, the same call prints `FAIL public-text`.
  - **Refusals (exit 2, nothing written, an existing notes file unchanged):** each refusal of the Options row. Then `--replace` rewrites the existing file.
  - **No network:** stubs for `curl`, `wget`, `gh`, `ssh` and `nc` on `PATH` write a marker when called, and no case leaves one.
  - **Static rules on `notes.sh`:** mode 100755, `umask 077`, ASCII, the main guard, no network command, none of 11.4's `no-outward` strings, and none of the name from the note, "IRIS Couch" or "per step".
  - **On the real tree:** `release/notes-areas.txt` parses; every `story` line names a heading of the real epics.md; and `notes.sh --version <module.xml's version> --rc 1 --candidate HEAD` with temporary `--record`, `--eval` and `--notes` prints `PASS stories`, `PASS areas`, `PASS dev-only` and `PASS public-text`, and FAILs eval, rehearsal and upgrade (no inputs).
- `ci/units.sh` -- add `release-notes` to the end of `CHECK_SCRIPTS`, and nothing else. Then run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- **AC1 (stories by area; REL-8, NFR-24).** Given the previous release's tag and the candidate, when `release/notes.sh` runs, then the draft lists the stories `done` at the candidate and not `done` at the tag, each by its title, under its area's `## ` heading in the mapping's order. For 1.0.0, with no tag, it lists every `done` story and opens with "This is the first release of OcuTalon.". A later version lists only the new stories and opens with "Changes since v<tag version>.". A story whose epic has no area fails `areas`, naming the epic.
- **AC2 (the developer section; CON-5, NFR-24).** Given developer stories (mapped `developer`, numbered 0, titled `Epic <n> burn-down`, or without a heading), when the draft is written, then they appear only under `## For admins and developers`, with the runs table and the upgrade rows. `dev-only` fails with `file:line` when a class name, `##class(` call or error code appears outside that section.
- **AC3 (the evaluation summary; FR-62, REL-5).** Given the evaluation result of the candidate's commit, when the draft is written, then `### Evaluation` holds its `Result:` line, the eight scores (right, of, share, target), the mean and highest cost per attention decision, the largest model request in tokens, and the override line: `Override: none.`, or the reason of an overridden result. A result that is missing, unreadable, of another format or of another commit fails `eval`, and the subsection holds only its `Not available:` line.
- **AC4 (the rehearsal's timings and the upgrade result; REL-6).** Given the candidate's record, when the draft is written, then `### Clean-machine rehearsal` holds the rehearsal's `Result:`, `Mode:` and host lines and its table, verbatim, and `### Upgrade in place` holds the upgrade's `Result:`, `Mode:`, `Previous:` and `Note:` lines, verbatim. A missing section, or a `Candidate:` line without the candidate's sha, fails its row.
- **AC5 (no false all-clear).** Given any run, when it ends, then the result and the exit follow the result rules: an evaluation on the mock, a dry-run rehearsal or a non-release upgrade gives `dry run` and exit 3, never `draft`; any failed row gives `fail` and exit 1.
- **AC6 (the author edits and publishes; REL-8, REL-11).** Given any run, when it ends, then only the notes file was written (the record and the result are unchanged); an existing notes file is refused without `--replace`; no network tool ran; and no line of the script publishes, posts, tags or pushes.
- **AC7 (integration: Story 11.4's checklist consumes the draft).** Given a draft written at the default `notes_path <v> <rc>`, when the checklist's `row_public_text` runs on its own default notes path, then it passes; and after a planted local path, both `notes.sh`'s `public-text` row and the checklist's row fail.
- **AC8 (the mapping covers release 1).** Given the real tree, when the self-test's real-tree case runs, then every `done` story maps to an area or to the developer section, and every `story` line of `release/notes-areas.txt` names a story heading of epics.md.

## Spec Change Log

## Review Triage Log

## Design Notes

**Lead update 2026-11-01 (DW-551, from Story 11.4's implement stage; address it in Tasks & Acceptance).** Story 11.4's built `row_public_text` takes the notes file as an argument and scans it for local paths and key-like text only. The draft check this story writes must also refuse the inspiration's name outside the not-affiliated note (the note verbatim, or the name nowhere), with a pinning test; adjudicate DW-551 against it.


**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-22 | The evaluation set and its result file (`ocutalon.evalResult/1`, `eval/run.sh --release-candidate`, `--override`); the CON-5 scanners reused (`lib-scan.sh`, `lib-keys.sh`); a hosted, hermetic self-test |
| AD-29 | `release/` is Lane A's; `ci/units.sh` is shared by region; the open epics' files stay untouched |
| AD-19 | No key or configuration value is read, printed or written (JSON is read by file path; scan failures name only `file:line`) |
| AD-25 | Not used here: Story 11.5's update hook writes the online demo's section into this draft |

No AC contradicts an AD.

**The draft** (indented two spaces here, so that no section scan reads it; in the file each line starts at column 1; the order is fixed; 1.0.0 shown):
```
  <!-- Drafted by release/notes.sh for OcuTalon 1.0.0 rc1 at <full sha>. Edit it before you publish it. -->
  # OcuTalon 1.0.0

  This is the first release of OcuTalon.

  ## Install, upgrade and sign in

  - The image builds and starts OcuTalon in its own namespace
  (one line per story of the area)

  (one ## section per area with a story)

  ## How this release was checked

  ### Evaluation

  Result: pass

  | Measure | Right | Of | Share | Target |
  | --- | --- | --- | --- | --- |
  | Items decided right | 19 | 20 | 95.0% | 90% |
  | Incidents diagnosed right | 9 | 10 | 90.0% | 80% |
  | Held-out items decided right | 5 | 5 | 100.0% | - |
  | Held-out incidents diagnosed right | 2 | 2 | 100.0% | - |
  | Injection attempts handled safely | 2 | 2 | 100.0% | - |
  | Held-out injection attempts handled safely | 1 | 1 | 100.0% | - |
  | All-clear answers right | 3 | 3 | 100.0% | - |
  | Command requests answered right | 1 | 1 | 100.0% | - |

  - Cost per attention decision: mean $0.0006, highest $0.0009.
  - Largest model request: 1,520 tokens.
  - Override: none.

  ### Clean-machine rehearsal

  (Result:, Mode:, Clean host: and Driver host: lines, then the step and bound table, all verbatim)

  ### Upgrade in place

  (Result:, Mode:, Previous: and Note: lines, verbatim)

  ## For admins and developers

  ### Stories about how OcuTalon is built and tested

  - 0.4 The cross-lane message and data contracts
  (one line per developer story; a story without a heading as its key)

  ### Rehearsal runs

  (the ### Runs table, verbatim)

  ### Upgrade checks

  (the upgrade table, verbatim)
```
- Share: one decimal place and `%`, or `not measured` when null. Target: the whole percent, or `-` when the score has none. Costs: `$` and four decimal places, or `not measured`. Tokens: thousands separated by commas, or `not measured`.
- An overridden result: `- Override: the author overrode a blocked result. Reason: <override.reason>`.
- A result on the mock adds, after `Result:`, the line `Note: The CI mock stood in for the model, so these figures are not the release's.`
- A failed input's subsection holds only its line: `Not available: no evaluation result for this candidate.`, `Not available: no clean-machine rehearsal for this candidate.`, or `Not available: no upgrade result for this candidate.` A developer subsection with nothing to show is left out.
- Story 11.5's update hook adds its online demo section to the draft with `record_write <notes> <section>`. The draft uses only `## ` sections, so the hook's section is a section of its own.

**`release/notes-areas.txt`** (the simplest option that fits: a small mapping file in `release/`, because epics.md's headings carry planning words such as "(step 2)" and "Could", and some epics and stories are internal work, so a classification is needed in any case). Comment lines start with `#`. The areas appear in this order:
```
epic 0 Install, upgrade and sign in
epic 10 Install, upgrade and sign in
epic 15 Install, upgrade and sign in
epic 2 The page and the chat
epic 4 The demo
epic 5 Watching productions and incidents
epic 3 Approvals and the audit log
epic 6 Approvals and the audit log
epic 7 Approvals and the audit log
epic 1 Attention decisions and the model
epic 8 Heartbeat and reminders
epic 12 Telegram
epic 13 The bridge for your own productions
epic 14 Security
epic 16 The online demo
epic 29 The online demo
epic 30 Fixes and hardening
epic 31 Fixes and hardening
epic 9 developer
epic 11 developer
epic 32 developer
epic 38 developer
story 0.4 developer
story 0.5 developer
story 0.6 developer
story 0.7 developer
story 0.8 developer
story 0.9 developer
story 0.10 The demo
story 0.11 developer
story 1.2 developer
story 1.10 Heartbeat and reminders
story 1.12 developer
story 2.3 developer
story 2.4 developer
story 2.16 developer
story 2.17 developer
story 3.8 The online demo
story 5.11 developer
story 10.3 developer
story 11.2 Install, upgrade and sign in
story 11.8 Heartbeat and reminders
story 12.1 developer
story 16.6 developer
story 29.3 developer
story 29.5 developer
story 29.6 developer
story 29.8 developer
story 31.1 The page and the chat
story 31.2 Approvals and the audit log
story 31.3 The online demo
story 31.4 Telegram
```
- The step epics (17 to 28 and 33 to 37) and the personality epics have no line: none of them ships in 1.0.0, and inventing an area for unbuilt work would be a claim. The first release that ships one fails `areas`, naming it, until a line is added.

**New public-facing text (for the lead to rule; product default 3).** The draft is outward text. Every fixed sentence is new: the provenance comment; "This is the first release of OcuTalon."; "Changes since v<version>."; the area names above; `## How this release was checked`, `### Evaluation`, `### Clean-machine rehearsal`, `### Upgrade in place`; the scores table's header and its eight labels; the cost, size and override lines; the mock note; the three `Not available:` lines; `## For admins and developers`, `### Stories about how OcuTalon is built and tested`, `### Rehearsal runs` and `### Upgrade checks`. None names the inspiration, a rival entry or an entrant; none says "IRIS Couch"; cost is per attention decision and size per request, never per step. The copied lines and tables are Stories 11.2's, 11.3's and 11.11's own section text.

**Interface (Rule 1/2).**

| Link | Who |
| --- | --- |
| Consumed-by | Story 11.4's checklist: its `public-text` row (`row_public_text`) scans the draft at `notes_path <v> <rc>`, its default `--notes` |
| Consumed-by | Story 11.5's sequence: `bash release/notes.sh --version <v> --rc <n> [--candidate <ref>] [--eval <file>]` after the gates, as its draft-notes step (REL-8). It reads `RESULT`. Its update hook adds the online demo's section to the draft. `--eval` lets it pass the result file from wherever it keeps it |
| Consumes | Story 11.3's and 11.4's `lib-release.sh` (`record_path`, `notes_path`); the record sections of Stories 11.2, 11.3 and 11.11; Story 9.5's result file; the candidate's `sprint-status.yaml` and `epics.md`; `lib-scan.sh` (`local_path`) and `lib-keys.sh` (`key_like`) |

- **Integration ACs:** AC7 (the checklist's `row_public_text`, the real copied function, reads the draft from its default path). There are no other consumers in this story; the first outside consumer will be Story 11.5.

**Extend, don't copy (Rule 2).**
- **The previous tag** is one definition, `release_previous_tag` in `lib-release.sh`, used by this script and by 11.2's `resolve_previous`. Only `test-storage.sh:323-325` keeps its own copy: it is a top-level script whose release diff predates the library.
- **The public-text scan** of the draft calls the same `local_path` and `key_like` that the checklist's `row_public_text` and `test-boundaries.sh` use. The script does not run `row_public_text` itself, because that row also runs `test-boundaries.sh` on the whole tree, which is the checklist's job.
- **`names_outside_section`** is a copy of `test-readme.sh`'s `dev_names` (about 6 awk lines) with the heading as a parameter. That script runs at top level, cannot be sourced, and is Epic 10's read-only file. The copy lives in `lib-scan.sh`, which `test-readme.sh` already sources, so the two can be unified when Epic 10 next changes `test-readme.sh` (not this story's file).
- **The section reader** (`notes_section`) reads the same `## ` boundaries that 11.3's `record_write` replaces. If 11.3's library already has a reader (11.2's `record_section`, moved there), use it instead.
- **The row lines, the result printing and the exit-code style** are 11.3's and 11.4's (`PASS|FAIL`, `RESULT`, 0/1/2/3).

**Decided in-stage.**
1. **The area mapping** is a small file in `release/`, not epics.md's headings (reason above). Epic lines give the default; story lines move one story. Developer stories are found by the file, by story number 0 and by the burn-down title, so each future burn-down and X.0 needs no line.
2. **Where each input is read.** The tracker, the titles and `module.xml` come from the candidate ref through `git show`, so the notes describe the candidate itself, wherever the script runs. The mapping, the record and the result are files, so the author can correct a mapping or name a result without cutting a new candidate.
3. **The evaluation must be the candidate's.** Its `commit` must equal the candidate's full sha, and its `format` must be `ocutalon.evalResult/1`. A result on the mock is reported, with the mock note, and makes the run a dry run.
4. **Copy, don't rephrase.** The rehearsal's and the upgrade's lines and tables are copied verbatim, so the notes can claim no more than the record does, and Story 11.12's added rows need no change here. The per-run table and the upgrade rows go to the developer section: they are detail, and the upgrade rows may name internal checks.
5. **The generator reports the gates; it does not judge them.** A `blocked` evaluation or a failed rehearsal is written as its section says. Story 11.5's gates decide whether the release goes out.
6. **One override line.** The AC names the REL-5 override twice (in the evaluation summary and on its own); the one line carries it, with its reason.
7. **No overwrite by default.** The author edits the draft in place, so a second run refuses unless `--replace` is given.
8. **No record section.** The generator writes only the draft. Story 11.5 records its steps in the candidate's record.
9. **The developer heading** is the README's own, `## For admins and developers`, so the two documents keep one rule.
10. **Node for JSON**, the tool `eval/run.sh --override` already uses. A missing `node` fails `eval`; it is not a refusal.

**Siblings.** Stories 11.2 (`## Upgrade harness`, `resolve_previous`), 11.3 (`lib-release.sh`, `## Clean-machine rehearsal`), 11.11 (the bound rows and `### Runs`) and 11.4 (`notes_path`, `row_public_text`, `local_path` in `lib-scan.sh`) are planned (ready-for-dev) and built before this story; this plan uses their specs' stated interfaces. Story 11.12 adds rows only. Story 11.5 composes this story.

**Rule 5 check.** NFR-24, REL-8 and CON-5 are measurable here: the `dev-only` rule, the public-text scanners, the area grouping and the verbatim copies. No intent gap.

**Size.** Two new scripts, a data file and its self-test, two small library additions and one CI line. The story stays whole: its parts share one draft.

**Ledger (Rule 17).** This story owns no entries.

**Contended paths (U14).** Checked at plan time against `contended-epic-11.txt` and `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for 4, 12, 13, 15, 30 and 31:
- New files: `release/notes.sh`, `release/notes-areas.txt`, `docker/tests/test-release-notes.sh`.
- Changed: `release/lib-release.sh` and possibly `release/upgrade-harness.sh` (this epic's); `docker/tests/lib-scan.sh` (no open epic changes it; one function appended); `ci/units.sh` (the `CHECK_SCRIPTS` line only, contended by Epics 12, 13, 15 and 29, and shared by region: a plain union).
- `README.md` and `docker/tests/test-readme.sh` are read only.

**CI budget (REL-4).** No IRIS group changes. The self-test runs in the hosted `checks` job and adds a few seconds (inference: a synthetic repository and about 25 short runs).

**Continuity.** The previous `done` story, 11.10 (the REL-2 failure paths), shares no file with this story.

## Clarification Needed (non-blocking: the plan does not depend on the answer)

1. Rule the new public-facing sentences and the area names listed in Design Notes (veto window 5).

## Verification

Run everything from the epic-11 worktree root, each command in the foreground of its own call with `timeout: 600000`. No IRIS slot, MCP call or throwaway is needed: this story changes no class and starts no container.

**Commands:**
- `(once, first)` `git rev-parse --show-toplevel` -- expected: the epic-11 worktree.
- `(loop)` `bash -n release/notes.sh && bash docker/tests/test-release-notes.sh` -- expected: every PASS line, exit 0.
- `(loop)` `bash docker/tests/test-release-checklist.sh` -- expected: exit 0 (`lib-scan.sh` and `lib-release.sh` gained a function).
- `(loop)` `bash docker/tests/test-rehearsal.sh`, then `bash docker/tests/test-upgrade-harness.sh`, each in its own call -- expected: exit 0 (the shared library, and `resolve_previous` if it now calls `release_previous_tag`).
- `(loop)` `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-readme.sh`, each in its own call -- expected: exit 0 (`release/*.sh` scope and `lib-scan.sh`, which the README test sources).
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash ci/changes.sh ci.yml`, each in its own call -- expected: exit 0, with `release-notes` in exactly one list.
- `(once)` On the real tree: `d="${TMPDIR:-/tmp}/e11s13-notes"; rm -rf "$d"; mkdir -p "$d"; bash release/notes.sh --version "$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/module.xml)" --rc 1 --candidate HEAD --record "$d/rc1.md" --eval "$d/none.json" --notes "$d/notes.md"`. Expected: `PASS stories`, `PASS areas`, `PASS dev-only` and `PASS public-text`; FAIL eval, rehearsal and upgrade; `RESULT fail` and exit 1; no file under `release/records/`. Read the draft once and record here the story count per area and the seconds the run took.
- `(once)` Every script of `CHECK_SCRIPTS` in parts, one part per call, each `for s in <names>; do bash docker/tests/test-$s.sh || echo "FAILED $s"; done`: (1) `boundaries storage class-rules ci-config ci-changes compose-file pinned-sources`; (2) `after-start healthcheck lib-live bootstrap demo-path-gate ci-warm`; (3) `probe install-script readme eval-set online-host online-load`; (4) the release scripts then in the list (`rehearsal upgrade-harness release-checklist release-notes`, as present). A part that nears 8 minutes is split further. Expected: no `FAILED` line.

**Mutations to demonstrate (Rule 19; one per AC, recorded here as `mutation: <change> -> <test red>`):**
- AC1: read the previous tag's tracker from the candidate instead, so the later-version case lists the old stories.
- AC2: drop the story-number-0 rule, so that fixture story is listed under its area.
- AC3: skip the `commit` comparison, so the other-commit case passes.
- AC4: accept a `Candidate:` line without the candidate's sha, so that case passes.
- AC5: ignore `onMock`, so the mock case gives `RESULT draft`.
- AC6: drop the existing-file refusal, so the refusal case overwrites the file.
- AC7: write the draft to `rc<n>.notes.md` in place of `notes_path`, so the checklist's default-path call fails.
- AC8: delete the `epic 8` line of the real mapping, so the real-tree case fails `areas`.

**Shared surfaces:**
- `CHECK_SCRIPTS` in `ci/units.sh` (it gains `release-notes`), read by `ci/checks.sh` and `test-ci-config.sh`.
- `lib-scan.sh`'s function list (it gains `names_outside_section`), sourced by `test-readme.sh` and the static scanners.
- `lib-release.sh`'s function list (it gains `release_previous_tag`), and 11.2's `resolve_previous` if it now calls it.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds its own repository, stubs, records and results in a temporary folder, and removes them.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
