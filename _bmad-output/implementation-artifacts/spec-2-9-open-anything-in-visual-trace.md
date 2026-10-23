---
title: 'Story 2.9: Open anything in Visual Trace'
type: 'feature'
created: '2026-10-23'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Each chat turn is its own Visual Trace session today: `WebChatIn` never sets `%SessionId`, so a judge has to hunt for every turn. No trace URL is built anywhere. `Conversation.Rebuild` also retries a `SessionBroken` turn under the turn's own `ItemId`. AD-20's one decision per (`ItemId`, `Kind`) makes the real `Decide` refuse that retry, so the retry never gets an answer (DW-112, HIGH).

**Approach:** This story builds the server half of Visual Trace, split from the page half (Design Notes, Decided 1).
- **The thread.** `OcuTalon.Core.Trace.Join` gives each session one trace thread a day. `WebChatIn` joins it, so a day's turns are one Visual Trace session.
- **The position.** `Trace.Position` works out where a turn's Item lands in Visual Trace's own item list. `Conversation` stores that on the Turn when it takes the Item.
- **The URL.** The new `OcuTalon.Web.TraceLink` is the one builder of trace URLs. `/state` and `/events` add a `traceUrl` to every payload object that carries `traceHeaderId` and `traceNamespace`. The URL's page follows the viewer's own Visual Trace settings.
- **DW-112.** `Conversation` retries a broken turn as a new `Decide` call under a new `ItemId`, derived from the turn's.

## Boundaries & Constraints

**Always:**
- **`OcuTalon.Core.Trace` (new, Lane B; AD-26, AD-4).**
  - **`Join(sessionRef, Output sc, now = "") As %Integer`.** It takes the `Session` row's own lock (`%LockId`), waiting at most `Parameter LOCKWAIT = 2` seconds.
    - When the row's `ThreadDay` is `Day(now)` and its `ThreadSessionId` is set, Join releases the lock and returns that id.
    - Otherwise Join returns "" and **keeps the lock**. The caller then sends its first message in a session of its own and calls `Started`.
    - When there is no `Session` row, or the lock does not come free within LOCKWAIT, Join returns "" with an error `sc`. The lock is then not held.
  - **`Started(sessionRef, sessionId, now = "") As %Status`.**
    - A non-empty `sessionId` is recorded as the row's `ThreadSessionId`, with `ThreadDay = Day(now)`.
    - An empty one records nothing.
    - Started always releases the lock that Join kept.
  - **`Day(now = "")`.** The instance-zone local date `YYYY-MM-DD` of a UTC time, from `$Extract(Data.Time.ToLocal(utc), 1, 10)`. The default is `Data.Time.NowUtc()`.
  - **`Position(headerId, Output withEvents, Output withoutEvents) As %Status`.** This is the target header's 1-based index in the item list that Visual Trace draws for the header's session. It is computed twice, with events and rule rows shown and with them hidden.
    - Position ports the counting logic of `EnsPortal.SVG.VisualTrace.BuildTraceInfo` and `InjectEvents` without the drawing (Code Map). The rules:
      - **Headers** of the session are taken in `%ID` order, up to and including the target.
      - **Event rows** (`Ens_Util.Log`) and **rule rows** (`Ens_Rule.Log`) are keyed `time_"#"_msgId` in one local array, as Visual Trace keys them.
      - **Before each header,** those rows are injected while they sort before it: time earlier than its `TimeCreated`, or the same time with `msgId < its id`. Each one counts only when its host (`ConfigName`, falling back to `SourceClass`; for a rule row, falling back to the session's first header's `SourceConfigName`) is the source or target of an earlier header. A row that fails this check is passed over for good.
      - **I/O rows** count when `TimeReceived` is before the header's `TimeCreated` and `CorrespondingRequestId` is at most the header's id.
      - **Not modelled:** ACK rows and internal items. No OcuTalon message is an EDI document or an internal item.
    - Every read is a checked prepare (one-argument `%Prepare`), so Position runs only in production jobs and tests. An unknown header or a failed read gives an error status and leaves both outputs empty.
  - Trace never sends a message and never throws.
- **`WebChatIn` (`Channel/WebChat/In.cls`, AD-26).** After the allowance has allowed the message, `Accept` reads `now` once and then:
  1. `thread = Trace.Join(sessionRef, .joinSc, now)`. A Join error logs one `$$$LOGWARNING` with the new `Parameter ERRORJOIN = "WebChatIn could not join the session's trace thread, so this turn is traced on its own: "` and the status text. The message still goes, in a session of its own.
  2. `..%SessionId = thread`, `..%SuperSession = session.TraceRef`.
  3. The Item send.
  4. When `joinSc` is OK and `thread` was "", it calls `Started(sessionRef, ..%SessionId, now)`, passing "" when the send failed. It runs in every path, a thrown error included.

  A Join failure never refuses or loses a message. `RunTurns` is unchanged. **Only channel services call `Join`.** Commands, approvals and notices inside a turn join through the bridge context's `ThreadSessionId`.
- **The Turn's position.**
  - `Data/Turn.cls` appends `TraceItemIndex As %Integer` and `TraceItemIndexNoEvents As %Integer`, with their storage values appended.
  - In `Conversation.Take`, once `TraceHeaderId` is set, it calls `Trace.Position` and stores both.
  - A failed Position logs one warning, leaves both empty, and never stops the turn.
  - `Live.Payload.ChatMessage` gains `TraceItemIndex` (`traceItemIndex`) and `TraceItemIndexNoEvents` (`traceItemIndexNoEvents`), set by `FromRow` only when the row has them. `payloads.ts` is regenerated from it.
- **`OcuTalon.Web.TraceLink` (new, Lane B; AD-24, AD-26), the one builder of trace URLs.**
  - **`Viewer(Output viewer)`.** It is called once per request. It records whether demo mode is on (`Setting.Get(Install.Step.Demo.#MODEKEY) = "1"`). It reads the page size and "Show events" lazily, once per namespace, through IRIS's own `##class(EnsPortal.VisualTrace).GetItemsPerPage()` and `.GetShowEvents()`, run in the target's namespace. Any error falls back to 40 and on.
  - **`Url(headerId, namespace, index = "", indexNoEvents = "", ByRef viewer) As %String`.**
    - The application comes from the namespace, compared without regard to case. `OCUTALON` gives `/ocutalon/trace/ocutalon/`. `OCUORDERS` gives `/ocutalon/trace/ocuorders/`, only when demo mode is on.
    - The URL is the application's path, then `EnsPortal.VisualTrace.zen?SESSIONID=<headerId>`.
    - It adds `&PAGE=<ceil(i / pageSize)>` only when the index `i` for the viewer's "Show events" is known: `index` when it is on, `indexNoEvents` when it is off.
    - An empty header id, any other namespace, or OCUORDERS without demo mode gives "".
  - **`Add(json, ByRef viewer)`.** It walks a `%DynamicObject` or `%DynamicArray` recursively. On every object with a non-empty `traceHeaderId` and a `traceNamespace`, it sets `traceUrl` to `Url(...)`, using that object's `traceItemIndex` and `traceItemIndexNoEvents`. The key stays absent when the URL is "". Nested objects are covered, such as a chat message's `decision` and an incident's `traceTargets.*`.
  - TraceLink reads no table.
