---
title: 'Story 29.3: The demo host is adapted for the launch'
type: 'feature'
created: '2026-10-29'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The online demo launches November 2 to 4 on a host that only the author may touch (the Contest Planner acts for the author). Nothing in the repository lets the Planner check, in a repeatable way, that the host's proxy, password guard, busy and maintenance pages, time zone and status match AD-25. So every host-side criterion of this story is unverified, and six routed ledger entries are waiting on that check: DW-214, DW-226, DW-234, DW-240, DW-254 and DW-287.

**Approach:** Ship a read-only host check script in `release/`. It takes the base URL and sends only public reads plus requests that must be refused, all with dummy values. Prove it in the hosted `checks` job against a local stand-in proxy that the test can break one rule at a time. Record every criterion that only the host can satisfy as a release check for the Planner's hands-on pass: pending, or measured by the Planner on the gated host (2026-10-30, the Epic 16 deploy) and re-checked at the release deploy, never asserted by the script. The rest of the repository work, DW-233 (the address key) and DW-260/DW-94 (the probe and the cap text), is split into Stories 29.5 and 29.6 (the lead's ruling of 2026-10-30, under Design Notes, "Lead rulings"); this story does not plan or build it. The guard checks follow AD-25 as the lead's ruling U-158 reads it (Design Notes, "Lead rulings"): a sign-in body's decoded names all come from the four, and the pattern refuses every matching field except a sign-in body's one `IRISPassword`.

## Boundaries & Constraints

**Always:**
- Owner decision `epic29_brief` binds; it is quoted under Design Notes.
- Interface:
  - Usage: `bash release/demo-host-check.sh <base-url> [--state normal|busy|maintenance] [--demo-status FILE|-] [--zone FILE|-]`. The default state is `normal`, and at most one input may be `-`.
  - Environment variables, all optional:
    - `OCUTALON_GATE_USER` and `OCUTALON_GATE_PASSWORD`: basic auth for the access gate.
    - `OCUTALON_CHECK_BLOCK_STATUS`: the statuses the proxy and the guard refuse with, space-separated (default `403`; a 401 or 407 in it is a usage error).
    - `OCUTALON_CHECK_BLOCK_MARK`: a text the proxy's block answer carries, in a header or the body.
  - Gate credentials reach curl only through a mode-600 temporary curl config, never through argv, and are never printed.
- Requests are either public reads (`/ocutalon/public/status`, the splash, one static broker file, the pages and logos) or refusal probes. Every POST uses dummy values: user `zz-host-check`, passwords `dummy-old` and `dummy-new`, token `dummy-token`. Neither published account's name or password is ever used.
- The methods are GET and POST only. Nothing is retried, and every request has a 30 s limit.
- Output is one line per check, `PASS|FAIL|SKIP <id> <text>`, then a summary line.
- Exit codes:
  - `0`: every check ran and passed.
  - `1`: any check failed.
  - `2`: a usage error, a missing tool (bash 3.2 or later, curl, jq), or the host or the gate refusing the first credentialed status read. Nothing else runs after this.
  - `3`: nothing failed, but a check was skipped because an optional input was missing.
