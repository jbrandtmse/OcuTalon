#!/usr/bin/env bash
# Live test of the production (Story 0.6, matrix rows 13 to 18 and 21): builds the image and starts it in one throwaway
# compose project with the after-start script active and no model key, then checks
#   - row 13, the first start: the log lists STEP Production OK and ends with RESULT OK, Docker reports healthy, the
#     production OcuTalon.Production is Running, and it is not the autostart production (AD-3);
#   - row 14, the items: the container holds no model key and the start wrote no error or alert to the event log; each
#     enabled item with a pool in the item oracle (OcuTalon.Test.Install.Production, Items) has an Alive job that is not in
#     error, each enabled adapterless service has no job and answers CreateBusinessService, each disabled item has no job,
#     and CreateBusinessService("EvalIn") is refused as disabled;
#   - row 15, outside Decide: a terminal session reads the three extension classes and a runner's model from the active
#     production;
#   - row 16, the stubs over the running production: a created CommandsIn service sends to SessionOps, Conversation,
#     TriageAgent and OutcomeRouter. The operations answer code 5003, the process answers that it terminated because of
#     5003, the router answers OK with nothing and sends nothing on, and every target keeps the job it had; then the same
#     for every enabled stub with a pool, so that no stub kills its job on a request;
#   - row 17, Submit: it reaches CommandsIn with the origin web_user, and with the origin tool inside a bridge context;
#     an origin outside the enumeration is refused naming it; CommandsIn logs its error;
#   - row 18, the Running branch: the Production step run on the running production starts every item with a pool again;
#   - row 21, an item that cannot start: with a WatchOps whose OnInit fails the step fails naming WatchOps, and with the
#     original class back it succeeds and WatchOps runs;
#   - DW-12, the container's time zone (Story 0.9): the stack starts with the compose-level TZ America/New_York, so that
#     (1) after row 14 every alive item job holds TZ=America/New_York in /proc/<job>/environ, and (2) after row 21 the
#     WatchOps fixture's OnInit, which runs in the item's own production job, has recorded Data.Time.Zone() as
#     America/New_York and ToLocal as 12:00:00 for 17:00Z in January (EST) and for 16:00Z in July (EDT), with TZ read from the
#     job's environment; the probe is ^OcuTalonTest("TimeProbe", job), killed after the check;
#   - a runner with no model: with an agent class that has no MODEL the step fails naming the runner, and with the original
#     class back it succeeds;
#   - another production: with OcuTalon.Production stopped and a fixture production running, the step fails naming the
#     fixture and leaves it running; with a production Troubled or Suspended under another name it fails naming it and
#     recovers or starts nothing; with OcuTalon.Production Suspended it starts it. The Troubled and Suspended states are
#     made by setting the director's state globals in the throwaway, and each is removed afterwards. Each stop in the block
#     first waits, up to 10 s, until Ens.ScheduleHandler has finished the start's request (DW-28), and a failed stop
#     prints its error.
# The project is unique, publishes no host port and receives no keys: the start is the no-key start of AD-23. An EXIT trap
# removes the project with its volume and images. Every wait ends by an overall deadline, so even a failing run ends within
# about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t06

# DW-12: the whole stack runs in a US zone, so that the checks see what a production job does with the container's TZ.
printf 'services:\n  iris:\n    environment:\n      TZ: America/New_York\n' > "$tmp/compose.tz.yml"
live_add_file "$tmp/compose.tz.yml"

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

check_no_key "row 14"
check_clean_start "row 14"
check_items_run "row 14"
check_session "row 14: CreateBusinessService refuses EvalIn as disabled" OCUTALON \
  "CHK|evalin-refused|1|1" \
  'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|evalin-refused|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["is disabled")' \
  'Halt'

# --- DW-12: the container's zone reaches every item job ---

