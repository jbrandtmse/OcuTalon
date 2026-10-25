#!/usr/bin/env bash
# Live test of the install at start (matrix rows 1 to 5, and Story 0.3's row 14): builds the image and starts it in one throwaway
# compose project with the after-start script active, then checks
#   - row 1, a fresh volume: healthy, the marker equal to the image's version, and a log that lists the merge,
#     the readiness step, IPM installed in %SYS and mapped into OCUTALON only, the package loaded, one STEP
#     line per installer step in the order of AD-23, and RESULT OK; readiness set, the online-demo flag off; the web
#     bundle in the durable csp/ocutalon-web/ folder, byte for byte as the image holds it, and none in csp/ocutalon/
#     (Story 0.3, row 14; Story 0.5, row 22);
#   - row 2, the same version with a mapping removed by hand: the mapping is back, the package skipped
#     (its compile time unchanged), every step run again, data and private probes intact; the same restart
#     finds IPM recorded as 0.10.9 and installs the pinned 0.10.10;
#   - row 3, the developer compose file: the package loaded again;
#   - row 4, a public class deleted: the load forced by the public-class check, the class back in OCUTALON_PUBLIC;
#   - row 5, the bridge alone: no code under src/bridge/ names another package of OcuTalon, src/bridge/ loaded into an
#     Interoperability namespace without IPM, and its installer run, and refused in a namespace without Interoperability,
#     where only the installer class is loaded because the bridge's messages need Ens.Request and Ens.Response.
# The Demo step rides on these restarts and adds none (Story 0.10): demo mode is on at the first start (the image has its version
# file), switched off before row 2's restart, still off at row 3's recreate, switched on before row 4's recreate, and switched off
# again before row 4's last restart. The checks
#   - row 1: OCUORDERS, its databases, resources, mappings, Interoperability, production and trace grants exist (check_demo_on),
#     and the surfaces of the instance are recorded;
#   - row 2: all of it is gone (check_demo_off), and the surfaces equal row 1's less every line that names OCUORDERS;
#   - row 3: a foreign OCUORDERS (databases OCUFOREIGN_DATA and OCUFOREIGN_CODE) is built before the recreate, and the start with
#     demo mode off keeps it (Story 0.12): the start ends ready, its log holds one WARN Demo line right after STEP Demo OK, and the
#     status mark demoKept holds the note, with its how field (what was kept and how to remove it by hand);
#   - row 4: recreated, with the same surfaces as row 1.
# Story 0.10's QA pass (DW-37) adds the states that only a foreign or partial start reaches, as fixtures inside rows 3 and 4 with no
# restart: each builds its own state, calls the step's Run() in OCUTALON, checks the answer and the state, and removes the state.
#   - row 3, the foreign OCUORDERS of the recreate: demo mode off keeps it, warns and records the note, exactly as the start did,
#     and demo mode on refuses it and leaves the mark as it was (row 7); once it is removed, OCUORDERS is absent and demo mode is off,
#     and then Test.Demo.Production fails every test with the reason and skips none (matrix row 15); the seed is 1 where the image's
#     version file exists and 0 without it (row 6); a database entry OCUORDERS_CODE with another directory stops the step, and the
#     next off start removes the partial state, a database file with no CPF entry included, and the mark; the surfaces equal row 2's;
#   - row 4, OCUORDERS present: a drifted package mapping is modified back; a foreign production refuses the on path, and the off
#     path keeps the namespace with a warning and the note, running or only defined and stopped, and removes only OcuTalon's access
#     (the trace application, the trace role's OCUORDERS grants and SQL privileges), with nothing stopped, started or removed (each
#     keep fixture seeds a fixture role ZzOcuGrantee with its own SQL privilege in OCUORDERS, which the keep leaves, and removes it
#     again); a Troubled Orders production is recovered and started, which clears the mark; a production whose items do not run within the
#     wait is an error that names the item; demo mode switched off while the Orders production runs stops it and removes
#     OCUORDERS, and switched on again recreates it. The last restart has demo mode off and the foreign production defined and
#     stopped: it ends ready, with the WARN line, the note, OCUORDERS and the definition kept, and OcuTalon's access gone.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its
# volume and images. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-scan.sh"
live_start t02s

version=$(manifest_version src/module.xml)
ipm_version=0.10.10

# The compile time of a class, as the class dictionary records it.
compile_time() {
  printf '%s\n' 'Write !,"CHK|compiled|",##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Install.Registry").TimeChanged' 'Halt' \
    | session_value OCUTALON compiled
}

# The state that a ready start leaves, whatever the start was: the marker, Docker's verdict, the installed versions.
check_ready_state() { # check_ready_state <label>
  local label=$1
  if [ "$(marker)" = "$version" ]; then
    pass "$label: the marker equals the image's version $version"
  else
    fail "$label: the marker is '$(marker)', wanted $version"
  fi
  if [ "$(health_status)" = healthy ] && [ "$(restart_count)" = 0 ]; then
    pass "$label: Docker reports healthy, with no restart"
  else
    fail "$label: Docker reports '$(health_status)' after $(restart_count) restart(s), wanted healthy and 0"
  fi
  check_session "$label: installed package, readiness and flag" OCUTALON \
    "CHK|package|$version
CHK|ready|1
CHK|onlineDemo|0
CHK|settings-dest|^$mgr/ocutalon_public/
CHK|ns|OCUTALON" \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|package|",$Select($IsObject(m):m.VersionString,1:"")' \
    'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
    'Write !,"CHK|onlineDemo|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
    'Write !,"CHK|settings-dest|",##class(%SYS.Namespace).GetRoutineDest("OCUTALON","OcuTalon.Data.Public.Settings.1","INT")' \
    'Write !,"CHK|ns|",$Namespace' \
    'Halt'
}

# --- row 1: a fresh volume ---

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
  die "row 1 the first start did not end ready within 400 s"
fi
pass "row 1 the first start ended ready"

expected_run "nothing to clear" "installed $ipm_version (was none)" "mapped into OCUTALON" "skipped (package not installed)" \
  "loaded (not installed)" "$version" > "$tmp/expected.row1"
check_log "row 1" "$tmp/expected.row1"
check_ready_state "row 1"
if dc logs iris 2>&1 | tr -d '\r' | grep -q 'STEP Ready OK'; then
  pass "row 1: the per-step summary reaches the container's output"
else
  fail "row 1: the container's output holds no STEP summary line"
fi

# --- row 14 and Story 0.5's row 22: the web bundle is installed byte for byte, in csp/ocutalon-web/ ---

image_tree=$(container_tree_hashes /opt/ocutalon/src/ocutalon/csp)
durable_tree=$(container_tree_hashes /durable/iris/csp/ocutalon-web)
if [ -n "$image_tree" ] && [ "$image_tree" = "$durable_tree" ]; then
  pass "row 14: /durable/iris/csp/ocutalon-web/ holds the image's bundle, byte for byte ($(printf '%s\n' "$image_tree" | wc -l | tr -d ' ') files)"
else
  fail "row 14: /durable/iris/csp/ocutalon-web/ differs from /opt/ocutalon/src/ocutalon/csp/"
fi
if [ -n "$(container_sha256 /durable/iris/csp/ocutalon-web/index.html)" ] \
  && [ "$(container_sha256 /durable/iris/csp/ocutalon-web/index.html)" = "$(container_sha256 /opt/ocutalon/src/ocutalon/csp/index.html)" ]; then
  pass "row 14: index.html is byte-identical to the image's"
