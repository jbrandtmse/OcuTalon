---
title: 'Story 16.8: The page counts down to the reset and waits it out'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '21c67e4e46e86fd7682f31382042c46da0f6d635'
baseline_commit: '21c67e4e46e86fd7682f31382042c46da0f6d635'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only: AD-12, lines 327-341, the closed status catalog at 338; AD-13, lines 342-386, the public status at 352 and the `?since=` return at 374; AD-19, lines 478-519; AD-25, lines 676-721, the schedule at 696; AD-3, lines 122-151, the public packages at 129-135; the event table row at 1110; Consistency Conventions "Times" and "Announcements and focus", lines 894-930)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (Story 16.8, lines 4345-4376; Story 16.4, lines 4242-4278, for what it reuses)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (line 79 the titles; 105-135 the splash and the resetting view; 180-183 page time and countdowns; 208-211 banners and the countdown; 336-347 the splash states; 845-860 the banner table)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md (lines 234-239 inline-notice-info; 521-528 the countdown tokens; 700 the splash fold rule; 743 and 752 the header and the countdown)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The online demo resets every few hours, and today the page neither shows the reset coming nor gets through it.
- `/state` has no next reset, and `StatusMonitor` never raises `resetSoon` or publishes `reset`.
- The header has no countdown.
- The splash has no reset-soon warning and no after-reset notice.
- A page left open across the reset keeps polling a dead session until a 401 sends it to a sign-in page that doesn't say why.
- DW-235: `AddressCounter.Shift` and `SessionEvents.CookieExpiry` repeat the accessor's UTC parsing.

**Approach:**
- **Server.**
  - `OcuTalon.Data.Public.Settings` becomes the one UTC helper (DW-235). It also computes the time left to the next reset and whether the reset is soon.
  - `StatusMonitor` computes `resetSoon` in one method that `/state` also calls, and publishes `reset` when the next reset changes.
  - `/state` gains `nextReset` on the online demo.
  - The splash renders the reset-soon warning and the `?since=` notice.
  - The shell's post-sign-in redirect drops `since`.
- **Page.**
  - A countdown pill in the header.
  - A reset watch that holds the pending reset and switches the whole page to a resetting view at the reset. A late timer, lost contact or a 401 past the reset also switch it.
  - The view polls the public status quietly and navigates once to `/ocutalon/?since=<load time>`.
- **Tests.**
  - ObjectScript classes on throwaways.
  - Node unit tests.
  - Two Playwright tests on the flag-on stack: one with a controlled clock and controlled answers, and one against the real server's clock.
  - The live unit's anchor moves 2 hours ahead of its start, so that no reset falls inside a run.

## Boundaries & Constraints

**Always:**
- **One next reset.** Every reader uses `OcuTalon.Data.Public.Settings.NextReset()`:
  - `/ocutalon/public/status` (unchanged);
  - `/state`'s `nextReset`;
  - `StatusMonitor`'s `reset` event;
  - the splash;
  - the resume cookie's expiry (unchanged).

  `NextReset` reads only the anchor and the interval, so `lastReset` and `lastResetKind` never move the schedule (AD-25).
- **DW-235, one UTC helper.** `Public.Settings` gets three public class methods:
  - `ToSeconds(utc)`:
    - accepts exactly `YYYY-MM-DDThh:mm:ssZ` with a valid date and time, which is the `Public` step's own `time` rule (`Install/Step/Public.cls:133`);
    - returns the seconds since the horolog epoch;
    - returns "" for anything else and never throws.
  - `FromSeconds(seconds)`: the UTC time to the second, with "Z".
  - `Shift(utc, seconds)`: the time moved by that many seconds, or "" for an unreadable time.

  The callers:
  - `NextReset` uses these methods, and its result is unchanged for every stored value the `Public` step accepts.
  - `AddressCounter.Shift` becomes a one-line delegate to `Settings.Shift`. Its signature and contract don't change.
  - `SessionEvents.CookieExpiry` parses through `Settings.ToSeconds` and has no `$ZDateTimeH` of its own. Its output doesn't change.

  No new class goes into `OcuTalon.Data.Public`, and the public packages still reference nothing outside AD-3's allow-list.
- **Reset soon: one threshold.** `Settings.RESETSOONSECONDS` is 300.
  - `Settings.SecondsToReset(now)` is `NextReset(now)` minus now, in whole seconds, or "" with no next reset.
  - `Settings.ResetSoon(now)` is 1 when `0 < SecondsToReset(now) <= 300`.
  - `now` defaults to the current UTC time in both.
- **The `resetSoon` condition.**
  - `StatusMonitor.ResetSoon(now = "")` is a new class method. It returns an `OcuTalon.Live.Payload.Status` with `Condition` `resetSoon` and no slots. `Active` is 1 when `onlineDemo` is "1" (through `Data.Setting.Get`) and `Settings.ResetSoon(now)` is 1.
  - `StatusMonitor.OnProcessInput` inserts it after `Computed`'s conditions. It is then remembered, compared and published like the other conditions: the first run is silent, and a clear is published with `active` false. `resetSoon` is last in `CONDITIONS`, so the catalog order holds.
  - `Web.Api.StateBody` appends it to `status` when active, through `Live.Payload.Status.ActiveOf`, after `Active`'s entries.
- **The `reset` event.** `StatusMonitor` publishes `reset` (`OcuTalon.Live.Payload.Reset`, `NextReset`) on the stream of its `Stream` seam when `NextReset()` differs from the value it remembers.
  - It publishes only with `onlineDemo` "1", and never an empty value.
  - The first run after the job starts only remembers.
  - A failed publish is logged as a warning with `LOGPUBLISH` and is not remembered, so the next run publishes it again.
- **`/state`.** On the online demo, when there is a next reset, `StateBody`'s last key is `nextReset` (after `traceAccount` when that key is present). In every other case the key is absent, and a local snapshot keeps exactly its keys.
- **The splash.** This is the online demo only; the local sign-in page never changes.
  - **The info notice above both cards** sits between `.lead` and `.splash-cards`, as an `inline-notice-info` with an info icon.
    - It shows only when the request's `since` passes `ToSeconds` and the public `lastReset` passes `ToSeconds` and is strictly later.
    - Kind `unscheduled` gives the restart text. Any other kind gives the reset text, whose `{time}` is `<time class="tnum" id="ocu-notice-time" datetime="<lastReset>">`, filled by the script in the browser's zone as hour and minute, like the splash's other times.
    - The value of `since` is never written into the page.
  - **The reset-soon notice under the sign-in card's title** is a warning `.notice`.
    - It is written whenever the reset line is (there is a next reset and an interval), with the `hidden` attribute unless `Settings.ResetSoon()` holds at render.
    - Its countdown and time are spans that the script fills. "in {countdown}" reads with one "in": "The demo resets in 4 min, which may cut your run short. You can start now or come back after 20:00." The countdown is also given in words for assistive technology.
    - The script shows it while `0 < remaining <= 300` s against the reset line's time (after its roll-forward), and hides it otherwise.
    - It is announced once through `#ocu-live` when it appears after the page has loaded.
    - The form, its fields and **Sign in and start** don't change.
  - **Texts and styles.**
    - The new texts are `Splash` parameters, each matched to a new catalog key (`splash.resetNotice`, `splash.restartNotice`, `splash.resetSoon`); the info icon is a non-text parameter.
    - The styles come from `splash.css`, with a `.notice-info` rule on the `inline-notice-info` tokens.
    - `SplashAssets` is regenerated by `web/scripts/tokens.mjs` and `Splash` is recompiled. `SignInAssets` stays byte-identical.
- **The shell's sign-in redirect.** `Shell.Redirect` (the 303 after the sign-in POST) drops every `since` pair from the query and keeps the other pairs, so the signed-in page's address never carries `since`. `FullUrl` and `Error:FullURL` don't change, so a refused sign-in keeps its notice.
- **The countdown pill** is a new component, `web/src/app/header/reset-countdown.ts`.
  - **Placement:** the header's right side, after the drawer Status button and before the Visual Trace button.
  - **When it shows:** only when the snapshot's `onlineDemo` is true and the page has a pending reset.
  - **Visible text:** "Next reset {time} · in {countdown}", aria-hidden, in tabular figures.
    - `{time}` is `pageTime(reset)`.
    - `{countdown}` is `countdownText`'s text without its leading "in ".
    - So it reads "Next reset 16:00 · in 1 h 42 min", "· in 9 min" and "· in 23 s".
  - **Accessible text:** visually hidden, the same pattern with the countdown in words of whole minutes. That is `countdownText`'s spoken form while 60 s or more remain, and "in 1 minute" through the last minute, so it changes only at whole-minute boundaries.
  - **Updates:** within 1 s of each whole-minute boundary, and every second in the last minute.
  - **Classes:** `reset-countdown`, plus `reset-countdown-urgent` while the remaining time is 600 s or less. Styles come only from the `--reset-countdown-*` tokens.
  - **No live region:** no `aria-live`, and no role `timer` or `status`.
- **The pending reset.** The logic is framework-free in `web/src/app/live/reset-schedule.ts`, and a root service, `web/src/app/live/reset-watch.ts`, holds it.
  - It starts from the snapshot's `nextReset`. Every later snapshot and every `reset` event offers a value.
  - An earlier value always replaces it.
  - A later value replaces it only while the page's clock is more than 300 s before it. Once the warning period has begun, the pending reset never moves later.
  - An empty value never replaces it.
- **The switch.** The page enters the resetting view when its clock reaches the pending reset.
  - **When it checks:** on a timer set to the pending reset, on every poll answer, on every change of `LiveState.contact`, and on every 401 from the API.
  - **A 401 at or after the pending reset** enters the view instead of `SessionGate`'s sign-out path.
  - **Entering the view** calls `LiveState.stop()`, so no request under `/ocutalon/api/` follows. It happens once.
- **The resetting view** is a new component, `web/src/app/live/resetting-view.ts`. `app.ts` uses it in place of the whole app: the skip links, header, banners and routed page.
  - **Logo:** the full logo at 320px, from `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png`, with alt "OcuTalon", in the page's theme.
  - **Card:** 400px, with the h1 "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself.", on the splash canvas. Styles come only from the tokens.
  - **Tab title:** "Resetting · OcuTalon".
  - **Focus:** when the switch removed the focused element, focus goes to the view's main region through `shared/focus-rule.ts`. Nothing new is announced.
