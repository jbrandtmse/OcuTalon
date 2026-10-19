#!/usr/bin/env bash
# Live test of the Production step across restarts (Story 0.6, matrix rows 19 and 20): builds the image and starts it in one
# throwaway compose project with the after-start script active and no model key, then
#   - row 19, the EvalIn switch: recreates the container with OCUTALON_EVAL=1 in its environment and then without it. With
#     the variable the start ends ready with STEP Production OK, CreateBusinessService("EvalIn") succeeds and the System
#     Default Setting row (OcuTalon.Production, EvalIn, any class, Enabled) is 1. Without it the service is refused as
#     disabled and the row is 0;
#   - row 20, an unclean stop: kills the instance with docker kill -s KILL and starts the container again. The next start ends
#     ready with STEP Production OK, the production is Running again, and every item runs as in the first start (the job
#     check of test-production.sh, row 14). The kill leaves the production Troubled, and the step recovers it: before the
#     kill ^Ens.Suspended, where RecoverProduction names the production it suspends, is empty, and after the next start it
#     names OcuTalon.Production (measured on build 154: a clean stop and CleanProduction leave it empty, so a step that
#     cleans the production instead of recovering it would lose its queued messages and fail this check).
# The first start also has to be a start with no model key that wrote no error to the event log.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its volume and
# images. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t06r

# check_start <label>: this start's log lists STEP Production OK and ends with RESULT OK.
check_start() {
  log_steps > "$tmp/steps.log"
  if grep -qx 'STEP Production OK' "$tmp/steps.log" && tail -n 1 "$tmp/steps.log" | grep -q '^RESULT OK '; then
    pass "$1: the log has STEP Production OK and ends with RESULT OK"
  else
    sed 's/^/  /' "$tmp/steps.log" | tail -n 8
    fail "$1: the log has no STEP Production OK, or does not end with RESULT OK"
  fi
}

# check_eval <label> <enabled 1|0>: EvalIn's row holds the value, and CreateBusinessService("EvalIn") agrees with it.
check_eval() {
  if [ "$2" = 1 ]; then
    check_session "$1: the row is 1 and EvalIn answers CreateBusinessService" OCUTALON \
      "CHK|row|1
CHK|create|1" \
      'Write !,"CHK|row|",##class(Ens.Config.DefaultSettings).%OpenId("OcuTalon.Production||EvalIn||*||Enabled").SettingValue' \
      'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|create|",$SYSTEM.Status.IsOK(sc)' \
      'Halt'
  else
    check_session "$1: the row is 0 and EvalIn is refused as disabled" OCUTALON \
      "CHK|row|0
CHK|refused|1" \
      'Write !,"CHK|row|",##class(Ens.Config.DefaultSettings).%OpenId("OcuTalon.Production||EvalIn||*||Enabled").SettingValue' \
      'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|refused|",($SYSTEM.Status.IsError(sc)&&($SYSTEM.Status.GetErrorText(sc)["is disabled"))' \
      'Halt'
  fi
}

# --- the first start, without the variable ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"
check_start "first start"
check_no_key "first start"
check_clean_start "first start"
check_eval "first start, no variable" 0

# --- row 19: OCUTALON_EVAL=1, then without it ---

printf 'services:\n  iris:\n    environment:\n      OCUTALON_EVAL: "1"\n' > "$tmp/eval.yml"
live_add_file "$tmp/eval.yml"
if ! dc up -d >/dev/null 2>&1; then
  die "row 19 recreate with OCUTALON_EVAL=1 failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 19 the start with OCUTALON_EVAL=1 did not end ready within 200 s"
fi
check_start "row 19, OCUTALON_EVAL=1"
check_eval "row 19, OCUTALON_EVAL=1" 1

live_pop_file
if ! dc up -d >/dev/null 2>&1; then
  die "row 19 recreate without OCUTALON_EVAL failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 19 the start without OCUTALON_EVAL did not end ready within 200 s"
fi
check_start "row 19, no variable"
check_eval "row 19, no variable" 0

# --- row 20: an unclean stop ---

check_session "row 20: before the kill no production is suspended" OCUTALON \
  "CHK|suspended|" \
  'Write !,"CHK|suspended|",$Get(^Ens.Suspended)' \
  'Halt'
killed_start=$(started_at)
docker kill -s KILL "$cid" >/dev/null 2>&1 || die "row 20 the kill failed"
dc start iris >/dev/null 2>&1
cid=$(dc ps -q iris)
if ! wait_started_ready 300; then
  start_log | tail -n 30 | cut -c1-200
  die "row 20 the start after the kill did not end ready within 300 s"
fi
if [ "$(started_at)" != "$killed_start" ]; then
  pass "row 20: the container was killed and started again, and the start ended ready"
else
  fail "row 20: the container did not start again after the kill"
fi
check_start "row 20"
check_session "row 20: the step recovered the Troubled production, and did not clean it" OCUTALON \
  "CHK|suspended|OcuTalon.Production" \
  'Write !,"CHK|suspended|",$Get(^Ens.Suspended)' \
  'Halt'
check_session "row 20: the production is Running again" OCUTALON \
  "CHK|state|OcuTalon.Production|1" \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|state|",n,"|",s' \
  'Halt'
check_items_run "row 20"

if [ "$fails" -ne 0 ]; then
  echo "test-production-restart: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-production-restart: all checks passed"