- **`Web.Api`.** `StateBody` and `EventsBody` each call `TraceLink.Add` on their whole result, with one `Viewer` per call (AD-12).
- **DW-112 (AD-20, AD-30).** `Conversation` gains `ClassMethod RetryItemId(itemId) As %String`. It returns the first 22 characters of the base64url form (`+/` become `-_`, no `=`) of `$SYSTEM.Encryption.SHAHash(256, itemId_"/retry")`.
  - While `BrokenRetried` is 1, `Ask`'s turn request carries `RetryItemId(turn.ItemId)` in place of the turn's `ItemId`.
  - The Turn keeps its own `ItemId`. Its `TurnDecisionRef` ends as the retry's DecisionRef (`Replied` already sets it).
  - The broken attempt's row stays as `Decide` recorded it.
  - Busy re-asks after the retry use the same derived `ItemId`. A second broken answer is the fallback, as today.
- **Tests (AD-22, Rule 19).**
  - The `%UnitTest` classes are slot-safe unless named as production classes. They make their rows through `Test.Data.Fixture` and remove them.
  - Synthetic `Ens` headers carry a run SuperSession, so `Fixture.RemoveMessages` removes them together with their sessions' log rows.
  - Browser specs sign in as a new fixture user, `THREAD` (`ZzThread`, with `OcuTalonUser,OcuTalonTraceViewer`), and restore its Visual Trace settings in `finally`.

**Never:**
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Checks,Eval,Watch,Schedule,Install}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `test-pinned-sources.sh`, `test-ci-warm.sh` and `test-ci-config.sh`, and every row of `test-production.sh`.
- **Never edit** `Production.cls` or `docker/merge.cpf`. `ThreadProduction`'s Decide swap changes only the running configuration of a throwaway, and it restores it.
- **Never add** an unchecked prepare, embedded SQL, an `ALLOW_UNCHECKED` entry, a production item, a role or grant, or a dependency. Product code never reads `^EnsPortal.Settings` directly; only tests set and restore it.
- **Never use as `%SessionId`** any id but a real session's own id: a `Join` result, or a header's `SessionId`.
- **Never build the page half** (Decided 1). That means:
  - trace links on the decision strip and the rail rows;
  - the header's Visual Trace menu and `/state`'s conversation target;
  - the sign-in popover and DW-58;
  - the approval and reminder payloads' trace targets.

  Also out of scope: the online demo's busy check before a trace window (Epic 16), and the public accounts' pinned page size (the installer).
- **Never run on slot B:**
  - `Test.Core.ThreadProduction`, `RoutingProduction`, `ConversationProduction` and `CommandsInProduction`;
  - `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` and `Test.Demo.Production`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First turn of the day | Session row with no thread, or a `ThreadDay` before today | The Item's header starts its own session. The row now holds that id and today, and the lock is released. | The send fails: nothing is recorded, and the lock is released |
| Later turn that day | Row holds thread T for today | The Item, the decide and turn requests, their responses, the AgentStep requests, the Outbound and Notify's send to WebChatOut all have SessionId T; the requests carry the TraceRef as SuperSession | — |
| After midnight | T for yesterday (local date) | A new thread T2, the new Item's own id | — |
| Lock busy | Another process holds the row's lock for over 2 s | The message is sent in its own session with one warning, and nothing is recorded | No Session row: the same |
| Position | Synthetic session: headers h1 (A→B), h2 (B→C), h3 (C→D), h4 (D→E); event of host A before h1; event of host C before h2; rule row of host B before h3; I/O row received before h3 whose request is h4 | h3: with events 4 (h1, h2, the rule row, h3). A's event is dropped because nothing was on the diagram yet, and C's because only h1's A and B were; the I/O row belongs after h3. Without events: 3. | Unknown header: an error, both empty |
| PAGE | index 40, 41, 80, 81; page size 40, then 10 | 1, 2, 2, 3; then 4, 5, 8, 9 | No index: no `PAGE` |
| Show events off | index 50, indexNoEvents 30, size 40 | `PAGE=1` | — |
| Namespaces | `OCUTALON`; `ocuorders` with demo mode on, then off; `ZZNS`; no header id | `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=…`; `/ocutalon/trace/ocuorders/…`; no `traceUrl` key in the other cases | Settings read throws: 40 and on |
| Nested | A `chat.message` with a decision; an incident's `traceTargets.sample`; arrays | Every object with a target gets its own `traceUrl` | Objects with no target are unchanged |
| DW-112 | Turn answers: broken, then reply | Third Decide call: `ItemId = RetryItemId(turn.ItemId)` ≠ the turn's, and fresh. The turn is done with the reply, and `TurnDecisionRef` is the retry's. | The retry is broken too: the fallback `error` |
| Over 40 items | The `ZzThread` thread holds more than 45 items; viewer size 40, then 10, then Show events off | Each latest-turn link opens Visual Trace with that turn's element on the rendered page | — |

</intent-contract>

## Code Map

