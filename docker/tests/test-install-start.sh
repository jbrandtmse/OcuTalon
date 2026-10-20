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
# file), switched off before row 2's restart, still off at row 3's recreate, and switched on before row 4's recreate. The checks
#   - row 1: OCUORDERS, its databases, resources, mappings, Interoperability, production and trace grants exist (check_demo_on),
#     and the surfaces of the instance are recorded;
#   - row 2: all of it is gone (check_demo_off), and the surfaces equal row 1's less every line that names OCUORDERS;
#   - row 3: still gone, and the step does nothing;
#   - row 4: recreated, with the same surfaces as row 1.
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
check_demo_off "row 3"
live_pop_file

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
check_session "row 4: the public class is deleted" OCUTALON "CHK|deleted|1" \
  'Write !,"CHK|deleted|",$SYSTEM.OBJ.Delete("OcuTalon.Data.Public.Settings","-d")' 'Halt'
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
