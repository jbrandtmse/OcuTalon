---
title: 'Story 2.13: Open Visual Trace from the page'
type: 'feature'
created: '2026-10-23'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 2.9 serves a `traceUrl` on every `/state` and `/events` payload object that has a trace target, but the page shows none of them:
- no decision strip or rail row links to Visual Trace;
- the header has no Visual Trace menu;
- local users get no sign-in help.

Two targets are also wrong or missing:
- A rail decision of a chat turn opens page 1 of the day's thread with the day's first Item selected, because its target is the thread's own id (DW-129).
- An approval request's payload carries no target.

Story 2.1's popover service has never run in a browser (DW-58).

**Approach:** This is the page half of Story 2.9.
- **One trace link component** renders every link from the payload's own `traceUrl`, beside the row's button, opening a new tab.
- **One small service** keeps the sign-in help's state: seen in this tab's session, "Don't show this again" per browser, never on the online demo. It shows "Sign in to Visual Trace" through `Popovers`.
- **The header gains the Visual Trace menu.** Its popover holds "Open my conversation in Visual Trace", which links to the newest turn's trace.
- **On the server:**
  - a chat turn's decision carries its turn's target and item index;
  - an approval request carries its incident's target;
  - `payloads.mjs` types `traceUrl`.

## Boundaries & Constraints

**Always:**
- **The trace link: `app-trace-link` (new, `web/src/app/shared/trace-link.ts`; UX-DR42).**
  - It is an `<a>` with:
    - `href`: the payload's `traceUrl` exactly as served;
    - `target="_blank"` and `rel="noopener noreferrer"`;
    - the `external-link` icon (12px) and an always-underlined visible "Trace", styled with the `--trace-link-foreground` and `--trace-link-typography-*` tokens.
  - Its plain name is "Trace (opens in a new tab)": the visible text plus a visually hidden " (opens in a new tab)", as `ocutalon-reply.ts:91-92` does.
  - A row or strip renders the link only when its payload has a `traceUrl`.
  - It is the last item of its line, after the line's separator, and never inside a button:
    - the decision strip: line 1, after the confidence and cost (UX-DR61);
    - the decision row: line 3 (UX-DR57);
    - approval, check and reminder rows: the meta line.
- **Where each link opens (UX-DR139, AD-26).**
  - **A reply's strip:** the turn's own `traceUrl`, from its `chat.message`: the Item header, with PAGE.
  - **A notice card's strip:** its decision's.
  - **A rail decision row:** the decision's.
  - **A check row:** the check's latest run (`CheckView`).
  - **A reminder row:** the reminder's. None exists until Story 8.3 stores the waiter.
  - **An approval row:** the approval's, which is its incident's (below).
- **DW-129: a chat turn's decision opens at its turn.**
  - `Live.Payload.Decision` appends `TraceItemIndex` (`traceItemIndex`) and `TraceItemIndexNoEvents` (`traceItemIndexNoEvents`).
  - `FromRow` still sets `TraceHeaderId` to `TraceSessionId` first. It then calls `Ownership.TurnOfItem(row.ItemId, row.OwnerRef, .sc)`. When that returns a Turn with a `TraceHeaderId`, the payload's `traceHeaderId`, `traceItemIndex` and `traceItemIndexNoEvents` become the Turn's.
  - These cases keep the `TraceSessionId` target: no turn, a turn with no header, a failed read, or an owner that is not a session.
  - So the rail row, the `decision` event (`BridgeSink.Recorded`) and every nested decision open the day's thread on that turn's page.
  - **`Ownership.TurnOfItem(itemId, sessionRef, Output sc) As OcuTalon.Data.Turn` (new).**
    - It reads through a new fixed `Rows` kind, `turnOfItem`: `SELECT ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ItemId = ?`, binds `oa`.
    - The row is kept only when its `ItemId` equals `itemId` exactly.
    - It returns "" for an empty `itemId` or when nothing is found.
    - Every condition of `Rows` applies (AD-13). Its `sessionRef` is the decision row's `OwnerRef`, which is the owner of a record the product wrote and never request input.
- **The approval's target.**
  - `Live.Payload.Approval.FromRow(row, sessionRef = "")`: when `sessionRef` and `row.IncidentRef` are both set, and `Ownership.Incident(row.IncidentRef, sessionRef, .sc)` returns an incident with a `TraceHeaderId`, then `traceHeaderId` is that id and `traceNamespace` is `$Namespace`. Otherwise there is no target.
  - `Web.Api.RailBody` passes its session, and `BridgeSink.Approved` passes each recipient.
- **Typing.** `web/scripts/payloads.mjs` adds `traceUrl?: string;` as the last field of every interface that has both `traceHeaderId` and `traceNamespace`, and `payloads.ts` is regenerated.
- **Sign-in help: `TraceHelp` (new root service, `web/src/app/shared/trace-help.ts`; UX-DR38, UX-DR128, UX-DR140, FR-14).**
  - **`needed`** holds when all of these are true:
    - the snapshot has loaded with `onlineDemo` false;
    - the help has not been seen in this tab's session (`sessionStorage` key `ocutalon.traceHelp.seen`);
    - "Don't show this again" is not set (`localStorage` key `ocutalon.traceHelp.dontShow`).

    Every storage read and write sits in a try/catch, as in `theme.ts:12-19,42-46`. On failure, an in-memory flag holds for the page.
  - **While `needed`:**
    - every trace link is named "Open in Visual Trace (shows sign-in help first)" and has `aria-haspopup="dialog"`;
    - a press opens no tab: it shows the help popover with the link as its trigger, and records that the help was seen.
  - **Once seen:** every link has its plain name and no `aria-haspopup`, and opens directly.
  - **The help popover holds:**
    - the heading "Sign in to Visual Trace", which names the dialog;
    - "Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.";
    - "Open Visual Trace", a link styled as a primary button. Its target is the trigger's `traceUrl`, opened in a new tab; its name is "Open Visual Trace (opens in a new tab)"; it has focus when the popover opens; pressing it also closes the popover.
    - "Don't show this again", a ghost button. It records the flag and closes the popover.