**Server (Lane B, edit or new)**
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls`:
  - class comment `:1-11` (`:5` "takes the session's TraceRef as its SuperSession");
  - `Accept` `:40-66` (SuperSession `:53`, Send `:62`);
  - the private seams `Send` `:69-72` and `Allowed` `:75-78`.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`:
  - properties `:10-24`;
  - `ForUser`'s lock pattern `:44-49,72`;
  - storage `:99-127` (Values 1-6).
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls`: `TraceHeaderId` `:50-51`, and storage Values up to 20 (`:139-142`).
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
  - class comment: SessionBroken `:17-18`, trace `:32-36`;
  - `BrokenRetried` `:116`;
  - `Take` `:157-180` (`:178` sets TraceHeaderId);
  - `Begin` `:292-314`, `Join` `:318-326`, `Request` `:329-332`, `ItemOf` `:335-346`;
  - `Ask` `:375-391`;
  - `Replied` `:404-418` (`:412` TurnDecisionRef before `:414` Rebuild);
  - `Delay` `:446-456` and `Resend` `:459-465` (the busy re-ask goes through `Ask`);
  - `Rebuild` `:469-474`.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls:151-164`: `RequestFor` copies `ItemId` `:157` and `ThreadSessionId` `:162`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls`: trace properties `:35-39`, and `FromRow` `:57-80` (sets the target only when the row has one).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - class comment `:1-19`;
  - `State` `:108-114`;
  - `StateBody` `:256-293`, used by `State` and `Test.Web.Api`;
  - `ChatItems` `:300-343`, `RailBody` `:347-363`, `CheckView` `:368-385` (Check target);
  - `PayloadObject` `:388-392`;
  - `EventsBody` `:430-439`.

  `Live/Event.cls:43` parses each stored payload into a `%DynamicObject`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `TurnCost` `:48-68` sums the two DecisionRefs, unchanged;
  - the class comment `:17-25` and `Watchers` show the checked-prepare pattern for reads that run only in production jobs and tests.
- New: `src/ocutalon/cls/OcuTalon/Core/Trace.cls` and `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls`. Neither is persistent, so neither needs a `short-names.tsv` row.

**Read-only evidence**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls:15-28` (`NowUtc`, `ToLocal`; no local-date method).
- Bridge:
  - `Bridge/Process/Decide.cls:22` (Epic 0 stub: NotImplemented);
  - `Bridge/Data/Decision.cls:66` (`TraceSessionId`) and `:73` (`ItemIdKindIndex` unique);
  - `Bridge/Msg/AgentStep.cls:5-27`;
  - `Bridge/Operation/Steps.cls:1-10` (AgentSteps stub);
  - `Bridge/Ids.cls:7` (`NewRef`, random);
  - `Bridge/Context.cls:32,35`.
- `Production.cls`: `:18` (`Decide`, `OcuTalon.Bridge.Process.Decide`), `:33` (`AgentSteps`), `:45` (`WebChatIn`).
- Trace applications:
  - `Install/Step/Web.cls:7-11,47,147-160` (the app is `/ocutalon/trace/ocutalon`, with CookiePath `.../`);
  - `:35` (the API's application roles include `%DB_OCUTALON_DATA`);
  - `Install/Step/Demo.cls:36` (`MODEKEY`) and `:77-78` (the OCUORDERS app, in demo mode only).
- IRIS: `irislib/` is gitignored, so name it in searches.
  - `Ens/BusinessService.cls`: ProcessInput `:44-85`, whose `Exit` kills `$$$JobSessionId` (`:79`); `SendRequestAsync` `:182-215` sets `..%SessionId` from the new header (`:204`).
  - `Ens/MessageHeader.cls:57-72` (a new session's id is the header's id).
  - `EnsPortal/VisualTrace.cls`:
    - `SESSIONID` and `PAGE` `:29,35`;
    - the frame's parameters `:314-322,583-593`;
    - selecting the target `:952-961`;
    - the settings getters `GetItemsPerPage` `:1156-1159` and `GetShowEvents` `:1180-1183`.
  - `EnsPortal/SVG/VisualTrace.cls`:
    - defaults `MSGPERPAGE` 40 `:19` and `INCLUDEEVENTS` 1 `:25`;
    - paging `:513-515`;
    - each message is `<g id="<headerId>">` `:691`;
    - `BuildTraceInfo` `:1413`: session lookup `:1447`, header cursor `:1516-1594`, event and rule rows `:1596-1631`, I/O query `:1679-1690`, the header loop `:1686-1810` (`InjectEvents(1)` `:1691`, `clsInv` `:1788-1797`), the remaining rows `:1819-1821`;
    - `InjectEvents` `:1842-1975`.
  - SessionId indexes: `Ens/MessageHeader.cls:24`, `Ens/Util/Log.cls:24`, `Ens/Rule/Log.cls:17`, `Ens/Util/IOLog.cls:47`.
- Measured on slot B in this plan (build 154, OCUTALON):
  - `^EnsPortal.Settings` and `Ens.MessageHeader` both resolve to `OCUTALON_DATA`;
  - `##class(EnsPortal.VisualTrace).GetItemsPerPage()` and `GetShowEvents()` run outside CSP and return 40 and 1 for a user with no settings.

**Server tests (Lane B, edit or new)**
- `Test/Core/DecideDouble.cls`:
  - doc `:1-28`;
  - `OnRequest` `:31-122` (`ref` `:56`; the Record gate `:118-120`);
  - `Write` `:125-141`, which skips an existing (ItemId, Kind) row at `:128`.
- `Test/Core/ConversationProbe.cls:28-48`: hands Decide requests to a shadow double, so `%ConfigName` is "".
- `Test/Core/ConversationTurns.cls`:
  - `TestBrokenRetriedFresh` `:357-392`;
  - `TestTurnJoinsItsItemSession` `:742-779`;
  - `Call(n, field)` `:1326`;
  - `Sent` `:1332`.
- `Test/Core/WebChatInProbe.cls:1-40` (Send records `superSession`, not `%SessionId`) and `Test/Core/WebChatMessages.cls:57` (`TestBuildsItem`).
- `Test/Core/InProduction.cls`: guard `:32-46`, clean-up `:48-54`, `Session` `:67-74`.

  `Test/Core/ConversationProduction.cls`: doc `:1-25`, `TestTurnThroughProduction` `:63-134`, `TestTurnsRunInOrder` `:162-233`, `Send`/`WaitDone` `:331-358`. Its assertions compare with the Item's `sessionId`, which is now the thread.
- `Test/Data/Fixture.cls`:
  - `Session` `:17`;
  - `Decision` `:117-134`, whose `TraceSessionId` is 42 at `:127` (overridable through `fields`);
  - `RemoveMessages` `:306-332`, which deletes headers, bodies and `Ens_Util.Log` only;
  - `Headers` `:336`, `Between` `:347`.
- `Test/Core/BridgeSink.cls:616-640` (`HoldStream`, `ReleaseStream`, `Hold`): the lock-holder job pattern.
- `Test/Web/Api.cls` (`TestStateBody` `:71`, `TestStateChatDecision` `:276`, `TestEventsBody` `:514`) and `Test/Live/Payloads.cls` (ChatMessage `FromRow` tests `:246-304`; the property oracles further down).
- `docker/tests/test-class-rules.sh:1-21` (each rule self-tests on synthetic classes) and `:33-35` (`ALLOW_UNCHECKED`, unchanged).
- `ci/units.sh`: shard `lane-b` covers the areas `Core` and `Web`, so new classes join it with no edit.

**Web and browser tests (Lane B, edit or new)**
- `web/src/app/live/payloads.ts:97-98`: the ChatMessage trace fields. The file is generated by `web/scripts/payloads.mjs`, never hand-edited.
- `web/e2e/api/api.spec.ts`:
  - `post` `:395` and `sessionEvents` `:403` (to move to `support`);
  - the chat tests `:456-505` (`traceHeaderId` `:468`, `/state` `:485-505`).
- `web/e2e/support/iris.ts:15` (`fixtureUser`) and `:39` (`irisScript`); `web/e2e/sign-in/helpers.ts:60` (`signIn`), `:66` (`signInOverHttp`) and `:83` (`envelope`).
- `docker/tests/test-sign-in.sh`: header `:7-31`, users `:45-65`, role loop `:128`, environment `:177-197`, labels `:211,217`.

## Tasks & Acceptance

**Execution:**
0. **Task 0 (implement stage, measured first, results under `## Verification`):**
   - (a) **The Decide swap on a throwaway.** Set the running `OcuTalon.Production` item `Decide` to `OcuTalon.Test.Core.DecideDouble` through `Ens.Config.Production` and `Ens.Director.UpdateProduction`, or with a second, enabled `Decide` item of that class while the original is disabled. Show that a turn is answered by the double, and that after the restore a turn falls back through the stub again.
   - (b) **Reaching Visual Trace's SVG from Playwright.** Through the frame tree, the frame element's SVG document, or by fetching the frame's own URL with the page's cookies.

   If neither variant of (a) works on build 154, stop with an `intent gap` naming AC "Until Stories 1.3 and 1.5".
1. `src/ocutalon/cls/OcuTalon/Data/Session.cls` -- append `ThreadSessionId As %Integer` ("the session id of today's trace thread", AD-26) and `ThreadDay As %String(MAXLEN = 10)`, with storage Values 7 and 8 appended. Update the class comment -- the thread lives on the row (AD-26).
2. `src/ocutalon/cls/OcuTalon/Data/Turn.cls` -- append `TraceItemIndex` and `TraceItemIndexNoEvents` (`%Integer`, documented), with storage Values appended -- the position for PAGE.
3. `src/ocutalon/cls/OcuTalon/Core/Trace.cls` (new) -- add `LOCKWAIT`, `Join`, `Started`, `Day` and `Position` as Boundaries says, with a contract-only class comment -- the thread and the item index (AD-26).
4. `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- the four steps of Boundaries, `ERRORJOIN`, and the class comment -- turns join the day's thread.
5. `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
   - `Take` stores `Position`'s two indexes, with a warning on failure.
   - Add `RetryItemId`; `Ask` uses it while `BrokenRetried`.
   - Update the class comment's SessionBroken and trace sentences: the Items of a session share its day's thread.

   This carries the PAGE index and DW-112.
6. `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` -- add the two properties, and set them in `FromRow` when the row has them. Then run `node web/scripts/payloads.mjs` to regenerate `web/src/app/live/payloads.ts` -- the index reaches `/state` and `/events`.
7. `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls` (new) -- `Viewer`, `Url` and `Add` as Boundaries says -- the one URL builder.
8. `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `StateBody` and `EventsBody` end with `TraceLink.Add`, using one viewer per call. Add a class comment line -- AC "Trace URLs".
9. `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls` -- three changes, and the doc:
   - (a) When it runs as a production item (`..%ConfigName '= ""`; `ConversationProbe`'s shadow double has none), every request that it answers with a DecisionRef sends two `OcuTalon.Bridge.Msg.AgentStep` (Position 1 and 2, that DecisionRef, StepKind `model`, Label `zz step`, Status `ok`) asynchronously to `AgentSteps` before it answers, with no response required.
   - (b) While Record is on, `Write` sets the row's `TraceSessionId` to the double's `%SessionId` when that is set.
   - (c) While Record is on, a `turn` request whose `ItemId` already has a `turn` row answers the error status "zz the item already has the turn decision", as `Decide` does (AD-20).

   This is the Decide double of AC "Until Stories 1.3 and 1.5", and DW-112's realism.
