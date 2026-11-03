---
title: 'Story 11.15: The hands-on gate stops the sequence, and its resume command waits for a pass or a carry-over'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 11.14 puts `hands-on` last in `release/release.sh`'s gate list as a stop that never passes. Nothing yet tells the Contest Planner which candidate to install, reads the pass the Planner records, refuses to resume without it, or lets a re-cut that only adds the pass's fixes carry the pass over. With no grammar for the pass record, the gate has nothing to read.

**Approach:** Replace 11.14's `step_hands_on` with the real gate:
- It defines the `## Hands-on pass` section that the Contest Planner writes into the candidate's record. The section has two forms: a fresh pass, or a carry-over.
- On the first arrival, the gate stops (exit 4) and names the candidate to install.
- `resume` (and `next`) then refuse (exit 2, nothing written) until the record holds a valid pass or carry-over for this candidate.
- A carry-over is checked against 11.5's `Cut from:` line and against git itself.

This story takes epics.md Story 11.15's two criteria, verbatim there.

## Boundaries & Constraints

**Always:**
- **11.5's and 11.14's conventions still hold:**
  - Bash 3.2 and ASCII; mode 100755; `umask 077`; the main guard;
  - `PASS|FAIL <step> <detail>`, then `RECORD` and `RESULT`;
  - the stop routine (record, commit with an explicit pathspec, ASK `record`);
  - answers only on stdin; no value printed; exactly two pushes; exit codes 0, 1, 2, 4 and 5 keep their meaning.
- **The Contest Planner writes the pass, never the script.** The Planner writes it under the owner's delegation, as for 11.4's Author confirmations. The script only reads `## Hands-on pass`. It never writes, edits or completes that section, a finding's disposition or a carry-over note. It reads the record in the author's checkout at the state's `--record` path, committed or not. The next stop's record commit carries the section with it (`record_write` keeps it byte for byte).
- **Hands-on time stays the sum of ASK windows (11.5).** The script is not running during the pass, so the pass adds nothing. A test proves it with a clock jump between the stop and the resume.
- **Fresh pass (the grammar in Design Notes).** It is valid only when all of these hold:
  - `Result: pass`;
  - its `Candidate:` line equals `## Release sequence`'s `Candidate:` line byte for byte;
  - `Routes:` includes both `web` and `telegram` (REL-7: "Later passes include Telegram"; for 1.0.0, Stories 38.1 and 38.3);
  - `Phone look:` is `done` or `skipped` (either one passes; REL-7 says the look never blocks);
  - every finding line is `fixed <40-hex>` or `deferred` with text, or `Findings: none`.
- **What the gate makes of a fresh pass:**
  - It passes only when no finding is `fixed`, because a fix is never in the candidate it was found on.
  - With fixes recorded, it fails and prints the re-cut command that carries the pass over.
  - `Result: fail`, or any `open` finding, fails the gate.
- **A same-version carry-over** is valid only when all of these hold:
  - `Carried from:` equals the `Candidate:` line of an earlier record of the same version, and that record holds a valid fresh pass;
  - this candidate's `Cut from:` names that candidate's SHA, then exactly the source pass's `fixed` SHAs (as a set, each once);
  - git agrees, checked in `<state>/candidate` (11.14's `candidate_clone`):
    - `<source>..<candidate>` is the picks plus one cut commit;
    - each pick's `git patch-id --stable` equals its fix's;
    - each fix is an ancestor of `<remote>/<integration>`;
    - the cut commit touches only `src/module.xml` and `src/ocutalon/csp/`;
  - the section's `Note:` line is not empty.
- **A cross-version carry-over** ("other releases record a carry-over") is valid only when all of these hold:
  - the version is not 1.0.0;
  - the section holds `Ends a build step: no`;
  - `Carried from:` names an earlier version's record with a valid fresh pass;
  - that version's `v<x.y.z>` tag exists (11.5's `release_tags`);
  - `Note:` is not empty.
