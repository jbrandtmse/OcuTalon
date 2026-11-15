---
title: 'DW-1347: A source poll hashes the whole answer before the tool-result cut'
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: '8966d4c18b46b8bb8ae114273eab9e4901483dfd'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-11-run-source-polls-through-the-governed-proxy.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1347, from 22.11's code review):** a source poll's answer is cut at the tool-result room before anything hashes it.
- `Tools/McpCall.cls` `CallMcpTool` (L41-47) passes the room to `Mcp.Proxy.Call` and returns the text through `Result.Return` (L45).
- `Result.Return` cuts a text longer than the room (40,000 characters) to its first characters, a line break and `CUTNOTE` ("[cut by OcuTalon: {shown} of {total} characters shown]").
- `Bridge.Poll.Run` takes that value as `Reply.Text` (L90, L112). `Decide.PollAnswer` copies it (L816). `Checks.Process.RecordSource` hashes `Reply.Text` (L1262, `HashOf` L1312) and sends it as the Item's Text (`SourceItem` L1331).

So the hash covers only the shown part plus the note. An answer that changes only past the cut, at the same length, has the same hash, and no Item is sent. The spine says this today (AD-6 "Source polls", "not measured against an answer beyond the room"), and so does `Data/BackgroundCheck.cls`. `Reported.seen` is documented as "hashes of whole answers", which is not true for a long answer.

**Approach (Planner ruling ~20:40Z Nov 14: compare the hash of the FULL tool result, taken BEFORE the tool-result cut):**
- **The hash.** In a poll's context (`Bridge.Context IsPoll`), `Mcp.Proxy.Call` puts the SHA-256 of the whole text it got from the server into the context's HostData member `answerHash`, as 64 lower-case hex characters. It does this before it answers, so before `McpCall`'s `Return` cuts anything. HostData is the bridge's existing channel for "JSON a tool may fill" that the reply carries to the host (AD-31).
- **The carry.** `Bridge.Poll.Run` copies the context's HostData to the `Reply` when the call returned the tool's text, and `Decide.PollAnswer` copies `HostData` from the runner's Reply.
- **The compare.** `Checks` compares `answerHash` with `seen`, and no longer hashes `Reply.Text`. A passed answer with text but no usable `answerHash` is recorded as not checked with `REASONREAD` (Reason `error`). It never falls back to hashing the cut text, which would bring the defect back without anyone noticing.
- **Not changed:** the Item's Text, the chat path and `McpCall`. The Item's Text stays `Reply.Text`, the answer as cut (at most 40,000 characters, note included), because the Item goes to `Intake`'s attention decision, which a model makes. A chat call's result and its cut are unchanged, and the full text never enters a model's context.

## Boundaries & Constraints