else
  fail "row 14: index.html differs from the image's, or is missing"
fi
if [ -z "$(container_sha256 /durable/iris/csp/ocutalon/index.html)" ]; then
  pass "row 22: /durable/iris/csp/ocutalon/index.html is absent"
else
  fail "row 22: /durable/iris/csp/ocutalon/index.html exists"
fi

# IPM is installed in %SYS, and mapped into OCUTALON only: no other user namespace maps %IPM.
check_session "row 1: IPM in %SYS, mapped into OCUTALON and not into USER" %SYS \
  "CHK|ipm-version|$ipm_version
CHK|ipm-mapped-ocutalon|1
CHK|ipm-mapped-user|0" \
  'Set m=##class(%IPM.Storage.Module).NameOpen("zpm") Write !,"CHK|ipm-version|",$Select($IsObject(m):m.VersionString,1:"")' \
  'Write !,"CHK|ipm-mapped-ocutalon|",##class(Config.MapPackages).Exists("OCUTALON","%IPM")' \
  'Write !,"CHK|ipm-mapped-user|",##class(Config.MapPackages).Exists("USER","%IPM")' \
  'Halt'

check_demo_on "row 1"
demo_surfaces "$tmp/surfaces.row1"

# --- row 2: the same version, with a mapping removed by hand ---

set_probes
check_probes "before the restart"
compiled_before=$(compile_time)
check_session "row 2: the IRIS.IF.* mapping is removed" %SYS "CHK|deleted|1" \
  'Write !,"CHK|deleted|",##class(Config.MapGlobals).Delete("OCUTALON","IRIS.IF.*")' 'Halt'
# The same restart also finds an older IPM recorded, which the session upgrades to the pinned release.
check_session "row 2: IPM is recorded as 0.10.9" %SYS "CHK|ipm-recorded|1" \
  'Set m=##class(%IPM.Storage.Module).NameOpen("zpm"),m.VersionString="0.10.9" Write !,"CHK|ipm-recorded|",m.%Save()' 'Halt'
# The same restart also finds demo mode switched off.
set_demo_mode 0

dc stop iris >/dev/null 2>&1
dc start iris >/dev/null 2>&1
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 2 the restart did not end ready within 200 s"
fi
expected_run "cleared" "installed $ipm_version (was 0.10.9)" "already mapped" "ok" "skipped $version" "$version" > "$tmp/expected.row2"
check_log "row 2" "$tmp/expected.row2"
check_ready_state "row 2"
check_session "row 2: the merge brought the IRIS.IF.* mapping back" OCUTALON "CHK|dest|^$mgr/ocutalon_private/" \
  'Write !,"CHK|dest|",##class(%SYS.Namespace).GetGlobalDest("OCUTALON","^IRIS.IF.Zz")' 'Halt'
check_probes "row 2"
if [ "$(compile_time)" = "$compiled_before" ] && [ -n "$compiled_before" ]; then
  pass "row 2: the package was not compiled again (compile time $compiled_before)"
else
  fail "row 2: the compile time of OcuTalon.Install.Registry changed from '$compiled_before' to '$(compile_time)'"
fi
check_demo_off "row 2"
demo_surfaces "$tmp/surfaces.row2"
compare_surfaces "row 2: nothing else changes" "$tmp/surfaces.row1" "$tmp/surfaces.row2" --drop-orders

# --- Story 0.12 (DW-42): a foreign OCUORDERS kept at row 3's recreate ---
#
# The helpers of the foreign and kept states. demo_run is the ObjectScript that calls the step and returns to the session's own
# namespace; fixture names are the Zz and OCUFOREIGN ones, which no product object carries. The three sentences are 0.10's
# fixed refusals, which the off path now uses as its warning and as the text of the note.

foreign_sentence='Namespace OCUORDERS exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone.'
running_sentence='The production ZzOcuForeign.Production is in namespace OCUORDERS and is not stopped, so the Demo step leaves it alone.'
defined_sentence='The production ZzOcuForeign.Production is in namespace OCUORDERS, so the Demo step leaves it alone.'

# The how field of the note, the owner's sentence: what was kept, from the facts that the kept sentence names, and how to remove it
# by hand. Each is written out in full, so that a check cannot follow a change of the step's wording.
foreign_how='OcuTalon left the OCUORDERS namespace in place because it holds databases that OcuTalon did not create. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal.'
running_how='OcuTalon left the OCUORDERS namespace in place because it holds the production ZzOcuForeign.Production, which is not stopped. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal.'
defined_how='OcuTalon left the OCUORDERS namespace in place because it holds the production ZzOcuForeign.Production. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal.'

demo_run='Set home=$Namespace,$Namespace="OCUTALON" Set sc=##class(OcuTalon.Install.Step.Demo).Run() Set $Namespace=home'

# fixture_class <name> < class text: puts a fixture class into the container's /tmp, where a session loads it.
fixture_class() {
  dc exec -T iris sh -c "cat > /tmp/$1.cls" || die "the fixture class $1 could not be copied into the container"
}

# foreign_state <label>: the ObjectScript lines (for %SYS) that print CHK|<label>|<globals>/<routines>|<six flags>|<package
# mappings>|<Interoperability marker>|<trace role names OCUORDERS>|<web applications>, the state of the namespace OCUORDERS and of
# everything the step would create for it: the flags are the CPF entries OCUORDERS_CODE and OCUORDERS_DATA, their resources and
# their directories.
foreign_state() {
  printf '%s\n' \
    'Set mgr=$SYSTEM.Util.ManagerDirectory() Kill p Set sc=##class(Config.Namespaces).Get("OCUORDERS",.p) Set fp=$Get(p("Globals"))_"/"_$Get(p("Routines"))_"|"_##class(Config.Databases).Exists("OCUORDERS_CODE")_##class(Config.Databases).Exists("OCUORDERS_DATA")_##class(Security.Resources).Exists("%DB_OCUORDERS_CODE")_##class(Security.Resources).Exists("%DB_OCUORDERS_DATA")_##class(%File).DirectoryExists(mgr_"ocuorders_code")_##class(%File).DirectoryExists(mgr_"ocuorders_data")' \
    'Set rs=##class(%ResultSet).%New("Config.MapPackages:List") Do rs.Execute("OCUORDERS") Set maps=0 While rs.Next() { Set maps=maps+1 } Set ok=##class(Security.Roles).Get("OcuTalonTraceViewer",.q)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE NameSpace = ?","OCUORDERS") Do rs.%Next()' \
    "Write !,\"CHK|$1|\",fp,\"|\",maps,\"|\",\$Data(^%SYS(\"Ensemble\",\"InstalledNamespace\",\"OCUORDERS\")),\"|\",(\$Get(q(\"Resources\"))[\"OCUORDERS\"),\"|\",rs.%GetData(1)"
}

# kept_note: the ObjectScript lines (for OCUTALON) that print CHK|note|<text>|<namespace>|<globals>|<routines>|<how> from the status
# mark demoKept, or CHK|note|<absent> when the mark has no row.
kept_note() {
  printf '%s\n' \
    'Set note=##class(OcuTalon.Data.StatusMark).Get("demoKept")' \
    'If note="" { Write !,"CHK|note|<absent>" } Else { Set o=##class(%DynamicAbstractObject).%FromJSON(note) Write !,"CHK|note|",o.text,"|",o.namespace,"|",o.globals,"|",o.routines,"|",o.how }'
}

