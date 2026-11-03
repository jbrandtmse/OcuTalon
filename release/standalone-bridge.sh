#!/usr/bin/env bash
# The bridge alone (Story 1.3, grown by Stories 13.1 and 13.2; AD-2, AD-29; FR-5, REL-4): proves in a throwaway stack that src/bridge/ loads into
# a clean Interoperability namespace with no Foundation and no IPM, that OcuTalon.Bridge.Installer sets it up, and that
# OcuTalon.BridgeExample.Production, a small production of its own, makes a decision through the bridge, routes on it and takes each
# fallback, configured only by settings, and whose own tools the bridge governs: a read-only tool runs, a risky or unclassified tool waits for
# approval as an IRIS Workflow request and is replayed once it is approved. It is the standalone-bridge job of .github/workflows/lane-a.yml and runs the same way on a
# developer machine:
#   OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh
# It sources ci/iris.sh (which sources ci/units.sh and docker/tests/lib-live.sh) and runs nothing of them but the throwaway
# recipe: a project of its own, the CI override with the model mock, the throwaway lock and the teardown on exit. The checks:
#   1. the namespace OCUBRIDGE is created without Interoperability (it is no Interoperability namespace until it is enabled) and
#      enabled for it with no Foundation installer (it is no HealthShare namespace after);
#   2. LoadDir of /opt/ocutalon/src/bridge/cls and OcuTalon.Bridge.Installer.Run() give 1, OcuTalon.Bridge.Installer.CheckAudit() is
#      OK, and no OcuTalon class outside OcuTalon.Bridge and OcuTalon.BridgeExample is there; no production runs before the example
#      starts;
#   3. the CI override's environment is there (OCUTALON_MOCK_KEY_HEADER is 1 and OCUTALON_MODEL_BASE_URL is set), the container's
#      ANTHROPIC_API_KEY is this run's dummy key (a compose file generated at run time inside the run's temporary folder, never
#      committed and never printed; the check prints 1 or 0), and the inline ProviderConfig of the TriageAgent runner is written as a
#      System Default Settings row, as a developer sets it for a namespace of their own (AD-19): the mock's base URL, the key
#      placeholder @{env:ANTHROPIC_API_KEY} and the mock key header of the example agent. The example's definition holds no
#      provider setting, and nothing writes the $Production TestingEnabled row: items enter through the example's own service. Two
#      more rows of Decide govern the example's tools: ToolClassification (example_count_items is safe and read-only,
#      example_forward_item is risky, and example_archive_item has no entry) and ApprovalRole (ExampleApprovers). In %SYS the check
#      creates the role ExampleApprovers and the login-disabled users ExampleApprover (with the role) and ExampleViewer (without it):
#      fixtures of the throwaway, since the product creates no role or user;
#   4. the example production starts: ten jobs are Alive (its twelve items, two of them services) and ExampleItemIn is enabled; the runner resolves the example agent as its
#      AgentClass and AgentAllowList and DecisionPayload as its ReplyClass; the three extension settings of Decide give the three base
#      classes; the director reads both governance rows live, the gate classifies the three tools from the ToolClassification row alone
#      (safe:1:setting, risky:0:setting, unclassified) and the agent has its toolset; one Action entry with a run-unique marker, the
#      acting user, the SessionRef and the channel (AD-17) is written through OcuTalon.Bridge.Audit;
#   5. each row of the matrix of Story 13.1 sends an item through ExampleItemIn (OcuTalon.BridgeExample.ItemIn Send) and polls, with a
#      deadline, until the router has routed it; every decision that reached the model has a CostUSD equal to Price.CostFor and to
#      its one Usage row, and its Decision row holds the same model and cost:
#      a. the happy path: the trace of the session in header order (the item, the request, the runner's request and reply, each
#         AgentStep to AgentSteps in Position order, the DecisionResponse, the Decided message, the send to ExampleNotifyOut), the
#         request's fields, the decision with its reasons, confidence and four token counts, and AgentSteps logged no error;
#      b. digest (routed to ExampleDigestOut only), ignore (routed nowhere) and act (routed to ExampleNotifyOut only);
#      c. the model row (TriageAgent Model), the budget row (Decide DecisionTokenBudget) and the timeout row (Decide TimerSeconds,
#         with a reply held past it), each a System Default Settings row applied with the one apply helper below and undone; the
#         no-key row, where the placeholder of the ProviderConfig key names a variable that the stack never sets (written with SQL
#         and read live, so no apply follows; see provider_key) and is restored; and the refusal, a marker scenario. Each fallback
#         is tellnow with Fallback 1 and its reason in the Decision row and the DecisionResponse, routed to ExampleFallbackOut, with
#         no reasons kept and no tool step, and the budget fallback's line in ExampleFallbackOut's event log names the decision and
#         its reason;
#      d. the production keeps running: the ten jobs are Alive and a plain item gets a usable tellnow from the default model;
#      e. the example's tools (Story 13.2), the rows in this order: read-only (an untrusted item's example_count_items runs with no
#         approval, as an ok tool step, and no request is raised); risky held and unclassified held (a user item's example_forward_item
#         and example_archive_item do not run: each is one pending tool_call row with its name, arguments, source, runner and role,
#         its denied step with the HELD sentence, and the start of the hold and its Workflow task in the item's own session);
#         not allowed (ExampleViewer's answer); approve (ExampleApprover's answer through Approval.Answer: the row ends done, the call
#         runs once, the replay reaches Decide as a request of kind tool, and the mock's log gains no request); a second answer
#         (already_answered, the winner approve); rejected (the archive call is rejected and never runs); expired (a second risky item
#         whose row's ExpiresAt is moved 1 s into the past is answered expired); and untrusted (forward and archive are denied
#         as untrusted with no request, and only example_count_items runs);
#   6. the mock's request log holds no request rejected for sampling or max_tokens, a request of the Sonnet model, and a request that
#      was not rejected for each marker item (the four tool markers included); the run's dummy key is found in no AgentStep, Reply,
#      DecisionResponse, Decision, Decided, Request, ApprovalRequest or event-log row of OCUBRIDGE, and in no IRIS audit entry since the run
#      began (a hit fails the check without printing the value); the Action entry of check 4 is read back from the IRIS audit log (it can
#      arrive about a minute late, so the read-back polls for up to 180 s), and so are the six entries of 5e: the Approval entries
#      answered/approved, started, finished/done, answered/rejected and expired, and the Action entry of the replay (action
#      example_forward_item, result done, its approvalRef), each with its UTC time, its irisUser ExampleApprover and its channel system;
#   7. no web application of the namespace names an OcuTalon class or /ocutalon;
#   8. the production stops.
# The apply helper: a System Default Settings row that is saved or deleted raises the production's modification counter, and
# Ens.Director.UpdateProduction() then restarts the items whose effective setting changed (measured on build 154: the job of
# TriageAgent changed after a Model row was saved and again after it was deleted, and the job of Decide changed after a
# TimerSeconds row was saved and again after it was deleted; the other jobs kept theirs), so apply is UpdateProduction() followed by
# a wait until the ten items are Alive. TempStopConfigItem is not needed.
# Prints one PASS or FAIL line per check, and exits 1 when any fails, with the event log's error rows on a failure. The trap of
# live_start removes the project, its volume and its images, and releases the lock. The dummy key is generated at run time and
# written nowhere but the temporary folder that the trap removes.
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
since=$(date -u '+%Y-%m-%d %H:%M:%S')
# The dummy key of this run: 16 random hex digits after a fixed prefix. It reaches the container only through the compose file of the
# run's temporary folder, and no line of this script prints it.
dummy="ocutalon-example-dummy-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
printf 'services:\n  iris:\n    environment:\n      ANTHROPIC_API_KEY: %s\n' "$dummy" > "$tmp/key.yml"
live_add_file "$tmp/key.yml"
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

check_session "the bridge loads and installs alone: its audit events are registered, no other OcuTalon class is there, and no production runs" $NS \
  "CHK|load|1