tz_wanted=America/New_York
item_jobs "$tmp/jobs.tz"
tz_jobs=$(awk -F'\t' '{ print $2 }' "$tmp/jobs.tz" | tr ',' ' ')
# $tz_jobs is split on purpose: one argument per job id.
# shellcheck disable=SC2086
dc exec -T iris sh -c 'for j in "$@"; do printf "%s=%s\n" "$j" "$(tr "\0" "\n" < "/proc/$j/environ" 2>/dev/null | sed -n "s/^TZ=//p")"; done' sh $tz_jobs \
  | tr -d '\r' > "$tmp/jobs.tz.env"
tz_count=$(grep -c . "$tmp/jobs.tz.env")
tz_bad=$(grep -vxE "[0-9]+=$tz_wanted" "$tmp/jobs.tz.env" | tr '\n' ' ')
if [ "$tz_count" -gt 0 ] && [ -z "$tz_bad" ]; then
  pass "DW-12: each of the $tz_count alive item jobs holds TZ=$tz_wanted in /proc/<job>/environ"
else
  sed 's/^/  job=TZ: /' "$tmp/jobs.tz.env" | head -n 20
  fail "DW-12: $tz_count alive item jobs were read; no TZ=$tz_wanted in /proc/<job>/environ for: ${tz_bad:-none}"
fi

# --- row 15: the accessor outside Decide ---

check_session "row 15: a terminal session reads the extension classes and a runner's model from the active production" OCUTALON \
  "CHK|HostSinkClass|OcuTalon.Core.BridgeSink|1
CHK|ReplyFilterClass|OcuTalon.Checks.ReplyGuard|1
CHK|ClassificationClass|OcuTalon.Bridge.Ext.Classification|1
CHK|model|TriageAgent|claude-haiku-5-5" \
  'For s="HostSinkClass","ReplyFilterClass","ClassificationClass" { Set c=##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(s,,,.sc) Write !,"CHK|",s,"|",c,"|",$SYSTEM.Status.IsOK(sc) }' \
  'Write !,"CHK|model|TriageAgent|",##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent")' \
  'Halt'

# --- row 16: the stubs over the running production ---

item_jobs "$tmp/jobs.16.before"
check_session "row 16: the stubs answer 'not implemented', and the router answers OK with nothing" OCUTALON \
  "CHK|sync|SessionOps|0|5003|1|0
CHK|sync|Conversation|0|<Ens>ErrBPTerminated|1|0
CHK|sync|TriageAgent|0|5003|1|0
CHK|sync|OutcomeRouter|1||0|0
CHK|router-received|1
CHK|router-sent|0" \
  'Set q="SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ?",q2="SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName <> ?"' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,q,"CommandsIn","OutcomeRouter") Do rs.%Next() Set in0=rs.%GetData(1) Set rs=##class(%SQL.Statement).%ExecDirect(,q2,"OutcomeRouter","CommandsIn") Do rs.%Next() Set out0=rs.%GetData(1)' \
  'Set sc=##class(Ens.Director).CreateBusinessService("CommandsIn",.svc)' \
  'For t="SessionOps","Conversation","TriageAgent","OutcomeRouter" { Set req=##class(Ens.StringRequest).%New("x") Kill resp Set sc=svc.SendRequestSync(t,req,.resp,10) Write !,"CHK|sync|",t,"|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorCodes(sc),"|",($SYSTEM.Status.GetErrorText(sc)["#5003: Not implemented"),"|",$IsObject($Get(resp)) }' \
  'Hang 2 Set rs=##class(%SQL.Statement).%ExecDirect(,q,"CommandsIn","OutcomeRouter") Do rs.%Next() Write !,"CHK|router-received|",(rs.%GetData(1)>in0)' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,q2,"OutcomeRouter","CommandsIn") Do rs.%Next() Write !,"CHK|router-sent|",(rs.%GetData(1)-out0)' \
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

# --- row 16, every stub with a pool ---