# own_access <label>: the ObjectScript lines (for OCUTALON) that print CHK|<label>|<trace application /ocutalon/trace/ocuorders exists>|
# <the trace role names OCUORDERS>|<the trace role's SQL privilege rows in OCUORDERS>|<the trace role may SELECT Ens.MessageHeader
# in OCUORDERS>, OcuTalon's own access to the namespace (AD-24); the last field is the privilege as SQL checks it, not the row.
own_access() {
  printf '%s\n' \
    'Set $Namespace="%SYS" Set ok=##class(Security.Roles).Get("OcuTalonTraceViewer",.q) Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.SQLPrivileges WHERE Namespace = ? AND Grantee = ?","OCUORDERS","OcuTalonTraceViewer") Do rs.%Next()' \
    "Write !,\"CHK|$1|\",##class(Security.Applications).Exists(\"/ocutalon/trace/ocuorders\"),\"|\",(\$Get(q(\"Resources\"))[\"OCUORDERS\"),\"|\",rs.%GetData(1),\"|\",\$SYSTEM.SQL.Security.CheckPrivilege(\"OcuTalonTraceViewer\",1,\"Ens.MessageHeader\",\"s\",\"OCUORDERS\") Set \$Namespace=\"OCUTALON\""
}

# inside_state <variable>: the ObjectScript lines (for OCUTALON) that set the variable to a fingerprint of what the keep mode must
# leave in OCUORDERS: its globals and routines databases with their resources and files, its package and global mappings with
# their databases, its Interoperability marker and role, its web applications but OcuTalon's trace application, and its portal
# folder.
inside_state() {
  printf '%s\n' \
    'Set $Namespace="%SYS" Set mgr=$SYSTEM.Util.ManagerDirectory() Kill p Set sc=##class(Config.Namespaces).Get("OCUORDERS",.p) Set st=$Get(p("Globals"))_"/"_$Get(p("Routines"))_"|"_##class(Config.Databases).Exists("OCUORDERS_CODE")_##class(Config.Databases).Exists("OCUORDERS_DATA")_##class(Security.Resources).Exists("%DB_OCUORDERS_CODE")_##class(Security.Resources).Exists("%DB_OCUORDERS_DATA")_##class(%File).Exists(mgr_"ocuorders_code/IRIS.DAT")_##class(%File).Exists(mgr_"ocuorders_data/IRIS.DAT")' \
    'Set maps="" For q="Config.MapPackages:List","Config.MapGlobals:List" { Set rs=##class(%ResultSet).%New(q) Do rs.Execute("OCUORDERS") While rs.Next() { Set maps=maps_","_rs.Get("Name")_">"_rs.Get("Database") } }' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM Security.Applications WHERE NameSpace = ? AND Name <> ? ORDER BY Name","OCUORDERS","/ocutalon/trace/ocuorders") Set apps="" While rs.%Next() { Set apps=apps_","_rs.%GetData(1) }' \
    "Set $1=st_\"|\"_maps_\"|\"_\$Data(^%SYS(\"Ensemble\",\"InstalledNamespace\",\"OCUORDERS\"))_\"|\"_##class(Security.Roles).Exists(\"%EnsRole_ProdPrivs_OCUORDERS\")_\"|\"_apps_\"|\"_##class(%File).DirectoryExists(\$SYSTEM.Util.DataDirectory()_\"csp/ocuorders\") Set \$Namespace=\"OCUTALON\""
}

# foreign_grant <seed|count|remove>: the ObjectScript lines (for OCUTALON) for a fixture role ZzOcuGrantee that holds SQL SELECT on
# Ens.MessageHeader in OCUORDERS, a privilege that is not OcuTalon's own and that the keep mode must leave. seed creates the role and
# the grant and prints CHK|grantee-seed|<role created>|<grant status OK>; count prints CHK|grantee|<its privileges in OCUORDERS>; remove
# revokes the grant, deletes the role and prints CHK|grantee-removed|<revoked>|<role deleted>|<privileges left>.
foreign_grant() {
  case $1 in
    seed) printf '%s\n' \
      'Set $Namespace="%SYS" Set rc=##class(Security.Roles).Create("ZzOcuGrantee","OcuTalon test fixture","") Set $Namespace="OCUORDERS" Set gc=$SYSTEM.SQL.Security.GrantPrivilege("SELECT","Ens.MessageHeader","TABLE","ZzOcuGrantee") Write !,"CHK|grantee-seed|",$SYSTEM.Status.IsOK(rc),"|",$SYSTEM.Status.IsOK(gc) Set $Namespace="OCUTALON"' ;;
    count) printf '%s\n' \
      'Set $Namespace="%SYS" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.SQLPrivileges WHERE Namespace = ? AND Grantee = ?","OCUORDERS","ZzOcuGrantee") Do rs.%Next() Write !,"CHK|grantee|",rs.%GetData(1) Set $Namespace="OCUTALON"' ;;
    remove) printf '%s\n' \
      'Set $Namespace="OCUORDERS" Set vc=$SYSTEM.SQL.Security.RevokePrivilege("SELECT","Ens.MessageHeader","TABLE","ZzOcuGrantee") Set $Namespace="%SYS" Set dc=##class(Security.Roles).Delete("ZzOcuGrantee") Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.SQLPrivileges WHERE Grantee = ?","ZzOcuGrantee") Do rs.%Next() Write !,"CHK|grantee-removed|",$SYSTEM.Status.IsOK(vc),"|",$SYSTEM.Status.IsOK(dc),"|",rs.%GetData(1) Set $Namespace="OCUTALON"' ;;
  esac
}

# check_kept_log <label> <sentence>: in the start's log, the line right after STEP Demo OK is exactly WARN Demo <sentence>, and it is
# the only WARN Demo line.
check_kept_log() {
  local label=$1 sentence=$2 next count
  next=$(start_log | grep -A 1 -E '^STEP Demo OK [0-9.]+s$' | sed -n 2p)
  count=$(start_log | grep -c '^WARN Demo ')
  if [ "$next" = "WARN Demo $sentence" ] && [ "$count" = 1 ]; then
    pass "$label: the line after STEP Demo OK is WARN Demo with the kept sentence, and it is the only one"
  else
    fail "$label: the line after STEP Demo OK is '$next' ($count WARN Demo line(s)), wanted 'WARN Demo $sentence' once"
  fi
}

# A foreign OCUORDERS, one whose databases the step did not create, built while demo mode is off (it was set before row 2's
# restart), so that row 3's recreate starts with it.
check_session "a foreign OCUORDERS is built, and the step does not own it (matrix row 7)" %SYS "CHK|built|1
CHK|owned|0
CHK|before|OCUFOREIGN_DATA/OCUFOREIGN_CODE|000000|0|0|0|0" \
  'Set mgr=$SYSTEM.Util.ManagerDirectory()' \
  'For n="CODE","DATA" { Set dir=mgr_"ocuforeign_"_$ZConvert(n,"L")_"/" Set ok=##class(%File).CreateDirectoryChain(dir) Set sc=##class(SYS.Database).CreateDatabase(dir) Kill p Set p("Directory")=dir Set sc2=##class(Config.Databases).Create("OCUFOREIGN_"_n,.p) Set built(n)=(ok&&$SYSTEM.Status.IsOK(sc)&&$SYSTEM.Status.IsOK(sc2)) }' \
  'Kill p Set p("Globals")="OCUFOREIGN_DATA",p("Routines")="OCUFOREIGN_CODE" Set sc=##class(Config.Namespaces).Create("OCUORDERS",.p) Write !,"CHK|built|",(built("CODE")&&built("DATA")&&$SYSTEM.Status.IsOK(sc))' \
  'Set $Namespace="OCUTALON" Write !,"CHK|owned|",##class(OcuTalon.Install.Step.Demo).Owned() Set $Namespace="%SYS"' \
  "$(foreign_state before)" \
  'Halt'