- **A rehearsal never carries a pass over.** A carry-over is refused when either record's `## Release sequence` `Mode:` is not `release`, or when the source candidate is not a `release/*` branch (U-203). A fresh pass in a rehearsal record is judged like any other, because that is 11.18's fixture path.
- **Extend, don't copy (Rule 2):**
  - read fields with 11.14's `record_field`;
  - read the findings with one section-body reader in `lib-release.sh` (see Code Map);
  - get the candidate clone from 11.14's `candidate_clone`;
  - get the tags from 11.5's `release_tags`.
- **Tests use only throwaway repositories with local bare remotes, and the `gh` shim of 11.14.**

**Never:**
- Run `release/release.sh` in this worktree, in a real checkout, or against GitHub or any network remote.
- Cut a real release, tag a real release, push to `main` or `origin`, open a pull request, publish anything, or change repository settings.
- Add an option, environment variable or configuration key that passes, skips or pre-answers the hands-on gate.
- Count the pass toward hands-on time.
- Write `release/records/` of the real tree.
- Build 11.16's outward steps, or 11.18's rehearsal mode or fixture.
- Edit `.github/workflows/*`, `ci/units.sh`, `src/module.xml`, `README.md`, `docker/tests/lib-live.sh` or `.gitignore`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First arrival | Every automated gate passed; the record has no `## Hands-on pass` | `STOPPED hands-on` stop line (Design Notes), exit 4. Row `hands-on \| waiting`. The record's `Result:` reads the waiting text. Committed, then ASK `record` | The state marks `hands_on=stopped` |
| Resume, no pass | After the stop, `resume` (or `next`) with no section | `REFUSED hands-on no hands-on pass for release/<v>-rc<n> at <sha> in <record>`, exit 2 | State, record, commits and remote unchanged; no ASK |
| Fresh pass, all deferred | A valid fresh pass; `Findings: none` or only `deferred` | `PASS hands-on`, exit 0. Row `pass` with the routes, the finding counts and the phone look. The next `next` ends the steps with the end text | -- |
| Fresh pass with fixes | Valid, with one or more `fixed <sha>` | `FAIL hands-on` naming the re-cut command `start --version <v> --from release/<v>-rc<n> --pick <sha>...` (in finding order), exit 1. Record `Result: failed at hands-on: ...` | A later `next` re-reads the section |
| Pass failed or open | `Result: fail`, or any `open` finding | `FAIL hands-on the hands-on pass has open findings: F<k>...`, exit 1 | -- |
| Bad grammar | A missing or other `Candidate:`; a `Routes:` without `telegram`; a missing `Phone look:`; a finding with no disposition or text; an unknown `Result:` | `REFUSED hands-on <which rule>`, exit 2 | Nothing written |
| Carry-over valid | rc2 started with `--from release/1.0.0-rc1 --pick <the fixes>`; rc1's record holds the fresh pass; rc2's section is a carry-over with a note | `PASS hands-on`; row `carried over` naming the source and the picks | -- |
| Carry-over invalid | rc2 cut from the integration head; a missing or extra pick; a forged `Cut from:` line that git contradicts; a missing `Note:`; the source pass not valid | `REFUSED hands-on` naming the rule (`needs a fresh pass: ...`) | Nothing written |
| Rehearsal | `Mode: rehearsal` in either record, or a `rehearsal/*` source | `REFUSED hands-on a rehearsal record never carries a pass over` | -- |
| Cross-version | 1.0.1 (tag `v1.0.0` on the bare remote) carrying from 1.0.0 rc1's fresh pass, with `Ends a build step: no` | `PASS hands-on`, row `carried over` | Refused without the line, without the tag, or for 1.0.0 (`1.0.0 ends a build step and needs a fresh pass`) |
| Pass time | A 7,200 s clock jump between the stop and the resume | `Hands-on time:` is unchanged by the jump: only the ASK windows count | -- |

</intent-contract>

## Code Map

**Prerequisites.** Stories 11.3, 11.4, 11.11, 11.13, 11.5 and 11.14 are merged into this branch. Today 11.5 and 11.14 are only `ready-for-dev`, and `release/` holds only `lib-release.sh`, `rehearse.sh` and `upgrade-harness.sh`. If 11.5's `release.sh` or 11.14's gate steps are missing, implement HALTs `blocked` with `missing prerequisite story`, naming them.

