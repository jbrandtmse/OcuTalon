---
title: 'DW-1371: A replayed MCP call notes no answer hash'
type: 'chore'
created: '2026-11-15'
status: 'done'
baseline_revision: '1777dbad570db9eefe5ea1e300f9797a743fcef7'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1347-a-source-poll-hashes-the-whole-answer-before-the-tool-result-cut.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1371, LOW, from DW-1347's code review):** `Mcp/Proxy.cls` `Noted` (L67-78) writes `answerHash` into the context's HostData only when `Context.IsPoll()` is true (L70). The class doc (L28-29) says "no other call writes it". Only a chat call pins that, in `Test/Mcp/Attach.cls` `TestProxyCut` (L1439). Nothing pins it for the replay of an approved call. So widening the hash guard to `((approved '= "") || IsPoll())`, the same shape as the refusal guard on L69, keeps every test green.

**Why no existing replay test can catch it (measured by reading, not run):** a real replay runs in the runner job (`Bridge/Replay.cls` `Execute`). It ends the context at L145, before it builds the Reply at L148-154, and the Reply never gets HostData (class doc step 4: "The reply holds no text and no host data"). So a replay's HostData leaves no trace outside its own context. An assertion on the Reply or the row in `TestReplayResultIsCut` stays green under the widened guard, so on its own it would be a vacuous pin.

**Approach (tests only, Planner-accepted follow-up for 1.0.12):** one new test in `Test/Mcp/Approval.cls`. It builds the replay's context in the test process the way the product does: `Context.Begin` with the replay's request, then `Context.Grant(ref)` (as `Replay.Execute` L106-107 does), then `Context.TakeGrant` on the native triple (as `Policy/Gate.cls` L233 does). It then calls `Mcp.Proxy.Call` directly, once with a long text answer and once with a short one, and reads the context's HostData before it ends the context. A control step, run the same way in a poll's context, shows that this channel does hold an `answerHash` when the guard admits the call. `TestReplayResultIsCut` also gains one assertion that the end-to-end replay's Reply holds no HostData. That assertion guards the ledger's second `reopen_if` clause.

## Boundaries & Constraints

**Always:**
- Footprint: `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls` and this spec. Nothing else. The ledger's status line for DW-1371 is written at merge, per the run's DW process, as bookkeeping.
- The new test reaches the proxy only through product APIs: `Context.Begin`, `Grant`, `TakeGrant`, `Current`, `End`, `Approval.StartExecution`, `Mcp.Proxy.Call`, `Bridge.HostData.Get`. It never sets `^||OcuTalonBP.Context` nodes by hand.
- Every context the test begins is ended on every path. `OnAfterOneTest` gains `Do ##class(OcuTalon.Bridge.Context).End()` as its first line, as `Test/Mcp/Attach.cls` L155 has. A context left in the test process would make a later test's `Approval.Answer` run as origin tool.
- Fixtures come from `JobFixture` as they are: the server `zzmcp`, its tool rows, the mock, the wallet secret and the Config Store entry. The approved row comes from `Approved()`, which tracks it so that `OnAfterOneTest` deletes it. The secret appears in no assertion message.
- ObjectScript stays ASCII. The class header gets one bullet for the new test, and the `TestReplayResultIsCut` bullet gains its new clause. Comments state the contract, not review history.

**Never:**
- Change product code: `Mcp/Proxy.cls`, `Bridge/Context.cls`, `Bridge/Replay.cls`, `Bridge/Policy/Gate.cls`, `Bridge/HostData.cls`, `Msg.*` and the rest. If implement finds that the pin cannot be written without a product change, it stops with `## Clarification Needed` and does not make the change (see Veto items).
- Delete, skip, weaken or reorder an existing assertion of the class, or touch `Test/Mcp/JobFixture.cls`, `Test/Mcp/Attach.cls` or `Test/Mcp/Mock.cls`.
- Run anything on a dev slot (Rule 21).

## I/O & Edge-Case Matrix

