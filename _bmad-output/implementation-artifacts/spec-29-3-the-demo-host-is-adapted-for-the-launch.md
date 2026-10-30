---
title: 'Story 29.3: The demo host is adapted for the launch'
type: 'feature'
created: '2026-10-29'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [multiple-goals, oversized]
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
    - `OCUTALON_CHECK_BLOCK_STATUS`: the proxy's block status (default `403`).
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
- A block check passes only when the status is the block status and, if the block mark is set, the mark is present, and the body holds no IRIS form field (`IRISPassword`, `IRISOldPassword`). A 401 or 407 never passes a block check.
- The S17 password-change forms are defined once, in `docker/tests/lib-online.sh`. The live test and the script both use that definition.
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
| 3 | Blocked paths | `/csp/sys/`, `/csp/user/`, `/csp/broker/%25CSP.PasswordChange.cls`, `/api/mgmnt/`, `/api/monitor/metrics`, `/api/atelier/`, `/ui/`, `/mcp/`, `/mcp/ocutalon`, `/ocutalon/hook`, and `/ocutalon/../csp/sys/` sent as is (`--path-as-is`) | `PASS block-*` | Fault: one path passes to the fake IRIS, giving `FAIL block-<id>` with the path, exit 1 |
| 4 | DW-214 | `%25CSP.PasswordChange.cls` at `/ocutalon/trace/ocutalon/`, `/ocutalon/trace/ocuorders/`, `/ocutalon/`, `/ocutalon/api/` and `/ocutalon/public/`, also as `%25csp.passwordchange.cls`, `%25CSP.PASSWORDCHANGE.CLS` and `%25%43SP.PasswordChange.cls` | `PASS block-pw-*` | Fault: one variant is let through (the fake IRIS answers 200 with the change form), giving `FAIL block-pw-<id>` |
| 5 | The guard's refusals | F1 to F11 from `password_form` at `/ocutalon/`; F1 and F3 also at `/ocutalon/api/v1/state` and both trace apps' `EnsPortal.MessageViewer.zen`; F12's post to both trace `%25CSP.PasswordChange.cls`; a sign-in body with an extra name `x=1`; a 64 KiB sign-in body; `IRISPassword` in a GET query string; a urlencoded `IRISPassword` POSTed to `/ocutalon/api/v1/messages` | `PASS guard-*` | Fault, one per rule (multipart, chunked, names not URL-decoded, case-sensitive pattern, legacy names, query string, extra name, size), giving `FAIL guard-<id>` |
| 6 | DW-226 | The splash's three-field POST (`IRISUsername`, `IRISPassword`, `IRISLogin=Sign in and start`) to `/ocutalon/`; the trace sign-in page's four-field POST (with `IRISSessionToken`) to a trace app | Both reach IRIS and come back as its sign-in page with `aria-invalid="true"`, giving `PASS guard-signin-3` and `guard-signin-4` | Fault "exactly four names" (the three-field POST refused), giving `FAIL guard-signin-3` |
| 7 | No false all-clear | Fault: a blocked path is answered by the fake IRIS with 404 or 401 | `FAIL block-<id>` (not the block status) | none |
| 8 | Gate closed, no credentials | Every request answers 401 | `gate refused` on stderr, exit 2, no block or guard line | none |
| 9 | Gate open while access is restricted | Credentials set; a request without them is admitted | `FAIL gate-closed` | No credentials: `SKIP gate-closed`, exit 3 |
| 10 | The status JSON | A key added or missing, a wrong type, no `no-store`, `lastResetKind` outside {scheduled, unscheduled}, `nextReset` in the past | `FAIL status-<id>` | none |
| 11 | `--demo-status` | The AD-25 keys and types; `lastReset`, `lastResetKind` and `nextReset` equal `/status`'s; `runningVersion` equals `goldenVersion`; `access` restricted with credentials set, `public` without | PASS | Not JSON or a mismatch: `FAIL demo-status-<id>`; not given: `SKIP`, exit 3 |
| 12 | `--zone` | `America/New_York`, `US/Eastern` or `EST5EDT` pass | `PASS zone` | Any other value: `FAIL zone`; not given: `SKIP zone`, exit 3 |
| 13 | Busy (`--state busy`) | `/ocutalon/` and `/ocutalon/zz/deep` answer either `docker/busy.html` byte for byte or IRIS's busy splash with `X-OcuTalon-Busy: 1`; `/ocutalon/api/v1/state` never answers the busy page; `/status` has `busy` true | `PASS busy-*` | One altered byte, or the busy page under `/ocutalon/api/`, gives `FAIL busy-<id>` |
| 14 | Maintenance (`--state maintenance`, DW-240) | `/ocutalon/` and a deep path answer `docker/maintenance.html` byte for byte; the four `logo/web/OcuTalon-Logo-*.png` match byte for byte both beside the page (resolved against `/ocutalon/`) and at `/ocutalon/assets/brand/<name>` | `PASS maint-*` | A logo is missing: `FAIL maint-logo-<name>` |
| 15 | The files are safe to publish | A static scan of the script and the check list | No IPv4 address, `localhost`, `host:port` or URL with a literal host; the script runs no `ocutalon-demo` (comment and usage lines excepted) and uses no PUT, DELETE or PATCH | `FAIL self-<id>` |

