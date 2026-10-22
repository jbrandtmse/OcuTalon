---
title: 'Story 2.4: Answer every chat message through the turn pipeline'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: 'e0c77f82f405d05a3ee00ede8bbc57215d3a9cf7'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Nothing runs the Reconcile declarations when the production is started on its own (an IPM install's autostart, or a
      production stop and start without an installer run), so a turn left running then waits for the next installer run.
    evidence: |-
      AD-23 says that on an IPM install the Reconcile declarations run on every production start, whatever started it. A search of
      src/ for OnStart, OnProductionStart and Autostart finds nothing, and Install.Step.Reconcile (the only caller of
      CallAreas("Reconcile")) runs only inside the installer's step order. Story 2.4 only adds Web.Reconcile() to that order, as its
      spec says; Production.cls and the installer registry are Lane A's.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Registry.cls, src/ocutalon/cls/OcuTalon/Production.cls
    severity: medium
  - summary: >-
      The Busy wait and resend run end to end only against a probe that replaces SetTimer, never through the real Ens.Alarm and the
      reopened instance.
    evidence: |-
      TestBusyRequeues (ConversationTurns) drives Wait through ConversationProbe. Task 0 measured the timer path once with a
      temporary change, which was reverted. ConversationProduction and restart row 20 reach only the Epic 0 Decide stub, which answers
      an error status, so Busy is never produced in a production. It needs the real Decide (Story 1.3) or a Decide double inside a
      test production (DecideDouble is an Ens.BusinessProcess for that).
    location: >-
      src/ocutalon/cls/OcuTalon/Core/Conversation.cls (Delay, Resend, Wait)
    severity: medium
  - summary: >-
      No test observes that WebChatIn's Allowed reaches Allowance.TryConsume, because TryConsume is a constant that cannot refuse yet.
    evidence: |-
      WebChatInProbe.Allowed records the call and either refuses or delegates to the real Allowed; TryConsume ignores its arguments and
      answers 1, so replacing Allowed's body with Quit 1 changes no test. Story 16.9 makes TryConsume able to refuse, and its test
      with the online-demo flag on closes the gap.
    location: >-
      src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls (Allowed)
    severity: low
---

<intent-contract>

## Intent

**Problem:** `POST /api/v1/messages`, `WebChatIn` and `Conversation` are still Epic 0 stubs. A message typed on the page goes nowhere, and no turn ever runs. A `Turn` row also has no text, so Story 2.2's `/state` chat can't show a conversation after a reload (DW-61).

**Approach:** Build the user-message path of AD-30:
- `POST /messages` calls `WebChatIn`. `WebChatIn` deduplicates on `clientId`, calls `Allowance.TryConsume`, and sends an `Item` to `Conversation`.
- `Conversation` alone owns the `Turn` queue. For each turn it calls `Decide` twice (`decide`, then `turn`) and handles Busy, SessionBroken and Tainted replies. It turns every failure into the turn-fallback reply, publishes `chat.message` at three stages, sends an `Outbound` to `Notify`, and starts the next queued turn.
- After every start, a reconcile re-runs every turn left `running` or `queued`.
- `Turn` keeps the message text, the reply as sent, the `clientId` and the trace target, and `ChatMessage.FromRow` maps them (DW-61).

Unit tests drive every reply shape through a `Decide` double at `Conversation`'s one send seam. Throwaway tests run the real production with Epic 0's `Decide` stub, which answers an error status.

## Boundaries & Constraints

**Always:**
- **The path (AD-1, AD-14, AD-30).** Every hop is a production message:
  - `POST /api/v1/messages` → `WebChatIn` (`Ens.Director.CreateBusinessService` + `ProcessInput`, in the REST process);
  - → `Conversation`, an async `OcuTalon.Msg.Item`;
  - → `Decide` (`decide`, then `turn`), async with a response;
  - → `Notify`, an async `OcuTalon.Msg.Outbound`.

  `Conversation` never calls `SendRequestSync` (AD-6 Prevents: a slow model call blocking a process). It never classifies a reply (AD-8) and never renders text (AD-32).
- **REST.**
  - The body is `{clientId, text, fromGuide}`:
    - `clientId` is a string of 1 to 128 characters;
    - `text` is a string with at least one non-space character;
    - `fromGuide` is true only when it is JSON `true`.
  - The session comes only from `Ownership.SessionRef` (AD-4). A `sessionRef` in the body is ignored.
  - A valid body answers `202` with `{"clientId": <clientId>}`, a repeat included. Any other body, including one that can't be read as a JSON object, answers `400` `bad_message` with `MESSAGEBADMESSAGE` "A message needs a clientId and some text." (veto item 2). A session row that can't be read, a `CreateBusinessService` error (no production) or a `WebChatIn` error answers `500` `server_error` with `MESSAGESERVERERROR`.
- **`WebChatIn`** (adapterless, pool 0) accepts two inputs.
  - **`OcuTalon.Channel.WebChat.Post`** (`SessionRef`, `ClientId`, `Text`, `FromGuide`). In order:
    1. If `Ownership.TurnByClient(SessionRef, ClientId)` finds a turn, the output is `{"accepted":1,"duplicate":1}` and nothing is sent.
    2. It calls `Allowance.TryConsume(SessionRef, "web", Text, .retryAt, .firstRefusal)`. A refusal queues nothing and answers an error status (Decided 4).
    3. It sets `..%SuperSession` to the `Session` row's `TraceRef`.
    4. It sends an `Item`: `ItemId` from `NewRef()`, `SessionRef`, `Channel` "web", `Provenance` "user", `Text`, `FromGuide` and `ClientId`.
    5. The output is `{"accepted":1,"duplicate":0}`.
  - **`OcuTalon.Core.Msg.RunTurns`**: forwarded to `Conversation` unchanged. This is the reconcile's way in (Decided 6).
