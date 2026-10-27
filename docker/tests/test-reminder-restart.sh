#!/usr/bin/env bash
# Live test of the reminders across an IRIS restart and an in-place upgrade (Story 8.5; AC 1, 2, 3, 5 and 6; FR-6, FR-34, NFR-10,
# NFR-16, NFR-17, AD-1, AD-5, AD-18, AD-22, AD-23, AD-26): builds the image and starts it in one throwaway compose project with the
# after-start script active and no model key, seeds one session with reminders, and then
#   - restart 1, plain: stops the container before the first reminder is due, waits until that reminder is past due, and starts it
#     again. Then
#       - R_due (set through the product, due while IRIS was down, its waiter survived the restart) fires once, late: Late 1, one
#         ReminderTimer to Notify request made at or after the start, with reminder.late and the slots time, text and dueAt, one web
#         card and one phone message with the catalog's late text, and the card in the chat of /state;
#       - R_lostdue (a pending row with no waiter, due while IRIS was down) fires the same way, through a waiter that the Reconcile
#         step started from HeartbeatIn;
#       - R_far (pending, due much later, a waiter) keeps its waiter, its start header and its TraceHeaderId, and the rail lists it
#         with the same dueAt;
#       - R_lost (pending, due much later, no waiter) gets a new waiter: a start header from HeartbeatIn, the first header of its own
#         trace session under the session's TraceRef, which the row's TraceHeaderId names, and the rail links to it;
#       - R_fired and R_cancelled are not touched, and R_orphan (pending, its session gone) is skipped: the after-start log has
#         STEP Reconcile OK and a WARN Reconcile line naming it;
#   - restart 2, an in-place upgrade: a reminder R_future is set, and the container is recreated with OCUTALON_DEV=1, which makes the
#     start run the package load of an upgrade. The log has STEP package loaded (dev), ReminderTimer's compiled time has moved, and
#     R_future, R_far and R_lost have the waiters, the TraceHeaderIds and the start headers they had before. R_future then fires once
#     from its pre-upgrade waiter, not late, never before its due time, with reminder.due, one web card and one phone message, and
#     it has left the rail.
# The checks assert order and outcome, never a number of seconds (NFR-10): the times that the script waits for are bounds on a wait, and
# the restart times are printed. Reconcile re-arms a waiter that the platform lost, never a living one, and the run does not assert on
# the start headers of R_due, whose waiter can look gone to a Reconcile that runs while it wakes.
# The event log of the whole run holds no error and no alert. The project is unique, publishes no host port and receives no keys. An
# EXIT trap removes the project with its volume and images. Every wait ends by the run's overall deadline.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t85r
unset OCUTALON_EVAL
run_begun=$SECONDS

# --- helpers ---

# field <line> <n>: the n-th |-separated field of the line.
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# expect_eq <label> <actual> <expected>
expect_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    printf '%s\n' "  actual:   $2" "  expected: $3"
    fail "$1"
  fi
}

# rem_state <ref>: the row and the waiters of a reminder as one line: state|late|traceHeaderId|waiting|starts|last source|last
# session|last superSession|last target, where waiting is the number of live ReminderTimer instances and starts the number of
# ReminderStart headers, and the last* fields are those of the newest start header.
rem_state() {
  printf '%s\n' \
    'Set RF="OcuTalon.Test.Schedule.ReminderFixture"' \
    "Set ref=\"$1\",row=##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)" \
    'Set h=$ClassMethod(RF,"StartHeaders",ref),n=h.%Size(),l=$Select(n:h.%Get(n-1),1:{})' \
    'Write !,"CHK|rem|",row.State,"|",row.Late,"|",row.TraceHeaderId,"|",$ClassMethod(RF,"WaitingCount",ref),"|",n,"|",l.source,"|",l.sessionId,"|",l.superSession,"|",l.target' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|rem|//p'
}

# rail_lines <session>: one line per reminder of the rail of /state: ref|dueAt|traceHeaderId|1 when traceUrl ends with that id.
rail_lines() {
  printf '%s\n' \
    "Set b=##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(\"$1\")),i=b.rail.reminders.%GetIterator()" \
    'While i.%GetNext(,.x) { Set u=x.traceUrl,t=x.traceHeaderId Write !,"CHK|rail|",x.ref,"|",x.dueAt,"|",t,"|",$Select(u="":0,1:($Extract(u,$Length(u)-$Length(t)+1,$Length(u))=t)) }' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|rail|//p'
}