iris_script OCUTALON > "$tmp/stubs.chk" <<'EOS'
Set it=##class(OcuTalon.Test.Install.Production).Items().%GetIterator() While it.%GetNext(,.x) { If x.stub,x.pool,x.enabled { Write !,"CHK|stub|",x.name } }
Halt
EOS
sed -n 's/^CHK|stub|//p' "$tmp/stubs.chk" > "$tmp/stubs.names"
stub_count=$(grep -c . "$tmp/stubs.names")
item_jobs "$tmp/jobs.16s.before"
check_session "row 16: every enabled stub with a pool ($stub_count) answers 'not implemented' and sends no response" OCUTALON \
  "CHK|sweep|$stub_count|bad=" \
  'Set sc=##class(Ens.Director).CreateBusinessService("CommandsIn",.svc)' \
  'Set n=0,bad="" Set it=##class(OcuTalon.Test.Install.Production).Items().%GetIterator()' \
  'While it.%GetNext(,.x) { If x.stub,x.pool,x.enabled { Set n=n+1 Kill resp Set req=##class(Ens.StringRequest).%New("x") Set sc=svc.SendRequestSync(x.name,req,.resp,10) If $SYSTEM.Status.IsOK(sc)||($Find($SYSTEM.Status.GetErrorText(sc),"#5003: Not implemented")=0)||$IsObject($Get(resp)) { Set bad=bad_" "_x.name } } }' \
  'Write !,"CHK|sweep|",n,"|bad=",$ZStrip(bad,"<W")' \
  'Halt'
item_jobs "$tmp/jobs.16s.after"
moved=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  before=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$tmp/jobs.16s.before")
  after=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$tmp/jobs.16s.after")
  if [ -z "$before" ] || [ "$before" != "$after" ]; then moved="$moved $name"; fi
done < "$tmp/stubs.names"
if [ "$stub_count" -gt 0 ] && [ -z "$moved" ]; then
  pass "row 16: each of the $stub_count stubs keeps the job it had"
else
  fail "row 16: $stub_count stubs were tried; no job, or a different job, for:$moved"
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
if [ "$count" -gt 0 ] && [ -z "$stale" ]; then
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
	Set ^OcuTalonTest("TimeProbe", $Job) = $ListBuild(##class(OcuTalon.Data.Time).Zone(), ##class(OcuTalon.Data.Time).ToLocal("2026-01-15T17:00:00Z"), ##class(OcuTalon.Data.Time).ToLocal("2026-07-15T16:00:00Z"), $SYSTEM.Util.GetEnviron("TZ"))
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

# --- DW-12: an item's own production job converts in the container's zone ---

check_session "DW-12: the item's own production job reports Zone() America/New_York, EST in January and EDT in July" OCUTALON \
  "CHK|probe|1|bad=" \
  'Set n=0,bad="",j="" For { Set j=$Order(^OcuTalonTest("TimeProbe",j),1,v) Quit:j=""  Set n=n+1,ok=($ListToString(v,"|")="America/New_York|2026-01-15T12:00:00|2026-07-15T12:00:00|America/New_York") Write !,"CHK|probe-value|",j,"|",$ListToString(v,"|") If ok=0 { Set bad=bad_" "_j } }' \
  'Write !,"CHK|probe|",(n>0),"|bad=",$ZStrip(bad,"<W")' \
  'Kill ^OcuTalonTest("TimeProbe")' \
  'Halt'
sed -n 's/^CHK|probe-value|/  DW-12 probe in job /p' "$tmp/actual.chk" | head -n 6

# --- a runner that resolves no model ---

cat > "$tmp/TriageNoModel.cls" <<'EOC'
Class OcuTalon.Agent.Triage Extends %AI.Agent
{

Parameter MOCKKEY = "triage";

}
EOC
dc exec -T iris sh -c 'cat > /tmp/TriageNoModel.cls' < "$tmp/TriageNoModel.cls"
check_session "the step fails naming a runner that resolves no model, and succeeds once it resolves one" OCUTALON \
  "CHK|fixture|1
CHK|row-deleted|1|1
CHK|start-unresolved|1|1
CHK|restored|1
CHK|start-ok|1" \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/TriageNoModel.cls","ck-d")' \
  'Set id="OcuTalon.Production||TriageAgent||*||Model",seeded=##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id) Write !,"CHK|row-deleted|",seeded,"|",(##class(Ens.Config.DefaultSettings).%ExistsId(id)=0)' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(15) Write !,"CHK|start-unresolved|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["resolve no model: TriageAgent")' \
  'Write !,"CHK|restored|",$SYSTEM.OBJ.Load("/opt/ocutalon/src/ocutalon/cls/OcuTalon/Agent/Triage.cls","ck-d")' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Run() Write !,"CHK|start-ok|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'

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
# settle_scheduler (lib-live.sh) ends each stop's wait for Ens.ScheduleHandler (DW-28).
check_session "another production: the step fails naming it and leaves it running" OCUTALON \
  "CHK|settled|1