# --- row 3: the developer compose file reloads the package ---

compiled_before=$(compile_time)
live_add_file "$root/docker-compose.dev.yml"
if ! dc up -d >/dev/null 2>&1; then
  die "row 3 recreate with docker-compose.dev.yml failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 3 the dev start did not end ready within 200 s"
fi
expected_run "cleared" "present $ipm_version" "already mapped" "ok" "loaded (dev)" "$version" > "$tmp/expected.row3"
check_log "row 3" "$tmp/expected.row3"
check_ready_state "row 3"
after=$(compile_time)
if [ -n "$compiled_before" ] && [ -n "$after" ] && [ "$after" != "$compiled_before" ]; then
  pass "row 3: the package was compiled again (compile time $compiled_before to $after)"
else
  fail "row 3: the compile time of OcuTalon.Install.Registry is '$after' after the dev start, it was '$compiled_before'"
fi
check_kept_log "row 3" "$foreign_sentence"
check_session "row 3: the start recorded the note of the kept OCUORDERS, and the foreign namespace is as it was (matrix row 11)" OCUTALON \
  "CHK|note|$foreign_sentence|OCUORDERS|OCUFOREIGN_DATA|OCUFOREIGN_CODE|$foreign_how
CHK|kept|OCUFOREIGN_DATA/OCUFOREIGN_CODE|000000|0|0|0|0" \
  "$(kept_note)" \
  'Set $Namespace="%SYS"' \
  "$(foreign_state kept)" \
  'Halt'
live_pop_file

# --- Story 0.10, QA (DW-37; matrix rows 3, 6, 7 and 15): the states the Demo step meets only from a foreign or partial start ---
#
# The foreign OCUORDERS of row 3's recreate is still here, with demo mode off. Each fixture starts from the state before it, builds
# its own foreign or partial state, calls the step's Run() the way the after-start does (in OCUTALON), checks the answer and what
# the step did and did not touch, and removes its state again. No fixture restarts the container. The surfaces at the end of the
# block equal row 2's. The helpers (demo_run, fixture_class, foreign_state, kept_note, own_access, inside_state, foreign_grant and
# check_kept_log) are defined above.

# production_class_fails <label> <reason>: runs OcuTalon.Test.Demo.Production through %UnitTest.Manager in the container, the way
# ci/iris.sh class does, and checks that every test failed, none was skipped, and each failed with <reason>.
production_class_fails() {
  check_session "$1" OCUTALON \
    "CHK|ran|1
CHK|all-failed|1
CHK|none-skipped|1
CHK|each-names-reason|1" \
    'Set old=$Get(^UnitTestRoot),^UnitTestRoot="/tmp/",before=$Order(^UnitTest.Result(""),-1)' \
    'Do ##class(%UnitTest.Manager).RunTest(":OcuTalon.Test.Demo.Production","/noload/nodelete/norecursive")' \
    'Set id=$Order(^UnitTest.Result(""),-1),(n,bad,skip,why)=0 Write !,"CHK|ran|",(id>before)' \
    'Set inst=##class(%UnitTest.Result.TestInstance).%OpenId(id) Set k1="" For { Set su=inst.TestSuites.GetNext(.k1) Quit:k1=""  Set k2="" For { Set tc=su.TestCases.GetNext(.k2) Quit:k2=""  Set k3="" For { Set tm=tc.TestMethods.GetNext(.k3) Quit:k3=""  Set n=n+1 Set:tm.Status=0 bad=bad+1 Set k4="" For { Set ta=tm.TestAsserts.GetNext(.k4) Quit:k4=""  Set:ta.Status=2 skip=skip+1 Set:(ta.Status=0)&&(ta.Description="'"$2"'") why=why+1 } } } }' \
    'Write !,"CHK|all-failed|",((n>0)&&(bad=n)),!,"CHK|none-skipped|",(skip=0),!,"CHK|each-names-reason|",((n>0)&&(why=n))' \
    'Do ##class(%UnitTest.Result.TestInstance).%DeleteId(id) If old="" { Kill ^UnitTestRoot } Else { Set ^UnitTestRoot=old }' \
    'Halt'
}

# Matrix row 7: the foreign OCUORDERS that row 3's recreate started with (built above) is kept when demo mode is off, with a warning
# and the note, and refused (and left alone, the mark as it was) when it is on.
set_demo_mode 0
check_session "demo mode off keeps a foreign OCUORDERS exactly as it was, warns, and records the note (matrix rows 7 and 11)" OCUTALON \
  "CHK|cleared|1|
CHK|run|1|
CHK|warn|1|$foreign_sentence
CHK|note|$foreign_sentence|OCUORDERS|OCUFOREIGN_DATA|OCUFOREIGN_CODE|$foreign_how
CHK|off|OCUFOREIGN_DATA/OCUFOREIGN_CODE|000000|0|0|0|0" \
  'Set cleared=##class(OcuTalon.Data.StatusMark).Record("demoKept","") Write !,"CHK|cleared|",$SYSTEM.Status.IsOK(cleared),"|",##class(OcuTalon.Data.StatusMark).Get("demoKept")' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set w=##class(OcuTalon.Install.Step).TakeWarnings() Write !,"CHK|warn|",$ListLength(w),"|",$ListGet(w,1)' \
  "$(kept_note)" \
  'Set $Namespace="%SYS"' \
  "$(foreign_state off)" \
  'Halt'
set_demo_mode 1
check_session "demo mode on refuses a foreign OCUORDERS with the stated text, touches nothing and leaves the mark as it was (matrix row 7); the fixture is removed again" %SYS \
  "CHK|seeded|1
CHK|run|0|ERROR #5001: Namespace OCUORDERS exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone.
CHK|on|OCUFOREIGN_DATA/OCUFOREIGN_CODE|000000|0|0|0|0
CHK|mark-left|stale
CHK|removed|1|1|1|1|1|1|1
CHK|gone|/|000000|0|0|0|0" \
  'Set $Namespace="OCUTALON" Write !,"CHK|seeded|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record("demoKept","stale")) Set $Namespace="%SYS"' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  "$(foreign_state on)" \
  'Set $Namespace="OCUTALON" Write !,"CHK|mark-left|",##class(OcuTalon.Data.StatusMark).Get("demoKept") Set x=##class(OcuTalon.Data.StatusMark).Record("demoKept","") Set $Namespace="%SYS"' \
  'Set mgr=$SYSTEM.Util.ManagerDirectory(),gone=##class(Config.Namespaces).Delete("OCUORDERS")' \
  'For n="CODE","DATA" { Set dir=mgr_"ocuforeign_"_$ZConvert(n,"L")_"/" Set gone=gone_"|"_##class(Config.Databases).Delete("OCUFOREIGN_"_n) Set gone=gone_"|"_##class(SYS.Database).DeleteDatabase(dir) Set gone=gone_"|"_##class(%File).RemoveDirectoryTree(dir) }' \
  'Write !,"CHK|removed|",gone' \
  "$(foreign_state gone)" \
  'Halt'