# check_rail <label> <session> <ref> <dueAt> <traceHeaderId, or "-" for none>: the rail lists the reminder with its dueAt and, unless
# the id is "-", a trace link that ends with the given id.
check_rail() {
  local lines line
  lines=$(rail_lines "$2")
  if [ "$5" = "-" ]; then
    line=$(printf '%s\n' "$lines" | grep "^$3|$4|" | head -n 1)
  else
    line="$3|$4|$5|1"
  fi
  if [ -n "$line" ] && printf '%s\n' "$lines" | grep -qxF -- "$line"; then
    pass "$1: the rail lists the reminder with its dueAt$([ "$5" = "-" ] || echo " and a trace link to its waiter")"
  else
    printf '%s\n' "  rail: $(printf '%s' "$lines" | tr '\n' ' ')" "  wanted: $3|$4|$5"
    fail "$1: the rail does not list the reminder with its dueAt$([ "$5" = "-" ] || echo " and a trace link to its waiter")"
  fi
}

# fired_lines <ref> <session> <late 0|1> <lower bound> <origin trace id or "">: what a fired reminder left, as CHK lines (see
# fired_expected). The lower bound is a UTC time to the second, YYYY-MM-DDThh:mm:ss, that the Notification must not precede.
fired_lines() {
  printf '%s\n' \
    'Set F="OcuTalon.Test.Data.Fixture",RF="OcuTalon.Test.Schedule.ReminderFixture",C="OcuTalon.Msg.Catalog"' \
    "Set ref=\"$1\",s=\"$2\",late=$3,lower=\"$4\",origin=\"$5\"" \
    'Set row=##class(OcuTalon.Data.Reminder).RefIndexOpen(ref),text=row.Text,due=row.DueAt,key=$Select(late:"reminder.late",1:"reminder.due"),want=$Select(late:"Reminder (late; it was due at ",1:"Reminder: ")' \
    'If late { Set o={"time":(due),"text":(text),"dueAt":(due)} } Else { Set o={"text":(text),"dueAt":(due)} }' \
    'Set slots=o.%ToJSON()' \
    'Write !,"CHK|row|",row.State,"|",row.Late' \
    'Set h=$ClassMethod(RF,"StartHeaders",ref),k=0,first="",originN=0' \
    'For i=0:1:h.%Size()-1 { Set b=$ClassMethod(F,"Between",$ClassMethod(F,"SessionHeaders",h.%Get(i).sessionId),1,"ReminderTimer","Notify") Set k=k+b.%Size() Set:(k>0)&&(first="") first=b.%Get(0) Set:h.%Get(i).sessionId=origin originN=originN+b.%Size() }' \
    'If k { Set nt=##class(OcuTalon.Msg.Notification).%OpenId(first.bodyId),hd=##class(Ens.MessageHeader).%OpenId(first.id),made=$Translate($Piece(hd.TimeCreated,".",1)," ","T") Write !,"CHK|notify|",k,"|",nt.CatalogKey,"|",(nt.Slots=slots),"|",('"'"'(lower]made)) } Else { Write !,"CHK|notify|0" }' \
    'Write !,"CHK|origin|",$Select(origin="":"-",1:originN)' \
    'Set onl=##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"),cards=##class(OcuTalon.Data.Ownership).RecentNotices(s,50),nw=0,eq=0,pre=0,cardtext=""' \
    'For i=1:1:cards.Count() { Set c=cards.GetAt(i) If (c.Kind="reminder")&&(c.Text[text) { Set nw=nw+1,cardtext=c.Text,eq=(c.Text=$ClassMethod(C,"RenderAt",key,slots,"web",c.RecordedAt,onl)),pre=($Extract(c.Text,1,$Length(want))=want) } }' \
    'Write !,"CHK|web|",nw,"|",eq,"|",pre' \
    'Set msgs=##class(OcuTalon.Data.Ownership).RecentPhone(s,50),np=0,peq=0' \
    'For i=1:1:msgs.Count() { Set m=msgs.GetAt(i) If m.Text[text { Set np=np+1,peq=(m.Text=$ClassMethod(C,"RenderAt",key,slots,"phone",m.CreatedAt,onl)) } }' \
    'Write !,"CHK|phone|",np,"|",peq' \
    'Set st=##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(s))' \
    'Write !,"CHK|chat|",((cardtext'"'"'="")&&(st.chat.%ToJSON()[cardtext))' \
    'Halt' | iris_script OCUTALON
}