CHK|run|1
CHK|audit|1
CHK|other-classes|0
CHK|running-before|0
CHK|active-before|" \
  'Write !,"CHK|load|",$SYSTEM.OBJ.LoadDir("/opt/ocutalon/src/bridge/cls","ck-d",.errors,1)' \
  'Write !,"CHK|run|",##class(OcuTalon.Bridge.Installer).Run()' \
  'Write !,"CHK|audit|",$SYSTEM.Status.IsOK(##class(OcuTalon.Bridge.Installer).CheckAudit())' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ? AND NOT (Name %STARTSWITH ? OR Name %STARTSWITH ?)","OcuTalon.","OcuTalon.Bridge.","OcuTalon.BridgeExample.") Do rs.%Next() Write !,"CHK|other-classes|",rs.%GetData(1)' \
  'Write !,"CHK|running-before|",##class(Ens.Director).IsProductionRunning()' \
  'Write !,"CHK|active-before|",##class(Ens.Director).GetActiveProductionName()' \
  'Halt'
if [ "$fails" -ne 0 ]; then die "the bridge did not load and install alone"; fi

# --- 3. the settings of the example, as System Default Settings rows of this namespace ---

# row_set <item> <setting> <value>: writes (or replaces) the System Default Settings row of the example production.
row_set() {
  printf '%s\n' \
    "Set rid=\"\" Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = ? AND SettingName = ?\",\"$PRODUCTION\",\"$1\",\"$2\") If rs.%Next() { Set rid=rs.%GetData(1) }" \
    "Set r=\$Select(rid'=\"\":##class(Ens.Config.DefaultSettings).%OpenId(rid),1:##class(Ens.Config.DefaultSettings).%New()) Set r.ProductionName=\"$PRODUCTION\",r.ItemName=\"$1\",r.HostClassName=\"*\",r.SettingName=\"$2\",r.SettingValue=\"$3\",r.Description=\"Written by $SCRIPT in a throwaway namespace.\" Write !,\"CHK|row-set|\",r.%Save()"
}
# row_del <item> <setting>: deletes that row.
row_del() {
  printf '%s\n' \
    "Set rid=\"\" Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = ? AND SettingName = ?\",\"$PRODUCTION\",\"$1\",\"$2\") If rs.%Next() { Set rid=rs.%GetData(1) }" \
    "Write !,\"CHK|row-del|\",\$Select(rid=\"\":0,1:\$SYSTEM.Status.IsOK(##class(Ens.Config.DefaultSettings).%DeleteId(rid)))"
}
before=$fails
check_session "the environment is the CI override's: the mock key switch is 1 and the model base URL is set" $NS \
  "CHK|mock-flag|1
