#!/usr/bin/env bash
# Live test of OcuTalon's audit events (Story 0.4, matrix rows 10 to 12): builds the image and starts it in one throwaway
# compose project with the after-start script active, then checks
#   - row 10, the first start: the six events OcuTalon/<T>/<T> for Action, Approval, Pairing, Settings, MCP and Tool exist
#     and are enabled, no other OcuTalon event exists, instance-wide auditing is on (OcuTalon never changes it), and the
#     STEP lines are those of the registry's fixed order;
#   - row 11, the audit write: Bridge.Audit.Write("Action", {"marker": <unique>}, <description>) returns OK, and within
#     the poll (OCUTALON_AUDIT_POLL seconds, 120 by default) one %SYS.Audit row has EventSource OcuTalon, EventType and
#     Event Action, and the marker in its EventData and its description;
#   - row 12, the structural events: with OcuTalon/Tool/Tool disabled, Install.Step.Audit.Run() fails naming it and leaves
#     it disabled, and Bridge.Installer.Run() leaves six events, all enabled; with OcuTalon/MCP/MCP deleted,
#     Install.Step.Audit.Run() fails naming it and creates nothing.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its volume
# and images. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check, and INFO lines for the measured audit behaviour; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t04

version=$(manifest_version src/module.xml)
ipm_version=0.10.10
poll=${OCUTALON_AUDIT_POLL:-120}
marker="t04-$(date +%s)-$$"

six="OcuTalon/Action/Action=1:1;OcuTalon/Approval/Approval=1:1;OcuTalon/Pairing/Pairing=1:1;OcuTalon/Settings/Settings=1:1;OcuTalon/MCP/MCP=1:1;OcuTalon/Tool/Tool=1:1;"

# The script lines that print CHK|<name>|<for each of the six events: name=exists:enabled;>|<number of OcuTalon events>.
events_state() { # events_state <name>
  printf '%s\n' \
    'Zn "OCUTALON" Set names=##class(OcuTalon.Bridge.Audit).Events()' \
    'Zn "%SYS" Set out="",p=0 While $ListNext(names,p,n) { Kill ev Set ex=##class(Security.Events).Exists(n,,,.ev) Set out=out_n_"="_ex_":"_$Select(ex:ev.Enabled,1:0)_";" }' \
    'Set rs=##class(%ResultSet).%New("Security.Events:List") Set sc=rs.Execute("OcuTalon","*","*") Set c=0 While rs.Next() { Set c=c+1 }' \
    "Write !,\"CHK|$1|\",out,\"|\",c" \
    'Halt' | iris_script %SYS
}

# --- row 10: the first start ---

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
  die "row 10 the first start did not end ready within 400 s"
fi
pass "row 10 the first start ended ready"

expected_run "nothing to clear" "installed $ipm_version (was none)" "mapped into OCUTALON" "skipped (package not installed)" \
  "loaded (not installed)" "$version" > "$tmp/expected.row10"
check_log "row 10" "$tmp/expected.row10"

events_state first > "$tmp/actual.first"
printf 'CHK|first|%s|6\n' "$six" > "$tmp/expected.first"
compare_chk "row 10: the six events exist and are enabled, and no other OcuTalon event exists" "$tmp/actual.first" "$tmp/expected.first"

check_session "row 10: instance-wide auditing is on" %SYS "CHK|audit-enabled|1" \
  'Set sc=##class(Security.System).Get("SYSTEM",.sp) Write !,"CHK|audit-enabled|",$Get(sp("AuditEnabled"))' \
  'Halt'

# --- row 11: the audit write ---

printf '%s\n' \
  'Zn "OCUTALON"' \
  "Set sc=##class(OcuTalon.Bridge.Audit).Write(\"Action\",{\"marker\":\"$marker\"},\"zz $marker\") Write !,\"CHK|write|\",\$SYSTEM.Status.IsOK(sc)" \
  'Set r=$SYSTEM.Security.Audit("OcuTalon","Zz","Zz","x","zz unregistered") Write !,"CHK|unregistered|",r' \
  'Halt' | iris_script OCUTALON > "$tmp/actual.write"