# fired_expected <late 0|1> <origin trace id or "">: the lines of fired_lines for a reminder that fired once, on every channel.
fired_expected() {
  local key=reminder.due origin=-
  [ "$1" = 1 ] && key=reminder.late
  [ -n "$2" ] && origin=1
  printf '%s\n' "CHK|row|fired|$1" "CHK|notify|1|$key|1|1" "CHK|origin|$origin" "CHK|web|1|1|1" "CHK|phone|1|1" "CHK|chat|1"
}

fired_ok() { [ "$(fired_lines "$@")" = "$(fired_expected "$3" "$5")" ]; }

# await_fired <label> <max s> <ref> <session> <late> <lower bound> <origin trace id or "">: within the time, the reminder is fired once,
# with the late flag, one Notification (with the key and slots of the flag, made at or after the bound), one web card and one phone
# message with the catalog text, and the card in the chat of /state.
await_fired() {
  local label=$1 max=$2
  shift 2
  if wait_until "$max" fired_ok "$@"; then
    pass "$label: fired once, $([ "$3" = 1 ] && echo late || echo "not late"), on every channel, with the catalog text"
  else
    printf '%s\n' "  actual:" "$(fired_lines "$@" | sed 's/^/    /')" "  expected:" "$(fired_expected "$3" "$5" | sed 's/^/    /')"
    fail "$label: not fired once with one Notification, one web card and one phone message within $max s"
  fi
}

# --- the first start ---

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

# --- the reminders ---

# One session and seven reminders. The two that are due soon are made last, so that the stop comes well before the first is due.
# CHK|rem|<name>|<ref>|<dueAt>|<seconds of dueAt>|<TraceHeaderId>, and the seconds of now, to put the due times on this host's clock.
seeded_host=$(date -u +%s)
seeded=$(printf '%s\n' \
  'Set F="OcuTalon.Test.Data.Fixture",RF="OcuTalon.Test.Schedule.ReminderFixture",T="OcuTalon.Data.Time"' \
  'Set s=$ClassMethod(F,"Session","ZzReminderRestart"),tr=##class(OcuTalon.Data.Session).RefIndexOpen(s).TraceRef' \
  'Write !,"CHK|session|",s,"|",tr' \
  'Set now=$ClassMethod(T,"NowUtc")' \
  'Set r("far")=$ClassMethod(RF,"Set",s,"zz restart far",86400).ref' \
  'Set r("lost")=$ClassMethod(F,"Reminder",s,$ClassMethod(T,"AddSeconds",now,86410),"pending",{"Text":"zz restart pending lost"})' \
  'Set r("fired")=$ClassMethod(F,"Reminder",s,"2030-01-01T10:00:01Z","fired",{"Text":"zz restart fired"})' \
  'Set r("cancelled")=$ClassMethod(F,"Reminder",s,"2030-01-01T10:00:02Z","cancelled",{"Text":"zz restart cancelled"})' \
  'Set r("orphan")=$ClassMethod(F,"Reminder",##class(OcuTalon.Bridge.Ids).NewRef(),$ClassMethod(T,"AddSeconds",now,86420),"pending",{"Text":"zz restart orphan"})' \
  'Set r("lostdue")=$ClassMethod(F,"Reminder",s,$ClassMethod(T,"AddSeconds",$ClassMethod(T,"NowUtc"),65),"pending",{"Text":"zz restart lostdue"})' \
  'Set r("due")=$ClassMethod(RF,"Set",s,"zz restart due",60).ref' \
  'For n="due","far","lostdue","lost","fired","cancelled","orphan" { Set row=##class(OcuTalon.Data.Reminder).RefIndexOpen($Get(r(n))) Write !,"CHK|rem|",n,"|",$Get(r(n)),"|",$Select($IsObject(row):row.DueAt_"|"_$ClassMethod(T,"Seconds",row.DueAt)_"|"_row.TraceHeaderId,1:"||") }' \
  'Write !,"CHK|now|",$ClassMethod(T,"Seconds",$ClassMethod(T,"NowUtc"))' \
  'Halt' | iris_script OCUTALON)
seeded_host_end=$(date -u +%s)
S=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|session|\([^|]*\)|.*/\1/p')
S_TRACE=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|session|[^|]*|//p')
seeded_now=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|now|//p')
# rec <name> <field>: the field of the seeded reminder: 1 ref, 2 dueAt, 3 seconds of dueAt, 4 TraceHeaderId.
rec() { printf '%s\n' "$seeded" | sed -n "s/^CHK|rem|$1|//p" | cut -d'|' -f"$2"; }
ok_seed=1
for n in due far lostdue lost fired cancelled orphan; do
  [ -n "$(rec $n 1)" ] || ok_seed=0
