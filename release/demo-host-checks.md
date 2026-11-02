# Demo host checks

For the Contest Planner's hands-on pass on the gated demo host (Story 29.3; AD-25). The host and its configuration are the author's and stay outside this repository. This list, `release/demo-host-check.sh` and the author's load script `release/demo-load.sh` (Story 29.8; see "The load run" below) hold no host address, name, gate user, password or token; the examples use `https://demo.example`.

The script is read-only. It sends GET and POST requests only: public reads, and requests the host must refuse, all with dummy values (user `zz-host-check`, passwords `dummy-old` and `dummy-new`, token `dummy-token`). It never uses either published account, and it signs out every IRIS session its own requests open. Its dummy sign-ins leave failed-sign-in entries in the host's audit log. It runs no `ocutalon-demo` command: the two inputs that come from the host (the status command's output and the container's time zone) are read from a file or from standard input.

A host-only criterion is never marked as passing here. Each stays `pending` until the Planner records it, or carries what the Planner measured, which is re-checked at the release deploy.

## Settings

| Setting | What the Planner sets |
|---|---|
| `OCUTALON_GATE_USER`, `OCUTALON_GATE_PASSWORD` | The access gate's basic-authentication credentials, from the Planner's own configuration. They reach curl only through a temporary configuration file readable by the owner alone and are never printed. Without them the check `gate-closed` is skipped and `access` is expected to read `public`. |
| `OCUTALON_CHECK_BLOCK_STATUS` | Every status the host refuses with, separated by spaces. The gated host's password-change filter answered 404 when the Planner measured it (2026-10-30), so `'403 404'`, unless the host's other blocks differ. 401 and 407 are usage errors: an authentication challenge is never a block. The default is `403`. |
| `OCUTALON_CHECK_BLOCK_MARK` | A text that only the host's refusals carry, in a header or in the body: best a response header that the refusing rule adds. Never a text that IRIS's own answers can hold, such as a status word or a word of IRIS's own not-found page: the script fails `block-mark` when an allowed answer carries the mark, but its allowed reads are answered 200, so it cannot see a mark that only IRIS's not-found answers carry, and such a mark would pass a probe that the host lets through. It turns every `SKIP ... ambiguous` into a verdict. |

A refusal counts as a block only when its status is one of the block statuses, its body holds no IRIS form field (`IRISPassword`, `IRISOldPassword`), and the mark is present when one is set. IRIS answering a probe by itself never counts as a block: with no mark set, a probe whose answer has the same status as the answer IRIS gives alone (and no form field) is `SKIP <id> ambiguous`, and the script exits 3 rather than 0. Set the mark to get a verdict for it. On the gated host as measured (refusals of 404, so `'403 404'`) and with no mark, the 20 probes that IRIS itself answers 404 with no form field are each `SKIP ... ambiguous` (the `/csp/sys/`, `/csp/user/`, `/ui/`, `/mcp/`, `/mcp/ocutalon` and dot-dot paths, and the password-change page under `/ocutalon/public/` and `/csp/broker/`), so run 1 exits 3 until a mark is set; each `SKIP` line names its probe.

## The three runs

Exit codes: 0 every check passed; 1 a check failed; 2 a usage error, a missing tool (bash 3.2 or later, curl, jq), or the host or the gate refusing the first credentialed request; 3 nothing failed, but a check was skipped.

1. Normal, at any time: the allow-list, the blocks, the password guard, the status JSON, the time zone and the status command. The Planner pipes in what only the host can read: the output of `ocutalon-demo status` (`--demo-status`) and the IRIS container's `TZ` value (`--zone`); at most one of the two may be standard input.

   ```
   OCUTALON_CHECK_BLOCK_STATUS='403 404' OCUTALON_CHECK_BLOCK_MARK='<mark>' \
     bash release/demo-host-check.sh https://demo.example --demo-status status.json --zone zone.txt
   ```

