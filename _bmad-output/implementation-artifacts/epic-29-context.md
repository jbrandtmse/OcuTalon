# Epic 29 Context: The online demo's platform side

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Get the online demo ready to go public about November 1, ahead of 1.0.0 (about November 3) and without Telegram (owner decision `planner_demo_first`). The host's proxy, password guard, gateway, resets and monitoring must match the architecture. Visitors' sessions must stay apart, and the address counter must hold nothing that turns back into an address. A demo whose replies all fall back must never report healthy. "Demo busy" must engage on OcuTalon's own count of live visitors, yet a visitor who got in must never be refused Visual Trace, and the author's load run must measure what the demo can carry. The demo host belongs to the owner alone (owner decision `epic29_brief`), so this epic builds and tests only what the repository holds, on throwaway stacks and stand-ins. Host-only criteria stay release checks for the Contest Planner. The closing burn-down stops the online demo's browser tests failing on timing, so that a red CI run on the launch's path means a real defect.

## Stories

- Story 29.3: The demo host is adapted for the launch
- Story 29.4: Sessions stay isolated under load
- Story 29.5: The address counter's hash is keyed per reset
- Story 29.6: The probe alerts when every turn falls back
- Story 29.7: Demo busy counts the live visitors
- Story 29.8: The author's load run measures the demo's capacity
- Story 29.9: Epic 29 burn-down

## Requirements & Constraints

**Hard boundary (`epic29_brief`, binding on every story):**
- No story connects to, deploys to, configures or probes the demo host. None runs the host commands, SSH or DNS, or looks for the host's deployment configuration or runbook, which stay outside the repository.
- Host-only criteria are listed as release checks and never faked as passing.
- No file holds a host address, host name, credentials, keys, local paths or private infrastructure details. The repository is public.

**Story 29.9 (next): test-only, no product behaviour change.** Each flaky case must pass on a fresh CI stack on its own merits, without an unchanged rerun.
- **DW-333:** every remaining spec that signs in and then waits 10 s for `data-snapshot` must wait for the state answer first, using the `loadedAfter` wait in `web/e2e/support/floor.ts`. That covers `web/e2e/chat/chat.spec.ts` C7's `open()` and its siblings. Story 29.7 already fixed the demo-path, reset, resume, splash and session specs.
- **DW-429:** `live:online-session`'s `web/e2e-online/session/leave.spec.ts` L2 (600 s idle frees the place) must read the freed page's time robustly. It once went red with `since=NaN` in the freed page's URL.
- **DW-432:** `live:online-allowance` D1 must not race the status monitor's first tick. StatusMonitor can publish `dailyCap` before S1's `/state`, which a web process works out from the day's mark alone, so the case missed S1's daily-cap banner.

**Built (29.3 to 29.8), binding facts:**
- **29.3:** a read-only host check script in `release/` with a stand-in test, plus the release check list. Ruling U-158 reads the password guard by its stated outcome: a sign-in body's decoded field names all come from `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin`. The refusal pattern `(IRIS|Cache)(Old|Repeat)?Password` applies to every field except a sign-in body's one `IRISPassword`.
- **29.4:** second-visitor isolation runs in the online demo-path unit on a test stack with the CI mock. The paired-chat cases stay off until Story 31.4.
- **29.5 (veto U-156):** the counter stores an HMAC of the client address, keyed by a private per-instance secret that is never printed, logged or sent. The key is made lazily at its first use after a `lastReset` change (veto U-167), so it never comes back with the golden copy.
- **29.6 (veto U-157):** `no_key`, timeout and rate-limit fallbacks give the probe an alert-only outcome that never counts toward a reset.
- **29.7 (U-163, AD-13 amended; P12 and NFR-23 unchanged):** a session leaves the count at sign-out and at its CSP timeout (about 120 s). The probe and the host's admin path never count, and every reset starts the count at 0. Status and the login page report busy, sessionless and taking no connection, once live visitor sessions reach the visitor cap (about 6). A 6th visitor gets in; a 7th sees "Demo busy". The `InstanceConnections()` check stays as the trace-licence guard, and OWNCONNECTIONS is 0. **U-169:** `/status?for=trace` takes `busy` from the connection check alone, while plain `/status` is busy on either rule. Any other, missing or repeated `for` answers the plain form. Both forms return the same five keys.
- **29.8:** a load script and its procedure in `release/`, proven on a local online-demo stack with the CI mock. It runs stated numbers of visitors and model turns and times notices against 60 s. One more visitor must see the busy text, never an error page. It signs everyone out and writes per-visitor lines plus a table for the release notes. DW-286 measures licence units at sign-in, on trace pages and after leaving. **Release check (the Contest Planner):** 6 visitors without Visual Trace, then 3 with it, through the real proxy, within the $20 daily cap and 8 licence units.