done
[ -n "$S" ] && [ -n "$S_TRACE" ] && [ -n "$seeded_now" ] && [ -n "$(rec due 4)" ] && [ -n "$(rec far 4)" ] || ok_seed=0
if [ "$ok_seed" != 1 ]; then
  printf '%s\n' "$seeded" | sed 's/^/  /'
  die "the session and the seven reminders could not be seeded"
fi
R_due=$(rec due 1) R_far=$(rec far 1) R_lostdue=$(rec lostdue 1) R_lost=$(rec lost 1)
R_fired=$(rec fired 1) R_cancelled=$(rec cancelled 1) R_orphan=$(rec orphan 1)
due_at=$(rec due 2)
# The host time of R_due's due time lies between these two bounds: the host clock before the seeding call (the earlier bound, for the
# "stopped before it was due" check) and after it (the later bound, for the wait until it is past due).
due_epoch=$((seeded_host + $(rec due 3) - seeded_now))
due_epoch_late=$((seeded_host_end + $(rec due 3) - seeded_now))
far_at=$(rec far 2) lost_at=$(rec lost 2) far_trace=$(rec far 4) due_trace=$(rec due 4)
far_before=$(rem_state "$R_far")
lost_before=$(rem_state "$R_lost")
expect_eq "seeded: R_far has one live waiter from ReminderOps, R_lost none" "$(field "$far_before" 4)|$(field "$far_before" 5)|$(field "$far_before" 6)|$(field "$lost_before" 4)|$(field "$lost_before" 5)|$(field "$lost_before" 3)" "1|1|ReminderOps|0|0|"
check_rail "seeded R_due" "$S" "$R_due" "$due_at" "$due_trace"
check_rail "seeded R_far" "$S" "$R_far" "$far_at" "$far_trace"
check_rail "seeded R_lostdue" "$S" "$R_lostdue" "$(rec lostdue 2)" "-"
check_rail "seeded R_lost" "$S" "$R_lost" "$lost_at" "-"

# --- restart 1, plain ---

dc stop iris >/dev/null 2>&1
stopped_epoch=$(date -u +%s)
if [ "$stopped_epoch" -lt "$due_epoch" ]; then
  pass "restart 1: IRIS stopped before R_due ($R_due) was due"
else
  fail "restart 1: IRIS stopped $((stopped_epoch - due_epoch)) s after R_due ($R_due, due $due_at) was due, so it was not due while IRIS was down"
fi
now_epoch=$(date -u +%s)
if [ "$now_epoch" -lt $((due_epoch_late + 15)) ]; then
  sleep $((due_epoch_late + 15 - now_epoch))
fi
t0=$SECONDS
dc start iris >/dev/null 2>&1
if ! wait_started_ready 300; then
  start_log | tail -n 30 | cut -c1-200
  die "restart 1: the start did not end ready within 300 s"
fi
restart1_s=$((SECONDS - t0))
started1=$(started_at | cut -c1-19)
echo "TIMING restart 1 (plain): ${restart1_s}s to ready"
pass "restart 1: the start ended ready"
if log_steps | grep -qx 'STEP Reconcile OK' && start_log | grep -q "^WARN Reconcile .*$R_orphan"; then
  pass "restart 1: the log has STEP Reconcile OK and a WARN Reconcile line naming R_orphan"
else
  start_log | grep -E '^(STEP Reconcile|WARN)' | cut -c1-200 | sed 's/^/  /'
  fail "restart 1: the log has no STEP Reconcile OK, or no WARN Reconcile line naming R_orphan ($R_orphan)"
fi

await_fired "restart 1: R_due (its waiter survived)" 60 "$R_due" "$S" 1 "$started1" ""
await_fired "restart 1: R_lostdue (no waiter)" 60 "$R_lostdue" "$S" 1 "$started1" ""
lostdue_state=$(rem_state "$R_lostdue")
expect_eq "restart 1: R_lostdue's waiter was started by HeartbeatIn under the session's TraceRef" "$(field "$lostdue_state" 5)|$(field "$lostdue_state" 6)|$(field "$lostdue_state" 7)|$(field "$lostdue_state" 8)|$(field "$lostdue_state" 9)" "1|HeartbeatIn|$(field "$lostdue_state" 3)|$S_TRACE|ReminderTimer"

