---
title: 'Story 2.10: Show status banners for a missing key or a stalled heartbeat'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: 'eb1412c51bdcef0441b4244ff227d33e9a89089e'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: 'After Epic 1 merges, /state may compute noModelKey as off on a start with no key: Lane A''s Keys.Status cannot read the Config Store entry in an /ocutalon/api request and then counts the key as present'
    evidence: 'OCT-epic1 Bridge/Keys.cls Present: when ConfigStore.Details fails, present = %ConfigStore.Configuration.Exists(fqn), which adds a temporary role and answers 1. irislib %SYS/ConfigStore/Configuration.cls Get :222 calls CheckPermission(fqn,"READ"), which needs %Admin_ConfigStore:USE or the entry''s ReadResource (default %Admin_ConfigStore, :92) and audits each refusal (:1262). The API application grants only %DB_OCUTALON_CODE, _DATA and _PRIVATE (Install/Step/Web.cls :35). So in the request each runner reads as present, and three refusals are audited per /state. Budget.State''s Usage SELECT (OCT-epic1 Budget.cls :129) also lacks the SQL grant there, so it logs a warning per call and counts 0 spent; the day''s capped mark still works. This is (inference) from the source; no runtime measurement was possible on this branch, because the stubs are still in place.'
    location: 'src/bridge/cls/OcuTalon/Bridge/Keys.cls (OCT-epic1); AD-20 Status reads'
    severity: 'high'
---

<intent-contract>

## Intent

**Problem:** The page has no status banners:
- `.banner-slot` (Story 2.1) is empty;
- `Live.Payload.Status.Active` answers `[]`;
- `StatusMonitor` is an Epic 0 stub.

So a user is never told:
- that OcuTalon has no model key;
- that today's cost limit stops the model;
- that the heartbeat has stalled and checks are late.

Banner times would also render as instance message times (DW-29).

**Approach:**
- **One server computation, `Live.Payload.Status`.** It turns the readings of Lane A's `Keys.Status` and `Budget.State` into `noModelKey` and `dailyCap`. `/state` calls it on read.
- **`StatusMonitor` becomes a 15-second polling service.** It publishes a `status` event on the instance stream when a computed condition changes.
- **A banner stack in `.banner-slot`.** It renders every condition of the closed catalog in the catalog's order, from the live store, with these behaviours:
  - verbatim texts from the generated `catalog.ts`;
  - page times;
  - closing for "Reset soon" and "Reconnecting" only;
  - announcements;
  - the focus rule.
- **The rail's check rows** read "Last run {time} (late)" while `heartbeatStalled` holds.

## Boundaries & Constraints