**Files:**
- `release/release.sh` (11.5, extended by 11.14) -- replace `step_hands_on`. Change these:
  - the end-of-steps `Result:` text;
  - the header comment, which gains the `## Hands-on pass` grammar (the contract the Planner writes to; Rule 14);
  - `next` and `resume` keep one code path, which is the gate's re-check.
  - Read 11.5's state file helpers (`env_get` / `env_set` in `lib-release.sh:39-48`) for `hands_on=stopped`.
- `release/lib-release.sh`:
  - `record_write` `:207-233` ends a section at the next `^##? ` heading, so `###` lines and `- ` lines stay inside it.
  - `env_get` / `env_set` `:40-48`; `detail_clean` `:50`; `record_path` `:204`.
  - 11.14 adds `record_field` and `candidate_clone`, and 11.5 adds `release_tags` and `candidate_branch`.
  - **Add `record_section_body <file> <title>`** (the lines of one `## ` section after its title, up to the next `^##? ` heading) only if no reader exists by then:
    - if 11.14's `record_field` is built on a body reader, expose that one;
    - if 11.13's `notes_section` was moved into the library, reuse it.
  - Never name it `record_section`: `release/upgrade-harness.sh:399` defines that name as its section writer and sources this library.
- 11.5's `Cut from:` (spec 11.5 Design Notes) has two forms:
  - `feature/OCT_OcuTalon_MVP at <sha>`;
  - `release/1.0.0-rc1 at <sha>, then <sha1> <sha2> cherry-picked from feature/OCT_OcuTalon_MVP` (picks made with `cherry-pick -x`, in order, then the cut commit, `--allow-empty` on a re-cut).
- 11.5's `Candidate:` is `1.0.0 rc1, release/1.0.0-rc1 at <40-hex>`, and `Mode:` is always `release` (11.18 adds `rehearsal`).
- 11.14's hands-on placeholder: Matrix row "Hands-on" and AC8 in spec 11.14. 11.14's self-test pins its text, and this story updates those pins.
- `docker/tests/test-release-sequence.sh` (11.5, extended by 11.14) -- extend:
  - reuse 11.14's fixture driver, which brings a throwaway candidate through every automated gate green;
  - reuse its `gh` shim and its clock seam (`OCUTALON_RELEASE_NOW`).
  - It has no new `CHECK_SCRIPTS` entry.
- 11.4's precedent for Planner-written lines: `- <id>: confirmed <YYYY-MM-DD>` under `## Author confirmations`, which the checklist reads and never writes (spec 11.4 :30, :59). The finding lines take the same `- <id>: <word> ...` shape.

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure, figures into `## Verification`):
  - Time 11.14's `bash docker/tests/test-release-sequence.sh` as built.
  - Confirm `git cherry-pick -x`'s trailer and `git patch-id --stable` on a pick against its fix, in a scratch throwaway repository.
  - If the self-test with this story's cases would exceed about 6 minutes, add a case filter (`--cases hands-on`) and list the split calls under Verification.
- `release/lib-release.sh` -- add `record_section_body` only as described in Code Map. Keep every existing function and its consumers' self-tests green.
- `release/release.sh` -- the gate as in Boundaries, the Matrix and Design Notes:
  - the fresh-pass judge;
  - the same-version and cross-version carry-over checks (string, then git);
  - the stop and refusal texts;
  - the end text;
  - the grammar in the header.
- `docker/tests/test-release-sequence.sh`:
  - Update 11.14's hands-on pins.
  - Add the cases. Drive one candidate to the gate. Because a refusal writes nothing, loop over the grammar fixtures with `resume` on that one state, checking after each that the state, the record bytes, `git rev-parse HEAD` and the bare remote's refs are unchanged.
  - Then the fresh-pass, fixes, carry-over, rehearsal and cross-version paths (Matrix), plus IA1 and IA2.

