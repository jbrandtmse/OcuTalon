---
title: "Story 29.8: The author's load run measures the demo's capacity"
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: 'd906be9be6183fd2851287d29eb1ef4e870a1b30'
baseline_commit: 'd906be9be6183fd2851287d29eb1ef4e870a1b30'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized]
deferred:
  - summary: >-
      In one throwaway run of L2 the connection reading after the one more visitor was one lower than the peak of the visitors' trace pages (6/2 against 7/2), so a trace connection may end within seconds of its last page.
    evidence: |-
      The first live run of the load phase (3 visitors with Visual Trace, a units command that reads InstanceConnections and LUConsumed through a terminal): the readings were 3/2, 5/2 and 7/2 after visitors 1, 2 and 3, and 6/2 after the one more visitor, about 5 s later; the run's EXTRA line was still busy by the status. The next two runs peaked at 7/2 as well, but their after-the-extra reading was not printed. Story 29.4's Task 0 and T0-g measured trace connections living 112 to 133 s after the last page request, which a drop within 5 s contradicts. The script now reports the highest reading of the run as UNITS load, and the extra's own reading stays in its table row.
      A throwaway that reads the units every 2 s for 2 minutes after the last trace page would settle whether the drop is real, and the host's own reading is H25's.
    location: >-
      release/demo-load.sh (u_load); release/demo-host-checks.md, The load run (the licence units)
---

<intent-contract>

## Intent

**Problem:** Nothing in the repository lets the author measure what the online demo carries before it goes public: how many visitors run the demo path at once, whether each incident notice still arrives within NFR-7's 60 seconds under that load, and whether one more visitor sees "Demo busy" and never an error page. The licence units each visitor uses (DW-286) rest on throwaway readings, and the real-proxy run is the Contest Planner's (owner decisions `epic29_brief` and `planner_demo_first`).

**Approach:** Ship `release/demo-load.sh`, the author's load script. It signs N scripted visitors in from their own addresses and drives the demo path within a stated bound of model turns, optionally with Visual Trace open. It times each notice on the server's clock, has one more visitor read the status, open the splash and press Sign in, then signs everyone out. It prints one line per visitor and a Markdown table for the 1.0.0 release notes. Prove its verdicts against a hermetic stand-in in the hosted `checks` job, and its real run on a local online-demo throwaway with the CI mock inside `live:online-demo-path`. Record the real-proxy run as release check H25 for the Planner.

## Boundaries & Constraints

**Always:**
- Owner decisions `epic29_brief` and `planner_demo_first` bind; they are quoted under Design Notes. The busy expectations are Story 29.7's rule (6 visitors in, a 7th sees "Demo busy"; `/status?for=trace` is the connection check alone).
- Usage: `bash release/demo-load.sh <base-url> --visitors N --max-turns M [--trace] [--hold S]`.
  - `<base-url>` is an origin: a scheme, a host and an optional port (`origin_ok`, shared with `demo-host-check.sh`).
  - `--visitors` is 1 to 8.
  - `--max-turns` is required, 0 to 999.
  - A driven visitor's run starts 2 model turns: its watch turn and its incident's diagnosis. So the first `min(N, floor(M/2))` visitors drive the demo path, and the rest sign in only.
  - `--trace` needs `M >= 2N`.
  - `--hold` is 0 to 600 seconds (default 0), or at most 90 with `--trace`.
