# Epic 16 Context: Anyone can try the online demo

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 16 builds the repository side of the online demo. A judge with no install and no key signs in from a splash screen with published credentials and gets a session of their own that this browser resumes until the scheduled reset, although every visitor shares one IRIS account. The demo says plainly when it is full or resetting and shows the reset coming. The epic also ships the busy page, the maintenance page and the monitoring probe that the demo host runs. It runs on runner C in Lane B's files, after Epics 2 and 3 merged. Story 3.8 already writes the online-demo start values through the `Public` installer step, installs the staged password guard and sets the $20 daily cost cap, and this epic builds on all three. Local and IPM installs must not change. The demo opens with restricted access by November 1 and goes public by November 4.

## Stories

- Story 16.1: The online demo's settings arrive at start, and its public accounts are safe to publish
- Story 16.2: The splash screen shows the demo and its sign-in details
- Story 16.3: Signing in opens a session this browser resumes until the reset (owns DW-16)
- Story 16.4: Leaving the page frees its place, and Sign out ends the session (waits on Epic 10; not built in this dispatch)
- Story 16.5: A full demo says it is busy, and the host's busy and maintenance pages are ready
- Story 16.6: A probe checks the demo every 15 minutes
- Story 16.8: The page counts down to the reset and waits it out
- Story 16.9: Allowances cap messages, model cost and simulated emails (waits on Epic 6; not built in this dispatch)

This dispatch builds 16.1, 16.2, 16.3, 16.5, 16.6 and 16.8, in that order. Stories 16.7 and 16.10 have moved to 29.3 and 31.3.

## Requirements & Constraints

- **Local installs:** with the online-demo flag off nothing changes. There are no public accounts and no password guard, the cost cap stays at its seed value of 0, no credentials are stored, and there is no countdown. The local sign-in page (with "You were signed out."), the Visual Trace menu and the trace popover behave as before.
- **Isolation:** each sign-in on the shared demo account gets its own OcuTalon session, and the page never shows another session's data. Only sign-out or the reset ends a session. CSP sessions are short and exist only to hold licence connections.
- **Capacity:** the Community licence allows 8 connections. With the cap at 8 and 2 held in reserve (probe and operator), about 6 visitors fit. A full demo always shows the busy text, never a raw server error.
- **Per-address limit:** 5 new sessions per client address per hour. Only new sessions count, so a resume always works.
- **Secrets:**
  - The resume reference is a bearer secret: it never appears in a production message, log, live event or audit entry.
  - The probe's files hold no host, address, key or credential.
  - The busy and maintenance pages name no infrastructure and pass the public-text check.
- **Passwords:** no OcuTalon page offers a password change. The guard refuses every S17 form (current and legacy field names, query string, percent-encoded names, multipart, chunked, GET or POST) except the published value, which the installer can still set.
- **Read-only account:** it may open only Visual Trace and the message viewer, in both namespaces. At `/ocutalon` it gets the "no OcuTalon role" message.
- **Accessibility:** the splash works by keyboard alone with the focus ring always visible and meets D › Colors' contrast pairs. Every page sets `lang="en"`. At 1280×600, in light and dark, **Sign in and start** is above the fold.

## Technical Decisions

**Public settings (AD-19, AD-3).**
- Public values live only in `^OcuTalonPublic`, in `OCUTALON_PUBLIC`.
- `OcuTalon.Data.Public.Settings` is their only reader and writer: `Get`, `Set` (fixed keys), `ClearReady`, `SetReady` and `NextReset`.
- `Setting.Get` delegates the public keys to it, and a CI check fails any other class that references the global.
- Product values such as the idle cap and the per-address limit (seeded by 16.3) go through `OcuTalon.Data.Setting.Get`.

**What Story 3.8 built (Lane A's files: read them, don't edit them, and ask Lane A for any change).**
- The `Public` step runs right after `Bridge.Installer` on every start. With the flag set, it writes every public key plus `Decide`'s `DailyCostCapUSD`, `GatewaySpendUSD` and `GatewaySpendDate`.
- A malformed start value fails that step, naming the variable but never the value.
- The step's last phase pins the public accounts' Visual Trace page size, then sets readiness.
- With the flag set, the Users step installs the password guard. It is a generated `%SYS` routine of salted SHA-512 hashes, staged and self-checked before it goes live, and it compares user names case-insensitively.
- 3.8 proved all of this in-process only, and no compose file passes the online-demo variables yet. 16.1 makes the first real flag-on start on a test stack with test start values: it covers the Registry order, the guard compile and every S17 form.