**Acceptance Criteria:**
- **AC1 (the stop names the candidate; REL-7):** **Given** every automated gate passed, **when** `next` reaches `hands-on`, **then**:
  - it prints the stop line with the candidate branch, its full SHA, the record path and the `resume` command, and exits 4;
  - the committed record reads the waiting `Result:` text, with a `hands-on | waiting` row;
  - the record holds no `## Hands-on pass` section.
- **AC2 (the resume refusal; REL-7):** **Given** the stop, **when** `resume` runs with no section, or with each bad-grammar fixture of the Matrix, on that one state, **then**:
  - it exits 2 with the Matrix's `REFUSED hands-on` line;
  - the state, the record bytes, the checkout's HEAD and the remote's refs are unchanged;
  - no ASK is printed.
- **AC3 (a fresh pass; REL-7, CON-5):** **Given** a valid fresh pass, **when** `resume` runs, **then**:
  - all findings `deferred` (or none) gives `PASS hands-on`, with the row as in the Matrix, and the next `next` ends with the end text;
  - one `fixed` finding gives `FAIL hands-on` with the exact re-cut command;
  - `Result: fail` or an `open` finding gives `FAIL hands-on`.
  - No line or record says `pass` for the release.
- **AC4 (the pass time is not counted; REL-3):** **Given** a 7,200 s jump on the clock seam between the stop and the resume, and known ASK windows, **when** the steps end, **then** `Hands-on time:` equals the ASK windows' sum.
- **AC5 (a carry-over through a re-cut; REL-7, P29):** **Given** rc1's fresh pass with two `fixed` findings whose commits are on the throwaway's integration branch, **when** the author starts rc2 with `--from release/1.0.0-rc1 --pick <both>`, drives it to the gate, and the Planner's carry-over goes into rc2's record, **then** `resume` passes with a `carried over` row. Each of these is refused:
  - rc2 cut from the integration head ("needs a fresh pass");
  - a pick set that misses a fix or adds a non-fix commit;
  - rc2's `Cut from:` hand-edited to name the right picks while git shows others;
  - a carry-over with no `Note:`.
- **AC6 (rehearsal and 1.0.0; U-203):**
  - **Given** `Mode: rehearsal` planted in either record's `## Release sequence`, **when** a carry-over is judged, **then** it is refused with the rehearsal line.
  - **Given** 1.0.0 with a cross-version carry-over, **when** it is judged, **then** it is refused ("1.0.0 ends a build step and needs a fresh pass").
