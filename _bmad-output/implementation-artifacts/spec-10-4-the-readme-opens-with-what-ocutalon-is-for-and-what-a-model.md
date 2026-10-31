---
title: 'The README opens with what OcuTalon is for, and what a model adds'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '095c523433cac9e1285745aca38b7d8f16efe7c5'
baseline_commit: '095c523433cac9e1285745aca38b7d8f16efe7c5'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['oversized']
deferred:
  - summary: >-
      The README opening ("Every decision is in Visual Trace with its reasons and cost") and the unchanged "Each decision shows its reasons, its confidence and its cost" line may read as an overclaim for a fixed-rules decision, which keeps only the fallback reason.
    evidence: |-
      Design Note 1 row "Opening: ... Visual Trace with its reasons and cost" records "a fallback row keeps no reasons or payload" yet agrees. A reviewer read this as a possible overclaim. The opening is the owner's text and was not changed.
    location: >-
      README.md:3 and README.md:34
    severity: low (unverified)
---

<intent-contract>

## Intent

**Problem:** The README's top shows a "Contest task → where to see it" table before it says what OcuTalon is for, and "What OcuTalon does" ends on "No key, still works.", which makes a model look unnecessary. From the online demo launch (Sat Oct 31 19:00Z at the earliest) the feature branch is GitHub's default and its README is what visitors see.

**Approach:** Edit `README.md` exactly as Story 10.4 (epics.md) says, copying the owner's text byte for byte from that story's block, re-pin the new shape in `docker/tests/test-readme.sh`, and mark Story 10.2's top-of-the-README criterion as amended.

## Boundaries & Constraints

**Always:**
- Copy the owner's text from Story 10.4's block in `epics.md` byte for byte. The block is pure ASCII: straight apostrophes and quotes, and no em dash. Never polish, re-wrap or re-punctuate it. Each quoted paragraph, item and table row is one README line, as the block holds it.
- The teaser line stays exactly `Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU`. It is moved, never edited.
- The README starts with these lines: `# OcuTalon`, a blank line, the opening paragraph, a blank line, the teaser line, a blank line, then `## Try it in two minutes`. The first three H2s are "Try it in two minutes", "What's interesting" and "What you can use it for". The "Contest task → where to see it" section (its H2, table and teaser line) is gone. Every remaining H2 and its text stay as they are, except for the "No key, still works." bullet.
- In "What OcuTalon does", the "No key, still works." bullet's place is taken by a blank line, the paragraph, a blank line and the five table lines. Nothing else in that section changes. The "Set a model key" sentence "Without a key, OcuTalon still starts. Every decision uses fixed rules, and the page shows a notice that says so." stays as it is.
- Every `test-readme.sh` rule other than `top`, `teaser`, `contest-table` and `key-account` keeps its checks, above all `public-text` (no "from your phone"), `no-telegram`, `dev-only`, `readme-links` and `product-links`. The not-affiliated note stays word for word, and the new text adds no OpenClaw mention.
- `test-readme.sh` stays hermetic and runs under bash 3.2 with BSD or GNU tools. Each changed or new rule first proves on broken copies that it can still flag, using the file's own `st` self-test pattern. Each one fails closed when README.md is missing.
- Footprint: `README.md`, `docker/tests/test-readme.sh`, Epic 10's story blocks in `epics.md`, and `_bmad-output/implementation-artifacts` for Epic 10.

**Never:**
- Never change a table cell, the opening paragraph or a use-case item to match the build or a rule. A contradiction is reported to the lead as an intent gap, never edited.
- Never add any of the later additions: Story 30.4's sentence, the Telegram sentence, Story 13.3's third item, screenshots, a flow diagram, the measured 0.1.0 line or a CI badge.
- No committed file holds a local absolute path, a key, private infrastructure, a rival entry or entrant, "IRIS Couch" or another model provider.
- Nothing changes under `src/`, `web/`, `ci/` or in `docker/tests/lib-scan.sh`. No IRIS, slot, throwaway or MCP call is needed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Real README | the edited tree | `test-readme.sh` prints 21 PASS lines (top, try-it, interesting, use-cases, teaser, outcomes, install, install-pointer, commands, key-account, lan, sign-in-address, demo-mode, admin-commands, after-start-log, dev-only, public-text, no-telegram, product-links, readme-links, must-scan) and `SKIP #telegram`, and exits 0 | No error expected |
| Opening drifts | a word of the opening paragraph changed or the paragraph removed; a stray line under the title; the opening and the teaser swapped | `FAIL top` naming the README line | exit 1 |
| Order drifts | "What you can use it for" renamed, or moved before "What's interesting"; a "Contest task" heading or the line `\| Contest task or criterion` back | `FAIL top` | exit 1 |
| Teaser drifts | the teaser changed, given twice, put above the opening or under the first H2, or with no blank line between it and the opening; an image or embed anywhere | `FAIL teaser` | exit 1 |
| Use cases drift | an item changed, removed or swapped; a third item; Story 30.4's sentence appended | `FAIL use-cases` | exit 1 |
| Model table drifts | the paragraph or a cell changed; a row removed; the table moved out of "What OcuTalon does"; "No key, still works." back; the "Set a model key" sentence changed or moved | `FAIL key-account` | exit 1 |
| No README | README.md absent | every rule prints `FAIL ...: README.md is missing`, `use-cases` included | exit 1 |

</intent-contract>

## Code Map

