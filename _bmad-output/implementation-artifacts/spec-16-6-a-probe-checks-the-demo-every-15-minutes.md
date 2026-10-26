---
title: 'Story 16.6: A probe checks the demo every 15 minutes'
type: 'feature'
created: '2026-10-26'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-25, lines 676-721, above all "The probe" at 710-713 and capacity at 714-719; AD-13, lines 342-386, the probe exemption at 365, the session-lifetime bullets at 369-375 and "Demo busy" at 376-381; AD-19, lines 478-519, the online-demo start values table at 499-511; AD-22, lines 576-601, how a request picks its mock scenario)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (Story 16.6, lines 4314-4341; Story 29.3, lines 6208-6250, the probe on the host at 6247)'
  - '{project-root}/_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md (FR-59 Monitoring, line 1077)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing watches the online demo. A changed demo password, a stuck production or a broken model path stays broken until a judge finds it. Story 29.3 must install and schedule a probe on the demo host, and this repository has none to give it (FR-59, AD-25).

**Approach:**
- **The probe.** One new bash script, `docker/probe.sh`. Each invocation is one run. The demo host's scheduler runs it every 15 minutes (Story 29.3).
  - It reads the busy status, checks that IRIS serves the splash, and signs in through the form with the published demo account.
  - It sends one fixed chat message, waits up to 120 s on `GET /api/v1/events` for that turn's decision, and signs out with `POST /api/v1/session/end`.
  - It classifies the run, keeps a small state folder (the log, the count of counted failures, busy runs per day), and runs the host's alert and reset commands.
  - Every host detail comes from the environment the host provides.
- **Its tests.**
  - A probe phase in the existing `online-demo` live unit produces every outcome on a fresh flag-on throwaway, with stub alert and reset commands.
  - A new hermetic check script runs the probe against a small stub server. It covers what the throwaway cannot give: an HTTP 503, the request discipline and configuration errors.

## Boundaries & Constraints

**Always:**
- **Where it runs.** The probe calls IRIS directly at `OCUTALON_PROBE_URL`, never through the proxy, so the sign-in is exempt from the busy refusal and the per-address limit (AD-13).
  - `OCUTALON_PROBE_URL` is an origin only: `http://` or `https://`, then host and optional port, with no path. A trailing `/` is dropped.
  - Every path is fixed in the probe under `/ocutalon/`.
  - The same origin is the `Origin` header of every POST.