- **AC7 (other releases record a carry-over; P29):** **Given** a throwaway whose bare remote has `v1.0.0` and whose checkout holds 1.0.0 rc1's record with a fresh pass, **when** 1.0.1 rc1 reaches the gate with a cross-version carry-over and `Ends a build step: no`, **then** it passes. It is refused without that line, or with the tag missing.
- **AC8 (the script never writes the pass):** **Given** any run through the gate, **when** the record is read after each stop, **then** every `## Hands-on pass` byte in it came from the test's fixture (byte-compared). A scan of `release/release.sh` finds no writer of that title (no `record_write` call whose section file starts `## Hands-on pass`).
- **IA1 (Rule 1; consumes 11.5's real re-cut):** **Given** rc2 cut by the real `release.sh start --version 1.0.0 --from release/1.0.0-rc1 --pick <both fixes>`, **when** the gate judges the carry-over, **then** it reads the `Cut from:` line that 11.5's stop routine wrote into rc2's record (no test writes that line, except in AC5's forged case), and the `carried over` row names the same picks.
- **IA2 (Rule 1; consumes 11.3's real `record_write`):** **Given** a pass section in the record, **when** later stops rewrite `## Release sequence` (the PASS row, the end of the steps), **then** `## Hands-on pass` and the other gates' sections stay byte-identical, and `release.sh status` still reads the state.
- **Standing:** every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-29:** `release/` and `release/records/<version>/` are Lane A's; this is the release sequence's hands-on gate. Step epics merge only once `release/1.0.0-rc1` exists, which this story never creates outside a throwaway.
- **AD-23:** the cut commit changes only `src/module.xml` and the force-added `src/ocutalon/csp/`. The carry-over check relies on that.
- **AD-22:** throwaways only; nothing goes to a registry; no key.
- No criterion contradicts an AD.
- Product default 2 (no false all-clear): every non-pass is `FAIL` or `REFUSED`, and the end text says "not a release".

**The pass record (golden; written by the Contest Planner).** A fresh pass:
```
## Hands-on pass

Result: pass
Candidate: 1.0.0 rc1, release/1.0.0-rc1 at <40-hex sha>
Routes: web, telegram
Phone look: skipped
Findings:
- F1: fixed <40-hex sha> <what was found and how it was fixed>
- F2: deferred <what was found, and the Contest Planner's reason to defer it>
```
- `Findings: none` stands for an empty list.
- `- F<k>: open <text>` means a finding not yet handled.
- `Result:` is `pass`, `fail` or `carried over`.
- Other lines (for example the date, 38.3's TLS handshake or its timings) are allowed and ignored.

A carry-over:
```
## Hands-on pass

Result: carried over
Candidate: 1.0.0 rc2, release/1.0.0-rc2 at <40-hex sha>
Carried from: 1.0.0 rc1, release/1.0.0-rc1 at <40-hex sha>
Note: <the Contest Planner's note>
```
A cross-version carry-over also holds `Ends a build step: no`.

**Fixed texts (new public-facing text for the lead to rule; product default 3; records are committed to the public repository):**
- Stop line: `STOPPED hands-on install release/<v>-rc<n> at <sha> and run the hands-on pass; record it under "## Hands-on pass" in <record>, then run: release/release.sh resume --version <v> --rc <n>`
- Waiting result: `Result: stopped at hands-on: every automated gate passed; waiting for the Contest Planner's hands-on pass on release/<v>-rc<n> at <sha> (not a release)`
- End result: `Result: stopped after hands-on: every gate passed; no step after the gates has run (not a release)`
- Rows:
  - `hands-on | waiting | install release/<v>-rc<n> at <short sha> for the Contest Planner's hands-on pass`
  - `hands-on | pass | the Contest Planner's pass on <short sha>: routes web, telegram; <k> findings, all deferred; phone look <done|skipped>`
  - `hands-on | carried over | from <v> rc<m> at <short sha>; this candidate adds only the recorded fixes <short shas>`
  - `hands-on | fail | <detail>`
- FAIL details:
  - `the fixes are not in this candidate: re-cut with release/release.sh start --version <v> --from release/<v>-rc<n> --pick <sha>...`
  - `the hands-on pass has open findings: F<k>...`
- REFUSED details:
  - `no hands-on pass for release/<v>-rc<n> at <sha> in <record>`
  - `the hands-on pass names another candidate`
  - `the hands-on pass must cover the routes web and telegram`
  - `the hands-on pass has no phone look line (done or skipped)`
  - `finding F<k> has no fix, deferral or text`
  - `unknown hands-on result: <word>`
  - `needs a fresh pass: <reason>`
  - `a rehearsal record never carries a pass over`
  - `1.0.0 ends a build step and needs a fresh pass`
  - `a carry-over needs the Contest Planner's note`
- The section labels: `## Hands-on pass`, `Result:`, `Candidate:`, `Routes:`, `Phone look:`, `Findings:`, the finding words `fixed`, `deferred` and `open`, `Carried from:`, `Note:` and `Ends a build step: no`.
- None names a rival entry or entrant, says "IRIS Couch", or names OpenClaw.

**Decided in-stage (unattended block: small, reversible, in intent):**
1. **Refusal, not stop, after the first arrival.** At the first arrival, a section that judges `PASS` or `FAIL` is acted on at once, and anything else stops (exit 4, record written), so the record tells the Planner what to install. Every later attempt without a valid pass is a refusal (exit 2) that writes nothing, so polling never adds commits.
2. **A fix fails the candidate it was found on.** A fix cannot be inside an immutable candidate, so a pass with `fixed` findings fails that candidate. It prints the exact re-cut command whose candidate can then carry the pass over (38.1's flow).
3. **Git checks the carry-over, not only the record line.** The record is a hand-editable file. "Only changes since that candidate are those fixes" is proved with patch-ids and the cut commit's paths.
4. **Carry-overs are not chained.** `Carried from:` must name a record holding a fresh pass. A later re-cut carries from that pass directly. To carry another fix, the Planner adds it as a `fixed` finding to the source pass.
5. **Every fresh pass covers web and Telegram** (REL-7: "Later passes include Telegram"). This holds for every version, so the gate has no version table.
6. **Which later release ends a build step is the Contest Planner's call.** The version number cannot tell, so a cross-version carry-over needs the Planner's explicit `Ends a build step: no` and a tagged source release. 1.0.0 is refused one outright. This is the safe reading of "other releases record a carry-over". Listed for veto with the labels above.
7. **The gate reads the record in the author's checkout, committed or not.** The Planner may commit it or leave it to the next stop's record commit.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.5's step list, `start --from --pick`, `Cut from:`, `Candidate:`, `Mode:`, the stop routine and the state (IA1, real);
  - 11.14's gate list, `record_field`, `candidate_clone`, the fixture driver and the exit-code conventions;
  - 11.3's `record_path` and `record_write` (IA2, real);
  - 11.5's `release_tags`.
- **Consumed-by:**
  - 11.16: its outward steps run after `hands-on`, and it reads the hands-on row's `pass` or `carried over` as passed. It replaces this story's end text.
  - 11.18: the rehearsal candidate's fixture pass record (a fresh pass in a `Mode: rehearsal` record) and its "refuses to resume until the fixture pass record is in the candidate's record".
  - Epic 38: Stories 38.1 (web) and 38.3 (Telegram) on `release/1.0.0-rc1` write the fresh pass the Planner records, and 38.1's re-cut path carries it over.

**Smaller is better.** Story 11.5's line has used 5 of its 6 split pieces. This story is one gate in one script plus its tests, so it is not split.

**Ledger inbox (Rule 17):** none (`LEDGER slice` for this key is empty).

**Previous story continuity:** 11.10 (done) touched web e2e only. There is nothing shared.

**Contended paths (U14):** none. The files are `release/release.sh`, `release/lib-release.sh` and `docker/tests/test-release-sequence.sh`, all Epic 11's. `ci/units.sh` is unchanged. There are no footprint extensions.

**CI budget (inference):** the hosted `checks` job's self-test grows by about 20 to 60 s. No IRIS group runs (`release/` and `docker/tests/test-*.sh` are not IRIS inputs).

## Verification

Run each command in its own foreground call, with `timeout: 600000`, from the worktree root. No IRIS stack and no lane lock are used. `release/release.sh` runs only inside the self-test's throwaway.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh` (or its `--cases` parts from Task 0, one per call) -- expected: exit 0; the throwaway is removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` If `lib-release.sh` changed: `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh` and `test-release-notes.sh`, one per call -- expected: exit 0.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash ci/changes.sh ci.yml` -- expected: exit 0, and no IRIS group for these paths.
- `(once)` `bash ci/checks.sh` in its parts, one per call -- expected: no `FAILED`.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: drop the record path from the stop line.
- AC2: write the record on a refusal.
- AC3: pass a fresh pass with a `fixed` finding.
- AC4: count the time between stop and resume.
- AC5: skip the patch-id compare, so the forged `Cut from:` case passes.
- AC6: accept `Mode: rehearsal` as the source.
- AC7: ignore `Ends a build step: no`.
- AC8: write a placeholder `## Hands-on pass` at the stop.
- IA1: read `Cut from:` from a test-written line.
- IA2: hand-roll the section write, dropping other sections.

**Shared surfaces:**
- The `STEPS` list, rows and `Result:` texts that 11.5's and 11.14's self-test pins; this story updates the hands-on pins.
- `lib-release.sh`'s function list, if `record_section_body` is added.
- The record's `## ` sections.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds and removes its own repositories, bare remotes, shims, state and records.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