**Always:**
- **The computation: `OcuTalon.Live.Payload.Status` (AD-12, AD-20).**
  - `Parameter AGENTS = "TriageAgent,DiagnosisAgent,ChatAgent"`: the runner items whose keys `Keys.Status(agent)` reads (Lane A's decision 7 on Story 1.6).
  - `Readings(Output keys, Output budget)`:
    - `keys` is `{"TriageAgent": 0|1, "DiagnosisAgent": 0|1, "ChatAgent": 0|1}`, from `##class(OcuTalon.Bridge.Keys).Status(agent)`;
    - `budget` is `##class(OcuTalon.Bridge.Budget).State()`, called with no argument, or `{}` when it is not an object.

    It is the only place that calls the two bridge APIs.
  - `Computed(keys, budget)`: the conditions this build computes, as `Status` payload objects, in `CONDITIONS` order (`dailyCap`, then `noModelKey`).
    - **`noModelKey`** is active when any of the three agents reads 0 (Decided 2). It has no slots.
    - **`dailyCap`** is active when `budget.capped` is true. Its slots are `Cap` = `budget.cap` and `Time` = `budget.resetsAt`, the latter only when it is a UTC time.
    - An inactive condition carries no slots.
  - `Active(sessionRef)`: the active ones of `Computed(Readings())`, as JSON objects shaped like the payload's export. `sessionRef` is unused until Epic 16 adds `allowance`, and the doc says so.
  - `/state` keeps calling `Active` (`Web/Api.cls:293`, unchanged).
- **`OcuTalon.Core.StatusMonitor` (AD-12, AD-18, AD-33): the one publisher of `status`.**
  - It is an `Ens.InboundAdapter` service with `CallInterval` 15, and no longer carries `STUB`.
  - Each `OnProcessInput`:
    - reads through two private seams, `Readings` (it calls `Status.Readings`) and `Stream` (the instance stream);
    - takes `Status.Computed`;
    - compares each condition's exported JSON with the one it remembers in a multidimensional property.
  - **The first run after the job starts publishes nothing.** It only remembers the state (Decided 4).
  - **Each later change** publishes one full view, through `Live.Publish(stream, "status", payload)`, in `CONDITIONS` order.
  - **A publish that fails** is logged with `$$$LOGWARNING` and not remembered, so the next run tries it again.
  - `OnProcessInput` always returns OK, so the clean-start check finds no error row.
- **The production (Lane B's region only).** `Production.cls:53` becomes `PoolSize="1"` with `<Setting Target="Adapter" Name="CallInterval">15</Setting>`. `Test/Core/ProductionItems.cls:26` matches it: pool 1, stub 0, that setting.
- **The page's texts (AD-32, Conventions "Text OcuTalon sends").**
  - `web/scripts/catalog.mjs` lists:
    - the nine `banner.*` keys;
    - the actions the page renders: `bannerAction.installYourself`, `bannerAction.howToSetKey` and `bannerAction.setUpBot` (not `budgets`).
  - It accepts the slot types `time`, `count` and `cost` besides `fallbackReason`.
  - It emits `PAGE_SLOTS`, each listed key's slot types.
  - In `renderPageText`, a `fallbackReason` slot still maps to its reason text. Every other slot takes the caller's already formatted string, cleaned like any string slot, in one pass.
  - Any other slot type, or a `one` form, is still refused.
  - `catalog.ts` is regenerated, and stays printable ASCII.
- **The banner catalog: `web/src/app/banners/banner-view.ts` (new, framework-free).**

  | Id (`data-banner`) | Key | Variant / icon | Action | Closable |
  | --- | --- | --- | --- | --- |
  | `allowance` | `banner.allowance` | danger / `circle-alert` | Install it yourself → `README_URL` | no |
  | `dailyCap` (`onlineDemo` true) | `banner.dailyCap` | danger / `circle-alert` | Install it yourself → `README_URL` | no |
  | `unreachable` (page's own) | `banner.unreachable` | danger / `circle-alert` | none | no |
  | `noModelKey` | `banner.noModelKey` | warning / `triangle-alert` | How to set a key → `README_URL` | no |
  | `costCap` (`dailyCap`, `onlineDemo` false) | `banner.costCap` | warning / `triangle-alert` | none ("Budgets" waits for the settings page) | no |
  | `heartbeatStalled` | `banner.heartbeatStalled` | warning / `triangle-alert` | none | no |
  | `telegramPaused` | `banner.telegramPaused` | warning / `triangle-alert` | Set up a bot → `readmeSection(README_URL, TELEGRAM_ANCHOR)` | no |
  | `resetSoon` | `banner.resetSoon` | warning / `triangle-alert` | none | yes |
  | `reconnecting` (page's own) | `banner.reconnecting` | info / `info` | none | yes |

  - `bannersView(input, format)` takes the store's `status`, the page's own conditions (none until Story 2.11), `onlineDemo` and the closed records. It gives the shown banners in table order.
  - A banner's text is `renderPageText(key, slots)`, with these slots:
    - `{time}` = `pageTime(slot)`: the browser's zone and hour format, no suffix, never " ET" (DW-29);
    - `{cap}` = `formatCost`;
    - `{limit}` = digits.
  - A missing slot renders empty, and the banner still shows (Decided 15).
  - The closing rule:
    - a closed banner is remembered with its signature (id and slots);
    - it stays hidden while the condition holds with that signature;
    - it shows again when the slots change, or when the condition clears and starts again (the record is dropped on clear).
- **The stack: `web/src/app/banners/banner-stack.ts` (new), rendered inside `app.ts`'s `div.banner-slot`.**
  - **Each banner:**
    - full width, `--status-banner-<variant>-min-height` (44px) or more;
    - `--status-banner-<variant>-background`;
    - a 4px left accent and the icon, both in `--status-banner-<variant>-accent`;
    - the text in `--status-banner-<variant>-foreground`.
  - **The action** is an underlined link that opens a new tab and says so, as `telegram-card.ts:23-24` does: `target="_blank"`, `rel="noopener noreferrer"`, `external-link`, and a visually hidden " (opens in a new tab)".
  - **A closable banner** has an icon-only ghost button `x` named "Close".
  - **No banner is a live region.**
  - **Announcements.** Once the first snapshot has loaded, each banner that appears is announced once through `Announcer.announce(text)`, whether it came by an event or by a reloaded snapshot. The banners of the first snapshot are not announced (Decided 9).
  - **Focus.** Each banner takes focus with `tabindex="-1"`. When a banner that holds focus leaves (closed or cleared), focus moves, with no scroll, to the next banner, else the previous one, else `main.main`. `main.main` gains `tabindex="-1"` in `main-page.ts` (Decided 11). Nothing else moves focus.
- **The rail.** `RAIL_TEXTS.lastRunLate = 'Last run {when} (late)'`. While `store.status.heartbeatStalled?.active` is true, `checkRow` uses it in place of `lastRun`. The rest of the meta line is unchanged.
- **Tests (AD-22, Rule 19).**
  - **`%UnitTest` classes are slot-safe.** `StatusMonitor` is driven through a probe subclass that overrides `Readings` and `Stream`, a shadow instance as in `Test/Web/ApiProbe.cls:14-16`, and publishes on a private stream that the class removes.
  - **Browser specs sign in as the new fixture user `ZzBanners`** (`OcuTalonUser`). They publish fixture `status` payloads through `Live.Publish` on that user's own session stream only (Decided 5). They clear every condition they turn on, in `finally`.

**Never:**
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**`, `Data/{StatusMark,Time,Reminder}.cls`, `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`.
- **Out of scope here, each with its producer's story:**
  - `heartbeatStalled` from `StatusMark` (8.2);
  - `telegramPaused` (12.x);
  - `allowance` and `resetSoon` (16.x);
  - the reconnecting and unreachable states (2.11);
  - "Budgets" and the step-2 no-key text (step 2).
- **Never add:**
  - a `/state` or `/events` key, an event type, or a stored property, table or global;
  - a role or grant, an unchecked prepare, an `Ens` table read in a request, or a dependency;
  - a test-only global read by product code;
  - public text beyond the AC and UX texts (Decided 8).
- **Never publish** a fixture or test event on the instance stream (Story 2.2's Decided 13). StatusMonitor's tests use a private stream.
- **Never render a banner on the server,** and never show an instance-zone time or " ET" in a banner.
- **Never run on slot B:**
  - `Test.Core.ThreadProduction`, `Test.Core.RoutingProduction`, `Test.Core.ConversationProduction` and `Test.Core.CommandsInProduction`;
  - `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` and `Test.Demo.Production`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No key, snapshot | `Keys.Status` 0 for one or more runners (the Epic 0 stub answers 0; a CI start has no key) | `/state` `status` holds `{"condition":"noModelKey","active":true}`. On load, the warning banner shows with the exact text and "How to set a key (opens in a new tab)" → `README_URL`, has no close and is not announced | All three present: no `noModelKey` in `status`, no banner |
| Local cost cap | `Budget.State` `{capped: true, cap: 20, resetsAt: T}` (fixture readings; on the page, a fixture event) | `dailyCap` `{cap: 20, time: T}`. The warning reads "OcuTalon has reached today's cost limit of $20.00. Decisions use fixed rules until {pageTime(T)}.", with no action. The composer stays usable | `capped` false: not in `status`, and the inactive event carries no slots |
| Online-demo cap | The same, `onlineDemo` true | The danger banner reads "The online demo has used today's model allowance. Decisions use fixed rules until {pageTime(T)}.", with "Install it yourself" | — |
| Heartbeat stalled | A `heartbeatStalled` `{time: T}` event or snapshot entry; a check with `lastRunAt` | The warning text with `{pageTime(T)}`, no action. The check row reads "Last run hh:mm (late) · …". Inactive: the banner and "(late)" leave within one live update | — |
| StatusMonitor runs | The first run, then a changed reading, then the same again | The first run publishes nothing. The change publishes one full view per changed condition on the stream. The same again publishes nothing | A failed publish: a warning, nothing remembered, published at the next run |
| Stack order | `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused` and `resetSoon` active (B5 publishes all six, so it does not depend on the stack's key) | Local: `allowance`, `noModelKey`, `costCap`, `heartbeatStalled`, `telegramPaused`, `resetSoon`. Online demo: `dailyCap` second | An unknown condition: ignored |
| Close | Close pressed on Reset soon | It leaves, and stays away while the condition holds with the same slots. Clear-then-active, or changed slots: it returns and is announced | Unclosable banners have no Close |
| Page time (DW-29) | Browser in Asia/Kolkata, instance UTC, `onlineDemo` true, `time` 2026-10-23T12:00:00Z | "…until 17:30." with no zone name and no " ET" | An unreadable time: empty slot, and the banner still shows |
| Focus | A banner's link or Close has focus, and the banner leaves | Focus moves to the next banner, else the previous one, else `main.main` | — |
| No-key start (Story 1.6) | `Decide` still carries `STUB` | Skipped: "Story 1.6 turns this on" | Built: the banner shows on load from the real `/state`, and a posted message's reply reads "I couldn't answer that: no model key is set. Nothing was changed." |

</intent-contract>

## Code Map

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls:1-24`:
  - `CONDITIONS` `:6`;
  - the properties `:9-15`;
  - `Active` `:17-22`, the stub that answers `[]`.
- `Live/Payload/Part/StatusSlots.cls:6-12`: `Limit`, `Cap` (`SCALE` 6), `Time`. Unchanged.
- `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls:1-15`: the stub, with `STUB` at `:8` and the handler at `:10-13`.
- `src/ocutalon/cls/OcuTalon/Production.cls:53`: the `StatusMonitor` item. Lane B's region is `:44-69`, and Lane A's adapter-setting rows (`:24-26`) are the pattern.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:26`: the oracle row. It is read by `Test/Install/Production.cls` (contended, read only: class, pool, enabled, settings and the `STUB` agreement, `:121-157`) and by `docker/tests/lib-live.sh:612-629`'s `check_production` (a pooled item must be alive).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:258-297`: `StateBody`, which calls `Status.Active` at `:293`. No change.
- Read only:
  - `src/bridge/cls/OcuTalon/Bridge/Keys.cls:6-9` (the stub answers 0) and `Budget.cls:8-11` (`{"spent":0,"cap":0,"capped":false,"resetsAt":""}`). On OCT-epic1, `Status(agent)` takes the runner item's name, and `State(now = "", Output faults)` keeps the no-argument call.
  - `Live/Publish.cls:13` (`INSTANCE`) and `:52` (`Publish(stream, type, payload, .seq, lockWait)`).
  - `Live/Event.cls:34` (`Since`).
  - `Web/Api.cls:434-452` (`EventsBody(session, after, afterInstance, instanceStream)`).

**Server tests (Lane B, edit or new)**
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - the doc `:1-19`, which says "Nothing is published on the instance stream";
  - `TestStateBody` `:92-150`, which pins `status` as empty at `:137-138`;
  - `:267`;
  - the private-stream pattern: `zzapistateinstance<n>`, cleaned in `Clean`.
- `Test/Web/ApiProbe.cls:14-16` and `Test/Core/WebChatInProbe.cls`: the probe pattern (`Ens.Host.GetShadowInstance("class||<probe>")`).
- `Test/Live/Payloads.cls:94` pins `CONDITIONS` (unchanged).
- `Test/Contract/Ac.cls:320-321` pins `Budget.State()` and `Keys.Status(agent)`, unchanged.

**Web (Lane B, edit or new)**
- `web/scripts/catalog.mjs`:
  - the header `:1-21`;
  - `LISTED_KEYS` `:34` and `SLOT_TYPE` `:37`;
  - `pageText` `:94-111`;
  - `RENDERER` `:128-156`;
  - `generate` `:159-208`.
- `web/src/app/msg/catalog.ts`: generated; do not edit.
- The Core catalog's banner keys: `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:267-343`.
- `web/src/app/app.ts:16-28`: the template with `div.banner-slot`, and the flex column at `100dvh`, so a banner shrinks the routed page and never scrolls the page at 1280×720.
- `web/src/app/live/live-state.ts:55` (`snapshot`, with `onlineDemo`) and `:61` (`store`).
- `web/src/app/live/live-store.ts:50,79,121,172-173`: `status`, keyed by `condition`, from the snapshot and from events on either stream.
- `web/src/app/chat/page-time.ts:27-33`: `pageTime`.
- `web/src/app/chat/decision-view.ts:72-85`: `formatCost`.
- `web/src/app/links.ts:5`: `README_URL`.
- `web/src/app/rail/rail-view.ts`:
  - `RAIL_TEXTS` `:22-47` (`lastRun` `:41`), `TELEGRAM_ANCHOR` `:50`, `RailFormat` `:59-72`;
  - `readmeSection` `:152-155`, `checkRow` `:190-209` and `railView` `:294-330`.
- `web/src/app/rail/status-rail.ts`: `formatAt` `:30-42`, and the focus rule `:240-273` is the pattern.
- `web/src/app/rail/telegram-card/telegram-card.ts:23-24`: the new-tab link.
- `web/src/app/shared/announcer.ts:6-13`.
- `web/src/app/shared/inline-notice.ts`: not extended (Rule 2 below).
- `web/src/app/icon/icon.ts:4-24`: `circle-alert`, `triangle-alert`, `info`, `x` and `external-link`.
- `web/src/styles/tokens.css`: banner tokens `:117`, `:158-169`, dark `:614-622` and `:837-845`.
- `web/src/app/main-page/main-page.ts:54-60`: `main.main`.

**Web tests**
- `web/scripts/catalog.test.mjs` (the real tree `:27-70`, the fixtures and refusals), `rail-view.test.mjs` and `live-store.test.mjs:45,112-136` (status from either stream, unchanged).
- `web/e2e/support/iris.ts`:
  - `FixtureKind` and `fixtureUser` `:15-20`;
  - `irisScript` and `chk` `:42-63`;
  - `quoted` `:115`;
  - `publishCheck` `:687-710` is the pattern for `publishStatus`;
  - `seedCheck` `:662`, `seedDecision` `:442`, `sinkEvent` `:370` and `cleanFixtureRows` `:575`.
- `web/e2e/support/api.ts:24` (`changeSnapshot`); `web/e2e/support/page.ts` (`plain`, `tokenColor`).
- `web/e2e/live/live.spec.ts:69-88`: the announcement recorder, which moves to `support/page.ts`.
- `web/e2e/rail/rail.spec.ts`:
  - the header `:22-31`;
  - `APPLIED_MS` and `ONE_UPDATE_MS` `:46-50`, the "within one live update" pattern;
  - R11 `:474`, which asserts that `.banner-slot` is empty.
- `web/e2e/api/api.spec.ts:136`, which pins `status` as `[]` (the keys at `:117` are unchanged).
- `web/e2e/frame/frame.spec.ts`: F1 `:62-91` (DOM order with `.banner-slot`), F7 `:372-411` (header Tab stops only) and F9 `:498`.
- `web/e2e/demo-path/not-built.ts:11-15`: the skip text "Story <n.m> turns this on".
- `docker/tests/test-sign-in.sh`:
  - header `:1-45`;
  - users `:57-77`, created in the loop at `:141`;
  - the instance seed, asserted as `instance-seq|1`, at `:156-176` (`:172`);
  - redaction `:188`, env `:189-224`;
  - labels `:228` and `:234`.
- `docker/tests/lib-live.sh:632-641`: `check_no_key`.

## Tasks & Acceptance

**Execution:** No Task 0 is needed. `Test/Install/Production.cls:121-157` already drives shadow instances of item classes, including the Telegram stub's adapter service, so a shadow instance of an `Ens.InboundAdapter` service is known to work. The bridge's request-context behaviour can't be measured here (see Design Notes, cross-lane risk).

1. `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls`: add `AGENTS`, `Readings`, `Computed` and the real `Active`, as Boundaries says, each documented. This is the one computation (AD-12, AD-20).
2. `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls`: build the service as Boundaries says. Drop `STUB`, set `ADAPTER`, add the remembered state, the `Readings` and `Stream` seams and `OnProcessInput`. Replace the class doc. This is the publisher.
3. `src/ocutalon/cls/OcuTalon/Production.cls:53` and `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:26`: `PoolSize` 1, `CallInterval` 15, stub 0. This runs it every 15 s.
4. `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls` (new): the fixture-reading tests.
   - `Computed`:
     - each of the three agents at 0 alone gives `noModelKey` active, and all at 1 give it inactive;
     - `capped` true gives `dailyCap` with `cap` and `time`, and `capped` false gives it with no slots;
     - a `resetsAt` that is not UTC gives no `time`;
     - the order is the `CONDITIONS` order.
   - `Active`: only the active ones, as JSON objects.
   - `Readings`: equal to direct calls of `Keys.Status` for each `AGENTS` item and of `Budget.State()`.
5. `src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitorProbe.cls` and `Test/Core/StatusMonitor.cls` (new). The probe takes its readings and stream from properties. The tests:
   - the first run publishes nothing;
   - a change publishes exactly the changed conditions' full views, in order;
   - an unchanged run publishes nothing;
   - a slot change publishes, and a clear publishes `active` false with no slots;
   - a publish refused inside an open transaction (`TSTART`, run, `TROLLBACK`) returns OK and is published at the next run;
   - the published events are served by `Web.Api.EventsBody` with the private stream as the instance stream (the consumer). This is an Integration AC.

   The stream's events and counter are removed before and after.
6. `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`: `TestStateBody` (`:137-138`) asserts that `status` equals `Status.Active(session.Ref)`, member for member, and the class doc follows. This replaces Story 2.2's pin.
7. `web/scripts/catalog.mjs` and `web/src/app/msg/catalog.ts`: the listed keys, the slot types and `PAGE_SLOTS`, as Boundaries says. Update the header comment and run `npm --prefix web run catalog`. This gives the page its banner texts.
8. `web/src/app/banners/banner-view.ts` (new): the banner catalog, `bannersView`, the closing rule and `BANNER_TEXTS` (`close: 'Close'`; the new-tab words reuse `CHAT_TEXTS.opensInNewTab`). It is the pure model.
9. `web/src/app/banners/banner-stack.ts` (new) and `web/src/app/app.ts`: the component, inside `div.banner-slot`, as Boundaries says (style, close, announce, focus). `web/src/app/main-page/main-page.ts`: `tabindex="-1"` on `main.main`. These render the stack.
10. `web/src/app/rail/rail-view.ts`: `lastRunLate`, and `checkRow` reads the store's `heartbeatStalled`. This adds the "(late)" marks.
11. Node tests:
    - `web/scripts/banner-view.test.mjs` (new):
      - all nine ids and the table's columns;
      - the exact texts with slots;
      - the local and online orders;
      - the closing rule (hidden while the same, back on a changed slot and on clear-then-active);
      - an inactive or unknown condition shows nothing;
      - a missing slot renders empty but still shows;
      - `{time}` is `pageTime` in a named zone with no suffix, on the online demo too;
      - only the nine banners exist (UX-DR100);
      - ASCII strings.
    - `catalog.test.mjs`:
      - the real tree holds the 12 listed banner and action keys with their `PAGE_SLOTS`;
      - a fixture renders `time`, `cost` and `count` slots as given;
      - a `noun` slot is still refused.
    - `rail-view.test.mjs`: "(late)" only while `heartbeatStalled` is active.
12. `web/e2e/support/iris.ts` and `web/e2e/support/page.ts` (Rule 2):
    - `FixtureKind` gains `'BANNERS'`.
    - `publishStatus(user, {condition, active, slots})` publishes a `Live.Payload.Status` on the user's session stream and returns its Seq.
    - `decideIsStub()` reads `+$Parameter("OcuTalon.Bridge.Process.Decide","STUB")`.
    - The announcement recorder moves from `live.spec.ts:69-88` to `support/page.ts`, and `live.spec.ts` imports it.
13. `web/e2e/banners/banners.spec.ts` (new; chromium; user `BANNERS`; a header comment like `rail.spec`'s). The cases, against real HTTP:
    - **B1:** the snapshot's no-key banner on load.
      - The text, variant tokens, icon, height, width, under the header, the link with its href, target and rel, no Close, no live-region attribute, and not announced.
      - A seeded `decide` fallback with `no_key` shows the flag and "No model key is set." on its rail row.
    - **B2:** heartbeat stalled by event.
      - The banner within one live update, its text with page time and no action.
      - A seeded check's row reads "Last run hh:mm (late)".
      - It is announced once.
      - Clearing it removes the banner and "(late)" within one live update.
    - **B3:** the local cost cap.
      - The warning text with "$20.00" and no action.
      - The composer stays usable: it takes text, and Send is not `aria-disabled`.
      - A `daily_cap` fallback row reads "Today's cost limit has been reached."
    - **B4:** the online-demo cap from the snapshot (DW-29).
      - `timezoneId` Asia/Kolkata, and `/state` routed with `onlineDemo` true and a `dailyCap` entry.
      - The danger banner with "until 17:30." (no " ET", no zone name), `circle-alert`, and "Install it yourself" → `README_URL`.
    - **B5:** the stack.
      - Six events give the local order of the matrix, each with its variant and action ("Set up a bot" → `…#telegram`). The case publishes `noModelKey` itself, so the order holds whatever the stack's key state.
      - Only Reset soon has a Close.
      - Close removes it. Focus moves to the banner before it (Bot in use), because no banner follows Reset soon. It stays closed while the condition holds. Clear-then-active brings it back, announced.
      - Focus moves to `main.main` when the last focused banner leaves (the case clears every condition, `noModelKey` included, on its own session stream).
    - **B6:** the no-key start (FR-38).
      - While `decideIsStub()` is 1: `test.skip(true, 'Story 1.6 turns this on')`.
      - Otherwise: B1's banner from the real `/state`, and a posted message's reply reads "I couldn't answer that: no model key is set. Nothing was changed." with the fallback flag.
14. `docker/tests/test-sign-in.sh`:
    - add `ZzBanners` (`OcuTalonUser`): its password, the user loop, redaction and `OCUTALON_BANNERS_USER` / `_PASSWORD`;
    - call `check_no_key "sign-in"` after the start;
    - add "Story 2.10's B1 to B6" in the header and the PASS and FAIL labels.
15. **The sweep (shared surfaces).**
    - `api.spec.ts:136`: `status` equals `[{condition: 'noModelKey', active: true}]`, the computed no-key condition of this stack.
    - `rail.spec.ts:474`: "no Telegram banner": no `[data-banner="telegramPaused"]`.
    - Search `web/e2e/` for assertions that the always-present no-key banner changes, and update each one: the slot being empty, link, focusable or tab-stop counts after the header, and heights of the main page at 1280×720.

**Acceptance Criteria:**
- **The computation (AD-12, AD-20).**
  - **Given** the readings of `Keys.Status` for the three runner items and `Budget.State()`,
  - **when** `/state` serves or `StatusMonitor` runs every 15 s,
  - **then:**
    - both use `Status.Computed`;
    - `/state`'s `status` holds the active conditions;
    - `StatusMonitor` publishes a full `status` view on the instance stream for each condition that changed since its last run, and nothing on its first run.

  Tests: `Test.Live.Status`, `Test.Core.StatusMonitor`, `Test.Web.Api`, B1.
- **Banners (UX-DR34, UX-DR116).**
  - **Given** a condition starts or ends, by the snapshot or a `status` event,
  - **when** the page applies it,
  - **then:**
    - its banner appears or clears within one live update, full width, at least 44px tall, with its accent, icon and at most one underlined action;
    - it is announced when it appears after the first snapshot;
    - banners stack in the catalog's order;
    - only Reset soon and Reconnecting can be closed, and a closed banner returns when its condition gets worse;
    - banner times are page times.

  Tests: B2, B4, B5, `banner-view.test.mjs`.
- **No model key (FR-38, UX-DR98, UX-DR111).**
  - **Given** a start with no model key,
  - **when** the page loads,
  - **then** the unclosable warning banner reads the AC's text, with "How to set a key" to the README, and decisions show the fallback flag with "no model key is set".
  - **And** B6 makes the no-key CI start check. It turns itself on when Story 1.6 merges.

  Tests: B1, B6.
- **Heartbeat stalled (FR-32, UX-DR53, UX-DR99, UX-DR123).**
  - **Given** `heartbeatStalled` with its last-tick time,
  - **when** the page shows it,
  - **then** the unclosable warning reads the AC's text, with no action and the time as a page time, and check rows read "Last run {time} (late)". Both leave within one live update of the clear.

  Tests: B2, `rail-view.test.mjs`.
- **Cost cap (FR-4, UX-DR97, UX-DR100, UX-DR111).**
  - **Given** today's cost cap is reached,
  - **when** the page shows `dailyCap`,
  - **then:**
    - on the online demo, the danger banner with "Install it yourself";
    - otherwise, the warning naming `{cap}`, with no "Budgets";
    - the composer stays usable, and decisions read "today's cost limit has been reached";
    - no other page state exists for a starting install or a pre-launch demo.

  Tests: B3, B4, `banner-view.test.mjs`.
- **DW-29.**
  - **Given** a banner with a `{time}` slot,
  - **when** the browser's zone differs from the instance's, on the online demo too,
  - **then** the time is the browser's page time, unsuffixed.

  Tests: B4, `banner-view.test.mjs`.

## Spec Change Log

## Review Triage Log

### 2026-10-23 — Review pass
- verdicts: 31 findings — high 0, medium 5, low 20, false 4, maybe-false 2
- findings:
  - `[medium]` `[patch]` Blind Hunter: `catalog.mjs` reason entries pass the widened `SLOT_TYPES`, nothing fills a time, count or cost slot in a reason text, and the 'reason-slot' test was edited from `count` to `noun` — a guard weakened; fixed: `generate` refuses any `fallbackReason.*` slot that is not `fallbackReason` (`REASON_SLOT_TYPE`), the `count` case is restored and `time` and `noun` cases added; mutation recorded
  - `[false]` `[reject]` Blind Hunter: `Active` is not guarded, so a throwing `Keys.Status` or `Budget.State` fails `/state` — `Test.Web.Api` `TestStateFailsLoudly` pins that a failed read is an error and never an empty section, and `[]` would be a false all-clear
  - `[low]` `[reject]` Blind Hunter: `TestStateBody` compares `status` with a second call of `Active`, so it cannot see `StateBody` dropping `status` when no condition is active — the CI start has no key (`check_no_key`), so the expected array is not empty there, `api.spec` row 13 pins `[noModelKey]`, and the fix needs a readings argument on `Active` (public surface); reopen_if a gate runs `Test.Web.Api` on a stack with a key set and no cap
  - `[low]` `[reject]` Blind Hunter: `banner-stack.ts` builds the view list twice (`active`, `banners`) and `rail-view.ts` repeats banner-view's `holds` test — at most nine banners per store change, and the rail's one-line check reads the store's own shape; sharing it adds a rail to banner import for nothing observable
  - `[low]` `[patch]` Blind Hunter: the `banner-view.test.mjs` title "fewer digits below" contradicts its `$0.500` assertion — retitled "three below a dollar"
  - `[low]` `[reject]` Blind Hunter: a failed JSON export in `StatusMonitor` is logged as "could not publish" — the export of a payload the run just built does not fail (`wontfix-theoretical`; real only if a `Status` property gains a constraint a condition can break)
  - `[low]` `[reject]` Blind Hunter: a persistent failure logs the same warning every 15 s — the spec fixes "a publish that fails is logged and published at the next run" (`by-design`)
  - `[low]` `[patch]` Blind Hunter: `DailyCap` treats a number as a cap and a string as none, undocumented and untested — the doc now says so and `TestComputedDailyCap` pins 1, 0 and "true"; mutation recorded
  - `[false]` `[reject]` Edge Case Hunter: `Active` unguarded (same claim as the Blind Hunter's) — refuted by `TestStateFailsLoudly`, which pins that a failed read is an error
  - `[low]` `[reject]` Edge Case Hunter: a first run that skips a condition whose JSON export fails makes the next run publish it — export of a fresh payload does not fail (`wontfix-theoretical`), and a per-condition baseline would swallow the retry of a failed publish, so the run-wide first flag is right
  - `[low]` `[reject]` Edge Case Hunter: after a job restart with a page open, a changed state is not published and the page keeps a stale banner — the spec's Decided 4 names this residual (`by-design`)
  - `[maybe-false]` `[defer]` Edge Case Hunter: the silent first run in the job process may disagree with `/state` computed in the web process — the same root cause as the frontmatter `deferred` item (Lane A's `Keys.Status` in a request, DW-148); would settle it: a runtime measurement after Epic 1 merges (B1, B6, `api.spec` row 13); no new item
  - `[false]` `[reject]` Edge Case Hunter: an impossible `resetsAt` such as `2026-13-45T99:99:99Z` becomes a slot — `pageTime` answers "" for an unreadable time and the banner still shows (Decided 15, matrix "An unreadable time"), covered by `banner-view.test.mjs`
  - `[low]` `[reject]` Edge Case Hunter: a banner queued for announcement that clears before its turn is still announced — the queue gap is 150 ms per waiting banner, so the stale announcement is at most a fraction of a second old (`wontfix-theoretical`)
  - `[medium]` `[patch]` Edge Case Hunter: the generator accepts a time, count or cost slot in a `fallbackReason.*` text (same claim as the first Blind Hunter row) — fixed with it
  - `[low]` `[reject]` Edge Case Hunter: R11 no longer asserts an empty `.banner-slot` — Task 15 names the new assertion (no `[data-banner="telegramPaused"]`) because the no-key banner is always present (`by-design`)
  - `[low]` `[reject]` Edge Case Hunter: nothing computes `heartbeatStalled` — the intent excludes it: "heartbeatStalled from StatusMark (8.2)" is out of scope here
  - `[medium]` `[patch]` Verification Gap: `StatusMonitor`'s own `Readings` and `Stream` bodies run in no test, so a wrong stream or an empty reading leaves every test green — fixed: `Test.Core.StatusMonitorSeamProbe` and `TestProductSeams` (the instance stream; keys and budget equal `Status.Readings`); two mutations recorded
  - `[low]` `[patch]` Verification Gap: `TestActive` has two assertions that cannot fail (`ActiveOf` against itself, and `[` in an array's JSON) — the first removed, the second replaced by a class check of the answer
  - `[low]` `[reject]` Verification Gap: `TestStateBody` and `TestActive` depend on the Keys stub for a non-empty expectation (same root cause as the second Blind Hunter row) — see that row
  - `[low]` `[patch]` Verification Gap: `DailyCap`'s number and string arms have no test (same claim as the Blind Hunter's) — fixed with it
  - `[medium]` `[patch]` Verification Gap: the 'reason-slot' catalog test was edited so that the generator's refusal is no longer pinned (same claim as the first row) — fixed with it
  - `[low]` `[reject]` Verification Gap: B6, the only real no-key reply check, is skipped while `Decide` has `STUB` — the matrix row names the skip, and B6 turns itself on when Epic 1 merges (`by-design`)
  - `[low]` `[patch]` Verification Gap, Rule 19: B1, the look and action clause and the 'within one live update' wording had no demonstrated mutation at their browser tier — closed in this pass by one `live sign-in` run with three mutations, six cases red, lines written; the planned reds at the tiers above the cheapest one are not required (one demonstrated mutation per AC)
  - `[low]` `[reject]` Verification Gap: the second warning count in `TestRefusedPublishIsPublishedAtTheNextRun` stays at 1 only because `TROLLBACK` removes the first — a failure of that would be a false red, not a false green, and the class passes (`wontfix-theoretical`)
  - `[low]` `[reject]` Verification Gap: a failed JSON export is logged under the "could not publish" text and leaves a first-run condition unremembered (same claims as the Blind Hunter's and Edge Case Hunter's) — see those rows
  - `[false]` `[reject]` Intent Alignment: the diff implements the seam reading of the intent, and the live reading only on a stack of stubs — the intent's own tests clause prescribes probes, private streams and session-stream fixtures (Decided 5, 13), so the split is the specified one; no defect claimed
  - `[medium]` `[patch]` Intent Alignment: the real seam bodies run in no test and the path meets only at a fixture (same claim as the Verification Gap's seams row) — fixed with it
  - `[maybe-false]` `[defer]` Intent Alignment: `/state` runs under the web roles and the job under its own, and Epic 1's `Keys.Status` may count a key as present in a request — the frontmatter `deferred` item (DW-148) already records this; would settle it: a measurement after Epic 1 merges; no new item
  - `[low]` `[reject]` Intent Alignment: `ActiveOf` is a public method the contract does not list — it is the seam that lets the tests give `Active`'s filter fixture conditions; recorded as Decided 16
  - `[low]` `[reject]` Intent Alignment: a first run that throws leaves nothing remembered, so the next good run is silent — Decided 4 says the first run that reads only remembers (`by-design`)

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-12:**
  - the closed status catalog;
  - computed on read in `/state` and published by `StatusMonitor`;
  - full views through `Live.Publish` only after commit;
  - the page applies events idempotently and never moves focus because of one, except for the replacement rule.
- **AD-20:** status reads go only through `Budget.State()` and `Keys.Status(agent)`.
- **AD-18:** `StatusMonitor`'s `CallInterval` is 15 s, and the page shows times in the browser's zone. `StatusMark` is not read here, because Story 8.2 reads it.
- **AD-19:** the `onlineDemo` flag. Keys come only from the environment, and the banner names the variable, never a value.
- **AD-32:** producers never render, and the page renders from `catalog.ts`.
- **AD-33:** `StatusMonitor` is the one publisher of `status`.
- **AD-13:**
  - no new unchecked prepare, and no `Ens` table read in a request;
  - this story's request reads are the two bridge APIs, as AD-20 says.
- **AD-29:** Lane A is read only through the two Epic 0 APIs. The stubs answer as fixtures until Stories 1.4 and 1.6.
- **AD-22:** the tests.
- **AD-2:** `Live` may call the bridge, and the bridge calls nothing of OcuTalon's.
- **AD-5:** the state `StatusMonitor` remembers is not durable state.
- **Conventions:** Live events, Times, Text OcuTalon sends, README link, Angular, Tests, Production item names and Logging.

No AC contradicts an AD's Rule.

**Rule 5:** the "within one live update" of NFR-9 is measured as in `rail.spec`: wait until the page has applied the event's Seq, then expect the change within 1 s. No NFR is unmeasurable.

**Decided in-stage** (small, reversible, within the intent):
1. **The story is not split.** The server part is two classes, one production row and its oracle. The page part is one view module, one component and the generator's extension. That is the size of Story 2.13, which ran in one pass.
2. **`noModelKey` is on when any of the three agents has no key.** In release 1, every entry carries the same `@{env:ANTHROPIC_API_KEY}` placeholder, so "any" and "all" coincide. "Any" never hides a missing key. Step 2's per-provider keys revisit this with their own text.
3. **`dailyCap` follows `capped`** (a marked day or spent ≥ cap), with `cap` and `resetsAt` as its slots. An inactive condition carries no slots, so the midnight rollover of `resetsAt` publishes nothing.
4. **StatusMonitor's baseline is silent and held in memory.** Its first run publishes nothing.
   - **Why:** the snapshot is computed on read, and an IRIS restart ends the CSP sessions, so open pages reload. On a fresh stack nothing changes, so the instance stream keeps the counts that `test-sign-in.sh:172` (`instance-seq|1`) and `api.spec` rows 13 and 14 assert.
   - **The residual:** a production-only restart, with a page open, while a computed condition changed, is seen at the page's next reload.
5. **Browser specs publish fixture `status` payloads on their own session stream.** The page applies a `status` event from either stream alike (`live-store.ts:172-173`, and `live-store.test.mjs:112-136` pins the instance stream). Story 2.2's Decided 13 keeps specs off the instance stream. `StatusMonitor`'s own instance-stream publication is pinned by `Test.Core.StatusMonitor`, through `EventsBody` with a private stream as the instance stream.
6. **DW-29 is resolved in the browser.** The page formats the UTC slot with `pageTime`. No server path renders a banner key, so `Catalog.Render` is unchanged.
7. **Slot formats:** `{cap}` is `formatCost` (the UX's Formats rule, as the server's), and `{limit}` is digits.
8. **Links and text.**
   - "How to set a key" and "Install it yourself" open `README_URL`. The AC says "the README", and Story 10.2's link check covers that address; a section anchor would point at a section no story has written yet.
   - "Set up a bot" opens the README's `#telegram` section, as Story 12.7's AC says, and it only shows when Telegram runs.
   - Every action says " (opens in a new tab)", the pattern of the Telegram card and of About. The Close name "Close" is Story 2.1's banner-close precedent.
9. **Announcements:** a banner is announced when it appears after the first snapshot. The banners of the first snapshot are not announced, as the UX says of inline notices ("Announced only when it appears after page load"). So the no-key banner, present on every stack, adds no announcement to other specs.
10. **"Gets worse"** is a changed signature (the slots), or the condition clearing and starting again. Closed records live for the page's life only.
11. **Focus, when a focused banner leaves:** the next banner, else the previous one, else `main.main`. That is the UX's "nearest container", and `main` takes `tabindex="-1"` so that it can hold focus outside the tab order.
12. **B6's turn-on probe** is `Decide`'s `STUB` parameter. It is the project's built-or-not marker (Story 11.5's check). Story 1.3 removes it in Epic 1, together with Story 1.6, so B6 turns on when Epic 1 merges, with no edit. Until then it skips with the convention's text.
13. **The no-key banner shows on every stack of this branch**, because the Keys stub answers 0. After Story 1.6 it still shows on every CI stack, because CI starts with no key (`compose.throwaway.yml` resets `env_file`, and `check_no_key` holds). The specs are written to hold either way.
14. **`banner-view.ts` keeps the catalog as a table in code**, not in the generated module. Variants, icons, actions and closability are page presentation (DESIGN, EXPERIENCE). Only texts come from the catalog.
15. **A banner whose slot is missing or unreadable still shows**, with that slot empty. A warning is never dropped.
16. **Decided in implement:** `Status.ActiveOf(conditions)` is a public helper that `Active` calls. It is the seam that lets `Test.Live.Status` give `Active`'s filter fixture conditions on a slot whose bridge readings are stubs.
17. **Decided in implement:** `dailyCap` holds when `capped` is the JSON boolean true or a number other than 0. Lane A's `Budget.State` answers a JSON boolean; the number arm only tolerates an ObjectScript 1. Any other value is not a cap, and `Test.Live.Status` pins all three.
18. **Decided in review:** `Test.Core.StatusMonitorSeamProbe` is a subclass of `StatusMonitor` that keeps both private seams as the product has them and makes them callable, so `TestProductSeams` checks that the job publishes on the instance stream and reads `Status.Readings`. Nothing is published.
19. **Decided in review:** a `fallbackReason.*` text may declare only `fallbackReason` slots, as before this story. The page renders a reason text as it is, so a time, count or cost slot in one would show its placeholder.

**Cross-lane risk for the lead (route it, decide or escalate; not this story's to fix).** This is the frontmatter `deferred` item.
- **The risk:** after Epic 1 merges, Lane A's `Keys.Status` cannot read the Config Store entry in an `/ocutalon/api` request, and counts the key as present. So `/state` would compute `noModelKey` as off on a start with no key. Every page load would also audit three refusals, and `Budget.State` would log a warning per call, because the request has no SQL grant for `Usage`.
- **What catches it:** B6 (and B1 and `api.spec` row 13) turn red at the merge if it is real.
- **Remedies, each a veto item:**
  - (a) Lane A makes `Keys.Status` judge a key in a request without the Config Store privilege, which is security posture;
  - (b) amend AD-12 and AD-20, so that the snapshot takes the instance-wide conditions from `StatusMonitor`'s last computation in the production job, which adds a stored record and amends an AD.
- **Recommendation:** route (a) to Epic 1 before its merge.

**Veto-window items:** none. No stored data, role, grant or dependency changes. The production row changes pool size and adapter only, which is structure (AD-5). Decided 8 lists the only text that is not quoted verbatim.

**Integration ACs (Rule 1).**
- The page reads `/state`'s `status`, which `Status.Active` computes from the real Keys stub, and shows the no-key banner on load (B1, a real stack).
- The page reads `status` events through real polling and `Live.Publish`, shows and clears banners and the rail's "(late)" marks, and announces them (B2 to B5).
- `Web.Api.EventsBody` serves what `StatusMonitor` publishes (`Test.Core.StatusMonitor`, on the real `Live.Event` table).

**Consumed-by:**
- **2.11:** its reconnecting and unreachable states enter `bannersView` as the page's own conditions, and Reconnecting is closable.
- **2.12:** the accessibility floor tests the stack.
- **8.2:** it appends `heartbeatStalled` to `Status.Computed` (from `StatusMark`'s last tick), and its banner and "(late)" marks then appear from the real condition.
- **12.x:** it produces `telegramPaused`; "Set up a bot" opens `#telegram` (12.7).
- **16.x:** it produces `allowance`, `resetSoon` and the online demo's daily-cap message.
- **4.x:** it adds the guide's recompute to `StatusMonitor`'s run (AD-12), as its own entry.
- **10.2:** the README link check covers `README_URL`.
- **Step 2:** "Budgets" and the step-2 no-key text.

**Consumes:**
- 0.5: `Live.Payload.Status`, `StatusSlots` and `Live.Publish`;
- 0.9 and 2.5: the banner keys and `catalog.mjs`;
- 2.1: `.banner-slot`, `Icon`, the tokens, `Announcer` and `README_URL`;
- 2.2: `/state`'s `status`, `LiveState` and the store;
- 2.6: `formatCost` and the fallback reasons;
- 2.8: the rail's check rows;
- Epic 0: `Keys.Status` and `Budget.State`, real in 1.6 and 1.4.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `catalog.mjs` gains slot types, not a second generator.
- `bannersView` reuses `renderPageText`, `pageTime`, `formatCost`, `README_URL`, `readmeSection` and `CHAT_TEXTS.opensInNewTab`.
- The action link copies the Telegram card's new-tab pattern.
- `StatusMonitorProbe` follows `WebChatInProbe` and `ApiProbe`.
- `publishStatus` sits beside `publishCheck`.
- The announcement recorder moves to `support/page.ts`; it is not copied.
- The banner is a new component and does not extend `inline-notice.ts`. That notice has no accent bar, no action and no close, and sits in the flow, while a banner is full width with an accent, an action and an optional close; a shared base would carry two layouts.

**Ledger (Rule 17).** DW-29 is addressed by Tasks 7, 8, 11 and 13 (B4), and by the AC "DW-29".

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`. There is one `iris_execute_tests` call per message, and the first call of a stage is `iris_server_info`.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s210i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses `e2s210q` and review uses `e2s210r`.

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, port 1991.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`), in two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests` on slot B, one class per message. Expected: all pass, and no `zz` row or stream is left.
  - New or changed: `OcuTalon.Test.Live.Status`, `Test.Core.StatusMonitor`, `Test.Web.Api`.
  - Regression: `Test.Install.Production` (the oracle row), `Test.Live.Payloads`, `Test.Contract.Ac`, `Test.Msg.Contracts`.
- (loop) Each in its own call: `node web/scripts/catalog.mjs --check`, `node web/scripts/payloads.mjs --check`, `npm --prefix web test`, `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh`. Expected: exit 0.
- (loop) Each in its own call: `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-storage.sh`. Expected: exit 0.
- (loop) Throwaway, one piece per call: `build`; `live sign-in` (B1 to B6 and every other chromium spec); `teardown`. Expected:
  - each passes;
  - B6 is skipped with "Story 1.6 turns this on";
  - the script prints PASS for `check_no_key`;
  - teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `build`; `shard lane-b`; `shard lane-b --reverse`; `live production`; `live demo-path`; `teardown`. Expected:
  - every class passes;
  - `StatusMonitor` is alive, and the start writes no error row;
  - the demo path's floor count is unchanged.

**Planned mutations (Rule 19).** For each one: apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Computation | `Computed` ignores `ChatAgent` | `Test.Live.Status` |
| Computation | `dailyCap` drops its slots | `Test.Live.Status`; B3 |
| Computation | `StateBody` sets `status` to `[]` | `Test.Web.Api`; B1; `api.spec` row 13 |
| Computation | `StatusMonitor` publishes on its first run | `Test.Core.StatusMonitor` |
| Computation | `OnProcessInput` skips the run | `Test.Core.StatusMonitor` |
| Banners | `noModelKey` and `costCap` swapped in order | `banner-view.test.mjs`; B5 |
| Banners | Reset soon not closable, or `noModelKey` closable | `banner-view.test.mjs`; B1 or B5 |
| Banners | Closed records never dropped on clear | `banner-view.test.mjs`; B5 |
| Banners | A new banner not announced | B2 |
| Banners | Focus not moved when a focused banner leaves | B5 |
| Heartbeat | `checkRow` ignores `heartbeatStalled` | `rail-view.test.mjs`; B2 |
| Cost cap | The composer is `aria-disabled` while `dailyCap` holds | B3 |
| DW-29 | `{time}` uses `pageTimeBeside` or adds " ET" on the online demo | `banner-view.test.mjs`; B4 |
| Typing | `catalog.mjs` lists no banner keys | `catalog.test.mjs` |

**Demonstrated mutations (Rule 19).** Each was applied, seen red at the cheapest tier that goes red, and restored; `git status --short`, `git diff --stat` and the checksum of every changed file were identical before and after.
- mutation: `Status.NoModelKey` reads `TriageAgent,DiagnosisAgent` only (`Computed` ignores `ChatAgent`) -> `Test.Live.Status` `TestComputedNoModelKey` red (slot B).
- mutation: `Status.DailyCap` quits before it sets the slots -> `Test.Live.Status` `TestComputedDailyCap` and `TestActive` red (slot B). B3 publishes its own payload, so it does not pin the computation; the unit class does.
- mutation: `StateBody` sets `status` to `[]` -> `Test.Web.Api` `TestStateBody` red (slot B). B1 and `api.spec` row 13 were not run for it.
- mutation: `StatusMonitor.OnProcessInput` publishes on its first run (`first` fixed to 0) -> `Test.Core.StatusMonitor`, all six tests red (slot B).
- mutation: `StatusMonitor.OnProcessInput` quits before the run -> `Test.Core.StatusMonitor`, five of six tests red (slot B).
- mutation: the `noModelKey` and `costCap` rows swapped in `BANNERS` -> `banner-view.test.mjs`, five tests red. B5 was not run for it.
- mutation: Reset soon `closable: false`, and separately `noModelKey` `closable: true` -> `banner-view.test.mjs`, six and four tests red.
- mutation: `retainClosed` never drops a record -> `banner-view.test.mjs`, four tests red.
- mutation: `textSlots` appends " ET" to `{time}` -> `banner-view.test.mjs`, three tests red.
- mutation: `checkRow` ignores `heartbeatStalled` -> `rail-view.test.mjs`, two tests red.
- mutation: `catalog.mjs` `LISTED_KEYS` without the banner and action keys -> `catalog.test.mjs`, five tests red.
- mutation: `banner-stack.ts` announces no new banner, with the next two, in one `live sign-in` run -> B2 and B5 red (at the announcement).
- mutation: `banner-stack.ts` appends " ET" to `{time}` when `onlineDemo` is true (same run) -> B4 red.
- mutation: `composer.ts` Send gets `aria-disabled="true"` while `dailyCap` is active (same run) -> B3 red.
- mutation: `banner-stack.ts` `keepFocus` returns at once, in a second `live sign-in` run (B5's announcement line would hide it in the first) -> B5 red at the focus line.
- mutation: `StatusMonitor.Stream` answers `""` -> `Test.Core.StatusMonitor` `TestProductSeams` red ("the job publishes on the instance stream"; slot B).
- mutation: `StatusMonitor.Readings` body emptied -> `TestProductSeams` red, four assertions (slot B).
- mutation: `Status.DailyCap` loses its `"number"` arm -> `Test.Live.Status` `TestComputedDailyCap` red ("capped as the number 1: active"; slot B).
- mutation: `catalog.mjs` reason-slot guard made unreachable (`if (false)` for `type !== REASON_SLOT_TYPE`) -> `catalog.test.mjs` "fails on a reason text with a slot ..." red.
- mutation: three together in one `live sign-in` run, `StateBody` sets `status` to `[]`, `banner-stack.ts` drops `rel="noopener noreferrer"` from the action link, and its CSS drops the 4px accent (`border-left: 0px`) -> six cases red: `api.spec` row 13 (status), B1 (no banner), B2, B3, B4 (log: "has a 4px left accent", received "0px") and B5 (log: `expectAction`'s `rel`, expected "noopener noreferrer"). This closes the no-key AC's B1 and the look and action clause of `expectLook` and `expectAction`; the run does not say which of the three each of B1 to B3 failed on.

**Shared surfaces:**
- `/state`'s `status`, now computed: `[noModelKey]` on every stack with the Keys stub, and on a CI start with no key after Story 1.6. It is asserted in `Test.Web.Api` `TestStateBody` and in `api.spec` row 13.
- `.banner-slot`'s content. The no-key banner shows on every page of every stack, which affects rail.spec R11, any count of links, focusable controls or tab stops after the header, and the main page's height at 1280×720 (`frame.spec`, `chat.spec`, `links.spec`).
- `StatusMonitor`'s production row and the `ProductionItems` oracle, read by `Test.Install.Production` and `check_production`.
- `catalog.ts`'s `PAGE_TEXTS` and the new `PAGE_SLOTS` (`catalog.test.mjs`).
- The meta of the rail's check rows while `heartbeatStalled` holds (`rail-view.test.mjs`, `rail.spec`).
- `main.main`'s `tabindex`.
- `fixtureUser`'s kinds, and `test-sign-in.sh`'s users and labels.
- The announcement recorder, which moves to `support/page.ts` (`live.spec`).
- The instance stream: unchanged by any test, and by `StatusMonitor` on a fresh stack.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` classes make and remove their own rows, streams and counters;
- `banners.spec.ts` owns `ZzBanners`, publishes only on that session's stream, clears every condition it turns on in `finally`, removes its fixture rows, and never assumes an empty banner slot beyond the snapshot's own `noModelKey`.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-23).** The plan halted after planning, as the dispatch asked.
- It used the committed `epic-2-context.md` (3b3a732) without recompiling it, and took Story 2.9 (the rule's choice) and Story 2.13 (the lead's) as the continuity context.
- It ran no runtime measurement and started no throwaway.
- **One cross-lane risk is flagged for the lead:** the frontmatter `deferred` item and the Design Notes' cross-lane risk. Lane A's `Keys.Status` in an `/ocutalon/api` request after Epic 1 merges is an inference from the source.
- DW-29 is addressed.

**Implement and review (2026-10-23, baseline `eb1412c`).**

*Implemented.*
- The server computes the banner conditions once, in `Live.Payload.Status` (`Readings`, `Computed`, `Active`), and `/state` and `StatusMonitor` both use it.
- `StatusMonitor` is a 15-second `Ens.InboundAdapter` service. Its first run publishes nothing, a change publishes full views on the instance stream in the catalog's order, and a refused publish is logged and tried again at the next run.
- The page shows the nine banners in the catalog's order in `.banner-slot`, with page times, announcements, the focus rule and Close on Reset soon and Reconnecting only. The rail's check rows read "(late)" while `heartbeatStalled` holds.

*Files changed.*
- Server:
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls`: the computation (`AGENTS`, `Readings`, `Computed`, `Active`, `ActiveOf`).
  - `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls`: the polling publisher, without `STUB`.
  - `src/ocutalon/cls/OcuTalon/Production.cls` and `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls`: pool 1, `CallInterval` 15.
- Server tests:
  - `Test/Live/Status.cls`, `Test/Core/StatusMonitor.cls`, `Test/Core/StatusMonitorProbe.cls` and `Test/Core/StatusMonitorSeamProbe.cls` (new);
  - `Test/Web/Api.cls`: `TestStateBody` compares `status` with `Status.Active`.
- Page:
  - `web/scripts/catalog.mjs` and `web/src/app/msg/catalog.ts`: the banner and action keys, the slot types and `PAGE_SLOTS`;
  - `web/src/app/banners/banner-view.ts` and `banner-stack.ts` (new), with `web/src/app/app.ts`;
  - `web/src/app/main-page/main-page.ts`: `tabindex="-1"` on `main.main`;
  - `web/src/app/rail/rail-view.ts`: `lastRunLate`.
- Page tests:
  - `web/scripts/banner-view.test.mjs` (new);
  - `web/scripts/catalog.test.mjs` and `web/scripts/rail-view.test.mjs`;
  - `web/e2e/banners/banners.spec.ts` (new: B1 to B6);
  - `web/e2e/support/iris.ts` and `web/e2e/support/page.ts`: `publishStatus`, `decideIsStub`, the announcement recorder;
  - `web/e2e/live/live.spec.ts`, `web/e2e/api/api.spec.ts` (row 13) and `web/e2e/rail/rail.spec.ts` (R11): the sweep;
  - `docker/tests/test-sign-in.sh`: `ZzBanners`, `check_no_key` and the labels.

*Review.* Four layers reported 31 findings: high 0, medium 5, low 20, false 4, maybe-false 2 (the Review Triage Log has one row each).
- **Patches applied (3 medium entries, 5 low):**
  - the generator again refuses a non-`fallbackReason` slot in a `fallbackReason.*` text, with the test restored (Decided 19);
  - `StatusMonitor`'s own seams are tested through `StatusMonitorSeamProbe` (`TestProductSeams`; Decided 18);
  - `dailyCap` is documented and tested for a number and a string `capped` (Decided 17);
  - two assertions that could not fail were removed from `Test.Live.Status`;
  - a test title was corrected;
  - the missing mutation lines were closed.
- **Deferred:** nothing new. The two findings that restate the frontmatter item (Lane A's `Keys.Status` in an `/ocutalon/api` request) are recorded as `maybe-false` duplicates of it.
- **Rejected, with reasons in the log:**
  - `Active` is not guarded, because `/state` fails loudly by design (`TestStateFailsLoudly`);
  - `TestStateBody` depends on the stub, but the CI start has no key, `api.spec` row 13 pins it, and the fix needs a new argument (reopen_if a gate runs `Test.Web.Api` on a stack with a key set and no cap);
  - double computation and a repeated one-line test (negligible);
  - logging texts and repeat rates on failures that do not occur or that the spec fixes;
  - the job-restart residual (Decided 4), R11's new assertion (Task 15), B6's skip (the matrix), `heartbeatStalled` from `StatusMark` (Story 8.2), an impossible `resetsAt` (the page shows an empty time), a stale announcement (at most 150 ms per waiting banner), and the intent-alignment notes (descriptive).

*Follow-up review recommendation: true.* Two medium entries were patched (the generator's slot guard and the `StatusMonitor` seams test). Both were verified by mutation and the loop and once checks passed after them, but they did not get a second review pass.

*Verification performed.*
- Slot B (`ocutalon-slot-b`, `OCUTALON`, build 154): both `iris_doc_load` calls compile with 0 errors; `Test.Live.Status` 5/5, `Test.Core.StatusMonitor` 7/7, `Test.Web.Api` 29/29, `Test.Install.Production` 4/4, `Test.Live.Payloads` 10/10, `Test.Contract.Ac` 6/6, `Test.Msg.Contracts` 6/6; no `zz` row or stream is left.
- Static and Node: `catalog.mjs --check`, `payloads.mjs --check`, `npm --prefix web test` (370 pass), lint, `test-web-build.sh`, `test-class-rules.sh`, `test-boundaries.sh` and `test-storage.sh` exit 0.
- Throwaway `e2s210i`: `live sign-in` ran twice after the last patch (the final run 176 passed, 2 skipped: B6, "Story 1.6 turns this on", and a demo-path "not built" case); `check_no_key` prints PASS. The `(once)` lines: `ci/checks.sh` exits 0; `shard lane-b` and `shard lane-b --reverse` pass 42 classes each; `live production` passes (every enabled item runs, the start writes no error row); `live demo-path` passes with the floor 3 of 3; `teardown` leaves nothing.
- Matrix Test Audit: every row has a covering test that ran and passed, B6 excepted. Its row is the matrix's own skip while `Decide` carries `STUB`.
- Mutations (Rule 19): see the lines under `## Verification`. Every one was applied, seen red and restored with `git diff` byte-identical.

*Residual risks.*
- **The cross-lane risk (DW-148, the frontmatter item):** after Epic 1 merges, `Keys.Status` may count a key as present in a request. B1, B6 and `api.spec` row 13 turn red at that merge if it is real. B6 is skipped until then.
- `TestRefusedPublishIsPublishedAtTheNextRun` takes 25 to 40 seconds (any `TSTART` and `TROLLBACK` on this slot does).
- The production bundle is 522 kB against a 500 kB budget, a warning; the baseline was 512 kB.
- Banners that appear together are announced 150 ms apart, because the CDK live announcer drops a message that is still waiting.