- **Configuration: environment variables only. The file names none of their values.**
  - **Required.**
    - `OCUTALON_PROBE_URL`.
    - `OCUTALON_DEMO_USER` and `OCUTALON_DEMO_PASSWORD`: AD-19's names for the published account, so that the host keeps those values in one place, the file it already passes to IRIS.
    - `OCUTALON_PROBE_ALERT_COMMAND`.
    - `OCUTALON_PROBE_RESET_COMMAND`.
    - `OCUTALON_PROBE_STATE_DIR`: created when it is missing.
  - **Test-only overrides**, which Story 29.3 never sets (the precedent is `docker/healthcheck.sh`'s overridable paths):
    - `OCUTALON_PROBE_MESSAGE` replaces the fixed message;
    - `OCUTALON_PROBE_DECISION_WAIT` is a whole number of seconds from 1 to 120, 120 by default. It can shorten the wait, never lengthen it.
  - **A configuration error** is a missing required variable, a URL that is not an origin, or a wait outside 1-120. The probe then makes no request, writes nothing, prints one line on stderr naming the variable (never a value) and exits 2.
- **One run, in this order.** The first step that ends the run decides the outcome. Every answer passes the busy rule first: HTTP 503, or a header `X-OcuTalon-Busy: 1` (name in any case), ends the run as `busy`.
  1. **The status.** `GET /ocutalon/public/status`.
     - A body with `"busy":true` is `busy`.
     - Any other answer, no answer included, goes on to the splash check.
  2. **The splash.** `GET /ocutalon/` on a fresh cookie jar.
     - The splash is served when the answer is 200 and the body holds both `<title>Try OcuTalon</title>` (Splash's `TITLE`) and an `IRISPassword` field.
     - Anything else is `no_splash`: the local sign-in page, a 404, a connection refused or a timeout.
  3. **The sign-in.** One form POST to `/ocutalon/` on the splash's jar, URL-encoded.
     - It posts `IRISUsername`, `IRISPassword` and `IRISLogin` (`Sign in`). It also posts `IRISSessionToken` when the splash form carries one (build 154 carries none, DW-226).
     - After a 3xx answer, one GET of `/ocutalon/` on the same jar follows.
     - A page holding `<app-root` means signed in.
     - A page holding an `IRISPassword` field means the form came back: `auth_failed`.
     - Anything else is `no_decision`.
  4. **The message.** `POST /ocutalon/api/v1/messages` with `{"clientId":"probe-<UTC yyyymmddThhmmssZ>-<pid>","text":"<message>","fromGuide":false}` and the browser envelope: `Content-Type: application/json`, `X-OcuTalon-Request: 1` and the matching `Origin`.
     - Any answer but 202 is `no_decision`.
     - Text is JSON-escaped (`\` and `"`).
  5. **The decision.** `GET /ocutalon/api/v1/events` every 2 s, until 120 s after the 202 (or the test-only wait).
     - **The turn's decision** is an event with `"type":"chat.message"`, the run's `clientId`, `"state":"done"` and a `"decision":{` object. It is the shown decision of the ended turn (AD-20).
     - Its `"fallbackReason":"daily_cap"` is `capped`. Any other decision is `healthy`, including a fallback with another reason.
     - No decision by then is `no_decision`.
     - The first poll is `after=0&afterInstance=0`. Later polls keep `after=0`, because the fresh session holds only this turn, and take `afterInstance` from the highest instance `seq` seen.
  6. **The sign-out.** Every run that signed in posts `POST /ocutalon/api/v1/session/end` with the envelope and the body `{}` before it exits, on every path, through an EXIT trap.
- **Requests.**
  - Each request has a connect and a total time limit, so that a run ends within about 5 minutes.
  - Every GET carries a unique `t=<n>` query parameter.
  - **Credentials.**
    - They travel only in the one sign-in POST, on the jar of the splash GET.
    - The password reaches curl on stdin (`--data-urlencode IRISPassword@-`), never on a command line.
    - No request carries an `Authorization` header or a credential in a query string.
    - No API call is made before the sign-in succeeded or after the sign-out (AD-13: nothing calls IRIS under a public account without a session).
  - **The cookie jar** lives in a temporary folder, mode 700, removed at exit. No resume cookie is kept between runs.
- **Outcomes and their effects.** Exactly one label per run. `no_splash` is the label of a run that ended at the splash check (Design Notes).

  | Outcome | Alert | Count of counted failures | Exit |
  | --- | --- | --- | --- |
  | `healthy`, `capped` | no | cleared to 0 | 0 |
  | `busy` | yes | unchanged; adds 1 to today's busy count | 1 |
  | `no_splash` | yes | unchanged | 1 |
  | `auth_failed`, `no_decision` | yes | plus 1; at 2, the reset command runs once and the count is cleared to 0 | 1 |

- **Commands.** Each command variable is split on white space into words, with no shell evaluation.
  - The alert command runs with two more arguments: the outcome and the run's log line.
  - The reset command runs with none, in the foreground, and its exit status goes into the log line.
  - An alert command that fails or cannot run prints one line on stderr. The outcome does not change.
- **The state folder.**
  - `probe.log`: one appended line per run, which the probe also prints on stdout: `<UTC time, YYYY-MM-DDThh:mm:ssZ> <outcome> count=<n>[ fallback=<reason>][ reset=<exit status>]`.
    - `count` is the number of counted failures in a row, this run included.
    - `fallback` is the decision's fallback reason, when it has one.
  - `counted-failures`: that number, written whole, through a temporary file and a rename. An unreadable value counts as 0.
  - `busy-per-day`: one line per UTC day, `YYYY-MM-DD <n>`. Older days are kept.
  - Order inside a run: classify, then update the count and the busy count, run the reset when it is due, append the log line, then alert.
- **No secret leaks.** The password never appears on stdout or stderr, in the log, in a state file or in an alert argument.
- **The message** is the probe's constant: `Health check from the online demo's probe. Reply with one short sentence.` (For the lead.)
- **Tooling.**
  - bash 3.2 or later (no associative arrays), curl and POSIX utilities (`date`, `sed`, `grep`, `tr`, `mkdir`, `mv`). No jq, Python or Node.
  - JSON is read by key tokens on IRIS's compact output (Design Notes).
  - The file is ASCII and is tracked with mode 100755.
- **The live tests, in `docker/tests/test-online-demo.sh`.**
  - **Where.** One phase, right after the proxy address is put back (`:1247-1252`) and before the password-log checks (`:1254`), so that no request is proxied.
  - **How the probe runs.** Through `bash "$root/docker/probe.sh"` with:
    - the unit's `$base`, demo account and published password;
    - a fresh state folder under `$tmp`;
    - two stub commands written to `$tmp`, which append one line per call to one shared record file: `alert <outcome> <line>` or `reset`. So the record shows the order of the calls.
  - **Settings the phase changes** are put back on every path and read back: `connectionCap` 8, the public `onlineDemo` "1", the `Conversation` item enabled, and no `^OcuTalonBP.UsageCapped` node of today unless one was there before the phase.
  - **The deadline.** The phase starts only with at least 150 s of the deadline left, and otherwise fails, as the busy rows do (`:1046-1048`).
- **Runtime targets (Rule 21).**
  - Stacks go only through `ci/iris.sh` with lane C's variables.
  - The story changes no ObjectScript, so `ocutalon-slot-c` is not used. A stage that does need it first checks it with `iris_server_info` (build 154, port 52792, namespace `OCUTALON`).

**Never:**
- **Files.**
  - No change to any IRIS class, `web/`, `ci/mock/` (no new scenario: Design Notes), `docker/tests/lib-live.sh`, any other existing `docker/**` file but `docker/tests/test-online-demo.sh`, `.github/workflows/**`, `README.md`, `docs/**`, or any contended path of the lead's lists.
  - `ci/units.sh` takes only the one `probe` token.
  - `docker/probe.sh` holds no host name, address, port, key, credential or local path, and no default for any of them.
- **Behaviour.**
  - No second sign-in in a run, no loop or sleep between runs, no lock: the schedule is the host's.
  - The published values are never read from the splash's prefilled fields.
  - No resume reference is stored.
- **Nothing outward.** Nothing touches the demo host, DNS, a real alert channel, a real reset or any external service. The tests use stubs only.
- **Out of scope:**
  - installing and scheduling the probe on the host, the host's alert and reset commands, and the proxy's busy count (Story 29.3);
  - `SessionOps.End` (Story 16.4);
  - a real-host measurement of licence connections (DW-251, Story 29.4);
  - rebalancing the CI groups.

## I/O & Edge-Case Matrix

Where each row runs:
- **Live, the `online-demo` unit's probe phase on a fresh flag-on throwaway:** rows 1 to 9, in this order, on one state folder.
- **Hermetic, `docker/tests/test-probe.sh` against a stub server:** rows 10 to 15.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Healthy (AC 1, 2, 5) | P1: the unit's configuration, cap 8, flag on | Exit 0. The log's last line is `<time> healthy count=0` with no `fallback`. No alert and no reset. Exactly one new `Session` row, and its `CspSessionId` names no live `%CSP.Session` (read in %SYS right after the run) | -- |
| 2 | Wrong password (AC 2, 3) | P2: `OCUTALON_DEMO_PASSWORD` set to a random wrong value | Exit 1, `auth_failed count=1`, one alert (`auth_failed` and the line), no reset, no new `Session` row | -- |
| 3 | No splash (AC 2, 3) | P3: public `onlineDemo` set to "0", put back to "1" after the run | Exit 1, `no_splash count=1` (unchanged), one alert, no reset | The flag is put back and read back on every path |
| 4 | Busy (AC 2, 3, 4, 5) | P4: `connectionCap` set to the `http_view` reading plus the reserve, so the status is busy (Story 16.5's row 1 boundary); put back to 8 after | Exit 1, `busy count=1` (unchanged), one alert, no reset, `busy-per-day` holds `<today UTC> 1`, no new `Session` row | The cap is put back and read back on every path |
| 5 | No decision, then the reset (AC 2, 3, 5) | P5: the `Conversation` item disabled (`Ens.Director.EnableConfigItem`), `OCUTALON_PROBE_DECISION_WAIT=10`; enabled again after | Exit 1, `no_decision count=2 reset=0`, one alert. The record's first `reset` line comes right before this run's `alert` line (the reset runs before the alert). The stored count is 0 | The item is enabled again and read back on every path |
| 6 | The count starts again (AC 3) | P6: wrong password | `auth_failed count=1`, one alert, the reset stub still called once in total | -- |
| 7 | Capped (AC 2, 3, 5) | P7: `OCUTALON_PROBE_MESSAGE="[[mock:daily-cap]] probe capped check"`. Lane A's `daily-cap` scenario answers the gateway's HTTP 403 "daily cost cap reached" | Exit 0, `capped count=0 fallback=daily_cap`, no alert. The day's capped mark is removed after (when it was absent before) and reads absent | Removed on every path |
| 8 | Capped cleared the count (AC 3) | P8: wrong password | `auth_failed count=1`. Still one reset in total, so a capped run cleared the count | -- |
| 9 | The phase as a whole (AC 3, 4, 6) | After P1 to P8 | `probe.log` holds exactly 8 lines, in order: healthy, auth_failed, no_splash, busy, no_decision, auth_failed, capped, auth_failed. The record holds 6 `alert` lines (P2, P3, P4, P5, P6, P8), each with its outcome and its run's line, and exactly 1 `reset` line. The `AddressCounter` row count is unchanged (the probe is exempt). Neither the published nor the wrong password is in the probe's stdout, stderr, state files or records. Cap 8, flag "1", `Conversation` enabled and no new capped mark read back | -- |
| 10 | Request discipline (AC 1) | A healthy stub run that records every request; a variant whose splash form carries `IRISSessionToken` | The order: status, splash, sign-in POST (with the cookie the splash set), the redirect GET, message POST, events polls, session/end. The credential fields are only in the sign-in POST body, and its field names are exactly the three, plus the token in the variant. No request has `Authorization`, and no query string has an `IRIS` field. Every API call carries the session cookie. Both POSTs carry the envelope with `Origin` equal to the URL. Every GET has a distinct `t` | -- |
| 11 | Busy from a 503 or the marker (AC 2) | The stub answers 503 at the status, at the splash, at the sign-in POST, at the message POST, or at the second events poll; or the splash carries `X-OcuTalon-Busy: 1` | Each run is `busy`. Every run that signed in still posted session/end | -- |
| 12 | No splash (AC 2, 3) | The stub serves the local sign-in page (title `Sign in &middot; OcuTalon`) or a 404; or nothing listens on the URL's port | Each run is `no_splash`, and the count is unchanged | -- |
| 13 | Other endings (AC 2, 3) | A 500 on the message POST; no decision within a 2 s wait; a decision with `fallbackReason` `error`; the form back after the POST; a reset command that exits 3 at the second counted failure; an alert command that exits 1 | `no_decision`; `no_decision`; `healthy count=0 fallback=error`; `auth_failed`; `reset=3` and the count cleared to 0; one stderr line and the same outcome | -- |
| 14 | Configuration (AC 6) | Each required variable unset in turn; a URL with a path; a wait of 0 and of 121; a missing state folder | Exit 2 with one stderr line naming the variable and no value, no request made (the stub's record is empty) and nothing written. The missing state folder is created, and the run goes on | -- |
| 15 | The file itself (AC 6) | `docker/probe.sh` | ASCII. No IPv4 or IPv6 literal, `localhost`, `host:port`, or URL with a literal host (`https?://[A-Za-z0-9]`). No `-u `, `--user`, `Authorization`, `--basic`, `--digest` or `--netrc`. `IRISPassword` appears in one request only. The wait's default, read from its assignment, is 120. `test-boundaries.sh` passes over it | -- |

</intent-contract>

## Code Map

- **`docker/probe.sh`** (new): the probe. Its header comment states:
  - what runs it (the demo host's scheduler, every 15 minutes, directly against IRIS and from an address other than `proxyAddress`);
  - the variables, the two commands' calling convention, the state files, the outcomes and exit codes, and the tools it needs;
  - that the two test-only overrides are for tests.
- **Read only, the product surfaces the probe calls:**
  - `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
    - the class comment :1-21 (the routes, the envelope, 401 `signed_out`);
    - `UrlMap` :52-67;
    - `Events` :118-130 (`after`, `afterInstance`; 400 `bad_cursor`);
    - `EndSession` :132-140 (`Logout(1)`, `EndSession`, 204);
    - `Messages` :142-160 (`{clientId, text, fromGuide}`, 202 `{clientId}`, 500 when the production cannot take it);
    - `EventsBody` :448-462 (`{"epoch", "events"}`, session stream then instance stream);
    - `EnvelopeError` from :464.
  - `src/ocutalon/cls/OcuTalon/Live/Event.cls:31-43`: the envelope `{"seq","stream":"session"|"instance","ts","type","payload"}`. `MAXEVENTS` is 200 (:11).
  - `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls`: `clientId`, `state` (queued, running, done), `fallbackReason`, and `decision` (:49), which is the shown decision.
  - `src/ocutalon/cls/OcuTalon/Data/Turn.cls:73-79` `ShownDecisionRef`: the reply decision of a fallback reply, else the triage decision.
  - `src/ocutalon/cls/OcuTalon/Core/Conversation.cls:5-32`: the decision landing publishes a `running` chat.message, which carries the triage decision. Finishing publishes `done` with the shown decision.
  - `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`: `TITLE` "Try OcuTalon" :22, written at :144; the form :155-169 (`IRISUsername` :159, `IRISPassword` :162).
  - `Login.cls`: the local page's title "Sign in &middot; OcuTalon" :13; `UseSplash` :89-92 reads the public key `onlineDemo`.
  - `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls`: `Busy()` and `BUSYHEADER` (Story 16.5).
  - `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`: `ClientAddress`. A request that does not come from `proxyAddress` is exempt.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `DAILYCAPTEXT` :122-124; the classification :654-674 (the text of a failure gives `daily_cap`); `MarkCapped` :855.
  - `src/bridge/cls/OcuTalon/Bridge/Budget.cls:9-11, 85, 94-125`: the day's mark `^OcuTalonBP.UsageCapped(<instance-zone date>)`. Once it is set, every later Decide of the day prechecks `daily_cap`.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls:196, 1404` show the removal: `Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))`.
  - `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls:9`: `KEYS` (`onlineDemo`, `connectionCap`, `connectionReserve`).
  - `src/ocutalon/cls/OcuTalon/Production.cls:57`: the item `Conversation`. `Test/Bridge/Approval.cls:560, 572` is the `Ens.Director.EnableConfigItem(name, 0|1)` pattern.
- **Read only, the CI mock:**
  - `ci/mock/mock.mjs:10-20`: selection is a marker, then a guide prompt, then `x-ocutalon-mockkey`. There is no default reply.
  - `ci/compose.ci.yml:8-17`: `OCUTALON_MOCK_KEY_HEADER=1`. So the probe's fixed message gets `A/triage.json` and `A/chat.json` (the agents' `MOCKKEY`): the healthy reply.
  - `ci/mock/scenarios/A/daily-cap.json`: marker `daily-cap`, 403 `permission_error` "daily cost cap reached". It is Lane A's and is used here read only, as `Test.Agent.Decide` uses it.
- **`docker/tests/test-online-demo.sh`** (this epic's):
  - the header :2-71, which names the new phase;
  - `redact` :103;
  - `logout_all` :276;
  - `online_signin` :287-310 and `signin_outcome` :312-328 (the `<app-root` and `aria-invalid` markers);
  - `page_token` :330;
  - row 6's real message :725-767, a turn that ends on the mock;
  - Story 16.5's helpers :977-1031: `public_value`, `set_cap`, `status_read`, `http_view`, `marker_in`, and the `session_value OCUTALON <tag>` idiom;
  - the deadline gate :1046-1048;
  - the cap's restore :1239-1245, the proxy's restore :1247-1252, then the new phase, then the password-log checks :1254.
- **`docker/tests/lib-live.sh`** (read only):
  - `root` and `tmp` :9, :58; `deadline` :13, :78;
  - `pass`/`fail` :273-277;
  - `iris_script` :307; `session_value` :487.
- **`ci/units.sh`:**
  - `CHECK_SCRIPTS` :6 gains `probe` (`docker/tests/test-probe.sh`; the hosted `checks` job runs it through `ci/checks.sh`, with no `ci.yml` change);
  - `IRIS_INPUT` :65 already claims `docker/probe.sh` (`docker/[^/]+$`), so a probe change runs every IRIS group, the `image` group's `online-demo` among them;
  - `NOT_IRIS_INPUT_PATTERN` :79 already covers `docker/tests/test-probe.sh`.
- **Read only, the rules the new files must keep:**
  - `docker/tests/test-ci-config.sh:24` (units: every `docker/tests/test-*.sh` in exactly one list; inputs: a live script's `$root/<file>` must be claimed by its group);
  - `docker/tests/test-boundaries.sh:96` (scans `docker/`: ASCII, local paths, key-like strings);
  - `.dockerignore` is an allow-list, so `docker/probe.sh` never enters the image;
  - `docker/healthcheck.sh:5` is the precedent for test-only overrides.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, in the `online-demo` unit on lane C's fresh throwaway; printed as `MEASURED` lines, any temporary diagnostic reverted byte-identical):
  - (a) **A healthy turn's events.** Find which chat.message events of the probe's `clientId` carry `"decision":{` (running, done or both), and whether a model decision's `fallbackReason` is absent or empty. The probe reads only `done`.
  - (b) **Capped.** With the `daily-cap` marker, the `done` event's decision has `"fallbackReason":"daily_cap"`, the day's mark appears, and the removal clears it.
  - (c) **Conversation disabled.** Record what `POST /messages` answers (202, or 500 from `WebChatIn`); either is `no_decision`. Record how the item's enabled state is read back, and confirm that the restart row (row 13) stays green after the item is enabled again.
  - (d) **The sign-out.** Control: a test session signed in with `online_signin` has a live `%CSP.Session` for its row's `CspSessionId`, and after `logout_all` it has none. Then confirm that P1's CSP session is gone right after the probe's session/end.
  - (e) **The splash's cookie.** Whether the splash GET sets a CSP session cookie that the sign-in POST then carries.
  - (f) **DW-220.** The unit's time with the phase.
- [ ] `docker/probe.sh` (new, mode 100755) -- the probe of Boundaries, with its header comment (Code Map) -- rows 1 to 15.
- [ ] `docker/tests/test-probe.sh` (new; footprint extension) -- rows 10 to 15.
  - **The stub.** One inline Node HTTP server (`node - <<'EOF'`, as the live unit runs Node).
    - It listens on 127.0.0.1 port 0 and prints its port.
    - It serves the status, the splash, the sign-in POST (303 and a `CSPSESSIONID`-style cookie), the shell (`<app-root>`), messages (202), events and session/end (204).
    - A scenario variable picks the variant of each row.
    - It records every request (method, path, query, the headers named in row 10, the body) as one JSON line.
  - **Each row** runs the real `docker/probe.sh` with stub commands (one shared record file, as in the live phase) and its own state folder. It asserts on the exit code, the log line, the stub server's request record and the command record.
  - **Row 15** greps the file.
  - It prints one PASS or FAIL line per check and exits 0 only when all pass.
- [ ] `ci/units.sh` -- `CHECK_SCRIPTS` gains the token `probe`. No other line changes -- the script of rows 10 to 15 joins the hosted checks.
- [ ] `docker/tests/test-online-demo.sh` -- the probe phase, rows 1 to 9:
  - **The header** names the phase and its runs.
  - **Helpers.**
    - `probe_run <label> [VAR=value ...]` runs the probe with the unit's configuration plus the overrides, and leaves its exit code, stdout and stderr in `$tmp`.
    - A reader of the newest `Session` row id, and of a row's `CspSessionId`.
    - `csp_alive <id>`: `%CSP.Session` `%ExistsId` in %SYS, through `iris_script`.
    - `set_flag`.
    - `conversation_enabled <0|1>` through `Ens.Director.EnableConfigItem`, with its read-back.
    - The capped mark's `$Data` and its removal.
  - **The sequence** is P1 to P8 as in the matrix, then row 9's checks.
  - **Restores** are as in Boundaries, each with a PASS or FAIL line.
  - **Output.** Task 0's `MEASURED` lines. The wrong password comes from `hexpw` and is never printed.

**Acceptance Criteria:**
- Given `docker/probe.sh` run with the host's environment against IRIS directly, when it runs, then:
  - it reads the busy status and checks that IRIS serves the splash (the online-demo flag);
  - it signs in through the form with `OCUTALON_DEMO_USER` and `OCUTALON_DEMO_PASSWORD`;
  - it posts the one fixed message with JSON, `X-OcuTalon-Request: 1` and the matching `Origin`;
  - it waits up to 120 s on `GET /api/v1/events` for that turn's decision, and signs out with `POST /api/v1/session/end`, after which its CSP session no longer exists;
  - credentials travel only in the sign-in form, and no call carries them without a session.

  Rows 1, 9 and 10 hold.
- Given a finished run, when the probe classifies it, then the outcome is exactly one of healthy, `busy` (HTTP 503 or a busy status), `capped` (a `daily_cap` fallback decision, healthy), `auth_failed` (the form comes back) or `no_decision` (no decision within 120 s). A run that finds no splash is `no_splash`. Rows 1 to 8 and 11 to 13 hold.
- Given successive runs, when a run is `busy`, `auth_failed`, `no_decision` or `no_splash`, then:
  - the host's alert command runs with the outcome and the run's line;
  - only `auth_failed` and `no_decision` count, and the second in a row since the last healthy or `capped` run runs the reset command once and clears the count;
  - `busy` and `no_splash` leave the count, so a changed password leads to a reset and a full demo never does.

  Rows 2 to 9 and 13 hold.
- Given the probe's runs, when it records them, then each run appends one line with its UTC time and outcome to `probe.log` (and stdout), and each `busy` run adds one to today's line of `busy-per-day`, which the author reads on the host beside the proxy's count. Rows 4 and 9 hold.
- Given a fresh throwaway with the online-demo start values, the CI mock and stub alert and reset commands, when the probe phase runs, then it produces:
  - healthy from a normal run;
  - `busy` from a lowered cap;
  - `capped` from the mock's HTTP 403 "daily cost cap reached";
  - `auth_failed` from a wrong password;
  - `no_decision` with the `Conversation` item disabled.

  The reset stub runs only after the second counted failure in a row. Rows 1 to 9 hold.
- Given `docker/probe.sh`, when it is scanned and run, then:
  - it holds no host name, address, port, key or credential, all of which come from the host's environment;
  - it passes `test-boundaries.sh`;
  - it never prints or stores the password.

  Rows 9, 14 and 15 hold.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions:**
- **AD-25:**
  - the probe in `docker/`, connecting directly from the demo host;
  - it signs in, sends a chat message, checks for a decision, and signs out after each check;
  - the four outcomes, and that only `auth_failed` and `no_decision` count toward the unscheduled reset;
  - the busy count per day beside the proxy's count;
  - no infrastructure detail in the repository.
- **AD-13:**
  - the form sign-in and its fields;
  - the browser envelope on every POST;
  - the reserve and its exemption for sessions that do not come through the proxy;
  - "nothing calls IRIS under a public account without a session";
  - the busy status and the `X-OcuTalon-Busy` marker;
  - the short CSP session that holds the licence connection.
- **AD-19:** the probe reads the published account under AD-19's variable names, so the host keeps one home for those values. Keys and tokens never reach the probe.
- **AD-20 and AD-8:** a gateway 403 "daily cost cap reached" is the `daily_cap` fallback, which marks the day. The turn's shown decision carries it.
- **AD-12:** the live-event envelope and polling.
- **AD-22:** the CI mock's selection (marker, guide prompt, `MOCKKEY`; no default reply) and throwaways only.
- **AD-29 and AD-33:** Lane B's files, and Lane A's scenario used read only.
- **AD-4:** each sign-in without a resume cookie opens its own OcuTalon session.
- No AC contradicts an AD's Rule, and no NFR is unmeasurable.
  - "Frees its licence connection at once" is observed as the CSP session's end. The session is what holds the connection (AD-13, S13).
  - On build 154 a CSP session raises no licence count on the throwaway (DW-251, routed to Story 29.4). That the connection goes with the session is (inference) here.

**Decided in-stage:**
- **bash and curl, with JSON read by key tokens.**
  - The host is known to run Docker, git and SSH (AD-25, Story 29.3); bash and curl are the repository's own host-script tools. No interpreter or package is added: jq, Python and Node are not assumed on the host.
  - IRIS's `%ToJSON` output is compact, and a quote inside a JSON string is always escaped. So `"key":` and `{"seq":` occur only as real keys, and splitting the events body before each `{"seq":` gives one event per line.
- **The turn's decision is the one the `done` event carries.** A `running` event can already carry the triage decision while the reply never comes, and a visitor's demo works only when the turn ends. "A broken online demo is noticed" (the story's goal) selects `done`.
  - Per the AC's definitions, a decision with a fallback reason other than `daily_cap` is healthy. The log line names the reason (`fallback=`), so the author can see it.
- **`no_splash` is its own label.** The AC lists "the instance doesn't serve the splash" separately from the outcomes that count, so it is neither `no_decision` nor counted. It alerts and leaves the count.
- **"Two in a row" counts the counted failures since the last healthy or `capped` run.** The AC names those two as the runs that clear the count. So `busy` and `no_splash` leave it, and a changed password still leads to a reset during a busy spell.
  - The count is cleared when the reset command runs, so a demo that stays broken is reset again after two more counted failures.
- **Any other answer after a served splash is `no_decision`:** a page that is neither the shell nor the form, a message refused with something other than 503, a 401 or 500 on an API call. No decision came.
- **A fresh OcuTalon session every run.**
  - The resume cookie is `Secure`, and the probe calls IRIS over plain HTTP on the host. Keeping one would also store a bearer secret on the host and grow the session's history, and with it each probe turn's request.
  - That is at most 16 probe sessions in a 4-hour reset window. The reset removes them.
- **The capped test reuses Lane A's `daily-cap` scenario** through the test-only message override. No new `ci/mock/scenarios/B/` file is added, although the lead allowed one:
  - it is the gateway answer that `Test.Agent.Decide` already uses (Rule 2);
  - a Lane B spec already selects a Lane A marker (`web/e2e/chat/notice.spec.ts`, `refusal`);
  - changing nothing under `ci/mock` keeps warm stacks valid, and keeps Epic 4's B folder untouched.
  - The healthy run needs no scenario: the agents' `MOCKKEY` gives the normal reply.
- **The message and the wait are test-only overrides with safe defaults.** The healthy, busy and auth runs use the fixed message. Only the capped run needs a marker. The wait can only be shortened, so the 120 s rule holds on the host. Row 15 pins the default of 120, and the live runs other than P5 use it.
- **The status first, then the splash.** AD-25 names "a busy status". The status is sessionless and takes no connection. The splash's own busy marker is the same reading, caught by the busy rule.
- **The probe phase extends the `online-demo` unit; it is not a new live unit.**
  - The unit already starts the flag-on throwaway with the published account and the mock, and holds the cap helpers (Rule 2).
  - A new unit would need a second stack start (about 55 s locally, 150-230 s on CI) and a copy of the start override.
  - The cost is about 50 to 90 s more on the unit (inference: 8 runs, the 10 s wait, about 15 `iris_script` calls). That takes 280 s to about 330-370 s, inside the 540 s local deadline and the 1200 s CI one.
  - The hermetic script covers what the throwaway cannot produce, above all an HTTP 503 (DW-251).
- **Calling conventions.**
  - Command variables are split into words with no shell evaluation, so a program with fixed arguments works and no value is ever run as shell code.
  - The reset runs in the foreground, so its exit status reaches the log line.
  - Exit codes 0, 1 and 2 let a scheduler tell the cases apart.
- **No lock.** Every request is time-limited, so a run ends long before the next scheduled one. Running one probe at a time is the scheduler's job (Story 29.3).
- **`IRISSessionToken` is posted when present.** This keeps the probe working if a later build adds the token. Otherwise a new token would read as `auth_failed` and cause resets.

**Integration ACs:**
- The probe is the consumer of a real flag-on instance: its status, splash, sign-in form and JSON API. It produces each outcome there (rows 1 to 9, live).
- No consumer in this repository. The first consumer will be Story 29.3, which installs and schedules it on the demo host.

**Consumed-by:**
- **Story 29.3 (outward):**
  - runs `docker/probe.sh` every 15 minutes from the host, directly against IRIS, and from an address other than `proxyAddress`. Otherwise its sign-ins count toward the address limit and can be refused (a refusal reads as `auth_failed`);
  - gives it `OCUTALON_DEMO_USER` and `OCUTALON_DEMO_PASSWORD` from the file it passes to IRIS, plus the URL, the state folder and the alert and reset commands;
  - reads `busy-per-day` beside the proxy's count;
  - provides bash and curl.

**Consumes:**
- Story 16.2: the splash's title and form.
- Story 16.3: the sign-in, `ClientAddress`'s exemption, and a session per sign-in.
- Story 16.5: the busy status and the marker, and the unit's cap helpers.
- The JSON API of Epics 0 and 2: `POST /api/v1/messages`, `GET /api/v1/events` and `POST /api/v1/session/end` (`Web.Api.EndSession`, which Story 16.4 later extends).
- The chat turn's shown decision on `chat.message` (`Core.Conversation`, `Turn.ShownDecisionRef`).
- The bridge's `daily_cap` fallback and the day's mark.
- Story 0.11's mock and Lane A's `daily-cap` scenario (read only).
- Story 0.7's recipe.

**Rule 2 (extend, don't copy):**
- **Extensions.** The phase reuses `set_cap`, `http_view`, `public_value`, `status_read`, `session_value`, `hexpw`, `redact` and the deadline gate. The capped run reuses `daily-cap`.
- **Copies, with reasons.**
  - The probe's sign-in sequence and markers (the splash GET, the form POST and its redirect GET, `<app-root`, the token read, the marker header) restate `online_signin`, `signin_outcome`, `page_token` and `marker_in`. The probe is a product file that runs on the host and cannot source test helpers. The test must exercise the probe's own requests, and the unit's helpers stay as they are.
  - The hermetic stub has no sibling: `ci/mock` serves the model API only.

**Footprint extensions** (outside the stated footprint, on no contended list):
- `docker/tests/test-probe.sh` (new): `CHECK_SCRIPTS` names map to `docker/tests/test-<name>.sh`, outside the `docker/**/probe*` glob.
- `ci/units.sh`: one token, shared by region.

Everything else is inside the footprint: `docker/probe.sh` and `docker/tests/test-online-demo.sh`.

**For the lead:**
- **The probe's fixed message** is new text: "Health check from the online demo's probe. Reply with one short sentence." It goes into the probe's own session. Visitors see it only by browsing the message viewer of Visual Trace with the trace accounts. It makes no claim about the product. If it is ruled public-facing text, it is a veto item, and the text is one constant in `docker/probe.sh`.
- **The host interface is a seam with Story 29.3:** the variables, the commands' calling convention, the state files and the exit codes. Recording it in AD-25 is the lead's call (Rule 20). The plan stage does not edit the spine.
- **Host prerequisites for Story 29.3:** bash and curl, and the address rule above. No package is added to the repository.
- **A turn that ends in a fallback other than `daily_cap` is healthy,** as the AC defines it, with the reason in the log line.
- **DW-220:** the unit grows by about 50 to 90 s locally. Record the measured time.
- **Integrate-forward:** `CHECK_SCRIPTS` is a union-merge point if Epic 4 adds tokens.

**Ledger inbox:** none.

**Lead spec gate (2026-10-26, runner C):**
- The probe's fixed message is accepted as a veto ruling (U-90): it is visible in Visual Trace and the UX does not specify it.
- The probe's host interface is recorded in the spine (Consistency Conventions, "Online-demo probe", Rule 20); an interface change in implement or review updates that row in the same commit. DW-254 routes the host's side (schedule, bash and curl, a direct address other than `proxyAddress`, the environment) to Story 29.3.
- Reusing Lane A's existing `daily-cap` mock scenario (read only) instead of a new B scenario is accepted (Rule 2); no existing file under `ci/mock/` changes.
- Footprint extensions accepted: `docker/tests/test-probe.sh` (new; the check-script naming rule) and one `probe` token in `ci/units.sh` (own entry).
- Record the `online-demo` unit's measured time under Verification (DW-220: about 280 s before this story).

## Verification

**Targets and variables:**
- Every command runs from the worktree root, in the foreground with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- Every `ci/iris.sh` call carries lane C's three variables, written out below for the implement stage. QA and review use their own stage names and tags:
  - implement `e16s6i` and `e16s6iw`;
  - QA `e16s6q` and `e16s6qw`;
  - review `e16s6r` and `e16s6rw`.
- The live phase runs only in the `online-demo` unit's throwaway project of lane C (`ocutalon-<label>-e16s6i-<epoch>-<pid>`), never on `ocutalon-slot-c`.
- No class changes, so no warm stack is needed. If a stage holds one anyway, `ci/warm.sh down` with its `w` tag ends it.
- Each stage tears down only its own tags.
- Run `ci/iris.sh build` before every `live` run. A WebKit floor flake (DW-198) gets one rerun.

**Commands:**
- (loop) `bash docker/tests/test-probe.sh` -- every check PASS, rows 10 to 15.
- (loop) `bash ci/checks.sh` -- every block passes:
  - `probe`;
  - `boundaries`, which scans `docker/probe.sh`;
  - `ci-config`, whose units rule finds `test-probe.sh` in `CHECK_SCRIPTS`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s6i bash ci/iris.sh build` -- before each `live` run.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s6i bash ci/iris.sh live online-demo` -- PASS:
  - Stories 16.1 to 16.5's rows, unchanged;
  - the probe phase's rows 1 to 9 and its restores;
  - Task 0's `MEASURED` lines.

  Record its time (DW-220): 280 s before this story; about 330 to 370 s expected, inside the 540 s deadline.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s6i bash ci/iris.sh teardown` -- nothing tagged `e16s6i` is left.
- The shards, the install, production, floor and demo-path units, and the web tests are left to CI. This story changes no class and no web file.

**Shared surfaces:**
- **The public `connectionCap`** (P4) and **`onlineDemo`** (P3) are lowered or flipped, then put back and read back. Every later check of the unit and the restart row assume 8 and "1".
- **The `Conversation` item** (P5) is disabled, then enabled and read back. The restart row's expected run assumes it is enabled.
- **The day's capped mark `^OcuTalonBP.UsageCapped(<date>)`** (P7) makes every later Decide of the day `daily_cap`, and raises the `dailyCap` status condition until it is removed. The phase removes it when it was absent before. Nothing after the phase needs a decision.
- **`Session` rows:** the probe runs leave their own rows, as row 6 leaves its own. They are not removed, because a turn queued while `Conversation` was disabled may still run for its session. No later check counts sessions.
- **`CHECK_SCRIPTS`:** `test-ci-config.sh`'s units rule.
- **The `online-demo` unit's time and deadline,** and the CI `image` job (DW-220).
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19). Each mutation is applied temporarily, observed red, then reverted with the tree byte-identical. Live mutations need a fresh `live online-demo` each, so batch those that turn different rows red into one run.

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | live row 1 | the probe skips `POST /api/v1/session/end` |
| AC 1 | hermetic row 10 | the events GET also sends `-u "$user:$password"` |
| AC 2 | live row 7 | the `daily_cap` test is removed (every decision is healthy) |
| AC 2 | live row 5 | a run with no decision by the deadline is classified healthy |
| AC 2 | live row 4 | the busy rule ignores both `"busy":true` and the marker header (the exempt sign-in then gives healthy) |
| AC 2 | hermetic row 11 | a 503 on the message POST is classified `no_decision` |
| AC 2 | hermetic row 15 | the wait's default becomes 60 |
| AC 3 | live rows 5 and 9 | `busy` clears the count |
| AC 3 | live row 8 | `capped` does not clear the count |
| AC 3 | live row 2 | the reset runs at the first counted failure |
| AC 4 | live row 4 | the busy count is not written |
| AC 6 | hermetic row 15 | the probe gains a default URL `http://203.0.113.9:52773` |
| AC 6 | hermetic row 14 | the configuration error line prints the variable's value |

**Mutation record:** the stage that adds or changes each pinning test writes its `mutation:` line here.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-26).** Sources:
- the cached `epic-16-context.md`, and Story 16.5's spec for continuity;
- the spine's AD-13, AD-19, AD-22 and AD-25;
- Stories 16.6 and 29.3 in `epics.md`, and FR-59;
- the code the probe calls.

The spec passed the READY FOR DEVELOPMENT standard. The run halted after planning, as the dispatch asked.
- **Warnings:** `oversized`.
- **Decided in-stage:** under Design Notes.
- **Items for the lead's gate:** under For the lead (the probe's message text, the host interface as a seam with Story 29.3, host prerequisites, healthy with another fallback reason, DW-220's growth).
- **Ledger inbox:** none.
- **Footprint extensions:** `docker/tests/test-probe.sh` (new) and one `ci/units.sh` token.
- **No new mock scenario:** Lane A's `daily-cap` is reused, although the lead allowed one under `ci/mock/scenarios/B/`.
