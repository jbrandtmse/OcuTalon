---
title: 'Story 22.12: Document polling a Jira MCP tool as a source'
type: 'feature'
created: '2026-11-14'
status: 'done'
baseline_revision: '2d48d99fcc70975b9e603e7398782537fec2b98f'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-6-document-a-worked-jira-example-and-mcp-governance.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-11-run-source-polls-through-the-governed-proxy.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The worked example `docs/mcp-jira-example.md` (22.6) covers the tools half only. Its source half moved here (ruling M (4)): setting "new tickets assigned to me" as a source poll of a Read-only Jira search tool, the source's entry on the digest's coverage list, and the source half of the release check. 22.6's doc check also forbids any source-poll text (`mcp_doc_problems`, "a line mentions a source poll").

**Approach:** Add a section 4 to the worked example, and one bullet to the security overview's MCP tools section, with only the text of `## Public text`. Every sentence is checked against this branch's code (Design Notes, Claims). Replace 22.6's negative source-poll guard in `overviewdoc` with:
- whole-line pins of the new lines;
- code-derived pins that tie each quoted product string and number to its source in code.

The release check's source half is the Contest Planner's REL-7 hands-on pass, with no script change.

## Boundaries & Constraints

**Always:**
- **Footprint (Lane A, 22.6's docs).** Edit only:
  - `docs/mcp-jira-example.md`;
  - `docs/security-overview.md` (the hand-written `## MCP tools` section only, never a generated region);
  - `docker/tests/test-release-sequence.sh` (the `overviewdoc` rule and its helpers only).
- **Text.** Ship the `## Public text` blocks word for word, and nothing else. Quoted product strings are the code's own, approved or accepted:
  - 21.5's Settings strings and the rail line;
  - 35.1's `mcp.sourceStopped`;
  - the `digest.*` and `checks.allPassed` catalog lines;
  - 22.6's lines, kept as they are.
- **Honesty.** No sentence claims more than the code does:
  - whole-answer de-duplication against the 50 newest hashes, not per ticket;
  - the tool-result cut (DW-1347) stated;
  - the allowance stated as the code computes it;
  - no hard deadline;
  - no changed-tool replay path (ruling F(2)).
- Every 22.6 pin and control stays green, except the `e-poll` control, which this story replaces. The overview's frame stays green.
- Every quoted string and number that has a source in code is checked against that source by `overviewdoc`, so that a code change that makes the doc false turns CI red.

**Never:**
- Edit `README.md`, `GUIDE.md`, `release/**`, `web/**`, `_bmad-output/planning-artifacts/**`, any `.cls`, `docker/tests/test-readme.sh` or any Lane B file. Cross-lane items are proposals only (Design Notes).
- Edit a generated region of the overview, or any line of the overview outside `## MCP tools`.
- Name a real server, URL, account or token. No `://` in the overview.
- Delete, skip or shorten an existing pin or control. The only removal is the `source poll` guard and its `e-poll` control, and pins of the new section replace them.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Committed docs | the tree after this story | `overviewdoc` passes: `ovw_doc_problems` and `mcp_doc_problems` give no lines | none |
| A ruled source line changed | a copy of the example with one word of any line of P1b changed | one line: "the example lacks ruled line N of its classification and governance text word for word", with N that line's number | none |
| Code moves | a temporary tree copy where one source of a quoted fact changes: `mcp.sourceStopped`'s text, a `digest.*` line, `QUEUESECONDS`, `MISSEDSECONDS`, `SEENMAX`, `NAMEMAX`, `ENTRYMAILBOX`, `INTERVAL_CHOICES`, `checkScheduleSource` or a Settings label | one problem line that names the fact (the doc is now false) | none |
| Section gone | a copy without `## 4.` and the lines under it | the ruled-line problem lines for the missing lines | none |
| Overview bullet | the overview's MCP tools section without P2, or with one word changed | "the MCP tools section lacks the source bullet word for word" | none |
| 22.6's pins | the existing controls | each still gives its own line; ruled lines 1-14 keep their numbers | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `web/`, `src/bridge/`, `docs/` or `docker/`. Line numbers are at `662491847`.

**The pins to extend** (`docker/tests/test-release-sequence.sh`):
- Header comment L32-46: the `overviewdoc` line names "no source-poll text" (L42).
- `OVW_MCP_*` constants L2180-2190.
- `ovw_mcp_example_lines` L2192-2213: 14 ruled lines. Existing controls name lines 5, 10, 13 and 14, so new lines are appended as 15 and up.
- `ovw_mcp_shared_problems` L2253-2264.
- `ovw_doc_problems` L2269-2329: the MCP tools section checks are at L2284-2296.
- `mcp_approval_problems` L2335-2345: the precedent for a quoted string checked against the catalog, with a catalog copy argument for controls.
- `mcp_doc_problems` L2351-2382: the guard at L2371 is `grep -qiF -e 'source poll' ... "a line mentions a source poll"`.
- `t_overviewdoc` L2400+: the `e-poll` control is L2508-2509, and the example controls are L2488-2529.
- `ovw_text_problems` (ASCII, machine path) and the `://` and IP check apply to the overview.

**Docs:**
- `docs/mcp-jira-example.md`: L3 is the intro, L42-48 step 3, and L50 is `## How OcuTalon governs MCP tools`, where the new section goes before.
- `docs/security-overview.md` `## MCP tools` L208-225: the last bullet is L223 "- Removing a server cancels its pending approval requests.", and the time-limits paragraph is L225.
- `docker/tests/test-readme.sh` (read only): rule `docs` pins L187 under `## MCP tools` with no heading between (L1736-1739), so a new bullet keeps it green. `admin-mcp` pins GUIDE.md:285 and the example's classification sentence; it is unchanged.

**Claims: the code evidence for each sentence of `## Public text`, at `662491847`.**
1. **Settings form and its fields.**
   - `web/src/app/settings/mcp-view.ts`:
     - L73 "Use as a source", L75 "Source name", L76 "Arguments (JSON)", L77 "Check every", L78 "Only a Read-only tool can be a source.", L79 "Your sources";
     - L83 the accessible name "Use {tool} on {server} as a source";
     - L88 `INTERVAL_CHOICES` [5, 15, 30, 60, 360, 1440], with words from `web/src/app/rail/rail-view.ts` L173-182 and L61-64: "5 minutes", "15 minutes", "30 minutes", "1 hour", "6 hours", "1 day";
     - L89 `DEFAULT_INTERVAL` 15;
     - L186-188 `canBeSource`: Read-only and not refused.
   - `web/src/app/settings/mcp-section.ts`:
     - L236-252: the Source button on each Read-only row; any other row shows the reason;
     - L262-326: the form under the heading "Use as a source", and Save is `SETTINGS_TEXTS.save` "Save changes" (L321, L526; `settings-view.ts` L49);
     - L333-361: "Your sources", where each row has **Remove** (L65: it acts at once).
2. **The server's rules** (`Mcp/Ops.cls` `OnSetSource` L199-232):
   - Read-only only (L212, and again under the lock at L449);
   - a name of 1 to 100 characters (L214, `NAMEMAX` L104, `MESSAGESOURCENAME` L83);
   - "Mailbox", in any letter case, refused (L215, `Checks/Coverage.cls` `ENTRYMAILBOX` L79, `MESSAGESOURCERESERVED` L85);
   - arguments a JSON object, refused when they hold `secret://` or `@{` (L217, `Normalised` L534-549);
   - an interval of 5 to 1,440 minutes (L219, L99-101). The page offers only the six choices.
   - Removing a server removes its sources (class doc L12).
   - Every verb is refused on the online demo (`Refusal` L860-863). `Checks.RunSources` runs nothing there (`Checks/Process.cls` L1042, L1063-1066).
3. **Saving and changing.** `Watch/Ops.cls` `SetSource` L239-276:
   - the natural key is (session, `source`, name), so saving the same name updates the row (class doc L24-28, L247-250);
   - every save makes the row due now (L266);
   - another server, tool or arguments moves `CreatedAt` (L251, `REPOINTRESETS` L46);
   - an interval-only change keeps it.
4. **The rail row.** `web/src/app/rail/rail-view.ts`:
   - L33: the heading "Background checks";
   - L60 and L288-289: "Polled every {duration}";
   - L269-277: "Last run {when}" with the finding or the result word;
   - L291: the trace link, with `Live/Payload/Check.cls` L62-64 and `Web/Api.cls` L136 (traceUrl).
5. **The schedule.**
   - The heartbeat Tick runs every minute: `Install/Step/Schedule.cls` L2, L51.
   - A row is due when its `NextDueAt` falls within 5 s of the Tick (`Checks/Process.cls` `DUESLACKSECONDS` L109). At the send, `NextDueAt` becomes the tick time plus the interval (L1096-1099).
6. **The governed call** (`src/bridge/cls/OcuTalon/Bridge/Poll.cls` L3-17):
   - one `call_mcp_tool` on a proxy-only manager, under the gate (untrusted rule) and the step audit, with no model and no grant;
   - the step label "Running {tool} on {server}" (`Bridge/Policy/Gate.cls` `MCPLABEL` L150), emitted by `Bridge/Process/Decide.cls` L414-415 and L432 (`EmitSteps`);
   - the `MCP` audit entry for a call that reached the server (`Mcp/Proxy.cls` L55, L217-231).
7. **Baseline and de-duplication** (`Checks/Process.cls` `RecordSource` L1253-1283):
   - the first passed run since `CreatedAt` sets `baseline` and sends nothing (L1263-1265; `StateOf` L1132-1147 starts afresh when `LastRunAt` is before `CreatedAt`);
   - a later answer whose SHA-256 is not in `seen` sends one Item (L1266-1268), and the newest 50 are kept (`SEENMAX` L1020, `Newest` L1300-1309);
   - an empty answer sends nothing (L1262).
8. **The Item** (`SourceItem` L1323-1333): channel `system`, Provenance `untrusted`, Subject the source's name, Text the whole answer, sent to `Intake` (`SendFinding` L871-875, `Record` L638-644, `SendOwn` L411). Intake makes its attention decision: 22.11 `TestNewResultReachesIntake`.
9. **The cut.** The proxy hashes the whole answer before the cut (`Mcp/Proxy.cls` `Noted`, `answerHash`), `Checks` compares that hash, and the Item holds the answer as cut (`Checks/Process.cls` `SourceItem`) [AMENDED 2026-11-15, DW-1347 option (a), Contest Planner ~09:10Z Nov 15; true once DW-1347 (lane C) is on feature; it read "`Tools/McpCall.cls` L4 and L44 pass the tool-result room (`Tools/Result.cls` `Room` L68-71) to `Proxy.Call`, so a poll's answer is cut like any tool result. A change past the cut that keeps the length is missed: DW-1347, escalated, a low DW ..."].
10. **One poll at a time, install-wide.** `RunSources` L1037-1060, `PollInFlight` L1068-1087 (`INFLIGHTSECONDS` L1026), `PollSource` L1092-1095: a due source waits for a later Tick while a poll is in flight. A stopped source records at once.
11. **The stop:**
    - `PollSource` L1094 and L1102-1104 (classification not `read-only`: no call);
    - `SourceAnswer` L1237 (`notreadonly` and `changed` are stopped);
    - `RecordSource` L1282 (one notice per transition);
    - `Mcp/Ops.cls` `SourceStopped` L37-38 and L790 (every admin session);
    - `Msg/Catalog/Watch.cls` L1078-1079: the text of `mcp.sourceStopped`.
    A run that is not a stop clears it (L1261, L1277), so the next due run after the tool is Read-only again polls.
12. **The coverage entry** (`Checks/Coverage.cls`):
    - the source's row is named by its `DisplayName` (L5, `EntryOf` L469-473; `Digest/Process.cls` L33-34: as the admin typed it);
    - only runs since `CreatedAt` count (L309, L19-24);
    - the allowance is interval x 60 + max(`MISSEDSECONDS` 180, `QUEUESECONDS` 120 x the non-stopped sources) (L20-31, L58, L62, `SourceSlack` L519-525, `PollingSources` L528-549, `Current` L508-516);
    - the reasons (`ReasonOf` L613-617, `KeyOf` L620-623; `Checks/Process.cls` L1237, L1278).
13. **The digest lines** (`Msg/Catalog/Watch.cls`):
    - L489-490 "Passed: {entry} (at {time}).";
    - L506-507 "unreachable since {time}";
    - L522-523 "the check timed out at {time}";
    - L514-515 "the check stopped with an error at {time}";
    - L563-564 "stopped polling at {time}: its tool is no longer Read-only";
    - L530-531 "the check didn't run between {from} and {to}";
    - L548-549 "its last check was at {time}, too long ago to count".
    A time slot renders as hh:mm for the same day (`Msg/Catalog.cls` L168-174, `Data.Time.ForMessage`).
14. **The digest's order and all-clear:**
    - `Checks/Render.cls` L11: rows ordered failed, then not_checked, then passed;
    - L12-13: `checks.allPassed` "Everything I checked passed." (`Msg/Catalog/Watch.cls` L77-78) only when every row passed;
    - `Digest/Process.cls` L33-37;
    - `web/src/app/chat/chat-view.ts` L275-279: "What I checked" opens when any row did not pass.
15. **Untrusted results and the overview bullet:**
    - AD-30; `Checks/Process.cls` L1329;
    - the overview's "Results are untrusted content." (L222);
    - the gate's untrusted rule (`Bridge/Poll.cls` L11-12).

## Tasks & Acceptance

**Execution:**
- [ ] `docs/mcp-jira-example.md`:
  - L3 becomes P1a;
  - insert P1b between L48 and L49 (the empty line before `## How OcuTalon governs MCP tools`), with one empty line around each block;
  - nothing else changes.
- [ ] `docs/security-overview.md` -- insert P2 as a new bullet right after L223 ("- Removing a server cancels its pending approval requests."), inside `## MCP tools`.
- [ ] `docker/tests/test-release-sequence.sh` (`overviewdoc` only):
  1. **`ovw_mcp_example_lines`.** Append every non-empty line of P1b, in order, as ruled lines 15 and up: headings, paragraphs, list items, the table's header, separator and rows. Then append P1a. The comment above it names the source section (Story 22.12).
  2. **`mcp_doc_problems`.** Remove the `source poll` guard (L2371) and update the function's doc comment. Call a new `mcp_source_problems "$f" "${3:-$root}"`. `mcp_doc_problems` gains an optional third argument, the root to read the code from, which is `$root` by default.
  3. **New `mcp_source_problems <file> <code root>`.** It gives one problem line per fact that the example does not hold as the code states it. Read each fact from its file under the code root, as `mcp_approval_problems` does (sed or awk on the class or TS source, no IRIS):
     - (a) `mcp.sourceStopped`'s text (`Msg/Catalog/Watch.cls`), with {source} Jira tickets, {time} 09:15, {tool} search_issues and {server} Jira, is in the example exactly once, in double quotes.
     - (b) Each of `digest.passed` {entry Jira tickets, time 09:15}, `digest.notCheckedUnreachable`, `digest.notCheckedTimeout`, `digest.notCheckedError` and `digest.notCheckedStopped` {time 09:15}, `digest.notCheckedMissed` {from 09:00, to 09:30} and `digest.notCheckedStale` {time 08:30}, filled, is in the example. So is `checks.allPassed`'s text.
     - (c) `QUEUESECONDS`/60 and `MISSEDSECONDS`/60 (`Checks/Coverage.cls`) give "plus 3 minutes, or plus 2 minutes for each source", and `SEENMAX` (`Checks/Process.cls`) gives "the 50 newest". `NAMEMAX` (`Mcp/Ops.cls`) gives "1 to 100 characters", and `ENTRYMAILBOX` gives "Mailbox".
     - (d) The six `INTERVAL_CHOICES` numbers (`web/src/app/settings/mcp-view.ts`), as the rail's `intervalText` words, joined as "5 minutes, 15 minutes, 30 minutes, 1 hour, 6 hours and 1 day" (the numbers are read; the word rule is the doc's own, so a changed number is caught). `checkScheduleSource` (`rail-view.ts`) with 15 minutes gives "Polled every 15 minutes".
     - (e) The labels `sourceHeading`, `sourceName`, `sourceArguments`, `sourceInterval`, `sources` and `SETTINGS_TEXTS.save` are each in the example in bold (`**...**`), and each literal is in its TS file.
     Each problem line names its fact, for example "the example's stop notice is not the catalog's mcp.sourceStopped" or "the example's allowance is not the code's (QUEUESECONDS, MISSEDSECONDS)".
  4. **`ovw_doc_problems`.** A new constant `OVW_MCP_SOURCE` holds P2 without its "- ". `ovw_mcp_shared_problems`' pattern is the model: the MCP tools section must hold "- $OVW_MCP_SOURCE" as a whole line, else "the MCP tools section lacks the source bullet word for word".
  5. **`t_overviewdoc`.**
     - Replace the `e-poll` control with "control: the source section removed from the example": a copy with P1b deleted gives the ruled-line problem lines of its lines.
     - Add a loop control: for each ruled line from 15 to the last, a copy with " x" appended to that line (its first occurrence) gives exactly "the example lacks ruled line N ...".
     - Add one control per `mcp_source_problems` fact (a)-(e). Each builds a temporary code root (a copy of only the files read, under `$d/code`) with that one fact changed, for example `QUEUESECONDS = 60` or a word of `mcp.sourceStopped`, and asserts its one problem line.
     - Add one control for P2: one word changed.
     - The committed files still give "".
  6. **The header comment** L32-46: "no source-poll text" becomes the source section's ruled lines and the code-derived facts (Story 22.12), plus the overview's source bullet.