# The foreign OCUORDERS is gone and demo mode is off again: the state of row 2, which the rest of the block needs.
set_demo_mode 0
check_demo_off "row 3"

# Matrix row 15: with OCUORDERS missing, the end-to-end tests fail, with the reason, and are never skipped.
production_class_fails "with no OCUORDERS every test of Test.Demo.Production fails with the reason, and none is skipped (matrix row 15)" \
  "OCUORDERS does not exist: this class runs in throwaways and CI only (Rule 21)"

# Matrix row 6, on Docker and on IPM: the image has its version file, so the seed is 1; a step whose version file is absent (the IPM case,
# made by a subclass that names a file that does not exist) seeds 0 into a missing row and creates nothing.
fixture_class ZzOcuNoVersion <<'EOC'
Class ZzOcuNoVersion.Demo Extends OcuTalon.Install.Step.Demo
{

Parameter VERSIONFILE = "/tmp/zz-ocu-no-version-file";

}
EOC
check_session "demo.mode: the seed is 1 on Docker (the image's version file), and 0 with no version file (IPM), which creates nothing (matrix row 6)" OCUTALON \
  "CHK|docker-seed|1|1
CHK|fixture|1
CHK|ipm-seed|0
CHK|row-deleted|1
CHK|ipm-run|1
CHK|ipm-row|0
CHK|ipm-nothing|0|0|0
CHK|fixture-removed|1" \
  'Write !,"CHK|docker-seed|",##class(OcuTalon.Install.Step.Demo).DefaultMode(),"|",##class(%File).Exists(##class(OcuTalon.Install.Step.Demo).#VERSIONFILE)' \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOcuNoVersion.cls","ck-d")' \
  'Write !,"CHK|ipm-seed|",##class(ZzOcuNoVersion.Demo).DefaultMode()' \
  'Set row=##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode") Write !,"CHK|row-deleted|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.Setting).%DeleteId(row.%Id()))' \
  'Set sc=##class(ZzOcuNoVersion.Demo).Run() Write !,"CHK|ipm-run|",$SYSTEM.Status.IsOK(sc)' \
  'Set row=##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode") Write !,"CHK|ipm-row|",$Select($IsObject(row):row.Value,1:"<absent>")' \
  'Set $Namespace="%SYS" Write !,"CHK|ipm-nothing|",##class(Config.Namespaces).Exists("OCUORDERS"),"|",##class(Security.Resources).Exists("%DB_OCUORDERS_CODE"),"|",##class(%File).DirectoryExists($SYSTEM.Util.ManagerDirectory()_"ocuorders_code") Set $Namespace="OCUTALON"' \
  'Write !,"CHK|fixture-removed|",$SYSTEM.OBJ.Delete("ZzOcuNoVersion.Demo","-d")' \
  'Halt'

# Matrix rows 1 and 3, a partial start: the database entry OCUORDERS_CODE names another directory, so the step stops after it has made
# its resources and its code database file, and says which entry is wrong; a later start with demo mode off removes that partial
# state, a database file that has no entry in the CPF included, and leaves the entry that is not the step's own.
set_demo_mode 1
check_session "a database entry OCUORDERS_CODE with another directory stops the step with the stated text, and the entry is kept (matrix row 1)" %SYS \
  "CHK|entry|1
CHK|run|0|ERROR #5001: The database OCUORDERS_CODE exists with the directory $mgr/ocuforeign_code/, not $mgr/ocuorders_code/, so the Demo step cannot use it.
CHK|entry-kept|$mgr/ocuforeign_code/
CHK|partial|0|1|0
CHK|seeded|1
CHK|mark-left|stale" \
  'Set mgr=$SYSTEM.Util.ManagerDirectory() Kill p Set p("Directory")=mgr_"ocuforeign_code/" Write !,"CHK|entry|",$SYSTEM.Status.IsOK(##class(Config.Databases).Create("OCUORDERS_CODE",.p))' \
  'Set $Namespace="OCUTALON" Write !,"CHK|seeded|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record("demoKept","stale")) Set $Namespace="%SYS"' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set $Namespace="OCUTALON" Write !,"CHK|mark-left|",##class(OcuTalon.Data.StatusMark).Get("demoKept") Set $Namespace="%SYS"' \
  'Kill p Set sc=##class(Config.Databases).Get("OCUORDERS_CODE",.p) Write !,"CHK|entry-kept|",$Get(p("Directory"))' \
  'Write !,"CHK|partial|",##class(Config.Namespaces).Exists("OCUORDERS"),"|",##class(%File).Exists(mgr_"ocuorders_code/IRIS.DAT"),"|",##class(%File).DirectoryExists(mgr_"ocuorders_data")' \
  'Halt'
set_demo_mode 0
check_session "demo mode off removes the partial state, a code database file with no CPF entry included, and keeps the entry that is not its own (matrix row 3)" %SYS \
  "CHK|run|1
CHK|cleaned|0|0|0|0|1
CHK|entry-removed|1
CHK|note|<absent>" \
  'Set mgr=$SYSTEM.Util.ManagerDirectory()' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)' \
  'Set $Namespace="OCUTALON"' \
  "$(kept_note)" \
  'Set $Namespace="%SYS"' \
  'Write !,"CHK|cleaned|",##class(%File).Exists(mgr_"ocuorders_code/IRIS.DAT"),"|",##class(%File).DirectoryExists(mgr_"ocuorders_code"),"|",##class(Security.Resources).Exists("%DB_OCUORDERS_CODE"),"|",##class(Security.Resources).Exists("%DB_OCUORDERS_DATA"),"|",##class(Config.Databases).Exists("OCUORDERS_CODE")' \
  'Write !,"CHK|entry-removed|",##class(Config.Databases).Delete("OCUORDERS_CODE")' \
  'Halt'
check_demo_off "row 3 after the foreign and partial states"
demo_surfaces "$tmp/surfaces.row3"
compare_surfaces "row 3: the foreign and partial states leave nothing behind" "$tmp/surfaces.row2" "$tmp/surfaces.row3"

# --- row 4: a public class deleted ---

set_demo_mode 1
if ! dc up -d >/dev/null 2>&1; then
  die "row 4 recreate without the dev file failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  die "row 4 the start without the dev file did not end ready within 200 s"
fi
check_demo_on "row 4"
demo_surfaces "$tmp/surfaces.row4"
compare_surfaces "row 4: recreated as at the first start" "$tmp/surfaces.row1" "$tmp/surfaces.row4"

# --- Story 0.10, QA (DW-37; matrix rows 1, 2, 3, 7 and 15): the branches of the step that a start with the namespace and the production
# --- already in place reaches only from a foreign or broken state ---
#
# OCUORDERS and its production are fresh here. Each fixture breaks one thing, calls Run() (demo_run, above), checks the answer and
# the state, and puts the state back, so the production runs again at the end (check_orders_jobs) and row 4's restart follows
# as before. The foreign production and the subclasses are loaded from /tmp and deleted again.

