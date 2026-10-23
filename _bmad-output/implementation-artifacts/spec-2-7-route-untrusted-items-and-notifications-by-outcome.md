---
title: 'Story 2.7: Route untrusted items and notifications by outcome'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: 'cd7264f1b5e461d0326a93413277441363efcf64'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing arriving from outside the conversation reaches the user yet. `Intake`, `WebChatOut` and the `OutcomeRouter` and `Notify` rules are Epic 0 stubs, and `Delivery.Record` and `FindByApproval` are stubs too. So an untrusted item is never decided or routed, and no notification reaches a channel. Separately, a reload would lose every notice card, because no table keeps a delivered card's text (DW-62).

**Approach:**
- **Server.**
  - Build `Intake`: render, decide, an untrusted fresh turn on `act`, then the `ItemDecision`.
  - Build the two routing rules, with a transform from an `ItemDecision` to a `Notification` and a small function set.
  - Build `WebChatOut`: it renders through `Msg.Catalog.Render`, keeps the card on its `Delivery` row, and publishes `notification`.
  - Implement `Delivery.Record` and `FindByApproval`, and merge the kept cards into `/state`'s chat.
- **Page.**
  - The tell-now and reminder notice cards in the chat.
  - Page times that name the browser's zone when it differs from the instance's.
  - A CI check that an untrusted item becomes a tell-now card within 5 seconds.

## Boundaries & Constraints