</intent-contract>

## Code Map

- `docker/tests/test-online-demo.sh:249-344`: `pct` and `form_request` hold the S17 forms F1 to F12 as Story 16.1 rebuilt them (the spike never recorded them). Lines 110 (`CHANGE_FORMS`) and 400-437 (rows 5 and 6) assert on them. The pure field-name and encoding table moves to `lib-online.sh`. F12's two-step flow, the tokens and the jars stay here.
- `docker/tests/lib-online.sh:1-20`: helpers for the online live units. It defines only functions, so the release script can source it by its own path.
- `docker/tests/test-probe.sh`:
  - Lines 13-31, 72-75 and 186-203 hold the scaffolding to extract into a new `lib-stub.sh`: `set -u`, the `mktemp` folder, the cleanup trap, `pass`/`fail`, the tool check, the inline `node -` stub on port 0 on 127.0.0.1, and the port-file wait.
  - Lines 832-834 hold the self-pin pattern (no IP address, `localhost` or `host:port` in the probe) to reuse.
- `docker/probe.sh`:
  - Lines 147-150: busy means a 503 or `X-OcuTalon-Busy: 1`.
  - Line 189: splash markers `<title>Try OcuTalon</title>` and an `IRISPassword` field.
  - Lines 210-218: the form coming back means refused, and `<app-root` means signed in.
  - The script reuses these markers. The probe's live test (`test-online-demo.sh` rows 1-9) pins them against real IRIS.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls:151,178-189` and `Login.cls:27,146-162`: the sign-in form. Its action is `Error:FullURL`, it has no enctype, and its fields are `IRISUsername`, `IRISPassword` and `IRISLogin`. A failed sign-in brings the page back with `aria-invalid="true"` (the 200 status is inference, until Task 0 (c)). A failed sign-in fires no `OnLogin`, so it writes no `AddressCounter` row (`Web/SessionEvents.cls:89`).
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls:46-65`: the response is 200, `application/json`, `Cache-Control: no-store`, and `X-OcuTalon-Busy: 1` only when busy. It always holds `ready` (boolean), `nextReset` (string or null), `busy` (boolean), `lastReset` (string or null) and `lastResetKind` (string or null).
- `docker/busy.html` and `docker/maintenance.html`:
  - Both are compared byte for byte.
  - The maintenance page refreshes to `/ocutalon/` after 10 s and names the logos by bare file name.
  - Story 16.8's view (`web/src/app/live/resetting-view.ts:19-28`) asks for `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png`. The sources are `logo/web/`.
- `ci/units.sh:6` holds `CHECK_SCRIPTS`; append `online-host`.
  - `ci/checks.sh:7-29` runs `docker/tests/test-<name>.sh` in turn.
  - The hosted `checks` job (`.github/workflows/ci.yml:30-43`, read-only) runs on every push and pull request, and `ci/changes.sh` never skips it. So a change under `release/` runs the new test without a classifier change (`test-ci-changes.sh:243` keeps "release runs no group").
  - The job's 15 minutes are shared, and `bash ci/checks.sh` takes about 123 s today.
- `docker/tests/test-ci-config.sh:624-650`: every `docker/tests/test-*.sh` must be in exactly one list.
- `docker/tests/test-boundaries.sh:34-42,94-96`: the local-path and key patterns scan every tracked file, `release/` included. The ASCII rule covers `docker/`. No IP rule applies outside `README.md`.
- `release/standalone-bridge.sh:1-37,209-213` (read-only): the header, `set -u`, the root/cd lines, the summary line and mode 755.
- Spine, `ARCHITECTURE-SPINE.md`:
  - AD-25 at 685-736: the guard at 696-701, the probe at 719-722, capacity at 723-733.
  - AD-13 at 345-395: the `/status` shape at 356 and password changes at 391-394.

## Tasks & Acceptance

**Execution:**

The tasks follow the resolution of the AD-25 intent gap below. The guard expectations (rows 5 and 6) follow the recommended amendment.

- Task 0 is a measurement on a lane-C warm throwaway (`ci/warm.sh up`, tag `e29s3iw`, using the web port `ci/warm.sh status` reports; record `MEASURED` lines under Verification):
  - (a) IRIS's own status and markers, with no proxy in front, for every request of rows 3 to 5. These are the fake IRIS's answers; name any request IRIS itself answers with 403.
  - (b) The static `/csp/broker/` files a trace page loads.
  - (c) IRIS's answer to rows 6's two POSTs.
  - Then `ci/warm.sh down`.
- `docker/tests/lib-online.sh`: add `pct` (moved) and `password_form <F1..F11> <user> <old> <new>`. It sets `form_method`, `form_query` and the array `form_args` (curl arguments) and nothing else, and runs on bash 3.2. This makes one definition of the S17 forms.
- `docker/tests/test-online-demo.sh`: `form_request` builds F1 to F11 from `password_form`, and F12 and the token logic stay. Rows 5 and 6 behave exactly as before.
- `docker/tests/lib-stub.sh` (new): `stub_start` (an inline Node server on stdin and its arguments; sets `stub_pid` and `stub_port`, or fails), `pass`, `fail`, `need_tools` and the cleanup trap. `docker/tests/test-probe.sh` sources it, with no change in behaviour.
- `release/demo-host-check.sh` (new, mode 755): implement the Boundaries interface and matrix rows 2 to 15.
  - Check ids are stable (`allow-*`, `block-*`, `block-pw-*`, `guard-F<n>`, `guard-*`, `gate-closed`, `status-*`, `demo-status-*`, `zone`, `busy-*`, `maint-*`).
  - It sources `docker/tests/lib-online.sh` by its own path for the forms.
  - The busy and maintenance checks run only in their `--state`.
  - The header says what the script checks, its inputs and its exit codes, and that it sends dummy-value requests that leave failed-sign-in entries in the host's audit log.
- `docker/tests/test-online-host.sh` (new, mode 755, ASCII):
  - A Node stand-in that is the proxy and guard of the amended AD-25 in front of a fake IRIS built from Task 0's measurements.
  - Basic-auth gate credentials are random per run and never printed.
  - Fault flags are read per request from a flags file.
  - It serves busy and maintenance from the repository's files.
  - It runs the script for each matrix row and asserts the exit code and the named `PASS`, `FAIL` or `SKIP` line.
  - Row 15's static scan covers the script and the check list.
- `ci/units.sh`: append `online-host` to `CHECK_SCRIPTS` (this story's own entry).
- `release/demo-host-checks.md` (new): how to run the three runs, with `https://demo.example`:
  1. Normal, with `--zone` and `--demo-status`.
  2. During a reset, `--state maintenance`.
  3. While full, `--state busy`.

  Then the H1 to H24 table from Design Notes, each row marked `pending: the Contest Planner, hands-on on the gated host`. It also holds the probe's host interface (DW-254), the licence-unit check (DW-287), the logo placement (DW-240) and the proxy-address check (DW-234).