- **Waiting it out.** The view polls `GET /ocutalon/public/status?t=<n>` at once, then every 10 s, with `fetch`, `credentials: 'omit'`, `cache: 'no-store'` and a 3 s limit.
  - A failed request, a timeout, or an answer that isn't the status JSON counts as not ready, silently.
  - It navigates once, with `location.replace`, to `/ocutalon/?since=<the page's load time>` when an answer has `ready` true and one of these holds:
    - its `lastReset` is strictly later than the load time;
    - the page's clock is at least 15 minutes past the pending reset.

    Then it stops polling.
  - The load time is UTC ISO 8601 to the second. It is captured once, when the page's script starts, and exported together with the address builder in `web/src/app/session/splash-address.ts` for Story 16.4.
- **Source text (Rule 14).** A non-ASCII character in code is written as an escape: the title's middle dot is `·` in TypeScript and `&middot;` in HTML. Comments state the contract, never the history.
- **Runtime targets (Rule 21).**
  - ObjectScript is loaded and compiled on `ocutalon-slot-c` (`OCUTALON`, port 52792) for compile checks only. Check it with `iris_server_info` first.
  - Tests run only on lane C's throwaways, through `ci/iris.sh` and `ci/warm.sh` with the lane's variables.

**Never:**
- **Files.**
  - No edit to any contended path, including:
    - `Live/Payload/Status.cls`, `Test/Live/Status.cls`, `Live/Publish*.cls`, `Data/Time.cls`;
    - `Install/**`, `Test/Install/**`;
    - `web/e2e/demo-path/**`, `web/src/app/{guide,mailbox,phone,feed}/**`;
    - `.github/workflows/**`, `README.md`, `docs/**`;
    - `docker/maintenance.html`, `docker/busy.html`.
  - `Web/Api.cls` and `Core/StatusMonitor.cls` take new methods and their call lines only. No existing line of either is reshaped.
  - `web/playwright.config.ts`, `web/package.json` and `ci/units.sh` don't change: the `online-demo` project picks up the new spec on its own.
- **Behaviour.**
  - No new public text. Every text here is specified in the UX or the acceptance criteria; a needed text that isn't is escalated, never written.
  - Nothing extends a reset. There is no control to postpone one, and no later value replaces a pending reset in its last 5 minutes.
  - The view never opens the WebSocket, calls the API, shows a banner or an error, or navigates twice.
  - The splash never echoes `since`, and a malformed `since` shows nothing.
  - A local or IPM install gets no countdown, notice, `nextReset` key or `reset` event.
  - No handling of a 401 or a changed epoch outside the reset, no place-freed notice and no idle cap. These are Story 16.4's.
- **Out of scope:**
  - the host's reset schedule, serving the maintenance page, and passing `lastReset` (Story 29.3);
  - the `allowance` condition (Story 16.9).

## I/O & Edge-Case Matrix

Where each row runs:
- **ObjectScript, on lane C's warm or fresh throwaway:** rows 1 to 9.
- **Node (`npm --prefix web test`):** rows 10 to 12.
- **Playwright on the `online-demo` unit's fresh flag-on throwaway:** rows 13 and 14.
- **Playwright on the flag-off `sign-in` unit:** row 15.
- **The `online-demo` unit itself:** row 16.

Any test whose outcome depends on how near a reset is sets the anchor relative to the current time and puts it back. It never relies on the fixed 2026-10-18 anchor, so a run near a 4-hour boundary can't flip it.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | One UTC helper (DW-235; AC 6) | `ToSeconds` of `2026-10-18T00:00:00Z`, `2026-12-31T23:59:59Z`, `""`, `2026-10-18T00:00:00` (no Z), `2026-10-18T00:00:00.5Z`, `2026-02-30T00:00:00Z`, `x`; `Shift` across a day and a year, by a negative amount, and of an unreadable time | Round trip `FromSeconds(ToSeconds(t)) = t`; "" for every malformed input, never an error; `Shift` matches the old `AddressCounter.Shift` results. `AddressCounter.Shift` and `SessionEvents.CookieExpiry` give their old results (the existing rows stay green), and neither method's implementation holds `$ZDateTimeH` | -- |
| 2 | The schedule ignores the last reset (AC 1) | Anchor `2026-10-18T00:00:00Z`, interval 4; `lastReset` and `lastResetKind` set to `2026-10-18T05:13:00Z` `unscheduled`, then cleared | `NextReset("2026-10-18T05:30:00Z")` is `2026-10-18T08:00:00Z` in both states. `SecondsToReset` and `ResetSoon` at `07:55:00Z` (300 s left) are 300 and 1; at `07:54:59Z` 301 and 0; at `08:00:00Z` the next slot (14400 s) and 0. No anchor gives "" and 0 | -- |
| 3 | The same next reset everywhere (AC 1) | Flag "1", anchor about now + 1 h, interval 4, read-only account set | `Status.Body().nextReset` = `StateBody(session).nextReset` = the `reset` payload that the StatusMonitor probe publishes after the anchor changes, and `CookieExpiry` of it is the cookie form of the same time. `/state`'s keys are the local keys, then `traceAccount`, then `nextReset`, which is last | -- |
| 4 | Local keeps its snapshot (AC 2) | Flag "0" with an anchor set; then flag "1" with no anchor | Neither `/state` has a `nextReset` key; the local key list is unchanged; `status` has no `resetSoon` | -- |
| 5 | `resetSoon` and `reset` through StatusMonitor (AC 1, 3) | Probe `StatusMonitorProbe` on a fixture stream, flag "1", anchor now + 3600 s. Run 1; anchor to now + 120 s, run 2; run 3 unchanged; anchor to now + 3600 s, run 4; anchor to now + 120 s and flag "0", run 5 | Run 1 publishes nothing (silent). Run 2 publishes `status` `{condition: resetSoon, active: true}` (no slots) and `reset` `{nextReset: now + 120 s}`. Run 3 publishes nothing. Run 4 publishes `resetSoon` `active: false` and `reset` with the new time. Run 5 publishes nothing: `resetSoon` stays inactive with the flag off, and no `reset` is published with the flag off. `StateBody`'s `status` holds `resetSoon` last while it is active, and not otherwise | Settings put back and read back; the fixture stream's events and counter removed |
| 6 | The after-reset notice (AC 4) | Splash rendered with `since` earlier than `lastReset`, kind `scheduled`; the same with kind `unscheduled`; `since` equal to `lastReset`; `since` later; `since` malformed (no Z, `<script>`, empty); no `lastReset`; the local sign-in page with the flag off | Scheduled: one `inline-notice-info` before `.splash-cards` with the reset text and `<time ... datetime="<lastReset>">`. Unscheduled: the restart text. Every other case: no info notice. The page never contains the `since` value, and the local page is byte-identical to before | -- |
| 7 | The reset-soon notice (AC 3) | Anchor now + 120 s; anchor now + 3600 s; no interval | 120 s: the warning `.notice` right after the sign-in card's `h2`, not hidden, with the countdown spans (visible and spoken) and `<time datetime="<next>">`. 3600 s: the same element with `hidden`. No interval: no reset line and no notice. The form, its fields and the button are unchanged in every case | -- |
| 8 | The redirect drops `since` (AC 4) | `Shell.Redirect` for `/ocutalon/` with query `since=2026-10-25T07:49:30Z`; with `x=1&since=...&y=2`; with `since` twice; and the existing cases | `Location` is `/ocutalon/`; `/ocutalon/?x=1&y=2`; `/ocutalon/`. The existing redirect cases are unchanged | -- |
| 9 | Texts (AC 3, 4) | `Test.Web.PublicTexts`, `Test.Msg.Catalog` | `RESETNOTICE`, `RESTARTNOTICE` and `RESETSOON` equal `splash.resetNotice`, `splash.restartNotice` and `splash.resetSoon` with placeholders verbatim, and the info icon is classified as not text. Counts: compared 37 to 40, notText 27 to 28; catalog Core 90 to 93, total 112 to 115 | -- |
| 10 | The pill's texts (AC 2) | Remaining 1:42:30, 10:00, 10:01, 1:00, 0:59, 0:23, 0:01; `onlineDemo` false; no reset | Visible: "Next reset {t} · in 1 h 42 min", "· in 10 min" (urgent), "· in 10 min" (not urgent at 10:01), "· in 1 min" (urgent), "· in 59 s", "· in 23 s", "· in 1 s". Spoken: "in 1 hour 42 minutes", "in 10 minutes", "in 10 minutes", "in 1 minute", then "in 1 minute" for every second of the last minute. Not shown without `onlineDemo` or a reset | -- |
| 11 | The pending reset and the switch (AC 1, 4) | Pending T. Offered T - 1 h; T + 4 h at T - 6 min; T + 4 h at T - 5 min; T + 4 h at T + 10 s; `""`. Then the clock at T - 1 s and at T; a 401 at T - 10 s and at T + 2 s; contact `reconnecting` at T + 1 s | The pending reset becomes T - 1 h, then T + 4 h, and is kept for the next two offers and for `""`. The switch is false at T - 1 s and true at T. A 401 at T - 10 s goes to `SessionGate`'s path; a 401 at T + 2 s and lost contact past T enter the view. Entering happens once | -- |
| 12 | Waiting it out (AC 4) | Load time L, pending T. Status answers in turn: a network error, a timeout, HTML (the maintenance page), `{ready:false}`, `{ready:true, lastReset: <before L>}`, `{ready:true, lastReset: T}`; a variant where `{ready:true, lastReset: <before L>}` repeats until T + 15 min | One poll at once and then one every 10 s. Each poll is GET with no credentials and `no-store`. No navigation until the answer with `lastReset` T, then exactly one navigation to `/ocutalon/?since=<L to the second, Z>`, and polling stops. In the variant it navigates once at the first ready answer at or after T + 15 min. Nothing is shown or announced for a failed poll | -- |
| 13 | The last 10 minutes, controlled (AC 2 to 5) | The flag-on stack, signed in from the splash. The browser clock is installed at T - 10:30, where T is the stack's `lastReset` read from IRIS. Routes: `/api/v1/state` (the real answer with `nextReset` T and any real `resetSoon` removed), `/api/v1/events` (real answers with any real `reset` or `resetSoon` removed, plus one `status` `resetSoon` active event once the clock passes T - 5:00), and `/ocutalon/public/status` (HTML, then `{ready:false}`, then ready with an old `lastReset`, then ready with `lastReset` T) | At T - 10:30 the pill reads "in 10 min" and is not urgent; at T - 10:00 it is urgent. At T - 5:00 the `resetSoon` banner appears in the catalog's order and is announced once. In the last minute the pill ticks every second while its accessible text stays "in 1 minute". At T the resetting view shows its texts, the 320px logo and the title "Resetting · OcuTalon", with no header and no banners, and none of the page's own requests (`page.on('request')`) goes to `/ocutalon/api/` after that. The status polls carry no `Cookie` header. The test ends the CSP session, as a reset would. There is no navigation on the old `lastReset`; on `lastReset` T there is exactly one navigation to `/ocutalon/?since=<load time>`, where the real splash shows "The demo was reset at {T in the browser's zone}, which cleared your session. Sign in again for a fresh one." above both cards. There is no second navigation within the next 30 s of clock | Routes removed and the group signed out in `finally` |
| 14 | The real server, a reset 4 minutes away (AC 1 to 3) | The real clock. The test reads the public anchor, sets it to now + 4 min (to the second) and reads it back, then signs in | `/api/v1/state`'s `nextReset` equals `/ocutalon/public/status`'s and the anchor, and its `status` contains `resetSoon`. The pill is urgent and reads "in 3 min" or "in 4 min". The `resetSoon` banner is shown. In a fresh context the splash shows the reset-soon notice under the sign-in card's title, not hidden, and signing in from it still opens the page | The anchor is put back and read back, and every context signs out, in `finally` |
| 15 | Local install (AC 2) | The flag-off stack's main page (`web/e2e/frame/frame.spec.ts`) | No `.reset-countdown` element, and no resetting view | -- |
| 16 | A run never meets a reset | `docker/tests/test-online-demo.sh` start values | The anchor is computed at the unit's start as now + 2 h, to the minute, and stays quoted in the override. Row 2's check (a 4-hour step of the anchor, later than now, at most 4 h away) still passes, and so do every 16.1 to 16.6 row and the restart row. The browser step therefore never meets a real `resetSoon` period or a real reset | -- |