10. `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- two changes -- clean-up and the thread assertions (Rule 2):
    - `RemoveMessages` also deletes, for each session it finds, the session's remaining headers with their bodies (responses can carry no SuperSession), and its `Ens_Rule.Log` and `Ens_Util.IOLog` rows.
    - A new `SessionHeaders(sessionId)` gives the same objects as `Headers`, read by SessionId.
11. `src/ocutalon/cls/OcuTalon/Test/Core/WebChatInProbe.cls` -- `Send` also records `..%SessionId`. A transient `NewSession` id, when set and `..%SessionId` is "", becomes `..%SessionId` after the record, as Ens does -- the probe for Task 14.
12. `src/ocutalon/cls/OcuTalon/Test/Core/Trace.cls` (new, slot-safe) -- the tests:
    - `TestJoinStartsAndKeepsTheThread`: Join gives "" with OK; `Started(…, 777)`; Join gives 777; `ThreadDay` is `Day()`.
    - `TestNewThreadAfterLocalMidnight`: `now` values one second either side of local midnight are found by stepping UTC hours through `Data.Time.ToLocal`, then Join and Started with explicit `now`.
    - `TestStartedWithoutASessionRecordsNothing`.
    - `TestBusyLockAndNoRowFail`: a holder job, as in `Test.Core.BridgeSink`'s `Hold`, holds the row's `%LockId`. Join returns "" with an error in about 2 s, and the lock is not held after. An unknown SessionRef gives an error.
    - `TestPositionCountsAsVisualTraceDraws`: the matrix row "Position" on synthetic `Ens.MessageHeader`, `Ens.Util.Log`, `Ens.Rule.Log` and I/O-log rows. It also covers a same-time event with `MessageId` below and at the header id, a rule row with no `CurrentHeaderId` or `ConfigName`, and a thread of more than 40 items whose last header is at 41 or more.
    - `TestPositionOfAnUnknownHeader`.
13. `src/ocutalon/cls/OcuTalon/Test/Web/TraceLink.cls` (new, slot-safe) -- the matrix rows PAGE, Show events off, Namespaces and Nested, plus Viewer:
    - the viewer's own settings, set through `EnsPortal.VisualTrace.SetItemsPerPage` and `SetShowEvents` for `$Username`, with the previous `^EnsPortal.Settings($Username,"VisualTrace")` saved and restored;
    - the defaults when unset.
14. `src/ocutalon/cls/OcuTalon/Test/Core/WebChatMessages.cls` -- the tests:
    - `TestJoinsTodaysThread`: a row with today's thread gives the probe's send that `%SessionId` and the TraceRef, and the row is unchanged.
    - `TestFirstTurnStartsTheThread`: no thread plus `NewSession` 5150 gives a send with `%SessionId` "" and records 5150 for today.
    - `TestJoinFailureStillSends`: a held lock still sends the message, in its own session, with one warning that starts with `ERRORJOIN`.
    - `TestFailedSendRecordsNoThread`.
15. `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls`:
    - Add `TestBrokenRetryIsANewItem` (DW-112), with Record on and turn answers broken, then reply. It checks:
      - call 3 is a turn, fresh, with `itemId = ##class(OcuTalon.Core.Conversation).RetryItemId(turn.ItemId)`, which matches `22(1AN,1"-",1"_")` and is not the turn's;
      - the Turn is done with the reply text;
      - the Turn's `ItemId` is unchanged;
      - `TurnDecisionRef` is the third answer's;
      - two `turn` Decision rows: the turn's own `ItemId` with fallback `error`, and the derived one.
    - Update any test that the double's AD-20 refusal turns red. Search for `Record(`.
