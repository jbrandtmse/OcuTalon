# Epic 29 Context: The online demo's platform side

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Get the online demo ready for its November 2 to 4 launch, running with access restricted from November 1. The demo host's proxy, password guard, gateway, resets and monitoring must match the architecture, and visitors' sessions must stay apart even when the demo is full. The address counter must not hold a value that turns back into a visitor's address. A demo whose replies all fall back must never report healthy. "Demo busy" must engage on OcuTalon's own count of live visitors, because a signed-in visitor holds no connection, and the author's load run measures what the demo can carry. The demo host belongs to the owner alone (owner decision `epic29_brief`, 2026-10-30). So this epic builds and tests only what the repository must hold for the host to meet its criteria, on throwaway stacks and stand-ins. Host-only criteria stay release checks for the Contest Planner's hands-on pass. This replaces the earlier rule that Story 29.3 changes no file in the repository.

## Stories

- Story 29.3: The demo host is adapted for the launch
- Story 29.4: Sessions stay isolated under load
- Story 29.5: The address counter's hash is keyed per reset
- Story 29.6: The probe alerts when every turn falls back
- Story 29.7: The author's load run measures the demo's capacity

## Requirements & Constraints

**Hard boundary (binding, every story):**
- No story connects to, deploys to, configures or probes the demo host. None runs `ocutalon-demo`, SSH or DNS commands, or looks for the host's deployment configuration or runbook (those stay outside the repository).
- Host-only criteria are listed as release checks and never faked as passing. The load run on the host is the author's, never the build's.
- No file may contain a host address, host name, credentials, keys, local paths or private infrastructure details.

**Story 29.3 (built): the `release/` host check script, its stand-in test and the release check list.**
- The script takes the base URL as an argument and reads optional gate credentials from environment variables. It holds no host address or credentials, is read-only, never runs an `ocutalon-demo` command, sends only requests that should be refused (with dummy values), and is proven by its stand-in test, never against the host.
- It checks the path allow-list (only `/ocutalon/*` and the static `/csp/broker/` files get through; DW-214's `%CSP.PasswordChange.cls` under both trace paths is blocked, also as `%25CSP` and in mixed case), the password guard, the busy and maintenance pages, the US Eastern time zone and the shape of `/ocutalon/public/status`.
- **Password guard:** field names are URL-decoded in the query string and the body; multipart and chunked bodies are refused; a sign-in POST is accepted only as a bounded `application/x-www-form-urlencoded` body; any decoded name matching `(IRIS|Cache)(Old|Repeat)?Password`, in any case, is refused. The splash posts three fields, without `IRISSessionToken`, so the rule is "only these", never "all four" (DW-226).
- The lead's ruling U-158 reads AD-25's guard bullets by their stated outcome: a sign-in body's decoded names all come from `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin`, and the refusal pattern applies to every field except a sign-in body's one `IRISPassword`. AD-25's text is unchanged.
- **Release check list** for the Planner at the deploy: DW-240 (the four logo files beside the maintenance page and at `/ocutalon/assets/brand/<name>`), DW-254 (the probe every 15 minutes, with its environment), DW-287 (the admin and reset path needs no licence unit at 8 units, or the host keeps one free), DW-234 (one proxied sign-in writes a counter row; the proxy address in settings must match exactly), DW-269 (each reset writes the new last-reset time and kind before IRIS starts).

**Story 29.4 (built):** the online demo-path unit `live:online-demo-path` runs the second visitor's isolation on a test stack with the online-demo start values, the CI mock and mocked Telegram. B never sees or answers A's request (`/state`, polling, `POST /api/v1/approvals/:ref/answer`); each session's conversation, mailbox, checks, reminders and orders stay its own; production messages carry only the `SessionRef` and the internal chat reference, never a Telegram identifier or IRIS user name. The paired-chat cases stay off until Story 31.4.

**Story 29.5 (built): DW-233, kept by veto U-156.** The counter stores an HMAC of the client address, keyed by a per-instance secret in the private database that is never printed, logged or sent. The key is made lazily at its first use after a `lastReset` change (veto U-167), so it never comes back with the golden copy; a test proves two resets give two different keys.

**Story 29.6 (planned): DW-260, kept by veto U-157, and DW-94.**
- A new alert-only probe outcome, `degraded`, covers `no_key`, timeout and rate-limit fallbacks. Like `busy`, it alerts the author and never counts toward an unscheduled reset.
- Existing outcomes stay: `busy` alerts only, `capped` (a `daily_cap` fallback) is healthy, `auth_failed` and `no_decision` (none within 120 s) count, and two counted failures in a row trigger an unscheduled reset.
- **DW-94:** the gateway's 403 "daily cost cap reached" was measured only in Anthropic's error-JSON shape. A stand-in pins whether a plain-text 403 still classifies as `daily_cap` (the cap is found by its text). If the repository needs a change, make it there; otherwise the release check names the body the gateway must send.

**Story 29.7 (next): the AD-13 visitor count and the author's load run (DW-286, DW-251).**
- **Owner decision U-163's four conditions are its first criteria** (P12 and NFR-23 unchanged):
  1. A session leaves the count at sign-out and at its CSP timeout (about 120 s), so a crashed tab can't hold a place.
  2. The probe and the host's admin path never count.
  3. Every reset starts the count at 0.
  4. `/ocutalon/public/status` and the login page report busy, sessionless and without taking a connection, once the live visitor count reaches the visitor cap (about 6). The post-sign-in check ends a new public session with the busy text when it would take the count past the cap, so a 6th visitor gets in and a 7th sees "Demo busy". The `InstanceConnections()` check stays as the guard on trace licence units, and a new session counts no connection of its own (OWNCONNECTIONS 0).
- **The load run is the author's** (the Contest Planner's pass) on the adapted host before the launch, with the real model, through the real proxy. Two cases: 6 scripted visitors without Visual Trace, then 3 with it open, each signing in from its own client address, nothing bypassing the per-address counter. Every incident notice arrives within 60 s, rate-limited model requests are retried with back-off before any fallback, and one more visitor sees the busy text, never an error page.
- The run spends only a brief, bounded number of model turns under the $20 daily cost cap and stays within the 8-licence-unit ceiling (DW-287). Results are measured, never asserted in sharded CI, and go into the 1.0.0 release notes. The repository holds the load script and its procedure in `release/`, proven on a local stack.
- **Measured facts** (build 154; answering DW-251 and feeding DW-286): a signed-in visitor holds no connection or licence unit; each open trace application session adds one connection; the unit is keyed by user and TCP peer; leaving frees it within about 2 minutes.

