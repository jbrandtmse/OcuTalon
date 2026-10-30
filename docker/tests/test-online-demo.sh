#!/usr/bin/env bash
# Live test of the online demo's real start (Story 16.1; AD-13, AD-19, AD-23, AD-24, AD-25): builds the image and starts it in one
# throwaway compose project with the online-demo flag on and test start values, and checks, in this order:
#   - the start (rows 1 to 3): the log's STEP lines are the expected run (Bridge.Installer, Public, Roles, Users, Web, ... Ready), every step
#     OK, RESULT OK and readiness 1; each of the 13 public keys reads back as its start value through Public.Settings and through
#     Setting.Get (a password is compared inside IRIS and printed as 1 or 0); /ocutalon/public/status reports the next reset that NextReset
#     computes, on a 4-hour step of the anchor, with busy false and the last reset as given; Decide's three budget rows;
#   - the public accounts and the password guard (row 4): the roles, the flags, the README account disabled, the guard setting and routine
#     (no staging routine, no password in the source) and the Visual Trace page size 100 in OCUTALON and OCUORDERS for both names;
#   - every password-change form of spike S17 over HTTP (rows 5 and 6), F1 to F11 of the spec, from curl: each is sent for the demo account,
#     the read-only account (name in capitals) and a control user with no public account, and afterwards both public accounts still sign in
#     with their published passwords and not with the attempted one, while the control's password changed exactly for the forms of
#     CHANGE_FORMS (Task 0 measured them on build 154; a change in IRIS's behaviour turns this unit red in either direction); the sign-in
#     page has no old-password or repeat-password field and neither has a trace application's page for %CSP.PasswordChange.cls with no
#     session; F12 posts IRIS's own password-change page of each trace application (served to a signed-in user on build 154) the same way;
#   - the splash with no session (Story 16.2, row 11): the /ocutalon* applications in IRIS are exactly the five, every OcuTalon path that
#     needs a sign-in gives the splash (the h1, no app-root, the splash's exact policy over its own two hashed blocks, and no-store), a
#     sign-in image is served, /ocutalon/public/status answers and /ocutalon/public/x does not, the API answers 401 signed_out and the
#     trace applications' pages give IRIS's sign-in page; the splash form's input names are printed as "MEASURED splash form inputs:"
#     and none is outside the four of the proxy's allow-list;
#   - the visitor's own session (Story 16.3), after the splash checks: row 12, six sign-ins from one forwarded address in the first phase
#     (the proxy address is one that no request comes from) are all exempt and write no counter row; row 4, a sign-in at the OCUTALON
#     trace application sets no resume cookie and creates no Session row, and the same jar's first /ocutalon/ request does; row 6, a
#     sign-in, a real message, a resume with the cookie and a sign-out, after which the resume reference is searched for in the container's
#     logs, the event log, the live events, the audit log and every global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC (counts
#     only; it runs with the password searches, after the browser and after the restart); row 14, the seeded address limit; Task 0's
#     MEASURED lines (the resume Set-Cookie attributes, the browser's Secure cookie, the host's REMOTE_ADDR, CSP session id reuse);
#     (QA) row 5 over HTTP: a dozen tampered or malformed cookies (a real reference with a character changed, added or removed, padding,
#     the other case, standard base64 letters, a wide character, escapes, 2000 characters, 22 of no permitted one) each get the shell, a
#     new cookie and a new session, never an error or a console log line, and the real reference still resumes its own session; and the
#     reference searches' controls: the three log sources are readable and not empty, and each searched record (the event log, the live
#     events, the production message headers, the audit log, each of the three databases of the global scan) holds something the search
#     can find, so that a count of 0 cannot come from a search that sees nothing;
#   - the address counter's key (Story 29.5; AD-3, AD-5, AD-25): none exists after the start, the splash checks and row 12's exempt
#     sign-ins; phase 2 removes the node row 12's lookups made, and its first counted sign-in makes it, with the start's last reset as its
#     marker and no row under the plain SHA-256; row 13 adds a counter row before the restart, and after it the row still counts, the marker
#     is unchanged, and no node of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC holds the key but its own, raw or base64url (counts
#     only; the key is never printed);
#   - the browser (rows 7 to 12, Story 16.8's reset.spec.ts (the last ten minutes before a reset on a controlled clock, and a real reset four
#     minutes away) with Task 0's MEASURED lines, and the splash's S1 to S12, S2b, S6b and S8b, and Story 16.3's R1, R2, R4 and R5; the REL-2 online run
#     has its own unit, test-online-demo-path.sh): the project online-demo of web/playwright.config.ts (web/e2e-online/) as both public accounts;
#   - the proxied phase (Story 16.3, rows 10 and 11 and Task 0 (c)): the public proxy address is set to the address IRIS sees for this
#     host's requests, a first proxied sign-in must write a counter row (else the check fails naming the derived address), then five
#     sign-ins from one forwarded address are counted and the sixth is refused with the splash's field error, a cookie sign-in resumes,
#     "A, C" counts C, and address-limit.spec.ts (L1) runs the page case; the proxy address is put back and read back on every path;
#   - the busy states (Story 16.5): after the browser step the public connection cap reads back 8 and the reserve 2 (B1 lowers the cap and
#     restores it); in the proxied phase, after row 11, the HTTP view of the connections (what /ocutalon/public/status counts, found by the
#     flip of Task 0 (a): the cap set to r plus the reserve, with r what an iris_script reads) is read with no session, five status GETs and
#     five splash GETs leave it unchanged (row 4), and two signed-in sessions leave it unchanged too (Task 0 (b): a CSP session is not counted
#     on build 154, so the cap, set from the baseline, brings the status to the boundary in place of more sessions); with S1 and S2 signed in,
#     a cap of the baseline plus the reserve plus 1 gives a status that is not busy with no X-OcuTalon-Busy header and the baseline plus the
#     reserve gives busy with the header and status 200 (row 1), the splash of a fresh jar shows the busy error and link with the header and
#     the splash's exact policy, and with the cap one higher a fresh splash shows no busy error and no header (row 2); with the status busy
#     a proxied sign-in and one with a valid resume cookie are refused with the busy splash, the header, no resume cookie, no session, no
#     counter row and no attach (row 5), and with the cap one higher a proxied sign-in is let in: the boundary is the status's own, because
#     the check leaves out no own connection (OWNCONNECTIONS is 0, Story 29.7; row 6); the cap is put back to 8 and read back on every
#     path, beside the proxy address; MEASURED lines give Task 0's results;
#   - the probe (Story 16.6; docker/probe.sh, AD-25), in a phase right after the proxy address is put back (so no request is proxied) and
#     before the password-log checks, with the three runners' model keys pointed at the mock key variable for P1 to P8
#     (Test.Agent.RunnerFixture, so that a turn reaches the mock) and put back and read back before P9 and after the phase: nine runs on one state folder
#     with stub alert and reset commands that append "alert <outcome> <line>" or "reset" to one record file: P1 healthy (row 1: exit 0,
#     no alert or reset, exactly one new Session row whose CSP session
#     no longer exists), P2 a wrong password (row 2, auth_failed count=1), P3 the online-demo flag "0" (row 3, no_splash), P4 the cap at the
#     HTTP view plus the reserve (row 4, busy, today's line of busy-per-day, no new Session row), P5 the Conversation item disabled with a
#     10 s wait (row 5, no_decision count=2, the reset line right before the alert line), P6 a wrong password (row 6, the count starts
#     again), P7 the mock's daily-cap marker (row 7, capped with fallback=daily_cap, the day's mark removed), P8 a wrong password (row 8,
#     capped cleared the count), P9 (Story 29.6) the runners' keys put back to the Provider step's placeholder first, so that the turn is
#     a no_key fallback: degraded count=1 fallback=no_key, exit 1, one more alert line, no reset and the count unchanged;
#     row 9: the nine log lines in order, seven alert lines and one reset line in the record, the AddressCounter
#     rows unchanged, neither password anywhere, and the flag, the cap, the Conversation item and the capped mark read back. Task 0's
#     MEASURED lines (a) to (f) give a healthy turn's events, the capped mark, the disabled Conversation item, the sign-out (a control
#     session, then the probe's), the splash cookie and the phase's time. The phase starts only with 150 s of the deadline left;
#   - Story 29.3, IRIS's own answers to the host check (release/demo-host-check.sh, docker/tests/lib-online.sh): signed out and with no
#     proxy, each item on a jar of its own ended with logout_all, the section prints one "MEASURED host probe" line per host_probes probe
#     and pins its status and whether the page holds an IRIS form field against the line's <iris> field; a signed-in trace page loads the
#     /csp/broker/ file the check reads, which IRIS serves with 200; the splash's three-field POST and the trace page's four-field POST
#     (dummy values) come back as IRIS's sign-in page: the splash's refused (aria-invalid), the trace page's the page a plain GET gives;
#   - neither published password is in the container's output, messages.log, the after-start log, the production event log, the live
#     events or the audit log, checked after the browser and again after the restart;
#   - a restart (row 13): the second start's STEP lines are the expected run for a restart, all OK, ready, the guard setting still
#     Check^OcuTalonPasswordGuard and both public accounts still sign in with their published passwords.
# Test start values (a compose override written to this run's temporary folder, never a tracked file): OCUTALON_ONLINE_DEMO=1, the demo
# account DemoVisitor and the read-only account TraceReader with random passwords per run (hex, passed to compose by ${VAR} interpolation so
# that they are in no file, and replaced by <redacted> in every line this script prints), a 4-hour reset step from the anchor
# two hours after the unit's start, to the minute (quoted in the override, which compose would otherwise read as a timestamp), the last reset 2026-10-25T08:00:00Z (scheduled), the proxy address 192.0.2.10 (TEST-NET: no request of this test is
# proxied), a connection cap of 8 with a reserve of 2, 50 messages an hour, a daily cost cap of 20 USD and no gateway variable.
# Every request that signs in ends with ?IRISLogout=end on its application and on /ocutalon/, each with its own cookie jar, so that no form
# leaves a licence connection held; every page request carries a unique probe=<n> query parameter, because the web gateway keeps the answer
# to a URL (test-bundle-folder.sh). No password is ever printed.
# It does not rebuild the web bundle: ci/iris.sh build makes it, as for the other browser units. The project is unique and publishes its web
# port only on 127.0.0.1, on the first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). An EXIT trap removes the project with its volume
# and images. Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held); the browser run's global timeout is what is left of it minus 20 s, and the browser does not start with under 60 s left.
# The stack's CSP sessions time out after 120 s on /ocutalon, /ocutalon/api and the trace applications (Story 16.4; AD-13), and its pages
# stop polling and leave for the splash after the idle cap (600 s of no key press, click or sent message): no check here reuses a jar or a
# page after more than 120 s without a request, and a case of the browser step that lets a page's clock pass 600 s keeps the page active.
# The shared start (the test values, redact, the probe counter, logout_all and online_signin) is docker/tests/lib-online.sh's, which
# test-online-session.sh (Story 16.4) uses too, and so do the S17 forms (password_form) and the host check's probes (host_probes).
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later, curl, the
# built web bundle and Chromium (npx --prefix web playwright install chromium; ci/iris.sh live installs it).
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-demo
live_web_port || exit 1

version=$(manifest_version src/module.xml)
ipm_version=0.10.10
base="http://127.0.0.1:$web_port"

# The users, the passwords, the anchor and the last reset come from lib-online.sh (online_values); the control user is this unit's own.
online_values
control_user=ZzOnlineControl
control_password=$(hexpw)

# The forms of S17 that change a password on build 154, as "<form>@<where>" for every request that does (Task 0 measured them; the unit
# asserts both directions: a listed request changes the control's password, an unlisted one does not). <where> is root (/ocutalon/), state
# (/ocutalon/api/v1/state), trace-ocutalon and trace-ocuorders (the message viewers, posted with the session token of their sign-in page) and
# pwpage-ocutalon and pwpage-ocuorders (F12, IRIS's own password-change page of a trace application). Measured on build 154: every form but
# F11 (names in mixed case) changes it at /ocutalon/, F1 and F3 also at /ocutalon/api/v1/state and at both trace applications, and F12 at both.
CHANGE_FORMS="F1@root F1@state F1@trace-ocutalon F1@trace-ocuorders F2@root F3@root F3@state F3@trace-ocutalon F3@trace-ocuorders F4@root F5@root F6@root F7@root F8@root F9@root F10@root F12@pwpage-ocutalon F12@pwpage-ocuorders"

# No password of the run, current or attempted, is printed: the checks print names, outcomes and counts (a password is compared
# inside IRIS or by curl), and every tail of a log that this script shows passes through redact (lib-online.sh).
# The resume reference of row 6 is one more such value, once it is known.
resume_ref=

# An attempted (new) password is random too, and is never printed.
new_attempt() { hexpw; }

# --- the test start values: an override in this run's temporary folder; the passwords come from the environment of docker compose ---

online_override

# --- build and start (row 1) ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log" | redact
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200 | redact
  dc logs --tail 20 iris 2>&1 | cut -c1-200 | redact
  die "row 1 the first start did not end ready within 400 s"
fi
pass "row 1 the first start ended ready"

expected_run "nothing to clear" "installed $ipm_version (was none)" "mapped into OCUTALON" "skipped (package not installed)" \
  "loaded (not installed)" "$version" > "$tmp/expected.row1"
check_log "row 1" "$tmp/expected.row1"
check_no_key "row 1"

# --- row 2: every key, through the accessor and through Setting.Get ---

# The lines that print each key through the accessor and through Setting.Get; a password is compared inside IRIS with the start variable.
keys_lines=()
for k in onlineDemo demoUser readonlyUser resetIntervalHours resetAnchor lastReset lastResetKind proxyAddress connectionCap connectionReserve messageAllowance ready; do
  keys_lines+=("Write !,\"CHK|$k|\",##class(OcuTalon.Data.Public.Settings).Get(\"$k\"),\"|\",##class(OcuTalon.Data.Setting).Get(\"$k\")")
done
for pair in demoPassword:OCUTALON_DEMO_PASSWORD readonlyPassword:OCUTALON_READONLY_PASSWORD; do
  keys_lines+=("Set e=\$SYSTEM.Util.GetEnviron(\"${pair#*:}\") Write !,\"CHK|${pair%%:*}|\",((e'=\"\")&&(##class(OcuTalon.Data.Public.Settings).Get(\"${pair%%:*}\")=e)),\"|\",((e'=\"\")&&(##class(OcuTalon.Data.Setting).Get(\"${pair%%:*}\")=e))")
done
check_session "row 2: all 13 keys and readiness read back as their start values through the accessor and through Setting.Get" OCUTALON \
  "CHK|onlineDemo|1|1
CHK|demoUser|$demo_user|$demo_user
CHK|readonlyUser|$readonly_user|$readonly_user
CHK|resetIntervalHours|4|4
CHK|resetAnchor|$anchor|$anchor
CHK|lastReset|$last_reset|$last_reset
CHK|lastResetKind|scheduled|scheduled
CHK|proxyAddress|$proxy_start|$proxy_start
CHK|connectionCap|8|8
CHK|connectionReserve|2|2
CHK|messageAllowance|50|50
CHK|ready|1|1
CHK|demoPassword|1|1
CHK|readonlyPassword|1|1" \
  "${keys_lines[@]}" 'Halt'