**Always:**
- **Footprint (all Lane A packages, AD-29; the work is run by lane C, see Veto item 2):**
  - `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls`: `Noted` notes the hash for a poll's text answer; new `AnswerHash` and `Parameter ANSWERHASH = "answerHash"`; class and `Call` doc.
  - `src/bridge/cls/OcuTalon/Bridge/Poll.cls`: `Run` copies HostData on the text path; class doc step 7.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `PollAnswer` copies `HostData`; its doc comment.
  - `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: `SourceAnswer` and `RecordSource` take the hash from the Reply; `HashOf` is removed; class doc L94-96.
  - Tests: `Test/Mcp/SourceRun.cls`, `Test/Bridge/Poll.cls`, `Test/Mcp/Attach.cls` (`TestProxyCut`), `Test/Mcp/SourceRunProduction.cls`.
  - The spine record: `ARCHITECTURE-SPINE.md` AD-6 "Source polls" and AD-18 "Source polls, Part B", amended with tags (Veto item 4).
  - This spec.
- The hash is the same format `Checks.HashOf` writes today: SHA-256 of the UTF-8 text, 64 lower-case hex. An answer within the room therefore hashes exactly as before, so `seen` stays valid for it.
- Keep the 50-hash window (`SEENMAX`), the oldest-first order (`Newest`), the baseline rule, the empty-answer rule (passed, never an Item, no hash pushed), the repoint rule and the in-flight mark exactly as 22.11 built them.
- `answerHash` is written only in a poll's context, and only for a text answer. A refusal writes nothing and leaves the Reply's HostData empty.
- ObjectScript stays ASCII. Comments state the contract, not review history.

**Never:**
- Change `Tools/McpCall.cls`, `Tools/Result.cls`, the room, `CUTNOTE`, or what a chat or replay call returns or audits. `Proxy.Run`'s `cut` audit outcome stays as it is: the poll's text is still cut.
- Put the full answer in `Reply.Text`, the Item, a step, a log line or an audit entry, or carry it anywhere beyond `Proxy.Call`'s own variables.
- Add a property, column, table, message class, production item, catalog key or setting. Change `Msg.*`, `Data.*`, `Bridge/Msg/Reply.cls`, `Bridge/HostData.cls`, `Bridge/Context.cls` or any Lane B file.
- Edit `docs/mcp-jira-example.md` or `docker/tests/test-release-sequence.sh` unless Task 0 item 1 finds 22.12's cut sentence on the base (see Public text: "Same commit").
- Delete, skip, tag off or weaken a test.

## I/O & Edge-Case Matrix

Fixtures as in 22.11: server `zz`/`zzmcp`, tool `zz_lookup`, source "Jira". Room R = 40,000 characters. A = 50,000 characters of "a"; A' = A with its last character "b".

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Short answer | The mock answers "T-1 open" (within R). | `Reply.Text` = "T-1 open". `Reply.HostData` = `{"answerHash":"<SHA-256 hex of T-1 open>"}`. `seen` holds that hash, the same value 22.11 wrote. | none |
| 2 Long answer, baseline | A. | `Reply.Text` = the first characters of A that fit, a line break and "[cut by OcuTalon: N of 50000 characters shown]", R characters in all, as today. `answerHash` = hash of the whole A. The baseline sends no Item. | none |
| 3 Change past the cut (the defect) | After 2, A'. | `Reply.Text` is identical to scenario 2's, and `answerHash` = hash of A', which differs. One Item is sent. Its Text is the cut text of A', with the note. `seen` holds both hashes. | none |
| 4 Same long answer again | After 3, A' again. | No Item. passed. | none |
| 5 Empty answer | The mock answers "". | passed, no Item, `seen` unchanged (as today), whatever `answerHash` holds. | none |
| 6 No usable hash | A passed Reply whose Text is not empty and whose HostData is empty, not JSON, has no `answerHash`, or holds one that is not 64 lower-case hex. | not_checked with `REASONREAD` (CheckRun Reason `error`). No Item, `seen` and `baseline` unchanged, `stopped` cleared (a run that is not a stop). | none |
| 7 Refusal or denial | Any `POLLREASONS` word, `denied`, `failed`, the timer. | As 22.11. `Reply.HostData` is empty. | none |
| 8 Chat call | A user turn's `call_mcp_tool` gets a 100,000-character answer. | The cut value, the `cut` audit outcome and `ToolResultChars` are exactly as `TestProxyCut` pins today. The turn's HostData has no `answerHash` member. | none |
| 9 Online demo | `onlineDemo` 1. | No poll (22.11). The proxy refuses with `MCPDEMO` before any text, so nothing is noted. | none |

</intent-contract>

## Code Map

- `Mcp/Proxy.cls`: `Call` L41-57 calls `Run` (L50) and returns `..Noted(answer, approved)` (L56). `Noted` L61-65 already notes a poll's refusal word (`IsPoll`). `Run` L81-93 builds `{"text", "outcome"}` from `TextOf` (L202). This is the only place that holds the whole text.
- `Tools/McpCall.cls` L41-47: `Return` is the cut. Not changed.
- `Bridge/Poll.cls`: `Run` L46-121. The text path is L89-93; the reply is built at L110-118; the context ends at L109, so HostData has to be read before then. Class doc step 7, L13-15.
- `Bridge/Process/Decide.cls`: `PollAnswer` L803-824, which copies the fields one by one and leaves out `HostData`. Doc L798-802.
- `Bridge/HostData.cls`: `Put(member, value)` L17-22. It is in `Test/Bridge/CodeRules` `CALLBACKHELPERS`, so `Proxy`, which runs inside AI Hub's callback, may call it. `Bridge.Poll` is not on that list, so nothing in the callback may call it.
- `Checks/Process.cls`: `SourceAnswer` L1225-1239, `RecordSource` L1253-1282 (hash at L1262), `HashOf` L1312-1321 (its only caller is L1262), `SourceItem` L1323-1333, `REASONREAD` L171. Class doc L94-96.
- Tests: `Test/Mcp/SourceRun.cls` helper `Answer` L707-735 builds the Reply; `Hash` L743-751 is the test's own oracle. `Test/Bridge/Poll.cls` has `TestPollNoDecisionRow` L86-146 and `TestPollRunWords` L250 and up. `Test/Mcp/Attach.cls` has `TestProxyCut` L1413-1445. `Test/Mcp/Mock.cls`: `Call(port, "text", value)` keeps the value in a global, so a 50,000-character text works (inference; Task 0).
- `Mcp/Client.cls` `MAXBODY` = 1,000,000 bounds the body, so the whole text is at most about 1,000,000 characters, and at most 3,000,000 bytes in UTF-8, which is below the longest string, 3,641,144 (inference; Task 0 item 3).

## Tasks & Acceptance

**Task 0 (measure first, on lane C's throwaway, before any product change; record each result under `## Verification`):**
1. **The doc sentence on the base.** Run `git grep -n "compares whole answers" -- docs/mcp-jira-example.md docker/tests/test-release-sequence.sh` on this branch's base, and again at integrate. At plan time (97e062daf) it finds nothing: the worked example has no source-poll text, and `mcp_doc_problems` refuses one (test-release-sequence.sh L2371). Record the result. It decides the "Same commit" branch (Public text).
2. **The defect, observed.** Point the mock at A, then at A' (`Mock.Call(port, "text", ...)`), and call `Bridge.Poll.Run` for a Read-only source (the `TestPollRunWords` setup). Record that both Replies have the same `Text`, of length R, ending in "[cut by OcuTalon: N of 50000 characters shown]". If they differ, stop with `## Clarification Needed`: the defect is not as the ledger describes it.
3. **The hash bound.** Hash a 1,000,000-character text of `$Char(8364)` with the formula `AnswerHash` will use. Record that it gives 64 hex characters without `<MAXSTRING>`, and how many ms it takes. If it throws, hash with `$SYSTEM.Encryption.SHAHashStream(256, stream)` over a UTF-8 stream of the text instead (same digest), and record that.

**Execution:**
- [ ] `Mcp/Proxy.cls`:
  - `Parameter ANSWERHASH = "answerHash"`, documented as the HostData member through which a poll's proxy call gives the hash of the whole answer.
  - `ClassMethod AnswerHash(text As %String) As %String`: the SHA-256 of the UTF-8 text as 64 lower-case hex, the body of `Checks.HashOf` moved here (or the stream form from Task 0 item 3). It answers "" on any error and never throws.
  - `Noted`: when `##class(OcuTalon.Bridge.Context).IsPoll()` and `answer.%GetTypeOf("text") = "string"`, `Do ##class(OcuTalon.Bridge.HostData).Put(..#ANSWERHASH, ..AnswerHash(answer.text))`, inside a Try that ignores a failure. An empty hash is not put. The refusal branch is unchanged.
  - Update the class doc's poll bullet (L25-27) and `Noted`'s doc.
- [ ] `Bridge/Poll.cls` `Run`:
  - On the text path (L89-93), right after `Set text = answer.value`, read `##class(OcuTalon.Bridge.Context).Current().HostData` into a local. Set that local to "" at the top of `Run`.
  - When the reply is built, set `reply.HostData` from it.
  - Class doc step 7: "HostData is the context's HostData when the call returned the tool's text (the proxy's `answerHash`, the hash of the whole answer, taken before the cut), else empty."
  - The bridge names no host class (AD-2), so the member name is not used in the bridge.