- Only if the split below is not accepted: Parts B (DW-233) and C (DW-260, DW-94), as planned under "Proposed siblings".

**Acceptance Criteria:**
- Given the stand-in with every amended AD-25 rule, when `test-online-host.sh` runs the script in the normal state with gate credentials, `--demo-status` and `--zone`, then every check passes and the script exits 0. The same run against each fault of rows 2 to 14 exits 1 (2 for row 8, 3 for a skip), with the `FAIL` line of that fault's check id and no other `FAIL`.
- Given a host that lets one DW-214 variant through (any letter case, `%25`-encoded, any OcuTalon application path), when the script runs, then it fails `block-pw-<id>` naming that path.
- Given the guard of the amended AD-25, when the script sends the splash's three-field and the trace page's four-field sign-in POSTs with dummy values, then both reach IRIS (DW-226). A guard that requires all four names fails `guard-signin-3`.
- Given a host answers a blocked path with 401, 404, or a status other than the block status, when the script runs, then that check fails. With a closed gate and no credentials, it exits 2 before any block or guard check, so it never reports an all-clear it did not observe.
- Given the busy or the maintenance state, when the script runs in that state, then the pages and the four logos are checked byte for byte against `docker/` and `logo/web/` (DW-240), at both logo locations.
- Given the live `online-demo` unit, when it runs with `form_request` built on `password_form`, then rows 5 and 6 pass with the same `CHANGE_FORMS` results as before.
- Given a commit that changes only `release/demo-host-check.sh`, when CI runs, then the hosted `checks` job runs `online-host`, and `test-ci-config.sh` passes with it registered.
- Given `release/demo-host-checks.md`, when it is read, then every row H1 to H24 is present with status `pending`, and row 15's scan of the file is clean.