sed -n 's/^CHK|unregistered|/INFO $SYSTEM.Security.Audit of an unregistered event returns: /p' "$tmp/actual.write"
grep -v '^CHK|unregistered|' "$tmp/actual.write" > "$tmp/actual.write.chk"
printf 'CHK|write|1\n' > "$tmp/expected.write"
compare_chk "row 11: Bridge.Audit.Write returns OK" "$tmp/actual.write.chk" "$tmp/expected.write"

audit_rows() { # the number of audit rows with the marker in EventData and the description
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventSource = ? AND EventType = ? AND Event = ? AND EventData [ ? AND Description [ ?","OcuTalon","Action","Action","'"$marker"'","'"$marker"'")' \
    'Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' \
    'Halt' | iris_script %SYS | sed -n 's/^CHK|rows|//p' | head -n 1
}
audit_row_visible() { [ "$(audit_rows)" = 1 ]; }

written_at=$SECONDS
budget=$((deadline - written_at))
[ "$budget" -le "$poll" ] || budget=$poll
if wait_until "$poll" audit_row_visible; then
  pass "row 11: one %SYS.Audit row (source OcuTalon, type Action, event Action) holds the marker and the description"
  echo "INFO the row was readable after $((SECONDS - written_at)) s"
else
  fail "row 11: no such %SYS.Audit row within $budget s (the poll is $poll s; the run's deadline leaves the rest) (rows: '$(audit_rows)')"
fi

# --- row 12: the events are structural ---

printf '%s\n' \
  'Zn "%SYS" Set p("Enabled")=0 Write !,"CHK|disabled|",##class(Security.Events).Modify("OcuTalon/Tool/Tool",,,.p)' \
  'Zn "OCUTALON" Set sc=##class(OcuTalon.Install.Step.Audit).Run() Write !,"CHK|check-fails|",$SYSTEM.Status.IsError(sc),!,"CHK|check-names|",($SYSTEM.Status.GetErrorText(sc)["OcuTalon/Tool/Tool")' \
  'Zn "%SYS" Kill ev Set ex=##class(Security.Events).Exists("OcuTalon/Tool/Tool",,,.ev) Write !,"CHK|check-changes-nothing|",ex,":",ev.Enabled' \
  'Zn "OCUTALON" Write !,"CHK|run|",##class(OcuTalon.Bridge.Installer).Run()' \
  'Halt' | iris_script OCUTALON > "$tmp/actual.row12a"
printf 'CHK|disabled|1\nCHK|check-fails|1\nCHK|check-names|1\nCHK|check-changes-nothing|1:0\nCHK|run|1\n' > "$tmp/expected.row12a"
compare_chk "row 12: with an event disabled, Step.Audit fails naming it and changes nothing, and Bridge.Installer.Run() succeeds" "$tmp/actual.row12a" "$tmp/expected.row12a"
events_state restored > "$tmp/actual.restored"
printf 'CHK|restored|%s|6\n' "$six" > "$tmp/expected.restored"
compare_chk "row 12: Bridge.Installer.Run() leaves six events, all enabled" "$tmp/actual.restored" "$tmp/expected.restored"

printf '%s\n' \
  'Zn "%SYS" Write !,"CHK|deleted|",##class(Security.Events).Delete("OcuTalon/MCP/MCP")' \
  'Zn "OCUTALON" Set sc=##class(OcuTalon.Install.Step.Audit).Run() Write !,"CHK|fails|",$SYSTEM.Status.IsError(sc),!,"CHK|names|",($SYSTEM.Status.GetErrorText(sc)["OcuTalon/MCP/MCP")' \
  'Zn "%SYS" Write !,"CHK|created|",##class(Security.Events).Exists("OcuTalon/MCP/MCP")' \
  'Halt' | iris_script OCUTALON > "$tmp/actual.row12b"
printf 'CHK|deleted|1\nCHK|fails|1\nCHK|names|1\nCHK|created|0\n' > "$tmp/expected.row12b"
compare_chk "row 12: with OcuTalon/MCP/MCP deleted, Step.Audit fails, naming it, and creates nothing" "$tmp/actual.row12b" "$tmp/expected.row12b"

if [ "$fails" -ne 0 ]; then
  echo "test-audit: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-audit: all checks passed"