- [ ] `Bridge/Process/Decide.cls` `PollAnswer`: `Set response.HostData = runnerReply.HostData` on the answered path. Add `HostData` to the doc's list of fields that are carried over.
- [ ] `Checks/Process.cls`:
  - `SourceAnswer` reads the hash from the Reply's HostData. Parse it in a Try. The member `##class(OcuTalon.Mcp.Proxy).#ANSWERHASH` must be a string matching `^[0-9a-f]{64}$`, else the hash is "".
  - When the outcome is passed, the text is not empty and the hash is "", the outcome becomes error.
  - `RecordSource(row, runAt, outcome, text, hash = "")` uses that hash in place of `..HashOf(text)`, and keeps `text = ""` as "no hash, no Item". The stop call at L1103 passes no hash.
  - Remove `HashOf`.
  - Class doc L94-96: "hashes of whole answers (the proxy's `answerHash`, taken before the tool-result cut)", "Text the answer as cut at the tool-result room", and "a passed answer with text but no usable `answerHash` is REASONREAD".
- [ ] Tests (one test class per foreground call):
  - `Test/Mcp/SourceRun.cls`:
    - `Answer` gains `hash As %String = "auto"`. "auto" sets `reply.HostData` to `{"answerHash": ..Hash(text)}` when the text is not empty. "none" leaves HostData empty. Any other value is put as the member. Every existing test keeps passing unchanged.
    - New `TestLongAnswerChangedPastCut` (matrix 2-4): the same cut Text (built with `OcuTalon.Tools.Result` `Return` on A, with no context) is sent with A's hash (the baseline), then with A''s hash (one Item, whose Text equals the cut Text and ends with the note, at most R characters), then with A''s hash again (no Item). `seen` holds both hashes, newest last.
    - New `TestNoAnswerHash` (matrix 5-6): each bad form (none, "not json", `{}`, an upper-case hex, 63 characters) on a passed Reply with Text records not_checked with `REASONREAD` and Reason `error`, sends no Item and leaves `seen` and `baseline` as they were. An empty Text with no hash is passed with no Item.
    - Header bullets for both.
  - `Test/Bridge/Poll.cls`:
    - `TestPollRunWords` gains: the short answer's `Reply.HostData` is `{"answerHash": <Hash("...")>}`, and a refusal's HostData is "".
    - New `TestPollWholeAnswerHash` (matrix 2-3, mock "text" A then A'): both `Reply.Text` are equal, of length R and end with the note. The two `answerHash` values are `Hash(A)` and `Hash(A')`, and they differ.
    - `TestPollNoDecisionRow`: the runner's Reply carries `HostData` `{"answerHash":"<64 hex>"}`, and Decide's answer has the same `HostData`. The timer's and the failed answer's are "".
  - `Test/Mcp/Attach.cls` `TestProxyCut` (matrix 8): after the cut call, `##class(OcuTalon.Bridge.HostData).Get("answerHash")` is "" (no member). Every existing assertion stays.
  - `Test/Mcp/SourceRunProduction.cls` new `TestLongAnswerChangedPastCutInProduction` (the integration AC; throwaway and CI only): a Read-only source whose mock answers A gets its baseline, and after the mock answers A', the next run sends one Item that reaches `Intake`. The Item's Text is at most R characters and ends with "[cut by OcuTalon: " ... " of 50000 characters shown]". The poll's Reply carries an `answerHash`.
- [ ] Spine (Veto item 4), word for word as under Design Notes.
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Acceptance Criteria:**
1. Given a poll whose answer is longer than the room, when only a part past the cut changes and the length stays the same, then `Checks` sends one new Item. The Item's Text is the cut answer with its note, and `seen` holds the hash of each whole answer.
   - mutation: `Checks` hashes `Reply.Text` again (restore `HashOf(text)` at the hash line) -> `TestLongAnswerChangedPastCut` red ("one Item").
2. Given a poll, when the proxy gets a text, then the Reply's `HostData.answerHash` is the SHA-256 hex of the whole text, and a refusal's Reply has no HostData.
   - mutation: `Noted` hashes the value cut to R (`$Extract(answer.text, 1, 40000)`) -> `TestPollWholeAnswerHash` red;
   - mutation: drop `Poll.Run`'s HostData copy -> `TestPollRunWords` red.
3. Given Decide answers a poll, when the runner's Reply carries HostData, then Decide's answer carries the same HostData.
   - mutation: drop the copy line in `PollAnswer` -> `TestPollNoDecisionRow` red.
4. Given a passed Reply with text and no usable `answerHash`, then the run is not checked with `REASONREAD`, no Item is sent and `seen` is unchanged.
   - mutation: fall back to `AnswerHash(text)` when the hash is "" -> `TestNoAnswerHash` red.
5. Given a chat call, then its result, its cut, its audit outcome and `ToolResultChars` are unchanged, and no `answerHash` is noted.
   - mutation: drop the `IsPoll()` condition in `Noted` -> `TestProxyCut` red ("no answerHash").
6. (Integration) Given the real production, when a long answer changes past the cut, then one Item reaches `Intake` with the cut text.
   - mutation: drop `Decide.PollAnswer`'s HostData copy -> `TestLongAnswerChangedPastCutInProduction` red (the run records error, no Item).
7. Every 22.11 test still passes unchanged: `SourceRun`, `SourceRunProduction`, `Bridge.Poll`, `Mcp.Proxy`, `Mcp.Attach`, `Bridge.CodeRules`. `test-boundaries.sh` passes (the bridge names no host class).

### Review Findings

Code review 2026-11-15 (full mode, acceptance auditor armed; diff `8966d4c18` to the tree at `d2ca12bc0` without bookkeeping). 20 layer findings (blind hunter 9, edge hunter 1, verification-gap 5, acceptance auditor 5): high 0; medium 3 rows in 2 entries, both patched; low 17: 3 patched, 2 ledgered `wontfix-accepted`, 12 rejected. No AD mismatch: the spine hunks match the Design Notes word for word, and the bridge code names no host class or `answerHash`.