CHK|base-url|1" \
  'Write !,"CHK|mock-flag|",($SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")=1)' \
  'Write !,"CHK|base-url|",(($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")="")=0)' \
  'Halt'
if [ "$fails" -ne "$before" ]; then die "this script runs in the CI override's environment only (ci/compose.ci.yml)"; fi
check_session "the container's ANTHROPIC_API_KEY is this run's dummy key" $NS \
  "CHK|key-env|1" \
  "Write !,\"CHK|key-env|\",(\$SYSTEM.Util.GetEnviron(\"ANTHROPIC_API_KEY\")=\"$dummy\")" \
  'Halt'
check_session "the runner's inline ProviderConfig is written as a System Default Settings row: the key is the placeholder of ANTHROPIC_API_KEY" $NS \
  "CHK|row-provider|1" \
  'Set pc={"model_provider":"anthropic","api_key":"@{env:ANTHROPIC_API_KEY}","base_url":($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")),"http_config":{"custom_headers":{"x-ocutalon-mockkey":"bridge-example"}}}.%ToJSON()' \
  'Set r=##class(Ens.Config.DefaultSettings).%New() Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="TriageAgent",r.HostClassName="*",r.SettingName="ProviderConfig",r.SettingValue=pc,r.Description="Written by release/standalone-bridge.sh in a throwaway namespace." Write !,"CHK|row-provider|",r.%Save()' \
  'Halt'
# The governance of the example's tools is two more System Default Settings rows of Decide, as a developer writes them (AD-5, AD-10, AD-19,
# AD-31), read live, so no apply follows: ToolClassification classifies two of the three tools by their class and name (example_count_items is
# safe and read-only, example_forward_item is risky; example_archive_item has no entry, so it is unclassified), and ApprovalRole names the
# role whose members may answer. The classification is the one place that classifies the tools: they declare none in code. The value is
# written into an ObjectScript string, so its quotes are doubled.
tools_class=OcuTalon.BridgeExample.Tools
tool_json='[{"class":"'$tools_class'","tool":"example_count_items","classification":"safe","readOnly":1},{"class":"'$tools_class'","tool":"example_forward_item","classification":"risky"}]'
check_session "the ToolClassification row of Decide classifies example_count_items safe and read-only and example_forward_item risky" $NS \
  "CHK|row-set|1" \
  "$(row_set Decide ToolClassification "${tool_json//\"/\"\"}")" \
  'Halt'
check_session "the ApprovalRole row of Decide names the role ExampleApprovers, which is not OcuTalon's" $NS \
  "CHK|row-set|1" \
  "$(row_set Decide ApprovalRole ExampleApprovers)" \
  'Halt'
# The role and its two users are fixtures of this throwaway namespace's instance, and nothing of the product creates a role or a user. The
# users cannot sign in (disabled, with a random password that is generated in the session and printed nowhere); ExampleApprover holds the
# role (IRIS refuses a user and a role of one name, so the role is ExampleApprovers) and ExampleViewer holds none, so Approval.Answer, which reads the answerer's recursed role set, lets the first answer and refuses the second.
check_session "the role ExampleApprovers is created, with the user ExampleApprover that holds it and the user ExampleViewer that does not" %SYS \
  "CHK|role|1
CHK|user-approver|1
CHK|user-viewer|1
CHK|approver-holds|1
CHK|viewer-holds|0" \
  'Set sc=##class(Security.Roles).Create("ExampleApprovers","Throwaway role of release/standalone-bridge.sh: the approval role of the bridge example.","") Write !,"CHK|role|",$SYSTEM.Status.IsOK(sc)' \
  'Set pw="Aa1-"_$ZConvert($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)),"L")' \
  'Set sc=##class(Security.Users).Create("ExampleApprover","ExampleApprovers",pw,"Example approver (throwaway)","","","",0,0,"Throwaway user of release/standalone-bridge.sh.") Write !,"CHK|user-approver|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|user-approver-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set sc=##class(Security.Users).Create("ExampleViewer","",pw,"Example viewer (throwaway)","","","",0,0,"Throwaway user of release/standalone-bridge.sh.") Write !,"CHK|user-viewer|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|user-viewer-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set pw=""' \
  'Set sc=$SYSTEM.Security.GetUserRecursedRoleSet("ExampleApprover",.roles) Write !,"CHK|approver-holds|",($SYSTEM.Status.IsOK(sc)&&($ListFind($ListFromString($ZConvert($Get(roles),"L")),"exampleapprovers")>0))' \
  'Set sc=$SYSTEM.Security.GetUserRecursedRoleSet("ExampleViewer",.roles) Write !,"CHK|viewer-holds|",($SYSTEM.Status.IsOK(sc)&&($ListFind($ListFromString($ZConvert($Get(roles),"L")),"exampleapprovers")>0))' \
  'Halt'
if [ "$fails" -ne 0 ]; then
  sed -n 's/^CHK|\(user-[a-z]*-error\)|/  \1: /p' "$tmp/actual.chk"
  die "the settings of the example could not be written"
fi

# --- 4. the example production: start, the runner's settings, the extensions and the audit entry ---

# The ObjectScript lines that the checks below share. frag <name> < lines: sets the variable to the lines.
frag() { IFS= read -r -d '' "$1" || true; }

# alive: waits up to 90 s until the ten job items of the example are Alive, and prints their number.
frag F_ALIVE <<'EOF'
Set items=$ListBuild("Decide","TriageAgent","AgentSteps","ExampleTriage","ExampleRouter","ExampleNotifyOut","ExampleDigestOut","ExampleFallbackOut","ApprovalHold","OcuTalonApprovals")
For k=1:1:90 { Kill alive Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate"),x=rs.Execute() While rs.Next() { If (rs.Get("State")="Alive")&&($ListFind(items,rs.Get("ConfigName"))) Set alive(rs.Get("ConfigName"))=1 } Set n=0,x="" For  { Set x=$Order(alive(x)) Quit:x=""  Set n=n+1 } Quit:n>=10  Hang 1 }
Write !,"CHK|jobs|",n
EOF
# apply: the one helper that makes a saved or deleted System Default Settings row take effect (see the header).
frag F_APPLY <<'EOF'
Set sc=##class(Ens.Director).UpdateProduction(30) Write !,"CHK|apply|",$SYSTEM.Status.IsOK(sc)
EOF

# diagnose: the error rows of the event log, printed after a failure.
diagnose() {
  check_session "diagnosis: the event log of $NS holds these error rows" $NS \
    "CHK|diagnosis|done" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 6 ConfigName,SUBSTRING(Text,1,200) FROM Ens_Util.Log WHERE Type IN (2,3) ORDER BY ID DESC") While rs.%Next() { Write !,"CHK|row|",rs.%GetData(1),"|",rs.%GetData(2) }' \
    'Write !,"CHK|diagnosis|done"' \
    'Halt'
  sed -n 's/^CHK|row|/  event log: /p' "$tmp/actual.chk" | sed "s/$dummy/<dummy key>/g"
}

check_session "the example production starts: ten jobs are Alive and ExampleItemIn is enabled" $NS \
  "CHK|start|1
CHK|jobs|10
CHK|itemin-enabled|1
CHK|active|$PRODUCTION" \
  'Set sc=##class(Ens.Director).StartProduction("OcuTalon.BridgeExample.Production") Write !,"CHK|start|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|start-error|",$SYSTEM.Status.GetErrorText(sc)' \
  "$F_ALIVE" \
  'Set p=##class(Ens.Config.Production).%OpenId("OcuTalon.BridgeExample.Production") Set en=0 For i=1:1:p.Items.Count() { Set it=p.Items.GetAt(i) If it.Name="ExampleItemIn" Set en=it.Enabled } Write !,"CHK|itemin-enabled|",en' \
  'Write !,"CHK|active|",##class(Ens.Director).GetActiveProductionName()' \
  'Halt'
if [ "$fails" -ne 0 ]; then
  diagnose
  die "the example production did not start with its ten jobs"
fi
check_session "the runner runs the example agent, which is on its allow-list, and checks its reply against DecisionPayload" $NS \
  "CHK|AgentClass|OcuTalon.BridgeExample.Agent
CHK|AgentAllowList|OcuTalon.BridgeExample.Agent
CHK|ReplyClass|OcuTalon.Bridge.Msg.DecisionPayload" \
  'For s="AgentClass","AgentAllowList" { Write !,"CHK|",s,"|",##class(Ens.Director).GetAdapterSettingValue("OcuTalon.BridgeExample.Production||TriageAgent",s) }' \
  'Write !,"CHK|ReplyClass|",##class(OcuTalon.Bridge.Process.Decide).ReplyClassOf("TriageAgent")' \
  'Halt'
check_session "the three extension settings of Decide give the three base classes" $NS \
  "CHK|HostSinkClass|OcuTalon.Bridge.Ext.HostSink
CHK|ReplyFilterClass|OcuTalon.Bridge.Ext.ReplyFilter
CHK|ClassificationClass|OcuTalon.Bridge.Ext.Classification" \
  'For s="HostSinkClass","ReplyFilterClass","ClassificationClass" { Write !,"CHK|",s,"|",##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(s) }' \
  'Halt'
check_session "the rows of check 3 are read live by the director, the gate classifies the example's three tools only from the ToolClassification row, and the agent has its toolset" $NS \
  "CHK|ApprovalRole|ExampleApprovers
CHK|ToolClassification|$tool_json
CHK|class-count|safe:1:setting
CHK|class-forward|risky:0:setting
CHK|class-archive|:0:
CHK|toolset|OcuTalon.BridgeExample.ToolSet
CHK|tools|3" \
  'Write !,"CHK|ApprovalRole|",##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ApprovalRole","OcuTalon.BridgeExample.Production")' \
  'Write !,"CHK|ToolClassification|",##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ToolClassification","OcuTalon.BridgeExample.Production")' \
  'Set c=##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf("OcuTalon.BridgeExample.Tools","example_count_items") Write !,"CHK|class-count|",c.classification,":",c.readOnly,":",c.by' \
  'Set c=##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf("OcuTalon.BridgeExample.Tools","example_forward_item") Write !,"CHK|class-forward|",c.classification,":",c.readOnly,":",c.by' \
  'Set c=##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf("OcuTalon.BridgeExample.Tools","example_archive_item") Write !,"CHK|class-archive|",c.classification,":",c.readOnly,":",c.by' \
  'Write !,"CHK|toolset|",$Parameter("OcuTalon.BridgeExample.Agent","TOOLSETS")' \
  'Write !,"CHK|tools|",##class(OcuTalon.BridgeExample.ToolSet).%New().%Discover().tools.%Size()' \
  'Halt'
marker="standalone-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
check_session "an Action entry with the run's marker is written through OcuTalon.Bridge.Audit" $NS \
  "CHK|audit-write|1" \
  "Set sc=##class(OcuTalon.Bridge.Audit).Write(\"Action\",{\"marker\":\"$marker\",\"user\":(\$USERNAME),\"sessionRef\":\"\",\"channel\":\"system\"},\"standalone bridge $marker\") Write !,\"CHK|audit-write|\",\$SYSTEM.Status.IsOK(sc)" \
  'Halt'

# --- 5. the matrix: each item goes through ExampleItemIn and is polled to its routed header ---

# find: the session of the item that Send answered with (iid).
frag F_FIND <<'EOF'
Set iRow="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID FROM OcuTalon_BridgeExample_Msg.Item WHERE ItemId = ? ORDER BY ID DESC",iid) If rs.%Next() { Set iRow=rs.%GetData(1) }
Set sid="" For k=1:1:20 { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? ORDER BY ID","OcuTalon.BridgeExample.Msg.Item",iRow) If rs.%Next() { Set sid=rs.%GetData(1) } Quit:sid'=""  Hang 0.5 }
Write !,"CHK|session|",(sid'="")
EOF
# await: polls for up to wait seconds until the router's Decided header and, when target is set, its send to the target are Completed.
frag F_AWAIT <<'EOF'
Set done=0 For k=1:1:(wait*2) { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = ? AND MessageBodyClassName = ? AND Status = 9",sid,"ExampleRouter","OcuTalon.BridgeExample.Msg.Decided") Do rs.%Next() Set done=rs.%GetData(1) If done,target'="" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND TargetConfigName = ? AND Status = 9",sid,"ExampleRouter",target) Do rs.%Next() Set done=rs.%GetData(1) } Quit:done  Hang 0.5 }
Write !,"CHK|completed|",(done>0)
Set routed="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TargetConfigName FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID",sid,"ExampleRouter") While rs.%Next() { Set routed=routed_$Select(routed="":"",1:",")_rs.%GetData(1) }
Write !,"CHK|routed|",$Select(routed="":"none",1:routed)
EOF
# decision: the one DecisionResponse of the session, and the Decision row, the Usage rows, the runner requests and the tool steps of its Ref.
frag F_DECISION <<'EOF'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*), MIN(MessageBodyId) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ?",sid,"OcuTalon.Bridge.Msg.DecisionResponse") Do rs.%Next() Write !,"CHK|responses|",rs.%GetData(1) Set resp="" If rs.%GetData(1)=1 { Set resp=##class(OcuTalon.Bridge.Msg.DecisionResponse).%OpenId(rs.%GetData(2)) }
If $IsObject(resp) { Write !,"CHK|outcome|",resp.Outcome,!,"CHK|fallback|",resp.Fallback,!,"CHK|reason|",resp.FallbackReason,!,"CHK|model|",resp.Model }
Set ref="" Set:$IsObject(resp) ref=resp.DecisionRef
Set row="" If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(iid,"decide",.rid) { Set row=##class(OcuTalon.Bridge.Data.Decision).%OpenId(rid) }
If $IsObject(row) { Write !,"CHK|row|",row.Fallback,":",row.FallbackReason,":",row.Outcome,":",(row.Ref=ref),":",(row.TraceSessionId=sid) }
Write !,"CHK|reasons|",$Select($IsObject(resp):(resp.Reasons'=""),1:"?"),":",$Select($IsObject(row):(row.Reasons'=""),1:"?")
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?",ref) Do rs.%Next() Write !,"CHK|usage-rows|",rs.%GetData(1)
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND TargetConfigName = ?",sid,"Decide","TriageAgent") Do rs.%Next() Write !,"CHK|runner-requests|",rs.%GetData(1)
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Msg.AgentStep WHERE DecisionRef = ? AND StepKind = ?",ref,"tool") Do rs.%Next() Write !,"CHK|tool-steps|",rs.%GetData(1)
EOF
# priced: for a decision that reached the model, its CostUSD is Price.CostFor of its model and tokens and its one Usage row's, and the
# Decision row holds the same model and cost and input tokens above 0.
frag F_PRICED <<'EOF'
Set exp=##class(OcuTalon.Bridge.Data.Price).CostFor(resp.Model,resp.InputTokens-resp.CacheReadTokens-resp.CacheWriteTokens,resp.CacheReadTokens,resp.CacheWriteTokens,resp.OutputTokens)
Write !,"CHK|cost|",((exp'="")&&(exp>0)&&($ZABS(resp.CostUSD-exp)<0.000001))
Write !,"CHK|tokens|",((resp.InputTokens>0)&&(resp.OutputTokens'="")&&(resp.CacheReadTokens'="")&&(resp.CacheWriteTokens'=""))
Set uid="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? ORDER BY ID",ref) If rs.%Next() { Set uid=rs.%GetData(1) }
Set u="" If uid'="" { Set u=##class(OcuTalon.Bridge.Data.Usage).%OpenId(uid) }
If $IsObject(u) { Write !,"CHK|usage|",u.Agent,":",u.Model,":",($ZABS(u.CostUSD-resp.CostUSD)<0.000001) }
Write !,"CHK|row-priced|",($IsObject(row)&&(row.Model=resp.Model)&&(row.InputTokens>0)&&($ZABS(row.CostUSD-resp.CostUSD)<0.000001))
EOF

# item_check <label> <expected CHK lines> <wait seconds> <routed target or ""> <subject> <body> [<script line>...]: sends the item, finds its
# session, polls for the routing and runs the shared lines and the extra ones in one IRIS session. The item's provenance is the optional
# variable ITEM_PROVENANCE of the call (ITEM_PROVENANCE=user item_check ...); with none the item is untrusted, as Send makes it.
item_check() {
  local label=$1 expected=$2 wait=$3 target=$4 subject=$5 body=$6 send
  shift 6
  send=$(printf 'Set sc=##class(OcuTalon.BridgeExample.ItemIn).Send("%s","%s","%s",.iid) Write !,"CHK|send|",$SYSTEM.Status.IsOK(sc)' "$subject" "$body" "${ITEM_PROVENANCE:-}")
  check_session "$label" $NS "$expected" "$send" "Set wait=$wait,target=\"$target\"" "$F_FIND" "$F_AWAIT" "$F_DECISION" "$@" 'Halt'
}

# provider_key <value>: sets the api_key of the ProviderConfig row of TriageAgent. The row is updated with SQL and %NOCHECK because
# the object save validates the setting by expanding its @{env:} placeholders, which refuses a variable that is not set.
provider_key() {
  printf '%s\n' \
    "Set rid=\"\" Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = ? AND SettingName = ?\",\"$PRODUCTION\",\"TriageAgent\",\"ProviderConfig\") If rs.%Next() { Set rid=rs.%GetData(1) }" \
    "Set r=##class(Ens.Config.DefaultSettings).%OpenId(rid) Set cfg={}.%FromJSON(r.SettingValue) Do cfg.%Set(\"api_key\",\"$1\") Set up=##class(%SQL.Statement).%ExecDirect(,\"UPDATE %NOCHECK Ens_Config.DefaultSettings SET SettingValue = ? WHERE ID = ?\",cfg.%ToJSON(),rid) Write !,\"CHK|row-set|\",(up.%SQLCODE=0)"
}

# 5a. the happy path
frag F_HAPPY <<'EOF'
Set sig="",last="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT SourceConfigName, TargetConfigName, MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName <> ? AND TargetConfigName <> ? ORDER BY ID",sid,"Ens.Alarm","Ens.Alarm") While rs.%Next() { Set part=rs.%GetData(1)_">"_rs.%GetData(2)_":"_$Piece(rs.%GetData(3),".",$Length(rs.%GetData(3),".")) If part'=last { Set sig=sig_$Select(sig="":"",1:";")_part,last=part } }
Write !,"CHK|trace|",sig
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MIN(MessageBodyId) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND TargetConfigName = ?",sid,"ExampleTriage","Decide") Do rs.%Next() Set rq=##class(OcuTalon.Bridge.Msg.Request).%OpenId(rs.%GetData(1))
If $IsObject(rq) { Write !,"CHK|request|",rq.Kind,"|",rq.OwnerRef,"|",rq.Channel,"|",rq.Provenance,"|",(rq.ItemId=iid),"|",rq.Summary,"|",(rq.Input'="") }
Write !,"CHK|confidence|",resp.Confidence,":",(resp.Reasons'=""),":",(resp.AgentStepCount>0)
Set bad=1 For k=1:1:60 { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ? AND Status <> 9",sid,"OcuTalon.Bridge.Msg.AgentStep") Do rs.%Next() Set bad=rs.%GetData(1) Quit:bad=0  Hang 0.5 }
Set n=0,ok=1 Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ? AND SourceConfigName = ? AND TargetConfigName = ? ORDER BY ID",sid,"OcuTalon.Bridge.Msg.AgentStep","Decide","AgentSteps") While rs.%Next() { Set st=##class(OcuTalon.Bridge.Msg.AgentStep).%OpenId(rs.%GetData(1)) Set n=n+1 If ('$IsObject(st))||(st.Position'=n)||(st.Label="")||(st.Summary="")||(st.DurationMs="")||(st.EstimatedTokens'>0)||(st.DecisionRef'=ref)||((n=1)&&(st.StepKind'="model")) Set ok=0 }
Write !,"CHK|steps|",(n>0),":",ok,":",(bad=0)
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 2","AgentSteps") Do rs.%Next() Write !,"CHK|steps-errors|",rs.%GetData(1)
EOF
happy_trace="ExampleItemIn>ExampleTriage:Item;ExampleTriage>Decide:Request;Decide>TriageAgent:Request;TriageAgent>Decide:Reply;Decide>AgentSteps:AgentStep;Decide>ExampleTriage:DecisionResponse;ExampleTriage>ExampleRouter:Decided;ExampleRouter>ExampleNotifyOut:Decided"
happy_subject="Standalone bridge example item"
item_check "an item through ExampleItemIn: the trace, the request, the decision tellnow, its price and its steps, routed to ExampleNotifyOut only" \
  "CHK|send|1
CHK|session|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|0
CHK|reason|
CHK|model|claude-haiku-5-5
CHK|row|0::tellnow:1:1
CHK|reasons|1:1
CHK|usage-rows|1
CHK|runner-requests|1
CHK|tool-steps|0
CHK|cost|1
CHK|tokens|1
CHK|usage|TriageAgent:claude-haiku-5-5:1
CHK|row-priced|1
CHK|trace|$happy_trace
CHK|request|decide|instance|system|untrusted|1|$happy_subject|1
CHK|confidence|.7:1:1
CHK|steps|1:1:1
CHK|steps-errors|0" \
  60 ExampleNotifyOut "$happy_subject" "The example item of the standalone bridge check." \
  "$F_PRICED" "$F_HAPPY"

# 5b. digest and ignore
item_check "an item with the marker bridge-example-digest is decided digest and routed to ExampleDigestOut only" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleDigestOut
CHK|responses|1
CHK|outcome|digest
CHK|fallback|0
CHK|row|0::digest:1:1
CHK|usage-rows|1
CHK|cost|1
CHK|usage|TriageAgent:claude-haiku-5-5:1
CHK|row-priced|1" \
  60 ExampleDigestOut "Weekly summary" "A weekly summary arrived. [[mock:bridge-example-digest]]" \
  "$F_PRICED"
item_check "an item with the marker bridge-example-ignore is decided ignore, and the router sends it to no operation" \
  "CHK|send|1
CHK|completed|1
CHK|routed|none
CHK|responses|1
CHK|outcome|ignore
CHK|fallback|0
CHK|row|0::ignore:1:1
CHK|usage-rows|1
CHK|cost|1
CHK|usage|TriageAgent:claude-haiku-5-5:1
CHK|row-priced|1" \
  60 "" "Newsletter" "A newsletter arrived. [[mock:bridge-example-ignore]]" \
  "$F_PRICED"
item_check "an item with the marker bridge-example-act is decided act and routed to ExampleNotifyOut, like tellnow" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|responses|1
CHK|outcome|act
CHK|fallback|0
CHK|row|0::act:1:1
CHK|usage-rows|1
CHK|cost|1
CHK|usage|TriageAgent:claude-haiku-5-5:1
CHK|row-priced|1" \
  60 ExampleNotifyOut "Action needed" "An item that asks for an action. [[mock:bridge-example-act]]" \
  "$F_PRICED"

# 5c. the model row
check_session "the model row: TriageAgent Model is claude-sonnet-5-5 as a System Default Settings row, applied" $NS \
  "CHK|row-set|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_set TriageAgent Model claude-sonnet-5-5)" "$F_APPLY" "$F_ALIVE" 'Halt'
item_check "the next decision names the new model: the DecisionResponse, the Decision row and the Usage row, at the Sonnet price" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|outcome|tellnow
CHK|fallback|0
CHK|model|claude-sonnet-5-5
CHK|usage-rows|1
CHK|cost|1
CHK|usage|TriageAgent:claude-sonnet-5-5:1
CHK|row-priced|1" \
  60 ExampleNotifyOut "Model row item" "An item that is decided with the changed model." \
  "$F_PRICED"
check_session "the model row is removed and applied again" $NS \
  "CHK|row-del|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_del TriageAgent Model)" "$F_APPLY" "$F_ALIVE" 'Halt'

# 5c. the four fallbacks: every one is tellnow with Fallback 1, its reason on the row and the DecisionResponse, routed to
# ExampleFallbackOut, with no reasons kept and no tool step.
check_session "the budget row: Decide DecisionTokenBudget is 1 as a System Default Settings row, applied" $NS \
  "CHK|row-set|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_set Decide DecisionTokenBudget 1)" "$F_APPLY" "$F_ALIVE" 'Halt'
item_check "budget: an item over the budget takes the fallback budget: no runner request, no Usage row, routed to ExampleFallbackOut" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleFallbackOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|1
CHK|reason|budget
CHK|row|1:budget:tellnow:1:1
CHK|reasons|0:0
CHK|usage-rows|0
CHK|runner-requests|0
CHK|tool-steps|0
CHK|outcome-log|1" \
  60 ExampleFallbackOut "Budget row item" "An item that is over the token budget of one." \
  'Set n=0 For k=1:1:20 { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 4 AND Text [ ? AND Text [ ?","ExampleFallbackOut",ref,"fallback budget") Do rs.%Next() Set n=rs.%GetData(1) Quit:n  Hang 0.5 } Write !,"CHK|outcome-log|",n'
check_session "the budget row is removed and applied again" $NS \
  "CHK|row-del|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_del Decide DecisionTokenBudget)" "$F_APPLY" "$F_ALIVE" 'Halt'

check_session "the no-key row: the key of the ProviderConfig row names a variable that the stack never sets" $NS \
  "CHK|row-set|1" \
  "$(provider_key '@{env:OCUTALON_EXAMPLE_UNSET_KEY}')" 'Halt'
item_check "no key: an item takes the fallback no_key: no runner request, routed to ExampleFallbackOut" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleFallbackOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|1
CHK|reason|no_key
CHK|row|1:no_key:tellnow:1:1
CHK|reasons|0:0
CHK|usage-rows|0
CHK|runner-requests|0
CHK|tool-steps|0" \
  60 ExampleFallbackOut "No key item" "An item that is sent with no model key."
check_session "the no-key row is restored to the placeholder of ANTHROPIC_API_KEY" $NS \
  "CHK|row-set|1" \
  "$(provider_key '@{env:ANTHROPIC_API_KEY}')" 'Halt'

item_check "refusal: an item with the marker bridge-example-refusal takes the fallback refusal, routed to ExampleFallbackOut" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleFallbackOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|1
CHK|reason|refusal
CHK|row|1:refusal:tellnow:1:1
CHK|reasons|0:0
CHK|usage-rows|1
CHK|runner-requests|1
CHK|tool-steps|0" \
  60 ExampleFallbackOut "Refusal item" "An item that the model refuses. [[mock:bridge-example-refusal]]"

check_session "the timeout row: Decide TimerSeconds is 12 as a System Default Settings row, applied" $NS \
  "CHK|row-set|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_set Decide TimerSeconds 12)" "$F_APPLY" "$F_ALIVE" 'Halt'
item_check "timeout: an item whose reply is held 25 s takes the fallback timeout after 12 s, routed to ExampleFallbackOut" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleFallbackOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|1
CHK|reason|timeout
CHK|row|1:timeout:tellnow:1:1
CHK|reasons|0:0
CHK|runner-requests|1
CHK|tool-steps|0
CHK|duration|1" \
  60 ExampleFallbackOut "Timeout item" "An item whose reply is late. [[mock:bridge-example-late]]" \
  'Write !,"CHK|duration|",($IsObject(resp)&&(resp.DurationMs>=12000)&&(resp.DurationMs<=17999)&&$IsObject(row)&&(row.DurationMs>=12000)&&(row.DurationMs<=17999))'
check_session "the timeout row is removed and applied again" $NS \
  "CHK|row-del|1
CHK|apply|1
CHK|jobs|10" \
  "$(row_del Decide TimerSeconds)" "$F_APPLY" "$F_ALIVE" 'Halt'

# 5d. the production keeps running: the runner may still hold the late call, so the item polls for up to 90 s
item_check "the production keeps running: every job is Alive and a plain item gets a usable tellnow from the default model, routed to ExampleNotifyOut" \
  "CHK|send|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|0
CHK|model|claude-haiku-5-5
CHK|row|0::tellnow:1:1
CHK|usage-rows|1
CHK|cost|1
CHK|usage|TriageAgent:claude-haiku-5-5:1
CHK|row-priced|1
CHK|jobs|10" \
  90 ExampleNotifyOut "Keeps running item" "A plain item after the fallbacks." \
  "$F_PRICED" "$F_ALIVE"

# --- 5e. the example's own tools: the hold, the answers, the replay, rejection, expiry and the untrusted denial (Story 13.2) ---
# Each row of the matrix of Story 13.2 runs in order against the ten-job production, with the rows of check 3 in force: example_count_items
# is classified safe and read-only by its row, example_forward_item risky, and example_archive_item has no entry. Every answer goes through
# OcuTalon.Bridge.Approval.Answer, and nothing writes the state of an ApprovalRequest row. The one fixture write is the ExpiresAt of the row
# of the expiry case, moved 1 s into the past as Test.Bridge.Approval does. The refs and the session of a row are read back from the
# session's output and handed to the next row. A tool's own event-log line ("ExampleTools: example_<name>_item ran") counts its runs.

# The lines that the rows share. A row sets rowsBefore (the number of ApprovalRequest rows before it), wantSteps (the number of tool steps
# that its session holds when it is done) and sid (its session).
frag F_RUNS <<'EOF'
For t="forward","archive" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text = ?","ExampleTools: example_"_t_"_item ran") Do rs.%Next() Write !,"CHK|",t,"-runs|",rs.%GetData(1) }
EOF
frag F_ADDED <<'EOF'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest") Do rs.%Next() Write !,"CHK|rows-added|",(rs.%GetData(1)-rowsBefore)
EOF
# steps: the tool steps of the session in header order, as label=status, and how many of the denied ones carry the HELD and the UNTRUSTED
# sentence of the gate in their Summary. It polls for up to 60 s until the session holds wantSteps tool steps.
frag F_STEPS <<'EOF'
Set held=$ZStrip(##class(OcuTalon.Bridge.Policy.Gate).#HELD,">","."),untr=$ZStrip(##class(OcuTalon.Bridge.Policy.Gate).#UNTRUSTED,">",".")
For k=1:1:120 { Set list="",nt=0,nh=0,nu=0 Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ? AND SourceConfigName = ? AND TargetConfigName = ? ORDER BY ID",sid,"OcuTalon.Bridge.Msg.AgentStep","Decide","AgentSteps") While rs.%Next() { Set st=##class(OcuTalon.Bridge.Msg.AgentStep).%OpenId(rs.%GetData(1)) If $IsObject(st)&&(st.StepKind="tool") { Set nt=nt+1,list=list_$Select(list="":"",1:";")_st.Label_"="_st.Status If st.Status="denied" { If st.Summary[held { Set nh=nh+1 } If st.Summary[untr { Set nu=nu+1 } } } } Quit:nt>=wantSteps  Hang 0.5 }
Write !,"CHK|tool-step-list|",list,!,"CHK|held-steps|",nh,!,"CHK|untrusted-steps|",nu
EOF
# trace: whether the session holds the start of a hold and the hold's Workflow task, and how many replays reached Decide and of what kind.
frag F_TRACE <<'EOF'
Set sig="|" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT SourceConfigName, TargetConfigName, MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID",sid) While rs.%Next() { Set sig=sig_rs.%GetData(1)_">"_rs.%GetData(2)_":"_$Piece(rs.%GetData(3),".",$Length(rs.%GetData(3),"."))_"|" }
Write !,"CHK|approval-trace|",(sig["|ApprovalStartIn>ApprovalHold:ApprovalStart|"),":",(sig["|ApprovalHold>OcuTalonApprovals:TaskRequest|")
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*), MIN(MessageBodyId) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND TargetConfigName = ? AND MessageBodyClassName = ?",sid,"ApprovalHold","Decide","OcuTalon.Bridge.Msg.Request") Do rs.%Next() Set nrep=rs.%GetData(1),rq="" If nrep=1 { Set rq=##class(OcuTalon.Bridge.Msg.Request).%OpenId(rs.%GetData(2)) }
Write !,"CHK|replay-request|",nrep,":",$Select($IsObject(rq):rq.Kind,1:"")
EOF
# request: the newest ApprovalRequest row, its Ref and its fields.
frag F_REQUEST <<'EOF'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID FROM OcuTalon_Bridge_Data.ApprovalRequest ORDER BY ID DESC") Do rs.%Next() Set req=##class(OcuTalon.Bridge.Data.ApprovalRequest).%OpenId(rs.%GetData(1))
Write !,"CHK|aref|",req.Ref,!,"CHK|request|",req.Kind,"|",req.State,"|",req.ToolName,"|",req.ToolArguments,"|",req.ToolSource,"|",req.Runner,"|",req.RequiredRole
EOF
# state: the state and the Result of the row aref, polled for up to 60 s until it is done or failed when final is 1 (final 0 reads it once).
frag F_STATE <<'EOF'
For k=1:1:120 { Set req=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(aref) Do req.%Reload() Quit:('final)||(req.State="done")||(req.State="failed")  Hang 0.5 }
Write !,"CHK|state|",req.State,!,"CHK|result|",req.Result
EOF
# answer <action> <user>: the line that answers the row aref through Approval.Answer, as the user, on the channel system.
answer_line() {
  printf 'Set res=##class(OcuTalon.Bridge.Approval).Answer(aref,"%s","system","%s","",.winner) Write !,"CHK|answer|",res,!,"CHK|winner|",winner.action' "$1" "$2"
}
# approval_rows: the number of ApprovalRequest rows of the namespace.
approval_rows() {
  printf '%s\n' 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest") Do rs.%Next() Write !,"CHK|n|",rs.%GetData(1)' 'Halt' | session_value $NS n
}
frag F_POSTS <<'EOF'
Set f=##class(%Stream.FileCharacter).%New() Set lsc=f.LinkToFile("/opt/ocutalon/mock-log/requests.jsonl") Set total=0
While 'f.AtEnd { Set line=f.ReadLine(4000000) Continue:line=""  Set e={}.%FromJSON(line) If (e.method="POST")&&(e.model'="") Set total=total+1 }
Write !,"CHK|posts|",total
EOF
# mock_posts: the number of model requests in the mock's log so far.
mock_posts() { printf '%s\n' "$F_POSTS" 'Halt' | session_value $NS posts; }
# from_output <name>: the value of the CHK|<name>| line of the last session's output.
from_output() { sed -n "s/^CHK|$1|//p" "$tmp/actual.chk" | head -n 1; }
# held_expected <tool> <arguments> <label> <forward runs> <archive runs>: the lines of a user item whose call is held, up to its session.
held_expected() {
  printf 'CHK|send|1\nCHK|session|1\nCHK|completed|1\nCHK|routed|ExampleNotifyOut\nCHK|responses|1\nCHK|outcome|act\nCHK|fallback|0\nCHK|row|0::act:1:1\nCHK|tool-steps|1\nCHK|rows-added|1\nCHK|request|tool_call|pending|%s|%s|%s|TriageAgent|ExampleApprovers\nCHK|forward-runs|%s\nCHK|archive-runs|%s\nCHK|tool-step-list|%s=denied\nCHK|held-steps|1\nCHK|untrusted-steps|0\nCHK|approval-trace|1:1\nCHK|replay-request|0:' \
    "$1" "$2" "$tools_class" "$4" "$5" "$3"
}

# Read-only: an untrusted item. The mock calls example_count_items, which the row classifies safe and read-only, so it runs without approval.
rows_now=$(approval_rows)
item_check "read-only: an untrusted item's call of example_count_items runs with no approval, as an ok tool step of the decision's session, and the decision is usable" \
  "CHK|send|1
CHK|session|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|0
CHK|row|0::tellnow:1:1
CHK|tool-steps|1
CHK|rows-added|0
CHK|forward-runs|0
CHK|archive-runs|0
CHK|tool-step-list|Counting the example's items=ok
CHK|held-steps|0
CHK|untrusted-steps|0
CHK|approval-trace|0:0" \
  60 ExampleNotifyOut "Count items" "How many items does the example hold? [[mock:bridge-example-tool-read]]" \
  "Set rowsBefore=$rows_now,wantSteps=1" "$F_ADDED" "$F_RUNS" "$F_STEPS" "$F_TRACE"

# Risky held: a user item. The mock calls example_forward_item {"team":"operations"}, which the row classifies risky.
rows_now=$(approval_rows)
ITEM_PROVENANCE=user item_check "risky held: a user item's call of example_forward_item does not run: one pending tool_call row with the call, its denied step, the hold's start and its Workflow task in the item's session" \
  "$(held_expected example_forward_item '{"team":"operations"}' 'Forwarding the item' 0 0)" \
  60 ExampleNotifyOut "Forward item" "Please forward this item to operations. [[mock:bridge-example-tool-risky]]" \
  "Set rowsBefore=$rows_now,wantSteps=1" "$F_ADDED" "$F_REQUEST" "$F_RUNS" "$F_STEPS" "$F_TRACE" 'Write !,"CHK|sid|",sid'
risky_ref=$(from_output aref)
risky_sid=$(from_output sid)

# Unclassified held: a user item. The mock calls example_archive_item {}, which no row classifies.
rows_now=$(approval_rows)
ITEM_PROVENANCE=user item_check "unclassified held: a user item's call of example_archive_item, which no row classifies, does not run either: one pending tool_call row, its denied step, and the hold in the item's session" \
  "$(held_expected example_archive_item '{}' 'Archiving the item' 0 0)" \
  60 ExampleNotifyOut "Archive item" "Please archive this item. [[mock:bridge-example-tool-unclassified]]" \
  "Set rowsBefore=$rows_now,wantSteps=1" "$F_ADDED" "$F_REQUEST" "$F_RUNS" "$F_STEPS" "$F_TRACE" 'Write !,"CHK|sid|",sid'
unclass_ref=$(from_output aref)
unclass_sid=$(from_output sid)

# Not allowed: ExampleViewer does not hold the role.
check_session "not allowed: ExampleViewer's answer is not_allowed, the row stays pending and nothing runs" $NS \
  "CHK|answer|not_allowed
CHK|state|pending
CHK|forward-runs|0
CHK|archive-runs|0" \
  "Set aref=\"$risky_ref\",final=0" \
  "$(answer_line approve ExampleViewer)" \
  "$F_STATE" "$F_RUNS" 'Halt'

# Approve: ExampleApprover holds the role. The hold replays the call through Decide to TriageAgent with no model request.
rows_now=$(approval_rows)
posts_before=$(mock_posts)
check_session "approve: the answer is done, the row ends done with Result done, the call runs once as an ok step, the replay reaches Decide as a request of kind tool, and the reply says one tool ran" $NS \
  "CHK|answer|done
CHK|state|done
CHK|result|done
CHK|rows-added|0
CHK|forward-runs|1
CHK|archive-runs|0
CHK|tool-step-list|Forwarding the item=denied;Forwarding the item=ok
CHK|replay-request|1:tool
CHK|replay-reply|1:1" \
  "Set aref=\"$risky_ref\",sid=\"$risky_sid\",final=1,rowsBefore=$rows_now,wantSteps=2" \
  "$(answer_line approve ExampleApprover)" \
  "$F_STATE" "$F_ADDED" "$F_RUNS" "$F_STEPS" "$F_TRACE" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ? AND SourceConfigName = ? AND TargetConfigName = ? ORDER BY ID DESC",sid,"OcuTalon.Bridge.Msg.Reply","TriageAgent","Decide") Set rp="" If rs.%Next() { Set rp=##class(OcuTalon.Bridge.Msg.Reply).%OpenId(rs.%GetData(1)) } Write !,"CHK|replay-reply|",$Select($IsObject(rp):rp.ToolsRun_":"_(rp.FailureText=""),1:"none")' \
  'Halt'
posts_after=$(mock_posts)
if [ -n "$posts_before" ] && [ "$posts_before" = "$posts_after" ]; then
  pass "approve: the mock's log gains no model request across the approval and the replay ($posts_before requests before and after)"
else
  fail "approve: the mock's log gained model requests across the approval ($posts_before before, $posts_after after)"
fi

# Second answer: the winner's action is approve and nothing runs again.
check_session "second answer: a reject by ExampleApprover is already_answered with the winner approve, and the tool's line count stays 1" $NS \
  "CHK|answer|already_answered
CHK|winner|approve
CHK|state|done
CHK|forward-runs|1
CHK|archive-runs|0" \
  "Set aref=\"$risky_ref\",final=1" \
  "$(answer_line reject ExampleApprover)" \
  'Hang 3' "$F_STATE" "$F_RUNS" 'Halt'

# Rejected: the unclassified call is rejected, so it never runs.
check_session "rejected: the reject is done, the row is rejected, no replay reaches Decide, and example_archive_item never runs" $NS \
  "CHK|answer|done
CHK|state|rejected
CHK|replay-request|0:
CHK|forward-runs|1
CHK|archive-runs|0" \
  "Set aref=\"$unclass_ref\",sid=\"$unclass_sid\",final=0" \
  "$(answer_line reject ExampleApprover)" \
  'Hang 3' "$F_STATE" "$F_TRACE" "$F_RUNS" 'Halt'

# Expired: a second risky user item; its row's ExpiresAt is moved 1 s into the past, and an approval then finds it expired.
rows_now=$(approval_rows)
ITEM_PROVENANCE=user item_check "expired: a second user item's call of example_forward_item is held again, as a pending row" \
  "$(held_expected example_forward_item '{"team":"operations"}' 'Forwarding the item' 1 0)" \
  60 ExampleNotifyOut "Forward another item" "Please forward this other item to operations. [[mock:bridge-example-tool-risky]]" \
  "Set rowsBefore=$rows_now,wantSteps=1" "$F_ADDED" "$F_REQUEST" "$F_RUNS" "$F_STEPS" "$F_TRACE" 'Write !,"CHK|sid|",sid'
expired_ref=$(from_output aref)
check_session "expired: the row's ExpiresAt is moved 1 s into the past, the approval then answers expired, the row is expired, and the tool's line count stays 1" $NS \
  "CHK|aged|1
CHK|answer|expired
CHK|state|expired
CHK|forward-runs|1
CHK|archive-runs|0" \
  "Set aref=\"$expired_ref\",final=0" \
  'Set row=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(aref) Set row.ExpiresAt=##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Bridge.Time).NowUtc(),-1) Write !,"CHK|aged|",$SYSTEM.Status.IsOK(row.%Save())' \
  "$(answer_line approve ExampleApprover)" \
  'Hang 3' "$F_STATE" "$F_RUNS" 'Halt'

# Untrusted: forward and archive are denied with the UNTRUSTED sentence and raise no request; only the read-only tool runs.
rows_now=$(approval_rows)
item_check "untrusted: an untrusted item's calls of example_forward_item and example_archive_item are denied as untrusted with no request, and only example_count_items runs" \
  "CHK|send|1
CHK|session|1
CHK|completed|1
CHK|routed|ExampleNotifyOut
CHK|responses|1
CHK|outcome|tellnow
CHK|fallback|0
CHK|row|0::tellnow:1:1
CHK|tool-steps|3
CHK|rows-added|0
CHK|forward-runs|1
CHK|archive-runs|0
CHK|tool-step-list|Forwarding the item=denied;Archiving the item=denied;Counting the example's items=ok
CHK|held-steps|0
CHK|untrusted-steps|2
CHK|approval-trace|0:0" \
  60 ExampleNotifyOut "Mixed tools" "Forward this item, archive it and count the items. [[mock:bridge-example-tool-untrusted]]" \
  "Set rowsBefore=$rows_now,wantSteps=3" "$F_ADDED" "$F_RUNS" "$F_STEPS" "$F_TRACE"

if [ "$fails" -ne 0 ]; then diagnose; fi

# --- 6. the mock's log, the dummy key, and the audit entry ---

frag F_MOCKLOG <<'EOF'
Set f=##class(%Stream.FileCharacter).%New() Set lsc=f.LinkToFile("/opt/ocutalon/mock-log/requests.jsonl") Write !,"CHK|log-open|",$SYSTEM.Status.IsOK(lsc)
Set total=0,rej=0,sonnet=0 Kill mk While 'f.AtEnd { Set line=f.ReadLine(4000000) Continue:line=""  Set e={}.%FromJSON(line) If (e.method="POST")&&(e.model'="") { Set total=total+1 Set:(e.rejected="sampling")||(e.rejected="max_tokens") rej=rej+1 Set:e.model="claude-sonnet-5-5" sonnet=sonnet+1 If (e.marker'="")&&(e.rejected="") Set mk(e.marker)=$Get(mk(e.marker))+1 } }
Write !,"CHK|log-requests|",(total>0),!,"CHK|log-rejected|",rej,!,"CHK|log-sonnet|",sonnet
Write !,"CHK|log-markers|",(+$Get(mk("bridge-example-digest"))>0),(+$Get(mk("bridge-example-ignore"))>0),(+$Get(mk("bridge-example-act"))>0),(+$Get(mk("bridge-example-refusal"))>0),(+$Get(mk("bridge-example-late"))>0),(+$Get(mk("bridge-example-tool-read"))>0),(+$Get(mk("bridge-example-tool-risky"))>0),(+$Get(mk("bridge-example-tool-unclassified"))>0),(+$Get(mk("bridge-example-tool-untrusted"))>0)
EOF
check_session "the mock's log holds no request rejected for sampling or max_tokens, one request of the Sonnet model, and a request not rejected for each marker, the four tool markers included" $NS \
  "CHK|log-open|1
CHK|log-requests|1
CHK|log-rejected|0
CHK|log-sonnet|1
CHK|log-markers|111111111" \
  "$F_MOCKLOG" 'Halt'

keysearch() { # keysearch <table> <column>...: a line that prints the number of rows of the table whose columns hold the dummy key
  local table=$1 name=${1##*.} cond="" c
  shift
  for c in "$@"; do cond="$cond${cond:+ OR }$c [ ?"; done
  printf 'Set rs=##class(%%SQL.Statement).%%ExecDirect(,"SELECT COUNT(*) FROM %s WHERE %s"%s) Do rs.%%Next() Write !,"CHK|key-%s|",rs.%%GetData(1)' \
    "$table" "$cond" "$(for c in "$@"; do printf ',key'; done)" "$name"
}
check_session "the run's dummy key is in no AgentStep, Reply, DecisionResponse, Decision, Decided, Request or ApprovalRequest row and in no event-log row of $NS" $NS \
  "CHK|key-AgentStep|0
CHK|key-Reply|0
CHK|key-DecisionResponse|0
CHK|key-Decision|0
CHK|key-Decided|0
CHK|key-Request|0
CHK|key-ApprovalRequest|0
CHK|key-Log|0" \
  "Set key=\"$dummy\"" \
  "$(keysearch OcuTalon_Bridge_Msg.AgentStep Label Summary)" \
  "$(keysearch OcuTalon_Bridge_Msg.Reply Text HostData Steps FailureText)" \
  "$(keysearch OcuTalon_Bridge_Msg.DecisionResponse Reasons Payload FallbackReason)" \
  "$(keysearch OcuTalon_Bridge_Data.Decision Reasons Payload Summary)" \
  "$(keysearch OcuTalon_BridgeExample_Msg.Decided Summary FallbackReason ItemId)" \
  "$(keysearch OcuTalon_Bridge_Msg.Request InputText Summary)" \
  "$(keysearch OcuTalon_Bridge_Data.ApprovalRequest ToolArguments)" \
  "$(keysearch Ens_Util.Log Text)" \
  'Halt'
audit_rows() { # the number of audit rows with the marker in EventData and the description
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventSource = ? AND EventType = ? AND Event = ? AND EventData [ ? AND Description [ ?","OcuTalon","Action","Action","'"$marker"'","'"$marker"'")' \
    'Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' \
    'Halt' | iris_script %SYS | sed -n 's/^CHK|rows|//p' | head -n 1
}
audit_row_visible() { [ "$(audit_rows)" = 1 ]; }
waited_from=$SECONDS
if wait_until 180 audit_row_visible; then
  pass "the Action entry of check 4 is read back from the IRIS audit log after $((SECONDS - waited_from)) s"
else
  fail "the Action entry of check 4 is not in the IRIS audit log within 180 s (rows: '$(audit_rows)')"
fi
# The six entries of the approval cases of 5e (Story 13.2), each matched by the Ref of its row in the entry's event data: the answer that
# approved the forward, the start and the finish of its run (done), the Action entry of the run (action example_forward_item, result done and
# the approvalRef), the answer that rejected the archive, and the expiry of the third row. Each is read with its UTC time, its irisUser
# and its channel; the time must fall after the start of the run (since, UTC).
frag F_AUDIT <<'EOF'
Set specs=$ListBuild($ListBuild("answered-approved","Approval",approved,"""change"":""answered""","""outcome"":""approved"""),$ListBuild("started","Approval",approved,"""change"":""started""","""kind"":""tool_call"""),$ListBuild("finished-done","Approval",approved,"""change"":""finished""","""to"":""done"""),$ListBuild("action","Action",approved,"""action"":""example_forward_item""","""result"":""done"""),$ListBuild("answered-rejected","Approval",rejected,"""change"":""answered""","""outcome"":""rejected"""),$ListBuild("expired","Approval",expired,"""change"":""expired""","""kind"":""tool_call"""))
For i=1:1:$ListLength(specs) { Set spec=$List(specs,i),line="none" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 UTCTimeStamp, EventData FROM %SYS.Audit WHERE EventSource = ? AND EventType = ? AND EventData [ ? AND EventData [ ? AND EventData [ ?","OcuTalon",$List(spec,2),$List(spec,3),$List(spec,4),$List(spec,5)) If rs.%Next() { Set data={}.%FromJSON(rs.%GetData(2)) Set line=data.irisUser_":"_data.channel_":"_(rs.%GetData(1)]]since) } Write !,"CHK|audit-",$List(spec,1),"|",line }
EOF
audit_entries() { # the CHK lines of the six entries, from the IRIS audit log
  printf '%s\n' "Set approved=\"$risky_ref\",rejected=\"$unclass_ref\",expired=\"$expired_ref\",since=\"$since\"" "$F_AUDIT" 'Halt' | iris_script %SYS
}
audit_entries_visible() { audit_entries > "$tmp/audit.chk"; [ "$(grep -c '^CHK|audit-' "$tmp/audit.chk")" = 6 ] && ! grep -q '|none$' "$tmp/audit.chk"; }
printf '%s\n' "CHK|audit-answered-approved|ExampleApprover:system:1" "CHK|audit-started|ExampleApprover:system:1" "CHK|audit-finished-done|ExampleApprover:system:1" \
  "CHK|audit-action|ExampleApprover:system:1" "CHK|audit-answered-rejected|ExampleApprover:system:1" "CHK|audit-expired|ExampleApprover:system:1" > "$tmp/audit.exp"
waited_from=$SECONDS
if wait_until 180 audit_entries_visible; then
  compare_chk "the six approval entries of 5e are read back from the IRIS audit log after $((SECONDS - waited_from)) s, each with its time, its irisUser ExampleApprover and its channel system" "$tmp/audit.chk" "$tmp/audit.exp"
else
  fail "the six approval entries of 5e are not all in the IRIS audit log within 180 s ($(grep '^CHK|audit-' "$tmp/audit.chk" | tr '\n' ' '))"
fi
# The search runs after the read-back: the audit log has then caught up with the entries written before it.
check_session "the run's dummy key is in no IRIS audit entry since the run began" %SYS \
  "CHK|key-audit|0" \
  "Set key=\"$dummy\"" \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM %SYS.Audit WHERE UTCTimeStamp >= ? AND (Description [ ? OR EventData [ ?)\",\"$since\",key,key) Do rs.%Next() Write !,\"CHK|key-audit|\",rs.%GetData(1)" \
  'Halt'

# --- 7. no OcuTalon web application ---

check_session "no web application of $NS names an OcuTalon class or /ocutalon" %SYS \
  "CHK|ocutalon-apps|0" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE NameSpace = ? AND (Name %STARTSWITH ? OR DispatchClass %STARTSWITH ? OR PermittedClasses [ ?)","OCUBRIDGE","/ocutalon","OcuTalon","OcuTalon") Do rs.%Next() Write !,"CHK|ocutalon-apps|",rs.%GetData(1)' \
  'Halt'

# --- 8. the production stops ---

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
