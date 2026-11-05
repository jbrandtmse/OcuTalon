---
title: "Story 17.8: Only Decide moves a conversation's link"
type: 'bugfix'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-17-2-retry-once-on-a-second-model-before-falling-back.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Today three runner paths move a conversation's link before `Decide` has judged the reply: `SaveLinked` (a fresh or compacted turn), `SwitchTo` (the compaction fork) and `SaveRetried` (the retry, which reads lateness once). So a late, refused or superseded reply can still change what OcuTalon remembers of a chat (DW-729, DW-730). Separately, the retry's seed holds the first attempt's unseen exchange (DW-726).

**Approach:** Make `Decide` the one arbiter. Runners save their AI session and report it on the `Reply` (`SessionId`, `SessionFrom`, `HistoryCount`). `Decide` points the link (the compare-and-set `ConversationLink.Point`) only when it accepts a reply as the decision's answer: on time and untainted. A reply it does not accept moves nothing. `Decide` also builds the retry's seed from the stored conversation as it stood before the first attempt, and sends the retry as a fresh turn seeded with it.

## Boundaries & Constraints

**Always:**
- **The one write path.** `ConversationLink.Point` with `expected` is the only way a product class moves a link. `Decide.PointLink` is its only product caller. The adapter only reads the link (`SessionOf`) and takes the lock (`Lock`/`Unlock`).
- **When `Decide` points.** It points in `Conclude`, after the turn's `Decision` row is saved and before the answer is returned. It does so only for a linked turn (`Adapter.Agent.IsLinked`) whose reply is usable and untainted and names a saved session (`SessionId` not empty) other than `SessionFrom`. The call is `Point(OwnerRef, <first runner>, SessionId, SessionFrom)`. The first runner keys the link for both attempts.
- **What moves nothing.** A fallback, a reply after the timer (the framework discards it), a tainted reply, and a reply that `Decide` replaced with the retry. This holds for fresh, compacted, saved (continue) and retried turns alike.
- **`SessionRotated` (set by `Decide` only).** It is 1 when `PointLink` moved the link and either `SessionFrom` was not empty or the turn was `fresh`. It is 0 for a continue turn, for the first link of a continue turn, for every fallback, and when the move failed. Runners leave it 0.
- **The retry's seed (DW-726).** For a linked turn that is not `fresh`, the retry clone is sent `fresh`, with `SeedText` = `Compaction.Seed` of the first `HistoryCount` stored messages of the session that the first runner's link names. Those are the messages the first attempt began with; all of them when there is no first reply or no count. The turn's input follows (`ChatInput`). Nothing the first attempt produced goes in. A `fresh` turn keeps its own `SeedText`.
- **Saving.** Runners save after a completed, untainted Chat, late or not (Conventions "Saved conversations"). A continue turn still saves into the session it opened. A retry that already knows it is late (`RetryIsLate`) saves nothing, as in 17.2.
- **Lane and storage rules.**
  - Storage is append-only (AD-5): `Reply` gains three properties at slots 11-13. No `Request` property is added: the guide check names every `Request` property, and `Reply`'s own are not checked.
  - The bridge names no OcuTalon package (AD-2). Source is ASCII, and comments state the contract (Rule 14).
- **Tests** use the CI mock only, in lane A throwaways.