</intent-contract>

## Code Map

**Server, the schedule and DW-235:**
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls`:
  - `KEYS` :9; `NextReset` :60-75;
  - the private `UtcNow` :89, `ToSeconds` :95-99 and `FromSeconds` :101-104, which become the public helper; `UtcNow` stays private.
  - The class may reference only `$SYSTEM.Status` and ObjectScript functions (AD-3; its comment :1-4).
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`: `Shift` :82-89 becomes the delegate. Its callers: :31 and :72, `Web/SessionEvents.cls:78`, `Test/Web/Install.cls:128`, `Test/Data/AddressCounter.cls:182` and `Test/Web/SessionEvents.cls:233`.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`: `CookieExpiry` :110-118. It keeps reading `Data.Time`'s `WEEKDAYS` and `MONTHS` (read only).
- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls:122-136` (read only): the `time` and `kind` rules that the start values pass.
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls` (read only): `Body` :57-66 already gives `nextReset`, `lastReset` and `lastResetKind`, null when unset.

**Server, the condition and the event:**
- `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls`:
  - `OnProcessInput` :25-56, where the `resetSoon` call line goes after :30, and the reset publish after the loop;
  - `Remembered` :23, `LOGPUBLISH` :18, and the seams `Readings` :59 and `Stream` :65;
  - the class comment :1-12 names the new duties.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls` (read only, contended):
  - `CONDITIONS` :9, where `resetSoon` is last;
  - `Computed` :45-51 and `Active` :56-60;
  - `ActiveOf` :63-74, which is reused;
  - the private `DailyCap` :77-90 is the shape that `ResetSoon` follows.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Reset.cls` (read only): `NextReset`. `reset` is already in `Live.Publish`'s TYPES, `payloads.ts` and `Test/Live/Payloads.cls:13`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `StateBody` :273-313. The status line is :308 and the `traceAccount` line :309. The new call lines go after :309, because Epic 4 inserts `guide` after :308.
  - The comment :263-272 names `nextReset`.
  - `TraceAccount` :248-255 is the pattern for an online-only key.
- Spine event table, line 1110: `status` and `reset` are both published by `StatusMonitor`.

**The splash and the shell:**
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - the parameters :22-91, including `ICONWARNING`;
  - `OnLoginPage` :117-193: `.lead` :152, `.splash-cards` :153, the sign-in card's `h2` :155, the Visual Trace warning `.notice#ocu-warning` :166, the field error :168-170, and `#ocu-live` :189;
  - `ResetLine` :215-228: the `#ocu-reset-time` `datetime` and `data-step`, and the countdown spans.
  - It reads the request through `$Get(%request.Data(...,1))` (:122, :131, :134).
- `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls:55-86`: the CSP header and the compile-time `StyleHash` and `ScriptHash`. `Splash` inherits `CSS` and `SCRIPT` from `SplashAssets` (`Splash.cls:19`).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`:
  - `Login` :47-58 reaches the splash in the same request, so `since` is in `%request.Data`;
  - `Redirect` :93-97;
  - `FullUrl` :141-145, which stays as it is.
- `web/src/signin/splash.js`:
  - `announce` :32 (the `#ocu-live` region) and `fill` :103;
  - `countdown` :109-131, which gives "in {n} s", "in {n} min" and "in {h} h {m} min" with spoken forms;
  - `timeFormat` :133;
  - `startCountdown` :137-172, which ticks each second and rolls forward by `data-step`;
  - `fillErrorTime` :174-184.
  - `web/scripts/announce-focus-sources.test.mjs:119` pins one focus call in this file.
- `web/src/signin/splash.css:173-186` `.notice` (warning tokens). The `inline-notice-info` tokens are in DESIGN.md:234-239, and the Angular counterpart is `web/src/app/shared/inline-notice.ts:59-63`.
- `web/scripts/tokens.mjs`: it writes `tokens.css`, `SignInAssets.cls` and `SplashAssets.cls`, inlines only the tokens a stylesheet uses, and `--check` fails when any of them is stale (:364-370, :421-454).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: `splash.resetLine` :469-473 is the shape for the new keys (slots typed `text`, and a `source`); `banner.resetSoon` :314-318 already exists.
- The UX texts:
  - EXPERIENCE.md:342: "The demo was reset at {time}, which cleared your session. Sign in again for a fresh one."
  - EXPERIENCE.md:343: "The demo was restarted, which cleared your session. Sign in again for a fresh one."
  - EXPERIENCE.md:346: "The demo resets in {countdown}, which may cut your run short. You can start now or come back after {next reset time}."
  - EXPERIENCE.md:115: the reset-soon notice sits under the card title.

**The page:**
- `web/src/app/app.ts:22-27` (the template) and :47-49 (`LiveState.load()`). Hash routing is one wildcard route (`app.config.ts:11, 18`), and the title is only `<title>OcuTalon</title>` (`web/src/index.html:5`).
- `web/src/app/header/header.ts`: the right side `.side.right` :91; the drawer Status button :92-108; the Visual Trace button :109. `snapshot()?.onlineDemo` is read at :369-375.
- `web/src/app/chat/page-time.ts`:
  - `pageTime` :27;
  - `WHEN_TEXTS` :82-100;
  - `Countdown` :160 and `countdownText` :170-194: seconds rounded up, minutes rounded down, "in 0 s" past due.
- `web/src/app/rail/status-rail.ts:44-45, 99-102, 176-178, 235-243`: the visible countdown with `aria-hidden` beside a visually hidden spoken one, `tabular-nums`, and the tick signal with `setInterval` in an effect with `onCleanup`. This is the pill's pattern.
- `web/src/styles/tokens.css:499-507` (dark :753-756 and :976-979): the `--reset-countdown-*` and `--reset-countdown-urgent-*` tokens, generated and not yet used. `base.css` has `.tabular` :141 and `.visually-hidden` :129.
- `web/src/app/live/live-state.ts`: `snapshot`, `status`, `store` and `contact` :79-88; `load` :97; `stop` :132-140; the poll :220-260, where an epoch change reloads at :248-254.
- `web/src/app/live/contact-watch.ts:16-25`: `reconnecting` after 10 s and `unreachable` after 30 s.
- `web/src/app/live/live-store.ts`: the `reset` collection :54, `LiveStore.reset` :84, cleared at :125 and stored at :182-183.
- `web/src/app/live/payloads.ts:217-219` `ResetPayload { nextReset?: string }` (generated; no change).
- `web/src/app/api/api-types.ts`: `StateSnapshot` :32-52 (`traceAccount?` :51) gains `nextReset?: string`; `PublicStatus` :78-84.
- `web/src/app/api/envelope.interceptor.ts:27-45`: a 401 calls `SessionGate.onSignedOut`.
- `web/src/app/session/session-gate.ts:26-33` `onSignedOut`: stop, then `location.replace('/ocutalon/?signedOut=1' + hash)`.
- `web/src/app/live/demo-busy-state.ts:9, 15, 69-78`: the sibling status reader. It uses `HttpClient` with a 3 s `timeout`, and is not reused (Design Notes).
- `web/src/app/banners/banner-view.ts`:
  - `BANNERS` :66-77, whose `resetSoon` row :75 is already warning and closable;
  - the close signature `id|slots` :161-163 and `retainClosed` :208.
  - `banner-stack.ts:208-238` announces a new banner once after the first snapshot. Nothing changes in the banners.
- `web/src/app/shared/announcer.ts:31`; `web/src/app/shared/focus-rule.ts:28-33, 53`, whose fallback goes to `main.main` (:6).
- `web/scripts/brand.mjs:12-19`: `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png` (640×357). `docker/maintenance.html` (read only) holds the title :17, the logo :70, the texts :72-73, `meta refresh` 10 s :16 and the card at 400px.

**Tests:**
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls`: `TestNextReset` :91-121 (`$ClassMethod(accessor, "NextReset", now)`).
- `src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitor.cls` (read only, the pattern for row 5):
  - the probe through `Ens.Host.GetShadowInstance("class||OcuTalon.Test.Core.StatusMonitorProbe")` and `StreamRef` :266-271;
  - events read with `Live.Event.Since(stream, 0, 200, "session")` :291;
  - cleanup :301-306;
  - `Test.Core.Observe.RemoveWarnings` :52.
  - `StatusMonitorProbe.cls:10-28` overrides `Readings` and `Stream`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - `TestStateBody` :122 pins the local key list;
  - `TestStateTraceAccount` :1253-1287 has `traceAccount` last. It stays green because a shard throwaway has no anchor, so there is no `nextReset`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls`: `TestPage` :114 (markup); `OnBeforeOneTest` :442-457 (fixed anchor 2026-10-18, interval 4); `Render` :505-548, which gains a query argument.