- [ ] **Planner ~07:30Z Nov 15 gate rulings (binding):**
  - P1b's sentence "The poll itself asks no model; only a new item's attention decision does." is pinned (it is one of P1b's ruled lines; add it to the loop control like the others, and confirm a one-word change turns `overviewdoc` red).
  - Every coverage number in P1b ("plus 3 minutes", "plus 2 minutes for each source", "the 50 newest", "1 to 100 characters", the six interval choices) is pinned to the CODE's constants (`Checks/Coverage.cls` `MISSEDSECONDS` and `QUEUESECONDS`, `Checks/Process.cls` `SEENMAX`, `Mcp/Ops.cls` `NAMEMAX`, `web/src/app/settings/mcp-view.ts` `INTERVAL_CHOICES`), read from the files by `mcp_source_problems`, never as literals copied into the test; each has a control that changes the constant in a code-root copy and turns the check red.
  - `docs/security-overview.md`: after inserting P2 in the hand-written `## MCP tools` section, regenerate the file (`bash docker/tests/test-security-overview.sh --write` on lane D's throwaway, then `bash docker/tests/test-security-overview.sh` compare) and keep `test-security-overview.sh` green; the generated regions must not change.
  - `_bmad-output/planning-artifacts/epics.md` Step 4 release check (the "**Step 4:** Story 22.6: ..." bullet near L1009): move "new tickets assigned to the user become items with decisions in Visual Trace" from Story 22.6's sentence to a new Story 22.12 sentence that also says the source shows on the digest's coverage list, with an `[AMENDED 2026-11-15, Story 22.12, Contest Planner gate ruling ~07:30Z Nov 15 (cross-lane item 2)]` marker and the old text. In 22.12's one commit.
  - Do NOT edit `GUIDE.md` (lane B adds T7 as a follow-up). DW-1347 (lane C) changes P1b's cut sentence in its own commit; if it has landed when you integrate, take its wording.
- [ ] This spec -- the `## Verification` mutation lines (implement stage).

**Acceptance Criteria:**
- Given the committed `docs/mcp-jira-example.md`, when `overviewdoc` runs, then it sets "new tickets assigned to me" up as a source of the Read-only `search_issues` tool (P1b, word for word). It shows the source's coverage entry, checked and not checked with each reason. Every quoted product string and number equals its source in code. 22.6's ruled lines 1-14 and checks still pass. Mutations:
  - any P1b or P1a line changed -> its ruled-line line (the loop control, one per line);
  - in a code-root copy, `QUEUESECONDS` 120 -> 60 -> the allowance line;
  - a word of `mcp.sourceStopped` -> the stop-notice line;
  - `SEENMAX` 50 -> 40 -> the hash-count line;
  - an `INTERVAL_CHOICES` number -> the choices line;
  - `digest.notCheckedStopped` text -> the digest-line line.
- Given the committed `docs/security-overview.md`, when `overviewdoc` runs, then its MCP tools section holds P2 as a whole bullet and every 22.6 check passes. `test-readme.sh` rule `docs` (L187 under `## MCP tools`, no heading between) passes. Mutation: one word of P2 -> "the MCP tools section lacks the source bullet word for word".
- Given 22.6's controls, when `t_overviewdoc` runs, then each gives its own line as before, except `e-poll`, which this story replaced. Mutation: restore the `source poll` guard -> "the committed worked example is good" red ("a line mentions a source poll" is not expected).
- Given the whole tree, when `bash ci/checks.sh` runs, then every check script passes, `test-readme.sh` (`readme-anchors`, `admin-mcp`, `docs`) included.

**Release check** (the source half, moved from 22.6 by ruling M (4)): the Contest Planner's REL-7 hands-on pass, on the first daily release candidate that ships 22.11 and 22.12. It follows section 4 on a clean local install with a real Jira MCP server. New tickets assigned to the user become items with decisions in Visual Trace, and the source shows on the digest's coverage list, checked, or not checked with its reason. No script runs it: `test-release-sequence.sh` pins the text only (`overviewdoc`). For the lead, see Design Notes "Cross-lane and planning items" (2).

## Spec Change Log

- 2026-11-15 (lead, after implement). **DW-1347 option (a), Contest Planner ~09:10Z Nov 15 (BINDING)**, from `<coordination>/prompts/epic-22-rulings-20261113-1715.md` "22.12 and DW-1347": P1b's answer-cut sentence is replaced, verbatim, with "- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item. Even a long answer is compared whole, so a change anywhere in it makes a new item, but a long answer is cut in the item, as any tool's result is. Keep the answer short, for example with `maxResults`, so that the item holds all of it.", in the doc and in its `ovw_mcp_example_lines` pin in one commit; Code Map claim 9 takes DW-1347's spec wording (706466a80). The line is true of the code once DW-1347's fix (lane C) is on feature: 22.12 merges after DW-1347.

- 2026-11-15 (lead). **Gate ruled, Contest Planner ~07:30Z Nov 15 (relayed by the orchestrator; BINDING):** IMPLEMENT. P1a APPROVED verbatim. P1b APPROVED verbatim with ONE fix: "A poll asks no model." becomes "The poll itself asks no model; only a new item's attention decision does.", pinned; the coverage numbers are pinned to the code's constants, not to literals copied into the test. P2 APPROVED verbatim; regenerate `docs/security-overview.md` and keep `test-security-overview.sh` green. VETO: removing 22.6's "no source polls in the worked example" guard APPROVED. Release-check half: `test-release-sequence.sh` gets text pins only. Cross-lane: (1) GUIDE.md T7 is lane B's follow-up, lane D does not edit GUIDE.md; (2) the epics.md Step 4 release-check pointer fix (22.6 → 22.12) goes in 22.12's commit; (3) DW-1347 (lane C) changes P1b's cut sentence and its pin in its own commit; if it lands first, 22.12 takes its wording at integrate. Applied: P1b's sentence replaced in `## Public text`; the rulings task added under Execution.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 25 findings - high 0, medium 4, low 16, false 5, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the test holds the section three times (heredoc, mcp_source_problems, OVW_MCP_SOURCE) - the spec's Task 3 and 5 require both whole-line pins and code-derived pins; they check different things (wording versus code).
  - `[medium]` `[patch]` Blind: the step label, the Remove button, the Background checks heading, the What I checked list and the "every minute" cadence are not tied to code - verified: only the doc's own lines pinned them. Patched with code-derived pins and controls (see Verification).
  - `[false]` `[reject]` Blind: the name and arguments rules are described incompletely - the approved P1b claims nothing untrue; the omitted refusals are extra limits, not contradicted claims.
  - `[low]` `[reject]` Blind: the overview bullet lacks the data consequences - approved P2, word for word; a change edits public text (Planner-ruled).
  - `[low]` `[reject]` Blind: no step to confirm polling works - approved P1b text; adding it edits public text.
  - `[low]` `[reject]` Blind: mcp_catalog_text keeps escapes - no catalog text has an escape today, and one that gains one turns the check red, never silently green.
  - `[low]` `[reject]` Blind: digest lines are matched anywhere in the section - the ruled-line pins tie each line to its row; the code-derived pin ties its text to the catalog.
  - `[low]` `[reject]` Blind: mcp_doc_problems mixes path bases - pre-existing (the expiry check reads src relative to the working directory); the third argument is the spec's, and its header says so.
  - `[low]` `[patch]` Edge: the stop-notice "exactly once" counts lines - patched to count occurrences (grep -o), with a control that quotes the notice twice.
  - `[medium]` `[patch]` Edge: Remove is not pinned to code - same root cause as the second Blind row; patched (removeButton joins the labels).
  - `[low]` `[reject]` Edge: ruled lines match anywhere, order and section not pinned - 22.6's mechanism, as the spec's Task 1 requires; a moved line is harmless.
  - `[false]` `[reject]` Edge: the allowance would demand "1 minutes" if a constant became 60 s - theoretical; the approved text and its ruled line would also need a change then, and the check turns red, not green.
  - `[low]` `[reject]` Edge: the demo-sentence control now gives two lines - forced by the spec (P1a is a ruled line); both assertions hold, so the 22.6 coverage is kept.
  - `[low]` `[reject]` Edge: only mcp_source_problems honours the third argument - the spec says "the root to read the code from" for the new facts; the expiry and approval reads are 22.6's and unchanged.
  - `[medium]` `[patch]` Gap: four quoted strings and the cadence pinned only to the doc - same root cause as the second Blind row; patched.
  - `[low]` `[patch]` Gap: no control for the count-of-one branch - patched with the quoted-twice control.
  - `[low]` `[patch]` Gap: the section-removed facts control compares two outputs that may both be empty - patched with two fixed assertions (the stop notice line is present, more than 20 fact lines).
  - `[low]` `[patch]` Gap: mutation lines missing for controls - written (Verification, review-pass lines).
  - `[low]` `[reject]` Gap (other finding): the e-demo control split - same as the Edge row on it.
  - `[low]` `[reject]` Intent: the allowance's formula (SourceSlack) is not pinned, only its constants - the spec's Task 3(c) pins the constants; the formula is not readable by sed; reopen_if a change of SourceSlack's rule is not caught by a Test.Checks test.
  - `[medium]` `[patch]` Intent: R3, facts with a code source but no pin - same root cause as the second Blind row; patched.
  - `[low]` `[reject]` Intent: digest lines matched by substring - same as the Blind row on it.
  - `[low]` `[reject]` Intent: the e-demo control is adapted - same as the Edge row on it.
  - `[false]` `[reject]` Intent: the spec file is edited - the Verification section is a tracking section the spec itself asks the implement stage to fill.
  - `[false]` `[reject]` Intent: no automated surface for the release check's source half - by design (ruling M (4): the REL-7 hands-on pass, text pins only).

## Design Notes

**Governing ADs (Rule 6):**
- AD-10: one gate, and the untrusted rule for a poll.
- AD-17: the `MCP` audit entry.
- AD-18: the source row, the run, coverage and the allowance (DW-1346).
- AD-21: MCP calls and S11; no hard deadline.
- AD-22: the doc checks are hermetic and static.
- AD-25: off on the online demo.
- AD-28: the all-clear only from `Render`.
- AD-29: lanes, and 22.6's docs paths.
- AD-30: untrusted Items to `Intake`.
- AD-32: the notices and lines are catalog keys, quoted from the catalog.

No AC contradicts an AD. No NFR trips Rule 5.

**Integration ACs (Rule 1):** no service or shared module. The docs are read by people. The REL-7 pass consumes section 4, and GUIDE.md:285's link (36.3) points at the file. No new consumer code in this story.

**Consumes:**
- 22.6: the example, its ruled lines and `mcp_doc_problems`;
- 22.5 and 22.13: the row, the coverage and the repoint;
- 22.11: the poll run, the baseline, de-duplication, the stop, one poll at a time and QUEUESECONDS 120;
- 21.5: the form, "Your sources" and "Polled every {duration}";
- 35.1: `mcp.sourceStopped`.

**Consumed-by:** 36.3 (GUIDE.md links the file; no change needed), and the step 4 REL-7 pass.

**Extend, don't copy (Rule 2):**
- the new lines extend `ovw_mcp_example_lines`, numbered after line 14;
- `mcp_source_problems` follows `mcp_approval_problems`' catalog-reading form and its copy-argument controls;
- `OVW_MCP_SOURCE` follows `OVW_MCP_AUDIT` and `OVW_MCP_DATA`.

**Decided in-stage:**
1. **Code-derived pins.** "True of the code at merge" is pinned, not only reviewed: each quoted string and number is read from its source in code (Tasks 3). A later code change that makes the doc false turns `ci/checks.sh` red. Static and hermetic: no IRIS.
2. **The six choices, not 5-1,440.** The page offers six intervals (`INTERVAL_CHOICES`). The server's 5 to 1,440 range is reachable only by the API, so the doc names the six choices.
3. **The cut sentence (DW-1347).** Closed: replaced by the Planner-approved line (option (a), ~09:10Z Nov 15) in this story's commit. [It read: "It stays while DW-1347 is open."] Whoever fixes DW-1347 (lane C, a low DW) changes this sentence and its pin in the same commit (Cross-lane items).
4. **One overview bullet (P2).** The overview's MCP rules list every governed MCP path for the security reviewer, and polls are a new one. The epic's "never yields an all-clear" promise is stated there plainly. One bullet; the rest is already true.
5. **Source name "Jira tickets".** The AC's "new tickets assigned to me" names the poll, not the label. A short name reads better in the digest's sentences. The heading and the arguments say "new tickets assigned to you".
6. **No IRIS in Verification.** No class changes, and the overview's hand edit is not drift (`overviewdrift`: "a hand-written change: nothing is printed", L2169-2170). So no `ci/iris.sh` call is needed. If one is needed anyway, use the lane D values below.

**Cross-lane and planning items (proposals; not edited here):**
1. **GUIDE.md T7 "MCP tools as sources"** (21.5's ruled bullet; Lane B / Story 36.3). Both of its conditions now hold on this branch:
   - (a) a test proves a saved source on the coverage list (22.11 `TestStoppedCoverage`; `Test.Digest.Coverage`'s source tests);
   - (b) a whole answer seen before is skipped (`Checks/Process.cls` L1266), so "each new result" stays.

   T7 can ship as ruled once 22.11 merges. Optionally, GUIDE.md:285's "shows how to add a server and classify its tools" could add "and set one up as a source". It is still true without it.
2. **`epics.md` Step 4 release check** (Epic List L1013, for the lead as a Rule 5 apply-and-report pointer correction after the approved split). Change "Story 22.6: ... a risky call waits for approval, and new tickets assigned to the user become items with decisions in Visual Trace." to "Story 22.6: ... a risky call waits for approval. Story 22.12: following its source section, new tickets assigned to the user become items with decisions in Visual Trace, and the source shows on the digest's coverage list."
3. **DW-1347** (lane C): its fix must update P1b's cut sentence and its pin in the same commit.
4. **README.md:** none. **More to try:** none (sources are off on the demo).

**Ledger inbox (Rule 17):** `LEDGER slice 22-12-document-polling-a-jira-mcp-tool-as-a-source` is empty (checked at `662491847`). Story 22.12's block in `epics.md` carries no DW bullet.

**Context note:** `epic-22-context.md` (committed at `5fafee78`) predates `epics.md` and the spine changes of 22.11, 22.14 and 36.3, so the planning artifacts are newer than it. The changes that matter here were read directly: the spine's AD-18 Part B and the QUEUESECONDS 120 ruling, 36.3's GUIDE retarget and the 22.14 block. The cache was not recompiled, as the stage instructs. The lead may re-run the pre-warm before the next plan.

## Veto items

1. **NEW public text P1a, P1b and P2** (veto window 5: claims about what the product does).
   - Online demo: none of it ships on the demo page. P1a keeps the demo-off sentence, and P1b says sources are off there.
2. **The removal of 22.6's negative `source poll` guard** (window 4, a guarantee written into 22.6's AC 1, "it never mentions source polls"). It was ruled to last only until this story (M (4) split). The new whole-line and code-derived pins replace it.
   - Online demo: n/a.

No new route, privilege, grant, table, column, retention, dependency or code change.

## Public text

All of it is NEW for the Planner (PLANNER REPORT). The strings in double quotes inside it are existing approved or accepted product text, quoted (Code Map, Claims).

**P1a, `docs/mcp-jira-example.md` L3 (replaces it; NEW wording, from 22.6's approved line):**

```markdown
This example adds a Jira MCP server to OcuTalon on your own install, classifies its tools, runs a search, approves a change and sets up a source that polls for new tickets. Then it explains how OcuTalon governs MCP tools. MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none.
```

**P1b, `docs/mcp-jira-example.md`, a new section after step 3 (NEW):**

````markdown
## 4. Poll new tickets assigned to you as a source

A Read-only tool can also be a source: OcuTalon calls it on a schedule, makes an attention decision on each new result, and lists the source on your digest's coverage list. Only a Read-only tool can be a source, and sources are off on the online demo.

In the Tools table, press **Use as a source** on the `search_issues` row, fill in the fields under **Use as a source**, then press **Save changes**:

- **Source name**: `Jira tickets`. A source's name is 1 to 100 characters, and it can't be "Mailbox" in any letter case: that is the name your digest gives the connected mailbox.
- **Arguments (JSON)**: the arguments of your server's search tool, as a JSON object. For the newest tickets assigned to you, for example: `{"jql": "assignee = currentUser() ORDER BY created DESC", "maxResults": 5}`. The arguments go to the server with every call, so put no secret in them; OcuTalon refuses a `secret://` reference there.
- **Check every**: 15 minutes. The choices are 5 minutes, 15 minutes, 30 minutes, 1 hour, 6 hours and 1 day.

The source then shows under **Your sources**, and under Background checks its row reads "Polled every 15 minutes", with its last run, its result and a link to its trace. To change the source, save it again with the same name. **Remove** removes it, and removing the server removes its sources too.

Each poll is one call of `call_mcp_tool`, through the same gate as a call from the chat, with the same audit entry, and shows as the step "Running search_issues on Jira" in Visual Trace. The poll itself asks no model; only a new item's attention decision does. OcuTalon polls the source at its next background check, which comes every minute, and then every 15 minutes:

- The first poll that gets an answer sets a baseline: OcuTalon keeps a hash of the answer and sends nothing.
- A later answer that differs from each of the 50 newest different answers becomes one item, with the whole answer as its text, and OcuTalon makes an attention decision on it. The item and its decision show in Visual Trace. An answer that matches one of them, or an empty answer, sends nothing.
- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item. Even a long answer is compared whole, so a change anywhere in it makes a new item, but a long answer is cut in the item, as any tool's result is. Keep the answer short, for example with `maxResults`, so that the item holds all of it.
- Each item is untrusted content, as every result of an MCP tool is.
- Saving the source with another tool or other arguments starts it over, with a new baseline. Changing only how often it is checked keeps its hashes.
- OcuTalon runs one source's poll at a time for the whole install, so when several sources are due together, the others wait for a later minute.
- If the tool is classified Risky or Unclassified, or its description or inputs change, the source stops polling at its next due time: OcuTalon makes no call, and every admin gets this notice once: "The source Jira tickets stopped polling at 09:15, because its tool search_issues on Jira is no longer Read-only. Your digest lists it as not checked." Once you classify the tool Read-only again, the source polls again at its next due time.

### The source on your digest

Your digest's coverage list names the source as you typed it: "Passed: Jira tickets (at 09:15)." Only the polls since you set the source up, or last gave it another tool or other arguments, count. The source counts as checked only when its latest poll passed and it kept to its schedule: the time between two of its polls, and from its last poll to the digest, may be at most its interval plus 3 minutes, or plus 2 minutes for each source on this install that isn't stopped, when that is longer. Otherwise the source is not checked, and the digest gives the reason, for example:

| What happened | The digest's line |
| --- | --- |
| OcuTalon couldn't reach the server | Not checked: Jira tickets (unreachable since 09:15). |
| The server didn't answer in time | Not checked: Jira tickets (the check timed out at 09:15). |
| The call failed for another reason | Not checked: Jira tickets (the check stopped with an error at 09:15). |
| The tool is no longer Read-only | Not checked: Jira tickets (stopped polling at 09:15: its tool is no longer Read-only). |
| A poll came too late | Not checked: Jira tickets (the check didn't run between 09:00 and 09:30). |
| The last poll is too old | Not checked: Jira tickets (its last check was at 08:30, too long ago to count). |

A source that isn't checked is named before every entry that passed, the page opens its "What I checked" list, and the digest never says "Everything I checked passed."
````

Evidence for P1a and P1b: Code Map, Claims 1-14, sentence by sentence in the order above:
- intro: Claims 1, 2, 7, 8 and 12;
- form: 1 and 2;
- rail and changes: 3 and 4;
- the call: 6;
- the schedule: 5;
- baseline and de-duplication: 7 and 8;
- whole answers and the cut: 7 and 9;
- untrusted: 15;
- the repoint: 3;
- one at a time: 10;
- the stop: 11;
- coverage: 12, 13 and 14.

The times are examples, rendered as the catalog renders a same-day time.

**P2, `docs/security-overview.md` `## MCP tools`, a new bullet after "Removing a server cancels its pending approval requests." (NEW):**

```markdown
- An admin can make a Read-only tool a source, which OcuTalon calls on a schedule through the same gate, audit entry and agent step. Its new results reach OcuTalon's attention decisions only as untrusted items. A source whose tool is no longer Read-only makes no call, and a source that wasn't checked never counts as passed in the digest.
```

Evidence: Claims 2 (admins only, Read-only only), 6 (gate, audit, step), 8 and 15 (untrusted items), 11 (no call when stopped), 12 and 14 (not checked is never passed). It has no `://` and no "deadline".

**Reused, unchanged (existing):**
- 21.5's "Use as a source", "Source name", "Arguments (JSON)", "Check every", "Your sources", "Polled every {duration}" and the interval words; `SETTINGS_TEXTS.save` "Save changes"; "Remove".
- 35.1's `mcp.sourceStopped`.
- The `digest.*` lines and `checks.allPassed`.
- 22.6's "Running {tool} on {server}", the Tools table, and every ruled line 1-14.

## Verification

No IRIS stack is needed (Decided in-stage 6). If any call does need one: run it with the lane D values `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`, with run tag `e22s12i` (fresh) or `e22s12iw` (warm), and `ci/iris.sh teardown` / `ci/warm.sh down` at the end. Use one call per class with `timeout: 600000`. Never two `iris_execute_tests` calls in one message, and pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call.

Each command below runs in one foreground call of about 150 s or less.

**Commands:**
- (loop) `bash docker/tests/test-release-sequence.sh overviewdoc` -- expected: exit 0, `PASS overviewdoc`
- (once) `bash docker/tests/test-release-sequence.sh overviewdoc overview overviewdrift static` -- expected: exit 0 (named subsets; the whole script is about 170 s)
- (once) `bash docker/tests/test-readme.sh docs admin-mcp readme-anchors` -- expected: exit 0
- (once) `bash ci/checks.sh` -- expected: every block PASS (about 20-40 s)
- (once) `git diff --stat` -- expected: only the three footprint files and this spec

**Mutation lines (Rule 19; implement stage).** Apply each mutation, observe the red, revert byte for byte, and confirm that `git status --short` and `git diff --stat` are unchanged. Write `mutation: <what> -> <which check went red>` here:
- the loop control's evidence: one line per P1b and P1a line (ruled lines 15 and up), each red with its own number;
- `QUEUESECONDS` 60, `MISSEDSECONDS` 120, `SEENMAX` 40, `NAMEMAX` 99 and `ENTRYMAILBOX` "Inbox", each in a code-root copy;
- one word of `mcp.sourceStopped`, of `digest.notCheckedStopped` and of `checks.allPassed`;
- `INTERVAL_CHOICES` 15 -> 20;
- `checkScheduleSource` "Polled every" -> "Checked every";
- `sourceName` 'Source name' -> 'Name';
- one word of P2 in the overview;
- the `source poll` guard restored.

**Mutation results (implement stage).** Each was made in a copy (a symlink tree of the repository under scratch, with only the mutated file and the script as real copies), never in a tracked file, so there was nothing to revert; `git status --short` and `git diff --stat` were checked after the last one. `overviewdoc` printed its "the committed worked example is good" (or "the committed overview has a good frame") line with the one problem, then `FAIL overviewdoc`:
- mutation: ruled lines 15 to 41 of the example (every P1b line, then P1a as the last), each with " x" appended -> `mcp_doc_problems` gave exactly "the example lacks ruled line N of its classification and governance text word for word" for each N (the loop control of `t_overviewdoc`, run once more as a standalone loop over the committed example: 27 lines, 27 own-number lines, and no line for the unchanged file); line 22 holds "The poll itself asks no model; only a new item's attention decision does."
- mutation: `QUEUESECONDS` 120 -> 60 in a code-root copy -> `overviewdoc` red, "the example's allowance is not the code's (QUEUESECONDS, MISSEDSECONDS)"
- mutation: `MISSEDSECONDS` 180 -> 120 -> `overviewdoc` red, "the example's allowance is not the code's (QUEUESECONDS, MISSEDSECONDS)"
- mutation: `SEENMAX` 50 -> 40 -> `overviewdoc` red, "the example's count of kept hashes is not the code's (SEENMAX)"
- mutation: `NAMEMAX` 100 -> 99 -> `overviewdoc` red, "the example's name limit is not the code's (NAMEMAX)"
- mutation: `ENTRYMAILBOX` "Mailbox" -> "Inbox" -> `overviewdoc` red, "the example's reserved name is not the code's (ENTRYMAILBOX)"
- mutation: one word of `mcp.sourceStopped` ("stopped polling" -> "paused polling") -> `overviewdoc` red, "the example's stop notice is not the catalog's mcp.sourceStopped"
- mutation: one word of `digest.notCheckedStopped` -> `overviewdoc` red, "the example's digest line is not the catalog's digest.notCheckedStopped"
- mutation: one word of `checks.allPassed` ("Everything" -> "All") -> `overviewdoc` red, "the example's all-clear sentence is not the catalog's checks.allPassed"
- mutation: `INTERVAL_CHOICES` 15 -> 20 -> `overviewdoc` red, "the example's interval choices are not the code's (INTERVAL_CHOICES)"
- mutation: `DEFAULT_INTERVAL` 15 -> 30 -> `overviewdoc` red, "the example's default interval is not the code's (DEFAULT_INTERVAL)"
- mutation: `checkScheduleSource` "Polled every" -> "Checked every" -> `overviewdoc` red, "the example's rail line is not the code's (checkScheduleSource)"
- mutation: `sourceName` 'Source name' -> 'Name' -> `overviewdoc` red, "the example's label is not the code's sourceName"
- mutation: one word of P2 in the overview ("on a schedule" -> "on a timetable") -> `overviewdoc` red, "the MCP tools section lacks the source bullet word for word"
- mutation: the `source poll` guard restored in `mcp_doc_problems` -> `overviewdoc` red, "the committed worked example is good" got "a line mentions a source poll" (the example's "the source polls again" holds the phrase)
- Also in every `overviewdoc` run: a control for each of the digest lines, the four other labels and QUEUESECONDS that is not a whole number of minutes, with its one problem line; the committed files give "".
- Review-pass patches (same symlink-tree method, one mutated file each; `overviewdoc` red with the committed example's one problem line):
  - mutation: rail `checks: 'Background checks'` -> 'Scheduled checks' -> "the example's rail heading is not the code's (checks)"
  - mutation: chat `whatIChecked` 'What I checked' -> 'What was checked' -> "the example's list of what was checked is not the code's (whatIChecked)"
  - mutation: `Gate.cls` `MCPLABEL` "Running ..." -> "Calling ..." -> "the example's step label is not the code's (MCPLABEL)"
  - mutation: `Schedule.cls` heartbeat `DailyIncrement` 1 -> 5 -> "the code's heartbeat is not every minute (Schedule Tasks), so the example's background check is not every minute"
  - mutation: `removeButton` 'Remove' -> 'Delete' -> "the example's label is not the code's removeButton"
  - mutation: the stop-notice bullet duplicated in the example -> "the example's stop notice is not the catalog's mcp.sourceStopped"
  - mutation: the stop-notice count `-eq 1` -> `-ge 1` in the script -> "control: the stop notice quoted twice in the example" red
  - mutation: `mcp_source_problems` made to return at once -> every code-fact control red, by name: the two section-removed controls, the stop notice quoted twice, QUEUESECONDS 60, MISSEDSECONDS 120, QUEUESECONDS not whole minutes, SEENMAX 40, NAMEMAX 99, ENTRYMAILBOX Inbox, mcp.sourceStopped, checks.allPassed, all seven digest.* lines (digest.passed, notCheckedUnreachable, Timeout, Error, Stopped, Missed, Stale), INTERVAL_CHOICES, DEFAULT_INTERVAL, checkScheduleSource, sourceName, the seven labels (sourceHeading, sourceName, sourceArguments, sourceInterval, sources, removeButton, save), the rail heading, whatIChecked, MCPLABEL and the heartbeat

**Commands run (implement stage):**
- `bash docker/tests/test-release-sequence.sh overviewdoc` -> `PASS overviewdoc`
- `bash docker/tests/test-security-overview.sh --write` and then without `--write` (lane D throwaway, tag `e22s12i`) -> all checks passed; the file was byte-identical after the write (no generated region changed); `ci/iris.sh teardown` left nothing
- `bash docker/tests/test-readme.sh` -> all rules passed
- `bash ci/checks.sh` -> "checks: all scripts passed" (release-sequence, the whole script, 245 s inside it)

**Shared surfaces:**
- `ovw_mcp_example_lines`, whose numbering the existing controls 5, 10, 13 and 14 read: appended only;
- `mcp_doc_problems`' output, read by `t_overviewdoc`'s controls;
- the overview's `## MCP tools` section, which `test-readme.sh` `docs` reads (L187 position) and `ovw_doc_problems` reads;
- the `e-poll` control, replaced.

Every test added or changed passes on a fresh environment (a clean checkout), in either order. The checks are static, read only committed files and temporary copies under `$tmp`, and depend on no other rule's state.

## Auto Run Result

Status: done
Blocking condition: none

Implement and review pass (2026-11-15, `OCT-epic22` from `2d48d99fc`).

**Implemented change.** Section 4 and the digest section are in the worked example, with P1a as its intro, and P2 is in the overview's `## MCP tools` section. All three are word for word from `## Public text`, with the Planner's ruled sentence "The poll itself asks no model; only a new item's attention decision does.". Each sentence was re-checked against the code after 22.15 merged: its changes (Mcp/Ops.cls, Mcp/ToolClassification.cls and their tests) touch none of P1b's claims. 22.6's negative `source poll` guard and its `e-poll` control are replaced by ruled lines 15 to 41 (every P1b line, then P1a) with a loop control, and by `mcp_source_problems`, which reads every quoted fact from the code under a code root. The epics.md Step 4 pointer is corrected with its marker and old text.

**Files changed.**
- `docs/mcp-jira-example.md`: P1a (intro) and P1b (section 4 and the digest section).
- `docs/security-overview.md`: P2 as a new bullet in `## MCP tools`; the generated regions are unchanged (`test-security-overview.sh --write` left the file byte-identical, and its compare run passed).
- `docker/tests/test-release-sequence.sh`: the `overviewdoc` rule only: `OVW_MCP_SOURCE`, the appended ruled lines, `mcp_source_problems` and its helpers, `ovw_code_copy`, and the controls.
- `_bmad-output/planning-artifacts/epics.md`: the Step 4 release-check bullet only.
- This spec: the Verification mutation lines and the triage log.

**Review.** 25 findings from four layers: high 0, medium 4, low 16, false 5. One root cause, four medium rows (the step label, the Remove button, the Background checks heading, the What I checked list and the heartbeat's minute were pinned only to the doc itself) was patched with code-derived pins and controls (`removeButton` joined the labels; the rail heading, `whatIChecked`, `Gate.MCPLABEL` and the heartbeat's task definition are read from code). Four low rows were patched too: the stop notice is counted by occurrence with a quoted-twice control, the section-removed control has fixed assertions, and the missing mutation lines are written. Every other finding is rejected with its reason in the triage log (approved public text, the spec's own mechanism, pre-existing code, or theoretical). Nothing is deferred.

**Follow-up review recommended:** false (one medium entry patched, no high).

**Verification.** `bash docker/tests/test-release-sequence.sh overviewdoc` PASS (about 40 s); `... overviewdoc overview overviewdrift static` PASS; `bash docker/tests/test-readme.sh docs admin-mcp readme-anchors` PASS; `bash ci/checks.sh` "checks: all scripts passed" (release-sequence and readme inside it); `test-security-overview.sh --write` and compare passed on lane D's throwaway (tag `e22s12i`, torn down). Every mutation of the spec's list, and the review-pass ones, was observed red in a symlink-tree copy under scratch and left the tracked tree untouched (see Verification).

**Residual risks.** DW-1347 (lane C) must change P1b's cut sentence and its ruled-line pin in the same commit. The allowance's formula (`SourceSlack`) is read only through its two constants (reopen_if a rule change there goes uncaught). `ci/checks.sh` takes about 8 minutes, not the 20 to 40 seconds this spec states.