**Always:**
- **Intake (AD-6, AD-10, AD-14, AD-26, AD-30).** `OcuTalon.Core.Intake` loses `Parameter STUB`. It takes an `OcuTalon.Msg.Item`. Like `Conversation`, it never waits on a call: every send goes through one private seam, `Send(target, request, responseRequired, key)`, which calls `SendRequestAsync`.
  - **Refused items.** It logs a warning (`$$$LOGWARNING`) and sends nothing for:
    - a message that is not an Item;
    - provenance other than `untrusted` (user text goes to `Conversation`, NFR-14);
    - an empty `ItemId` or an empty owner (`SessionRef`);
    - no `Text`, `Subject` or `Sender`.
  - **The trace.** It keeps the session of its inbound header, which is the item's own trace session (AD-26). It sets `%SuperSession` to the owner session's `TraceRef` when the header carries none and the owner is a session.
  - **The decide request.** It sends `Decide` (key `decide`, an answer required) the request from a new public `ClassMethod RequestFor(item, kind, traceRef, threadSessionId) As OcuTalon.Bridge.Msg.Request`. That request carries:
    - `Kind`;
    - `Provenance` (the item's);
    - `Input` = `OcuTalon.Agent.Input.Render(item)`;
    - `ItemId` and `Summary`;
    - `OwnerRef` = the item's `SessionRef`;
    - `TraceRef`, `Channel` and `ThreadSessionId`.

    `Conversation.Request` calls `RequestFor` too (Design Notes, Rule 2).
  - **Summary.**
    - For an item with a `Sender` or `Subject`: "{Sender}: {Subject}", or the one that is set.
    - Otherwise: the first line of `Text`.
    - Either way it goes through `Conversation.Summary`'s cut: 80 characters, ending in "…" when cut.
  - **Decide's answer.**
    - A `DecisionResponse` whose `Outcome` is in `Msg.Enum` OUTCOME gives `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`. A fallback's outcome is `tellnow`, and a reason outside FALLBACKREASON becomes `unusable`.
    - Anything else gives the fallback: `Outcome` `tellnow`, `Fallback` 1, `FallbackReason` `unusable`, an empty `DecisionRef`. That covers an error status, no answer, another class and an unknown outcome.
  - **Act.** On a non-fallback `act`, Intake first sends a `turn` request (key `turn`): the same `RequestFor` fields with `Kind` `turn`, `SessionMode` `fresh` and no `SeedText`.
    - Whatever the turn answers, or if its send fails, Intake then sends the `ItemDecision`. The turn's reply is not delivered (Design Notes, Decided 4).
    - A `Busy` answer is not expected (AD-6 exempts fresh untrusted turns) and is handled like any other answer.
  - **The ItemDecision** has the fields the AC lists:
    - from the Item: `ItemId`, `SourceItemId`, `OwnerRef`, `Channel`, and its `CatalogKey` and `Slots`;
    - `Summary`: the request's;
    - from Decide's answer, as above: `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`.

    It goes asynchronously, with no answer, to `OutcomeRouter` (a session or `instance` owner) or to `EvalSink` (owner `eval`), never both.
  - **What Intake never does.** It never sends to `Conversation` or `Notify`, never writes a `Turn` row and never publishes a live event.
- **OutcomeRouter (`OcuTalon.Core.Rule.Outcome`, AD-30, AD-32).** It loses STUB and keeps `RuleAssistClass`. Its one rule set routes `OcuTalon.Msg.ItemDecision` (a `msgClass` constraint) on named properties only:

  | ItemDecision | Action |
  | --- | --- |
  | `OwnerRef` `eval` | nothing |
  | `Outcome` `digest` | send to `DigestStore`, unchanged |
  | `Outcome` `tellnow` or `act`, and `IsSession(OwnerRef)` | send to `Notify` through the transform `OcuTalon.Core.Rule.Notice` |
  | anything else (ignore; an `instance` tell now or act) | nothing |

  For Ignore, the record is `Decide`'s `Decision` row plus the ItemDecision that the router received.
- **The transform `OcuTalon.Core.Rule.Notice` (an `Ens.DataTransform`).** It turns an ItemDecision into a `Notification` with:
  - `SessionRef` = `OwnerRef`, `Kind` `tellnow` and its `DecisionRef`;
  - the `CatalogKey` and `Slots`, chosen in this order:
    1. **A CatalogKey on the ItemDecision:** that key and its slots, as they are.
    2. **A fallback:** `notice.tellNowFallback` with `{"whatHappened": Summary, "reason": FallbackReason}`, the reason `unusable` when it is empty or unknown.
    3. **Otherwise:** `notice.tellNow` with `{"whatHappened": Summary, "reason": <the first line of the Decision row's Reasons>}`, read through `Ownership.Decision(DecisionRef, OwnerRef)`.

  It returns an error, and the router logs it and sends nothing, when:
  - the row is not visible;
  - its first reason line is empty;
  - `Summary` is empty for case 2 or 3.

  It renders no text.
- **Notify (`OcuTalon.Core.Rule.Notify`, AD-4, AD-14).** It loses STUB and keeps `RuleAssistClass`. It routes on the message class, `Kind`, `OriginChannel`, `ChatRef` and the session's channels.
  - **The functions.** "Paired" means `TelegramPaired(SessionRef)`: `Telegram.In.Included()` and a `Pairing` row for the session (`Ownership.Pairing`). "Demo on" means `DemoOn()`, the `demo.mode` setting being "1".

  | Message | Targets |
  | --- | --- |
  | `Outbound` (a reply) | `WebChatOut`; also `TelegramOut` when `OriginChannel` is `telegram` and the session is paired |
  | `Notification` kind `pairing` | `TelegramOut` alone when `ChatRef` is set and `TelegramOn()`; otherwise none |
  | `Notification` kind `allowance` | `WebChatOut`; also `TelegramOut` when paired |
  | `Notification`, any other kind | `WebChatOut`; also `SimPhoneOut` when demo is on; also `TelegramOut` when paired |
- **The function set `OcuTalon.Core.Rule.Functions` (an `Ens.Rule.FunctionSet`)** has the class methods `IsSession(ref)`, `DemoOn()`, `TelegramOn()` and `TelegramPaired(sessionRef)`. No other function set may use these names (Task 0).
- **WebChatOut (`OcuTalon.Channel.WebChat.Out`, AD-12, AD-14, AD-32, AD-33).** It loses STUB. An `XData MessageMap` maps `Notification` to `OnNotification` and `Outbound` to `OnOutbound`.
  - **Who gets it.** It acts only when the message's `SessionRef` is a session (`Session.Recipients` gives it back). Otherwise it logs a warning and records nothing.
  - **Card kinds (`tellnow`, `reminder`).**
    1. It renders `Msg.Catalog.Render(CatalogKey, Slots, "web", .sc)`. A render error returns the error, with no row and no event.
    2. It records the row through `Delivery.Record`. The row is the card:
       - `ChannelMessageId` is the card's new Ref (`Bridge.Ids.NewRef()`);
       - `Kind`;
       - `Text`: the whole rendered text;
       - `DecisionRef`;
       - `DueAt`: the slot `dueAt` of a reminder;
       - `FallbackReason`: the value of the slot that the key's catalog entry declares as type `fallbackReason`, if it has one.
    3. After the save it publishes `notification` on the session's stream, with `Live.Payload.Notification.FromRow(row)`. A failed publish is logged, and the row stays.
  - **Every other kind** records its `Delivery` row only (no text, no event) until the story that designs that kind's web form.
  - **A reply (`Outbound`)** records its `Delivery` row only: channel `web`, no `ChannelMessageId` (the page shows the turn) and its `DecisionRef`.
- **Delivery (AD-14, AD-33; DW-62).**
  - `Record(ownerRef, channel, channelMessageId, approvalRef, kind = "", text = "", decisionRef = "", dueAt = "", fallbackReason = "") As %Status` saves one row with `RecordedAt` = `Data.Time.NowUtc()`. It refuses an empty owner, and a channel outside CHANNEL. The pinned leading parameters stay.
  - **Appended properties:** `Kind` (32), `Text` (`MAXLEN = ""`), `DecisionRef` (22), `DueAt` (20) and `FallbackReason` (32), plus `Index OwnerRefChannelIndex On (OwnerRef, Channel)`.
  - `FindByApproval(approvalRef, channel, ownerRef)` gives the `ChannelMessageId` of the newest row whose three values match exactly (case-sensitive), read through `Ownership.DeliveryFor`. It gives "" otherwise, `instance` and `eval` owners included.
- **New Ownership row kinds (AD-13 as amended).** Each has fixed SQL with the owner in its `WHERE` and joins `TestIsolationEveryRowKind`. There is no new unchecked prepare.
  - `recentNotices` (`ao`): `SELECT TOP ? ID FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND Kind IN ('tellnow', 'reminder') ORDER BY RecordedAt DESC, ID DESC`.
  - `deliveryByApproval` (`aao`): `SELECT ID FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ? AND Channel = ? AND OwnerRef = ? ORDER BY ID DESC`.
  - Their public methods are `RecentNotices(sessionRef, max = 100, *sc)` and `DeliveryFor(approvalRef, channel, sessionRef, *sc)`.
- **The snapshot's chat (DW-62).** `Web.Api.ChatItems` also reads `RecentNotices(sessionRef, CHATMAX)`. It merges them as `{"type": "notification", "payload": FromRow(row)}` at rank 2, by `RecordedAt`: at the same second a turn comes first, then an incident, then a card. The newest `CHATMAX` stay, oldest first, and the key list does not change.
- **The `notification` payload (AD-12).** `Live.Payload.Notification` gains `Decision As OcuTalon.Live.Payload.Decision(%JSONFIELDNAME = "decision")` and `FallbackReason As %String(%JSONFIELDNAME = "fallbackReason", MAXLEN = 32)`, each on one line. It also gains `FromRow(row As OcuTalon.Data.Delivery)`, which sets:
  - `ref` = `ChannelMessageId`, `kind`, `decisionRef`, `approvalRef`, `dueAt`, `fallbackReason`, and `createdAt` = `RecordedAt`;
  - for `tellnow`, when the text has two or more lines: `text` = every line but the last, and `whyNow` = the last line (the catalog puts "Why now:" on its own last line). Otherwise `text` is the whole text and `whyNow` is "";
  - `decision` = `Decision.FromRow(Ownership.Decision(DecisionRef, OwnerRef))` when found. A failed read leaves it empty and never fails the publish or `/state`.
- **The catalog (AD-32).** `Catalog.Core` gains `notice.tellNowFallback`:
  - text: `"{whatHappened}\nWhy now: {reason}"`;
  - slots: `whatHappened` (`text`) and `reason` (`fallbackReason`);
  - source: "EXPERIENCE Message Catalog / Notifications and reminders / Tell now; Component Patterns / Fallback flag".
- **The notice card (UX-DR69, D:799, mockup `states.html:572-610`).** A new `app-notice-card` renders a `NoticeView` for kinds `tellnow` and `reminder` only. It has no title or heading, and the text is rendered by interpolation only.
  - **A tell-now card:**
    - a 4px `attention` bar (`--notice-card-accent-bar-tell-now`);
    - `bell-ring` in `--attention-ink`, `aria-hidden`;
    - `text`, then the `whyNow` line;
    - `app-decision-strip` with `[reasons]="false"`, which shows line 1 and Details only (mockup B5).

    The strip shows:
    - the decision's own cost (`decision.costUSD`, EXPERIENCE:254);
    - a fallback (the payload's `fallbackReason`, or the decision's `fallback`): the chip "Tell now" and the Fallback flag, with no confidence;
    - with no decision: no confidence, no cost and no Details.
  - **A reminder card:** an `info-ink` bar, `bell` in `--info-ink`, `text`, then the caption "Due {time} · arrived {time}" in `t-cap`, from `dueAt` and `createdAt`. The caption is left out when `dueAt` is empty.
  - **Page times (UX-DR123).** The caption's times come from a new `pageTimeBeside(iso, instanceZone, locale?, timeZone?)`: `pageTime(iso)`, followed by the browser zone's short name (`timeZoneName: 'short'`) when the browser zone's UTC offset at that instant differs from the instance zone's, or when the instance zone is not a valid zone. `instanceZone` comes from the snapshot.
- **The chat list.** `chatView` returns `ChatEntryView = TurnView | NoticeView`, in store order. Each entry has `entry: 'turn' | 'notice'`, and a notice's key is `notification:<ref>`.
  - A `notification` of another kind renders nothing.
  - `newest` still marks the last turn strip.
  - The panel branches on `entry`. Arrival tracking (`noteArrivals`, `data-part`) learns a `notice` part, so a card that lands while the reader has scrolled up shows **New messages**, as a reply does. No focus moves when a card lands.
- **Fixed strings** are exported constants with escaped non-ASCII (Rule 14): `NOTICE_TEXTS.due` "Due {time}" and `arrived` "arrived {time}", joined by `CHAT_TEXTS.separator`.
- **Tests (AD-22, Rule 19).**
  - Browser specs that send items or notices sign in as the new fixture user `NOTICE` (`ZzNotice`, the user role).
  - `%UnitTest` classes use `Test.Data.Fixture` and `Fixture.Clean(refs)`. `Clean` also deletes the `Delivery` rows of the fixture sessions it deletes, so rows made by the production go with their session.
  - Node-tested modules import only types.

**Never:**
- **Contended paths are read-only** (Lane A and the other running epics):
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Checks,Eval,Watch}/**`;
  - `Install/**` and `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`, except the one ruled edit of `Test/Install/Production.cls` (Tasks & Acceptance: TestStubsAnswer's rule-class loop only);
  - `Data/Public/**`, `Data/{StatusMark,Time,Reminder}.cls`, `Core/Commands*.cls`, `Schedule/**` and `Msg/Tick.cls`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts`, `release/**` and `lane-a.yml`;
  - `test-pinned-sources.sh`, and every row of `test-production.sh` but Lane B's Intake line.

  Calling `Agent.Input.Render`, `Bridge.Ids.NewRef`, `Telegram.In.Included` and `Install.Step.Demo.#MODEKEY`, and sending to `DigestStore` and `EvalSink`, is allowed.
- **Never edit** `Production.cls` (no item or setting changes), `docker/merge.cpf` or `ALLOW_UNCHECKED`.
- **Never build another story's part:**
  - 1.12: `DigestStore`'s store;
  - 2.8: the rail;
  - 2.9: any trace link (the card strip's "· Trace" included);
  - 2.12: announcements, the Firefox and WebKit runs, the accessibility scan;
  - 4.5: `SimPhoneOut`, and the phone half of the 5 s check;
  - 4.6: `SimMailboxIn` and its endpoints;
  - 6.x: incident and approval cards;
  - 8.x: `ReminderTimer` and its notifications;
  - 9.x: `EvalSink`;
  - 10.3: pairing;
  - 12.6: `TelegramOut`;
  - 16.x: the web form of `allowance`.
- **Never** let a producer render text, show a notice as HTML, put a trace link on a card, add a dependency, or change the snapshot's key list or `POST /messages`.
- **Never run on slot B:** `Test.Core.RoutingProduction`, `ConversationProduction`, `CommandsInProduction`, `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` or `Test.Demo.Production`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Item decided | Untrusted mail Item of session S; Decide answers `tellnow` D | One `decide` request (untrusted, Summary "Sender: Subject"); one ItemDecision to OutcomeRouter with every field | — |
| Act | Decide answers `act` | A `turn` request (untrusted, `fresh`, no SeedText), then the ItemDecision (`act`, D's ref) | Turn error: the ItemDecision is still sent |
| Eval | Item owned by `eval` | The ItemDecision goes to EvalSink only; nothing at OutcomeRouter, Notify or WebChatOut; no Delivery row or event | — |
| Decide fails | Error status, no answer, wrong class, unknown outcome (the stub) | ItemDecision `tellnow`, Fallback 1, `unusable`, no DecisionRef | — |
| Refused | User provenance; no ItemId, owner or content | Nothing sent | Warning logged |
| Outcomes | Fixture ItemDecision of each outcome, with and without CatalogKey | ignore: nothing; digest: to DigestStore; tellnow and act: one `tellnow` Notification to Notify | Transform error: logged, nothing sent |
| Tell now text | D's Reasons "zz first\nzz second"; Summary "zz Dana: Invoice" | `notice.tellNow`; card text "zz Dana: Invoice", then "Why now: zz first."; strip line 1 "Tell now", confidence, D's cost, Details | — |
| Code key | CatalogKey `watch.productionStopped` | That key and those slots; card shows its two lines | — |
| Fallback card | ItemDecision fallback `refusal`, no row | `notice.tellNowFallback`; card "…", then "Why now: the model declined to answer"; chip Tell now and Fallback; no confidence, cost or Details | — |
| Instance | `instance` tell now or act | No Notification | — |
| Notify targets | Each kind × demo on/off × paired or not × Telegram included; Outbound web/telegram | The table in Boundaries | — |
| Reply | Outbound from Conversation | One Delivery row (S, web, its DecisionRef); no `notification` event | — |
| Reminder card | `reminder.due` {text: "stretch", dueAt: 12:00Z}, browser zone = instance zone | "Reminder: stretch.", then "Due 12:00 · arrived HH:MM" | No dueAt: no caption |
| Other zone | Browser Europe/Berlin (en-GB), instance UTC, dueAt 2026-07-15T12:00:00Z | "Due 14:00 CEST · arrived HH:MM CEST" (CET in winter) | Invalid instance zone: suffix shown |
| Delivery | Two rows for (A1, telegram, S); one of another owner | `FindByApproval(A1, telegram, S)` gives the newest of S's; a case-changed ref gives "" | Empty owner: Record errors |
| Reload | Turn 2024, a card now, a turn 2099 | `/state` and the page: turn, card, turn | — |
| Five seconds | Untrusted Item into Intake through the real production | A tell-now card with its summary in the web chat within 5 s of the send | — |

</intent-contract>

## Code Map

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls:1-19`: the stub, with `STUB` at `:7` and `OnRequest` at `:9-12`. Build it as Conversation is built (`Core/Conversation.cls`):
  - the constants `:44-62`;
  - `OnError` and `OnResponse` (dispatch by key) `:134-154`;
  - `Begin`'s send and its error branch `:290-312`;
  - `Request` `:329-342` and `ItemOf` `:345-356`, which build from a Turn and hard-code `user`;
  - `Summary` `:360-365`, a public ClassMethod with an 80-character cut;
  - `Decided` `:369-381`, `Replied` `:414-428`, `Send` `:645-648`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls:329-342`: `Request` becomes a call of `Intake.RequestFor(..ItemOf(turn), kind, ..%SuperSession, ..%SessionId)`. The fields stay as they are; `TestSourceKeepsToItsBoundaries` (`Test/Core/ConversationTurns.cls:873`) allows `Intake`.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Outcome.cls`, `Notify.cls`: both have `:1-19`, with `RuleAssistClass` `:5`, `STUB` `:9` and an empty rule set `:11-17`. The rule XML shape (`<rule>`, `<constraint name="msgClass">`, `<when condition="Document.Outcome=&quot;digest&quot;">`, `<send transform="…" target="A,B"/>`) and the evaluation order (each `<rule>` is evaluated; within a rule, the first `<when>` wins) come from `irislib/Ens/Rule/Generator.cls:156-178,378-399,522` and `irislib/Ens/Rule/Model/expression.cls:654,715-717`.
  - Function sets: `irislib/Ens/Rule/FunctionSet.cls:8-11` and `irislib/Ens/Rule/Utilities.cls:41,77-98`.
  - The router sends with `SendRequestAsync` and no `ResponseFrom`, so a target's error stays with the target (`irislib/EnsLib/MsgRouter/RoutingEngine.cls:363-423`). A transform error is logged and its send is skipped (`:395-399`).
- New: `Core/Rule/Notice.cls` (`Ens.DataTransform`, `Transform(source, ByRef target, ByRef aux)`, `irislib/Ens/DataTransform.cls:67`) and `Core/Rule/Functions.cls` (`Ens.Rule.FunctionSet`).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls:1-14`: the stub.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls`:
  - the properties `:9-21`;
  - the index `:23`;
  - `Record` `:28-31`, which errors as a stub;
  - `FindByApproval` `:35-38`;
  - the storage `:40-68`, where new slots go after `RecordedAt`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `Decision` `:244-251`, the pattern for `DeliveryFor`;
  - `RecentTurns` `:152`;
  - `Pairing` `:223`;
  - `Rows` `:307-350` (the `instance`/`eval` refusal `:312-313`);
  - `Statement` `:355-431` (`recentTurns` `:362` and `decisions` `:386-389` are the shapes);
  - the class comment `:5-12`.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:76-93`: `Recipients` gives `instance` without an incident no session.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `CHATMAX` `:29-30`;
  - `StateBody`'s doc `:248-255`;
  - `ChatItems` `:295-336`, whose rank-1 incident line `:312` is the pattern for rank 2;
  - `PayloadObject` `:381-385`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Notification.cls:1-32`: nine properties and no methods. `ChatMessage.FromRow` (`ChatMessage.cls:58-83`, with `SetDecision`) is the pattern; `Decision.FromRow` is at `Payload/Decision.cls:67-91`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls`:
  - `Publish(stream, type, payload, Output seq, lockWait)` `:52`, which refuses inside a transaction (`:55`);
  - `IsStream` `:43`;
  - `TYPES` `:10` (`notification:Notification`).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`:
  - the slot types `:1-29`;
  - `Render` `:51-61`, which reads `Public.Settings.Get("onlineDemo")`;
  - an empty string slot is an error (`SlotText`);
  - `Entry(key, *sc)` `:79` gives the slot types.

  `Msg/Catalog/Core.cls:236-258` holds `notice.tellNow`, `reminder.due` and `reminder.late`. `Catalog/Watch.cls:12,20` holds `watch.productionStopped` and `watch.itemDisabled`.
- Read-only:
  - `Msg/{Item,ItemDecision,Notification,Outbound,Enum}.cls`;
  - `Core/BridgeSink.cls:43-60` (`IsSession`, the Ownership read);
  - `Bridge/Ids.cls:7-10`;
  - `Channel/Telegram/In.cls:20-23`;
  - `Agent/Input.cls:7`, a stub that returns "" here (on `OCT-epic1`, `Render(item, now = "")` quotes untrusted text);
  - `Digest/Store.cls` and `Eval/Sink.cls`, both stubs that answer 5003;
  - `Channel/SimMailbox/In.cls` and `Core/NoticesIn.cls`, adapterless stubs that the tests use only as sending hosts;
  - the bridge `Request`, `DecisionResponse` and `Reply` (`src/bridge/cls/OcuTalon/Bridge/Msg/*.cls`);
  - `Decision.Reasons`, one reason per line (`Bridge/Data/Decision.cls:27`).

**Server tests (Lane B, edit or new)**
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls`:
  - `OnRequest` `:31-121`, where a non-turn kind answers the scripted outcome or `fallback:<reason>` (`:100-116`);
  - `Script` `:157-167`, `Record` `:144-147`, `Written` `:150-153`, `Seen` `:170-187`, `Clear` `:191-194`;
  - `:35` subscripts by `OwnerRef`, so an empty owner throws.
- `Test/Core/ConversationProbe.cls:37-83,122-144`: `Send` (with a shadow DecideDouble) and `Deliver`. This is the pattern for the new `IntakeProbe`.
- `Test/Core/InProduction.cls:12,32-74`: the guard and `Session`. `ConversationProduction.cls` has `Send` `:312-322`, the `Wait*` helpers `:325-367` and the Outbound checks `:110,206,256,303`.
- `Test/Data/Fixture.cls`:
  - `Session` `:15`, `Decision` `:111`, `Usage` `:130`, `Pairing` `:156`;
  - `Clean` `:243-265`, `RemoveMessages` `:271`, `Headers` `:301`, `Between` `:312`;
  - `Keep` and `Record` `:323-336`.
- `Test/Data/Ownership.cls`:
  - `TestIsolationEveryRowKind` `:308-338` (its kinds `:318`);
  - `TestRowsRefuses` `:343`;
  - `Seed` `:613-631`, `ReadAll` `:636-681`;
  - `Refs` `:684-692`, where a Delivery row has no `Ref`.
- `Test/Data/Tables.cls`: `TestDeliveryStubs` `:85-92` (it is removed), the `Delivery` oracle `:413-425`, the registry row `:617-621`.
- `Test/Web/Api.cls`: `TestStateSections` `:159` (4 entries, `:199`), `TestStateChatCapped` `:247`, the ties at `:322`, `Items` `:1070-1076`.
- `Test/Live/Payloads.cls`: `TestContracts` `:74-93` (27 classes, unchanged), the Notification contract `:561-574`, `TestFromRowBuilders` `:333-435`.
- `Test/Msg/Catalog.cls`: the header `:3`, the 63 Core keys `:80-83`, the 85 fixtures `:121`.
- `Test/Core/ProductionItems.cls`: `:19` (WebChatOut) and `:28` (Intake) become `"stub": 0`; `:29-30` are unchanged.
- `Test/Contract/Ac.cls:292-293,313,339`: the pinned leading parameters of `Delivery.Record` and `FindByApproval`, `Agent.Input.Render` and `Msg.Catalog.Render`.
- `docker/tests/test-production.sh:129-152`: row 16's line `CHK|sync|Intake|0|<Ens>ErrBPTerminated|1|0` (`:131`) is Lane B's, and the header's Intake clause is at `:12-13`.

**Contended (Lane A), one ruled edit (orchestrator ruling, 2026-10-23, U14, option (a))**
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:158-166`: `TestStubsAnswer`'s rule-class loop (`For class = "OcuTalon.Core.Rule.Outcome", "OcuTalon.Core.Rule.Notify"`) asserts that both rule classes carry STUB and have one rule set with no rule. On `OCT-epic1` the same lines are `:173-181`. Only this loop may change; the class header comment (lines 1-20) and every other line of the file stay as they are.

**Page (Lane B, edit or new)**
- `web/src/app/chat/chat-view.ts`:
  - the header `:7-9` ("notice entries render nothing yet (… 2.7)");
  - `CHAT_TEXTS` `:22`;
  - `TurnView` `:80-104`;
  - `messageOf` `:133-135` and `keyOf` `:138-140`;
  - `chatView` `:197-270`, where notices are skipped at `:207-210`;
  - `isFreshChat` `:304-306`.
- `web/src/app/chat/chat-panel.ts`:
  - `Target` `:29-35`;
  - the template `@for (turn of turns(); …)` `:65-71`;
  - `fresh` `:167` and `turns` `:175-188`;
  - `noteArrivals` `:194,260-276`;
  - the `[data-part]` lookup `:252-255`.
- `web/src/app/chat/decision-strip.ts`: the inputs `:166-174`, the reason lines `:204`, Details `:68-80`. `ocutalon-reply.ts:77-85` passes them.
- `web/src/app/chat/page-time.ts:24` (`pageTime`, which adds no zone name today) and `web/scripts/page-time.test.mjs`.
- `web/src/app/icon/icon.ts:4-23` has `bell-ring` and lacks `bell`.
- `web/src/app/live/live-store.ts`:
  - `notification` already joins `chat` by `ref` (`:41`);
  - `chatKey` `:95-97`;
  - a live entry is appended (`:147-153`).
- `web/src/app/live/payloads.ts:105-115` (generated) holds `NotificationPayload`. `api-types.ts:34` holds `instanceZone`, which `LiveState.snapshot()` returns (`live-state.ts:57`).
- `web/src/styles/tokens.css` is generated and read-only:
  - `--notice-card-*` `:372-380`;
  - `--attention` `:21`, `--attention-ink` `:24`, `--info-ink` `:32`;
  - the dark blocks `:695-698,918-921`.
- UX:
  - `EXPERIENCE.md`: `:180` (times), `:254` (a card's cost), `:263` (fallbacks notify), `:267` (notice card), `:763-765` (texts);
  - `DESIGN.md:799`;
  - mockups `states.html:183-190,572-576,605-610` and `main-page.html:204-206,453-456`.

**Browser and CI tests (Lane B, edit or new)**
- `web/e2e/support/iris.ts`:
  - `fixtureUser` `:15-17`, `irisScript` `:39-54`, `chk` `:57-60`;
  - `publishReminder` `:69-84` and `sinkEvent` `:334-343`, the patterns for the new senders;
  - `seedTurns` `:272-327`.
- `docker/tests/test-sign-in.sh`: the users `:117` and the environment `:176-190`.
- `web/e2e/chat/decision.spec.ts:267-293` (D6's timed `toHaveText`) and `chat.spec.ts:880-892` (C14, Berlin en-GB) are the patterns.
- `web/e2e/demo-path/not-built.ts`: `notBuilt(title, story)`.
- `ci/mock/scenarios/A/refusal.json`: marker `refusal`, a 200 with `stopReason` refusal. It is read-only and used as a marker only.

## Tasks & Acceptance

**Execution:**
- **The ruled Lane A edit (orchestrator ruling 2026-10-23, U14, option (a); a one-time footprint extension).** In `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`, inside `TestStubsAnswer`'s rule-class loop only (`For class = "OcuTalon.Core.Rule.Outcome", "OcuTalon.Core.Rule.Notify" {`), add as the loop's first statement a guard that skips a class whose `STUB` parameter is not 1 (`If +$Parameter(class, "STUB") '= 1 Continue`), with its explanation as an inline comment beside the loop (the STUB and empty-rule-set assertions hold only while a rule class is still a stub). Do NOT touch the class header comment (lines 1-20; Epic 1 rewrote it on `OCT-epic1`) or any other line of the file. The `lane-a` shard's `Test.Install.Production` then passes with both rule classes built (Verification's `shard lane-a`).
- **Task 0** (implement stage; recorded under `## Verification`).
  - On slot B, a temporary test evaluates the built rules with `Ens.Rule.RuleDefinition.EvaluateRulesEx(rule, "", context, "", .ret, .reason, 1, "e")`. The context is an `EnsLib.MsgRouter.RoutingEngine` shadow instance with `Document`, `MsgClass` and `Source` set. Record the `ret` format (for example `send:WebChatOut:;send:SimPhoneOut:`).
  - If rules cannot be evaluated off a production on slot B, `Test.Core.Routing`'s rule methods move into `Test.Core.RoutingProduction` (throwaway only) and read the headers each router sent; say which.
  - Grep `irislib` and `src` to confirm that no other `Ens.Rule.FunctionSet` declares the four function names.
  - In the throwaway, measure Lane B's row-16 Intake line for the real Intake, and confirm that `CreateBusinessService("SimMailboxIn")` and then `SendRequestAsync("Intake", item)` reach Intake.
- `Core/Intake.cls`: build Intake as in Boundaries, with `RequestFor`, the `Send` seam, `OnError` and `OnResponse` by key, and the item names `DECIDE`, `OUTCOMEROUTER` and `EVALSINK` as parameters. Delete `STUB`. Write a contract class comment.
- `Core/Conversation.cls`: `Request` calls `Intake.RequestFor`, with no change of fields.
- `Core/Rule/Outcome.cls`, `Notify.cls`, and new `Notice.cls` and `Functions.cls`: the rules, the transform and the functions (Boundaries). Delete `STUB` from both rules and keep their class comments as contracts.
- `Channel/WebChat/Out.cls`: build `OnNotification` and `OnOutbound` (Boundaries), and delete `STUB`.
- `Data/Delivery.cls`: the five properties, the index, `Record` and `FindByApproval`. `Data/Ownership.cls`: the two kinds, `RecentNotices`, `DeliveryFor` and the class comment.
- `Web/Api.cls`: the rank-2 merge in `ChatItems`, and both doc comments (DW-62).
- `Live/Payload/Notification.cls`: the two properties and `FromRow`.
- `Msg/Catalog/Core.cls`: `notice.tellNowFallback`.
- `Test/Data/Fixture.cls`: add `Delivery(ownerRef, fields)`, recorded under its `ChannelMessageId`. `Clean` deletes the `Delivery` rows of every fixture `Session` it deletes.
- New `Test/Core/IntakeProbe.cls`: it extends Intake, overrides `Send` (Decide goes to a shadow DecideDouble; every other target is recorded with its message), and gets `Deliver`, as `ConversationProbe` does (Rule 2).
- New `Test/Core/Intake.cls` (slot-safe, DecideDouble scripts and fixture sessions). Its tests:
  - `TestDecideRequest`: every field, with the mail and text summaries and the 80-character cut;
  - `TestEachOutcomeSendsOneItemDecision`: every field, the CatalogKey and Slots copied, no turn;
  - `TestActRunsAnUntrustedFreshTurn`: the turn's fields, then the ItemDecision after its answer, and also after a turn error;
  - `TestEvalGoesToEvalSinkOnly`;
  - `TestInstanceGoesToOutcomeRouter`;
  - `TestDecideFailureIsAFallback`: an error, another class, an unknown outcome, a fallback with an unknown reason;
  - `TestRefusedItems`;
  - `TestNeverTouchesTheConversation`: no send to Conversation or Notify, no Turn row, no live event.
- New `Test/Core/Routing.cls` (slot-safe, per Task 0). Its tests:
  - `TestOutcomeRoutes`: each outcome × with and without a CatalogKey × owner session, `instance` and `eval`, with the targets and transform written out;
  - `TestNoticeTransform`: the three key cases, the first reason line, another owner's decision is an error, an empty reason, an unknown fallback reason becomes `unusable`;
  - `TestNotifyTargets`: every kind × demo on and off × paired or not × Telegram included or not, an Outbound on web and on Telegram, and `pairing` with and without `ChatRef`;
  - `TestFunctions`.

  It restores the `demo.mode` setting and `^OcuTalonTest("TelegramIncluded")` as it found them.
- New `Test/Core/WebChatOut.cls` (slot-safe, shadow instance and fixture sessions). Its tests:
  - `TestTellNowCard`: the row's fields, and one event whose payload is `FromRow` with text and whyNow split and the decision embedded;
  - `TestFallbackCard`: `fallbackReason` from the slot type;
  - `TestReminderCard`: `dueAt`;
  - `TestOtherKindsRecordOnly`: an `incident` gives a row, no text and no event;
  - `TestReplyRecordsItsDeliveryOnly`;
  - `TestRenderErrorRecordsNothing`;
  - `TestNotASession`: `instance` and an unknown Ref.
- New `Test/Data/Delivery.cls` (slot-safe). Its tests:
  - `TestRecordKeepsTheCard`;
  - `TestRecordRefuses`;
  - `TestFindByApproval`: exact match, newest, another owner, another channel, a case-changed ref, `instance`, empty.
- New `Test/Core/RoutingProduction.cls` (extends `InProduction`; throwaway only). Its tests:
  - `TestUntrustedItemReachesTheWebChat`: a mail Item from a `SimMailboxIn` host goes to the stub Decide, then to the fallback ItemDecision, the router, Notify and WebChatOut. It checks one Delivery card with `notice.tellNowFallback`'s text and one `notification` event; that the headers SimMailboxIn→Intake→Decide, Intake→OutcomeRouter→Notify→WebChatOut are in its SuperSession; and that there is no Turn row and no `chat.message`.
  - `TestEachOutcomeThroughTheRouter`: fixture ItemDecisions into the running OutcomeRouter (digest gives a header to DigestStore; tellnow and act give cards; ignore gives nothing).
  - `TestEvalItemWritesNoDeliveryOrEvent` (AD-22).
  - `TestReplyRecordsItsDeliveryOnly`: an Outbound into Notify.
- `Test/Core/ConversationProduction.cls`: each turn's Outbound now also reaches WebChatOut and leaves one reply Delivery row (asserted, and cleaned with the session).
- `Test/Data/Ownership.cls`: the two kinds join the isolation test, `Seed`, `ReadAll`, `Refs` (`ChannelMessageId`) and `TestRowsRefuses`. Add `TestRecentNotices`.
- `Test/Web/Api.cls`: `TestStateChatNotices`. It checks:
  - a card between two turns;
  - the same-second order turn, incident, card;
  - the 100 cap across all three;
  - that another session's card, a non-card kind and a reply row are absent.
- Edit the oracles:
  - `Test/Data/Tables.cls`: Delivery's properties and indexes; `TestDeliveryStubs` goes;
  - `Test/Live/Payloads.cls`: Notification's contract, plus `FromRow` in `TestFromRowBuilders`;
  - `Test/Msg/Catalog.cls`: 64 Core keys, 86 fixtures, and the new key's texts on each channel;
  - `Test/Core/ProductionItems.cls`: `:19` and `:28`.
- `docker/tests/test-production.sh`: Lane B's Intake line `:131` takes the value Task 0 measured, and the header's Intake clause `:12-13` is updated. No other row changes.
- `web/scripts/payloads.mjs` is unchanged. Regenerate `payloads.ts`.
- `web/src/app/chat/chat-view.ts`: `NoticeView`, `ChatEntryView`, `noticeOf` and `NOTICE_TEXTS`; `chatView` emits notices; update the header.
- New `web/src/app/chat/notice-card.ts` (`app-notice-card`, standalone, OnPush, styled from tokens, within the 4 kB budget).
- `chat-panel.ts`: `entries()`, the branch, the `notice` arrival part, and `instanceZone` passed in. `decision-strip.ts`: the `reasons` input (default true). `page-time.ts`: `pageTimeBeside`. `icon.ts`: `bell`, a Lucide path like the others.
- Node tests. Their oracles are written out:
  - `chat-view.test.mjs`: order, kinds, keys, the fallback, `newest` unaffected;
  - `page-time.test.mjs`: same zone; Berlin summer "14:00 CEST" and winter "13:00 CET" (en-GB); Kolkata en-US "GMT+5:30"; equal offsets with different ids (Europe/London in January and UTC) give no suffix; an invalid instance zone; empty input.
- `web/e2e/support/iris.ts`. All values go through `quoted()`, with a CHK of each status:
  - `'NOTICE'` joins `fixtureUser`;
  - `seedDecision(user, fields)`;
  - `sendItem(user, item)`, from a `SimMailboxIn` host into `Intake`, with the session's TraceRef as SuperSession;
  - `sendItemDecision(user, fields)`, into `OutcomeRouter`;
  - `sendNotification(user, fields)`, from a `NoticesIn` host into `Notify`.
- `docker/tests/test-sign-in.sh`: the fixture user `ZzNotice` (user role) with its password, role loop, redaction, `OCUTALON_NOTICE_USER`/`_PASSWORD` and the labels N1-N11.
- New `web/e2e/chat/notice.spec.ts` (chromium; the user NOTICE). Its default is `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`, and N6 overrides it. It has a header rule like `chat.spec`'s, each test asserts only its own refs, and `unrouteAll` runs after each test. The titles name the matrix rows:
  - **N1** "a tell-now notice shows as a card with its Why now line and the strip". A seeded decision (reasons "zz first\nzz second", 0.9, $0.0003) and `sendItemDecision` tellnow give:
    - the attention bar and `bell-ring` (`aria-hidden`);
    - the summary, then "Why now: zz first.";
    - no heading inside the card;
    - strip line 1 "Tell now" and "Confidence 0.90 · $0.0003", with Details and no reason lines;
    - no `focusin`, and no live region in the card.
  - **N2** "a code-written notice keeps its own two lines": `watch.productionStopped`.
  - **N3** "only Tell now and Act notify": ignore, digest and act are sent; only the act card shows (chip "Act"), before and after a reload.
  - **N4** "a fallback with no decision shows Tell now and the Fallback flag": "Why now: the model declined to answer", with no "Confidence", no "$" and no Details.
  - **N5** "a reminder card shows its due and arrival times": `sendNotification` reminder gives `bell`, the `info-ink` bar, "Reminder: stretch." and "Due 12:00 · arrived HH:MM".
  - **N6** "page times beside message text name the browser's zone when it differs" (Europe/Berlin, en-GB; UX-DR123): "Due 14:00 CEST · arrived HH:MM CES?T".
  - **N7** "a reload keeps the cards in the conversation in time order" (DW-62): turn 2024, card, turn 2099.
  - **N8** "/events serves WebChatOut's notification with the card's fields".
  - **N9** "markup in an arriving item shows as text": a Subject `<i>zz</i>` shows literally.
  - **N10** "an untrusted item reaches the web chat as a tell-now card within 5 seconds". `sendItem` uses the text "zz body [[mock:refusal]]". `started` is taken before the send; the test expects the card with the item's summary, a "Why now:" line and the Fallback flag within 5000 ms, and logs the elapsed time.
  - **N11** `notBuilt('a tell-now notification reaches the simulated phone within 5 seconds', '4.5')`.

**Acceptance Criteria:**
- **Intake (NFR-14, AD-10, AD-14, AD-30).** **Given** an untrusted Item, **when** `Intake` receives it, **then**:
  - it renders the Item with `Agent.Input` and calls `Decide` (`decide`);
  - on `act` it runs a `turn` (`untrusted`, `fresh`) that never touches the user's conversation, before it sends the `ItemDecision` with every listed field to `OutcomeRouter`.

  Tests: `TestDecideRequest`, `TestEachOutcomeSendsOneItemDecision`, `TestActRunsAnUntrustedFreshTurn`, `TestNeverTouchesTheConversation`, `TestUntrustedItemReachesTheWebChat`.
- **Evaluation (AD-22, AD-30).** **Given** an Item owned by `eval`, **when** `Intake` decides it, **then** the `ItemDecision` reaches only `EvalSink` (the probe's double in `TestEvalGoesToEvalSinkOnly`, the real stub in production), with nothing at `OutcomeRouter`, `Notify` or `WebChatOut` and no `Delivery` row or live event (`TestEvalItemWritesNoDeliveryOrEvent`).
- **Until Story 1.3 (AD-29).** **Given** the Epic 0 `Decide`, **when** Intake's tests run, **then** the slot-safe tests use `DecideDouble` through `IntakeProbe`, and the production tests take the stub's fallback path. The real decide path needs no edit when Story 1.3 merges.
- **OutcomeRouter (FR-1, AD-14, AD-30, AD-32).** **Given** fixture `ItemDecision`s of each outcome, with and without a `CatalogKey`, **when** the rule routes them, **then**:
  - Ignore notifies nobody;
  - Digest goes to `DigestStore`;
  - Tell now and Act give one `tellnow` `Notification` with the item's key and slots, or `notice.tellNow` with the summary and the decision's first reason line read through Ownership (or the fallback key with its reason).

  Tests: `TestOutcomeRoutes`, `TestNoticeTransform`, `TestEachOutcomeThroughTheRouter`, N1-N4.
- **Notify (FR-1, AD-14, UX-DR18).** **Given** a reply or a notification, **when** `Notify` routes it, **then** the targets match the table for each kind, with demo mode on and off, with and without a pairing, and with Telegram included or not. A reply's `WebChatOut` copy records only its `Delivery` row (`TestNotifyTargets`, `TestReplyRecordsItsDeliveryOnly`, ConversationProduction).
- **Delivery (AD-14, AD-33).** **Given** a recorded row, **when** `FindByApproval(approvalRef, channel, ownerRef)` runs, **then** it finds that owner's row by its approval `Ref` and channel exactly, and nobody else's. `WebChatOut` is the first writer (`TestFindByApproval`, `TestRecordKeepsTheCard`, `TestIsolationEveryRowKind`).
- **WebChatOut (FR-12, AD-32, UX-DR108, UX-DR123).** **Given** a notification, **when** `WebChatOut` delivers it, **then** its text is `Msg.Catalog.Render(key, slots, "web")`, with message times in the instance's zone (" ET" on the online demo, through `Render`). It records its `Delivery` row and publishes one `notification` event (`TestTellNowCard`, N8).
- **Texts (NFR-24, UX-DR112, UX-DR118, UX-DR119, UX-DR122).** **Given** the catalog, **when** a tell-now, code-written or reminder notice renders, **then** it is the catalog text exactly: "{what happened}", then "Why now: {reason}" on its own line; the `Watch` texts; "Reminder: {text}." and its late form (`Test.Msg.Catalog`, N1, N2, N5).
- **Notice cards (FR-1, UX-DR69).** **Given** a `notification` event or snapshot entry, **when** it renders in the chat, **then**:
  - a tell-now card has the attention bar, `bell-ring`, the text with no title, the "Why now:" line and a decision strip (line 1 with the decision's own cost);
  - a reminder card has the `info-ink` bar, `bell`, the text and "Due {time} · arrived {time}".

  Tests: N1-N5, `chat-view.test.mjs`.
- **Page times (FR-12, UX-DR123).** **Given** the browser in a zone different from the instance's, **when** a reminder card shows its times, **then** each one adds the browser zone's short name. In the same zone it adds none (N5, N6, `page-time.test.mjs`).
- **Five seconds (FR-1, NFR-9, P30).** **Given** the CI stack with the mock, **when** an untrusted item arrives on every run, **then** its tell-now card is in the web chat within 5 seconds (N10). The phone half is declared for Story 4.5 (N11).
- **Restart (DW-62).** **Given** a session with cards and turns, **when** the page reloads, **then** `/state`'s chat holds the cards in time order among the turns (`TestStateChatNotices`, N7).

## Spec Change Log

- 2026-10-23, lead (spec gate): the plan halted on an intent gap (the contended `Test.Install.Production.TestStubsAnswer`). The orchestrator ruled option (a): a one-time footprint extension for that test's rule-class loop only, with the guard and an inline comment, never the class header. The precondition became an implement task (Tasks & Acceptance), and the status was set to `ready-for-dev` without a re-plan. The four veto-window items were ruled as planned (veto); the spine notes went in as a Conventions row, "Notice cards", not as AD amendments; DW-81 was re-owned to `burndown`.

## Review Triage Log

### 2026-10-23 — Review pass
- verdicts: 35 findings — high 0, medium 5, low 22, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `ChatItems` builds every card payload (and its decision read) before the cap trims the list — the turn and incident reads build up to `CHATMAX` payloads before the merge in the same way; at most 100 reads, and a fix restructures the merge (more than a direct correction)
  - `[low]` `[reject]` Blind: `recentNotices` scans every web `Delivery` row of the session, because `OwnerRefChannelIndex` stops at `Channel` and replies are rows too — the index and the SQL are fixed by the intent, so a fix changes specified behaviour
  - `[low]` `[patch]` Blind: the card kinds are written in three places and no test ties them — `TestRecentNotices` now records a row of every kind in `WebChatOut.CARDKINDS` and expects each as a card; mutation: a kind the SQL lacks, red
  - `[low]` `[reject]` Blind: `Rule.Notice` sends nothing when the Decision row is not visible or its first reason line is empty — the intent states it (an error the router logs; Decided 5: loud, never a mislabelled fallback)
  - `[low]` `[reject]` Blind: `dueAt` is copied from the slot without a UTC check (a value over 20 characters fails the save, a short non-time shows "Due ") — the producer is code (Epic 8) and a bad value fails loudly at the save; a check adds a branch with no reachable trigger (grouped with the Edge rows on `dueAt`)
  - `[low]` `[patch]` Blind: the refusal warning does not say which Item was refused — it now ends with the Item's ItemId and channel when the message is an Item; `TestRefusedItems` asserts it; mutation: the warning without it, red
  - `[medium]` `[patch]` Blind: nothing tests a notice card that lands while the list is scrolled up (New messages and its focus) — new browser case N12 (scrolled up, the card shows New messages, the press goes to the bottom and focuses the card); mutation: the arrival part always `user`, N12 red alone (grouped with the verification-gap row)
  - `[medium]` `[patch]` Blind: `seedDecision` copies the field loop and preamble of `decisionLines` (Rule 2) — both now build the row from `decisionRowLines`
  - `[medium]` `[patch]` Blind: test helpers copied across classes (`Deliveries`, `WaitDeliveries`, `Notifications`, `WaitEvents`, `Count`, the event-log warning helpers) (Rule 2) — the new tests share `Test.Core.Observe`; the two production classes, Intake, WebChatOut and Delivery tests delegate to it. The earlier copies in `ConversationTurns` and `BridgeSink` (Stories 2.4 and 2.3) are not part of this change
  - `[low]` `[reject]` Blind: `Conversation` and `Intake` call each other for stateless helpers — the intent names both calls (`Conversation.Request` calls `Intake.RequestFor`; `Summary` reuses `Conversation.Summary`)
  - `[low]` `[reject]` Edge: an error from the send of the ItemDecision loses it, because `Sent` is set before the send — `SendRequestAsync` fails only for an item that is not configured; the error is returned to the framework and logged, and the intent names no other target
  - `[low]` `[reject]` Edge: an Item whose owner is no session, `instance` or `eval` is decided (a paid call) and then dropped by the router — the intent's refusals are an empty owner; the fix adds a read and a branch for a race
  - `[low]` `[reject]` Edge: a reminder `dueAt` over 20 characters fails the `Delivery` save and loses the reminder — same root as the Blind `dueAt` row
  - `[low]` `[reject]` Edge: the caption reads "Due " when `dueAt` is not a readable time — same root as the Blind `dueAt` row
  - `[low]` `[reject]` Edge: `FromRow` splits the last line as `whyNow` whatever it says — the intent states the split, and every tell-now key's text ends in its "Why now:" line
  - `[low]` `[patch]` Edge: a reminder with a decision would show a decision strip — `noticeOf` now gives a strip only to a tell now (`chat-view.test.mjs` asserts a reminder has none); mutation: the kind condition removed, red
  - `[low]` `[reject]` Edge: a fallback ItemDecision that carries a CatalogKey loses its fallback reason — the intent's first case is "that key and its slots, as they are"
  - `[low]` `[reject]` Edge: a tell now whose CatalogKey or Slots cannot be rendered is lost — the intent says a render error returns the error with no row and no event; the keys are code-written
  - `[low]` `[reject]` Edge (claim): the header's promise of a fallback after an exception holds not when the failure is in the send of the ItemDecision — same root as the send-failure row
  - `[medium]` `[patch]` Verification gap: no test pins the New messages path of a notice card — same root as the Blind row, closed by N12
  - `[medium]` `[patch]` Verification gap: the exception path of `Intake.OnRequest` (a decide request that cannot be sent, then `Decided` throws) and the `Sent` guard are not tested — `TestCallbackFailureSendsTheFallback` now covers both; mutations: no `Abandon` in the catch and no `Sent` guard, each red
  - `[low]` `[reject]` Verification gap (other): the guard in `TestStubsAnswer` makes the STUB assertion after it unable to fail — the edit is the orchestrator's ruling, limited to that guard in a Lane A file; `Test.Core.Routing` pins that the rule classes route
  - `[low]` `[patch]` Verification gap (other): the absence assertions (the router sends nothing on an ignore; no notification event for a reply) have no readiness signal — `Observe.WaitProcessed` waits for the inbound header to be Completed before `RoutingProduction` and `ConversationProduction` assert absence
  - `[low]` `[reject]` Verification gap (other): five Planned-mutation rows rest on a variant or on one combined throwaway — every acceptance criterion has a recorded mutation, and the combined run mapped four mutations to four distinct red cases
  - `[low]` `[reject]` Verification gap (other): `Test.Data.Delivery` tracks its `instance` and `eval` rows in memory only, so an interrupted run leaves them — the Refs are run-numbered and collide with nothing
  - `[low]` `[reject]` Verification gap (other): the Telegram-included half of the routing tests rests on the stub's global — the intent directs `^OcuTalonTest("TelegramIncluded")`
  - `[false]` `[reject]` Verification gap (other): source-text assertions are not coverage — the layer states no defect, and the executed pins are N9 and N5
  - `[false]` `[reject]` Intent: the slot tests sit at the class and table surfaces and the production surface is CI-only — the intent bars `Test.Core.RoutingProduction` and the browser specs from slot B, and runs them in the throwaway
  - `[false]` `[reject]` Intent: the pass label says N1-N11 while the spec file has N1-N10 and a placeholder — the intent names N11 as the declared placeholder; the label now reads N1-N12
  - `[false]` `[reject]` Intent: the comments on Decide differ between `RoutingProduction` (the stub's error) and N10 (the future mock) — both describe the same fallback, now and after Story 1.3
  - `[low]` `[reject]` Intent: additions the spec does not list (the `Output row` of `Record`, `ProbeSeam`, `Intake`'s stored properties, the strip's `reasons` input) — `ProbeSeam` and `reasons` are in the spec; the other two are recorded under Decided in-stage 16 and by the class contract
  - `[false]` `[reject]` Intent: a tell-now card with neither a decision nor a fallback has no strip, where the intent could be read as a bare chip — the strip component has no outcome to show without a decision or a fallback, recorded as Decided in-stage 17
  - `[false]` `[reject]` Intent: the non-fallback card cases send the ItemDecision straight to the router and no test sends an act or a DecisionRef through the real Intake and Decide — the intent's "Until Story 1.3" criterion makes the stub Decide the real path in this tree
  - `[false]` `[reject]` Intent: only the reminder caption uses the zone name — the intent scopes it to the caption
  - `[false]` `[reject]` Intent: the intent is silent on an act whose turn never answers — Decide always answers (its own timeouts end in an error status or a fallback), and the intent says the ItemDecision follows whatever the turn answers

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-4:** `Recipients`; the pairing route (kind `pairing` with a `ChatRef` goes to `TelegramOut` alone).
- **AD-6:** the request's fields; Busy is exempt for fresh untrusted turns.
- **AD-8:** a fallback is `tellnow` and notifies.
- **AD-10:** the untrusted turn is read-only, and anything more is an offer.
- **AD-12:** full views keyed by `Ref`, published after the commit.
- **AD-13 as amended:** two row kinds under its four conditions; text is rendered by interpolation.
- **AD-14:** channels, Notify's rule, `Delivery`.
- **AD-18:** times only through `Data.Time`, inside `Render`.
- **AD-20:** a card shows the decision's own cost.
- **AD-22:** an evaluation writes no Notification, Delivery or event; throwaways for production tests.
- **AD-26:** an untrusted item keeps its own trace session.
- **AD-29:** stubs, and Lane A is read-only.
- **AD-30:** the wiring.
- **AD-31:** bridge rows are read through Ownership.
- **AD-32:** producers never render, and only `*Out` operations render.
- **AD-33:** `notification` has one publisher, `WebChatOut`; `Delivery` is Lane B's.
- **Conventions:** Messages (rules route only on named properties), Enumerations, Identifiers, Times, Live events, Text OcuTalon sends, Tests, Angular.

No AC contradicts an AD's Rule. **Rule 5:** the 5 s check is measurable. Its clock starts before the item is sent, so it bounds the time from decision to card from above. Until Story 1.3 merges, its decision is Intake's fallback for the stub. From then on the `refusal` marker makes it the mock's (inference: nothing in this tree runs that path). No NFR is unmeasurable as worded.

**Decided in-stage** (small, reversible, within the intent):
1. **No split.** The parts form one route, and its integration checks (`TestUntrustedItemReachesTheWebChat`, N10) need all of them. The size is that of Story 2.6, which ran in one implement pass. DW-81 is declined instead (Ledger).
2. **The routing rules are tested by evaluation** (Task 0) and through the running production. A disabled `TelegramOut` is never a target unless Telegram is included (`TelegramPaired`, `TelegramOn`), so release 1 never sends to it.
3. **An `instance` owner's tell now or act creates no Notification.** `Session.Recipients` gives `instance` no session without an incident (AD-4), and `Ownership` reads no `instance` decision. No release-1 producer sends one: mailbox items are the session's (Story 4.6), and findings carry the watch's session (Story 30.4). The first story that sends `instance` items settles their recipients.
4. **The act turn's reply is not delivered.** The AC and AD-30 build the `ItemDecision` from the Item and `DecisionResponse` only. The reply stays in its `turn` Decision row and in the trace. Story 3.3 owns the CI test that the user's link stays unchanged.
5. **A fallback tell now uses `notice.tellNowFallback`.** A fallback Decision row has empty Reasons (Lane A's Decide), `notice.tellNow`'s `reason` slot must not be empty, and the UX makes a fallback's reason its first line (EXPERIENCE:255). The slot carries the enum, so `Render` writes the words. A non-fallback decision with no first reason line is a transform error, which is loud, never a mislabelled fallback.
6. **The card keeps what it showed.** The whole rendered text goes on its `Delivery` row, which is the web chat's copy (AD-14). So a reload shows the text as it was sent, its message times included. `text` and `whyNow` are split from the last line.
7. **A card's strip is line 1 and Details only** (mockup B5): the "Why now:" line is the decision's first reason, and "nothing repeats" (DESIGN:799).
8. **Card kinds** are `tellnow` and `reminder` (EXPERIENCE:267). Every other kind records its `Delivery` row only, until its story (Epic 6, Epic 16).
9. **A reminder's due time** is the slot `dueAt` (UTC). No reminder text declares it, so `Render` ignores it. `reminder.late`'s `time` stays the text's own slot.
10. **"Differs from the instance's" compares UTC offsets at the instant shown.** Equal offsets read the same clock time, so the zone name is needed only when the offsets differ. An unknown instance zone shows the name.
11. **The mail summary** is "{Sender}: {Subject}", cut at 80 characters by `Conversation.Summary`'s rule.
12. **`FindByApproval` gives the newest exact match.** The SQL narrows the rows by the collated index, and the code compares the values exactly, so a Ref that differs only by case never matches.
13. **A web reply's row has no `ChannelMessageId`.** The page shows the turn, so no web message exists for it. No `TurnRef` is added to `Outbound`.
14. **Demo mode sends to Story 4.5's `SimPhoneOut` stub.** It answers "not implemented" and logs it at the stub, with no effect on the router (no `ResponseFrom`), until Story 4.5.
15. **The 5 s check uses Lane A's existing `refusal` marker,** because `ci/mock/scenarios/B/` is contended. A model-written tell now through B markers is Story 4.6's.
16. **`Delivery.Record` takes a trailing `Output row`** (implement stage): the saved row, so that `WebChatOut` publishes `Notification.FromRow(row)` without a read back. The leading parameters are the ones the spec lists, and `Test.Contract.Ac` pins them.
17. **A tell-now card has a strip only with a decision or a fallback reason** (implement stage). A code-written notice with neither (N2) has no strip, because the strip shows a decision's outcome or the Fallback flag and has nothing else to show; a reminder card never has one.
18. **`DemoOn()` reads the setting through `Setting.Get`** (implement stage), so a change of demo mode can take up to the setting cache's 60 seconds to reach a long-running router job.

**Veto-window items for the lead** (unattended policy):
1. **Stored data.** `Delivery` gains `Kind`, `Text`, `DecisionRef`, `DueAt`, `FallbackReason` and `OwnerRefChannelIndex`, the store of DW-62. `Delivery` had no rows before this story, because `Record` was a stub, so the new index needs no build.
2. **Text not written out in the UX:**
   - `notice.tellNowFallback` ("{whatHappened}" then "Why now: {fallback reason}");
   - the mail summary "{Sender}: {Subject}";
   - the zone-named caption "Due 14:00 CEST · arrived 14:01 CEST".

   Each composes the UX's own strings.
3. **What a card leaves out.** A card's strip omits the reason lines (Decided 7), and an `instance` tell now notifies nobody in release 1 (Decided 3).
4. **A cross-story convention:** a reminder Notification carries `dueAt` in its slots (Epic 8's `ReminderTimer`).

There is no new dependency, privilege or secret. `ZzNotice` exists only on throwaways, with the user role.

**Spine notes for the lead (Rule 20, light path):**
- **AD-14:** the web copy's `Delivery` row keeps its card (kind, text, decision, due time, fallback reason); `FindByApproval` matches exactly and gives the newest; Notify's table (Boundaries), including AD-4's pairing route and the Telegram-included condition.
- **AD-32:** a fallback tell now uses `notice.tellNowFallback`; a reminder Notification carries `dueAt` in its slots; an `instance` tell now creates no Notification until a story gives it recipients.
- **Conventions, "Live events":** the snapshot's chat merges the web notice cards (tell now and reminder) by time, a turn, then an incident, then a card at the same second. The `notification` payload carries the shown `decision` and `fallbackReason`, and `text` without the "Why now:" line, which is `whyNow`.
- **AD-13** needs no amendment: its amendment provides for new row kinds.

**Lead's rulings at the spec gate (2026-10-23).**
- **Contended Lane A test (orchestrator ruling, U14, option (a), category decide):** a one-time footprint extension for `Test/Install/Production.cls`, `TestStubsAnswer`'s rule-class loop only, with the guard and an inline comment; the class header comment (lines 1-20) is never touched (Tasks & Acceptance). Reported under `footprint_extensions:`.
- **Veto U-35:** the four veto-window items above are kept as planned (keep (a)); the owner may reverse any one before the release.
- **Spine:** the notes above went in as one Conventions row, "Notice cards" (AD-14 is extended, not contradicted; AD-32 does not address a fallback decision), not as AD amendments.
- **DW-81** is re-owned to `burndown` (`by=spec_gate`), with the reason under Ledger.

**Integration ACs (Rule 1).**
- The page reads `WebChatOut`'s `notification` events and `/state`'s cards, and renders the card (N1-N8, on a real throwaway).
- The real `Notify` rule, through the running production, puts a card on the page (N5, `TestReplyRecordsItsDeliveryOnly`).
- The real `OutcomeRouter` and its transform, through the running production, put a card on the page (N1-N4, `TestEachOutcomeThroughTheRouter`).
- The real `Intake`, fed by a `SimMailboxIn` host, reaches the page through every hop (`TestUntrustedItemReachesTheWebChat`, N10).
- No consumer reads `FindByApproval` in this story. The first will be Story 4.5 (`SimPhoneOut`'s in-place edits), then 12.6 (`TelegramOut`).

**Consumed-by:**
- **1.12:** digest ItemDecisions at `DigestStore`.
- **2.9:** the card strip's trace link. Notify adds one rule-log row per message to the turn thread's index (AD-26).
- **2.12:** the cards in the announcer, the scan and the cross-browser runs.
- **3.3:** the untrusted act turn.
- **4.5:** `SimPhoneOut` as Notify's demo target, `FindByApproval`, and N11's phone half.
- **4.6:** `SimMailboxIn` into `Intake`, and the per-outcome markers.
- **6.x:** the incident and approval kinds' web form.
- **8.x:** a reminder Notification with `dueAt`.
- **9.x:** `EvalSink`.
- **10.3:** the pairing route.
- **12.6:** `TelegramOut` with `Record` and `FindByApproval`.
- **16.x:** the web form of `allowance`.
- **30.4:** findings with a `CatalogKey`.

**Consumes:**
- 0.4: the message contracts and `Delivery`;
- 0.6: the items, the rule stubs, `Agent.Input` and `HostSink`;
- 0.9: `Catalog.Render`;
- 2.2: `Ownership`, `ChatItems` and the live store;
- 2.4: `Conversation.Summary`, `DecideDouble`, the `ConversationProbe` pattern and `InProduction`;
- 2.5: the chat panel, `pageTime` and the fixture-user pattern;
- 2.6: `app-decision-strip`, `Ownership.Decision`, `Decision.FromRow` and the `sinkEvent` pattern.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `Intake.RequestFor` is the one request builder, and `Conversation.Request` calls it.
- `Summary` reuses `Conversation.Summary`.
- `IntakeProbe` follows `ConversationProbe`. If its recording and delivery repeat ConversationProbe's, move them into one helper that both call.
- `DeliveryFor` follows `Ownership.Decision`, and `recentNotices` follows `recentTurns`.
- `Notification.FromRow` follows `ChatMessage.FromRow`.
- The card reuses `app-decision-strip` (a `reasons` input) and `pageTime` (`pageTimeBeside` wraps it).
- The senders in `iris.ts` follow `sinkEvent`. `Fixture.Delivery` follows `Fixture.Usage`.
- `Test.Core.Observe` holds the Delivery, event, processed-header and event-log reads that the tests of Intake, WebChatOut, Delivery and the two production classes share, and `iris.ts` builds a Decision row's lines in one function for `seedTurns` and `seedDecision` (review patches, Rule 2).

**Ledger (Rule 17).**
- **DW-62** is addressed by the `Delivery` card fields, `RecentNotices`, the rank-2 merge, `TestStateChatNotices` and N7.
- **Declined DW-81:** it needs a production of its own with `DecideDouble` as `Decide`. Nothing in this story needs one: Intake reaches Decide through `IntakeProbe` and the shard's stub, and fresh untrusted turns are never Busy (AD-6). A namespace runs one production, so the test would stop and restart the lane-b shard's `OcuTalon.Production`. It belongs to a test-infrastructure story, such as Epic 2's burn-down.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message.
- **Throwaway commands** are `OCUTALON_RUN_TAG=e2s27i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`, one piece per call with `timeout: 600000`, ending with `teardown` on the same tag. A `LOCK busy` exit 75 is contention: wait and run it again.
- **Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (once) Task 0's slot-B measurement (the temporary rule-evaluation test), then remove it (`grep -rn MEASURE src/` finds none). Expected: the recorded `ret` format and the function-name grep.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: all pass, with no `zz` row, event or log row left.
  - New: `OcuTalon.Test.Core.Intake`, `Test.Core.Routing`, `Test.Core.WebChatOut`, `Test.Data.Delivery`.
  - Changed or regression: `Test.Data.Ownership`, `Test.Web.Api`, `Test.Live.Payloads`, `Test.Msg.Catalog`, `Test.Msg.Contracts`, `Test.Data.Tables`, `Test.Core.ConversationTurns`, `Test.Core.BridgeSink`, `Test.Contract.Ac`.
- (loop) One call each: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `node web/scripts/payloads.mjs --check`, `node web/scripts/tokens.mjs --check`. Expected: exit 0.
- (loop) `bash docker/tests/test-web-build.sh`. Expected: exit 0, within the style budget.
- (loop) One call each: `bash docker/tests/test-class-rules.sh` (`ALLOW_UNCHECKED` unchanged), `test-boundaries.sh`, `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-mock.sh`. Expected: exit 0.
- (loop) Throwaway, one piece per call: `build`; `class OcuTalon.Test.Core.RoutingProduction`; `class OcuTalon.Test.Core.ConversationProduction`; `live sign-in` (N1-N11, D1-D13, C1-C15); `live production` (Lane B's row-16 line); `live demo-path`; `teardown`.
  - Expected: each passes. The demo path still prints `floor 2 of 2 passed`, and N10's logged elapsed time is under 5000 ms. Teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway: `shard lane-b`, `shard lane-a` (`Test.Install.Production` green once the precondition is met), `teardown`. Expected: every class passes.

**Planned mutations (Rule 19).** For each one the implement stage applies the mutation, observes red, restores a byte-identical tree (`git status --short` and `git diff --stat` unchanged) and records `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Intake untrusted | a `user` Item accepted | `TestRefusedItems` |
| Act turn | the turn sent with `continue`, or not sent | `TestActRunsAnUntrustedFreshTurn` |
| Act order | the ItemDecision sent before the turn's answer | `TestActRunsAnUntrustedFreshTurn` |
| Fields | `CatalogKey` not copied | `TestEachOutcomeSendsOneItemDecision`; N2 |
| Eval | an `eval` ItemDecision sent to OutcomeRouter | `TestEvalGoesToEvalSinkOnly`; `TestEvalItemWritesNoDeliveryOrEvent` |
| Fallback | a Decide error sends no ItemDecision | `TestDecideFailureIsAFallback`; `TestUntrustedItemReachesTheWebChat`; N10 |
| Conversation untouched | Intake sends the Item to Conversation | `TestNeverTouchesTheConversation` |
| Digest | digest sent to Notify | `TestOutcomeRoutes`; N3 |
| Ignore | ignore sent to Notify | `TestOutcomeRoutes`; N3 |
| Instance | the `IsSession` condition removed | `TestOutcomeRoutes` |
| Reason | the second reason line, or the row read with `RefIndexOpen` (no owner) | `TestNoticeTransform`; N1 |
| Fallback key | a fallback renders `notice.tellNow` | `TestNoticeTransform`; N4 |
| Phone | `SimPhoneOut` whatever demo mode | `TestNotifyTargets` |
| Allowance | allowance to the phone | `TestNotifyTargets` |
| Pairing | `pairing` to WebChatOut | `TestNotifyTargets` |
| Reply | a reply publishes `notification` | `TestReplyRecordsItsDeliveryOnly` |
| Render | the raw key stored as the text | `TestTellNowCard`; N1 |
| Card row | no `Delivery` row | `TestTellNowCard`; `TestUntrustedItemReachesTheWebChat` |
| Other kinds | `incident` publishes a card | `TestOtherKindsRecordOnly` |
| Find | the owner ignored; a case-insensitive match | `TestFindByApproval` |
| Isolation | `recentNotices` without `OwnerRef = ?` | `TestIsolationEveryRowKind` |
| Merge | `ChatItems` skips the cards | `TestStateChatNotices`; N7 |
| Split | `whyNow` left empty | `TestTellNowCard`; N1 |
| Strip | the card's strip shows reason lines | N1 |
| Zone | the name always, or never, added | `page-time.test.mjs`; N5, N6 |
| Safety | `[innerHTML]` for the text | N9; `page-safety.test.mjs` |
| Flag | `fallbackReason` dropped from the card | N4 |
| Notices | `chatView` skips notices | `chat-view.test.mjs`; N1 |
| Five seconds | `Hang 6` in `OnNotification` | N10 |

**Task 0 (implement stage, recorded).**
- **Rules off a production.** A rule is evaluated on slot B with `Ens.Rule.RuleDefinition.EvaluateRulesEx(rule, 0, engine, "", .ret, .reason, 1, "e")`, where `engine` is `Ens.Host.GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine")` with `Document`, `MsgClass` and `Source` set. The session id must be a non-empty value (the tests pass 0): with `""` the call reads `pContext.%Process.%SessionId`, which a shadow engine lacks. A rule log row is written only on an error, so the "e" level leaves none. `Test.Core.Routing` is therefore slot-safe, and `Test.Core.RoutingProduction` is for the wiring only.
- **The `ret` format** is `send:<targets>:<transform>` for each action, actions joined by `;`, and "" for none. Examples: `send:DigestStore:`, `send:Notify:OcuTalon.Core.Rule.Notice`, `send:WebChatOut,SimPhoneOut,TelegramOut:`. `reason` reads `rule#1(ItemDecision):when#2`.
- **Function names.** `rg` over `irislib` and `src` finds `IsSession`, `DemoOn`, `TelegramOn` and `TelegramPaired` declared only in `OcuTalon.Core.Rule.Functions` (the one other `IsSession`, `Core.BridgeSink.IsSession`, is a private method of a class that is not a function set). `TestFunctions` pins it by listing every `Ens.Rule.FunctionSet` subclass.
- **Row 16, Lane B's Intake line.** Measured in the throwaway for the real Intake: `CHK|sync|Intake|1||0|0` (a message that is not an Item is refused with a warning and answered OK with nothing), in place of `CHK|sync|Intake|0|<Ens>ErrBPTerminated|1|0`. `live production` passes with it.
- **The host.** `Ens.Director.CreateBusinessService("SimMailboxIn")` and then `SendRequestAsync("Intake", item)` reach Intake: `RoutingProduction` finds the SimMailboxIn to Intake header, and the N cases send through the same hosts.

**Mutations demonstrated (Rule 19).** Each was applied, run red and reverted; `git status --short`, `git diff --stat` and the hash of every changed file matched the tree before the mutations. Slot B unless the line says otherwise.
- mutation: `Intake.Refusal` without the provenance check (a `user` Item accepted) -> `TestRefusedItems` red
- mutation: the act's turn request sent with SessionMode `continue` -> `TestActRunsAnUntrustedFreshTurn` red
- mutation: the ItemDecision sent right after the turn request, before the turn's answer -> `TestActRunsAnUntrustedFreshTurn` red
- mutation: `Finish` without `decision.CatalogKey = item.CatalogKey` -> `TestEachOutcomeSendsOneItemDecision` red (N2 not run with this one)
- mutation: `Finish` always sends to OutcomeRouter (eval included) -> `TestEvalGoesToEvalSinkOnly` red; throwaway `RoutingProduction`: `TestEvalItemWritesNoDeliveryOrEvent` red
- mutation: `Decided` quits after a Decide error, so no ItemDecision goes -> `TestDecideFailureIsAFallback` red; throwaway `RoutingProduction`: `TestUntrustedItemReachesTheWebChat` (and `TestEvalItemWritesNoDeliveryOrEvent`) red
- mutation: `Finish` also sends the Item to Conversation -> `TestNeverTouchesTheConversation` red
- mutation: Outcome rule sends digest to Notify -> `TestOutcomeRoutes` red (N3 not run)
- mutation: Outcome rule sends ignore to Notify -> `TestOutcomeRoutes` red (N3 not run)
- mutation: the `IsSession` condition removed from the tell-now rule -> `TestOutcomeRoutes` red
- mutation: `Notice` reads the Decision row with `Bridge.Data.Decision.RefIndexOpen` (no owner) -> `TestNoticeTransform` red (N1 not run)
- mutation: a fallback ItemDecision keyed `notice.tellNow` -> `TestNoticeTransform` red (N4 not run)
- mutation: Notify's last otherwise also sends to SimPhoneOut -> `TestNotifyTargets` red
- mutation: allowance also sent to SimPhoneOut -> `TestNotifyTargets` red
- mutation: pairing sent to WebChatOut -> `TestNotifyTargets` red
- mutation: `OnOutbound` publishes a notification -> `Test.Core.WebChatOut` `TestReplyRecordsItsDeliveryOnly` red
- mutation: the raw catalog key stored as the card's text -> `TestTellNowCard` red (N1 not run)
- mutation: no Delivery row for a card -> `TestTellNowCard` red; throwaway `RoutingProduction`: `TestUntrustedItemReachesTheWebChat` and `TestEachOutcomeThroughTheRouter` red
- mutation: `OnNotification` publishes the notification of an `incident` -> `TestOtherKindsRecordOnly` red
- mutation: `Ownership.DeliveryFor` without its exact comparison (a case-insensitive match) -> `Test.Data.Delivery` `TestFindByApproval` red
- mutation: `recentNotices` with `? <> ''` in place of `OwnerRef = ?` -> `Test.Data.Ownership` `TestIsolationEveryRowKind` red
- mutation: `ChatItems` skips the cards -> `TestStateChatNotices` red (N7 not run)
- mutation: `Notification.FromRow` leaves `whyNow` empty -> `Test.Core.WebChatOut` `TestTellNowCard` red (N1 not run)
- mutation: `pageTimeBeside` adds " UTC" in the same zone, and (separately) never adds the name -> `page-time.test.mjs` red both times (N5, N6 not run)
- mutation: `noticeOf` ignores the notification's `fallbackReason` -> `chat-view.test.mjs` red
- mutation: `chatView` skips notices -> `chat-view.test.mjs` red (N1 not run)
- mutation: the card binds its text with `[innerHTML]` -> `page-safety.test.mjs` red
- mutation: the card's strip with `[reasons]="true"`, WebChatOut's `Hang 6`, `noticeOf` ignoring `fallbackReason` and the `[innerHTML]` text, applied together in one throwaway `live sign-in` -> N1, N10, N4 and N9 red, and 121 others green
- mutation: Intake's `OnRequest` catch without `Do ..Abandon(request)` (the decide request cannot be sent, and `Decided` throws) -> `Test.Core.Intake` `TestCallbackFailureSendsTheFallback` red ("one ItemDecision is sent")
- mutation: `Finish` without `If ..Sent Quit $$$OK` (a second answer after the ItemDecision went) -> `TestCallbackFailureSendsTheFallback` red ("a second answer sends no second one")
- mutation: the refusal warning without the Item's ItemId and channel -> `TestRefusedItems` red
- mutation: `WebChatOut.CARDKINDS` holding a kind that the `recentNotices` SQL lacks (`incident`) -> `Test.Data.Ownership` `TestRecentNotices` red ("every kind that WebChatOut makes a card of is a card of the snapshot's chat")
- mutation: `noticeOf` gives a reminder a strip (the `kind === 'tellnow'` condition removed) -> `chat-view.test.mjs` red
- mutation: the arrival part of a notice always `user` (`chat-panel.ts` `noteArrivals`), in one throwaway `live sign-in` -> N12 red (the card is not focused), and 125 others green
- Not demonstrated on their own: the N5 and N6 zone mutation, N2, N3, N7, and N1 under the Reason, Render and Split mutations; their unit pins above went red.

**Implement-stage results** (the last pass, after the review patches).
- Slot B (build 154): `Test.Core.Intake` (9), `Routing` (4), `WebChatOut` (8), `Test.Data.Delivery` (3), `Ownership` (17), `Test.Web.Api` (28), `Test.Live.Payloads` (8), `Test.Msg.Catalog` (22), `Msg.Contracts` (6), `Test.Data.Tables` (5), `ConversationTurns` (38), `BridgeSink` (9) and `Test.Contract.Ac` (6) all pass, and no `zz` session, Delivery row, Turn, live event, Decision or log row of Intake or WebChatOut is left.
- Throwaway (tag `e2s27i`, torn down, nothing left): `class RoutingProduction` and `class ConversationProduction` pass; `live sign-in` passes (126 passed, N11 skipped) and prints N10's time on a passing run (1349 ms from before the send); `live production` and `live demo-path` pass (`floor 2 of 2 passed`); `shard lane-b` (37 classes) and `shard lane-a` (9 classes, `Test.Install.Production` green with both rule classes built) pass.
- Host: `npm --prefix web test` (257), `npm --prefix web run lint`, the three `--check` generators, `test-web-build.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-mock.sh` and `ci/checks.sh` pass.

**Shared surfaces:**
- `Data.Delivery`'s properties and indexes (`Test.Data.Tables`); `TestDeliveryStubs` goes;
- `Ownership`'s row kinds (`TestIsolationEveryRowKind`, `Seed`, `ReadAll`, `Refs`, `TestRowsRefuses`);
- the snapshot's chat (`Test.Web.Api`'s chat tests, which hold no Delivery rows; api.spec);
- the `notification` payload (`Test.Live.Payloads`, `payloads.ts`);
- the Core catalog keys (`Test.Msg.Catalog`, from 63 to 64 keys);
- Lane B's production oracle rows (`Test.Core.ProductionItems`, `Test.Install.Production`'s stub count);
- row 16 of `test-production.sh`;
- `ConversationProduction`, whose Outbounds now make Delivery rows;
- `chatView`'s output type and `isFreshChat` (`chat-view.test.mjs`);
- `IconName`;
- the strip's inputs (`ocutalon-reply.ts`, `decision.spec`);
- the users and labels in `test-sign-in.sh`, and `fixtureUser` in `iris.ts`.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` methods make their rows through `Fixture` and remove them with `Fixture.Clean(refs)`, the production-made Delivery rows of their sessions included;
- `Test.Core.Routing` restores the demo setting and the Telegram switch;
- `notice.spec` seeds and sends on its own user and asserts only its own refs. N7's 2024 and 2099 dates make the order hold whatever ran before.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Summary of the implemented change.** Intake decides an untrusted Item (`RequestFor`, the `Send` seam, the fallback, the fresh untrusted turn on an act) and sends the ItemDecision to OutcomeRouter or, for the owner `eval`, to EvalSink only. `OutcomeRouter` and `Notify` now route (rule sets, the `Notice` transform and the `Functions` set). `WebChatOut` renders a card through the catalog, keeps it on its `Delivery` row, and publishes `notification`; a reply records its row only. `Delivery.Record` and `FindByApproval` are built, with the two Ownership row kinds (`recentNotices`, `deliveryByApproval`), the snapshot's chat merging the kept cards (DW-62), `Notification.FromRow`, and the catalog key `notice.tellNowFallback`. The page has `app-notice-card` (tell now and reminder), `pageTimeBeside`, the `bell` icon, the strip's `reasons` input, and the chat list of turns and notices. The ruled Lane A edit is the one guard in `Test.Install.Production.TestStubsAnswer`'s rule-class loop.

**Files changed.**
- Server: `Core/Intake.cls` (built), `Core/Conversation.cls` (`Request` calls `Intake.RequestFor`), `Core/Rule/{Outcome,Notify}.cls` (built) and `Core/Rule/{Notice,Functions}.cls` (new), `Channel/WebChat/Out.cls` (built), `Data/Delivery.cls`, `Data/Ownership.cls`, `Web/Api.cls`, `Live/Payload/Notification.cls`, `Msg/Catalog/Core.cls`.
- Server tests: `Test/Core/{Intake,Routing,WebChatOut,RoutingProduction,IntakeProbe,ProbeSeam,Observe}.cls` and `Test/Data/Delivery.cls` (new); `Test/Core/{ConversationProbe,ConversationProduction,ProductionItems}.cls`, `Test/Data/{Fixture,Ownership,Tables}.cls`, `Test/Live/Payloads.cls`, `Test/Msg/Catalog.cls`, `Test/Web/Api.cls`; the ruled line pair in `Test/Install/Production.cls`.
- Page: `chat/notice-card.ts` (new), `chat/{chat-view,chat-panel,decision-strip,page-time}.ts`, `icon/icon.ts`, `live/payloads.ts` (regenerated); tests `e2e/chat/notice.spec.ts` (new, N1-N12), `e2e/chat/chat.spec.ts` and `e2e/support/{iris,page}.ts`, and the node tests `chat-view`, `page-time` and `page-safety`.
- CI scripts: `docker/tests/test-sign-in.sh` (the `ZzNotice` user, the labels N1-N12, N10's time on a passing run) and Lane B's Intake line and header clause in `docker/tests/test-production.sh` (`CHK|sync|Intake|1||0|0`, measured by Task 0).

**Review findings.** First pass, 35 findings from four layers: high 0, medium 5, low 22, false 8, maybe-false 0 (rows in `## Review Triage Log`).
- Patches applied (medium 4, low 4, by root cause): the New messages path of a notice card (N12); Intake's `OnRequest` exception path and `Sent` guard; `seedDecision` copying `decisionLines` (one `decisionRowLines`); the test helpers copied across classes (one `Test.Core.Observe`); the card kinds tied across WebChatOut and `recentNotices`; the refusal warning naming the Item; a reminder has no strip; the absence assertions wait for the router and WebChatOut to complete. N10's elapsed time is also printed on a passing run (the implement stage's own note).
- Deferred: none (`deferred: []`).
- Rejected with reasons: see the log; every `reject` row names the intent text or the refutation. The larger groups are the `dueAt` value checks (producers are code), the send-failure rows (no other target exists), and rows that restate the intent (transform errors, the `Conversation`/`Intake` calls, the specified index, the ruled guard).

**Follow-up review recommended: false.** Four medium and four low entries were patched, all in tests and test support except the refusal warning's text and `noticeOf`'s strip condition; each pin has a recorded mutation that went red, and the whole loop (slot B classes, node tests, the throwaway pieces, both shards, `ci/checks.sh`) passed after the last patch. No unverified risk can be named.

**Verification performed.** Every `(loop)` command of `## Verification` on two passes (before the review and after the last patch) and every `(once)` command once after the last patch: see `Implement-stage results`. Task 0 is recorded under `## Verification`. The Matrix rows are covered by tests that ran and passed (Intake, Routing, WebChatOut, Delivery, Ownership, Web.Api, RoutingProduction, ConversationProduction, N1-N10, `chat-view.test.mjs`, `page-time.test.mjs`); N11 is the declared placeholder for Story 4.5.

**Residual risks.**
- `DemoOn()` reads `demo.mode` through `Setting.Get` (AD-19's 60-second per-process cache), so a change of demo mode can take up to a minute to reach a running router job (Decided in-stage 18).
- With the Epic 0 stub for `Decide`, the production and browser cases take the fallback path; the real decide path (a `DecisionRef` through Intake) is tested through `DecideDouble` on the slot and needs no edit when Story 1.3 merges.
- The earlier copies of the event-log helpers in `ConversationTurns` and `BridgeSink` (Stories 2.3 and 2.4) remain; `Test.Core.Observe` is where a later story can fold them.
- `Test.Install.Production.TestStubsAnswer` no longer asserts anything for a built rule class; `Test.Core.Routing` pins that both route.

**Plan summary.** The spec is written in full and verified against the READY FOR DEVELOPMENT standard, apart from the contended-test precondition, which the orchestrator's ruling resolved (Spec Change Log, 2026-10-23).
- **Scope.** Intake, the two rules with their transform and function set, WebChatOut, Delivery, the notice-card store and its merge into `/state` (DW-62), the notice cards, zone-named page times, and the 5 s check.
- **For the lead.**
  - **No split** (Decided 1).
  - **DW-81 is declined** with its reason (Ledger), for re-routing (`burndown` or a test-infrastructure story).
  - **Four veto-window items** (Design Notes): `Delivery`'s new fields, the composed texts, the cards' omissions, and the `dueAt` slot convention.
  - **Spine notes** for AD-14, AD-32 and the "Live events" convention.
