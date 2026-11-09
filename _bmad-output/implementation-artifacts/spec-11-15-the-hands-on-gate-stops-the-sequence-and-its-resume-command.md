---
title: 'Story 11.15: The hands-on gate stops the sequence, and its resume command waits for a pass or a carry-over'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '1f41365ed0f22e661fec5df63c2cfa36d050db6d'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The record-push FAIL line printed at the first hands-on stop tells the author to run release.sh resume, but resume now refuses (R1) until the Planner's section exists, so a failed push of the waiting record is offered again only when the sequence ends.
    evidence: |-
      stop_routine's FAIL text for a moved integration branch says "bring the checkout up to date and run release.sh resume"; at hands-on, resume returns REFUSED until a pass or carry-over is recorded (spec Decided 4 and 12). Reachable only when the integration branch moved during the first stop.
    location: >-
      release/release.sh stop_routine (record push FAIL text)
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 11.14 left `hands-on` as a stop that never passes: every `release.sh next` or `resume` at it stops again, re-commits the record and asks the record question again (`release/release.sh:1607-1617`). Nothing reads the Contest Planner's hands-on pass. The hand-cut records hold it only as prose (`release/records/1.0.0/rc4.md`, "## Hand gates", "Story 38.1 web pass: done on rc4"), and the daily records 1.0.1 to 1.0.4 hold no pass and no carry-over at all. So nothing can tell a pass for this commit from no pass, and nothing carries a pass over to a re-cut.

**Approach:** Define the smallest machine-readable form of the pass, a `## Hands-on pass` section that only the Contest Planner writes, and make `step_hands_on` read it.
- On first arrival the step stops, exactly as today, and adds one NOTE line with the section's form.
- After that, `resume` (the same command as `next`) refuses (exit 2, nothing written) until the section holds, for this candidate's commit, a pass with no fix outstanding, or a valid carry-over. Then the step passes and the sequence ends with 11.14's existing end text.
- A carry-over is valid in a fixes-only release (patch version), or in a re-cut made with `--from` from a passed candidate plus exactly the fixes that pass recorded.

## Boundaries & Constraints

**Always:**
- **11.5's and 11.14's conventions stay:** Bash 3.2, ASCII, mode 100755, `umask 077`, the main guard; `PASS|FAIL <step> <detail>` lines; `REFUSED <text>` with exit 2 and nothing written; exit codes 0, 1, 2, 4 and 5 keep their meaning; answers only from stdin; exactly two pushes; no value of the environment printed.
- **The Contest Planner writes the pass and the carry-over, never the script (REL-7).** `release.sh` only reads `## Hands-on pass` from the record file (`record_abs`, committed or not). It never writes, edits, completes or removes that section. No option, environment variable or answer writes a pass or skips the gate. The next record commit carries the Planner's section along, because `record_write` keeps other sections byte for byte (already met, pinned by `t_gate`).
- **A pass or carry-over counts only for this commit:** the section's `Candidate:` line must end with ` at <the cut's full sha>`, the same rule as 11.14's `gate_verdict`.
- **First arrival always stops** (exit 4, through 11.14's `stop_routine hands`), even when a valid section is already there. "Arrived before" means `rows.tsv` holds a `hands-on` row. States that 11.14's code left at `hands-on` therefore resume with no migration.
- **Feature or fixes-only comes from the version (the owner's version rule, AD-29 "Releases").** A version `x.y.0` adds a feature, so it needs a fresh pass on this candidate, or a re-cut carry-over. A version `x.y.z` with z > 0 is fixes-only, so a carry-over with the Planner's note is accepted.
- **A re-cut carry-over is checked against the sequence's own data.** The state's `from` (`release/<v>-rc<m>`), `from_sha` and `picks_full` come from `start --from ... --pick` and `step_cut`. The source record is `rc<m>.md` in the folder of this record, the same convention as `earlier_hands`. All of these must hold:
  - its `## Release sequence` reads `Mode: release`;
  - its `## Hands-on pass` reads `Result: pass` with `Candidate:` ending ` at <from_sha>`;
  - its `Fixes:` commits, resolved to full ids, equal this candidate's picks as a set.
- **Hands-on time stays the sum of the ASK windows** (already met). The gate reads the clock nowhere.
- **Extend, don't copy:** use `gate_verdict` and `record_field` (11.14), `refuse`, `record_relpath_or_abs` and `short_sha`; reuse the existing `stop_routine hands` and `end`. New code goes into new functions. `release/lib-release.sh` is not changed.
- **Tests run only in the self-test's throwaway repositories with a local bare remote and the existing shims.**

**Never:**
- Act outward in any form, here or in any test: no pull request, no push to origin, no tag pushed outside the throwaway, no publish; no contact with the demo host; no run of the real release sequence; no real model key (`ANTHROPIC_API_KEY` unset); no Telegram bot; no install from the public IPM registry.
- Record a pass or a carry-over from code, or add a way to (option, variable, answer, configuration key).
- Machine-check the pass's prose (routes, phone look, each finding's disposition). That stays the Planner's text under the section.
- Change `step_image` (around line 575), the header's "Needs bash" lines (48-52), `release/upgrade-harness.sh`, `ci/warm.sh`, `ci/units.sh`, `ci/iris.sh`, `release/lib-release.sh`, `.github/workflows/*`, or the self-test's Epic 0 lines (`:219` the shim's Dockerfile message, `:727` mkseed's archive list, `:1358` t_image's failed-build line, `:3222` t_static's `pip_pins` line).
- Build 11.16's outward steps or 11.18's rehearsal mode.
- Write `release/records/` of the real tree.

## I/O & Edge-Case Matrix

