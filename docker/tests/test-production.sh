#!/usr/bin/env bash
# Live test of the production (Story 0.6, matrix rows 13 to 18 and 21): builds the image and starts it in one throwaway
# compose project with the after-start script active and no model key, then checks
#   - row 13, the first start: the log lists STEP Production OK and ends with RESULT OK, Docker reports healthy, the
#     production OcuTalon.Production is Running, and it is not the autostart production (AD-3);
#   - row 14, the items: each of the 25 enabled items with a pool has an Alive job that is not in error, the 10 enabled
#     adapterless services have no job and answer CreateBusinessService, TelegramIn, TelegramOut and EvalIn have no job,
#     and CreateBusinessService("EvalIn") is refused as disabled;
#   - row 15, the accessor outside Decide: a terminal session reads the three extension classes from the active production;
#   - row 16, the stubs over the running production: a created CommandsIn service sends to SessionOps, Conversation,
#     TriageAgent and OutcomeRouter. The operations answer code 5003, the process answers that it terminated because of
#     5003, the router answers OK with nothing, and every target keeps the job it had;
#   - row 17, Submit: it reaches CommandsIn with the origin web_user, and with the origin tool inside a bridge context;
#     an origin outside the enumeration is refused naming it; CommandsIn logs its error;
#   - row 18, the Running branch: the Production step run on the running production starts every item with a pool again;
#   - row 21, an item that cannot start: with a WatchOps whose OnInit fails the step fails naming WatchOps, and with the
#     original class back it succeeds and WatchOps runs;
#   - another production: with OcuTalon.Production stopped and a fixture production running, the step fails naming the
#     fixture and leaves it running.
# The project is unique, publishes no host port and receives no keys: the start is the no-key start of AD-23. An EXIT trap
# removes the project with its volume and images. Every wait ends by an overall deadline, so even a failing run ends within
# about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t06

version=$(manifest_version src/module.xml)

# --- row 13: the first start ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "row 13 the first start did not end ready within 400 s"
fi
pass "row 13 the first start ended ready"

log_steps > "$tmp/steps.log"
if grep -qx 'STEP Production OK' "$tmp/steps.log" && [ "$(tail -n 1 "$tmp/steps.log")" = "RESULT OK $version" ]; then
  pass "row 13: the log has STEP Production OK and ends with RESULT OK $version"
else
  sed 's/^/  /' "$tmp/steps.log" | tail -n 8
  fail "row 13: the log has no STEP Production OK, or does not end with RESULT OK $version"
fi
if [ "$(health_status)" = healthy ] && [ "$(restart_count)" = 0 ]; then
  pass "row 13: Docker reports healthy, with no restart"
else
  fail "row 13: Docker reports '$(health_status)' after $(restart_count) restart(s), wanted healthy and 0"
fi
check_session "row 13: OcuTalon.Production is Running, and is not the autostart production" OCUTALON \
  "CHK|state|OcuTalon.Production|1
CHK|autostart|" \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|state|",n,"|",s' \
  'Write !,"CHK|autostart|",$Select($Get(^Ens.AutoStart)="OcuTalon.Production":"OcuTalon.Production",1:"")' \
  'Halt'

# --- row 14: the items run ---

check_items_run "row 14"
check_session "row 14: CreateBusinessService refuses EvalIn as disabled" OCUTALON \
  "CHK|evalin-refused|1|1" \
  'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|evalin-refused|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["is disabled")' \
  'Halt'

# --- row 15: the accessor outside Decide ---

check_session "row 15: a terminal session reads the extension classes of the active production" OCUTALON \
  "CHK|HostSinkClass|OcuTalon.Core.BridgeSink|1
CHK|ReplyFilterClass|OcuTalon.Checks.ReplyGuard|1
CHK|ClassificationClass|OcuTalon.Bridge.Ext.Classification|1" \
  'For s="HostSinkClass","ReplyFilterClass","ClassificationClass" { Set c=##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(s,,,.sc) Write !,"CHK|",s,"|",c,"|",$SYSTEM.Status.IsOK(sc) }' \
  'Halt'