computed_next=$(printf '%s\n' 'Write !,"CHK|next|",##class(OcuTalon.Data.Public.Settings).NextReset()' 'Halt' | session_value OCUTALON next)
next_probe
status_json=$(curl -s --max-time 30 "$base/ocutalon/public/status?probe=$probes")
status_verdict=$(node - "$status_json" "$computed_next" "$anchor" "$last_reset" <<'EOF'
const [, , json, computed, anchor, lastReset] = process.argv;
const problems = [];
let status = {};
try {
  status = JSON.parse(json);
} catch {
  problems.push('the answer is not JSON');
}
const step = 4 * 3600 * 1000;
const next = Date.parse(status.nextReset ?? '');
const now = Date.now();
if (status.ready !== true) problems.push('ready is not true');
if (!computed || status.nextReset !== computed) problems.push('nextReset is not what NextReset() computes');
if (!Number.isFinite(next) || (next - Date.parse(anchor)) % step !== 0) problems.push('nextReset is not on a 4-hour step of the anchor');
if (!(next > now)) problems.push('nextReset is not later than now');
if (next - now > step) problems.push('nextReset is more than 4 hours away');
if (status.busy !== false) problems.push('busy is not false');
if (status.lastReset !== lastReset) problems.push('lastReset differs');
if (status.lastResetKind !== 'scheduled') problems.push('lastResetKind differs');
console.log(problems.length === 0 ? 'ok' : problems.join('; '));
EOF
)
if [ "$status_verdict" = ok ]; then
  pass "row 2: /ocutalon/public/status is ready, its nextReset is NextReset() on a 4-hour step of the anchor (later than now, at most 4 hours away), busy is false and the last reset is as given"
else
  fail "row 2: /ocutalon/public/status: $status_verdict"
fi

# --- row 3: Decide's budget rows ---

check_session "row 3: Decide's budget rows are the cap 20 and an empty spend and date" OCUTALON \
  "CHK|row|DailyCostCapUSD|[20]
CHK|row|GatewaySpendUSD|[]
CHK|row|GatewaySpendDate|[]" \
  'For s="DailyCostCapUSD","GatewaySpendUSD","GatewaySpendDate" { Set id="OcuTalon.Production||Decide||*||"_s Write !,"CHK|row|",s,"|",$Select(##class(Ens.Config.DefaultSettings).%ExistsId(id):"["_##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue_"]",1:"<none>") }' \
  'Halt'

# --- row 4: the public accounts and the guard ---
# The README account is not enabled: on a fresh flag-on volume it is never created, and one that exists is disabled; both read as 0.

check_session "row 4: the accounts, the README account, the guard and the page size pins" %SYS \
  "CHK|acct|$demo_user|OcuTalonTraceViewer,OcuTalonUser|1|0|1|1
CHK|acct|$readonly_user|OcuTalonTraceViewer|1|0|1|1
CHK|readme-enabled|0
CHK|validation|Check^OcuTalonPasswordGuard
CHK|guard-routine|1|0
CHK|guard-holds|OCUTALON_DEMO_PASSWORD|0
CHK|guard-holds|OCUTALON_READONLY_PASSWORD|0
CHK|pin|$demo_user|OCUTALON|100
CHK|pin|$demo_user|OCUORDERS|100
CHK|pin|$readonly_user|OCUTALON|100
CHK|pin|$readonly_user|OCUORDERS|100" \
  "For u=\"$demo_user\",\"$readonly_user\" { Kill o,r If '##class(Security.Users).Exists(u,.o) { Write !,\"CHK|acct|\",u,\"|<missing>\" Continue } For i=1:1:o.Roles.Count() { Set r(o.Roles.GetAt(i))=1 } Set rl=\"\",k=\"\" For { Set k=\$Order(r(k)) Quit:k=\"\"  Set rl=rl_\$Select(rl=\"\":\"\",1:\",\")_k } Write !,\"CHK|acct|\",u,\"|\",rl,\"|\",o.Enabled,\"|\",o.ChangePassword,\"|\",o.PasswordNeverExpires,\"|\",o.AccountNeverExpires }" \
  'If ##class(Security.Users).Exists("ocutalon",.m) { Write !,"CHK|readme-enabled|",m.Enabled } Else { Write !,"CHK|readme-enabled|0" }' \
  'Do ##class(Security.System).Get(,.sp) Write !,"CHK|validation|",$Get(sp("PasswordValidationRoutine"))' \
  'Write !,"CHK|guard-routine|",##class(%Routine).Exists("OcuTalonPasswordGuard.mac"),"|",##class(%Routine).Exists("OcuTalonPasswordGuardNew.mac")' \
  'Set rt=##class(%Routine).%New("OcuTalonPasswordGuard.mac") Set src="" While '"'"'rt.AtEnd { Set src=src_rt.ReadLine()_$Char(10) }' \
  'For p="OCUTALON_DEMO_PASSWORD","OCUTALON_READONLY_PASSWORD" { Set e=$SYSTEM.Util.GetEnviron(p) Write !,"CHK|guard-holds|",p,"|",((e'"'"'="")&&($Find(src,e)>0)) }' \
  "For u=\"$demo_user\",\"$readonly_user\" { For n=\"OCUTALON\",\"OCUORDERS\" { Write !,\"CHK|pin|\",u,\"|\",n,\"|\",\$Get(^|n|EnsPortal.Settings(u,\"VisualTrace\",\"ItemsPerPage\")) } }" \
  'Halt'

# --- the control user: no public account, the role OcuTalonUser, so that it signs in to the shell ---

created=$(live_fixture_user "$control_user" "$control_password" "OcuTalonUser" "online-demo control")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the control user $control_user (role OcuTalonUser) is created"
else
  die "the control user $control_user could not be created ('$created')"
fi

# --- rows 5 and 6: the password-change forms over HTTP ---

# signin_outcome <user> <password>: a plain sign-in POST to /ocutalon/, on a jar of its own, and what it led to, ended with a sign-out:
#   shell    IRIS accepted it and the page is the application's shell;
#   norole   IRIS accepted it and the page says the account has no OcuTalon user role;
#   refused  the sign-in page with the failed-sign-in error (aria-invalid);
#   other    anything else.
signin_outcome() {
  local jar outcome
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  online_signin "$jar" "" "" "$1" "$2" > /dev/null
  case $(cat "$jar.b" 2>/dev/null) in
    *'aria-invalid="true"'*) outcome=refused ;;
    *'user role. Ask an OcuTalon admin to add it.'*) outcome=norole ;;
    *'<app-root'*) outcome=shell ;;
    *) outcome=other ;;
  esac
  logout_all "$jar" /ocutalon/
  printf '%s' "$outcome"
}

# page_token <jar> <url>: the IRISSessionToken that the sign-in or password-change page of the url puts in its form (the jar takes the session
# cookie), or nothing. A trace application's form is posted with it, as a browser posts it.
page_token() {
  curl -s --max-time 30 -c "$1" -b "$1" "$2" | sed -n 's/.*name="IRISSessionToken" value="\([^"]*\)".*/\1/p' | head -n 1
}

# form_request <form> <path> <app path> <user> <old> <new>: sends the form to the path on a jar of its own and signs out. A trace
# application's F1 and F3 carry the session token of its sign-in page; F12 signs in at the application with its form first, then posts
# the password-change page's own form with that page's token.
form_request() {
  local form=$1 path=$2 app=$3 user=$4 old=$5 new=$6 jar url
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  url="$base$path?probe=$probes"
  local common=(-s --max-time 30 -o /dev/null -c "$jar" -b "$jar")
  local token=""
  case $path in
    /ocutalon/trace/*)
      if [ "$form" = F12 ]; then
        next_probe
        token=$(page_token "$jar" "$base${app}EnsPortal.MessageViewer.zen?probe=$probes")
        [ -n "$token" ] || fail "row 5: $form for $user at $path: the application's sign-in page gave no session token, so the request cannot sign in"
        next_probe
        curl "${common[@]}" --data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$user" --data-urlencode "IRISPassword=$old" \
          --data-urlencode 'IRISLogin=Login' "$base${app}EnsPortal.MessageViewer.zen?probe=$probes"
        next_probe
        token=$(page_token "$jar" "$url")
        [ -n "$token" ] || fail "row 5: $form for $user at $path: the password-change page gave no session token, so the request cannot sign in"
        next_probe
        password_form F12 "$user" "$old" "$new" "$token"
        curl "${common[@]}" "${form_args[@]}" "$base$path?probe=$probes"
        logout_all "$jar" "$app"
        return 0
      fi
      case $form in
        F1 | F3)
          next_probe
          token=$(page_token "$jar" "$base$path?probe=$probes")
          [ -n "$token" ] || fail "row 5: $form for $user at $path: the application's sign-in page gave no session token, so the request cannot sign in"
          ;;
      esac
      ;;
  esac
  password_form "$form" "$user" "$old" "$new" "$token"
  curl "${common[@]}" ${form_args[@]+"${form_args[@]}"} "$url${form_query:+&$form_query}"
  logout_all "$jar" "$app"
}

# The password that the control user has now: a form that changes it moves this to the attempted one.
control_now=$control_password

# in_change_forms <form@where>: 0 when the request is listed.
in_change_forms() { case " $CHANGE_FORMS " in *" $1 "*) return 0 ;; esac; return 1; }

# measured: the requests that changed the control's password in this run, for the report.
measured=""

# run_form <form> <where> <path> <app path>
run_form() {
  local form=$1 where=$2 path=$3 app=$4 key new target name published accepted shown outcome_ok outcome_bad
  key="$form@$where"
  for target in demo readonly control; do
    new=$(new_attempt)
    case $target in
      demo) name=$demo_user shown=$demo_user published=$demo_password accepted=shell ;;
      readonly) name=$readonly_user_caps shown=$readonly_user published=$readonly_password accepted=norole ;;
      control) name=$control_user shown=$control_user published=$control_now accepted=shell ;;
    esac
    form_request "$form" "$path" "$app" "$name" "$published" "$new"
    outcome_ok=$(signin_outcome "$shown" "$published")
    outcome_bad=$(signin_outcome "$shown" "$new")
    case $target in
      demo | readonly)
        if [ "$outcome_ok" = "$accepted" ] && [ "$outcome_bad" = refused ]; then
          pass "row 5: $key for the $target account: its published password still signs in ($accepted) and the attempted one does not"
        else
          fail "row 5: $key for the $target account: the published password gives '$outcome_ok' (wanted $accepted) and the attempted one '$outcome_bad' (wanted refused)"
        fi
        ;;
      control)
        if [ "$outcome_bad" = shell ] && [ "$outcome_ok" = refused ]; then
          control_now=$new
          measured="$measured $key"
          if in_change_forms "$key"; then
            pass "row 5: $key changes the control's password, as CHANGE_FORMS says"
          else
            fail "row 5: $key changes the control's password, and CHANGE_FORMS does not list it"
          fi
        elif [ "$outcome_ok" = shell ] && [ "$outcome_bad" = refused ]; then
          if in_change_forms "$key"; then
            fail "row 5: $key leaves the control's password, and CHANGE_FORMS lists it"
          else
            pass "row 5: $key leaves the control's password, as CHANGE_FORMS says"
          fi
        else
          fail "row 5: $key for the control: the current password gives '$outcome_ok' and the attempted one '$outcome_bad' (wanted one shell and one refused)"
        fi
        ;;
    esac
  done
}

for form in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11; do
  run_form "$form" root /ocutalon/ /ocutalon/
  case $form in
    F1 | F3)
      run_form "$form" state /ocutalon/api/v1/state /ocutalon/api/
      run_form "$form" trace-ocutalon /ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen /ocutalon/trace/ocutalon/
      run_form "$form" trace-ocuorders /ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen /ocutalon/trace/ocuorders/
      ;;
  esac
done
# F12: the page %CSP.PasswordChange.cls that each trace application serves to a signed-in user (see row 6).
run_form F12 pwpage-ocutalon /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls /ocutalon/trace/ocutalon/
run_form F12 pwpage-ocuorders /ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls /ocutalon/trace/ocuorders/
echo "MEASURED the requests that changed the control's password:${measured:- none}"

next_probe
login_page=$(curl -s --max-time 30 "$base/ocutalon/?probe=$probes")
case $login_page in
  *'Try OcuTalon in two minutes'*) login_shown=1 ;;
  *) login_shown=0 ;;
esac
if [ "$login_shown" = 1 ] && ! printf '%s' "$login_page" | grep -Eqi 'name="[^"]*(OldPassword|RepeatPassword)'; then
  pass "row 6: the sign-in page has no old-password or repeat-password field"
else
  fail "row 6: the sign-in page is missing, or offers an old-password or repeat-password field"
fi
# With no session a trace application shows IRIS's own sign-in page for %CSP.PasswordChange.cls (build 154 answers 200 and the page holds no
# old-password or repeat-password field). Signed in, build 154 serves IRIS's own password-change page there with 200, not 404 (measured):
# no OcuTalon page offers a change, but IRIS's does, so the guard decides, as F12 above shows for both public accounts.
for app in ocutalon ocuorders; do
  next_probe
  answer=$(curl -s --max-time 30 -w '\n%{http_code}' "$base/ocutalon/trace/$app/%25CSP.PasswordChange.cls?probe=$probes")
  code=${answer##*$'\n'}
  anonymous=${answer%$'\n'*}
  if [ "$code" = 200 ] && printf '%s' "$anonymous" | grep -Eq 'name="?IRISPassword' \
    && ! printf '%s' "$anonymous" | grep -Eqi 'name="?[^" >]*(OldPassword|RepeatPassword)'; then
    pass "row 6: with no session the $app trace application's page for %CSP.PasswordChange.cls is IRIS's sign-in page (200, a password field) with no old-password or repeat-password field"
  else
    fail "row 6: with no session the $app trace application's page for %CSP.PasswordChange.cls is not IRIS's sign-in page (status '$code', or no password field) or offers a password-change field"
  fi
done

# --- Story 16.2, row 11: with no session, every OcuTalon path gives the splash, the status or a sign-in page ---

# splash_get <path>: GETs the path on a jar of its own with a unique probe, leaves the body in $tmp/splash.body, ends the jar's session
# on /ocutalon/ and prints the HTTP status.
splash_get() {
  local jar code sep='?'
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  case $1 in *\?*) sep='&' ;; esac
  rm -f "$tmp/splash.headers" "$tmp/splash.body"
  code=$(curl -s --max-time 30 -D "$tmp/splash.headers" -o "$tmp/splash.body" -w '%{http_code}' -c "$jar" -b "$jar" "$base$1${sep}probe=$probes")
  logout_all "$jar" /ocutalon/
  printf '%s' "$code"
}

# splash_envelope: reads $tmp/splash.headers and $tmp/splash.body (QA): prints "ok" when the Content-Security-Policy header is the
# splash's policy over the SHA-256 of the body's one <style> and one <script> (exactly one script hash, one style hash, no
# unsafe-inline or unsafe-eval) and Cache-Control is no-store, otherwise what differs.
splash_envelope() {
  node -e '
    const fs = require("fs"), crypto = require("crypto");
    const headers = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/);
    const body = fs.readFileSync(process.argv[2], "utf8");
    const header = (name) => headers.filter((line) => line.toLowerCase().startsWith(name + ":")).map((line) => line.slice(name.length + 1).trim());
    const hash = (text) => crypto.createHash("sha256").update(text, "utf8").digest("base64");
    const styles = [...body.matchAll(/<style>([\s\S]*?)<\/style>/g)], scripts = [...body.matchAll(/<script>([\s\S]*?)<\/script>/g)];
    const problems = [];
    if (styles.length !== 1 || scripts.length !== 1) problems.push("the body has " + styles.length + " style and " + scripts.length + " script blocks");
    const policy = header("content-security-policy");
    if (policy.length !== 1) problems.push(policy.length + " Content-Security-Policy headers");
    const want = "default-src \x27none\x27; script-src \x27sha256-" + hash(scripts[0] ? scripts[0][1] : "") + "\x27; style-src \x27sha256-" + hash(styles[0] ? styles[0][1] : "") + "\x27; img-src \x27self\x27; form-action \x27self\x27; frame-ancestors \x27none\x27; base-uri \x27none\x27";
    if (policy[0] !== want) problems.push("policy is not the splash policy over the body blocks");
    if (/unsafe-/.test(policy.join(" "))) problems.push("policy has an unsafe- keyword");
    if ((policy.join(" ").match(/sha256-/g) || []).length !== 2) problems.push("policy does not hold exactly two hashes");
    if (header("cache-control").join(",") !== "no-store") problems.push("Cache-Control is " + header("cache-control").join(","));
    console.log(problems.length === 0 ? "ok" : problems.join("; "));
  ' "$tmp/splash.headers" "$tmp/splash.body" 2>&1 | tr '\n' ' '
}

check_session "row 11: the /ocutalon* applications in IRIS are exactly the five" %SYS \
  "CHK|apps|/ocutalon,/ocutalon/api,/ocutalon/public,/ocutalon/trace/ocuorders,/ocutalon/trace/ocutalon" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM Security.Applications WHERE Name LIKE ? ORDER BY Name","/ocutalon%") Set l="" While rs.%Next() { Set l=l_$Select(l="":"",1:",")_rs.%Get("Name") } Write !,"CHK|apps|",l' \
  'Halt'

bundle_main=$(dc exec -T iris sh -c "ls /durable/iris/csp/ocutalon-web" 2>/dev/null | tr -d '\r' | grep -E '^main-[A-Za-z0-9]+\.js$' | head -n 1)
if [ -z "$bundle_main" ]; then
  fail "row 11: no main-<hash>.js bundle file in the stack's web folder"
  bundle_main=main.js
fi
for path in /ocutalon/ '/ocutalon/x/y?a=1' /ocutalon/index.html "/ocutalon/$bundle_main"; do
  code=$(splash_get "$path")
  if [ "$code" = 200 ] && grep -q '<h1>Try OcuTalon in two minutes</h1>' "$tmp/splash.body" && ! grep -q '<app-root' "$tmp/splash.body"; then
    pass "row 11: with no session $path gives the splash (200, its h1, no app-root)"
  else
    fail "row 11: with no session $path gives status '$code', not the splash"
  fi
  envelope=$(splash_envelope)
  if [ "$envelope" = "ok " ]; then
    pass "row 11 (QA): $path is answered with the splash's exact policy over its one style and one script (two hashes, no unsafe- keyword) and no-store"
  else
    fail "row 11 (QA): $path's envelope: $envelope"
  fi
  if [ "$path" = '/ocutalon/x/y?a=1' ]; then
    inputs=$(grep -o '<input [^>]*' "$tmp/splash.body" | sed -n 's/.* name="\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ')
    echo "MEASURED splash form inputs: ${inputs% }"
    outside=
    for name in $inputs; do
      case $name in IRISSessionToken | IRISUsername | IRISPassword | IRISLogin) ;; *) outside="$outside $name" ;; esac
    done
    if [ -z "$outside" ] && printf '%s' "$inputs" | grep -q IRISUsername; then
      pass "row 7: the splash form's input names are within IRISSessionToken, IRISUsername, IRISPassword and IRISLogin"
    else
      fail "row 7: the splash form's input names are outside the four of the proxy's allow-list:${outside:- (or the form has no user name field)}"
    fi
  fi
done

next_probe
jar="$tmp/jar.$probes"
: > "$jar"
logo=$(curl -s --max-time 30 -o /dev/null -w '%{http_code} %{content_type}' -c "$jar" -b "$jar" "$base/ocutalon/assets/brand/OcuTalon-Logo-light-640.png?probe=$probes")
logout_all "$jar" /ocutalon/
if [ "$logo" = '200 image/png' ]; then
  pass "row 11: with no session the 1x logo is served as image/png"
else
  fail "row 11: with no session the 1x logo gives '$logo', wanted '200 image/png'"
fi

code=$(splash_get /ocutalon/public/status)
status_keys=$(node -e 'try { console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).sort().join(",")); } catch { console.log("not JSON"); }' "$tmp/splash.body")
if [ "$code" = 200 ] && [ "$status_keys" = busy,lastReset,lastResetKind,nextReset,ready ]; then
  pass "row 11: /ocutalon/public/status gives 200 JSON with its five keys"
else
  fail "row 11: /ocutalon/public/status gives status '$code' and keys '$status_keys'"
fi
code=$(splash_get /ocutalon/public/x)
if [ "$code" = 404 ]; then
  pass "row 11: /ocutalon/public/x gives 404"
else
  fail "row 11: /ocutalon/public/x gives '$code', wanted 404"
fi
for path in /ocutalon/api/v1/state /ocutalon/api/v1/events; do
  code=$(splash_get "$path")
  if [ "$code" = 401 ] && grep -q 'signed_out' "$tmp/splash.body"; then
    pass "row 11: with no session $path gives 401 signed_out"
  else
    fail "row 11: with no session $path gives status '$code' (wanted 401 with signed_out)"
  fi
done
for app in ocutalon ocuorders; do
  for page in EnsPortal.VisualTrace.zen EnsPortal.MessageViewer.zen; do
    code=$(splash_get "/ocutalon/trace/$app/$page")
    if [ "$code" = 200 ] && grep -Eq 'name="?IRISPassword' "$tmp/splash.body" && ! grep -q '<app-root' "$tmp/splash.body" \
      && ! grep -q 'Try OcuTalon in two minutes' "$tmp/splash.body"; then
      pass "row 11: with no session the $app trace application's $page is IRIS's sign-in page (200, a password field, no app-root, not the splash)"
    else
      fail "row 11: with no session the $app trace application's $page gives status '$code', not IRIS's sign-in page"
    fi
  done
done

# --- Story 16.3: the visitor's own session (rows 4, 6, 12 and 14, and Task 0's MEASURED lines) ---

# set_cookie_value <headers file>: the value of the Set-Cookie of OcuTalonResume in the headers, or nothing. It is the resume reference:
# the caller keeps it in a variable and never prints it.
set_cookie_value() {
  tr -d '\r' < "$1" 2>/dev/null | grep -i '^set-cookie: OcuTalonResume=' | sed 's/^[^=]*=//; s/;.*//' | head -n 1
}