- `src/ocutalon/cls/OcuTalon/Test/Web/Shell.cls`: `TestRedirect` :94-101 and the `Redirect(url, query)` helper :144-152.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`: `XData Classified` :142-169 and the counts :39, :82-84.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: the counts :3, :80-83 and :121; keys from :952 (`splash.*` :1020-1044); fixtures from :1181 (`splash.resetLine` :1261).
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`: `TestReferencesOnlyThePublicAllowList` :205-244 covers the new public methods. The status keys :36 and :63 are unchanged.
- `web/scripts/*.test.mjs`, run by `node --test`; `fake-clock.mjs:9`:
  - `page-time.test.mjs`;
  - `ux-strings.test.mjs`: `IMPORTED` :41-51 and `SOURCES` :143. Kinds are `ux` (EXPERIENCE.md verbatim) and `ac` (a story's criteria).
  - `host-pages.test.mjs:98-116`: the maintenance texts, title and logo.
  - `announce-focus-sources.test.mjs`: no `aria-live` or role `timer`/`status` :44-49; header files silent :91-93; the exact speaker list :97-106 and focus-call list :112-118, :137.
  - `shell-styles.test.mjs`: every `var(--x)` must exist.
  - `live-store.test.mjs:213-218` (`reset`).
- `web/e2e-online/`:
  - `support.ts`: `signOutGroup` :24, `signInFromSplash` :45, `publicValue` and `setPublic` :162-168, `readStatus` :184. `fixtureUser` and `irisScript` are in `web/e2e/support/iris.ts:35, 59`.
  - `splash.spec.ts:153-215`: the clock pattern (`install`, `pauseAt`, `runFor`) and `since` at :477.
  - `busy.spec.ts:258-323`: `page.route` stubs of the public status (JSON, abort, HTML, no answer) and `unrouteAll` :283.
  - `demo-account.spec.ts:115-116`: `traceAccount` is the last key, which changes to "then `nextReset`".
- `web/e2e/`:
  - `support/clock.ts` `runUntil` :109 and `freeze` :135;
  - `banners.spec.ts:323-386` (`resetSoon` on the local stack) and the events stubs :613, :949, :1004;
  - `frame/frame.spec.ts:104, 127-161` (header).
- `web/playwright.config.ts:47`: the `online-demo` project, `testDir ./e2e-online` with no `testMatch`. `web/scripts/playwright-projects.test.mjs:195-201` lists the files on disk, so a new spec passes it.
- `docker/tests/test-online-demo.sh`:
  - the `anchor` :102 and `last_reset` :103 start values, quoted in the override at :136;
  - row 2's verdict :203-233 (the step check :220);
  - row 11's status keys :590-596;
  - `run_e2e` :844-855, which runs every `web/e2e-online` spec;
  - `MEASURED` lines are echoed at :867.
- `ci/units.sh`: `online-demo` is the last unit of group `image` (:35); `BROWSER_UNITS` (:41); shard `lane-b` holds `Test.Web.*`, `Test.Data.*`, `Test.Core.*`, `Test.Live.*` and `Test.Msg.*`, discovered automatically.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement). Print each result as a `MEASURED` line in the unit or the Playwright log, and revert any temporary diagnostic byte-identical:
  - (a) A sessionless `GET /ocutalon/?since=2026-01-01T00:00:00Z` on the flag-on throwaway reaches `Splash` with `%request.Data("since",1)` set (the info notice of row 6 renders there).
  - (b) Playwright's installed clock carries across the view's `location.replace` to the splash: the splash's script reads the controlled time.
  - (c) The view's status polls carry no `Cookie` header.
  - (d) DW-220: the `online-demo` unit's time with the new spec. It was 310 to 325 s locally before this story.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- public `ToSeconds`, `FromSeconds` and `Shift`; `NextReset` through them; `RESETSOONSECONDS`, `SecondsToReset(now)` and `ResetSoon(now)` -- one UTC helper, and the reset-soon rule for both the splash and `StatusMonitor` (DW-235; rows 1 and 2).
- [ ] `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls` -- `Shift` becomes `Quit ##class(OcuTalon.Data.Public.Settings).Shift(utc, seconds)`, with its comment unchanged in meaning -- DW-235.
- [ ] `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls` -- `CookieExpiry` parses with `Settings.ToSeconds` (day number `seconds \ 86400` for the weekday), with no `$ZDateTimeH` of its own -- DW-235.
- [ ] `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls` -- the new class method `ResetSoon(now)`; a call line after `Computed` that inserts it; a private `PublishReset(stream)` (remember, compare, publish `reset`, log failures) called after the conditions loop, with its remembered value in a new private property; the class comment -- AC 1 and 3 (rows 3 and 5).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- a new private method that appends the active `resetSoon` (through `ActiveOf`) and sets `nextReset` on the online demo; one call line after the `traceAccount` line (:309); the `StateBody` comment -- AC 1 and 2 (rows 3 and 4).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` -- the parameters `RESETNOTICE`, `RESTARTNOTICE`, `RESETSOON` (with `{time}` and `{countdown}`) and `ICONINFO`; private `InfoNotice()` and `ResetSoonNotice()`, written at the two places in Boundaries -- AC 3 and 4 (rows 6 and 7).
- [ ] `web/src/signin/splash.css` and `web/src/signin/splash.js`, then `node web/scripts/tokens.mjs` to regenerate `src/ocutalon/cls/OcuTalon/Web/Public/SplashAssets.cls`:
  - the CSS gains `.notice-info`;
  - the script fills `#ocu-notice-time` and the reset-soon notice's time and countdown;
  - it shows and hides the notice each tick from the reset line's time;
  - it announces the notice once when it appears after load.

  `SignInAssets.cls` stays byte-identical -- AC 3 and 4.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- `Redirect` uses a new private `RedirectUrl()`, which is `FullUrl` minus every `since` pair -- no stale notice on a later reload (row 8).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- the keys `splash.resetNotice` (slot `time`), `splash.restartNotice` and `splash.resetSoon` (slots `countdown` and `time`), with EXPERIENCE.md's texts and their `source` (footprint extension) -- row 9.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls` -- rows 1 and 2, including a check that the implementations of `AddressCounter.Shift` and `SessionEvents.CookieExpiry` (read from `%Dictionary.MethodDefinition`) hold no `$ZDateTimeH`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/ResetSchedule.cls` (new) -- rows 3 to 5, through `Status.Body`, `Api.StateBody`, `StatusMonitor.ResetSoon` and the existing `StatusMonitorProbe` (read only). It saves and puts back every public key it sets, and removes its fixture stream and session.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` -- `Render` gains a `query` argument; rows 6 and 7. Every case that depends on whether the reset is near sets the anchor relative to now.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Shell.cls` -- row 8.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` and `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- the new parameters and keys, their fixtures and the counts (row 9; the catalog test is a footprint extension).
- [ ] `web/src/app/chat/page-time.ts` -- a new export that gives the spoken countdown in whole minutes, "in 1 minute" through the last minute, built on `countdownText` (footprint extension) -- row 10.
- [ ] `web/src/app/session/splash-address.ts` (new) -- the page's load time, captured once at module start, and `splashAddress(loadedAtMs)`, which gives `/ocutalon/?since=<UTC ISO 8601 to the second>` -- for this story's view and Story 16.4.
- [ ] `web/src/app/live/reset-schedule.ts` (new, framework-free, with timers and `fetch` injected):
  - the pending-reset rule;
  - the "due" rule;
  - the poller and its navigation rule, with `RESET_SOON_MS` 300 000, `RESET_WINDOW_MS` 900 000, `RESET_POLL_MS` 10 000 and `STATUS_LIMIT_MS` 3 000;
  - the texts `RESET_TEXTS`: the countdown pattern, the heading, the body and the title.

  Rows 11 and 12.
- [ ] `web/src/app/api/api-types.ts` -- `nextReset?: string` on `StateSnapshot`.
- [ ] `web/src/app/live/reset-watch.ts` (new root service) -- holds the pending reset from `LiveState`'s snapshot and store, owns the `resetting` signal, checks at the moments in Boundaries, enters once, and runs the poller with `globalThis.fetch` and `location.replace` -- AC 4.
- [ ] `web/src/app/live/resetting-view.ts` (new component) -- the view of Boundaries, setting `document.title` while shown -- AC 4.
- [ ] `web/src/app/header/reset-countdown.ts` (new) and `web/src/app/header/header.ts` (place it, one element) -- the pill -- AC 2.
- [ ] `web/src/app/app.ts` -- `@if` the reset watch is resetting, the view; else the existing template (footprint extension) -- AC 4.
- [ ] `web/src/app/session/session-gate.ts` -- `onSignedOut` first asks the reset watch: at or past the pending reset it enters the view and returns -- AC 4 (row 11).
- [ ] `web/scripts/reset-schedule.test.mjs` (new; footprint extension) -- rows 11 and 12 on `fake-clock.mjs`, plus the pill's text and visibility rule (row 10), if it lives in a framework-free module.
- [ ] `web/scripts/page-time.test.mjs`, `ux-strings.test.mjs`, `host-pages.test.mjs` and, as needed, `announce-focus-sources.test.mjs` (footprint extensions) -- each with a short purpose:
  - `page-time`: row 10's spoken forms.
  - `ux-strings`: `RESET_TEXTS` joins `IMPORTED`, with sources: the countdown pattern `ac` (Story 16.8); the heading, body and title `ux` (EXPERIENCE.md:79, :132).
  - `host-pages`: the view's heading, body, title, logo files and width equal the maintenance page's.
  - `announce-focus-sources`: its exact lists, if the view's focus call is new.
- [ ] `web/e2e-online/reset.spec.ts` (new) -- rows 13 and 14 -- AC 1 to 5.
- [ ] `web/e2e-online/demo-account.spec.ts` -- `traceAccount`, then `nextReset` as the last key (:115-116).
- [ ] `web/e2e/frame/frame.spec.ts` -- row 15, one assertion (footprint extension).
- [ ] `docker/tests/test-online-demo.sh` -- the anchor relative to the unit's start (row 16); the header names the new spec; Task 0's `MEASURED` lines.