fixture_class ZzOcuForeign <<'EOC'
Class ZzOcuForeign.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="ZzOcuForeign.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
</Production>
}

}
EOC
fixture_class ZzOcuFast <<'EOC'
Class ZzOcuFast.Demo Extends OcuTalon.Install.Step.Demo
{

Parameter WAITSECONDS = 3;

}
EOC

# A mapping of the namespace that drifted to another database is put back, and the running production is left alone.
check_session "a package mapping of OCUORDERS that names another database is modified back (matrix row 2)" %SYS \
  "CHK|broken|1|^$mgr/ocutalon_code/
CHK|run|1
CHK|healed|^$mgr/ocutalon_public/" \
  'Kill p Set p("Database")="OCUTALON_CODE" Set sc=##class(Config.MapPackages).Modify("OCUORDERS","OcuTalon.Data.Public",.p) Write !,"CHK|broken|",$SYSTEM.Status.IsOK(sc),"|",##class(%SYS.Namespace).GetRoutineDest("OCUORDERS","OcuTalon.Data.Public.Settings.1","INT")' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)' \
  'Write !,"CHK|healed|",##class(%SYS.Namespace).GetRoutineDest("OCUORDERS","OcuTalon.Data.Public.Settings.1","INT")' \
  'Halt'

# Another production runs in OCUORDERS: the step refuses it with demo mode on, and with demo mode off keeps the namespace, warns and
# records the note and removes only OcuTalon's access; it stops nothing, starts nothing, and deletes nothing in the namespace. (The
# Orders production is stopped first, once Ens.ScheduleHandler has taken its start.)
check_session "a foreign production runs in OCUORDERS and the Orders production is stopped (fixture)" OCUORDERS \
  "CHK|settled|1
CHK|stopped|1
CHK|fixture|1
CHK|foreign-started|1
CHK|foreign-state|ZzOcuForeign.Production|1" \
  "$settle_scheduler"' Write !,"CHK|settled|",settled' \
  'Set sc=##class(Ens.Director).StopProduction(30,1) Write !,"CHK|stopped|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|stop-error|",$SYSTEM.Status.GetErrorText(sc)' \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOcuForeign.cls","ck-d")' \
  'Set sc=##class(Ens.Director).StartProduction("ZzOcuForeign.Production") Write !,"CHK|foreign-started|",$SYSTEM.Status.IsOK(sc)' \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|foreign-state|",n,"|",s' \
  'Halt'
sed -n 's/^CHK|stop-error|/  the Orders production did not stop: /p' "$tmp/actual.chk"
check_session "demo mode on refuses OCUORDERS while another production runs there, and starts nothing (matrix rows 1 and 7)" OCUTALON \
  "CHK|run|0|ERROR #5001: The production ZzOcuForeign.Production is in namespace OCUORDERS and is not stopped, so the Demo step leaves it alone.
CHK|state|ZzOcuForeign.Production|1" \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set $Namespace="OCUORDERS" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|state|",n,"|",s' \
  'Halt'
production_class_fails "with another production running in OCUORDERS every test of Test.Demo.Production fails with the reason, and none is skipped (matrix row 15)" \
  "The Orders production does not run in OCUORDERS"
set_demo_mode 0
check_session "demo mode off keeps OCUORDERS while another production runs there: it warns, records the note, removes OcuTalon's own access only, and stops and deletes nothing (matrix rows 3, 7 and 13)" OCUTALON \
  "CHK|own-before|1|1|1|1
CHK|grantee-seed|1|1
CHK|run|1|
CHK|warn|1|$running_sentence
CHK|note|$running_sentence|OCUORDERS|OCUORDERS_DATA|OCUORDERS_CODE|$running_how
CHK|own|0|0|0|0
CHK|inside|1|1
CHK|grantee|1
CHK|kept|1|1|1|ZzOcuForeign.Production|1
CHK|grantee-removed|1|1|0" \
  "$(own_access own-before)" \
  "$(foreign_grant seed)" \
  "$(inside_state inBefore)" \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set w=##class(OcuTalon.Install.Step).TakeWarnings() Write !,"CHK|warn|",$ListLength(w),"|",$ListGet(w,1)' \
  "$(kept_note)" \
  "$(own_access own)" \
  "$(inside_state inAfter)" \
  'Write !,"CHK|inside|",(inBefore=inAfter),"|",(inAfter["/csp/ocuorders")' \
  "$(foreign_grant count)" \
  'Set $Namespace="%SYS" Set kept=##class(Config.Namespaces).Exists("OCUORDERS")_"|"_##class(Config.Databases).Exists("OCUORDERS_CODE")_"|"_##class(Config.Databases).Exists("OCUORDERS_DATA") Set $Namespace="OCUORDERS" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|kept|",kept,"|",n,"|",s Set $Namespace="OCUTALON"' \
  "$(foreign_grant remove)" \
  'Halt'

# The foreign production stopped: it is still defined in OCUORDERS, so demo mode off still keeps the namespace, with the other
# sentence. OcuTalon's own access was removed by the keep above, and stays removed; the fixture role is seeded again for this run.
check_session "demo mode off keeps OCUORDERS while another production is defined there, stopped: it warns, records the note, leaves OcuTalon's access removed and another grantee's privilege in place, and deletes nothing (matrix rows 3, 7 and 12)" OCUTALON \
  "CHK|settled|1
CHK|foreign-stopped|1|2
CHK|grantee-seed|1|1
CHK|run|1|
CHK|warn|1|$defined_sentence
CHK|note|$defined_sentence|OCUORDERS|OCUORDERS_DATA|OCUORDERS_CODE|$defined_how
CHK|own|0|0|0|0
CHK|inside|1|1
CHK|grantee|1
CHK|kept|1|1|1|1|1
CHK|grantee-removed|1|1|0" \
  'Set $Namespace="OCUORDERS" '"$settle_scheduler"' Write !,"CHK|settled|",settled' \
  'Set sc=##class(Ens.Director).StopProduction(30,1) Set sc2=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|foreign-stopped|",$SYSTEM.Status.IsOK(sc),"|",s Write:$SYSTEM.Status.IsError(sc) !,"CHK|stop-error|",$SYSTEM.Status.GetErrorText(sc) Set $Namespace="OCUTALON"' \
  "$(foreign_grant seed)" \
  "$(inside_state inBefore)" \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set w=##class(OcuTalon.Install.Step).TakeWarnings() Write !,"CHK|warn|",$ListLength(w),"|",$ListGet(w,1)' \
  "$(kept_note)" \
  "$(own_access own)" \
  "$(inside_state inAfter)" \
  'Write !,"CHK|inside|",(inBefore=inAfter),"|",(inAfter["/csp/ocuorders")' \
  "$(foreign_grant count)" \
  'Set $Namespace="%SYS" Set kept=##class(Config.Namespaces).Exists("OCUORDERS")_"|"_##class(Config.Databases).Exists("OCUORDERS_CODE")_"|"_##class(Config.Databases).Exists("OCUORDERS_DATA") Set $Namespace="OCUORDERS" Write !,"CHK|kept|",kept,"|",##class(Ens.Config.Production).%ExistsId("ZzOcuForeign.Production"),"|",##class(Ens.Config.Production).%ExistsId("OcuTalon.Demo.Orders.Production")' \
  "$(foreign_grant remove)" \
  'Halt'