far_after1=$(rem_state "$R_far")
expect_eq "restart 1: R_far is pending with the same TraceHeaderId, one start header from ReminderOps and one waiter" "$(field "$far_after1" 1)|$(field "$far_after1" 3)|$(field "$far_after1" 4)|$(field "$far_after1" 5)|$(field "$far_after1" 6)" "pending|$far_trace|1|1|ReminderOps"
check_rail "restart 1: R_far" "$S" "$R_far" "$far_at" "$far_trace"
lost_after1=$(rem_state "$R_lost")
lost_trace=$(field "$lost_after1" 3)
if [ -n "$lost_trace" ] && [ "$lost_trace" != "$(rec lost 4)" ]; then
  expect_eq "restart 1: R_lost is pending with a new waiter: one start header from HeartbeatIn, the first of its own session under the session's TraceRef, the row's TraceHeaderId" \
    "$(field "$lost_after1" 1)|$(field "$lost_after1" 4)|$(field "$lost_after1" 5)|$(field "$lost_after1" 6)|$(field "$lost_after1" 7)|$(field "$lost_after1" 8)|$(field "$lost_after1" 9)" \
    "pending|1|1|HeartbeatIn|$lost_trace|$S_TRACE|ReminderTimer"
else
  fail "restart 1: R_lost has no new TraceHeaderId ('$lost_trace')"
fi
check_rail "restart 1: R_lost" "$S" "$R_lost" "$lost_at" "$lost_trace"
for n in fired cancelled; do
  ref=$(rec $n 1)
  st=$(rem_state "$ref")
  expect_eq "restart 1: R_$n is unchanged: $n, no TraceHeaderId, no waiter, no start header" "$(field "$st" 1)|$(field "$st" 3)|$(field "$st" 4)|$(field "$st" 5)" "$n||0|0"
done
orphan_state=$(rem_state "$R_orphan")
expect_eq "restart 1: R_orphan is pending with no waiter and no start header" "$(field "$orphan_state" 1)|$(field "$orphan_state" 3)|$(field "$orphan_state" 4)|$(field "$orphan_state" 5)" "pending||0|0"

# --- R_future ---

future_secs=$((6 * restart1_s + 60))
[ "$future_secs" -ge 120 ] || future_secs=120
future=$(printf '%s\n' \
  'Set T="OcuTalon.Data.Time",RF="OcuTalon.Test.Schedule.ReminderFixture"' \
  "Set f=\$ClassMethod(RF,\"Set\",\"$S\",\"zz restart future\",$future_secs),now=\$ClassMethod(T,\"Seconds\",\$ClassMethod(T,\"NowUtc\"))" \
  'Write !,"CHK|future|",f.ref,"|",f.dueAt,"|",$ClassMethod(T,"Seconds",f.dueAt),"|",f.traceHeaderId,"|",now' \
  'Write !,"CHK|changed|",##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Schedule.ReminderTimer").TimeChanged' \
  'Halt' | iris_script OCUTALON)
future_host=$(date -u +%s)
future_line=$(printf '%s\n' "$future" | sed -n 's/^CHK|future|//p')
R_future=$(field "$future_line" 1) future_at=$(field "$future_line" 2) future_trace=$(field "$future_line" 4)
future_due_epoch=$((future_host + $(field "$future_line" 3) - $(field "$future_line" 5)))
timer_changed_before=$(printf '%s\n' "$future" | sed -n 's/^CHK|changed|//p')
if [ -n "$R_future" ] && [ -n "$future_trace" ] && [ -n "$timer_changed_before" ]; then
  pass "R_future is set, due $future_secs s after restart 1, with its waiter's TraceHeaderId"
else
  printf '%s\n' "$future" | sed 's/^/  /'
  die "R_future could not be set"
fi
check_rail "R_future" "$S" "$R_future" "$future_at" "$future_trace"
future_before=$(rem_state "$R_future")
far_before2=$(rem_state "$R_far")
lost_before2=$(rem_state "$R_lost")

# --- restart 2, an in-place upgrade ---

printf 'services:\n  iris:\n    environment:\n      OCUTALON_DEV: "1"\n' > "$tmp/dev.yml"
live_add_file "$tmp/dev.yml"
t0=$SECONDS
if ! dc up -d > "$tmp/up2.log" 2>&1; then
  tail -n 20 "$tmp/up2.log"
  die "restart 2: the container could not be recreated with OCUTALON_DEV=1"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "restart 2: the start did not end ready within 400 s"
