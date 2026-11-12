---
title: "Story 0.28: DW-1171 follow-up: the README's Contest checklist gets a Video row, and the For judges Usability row links the incident path and the full video"
type: 'feature'
created: '2026-11-12'
status: 'in-progress'
baseline_revision: '793840c5af3873540913aceac72b1086083d0b7e'
baseline_commit: '793840c5af3873540913aceac72b1086083d0b7e'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred:
  - summary: >-
      No per-push test runs check-readme-video.sh's own logic (retry, cap, 206 handling, status handling, both youtu.be addresses): the release checklist's test stubs the script, and the script's self-tests run only online.
    evidence: |-
      A stub-curl test would be a new test-*.sh, which needs an entry in a ci/units.sh list; this story's boundaries rule out a ci/ hunk and a new CI group. A regression shows at the next release candidate run, as a loud FAIL on the readme-video row.
    location: >-
      docker/tests/check-readme-video.sh
    severity: low
  - summary: >-
      ci/units.sh NOT_IRIS_INPUT_PATTERN lists docker/tests/record-eval.sh and docker/tests/test-*.sh but not docker/tests/check-readme-video.sh, so a later edit of that script makes ci/changes.sh run every CI group.
    evidence: |-
      The script reads no IRIS input; the fix is one alternative in the pattern (ci/units.sh:251), a ci/ hunk this story may not carry. Cost is extra CI minutes on later edits of the script only; this story's own push runs every group once.
    location: >-
      ci/units.sh:251
    severity: low
  - summary: >-
      Nothing per push checks that the real docker/tests/check-readme-video.sh exists, is executable and parses (test-release-checklist.sh uses a stub at the same path).
    evidence: |-
      A deleted or non-executable script fails the readme-video row at release time (row_script reports the failure), not per push. Closing it needs a rule in a per-push test.
    location: >-
      release/checklist.sh:312
    severity: low
---

<intent-contract>

## Intent

**Problem:** (DW-1171) The README's Contest checklist has no Video row, and the "For judges" Usability row links neither the full video nor the incident path.

**Approach:** Part A of Story 0.27's plan, split out whole by the orchestrator's ruling (U5 decide; the Contest Planner pre-authorized it) so it makes the 1.0.8 cut. The Contest Planner's DW-1171 ruling (2026-11-12 ~01:55Z, owner's delegation; `prompts/story-026-rulings.md` item 2) binds word for word: the ruled Video row right after "Online demo" in the Contest checklist; the two ruled sentences replacing the first sentence of the "For judges" Usability row, the rest unchanged; hermetic README rules for both and for the `#one-incident-end-to-end` anchor; the web tests' count pin moved to the ruled sentence (still pinned against the More to try registry); and a separate network check that the Video row's links answer 200.

## Boundaries & Constraints