- **The Visual Trace menu (`header.ts`; UX-DR29, UX-DR39).**
  - The trigger sits before the theme button. It is a ghost button showing "Visual Trace" and `external-link`, with `aria-haspopup="dialog"` and `aria-expanded`.
  - A press opens one popover through `Popovers.show`. A press while it is open closes it.
    - **While `needed`:** the heading "Sign in to Visual Trace", the help text, "Open my conversation in Visual Trace" and "Don't show this again". Opening it records that the help was seen.
    - **Otherwise:** the heading "Visual Trace" and "Open my conversation in Visual Trace".
  - **"Open my conversation in Visual Trace"** is a link that opens a new tab. Its name ends with " (opens in a new tab)", and its target is `conversationUrl`: the `traceUrl` of the newest `chat.message` in the live store that has one. That is the current day's thread at its newest turn, kept current by `chat.message` events. With no such turn, the link has `aria-disabled="true"`, stays focusable, has no `href` and does nothing.
- **Strings and pure helpers live in `web/src/app/shared/trace-view.ts` (new, framework-free).** It holds:
  - `TRACE_TEXTS` (ASCII only);
  - the two storage keys;
  - `needsSignInHelp(onlineDemo, seen, dontShow)`;
  - `conversationUrl(chat)`.

  A node string test pins them (UX-DR117).
- **Tests (AD-22, Rule 19).**
  - The `%UnitTest` classes are slot-safe. They make and remove their rows through `Test.Data.Fixture`.
  - The browser spec signs in as a new fixture user, `LINKS` (`ZzLinks`, with `OcuTalonUser,OcuTalonTraceViewer`). It owns its session and never assumes an empty chat.
  - The empty and online-demo states route `/state`, as `frame.spec`'s `changeSnapshot` does.

**Never:**
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**`, `Data/{StatusMark,Time,Reminder}.cls`, `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`.

  `Data/Incident.cls` (Lane A's, AD-15) is read only.
- **The page never assembles, edits or completes a trace URL.** It shows no link where no `traceUrl` exists.
- **Never add:**
  - a `/state` or `/events` key, an event type, a stored property or index, a role or grant;
  - an unchecked prepare outside `Ownership.Rows`;
  - an `Ens` read in a request, or a dependency;
  - public text beyond the AC and UX texts (Decided 6).
- **Out of scope:**
  - online-demo credential rows (Story 16.1);
  - the busy check before a trace window (16.5);
  - incident card links (6.1);
  - the reminder's waiter target (8.3);
  - REL-2's trace step (4.7).
- **Never run on slot B:**
  - `Test.Core.ThreadProduction`, `Test.Core.RoutingProduction`, `Test.Core.ConversationProduction` and `Test.Core.CommandsInProduction`;
  - `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` and `Test.Demo.Production`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reply strip | A done turn whose `chat.message` has `traceUrl` U | The strip's line 1 ends with "· Trace", `href` U, new tab | A turn with no `traceUrl`: no link |
| Notice strip | A notification whose decision has `traceUrl` D | The link's `href` is D | No `traceUrl`: no link |
| Rail decision of a chat turn (DW-129) | A `decide` row whose `ItemId` is the session's Turn (`TraceHeaderId` 9001, indexes 46 and 30), with `TraceSessionId` 42; page size 40 | The payload has `traceHeaderId` 9001, `traceItemIndex` 46 and `traceItemIndexNoEvents` 30; `traceUrl` `…SESSIONID=9001&PAGE=2`, the same as the turn's own | Turn with no header, another session's turn, owner instance or eval, failed read: `SESSIONID=42`, no PAGE |
| Rail decision of an item | A `decide` row with an `ItemId` of no turn, `TraceSessionId` 42 | `…SESSIONID=42` | — |
| Approval row | Pending approval; its incident is noticed and has `TraceHeaderId` 777 | `traceUrl` `…SESSIONID=777`, in `/state` and in the recipient's `approval` event | No `IncidentRef`, no `TraceHeaderId`, an incident the session can't see, or no `sessionRef`: no target |
| Check and reminder rows | A check with `LastRunHeaderId`; a reminder payload with a target | Link on the meta line | No target (every reminder row today): no link |
| Help, local | Fresh browser, `onlineDemo` false | Links are named "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup`. A press opens no tab and shows the dialog "Sign in to Visual Trace". After that, plain names, and links open directly | Storage throws: the help shows once per page load |
| Don't show this again | Pressed in tab A | A new tab of the same browser: links open directly, no help | — |
| Online demo | `onlineDemo` true | Links open directly from the start; the menu is headed "Visual Trace"; the help never shows | — |
| Menu | Turns T1 to Tn in the chat, Tn the newest | The conversation link's `href` is Tn's `traceUrl`; turn Tn+1 arriving by event moves it there with no reload | No turn: `aria-disabled`, no `href` |