- [x] [Review][Patch] (medium; blind hunter) `TestLongAnswerChangedPastCutInProduction` waited only for the Item (`Items()`), so its triage by Intake, Decide and the model mock could still run when `OnAfterOneTest` removed the trace (Rule 19 hermeticity). It now waits for `Decisions()`, as `TestNewResultReachesIntake` does. [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls:188]
- [x] [Review][Patch] (medium; blind hunter + verification-gap) The same test's Item Text assertions sat behind `If item.%Size() = 1` and nothing asserted that size, so AC 6's "with the cut text" could pass unchecked. It now asserts that the Item is in the session's trace. [src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRunProduction.cls:195]
- [x] [Review][Patch] (low; blind hunter) The `SourceItem` doc said "Text the answer". It now says "Text the answer as cut at the tool-result room", matching the class doc and AD-18 Part B. [src/ocutalon/cls/OcuTalon/Checks/Process.cls:1322]
- [x] [Review][Patch] (low; verification-gap) AC 2's refusal clause and AC 7 had no `mutation:` line. Both are now recorded under Verification: the refusal clause holds by construction, with no separating single mutation, and AC 7 is the regression list.
- [x] [Review][Defer] (low; verification-gap) A replay's proxy call has no pin that it notes no `answerHash`. Only a chat call is pinned (`TestProxyCut`), and the replay test is `Test/Mcp/Approval.cls`, which is outside this footprint. Filed as DW-1371, `wontfix-accepted` with `reopen_if`.
- [x] [Review][Defer] (low; acceptance auditor) Ruling (d) approves "the AD-6, AD-31 and AD-18 Part B amendments" verbatim, but this spec writes no AD-31 text. Decided in this unattended run: "AD-31" is the AD that Veto item 4 names for the HostData channel ("AD-6 and AD-31"). The approved verbatim text is the two Design Notes amendments, which are applied word for word, and AD-31's Rule is unchanged and holds. Filed as DW-1372, `wontfix-accepted`, `reopen_if` the Planner meant more text. The lead may confirm it with the Planner.