- **`OcuTalon.Core.Allowance.TryConsume(sessionRef, channel, text, Output retryAt, Output firstRefusal) As %Boolean`** allows every message with `retryAt` "" and `firstRefusal` 0. Story 16.9 adds the online-demo count, the per-session lock, the refused `Turn` and the 429. `Conversation` never calls it (AD-20).
- **The queue (AD-6, AD-30).** At most one turn per session is `running`, and turns start in `CreatedAt`, ID order.
  - **On an `Item`:**
    - It drops an `Item` whose `ItemId` already has a turn (a re-delivery) or whose `ClientId` already has one for the session (a race past `WebChatIn`'s check).
    - It drops, with `$$$LOGWARNING`, an `Item` that is not `user` provenance, or has no `ItemId`, no text or no `Session` row (NFR-14).
    - Otherwise it saves a `queued` turn, publishes `chat.message`, and starts the session's next turn.
  - **On a `RunTurns` with a `SessionRef`:** it starts that session's next turn.
  - **On a `RunTurns` with an empty `SessionRef` (the sweep):** every `running` turn becomes `queued`, then one `RunTurns(SessionRef)` goes to itself for each session with queued turns.
  - **Starting a turn:** under `LOCK +^OcuTalon.Core.TurnQueue(SessionRef):5`, if no turn of the session is `running`, it marks the head `running` and increments `Attempt`.
- **A turn.** Before any send, the instance sets two values:
  - `..%SessionId` to the `SessionId` of the turn's `Item` header (`TraceHeaderId`); with no header, its own session stays;
  - `..%SuperSession` to the session's `TraceRef`.

  It then sends a `Request` with `Kind` "decide": `Provenance` user, `Input` = `Agent.Input.Render(<an Item built from the row>)`, `ItemId`, `Summary` (the text's first line, at most 80 characters), `OwnerRef`, `TraceRef`, `Channel` and `ThreadSessionId` = `..%SessionId`.
  - **Whatever answers the decide request** (any outcome, a fallback, an error status or a wrong class), it stores `TriageDecisionRef` when the answer is a `DecisionResponse` and publishes `chat.message`.
  - **Then it sends the same request with `Kind` "turn".** `SessionMode` is "fresh" with `SeedText` = the recap when `Ownership.LastRepliedTurn(SessionRef)` is `Tainted`; otherwise it is "continue".
- **The turn's answer:**
  - **`Busy`:** wait 3 s (`SetTimer`) and send the turn request again, at most 5 times. A sixth `Busy` is the fallback `rate_limited`.
  - **`SessionBroken`**, the first time: send the turn request again, with `SessionMode` "fresh" and the recap. The second time it is the fallback, with the reply's reason.
  - **A `Reply` with `Fallback` 1:** the fallback, with its `FallbackReason`.
  - **A usable `Reply`:** `ReplyText` = its `Text`, as sent.
  - **An error status, no answer, or not a `Reply`:** the fallback `unusable`, at once.
  - A reason outside `Msg.Enum FALLBACKREASON` becomes `unusable`. `Tainted` and `TurnDecisionRef` are copied from any `Reply`.
- **Finishing (AD-30's order).** `State` becomes "done" and the row is saved. Then:
  1. publish `chat.message`;
  2. send the `Outbound` to `Notify`: `SessionRef`, `OriginChannel` = the turn's `Channel`, `Text`, and for a fallback `CatalogKey` "conversation.turnFallback" with `Slots` `{"fallbackReason": <reason>}`;
  3. if the session has a queued turn, send `RunTurns(SessionRef)` to itself.
- **A stale answer is dropped.** An answer whose instance `Attempt` differs from the row's, or whose row isn't `running`, changes nothing. A reconcile re-run therefore still gives exactly one reply (Decided 7).
- **The recap (AD-10 3a).** It is written by code from the session's done turns before the current one, the 20 most recent, each side cut at 2,000 characters (Decided 8). It uses the user's text and the reply as sent, or `RECAPNOANSWER` for a fallback. It never uses `HostData` or a tool result.
- **The restart (AD-5, AD-23).**
  - `Install.Step.Web.Reconcile()` calls `Conversation.Reconcile()`.
  - With the production running, that sends one empty `RunTurns` through `WebChatIn`.
  - With the production not running, it answers OK and does nothing; the next start reconciles.
- **Live events (AD-12).** `chat.message` = `ChatMessage.FromRow(turn)` on the session's stream, published when the turn is queued, when the decision lands (state `running`) and when the reply lands (`done`). It is published after the row commits. A publish or `Notify` failure is logged with `$$$LOGERROR` and never stops the turn.
- **SQL (AD-13 as amended).** Three new `Ownership` row kinds, each with the owner in its `WHERE`, its fixed SQL, and `TestIsolationEveryRowKind` coverage:
  - `turnByClient` (`oa`);
  - `turnQueue` (`o`, `State IN ('queued','running')`, ORDER BY CreatedAt, ID);
  - `lastReplied` (`o`, `State = 'done' AND TurnDecisionRef IS NOT NULL`, TOP 1, newest first).

  The one cross-session read, the sweep's `SELECT DISTINCT %EXACT(SessionRef) ... WHERE State IN ('queued','running')`, is a checked `%SQL.Statement` in `Conversation`, which runs in a production job. There is no unchecked prepare and no embedded SQL; `ALLOW_UNCHECKED` is unchanged.
- **Code (Rule 14).** Source is ASCII (the cut mark is `$Char(8230)`). Comments state the contract. Use `%Status` throughout. The texts are class parameters.

**Never:**
- **Never edit Lane A** (`src/bridge/**`, `Agent/**`, `Install/**` other than `Install/Step/Web.cls`, `Test/Install/**`), `docker/merge.cpf`, or `test-production.sh`'s Epic 1 fixture check (about `:277-298`).
- **Never build another story's part:**
  - `Notify`'s rule, `WebChatOut` and `Delivery` (2.7);
  - `Trace.Join` (2.9);
  - `BridgeSink` and decision fields on `chat.message` (2.6);
  - the chat panel and an API client call (2.5);
  - the allowance refusal (16.9);
  - `SystemNote` (approved-call notes).
- **Never change** `Submit`, a cross-lane signature pinned in `Test.Contract.Ac`, or `Production.cls`.
- **Never run on slot B:** `ConversationProduction`, `CommandsInProduction`, `Test.Install.Registry`, `Test.Install.Production`, `Test.Demo.Production`, `Test.Live.Publish` or `Test.Web.Install` (Rule 21).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Post | Valid body, signed in | 202 `{clientId}`. The `Item` has a new `ItemId`, the session's `SessionRef`, `web`, `user`, the text, `FromGuide` and `ClientId`, with `SuperSession` = `TraceRef` | — |
| Repeat | Same `clientId`, same session (a done or a queued turn) | 202. Nothing is sent and no new turn is made. Another session with the same `clientId` gets its own turn | Race: `Conversation` drops the second `Item` |
| Bad body | Not JSON, no `clientId`, a `clientId` over 128 characters, empty or space-only `text` | 400 `bad_message`, nothing sent | — |
| Refusal | `TryConsume` answers 0 (a probe; nothing does in 2.4) | Nothing is queued, and `WebChatIn` answers an error status | REST 500 |
| Turn | `Item` with no turn running | Turn queued → running → done. `decide`, then `turn`, each with `ItemId`, `OwnerRef`, `TraceRef`, `Channel`, `Summary` and `ThreadSessionId` = the turn's session. Three `chat.message` events. One `Outbound`. Both `DecisionRef`s stored | — |
| Mid-turn | A second `Item` while T1 runs | T2 is queued and starts only after T1 is done. T2's requests carry T2's own `ItemId` and `Summary`, and T1's carry nothing of T2's (NFR-6) | — |
| Any outcome | `decide` answers ignore, digest, tellnow, act, a fallback, an error status, or a `Reply` | The turn request is still sent, and there is exactly one reply | — |
| Busy | `Reply.Busy` 1 | A 3 s wait and a resend, up to 5 times. The 6th is the fallback `rate_limited` | — |
| Broken | `SessionBroken` | One resend with `fresh` + recap. Broken again: fallback with the reply's reason | — |
| Tainted | T1's `Reply.Tainted` 1 | T2's turn request is `fresh`, and its `SeedText` holds T1's text and reply, never its `HostData`. T3 (after an untainted T2) is `continue` | — |
| Fallback | `Reply` with `Fallback` and each of the 12 reasons; or an error status | `ReplyCatalogKey` `conversation.turnFallback`, `FallbackReason` = the reason (`unusable` for an error status). `Outbound` and `chat.message` carry the key and reason. `Catalog.Render` gives the UX sentence | — |
| Stale | Answer for `Attempt` n after a re-run made it n+1 | Nothing changes, nothing is published, nothing is sent | — |
| Restart | T1 `running`, T2 and T3 `queued`, then a reconcile or a kill and start | T1 runs again, then T2, then T3, each with one reply | Production not running: reconcile answers OK and does nothing |
| Reload | `/state` after a done turn | The chat entry has `text`, `replyText` or `catalogKey`+`fallbackReason`, `clientId` and `traceHeaderId`/`traceNamespace` (DW-61) | — |

</intent-contract>

## Code Map

**Lane B (edit)**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `:48` `/v1/messages` → `NotBuilt`;
  - `CurrentSession` `:301-311` (`Ownership.SessionRef` + `RefIndexOpen`);
  - `Fail` `:363-377` (no 202; set `%response.Status = ..#HTTP202ACCEPTED`);
  - the envelope `OnPreDispatch`/`EnvelopeError` `:63-75`/`:352-360` (already done before any handler);
  - `ChatItems` `:215-248` uses `Ownership.Turns` + `FromRow` and is unchanged.

  Nothing reads `%request.Content` yet. The parameters are at `:27-41`.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- the stub (`STUB` `:7`, error handler `:9-12`).
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` -- the stub BP (`:7`, `:9-12`). Its storage is `<Type>` only.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- 8 properties (storage slots 2-9), `RefIndex` unique and `SessionRefIndex`. New slots start at `Value name="10"`. The global row is `src/short-names.tsv:14`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `Statement` `:232-272` (the fixed kinds; `o`/`a` binds);
  - `Rows` `:184-227` (refuses empty, `instance` or `eval`);
  - `Turns` `:74-77`;
  - `Incident` `:122-129` (the wrapper shape for `rows.GetAt(1)`).
- `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` -- 10 properties. `FromRow` `:37-46` sets 5, and its comment `:35-36` names Story 2.4.
- `src/ocutalon/cls/OcuTalon/Msg/Item.cls` -- 11 properties (slots 1-11, subscript "Item").
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- Lane B's only step class. It has `Purge` `:81` and `Grants` `:89`, and no `Reconcile` (it inherits `Install.Step.Reconcile()` `:30`, OK). `Install.Registry.CallAreas("Reconcile")` calls every step class's.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:18,27` -- `WebChatIn` and `Conversation` have `"stub": 1`.
- `docker/tests/test-production.sh` -- row 16 `:128-152` (header `:12-15`) sends `Ens.StringRequest` to `Conversation` and expects `<Ens>ErrBPTerminated`/#5003. This breaks once it is built. The pool sweep `:156+` reads the oracle and adapts.
- `docker/tests/test-production-restart.sh` -- row 20:
  - the seeding `:120-127` (session A, a done turn, a check, a reminder and an approval);
  - the journal sync `:135`, the kill `:140`, `check_start` `:152`;
  - the snapshot compare `:163+` (A's chat must stay equal).
- `docker/tests/test-sign-in.sh` -- `create_fixture_user` `:68-96`, the env exports `:150-160`. `web/e2e/support/iris.ts:14-15` `fixtureUser('LIVE'|'SESSION'|'SIGNIN')`.
- `web/e2e/api/api.spec.ts`:
  - `MESSAGES` `:49`;
  - `UNBUILT` `:64-65` (lists messages);
  - the envelope tests `:235-279` post `'{}'` to `MESSAGES` and expect 501 for "let through";
  - row 16 `:293-305`; row 17's GET `/messages` 405 at `:310` stays.

  The README account's session is seeded and read by row 14, so the new tests need their own user.
- `web/src/app/live/payloads.ts:71-82` -- generated by `node web/scripts/payloads.mjs` (`--check` fails when stale).

**Tests that pin the old shapes (Lane B, update)**
- `Test/Data/Tables.cls:367-383` -- the Turn contract (types, MAXLEN, indexes); `:80` `TestSqlNames` (Conversation included).
- `Test/Live/Payloads.cls`:
  - `:369-383` -- the ChatMessage contract;
  - `:244-256` -- `TestFromRowBuilders`, where `:256` asserts `ClientId|Text|ReplyText|TraceHeaderId|TraceNamespace` are empty.
- `Test/Msg/Contracts.cls:161` -- the `Item` contract (an exact property list).
- `Test/Web/Api.cls:536-545` -- `TestRoutes` (`:539` "POST /v1/messages NotBuilt"). The helpers are `CallSession` `:644-652`, `Run`, `Written(.sc, class, method, args...)` and `PreDispatch`. `Test/Web/StubRequest.cls:18-28` has no body.
- `Test/Data/Ownership.cls`:
  - `TestIsolationEveryRowKind` `:296-319` (kind list `:304`);
  - `TestRowsRefuses` `:349`;
  - `Seed` `:367-377`;
  - `ReadAll` `:380-395`.
- `Test/Data/Fixture.cls:24` -- `Turn(sessionRef, createdAt, state)` sets no `ItemId` or text. `Adopt(row)` `:159` and `Clean(refs)` `:179` work by Ref; `RemoveMessages` `:207`.
- `Test/Core/CommandsInProduction.cls:266-288` -- the private `Headers(super)` and `Between(...)`, which move to `Fixture` (Rule 2).
- `Test/Install/Production.cls:124-167` (Lane A, read-only) -- `TestStubsAnswer` asserts `STUB` = the oracle's `stub`. `TestDefinition` compares pool and settings, which are unchanged.
- `Test/Install/Registry.cls:186-196` (Lane A, read-only) -- runs the `Reconcile` step, which now calls `Web.Reconcile()`. It must answer OK without a production too.

**Contracts (read-only)**
- `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`:
  - `Kind`, `Provenance`, `Input` (`InputText`), `ItemId`, `Summary`(80);
  - `DecisionRef`, `OwnerRef`, `TraceRef`, `Channel`;
  - `ThreadSessionId` (%Integer), `SessionMode`, `SeedText`, `SystemNote`.

  It has no `SessionRef`.
- `Bridge/Msg/Reply.cls` -- `Text`, `Tainted`, `ToolsRun`, `SessionBroken`, `Busy` and `HostData`, plus `Result`'s `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`; `NewBusy()` `:28`. `DecisionResponse.cls` adds `Payload`.
- `Bridge/Process/Decide.cls` -- `STUB`; `OnRequest` answers `$$$ERROR($$$NotImplemented)`. The caller sees `<Ens>ErrBPTerminated` carrying #5003 (Story 2.3's measurement).
- `Bridge/Ids.cls:7` `NewRef()`. `Agent/Input.cls:7` `Render(item)` returns "" until Story 1.3.
- `Msg/Catalog/Core.cls:157-163` `conversation.turnFallback` "I couldn't answer that: {fallbackReason}. Nothing was changed." (slot `fallbackReason`, no `web` text). The reason keys are `:181-234`; `Msg/Catalog.cls:44` `REASONKEYS` maps `invalid`/`unusable` → generic. `Render`/`RenderAt` `:51`/`:64`.
- `Msg/Enum.cls:15` `FALLBACKREASON`; `:36` `CHANNEL`.
- `Data/Session.cls` -- `Ref`, `TraceRef` `:14`, `RefIndex` `:26`. `Data/Time.cls:15` `NowUtc()`.
- `Live/Publish.cls:52-93` `Publish(stream, type, payload, Output seq)`. It refuses `$TLevel > 0` and a payload class not exactly `Live.Payload.<X>`.
- `Data/Public/Settings.cls:19` `Get("onlineDemo", .sc)`; tests save and restore it as `Test/Web/Api.cls:43,59` does.

**Patterns to follow**
- `Core/Commands.cls:18-37` -- `CreateBusinessService` + `ProcessInput` from a caller's process.
- `Core/CommandsIn.cls` -- the private one-send seam `Send` `:92`; the outside-a-context `SuperSession` from `TraceRef` (`Join` `:119-130`).
- `Test/Core/CommandsInProbe.cls`, `CommandsOwner.cls` -- a probe overrides only the seam, hands the request to a shadow instance of a test host, and records under `^OcuTalonTest(<class>, run, n)`. `CommandsRouting` `NewProbe` uses `Ens.Host.GetShadowInstance("class||<probe>")`.
- `Test/Core/CommandsInProduction.cls` -- a throwaway-only class: the guard, fixture sessions, `zz` SuperSessions and `Fixture.RemoveMessages`.

**IRIS reference (read)**
- `irislib/Ens/BusinessProcess.cls`:
  - `SendRequestAsync` `:160` → `SendRequestAsyncInternal` `:199-233`, which uses `..%SessionId`/`..%SuperSession` at send time (`acceptRequestAsync`);
  - `SetTimer(timeout, key)` `:189` (seconds or `PT3S`);
  - an error answer calls `OnError` `:339`; OK there makes the framework call `OnResponse` (`:425-435`) (inference: with no body);
  - a timer calls `OnTimeout` then `OnResponse` with its key (`:363-378`);
  - completion when nothing is pending `:463-480`. A timer set inside `OnResponse` survives (the "only timers left" clear `:401-415` runs before `OnResponse`).
- `Ens/Host.cls:40,58` -- `%SessionId` and `%SuperSession` are stored BP properties. `Ens/Actor.cls:64-87` -- one job interleaves instances, and a response reopens the stored instance.
- `Ens/BusinessService.cls:97-101,202` -- `preProcessInput` clears the session; a BS's async send has no return queue. `Ens/MessageHeader.cls:70` -- an empty session id gets the header's own id.
- `Ens/Director.cls:393-469` -- a stop puts in-progress and queued async messages back. BP instances waiting on an answer are never resumed by the framework.

## Tasks & Acceptance

**Execution:**
- **Task 0** (implement stage, throwaway `e2s24i`, the first run of `ci/iris.sh class OcuTalon.Test.Core.ConversationProduction` with temporary `MEASURE` assertions removed afterwards; record each under `## Verification`):
  1. **The stub `Decide`'s answer.** Does `Conversation` get `OnError` with `<Ens>ErrBPTerminated`, and then `OnResponse` with no `callresponse`? `Conversation` handles the error path in exactly the one callback that the measurement shows.
  2. **The session.** Is a `..%SessionId` set before `SendRequestAsync` the request header's `SessionId`, and does it survive the reopen for `OnResponse`?
  3. **The self-send.** Does `SendRequestAsync("Conversation", runTurns, 0)` from `Conversation` reach a new instance? If it is refused, the finishing instance starts the next turn itself, and the spec records it.
  4. **The trace target.** Does the `Item` header's ID equal its `SessionId` (there is no Join yet)?
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- append the properties (slots 10-18, compiler-generated storage committed):
  - `ItemId` %String(22);
  - `ClientId` %String(MAXLEN 128, COLLATION "EXACT");
  - `Text` %String(MAXLEN "");
  - `ReplyText` %String(MAXLEN "");
  - `ReplyCatalogKey` %String(128);
  - `FallbackReason` %String(32);
  - `TraceHeaderId` %Integer;
  - `Tainted` %Boolean IE 0;
  - `Attempt` %Integer IE 0.

  Add `Index ItemIdIndex On ItemId [ Unique ]` and `Index ClientIdIndex On (SessionRef, ClientId)`. Why: DW-61, the queue's dedup, and the stale guard.
- `src/ocutalon/cls/OcuTalon/Msg/Item.cls` -- append `ClientId` %String(128) (slot 12): "the page's own id; set only by WebChatIn". Why: the turn keeps it (DW-61).
- `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls`:
  - add `CatalogKey` (`catalogKey`, 128) and `FallbackReason` (`fallbackReason`, 32);
  - `FromRow` also maps `ClientId`, `Text`, `ReplyText`, `ReplyCatalogKey`→`CatalogKey`, `FallbackReason` and `TraceHeaderId`, and sets `TraceNamespace` = `$Namespace` when `TraceHeaderId` is set;
  - rewrite the comment;
  - regenerate `web/src/app/live/payloads.ts` with `node web/scripts/payloads.mjs`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the three kinds to `Statement` with the SQL in Boundaries. Add the wrappers:
  - `TurnByClient(sessionRef, clientId, .sc) As Turn` ("" for an empty `clientId` or no row);
  - `TurnQueue(sessionRef, .sc) As %ListOfObjects`;
  - `LastRepliedTurn(sessionRef, .sc) As Turn`.
- `src/ocutalon/cls/OcuTalon/Core/Allowance.cls` (new) -- `TryConsume` as in Boundaries. The comment says that Story 16.9 adds the count and the refusal.
- `src/ocutalon/cls/OcuTalon/Core/Msg/RunTurns.cls` (new, `Ens.Request`, storage committed) -- `SessionRef` %String(22); "" means every session.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Post.cls` (new, `%RegisteredObject`) -- `SessionRef`, `ClientId`, `Text`, `FromGuide`.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- build it as in Boundaries, and delete `STUB` and the stub handler.
  - The private seams are `Send(target, request) As %Status` (`SendRequestAsync(target, request, 0)`) and `Allowed(sessionRef, channel, text, .retryAt, .firstRefusal) As %Boolean` (`Allowance.TryConsume`).
  - Any other input, or a `Post` with an empty session, `ClientId` or text, answers an error status and sends nothing.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` -- build it as in Boundaries, and delete `STUB` and the stub handler.
  - **Persistent properties** (storage committed): `TurnRef`, `Attempt`, `BusyRequeues`, `BrokenRetried` and `CallError` (%Status).
  - **Parameters:** `DECIDE` "Decide", `NOTIFY` "Notify", `BUSYWAIT` 3, `BUSYMAX` 5, `FALLBACKKEY` "conversation.turnFallback", `RECAPTURNS` 20, `RECAPCHARS` 2000, `RECAPHEAD` "This conversation so far, as OcuTalon recorded it (the user's messages and OcuTalon's replies as sent):", `RECAPUSER` "User: ", `RECAPREPLY` "OcuTalon: ", `RECAPNOANSWER` "(OcuTalon couldn't answer this message.)".
  - **`OnRequest`:** `Item` or `RunTurns`; any other class answers an error status and changes nothing.
  - **`OnResponse`/`OnError`** key on `decide`, `turn` and `busy`. They read only the instance's own properties and `callresponse`, never `request`, so the probe can drive them.
  - **Private seams:** `Send(target, request, responseRequired, key) As %Status` (`SendRequestAsync`) and `Wait(seconds, key) As %Status` (`SetTimer`).
  - **`ClassMethod Reconcile() As %Status`:** as in Boundaries.
  - **`Recap(sessionRef, turnRef) As %String`**, through `Ownership.Turns`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `ClassMethod Reconcile() As %Status` returns `##class(OcuTalon.Core.Conversation).Reconcile()`. Its comment says that Lane B's areas reconcile here.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - route `/v1/messages` POST → `Messages`;
  - add `MESSAGEBADMESSAGE`;
  - `Messages()` validates the body (REST in Boundaries), builds a `Post` with `SessionRef` from `CurrentSession`, and calls the private `ClassMethod Post(input, Output output) As %Status` (`CreateBusinessService("WebChatIn")` + `ProcessInput`), then answers 202, 400 or 500.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` -- `WebChatIn` and `Conversation` get `"stub": 0`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - `Turn(sessionRef, createdAt, state, text = "", clientId = "", attempt = 0)` always sets `ItemId` = `NewRef()`;
  - add the public `Headers(superSession)` and `Between(headers, type, source, target)`, moved from `CommandsInProduction`, which then calls them.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls` (new, `Ens.BusinessProcess`, storage committed, no Test methods) -- the `Decide` stand-in, reused by Stories 2.7 and 2.9.
  - **Recording:** `OnRequest` records each request's fields under `^OcuTalonTest("DecideDouble", OwnerRef, "seen", n)`.
  - **Answering:** it pops the next scripted answer for (`OwnerRef`, `Kind`):
    - `decide`: `tellnow`/`act`/`ignore`/`digest`, `fallback:<reason>`, `error`;
    - `turn`: `reply`, `tainted` (with `HostData` `{"zz":"tool result"}`), `busy` (`NewBusy()`), `broken` (`SessionBroken` 1, `Fallback` 1, `error`), `fallback:<reason>`, `error`, `wrong` (an `Ens.StringResponse`);
    - with an empty script: `tellnow` or `reply`.
  - Every non-busy answer carries a new `DecisionRef`.
  - **Helpers:** `Script(ownerRef, kind, answers As %List)`, `Seen(ownerRef) As %DynamicArray` and `Clear(ownerRef)`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls` (new, extends `Conversation`, transient properties only, no Test methods) -- it overrides `Send` and `Wait`:
  - each records;
  - a `Decide` request goes to a shadow `DecideDouble`, and its answer is kept;
  - `Deliver()` hands the kept answers, and a timer's `Ens.AlarmResponse`, to `OnError`/`OnResponse` as the framework does (the Task 0 form);
  - sends to `Conversation`/`Notify` are recorded only.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatInProbe.cls` (new, extends `WebChat.In`, no Test methods) -- overrides `Send` (records the request and `..%SuperSession`) and `Allowed` (a refusal mode).
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` (new, `%UnitTest`, slot-safe) -- fixture sessions; it ends the bridge context, cleans its `^OcuTalonTest` runs and the double's scripts, and calls `Fixture.Clean` (turns adopted). The tests:
  - `TestTurnRows`;
  - `TestDecideThenTurn`;
  - `TestStagesPublished`;
  - `TestEveryTriageOutcomeRuns`;
  - `TestSecondMessageWaits` (NFR-6);
  - `TestBusyRequeues`;
  - `TestBrokenRetriedFresh`;
  - `TestTaintedNextFresh`;
  - `TestRecapFromTurnRows`;
  - `TestEveryFallbackReason` (the 12 reasons, the error status and `wrong`). Each renders the `Outbound`'s key and slots through `Catalog.RenderAt(..., "web", ...)` and compares the AC's exact sentence;
  - `TestDuplicateItemDropped`;
  - `TestUntrustedItemRefused`;
  - `TestStaleAnswerDropped`.

  The sweep (an empty `RunTurns`) is tested only on throwaways (`TestReconcileResumesTurns`, restart row 20), because it re-queues every session's `running` turns, not only the test's own.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatMessages.cls` (new, `%UnitTest`, slot-safe) -- the tests:
  - `TestBuildsItem`;
  - `TestRepeatClientId` (same session and another session);
  - `TestRefusalQueuesNothing`;
  - `TestBadPostRefused`;
  - `TestRunTurnsForwarded`;
  - `TestAllowanceAllowsWithFlagOff` (60 calls, `onlineDemo` saved and restored).
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls` (new, `%UnitTest`, THROWAWAY AND CI ONLY; the same guard as `CommandsInProduction`; it removes its turns, events, messages and double scripts). The tests:
  - **`TestTurnThroughProduction`** (Integration AC). A `Post` goes through `CreateBusinessService("WebChatIn")`, and the turn reaches `done` within 20 s. Then:
    - the row has the text, `ClientId`, `ItemId`, `TraceHeaderId` = the `Item` header, `conversation.turnFallback` and `unusable`;
    - the session stream holds three `chat.message` events (`queued`, `running`, `done`);
    - the `Item`, two `Decide` requests (`decide` and `turn`, `ThreadSessionId` = the `Item`'s session) and one `Outbound` to `Notify` (key and slots) all have `SuperSession` = `TraceRef`.
  - **`TestRepeatQueuesNothing`.**
  - **`TestTurnsRunInOrder`:** three posts; the `Decide` `turn` requests come in the posts' `ItemId` order, and each turn has one `done` event.
  - **`TestReconcileResumesTurns`:** fixture T1 `running`, T2 and T3 `queued`; then `Install.Step.Web.Reconcile()`. All three reach `done`, in order, each with one `done` event and one `turn` request.
- `src/ocutalon/cls/OcuTalon/Test/Web/ApiProbe.cls` (new, extends `Web.Api`) -- overrides `Post` to call a shadow `WebChatInProbe`.
- `Test/Web/StubRequest.cls` -- gains `MakeBody(application, json)`, which sets `Content` to a character stream.
- `Test/Web/Api.cls`:
  - `TestRoutes` expects "POST /v1/messages Messages";
  - add `TestMessagesAccepted` (202 body; the probe saw the CSP session's ref, not the body's `sessionRef`; `fromGuide`);
  - add `TestMessagesRepeat`;
  - add `TestMessagesBadBody` (each bad row, 400 `bad_message`, nothing sent);
  - add `TestMessagesServerError`.
- `Test/Data/Ownership.cls` -- the three kinds join `TestIsolationEveryRowKind`, `Seed`, `ReadAll` and `TestRowsRefuses`. Add `TestTurnByClient`, `TestTurnQueueOrder` and `TestLastRepliedTurn`.
- `Test/Data/Tables.cls` (the Turn contract), `Test/Live/Payloads.cls` (the ChatMessage contract, and `TestFromRowBuilders` now asserts each mapped field), `Test/Msg/Contracts.cls` (the `Item` contract) -- update to the new shapes.
- `Test/Contract/Ac.cls` -- pin `OcuTalon.Core.Allowance.TryConsume(sessionRef,channel,text,*retryAt,*firstRefusal) As %Boolean` (a new cross-lane API: Story 12.6's `TelegramIn`).
- `docker/tests/test-production.sh` row 16 -- `Conversation` → `Intake` (still a stub process, until Story 2.7) in the list, the regex, the job check and the header `:12-15`.
- `docker/tests/test-production-restart.sh` row 20:
  - **Before the journal sync:** seed fixture session B with T1 `running` (Attempt 1) and T2 `queued`, each with text.
  - **After the next start:** within 60 s both are `done`, each with `conversation.turnFallback` and exactly one `done` `chat.message` on B's stream, T1's `Seq` below T2's.
  - **Then:** clean B. Session A's snapshot check is unchanged.
- `docker/tests/test-sign-in.sh`, `web/e2e/support/iris.ts` -- a `CHAT` fixture user (`OCUTALON_CHAT_USER`, user role).
- `web/e2e/api/api.spec.ts`:
  - **Existing tests:** messages leaves `UNBUILT`, and the envelope tests post to `/ocutalon/api/v1/demo/break-feed` instead.
  - **New, as the `CHAT` user (Integration AC, Rule 3):**
    - POST `/messages` → 202 `{clientId}`;
    - GET `/events` from `/state`'s cursor shows `chat.message` for that `clientId` reaching `done` with `catalogKey` `conversation.turnFallback` and `fallbackReason` `unusable` within 20 s;
    - a repeat POST → 202 and no second turn;
    - a GET `/state` shows the turn with its text;
    - `{}` → 400 `bad_message`.

**Acceptance Criteria:**
- **Post (AD-1, AD-14, AD-30).**
  - **Given** a signed-in page, **when** `POST /api/v1/messages` arrives with `clientId`, `text` and `fromGuide`, **then** it answers 202, and `WebChatIn`, through `CreateBusinessService` and `ProcessInput`, sends `Conversation` an `Item` with a new `ItemId`, the session's `SessionRef`, `web`, `user`, the text, `FromGuide` and `ClientId` (`TestBuildsItem`, `TestMessagesAccepted`, `TestTurnThroughProduction`, the API spec).
  - A repeated `clientId` from the same session answers 202 and queues nothing new (`TestRepeatClientId`, `TestRepeatQueuesNothing`, the API spec).
- **Allowance (AD-20).** **Given** a message, **when** `WebChatIn` handles it, **then** it calls `Allowance.TryConsume` before queueing, a refusal queues nothing, and `TryConsume` allows every message while the online-demo flag is off (`TestRefusalQueuesNothing`, `TestAllowanceAllowsWithFlagOff`).
- **Turn.**
  - **Given** `Conversation` receives the `Item`, **when** the turn runs, **then**:
    - it queues a `Turn` (`queued`, `running`, `done`) with `Channel` and `FromGuide`;
    - it calls `Decide` `decide` (provenance `user`), then `turn`, with `ThreadSessionId` = its trace session;
    - it stores both `DecisionRef`s;
    - it sends one `Outbound` with `OriginChannel` to `Notify`
    
    (`TestDecideThenTurn`, `TestTurnRows`, `TestTurnThroughProduction`).
  - `chat.message` is published when the turn is queued, when the decision lands and when the reply lands (`TestStagesPublished`, `TestTurnThroughProduction`).
  - A message sent mid-turn becomes its own turn and reaches the model as its own message (`TestSecondMessageWaits`).
- **Reply shapes (AD-6, AD-8, AD-10).** **Given** `Decide` answers `Busy`, `SessionBroken` or `Tainted`, **when** `Conversation` handles it, **then**:
  - `Busy` waits 3 s and resends at most 5 times, then falls back with `rate_limited`, while an error status falls back at once;
  - `SessionBroken` is retried once `fresh` with a code-written recap;
  - after `Tainted` the next turn is `fresh` with a recap built from `Turn` rows, never from tool results
  
  (`TestBusyRequeues`, `TestBrokenRetriedFresh`, `TestTaintedNextFresh`, `TestRecapFromTurnRows`).
- **Fallback (FR-4, AD-8, AD-32).** **Given** a fallback reply or an error status, **when** the turn finishes, **then** the `Outbound`, the row and `chat.message` carry `conversation.turnFallback` and the reason, and `Catalog.Render` gives "I couldn't answer that: {reason}. Nothing was changed." with `{reason}` in these words. `TestEveryFallbackReason` writes the oracle out and never reads it from the catalog:
  - `timeout` "the model didn't answer within 60 seconds";
  - `empty` "the model's reply was empty";
  - `cut_off` "the model's reply was cut off";
  - `refusal` "the model declined to answer";
  - `error` "the model returned an error";
  - `rate_limited` "the model was busy and retries ran out";
  - `budget` "this would have gone over the token budget";
  - `too_large` "this request would have been too large to send";
  - `daily_cap` "today's cost limit has been reached";
  - `no_key` "no model key is set";
  - `invalid`, `unusable` and an error status "the model's reply couldn't be used".

  Whatever the attention decision's outcome, the turn gets exactly one reply (`TestEveryFallbackReason`, `TestEveryTriageOutcomeRuns`).
- **Restart (FR-6, NFR-16, AD-5, AD-30).** **Given** turns queued or running, **when** IRIS or its container restarts, **then** queued turns run in order and a turn left running runs again, each with one reply (`TestReconcileResumesTurns`, `test-production-restart.sh` row 20, `TestStaleAnswerDropped`).
- **DW-61 (Story 2.2's snapshot).** **Given** a done turn, **when** `/state` loads after a reload, **then** its chat entry carries the text, the reply as sent (or the fallback key and reason), the `clientId` and the trace target (`TestFromRowBuilders`, the API spec).
- **Built, isolated.** **Given** the oracle, **when** `Test.Install.Production` runs, **then** `WebChatIn` and `Conversation` carry no `STUB`. Every new row kind returns none of another session's rows (`TestStubsAnswer`, `TestIsolationEveryRowKind`).

## Spec Change Log

- 2026-10-22, spec validation (lead): the veto-window items are ruled as planned (inbox U-20): the `Turn` and `Msg.Item` schema additions and the `bad_message` text. The spine's Conventions REST row gains `bad_message` (Rule 20, light path). DW-61 is addressed, and no decision-pending entry is built on.

## Review Triage Log

### 2026-10-22 - Review pass
- verdicts: 46 findings - high 0, medium 14, low 27, false 5, maybe-false 0. Four layers reported: blind-hunter (15 rows: 7 items, those with several claims split), edge-case-hunter (15), verification-gap (12: 5 gaps and 7 other findings), intent-alignment (4 divergences; the layer is descriptive). Rows that share a root cause share a route.
- findings:
  - `[medium]` `[patch]` A turn can be left `running` when `Begin` (Join, Request, Agent.Input.Render) throws on the OnRequest path - `Begin` is now inside a Try that logs and calls `Abandon`; `TestBeginFailureEndsTurn` (mutation line recorded).
  - `[low]` `[reject]` `Start`'s lock timeout after `Take` saved the turn leaves a queued turn with no RunTurns - the lock is held for milliseconds and waited on for 5 s, the next message or the sweep starts the turn, and a retry adds a new loop; reopen_if a `ERRORBUSY` line appears in a production's event log.
  - `[low]` `[reject]` No watchdog for a Decide answer that never comes - the queue is persistent, an error in Decide returns an error response, and a stop re-queues in-progress messages; AD-6 puts the model timeout in Decide; reopen_if a turn is seen `running` with no Decide message in flight.
  - `[medium]` `[defer]` Nothing runs the Reconcile declarations on an IPM autostart or a production-only restart - AD-23's trigger is Lane A's (Production and Registry), the spec adds only `Web.Reconcile()`; deferred item 1.
  - `[low]` `[reject]` The message text has no maximum length - Decide answers `too_large` for a request it cannot send, the web request and the long-string limit bound a post, and a cap needs its own user-facing text (a veto item); reopen_if Story 2.5's input limit or Story 16.9's allowance fixes a number.
  - `[medium]` `[patch]` `WebChatIn.Accept`'s send-failure branch had no test (the Api test replaces `Post` whole) - `TestSendFailureAnswersError` uses `FailSend`; mutation line recorded. `PendingCount` stays as a harmless helper.
  - `[medium]` `[patch]` An exception inside `OnResponse` (the Catch and `Abandon`) was untested - `ThrowIn` "decided" and `TestCallbackFailureEndsTurn`; mutation line recorded.
  - `[low]` `[reject]` A failed `SetTimer` and `Requeue` returning -1 have no failure mode in the probe - each is a three-line branch that ends in the fallback or a log line; reopen_if the timer or the lock code changes.
  - `[medium]` `[patch]` `Conversation.Reconcile` with no production was tested nowhere (matrix row Restart, error handling) - `TestReconcileWithoutProduction`, skipped where a production runs; mutation line recorded. The error branch with a production running stays throwaway-only.
  - `[low]` `[patch]` `^OcuTalonTest("ApiProbe","mode")` survives an aborted run - `Test.Web.Api.OnBeforeAllTests` clears it.
  - `[low]` `[reject]` `ConversationProduction` does no `Fixture.Clean` up front - it runs in a fresh throwaway and removes its own rows afterwards; reopen_if an interrupted run is seen to leave rows in a reused stack.
  - `[low]` `[reject]` `ConversationTurns.Session()` also resets the probe's records - its comment says so and no test creates a session after it has recorded calls.
  - `[low]` `[patch]` The `DecideDouble` header said every non-busy answer carries a DecisionRef - reworded to the DecisionResponse and Reply it makes.
  - `[low]` `[patch]` `test-sign-in.sh` called the chat user "a fifth user" - reworded to "a further user".
  - `[low]` `[patch]` The comment above `UNBUILT` in `api.spec.ts` did not name messages as built - reworded.
  - `[medium]` `[patch]` Edge case: `Begin` has no Try/Catch - same root as the first row, patched with it.
  - `[low]` `[reject]` Edge case: `Conclude`'s `%Save` can fail and leave the row `running` - a save of an unconstrained row fails only on a disk or lock fault, where the sweep resumes it; a retry timer is new machinery; reopen_if a `%Save` error is logged from `Conclude`.
  - `[low]` `[reject]` Edge case: `Start` returns an error after the Item was queued - same as the lock-timeout row.
  - `[low]` `[reject]` Edge case: the self-send of RunTurns fails after a turn is done - the target is this running item; reopen_if `Again` logs an error.
  - `[low]` `[reject]` Edge case: a running turn has no age check - same as the watchdog row.
  - `[low]` `[reject]` Edge case: a poison turn is requeued by every sweep with `Attempt` growing - needs a job-killing fault on one turn; an attempt cap would be a new fallback rule; reopen_if a turn's `Attempt` passes 3 in a real install.
  - `[low]` `[reject]` Edge case: an empty `SessionRef` makes the sweep throw on a null subscript - `Take` refuses an Item with no session and no code writes such a row; a guard adds a branch for a corrupt row; reopen_if a row with an empty `SessionRef` is found.
  - `[low]` `[patch]` Edge case: `AfterTaint` ignored a failed read and counted it untainted - it now counts it as tainted (fresh session with the recap); `TestTaintReadFailureStartsFresh`, mutation line recorded.
  - `[false]` `[reject]` Edge case: a `Reply` with no fallback and empty Text gives a blank Outbound - Decide classifies an empty reply as the fallback `empty` (AD-8) and Conversation must not classify; the blank reply needs a Decide that breaks AD-8.
  - `[low]` `[reject]` Edge case: a failed send after `Allowed` would consume the allowance once Story 16.9 counts - the order is the spec's (step 2 before steps 3 and 4), a duplicate returns before `Allowed`, and a refund belongs to Story 16.9's count; reopen_if Story 16.9 counts at `TryConsume`.
  - `[low]` `[reject]` Edge case: no upper bound on the text - same as the text-length row.
  - `[false]` `[reject]` Edge case: a failing `Reconcile` stops the installer's later steps - `CallAreas` reports a failing area in the step's result for every area, as for `ReminderTimer` and `ApprovalHold`; a production that runs and cannot create `WebChatIn` is broken, and Decided 18 records that.
  - `[medium]` `[patch]` Edge case (claim): Conversation does not turn every failure into the fallback - covered by the `Begin` guard; the `Conclude` and `Start` rows are rejected above.
  - `[medium]` `[defer]` Edge case (claim): the reconcile runs only from the installer - same as the IPM-autostart row, deferred item 1.
  - `[false]` `[reject]` Edge case (claim): `lastReplied` hides a tainted reply with no `TurnDecisionRef` - Decided 9 sets the rule, and every non-Busy answer of Decide carries a `DecisionRef` (`Result`).
  - `[medium]` `[patch]` Verification gap: the model-input assertions compare "" with "" (`Render` is a stub), so nothing observes `ItemOf` - `TestItemOfCarriesTheRow` through `ItemFor`; mutation line recorded.
  - `[medium]` `[patch]` Verification gap: the 80-character cut of `Summary` has no test - `TestSummaryCut`; mutation line recorded.
  - `[medium]` `[defer]` Verification gap: the Busy resend runs only against a probe that replaces `SetTimer` - needs the real Decide or a Decide double in a test production; deferred item 2.
  - `[medium]` `[patch]` Verification gap: the Catch in `OnResponse` and `Abandon` have no test - same as the exception row, patched with it.
  - `[low]` `[defer]` Verification gap: the hop from `Allowed` to `TryConsume` is unobserved while `TryConsume` is a constant - deferred item 3, Story 16.9.
  - `[medium]` `[patch]` Other: `ConversationProduction` reads the Notify headers after the `done` event, which comes before the Outbound is sent - `WaitNotices` polls for the header.
  - `[low]` `[reject]` Other: the production tests hard-code the Epic 0 stub's fallback `unusable` - the spec's ACs name it, and Story 1.3 (Consumed-by) updates them to the mock; reopen_if Story 1.3 lands with these tests unchanged.
  - `[low]` `[patch]` Other: the last assertion of `TestRefusalQueuesNothing` could not fail on a leftover - it now checks the output is a new message and that it is sent.
  - `[low]` `[reject]` Other: the `api.spec.ts` chat tests depend on each other - they are a serial describe by design, as a chat is a sequence; the unit classes are order-free.
  - `[low]` `[patch]` Other: probe state left behind by an aborted run - same as the `ApiProbe` row.
  - `[false]` `[reject]` Other: pinning tests with no `mutation:` line - every AC has a recorded mutation with a named red test; the sub-claims are not per-assertion requirements (Rule 19), and the new tests have their lines.
  - `[medium]` `[patch]` Other: no catch on the OnRequest path - same root as the first row.
  - `[false]` `[reject]` Intent alignment: the non-error reply shapes are driven only through the probe's emulation of the framework - Decided 5; the auditor compared the emulation with `Ens.BusinessProcess` and found it matches; the real error path runs in `ConversationProduction`.
  - `[low]` `[reject]` Intent alignment: the real `Web.Api.Post` error branch and the refusal-to-500 chain are tested in two pieces - the branch is a pass-through of the status; reopen_if `Post` gains logic.
  - `[low]` `[reject]` Intent alignment: the sweep and `Requeue` are not unit-tested on a slot - the spec limits them to throwaways because they re-queue every session (`TestReconcileResumesTurns`, restart row 20).
  - `[low]` `[reject]` Intent alignment: a `SessionBroken` reply's `Tainted` and `TurnDecisionRef` are not kept when the retry then ends in an error status - an error status leaves no reply to copy from, and a second reply sets its own; reopen_if a broken first reply is seen to carry a Tainted flag that the retry hides.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-1:** `WebChatIn` is the business service into the production.
- **AD-4:** the session only from `Ownership`.
- **AD-5:** state in `Turn` rows; append-only storage; the reconcile.
- **AD-6:** async `Decide` calls, `Busy`, serialized turns, the request fields.
- **AD-8:** `Decide` alone classifies replies; `SessionBroken`.
- **AD-10 3a:** the fresh session and its recap.
- **AD-12:** full-view payloads, after the commit.
- **AD-13 as amended:** the three row kinds with isolation tests, and only a checked statement for the sweep.
- **AD-14:** the `Item` and `Outbound`.
- **AD-20:** `TryConsume`; the `Turn` stores two `DecisionRef`s, never a total.
- **AD-22:** tests under `Test.Core`, throwaway-only live classes.
- **AD-23:** the `Reconcile()` declarations.
- **AD-26:** `SuperSession` = `TraceRef`, `ThreadSessionId`, the trace target on the row.
- **AD-29:** the `Agent.Input` and `Decide` stubs.
- **AD-30:** the pipeline.
- **AD-32:** producers never render; the fallback key.
- **AD-33:** Lane B owns these items, `Turn` and `chat.message`.
- **Conventions rows:** Messages, Identifiers, Times, REST, Live events, Text OcuTalon sends, Logging and errors, Tests.

No AC contradicts an AD's Rule. Rule 5: no NFR here is unmeasurable as worded.

**Decided in-stage** (small and reversible, within the intent):
1. **The attention decision never stops the turn.** "Whatever outcome the attention decision carries, the turn runs" and AD-30's fixed sequence say so, so a `decide` fallback or error still sends the `turn` request. "A turn's decision or reply is a fallback" is read as the `turn` result: its `Reply` and its `Decision` row.
2. **An error status, no answer or a wrong class becomes `unusable`.** The slot must be a `FALLBACKREASON` value, and the AC words it "the model's reply couldn't be used". The catalog's `error` ("the model returned an error") is for the model's own error.
3. **Stages by `state`.** The three publishes are `queued`, then `running` (published only when the decision lands), then `done`. Story 2.5 shows "Deciding…" until `running` arrives. No `running` is published at the start of a turn.
4. **The refusal path is Story 16.9's.** In 2.4, `TryConsume` never refuses. `WebChatIn` queues nothing on a refusal and answers an error status (REST 500), so a refusal can't run a turn. Story 16.9 turns this into the 429 with `retryAt`, the refused `Turn` and the notice. No new 429 text is written.
5. **The double sits behind the send seam.** It does not replace the `Decide` item, so the unit classes run on slot B with no production, as in Story 2.3. The real Interoperability path runs in `ConversationProduction` against Epic 0's stub. The double is an `Ens.BusinessProcess`, so Stories 2.7 and 2.9 can also put it in a throwaway production.
6. **The reconcile enters through `WebChatIn`.** AD-1 says that code outside the production sends through a business service. `WebChatIn` already sends to `Conversation`, so this needs no new item or verb. A `RunTurns` carries no text and no session. A `CommandsIn` verb was rejected because it would mean a new cross-lane verb class and a change to 2.3's table.
7. **The stale guard.** A sweep can catch a turn that started between the `Production` step and `Reconcile`. The bumped `Attempt` drops the old instance's answers, so the user gets exactly one reply; the cost is at most one extra model call, and only in that window.
8. **Recap bounds.** It keeps the 20 newest turns, each side cut at 2,000 characters with `$Char(8230)`: about 80,000 characters at most, under the 40,000-token compaction line. A fallback reply shows as `RECAPNOANSWER`. The recap is model-facing, not shown to the user.
9. **`lastReplied` skips turns with no reply decision.** That covers error-status fallbacks and Story 16.9's refused turns, so a tainted turn's flag can't be hidden behind them.
10. **The checked sweep statement.** The sweep is the only read across sessions, so it can't be an `Ownership` kind, which requires an owner. It runs in `Conversation`'s production job, never in REST.
11. **`ClientId` uses exact collation.** It is the page's own id and compares exactly.
12. **The trace target is the `Item` header.** It is the user's message, where Story 2.9's turn link opens. `TraceNamespace` is the running namespace, so it isn't stored.
13. **The error path is one callback pair.** Task 0 measured it (see `## Verification`): the framework calls `OnError` with the `<Ens>ErrBPTerminated` status and then `OnResponse` with no `callresponse`. `OnError` only keeps the status in `CallError` and answers OK; `OnResponse` does the work and reads `CallError` (`Decided` clears it, `Replied` reads and clears it). A turn never depends on `callresponse` being empty: a stored error always wins.
14. **Sends and callbacks never strand a turn.** A decide send that fails is handled as an error answer (the turn request is still tried); a turn send that fails, a failed `SetTimer` and an exception inside `OnResponse` give the fallback `unusable` (the exception only while the instance is not stale). `Next`, `Tell` and `Announce` log a failure and go on.
15. **`WebChatIn` answers a JSON text.** The output is the string `{"accepted":1,"duplicate":0|1}`, not an object, so the service's IO log and `ProcessInput` handle it as any string; a `RunTurns` forward has an empty output. Its private `Send` calls `SendRequestAsync(target, request)`: in `Ens.BusinessService` the third argument is a description, not "response required", so the spec's `, 0` is left out.
16. **"A non-space character" means after `$ZStrip(text, "<>WC")`.** Measured on build 154: `W` alone leaves a line feed or carriage return, so the check also strips control characters at both ends. `Conversation` (an `Item` with only white space has no text), `WebChatIn` and `Messages` use the same test.
17. **`Summary` and the recap cut.** The `Summary` strips leading white space and line breaks first, then takes the first line; a line over 80 characters is cut to 79 and the cut mark (80 in all). A recap side over 2,000 characters is cut to 1,999 and the cut mark (2,000 in all).
18. **`Reconcile` returns an error status** when the production runs but `CreateBusinessService("WebChatIn")` or `ProcessInput` fails (a start that cannot resume the turns says so); with no production running it answers OK and does nothing.
19. **Test seams.** `ConversationProbe` also has `Deliver(max)` (hand over at most `max` kept answers), `PendingCount()` and `FailTarget` (a target whose send fails); `WebChatInProbe` has `Refuse` and `FailSend`; `ApiProbe.Post` reads `^OcuTalonTest("ApiProbe","run")` and `"mode"` (`fail` answers an error status). `ApiProbe`'s override of the private class method `Post` is reached through `Messages` (measured: `..Post` in a class method is resolved against the class that was called). Extra tests: `TestStagesInOrder` (a turn waiting behind another), `TestSendFailuresNeverStrandTurn`, `TestTurnByClient`-style Ownership tests as listed, and a tainted-reply segment in `TestRecapFromTurnRows` (the recap never holds the `HostData`).
20. **`Begin` and `AfterTaint` (review patches).** `Begin` runs its trace step and its decide send inside a Try; a failure there is logged and ends the turn with the fallback `unusable` through `Abandon`, as a failure inside `OnResponse` already does, so a started turn is never left `running` by an exception on the `OnRequest` path. `AfterTaint` counts a failed read of the last replied turn as tainted: the safe direction is a fresh session with the recap.
21. **Review-pass tests.** `ConversationTurns` gains `TestBeginFailureEndsTurn`, `TestCallbackFailureEndsTurn`, `TestItemOfCarriesTheRow`, `TestSummaryCut`, `TestTaintReadFailureStartsFresh` and `TestReconcileWithoutProduction` (skipped where a production runs); `WebChatMessages` gains `TestSendFailureAnswersError`. `ConversationProbe` gains `ThrowIn` (`join`, `decided`), `ItemFor` and `FreshAfter`. `Test.Web.Api` clears `^OcuTalonTest("ApiProbe")` before its tests, and `ConversationProduction` waits for the Outbound's request header before it reads the headers (`Conversation` sends the Outbound after it saves the turn and publishes its last event).

**Veto-window items for the lead** (ruled at spec validation: kept as planned, veto inbox U-20; the implement stage builds as planned unless the owner reverses it):
1. **A change to how stored data is kept (schema, AD-5; Lane B tables by AD-33).**
   - **`OcuTalon.Data.Turn`** gains `ItemId`, `ClientId`, `Text`, `ReplyText`, `ReplyCatalogKey`, `FallbackReason`, `TraceHeaderId`, `Tainted` and `Attempt` (slots 10-18), and `ItemIdIndex` (unique) and `ClientIdIndex`.
     - Storage impact: each turn row also holds the user's text and the reply as sent (in practice the reply is bounded by the 8,000-token output cap, about 32 KB). The rest is two refs and small fields.
     - Old rows: before this story only test fixtures wrote `Turn`, so no install holds rows to migrate or index.
   - **`OcuTalon.Msg.Item`** (a Lane B message class) gains `ClientId` (slot 12). This is an addition; the `Test.Contract.Ac` pins still hold.
   - **New stored message and process classes:** `Core.Msg.RunTurns` (`SessionRef`), and `Conversation`'s instance properties (`TurnRef`, `Attempt`, `BusyRequeues`, `BrokenRetried`, `CallError`).
   - **The `chat.message` JSON** gains `catalogKey` and `fallbackReason`. These are kept only inside `Live.Event` payloads.
2. **Public-facing text not in the UX or PRD.** The REST 400 code `bad_message` with "A message needs a clientId and some text." It is one parameter.

**Spine notes for the lead (Rule 20, light path).** Ruled at spec validation: the lead wrote the Conventions REST row's `bad_message` code into the spine (veto U-20). The turn-queue reconcile note carries no new rule (AD-30's restart criterion already requires it), so it is left out:
- the Conventions REST row's 400 codes gain `bad_message`;
- AD-30 or AD-5 could note that Lane B's turn queue reconciles from `Install.Step.Web.Reconcile()` through `WebChatIn` (Decided 6).

AD-13 needs no change: its amendment already provides for new row kinds.

**Integration ACs (Rule 1).**
- **`Web.Api` `POST /messages`** (consumer) → `WebChatIn` → `Conversation`. The page's live path shows the turn reach `done` with its fallback reply in `/events` and `/state` (API spec, real HTTP on a throwaway).
- **`Install.Step.Web.Reconcile`** (consumer) → `Conversation`. Turns resume after a real kill and start (`test-production-restart.sh` row 20).
- **`WebChatIn`** (consumer) → `Allowance.TryConsume` (`TestTurnThroughProduction`).

**Consumed-by:**
- **1.3 (Lane A):** the real `Decide` and `Agent.Input` replace the stubs, and the same tests then reach the mock.
- **2.5:** the chat panel posts with `clientId` (Retry sending reuses it) and renders `chat.message` and `/state`, including `catalogKey` and `fallbackReason`.
- **2.6:** it adds the decision link and `Checks.Render`'s key and rows to `Outbound` and `chat.message`; `TurnCost` uses the `Turn`'s two refs.
- **2.7:** `Notify` routes the `Outbound`, `WebChatOut` records `Delivery`, and `Intake`'s tests reuse `DecideDouble`.
- **2.9:** `Trace.Join` goes in `WebChatIn` before its send; `TraceHeaderId` is the link target; the double gains decision and `AgentStep` messages.
- **12.6 (Lane A):** `TelegramIn` sends `Item`s to `Conversation` and calls `TryConsume` (pinned).
- **16.9:** the refusal, the refused `Turn` and the 429.
- **The guide stories:** `fromGuide`.
- **3.x:** `SystemNote` for approved calls.

**Consumes:**
- `Ownership`, `Session`, `Live.Publish`, `ChatMessage` and `Fixture` (Stories 0.5 and 2.2);
- the `Bridge.Msg` request and answers, `Ids.NewRef` and `Agent.Input` (0.4);
- `Msg.Catalog` (0.9);
- the `Decide` stub, the production and its oracle (0.6);
- the installer registry and `Reconcile` step (0.2).

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `ConversationProbe`, `WebChatInProbe` and `ApiProbe` follow `CommandsInProbe`; `DecideDouble` follows `CommandsOwner`.
- The new row kinds extend `Ownership`'s fixed table, and `Fixture.Turn` gains arguments.
- `Headers`/`Between` move from `CommandsInProduction` into `Fixture`.
- Copy, with its reason: `WebChatIn` sets `..%SuperSession` from `TraceRef` (two lines, like `CommandsIn.Join`'s outside-a-context branch), because `CommandsIn.Join` is a private method of another item and Story 2.9's `Trace.Join` replaces both.
- There is no recap builder to reuse: `Bridge.Compaction` has only the prompt.

**Ledger (Rule 17).** DW-61 is addressed: the `Turn` columns, `FromRow`, and the `/state` and API-spec checks. It is not declined.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message. Every throwaway command is `OCUTALON_RUN_TAG=e2s24i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`, one piece per call with `timeout: 600000`, ending with `teardown` on the same tag. A `LOCK busy` exit 75 is the other lane's contention: wait and run it again. If a slot B class nears the call's cap, run it as `ci/iris.sh class` on the throwaway instead.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`) as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: all pass, and slot B holds no `zz` fixture row, `^OcuTalonTest` run or double script afterwards.
  - `OcuTalon.Test.Core.ConversationTurns`
  - `OcuTalon.Test.Core.WebChatMessages`
  - `OcuTalon.Test.Core.CommandsRouting`
  - `OcuTalon.Test.Data.Ownership`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Msg.Contracts`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Contract.Ac`
- (loop) One call each: `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-storage.sh`, `node web/scripts/payloads.mjs --check`. Expected: exit 0, with `ALLOW_UNCHECKED` unchanged.
- (loop) throwaway: `build`.
- (loop) throwaway: `class OcuTalon.Test.Core.ConversationProduction`. Expected: passes; Task 0 is recorded from the first run.
- (loop) throwaway: `class OcuTalon.Test.Core.CommandsInProduction` (`Headers` moved). Expected: passes.
- (loop) throwaway: `class OcuTalon.Test.Install.Production`. Expected: passes (`TestStubsAnswer` with stub 0).
- (loop) throwaway: `class OcuTalon.Test.Install.Registry`. Expected: passes (the `Reconcile` step with `Web.Reconcile`).
- (loop) throwaway: `teardown`. Expected: 0 left.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) throwaway, one call each: `shard lane-b`, `shard lane-a`, `live production` (row 16 with `Intake`), `live production-restart` (row 20 with session B), `live sign-in` (the API spec), then `teardown`. Expected: every class and check passes.

**Planned mutations (Rule 19).** For each, the implement stage applies the mutation, observes red, restores a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and records `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Post | `WebChatIn` sends provenance `untrusted` | `TestBuildsItem`; `TestUntrustedItemRefused`/`TestTurnThroughProduction` |
| Repeat | `WebChatIn`'s and `Conversation`'s `clientId` checks removed | `TestRepeatClientId`; `TestDuplicateItemDropped`; `TestRepeatQueuesNothing` |
| Allowance | `WebChatIn` sends before `Allowed` / ignores a refusal | `TestRefusalQueuesNothing` |
| Turn | the `decide` call skipped | `TestDecideThenTurn`; `TestTurnThroughProduction` |
| Thread | `ThreadSessionId` left empty | `TestDecideThenTurn`; `TestTurnThroughProduction` |
| Stages | the decision-landed publish dropped | `TestStagesPublished` |
| Mid-turn | the "no turn running" check skipped | `TestSecondMessageWaits` |
| Busy | `BUSYMAX` 6 / no wait | `TestBusyRequeues` |
| Broken | no fresh retry | `TestBrokenRetriedFresh` |
| Tainted | the next turn sent `continue` | `TestTaintedNextFresh` |
| Recap | `HostData` added to the recap | `TestRecapFromTurnRows` |
| Fallback | an error status mapped to `error` | `TestEveryFallbackReason` |
| Any outcome | `ignore` ends the turn with no `turn` call | `TestEveryTriageOutcomeRuns` |
| Restart | the sweep leaves `running` turns alone | `TestReconcileResumesTurns`; restart row 20 |
| Stale | the `Attempt` guard removed | `TestStaleAnswerDropped` |
| DW-61 | `FromRow` omits `Text` | `TestFromRowBuilders`; API spec `/state` |
| Isolation | `turnByClient` without its owner check | `TestIsolationEveryRowKind` |
| Built | `STUB` left on `Conversation` | `TestStubsAnswer` |

**Task 0 (measured by the implement stage).** The first throwaway run of `ci/iris.sh class OcuTalon.Test.Core.ConversationProduction` (stack `e2s24i`, build 154) ran with temporary writes in `Conversation` (removed afterwards; `grep MEASURE` finds none) that recorded each callback with the instance's `%Id()`, `%SessionId`, primary header and `%SuperSession`:
- measure 1, the stub `Decide`'s answer: the response header from `Decide` to `Conversation` is type 2 with `IsError` 1, no body class and the status `ERROR <Ens>ErrBPTerminated: Terminating BP Decide # due to error: ERROR #5003: Not implemented`. `Conversation` got `OnError` with that status and then `OnResponse` with no `callresponse` (`answer=[]`), in that order, for both `decide` and `turn`. It handles the error in `OnResponse`, with `OnError` only keeping the status (Decided 13).
- measure 2, the session: a `%SessionId` set before `SendRequestAsync` is the request header's `SessionId` (the decide request, its error response and the Outbound to `Notify` all sit in the Item's session, e.g. 46, while the instance's own primary header, a `RunTurns`, was in session 44), and `OnError`/`OnResponse` after the reopen still read `%SessionId` 46 and `%SuperSession` = the `TraceRef`.
- measure 3, the self-send: `SendRequestAsync("Conversation", RunTurns, 0)` from `Conversation` reached a new instance each time (instance ids 4, 7, 11 and 24, 30, 34, in the one job of the pool), so the finishing instance does not start the next turn itself.
- measure 4, the trace target: the `Item` header's ID equals its `SessionId` (28/28, 36/36, 44/44, 46/46, 48/48): `WebChatIn`'s `ProcessInput` starts a session of its own, and there is no `Join` yet.
- also, the timer path (measured with a temporary change to `Replied`, reverted: the first two error answers of each turn were treated as Busy): the wait that `Conversation` sets with `SetTimer` inside `OnResponse` fires through `Ens.Alarm`, reaches `OnResponse` with the key `busy`, and the turn request goes out again. Every turn still reached done inside the 20 s wait, with the extra requests as the only failed assertions (the request counts), so `Ens.Alarm` is present in the production and a timer set in `OnResponse` survives the framework's clean-up of pending timers.
- also: the container start's `Reconcile` step sent one empty `RunTurns` through `WebChatIn` (a sweep over no turns, read in the production job with the checked statement, no error), and the test's `Web.Reconcile()` swept the three fixture turns as `TestReconcileResumesTurns` expects.

**Mutations observed (Rule 19).** Each was applied, observed red, and reverted; `git status --short`, `git diff --stat` and a hash of `git diff` plus the untracked files were identical before the first and after the last.
- mutation: `WebChatIn` sends provenance `untrusted` -> `TestBuildsItem` red (slot B)
- mutation: `WebChatIn`'s and `Conversation`'s `TurnByClient` checks removed -> `TestRepeatClientId` and `TestDuplicateItemDropped` red (slot B)
- mutation: `WebChatIn` ignores a refusal of `Allowed` -> `TestRefusalQueuesNothing` red (slot B)
- mutation: the `decide` call skipped (`Begin` goes straight to the turn request) -> `TestDecideThenTurn` red (slot B)
- mutation: `ThreadSessionId` left empty -> `TestDecideThenTurn` red (slot B)
- mutation: the decision-landed `Announce` dropped from `Decided` -> `TestStagesPublished` red (slot B)
- mutation: the "no turn running" check skipped in `Start` -> `TestSecondMessageWaits` red (slot B)
- mutation: `BUSYMAX` 6 -> `TestBusyRequeues` red (slot B)
- mutation: no fresh retry after `SessionBroken` -> `TestBrokenRetriedFresh` red (slot B)
- mutation: `AfterTaint` always 0 (the next turn sent `continue`) -> `TestTaintedNextFresh` red (slot B)
- mutation: a tainted reply's `HostData` appended to the reply that is stored -> `TestRecapFromTurnRows` red (slot B; its tainted-reply segment was added for this row, since `Turn` rows hold no `HostData` for a fixture to carry)
- mutation: an error status mapped to the fallback `error` -> `TestEveryFallbackReason` red (slot B)
- mutation: `ignore` ends the turn with no `turn` call -> `TestEveryTriageOutcomeRuns` red (slot B)
- mutation: the sweep leaves `running` turns alone -> `TestReconcileResumesTurns` red (throwaway `e2s24i`); the restart row 20 was not re-run with it
- mutation: the `Attempt` guard removed from `Current` -> `TestStaleAnswerDropped` red (slot B)
- mutation: `FromRow` omits `Text` -> `TestFromRowBuilders` red (slot B); the API spec `/state` check was not re-run with it
- mutation: `turnByClient` without its owner check -> `TestIsolationEveryRowKind` red (slot B)
- mutation: `Parameter STUB = 1` left on `Conversation` -> `TestStubsAnswer` red (throwaway `e2s24i`)
- not observed: the second variant of the Allowance row (`WebChatIn` sends before `Allowed`) and `TestUntrustedItemRefused`/`TestTurnThroughProduction`/`TestRepeatQueuesNothing` as the red test of the Post and Repeat rows; the unit tests above stand for them.
- mutation (review pass): `Begin`'s Catch does not call `Abandon` -> `TestBeginFailureEndsTurn` red (slot B)
- mutation (review pass): `OnResponse`'s Catch does not call `Abandon` -> `TestCallbackFailureEndsTurn` red (slot B)
- mutation (review pass): `ItemOf` leaves out `Item.Text` -> `TestItemOfCarriesTheRow` red (slot B)
- mutation (review pass): `Summary` cuts to 80 characters and adds the cut mark -> `TestSummaryCut` red (slot B)
- mutation (review pass): `AfterTaint` ignores a failed read -> `TestTaintReadFailureStartsFresh` red (slot B)
- mutation (review pass): `WebChatIn.Accept` ignores the status of its send -> `TestSendFailureAnswersError` red (slot B)
- mutation (review pass): `Conversation.Reconcile` without the check for a running production -> `TestReconcileWithoutProduction` red (slot B)
  Each was loaded from a copy outside the repository and then reloaded from the tree, so the working tree was never changed by a mutation (`git status` and a hash of `git diff` plus the untracked files were identical before and after).

**Runs by the implement stage (the loop).** Slot B: `ConversationTurns` 15/15, `WebChatMessages` 6/6, `Data.Ownership` 13/13, `Data.Tables` 6/6, `Live.Payloads` 5/5, `Msg.Contracts` 6/6, `Web.Api` 22/22, `Contract.Ac` 6/6; the check scripts and `node web/scripts/payloads.mjs --check` pass with `ALLOW_UNCHECKED` unchanged; throwaway `e2s24i`: `build`, `ConversationProduction`, `CommandsInProduction`, `Install.Production` and `Install.Registry` pass, and `live production` (row 16 with `Intake`), `live production-restart` (row 20 with session B) and `live sign-in` (the API spec, 83 passed) pass.

**Shared surfaces:**
- the `Turn` table and its contract (`Test.Data.Tables`);
- the `Item` contract (`Test.Msg.Contracts`);
- the `ChatMessage` contract and `web/src/app/live/payloads.ts`;
- `Ownership`'s row-kind list (`TestIsolationEveryRowKind`, `Seed`, `ReadAll`, `TestRowsRefuses`);
- the production oracle's `WebChatIn`/`Conversation` rows (`Test.Install.Production`, `test-production.sh` rows 14, 16 and 18);
- `Test.Web.Api` `TestRoutes`;
- `api.spec.ts` `UNBUILT` and the envelope tests;
- `test-production.sh` row 16;
- `test-production-restart.sh` row 20;
- `test-sign-in.sh`'s fixture users;
- `Fixture.Turn`/`Headers`/`Between`;
- `Install.Step.Web`'s `Reconcile` (called by `Test.Install.Registry`);
- the `lane-b` shard's class list (three new `%UnitTest` classes: `ConversationTurns`, `WebChatMessages` and `ConversationProduction`);
- the OCUTALON message headers and session streams on throwaways (each class removes its own).

Every test added or changed passes on a fresh environment, in either order. The `%UnitTest` classes create and remove their own rows through `Test.Data.Fixture` (`Fixture.Clean(refs)` naming only their own rows, turns adopted), keep their records under their own `^OcuTalonTest` subtree, and save and restore `onlineDemo`. Playwright uses its own `CHAT` fixture user.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A message posted on the page now runs through the whole turn pipeline. `POST /api/v1/messages` validates `{clientId, text, fromGuide}` and calls `WebChatIn` through `CreateBusinessService` and `ProcessInput`; `WebChatIn` deduplicates on `clientId`, asks `Allowance.TryConsume` and sends an `Item` to `Conversation`. `Conversation` owns the per-session `Turn` queue: it sends `Decide` the `decide` and then the `turn` request asynchronously, handles Busy (3 s timer, 5 resends), SessionBroken (one fresh retry with a code-written recap) and Tainted (next turn fresh), turns every failure into the `conversation.turnFallback` reply, publishes `chat.message` at queued, running and done, sends the `Outbound` to `Notify`, and starts the next turn. `Install.Step.Web.Reconcile()` sweeps the queue through `WebChatIn` after a start, and a stale answer is dropped by the `Attempt` guard. `Turn` keeps the text, the reply as sent, the `clientId`, the fallback key and reason, the trace target, `Tainted` and `Attempt`, and `ChatMessage.FromRow` maps them (DW-61). Task 0's four measurements are recorded under `## Verification`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`: the turn queue, the reply shapes, the recap, the sweep and `Reconcile`.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls`, `Post.cls`, `Core/Allowance.cls`, `Core/Msg/RunTurns.cls`: the service, its input, the allowance and the reconcile request.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls`, `Msg/Item.cls`, `Live/Payload/ChatMessage.cls`, `web/src/app/live/payloads.ts`: the new columns, the `ClientId` of an `Item`, the payload fields.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: the row kinds `turnByClient`, `turnQueue` and `lastReplied`, with their wrappers.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`, `Install/Step/Web.cls`: the messages route and the Web step's `Reconcile`.
- New tests and doubles under `src/ocutalon/cls/OcuTalon/Test/Core/` (`ConversationTurns`, `WebChatMessages`, `ConversationProduction`, `DecideDouble`, `ConversationProbe`, `WebChatInProbe`) and `Test/Web/ApiProbe.cls`.
- Updated tests: `Test/Data/Fixture.cls`, `Test/Data/Ownership.cls`, `Test/Data/Tables.cls`, `Test/Live/Payloads.cls`, `Test/Msg/Contracts.cls`, `Test/Contract/Ac.cls`, `Test/Core/CommandsInProduction.cls`, `Test/Core/ProductionItems.cls`, `Test/Web/Api.cls`, `Test/Web/StubRequest.cls`.
- `docker/tests/test-production.sh` (row 16), `test-production-restart.sh` (row 20), `test-sign-in.sh` (the chat user), `web/e2e/api/api.spec.ts` and `web/e2e/support/iris.ts` (the chat specs).

**Review findings (46 from four layers).** Patches applied: 18 rows, grouped into 13 entries (7 medium): `Begin` runs inside a Try that ends the turn with the fallback on a failure; `AfterTaint` counts a failed read as tainted; new tests for the `Begin` and `OnResponse` failures, the `Item` that Decide's input is rendered from, the `Summary` cut, the failed taint read, `Reconcile` with no production, and a send failure in `WebChatIn`; `ConversationProduction` waits for the Outbound's header; the probe state is cleared before `Test.Web.Api`; three comments corrected. Deferred (3, in the frontmatter): the Reconcile trigger on an IPM autostart (Lane A), the Busy resend through the real timer, and the `Allowed` to `TryConsume` hop (Story 16.9). Rejected: 24 rows, each with its reason in `## Review Triage Log` (19 low, 5 false). Follow-up review recommended: true, because 7 medium entries were patched; the unverified risk is that the patched failure paths (`Begin`'s Catch and `OnResponse`'s Catch) are exercised only through the probe's throw hooks, not through a real fault in a running production.

**Verification.** Slot B (`ocutalon-slot-b`, build 154U): both `iris_doc_load` calls 0 errors; `ConversationTurns` 21, `WebChatMessages` 7, `CommandsRouting` 12, `Data.Ownership` 13, `Data.Tables` 6, `Live.Payloads` 5, `Msg.Contracts` 6, `Web.Api` 22 and `Contract.Ac` 6 all passed, run once before the review and once after the patches; no fixture row, event or `^OcuTalonTest` run was left. Seven review mutations and the implement stage's 18 were observed red and reverted. `test-class-rules.sh` (`ALLOW_UNCHECKED` unchanged), `test-boundaries.sh`, `test-ci-config.sh`, `test-storage.sh` and `payloads.mjs --check` pass. Throwaway `e2s24i`: `build`; `ConversationProduction`, `CommandsInProduction`, `Install.Production` and `Install.Registry` passed twice; after the last patch `ci/checks.sh`, `shard lane-b` (31 classes) and `shard lane-a` (9 classes), `live production` (row 16), `live production-restart` (row 20) and `live sign-in` (83 passed) all passed; teardown left nothing. Matrix Test Audit: every row has a covering test that ran and passed (Restart through `TestReconcileResumesTurns`, restart row 20 and `TestReconcileWithoutProduction`).

**Residual risks.** The Reconcile trigger for a production that starts on its own is not built (deferred 1). The Busy timer is verified end to end only once, in Task 0, by a temporary change. The production tests expect Epic 0's `Decide` stub (fallback `unusable`), so Story 1.3 must update them. `Conversation.Reconcile()` returns an error when the production runs and `WebChatIn` cannot be created (Decided 18), which fails the installer's Reconcile step. The message text has no upper bound (rejected row, reopen_if noted).