CHK|stopped|1
CHK|fixture|1
CHK|other-started|1
CHK|start-refused|1|1
CHK|other-state|ZzOther.Production|1
CHK|other-settled|1
CHK|other-stopped|1" \
  "$settle_scheduler"' Write !,"CHK|settled|",settled' \
  'Set sc=##class(Ens.Director).StopProduction(30) Write !,"CHK|stopped|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|stop-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOther.cls","ck-d")' \
  'Set sc=##class(Ens.Director).StartProduction("ZzOther.Production") Write !,"CHK|other-started|",$SYSTEM.Status.IsOK(sc)' \
  'Set sc=##class(OcuTalon.Install.Step.Production).Start(15) Write !,"CHK|start-refused|",$SYSTEM.Status.IsError(sc),"|",($SYSTEM.Status.GetErrorText(sc)["ZzOther.Production")' \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|other-state|",n,"|",s' \
  "$settle_scheduler"' Write !,"CHK|other-settled|",settled' \
  'Set sc=##class(Ens.Director).StopProduction(30) Write !,"CHK|other-stopped|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|stop-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Halt'
sed -n 's/^CHK|stop-error|/  another production: the stop failed: /p' "$tmp/actual.chk"

# The director reports Troubled when ^Ens.Runtime is left without running jobs, and Suspended when only ^Ens.Suspended is
# set (Ens.Director GetProductionStatus). A stop that leaves a message queued leaves ^Ens.Suspended set (Ens.Director
# StopProduction), so the block first removes it and checks that the namespace is Stopped; each fake is removed after its check.
check_session "another production, Troubled or Suspended: the step fails naming it and recovers nothing; this one Suspended: it starts" OCUTALON \
  "CHK|clean|2|0|0
CHK|troubled-other|4|ZzOther.Production|1|1|0|ZzOther.Production
CHK|suspended-other|3|ZzOther.Production|1|1|0|ZzOther.Production
CHK|suspended-this|3|1||1" \
  'Kill ^Ens.Suspended Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|clean|",s,"|",$Data(^Ens.Runtime),"|",$Data(^Ens.Suspended)' \
  'Set ^Ens.Runtime("Name")="ZzOther.Production" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Set st=##class(OcuTalon.Install.Step.Production).Start(15) Set t=$SYSTEM.Status.GetErrorText(st) Write !,"CHK|troubled-other|",s,"|",n,"|",$SYSTEM.Status.IsError(st),"|",((t["ZzOther.Production")&&(t["stops no other production")),"|",$Data(^Ens.Suspended),"|",$Get(^Ens.Runtime("Name")) Kill ^Ens.Runtime,^Ens.Suspended' \
  'Set ^Ens.Suspended="ZzOther.Production" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Set st=##class(OcuTalon.Install.Step.Production).Start(15) Set t=$SYSTEM.Status.GetErrorText(st) Write !,"CHK|suspended-other|",s,"|",n,"|",$SYSTEM.Status.IsError(st),"|",((t["ZzOther.Production")&&(t["stops no other production")),"|",##class(Ens.Director).IsProductionRunning(),"|",$Get(^Ens.Suspended) Kill ^Ens.Suspended' \
  'Set ^Ens.Suspended="OcuTalon.Production" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Set st=##class(OcuTalon.Install.Step.Production).Start(30) Write !,"CHK|suspended-this|",s,"|",$SYSTEM.Status.IsOK(st),"|",##class(OcuTalon.Install.Step.Production).NotRunning(),"|",##class(Ens.Director).IsProductionRunning()' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-production: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-production: all checks passed"
