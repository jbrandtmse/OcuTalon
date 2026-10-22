#!/usr/bin/env bash
# The bridge alone (Story 1.3; AD-2, AD-29; FR-5, REL-4): proves in a throwaway stack that src/bridge/ loads into a clean
# Interoperability namespace with no Foundation and no IPM, that OcuTalon.Bridge.Installer sets it up, and that
# OcuTalon.BridgeExample.Production answers a decide request through Ens's testing service. It is the standalone-bridge job of
# .github/workflows/lane-a.yml and runs the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh
# It sources ci/iris.sh (which sources ci/units.sh and docker/tests/lib-live.sh) and runs nothing of them but the throwaway
# recipe: a project of its own, the CI override with the model mock, the throwaway lock and the teardown on exit. The checks:
#   1. the namespace OCUBRIDGE is created without Interoperability (it is no Interoperability namespace until it is enabled) and
#      enabled for it with no Foundation installer (it is no HealthShare namespace after);
#   2. LoadDir of /opt/ocutalon/src/bridge/cls and OcuTalon.Bridge.Installer.Run() give 1, and no OcuTalon class outside
#      OcuTalon.Bridge and OcuTalon.BridgeExample is there; no production runs before the example starts;
#   3. the CI override's environment is there (OCUTALON_MOCK_KEY_HEADER is 1 and OCUTALON_MODEL_BASE_URL is set), and two System
#      Default Settings rows of the example production are written, as a developer sets them for a namespace of their own (AD-19):
#      the inline ProviderConfig of the TriageAgent runner (the mock's base URL, the key placeholder of the CI variable and the
#      mock key header of the example agent) and the $Production TestingEnabled that switches Ens's testing service on. The
#      example's definition holds neither;
#   4. the example production starts, the three extension settings of Decide give the three bases, and a decide request through
#      EnsLib.Testing.Service gets a DecisionResponse with the outcome of the scenario bridge-example, tellnow, and a Decision row
#      whose TraceSessionId is the session of the request; the bridge alone also counts and prices the call (Story 1.4; AD-2, AD-20):
#      both Price rows that Installer.Run() seeds exist, and the decision's row holds the model claude-haiku-5-5 and tokens and a cost
#      above 0, with one Usage row for its Ref that TriageAgent wrote;
#   5. no web application of the namespace names an OcuTalon class or /ocutalon;
#   6. the production stops.
# Prints one PASS or FAIL line per check, and exits 1 when any fails. The trap of live_start removes the project, its volume and
# its images, and releases the lock. No key is written anywhere: the key is the placeholder of a non-secret CI variable.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
. "$root/ci/iris.sh"

NS=OCUBRIDGE
PRODUCTION=OcuTalon.BridgeExample.Production
SCRIPT=release/standalone-bridge.sh

setup_tag
preflight
live_start sbridge
echo "STACK standalone bridge: project $P"
started=$SECONDS
if ! dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "the stack did not become ready"
fi
live_track_image
echo "READY standalone bridge $((SECONDS - started))s"

# --- 1. the namespace: no Interoperability at creation, then enabled with no Foundation installer ---

cat > "$tmp/ocubridge.cpf" <<'EOC'
[Actions]
CreateResource:Name=%DB_OCUBRIDGE,Description="Bridge-alone test database"
CreateDatabase:Name=OCUBRIDGE,Directory=ocubridge,Resource=%DB_OCUBRIDGE
CreateNamespace:Name=OCUBRIDGE,Globals=OCUBRIDGE,Routines=OCUBRIDGE
EOC
if dc exec -T iris sh -c 'cat > /tmp/ocubridge.cpf' < "$tmp/ocubridge.cpf" > "$tmp/merge.log" 2>&1 \
  && dc exec -T iris iris merge IRIS /tmp/ocubridge.cpf >> "$tmp/merge.log" 2>&1; then
  pass "the namespace $NS is created"
else
  tail -n 30 "$tmp/merge.log"
  die "the namespace $NS could not be created"
fi
check_session "the namespace $NS has no Interoperability until it is enabled for it, with no Foundation installer" %SYS \
  "CHK|interop-before|0
CHK|enable|1
CHK|interop|1
CHK|foundation|0" \
  'Write !,"CHK|interop-before|",##class(%Library.EnsembleMgr).IsEnsembleNamespace("OCUBRIDGE")' \
  'Set sc=##class(%Library.EnsembleMgr).EnableNamespace("OCUBRIDGE",0,,1) Write !,"CHK|enable|",$SYSTEM.Status.IsOK(sc)' \
  'Write !,"CHK|interop|",##class(%Library.EnsembleMgr).IsEnsembleNamespace("OCUBRIDGE")' \
  'Write !,"CHK|foundation|",##class(%Library.EnsembleMgr).IsHealthShareNamespace("OCUBRIDGE")' \
  'Halt'