- `README.md` -- today: Try it (line 3), What's interesting (14), the Contest task H2, its table (18-29) and the teaser (31); What OcuTalon does (33-48), with the "No key" bullet at 48; the "Set a model key" fixed-rules sentence at 135. The arrow on line 18 is its only non-ASCII byte, so the result is pure ASCII.
- `_bmad-output/planning-artifacts/epics.md` -- Story 10.4's block runs from `### Story 10.4:` to `## Epic 11:`. Its quoted text is the three runs of `> ` lines: the opening (1 line), the items (2), and the paragraph, a bare `>` and the table (7). Story 10.2's criterion starts at `**Given** the top of the README, right after "Try it in two minutes"` and ends at its `[AMENDED 2026-10-23 ...]` line. The table bullet is its fifth line.
- `docker/tests/test-readme.sh` -- what this story changes in it:
  - constants (105-118): `ARROW`, `H_TABLE`, `TEASER`, `OTHER_H2`;
  - helpers: `section` (133), `chk_facts` (142), `st`, `st_move`, `st_append`, `st_facts`, `strip_str` (165-214), `rule_begin` and `finish` (217-246);
  - `chk_top` (251, "only blank lines" under the title) and `chk_table` with `TABLE_ROWS` (315-334, removed);
  - `chk_teaser` (337, "last line of the table's section");
  - `chk_key_account` (422). Its whole-file `fixed rules` fact in `KEY_FACTS` (415) is the only check the "No key" bullet fed (`outcomes` pins only the four outcome bullets);
  - rules: `rule_top` (681), `rule_contest_table` (724, removed), `rule_teaser` (738) and `rule_key_account` (806);
  - the slug self-test in `rule_readme_links` (1016) links `#contest-task--where-to-see-it`, which goes red once the heading is gone;
  - `RULES` (1031) and the header's "What it pins" list (5-37).
- `docker/tests/lib-scan.sh` -- `scan_files`, `scan_rule`: read only.
- `ci/units.sh` -- `readme` stays in `CHECK_SCRIPTS` (line 6). README.md, `docker/tests/test-*.sh` and `_bmad-output/` are not IRIS inputs (`NOT_IRIS_INPUT_PATTERN`, `BOOKKEEPING_PATTERN`). So this push runs the hosted `checks` job and skips the IRIS groups (inference; `ci/changes.sh` decides).
- Continuity: Story 10.2's spec (`## Verification`) gives the matrix and mutation format, and its Claims list (C1-C96) covers the README sentences this story keeps. Story 10.3 kept `Included()` test-only, so `no-telegram` still refuses the word.

## Tasks & Acceptance

**Execution:**
- `README.md` -- make the four edits: remove the Contest task H2 and its table; put the opening, a blank line and the teaser under the title; add "What you can use it for" right after "What's interesting"; replace the "No key" bullet. Copy every quoted line from the epics.md block, not from this spec -- the owner's exact text.
- `docker/tests/test-readme.sh` -- make the changes in Design Note 2 -- they pin ACs 1-3 and 5 and keep every other rule.
- `_bmad-output/planning-artifacts/epics.md` -- apply Design Note 3's replacement to Story 10.2's criterion -- Story 10.4's last test criterion.
- this spec -- record the Verification results and one `mutation:` line per AC -- Rule 19.

**Acceptance Criteria:**
- AC1: Given the README, when a judge opens it, then the "Contest task → where to see it" H2 and its table are gone, and right under "# OcuTalon" come the opening paragraph (byte for byte from epics.md), one blank line and the teaser line as it reads today, then the H2s "Try it in two minutes", "What's interesting" and "What you can use it for".
- AC2: Given "What you can use it for", when a judge reads it, then it holds exactly the two items, byte for byte, and none of the three later additions.
- AC3: Given "What OcuTalon does", when a judge reads it, then "No key, still works." is gone, its place holds the paragraph and the three-row table byte for byte, and the fixed-rules sentence in "Set a model key" is unchanged.
- AC4: Given the build at this story's base, when every table cell, the opening paragraph and the two items are checked against the code and the tests, then each one agrees (Design Note 1), and the story's diff touches nothing under `src/`, `web/` or `ci/`, so the evidence still holds.
- AC5: Given `test-readme.sh`, when it runs on the real tree, then it prints exactly the 21 PASS names of the matrix plus `SKIP #telegram` and exits 0; `contest-table` is gone, and each rule goes red on its matrix row.
- AC6: Given epics.md, when a reader reads Story 10.2's top-of-the-README criterion, then it describes the new top and carries an `[AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; ...]` marker that quotes its table line and its teaser line as they read before.
- AC7: Given the story's diff, when it is reviewed, then it touches only the footprint, holds no local absolute path, and adds no screenshot, diagram, badge or 0.1.0 line (the `teaser` rule's embed scan refuses any image).

### Review Findings

