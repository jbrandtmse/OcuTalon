---
title: "Story 11.24: The README's IPM install works literally on a fresh build 154 and build 109 instance"
type: 'bugfix'
created: '2026-11-05'
status: 'done'
baseline_revision: '907dc7cb2a555572c5bd3a292fe2f89d331243e7'
baseline_commit: '907dc7cb2a555572c5bd3a292fe2f89d331243e7'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** A fresh AI Hub image (build 154 or build 109) has no IPM in %SYS, and the README's "Install it with IPM" section and `docs/install-ipm.md` give no command to load it; with IPM loaded in %SYS only, the single `zpm "enable -community"` they give maps IPM into USER but skips USER's repositories, so the USER install stops with "ERROR! No repositories are configured and enabled in this namespace." `docs/install-ipm.md` also still carries the pre-publication sentence and a local-repository reload path.

**Approach:** The README section and the install guide give, word for word, one measured command block: a pinned IPM 0.10.10 load line (the community registry's 0.10.10 installer), then `zpm "enable -map -ns USER"` and `zpm "enable -community"` in %SYS, then today's two install commands. The guide's sample outputs come from the plan's public-registry run (1.0.1), the stale sentence goes, `test-readme.sh`'s pins follow in place, and the implement stage proves the README block literally on fresh build 154 and build 109 throwaways, with committed evidence.

## Boundaries & Constraints

**Always:**
- README.md and `docs/install-ipm.md` change exactly as the two unified diffs in Design Notes, "Public text for approval" (apply them with `git apply`); no other user-facing wording. Commit only after the lead relays the Contest Planner's approval (the lead's gate).
- The IPM load line is exactly `IPM_LOAD` (Design Notes D1): the registry's pinned `/packages/zpm/0.10.10/installer`, never `latest`.
- Every changed pin in `docker/tests/test-readme.sh` is changed in place, never deleted; new pins are added; every self-test still flags its broken copy (Design Notes, "Pins changed").
- Evidence and all text: ASCII only; image refs written as `irishealth-community:<tag>` only; no host path, no IP address, no private registry host, no instance or container name, no secret.
- Live runs only on lane-B throwaways from the plain images, one at a time under the lane-B lock, web port 52802 on the loopback interface (Verification).