**Acceptance Criteria:**
- Given the reset interval, anchor and last reset in the public settings, when `/ocutalon/public/status`, `GET /api/v1/state` and `StatusMonitor`'s `reset` event give the next reset, then all three give `Settings.NextReset()`, which is also the resume cookie's expiry. An unscheduled reset (`lastReset` and `lastResetKind` changed) leaves the schedule unchanged, and `/ocutalon/public/status` still reports readiness, the next reset, busy, and the last reset's time and kind, which the splash's notice uses. Rows 2, 3, 5 and 14 hold.
- Given a signed-in page on the online demo, when it shows the header, then the pill reads "Next reset {time} · in {countdown}" in page time with tabular figures. It updates at each whole minute and every second in the last minute, and turns `reset-countdown-urgent` from 10 minutes before. Its accessible text changes only on whole minutes and uses words. Nothing extends the reset, and a local install shows no countdown. Rows 4, 10, 11, 13, 14 and 15 hold.
- Given 5 minutes or less before the reset, when `StatusMonitor` raises `resetSoon`, then the closable warning banner "The demo resets in 5 minutes. Your session and Telegram pairing will be cleared." appears in the banner catalog's order and is announced once. Meanwhile the splash shows the reset-soon notice under the sign-in card's title, and signing in still works. Rows 5, 7, 13 and 14 hold.
- Given the scheduled time arrives, or the page finds itself past it through a late timer, lost contact or a 401, when the page notices, then:
  - it switches once to the resetting view, with the maintenance page's logo, texts and tab title;
  - it stops the live path;
  - it polls `/ocutalon/public/status` quietly, with no credentials;
  - it navigates once to `/ocutalon/?since=<load time>` when status reports ready after the reset;
  - the splash then shows the reset notice, or the restart notice when the kind is `unscheduled`, above both cards;
  - the signed-in address drops `since`.

  Rows 6, 8, 11, 12 and 13 hold.
- Given a Playwright test with a controlled clock and controlled status answers, when it takes a signed-in page through the last 10 minutes before a reset, then the countdown turns urgent at 10 minutes, the banner appears at 5, the resetting view shows at the reset, and the page lands once on the splash with the reset notice when status reports ready. Row 13 holds.
- Given DW-235, when `AddressCounter.Shift` and `SessionEvents.CookieExpiry` move or parse a UTC time, then both use `Public.Settings`' one public helper, give their old results, and keep no parsing of their own. Row 1 holds.

## Spec Change Log

## Review Triage Log

### 2026-10-26 -- Review pass
- verdicts: 42 findings -- high 0, medium 7, low 27, false 8, maybe-false 0
- findings:
  - `low` `reject` (blind) Browser clock decides the switch; no skew correction -- the pill, the switch and `since` use the page's clock by the Times convention and the spec's Decided in-stage; a skewed clock shows the time it believes. Not worth a server-time channel.
  - `low` `reject` (blind) The resetting view cannot be left for up to 15 minutes if the schedule moves -- AD-25 bounds the reset at 15 minutes and the view exits on the first ready answer after that; a schedule changed inside the warning period is an operator action.
  - `false` `reject` (blind) `Settings.ToSeconds` is strict and may silently disable a hand-set anchor -- matrix row 1 requires exactly the `Public` step's `time` rule, which is also what stores the anchor.
  - `low` `reject` (blind) A throwing `ResetSoon()` suppresses the other conditions of the run -- `ResetSoon` and `NextReset` catch their parsing and cannot throw on stored text; a guard would be speculative.
  - `medium` `patch` (blind) No test for the 401 at or after the reset -- R3 added (mutation line written).
  - `low` `reject` (blind) `RedirectUrl` compares the raw key, so `?%73ince=` is not stripped -- needs a hand-built address and the only consequence is a `since` in the signed-in address that nothing reads.
  - `low` `reject` (blind) R2's thin timing margin and a left-over anchor if it dies -- row 14 mandates a four-minute reset; the finally restores the anchor and the case passed in every run.
  - `low` `patch` (blind) The comment at `docker/tests/test-online-demo.sh:72` still names the fixed anchor -- reworded to the computed anchor.
  - `low` `reject` (blind) `ResetSoonNotice` depends on the literal `in {countdown}` -- `Test.Web.PublicTexts` and `TestResetSoonNotice` fail at once if the catalog text changes.
  - `low` `reject` (blind) `InSeconds` copied in two test classes (and the time arithmetic in two others) -- a four-line private helper; sharing it would couple two test classes for no gain.
  - `false` `reject` (edge) `ResetWatch` is not gated on `onlineDemo` -- `nextReset` is in the snapshot and the `reset` event is published only on the online demo (`Api.AddReset`, `StatusMonitor.PublishReset`).
  - `low` `reject` (edge) The 15-minute window sits behind `ready` in `shouldNavigate` -- by design (matrix row 12: navigate on a ready answer); a demo that is not ready would land the visitor on the maintenance page.
  - `low` `reject` (edge) A failed first run makes the next run publish a `reset` event -- the event carries the same time every page already holds; pages ignore an equal offer.
  - `low` `reject` (edge) `Do conditions.Insert(..ResetSoon())` inside the one Try -- same as the blind finding on a throwing `ResetSoon`.
  - `low` `reject` (edge) Browser versus server clock skew -- same as the blind finding.
  - `low` `reject` (edge) R2 anchor margin against its 240 s timeout -- same as the blind finding.
  - `low` `reject` (edge) `anchor=$(node ...)` could print nothing -- the unit already needs node for every browser step, and the row 2 step check would name the empty anchor.
  - `low` `reject` (edge) The reset-soon notice reads with empty spans where scripting is off -- the splash fills every time and countdown in script (the reset line and the too-many error do the same).
  - `false` `reject` (edge) `ToSeconds` dropped the old tolerance -- same as the blind finding on strictness.
  - `low` `reject` (edge) `FromSeconds` is unguarded for a huge interval -- it was outside the old `Try` too (pre-existing), and `Shift` is guarded.
  - `low` `patch` (edge) The stale anchor comment in the unit -- fixed with the blind finding.
  - `medium` `patch` (gap) The 401 and lost-contact entry paths of `ResetWatch` have no test -- R3 (401) and R3b (contact) added, each with a mutation line.
  - `medium` `patch` (gap) The `reset` event's wiring into the pending reset has no test -- R4 added, with a mutation line.
  - `medium` `patch` (gap) The splash script's reveal, hide and announce-once has no test -- R5 added, with a mutation line.
  - `medium` `patch` (gap) R1's "no Cookie header" assertion cannot fail at a routed request -- removed; `credentials: 'omit'` stays pinned by the Node test of row 12 (Decided in-stage).
  - `low` `reject` (gap) A failed `reset` publish and its retry are untested -- it mirrors the existing condition publisher's rule and is not an acceptance criterion.
  - `low` `reject` (gap) `TestUtcHelper` proves the absence of `$ZDateTimeH` by source text -- the spec asks for exactly that check, and runtime assertions sit beside it.
  - `low` `reject` (gap) `host-pages.test.mjs` checks the view's logo and card by regex -- R1 measures the same at runtime; the regex only adds the file names.
  - `low` `reject` (gap) R1's negative assertions use fixed sleeps -- weak, not vacuous: the navigation would come on the answer's tick.
  - `false` `reject` (gap) R1 relies on the unit's start values for `lastReset` -- it asserts that `lastReset` parses, so it fails loudly without them.
  - `low` `reject` (gap) Row 16 has no pinning check -- the unit's anchor is one line and its existing step check runs; a shorter lead would show as a failing spec.
  - `low` `reject` (gap) `PublishReset` sub-behaviours have no mutation lines of their own -- Rule 19 asks one demonstrated mutation per AC, and AC 1 has three.
  - `low` `reject` (intent) `PublicTexts` notText is 29, not row 9's 28 -- `RESETSOONSECONDS` is a class parameter; recorded under Decided in-stage.
  - `low` `reject` (intent) The sign-in redirect dropping `since` is pinned at class level only -- `Shell.Redirect` is the code that drops it and `TestRedirectDropsSince` runs it.
  - `medium` `patch` (intent) The 401 and lost-contact paths are tested nowhere -- R3 and R3b.
  - `false` `reject` (intent) Row 15: `ResetWatch` is not gated on the flag -- the server sends no `nextReset` with the flag off.
  - `medium` `patch` (intent) The splash script's hide, reveal and announcement are untested -- R5.
  - `false` `reject` (intent) R1 fabricates the answers -- row 13 specifies controlled answers.
  - `false` `reject` (intent) Row 16 is not visible in the diff -- the anchor line is in the unit script, which the diff shows.
  - `low` `reject` (intent) Doc comments of `Api.cls` and `StatusMonitor.cls` were reworded -- they describe the new behaviour; the ruling protects other epics' entries and lines of behaviour.
  - `false` `reject` (intent) `NextReset` now returns "" unless the value is exactly `YYYY-MM-DDThh:mm:ssZ` -- row 1 names this strictness.
  - `low` `reject` (intent) `PublishReset` remembers the value when the flag is off or the value is empty -- intended: a later change is compared with what the last run saw.

## Design Notes

**Architecture decisions:**
- **AD-12.**
  - `resetSoon` is in the closed catalog and is computed on read in `/state` and published by `StatusMonitor` as a full view: one method serves both.
  - `reset` and `status` have one publisher, `StatusMonitor` (event table, line 1110).
  - The online demo only polls; the view never opens the WebSocket.
- **AD-13.**
  - The public status endpoint is sessionless and unchanged.
  - The splash is server-rendered and takes its notice from `?since=` against the public `lastReset` ("When the page returns to the splash after a 401 or a changed epoch, it passes the time it loaded", line 374).
  - The splash's one hash-pinned script, with no `style=`, is kept, and so is the `Login` form contract.
- **AD-19:**
  - every public value, and the next reset, come only through `OcuTalon.Data.Public.Settings`;
  - "the accessor also computes the next reset";
  - the time left and "reset soon" are computations of the same accessor.
- **AD-25:**
  - the host owns the schedule and passes the interval, the anchor, and the last reset's time and kind;
  - an unscheduled reset doesn't shift the schedule;
  - the maintenance page is the host's twin of the resetting view;
  - the reset window is at most 15 minutes.
- **AD-3:** the public packages reference only their allow-list. The helper lives in the accessor, so `Data.Public` still holds only the accessor, and `Test.Web.Status`'s scan covers the new public methods.
- **AD-4:** the resume cookie expires at the next reset, and the reset ends every session.
- **AD-33 and AD-29:** Lane B's files; contended files are read only.
- **AD-22:** tests run on throwaways only.
- **Conventions:**
  - "Times": UTC ISO 8601 to the second, so string order is time order, and `since` is written to the second.
  - "Announcements and focus" names Story 16.8: the view uses the focus rule and adds no speaker.
  - "Angular": standalone components and signals.
  - "Shared look outside Angular": the maintenance page stays self-contained, and the view uses the tokens.
