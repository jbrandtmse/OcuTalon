#!/usr/bin/env bash
# Live test that the heartbeat task resumes itself when it comes back Suspended (Story 8.8; AC 1, 2 and 4; FR-32, AD-18, AD-19, AD-22,
# AD-23; DW-1018): builds the image and starts it in one throwaway compose project with the after-start script active and no model key,
# and then
#   - the first start: the heartbeat task exists, is not suspended, and its id, schedule, RunAsUser and the number of tasks of its name
#     are read;
#   - the task is suspended (Suspended 1, as on the 1.0.5 demo) and the container is stopped and started again (restart 1, plain). The
#     after-start log has STEP Reconcile OK and exactly one line "WARN Reconcile the task "OcuTalon heartbeat" was suspended, so it was
#     resumed"; within 120 s of the start ending ready the task's stored Suspended is 0 and the heartbeatTick mark holds a tick taken at
#     or after the container's start; the task has the same id, schedule and RunAsUser, and there is still one task of that name;
#   - restart 2, plain, with the task running: the log has STEP Reconcile OK and no such WARN line, and the task is unchanged.
# The checks assert order and outcome, never a number of seconds (NFR-10): the 120 s are the bound of the wait, and the restart and first
# tick times are printed as TIMING lines. The event log of the whole run holds no error and no alert. The project is unique, publishes
# no host port and receives no keys. An EXIT trap removes the project with its volume and images. Every wait ends by the run's overall
# deadline. Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
# On a loaded developer machine the run can pass lib-live.sh's default overall deadline (540 s): run it with OCUTALON_LIVE_DEADLINE=1200, the value CI uses.
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t88h
unset OCUTALON_EVAL
run_begun=$SECONDS

TASK="OcuTalon heartbeat"
RESUME_LINE="WARN Reconcile the task \"$TASK\" was suspended, so it was resumed"

# --- helpers ---

# hb_state: the heartbeat task as one line: id|schedule fields|RunAsUser|number of tasks of its name|stored Suspended|tick mark. The
# schedule fields are those of Test.Schedule.Heartbeat ScheduleOf without Suspended. A session that did not answer prints nothing.
hb_state() {
  printf '%s\n' \
    'Set H="OcuTalon.Test.Schedule.Heartbeat",id=##class(%SYS.Task).FindId("OcuTalon heartbeat"),t=##class(%SYS.Task).%OpenId(id)' \
    'If $IsObject(t) { Write !,"CHK|hb|",id,"|",$Replace($ClassMethod(H,"ScheduleOf",t),"Suspended="_t.Suspended_";",""),"|",t.RunAsUser,"|",$ClassMethod(H,"TaskCount","OcuTalon heartbeat"),"|",##class(%SYS.Task).SuspendedGetStored(id),"|",##class(OcuTalon.Data.StatusMark).Get("heartbeatTick") } Else { Write !,"CHK|hb|missing" }' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|hb|//p' | tail -n 1
}

# field <line> <n>: the n-th |-separated field of the line.
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# same <line> <line>: the id, schedule, RunAsUser and task count (fields 1 to 4) of the two state lines are equal.
same() { [ -n "$1" ] && [ "$(field "$1" 1-4)" = "$(field "$2" 1-4)" ]; }

# resumed_since <container start stamp>: the task is at 0 and its tick mark is at or after the stamp (ISO UTC text, compared as text).
resumed_since() {
  local s tick
  s=$(hb_state)
  [ -n "$s" ] && [ "$(field "$s" 5)" = 0 ] || return 1
  tick=$(field "$s" 6)
  [ -n "$tick" ] || return 1
  [ "$(printf '%s\n' "$tick" "${1}Z" | LC_ALL=C sort | head -n 1)" = "${1}Z" ]
}

# --- the first start ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200
  die "the first start did not end ready within $LIVE_FIRST_START_WAIT s"
fi
pass "the first start ended ready"

first=$(hb_state)
if [ -n "$first" ] && [ "$(field "$first" 1)" != missing ] && [ "$(field "$first" 4)" = 1 ] && [ "$(field "$first" 5)" = 0 ]; then
  pass "the first start: one task $TASK, not suspended"