Code review 2026-10-31 (bmad-code-review, tier full-opus; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 26 rows, 6 entries after grouping: high 0, medium 2, low 4. Each entry gives severity / fix-risk / footprint / spec-status (Rule 15).

- [x] [Review][Patch] G1 (medium / low: test-only, self-tests prove each branch / in-story / clear): `key-account` pins the model block anywhere in "What OcuTalon does" and does not check the lines around it. With the empty line above the paragraph removed, GitHub renders the paragraph inside the Reminders bullet as a lazy continuation. A pipe-less line right under the last row renders as a fourth row. The block can also move up the section, out of the bullet's place (AC3, Always). In each case all 21 rules stay green. Sources: verification-gap+edge-case-hunter+acceptance-auditor. [docker/tests/test-readme.sh:483]
- [x] [Review][Patch] G3 (medium / low: a check of the same kind as the no-readme loop / in-story / clear): CI does not see a rule dropped from `RULES` (AC5's pin is a spec command that CI does not run). With `use_cases` dropped, the script prints 20 PASS lines and exits 0. Sources: verification-gap+blind-hunter. [docker/tests/test-readme.sh:1111]
- [x] [Review][Patch] G2 (low / low / in-story / clear): `chk_top`'s branch for a stray line under the title (the only guard for a line between the teaser and the first H2, such as the banned 0.1.0 line) has no self-test that only it catches. Source: verification-gap. [docker/tests/test-readme.sh:302]
- [x] [Review][Patch] G4 (low / low / in-story / clear): the header says `top` refuses "no row of that table", but `chk_top` refuses only the heading and the header row. Sources: blind-hunter+edge-case-hunter. [docker/tests/test-readme.sh:8]
- [x] [Review][Patch] G5 (low / low / in-story / clear): the self-test 'the use cases section moved down' renames the heading instead of moving it, so it repeats 'renamed'. Sources: blind-hunter+verification-gap. [docker/tests/test-readme.sh:750]
- [x] [Review][Defer] G7 (low / low / in-story / spec-bound): Story 10.2's Given line still reads "right after 'Try it in two minutes'", and its first criterion "it starts with 'Try it in two minutes'", while its amended Then puts the teaser above that heading. Design Note 3 prescribes the text and decided-in-stage (e) leaves the first criterion, so it is closed `by-design` as DW-481; the lead may add a marker at its gate. Source: acceptance-auditor. [_bmad-output/planning-artifacts/epics.md:3540] — deferred: spec-bound (Design Note 3, decided-in-stage (e))

Rejected:
- `low` Blind 1: the QA block says `top` has "nine self-tests" (it had 12). The fix edits QA's record in the spec; the review's verification line below records the current count.
- `low` Blind 2 + Acceptance 4 + Edge 8: DW-480 and the spec's `deferred` location cite README.md:34. The line "Each decision shows its reasons, its confidence and its cost." is README.md:36. The fix edits the spec's frontmatter and a write-once ledger body. It is reported to the lead for DW-480's adjudication.
- `low` Blind 6: the `rows -ne 5` count would also flag an unrelated table in "What OcuTalon does". The Always rule says nothing else in that section changes, so the count is right, and its message is clear enough.
- `false` Blind 7: the README repeats the use cases in "What OcuTalon does". The opening and use cases summarise the detail below by the owner's design, the text is the owner's word for word (Never), and no harm is named.
- `low` Edge 3: no self-test reaches only `chk_teaser`'s "below the first H2" branch. In the only README state that reaches it (opening and teaser both under the first H2), `top`'s `chk_block` also fails, so the gap is theoretical.
- `low` Edge 7: `top` passes with the opening in a code fence lower down and only the teaser at the top. This is not a realistic edit, and `teaser` fails on it (the teaser is not two lines below the opening).
- `low` Acceptance 1: no check pins the empty line between the teaser and `## Try it in two minutes`. An ATX heading ends a paragraph, so the page renders the same either way, and the fix would add a guard with no user-visible effect.
- `false` Acceptance 3: the manual footprint record names four files, while the diff also holds the cycle log, sprint-status and ledger. Those are the lead's bookkeeping commit `73e3807a`, inside the footprint, so AC7 holds.
- `low` Acceptance 5: AC4 says every claim agrees while DW-480 is open. Checked: `Result` carries `FallbackReason` and `CostUSD` (`src/bridge/cls/OcuTalon/Bridge/Msg/Result.cls:12,42`), so the build does not contradict the opening. DW-480 is already on the ledger, and the lead adjudicates it.
- `low` Acceptance 7: the `top` FAIL for a removed or swapped opening names the missing line's text, not its number. That is cosmetic, because the text names the line.

## Spec Change Log

## Review Triage Log

### 2026-10-31 - Review pass
- verdicts: 19 findings (rows; the verification-gap pair on the opening paragraph shares one row) - high 0, medium 1, low 10, false 7, maybe-false 1
- findings:
  - `[low]` `[defer]` Blind 1: the opening and the unchanged "Each decision shows its reasons ..." line say a decision shows reasons and cost, while a fixed-rules row keeps only the fallback reason -- owner text, plan-stage Design Note 1 judged it agreed; not changed here (Never: no cell or opening edits). Recorded unverified for the Contest Planner (deferred).
  - `[false]` `[reject]` Blind 2: "a fix with a dry run" is not always true -- the cell describes the row's date-format case, which Design Note 1 verified; owner text, and an edit would break the byte-for-byte rule.
  - `[low]` `[patch]` Blind 3: `rule_key_account` declared an unused `local n` -- removed the declaration.
  - `[false]` `[reject]` Blind 4: the Auto Run Result status reads stale -- finalize rewrites it in this pass.
  - `[false]` `[reject]` Blind 5: `chk_block` matches anywhere, so `top` does not pin the opening to the top -- line 1 must be the title (checked), and any non-blank line before the first H2 other than the opening and the teaser is flagged, so the block can only sit at the top.
  - `[low]` `[reject]` Blind 6: Story 10.2's criterion is loosely formatted -- it is the text Design Note 3 prescribes; the fix edits the spec's prescription.
  - `[low]` `[reject]` Blind 7: the removed table's repository pointers have no replacement -- the owner removed the section; the "add it back later" follow-up belongs to the lead.
  - `[low]` `[patch]` Edge 1 and Verification-gap 2: the opening paragraph could appear twice and `top` stayed green -- `chk_top` counts the opening and flags more than one; self-test 'the opening paragraph twice' added.
  - `[low]` `[reject]` Edge 2: the Contest task heading and header-row match only one casing and spacing -- unlikely drift; the fix is a looser regex for a case the owner text does not show.
  - `[low]` `[reject]` Edge 3: the "No key, still works." refusal is case- and period-sensitive -- the spec names that exact string.
  - `[low]` `[reject]` Edge 4: the "Set a model key" sentence is a substring match -- `chk_facts` semantics, the same as every fact the rule held before.
  - `[medium]` `[patch]` Verification-gap 1: a fourth row in the model table kept every rule green -- `chk_key_account` now counts the `|` lines of "What OcuTalon does" (5); self-test 'a fourth row added to the model table' added.
  - `[low]` `[patch]` Verification-gap 3: the "non-empty line where the blank is" branch of `chk_teaser` had no self-test -- self-test 'a stray line where the empty line is' added; without the branch `FAIL teaser` goes red.
  - `[false]` `[reject]` Verification-gap AC4 note: AC4 has no pinning test by design (a recorded check, mutation line "none").
  - `[false]` `[reject]` Intent-alignment (1)-(3): descriptive; the diff implements the byte-for-byte reading (A) and its tests exercise the raw file, as the spec says.
  - `[false]` `[reject]` Intent-alignment: no rendering test exists -- the spec calls for text pins; the shape (blank lines before the table) is pinned by `chk_block`.
  - `[false]` `[reject]` Intent-alignment: the constants and the README agree by construction -- the spec's byte check against epics.md is the independent check, and it printed `checked 9`.
  - `[maybe-false]` `[reject]` Intent-alignment: claims versus pinned text -- the script pins wording; Design Note 1 holds the code evidence, and a behaviour change is outside this story.
  - `[low]` `[reject]` Intent-alignment: the old table's repository links are gone from the top -- owner decision (observation only).

## Design Notes

**1. Claims checked against the build (plan stage, base `a627b7cc55037947ec826db1f8474069490476a9`).** Every claim agrees, so there is no intent gap.

| Cell or claim | Built behaviour | Evidence | Agrees? |
| --- | --- | --- | --- |
| "Claude Haiku 5.5 by default" | every agent's model is `claude-haiku-5-5` | `Agent/Triage.cls:7`, `Agent/Chat.cls:11`, `Agent/Diagnosis.cls:7` | yes |
| "no model key, or ... can't give a usable answer, it falls back to fixed rules" | a precheck for a missing key gives `no_key`; refusal, empty, cut-off, error, timeout, rate limit, budget and invalid each give a fallback | `Bridge/Process/Decide.cls:592,669,647-680`; `Test/Bridge/Fallback.cls`; `Test/Agent/Decide.cls:487` (mock `refusal`, `empty`, `max-tokens`, `provider-error`, `invalid-reply`) | yes |
| "says so on the page" | the no-key banner ("...so every decision uses fixed rules..."); a fallback shows Tell now, the Fallback flag and the reason | `web/src/app/msg/catalog.ts:14`; `web/e2e/banners/banners.spec.ts:190`; `web/src/app/chat/decision-strip.ts:67-68,92,220` | yes |
| "and in Visual Trace" | `Result` (an `Ens.Response`) carries `Fallback` and `FallbackReason`; its XML shows in Visual Trace | `Bridge/Msg/Result.cls:2,18-21`; `Test/Agent/Decide.cls:1169-1171` (TestTraceFields) | yes |
| Item, with a model: "decides Ignore, Digest, Tell now or Act, and says why" | the row's outcome and reasons; the Tell now notice's "Why now:" comes from the first reason; a user's own item is never ignored or digested | `Core/Rule/Notice.cls:47-49`; `Msg/Catalog/Core.cls:236`; `Decide.cls:728`; mock `mail-act`, `mail-digest`, `mail-ignore`, `mail-tell-now` | yes |
| Item, fixed rules: "Tell now, marked as a fallback with the reason" | outcome `tellnow`, `Fallback` 1, the reason, no act; notice `notice.tellNowFallback` with the reason; page chip and flag | `Decide.cls:894-898`; `Core/Intake.cls:184`; `Core/Rule/Notice.cls:39-42`; `Msg/Catalog/Core.cls:244-248`; `Test/Core/Intake.cls:272` | yes |
| 50 orders, with a model: "One incident, with the cause in plain English, the part at fault, and a fix with a dry run" | the diagnosis stores cause, `elementAtFault` and fix; the with-fix notice gives cause, fix and dry run; the card's evidence line shows the element | `Watch/IncidentManager.cls:658-666`; `Msg/Catalog/Watch.cls:78-80`; `web/src/app/incidents/incident-view.ts:232-244`; mock `diagnosis` | yes, for the row's date-format case. A cause with no fix in the fixed set gets `incident.noFix` (`Watch.cls:130`). |
| 50 orders, fixed rules: "Grouped by item and error, with no cause and no fix" | groups keyed by `ItemName` and `ErrorPattern`; a fallback stores no cause, element or fix; notice `incident.fallback` ("I couldn't work out the cause ..., so I'm not proposing a fix") | `Data/FailureGroup.cls:13-16`; `IncidentManager.cls:306,343-344,653-656,679-680`; `Watch/Notice.cls:87`; `Msg/Catalog/Watch.cls:119-120`; `Test/Watch/NoticeText.cls:242` | yes |
| Chat, with a model: "answers, watches a production or sets a reminder" | a turn's reply; the built-in tools `start_watch` and `set_reminder` | `Tools/Names.cls:6,12`; mock `chat`, `guide-watch`, `guide-reminder` | yes |
| Chat, fixed rules: "says it couldn't answer, and why" | `conversation.turnFallback` "I couldn't answer that: {fallbackReason}. Nothing was changed." | `Core/Conversation.cls:66-67`; `Msg/Catalog/Core.cls:157-158`; `Test/Core/ConversationTurns.cls:717`; `Test/Agent/Decide.cls:1200` | yes |
| Opening: risk rules the model can't change; approvals audited; "Visual Trace with its reasons and cost"; "fails safe ... claims nothing" | the gate classifies by code, settings or the admin's table and treats unclassified as risky; no release-1 tool changes a classification; each answer writes an Approval audit entry; trace XML holds reasons and usage; a fallback row keeps no reasons or payload | `Bridge/Policy/Gate.cls:10-19`; `Tools/Names.cls`; `Bridge/Approval.cls:13,277`; `Test/Agent/Decide.cls:28-35`; `Decide.cls:894-899` | yes |
| Opening and items: one notice, fix and dry run, resend after approval, the count, two minutes, plain-words watch, one incident, no false all-clear | as the README already says (Story 10.2 Claims C27, C28, C32, C35, C47-C52); the all-clear only from code | `Checks/ReplyGuard.cls:4,17-21`; `web/src/app/guide/guide-view.ts:27` ("About 2 minutes"); `web/src/app/chat/chat-view.ts:60-61` | yes. "usually fifty times" is about the reader's integrations, not a product claim. |

**2. `test-readme.sh` changes.**
- Add a helper `chk_block <label> <file> <lines>` beside `chk_facts`, which prints a problem unless the lines appear consecutively, each word for word. `top`, `use-cases` and `key-account` all use it, so no per-rule copy is needed (Rule 2).
- **top** checks:
  - the title;
  - the opening paragraph as the first non-blank line under it;
  - no other non-blank line before the first H2 except the teaser;
  - the first three H2s (Try it, What's interesting, What you can use it for);
  - `OTHER_H2`;
  - no heading that starts with "Contest task", and no line that starts with `| Contest task or criterion`.

  Self-tests: a stray line, the title changed, Try it and What's interesting swapped, the use-case section moved down, a required section removed, the opening changed, the opening removed, and the Contest task H2 re-added.
- **teaser** checks:
  - the teaser line appears once;
  - it sits two lines below the opening, with an empty line between them, before the first H2;
  - the existing embed scan.

  Self-tests: removed, changed, twice, moved to the end, put above the opening, put under the first H2, the blank line between dropped, and the six embed cases.
- **use-cases** (new): the non-blank lines of "What you can use it for" are exactly item 1 then item 2. Self-tests: each item changed, removed or swapped; a third item; Story 30.4's sentence appended; Story 13.3's item appended.
- **key-account** keeps the key line, `.env.example`, `Claude Haiku 5.5`, the account and "Sign in to Visual Trace". The whole-file `fixed rules` fact is replaced by two checks:
  - the "Set a model key" sentence, word for word, inside its section;
  - in "What OcuTalon does", the block: the paragraph, an empty line and the five table lines.

  It also refuses `No key, still works.` anywhere. Self-tests: each block line stripped, a cell changed, a row removed, the table moved out of the section, the bullet re-added, and the sentence moved out of its section.
- **Removed:** `rule_contest_table`, `chk_table`, `TABLE_ROWS` and `H_TABLE`.
- **readme-links:** the slug self-test appends its own heading, built with `ARROW`, to the scratch copy (`## Contest task $ARROW where to see it`, linked as `#contest-task--where-to-see-it`). The arrow case stays pinned without the README holding the heading.
- **Housekeeping:** add `use_cases` to `RULES` after `interesting`, and remove `contest_table`. Update the header (Stories 10.2 and 10.4; FR-4, FR-38) and its "What it pins" lines. These are contract comments only (Rule 14).
- **Constants:** the text constants are ASCII, so they need no escapes. Item 2 holds double quotes, so give it single quotes in bash. The paragraph and the third table row hold apostrophes, so give them double quotes.

**3. epics.md: Story 10.2's criterion.**
- Replace its `**Then** it has, in this order:` line and the three bullets after it with:
  ```
  **Then** it has, in this order:
  - a short "What's interesting" section, of about 120 words at most, that says what is technically interesting in what the release ships and why it was built that way;
  - and Story 10.4's "What you can use it for" section (FR-58).
  The teaser video's link, which the author gives, is the line right under Story 10.4's opening paragraph, above "Try it in two minutes" (FR-58).
  ```
- Keep the `[AMENDED 2026-10-23 ...]` line.
- After it, add this line:
  ```
  [AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: "I'm not sure that I want to keep the "Contest task -> where to see it" section. Let's remove it for now and consider adding it back in later if it makes sense." Story 10.4 removes the table and moves the teaser line under its opening paragraph. The table line read: "a "Contest task → where to see it" table that maps each part of the contest task (an IRIS Interoperability workflow, an IRIS AI Hub agent and a decision-making task) and each judging criterion (Complexity, Clarity of Instructions, Developer Experience, Applicability and Usability) to the feature that meets it and the place in the online demo or the repository that shows it;" and the teaser line read: "and the teaser video's link, which the author gives (until then there is no video line and no placeholder) (FR-58)."]
  ```
  The two quotes are the old bullets without their `- `. Copy them from the old lines rather than from this spec, so the arrow's bytes stay as they are.
- The `**And** every sentence and table row ...` line stays as it is: the model table's rows ship.

**4. Architecture decisions.**
- AD-8 (fallback semantics), AD-15 (grouping and the notice variants), AD-10 (fixed risk rules), AD-17 (audit) and AD-28 (no false all-clear) back the claims.
- AD-29 makes README.md and `test-readme.sh` Lane B's files.
- AD-22 runs `test-readme.sh` in the hosted `checks` job.
- No acceptance criterion contradicts an AD's Rule.

**5. Rules 1, 2 and 17.** This story introduces no service, module or shared component. It changes the README and its hermetic check, so no Integration AC applies.
- Consumes: none.
- Consumed-by: no new consumer. The page's README anchors (`product-links`) and `install.sh`'s Troubleshooting pointer (`install-pointer`) read headings this story keeps. A `git grep` of the tracked tree finds `contest-task` and "No key, still works" only in README.md and `test-readme.sh`.
- Ledger inbox: none.

**6. Punctuation.** `test-readme.sh`, `lib-scan.sh` and `ci/` have no em-dash or quote rule. The quoted block has no byte above 0x7F. A plan-stage probe built the target README from the block and ran it against the current test. Only `top`, `contest-table`, `teaser` and the `readme-links` slug self-test went red, and those are the four this story changes. Every other rule passed, and so did `test-boundaries.sh`. No kept rule rejects the owner's text.

**Decided in-stage.**
- (a) `use-cases` is a new rule, because AC2 needs a pinning test.
- (b) The "No key" pin moves inside `key-account`, which took the bullet's only fact.
- (c) `top` refuses the Contest task heading and its header row, which pins "gone".
- (d) The slug self-test supplies its own arrow heading.
- (e) Story 10.2's first criterion ("it starts with 'Try it in two minutes'") is read as its first section and is not amended. Story 10.4 names only the top-of-the-README criterion and its table line; the lead may add a marker at its gate.
- (f) The amendment makes epics.md newer than `epic-10-context.md`. No later Epic 10 story is planned.

## Verification

No live check is planned. If one runs, set `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b`, `OCUTALON_TEST_WEB_PORT=52802` and `OCUTALON_LOCK_OWNER='epic=10 stage=<stage>'`, and use only MCP profile `ocutalon-slot-b` with namespace `OCUTALON`.

Names used below:
- `<scratch>` is the implement stage's own scratchpad subfolder, `e10s4impl/`. Its spawn prompt gives the absolute path. That path is never written into a committed file, because `test-boundaries.sh` refuses local paths.
- `<tree>` is `<scratch>/tree`. Build it once with `git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -xf - -C <tree> && git -C <tree> init -q`, and never commit in it. Each row edits the tree's copy and is reset with `cp` from the worktree; the working tree is never mutated.
- `<baseline>` is the frontmatter `baseline_commit` that the implement stage records.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: 21 PASS lines, `SKIP #telegram`, exit 0.
- (loop) `bash docker/tests/test-readme.sh | sed -n 's/^PASS \([a-z-]*\):.*/\1/p' | tr '\n' ' '` -- expected exactly: `top try-it interesting use-cases teaser outcomes install install-pointer commands key-account lan sign-in-address demo-mode admin-commands after-start-log dev-only public-text no-telegram product-links readme-links must-scan `.
- (loop) Byte check: `awk '/^### Story 10.4:/{on=1} /^## Epic 11:/{on=0} on && /^> /{print substr($0,3)}' _bmad-output/planning-artifacts/epics.md > <scratch>/quoted.txt; n=0; while IFS= read -r l; do n=$((n+1)); [ "$(grep -cxF -- "$l" README.md)" = 1 ] || echo "NOT ONCE: $l"; done < <scratch>/quoted.txt; echo "checked $n"` -- expected: `checked 9` and no `NOT ONCE` line. Also, `grep -cxF 'Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU'` prints 1 for README.md and for `git show <baseline>:README.md`.
- (loop) Amendment: `awk '/^### Story 10.2:/{on=1} /^### Story 10.3:/{on=0} on' _bmad-output/planning-artifacts/epics.md | grep -cF -e '[AMENDED 2026-10-31, owner decision, relayed by the Contest Planner' -e 'table that maps each part of the contest task'` -- expected: 1. Both strings sit on the one marker line, and no live table bullet remains (`grep -c '^- a "Contest task'` in the block prints 0).
- (loop) `uvx --from shellcheck-py==0.9.0.6 shellcheck docker/tests/test-readme.sh` -- expected: no findings.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- (loop) Matrix. Each row is a one-line edit of the scratch tree's README.md, unless another file is named; `bash <tree>/docker/tests/test-readme.sh` must exit 1 with the rule's FAIL:
  - top: "A stray line." under the title; "fifty" changed to "fifteen".
  - try-it: step 4 deleted.
  - interesting: "audit log" changed to "audit trail" in its section.
  - use-cases: Story 30.4's sentence appended to item 2.
  - teaser: moved under `## Try it in two minutes`.
  - outcomes: "Recorded; nobody notified." changed to "Recorded.".
  - install: `2.24` changed to `2.20`.
  - install-pointer: `## Troubleshooting` renamed.
  - commands: `Run docker compose restart to apply it.` appended.
  - key-account: "Tell now, marked as a fallback" changed to "Digest, marked as a fallback".
  - lan: "LAN" removed.
  - sign-in-address: the ready block's `Open:` line changed.
  - demo-mode: the `SetDemoMode(<0 or 1>)` line changed.
  - admin-commands: `-U %SYS` changed to `-U SYS`.
  - after-start-log: the log path changed.
  - dev-only: `The class OcuTalon.Core.X does it.` under the title.
  - public-text: `Approve it from your phone.` appended.
  - no-telegram: `Set up Telegram here.` appended.
  - product-links: `## Set a model key` renamed (the page links `#set-a-model-key`).
  - readme-links: `[x](#nowhere)` appended.
  - must-scan: README.md dropped from the tree's `docker/tests/test-boundaries.sh` must-scan list.
  - No README: the tree's README.md removed; every rule's FAIL says it is missing.
- (once) GNU tools: run the scratch tree's test in the local `ubuntu:24.04` image (`docker run --rm`, the tree mounted read-only, with a `git ls-files` stand-in that prints the tree's file list filtered by the pathspec prefix, as Story 10.2 did) -- expected: the same 21 PASS and the SKIP. If the image is absent, record that and rely on the hosted `checks` job.
- (once) `bash ci/checks.sh` with `timeout: 600000` -- expected: `checks: all scripts passed`.

**Manual checks:**
- `git diff <baseline> -- README.md` removes only the Contest task section (its H2 through the blank line after the teaser) and the "No key" bullet. It adds only the quoted lines, the teaser, `## What you can use it for` and blank lines.
- `git diff --stat <baseline>` names only README.md, `docker/tests/test-readme.sh`, `epics.md` and this spec.

Shared surfaces: README.md's H2 headings and their slugs (read by `top`, `readme-links`, `product-links`, `install-pointer`, `sign-in-address` and `lan`; no page anchor and no `install.sh` pointer names a removed heading); `test-readme.sh`'s `RULES` (no other test reads it; `CHECK_SCRIPTS`' `readme` is unchanged); Story 10.2's block in epics.md (no test reads it). Every test added or changed passes on a fresh environment, in either order: `test-readme.sh` starts nothing and reads only tracked files.

Mutations (Rule 19; the implement stage writes one line per AC, each on the scratch tree, reverted and compared byte for byte):
- AC1: the opening comparison in `chk_top` made always true -> `FAIL top: a broken copy was not flagged`.
- AC2: "never" changed to "rarely" in item 2 -> `FAIL use-cases`.
- AC3: a fixed-rules cell changed -> `FAIL key-account`.
- AC4: none, because it is a recorded check. Confirm `git diff --stat <baseline> -- src web ci` is empty.
- AC5: `use_cases` dropped from `RULES` -> the PASS-name command differs.
- AC6: the marker removed from the tree's epics.md -> the amendment command prints 0.
- AC7: `![badge](x.svg)` appended -> `FAIL teaser`.

### Verification results (implement stage, base `095c523433cac9e1285745aca38b7d8f16efe7c5`)

- (loop) `bash docker/tests/test-readme.sh`: 21 PASS lines, `SKIP #telegram`, `test-readme: all rules passed`, exit 0. The PASS-name command printed exactly `top try-it interesting use-cases teaser outcomes install install-pointer commands key-account lan sign-in-address demo-mode admin-commands after-start-log dev-only public-text no-telegram product-links readme-links must-scan `.
- (loop) Byte check: `checked 9`, no `NOT ONCE` line. The teaser line count is 1 in README.md and 1 in `git show <baseline>:README.md`. README.md and `test-readme.sh` hold no byte above 0x7F.
- (loop) Amendment: the command prints 1 (both strings on the one marker line); `grep -c '^- a "Contest task'` in Story 10.2's block prints 0.
- (loop) shellcheck 0.9.0.6 on `docker/tests/test-readme.sh`: no findings, exit 0. `bash docker/tests/test-boundaries.sh`: `test-boundaries: all rules passed`, exit 0.
- (loop) Matrix on the scratch tree (30 one-line edits, each reset by `cp` from the worktree): every row exits 1 and prints `FAIL <rule>` for its own rule. The rows of the spec's list all hold, plus extra rows: the opening's "fifty" changed, a `## Contest task` heading back, the use-cases heading renamed, a second teaser line, the "No key, still works." bullet back, the "Set a model key" sentence changed, and one cell of the model table changed. Where a row also trips a neighbouring rule, the extra FAIL is a consequence of the edit (the stray line under the title also fails `top`; `x.svg` also fails `readme-links`; the renamed `## Set a model key` also fails `top`, `key-account` and `readme-links`). No README: exit 1, 21 of 21 rules print `FAIL ...: README.md is missing`, `use-cases` included.
- (once) GNU tools: the scratch tree in the local `ubuntu:24.04` image (present; tree mounted read-only, a `git ls-files` stand-in filtering the tree's list by the pathspec prefix): the same 21 PASS lines, `SKIP #telegram`, `test-readme: all rules passed`.
- (once) `bash ci/checks.sh`: `checks: all scripts passed`.
- Manual: `git diff <baseline> -- README.md` removes the Contest task H2, table and teaser line with its blank, and the "No key" bullet; it adds the quoted lines, the teaser line, `## What you can use it for` and blank lines. `git diff --stat <baseline>` names README.md, `test-readme.sh`, `epics.md` and this spec. `git diff --stat <baseline> -- src web ci` is empty (AC4). No committed file holds a local absolute path.
- Design Note 1: every claim was taken as checked at the plan stage; the implement stage found no contradiction and changed no cell, the opening or an item.

Mutations (Rule 19; each on the scratch tree, reverted and compared byte for byte with the worktree):
- mutation: AC1: the `chk_block top` opening comparison in `chk_top` replaced by `true` -> `FAIL top: a broken copy was not flagged` (self-tests 'the opening paragraph removed' and 'the opening and the teaser swapped' not flagged).
- mutation: AC2: "never gives" changed to "rarely gives" in item 2 -> `FAIL use-cases` (`use-cases: missing the line "- **"Only tell me if something needs me."** ...`).
- mutation: AC3: "with no cause and no fix" changed to "with a cause and no fix" in the fixed-rules column -> `FAIL key-account` (`missing the line "| 50 orders fail | ..."`).
- mutation: AC4: none, because it is a recorded check; `git diff --stat <baseline> -- src web ci` is empty.
- mutation: AC5: `use_cases` dropped from `RULES` -> the PASS-name command prints 20 names, without `use-cases`, which differs from the expected list.
- mutation: AC6: the `[AMENDED 2026-10-31, owner decision` line removed from the tree's epics.md -> the amendment command prints 0.
- mutation: AC7: `![badge](x.svg)` appended -> `FAIL teaser` (`an image or embed`).
- mutation: review patches (on the scratch tree, reverted from a backup and compared byte for byte): the `elif` branch of `chk_teaser` deleted -> `FAIL teaser`; the `rows=` count lines of `chk_key_account` deleted -> `FAIL key-account: a broken copy was not flagged`; the opening-once line of `chk_top` deleted -> `FAIL top: a broken copy was not flagged`.

Review-pass re-run (after the three test patches, base `095c523433cac9e1285745aca38b7d8f16efe7c5`): `test-readme.sh` 21 PASS and `SKIP #telegram`, shellcheck clean; (once) `bash ci/checks.sh` -> `checks: all scripts passed`; (once) GNU tools in `ubuntu:24.04` -> the same 21 PASS and `test-readme: all rules passed`.

### QA stage (QA)

No test file is added: every AC has a pinning check that goes red, and the implement stage's mutation lines above all hold (re-run on a fresh scratch tree built from the worktree, each file reset with `cp` and compared with `cmp` afterwards; `git status --short` in the worktree stayed empty).

Pinning check per AC:
- AC1: `test-readme.sh` rule `top` (`chk_top` with `chk_block`, nine self-tests).
- AC2: rule `use-cases`.
- AC3: rule `key-account` (`chk_block` on the model paragraph and table, the `No key, still works.` refusal, the "Set a model key" sentence).
- AC4: no test, by design. The pinning check is the spec's byte check (it prints `checked 9`, and `NOT ONCE` names a drifted line) plus `git diff --stat <baseline> -- src web ci`, which is empty.
- AC5: the PASS-name command (21 names). The script cannot see a rule dropped from `RULES`, so the command is the pin.
- AC6: the amendment command (prints 1 on the real tree).
- AC7: rule `teaser` (embed scan) and `readme-links`; `test-boundaries.sh` refuses a local path; the footprint is `git diff --stat <baseline>`.

QA mutations (Rule 19; one per AC, plus the ones the implement stage wrote):
- mutation: AC1: "fifty" changed to "fifteen" in the opening paragraph -> `FAIL top` (and `FAIL teaser`), exit 1; also a `## Contest task` heading back -> `FAIL top`; also `: top` in place of `chk_block top` in `chk_top` -> `FAIL top: a broken copy was not flagged` (self-tests 'the opening paragraph removed' and 'the opening and the teaser swapped' not flagged).
- mutation: AC2: "never gives" changed to "rarely gives" in item 2 -> `FAIL use-cases`, exit 1.
- mutation: AC3: "with no cause and no fix" changed to "with a cause and no fix" -> `FAIL key-account`, exit 1; also the `- No key, still works.` bullet back -> `FAIL key-account`.
- mutation: AC4: the byte check run on a tree whose opening has "fifty" changed to "fifteen" -> `NOT ONCE: Your integrations already tell you ...` and `checked 9`; on the real tree it prints `checked 9` only. `git diff --stat <baseline> -- src web ci` is empty.
- mutation: AC5: `use_cases` dropped from `RULES` -> the PASS-name command prints 20 names, without `use-cases`, which differs from the expected list (the script itself stays green).
- mutation: AC6: the `[AMENDED 2026-10-31, owner decision` line removed from the tree's epics.md -> the amendment command prints 0 (1 on the real file).
- mutation: AC7: `![badge](x.svg)` appended -> `FAIL teaser` and `FAIL readme-links`, exit 1.
- mutations_demonstrated=7 (one per AC; AC4's red is the byte check, AC5's and AC6's are the spec's commands, which are recorded checks and not part of the CI run).

### Code review stage (review patches G1-G5)

Results after the patches (base `095c523433cac9e1285745aca38b7d8f16efe7c5`):
- `test-readme.sh` on the real tree (bash 3.2, BSD tools): the 21 PASS names of the PASS-name command in order, `SKIP #telegram`, exit 0.
- `rule_top` now has 13 self-tests, and `rule_key_account` has 3 more.
- shellcheck 0.9.0.6: no findings. The file holds no byte above 0x7F.
- (once) GNU tools in `ubuntu:24.04`, with the scratch tree mounted read-only and a `git ls-files` stand-in: 21 PASS and `test-readme: all rules passed`.
- (once) `bash ci/checks.sh`: `checks: all scripts passed`.
- Byte check: `checked 9` and no `NOT ONCE` line. The teaser count is 1 in README.md and 1 at the baseline.

Mutations (Rule 19). Each was applied on a scratch copy of the tree, then reset with `cp` and compared with `cmp`. The worktree's `git status --short` and `git diff --stat` were unchanged afterwards.
- mutation: AC3 (G1): the `prev != ""` line of `chk_key_account`'s new awk check removed -> `FAIL key-account: a broken copy was not flagged` (self-test 'the empty line above the model paragraph removed').
- mutation: AC3 (G1): its `END` tail line removed -> `FAIL key-account: a broken copy was not flagged` (self-tests 'a line without a bar right under the model table' and 'a bullet after the model table').
- mutation: AC3 (G1): on README.md, three edits, one at a time, each -> `FAIL key-account`, exit 1:
  - the empty line above "**With a model, and without one.**" deleted;
  - `Cost | Costs you nothing extra | Free` put right under the last row;
  - a bullet put after the table.
- mutation: AC5 (G3): `use_cases` dropped from `RULES` -> `FAIL rules: rule_use_cases is not in RULES`, exit 1. The same red appears under GNU tools. Before the patch, the script printed 20 PASS lines and exited 0.
- mutation: AC5 (G3): `unlisted "${RULES% *}"` replaced by `unlisted "$RULES"` -> `FAIL rules: a rule left out of RULES is not found`.
- mutation: AC1 (G2): `chk_top`'s stray-line test made `if (0)` -> `FAIL top: a broken copy was not flagged` (self-test 'a line between the teaser and the first H2 section').
- mutation: AC1 (G5): `chk_top`'s first-three-H2 comparison made `if false && ...` -> `FAIL top: a broken copy was not flagged` (self-tests 'the first two sections swapped', 'the use cases section moved down' and 'the use cases section renamed').

## Auto Run Result

Status: done
Blocking condition: none

Summary: the README now opens with the owner's opening paragraph and the teaser line, drops the "Contest task" section, adds "What you can use it for" (two items) and, in "What OcuTalon does", the model paragraph and three-row table in place of the "No key, still works." bullet. `test-readme.sh` pins the new shape (`chk_block`, new `use-cases` rule; `contest-table` removed). Story 10.2's top-of-the-README criterion in epics.md carries the 2026-10-31 amendment.

Files changed:
- `README.md` -- the four edits, pure ASCII, owner text copied by script from epics.md.
- `docker/tests/test-readme.sh` -- `chk_block`, reworked `top`, `teaser`, `key-account`, new `use-cases`, `contest-table` removed, slug self-test supplies its own arrow heading; review patches: model-table line count, opening-once count, two self-tests.
- `_bmad-output/planning-artifacts/epics.md` -- Story 10.2's criterion amended.
- this spec -- Verification results, mutation lines, triage log.

Review: 19 findings from four layers. Patches applied: 4 (1 medium: fourth table row not flagged; 3 low: unused `local n`, opening could appear twice, unexercised blank-line branch of `chk_teaser`). Deferred: 1 (low, unverified: reasons-and-cost wording for fixed-rules decisions in owner text). Rejected: 14 (rows marked reject), each with its reason in the Review Triage Log.

Follow-up review recommended: false (no high patched; one medium patched).

Verification: see "Verification results" above and the review-pass re-run line; all (loop) and (once) commands pass.

Residual risks: the reasons-and-cost wording in the deferred item; wording is pinned, not product behaviour.