The REFUSED, NOTE, PASS and FAIL texts are under Design Notes, Public text, tagged R1-R9. `<c>` is the cut's full sha.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First arrival | `next` reaches `hands-on` with no `hands-on` row (with or without a section already written) | The STOPPED line (unchanged), then the NOTE line. Exit 4. Row `hands-on \| waiting`; record committed; ASK `record`. The sequence writes no `## Hands-on pass` | Answer `pass` or `yes` to the record question: no section written |
| No section | `resume` after the stop; the record has no `## Hands-on pass`, or the file is missing | R1, exit 2 | State, record, commits and remote unchanged |
| Another commit | `Candidate:` does not end with ` at <c>` (missing, short sha, one character cut or added) | R2, exit 2 | Nothing written |
| Unknown result | `Result:` not `pass` and not `carry-over` | R3, exit 2 | Nothing written |
| Pass, Fixes missing or bad | `Result: pass`, no `Fixes:` line or an empty one; or a token that `git rev-parse --verify --quiet <t>^{commit}` cannot resolve | R4 / R5, exit 2 | Nothing written |
| Fresh pass | `Result: pass`, this commit, `Fixes: none` | PASS P1, exit 0 through `stop_routine end` (record question); row `pass`; record `Result: stopped after hands-on: no step after the gates has run (not a release)` | -- |
| Pass with fixes | `Result: pass`, this commit, `Fixes: <commit>...` | FAIL F1 with the re-cut command (7-character shas in the order written). Exit 1; record `Result: failed at hands-on: ...` | The next `resume` reads the section again |
| Carry-over, no note | `Result: carry-over`, this commit, no `Note:` or an empty one | R6, exit 2 | Nothing written |
| Carry-over, feature release from the head | Version `x.y.0`, state `from` empty | R7, exit 2 | Nothing written |
| Re-cut carry-over | Version `x.y.0`, rc2 started with `--from release/<v>-rc1 --pick <f>`. rc1's record: `Mode: release`, a pass at rc1's sha, `Fixes: <f>`. rc2's section: carry-over with a note | PASS P3, row `carried over` | -- |
| Re-cut, bad source | rc1's record missing; or it reads `Mode:` other than `release`; it has no pass; it reads `Result: carry-over`; or its `Candidate:` names another commit | R8, exit 2 | Nothing written |
| Re-cut, other picks | rc1's `Fixes:` set differs from rc2's picks (one more, one fewer, or another commit) | R9, exit 2 | Nothing written |
| Fixes-only release | Version `1.0.1` (tag `v1.0.0` exists), carry-over with a note for this commit, with or without `from` | PASS P2, row `carried over` | -- |
| Options and variables | `resume --pass`, `resume --carry-over`; `OCUTALON_RELEASE_HANDS_ON=pass` and `OCUTALON_HANDS_ON_PASS=1` in the environment | `REFUSED unknown option` (already met: `release_main`) / R1, exit 2 | Nothing written |

</intent-contract>

## Code Map

**`release/release.sh`** (1909 lines at `b0bbd2d7`; the Planner reviews every hunk):
- `:4`: the header's steps line, which `cli_usage` (`:1621`, lines 2-7) prints. `:40`: the gates paragraph, whose last sentence is about hands-on.
- `:70` `refuse` (prints `REFUSED`, exit 2). `:79-80` `sget`/`sset`. `:83` `row_set`; `rows` is `<state>/rows.tsv`, with `id<TAB>result<TAB>detail` lines. `:63` `TAB`.
- `:136-150` `ask`: the only clock reads besides `step_ci`'s first check. `:167` `earlier_hands`: the record folder convention, `dirname "$(record_abs)"`/`rc<m>.md`.
- `:200` `record_abs`. `:207-244` `record_render` (`Cut from:` uses `from`, `from_sha`, `picks_full`). `:434` `record_relpath_or_abs`.
- `:340-431` `stop_routine`: kinds `hands` (`:348`, exit 4) and `end` (`:343`, the end text), both used as they are.
- `:450` `step_fail`, which strips local paths from the detail.
- `:467-560` `step_cut`: `--from` is cut from `from_sha`; each pick must be an integration-branch commit, cherry-picked with `-x`; `sset picks_full` holds the full ids, space-separated (`:553`).
- `:1110` `short_sha`. `:1160-1175` `gate_verdict <heading> <mode|->`: sets `GATE_RESULT`, `GATE_MODE` and `GATE_CAND`, and returns 0 for a pass on this commit, 1 for another result or mode, 2 for another commit.
- `:1607-1617` `step_hands_on`: the function to change; `return 6` maps to `stop_routine hands` in `cmd_next` (`:1729-1733`).
- `:1696-1745` `cmd_next`: 0 records the row, then the next step, or `done`, which leads to `stop_routine end`. 1 or anything else gives `stop_routine failed`.
- `:1820-1828` `start --from` accepts only `release/<v>-rc<m>`. `:1872-1897` `release_main`: unknown options for `next`/`resume`/`status` are refused.

**`release/lib-release.sh`** (read only): `record_section` `:439` (a `## ` section, up to the next `## ` or `# `), `record_field` `:448` (the text after `<field>: ` on the first such line), `record_write` `:409` (keeps other sections byte for byte).

**Records (evidence for the format):**
- `release/records/1.0.0/rc4.md` holds the pass as prose under "## Hand gates (Contest Planner, 2026-11-04)" and in "## Release result".
- `1.0.1/rc1.md`, `1.0.2/rc1.md`, `1.0.3/rc1.md` to `rc3.md` and `1.0.4/rc1.md` hold no pass or carry-over.
- `1.0.3/rc2.md` is a `--from rc1 --pick` re-cut. Its `Cut from:` line reads `release/1.0.3-rc1 at <sha>, then <picks> cherry-picked from ...`.

**Self-test `docker/tests/test-release-sequence.sh`** (4312 lines):
- Header rule list `:44-77` (`handson` `:74`). Rule calls `:4271-4305`.
- Helpers:
  - `newcase` `:792`, `flag` `:810`, `clockfile` `:814`, `rs` `:820`, `Y`/`N` `:831`, `snap` `:835`;
  - `rec_file` `:841` (1.0.0 only), `cand` `:842` (1.0.0 only), `rhead` `:843`;
  - `GATE_ORDER` `:908`, `run_steps` `:920`, `to_step` `:937`, `fixes_case` `:1243` (rc1 cut, then two integration fixes `FIX1`/`FIX2`, pushed);
  - `sect` `:2664`, `sdir1` `:3261`, `row_of` `:3262`.
- `t_handson` `:3909-3938`: the full drive to `hands-on`. `:3928-3935` pin "each later next stops the same way", which this story changes. `:3937` pins "the hands-on step asks nothing".
- `t_resume` `:1696-1698` pins "the hands-on gate stops again: exit 4", which this story changes.
- `t_gate` `:1826`: a comment says the end is unreachable.
- State jumps use `env_set` in a subshell that sources `lib-release.sh` (`t_gate` `:1827-1831`).