16. `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls` (new; extends `InProduction`; throwaways and CI only) -- the class comment says so. `OnBeforeAllTests` swaps `Decide` to the double once the guard passes (Task 0a). `OnAfterAllTests` restores it before `##super()`, even after a failure. It also clears the double's records. The tests:
    - `TestTwoTurnsOneThread`, with Record on and two messages through WebChatIn. Both turns are done with the double's reply, and:
      - both Items have SessionId T. T is the first Item header's `%ID`, and that header's own SessionId.
      - The Session row holds T and `Trace.Day()`.
      - Every header of the run's SuperSession has SessionId T.
      - `SessionHeaders(T)` holds, per turn, 2 Conversation-to-Decide requests (with the TraceRef as SuperSession), their 2 responses, at least 2 AgentStep requests to `AgentSteps`, and 1 Outbound to Notify.
      - The written Decision rows have `TraceSessionId` T.
      - Turn 2's `TraceItemIndex` is greater than turn 1's, and equals `Trace.Position` of its header read afterwards.
    - `TestNewThreadAfterMidnight`: after turn 1, the row's `ThreadDay` is set to yesterday's local date. Turn 2's Item starts T2, its own id, which is not T1; the row holds T2 and today; turn 2's headers are all in T2.
    - Both tests also check that every SessionId among the run's headers is the `%ID` of a header whose SessionId is itself.
17. `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls` -- the doc says that a session's Items share its day's thread. Its assertions stay unless one goes red -- the shared surface.
18. `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` and `Test/Live/Payloads.cls` -- the changes, and every assertion that compares a whole payload is updated -- AC "Trace URLs":
    - `StateBody`'s turn entry and its nested decision, and `EventsBody`'s `chat.message`, carry `traceUrl`;
    - a check with namespace `ZZNS` carries none;
    - ChatMessage's oracle and `FromRow` gain the two index fields.
19. `docker/tests/test-class-rules.sh` -- a rule, `trace-join`: `OcuTalon.Core.Trace).Join(` may appear on a code line only under `OcuTalon/Channel/` and `OcuTalon/Test/`. It has synthetic samples (a Core class breaks it, a Channel class keeps it, a comment mentions it), and the header lists it -- AC "Only channel services".
20. `web/e2e/support/` -- the changes:
    - move api.spec's `post` and `sessionEvents` here, and api.spec imports them (Rule 2);
    - add `'THREAD'` to `fixtureUser`;
    - add `setTraceSettings(user, {itemsPerPage?, showEvents?})`, which sets or kills `^EnsPortal.Settings(user,"VisualTrace",…)` through `irisScript` with `quoted()` values and returns the previous values for the restore.