**Never:**
- A runner calling `Point`, or `Decide` pointing for a reply it did not accept.
- A new `Request` property, any edit to `Bridge/Msg/Enum.cls` or `Bridge/Ext/**`, a mock scenario change, or a `ci/units.sh` edit.
- Spine edits (the lead's job, Rule 20).
- `docs/bridge-guide.md` before the lead records the Planner's approval of the text under Design Notes.
- DW-483 (a same-model retry), or a change to purge logic, `Reconcile`, `Redact`, `KeyProof` or `list_productions` (Story 30.7).
- Any destructive run on `ocutalon-slot-a`, a real provider, or a real key.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Accepted fresh turn | Link S1; `fresh` turn, usable on time | The runner saves S2 and the link stays S1 until `Conclude`, which points it to S2. `SessionRotated` 1 | none |
| Accepted continue turn | Link S1; continue | Saved into S1 in place (`SessionId`=`SessionFrom`=S1): no `Point`, `SessionRotated` 0 | none |
| First link | No link; continue / `fresh` | `PointLink` with expected "" creates the link; `SessionRotated` 0 / 1 | none |
| Accepted compaction | Link S1; flagged; fork F (or the seeded fallback session) | `SwitchTo` saves and reopens F and points nothing; `Conclude` points to F. `SessionRotated` 1 | none |
| Accepted retry | Link S1; first attempt refused | The retry saves S2; `Conclude` points to S2; `SessionRotated` 1 | none |
| Fallback (any type) | A refused, empty or cut-off reply, a precheck refusal or a timer | The link is unchanged and `SessionRotated` 0; a session the runner saved stays unlinked (purged after a day, AD-27) | fallback |
| Late first attempt, no retry (DW-730) | `fresh` or compacted turn; the timer fires; the runner finishes late | Timeout fallback; the late runner saves its session; the link still names S1 | fallback |
| Race (DW-729) | Retry finishes after T2, before `Decide` handles its timer (no `Decision` row yet) | The retry saves S2 and points nothing; the timer's fallback is recorded; the link still names S1 | fallback |
| Tainted | Usable reply, `Tainted` 1 | Nothing saved, link unchanged, `SessionRotated` 0 | none |
| Lost compare-and-set | The link no longer names `SessionFrom` | No move, one warning naming the DecisionRef; the answer stands with `SessionRotated` 0 | warning |
| Point error | The link row is locked by another process | One warning; the answer stands with `SessionRotated` 0 | warning |
| Retry seed (DW-726) | S1=[u1,a1]; the first attempt (continue) is refused and saves [u2,refusal] into S1 (`HistoryCount` 2) | The retry's one user message is `Seed([u1,a1])`, a blank line, then u2's input. No refusal text; u2 appears once | none |
| Seed, no cut | The first attempt compacted, saved nothing, or was never sent (`no_key`) | The seed is the whole stored S1 | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`
  - Class doc: :24-35 (the line "Decide never changes the conversation link; it only reads it" at :34-35), :95-97 (SessionBroken), :98-112 (the retry).
  - `OnResponse` :362, which calls `Conclude` at :403. `RetryRequest` :453 and `SentRequest` :442.
  - `TryRetry` :616, which builds the clone at :638 and :647.
  - `EstimateTokens` :1163, with the `retryOf` history branch at :1173-1176. `Precheck` :1101 passes `retryOf`.
  - `Conclude` :1281: `Record` at :1334, and the turn answer cloned from the reply at :1337-1345.
  - `RecordFallback` :1496, which copies the runner's `SessionRotated` at :1519-1523 (doc :1491-1494). `RunnerFor` :778.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`
  - Class doc :22-51. `Expected` :89-91.
  - `AnswerLinked` :411: `Expected` read :423, the fork sets `SessionRotated` :440, `SaveLinked` call :442.
  - `AnswerRetried` :462: the seed :467-471, `SaveRetried` :474.
  - `SaveRetried` :488 (`Point` :494). `RetryIsLate` :509. `SaveLinked` :568-587 (`Point` :579).
  - `Compact` doc :589-597. `SwitchTo` :714-736 (`Point`/`moved` :731-734). `ChatInput` :828 (`seeded` 1 sends `SeedText`).
- `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`: `SessionRotated` doc :17-20; storage slots 1-10. Not contended.
- `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`: class doc :1-16 ("only the runner writes it"); `Point` doc :43-53. The code is unchanged.
- `src/bridge/cls/OcuTalon/Bridge/RequestSize.cls`: `StoredMessages(sessionId)` :86, the sibling `HistoryChars` :69.
- `src/bridge/cls/OcuTalon/Bridge/Purge.cls`: class doc :5-10 ("it points a link at a session right after it saves it"). Doc only.
- `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`: `Seed(context)`. Read only.
- Other callers of the link, and what happens to each:
  - `Bridge.Purge`: one `SELECT`; it writes nothing and stays so.
  - Lane B `Conversation`: it never names the class. Its `SessionBroken` retry is a fresh `Decide` request, so `Decide` links it on acceptance.
  - `OpenSession`: it reads no link.
  - Test fixtures: they call `Point` (both forms) and `DELETE`; tests are allowed to.
- Tests (all in existing classes, so no `ci/units.sh` change):
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls`:
    - helpers `Send` :1269, `NewTurn` :1249, `LinkOf` :1324, `RunLate` :177, `WaitLate` :191, `NewStoredSession` :574;
    - the 17.2 tests `TestRetriedContinueTurn` :207, `TestRetriedFreshTurn` :276, `TestRetriedPointFailureKeepsTheReply` :427 and `TestRetryMovesTheLinkOnlyWhenOnTime` :454 (`RecordDecision` :499, `UsageRowsOf` :514);
    - also `TestFirstAndNextTurn` :141, `TestFresh` :772, `TestFreshFailsOrTainted` :820, `TestSaveProblem` :1082 and `TestQuarantineAfterTaint` :704.
  - `Test/Bridge/Compaction.cls`: `TestGuardedCompaction` :73, `Go` :618, `TestAfterTheSwitch` :309.
  - `Test/Bridge/Decide.cls`: `TestTurnKeepsReply` :1132, `TestConcludeFallbacks` :1476, `TestFallbackCarriesRotation` :3040, `TestRetryWiring` :3260, `TestRetryAfterTimer` :3449, `TestEstimateTokens` :1845, `NewSession(chars)` :3725, `StartHolder` :3848.
  - `Test/Bridge/SecondModel.cls`: `TestRetriedTurnKeepsTheConversation` :299. It asserts today that the seed holds "The CI mock refuses this request.", which is DW-726. Also `TestIntegrationWebChat` :433, and the helpers `UseTimer` :533, `Arm` :547, `WaitLate` :562, `Prepare` :493.
  - `Test/Bridge/CodeRules.cls` `TestOnlyTheRunnerWritesLinks` :501-566 (doc :40-45).
  - `Test/Bridge/Contracts.cls`: the `Reply` map at :181.
  - `Test/Bridge/ZzRetryAdapter.cls` `SaveLinked` override :28. `Test/Bridge/Runner.cls` `NewRunner` :1249.
  - Contended, Epic 39:
    - `Test/Eval/ThinkingSmoke.cls` drives three linked turns straight through `ZzSmokeRunner.OnMessage`, with no `Decide`. It asserts that turn 3 is rotated and that the linked session starts with the summary.
    - `Test/Eval/ZzSmokeRunner.cls` is 7 lines: `Extends AgentRunner` plus the `ADAPTER` parameter.
    - `Test/Eval/Run.cls` `TestTurnSessions` expects `SessionRotated` on 5 fresh eval turns through `Decide`. It is unchanged if all 5 are accepted.
- Mock scenarios reused, unchanged: `retry-chat` (a refusal, then text) and `retry-chat-held` (text after 20 s, then text).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure, warm throwaway `e17s8iw`, CI mock). For one opened linked session, check that `MessageCount()`, `GetContext().%Size()` and `RequestSize.StoredMessages(id).%Size()` agree before Chat. After a continue turn refused through `retry-chat` (armed 1) and saved in place, check that `StoredMessages` holds N+k and that its first N equal the pre-Chat messages. Record N, k and the method chosen under Design Notes. If the counts disagree, stop with `## Clarification Needed`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`:
  - add `SessionId` (MAXLEN 128): the AI session this turn saved, "" when none;
  - add `SessionFrom` (MAXLEN 128): the session the link named when the runner began, "" for none;
  - add `HistoryCount` (`%Integer`): the messages that session held when it was opened, before compaction and Chat, "" when not opened;
  - append the storage slots;
  - rewrite the `SessionRotated` doc as the Always rule says.
- [ ] `src/bridge/cls/OcuTalon/Bridge/RequestSize.cls`: extend `StoredMessages(sessionId, count = "")` so that a whole-number count returns the first `count` messages. Extend; do not copy.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `AnswerLinked` fills `SessionFrom` (= `Expected`, the link read at the start) and `HistoryCount` (per Task 0) on the reply. It drops the fork's `SessionRotated`.
  - `SaveLinked` saves the session and sets `SessionId` on success. It makes no `Point` and sets no `SessionRotated`. Its warning stays, and its signature may drop `fresh`.
  - `SwitchTo` saves the fork, releases and reopens it, and points nothing (the `moved` branch goes). `Expected` keeps the original link value.
  - `AnswerRetried` seeds with `ChatInput(request, 1)`, that is, the request's `SeedText`, which `Decide` built. It reads no stored history. It sets `SessionFrom` = `SessionOf(OwnerRef, RetryOf)`.
  - `SaveRetried` saves, unless `RetryIsLate`, and sets `SessionId`; it makes no `Point`.
  - Rewrite the class doc, `Expected` and the `Compact`/`SwitchTo` docs.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - Add `PointLink(request, runner, reply, Output rotated) As %Status` per Always. It warns on an error or a lost compare-and-set.
  - `Conclude` gets an optional `runner` (the link's agent; default `RunnerFor`). After `Record` saves a turn's row, it calls `PointLink`. The answer's `SessionRotated` is `rotated`, and the answer clears `SessionId`, `SessionFrom` and `HistoryCount`.
  - `OnResponse` passes `runner`.
  - `RecordFallback` leaves `SessionRotated` 0.
  - `RetryRequest(request, decisionRef, estimate, runner, reply = "")`: for a linked turn that is not `fresh`, the clone is `fresh` with `SeedText` = the new `RetrySeed(request, runner, reply)`. `TryRetry` passes the first attempt's reply and builds the seed once.
  - `EstimateTokens` drops the `retryOf` history branch (the clone now carries its seed), along with the argument where it becomes unused.
  - Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`: doc only. `Decide.PointLink` is the only product caller of `Point` (the compare-and-set). The unconditional form has no product caller and is kept for test fixtures. The adapter reads the link and locks it.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Purge.cls`: doc only.
  - A saved session is named when `Decide` accepts its turn, within the decision's 110 s.
  - A session whose reply was not accepted stays unnamed and is deleted after a day.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`: add one helper, `Accept(request, reply, runner = "ZzRunner")`. It calls `Decide.PointLink` and sets `reply.SessionRotated`, as `Decide`'s answer would. The shadow-runner tests model an accepted reply with it.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls`:
  - `Send` accepts by default (an `accept` argument, 1). Adapt the tests that expect links (Code Map); each asserts the link before acceptance (unchanged) and after it.
  - `TestRetryMovesTheLinkOnlyWhenOnTime`, `TestRetriedContinueTurn` and the late-retry cost assertion keep every assertion; the on-time move is now checked after `Accept`.
  - Move `TestRetriedPointFailureKeepsTheReply` to the `Decide` test below.
  - Add `TestBusyDecideMovesNothing` (DW-729): a retry with no `Decision` row yet answers and saves S2, and the link stays S1. Then the timer fallback is recorded (`RecordFallback` for that DecisionRef), and the link stays S1.
  - Add `TestLateFreshTurnMovesNothing` (DW-730, in process): a `fresh` turn saves S2 and leaves the link on S1; then its timer fallback is recorded.
  - Add `TestRetrySeedHoldsNoFirstAttempt` (DW-726), per the matrix row, with `retry-chat` armed 1. The first reply's `HistoryCount` goes to `RetryRequest`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Compaction.cls`:
  - `Go` accepts by default; adapt `TestGuardedCompaction`, `TestAfterTheSwitch` and the rest.
  - Add `TestLateCompactionMovesNothing` (DW-730, compacted): after the compacted turn the link names S1, `SessionId` is F and `SessionFrom` is S1. After the timer fallback the link is still S1, and the next accepted turn opens S1.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:
  - Add `TestPointLink`, covering the matrix rows accepted fresh, accepted continue, first link, tainted, lost compare-and-set and Point error.
  - Add `TestConcludeAccepts`: through `Conclude` and the `ZzDecide` `OnResponse` path, a usable reply moves the link, a refused one does not, and the answer carries no session fields.
  - Rewrite `TestFallbackCarriesRotation` as `TestFallbackMovesNothing`. Adapt `TestTurnKeepsReply` and `TestConcludeFallbacks`/`AssertFallback`.
  - Extend `TestRetryWiring`: the clone of a linked continue turn is `fresh`, with the seed of the first `HistoryCount` messages.
  - Update the `TestEstimateTokens` retry cases.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/SecondModel.cls`:
  - In `TestRetriedTurnKeepsTheConversation` (and `TestIntegrationWebChat` where it asserts the seed), the retry's seed is the stored first exchange only, and neither the seed nor the next turn holds "The CI mock refuses this request."
  - Add `TestLateFreshTurnMovesNothing` (live, DW-730), with no `RetryItem` and `UseTimer(12)`. On an owner whose link is S1, a `fresh` turn with `retry-chat-held` armed 1 takes the timeout fallback. After `WaitLate`, the link still names S1, and the next turn's logged history is S1's without the late exchange.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:
  - Rename the test to `TestOnlyDecideWritesLinks`.
  - `Decide` calls `Lock`, `Unlock`, `SessionOf` and `Point`, with `Point` in one place. The adapter calls `SessionOf`, `Lock` and `Unlock`, and never `Point`.
  - Update the doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`: add the three `Reply` properties. `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzRetryAdapter.cls`: follow the `SaveLinked` signature.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Eval/ZzSmokeRunner.cls` (contended with Epic 39; the append rule): add one self-contained `OnMessage` override as the class's last member. It calls `##super` and then, for an answered linked turn, calls `Test.Bridge.Runner.Accept`, as `Decide` accepts each on-time smoke turn. Report it in the closing summary. Make no other edit under `Test/Eval/**`; anything more needs `## Clarification Needed`.
- [ ] Rule 19 search: find every test that drives a runner directly (`OnMessage` or `Answer` on a shadow host) and asserts a link or `SessionRotated` (for example `Test.Bridge.Gate` `LinkRows`, `Test.Bridge.Runner`, `Test.Agent.*`). Adapt it through `Accept`. A contended file other than the one above is `## Clarification Needed`.
- [ ] [GATED, U-286: only after the lead records the Planner's approval of the text under Design Notes] `docs/bridge-guide.md`: replace the last paragraph of "## Second-model retry" with the approved text, verbatim, and change nothing else (contended with Epic 40).

**Acceptance Criteria:**
- Given a linked turn whose reply `Decide` accepts, on time and untainted (fresh, compacted, saved or retried), when `Conclude` records it, then `Decide.PointLink` points the link at that reply's session through the compare-and-set `Point`, and the runner moved nothing before that (the link is asserted unchanged between the runner's reply and acceptance).
- Given a reply `Decide` does not accept (a fallback, late, superseded, tainted), when it arrives, then its cost is counted and the link keeps naming the session it named.
  - The race: a retry finishing after T2 while `Decide` is busy leaves the link unchanged (DW-729).
  - A late first attempt with no retry, on a fresh and on a compacted turn, leaves it unchanged (DW-730).
  - Story 17.2's DW-725 tests still pass.
- Given a second-model retry of a linked continue turn whose first attempt saved its exchange, when the retry's seed is built, then it holds only the messages the first attempt began with, and the current input follows once (DW-726).
- Given CodeRules, when it scans the product classes, then `Decide` is the only caller of `Point`, and in one place.
- Given `docs/bridge-guide.md`, when the story is pushed, then the section says only what the code does (the gated text, once approved).

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-6: the link, the lock, the retry bullet and its 17.8 amendment.
- AD-8: the retried reasons; "A late reply moves nothing"; "One arbiter moves the link".
- AD-5: append-only storage; the 110 s timer.
- AD-20: one decision, and cost counted for late replies.
- AD-27: unlinked sessions are purged.
- AD-2: the bridge names no OcuTalon package.
- AD-29/AD-33: Lane A owns `ConversationLink`, `Decide` and the runner.
- Conventions: "Retried turns", "Saved conversations" and "SessionBroken retry".

No AC contradicts an AD's Rule: AD-6's and AD-8's 17.8 amendments state this story's rule explicitly. Older sentences that the amendments supersede are listed for the lead below.

**Ledger (Rule 17):**
- DW-729 is addressed by `PointLink`, the removal of `SaveRetried`'s `Point`, the Race row and `TestBusyDecideMovesNothing`.
- DW-730 is addressed by the removal of `SaveLinked`'s and `SwitchTo`'s `Point` and by `TestLateFreshTurnMovesNothing` (live and in process) and `TestLateCompactionMovesNothing`.
- DW-726 is addressed by `RetrySeed`/`HistoryCount`, the Retry seed rows, `TestRetrySeedHoldsNoFirstAttempt` and the updated live assertion.

**How `Decide` learns the session (design choice, AD-5).** Three new `Reply` properties:
- `SessionId` is the saved session to point at.
- `SessionFrom` is the compare-and-set's expected value: the link the runner began from, so a stale attempt never overwrites a newer link.
- `HistoryCount` is the seed's cut.

`Reply` is a message class: append-only slots, not contended, and outside the guide's reference rule (`test-bridge-guide.sh` lists `Request`, `Result`, `DecisionResponse` and `AgentStep`). A `Request` property would have forced new public guide text. So `Decide` passes the seed in the clone's existing `SeedText` and sends the retry as `fresh`, which is exactly what a fresh turn means: a new AI session seeded with a code-written recap.

**Decided in-stage:**
1. The fields above. The seed is built by `Decide` (`RetrySeed`); the runner no longer reads the first runner's history.
2. The `SessionRotated` rule, which keeps today's meaning for every consumer: `Test.Agent.Conversation`'s first turn 0, `Test.Eval.Run`'s fresh turns 1, `ThinkingSmoke`'s turn 3 1. No product class outside the bridge reads it.
3. Fallbacks carry `SessionRotated` 0, because nothing moved.
4. `RetryIsLate` stays as a save-skip for a retry that already knows it is late. It never decides the link, and it keeps 17.2's "saved no AI session" assertion.
5. The unconditional `Point` form stays, with no product caller, for test fixtures.
6. `Decide` points after the row and before the answer, so the caller's next turn opens the moved link. A failure is a warning, never an error status.
7. A new conversation's first link is created by `Decide` on acceptance. A first turn that falls back leaves no link, and the next turn starts afresh.
8. Pinning tests:
   - The compacted late case is pinned in process (a live compaction that is also late needs a long scenario).
   - The fresh late case is pinned live and in process.
   - The race is pinned in process (its timing is not deterministic live).
9. Test placement: existing classes in shards `lane-a@Bridge` and `@rest`.
10. Shadow tests model `Decide`'s acceptance through one helper (`Test.Bridge.Runner.Accept`).

**Residual risks:**
- A continue turn still saves into its open session late or not (Conventions "Saved conversations"). So a late or refused continue reply's exchange stays in S1 when no retry replaces it, as in release 1.
- Two concurrent linked requests for one conversation from a caller other than `Conversation` (which serializes its turns) can start from the old session in the window between a runner's lock release and `Decide`'s `Point`. The later one's compare-and-set then fails with a warning.

**Footprint (Rule 11):**
- Extensions, not contended: `Bridge/Msg/Reply.cls`, `Bridge/Data/ConversationLink.cls` (doc), `Bridge/RequestSize.cls`, `Bridge/Purge.cls` (doc).
- Contended, append rule: `Test/Eval/ZzSmokeRunner.cls` (Epic 39).
- Contended, gated: `docs/bridge-guide.md` (Epic 40).
- Not touched: `Bridge/Msg/Enum.cls`, `Bridge/Ext/**`, `ci/units.sh`, `src/short-names.tsv`, the spine, Lane B classes.
- Story 30.7: this story edits only the doc comment of `Bridge/Purge.cls`'s session rule; no purge logic.

**Extend, don't copy (Rule 2):**
- `StoredMessages` gains `count`.
- `RetrySeed` reuses `Compaction.Seed` and `StoredMessages`.
- `PointLink` reuses `Point`.
- The shadow acceptance is one helper, beside `NewRunner`.

**Integration ACs (Rule 1).** The consumer `Conversation` (through `WebChatIn`, `SecondModel` `TestIntegrationWebChat`) gets an accepted retry. The user's next message is answered from the retry's session, with no first-attempt content. Consumes: 17.2's retry path, `ConversationLink.Point`, `Compaction.Seed`, `RequestSize.StoredMessages`. Consumed-by: 17.3/17.4 (the retry runners they configure inherit the arbiter); 30.7 (the purge reads links that only `Decide` writes).

**Proposed guide text (for the Planner, U-286; the gated task applies it only once approved).** The last sentence of the current paragraph becomes untrue: no "later writers" move the link any more. "Seeded from the stored conversation" also needs the DW-726 precision. The replacement, verbatim:

> A retried turn of a conversation that the bridge saves runs without the conversation lock, in a new AI session. `Decide` seeds it with a code-written recap of the stored conversation as it stood before the turn (or with `SeedText` when the turn starts fresh), and the turn's input follows; nothing that the first attempt produced goes in. Only `Decide` moves a conversation to another AI session, and only when it accepts a reply as the decision's answer: a reply that reached it within its timer, is usable and is not tainted. A reply that `Decide` does not accept, the first attempt's or the retry's, moves nothing: the conversation stays in the AI session it was in.

**For the lead: spine conformance (Rule 20; the spine is contended, so it is not edited here).** These sentences predate the 17.8 amendments and now read stale:
- AD-6 "Conversation link":
  - "Only the runner writes it" should read "Only `Decide` writes it, on accepting a reply".
  - "The runner rotates the link to a fresh AI session when ..." should read "The runner starts a fresh AI session when ...; `Decide` points the link at it on accepting the reply".
- Conventions "Saved conversations", second sentence: the retry's session is linked by `Decide`; no attempt points the link.
- Conventions "Retried turns":
  - "after a completed, untainted Chat the retry runner saves its session and points the first runner's link at it" should read "... saves its session; `Decide` points the link on accepting the reply".
  - The `Point` sentence: the compare-and-set is `Decide`'s.
  - The seed: `Decide` builds it from the messages the first attempt began with and sends the retry `fresh`.
- `epic-17-context.md` follows at the next pre-warm.

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`. Tags: `e17s8iw` (warm) and `e17s8i` (fresh); QA and review use theirs. Run one call each, in the foreground, with `timeout: 600000`; run `ci/warm.sh down` at the end, also after a failure. Compile checks on `ocutalon-slot-a` use `iris_doc_load` only (`server`/`namespace` `OCUTALON`).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s8iw ci/warm.sh up`. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s8iw ci/iris.sh class <C>`, one per call. Expected: `CLASS <C> passed` for `OcuTalon.Test.Bridge.` `Conversation`, `Decide`, `Compaction`, `SecondModel`, `CodeRules`, `Contracts`, `Gate`, `Runner`, `Link`, `Purge`, and for `OcuTalon.Test.Eval.ThinkingSmoke`.
- (once) The same, for the consumers that must stay green unedited: `OcuTalon.Test.Agent.Conversation`, `Agent.Compaction`, `Agent.Decide`, `Agent.RequestSize`, `OcuTalon.Test.Eval.Run`, `OcuTalon.Test.Checks.Turns`, `OcuTalon.Test.Core.ConversationTurns`. A red in a contended class is `## Clarification Needed`, never an edit.
- (once) `bash docker/tests/test-storage.sh`, then `test-class-rules.sh`, `test-boundaries.sh` and `test-bridge-guide.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s8i ci/iris.sh shard lane-a@Bridge`, then `shard lane-a@rest`, each in its own call; use `--part k/2` when a call nears 8 minutes. Then `ci/iris.sh teardown`. Expected: every class passes.

**Shared surfaces:**
- the `Reply` contract (`Test.Bridge.Contracts`);
- the link-writer rule (`CodeRules`);
- `SessionRotated` (`Test.Agent.Conversation`, `Agent.Compaction`, `Test.Eval.Run`, `ThinkingSmoke`);
- link rows and saved AI sessions (each test deletes its own: `DropSince`, `DELETE ... ConversationLink`).

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19), each applied to one file, observed red, and restored byte for byte (`md5`, `git status --short` unchanged):**
- `Conclude` skips `PointLink` -> `Bridge.Decide` `TestConcludeAccepts` red (and live `SecondModel` `TestRetriedTurnKeepsTheConversation`).
- `SaveLinked` calls `Point` again -> `Bridge.Conversation` `TestLateFreshTurnMovesNothing` and `CodeRules` `TestOnlyDecideWritesLinks` red; live `SecondModel` `TestLateFreshTurnMovesNothing` red.
- `SaveRetried` points when not `RetryIsLate` (17.2's line) -> `Bridge.Conversation` `TestBusyDecideMovesNothing` red.
- `SwitchTo` points the fork -> `Bridge.Compaction` `TestLateCompactionMovesNothing` red.
- `PointLink` passes no `expected` -> `Bridge.Decide` `TestPointLink` (the lost compare-and-set case) red.
- `rotated` = `moved` -> `TestPointLink` (the first link of a continue turn) red.
- `RetrySeed` ignores the count -> `Bridge.Conversation` `TestRetrySeedHoldsNoFirstAttempt` and live `TestRetriedTurnKeepsTheConversation` red; `TryRetry` passes "" as the reply -> `Bridge.Decide` `TestRetryWiring` red.
- 17.2's: `RetryIsLate` always 1 -> `TestRetryMovesTheLinkOnlyWhenOnTime` red. Restored, the three DW-725 tests pass.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned; halted after planning as directed. The lead has two gates before the implement stage:
- The guide paragraph under Design Notes ("Proposed guide text") needs the Planner's approval (U-286). Until then the guide task stays gated.
- The `Test/Eval/ZzSmokeRunner.cls` append block (contended with Epic 39, under the project block's append rule) is reported here for the orchestrator.