sed -n 's/^CHK|stop-error|/  the foreign production did not stop: /p' "$tmp/actual.chk"
set_demo_mode 1

# The foreign production is removed. The Orders production is then left Troubled (the director's state global names it and no
# job runs, as after a crash), and the step recovers and starts it.
check_session "the foreign production is removed, and the Orders production is left Troubled (fixture)" OCUORDERS \
  "CHK|foreign-removed|1|0
CHK|troubled|OcuTalon.Demo.Orders.Production|4" \
  'Write !,"CHK|foreign-removed|",$SYSTEM.OBJ.Delete("ZzOcuForeign.Production","-d"),"|",##class(Ens.Config.Production).%ExistsId("ZzOcuForeign.Production")' \
  'Set ^Ens.Runtime("Name")="OcuTalon.Demo.Orders.Production" Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|troubled|",n,"|",s' \
  'Halt'
check_session "a Troubled Orders production is recovered and started, and its items run; the run clears the note (matrix rows 2 and 15)" OCUTALON \
  "CHK|seeded|1
CHK|run|1
CHK|warn|0|
CHK|note|<absent>
CHK|own|1|1|1|1
CHK|running|1|OcuTalon.Demo.Orders.Production" \
  'Write !,"CHK|seeded|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record("demoKept","stale"))' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)' \
  'Set w=##class(OcuTalon.Install.Step).TakeWarnings() Write !,"CHK|warn|",$ListLength(w),"|",$ListGet(w,1)' \
  "$(kept_note)" \
  "$(own_access own)" \
  'Set $Namespace="OCUORDERS" Write !,"CHK|running|",##class(Ens.Director).IsProductionRunning(.n),"|",n' \
  'Halt'

# A production that does not finish starting is an error that names the item: a pool is set on the adapterless PartnerOrdersIn in
# the running configuration, so that it has no job; the subclass waits 3 s instead of the step's 60.
check_session "a production whose items do not all run within the wait is an error naming the item (matrix row 1)" OCUTALON \
  "CHK|pre|1|OcuTalon.Demo.Orders.Production
CHK|fixture|1
CHK|run|0|ERROR #5001: OcuTalon.Demo.Orders.Production did not finish starting in 3 s: these items do not run: PartnerOrdersIn
CHK|restored|1
CHK|fixture-removed|1" \
  'Set $Namespace="OCUORDERS" Write !,"CHK|pre|",##class(Ens.Director).IsProductionRunning(.n),"|",n Set $Namespace="OCUTALON"' \
  'Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOcuFast.cls","ck-d")' \
  'Set $Namespace="OCUORDERS" Set ^Ens.Runtime("ConfigItem","PartnerOrdersIn","PoolSize")=1 Set $Namespace="OCUTALON"' \
  'Set sc=##class(ZzOcuFast.Demo).Run() Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set $Namespace="OCUORDERS" Set ^Ens.Runtime("ConfigItem","PartnerOrdersIn","PoolSize")=0 Set $Namespace="OCUTALON"' \
  "$demo_run"' Write !,"CHK|restored|",$SYSTEM.Status.IsOK(sc)' \
  'Write !,"CHK|fixture-removed|",$SYSTEM.OBJ.Delete("ZzOcuFast.Demo","-d")' \
  'Halt'

# Demo mode switched off while the Orders production runs (Story 4.1's switch, with no restart): the step stops the production
# and removes OCUORDERS, and no job is left there; switched on again, it creates OCUORDERS and starts the production.
set_demo_mode 0
check_session "demo mode off while the Orders production runs stops it and removes OCUORDERS, with no job left there (matrix row 3)" OCUTALON \
  "CHK|pre|1|OcuTalon.Demo.Orders.Production
CHK|settled|1
CHK|seeded|1
CHK|run|1|
CHK|warn|0|
CHK|note|<absent>
CHK|gone|0|0|0" \
  'Set $Namespace="OCUORDERS" Write !,"CHK|pre|",##class(Ens.Director).IsProductionRunning(.n),"|",n '"$settle_scheduler"' Write !,"CHK|settled|",settled Set $Namespace="OCUTALON"' \
  'Write !,"CHK|seeded|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record("demoKept","stale"))' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set w=##class(OcuTalon.Install.Step).TakeWarnings() Write !,"CHK|warn|",$ListLength(w),"|",$ListGet(w,1)' \
  "$(kept_note)" \
  'Set $Namespace="%SYS" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.ProcessQuery WHERE NameSpace = ?","OCUORDERS") Do rs.%Next() Write !,"CHK|gone|",##class(Config.Namespaces).Exists("OCUORDERS"),"|",$Data(^%SYS("Ensemble","RunningNamespace","OCUORDERS")),"|",rs.%GetData(1) Set $Namespace="OCUTALON"' \
  'Halt'
set_demo_mode 1
check_session "demo mode on again creates OCUORDERS and starts the Orders production (matrix row 5)" OCUTALON \
  "CHK|run|1|" \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Halt'
check_orders_jobs "row 4 after the foreign and broken states"
check_session "row 4: the public class is deleted" OCUTALON "CHK|deleted|1" \
  'Write !,"CHK|deleted|",$SYSTEM.OBJ.Delete("OcuTalon.Data.Public.Settings","-d")' 'Halt'
# The last restart has demo mode off and the foreign production defined in OCUORDERS and stopped: LoadFromClass defines it (it adds
# its definition to the namespace) and starts nothing, so the Orders production keeps running until the restart.
check_session "row 4: OcuTalon's access to OCUORDERS is whole, and the foreign production is defined there and not started (fixture before the last restart)" OCUTALON \
  "CHK|own-before|1|1|1|1
CHK|fixture|1
CHK|defined|1|1
CHK|not-foreign-running|1" \
  "$(own_access own-before)" \
  'Set $Namespace="OCUORDERS" Write !,"CHK|fixture|",$SYSTEM.OBJ.Load("/tmp/ZzOcuForeign.cls","ck-d")' \
  'Set sc=##class(Ens.Config.Production).LoadFromClass("ZzOcuForeign.Production") Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Config.Production WHERE Name = ?","ZzOcuForeign.Production") Do rs.%Next() Write !,"CHK|defined|",$SYSTEM.Status.IsOK(sc),"|",rs.%GetData(1)' \
  'Set r=##class(Ens.Director).IsProductionRunning(.n) Write !,"CHK|not-foreign-running|",$Select(n="ZzOcuForeign.Production":0,1:1)' \
  'Halt'
set_demo_mode 0
dc stop iris >/dev/null 2>&1
dc start iris >/dev/null 2>&1
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 4 the restart did not end ready within 200 s"
fi
expected_run "nothing to clear" "present $ipm_version" "already mapped" "OcuTalon.Data.Public.Settings is not compiled" \
  "loaded (public classes)" "$version" > "$tmp/expected.row4"
check_log "row 4" "$tmp/expected.row4"
check_ready_state "row 4"
check_kept_log "row 4" "$defined_sentence"
check_session "row 4: the last start kept OCUORDERS and the foreign definition, recorded the note, and removed OcuTalon's own access only (matrix row 12)" OCUTALON \
  "CHK|note|$defined_sentence|OCUORDERS|OCUORDERS_DATA|OCUORDERS_CODE|$defined_how