# set_cookie_shape <headers file>: the Set-Cookie line of OcuTalonResume with its value replaced, for the MEASURED lines.
set_cookie_shape() {
  tr -d '\r' < "$1" 2>/dev/null | grep -i '^set-cookie: OcuTalonResume=' | sed 's/^[^:]*: //; s/OcuTalonResume=[^;]*/OcuTalonResume=<value>/' | head -n 1
}

# page_outcome <body file>: shell (the application), refused (the splash with the address-limit error) or other.
page_outcome() {
  if grep -q '<app-root' "$1"; then
    printf shell
  elif grep -q 'Too many new sessions from your network this hour' "$1"; then
    printf limit
  else
    printf other
  fi
}

# jar_epoch <jar>: the epoch of /state for the jar's session, or nothing. The jar is signed out by the caller.
jar_epoch() {
  next_probe
  curl -s --max-time 30 -b "$1" -c "$1" "$base/ocutalon/api/v1/state?probe=$probes" | sed -n 's/.*"epoch":"\([^"]*\)".*/\1/p' | head -n 1
}

# row_field <epoch> <property>: a property of the Session row of the epoch (an epoch is base64url, so it is safe in a literal).
row_field() {
  printf '%s\n' \
    "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?\",\"$1\")" \
    "Set v=\"\" While rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get(\"ID\")) If \$IsObject(r),r.Epoch=\"$1\" { Set v=\$Property(r,\"$2\") Quit } }" \
    'Write !,"CHK|field|",v' \
    'Halt' | session_value OCUTALON field
}

# session_rows: the number of Session rows (counter_rows is lib-online.sh's).
session_rows() {
  printf '%s\n' 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Session") Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' 'Halt' | session_value OCUTALON rows
}

# --- row 14 (live): the seeded address limit ---

check_session "row 14: after the flag-on start the address limit's setting row exists and reads 5" OCUTALON \
  "CHK|limit|5|1" \
  'Write !,"CHK|limit|",##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY),"|",##class(OcuTalon.Data.Setting).KeyIndexExists(##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY)' \
  'Halt'

# --- row 12 (live, first phase): the proxy address is one that no request comes from, so every sign-in is exempt ---

a0=203.0.113.250
counter_before=$(counter_rows)
exempt_ok=0
for i in 1 2 3 4 5 6; do
  jar="$tmp/jar.exempt.$i"
  : > "$jar"
  code=$(online_signin "$jar" "$a0" "")
  outcome=$(page_outcome "$jar.b")
  if [ "$i" = 1 ]; then
    echo "MEASURED resume Set-Cookie attributes (the sign-in POST's answer): $(set_cookie_shape "$jar.h")"
    echo "MEASURED resume Set-Cookie attributes (the first /ocutalon/ GET after it): $(set_cookie_shape "$jar.g")"
  fi
  if [ "$outcome" = shell ] && [ -n "$(set_cookie_value "$jar.h")" ]; then exempt_ok=$((exempt_ok + 1)); fi
  logout_all "$jar" /ocutalon/
done
# The start, the splash checks and these exempt sign-ins make no key (Story 29.5): the counter makes it at its first counted sign-in.
check_session "row 12: the start, the splash checks and six exempt sign-ins made no address key" OCUTALON \
  "CHK|key|0" \
  'Set k=##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL Write !,"CHK|key|",$Data(@k)' \
  'Halt'
if [ "$exempt_ok" = 6 ] && [ "$(counter_rows)" = "$counter_before" ] && [ "$(counter_rows "$a0")" = 0 ]; then
  pass "row 12: six sign-ins from one forwarded address, not from the proxy, all give the shell and a cookie, and write no counter row"
else
  fail "row 12: of six exempt sign-ins $exempt_ok gave the shell and a cookie, and the counter holds '$(counter_rows "$a0")' row(s) for the address (before: '$counter_before', now '$(counter_rows)')"
fi

# --- row 4: the trace applications do not attach; the first /ocutalon request of the group's sign-in does ---

# console_lines: the number of OcuTalon.Web.SessionEvents lines in messages.log (OnLogin writes one for an attach that failed). The trace
# application's account has no write access to the private database, so an OnLogin that ran there would fail and write one.
console_lines() { dc exec -T iris grep -c 'OcuTalon.Web.SessionEvents: ' "$mgr/messages.log" 2>/dev/null | tr -d '\r'; }
jar="$tmp/jar.trace"
: > "$jar"
rows_before=$(session_rows)
lines_before=$(console_lines)
next_probe
trace_url="$base/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?probe=$probes"
token=$(page_token "$jar" "$trace_url")
if [ -z "$token" ]; then
  fail "row 4: the trace application's sign-in page gave no session token"
else
  next_probe
  curl -s --max-time 30 -D "$jar.h" -o /dev/null -c "$jar" -b "$jar" --data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$demo_user" \
    --data-urlencode "IRISPassword=$demo_password" --data-urlencode 'IRISLogin=Login' "$base/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?probe=$probes"
  rows_after_trace=$(session_rows)
  lines_after_trace=$(console_lines)
  trace_cookie=$(set_cookie_value "$jar.h")
  next_probe
  curl -s --max-time 30 -D "$jar.g" -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/?probe=$probes"
  rows_after_shell=$(session_rows)
  shell_cookie=$(set_cookie_value "$jar.g")
  echo "MEASURED resume Set-Cookie attributes (the group-carried first /ocutalon/ GET): $(set_cookie_shape "$jar.g")"
  if [ -z "$trace_cookie" ] && [ "$rows_after_trace" = "$rows_before" ] && [ "$lines_after_trace" = "$lines_before" ] && [ -n "$shell_cookie" ] && [ "$rows_after_shell" = $((rows_before + 1)) ]; then
    pass "row 4: the trace application's sign-in runs no OnLogin (no console log line), sets no resume cookie and creates no Session row; the jar's first /ocutalon/ request sets it and creates one"
  else
    fail "row 4: after the trace sign-in the cookie is '${trace_cookie:+set}', the rows $rows_before to $rows_after_trace and the console log's OnLogin lines $lines_before to $lines_after_trace; after /ocutalon/ the cookie is '${shell_cookie:+set}' and the rows $rows_after_shell (wanted none, equal, set, +1)"
  fi
fi
logout_all "$jar" /ocutalon/trace/ocutalon/

# --- row 6 and Task 0 (d): a real message, a resume with the cookie, and the reference kept out of every record ---

jar="$tmp/jar.row6"
: > "$jar"
online_signin "$jar" "" "" > /dev/null
resume_ref=$(set_cookie_value "$jar.h")
epoch_one=$(jar_epoch "$jar")
csp_one=$(row_field "$epoch_one" CspSessionId)
if [ -z "$resume_ref" ] || [ -z "$epoch_one" ]; then
  fail "row 6: the sign-in gave no resume cookie ('${resume_ref:+set}') or no epoch ('$epoch_one')"
  logout_all "$jar" /ocutalon/
else
  client_id="zz-row6-$(date +%s)"
  next_probe
  posted=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" \
    --data "{\"clientId\":\"$client_id\",\"text\":\"zz row six\",\"fromGuide\":false}" "$base/ocutalon/api/v1/messages?probe=$probes")
  turn_done=0
  for _ in $(seq 1 40); do
    next_probe
    if curl -s --max-time 30 -b "$jar" -c "$jar" "$base/ocutalon/api/v1/state?probe=$probes" | node -e 'let d = ""; process.stdin.on("data", (c) => (d += c)).on("end", () => { try { process.exit(JSON.parse(d).chat.some((i) => i.payload && i.payload.clientId === process.argv[1] && i.payload.state === "done") ? 0 : 1); } catch { process.exit(1); } });' "$client_id"; then
      turn_done=1
      break
    fi
    sleep 2
  done
  if [ "$posted" = 202 ] && [ "$turn_done" = 1 ]; then
    pass "row 6: a message was posted (202) and its turn is done, so a production message of the session exists"
  else
    fail "row 6: the message post gave '$posted' and its turn done is '$turn_done'"
  fi
  logout_all "$jar" /ocutalon/
  code=$(online_signin "$jar" "" "$resume_ref")
  epoch_two=$(jar_epoch "$jar")
  csp_two=$(row_field "$epoch_one" CspSessionId)
  if [ "$epoch_two" = "$epoch_one" ] && [ -z "$(set_cookie_value "$jar.h")" ]; then
    pass "row 6: signing in again with the cookie resumes the same session (the same epoch) and sets no new cookie"
  else
    fail "row 6: signing in again with the cookie gave the epoch '$epoch_two' (wanted '$epoch_one') or set a cookie"
  fi
  echo "MEASURED CSP session id reused on resume: $([ -n "$csp_one" ] && [ "$csp_one" = "$csp_two" ] && echo yes || echo no)"
  logout_all "$jar" /ocutalon/
fi

# --- (QA) row 5 over HTTP: tampered and malformed cookies never resume and never fail ---

if [ -z "$resume_ref" ] || [ -z "$epoch_one" ]; then
  fail "row 5 (QA): row 6 kept no resume reference or epoch, so the tampered cookies have nothing to be tampered from"