## Spec Change Log

- 2026-10-30, lead, re-dispatch 1 of the plan: the plan HALTed on AD-25's guard wording and proposed a split. The lead ruled (Design Notes, "Lead rulings"): comply with AD-25 by its stated outcome (veto item U-158, AD text unchanged, DW-226 to the decision sheet); the split into Stories 29.5 and 29.6 accepted; the Planner's measured host facts of 2026-10-30 added. Status reset to `draft` for the re-plan.

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
- **AD-25:** the proxy allow-list and blocks, the guard, the pages, the gateway, resets, `ocutalon-demo status`, the probe and capacity. Its guard wording is the intent gap.
- **AD-13:** the `/status` shape, the sign-in form contract, password changes and the client-address rule.
- **AD-24:** the trace application paths.
- **AD-19:** the online-demo variables, including `OCUTALON_LAST_RESET`, and the endpoint overrides.
- **AD-8 and AD-20:** the cap's 403 and its text, recorded as a release check.
- **AD-22:** testing and CI, the hosted `checks` job.
- **AD-29:** the Epic 29 exception, with `release/` for this story's new files.
- **AD-33:** Lane B keeps the classes.

**Integration ACs:** no automated consumer in this story. The first consumer is the Contest Planner's hands-on pass at the deploy, through `release/demo-host-checks.md`. Story 29.4's author load case runs the same list on the adapted host.
- **Consumed-by:**
  - The Planner's release pass.
  - Story 29.4: the adapted host is its real-proxy case's precondition.
  - Story 11.5: its hook relies on `ocutalon-demo status`, and H18 checks that shape.
- **Consumes:**
  - `docker/busy.html`, `docker/maintenance.html` and `logo/web/` (Story 16.5).
  - `/ocutalon/public/status` (Stories 0.5 and 16.1).
  - The splash form (Story 16.2).
  - The probe's markers (Story 16.6).
  - The S17 forms (Story 16.1).

**Extend, don't copy (Rule 2):**
- `password_form` extends `form_request` (`test-online-demo.sh:288-344`) by moving its table to `lib-online.sh`, so the forms have one definition.
- `lib-stub.sh` is `test-probe.sh`'s scaffolding, moved and then sourced by both scripts.
- The script's report lines are its own, a five-line copy of the idea in `lib-live.sh`'s `pass`/`fail`. A copy is the better choice here:
  - They add check ids and `SKIP`.
  - A public tool run against a remote host must not source `lib-live.sh`, which assumes throwaway stacks and locks.
