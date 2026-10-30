# Epic 29 Context: The online demo's platform side

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Get the online demo ready to go public about November 1, this weekend, ahead of 1.0.0 (about November 3) and without Telegram (owner decision `planner_demo_first`). The host's proxy, password guard, gateway, resets and monitoring must match the architecture. Visitors' sessions must stay apart, and the address counter must hold nothing that turns back into an address. A demo whose replies all fall back must never report healthy. "Demo busy" must engage on OcuTalon's own count of live visitors, because a signed-in visitor holds no connection, yet a visitor who got in must never be refused Visual Trace. The author's load run must measure what the demo can carry. The demo host belongs to the owner alone (owner decision `epic29_brief`, 2026-10-30). So this epic builds and tests only what the repository must hold, on throwaway stacks and stand-ins. Host-only criteria stay release checks for the Contest Planner's hands-on pass.

## Stories

- Story 29.3: The demo host is adapted for the launch
- Story 29.4: Sessions stay isolated under load
- Story 29.5: The address counter's hash is keyed per reset
- Story 29.6: The probe alerts when every turn falls back
- Story 29.7: Demo busy counts the live visitors
- Story 29.8: The author's load run measures the demo's capacity

## Requirements & Constraints

**Hard boundary (`epic29_brief`, binding on every story):**
- No story connects to, deploys to, configures or probes the demo host. None runs the host commands, SSH or DNS, or looks for the host's deployment configuration or runbook, which stay outside the repository.
- Host-only criteria are listed as release checks and never faked as passing. The real-proxy load run is the Contest Planner's, never the build's.
- No file holds a host address, host name, credentials, keys, local paths or private infrastructure details.

**Built (29.3 to 29.6), binding facts:**
- 29.3: a read-only host check script in `release/` with a stand-in test, plus the release check list. Ruling U-158 reads the password guard by its stated outcome: a sign-in body's decoded field names all come from `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin` ("only these", since the splash posts three). The refusal pattern `(IRIS|Cache)(Old|Repeat)?Password` applies to every field except a sign-in body's one `IRISPassword`.
- 29.4: second-visitor isolation runs in the online demo-path unit on a test stack with the CI mock. The paired-chat cases stay off until Story 31.4.
- 29.5 (veto U-156): the counter stores an HMAC of the client address, keyed by a private per-instance secret that is never printed, logged or sent. The key is made lazily at its first use after a `lastReset` change (veto U-167), so it never comes back with the golden copy.
- 29.6 (veto U-157): `no_key`, timeout and rate-limit fallbacks give the probe an alert-only outcome that never counts toward a reset.

**Story 29.7 (planned): owner decision U-163 (AD-13 amended), with U-169's trace form.** P12 and NFR-23 are unchanged.
1. A session leaves the count at sign-out and at its CSP timeout (about 120 s), so a crashed tab can't hold a place.
2. The probe and the host's admin path never count.
3. Every reset starts the count at 0.
4. `/ocutalon/public/status` and the login page report busy, sessionless and taking no connection, once live visitor sessions reach the visitor cap (about 6). The post-sign-in check ends a new public session with the busy text when it would take the count past the cap, so a 6th visitor gets in and a 7th sees "Demo busy". The `InstanceConnections()` check stays as the trace-licence guard, and a new session counts no connection of its own (OWNCONNECTIONS 0).
- **U-169:** `/status?for=trace` takes its `busy` from the connection check alone. At 6 visitors with connections under the cap minus the reserve, the trace form says not busy and the trace window opens, while plain `/status` says busy. With connections at the cap minus the reserve and fewer than 6 visitors, the trace form says busy and the page shows the busy text. Plain `/status` keeps its own rule (connections or visitor count). Any other, missing or repeated `for` answers the plain form. Both forms keep the same five keys with no extra field.