# --- row 16: the stubs over the running production ---

item_jobs "$tmp/jobs.16.before"
check_session "row 16: the stubs answer 'not implemented', and the router answers OK with nothing" OCUTALON \
  "CHK|sync|SessionOps|0|5003|1|0
CHK|sync|Conversation|0|<Ens>ErrBPTerminated|1|0
CHK|sync|TriageAgent|0|5003|1|0
CHK|sync|OutcomeRouter|1||0|0" \
  'Set sc=##class(Ens.Director).CreateBusinessService("CommandsIn",.svc)' \
  'For t="SessionOps","Conversation","TriageAgent","OutcomeRouter" { Set req=##class(Ens.StringRequest).%New("x") Kill resp Set sc=svc.SendRequestSync(t,req,.resp,10) Write !,"CHK|sync|",t,"|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorCodes(sc),"|",($SYSTEM.Status.GetErrorText(sc)["#5003: Not implemented"),"|",$IsObject($Get(resp)) }' \
  'Halt'
item_jobs "$tmp/jobs.16.after"
targets='^(SessionOps|Conversation|TriageAgent|OutcomeRouter)'
if [ "$(grep -cE "$targets" "$tmp/jobs.16.before")" = 4 ] \
  && [ "$(grep -E "$targets" "$tmp/jobs.16.before")" = "$(grep -E "$targets" "$tmp/jobs.16.after")" ]; then
  pass "row 16: SessionOps, Conversation, TriageAgent and OutcomeRouter keep the jobs they had"
else
  grep -E "$targets" "$tmp/jobs.16.before" | sed 's/^/  before: /'
  grep -E "$targets" "$tmp/jobs.16.after" | sed 's/^/  after:  /'
  fail "row 16: a target lost its job, or got a new one"
fi

# --- row 17: Submit, live ---

check_session "row 17: Submit reaches CommandsIn with the origin of the caller, tool inside a context, and refuses a bad origin" OCUTALON \
  "CHK|submit-user|5003|web_user
CHK|submit-tool|5003|tool
CHK|submit-zz|1|1|web_admin
CHK|commandsin-logged|1" \
  'Set cmd=##class(OcuTalon.Msg.Command.ListReminders).%New() Set cmd.Origin="web_admin" Set sc=##class(OcuTalon.Core.Commands).Submit(cmd,"web_user",.res) Write !,"CHK|submit-user|",$SYSTEM.Status.GetErrorCodes(sc),"|",cmd.Origin' \
  'Set sc=##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(),"zzss") Set cmd=##class(OcuTalon.Msg.Command.ListReminders).%New() Set cmd.Origin="web_admin" Set sc=##class(OcuTalon.Core.Commands).Submit(cmd,"web_admin",.res) Write !,"CHK|submit-tool|",$SYSTEM.Status.GetErrorCodes(sc),"|",cmd.Origin Do ##class(OcuTalon.Bridge.Context).End()' \
  'Set cmd=##class(OcuTalon.Msg.Command.ListReminders).%New() Set cmd.Origin="web_admin" Set sc=##class(OcuTalon.Core.Commands).Submit(cmd,"zz",.res) Write !,"CHK|submit-zz|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["zz"),"|",cmd.Origin' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 2 AND Text LIKE ?","CommandsIn","%Not implemented%") Do rs.%Next() Write !,"CHK|commandsin-logged|",(rs.%GetData(1)>0)' \
  'Halt'

# --- row 18: the step on the running production ---

iris_script OCUTALON > "$tmp/pooled.chk" <<'EOS'
Set it=##class(OcuTalon.Test.Install.Production).Items().%GetIterator() While it.%GetNext(,.x) { If x.enabled,x.pool { Write !,"CHK|pooled|",x.name } }
Halt
EOS
sed -n 's/^CHK|pooled|//p' "$tmp/pooled.chk" > "$tmp/pooled.names"
item_jobs "$tmp/jobs.18.before"
check_session "row 18: the step runs on the running production and leaves nothing unstarted" OCUTALON \
  "CHK|start|1|