Rejected:
- Edge hunter: a poll in flight across the upgrade gets one REASONREAD run. `false`: no release has source polls (22.11 is in no tag), and 22.11 ships with this fix in 1.0.11.
- Blind hunter: no log line when `Checks` sees no usable hash. `low`, rejected: it is unreachable in normal running, the coverage list shows "Couldn't be read", and the fix adds a branch.
- Blind hunter: the spine's Conventions table does not list `answerHash`. `false`: HostData members are recorded in their own AD records (`learned` too, at AD-21). `answerHash` is in the amended AD-6 and AD-18 lines, and it is not a cross-lane carrier.
- Blind hunter: the `Bridge/HostData.cls` and `Tools/HostData.cls` docs do not list the member. Rejected as spec-bound: this spec forbids changing `Bridge/HostData.cls` and naming the member in the bridge, and `Tools/HostData.cls` is outside the footprint.
- Blind hunter: `Proxy` calls `Bridge.HostData.Put` and not the `Tools.HostData` facade. `by-design`: the Execution task prescribes it, and `Bridge.HostData` is in `CALLBACKHELPERS`.
- Blind hunter: the Auto Run Result says nine mutation lines (now twelve, plus this review's). Rejected: the fix edits an earlier pass's section of the spec. These records supersede it.
- Blind hunter: the triage log says `$` matches before a final line break. Rejected: the fix edits the spec's earlier log. For the record, `$Match` matches the whole string, so a 64-hex hash with a final line break is refused, as QA probed.
- Acceptance auditor: the "AD-6" amendment sits in AD-10's section. `false`: it is the bullet tagged "(AD-6, AD-10; Story 22.11)", and the replaced sentence occurred only there.
- Acceptance auditor: `Proxy.Call`'s doc is not updated. `false`: it defers to the class description, which is updated, and nothing in it is untrue.
- Acceptance auditor: `Poll.cls` names `answerHash` in a comment. `by-design`: the spec dictates that step 7 sentence. No code line in `src/bridge/` names it, and `test-boundaries.sh` skips comments.
- Acceptance auditor: `cycle-log-epic-21.md` is in the diff. `false`: it is bookkeeping, excluded from the footprint check.
- Verification-gap (other): `Prepare` makes the row due before the mock is set to A. `low`, rejected: the window is milliseconds, the outcome would be a loud red ("seen holds..."), never a false green, and the sibling test has the same order.

## Design Notes

**Governing ADs:** AD-6 (source polls; no model in a poll), AD-10 (the cut stays where it is, for every model step), AD-18 (Part B: what `seen` holds), AD-21, AD-31 (HostData is the reply's channel from a tool to the host), AD-2 (the bridge copies HostData without naming its members), AD-33 (`Checks` alone writes `Reported`). Nothing in them is contradicted. Two of their records are amended below.

**Why the Proxy and not McpCall.** The ledger's note asked for an empty room for a poll in `McpCall`. That would put the whole answer in `Reply.Text` and the Item, up to about 1,000,000 characters, and so in the attention decision's model input and in two Ens message bodies. `Test/Bridge/CodeRules` `TestToolsReturnThroughResult` also requires every code line of a tool class to quit through `..Return(`, so `McpCall` cannot return the uncut text or hold a helper that returns a hash. `Mcp.Proxy` is the one place that holds the whole text. It already handles a poll on its own (`Noted`), and it is a listed callback helper.

**Why no fallback to the shown text.** A fallback would make the doc sentence below untrue without anyone noticing, and keep a second copy of the hash formula in `Checks`. A missing hash is a broken bridge-to-host contract. It shows as "Couldn't be read" on the coverage list, and the production test pins the whole chain.

**Item size.** The Item stays at most R characters, note included (`Result.Return` on a fresh poll context, whose `ToolResultChars` starts at 0, `Context.Begin` L89). The answer's Ens messages hold the cut text, as in 22.11, plus a 64-character hash in `HostData`. `HostData` holds no argument, URL or secret, so 22.11's `TestNoSecretLeaks` rules hold.

**Spine amendments (Veto item 4), word for word:**
- AD-6 "Source polls", replace "A poll's answer is cut at the tool-result room like any tool result (not measured against an answer beyond the room)." with: "A poll's answer is cut at the tool-result room like any tool result. Before the cut, the proxy puts the SHA-256 of the whole answer (64 lower-case hex characters) in the context's HostData member `answerHash`, and `Poll.Run` and `Decide.PollAnswer` carry that HostData on the `Reply` [AMENDED 2026-11-15, DW-1347, Contest Planner ruling ~20:40Z Nov 14: it read "A poll's answer is cut at the tool-result room like any tool result (not measured against an answer beyond the room)."]."
- AD-18 "Source polls, Part B", replace "after it, an answer whose hash is not in `seen` becomes one Item for `Intake` (provenance `untrusted`, channel `system`, Subject the source's name, Text the answer) and joins `seen`; an empty answer is `passed` and never an Item." with: "after it, an answer whose `answerHash` (the hash of the whole answer, taken before the cut) is not in `seen` becomes one Item for `Intake` (provenance `untrusted`, channel `system`, Subject the source's name, Text the answer as the `Reply` holds it, cut at the tool-result room) and joins `seen`; an empty answer is `passed` and never an Item, and an answer with text but no usable `answerHash` is Reason `error` [AMENDED 2026-11-15, DW-1347, Contest Planner ruling ~20:40Z Nov 14: it read "an answer whose hash is not in `seen` becomes one Item for `Intake` (provenance `untrusted`, channel `system`, Subject the source's name, Text the answer)"]."

**For 22.12 (lane D), at its integrate:** its Code Map claim 9 ("The cut") becomes: "the proxy hashes the whole answer before the cut (`Mcp/Proxy.cls` `Noted`, `answerHash`), `Checks` compares that hash, and the Item holds the answer as cut (`Checks/Process.cls` `SourceItem`)". Its Decided-in-stage 3 and Cross-lane item 3 are closed by the replacement line below. Its P1b line "with the whole answer as its text" (the bullet before the cut sentence) is still true of an answer within the room. The replacement line now says plainly that a long one is cut, so this spec asks for no change there.

**Ledger inbox:** DW-1347 (this spec). Its status line is recorded per the run's DW process at merge.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | The replacement for 22.12's P1b cut sentence, word for word under Public text. It is not shipped by this fix while 22.12's section is not on feature (Task 0 item 1); 22.12 takes it, with its `ovw_mcp_example_lines` pin, at its integrate. No product string changes: `REASONREAD` and `CUTNOTE` are reused as they are. | Approve. The line is true of the fixed code: it says the whole answer is compared and the item holds a long answer cut. |
| 2 | (b) Cross-lane edits | Every file is in a Lane A package (`Mcp.Proxy`, `Bridge.Poll`, `Bridge.Process.Decide`, `Checks.Process`, `Test.Mcp.*`, `Test.Bridge.Poll`) plus the spine record, and lane C makes the edits (an epic-21 worktree, whose home lane is B). Conditionally, also lane D's `docs/mcp-jira-example.md` and `docker/tests/test-release-sequence.sh` (one line each), only if 22.12 is on the base first. At plan time no in-flight branch (`OCT-epic22`, `OCT-epic22-s2214`, `OCT-epic21`, `OCT-epic21-s2115`, `OCT-epic21-s219`) touches these files. | Approve, as the Planner's lane C assignment. The lead serializes the merge against any Lane A story that touches these files. |
| 3 | (c) Stored data or schema | No class, property, column or storage change. `Reply.HostData` (an existing property) carries `{"answerHash"}` on a poll's Replies. `Reported.seen` keeps its approved shape (22.11 veto 2) and now matches its documented meaning: hashes of whole answers. A short answer's hash does not change. A source whose stored hash came from a cut answer sends one Item on its first poll after the fix. 22.11 is in no release (no tag contains 97e062daf; the newest is v1.0.10), so only dev and throwaway rows hold such a hash. | Approve, with no migration. |
| 4 | (d) Architecture additions | Two additions: a new HostData member `answerHash` (the bridge-to-host poll contract, AD-6 and AD-31), and a new failure rule (a passed answer with text and no usable hash is Reason `error`). The spine records AD-6 "Source polls" and AD-18 Part B are amended word for word (Design Notes). `Checks` reads `Mcp.Proxy`'s `ANSWERHASH` parameter, a domain-to-domain reference of the kind it already makes (`Mcp.ToolClassification`, `Mcp.Ops`). | Approve. |

## Public text

**NEW, for 22.12's P1b** (`docs/mcp-jira-example.md`, the bullet under the source section's poll list). This whole line replaces the line that 22.12's spec gives as "- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item, which holds the whole answer. A long answer is cut, as any tool's result is, and a change only in the part that was cut off may not make a new item, so keep the answer short, for example with `maxResults`.":

```
- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item. Even a long answer is compared whole, so a change anywhere in it makes a new item, but a long answer is cut in the item, as any tool's result is. Keep the answer short, for example with `maxResults`, so that the item holds all of it.
```

Why it is true of the fixed code:
- "compared whole": `Checks` compares `answerHash`, the hash of the proxy's whole text, taken before `Return`.
- "a change anywhere in it makes a new item": a different whole text gives a different hash. The bullet before it already says that an answer matching one of the 50 newest sends nothing.
- "a long answer is cut in the item, as any tool's result is": the Item's Text is `Reply.Text`, `Result.Return`'s output, the shown characters and the note.
- "so that the item holds all of it": an answer within the room comes back whole.

The line is ASCII, mentions no deadline and no replay path, and quotes no number.

**Same commit (Planner ruling, 22.12 spec gate ~06:30Z Nov 15):** the sentence and its pin always change in one commit:
- **22.12 not on the base (the case at plan time; Task 0 item 1):** this fix edits neither `docs/mcp-jira-example.md` nor `docker/tests/test-release-sequence.sh`. The line above is 22.12's wording. At 22.12's integrate, lane D puts it in P1b and in `ovw_mcp_example_lines` (as the same ruled line) in 22.12's own commit, so the old sentence never reaches feature. The lead relays this at the turn end (a prompts/ file).
- **22.12 on the base first (found at implement or integrate):** this fix's commit also replaces the old line in `docs/mcp-jira-example.md` and the identical line in `ovw_mcp_example_lines`, both in one commit. If it shows up only at integrate, the integrate stage makes that one commit, holding the doc line and the pin together, and runs `bash docker/tests/test-release-sequence.sh` for `overviewdoc` to show it passes, its loop control included. Nothing else in either file changes.

**Existing, reused:** `REASONREAD` ("Couldn't be read"), `CUTNOTE`. **Not product text:** `answerHash` (a HostData member that only Checks reads).

**Findability:** no UI change.

## Spec gate rulings (Contest Planner, ~09:10Z Nov 15, BINDING)

- APPROVED, with one wording fix. The Public text line above ships verbatim as ruled ("but a long answer is cut in the item, as any tool's result is").
- CONDITION: a test where two long answers differ only past the cut point must make a new item, as the AC's mutation. AC 1 (`TestLongAnswerChangedPastCut`, and its mutation of restoring `HashOf(text)`) is that test. Keep it, and record its red/green under Verification.
- Option (a) APPROVED: lane D carries the line and its `ovw_mcp_example_lines` pin into 22.12's own commit, and rewords claim 9. If 22.12 lands first, one DW-1347 commit replaces both the line and its pin.
- (b) APPROVED: lane C edits lane A's Mcp/Bridge/Checks files and the spine. Lane A (25.6) stays out of them until DW-1347 merges.
- (c) APPROVED: no migration. The one extra Item on the first poll after the fix is accepted.
- (d) APPROVED verbatim: the AD-6, AD-31 and AD-18 Part B amendments, plus the no-hash error rule.

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1347iw`.
- One test class per foreground call, `timeout: 600000`, each under about 3 minutes. Never two `iris_execute_tests` calls in one message.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e21dw1347iw ci/warm.sh up`, then Task 0 items 2 and 3.
- (loop) Warm, each `ci/iris.sh class <Class>`, expected to pass:
  - `OcuTalon.Test.Mcp.SourceRun`
  - `OcuTalon.Test.Bridge.Poll`
  - `OcuTalon.Test.Mcp.Attach`
  - `OcuTalon.Test.Mcp.Proxy`
- (once) Warm, each `ci/iris.sh class <Class>`, expected to pass:
  - `OcuTalon.Test.Mcp.SourceRunProduction`
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Bridge.CodeRules`
  - `OcuTalon.Test.Tools.Result`
  - `OcuTalon.Test.Checks.Runs`
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: exit 0.
- (once, only on the "22.12 on the base" branch) `bash docker/tests/test-release-sequence.sh` for `overviewdoc`: passes.
- (once) `git diff --name-only 5f8292f89` lists only the footprint files.
- (once, at the end, also after a failure) `OCUTALON_RUN_TAG=e21dw1347iw ci/warm.sh down`.

**Mutations:** one per AC as listed under Acceptance Criteria. Record each as `mutation: <change> -> <test that went red>`. Revert it byte for byte, and check that `git status --short` and `git diff --stat` are as before.

**Task 0 records** (lane C warm throwaway `e21dwiw`, before any product change; base 8966d4c18):
- Item 1: `git grep -n "compares whole answers" -- docs/mcp-jira-example.md docker/tests/test-release-sequence.sh` finds nothing (exit 1). 22.12's sentence is not on the base, so this commit edits neither file.
- Item 2 (the defect, observed): the mock answered A (50,000 "a") then A' (A with its last character "b"), and `Bridge.Poll.Run` ran for a Read-only source. Both Replies have the same `Text`, 40,000 characters long, ending in a line break and "[cut by OcuTalon: 39949 of 50000 characters shown]", with no failure word (`same=1`). The defect is as the ledger describes it.
- Item 3 (the hash bound): the `Checks.HashOf` formula (`SHAHash(256, $ZConvert(text, "O", "UTF8"))` and the hex loop) over 1,000,000 characters of `$Char(8364)` gave 64 hex characters, no `<MAXSTRING>`, in 2.4 ms. `AnswerHash` uses that formula; no stream-hash fallback is needed.

**Implement records** (lane C warm throwaway `e21dwiw`; each mutation applied alone, red observed, reverted byte for byte, `git status --short` and `git diff --stat` as before, and the class green again on the same stack):
- mutation: `Checks` hashes the Reply's text again (`Set hash = AnswerHash(text)` at the hash line, in place of `HashOf(text)`) -> `TestLongAnswerChangedPastCut` red ("a change past the cut is one Item", "the same whole answer again sends no Item", "seen holds both hashes"); `OcuTalon.Test.Mcp.SourceRun` green after the revert.
- mutation: `Noted` hashes the text cut to R (`AnswerHash($Extract(answer.text, 1, 40000))`) -> `TestPollWholeAnswerHash` red ("the first answerHash is the hash of the whole answer", "the second is the hash of the changed answer", "and they differ"); `OcuTalon.Test.Bridge.Poll` green after the revert.
- mutation: drop `Poll.Run`'s HostData copy (`Set reply.HostData = hostData`) -> `TestPollRunWords` red ("its HostData is the answerHash, the SHA-256 of the answer"); `OcuTalon.Test.Bridge.Poll` green after the revert.
- mutation: drop the copy line in `PollAnswer` (`Set response.HostData = runnerReply.HostData`) -> `TestPollNoDecisionRow` red ("and the runner's HostData, with its answerHash of 64 hex characters", "the answerHash is 64 lower-case hex characters"); `OcuTalon.Test.Bridge.Poll` green after the revert.
- mutation: fall back to `AnswerHash(text)` when the hash is "" (in place of the error outcome) -> `TestNoAnswerHash` red (every bad form: REASONREAD, Reason `error`, no Item, seen and baseline as they were); `OcuTalon.Test.Mcp.SourceRun` green after the revert.
- mutation: drop the `IsPoll()` condition in `Noted`'s hash branch -> `TestProxyCut` red ("a chat call notes no answerHash: no member is in the turn's HostData"); `OcuTalon.Test.Mcp.Attach` green after the revert.
- mutation: drop `Decide.PollAnswer`'s HostData copy -> `TestLongAnswerChangedPastCutInProduction` red ("one Item went from Checks to Intake, though the answer changed only past the cut", "the poll's Reply carries the answerHash of the whole answer"; the run records error); `OcuTalon.Test.Mcp.SourceRunProduction` green after the revert.
- Warm, passing on the final tree: `OcuTalon.Test.Mcp.SourceRun`, `OcuTalon.Test.Bridge.Poll`, `OcuTalon.Test.Mcp.Attach`, `OcuTalon.Test.Mcp.Proxy`, `OcuTalon.Test.Mcp.SourceRunProduction`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Tools.Result`, `OcuTalon.Test.Checks.Runs`. `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`: exit 0.
- Review patches (two mediums; each mutation applied alone, red observed, reverted byte for byte, `git status --short` and `git diff --stat` as before, class green again on the same stack):
  - mutation: delete `If text = "" Set hash = ""` in `Checks.RecordSource` -> `TestNoAnswerHash` red ("an empty text with the hash of the empty text is passed, with no Item, and seen is as it was"); `OcuTalon.Test.Mcp.SourceRun` green after the revert.
  - mutation: `AnswerHash` hashes `text` without `$ZConvert(text, "O", "UTF8")` -> `TestPollWholeAnswerHash` red ("a character beyond 255 is hashed as UTF-8"); `OcuTalon.Test.Bridge.Poll` green after the revert.
  - `TestPollWholeAnswerHash` carries no `Poll.Run` case with a character beyond 255: the mock's transport answers such a character as "?" (measured), so the UTF-8 pin is the direct `AnswerHash` call against the SHA-256 digest of the euro sign.
- Lead checks after the handoff: `npm test` in `web/` (the node suite): 2104 tests, 0 failed. `bash docker/tests/test-boundaries.sh`: all rules passed. `git diff --name-only 8966d4c18` lists only the footprint files (this spec, the spine, four product classes, four test classes). The spine's `updated:` is 2026-11-15; `lint_spine.py` reports no `ad_id` or `ad_fields` finding and the same 10 low `placeholder` findings (`ok: false`) as the spine at the base, none in the amended lines. The spine folder has no `.memlog.md` (it is gitignored and absent), so no memlog line was appended.
- Shared surfaces: none (no list, menu, roster, schema or count that other tests assert on changes).

**QA records** (lane C warm throwaway `e21dwqw`; each mutation applied alone, red observed, reverted byte for byte, `git status --short` and `git diff --stat` as before, `OcuTalon.Test.Mcp.SourceRun` green again on the same stack):
- Gap weighed and closed: `TestNoAnswerHash` took the forms none, not JSON, no member, a number of 5, upper-case hex and 63 characters. The matrix's "wrong length or not hex" was pinned only for 63 characters and upper case, so a hash of 65 characters, one of 64 characters with a letter that is not hex, a 64-digit JSON number (not a string) and a 64-hex array member are added to its list. No new test method.
- mutation: the match in `Checks.SourceAnswer` allows a longer hash (`{64}` -> `{64,}`) -> `TestNoAnswerHash` red (the 65-character form: "not_checked with REASONREAD", then the cascade of "no Item is sent");
- mutation: the match allows letters beyond f (`[0-9a-f]` -> `[0-9a-z]`) -> `TestNoAnswerHash` red (the form with a "g": "not_checked with REASONREAD", "no Item is sent", "seen and baseline are as they were");
- mutation: drop the string check on the member (`data.%GetTypeOf(...) = "string") && `) -> `TestNoAnswerHash` red (the 64-digit JSON number form: "not_checked with REASONREAD", "no Item is sent", "seen and baseline are as they were").
- Gaps weighed and not added (already pinned, or no new behavior): the same long answer again (`TestLongAnswerChangedPastCut` step 3), a short answer's hash as before (the abc and euro vectors in `TestPollWholeAnswerHash`, the 22.11 oracle in `SourceRun`), the 50-hash window (`TestSeenBefore`, which feeds whole-answer hashes through `Answer`), a chat call's HostData and cut (`TestProxyCut`), an empty answer with a hash (`TestNoAnswerHash`). A hash of 64 hex characters plus a final line break is also rejected (probed, passes; no mutation separates it, so not added). No product bug found.

**Code review records** (lane C warm throwaway `e21dwcw`; each mutation applied alone, red observed, reverted byte for byte, `git status --short` and `git diff --stat` as before, the class green again on the same stack):
- Warm, passing: `OcuTalon.Test.Mcp.SourceRun` (1.4 s), `OcuTalon.Test.Bridge.Poll` (28.4 s), `OcuTalon.Test.Mcp.Attach` (183.3 s), and after the review patches `OcuTalon.Test.Mcp.SourceRunProduction` (46.9 s) and `OcuTalon.Test.Mcp.SourceRun` (0.8 s).
- mutation (the new pin "the Item is in the session's trace" in `TestLongAnswerChangedPastCutInProduction`): drop `Decide.PollAnswer`'s HostData copy -> `TestLongAnswerChangedPastCutInProduction` red ("one Item went from Checks to Intake, though the answer changed only past the cut", "the Item is in the session's trace", "the poll's Reply carries the answerHash of the whole answer"); `OcuTalon.Test.Mcp.SourceRunProduction` green after the revert (47.0 s).
- mutation (the Planner's CONDITION, observed again): `RecordSource` hashes the Reply's cut text (`Set hash = $Select(text = "": "", 1: ##class(OcuTalon.Mcp.Proxy).AnswerHash(text))` in place of `If text = "" Set hash = ""`) -> `TestLongAnswerChangedPastCut` red ("a change past the cut is one Item", "the same whole answer again sends no Item", "seen holds both hashes, newest last"); `OcuTalon.Test.Mcp.SourceRun` green after the revert.
- AC 2, second clause (a refusal's Reply has no HostData): no single mutation separates it. Two independent guards hold it: the proxy's refusal (`{"refusal", "outcome"}`) has no `text`, so `Noted` writes nothing, and `Poll.Run` copies HostData only on the text path. The `HostData = ""` assertions in `TestPollRunWords`, `Refuses` and `TestPollNoDecisionRow` record that by construction. Removing either guard alone is an equivalent mutant.
- AC 7 (every 22.11 test passes unchanged) is the regression list, not a behavior of its own, so it has no mutation. Its evidence is the green classes above and in the implement records.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 20 findings (blind hunter 9, edge hunter 5, verification-gap 6; the intent auditor is descriptive) - high 0, medium 3 (two entries), low 17, false 0, maybe-false 0
- findings:
  - Blind hunter 1, edge hunter 2 (`Noted`/`AnswerHash` fail silently, no log): `[low]` `reject` - the spec says the failure is ignored; a missing hash shows as "Couldn't be read" on the coverage list, and a log line is more code than a cosmetic gain.
  - Blind hunter 2 (`$` in `^[0-9a-f]{64}$` also matches before a final line break): `[low]` `reject` - only the proxy writes `answerHash`, and it writes 64 hex characters; no reachable input.
  - Blind hunter 3 and verification-gap 2 (no known-vector or non-ASCII hash test): `[medium]` `patch` - real: dropping the UTF-8 conversion kept every test green while a wide-character answer would hash to "". Fixed: `TestPollWholeAnswerHash` asserts `AnswerHash` against the SHA-256 vector of "abc" and of the euro sign; mutation recorded.
  - Blind hunter 4 (the failure branch of `Noted` is untested): `[low]` `reject` - it needs failure injection into `SHAHash`; the spec asks only that a failure is ignored.
  - Blind hunter 5 (the hash formula exists in `Channel.Email.Out` too): `[low]` `reject` - pre-existing sibling that this fix does not touch; `Proxy.AnswerHash` is the moved body of `Checks.HashOf`, which is removed, so this adds no copy.
  - Blind hunter 6 (an Item whose Text equals the last one's): `[low]` `reject` - by-design: the Item's Text stays the answer as cut (the Planner's ruling in the spec's intent).
  - Blind hunter 7, edge hunter 1 (one extra Item after upgrade for a long answer): `[low]` `reject` - by-design: Veto item 3 approved it, no migration.
  - Blind hunter 8, edge hunter 4 (the hash is parsed for every Reply): `[low]` `reject` - harmless and the parse is in a Try; a guard adds a branch for no user-visible change.
  - Blind hunter 9 (the spec does not cite `MAXBODY` for the hash bound): `[low]` `reject` - the fix would edit this build's spec; the Code Map already cites `MAXBODY`.
  - Edge hunter 3 (`Context.Current()` empty between two sets in `Poll.Run`): `[low]` `reject` - `Run` begins the context itself, so it is never empty there.
  - Edge hunter 5 (AC 7 says "unchanged" but existing assertions gain a HostData check): `[low]` `reject` - the spec's own task list asks for those additions.
  - Verification-gap 1 (an empty text with a valid hash of the empty text is not tested): `[medium]` `patch` - real: the proxy hashes an empty text too, so `RecordSource`'s `If text = "" Set hash = ""` is the only guard against an empty Item and no test pinned it. Fixed: `TestNoAnswerHash` runs an empty text with `Hash("")` and asserts passed, no Item and `seen` as it was; mutation recorded.
  - Verification-gap 3 (no direct test of `Proxy.AnswerHash` or the `Noted` Try/Catch): `[low]` `reject` - `AnswerHash` is now pinned directly (patch above); the Catch needs failure injection (see blind hunter 4).
  - Verification-gap 4 (the refusal's empty HostData has no distinguishing mutation): `[low]` `reject` - an equivalent mutant: the proxy writes nothing for a refusal, so copying on every path still gives an empty HostData.
  - Verification-gap 5 (the mock is restored only at the end of two tests): `[low]` `reject` - the existing tests (`TestProxyCut`) do the same, and the next test sets the mock text it needs.
  - Verification-gap 6 (`Result.Return` in `TestLongAnswerChangedPastCut` assumes no leaked context): `[low]` `reject` - the test's own "fills the room" assertion would fail loudly.
  - Intent-alignment (descriptive, no findings): the implemented reading is the proxy's answer path, HostData carried by `Poll.Run` and `Decide.PollAnswer`, and `Checks` comparing the member; it reports no divergence from the intent.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: a source poll now compares the SHA-256 of the whole tool answer, taken in `Mcp.Proxy` before the tool-result cut and carried in the Reply's HostData member `answerHash`. A change only past the cut sends one Item (its Text is still the cut answer). A passed answer with text and no usable `answerHash` is not checked with `REASONREAD`; there is no fallback to hashing the cut text. Task 0 on the lane C throwaway: 22.12's sentence is not on the base (no doc or pin edit), the defect reproduced (same cut Text for A and A'), and a 1,000,000-character hash took 2.4 ms with no `<MAXSTRING>`.
- Files changed:
  - `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls`: `ANSWERHASH`, `AnswerHash`, `Noted` notes the hash for a poll's text answer.
  - `src/bridge/cls/OcuTalon/Bridge/Poll.cls`: `Run` copies the context's HostData on the text path.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `PollAnswer` copies `HostData`.
  - `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: `SourceAnswer` and `RecordSource` use `answerHash`; `HashOf` removed.
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls`, `Test/Bridge/Poll.cls`, `Test/Mcp/Attach.cls`, `Test/Mcp/SourceRunProduction.cls`: the pins and the integration test.
  - `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: AD-6 "Source polls" and AD-18 "Source polls, Part B" amended word for word, `updated:` 2026-11-15.
- Review findings: 20 reported, no high. 3 medium rows in 2 entries patched (the empty-text-with-hash pin; the UTF-8 hash pin, found by two layers). 17 low rows rejected with their reasons in the triage log. None deferred.
- Follow-up review recommendation: `false` (no high was patched, per the run's instruction; two mediums were patched, each with a recorded mutation).
- Verification: warm classes `SourceRun`, `Bridge.Poll`, `Mcp.Attach`, `Mcp.Proxy`, `SourceRunProduction`, `Bridge.Decide`, `Bridge.CodeRules`, `Tools.Result`, `Checks.Runs` passed (`SourceRun` and `Bridge.Poll` again after the review patches); `test-boundaries.sh` and `test-class-rules.sh` exit 0; the node suite (`npm test` in `web/`) 2104 passed; nine mutation lines recorded under `## Verification`, including the Planner's CONDITION (`TestLongAnswerChangedPastCut` red when `Checks` hashes the cut text again, green after).
- Residual risks: the first poll after the fix sends one extra Item for a source whose stored hash came from a cut long answer (approved, no migration). The spine lint reports the same 10 low placeholder findings as at the base (`ok: false`); none is in the amended lines. 22.12 (lane D) still has to carry the Public text line and its pin at its own integrate. The handoff subagent launched two warm test classes in one message once (both passed); noted as a Rule 18 slip.