</intent-contract>

## Code Map

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - class comment `:1-26`, which lists the reads and the `Rows` conditions;
  - `Incident` `:262-269` and `Decision` `:273-280` are the pattern for the new `TurnOfItem`;
  - `Rows` `:380-425`;
  - `Statement` `:428+`, where the new `turnOfItem` kind sits beside `turnByClient`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls`:
  - trace properties `:59-63`;
  - `FromRow` `:65-91`, which sets the trace at `:88-89`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls`: trace properties `:50-54`, and `FromRow` `:56-96`. The doc at `:56-58` says "the trace … stay empty", and the method starts at `:59`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `RailBody` `:349-368` (the method starts at `:351`, the approvals push is at `:356`) and `CheckView` `:372-390` (the check target, unchanged).
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`: `Approved` `:69-88` (the method starts at `:70`; `FromRow` at `:87`, with `recipient` in scope) and `Recorded` `:113-125`.
- Read only:
  - `Data/Turn.cls` (`ItemId` `:33`, `TraceHeaderId` `:51`, the indexes `:55-58`, `ItemIdIndex` unique `:85`);
  - `Data/Incident.cls` (`TraceHeaderId` `:66`, `RefIndex` `:71`);
  - `Bridge/Data/ApprovalRequest.cls` (`IncidentRef` `:18`);
  - `Live/Payload/ChatMessage.cls` (`SetDecision` `:93-108`, which calls `Decision.FromRow`);
  - `Live/Payload/Notification.cls:72`;
  - `Web/TraceLink.cls` (`Add` reads each object's own `traceItemIndex`, `:60-80`).

**Server tests (Lane B, edit)**
- `Test/Data/Fixture.cls`:
  - `Incident` `:80-96` has no `fields` argument; `Approval` `:100` and `Check` `:64` take one;
  - `Decision` `:118-134`, with `TraceSessionId` 42 at `:128`;
  - `Turn` `:31`, which sets no `TraceHeaderId`.
- `Test/Data/Ownership.cls`: `TestIsolationEveryRowKind` `:348`, `TestRowsRefuses` `:386`, `TestDecisionRead` `:475` and `TestTurnByClient` `:608`.
- `Test/Live/Payloads.cls`:
  - `TestFromRowBuilders` `:334`: reminder `:375-384`, approval `:402-415` (asserts no trace), decision `:437-442`;
  - `TestChatMessageCarriesItsDecision` `:246`;
  - the property oracles.
- `Test/Web/Api.cls`:
  - `TestStateSections` `:178` (rail `:226-246`; decision `SESSIONID=42` at `:246`);
  - `TestStateChatDecision` `:297` (nested decision `traceUrl` at `:335`);
  - `TestEventsBody` `:546`.
- `Test/Core/BridgeSink.cls`: `TestDecisionRecordedPublishesTheDecision` `:81` and `TestApprovalEventsPublishTheRequest` `:170` (`FromRow` at `:190`).
- `Test/Contract/Ac.cls:223` pins `Live.Payload.Decision`'s `ItemId,ItemSummary` (presence only; it is unchanged).

**Web (Lane B, edit or new)**
- `web/scripts/payloads.mjs` `renderInterface` `:120-121` (the header comment is `:1-21`), and `web/src/app/live/payloads.ts`, which the script generates:
  - `TraceTarget` `:81-84`;
  - `ChatMessagePayload` `:86-105`;
  - `DecisionPayload` `:140-161`;
  - `ApprovalPayload` `:163-181`;
  - `ReminderPayload` `:189-197`;
  - `CheckPayload` `:252-265`.
- `web/src/app/shared/popover.ts`: `Popovers.show({trigger, content, viewContainerRef, labelledBy})` `:64-108`. Focus moves to the first control at `:143-148`. Esc, an outside press and focus leaving close the popover at `:91-104,121-140`, and a press on the trigger is left to the trigger.
- `web/src/app/theme/theme.ts:7,12-19,42-46`: the storage try/catch pattern.
- `web/src/app/icon/icon.ts:15`: `external-link`; `size` defaults to 14.
- `web/src/app/live/live-state.ts:57,63`: the `snapshot` and `store` signals.
- `web/src/app/live/live-store.ts:65-86`: `LiveStore.chat` is `LiveItem[]`, in order, and new items are appended.
- `web/src/app/chat/chat-view.ts`:
  - `CHAT_TEXTS` `:25-57` (`opensInNewTab` `:44`);
  - `TurnView` `:89-114`;
  - `chatView` `:267+`, which copies `message.decision` at `:301-307`.
- `web/src/app/chat/decision-strip.ts`: line 1 `:55-72` (chip, flag, `.meta`), the Details button `:83-93`, inputs `:181-191`.
- `web/src/app/chat/ocutalon-reply.ts:77-85` (the strip) and `:91-92` (the new-tab link pattern); `web/src/app/chat/notice-card.ts:36-43`.
- `web/src/app/rail/rail-view.ts`:
  - `RAIL_TEXTS` `:21-46` and `RailRow` `:91-104`;
  - `approvalRow` `:176-188`, `checkRow` `:190-209`, `reminderRow` `:219-231`, `decisionRow` `:233-262`, `railView` `:280-307`.
- `web/src/app/rail/decision-row.ts` (meta line `:55-64`; the button is line 1, `:28-44`) and `web/src/app/rail/status-rail.ts:79-103` (approval, check and reminder rows; meta `:94-103`).
- `web/src/app/header/header.ts:39-60`: the right side, with the theme button, then account.
- `web/src/styles/base.css:113-123`: `.visually-hidden`. The trace-link and popover tokens are in `web/src/styles/tokens.css:508-515`. No style file changes.

**Web tests**
- `web/scripts/rail-view.test.mjs` (imports `:15-21`, strings `:89-123`), `chat-view.test.mjs` (strings `:378-417`) and `payloads.test.mjs` (real tree `:53-90`, fixture tree `:92-135`). They import the `.ts` modules directly.
- `web/e2e/trace/trace.spec.ts`:
  - `newestTurn` `:59` and `postTurn` `:69`;
  - `openTrace` `:130-139` (fixed to THREAD);
  - `drawnMessages` `:153` and `expectDrawn` `:178`.
- `web/e2e/support/iris.ts`:
  - `fixtureUser` `:15`;
  - `ReminderFields` `:69-79` and `publishReminder` `:81`;
  - `SeedDecision` `:133-152`, `DECISION_FIELDS` `:212-227` and `seedDecisions` `:403`, whose identity line gives a new `ItemId`;
  - `sinkEvent` `:358`;
  - `ApprovalFields` `:587` and `seedApproval` `:601`;
  - `CheckFields` `:635-645` (no `lastRunHeaderId`) and `seedCheck` `:648`.
- `web/e2e/support/api.ts`: `STATE`, `MESSAGES`, `post` and `sessionEvents`.
- `web/e2e/frame/frame.spec.ts`:
  - `changeSnapshot` `:19-26`;
  - F3 `:144-154` (header box order, and Tab from home to theme);
  - F7 `:393-398` (the Tab sequence);
  - F9 `:499` (the `/state` keys, unchanged).
- At risk if a seeded payload has a target:
  - `decision.spec.ts`: D1 `:121-123`, D5 `:261-263`, D8 `:394,:402`. `ACT` has `traceSessionId` 4512 at `:58`. Reply strips are unaffected because they use the turn's URL; its rail rows are affected.
  - `notice.spec.ts`;
  - `rail.spec.ts` R2 `:150`.
- `web/scripts/playwright-projects.test.mjs:69-80` picks up a new spec on its own.
- `docker/tests/test-sign-in.sh`:
  - header `:31`;
  - the user variable `:70`;
  - users and roles `:133-148`;
  - environment `:205-206`;
  - PASS and FAIL labels `:219,:225`.

## Tasks & Acceptance

**Execution:** No Task 0. Visual Trace's `SESSIONID` and `PAGE` were measured in Story 2.9 (T1-T4); popups and storage are browser behaviour.

1. `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: add `TurnOfItem` and the `turnOfItem` kind as Boundaries says, and name it in the class comment's list of reads (DW-129, AD-13).
2. `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls`: append the two index properties, documented. `FromRow` takes the turn's target as Boundaries says. Replace the `TraceHeaderId` doc and the `FromRow` doc so they state the rule (DW-129).
3. `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls`: `FromRow(row, sessionRef = "")` takes the incident's target, with its doc. This fills the approval row's target.
4. `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `RailBody` passes `sessionRef` to `Approval.FromRow`.
5. `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`: `Approved` passes `recipient` to `Approval.FromRow`, so the event matches `/state`.
6. `web/scripts/payloads.mjs`:
   - add the `traceUrl?: string;` rule, and a header-comment line saying `Web.TraceLink` adds it when the payload is served;
   - run `node web/scripts/payloads.mjs` to regenerate `web/src/app/live/payloads.ts`.

   This gives the client its type.
7. `web/src/app/shared/trace-view.ts` (new): `TRACE_TEXTS`, the storage keys, `needsSignInHelp` and `conversationUrl`. `conversationUrl` returns the `traceUrl` of the last `chat.message` item that has one, else `undefined`. These are the strings and pure rules.
   - `TRACE_TEXTS` is:
     - `trace: 'Trace'`;
     - `opensInNewTab: '(opens in a new tab)'`;
     - `signInName: 'Open in Visual Trace (shows sign-in help first)'`;
     - `signInHeading: 'Sign in to Visual Trace'`;
     - `signInText: 'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.'`;
     - `openVisualTrace: 'Open Visual Trace'`;
     - `dontShow: "Don't show this again"`;
     - `menu: 'Visual Trace'`;
     - `openConversation: 'Open my conversation in Visual Trace'`.
8. `web/src/app/shared/trace-help.ts` (new): `TraceHelp`, with `needed`, `markSeen()` and `dontShowAgain()` over the two storages with an in-memory fallback. It is the one source of the help state.
9. `web/src/app/shared/trace-link.ts` (new): two components. It renders the link and the first-press help.
   - `app-trace-link`, with input `url`.
   - `app-trace-help`, the help block that the link's popover and the menu's popover both use: the heading (a unique id per instance), the text, a projected action, and "Don't show this again".
10. `web/src/app/chat/chat-view.ts`: `TurnView.traceUrl` comes from the message. Set it only when the message has one, so turns without a target keep their shape.
11. `web/src/app/chat/decision-strip.ts`: add an input `traceUrl`, and render `app-trace-link` as the last item of line 1 after the separator. `ocutalon-reply.ts` passes `turn().traceUrl`; `notice-card.ts` passes `notice().decision?.traceUrl`. This puts the link on the strip.
12. `web/src/app/rail/rail-view.ts`: `RailRow.traceUrl`, set by the four row builders only when the payload has one. Then `decision-row.ts` and `status-rail.ts` render `app-trace-link` last on the meta line. This puts the link on the rows.
13. `web/src/app/header/header.ts`: the Visual Trace menu as Boundaries says, using `Popovers`, `TraceHelp` and `conversationUrl(live.store()?.chat)`.
14. `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `Incident` gains a trailing `fields` argument, as `Approval` has (Rule 2).
15. `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`:
    - add `TestTurnOfItem`: own turn found; another session's turn, an unknown `ItemId`, an `ItemId` differing only in case, and "" all give "";
    - make `TestIsolationEveryRowKind` and `TestRowsRefuses` cover `turnOfItem` (AD-13's condition).
16. `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`:
    - `TestDecisionOfATurnOpensAtTheTurn`: the matrix's DW-129 row with its four fallback cases, and an `eval` owner;
    - `TestApprovalOpensAtItsIncident`: the matrix's approval row with each "no target" case;
    - update the Decision property oracle and any assertion that `FromRow(row)` changes.
17. `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`: in `TestStateSections`, a rail decision of a chat turn carries `traceUrl` = `…SESSIONID=<turn header>&PAGE=<ceil(index/40)>`, the same as the turn's own, and an approval whose incident has a trace carries `…SESSIONID=<id>`. Update every assertion this changes, `TestStateChatDecision`'s nested decision included.
18. `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls`: `decision.recorded` for a turn's decision publishes the turn's target, and an `approval.*` event's payload carries the incident's target for each recipient. This tests the event path.
19. Node tests:
    - `web/scripts/trace-view.test.mjs` (new): the strings, deep-equal plus an ASCII check, and `needsSignInHelp`'s truth table. For `conversationUrl`: the newest turn wins over older ones and over incidents and notices; there is none for an empty chat or turns with no `traceUrl`.
    - `rail-view.test.mjs`: each row kind carries `traceUrl` only when its payload has one.
    - `chat-view.test.mjs`: `TurnView.traceUrl`.
    - `payloads.test.mjs`: `traceUrl?` appears on exactly the interfaces that have both trace fields (real tree: `TraceTarget`, `ChatMessagePayload`, `DecisionPayload`, `ApprovalPayload`, `ReminderPayload`, `CheckPayload`; never `NotificationPayload`), plus a fixture-tree case.
20. `web/e2e/support/` (Rule 2):
    - move `newestTurn`, `postTurn`, `openTrace` (now taking the user) and `drawnMessages` from `trace.spec.ts` to a new `support/trace.ts`, and import them in `trace.spec.ts`;
    - `fixtureUser` gains `'LINKS'`;
    - `SeedDecision` gains `itemId`, defaulting to a new Ref;
    - `CheckFields` gains `lastRunHeaderId`;
    - `ReminderFields` gains `traceHeaderId` and `traceNamespace`;
    - `support/iris.ts` gains `seedIncident(user, {traceHeaderId})`. It writes a noticed incident of the user's session through `Test.Data.Fixture.Incident` with `fields`, and returns its Ref for `seedApproval`'s `incidentRef`.
21. `web/e2e/trace/links.spec.ts` (new; chromium; user `LINKS`; a header comment like `trace.spec`'s). The tests run against real HTTP, with real Visual Trace pages for V1, V2 and V8. Each test gets a fresh browser context.
    - **V1:** a reply's strip links to its turn, and the link opens Visual Trace on it.
      - Set-up: post a message, and wait for its turn to be done. Mark the help as seen with an init script that sets `sessionStorage`.
      - The strip's link has `href` equal to the turn's `traceUrl`, `target="_blank"`, and is outside the Details button.
      - Its popup draws `g[id=<traceHeaderId>]`.
    - **V2:** a rail decision of a chat turn opens on its turn (DW-129).
      - Seed a `decide` row with the posted turn's `ItemId`, and publish it through `sinkEvent('decision.recorded')`.
      - The row's link, on line 3, has the turn's own `traceUrl`, and its popup draws the turn's header.
      - A `decide` row with a new `ItemId` and `traceSessionId` X has `…SESSIONID=X` and no PAGE.
    - **V3:** check, reminder and approval rows carry their links, and a row with no target has none.
      - Seed a check with `lastRunHeaderId`, a reminder event with a target, and an approval whose `seedIncident` has `TraceHeaderId`, plus a check with no target.
      - Each row's link is last on its meta line, with `href` equal to its `traceUrl`.
      - Pressing the check's link opens a page at that URL.
    - **V4:** the first press on a local install shows the sign-in help, and then links open directly.
      - Every link is named "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"`.
      - A press opens no page, and shows the dialog "Sign in to Visual Trace": no `aria-modal`, the exact text, and focus on "Open Visual Trace (opens in a new tab)", whose `href` is the link's.
      - Pressing "Open Visual Trace" opens the page and closes the dialog.
      - After that, links have plain names, no `aria-haspopup`, and open directly, also after a reload of the same tab.
    - **V5:** "Don't show this again" is remembered per browser, and storage failures are tolerated.
      - "Don't show this again" closes the dialog with focus back on the link. A second page of the same context then has direct links.
      - In a context whose init script makes `Storage` throw, the help shows on the first press and links open directly after it.
    - **V6:** on the online demo, links open directly and the help never shows.
      - `/state` is routed with `onlineDemo: true`.
      - Links have plain names from the start, a press opens a page, the menu is headed "Visual Trace", and "Sign in to Visual Trace" never appears.
    - **V7:** the Visual Trace menu and its popover behaviour (DW-58).
      - "Visual Trace" sits between the badge and the theme button, with `aria-haspopup="dialog"` and `aria-expanded` false, then true.
      - The popover has `role="dialog"`, `aria-labelledby` pointing at its heading, and no `aria-modal`. On the first open: "Sign in to Visual Trace", the text, "Open my conversation in Visual Trace (opens in a new tab)" and "Don't show this again", with focus on the first control.
      - Esc, an outside press on the chat panel, and Shift+Tab from the first control each close it, with focus back on the button. A press on the button while it is open closes it.
      - Later opens are headed "Visual Trace".
      - With `/state` routed to an empty chat, the conversation link is `aria-disabled`, has no `href`, and opens nothing.
    - **V8:** "Open my conversation" opens the current day's thread at its newest turn.
      - Post two turns. The conversation link's `href` is the newest turn's `traceUrl`.
      - A third turn posted with no reload moves the link within one poll.
      - Its popup draws the newest turn with the label `[traceItemIndex]`, which is greater than the first posted turn's index.
22. `docker/tests/test-sign-in.sh`: add the user `ZzLinks` (`OcuTalonUser,OcuTalonTraceViewer`) with its password, the role loop, redaction, `OCUTALON_LINKS_USER` and `OCUTALON_LINKS_PASSWORD`, and "Story 2.13's V1-V8" in the header and in the PASS and FAIL labels.
23. **The sweep (shared surfaces).**
    - Update `frame.spec` F3 and F7: the Visual Trace button now sits between the badge and the theme button, and Tab from home goes to it first.
    - Search `web/e2e/` for assertions that the new links change, and update each one. That means assertions on a strip's line 1, a row's meta line, a link or focusable count, or a Tab sequence, where the seeded payload has a trace target. Start with the at-risk list in the Code Map.

**Acceptance Criteria:**
- **Links on every row (UX-DR42, UX-DR57, UX-DR61).**
  - **Given** a reply, a notice card, or a decision, check, reminder or approval row whose payload has a `traceUrl`,
  - **when** the page renders it,
  - **then** it carries a trace link: the `external-link` icon and the underlined "Trace", last on its line, outside every button. The link has `href` set to that `traceUrl`, `target="_blank"`, and the name "Trace (opens in a new tab)" once the help is seen. A row whose payload has no `traceUrl` has no link.

  Tests: V1, V3, `rail-view.test.mjs`.
- **Where they open (NFR-20, UX-DR139, DW-129).**
  - **Given** those links,
  - **when** they are pressed,
  - **then** they open as follows:
    - a reply's link opens its turn: Visual Trace draws the turn's Item header on the opened page;
    - a rail decision of a chat turn opens the same URL as its turn and draws the turn's header;
    - any other decision opens its `TraceSessionId`;
    - a check opens its latest run;
    - an approval request opens its incident's trace;
    - a reminder opens the target its payload carries.

  Tests: V1, V2, V3, `TestDecisionOfATurnOpensAtTheTurn`, `TestApprovalOpensAtItsIncident`, `Test.Web.Api`, `Test.Core.BridgeSink`.
- **The Visual Trace menu (UX-DR29, UX-DR39, UX-DR139).**
  - **Given** the header,
  - **when** I open the Visual Trace menu,
  - **then** its popover holds "Open my conversation in Visual Trace". It opens the current day's thread at the newest turn in a new tab: Visual Trace draws that turn with a label equal to its `traceItemIndex`, which is above the earlier turns'. A turn that arrives later moves the link with no reload. With no turn, the link is disabled.

  Tests: V7, V8, `trace-view.test.mjs`.
- **Sign-in help on local and IPM installs (UX-DR38, UX-DR128, UX-DR140, FR-14).**
  - **Given** a local install and a tab that has not seen the help,
  - **when** I press a trace link or open the menu,
  - **then:**
    - links are named "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"`;
    - the first press opens no tab and shows "Sign in to Visual Trace" with the help text, "Don't show this again" and, for a link, "Open Visual Trace", which opens that link's target;
    - after that, links have plain names and open directly, the same tab's reload included;
    - "Don't show this again" holds in a new tab of the same browser;
    - a storage that throws still gives working help and links.

  Tests: V4, V5, V7.
- **The online demo (UX-DR140, FR-59).**
  - **Given** `onlineDemo`,
  - **when** I press a trace link or open the menu,
  - **then** links open directly from the first press, and "Sign in to Visual Trace" never shows.

  Tests: V6, `trace-view.test.mjs`.
- **DW-58: the popover service, in a browser.**
  - **Given** the Visual Trace menu's popover,
  - **when** it opens and closes,
  - **then:**
    - its container is `role="dialog"`, named by its visible heading, with no `aria-modal`;
    - focus goes to its first control;
    - Esc, a press outside, and Shift+Tab out of its first control each close it and return focus to the menu button;
    - a press on the menu button while it is open closes it.

  Tests: V7.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-26:** every trace URL comes from `TraceLink`, rows store the header that their links need, and "Open my conversation" opens the current day's thread.
- **AD-24:** the trace applications and the viewer's own page size, which is unchanged.
- **AD-12:** payloads carry targets, the web layer adds the URL, and the page applies events and never moves focus because of one.
- **AD-13:** `Ownership.Rows` is the one unchecked prepare, under four conditions, and the new `turnOfItem` kind meets them all. The request reads no `Ens` table. The page and the trace applications share one sign-in group.
- **AD-4:** every record is read through `Ownership`.
- **AD-33:** `BridgeSink` stays the one publisher of `decision` and `approval` events.
- **AD-15:** only `IncidentManager` writes `Incident`, so this story reads it and never writes it.
- **AD-20:** `Decision.TraceSessionId`.
- **AD-19:** the `onlineDemo` setting.
- **AD-29:** Lane A's tables and classes are read-only.
- **AD-22:** the tests.
- **Conventions:** Live events, Identifiers (header ids may leave the server for trace links), Angular, and Tests.

**AD-26 compliance (DW-129).** The URL's `SESSIONID` takes any header id, and Visual Trace opens that header's session with it selected (Story 2.9, T1 and T4). The turn's Item header lies in the session that holds the decision message, the day's thread. So a chat turn's decision still opens "the session holding its decision message". It now lands on the turn's page instead of page 1, through the header the Turn row already stores ("Rows that a link targets store the header id it needs (turn, …)"). No AD Rule is contradicted, and no AC contradicts an AD.

**Rule 5:** NFR-20 and NFR-9 are measured by V1, V2, V8 and the live updates. No NFR is unmeasurable.

**Decided in-stage** (small, reversible, within the intent):
1. **A reply's strip opens the turn** (its `chat.message` `traceUrl`), as UX-DR139 says for a turn. Notice strips and rail rows open their decision's link.
2. **DW-129 opens the decision at its turn, not on the decision message's own header.**
   - That header is the response of Lane A's `Decide`, which no Lane B row stores, and storing it would be a schema change (veto 3).
   - The turn's Item opens the right page, and the decision request and response follow it in the turn's group.
   - What remains: when the Item is the last item of its page, the decision response is on the next page. A turn's own link has the same limit.
3. **"Open my conversation" is the newest turn's `traceUrl`, with no `/state` key.**
   - The epic context's "add today's thread to `/state`" came from Story 2.9's proposal. It is not an AC, and a snapshot key would go stale when the day's first turn starts a thread after the page loaded.
   - The newest turn's link opens the current day's thread (the same session), stays current through `chat.message` events, and before the day's first turn falls back to the latest turn, as UX-DR139 does.
4. **`traceUrl` is typed by the generator** (one rule, where `TraceLink`'s rule lives), not by hand-written intersection types.
5. **Help state.**
   - "Seen" is kept in `sessionStorage` (the tab's session), and "Don't show this again" in `localStorage`. Both are tolerant of failures.
   - "Seen" is recorded when the help is shown.
   - The help is never shown before the snapshot has said `onlineDemo` is false.
6. **Text.**
   - Every visible string is quoted in the AC or the UX.
   - Two accessible names are compositions by UX-DR42's rule: "Trace (opens in a new tab)" and "Open Visual Trace (opens in a new tab)".
   - The menu's popover heading after the help is "Visual Trace", the menu button's own label in the mockup.
   - The disabled conversation link has no explanation, because one would be new public text.
7. **One menu popover.** Until the help is seen, it carries the help (heading, text, "Don't show this again") around the conversation link. That conversation link stands in for the optional "Open Visual Trace" button. After that, the menu is headed "Visual Trace". "Open Visual Trace" is a link styled as a button, because it navigates.
8. **The menu button sits before the theme button** (UX-DR29: "Visual Trace, theme and account"). It carries `aria-expanded`; trace links carry only the `aria-haspopup` that the AC names.
9. **The fixture user `ZzLinks`** (user and trace roles, throwaways only), as Story 2.9's `ZzThread`, so V1 to V8 own their session.
10. **No reminder producer.** Story 8.3 stores the waiter's header on the `Reminder` row (`epics.md:2940-2941`) and fills the payload. The row's link then appears with no page change. V3 publishes a reminder event that carries a target.
11. **The story is not split.** The server part is five small edits. The page part is three new files (`trace-view.ts`, `trace-help.ts`, `trace-link.ts`) plus edits to the strip, the rows and the header.

**Veto-window items for the lead:** none required.
- No stored data, role, grant or dependency changes.
- `ZzLinks` exists only on throwaways, as `ZzThread` does.
- Decided 6 lists the only text that is not quoted verbatim from the AC or UX.

**Spine notes for the lead (Rule 20, light path, the lead's call):** the Conventions "Live events" row could add:
- "A decision of a chat turn carries its turn's target and item index (`Ownership.TurnOfItem`), so its link opens the day's thread at the turn (DW-129). Every other decision carries its `TraceSessionId`."
- "An approval request carries its incident's `TraceHeaderId`."
- "The page's 'Open my conversation' is the newest turn's `traceUrl`."

**Integration ACs (Rule 1).**
- The reply strip, notice strip, rail rows and header menu read `app-trace-link` and `TraceHelp`, and open real Visual Trace pages (V1 to V8, over real HTTP).
- `Decision.FromRow` reads `Ownership.TurnOfItem`, and `/state`'s rail decision and the `decision` event carry the turn's `traceUrl` (`Test.Web.Api`, `Test.Core.BridgeSink`, V2).
- `BridgeSink.Approved` and `RailBody` read `Approval.FromRow(row, session)`, and the approval event and `/state` carry the incident's target (`Test.Core.BridgeSink`, `Test.Web.Api`, V3).

**Consumed-by:**
- **2.12:** the accessibility and responsive floor tests these links, the popover and the menu.
- **4.7:** REL-2's trace step and the finish state's whole-conversation link reuse `app-trace-link` and `conversationUrl`.
- **6.1:** the incident card's links use `app-trace-link` with `traceTargets.*.traceUrl`.
- **8.3:** the reminder's waiter target appears on its row.
- **16.1:** the menu's credential rows on the online demo.
- **16.5:** the busy check before a trace window opens.
- **IncidentManager (Lane A, AD-15):** setting `Incident.TraceHeaderId` turns on the approval links.

**Consumes:**
- 2.9: `traceUrl`, `TraceLink`, the Turn's indexes and `trace.spec`'s helpers;
- 2.1: `Popovers`, the header and `Icon`;
- 2.6: the decision strip;
- 2.7: the notice card;
- 2.8: the rail rows and `RailRow`;
- 2.2: `/state`, `LiveState` and the live store;
- 0.5: `payloads.mjs`.

The Integration ACs run against a real throwaway and the real Visual Trace.

**Extend, don't copy (Rule 2).**
- `Popovers` (2.1) gets its first consumers, and no second popover mechanism is added.
- The strip and the rail rows (2.6, 2.8) gain an input or field, not new row components.
- `app-trace-link` reuses the new-tab link pattern of `ocutalon-reply.ts:91-92`, and `TraceHelp` reuses the storage pattern of `theme.ts`.
- `TurnOfItem` is one more `Rows` kind beside `turnByClient`.
- `Fixture.Incident` gains `fields` as `Fixture.Approval` has.
- `trace.spec`'s helpers move to `support/trace.ts` and are not copied.
- The seed helpers gain fields, not twins.

**Ledger (Rule 17).**
- **DW-58** is addressed by Task 13, Task 21 (V7) and the AC "DW-58".
- **DW-129** is addressed by Tasks 1-2, 16-18, V2 and the AC "Where they open".

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`. There is one `iris_execute_tests` call per message, and the first call of a stage is `iris_server_info`.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s213i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses `e2s213q` and review uses `e2s213r`.

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, port 1991.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), in two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: all pass, and no `zz` row is left.
  - New or changed: `OcuTalon.Test.Data.Ownership`, `Test.Live.Payloads`, `Test.Web.Api`, `Test.Core.BridgeSink`.
  - Regression: `Test.Web.TraceLink`, `Test.Contract.Ac`, `Test.Core.ConversationTurns`.
- (loop) Each in its own call: `node web/scripts/payloads.mjs --check`, `npm --prefix web test`, `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh`. Expected: exit 0.
- (loop) Each in its own call: `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-storage.sh`. Expected: exit 0.
- (loop) Throwaway, one piece per call: `build`; `live sign-in` (V1 to V8 and every other chromium spec); `teardown`. Expected: each passes, and teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `build`; `shard lane-b`; `shard lane-b --reverse`; `live demo-path`; `teardown`. Expected: every class passes, and the demo path's floor count is unchanged.

**Planned mutations (Rule 19).** For each one: apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Links on every row | `decision-strip.ts` renders no link | V1 |
| Links on every row | `checkRow` drops `traceUrl` | `rail-view.test.mjs`; V3 |
| Where they open | The reply strip gets `decision.traceUrl` in place of the turn's | V1 (`href` is not the turn's) |
| Where they open | `Decision.FromRow` skips `TurnOfItem` | `TestDecisionOfATurnOpensAtTheTurn`; V2 |
| Where they open | `Approval.FromRow` ignores the incident | `TestApprovalOpensAtItsIncident`; V3 |
| Menu | `conversationUrl` takes the first turn | `trace-view.test.mjs`; V8 |
| Sign-in help | `needsSignInHelp` ignores `seen` | `trace-view.test.mjs`; V4 |
| Sign-in help | "Don't show this again" writes nothing | V5 |
| Online demo | `onlineDemo` ignored | `trace-view.test.mjs`; V6 |
| DW-58 | `Popovers.show` sets `aria-modal` | V7 |
| AD-13 isolation | `turnOfItem` without `SessionRef = ?` | `TestIsolationEveryRowKind` |
| Typing | `traceUrl?` emitted on every interface | `payloads.test.mjs` |

**Shared surfaces:**
- The `decision` payload, which gains two keys and a chat turn's target; `payloads.ts`; `Test.Live.Payloads`' oracle; `Test.Web.Api`'s rail and nested-decision assertions; `Test.Core.BridgeSink`.
- The `approval` payload's target.
- `Ownership`'s row kinds (`TestIsolationEveryRowKind`, `TestRowsRefuses`), and `Fixture.Incident`'s arguments.
- Every generated interface with trace fields, which gains `traceUrl?` (`payloads.test.mjs`).
- The header's controls and their Tab order (`frame.spec` F3, F7).
- Strips and rail rows with a target, which gain a link: line text, focusable count, Tab order (`decision.spec`, `notice.spec`, `rail.spec`, `chat.spec`, `rail-view.test.mjs`, `chat-view.test.mjs`).
- `fixtureUser`'s kinds, and `test-sign-in.sh`'s users and labels.
- The e2e seed helpers, and `trace.spec`'s helpers, which move to `support/trace.ts`.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` classes make and remove their own rows;
- `links.spec.ts` owns `ZzLinks`, removes its fixture rows, never assumes an empty chat, and gives each test a fresh browser context.

**Manual checks:** none.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-23):** The plan halted after planning, as the dispatch asked. It used the committed `epic-2-context.md` without recompiling it, and took Story 2.9 as the continuity context. It ran no runtime measurement: no Task 0 was needed, and no throwaway was started.
