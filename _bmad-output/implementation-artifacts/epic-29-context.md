# Epic 29 Context: The online demo's platform side

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Get the online demo ready for its November 2 to 4 launch, running with access restricted from November 1. The demo host's proxy, password guard, gateway, resets and monitoring must match the architecture, and visitors' sessions must stay apart even when the demo is full. The demo host belongs to the owner alone (owner decision `epic29_brief`, 2026-10-30). So this epic builds and tests only what the repository must hold for the host to meet its criteria, on throwaway stacks and stand-ins. Host-only criteria stay release checks for the Contest Planner's hands-on pass. This replaces the earlier rule that Story 29.3 changes no file in the repository.

## Stories

- Story 29.3: The demo host is adapted for the launch
- Story 29.4: Sessions stay isolated under load

## Requirements & Constraints

**Hard boundary (binding):**
- No story connects to, deploys to, configures or probes the demo host. None runs `ocutalon-demo`, SSH or DNS commands, or looks for the host's deployment configuration or runbook (those stay outside the repository).
- Host-only criteria are listed as release checks and never faked as passing. DW-240 (the logo files beside the maintenance page and at `/ocutalon/assets/brand/<name>`), DW-254 (scheduling the probe and giving it its environment) and DW-287 (the admin and reset path at 8 licence units) are the Planner's at the deploy. The other host-side items routed here are host checks too: DW-234 (one proxied sign-in writes a counter row; pin the proxy IP) and DW-269 (a reset writes the new last-reset time and kind).
- No file may contain a host address, credentials, keys, local paths or private infrastructure details.

**Story 29.3, the repository's part:**
- **DW-233:** the address counter stores an HMAC of the client address, keyed by a per-instance secret held in the private database. The secret is renewed at each reset and never appears in the golden copy. It replaces the unsalted SHA-256, because an IPv4 value can be brute-forced within a row's one-hour life.
- **DW-260:** a new alert-only probe outcome for `no_key`, `timeout` and `rate_limit` fallbacks. Like `busy`, it alerts the author and never counts toward a reset. The existing outcomes stay as they are: `busy` alerts only, `capped` (a `daily_cap` fallback) is healthy, and `auth_failed` and `no_decision` (none within 120 s) count. Two counted failures in a row trigger an unscheduled reset.
- **DW-94, only if it needs a repository change:** the gateway's 403 "daily cost cap reached" was measured only in Anthropic's error-JSON shape. A stand-in settles whether a plain-text 403 still classifies as `daily_cap` (the cap is found by its text).
- **A repeatable host check script in `release/`:**
  - It takes the base URL as an argument and reads optional gate credentials from environment variables.
  - It holds no host address or credentials, is read-only, and never runs an `ocutalon-demo` command.
  - It sends only requests that should be refused, with dummy values.
  - It checks:
    - The proxy blocks the webhook path, every password-change page and the rest of `/csp/*`, `/api/*` and `/ui/*`. Only `/ocutalon/*` and the static `/csp/broker/` files get through. The password-change pages include DW-214's `%CSP.PasswordChange.cls` under `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/`, also written with `%25CSP` and in mixed case.
    - The password guard's field rules:
      - Field names are URL-decoded in both the query string and the body.
      - Multipart and chunked bodies are refused.
      - A sign-in POST is accepted only as a bounded `application/x-www-form-urlencoded` body whose names come only from `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin`. The splash posts three of them, without `IRISSessionToken`, so the rule is "only these", never "all four" (DW-226).
      - Any decoded name matching `(IRIS|Cache)(Old|Repeat)?Password`, in any letter case, is refused.
    - The busy and maintenance pages.
    - The US Eastern time zone.
    - The shape of the `/ocutalon/public/status` JSON: readiness, next reset, busy, and the last reset's time and kind.

**Story 29.4:**
- **Isolation.** Two browsers share one demo account on a test stack with the online-demo start values, the CI mock and mocked Telegram.
  - A's incident, notice and approval request appear only in A's views.
  - B cannot see or answer A's request through `/state`, polling or `POST /api/v1/approvals/:ref/answer`.
  - Each session's conversation, mailbox, checks, reminders and orders stay its own.
  - No OCUTALON or OCUORDERS message body or header holds a Telegram name, user name, chat id, phone number or IRIS user name. Messages carry only the `SessionRef` and the internal chat reference.
  - The REL-2 demo-path test's online-demo run turns on its trace step and the second visitor.
  - The paired-chat cases stay off.