**Measured (DW-251):** a signed-in visitor holds no connection or licence unit. Each open trace session adds one, and leaving frees it within about 2 minutes.

## Technical Decisions

- **Tests and CI:** the browser tests run in CI's `browser` group, each unit on its own fresh throwaway with the CI mock (`live:demo-path` first). The demo path's step summary never counts a skipped step as a pass, and a test tagged `@floor` must have passed.
- **Capacity:** the connection cap (8) and the reserve (1 probe, 1 operator) are public settings, never `InstanceConnectionsMax()`. At the cap IRIS answers 503. The proxy turns that into the busy page under `/ocutalon/` except `/ocutalon/api/`, and the Angular client shows busy for an API 503. Busy responses carry `X-OcuTalon-Busy: 1`.
- **The visitor count** holds live public sessions that arrived through the proxy, where the sessionless checks can read it. Status and the login page read only public settings through `OcuTalon.Data.Public.Settings`, the sole reader and writer of `^OcuTalonPublic` (a CI check enforces this).
- **`/ocutalon/public`** is unauthenticated, outside the sign-in group, sessionless and `no-store`. It always returns `{ready, nextReset, busy, lastReset, lastResetKind}`, with `null` for an unset value.
- **Client address:** the right-most `X-Forwarded-For` entry when the request comes from the proxy address in settings, otherwise the connection's address. Sessions that don't arrive through the proxy are exempt. The probe connects directly and signs out after each check.
- **Session lifetime:** a 120 s CSP timeout, with polling keeping the main session alive. `?IRISLogout=end` frees a trace unit at once. The idle cap (a product setting, default 600 s; polling doesn't count) stops the page polling and ends its CSP session.
- **Resets** restore a golden copy with no sessions, pairings, approvals, live events or CSP sessions, and with readiness cleared. AD-19's online-demo variables are written at every start. The copy is captured from a started, upgraded instance, so anything made at an ordinary start lands in it unless its lifecycle keeps it out.
- **Private records** use AD-3's private global prefix, registered in `src/short-names.tsv`.
- **Ownership:** Epic 29 builds in Lane B's files. AD-29's Epic 29 exception lets it change `release/` and the specs and tests its stories name. Lane A owns `web/e2e/demo-path/telegram-*.spec.ts` and `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- **Busy text:** "The demo is busy right now. Try again in a few minutes, or install it yourself." with "Install it yourself (README)". It appears on the splash as a field error, on the host's busy page and before a trace window opens, never as a raw error page.
- **Place freed:** after the page closes or sits idle for 10 minutes, the splash shows an info notice above both cards: "You were away for a while, so your place was freed for other visitors. Sign in again to pick up where you left off." Signing in from the same browser resumes the session.
- **Daily cap:** the main page shows the "daily cap" banner. The composer stays usable, and decisions take the daily-cap fallback.
- **Maintenance page:** "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself."
- **Sign-in limit:** 5 new sessions per address per hour. Past that, the sign-in shows when the next session becomes available.

## Cross-Story Dependencies

- Stories 29.3 to 29.8 are built. Story 29.9, the last, changes only tests of behaviour that 29.7 and Epic 16 built.
- 29.8's release check joins 29.3's release check list for the Contest Planner's pass on the gated host, before the public flip.
- Story 11.5's release hook calls AD-25's two host commands, which live on the host. Nothing in this epic builds or calls them.
- Story 31.4 turns the paired-chat cases on once Epics 12 and 29 merge. Telegram reaches the demo host with the 1.0.0 update.