- **No conflicts.** No acceptance criterion contradicts an AD's Rule, and no NFR is unmeasurable.
  - `StatusMonitor`'s 15 s `CallInterval` (AD-18) bounds when the banner appears after the 5-minute mark. A page that loads inside the period sees `resetSoon` at once, because `/state` computes on read.
  - The 1280×600 fold rule binds the splash's normal state only (DESIGN.md:700). The notices are other states, so the fold checks of Stories 16.2 and 16.5 keep their normal state. Row 16 keeps a real `resetSoon` period out of the unit.

**Decided in-stage:**
- **DW-235's helper is three public class methods of `Public.Settings`, not a new class.**
  - AD-3 describes `OcuTalon.Data.Public` as "the public-settings accessor", and the ledger's routing note names `Public.Settings`.
  - The strict form is the `Public` step's own `time` rule, so `NextReset` keeps every result for an accepted value.
  - `AddressCounter.Shift` stays as a delegate, so that its callers (three test classes and `SessionEvents`) and other epics' merges are untouched.
- **`resetSoon` is built in `StatusMonitor.ResetSoon`, not in `Live.Payload.Status.Computed`**, which is contended (Epic 8). Two call lines, one in `StatusMonitor` and one in `Api`, keep one computation. `resetSoon` is last in `CONDITIONS`, so appending keeps the catalog order whatever Epic 8 adds to `Computed`.
- **One threshold, 300 s or less, for the banner and the splash.** The criteria say "5 minutes remain" and "less than 5 minutes remain"; one rule means the banner and the splash never disagree, and the difference is one second.
- **The `reset` event:** published on change only, the first run silent, never empty, the online demo only, like the conditions' remembering.
- **`/state`'s `nextReset` is the last key, after `traceAccount`.** Epic 4 inserts `guide` after `status` (:308); a call line after :309 keeps the two insertions in separate hunks. It is present only on the online demo with a schedule, like `traceAccount`.
- **The pending reset never moves later inside its last 5 minutes.**
  - At the scheduled time the old instance's `NextReset` rolls forward to the next slot. `StatusMonitor` then publishes it within 15 s, and a reloaded snapshot carries it too.
  - A page whose clock is a few seconds behind would otherwise follow the later value and never switch.
  - This is the criterion's "nothing extends the reset", applied to the page.
- **The switch is "the page clock is at or past the pending reset", checked on a timer, every poll answer, every contact change and every 401.**
  - The criterion's window starts at the scheduled time, so lost contact inside it is past the pending reset by definition. The extra checks make it work when timers were suspended (a sleeping laptop, a throttled tab), and stop a 401 after the reset from sending the page to the sign-out path.
  - A 401 before the pending reset is Story 16.4's.