2. During a reset, while the maintenance page is up (DW-240): `bash release/demo-host-check.sh https://demo.example --state maintenance`. It compares the page and the four logos (`logo/web/OcuTalon-Logo-{light,dark}-{640,1280}.png`) byte for byte against the repository, beside the page and under `/ocutalon/assets/brand/`.

3. While the demo is full (during the load run's `--hold`, H25): `bash release/demo-host-check.sh https://demo.example --state busy`. It checks that the busy page (`docker/busy.html`, or IRIS's busy splash with `X-OcuTalon-Busy: 1`) replaces IRIS's 503 for `/ocutalon/` and deeper paths, that `/ocutalon/api/` never answers it, and that the status reports busy.

## The criteria

"Measured" means measured on the gated host by the Contest Planner, 2026-10-30 (the Epic 16 deploy). Every measured row is re-checked at the release deploy. The last column holds one of exactly three values: `pending`, `measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy`, or `measured in part 2026-10-30 (Epic 16 deploy); rest pending`.

| H | Criterion | Script / repository | The Planner's check | Status |
|---|---|---|---|---|
| H1 | AC1: the access gate admits only allowed visitors | `gate-closed` | The gate's allow-list; opening it at launch is the author's | pending |
| H2 | AC1: overwrites `X-Forwarded-For`; DW-234 | Story 16.3 pins the rule | Measured: proxied sign-ins write an address-counter row. Re-check: a sign-in with a spoofed `X-Forwarded-For` writes one row for the real client address, and `proxyAddress` is the address IRIS sees for the proxy | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H3 | AC1: passes WebSocket upgrades | none (release 1 polls) | `Upgrade` and `Connection` pass | pending |
| H4 | AC1: allows only `/ocutalon/*` and static `/csp/broker/` files; blocks the webhook path, the password-change pages and `/csp/*`, `/api/*`, `/ui/*`; no MCP endpoint | `allow-*`, `block-*`, `block-pw-*` | Measured: the filter answers 404 to every password-change form of the script's list, signed out and signed in, with and without a query string; a trace page and `/ocutalon/public/status` answer 200. Run 1 for the rest | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H5 | AC2: the guard's field rules; all eleven S17 forms blocked | `guard-*`, `guard-F1` to `guard-F11`, F12 | Measured: the guard (S17's check) is installed. Run 1 | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H6 | AC2: sign-in, the page, the JSON API, polling, trace pages and broker files keep working | `allow-*`, `guard-signin-*` | Measured: the filter admits the splash's three-field sign-in (DW-226); the demo path through the proxy passes sign-in, watch, the reminder to the phone, Break the feed and sign-out (steps 4 and 5 were not built at that deploy), with the exact origin mapped (DW-416). Visual Trace through the proxy | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H7 | AC3: the maintenance page during resets; DW-240 | `maint-*` | Measured: the four logos answer 200 at `/ocutalon/`, `/ocutalon/assets/brand/` and deeper while IRIS is down. Re-check: run 2, during a reset | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H8 | AC3: the busy page in place of a 503 except `/ocutalon/api/` | `busy-*` | Run 3, while full (during the load run's `--hold`, H25) | pending |
| H9 | AC3: busy pages and `X-OcuTalon-Busy` logged and counted per day | none | The proxy's daily counts | pending |
| H10 | AC4: IRIS has no general internet | none | A request from IRIS to a public address fails | pending |
| H11 | AC4: the time zone is US Eastern | `zone` | Measured: the container and the agent's input are `America/New_York`; a reset time of 18.12 UTC renders as 14.12 ET. Re-check: run 1 with `--zone` | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H12 | AC4: only a dummy model key and bot token; the AD-19 endpoint overrides | none | Inspection on the host | pending |
| H13 | AC4: the gateway's routes, the key and token swaps (`/bot<dummy>/`), rate and path limits, the $20 cap refused with 403 "daily cost cap reached"; DW-94's body | Story 29.6 (DW-94): `Test.Agent.Decide` | Measured: Story 16.9's caps (the third message refused with 429 and `retryAt`; the daily-cap notice sent once). The routes and the limits. The body of the 403 must hold "daily cost cap reached": either as plain text or as Anthropic's error JSON (`{"type":"error","error":{"type":"permission_error","message":"daily cost cap reached"}}`), and both give `daily_cap`. An empty body gives `error`, so the day is not marked and no daily-cap notice shows. The Planner checks the body at the deploy | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H14 | AC4: the bot is used by no other instance; the provider-side spend limit | none | The author's | pending |
| H15 | AC4: the Telegram file-download route is not configured (Story 26.2) | none | Confirm it is absent | pending |
| H16 | AC5: resets every 4 h by default; the golden-copy contents; the version refusal; AD-19's variables at start; an unscheduled reset leaves the schedule | `status-*`, `demo-status-*` | The reset procedure | pending |
| H17 | AC5: each start passes that reset's own `OCUTALON_LAST_RESET` (the address key renews per reset, DW-233) | Story 29.5 | Runs before and after a reset show a new `lastReset`. At the release's update, before IRIS stops for the capture, `Write $Data(^OcuTalonP.AddrCountK)` in a terminal of the updated instance, in namespace OCUTALON (`zn "OCUTALON"`), prints 0: the golden copy holds no address key (Story 29.5). The terminal takes a licence unit, so never at the cap (DW-287) | pending |
| H18 | AC5: the `ocutalon-demo status` JSON | `demo-status-*` | Run 1 with the output piped in | pending |
| H19 | AC5: `ocutalon-demo update` before and after launch, its exit lines, the version check, at most 15 min | Story 11.5's stand-in | The update on the host | pending |
| H20 | AC6: the probe every 15 min, alerts reach the author, two counted failures reset; DW-254, and DW-260 via Story 29.6 | `test-probe.sh` | Measured: the probe is healthy and its scheduled run alerted `busy` during the busy test. The 15-minute schedule, the environment, the source address and the reset wiring. The outcome `degraded` (a `no_key`, `timeout` or `rate_limited` fallback) alerts, exits 1 and changes no count, and the host's alert command must deliver every outcome it is given, `degraded` included | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H21 | AC6: nothing else holds an IRIS connection; the runbook stops the proxy first at the cap | none | Inspection on the host | pending |
| H22 | AC6: DW-287, the admin and reset path needs no licence unit at 8 units, or one is kept free | none | Measured: one licence unit in use, held by the deploy terminal; no host command opens an IRIS terminal; the health check uses `iris qlist`. Re-check at the cap | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H23 | AC7: the configuration and runbook stay outside the repository; the server and DNS, the bot and token, the real key in the gateway, SSH for the hook, opening the gate | none | The author's preconditions | pending |
| H24 | The Epic 16 deploy fact "EvalIn off" | none | Measured: `EvalIn` `Enabled=0`, and `OCUTALON_EVAL` is unset | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H25 | NFR-7, NFR-23, DW-286: the load run through the real proxy. Case 1: 6 visitors on the demo path, every notice within 60 s, the one more visitor sees "Demo busy". Case 2: 3 visitors with Visual Trace open, the one more visitor sees "Demo busy" at the trace connections. The licence units per visitor on the host | `release/demo-load.sh` (the load run below) | The two cases of "The load run", with the source addresses and the units command; the tables go into the 1.0.0 release notes | pending |

## The probe's host interface (DW-254, H20)

`docker/probe.sh` runs on the demo host, not through the proxy, and needs bash and curl only. The Planner checks:

- The variables it reads: `OCUTALON_PROBE_URL` (the IRIS origin the host reaches directly), `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_PROBE_ALERT_COMMAND`, `OCUTALON_PROBE_RESET_COMMAND` and `OCUTALON_PROBE_STATE_DIR`.
- A run every 15 minutes.
- A direct connection to IRIS from an address other than `proxyAddress`, so that the reserve check exempts it (AD-13).
- The outcomes and exit codes: `healthy` and `capped` exit 0 with no alert; `busy`, `no_splash` and `degraded` alert and exit 1 and change no count (`busy` adds one to the day's busy count; `degraded` is a turn that fell back with `no_key`, `timeout` or `rate_limited`, so the demo answers but without its model); `auth_failed` and `no_decision` alert, add one to the count of counted failures and exit 1, and at two the reset command runs once; a configuration error exits 2; a run that receives a signal signs out and exits 130. The alert reaches the author for every outcome it is given, `degraded` included, and the reset command resets the demo.

Measured on the gated host (2026-10-30): the probe is healthy, and its scheduled run alerted `busy` during the busy test, so the alert path works.

## The licence units (DW-287, H22)

The Community licence allows 8 concurrent connections: 6 for visitors, one for the probe and one for an operator (AD-13, AD-25). At 8 units, trace pages answer 503 and `iris session` terminals are refused, so the host's admin and reset path must not need a unit at the cap. The host keeps its health check on `iris qlist`, which takes no connection, and opens no IRIS terminal; the runbook's way in at the cap is to stop the proxy first. The script's own requests end their sessions (`?IRISLogout=end`), so a run holds no unit.

Measured on the gated host (2026-10-30): one licence unit in use, held by the deploy terminal. Re-check at the release deploy, and again with the demo full.

## The logo placement (DW-240, H7)

The maintenance page names its logos by bare file name, so a browser resolves them against `/ocutalon/`; Story 16.8's reset view asks for them at `/ocutalon/assets/brand/`. The host must serve the four files of `logo/web/` (`OcuTalon-Logo-light-640.png`, `OcuTalon-Logo-light-1280.png`, `OcuTalon-Logo-dark-640.png`, `OcuTalon-Logo-dark-1280.png`) at both places, unchanged, while IRIS is down, and the page itself unchanged. Run 2 checks all of it byte for byte; `maint-logo-<name>` names the logo and the place that failed.

Measured on the gated host (2026-10-30): the four logos answer 200 at `/ocutalon/`, `/ocutalon/assets/brand/` and deeper while IRIS is down.

## The proxy-address check (DW-234, H2)

IRIS takes the client's address from the right-most `X-Forwarded-For` entry only when the request comes from the address in the `proxyAddress` setting, and the connection's address otherwise (AD-13). So the proxy must overwrite `X-Forwarded-For`, and `proxyAddress` must be the address IRIS sees for the proxy. If the setting is unset or does not match, every proxied visitor counts under the proxy's one address. There is no repository-side fix: counting an unmatched address by the connection would put every visitor under one counter, and reporting it on the status JSON would change AD-13's fixed shape. Story 16.3's phase 2 already pins the rule.

Measured on the gated host (2026-10-30): proxied sign-ins write an address-counter row. Re-check at the release deploy: a sign-in with a spoofed `X-Forwarded-For` writes one row for the real client address, and `proxyAddress` is the address IRIS sees for the proxy.

## The load run (Story 29.8, H25)

`release/demo-load.sh` is the author's load script. It signs N scripted visitors in from their own source addresses, drives the demo path within a stated bound of model turns, times each incident notice on the server's clock, has one more visitor read the status, open the splash and press Sign in, and signs everyone out. It prints one line per visitor and a Markdown table for the 1.0.0 release notes. It sends GET and POST requests only, signs out every session it opens (also on Ctrl-C, exit 130), and holds no host address: the base URL is an argument, and the gate credentials, the source addresses and the units command come from the Planner's environment. The published demo account is read from the host's own splash and is never printed. This story never runs it against the host; the repository proves it against a stand-in in CI (`docker/tests/test-online-load.sh`) and against a local throwaway inside `live:online-demo-path`.

On the gated demo host, before the public flip. Run it from a checkout of the head to deploy, on a driver machine with bash 3.2 or later, curl and jq.

**The commands.** `https://demo.example` stands for the host's origin. The Planner's environment holds the values for every run:

- `OCUTALON_LOAD_INTERFACES`: N+1 of the driver machine's source addresses (the last is the one more visitor's), different for each run, or the same ones an hour later, because of the limit of 5 new sessions per address per hour;
- `OCUTALON_GATE_USER` and `OCUTALON_GATE_PASSWORD`, while the gate is closed;
- `OCUTALON_LOAD_UNITS_COMMAND`, optional.

Every run starts with no visitor signed in.

1. Optional, with no model calls (7 addresses):
   ```
   bash release/demo-load.sh https://demo.example --visitors 6 --max-turns 0
   ```
2. Case 1 (7 addresses). While its `HOLD` line shows, run `bash release/demo-host-check.sh https://demo.example --state busy` in another terminal (run 3, H8):
   ```
   bash release/demo-load.sh https://demo.example --visitors 6 --max-turns 12 --hold 60
   ```
3. Case 2 (4 addresses):
   ```
   bash release/demo-load.sh https://demo.example --visitors 3 --trace --max-turns 6
   ```

**Inputs.**

- The gate credentials and the source addresses (N+1 per run, distinct) come from the Planner's configuration. With neither list set, N is at most 4. `OCUTALON_LOAD_FORWARDED_FOR` is for a local stack only: the host's proxy overwrites `X-Forwarded-For` (H2).
- Visitor counts: 6, then 3. `--max-turns` is required: a driven visitor's run starts 2 model turns (the watch turn and the incident's diagnosis), so the first `min(N, floor(M/2))` visitors drive the demo path and the rest only sign in; `--trace` needs M of at least 2N. The script prints `TURNS FAIL` when the visitors' observed turns exceed M.
- Duration: about 1-2 min per case, plus the hold (at most 600 s, or 90 s with `--trace`).
- The model-call budget is 12 + 6 = 18 model turns (0 for the optional run). The Planner reads the gateway's day spend before and after; the cap is $20.
- The units command is the Planner's own reading of `$SYSTEM.License.InstanceConnections()` and `LUConsumed()`, printing two integers on its first line, or it is left unset. It is split on white space and run with no shell evaluation. A terminal takes one connection itself (the throwaway's baseline reads 1 connection and 1 unit), so never read it at 8.

