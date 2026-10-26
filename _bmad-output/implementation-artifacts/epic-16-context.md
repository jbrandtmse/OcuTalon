# Epic 16 Context: Anyone can try the online demo

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 16 builds the repository side of the online demo. A judge with no install and no key signs in from a splash screen with published credentials and gets a session of their own that this browser resumes until the scheduled reset, although every visitor shares one IRIS account. The demo says plainly when it is full or resetting and shows the reset coming. The epic also ships the busy page, the maintenance page and the monitoring probe that the demo host runs. It runs on runner C in Lane B's files, on top of Epics 2 and 3. Stories 16.1 to 16.3 are done: the first real flag-on start, the splash, and per-sign-in sessions with the per-address limit. Local and IPM installs must not change. The demo opens with restricted access by November 1 and goes public by November 4.

## Stories

- Story 16.1: The online demo's settings arrive at start, and its public accounts are safe to publish (done)
- Story 16.2: The splash screen shows the demo and its sign-in details (done)
- Story 16.3: Signing in opens a session this browser resumes until the reset (done; resolved DW-16)
- Story 16.4: Leaving the page frees its place, and Sign out ends the session (waits on Epic 10; not in this dispatch)
- Story 16.5: A full demo says it is busy, and the host's busy and maintenance pages are ready
- Story 16.6: A probe checks the demo every 15 minutes
- Story 16.8: The page counts down to the reset and waits it out (owns DW-235)
- Story 16.9: Allowances cap messages, model cost and simulated emails (waits on Epic 6; not in this dispatch)

This dispatch still builds 16.5, 16.6 and 16.8, in that order. Stories 16.7 and 16.10 have moved to 29.3 and 31.3.

## Requirements & Constraints

- **Local installs:** with the online-demo flag off nothing changes: no public accounts, no password guard, cost cap at its seed of 0, no stored credentials, no countdown, no `traceAccount` in `/state`. The local sign-in page (with "You were signed out."), the Visual Trace menu and the trace popover behave as before, and a local install keeps one durable session per IRIS user.
- **Isolation:** each sign-in on the shared demo account gets its own OcuTalon session, and the page never shows another session's data. Only sign-out or the reset ends a session. CSP sessions are short and exist only to hold licence connections.
- **Capacity:** the Community licence allows 8 connections. With the cap at 8 and 2 held in reserve (probe and operator), about 6 visitors fit. A full demo always shows the busy text, never a raw server error.
- **Per-address limit:** 5 new sessions per client address per hour (setting `onlineDemo.sessionsPerAddress`). Only creations count, so a resume always works.
- **Secrets:**
  - The resume reference is a bearer secret: it never appears in a production message, log, live event or audit entry.
  - The probe's files hold no host, address, key or credential.
  - The busy and maintenance pages name no infrastructure and pass the public-text check.
- **Public accounts:** no OcuTalon page offers a password change, and the guard refuses every S17 form except the published value. The read-only account opens only Visual Trace and the message viewer, in both namespaces.
- **Accessibility:** every page works by keyboard with the focus ring always visible, meets D › Colors' contrast pairs and sets `lang="en"`. At 1280×600, in light and dark, **Sign in and start** stays above the fold (it sits at 574 of 600 now).

## Technical Decisions

**Public settings (AD-19, AD-3).**
- Public values live only in `^OcuTalonPublic`, in `OCUTALON_PUBLIC`. `OcuTalon.Data.Public.Settings` is their only reader and writer (`Get`, `Set` on fixed keys, `ClearReady`, `SetReady`, `NextReset`). `Setting.Get` delegates every public key to it, and a CI check fails any other class that references the global.
- Product values (the idle cap, the per-address limit) go through `OcuTalon.Data.Setting.Get`.
- **DW-235 (16.8):** `AddressCounter.Shift` and `SessionEvents.CookieExpiry` repeat `Public.Settings`' private UTC parsing (`ToSeconds`/`FromSeconds`). Share one helper and make both callers use it. Since `Public.Settings` may reference only the public packages, the helper has to live there; `Data/Time.cls` is contended.