The fixture server is `zzmcp` and the tool is `zz_delete_ticket` (risky, approved row). The room is R = `Tools.Result Room()` (40,000). L = 100,000 characters of "x" (mock mode `long`).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Replay, long answer | Replay context (Kind tool, Provenance user, ItemId the executing Ref, grant taken). Mock `long` 100000. `Proxy.Call(zzmcp, zz_delete_ticket, {"id":"T-15"}, R)`. | The answer has `text` of type string, length 100000 and outcome `cut`. `Context.ReplayRefusal()` is "". `HostData.Get("answerHash")` is "", and `Context.Current().HostData` is "". | none |
| 2 Replay, short answer | Same context. Mock `text` "T-15 deleted". | The answer is `text` "T-15 deleted", outcome `ok`. HostData is still "" (no member). | none |
| 3 Control: poll | A new context (Kind tool, Provenance untrusted, no grant). Mock `long` 100000. `Proxy.Call(zzmcp, zz_lookup, {"id":"1"}, R)`. | `HostData.Get("answerHash")` = `Test.Mcp.SourceRun Hash(L)`. This proves the observation is not vacuous. | none |
| 4 End-to-end replay | `TestReplayResultIsCut` as it is (mock `long` 100000, replay through the runner). | Everything it asserts today, plus: the Reply's `HostData` is "". | none |
| 5 Chat call | `TestProxyCut`, unchanged. | Green, as pinned by DW-1347. | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls`: `Call` L46-62 reads `approved` from `Context.ApprovedFingerprint(tool)` (L48) and answers through `Noted` (L49, L61). In `Noted` L67-78, L69 is the refusal guard (`approved` or `IsPoll`) and L70 the hash guard (`IsPoll` only). `ANSWERHASH` is at L42. `Run` L109-120 checks the live fingerprint against `approved` for a replay (L114).
- `src/bridge/cls/OcuTalon/Bridge/Context.cls`: `Begin` L75-93 sets HostData to "". `Grant` L315-337 needs an executing tool_call row. `TakeGrant` L340-353 sets the APPROVED node. `IsPoll` L194-198 is Kind tool and Provenance untrusted (a replay's Provenance is user). `ApprovedFingerprint` L359-364, `ReplayRefusal` L378-382.
- `src/bridge/cls/OcuTalon/Bridge/HostData.cls`: `Get` L25-28 answers "" when there is no member.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls`: in `Execute` L83-156, Begin and Grant are at L106-107, ExecuteTool at L117, `Context.End` at L145 and the Reply at L148-154, with no HostData. Class doc step 4 is L26-27.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` L233: the gate's `TakeGrant(native.tool, native.arguments, native.toolref)` for an MCP replay.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` L491-494: `StartExecution` (approved to executing).
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls`: header bullets L5-25 (`TestReplayResultIsCut` is on L21), `OnAfterOneTest` L49-63, `TestReplayResultIsCut` L383-398. Helpers: `Prepare` L666, `Approved` L739 (fingerprint at "Deletes a ticket.", toolref `Mcp.Attach Toolref(SERVER)`), `Fresh` L638, `Send` L753 (the replay request's fields), `Replay` L768.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/JobFixture.cls` `Setup` L122-142: the rows `zz_lookup` (read-only) and `zz_delete_ticket` (risky), and the mock with the header.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`: `Call(port, mode, value)` L144 and `Calls(port, tool)` L181. The modes `long` and `text` are at L379-380.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceRun.cls` `Hash` L821-829: the independent SHA-256 oracle that `Test/Bridge/Poll.cls` also uses.

## Tasks & Acceptance