- **The real-proxy load case is the author's**, not this story's to run. It has two cases: 6 scripted visitors without Visual Trace, then 3 with it open. Each visitor signs in from its own client address, and nothing bypasses the per-address counter.
  - Every incident notice arrives within 60 s.
  - Rate-limited model requests are retried with back-off before any fallback.
  - One more visitor sees the busy text, never an error page.
  - The results are measured (never asserted in sharded CI) and go into the 1.0.0 release notes.
  - The run must not spend the $20 daily cost cap and stays within the 8-licence-unit ceiling (DW-287).
- **Routed here:**
  - Demo-host measurements that go with the author's run: DW-286 (licence units per visitor) and DW-251 (whether signed-in sessions raise `InstanceConnections()`, so that the busy checks engage).
  - DW-252: an e2e-online case where a guide prompt refused with 503 leaves silently.
  - DW-236: `iris_script` gets an environment pass-through, and the copies delegate to it.
  - DW-333: `openFloor` waits for the GET `/state` answer.
  - DW-413: the daily-cap cases read the instance's day once.

## Technical Decisions

- **Topology:** a TLS proxy, IRIS with no general internet, and an outbound gateway.
  - The proxy overwrites `X-Forwarded-For` and passes WebSocket upgrades. Caddy can't inspect bodies, so the guard is a small body-inspecting filter or a Coraza WAF module.
  - The gateway answers only `POST /v1/messages`, `GET /v1/models/<id>` and the Telegram API.
    - It swaps in the real key and token, rewriting `/bot<dummy>/`.
    - It applies rate and path limits.
    - It enforces the $20 daily cap from each response's usage, refusing over it with 403.
  - IRIS holds only a dummy key and a dummy token, and reaches the gateway through `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_TELEGRAM_API_BASE` and `OCUTALON_EXTRA_CA_FILE`.
- **Client address:** the right-most `X-Forwarded-For` entry when the request comes from the proxy address in settings, and the connection's address otherwise. The probe connects directly from the host and is exempt.
- **Capacity:**
  - The cap is 8 connections, with a reserve of 1 for the probe and 1 for an operator.
  - Sign-in takes no unit. The first trace page per user and client address takes one, held until `?IRISLogout=end` or the 120 s timeout. At 8 units, trace pages answer 503 and `iris session` is refused.
  - Status and the login page report busy at the cap minus the reserve, and the post-sign-in check ends a new public session over it.
  - At the cap, the proxy turns IRIS's 503 into the busy page for every request under `/ocutalon/` except `/ocutalon/api/`.
  - Busy responses carry `X-OcuTalon-Busy: 1`, which the proxy counts per day.
- **Resets:**
  - A reset restores a golden copy holding no sessions, pairings, approvals, live events or CSP sessions, with readiness cleared, and refuses a golden copy whose version differs from the image's.
  - The `Public` step writes AD-19's online-demo variables on every start. A malformed value fails the step, naming the variable, never the value.
  - A golden copy is captured from a started, upgraded instance, so the HMAC secret's lifecycle must keep it out of that capture.
- **Private records** use AD-3's private global prefix (`^OcuTalonP.<Short>`, registered in `src/short-names.tsv`). The private-data check at every start, and in CI, confirms they resolve to the private database.
- **Password-change defence in depth:** the proxy is the first line. The installer's `%SYS` password-validation routine, which allows each public account only its published password, is the tested fallback. The probe's sign-in check is the backstop.
- **Ownership:** Epic 29 is Lane B's, and the classes it builds stay Lane B's. The Epic 29 exception lets it change `release/` (Lane A's folder) for the load test and the specs and tests it names, and the owner decision puts 29.3's host check script there too. Each spec names its files, and the orchestrator serializes overlaps.

## UX & Interaction Patterns

- **Busy text:** "The demo is busy right now. Try again in a few minutes, or install it yourself." with "Install it yourself (README)". It shows on the splash and on the host's busy page, never as a raw error page.
- **Maintenance page:** "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself."
- **Sign-in limit:** one address can start 5 new sessions an hour. Over that, the sign-in shows the too-many-sessions field error with the time the next session becomes available.
- **Message times** use the instance's time with " ET" on the online demo ("since 14:12 ET").

## Cross-Story Dependencies

- Epic 16 has merged, so its pages (16.5), probe (16.6), splash (16.2), sessions and counter (16.3), sign-out (16.4) and allowances (16.9) are in place.
- Story 29.4 waits for Epic 7 to merge (Epic 5 is done). The author's real-proxy case also needs the adapted host and the released demo path (Epic 11).
- Story 11.5's release hook calls `ocutalon-demo status` and `update` over SSH. Those commands are host-side and outside the repository; nothing in this epic builds or calls them.
- Story 31.4 turns the paired-chat cases on once Epics 12 and 29 have merged. Story 31.3 (formerly 16.10) keeps the README, the links and the measurement after launch.
- Story 26.2 later adds the gateway's Telegram file-download route.