- Environment (all optional):
  - `OCUTALON_GATE_USER` and `OCUTALON_GATE_PASSWORD`: the access gate, through `gate_read` and `gate_config` (mode-600 curl config).
  - `OCUTALON_LOAD_INTERFACES`: N+1 distinct source addresses, used with curl `--interface`, in visitor order, the last for the one more visitor (the host).
  - `OCUTALON_LOAD_FORWARDED_FOR`: N+1 distinct addresses, sent as `X-Forwarded-For`. Only for a local stack whose proxy address is this machine's; the host's proxy overwrites the header (H2).
  - Never both lists. With neither, N is at most 4 (5 new sessions an hour per address, the one more visitor included).
  - `OCUTALON_LOAD_UNITS_COMMAND`: split on white space, with no shell evaluation (`docker/probe.sh`'s rule). It prints the connections and licence units as two integers on its first line. It runs before the run, after each sign-in, after each visitor's trace pages, after the one more visitor, and after the sign-out. Anything else reads `?` and fails nothing.
  - `OCUTALON_LOAD_WATCH_TEXT`: the watch message. The default is the guide's watch prompt, sent with `fromGuide` true; any other text is sent with `fromGuide` false.
- **Each visitor, in this order:**
  1. **Sign in.** GET the splash and read the account the splash prefills (the host's published demo account, never a repository value). POST the three fields (`IRISUsername`, `IRISPassword`, `IRISLogin=Sign in and start`) from a file in the work folder. The visitor is signed in once `/state` answers 200.
  2. **Drive** (driven visitors only):
     - post the watch message;
     - when its turn is done, press Break the feed. A 409 `not_watching` is retried every 2 s for 20 s, and the message is never re-sent;
     - the notice is the first simulated-phone item whose `createdAt` is at or after the press's `startedAt`. It is timed as `createdAt` minus `startedAt`, and waited for up to 120 s;
     - approve its request on the `phone` channel, then wait up to 120 s for the incident to be `resolved` or `closed`.
  3. **Wait** (signed-in-only visitors): poll `/state` every 5 s until the drivers end.
  4. **Visual Trace** (`--trace` only): open one page in each trace application the run links to, the first `traceUrl` under `/ocutalon/trace/ocutalon/` and the first under `/ocutalon/trace/ocuorders/`. Read `/ocutalon/public/status?for=trace` before each page.
- A sign-in that does not reach `/state` 200 is classified:
  - `busy`: the busy text;
  - `limit`: the address-limit text "Too many new sessions from your network this hour";
  - `refused`: the splash with `aria-invalid`;
  - `error`: anything else.
- **The one more visitor**, from its own address, after every visitor has finished its steps: reads `/ocutalon/public/status`, GETs the splash and posts the splash's sign-in. Each answer is classified:
  - `busy`: the body holds "The demo is busy right now." and the title "Try OcuTalon";
  - `admitted`: a redirect, or a later `/state` 200. The visitor is then signed out;
  - `error`: anything else;
  - status `free`: 200 with `busy` false, and splash `form`: the splash without the busy text.
- `--hold`, after the one more visitor: every visitor polls `/state` every 5 s for S seconds. A `HOLD` line goes to stderr first.
- **Sign-out of each visitor:**
  - POST `/api/v1/session/end`;
  - then `?IRISLogout=end` on both trace applications and on `/ocutalon/`;
  - then `/state` must answer 401.
  - On INT, TERM or HUP: stop the drivers, sign out every visitor signed in so far, and exit 130.
- **Verdicts:**
  - **`VISITOR n PASS`** needs all of these:
    - signed in and signed out;
    - when driven:
      - Break the feed answered 200, and the notice came within 60 s;
      - no `no_key`, `timeout`, `rate_limited` or `daily_cap` fallback on its turn or its incident;
      - the incident ended `resolved` or `closed`;
    - with `--trace`: both pages answered 200 with no IRIS sign-in field (`HOST_FORM_FIELD_RE`), and the trace form was not busy before either page.
  - **`EXTRA PASS`** needs `status=busy splash=busy signin=busy`.
  - **Turns:** a run whose observed turns (each chat turn with a decision and each incident with a `decisionRef` in the visitors' `/state`) exceed M prints `TURNS FAIL`.
- **Output.** Results go to stdout; progress lines go to stderr.
  - A header line.
  - One line per visitor: `VISITOR <n> PASS|FAIL signin=<ok|busy|limit|refused|error> path=<driven|signed-in> turns=<k> notice=<s|-> fix=<state|-> trace=<k|busy|-> fallback=<none|reasons> units=<c>/<u>[,<c>/<u>] signout=<ok|failed>`, with ` why=<first failure>` on a FAIL.
  - `EXTRA PASS|FAIL status=<busy|free|error> splash=<busy|form|error> signin=<busy|admitted|error>`.
  - `UNITS before=<c>/<u> load=<c>/<u> after=<c>/<u>`, or `n/a`.
  - `TURNS FAIL used <k> of at most <M>`, only when the observed turns exceed M.
  - A Markdown table with one row per visitor and one for the one more visitor (columns: Visitor, Signed in, Demo path, Model turns, Notice (s), Within 60 s, Fix, Trace pages, Fallbacks, Connections/units, Signed out), and then the line `Model turns used: <k> of at most <M>.`.
  - The summary line `demo-load: <p> passed, <f> failed`.
  - Visitors are named by number. No line holds the base URL, an address, a credential or the published account.
- Exit codes:
  - `0`: every check passed;
  - `1`: a check failed;
  - `2`: a usage error; a missing tool (bash 3.2 or later, curl, jq); a 401 or 407 to the first request; no answer; or a first status read that is not ready or is already busy. Nothing else is sent after a code 2;
  - `130`: after a signal.
- **Requests:**
  - GET and POST only, each with a 30 s limit;
  - every page GET has a unique `t` query;
  - POSTs under `/ocutalon/api/` carry the browser envelope (`Content-Type: application/json`, `X-OcuTalon-Request: 1`, and `Origin` set to the base URL);
  - `umask 077` and a private work folder, removed on exit.
- The script sources `docker/tests/lib-online.sh`, as `demo-host-check.sh` does. Both release scripts share `gate_read`, `gate_config` and `origin_ok` there, and `demo-host-check.sh` behaves exactly as before.
- The live proof is the AD-13 local stand-in for the proxy. The proxy address is set to the address IRIS sees for the host's requests. Each visitor sends its own `X-Forwarded-For`. The proxy address is put back after the run.
- The script, the check list and every file under `docker/` are ASCII. No tracked file holds a host address, IP, host name, gate user, password, token, local path or deployment detail. Examples use `https://demo.example`.

**Never:**
- Connect to, deploy to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands. Read `.env`.
- Mark H25 or any host-only criterion as passing. Assert the real-proxy result in CI.
- Change product code, the mock, the page, or AD-13/AD-25's busy rule (Story 29.7's).
- Re-send a watch message, or repeat any request that starts a model turn.
- Put the published password or a gate credential on a command line, in the output or in a log.
- Edit contended paths, `release/standalone-bridge.sh` or `release/ipm*`, or write the spine.

## I/O & Edge-Case Matrix

The S rows run the real `release/demo-load.sh` against the stand-in of `docker/tests/test-online-load.sh` (a `lib-stub.sh` Node server; flags in a file re-read on every request). The L rows run in `live:online-demo-path`'s load phase on a fresh online-demo throwaway, with the keys at the CI mock and `OCUTALON_LOAD_WATCH_TEXT` set to the mock's `[[mock:watch-start-orders]]` marker before the guide's prompt.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| S1 | Case 1 (AC1's shape) | `--visitors 6 --max-turns 12`, 7 forwarded addresses | Exit 0. Six `VISITOR PASS` lines, each `path=driven`, `notice=5` (the stand-in's default) and `fix=resolved`. `EXTRA PASS`. The table has 7 rows, then "Model turns used: 12 of at most 12.". The stand-in saw: 6 message POSTs and 6 Break the feed POSTs; only GET and POST; one session per visitor address, the extra's with none; every session ended | none |
| S2 | The bound | `--visitors 6 --max-turns 5`, then `--max-turns 0` | Visitors 1 and 2 are `path=driven` and 3 to 6 `path=signed-in`. Exactly 2 message POSTs and 2 Break the feed POSTs, and "Model turns used: 4 of at most 5.", exit 0. With 0: no message or Break the feed POST, exit 0 | none |
| S3 | Visual Trace | `--visitors 3 --trace --max-turns 6` | Each line has `trace=2`, and every page follows a `/status?for=trace` read. `EXTRA` is busy at 6 trace sessions. Exit 0 | `--trace --max-turns 5`: exit 2, nothing sent |
| S4 | A late notice | flag: notice 61 s | Each driven visitor is `FAIL ... notice=61 ... why=notice over 60 s`. All are signed out. Exit 1 | none |
| S5 | Fallbacks | flags: the turn falls back for `no_key`, `timeout`, `rate_limited` or `daily_cap`, the incident for `no_key`, and then the turn for `invalid` | Each of the first four, and the incident's `no_key`, gives `FAIL fallback=<reason>`. `invalid` gives PASS, and `fallback=invalid` appears in the line and the table | none |
| S6 | The watch does not start | `--visitors 1 --max-turns 2`; Break the feed answers 409 `not_watching` | After 20 s: `FAIL ... why=not watching`, and exactly one message POST | none |
| S7 | The one more visitor gets in | flag: the sign-in admits past the cap; then `--visitors 2` with no flag | First run: `EXTRA FAIL signin=admitted`, and the extra's session is ended. Second run (under the cap): `EXTRA FAIL status=free splash=form signin=admitted`. Exit 1 | none |
| S8 | An error page | flag: the splash answers 500 while busy | `EXTRA FAIL splash=error`, exit 1 | none |
| S9 | A failed sign-out | flag: `session/end` answers 500 | Every visitor is `FAIL signout=failed`. Every jar's `?IRISLogout=end` still reaches the stand-in. Exit 1 | none |
| S10 | Preconditions | Each separately: `ready` false; busy before any sign-in; the gate on and no credentials; a closed port | Exit 2, with stderr naming the cause. Nothing is sent after the first status read | none |
| S11 | Usage | Each separately: no base URL; a URL with a path; `--visitors 0` or `9`; `--max-turns` missing or `x`; a list of length other than N+1, or with a repeat; both lists; no list and `--visitors 5`; `--hold 601`; `--hold 91 --trace`; an unknown option; one gate variable alone | Exit 2. The stand-in's record stays empty | none |
| S12 | Credentials, addresses, output | Gate credentials set; then `OCUTALON_LOAD_INTERFACES`; a logging curl in front (`lib-stub.sh`'s shim, which drops `--interface` before the real curl) | Every request carries the basic auth. No command line holds a gate credential or the published password. No curl inherits `OCUTALON_GATE_*`. Every `-K` file is mode 600. Each visitor's calls carry its own `--interface`. stdout and stderr hold no base URL, port, address, credential or published account | none |
| S13 | Licence readings | The units command prints `3 2`; then one that prints nothing | `units=3/2` in every line, in the `UNITS` line and in the table. With nothing: `units=?`, and no FAIL | none |
| S14 | A signal | flag: the turn never ends; TERM after the first message POST | Exit 130 within 10 s. Every signed-in visitor is signed out. No request comes after the sign-outs | none |
| S15 | Hold | `--hold 2` | After the extra's sign-in POST, every session polls `/state` for at least 2 s, then signs out | none |
| S16 | Pins | `release/demo-load.sh`, `web/src/app/guide/guide-view.ts:32`, `docker/probe.sh:246` | The default watch text equals `GUIDE_TEXTS.promptWatch`. The probe's three degraded reasons are all in the script's list | none |
| L1 | Case 1, live | `--visitors 6 --max-turns 10`, X-Forwarded-For `198.51.100.81` to `.87` | Exit 0. Six PASS lines: five `path=driven` with notice at most 60 and `fix=resolved`, and one `path=signed-in`. `EXTRA PASS`: busy by Story 29.7's visitor count, and the sign-in refused. IRIS gains 5 Turn rows and 5 Incident rows, all 5 `resolved`. Each visitor address has 1 counter row and `.87` has none. Afterwards, plain `/status` is not busy and the connections are at the baseline | none |
| L2 | Case 2, live (DW-286) | `--visitors 3 --trace --max-turns 6`, `.91` to `.94`, the unit's units command | Exit 0. Three PASS lines with `trace=2`. The readings rise by 0 at each sign-in and by 2 after each visitor's pages, to the baseline plus 6 at load. `EXTRA PASS`: busy by the connections, and the sign-in refused. Back at the baseline right after the sign-out. MEASURED lines print every reading | none |

</intent-contract>

## Code Map

**The sibling to extend: `release/demo-host-check.sh`** (Story 29.3, 538 lines)
- The header, :1-46: the usage, the environment, the request rules, the exit codes.
- The tools and the library, :65-72: the bash 3.2 check, `curl jq ...`, and `. docker/tests/lib-online.sh`.
- The base URL, :105-111: the origin regex is at :108. It becomes `origin_ok`.
- The gate, :113-120: both variables or neither, no colon, no line break, and the plain-http warning. The config is written at :165-174 (mode 600, `-K`, then `unset`). Both parts move into lib-online.sh's `gate_read` and `gate_config`; the warning stays in each script.
- `umask 077`, the work folder and the traps are at :134-138. The report and pass/fail helpers are at :178-191.
- `sign_out` (:206-213) is the group sign-out pattern, and `get_t` (:236-243) gives the unique `t`.
- `first_answer` (:256-262): 401/407 or no answer means exit 2.
- `busy_answer_ok` (:465-468) reads the busy page and the busy splash. The summary and exit are at :535-538.

**`docker/tests/lib-online.sh`**
- The header, :1-17, and the no-stack section, :121-123. The new helpers go there, beside `HOST_FORM_FIELD_RE` (:125-126), `host_app` (:142-150) and `pct` (:152-159).
- `logout_all` (:76-82) and `online_signin` (:84-106) are the test-side sign-in and sign-out (Rule 2 under Design Notes).
- `keys_point` (:111-115).
- After Story 29.7 the stack helpers also hold `host_address`, `set_proxy`, `status_read` and `counter_rows`, moved unchanged from `test-online-demo.sh`. Anchor on these names.

**`docker/tests/lib-stub.sh`** (52 lines): `tmp`, the cleanup, `pass`/`fail`, `need_tools` and `stub_start`.
- The shim moves here from `test-online-host.sh:820-851`, which holds the logging curl and its three checks: argv, environment and `-K` mode.

**`docker/tests/test-online-host.sh`**
- The header is at :1-27; `set_flags`, `run_script` and `expect_run` are at :316-375.
- Row 15, :862-889: `scan`, ASCII, no host command, no PUT/DELETE/PATCH, no credential option, `chmod 600` plus `umask 077`, executable, mode 100755.
- AC 9, :891-907, loops over `seq 1 24`.

**`docker/tests/test-online-demo-path.sh`** (Story 29.4, `live:online-demo-path`)
- The header is at :1-21, `online_override` at :31 and `keys_point` at :53-59. `run_e2e "$@"` is at :66-77, so `-g` filters the browser cases.
- The browser step runs from :126. `MEASURED ... the unit took` is at :155 and the exit at :157.
- The browser step's visitors are not proxied: the proxy address is `192.0.2.10`, from `online_values`. So they never count.

**The product surfaces the script reads** (read-only)
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - `TITLE` "Try OcuTalon" :24, `SUBMIT` "Sign in and start" :38, `TOOMANY` :76 and `BUSY` :79;
  - the published values and the prefilled `value=` attributes, :152-155 and :181-184;
  - the busy state and header, :124-127.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:1-50`: the routes, `session/end` (:34-36) and the envelope (:44-45).
- `web/src/app/live/payloads.ts`: `ChatMessagePayload` :106, `PhonePayload` :142, `DecisionPayload` :162 and `IncidentPayload` :258.
  - `/state` keys: `chat` (`chat.message` and `incident` items), `rail.decisions`, `rail.checks` and `phone`.
  - The incident states are `open, awaiting_approval, fixing, resolved, closed` (`Msg/Enum.cls:18`).
- `web/src/app/guide/guide-view.ts:32`: `promptWatch`.
- `docker/probe.sh:246`: the degraded reasons.
- `docker/busy.html`: the title "Try OcuTalon" and "The demo is busy right now.".
- IRIS tables for the live counts: `OcuTalon_Data.Turn` and `OcuTalon_Data.Incident` (`State`).

**CI**
- `ci/units.sh`:
  - `CHECK_SCRIPTS` :6;
  - the group comment :33-35, and `shards-2` :45;
  - `IRIS_INPUT` :122, `NOT_IRIS_INPUT_PATTERN` :137 (`release/` is a non-input), and `group_input_pattern` :141-161.
- `docker/tests/test-ci-config.sh`:
  - `unit_reads` :1033-1036 flags a `$root/<path>` read;
  - the inputs rule :1056-1085: a read must be claimed by the unit's group;
  - the exactly-one-list rule :624-650.
- `docker/tests/test-ci-changes.sh:243` "release runs no group" (`release/x.sh`) stays true.

**The check list** (`release/demo-host-checks.md`)
- The intro is at :3.
- Run 3, :32, and H8, :47, still name "Story 29.4's author run".
- H24 is the last row, at :63. The licence units section is at :76-80.

**Measured in this plan (Task 0).** Scratch scripts, not tracked, ran on a lane-C online-demo throwaway: tag `e29s8plan`, build 154, the CI mock with the keys pointed, and `proxyAddress` set to the host's address. Four runs; each was torn down by its EXIT trap, so nothing tagged `e29s8plan` is left. Readings are connections/units from a terminal, whose own process is the baseline 1/1.
- **T0-a: sign-in.** The splash prefills the published account, and a GET sets 2 cookies. Six visitors from six forwarded addresses signed in: POST 303, the shell, `/state` 200, still 1/1. A signed-in visitor holds no connection or unit.
- **T0-b: the curl demo path.**
  - With the marker, the turn was done with an Orders check row in 1-2 s.
  - Break the feed answered 200 with `startedAt` (UTC, whole seconds).
  - The first phone item (`direction` out, with `approvalRef`) came `createdAt - startedAt` = 10-13 s after the press, for 3 and for 6 visitors in parallel.
  - Approving on `phone` answered 200, and the incident was `resolved` within 1 s.
- **T0-c: per driven visitor.**
  - `/state` holds one chat turn with a decision (3 agent steps; the mock's watch scenario gives fallback `invalid`) and one incident with a `decisionRef`.
  - The mock logged 6 model requests per visitor (4 watch, 2 diagnosis). That is 2 model turns.
  - The diagnosis's cost is not in `/state`.
- **T0-d: trace pages.**
  - A driven visitor's `/state` has 6 `traceUrl`s in `/ocutalon/trace/ocutalon/` and 2 in `/ocutalon/trace/ocuorders/`.
  - One page in each answered 200 with no sign-in field, at +1 connection each.
  - The run's first trace page took one unit, and every visitor shares it (same user, same TCP peer).
  - 3 visitors x 2 pages read 7/2: 6 trace connections, and plain `/status` busy.
- **T0-e: before Story 29.7.**
  - Case 1's 7th visitor saw no busy and its sign-in got in (DW-251).
  - Case 2's 4th visitor, at 6 trace connections: status busy and splash busy (200, with the header), but the sign-in POST got in (303, a resume cookie, `/state` 200), because `OWNCONNECTIONS` is 1.
  - Story 29.7's count and its AC8 (`OWNCONNECTIONS` 0) close both. So the sign-in step is the check that sees them.
- **T0-f: sign-out.** `session/end` 204, then the group sign-out: `/state` 401, and back to 1/1 at once.
- **T0-g: DW-286's occurrence.**
  - A trace tab closed while its page polls `/state` every 5 s: the trace connections stay until 112-123 s after the last page request, and are gone by 133 s.
  - The main session stays alive.
  - The unit stays (2) until sign-out, then 1/1.
- **T0-h: timings.** Ready after 84-85 s. Case 1 (6 visitors) took 17 s, and case 2 (3 visitors with trace) 17 s.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-online.sh` -- add these in the no-stack section and list them in the header (Rule 2: the gate rules move here once, for both release scripts):
  - `origin_ok <url>`: the regex of `demo-host-check.sh:108`;
  - `gate_read`: reads the two variables into `gate_user` and `gate_password`; returns 1 with `gate_problem` set to the existing message for half-set credentials, a colon or a line break;
  - `gate_config <dir>`: writes `<dir>/gate.cfg` with `chmod 600` and the same escaping, sets the array `gate_args` (empty when there are no credentials), and unsets the four variables.
- `release/demo-host-check.sh` -- call `origin_ok`, `gate_read || usage "$gate_problem"` and `gate_config "$work"` in place of the inline code -- no change in behaviour; `test-online-host.sh` pins it.
- `release/demo-load.sh` (new, mode 755, tracked 100755) -- the script as Boundaries define it, with a header like `demo-host-check.sh`'s (usage, environment, requests, output, exit codes). Drivers run as background subshells that write `key=value` result files, and the parent waits. The traps stop them and sign out. The time arithmetic uses jq `fromdateiso8601` -- portable across macOS and Linux.
- `docker/tests/lib-stub.sh` -- move the shim here and list it in the header:
  - `curl_shim <dir> [strip-interface]` writes the logging curl. With `strip-interface` it logs `--interface <v>` and drops it before calling the real curl;
  - `shim_checks <log> <label> <secret>...` prints the argv, environment and mode-600 PASS/FAIL lines.
- `docker/tests/test-online-host.sh` -- three changes:
  - use `curl_shim` and `shim_checks`;
  - run row 15 over both release scripts: `umask 077` in each, and `chmod 600` in lib-online.sh's `gate_config`;
  - AC 9 covers H1 to H25.
  - The header says so.
- `docker/tests/test-online-load.sh` (new; `lib-stub.sh` and `lib-online.sh`; needs node, curl and jq) -- rows S1 to S16. The stand-in:
  - serves the splash with a random published account per run (with the busy text and `X-OcuTalon-Busy: 1` while busy), the sign-in (303 and a cookie, or the busy splash), `/ocutalon/`, `/state`, `messages` 202, `demo/break-feed` 200 `{startedAt}` (or 409), `approvals/:ref/answer` 200, `session/end` 204, `?IRISLogout=end`, `/public/status` (both forms) and trace pages;
  - is busy at 6 live sessions or 6 trace sessions, and its trace form at 6 trace sessions;
  - checks the envelope;
  - writes the phone item's `createdAt` as `startedAt` plus the flag's seconds, at once, so S4 needs no wait;
  - records method, path, `X-Forwarded-For`, session and auth per request.
  - Flags: notice, fallback, inc-fallback, not-watching, extra=admit, extra=error, signout=fail, ready=false, busy=true, gate=on, hang=turn.
  - The header lists the rows.
- `docker/tests/test-online-demo-path.sh` -- a load phase after the browser step, rows L1 and L2. It needs at least 150 s of the deadline left, else it FAILs, saying so. The phase:
  - sets the proxy to `host_address` and reads it back;
  - writes `$tmp/units.sh`: the reading of `InstanceConnections()` and `LUConsumed()` through `docker exec -i <cid> iris session IRIS -U OCUTALON`;
  - waits up to 150 s for the baseline (the unit's own reading after the start);
  - counts Turn, Incident and resolved Incident rows before and after L1;
  - checks `counter_rows` per address, `status_read`, and the readings;
  - prints MEASURED lines (each case's seconds, each notice, each reading);
  - puts the proxy address back to `$proxy_start` and reads it back.
  - The header says so.
- `release/demo-host-checks.md` -- these edits:
  - the intro names both scripts;
  - add H25 (`release/demo-load.sh`, `pending`): the two real-proxy cases with their pass criteria and DW-286's per-visitor units on the host;
  - add a section "The load run (Story 29.8, H25)": the commands, inputs, licence units, pass, cleanup and results, as `## Host release check` below;
  - run 3 and H8 now read "while full (during the load run's `--hold`, H25)".
- `ci/units.sh` -- three edits:
  - `CHECK_SCRIPTS` gains `online-load`;
  - `IRIS_INPUT` gains `release/demo-load\.sh$`, and its comment names the unit that runs it;
  - the `online-demo-path` sentence names the load phase and its expected time.

**Acceptance Criteria:**
- **AC1 (Integration AC; FR-15, NFR-7, NFR-23, AD-13).** The consumer, `live:online-demo-path`'s load phase, runs the script against a real throwaway. Given the unit's stack with the keys at the mock and the proxy address set to the host's address, when the phase runs L1, then row L1 holds in full, and IRIS's own Turn, Incident and counter-row counts agree with the script's lines.
- **AC2 (DW-286).** Given L1's stack, when the phase runs L2 with the units command, then row L2 holds: per-visitor readings of +0 at sign-in and +2 after the pages, and the baseline right after the sign-out.
- **AC3 (none beyond the bound).** Given the stand-in, when the script runs rows S2, S3's refusal and S6, then it never sends more turn-starting requests than `floor(M/2)` drivers allow, and never re-sends a watch message.
- **AC4 (no false all-clear).** Given the stand-in, when a notice is late (S4), a turn falls back degraded (S5), the one more visitor gets in or meets an error page (S7, S8), or a sign-out fails (S9), then the run prints the named FAIL and exits 1.
- **AC5 (preconditions and usage).** Given the inputs of S10 and S11, when the script starts, then it exits 2 and sends nothing beyond the first status read.
- **AC6 (no host detail or credential).** Given S12's runs, and row 15 of `test-online-host.sh` over both release scripts, when they run, then no command line, inherited environment, output line or tracked script holds a credential, the published account, an address or a host literal.
- **AC7 (cleanup and the Planner's aids).** Given S13, S14 and S15, when the readings, a TERM and `--hold` occur, then the readings appear as `c/u`, a signal signs everyone out (exit 130), and the hold keeps the visitors signed in for its time.
- **AC8 (the shared helpers and the check list).** Given the story's diff, when `test-online-host.sh` runs, then every existing row passes unchanged, and H1 to H25 each hold one of the three statuses, with H25 `pending`.
- **AC9 (pins).** Given S16, when it runs, then the default watch text is the guide's, and the probe's degraded reasons are in the script's list.
- **AC10 (standing, Rule 19).** Given a fresh environment, when the story's added and changed tests run forward and then in reverse order, then every one passes.

### Review Findings

Code review 2026-10-30 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). Each line: severity, fix-risk, footprint, spec-status.

- [x] [Review][Patch] A signal while a sign-in POST is in flight leaves its session open: bash runs the trap only after the curl returns, so `post_signin` never records the 3xx and `on_signal` skips the visitor (measured on bash 3.2 and 5.2); the `opened` read in `on_signal` had no test -- med, fix-risk low, in-story, clear. Fix: record the visitor before the POST and sign out that list on a signal; S14 gains a TERM during a slowed sign-in [release/demo-load.sh:350]
- [x] [Review][Patch] A driver whose path ends first stops polling, so on a run whose drivers end more than about 2 min apart its CSP session reaches AD-13's 120 s timeout: a false `FAIL` (the state answered 401 at the end) and the visitor count drops, so the one more visitor can read `free` -- med, fix-risk med (the drivers' end condition), in-story, clear (spec silent). Fix: each driver polls like a signed-in-only visitor until every driver has ended; S2 gains a run with one slow turn [release/demo-load.sh:449]
- [x] [Review][Patch] AC8's "H25 `pending`" is not pinned: the H-row loop accepts any of the three statuses -- med (Rule 19), fix-risk low, in-story, clear [docker/tests/test-online-host.sh:882]
- [x] [Review][Patch] The stand-in's sessions persist across rows, so a row's busy expectations depend on earlier rows having signed out (Rule 19 hermeticity) -- med, fix-risk low, in-story, clear. Fix: each `set_flags` starts a new generation, and the stand-in clears its sessions when the generation changes [docker/tests/test-online-load.sh:244]
- [x] [Review][Patch] `UNITS load=` as the run's highest reading has no test that tells it from another reading (S13's command always prints `3 2`) -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:651]
- [x] [Review][Patch] The one more visitor's path for a busy page with no form (the host's `docker/busy.html`; `account.body`) never runs -- low, fix-risk low, in-story, clear [release/demo-load.sh:664]
- [x] [Review][Patch] `clean()` has no test -- low, fix-risk low, in-story, clear [release/demo-load.sh:223]
- [x] [Review][Patch] `clean()` turns the parentheses of the script's own `why` texts into `_` -- low, fix-risk low, in-story, clear [release/demo-load.sh:224]
- [x] [Review][Patch] `gate_read`'s line-break rule (the guard on `gate.cfg` injection) has no test -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:600]
- [x] [Review][Patch] The sign-in classes `busy`, `limit` and `refused` are never produced by a test -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:545]
- [x] [Review][Patch] S12's secret check misses the percent-encoded published account and the base64 gate value, so a sign-in body moved onto the command line stays green -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:616]
- [x] [Review][Patch] INT and HUP are not pinned: S14 sends TERM only (a non-interactive shell's background job ignores INT, so a static check of the trap line) -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:677]
- [x] [Review][Patch] `shim_checks`' header says "at least shim_min" where the code needs more than it, and two failure lines do not name the call count -- low, fix-risk low, in-story, clear [docker/tests/lib-stub.sh:112]
- [x] [Review][Patch] S1's address-check comment claims more than it checks -- low, fix-risk low, in-story, clear [docker/tests/test-online-load.sh:348]
- [x] [Review][Patch] A progress line prints the server's incident state without `clean()` -- low, fix-risk low, in-story, clear [release/demo-load.sh:533]
- [x] [Review][Patch] A failed sign-out of a half-failed sign-in is overwritten with `signout=-` -- low, fix-risk low, in-story, clear [release/demo-load.sh:772]
- [x] [Review][Patch] The one more visitor's table row hard-codes `-` under Signed out, so a failed sign-out of an admitted extra is never shown -- low, fix-risk low, in-story, clear [release/demo-load.sh:860]
- [x] [Review][Patch] A units command of white space only prints `UNITS before=- load=- after=-` instead of `UNITS n/a` -- low, fix-risk low, in-story, clear [release/demo-load.sh:845]
- [x] [Review][Defer] H8's "the busy page in place of a 503" is never exercised by run 3 during the load run's `--hold`: busy there comes from the visitor count and IRIS serves its own busy splash, while IRIS answers 503 only at the cap of 8 connections (AD-13) [release/demo-host-checks.md:47] -- deferred: pre-existing (run 3 accepts IRIS's busy splash by Story 29.3's design; this story's edit only renamed the occasion), med, fix-risk low, in-epic; how H8's 503 mapping is shown on the host is the Planner's call (DW-464, decision-pending)

**Rejected:**
- `low` B1: a change to `release/demo-load.sh` runs every IRIS group -- by-design: the spec puts it in `IRIS_INPUT` (Tasks, CI); a claimed path never reaches `NOT_IRIS_INPUT_PATTERN` (DW-465, by-design).
- `low` B2: the CI estimates differ (comment "2 to 3 min", Auto Run Result "1.5 to 2"), and shards-2 is near REL-4's 35 min -- both are labelled inference; the rebalance is the lead's.
- `low` B5: after a signal, a second Ctrl-C is ignored while the sign-outs run, up to 30 s per request against a host that stops answering -- a second signal that aborts would give up the cleanup guarantee (DW-466, wontfix-accepted).
- `false` B6 (part): `shim_min` leaking -- `shim_checks` never exits early, and S12 resets it on every path.
- `low` B9/E8: `origin_ok` accepts a value with a line break -- the same behaviour as `demo-host-check.sh` before; such a URL fails loudly (exit 2, host unreachable).
- `low` B10: row 15's scans skip `lib-online.sh` -- the release scripts use only `gate_read`, `gate_config`, `origin_ok` and `pct` from it, none sends a request; S1 records every method the stand-in sees.
- `low` B11: the hold prints no end line, and 60 s against run 3's length -- run 3's busy checks are a handful of requests; a late run 3 fails loudly on busy-status, never passes.
- `low` E4: `UNITS load=` skips a `?` reading -- the `?` shows in the visitor's line; fixing it adds a branch.
- `low` E5/E12: a `createdAt` in another form makes the notice wait 120 s with the wrong reason -- the server writes UTC whole seconds (T0-b) (DW-467, wontfix-theoretical).
- `false` E6: a non-approval phone item after the press -- the spec defines the notice as the first phone item at or after the press, and the demo path sends none before the notice (T0-b, L1).
- `low` E7: a base URL with `:443` sends an `Origin` the server refuses -- the documented commands name no port, and the run fails loudly (403).
- `low` E9: a line break in a server string adds result keys -- the state, fallback reason and error code are enums or fixed codes (DW-468, wontfix-theoretical).
- `false` E11: curl globbing of trace URLs -- the product's trace URLs are `.../EnsPortal.VisualTrace.zen?SESSIONID=<n>`, with no brackets or braces.
- `low` V8: AC10 has no mutation line and CI runs only forward -- by-design: AC10's pin is the lead's fresh check before the push (Rule 19), forward and reverse.
- `low` A4: the units reading accepts trailing text after the two integers -- a lenient parse of the first two integers; tightening risks the live reading.
- `false` A7: `UNITS load=` leaves out the after-sign-out reading -- that reading is `after=`, printed beside it.
- `low` A9: wording drifts ("visitor cap of 6", the head to deploy, the CI estimate) -- cosmetic; the visitor cap setting is 6.

## Spec Change Log

## Review Triage Log

### 2026-10-30 -- Review pass
- verdicts: 34 findings -- high 0, medium 11, low 21, false 2, maybe-false 0
- findings:
  - `medium` `patch` Blind: shim_checks demands only one mode-600 call (was more than 100), shim_min is a hidden global, no secrets hangs grep -- the cfg check now needs more than shim_min calls; shim_checks fails when given no secret; S12 resets shim_min
  - `medium` `patch` Blind: a visitor interrupted between the sign-in POST and the state read is never signed out -- post_signin records every 3xx answer in an opened file; on_signal signs out the union; signin_visitor signs out an opened visitor whose state read failed; S9 state=500 run pins it
  - `low` `patch` Blind: units_start is never checked to be two integers -- load_phase fails first when units_start is not two integers
  - `false` `reject` Blind: the CI time estimate for the load phase looks too low -- measured 33 s for the phase on the throwaway (wait_baseline waited 0 s); the estimate scales that by the runner factor
  - `low` `patch` Blind: the one more visitor reads busy only for N at the cap, with no note -- header of demo-load.sh now says N must be 6 (3 with --trace) and what the line reads otherwise
  - `low` `patch` Blind: server text (fix, fallback, why) is printed unsanitised into lines and the table -- clean() maps anything outside letters, digits and . _ , : / space - to _ before printing
  - `low` `reject` Blind: a late-resolving incident of the browser step could skew L1's row counts -- rejected low: two full live runs and the subagent's runs counted +5 each; the fix would add a settle wait and complexity
  - `low` `reject` Blind: lib-online.sh and lib-stub.sh are outside row 15's ASCII and host-literal scan -- test-boundaries.sh already holds every file under docker/ to ASCII and no local path; the libraries hold no host literal
  - `medium` `patch` Edge: sign-in POST succeeds but the state read answers 000 or 5xx, session never ended -- same root cause as the interrupted sign-in; fixed with the opened file
  - `medium` `patch` Edge: INT or TERM after the sign-in POST and before the signed list entry -- same root cause; on_signal reads opened as well as signed
  - `medium` `patch` Edge: the extra visitor admitted whose state read fails is never ended -- a 3xx answer already counts as admitted and is signed out; the opened file covers a signal; same root cause
  - `low` `reject` Edge: the units command has no time limit -- rejected low: the command is the author's own, a bounded wait needs a portable timeout the script does not have (no timeout on macOS)
  - `low` `reject` Edge: a hold of 90 s with trace pages opened earlier may outlast the busy state -- by-design: the spec bounds the hold at 90 s with --trace; the Planner reads the HOLD line and the busy state live
  - `low` `reject` Edge: createdAt with an offset or fractional seconds is unreadable -- the server writes UTC whole seconds (T0-b); the script strips fractions and reports 'unreadable' loudly
  - `low` `patch` Edge: units_start unvalidated in the phase -- same root cause as the Blind finding
  - `low` `reject` Edge: table_counts with non-numeric fields breaks the arithmetic -- rejected low: the SQL is the unit's own and a failure already fails the phase's checks
  - `low` `reject` Edge: L1 and L2 have no timeout inside the 150 s reserve -- rejected low: the phase measured 33 s; the unit's own deadline check precedes it
  - `low` `patch` Edge: L2 starts without waiting for the baseline -- wait_baseline and a baseline check run before L2; L2 fails with the reason when it is not back
  - `low` `patch` Edge: shim_checks with no secret reads stdin and hangs -- same root cause as the first Blind finding
  - `medium` `patch` Edge: the mode-600 call count lost its 100 minimum -- same root cause as the first Blind finding
  - `medium` `patch` Edge: the cleanup claim holds only after the state read -- same root cause as the interrupted sign-in
  - `false` `reject` Edge: AC6 versus addresses on curl command lines -- AC6 forbids credentials, the published account and tracked host literals; --interface and X-Forwarded-For addresses on the command line are the spec's own mechanism
  - `medium` `patch` Gap: the notice filter (at or after the press) has no distinguishing test -- stand-in flag early-phone and an S1 run; mutation line written
  - `medium` `patch` Gap: TURNS FAIL is never exercised -- stand-in flag extra-turn and an S2 run; mutation line written
  - `medium` `patch` Gap: the one more visitor's address is never asserted -- S1 counts requests with the 7th X-Forwarded-For; S12 loops over visitors 1 to 7 on the -D header path; mutation line written
  - `medium` `patch` Gap: Visual Trace failure verdicts have no test -- S3 gains a fourth visitor run, trace=form and trace=500; mutation line written
  - `low` `patch` Gap: S1's unique t check tests format only -- S1 compares distinct GET URLs; mutation line written
  - `low` `patch` Gap: mutation lines missing or partial for the new pins -- lines added for each new pin; AC10 names its forward/reverse pin
  - `low` `patch` Gap: S13's evaluated-by-no-shell check can pass vacuously -- also requires the UNITS line the run printed
  - `low` `reject` Gap: S5 asserts the exit code only for invalid -- the VISITOR FAIL line is the verdict S5 pins; exit 1 is asserted in S4, S7, S8, S9
  - `low` `patch` Gap: the credentials row's cfg minimum weaker -- same root cause as the first Blind finding
  - `low` `reject` Gap: stand-in session state is shared across rows -- rows end their sessions (sessions_ok) and the reverse run passes
  - `low` `patch` Gap: L2 depends on L1's baseline -- same root cause as the Edge finding
  - `low` `patch` Gap: units_start never validated -- same root cause as the Blind finding
  - Intent Alignment Auditor: descriptive, no findings; it notes `units=-` without a units command (the spec is silent) and that the real-proxy behaviour is H25's.

## Design Notes

**Owner decision `epic29_brief`** (2026-10-30, the Contest Planner under the owner's delegation). It binds. As the orchestrator relays it for this story:
> the demo host is owner-only -- never connect to, deploy to, configure or probe it; never run `ocutalon-demo`, SSH or DNS commands. 29.4's (now this story's) real-proxy load case is the author's on the adapted host: it does not spend the $20 daily cost cap (a load that makes no model calls, or a brief, bounded run), stays within the 8-licence-unit ceiling (DW-287), and its measured results go into the 1.0.0 release notes, not into sharded CI. The script becomes public at 1.0.0: it takes the base URL as an argument and optional gate credentials and driver addresses from the author (environment variables or arguments), holds no host address, IP, gate user, password, token or deployment detail.

Its load-run bullet, as Story 29.7's first plan quoted it:
> The repository delivers what the author runs: a load script in `release/` and its procedure, taking the base URL and the driver addresses from the author, holding no host detail, never spending the $20 daily cost cap, staying within the 8-licence-unit ceiling (DW-287), writing results in a form for the 1.0.0 release notes, never asserted in sharded CI as the real-proxy result. It is proven in CI against a local stack or stand-in with a small bounded run, and never run against the demo host.

**Owner decision `planner_demo_first`** (relayed by the Contest Planner; the owner: "Yes, that should be our plan."). The online demo goes public this weekend, ahead of 1.0.0. So this story closes on throwaway evidence, and the real-proxy case is release check H25.

**Rule 5 (the NFR tripwire): no intent gap.**
- NFR-7's 60 s can be measured on the throwaway. T0-b gives 10-13 s from server timestamps for 6 parallel visitors.
- The mock removes the model's share (diagnosis is at most 20 s of NFR-7's budget). So the throwaway's figure checks the platform's pipeline under load, not NFR-7 for the real model. H25 measures that.
- NFR-23's "about 3 with Visual Trace open" holds, as measured (T0-d, Decided 8).

**Story 29.7 (planned, built first by the lead's order).** This story relies on its rule only through public surfaces (`/status`, its trace form, the splash and the sign-in), and on its helpers moved into lib-online.sh (`host_address`, `set_proxy`, `status_read`, `counter_rows`).
- T0-e shows that L1's and L2's `EXTRA` lines fail without it.
- If 29.7 were reordered after this story, this implement stops with a clarification. It does not copy the helpers (Rule 2), and it does not weaken the busy expectation.
- The script itself depends on no 29.7 code.

**Architecture decisions (Rule 6):**
- AD-13: sign-in, the envelope, busy, the visitor count, the trace form, the client address and the address limit.
- AD-25: the topology, the probe, capacity and the host boundary.
- AD-12: `/state`, polling and the guide.
- AD-15: watch, incident and notice.
- AD-11: approvals and the phone channel.
- AD-26: trace links.
- AD-19: the published accounts, the cap and the reserve.
- AD-20: the daily cap.
- AD-22: tests, throwaways, the mock and CI.
- AD-29: the Epic 29 exception for `release/`.

No AC contradicts an AD's Rule.

**For the lead (Rule 20; this stage does not write the spine).** AD-25's Capacity bullets and AD-13's line on trace units still say "(inference, until Story 29.4 measures...)". T0-a, T0-d, T0-f and T0-g are those measurements on the online-demo configuration of a throwaway. The lead may replace the inference notes on the light path, keeping the ids. The host's own reading stays H25's.

**Integration ACs (Rule 1).** The script is a tool for the author. Its in-repo consumer is `live:online-demo-path`'s load phase (AC1, AC2), against a real stack.
- **Consumed-by:**
  - the Contest Planner's release check H25, on the gated host;
  - the 1.0.0 release notes (the table);
  - the check list's run 3 and H8 (`--hold`).
- **Consumes:**
  - Story 29.3's helpers, check list and test;
  - Story 29.7's visitor count, trace form and helpers;
  - Story 29.4's unit;
  - Stories 16.1 to 16.5's splash, published accounts, sign-in, address counter and `/status`;
  - Lane A's watch, incident and approval path;
  - the mock's `watch-start-orders` and `diagnosis` scenarios;
  - Story 29.6's degraded reasons.

**Extend, don't copy (Rule 2):**
- The gate rules and the origin regex move into lib-online.sh, for both release scripts.
- The credential shim moves into lib-stub.sh, for both tests.
- Row 15's self-scan widens to both release scripts.
- The live phase uses Story 29.7's helpers.
- The sign-in, the sign-out and the requests are new in the script:
  - `online_signin` passes the password on curl's command line, which suits a test's random hex but not the published account;
  - `online_signin` and `logout_all` send no gate, source address or forwarded header, and every request of the script goes through one function that adds them.
  - The field names and the button value follow `host_signin 3`.
- The degraded set lists the probe's three plus `daily_cap`, because the probe is standalone on the host and sources nothing. S16 pins the probe's three inside the script's list.

**Ledger inbox (Rule 17).** DW-286 is addressed:
- the throwaway readings per visitor: T0-a, T0-d and T0-f here, and every run of L2;
- its 16.4 occurrence (a trace tab closed while the page polls): T0-g;
- the host's own reading: H25 (a release check, `pending`).

At adjudication: `resolved-by` this story, with the host reading carried by H25. That is the lead's call.

**footprint_extensions:**
- `docker/tests/lib-stub.sh`: Story 29.3's file, not contended;
- `ci/units.sh`: own entries only (`CHECK_SCRIPTS`, an `IRIS_INPUT` alternative, one comment sentence).

The rest is in Epic 29's footprint: `release/**`, `docker/tests/lib-online.sh` and `docker/tests/test-online-*.sh`. `src/`, `web/`, `ci/mock/` and the spine are unchanged.

**CI.**
- The new hermetic test joins the hosted `checks` job (about 40-70 s, inference; S6 waits 20 s).
- The load phase adds about 2-3 min to `live:online-demo-path` on CI. That is inference: the two cases took 34 s locally in T0, plus the readings and counts (about 70-90 s locally), at the runner's 2.5-3.5x factor. So `shards-2` goes from about 33 to about 35-36 min (inference) -- at REL-4's 35 min.
- With Epic 9's `live:audit` joining `shards-2` at its merge, the lead's rebalance must place this whole unit (about 10-12 min, inference). `image` (about 28) has the most headroom.
- A change to `release/demo-load.sh` alone runs every group through `IRIS_INPUT`.
- The cases sit inside an existing unit, by the orchestrator's preference; a new unit would add a stack start of about 3-4 min on CI.

**Decided in-stage:**
1. Name and interface: `release/demo-load.sh`, one case per run. The Planner runs it twice, as the release check reads.
2. **The driven steps are 1, 2, 4, 5, and 6 with `--trace`.** Step 3 (the reminder) is left out: it adds a turn and a timed wait that neither NFR-7 nor NFR-23 measures.
3. **A model turn is a chat turn or an incident's diagnosis** (T0-c: 2 per driven visitor). `--max-turns` is required and has no default. A 409 `not_watching` is retried, because it starts nothing; nothing that starts a turn is retried.
4. **The notice is timed on the server's clock.** It is waited for up to 120 s, so that a late notice is measured; anything over 60 s is a FAIL.
5. **The one more visitor also presses Sign in** (T0-e: reading the status and the splash alone passed while a sign-in got in).
6. **The busy text** is "The demo is busy right now." with the title "Try OcuTalon". Both IRIS's busy splash and the host's busy page hold it.
7. **The degraded fallbacks:** `no_key`, `timeout` and `rate_limited` (U-157's set) and `daily_cap` (the turns did not use the model) FAIL. Other reasons are reported (the mock's watch decision is `invalid`, T0-c).
8. **Visual Trace open is one page in each trace application the run links to**: 2 connections per visitor, so 3 visitors reach the cap minus the reserve (6). That is P28's "about 3" (T0-d). One page per visitor would hold 3, and the demo would never be busy.
9. **Addresses:** `OCUTALON_LOAD_INTERFACES` for the host and `OCUTALON_LOAD_FORWARDED_FOR` for a local stack only. With neither, at most 4 visitors.
10. **The published account is read from the splash** (the host's own settings). The units command splits on white space without evaluation, by the probe's rule.
11. **`--hold`** gives H8's run 3 its full demo. With `--trace` it is at most 90 s (T0-g: trace connections free 112-133 s after the last page request).
12. **Exit 2 when the demo is not ready or already busy before the run:** nothing would be measured.
13. **Limits:** at most 8 visitors (the licence's 8 connections) and at most 999 turns.
14. **Visitors are named by number.** No address or URL is printed.
15. **`fromGuide` is true only for the guide's own prompt.**
16. **The live proof sits inside `live:online-demo-path`**, whose keys already point at the mock. A local run that needs only the load phase passes `-g "step 1"`.

## Host release check (for the Contest Planner)

On the gated demo host, before the public flip. This story never runs it.
- **The head to deploy:** Epic 29's merge sha, filled in by the lead at the close.
- **The script:** `release/demo-load.sh`, run from a checkout of that head, on a driver machine with bash 3.2 or later, curl and jq.
- **The exact commands.** `https://demo.example` stands for the host's origin, as in the check list.
  - The Planner's environment holds the values for every run:
    - `OCUTALON_LOAD_INTERFACES`: N+1 of the driver machine's source addresses, different for each run, or the same ones an hour later, because of the limit of 5 new sessions per address per hour;
    - `OCUTALON_GATE_USER` and `OCUTALON_GATE_PASSWORD`, while the gate is closed;
    - `OCUTALON_LOAD_UNITS_COMMAND`, optional.
  - Every run starts with no visitor signed in.
  1. Optional, with no model calls (7 addresses):
     ```
     bash release/demo-load.sh https://demo.example --visitors 6 --max-turns 0
     ```
  2. Case 1 (7 addresses):
     ```
     bash release/demo-load.sh https://demo.example --visitors 6 --max-turns 12 --hold 60
     ```
     While its `HOLD` line shows, run `bash release/demo-host-check.sh https://demo.example --state busy` in another terminal (run 3, H8).
  3. Case 2 (4 addresses):
     ```
     bash release/demo-load.sh https://demo.example --visitors 3 --trace --max-turns 6
     ```
- **Inputs:**
  - The gate credentials and the source addresses (N+1 per run, distinct) come from the Planner's configuration.
  - The account is the published demo account, which the script reads from the host's own splash. It is never a value in the repository.
  - Visitor counts: 6, then 3.
  - Durations: about 1-2 min per case, plus the hold. On the throwaway each case took 17 s with the mock.
  - The model-call budget is 12 + 6 = 18 model turns (0 for the optional run). The Planner reads the gateway's day spend before and after; the cap is $20.
  - The units command is the Planner's own reading of `$SYSTEM.License.InstanceConnections()` and `LUConsumed()`, printing two integers, or it is left unset. A terminal takes one connection itself (the throwaway's baseline 1/1), so never read it at 8.
- **The licence units** (Story 29.4's Task 0 and T0-a, T0-d, T0-f and T0-g here):
  - a signed-in visitor holds none;
  - each open trace application session holds one connection; with `--trace` a visitor opens two;
  - the unit is keyed by user and TCP peer, so through the proxy all visitors share one;
  - sign-out frees at once, and leaving frees in about 2 minutes (112-133 s, even while the page polls).
  - Case 1 peaks at no trace connection. Case 2 peaks at 6 (the cap 8 minus the reserve 2), plus the reading's own.
- **A pass:**
  - both cases exit 0;
  - every notice is within 60 s;
  - no turn or incident falls back for `rate_limited`, `timeout`, `no_key` or `daily_cap`;
  - the gateway's log shows every 429 retried with back-off before any fallback (host-only);
  - the one more visitor's line is `EXTRA PASS status=busy splash=busy signin=busy`: busy at the visitor cap of about 6 in case 1 (Story 29.7's count), and at 6 trace connections in case 2, and never an error page.
  - `UNITS load=` is the highest reading of the run: in case 2 the baseline plus 6 connections (7/2 on a throwaway whose idle reading is 1/1); `after=` is the baseline again.
  - The two tables go into the 1.0.0 release notes, and H25 records "measured" with the date.
- **Cleanup:**
  - every visitor signs out (the script does it, Ctrl-C included, exit 130);
  - afterwards `/ocutalon/public/status` reads `"busy":false`;
  - no `demo-load.sh` process is left (`pgrep -f demo-load.sh` prints nothing).

## Verification

Every command runs from the worktree root in its own foreground call (`timeout: 600000`). Each live call sets `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement' OCUTALON_RUN_TAG=e29s8i` (abbreviated `<lane C>` below).

**Commands:**
- `(loop)` `bash docker/tests/test-online-load.sh` -- expected: every PASS, exit 0, about 40-70 s.
- `(loop)` `bash docker/tests/test-online-host.sh` -- expected: every PASS, including row 15 for both release scripts and H1 to H25.
- `(once)` `bash docker/tests/test-probe.sh` -- expected: all pass (lib-stub.sh changed).
- `(once)` `bash docker/tests/test-ci-config.sh` -- expected: all pass. `online-load` is in exactly one list, and shards-2's pattern claims the unit's read of `release/demo-load.sh`.
- `(once)` `bash docker/tests/test-ci-changes.sh` -- expected: all pass (`release/x.sh` still runs no group).
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: all pass (no local path or key; ASCII under `docker/`).
- `(once)` `bash ci/checks.sh` -- expected: every block passes, as in the hosted `checks` job.
- `(once)` `<lane C> ci/iris.sh build` -- expected: the image and web bundle build. It runs before the live calls, because Story 29.7 changed `web/`.
- `(loop)` `<lane C> ci/iris.sh live online-demo-path -g "step 1"` -- expected: step 1 and the load phase pass (L1, L2), about 3-4 min (inference).
- `(once)` `<lane C> ci/iris.sh live online-demo-path` -- expected: the whole unit passes in about 5.5-7 min, inside the 540 s deadline. If it dies of the deadline with no failed check, re-run it once with `OCUTALON_LIVE_DEADLINE=900`.
- `(once)` `<lane C> ci/iris.sh teardown` -- expected: nothing tagged `e29s8i` is left. Run it also after a failure.

**Mutations** (Rule 19: apply, observe red, revert, then confirm `git status --short` and `git diff --stat` are unchanged):
- AC1: in `demo-load.sh`, skip `session/end` and the group sign-out -> the live `-g "step 1"` run's L1 check "plain /status not busy afterwards" goes red.
  mutation: applied 2026-10-30 (signout_visitor returns at once); the live `-g "step 1"` run went red on `L1: afterwards the status reads 'true 1 200'` (and L2 on the busy start); reverted, status and diff stat identical.
- AC2: open only the `/ocutalon/trace/ocutalon/` page -> L2 goes red (`trace=1`, `EXTRA FAIL status=free`).
  mutation: applied 2026-10-30 (only `/ocutalon/trace/ocutalon/` opened); the live `-g "step 1"` run went red on L2: `trace=1` per visitor, `EXTRA FAIL status=free splash=form signin=admitted`, readings 1/1,2/2 per visitor; reverted, status and diff stat identical.
- AC3: let every visitor drive whatever M says -> S2 goes red (6 message POSTs).
  mutation: applied 2026-10-30 (`drivers=$visitors`); `ONLY_ROWS=s2` went red on 4 checks (6 message POSTs, `Model turns used: 12 of at most 5.`); reverted, status and diff stat identical.
- AC4: drop the 60 s comparison -> S4 goes red.
  mutation: applied 2026-10-30 (the comparison removed); `ONLY_ROWS=s4` went red (`notice=61` PASS, exit 0); reverted, status and diff stat identical.
- AC5: skip the readiness/busy precondition -> S10 goes red (sign-ins recorded).
  mutation: applied 2026-10-30 (both precondition checks removed); `ONLY_ROWS=s10` went red (`ready=false`: exit 1 with 24 requests; busy: 7 requests); reverted, status and diff stat identical.
- AC6: post the sign-in with `--data-urlencode "IRISPassword=$p"` -> S12 goes red (the published password on a command line).
  mutation: applied 2026-10-30 (the password also posted as `--data-urlencode`); `ONLY_ROWS=s12` went red in both runs (`7 of 100 command lines hold a secret`); reverted, status and diff stat identical.
- AC7: remove the signal trap's sign-out -> S14 goes red.
  mutation: applied 2026-10-30 (the handler's sign-out loop removed); `ONLY_ROWS=s14` went red (3 sessions opened, none ended; no 401 reads); reverted, status and diff stat identical.
- AC8: `gate_config` writes mode 644 -> `test-online-host.sh`'s credentials row goes red.
  mutation: applied 2026-10-30 (`gate_config` chmod 644); `test-online-host.sh` went red on `credentials: 0 calls read a mode 600 configuration, 101 another mode` and on row 15's chmod check; reverted, status and diff stat identical.
- AC9: change one word of the default watch text -> S16 goes red.
  mutation: applied 2026-10-30 (`tell me if anything needs me`); `ONLY_ROWS=s16` went red (the default text differs from the guide's; the body sent carries the changed text); reverted, status and diff stat identical.
- AC3 (the turn bound, observed): `TURNS FAIL`.
  mutation: applied 2026-10-30 (the guard `if [ "$turns_used" -gt "$max_turns" ]` made `if false`); `ONLY_ROWS=s2` went red (`S2: extra turns: exit 1; Model turns used: 6 of at most 4.`, no TURNS FAIL line); reverted, status and diff stat identical.
- AC1/AC4 (the notice is the first phone item at or after the press): the stand-in's `early-phone` flag.
  mutation: applied 2026-10-30 (the `>= startedAt` comparison made `>= 0`); `ONLY_ROWS=s1` went red (`notice=-30`, `why=the notice time is unreadable`); reverted, status and diff stat identical.
- AC1 (every page GET has a unique `t`): S1's distinct-URL check.
  mutation: applied 2026-10-30 (`t_next` writes the constant `$1x1`); `ONLY_ROWS=s1` went red (`69 GETs, 33 distinct URLs`); reverted, status and diff stat identical.
- AC6 (each visitor, the one more visitor included, uses its own address): S1's X-Forwarded-For check and S12's `--interface` loop over visitors 1 to 7.
  mutation: applied 2026-10-30 (the one more visitor's requests use visitor 1's interface and forwarded address); `ONLY_ROWS='s1 s12'` went red (`0 requests carry the one more visitor's address`, `visitors without their own --interface: 7 7(other)`); reverted, status and diff stat identical.
- AC4 (Visual Trace verdicts): S3's fourth visitor and its `trace=form` run.
  mutation: applied 2026-10-30 (the `HOST_FORM_FIELD_RE` branch made `elif false`; then the busy-form branch made `if false`); `ONLY_ROWS=s3` went red each time (`trace form: ... PASS ... trace=2`; `four visitors: ... PASS ... trace=2`); reverted, status and diff stat identical.
- AC7 (a session opened by a sign-in whose state read failed is signed out): S9's `state=500` run.
  mutation: applied 2026-10-30 (the record of an opened session removed from `post_signin`); `ONLY_ROWS=s9` went red (`opened [s5 s6], ended [s6], wanted 2 session(s), each ended`); reverted, status and diff stat identical.
- AC10 (standing): no mutation line; its pin is the forward and reverse run (`TEST_REVERSE=1`) of `test-online-load.sh`, which passed in both orders.
- (QA) AC7 (`--hold` keeps the visitors signed in): S15.
  mutation: applied 2026-10-30 (the hold block made `if false`); `ONLY_ROWS=s15` went red (`a session did not poll for 2 s (last span -1 ms)`); reverted from a backup, status and diff stat identical.
- (QA) AC7 (the licence readings appear as `c/u`): S13.
  mutation: applied 2026-10-30 (the visitor's units always blanked); `ONLY_ROWS=s13` went red (`units=-` in the line with `UNITS before=3/2`); reverted, status and diff stat identical.
- (QA) AC4 (the one more visitor admitted): S7.
  mutation: applied 2026-10-30 (the sign-in dropped from the `EXTRA PASS` condition); `ONLY_ROWS=s7` went red (`EXTRA PASS status=busy splash=busy signin=admitted`); reverted, status and diff stat identical.
- (QA) AC4 (the one more visitor meets an error page): S8.
  mutation: applied 2026-10-30 (the splash dropped from the `EXTRA PASS` condition); `ONLY_ROWS=s8` went red (`EXTRA PASS ... splash=error`); reverted, status and diff stat identical.
- (QA) AC4 (a `daily_cap` fallback): S5.
  mutation: applied 2026-10-30 (`daily_cap` removed from `DEGRADED_REASONS`); `ONLY_ROWS=s5` went red (`VISITOR 1 PASS ... fallback=daily_cap`); reverted, status and diff stat identical.
- (QA) AC4 (a failed `session/end`): S9.
  mutation: applied 2026-10-30 (every `session/end` answer accepted); `ONLY_ROWS=s9` went red (`VISITOR 1 PASS ... signout=ok`); reverted, status and diff stat identical.
- (QA) AC3 (never re-send; a watch that does not start): S6.
  mutation: applied 2026-10-30 (the `not watching` failure removed); `ONLY_ROWS=s6` went red (`VISITOR 1 PASS ... turns=1 notice=-`); reverted, status and diff stat identical.
- (QA) AC5 (`--trace` needs `M >= 2N`): S3.
  mutation: applied 2026-10-30 (the bound removed); `ONLY_ROWS=s3` went red (`--trace --max-turns 5: exit 1, record 68 lines`); reverted, status and diff stat identical.
- (QA) AC5 (a list of the wrong length): S11, after the fix below.
  mutation: applied 2026-10-30 (the length check made a no-op); `ONLY_ROWS=s11` went red (`a list of the wrong length: exit 1, 50 requests`; `an interface list of the wrong length: exit 2, 0 requests`); reverted, status and diff stat identical.
- (QA) AC5 (both lists are never set together): S11. The pin was unfalsifiable: with the check gone, the run still ended with exit 2 and an empty record, because the interface list pointed at an address that does not exist and the first request failed. `expect_usage` now also requires the script's `usage:` line on stderr, which only a usage error prints (a missing answer prints none), and the "both lists" row uses a list of the right length (`ifc4`) so only the check can stop it.
  mutation: applied 2026-10-30 (the both-lists check made `if false`); before the fix `ONLY_ROWS=s11` stayed green (the unfalsifiable pin); after the fix it went red (`both lists: exit 2, 0 requests`); reverted, status and diff stat identical.
- (QA) File list: no new test file. Changed: `docker/tests/test-online-load.sh` (`ifc4`, `expect_usage` requires the `usage:` line). Forward and `TEST_REVERSE=1` runs both pass (54 script runs, about 52 s).
- (CR) AC7 (a TERM while a sign-in POST waits for its answer still signs that session out): S14's `signin=slow` run.
  mutation: applied 2026-10-30 (`on_signal` reads `opened` in place of `posting`); `ONLY_ROWS=s14` went red (`opened [s4 ], ended []`); reverted, status and diff identical.
- (CR) AC7 (INT, TERM and HUP alike): S14's trap check.
  mutation: applied 2026-10-30 (INT dropped from the trap line); `ONLY_ROWS=s14` went red (`the script's signal trap is not on_signal for INT, TERM and HUP`); reverted, status and diff identical.
- (CR) AC1/AC4 (a driver that ends first keeps polling until the last driver ends, so no session idles to its CSP timeout): S2's `slow-turn` run.
  mutation: applied 2026-10-30 (the driver's `wait_visitor` after its path removed); `ONLY_ROWS=s2` went red (`longest pause between visitor 2's state reads 10261 ms`); reverted, status and diff identical.
- (CR) AC8 (H25 is `pending`): `test-online-host.sh`'s H25 check.
  mutation: applied 2026-10-30 (H25's status made the `measured ... re-check at the release deploy` text); `test-online-host.sh` went red (`H25 reads 'measured ...', not pending`); reverted, status and diff identical.
- (CR) AC2/AC7 (`UNITS load=` is the run's highest reading): S13's rising-and-falling run.
  mutation: applied 2026-10-30 (`u_load` set to the one more visitor's reading); `ONLY_ROWS=s13` went red (`UNITS before=1/1 load=4/2 after=1/1`); reverted, status and diff identical.
- (CR) AC6 (no secret on a command line, in any form a command line could carry it): S12 with the percent-encoded account and the base64 gate value.
  mutation: applied 2026-10-30 (the sign-in body posted as `--data-binary "$(cat ...)"`); `ONLY_ROWS=s12` went red in both runs (`7 of 106 command lines hold a secret`), which the raw secrets alone do not catch; reverted, status and diff identical.
- (CR) AC5 (a gate credential with a line break is a usage error): S11.
  mutation: applied 2026-10-30 (`gate_read`'s line-break case made to match only `\x01`); `ONLY_ROWS=s11` went red (`a gate password with a line break: exit 2, 1 requests`); reverted, status and diff identical.
- (CR) AC4 (the one more visitor on a busy page with no form): S8's `extra=page` run.
  mutation: applied 2026-10-30 (the `account.body` branch removed); `ONLY_ROWS=s8` went red (`EXTRA FAIL status=busy splash=busy signin=error`); reverted, status and diff identical.
- (CR) Printed server text (`clean`): S5's `fallback=a|b<c` run.
  mutation: applied 2026-10-30 (`clean` prints its input unchanged); `ONLY_ROWS=s5` went red (`fallback=a|b<c`, and the table row split by the `|`); reverted, status and diff identical.
- (CR) The sign-in classes: S9's `signin=busy`, `signin=limit` and `signin=refused` runs.
  mutation: applied 2026-10-30 (`LIMIT_TEXT` changed); `ONLY_ROWS=s9` went red (`signin=limit: ... signin=error`); reverted, status and diff identical.
- (CR) File list: no new test file. Changed: `docker/tests/test-online-load.sh` (the stand-in's generation reset and its `signin`, `slow-turn` and `extra=page` flags; rows S2, S5, S8, S9, S11, S12, S13 and S14; `load_until`), `docker/tests/test-online-host.sh` (H25 `pending`) and `docker/tests/lib-stub.sh` (`shim_checks`' wording). Forward and `TEST_REVERSE=1` runs both pass (62 script runs, 85 s). `test-online-host.sh` (135 checks), `test-ci-config.sh`, `test-boundaries.sh` and `test-probe.sh` pass. `ci/iris.sh live online-demo-path` (fresh, lane C) passes in 203 s: the load phase 34 s, L1's notices 10 to 12 s, L2's readings 1/1, then 3/2, 5/2 and 7/2, then 1/1; teardown left nothing.

**Shared surfaces:**
- the check list's H rows (H1 to H25);
- `CHECK_SCRIPTS` and `IRIS_INPUT` in `ci/units.sh`;
- lib-online.sh's `gate_read`, `gate_config` and `origin_ok`, used by both release scripts;
- lib-stub.sh's shim, used by `test-online-host.sh` and `test-online-load.sh` (`test-probe.sh` sources the file);
- `live:online-demo-path`'s output: the report check reads only Playwright's JSON;
- the stack's proxy address, set and then put back.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `release/demo-load.sh` (the author's load script), its hermetic stand-in test `docker/tests/test-online-load.sh` (rows S1 to S16, in the hosted `checks` job) and a load phase (L1, L2) in `live:online-demo-path`. The gate rules and `origin_ok` moved into `docker/tests/lib-online.sh` and the credential shim into `docker/tests/lib-stub.sh`, shared with `demo-host-check.sh` and `test-online-host.sh`. Release check H25 (`pending`) and the load run section are in `release/demo-host-checks.md`; the "Host release check" section above matches the script.

**Files changed.**
- `release/demo-load.sh` (new, 100755): the load script.
- `release/demo-host-check.sh`: calls `origin_ok`, `gate_read`, `gate_config`; behaviour unchanged.
- `release/demo-host-checks.md`: intro, run 3 and H8 (`--hold`), H25, the load run section.
- `docker/tests/lib-online.sh`: `origin_ok`, `gate_read`, `gate_config`.
- `docker/tests/lib-stub.sh`: `curl_shim`, `shim_checks`.
- `docker/tests/test-online-host.sh`: shared shim, row 15 over both release scripts, H1 to H25.
- `docker/tests/test-online-load.sh` (new): S1 to S16 against the Node stand-in.
- `docker/tests/test-online-demo-path.sh`: the load phase (L1, L2).
- `ci/units.sh`: `online-load` in `CHECK_SCRIPTS`, the `IRIS_INPUT` alternative, one comment sentence (the footprint extensions).

**Review.** 34 findings from the four layers: patches applied for 23 findings (11 medium, 12 low; about nine root causes), none newly deferred (the one existing entry stays), 11 rejected with the reasons in the triage log (2 false, 9 low not worth a fix). The patches: sign-out of a visitor whose sign-in opened a session but whose state read failed or was interrupted (an `opened` list); printed server text sanitised; the shim's mode-600 minimum restored and an empty secret list refused; the units baseline validated and the baseline re-checked before L2; the header says N must fill the demo; new stand-in flags and S rows for the notice filter, `TURNS FAIL`, the one more visitor's own address, the Visual Trace verdicts, unique URLs, and S13/S9 hardening; each with a `mutation:` line.

**Follow-up review recommended: true.** Patched medium findings: 11 (more than one). The unverified risk: the sign-out of a session opened by an interrupted or half-failed sign-in is proved against the stand-in only; the live phase and H25 do not interrupt a sign-in.

**Verification (all on this tree, lane C).**
- `test-online-load.sh` 56 s, all pass, forward and `TEST_REVERSE=1`; `test-online-host.sh` 82 s, all pass; `test-probe.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh` and `ci/checks.sh` (the `online-load` block 55 s) pass.
- `ci/iris.sh live online-demo-path` (whole unit): passes, 177 s on the unit's clock, 3 min 3 s for the call. The load phase took 33 s (L1 16 s, notices 10 to 11 s; L2 16 s, readings 1/1 at each sign-in, 3/2, 5/2, 7/2 after the visitors' pages, 1/1 after the sign-out). Teardown of `e29s8i` left nothing.
- Mutations: nine AC lines and seven new ones, each red then reverted with status and diff stat identical.

**CI estimate (for the lead's rebalance).** The load phase adds about 33 s locally, so about 1.5 to 2 min on CI at the runner factor of 2.5 to 3.5 (inference); `shards-2` goes from about 33 to about 34.5 to 36 min, at REL-4's 35. Measured local seconds: `live:online-demo-path` 177 s; `test-online-load.sh` 56 s.

**Residual risks.**
- One reading of the units after the one more visitor was 6/2 against a 7/2 peak in an earlier run (deferred entry above); the script reports the peak as `load`.
- Everything on the host (the proxy, the per-address limit, real model latency and cost, the host's licence units) is H25's, `pending`.
- `units=-` appears in a visitor line when no units command is set; the spec is silent on it.