CHK|own|0|0|0|0
CHK|kept|1|1|1|1|1" \
  "$(kept_note)" \
  "$(own_access own)" \
  'Set $Namespace="%SYS" Set kept=##class(Config.Namespaces).Exists("OCUORDERS")_"|"_##class(Config.Databases).Exists("OCUORDERS_CODE")_"|"_##class(Config.Databases).Exists("OCUORDERS_DATA") Set $Namespace="OCUORDERS" Write !,"CHK|kept|",kept,"|",##class(Ens.Config.Production).%ExistsId("ZzOcuForeign.Production"),"|",##class(Ens.Config.Production).%ExistsId("OcuTalon.Demo.Orders.Production")' \
  'Halt'

# --- row 5: the bridge alone, in a namespace without IPM ---

# bridge_refs (lib-scan.sh) is the source check of AD-2; test-class-rules.sh runs it in the hosted checks job.
# The scan is shown to flag a bad sample and to pass a clean one (bridge_ref_samples of lib-scan.sh) before it is trusted on the
# real tree.
bridge_ref_samples "$tmp/refs"
if [ "$(bridge_refs "$tmp/refs/Bad.cls" | wc -l | tr -d ' ')" = 2 ] && [ -z "$(bridge_refs "$tmp/refs/Ok.cls")" ]; then
  pass "row 5: the source check flags another package named as a class or as a table, and passes the bridge's own names and comments"
else
  fail "row 5: the source check does not flag the bad sample exactly twice, or flags the clean one"
fi
bridge_files=$(find src/bridge/cls -name '*.cls' | sort)
if [ -z "$bridge_files" ]; then
  fail "row 5: no class under src/bridge/cls/ was found to scan"
else
  refs=$(bridge_refs $bridge_files)
  if [ -z "$refs" ]; then
    pass "row 5: no code under src/bridge/ names an OcuTalon package other than the bridge's own ($(printf '%s\n' "$bridge_files" | wc -l | tr -d ' ') classes)"
  else
    printf '%s\n' "$refs" | head -n 10 | sed 's/^/  /'
    fail "row 5: code under src/bridge/ names an OcuTalon package other than the bridge's own"
  fi
fi

cat > "$tmp/ocubridget.cpf" <<'EOC'
[Actions]
CreateResource:Name=%DB_OCUBRIDGET,Description="Bridge-only test database"
CreateDatabase:Name=OCUBRIDGET,Directory=ocubridget,Resource=%DB_OCUBRIDGET
CreateNamespace:Name=OCUBRIDGET,Globals=OCUBRIDGET,Routines=OCUBRIDGET,Interop=1
CreateResource:Name=%DB_OCUPLAIN,Description="Plain namespace test database"
CreateDatabase:Name=OCUPLAIN,Directory=ocuplain,Resource=%DB_OCUPLAIN
CreateNamespace:Name=OCUPLAIN,Globals=OCUPLAIN,Routines=OCUPLAIN
EOC
if dc exec -T iris sh -c 'cat > /tmp/ocubridget.cpf' < "$tmp/ocubridget.cpf" >/dev/null 2>&1 \
  && dc exec -T iris iris merge IRIS /tmp/ocubridget.cpf >/dev/null 2>&1; then
  pass "row 5: the Interoperability namespace OCUBRIDGET and the plain namespace OCUPLAIN are created"
else
  die "row 5 the namespaces OCUBRIDGET and OCUPLAIN could not be created"
fi
check_session "row 5: the bridge loads and installs alone, in a namespace without IPM" OCUBRIDGET \
  "CHK|ipm-class|0
CHK|load|1
CHK|run|1
CHK|other-classes|0
CHK|ipm-after|0
CHK|ns|OCUBRIDGET" \
  'Write !,"CHK|ipm-class|",##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main")' \
  'Write !,"CHK|load|",$SYSTEM.OBJ.LoadDir("/opt/ocutalon/src/bridge/cls","ck-d",.errors,1)' \
  'Write !,"CHK|run|",##class(OcuTalon.Bridge.Installer).Run()' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ? AND NOT (Name %STARTSWITH ? OR Name %STARTSWITH ?)","OcuTalon.","OcuTalon.Bridge.","OcuTalon.BridgeExample.") Do rs.%Next() Write !,"CHK|other-classes|",rs.%GetData(1)' \
  'Write !,"CHK|ipm-after|",##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main")' \
  'Write !,"CHK|ns|",$Namespace' \
  'Halt'
# The installer refuses a namespace that is not an Interoperability namespace, and names it.
check_session "row 5: the bridge installer refuses a namespace without Interoperability" OCUPLAIN \
  "CHK|load|1
CHK|refused|1
CHK|names-namespace|1" \
  'Write !,"CHK|load|",$SYSTEM.OBJ.Load("/opt/ocutalon/src/bridge/cls/OcuTalon/Bridge/Installer.cls","ck-d")' \
  'Set sc=##class(OcuTalon.Bridge.Installer).Run() Write !,"CHK|refused|",$SYSTEM.Status.IsError(sc),!,"CHK|names-namespace|",($SYSTEM.Status.GetErrorText(sc)["OCUPLAIN")' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-install-start: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-install-start: all checks passed"

# --- Story 5.1 (veto U-79): the keep path takes the service role's Read on the OCUORDERS data database away. ---
# This block is self-contained: it runs after the summary above and ends with a summary of its own. The script ends in the keep state (demo mode off,
# the foreign OCUORDERS kept). A start rewrites the roles first, so the block seeds the grant itself (and the resource, when the keep left none), reruns
# the Demo step as the mode switch does, and checks that the service role holds no OCUORDERS resource afterwards. The off path shares the keep path's
# role edit, which runs before either branch removes anything else.
check_session "Story 5.1 (U-79): the Demo step in the keep state removes the service role's OCUORDERS data grant, and the role holds no OCUORDERS resource" OCUTALON \
  "CHK|seeded|1|1
CHK|run|1|
CHK|role|0" \
  'Set $Namespace="%SYS" Set made=0 If '\''##class(Security.Resources).Exists("%DB_OCUORDERS_DATA") { Set made=$SYSTEM.Status.IsOK(##class(Security.Resources).Create("%DB_OCUORDERS_DATA","Story 5.1 fixture")) } Set ok=##class(Security.Roles).Get("OcuTalonServiceRole",.p) Kill q Set q("Resources")=p("Resources")_$Select(p("Resources")="":"",1:",")_"%DB_OCUORDERS_DATA:R" Set mc=##class(Security.Roles).Modify("OcuTalonServiceRole",.q) Set ok=##class(Security.Roles).Get("OcuTalonServiceRole",.p) Write !,"CHK|seeded|",$SYSTEM.Status.IsOK(mc),"|",(p("Resources")["%DB_OCUORDERS_DATA:R") Set $Namespace="OCUTALON"' \
  "$demo_run"' Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Status.GetErrorText(sc)' \
  'Set $Namespace="%SYS" Set ok=##class(Security.Roles).Get("OcuTalonServiceRole",.p) Write !,"CHK|role|",($Get(p("Resources"))["OCUORDERS") If made { Set d=##class(Security.Resources).Delete("%DB_OCUORDERS_DATA") } Set $Namespace="OCUTALON"' \
  'Halt'
if [ "$fails" -ne 0 ]; then
  echo "test-install-start: $fails check(s) failed (including the U-79 block; project $P)"
  exit 1
fi
echo "test-install-start: all checks passed (including the U-79 block)"