if [ "$fails" -ne 0 ]; then die "the namespace $NS could not be enabled for Interoperability"; fi

# --- 2. the bridge alone ---

check_session "the bridge loads and installs alone: no other OcuTalon class, and no production runs" $NS \
  "CHK|load|1
CHK|run|1
CHK|other-classes|0
CHK|running-before|0
CHK|active-before|" \
  'Write !,"CHK|load|",$SYSTEM.OBJ.LoadDir("/opt/ocutalon/src/bridge/cls","ck-d",.errors,1)' \
  'Write !,"CHK|run|",##class(OcuTalon.Bridge.Installer).Run()' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ? AND NOT (Name %STARTSWITH ? OR Name %STARTSWITH ?)","OcuTalon.","OcuTalon.Bridge.","OcuTalon.BridgeExample.") Do rs.%Next() Write !,"CHK|other-classes|",rs.%GetData(1)' \
  'Write !,"CHK|running-before|",##class(Ens.Director).IsProductionRunning()' \
  'Write !,"CHK|active-before|",##class(Ens.Director).GetActiveProductionName()' \
  'Halt'
if [ "$fails" -ne 0 ]; then die "the bridge did not load and install alone"; fi

# --- 3. the settings of the example, as System Default Settings rows of this namespace ---

before=$fails
check_session "the environment is the CI override's: the mock key switch is 1 and the model base URL is set" $NS \
  "CHK|mock-flag|1
CHK|base-url|1" \
  'Write !,"CHK|mock-flag|",($SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")=1)' \
  'Write !,"CHK|base-url|",(($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")="")=0)' \
  'Halt'
if [ "$fails" -ne "$before" ]; then die "this script runs in the CI override's environment only (ci/compose.ci.yml)"; fi
check_session "the runner's inline ProviderConfig and the testing switch are written as System Default Settings rows" $NS \
  "CHK|row-provider|1
CHK|row-testing|1" \
  'Set pc={"model_provider":"anthropic","api_key":"@{env:OCUTALON_MOCK_KEY_HEADER}","base_url":($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")),"http_config":{"custom_headers":{"x-ocutalon-mockkey":"bridge-example"}}}.%ToJSON()' \
  'Set r=##class(Ens.Config.DefaultSettings).%New() Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="TriageAgent",r.HostClassName="*",r.SettingName="ProviderConfig",r.SettingValue=pc,r.Description="Written by release/standalone-bridge.sh in a throwaway namespace." Write !,"CHK|row-provider|",r.%Save()' \
  'Set r=##class(Ens.Config.DefaultSettings).%New() Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="$Production",r.HostClassName="*",r.SettingName="TestingEnabled",r.SettingValue=1,r.Description="Written by release/standalone-bridge.sh in a throwaway namespace." Write !,"CHK|row-testing|",r.%Save()' \
  'Halt'
if [ "$fails" -ne 0 ]; then die "the settings of the example could not be written"; fi

# --- 4. the example production: start, extensions, and a decide request ---

check_session "the example production starts with its three items" $NS \
  "CHK|start|1
CHK|jobs|3
CHK|active|$PRODUCTION" \
  'Set sc=##class(Ens.Director).StartProduction("OcuTalon.BridgeExample.Production") Write !,"CHK|start|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|start-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'For k=1:1:120 { Set n=0,rs=##class(%ResultSet).%New("Ens.Job:Enumerate"),x=rs.Execute() While rs.Next() { If (rs.Get("State")="Alive")&&($ListFind($ListBuild("Decide","TriageAgent","AgentSteps"),rs.Get("ConfigName"))) Set n=n+1 } Quit:n=3  Hang 1 }' \
  'Write !,"CHK|jobs|",n' \
  'Write !,"CHK|active|",##class(Ens.Director).GetActiveProductionName()' \
  'Halt'
check_session "the three extension settings of Decide give the three base classes" $NS \
  "CHK|HostSinkClass|OcuTalon.Bridge.Ext.HostSink
CHK|ReplyFilterClass|OcuTalon.Bridge.Ext.ReplyFilter
CHK|ClassificationClass|OcuTalon.Bridge.Ext.Classification" \
  'For s="HostSinkClass","ReplyFilterClass","ClassificationClass" { Write !,"CHK|",s,"|",##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(s) }' \
  'Halt'
check_session "a decide request through Ens's testing service gets the outcome of the scenario, and a Decision row of its session" $NS \
  "CHK|send|1