**The public package (AD-3, AD-13).**
- What it may reference (CI-checked): `OcuTalon.Web.Public` and `OcuTalon.Data.Public` reference only `%CSP`, dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (in the compile-time generator) and each other.
- Both packages run with no roles before sign-in.
- They keep their own copies of the UX texts, and a test compares those copies with the catalog.
- `/ocutalon/public/status` is unauthenticated, sessionless and `no-store`. It always returns `{ready, nextReset, busy, lastReset, lastResetKind}`, with `null` for any value that isn't set.

**Splash and sign-in (AD-13, AD-25).**
- `OcuTalon.Web.Public.Login` renders the splash when the flag is set, and keeps `%CSP.Login`'s form contract.
- The form posts only `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin`, URL-encoded, which is all the proxy admits.
- Styles are inline, generated from the token stylesheet, with no `style=` attributes. One hash-pinned inline script handles the copy buttons and the browser-zone times, under AD-13's Content-Security-Policy.
- `InvalidLoginAction` stays 0.

**Resume session (AD-4, DW-16).**
- `OnLogin` in `OcuTalon.Web.SessionEvents` handles every sign-in:
  - With no matching cookie it creates a `Session` row with a new `SessionRef`, `TraceRef` and epoch.
  - With a cookie it reattaches the row it finds by the SHA-256 of the cookie's reference.
