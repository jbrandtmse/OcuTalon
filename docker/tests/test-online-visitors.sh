#!/usr/bin/env bash
# Live test of the online demo's visitor count (Story 29.7; AD-13, AD-25; owner decisions U-163 and U-169): builds the image and starts it
# in one throwaway compose project with the online-demo flag on and the test start values of docker/tests/lib-online.sh, a connection cap of
# 8 with a reserve of 2 and the visitor cap of 6 (OcuTalon.Web.Public.Status.#VISITORCAP). The count is the marked, not timed-out
# sessions of IRIS's CSP session store, so the unit has a stack of its own and it is the only one that holds six proxied sessions at once.
# In this order:
#   - the start: the log ends ready;
#   - the proxy address is set to the address that IRIS sees for this host's requests (host_address, set_proxy of lib-online.sh), so that
#     every request of the browser step and of the curl sign-ins is proxied and counted under its X-Forwarded-For; the precondition is that
#     one curl sign-in writes one counter row for its forwarded address, else the unit dies naming the address;
#   - the browser step: the project online-visitors of web/playwright.config.ts (web/e2e-online/visitors/), case V1: the 6th visitor gets
#     in and the 7th sees Demo busy, the probe's path never counts, a sign-out and the CSP timeout leave the count, Visual Trace opens at a
#     full house through the trace form of the status, and the status answers each query form (matrix rows 1 to 6 and 9);
#   - row 7, every reset starts at 0: IRIS's ClearSessionsOnRestart reads 1; the plain status is not busy before the row's own sign-ins
#     (a session that the browser step left signed in leaves the count at its 120 s timeout, so the read is repeated for up to 150 s);
#     the timeout of /ocutalon is set to 3600 s, so that only an emptied session store can read 0; six proxied curl sign-ins from six addresses make the plain status busy; the timeout goes back to
#     120 s and is read back; IRIS restarts; after ready the plain status is not busy with no marker header, a proxied sign-in gets the
#     shell once the proxy address is set again, and the six jars' /state answer 401;
#   - the proxy address goes back to its start value and is read back, and the timeout is back at 120 s, on every path that reaches
#     that step; a die before it leaves the stack to the EXIT trap, which removes the project.
# MEASURED lines give the browser step's seconds, the restart's seconds and the unit's seconds. Every wait ends by the overall deadline
# (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI; run the unit with 1200 locally); the browser run's global timeout is what is
# left of it minus 20 s. The project is removed by the EXIT trap, and no password is printed.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs docker compose, the build 154 base image (IRIS_IMAGE), Node 24.15 or
# later, curl, the built web bundle and Chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-visitors
live_web_port || exit 1

base="http://127.0.0.1:$web_port"
online_values
resume_ref=
online_override

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

# --- the proxy address, and the proxied precondition ---

host_ip=$(host_address)
echo "MEASURED REMOTE_ADDR of the host's requests, derived from the container's default gateway: ${host_ip:-<none>}"
if [ -z "$host_ip" ] || [ "$(set_proxy "$host_ip")" != "$host_ip" ]; then
  die "the host's address could not be derived ('${host_ip:-}') or the proxy address could not be set"
fi
precondition_address=198.51.100.70
jar="$tmp/jar.precondition"
: > "$jar"
online_signin "$jar" "$precondition_address" "" > /dev/null
logout_all "$jar" /ocutalon/
if [ "$(counter_rows "$precondition_address")" != 1 ]; then
  set_proxy "$proxy_start" > /dev/null
  die "a sign-in from $host_ip with X-Forwarded-For $precondition_address wrote no counter row, so $host_ip is not the address that IRIS sees for this host's requests"
fi
pass "a proxied sign-in wrote one counter row for its forwarded address (the proxy address is $host_ip)"

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
    npm --prefix web run e2e:online-visitors -- "$@" > "$e2e_log" 2>&1
}
browser_started=$SECONDS
if [ $((deadline - SECONDS)) -lt 420 ]; then
  fail "the browser step: only $((deadline - SECONDS)) s of the deadline are left (V1 needs about 300 s)"
else
  run_e2e
  e2e_status=$?
  echo "MEASURED Story 29.7: the browser step took $((SECONDS - browser_started)) s; the unit has run $SECONDS s at this point"
  grep -h '^MEASURED ' "$e2e_log" | redact
  if [ "$e2e_status" -eq 0 ] && grep -Eq '(^|[^0-9])1 passed' "$e2e_log" && ! grep -Eq '[0-9]+ skipped' "$e2e_log"; then
    show_log 12
    pass "V1 passes ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
  else
    show_log 80
    if grep -q "Executable doesn't exist" "$e2e_log"; then
      echo "  a browser is missing: run npx --prefix web playwright install chromium"
    fi
    fail "the specs of the online-visitors project failed or did not run exactly once (exit $e2e_status)"
  fi
fi

# --- row 7: every reset starts at 0 ---