else
  swap=A
  if [ "${resume_ref:0:1}" = A ]; then swap=B; fi
  upper=$(printf '%s' "$resume_ref" | tr 'a-z' 'A-Z')
  tamper_values=("${swap}${resume_ref:1}" "${resume_ref}=" "${resume_ref}x" "${resume_ref:0:21}" "${resume_ref:1}" "${resume_ref:0:20}+/" "${resume_ref:0:21}!" "${resume_ref}%0A"
    "${resume_ref:0:20}%C3%A9" "${resume_ref:0:20}$(printf '\303\251')" "$upper" "$(printf '!%.0s' $(seq 1 22))" "$(printf 'A%.0s' $(seq 1 2000))")
  tamper_lines_before=$(console_lines)
  tamper_n=0
  tamper_good=0
  tamper_bad=""
  for value in "${tamper_values[@]}"; do
    if [ "$value" = "$resume_ref" ]; then continue; fi
    tamper_n=$((tamper_n + 1))
    jar="$tmp/jar.tamper.$tamper_n"
    : > "$jar"
    code=$(online_signin "$jar" "" "$value")
    outcome=$(page_outcome "$jar.b")
    new_value=$(set_cookie_value "$jar.h")
    epoch=$(jar_epoch "$jar")
    if [ "$outcome" = shell ] && [ -n "$new_value" ] && [ "$new_value" != "$value" ] && [ "$new_value" != "$resume_ref" ] && [ -n "$epoch" ] && [ "$epoch" != "$epoch_one" ]; then
      tamper_good=$((tamper_good + 1))
    else
      tamper_bad="$tamper_bad $tamper_n:$code/$outcome"
    fi
    logout_all "$jar" /ocutalon/
  done
  if [ "$tamper_n" -ge 12 ] && [ "$tamper_good" = "$tamper_n" ]; then
    pass "row 5 (QA): $tamper_n tampered or malformed cookies each gave the shell, a new cookie and a new session"
  else
    fail "row 5 (QA): of $tamper_n tampered or malformed cookies $tamper_good gave the shell, a new cookie and a new session (the others, as n:status/page:$tamper_bad)"
  fi
  if [ "$(console_lines)" = "$tamper_lines_before" ]; then
    pass "row 5 (QA): none of them wrote an OcuTalon.Web.SessionEvents line to messages.log"
  else
    fail "row 5 (QA): the tampered cookies wrote OcuTalon.Web.SessionEvents lines to messages.log ($tamper_lines_before to $(console_lines))"
  fi
  jar="$tmp/jar.tamper.back"
  : > "$jar"
  online_signin "$jar" "" "$resume_ref" > /dev/null
  if [ "$(jar_epoch "$jar")" = "$epoch_one" ] && [ -z "$(set_cookie_value "$jar.h")" ]; then
    pass "row 5 (QA): after them the real reference still resumes its own session and sets no cookie"
  else
    fail "row 5 (QA): after the tampered cookies the real reference no longer resumes its own session, or sets a cookie"
  fi
  logout_all "$jar" /ocutalon/
fi

# --- rows 7 to 12: the browser ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed step can echo what was typed: every password is replaced before anything reaches
# the terminal.
show_log() { tail -n "$1" "$e2e_log" | redact | sed 's/^/  /'; }
# run_e2e <spec file or nothing>: the online-demo project's run, with the stack's start values, into $e2e_log. The caller's own variables
# (OCUTALON_ONLINE_PROXIED, OCUTALON_ONLINE_LIMIT_ADDRESS) pass through; the global timeout is what is left of the deadline minus 20 s.
run_e2e() {
  local left=$((deadline - SECONDS))
  OCUTALON_URL="$base" \
    OCUTALON_DEMOACCOUNT_USER="$demo_user" \
    OCUTALON_DEMOACCOUNT_PASSWORD="$demo_password" \
    OCUTALON_READONLYACCOUNT_USER="$readonly_user" \
    OCUTALON_READONLYACCOUNT_PASSWORD="$readonly_password" \
    OCUTALON_E2E_IRIS_CONTAINER="$cid" \
    OCUTALON_E2E_TIMEOUT_MS=$(((left - 20) * 1000)) \
    npm --prefix web run e2e:online-demo -- "$@" > "$e2e_log" 2>&1
}
browser_started=$SECONDS
run_e2e
e2e_status=$?
echo "MEASURED Story 16.8 Task 0 (d): the browser step took $((SECONDS - browser_started)) s; the unit has run $SECONDS s at this point (DW-220: 310 to 325 s for the whole unit before this story)"
if [ "$e2e_status" -eq 0 ]; then
  show_log 20
  pass "rows 7 to 12: the specs of the online-demo project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  a browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 7 to 12: the specs of the online-demo project failed (exit $e2e_status)"
fi
grep -h '^MEASURED' "$e2e_log" | redact

# B1 lowers the connection cap and restores it: after the browser step the cap and the reserve are what the start gave. (Story 16.5)
browser_cap=$(printf '%s\n' 'Write !,"CHK|v|",##class(OcuTalon.Data.Public.Settings).Get("connectionCap")' 'Halt' | session_value OCUTALON v)
browser_reserve=$(printf '%s\n' 'Write !,"CHK|v|",##class(OcuTalon.Data.Public.Settings).Get("connectionReserve")' 'Halt' | session_value OCUTALON v)
if [ "$browser_cap" = 8 ] && [ "$browser_reserve" = 2 ]; then
  pass "Story 16.5: after the browser step the connection cap reads 8 and the reserve 2"
else
  printf '%s\n' 'Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap","8")' 'Do ##class(OcuTalon.Data.Public.Settings).Set("connectionReserve","2")' 'Halt' | session_value OCUTALON none > /dev/null
  fail "Story 16.5: after the browser step the connection cap read '$browser_cap' and the reserve '$browser_reserve' (wanted 8 and 2); both were put back"
fi

# --- Story 16.3, the proxied phase (rows 10 and 11, Task 0 (c)) ---

host_ip=$(host_address)
echo "MEASURED REMOTE_ADDR of the host's requests, derived from the container's default gateway: ${host_ip:-<none>}"
proxied_ok=0
if [ -n "$host_ip" ] && [ "$(set_proxy "$host_ip")" = "$host_ip" ]; then
  precondition="zz-phase2-precondition"
  jar="$tmp/jar.precondition"
  : > "$jar"
  # Row 12's lookups made a key: remove it, so that this counted sign-in is the first use (Story 29.5).
  check_session "phase 2: the key is removed before the first counted sign-in" OCUTALON \
    "CHK|key|0" \
    'Set k=##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL Kill @k Write !,"CHK|key|",$Data(@k)' \
    'Halt'
  online_signin "$jar" "$precondition" "" > /dev/null
  logout_all "$jar" /ocutalon/
  check_session "phase 2: the first counted sign-in made the key with the start's marker, and wrote no row under the plain SHA-256" OCUTALON \
    "CHK|key|1
CHK|marker|1
CHK|sha|0" \
    'Set k=##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL Write !,"CHK|key|",$Data(@k)' \
    'Set v=$Get(@k) Write !,"CHK|marker|",$ListValid(v)&&($ListLength(v)=2)&&($List(v,1)=##class(OcuTalon.Data.Public.Settings).Get("lastReset"))&&($Length($List(v,2))=32)' \
    "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?\",##class(OcuTalon.Data.Session).Hash(\"$precondition\")) Do rs.%Next() Write !,\"CHK|sha|\",rs.%GetData(1)" \
    'Halt'
  if [ "$(counter_rows "$precondition")" = 1 ]; then
    proxied_ok=1
    pass "phase 2: one proxied sign-in wrote a counter row for its forwarded address (the proxy address is $host_ip)"
  else
    fail "phase 2: a sign-in from $host_ip with X-Forwarded-For wrote no counter row, so $host_ip is not the address that IRIS sees for this host's requests"
  fi
else
  fail "phase 2: the host's address could not be derived ('${host_ip:-}') or the proxy address could not be set"
fi

if [ "$proxied_ok" = 1 ]; then
  # Row 10: five creations from address A, then a sixth, a cookie sign-in and a list that ends in C.
  addr_a=203.0.113.20
  addr_c=203.0.113.30
  first_ref=
  first_epoch=
  created=0
  for i in 1 2 3 4 5; do
    jar="$tmp/jar.limit.$i"
    : > "$jar"
    online_signin "$jar" "$addr_a" "" > /dev/null
    if [ "$(page_outcome "$jar.b")" = shell ] && [ -n "$(set_cookie_value "$jar.h")" ]; then created=$((created + 1)); fi
    if [ "$i" = 1 ]; then
      first_ref=$(set_cookie_value "$jar.h")
      first_epoch=$(jar_epoch "$jar")
    fi
    logout_all "$jar" /ocutalon/
  done
  # The first creation is aged to 50 minutes: the window is the past hour, so it still counts and the sixth is refused until ten minutes from now.
  aged=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT TOP 1 ID FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ? ORDER BY ID\",##class(OcuTalon.Data.AddressCounter).AddressHash(\"$addr_a\")) Set ok=0 If rs.%Next() { Set r=##class(OcuTalon.Data.AddressCounter).%OpenId(rs.%Get(\"ID\")) Set r.CreatedAt=##class(OcuTalon.Data.AddressCounter).Shift(##class(OcuTalon.Data.Time).NowUtc(),-3000) Set ok=\$SYSTEM.Status.IsOK(r.%Save()) } Write !,\"CHK|aged|\",ok" 'Halt' | session_value OCUTALON aged)
  rows_before=$(session_rows)
  jar="$tmp/jar.limit.6"
  : > "$jar"
  code=$(online_signin "$jar" "$addr_a" "")
  oldest=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT MIN(CreatedAt) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?\",##class(OcuTalon.Data.AddressCounter).AddressHash(\"$addr_a\")) Do rs.%Next() Write !,\"CHK|oldest|\",##class(OcuTalon.Data.AddressCounter).Shift(rs.%GetData(1),3600)" 'Halt' | session_value OCUTALON oldest)
  state_status=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" "$base/ocutalon/api/v1/state?probe=$(next_probe; echo "$probes")")
  refused_page=$(tr -d '\n' < "$jar.b")
  refused_ok=1
  [ "$code" = 200 ] || refused_ok=0
  [ "$(page_outcome "$jar.b")" = limit ] || refused_ok=0
  case $refused_page in *'<time class="tnum" id="ocu-error-time" datetime="'"$oldest"'"></time>.'*) ;; *) refused_ok=0 ;; esac
  case $refused_page in *aria-invalid*) refused_ok=0 ;; esac
  case $refused_page in *' disabled'*) refused_ok=0 ;; esac
  [ -z "$(set_cookie_value "$jar.h")" ] || refused_ok=0
  [ "$state_status" = 401 ] || refused_ok=0
  [ "$(session_rows)" = "$rows_before" ] || refused_ok=0
  logout_all "$jar" /ocutalon/
  if [ "$created" = 5 ] && [ "$refused_ok" = 1 ] && [ -n "$oldest" ] && [ "$aged" = 1 ]; then
    pass "row 10: five sign-ins from one forwarded address give the shell and a cookie each, and the sixth (the oldest creation aged to 50 minutes) gets 200 and the splash with the field error and the time of the oldest creation plus one hour, no marked field, no disabled button, no cookie, no session and no row"
  else
    fail "row 10: created=$created of 5, aged=$aged, the sixth: status '$code', outcome '$(page_outcome "$jar.b")', session state '$state_status', refused_ok=$refused_ok, oldest '$oldest'"
  fi
  jar="$tmp/jar.limit.resume"
  : > "$jar"
  online_signin "$jar" "$addr_a" "$first_ref" > /dev/null
  resumed_epoch=$(jar_epoch "$jar")
  logout_all "$jar" /ocutalon/
  if [ -n "$first_epoch" ] && [ "$resumed_epoch" = "$first_epoch" ] && [ "$(counter_rows "$addr_a")" = 5 ]; then
    pass "row 10: with the first session's cookie the sixth sign-in resumes it (the same epoch) and is not counted or refused"
  else
    fail "row 10: the cookie sign-in at the limit gave the epoch '$resumed_epoch' (wanted '$first_epoch'), and the address has '$(counter_rows "$addr_a")' counter rows"
  fi
  jar="$tmp/jar.limit.list"
  : > "$jar"
  online_signin "$jar" "$addr_a, $addr_c" "" > /dev/null
  list_outcome=$(page_outcome "$jar.b")
  logout_all "$jar" /ocutalon/
  if [ "$list_outcome" = shell ] && [ "$(counter_rows "$addr_c")" = 1 ] && [ "$(counter_rows "$addr_a")" = 5 ]; then
    pass "row 10: a forwarded list that ends in another address counts that address and is allowed; the first address still has exactly five counter rows"
  else
    fail "row 10: the list '$addr_a, $addr_c' gave '$list_outcome', C has '$(counter_rows "$addr_c")' counter row(s) and A has '$(counter_rows "$addr_a")'"
  fi

  # Row 11: the page, from address L of its own.
  remaining=$((deadline - SECONDS))
  if [ "$remaining" -lt 60 ]; then
    fail "row 11: only $remaining s are left of the deadline: too little for the proxied browser case"
  else
    limit_address=203.0.113.40
    OCUTALON_ONLINE_PROXIED=1 OCUTALON_ONLINE_LIMIT_ADDRESS="$limit_address" run_e2e address-limit.spec.ts
    limit_status=$?
    if [ "$limit_status" -eq 0 ] && grep -Eq '(^|[^0-9])1 passed' "$e2e_log" && ! grep -Eq '[0-9]+ skipped' "$e2e_log"; then
      show_log 12
      pass "row 11: the proxied browser case passes ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
    else
      show_log 60
      fail "row 11: the proxied browser case did not run and pass exactly once (exit $limit_status)"
    fi
  fi
fi

# --- Story 16.5: the busy states (rows 1, 2, 4, 5 and 6, and Task 0 (a) to (d)) ---

cap_start=8
reserve_start=2
busy_text="The demo is busy right now. Try again in a few minutes, or install it yourself."

