---
title: "Story 0.28: DW-1171 follow-up: the README's Contest checklist gets a Video row, and the For judges Usability row links the incident path and the full video"
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
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

**Acceptance Criteria:**
- Given the README (DW-1171), when the Contest checklist and the "For judges" table are read, then the ruled Video row sits right after "Online demo" and the Usability row opens with the two ruled sentences, the rest unchanged; `test-readme.sh` passes `checklist-video`, `judges-usability`, `video` and `readme-links`, and fails on each bad copy.
- Given the More to try registry, when the web tests run, then the README's count word in "Its More to try panel has ... more things to try" equals the registry's item count (fifteen now; sixteen once Story 35.3's item is in), and a README saying another number fails.
- Given the network, when `bash docker/tests/check-readme-video.sh` runs, then every Video row link answers 200 and each YouTube id's oEmbed answers 200, and the copy with an unknown id or a missing MP4 is flagged; offline it fails loudly after its bounded retries and is never skipped.
- Given the release candidate checklist, when `release/checklist.sh` runs its automated rows, then `readme-video` runs `docker/tests/check-readme-video.sh` and reports PASS or FAIL like the other script rows.
- Given CI on this story's head, when it finishes, then every workflow is green (the network check is not run per push).

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

- 2026-11-12 ~02:10Z, lead: Contest Planner 02:05Z item 4: the network check stays OUT of `CHECK_SCRIPTS` (not per push) and runs from one row of the release candidate checklist (`release/checklist.sh`); renamed `docker/tests/check-readme-video.sh` so the `units` rule (every `test-*.sh` in exactly one CI list) is untouched (lead decision).

- 2026-11-12 ~02:00Z, lead: split out of Story 0.27's plan (Part A) by the orchestrator's ruling; bullets moved whole. The plan stage measured the network behaviour (Design Notes).

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Split out of Story 0.27's plan by the lead on the orchestrator's ruling; implement after Story 0.26 merges.
