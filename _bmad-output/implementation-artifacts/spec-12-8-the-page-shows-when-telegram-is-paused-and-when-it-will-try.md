---
title: 'Story 12.8: The page shows when Telegram is paused, and when it will try again'
type: 'feature'
created: '2026-10-31'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-12, AD-13, AD-14, AD-18, AD-19, AD-22, AD-29, AD-32 and AD-33)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 12.2's `TelegramIn` pauses for 5 minutes on a 409 and records the `telegramPaused` mark, which `/state` and `StatusMonitor` turn into the `telegramPaused` status condition. Lane B's warning banner already shows for that condition, but:
- no browser test has seen the banner come from a real pause, or leave when the pause ends;
- the Telegram card has no paused state: it shows nothing (state `on`), or "Telegram not set up" (state `off`, which is what `TelegramIn` records after a restart during a pause);
- nothing searches the page for the bot token.

**Approach:**
- The card gets its paused state: the `circle-pause` icon, "Telegram paused" and "Trying again at {time}". It shows whenever the store holds `telegramPaused` as active (the same condition, from the same store, as the banner), ahead of every other state, and with no QR code, link or code.
- The banner is reused unchanged.
- One browser test in Lane A's `web/e2e/demo-path/telegram-page.spec.ts` drives the real `TelegramIn` against the CI mock: a 409, the page's banner and card, a reload, the resume and the clear, and the token search. A second test there checks the card's states from a changed snapshot.
- A new test-only class, `Test.Channel.TelegramPageFixture`, is the spec's IRIS side. It is built on `LiveCase`'s helpers, which become public class methods.

## Boundaries & Constraints

**Always:**
- **One truth for "paused".** The card is paused exactly while `LiveState.store().status.telegramPaused.active` is `true`. That is the same reading, of the same store, as `banner-view.ts`'s `holds`. The store applies the snapshot's `status` and every `status` event, so the card and the banner appear and leave on the same live update.
  - The card never reads `telegram.pausedUntil`: only the snapshot sets it, so it would keep a cleared pause on screen.
- **Paused comes first.** It is ahead of every state the card knows (`off`, `rejected`, `on`), and later stories add theirs below it. While paused the card holds only:
  - the icon, `circle-pause` in `--telegram-card-paused-icon`, hidden from assistive technology;
  - "Telegram paused";
  - "Trying again at {time}" in caption type.

  It holds no link, no `img`, no `canvas` and no other `svg`, so Story 12.3's QR code stays withdrawn.
- **The card's {time} is the banner's {time}.** It is `pageTime` (`chat/page-time.ts`) of the condition's `time` slot: the browser's zone and hour format, with no suffix. A missing or unreadable time is empty, by the banner's own rule (the server raises the condition only with a readable UTC time, `Live/Payload/Status.cls:163`).
- **Texts.** The two new page strings are EXPERIENCE.md's, verbatim. They live in a framework-free Lane A module `telegram-card-view.ts` as `TELEGRAM_CARD_TEXTS`, bound by interpolation (AD-13; Rule 14 ASCII).
- **The browser tests.** They run on fresh throwaways and in CI only, against the CI mock and its dummy token.
  - The real-pause test turns the release's Telegram section on only through the seam (`setTelegramIncluded(1)`), and restores it in `finally`.
  - `TelegramPageFixture.Finish` stops `TelegramIn`, restores its `Enabled` row and both Telegram marks, resets the mock's Bot API side (after the item has no job, as `BotApi.Reset` requires), and waits for StatusMonitor's clear, so no `telegramPaused` event outlives the test.
  - Every IRIS script of the spec prints its `CHK|` lines on every path (Try/Catch), because `irisScript` re-runs a session that printed none, and `Start` is not idempotent.
- **The token** is read from the stack's environment, through `TelegramPageFixture.Token()`. It is compared only as a boolean (`includes(...)` asserted `false`): no assertion text, message, title, annotation or log of the spec holds it.

