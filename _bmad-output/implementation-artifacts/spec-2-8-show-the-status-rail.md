---
title: 'Story 2.8: Show the status rail'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: '59fed455092234868637bac90fbd70c7a3c22299'
baseline_commit: '59fed455092234868637bac90fbd70c7a3c22299'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The failing branches of Ownership.Watchers and Ownership.ApprovalIncident, and Session.Recipients passing Watchers' status
      on, are run by no test, so dropping the pass-through (the original DW-68 bug) leaves every test green.
    evidence: |-
      TestFailedWatcherReadIsLoud fails the read through the BridgeSink.Recipients seam (BridgeSinkProbe), above the code that can
      fail; TestRecipients, TestApprovalIncident and TestInstanceScope assert only that sc is OK. Measured on slot B: Set $ROLES=""
      leaves %All in place for _SYSTEM; $SYSTEM.Security.Login("UnknownUser") ends the process with <PROTECT>; a bound NaN, INF,
      $LIST, control-character or OREF value gives no SQL error. So only a privilege-limited login (Story 6.2's REST answer
      path, where these reads really fail) or a private statement seam in Ownership and Session can make them fail.
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Session.cls:93; src/ocutalon/cls/OcuTalon/Data/Ownership.cls:298-326 and :337-364
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The main page's status rail is still four bare headings (Story 2.1's frame). The snapshot already carries the session's pending approval requests, background checks, pending reminders and newest decisions (Story 2.2's `RailBody`), and the live store already keeps them current, but nothing renders them and there is no Telegram section. `BridgeSink` drops every `approval.*` event, so no `approval` event ever reaches a page. And `Session.Recipients` answers "nobody watches" when its watcher read fails (DW-68).

**Approach:**
- **Server.** `BridgeSink` publishes an `approval` event for each `approval.*` bridge event:
  - to the owning session;
  - for an `instance` incident's request, to each session that `Session.Recipients` returns.

  It reads the row through Ownership for each recipient. The two cross-owner reads report their status, and a failed read is logged loudly and publishes nothing (DW-68).
- **Page.** A new `app-status-rail` renders the rail from the live store. It holds:
  - five sections, with live counts, rows, empty texts and hints;
  - approval rows with the attention bar and the raised and expiry times;
  - check rows;
  - reminder rows with a ticking countdown;
  - decision rows as disclosures;
  - the Telegram card, its own component, only when the release includes Telegram.

  A focused row that leaves passes focus to its section heading.
- **Tests.**
  - Node tests of the rail's view and of the page times;
  - `%UnitTest` cases for BridgeSink, Recipients and Ownership;
  - a browser spec, R1-R12;
  - the REL-2 spec for UJ-1's page step checks the rail's sections.

## Boundaries & Constraints