**The licence units** (Story 29.4's Task 0 and Story 29.8's throwaway readings; DW-286):

- a signed-in visitor holds none;
- each open trace application session holds one connection, and with `--trace` a visitor opens two;
- the unit is keyed by user and TCP peer, so through the proxy all visitors share one;
- sign-out frees at once, and leaving frees in about 2 minutes (112 to 133 s, even while the page polls);
- case 1 peaks at no trace connection; case 2 peaks at 6 (the cap 8 minus the reserve 2), plus the reading's own.

**A pass.**

- Both cases exit 0 and print no FAIL line.
- Every notice is within 60 s.
- No turn or incident falls back for `rate_limited`, `timeout`, `no_key` or `daily_cap`.
- The gateway's log shows every 429 retried with back-off before any fallback (host-only).
- The one more visitor's line is `EXTRA PASS status=busy splash=busy signin=busy`: busy at the visitor cap of 6 in case 1, and at 6 trace connections in case 2, and never an error page.
- `UNITS load=` is the highest reading of the run: in case 2 the baseline plus 6 connections (7/2 on a throwaway whose idle reading is 1/1); `after=` is the baseline again.
- The two tables go into the 1.0.0 release notes, and H25 records "measured" with the date.

**Cleanup.**

- Every visitor signs out (the script does it, Ctrl-C included).
- Afterwards `/ocutalon/public/status` reads `"busy":false`.
- No `demo-load.sh` process is left (`pgrep -f demo-load.sh` prints nothing).

**Results.** H25 stays `pending` until the Planner records the two runs. The repository never marks it as passing.