# public_value <key>: a public setting's value. set_cap <value>: sets the public connection cap and prints what it reads back.
public_value() { printf '%s\n' "Write !,\"CHK|v|\",##class(OcuTalon.Data.Public.Settings).Get(\"$1\")" 'Halt' | session_value OCUTALON v; }
set_cap() { printf '%s\n' "Do ##class(OcuTalon.Data.Public.Settings).Set(\"connectionCap\",\"$1\")" 'Write !,"CHK|cap|",##class(OcuTalon.Data.Public.Settings).Get("connectionCap")' 'Halt' | session_value OCUTALON cap; }
# script_connections: InstanceConnections() as an iris_script reads it (its own process holds one connection).
script_connections() { printf '%s\n' 'Write !,"CHK|conn|",$SYSTEM.License.InstanceConnections()' 'Halt' | session_value OCUTALON conn; }
# http_view: the HTTP view of the licence connections, which is what the status counts, by the flip of Task 0 (a): with r what script_connections
# reads, the cap is set to r plus the reserve, and a busy status means the view is r; otherwise it is r - 1, which a cap of r - 1 plus the
# reserve must confirm. The cap is put back to what it was. It prints the view, or nothing when neither r nor r - 1 held.
http_view() {
  local r saved view=""
  saved=$(public_value connectionCap)
  r=$(script_connections)
  case $r in '' | *[!0-9]*) set_cap "$saved" > /dev/null; return 1 ;; esac
  set_cap "$((r + reserve_start))" > /dev/null
  if [ "$(status_read | cut -d' ' -f1)" = true ]; then
    view=$r
  else
    set_cap "$((r - 1 + reserve_start))" > /dev/null
    if [ "$(status_read | cut -d' ' -f1)" = true ]; then view=$((r - 1)); fi
  fi
  set_cap "$saved" > /dev/null
  printf '%s' "$view"
}
# drop_session <epoch>: removes the Session row of the epoch. drop_counter <address>: removes the address's counter rows.
drop_session() {
  [ -n "$1" ] || return 0
  printf '%s\n' \
    "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?\",\"$1\")" \
    "While rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get(\"ID\")) If \$IsObject(r),r.Epoch=\"$1\" { Do ##class(OcuTalon.Data.Session).%DeleteId(r.%Id()) } }" \
    'Write !,"CHK|dropped|1"' \
    'Halt' | session_value OCUTALON dropped > /dev/null
}
drop_counter() {
  printf '%s\n' "Do ##class(%SQL.Statement).%ExecDirect(,\"DELETE FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?\",##class(OcuTalon.Data.AddressCounter).AddressHash(\"$1\"))" 'Write !,"CHK|dropped|1"' 'Halt' | session_value OCUTALON dropped > /dev/null
}
# marker_in <headers file>: 1 when the headers hold X-OcuTalon-Busy: 1.
marker_in() { if tr -d '\r' < "$1" 2>/dev/null | grep -qi '^x-ocutalon-busy: 1$'; then printf 1; else printf none; fi; }
# busy_page <body file>: 1 when the page is the splash with the busy error: the text, then the README link, no marked field, no disabled button.
busy_page() {
  local page
  page=$(tr -d '\n' < "$1" 2>/dev/null)
  case $page in
    *'id="ocu-error"'*"$busy_text"' <a class="link" href="https://github.com/jbrandtmse/OcuTalon#readme" target="_blank" rel="noopener noreferrer">Install it yourself (README)<span class="sr-only"> (opens in a new tab)</span>'*) ;;
    *) printf 0; return ;;
  esac
  case $page in *aria-invalid* | *' disabled'*) printf 0; return ;; esac
  printf 1
}

busy_ok=0
if [ "$proxied_ok" = 1 ]; then
  remaining=$((deadline - SECONDS))
  if [ "$remaining" -lt 90 ]; then
    fail "Story 16.5: only $remaining s are left of the deadline: too little for the busy rows"
  else
    busy_ok=1
    # Task 0 (a): the baseline, with no session held by this test.
    script_base=$(script_connections)
    view_base=$(http_view)
    echo "MEASURED Task 0 (a): InstanceConnections() in an iris_script reads $script_base with no session; the HTTP view of the connections (the status's count) is ${view_base:-<unknown>}"
    if [ -z "$view_base" ]; then
      busy_ok=0
      fail "Story 16.5: the HTTP view of the connections could not be found by the flip (the script read '$script_base')"
    fi
  fi
fi
if [ "$busy_ok" = 1 ]; then
  # Task 0 (c) and row 4: five status GETs and five splash GETs, on no jar, leave the view unchanged.
  for i in 1 2 3 4 5; do
    status_read > /dev/null
    next_probe
    curl -s --max-time 30 -o /dev/null "$base/ocutalon/?probe=$probes"
  done
  view_pages=$(http_view)
  echo "MEASURED Task 0 (c): after 5 status GETs and 5 splash GETs with no jar kept the HTTP view of the connections is ${view_pages:-<unknown>} (before: $view_base)"
  if [ "$view_pages" = "$view_base" ]; then
    pass "row 4: five status GETs and five splash GETs leave the HTTP view of the connections at $view_base"
  else
    fail "row 4: the HTTP view of the connections was $view_base and is '${view_pages:-<unknown>}' after five status GETs and five splash GETs"
  fi

  # Task 0 (b): what a signed-in curl session does to the HTTP view of the connections. Measured on build 154 (Community key, the instance's
  # own web server): nothing. A CSP session is not counted in $SYSTEM.License.InstanceConnections(), so no sign-in can move the count to the
  # cap, and the rows below reach the boundary with the cap, set from the baseline, in place of a third or fourth session.
  addr_s1=203.0.113.51
  addr_s2=203.0.113.52
  addr_s3=203.0.113.53
  addr_s4=203.0.113.54
  addr_s5=203.0.113.55
  jar_s1="$tmp/jar.busy.s1"
  jar_s2="$tmp/jar.busy.s2"
  : > "$jar_s1"
  : > "$jar_s2"
  online_signin "$jar_s1" "$addr_s1" "" > /dev/null
  s1_outcome=$(page_outcome "$jar_s1.b")
  s1_epoch=$(jar_epoch "$jar_s1")
  script_one=$(script_connections)
  view_one=$(http_view)
  online_signin "$jar_s2" "$addr_s2" "" > /dev/null
  s2_outcome=$(page_outcome "$jar_s2.b")
  s2_cookie=$(set_cookie_value "$jar_s2.h")
  s2_epoch=$(jar_epoch "$jar_s2")
  script_two=$(script_connections)
  view_two=$(http_view)
  echo "MEASURED Task 0 (b): with one signed-in session InstanceConnections() reads $script_one in an iris_script and the HTTP view is ${view_one:-<unknown>}; with two it reads $script_two and ${view_two:-<unknown>} (baseline $script_base and $view_base)"
  if [ "$s1_outcome" = shell ] && [ "$s2_outcome" = shell ] && [ "$view_one" = "$view_base" ] && [ "$view_two" = "$view_base" ]; then
    pass "Task 0 (b): two signed-in sessions leave the HTTP view of the connections at $view_base: a CSP session is not counted (a change in IRIS's behaviour turns this red, and rows 1, 5 and 6 then need the sessions' own count)"
  else
    fail "Task 0 (b): the sign-ins gave '$s1_outcome' and '$s2_outcome'; the view was $view_base without a session, '${view_one:-<unknown>}' with one and '${view_two:-<unknown>}' with two"
  fi

  # Rows 1 and 2, with S1 and S2 signed in: the cap one above the baseline plus the reserve is not busy; at the baseline plus the reserve the
  # connections have reached cap minus reserve, so the status is busy, with the marker and the status 200, and the splash shows the busy error.
  cap_free=$((view_base + reserve_start + 1))
  cap_busy=$((view_base + reserve_start))
  if [ "$(set_cap "$cap_free")" != "$cap_free" ]; then
    fail "Story 16.5: the connection cap could not be set to $cap_free"
  else
    reading_free=$(status_read)
    set_cap "$cap_busy" > /dev/null
    reading_busy=$(status_read)
    if [ "$reading_free" = "false none 200" ] && [ "$reading_busy" = "true 1 200" ]; then
      pass "row 1: with S1 and S2 signed in, a cap of the baseline plus the reserve plus 1 gives a status that is not busy and has no X-OcuTalon-Busy header, and the baseline plus the reserve gives busy with the header and status 200"
    else
      fail "row 1: the status with the cap at $cap_free reads '$reading_free' (wanted 'false none 200'), and at $cap_busy '$reading_busy' (wanted 'true 1 200')"
    fi
    splash_code=$(splash_get /ocutalon/)
    splash_page=$(tr -d '\n' < "$tmp/splash.body")
    splash_marker=$(marker_in "$tmp/splash.headers")
    splash_focus=$(printf '%s' "$splash_page" | grep -o 'autofocus' | wc -l | tr -d ' ')
    splash_policy=$(splash_envelope)
    splash_policy=${splash_policy%% *}
    if [ "$splash_code" = 200 ] && [ "$(busy_page "$tmp/splash.body")" = 1 ] && [ "$splash_marker" = 1 ] && [ "$splash_focus" = 1 ] && [ "$splash_policy" = ok ]; then
      case $splash_page in
        *'value="'"$demo_user"'"'*) pass "row 2: while busy the splash shows the busy text and the README link under the button (no marked field, no disabled button, one autofocus, the published values), with the splash's exact policy and the X-OcuTalon-Busy header" ;;
        *) fail "row 2: while busy the splash does not hold the published user name" ;;
      esac
    else
      fail "row 2: while busy the splash gave status '$splash_code', busy page '$(busy_page "$tmp/splash.body")', header '$splash_marker', autofocus '$splash_focus', envelope '$splash_policy'"
    fi

    # Row 2, not busy: with the cap one higher a fresh splash shows no busy error and carries no marker header.
    set_cap "$cap_free" > /dev/null
    free_code=$(splash_get /ocutalon/)
    free_error=$(grep -c 'id="ocu-error"' "$tmp/splash.body")
    free_text=$(grep -cF "$busy_text" "$tmp/splash.body")
    free_marker=$(marker_in "$tmp/splash.headers")
    if [ "$free_code" = 200 ] && [ "$free_error" = 0 ] && [ "$free_text" = 0 ] && [ "$free_marker" = none ]; then
      pass "row 2: with a place free the splash shows no busy error (no #ocu-error, no busy text) and carries no X-OcuTalon-Busy header"
    else
      fail "row 2: with the cap at $cap_free the splash gave status '$free_code', #ocu-error $free_error, busy text $free_text, header '$free_marker' (wanted 200, 0, 0, none)"
    fi
    set_cap "$cap_busy" > /dev/null

    # Task 0 (f): whether the web gateway answers two GETs of one status URL, with the cap changed between them, differently.
    next_probe
    cache_url="$base/ocutalon/public/status?probe=cache$probes"
    set_cap "$cap_busy" > /dev/null
    cache_first=$(curl -s --max-time 30 "$cache_url")
    set_cap "$cap_free" > /dev/null
    cache_second=$(curl -s --max-time 30 "$cache_url")
    set_cap "$cap_busy" > /dev/null
    cache_busy_of() { case $1 in *'"busy":true'*) printf true ;; *'"busy":false'*) printf false ;; *) printf unreadable ;; esac; }
    echo "MEASURED Task 0 (f): two GETs of one /ocutalon/public/status URL with the cap changed between them answered busy=$(cache_busy_of "$cache_first") and then busy=$(cache_busy_of "$cache_second") (the gateway $([ "$cache_first" = "$cache_second" ] && echo 'repeated the first answer' || echo 'did not cache'))"

    # Rows 5 and 6, at the status's own boundary (OWNCONNECTIONS = 0: the new session holds no connection, so the check leaves none out):
    # with the cap at cap_busy the status is busy, so a proxied sign-in (S3), and one with a valid resume cookie of S2's row (S4), are
    # refused with the busy splash.
    own=$(printf '%s\n' 'Write !,"CHK|own|",##class(OcuTalon.Web.SessionEvents).#OWNCONNECTIONS' 'Halt' | session_value OCUTALON own)
    conn_before_s3=$(script_connections)
    rows_before=$(session_rows)
    csp_before=$(row_field "$s2_epoch" CspSessionId)
    jar_s3="$tmp/jar.busy.s3"
    : > "$jar_s3"
    s3_code=$(online_signin "$jar_s3" "$addr_s3" "")
    s3_state=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar_s3" -c "$jar_s3" "$base/ocutalon/api/v1/state?probe=$(next_probe; echo "$probes")")
    s3_ok=1
    s3_why=""
    [ "$s3_code" = 200 ] || { s3_ok=0; s3_why="$s3_why status"; }
    [ "$(busy_page "$jar_s3.b")" = 1 ] || { s3_ok=0; s3_why="$s3_why page"; }
    [ "$(marker_in "$jar_s3.h")" = 1 ] || { s3_ok=0; s3_why="$s3_why header"; }
    [ -z "$(set_cookie_value "$jar_s3.h")" ] || { s3_ok=0; s3_why="$s3_why cookie-post"; }
    [ -z "$(set_cookie_value "$jar_s3.g")" ] || { s3_ok=0; s3_why="$s3_why cookie-get"; }
    [ "$s3_state" = 401 ] || { s3_ok=0; s3_why="$s3_why state"; }
    [ "$(session_rows)" = "$rows_before" ] || { s3_ok=0; s3_why="$s3_why rows"; }
    [ "$(counter_rows "$addr_s3")" = 0 ] || { s3_ok=0; s3_why="$s3_why counter"; }
    logout_all "$jar_s3" /ocutalon/
    [ -n "$s2_cookie" ] || { s4_cookie_missing=1; }
    jar_s4="$tmp/jar.busy.s4"
    : > "$jar_s4"
    s4_code=$(online_signin "$jar_s4" "$addr_s4" "$s2_cookie")
    s4_ok=1
    s4_why=""
    [ -z "${s4_cookie_missing:-}" ] || { s4_ok=0; s4_why="$s4_why no-resume-cookie-from-S2"; }
    [ "$s4_code" = 200 ] || { s4_ok=0; s4_why="$s4_why status"; }
    [ "$(busy_page "$jar_s4.b")" = 1 ] || { s4_ok=0; s4_why="$s4_why page"; }
    [ "$(marker_in "$jar_s4.h")" = 1 ] || { s4_ok=0; s4_why="$s4_why header"; }
    [ -z "$(set_cookie_value "$jar_s4.h")" ] || { s4_ok=0; s4_why="$s4_why cookie"; }
    [ "$(row_field "$s2_epoch" CspSessionId)" = "$csp_before" ] || { s4_ok=0; s4_why="$s4_why attached"; }
    [ "$(session_rows)" = "$rows_before" ] || { s4_ok=0; s4_why="$s4_why rows"; }
    [ "$(counter_rows "$addr_s4")" = 0 ] || { s4_ok=0; s4_why="$s4_why counter"; }
    logout_all "$jar_s4" /ocutalon/
    if [ "$s3_ok" = 1 ] && [ "$s4_ok" = 1 ]; then
      pass "row 5: with the status busy (the cap at the baseline plus the reserve) a proxied sign-in and a proxied sign-in with a valid resume cookie each get 200 and the busy splash with X-OcuTalon-Busy: 1, no resume cookie, no session, no new Session row, no counter row, and the cookie's row is not attached"
    else
      fail "row 5: S3 (status '$s3_code', session state '$s3_state') ok=$s3_ok, failed:${s3_why:- none}; the cookie sign-in (status '$s4_code') ok=$s4_ok, failed:${s4_why:- none}; the script read ${conn_before_s3:-<unknown>} connections before S3 (view $view_base)"
    fi

    # Row 6, one cap higher: the status is not busy, and a proxied sign-in is let in (the shell, a cookie and a counter row), so the
    # boundary is the status's own (OWNCONNECTIONS = 0, Task 0 (d)).
    set_cap "$cap_free" > /dev/null
    jar_s5="$tmp/jar.busy.s5"
    : > "$jar_s5"
    conn_before_s5=$(script_connections)
    online_signin "$jar_s5" "$addr_s5" "" > /dev/null
    s5_outcome=$(page_outcome "$jar_s5.b")
    s5_cookie=$(set_cookie_value "$jar_s5.h")
    s5_epoch=$(jar_epoch "$jar_s5")
    s5_counter=$(counter_rows "$addr_s5")
    logout_all "$jar_s5" /ocutalon/
    if [ "$s3_ok" = 1 ] && [ "$s5_outcome" = shell ] && [ -n "$s5_cookie" ] && [ "$s5_counter" = 1 ]; then
      pass "row 6: the boundary is the status's own (the check leaves out no own connection, OWNCONNECTIONS = $own): refused with the status busy at the cap $cap_busy, and with the cap $cap_free a proxied sign-in is let in (the shell, a cookie, one counter row)"
    else
      fail "row 6: the sign-in past the boundary was refused=$s3_ok, and with the cap at $cap_free a proxied sign-in gave '$s5_outcome' with cookie '${s5_cookie:+set}' and $s5_counter counter row(s) (view $view_base, OWNCONNECTIONS $own, the script read ${conn_before_s3:-<unknown>} before S3 and ${conn_before_s5:-<unknown>} before S5)"
    fi
    echo "MEASURED Task 0 (d): OWNCONNECTIONS = $own; with the view at $view_base the sign-in at cap $cap_busy was '$([ "${s3_ok:-0}" = 1 ] && echo refused || echo not-refused)' and the one at cap $cap_free gave '$s5_outcome'; two sessions add $((${view_two:-0} - ${view_base:-0})) to the HTTP view here, so a new session holds no connection when OnLogin runs"
    for epoch in "$s5_epoch"; do drop_session "$epoch"; done
  fi
  logout_all "$jar_s2" /ocutalon/
  logout_all "$jar_s1" /ocutalon/
  drop_session "$s1_epoch"
  drop_session "$s2_epoch"
  for a in "$addr_s1" "$addr_s2" "$addr_s3" "$addr_s4" "$addr_s5"; do drop_counter "$a"; done