## Technical Decisions

- **Topology:** a TLS proxy, IRIS with no general internet, and an outbound gateway.
  - The proxy overwrites `X-Forwarded-For` and passes WebSocket upgrades. The password guard is a body-inspecting filter in front of IRIS.
  - The gateway answers only `POST /v1/messages`, `GET /v1/models/<id>` and the Telegram API. It swaps in the real key and token (rewriting `/bot<dummy>/`), applies rate and path limits, and enforces the $20 daily cap from each response's usage, refusing over it with 403.
  - IRIS holds only a dummy key and a dummy token, and reaches the gateway through `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_TELEGRAM_API_BASE` and `OCUTALON_EXTRA_CA_FILE`.
- **Client address:** the right-most `X-Forwarded-For` entry when the request comes from the proxy address in settings, and the connection's address otherwise. The probe connects directly, so it is exempt from the reserve check and the visitor count. It signs in with the public demo credentials, sends a chat message, checks for a decision and signs out after each check.
- **Capacity and busy:**
  - The connection cap is 8 with a reserve of 1 for the probe and 1 for an operator, both public settings (never `InstanceConnectionsMax()`, a high-water mark).
  - Before sign-in, status and the login page report busy when `InstanceConnections()` reaches the cap minus the reserve, or when the visitor count reaches the visitor cap. Both checks are unauthenticated and sessionless, so the count must be kept where they can read it without a session. They read public values only through `OcuTalon.Data.Public.Settings`, the sole reader and writer of `^OcuTalonPublic` (a CI check fails on any other reference).
  - The visitor count holds each live public session that arrived through the proxy; sessions that don't arrive through the proxy are exempt.
  - The online demo's CSP timeout is 120 s, `?IRISLogout=end` frees a trace unit at once, and the idle cap (default 600 s) ends an idle page's CSP session.
  - At 8 units, trace pages answer 503 and `iris session` is refused. The proxy turns IRIS's 503 into the busy page for every request under `/ocutalon/` except `/ocutalon/api/`, and the Angular client shows busy for an API 503. Before opening a trace window the page checks `/status`.
  - Busy responses carry `X-OcuTalon-Busy: 1`, which the proxy counts per day.
- **Resets and the golden copy:** a reset restores a golden copy with no sessions, pairings, approvals, live events or CSP sessions, readiness cleared, and refuses one whose version differs from the image's. The `Public` step writes AD-19's online-demo variables (the last reset's time and kind included) on every start; a malformed value fails the step, naming the variable, never the value. A golden copy is captured from a started, upgraded instance, so anything made at an ordinary start lands in the capture unless its lifecycle keeps it out.
- **Private records** use AD-3's private global prefix (`^OcuTalonP.<Short>`, registered in `src/short-names.tsv`); the private-data check at every start and in CI confirms they resolve to the private database.
- **Password-change defence in depth:** the proxy is the first line, the installer's `%SYS` password-validation routine (each public account allowed only its published password) the tested fallback, and the probe's sign-in check the backstop.
- **Ownership:** Epic 29 is Lane B's, and the classes it builds stay Lane B's; the counter and the probe in `docker/` are Lane B's own files. AD-29's Epic 29 exception lets it change `release/` (Lane A's folder) for the load test and the specs and tests it names, and the owner decision puts 29.3's host check script there too. Each spec names its files, and the orchestrator serializes overlaps.

## UX & Interaction Patterns

- **Busy text:** "The demo is busy right now. Try again in a few minutes, or install it yourself." with "Install it yourself (README)". It shows on the splash and on the host's busy page, never as a raw error page.
- **Maintenance page:** "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself."
- **Sign-in limit:** one address can start 5 new sessions an hour. Over that, the sign-in shows the too-many-sessions field error with the time the next session becomes available.
- **Message times** use the instance's time with " ET" on the online demo ("since 14:12 ET").

## Cross-Story Dependencies

- Stories 29.3 to 29.5 are done; 29.6 is planned and ready to build; 29.7 follows.
- Epic 16 has merged: its pages (16.5), probe (16.6), splash (16.2), sessions and counter (16.3), sign-out (16.4) and allowances (16.9) are in place. Story 29.5 changed 16.3's counter, Story 29.6 changes 16.6's probe, and Story 29.7's visitor count joins the existing busy checks (status, splash, post-sign-in reserve).
- Story 29.6's DW-94 outcome may add an item, the 403 body the gateway must send, to Story 29.3's release check list.
- Story 29.7's load run needs the adapted host (Story 29.3) and the released demo path (Epic 11), so the author runs it after the release is deployed.
- Story 11.5's release hook calls the two host commands AD-25 fixes. They are host-side and outside the repository, and nothing in this epic builds or calls them.
- Story 31.4 turns the paired-chat cases on once Epics 12 and 29 have merged. Story 31.3 keeps the README, the links and the measurement after launch.
- Story 26.2 later adds the gateway's Telegram file-download route.