## Tasks & Acceptance

**Execution:**
- `release/release.sh` -- four hunks; no other line changes:
  - **Header `:4`:** `(Stories 11.15, 11.16 and 11.18 extend STEPS)` becomes `(Stories 11.16 and 11.18 extend STEPS)`.
  - **Header `:40`:** replace its last sentence (`hands-on stops: the Contest Planner's pass is not recorded by this sequence.`) with the Public text sentence.
  - **New function `handson_verdict`,** just above `step_hands_on`, with a contract comment that states the section's form (Public text):
    - It judges the record's `## Hands-on pass` for the state's `cand_sha`, in the Matrix's order.
    - On a refusal it calls `refuse` (R1-R9).
    - It returns 0 with `STEP_ROW`/`STEP_DETAIL` set for P1-P3, and 1 through `step_fail hands-on` for F1.
    - It reads the pass branch with `gate_verdict "## Hands-on pass" -`, then `record_field` for `Fixes` and `Note`. It reads the source record with `record_field` (`## Release sequence` `Mode`, then `## Hands-on pass` `Result`/`Candidate`/`Fixes`).
    - It resolves commits with `git rev-parse --verify --quiet "<t>^{commit}" < /dev/null`, and compares sets with `sort -u`.
    - The feature test is `${version##*.}` = `0`.
    - Every text taken from the record (a `Fixes:` token, a `Note:`) goes through `detail_clean` before it is printed. The PASS line prints the cleaned `STEP_DETAIL`, as `step_fail` does for FAIL.
  - **`step_hands_on`:**
    - When `rows.tsv` has no `hands-on` row, it keeps today's body (row `waiting`, the STOPPED line) and adds the NOTE line, then returns 6.
    - Otherwise it returns what `handson_verdict` returns.
    - Its comment states this contract. It asks nothing.
