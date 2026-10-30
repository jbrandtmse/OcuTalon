#!/usr/bin/env bash
# Live test of the online demo's allowances (Story 16.9; AD-11, AD-20, AD-31, AD-32; FR-40): builds the image and starts it in one throwaway
# compose project with the online-demo flag on and the test start values of docker/tests/lib-online.sh (the units of test-online-demo.sh and
# test-online-session.sh share them): 50 messages an hour, a daily cost cap of $20. The cap is instance-wide, so this unit has a stack of its
# own. In this order:
#   - the start and the start values: the log ends ready; the public flag and message allowance, the Allowance limits (50 messages, 20 emails)
#     and the daily cap that Budget.State() reads;
#   - the model keys of the three runners are pointed at the CI mock (keys_point of lib-online.sh): Decide checks the key before the cap, so
#     without a key every decision would fall back with no_key and never with daily_cap;
#   - the browser step: the project online-allowance of web/playwright.config.ts (web/e2e-online/allowance/) as the demo account:
#     messages.spec.ts (A1: the 51st message, the 429, the banner, the explained-disabled controls and one notice card; A2: the window clears
#     at retryAt; E1 and E2: the 21st simulated email and its clear) and daily-cap.spec.ts (D1: the cap reached by IRIS's own count, the
#     message once to each session with activity; D2: the gateway's 403 through the mock; AP: an approval and Break the feed while both caps
#     hold);
#   - the IRIS checks after the browser: no capped mark and no refused Turn of the run is left, and the flag and the limits are as they were;
#   - MEASURED lines: the browser step's seconds, the unit's seconds and the 429 round trip that A1 prints.
# Every wait ends by the overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default; run the unit with a longer one when the machine is slow);
# the browser run's global timeout is what is left of it minus 20 s. The project is removed by the EXIT trap, and no password is printed.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs docker compose, the build 154 base image (IRIS_IMAGE), Node 24.15 or
# later, the built web bundle and Chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-allowance
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

# --- the start values ---

check_session "the start values: the flag, the 50 messages and 20 emails an hour, and the daily cap of 20 dollars" OCUTALON \
  "CHK|flag|1
CHK|limit|50
CHK|emails|20
CHK|cap|20" \
  'Write !,"CHK|flag|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
  'Write !,"CHK|limit|",##class(OcuTalon.Core.Allowance).Limit()' \
  'Write !,"CHK|emails|",##class(OcuTalon.Core.Allowance).#EMAILLIMIT' \
  'Write !,"CHK|cap|",##class(OcuTalon.Bridge.Budget).State().cap' \
  'Halt'
check_session "no capped mark of the day exists to begin with" OCUTALON \
  "CHK|mark|0" \
  'Write !,"CHK|mark|",$Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())))' \
  'Halt'

# --- the keys ---

if [ "$(keys_point)" = 1 ]; then
  pass "the runners' model keys point at the CI mock"
else
  die "the runners' model keys could not be pointed at the CI mock"
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
    npm --prefix web run e2e:online-allowance -- "$@" > "$e2e_log" 2>&1
}
browser_started=$SECONDS
if [ $((deadline - SECONDS)) -lt 120 ]; then
  fail "the browser step: only $((deadline - SECONDS)) s of the deadline are left"
else
  run_e2e
  e2e_status=$?
  echo "MEASURED Story 16.9 Task 0 (b): the browser step took $((SECONDS - browser_started)) s; the unit has run $SECONDS s at this point"
  grep -h '^MEASURED ' "$e2e_log" | redact
  if [ "$e2e_status" -eq 0 ]; then
    show_log 20
    pass "the specs of the online-allowance project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
  else
    show_log 80
    if grep -q "Executable doesn't exist" "$e2e_log"; then
      echo "  a browser is missing: run npx --prefix web playwright install chromium"
    fi
    fail "the specs of the online-allowance project failed (exit $e2e_status)"
  fi
fi

# --- the IRIS checks after the browser ---

check_session "after the browser step: the day is not marked, the flag and the limits are as they were, and no refused Turn is left" OCUTALON \
  "CHK|mark|0
CHK|flag|1
CHK|limit|50
CHK|refused|0" \
  'Write !,"CHK|mark|",$Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())))' \
  'Write !,"CHK|flag|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
  'Write !,"CHK|limit|",##class(OcuTalon.Core.Allowance).Limit()' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE State = ?","refused") Do rs.%Next() Write !,"CHK|refused|",rs.%GetData(1)' \
  'Halt'
echo "MEASURED Story 16.9 Task 0 (b): the unit took $SECONDS s"

if [ "$fails" -ne 0 ]; then
  echo "test-online-allowance: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-allowance: all checks passed"