21. `web/e2e/api/api.spec.ts` -- the done `chat.message` event and `/state`'s turn carry `traceUrl` equal to `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=<traceHeaderId>&PAGE=<ceil(traceItemIndex/40)>` (the chat user has default settings) -- AC "Trace URLs", over real HTTP.
22. `web/e2e/trace/trace.spec.ts` (new; chromium; user THREAD; a header comment like rail.spec's) -- the cases:
    - **Set-up:** post messages through the API and wait for each turn to be done, until the newest turn's `traceItemIndex` is over 45 (at most 15 turns).
    - **T1** "the link to a late turn of a thread of more than 40 items opens Visual Trace on that turn": `/state`'s `traceUrl` has `PAGE=ceil(index/40)` ≥ 2. A page opens it, and the rendered SVG holds `g[id="<traceHeaderId>"]` (Task 0b).
    - **T2** "with the viewer's page size 10 the link's PAGE follows and still opens on the turn".
    - **T3** "with Show events off the link counts no event or rule rows and still opens on the turn": the precondition is `traceItemIndexNoEvents` < `traceItemIndex`.
    - **T4** "a day's turns are one Visual Trace session": `SESSIONID=<late turn>&PAGE=1` renders the first turn's Item header of the day.
    - Settings are restored in `finally`.
23. `docker/tests/test-sign-in.sh` -- add the user `ZzThread` (`OcuTalonUser,OcuTalonTraceViewer`), with its password, the role loop, the redaction, `OCUTALON_THREAD_USER` and `OCUTALON_THREAD_PASSWORD`, and "Story 2.9's T1-T4" in the header and the PASS and FAIL labels.
24. **The sweep.** Search `web/e2e/` and `web/scripts/` for exact equality (`toEqual`, `deepEqual`) on payload objects from `/state` or `/events`, and widen each to allow `traceUrl`, `traceItemIndex` and `traceItemIndexNoEvents` -- the shared surface.

**Acceptance Criteria:**
- **One thread a day (FR-3, NFR-20, AD-26, AD-4).** **Given** a session's chat turns, **when** `WebChatIn` takes each message, **then**:
  - `Trace.Join` returns the session's thread for the day, kept on the `Session` row and allocated under its lock;
  - `WebChatIn` sets `..%SessionId` and `..%SuperSession` inside `OnProcessInput`, before its first send;
  - both turns' decisions, agent steps and replies are in one trace session with the session's SuperSession;
  - the first turn after local midnight starts a new thread.

  Tests: `TestTwoTurnsOneThread`, `TestNewThreadAfterMidnight`, `Test.Core.Trace`, `WebChatMessages`.
- **Never fails a message.** **Given** a Join that fails (busy lock, no row) or a failed send, **when** a message arrives, **then** it is still sent in its own session with one warning, and no thread is recorded. Tests: `TestJoinFailureStillSends`, `TestFailedSendRecordsNoThread`, `TestBusyLockAndNoRowFail`.
- **Only channel services; real session ids only (AD-26).** **Given** `src/`, **when** `test-class-rules.sh` runs, **then** only `OcuTalon.Channel` and `OcuTalon.Test` call `Trace.Join`. **Given** a thread test's headers, **when** `ThreadProduction` reads them, **then** every SessionId among them is a header's own id. Tests: the `trace-join` rule, `ThreadProduction`.
- **Until Stories 1.3 and 1.5 (AD-29).** **Given** this tree's stub Decide, **when** the thread tests run, **then** the throwaway's `Decide` is the double, which sends AgentStep messages and answers in the turn's thread. Its restore is the one switch, which the real path removes once Stories 1.3 and 1.5 have merged (Epic 11). Tests: `ThreadProduction`.
- **The item index (AD-26, as Decided 3 refines it).** **Given** a turn's Item header, **when** `Conversation` takes it, **then** the Turn keeps the header's position in Visual Trace's own item list, with events shown and hidden, and `chat.message` carries both. Tests: `TestPositionCountsAsVisualTraceDraws`, `TestTwoTurnsOneThread`, `Test.Live.Payloads`.
- **Trace URLs (AD-12, AD-24, AD-26).** **Given** a payload object carrying `traceHeaderId` and `traceNamespace`, **when** `/state` or `/events` serves it, **then**:
  - `TraceLink` adds `traceUrl`, which is the namespace's own trace application, then `EnsPortal.VisualTrace.zen?SESSIONID=<id>`, with `PAGE = ceil(index ÷ page size)` when an index is known;
  - the page size and "Show events" are the viewer's own, read through one helper (defaults 40 and on);
  - there is no URL for another namespace, or for OCUORDERS without demo mode.

  Tests: `Test.Web.TraceLink`, `Test.Web.Api`, api.spec.
- **Opens on the turn (AD-26).** **Given** a thread of more than 40 items, **when** a viewer opens the link to a late turn, **then** Visual Trace renders that turn's message on its page. This holds at page size 40, at page size 10, and with Show events off. Tests: T1-T4.
- **DW-112 (AD-20, AD-30).** **Given** a turn whose first turn answer is SessionBroken, **when** `Conversation` retries it, **then**:
  - the retry is a new Decide call, fresh, under `RetryItemId(turn.ItemId)`, and gets the reply;
  - the Turn keeps its `ItemId` and links to the retry's decision;
  - the broken attempt keeps its `error` fallback row.

  Tests: `TestBrokenRetryIsANewItem`.

## Spec Change Log

- 2026-10-23, lead (spec gate): split applied (AC 3-5 and DW-58 to Story 2.13); veto U-40; DW-74 to burndown; the DW-112 Conventions row written; AD-26's wording sent to the orchestrator.

## Review Triage Log

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-26:** threads, Join, the joining service, PAGE, the one builder, and real session ids.
- **AD-24:** the trace applications, and the viewer's own page size.
- **AD-4:** the TraceRef is every message's SuperSession.
- **AD-12:** payloads carry targets, and the web layer adds the URL when it serves.
- **AD-13:** no unchecked prepare and no embedded SQL. TraceLink reads no table, and Trace's checked reads run in production jobs.
- **AD-20:** one Decision per (ItemId, Kind); `TraceSessionId`; `TurnCost`.
- **AD-30:** Conversation, and the broken retry.
- **AD-6:** `Request.ItemId` and `ThreadSessionId`; busy writes no row.
- **AD-29:** Lane A's Decide and installer are read-only, with the double until Stories 1.3 and 1.5.
- **AD-22:** destructive and production tests run only on throwaways.
- **AD-33:** Conversation is `chat.message`'s one publisher.
- **Conventions:** Identifiers (header and session ids may leave the server for trace links), Times, Live events, Logging, Tests, and the new DW-112 row below.

No AC contradicts an AD's Rule. Decided 3 refines AD-26's item-index wording; see the veto items.

**Rule 5:** no NFR is unmeasurable as worded. NFR-20 is measured by T1-T4 against Visual Trace itself.

**Decided in-stage** (small, reversible, within the intent):
1. **Split.** This spec is the story's server half: AC 1 and 2 of `epics.md`, DW-112, and DW-74 (declined below). The page half moves verbatim to a new sibling, planned next in Epic 2 before 2.10 (veto item 1):
   - AC 3, the trace links on the strip and the rail rows;
   - AC 4, the Visual Trace menu;
   - AC 5, the sign-in popover;
   - DW-58.

   The whole story would be about twice Story 2.8, which already ran oversized. Its two halves meet only at `traceUrl`. No AC is dropped, and REL-2's trace step stays Story 4.7's. The proposed block for `epics.md`:

   > ### Story 2.13: Open Visual Trace from the page
   > As a judge, I want every decision strip and rail row to link to the right place in Visual Trace, and a header menu that opens my conversation, so that I can follow the assistant's work from the page in one click.
   > **Acceptance Criteria:** Story 2.9's third, fourth and fifth Given/When/Then blocks, word for word (the row links and where they open, the Visual Trace menu, the sign-in popover), each using the `traceUrl` that `/state` and `/events` now carry (Story 2.9). The approval row's and reminder row's payloads gain their targets, the incident's trace and the waiter, where the row has one. `/state` carries today's thread for "Open my conversation".
   > - DW-58 (moved from Story 2.9 with its first consumer, the Visual Trace menu).

   Sprint key: `2-13-open-visual-trace-from-the-page`. Depends on Story 2.9.
2. **Where the index is computed.** The REST request runs as the signed-in user, who holds no SQL privilege on the `Ens` tables, and AD-13 bars any new unchecked read. So `Trace.Position` runs in `Conversation`'s production job when it takes the Item. The Turn keeps the result, `chat.message` carries it, and `TraceLink` only divides it by the viewer's page size at serve time.
   - Items logged before the target are complete by then. A row with an earlier time committed after `Take` is a millisecond race (inference).
3. **What the index counts.** It counts exactly what Visual Trace draws, read from source (Code Map):
   - an event or rule row is drawn only once its host is on an earlier header;
   - an I/O row is drawn only for a request up to the target.

   AD-26's sentence "every event-log, rule-log and I/O-log row … logged up to the target's creation" over-counts in those cases. T1-T4 are the oracle.
4. **The viewer's settings** come through `EnsPortal.VisualTrace`'s own `GetItemsPerPage`/`GetShowEvents`, measured outside CSP, in the target's namespace. So nothing reads `^EnsPortal.Settings` directly (the Settings convention), and the public accounts' pinned 100 is read the same way.
5. **PAGE only when an index is known.** Only turns carry one now. A decision opens its session at page 1, with Visual Trace's details pane on the target, as `SESSIONID` selects it (`VisualTrace.cls:952-961`).
6. **The URL** is path-only, on the page's own origin. There is no URL, and no key, for a target with no application.
7. **Join's lock** is the Session row's own `%LockId`. Join holds it only across a first-of-day send, waiting at most 2 s. A failure sends the turn in its own session, because a user's message is always answered (product default 2).
8. **The day** is `Data.Time.ToLocal`'s local date, the one zone conversion. `ThreadProduction` simulates midnight by setting `ThreadDay` to yesterday, and `Test.Core.Trace` pins the midnight arithmetic with an explicit `now`. On a UTC instance, a UTC-date mutation is indistinguishable (Verification).
9. **The Decide double in the production** is a runtime swap on throwaways only, restored after the class (Task 0a). It sends two AgentStep messages a request: the "agent steps" of the AC. The response it returns is the decision message, and its Decision rows carry its own session as `TraceSessionId`.
10. **`RetryItemId`** is deterministic: it is derived from the turn's ItemId, keeps AD-6's 22-character form, and is the same on a re-run after a restart. So `Decide`'s one-row rule answers a re-run rather than spending a second call.
    - `TurnCost` sums triage plus the retry (the Turn's two DecisionRefs). The broken attempt's row stays in `RunCost`. A history rejected by the provider bills no tokens (inference, S2).
11. **The double refuses a second `turn` call per ItemId** while Record is on, as AD-20's Decide does. Without that, DW-112's pin would pass against the bug.
12. **"Only channel services call it"** becomes a static rule in `test-class-rules.sh`, the project's home for code rules.
13. **`ZzThread`** is a new fixture user (user and trace roles), so T1-T4 own their thread and their Visual Trace settings.
14. **I/O rows** always count, because Visual Trace's I/O switch is a per-CSP-session form value that the API cannot see, defaulting to on. Show internal items and ACK rows are left out (no OcuTalon message is either).

**Veto-window items for the lead** (unattended policy):
1. **The split**, which moves AC 3-5 and DW-58 to a not-yet-planned sibling in this epic (veto 7). The proposed block is under Decided 1. Nothing a release gate depends on moves: REL-2's trace step is Story 4.7's `notBuilt`.
2. **Stored-data change** (veto 3):
   - `Session` gains `ThreadSessionId` and `ThreadDay`;
   - `Turn` gains `TraceItemIndex` and `TraceItemIndexNoEvents`;
   - the `chat.message` payload gains `traceItemIndex` and `traceItemIndexNoEvents`.

   The storage is appended only. The AC itself says the thread is kept on the Session row.
3. **AD-26's item-index wording** (veto 9; Rule 5 apply-and-report). Recommended amended bullet:

   > The item index is the target's position in Visual Trace's own list of its session: the headers in ID order up to the target, each event-log and rule-log row placed before the first header created after it once its host is the source or target of an earlier header, and each I/O-log row received before a header whose request id is at most that header's. `OcuTalon.Core.Trace.Position` computes it, with events shown and hidden, in the production job that first handles the target (`Conversation` for a turn). The target's row keeps both, and `TraceLink` divides by the viewer's page size.

   There is no new dependency, privilege, secret, live region or public text. `ZzThread` exists only on throwaways.

**Lead's rulings at the spec gate (2026-10-23).**
- **The split** is applied (U5: a split into a sibling planned next in the same epic is decide): AC 3-5 and DW-58 moved word for word to Story 2.13 (`2-13-open-visual-trace-from-the-page`) in `epics.md`, planned next after this story; the 2.9 block carries the marker.
- **Veto U-40:** the stored-data items (veto item 2) are kept as planned.
- **DW-74** is re-owned to `burndown` (`by=spec_gate`); **DW-58** to Story 2.13.
- **DW-112's Conventions row** ("SessionBroken retry") is written in the spine with this spec's `RetryItemId` detail.
- **AD-26's item-index wording** (veto item 3) is an AD amendment, which in this parallel run is the orchestrator's (U7, U14): AD-26 is cited by Epic 1's in-flight specs. Pending its ruling.

**Spine notes for the lead (Rule 20, light path):**
- **A Conventions row, as given by the orchestrator, with the fix:** "A `SessionBroken` turn's retry is a new `Decide` call with a new `ItemId`; the broken attempt keeps its `error` fallback row (AD-20, AD-30)." Optional detail: "the retry's `ItemId` is `Conversation.RetryItemId(turn.ItemId)`, the first 22 base64url characters of SHA-256 of the turn's `ItemId` plus `/retry`; the Turn keeps its own `ItemId` and links to the retry's decision."
- **AD-26:** veto item 3's amended bullet, if the lead applies it.
- **Conventions, "Live events":** the web layer adds `traceUrl` (`OcuTalon.Web.TraceLink`) when it serves `/state` and `/events`. It goes to every payload object that carries `traceHeaderId` and `traceNamespace`, and is absent when no trace application serves the namespace. `chat.message` also carries `traceItemIndex` and `traceItemIndexNoEvents`.

**Integration ACs (Rule 1).**
- `WebChatIn` reads `Trace.Join`, and a day's turns land in one real trace session (`ThreadProduction`, on a throwaway).
- `Conversation` reads `Trace.Position`, and `chat.message` carries the index (`ThreadProduction`, `Test.Live.Payloads`).
- `Web.Api` reads `TraceLink`, and `/state` and `/events` carry `traceUrl` over real HTTP (api.spec).
- **Visual Trace itself, the real portal page, reads the URL** and renders the target turn on its page (T1-T4).
- The page has no consumer in this story. The first will be the sibling 2.13.

**Consumed-by:**
- **2.13 (proposed):** trace links on the strip and the rail rows, the Visual Trace menu (today's thread), and the sign-in popover.
- **4.7:** 06-trace's climax link.
- **12.6:** `TelegramIn` calls `Join`.
- **1.3 and 1.5, through Epic 11:** the real decision message and AgentSteps in the thread, which retire the double swap.
- **Epic 16 and the installer:** the busy check before a trace window, and the public accounts' pinned page size, which `Viewer` reads.
- **Epic 5 and Epic 8:** check and waiter targets, which TraceLink serves generically.

**Consumes:**
- 2.4: `Conversation`, `Turn`, `WebChatIn`, `DecideDouble`, `ConversationProbe`, `ConversationProduction` and `InProduction`;
- 2.2: `/state`, `/events` and `Live.Event`;
- 0.5: the payload classes and `payloads.mjs`;
- 0.6: the production and the stubs;
- Lane A's `Install.Step.Web`: the trace applications;
- 0.4: `Data.Time`;
- IRIS's `EnsPortal.VisualTrace`, read only.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `Join`'s lock follows `Session.ForUser`'s pattern.
- `Position`'s checked reads follow `Ownership.Watchers`'s pattern. It ports Visual Trace's counting, because no IRIS method gives it outside CSP: `BuildTraceInfo` writes `%session`'s temp global.
- The viewer's settings call IRIS's own getters.
- `DecideDouble`, `WebChatInProbe`, `Fixture.RemoveMessages` and `InProduction` are extended, and no new double is added.
- The lock holder follows `Test.Core.BridgeSink`'s `Hold`.
- api.spec's `post` and `sessionEvents` move to `web/e2e/support/` and are not copied.
- `setTraceSettings` follows `setTelegramIncluded`.
- `RetryItemId` has no sibling (`Ids.NewRef` is random).

**Ledger (Rule 17).**
- **DW-112** is addressed by Task 5, Task 9c, Task 15 and the AC "DW-112". This is HIGH, and must be resolved before the integrate-forward.
- **Declined DW-74:** the fix (Submit saving and restoring the caller's `$$$JobSessionId`/`$$$JobSuperSession` around `ProcessInput`, whose `Exit` kills them unconditionally, `irislib/Ens/BusinessService.cls:79`; read from source, not run) belongs in `Core/Commands.cls`, which is contended this run. `Trace.Join` cannot restore it (it runs in channel services at a turn's start, before any tool), and the runner is Lane A's. Recommended: re-own to the Epic 2 burn-down, with this evidence and its throwaway check.
- **Declined DW-58:** its first consumer, the Visual Trace menu, moves with the page half. Recommended: re-own to `2-13-open-visual-trace-from-the-page` once the lead creates it.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s29i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call, with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses `e2s29q` and review uses `e2s29r`.

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), in two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: all pass, and no `zz` row, header, log row or `^EnsPortal.Settings` node is left.
  - New or changed: `OcuTalon.Test.Core.Trace`, `Test.Web.TraceLink`, `Test.Core.WebChatMessages`, `Test.Core.ConversationTurns`, `Test.Web.Api`, `Test.Live.Payloads`.
  - Regression: `Test.Core.Intake`, `Test.Contract.Ac`, `Test.Data.Session`, `Test.Data.Ownership`.
- (loop) Each in its own call: `node web/scripts/payloads.mjs --check`, `npm --prefix web test`, `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh`. Expected: exit 0.
- (loop) Each in its own call: `bash docker/tests/test-class-rules.sh` (the new `trace-join` rule passes and its samples flag), `test-boundaries.sh`, `test-storage.sh`, `test-ci-config.sh` (run only, never edited). Expected: exit 0.
- (loop) Throwaway, one piece per call:
  - `build`;
  - `class OcuTalon.Test.Core.ThreadProduction`;
  - `class OcuTalon.Test.Core.ConversationProduction`;
  - `live sign-in`, which runs T1-T4 and every earlier chromium spec;
  - `teardown`.

  Expected: each passes, and teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `shard lane-b`; `shard lane-b --reverse`; `shard lane-a`; `live demo-path`; `teardown`. Expected: every class passes, `ThreadProduction` among them, and the demo path's floor count is unchanged.

**Planned mutations (Rule 19).** For each one, apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| One thread a day | `Accept` leaves `..%SessionId` unset | `TestTwoTurnsOneThread`; `TestJoinsTodaysThread` |
| One thread a day | `Join` ignores `ThreadDay` | `TestNewThreadAfterMidnight`; `TestNewThreadAfterLocalMidnight` |
| One thread a day | `Join` takes no lock | `TestBusyLockAndNoRowFail` |
| Never fails | `Accept` quits on a Join error | `TestJoinFailureStillSends` |
| Only channel services | `Conversation.Join` calls `Trace.Join` | `test-class-rules.sh` `trace-join` |
| Until 1.3 and 1.5 | The double sends no AgentStep | `TestTwoTurnsOneThread` |
| Item index | The host-on-diagram check is dropped | `TestPositionCountsAsVisualTraceDraws` |
| Item index | `Take` stores no index | `TestTwoTurnsOneThread`; `Test.Live.Payloads` |
| Trace URLs | `PAGE = i \ size + 1` | `Test.Web.TraceLink` (40 gives 2) |
| Trace URLs | A page size fixed at 40 | `Test.Web.TraceLink`; T2 |
| Trace URLs | `Add` does not recurse | `Test.Web.TraceLink`; `TestStateChatDecision` |
| Trace URLs | `EventsBody` not walked | `Test.Web.Api` `TestEventsBody`; api.spec |
| Trace URLs | OCUORDERS URL without demo mode | `Test.Web.TraceLink` |
| Opens on the turn | `Position` counts no events | T1 or T3 |
| DW-112 | `Ask` keeps the turn's `ItemId` | `TestBrokenRetryIsANewItem` |

Not falsifiable on a UTC instance: `Day` using the UTC date (Decided 8). `Data.Time.ToLocal` is the one conversion.

**Shared surfaces:**
- The `Session` row (`ThreadSessionId`, `ThreadDay`) and the `Turn` row (two indexes).
- The `chat.message` payload (two keys), with `payloads.ts` and `Test.Live.Payloads`' oracle.
- Every `/state` and `/events` payload object with a target, which gains `traceUrl`. That affects `Test.Web.Api`, api.spec, decision.spec and any exact-equality assertion (Task 24).
- `DecideDouble`: production-mode AgentSteps, `TraceSessionId`, and the AD-20 refusal while Record is on (`ConversationTurns`, `Test.Core.Intake`).
- `WebChatInProbe`'s records.
- `Fixture.RemoveMessages`, which now also deletes the found sessions' remaining headers, rule-log rows and I/O-log rows; and the new `Fixture.SessionHeaders`.
- `ConversationProduction`'s Items, which now share one thread per session.
- `test-class-rules.sh`'s rules.
- `fixtureUser`'s kinds, and `test-sign-in.sh`'s users and labels.
- The throwaway production's `Decide` item during `ThreadProduction`, which is restored.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` classes make and remove their own rows, headers, log rows and settings;
- `ThreadProduction` restores `Decide` in `OnAfterAllTests`;
- trace.spec owns `ZzThread`, never assumes an empty thread, and restores its settings in `finally`.

**Manual checks:** none.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
