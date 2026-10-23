---
title: 'Story 1.8: Conversations survive restarts'
type: 'feature'
created: '2026-10-23'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-3, AD-5, AD-6, AD-7, AD-8, AD-9, AD-10 rule 3 and 3a, AD-20, AD-22, AD-26, AD-30, AD-31 and AD-33, the AI Hub Capability Map row "Persistent conversations", and the Redaction, Logging and errors and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:**
- **Every turn starts from nothing.** The runner's `Answer` chats in a throwaway AI session for every request (`Adapter/Agent.cls:249`). No session is ever saved, `OcuTalon.Bridge.Data.ConversationLink` (Epic 0) is never written, and a user's second turn carries none of the first. A restart cannot lose a conversation that was never kept.
- **The conversation flags are never set.** `Reply.Busy`, `SessionRotated` and `SessionBroken` exist (Story 0.4). Nothing sets them, and `SessionMode`, `SeedText` and `SystemNote` are never read. `Invalid input` is classified `error` and goes no further (Story 1.6's decision 1).
- **Story 1.7 left two questions for this story** (its Consumed-by):
  - a re-sent turn must reopen its linked session;
  - the late `Chat` of a timed-out turn would save its session, and its taint is not on the fallback `Reply`.

**Approach:**
- **User turns are linked.** For a `turn` with provenance `user`, the runner holds the conversation lock and opens the session that the link names, or creates and links one. It saves the session only after a completed `Chat` that is not tainted, and opens it with the composed config every time. Every other request keeps its throwaway session.
- **Fresh turns rotate.** `SessionMode` `fresh` rotates the link to a new session seeded with `SeedText`. `SystemNote` travels before the input.
- **Decide answers the conversation states.** It refuses a turn whose lock stays held for 2 seconds with a `Busy` reply, and it flags `Invalid input` on a user turn as `SessionBroken`.
- **Sessions live where AD-3 puts them.** They and the links are in the private database, so the conversation survives a production restart.

## Boundaries & Constraints

**Always:**
- **Which requests are linked (AD-6, AD-10).**
  - Only a `turn` with provenance `user` is linked, under the key (`OwnerRef`, the runner item's name: `ChatAgent` in OcuTalon, `..BusinessHost.%ConfigName` in the adapter).
  - `decide`, `diagnose` and an untrusted `turn` keep today's throwaway session, which is never saved or linked. `tool` stays "not implemented" (`Answer`, :239).
- **`ConversationLink` (AD-6, AD-33).** No property, index or Storage change. It gains:
  - `SessionOf(ownerRef, agent) As %String`: the linked session id, or "".
  - `Point(ownerRef, agent, sessionId) As %Status`: creates the row or updates its `SessionId`. It is the only writer.
  - `Lock(ownerRef, agent, seconds As %Integer = {..#LOCKSECONDS}) As %Boolean` and `Unlock(ownerRef, agent)`: an incremental `LOCK +` / `LOCK -` of `^OcuTalonBP.Conv(ownerRef, agent)`. `LOCKSECONDS` is 2. The unlock is immediate and runs outside any transaction.
  - **Who uses them.** The adapter is the only caller of `Point` and `SessionOf`. The adapter and `Decide` are the only callers of `Lock` and `Unlock`. No other product class names the link class.
- **A linked turn in the runner (AD-6, AD-7, AD-9, AD-10).** `Answer` runs these steps in order:
  1. **Refusals.** The existing refusals stay. A linked turn with an empty `OwnerRef` is also refused with an error that names `OwnerRef`. Nothing is sent and no lock is taken.
  2. **The lock.** `Lock(OwnerRef, agent)` waits `LOCKSECONDS`. When it is not taken, the reply is `Reply.NewBusy()` with status OK, and nothing else happens: no `Chat`, no `Usage` row and no steps.
  3. **The session.** A turn with `SessionMode` `fresh`, or one with no link, gets `NewSession`. Any other turn gets `OpenSession(SessionOf(...))`, which composes the config as for a new session (Story 1.2). A failure keeps its error status, as `NewSession`'s does today.
  4. **The input.** `Chat` gets `ChatInput(request, seeded)`, where `seeded` is 1 for a linked `fresh` turn.
  5. **The call.** `Chat`, the steps, the `Usage` row and `ToolsRun` work as today.
  6. **Saving.** After a completed `Chat` whose context is not tainted, the runner `%Save`s the session, then `Point`s the link at its id. `SessionRotated` is 1 exactly when the turn was `fresh` and the link now names its new session, whether `Point` created the link or moved it; it is 0 for every `continue` turn.
     - **Nothing is saved** after a `Chat` that threw, or a tainted one, and the link stays as it was.
     - **A save or `Point` problem** is one warning that names the runner, the `OwnerRef` and the `DecisionRef`. It never changes the reply, and `SessionRotated` is then 0.
  7. **On every path,** exceptions included, the runner:
     - clears the agent's `Session` and every reference that the adapter holds to the AI session, so the next request opens it from the database;
     - then releases the lock;
     - then ends the context.
- **`ChatInput(request, seeded As %Boolean) As %String` (pure).** It joins the non-empty parts below with `$Char(10, 10)`, in this order, for every request:
  - `SeedText`, only when `seeded`;
  - `SystemNote`;
  - `Input`.

  Untrusted and throwaway requests normally carry neither, so their input stays `Input`. A continue turn ignores `SeedText`.
- **The first step's estimate (AD-9).** `BaseChars` counts `ChatInput`'s length, not `Input`'s. For an opened session it adds the length of `session.GetContext().%ToJSON()`, read before `Chat` and outside every callback.
- **`Decide` (AD-6, AD-8, AD-20, AD-30).**
  - **Busy.**
    - **The probe.** For a `turn` with provenance `user`, after `CheckSettings` and before the `DecisionRef` and the precheck, `Decide` takes `ConversationLink.Lock(OwnerRef, RunnerFor("turn"))` and at once `Unlock`s it.
    - **The refusal.** When the lock is not taken in `LOCKSECONDS`, the answer is `Reply.NewBusy()`, and nothing else happens: no `Decision` row, no `decision.recorded`, no timer, no runner request and no steps.
    - **The runner's refusal.** A runner `Reply` with `Busy` 1 (the key `reply`) is answered the same way.
    - **What Busy never is:** an error status, a fallback or a row.
    - **The exemption.** Untrusted turns, `decide` and `diagnose` are never probed.
  - **SessionBroken.**
    - **The text.** The new parameter `INVALIDINPUTTEXT` is `Invalid input`, sourced from the provider text that Story 0.11 measured for a 400 (`... error: Invalid input: <msg>`). It is matched without regard to case.
    - **The flag.** A `turn` with provenance `user` whose failure text holds it gets a fallback `Reply` with `SessionBroken` 1. The reason stays `error`, so `Classify` does not change.
    - **Where it is never set:** on untrusted turns, `decide` and `diagnose`.
  - **Carried flags.**
    - **A fallback `Reply`** carries the runner's `SessionRotated`, as it carries `Tainted` and `ToolsRun` (`RecordFallback`, :724-727).
    - **A fallback with no runner reply** (a precheck or the timer) sets none.
    - **A usable answer** is a clone of the runner's reply and keeps all of them.
  - **SessionMode.** `Admit` refuses a `SessionMode` other than "", `continue` and `fresh` (`Request.#SESSIONMODES`), naming `SessionMode`. "" means `continue`.
  - **No other change** to `Classify`, the timer, the re-send or the totals. A re-sent turn's runner reopens the linked session, which a failed `Chat` never saved, and `Resend` takes no lock probe.
- **Storage and the private database (AD-3, AD-5).** No class changes a property, an index or a Storage block. `^AI.Agent.Session*` and `^OcuTalonBP.*` already map to OCUTALON_PRIVATE (`docker/merge.cpf:13`, `Install.Step.PrivateData`), and this story adds no mapping.
- **The bridge boundary (AD-2).** Nothing in `src/bridge/` names another OcuTalon package.
- **Logs and text.**
  - A Busy refusal logs no warning.
  - Every new warning is Type 3 and passes `Redact.Text`.
  - All text in `src/`, `ci/` and `release/` is ASCII.
- **Tests.**
  - **Where they go.** `OcuTalon.Test.Bridge` and `.Agent`, in the `lane-a` shard. The new classes join existing areas, so `ci/units.sh` does not change.
  - **One owner per conversation.** Every test user turn has its own `OwnerRef` (a new Ref), unless the test is about one conversation, which then uses its own Ref for all its turns.
  - **Every test puts back what it changed:**
    - the AI sessions saved since it began and the links that name them;
    - its `Decision`, `Usage` and `AgentStep` rows;
    - its System Default Settings rows (`Decide`'s `TimerSeconds` and `ChatAgent`'s `Effort`), restarting the item it changed;
    - its armed countdowns.
  - **Locks.** A test that holds a conversation lock releases it on every path.
  - **The restart test** waits until every item runs again (`Install.Step.Production.Start`) before it acts.

**Never:**
- **Story 1.9:** no `too_large`, and `EstimateTokens` does not count the history.
- **Story 30.1:** no compaction, no `ForkAndSummarize`, no `Summarize`, and no compaction flag.
- **Story 30.2:** no purge. A session that a rotation leaves behind stays until that story's purge.
- **No repair in place:** no `SetMessage`, `InsertMessage`, `RemoveMessage`, `RewindTo`, `Reset` or `ResetContext` on any session.
- **Saving and linking:**
  - no save after a failed or a tainted `Chat`;
  - no link for anything but a user turn;
  - no session object kept from one request to the next.
- **Lane B's files:**
  - no change to `OcuTalon.Core.Conversation`, `OcuTalon.Msg.*` (`Msg.Enum` included), the catalog, `docker/**`, or `ci/**` outside `ci/mock/scenarios/A/`;
  - no change to the mock's code or its tests, or to `Test/{Contract,Core,Data,Demo,Live,Msg,Web}/**`;
  - `Test.Contract.Mock`'s `Arm`, `LogMark` and `LogSince` are only called.
- **The mock's existing scenarios** do not change.
- **No new structures:**
  - no new production item, table, index, event type, mapping or setting;
  - no change to `Production.cls` or `BridgeExample`;
  - `release/standalone-bridge.sh` stays as it is.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First user turn (in process) | A `ZzRunner` (Chat agent), a user turn with a new owner and no link | A link (owner, `ZzRunner`) names a saved `%AI.Agent.Session`. `SessionRotated` is 0. | OK |
| Next user turn (in process) | The same owner again | 1. **The link** names the same session.<br>2. **The logged request** carries turn 1's user text and reply before turn 2's input.<br>3. **The saved session** now holds both exchanges. | OK |
| Throwaway kinds (in process) | A `decide`, an untrusted `turn` and a `diagnose`, for a new owner and for an owner with a link | 1. **A new owner** gets no link.<br>2. **The owner with a link** keeps its link and saved session as they were.<br>3. **No session is saved** after the mark.<br>4. **The untrusted request** carries no history. | OK |
| A failed `Chat` (in process) | `provider-error` on a linked owner, and on a first turn | 1. **The linked owner:** the link and the saved session's data are unchanged.<br>2. **The first turn:** no link and no saved session.<br>3. **The failure `Reply`** is as in Story 1.6. | Failure `Reply` |
| A tainted turn (in process) | A `ZzRunner` with `ProbeAgent`, `context-probe`, a linked owner | `Tainted` is 1. The link and the saved session's data are unchanged. | OK |
| Fresh (in process) | `SessionMode` `fresh` with a `SeedText` and a `SystemNote`, for a linked owner | 1. **The link** names a new session, and `SessionRotated` is 1.<br>2. **The logged first request** has exactly one message, from the user, whose text is the seed, a blank line, the note, a blank line and the input.<br>3. **The old session's row** still exists. | OK |
| Fresh that fails or is tainted (in process) | `fresh` with `provider-error`; `fresh` through `ProbeAgent` with `context-probe` | The link is unchanged, and `SessionRotated` is 0. | n/a |
| `ChatInput` (pure) | Every combination of empty and set `SeedText`, `SystemNote` and `Input`, with `seeded` 0 and 1 | The parts that are set, in the order seed, note, input, joined by `$Char(10, 10)`. With `seeded` 0 the seed is left out. | n/a |
| No session kept (in process) | After a linked turn | 1. **The adapter's agent** holds no `Session`.<br>2. **`%OpenId`** of the linked id gives an object that is not attached.<br>3. **The next turn** opens it with the composed config. | n/a |
| Empty owner (in process) | A user turn with `OwnerRef` "" | An error names `OwnerRef`. Nothing reaches the mock. | Status error |
| Restart (live) | `ChatAgent`'s `Effort` row is `low`. Turn 1 (`recall-tell`) says "My build server is called ORION-7". `Install.Step.Production.Start` restarts the production. Turn 2 (`recall-ask`) asks the name. | 1. **The jobs:** `ChatAgent`'s jobs after the restart share none with before.<br>2. **The history:** turn 2's first logged request carries turn 1's user text, the fact included, and its reply, in that order, before turn 2's input.<br>3. **The config:** both turns' requests have `maxTokens` 8000 and effort `low`.<br>4. **The reply** is `recall-ask`'s text.<br>5. **Storage:** `^AI.Agent.SessionD` and `^OcuTalonBP.ConvLinkD` resolve to OCUTALON_PRIVATE, whose folder is under the manager directory, and that database holds the session's row and the link's row. | OK; restored |
| Busy while held (live) | The test holds the lock (owner, `ChatAgent`). Then: a user turn; an untrusted turn of the same owner; the lock released; the same user turn sent again with the same `ItemId`. | 1. **The held turn:** a `Busy` reply 2 to 5 s after the send. `Busy` is 1 and nothing else is set (no `DecisionRef`, `Fallback` 0, no text). No `Decision` row, no header to `ChatAgent`, no step.<br>2. **The untrusted turn** is answered at once, with `Busy` 0 and no history in its request.<br>3. **The resent turn** is answered, with a row. | OK |
| Busy after a timed-out turn (live) | `Decide`'s `TimerSeconds` row is 12, written directly, and `Decide` restarted. Turn 1 is `turn-late` (the reply comes after 18 s). Turn 2 is sent as soon as turn 1 is answered. The test waits until `ChatAgent` answers turn 1, then sends turn 3. | 1. **Turn 1:** a `timeout` fallback.<br>2. **Turn 2:** `Busy`.<br>3. **Turn 3** is answered. Its first request carries turn 1's input and the late reply, which the late `Chat` saved. | OK; restored |
| The runner's Busy (live) | The test holds the lock, and a linked turn is sent straight to `ChatAgent` | A `Busy` `Reply` after about 2 s, with no `Usage` row and nothing at the mock | OK |
| A re-send reopens (live) | Turn 1, then turn 2 with `overloaded:<key>` armed 1 | Turn 2 is answered after `Decide` sent 2 requests. The two logged requests have equal `messages`: the history, then turn 2's input once. | OK |
| SessionBroken (live) | Turn 1; turn 2 with `invalid-input`; an untrusted turn with `invalid-input`; turn 3 (a new `ItemId`, `fresh`, with a `SeedText`) | 1. **Turn 2:** an `error` fallback with `SessionBroken` 1. The link and the saved session's data are unchanged.<br>2. **The untrusted turn:** `error` with `SessionBroken` 0.<br>3. **Turn 3** is answered with `SessionRotated` 1. The link has moved, and its request holds one user message. | OK |
| `Decide` (in process) | `OnResponse` with a runner `Busy` reply; `Conclude` with an `Invalid input` failure for a user turn, an untrusted turn and a `decide`; `RecordFallback` with a reply whose `SessionRotated` is 1; `Admit` with `SessionMode` "", `continue`, `fresh`, `Fresh` and `x` | 1. **A runner Busy:** `NewBusy`, with no row and no event.<br>2. **Invalid input:** `SessionBroken` 1, then 0, then a `DecisionResponse`, each with the reason `error`.<br>3. **The rotation** is carried.<br>4. **`Admit`** accepts the first three values and refuses the last two, naming `SessionMode`. | n/a |
| Only the runner writes links (scan) | The product classes of `src/` | 1. **Who names the link class:** only `ConversationLink`, the adapter and `Decide`.<br>2. **What `Decide` calls:** only `Lock` and `Unlock`.<br>3. **The scanner** is first shown to flag a sample. | n/a |

</intent-contract>

## Code Map

- **AI Hub (read only, `irislib/`):**
  - **`%AI/Agent.cls`:**
    - `CreateSession` (:639-683) makes the session the agent's `Session` (:680);
    - `ResumeSession` (:693-705) attaches with `BuildSessionConfig(config)` only when the session is not attached, so the config of an attached session is ignored;
    - `OpenSession(id, config)` (:709-716) is `%OpenId` followed by `ResumeSession`, and `%OpenId` returns the object that is still open in the process;
    - `Chat` (:728).
  - **`%AI/Agent/Session.cls`:**
    - storage in `^AI.Agent.SessionD`, `I` and `S` (:746-750);
    - `%OnAddToSaveSet` writes the live history to `ContextData` (:80-98);
    - `%AttachToAgent` imports it with the config (:120-160);
    - `%OnClose` frees the native slot (:101-110);
    - `GetContext` (:284) and `MessageCount` (:448);
    - the repair methods that this story must not call: `SetMessage`, `InsertMessage`, `RemoveMessage` and `RewindTo` (:379-445), and `Reset` and `ResetContext` (:295-320).
- **The bridge (Lane A, `src/bridge/cls/OcuTalon/Bridge/`):**
  - **`Adapter/Agent.cls`:**
    - the class doc (:3-34);
    - `NewSession` (:199-210) and `OpenSession` (:212-225; its doc says why the open needs a session that no agent has attached);
    - `Answer` (:235-295): the refusals at :239-243, `Context.Begin` at :246, the throwaway session at :249, `StepBuffer.Start(BaseChars)` at :255, `Chat` at :258, its Catch at :259-262, `RecordUsage` at :265-270, the reply at :273-284 (`Tainted` at :281) and the ends at :291-292;
    - `BaseChars` (:300-312), `FailureText` (:317) and `ToolsRan` (:354).
  - **`Process/Decide.cls`:**
    - the class doc (:3-66) and `RUNNERS` (:73);
    - `OnRequest` (:176-204): the turn refusal at :182-184, `CheckSettings` at :191, the `DecisionRef` at :193-194, the precheck at :195-198 and the send at :199-203;
    - `OnResponse` (:227-264): `EmitSteps` at :239, the failure at :240-248, the re-send at :249-257 and `Conclude` at :263;
    - `Resend` (:271-287), `Admit` (:391-403), `EstimateTokens` (:515) and `Classify` (:539-566, the failure branch at :546-559);
    - `Conclude` (:599-658): the facts at :606-628, the fallback at :631-633 and the clone at :647-655;
    - `RecordFallback` (:701-730): the carried flags at :724-727.
  - **`Data/ConversationLink.cls`:** the properties at :9-15, the unique `OwnerRefAgentIndex` and Storage. The registry row is `src/short-names.tsv:6` (`ConvLink`). `^OcuTalonBP.Conv` is a lock name, not storage, so it gets no row.
  - **`Msg/Reply.cls`:** `SessionRotated` (:15), `SessionBroken` (:24), `Busy` (:27) and `NewBusy` (:47).
  - **`Msg/Request.cls`:** `SessionMode` (:36), `SeedText` (:39) and `SystemNote` (:42).
  - **`Context.cls`:** `Tainted` (:38) and `Current()` (:74).
  - **`Operation/AgentRunner.cls`:** `OnMessage` (:24-38) passes `Answer`'s reply on.
- **OcuTalon (read only, or call only):**
  - **`src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:** `Start(wait)` (:61-94) restarts a running production and waits until `NotRunning()` is empty, then checks the runners' models.
  - **`src/ocutalon/cls/OcuTalon/Install/Step/PrivateData.cls`:** the private prefixes (:13-16), `GetGlobalDest` at :66 and `Directory` (:91).
  - **`docker/merge.cpf:13`:** the `AI.Agent.Session*` mapping.
  - **`src/ocutalon/cls/OcuTalon/Production.cls`:** `Decide` and the three runners have PoolSize 1 (:18, :24, :28, :31). `ChatAgent`'s agent class has no `EFFORT`, so it sends no effort by default.
- **The mock (Lane B's code; Lane A adds files under `ci/mock/scenarios/A/` only):**
  - **Selection** is by the first marker of the newest user message with text, and never reads wording or history (`mock.mjs:9-23`, `newestTextIndex` at :103-109).
  - **The log** keeps each request's `messages` whole, and the system text by size only (`summarizeRequest`, :152-161).
  - **Usage:** a text reply's `input_tokens` is `ceil(rawLength / 4)` (:324-325), so a history changes the counts.
  - **Existing scenarios:** `invalid-input.json` (400), `overloaded.json`, `provider-error.json`, `context-probe.json`, and `decide-late.json`, whose shape `turn-late` follows.
- **Tests (Lane A, `src/ocutalon/cls/OcuTalon/Test/`):**
  - **`Agent/RunnerFixture.cls`:**
    - `Restart` (:91) and `WaitAllRun` (:100);
    - `Jobs` (:110), `Send` (:202) and `NewRequest` (:214-226; `OwnerRef` "instance" at :221);
    - `Run`, `SessionOf` and `HeaderMark` (:316-380);
    - `PointKeys` and `RestoreKeys` (:394-404);
    - `RememberDefault`, `PutDefault` and `RestoreDefaults` (:596-650);
    - `FallbackProblems` (:736-772; the "000" check of `SessionRotated`, `SessionBroken` and `Busy` at :749);
    - `FindRequests` (:782-790).
  - **`Agent/Decide.cls`:**
    - `OnAfterOneTest` (:148-197) and `Prepare` (:1382);
    - the private `WaitForAnswer` (:1450-1458), which moves to the fixture;
    - `TestTimer` (:523-569), whose direct row of 12 and `Decide` restart are the pattern of the late-turn test;
    - `TestTurnFallbackIsReplyOnly` (:1145-1173; the five flags at :1159).
  - **`Agent/Steps.cls`:** `OnBeforeAllTests` and `OnAfterAllTests` (:77-124, the `StepsAgent` swap) and `OnAfterOneTest` (:95-105).
  - **`Bridge/Runner.cls`:**
    - `OnAfterOneTest` (:74-80) and `TestContext` (:283, a per-test `OwnerRef` at :292);
    - `TestFailureKeepsContext` (:339; empty `OwnerRef`) and `TestOpenKeepsConfig` (:411-444);
    - `NewUsageRequest` (:902-910, `OwnerRef` "instance"), `SaveSession` (:933), `NewRunner` (:949) and `ProviderConfig` (:963).
  - **`Bridge/Decide.cls`:**
    - `TestTurnKeepsReply` (:758) and `TestConcludeFallbacks` (:1103; a reply with `SessionRotated` 1 at :1114);
    - `TestOnErrorFallback` (:1155) and `TestTimerFallback` (:1528);
    - `NewProcess` (:2019), `NewReply` (:2051) and `AssertFallback` (:2168; the "0|0|0" at :2200).
  - **`Bridge/CodeRules.cls`:** `SESSIONCALLS` (:51) and `TestSessionsOnlyThroughTheComposer` (:129), whose scan pattern the link scan follows. `Bridge/Source.cls` holds `Matches`.
  - **`Bridge/ProbeAgent.cls` and `ProbeTool.cls`:** the only code that taints a turn today (`Context.Put("Tainted", 1)`).
  - **`Agent/KeyScan.cls`:** `FindSessions` (:256-268) opens every saved session.
  - **Lane B, read only:** `Contract/Ac.cls:224-226, 267, 294` and `Data/Tables.cls:258, 556` name the link class, the flags and `NewBusy`. No property changes, so they stay green.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **Targets.** A throwaway of tag `e1s8a` with the CI mock, for everything that needs the mock. The slot `ocutalon-slot-a` (namespace `OCUTALON`, after `iris_server_info` shows build 154) only for facts that need no mock.
- **(a) The object cache.** In one process:
  - save a session after a completed `Chat`, keep it referenced, and `%OpenId` its id: is the result attached?
  - release every reference (the agent's `Session` included) and `%OpenId` again: is it attached now?
  - after a `Chat` that threw on an attached session, what is `MessageCount()` compared with before?
- **(b) A resumed request.** A linked turn after a saved one:
  - the `messages` that the mock logs: their shape (a string or blocks) and their order;
  - `maxTokens`, and the effort with `Effort` `low`.
  - **Stop:** if the earlier exchange is missing, stop with status `blocked` and the condition `intent gap: AD-6 / FR-6 (resume), measured <fact>`.
- **(c) `Invalid input`.** `invalid-input` on an opened session through the runner: the `FailureText`.
  - **Stop:** if it does not hold `Invalid input`, stop with status `blocked` and the condition `intent gap: AD-8 (Invalid input text), measured <text>`.
- **(d) The restart.** `Install.Step.Production.Start` on the running production:
  - the seconds until it returns;
  - `ChatAgent`'s jobs before and after;
  - whether a turn is answered after it with no further `PointKeys`.
- **(e) The lock.** While `ChatAgent` is in a `Chat` (`turn-late`), does `LOCK +^OcuTalonBP.Conv(owner, "ChatAgent"):2` from the test process fail after about 2 s? Does it succeed once the reply is saved?
- **(f) The stats of an opened session.** `GetStats()` right after `OpenSession`: are the counters restored or 0? The `Usage` delta is right either way.
- **(g) Where things are stored.** The id of a saved session, and `GetGlobalDest` of `^AI.Agent.SessionD` and `^OcuTalonBP.ConvLinkD`.
- **Other facts.** If any fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`:**
  - `LOCKSECONDS` 2, plus `SessionOf`, `Point`, `Lock` and `Unlock`, as in Boundaries;
  - the class doc: the lock, its key and its two users.
  - No property, index or Storage change. Rationale: AD-6, AD-33.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`.** Rationale: AD-6, AD-7, AD-9, AD-10; FR-6, NFR-2.
  - **The linked path of `Answer`:** steps 1 to 7 of Boundaries, in a private method beside `Answer`'s throwaway path, not a second `Answer`.
  - **`ChatInput`** (pure).
  - **`BaseChars`** takes the composed input and the opened session.
  - **The release** of the session object on every path.
  - **The docs:** the class doc and `Answer`'s doc.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`.** Rationale: AD-6, AD-8, AD-20, AD-30, AD-31.
  - **The Busy probe in `OnRequest`**, and `OnResponse` answering a runner `Busy` reply with `NewBusy`, after `EmitSteps` and before the re-send is weighed.
  - **SessionBroken:** `INVALIDINPUTTEXT`, and the pure `Broken(request, failure) As %Boolean`, which `Conclude` uses and passes to `RecordFallback`. `RecordFallback` gains a trailing `broken As %Boolean = 0` and carries the runner's `SessionRotated`.
  - **`Admit`** checks `SessionMode`.
  - **The class doc:** the Busy and SessionBroken paragraphs.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`:** `Parameter SESSIONMODES = "continue,fresh"`, and the docs of `SessionMode`, `SeedText` and `SystemNote` (how the runner sends them). No storage change. Rationale: AD-6.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`:** the docs of `SessionRotated`, `SessionBroken` and `Busy` (who sets each, and when a fallback carries it). No storage change. Rationale: AD-6, AD-8.
- **`src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`:** the class doc names the Busy reply. Rationale: AD-6.

**The mock (Lane A's folder).** Rationale: AD-22.
- **`ci/mock/scenarios/A/recall-tell.json`** (new): a 200 with the text `Noted.`
- **`ci/mock/scenarios/A/recall-ask.json`** (new): a 200 with the text `Your build server is called ORION-7.`
- **`ci/mock/scenarios/A/turn-late.json`** (new): a 200 with `delayMs` 18000 and the text `The CI mock answers this turn late.` (the shape of `decide-late`).

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls`** (new, in process, a `ZzRunner`): the rows "First user turn" to "Empty owner".
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Conversation.cls`** (new, live): the rows "Restart" to "SessionBroken", with the fixture's `Prepare` pattern (`ReadyReason`, `PointKeys`, then `RestoreKeys` at the end).
  - **Its methods:** `TestRestart`, `TestBusyWhileHeld`, `TestBusyAfterTimedOutTurn`, `TestRunnerBusy`, `TestResendReopens` and `TestSessionBroken`.
  - **After the restart,** `TestRestart` calls `PointKeys` again only if Task 0 (d) shows that a turn is not answered without it.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:**
  - new: `TestBusyRelayed`, `TestSessionBroken`, `TestFallbackCarriesRotation` and `TestAdmitSessionMode` (the row "`Decide` (in process)");
  - `TestConcludeFallbacks` and `AssertFallback` expect the carried `SessionRotated`;
  - the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:** `TestOnlyTheRunnerWritesLinks` (the row "Only the runner writes links").
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`:**
  - `NewUsageRequest` and the user-turn requests get a new `OwnerRef` each;
  - `TestFailureKeepsContext` sets one;
  - `OnAfterOneTest` removes the sessions saved since the test began and their links.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
  - `NewRequest` gains a trailing `ownerRef As %String = ""`. "" gives a new Ref for a user `turn` and "instance" for anything else;
  - `FallbackProblems` judges `Busy` only (`SessionRotated` and `SessionBroken` are carried, like `Tainted`);
  - `WaitForAnswer` moves here from `Test.Agent.Decide`, public;
  - `SessionMark()` and `DropSince(mark)`: delete the AI sessions saved after the mark, and the links that name them.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`** and **`Test/Agent/Steps.cls`:** `OnAfterOneTest` calls `DropSince`. `Decide.cls` uses the fixture's `WaitForAnswer`.
- **Coverage.** These tests prove every matrix row.

**Acceptance Criteria:**
- **AC1, only user turns are linked.**
  - **Given** a `turn` with provenance `user`,
  - **when** the runner handles it,
  - **then:**
    - it opens the AI session that `ConversationLink` maps for (`OwnerRef`, agent), or creates one and links it;
    - only the runner writes links, and only for user turns;
    - `decide`, `diagnose` and untrusted turns run in a throwaway session that is never linked or saved.

  (`Test.Bridge.Conversation`: the first, next and throwaway rows; `Test.Bridge.CodeRules.TestOnlyTheRunnerWritesLinks`)
- **AC2, the lock, the save and the config.**
  - **Given** a linked conversation,
  - **when** a turn runs,
  - **then:**
    - the runner holds `LOCK ^OcuTalonBP.Conv(<OwnerRef>, <agent>)` from `OpenSession` (or `NewSession`) to `%Save`;
    - it saves the AI session only after a completed `Chat` that is not tainted;
    - it opens the session with the composed config every time, so the mock's log shows the resumed session still sending its 8,000-token cap and its effort.

  (`Test.Bridge.Conversation`: the failed, tainted and no-session-kept rows; `Test.Agent.Conversation.TestRestart`, `TestRunnerBusy`)
- **AC3, a held conversation answers Busy (Integration AC: `Decide`'s caller reads `Busy`).**
  - **Given** a `turn` whose conversation lock is still held by an earlier turn, even one that `Decide` gave up on,
  - **when** `Decide` has waited 2 seconds for it,
  - **then:**
    - it answers a `Reply` whose `Busy` is 1, with no text and no decision, never an error status, and it is not a fallback;
    - an untrusted turn is never refused this way.

  (`Test.Agent.Conversation.TestBusyWhileHeld`, `TestBusyAfterTimedOutTurn`; `Test.Bridge.Decide.TestBusyRelayed`)
- **AC4, a conversation survives a restart (Integration AC: the model API, through AI Hub, reads the history).**
  - **Given** a user told OcuTalon a fact in one turn,
  - **when** the production restarts before the next turn, so no runner job keeps anything in memory,
  - **then:**
    - the next turn's first model request carries the earlier conversation;
    - the `recall-ask` question is answered;
    - AI sessions and conversation links live in the private database on the durable volume.

  (`Test.Agent.Conversation.TestRestart`; `Test.Bridge.Conversation`, the next-turn row)
- **AC5, a fresh turn rotates.**
  - **Given** a `turn` with `SessionMode` `fresh` and a `SeedText`,
  - **when** the runner handles it,
  - **then:**
    - the link moves to a fresh AI session seeded with that recap;
    - any `SystemNote` is sent as code-written text before the input;
    - the reply's `SessionRotated` is 1.

  (`Test.Bridge.Conversation`: the fresh rows and `ChatInput`; `Test.Agent.Conversation.TestSessionBroken`, turn 3)
- **AC6, a rejected history is reported, never repaired.**
  - **Given** the provider rejects a conversation's stored history ("Invalid input") on a user `turn`,
  - **when** the runner gets the error,
  - **then:**
    - the reply has `SessionBroken` set (an `error` fallback);
    - the stored history and the link stay as they were, so the caller can retry once in a fresh, seeded session.

  (`Test.Agent.Conversation.TestSessionBroken`; `Test.Bridge.Decide.TestSessionBroken`)
- **AC7, Story 1.7's two questions (decided in this story).**
  - **Given** a turn that `Decide` re-sends after a rate limit, and a turn whose `Chat` outlives `Decide`'s timer,
  - **when** the runner handles the re-send, and the late `Chat` ends,
  - **then:**
    - the re-sent attempt reopens the same saved history;
    - the late `Chat` holds the lock until its save, so the next turn is `Busy` until then;
    - an untainted late `Chat` is saved, and the next turn carries it;
    - a tainted turn is never saved, late or not.

  (`Test.Agent.Conversation.TestResendReopens`, `TestBusyAfterTimedOutTurn`; `Test.Bridge.Conversation`, the tainted row)

## Spec Change Log

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** the link, the adapter and `Decide` name no OcuTalon package.
- **AD-3:** the sessions and links in OCUTALON_PRIVATE, through the existing mappings.
- **AD-5:** state on the durable volume; no Storage changes.
- **AD-6:**
  - the link: only the runner writes it, and only for user turns;
  - the lock from `OpenSession` to `%Save`, and a save only after a completed `Chat`;
  - the same composed config on every open;
  - the rotation for `fresh`;
  - `Busy` after 2 seconds;
  - the `Request` and `Reply` fields.
- **AD-7:** the session config built in code on every resume.
- **AD-8:** "Invalid input" on a turn sets `SessionBroken`, and the history is never repaired in place; the re-send.
- **AD-9:** the first step's estimate counts the history.
- **AD-10 (rule 3 and 3a):** untrusted turns run in a fresh session, and untrusted content never carries into a later turn.
- **AD-20:**
  - only a busy refusal records no `Decision` row;
  - one `Usage` row per `Chat`;
  - retention purges only sessions that no link names (Story 30.2).
- **AD-22:** the scenarios under `A/` and selection by marker.
- **AD-26:** the Busy reply is Decide's answer in the trace.
- **AD-30:** `Conversation`'s use of `Busy`, `SessionBroken` and `Tainted`, as the consumer.
- **AD-31:** no event for a Busy refusal.
- **AD-33:** Lane A owns `ConversationLink`; no new item, table or event type.

No acceptance criterion contradicts an AD's Rule. AC6 and AD-20 together have one consequence for Story 2.4 (decision 12), which goes to the lead (Clarification Record).

**Decided in-stage:**
1. **The lock's name.**
   - **The name:** `^OcuTalonBP.Conv(OwnerRef, agent)`, with the link's own unique key as `<link>`. The key exists before the first turn creates the row, so two first turns cannot both create one.
   - **The kind of lock:** incremental (`LOCK +` / `LOCK -`), because a plain `LOCK` would drop every other lock that the job holds.
   - **One place:** one helper on `ConversationLink`, so the runner and `Decide` cannot drift.
2. **The agent of a link** is the runner item's name, as in the `Usage` row's `Agent` (Story 1.4). `Decide` knows it from `RUNNERS`, and the runner from its config name.
3. **Busy has two checks with one answer.**
   - **`Decide`'s probe** is the AC's check. With `ChatAgent`'s pool of 1, a turn queued behind a late `Chat` could never be told apart inside the runner.
   - **The runner** takes the lock with the same 2-second wait and answers `NewBusy` when it cannot take it. This covers the gap between the probe and the send, which no product path reaches (`Conversation` serializes a session's turns).
   - **Where the probe runs:** after `CheckSettings` (a misconfigured `Decide` stays an error) and before the precheck, so a turn that cannot run now records nothing.
4. **An empty `OwnerRef` on a linked turn is refused by the runner.** `Decide` already refuses it (`Admit`), and a silent throwaway session would hide the fault.
5. **No session object outlives a request.**
   - **Why it matters:** `OpenSession` returns the object that is still open in the process, attached, with its live history (Code Map). An object that is kept would carry an unsaved failed or tainted turn into the next request.
   - **The rule:** releasing it makes every linked turn open the saved history, and that is how a re-sent turn reopens it (Story 1.7's first question).
6. **A tainted turn is never saved.**
   - **What AD-10 3a already gives:** after a tainted reply, `Conversation` sends the next turn `fresh` with a recap from the `Turn` rows, so in the normal path nothing is lost.
   - **The gap it closes:** a late `Chat` whose taint the timer fallback cannot carry (Story 1.7's second question) never puts tool results into the stored history.
   - **For the lead:** recorded in the Clarification Record.
7. **The late `Chat` of a timed-out turn, decided against the lock.**
   - **The lock** is held until the save, so the next turn is `Busy` until the late `Chat` ends.
   - **An untainted late `Chat` is saved,** as AD-6's rule says ("after a completed `Chat`"). The user's words are kept, and the next turn carries the late exchange.
   - **The cost:** the history then holds an answer that the user did not see (their reply was the timeout fallback). Recorded for the lead.
8. **How `SeedText` and `SystemNote` reach the model.**
   - **The rule:** `ChatInput` joins seed, note and input in the turn's one user-role message, so the seed is the fresh session's first message.
   - **Why:** it needs no AI Hub message API (`InsertMessage` would be a repair-style call). It is observable in full in the mock's log, where the system text is reduced to its size. `Agent.Input`'s time preamble is the precedent for code-written text in the user message.
9. **A fresh turn moves the link only after a completed, untainted `Chat`.**
   - **Why:** an unsaved session has no id.
   - **When a fresh turn fails or is tainted,** the link stays, and the caller sends `fresh` again (after `Tainted` or `SessionBroken`).
   - **The old session** stays for Story 30.2's purge of sessions that no link names.
10. **`SessionMode` values.** "", `continue` and `fresh` are admitted; any other value is refused, so a misspelt `fresh` can never continue a session that should have rotated. The values are a parameter on `Request`, not on `Msg.Enum`, because the bridge's `Msg.Enum` must equal Lane B's `OcuTalon.Msg.Enum` (a pinned test).
11. **SessionBroken.**
    - **Where it is set:** in `Decide`, beside the one classification (AD-8), only for user turns, which are the only ones with a stored history.
    - **The reason** stays `error`, as Story 1.6 left it, so the catalog's text is unchanged.
    - **The runner** does nothing special: a failed `Chat` saves nothing, which is "never repaired in place".
12. **A SessionBroken answer is a recorded fallback.**
    - **The rule:** AD-20 exempts only a busy refusal from recording a row.
    - **The consequence:** `Decide` records one turn decision per `ItemId`, so `Conversation`'s retry (AD-30, Story 2.4) is a new `Decide` call and needs a new `ItemId`.
    - **For the lead:** the Clarification Record lists the choice.
13. **Fallbacks carry `SessionRotated`,** as they carry `Tainted` and `ToolsRun`. A fresh turn whose reply is then refused did move the link, and the caller must know. `FallbackProblems` stops treating `SessionRotated` and `SessionBroken` as flags that a fallback never has.
14. **A link whose session cannot be opened is an error status,** as a failed `NewSession` is today. It is unreachable: retention purges only sessions that no link names (AD-20), and nothing else deletes one.
15. **The first step's estimate counts the history** (`BaseChars`). Without it, every linked turn's model-step estimate and the `Usage` row's largest estimate would leave out the history, which this story starts sending. Story 1.9 still owns the precheck's estimate.
16. **"A question only the history answers."**
    - **What the mock can do:** it never reads history (selection is by marker, `mock.mjs:23`), so `recall-ask` answers from its script.
    - **The falsifiable pin** is the mock's log: turn 2's first request carries turn 1's fact and reply. The mutation "the runner opens a new session for a linked turn" turns it red.
    - **The outcome** for the product and for the test is the same as for a mock that checks the history. Recorded for the lead.
17. **Test owners.**
    - **Why every test user turn needs its own conversation:** the fixture's turns all use `OwnerRef` "instance" today, so they would share one history, and the mock's token counts grow with it (`mock.mjs:325`).
    - **The rule:** `NewRequest` gives each user turn a new Ref unless a test names one, and `DropSince` removes what a test saved.
18. **The restart is `Install.Step.Production.Start`,** the product's own restart, which waits until every item runs again. A test asserts `ChatAgent`'s new jobs. A whole-production restart, not one item's, matches the AC.
19. **`ChatAgent`'s `Effort` is `low` for the resume check.** The Chat agent declares no `EFFORT` and sends none, so without a value the effort half of AC2 could not fail. The row is put back afterwards.

**Integration ACs (Rule 1):**
- **AC3:** `Decide`'s caller (the test, through the production's service) reads `Busy`.
- **AC4:** the model API, through AI Hub's provider, reads the restored history (the mock's log).
- **The other flags have no production consumer in this story.** For `Busy`, `SessionBroken`, `SessionRotated` and `SystemNote`, the first is Story 2.4 (`Conversation`, Lane B).

**Consumed-by:**
- **Story 2.4 (Lane B):** `Conversation`:
  - sets `OwnerRef` to the session's `SessionRef`;
  - treats `Busy` as wait-and-retry;
  - retries a `SessionBroken` turn once with `SessionMode` `fresh`, its recap and, by decision 12, a new `ItemId`;
  - sends `fresh` with a `SeedText` after a `Tainted` reply;
  - passes `SystemNote`;
  - sends only "", `continue` or `fresh`.
- **Story 1.9:** the precheck's history estimate reads the linked session (`ConversationLink.SessionOf`).
- **Stories 3.x (the gate):** the taint that the gate sets keeps a turn from being saved (decision 6). AD-10 3a's CI test, "after a tainted turn, the next turn's first model request holds no tool result from it", holds by construction.
- **Stories 9.1 to 9.3:** `EvalIn`'s `turn` cases (owner `eval`, provenance `user`) would share the one link (`eval`, `ChatAgent`), unless each case is sent `fresh`.
- **Story 30.1:** compaction moves the link through `Point`, under the same lock.
- **Story 30.2:** the purge removes the sessions that no link names.

**Consumes:**
- **Story 1.2:** `NewSession`, `OpenSession`, `Compose`, `RunnerFixture`, and `TestOpenKeepsConfig`'s finding about attached sessions.
- **Story 1.3:** `Decide`, its one decision per item, and `Run` / `SessionOf`.
- **Story 1.4:** one `Usage` row per `Chat`.
- **Story 1.5:** `BaseChars` and the steps.
- **Story 1.6:** `Classify`, `RecordFallback`, `FallbackProblems`, and the measured `Invalid input` text.
- **Story 1.7:** the re-send, the timer, `ToolsRun`, and `TestTimer`'s direct timer row.
- **Epic 0:** `ConversationLink`, the `Reply` flags, `NewBusy`, the `Request` fields, the private mappings and `PrivateData`, and the mock's `invalid-input`.
- **Lane B, call only:** `Test.Contract.Mock.Arm`, `LogMark` and `LogSince`, and the mock.

**Extend, don't copy (Rule 2):**
- **One `Answer`.** The linked path is a private method that `Answer` calls. `NewSession`, `OpenSession`, `RecordUsage`, `StepRecords` and `ToolsRan` are reused.
- **Parameters, not copies:**
  - `BaseChars` gains the session;
  - `RecordFallback` gains `broken`;
  - `RunnerFixture.NewRequest` gains `ownerRef`.
- **`Reply.NewBusy`** answers both Busy paths.
- **One lock name,** in `ConversationLink`, for the runner and `Decide`.
- **The restart** is `Install.Step.Production.Start`. `RunnerFixture.Restart` restarts one item only.
- **`WaitForAnswer`** moves into the fixture, so the new live class does not copy it.
- **The link scan** follows `TestSessionsOnlyThroughTheComposer`'s scanner and `Source.Matches`.
- **The scenario** `turn-late` follows `decide-late`'s shape.
- **The new test classes** are needed because no test of conversations exists. `Test.Agent.Decide` already has 1,625 lines.

**Ledger:** the inbox for this story is empty, so no entry is addressed or declined.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and process-local facts. No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s8a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s8q` and review `e1s8r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - `ci/iris.sh teardown` runs with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each prefixed with the tag and the lock owner where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, the storage check, the bridge-references check and the boundaries check included. About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Conversation`, `.Bridge.Decide`, `.Bridge.Runner` and `.Bridge.CodeRules`;
  - `.Agent.Conversation`, `.Agent.Decide` and `.Agent.Steps`.

  Expected: `CLASS ... passed`. `.Agent.Decide` takes about 2 min, and `.Agent.Conversation` should take 2 to 3 min (the restart and the 18-s late turn).
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s8a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the three new scenarios.
- **(once)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers`. `Agent.KeyScan` opens every saved session.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed, `Test.Contract.Ac` and `Test.Data.Tables` included (no property changed).
- **(once)** `bash release/standalone-bridge.sh`. Expected: every check `PASS` (the example sends no turn).
- **(once)** `bash ci/iris.sh live production-restart`, then `live compose-start`, then `live demo-path`, one per call. Expected: PASS. `compose-start` checks that `AI.Agent.Session*` resolves to the private database, and `demo-path` passes its `@floor` test.
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s8a`'s projects.
- **Not run:** `live storage-roundtrip`, because no Storage block changes, which `bash ci/checks.sh`'s storage check confirms.

**Shared surfaces:**
- **Every user turn now saves an AI session and a link.**
  - **What it touches:** `^AI.Agent.SessionD` and `^OcuTalonBP.ConvLinkD`. `Test.Agent.KeyScan.FindSessions` opens every saved session.
  - **What changes:** the turns of `Test.Agent.Decide`, `Test.Agent.Steps` and `Test.Bridge.Runner` create them, so those classes remove them (`DropSince`).
- **The owner of a test's user turns.**
  - **The fixtures:** `RunnerFixture.NewRequest` (`OwnerRef` "instance" today) and `Test.Bridge.Runner.NewUsageRequest` give each user turn a new Ref.
  - **Search the test trees** for `NewRequest("turn", "user"` and `Provenance = "user"`. A test that asserts a user turn's `OwnerRef` or its token counts expects the new owner and a request with no history.
- **The flags of a fallback `Reply`:**
  - `RunnerFixture.FallbackProblems` (:749);
  - `Test.Bridge.Decide.AssertFallback` (:2200) and `TestConcludeFallbacks` (:1114, a reply with `SessionRotated` 1, which is now carried);
  - `Test.Agent.Decide.TestTurnFallbackIsReplyOnly` (:1159) and `Test.Bridge.Decide.TestTimerFallback` (:1563), whose five zeros stay true.
- **`Decide`'s turn path:**
  - a user turn takes the lock probe;
  - `Admit` refuses an unknown `SessionMode`;
  - `Test.Bridge.Decide.TestOnRequestUsesItsSettings` and the `Admit` tests.
- **`TestFailureKeepsContext`** now needs an `OwnerRef`.
- **Production state while a test runs:**
  - all jobs (the restart test restarts every item);
  - `Decide`'s `TimerSeconds` row and `ChatAgent`'s `Effort` row, with the items that they restart;
  - a conversation lock that a test holds.
- **The mock:** the new `recall-tell`, `recall-ask` and `turn-late`, and the countdown of `overloaded:<key>`, which the test arms on its own key and clears.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `Answer` links an untrusted turn too | `Bridge.Conversation` (the throwaway row) |
| AC1 | A product class other than the adapter calls `Point` | `Bridge.CodeRules.TestOnlyTheRunnerWritesLinks` |
| AC2 | The runner takes no lock | `Agent.Conversation.TestRunnerBusy` and `TestBusyAfterTimedOutTurn` |
| AC2 | The session is saved after a `Chat` that threw | `Bridge.Conversation` (the failed row) |
| AC2 | `OpenSession` composes no config | `Agent.Conversation.TestRestart` (the cap and the effort of turn 2) |
| AC3 | `Decide` skips its probe | `Agent.Conversation.TestBusyWhileHeld` (a header to `ChatAgent`) |
| AC3 | A Busy refusal records a fallback row | `Agent.Conversation.TestBusyWhileHeld`, `Bridge.Decide.TestBusyRelayed` |
| AC3 | Untrusted turns are probed too | `Agent.Conversation.TestBusyWhileHeld` (the untrusted turn) |
| AC4 | A linked turn always opens a new session | `Agent.Conversation.TestRestart`, `Bridge.Conversation` (the next-turn row) |
| AC4 | The adapter keeps the session object between requests | `Bridge.Conversation` (the no-session-kept row) |
| AC5 | `fresh` is treated as `continue` | `Bridge.Conversation` (the fresh row) |
| AC5 | `ChatInput` drops `SystemNote` | `Bridge.Conversation` (`ChatInput`, the fresh row) |
| AC6 | `Invalid input` sets no `SessionBroken` | `Agent.Conversation.TestSessionBroken`, `Bridge.Decide.TestSessionBroken` |
| AC6 | `SessionBroken` is set on an untrusted turn | `Bridge.Decide.TestSessionBroken` |
| AC7 | A tainted turn is saved | `Bridge.Conversation` (the tainted row) |
| AC7 | A re-sent attempt reuses the kept object (decision 5 undone) | `Agent.Conversation.TestResendReopens`, if Task 0 (a) shows that a failed `Chat` grows the live history; otherwise the no-session-kept row stands for it |

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **A tainted turn is never saved** (decision 6). This changes which AI sessions are stored: a guarantee is strengthened, and no schema or format changes. It closes Story 1.7's second question for every path, a late `Chat` included.

**For the lead (ruling recommended, not blocking):**
- **Decision 12, SessionBroken and Story 2.4's retry.**
  - **The facts:** the broken attempt is a recorded `error` fallback, because AD-20 exempts only a busy refusal. `Decide` records one turn decision per `ItemId`. So `Conversation`'s one retry in a fresh session (AD-30) must carry a new `ItemId`.
  - **Two options:**
    - **(a, recommended):** keep AD-20, and add a note to Story 2.4 (Lane B, not yet planned): "the retry is a new `Decide` call with a new `ItemId`". That is veto item 8 for another epic's story, which a parallel run routes to the orchestrator.
    - **(b):** amend AD-20 so that a broken-session answer records no row, like a busy refusal (veto item 9). Then the broken attempt would leave no row, and any `Usage` row it wrote would have no decision.
  - **A spine line is recommended either way (Rule 20),** under AD-30: "A `SessionBroken` turn's retry is a new `Decide` call with a new `ItemId`", or the amended AD-20.
- **Decision 7, the late `Chat`.** An untainted late `Chat` is saved (AD-6's rule), so the next turn sees an answer that the user did not see. The alternative is not to save when `Decide` has already recorded the decision of the `DecisionRef`. That leaves a race of milliseconds and drops the user's own words from the history. Recommended: keep AD-6's rule.
- **Decision 6, a spine line (Rule 20),** under AD-6: "A turn whose context is tainted is never saved, so its tool results never reach the stored history (AD-10 3a)." It binds Epic 3's gate and Story 30.1's compaction.
- **Decision 16, the recall scenario.** Its answer is scripted, and the history pin is the mock's log. A mock that checks the history would be new mock behaviour, which is Lane B's (AD-22), and the outcome would not differ.
- **Stories 9.1 to 9.3:** `eval` turn cases would share one conversation unless each is sent `fresh` (Consumed-by).

**Lead's rulings at the spec gate (2026-10-23, Epic 1 runner, unattended):**
- **Decision 12:** this story complies with AD-20 as written: the broken attempt is a recorded `error` fallback with `SessionBroken` 1. No AD changes here. Story 2.4 is already done in Epic 2, and its `Conversation.Rebuild` retries with the same `ItemId`, which `Decide` refuses (`ResponseFromRow`): that cross-epic part goes to the orchestrator, with the spine lines.
- **The orchestrator's ruling (2026-10-23, U14, option a):** AD-20 stays; this story is unchanged; Epic 2 fixes `Conversation.Rebuild` so the retry is a new `Decide` call under a new `ItemId` (its ledger, before it merges), and writes the AD-30 line as its own Conventions row. The taint rule is the spine's Consistency Conventions row "Saved conversations" (no AD text changes). Do not edit `Core/Conversation.cls` (contended).
- **Veto window, kept as planned:** a tainted turn is never saved (inbox U-37); the late untainted `Chat` of a timed-out turn is saved (U-38).
- **Decided:** decision 16 stands (the history pin is the mock's request log).
- **Stories 9.1 to 9.3:** ledgered as DW-110, routed to Story 9.1.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-23, halted after planning as the dispatch asked).**
- **Sources.** The cached `epic-1-context.md`, Story 1.7's spec (done) for continuity, the Story 1.8 block of `epics.md`, and the spine's AD-2, 3, 5 to 10, 20, 22, 26, 30, 31 and 33.
- **The standard.** The spec meets the READY FOR DEVELOPMENT standard.
- **No runtime.** Nothing was measured or run against a runtime in this stage; Task 0 holds the measurements.
- **Story 1.7's two questions** are decided here (AC7; decisions 5 to 7): a re-sent turn reopens the saved history because no session object outlives a request, and a tainted turn is never saved, so a late taint cannot reach a later turn.
- **The ledger inbox** is empty.
- **The Clarification Record** lists one item for the veto window (a tainted turn is never saved) and five for the lead. The first, SessionBroken against AD-20, means that Story 2.4's retry needs a new `ItemId`. None blocks implementation.
- **Footprint.** Every file the plan edits is in Epic 1's footprint: `src/bridge/**`, `Test/{Agent,Bridge}/**` and `ci/mock/scenarios/A/**`. No contended path is touched.