- The reference is 16 random bytes, base64url-encoded to 22 characters.
- The cookie is HttpOnly, Secure and `SameSite=Strict`, with path `/ocutalon/`, and expires at the next reset.
- New CSP sessions are recognised only in the session events, never by a changed `%session.SessionId`. The trace applications don't attach.
- `OcuTalon.Data.Ownership` stays the one way to resolve a session (Story 2.2). It resolves from the CSP session attached in `OnLogin`, never from the IRIS user name, and a local install keeps one durable session per IRIS user.
- Unchecked SQL prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows` (CI-checked).
- REST code writes only the `Session` row, the address counter, the sign-out command, a pairing hash and UI-only markers.
- The client address is the right-most `X-Forwarded-For` entry when the request comes from the proxy address in settings, and the connection's address otherwise.
- Sign-ins that don't come through the proxy, the probe's among them, are exempt from the limit.
- `OcuTalon.Data.AddressCounter` stores addresses hashed, with timestamps. Its area's `Purge(daysToKeep)` keeps one hour.

**Busy (AD-13, AD-25).**
- Status and the splash report busy when `$SYSTEM.License.InstanceConnections()` reaches the cap minus the reserve. The check takes no licence connection and never uses `InstanceConnectionsMax()`.
- After sign-in, a session that came through the proxy is ended when connections exceed the cap minus the reserve. No session is created and nothing counts toward the per-address limit.
- Every busy response IRIS renders carries `X-OcuTalon-Busy: 1`.
- The proxy serves the busy page for IRIS 503s outside `/ocutalon/api/`. The Angular client shows busy for an API 503 itself.
- Both host pages are self-contained files in `docker/`.

**Probe (AD-25).**
- It lives in `docker/` and calls IRIS directly, not through the proxy.
- Each run:
  - checks that the instance serves the splash;
  - signs in through the form;
  - sends `POST /api/v1/messages` (JSON, `X-OcuTalon-Request: 1`, matching `Origin`);
  - waits up to 120 s on `GET /api/v1/events` for the decision;
  - signs out with `POST /api/v1/session/end`.
- It never sends credentials without a session.
- Outcomes:
  - healthy, or `capped` (a `daily_cap` fallback, which also counts as healthy);
  - `busy`;
  - `auth_failed` (the sign-in form comes back);
  - `no_decision` (no decision within 120 s).
- Alerts: `busy`, `auth_failed`, `no_decision` and a missing splash all alert the author.
- Resets: only two `auth_failed` or `no_decision` runs in a row trigger the host's reset command. A healthy or `capped` run clears the count.
- Logging: one line per run, plus a per-day count of `busy` runs.

**Reset schedule (AD-12, AD-25).**
- `/ocutalon/public/status`, `GET /api/v1/state` and `StatusMonitor`'s `reset` event all give the same next reset, computed by `NextReset`. That time is also the cookie's expiry.
- An unscheduled reset doesn't shift the schedule.
- `resetSoon` is a closed status condition, computed in `/state` and published by `StatusMonitor`.
- The online demo polls and never opens the WebSocket.

**Files and tests (AD-29, AD-33, AD-22).**
- All files are Lane B's. Stay inside the epic-16 `paths_hint` in `_bmad/custom/epic-dependencies.yaml`.
- `Web/Api.cls` and `Core/StatusMonitor.cls` are shared entries and may be contended at run time.
- Tests are named `OcuTalon.Test.<Area>.<Subject>`. The online-demo REL-2 specs are `web/e2e/demo-path/online-*.spec.ts`. An unbuilt part is `notBuilt(title, 'N.M')`.
- Security, setting and password tests run only on throwaway stacks. Slot `ocutalon-slot-c` is load-and-compile only.
- Keep each run under the 10-minute cap, and prefer warm mode.

## UX & Interaction Patterns

- **Splash layout:**
  - It sits on D `splash-canvas`, which follows the operating system's theme, at most `splash-max-width` wide.
  - From the top: the 240px logo, the `h1` and its subheading, then the "Sign in to the demo" and "Before you start" cards side by side, then the Visual Trace card and the footer.
  - The demo credentials are prefilled and visible, with 88px side labels and no show/hide toggle.
  - A failed sign-in says "That user name and password didn't work.", keeps the user name, clears the password and moves focus to the error.
  - Copy buttons confirm with "Copied". On failure they say "Couldn't copy. Select the text and copy it yourself." and select the value.
- **Where each splash state goes:**
  - Info notice above both cards: place freed (16.4), or the reset or restart notice when `?since=` is earlier than the last reset (16.8).
  - Warning notice under the sign-in card's title: reset under 5 minutes away (16.8). Sign-in still works.
  - Field error under **Sign in and start**: too many sessions (16.3) and busy (16.5). The button stays enabled and no field is marked.
- **Main page:**
  - The header pill `reset-countdown` reads "Next reset {time} · in {countdown}". It updates each minute, and each second in the last minute, and turns `reset-countdown-urgent` at 10 minutes. Its accessible text changes only on whole minutes and uses words.
  - The closable `resetSoon` banner follows the banner catalog's order and is announced once, through `Announcer`.
  - The Visual Trace popover shows the read-only credential rows from the snapshot (16.1).
  - While status reports busy, a trace link shows the busy text instead of opening, and any API 503 shows it too. Both keep what the visitor typed (16.5).
- **Resetting view and maintenance page:** 16.8's resetting view and 16.5's maintenance page share the 320px logo, the 400px card, both texts and the tab title "Resetting · OcuTalon". Each polls status quietly, without a session, and navigates once.
- **Times:** the splash shows times in the browser's zone, the main page in page time. README links use `README_URL`.

## Cross-Story Dependencies

**Within the epic:**
- 16.1 comes first: every later reader goes through the accessor, and the snapshot gains the read-only credentials.
- 16.2's splash hosts 16.3's error, 16.5's busy error and 16.8's notices.
- 16.3's post-sign-in hook also hosts 16.5's busy refusal, which must not count toward the per-address limit.
- 16.5's maintenance page sets the texts that 16.8's resetting view reuses.

**Ahead of 16.4:**
- 16.8 builds the splash's `?since=` notices. Story 16.4 later adds the return to the splash after a 401 or a changed epoch and reuses them.
- Until 16.4 lands, `POST /api/v1/session/end` ends only the CSP session. That frees the connection, which is enough for 16.6's probe; `SessionOps.End` comes with 16.4.

**Other epics:**
- This epic extends Stories 2.2 (Ownership), 2.4 (`Allowance.TryConsume`, still a constant until 16.9), 2.9 (trace links) and 2.10 (banners).
- Epic 10 hasn't merged:
  - 16.3 reads the fixture `Pairing` row until Story 10.3 turns on the `/state` check.
  - Story 10.2's README link check covers the README links once it merges.
  - 16.4 waits for 10.3's unlink. Per its 2026-10-25 amendment, it cancels reminders through a recording `ReminderOps` double until Story 8.4.
- Story 12.7 turns on 16.3's Telegram-card check.
- Story 11.1 turns on the later steps of 16.2's online-demo run.
- Until Story 30.2's purge task exists, tests call `AddressCounter.Purge` directly.
- 16.6's `capped` case needs a Lane B mock scenario that answers with the gateway's 403 "daily cost cap reached".
- Epics 29 (29.3, 29.4) and 31 (31.1 to 31.3) wait for this epic to merge.