**Task 0 (measure first, on lane C's warm throwaway, before the test is written; record each result under `## Verification`). Each item is (inference) until measured:**
1. **The in-process call works from this class.** `Test.Mcp.Proxy` measures in-process `Proxy.Call` only for its own fixture, `zzprx<n>`. After `Prepare()`, a direct `Proxy.Call(..#SERVER, "zz_delete_ticket", {"id":"T-15"})` from the test process should answer a `text`, and the mock should log one tools/call with its header matched. If it does not (for example, the credential cannot be resolved in the test process), stop with `## Clarification Needed`. Do not change the fixture or the product.
2. **The poll control passes the row check.** `Mcp.Attach Toolref(zzmcp)` should equal the spec string that `JobFixture.Setup` fingerprints its rows with, so scenario 3's call is not refused `changed`. Record the answer's outcome.
3. **The gap, observed.** On the base, apply mutation M1 (below) and run `OcuTalon.Test.Mcp.Approval:TestReplayResultIsCut` and `OcuTalon.Test.Mcp.Attach:TestProxyCut`. Both should stay green, which is the ledger's evidence. Then revert byte for byte.

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls`, new `Method TestReplayNotesNoAnswerHash()` (matrix 1-3), placed after `TestReplayResultIsCut`:
  - `If '..Prepare() Quit`. Then `ref = ..Approved("zz_delete_ticket", "{""id"":""T-15""}")`, and `Approval.StartExecution(ref)` OK.
  - Begin a request built like `Send`'s (Kind tool, Provenance user, ItemId ref, a new DecisionRef, OwnerRef `..SessionRef`, Channel system). Then `Context.Grant(ref)` OK. Then `TakeGrant("zz_delete_ticket", {"id":"T-15"}, Mcp.Attach Toolref(SERVER))` = 1.
  - Preconditions: `ApprovedFingerprint("zz_delete_ticket")` = `..Fresh(ref).ToolFingerprint` (not empty), and `Current().Kind _ "|" _ Current().Provenance` = "tool|user". Do not assert `IsPoll()` itself. Mutation M2 changes `IsPoll`, and the HostData assertions, not a precondition, must be what goes red.
  - Matrix 1: the mock answers `long` 100000. `answer = Proxy.Call(..#SERVER, "zz_delete_ticket", {"id":"T-15"}, Tools.Result Room())`. Assert type, length and outcome = "string|100000|cut", and `ReplayRefusal()` = "". Then assert `HostData.Get(##class(OcuTalon.Mcp.Proxy).#ANSWERHASH)` = "", with the message "a replay's long text answer notes no answerHash", and `Current().HostData` = "".
  - Matrix 2: the mock answers `text` "T-15 deleted". The same call gives "string|T-15 deleted|ok", and the same two HostData assertions hold ("a replay's short answer notes none either").
  - `Context.End()`. Matrix 3: begin a poll-shaped request (Kind tool, Provenance untrusted, a new ItemId, OwnerRef `..SessionRef`, Channel system) with no grant. The mock answers `long` 100000. `Proxy.Call(..#SERVER, "zz_lookup", {"id":"1"}, Room())`. Assert `HostData.Get(...ANSWERHASH)` = `##class(OcuTalon.Test.Mcp.SourceRun).Hash(L)` ("the same channel holds a poll's answerHash"). Then `Context.End()`.
  - Finally assert that `Mock.Calls(port, "zz_delete_ticket")` = 2 and `Calls(port, "zz_lookup")` = 1: each call reached the server.
- [ ] Same file, `TestReplayResultIsCut`: after the replay, add `Do $$$AssertEquals($Select($IsObject($Get(reply)): reply.HostData, 1: "no reply"), "", "the replay's Reply holds no HostData, so no answerHash")` (matrix 4). Every existing assertion stays.
- [ ] Same file, `OnAfterOneTest`: add `Do ##class(OcuTalon.Bridge.Context).End()` as its first line.
- [ ] Same file, class header: add a bullet for `TestReplayNotesNoAnswerHash` (the replay's context built as the replay and the gate build it, long and short text answers, no `answerHash`, and the poll control). Add to the `TestReplayResultIsCut` bullet: "and its Reply holds no HostData".
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Acceptance Criteria:**
1. Given the replay of an approved MCP call whose server answers a text, long or short, when the governed proxy answers, then the replay context's HostData holds no `answerHash` member and stays empty, while the same channel holds the whole answer's hash in a poll's context.
   - mutation M1 (Rule 19): widen the hash guard in `Noted` (L70) to `If ((approved '= "") || ##class(OcuTalon.Bridge.Context).IsPoll()) && (answer.%GetTypeOf("text") = "string") {`. `TestReplayNotesNoAnswerHash` goes red ("a replay's long text answer notes no answerHash", "a replay's short answer notes none either"), and is green after the revert. `TestReplayResultIsCut` and `TestProxyCut` stay green under M1. Record that too, as the evidence for the Intent's vacuity note.
   - mutation M2: `IsPoll` (Context L197) reads the Kind only (drop `&& ($Get(^||OcuTalonBP.Context("Provenance")) = "untrusted")`). `TestReplayNotesNoAnswerHash` goes red on the same HostData assertions, and is green after the revert. This is the natural second mutation: it makes every tool-kind context a poll, and only the replay pin can tell it apart, since `TestProxyCut` is a turn.
2. Given the end-to-end replay of a long answer, then its Reply holds no HostData.
   - mutation M3 (combined, the ledger's second `reopen_if`): M1, plus `Replay.Execute` carrying the context's HostData. That is `Set hostData = ##class(OcuTalon.Bridge.Context).Current().HostData` before L145 and `Set reply.HostData = hostData` after L154. `TestReplayResultIsCut` goes red on the new assertion, and is green after both are reverted. The carry alone is an equivalent mutant (the replay's HostData is empty), so it is not recorded alone.
3. The regression set passes unchanged: `OcuTalon.Test.Mcp.Approval` (whole class), `OcuTalon.Test.Mcp.Attach:TestProxyCut` and `OcuTalon.Test.Mcp.SourceRun`.

## Spec Change Log

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 11 findings - high 0, medium 0, low 7, false 4, maybe-false 0
- findings:
  - `[low]` `patch` blind-hunter: the header bullet says the replay's HostData "leaves no trace outside its context, so this is the only place that can see it", which reads against the new Reply assertion - patched: the bullet now says the Reply carries no HostData (TestReplayResultIsCut) and the proxy's note in the replay's own context is seen only here; re-ran Test.Mcp.Approval green.
  - `[false]` `reject` blind-hunter: the test hand-builds the replay context instead of running Replay.Execute - the spec's approach (Execute ends the context before the Reply, so nothing outside can observe it); Design Notes record why.
  - `[false]` `reject` blind-hunter: the second Proxy.Call runs after the grant was taken - TakeGrant sets the APPROVED node, which stays for the context; M1 turned the short-answer assertions red, which shows it was still held.
  - `[low]` `reject` blind-hunter / edge-case-hunter: Context.Begin gets no superSession or runner argument - Proxy and Noted read neither (grep of Mcp/Proxy.cls), theoretical.
  - `[low]` `reject` blind-hunter: no mutation of the poll control (M4) - the spec asks one mutation per AC and the control is observed live in Task 0 item 2 (hash equals the oracle); more would add scope (Rule 14).
  - `[low]` `reject` blind-hunter: Task 0 item 1 record is confusing (probe used zz_lookup) - the fix edits the spec's records only; the replay-shaped zz_delete_ticket call is evidenced by the real test passing.
  - `[low]` `reject` blind-hunter: other calls (model turn, non-text answer) have no test - the intent's gap is the replay; the chat call is pinned by TestProxyCut.
  - `[low]` `reject` blind-hunter: OnAfterOneTest ends the context for every test - spec-mandated (Boundaries), same as Attach.cls L155.
  - `[false]` `reject` edge-case-hunter: the APPROVED node is not re-checked before the short call - same evidence as the grant row (M1 red on the short assertions).
  - `[low]` `reject` edge-case-hunter: the poll control skips the poll map - Proxy.Call needs none (the control passed live and matches the oracle); theoretical.
  - `[false]` `reject` edge-case-hunter (claim): the Reply assertion alone does not pin the guard - correct and stated in the spec (it guards M3's carry only).
  - verification-gap: no gaps; its other notes (AC3 has no mutation, as it adds no behavior; stale Auto Run Result) need no action (the latter is rewritten at finalize).
  - intent-alignment: descriptive only; it reports reading A implemented (in-process context, spec's approach), no finding.

## Design Notes

**Why an in-process context and not the runner's replay.** The proxy decides "replay" only from `Context.ApprovedFingerprint(tool)`, and "poll" only from `Context.IsPoll()`. `Begin` + `Grant` + `TakeGrant` set exactly the nodes that `Replay.Execute` and the gate set in the runner job. Calling `Proxy.Call` directly skips the gate, `McpCall` and the proxy manager, none of which reads or writes `answerHash`. This is the only place where the replay's HostData can be observed without a product seam, because `Replay.Execute` ends the context before it builds the Reply. A seam (a probe that records the context at `End`, or a Reply that carries HostData) would be a product change. It is not needed, so there is none.

**What the pin protects.** Today a replay's HostData goes nowhere, so a widened guard would cost only a hash and change no output. The pin keeps the Proxy's documented contract ("no other call writes it"). Matrix 4 and M3 cover the day a change starts carrying a replay's HostData: then a hash written there would reach the host as a poll-only member.

**Why `Prepare()`.** It is the class's one entry point. It checks the production, makes the fixtures and the session that owns the row, and points the runner's key. Matrix 1-3 need only the fixtures. The runner restart costs a few seconds, and in exchange the test gets the same setup and clean-up as its neighbours.

**Cross-lane note (no veto row).** `Test/Mcp` is a Lane A package (AD-29). Lane C edits it under the Planner's grant for DW-1347 (ruling (b)). Lane A's hold ("stay out until DW-1347 merges") ended with merge 999138505. At plan time, after `git fetch`, no remote branch (66 refs) and no local branch has a commit past `origin/feature/OCT_OcuTalon_MVP` (9991385054) that touches `Test/Mcp/Approval.cls`. Its last change on feature is cc3c9df48 (DW-1255). Integrate re-runs the same check. The lead serializes the merge if a Lane A branch picks up the file in the meantime.

## Veto items

None. The change is tests only: no product change, no public text, no stored data and no architecture addition. The cross-lane edit of one Lane A test file is a note (Design Notes), not a veto row, because no in-flight branch edits that file. If Task 0 item 1 or 2 fails, so that a product seam would be needed, implement stops with `## Clarification Needed`, and that seam becomes a Veto item for the Planner.

## Public text

None.

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21dw1371iw`.
- Run one test class (or `Class:Method`) per foreground call, with `timeout: 600000`, each under about 3 minutes. `Test.Mcp.Approval` took 79 s at 22.6 QA. Never put two `iris_execute_tests` calls in one message.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e21dw1371iw ci/warm.sh up`, then Task 0 items 1-3.
- (loop) Warm `ci/iris.sh class OcuTalon.Test.Mcp.Approval:TestReplayNotesNoAnswerHash`: passes.
- (once) Warm, each `ci/iris.sh class <spec>`, expected to pass:
  - `OcuTalon.Test.Mcp.Approval`
  - `OcuTalon.Test.Mcp.Attach:TestProxyCut`
  - `OcuTalon.Test.Mcp.SourceRun`
- (once) `bash docker/tests/test-class-rules.sh`: exit 0.
- (once) `git diff --name-only 82e7ca18f` lists only `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls` and this spec.
- (once, at the end, also after a failure) `OCUTALON_RUN_TAG=e21dw1371iw ci/warm.sh down`.

**Mutations:** M1, M2 and M3 as under Acceptance Criteria. Record each as `mutation: <change> -> <test that went red> ("<assertion message>")`. Revert it byte for byte, check that `git status --short` and `git diff --stat` are as before, and see the method green again on the same stack.

**Task 0 records (lane C warm throwaway e21dw1371iw, HEAD 1777dbad5):**
1. In-process call works from this class. After `Prepare()`, a scratch probe method (removed before the real test) called `Mcp.Proxy.Call(zzmcp, ...)` directly: it answered `{"text":"T-15 deleted","outcome":"ok"}`, and the mock logged initialize, notifications/initialized, tools/list and one tools/call, each with auth `matched` and client `iris`. (The probe's direct call used `zz_lookup`, a plain non-replay call; the replay-shaped call of `zz_delete_ticket` with the grant taken is exercised by the real test, whose type/length/outcome assertions pass and whose mock counts 2 for it.) Decision: the probe used `zz_lookup` because a non-replay call needs the classification row, which the fixture holds for both tools; no product or fixture change was needed.
2. The poll control passes the row check. `Mcp.Attach Toolref(zzmcp)` = `mcp:remote:@{config:AI.MCP.OcuTalon_zzmcp}`, equal to the spec string `JobFixture.Setup` fingerprints its rows with. The probe's poll-context call (Kind tool, Provenance untrusted, no grant, mock `long` 100000, `zz_lookup`) answered type string, outcome `cut`, no refusal, length 100000, and HostData `answerHash` = d69e6898...e5d4, equal to `SourceRun Hash` of 100,000 "x".
3. The gap, observed. With M1 applied on the unmodified test class, `OcuTalon.Test.Mcp.Approval:TestReplayResultIsCut` passed and `OcuTalon.Test.Mcp.Attach:TestProxyCut` passed. M1 was then reverted byte for byte (cmp against the backup).

**Mutations (each reverted byte for byte, cmp equal, then the method green again on the same stack):**
- mutation: M1, `Noted` hash guard widened to `((approved '= "") || IsPoll())` -> `TestReplayNotesNoAnswerHash` red ("a replay's long text answer notes no answerHash", "and the replay's HostData stays empty", "a replay's short answer notes none either", "and the replay's HostData is still empty"). `TestReplayResultIsCut` and `TestProxyCut` stayed green under M1 (Task 0 item 3).
- mutation: M2, `Context.IsPoll` reads the Kind only -> `TestReplayNotesNoAnswerHash` red (the same four HostData assertions; "a replay's long text answer notes no answerHash", "a replay's short answer notes none either"). No precondition went red.
- mutation: M3, M1 plus `Replay.Execute` carrying the context's HostData to the Reply -> `TestReplayResultIsCut` red ("the replay's Reply holds no HostData, so no answerHash").

**Results of the final tree (warm lane C, one run per call):** `TestReplayNotesNoAnswerHash` passed; `OcuTalon.Test.Mcp.Approval` (whole class) passed (69 s); `OcuTalon.Test.Mcp.Attach:TestProxyCut` passed; `OcuTalon.Test.Mcp.SourceRun` passed; `bash docker/tests/test-class-rules.sh` exit 0; `bash docker/tests/test-boundaries.sh` exit 0.

**QA records (lane C warm throwaway e21dw1371qw, HEAD 7a4e22a9a, 2026-11-15):**
- Verdict: no test added. Every assertion of `TestReplayNotesNoAnswerHash` and the new `TestReplayResultIsCut` assertion is closed by a mutation below; a further test would duplicate one of them. Two assertions are not pinned by a mutation and are recorded as such: the `Calls` counts (2 and 1) are redundant with the answer assertions (a call that did not reach the server would fail those first), and the `OnAfterOneTest` `Context.End()` line is defensive (no passing path leaves a context, so no mutation of it can go red without first failing a test).
- Hermetic: each test starts its own mock on a new port, which `Remove` stops and forgets; the context is ended on every path by the test and again by `OnAfterOneTest`; the approved row and the session are deleted there; the `Leftovers` and secret-places assertions of `JobFixture` pass after the test. `OcuTalon.Test.Mcp.Approval` whole class run three times in a row on the same warm stack (69.3 s, 69.0 s, and 68.8 s after the mutation runs and their reverts): all passed.
- mutation: M1, `Noted` hash guard widened to `((approved '= "") || IsPoll())` -> `TestReplayNotesNoAnswerHash` red ("a replay's long text answer notes no answerHash", "and the replay's HostData stays empty", "a replay's short answer notes none either", "and the replay's HostData is still empty"); `TestReplayResultIsCut` stayed green under M1 (the vacuity of a Reply-only pin, as the Intent says). Reverted byte for byte (cmp equal), the method green again.
- mutation: M2, `Context.IsPoll` reads the Kind only -> `TestReplayNotesNoAnswerHash` red on the same four HostData assertions; no precondition went red. Reverted byte for byte (cmp equal), green again.
- mutation: M3, M1 plus `Replay.Execute` carrying the context's HostData to the Reply -> `TestReplayResultIsCut` red ("the replay's Reply holds no HostData, so no answerHash"). Both reverted byte for byte (cmp equal), green again.
- mutation: M4 (QA, the control pin), `Noted` hash guard `If 0 && (...)` (a poll's hash is never noted) -> `TestReplayNotesNoAnswerHash` red on exactly one assertion ("the same channel holds a poll's answerHash"); the replay assertions stayed green, so the control is what goes red, as intended. Reverted byte for byte (cmp equal), green again.
- Product findings: none. `git status` was clean after every revert; the stack e21dw1371qw is down (0 leftover containers, volumes, networks).

## Auto Run Result

Status: done
Blocking condition: none. No Veto item.

- Summary: `TestReplayNotesNoAnswerHash` builds the replay's context in the test process (Begin, Grant, TakeGrant), calls `Mcp.Proxy.Call` with a long and a short text answer, and asserts that no `answerHash` is noted and the HostData stays empty, with a poll-context control that holds the hash. `TestReplayResultIsCut` also asserts that the Reply holds no HostData. `OnAfterOneTest` ends a left-over context. Tests only; no product change.
- Files changed: `src/ocutalon/cls/OcuTalon/Test/Mcp/Approval.cls` (the new test, a private `BeginTool` helper that both contexts use, the Reply assertion, the `OnAfterOneTest` line, two header bullets) and this spec.
- Review: 11 findings, 1 low patched (header wording), 10 rejected with reasons in the triage log, 0 deferred. Patched by verdict: high 0, medium 0, low 1.
- Follow-up review recommendation: `false` (no high patched).
- Verification: Task 0 items 1-3 and the mutation lines M1, M2, M3 are under `## Verification`. After the last patch: `OcuTalon.Test.Mcp.Approval` passed (66 s), earlier on the same tree `TestReplayNotesNoAnswerHash`, `Attach:TestProxyCut` and `Test.Mcp.SourceRun` passed; `test-class-rules.sh` and `test-boundaries.sh` exit 0. The warm stack `e21dw1371iw` is down.
- Residual risks: the test rebuilds the replay's context by hand, so a change to how `Replay.Execute` builds it is not seen (the spec's stated trade-off). Task 0 item 1 probed `zz_lookup`, not `zz_delete_ticket`; the replay-shaped call is covered by the real test.