**Never:**
- No edit of `test-readme.sh` lines 37-45 (header), the `DOCKERFILE`/`dockerfile_p` area (about 130-165), `chk_licence` or `rule_licence` (Epic 34's regions); keep at least one unchanged line between this story's hunks and those: new `chk_ipm` checks go above its `# The linked page gives...` comment (about 1052), new `rule_ipm` self-tests above its `finish ipm` line.
- No change to README sections other than "Install it with IPM", to `docs/bridge-guide.md`, `docs/security-overview.md`, `docker/**` (except `docker/tests/test-readme.sh`), `Install/**`, `src/**`, `module.xml`, `release/**`, `ci/**`, `.github/**`.
- Never use OcuTalon's built image or `ocutalon-iris-base:*` for the live runs; never pull, tag, push or remove an image; never touch another lane's lock or containers.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh build 154 (case 1) | plain `irishealth-community:2026.3.0AI.154.0`, no IPM in %SYS, USER unmapped | README block pasted literally: IPM line ends `Load finished successfully.`; map step maps USER; `enable -community` prints `Mapping IPM repository in %SYS equivalently to USER`; USER run stops with the OCUTALON line; OCUTALON run ends `Activate SUCCESS`; `GET /ocutalon/` 200 | none |
| Fresh build 109 (case 1) | plain `irishealth-community:2027.1.0AI.109.0` | same as above | none |
| USER mapped first (case 2) | IPM loaded, then the old README's single `zpm "enable -community"` (USER mapped, repositories skipped; USER install fails "No repositories") | the whole README block (IPM line again, map, community) then both installs succeed; IPM line installs nothing new | none |
| Old single command | IPM in %SYS only, `enable -community` alone | `Skipping repository mapping of USER - IPM not mapped from source namespace.`; USER install `ERROR! No repositories are configured and enabled in this namespace.` | documented in the guide as why the order matters |

</intent-contract>

## Code Map

- `README.md` 157-180 -- "Install it with IPM" (the only section that changes). Line 159 intro, 161-163 the registry block, 165 the repositories warning (pinned as `IPM_WARNING`), 180 the link sentence. Epic 34 adds one bullet near 343 (another hunk).
- `docs/install-ipm.md` -- 3 intro, 7-8 "What you need" (7 is the build 154 bullet whose build 109 sentence `chk_docs` pins), 14-86 the registry section with the old `enable -community` output, 106-120 the USER sample, 137-178 the OCUTALON sample (`Reload START (/tmp/ocutalon-repo/ocutalon-0.1.0/)` at 149), 180 the stale sentence, 195 the folder-install paragraph that gains one sentence. Headings, the U-232 sentence (124) and every other line stay.
- `docker/tests/test-readme.sh` (1837 lines) -- header `ipm` 34-37 and `dev-only` 62; `dev_names` 859-868 (with its comment); `rule_dev_only` 1510-1534 (the heredoc of rows 1517-1524, `st_append` 1525); `H_IPM`/`IPM_WARNING` 1020-1021 and `chk_ipm` 1022-1058 (the `# The linked page gives...` block 1052-1057); `IPM_BULLET_START`/`IPM_SENTENCE` 1076-1077 and their use 1085-1087 in `chk_docs`; `rule_ipm` 1750-1765 (`finish ipm` 1764); `rule_docs` self-tests 1787-1788. Helpers: `section` (259), `st <label> <slot> <file> <awk> <checker>` (327; a no-op edit is itself a failure), `st_append` (342), `rule_begin` (366), `finish` (381), `dev_names_1` (903). Rules run at the end from `RULES` (1799), so a constant defined near `chk_ipm` is visible in `dev_names`.
- `docker/tests/test-cpf.sh` -- read only, must stay green: rule 9 `install_doc_ok` (DOC_PHRASES incl. 'IPM 0.10.10', `ERROR! <stop>`, STEP lines inside each Configure block in `Registry.Order()` order), rule 11 `ns_doc_ok` (exact refusal line once, 'Open an IRIS terminal in USER and load the package', 'USER is one on both IRIS for Health and IRIS build 154', 'run the command in USER instead'), rule 12 `registry_doc_ok` (registry heading before developers' heading; the FIRST `zpm "enable -community"` after the registry heading and before the first `zpm "install ocutalon"`; `RUNNING command: "enable -map -repos -globally"` inside a fence between them; the U-232 sentence; no `Node.js` before the developers' section). Measured: the proposed docs pass all of test-cpf.
- Other files that name IPM install commands (read only, unchanged): `release/ipm-install.sh` 1210-1219 (CI job: loads `docker/ipm/zpm-0.10.10.xml` with `ck-d`, then `enable -map -ns USER -q`, then a local file repository: an internal check, not the README path), `release/release.sh` 770-806 and `docker/tests/test-release-sequence.sh` 2371-2381 (packaging sessions), `docker/after-start.cos` (the image's own IPM step), `release/checklist.sh` 463 `CK_REGISTRY_TEXT` ("the README's two commands ran once against the registry...": out of footprint, see D9).
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` `Order()` and `src/preload/cls/OcuTalon/Install/Ipm.cls` `STOP` -- read only; identical at v1.0.1 and HEAD (measured), so the 1.0.1 registry samples satisfy test-cpf rule 9.
- `docker/ipm/zpm-0.10.10.xml` -- read only; differs from the registry's 0.10.10 installer only in `<TimeCreated>` (measured).

## Tasks & Acceptance

**Execution:**
- [x] `README.md`, `docs/install-ipm.md` -- apply the two diffs of "Public text for approval" exactly (`git apply`), after confirming with the lead that the Planner approved them. -- AC1-AC3
- [x] `docker/tests/test-readme.sh` -- make P1-P9 of "Pins changed" exactly; touch no other line. -- AC4
- [x] Live literal runs (Verification, once) on fresh build 154 and build 109 throwaways (case 1) and the case 2 run on build 154; tear down and release the lock after each, failures included. -- AC1, AC2
- [x] `_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md` -- new: for each run the image ref, `$ZVersion` build, the commands as extracted from README.md, the lines quoted in Verification, durations, and the plan's Task 0 table (Design Notes); no secret, path, IP, host or container name. -- AC1, AC2
- [x] `docs/install-ipm.md` sample blocks -- after the build 154 case 1 literal run, replace every sample block whose lines differ from that run's real output (timestamps and durations included) with the run's output, trimmed as in Design Notes; record which blocks changed in the evidence file; re-run `test-readme.sh` and `test-cpf.sh`. -- AC3 (Planner's approval condition 3)
- [x] This spec -- record Verification results and `mutation:` lines.
- [x] [Smoke] DW-760: the guide's sentence "The two commands give the same result when USER already had IPM." is false when IPM was installed in USER itself — `docs/install-ipm.md:56` — the lead's smoke (2026-11-05, fresh build 154, the IPM line run in USER, then README blocks 1-2 in %SYS literally) printed `Skipping IPM mapping of USER - IPM already installed.` and `Skipping repository mapping of USER - IPM not mapped from source namespace.`; USER's `zpm "repo -list"` gave `No repositories found.` and block 3 stopped with `ERROR! No repositories are configured and enabled in this namespace.`; then `zpm "enable -community"` run in USER set up the registry there and blocks 3 and 4 succeeded (`Activate SUCCESS`, page 200). Fix: replace that one sentence with the Planner-approved text recorded under Spec Change Log (nothing else in README or the guide changes); add a whole-line-or-substring pin for the new text in `chk_ipm` (page side) with a self-test above `finish ipm` that removes it; re-run that case literally on a fresh build 154 throwaway (the IPM line in USER, README blocks 1-2 in %SYS, the guide's new USER command, blocks 3 and 4, page 200) and add it to the evidence file as Run 4. -- AC3
- [x] [CI] checks: `docker/tests/test-release-notes.sh` rule `static` red — `names_outside_section on README.md: got 'README.md:162', wanted ''` — https://github.com/jbrandtmse/OcuTalon/actions/runs/42121035820 (head df640ba8; reproduced locally). Its line 913 mirrors the README's own developer-section rule (`dev_names` of test-readme.sh), which since this story exempts exactly the IPM load line (`IPM_LOAD`); the mirror lacks the exemption. Fix, in `docker/tests/test-release-notes.sh` only (a footprint extension, ruled by the orchestrator — see Spec Change Log): the `static` assertion at 912-913 drops a hit only when that README line equals test-readme.sh's `IPM_LOAD` value word for word (read from test-readme.sh's `IPM_LOAD='...'` line, one source; fail loudly if it is not found), so any other line, a changed load line included, is still reported; update the header comment at line 29 to say so. Touch nothing else in that file (Epic 39 changed its line ~993: keep at least one unchanged line between). Never edit `lib-scan.sh` or `release/**`. Demonstrate the two mutations the ruling requires (the load line in README.md changed by one character → `FAIL static` still reports it; the `IPM_LOAD='...'` line removed or renamed in test-readme.sh → the static rule fails loudly naming the missing value), plus a second `##class(` line outside the section → red; each reverted byte-identical; write their `mutation:` lines. Re-run every script under `docker/tests/` that copies or reads README rules (find them with `grep -ln 'dev_names\|IPM_LOAD\|names_outside_section' docker/tests/*.sh`): at least `test-release-notes.sh`, `test-readme.sh`, `test-cpf.sh`. -- AC1 (CI)

**Acceptance Criteria:**
- AC1 (literal install, both builds). Given fresh throwaways from the plain build 154 and build 109 Health images, when the fenced commands of README.md's "Install it with IPM" are extracted from the committed text and pasted in order (the first two blocks in one %SYS terminal, the third in USER, the fourth in USER), then each run prints `Load finished successfully.`, `Mapping IPM repository in %SYS equivalently to USER`, the OCUTALON stop line, and ends `[OCUTALON|ocutalon]	Activate SUCCESS`, and `GET /ocutalon/` answers 200; the evidence file records both.
- AC2 (one sequence, both cases). Given USER mapped first (IPM line plus the old single `zpm "enable -community"`, whose USER install fails "No repositories"), when the same README block runs, then both installs succeed; the evidence records this run on build 154 and the plan's Task 0 runs of both cases on both builds.
- AC3 (the guide matches). Given `docs/install-ipm.md`, when read, then it holds the README's three IPM lines whole and in the same order before its first install command, no "Until the package is published" sentence and no `/tmp/ocutalon-repo`, its OCUTALON sample reloads from `/usr/irissys/ipm/ocutalon/1.0.1/`, and `test-cpf.sh` passes.
- AC4 (pins in place). Given `test-readme.sh`, when run, then every rule passes, the changed pins are P1-P9 changed in place (none deleted), each new self-test flags its broken copy, and no line in Epic 34's regions changed (`git diff -U0` hunks of the file avoid 37-45 and the licence functions).
- AC5 (footprint). Given the diff since `baseline_revision` without `_bmad-output`, when listed, then it holds only `README.md`, `docs/install-ipm.md` and `docker/tests/test-readme.sh`.

### Review Findings

Code review 2026-11-05 (layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full-opus). 0 decision-needed, 4 patch, 1 defer, 14 rejected. Evidence hygiene (no host path, IP, private host, container name, secret) and Epic 34's regions checked clean. The approved README and guide text was not edited.

- [x] [Review][Patch] The guide's "no `/tmp/ocutalon-repo`" check had no self-test of its own (low, fix-risk low: one self-test line) [docker/tests/test-readme.sh:1803]
- [x] [Review][Patch] The registry reload-line check's "before the folder install" boundary had no self-test (low, fix-risk low: one self-test line) [docker/tests/test-readme.sh:1804]
- [x] [Review][Patch] The evidence did not tie the literal runs to the committed README; it now names commit dc1d0f09 and README's blob, whose fenced blocks equal the evidence's command blocks (low, fix-risk low: evidence wording) [_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md:3]
- [x] [Review][Patch] The evidence's quoted lines were described as whole lines; Run 1's note named a second `Load finished successfully.` the block omits; Run 3 prefixes a `USER install:` label (low, fix-risk low: evidence wording) [_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md:3,15]
- [x] [Review][Defer] The guide's "The two commands give the same result when USER already had IPM" is measured only for USER mapped from %SYS, not for an IPM installed in USER itself [docs/install-ipm.md:56] — deferred: DW-760 escalated owner=burndown (med unverified, fix-risk high: Planner-approved public text); settled by a run with IPM installed in USER, or by narrowing the sentence

**Rejected:**
- `[low]` README gives no precondition for another IPM version in %SYS (blind-hunter, edge-case-hunter) - approved text; it claims only none or 0.10.10 (D5), which is not false; a rewording is not a patch.
- `[low]` The repositories warning names only %SYS, and USER's own repositories are shadowed by the mapping (blind-hunter, edge-case-hunter) - approved text, no false claim; the guide's `SHARED_SENTENCE` (pre-existing, test-cpf pin) stays true ("changes both").
- `[low]` Neither text says `enable -community` maps %IPM into every namespace (blind-hunter) - the guide's sample shows `enable -map -repos -globally` and each mapping; "changes no service" is about the installer; approved text.
- `[low]` The folder-install prerequisite links a section that also runs `enable -community` (blind-hunter) - approved text; the section carries the repositories warning; not a false claim.
- `[low]` The README removed "(AI Hub build 154 with IPM 0.10.10)" (edge-case-hunter) - approved text; it now names the two builds run.
- `[low]` The load line discards `r.Get`'s status (edge-case-hunter) - approved word for word; the guide states the registry-reachable precondition; a failure errors loudly, the command is not broken.
- `[low]` The README's "run as written on ... build 154 and build 109" sentence has no pin (blind-hunter) - unlikely to drift silently; a pin adds a check and a constant for no AC; the guide's equivalent is pinned.
- `[low]` The section-count half of the load-line check can never fail alone (verification-gap) - redundant with the whole-README count and `ipm_in_order`, no behavior unprotected; fix edits the triage log only.
- `[low]` AC5 has no suite test; QA lines use `mutation (QA, ACn):` (verification-gap) - AC5 is a diff property checked by `git diff --name-only`, its mutation recorded; prefix cosmetic.
- `[low]` AC1/AC2's runtime claim has no automated test (verification-gap) - by design (AD-22: the AI Hub image never enters CI); the committed literal-run evidence is the Rule 3 real-runtime evidence.
- `[low]` P6's message and the whole-README count differ from spec P6 wording (acceptance-auditor) - added by the implement review's patch, recorded in the triage log; AC4 holds.
- `[low]` Cycle log says 21 self-review findings, the spec 20 (blind-hunter, edge-case-hunter, acceptance-auditor) - the spec's triage log lists 20; the cycle log is the lead's append-only record.
- `[false]` Spec says done while sprint-status says review (edge-case-hunter, acceptance-auditor) - the spec's `status` is build-auto's machine state; sprint-status tracks the review stage.
- `[low]` The spec's QA note says "two gaps" and lists three (blind-hunter) - fix edits the spec's narrative; negligible.

### Review Findings (rework 1)

Code review 2026-11-05 of the DW-760 rework (`b609d015..HEAD`; layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full-opus, no `model-overrides.yaml`). 0 decision-needed, 1 patch, 0 defer, 9 rejected; the acceptance auditor found no AC or constraint violation, and the hunks avoid Epic 34's regions. DW-760 checked: line 56 is the approved text byte for byte, `README.md` unchanged, the three sentences pinned by `IPM_USER_SENTENCE`; sentence 1 is borne out by Run 3 (USER mapped from %SYS, then the README block: `Mapping IPM repository in %SYS equivalently to USER`, `Activate SUCCESS`, 200), sentences 2 and 3 by Run 4 (`Skipping repository mapping of USER`, USER `No repositories found.`; `enable -community` in USER starts with `repo -delete-all`; then `Activate SUCCESS`, 200). No evidence contradicts any of them.

- [x] [Review][Patch] The old "same result when USER already had IPM." sentence could come back beside the approved text with the suite green: the pin checks only that the new text is present, so the rework's own triage row "fixed by the same patch" did not hold (low, fix-risk low: one negative check and one self-test) [docker/tests/test-readme.sh:1078,1811]

**Rejected:**
- `[low]` The triage row says `baseline_commit` is the story's original base, but the frontmatter moved it to `b609d015` (blind-hunter, edge-case-hunter) - fix edits the spec's review narrative; no behaviour depends on it.
- `[low]` The rework triage verdict tally ("medium 1, low 2") does not match its rows (3 medium of one root cause, 10 low) (blind-hunter, edge-case-hunter) - fix edits the spec's narrative only.
- `[low]` The Auto Run Result still says "three literal runs" and "both mutations" where Run 4 and four mutation lines exist (blind-hunter) - fix edits the spec's narrative only; the Verification section records all of them.
- `[low]` Run 4 saw USER's repositories empty before and after, so "left as they are" and "deletes" were not seen on a non-empty list (blind-hunter, acceptance-auditor) - not contradicted: the product printed `Skipping repository mapping of USER` and `repo -delete-all`; the Planner's Run 4 condition is met; approved text.
- `[low]` Run 4 does not run block 3 before the USER `enable -community` (acceptance-auditor) - the failure is the lead's smoke, quoted in the [Smoke] task; not part of the Planner's condition; nothing contradicts the sentence.
- `[low]` "This is the output of `enable -community` on build 154" now follows the USER sentence and could be read as the USER run (blind-hunter) - the sentence is true (the sample is the %SYS run it always was) and is approved public text; a rewording is not a patch.
- `[low]` DW-760's spec defer bullet and ledger trailer are not updated (blind-hunter) - the lead adjudicates the ledger entry; this review confirms it under the paragraph above.
- `[low]` The pinned text could move out of its paragraph with the suite green (edge-case-hunter) - unlikely; a position check adds complexity for no AC.
- `[false]` Spec says `done` while sprint-status says `review` (edge-case-hunter, verification-gap) - the spec's `status` is build-auto's machine state; this review syncs sprint-status.

## Spec Change Log

- 2026-11-05, lead spec gate: public text approved by the Contest Planner (owner's delegation) exactly as drafted; Task 0's "samples are final" replaced by the Planner's condition 3 (refresh sample blocks from the implement stage's build 154 case 1 run where they differ); one Tasks item added for it.
- 2026-11-05, rework iteration 1 (trigger: smoke, DW-760): the lead's smoke showed the guide's "same result when USER already had IPM" false for an IPM installed in USER itself; one `[Smoke]` task added. Replacement text APPROVED by the Contest Planner (owner's delegation, relayed by the orchestrator, 2026-11-05), word for word: in `docs/install-ipm.md` line 56, replace exactly the sentence `The two commands give the same result when USER already had IPM.` with exactly:
  `The two commands give the same result when USER already had IPM mapped from %SYS. If IPM was installed in USER itself, they leave USER's repositories as they are: then also run `zpm "enable -community"` in an IRIS terminal in USER before the install. There it first deletes the repositories configured in USER.`
  (The outer backticks above only delimit the text; the inner backticks around `zpm "enable -community"` are part of it. The rest of line 56, before and after, stays byte-identical; nothing else in README.md or the guide changes.) Planner's condition: Run 4 re-runs exactly that case, literally, on a fresh build 154 throwaway — IPM installed in USER itself (README block 1 run in USER), then README blocks 1-2 in %SYS, then `zpm "enable -community"` in USER, then README blocks 3 and 4, page 200 — and the evidence is committed. If any output differs from what the sentence says (USER's repositories untouched by the %SYS commands; USER's install working after the USER `enable -community`; that command deleting USER's repositories first, `repo -delete-all` in its output), HALT `blocked` with the observed output: never reword the text.
- 2026-11-05, rework iteration 2 (trigger: ci, story red on df640ba8): `test-release-notes.sh` `static` mirrors the README's developer-section rule without its new IPM-load-line exemption; one `[CI]` task added. `docker/tests/test-release-notes.sh` is outside this story's footprint and changed by open Epic 39 (its line ~993 only): RULED 2026-11-05 by the orchestrator (decide): ALLOWED as a footprint extension, exactly as proposed (two hunks: line 29 and lines 912-913; Epic 39 changed line 993 only); no change to `lib-scan.sh` or `release/**`; mutations: a changed load line still flagged, a missing `IPM_LOAD` fails loudly; the fresh check runs every script that copies or reads README rules.

## Review Triage Log

### 2026-11-05 - Review pass
- verdicts: 20 findings - high 0, medium 0, low 15, false 5, maybe-false 0
- findings:
  - `[low]` `patch` dev-only exemption of the IPM load line is not tied to the section (blind-hunter, verification-gap) - verified: an exact copy of the line in another README section is skipped by `dev_names`, and `chk_ipm` counted only the section; patched: `chk_ipm` now also requires exactly one occurrence in the whole README, with a self-test for a copy in another section.
  - `[low]` `patch` no self-test isolates "load line exactly once" (verification-gap) - added the self-test 'the IPM load line twice in the section'; the section count already flagged it, so the test now pins it.
  - `[low]` `patch` the spec records "mutation," lines, not `mutation:` lines (verification-gap, other findings) - prefix corrected, and a `mutation:` line added for the new self-tests.
  - `[false]` `reject` the result block of the spec still reads ready-for-dev against status in-review (blind-hunter, edge-case-hunter) - finalize writes the result block and the status together.
  - `[false]` `reject` evidence quotes the IPM folder path and mentions loopback publishing (blind-hunter, edge-case-hunter) - the path is inside the container, not a host path, and AC3 requires it; no IP address is written.
  - `[false]` `reject` "same result when USER already had IPM" is unmeasured (edge-case-hunter) - case 2 (USER mapped first) is that state, run here on build 154 and in Task 0 on both builds.
  - `[false]` `reject` AC1/AC2 evidence has no raw transcripts and does not quote the unchanged map and community blocks (verification-gap) - the spec designates the evidence file as prose with quoted lines; the blocks were compared line by line by script against the full run output; negligible.
  - `[false]` `reject` guide samples differ from the plan's run, against the intent contract (intent-alignment) - the Spec Change Log and the Planner's condition 3 direct the refresh from the implement run.
  - `[low]` `reject` the load line does not check the status of `r.Get` (edge-case-hunter) - the intent fixes the line word for word and excludes other wording; out of scope of the intent.
  - `[low]` `reject` another IPM version already in %SYS is not covered (blind-hunter, edge-case-hunter) - the text claims only none or 0.10.10 (D5); unmeasured and unclaimed.
  - `[low]` `reject` arm64 only; "AI Hub" versus "IRIS for Health" naming across the texts (blind-hunter, edge-case-hunter) - approved text; the claim is limited to the instances actually run.
  - `[low]` `reject` the guide's folder-install note links a section that contains `enable -community` (blind-hunter) - approved text.
  - `[low]` `reject` `ipm_in_order` checks first occurrences; the guide's reload pin hard-codes the IPM folder and a tab (blind-hunter) - spec P6 asks for exactly that; a changed folder is a real change the pin should flag.
  - `[low]` `reject` the first guide sample holds the run-together `Activate SUCCESS2026...` line; "several hundred lines" has no count (blind-hunter) - the sample is the real output, as the spec requires; the run printed 736 lines.
  - `[low]` `reject` spec `review_loop_iteration` and flags not updated (blind-hunter) - finalize sets them.
  - `[low]` `reject` AC5 has no pinning test (verification-gap) - AC5 is a footprint criterion checked by `git diff --name-only` (done: README.md, docs/install-ipm.md, docker/tests/test-readme.sh only, outside the bookkeeping folder).
  - `[low]` `reject` `release/checklist.sh:463` still says "two commands" (verification-gap, other findings) - D9, already filed as DW-759, out of footprint.
  - `[low]` `reject` intent expectations sit at the runtime surface, the tests at the text surface (intent-alignment) - descriptive; the runtime surface is exercised by the three literal runs in the evidence file.
  - `[low]` `reject` `$ZVersion` and `<SYNTAX>` claims rest on the Task 0 table only (intent-alignment) - the evidence file includes Task 0 and the runs' `$ZVersion`.
  - `[low]` `reject` evidence lines condensed or paraphrased (intent-alignment) - each quoted line is verbatim from the run, tabs shown as spaces, as the file says.

### 2026-11-05 - Review pass (rework iteration 1, DW-760)
- verdicts: 13 findings - high 0, medium 1, low 2, false 0, maybe-false 0 (10 rejected on their stated reasons below)
- findings:
  - `[medium]` `[patch]` Blind Hunter: the pin covers only the new "If IPM was installed in USER itself..." text, so the false first sentence ("same result when USER already had IPM.") could return next to it with the suite green -- same root cause as the Edge Case and Verification Gap rows below. Patched: `IPM_USER_SENTENCE` now starts at "The two commands give the same result when USER already had IPM mapped from %SYS." (all three approved sentences), and `rule_ipm` gained the self-test 'the page claiming the same result for any USER IPM'.
  - `[low]` `[reject]` Blind Hunter: the guide text hides the destructive step and names no failure symptom -- the sentence is the Planner-approved text, word for word; the spec forbids rewording (by-design).
  - `[low]` `[reject]` Blind Hunter: "This is the output of `enable -community` on build 154" now ambiguous -- the sentence is outside the one approved sentence, public text may not change in this pass; the sample is the %SYS run it always was, and the USER run's difference is stated in the new sentence.
  - `[low]` `[reject]` Blind Hunter: the case is verified on build 154 only -- the Planner's condition names one fresh build 154 throwaway; the 109 runs of the story stand in the evidence.
  - `[low]` `[reject]` Blind Hunter: `baseline_commit` differs from `baseline_revision`, Auto Run Result still says done -- `baseline_commit` is the story's original base by design; the result section is rewritten in this pass.
  - `[low]` `[reject]` Edge Case Hunter: "left as they are" untested with a seeded USER repository -- the %SYS run printed `Skipping repository mapping of USER`, which is the product's own statement; a seeded run is beyond the Planner's condition; no realistic harm (the sentence then still tells the reader to run the USER command).
  - `[low]` `[reject]` Edge Case Hunter: the evidence's empty `repo -list` before and after cannot tell untouched from never populated -- the observed outputs are quoted as they were; the claim in the evidence is limited to those lines.
  - `[medium]` `[patch]` Edge Case Hunter: nothing forbids the old false sentence beside the new one -- same root cause as the first row; fixed by the same patch.
  - `[low]` `[reject]` Edge Case Hunter: README has no pointer to the USER case -- README stays byte-identical by the Planner's approval (by-design).
  - `[medium]` `[patch]` Verification Gap: the pin leaves the first half of the replaced sentence unguarded -- same root cause as the first row; fixed by the same patch, mutation lines below.
  - `[low]` `[reject]` Verification Gap (other): the [Smoke] task cites AC3 though AC3 does not name the sentence -- the fix is a spec edit, which review does not make.
  - `[low]` `[reject]` Verification Gap (other): Run 4 is manual evidence only -- by design (AD-22: live behaviour is proven by committed literal runs, the hermetic suite pins text).
  - `[low]` `[reject]` Intent Alignment Auditor (descriptive): the change is guide-only prose plus a pin, the USER-installed state lies outside the fresh-image premise, and the README is untouched -- the Planner approved exactly this scope; no divergence to fix.

### 2026-11-05 - Review pass (rework 2, CI)
- verdicts: 10 findings - high 0, medium 0, low 10 (rejected), false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the results block does not record the `grep -ln` discovery output -- the fix edits this spec; the grep lists lib-scan.sh, test-readme.sh, test-release-notes.sh (a library plus the two scripts run).
  - `[low]` `[reject]` Blind: `review_loop_iteration` / `followup_review_recommended` not updated -- the fix edits this spec's frontmatter, which is the loop's own bookkeeping.
  - `[low]` `[reject]` Blind: the `IPM_LOAD` sed extraction fails on an escaped quote or a second `IPM_LOAD=` line -- the result is a visible false red, not a silent pass; IPM_LOAD has neither today and a guard adds branches.
  - `[low]` `[reject]` Blind: `ipm_load` is not `local` -- the name is used only in `t_static`; a `local` would add a third hunk against the ruling's two.
  - `[low]` `[reject]` Edge: two `IPM_LOAD=` lines make a multi-line value -- same visible false red, no silent pass; not reachable today.
  - `[low]` `[reject]` Edge: escaped quote in the value -- same; `IPM_LOAD` is a plain one-liner and test-readme.sh pins it.
  - `[low]` `[reject]` Edge: the load line is exempt wherever it sits and however often -- the once-only, in-section count is test-readme.sh's `ipm` rule, which passes; the ruling asks for word-for-word equality only.
  - `[low]` `[reject]` Edge: CRLF or trailing whitespace on the load line is reported -- loud false red, and test-readme.sh's exemption matches exactly the same way; the README is LF.
  - `[low]` `[reject]` Verification Gap (other): the filter is looser than test-readme.sh's rule -- by design of the ruling; the stricter check runs in test-readme.sh.
  - `[low]` `[reject]` Intent Alignment Auditor (descriptive): the diff implements the narrow-pin reading on the test surface only -- no divergence from the CI item; the docs and literal runs are earlier iterations.

## Design Notes

**Governing ADs.** AD-23 (an IPM install is the same package run twice, first in USER, then in OCUTALON, demo mode off; the `iris merge` alternative is followed by `zpm "enable -map -ns OCUTALON"`; Prevents "two install paths drifting apart": the README and the guide now carry one command block, pinned by one constant), AD-22 (test tiers: `test-readme.sh` is hermetic in the hosted `checks` job; the live proof runs on throwaways; the AI Hub image never enters a registry, cache or artifact, so the literal runs are local manual evidence), AD-29 (README is Lane B, `docs/install-ipm.md` Lane A; Epic 11 may change either). No AC contradicts an AD's Rule or Prevents line.

**Rule 1/2.** No service, module or shared component: documentation plus its hermetic test. No consumers in this story. Consumes: Epic 15's `ocutalon` package (15.1-15.4) as published to the public registry (1.0.1) and 11.17's self-contained artifact. Consumed-by: none. Extend, don't copy: the new pins extend `chk_ipm`/`rule_ipm` and the `st` helpers; the dev-only exemption extends `dev_names`; one `IPM_LOAD` constant serves `chk_ipm` (both files) and `dev_names`.

**Ledger (Rule 17).** The inbox for this story is empty; nothing to address or decline.

**Task 0 measured** (2026-11-05, plan stage, four fresh lane-B throwaways, arm64, the plain images; all removed, lock released):
- (a) Fresh images. 154: `$ZVersion` 2026.3.0AI (Build 154U); 109: 2027.1.0AI (Build 109U). On both, %SYS, USER and HSCUSTOM have no `%IPM.Main`, `zpm "version"` in %SYS gives `<SYNTAX>`, and USER has no `%IPM` mapping. HSLIB and HSSYS have `%IPM.Main`; HSLIB's module `zpm` is 0.10.5-SNAPSHOT on 154 and 0.10.10 on 109. The SSL configuration `ISC.FeatureTracker.SSL.Config` exists on both.
- (b) The registry's `/packages/zpm/latest/installer` and `/packages/zpm/0.10.10/installer` are the same bytes today (registry metadata: zpm 0.10.10), differing from `docker/ipm/zpm-0.10.10.xml` only in `<TimeCreated>`. `IPM_LOAD` in %SYS installed IPM 0.10.10 on both builds (`IPM.Installer: Installation succeeded`, 23.0 s on 154, 14.0 s on 109; output several hundred lines ending `Load finished successfully.`). Run again where 0.10.10 is installed, it only imports and compiles the installer class and prints `Load finished successfully.`. The repository file would need a checkout inside the container; the line fetches the release itself, so it is the simplest that works on both.
- (c) Case 1 (IPM in %SYS only): `zpm "enable -map -ns USER"` printed `Mapping %IPM package in %SYS equivalently to USER`; `zpm "enable -community"` then printed `Mapping IPM repository in %SYS equivalently to USER` (both builds). Case 2 (the old README's state): `IPM_LOAD` then a single `zpm "enable -community"` printed `Mapping %IPM package in %SYS equivalently to USER` and `Skipping repository mapping of USER - IPM not mapped from source namespace.`; USER's install then printed `ERROR! No repositories are configured and enabled in this namespace.` (both builds; reproduces the Planner's finding). The full block then (IPM line again, map, community) mapped USER's repositories (and HSCUSTOM's, HSSYS's, HSSYSLOCALTEMP's), and both installs succeeded (both builds).
- (d) All four containers: USER run stops with `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`; OCUTALON run `Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)` ... `Activate SUCCESS`; `GET /ocutalon/` 200. The 109 case 1 run was the drafted block pasted literally, session by session; the 154 case 1 run had read-only probe lines between the commands.
- Durations (s), 154 c1 / 154 c2 / 109 c1 / 109 c2: container ready 73 / 31 / 38 / 13; %SYS block 27 (IPM line alone) / 6 / 19 / 6; USER run 90 / 53 / 58 / 96; OCUTALON run 57 / 54 / 47 / 56.
- The guide's samples are the build 154 case 1 run's output, colour codes and banner removed, trailing spaces trimmed, tabs kept. [AMENDED 2026-11-05 at the lead's spec gate, the Contest Planner's approval condition 3] The implement stage's build 154 case 1 literal run (from the committed README text) is the samples' source: wherever that run's output differs from a sample block in `docs/install-ipm.md` (timestamps and durations included), replace that block's lines with the run's real output, trimmed the same way; prose and the README stay exactly as approved. The changed samples need no second approval as long as they are the real output of that run; the evidence file records which blocks changed.

**Lead gate (2026-11-05): public text APPROVED.** The Contest Planner, under the owner's delegation (relayed by the orchestrator), approved both diffs of "Public text for approval" exactly as written (spec at cfd880cb): yes to the D4 `dev-only` exemption of exactly the `IPM_LOAD` line, word for word, with the self-test showing a changed line is still flagged; yes to pinning `/packages/zpm/0.10.10/installer`, not `latest`. The README's and guide's claims about both builds stand on one condition: the implement stage's literal runs from the COMMITTED README text (154 case 1, 109 case 1, 154 case 2) pass, with the evidence committed; a failing run is a HALT (`blocked`), never a text change. D9 (DW-759) is not this story's: the Planner or the burn-down fixes it.

**Decided in-stage.**
- D1. `IPM_LOAD` is exactly: `s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")` -- the standard IPM installer one-liner with the version pinned (`latest` would move with the registry).
- D2. The enable sequence is `zpm "enable -map -ns USER"` then `zpm "enable -community"`, both in %SYS (measured, both cases, both builds). `enable -community` alone is kept as the only registry line the guide explains, so test-cpf rule 12 and `chk_ipm`'s registry-line pins keep their meaning.
- D3. Case 2 is the state the old README leaves (USER mapped, repositories skipped), the realistic "mapped first" case; it also shows the block is safe to paste again on an instance with IPM 0.10.10.
- D4. `dev-only` forbids `##class(` and dotted class names above "For admins and developers", and no IRIS-terminal line can load IPM without them. It exempts exactly the line `IPM_LOAD`, word for word (EXPERIENCE.md's plain-English rule allows what a user must type); any other such line, a changed load line included, is still flagged.
- D5. The README states only what was measured: the commands, the IRIS for Health instances of both builds; it does not claim the IPM install on the plain IRIS image or over an older IPM.
- D6. The guide's build 154 bullet keeps its start `- An InterSystems IRIS for AI Hub instance, build 154, ` and ends with a build 109 sentence, so the `docs` header lines 41-42 (Epic 34's region) stay true with no edit; only `IPM_SENTENCE` changes.
- D7. `test-readme.sh` header: lines 34-36 are rewritten (more lines allowed) and 37 stays byte-identical; line 62 changes. Lines 38-45 are never touched.
- D8. The implement stage extracts the commands from README.md's committed text (not from this spec) for the literal runs, so the evidence proves the README itself.
- D9. Out of footprint, for the lead: `release/checklist.sh:463` reads "the README's two commands ran once against the registry on a clean build 154 instance"; the README now has an IPM block before its two install commands, so the item undercounts them (inference: a LOW for a Lane A release story; `release/**` is not this story's).

**Contended regions.** Epic 34 (open) changes README.md near 343 and `test-readme.sh` at 40, 135, 167, after `chk_ipm` (from `# licence`) and in `rule_licence`; Epics 17, 39 and 40 change only docs files this story does not touch (`git diff --name-only` measured). This story's hunks: README 159-180; `test-readme.sh` 34-36, 62, 859-868, about 1520-1526, 1019-1021, 1046-1052, 1077, 1760-1764, 1787-1788 -- separate hunks, so the second merge is a plain union.

### Pins changed (`docker/tests/test-readme.sh`, each in place)

- P1 (header 34-36; 37 unchanged). Replace with: `#   ipm            the section "Install it with IPM" is there after "Check that it is ready": the IPM 0.10.10 load line, then` / `#                  zpm "enable -map -ns USER", then the community-registry line, all whole lines, come before the first install command,` / `#                  which is said to run in USER; docs/install-ipm.md is linked and gives the same three lines in the same order before its` / `#                  first install, no local-repository sentence or path, its registry sample reloading from IPM's package folder, and the` / `#                  registry install before the folder install; the section never says "any namespace" (AD-23, U-231, Story 11.24); it warns that the`.
- P2 (header 62). `#   dev-only       no ##class(, class name or error code outside the section "For admins and developers", except the IPM load` / `#                  line of "Install it with IPM", word for word (Story 11.24)`.
- P3 (`dev_names` 859-868). Comment: add "The IPM load line (IPM_LOAD) is exempt, word for word." Code: pass `-v ipmload="$IPM_LOAD"` and skip `$0 == ipmload` after `stop { next }`.
- P4 (`rule_dev_only`). Add, after the heredoc loop and before `st_append`: `st 'the IPM load line changed above the section' 1 "$README" '{ sub(/zpm\/0\.10\.10\/installer/, "zpm/0.10.9/installer") } { print }' dev_names_1`.
- P5 (1019-1021). Comment `# ipm (Story 31.3, Story 11.24; AD-23, U-231): ...`. `IPM_WARNING='`enable -community` first removes the package repositories that are already set up in %SYS, so note any you use before you run it.'` (the backticks are part of the text). New constants: `IPM_LOAD='<D1 line>'` and `IPM_MAP='zpm "enable -map -ns USER"'`.
- P6 (`chk_ipm`, new checks above the `# The linked page gives...` comment). README section: `IPM_LOAD` is a whole line exactly once (message `ipm: the section does not give the IPM 0.10.10 load line word for word, once`); `IPM_MAP` and `zpm "enable -community"` are whole lines; whole-line order load < map < community < first `zpm "install ocutalon"` (`ipm: the IPM load line, the map step and the registry line are not in this order before the first install`). Page (`$2`): the same three whole lines in the same order before the page's first whole-line `zpm "install ocutalon"` (`ipm: $IPM_DOC does not give the README's IPM lines in order before its first install`); no `Until the package is published` and no `/tmp/ocutalon-repo` (`ipm: $IPM_DOC keeps the local-repository sentence or path`); a line starting `[OCUTALON|ocutalon]<TAB>Reload START (/usr/irissys/ipm/ocutalon/` before the developers' heading (`ipm: $IPM_DOC has no registry reload line in its registry install`).
- P7 (`rule_ipm`). In place: 'the repositories warning removed' becomes `'!/^`enable -community` first removes the package repositories/'`. New self-tests above `finish ipm`: README (slot 1) 'the IPM load line removed' (`!/^s r=##class\(%Net\.HttpRequest\)/`), 'the IPM load line on the latest version' (sub `zpm\/0\.10\.10\/installer` -> `zpm/latest/installer`), 'the map step removed', 'the map step after the registry line', 'the IPM load line after the map step'; page (slot 2) 'the page without the IPM load line', 'the page without the map step', 'the page with the map step after the registry line', 'the local-repository sentence back' (append it), 'the page reloading from a local repository' (sub `/usr/irissys/ipm/ocutalon/1.0.1/` -> `/tmp/ocutalon-repo/ocutalon-0.1.0/`). The `finish ipm` label in place: `'the IPM section follows the image sections: IPM load line, map step, registry line, then the first install in USER, a link to the page with the same lines, no "any namespace"'`.
- P8 (`IPM_SENTENCE` 1077). `'Build 109, which the Early Access portal now offers in place of build 154, works the same way: the registry install on this page was run on fresh IRIS for Health instances of both builds.'` `IPM_BULLET_START` unchanged.
- P9 (`rule_docs` 1787-1788, in place). 'the IPM page without the build 109 sentence': the sub removes the new sentence (regex-escaped, with its leading space). 'the IPM page sentence changed': `sub(/was run on fresh IRIS for Health instances of both builds/, "has not been tested")`.

### Public text for approval

Two unified diffs against today's files (`baseline_revision`), word for word; they apply with `git apply` (measured with `--check`). Lines with a tab in the guide's samples keep the tab. Measured with the proposed files: `test-cpf.sh` all pass, `test-boundaries.sh` and `test-bridge-guide.sh` pass; `test-readme.sh` fails only `dev-only`, `ipm` and `docs` until P1-P9 land.

README.md:

~~~diff
--- a/README.md
+++ b/README.md
@@ -156,13 +156,20 @@
 
 ### Install it with IPM
 
-To install OcuTalon into an IRIS instance you already run (AI Hub build 154 with IPM 0.10.10), use the InterSystems Package Manager. In an IRIS terminal in %SYS, point IPM at the community package registry:
+To install OcuTalon into an IRIS instance you already run, use the InterSystems Package Manager (IPM) 0.10.10. These commands were run as written on fresh IRIS for Health instances of AI Hub build 154 and build 109. A fresh instance has no IPM in %SYS, so first open an IRIS terminal in %SYS and load IPM 0.10.10 from the community package registry:
 
 ```
+s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")
+```
+
+Its output is long and ends with `Load finished successfully.` If %SYS already has IPM 0.10.10, the line installs nothing new. Then, still in %SYS, enable IPM for USER and point it at the community package registry:
+
+```
+zpm "enable -map -ns USER"
 zpm "enable -community"
 ```
 
-This command first removes the package repositories that are already set up in %SYS, so note any you use before you run it.
+`enable -community` first removes the package repositories that are already set up in %SYS, so note any you use before you run it.
 
 Then open an IRIS terminal in USER, an Interoperability-enabled namespace, and run:
 
@@ -177,7 +184,7 @@
 zpm "install ocutalon"
 ```
 
-This second run installs OcuTalon with demo mode off. [Install OcuTalon with IPM](docs/install-ipm.md) shows the output of both runs, and the install from the package folder, for developers.
+This second run installs OcuTalon with demo mode off. [Install OcuTalon with IPM](docs/install-ipm.md) shows the output of each command, and the install from the package folder, for developers.
 
 ## Set a model key
 
~~~

docs/install-ipm.md:

~~~diff
--- a/docs/install-ipm.md
+++ b/docs/install-ipm.md
@@ -1,27 +1,61 @@
 # Install OcuTalon with IPM
 
-This page installs OcuTalon into an IRIS instance you already run, with the InterSystems Package Manager (IPM). The install takes two commands of the same text, one after the other. The first one ends early on purpose and tells you what to do next. The second one gives a running OcuTalon with demo mode off. The page opens with the install from the community package registry; the install from the package folder, for developers, comes after it.
+This page installs OcuTalon into an IRIS instance you already run, with the InterSystems Package Manager (IPM). On a fresh instance it first loads IPM 0.10.10 and points it at the community package registry. The install itself takes two commands of the same text, one after the other. The first one ends early on purpose and tells you what to do next. The second one gives a running OcuTalon with demo mode off. The page opens with the install from the community package registry; the install from the package folder, for developers, comes after it.
 
 ## What you need
 
-- An InterSystems IRIS for AI Hub instance, build 154, with IPM 0.10.10 loaded in %SYS and enabled for USER (the examples start there). Build 109, which the Early Access portal now offers in place of build 154, has not been tested with the IPM install yet.
-- For the registry install: an instance that can reach the community package registry.
+- An InterSystems IRIS for AI Hub instance, build 154, with no IPM in %SYS or with IPM 0.10.10 there. Build 109, which the Early Access portal now offers in place of build 154, works the same way: the registry install on this page was run on fresh IRIS for Health instances of both builds.
+- An instance that can reach the community package registry, which serves IPM and the `ocutalon` package.
 
 OcuTalon needs no other package: the one package `ocutalon` holds the bridge too.
 
 ## Install from the package registry
 
-### Point IPM at the registry
+### Load IPM and point it at the registry
 
-In an IRIS terminal in %SYS, run:
+A fresh AI Hub instance has no IPM in %SYS: there, `zpm "version"` answers `<SYNTAX>`. In an IRIS terminal in %SYS, load IPM 0.10.10 from the community package registry:
 
 ```
+s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")
+```
+
+The line fetches IPM's installer for version 0.10.10 and runs it. Its output is several hundred lines. On build 154 it ended with these lines:
+
+```
+[%SYS|ZPM]	Activate SUCCESS2026-11-05 20:24:07 0 IPM.Installer: Installation succeeded at 2026-11-05 20:24:07
+2026-11-05 20:24:07 0 %Installer: Elapsed time 23.047859s
+
+Time spent 23.049402
+Load finished successfully.
+```
+
+On an instance that already has IPM 0.10.10 in %SYS, the line loads the installer and installs nothing new. Then, still in %SYS, run these two commands:
+
+```
+zpm "enable -map -ns USER"
 zpm "enable -community"
 ```
 
-The command first deletes the repositories configured in %SYS (`repo -delete-all` in its output), then adds the community registry. This is its output, with the terminal's colour codes removed:
+`zpm "enable -map -ns USER"` maps IPM into USER. This is its output on build 154, with the terminal's colour codes removed:
+
+```
+Version of IPM in current namespace:
+%SYS> zpm 0.10.10
+Mapping %IPM package in %SYS equivalently to USER
+Mapping %IPM.* routines in %SYS equivalently to USER
+Done.
 
+%SYS>  zpm 0.10.10
+HSLIB> zpm 0.10.5-SNAPSHOT
+HSSYS> zpm 0.10.5-SNAPSHOT
+       Installed In: HSLIB
+USER>  zpm 0.10.10
+       Installed In: %SYS
 ```
+
+`enable -community` first deletes the repositories configured in %SYS (`repo -delete-all` in its output), then adds the community registry and maps it into USER (`Mapping IPM repository in %SYS equivalently to USER`). Run the two commands in this order. Without `enable -map -ns USER` first, `enable -community` maps IPM into USER but skips USER's repositories (`Skipping repository mapping of USER - IPM not mapped from source namespace.`), and the install in USER then stops with `ERROR! No repositories are configured and enabled in this namespace.` The two commands give the same result when USER already had IPM. This is the output of `enable -community` on build 154, with the terminal's colour codes removed:
+
+```
 Version of IPM in current namespace:
 %SYS> zpm 0.10.10
 
@@ -109,10 +143,10 @@
 
 Building dependency graph...Done.
 [USER|ocutalon]	Initialize START
-Compilation started on 11/03/2026 07:21:52
+Compilation started on 11/05/2026 20:26:03
 Compiling class OcuTalon.Install.Ipm
 Compiling routine OcuTalon.Install.Ipm.1
-Compilation finished successfully in 0.004s.
+Compilation finished successfully in 0.005s.
 
 [ocutalon]	Initialize FAILURE
 ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
@@ -140,13 +174,13 @@
 
 Building dependency graph...Done.
 [OCUTALON|ocutalon]	Initialize START
-Compilation started on 11/03/2026 07:21:55
+Compilation started on 11/05/2026 20:26:18
 Compiling class OcuTalon.Install.Ipm
 Compiling routine OcuTalon.Install.Ipm.1
 Compilation finished successfully in 0.002s.
 
 [OCUTALON|ocutalon]	Initialize SUCCESS
-[OCUTALON|ocutalon]	Reload START (/tmp/ocutalon-repo/ocutalon-0.1.0/)
+[OCUTALON|ocutalon]	Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)
 [OCUTALON|ocutalon]	Reload SUCCESS
 [ocutalon]	Module object refreshed.
 [OCUTALON|ocutalon]	Validate START
@@ -158,17 +192,17 @@
 STEP Bridge.Installer OK 0.1s
 STEP Public OK 0.0s
 STEP Roles OK 0.0s
-STEP Users OK 0.0s
-STEP Web OK 0.0s
+STEP Users OK 0.1s
+STEP Web OK 0.1s
 STEP SSL OK 0.0s
 STEP Tasks OK 0.1s
 STEP Demo OK 0.1s
 STEP Provider OK 0.1s
 STEP Audit OK 0.0s
 STEP Telegram OK 0.0s
-07:22:35.460:Ens.Director: Production 'OcuTalon.Production' starting...
-07:22:35.567:Ens.Director: Production 'OcuTalon.Production' started.
-STEP Production OK 1.2s
+20:27:03.977:Ens.Director: Production 'OcuTalon.Production' starting...
+20:27:04.200:Ens.Director: Production 'OcuTalon.Production' started.
+STEP Production OK 1.3s
 STEP Reconcile OK 0.2s
 STEP PrivateData OK 0.1s
 STEP Ready OK 0.0s
@@ -177,8 +211,6 @@
 OCUTALON>
 ```
 
-Until the package is published, these outputs come from the same package installed from a local IPM repository.
-
 The installer marks the OcuTalon production to start with the instance, so it comes back after an instance restart. It changes no service of the instance and no namespace or database it did not create.
 
 If a step fails after the code has loaded, the command reports the failure and names the step (`STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.`, then IPM's `ERROR!` line), the new code stays installed, and running the same command again finishes the install; a failure while IPM loads or compiles the code is rolled back and the previous version keeps running.
@@ -194,6 +226,8 @@
 
 The instance needs no Node.js. Copy the `src` folder to a place the instance can read. The examples below call it `/opt/ocutalon-ipm/src`; use your own folder in its place.
 
+It also needs IPM 0.10.10 in %SYS, enabled for USER, as [Load IPM and point it at the registry](#load-ipm-and-point-it-at-the-registry) gives.
+
 ### The first command
 
 Open an IRIS terminal in USER and load the package:
~~~

## Verification

All commands run from the worktree root after `git rev-parse --show-toplevel` matches it, each in its own foreground call with `timeout: 600000`.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: `test-readme: all rules passed`.
- (loop) `bash docker/tests/test-cpf.sh` -- expected: `test-cpf: all checks passed`.
- (loop) `git diff -U0 docker/tests/test-readme.sh | grep '^@@'` -- expected: no hunk touches lines 37-45 or the `chk_licence`/`rule_licence` bodies.
- (once) `bash docker/tests/test-boundaries.sh` and, as its own call, `bash docker/tests/test-bridge-guide.sh` -- expected: exit 0 each.
- (once) Live literal runs, one container at a time, each step its own call, well under 10 min (measured: ready 13-73 s, %SYS block 6-27 s, USER 53-96 s, OCUTALON 47-57 s). Acquire `<main checkout>/.worktrees/.coordination/locks/lane-b/throwaway-iris.lock` with `set -o noclobber` (content `epic=11 stage=implement project=<container> acquired_at=<UTC>`; wait 30-90 s with jitter while it exists). `docker run -d --name ocutalon-e11s24implement-<154|109>-<case> --label ocutalon.run=e11s24implement -p <loopback>:52802:52773 <image>` (publish only the web port, on the loopback interface, host port 52802; `<loopback>` is the IPv4 loopback address, written out only in the command, never in a file); the 154 image is `irishealth-community:2026.3.0AI.154.0`; the 109 image is loaded only under a registry-prefixed name, so take the one ref that `docker images --format '{{.Repository}}:{{.Tag}}'` lists ending in `/irishealth-community:2027.1.0AI.109.0`. Ready when `iris qlist` shows `^running` and a USER session answers. Extract the fenced blocks of README.md's "Install it with IPM" (in order: block 1 and block 2 into one `docker exec -i <c> iris session IRIS -U %SYS`, block 3 into `-U USER`, block 4 into `-U USER`), then `curl` the published `/ocutalon/`. Expected per run: `Load finished successfully.`, `Mapping IPM repository in %SYS equivalently to USER`, the OCUTALON stop line, `Activate SUCCESS`, HTTP 200. Runs: 154 case 1, 109 case 1, 154 case 2 (before the block: the IPM line and a single `zpm "enable -community"` in %SYS, then the USER install must print `ERROR! No repositories are configured and enabled in this namespace.`). After each: `docker rm -f` the container (label checked) and delete the lock if its content is yours, failures included.

**Rule 19.**
- Shared surfaces: README "Install it with IPM" and `docs/install-ipm.md`, asserted by `test-readme.sh` (`ipm`, `docs`, `dev-only`, `install`, `readme-links`) and `test-cpf.sh` rules 9, 11, 12. Every test added or changed passes on a fresh environment, in either order (`test-readme.sh` is hermetic and reads only tracked files).
- mutation lines (implement records each, observed red, reverted, tree byte-identical): AC1/AC4 the README load line pinned to `latest` -> `FAIL ipm` and `FAIL dev-only`; AC2 the map line moved after `zpm "enable -community"` in README -> `FAIL ipm`; AC3 the stale sentence appended to the guide -> `FAIL ipm`; AC4 the guide's build 109 sentence reverted to "has not been tested with the IPM install yet." -> `FAIL docs`; D4 the `dev_names` exemption widened to any line starting `s r=` -> `FAIL dev-only: a broken copy was not flagged`.

**Implement-stage results (2026-11-05, README/guide diffs applied with `git apply`; `test-readme.sh` P1-P9 in place):**
- (loop) `bash docker/tests/test-readme.sh` -> `test-readme: all rules passed`; `bash docker/tests/test-cpf.sh` -> `test-cpf: all checks passed`; `git diff -U0 docker/tests/test-readme.sh | grep '^@@'` -> hunks at 34, 62, 860-870, 1019-1026, 1051-1068, 1077, 1525, 1760-1764, 1787-1788 (old numbering); none in 37-45, the DOCKERFILE/dockerfile_p area, `chk_licence` or `rule_licence`.
- mutation: README load line pinned to `latest` -> `FAIL dev-only` and `FAIL ipm` (observed red, reverted, byte-identical).
- mutation: README map line moved after `zpm "enable -community"` -> `FAIL ipm` (observed red, reverted, byte-identical).
- mutation: stale "Until the package is published" sentence appended to the guide -> `FAIL ipm` (observed red, reverted, byte-identical).
- mutation: guide's build 109 sentence reverted to "has not been tested with the IPM install yet." -> `FAIL docs` (observed red, reverted, byte-identical).
- mutation: `dev_names` exemption widened to any line starting `s r=` -> `FAIL dev-only: a broken copy was not flagged` (observed red, reverted, byte-identical).
- mutation: the IPM load line copied into another README section (outside "Install it with IPM") -> before the `chk_ipm` whole-README count, `FAIL ipm: a broken copy was not flagged`; after it, flagged; the load line twice in the section is flagged too (observed red, reverted, byte-identical).
- (once) Live literal runs from README.md's committed blocks, one lane-B throwaway at a time, each removed and the lock released after its run: 154 case 1 PASS (Load finished successfully., Mapping IPM repository in %SYS equivalently to USER, the OCUTALON stop line, Activate SUCCESS, HTTP 200; ready 49 s, %SYS 34 s, USER 89 s, OCUTALON 62 s); 109 case 1 PASS (same lines; ready 29 s, %SYS 29 s, USER 78 s, OCUTALON 73 s); 154 case 2 PASS (the old single `enable -community` state gave `Skipping repository mapping of USER` and `ERROR! No repositories are configured and enabled in this namespace.`; the whole README block then ended Activate SUCCESS, HTTP 200; %SYS 8 s, USER 138 s, OCUTALON 77 s). Evidence: `_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md`.
- (once) Sample refresh from the 154 case 1 run: `docs/install-ipm.md` blocks changed are the IPM load tail, the USER sample and the OCUTALON sample (time stamps, durations); the `enable -map -ns USER` and `enable -community` outputs were identical. After it `test-readme.sh` and `test-cpf.sh` pass; `test-boundaries.sh` and `test-bridge-guide.sh` exit 0.

**QA-stage results (2026-11-05; no container started; README and guide text untouched):**
- Discoverable: `readme` and `cpf` are in `CHECK_SCRIPTS` (`ci/units.sh`), which the hosted `checks` job runs through `ci/checks.sh` as `docker/tests/test-<name>.sh`; no ignore file or tag excludes them. `bash docker/tests/test-readme.sh` -> all rules passed; `bash docker/tests/test-cpf.sh` -> all checks passed.
- Audit: AC1/AC2 (the README's three lines, once, whole, in order, pinned to 0.10.10) pinned by `chk_ipm` + `dev_names`; AC3 pinned by `chk_ipm` (the guide's lines in order, no stale sentence or path, registry reload line) and test-cpf rules 9, 11, 12; AC4 by the `st` self-tests; AC5 and the Epic 34 region separation are diff properties with no suite test (audited below). Two gaps found and closed (QA): the guide's own load line on `latest` had no self-test (only removal), and the reload-line pin was only exercised together with the stale-path pin; the dev-only exemption had no self-test for the load line with extra text on the same line.
- (QA) Added to `docker/tests/test-readme.sh`: `rule_ipm` 'the page IPM load line on the latest version' and 'the page registry reload line from another folder' (above `finish ipm`); `rule_dev_only` 'the IPM load line with a second call on its line' (after the P4 line, above `st_append`). `git diff -U0` of the QA edit: two hunks (one in `rule_dev_only`, one in `rule_ipm`), none in Epic 34's regions.
- mutation (QA, AC1): README load line pinned to `latest` -> `FAIL ipm` and `FAIL dev-only` (observed red, restored from backup, byte-identical).
- mutation (QA, AC2): README map line moved after `zpm "enable -community"` -> `FAIL ipm` (red, reverted, byte-identical).
- mutation (QA, AC3): the guide's registry reload line `/usr/irissys/ipm/ocutalon/1.0.1/` moved to `/usr/irissys/ipm/other/1.0.1/` -> `FAIL ipm`; the guide's load line on `latest` -> `FAIL ipm` (red, reverted, byte-identical). The pin takes the prefix `/usr/irissys/ipm/ocutalon/`, not the version, on purpose (a later package version keeps the page true).
- mutation (QA, AC4): the guide-order line `if ! ipm_in_order "$2"` deleted from `chk_ipm` -> `FAIL ipm: a broken copy was not flagged` (the page self-tests bite); the implement stage's guide build 109 sentence mutation -> `FAIL docs` stands above (red, reverted, byte-identical).
- mutation (QA, D4 dev-only exemption scope): `dev_names` exemption widened from `$0 == ipmload` to a 40-character prefix match -> `FAIL dev-only: a broken copy was not flagged` (the new second-call self-test, besides the 0.10.9 one; red, reverted, byte-identical).
- Epic 34 regions (AC4): the baseline's header lines 37-45 (now 39-47 after the story's two added header lines), the `DOCKERFILE`/`dockerfile_p` lines, `chk_licence` and `rule_licence` bodies hash identically at `2f7d0ec1` and now (sha256 8c3a2f9e...); mutation: a byte appended to header line 38 of the new numbering -> hash changes (red, reverted, byte-identical).
- mutation (QA, AC5): `git diff --name-only 2f7d0ec1 -- . ':(exclude)_bmad-output'` lists exactly README.md, docs/install-ipm.md, docker/tests/test-readme.sh; with a newline appended to `docs/bridge-guide.md` it also lists that file (red, reverted, byte-identical). No suite test covers AC5; this is the audit command.
- `mutations_demonstrated=6` (AC1, AC2, AC3, AC4, D4 exemption, AC5), plus the Epic 34 region check.

**Code-review results (2026-11-05; no container started; README and guide text untouched):**
- (CR) Added to `rule_ipm` above `finish ipm`: 'the page naming the local-repository path elsewhere' and 'the page registry reload line only in the folder install'. `bash docker/tests/test-readme.sh` -> all rules passed.
- mutation: (AC3, no `/tmp/ocutalon-repo`) `-e '/tmp/ocutalon-repo'` removed from `chk_ipm`'s stale-text grep -> `self-test: the page naming the local-repository path elsewhere: not flagged`, `FAIL ipm` (red, restored from backup, byte-identical).
- mutation: (AC3, reload line in the registry install) `/^## Install from the package folder/ { exit }` removed from `chk_ipm`'s reload-line awk -> `self-test: the page registry reload line only in the folder install: not flagged`, `FAIL ipm` (red, restored from backup, byte-identical).

**Rework results (2026-11-05, DW-760; Run 4 on a fresh build 154 throwaway, removed, lock released):**
- `docs/install-ipm.md` line 56: the one sentence replaced by the approved text (`git diff -U0` shows one hunk); `README.md` unchanged (`git diff --quiet HEAD -- README.md`).
- `docker/tests/test-readme.sh`: `IPM_USER_SENTENCE` (next to `IPM_MAP`), a page-side `grep -qF` in `chk_ipm` above the `# The linked page gives...` comment (message `ipm: docs/install-ipm.md does not say what to do when IPM was installed in USER itself`), and the self-test 'the page without the USER-installed IPM sentence' (slot 2) in `rule_ipm` above `finish ipm`. Three hunks, none in Epic 34's regions. `bash docker/tests/test-readme.sh` -> all rules passed; `bash docker/tests/test-cpf.sh` -> all checks passed.
- mutation: the guide's new sentence cut back to "They leave USER's repositories..." -> `FAIL ipm` with the new message (observed red, restored from backup, sha256 identical).
- mutation: the new `chk_ipm` check deleted -> `self-test: the page without the USER-installed IPM sentence: not flagged`, `FAIL ipm: a broken copy was not flagged` (observed red, restored from backup, byte-identical).
- (once) Run 4, README blocks literally: block 1 in USER (IPM in USER, none in %SYS); blocks 1 and 2 in %SYS printed `Skipping IPM mapping of USER - IPM already installed.` and `Skipping repository mapping of USER - IPM not mapped from source namespace.`, USER `repo -list` -> `No repositories found.`; `zpm "enable -community"` in USER began with `repo -delete-all`; block 3 -> the OCUTALON stop line; block 4 -> `Activate SUCCESS` (reload from `/usr/irissys/ipm/ocutalon/1.0.1/`); HTTP 200. Evidence: Run 4 in `_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md`.
- Review patch (2026-11-05): `IPM_USER_SENTENCE` widened to the three approved sentences; `rule_ipm` self-test 'the page claiming the same result for any USER IPM' (slot 2) added above `finish ipm`; `test-readme.sh` -> all rules passed, `test-cpf.sh` -> all checks passed; `git diff -U0` of the file: three hunks, none in Epic 34's regions.
- mutation: the guide's first sentence reverted to "...when USER already had IPM." -> `FAIL ipm` (observed red, restored from backup, sha256 identical).
- mutation: the `chk_ipm` USER-sentence check deleted -> both self-tests 'the page without the USER-installed IPM sentence' and 'the page claiming the same result for any USER IPM' `not flagged`, `FAIL ipm: a broken copy was not flagged` (observed red, restored from backup, sha256 identical).
- Code review patch (rework 1, 2026-11-05): `chk_ipm` gains a negative check, `grep -qE 'when USER already had IPM\.([[:space:]]|$)'` (message `ipm: docs/install-ipm.md claims the same result for any IPM in USER`), and `rule_ipm` the self-test 'the page with the any-USER-IPM sentence beside the new one' (slot 2) above `finish ipm`; `test-readme.sh` -> all rules passed, `test-cpf.sh` -> all checks passed; `git diff -U0` adds two lines (1078, 1811), none in Epic 34's regions.
- mutation: the new negative check deleted -> `self-test: the page with the any-USER-IPM sentence beside the new one: not flagged`, `FAIL ipm: a broken copy was not flagged` (observed red, restored from backup, sha256 identical).

**CI rework results (2026-11-05, iteration 2):**
- `docker/tests/test-release-notes.sh`: two hunks only (header comment line 29, now two lines; the `static` README assertion at 913, now with `ipm_load` read from the `IPM_LOAD='...'` line of `docker/tests/test-readme.sh`; no value -> `static: docker/tests/test-readme.sh holds no IPM_LOAD='...' line` and `bad=1`). Line ~993 (Epic 39) untouched. No other file edited.
- mutation: README.md line 162 (the load line) changed by one character (`0.10.10` -> `0.10.11`) -> `bash docker/tests/test-release-notes.sh` prints `names_outside_section on README.md: got 'README.md:162', wanted ''` and `FAIL static` (observed red, restored from backup, sha256 identical, `git status` clean for README.md).
- mutation: `IPM_LOAD=` renamed `IPM_LOADX=` in docker/tests/test-readme.sh -> `static: docker/tests/test-readme.sh holds no IPM_LOAD='...' line` and `FAIL static` (observed red, restored from backup, sha256 identical).
- mutation: a second `##class(` line added to README.md outside "For admins and developers" (line 163) -> `names_outside_section on README.md: got 'README.md:163', wanted ''` and `FAIL static` (observed red, restored from backup, sha256 identical).
- `bash docker/tests/test-release-notes.sh` -> all 16 rules PASS, exit 0; `bash docker/tests/test-readme.sh` -> `test-readme: all rules passed`; `bash docker/tests/test-cpf.sh` -> `test-cpf: all checks passed`. No container, IRIS or network used.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** README "Install it with IPM" and `docs/install-ipm.md` carry the Planner-approved text (applied with `git apply`), the guide's IPM load tail, USER and OCUTALON samples are refreshed from the build 154 case 1 run, and `docker/tests/test-readme.sh` pins P1-P9 are in place plus two self-tests and a whole-README count for the load line. The README block ran literally on fresh build 154 (case 1), build 109 (case 1) and build 154 (case 2); each ended Activate SUCCESS with HTTP 200.

**Files changed.**
- `README.md` - "Install it with IPM": load line, map step, community line, adjusted prose.
- `docs/install-ipm.md` - same three lines, stale sentence and local path removed, samples refreshed from the real run.
- `docker/tests/test-readme.sh` - pins P1-P9 in place, `IPM_LOAD`/`IPM_MAP`, `ipm_in_order`, new `rule_ipm` self-tests, load-line exemption in `dev_names`.
- `_bmad-output/implementation-artifacts/evidence/11-24-readme-ipm-literal-runs.md` - new: the three runs, Task 0 table, refreshed blocks.

**Review.** 20 findings: 3 patched (low), 17 rejected with reasons in the triage log; none deferred.

**Follow-up review recommended:** false (no high patched; no two mediums patched).

**Verification.** `test-readme.sh` all rules passed; `test-cpf.sh` all checks passed; `test-boundaries.sh` and `test-bridge-guide.sh` exit 0; `git diff -U0` hunks avoid lines 37-45 and the licence functions; the three literal runs passed (evidence file); containers removed and the lane-B lock released after each run.

**Residual risks.** The README claim rests on the three runs of 2026-11-05 (arm64); `release/checklist.sh:463` is DW-759 (out of footprint).

**Rework pass 1 (DW-760, 2026-11-05).** The guide's line 56 carries the Planner-approved three sentences (one hunk; README unchanged); `chk_ipm` pins them and `rule_ipm` has two self-tests for them; Run 4 (fresh build 154, IPM installed in USER itself) passed and is in the evidence file. Review: 13 findings, 1 root cause patched (the pin now covers all three sentences; medium), 10 rejected with reasons in the triage log, none deferred. Follow-up review recommended: false (no high patched). Verification: `test-readme.sh` all rules passed; `test-cpf.sh` all checks passed; both mutations observed red and restored byte-identical. Teardown: no container with label `ocutalon.run=e11s24implement`; lane-B lock released.

**Rework pass 2 (CI, 2026-11-05).** Summary: `docker/tests/test-release-notes.sh` `static` rule (ruled footprint extension, two hunks: header line 29 and lines 912-913) drops a `names_outside_section` hit on README.md only when that line equals `IPM_LOAD` of `test-readme.sh` word for word, read from that one line; a missing value fails loudly. Files changed: `docker/tests/test-release-notes.sh`. Review: 10 findings, none patched, 10 rejected (low, reasons in the triage log), none deferred. Follow-up review recommended: false (no high patched). Verification: `test-release-notes.sh` all 16 rules pass; `test-readme.sh` all rules passed; `test-cpf.sh` all checks passed; three mutations red and reverted byte-identical (Verification, "CI rework results"). Residual risks: none beyond the rejected lows.