- The stand-in has no sibling.

**footprint_extensions:** `docker/tests/lib-stub.sh` (new; `docker/tests/` is uncontended). The other files are in the footprint: `release/` new files, `docker/tests/test-online-*.sh`, `docker/tests/lib-online.sh` and `docker/tests/test-probe.sh`. `ci/units.sh` gets only this story's own entry.

**Decided in-stage (small, reversible, contradicting no AD):**
1. "Only requests that should be refused" applies to the sign-in and password requests. Public reads (status, splash, a broker file, pages, logos) are needed for the status, page and gate checks and change nothing.
2. A block is the configured block status (default 403) plus an optional mark. Task 0 (a) records which probes IRIS itself would answer with 403, and the check list advises setting a mark.
3. The time zone. No unauthenticated surface reports it: the splash renders times in the browser's zone, and `/status` is UTC. So `--zone` reads the IRIS container's `TZ`, piped in the same way the owner allowed for the status JSON. Adding a zone to `/status` would amend AD-13's fixed shape.
4. Three runs, selected by `--state`. A read-only script cannot make the host busy or reset.
5. The pages are compared byte for byte, so the host must serve the repository's own files unchanged.
6. The oversize probe is 64 KiB, far above any sign-in form.
7. No new live unit. Task 0 makes the fake IRIS faithful, and the probe's live test already pins the shared markers against real IRIS.
8. jq is required, as in the hosted `checks` job.

**Ledger inbox (Rule 17):**
- **DW-214:** addressed by matrix row 4 and the second AC.
- **DW-226:** addressed by matrix row 6 and the third AC, pending the AD-25 ruling.
- **DW-240:** addressed by matrix row 14 and H7, the Planner's run during a reset.
- **DW-254:** addressed by H20 and by the check list's probe section: the variables `OCUTALON_PROBE_URL`, `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_PROBE_ALERT_COMMAND`, `OCUTALON_PROBE_RESET_COMMAND` and `OCUTALON_PROBE_STATE_DIR`; a run every 15 minutes with bash and curl; a direct connection to IRIS from an address other than `proxyAddress`; and the outcomes and exit codes.
- **DW-287:** addressed by H22, pending.
- **DW-234:** addressed by H2, pending. There is no repository-side fix:
  - Counting an unset or unmatched proxy address by `REMOTE_ADDR` would put every proxied visitor under one counter.
  - Reporting it on `/status` would amend AD-13's shape.
  - Story 16.3's phase 2 already pins the rule.
- **DW-233, DW-260, DW-94:** under "Proposed siblings", Stories 29.5 and 29.6. They are planned below and become tasks here if the split is not accepted.

**Host criteria, criterion by criterion (`epics.md` Story 29.3). The Planner's checks are all pending:**