CHK|response|OcuTalon.Bridge.Msg.DecisionResponse
CHK|outcome|tellnow
CHK|confidence|.7
CHK|fallback|0
CHK|row|1
CHK|row-ref|1
CHK|row-outcome|tellnow
CHK|row-trace|1" \
  'Set rq=##class(OcuTalon.Bridge.Msg.Request).%New() Set rq.Kind="decide",rq.Provenance="untrusted",rq.ItemId=##class(OcuTalon.Bridge.Ids).NewRef(),rq.OwnerRef="instance",rq.Channel="system",rq.Summary="Standalone bridge check",rq.Input="Triage this item."' \
  'Set sc=##class(EnsLib.Testing.Service).SendTestRequest("Decide",rq,.rs,.sid,1) Write !,"CHK|send|",$SYSTEM.Status.IsOK(sc)' \
  'Write !,"CHK|response|",$Select($IsObject(rs):$ClassName(rs),1:"none")' \
  'If $IsObject(rs) { Write !,"CHK|outcome|",rs.Outcome,!,"CHK|confidence|",rs.Confidence,!,"CHK|fallback|",rs.Fallback }' \
  'If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(rq.ItemId,"decide",.id) { Set row=##class(OcuTalon.Bridge.Data.Decision).%OpenId(id) } Else { Set row="" }' \
  'Write !,"CHK|row|",$IsObject(row)' \
  'If $IsObject(row)&&$IsObject(rs) { Write !,"CHK|row-ref|",(row.Ref=rs.DecisionRef),!,"CHK|row-outcome|",row.Outcome,!,"CHK|row-trace|",((sid'"'"'="")&&(row.TraceSessionId=sid)) }' \
  'Halt'
check_session "the bridge alone prices and counts the decision: both Price rows, and the decision has its model, tokens and cost, with one Usage row of TriageAgent" $NS \
  "CHK|prices|2
CHK|row|1
CHK|model|claude-haiku-5-5
CHK|input|1
CHK|cost|1
CHK|usage-rows|1
CHK|usage-agent|TriageAgent
CHK|usage-model|claude-haiku-5-5" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Price WHERE Model IN (?,?)","claude-haiku-5-5","claude-sonnet-5-5") Do rs.%Next() Write !,"CHK|prices|",rs.%GetData(1)' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID FROM OcuTalon_Bridge_Data.Decision WHERE Summary = ? ORDER BY ID DESC","Standalone bridge check") Set id="" If rs.%Next() { Set id=rs.%GetData(1) }' \
  'If $Length(id) { Set row=##class(OcuTalon.Bridge.Data.Decision).%OpenId(id) } Else { Set row="" }' \
  'Write !,"CHK|row|",$IsObject(row)' \
  'If $IsObject(row) { Write !,"CHK|model|",row.Model,!,"CHK|input|",(row.InputTokens>0),!,"CHK|cost|",(row.CostUSD>0) }' \
  'Set ref=$Select($IsObject(row):row.Ref,1:"")' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?",ref) Do rs.%Next() Write !,"CHK|usage-rows|",rs.%GetData(1)' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Agent, Model FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? ORDER BY ID",ref) Set agent="",model="" If rs.%Next() { Set agent=rs.%GetData(1),model=rs.%GetData(2) } Write !,"CHK|usage-agent|",agent,!,"CHK|usage-model|",model' \
  'Halt'
if [ "$fails" -ne 0 ]; then
  check_session "diagnosis: the event log of $NS holds these error rows" $NS \
    "CHK|diagnosis|done" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 6 ConfigName,SUBSTRING(Text,1,200) FROM Ens_Util.Log WHERE Type IN (2,3) ORDER BY ID DESC") While rs.%Next() { Write !,"CHK|row|",rs.%GetData(1),"|",rs.%GetData(2) }' \
    'Write !,"CHK|diagnosis|done"' \
    'Halt'
  sed -n 's/^CHK|row|/  event log: /p' "$tmp/actual.chk"
fi

# --- 5. no OcuTalon web application ---

check_session "no web application of $NS names an OcuTalon class or /ocutalon" %SYS \
  "CHK|ocutalon-apps|0" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE NameSpace = ? AND (Name %STARTSWITH ? OR DispatchClass %STARTSWITH ? OR PermittedClasses [ ?)","OCUBRIDGE","/ocutalon","OcuTalon","OcuTalon") Do rs.%Next() Write !,"CHK|ocutalon-apps|",rs.%GetData(1)' \
  'Halt'

# --- 6. the production stops ---

check_session "the example production stops" $NS \
  "CHK|settled|1
CHK|stopped|1" \
  "$settle_scheduler"' Write !,"CHK|settled|",settled' \
  'Set sc=##class(Ens.Director).StopProduction(30,1) Write !,"CHK|stopped|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|stop-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "$(basename "$SCRIPT" .sh): $fails check(s) failed (project $P)"
  exit 1
fi
echo "$(basename "$SCRIPT" .sh): all checks passed"