# set_app_timeout <seconds>: sets the CSP session timeout of /ocutalon and prints what it reads back.
set_app_timeout() {
  printf '%s\n' "Set p(\"Timeout\")=$1" 'Set sc=##class(Security.Applications).Modify("/ocutalon",.p)' 'Kill p Set sc=##class(Security.Applications).Get("/ocutalon",.p)' \
    'Write !,"CHK|timeout|",$Get(p("Timeout"))' 'Halt' | session_value %SYS timeout
}
# state_code <jar>: the status code of the API's /state for the jar.
state_code() {
  next_probe
  curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$1" "$base/ocutalon/api/v1/state?probe=$probes"
}

clear_flag=$(printf '%s\n' 'Write !,"CHK|clear|",$SYSTEM.CSP.GetConfig("ClearSessionsOnRestart")' 'Halt' | session_value %SYS clear)
if [ "$clear_flag" = 1 ]; then
  pass "row 7: IRIS's ClearSessionsOnRestart reads 1"
else
  fail "row 7: ClearSessionsOnRestart reads '$clear_flag' (wanted 1)"
fi

waited=0
start_state=$(status_read)
while [ "$start_state" != "false none 200" ] && [ "$waited" -lt 150 ] && [ $((deadline - SECONDS)) -gt 180 ]; do
  sleep 5
  waited=$((waited + 5))
  start_state=$(status_read)
done
if [ "$start_state" = "false none 200" ]; then
  pass "row 7: before the row's sign-ins the plain status is not busy (read after $waited s)"
else
  fail "row 7: before the row's sign-ins the plain status read '$start_state' after $waited s, so the browser step left visitors counted"
fi

six_jars=()
six_shells=0
if [ "$(set_app_timeout 3600)" = 3600 ]; then
  pass "row 7: the CSP session timeout of /ocutalon is 3600 s for the six sessions"
else
  fail "row 7: the CSP session timeout of /ocutalon could not be set to 3600"
fi
for i in 1 2 3 4 5 6; do
  jar="$tmp/jar.row7.$i"
  : > "$jar"
  online_signin "$jar" "198.51.100.8$i" "" > /dev/null
  six_jars+=("$jar")
  if grep -q '<app-root' "$jar.b" 2>/dev/null; then six_shells=$((six_shells + 1)); fi
done
before_restart=$(status_read)
if [ "$six_shells" = 6 ] && [ "$before_restart" = "true 1 200" ]; then
  pass "row 7: six proxied sign-ins from six addresses get the shell, and the plain status is busy with the marker header"
else
  fail "row 7: $six_shells of 6 proxied sign-ins got the shell, and the plain status read '$before_restart' (wanted 'true 1 200')"
fi
if [ "$(set_app_timeout 120)" = 120 ]; then
  pass "row 7: the timeout of /ocutalon is back at 120 s"
else
  fail "row 7: the timeout of /ocutalon could not be put back to 120 s"
fi

restart_started=$SECONDS
dc restart iris > /dev/null 2>&1
if ! wait_started_ready 300; then
  start_log | tail -n 20 | cut -c1-200 | redact
  die "row 7: the restart did not end ready within 300 s"
fi
restart_seconds=$((SECONDS - restart_started))
after_restart=$(status_read)
if [ "$after_restart" = "false none 200" ]; then
  pass "row 7: after the restart the plain status is not busy and carries no marker header"
else
  fail "row 7: after the restart the plain status read '$after_restart' (wanted 'false none 200')"
fi
if [ "$(set_proxy "$host_ip")" = "$host_ip" ]; then
  jar="$tmp/jar.row7.after"
  : > "$jar"
  online_signin "$jar" "198.51.100.90" "" > /dev/null
  if grep -q '<app-root' "$jar.b" 2>/dev/null; then
    pass "row 7: with the proxy address set again a proxied sign-in gets the shell"
  else
    fail "row 7: after the restart a proxied sign-in did not get the shell"
  fi
  logout_all "$jar" /ocutalon/
else
  fail "row 7: the proxy address could not be set again after the restart"
fi
gone=0
for jar in "${six_jars[@]}"; do
  if [ "$(state_code "$jar")" = 401 ]; then gone=$((gone + 1)); fi
done
if [ "$gone" = 6 ]; then
  pass "row 7: the six sessions are gone: each jar's /state answers 401"
else
  fail "row 7: only $gone of the six jars' /state answered 401 after the restart"
fi
echo "MEASURED Story 29.7: the restart took $restart_seconds s to ready"

# --- the proxy address and the timeout are back ---

if [ "$(set_proxy "$proxy_start")" = "$proxy_start" ]; then
  pass "the proxy address is back to its start value"
else
  fail "the proxy address could not be put back to $proxy_start"
fi
if [ "$(set_app_timeout 120)" = 120 ]; then
  pass "the timeout of /ocutalon reads 120 s"
else
  fail "the timeout of /ocutalon does not read 120 s"
fi
echo "MEASURED Story 29.7: the unit took $SECONDS s"

if [ "$fails" -ne 0 ]; then
  echo "test-online-visitors: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-visitors: all checks passed"