fi
restart2_s=$((SECONDS - t0))
echo "TIMING restart 2 (upgrade in place): ${restart2_s}s to ready"
pass "restart 2: the start ended ready"
if start_log | grep -qx 'STEP package loaded (dev)'; then
  pass "restart 2: the log has STEP package loaded (dev), the load of an upgrade"
else
  start_log | grep '^STEP package' | sed 's/^/  /'
  fail "restart 2: the log has no STEP package loaded (dev)"
fi
timer_changed_after=$(printf '%s\n' 'Write !,"CHK|changed|",##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Schedule.ReminderTimer").TimeChanged' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|changed|//p')
if [ -n "$timer_changed_after" ] && [ "$timer_changed_after" \> "$timer_changed_before" ]; then
  pass "restart 2: ReminderTimer was recompiled (its compiled time moved)"
else
  fail "restart 2: ReminderTimer's compiled time did not move ('$timer_changed_before' to '$timer_changed_after')"
fi
before_due=$(printf '%s\n' \
  'Set T="OcuTalon.Data.Time"' \
  "Write !,\"CHK|before|\",(\$ClassMethod(T,\"Seconds\",\$ClassMethod(T,\"NowUtc\"))<\$ClassMethod(T,\"Seconds\",\"$future_at\"))" \
  'Halt' | iris_script OCUTALON | sed -n 's/^CHK|before|//p')
if [ "$before_due" = 1 ]; then
  pass "restart 2: R_future is still in the future after the upgrade"
else
  fail "restart 2: R_future (due $future_at, $future_secs s after restart 1 of ${restart1_s}s) was already due when restart 2 (${restart2_s}s) ended, so the upgrade did not run before it"
fi
future_a=$(rem_state "$R_future") far_a=$(rem_state "$R_far") lost_a=$(rem_state "$R_lost")
expect_eq "restart 2: R_future keeps its waiter, TraceHeaderId and start header" "$future_a" "$future_before"
expect_eq "restart 2: R_far keeps its waiter, TraceHeaderId and start header" "$far_a" "$far_before2"
expect_eq "restart 2: R_lost keeps its waiter, TraceHeaderId and start header" "$lost_a" "$lost_before2"
expect_eq "restart 2: each of the three is pending with exactly one waiter" "$(field "$future_a" 1)$(field "$future_a" 4)|$(field "$far_a" 1)$(field "$far_a" 4)|$(field "$lost_a" 1)$(field "$lost_a" 4)" "pending1|pending1|pending1"
check_rail "restart 2: R_future" "$S" "$R_future" "$future_at" "$future_trace"
check_rail "restart 2: R_far" "$S" "$R_far" "$far_at" "$far_trace"
check_rail "restart 2: R_lost" "$S" "$R_lost" "$lost_at" "$lost_trace"

# --- R_future fires ---

future_wait=$((future_due_epoch + 60 - $(date -u +%s)))
[ "$future_wait" -gt 60 ] || future_wait=60
future_lower=$(printf '%s' "$future_at" | sed 's/Z$//')
await_fired "R_future after the upgrade (its pre-upgrade waiter)" "$future_wait" "$R_future" "$S" 0 "$future_lower" "$future_trace"
waiter_gone() { [ "$(field "$(rem_state "$1")" 4)" = 0 ]; }
wait_until 30 waiter_gone "$R_future" || true
future_after=$(rem_state "$R_future")
expect_eq "R_future: the one fired state, no waiter left" "$(field "$future_after" 1)|$(field "$future_after" 2)|$(field "$future_after" 4)" "fired|0|0"
if rail_lines "$S" | grep -q "^$R_future|"; then
  fail "R_future is still in the rail after it fired"
else
  pass "R_future has left the rail"
fi

# --- the end ---

# Nothing fired again after the later restart: the two reminders of restart 1 still show exactly one firing on every channel.
for pair in "R_due:$R_due" "R_lostdue:$R_lostdue"; do
  if fired_ok "${pair#*:}" "$S" 1 "$started1" ""; then
    pass "end: ${pair%%:*} is still fired once, late, on every channel"
  else
    printf '%s\n' "  actual:" "$(fired_lines "${pair#*:}" "$S" 1 "$started1" "" | sed 's/^/    /')"
    fail "end: ${pair%%:*} did not stay fired once on every channel"
  fi
done

check_clean_start "after both restarts"

echo "TIMING total $((SECONDS - run_begun))s (restart 1 ${restart1_s}s, restart 2 ${restart2_s}s)"
if [ "$fails" -ne 0 ]; then
  echo "test-reminder-restart: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-reminder-restart: all checks passed"
