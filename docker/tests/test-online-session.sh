#!/usr/bin/env bash
# Live test of leaving the online demo's page and of Sign out (Story 16.4; AD-1, AD-4, AD-13, AD-25): builds the image and starts it in one
# throwaway compose project with the online-demo flag on and the test start values of docker/tests/lib-online.sh (the unit of test-online-demo.sh
# shares them), and checks, in this order:
#   - the start and row 1: the log ends ready; Security.Applications reads a 120-second timeout for /ocutalon, /ocutalon/api and both trace
#     applications and 28800 for /ocutalon/public, and (row 6) the idle cap is seeded at 600 (the Web step with the flag on);
#   - Task 0's (c): a curl jar signs in and opens a Visual Trace page, and its trace CSP session has an AppTimeout of 120;
#   - the setup of rows 2 and 4: jar K signs in and a child process polls /ocutalon/api/v1/events with K's cursors every 5 s through the
#     browser step; jar C signs in at the same moment, opens a trace page and makes no request afterwards. C's session gets a fixture turn, a
#     fixture pairing, a real reminder due in an hour, a real Orders watch (a StartWatch through Commands.Submit), a pending fixture approval
#     request and a Break the feed run row; the unit checks that C holds a main and a trace CSP session before it waits to see them gone;
#   - the browser step: the project online-session of web/playwright.config.ts (web/e2e-online/session/) as the demo account: leave.spec.ts (L1
#     to L5: a reload, the idle cap, a 401, an epoch change injected, through the snapshot (L4b) and a real one; L4c, the bound of the group
#     sign-out), idle-activity.spec.ts (L7: pointer movement, a scroll and a focus change are no activity), sign-out.spec.ts (O1, the dialog; O2,
#     Sign out ends the session, with a second session untouched; O3, a failed /session/end) and sign-out-failed.spec.ts (O4: a Sign out that fails
#     for real, a reminder row held by another process, keeps the session resumable and the repeat finishes the work);
#   - row 2 (AD-13: polling keeps the session): at least 150 s after C's last request, K's /state answers 200 with K's epoch while C's CSP session no
#     longer exists (the unit waits for the rest of the 150 s when the browser step was shorter, then up to 180 s for C's session to go, and names
#     the elapsed seconds when it fails);
#   - row 4 (the closed page, AC 2; Telegram part off): C's main and trace CSP sessions are gone within 180 s of its last request (the delay and
#     the licence counts are MEASURED lines); every row of C is as it was; with no CSP session of C a real reminder set for C due in 5 s fires (its
#     state, its delivery row), Approval.Answer on the approval answers done, the watch's check runs again (LastRunAt passes the moment C was seen
#     gone, waited for 90 s at most); the splash with C's jar says the place was freed above both cards; a sign-in with C's jar resumes C's epoch with
#     the rows still there;
#   - Task 0's (a) and (b): the group sign-out of a jar that opened a trace page (a GET of /ocutalon/?IRISLogout=end), and POST /api/v1/session/end
#     on the online demo, each followed by whether the jar's trace CSP session is gone within 15 s and the licence units before and after; and (e):
#     how the unit names a jar's CSP sessions (printed as MEASURED lines).
# Every jar ends with the group sign-out, every page request carries a unique probe, no password or resume reference is printed, and the project is
# removed by the EXIT trap. The throwaway publishes its web port only on 127.0.0.1. Every wait ends by the overall deadline (OCUTALON_LIVE_DEADLINE,
# 540 s by default); the browser run's global timeout is what is left of it minus 20 s. Prints one PASS or FAIL line per check; exits 0 only when
# all pass. Needs docker compose, the build 154 base image (IRIS_IMAGE), Node 24.15 or later, curl, the built web bundle and Chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-session
live_web_port || exit 1

base="http://127.0.0.1:$web_port"
online_values
resume_ref=
online_override

k_pid=
stop_k() {
  if [ -n "$k_pid" ]; then
    kill "$k_pid" 2>/dev/null
    wait "$k_pid" 2>/dev/null
    k_pid=
  fi
}
trap 'stop_k; live_cleanup' EXIT

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log" | redact
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200 | redact
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"

# --- row 1: the timeouts ---

check_session "row 1: /ocutalon, /ocutalon/api and both trace applications time out after 120 s, and /ocutalon/public after 28800 s" %SYS \
  "CHK|timeout|/ocutalon|120