- A block check (`block-*`, `block-pw-*` and the guard's refusals) passes only when the status is one of the block statuses, the body holds no IRIS form field (`IRISPassword`, `IRISOldPassword`), and, if the block mark is set, the mark is present. IRIS answering a probe itself never counts as a block: with no mark set, when IRIS's own answer to that probe (`host_probes`, below) has the same status and no form field, the check is `SKIP <id> ambiguous`, never `PASS`; a set mark that an allowed answer also carries fails `block-mark`. A 401 or 407 never passes a block check.
- The S17 password-change forms and the refusal probes, with IRIS's own answer to each (`host_probes`, measured on build 154 and pinned by the live `online-demo` unit), are defined once, in `docker/tests/lib-online.sh`. The live test, the stand-in test and the script all use that definition.
- The script and `release/demo-host-checks.md` hold no host address, IP, host name, gate user, password, token or deployment detail. Examples use `https://demo.example`. Files under `docker/tests/` are ASCII only. The script runs on bash 3.2.

**Never:**
- Connect to, deploy to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands. Look for the host's configuration or runbook.
- Mark a host-only criterion as passing. A release check stays `pending` until the Planner records it.
- Use PUT, DELETE or PATCH, a real sign-in, or any request meant to change state.
- Add an IRIS live unit or change a CI group. Edit `release/standalone-bridge.sh` (Epic 13's) or Epic 15's `release/ipm*` files.

## I/O & Edge-Case Matrix

Every row runs `release/demo-host-check.sh` against the stand-in in `docker/tests/test-online-host.sh`. "Fault" means the stand-in breaks one rule.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| 1 | A correct host | Normal state, gate credentials, `--demo-status` fixture, `--zone` `America/New_York` | Every check PASS, exit 0 | none |
| 2 | Allowed paths | `/ocutalon/` (splash markers as `docker/probe.sh` reads them), `/ocutalon/public/status`, a static `/csp/broker/` file (from Task 0 (b)) | `PASS allow-*` | Fault: the splash path is blocked, giving `FAIL allow-splash`, exit 1 |
| 3 | Blocked paths | `/csp/sys/`, `/csp/user/`, `/api/mgmnt/`, `/api/monitor/metrics`, `/api/atelier/`, `/ui/`, `/mcp/`, `/mcp/ocutalon`, `/ocutalon/hook`, and `/ocutalon/../csp/sys/` sent as is (`--path-as-is`) | `PASS block-*` | Fault: one path passes to the fake IRIS, giving `FAIL block-<id>` with the path, exit 1 |
| 4 | DW-214 | `%25CSP.PasswordChange.cls` at `/ocutalon/trace/ocutalon/`, `/ocutalon/trace/ocuorders/`, `/ocutalon/`, `/ocutalon/api/`, `/ocutalon/public/` and `/csp/broker/`, also as `%25csp.passwordchange.cls`, `%25CSP.PASSWORDCHANGE.CLS`, `%25CsP.PaSsWoRdChAnGe.cls`, `%25%43SP.PasswordChange.cls`, `%25%43SP.Password%43hange.cls` and the double-encoded `%2525CSP.PasswordChange.cls`; at both trace paths every form again with the query string `?x=1` (the forms the Contest Planner measured on the gated host, 2026-10-30) | `PASS block-pw-*` | Fault: one variant is let through (the fake IRIS answers it as IRIS does, `host_probes`), giving `FAIL block-pw-<id>` naming the path |
| 5 | The guard's refusals | F1 to F11 from `password_form` at `/ocutalon/`; F1 and F3 also at `/ocutalon/api/v1/state` and both trace apps' `EnsPortal.MessageViewer.zen`; F12's post to both trace `%25CSP.PasswordChange.cls`; a sign-in body with an extra name `x=1`; a 64 KiB sign-in body; `IRISPassword` in a GET query string; a urlencoded `IRISPassword` POSTed to `/ocutalon/api/v1/messages` | `PASS guard-*` | Fault, one per rule (multipart, chunked, names not URL-decoded, case-sensitive pattern, legacy names, query string, extra name, size), giving `FAIL guard-<id>` |
| 6 | DW-226 | The splash's three-field POST (`IRISUsername`, `IRISPassword`, `IRISLogin=Sign in and start`) to `/ocutalon/`; the trace sign-in page's four-field POST (with `IRISSessionToken`) to a trace app | Both reach IRIS and come back as its sign-in page, refused by IRIS (the splash with `aria-invalid="true"`; the trace page with the refused marker Task 0 (c) measures, since the trace applications show IRIS's own sign-in page), giving `PASS guard-signin-3` and `guard-signin-4` | Fault "exactly four names" (the three-field POST refused), giving `FAIL guard-signin-3` |
| 7 | No false all-clear, every family (`block-*`, `block-pw-*`, `guard-*`) | Faults: (a) a refusal probe let through and answered 401, or 404 while 404 is not a block status; (b) block statuses `403 S` and no mark, where S is the status of IRIS's own form-less answer to a probe that is let through; (c) a mark that an allowed answer also carries | (a) `FAIL <id>` (not the block status); (b) `SKIP <id> ambiguous`, exit 3, never `PASS`; (c) `FAIL block-mark` | none |
| 8 | Gate closed, no credentials | Every request answers 401 | `gate refused` on stderr, exit 2, no block or guard line | none |
| 9 | Gate open while access is restricted | Credentials set; a request without them is admitted | `FAIL gate-closed` | No credentials: `SKIP gate-closed`, exit 3 |
| 10 | The status JSON | A key added or missing, a wrong type, no `no-store`, `lastResetKind` outside {scheduled, unscheduled}, `nextReset` in the past | `FAIL status-<id>` | none |
| 11 | `--demo-status` | The AD-25 keys and types; `lastReset`, `lastResetKind` and `nextReset` equal `/status`'s; `runningVersion` equals `goldenVersion`; `access` restricted with credentials set, `public` without | PASS | Not JSON or a mismatch: `FAIL demo-status-<id>`; not given: `SKIP`, exit 3 |
| 12 | `--zone` | `America/New_York`, `US/Eastern` or `EST5EDT` pass | `PASS zone` | Any other value: `FAIL zone`; not given: `SKIP zone`, exit 3 |
| 13 | Busy (`--state busy`) | `/ocutalon/` and `/ocutalon/zz/deep` answer either `docker/busy.html` byte for byte or IRIS's busy splash with `X-OcuTalon-Busy: 1`; `/ocutalon/api/v1/state` never answers the busy page; `/status` has `busy` true | `PASS busy-*` | One altered byte, or the busy page under `/ocutalon/api/`, gives `FAIL busy-<id>` |
| 14 | Maintenance (`--state maintenance`, DW-240) | `/ocutalon/` and a deep path answer `docker/maintenance.html` byte for byte; the four `logo/web/OcuTalon-Logo-*.png` match byte for byte both beside the page (resolved against `/ocutalon/`) and at `/ocutalon/assets/brand/<name>` | `PASS maint-*` | A logo is missing: `FAIL maint-logo-<name>` |
| 15 | The files are safe to publish | A static scan of the script and the check list | No IPv4 address, `localhost`, `host:port` or URL with a literal host; the script runs no `ocutalon-demo` (comment and usage lines excepted) and uses no PUT, DELETE or PATCH | `FAIL self-<id>` |
| 16 | A correct host that refuses with 404 (the gated host's password-change filter, measured 2026-10-30) | The stand-in refuses the `block-pw-*` family with 404 and the rest with 403; `OCUTALON_CHECK_BLOCK_STATUS='403 404'`; gate credentials, `--demo-status`, `--zone` | With the mark set: every check PASS, exit 0. Without it: no FAIL; each probe whose `host_probes` answer is `403:noform` or `404:noform` gives `SKIP <id> ambiguous` and every other one PASS; exit 3 if any SKIP, else 0 | none |

</intent-contract>

## Code Map

- `docker/tests/test-online-demo.sh`:
  - 105-110 (`CHANGE_FORMS`) and 249-344 (`pct`, `signin_outcome`, `page_token` at 282-284, `form_request` at 288-344) hold the S17 forms F1 to F12. The pure name-and-encoding table moves to `lib-online.sh`; F12's two-step flow, the tokens and the jars stay. 397-410 run the forms (rows 5 and 6) and 412-437 pin that, signed out, IRIS answers each trace `%25CSP.PasswordChange.cls` with 200 and its sign-in page (`name="?IRISPassword`).
  - 1582: the published-passwords section. The new Story 29.3 section goes just before it.
- `docker/tests/lib-online.sh`: 1-20 the header (functions only, sourced after `lib-live.sh`, so the script can source it by its own path); 75-80 `logout_all`, the sign-out pattern (`?IRISLogout=end` on the application and on `/ocutalon/`, on the request's own jar).
- `docker/tests/test-probe.sh`: 13-31, 72-75 and 186-203 are the scaffolding to move into `lib-stub.sh` (`set -u`, the `mktemp` folder, the cleanup trap, `pass`/`fail`, the tool check, the inline `node -` stub on port 0 of 127.0.0.1, the port-file wait); 832-834 the self-pin pattern for row 15.
- `docker/probe.sh`: 131 every GET carries a unique `t` parameter; 147-150 busy is a 503 or `X-OcuTalon-Busy: 1`; 189 the splash markers (`<title>Try OcuTalon</title>` and an `IRISPassword` field); 210-218 the form coming back means refused, `<app-root` means signed in. The probe's live test (`test-online-demo.sh` Story 16.6 rows) pins these against real IRIS.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls:151,178-189` and `Login.cls:27,146-162`: the sign-in form (action `Error:FullURL`, no enctype, fields `IRISUsername`, `IRISPassword`, `IRISLogin`); a failed sign-in brings the page back with `aria-invalid="true"` and fires no `OnLogin`, so it writes no `AddressCounter` row (`Web/SessionEvents.cls:89`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls:214`: `LoginPage` is empty for every application, so the trace applications show IRIS's own sign-in page (row 6's trace marker is Task 0 (c)'s).
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls:46-65`: 200, `application/json`, `Cache-Control: no-store`, `X-OcuTalon-Busy: 1` only when busy; always `ready` (boolean), `nextReset`, `busy` (boolean), `lastReset`, `lastResetKind` (each string or null but the booleans).
- `docker/busy.html`, `docker/maintenance.html`: compared byte for byte; the maintenance page refreshes to `/ocutalon/` after 10 s and names the logos by bare file name. Story 16.8's view (`web/src/app/live/resetting-view.ts:19-28`) asks for `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png`; the sources are `logo/web/`.
- `ci/units.sh:6` `CHECK_SCRIPTS` (append `online-host`); `group_units`: `live:online-demo` is in `install-upgrade` (about 556 s on CI; the group 30.8 min). `ci/checks.sh:7-29` runs `docker/tests/test-<name>.sh` in turn. The hosted `checks` job (`.github/workflows/ci.yml:30-43`, read-only) runs on every push and `ci/changes.sh` never skips it, so a change under `release/` runs the new test (`test-ci-changes.sh:243` keeps "release runs no group"). `bash ci/checks.sh` takes about 123 s of the job's 15 minutes.
- `docker/tests/test-ci-config.sh:624-650`: every `docker/tests/test-*.sh` is in exactly one list.
- `docker/tests/test-boundaries.sh:34-42,94-96`: the local-path and key patterns scan every tracked file, `release/` included; the ASCII rule covers `docker/`.
- `release/standalone-bridge.sh:1-37,209-213` (read-only): the header, `set -u`, the root/cd lines, the summary line, mode 755.
- Spine: AD-25 at 685-736 (the guard 696-701, the probe 719-722, capacity 723-733); AD-13 at 345-395 (`/status` 356, password changes 391-394).

## Tasks & Acceptance

**Execution:**

The tasks follow the lead's rulings of 2026-10-30 (Design Notes): the guard expectations (rows 5 and 6) follow ruling 1 (U-158); row 4's forms and the block criterion (rows 7 and 16) follow ruling 3.

- `docker/tests/lib-online.sh` -- add, bash 3.2, functions only -- one definition for the live test, the stand-in test and the script:
  - `pct` (moved from `test-online-demo.sh`).
  - `password_form <F1..F11> <user> <old> <new> [<token>]`: sets `form_method`, `form_query` and the array `form_args` (curl arguments) and nothing else.
  - `host_probes`: prints one line per refusal probe of rows 3 to 5, `<id> <iris> <method> <target> [<body>]`. `<target>` is the path and query exactly as sent (`--path-as-is`); `<body>` is a `password_form` form or one of `extra`, `big`, `query`, `api`, `F12`; `<iris>` is IRIS's own answer from Task 0, `<status>:form` or `<status>:noform`. Row 4's ids are `block-pw-<path>-<form>[-q]`, with paths `trace-ocutalon`, `trace-ocuorders`, `root`, `api`, `public`, `broker` and forms `canon`, `lower`, `upper`, `mixed`, `c43`, `c43h`, `double` (42 probes, plus 14 `-q` probes at the two trace paths).
  - `host_probe_args <line>`: sets `probe_method`, `probe_target` and the array `probe_args` for one line, building F1 to F11 with `password_form`. The `api` body is `text=zz-host-check&IRISPassword=dummy-new`, so it is no sign-in body under ruling 1.
- `docker/tests/test-online-demo.sh` -- `form_request` builds F1 to F11 from `password_form` (F12, the tokens and the jars stay), and rows 5 and 6 behave exactly as before. A new section, "Story 29.3: IRIS's own answers to the host check", before line 1582, sends every item signed out with no proxy, each on a jar of its own ended with `logout_all`, prints one `MEASURED` line per item, then pins:
  - (a) for every `host_probes` line, the status and the IRIS form field (`name="?(IRISPassword|IRISOldPassword)`) equal its `<iris>`;
  - (b) a signed-in trace page (the TraceReader account of `online_values`, signed out after) references the script's `/csp/broker/` file, and IRIS serves that file with 200;
  - (c) row 6's two dummy-value POSTs come back as IRIS's sign-in page with the refused marker the script expects.
  - **Task 0** is this section's first run (`live online-demo`, tag `e29s3i`, Verification): fill `<iris>`, the broker file and the trace page's refused marker from its `MEASURED` lines and copy those lines under Verification.
- `docker/tests/lib-stub.sh` (new) -- `stub_start` (an inline Node server from stdin with its arguments; sets `stub_pid` and `stub_port`, or fails), `pass`, `fail`, `need_tools` and the cleanup trap -- `docker/tests/test-probe.sh` sources it with no change in behaviour.
- `release/demo-host-check.sh` (new, mode 755) -- implement the Boundaries interface and rows 2 to 16:
  - Check ids are stable: `allow-*`, `block-*`, `block-pw-*`, `guard-F<n>[-<where>]`, `guard-*`, `guard-signin-3`, `guard-signin-4`, `gate-closed`, `block-mark`, `status-*`, `demo-status-*`, `zone`, `busy-*`, `maint-*`.
  - It sources `docker/tests/lib-online.sh` by its own path and sends `host_probes`' probes exactly as listed.
  - States: `normal` runs the allow, block, guard, gate, mark, status, demo-status and zone checks; `busy` the status read and `busy-*`; `maintenance` only `maint-*`. The first credentialed request (the status read; `/ocutalon/` in maintenance) answered 401 or 407, or unreachable, exits 2.
  - Allowed reads carry a unique `t=<n>` parameter (`docker/probe.sh:131`).
  - Each request runs on a jar of its own. An answer that sets an IRIS session cookie is followed by `?IRISLogout=end` on its application and on `/ocutalon/` with that jar, through the gate config (`logout_all`'s two requests).
  - `guard-signin-4` posts `IRISSessionToken=dummy-token` with the three other names to `/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen`.
  - The header says what the script checks, its inputs, the settings the Planner uses (`release/demo-host-checks.md`) and its exit codes, and that its dummy-value requests leave failed-sign-in entries in the host's audit log.
- `docker/tests/test-online-host.sh` (new, mode 755, ASCII) -- the matrix's test:
  - A Node stand-in on `lib-stub.sh`: the proxy and the guard of AD-25 as ruling 1 reads it (a sign-in body is a bounded urlencoded POST body whose names all come from the four; its one `IRISPassword` is the only exception), in front of a fake IRIS that answers each `host_probes` probe with its `<iris>` and the allowed reads, the sign-in POSTs and the pages as Task 0 measured.
  - Row 1 and the fault runs of rows 2 to 14 set the block mark (the stand-in's refusals carry it), so their verdicts do not depend on which probes IRIS itself answers with 403; rows 7 (b) and 16 run without it, and row 7 (c) sets one that an allowed answer carries.
  - Random basic-auth gate credentials per run, never printed. Fault flags, the refusal status of each family and a block-mark header are read per request from a flags file, so rows 7 and 16 need no restart.
  - The fake splash sets a session cookie; row 1 also asserts that the stand-in saw that session's sign-out and no method but GET and POST.
  - Row 7 (b)'s probe is the first `host_probes` line whose `<iris>` is `noform` with a status other than 401 or 407 (Task 0 names it; expected a `block-pw-*-double` probe, which IRIS decodes once to a class that does not exist, inference).
  - It serves busy and maintenance from the repository's files, runs the script once per matrix row and fault, and asserts the exit code, the named `PASS`, `FAIL` or `SKIP` line and no other `FAIL`.
  - Row 15's static scan covers the script and the check list. It also asserts the check list's rows H1 to H24, each with one of the three statuses of the H table.
- `ci/units.sh` -- append `online-host` to `CHECK_SCRIPTS` (this story's own entry).
- `release/demo-host-checks.md` (new) -- for the Planner, with `https://demo.example`:
  - The three runs: (1) normal, with `--zone` and `--demo-status`; (2) during a reset, `--state maintenance`; (3) while full, `--state busy`.
  - The settings: `OCUTALON_CHECK_BLOCK_STATUS` set to every status the host refuses with (the gated host's password-change filter answered 404 when the Planner measured it, 2026-10-30, so `'403 404'` unless the other blocks differ); `OCUTALON_CHECK_BLOCK_MARK` set to a text only the host's refusals carry, which turns every `SKIP ... ambiguous` into a verdict (the script fails `block-mark` if an allowed answer carries it); the gate credentials.
  - The H1 to H24 table from Design Notes with its statuses, citing "measured on the gated host by the Contest Planner, 2026-10-30" where measured.
  - Sections for the probe's host interface (DW-254), the licence-unit check (DW-287), the logo placement (DW-240) and the proxy-address check (DW-234).

**Acceptance Criteria:**
- Given the stand-in with every rule of AD-25 as ruling 1 reads it, when `test-online-host.sh` runs the script in the normal state with gate credentials, the block mark, `--demo-status` and `--zone`, then every check passes and the script exits 0. The same run against each fault of rows 2 to 14 exits 1 (2 for row 8, 3 for a skip), with the `FAIL` line of that fault's check id and no other `FAIL`.
- Given a host that lets one DW-214 form through (any of row 4's seven forms, at any of its six paths, with or without the query string), when the script runs, then it fails `block-pw-<id>` naming that path.
- Given the guard of AD-25 as ruling 1 reads it, when the script sends the splash's three-field and the trace page's four-field sign-in POSTs with dummy values, then both reach IRIS and come back refused by IRIS (DW-226). A guard that requires all four names fails `guard-signin-3`.
- Given a refusal probe answered with 401, 404 or any status that is not a block status, when the script runs, then that check fails; given a block status that IRIS itself gives to a probe that is let through and no mark, the check is `SKIP ... ambiguous` and the script never exits 0; given a mark that an allowed answer carries, `block-mark` fails. With a closed gate and no credentials, it exits 2 before any block or guard check. So it never reports an all-clear it did not observe.
- Given a host whose refusals answer 404 (row 16), when the Planner's settings of the check list are used, then the run passes (exit 0 with the mark) without counting any answer of IRIS's own as a block.
- Given the busy or the maintenance state, when the script runs in that state, then the pages and the four logos are checked byte for byte against `docker/` and `logo/web/` (DW-240), at both logo locations.
- Given the live `online-demo` unit (the consumer of `password_form` and `host_probes` against real IRIS), when it runs, then rows 5 and 6 pass with the same `CHANGE_FORMS` results as before, and the Story 29.3 section finds IRIS's own answer to every `host_probes` probe, the broker file and row 6's two answers as the script expects them.
- Given a commit that changes only `release/demo-host-check.sh`, when CI runs, then the hosted `checks` job runs `online-host`, and `test-ci-config.sh` passes with it registered.
- Given `release/demo-host-checks.md`, when `test-online-host.sh` reads it, then every row H1 to H24 is present with exactly one of the statuses `pending`, `measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy` or `measured in part 2026-10-30 (Epic 16 deploy); rest pending`, none of them a pass, and row 15's scan of the file is clean.

## Spec Change Log

- 2026-10-30, lead, re-dispatch 1 of the plan: the plan HALTed on AD-25's guard wording and proposed a split. The lead ruled (Design Notes, "Lead rulings"): comply with AD-25 by its stated outcome (veto item U-158, AD text unchanged, DW-226 to the decision sheet); the split into Stories 29.5 and 29.6 accepted; the Planner's measured host facts of 2026-10-30 added. Status reset to `draft` for the re-plan.
- 2026-10-30, plan re-dispatch 1 (runner C): re-planned around the rulings. Inside the intent contract, only the edits the rulings direct (the Approach paragraph is the lead's, unchanged): ruling 3's path forms in row 4 (the `/csp/broker/` probe moved there from row 3); ruling 3's block criterion in Boundaries (a list-valued `OCUTALON_CHECK_BLOCK_STATUS`, IRIS's own answer per probe in `host_probes`, `SKIP ... ambiguous`, `block-mark`), in row 7 (every family) and in the new row 16; ruling 1's "refused by IRIS" in row 6, with the trace page's marker from Task 0 (c). Outside it: the "Proposed siblings" section and the split-only task removed (ruling 2); the H table carries the Planner's measured facts (ruling 3); Task 0 moved from a warm stack to the online unit's fresh stack (Decided in-stage 7); the `multiple-goals` warning dropped. KEEP: the interface, the matrix, `lib-online.sh` / `lib-stub.sh`, `test-online-host.sh` in the hosted `checks` job, the check list, the mutations.

## Review Triage Log

## Design Notes

**Owner decision for Epic 29: the demo host and Story 29.3**. The Contest Planner decided it under the owner's delegation on 2026-10-30 (`owner_decision id=epic29_brief`). It binds, and is quoted verbatim:
> - **The demo host is owner-only (policy).** Never connect to, deploy to, configure or probe the demo host. Never run `ocutalon-demo`, SSH or DNS commands. Never look for the host's deployment configuration or runbook; they stay outside this repository, as 29.3's own criterion says. Opening the access gate is the author's.
> - **29.3's repository work** is what the repository must hold for the host to meet its criteria, tested on throwaway stacks and stand-ins:
>   - **DW-233 (veto U-156, kept):** the address counter stores an HMAC of the client address, keyed by a per-instance secret in the private database and renewed at each reset, instead of a plain SHA-256. The key must never be in the golden copy: a reset restores the golden copy, so a stored key would come back unchanged after every reset. Either the key is made at start whenever the reset marker changes, or it lives outside what the golden copy captures. The spec names which one, and a test proves that two resets give two different keys.
>   - **DW-260 (veto U-157, kept):** the probe gets an alert-only outcome for `no_key`, timeout and `rate_limit` fallbacks. It alerts the author and never counts toward a reset, like busy.
>   - **DW-94:** fix it in the repository if it needs a repository-side change.
>   - **A repeatable host check script in `release/`** that the Contest Planner runs against the gated host. Test it in CI against a local stand-in proxy or stack. The script becomes public at 1.0.0, so: it takes the base URL as an argument, and optional gate credentials from environment variables; it holds no host address, IP, gate user, password, token or deployment detail; it sends only requests that should be refused, with dummy values, never a real account's password; it is read-only against the host and runs no `ocutalon-demo` command (for the `ocutalon-demo status` JSON shape, it reads output piped into it, or the public status endpoint). Its checks: the proxy blocks (DW-214's `%CSP.PasswordChange.cls` paths, including `%25CSP` and mixed case), the password guard's field rules, the busy and maintenance pages, the time zone, and the status JSON shape.
> - **Host-only criteria** are recorded in the spec as release checks for the Contest Planner's hands-on pass on the gated host, never faked as passing. DW-240, DW-254 and DW-287 are the Planner's at the deploy. The Planner's Epic 16 deploy is running now; its measured facts (the U-81/DW-214 table, the time zone, DW-240, the licence units (DW-287), the probe, and EvalIn off) have NOT arrived: record those facts as pending release checks. No guessing.
> - **29.4's real-proxy load case** is the author's (the Planner's pass) on the adapted host. It does not spend the $20 daily cost cap (a load that makes no model calls, or a brief, bounded run) and stays within the 8-licence-unit ceiling (DW-287); its results go into the 1.0.0 release notes, not sharded CI. (Story 29.4's, not this story's.)
> - **Anything that needs a host action** is a `## Clarification Needed` (an intent gap HALT, in this stage).

**Lead rulings (re-dispatch 1, 2026-10-30; runner C, unattended policy 6df0676). They answer this plan's intent gap; re-plan around them and remove the gap:**
1. **AD-25's guard wording (DW-226): comply first, AD text unchanged (doctrine U7 step 1; veto item U-158).** The repository does not implement the guard (it is the host's, owner-only). AD-25 states its own outcome: all eleven S17 forms blocked while sign-in, the app, the JSON API, polling, the trace pages and the broker files keep working. Read against that outcome and the product's real forms, the guard bullets mean: on a sign-in POST, a bounded `application/x-www-form-urlencoded` body whose decoded field names ALL COME FROM `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin` (any may be absent: the splash and the local page post the last three, IRIS's trace sign-in page all four); and any field anywhere, in a query string or any request's body, whose decoded name matches `(IRIS|Cache)(Old|Repeat)?Password` case-insensitively is refused, the one `IRISPassword` of such a sign-in body excepted. The script, the stand-in and matrix rows 5 and 6 follow this reading (keep `guard-signin-3`/`guard-signin-4` as dummy-value POSTs that reach IRIS and come back refused by IRIS, never as a real sign-in). This story does not amend AD-25 or the epics.md criterion: the wording question goes to Epic 29's decision sheet on DW-226. Record this under the AD list below as the reading this story applies, citing U-158.
2. **The split is accepted (decide; doctrine U5, Rule 5 tier 2 within `split_children`).** Stories 29.5, "The address counter's hash is keyed per reset" (DW-233), and 29.6, "The probe alerts when every turn falls back" (DW-260, DW-94), are now in `epics.md` and the tracker, and their ledger entries are re-owned to them. Remove the "Proposed siblings" section and the "Only if the split is not accepted" task (their plans are kept by the lead for those stories' plan stages). Matrix, tasks and check-list rows that pointed at 29.5/29.6 keep pointing at them (H13, H17, H20).
3. **The Planner's measured facts have arrived** (measured on the gated host by the Contest Planner, 2026-10-30, after the Epic 16 deploy of c70a0f4; cite them exactly so, and NEVER copy a host address, host name, image name, IP or deployment detail into any committed file). Record them in the H table and in `release/demo-host-checks.md` as "measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy" rows, never as a script PASS:
   - U-81 / DW-214: IRIS alone serves `%CSP.PasswordChange.cls` with 200 to a signed-in user; the host's filter answers **404** to every path naming it, decoding until stable and ignoring letter case: `/ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls` signed out and signed in, `/ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls`, `%25csp.passwordchange.cls`, `%25CSP.PASSWORDCHANGE.CLS`, `%25CsP.PaSsWoRdChAnGe.cls`, the double-encoded `%2525CSP...`, `%25%43SP.Password%43hange.cls`, each with a query string, and `/ocutalon/%25CSP...` and `/csp/broker/%25CSP...`. The controls `EnsPortal.MessageViewer.zen` (a trace page) and `/ocutalon/public/status` still answer 200. **Carry every one of these path forms in the script's `block-pw-*` checks** (add the double-encoded form, the `%43`/`%43hange` form and a query-string variant to matrix row 4).
   - **Block status:** that filter answers 404, not 403. Design the block criterion so that the Planner's run against such a host can pass WITHOUT a false all-clear (IRIS answering a path itself must never count as a block). Decide in-stage (small, within the owner decision): for example a per-check expected status for the `block-pw-*` family (for these paths IRIS itself answers 200 with the change form, so a 404 carrying no IRIS form field is a block there), or a list-valued `OCUTALON_CHECK_BLOCK_STATUS` together with the "no IRIS form field in the body" rule and the optional mark; keep matrix row 7's "no false all-clear" fault for every family, and say in the check list which settings the Planner uses.
   - Time zone: the container and the agent's input are `America/New_York`; 18:12Z renders "14:12 ET" (H11 measured).
   - DW-240: the four logos answer 200 through the proxy at `/ocutalon/`, `/ocutalon/assets/brand/` and deeper while IRIS is down (H7 measured).
   - DW-287: one licence unit in use, held by the deploy terminal; no host command opens an IRIS terminal; the health check uses `iris qlist` (H22 measured).
   - EvalIn is off: `Enabled=0`, and `OCUTALON_EVAL` is unset (H24 measured).
   - The probe is healthy, and its scheduled run alerted `busy` during the busy test, so the alert path works (H20, DW-254: measured in part; the 15-minute schedule, environment and source address stay the Planner's check).
   - The password guard (S17's check) is installed (H5 measured in part).
   - DW-234: proxied sign-ins write an address-counter row (H2 measured).
   - DW-226: the filter admits the splash's three-field sign-in (H6, consistent with ruling 1).
   - The demo path through the proxy passes sign-in, watch, the reminder to the phone, Break the feed and sign-out; steps 4 and 5 wait on Story 11.1. The Story 16.9 caps work (the third message refused with 429 and `retryAt`; the daily-cap notice sent once).
4. **The Planner's other findings (dispositions are the lead's; nothing to build here):** origin behind TLS (API POSTs got 403 `wrong_origin`; the host maps the exact origin) is DW-416, no repository change in this story; busy one connection lenient is a note on DW-251 (Story 29.4's load case); model-written times without "ET" is DW-417; a reserve not below the cap leaving IRIS never ready is DW-418 (terminal); same-version pre-release deploys and applying DW-233/DW-260 on the host are the Planner's.
5. **AD-25's probe bullet needs no amendment for this story:** an alert-only outcome (Story 29.6's) extends "Only `auth_failed` and `no_decision` count" and contradicts nothing.

**Architecture decisions that govern this story (Rule 6):**
- **AD-25:** the proxy allow-list and blocks, the guard, the pages, the gateway, resets, `ocutalon-demo status`, the probe and capacity. **The guard reading this story applies (ruling 1, veto item U-158; AD text unchanged):** a sign-in POST's bounded urlencoded body has decoded names that all come from `IRISSessionToken`, `IRISUsername`, `IRISPassword` and `IRISLogin`, any of them absent; every field anywhere whose decoded name matches `(IRIS|Cache)(Old|Repeat)?Password` case-insensitively is refused, except that sign-in body's one `IRISPassword`. The wording question is DW-226's, for the decision sheet.
- **AD-13:** the `/status` shape, the sign-in form contract, password changes and the client-address rule.
- **AD-24:** the trace application paths.
- **AD-19:** the online-demo variables, including `OCUTALON_LAST_RESET`, and the endpoint overrides.
- **AD-8 and AD-20:** the cap's 403 and its text, recorded as a release check (H13).
- **AD-22:** testing and CI, the hosted `checks` job.
- **AD-29:** the Epic 29 exception, with `release/` for this story's new files.
- **AD-33:** Lane B keeps the classes.

**Integration ACs:** the shared helpers' consumer is in this story: the live `online-demo` unit reads `password_form` and `host_probes` and runs them against real IRIS (the seventh AC). The script itself has no automated consumer: no consumers in this story; the first consumer will be Story 29.4 (its author load case runs on the host this check list verifies), and before it the Contest Planner's hands-on pass runs the script and the list at the deploy.
- **Consumed-by:**
  - The Planner's release pass, through `release/demo-host-checks.md`.
  - Story 29.4: the adapted host is its real-proxy case's precondition.
  - Story 11.5: its hook relies on `ocutalon-demo status`, and H18 checks that shape.
- **Consumes:**
  - `docker/busy.html`, `docker/maintenance.html` and `logo/web/` (Story 16.5).
  - `/ocutalon/public/status` (Stories 0.5 and 16.1).
  - The splash form (Story 16.2).
  - The probe's markers (Story 16.6).
  - The S17 forms (Story 16.1).

**Extend, don't copy (Rule 2):**
- `password_form` extends `form_request` (`test-online-demo.sh:288-344`) by moving its table to `lib-online.sh`; `host_probe_args` builds on `password_form`. `host_probes` has no sibling.
- `lib-stub.sh` is `test-probe.sh`'s scaffolding, moved and then sourced by both scripts. The stand-in itself has no sibling (`test-probe.sh`'s stub speaks the probe's protocol, not a proxy's).
- The new live section reuses `logout_all`, `next_probe` and `page_token`'s pattern.
- Two copies, each better than reuse:
  - The script's report lines, a five-line copy of the idea in `lib-live.sh`'s `pass`/`fail`: they add check ids and `SKIP`, and a public tool run against a remote host must not source `lib-live.sh`, which assumes throwaway stacks and locks.
  - The script's sign-out, a copy of `logout_all`'s two requests: `logout_all`'s curl cannot carry the gate config.

**footprint_extensions:** `docker/tests/lib-stub.sh` (new; `docker/tests/` is uncontended). The other files are in the footprint: `release/` new files, `docker/tests/test-online-*.sh`, `docker/tests/lib-online.sh` and `docker/tests/test-probe.sh`. `ci/units.sh` gets only this story's own entry.

**Decided in-stage (small, reversible, contradicting no AD):**
1. "Only requests that should be refused" applies to the sign-in and password requests. Public reads (status, splash, a broker file, pages, logos) are needed for the status, page and gate checks and change nothing.
2. **The block criterion (ruling 3).** `OCUTALON_CHECK_BLOCK_STATUS` is a list, and a block needs a listed status, no IRIS form field and the mark when set. IRIS's own answer to every probe is in `host_probes`; when it has a listed status and no form field, only the mark can tell a block from IRIS, so with no mark the check is `SKIP ... ambiguous` (exit 3). `block-mark` fails a mark that an allowed answer carries. The table is measured on the online stack (Task 0) and pinned by the live unit, so a later build that changes an answer goes red there rather than becoming a false all-clear. Build 154, signed out, answers `%25CSP.PasswordChange.cls` at both trace paths with 200 and a form (`test-online-demo.sh:412-437`), so a host's 404 with no form passes there without a mark, as ruling 3's example says; Task 0 measures the other paths and forms.
3. The time zone. No unauthenticated surface reports it: the splash renders times in the browser's zone, and `/status` is UTC. So `--zone` reads the IRIS container's `TZ`, piped in the same way the owner allowed for the status JSON. Adding a zone to `/status` would amend AD-13's fixed shape.
4. Three runs, selected by `--state`. A read-only script cannot make the host busy or reset.
5. The pages are compared byte for byte, so the host must serve the repository's own files unchanged.
6. The oversize probe is 64 KiB, far above any sign-in form.
7. No new live unit. One new section of the existing `online-demo` unit pins every IRIS fact the script and the stand-in rely on (the probe answers, the broker file, row 6's answers). Task 0 is that section's first run, on the unit's fresh online stack (tag `e29s3i`) rather than a warm one: the warm stack starts without `online_override`, so its `/ocutalon/` and sign-in answers are not the online host's. Expected cost: about 100 to 200 requests, under a minute on CI's `install-upgrade` (inference; recorded after the first push).
8. jq is required, as in the hosted `checks` job.
9. The script ends every IRIS session its own requests open (`?IRISLogout=end`, as the live unit does after each form), so a run holds no licence unit at the 8-unit ceiling (DW-287). It ends only what its own request opened, and counts as part of the read or probe whose session it ends, so the Boundaries' two kinds of request still hold.
10. The `api` probe carries a second name (`text`), so it is no sign-in body under any reading of ruling 1, and the 64 KiB and extra-name probes are refused under every reading too. The script never asserts behaviour that ruling 1 leaves open.
11. Allowed reads carry a unique `t`, as the probe's do; refusal probes are sent exactly as listed, so row 4's bare forms stay bare.
12. The signed-in form of row 4 (the Planner measured it) is the Planner's: the script never signs in. It is recorded in H4.

**Ledger inbox (Rule 17):**
- **DW-214:** addressed by matrix row 4 (every form the Planner measured), the second AC and H4 (measured in part).
- **DW-226:** addressed by matrix row 6, the third AC and H6, under ruling 1 (U-158). Its wording question goes to the decision sheet (the lead's).
- **DW-234:** addressed by H2 (measured) and the check list's proxy-address section, re-checked at the release deploy. There is no repository-side fix:
  - Counting an unset or unmatched proxy address by `REMOTE_ADDR` would put every proxied visitor under one counter.
  - Reporting it on `/status` would amend AD-13's shape.
  - Story 16.3's phase 2 already pins the rule.
- **DW-240:** addressed by matrix row 14 and H7 (measured), re-checked by run 2 during a reset.
- **DW-254:** addressed by H20 (measured in part) and the check list's probe section: the variables `OCUTALON_PROBE_URL`, `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_PROBE_ALERT_COMMAND`, `OCUTALON_PROBE_RESET_COMMAND` and `OCUTALON_PROBE_STATE_DIR`; a run every 15 minutes with bash and curl; a direct connection to IRIS from an address other than `proxyAddress`; and the outcomes and exit codes.
- **DW-287:** addressed by H22 (measured) and Decided in-stage 9.

**Host criteria, criterion by criterion (`epics.md` Story 29.3).** "Measured" means measured on the gated host by the Contest Planner, 2026-10-30 (the Epic 16 deploy); every measured row is re-checked at the release deploy. The Status column holds one of exactly three values, and `release/demo-host-checks.md` copies them:

| H | Criterion | Script / repository | The Planner's check | Status |
|---|---|---|---|---|
| H1 | AC1: the access gate admits only allowed visitors | `gate-closed` | The gate's allow-list; opening it at launch is the author's | pending |
| H2 | AC1: overwrites `X-Forwarded-For`; DW-234 | Story 16.3 pins the rule | Measured: proxied sign-ins write an address-counter row. Re-check: a sign-in with a spoofed `X-Forwarded-For` writes one row for the real client address, and `proxyAddress` is the address IRIS sees for the proxy | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H3 | AC1: passes WebSocket upgrades | none (release 1 polls) | `Upgrade` and `Connection` pass | pending |
| H4 | AC1: allows only `/ocutalon/*` and static `/csp/broker/` files; blocks the webhook path, the password-change pages and `/csp/*`, `/api/*`, `/ui/*`; no MCP endpoint | `allow-*`, `block-*`, `block-pw-*` | Measured: the filter answers 404 to every row 4 form, signed out and signed in, with and without a query string; a trace page and `/ocutalon/public/status` answer 200. Run 1 for the rest | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H5 | AC2: the guard's field rules; all eleven S17 forms blocked | `guard-*`, `guard-F1` to `guard-F11`, F12 | Measured: the guard (S17's check) is installed. Run 1 | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H6 | AC2: sign-in, the page, the JSON API, polling, trace pages and broker files keep working | `allow-*`, `guard-signin-*` | Measured: the filter admits the splash's three-field sign-in (DW-226); the demo path through the proxy passes sign-in, watch, the reminder to the phone, Break the feed and sign-out (steps 4 and 5 wait on Story 11.1), with the exact origin mapped (DW-416). Visual Trace through the proxy | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H7 | AC3: the maintenance page during resets; DW-240 | `maint-*` | Measured: the four logos answer 200 at `/ocutalon/`, `/ocutalon/assets/brand/` and deeper while IRIS is down. Re-check: run 2, during a reset | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H8 | AC3: the busy page in place of a 503 except `/ocutalon/api/` | `busy-*` | Run 3, while full (Story 29.4's author run) | pending |
| H9 | AC3: busy pages and `X-OcuTalon-Busy` logged and counted per day | none | The proxy's daily counts | pending |
| H10 | AC4: IRIS has no general internet | none | A request from IRIS to a public address fails | pending |
| H11 | AC4: the time zone is US Eastern | `zone` | Measured: the container and the agent's input are `America/New_York`; 18:12Z renders "14:12 ET". Re-check: run 1 with `--zone` | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H12 | AC4: only a dummy model key and bot token; the AD-19 endpoint overrides | none | Inspection on the host | pending |
| H13 | AC4: the gateway's routes, the key and token swaps (`/bot<dummy>/`), rate and path limits, the $20 cap refused with 403 "daily cost cap reached"; DW-94's body | Story 29.6 (DW-94) | Measured: Story 16.9's caps (the third message refused with 429 and `retryAt`; the daily-cap notice sent once). The routes, the limits and the 403 body (Story 29.6) | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H14 | AC4: the bot is used by no other instance; the provider-side spend limit | none | The author's | pending |
| H15 | AC4: the Telegram file-download route is not configured (Story 26.2) | none | Confirm it is absent | pending |
| H16 | AC5: resets every 4 h by default; the golden-copy contents; the version refusal; AD-19's variables at start; an unscheduled reset leaves the schedule | `status-*`, `demo-status-*` | The reset procedure | pending |
| H17 | AC5: each start passes that reset's own `OCUTALON_LAST_RESET` (the address key renews per reset, DW-233) | Story 29.5 | Runs before and after a reset show a new `lastReset` | pending |
| H18 | AC5: the `ocutalon-demo status` JSON | `demo-status-*` | Run 1 with the output piped in | pending |
| H19 | AC5: `ocutalon-demo update` before and after launch, its exit lines, the version check, at most 15 min | Story 11.5's stand-in | The update on the host | pending |
| H20 | AC6: the probe every 15 min, alerts reach the author, two counted failures reset; DW-254, and DW-260 via Story 29.6 | `test-probe.sh` | Measured: the probe is healthy and its scheduled run alerted `busy` during the busy test. The 15-minute schedule, the environment, the source address and the reset wiring | measured in part 2026-10-30 (Epic 16 deploy); rest pending |
| H21 | AC6: nothing else holds an IRIS connection; the runbook stops the proxy first at the cap | none | Inspection on the host | pending |
| H22 | AC6: DW-287, the admin and reset path needs no licence unit at 8 units, or one is kept free | none | Measured: one licence unit in use, held by the deploy terminal; no host command opens an IRIS terminal; the health check uses `iris qlist`. Re-check at the cap | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |
| H23 | AC7: the configuration and runbook stay outside the repository; the server and DNS, the bot and token, the real key in the gateway, SSH for the hook, opening the gate | none | The author's preconditions | pending |
| H24 | The Epic 16 deploy fact "EvalIn off" | none | Measured: `EvalIn` `Enabled=0`, and `OCUTALON_EVAL` is unset | measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy |

## Verification

Every call runs in the foreground with `timeout: 600000`, one test call per message, against the explicitly named lane-C targets. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`.

**Commands:**
- (once, first) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh build`: the web bundle matches `web/src` (Rule 21, after the Epic 16 merge).
- (once, Task 0) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh live online-demo` with the new section and `host_probes`' probe list: copy its `MEASURED` lines below. Only on this run may the section's comparisons fail.
- (loop) `bash docker/tests/test-online-host.sh`: every row passes, exit 0; record its time (expected under 2 minutes).
- (loop) `bash docker/tests/test-probe.sh`: every check PASS after the `lib-stub.sh` move.
- (loop, after any change to `lib-online.sh` or `test-online-demo.sh`) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh live online-demo`: PASS, with rows 5 and 6 unchanged and the Story 29.3 section green; record the section's seconds (the unit takes about 310 s locally).
- (once) `bash ci/checks.sh`: every block passes, `online-host`, `probe`, `ci-config` and `boundaries` among them.
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh teardown`: nothing tagged `e29s3i` is left.

**Task 0's MEASURED lines** are recorded here by the implement stage.

**Shared surfaces:** `CHECK_SCRIPTS` (`test-ci-config.sh`'s units rule); the S17 form table (`test-online-demo.sh` rows 5 and 6); `host_probes` (new; read by the script, `test-online-host.sh` and the live section); `test-probe.sh`'s scaffolding; the online stack's sessions and licence units (the new section ends every session it opens). Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to record (Rule 19), one or more per AC:**
- AC1: ignore an extra status key: row 10's fault run passes, so `test-online-host` goes red.
- AC2: remove the `lower` form, or the `double` form, from `host_probes`: row 4's fault for it reports no `FAIL`, so `test-online-host` goes red.
- AC3: make the script expect the three-field POST to be refused: row 1 goes red (`guard-signin-3`).
- AC4: count a 401 as blocked: rows 7 (a) and 8 go red. Drop the ambiguity rule: row 7 (b) gives `PASS`, red. Drop `block-mark`: row 7 (c) goes red.
- AC5: compare the `block-pw-*` family's status against 403 only: row 16 goes red.
- AC6: check only the busy page's title: row 13's altered-byte fault goes red. Drop the `/ocutalon/assets/brand/` location: row 14's fault goes red.
- AC7: make `password_form` F11 use `IRISOldPassword`: `live online-demo` row 5 goes red. Change one `host_probes` `<iris>` field: the live Story 29.3 section goes red.
- AC8: remove `online-host` from `CHECK_SCRIPTS`: `test-ci-config` goes red.
- AC9: set H7's status to `pass` in the check list: `test-online-host` goes red. Add an IPv4 literal to the script: row 15 goes red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan re-dispatch 1 (2026-10-30): re-planned around the lead's rulings 1 to 3; the intent gap is removed, the spec meets the ready-for-development standard, and the stage HALTs after planning as directed.