CHK|notrunning|" \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(30) Write !,"CHK|start|",$SYSTEM.Status.IsOK(sc),"|",$Select($SYSTEM.Status.IsOK(sc):"",1:$SYSTEM.Status.GetErrorText(sc))' \
  'Write !,"CHK|notrunning|",##class(OcuTalon.Install.Step.Production).NotRunning()' \
  'Halt'
item_jobs "$tmp/jobs.18.after"
stale=""
count=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  count=$((count + 1))
  before=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$tmp/jobs.18.before")
  after=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$tmp/jobs.18.after")
  if [ -z "$before" ] || [ -z "$after" ] || printf '%s\n' "$before" | tr ',' '\n' | grep -qxFf <(printf '%s\n' "$after" | tr ',' '\n'); then
    stale="$stale $name"
  fi
done < "$tmp/pooled.names"
if [ "$count" = 25 ] && [ -z "$stale" ]; then
  pass "row 18: each of the $count items with a pool has new job ids"
else
  fail "row 18: $count items with a pool were compared; no new job ids for:$stale"
fi

# --- row 21: an item that cannot start ---

cat > "$tmp/WatchOpsFail.cls" <<'EOC'
Class OcuTalon.Watch.Ops Extends Ens.BusinessOperation
{

Parameter STUB = 1;

Method OnInit() As %Status
{
	Quit $SYSTEM.Status.Error(5001, "fixture: OnInit fails on purpose")
}

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
EOC
dc exec -T iris sh -c 'cat > /tmp/WatchOpsFail.cls' < "$tmp/WatchOpsFail.cls"
check_session "row 21: the step fails naming WatchOps while it cannot start, and succeeds once it can" OCUTALON \
  "CHK|fixture|1
CHK|start-fails|1|1
CHK|restored|1
CHK|start-ok|1
CHK|watchops-runs|1" \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/WatchOpsFail.cls","ck-d")' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(15) Write !,"CHK|start-fails|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["WatchOps")' \
  'Write !,"CHK|restored|",$SYSTEM.OBJ.Load("/opt/ocutalon/src/ocutalon/cls/OcuTalon/Watch/Ops.cls","ck-d")' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(30) Write !,"CHK|start-ok|",$SYSTEM.Status.IsOK(sc)' \
  'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Set sc=rs.Execute() Set up=0 While rs.Next() { If rs.Get("ConfigName")="WatchOps",rs.Get("State")="Alive" { Set up=1 } } Write !,"CHK|watchops-runs|",up' \
  'Halt'
check_items_run "row 21: after the restore"

# --- another production is left alone ---

cat > "$tmp/ZzOther.cls" <<'EOC'
Class ZzOther.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="ZzOther.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
</Production>
}

}
EOC
dc exec -T iris sh -c 'cat > /tmp/ZzOther.cls' < "$tmp/ZzOther.cls"
check_session "another production: the step fails naming it and leaves it running" OCUTALON \
  "CHK|stopped|1
CHK|fixture|1
CHK|other-started|1
CHK|start-refused|1|1
CHK|other-state|ZzOther.Production|1
CHK|other-stopped|1" \
  'Set sc=##class(Ens.Director).StopProduction(30) Write !,"CHK|stopped|",$SYSTEM.Status.IsOK(sc)' \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOther.cls","ck-d")' \
  'Set sc=##class(Ens.Director).StartProduction("ZzOther.Production") Write !,"CHK|other-started|",$SYSTEM.Status.IsOK(sc)' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(15) Write !,"CHK|start-refused|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["ZzOther.Production")' \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|other-state|",n,"|",s' \
  'Set sc=##class(Ens.Director).StopProduction(30) Write !,"CHK|other-stopped|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-production: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-production: all checks passed"