fi

# The connection cap goes back to its start value, whatever the phase's checks found.
cap_read=$(set_cap "$cap_start")
if [ "$cap_read" = "$cap_start" ] && [ "$(public_value connectionReserve)" = "$reserve_start" ]; then
  pass "Story 16.5: the connection cap is back to $cap_start (the reserve reads $reserve_start)"
else
  fail "Story 16.5: the connection cap reads '$cap_read' after being put back to $cap_start, or the reserve is not $reserve_start"
fi

# The proxy address goes back to its start value, whatever the phase's checks found.
if [ "$(set_proxy "$proxy_start")" = "$proxy_start" ]; then
  pass "phase 2: the proxy address is back to its start value"
else
  fail "phase 2: the proxy address could not be put back to $proxy_start"
fi

# --- Story 16.6: the probe (rows 1 to 9, and Task 0 (a) to (f)) ---

# docker/probe.sh runs against this unit's own throwaway, directly (no request is proxied: the proxy address is back at its start value),
# with the demo account and its published password, a state folder of its own and two stub commands that append one line per call to one
# record file ("alert <outcome> <line>" or "reset"), so that the record shows the order of the calls. Nine runs on one state folder:
# P1 healthy, P2 wrong password, P3 online-demo flag "0", P4 cap lowered to the boundary, P5 Conversation disabled, P6 wrong password,
# P7 the daily-cap mock marker, P8 wrong password, P9 (Story 29.6) the runners' keys back at the placeholder, so the turn falls back with
# no_key. Every setting a run changes is put back at once and read back at the end of the phase; the runners' model keys, pointed at the
# mock key variable before P1, are put back and read back before P9 and again after the phase.
probe_started=$SECONDS
probe_state="$tmp/probe-state"
probe_record="$tmp/probe-record"
wrong_password=$(hexpw)
mkdir -p "$probe_state"
: > "$probe_record"
cat > "$tmp/probe-alert.sh" <<'EOF'
#!/bin/sh
echo "alert $1 $2" >> "$PROBE_TEST_RECORD"
EOF
cat > "$tmp/probe-reset.sh" <<'EOF'
#!/bin/sh
echo "reset" >> "$PROBE_TEST_RECORD"
EOF
chmod 755 "$tmp/probe-alert.sh" "$tmp/probe-reset.sh"

# probe_run <label> [VAR=value]...: one run of docker/probe.sh with this unit's configuration plus the overrides. It leaves the exit code in
# probe_rc, stdout in $tmp/probe.<label>.out and stderr in $tmp/probe.<label>.err. The passwords reach the probe through the environment
# of a subshell, so they are on no command line.
probe_run() {
  local label=$1 kv
  shift
  (
    export OCUTALON_PROBE_URL="$base" OCUTALON_DEMO_USER="$demo_user" OCUTALON_DEMO_PASSWORD="$demo_password"
    export OCUTALON_PROBE_ALERT_COMMAND="$tmp/probe-alert.sh" OCUTALON_PROBE_RESET_COMMAND="$tmp/probe-reset.sh"
    export OCUTALON_PROBE_STATE_DIR="$probe_state" PROBE_TEST_RECORD="$probe_record"
    for kv in "$@"; do export "$kv"; done
    exec bash "$root/docker/probe.sh"
  ) > "$tmp/probe.$label.out" 2> "$tmp/probe.$label.err" < /dev/null
  probe_rc=$?
}
# probe_expect <label> <label of the check> <exit> <text> [<story>]: the run's exit code, one stdout line that is also the log's last line,
# and the text after the time. The story named in the check's lines is 16.6 unless given.
probe_expect() {
  local out="$tmp/probe.$1.out" got last lines story=${5:-16.6}
  got=$(sed 's/^[^ ]* //' "$out")
  last=$(tail -n 1 "$probe_state/probe.log" 2> /dev/null)
  lines=$(wc -l < "$out" | tr -d ' ')
  if [ "$probe_rc" = "$3" ] && [ "$got" = "$4" ] && [ "$lines" = 1 ] && [ "$(cat "$out")" = "$last" ] && grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$out"; then
    pass "Story $story, $2: exit $3, the log's last line and stdout are '<time> $4'"
  else
    fail "Story $story, $2: exit $probe_rc (wanted $3), '$got' (wanted '$4'), $lines stdout line(s), the log's last line is '$(printf '%s' "$last" | sed 's/^[^ ]* //')'"
  fi
}
# probe_counts: "<alert lines> <reset lines>" of the command record so far.
probe_counts() { printf '%s %s' "$(grep -c '^alert ' "$probe_record")" "$(grep -c '^reset$' "$probe_record")"; }
# probe_calls_ok <check label> <alerts> <resets> [<story>]: the record holds this many alert and reset lines.
probe_calls_ok() {
  local story=${4:-16.6}
  if [ "$(probe_counts)" = "$2 $3" ]; then
    pass "Story $story, $1: the record holds $2 alert line(s) and $3 reset line(s)"
  else
    fail "Story $story, $1: the record holds '$(probe_counts)' alert and reset lines, wanted '$2 $3'"
  fi
}

# set_flag <0|1>: sets the public online-demo flag and prints what it reads back.
set_flag() { printf '%s\n' "Do ##class(OcuTalon.Data.Public.Settings).Set(\"onlineDemo\",\"$1\")" 'Write !,"CHK|flag|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' 'Halt' | session_value OCUTALON flag; }
# conversation_enabled <0|1>: puts the Conversation item in the wanted state (the director refuses to enable an enabled item, so it is
# called only when the item is in the other state) and prints "<status ok>,<enabled items>" as the director reads it back, with the first
# words of the error text after a third comma when the status is an error.
conversation_enabled() {
  printf '%s\n' 'Set sc=1 Set en=##class(Ens.Director).IsItemEnabled("Conversation",.st)' \
    "If en'=$1 { Set sc=##class(Ens.Director).EnableConfigItem(\"Conversation\",$1) Set en=##class(Ens.Director).IsItemEnabled(\"Conversation\",.st) }" \
    'Write !,"CHK|conv|",$SYSTEM.Status.IsOK(sc),",",en,$Select($SYSTEM.Status.IsOK(sc):"",1:","_$Extract($SYSTEM.Status.GetErrorText(sc),1,120))' 'Halt' | session_value OCUTALON conv
}
# capped_mark: $Data of today's capped mark of the bridge. capped_unmark: removes it and prints $Data after.
capped_mark() { printf '%s\n' 'Write !,"CHK|mark|",$Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())))' 'Halt' | session_value OCUTALON mark; }
capped_unmark() { printf '%s\n' 'Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))' 'Write !,"CHK|mark|",$Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())))' 'Halt' | session_value OCUTALON mark; }
# session_newest: the highest Session row id. session_csp <id>: the CSP session id of a Session row. csp_alive <id>: 1 when %CSP.Session holds it.
session_newest() { printf '%s\n' 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT NVL(MAX(ID),0) FROM OcuTalon_Data.Session") Do rs.%Next() Write !,"CHK|newest|",rs.%GetData(1)' 'Halt' | session_value OCUTALON newest; }
session_csp() { printf '%s\n' "Set r=##class(OcuTalon.Data.Session).%OpenId(\"$1\") Write !,\"CHK|csp|\",\$Select(\$IsObject(r):r.CspSessionId,1:\"\")" 'Halt' | session_value OCUTALON csp; }
csp_alive() { printf '%s\n' "Write !,\"CHK|alive|\",##class(%CSP.Session).%ExistsId(\"$1\")" 'Halt' | session_value %SYS alive; }
csp_gone() { [ "$(csp_alive "$1")" = 0 ]; }

cat > "$tmp/turn-events.js" <<'EOF'
const fs = require("fs");
const [file, clientId] = process.argv.slice(2);
let body;
try { body = JSON.parse(fs.readFileSync(file, "utf8")); } catch { console.log("unreadable"); process.exit(0); }
const mine = (body.events || []).filter((e) => e.type === "chat.message" && e.payload && e.payload.clientId === clientId);
const done = mine.find((e) => e.payload.state === "done");
const reason = (o) => (o && "fallbackReason" in o ? (o.fallbackReason === "" ? "empty" : o.fallbackReason) : "absent");
const states = mine.filter((e) => e.payload.decision).map((e) => e.payload.state).join(",") || "none";
console.log(`${done ? "done" : "waiting"} decision-on=${states} chat.fallbackReason=${done ? reason(done.payload) : "n/a"} decision.fallbackReason=${done && done.payload.decision ? reason(done.payload.decision) : "n/a"}`);
EOF

# turn_events <message> <polls>: signs in as the demo account on a jar of its own, posts the message, polls the events up to <polls> times
# (2 s apart) until the turn is done, signs out, and prints "<POST status> <done or waiting> decision-on=<states of the turn's chat.message
# events that carry a decision> chat.fallbackReason=<..> decision.fallbackReason=<..>" (absent, empty or the value).
turn_events() {
  local jar client code n=0 verdict=""
  next_probe
  jar="$tmp/jar.turn.$probes"
  : > "$jar"
  online_signin "$jar" "" "" > /dev/null
  client="zz-turn-$(date +%s)-$probes"
  next_probe
  code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" \
    --data "{\"clientId\":\"$client\",\"text\":\"$1\",\"fromGuide\":false}" "$base/ocutalon/api/v1/messages?probe=$probes")
  while [ "$n" -lt "$2" ]; do
    n=$((n + 1))
    next_probe
    curl -s --max-time 30 -b "$jar" -c "$jar" "$base/ocutalon/api/v1/events?after=0&afterInstance=0&probe=$probes" > "$tmp/turn.events"
    verdict=$(node "$tmp/turn-events.js" "$tmp/turn.events" "$client")
    case $verdict in done*) break ;; esac
    sleep 2
  done
  logout_all "$jar" /ocutalon/
  printf '%s %s' "$code" "$verdict"
}

probe_ok=0
remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 150 ]; then
  fail "Story 16.6: only $remaining s are left of the deadline: too little for the probe phase"
else
  probe_ok=1
  flag_start=$(public_value onlineDemo)
  mark_before=$(capped_mark)
  conv_start=$(conversation_enabled 1)
  echo "MEASURED Task 0 (c): the Conversation item reads '$conv_start' (status ok, enabled items) before the phase"
  if [ "$flag_start" = 1 ] && [ "$(public_value connectionCap)" = "$cap_start" ] && [ "$conv_start" = "1,1" ] && case $mark_before in 0 | 1 | 10 | 11) true ;; *) false ;; esac; then
    pass "Story 16.6: the phase starts with the flag '1', the cap $cap_start, the Conversation item enabled and the day's capped mark read ('$mark_before')"
  else
    probe_ok=0
    fail "Story 16.6: the phase's start values are not the flag '1', the cap $cap_start, Conversation enabled and a read of the capped mark (flag '$flag_start', cap '$(public_value connectionCap)', Conversation '$conv_start', mark '$mark_before')"
  fi
fi
keys_attempted=0
if [ "$probe_ok" = 1 ]; then
  keys_attempted=1
  if [ "$(keys_point)" = 1 ]; then
    pass "Story 16.6: the runners' model keys point at the mock key variable and the runners have recorded it (a healthy turn reaches the mock)"
  else
    probe_ok=0
    fail "Story 16.6: the runners' model keys could not be pointed at the mock key variable"
  fi
fi

