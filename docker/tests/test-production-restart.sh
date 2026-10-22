#!/usr/bin/env bash
# Live test of the Production step across restarts (Story 0.6, matrix rows 19 and 20): builds the image and starts it in one
# throwaway compose project with the after-start script active and no model key, then
#   - row 19, the EvalIn switch (Story 0.7, row 14: the CI override passes OCUTALON_EVAL through): recreates the container with
#     OCUTALON_EVAL=1 in the environment of `docker compose up`, with no extra compose file, and then without it. With the
#     variable the start ends ready with STEP Production OK, CreateBusinessService("EvalIn") succeeds and the System Default
#     Setting row (OcuTalon.Production, EvalIn, any class, Enabled) is 1. Without it the service is refused as disabled and the
#     row is 0;
#   - row 20, an unclean stop: kills the instance with docker kill -s KILL and starts the container again. The next start ends
#     ready with STEP Production OK, the production is Running again, and every item runs as in the first start (the job
#     check of test-production.sh, row 14). The kill leaves the production Troubled, and the step recovers it: before the
#     kill ^Ens.Suspended, where RecoverProduction names the production it suspends, is empty, and after the next start it
#     names OcuTalon.Production (measured on build 154: a clean stop and CleanProduction leave it empty, so a step that
#     cleans the production instead of recovering it would lose its queued messages and fail this check).
#     Story 2.2 adds the snapshot: before the kill and again after the next start, the epoch, the chat and the rail that
#     Web.Api.StateBody builds for a session that Test.Data.Fixture seeded with a turn, a check, a pending reminder and a
#     pending approval are printed, and the two must be equal and hold the four fixture refs. Journaling must be enabled
#     (%SYS.Journal.System.GetState() 0), and the journal is synced before the kill, so that the kill cannot lose the seeded
#     rows. The rows are removed afterwards.
# The first start also has to be a start with no model key that wrote no error to the event log.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its volume and
# images. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t06r
unset OCUTALON_EVAL

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

# restart_snapshot <session ref>: the epoch, the chat and the rail that Web.Api.StateBody builds for the session, as one line of
# JSON ("" when the session or the body is missing).
restart_snapshot() {
  printf '%s\n' \
    "Set row=##class(OcuTalon.Data.Session).RefIndexOpen(\"$1\")" \
    'Set b=##class(OcuTalon.Web.Api).StateBody(row)' \
    'Write !,"CHK|snapshot|",{"epoch":(b.epoch),"chat":(b.chat),"rail":(b.rail)}.%ToJSON()' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|snapshot|//p'
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

if ! OCUTALON_EVAL=1 dc up -d >/dev/null 2>&1; then
  die "row 19 recreate with OCUTALON_EVAL=1 failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 19 the start with OCUTALON_EVAL=1 did not end ready within 200 s"
fi
check_start "row 19, OCUTALON_EVAL=1"
check_eval "row 19, OCUTALON_EVAL=1" 1

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
seeded=$(printf '%s\n' \
  'Set F="OcuTalon.Test.Data.Fixture"' \
  'Set s=$ClassMethod(F,"Session","ZzRestartSnapshot")' \
  'Write !,"CHK|session|",s' \
  'Write !,"CHK|refs|",$ClassMethod(F,"Turn",s),",",$ClassMethod(F,"Check",s),",",$ClassMethod(F,"Reminder",s),",",$ClassMethod(F,"Approval",s)' \
  'Halt' | iris_script OCUTALON)
snapshot_session=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|session|//p')
snapshot_refs=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|refs|//p')
snapshot_before=""
if [ -n "$snapshot_session" ] && [ "$(printf '%s' "$snapshot_refs" | tr ',' '\n' | grep -c .)" = 4 ]; then
  snapshot_before=$(restart_snapshot "$snapshot_session")
  pass "row 20: a session with a turn, a check, a pending reminder and a pending approval is seeded"
else
  fail "row 20: the snapshot's fixture rows could not be seeded ('$seeded')"
fi
check_session "row 20: journaling is enabled and the journal is synced to disk before the kill" OCUTALON \
  "CHK|journal|1" \
  'Try { Set state=##class(%SYS.Journal.System).GetState() Do ##class(%SYS.Journal.System).Sync() Write !,"CHK|journal|",(state=0) } Catch e { Write !,"CHK|journal|0" }' \
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

snapshot_after=""
if [ -n "$snapshot_session" ]; then
  snapshot_after=$(restart_snapshot "$snapshot_session")
fi
snapshot_whole=1
for ref in $(printf '%s' "$snapshot_refs" | tr ',' ' '); do
  case $snapshot_before in *"$ref"*) ;; *) snapshot_whole=0 ;; esac
done
if [ -n "$snapshot_before" ] && [ "$snapshot_whole" = 1 ] && [ "$snapshot_before" = "$snapshot_after" ]; then
  pass "row 20: the snapshot's epoch, chat and rail are identical after the kill, and hold the turn, the check, the reminder and the approval"
else
  printf '%s\n' "  before: $(printf '%s' "$snapshot_before" | cut -c1-300)" "  after:  $(printf '%s' "$snapshot_after" | cut -c1-300)"
  fail "row 20: the snapshot's epoch, chat and rail differ after the kill, or miss a fixture row"
fi
check_session "row 20: the snapshot's fixture rows are removed" OCUTALON \
  "CHK|left|0" \
  'Do ##class(OcuTalon.Test.Data.Fixture).Clean()' \
  'Write !,"CHK|left|",$Data(^OcuTalonTest("Fixture"))' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-production-restart: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-production-restart: all checks passed"