**Always:**
- **BridgeSink's approval events (AD-4, AD-12, AD-29, AD-31, AD-33).** `OnEvent` handles the five types `approval.raised`, `approval.answered`, `approval.expired`, `approval.cancelled` and `approval.result` before its session guard, because owner `instance` must reach them. `decision.recorded` and `turn.step` behave as they do today.
  1. The payload's `ref` comes from `Member`. An empty ref publishes nothing.
  2. **Owner `instance`:** `incidentRef = Ownership.ApprovalIncident(ref, .sc)`. An error status gives the loud warning (step 4's text), and an empty answer (not an instance request) publishes nothing.
  3. **Owner a session** (`IsSession`): `incidentRef` is "". **Any other owner** (`eval`, "", an unknown stream name) publishes nothing.
  4. **Recipients:** `recipients = ..Recipients(ownerRef, incidentRef, .sc)`. This is a new private seam that calls `Session.Recipients(ownerRef, incidentRef, .sc)`. An error status logs one `$$$LOGWARNING` with the new `Parameter ERRORRECIPIENTS = "BridgeSink could not read who receives an approval event: "`, followed by the type, the approval Ref, the incident Ref and the status text. Nothing is published.
  5. **Each recipient:** `Ownership.Approval(ref, recipient, .sc)`.
     - A visible row publishes `approval` with `Live.Payload.Approval.FromRow(row)` on that recipient's stream, through the existing `Publish` (LOCKWAIT).
     - A row the recipient can't see publishes nothing for that recipient: another session's request, an unnoticed incident's, or any instance request on the online demo.
     - A read error logs `ERRORFAILED` for that recipient.

  `OnEvent` still returns OK for every input and waits at most LOCKWAIT on each stream's lock. The class comment states the contract and no longer says "approval.* do nothing yet".
- **Recipients and the cross-owner reads (AD-4, AD-13 as amended, DW-68).**
  - `Session.Recipients(ownerRef, incidentRef = "", Output sc As %Status) As %List` gains a trailing `sc`. `Test.Contract.Ac` pins only the prefix `ownerRef,incidentRef` and the return type.
    - `sc` is OK unless the watcher read failed.
    - When it failed, the result is "" and means nothing. It never means that nobody watches.
  - `Ownership.Watchers(namespace, production, Output sc As %Status)` gains a trailing `sc`. A prepare or execute failure gives "" and the error. The online demo gives "" with OK, as before.
  - The new `Ownership.ApprovalIncident(ref, Output sc As %Status) As %String` gives the `IncidentRef` of the approval request whose Ref is exactly `ref` (case-sensitive) when its owner is `instance`, and "" otherwise.
    - It uses one fixed statement, `SELECT Ref, IncidentRef FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ? AND OwnerRef = 'instance'`.
    - It is prepared with the privilege check (a one-argument `%Prepare`), as Watchers is.
    - An error gives "" and the error.
  - Both cross-owner reads run only in production jobs and tests. Ownership's class comment (`:24-25`) says so for both.
  - No new unchecked prepare is added, and `ALLOW_UNCHECKED` doesn't change.
  - The other `Recipients` callers (`Channel/WebChat/Out.cls:69`, `Core/Rule/Functions.cls:11`) don't change.
- **The rail frame (UX-DR51, AD-29).** `main-page.ts` keeps `<section class="rail">`, which is the region "Status" through its visually hidden h2.
  - It keeps its loading skeletons: four groups, and no Telegram section while loading.
  - It keeps its headings-only failed state.
  - Once loaded, it renders `<app-status-rail />` inside the section.
  - The width is `--status-rail-width` (288px), and `--space-rail-width-wide` (320px) from a 1440px viewport, through a media query in the component (no token encodes the breakpoint).
  - It scrolls on its own and never collapses by itself.
- **Sections and counts.** The order is Telegram (only when `store.telegram.included`), Approval requests, Background checks, Reminders, Recent decisions.
  - Each heading is an `h3` with `tabindex="-1"`, so that focus can land on it.
  - A list section's heading holds two spans: the visible "{label} ({n})" (`aria-hidden`) and the visually hidden "{label}, {n}". So its accessible name reads "Background checks, 1".
  - An empty list shows "(0)". The Telegram heading has no count.
  - Counts, rows and empty texts follow the store, with no reload.
- **The views** (`rail/rail-view.ts`, framework-free, imports only types) show the store as a reload would (Decided 16):
  - approvals: state `pending`, ordered by `raisedAt`, then by store order;
  - checks: every check, in store order;
  - reminders: state `pending`, ordered by `dueAt`, then by store order;
  - decisions: kind `decide`, newest `recordedAt` first, then by store order, at most 20.
- **Rows.** Each row has:
  - a title (`--status-rail-section-row-title-*`);
  - a detail line, only when it has one;
  - a caption meta line (`--type-caption-*`).

  Every value is interpolated. The row kinds:
  - **Approval.**
    - A 3px `--attention` bar on the left.
    - Title for kind `fix`: "Repair and resend {affected} {noun}", where `{noun}` is the dry run's `itemNoun.one` when `affected` is 1 and `itemNoun.other` otherwise. With no dry run the title is "Repair and resend". For kind `tool_call` it is "Run {toolName}".
    - Meta: "Raised {when} · expires {when}".
    - No button and no link (Decided 5).
  - **Check.**
    - Title: "{displayName} production" for kind `production`, and the display name alone for any other kind.
    - Detail: "Live, plus a check every minute" for kind `production`, and none for other kinds.
    - Meta: "Last run {when} · {finding}". With no finding, the result word (`DECISION_TEXTS.passed`, `.failed` or `.notChecked`) takes its place. With neither, the meta is "Last run {when}". Before the first run (`lastRunAt` empty) there is no meta.
    - Under the list, always: `To stop, ask: "Stop watching Orders."`
  - **Reminder.**
    - Title: "{text} · {countdown}". The countdown uses `font-variant-numeric: tabular-nums`. The visible "in 59 s" is `aria-hidden`, beside a visually hidden "in 59 seconds".
    - Meta: "Due {when}" (`NOTICE_TEXTS.due`).
    - A reminder with no `dueAt` shows its text alone, with no meta.
    - Under the list, always: `To cancel, ask: "Cancel my reminder to stretch."`
  - **Decision** (`app-decision-row`).
    - Line 1 is a `<button type="button">` with `aria-expanded` and `aria-controls`. It holds the outcome chip (`outcomeOf(outcome, fallback)`), the fallback flag on a fallback, the `itemSummary` and the chevron (`chevron-down` or `chevron-up`, `aria-hidden`).
    - Line 2 is the first reason line, from `reasonLines(reasons, fallbackSentence, 1)`, which puts the fallback sentence first. It is one line, cut with an ellipsis.
    - Expanded, every reason line replaces line 2, in place. Esc inside the row collapses it.
    - Meta: "{when} · Confidence {0.00} · {cost}". A fallback has no confidence, and a decision with no `costUSD` has no cost.
  - **Empty texts:** "None waiting.", "Ask OcuTalon to watch a production.", "None pending." and "No decisions yet."
- **Times (UX-DR123, UX-DR124).** They extend `chat/page-time.ts`.
  - `pageWhen(iso, nowMs, locale?, timeZone?)` gives the time in the browser's zone and hour format, the time itself from `pageTime`:
    - the same local date: "{time}";
    - the next local date: "tomorrow at {time}";
    - up to six days either way: "{Weekday} at {time}";
    - further: "{Mon} {D} at {time}", with ", {YYYY}" after the day when the year differs.

    Day and month names are English (`en-US`). An empty or unreadable time gives "".
  - `countdownText(dueIso, nowMs)` gives `{text, spoken}`. The remaining time is counted in whole seconds, rounded up and never below 0:
    - under a minute: "in {s} s" and "in {s} second(s)";
    - under an hour, in whole minutes rounded down: "in {m} min" and "in {m} minute(s)";
    - from one hour: "in {h} h {m} min" and "in {h} hour(s) {m} minute(s)";
    - past due: "in 0 s" and "in 0 seconds".
  - A clock signal ticks every second while a reminder with a countdown is shown, and every 60 seconds otherwise. It follows `chat-panel.ts:213-217`'s effect pattern.
- **The Telegram card** (`rail/telegram-card/telegram-card.ts`, `app-telegram-card`; Lane A's from Epic 12, AD-29). It shows only when `included`.
  - While `state` is `off` or `rejected` it shows "Telegram not set up", then the link "How to set it up", which:
    - points to `README_URL` with `#telegram` in place of `#readme`;
    - has `target="_blank"` and `rel="noopener noreferrer"`;
    - shows the `external-link` icon;
    - ends with the visually hidden " (opens in a new tab)" (`CHAT_TEXTS.opensInNewTab`).
  - State `on` shows nothing under the heading; Story 12.3 adds its states.
  - No banner appears.
- **Focus (UX-DR131).** When an update removes a row that holds focus, focus moves to that section's heading (`preventScroll`). The rule is one mechanism shared by every list section. Nothing else in the rail moves focus.
- **Strings (Rule 14).** Fixed strings are exported constants, with non-ASCII written as escapes:
  - `RAIL_TEXTS` in `rail-view.ts`;
  - the day words and countdown words (`WHEN_TEXTS`) in `page-time.ts`.

  Reuse the existing ones:
  - `CHAT_TEXTS.separator` and `CHAT_TEXTS.opensInNewTab`;
  - `NOTICE_TEXTS.due`;
  - `DECISION_TEXTS`, `formatCost`, `confidenceText`, `reasonLines` and `outcomeOf`;
  - the fallback sentence lookup (Rule 2).

  A Node-tested module imports only types: Node strips the types, and it can't resolve an extensionless value import. So `rail-view.ts` takes every value it reuses through its `format` argument (Tasks), and the component and the node test pass the real ones.
- **Safety and announcements (AD-13).**
  - Every value is interpolated. There is no `[innerHTML]` and no `bypassSecurityTrust*`.
  - The rail has no live region and makes no announcement. Announcements are Story 2.12's.
- **Tests (AD-22, Rule 19).**
  - The `%UnitTest` classes are slot-safe and use `Test.Data.Fixture` and `Fixture.Clean(refs)`.
  - The browser specs sign in as the new fixture user `RAIL` (`ZzRail`, with the user role) and assert only on their own refs.
  - Node-tested modules import only types.

**Never:**
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Checks,Eval,Watch}/**`, `Install/**` and `Schedule/**`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts`, `release/**` and `lane-a.yml`;
  - `test-pinned-sources.sh`, and every row of `test-production.sh`;
  - Lane A's `Live/Payload/Check.cls` (tests only construct it).
- **Never edit:** `Production.cls`, `docker/merge.cpf`, `ALLOW_UNCHECKED`, any `Live/Payload/*.cls`, `/state`, `/events` or `payloads.ts`.
- **Never build another story's part:**
  - 2.9: any trace link, those in the rail's meta lines included;
  - 2.10: banners, and the "(late)" mark on check rows;
  - 2.12: announcements, the drawer below 1280px, DW-89's tab stops, the Firefox and WebKit runs, the accessibility scan;
  - 4.4: the demo-mode empty text of Background checks;
  - 6.1-6.3: approval cards, the row's press, `AnswersIn`;
  - 8.x: `ReminderOps` and `ReminderTimer`;
  - Epic 5: `Checks` and its `check` events;
  - 10.3 and 12.x: the Telegram pairing states;
  - 30.3: the replay's real `approval.result` (DW-99);
  - 31.1: the WebSocket.
- **Never** add a live region, a dependency, a production item or an unchecked prepare.
- **Never run on slot B:** `Test.Core.RoutingProduction`, `ConversationProduction`, `CommandsInProduction`, `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` or `Test.Demo.Production`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Session request | Fixture pending `fix` request of S; `OnEvent` of each of the five types, owner S | One `approval` event per call on S's stream, carrying `FromRow`'s fields; on the page: "Repair and resend 50 orders" / "Raised HH:MM · expires tomorrow at HH:MM", "Approval requests, 1" | — |
| Not published | Owner `eval`; S named for T's request; an empty ref, an unknown ref or a non-object payload | Nothing is published, and `OnEvent` returns OK | — |
| Instance (DW-68) | Noticed `instance` incident on P; sessions A and B watch P, C does not | One event on A's stream and one on B's, none on C's; none with the online demo on, and none when the incident is unnoticed | — |
| Failed read (DW-68) | The recipients seam answers an error | One warning naming the type, the request and the incident; no event | Nobody watching: no warning, no event |
| Leaves | The request's state goes to approved, expired or cancelled, then its event | The row leaves when the page applies that event's Seq, and the count drops | — |
| Empty rail | A user with nothing | Order: Approval requests, Background checks, Reminders, Recent decisions, each "(0)" with its empty text, both hints, no Telegram section | — |
| Telegram | `included` true, state `off` (test seam) | First section "Telegram" with no count, "Telegram not set up", link "How to set it up (opens in a new tab)" to `…OcuTalon#telegram` in a new tab; no banner | Not included: no section |
| Check | DisplayName "Orders", ran 14:13, finding "50 new failures" | "Orders production" / "Live, plus a check every minute" / "Last run 14:13 · 50 new failures"; a `check` event with the same ref updates the row in place | Never run: no meta; no finding: the result word |
| Reminder | Due in 59 s | "{text} · in 59 s", spoken "in 59 seconds", "Due HH:MM", ticking; a later event with the same ref updates the row in place | No `dueAt`: the text alone |
| Fired / cancelled | `reminder` event with state fired (plus its notice), or cancelled | The row leaves at that Seq; a fired one's notice card is in the chat | — |
| Countdown | 23 s, 9 min 30 s, 1 h 42 min, 2 h, past due | "in 23 s", "in 9 min", "in 1 h 42 min", "in 2 h 0 min", "in 0 s", each with its spoken form | — |
| Times | The same date, the next date, 3 days back, 10 days on, another year | "14:13", "tomorrow at 14:13", "Monday at 14:13", "Oct 17 at 14:12", "Oct 17, 2025 at 14:12" | Empty: "" |
| Decisions | 21 `decide` decisions and 1 `turn` decision | The 20 newest `decide` decisions, newest first, "Recent decisions, 20"; chip, summary and chevron; the first reason line; "HH:MM · Confidence 0.90 · $0.0003"; expanding shows every reason line | Fallback: flag, its sentence first, no confidence |
| New decision | A `decision` event for a new `decide` decision | It goes first and the oldest leaves; if the oldest's button had focus, focus moves to the "Recent decisions" heading | A `turn` decision event: no change |
| Reload | After the live events above | The rail's text equals a reload's | — |
| Markup | Summary `<i>zz</i>`, reminder text `<b>zz</b>` | Shown as literal text, with no element made | — |
| Titles | `affected` 1; no dry run; `tool_call` "zz_tool" | "Repair and resend 1 order"; "Repair and resend"; "Run zz_tool" | — |

</intent-contract>

## Code Map

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - class comment `:3-15` (`:12` "approval.* and budget.capped do nothing yet");
  - `OnEvent` `:27-40`, whose session guard `:30` runs before any dispatch;
  - `IsSession` `:43-46`;
  - `Recorded` `:49-60`, the pattern for an Ownership read and then a publish;
  - `Publish` `:89-93`;
  - `Member` `:96-100`.

  The type names come from the base, `src/bridge/cls/OcuTalon/Bridge/Ext/HostSink.cls:15-23`, which is read-only. Payloads are `{ref}` (`RefPayload` `:38`).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:77-93`: `Recipients` opens the incident with `Incident.RefIndexOpen`, then `Ownership.Watchers`, and returns its "" as is.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - the class comment `:24-25` (Watchers);
  - `Approval(ref, sessionRef, .sc)` `:282-291`, whose `approval` statement `:451-453` requires a noticed incident and the local flag;
  - `DeliveryFor` `:243-257`, the exact-match pattern;
  - `Watchers` `:293-319`, a checked `%Prepare(sql)` that returns "" on any error at `:303` and `:305`;
  - `LocalFlag` `:323`;
  - `Rows` refuses `instance` and `eval` owners (`:336-344`).
- Callers of `Recipients` that stay unchanged: `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls:69` and `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls:11`.
- Read-only:
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls:59-96` (`FromRow`, which parses the dry run, `affected` and `itemNoun` included);
  - `Live/Payload/{Check,Reminder,Decision}.cls`;
  - `Web/Api.cls:347-362` (`RailBody`) and `:284-290` (`/state`'s `telegram` block, whose `state` is always "off" in this tree);
  - `Live/Publish.cls` (`Publish`, `LastSeq`, `TYPES`);
  - `src/bridge/.../Bridge/Data/ApprovalRequest.cls` (`DRYRUNKEYS` `:9`; Kind, IncidentRef, OwnerRef, State, RaisedAt, ExpiresAt, ToolName);
  - `Data/BackgroundCheck.cls` (Kind, DisplayName, NextDueAt, LastRunAt, Result, Finding; no interval field);
  - `Data/Reminder.cls` (Text, DueAt, State, Late);
  - `Data/Incident.cls` (OwnerRef, Namespace, Production, NoticedAt);
  - `Channel/Telegram/In.cls` (`Included()`, test seam `^OcuTalonTest("TelegramIncluded")`).

**Server tests (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls`:
  - tests `:62` (decision), `:98` (eval and instance decisions), `:114` (another session's), `:130-146` (`TestBadPayloadsPublishNothing`, whose approval loop uses a decision Ref and still publishes nothing; its doc lines `:7-8` and `:128-129` say "not built yet"), `:249-285` (`TestNeverFailsItsCaller`, including the probe's throwing handlers `:282-285`);
  - helpers `Session` `:291`, `Sink` `:299`, `Events` `:305`, `Holding` `:311`, `Warnings` `:370`, `Hold` `:388`;
  - lifecycle `:28-47`.
- `Test/Core/BridgeSinkProbe.cls:7,13`: it overrides `Recorded` and `Step` to throw. It gains a `Recipients` override.
- `Test/Data/Session.cls:70-102` (`TestRecipients`: a and b watch, onlineDemo on and off).
- `Test/Data/Ownership.cls`:
  - `TestInstanceScope` `:126-176` (the Watchers cases `:159-164,176`);
  - `TestFinds` `:218`;
  - `TestIsolationEveryRowKind` `:309` (no new row kind);
  - `TestRowsRefuses` `:347`.
- `Test/Data/Fixture.cls`:
  - `Reminder` `:47`, `Check` `:61` (DisplayName "Zz "_production), `Incident` `:76` and `Approval` `:96` (DryRun `affected` 4, ExpiresAt fixed in 2030);
  - `Decision(…, fields)` `:113` and `SetFields` `:148`, the pattern for the new trailing `fields`;
  - `Clean` `:262`.
- `Test/Core/Observe.cls`: `Events(session, type, count, seconds)` `:46` and `Warnings(mark, .text, method, start)` `:88`.
- `Test/Contract/Ac.cls:324` (`Recipients` `ownerRef,incidentRef` → `%List`, prefix-pinned `:153-159`).
- `docker/tests/test-class-rules.sh:33-35` (`ALLOW_UNCHECKED`; a one-argument `%Prepare` is checked).

**Page (Lane B, edit or new)**
- `web/src/app/main-page/main-page.ts`:
  - `RAIL_SECTIONS` `:8`;
  - the rail template `:30-46` (h2 `:31`, h3 loop `:32-45`);
  - `.rail` CSS `:79-98`.
- `web/src/app/live/live-store.ts`:
  - `COLLECTIONS` `:39-56`;
  - `LiveStore` `:65-86`, where `decisions` keeps every kind, newest first, and `approvals`, `checks` and `reminders` are maps by ref in insertion order;
  - `applyEvent` `:139-189`.

  `live-state.ts:57-69` holds `snapshot`, `store` and `sessionSeq`. `api-types.ts:21-50` holds `TelegramState` and `StateSnapshot.rail`.
- `web/src/app/live/payloads.ts` (generated, read-only):
  - `DecisionPayload` `:138-159`;
  - `ApprovalPayload` `:161-179` (`dryRun.affected`, `itemNoun.one` and `.other`);
  - `ReminderPayload` `:187-195`;
  - `CheckPayload` `:250-263`.
- `web/src/app/chat/page-time.ts`: `pageTime` `:25` and `offsetMinutes` `:34`. `web/scripts/page-time.test.mjs` imports it at `:10`.
- `web/src/app/chat/decision-view.ts`:
  - `DECISION_TEXTS` `:18-41` (`confidence`, `separator`, `passed`, `failed`, `notChecked`);
  - `formatCost` `:72`, `confidenceText` `:114`, `reasonLines` `:142`, `outcomeOf` `:170`.
- `web/src/app/chat/decision-strip.ts`:
  - the id counter `:12`;
  - line 1 `:40-59`;
  - the Details disclosure `:71-81` (`aria-expanded`, `aria-controls`, the chevrons);
  - the fallback sentence lookup `:199-206` (`PAGE_TEXTS` and `REASON_KEYS` from `msg/catalog.ts`);
  - Esc `collapse()`.
- `web/src/app/chat/outcome-chip.ts:8,70` (`Outcome`, `app-outcome-chip`) and `fallback-flag.ts:36`.
- `web/src/app/chat/chat-view.ts`: `CHAT_TEXTS.separator` `:43`, `opensInNewTab` `:44` and `NOTICE_TEXTS.due` `:60`.
- `web/src/app/chat/chat-panel.ts:213-217`: the clock effect with `setInterval` and `onCleanup`.
- `web/src/app/links.ts:5` (`README_URL`).
- The new-tab markup: `web/src/app/about/about-dialog.ts:28-31` and `chat/ocutalon-reply.ts:91-92`.
- `web/src/app/icon/icon.ts:4-24` (`chevron-down`, `chevron-up`, `external-link`; no new icon).
- `web/src/styles/tokens.css` (generated, read-only):
  - `--status-rail-*` `:262-280`;
  - `--space-rail-width` and `-wide` `:118-119`;
  - `--attention` `:21`;
  - `--type-caption-*` `:78-86`;
  - `--decision-row-*` `:291-299`;
  - `--telegram-card-*` `:281-285`.
- `web/angular.json:55-57`: the component style budget, a 4 kB warning and an 8 kB error.
- UX:
  - `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`:
    - `:69` (section order);
    - `:180-191` (times, countdowns, separators);
    - `:219,384` (new tabs);
    - `:235-247` (the rail);
    - `:334` (empty texts);
    - `:354` (Telegram);
    - `:374` (Esc);
    - `:419` (focus);
    - `:440` (timers not announced);
    - `:442` (colour).
  - `DESIGN.md`: `:179-180` (widths), `:673` (tabular figures), `:778-786` and `:792` (rows, Telegram card, decision row, fallback).
  - `mockups/main-page.html:368-420,600-630`.
  - `epics.md:360-366,433,436,440` (UX-DR51 to 57, 124, 127 and 131).

**Browser and CI tests (Lane B, edit or new)**
- `web/e2e/support/iris.ts`:
  - `fixtureUser` `:15`, `irisScript` `:39`, `chk` `:57`, `literal` `:63`;
  - `publishReminder(user)` `:69-84`, which uses fixed text, state pending and no due time, and which `live.spec` L2, L4 and L10 call;
  - `quoted` `:92`;
  - `sinkEvent` `:341-354`, which always passes the session as owner and returns nothing;
  - `seedDecision` `:379`, `sendNotification` `:500`.
- `web/e2e/session/session.spec.ts:61` (`cleanFixtureRows`, which moves to `iris.ts`) and `:70-75` (fixture seeding through `irisScript`).
- `web/e2e/frame/frame.spec.ts:11` (`RAIL_LABELS`) and `:77` (all h3 texts, on the README account).
- `web/e2e/live/live.spec.ts:246-260`: L5 expects four skeleton groups, which is unchanged.
- `web/e2e/chat/notice.spec.ts:143,149-150`: N3's page-wide `page.getByText(ignored|digested)`. Its seeded `decide` decisions now show in the rail after the reload.
- `web/e2e/demo-path/01-page.spec.ts`: the floor tests `:16`, `:46` and the `notBuilt` lines `:81-83`. It runs on a fresh install as the README account in demo mode, with an empty rail.
- `docker/tests/test-sign-in.sh`:
  - users `:43-62`;
  - the role loop `:123`;
  - redaction `:170`;
  - environment `:171-198`;
  - labels `:14-31,204,210`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: append the trailing `Output sc` to `Watchers`, which returns "" with the error on a failed prepare or execute. Add `ApprovalIncident(ref, Output sc)` (Boundaries) and update the class comment for both cross-owner reads. This is the server half of DW-68.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`: append the trailing `Output sc` to `Recipients` and pass Watchers' status through. The doc says what a failed read means and where the read runs (DW-68).
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`: the approval path from Boundaries, with:
  - `ERRORRECIPIENTS`;
  - the private seam `Recipients(ownerRef, incidentRef, Output sc) As %List`;
  - a private `Approved(type, ownerRef, payload)` that follows `Recorded`;
  - the approval types dispatched before the session guard;
  - the class comment as a contract.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: add a trailing `fields As %DynamicObject = ""` to `Approval`, `Check` and `Reminder`, set through `SetFields` after the defaults. The defaults don't change.
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkProbe.cls`: add the `Recipients` override, which sets `sc` to a 5001 error "zz the watchers could not be read" and returns "". The existing throwing overrides stay as they are.
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` (slot-safe, fixture rows):
  - `TestApprovalEventsPublishTheRequest`: each of the five types for a session-owned pending `fix` request gives one `approval` event whose payload is `FromRow(row)` (ref, kind, state, incidentRef, dryRun.affected, raisedAt, expiresAt). A second call after the row's state changes carries the new state.
  - `TestApprovalOwnersThatPublishNothing`: owner `eval`, owner S naming T's request, an unknown ref, an empty ref and a non-object payload each publish nothing and return OK.
  - `TestInstanceApprovalReachesEveryWatcher` (DW-68): sessions A and B have checks on a run-numbered production, C has none, plus a noticed `instance` incident and its `instance` request. One `approval.raised` gives exactly one event on A and one on B, none on C. With onlineDemo on there are none; with an unnoticed incident there are none. It saves and restores `onlineDemo` as `Test.Data.Session` does.
  - `TestFailedWatcherReadIsLoud` (DW-68):
    - Through `BridgeSinkProbe`, an `instance` request gives one warning that starts with `ERRORRECIPIENTS` and names the approval and incident Refs, with no event anywhere and `OnEvent` returning OK.
    - Through `BridgeSink`, a noticed `instance` incident that no session watches gives no event and no warning.
  - Update the class comment and `TestBadPayloadsPublishNothing`'s doc lines; its loop stays. In `TestNeverFailsItsCaller`, the probe also takes `approval.raised` and returns OK, with the one warning counted.
- `src/ocutalon/cls/OcuTalon/Test/Data/Session.cls`: `TestRecipients` asserts that `sc` is OK in every case, and that the instance case still gives a and b.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`: add `TestApprovalIncident`:
  - an `instance` request gives its IncidentRef;
  - a session's request, an `eval` request, an unknown Ref, the Ref in another case and "" each give "";
  - `sc` is OK throughout.

  `TestInstanceScope`'s Watchers calls also assert that `sc` is OK.
- `web/src/app/chat/page-time.ts`: add `WHEN_TEXTS`, `pageWhen` and `countdownText` (Boundaries), and extend the header comment. It still imports nothing.
- `web/src/app/chat/decision-strip.ts`: export the strip's fallback sentence lookup as `fallbackSentence(reason: string | undefined): string | undefined`, with unchanged behaviour. The strip calls it (Rule 2).
- New `web/src/app/rail/rail-view.ts`, framework-free, importing only types:
  - `RAIL_TEXTS` and the view types.
  - `railView(store, format)`: the sections in order. Each section carries its label, count, spoken heading, empty text and hint. Each row carries its key, title, optional detail, meta parts, and the countdown's text and spoken form. The view also carries `telegramShown`.
  - `format: RailFormat` brings in every value the view reuses:
    - `when(iso)` and `countdown(dueIso)`, bound to the clock's now;
    - `cost`, `confidence`, `reasonLines`, `outcome` and `fallbackSentence`;
    - `separator`, `due` and the result words.
  - `approvalTitle`, `checkTitle` and `readmeSection(readmeUrl, anchor)`, which puts `#<anchor>` in place of `#readme`; `TELEGRAM_ANCHOR = 'telegram'`.
- New `web/src/app/rail/decision-row.ts` (`app-decision-row`): the disclosure. It reuses `app-outcome-chip`, `app-fallback-flag`, `app-icon` and decision-strip's id and Esc pattern.
- New `web/src/app/rail/telegram-card/telegram-card.ts` (`app-telegram-card`, input `telegram: TelegramState`): its link is `readmeSection(README_URL, TELEGRAM_ANCHOR)`.
- New `web/src/app/rail/status-rail.ts` (`app-status-rail`, standalone, OnPush, styled from tokens, within 4 kB):
  - it builds the `RailFormat` from the real modules (`page-time`, `decision-view`, `chat-view`, `fallbackSentence`) and calls `railView` with `live.store()`;
  - it renders the sections, headings, lists, empty texts and hints, the decision rows and the Telegram card;
  - it runs the clock;
  - it applies the focus rule: before each render it remembers which row key holds focus, and if that key is gone after the render it focuses that section's heading.
- `web/src/app/main-page/main-page.ts`: render `<app-status-rail />` once loaded, and the 1440px width. The loading and failed states don't change. Update the class comment.
- New `web/scripts/rail-view.test.mjs`. It imports `rail-view.ts`, and builds the format from `page-time.ts`, `decision-view.ts`, `chat-view.ts` and `links.ts`, each imported as it is, with a stub `fallbackSentence`. Its oracles are written out:
  - the order with and without Telegram;
  - the counts and spoken headings;
  - the filters (approvals pending; reminders pending; decisions `decide` only; at most 20);
  - the sorts;
  - the replace-in-place behaviour;
  - the approval titles (50 and 1, no dry run, `tool_call`);
  - the check title, detail and meta variants;
  - the reminder title, meta and no-due cases;
  - the decision lines, meta and fallback;
  - the empty texts and hints;
  - `readmeSection(README_URL, TELEGRAM_ANCHOR)` gives `https://github.com/jbrandtmse/OcuTalon#telegram`.
- `web/scripts/page-time.test.mjs`: the `pageWhen` and `countdownText` rows of the Matrix, with en-GB, en-US (12-hour) and a zone other than UTC (Europe/Berlin across a date line).
- `web/e2e/support/iris.ts`:
  - add `'RAIL'` to `fixtureUser`;
  - move `cleanFixtureRows` here (session.spec imports it);
  - add `seedApproval(user, fields, owner?)`, `setApprovalState(ref, state)`, `seedCheck(user, fields)`, `seedReminder(user, fields)`, `publishCheck(user, fields)`, `seedIncident(owner, fields)` and `setTelegramIncluded(value)`, which returns the previous value;
  - `publishReminder(user, fields = {})` keeps its defaults for `live.spec` and returns the Seq;
  - `sinkEvent(user, type, payload, owner: 'session' | 'instance' = 'session')` returns the session stream's last Seq after the call (`Live.Publish.LastSeq`).

  Every value goes through `quoted()`, with a CHK of each status.
- `docker/tests/test-sign-in.sh`: add the user `ZzRail` (`OcuTalonUser`) with its password, the role loop, the redaction, `OCUTALON_RAIL_USER` and `OCUTALON_RAIL_PASSWORD`, and the labels R1-R12 in the header and in the PASS and FAIL lines.
- New `web/e2e/rail/rail.spec.ts` (chromium, the user RAIL, `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`).
  - It has a header comment like `notice.spec`'s, and `unrouteAll` after each test.
  - Each test seeds run-stamped rows, cleans them in `finally`, and asserts counts on a page loaded after its own seeding.
  - A "within one live update" check waits for `main.main[data-session-seq]` to reach the Seq that `sinkEvent`/`publish*` returned, then asserts within 1 s.
  - The cases:
    - **R1** "the rail is the region Status with its sections in order, live counts, empty texts and hints": the headings' accessible names "Approval requests, 0", …, the visible "(0)", no Telegram section, the width 288px at 1280×720 and 320px at 1440×900, and `overflow-y: auto`.
    - **R2** "an approval request shows its action, its times and the attention bar": a request raised now, expiring in 24 h, with `affected` 50 gives "Repair and resend 50 orders" and "Raised HH:MM · expires tomorrow at HH:MM", with `border-left` 3px in `--attention`. A second request with `affected` 1 gives "Repair and resend 1 order", and the heading reads "Approval requests, 2".
    - **R3** "a raised request appears, and an answered, expired or cancelled one leaves within one live update": a `sinkEvent` raised for a fresh row adds it; for each of the three states, `setApprovalState` and then `sinkEvent` remove it and the count drops.
    - **R4** "an instance incident's request reaches the session that watches its production": a check on a run-stamped production, a noticed `instance` incident and its request, then `sinkEvent` with the owner `instance`, show the row.
    - **R5** "a check shows its name, schedule and last run, and a later check event updates its row in place": "{name} production", "Live, plus a check every minute", "Last run HH:MM · 50 new failures" and the hint. `publishCheck` with the same ref and "No new failures" changes the text, with one row and the same count.
    - **R6** "a reminder counts down in tabular figures and a later event updates it in place": "zz … · in 1 min", then the published update with the same ref gives "in 59 s" (spoken "in 59 seconds") and "Due HH:MM". The text changes within 3 s, and `font-variant-numeric` is `tabular-nums`.
    - **R7** "a fired reminder leaves and its notice card shows in the chat; a cancelled one leaves": the fired event plus `sendNotification` of kind `reminder` remove the row at that Seq and put the card in `main`. A cancelled one leaves too.
    - **R8** "Recent decisions shows the 20 newest attention decisions as disclosures": 21 `decide` decisions and one `turn` decision give 20 rows, newest first, and "Recent decisions, 20". Row 1 shows the chip, the summary and the chevron, with `aria-expanded` false; a press sets true and shows every reason line; line 2 is the first reason; the meta reads "HH:MM · Confidence 0.90 · $0.0003". A fallback row shows "Tell now", the Fallback flag and its sentence, with no "Confidence".
    - **R9** "a decision event puts the new decision first, the oldest leaves, and focus on the leaving row goes to the heading": focus is on the 20th row's button; a seeded decision and `sinkEvent` of `decision.recorded` follow. Afterwards the new row is first, the old one is gone, and `document.activeElement` is the "Recent decisions" heading. A `turn` decision's event changes nothing.
    - **R10** "after live events the rail holds what a reload shows": the rail's `innerText` after R3- and R9-style events equals its text after a reload.
    - **R11** "with Telegram included, the first section is the Telegram card with its README link": `setTelegramIncluded(1)`, restored in `finally`, gives the first heading "Telegram" with no count, "Telegram not set up", the link "How to set it up (opens in a new tab)" with that href and `target="_blank"`, and an empty `.banner-slot`.
    - **R12** "markup in a summary or a reminder shows as text": the summary `<i>zz</i> …` and the reminder `<b>zz</b> …` show literally, with no `i` or `b` element in the rail.
- `web/e2e/frame/frame.spec.ts` F1: the h3s are asserted by accessible name (`Approval requests, 0`, …) and by their visible "(0)" spans for the README account. Everything else in F1 stays.
- `web/e2e/chat/notice.spec.ts` N3: the page-wide absence checks at `:143` and `:149-150` look in `main` (the chat), with a comment that the rail lists every attention decision. Then sweep every spec for page-wide locators that a rail row could now also match (`page.getByText(`, `page.getByRole('button'`, chips, summaries, reminder texts), and scope them to `main` where they mean the chat.
- `web/e2e/demo-path/01-page.spec.ts`: a new `@floor` test, "shows the status rail with its sections, counts and empty states" (REL-2). For the README account it checks:
  - the region Status;
  - the four headings in order with their "(0)" counts;
  - the four empty texts and both hints;
  - no Telegram section;
  - no live region in the rail.

**Acceptance Criteria:**
- **Approval events (FR-8, FR-12, AD-4, AD-31, AD-33).** **Given** a fixture `ApprovalRequest`, **when** `BridgeSink.OnEvent` gets any of the five `approval.*` types, **then** it reads the row through `Ownership.Approval` and publishes one `approval` event to the owning session's stream. For an `instance` incident's request it publishes to each session `Session.Recipients` returns. Tests: `TestApprovalEventsPublishTheRequest`, `TestApprovalOwnersThatPublishNothing`, `TestInstanceApprovalReachesEveryWatcher`, R3, R4.
- **DW-68 (AD-13 as amended).** **Given** an `instance` request, **when** its recipients can't be read, **then** BridgeSink logs a warning naming the event, the request and the incident, and publishes nothing. When nobody watches, it logs nothing. Two watching sessions both get the event, and the cross-owner reads are checked prepares that report their status. Tests: `TestFailedWatcherReadIsLoud`, `TestInstanceApprovalReachesEveryWatcher`, `TestApprovalIncident`, `TestRecipients`.
- **Until Stories 3.4 and 3.5 (AD-29).** **Given** this tree, where Lane A's approval code is not merged, **when** the approval tests run, **then** they use fixture rows and call `OnEvent` directly (`sinkEvent` in the browser), and the real raise and answer paths need no edit here when they merge.
- **The rail (FR-12, UX-DR23, UX-DR51, UX-DR90).** **Given** the main page, **when** the rail renders, **then** it:
  - is the region "Status", 288px wide and 320px from 1440px;
  - scrolls on its own and never collapses;
  - has its sections in order;
  - gives each list heading a live count, visible "(n)" and spoken ", n", with none for Telegram;
  - gives each row a title, a detail line when it has one, and a meta line;
  - shows the four empty texts.

  Tests: R1, `rail-view.test.mjs`, F1, and the new demo-path floor test.
- **Approval rows (FR-8, UX-DR52, UX-DR131).** **Given** pending requests, **when** the snapshot or an `approval` event arrives, **then** each shows one row with the 3px attention bar, its action and "Raised … · expires …". A request that is answered, expires or is cancelled leaves within one live update. Tests: R2, R3, `rail-view.test.mjs`. The focus half is the shared mechanism (Decided 5), pinned by R9.
- **Check rows (FR-12, FR-33, UX-DR53).** **Given** the session's checks, **when** the snapshot or a `check` event arrives, **then** each shows its name, schedule and last run with its result, the rows are read-only, and the hint sits under the list. A later event updates the row in place. Tests: R5, `rail-view.test.mjs`.
- **Reminder rows (FR-12, FR-34, UX-DR54, UX-DR124).** **Given** pending reminders, **when** the snapshot or a `reminder` event arrives, **then** each shows its text, a ticking tabular countdown and its due time, with the hint. A fired or cancelled reminder leaves within one live update, and a fired one's notice card is in the chat. A later event updates the row in place. Tests: R6, R7, `rail-view.test.mjs`, `page-time.test.mjs`.
- **Decision rows (FR-1, FR-4, FR-12, UX-DR57, UX-DR127, UX-DR131).** **Given** the session's decisions, **when** the snapshot or a `decision` event arrives, **then** Recent decisions shows the 20 newest attention decisions, newest first, as disclosures. Line 1 holds the chip, summary and chevron and expands every reason in place; line 2 is the first reason line; the meta line holds the time, confidence and the decision's own cost, and a fallback shows its flag and no confidence. A focused row that leaves passes focus to the heading. Tests: R8, R9, `rail-view.test.mjs`.
- **Live parity (FR-12, NFR-9).** **Given** events applied after the snapshot, **when** the page reloads, **then** the rail holds exactly what it held. Tests: R10, `rail-view.test.mjs`.
- **Telegram (FR-12, FR-21, FR-58, UX-DR55, UX-DR56, AD-29).** **Given** the release does not include Telegram, **when** the rail renders, **then** there is no Telegram section and no README link (R1, the floor test). **Given** `Included()` returns 1 (the test seam), **then** the first section "Telegram" reads "Telegram not set up" with "How to set it up" opening the README's Telegram section in a new tab and saying so, and no banner appears (R11). The card is `web/src/app/rail/telegram-card/`.
- **REL-2.** **Given** a fresh install and the README account, **when** the demo path's page step runs, **then** its new `@floor` test checks the rail's sections, counts and empty states (`live demo-path` prints `floor 3 of 3 passed`).
- **Safety (AD-13).** **Given** markup in a summary or a reminder, **when** it shows in the rail, **then** it is text. Tests: R12, and `page-safety.test.mjs`, which scans `rail/**`.

### Review Findings

Code review of 2026-10-23 (`bmad-code-review`, full mode, four layers; diff `59fed45` to the working tree, bookkeeping excluded). 35 raw findings became 12 entries: high 0, medium 5, low 7. 23 rows were rejected (appendix). Every patch below was applied in this pass (menu option 1).

- [x] [Review][Patch] (medium) The rail's decision row left the outcome's meaning in the chip's pointer tooltip alone. EXPERIENCE:216 says a tooltip never holds the only copy, and the chat strip describes itself with the meaning. Fix: the row's button is now `aria-describedby` a hidden element holding `meaningOf(chip)`, and R8 asserts the description of an `act` row and of a fallback row. [web/src/app/rail/decision-row.ts:33] (fix-risk low; in-story)
- [x] [Review][Patch] (medium) R6 seeded a real pending Reminder due at 12:01:30 UTC today, which is overdue on the stack's own clock for any run after that time. Once Epic 8's reminder timer merges (FR-34, fired within 10 s), it would fire the row mid-case. Fix: R6 now seeds and fixes the page clock on the day after the run's date. [web/e2e/rail/rail.spec.ts:247] (fix-risk low; in-story)
- [x] [Review][Patch] (medium, Rule 2) `TestNeverWaitsMoreThanASecond` kept an inline copy of the hold, wait and release code that QA extracted as `HoldStream` and `ReleaseStream`. It now calls the two helpers, and `Hold`'s doc names `HoldStream`. [src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls:458] (fix-risk low; in-story)
- [x] [Review][Patch] (medium, Rule 2) `main-page.ts`'s `RAIL_SECTIONS` restated the four labels that `RAIL_TEXTS` owns, so a wording change in one would split the loading and failed headings from the loaded ones. It is now built from `RAIL_TEXTS`. [web/src/app/main-page/main-page.ts:10] (fix-risk low; in-story)
- [x] [Review][Patch] (low) R5, R8 and R10 asserted same-day times with the page on the real clock and each `today()` call reading the date again, so a run crossing 00:00 UTC could read "<weekday> at 12:00". `today()` now uses the run's one date, and those three cases fix the page clock at 12:30 on it. [web/e2e/rail/rail.spec.ts:56] (fix-risk low; in-story)
- [x] [Review][Patch] (low) R11 set the Telegram seam outside its `try`, so a helper failure after IRIS had set it would leave the seam at 1 for every later spec. The set now runs inside the `try`, and `before` defaults to 0. [web/e2e/rail/rail.spec.ts:462] (fix-risk low; in-story)
- [x] [Review][Patch] (low) The rail-view test "a reminder with no due time" built a second row with `dueAt` undefined but asserted only the first. It now asserts both rows. [web/scripts/rail-view.test.mjs:337] (fix-risk low; in-story)
- [x] [Review][Patch] (low, Rule 19) The AC "Until Stories 3.4 and 3.5" had no `mutation:` line. Closed in this pass: the mutation is recorded under `## Verification`. [_bmad-output/implementation-artifacts/spec-2-8-show-the-status-rail.md]
- [x] [Review][Defer] (medium) DW-113: the failing branches of `Ownership.Watchers` and `Ownership.ApprovalIncident`, and `Session.Recipients` passing Watchers' status on, are run by no test. [src/ocutalon/cls/OcuTalon/Data/Session.cls:93] — deferred: `escalated owner=burndown`, fix-risk high. Every full pin crosses a project boundary:
  - a product test hook (`test-boundaries.sh`'s test-global rule allows one, `TelegramIncluded`; AD-29, Story 0.4);
  - a persistent test subclass of `Session` (a stored-schema veto item);
  - or a privilege-limited login fixture (roles, Rule 21).

  A subclass seam in `Ownership` alone would pin neither the pass-through nor DW-68's regression. Recommended: route it to `6-2-approve-or-reject-a-fix-from-the-web-chat`, whose REST answer path is where these reads really fail and where a real signed-in user can pin them.
- [x] [Review][Defer] (low) DW-120: `page-time.ts` and `rail-view.ts` each define the same `{name}` filler. [web/src/app/rail/rail-view.ts:129] — deferred: `wontfix-accepted`. The reason is weak: both are Node-run modules that cannot import values. Making the filler shared changes exported signatures and their tests, so the fix is not a two-way door. The ledger entry holds its `reopen_if`.
- [x] [Review][Defer] (low) DW-121: the initial bundle is 503.22 kB against the 500 kB warning budget. [web/angular.json:51] — deferred: `wontfix-accepted`. No product target sets the budget, the error limit is 1 MB, and the warning is kept as the growth signal. It reopens past 550 kB.
- [x] [Review][Defer] (low) DW-122: a session that stops watching a production keeps that production's pending instance approval rows in its live rail until a reload. [src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:80] — deferred: `wontfix-accepted`, out of footprint. The trigger is Epic 5's stop-watching flow, and the stale row is an extra row that a reload clears, never a missing alert.

**Rejected** (one line each):
- (Blind Hunter, Edge Case Hunter) Instance approval events fail when they are emitted from a REST request. This is spec-bound (Design Notes 14; the lead's spec-gate ruling): it is DW-68's residual for Story 6.2, which the lead adjudicates. No new entry.
- (Blind Hunter) The Telegram seam leaves `^OcuTalonTest("TelegramIncluded")` at 0 when it was absent: false. `Included()` is `$Get(...) = 1`, so absent and 0 read the same, and nothing else sets the node.
- (Blind Hunter) The whole rail is rebuilt every second while any reminder is pending: spec-bound. Boundaries › Times and Decided 11 say the clock ticks every second while a countdown shows.
- (Blind Hunter) The hold helpers leave `^OcuTalonTest("BridgeSink","hold",...)` behind: false. `OnAfterAllTests` kills the node. The duplication half is the patch above.
- (Edge Case Hunter, Acceptance Auditor) A failed row fetch in `Watchers` or `ApprovalIncident` reads as "nobody watches": theoretical. A checked SELECT of a small table under the default isolation level takes no locks. It becomes real if a fetch can fail after a good prepare and execute (for example a READ COMMITTED read with lock timeouts). The fix adds an untestable branch, as in the first review.
- (Edge Case Hunter) `Session.Recipients` ignores the status of `Incident.RefIndexOpen`: theoretical. This is a pre-existing line, the open takes no lock on this class, and the fix adds a branch.
- (Edge Case Hunter) Several busy watcher streams make the wait about N seconds: spec-bound ("waits at most LOCKWAIT on each stream's lock").
- (Edge Case Hunter) A check event with `stopped: true` stays listed: false. `Live.Payload.Check.Stopped` means the watched production is stopped, and the row still exists after a reload.
- (Edge Case Hunter) A production check with an empty `displayName` reads " production": not worth the guard. The producer always sets the name, and the fix adds a fallback.
- (Edge Case Hunter) `seedDecisions` leaks the saved rows when a later save fails: as in the first review, only after a save failure that ends the run.
- (Verification Gap) R7's notice card is the one the test sent: spec-bound. R7 is the spec's own case, and the link from a fired reminder to its card is Epic 8's emitter.
- (Verification Gap) The ACs Approval events, DW-68 and The rail have no `mutation:` line: false. Each of them has recorded mutations, and Rule 19 asks one per AC.
- (Verification Gap) `page-time.test.mjs` "the same instant reads as pageTime" cannot fail: false. It goes red when `pageWhen` drops the caller's defaults (a hardcoded locale on an en-US runner). A hardcoded zone on a UTC runner is the only blind spot, and the zone rows elsewhere cover it.
- (Verification Gap) The R cases assert counts on one shared `RAIL` user: spec-bound. The spec names one fixture user, every case cleans in `finally`, and the config runs one worker.
- (Acceptance Auditor) The decision row's title uses `--decision-row-typography-*`: false. The decision row is its own component, and the spec's Code Map and DESIGN.md name its tokens.
- (Acceptance Auditor) `TestApprovalIncident` relies on the class-wide `Fixture.Clean()`: no reachable harm. It is the class's existing lifecycle, and one test class runs at a time on a slot (Rule 18).
- (Acceptance Auditor) `setTelegramIncluded` interpolates a typed `0 | 1`, and the seed helpers report a Ref rather than a status: no harm. The value is a typed literal, and a failed save still shows as a missing CHK line.

## Spec Change Log

- 2026-10-23, lead (spec gate): veto U-36 ruled (keep the four items); spine Conventions rows "Live events" and "README link" amended; DW-68's residual to be re-owned to Story 6.2 at adjudication.

## Review Triage Log

### 2026-10-23 — Review pass
- verdicts: 33 findings — high 0, medium 9, low 18, false 6, maybe-false 0
- findings:
  - `[medium]` `[defer]` (Blind Hunter) The real failure paths of the DW-68 reads are never exercised; dropping `.sc` from `Session.Recipients` leaves every test green — verified: `TestFailedWatcherReadIsLoud` swaps the BridgeSink seam above every path that can fail, and the other tests assert only `sc` OK. A real failure cannot be induced here (measured: `$ROLES=""` keeps `%All`, a `UnknownUser` login ends the process with `<PROTECT>`, no bound value gives an SQL error), and the smallest fix is a seam in product code (not trivial), so it is deferred with that evidence; grouped with the verification-gap and intent-alignment sightings below.
  - `[low]` `[patch]` (Blind Hunter) The per-recipient `ERRORFAILED` branch names neither the event, the request nor the recipient and is untested — real: the line now names type, request and recipient, and `TestAFailedRecipientReadDoesNotStopTheOthers` (new `BridgeSinkRefusedProbe`, whose seam names the owner eval, which Ownership refuses) pins the warning and that the next recipient still gets the event; two mutations recorded.
  - `[low]` `[patch]` (Blind Hunter) The class comment lost "eval and instance publish nothing" for `decision.recorded` and `turn.step` — real: one sentence restored in `BridgeSink`'s class comment.
  - `[low]` `[reject]` (Blind Hunter) The LOCKWAIT bound holds per recipient, not per call — the spec says "waits at most LOCKWAIT on each stream's lock" (Boundaries; AD-31 "waits at most 1 s on a lock"), and the comment says per stream; worst case needs several contended streams at once. By design.
  - `[medium]` `[patch]` (Blind Hunter) R2 and R6 fail in the minute after 00:00 UTC — real: R2 raised at now-60 s and expiring at now+24 h-60 s, and R6's due time at start+59 s, cross a date line near midnight. Both now take the page's clock from noon UTC (`setFixedTime`); R2 asserts both meta lines exactly.
  - `[medium]` `[patch]` (Blind Hunter) The slow clock branch and the interval switch have no test — real: R13 added (idle rail: the day words follow the page's date after the minute tick; a reminder arriving after the load starts the 1 s tick); two mutations recorded.
  - `[low]` `[patch]` (Blind Hunter) The Telegram card's `rejected` branch is untested, and state `on` renders an empty section — the test gap is real: R11 now loads the snapshot with `rejected` and `on` (mutation recorded); the empty body for `on` is the spec's own ("State `on` shows nothing under the heading; Story 12.3 adds its states").
  - `[low]` `[reject]` (Blind Hunter) `sinkEvent` can pass `applied()` when nothing was published — the helper returns the stream's last Seq by the spec; a sink that publishes nothing still fails the next assertion, only with a less specific message, and R9's "a turn decision changes nothing" relies on the unchanged Seq.
  - `[low]` `[patch]` (Blind Hunter) The doc comment of the new `@floor` test is garbled — real: reworded.
  - `[low]` `[reject]` (Edge Case Hunter) A row fetch that fails after a good prepare and execute reads as nobody watching (`Watchers`, `ApprovalIncident`) — no failing fetch can be shown on a simple SELECT of a small table, the pattern is `Ownership.Rows`'s, and the guard cannot be tested here; unlikely, and the fix adds a branch.
  - `[low]` `[reject]` (Edge Case Hunter) `Session.Recipients` ignores the status of `Incident.RefIndexOpen` — pre-existing line; the story's `sc` is the watcher read's, as the spec says; unlikely, and the fix adds a branch.
  - `[medium]` `[patch]` (Edge Case Hunter) The nowrap decision meta line overflows the 264px rail for the long date forms — verified in a browser: "Sep 18, 2025 at 14:12 · Confidence 0.90 · $0.0003" is 298px in a 263px line and gives the rail a sideways scrollbar (310px in 287px); "Tuesday at 14:12 · ..." is 5px over. Fixed with `flex-wrap: wrap` (as the check and approval rows have); R8's 20th row now dates from last year and asserts no sideways scroll (mutation recorded).
  - `[low]` `[reject]` (Edge Case Hunter) `seedDecisions` leaks the saved rows when a later row fails — only after a Decision save fails, which ends the run anyway; the fix adds a branch.
  - `[low]` `[patch]` (Edge Case Hunter) `SeedDecision.recordedAt` is ignored on the `seedTurns` path — real: `decisionLines` now passes `decision.recordedAt ?? createdAt`.
  - `[low]` `[reject]` (Edge Case Hunter) Telegram state `on` shows a bare heading — by design (same sighting as the Blind Hunter's), the spec leaves the state to Story 12.3.
  - `[medium]` `[defer]` (Verification Gap) The failed `Watchers`/`ApprovalIncident` read and its pass-through are never exercised — same root cause as the first row; deferred (see the `deferred:` entry).
  - `[medium]` `[patch]` (Verification Gap) The failed-state rail (four plain headings) is not asserted after the template split — real: the condition `!== 'loading'` kept every test green; L7 now asserts the four plain headings and no `app-status-rail` (mutation recorded).
  - `[medium]` `[patch]` (Verification Gap) The clock's rate switching is unpinned — same root cause as the second `medium` patch above; R13.
  - `[low]` `[patch]` (Verification Gap) The Telegram `rejected` and `on` branches are unpinned — same as the Telegram row above; R11.
  - `[low]` `[reject]` (Verification Gap, other findings) Sub-claims with no `mutation:` line (widths, hints, ordering, the link's attributes, the `ERRORFAILED` branch) — Rule 19 asks one demonstrated mutation per acceptance criterion, and each AC has one; the `ERRORFAILED` branch has its own now.
  - `[low]` `[patch]` (Verification Gap, other findings) The safety mutation shows red only in `page-safety.test.mjs` — the mutation (`[innerHTML]` on the decision summary) was applied again against R12, which goes red ("the summary shows as typed"); the line now names both.
  - `[low]` `[reject]` (Verification Gap, other findings) R8 stays green when the view keeps `turn` decisions or caps at 21 — `/state` already filters and caps, so those assertions guard `RailBody`; the view is pinned by R9 and `rail-view.test.mjs`, as the recorded mutation lines say.
  - `[low]` `[reject]` (Verification Gap, other findings) R5 stays green when check rows are keyed by position — one row keeps its place; `rail-view.test.mjs` pins the keying, as recorded.
  - `[medium]` `[patch]` (Verification Gap, other findings) R2 depends on the wall clock — the same root cause as the midnight row above.
  - `[low]` `[reject]` (Verification Gap, other findings) R7 leaves the notice row it sent behind — the row has a unique text, belongs to the rail user alone and no later case reads it; `notice.spec` does the same.
  - `[low]` `[reject]` (Verification Gap, other findings) F1 and the floor test rely on a clean README account — the spec states it ("a fresh install as the README account, with an empty rail"), and no spec seeds that account.
  - `[medium]` `[defer]` (Intent Alignment) The DW-68 failure path is tested only through the test-injected seam, not at the read sites — the same root cause as the first row; deferred.
  - `[false]` `[reject]` (Intent Alignment) Every test calls `BridgeSink.OnEvent` directly with fixture rows — no defect claimed; Lane A's emitters are not merged here, which the AC "Until Stories 3.4 and 3.5" states.
  - `[false]` `[reject]` (Intent Alignment) The focus rule is generic but only decision rows can hold focus, so only the decisions heading is exercised — no defect claimed; Decided 5 says so, and R9 pins the mechanism.
  - `[false]` `[reject]` (Intent Alignment) R10's reload comparison leaves reminders out and R4 is not reloaded — no defect claimed; the spec's R10 is R3- and R9-style events, and `rail-view.test.mjs` compares the live and reloaded views of every list.
  - `[false]` `[reject]` (Intent Alignment) Any result other than `passed` or `failed` reads "Not checked" — no defect claimed; the spec names the three words, and the mapping mirrors the chat's check rows.
  - `[false]` `[reject]` (Intent Alignment) N3's page-wide absence checks were scoped to `main` — no defect claimed; the spec's Tasks require it, because the rail lists every attention decision.
  - `[false]` `[reject]` (Intent Alignment) R11 flips a stack-wide test global, and the loading and failed states have no new test — no defect claimed for the global (one worker, restored in `finally`); the failed-state half is the L7 row above.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-4:** `Recipients` is the one resolver for an `instance` incident's sessions; ownership is enforced through `Ownership`.
- **AD-11:** the row is the truth, so rows leave when its state does.
- **AD-12:** full views keyed by `Ref`; polling is the release-1 live path; events are applied idempotently.
- **AD-13 as amended:** `Ownership.Rows` stays the one unchecked prepare. `Watchers` and `ApprovalIncident` are checked and run in production jobs and tests. Text is rendered as text.
- **AD-18:** page times are in the browser's zone; reminders and checks.
- **AD-20:** a decision row shows the decision's own cost.
- **AD-29:** Lane A's approval code is read-only and tested with fixtures; the Telegram card is its own component; `Included()`.
- **AD-31:** BridgeSink is the only place that turns bridge events into `Live.Publish` calls. It reads through Ownership, never fails its caller, and waits at most 1 s on a lock.
- **AD-33:** `approval` has one publisher, BridgeSink; `check` and `reminder` keep their publishers, and tests publish fixtures.
- **Conventions:** Live events, Times, Identifiers, Tests, Angular, README link, Text OcuTalon sends (page strings as TS constants), Notice cards (the fired reminder's card).

No AC contradicts an AD's Rule.

**Rule 5:** "within one live update" is measured exactly. The test waits until the page has applied the event's Seq and then asserts. No NFR is unmeasurable as worded.

**Decided in-stage** (small, reversible, within the intent):
1. **No split.** The server part is three short methods. The page part is one view module, three components and a time helper, about Story 2.7's size, which ran in one implement pass. The approval-row tests need both halves.
2. **Recent decisions gets a count too.** The AC says every list section has one. The mockup's missing count loses to the AC and EXPERIENCE:235.
3. **Hints always show**, as in the mockups (main-page.html:395-400,622-627), even under an empty list. Their quotes are straight ASCII, as in EXPERIENCE:237-238 and the AC; the page's strings use ASCII punctuation except "·" and "…".
4. **The demo-mode empty text of Background checks** ("Nothing yet. Step 1 of the guide sets up a watch.") is Story 4.4's (epics.md:2192). It names a guide that doesn't exist yet, so this story always shows "Ask OcuTalon to watch a production."
5. **Approval rows hold nothing focusable in this story.** Their press is Story 6.3's (epics.md:2646-2648) and their trace link is Story 2.9's. The focus rule is one mechanism for every list section, pinned by R9 with decision rows, so it applies to approval rows as soon as they hold a focusable element.
6. **Approval titles** use `affected`, the count AnswersIn and the card use (epics.md:2594,2600), with the noun by count. With no dry run the title is "Repair and resend". A `tool_call` request is "Run {toolName}", the UX's "Run {tool} on {server}" (EXPERIENCE:912) without the server, because release-1 tools have none.
7. **The row anatomy.** A detail line shows only when it has content: approval rows have none, as in the mockup. A reminder's title is "{text} · {countdown}", the UX fixture "Stretch · in 59 s", with "Due {time}" as its meta, from Story 2.7's `NOTICE_TEXTS.due`.
8. **Check rows.** Kind `production` gives "{displayName} production" and "Live, plus a check every minute" (FR-23: live failures plus the minute heartbeat). The last-run line uses the finding, else the existing words Passed, Failed and Not checked. There is no meta before the first run, so no new text.
9. **`pageWhen`** follows the Times convention's day rules in the browser's zone and hour format, and adds "tomorrow at", the UX's fixture word (UX-DR52, epics.md:2594). Day and month names are English, so a German browser doesn't mix languages; the hour format is the browser's (EXPERIENCE:180).
10. **The countdown** is EXPERIENCE:183's: seconds round up and minutes round down, so "in 9 min" means 9 minutes and some seconds. It never goes below "in 0 s", because a due reminder leaves when its fired event arrives, within 10 s (FR-34). From an hour it always shows both units ("in 2 h 0 min"), and the spoken forms are full words.
11. **The clock** ticks every second only while a countdown shows, and every 60 s otherwise, so day words such as "tomorrow" roll over.
12. **A reminder's text shows as stored**, with no change of case. The producer (Epic 8) stores what the user asked for.
13. **The Telegram card** has one state in this story, "not set up", for `off` and `rejected`. `/state` always reports `off` here (`Api.cls:284`). The README anchor is `#telegram`, a convention that Story 12.7's README section and Story 10.2's link check meet.
14. **DW-68** is met without an AD-13 amendment.
    - The cross-owner reads stay checked and report failures.
    - BridgeSink is loud on a failed read and never treats it as nobody watching.
    - Every release-1 emitter but one runs in a production job, where the read is allowed: raise in the gate's job or IncidentManager; expire in ApprovalHold; cancel in SessionOps or McpOps; result in FixExecutor or ApprovalHold.
    - The exception is Story 6.2's web answer path, which runs `Approval.Answer` in the signed-in user's request (epics.md:2605). There the reads fail, loudly (inference from AD-13's measured amendment, Story 2.2; nothing in this tree runs that path).
15. **`Ownership.ApprovalIncident` is new** because an `instance` request can't be read through `Ownership.Approval`, which needs a session, and AD-31 bars Core from opening a bridge row itself.
16. **The views filter and sort the store, and the store doesn't change.** `decisions` keeps every kind, and the view keeps `decide` decisions, newest `recordedAt` first (a stable sort, so a tie keeps the store's order, which is ID order), capped at 20. Approvals and reminders keep pending ones, sorted as `RailBody`'s SQL sorts them, and checks keep the map's insertion order. These are the orders a reload gives.
17. **While loading or failed, `main-page` keeps its plain headings and skeletons.** Telegram is unknown before the snapshot, so L5's four skeleton groups stay.
18. **The live-update checks wait on the page's `data-session-seq`**, which `sinkEvent` and the publishers' returned Seq make exact, rather than on a wall-clock bound that a busy runner could miss. The 2 s live bound is Story 2.2's L-tests'.
19. **The 1440px width** is a component media query, because no token encodes the breakpoint (tokens.css holds only the 320px value).
20. **DW-68 in the browser** uses one watching user (R4). The two-watcher case is the `%UnitTest`, against real fixture rows.

**Veto-window items for the lead** (unattended policy):
1. **Text not written out in the UX:**
   - "Run {toolName}";
   - "Repair and resend" with no count;
   - "{displayName} production" for any display name;
   - "Last run {time} · Passed", "· Failed" or "· Not checked";
   - "in 0 s", and "in {h} h 0 min";
   - the rail's day words "tomorrow at", "{Weekday} at" and "{Mon} {D}[, YYYY] at".

   Each is composed from the UX's own strings and the Times convention.
2. **What a row leaves out until its story:** approval rows have no press (6.3) and no trace link (2.9); check rows have no stopped state.
3. **A cross-story convention:** the README's Telegram section is at `#telegram` (Stories 12.7 and 10.2).
4. **DW-68's residual** belongs to Story 6.2 (Ledger below). Putting a `DW-n` bullet on another epic's not-yet-planned story is a veto item (8), routed by the orchestrator in a parallel run.

There is no new dependency, privilege, secret or stored data. `ZzRail` exists only on throwaways, with the user role.

**Spine notes for the lead (Rule 20, light path):**
- **AD-31 / AD-4:** BridgeSink resolves an `instance` request's recipients through `Session.Recipients`, after `Ownership.ApprovalIncident`. The cross-owner reads are checked prepares that run only in production jobs and tests, and a failed one is logged and publishes nothing. An emitter that runs in a REST request (Story 6.2's answer path) hands the fan-out to a production job or asks for an AD-13 amendment.
- **Conventions, "Live events":** the rail's views are what a reload gives:
  - approvals: pending, by raised time;
  - checks: by row;
  - reminders: pending, by due time;
  - decisions: `decide` only, the 20 newest.

  `decision` events of other kinds reach the store but not the rail.
- **AD-13** needs no amendment.

**Lead's rulings at the spec gate (2026-10-23).**
- **Veto U-36:** the four veto-window items above are kept as planned (keep (a)); the owner may reverse any one before the release.
- **Spine:** the notes above went into the Conventions rows "Live events" (the `approval` fan-out through checked reads, and the rail's view orders) and "README link" (`#telegram`), not as AD amendments: AD-31 and AD-4 are extended, not contradicted. The sentence about an emitter in a REST request is carried by DW-68's residual, not the spine.
- **DW-68's residual** is re-owned to `6-2-approve-or-reject-a-fix-from-the-web-chat` at this story's adjudication, as recommended; the orchestrator writes its `DW-n` bullet after the merge.

**Integration ACs (Rule 1).**
- The page reads BridgeSink's `approval` events through `/events` and adds or removes the row (R3, R4). On a real throwaway, `sinkEvent` drives the real BridgeSink, Ownership and `Live.Publish`.
- The page reads `/state`'s rail (Story 2.2's `RailBody`) and renders every section (R1, R2, R5, R8, and the demo-path floor test).
- `check` and `reminder` events published through `Live.Publish` update rows in place (R5-R7).
- `Session.Recipients` and the two Ownership reads feed BridgeSink's fan-out against real fixture rows on slot B (`TestInstanceApprovalReachesEveryWatcher`).

**Consumed-by:**
- **2.9:** the trace links in the rail rows' meta lines.
- **2.10:** the "(late)" mark on check rows; banners.
- **2.12:** the rail's announcements and counts, the drawer, DW-89's tab stops, the cross-browser runs and the scan.
- **4.4:** the demo-mode empty text.
- **6.2:** the REST answer path and DW-68's residual.
- **6.3:** the approval row's press, and a row leaving after an answer anywhere.
- **3.4 and 3.5:** the real raise, answer, expire and cancel emitters.
- **30.3:** a replayed tool call's `approval.result` (DW-99).
- **8.3 to 8.5:** reminder events from `ReminderOps` and `ReminderTimer`.
- **Epic 5:** `check` events from `Checks`.
- **10.3 and 12.3:** the Telegram card's states; Lane A owns the card from Epic 12.
- **11.1:** 04-incident's "Approval requests (1)" end to end.
- **21.x and 22.4:** "Run {tool} on {server}" rows.

**Consumes:**
- 0.4: the `Recipients` contract;
- 0.5: the payload classes;
- 0.6: the HostSink contract;
- 2.1: the frame;
- 2.2: `RailBody`, the live store, Ownership's rail reads and `Recipients`;
- 2.6: BridgeSink, the decision-view helpers, the chip and the flag, and decision events;
- 2.7: the reminder notice card, `NOTICE_TEXTS` and `page-time`.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `BridgeSink.Approved` follows `Recorded`.
- `ApprovalIncident` follows `Watchers`, which is checked and reads across owners, and `DeliveryFor`, which compares exactly.
- `Recipients` and `Watchers` are extended with a status.
- The rail's time words extend `page-time.ts`.
- The decision row reuses the chip, the flag, `decision-view`'s helpers and decision-strip's disclosure pattern. It is a separate component because its layout differs: the whole line 1 is the button.
- The fallback sentence lookup is one exported function that both components call.
- `Fixture.Approval`, `Check` and `Reminder` gain `Decision`'s trailing `fields`.
- The new e2e helpers follow `sinkEvent` and `seedDecision`, `publishReminder` gains fields, and `cleanFixtureRows` moves to `iris.ts`.
- The clock follows `chat-panel.ts:213-217`.
- The Telegram link reuses `README_URL` and `CHAT_TEXTS.opensInNewTab`, with about-dialog's markup.

**Ledger (Rule 17).**
- **DW-68** is addressed by:
  - `Watchers`' and `Recipients`' status;
  - `ApprovalIncident`;
  - BridgeSink's loud failure;
  - the tasks citing DW-68 (`TestInstanceApprovalReachesEveryWatcher`, `TestFailedWatcherReadIsLoud`, `TestApprovalIncident`, `TestRecipients`);
  - R4.

  **Residual for the lead:** Story 6.2's web answer path (`6-2-approve-or-reject-a-fix-from-the-web-chat`, epics.md:2605) calls `Approval.Answer` in the signed-in user's REST request. There BridgeSink's cross-owner reads fail, and the other watchers' rails keep the answered `instance` request until their next reload. Recommended: at adjudication, re-own that residual to Story 6.2 with the note "the answer path hands the instance fan-out to a production job, or asks for an AD-13 amendment". This is veto item 4 above.
- **DW-99** is not this story's. It is routed to Story 30.3. This story handles `approval.result` through `OnEvent` with fixture rows, as the AC says.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message.
- **Throwaway commands** are `OCUTALON_RUN_TAG=e2s28i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`. Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag. A `LOCK busy` exit 75 means contention: wait and run it again.
- **Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), in two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: every test passes, and no `zz` row, event or log row is left behind.
  - Changed: `OcuTalon.Test.Core.BridgeSink`, `Test.Data.Session`, `Test.Data.Ownership`.
  - Regression: `Test.Core.WebChatOut`, `Test.Core.Routing`, `Test.Web.Api`, `Test.Live.Payloads`, `Test.Contract.Ac`, `Test.Data.Delivery`.
- (loop) Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/payloads.mjs --check`, `node web/scripts/catalog.mjs --check`, `node web/scripts/tokens.mjs --check`. Expected: exit 0.
- (loop) `bash docker/tests/test-web-build.sh`. Expected: exit 0, with every new component's styles under the 4 kB warning.
- (loop) Each in its own call: `bash docker/tests/test-class-rules.sh` (`ALLOW_UNCHECKED` unchanged; no new unchecked prepare), `test-boundaries.sh`, `test-ci-config.sh`. Expected: exit 0.
- (loop) Throwaway, one piece per call: `build`; `live sign-in` (R1-R12, F1-F9, L1-L13, S1-S8, C1-C15, D1-D13, N1-N15); `live demo-path`; `teardown`.
  - Expected: each piece passes, and the demo path prints `floor 3 of 3 passed`.
  - Teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `shard lane-b`; `shard lane-b --reverse`; `shard lane-a`; `teardown`. Expected: every class passes.

**Planned mutations (Rule 19).** For each one, the implement stage:
1. applies the mutation;
2. observes red;
3. restores a byte-identical tree (`git status --short` and `git diff --stat` unchanged);
4. records `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Approval events | `Approved` reads the row by `RefIndexOpen` (no owner) | `TestApprovalOwnersThatPublishNothing` |
| Approval events | the approval dispatch after the session guard | `TestInstanceApprovalReachesEveryWatcher`; R4 |
| DW-68 two watchers | publish only to the first recipient | `TestInstanceApprovalReachesEveryWatcher` |
| DW-68 loud | a failed `Recipients` read treated as no recipients (no warning) | `TestFailedWatcherReadIsLoud` |
| DW-68 status | `ApprovalIncident` matches the Ref without regard to case | `TestApprovalIncident` |
| Rail order and counts | the count left out of the spoken heading | `rail-view.test.mjs`; R1; floor test |
| Empty texts | "None pending." for approvals | `rail-view.test.mjs`; R1 |
| Approval rows | the pending filter removed | `rail-view.test.mjs`; R3 |
| Attention bar | the bar's width 4px | R2 |
| Check rows | "production" left out of the title | `rail-view.test.mjs`; R5 |
| In place | the view keys check rows by position | `rail-view.test.mjs`; R5 |
| Reminder rows | the clock never ticks | R6 |
| Fired | fired reminders kept | `rail-view.test.mjs`; R7 |
| Countdown | minutes rounded up | `page-time.test.mjs` |
| Times | "tomorrow at" never used | `page-time.test.mjs`; R2 |
| Decisions | `turn` decisions kept, or the cap at 21 | `rail-view.test.mjs`; R8 |
| Disclosure | `aria-expanded` never changes | R8 |
| Fallback | confidence shown on a fallback | `rail-view.test.mjs`; R8 |
| Focus | the heading not focused when a row leaves | R9 |
| Live parity | decisions not sorted by `recordedAt` | `rail-view.test.mjs`; R10 |
| Telegram | the section shown when not included, or the link without "(opens in a new tab)" | R1 or R11; `rail-view.test.mjs` |
| Safety | `[innerHTML]` for the summary | `page-safety.test.mjs`; R12 |
| REL-2 | the headings without counts | the new demo-path floor test |

**Mutations observed (Rule 19, implement stage).** The server mutations ran on slot B, the page mutations on the built bundle with `rail.spec.ts` and the floor test run unchanged against an in-memory stand-in for the server (a scratch harness, not committed), and R4 on a real throwaway (`live sign-in`, tag e2s28i). Each was restored byte-identical before the next (`git status --short` and `git diff` unchanged).
- mutation: `Approved` reads the row by `ApprovalRequest.RefIndexOpen` (no owner) -> `TestApprovalOwnersThatPublishNothing` (and `TestInstanceApprovalReachesEveryWatcher`)
- mutation: `OnEvent` dispatches the approval types after the session guard -> `TestInstanceApprovalReachesEveryWatcher` (and `TestFailedWatcherReadIsLoud`); on the real throwaway R4 alone went red (140 passed, 1 failed)
- mutation: the recipient loop publishes to the first recipient only -> `TestInstanceApprovalReachesEveryWatcher`
- mutation: the failed `Recipients` read logs no warning -> `TestFailedWatcherReadIsLoud` (and `TestNeverFailsItsCaller`)
- mutation: `ApprovalIncident` takes every row the collated SQL equality returns, without the exact Ref comparison -> `TestApprovalIncident` ("the Ref in another case gives none")
- mutation: the spoken heading is the label alone -> `rail-view.test.mjs` (3 tests), R1, the floor test
- mutation: `emptyApprovals` is "None pending." -> `rail-view.test.mjs` (2 tests), R1
- mutation: the approvals view drops its pending filter -> `rail-view.test.mjs` (2 tests), R3
- mutation: the attention bar is `4px solid` -> R2 ("a 3px bar")
- mutation: the check title is "{name}" with "production" left out -> `rail-view.test.mjs` (4 tests), R5
- mutation: check rows keyed by position (`checks:<index>`) -> `rail-view.test.mjs` (2 tests); R5 stays green, because a single row keeps its position and no event reorders checks, so the pinning test of "in place" is `rail-view.test.mjs`
- mutation: the interval callback does nothing (the clock never ticks) -> R6 ("and it ticks")
- mutation: the reminders view drops its pending filter (fired reminders kept) -> `rail-view.test.mjs` (2 tests), R7
- mutation: countdown minutes rounded up (`Math.ceil`) -> `page-time.test.mjs` ("counts whole minutes, rounded down")
- mutation: `pageWhen` never takes the "tomorrow at" branch -> `page-time.test.mjs` (5 tests), R2
- mutation: the decisions view keeps `turn` decisions -> `rail-view.test.mjs` (2 tests), R9 ("a turn decision changes nothing"); R8 stays green, because `/state` already holds only `decide` decisions
- mutation: the decisions view caps at 21 -> `rail-view.test.mjs` (2 tests), R9 ("the list still holds twenty"); R8 stays green, because `/state` is capped at 20
- mutation: `aria-expanded` bound to `false` -> R8 ("a press expands it")
- mutation: confidence shown on a fallback -> `rail-view.test.mjs` ("a fallback ... no confidence"), R8
- mutation: the heading is not focused when a row leaves -> R9 ("focus moved to the Recent decisions heading")
- mutation: decisions not sorted by `recordedAt` -> `rail-view.test.mjs` (2 tests), R10 (the event's decision is older than two that the store holds)
- mutation: the Telegram section shown whether or not the release includes it -> `rail-view.test.mjs`, R1 ("four sections, no Telegram")
- mutation: the Telegram link without " (opens in a new tab)" -> R11
- mutation: `[innerHTML]` for the decision summary -> `page-safety.test.mjs` (2 tests), R12 ("the summary shows as typed")
- mutation: the visible heading is the label alone (no count) -> the new demo-path floor test ("and shows it")

**Deviation from the Matrix, for the lead.** R6 pins "in 59 s" and "in 57 s" with Playwright's page clock (`install` and `setFixedTime`), so the page's `Date.now()` is the test's `start` and the numbers are exact; the pure functions are also pinned with an injected `now` in `page-time.test.mjs` and `rail-view.test.mjs`.

**Mutations observed in the review pass (Rule 19).** The server ones ran on slot B, the page ones on the built bundle in the same scratch harness (`rail.spec.ts` against an in-memory stand-in for the server), and L7 with R11 together on a real throwaway (`live sign-in`, tag e2s28i: 140 passed, 2 failed, 1 skipped). Each was restored byte-identical.
- mutation: a failed read of one recipient stops the loop (`Quit` in place of `Continue` in `Approved`) -> `TestAFailedRecipientReadDoesNotStopTheOthers` ("the next recipient gets its event")
- mutation: the recipient warning leaves the request out -> `TestAFailedRecipientReadDoesNotStopTheOthers` ("naming the event, the request and the recipient")
- mutation: the clock's interval callback does nothing while no reminder shows a countdown -> R13 ("a minute on, the page is on the next date and the day words follow")
- mutation: the interval keeps the rate it was created with (`untracked(() => this.counting())`) -> R13 ("and the clock now ticks every second")
- mutation: the decision meta line is `white-space: nowrap` in place of `flex-wrap: wrap` -> R8 ("and the rail does not scroll sideways")
- mutation: `main-page` renders the status rail for every state but loading (`live.status() !== 'loading'`) -> L7 ("the rail keeps its four plain headings after a failed load")
- mutation: the Telegram card is "not set up" for `off` alone (`rejected` dropped) -> R11 ("state rejected: the card says it is not set up")

**Review-pass changes to the pinning tests.** R2 and R6 take the page's clock from noon UTC (`setFixedTime`), so a run in the first or last minute of a UTC day cannot move a time across a date line; R2 now asserts both meta lines exactly. R8's two oldest decisions date from last year. R11 also loads the snapshot with Telegram `rejected` and `on` (route patch of `/state`). L7 asserts the rail's four plain headings and no `app-status-rail`. R13 is new: it pins the clock's two rates. `test-sign-in.sh` labels the rail rows R1-R19 (R14-R19 are QA's, below).

**QA stage (2026-10-23): tests added (Rule 8, Rule 19).** No new file: every addition joins a file that the default run already discovers (the `lane-b` shard holds `Test.Core.BridgeSink` and `Test.Data.Ownership`; `npm --prefix web test` globs `scripts/*.test.mjs`; the chromium project runs `e2e/rail/rail.spec.ts`).
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls`: `TestApprovalNeverWaitsMoreThanASecond` (an approval event waits about a second on a held stream, drops with one `ERRORPUBLISH` warning and publishes once the lock is free; of two watchers of an instance request the one with the free stream still gets its event) and `TestOnlineDemoStillPublishesASessionsOwnRequest` (with onlineDemo on, a session's own request is published to it, as the demo's approval step needs, and an instance request is not); the private helpers `HoldStream` and `ReleaseStream`.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`: `TestApprovalIncident` also gives a Ref with a quote and a Ref with LIKE wildcards (a bound value: none found, status OK).
- (QA) `web/scripts/rail-view.test.mjs`: "a value that holds a placeholder is shown as typed and filled in once" (a reminder text `{countdown}`, a noun `{n}`).
- (QA) `web/e2e/rail/rail.spec.ts`: R14 (a decision row that stays keeps focus and stays open when an event adds a row above it), R15 (focus in the composer stays there when an approval leaves and when a decision arrives), R16 (each decision button's `aria-controls` names an element of its own row, by an id no other element has), R17 (20 rows at 1280x720: the wheel scrolls the rail, the page has nothing to scroll, the rail keeps 288px and the chat stays in view), R18 (a row of every kind: no live region or announcing attribute, the ticking countdown and the chevron are `aria-hidden`, the spoken words are not), R19 (a summary and a first reason longer than the line are cut to one line with an ellipsis, an open row shows every reason in full).
- (QA) `docker/tests/test-sign-in.sh`: the labels read R1-R19.

**Mutations observed by QA (Rule 19).** Server mutations ran on slot B, page mutations on a rebuilt bundle in `live sign-in` (tag e2s28q) in four groups of disjoint code (the `$index` and `min-height` mutations; the `keepFocus`, shared-id and `overflow-y` ones; the two ARIA ones; the `nowrap` one alone); every one was restored byte-identical (`shasum` of the file before and after, `git status --short` and `git diff --stat -- web/src` unchanged). `mutations_demonstrated=12`.
- mutation: `Approved` publishes through `Live.Publish.Publish` with its own five-second wait instead of the sink's `Publish` -> `TestApprovalNeverWaitsMoreThanASecond` ("it waited about a second, not five: 5.00 s", both parts)
- mutation: `Approved` quits when onlineDemo is on -> `TestOnlineDemoStillPublishesASessionsOwnRequest` (the other 14 BridgeSink tests stay green: the gap was real)
- mutation: `ApprovalIncident` puts the Ref into its SQL text in place of the bound `?` -> `TestApprovalIncident` ("a Ref with a quote ... is no error": SQLCODE -3, closing quote missing)
- mutation: `rail-view.ts`'s `fill` replaces the placeholders one after another -> `rail-view.test.mjs` "a value that holds a placeholder" (`in 59 s \u00B7 in 59 s` for `{countdown} \u00B7 in 59 s`)
- mutation: the rows of a section tracked by `$index` in place of `row.key` -> R14 alone ("the open row is still open"; R5, R9 and R10 stay green, so R14 is the only pin of the keyed rows in the DOM)
- mutation: `keepFocus` without its two early returns (focus outside a row counts as the decisions heading) -> R15 ("the composer still holds focus"); L4, C1, C2, C6, D9 and N12 went red too
- mutation: the reasons id of a decision row is the same for every row (`++lastId` dropped) -> R16 ("by three different ids")
- mutation: `.rail` is `overflow-y: hidden` -> R17 ("the wheel over the rail brings the oldest into view") and R1 (its CSS check)
- mutation: `:host` of `main-page` loses `min-height: 0` -> R17 ("the rows are taller than the rail": the rail grows to its content) and C6, C9, C10 and N12; R1 stays green
- mutation: the ticking countdown loses `aria-hidden` -> R18 ("the ticking countdown is hidden from assistive technology")
- mutation: the decision row's reasons container gets `aria-live="polite"` -> R18 ("the rail has no live region" and "an open row is no live region either"); both ran in one `live sign-in`, the soft assertions reporting each
- mutation: `white-space: nowrap` is `normal` in the decision row's `.summary` and `.one-line` -> R19 (the summary and the first reason are cut to one line, and the summary stays on one line open)

**Stability of the two pins the implement stage ran once (QA).**
- R13 (the clock's rates) and R6 (the countdown ticks): the 3 s windows wait for a 1 s interval to fire after `setFixedTime`, and the slow tick is fired by `clock.runFor(60_000)`, whose next fire is at most 60 s of fake time away because the interval was created after the install. So the only wall-clock dependence is one 1 s interval inside a 3 s window. A temporary copy of the spec ran R6 four times, R13 four times and R11 three times in one `live sign-in` (all passed), and each of them passed once in each of the six other runs of the stack (the first, four mutation runs whose mutations leave their code alone, and the final one): ten greens for R6 and R13 and nine for R11, none red. Judged stable on this runner. If a loaded CI runner ever flakes them, widen the 3 s window; do not add retries.
- R11's `/state` route patch: `route.fetch()` and `fulfill({ response, json })` replace the body and its length together, the later `page.route` supersedes the earlier one, and `afterEach` unroutes; no flake in the nine runs.
- The temporary loops are not in the committed spec (restored, `shasum` equal to the copy taken before).

**QA commands (all green on the final tree).** Slot B (`ocutalon-slot-b`, build 154): `Test.Core.BridgeSink` 16, `Test.Data.Ownership` 18, no `zz` session, incident, check, event or warning left behind. `npm --prefix web test` 312, `npm --prefix web run lint`, `test-class-rules.sh`, `test-ci-config.sh`. Throwaway e2s28q: `build`; `live sign-in` 148 passed and 1 skipped (N11, by declaration), R1-R19 included; `shard lane-b` and `shard lane-b --reverse`, 37 classes each passed (`Test.Core.BridgeSink` 4.8 s forward and 4.5 s reverse); teardown left nothing. `test-boundaries.sh` fails its `paths` rule on `cycle-log-epic-2.md:227` (a local path in the lead's bookkeeping line, not in this story's files).

**Mutations observed in the code review (2026-10-23, Rule 19).** The server mutation ran on slot B (`ocutalon-slot-b`, build 154) and the page mutation on a rebuilt bundle in `live sign-in` (tag e2s28r). Each was restored byte-identical (`shasum` before and after, `git diff --stat` unchanged).
- mutation (AC "Until Stories 3.4 and 3.5"): `Approved` reads the request's Ref from the payload member `requestRef` in place of HostSink's `{ref}` (`RefPayload`), the shape Lane A's emitters send -> `Test.Core.BridgeSink` 8 of 16 red: `TestApprovalEventsPublishTheRequest` ("approval.raised publishes one event"), plus `TestApprovalOwnersThatPublishNothing`, `TestInstanceApprovalReachesEveryWatcher`, `TestFailedWatcherReadIsLoud`, `TestAFailedRecipientReadDoesNotStopTheOthers`, `TestOnlineDemoStillPublishesASessionsOwnRequest`, `TestApprovalNeverWaitsMoreThanASecond` and `TestNeverFailsItsCaller`. So the approval tests drive `OnEvent` with exactly the contract's payload.
- mutation (AC Decision rows, the chip's meaning): the decision row's button loses `aria-describedby` -> R8 alone red ("described by its outcome's meaning": expected "OcuTalon took or requested an action", received ""); 147 passed, 1 failed.

**Code-review changes to the pinning tests.**
- R5, R8 and R10 now fix the page clock at 12:30 on the run's date, and `today()` reads one date per run. Their assertions are unchanged, and their recorded mutations (the check title, the view's sort, `aria-expanded`) do not depend on the date, so those lines stand.
- R6 seeds and fixes the clock on the day after the run's date, so its reminder is due in the future of the stack's clock. Its recorded mutation (the clock never ticks) stands.
- R8 also asserts each row's accessible description (the mutation above).
- R11 sets the seam inside its `try`.

**Code-review commands (all green on the final tree).**
- Slot B: `Test.Core.BridgeSink` 16 of 16.
- Web: `npm --prefix web test` 312, `npm --prefix web run lint`, `test-web-build.sh`, `test-class-rules.sh`, `test-boundaries.sh`.
- Throwaway e2s28r: `build`, then `live sign-in` 148 passed and 1 skipped (N11, by declaration), R1-R19 included; `teardown` left nothing.

**Shared surfaces:**
- The page's DOM. The rail now renders:
  - headings "{label} (n)" with a hidden "{label}, n" (frame.spec F1 `:77`);
  - decision summaries, chips and reasons, so any page-wide locator that meant the chat must look in `main` (notice.spec N3 `:143,149-150`, and the sweep);
  - reminder texts, so the reminders `live.spec` L2, L4 and L10 publish now show as rows; L5's four skeleton groups don't change.
- BridgeSink's approval behaviour (`Test.Core.BridgeSink`'s comment, `TestBadPayloadsPublishNothing`, `TestNeverFailsItsCaller`).
- `Session.Recipients`, whose trailing `sc` leaves `Test.Contract.Ac`'s prefix unchanged, `Ownership.Watchers` (a trailing `sc`) and the new `Ownership.ApprovalIncident`.
- `Fixture.Approval`, `Check` and `Reminder` (a trailing `fields`, defaults unchanged).
- `fixtureUser`'s kinds; the users and labels of `test-sign-in.sh`.
- `sinkEvent`'s return value and owner argument; `publishReminder`'s optional fields; `cleanFixtureRows` moves to `iris.ts`.
- The demo path's floor count, from 2 to 3.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` methods make their rows through `Fixture` and remove them with `Fixture.Clean(refs)`, and restore `onlineDemo`;
- `rail.spec` seeds and cleans its own run-stamped rows on its own user, asserts only its own refs and counts on a page loaded after its own seeding, and restores the Telegram seam in `finally`.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Plan summary.** The spec is written in full and checked against the READY FOR DEVELOPMENT standard.
- **Scope:**
  - BridgeSink's `approval` events, to the owner or to each watcher of an `instance` incident;
  - DW-68's status-reporting cross-owner reads, and the loud failure;
  - the rail's five sections, live counts, rows, empty texts and hints;
  - page day words and the countdown;
  - the decision disclosure and the Telegram card;
  - the focus rule;
  - the R1-R12 browser spec and the REL-2 page-step floor test.
- **For the lead:**
  - **No split** (Decided 1).
  - **DW-68 is addressed**, and its REST-path residual is recommended for Story 6.2 (Ledger, veto item 4).
  - **Four veto-window items** are listed in Design Notes.
  - **Spine notes** cover AD-31/AD-4 and the "Live events" convention.
  - **No footprint extension**: every file is in the epic footprint.
  - **No Task 0**: nothing in this story depends on unmeasured platform behaviour. The REST-path read failure is labelled inference, and nothing in this tree runs it.

**Implementation and review (2026-10-23).**
- **Summary of the change.**
  - Server:
    - `BridgeSink` publishes an `approval` event for each of the five `approval.*` types, to the owning session, or for an `instance` incident's request to each session `Session.Recipients` returns; each recipient reads the row through `Ownership.Approval`.
    - A failed cross-owner read logs one `ERRORRECIPIENTS` warning and publishes nothing; nobody watching logs nothing (DW-68).
    - `Ownership.Watchers` and `Session.Recipients` gain a trailing `sc`; `Ownership.ApprovalIncident` is new. Both reads are checked prepares, and `ALLOW_UNCHECKED` is unchanged.
  - Page:
    - `app-status-rail` renders the five sections with live counts, rows, empty texts and hints; `app-decision-row` and `app-telegram-card` are its parts; `main-page` renders the rail once loaded, 320px from 1440px.
    - `page-time` gains `pageWhen` and `countdownText`; `decision-strip` exports `fallbackSentence`; the focus rule sends focus from a leaving row to its section heading.
  - Tests: R1-R13 (R13 added in review), the REL-2 floor test, `rail-view.test.mjs`, the `page-time` and `page-safety` extensions, and the `%UnitTest` cases for BridgeSink, Recipients and Ownership.
- **Files changed.**
  - `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`: the approval path, its seams and the class comment.
  - `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`, `Data/Session.cls`: `Watchers` and `Recipients` report their status; `ApprovalIncident`.
  - `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls`, `BridgeSinkProbe.cls`, `BridgeSinkRefusedProbe.cls` (new), `Test/Data/Fixture.cls`, `Ownership.cls`, `Session.cls`: the DW-68 and approval cases, the trailing `fields` and `SetTelegramIncluded`.
  - `web/src/app/rail/` (new): `rail-view.ts`, `status-rail.ts`, `decision-row.ts`, `telegram-card/telegram-card.ts`.
  - `web/src/app/main-page/main-page.ts`, `chat/page-time.ts`, `chat/decision-strip.ts`: the rail frame, the time words, the shared fallback sentence.
  - `web/e2e/rail/rail.spec.ts` (new), `web/e2e/support/iris.ts`, `frame/frame.spec.ts`, `chat/notice.spec.ts`, `session/session.spec.ts`, `live/live.spec.ts`, `demo-path/01-page.spec.ts`: the browser cases and their helpers.
  - `web/scripts/rail-view.test.mjs` (new), `page-time.test.mjs`, `page-safety.test.mjs`, `playwright-projects.test.mjs`, `docker/tests/test-sign-in.sh`: the Node tests and the `ZzRail` fixture user.
- **Review findings.** 33 findings: high 0, medium 9, low 18, false 6.
  - **Patches (13 rows, 8 root causes):**
    - R2 and R6 depended on the wall clock near midnight UTC (now anchored on noon UTC).
    - The clock's two rates were unpinned (R13).
    - The decision meta line overflowed the rail for the long date forms (`flex-wrap`, pinned by R8).
    - The failed-state rail was unasserted (L7).
    - The Telegram `rejected` and `on` states were unpinned (R11).
    - The `ERRORFAILED` warning named neither the request nor the recipient, and its branch was untested (new `TestAFailedRecipientReadDoesNotStopTheOthers`).
    - The class comment lost the `eval` and `instance` sentence for `decision.recorded` and `turn.step`.
    - Smaller: `seedTurns` ignored `recordedAt`, the floor test's doc comment was garbled, and the safety mutation line now names R12.
  - **Deferred (1 entry, 3 sightings):** the failing branches of `Ownership.Watchers`, `Ownership.ApprovalIncident` and the status pass-through of `Session.Recipients` are run by no test (frontmatter `deferred:`). The failure cannot be induced on a slot or in `%UnitTest`; Story 6.2's REST answer path, run as a privilege-limited user, is where it first can be.
  - **Rejected (reason in the triage log):** a per-recipient lock wait (the spec's "each stream's lock"); `sinkEvent` returning the last Seq (the spec's design); a failed row fetch after a good execute (unlikely, untestable); `RefIndexOpen`'s status (a pre-existing line); `seedDecisions` leaking rows on a failed save; the empty Telegram section for state `on` (Story 12.3's); mutation lines per sub-assertion (Rule 19 asks one per AC); R8 and R5 staying green under the view mutations (pinned by R9 and `rail-view.test.mjs`); R7's notice row; F1's clean README account; and six intent-alignment descriptions that claim no defect.
- **Follow-up review recommendation: true.**
  - Four medium entries were patched: the midnight anchoring, the clock rates, the meta wrap and the failed-state rail.
  - The unverified risk: R13's 3 s tick windows on Playwright's page clock, and R11's route patch of `/state`, each ran green once on the throwaway (142 passed); their stability over repeated CI runs is unmeasured `(inference)`.
- **Verification performed (all green after the last patch).**
  - Slot B (`ocutalon-slot-b`, build 154):
    - Compile of `src/bridge` (33 classes) and `src/ocutalon` (212 classes): 0 errors.
    - `Test.Core.BridgeSink` (14), `Test.Data.Session` (4), `Test.Data.Ownership` (18) and the regression classes `Test.Core.WebChatOut`, `Test.Core.Routing`, `Test.Web.Api`, `Test.Live.Payloads`, `Test.Contract.Ac`, `Test.Data.Delivery`: all passed; no fixture row, event or warning left behind.
  - Web:
    - `npm --prefix web test` 311 passed, `run lint`, the `payloads`, `catalog` and `tokens` `--check` runs and `test-web-build.sh`: exit 0.
    - `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `ci/checks.sh`: exit 0.
  - Throwaway tag e2s28i:
    - `live sign-in`: 142 passed, 1 skipped (N11, by declaration), R1-R13 included.
    - `live demo-path`: `floor 3 of 3 passed`.
    - `shard lane-b` (37 classes) and `shard lane-b --reverse` (37), `shard lane-a` (9): every class passed.
    - Teardown left nothing.
  - Mutations: 25 from the implement pass and 7 from the review pass, each red and restored byte-identical (lines in `## Verification`).
- **Residual risks.**
  - The initial bundle is 503.22 kB against the 500 kB warning budget (485.9 kB before; the error limit is 1 MB). It is a build warning only; raising or keeping the budget is the lead's call.
  - The real failure of the cross-owner reads is unpinned (the deferred entry).
  - Docker Desktop restarted once during verification (all containers restarted, slot B included); the runs were repeated after it came back, with nothing started by this session left running.
  - Another runner held the throwaway lock for about 20 minutes; the pieces were run with `OCUTALON_LOCK_SLEEP_MIN=2` and `OCUTALON_LOCK_SLEEP_MAX=5`, which the lock script documents.