- `docker/tests/test-release-sequence.sh` -- add no `CHECK_SCRIPTS` entry. Add one helper and one rule, and update three rules:
  - **Helper `hands_put <record file> <line>...`:** writes a `## Hands-on pass` section with the given lines through `record_write`, in a subshell that sources `lib-release.sh`. This is the fixture of the Planner's record. Give it a sibling that drops the section (`awk`), for the "no section" cases.
  - **`t_handson` (full drive, AC1, AC3, IA1):**
    - Keep its first-stop assertions, and add the NOTE line, "no `## Hands-on pass` in the record", and "the answer `pass` writes none".
    - Replace `:3928-3935`: `resume` with no section gives R1, exit 2, and nothing written. Use a cksum of the state files, the record, `git log` and the remote refs, as `t_resume` `:1683` does.
    - Then add a fresh pass with `Fixes: none` and run `rs "$Y" resume`. Expect exit 0, P1, the row, the end `Result:`, `RESULT stopped`, no `RESULT pass` and no `released`, and `status` reading `next done`.
    - The bare remote's integration branch must hold the record with the section byte for byte (`sect` on `git --git-dir="$R" show`), and every commit the record push adds must change only the record.
    - Extend the "asks nothing" pin to `handson_verdict`.
  - **`t_resume` `:1696-1698`:** the second hands-on call is R1, exit 2.
  - **`t_gate` `:1826`:** the comment says the test reaches the end through the state.
  - **New rule `carryover` (`t_carryover`; AC2, AC4-AC8),** in three cases, each reaching `hands-on` by a cut and a state jump (`env_set ... next hands-on`):
    - (a) `1.0.1`, with `v1.0.0` tagged in the checkout and pushed to the bare remote, and the seam clock set:
      - the first stop;
      - each refusal row of the Matrix, the options and the variables, each followed by an unchanged snapshot;
      - a carry-over with a note: P2 and the row;
      - "Hands-on time: 15 s for this candidate" across a 7,990 s jump between the stop and the resume.
    - (b) `1.0.0` rc1 through `fixes_case`:
      - a valid pass (`Fixes: none`) already written before the first arrival still stops (exit 4);
      - carry-over: R7;
      - a pass with no `Fixes:`: R4;
      - `Fixes: deadbeef`: R5;
      - `Fixes: $FIX1`: F1 (exit 1, the record's `failed at hands-on`, `--pick ${FIX1:0:7}`), with the record question answered yes, so the checkout is level for the next start.
    - (c) In the same case:
      - start rc2 with `--from release/1.0.0-rc1 --pick "$FIX1"`, cut, jump, stop, then a carry-over with a note. rc1 still has steps left, so every call names `--version 1.0.0 --rc 2`;
      - edit rc1's record in the working tree, one variant per `resume` (Fixes `$FIX1 $FIX2`: R9; `Mode: rehearsal`: R8; `Result: carry-over`: R8; another sha: R8), each with nothing written;
      - restore rc1's record (`git checkout --`), then expect P3 and the row `carried over`.
  - **Header rule list:** reword `handson` and add `carryover` (Public text). Add `rule carryover t_carryover` after `rule handson t_handson`.
- After the edits, run the Verification commands, then `bash docker/tests/test-boundaries.sh` once.

**Approved 11.14 text items (DW-1008, DW-1009; the Planner's ruling `planner-2026-11-09-11.15` item 4), worked in this implement:**
- [x] [Review] DW-1008: keep as written (now approved): `FAIL <gate> the clone of release/<v>-rc<n> failed`, `FAIL <gate> the tags could not be copied into the clone`, `FAIL <gate> the clone's HEAD is not the cut commit`, `FAIL <gate> the web dependencies cannot be installed here`, `FAIL eval the result could not be kept for the notes`, and the `-` placeholder for an empty value (`Result: -, Mode: -`). No code change; no test change beyond what pins them today.
- [x] [Review] DW-1008 — `release/release.sh` `step_upgrade` (the remote-tags read) — when the remote's tags cannot be read, print exactly `FAIL upgrade the tags of <remote> could not be read; run git fetch --tags <remote>, then release.sh next` instead of the `missing: unreadable` value; update the self-test case that pins `missing: unreadable`.
- [x] [Review] DW-1008 — `release/release.sh` `step_eval` (the commit check) — print exactly `FAIL eval the result is of commit <the result's commit as written, or ->, not of the candidate <full sha>` (the full 40-character cut sha), so a near-miss never prints two equal shorts; update the `eval` rule's assertion.
- [x] [Review] DW-1008 — `release/release.sh` `step_upgrade` — when the harness's `build` phase exits 1, print exactly `FAIL upgrade the harness's build failed: <its line>` (exit 2 from a phase keeps `the harness refused <phase>: <its line>`); pin it in the `upgrade` rule.
- [x] [Review] DW-1009 — `release/release.sh` `step_eval` (the RUN line) — when the author's repository has a lane lock folder (`live_lock_dir` of the author's checkout resolves), print exactly `RUN cd <absolute clone path> && OCUTALON_LOCK_DIR=<lock folder> bash eval/run.sh --release-candidate`; otherwise keep today's line; pin both forms in the `eval` rule.

**Acceptance Criteria:**
- **AC1 (stop and name the candidate; REL-7).** Given every automated gate passed, when `next` first reaches `hands-on`, then it prints the STOPPED line and the NOTE line naming `release/1.0.0-rc1` and its full sha, exits 4, and commits the record with the `waiting` row. No `## Hands-on pass` is written, even when the record question is answered `pass`. With a valid section already written, the first arrival still stops.
- **AC2 (the resume command refuses).** Given the stop, when `resume` runs with each refusal input of the Matrix, then it prints that row's REFUSED line and exits 2, and the state files, the record, the checkout's commits and the remote's refs are unchanged.
- **AC3 (a fresh pass goes on).** Given a section `Result: pass` for this commit with `Fixes: none`, when `resume` runs, then it prints P1. The row reads `pass`, and the record's `Result:` is the end text. The record question follows (exit 0 on `no`), and the committed record holds the Planner's section byte for byte.
- **AC4 (a pass with fixes fails the candidate).** Given a pass for this commit with `Fixes: <commit>`, when `resume` runs, then it prints F1 with the `--from ... --pick` command, exits 1, and records `failed at hands-on`. A later `resume` reads the section again.
- **AC5 (a feature release needs a fresh pass; P29).** Given version `1.0.0` cut from the integration head, when the section is a carry-over with a note, then R7, exit 2.
- **AC6 (a re-cut carries the pass over).** Given rc2 cut with `--from release/1.0.0-rc1 --pick <f>`, and rc1's record holding a pass on rc1's commit with `Fixes: <f>` and `Mode: release`, when rc2's section is a carry-over with a note, then P3, with the row `carried over`. Given each bad source or other picks of the Matrix, then R8 or R9, with nothing written.
- **AC7 (other releases record a carry-over).** Given version `1.0.1`, when the section is a carry-over with a note for this commit, then P2, with the row `carried over`.
- **AC8 (the pass is not hands-on time; REL-3).** Given the seam clock (`1000 1010 9000 9005`), with the record question answered at the stop and after the resume and a 7,990 s jump in between, when the sequence ends, then the record reads `Hands-on time: 15 s for this candidate`.
- **IA1 (the record push carries the Planner's section).** Given the fresh-pass resume of AC3 with the record question answered `yes`, when the record is pushed, then the bare remote's integration branch holds `## Hands-on pass` byte for byte, and every commit the push adds changes only the record.
- **Standing.** Every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

- **planner-2026-11-09-11.15** (the Contest Planner's ruling, relayed by the orchestrator, 2026-11-09): APPROVED as written:
  1. the console text: the NOTE line, R1-R9, P1-P3 and F1 (`### Public text`);
  2. the `## Hands-on pass` record form, which only the Contest Planner writes;
  3. Decided 2: `x.y.0` needs a fresh pass, or a carry-over only to a `--from` re-cut whose picks equal the recorded fixes; `x.y.z` with z above 0 accepts a carry-over with the Planner's note; a rehearsal record never carries a pass;
  4. Story 11.14's DW-1008 and DW-1009 texts ride in this story's implement as `[Review]` items (below, under Tasks & Acceptance).

## Review Triage Log

### 2026-11-09 - Review pass
- verdicts: 26 findings - high 0, medium 4, low 17, false 5, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: spec decisions 13 and 14 (bad source Fixes gives R8; Fixes tokens read with set -f) had no test - tests added (a glob, an option-like token, a bad and a missing source Fixes), mutations recorded.
  - `[low]` `[reject]` Blind: handson_fixes accepts any revision expression - the spec states R5 for a token that git rev-parse cannot resolve; HEAD or a branch name resolving is the specified reading.
  - `[low]` `[reject]` Blind: the candidate's own record Mode is not checked - the spec checks only the source record's Mode; rehearsal mode is Story 11.18's.
  - `[low]` `[reject]` Blind: a fixes-only carry-over is checked only for a note - AC7 specifies exactly that.
  - `[low]` `[reject]` Blind: the NOTE prints only at first arrival and shows a basename for an outside record - the spec fixes the NOTE at the stop and record_relpath_or_abs is existing 11.14 behaviour.
  - `[low]` `[reject]` Blind: the new RUN line is not shell-quoted - the approved text is exact and matches the existing unquoted `cd` form.
  - `[low]` `[reject]` Blind: only build exit 1 reads "build failed" - the approved item names exit 1 and keeps exit 2; other codes keep today's text, and new wording would be unapproved public text.
  - `[low]` `[patch]` Blind: the "never writes the section" pin is a weak grep - a non-empty guard added; the behavioural pin is IA1.
  - `[low]` `[defer]` Edge: the record-push FAIL hint says run resume, which now refuses at hands-on until a pass exists - real, only when the branch moved during the stop; changing the text needs new approved wording; deferred.
  - `[medium]` `[patch]` Edge: a patch number with leading zeros (1.0.00, accepted by start) read as fixes-only - the feature test is now arithmetic (10#); a 1.0.00 case and a mutation line added.
  - `[low]` `[reject]` Edge: duplicate Fixes tokens or fixes already in the candidate - a recorded fix means fail by the spec (F1); a duplicate pick is the Planner's text.
  - `[low]` `[reject]` Edge: other build exit codes read "refused" - duplicate of the build exit row above.
  - `[low]` `[reject]` Edge: a relative or spaced lock folder in the RUN line - candidate_lock_dir is the existing 11.14 helper; the text is approved verbatim.
  - `[low]` `[reject]` Edge: a fixes-only carry-over has no earlier-pass check - duplicate of the AC7 row above.
  - `[low]` `[patch]` Edge: the source-text pin is weak - same fix as the Blind row above (non-empty guard).
  - `[false]` `[reject]` Edge: extra helper handson_fixes and the eval and upgrade hunks go beyond four hunks - the Tasks list the five [Review] items, and the spec asks for new code in new functions; the helper is one more function.
  - `[medium]` `[patch]` Gap: a fixes-only re-cut (with `from`) has no test - case (d) added: 1.0.1 rc2 from rc1 with a pick passes P2 on the note alone; mutation recorded.
  - `[medium]` `[patch]` Gap: the Fixes token guards are unpinned - same fix as the first row. The `-*` arm of the guard was dead code (git refuses `<token>^{commit}` with a leading dash anyway), so it was removed and decision 14 corrected.
  - `[low]` `[patch]` Gap: IA1 compares command-substituted text, blind to blank lines - the section is now compared as a checksum of its raw lines.
  - `[low]` `[patch]` Gap: the source-text pins pass vacuously if the functions are renamed - the extraction is asserted non-empty.
  - `[low]` `[patch]` Gap: the DW-1008 and DW-1009 changes have no mutation line - the four mutations were applied, red observed, reverted, and the lines written.
  - `[false]` `[reject]` Intent: a pass with fixes exits 1, not 2 - the Matrix row "Pass with fixes" specifies FAIL F1 and exit 1.
  - `[false]` `[reject]` Intent: ride-along edits to step_eval and step_upgrade - they are the five [Review] items approved in Tasks & Acceptance.
  - `[false]` `[reject]` Intent: the form is documented only in the NOTE, the header and a comment, and old records are not converted - the spec forbids writing the real records and lists the Planner's playbook as a PLANNER REPORT item.
  - `[false]` `[reject]` Intent: the tests reach hands-on by a state jump - the Tasks prescribe `env_set ... next hands-on`.
  - `[low]` `[reject]` Intent: a patch release's carry-over ignores `from` and picks - duplicate of the AC7 row above.

## Design Notes

**Already met (not rebuilt):**
- "It stops and names the candidate to install": the STOPPED line at `release.sh:1615` names `release/<v>-rc<n> (<short sha>)`, exits 4 through `stop_routine hands` (`:348`), and is pinned by `t_handson` `:3917`.
- "The time spent on the pass doesn't count toward the 15 minutes": hands-on time is the sum of the ASK windows only (`release.sh:44-45`, `ask` `:136-150`). The record line says "CI and the hands-on pass not counted" (`hands_line` `:186-195`). AC8 adds a pin across a clock jump.
- "The resume command": `resume` is `next` (`release.sh:18`, `release_main` `:1883`).
- A re-cut from the passed candidate plus fixes cherry-picked from the integration branch, "whose only changes since that candidate are those fixes": `start --from release/<v>-rc<m> --pick ...` and `step_cut` (`:467-560`) build the candidate as the source plus the picks plus one cut commit, and refuse a pick that is not on the integration branch.
- A record commit carries other sections byte for byte: `record_write`, pinned by `t_gate`.
- No option passes a gate: `release_main` refuses unknown options (`:1891`).
- 1.0.0's fresh pass: recorded by hand (`release/records/1.0.0/rc4.md`, "Story 38.1 web pass", "Story 38.3 Telegram pass"). `v1.0.0` is tagged, so `start` refuses 1.0.0.

**Built here.** The Planner today writes the pass as prose that nothing reads, and records no carry-over for the daily releases. This story adds the section's form, the refusal at `resume`, the pass and carry-over verdict, and the NOTE line that tells the Planner the form.

**Governing ADs (Rule 6):**
- **AD-29:** release rules. A daily release that adds a feature bumps the minor version, and one with only fixes bumps the patch (Decided 2). `release/` is Lane A's, and Epic 11 may change either lane's files.
- **AD-22:** tests run in throwaways, with no key and no registry.
- **AD-19:** no environment value is printed or recorded.
- **AD-28's principle** (no false all-clear): after a pass the sequence still ends "not a release" (11.14's end text).
- AD-23 and AD-25 are not used. No AC contradicts an AD.

**Decided in-stage (small, reversible, within intent):**
1. **The record form.** The records show no machine-readable pass, so this is the smallest form:
   - the heading `## Hands-on pass`;
   - `Result: pass|carry-over`;
   - `Candidate:` ending ` at <full sha>` (11.14's form);
   - for a pass, `Fixes: none|<commit>...`;
   - for a carry-over, `Note: <the Contest Planner's note>`.
   Findings (each with its fix or deferral), routes and the phone look stay the Planner's prose lines under it (REL-7). `Fixes:` is required, so a pass whose fixes are not in the candidate never goes on by omission.
2. **Feature or fixes-only comes from the version.** `x.y.0` needs a fresh pass or a re-cut carry-over; `x.y.z` (z > 0) accepts a carry-over with a note. This maps the owner's version rule (owner_fixed; AD-29 "Releases"; PRD REL-7: "each feature's hands-on pass runs on the first daily release candidate that ships it") onto the AC's "the release that ends a build step needs a fresh pass ... other releases record a carry-over". The set-aside plan's hand-written `Ends a build step:` line is dropped: the version decides it.
3. **The first arrival always stops**, even with a valid section (the AC's literal "stops"). The stop also commits the record and offers its push.
4. **"Refuses" is exit 2 with nothing written** (the header's meaning of 2). Unlike 11.14's re-stop, there is no record-commit churn on each try.
5. **A pass with fixes fails the candidate (exit 1).** Its fixes are not in it (REL-7: "with fixes for what that pass finds, before that step's release"), and a failed gate means a new rc (11.5). F1 prints the re-cut command.
6. **A carry-over source must hold a pass itself; there are no chains.** This follows the AC's "a re-cut from the passed candidate". For more fixes, the Planner re-cuts from the passed candidate with every recorded fix.
7. **Picks equal the recorded fixes as a set of full commit ids.** The order is free; the `--pick` order is the order they apply in.
8. **Rehearsal guard** (epic context: "A rehearsal record never carries a pass over to a real candidate"): the source record's `## Release sequence` must read `Mode: release`. `--from` already accepts only `release/` branches, and every pass is bound to a commit.
9. **"Arrived before" is the `hands-on` row in `rows.tsv`.** There is no new state key, and states left by 11.14 resume.
10. **The NOTE line at the stop** gives the Planner the exact `Candidate:` value (product default 3: keep it safe, make it convenient).
11. **The header's steps line drops 11.15**, which adds no step (text claims only what the code does).

**Decided in the implement pass (small, reversible, within intent):**
12. **Resume at `hands-on` no longer re-offers an unpushed record.** A refusal writes nothing, so a record push that failed at the first stop (a moved integration branch) is offered again only when the sequence ends after a pass. The `record` rule's "resume after the update" case now refuses (R1), has the Planner's pass written, and pins the push at the end.
13. **A source record whose `Fixes:` is missing or names a token that is no commit gives R8**, not R9: the pass on the source is unusable. R9 means only that the sets differ (`none` against one pick included).
14. **The `Fixes:` tokens are read with pathname expansion off** (`set -f` in `handson_fixes`), so `Fixes: *` names `*` and not a file.
15. **The DW-1009 `RUN` form is applied to the evaluation `RUN` line of the WAIT only.** The `--override` `RUN` line keeps its text, since the approved item names only the `--release-candidate` form.
16. **The `eval` rule's other-commit case** pins the full 40-character cut sha and, through an emptied `commit` field, the `-` form.
17. **The feature test is arithmetic** (`$((10#${version##*.}))` against 0), so a patch number written with leading zeros (`1.0.00`, which `start` accepts) is still a feature release.

**Extend, don't copy (Rule 2):**
- `handson_verdict` extends `gate_verdict`, called as it is, and `record_field`.
- The re-cut source path follows `earlier_hands`' folder convention.
- Refusals use `refuse`; the stop and the end reuse `stop_routine hands` and `end`.
- `candidate_clone` (named by 11.14's Consumed-by) is not needed: the Planner installs from the pushed branch, and the gate reads only the record and git objects of the author's checkout.
- `hands_put` reuses `record_write`, as `t_gate` sources `lib-release.sh`.

**Rules 1 and 2:**
- **Consumes:**
  - 11.14: `step_hands_on`, `gate_verdict`, `record_field`, `stop_routine hands` and `end`, and `cmd_next` cases 0 and 6;
  - 11.5: the `--from`/`--pick` state (`from`, `from_sha`, `picks_full`), `refuse`, and the ASK clock.
- **Consumed-by:**
  - 11.16: its first outward step follows a passing `hands-on` (`next_step hands-on`);
  - 11.18: the rehearsal's fixture pass record uses this form with the rehearsal commit's sha;
  - the Contest Planner, who writes the section at every daily release.
- **Integration AC:** IA1. The consumer is the record commit and push of `stop_routine end`; the observable effect is the bare remote's integration branch holding the Planner's section byte for byte.

**Ledger (Rule 17):** the inbox is empty; no entry is owned.

**release/** files changed (for the Planner's review):** only `release/release.sh`: header `:4` and `:40`, the new `handson_verdict`, and `step_hands_on`'s body and comment.

**Shared files and where (contended):**
- `release/release.sh`: `:4`, `:40`, and around `:1607` only. These are not near `step_image` (`:562-612`) or the "Needs bash" header lines (`:48-52`) that Epic 0's Story 0.15 edits.
- `docker/tests/test-release-sequence.sh`:
  - the touched parts: the header rule list, `t_resume` `:1696-1698`, the `t_gate` comment `:1826`, `t_handson`, a new helper and a new rule after `t_handson`, and the rule calls;
  - the untouched Epic 0 lines: `:219`, `:727`, `:1358` and `:3222`.
- `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` on 2026-11-09:
  - Epic 0 changes `ci/units.sh`, `ci/warm.sh`, `docker/tests/test-release-sequence.sh`, `release/release.sh` and `release/upgrade-harness.sh` (the lines above);
  - Epics 41, 17 and 32 change none of these paths.
- `footprint_extensions:` none. `release/**` is Epic 11's, and the self-test is Epic 11's own (Story 11.5).

**CI budget (REL-4):** no unit or group changes. The `release-sequence` self-test in the hosted `checks` job (20-minute limit) grows by about 20 to 40 s (inference: `handson` measured 12 s and `recut` 16 s on 2026-11-09). `carryover` has three cases and four cuts, with no full gate drive.

**PLANNER REPORT:**
- A real pass and resume on a real candidate cannot be proved without acting outward: a pushed candidate, an install with real keys, Telegram Web. The Contest Planner proves them at the first daily release after this merges.
- The Planner's own release playbook (under `.claude/`, owner-only, not touched here) should learn the `## Hands-on pass` form.

**Size.** One implement pass: `release.sh` about +90 lines; the self-test about +200. No split.

### Public text

All `release/release.sh` lines are printed on the author's console. Rows and `Result:` lines go into `release/records/<v>/rc<n>.md`. `<...>` are values; `<short>` is 7 characters and `<sha>` is 40.

- Header `:4` (also printed by usage): `# Steps, in order: cut, stubs, image, overview, ipm, ipmcheck, push, ci, eval, upgrade, rehearsal, notes, checklist, hands-on  (Stories 11.16 and 11.18 extend STEPS)`
- Header `:40`, the new last sentence: `hands-on stops and names the candidate to install; the Contest Planner records the author's hands-on pass (REL-7), or a carry-over, in the record's "## Hands-on pass" section, which this sequence only reads, and release.sh resume refuses (exit 2) until that section holds one for this commit (Story 11.15).`
- Unchanged and kept: `STOPPED hands-on every automated gate passed; install release/<v>-rc<n> (<short>) for the author's hands-on pass (REL-7); this sequence does not record that pass`, the `waiting` row and the hands-on `Result:` (11.14).
- NOTE (new, right after STOPPED): `NOTE hands-on the Contest Planner records it in <record> under "## Hands-on pass" with Result: pass and Fixes: none (or the fix commits), or Result: carry-over and Note: <why>, and Candidate: <v> rc<n>, release/<v>-rc<n> at <sha>; release.sh resume then reads it`
- R1: `REFUSED hands-on the record holds no "## Hands-on pass" section for release/<v>-rc<n> (<short>); the Contest Planner records the pass or the carry-over there first`
- R2: `REFUSED hands-on the "## Hands-on pass" section names another commit; its Candidate: line must end with " at <sha>"`
- R3: `REFUSED hands-on the "## Hands-on pass" section reads Result: <r or ->; only pass or carry-over goes on`
- R4: `REFUSED hands-on a pass needs a Fixes: line: none, or the commits that fix its findings`
- R5: `REFUSED hands-on the Fixes: line names <token>, which is not a commit of this repository`
- R6: `REFUSED hands-on a carry-over needs the Contest Planner's note on a Note: line`
- R7: `REFUSED hands-on <v> is a feature release, so it needs a fresh pass on this candidate; a pass carries over only to a re-cut from the passed candidate plus the fixes it recorded`
- R8: `REFUSED hands-on release/<v>-rc<m>, which this candidate was cut from, has no hands-on pass on <short of from_sha> in a release record`
- R9: `REFUSED hands-on the picks of this re-cut are not the fixes that the pass on release/<v>-rc<m> recorded`
- P1 (row `pass`): `PASS hands-on the author's hands-on pass (REL-7) on release/<v>-rc<n> (<short>) is recorded, with no fix outstanding`
- P2 (row `carried over`): `PASS hands-on the author's hands-on pass (REL-7) is carried over to release/<v>-rc<n> (<short>), a fixes-only release: <note>`
- P3 (row `carried over`): `PASS hands-on the author's hands-on pass (REL-7) on release/<v>-rc<m> (<short>) is carried over to release/<v>-rc<n> (<short>) with the fixes it recorded (<k>): <note>`
- F1 (row `fail`): `FAIL hands-on the pass on release/<v>-rc<n> recorded fixes that are not in this candidate; cut the next one with release.sh start --version <v> --from release/<v>-rc<n> --pick <short>...`
- Each row's detail is its PASS or FAIL text without the leading `PASS hands-on ` or `FAIL hands-on `, through `detail_clean` (300 characters at most). The record's `Result:` texts are 11.14's (`failed at hands-on: <detail>`, and the end text).
- **The record form the Contest Planner writes** (new; `release/records/<v>/rc<n>.md`). The lines can be in any order, and prose lines may follow:
  ```
  ## Hands-on pass
  Result: pass
  Candidate: <v> rc<n>, release/<v>-rc<n> at <sha>
  Fixes: none
  ```
  For fixes, write `Fixes: <commit> [<commit>...]`. A carry-over reads `Result: carry-over`, the same `Candidate:` line and `Note: <the Contest Planner's note>`.
- Self-test header rule list:
  - `handson   (AC8; Story 11.15 AC1, AC3, IA1) the stop at the hands-on gate: the line, the NOTE, the row, the record; a resume with no pass refuses; a fresh pass ends the steps and the record push carries the Planner's section`
  - `carryover (Story 11.15, AC2, AC4 to AC8) the resume's refusals, a pass with fixes, a feature release that needs a fresh pass, a re-cut that carries a pass over, a fixes-only release's carry-over, and the pass outside the hands-on time`
- No README or docs line changes.

## Verification

Run each command in its own foreground call with `timeout: 600000`, from the worktree root, with `TMPDIR` in the stage's scratch folder and `ANTHROPIC_API_KEY` unset. Each must finish in about 150 s. Measured on 2026-11-09 (plan, dev Mac): `handson` 12 s and `recut` 16 s, one rule per run. 11.14's code review measured these batches: `hands resume notes` 86 s; `gate secret first word pushes` 54 s; `gates` 117 s; `rehearsal handson static` 53 s; `ipm ipmfail` 53 s; `libs refusals cut` 29 s; `ipmcheck push record` 116 s. If a batch nears 120 s, split it and record the new batches here.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh handson carryover` -- expected: `PASS all rules` (about 40 s, inference).
- `(loop)` `bash docker/tests/test-release-sequence.sh resume gate` -- expected: `PASS all rules`.
- `(once)` the other rules that reach `hands-on`, one batch per call: `hands notes`, `secret first word pushes`, `gates`, `push record`, `static recut`, `ipm` -- expected: `PASS all rules` each.
  Implement-pass measures (dev Mac, 2026-11-09): `handson carryover` 19 s; `resume gate` 16 s; `resume gate eval` 36 s; `upgrade` 37 s; `hands notes` 50 s; `secret first word pushes` 30 s; `gates` 72 s; `push record` 42 s; `ipm recut static` 22 s; `libs refusals cut stubs ci rehearsal checklist` 113 s; `realgates` 43 s.
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.

**Mutations to apply (Rule 19; one per AC; record each as `mutation: ... → ...` here):**
- AC1: `step_hands_on` calls `handson_verdict` on first arrival. Expect red in `carryover` ("a valid section written before the first arrival still stops").
  mutation: the first-arrival test `if ! grep -q "^hands-on$TAB" "$rows"` replaced by `if false` -> `handson` red ("hands-on: exit", the STOPPED line, the NOTE) and `carryover` red ("1.0.1: the first stop"; (b)'s "a valid section written before the first arrival still stops" follows it); reverted, release.sh byte-identical.
- AC2: return 6 in place of `refuse` for "no section". Expect red in `handson` ("resume with no pass: exit 2", "nothing written").
  mutation: R1's `refuse` replaced by `return 6` -> `handson` red ("resume with no pass: exit", "the line", "nothing written", and the variables case); reverted.
- AC2: the ` at <sha>` suffix test removed. Expect red in `carryover` (the near-miss shas).
  mutation: R2's `*) refuse ...` branch replaced by `*) ;;` -> `carryover` red ("no Candidate line", "a short sha", "one character cut", "one character added", "another commit"); `handson` stays green; reverted.
- AC3: the P1 branch refuses with R4 instead of passing. Expect red in `handson` ("a fresh pass: exit 0", P1).
  mutation: `refuse` of R4 added before the P1 row -> `handson` red ("a fresh pass: exit", the line, the row, the end result, status); reverted.
- AC4: F1 returns 0. Expect red in `carryover` ("a pass with fixes: exit 1").
  mutation: F1's `return 1` replaced by `return 0` -> `carryover` red ("a pass with fixes: exit", the record, "a later resume reads the section again"); reverted.
- AC5: the feature test forced false. Expect red in `carryover` (R7).
  mutation: `if [ "${version##*.}" != 0 ]` replaced by `if true` -> `carryover` red ("a carry-over in a feature release cut from the head": exit, line, nothing written, and the R4 cases after it); reverted.
- AC6: the picks-versus-fixes comparison skipped. Expect red in `carryover` (R9). The `Mode: release` test skipped: red in `carryover` (R8, rehearsal).
  mutation: `[ "$want" = "$got" ] || refuse` replaced by `true || refuse` -> `carryover` red ("rc1 recorded more fixes", "rc1 recorded another fix"); reverted.
  mutation: the source record's `Mode` test replaced by `:` -> `carryover` red ("rc1 is a rehearsal record"); reverted.
- AC7: the patch-release branch requires `from`. Expect red in `carryover` (P2).
  mutation: the patch branch's condition made `[ "${version##*.}" != 0 ] && [ -n "$(sget from)" ]` -> `carryover` red ("1.0.1: the carry-over" exit 2, line, row, end result, time); reverted.
- AC8: `hands_add $(( $(clock) - <stop time> ))` added in `handson_verdict`. Expect red in `carryover` ("Hands-on time: 15 s").
  mutation: `hands_add $(($(clock) - 1010))` added before the carry-over row -> `carryover` red ("1.0.1: hands-on time is the two windows only"); reverted.
- IA1: `handson_verdict` rewrites the section (`record_write` of a changed copy). Expect red in `handson` ("byte for byte on the remote").
  mutation: the P1 branch rewrites the section with an extra line through `record_write` -> `handson` red ("IA1: the section is on the remote byte for byte", "IA1: the section in the checkout is the Planner's byte for byte", "the hands-on code never writes the section"); reverted.
- Review-pass pins (Rule 19; each applied on `release/release.sh`, red observed, reverted byte-identical):
  - AC5 (leading zeros): mutation: the feature test back to the string compare `[ "${version##*.}" != 0 ]` -> `carryover` red ("1.0.00 is a feature release").
  - AC7 (a fixes-only re-cut): mutation: the patch branch made to require no `from` (`&& [ -z "$(sget from)" ]`) -> `carryover` red ("1.0.1 re-cut: the carry-over").
  - Decision 14: mutation: `set -f` removed from `handson_fixes` -> `carryover` red ("a glob is no commit", it names a file of the checkout).
  - Decision 13: mutation: the source record's `handson_fixes` failure ignored -> `carryover` red ("rc1 names a fix that is no commit": R9 where R8 is expected).
  - F1 order: mutation: `HANDS_SHORTS` built in reverse -> `carryover` red (F1 with two fixes, and with one the trailing space).
  - DW-1008 eval commit: mutation: `$cand` back to `$short` in the text -> `eval` red. DW-1009: mutation: `lockdir=` forced empty -> `eval` red ("not run: the lines (a lane lock folder resolves)"). DW-1008 build: mutation: the build-failed test on exit 9 instead of 1 -> `upgrade` red. DW-1008 tags: mutation: the unreadable-tags branch disabled (`&& false`) -> `upgrade` red ("(QA) unreadable remote tags").

**Shared surfaces:**
- `step_hands_on`'s behaviour on a later `next` or `resume` (`t_handson`, `t_resume`);
- the hands-on row results (`waiting`, `pass`, `carried over`, `fail`);
- the end `Result:` text, now reachable (`t_gate`);
- the `## Hands-on pass` record form (11.16's and 11.18's fixtures);
- the console lines above;
- the self-test's rule list and header;
- `release.sh` header lines 4 and 40 (usage prints lines 2-7).
- Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `step_hands_on` stops on first arrival (the `hands-on` row is missing from `rows.tsv`) and adds the NOTE line with the section's form. Every later `next` or `resume` calls the new `handson_verdict`, which reads the record's `## Hands-on pass` section for the cut's full sha: R1 to R9 refuse (exit 2, nothing written), P1 to P3 pass (rows `pass`, `carried over`), F1 fails a pass that records fixes. The sequence ends with 11.14's end text. The script never writes the section (REL-7). The five approved DW-1008 and DW-1009 text items were worked as written.

**Files changed.**
- `release/release.sh`: header lines 4 and 40; new `handson_fixes` and `handson_verdict`; `step_hands_on`; `step_eval` (the commit text, the lane-lock RUN form); `step_upgrade` (the unreadable-tags text, the build-failed text).
- `docker/tests/test-release-sequence.sh`: helpers `hands_put`, `hands_drop`, `hsnap`, `hands_refused`; `t_handson` rewritten; new rule `carryover` (cases a to e); `t_resume`, `t_gate`, `t_record`, `t_eval`, `t_upgrade` pins updated; header rule list.
- This spec: decided-in-stage 12 to 17, mutation lines, triage log.

**Review.** 26 findings: patches applied 7 entries (4 medium: the untested Fixes guards and source-Fixes R8, the leading-zero patch number, the untested fixes-only re-cut, and the group of weak source-text pins; plus 3 low), deferred 1 (the record-push hint after a moved branch, low), rejected 14 low or false with the reasons in the log above. Follow-up review recommended: true, because three medium entries were patched; the unverified risk is the new `10#` arithmetic and the added cases (d) and (e), which were proved only by this pass's self-test runs and mutations.

**Verification performed.** All with `ANTHROPIC_API_KEY` unset and a scratch `TMPDIR`: `handson carryover`, `resume gate`, `hands notes`, `secret first word pushes`, `gates`, `push record`, `static recut ipm eval upgrade`, `libs refusals cut stubs ci rehearsal checklist realgates` each `PASS all rules`; `docker/tests/test-boundaries.sh` passed. Every AC and the review pins have a recorded mutation (red observed, reverted byte-identical). Not run: `image`, `overview*`, `ipmcheck`, `ipmfail`, `ipmwait`, `ipmnet`, `ipmlib` (they do not reach hands-on and release.sh changed nowhere near them).

**Residual risks.** A real pass and resume on a real candidate cannot be proved without acting outward; the Contest Planner proves it at the first daily release. One behaviour change for the Planner: at hands-on, a record push that failed at the stop is offered again only when the sequence ends (deferred item). `release/release.sh` also carries a helper `handson_fixes` beyond the one function the spec names, for the Planner's hunk review.