if [ "$probe_ok" = 1 ]; then
  # Task 0 (e): the splash GET's cookie, and whether the sign-in POST carries it (counted from curl's request headers; no value is printed).
  jar_e="$tmp/jar.splashcookie"
  : > "$jar_e"
  next_probe
  curl -s --max-time 30 -c "$jar_e" -b "$jar_e" -D "$tmp/splash-e.h" -o /dev/null "$base/ocutalon/?probe=$probes"
  e_set=$(tr -d '\r' < "$tmp/splash-e.h" | grep -ci '^set-cookie: CSPSESSIONID')
  next_probe
  curl -sv --max-time 30 -c "$jar_e" -b "$jar_e" -D "$tmp/signin-e.h" -o /dev/null --data-urlencode "IRISUsername=$demo_user" --data-urlencode "IRISPassword=$demo_password" \
    --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/?probe=$probes" 2> "$tmp/signin-e.v"
  e_carried=$(grep -ci '^> cookie: .*CSPSESSIONID' "$tmp/signin-e.v")
  e_reset=$(tr -d '\r' < "$tmp/signin-e.h" | grep -ci '^set-cookie: CSPSESSIONID')
  logout_all "$jar_e" /ocutalon/
  echo "MEASURED Task 0 (e): the splash GET sets $e_set CSP session cookie(s); the sign-in POST carries one: $([ "$e_carried" -ge 1 ] && echo yes || echo no); the POST sets $e_reset"

  # Task 0 (d), the control: a session signed in with online_signin has a live %CSP.Session for its row, and none after logout_all.
  jar_c="$tmp/jar.control"
  : > "$jar_c"
  online_signin "$jar_c" "" "" > /dev/null
  control_epoch=$(jar_epoch "$jar_c")
  control_csp=$(row_field "$control_epoch" CspSessionId)
  control_before=$([ -n "$control_csp" ] && csp_alive "$control_csp")
  logout_all "$jar_c" /ocutalon/
  control_gone_after=0
  if [ -n "$control_csp" ] && wait_until 9 csp_gone "$control_csp"; then control_gone_after=1; fi
  echo "MEASURED Task 0 (d): control session: CspSessionId read '$([ -n "$control_csp" ] && echo yes || echo no)', alive before the sign-out '${control_before:-?}', gone after logout_all '$control_gone_after'"
  if [ "$control_before" = 1 ] && [ "$control_gone_after" = 1 ]; then
    pass "Story 16.6, Task 0 (d): a session signed in with online_signin has a live CSP session, and logout_all ends it"
  else
    fail "Story 16.6, Task 0 (d): the control session's CSP session was not alive before ('${control_before:-?}') and gone after ('$control_gone_after') its sign-out, so row 1's read proves nothing"
  fi
  drop_session "$control_epoch"

  # Task 0 (a): a healthy turn's events, read by a session of this test.
  echo "MEASURED Task 0 (a): $(turn_events 'zz measure healthy turn' 40)"

  counter_phase_before=$(counter_rows)

  # P1, row 1: healthy.
  rows_before=$(session_rows)
  newest_before=$(session_newest)
  probe_run p1
  probe_expect p1 "row 1" 0 "healthy count=0"
  rows_after=$(session_rows)
  newest_after=$(session_newest)
  probe_calls_ok "row 1" 0 0
  if [ "$((rows_after - rows_before))" = 1 ] && [ "${newest_after:-0}" -gt "${newest_before:-0}" ]; then
    p1_csp=$(session_csp "$newest_after")
    if [ -n "$p1_csp" ]; then
      p1_gone=0
      if csp_gone "$p1_csp"; then p1_gone=1; elif wait_until 9 csp_gone "$p1_csp"; then p1_gone=2; fi
      echo "MEASURED Task 0 (d): P1's CSP session is gone $([ "$p1_gone" = 1 ] && echo 'right after the run' || { [ "$p1_gone" = 2 ] && echo 'within 9 s of the run' || echo 'NOT within 9 s'; })"
      if [ "$p1_gone" != 0 ]; then
        pass "Story 16.6, row 1: exactly one new Session row, and its CSP session no longer exists after the probe's sign-out"
      else
        fail "Story 16.6, row 1: the probe's CSP session still exists after its run (the sign-out did not end it)"
      fi
    else
      fail "Story 16.6, row 1: the new Session row has no CspSessionId"
    fi
  else
    fail "Story 16.6, row 1: the Session rows went from '$rows_before' to '$rows_after' (newest id '$newest_before' to '$newest_after'), wanted exactly one new row"
  fi

  # P2, row 2: a wrong password.
  rows_before=$(session_rows)
  probe_run p2 "OCUTALON_DEMO_PASSWORD=$wrong_password"
  probe_expect p2 "row 2" 1 "auth_failed count=1"
  probe_calls_ok "row 2" 1 0
  if [ "$(grep -c '^alert auth_failed ' "$probe_record")" = 1 ] && [ "$(session_rows)" = "$rows_before" ]; then
    pass "Story 16.6, row 2: one alert for auth_failed and no new Session row"
  else
    fail "Story 16.6, row 2: the alert is not one auth_failed line, or the Session rows changed from '$rows_before' to '$(session_rows)'"
  fi

  # P3, row 3: no splash (the online-demo flag "0").
  flag_read=$(set_flag 0)
  probe_run p3
  flag_back=$(set_flag "$flag_start")
  [ "$flag_read" = 0 ] || fail "Story 16.6, row 3: the flag could not be set to 0 (read '$flag_read')"
  probe_expect p3 "row 3" 1 "no_splash count=1"
  probe_calls_ok "row 3" 2 0
  if [ "$flag_back" = "$flag_start" ]; then
    pass "Story 16.6, row 3: the online-demo flag is back to '$flag_start'"
  else
    fail "Story 16.6, row 3: the online-demo flag reads '$flag_back' after being put back to '$flag_start'"
  fi

  # P4, row 4: busy (the cap at the HTTP view plus the reserve, Story 16.5's row 1 boundary).
  rows_before=$(session_rows)
  view=$(http_view)
  if [ -n "$view" ] && [ "$(set_cap "$((view + reserve_start))")" = "$((view + reserve_start))" ] && [ "$(status_read | cut -d' ' -f1)" = true ]; then
    probe_run p4
    set_cap "$cap_start" > /dev/null
    probe_expect p4 "row 4" 1 "busy count=1"
    probe_calls_ok "row 4" 3 0
    if [ "$(cat "$probe_state/busy-per-day" 2> /dev/null)" = "$(TZ=UTC0 date +%Y-%m-%d) 1" ] && [ "$(session_rows)" = "$rows_before" ]; then
      pass "Story 16.6, row 4: busy-per-day holds today's line with 1, and no Session row was added"
    else
      fail "Story 16.6, row 4: busy-per-day is '$(tr '\n' '|' < "$probe_state/busy-per-day" 2> /dev/null)' or the Session rows changed from '$rows_before' to '$(session_rows)'"
    fi
  else
    set_cap "$cap_start" > /dev/null
    fail "Story 16.6, row 4: the cap could not be set to the boundary (view '${view:-<unknown>}'), so the status was not busy"
  fi
  cap_back=$(public_value connectionCap)
  if [ "$cap_back" = "$cap_start" ]; then
    pass "Story 16.6, row 4: the connection cap is back to $cap_start"
  else
    set_cap "$cap_start" > /dev/null
    fail "Story 16.6, row 4: the connection cap read '$cap_back' after being put back to $cap_start"
  fi

  # P5, row 5: no decision (the Conversation item disabled), then the reset.
  conv_off=$(conversation_enabled 0)
  p5_post=$(turn_events 'zz measure disabled' 0)
  echo "MEASURED Task 0 (c): with the Conversation item disabled the director reads '$conv_off' (status ok, enabled items), and POST /messages answers ${p5_post%% *}"
  p5_newest_before=$(session_newest)
  probe_run p5 OCUTALON_PROBE_DECISION_WAIT=10
  p5_newest_after=$(session_newest)
  conv_on=$(conversation_enabled 1)
  probe_expect p5 "row 5" 1 "no_decision count=2 reset=0"
  if [ "$conv_off" = "1,0" ] && [ "$conv_on" = "1,1" ]; then
    pass "Story 16.6, row 5: the Conversation item was disabled ('$conv_off') and is enabled again ('$conv_on')"
  else
    fail "Story 16.6, row 5: the Conversation item reads '$conv_off' after being disabled and '$conv_on' after being enabled (wanted 1,0 and 1,1)"
  fi
  probe_calls_ok "row 5" 4 1
  # (QA) the sign-out on the decision-timeout path: the run's own Session row names a CSP session that no longer exists.
  p5_csp=""
  if [ "${p5_newest_after:-0}" -gt "${p5_newest_before:-0}" ]; then p5_csp=$(session_csp "$p5_newest_after"); fi
  if [ -n "$p5_csp" ] && { csp_gone "$p5_csp" || wait_until 9 csp_gone "$p5_csp"; }; then
    pass "Story 16.6, row 5 (QA): the run that waited out its decision signed out, and its CSP session no longer exists"
  else
    fail "Story 16.6, row 5 (QA): the no_decision run's CSP session '${p5_csp:-<none; newest id $p5_newest_before to $p5_newest_after>}' still exists after its run (no sign-out on the timeout path)"
  fi
  if [ "$(sed -n 4p "$probe_record")" = reset ] && [ "$(sed -n 5p "$probe_record" | cut -c1-18)" = "alert no_decision " ] && [ "$(cat "$probe_state/counted-failures" 2> /dev/null)" = 0 ]; then
    pass "Story 16.6, row 5: the reset line comes right before this run's alert line, and the stored count is 0"
  else
    fail "Story 16.6, row 5: the record's lines 4 and 5 are '$(sed -n 4p "$probe_record")' and '$(sed -n 5p "$probe_record" | cut -c1-30)', the stored count '$(cat "$probe_state/counted-failures" 2> /dev/null)'"
  fi

  # P6, row 6: the count starts again.
  probe_run p6 "OCUTALON_DEMO_PASSWORD=$wrong_password"
  probe_expect p6 "row 6" 1 "auth_failed count=1"
  probe_calls_ok "row 6" 5 1

  # P7, row 7: capped (Lane A's daily-cap mock scenario answers the gateway's HTTP 403 "daily cost cap reached").
  probe_run p7 "OCUTALON_PROBE_MESSAGE=[[mock:daily-cap]] probe capped check"
  mark_after=$(capped_mark)
  probe_expect p7 "row 7" 0 "capped count=0 fallback=daily_cap"
  probe_calls_ok "row 7" 5 1
  mark_removed=""
  if [ "$mark_before" = 0 ]; then mark_removed=$(capped_unmark); fi
  echo "MEASURED Task 0 (b): the capped run's done decision carries fallbackReason daily_cap (the log line says so); the day's mark reads $mark_after after it (before: $mark_before) and ${mark_removed:-<kept>} after the removal"
  if [ "$mark_before" != 0 ]; then
    pass "Story 16.6, row 7: the day's capped mark existed before the phase and is kept"
  elif [ "$mark_after" != 0 ] && [ "$mark_removed" = 0 ]; then
    pass "Story 16.6, row 7: the capped run marked the day, and the removal clears the mark"
  else
    fail "Story 16.6, row 7: the day's capped mark reads '$mark_after' after the run and '$mark_removed' after its removal (wanted set, then 0)"
  fi

  # P8, row 8: the capped run cleared the count.
  probe_run p8 "OCUTALON_DEMO_PASSWORD=$wrong_password"
  probe_expect p8 "row 8" 1 "auth_failed count=1"
  probe_calls_ok "row 8" 6 1

  # P9 (Story 29.6, row 6): the runners' keys go back to the Provider step's placeholder, so the next turn is a no_key fallback, which the
  # probe reports as degraded: an alert, exit 1, and the count of counted failures (1 after P8) unchanged, with no reset.
  p9_keys=0
  if [ "$(keys_restore)" = 1 ]; then
    p9_keys=1
    pass "Story 29.6, row 6: the runners' model keys are back to the Provider step's placeholder before P9"
  else
    fail "Story 29.6, row 6: the runners' model keys could not be put back to the placeholder, so P9 is not run"
  fi
  if [ "$p9_keys" = 1 ]; then
    probe_run p9
    probe_expect p9 "row 6" 1 "degraded count=1 fallback=no_key" 29.6
    probe_calls_ok "row 6" 7 1 29.6
    if [ "$(cat "$probe_state/counted-failures" 2> /dev/null)" = 1 ]; then
      pass "Story 29.6, row 6: degraded left the stored count at 1"
    else
      fail "Story 29.6, row 6: the stored count reads '$(cat "$probe_state/counted-failures" 2> /dev/null)' after degraded (wanted 1)"
    fi
  fi

  # Row 9: the phase as a whole.
  if [ "$(sed 's/^[^ ]* //; s/ .*//' "$probe_state/probe.log" | tr '\n' ' ')" = "healthy auth_failed no_splash busy no_decision auth_failed capped auth_failed degraded " ]; then
    pass "Story 16.6, row 9: probe.log holds exactly nine lines: healthy, auth_failed, no_splash, busy, no_decision, auth_failed, capped, auth_failed, degraded"
  else
    fail "Story 16.6, row 9: probe.log's outcomes are '$(sed 's/^[^ ]* //; s/ .*//' "$probe_state/probe.log" | tr '\n' ' ')'"
  fi
  : > "$tmp/probe-expected"
  for label in p2 p3 p4 p5 p6 p8 p9; do
    if [ "$label" = p5 ]; then echo reset >> "$tmp/probe-expected"; fi
    printf 'alert %s %s\n' "$(sed 's/^[^ ]* //; s/ .*//' "$tmp/probe.$label.out")" "$(cat "$tmp/probe.$label.out")" >> "$tmp/probe-expected"
  done
  if cmp -s "$tmp/probe-expected" "$probe_record"; then
    pass "Story 16.6, row 9: the record holds seven alert lines (each with its outcome and its run's line) and one reset line, in the order of the runs"
  else
    fail "Story 16.6, row 9: the command record is not the seven alerts and the one reset of the runs ($(grep -c '^alert ' "$probe_record") alert, $(grep -c '^reset$' "$probe_record") reset line(s))"
  fi
  counter_phase_after=$(counter_rows)
  if [ "$counter_phase_after" = "$counter_phase_before" ]; then
    pass "Story 16.6, row 9: the AddressCounter row count is unchanged ($counter_phase_after): the probe is exempt"
  else
    fail "Story 16.6, row 9: the AddressCounter rows went from '$counter_phase_before' to '$counter_phase_after'"
  fi
  leaks=0
  for secret in "$demo_password" "$wrong_password"; do
    leaks=$((leaks + $(cat "$tmp"/probe.p*.out "$tmp"/probe.p*.err "$probe_state"/* "$probe_record" | grep -cF -e "$secret")))
  done
  if [ "$leaks" = 0 ]; then
    pass "Story 16.6, row 9: neither the published nor the wrong password is in the probe's stdout, stderr, state files or record"
  else
    fail "Story 16.6, row 9: a password is in $leaks line(s) of the probe's output, state files or record"
  fi
  if [ "$(ls -A "$probe_state" | tr '\n' ' ')" = "busy-per-day counted-failures probe.log " ]; then
    pass "Story 16.6, row 9: the state folder holds only busy-per-day, counted-failures and probe.log (no cookie jar, no resume reference)"
  else
    fail "Story 16.6, row 9: the state folder holds '$(ls -A "$probe_state" | tr '\n' ' ')'"
  fi

  # The settings the phase changed, read back.
  restored_flag=$(public_value onlineDemo)
  restored_cap=$(public_value connectionCap)
  restored_conv=$(conversation_enabled 1)
  restored_mark=$(capped_mark)
  if [ "$restored_flag" = "$flag_start" ] && [ "$restored_cap" = "$cap_start" ] && [ "$restored_conv" = "1,1" ] && { [ "$mark_before" != 0 ] || [ "$restored_mark" = 0 ]; }; then
    pass "Story 16.6, row 9: the flag '$restored_flag', the cap $restored_cap, the Conversation item ('$restored_conv') and the day's capped mark ('$restored_mark') are as before the phase"
  else
    if [ "$mark_before" = 0 ]; then capped_unmark > /dev/null; fi
    set_flag "$flag_start" > /dev/null
    set_cap "$cap_start" > /dev/null
    fail "Story 16.6, row 9: after the phase the flag reads '$restored_flag', the cap '$restored_cap', the Conversation item '$restored_conv' and the capped mark '$restored_mark' (before: '$flag_start', $cap_start, enabled, '$mark_before')"
  fi
fi
if [ "$keys_attempted" = 1 ]; then
  if [ "$(keys_restore)" = 1 ]; then
    pass "Story 16.6: the runners' model keys are back to the Provider step's placeholder"
  else
    fail "Story 16.6: the runners' model keys could not be put back to the Provider step's placeholder"
  fi
fi
echo "MEASURED Task 0 (f): the probe phase took $((SECONDS - probe_started)) s; the unit has run $SECONDS s at this point (deadline $((deadline - SECONDS)) s away)"

# --- Story 29.3: IRIS's own answers to the host check (release/demo-host-check.sh) ---

# The script and the stand-in of test-online-host.sh rely on what IRIS itself answers to the host check's requests. This section sends
# every item signed out with no proxy, each on a jar of its own ended with logout_all, prints one MEASURED line per item, and pins:
# (a) each host_probes line's <iris> (the status and whether the page holds an IRIS form field); (b) the static /csp/broker/ file the
# check reads, which a signed-in trace page loads and IRIS serves with 200; (c) the two dummy-value sign-in POSTs of the guard checks,
# which come back as IRIS's sign-in page (the splash's with aria-invalid). Each item signs out on its application (host_app, the
# script's mapping too). The probes stop at the unit's deadline.
host_started=$SECONDS

# host_send <target> [<curl argument>...]: one request signed out on a jar of its own, with a unique probe parameter and the path sent as
# is; leaves the status in host_code (000 for no answer) and the body in $tmp/host.body (empty for no answer), then ends the jar's sessions.
host_send() {
  local target=$1 jar sep='?'
  shift
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  : > "$tmp/host.body"
  case $target in *\?*) sep='&' ;; esac
  host_code=$(curl -s --max-time 30 --path-as-is -c "$jar" -b "$jar" -o "$tmp/host.body" -w '%{http_code}' ${1+"$@"} "$base$target${sep}probe=$probes" < /dev/null)
  logout_all "$jar" "$(host_app "$target")"
}

# host_form_flag: form when the last body holds an IRIS form field, otherwise noform.
host_form_flag() {
  if grep -Eq "$HOST_FORM_FIELD_RE" "$tmp/host.body"; then printf form; else printf noform; fi
}

# host_text: the last body as text, up to 600 characters: its style and script blocks and tags removed, white space squeezed.
host_text() {
  tr '\r\n' '  ' < "$tmp/host.body" | sed 's/<style[^>]*>[^<]*<\/style>//g; s/<script[^>]*>.*<\/script>//g; s/<[^>]*>/ /g' | tr -s ' \t' ' ' | head -c 600
}

host_lines=$(host_probes)
host_count=0
host_wrong=0
while IFS= read -r host_line; do
  [ -n "$host_line" ] || continue
  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "Story 29.3: the deadline passed after $host_count host_probes probes"
    break
  fi
  if ! host_probe_args "$host_line"; then
    fail "Story 29.3: the host_probes line '$host_line' cannot be built"
    host_wrong=$((host_wrong + 1))
    continue
  fi
  host_send "$probe_target" ${probe_args[@]+"${probe_args[@]}"}
  host_got="$host_code:$(host_form_flag)"
  echo "MEASURED host probe $probe_id $probe_method $host_got"
  host_count=$((host_count + 1))
  if [ "$host_got" != "$probe_iris" ]; then
    fail "Story 29.3: IRIS answers the probe $probe_id ($probe_method $probe_target) with $host_got, host_probes lists $probe_iris"
    host_wrong=$((host_wrong + 1))
  fi
done << HOSTLINES
$host_lines
HOSTLINES
if [ "$host_wrong" = 0 ] && [ "$host_count" -ge 90 ]; then
  pass "Story 29.3: IRIS's own answer to each of the $host_count host_probes probes is the one listed (status, and whether the page holds an IRIS form field)"
else
  fail "Story 29.3: $host_count host_probes probes were measured (wanted at least 90) and $host_wrong of them differ from the list"
fi

# (b) a signed-in trace page loads the broker file the check reads, and IRIS serves it with 200.
trace_page=/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen
host_jar="$tmp/jar.hosttrace"
: > "$host_jar"
next_probe
host_token=$(page_token "$host_jar" "$base$trace_page?probe=$probes")
if [ -z "$host_token" ]; then
  fail "Story 29.3 (b): the trace application's sign-in page gave no session token"
else
  next_probe
  curl -s --max-time 30 -o /dev/null -c "$host_jar" -b "$host_jar" --data-urlencode "IRISSessionToken=$host_token" --data-urlencode "IRISUsername=$readonly_user" \
    --data-urlencode "IRISPassword=$readonly_password" --data-urlencode 'IRISLogin=Login' "$base$trace_page?probe=$probes" < /dev/null
  next_probe
  curl -s --max-time 30 -o "$tmp/host.trace" -c "$host_jar" -b "$host_jar" "$base$trace_page?probe=$probes" < /dev/null
  host_refs=$(grep -oE '/csp/broker/[A-Za-z0-9_./-]+' "$tmp/host.trace" | sort -u | tr '\n' ' ')
  echo "MEASURED the signed-in trace page's /csp/broker/ references: ${host_refs% }"
  host_broker=$(host_broker_file)
  next_probe
  host_broker_code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' "$base$host_broker?probe=$probes" < /dev/null)
  echo "MEASURED $host_broker answers $host_broker_code with no session"
  if printf '%s\n' $host_refs | grep -qxF "$host_broker" && [ "$host_broker_code" = 200 ]; then
    pass "Story 29.3 (b): a signed-in trace page loads $host_broker, and IRIS serves it with 200 with no session"
  else
    fail "Story 29.3 (b): the signed-in trace page loads '${host_refs% }' (wanted $host_broker), which answers $host_broker_code (wanted 200)"
  fi
fi
logout_all "$host_jar" /ocutalon/trace/ocutalon/

# (c) the two dummy-value sign-in POSTs of the guard checks come back as IRIS's sign-in page: the splash's refused (aria-invalid), the trace
# page's as the same page a plain GET gives (the Login form), which shows the POST reached IRIS and no more.
host_signin 3
host_send "$signin_target" "${signin_args[@]}"
host_splash_flag=$(grep -c 'aria-invalid="true"' "$tmp/host.body")
echo "MEASURED the splash's three-field POST: $host_code, aria-invalid $host_splash_flag, $(host_form_flag)"
if [ "$host_code" = 200 ] && [ "$host_splash_flag" -ge 1 ]; then
  pass "Story 29.3 (c): the splash's three-field POST with dummy values is refused by IRIS (200, aria-invalid)"
else
  fail "Story 29.3 (c): the splash's three-field POST gives $host_code with $host_splash_flag aria-invalid marker(s)"
fi
host_send "$trace_page"
host_plain_marker=$(grep -cF -- "$(host_trace_signin_marker)" "$tmp/host.body")
echo "MEASURED the trace application's sign-in page, a plain GET: $host_code, $(host_form_flag), Login form markers: $host_plain_marker"
host_signin 4
host_send "$signin_target" "${signin_args[@]}"
host_marker=$(host_trace_signin_marker)
echo "MEASURED the trace page's four-field POST: $host_code, $(host_form_flag), text: $(host_text)"
if [ "$host_code" = 200 ] && [ "$(host_form_flag)" = form ] && grep -qF -- "$host_marker" "$tmp/host.body"; then
  pass "Story 29.3 (c): the trace page's four-field POST with dummy values comes back as IRIS's sign-in page (200, a password field, its Login form; a plain GET gives the same page, so this shows the POST reached IRIS, not that IRIS refused the token)"
else
  fail "Story 29.3 (c): the trace page's four-field POST gives $host_code, $(host_form_flag), and the marker '$host_marker' is $(grep -qF -- "$host_marker" "$tmp/host.body" && echo present || echo absent)"
fi
echo "MEASURED Story 29.3 section took $((SECONDS - host_started)) s"

# --- the published passwords stay out of the logs and the event log (Never) ---

# log_hits <value>: the number of lines of the container's output, messages.log and the after-start log that hold the value (only the
# count is printed by the callers).
log_hits() {
  { dc logs --no-color iris 2>&1; dc exec -T iris cat "$mgr/messages.log" /durable/ocutalon-after-start.log 2>/dev/null; } | grep -cF -e "$1"
}
# check_password_not_logged <env variable> <label>: the value of the start variable is in no line of the container's output, of
# messages.log or of the after-start log (only a count is printed), and in no row of the production event log.
check_password_not_logged() {
  local variable=$1 label=$2 value n
  value=$(dc exec -T iris printenv "$variable" 2>/dev/null | tr -d '\r')
  if [ -z "$value" ]; then
    fail "$label: the container has no $variable, so a search of its logs for it proves nothing"
    return
  fi
  n=$(log_hits "$value")
  if [ "$n" = 0 ]; then
    pass "$label: no line of the container's output, messages.log or the after-start log holds it"
  else
    fail "$label: '$n' line(s) of the container's output, messages.log or the after-start log hold it"
  fi
}
# check_records_clean <when> <what> <variable>...: none of the values of the variables (in the environment of the session that runs the
# script; LIVE_SESSION_ENV names those that check_session hands over) is in a row of the production event log, of the live events
# (OCUTALON) or in an audit entry (%SYS); <what> names them in the labels. Only counts are printed.
check_records_clean() {
  local when=$1 what=$2 names="" events="" audits="" live="" v
  shift 2
  for v in "$@"; do
    names="$names${names:+,}\"$v\""
    events="$events${events:+
}CHK|eventlog|$v|0"
    live="$live${live:+
}CHK|liveevent|$v|0"
    audits="$audits${audits:+
}CHK|audit|$v|0"
  done
  check_session "$when: the production event log and the live events hold $what" OCUTALON \
    "$events
$live" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?\",e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|eventlog|\",p,\"|\",n }" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?\",e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|liveevent|\",p,\"|\",n }" \
    'Halt'
  check_session "$when: no audit entry holds $what" %SYS \
    "$audits" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?\",e,e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|audit|\",p,\"|\",n }" \
    'Halt'
}
# check_search_controls <when> (QA): the searches of check_logs_clean can see what they search. A search that reads nothing, because a
# file is missing or a table is empty or a database is not scanned, would also count 0, so each source is shown to hold something: the
# three log sources are readable and not empty; the event log, the live events, the production message headers and the audit log hold
# rows; and the global scan finds the row 6 session's resume hash (which only OCUTALON_PRIVATE holds), the row 6 message's text (the
# production's message body, in OCUTALON_DATA) and the public proxy address (OCUTALON_PUBLIC). Only these controls' words are printed.
check_search_controls() {
  local readable=1 f out_n hash
  out_n=$(dc logs --no-color iris 2>&1 | wc -l | tr -d ' ')
  if [ "${out_n:-0}" -lt 1 ]; then readable=0; fi
  for f in "$mgr/messages.log" /durable/ocutalon-after-start.log; do
    if ! dc exec -T iris test -s "$f" 2>/dev/null; then readable=0; fi
  done
  if [ "$readable" = 1 ]; then
    pass "$1: row 6 control: the container's output, messages.log and the after-start log are readable and not empty"
  else
    fail "$1: row 6 control: the container's output ('$out_n' lines), messages.log or the after-start log is unreadable or empty, so a search of them proves nothing"
  fi
  hash=$(row_field "$epoch_one" ResumeHash)
  check_session "$1: row 6 control: the searched records hold rows, and the global scan reads each of its three databases" OCUTALON \
    "CHK|control|eventlog|seen
CHK|control|liveevent|seen
CHK|control|messages|seen
CHK|control|scan-private|seen
CHK|control|scan-data|seen
CHK|control|scan-public|seen" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log") Do rs.%Next() Write !,"CHK|control|eventlog|",$Select(rs.%GetData(1)>0:"seen",1:"blind")' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Live.Event") Do rs.%Next() Write !,"CHK|control|liveevent|",$Select(rs.%GetData(1)>0:"seen",1:"blind")' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader") Do rs.%Next() Write !,"CHK|control|messages|",$Select(rs.%GetData(1)>0:"seen",1:"blind")' \
    "Write !,\"CHK|control|scan-private|\",\$Select(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(\"$hash\",\"OCUTALON_PRIVATE\")>0:\"seen\",1:\"blind\")" \
    'Write !,"CHK|control|scan-data|",$Select(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits("zz row six","OCUTALON_DATA")>0:"seen",1:"blind")' \
    "Write !,\"CHK|control|scan-public|\",\$Select(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(\"$proxy_start\",\"OCUTALON_PUBLIC\")>0:\"seen\",1:\"blind\")" \
    'Halt'
  check_session "$1: row 6 control: the audit log holds entries" %SYS \
    "CHK|control|audit|seen" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit") Do rs.%Next() Write !,"CHK|control|audit|",$Select(rs.%GetData(1)>0:"seen",1:"blind")' \
    'Halt'
}
# check_logs_clean <when>: neither published password is in the logs above, in a row of the production event log or of the live
# events (OCUTALON), or in an audit entry (%SYS); only counts are printed. After row 6 the same searches run for the resume reference, and
# a scan of every global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC (production messages included) adds to them. It runs
# after the browser and again after the restart, whose start writes both passwords again and rewrites the after-start log.
check_logs_clean() {
  check_password_not_logged OCUTALON_DEMO_PASSWORD "$1: the demo account's password"
  check_password_not_logged OCUTALON_READONLY_PASSWORD "$1: the read-only account's password"
  check_records_clean "$1" "neither published password" OCUTALON_DEMO_PASSWORD OCUTALON_READONLY_PASSWORD
  if [ -z "$resume_ref" ]; then
    fail "$1: row 6 kept no resume reference, so a search for it proves nothing"
    return
  fi
  if [ "$(log_hits "$resume_ref")" = 0 ]; then
    pass "$1: row 6: no line of the container's output, messages.log or the after-start log holds the resume reference"
  else
    fail "$1: row 6: '$(log_hits "$resume_ref")' line(s) of the container's output, messages.log or the after-start log hold the resume reference"
  fi
  OCUTALON_T16_REF="$resume_ref" LIVE_SESSION_ENV=OCUTALON_T16_REF check_records_clean "$1: row 6" "the resume reference" OCUTALON_T16_REF
  OCUTALON_T16_REF="$resume_ref" LIVE_SESSION_ENV=OCUTALON_T16_REF check_session "$1: row 6: no node of any global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC holds the resume reference" OCUTALON \
    "CHK|globals|0" \
    'Write !,"CHK|globals|",##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits($SYSTEM.Util.GetEnviron("OCUTALON_T16_REF"))' \
    'Halt'
  check_search_controls "$1"
}
check_logs_clean "after the first start"

# --- row 13: every start, a restart ---

check_session "row 13: a counter row is added before the restart" OCUTALON \
  "CHK|added|1" \
  'Write !,"CHK|added|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.AddressCounter).Add("zz-row13-restart"))' \
  'Halt'
dc stop iris > /dev/null 2>&1
dc start iris > /dev/null 2>&1
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200 | redact
  die "row 13 the restart did not end ready within 200 s"
fi
expected_run "cleared" "present $ipm_version" "already mapped" "ok" "skipped $version" "$version" > "$tmp/expected.row13"
check_log "row 13" "$tmp/expected.row13"
check_session "row 13: ready again, the guard setting unchanged" OCUTALON \
  "CHK|ready|1
CHK|validation|Check^OcuTalonPasswordGuard" \
  'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
  'New $Namespace Set $Namespace="%SYS" Do ##class(Security.System).Get(,.sp) Write !,"CHK|validation|",$Get(sp("PasswordValidationRoutine"))' \
  'Halt'
restart_outcome=$(signin_outcome "$demo_user" "$demo_password")
if [ "$restart_outcome" = shell ]; then
  pass "row 13: after the restart the demo account signs in with its published password"
else
  fail "row 13: after the restart the demo account's sign-in gives '$restart_outcome', wanted shell"
fi
restart_readonly=$(signin_outcome "$readonly_user" "$readonly_password")
if [ "$restart_readonly" = norole ]; then
  pass "row 13: after the restart the read-only account signs in with its published password (no OcuTalon role)"
else
  fail "row 13: after the restart the read-only account's sign-in gives '$restart_readonly', wanted norole"
fi
check_logs_clean "after the restart"
# The same restart keeps the key and the row, and the key sits in its own node only, raw and base64url (counts only, Story 29.5).
check_session "row 13: after the restart the row still counts, the key's marker is the start's, and only the key's own node holds the key" OCUTALON \
  "CHK|counted|1
CHK|marker|1
CHK|raw|1
CHK|b64|0" \
  'Write !,"CHK|counted|",##class(OcuTalon.Data.AddressCounter).Recent("zz-row13-restart")' \
  'Set k=##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL Set v=$Get(@k) Write !,"CHK|marker|",$ListValid(v)&&($ListLength(v)=2)&&($List(v,1)=##class(OcuTalon.Data.Public.Settings).Get("lastReset"))&&($Length($List(v,2))=32)' \
  'Write !,"CHK|raw|",##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits($List(v,2))' \
  'Write !,"CHK|b64|",##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits($Translate($SYSTEM.Encryption.Base64Encode($List(v,2),1),"+/=","-_"))' \
  'Halt'
drop_counter "zz-row13-restart"

if [ "$fails" -ne 0 ]; then
  echo "test-online-demo: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-demo: all checks passed"