| H | Criterion | Repository / script | Planner's hands-on check (pending) |
|---|---|---|---|
| H1 | AC1: the access gate admits only allowed visitors | `gate-closed` (with credentials, access restricted) | The gate's allow-list; opening the gate at launch is the author's |
| H2 | AC1: overwrites `X-Forwarded-For`; DW-234 | The rule is pinned by Story 16.3 | One sign-in through the proxy with a spoofed `X-Forwarded-For` writes one counter row for the real client address; pin the proxy IP, and `proxyAddress` is the address IRIS sees for the proxy |
| H3 | AC1: passes WebSocket upgrades | None (release 1 polls) | The proxy passes `Upgrade` and `Connection` |
| H4 | AC1: allows only `/ocutalon/*` and static `/csp/broker/` files; blocks the webhook path, the password-change pages and `/csp/*`, `/api/*`, `/ui/*`; no MCP endpoint | `allow-*`, `block-*`, `block-pw-*` | Run 1 |
| H5 | AC2: the guard's field rules; all eleven S17 forms blocked; the U-81/DW-214 table | `guard-*`, `guard-F1` to `guard-F11`, F12 | Run 1; the Epic 16 deploy's measured table, which has not arrived |
| H6 | AC2: sign-in, the page, the JSON API, polling, trace pages and broker files keep working | `allow-*`, `guard-signin-*` | A browser pass through the proxy with the published demo account: the page, polling, Visual Trace |
| H7 | AC3: the maintenance page during resets; DW-240 | `maint-*` | Run 2, during a reset |
| H8 | AC3: the busy page in place of a 503 except `/ocutalon/api/` | `busy-*` | Run 3, while full (Story 29.4's author run) |
| H9 | AC3: busy pages and `X-OcuTalon-Busy` logged and counted per day | none | The proxy's daily counts |
| H10 | AC4: IRIS has no general internet | none | A request from IRIS to a public address fails |
| H11 | AC4: the time zone is US Eastern | `zone` | Run 1 with `--zone`; one message time reads "ET" |
| H12 | AC4: only a dummy model key and bot token; the AD-19 endpoint overrides | none | Inspection on the host |
| H13 | AC4: the gateway's routes, the key and token swaps (`/bot<dummy>/`), rate and path limits, and the $20 cap refused with 403 "daily cost cap reached"; DW-94's body | Story 29.6 (DW-94) | The routes and limits; the 403 body is Anthropic's error JSON unless 29.6 measures plain text as `daily_cap` |
| H14 | AC4: the bot is used by no other instance; the provider-side spend limit | none | The author's |
| H15 | AC4: the Telegram file-download route is not configured (Story 26.2) | none | Confirm it is absent |
| H16 | AC5: resets every 4 h by default; the golden-copy contents; the version refusal; AD-19's variables at start; an unscheduled reset leaves the schedule | `status-*` and `demo-status-*` cross-checks | The reset procedure |
| H17 | AC5: each reset's start passes that reset's own `OCUTALON_LAST_RESET` (the address key renews per reset, DW-233) | Story 29.5 | Runs before and after a reset show a new `lastReset` |
| H18 | AC5: the `ocutalon-demo status` JSON | `demo-status-*` | Run 1 with the output piped in |
| H19 | AC5: `ocutalon-demo update` before and after launch, its exit lines, the version check, at most 15 min | Story 11.5's stand-in | The update on the host |
| H20 | AC6: the probe every 15 min, alerts reach the author, two counted failures reset; DW-254, and DW-260 via 29.6 | `test-probe.sh` | Scheduling, environment, source address, alert and reset wiring |
| H21 | AC6: nothing else holds an IRIS connection; the runbook stops the proxy first at the cap | none | Inspection on the host |
| H22 | AC6: DW-287, the admin and reset path needs no licence unit at 8 units, or one is kept free | none | Measured at the cap |
| H23 | AC7: the configuration and runbook stay outside the repository; the server and DNS, the bot and token, the real key in the gateway, SSH for the hook, opening the gate | none | The author's preconditions |
| H24 | The Epic 16 deploy fact "EvalIn off" | none | `EvalIn` is disabled on the demo instance |

**Proposed siblings (Rule 5 tier 2, part of the intent gap).** Each is a separate reviewable change: a security change to stored data, and a probe and mock change. Each is planned here so that no investigation is lost:
- **29.5, "The address counter's hash is keyed per reset" (DW-233, veto U-156; footprint `Data/AddressCounter.cls`, `Test/Data/**`, `docker/tests/test-online-demo.sh`, `web/e2e-online/**`):**
  - **The hash.** `AddressCounter.AddressHash(address)` is the base64url (no padding) of `$SYSTEM.Encryption.HMACSHA(256, $ZConvert(address,"O","UTF8"), ..Key())`. `Recent`, `Add` and `Lock` use it. Its sibling is `Session.Hash`; this differs in its primitive, and the one-line encoding is repeated.
  - **The key.** `Key()` reads `^OcuTalonP.AddrCountK = $ListBuild(marker, key)`, where the marker is the public `lastReset` that the `Public` step writes from `OCUTALON_LAST_RESET` at every start.
    - When the node is missing or its marker differs, it makes `GenCryptRand(32)` under `Lock +^OcuTalonP.AddrCountK:5`, re-reading the node after taking the lock.
    - A lock timeout makes `Lock()` return 0, which gives `SessionEvents`' existing "address counter is busy".
  - **Which option.** This is the owner's first option: the key is made at the first counted sign-in after a start whose marker changed. The `Public` step is in `Install/**`, Epic 15's contended path, so this story has no start hook. A key that came back in a golden copy is inert, and H17 guards the marker.
  - **Storage.** The prefix is mapped to the private database (AD-3); `test-storage.sh` needs no row. Old SHA-256 rows stop matching and are purged within the hour.
  - **Tests.**
    - `Test.Data.AddressCounter`: the SHA-256 assertions move to `AddressHash`. A new `TestKeyPerReset` works through three markers:
      1. `lastReset` T1 gives h1; capture the node, as the golden copy would.
      2. Set T2 and restore the node, which gives h2.
      3. Set T3 and restore the node again, which gives h3.

      The keys and the hashes must be pairwise different, compared as values and never printed. The same marker must leave both unchanged. `AddressHash` must differ from `Session.Hash`, and a row added before a reset must not count after it. The test restores `lastReset` and the node.
    - `test-online-demo.sh` lines 606, 866, 871 and 981 switch to `AddressHash`. Phase 2 adds: the forwarded address's row is under `AddressHash`, and none is under `Session.Hash`. Row 13 adds: the earlier rows still count after a restart with the same `lastReset`.
    - `web/e2e-online/address-limit.spec.ts:23` reads `AddressHash` through `irisScript`.
  - **Mutations.**
    - Make `AddressHash` return `Session.Hash`: `TestKeyPerReset` and phase 2 go red.
    - Make `Key()` ignore the marker: `TestKeyPerReset` goes red.
  - **Verification.** Warm `class OcuTalon.Test.Data.AddressCounter` and `live online-demo` on every pass; `shard lane-b` once.
  - **ADs:** AD-13, AD-3, AD-19, AD-27, AD-33.
- **29.6, "The probe alerts when every turn falls back" (DW-260, veto U-157, and DW-94):**
  - **The probe.** In `docker/probe.sh:243-246`, `no_key`, `timeout` and `rate_limited` (the enum's spelling of the owner's `rate_limit`) give `degraded`.
    - It alerts, exits 1 and leaves the count unchanged, like busy, in the state `case` at 297-313; the header at 16-18 and 37-41 changes to match.
    - Every other reason stays `healthy`, because the owner named three. The probe's own wait timeout stays `no_decision`, which is counted.
  - **The probe's tests.** `test-probe.sh` gets the flags `decision_no_key`, `decision_timeout` and `decision_rate_limited` (line 174). Each gives `degraded count=<n> fallback=<reason>`, an alert, no reset and an unchanged count. The `error` cases at 454-456 and 668 stay healthy.
  - **DW-94, Task 0 on a fresh throwaway.**
    - `ci/mock/scenarios.mjs:129-131` accepts a string `body`, served as is with the reply's headers, and gets a case in `ci/mock/test/scenarios.test.mjs`.
    - A new `ci/mock/scenarios/B/daily-cap-text.json` replies 403, `text/plain`, "daily cost cap reached".
    - `Test.Agent.Decide`'s `TestDailyCapBothPaths` is extended to that scenario, and the result is recorded as `MEASURED fallbackReason`.
    - If the result is `daily_cap`, keep the pin and resolve DW-94.
    - Otherwise make no bridge change (`src/bridge/**` is Epic 7's), drop the plain-text pin, and H13 requires the JSON body.
  - **Mutations.**
    - Drop `no_key` from the `degraded` case: its row goes red.
    - Change the scenario's text: the `Decide` pin goes red.
  - **Verification.** `test-probe.sh`, `test-mock.sh` and fresh `class OcuTalon.Test.Agent.Decide` on every pass; `shard lane-a` and `ci/checks.sh` once.
  - **footprint_extensions:** `ci/mock/scenarios.mjs`, `ci/mock/test/scenarios.test.mjs`, `ci/mock/scenarios/B/daily-cap-text.json` (new) and `Test/Agent/Decide.cls` (one method).
  - **ADs:** AD-25, AD-8, AD-20, AD-22.

## Verification

Every call runs in the foreground with `timeout: 600000`, one test call per message, against the explicitly named lane-C targets. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`.

**Commands:**
- (loop) `bash docker/tests/test-online-host.sh`: every check PASS (matrix rows 1 to 15), exit 0; record its time (expected well under 2 minutes).
- (loop) `bash docker/tests/test-probe.sh`: every check PASS after the `lib-stub.sh` extraction.
- (loop, after any change to `lib-online.sh` or `test-online-demo.sh`) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh build` once, then `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh live online-demo`: PASS, with rows 5 and 6 unchanged (about 310 s locally).
- Task 0: `LANE OCUTALON_RUN_TAG=e29s3iw bash ci/warm.sh up`, then the measurement curls (one per call batch), then `LANE OCUTALON_RUN_TAG=e29s3iw bash ci/warm.sh down`.
- (once) `bash ci/checks.sh`: every block passes, `online-host`, `probe`, `ci-config` and `boundaries` among them.
- (once) `LANE OCUTALON_RUN_TAG=e29s3i bash ci/iris.sh teardown` and `LANE OCUTALON_RUN_TAG=e29s3iw bash ci/warm.sh down`: nothing tagged is left, even after a failure.

**Shared surfaces:** `CHECK_SCRIPTS` (`test-ci-config.sh`'s units rule); the S17 form table (`test-online-demo.sh` rows 5 and 6); `test-probe.sh`'s scaffolding. Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to record (Rule 19):**
- Remove the `%25csp.passwordchange.cls` variant from the script: the row 4 fault run turns green, so `test-online-host` goes red.
- Make the script expect the three-field POST to be refused: row 1 goes red (`guard-signin-3`).
- Count a 401 as blocked: rows 7 and 8 go red.
- Check only the busy page's title: row 13's altered-byte fault goes red.
- Ignore an extra status key: row 10 goes red.
- Add an IPv4 literal to the script: row 15 goes red.
- Make `password_form` F11 use `IRISOldPassword`: `live online-demo` row 5 goes red.
- Remove `online-host` from `CHECK_SCRIPTS`: `test-ci-config` goes red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: AD-25's password-guard Rule is internally contradictory as worded, so the host check script cannot encode it without contradicting the AD (Rules 5 and 6). (1) "on a sign-in POST, accepts only ... bodies of bounded size whose decoded field names are exactly IRISSessionToken, IRISUsername, IRISPassword and IRISLogin": the splash and the local sign-in page post three names with no IRISSessionToken (measured, Story 16.2 Task 0 (b); DW-226), while IRIS's own sign-in page of the trace applications posts all four (Story 16.1, test-online-demo.sh:321-327). Read literally, the guard refuses every online-demo sign-in, against the same criterion's "sign-in ... keep working". (2) "refuses any field anywhere whose decoded name matches (IRIS|Cache)(Old|Repeat)?Password" also matches IRISPassword, the field every sign-in POST carries. Recommended amendment of AD-25's guard bullets, with the same words in epics.md Story 29.3's second criterion (a Rule 5 restatement): "on a sign-in POST, accepts only application/x-www-form-urlencoded bodies of bounded size whose decoded field names all come from IRISSessionToken, IRISUsername, IRISPassword and IRISLogin (any of them may be absent: the splash posts the last three, IRIS's trace sign-in page all four); refuses any other field anywhere, in the query string or the body of any request, whose decoded name matches (IRIS|Cache)(Old|Repeat)?Password case-insensitively; the one IRISPassword of such a sign-in body is the only exception." (3) In the same AD's probe bullet, record the owner's U-157 ruling as an outcome, "degraded (a no_key, timeout or rate_limited fallback: alert only)", beside no_splash (built by Story 16.6: alert only), keeping "Only auth_failed and no_decision count". Also proposed (Rule 5 tier 2, ask first): split the story. 29.3 keeps the host check script, its stand-in test and the release check list (DW-214, DW-226, DW-234, DW-240, DW-254, DW-287). A new 29.5, "The address counter's hash is keyed per reset", takes DW-233. A new 29.6, "The probe alerts when every turn falls back", takes DW-260 and DW-94. Design Notes hold both plans. If the split is declined, re-plan 29.3 with all three parts.