- **"When the demo is ready" means ready after the reset:** `ready` true with `lastReset` later than the page's load time. This is what makes the splash it lands on show the reset notice (AC 5), and it keeps the view waiting while an old instance still answers past its scheduled time.
  - At 15 minutes past the pending reset (AD-25's window), any `ready` answer navigates, so a failed or late reset never strands the page. That splash shows no notice.
- **The poll** runs every 10 s (the maintenance page's refresh, and 16.5's recheck), with a 3 s limit, `fetch` with `credentials: 'omit'` (the criterion's "without a session", taken literally) and `no-store`. Any answer that isn't the status JSON counts as not ready, because during a reset the host answers with the maintenance HTML.
- **`{next reset time}` becomes the slot `time`** in the catalog and the `Splash` parameter; the rendered text is the UX's.
- **"in {countdown}" carries one "in".** The countdown forms of `page-time.ts` and `splash.js` already start with "in", so the pill's `{countdown}` is that form without its "in ", and the splash's span replaces "in {countdown}". The fixture "Next reset 16:00 · in 1 h 42 min" and the mockup's "resets in 4 min" both hold.
- **The pill's accessible text holds "in 1 minute" through the last minute.** This is the existing word form, so no new text. "Changes only on whole minutes" then holds to the reset, at which the view takes over.
- **The splash's notice `{time}` is a page time in the browser's zone** (hour and minute), like the splash's reset line and the too-many error. The mockup shows "16:00" with no suffix.
- **A kind other than `unscheduled` gives the reset text.** The `Public` step's `kind` rule allows only `scheduled` and `unscheduled`.
- **`Shell.Redirect` drops `since`.** Otherwise the signed-in page keeps `/ocutalon/?since=…`, and reopening that address after the CSP session ended would claim "which cleared your session" about a session that still exists.
- **The live unit's anchor is now + 2 h at its start.** Its fixed anchor put a real reset or `resetSoon` period inside about 1 run in 30, which would show the splash's notice under the fold checks or switch a spec's page to the view. Row 2's step check holds with a future anchor (`NextReset` before the anchor is the anchor).
- **The resetting view announces nothing new.** It is not a banner, and the announcement table has no row for it. Focus goes to its main region through the focus rule when the switch removed the focused element, which tells assistive technology what replaced the page, and the title changes.

- **Implement pass (2026-10-26):**
  - `Settings.RESETSOONSECONDS` is a class parameter, so `Test.Web.PublicTexts` classifies it `notText` and that count is 29, not 28 (compared 40 as planned).
  - The splash never writes `since` into the notice. The form's action keeps the address it was served at (`Error:FullURL`, `%CSP.Login`'s contract), so it can hold `since`; a refused sign-in then keeps its notice.
  - The server writes the reset-soon notice without `hidden` when the reset is soon, and the script would show it either way, so `reset.spec.ts` R2 reads the served markup for that attribute.
  - The `frame.spec.ts` assertion is in F2 (demo mode off), whose snapshot callback also sets `nextReset`: the flag-off stack has no schedule, so only a snapshot with a `nextReset` lets the pill's `onlineDemo` rule show.
  - `LiveState.answers` (a counter of the live path's answers) is the one line added to `live-state.ts`, for the watch's check at every poll answer.
  - The pill's timer needs no slack: it is set to the exact moment the text or urgency changes. The paused clock fires the page's change-detection timer only when it moves, so `reset.spec.ts` runs the clock 20 ms past each target.
  - The resetting view's images carry no `height` attribute and no `height: auto` (the floor's fixed-height list stays as it is); their width and the 400px card are pinned by `host-pages.test.mjs`.
  - Task 0 (d) is a `MEASURED` line of the unit: the browser step took 170 s with the new spec and the whole unit 324 s wall-clock, run alone (DW-220: 310 to 325 s before).
  - `ci/checks.sh` `boundaries`: its `paths` rule fails on `_bmad-output/implementation-artifacts/cycle-log-epic-16.md:130`, which this story did not touch; nothing of this story trips it.
  - Review pass: Task 0 (c) cannot be measured in the browser: a routed request carries no network headers, so a `Cookie` assertion there passes whatever the poller sends. `credentials: 'omit'` is pinned by the Node test of matrix row 12, and R1 no longer asserts or prints a Cookie measurement.
  - Review pass: `reset.spec.ts` gained R3 (a 401 past the reset), R3b (lost contact past the reset), R4 (a `reset` event moves the pill) and R5 (the splash script reveals, announces and hides the reset-soon notice). The wall clock of R3 and R3b jumps with `page.clock.setSystemTime`, which moves `Date.now()` and leaves the page's timers where they are, so only the answer of the API or the contact change can show the reset.
  - Review pass: the `online-demo` unit's browser step took 187 s with R1 to R5 and R3b (45 cases); Task 0 (d) before the review pass: 170 s.

**Integration ACs:**
- `OcuTalon.Data.AddressCounter` (`Recent`, `Purge`) and `OcuTalon.Web.SessionEvents.CookieExpiry` read the shared helper and still count the same window and write the same cookie date. Their existing rows stay green, and on the real flag-on stack the resume cookie still expires at the status's `nextReset` (`web/e2e-online/resume.spec.ts:70-85`) -- row 1.
- The page reads the real `/state`'s `nextReset` and `resetSoon` and shows the pill and the banner -- row 14.
- The resetting view hands over to the real splash, whose `?since=` notice renders from the real `lastReset` -- row 13.
- `Splash` reads `Settings.ResetSoon` and shows the warning on the real stack -- row 14.

**Consumed-by:**
- **Story 16.4:**
  - `splashAddress` and the load time in `web/src/app/session/splash-address.ts`, for its 401 and changed-epoch returns;
  - `Splash`'s info-notice slot (`InfoNotice`), where the place-freed notice becomes the fallback when no reset notice applies;
  - `SessionGate.onSignedOut`'s reset check, which stays first;
  - `Shell.Redirect` dropping `since`.
- **Story 16.9:** the call-line pattern for a condition that `Computed` doesn't hold (`allowance`), and the appended `status` entry in `/state`.
- **Story 29.3:** the host passes `OCUTALON_LAST_RESET` as the time of the reset that just happened (not earlier than its scheduled time) and its kind, and serves the maintenance page. The view's navigation rule relies on that `lastReset`.
- **Epic 8**, owner of `Live/Payload/Status.cls`: `resetSoon` stays outside `Computed`. A later move into `Computed` must keep the one computation and remove the two call lines together.

**Consumes:**
- Story 16.1: `NextReset` and the public keys.
- Story 16.2:
  - the splash, `ResetLine`, `splash.js`'s countdown and roll-forward;
  - `Test.Web.PublicTexts` and the clock pattern of `splash.spec.ts`.
- Story 16.3: `CookieExpiry` and `AddressCounter` (DW-235), and `resume.spec.ts`'s cookie row.
- Story 16.5:
  - the maintenance page's texts, logo and title;
  - `busy.spec.ts`'s status stubs;
  - `DemoBusyState`, as a sibling.
- Epic 2:
  - `LiveState` and `LiveStore.reset`;
  - the banner table's `resetSoon` row, `Announcer` and `focus-rule.ts`;
  - `page-time.ts`, `status-rail.ts`'s countdown pattern, and `StatusMonitor` with its probe tests.
- `Live.Payload.Reset` and `Live.Payload.Status.ActiveOf`, read only.

**Rule 2 (extend, don't copy):**
- **Extensions:**
  - `Settings.ToSeconds`, `FromSeconds` and `NextReset` grow into the one helper, and `SecondsToReset` and `ResetSoon` sit on `NextReset`.
  - `Live.Payload.Status.ActiveOf` exports the appended condition.
  - `StatusMonitor`'s remember-compare-publish loop takes `resetSoon`, and the `reset` publish follows the same pattern.
  - `Splash` reuses `.notice`, `ResetLine`'s `<time>` and countdown spans, `splash.js`'s `countdown`, `startCountdown`, `fillErrorTime` and `announce`.
  - The pill uses `pageTime` and `countdownText`, with a whole-minute spoken form added beside them, and the visible-and-spoken pattern of `status-rail.ts`.
  - The view uses the brand files and the maintenance page's texts, and `host-pages.test.mjs` pins them as equal.
  - The tests use `StatusMonitorProbe`, `Test.Web.Splash.Render`, `Test.Web.Shell`'s `Redirect` helper, `support.ts`, `web/e2e/support/clock.ts`, and the route patterns of `busy.spec.ts` and `banners.spec.ts`.
- **Copies, with reasons:**
  - `StatusMonitor.ResetSoon` repeats the four-line shape of the private `Live.Payload.Status.DailyCap`. That class is contended, and the method is private there.
  - The view's status poller is not `DemoBusyState.check()`. That one sends credentials through `HttpClient`, accepts any answer with a boolean `busy`, and runs only while busy shows. The view needs no credentials, the `ready` and `lastReset` rule, and its own lifetime. Both read the same `PublicStatus` type.

**Footprint extensions** (outside the stated footprint, on no contended list):
- `web/src/app/app.ts`: the view takes the whole page, which only the root can do.
- `web/src/app/chat/page-time.ts`: the whole-minute spoken form beside `countdownText`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` and `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: new keys and counts, under the lead's ruling for this epic.
- `web/scripts/reset-schedule.test.mjs` (new), `page-time.test.mjs`, `ux-strings.test.mjs`, `host-pages.test.mjs` and, if needed, `announce-focus-sources.test.mjs`.
- `web/e2e/frame/frame.spec.ts`: one assertion.

Everything else is in the footprint:
- `Data/Public/**`, `Data/AddressCounter.cls`, `Web/SessionEvents.cls`;
- `Web/Public/**`, including `Splash`, `SplashAssets` and `Shell`;
- `Web/Api.cls` and `Core/StatusMonitor.cls`, new methods and call lines only;
- `Test/{Web,Data}/**`;
- `web/src/signin/**`, `web/src/app/{header,session,live,api}/**`, `web/e2e-online/**`;
- `docker/tests/test-online-demo.sh`.

**Ledger inbox:**
- DW-235 (routed here) is addressed by the tasks on `Settings`, `AddressCounter` and `SessionEvents`, matrix row 1 and the last acceptance criterion.

**For Story 16.4:**
- On the online demo, return to `splashAddress(<load time>)` for a 401 and for a changed epoch. Keep `SessionGate.onSignedOut`'s reset check first.
- Add the place-freed notice as `Splash.InfoNotice`'s fallback: the reset or restart notice wins whenever `since` is earlier than `lastReset` (AC 4: "in place of the place-freed notice").
- Keep `Shell.Redirect` dropping `since`. If 16.4 adds its own marker parameter, drop that from the redirect the same way.

**For the lead:**
- **No escalation.** Every text is specified: EXPERIENCE.md:79, :132, :342, :343, :346; the banner text in the catalog; the countdown pattern in AC 2 and DESIGN.md:752.
- **No AD changes.** The `reset` publisher is already `StatusMonitor`.
- **A seam with Story 29.3, possibly worth a convention row (Rule 20, the lead's call):**
  - the host passes `OCUTALON_LAST_RESET` as the time of the reset that just happened (not earlier than its scheduled time);
  - the page waits for `ready` with a `lastReset` later than its load time, at most 15 minutes past the scheduled time.
- **DW-220:** the new spec adds about 30 to 40 s to the `online-demo` unit locally (inference: the clock-controlled test has no real waits; the real-time test has one sign-in, one splash and one restore). Record the measured time.
- **Epic context.** The committed `epic-16-context.md` is reused, as the dispatch directs, although the spine is newer. The spine's only later change, the "Online-demo probe" convention row (Story 16.6), was read directly and does not bear on this story.
- **Integrate-forward:** `Web/Api.cls`, where Epic 4's `guide` line and this story's line are in separate hunks; `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls`, whose count conflicts merge as a union; `web/e2e-online/demo-account.spec.ts`.

**Lead spec gate (2026-10-26, runner C):**
- DW-235 is addressed (the three public UTC helpers on `Public.Settings`; `AddressCounter.Shift` and `SessionEvents.CookieExpiry` use them).
- No contended file: `resetSoon` is a new `StatusMonitor.ResetSoon` method; `StatusMonitor` and `Web/Api.cls` take new methods and call lines only; `nextReset` follows `traceAccount` in `StateBody`.
- Footprint extensions accepted (none contended): `web/src/app/app.ts`, `web/src/app/chat/page-time.ts`, `Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, `web/scripts/{reset-schedule,page-time,ux-strings,host-pages,announce-focus-sources}.test.mjs`, `web/e2e/frame/frame.spec.ts` (one assertion). Change as few existing lines in `app.ts` and `frame.spec.ts` as the design allows (Epic 4 may edit them too).
- DW-269 routes the host's side of the last-reset seam to Story 29.3 (the orchestrator writes the bullet after the merge).
- Record the `online-demo` unit's measured time under Verification (DW-220: about 310-325 s before this story).

## Verification

**Targets and variables:**
- Every command runs from the worktree root, in the foreground of its own call with `timeout: 600000`. Never put two test-runner calls in one message.
- **Tags:** implement `e16s8i` (fresh) and `e16s8iw` (warm); QA `e16s8q` and `e16s8qw`; review `e16s8r` and `e16s8rw`. Each stage tears down only its own tags.
- **Lane C's variables** go on every `ci/iris.sh` and `ci/warm.sh` call, written out below for the implement stage; other stages use their own stage name. The prefix is `V=`:

  ```
  OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement'
  ```

- **The throwaways:**
  - lane C's warm stack (`ocutalon-<label>-e16s8iw-...`) for class runs;
  - fresh projects (`ocutalon-<label>-e16s8i-<epoch>-<pid>`) for `live online-demo`, `live sign-in`, `live floor` and one fresh `shard lane-b`.

  Never `ocutalon-slot-c` for tests. The slot is load-and-compile only, through the IRIS MCP with `server` `ocutalon-slot-c` and `namespace` `OCUTALON` on every call, after `iris_server_info` (build 154, port 52792).
- **Rebuild and reruns.** Run `ci/iris.sh build` before every `live` run, because a browser run sees a web change only after a build. A WebKit floor flake (DW-198) gets one rerun.

**Commands:**
- (loop) `node web/scripts/tokens.mjs` after each `splash.css` or `splash.js` change, then `node web/scripts/tokens.mjs --check` -- exit 0; `git diff --stat` shows `SignInAssets.cls` unchanged.
- (loop) `npm --prefix web test` -- every node test passes (rows 10 to 12, `ux-strings`, `host-pages`, `announce-focus-sources`, `shell-styles`, `banner-view`, `live-store`, `playwright-projects`).
- (loop) `npm --prefix web run lint` -- exit 0.
- (loop) IRIS MCP `iris_doc_load` and compile of every changed class on `ocutalon-slot-c` / `OCUTALON` -- 0 errors. `SplashAssets` is compiled before `Splash`.
- (once) `V= OCUTALON_RUN_TAG=e16s8iw bash ci/warm.sh up`.
- (loop) `V= OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s8iw bash ci/iris.sh class <Class>`, one call per class, each `CLASS <name> passed`:
  - `OcuTalon.Test.Data.PublicSettings`
  - `OcuTalon.Test.Data.AddressCounter`
  - `OcuTalon.Test.Web.SessionEvents`
  - `OcuTalon.Test.Web.ResetSchedule`
  - `OcuTalon.Test.Web.Splash`
  - `OcuTalon.Test.Web.Shell`
  - `OcuTalon.Test.Web.PublicTexts`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Web.Status`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Core.StatusMonitor`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Live.Status` (read only: `Computed` is untouched)
- (once) `V= OCUTALON_RUN_TAG=e16s8iw bash ci/warm.sh down`.
- (once) `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh shard lane-b` -- every class passes on a fresh stack.
- (loop) `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh build`, then `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh live online-demo` -- PASS:
  - the rows of Stories 16.1 to 16.6, unchanged;
  - row 16;
  - the browser step with `reset.spec.ts` (rows 13 and 14) and the changed `demo-account.spec.ts`;
  - Task 0's `MEASURED` lines.

  Record its time (DW-220): 310 to 325 s before this story, about 350 to 365 s expected, inside the 540 s deadline.
- (once) `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh live sign-in` -- the flag-off Chromium suite passes (row 15, the header, the banners); about 430 s locally.
- (once) `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh live floor` -- passes in all three browsers, because `app.ts` and the header changed.
- (once) `bash ci/checks.sh` -- every block passes (`class-rules` `public-global`, `boundaries`, `ci-config`).
- (once) `V= OCUTALON_RUN_TAG=e16s8i bash ci/iris.sh teardown` -- nothing tagged `e16s8i` is left.

**Shared surfaces:**
- **The public settings.** `onlineDemo`, `resetAnchor`, `resetIntervalHours`, `lastReset` and `lastResetKind` are set by the server tests and by row 14, and are always put back and read back. Every test whose outcome depends on how near the reset is sets the anchor relative to now.
- **`/state`'s keys on the online demo** (`nextReset` last). Two tests pin them: `web/e2e-online/demo-account.spec.ts:115-116`, which changes, and `Test/Web/Api.cls` `TestStateTraceAccount`, which stays green with no anchor.
- **The `status` array and `status` events** (`resetSoon` appended): `web/e2e/banners.spec.ts` and `Test.Core.StatusMonitor`. With the flag off, `resetSoon` never changes, so it is never published.
- **The instance stream's `reset` events:** the probe tests use their own fixture stream; on the real stack, row 14's anchor change and its restore each publish one.
- **The header on the online demo** (the pill): any `web/e2e-online` spec that counts header controls.
- **The splash markup and the `SplashAssets` hashes:** `Test.Web.Splash` (`TestPage`, `TestPolicy`) and `web/e2e-online/splash.spec.ts`.
- **The counts:** `PublicTexts` (compared 40, notText 28) and the catalog (Core 93, total 115).
- **The web test inventories:** `ux-strings` and the `announce-focus-sources` lists.
- **The `online-demo` unit's anchor** (row 16) and its time and deadline (DW-220).
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19). Apply each mutation temporarily, observe red, revert, and confirm the tree is byte-identical (`git status --short` and `git diff --stat` unchanged). Batch the browser mutations that turn different rows red into one `live online-demo` run.

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `Test.Web.ResetSchedule`, row 3 | `StateBody`'s `nextReset` is the following slot (`Settings.Shift(next, 14400)`) |
| AC 1 | `Test.Data.PublicSettings`, row 2 | `NextReset` takes `lastReset` as the anchor when `lastResetKind` is `unscheduled` |
| AC 1 | `Test.Web.ResetSchedule`, row 5 | `PublishReset` publishes on every run (no comparison) |
| AC 2 | `reset-schedule.test.mjs` or `page-time.test.mjs`, row 10 | the accessible text uses `countdownText().spoken` |
| AC 2 | Playwright row 13 | urgent from 300 s instead of 600 s |
| AC 2 | `frame.spec.ts` row 15 and `Test.Web.ResetSchedule` row 4 | the pill ignores `onlineDemo`, and `StateBody` writes `nextReset` whatever the flag |
| AC 3 | `Test.Web.ResetSchedule`, row 5 | `RESETSOONSECONDS` is 600 (an anchor at now + 400 s must not be soon) |
| AC 3 | `Test.Web.Splash`, row 7 | the reset-soon notice is written without `hidden` when the reset isn't soon |
| AC 3 | Playwright row 14 | `ResetSoonNotice` writes `hidden` when the reset is soon |
| AC 4 | `Test.Web.Splash`, row 6 | the `since` comparison is inverted (notice when `since` is later) |
| AC 4 | `Test.Web.Splash`, row 6 | the restart text is never chosen |
| AC 4 | `Test.Web.Shell`, row 8 | `Redirect` keeps `since` |
| AC 4 | `reset-schedule.test.mjs`, row 11 | a later offer replaces the pending reset inside its last 5 minutes |
| AC 4 | `reset-schedule.test.mjs`, row 12 | navigate on `ready` alone, without the `lastReset` rule |
| AC 5 | Playwright row 13 | the poller keeps polling after navigating (or navigates on every ready answer): "lands once" goes red |
| AC 5 | Playwright row 13 | entering the view doesn't call `LiveState.stop()`: "no API request after the switch" goes red |
| AC 4 | Playwright R3 | `SessionGate.onSignedOut` doesn't ask `ResetWatch.enterIfDue()` first: the 401 past the reset goes to the signed-out page |
| AC 4 | Playwright R3b | `ResetWatch` has no check at a change of the page's contact or an answer of the live path |
| AC 2 | Playwright R4 | `ResetWatch` doesn't offer the `reset` event's time (the `eventReset` effect is removed) |
| AC 3 | Playwright R5 | the splash script never takes `hidden` off the reset-soon notice |
| AC 6 | `Test.Data.PublicSettings`, row 1 | `ToSeconds` accepts a time without the trailing "Z" |
| AC 6 | `Test.Data.PublicSettings`, row 1 | `CookieExpiry` keeps its own `$ZDateTimeH` parse (the source check) |

**Mutation record:**
- mutation: AC 1, `StateBody`'s `nextReset` is the following slot (`Settings.Shift(next, 14400)`) -> `Test.Web.ResetSchedule` red (`/state gives the next reset`); reverted, tree byte-identical.
- mutation: AC 1, `NextReset` takes `lastReset` as the anchor when `lastResetKind` is `unscheduled` -> `Test.Data.PublicSettings` red (`an unscheduled reset leaves the schedule`); reverted.
- mutation: AC 1, `PublishReset` has no comparison (publishes every run) -> `Test.Web.ResetSchedule` red (`run 3 changes nothing and publishes nothing`, `three runs with the same schedule publish nothing`); reverted.
- mutation: AC 2, the accessible text uses `countdownText().spoken` (`countdownSpokenMinutes` returns it unchanged) -> `page-time.test.mjs` and `reset-schedule.test.mjs` red (the last minute reads `in 59 seconds`); reverted.
- mutation: AC 2, urgent from 300 s instead of 600 s (`URGENT_MS`) -> `reset.spec.ts` R1 red (`urgent from 10 minutes before`); reverted.
- mutation: AC 2, the pill ignores `onlineDemo` -> `web/e2e/frame/frame.spec.ts` F2 red (the snapshot there carries a `nextReset`); reverted. (A flag-off stack has no schedule, so only a snapshot with `nextReset` can show this.)
- mutation: AC 2, `StateBody` writes `nextReset` whatever the flag (the `onlineDemo` line of `AddReset` removed) -> `Test.Web.ResetSchedule` red (`flag 0: no nextReset`); reverted.
- mutation: AC 3, `RESETSOONSECONDS` is 600 -> `Test.Web.ResetSchedule` red (`400 s ahead is not soon`); reverted.
- mutation: AC 3, the reset-soon notice is written without `hidden` when the reset is not soon -> `Test.Web.Splash` red (`400 s ahead is not soon`); reverted.
- mutation: AC 3, `ResetSoonNotice` writes `hidden` when the reset is soon -> `reset.spec.ts` R2 red (the served markup has no `<div class="notice notice-soon" id="ocu-reset-soon">`; the script shows the notice anyway, so the case reads the markup); reverted.
- mutation: AC 4, the `since` comparison is inverted -> `Test.Web.Splash` red (`one info notice with since earlier than lastReset`); reverted.
- mutation: AC 4, the restart text is never chosen -> `Test.Web.Splash` red (`the restart text`); reverted.
- mutation: AC 4, `Redirect` keeps `since` (`FullUrl` for `RedirectUrl`) -> `Test.Web.Shell` red (`TestRedirectDropsSince`); reverted.
- mutation: AC 4, a later offer replaces the pending reset inside its last 5 minutes -> `reset-schedule.test.mjs` red (`is replaced by a later offer only while the clock is more than 300 s before it`); reverted.
- mutation: AC 4, navigate on `ready` alone -> `reset-schedule.test.mjs` red (rows 11 and 12: `goes to the splash on ready ...`, `asks at once and then every 10 s ...`); reverted.
- mutation: AC 5, the poller keeps polling after navigating (`this.stop()` removed) -> `reset-schedule.test.mjs` red (`it stopped polling`, `no timer is left`). `reset.spec.ts` R1 cannot see it: the navigation unloads the old document within the same moment, so it pins "navigates once" through the navigation count only. Reverted.
- mutation: AC 5, entering the view does not call `LiveState.stop()` -> `reset.spec.ts` R1 red (the live path goes on polling after the switch; the unit prints only the last 80 lines of the failure, which had the case's cleanup error); reverted.
- mutation: AC 6, `ToSeconds` accepts a time without the trailing `Z` (`2N.1"Z"` in the pattern) -> `Test.Data.PublicSettings` red (`ToSeconds gives nothing for '2026-10-18T00:00:00'`); reverted.
- mutation: AC 6, `CookieExpiry` keeps its own `$ZDateTimeH` parse -> `Test.Data.PublicSettings` red (`CookieExpiry has no $ZDateTimeH of its own`); reverted.
- mutation: AC 4, `SessionGate.onSignedOut` does not ask `enterIfDue()` first -> `reset.spec.ts` R3 red (the page went to `/ocutalon/?signedOut=1#/` and no resetting view showed); reverted, tree byte-identical.
- mutation: AC 4, `ResetWatch` has no check at a change of contact or at an answer (the effect on `contact()` and `answers()` removed) -> `reset.spec.ts` R3b red (no resetting view after the API stopped answering past the reset); reverted, tree byte-identical.
- mutation: AC 2, `ResetWatch` does not offer the `reset` event's time (the `eventReset` effect removed) -> `reset.spec.ts` R4 red (the pill stayed on the earlier reset, `Next reset 0:57 \u00b7 in 1 h 54 min`); reverted, tree byte-identical.
- mutation: AC 3, the splash script never takes `hidden` off the reset-soon notice (`SplashAssets` regenerated with `web/scripts/tokens.mjs`) -> `reset.spec.ts` R5 red (the notice stayed hidden five minutes before the reset); reverted from backups, `tokens.mjs --check` current, tree byte-identical.
- After the mutations: `git status --short` was unchanged, the class files and web files matched their backups byte for byte, and the final `live online-demo`, `live sign-in` and `shard lane-b` runs were green on the reverted tree.

## Auto Run Result

Status: done
Blocking condition: none

**Implement pass and review (2026-10-26).**
- The server, splash, page and tests of the plan are in place. Verification, on lane C throwaways only:
  - `npm --prefix web test` 623 pass; `npm --prefix web run lint` and the `tokens`, `payloads` and `catalog` checks are current;
  - the 13 classes of the plan pass on the warm stack, and `shard lane-b` passes on a fresh one (45 classes);
  - `live online-demo` passes with 45 browser cases (`reset.spec.ts` R1, R2, R3, R3b, R4 and R5 included; the browser step took 187 s), `live sign-in` 192 cases, `live floor` 70 cases in three browsers.
  - `ci/checks.sh`: every block passes except `boundaries`, whose `paths` rule fails on `_bmad-output/implementation-artifacts/cycle-log-epic-16.md:130` (a tracked file this story did not touch; it holds a local machine path).
- Review (blind, edge-case, verification-gap, intent-alignment layers; 42 findings): 7 medium rows patched (the 401 and contact entry paths, the `reset` event wiring, the splash script's reveal and announcement, and an unfalsifiable Cookie assertion removed), 2 low rows patched (a stale unit comment); the rest rejected with their reasons in the Review Triage Log. Patched counts: 0 high, 5 medium entries (R3, R3b, R4, R5, Cookie). Nothing deferred.
- Follow-up review recommended: false (no high patched; the medium patches add tests only).
- Task 0: (a) a sessionless `GET /ocutalon/?since=...` reaches `Splash` with `since` set; (b) the installed clock carries across the view's `location.replace` (the splash read `2026-10-25T08:00:30Z` for a reset at `08:00:00Z`); (c) not measurable at a routed request (see Decided in-stage; the Node test pins `credentials: 'omit'`); (d) the browser step took 170 s (187 s after the review pass added R3 to R5) and the unit 324 s wall-clock before it.

**Plan (2026-10-26).**
- Planned and checked against the READY FOR DEVELOPMENT standard; the run halted after planning, as the dispatch asked.
- **Context.** The committed `epic-16-context.md` was reused. Story 16.6's spec was loaded for continuity. The spine's AD-3, AD-4, AD-12, AD-13, AD-19 and AD-25, its event table and its conventions were read in part, along with the UX and PRD regions in `context`.
- **Ledger.** DW-235 is addressed in the plan.
- **No escalation, no intent gap and no NFR tripwire.**
- **Warnings:** `oversized`.