CHK|timeout|/ocutalon/api|120
CHK|timeout|/ocutalon/trace/ocutalon|120
CHK|timeout|/ocutalon/trace/ocuorders|120
CHK|timeout|/ocutalon/public|28800" \
  'For n="/ocutalon","/ocutalon/api","/ocutalon/trace/ocutalon","/ocutalon/trace/ocuorders","/ocutalon/public" { Kill p Set sc=##class(Security.Applications).Get(n,.p) Write !,"CHK|timeout|",n,"|",$Get(p("Timeout"),"<none>") }' \
  'Halt'
check_session "row 6: the Web step seeded the idle cap at 600 seconds (the flag is on)" OCUTALON \
  "CHK|idle|600" \
  'Write !,"CHK|idle|",##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Data.Setting).#IDLEKEY)' \
  'Halt'

# --- helpers: jars, sessions and the licence ---

# jar_cookie <jar> <path>: the value of the CSPSESSIONID cookie that the jar holds for the path ("" when none).
jar_cookie() { awk -F'\t' -v p="$2" '$3 == p && $6 ~ /^CSPSESSIONID/ { print $7 }' "$1" | tail -n 1; }

# state_epoch <jar>: the epoch of the jar's /state ("" when it does not answer 200).
state_epoch() {
  local body code
  next_probe
  body=$(curl -s --max-time 30 -b "$1" -w '\n%{http_code}' "$base/ocutalon/api/v1/state?probe=$probes")
  code=${body##*$'\n'}
  if [ "$code" = 200 ]; then printf '%s' "$body" | sed -n 's/.*"epoch":"\([^"]*\)".*/\1/p' | head -n 1; fi
}

# state_code <jar>: the HTTP status of the jar's /state.
state_code() {
  next_probe
  curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$1" "$base/ocutalon/api/v1/state?probe=$probes"
}

# open_trace <jar>: opens the Visual Trace message viewer of OCUTALON with the jar (the first trace page of the jar's user takes a licence unit).
open_trace() {
  next_probe
  curl -s --max-time 30 -o /dev/null -b "$1" -c "$1" "$base/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?probe=$probes"
}

# csp_find <cookie value>: "<application>|<AppTimeout>|<session id>" of the CSP session whose cookie or id is the value ("none" when no session is).
csp_find() {
  printf '%s\n' "Set want=\"$1\",found=\"none\"" \
    'Set rs=##class(%ResultSet).%New("%CSP.Session:Extent") Do rs.Execute()' \
    'While rs.Next() { Set s=##class(%CSP.Session).%OpenId(rs.Get("ID")) If $IsObject(s),(s.CSPSessionCookie=want)||(s.SessionId=want) { Set found=s.Application_"|"_s.AppTimeout_"|"_s.SessionId Quit } }' \
    'Write !,"CHK|csp|",found' 'Halt' | iris_script %SYS | sed -n 's/^CHK|csp|//p'
}

# csp_exists <session id>: 1 when a CSP session with the id exists.
csp_exists() {
  printf '%s\n' "Write !,\"CHK|exists|\",##class(%CSP.Session).%ExistsId(\"$1\")" 'Halt' | iris_script %SYS | sed -n 's/^CHK|exists|//p'
}

# licence: "<InstanceConnections>/<LUConsumed>".
licence() {
  printf '%s\n' 'Write !,"CHK|lic|",$SYSTEM.License.InstanceConnections(),"/",$SYSTEM.License.LUConsumed()' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|lic|//p'
}

# session_row <epoch>: "<Ref>|<TraceRef>|<CspSessionId>" of the Session row of the epoch.
session_row() {
  printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?\",\"$1\") If rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get(\"ID\")) Write !,\"CHK|row|\",r.Ref,\"|\",r.TraceRef,\"|\",r.CspSessionId }" 'Halt' \
    | iris_script OCUTALON | sed -n 's/^CHK|row|//p'
}

# --- Task 0 (c): the trace CSP session's timeout ---

jar_t="$tmp/jar.t"
: > "$jar_t"
online_signin "$jar_t" "" "" > /dev/null
open_trace "$jar_t"
trace_cookie=$(jar_cookie "$jar_t" /ocutalon/trace/ocutalon/)
main_cookie=$(jar_cookie "$jar_t" /ocutalon/)
trace_info=$(csp_find "$trace_cookie")
main_info=$(csp_find "$main_cookie")
echo "MEASURED Story 16.4 Task 0 (e): the jar's cookies: main $([ -n "$main_cookie" ] && echo present || echo absent), trace $([ -n "$trace_cookie" ] && echo present || echo absent); found by cookie: main '${main_info%|*}', trace '${trace_info%|*}'"
if [ "$(printf '%s' "$trace_info" | cut -d'|' -f1,2)" = "/ocutalon/trace/ocutalon/|120" ]; then
  pass "Task 0 (c): the jar's trace CSP session is an /ocutalon/trace/ocutalon/ session with an AppTimeout of 120"
else
  fail "Task 0 (c): the jar's trace CSP session reads '${trace_info%|*}', wanted /ocutalon/trace/ocutalon/|120"
fi
logout_all "$jar_t" /ocutalon/trace/ocutalon/

# --- the setup of rows 2 and 4: K and C ---

jar_k="$tmp/jar.k"
jar_c="$tmp/jar.c"
: > "$jar_k"
: > "$jar_c"
online_signin "$jar_k" "" "" > /dev/null
online_signin "$jar_c" "" "" > /dev/null
epoch_k=$(state_epoch "$jar_k")
epoch_c=$(state_epoch "$jar_c")
if [ -z "$epoch_k" ] || [ -z "$epoch_c" ] || [ "$epoch_k" = "$epoch_c" ]; then
  die "K and C did not sign in to two sessions (epochs '$epoch_k' and '$epoch_c')"
fi
# K's cursors, then its poll loop: a child of this script, one /events request every 5 s with the jar, stopped after the browser step.
next_probe
cursors=$(curl -s --max-time 30 -b "$jar_k" "$base/ocutalon/api/v1/state?probe=$probes" | sed -n 's/.*"streams":{"session":\([0-9]*\),"instance":\([0-9]*\)}.*/\1 \2/p' | head -n 1)
cursor_session=${cursors% *}
cursor_instance=${cursors#* }
(
  n=0
  while :; do
    n=$((n + 1))
    curl -s --max-time 20 -o /dev/null -b "$jar_k" "$base/ocutalon/api/v1/events?after=${cursor_session:-0}&afterInstance=${cursor_instance:-0}&probe=k$$x$n"
    sleep 5
  done
) &
k_pid=$!

row_c=$(session_row "$epoch_c")
ref_c=${row_c%%|*}
trace_ref_c=$(printf '%s' "$row_c" | cut -d'|' -f2)
csp_c=$(printf '%s' "$row_c" | cut -d'|' -f3)
setup_c=$(printf '%s\n' \
  "Set ref=\"$ref_c\"" \
  'Set turn=##class(OcuTalon.Test.Data.Fixture).Turn(ref)' \
  'Set pair=##class(OcuTalon.Test.Data.Fixture).Pairing(ref,"Dana")' \
  'Set approval=##class(OcuTalon.Test.Data.Fixture).Approval(ref,"","pending",,{"RequiredRole":"OcuTalonUser"})' \
  'Set run=##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(ref)' \
  'Set made=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(ref,"zz online session",3600)' \
  'Set start=##class(OcuTalon.Msg.Command.StartWatch).%New() Set start.SessionRef=ref,start.Namespace=##class(OcuTalon.Install.Step.Demo).#NAMESPACE,start.Production=##class(OcuTalon.Install.Step.Demo).#PRODUCTION,start.DisplayName="Orders"' \
  'Set sc=##class(OcuTalon.Core.Commands).Submit(start,"web_user",.started)' \
  'Write !,"CHK|turn|",turn,!,"CHK|pair|",pair,!,"CHK|approval|",approval,!,"CHK|run|",run,!,"CHK|reminder|",made.ref,"|",made.ok,!,"CHK|watch|",$Select($IsObject($Get(started)):started.Ok_"|"_started.Outcome,1:"none")' \
  'Halt' | iris_script OCUTALON)
reminder_c=$(printf '%s\n' "$setup_c" | sed -n 's/^CHK|reminder|\([^|]*\)|1$/\1/p')
approval_c=$(printf '%s\n' "$setup_c" | sed -n 's/^CHK|approval|//p')
turn_c=$(printf '%s\n' "$setup_c" | sed -n 's/^CHK|turn|//p')
pair_c=$(printf '%s\n' "$setup_c" | sed -n 's/^CHK|pair|//p')
if [ -n "$reminder_c" ] && [ -n "$approval_c" ] && [ -n "$turn_c" ] && [ -n "$pair_c" ] && printf '%s\n' "$setup_c" | grep -q '^CHK|watch|1|started$'; then
  pass "setup: C's session holds a turn, a pairing, a real reminder, a real Orders watch, a pending request and a Break the feed run"
else
  printf '%s\n' "$setup_c" | cut -c1-160
  die "setup: C's rows could not be made"
fi
open_trace "$jar_c"
c_last=$SECONDS
licence_c_open=$(licence)
echo "MEASURED Story 16.4 Task 0: licence (connections/units) with C's trace page open: $licence_c_open"
trace_cookie_c=$(jar_cookie "$jar_c" /ocutalon/trace/ocutalon/)
trace_info_c=$(csp_find "$trace_cookie_c")
if [ -n "$csp_c" ] && [ "$(csp_exists "$csp_c")" = 1 ] && [ -n "$trace_cookie_c" ] && [ "$trace_info_c" != none ]; then
  pass "setup: C holds a main CSP session and a trace CSP session, which rows 2 and 4 wait to see gone"
else
  die "setup: C's CSP sessions could not be named (main '$csp_c', trace '${trace_info_c%|*}')"
fi

# --- the browser step ---

e2e_log="$tmp/e2e.log"
show_log() { tail -n "$1" "$e2e_log" | redact | sed 's/^/  /'; }
run_e2e() {
  local left=$((deadline - SECONDS))
  OCUTALON_URL="$base" \
    OCUTALON_DEMOACCOUNT_USER="$demo_user" \
    OCUTALON_DEMOACCOUNT_PASSWORD="$demo_password" \
    OCUTALON_READONLYACCOUNT_USER="$readonly_user" \
    OCUTALON_READONLYACCOUNT_PASSWORD="$readonly_password" \
    OCUTALON_E2E_IRIS_CONTAINER="$cid" \
    OCUTALON_E2E_TIMEOUT_MS=$(((left - 20) * 1000)) \
    npm --prefix web run e2e:online-session -- "$@" > "$e2e_log" 2>&1
}
browser_started=$SECONDS
if [ $((deadline - SECONDS)) -lt 120 ]; then
  fail "the browser step: only $((deadline - SECONDS)) s of the deadline are left"
else
  run_e2e
  e2e_status=$?
  echo "MEASURED Story 16.4: the browser step took $((SECONDS - browser_started)) s; the unit has run $SECONDS s at this point"
  if [ "$e2e_status" -eq 0 ]; then
    show_log 20
    pass "the specs of the online-session project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
  else
    show_log 80
    if grep -q "Executable doesn't exist" "$e2e_log"; then
      echo "  a browser is missing: run npx --prefix web playwright install chromium"
    fi
    fail "the specs of the online-session project failed (exit $e2e_status)"
  fi
fi

# --- row 2: polling keeps the session ---

while [ $((SECONDS - c_last)) -lt 150 ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 5; done
c_main_gone=$(csp_exists "$csp_c")
while [ "$c_main_gone" != 0 ] && [ $((SECONDS - c_last)) -lt 180 ] && [ "$SECONDS" -lt "$deadline" ]; do
  sleep 3
  c_main_gone=$(csp_exists "$csp_c")
done
elapsed=$((SECONDS - c_last))
k_code=$(state_code "$jar_k")
k_epoch=$(state_epoch "$jar_k")
stop_k
if [ "$elapsed" -lt 150 ]; then
  fail "row 2: only $elapsed s have passed since C's last request, wanted 150"
elif [ "$k_code" = 200 ] && [ "$k_epoch" = "$epoch_k" ] && [ "$c_main_gone" = 0 ]; then
  pass "row 2: $elapsed s after C's last request K's /state answers 200 with K's epoch, and C's CSP session no longer exists"
else
  fail "row 2: $elapsed s after C's last request K's /state answered $k_code (K's epoch $([ "$k_epoch" = "$epoch_k" ] && echo kept || echo 'not kept')) and C's CSP session $([ "$c_main_gone" = 0 ] && echo 'is gone' || echo 'still exists')"
fi

# --- row 4: the closed page ---

gone_at=
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ "$(csp_exists "$csp_c")" = 0 ] && [ "$(printf '%s' "$(csp_find "$(jar_cookie "$jar_c" /ocutalon/trace/ocutalon/)")")" = none ]; then
    gone_at=$((SECONDS - c_last))
    break
  fi
  sleep 5
done
licence_gone=$(licence)
echo "MEASURED Story 16.4 Task 0 (d): C's main and trace CSP sessions were gone ${gone_at:-never} s after its last request; licence (connections/units) $licence_c_open with the trace page open, $licence_gone once gone"
if [ -n "$gone_at" ] && [ "$gone_at" -le 180 ]; then
  pass "row 4: C's main and trace CSP sessions are gone $gone_at s after its last request (within 180 s)"
else
  fail "row 4: C's CSP sessions were not both gone within 180 s of its last request (${gone_at:-never})"
fi
seen_gone=$(printf '%s\n' 'Write !,"CHK|now|",##class(OcuTalon.Data.Time).NowUtc()' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|now|//p')
check_session "row 4: every row of C is as it was while no CSP session of C was open" OCUTALON \
  "CHK|turn|done
CHK|pairing|$ref_c
CHK|reminder|pending
CHK|watch|1
CHK|approval|pending
CHK|run|1" \
  "Write !,\"CHK|turn|\",##class(OcuTalon.Data.Turn).RefIndexOpen(\"$turn_c\").State" \
  "Write !,\"CHK|pairing|\",##class(OcuTalon.Data.Ownership).Pairing(\"$ref_c\",.sc).SessionRef" \
  "Write !,\"CHK|reminder|\",##class(OcuTalon.Data.Reminder).RefIndexOpen(\"$reminder_c\").State" \
  "Write !,\"CHK|watch|\",##class(OcuTalon.Data.Ownership).Checks(\"$ref_c\").Count()" \
  "Write !,\"CHK|approval|\",##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(\"$approval_c\").State" \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ?\",\"$ref_c\") Do rs.%Next() Write !,\"CHK|run|\",rs.%GetData(1)" \
  'Halt'

# With no CSP session of C: a real reminder due in 5 s fires, the approval can be answered, the watch's check runs again.
fire=$(printf '%s\n' "Set made=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(\"$ref_c\",\"zz online session fire\",5)" 'Write !,"CHK|fire|",made.ref,"|",made.ok' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|fire|//p')
fire_ref=${fire%%|*}
fired=
for _ in $(seq 1 12); do
  [ "$SECONDS" -lt "$deadline" ] || break
  fired=$(printf '%s\n' "Set r=##class(OcuTalon.Data.Reminder).RefIndexOpen(\"$fire_ref\") Write !,\"CHK|state|\",r.State" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|state|//p')
  [ "$fired" = fired ] && break
  sleep 5
done
delivered=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Kind = 'reminder'\",\"$ref_c\") Do rs.%Next() Write !,\"CHK|delivery|\",rs.%GetData(1)" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|delivery|//p')
if [ "$fired" = fired ] && [ "${delivered:-0}" -ge 1 ]; then
  pass "row 4: with no CSP session of C open, a real reminder due in 5 s fired and was delivered"
else
  fail "row 4: the reminder due in 5 s is '$fired' with $delivered delivery row(s)"
fi
answer=$(printf '%s\n' "Write !,\"CHK|answer|\",##class(OcuTalon.Bridge.Approval).Answer(\"$approval_c\",\"approve\",\"web\",\"$demo_user\",\"$ref_c\")" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|answer|//p')
if [ "$answer" = done ]; then
  pass "row 4: with no CSP session of C open, Approval.Answer on its request answers done"
else
  fail "row 4: Approval.Answer answered '$answer', wanted done"
fi
ran=
for _ in $(seq 1 18); do
  [ "$SECONDS" -lt "$deadline" ] || break
  ran=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT LastRunAt FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?\",\"$ref_c\") If rs.%Next() { Write !,\"CHK|ran|\",rs.%GetData(1)] \"$seen_gone\" }" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|ran|//p')
  [ "$ran" = 1 ] && break
  sleep 5
done
if [ "$ran" = 1 ]; then
  pass "row 4: C's watch ran again after C was seen gone"
else
  fail "row 4: C's watch did not run again within 90 s of the moment C was seen gone"
fi
echo "SKIP row 4: Telegram keeps working with no CSP session open (Story 31.3 turns this on)"

# The splash with C's jar says the place was freed; a sign-in with the jar resumes C's epoch with the rows still there.
next_probe
splash=$(curl -s --max-time 30 -b "$jar_c" "$base/ocutalon/?probe=$probes")
notice_at=$(printf '%s' "$splash" | grep -bo 'You were away for a while, so your place was freed' | head -n 1 | cut -d: -f1)
cards_at=$(printf '%s' "$splash" | grep -bo 'class="splash-cards"' | head -n 1 | cut -d: -f1)
if [ -n "$notice_at" ] && [ -n "$cards_at" ] && [ "$notice_at" -lt "$cards_at" ]; then
  pass "row 4: the splash with C's jar says the place was freed, above both cards"
else
  fail "row 4: the splash with C's jar shows no place-freed notice above the cards"
fi
online_signin "$jar_c" "" "" > /dev/null
resumed=$(state_epoch "$jar_c")
rows_back=$(printf '%s\n' "Write !,\"CHK|reminder|\",##class(OcuTalon.Data.Reminder).RefIndexOpen(\"$reminder_c\").State,\"|\",##class(OcuTalon.Data.Turn).RefIndexOpen(\"$turn_c\").State" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|reminder|//p')
if [ "$resumed" = "$epoch_c" ] && [ "$rows_back" = "pending|done" ]; then
  pass "row 4: a sign-in with C's jar resumes C's epoch, and C's turn and reminder are still there"
else
  fail "row 4: the sign-in with C's jar gave epoch '$([ "$resumed" = "$epoch_c" ] && echo C\'s || echo other)' and rows '$rows_back'"
fi
logout_all "$jar_c" /ocutalon/trace/ocutalon/
logout_all "$jar_k" /ocutalon/trace/ocutalon/

# --- Task 0 (a), (b), (e): what ends the trace session ---

# trace_end <label> <how>: a jar signs in, opens a Visual Trace page, and ends the session by <how> (group GET, or the API's session/end); prints
# whether the jar's trace CSP session is gone within 15 s and the licence before and after.
trace_end() {
  local label=$1 how=$2 jar="$tmp/jar.$1" trace gone=no existed=no before after waited=0
  : > "$jar"
  online_signin "$jar" "" "" > /dev/null
  open_trace "$jar"
  trace=$(jar_cookie "$jar" /ocutalon/trace/ocutalon/)
  if [ -n "$trace" ] && [ "$(csp_find "$trace")" != none ]; then existed=yes; fi
  before=$(licence)
  case $how in
    group)
      next_probe
      curl -s --max-time 30 -o /dev/null -b "$jar" -c "$jar" "$base/ocutalon/?IRISLogout=end&t=$probes"
      ;;
    api)
      next_probe
      curl -s --max-time 30 -o /dev/null -b "$jar" -c "$jar" -X POST -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" --data '{}' "$base/ocutalon/api/v1/session/end?probe=$probes"
      ;;
  esac
  if [ "$existed" = yes ]; then
    for waited in 0 3 6 9 12 15; do
      if [ "$(csp_find "$trace")" = none ]; then gone=yes; break; fi
      [ "$SECONDS" -lt "$deadline" ] || break
      sleep 3
    done
  else
    gone=unmeasured
  fi
  after=$(licence)
  echo "MEASURED Story 16.4 Task 0 ($label): after $how, the trace CSP session is gone within 15 s: $gone (after $waited s); licence (connections/units) before $before, after $after" >&2
  logout_all "$jar" /ocutalon/trace/ocutalon/
  logout_all "$jar" /ocutalon/trace/ocuorders/
  printf '%s' "$gone"
}
group_ends=$(trace_end a group | tail -n 1)
api_ends=$(trace_end b api | tail -n 1)
if [ "$group_ends" = yes ] || [ "$api_ends" = yes ]; then
  pass "Task 0: a sign-out ends a jar's trace CSP session (group GET: $group_ends, POST session/end: $api_ends)"
else
  fail "Task 0: neither the group GET nor POST session/end ended the jar's trace CSP session"
fi

# --- the clean-up of C's rows ---

printf '%s\n' \
  "Set ref=\"$ref_c\"" \
  "Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveAll(ref)" \
  'Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?",ref)' \
  "Set s=##class(OcuTalon.Data.Session).RefIndexOpen(ref) If \$IsObject(s) { Set ss=[] Do ss.%Push(s.TraceRef) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(s) Set refs=##class(OcuTalon.Test.Data.Fixture).AdoptTurns(ref,ref)_\",$approval_c,$pair_c\" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(ss) }" \
  'Write !,"CHK|cleaned|1"' 'Halt' | iris_script OCUTALON > /dev/null

if [ "$fails" -ne 0 ]; then
  echo "test-online-session: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-session: all checks passed"
