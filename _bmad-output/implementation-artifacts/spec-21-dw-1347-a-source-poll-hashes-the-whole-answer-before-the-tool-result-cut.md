---
title: 'DW-1347: A source poll hashes the whole answer before the tool-result cut'
type: 'bugfix'
created: '2026-11-15'
status: 'ready-for-dev'
baseline_revision: '5f8292f89e7eecf841e9e82b43a1499d2750b4cb'
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
- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item. Even a long answer is compared whole, so a change anywhere in it makes a new item, but the item holds a long answer cut, as any tool's result is. Keep the answer short, for example with `maxResults`, so that the item holds all of it.
```

Why it is true of the fixed code:
- "compared whole": `Checks` compares `answerHash`, the hash of the proxy's whole text, taken before `Return`.
- "a change anywhere in it makes a new item": a different whole text gives a different hash. The bullet before it already says that an answer matching one of the 50 newest sends nothing.
- "the item holds a long answer cut, as any tool's result is": the Item's Text is `Reply.Text`, `Result.Return`'s output, the shown characters and the note.
- "so that the item holds all of it": an answer within the room comes back whole.

The line is ASCII, mentions no deadline and no replay path, and quotes no number.

**Same commit (Planner ruling, 22.12 spec gate ~06:30Z Nov 15):** the sentence and its pin always change in one commit:
- **22.12 not on the base (the case at plan time; Task 0 item 1):** this fix edits neither `docs/mcp-jira-example.md` nor `docker/tests/test-release-sequence.sh`. The line above is 22.12's wording. At 22.12's integrate, lane D puts it in P1b and in `ovw_mcp_example_lines` (as the same ruled line) in 22.12's own commit, so the old sentence never reaches feature. The lead relays this at the turn end (a prompts/ file).
- **22.12 on the base first (found at implement or integrate):** this fix's commit also replaces the old line in `docs/mcp-jira-example.md` and the identical line in `ovw_mcp_example_lines`, both in one commit. If it shows up only at integrate, the integrate stage makes that one commit, holding the doc line and the pin together, and runs `bash docker/tests/test-release-sequence.sh` for `overviewdoc` to show it passes, its loop control included. Nothing else in either file changes.

**Existing, reused:** `REASONREAD` ("Couldn't be read"), `CUTNOTE`. **Not product text:** `answerHash` (a HostData member that only Checks reads).

**Findability:** no UI change.

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

**Task 0 records:** (to be written by the implement stage)

## Auto Run Result

Status: ready-for-dev
Blocking condition: none. The spec gate decides Veto items 1-4.

- Summary: the plan only; nothing is implemented.
- Size: medium. Four product files, about 30 changed lines. Four test classes, about 150 lines. Two spine sentences. No oversized warning.