**Story 29.8: closes on throwaway evidence (`planner_demo_first`).**
- A load script and its procedure in `release/`, proven on a local online-demo stack with the CI mock. It runs a stated number of scripted visitors, without and then with Visual Trace, each from its own client address where the stack allows, and a stated maximum of model turns.
- It times each incident notice against 60 s and has one more visitor read status and splash for the busy text, never an error page. It signs every visitor out, holds no host address or credential, and writes one line per visitor plus a table for the 1.0.0 release notes.
- DW-286: measure the licence units each visitor uses at sign-in, on trace pages and after leaving.
- **Release check (the Contest Planner, gated host, before the public flip):** through the real proxy with the real model, 6 visitors without Visual Trace, then 3 with it. Each signs in from its own client address, and nothing bypasses the per-address counter. Every notice must arrive within 60 s, and rate-limited requests are retried with back-off before any fallback. One more visitor must see the busy text. The run makes no model calls, or only a brief, bounded run under the $20 daily cap, within 8 licence units. Results are measured, never asserted in sharded CI.

**Measured on build 154 (DW-251):** a signed-in visitor holds no connection or licence unit. Each open trace session adds one, keyed by user and TCP peer, and leaving frees it within about 2 minutes.

## Technical Decisions

- **Capacity:** the connection cap (8) and the reserve (1 probe, 1 operator) are public settings, never `InstanceConnectionsMax()`. At the cap IRIS answers 503. The proxy turns that into the busy page under `/ocutalon/` except `/ocutalon/api/`, and the Angular client shows busy for an API 503. Busy responses carry `X-OcuTalon-Busy: 1`.
- **The visitor count** holds live public sessions that arrived through the proxy. It is kept where the sessionless checks can read it without a session. Status and the login page read only public settings, through `OcuTalon.Data.Public.Settings`, the sole reader and writer of `^OcuTalonPublic` (a CI check fails on any other reference).
- **`/ocutalon/public`** is unauthenticated, outside the sign-in group, sessionless and `no-store`. It always returns `{ready, nextReset, busy, lastReset, lastResetKind}`, with `null` when a value is unset.
- **Client address:** the right-most `X-Forwarded-For` entry when the request comes from the proxy address in settings, otherwise the connection's address. Sessions that don't arrive through the proxy are exempt. The probe connects directly, signs in with the public credentials and signs out after each check.
- **Session lifetime (online demo):** a 120 s CSP timeout. Polling keeps the main session alive. `?IRISLogout=end` frees a trace unit at once, and the idle cap (default 600 s) ends an idle page's CSP session.
- **Resets:** a reset restores a golden copy with no sessions, pairings, approvals, live events or CSP sessions, and readiness cleared. AD-19's online-demo variables, the last reset's time and kind included, are written at every start. The golden copy is captured from a started, upgraded instance, so anything made at an ordinary start lands in the capture unless its lifecycle keeps it out.
- **Private records** use AD-3's private global prefix, registered in `src/short-names.tsv`.
- **Ownership:** Epic 29 builds in Lane B's files, and what it builds stays Lane B's. AD-29's Epic 29 exception lets it change `release/` for the load test and host check script, and the specs and tests its stories name. Each spec names its files.

## UX & Interaction Patterns

- **Busy text:** "The demo is busy right now. Try again in a few minutes, or install it yourself." with "Install it yourself (README)". It appears on the splash as a field error, on the host's busy page and before a trace window opens, never as a raw error page.
- **Maintenance page:** "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself."
- **Sign-in limit:** 5 new sessions per address per hour. Past that, the sign-in shows when the next session becomes available.

## Cross-Story Dependencies

- Stories 29.3 to 29.6 are built. 29.7 is planned and next. 29.8 follows, since its "one more visitor sees busy" step exercises 29.7's rule.
- 29.7 joins Epic 16's existing busy checks (status, splash, post-sign-in reserve) and the page's pre-trace check, and relies on 16.4's sign-out and trace sign-out on leaving.
- 29.8's release check joins 29.3's release check list for the Contest Planner's pass, and needs the adapted host and a deployed release.
- Story 11.5's release hook calls AD-25's two host commands, which are host-side. Nothing in this epic builds or calls them.
- Story 31.4 turns the paired-chat cases on once Epics 12 and 29 merge. Telegram reaches the demo host with the 1.0.0 update.