else
  printf '%s\n' "  state: $first"
  die "the first start: no single, running task $TASK"
fi

# --- suspend ---

printf '%s\n' \
  'Set id=##class(%SYS.Task).FindId("OcuTalon heartbeat")' \
  'Write !,"CHK|suspend|",$SYSTEM.Status.IsOK(##class(%SYS.Task).Suspend(id,1))' \
  'Halt' | iris_script OCUTALON > /dev/null
suspended=$(hb_state)
if [ "$(field "$suspended" 5)" = 1 ]; then
  pass "the task is suspended (stored Suspended 1)"
else
  printf '%s\n' "  state: $suspended"
  die "the task could not be suspended"
fi

# --- restart 1, the task suspended ---

dc stop iris >/dev/null 2>&1
t0=$SECONDS
dc start iris >/dev/null 2>&1
if ! wait_started_ready 300; then
  start_log | tail -n 30 | cut -c1-200
  die "restart 1: the start did not end ready within 300 s"
fi
ready1=$SECONDS
restart1_s=$((ready1 - t0))
started1=$(started_at | cut -c1-19)
echo "TIMING restart 1 (task suspended): ${restart1_s}s to ready"
pass "restart 1: the start ended ready"
if log_steps | grep -qx 'STEP Reconcile OK' && [ "$(start_log | grep -cxF "$RESUME_LINE")" = 1 ]; then
  pass "restart 1: the log has STEP Reconcile OK and exactly one line saying that the task was resumed"
else
  start_log | grep -E '^(STEP Reconcile|WARN)' | cut -c1-200 | sed 's/^/  /'
  fail "restart 1: the log has no STEP Reconcile OK, or not exactly one '$RESUME_LINE' line"
fi
if wait_until 120 resumed_since "$started1"; then
  echo "TIMING first tick $((SECONDS - ready1))s after ready"
  pass "restart 1: the task is at 0 and the tick mark holds a tick taken after the start, within 120 s of ready"
else
  printf '%s\n' "  state: $(hb_state)" "  started: $started1"
  fail "restart 1: the task is not at 0, or no tick was taken after the start, within 120 s of ready"
fi
after1=$(hb_state)
if same "$after1" "$first"; then
  pass "restart 1: the task has the same id, schedule and RunAsUser, and there is one task of that name"
else
  printf '%s\n' "  before: $first" "  after:  $after1"
  fail "restart 1: the task's id, schedule, RunAsUser or count changed"
fi

# --- restart 2, the task running ---

dc stop iris >/dev/null 2>&1
t0=$SECONDS
dc start iris >/dev/null 2>&1
if ! wait_started_ready 300; then
  start_log | tail -n 30 | cut -c1-200
  die "restart 2: the start did not end ready within 300 s"
fi
restart2_s=$((SECONDS - t0))
echo "TIMING restart 2 (task running): ${restart2_s}s to ready"
pass "restart 2: the start ended ready"
if log_steps | grep -qx 'STEP Reconcile OK' && ! start_log | grep -q '^WARN Reconcile the task'; then
  pass "restart 2: the log has STEP Reconcile OK and no line about the task"
else
  start_log | grep -E '^(STEP Reconcile|WARN)' | cut -c1-200 | sed 's/^/  /'
  fail "restart 2: the log has no STEP Reconcile OK, or a WARN Reconcile line about the task"
fi
after2=$(hb_state)
if same "$after2" "$first" && [ "$(field "$after2" 5)" = 0 ]; then
  pass "restart 2: the task is unchanged (same id, schedule and RunAsUser) and at 0"
else
  printf '%s\n' "  before: $first" "  after:  $after2"
  fail "restart 2: the task changed or is not at 0"
fi

check_clean_start "after both restarts"

echo "TIMING total $((SECONDS - run_begun))s (restart 1 ${restart1_s}s, restart 2 ${restart2_s}s)"
if [ "$fails" -ne 0 ]; then
  echo "test-heartbeat-restart: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-heartbeat-restart: all checks passed"