**Never:**
- No change to:
  - `Included()`;
  - the banner (`banners/*`) or the catalog (`msg/catalog.ts`);
  - the live store or state (`live/*`);
  - `rail-view.ts`, `status-rail.ts` and `web/e2e/support/**`;
  - Lane B's specs (`banners.spec.ts`, `rail.spec.ts`);
  - `ci/units.sh` and `ci/mock/**` (no new scenario: `telegram-conflict` exists);
  - `Test/Contract/Mock.cls`, `README.md`, or any contended file of the dispatch.
- No Lane B `web/` file changes beyond the three entry-level edits named under Design Notes, "Footprint".
- No new spec file name in `web/e2e/demo-path/`: `demo-path-summary.mjs` fails on any `telegram-<id>` whose id is not a step.
- No real bot, no call to `api.telegram.org`, no real token. Every enabled item goes through `LiveCase`'s `BaseReason`, so its `ApiBase` row must name the mock.
- No spec publishes a live event; the real-pause test's events are StatusMonitor's own.
- No 5-minute wait. The test stands in for elapsed time by moving the mark, which is 12.2's pattern.

## I/O & Edge-Case Matrix

The browser runs in Asia/Kolkata with the en-GB locale. The time oracle is the mark's UTC minute plus 5 h 30 min, written `H:MM` (an unpadded 24-hour hour), as en-GB's `hour: 'numeric'` writes it.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Live onset (Integration: `TelegramIn` → `StatusMonitor` → the page) | Seam on. `TelegramIn` on against the mock (`Start`). The README account's page loaded with no banner and no paused card. Then `telegram-conflict` is queued while a poll is open (`Conflict`). | Within 1 s of the page's `data-instance-seq` reaching the onset's Seq:<br>- the banner `telegramPaused` reads "Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {oracle}. Each OcuTalon needs its own bot.", with the link "Set up a bot (opens in a new tab)" to `https://github.com/jbrandtmse/OcuTalon#telegram`, `target` `_blank`;<br>- the card's text is exactly "Telegram paused Trying again at {oracle}", its icon is `circle-pause` in the token's colour, and it holds no link and no `img`, `canvas` or other `svg`. | — |
| Reload while paused | The same pause, and `page.reload()` | The same banner and card, from `/state`'s `status`. | — |
| Resume and clear (Integration: `TelegramIn`'s 200) | `Resume`: the mark moved 2 s ahead; `TelegramIn`'s first 200 deletes it; StatusMonitor publishes the clear | Within 1 s of `data-instance-seq` reaching the clear's Seq: no `telegramPaused` banner, and the card shows neither paused text. | — |
| Token search (NFR-11) | The whole real-pause test | The dummy token is in neither the page's HTML (at the pause and after the clear) nor the text of any response under `/ocutalon/` that the page received. Positive controls: the HTML holds the banner's text; the bodies hold the mark's time and `ocutalon_ci_bot`. | — |
| Paused while off (a restart during a pause) | Changed `/state`: `included` true, `state` `off`, `telegramPaused` active with `2026-10-23T12:00:00Z` | The card is paused with "Trying again at 17:30", and no "How to set it up" link. The banner shows. | — |
| Paused while rejected | The same with `state` `rejected` | The card is paused, as above. | — |
| Not paused | `state` `off`, `telegramPaused` inactive | "Telegram not set up" with its link (R11 unchanged); no `telegramPaused` banner. | — |

</intent-contract>

## Code Map

**Lane A's card and spec (edit freely)**
- `web/src/app/rail/telegram-card/telegram-card.ts:1-61`: the card.
  - Its `telegram` input comes from `status-rail.ts:94`, and `notSetUp` is at :60.
  - The template (:19-28) shows only the not-set-up block; the styles (:29-50) use the `--telegram-card-*` tokens.
- `web/e2e/demo-path/telegram-page.spec.ts`: step 1's Telegram part.
  - Today it is only `notBuilt(…, '12.4')`, which stays: Story 12.4 replaces it.
  - `not-built.ts` declares the skip.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls` (Epic 12's, 12.2). These instance helpers use no state:
  - `BaseReason` :125, `WaitJobs` :159, `CallsOf` :261, `WaitCalls` :272, `WaitState` :296, `WaitMark` :308, `WaitMonitor` :332, `MonitorSettled` :341.

  These are private class methods:
  - `MonitorAge` :349, `InstanceSeq` :366, `Events` :372, `WaitEvent` :384, `WaitClear` :401.

  These keep state in properties (`RowsFound`, `StartedItems`, `MarksFound`):
  - `StartItems` :96, `StopItems` :138, `SaveMarks` :171, `RestoreMarks` :181.

  No subclass redefines any of them (grep).
- `Test/Channel/TelegramPause.cls:49-59` (`StartAndConflict`: start, wait for `on`, wait for an open poll, queue the 409) and `:110-139` (`TestResumeSucceeds`: move the mark 2 s ahead, wait for its deletion, then for the clear). The fixture follows both.
- `Test/Channel/BotApi.cls:46` `PollerReason`, `:60` `Reset`, which refuses while `TelegramIn` has a live job.

**Called, never edited**
- `Test/Contract/Mock.cls`:
  - `TELEGRAMBASE` :53, `TELEGRAMBASEVAR` :56 and `TELEGRAMTOKENVAR` :58;
  - `TelegramMissingReason` :394, `Control` :417 and `Calls` :429.
- `Test/Agent/RunnerFixture.cls`: `RunningReason` :86, `Jobs` :127, `SnapshotDefault` :670, `PutDefault` :682, `RememberDefault` :715 and `RestoreDefaults` :727.
- `Test/Data/Fixture.cls:179` `SetTelegramIncluded`.
- `Live/Payload/Status.cls:54-73,154-182`: the condition holds only while the mark is a UTC time after now, and its slot `Time` is the mark verbatim.
- `Web/Api.cls:765-775`: the Telegram block and `status`.
- `Core/StatusMonitor.cls:47-82`: every 15 s it publishes a changed condition on the instance stream, and its first run is silent.
- `ci/compose.ci.yml:21-22`: the mock base, and the dummy `TELEGRAM_BOT_TOKEN`.
- The page:
  - `live/live-store.ts:51,126,177-183`: `status` comes from the snapshot and every event, keyed by condition, while `telegram` comes from the snapshot and `pairing` events only, so `state` and `pausedUntil` are never live;
  - `live/live-state.ts:58,93,111`: `LiveState`, `store()` and `instanceSeq`;
  - `main-page/main-page.ts:104-105`: `data-session-seq` and `data-instance-seq`;
  - `banners/banner-view.ts:76`: the `telegramPaused` row, and `holds` at :146 (active only);
  - `banners/banner-stack.ts:25-32`: `FORMAT.time` is `pageTime`;
  - `chat/page-time.ts:15-35`: `pageTime`, with `hour: 'numeric'` and `minute: '2-digit'`;
  - `rail/rail-view.ts:53-58`: `RAIL_TEXTS.telegramNotSetUp` and `telegramHowTo`, `TELEGRAM_ANCHOR` and `readmeSection`;
  - `status-rail.ts:40-44,237,272`: its focus rule sends focus lost in the rail to the main region;
  - `styles/tokens.css:285,671,894`: `--telegram-card-paused-icon`, in the light and both dark blocks.
- The e2e support:
  - `support/iris.ts`: `irisScript` and `chk` :90-112, `quoted` :186, `setTelegramIncluded` :1041;
  - `support/floor.ts:150`: `signInReadmeLoaded`;
  - `support/page.ts:20`: `tokenColor`;
  - `support/api.ts:14,27`: `STATE`, and `changeSnapshot(page, change)`.
- `e2e/banners/banners.spec.ts:38,51-58`: the zone and locale, `APPLIED_MS` 15 s, `ONE_UPDATE_MS` 1 s; this is the pattern for "within one live update".
- `e2e/rail/rail.spec.ts:463-497`: R11 expects the `on` card to be empty and the off and rejected card to say "not set up", with no Telegram banner. It must stay green.
- The runner:
  - `web/playwright.config.ts`: one worker, a 45-second test timeout, `forbidOnly`;
  - `docker/tests/test-demo-path.sh:41-46`: Playwright's global timeout is the unit deadline left (540 s locally, 1200 s in CI);
  - `web/scripts/demo-path-summary.mjs:9-10,38-56`: `telegram-<step>.spec.ts` must name a step.

**Lane B files edited by entry (see Design Notes, "Footprint")**
- `web/src/app/icon/icon.ts:4-29`: the `IconName` union, and `:48-170` the `@switch` of Lucide paths.
- `web/scripts/ux-strings.test.mjs`:
  - `:41-61` `IMPORTED`; `:154` `SOURCES.ux`, where "Telegram not set up" is at :220;
  - `:613-618` fails for any `*_TEXTS` constant that is not imported, and `:624-626` for any inventory string with no source.
- `web/scripts/api-client-sources.test.mjs:111-127`: the Telegram-parts pin (its `doesNotMatch` is at :124). `doesNotMatch(/\btest\(|\btest\.(skip|only)\(/)` forbids any test of telegram-page's own.

## Tasks & Acceptance

**Execution:**
1. `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`. Behaviour-preserving refactor (Rule 2: extend, don't copy):
   - The stateless helpers become public `ClassMethod`s: `BaseReason`, `WaitJobs`, `CallsOf`, `WaitCalls`, `WaitState`, `WaitMark`, `WaitMonitor` and `MonitorSettled`.
   - `MonitorAge`, `InstanceSeq`, `Events`, `WaitEvent`, `WaitClear` and `EpochNow` lose `[ Private ]`.
   - New public class methods:
     - `Enable(item, ByRef rows) As %Status`: the body of `StartItems`' loop;
     - `Disable(items, rows) As %Status`: the body of `StopItems`;
     - `Marks() As %List` and `PutMarks(found As %List)`.
   - `StartItems`, `StopItems`, `SaveMarks` and `RestoreMarks` keep their signatures and properties, and call these.
   - The class doc names `TelegramPageFixture` as the second user.
2. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls` (new): `Extends %RegisteredObject`, class methods only, no `Test…` method (so it is not a test class). Each method returns `""` or a reason, and names no token.
   - `Start(Output saved)`:
     - the guards: `Mock.TelegramMissingReason`, `BotApi.PollerReason` and `RunnerFixture.RunningReason`;
     - `WaitMonitor`, then `BotApi.Reset`;
     - `saved` = base64 (no line breaks) of the UTF-8 of `$ListBuild(rows, Marks(), InstanceSeq())`, set before anything is enabled;
     - `Enable("TelegramIn", .rows)`, then `WaitState("on", 20)`.
   - `Conflict(Output until, Output onset)`:
     - `since = InstanceSeq()`;
     - `WaitCalls("getUpdates", 1, 20)`, then `Control("replies", {"scenario": "telegram-conflict"})`;
     - `WaitMark("telegramPaused", 1, 5)`, and `until` is that mark;
     - `onset = WaitEvent(since, 1)`.
   - `Resume(seconds, onset, Output clear)`:
     - `Record` the mark at `AddSeconds(NowUtc(), seconds)`;
     - `WaitMark(…, 0, 20)`;
     - `clear = WaitEvent(onset, 0)`.
   - `Finish(saved)`: safe after any partial `Start`.
     - `Disable("TelegramIn", rows)`, then `PutMarks`;
     - `BotApi.Reset`;
     - `WaitClear(since)`.
   - `Token()`: `$SYSTEM.Util.GetEnviron(Mock.#TELEGRAMTOKENVAR)`, the stack's dummy token, for the spec's search only.
3. `web/src/app/icon/icon.ts` (a Lane B entry): `IconName` gains `circle-pause`, with one `@case` of Lucide's `circle-pause` paths (ISC, already vendored): `<circle cx="12" cy="12" r="10" />`, `<line x1="10" x2="10" y1="15" y2="9" />` and `<line x1="14" x2="14" y1="15" y2="9" />`. If Lucide's current source differs, use its paths and the spec's selector follows.
4. `web/src/app/rail/telegram-card/telegram-card-view.ts` (new): a framework-free module (type imports only, erasable syntax, so Node imports it).
   - `TELEGRAM_CARD_TEXTS = { paused: 'Telegram paused', tryingAgainAt: 'Trying again at {time}' }`.
   - A pure view: `(telegram: TelegramState, status, format: { time(iso: string): string })`, giving paused (with its retry line), not set up (`off` or `rejected`), or nothing, in that order.
   - Its doc states the contract above.
5. `web/src/app/rail/telegram-card/telegram-card.ts`:
   - `inject(LiveState)`; the view computed from the `telegram` input and `store()?.status`, with `format.time = pageTime`.
   - The paused block: the icon (`circle-pause`, coloured by `--telegram-card-paused-icon`), then the text, then the caption line.
   - The root carries `data-state` `paused` or `not-set-up`.
   - The not-set-up block is unchanged.
   - The class doc gains the paused state.
6. `web/scripts/ux-strings.test.mjs` (a Lane B entry):
   - `IMPORTED` gains `['rail/telegram-card/telegram-card-view.ts', ['TELEGRAM_CARD_TEXTS']]`;
   - `SOURCES.ux` gains `'Telegram paused'` and `'Trying again at {time}'` (EXPERIENCE.md:357).
7. `web/e2e/demo-path/telegram-page.spec.ts`. Keep the `notBuilt(…, '12.4')` line, and update the header (12.8's tests, then 12.4's pairing replaces the call). Add `test.describe` with `test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' })`, then:
   - **T2, the card's states from a changed snapshot.** No seam and no IRIS state. One sign-in, then one `changeSnapshot` per case (routes cleared between cases), with `included: true` and the `telegramPaused` member set. The cases are the matrix rows "Paused while off", "Paused while rejected" and "Not paused".
   - **T1, the real pause** (`test.setTimeout(240_000)`). The local helpers call `irisScript`; `appliedInstance(seq)` polls `data-instance-seq` (15 s).
     - Steps: `was = setTelegramIncluded(1)`, `Start`, sign in, the baseline (no banner, no paused card);
     - then `Conflict`, the onset row, reload, the reload row, `Resume(2)`, the clear row;
     - then the token search.
     - Response bodies are read in full: their promises are collected, then awaited.
     - `finally`: `Finish(saved)`, then `setTelegramIncluded(was)`. A reason from `Finish` fails a test that had passed.
8. `web/scripts/api-client-sources.test.mjs` (a Lane B entry). The `telegram-page.spec.ts` row still pins one `notBuilt` owned by 12.4, still forbids `test.skip(` and `test.only(`, and now requires a test of its own (Story 12.8's). `telegram-approval.spec.ts` keeps "no test of its own". The title and header comment say so.

**Acceptance Criteria:**
- Given `TelegramIn` has stopped polling after a 409 Conflict and recorded the pause and its retry time (Story 12.2), so that `/state` carries the `telegramPaused` condition with that time, when the page shows it, then the page shows the warning banner "Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {time}. Each OcuTalon needs its own bot." with the "Set up a bot" README link, and the card shows "Telegram paused" and "Trying again at {time}" with the QR code withdrawn (FR-22, UX-DR56, UX-DR116). And:
  - this holds within one live update of StatusMonitor's onset and again after a reload;
  - both {time}s are the page time of the mark;
  - the card's paused state shows also when the snapshot's state is `off` or `rejected`.
- Given the pause has lasted 5 minutes (stood in for by moving the mark) and `TelegramIn` polls again with success, so the condition clears (Story 12.2), when the page receives the next live update, then the banner leaves within one live update, and the card leaves its paused state on the same update (FR-22, UX-DR34).
- Given a Telegram test run against the mock, when a test searches the page for the dummy token, then it finds none (NFR-11, AD-14). The search covers the page's HTML and every `/ocutalon/` response the page received, and each scan finds a value that its store does hold.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-12: status conditions are computed on read in `/state` and published by `StatusMonitor`, and the page applies them idempotently. This is the one source of the card and the banner.
- AD-13: text is bound by interpolation.
- AD-14: the pause mark, and no token on the page.
- AD-18: `StatusMark` and `StatusMonitor`.
- AD-19: the token comes from the environment only.
- AD-22: tests run in throwaways against the CI mock; no new scenario.
- AD-29: the lanes. The card folder and `telegram-*.spec.ts` are Lane A's, and the rest of `web/` is Lane B's.
- AD-32: the banner's text is the catalog's. The card's are page constants, like `RAIL_TEXTS`.
- AD-33: one owner per file; Lane B files are touched only by entry, as below.

No acceptance criterion contradicts an AD. "Within one live update" (UX-DR34) is measurable as `banners.spec.ts` measures it: 1 s after the page applied the event's Seq.

**Footprint (Rule 11 (b); the epic context says any other `web/` edit needs a ruling; reported under `footprint_extensions:`).** Lane A files:
- the card folder (`telegram-card.ts`, and the new `telegram-card-view.ts`);
- `telegram-page.spec.ts`;
- `Test/Channel/LiveCase.cls`, and the new `TelegramPageFixture.cls`.

Three Lane B files are edited by entry, none contended by a running epic (Epic 29 merged). None can live in Lane A's files:
1. **`web/src/app/icon/icon.ts`: one icon.** `Icon` is the page's one icon component (the spine's Stack row: Lucide paths vendored into `web/`). Drawing the SVG inside the card would copy it (Rule 2). DESIGN names the icon for the paused state.
2. **`web/scripts/ux-strings.test.mjs`: one `IMPORTED` row and two `SOURCES.ux` strings.** The test inventories every component template and every `*_TEXTS` constant under `src/app/`, the card included. It fails for a string with no source and for an unimported `*_TEXTS` constant, so no card text can ship without this entry. Every later card story meets the same row.
3. **`web/scripts/api-client-sources.test.mjs`: the telegram-page row of its Telegram-parts pin.** It forbids any test of the file's own. Its own header expects Lane A to change the file, and 12.4 meets the same row.

If the gate refuses any of the three, the plan cannot hold: (1) and (2) become a Lane B ask, and (3) would need the browser test outside the demo path.

**Decided in-stage:**
1. **The card's source is the store's `status`, not `telegram.pausedUntil`.** No event updates `pausedUntil` (`live-store.ts:181-183`).
   - The predicate copies one expression of `banner-view.ts`'s private `holds`. Exporting `holds` would edit Lane B's banner for one line.
2. **Paused is ahead of `off` and `rejected`.** After a restart during a pause, `TelegramIn` records `off` while the mark holds (12.2's `TestRestartHonoursPause`), and the banner shows on the condition alone. "Telegram not set up" beside "Telegram is paused" would contradict it.
3. **The time follows the banner's rule.** It is the same `pageTime`, and an empty slot gives an empty time; that case is not reachable from the server, so the card has no separate branch.
4. **New `TELEGRAM_CARD_TEXTS` in the card folder, not `RAIL_TEXTS`.**
   - `RAIL_TEXTS` is Lane B's, and `rail-view.test.mjs` pins it exactly. Adding there would edit two more Lane B files.
   - The two existing card texts stay where they are, so no R11 or rail test changes.
   - The module must be framework-free, because `ux-strings.test.mjs` imports it with Node.
5. **The icon is `circle-pause`.** That is Lucide's current name for DESIGN's `pause-circle`; the page names icons by current names (`circle-alert`, `triangle-alert`). The size is the card's choice, and the colour is the existing token.
6. **The browser tests live in `telegram-page.spec.ts`.**
   - The summary maps only `telegram-<step>` names, and the pause is step 1's page.
   - So they run in the existing `live:demo-path` unit (`browser` group, 26 min on af47ff3c). Expected cost (inference, because the waits are wall-clock: StatusMonitor's 15 s tick and the 5 s poll): T1 about 60-70 s locally and 1.5-2.5 min on the runner, and T2 about 10-15 s. That gives `browser` about 28 min, under 30.
   - No unit is added or moved, and `ci/units.sh` is unchanged.
   - If a local run dies of the unit deadline with no failed test, re-run it with `OCUTALON_LIVE_DEADLINE=900`, as Rule 21 says for `sign-in`.
7. **T1 drives the real chain** (409 → `TelegramIn` → mark → `StatusMonitor` / `/state` → page), so the Integration rows use a real instance.
   - T2 uses a changed snapshot (R11's pattern) for the states that a browser test cannot reach cheaply.
   - Elapsed time is stood in for by moving the mark. A 5-minute wait would take `browser` over 30 min.
8. **No Node unit test of the view module.** It would be a new file in Lane B's `web/scripts/`. T1 and T2 cover each branch, and `ux-strings.test.mjs` imports the module.
9. **No card-level focus rule.**
   - A live onset can remove a focused "How to set it up" link only while the page's state is a stale `off`, because no event carries the Telegram state. The rail's existing rule then moves focus to the main region, never to `<body>`.
   - The heading as the target belongs with the card's first focus rule (Unpair, Story 12.4).
10. **`data-state`** on the card root gives the tests a stable hook.
11. **The seam and Release 1.0.0.** `Included()` stays 0 until 12.7, so the card stays hidden on the page.
    - T1 shows it through `^OcuTalonTest("TelegramIncluded")`, which is `setTelegramIncluded`, as R11 does.
    - T2 uses `included: true` in the changed snapshot.

**Extend, don't copy (Rule 2):**
- The banner is reused unchanged.
- The card follows `StatusRail`'s `inject(LiveState)`, and the format is injected the way `BannerFormat.time` is.
- The fixture calls `LiveCase`'s helpers, which become public class methods, instead of copying them. The order of `Start` and `Conflict` follows `TelegramPause.StartAndConflict`: four calls of those helpers.
- The spec reuses `irisScript`, `chk`, `quoted`, `setTelegramIncluded`, `signInReadmeLoaded`, `tokenColor` and `changeSnapshot`.
- `TELEGRAM_CARD_TEXTS` is a deliberate sibling of `RAIL_TEXTS` (Decided 4).

**Integration ACs (Rule 1):** the matrix rows "Live onset" and "Resume and clear". In both, the page, the consumer, reads the real `/state` and StatusMonitor's real events, produced by the real `TelegramIn` against the mock, and shows the banner and the card or removes them.

**Consumes:**
- From Story 12.2: `TelegramIn`'s pause and resume, the `telegramPaused` mark, and the `LiveCase` helpers.
- From Lane B: `Live.Payload.Status`, `StateBody`, `StatusMonitor`, `LiveState`, the banner stack, `pageTime`, `Icon` and the e2e support.
- From Story 12.1: the mock and `BotApi`.

**Consumed-by:**
- 12.3 adds the unpaired state below paused. It keeps the paused assertions green, so no QR code shows while paused, and it meets the stale snapshot `state`: the card learns `on` only from a snapshot.
- 12.4 adds the paired state below paused and the card's first focus rule. Its pairing test joins `telegram-page.spec.ts` and may use `TelegramPageFixture` and `LiveCase`'s class methods.
- 12.7 turns the card on for the release.

**Owned ledger:** none (the inbox is empty).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- One command per foreground call, with `timeout: 600000`, and never two IRIS test runs in one message.
- Tests never run on a dev slot. If an IRIS MCP call is needed, it names `server: ocutalon-slot-c` and `namespace: OCUTALON`, after `iris_server_info`.
- Tear down only `e12s8i` and `e12s8iw`, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, `ux-strings` and `api-client-sources` among them.
- (loop) `npm --prefix web run lint`. Expected: `tsc` on the e2e and `node --check` pass.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s8iw ci/warm.sh up`, before the first `ci/iris.sh build` of the stage: a rebuilt bundle changes the warm manifest, so after a build run `down`, then `up`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s8iw ci/iris.sh class <Class>`, one call per class. The classes are `OcuTalon.Test.Channel.TelegramPause`, `TelegramIn`, `TelegramOut`, `TelegramNoToken`, `TelegramMock`, `TelegramSwitch` and `TelegramApi`. Expected: `CLASS … passed`; the refactored `LiveCase` behaves the same, and `TelegramPageFixture` compiles in the `WARM reloaded` line.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s8iw ci/warm.sh down`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s8i ci/iris.sh build`, once after each change under `web/` and before a browser unit.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s8i ci/iris.sh live demo-path`. Expected:
  - every PASS line;
  - `STEP 1 page: partly skipped`, with telegram-page's two tests passed and Story 12.4's part skipped;
  - no FAIL line.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s8i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: every Channel class passes in both orders.
- (once) The either-order check for the browser tests: swap T1 and T2 in `telegram-page.spec.ts` (a temporary edit), run `live demo-path` once, and revert byte for byte (`cmp` against your own backup).
- (once) `<lane> OCUTALON_RUN_TAG=e12s8i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`. Expected: passed. R11 and `banners.spec.ts`'s Telegram cases are unchanged by the new card.
- (once) One per call: `bash docker/tests/test-ci-config.sh` (`TelegramPageFixture` is no test class), `bash docker/tests/test-boundaries.sh`, then `bash ci/checks.sh`.
- (once) Write the changed and new paths to a file in the stage's scratchpad and run `bash ci/changes.sh ci.yml --paths-from <file>`. Record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s8i ci/iris.sh teardown`.
- (once) `git status --short -- ci web/src/app/banners web/src/app/live web/src/app/msg web/src/app/rail/rail-view.ts web/src/app/rail/status-rail.ts web/e2e/support web/e2e/banners web/e2e/rail src/ocutalon/cls/OcuTalon/Test/Contract src/ocutalon/cls/OcuTalon/Channel README.md` prints nothing. The only Lane B paths changed are the three entries named.
- Left to CI (Rule 23): `browser` (`demo-path` with T1 and T2, `sign-in`, `answers`), `production` (`shard:lane-a@Channel` with the refactor), and the other groups that `ci/changes.sh` selects. Record `iris (browser)`'s minutes and `live:demo-path`'s seconds.

**Shared surfaces:**
- **The Telegram card's rendered states.** Readers: R11 (`rail.spec.ts`), which expects an empty `on` card and a not-set-up card for `off` and `rejected`, with no pause on its stack; unchanged.
- **The `IconName` union** gains a member. No test lists it.
- **The UX strings inventory** gains two strings and one imported module (`ux-strings.test.mjs`).
- **The Telegram-parts pin** of `api-client-sources.test.mjs`.
- **The demo path's step 1 counts:** +2 passed. The verdict stays `partly skipped`, and `test-demo-path-gate.sh` reads fixtures only.
- **The marks and the item.** `telegramState` and `telegramPaused`, `TelegramIn`'s `Enabled` row, the mock's Bot API state and `^OcuTalonTest("TelegramIncluded")` are restored by `Finish` and the `finally`.
- **The instance stream's `telegramPaused` events.** `Finish` waits for the clear.
- **`LiveCase`'s helpers, now class methods.** Readers: the seven `Test.Channel` live classes.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).** Each is applied, seen red, and reverted byte for byte (`cmp` against your own backup; `git status --short` and `git diff --stat` unchanged), and recorded here as `mutation: … -> …`. A mutation of Lane B code is temporary. No mutation points a call at the public API.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, the card | The view never returns paused | T1 (onset), T2 (off, rejected) |
| AC1, the banner from a real pause | `BANNERS` loses its `telegramPaused` row | T1 (onset: no banner) |
| Paused over off and rejected | Paused only when `state` is `on` | T2 (off, rejected) |
| No link or QR while paused | The not-set-up link also renders while paused | T2 (off) |
| Not paused (contrast) | Paused for any `telegramPaused` member, ignoring `active` | T2 (not paused), T1 (baseline) |
| The time | The card shows `iso.slice(11, 16)` (UTC) | T1 and T2 (17:30 against 12:00) |
| The icon | The card names `clock` | T1 (the icon's lines) |
| AC2 | `applyEvent` ignores a `status` event whose `active` is false (`live-store.ts`) | T1 (clear: banner and card remain 1 s after the clear's Seq) |
| AC3 | `TelegramIn` records `RecordTelegram("on", token)` | T1 (a `/state` body holds the token) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