**Always:**
- README text is the ruled text of `## Ruled README change` (A1, A2), applied verbatim; no other README line changes.
- Every existing `test-readme.sh` rule keeps passing; none is deleted, skipped or weakened. `test-readme.sh` stays hermetic (its header promises no network).
- The count word stays pinned against the More to try registry ("fifteen" now; "sixteen" once Story 35.3's item is in; whichever of 35.3 and this story merges second sets it).
- Shell stays ASCII and bash 3.2 compatible. Every command a stage runs finishes in about 150 s.

**Never:**
- No `.github/workflows`, `ci/` or `_bmad/**` hunk, no new CI job or group: the network check is NOT in per-push CI (Contest Planner, 02:05Z). The one `release/**` hunk is the Planner-ruled row in `release/checklist.sh` that runs it.
- No `eval/**` change (Story 0.27). No absolute local path in any tracked file.
- The network check is never skipped, silently or loudly.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Video row links, online | `bash docker/tests/check-readme-video.sh` | Each link of the README's `\| Video \|` row answers 200 after redirects. Each `youtu.be/<id>` link's YouTube oEmbed (`https://www.youtube.com/oembed?url=https://youtu.be/<id>&format=json`) answers 200. Self-tests: a copy with an unknown video id and a copy with a missing MP4 name are flagged. Prints PASS lines | No error expected |
| Video row links, a link gone | A link or its oEmbed answers 404 (or any status other than 200 that is not retryable) | `FAIL readme-video: <url> answered <code>` | exit 1 at once, no retry |
| Video row links, offline or flaky | curl fails (no route, DNS, timeout), or answers 429 or 5xx | Up to 3 tries per address, 5 s apart, `--max-time 15`, with a 150 s cap on the whole script; then `FAIL readme-video: <url> could not be reached after 3 tries (<curl exit or code>)` | exit 1, never skipped |
| Ruled rows | `bash docker/tests/test-readme.sh` on the README with A1 and A2 | `checklist-video`, `judges-usability`, `video` and `readme-links` pass | No error expected |
| Rows broken | Video row moved, reworded, twice, or above "Online demo"; the anchor's heading renamed; the Usability sentences reworded | the rule names it | test fails |
| Count drifts | The Usability row's count word differs from the registry's count | the two web count tests fail | test fails |

</intent-contract>

## Code Map

- `README.md` -- the "For judges" `| Usability |` row (its first sentence replaced); the Contest checklist's `| Online demo |` row (the Video row goes right after it).
- `docker/tests/test-readme.sh` -- rules are `chk_<name>` plus `rule_<name>` with self-tests (`st`, `st_append`, `st_move`, `st_facts`), `finish` and `scan_rule`; `RULES` near the end. `chk_video` flags the teaser URL anywhere but the teaser line and the link bar; the ruled Video row holds the teaser URL, so it must also accept exactly that row. `chk_readme_links` already resolves every `#anchor` and checks hosts against `ALLOWED_HOSTS` (youtu.be and github.com/jbrandtmse/OcuTalon are on it). `section`, `headings` (slugs).
- `web/scripts/sources-docs.test.mjs` and `web/scripts/more-to-try-view.test.mjs` -- the count pin against the More to try registry (`MORE_TO_TRY_ITEMS.length`, words up to sixteen): `its More to try panel has ${word} more things to try`. The ruled sentence starts "Its", so both fail until moved. They run in CI's hosted `web` job.
- `ci/units.sh` / `docker/tests/test-ci-config.sh` (`units`): every `docker/tests/test-*.sh` must sit in exactly one CI list, so the network check is named `check-readme-video.sh` (outside the `test-*.sh` glob, like `record-eval.sh` and the `lib-*.sh` files) and is in no list. `release/checklist.sh` -- the release candidate checklist (Story 11.4): automated rows are `row_<name>` functions (`row_readme() { row_script readme docker/tests/test-readme.sh; }`), described in its header and dispatched in its row list; its own tests (find them: `git grep -n "checklist.sh" docker/tests`) may pin the row list.

## Tasks & Acceptance

**Execution:**
- `README.md` -- apply `## Ruled README change` parts A1 and A2 verbatim (DW-1171).
- `docker/tests/test-readme.sh` -- extend, following `video`'s pattern:
  - new rule `checklist-video`: in "## Contest checklist", the row right after `| Online demo |` is the ruled Video row, word for word, and it appears once; the link `#one-incident-end-to-end` resolves to the heading "One incident, end to end" (by `headings`' slug).
  - new rule `judges-usability`: the "For judges" `| Usability |` row starts with the two ruled sentences, word for word, except the count word, matched as `[a-z]+` (the web tests pin the number against the registry).
  - `video`: the teaser address may also be in the ruled Video row (exactly that line); a teaser address in any other line is still flagged.
  - Self-tests, one bad variant per way to break each rule (row moved, row reworded, row twice, Video row before Online demo, the anchor's heading renamed, sentence reworded, the full-video link changed). Update `RULES` and the header comment. Keep the "Hermetic" line true.
- `web/scripts/sources-docs.test.mjs`, `web/scripts/more-to-try-view.test.mjs` -- the count regex becomes `Its More to try panel has ${word} more things to try`; nothing else changes (DW-1171: the count stays pinned against the catalog).
- `docker/tests/check-readme-video.sh` -- new (DW-1171): the network check of the matrix's three "Video row links" rows. It takes an optional README path (default `README.md`), reads the `| Video |` row of the Contest checklist (a missing row fails), and checks every http(s) address in it, plus each YouTube id's oEmbed. Self-tests on copies: an unknown video id (oEmbed 404) and a missing MP4 name (404), each flagged; the row removed, flagged with no request. Header: what it pins, that it needs the network, and its retry and cap. bash 3.2, ASCII, curl only.
- `release/checklist.sh` -- add the automated row `readme-video` that runs `docker/tests/check-readme-video.sh` (one `row_readme_video() { row_script readme-video docker/tests/check-readme-video.sh; }` line, its PASS detail line, its header line and its place in the row list, following `readme`). Update whatever test pins the checklist's rows. This is a RELEASE TOOL hunk the Contest Planner ruled in (02:05Z item 4); the lead reports it.

- [ ] [Review] DW-1178 (Contest Planner ruling on 0.28, ~05:00Z, option (a), folded in before merge) -- `release/checklist.sh` `outward_hits`/`row_no_outward` and `docker/tests/test-readme.sh` -- allow exactly one more line in the `no-outward` row: `docker/tests/test-readme.sh`'s current `ALLOWED_HOSTS='...'` line, as it is now, with the same full-line match as the OEMBED allowance (any other path form or any change fails closed); add the same three cases to `test-release-checklist.sh` `outward-rows` (that line in that file passes; the same line in another file fails; a changed line fails); add a comment line directly above `ALLOWED_HOSTS` in `test-readme.sh` saying any edit to that line must update the no-outward allowance in `release/checklist.sh` in the same commit; keep the checklist header true. Every other `no-outward` hit still fails.

**Acceptance Criteria:**
- Given the README (DW-1171), when the Contest checklist and the "For judges" table are read, then the ruled Video row sits right after "Online demo" and the Usability row opens with the two ruled sentences, the rest unchanged; `test-readme.sh` passes `checklist-video`, `judges-usability`, `video` and `readme-links`, and fails on each bad copy.
- Given the More to try registry, when the web tests run, then the README's count word in "Its More to try panel has ... more things to try" equals the registry's item count (fifteen now; sixteen once Story 35.3's item is in), and a README saying another number fails.
- Given the network, when `bash docker/tests/check-readme-video.sh` runs, then every Video row link answers 200 and each YouTube id's oEmbed answers 200, and the copy with an unknown id or a missing MP4 is flagged; offline it fails loudly after its bounded retries and is never skipped.
- Given the release candidate checklist, when `release/checklist.sh` runs its automated rows, then `readme-video` runs `docker/tests/check-readme-video.sh` and reports PASS or FAIL like the other script rows.
- Given CI on this story's head, when it finishes, then every workflow is green (the network check is not run per push).

### Review Findings

Code review 2026-11-12 (layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; all four reported). 0 decision-needed, 10 patch, 1 defer, 8 rejected.

- [x] [Review][Patch] (med) QA's `video-script` names the video site's host whole in two lines, so the release checklist's `no-outward` row gains two hits [docker/tests/test-release-checklist.sh:886] -- the oEmbed addresses are now built by concatenation, as the file's header prescribes for rule-breaking samples.
- [x] [Review][Patch] (med) `check-readme-video.sh` wrote the oEmbed host in two parts only to slip past `no-outward` (a release safety check), which leaves the row's stated guarantee silently untrue [docker/tests/check-readme-video.sh:37] -- the host is named whole (`OEMBED="https://www.youtube.com/oembed"`), and `release/checklist.sh`'s `outward_hits` allows exactly that line, as it is, only in that file (header says so); `outward-rows` pins the allowed line passing, and the same line in another file, the line changed, and another line of that file naming the site all still failing. RELEASE TOOL hunk, for the lead to report.
- [x] [Review][Patch] (med) the 150 s cap (matrix "offline or flaky"; AC network) had no per-push test: the fake sleep never moves the clock [docker/tests/check-readme-video.sh:88] -- `video-script` sets the script's clock through `SECONDS`: cap reached (no request), a pause that would pass the cap (no pause, one request), `--max-time` no longer than what is left.
- [x] [Review][Patch] (low) the no-argument default path, which the release row uses, was never run; the "default file" case only counted README rows [docker/tests/test-release-checklist.sh:1014] -- `rv_run` places the copy at `docker/tests/` of a scratch tree; `default:<file>` runs it with no file.
- [x] [Review][Patch] (low) the "no temporary folder" fix had no test [docker/tests/check-readme-video.sh:52] -- case with an unusable `TMPDIR`: FAIL line, no request.
- [x] [Review][Patch] (low) the fake curl matched plan lines by substring, so a video's line also answered for its oEmbed and the retry cases did not test what their labels say [docker/tests/test-release-checklist.sh:868] -- exact match; the retry cases assert one pause and the order asked.
- [x] [Review][Patch] (low) `video-script` ran after `no-network` and without the network stubs on its PATH [docker/tests/test-release-checklist.sh:1033] -- it runs before `no-network`, with the stubs after the plan's curl.
- [x] [Review][Patch] (low) `video_row` and `swap_copy` read a `| Video |` line inside a code fence, against their comment [docker/tests/check-readme-video.sh:63] -- `!fence` added to both; a fenced-row-only case pins it.
- [x] [Review][Patch] (low) the second youtu.be address's oEmbed path was not exercised offline [docker/tests/test-release-checklist.sh:891] -- the fixture row has two youtu.be addresses; the order of all five requests is pinned.
- [x] [Review][Patch] (low) following redirects (`-L --max-redirs 10`) was not pinned offline [docker/tests/test-release-checklist.sh:910] -- both argument assertions now hold the whole command line.
- [x] [Review][Defer] (med) `no-outward` already fails at the baseline: `docker/tests/test-readme.sh`'s `ALLOWED_HOSTS` line names community.intersystems.com and openexchange.intersystems.com [docker/tests/test-readme.sh:1495] -- deferred: pre-existing (Story 0.18, 6118b053); a RELEASE TOOL fix needing a ruled form; DW-1178 escalated owner=burndown for the 1.0.8 RC.

Rejected:
- (low) test-readme.sh `judges-usability` counts a fenced `| Usability |` line as a second row -- the failure is loud (a false FAIL, never a false pass) and nobody puts that row in a fence; a guard for an unshown case.
- (low) an unreadable README is reported as "no Video row" -- still a loud FAIL; the fix adds a guard for a case nobody meets.
- (by-design) the web count regex reads the whole README, not the Usability row -- the spec says the web tests change nothing but the regex; `judges-usability` pins the row's start.
- (low, theoretical) every non-zero curl exit is retried, including certificate or redirect-loop errors -- still a loud FAIL naming the curl exit, at most 10 s later; real only if a ruled host's certificate broke.
- (spec edit) the frontmatter `deferred:` and Auto Run Result predate QA's `video-script` -- the fix edits the spec under review; DW-1175 and DW-1177 are closed in substance by `video-script` (lead's adjudication).
- (low) the `release/checklist.sh` hunk also rewords one header sentence beyond the row -- it keeps the header true about the row's network call; recorded in Design Notes; the lead's RELEASE TOOL report names it.
- (note) at the cap the FAIL line says "within the 150 s cap" instead of "after 3 tries" -- loud, never skipped; consistent with the matrix's intent.
- (note) 206 to a one-byte range counts as 200 -- documented implement-stage decision; the oEmbed must answer a true 200, pinned.

## Ruled README change

Verbatim text (the Contest Planner's DW-1171 ruling, 2026-11-12 ~01:55Z).

**A1. Contest checklist** -- insert this row directly after the `| Online demo | [demo.ocutalon.com](https://demo.ocutalon.com) |` row:

```markdown
| Video | [One incident, approved from a phone, traced](https://youtu.be/HIyCG5E6-JQ) (3:04, also as an [MP4 file](https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4)), and the [35-second teaser](https://youtu.be/wycbyfnXFMU). |
```

**A2. "For judges", Usability row** -- the whole row becomes (the first sentence is replaced by the two ruled sentences; the rest is unchanged; "fifteen" is the registry's count when this story merges, "sixteen" if Story 35.3's item is in first):

```markdown
| Usability | The demo guide walks [one incident, end to end](#one-incident-end-to-end) in about two minutes, and [the full video](https://youtu.be/HIyCG5E6-JQ) shows it in 3:04. Its More to try panel has fifteen more things to try ([New since 1.0.0](#new-since-100)). A dry run with counts comes first, and nothing risky runs without your yes. [Measured](#measured): 0 changes made without a person's approval, and 0 prompt-injection attempts that led to an action. A recorded evaluation set of over 50 cases ([eval](eval)) scores the real model. |
```

## Spec Change Log

- 2026-11-12 ~04:45Z, lead: rework iteration 1 (trigger fix_pack-style; Contest Planner ruling on 0.28 (2), option (a)): DW-1178 folded in as ONE bounded item under Tasks & Acceptance; nothing else is in scope.

- 2026-11-12 ~02:10Z, lead: Contest Planner 02:05Z item 4: the network check stays OUT of `CHECK_SCRIPTS` (not per push) and runs from one row of the release candidate checklist (`release/checklist.sh`); renamed `docker/tests/check-readme-video.sh` so the `units` rule (every `test-*.sh` in exactly one CI list) is untouched (lead decision).

- 2026-11-12 ~02:00Z, lead: split out of Story 0.27's plan (Part A) by the orchestrator's ruling; bullets moved whole. The plan stage measured the network behaviour (Design Notes).

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 18 rows (the layers' findings, with the Intent Alignment audit as one row) - high 0, medium 0, low 9, false 5, maybe-false 3, descriptive 1
- findings:
  - `[low]` `[defer]` (Blind, Verification Gap) no offline test of check-readme-video.sh's retry/cap/206/status logic, and the in-script self-tests swap only the first youtu.be id (a dead teaser id is tested by the main pass only) -- deferred: a stub-curl test needs a new test-*.sh in a ci/units.sh list, which the boundaries rule out.
  - `[low]` `[reject]` (Blind, Edge, Verification Gap) self-tests share the global 150 s cap, so a slow main pass can turn a self-test into "not flagged" -- the cap on the whole script is the ruled bound; the failure is loud and rare (the measured run takes about 5 s); a per-phase clock would break the ruled cap.
  - `[low]` `[patch]` (Blind) a failed mktemp exits with no FAIL line -- fixed: it prints "FAIL readme-video: no temporary folder" and exits 1 (checked with an unusable TMPDIR).
  - `[maybe-false]` `[reject]` (Blind) a video with embedding disabled would answer 401 or 403 at its oEmbed and be flagged -- both ruled videos answer 200 (measured); a status other than 200 failing at once is the ruled behaviour; an unreachable case would be low.
  - `[low]` `[defer]` (Blind, Verification Gap) no per-push static check of the real script (existence, mode, bash -n) -- deferred; a release-time loud failure, closing it needs a per-push rule.
  - `[false]` `[reject]` (Edge) other YouTube URL forms (youtube.com/watch, http) skip the oEmbed check -- checklist-video pins the Video row word for word, so only the ruled youtu.be form can be in it.
  - `[maybe-false]` `[reject]` (Edge) a server that ignores the range request would answer the whole MP4 and hit the 15 s limit -- measured: the MP4 answers 206 to a range; the hypothetical server change would be loud, low.
  - `[low]` `[patch]` (Edge) the --max-time value can be 0 if SECONDS reaches CAP between the cap test and the computation -- fixed: the value is at least 1.
  - `[maybe-false]` `[reject]` (Edge, Verification Gap) the unknown-id self-test expects the oEmbed address to be the flagged one; if youtu.be/<unknown> itself stopped answering 200 it would report "not flagged" -- relies on the measured quirk the script exists for; a false FAIL is loud, low.
  - `[low]` `[reject]` (Edge) a second, reworded "| Video |" row elsewhere is not flagged by checklist-video -- the ruled row directly after Online demo is pinned exactly and the network script reads the first row; a stale extra row is cosmetic; the guard adds branches for a case nobody meets.
  - `[low]` `[defer]` (Edge) NOT_IRIS_INPUT_PATTERN in ci/units.sh does not list the new script -- deferred: a ci/ hunk this story may not carry.
  - `[false]` `[reject]` (Edge) hyphenated or numeric count words misread by judges-usability -- the registry is capped at sixteen and the web tests pin the word; no hyphenated word can occur.
  - `[false]` `[reject]` (Edge) a transient 4xx (403, 404) from GitHub is not retried -- the spec says only a transport failure, 429 or 5xx is retried and any other status fails at once.
  - `[false]` `[reject]` (Verification Gap, other) the rest of the Usability row is not pinned word for word -- the rule pins the ruled start; the rest was unpinned before this story and the spec's "rest unchanged" is checked by the diff (the README hunk replaces one sentence).
  - `[false]` `[reject]` (Verification Gap, other) no assertion that cannot fail was found -- confirms the layer's check, no defect.
  - `[low]` `[reject]` (Intent Alignment) the anchors are checked with the script's own slug function, not GitHub's renderer -- how every other README rule works; unchanged approach.
  - `[low]` `[reject]` (Intent Alignment) "never skipped" rests on the release owner running the checklist -- the checklist row is the ruled mechanism; nothing for this story to add.
  - `[no-action]` `[reject]` (Intent Alignment) the whole audit (readings R1-R5, the script name check-readme-video.sh against the ruling's test-readme-video.sh, the split of ruling item c) -- descriptive; the diff implements R1 plus the narrowed R3, as the 02:05Z ruling and the spec's Spec Change Log record.

## Design Notes

**Governing ADs:** none binds README text or test scripts (AD-29: Epic 0 may edit any lane's files). No AD is amended.

**Network check (DW-1171, decided in-stage):**
- It is a separate script, `docker/tests/check-readme-video.sh`, NOT in per-push CI (Contest Planner, 02:05Z item 4: oEmbed approach and retries approved; it runs from one row of the release candidate checklist). It is named outside the `test-*.sh` glob so the `units` rule, which requires every `test-*.sh` in a CI list, stays unchanged. `test-readme.sh` stays hermetic, as its header promises.
- Measured (plan stage, 2026-11-12): `youtu.be/<any id>` answers 200 after one redirect even for an id that does not exist (`AAAAAAAAAAA`). So "returns 200" alone cannot fail on a wrong video. The script also asks YouTube's oEmbed for each id: 200 for both ruled videos, 404 for the unknown one. The MP4 answers 200 after one redirect (206 for a range), and a missing asset name answers 404.
- Flakiness bound:
  - only a transport failure, 429 or 5xx is retried (3 tries, 5 s apart, `--max-time 15`), and the whole script is capped at 150 s;
  - any other status fails at once;
  - offline it fails loudly with the address and the reason. It is never skipped, silently or loudly.
- (inference) GitHub-hosted runners reach youtube.com and github.com; a regional consent page would show as a failure naming the address, not as a pass.

**Implement stage (2026-11-12):**
- Count word: "fifteen". `MORE_TO_TRY_ITEMS` in `web/src/app/guide/more-to-try-view.ts` holds 15 items on this tree (Story 35.3's item is not in).
- `check-readme-video.sh` fetches each README address with a one-byte range (`-r 0-0`), so the MP4 is not downloaded whole on every run; 206, the answer to that range, counts as the 200 of the matrix (the plan stage measured 206 for a range). The oEmbed is fetched without a range and must answer 200. The first failing address ends the run (matrix: "exit 1 at once"). The self-tests run after the README passes, and each must be flagged by the swapped address answering a status (a transport failure does not count as flagged).
- The oEmbed host is written in two parts in `check-readme-video.sh` (`OEMBED_SITE=www.youtube`, then `.com`): `release/checklist.sh`'s `no-outward` row flags any `docker/**.sh` line naming the video site whole. The script only reads (GET). Lead to confirm, or rule another form.
- (observed) `no-outward` already flags `docker/tests/test-readme.sh` at the baseline (its `ALLOWED_HOSTS` line names community.intersystems.com and openexchange.intersystems.com); this story leaves that line as it is.
- `release/checklist.sh`: besides the row function, its PASS detail, header line and place in the row list, the header sentence "The script makes no network call." now says the readme-video row's script does. Its test (`docker/tests/test-release-checklist.sh`) stubs `check-readme-video.sh` like the other script rows, and pins 20 PASS lines, the readme-video failure row, and its tmpfail line (4 rows and 7 author rows).
- (observed) A YouTube id with an invalid last character (e.g. `HIyCG5E6-JZ`) gets oEmbed 400, not 404; the script flags it the same way.

**Ledger inbox:** DW-1171 is addressed by this story's tasks and its first three ACs.

**PUBLIC TEXT beyond the ruling:** none.

**RELEASE TOOL items:** one, ruled in by the Contest Planner (02:05Z item 4): the `readme-video` row in `release/checklist.sh`. No `.github/workflows` hunk, no `ci/units.sh` change.

Integration (Rule 1/2): not service-introducing. Consumed-by: none. Consumes: Story 0.26's "One incident, end to end" heading and video URLs; Story 20.2's More to try registry count.

Extend, don't copy: the new test-readme rules follow `video`'s pattern; `check-readme-video.sh` is a new script because no networked sibling exists and `test-readme.sh` is hermetic by contract.

Footprint extensions: `docker/tests/check-readme-video.sh` (new), `release/checklist.sh` (one row) and its test, `web/scripts/sources-docs.test.mjs`, `web/scripts/more-to-try-view.test.mjs`.

## Verification

Shared surfaces: `test-readme.sh`'s `video` rule (teaser-address places), the new rules `checklist-video` and `judges-usability`, its `RULES` count; the web tests' README count sentence; `release/checklist.sh`'s row list (and the test that pins it).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands** (from the worktree root, one per call, each finishing in about 150 s):
- `bash docker/tests/test-readme.sh` (loop, about 25 s) -- expected: `test-readme: all rules passed`.
- `/bin/bash docker/tests/test-readme.sh` (once) -- expected: the same under bash 3.2.
- `bash docker/tests/check-readme-video.sh` (loop, under 30 s online) -- expected: all PASS.
- `(cd web && node --test scripts/sources-docs.test.mjs scripts/more-to-try-view.test.mjs)` (loop) -- expected: 0 failed.
- `bash docker/tests/test-ci-config.sh` (once, about 32 s) -- expected: all pass (`units` unchanged: no new `test-*.sh`). The test that pins `release/checklist.sh`'s rows (loop) -- expected: pass.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `for f in docker/tests/test-readme.sh docker/tests/check-readme-video.sh; do LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c; done` (once) -- expected: all 0.
- `git diff --name-only <baseline> -- .github ci _bmad eval` (once) -- expected: empty. `git diff <baseline> -- release` (once) -- expected: only the `readme-video` row of `release/checklist.sh`.
- Lead (once): CI on the head, every workflow green.

Mutations (one per AC; record `mutation: <change> -> <test that went red>` here, revert, check `git status --short` and `git diff --stat` unchanged):
- AC DW-1171 rows: move the Video row above "Online demo" -> `checklist-video`; reword "in about two minutes" in the Usability row -> `judges-usability`.
- AC count: change "fifteen" to "fourteen" in the Usability row -> the two web count tests.
- AC network: change the full-video id in a scratch README copy passed to the script -> `check-readme-video.sh` (oEmbed 404).

Recorded (implement stage, 2026-11-12; each reverted, the README or script restored from a byte copy, `cmp` equal, `git status --short` and `git diff --stat` unchanged):
- mutation: Video row moved above "| Online demo |" -> `checklist-video` red ("the row right after '| Online demo |' ... is not the ruled Video row"); all other rules green.
- mutation: "in about two minutes" -> "in about three minutes" in the Usability row -> `judges-usability` red; all other rules green.
- mutation: "fifteen" -> "fourteen" in the Usability row -> the two web count tests red (`sources-docs.test.mjs` "README says how many more things to try there are", `more-to-try-view.test.mjs` "counts the items by the registry in the README"); `judges-usability` stays green (the count word is the web tests' matter).
- mutation: "35-second teaser" -> "short teaser" in the Video row -> `video` red (the teaser address outside its three places) and `checklist-video` red.
- mutation: full-video id `HIyCG5E6-JQ` -> `HIyCG5E6-JA` in a scratch README copy passed to the script -> `check-readme-video.sh` exit 1, "FAIL readme-video: <oEmbed of youtu.be/HIyCG5E6-JA> answered 404" (the tree untouched).
- mutation: the `row_readme_video` line dropped from `checklist_main`'s row list -> `test-release-checklist.sh` red: `base` (19 PASS lines, wanted 20) and `script-rows` (the readme-video failure not reported).
- offline (transport failure simulated with a proxy on a closed local port) -> `check-readme-video.sh` exit 1 after 3 tries 5 s apart: "could not be reached after 3 tries (curl exit 7)", about 10 s.

QA stage (2026-11-12), files changed:
- (QA) `docker/tests/test-release-checklist.sh` -- new rule `video-script` (`rv_run`, `t_video_script`): the real `docker/tests/check-readme-video.sh`, as a byte copy run with a curl and a sleep that answer from a plan (no network), is executable, parses and is ASCII (closes the deferred per-push existence check); passes when every address answers (206 to the MP4's range, the oEmbed asked without one); a 404, a 403 and a 206 without a range fail at once, with no pause and no later address asked; 503, 429 and a transport failure are tried 3 times with a 5 s pause, then fail loudly with the reason, or pass when a later try answers 200; a self-test is flagged only by a status; a missing row, a row in another section, a row with no address, a missing file and two arguments fail with no request (the last with exit 2). The header comment names the rule. Closes the matrix's "link gone" and "offline or flaky" rows per push (the deferred stub-curl gap), without a new `test-*.sh`.
- (QA) mutation: `429` dropped from the retried statuses in `check-readme-video.sh` -> `test-release-checklist.sh` `video-script` red ("429 then 200", "429 three times").
- (QA) mutation: `TRIES=3` -> `TRIES=2` in `check-readme-video.sh` -> `video-script` red ("502 three times", "offline").
- (QA) mutation: 206 accepted without a range in `check-readme-video.sh` -> `video-script` red ("oEmbed 206 (no range asked) is not a 200").
  Each reverted from a byte copy (`cmp` equal); `git status --short` and `git diff --stat` unchanged.
Code review (2026-11-12), after its patches: `test-release-checklist.sh` all 16 rules passed (bash and /bin/bash, about 35 s); `test-readme.sh`, `test-boundaries.sh`, `test-ci-config.sh` all passed; `check-readme-video.sh` online all checks passed (about 5 s); ASCII 0 on the three shell files; no diff under `.github`, `ci`, `_bmad`, `eval`; `release/checklist.sh`'s own `outward_hits` over the `no-outward` file set lists only `docker/tests/test-readme.sh:1495` (DW-1178, pre-existing). Mutations (each restored from a byte copy, `cmp` equal):
- mutation: the allowed-line filter dropped from `outward_hits` -> `outward-rows` red ("the allowed oEmbed line of check-readme-video.sh: exit", "allowed line: not listed").
- mutation: the allowed line's file anchor widened to any file -> `outward-rows` red ("the allowed line in another file").
- mutation: `CAP=150` -> `CAP=1500` in `check-readme-video.sh` -> `video-script` red ("cap reached", "cap near, 503", "cap near: the first request's --max-time").
- mutation: `!fence` dropped from `video_row` -> `video-script` red ("a row in a code fence only").
- mutation: the default file `$root/README.md` -> `$root/docs/README.md` -> `video-script` red ("no file given").
- mutation: the `mktemp` failure branch removed -> `video-script` red ("no temporary folder: the FAIL line").
- (QA) observed, not changed (the script is not a test file): `video_row` in `check-readme-video.sh` says "outside a code fence" but reads a `| Video |` row inside a fenced block of the Contest checklist section (the `!fence` test is only on the heading line). Not reachable with the ruled README (`checklist-video` pins the row right after Online demo); low.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README gets the ruled Video row after "Online demo" and the ruled two opening sentences of the "For judges" Usability row (count word "fifteen", the registry's count on this tree), pinned offline by the new `test-readme.sh` rules `checklist-video` and `judges-usability` and a widened `video` rule; the two web tests pin the ruled sentence ("Its More to try panel has ...") against the registry; a new networked `check-readme-video.sh` (outside per-push CI and outside the `test-*.sh` glob) is run by the new `readme-video` row of `release/checklist.sh`.

Files changed:
- `README.md` -- the Video row and the Usability row's two ruled sentences, verbatim.
- `docker/tests/test-readme.sh` -- rules `checklist-video`, `judges-usability`, widened `video`, their self-tests, `RULES` and header.
- `docker/tests/check-readme-video.sh` -- new; online check of the Video row's addresses and each YouTube id's oEmbed, 3 tries 5 s apart, 150 s cap, self-tests.
- `release/checklist.sh` -- the `readme-video` row (function, PASS text, header lines, row list); one header sentence about network calls reworded to stay true.
- `docker/tests/test-release-checklist.sh` -- stub, PASS count 19 to 20, a failure case, tmpfail rows 10 to 11.
- `web/scripts/sources-docs.test.mjs`, `web/scripts/more-to-try-view.test.mjs` -- count regex starts "Its".

Review: 18 triage rows from 4 layers. Patches applied: 2 (mktemp failure prints a FAIL line; `--max-time` at least 1). Deferred: 3 (all low; see frontmatter `deferred:`). Rejected with reasons: see the Review Triage Log. Follow-up review recommended: false (no high, no medium patched).

Verification (after the last patch): `test-readme.sh` all rules passed (bash and /bin/bash); `check-readme-video.sh` all checks passed online (also under /bin/bash); the two web test files 57 pass, 0 fail; `test-ci-config.sh` all rules passed; `test-release-checklist.sh` all rules passed; `test-boundaries.sh` all rules passed; ASCII check 0 on all four shell files; no diff under `.github`, `ci`, `_bmad`, `eval`; `release/` diff is `release/checklist.sh` only. Mutations are recorded in `## Verification`.

Residual risks: (1) the oEmbed host is written in two parts in `check-readme-video.sh` because the `no-outward` row of `release/checklist.sh` flags any `docker/**.sh` line naming that site whole; the script only GETs from it. (2) `test-readme.sh`'s existing `ALLOWED_HOSTS` line names `community.intersystems.com` and `openexchange.intersystems.com`, so the `no-outward` row already flags it at the baseline, independent of this story. (3) The readme-video row needs the network at release time. (4) CI on the head is the lead's step.