**What is already built (read it and extend it; don't copy it).**
- Story 3.8 (Lane A's files: read only; ask Lane A for changes): the `Public` step runs right after `Bridge.Installer`, writes every public key plus `Decide`'s three budget settings ($20 cap), and sets readiness last. The Users step installs the staged, self-checked password guard.
- 16.1 proved that on a real flag-on start. `/state` gains `traceAccount` on the online demo only, shown as the header popover's credential rows.
- 16.2: `OcuTalon.Web.Public.Login` hands off to `OcuTalon.Web.Public.Splash` (a subclass) when the flag is set. `/ocutalon/public/status` already returns `{ready, nextReset, busy, lastReset, lastResetKind}` with nulls and computes busy (`Status.IsBusy`).
- 16.3: `OcuTalon.Web.SessionEvents.OnLogin` creates or resumes a `Session` row (`ResumeHash`, `CspSessionId`). It does so through the `OcuTalonResume` cookie: 22-character reference, only its SHA-256 stored, HttpOnly, Secure, `SameSite=Strict`, path `/ocutalon/`, expiring at `NextReset`. A resume sets no new cookie. `Ownership.SessionRef` resolves from the CSP session attached in `OnLogin`, never from the user name, and no endpoint takes a `SessionRef` from the client.

**The public package (AD-3, AD-13).**
- `OcuTalon.Web.Public` and `OcuTalon.Data.Public` reference only `%CSP`, dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (in the generator) and each other (CI-checked). Both run with no roles before sign-in.
- New public texts are `Splash` parameters, each matched to a `splash.*` catalog key, and `Test.Web.PublicTexts` compares them.
- `/ocutalon/public/status` is unauthenticated, sessionless and `no-store`.

**Splash (AD-13, AD-25).**
- It keeps `%CSP.Login`'s form contract and posts only `IRISUsername`, `IRISPassword` and `IRISLogin` (and `IRISSessionToken` when present; build 154 sends none), URL-encoded, which is all the proxy admits. `InvalidLoginAction` stays 0.
- Styles and the single script come from `web/src/signin/splash.{css,js}`. `web/scripts/tokens.mjs` generates `SplashAssets` from them, and the bundle build runs `--check`. Both are pinned by hash in AD-13's CSP, with no `style=` attributes. `SignInAssets.cls` stays byte-identical.
- Times and countdowns are empty `<time datetime>` elements that the script fills in the browser's zone. The countdown follows `page-time.ts`' rules and rolls forward by the interval.
- Field errors go in `#ocu-error` under the button. A failed sign-in marks both fields, but the too-many and busy errors mark none.

**Sign-in refusals and the address limit (AD-4, AD-13).**
- New CSP sessions are recognised only in the session events, never by a changed `%session.SessionId`. The trace applications don't attach.
- `OnLogin` decides a refusal and records it under `Shell`'s `REFUSALKEY` as `$ListBuild(state, until)`. `Shell.OnPreDispatch` then ends the CSP session and renders the splash in that state (the no-role path). 16.5 adds the state "busy" there, checked before the counter, so a busy refusal counts nothing.
- The client address is the right-most `X-Forwarded-For` entry when the request comes from `proxyAddress`, and the connection's address otherwise. Sign-ins that don't come through the proxy (the probe, an operator) are exempt and write no counter row.
- `OcuTalon.Data.AddressCounter` counts under a per-address lock without SQL (the demo account has no SQL privilege) and stores addresses hashed (a keyed hash is pending as DW-233). `Purge(daysToKeep)` keeps one hour.
- Unchecked SQL prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows` (CI-checked). REST code writes only the `Session` row, the address counter, the sign-out command, a pairing hash and UI-only markers.

**Busy (AD-13, AD-25).**
- Busy is when `$SYSTEM.License.InstanceConnections()` reaches the cap minus the reserve. The check takes no licence connection, and nothing reads `InstanceConnectionsMax()`.
- After sign-in, a proxied session is ended when connections exceed the cap minus the reserve. No session is created and nothing counts.
- Every busy response IRIS renders (the splash's busy state, a busy status, the post-sign-in refusal) carries `X-OcuTalon-Busy: 1`.
- The proxy serves the busy page for IRIS 503s outside `/ocutalon/api/`, and the Angular client shows busy for an API 503 itself. Both host pages are self-contained files in `docker/`.

**Probe (AD-25).**
- It lives in `docker/` and calls IRIS directly, not through the proxy. Each run checks for the splash, signs in through the form, sends `POST /api/v1/messages` (JSON, `X-OcuTalon-Request: 1`, a matching `Origin`), waits up to 120 s on `GET /api/v1/events` for the decision, and signs out with `POST /api/v1/session/end`. It never sends credentials without a session.
- Outcomes: healthy; `capped` (a `daily_cap` fallback, also healthy); `busy`; `auth_failed` (the form comes back); `no_decision`. `busy`, `auth_failed`, `no_decision` and a missing splash alert the author through the host's alert command.
- Only two `auth_failed` or `no_decision` runs in a row run the host's reset command, and a healthy or `capped` run clears the count. It logs one line per run and keeps a per-day count of `busy`.

**Reset schedule (AD-12, AD-25).**
- `/ocutalon/public/status`, `GET /api/v1/state` and `StatusMonitor`'s `reset` event give the same next reset from `NextReset`, and so does the cookie's expiry. An unscheduled reset doesn't shift the schedule.
- `resetSoon` is a closed status condition, computed in `/state` and published by `StatusMonitor`. The online demo polls and never opens the WebSocket.

**Files and tests (AD-29, AD-33, AD-22).**
- All files are Lane B's, inside the epic-16 `paths_hint` (`_bmad/custom/epic-dependencies.yaml`). `Web/Api.cls` and `Core/StatusMonitor.cls` are contended.
- Lead rulings on files shared with Epic 4:
  - `web/playwright.config.ts`, `web/scripts/playwright-projects.test.mjs` and `web/package.json` take new entries only, and no existing line changes, header comments and count words included.
  - `ci/units.sh` takes this epic's own tokens only.
  - `Web/Api.cls` takes new methods plus their call lines.
  - `Data/Setting.cls` and `Test/Data/Setting.cls` take own members only, and `Test/Data/Tables.cls` Lane B entries only.
  - `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls` take new keys and their counts; count conflicts merge as a union.
- IRIS's own `%CSP.PasswordChange.cls` at the trace applications is covered by the guard and the proxy (veto U-81). Don't assert that it is absent.
- Flag-on checks extend `docker/tests/test-online-demo.sh`, the `online-demo` live unit (`image` group). It starts a fresh flag-on throwaway from a `$tmp` compose override of test start values, with `OCUTALON_RESET_ANCHOR` and `OCUTALON_LAST_RESET` quoted. It takes about 200-230 s locally (540 s deadline); record the time in Verification (DW-220). Its phase 2 sets `proxyAddress` to the host's address so that sign-ins count as proxied.
- Flag-on browser specs go in `web/e2e-online/` (Playwright project `online-demo`), never under `web/e2e/demo-path/`, which the flag-off project runs. The REL-2 online run is `web/e2e-online/demo-path.spec.ts`.
  - Reuse `signInFromSplash` and `signOutGroup` (`web/e2e-online/support.ts`) and `fixtureUser`.
  - An unbuilt part is `notBuilt(title, 'N.M')`.
- Tests are named `OcuTalon.Test.<Area>.<Subject>`. Security, setting and password tests run only on throwaways; `ocutalon-slot-c` is load-and-compile only. Every test signs out (capacity).
- Make one test-runner call per message, prefer warm mode, and keep each run under the 10-minute cap.

## UX & Interaction Patterns

- **Splash states:**
  - Info notice above both cards: place freed (16.4), or the reset or restart notice when `?since=` is earlier than the last reset (16.8).
  - Warning notice under the sign-in card's title: reset under 5 minutes away (16.8). Sign-in still works.
  - Field error under **Sign in and start**: too many sessions (16.3, built) and busy (16.5, with "Install it yourself (README)"). The button stays enabled.
- **Main page:**
  - The header pill `reset-countdown` reads "Next reset {time} · in {countdown}" in page time with tabular figures. It updates each minute, and each second in the last minute, and turns `reset-countdown-urgent` at 10 minutes. Its accessible text changes only on whole minutes and uses words.
  - The closable `resetSoon` banner follows the banner catalog's order and is announced once, through `Announcer`.
  - While status reports busy, a trace link (or "Open my conversation in Visual Trace") shows the busy text instead of opening, and any API 503 shows it too. Both keep what the visitor typed (16.5).
- **Resetting view and maintenance page:** 16.8's resetting view and 16.5's maintenance page share the 320px logo, the 400px card, both texts and the tab title "Resetting · OcuTalon". Each polls status quietly, without a session, and navigates once (16.8 passes `?since=<UTC ISO 8601>`).
- **Times:** the splash shows times in the browser's zone, the main page in page time. README links use `README_URL`.

## Cross-Story Dependencies

**Within the epic:**
- 16.5 extends 16.3's hook (busy before the counter) and `Shell`'s refusal state, and fills 16.2's `#ocu-error`. Its maintenance page sets the texts that 16.8's resetting view reuses, so it comes first.
- 16.6's probe signs in directly, so it is exempt from the limit. It needs the splash served, and its `capped` case needs a Lane B mock scenario (`ci/mock/scenarios/B/**`) that answers with the gateway's 403 "daily cost cap reached".
- 16.8 builds the splash's `?since=` notices and reset-soon warning, `/state`'s next reset and `resetSoon`, and the countdown. DW-235 belongs to it.

**Ahead of 16.4:**
- 16.4 reuses the `?since=` notices for its return to the splash after a 401 or a changed epoch.
- Until 16.4, an attach failure on the online demo answers 500, and `POST /api/v1/session/end` ends only the CSP session. That frees the connection, which is enough for 16.6; `SessionOps.End` comes with 16.4.

**Other epics:**
- This epic extends Stories 2.2 (Ownership), 2.4 (`Allowance.TryConsume`, still a constant until 16.9), 2.9 (trace links) and 2.10 (banners).
- Epic 10: Story 10.3 turns on 16.3's `/state` pairing check, and its `Pairing.HashCode` delegates to `Session.Hash` (DW-237). 16.4 reuses 10.3's unlink. Story 10.2's README link check covers the README links.
- Story 12.7 turns on 16.3's Telegram-card check. Story 11.1 turns on steps 2-6 of the online REL-2 run.
- Story 29.3 picks up the proxy's sign-in allow-list (DW-226) and a launch check that a proxied sign-in writes a counter row (DW-234).
- Until Story 30.2's purge task exists, tests call `AddressCounter.Purge` directly.
- Epics 29 (29.3, 29.4) and 31 (31.1 to 31.3) wait for this epic to merge.
