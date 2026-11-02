#!/usr/bin/env bash
# Live test of Story 0.1's image with the after-start script switched off (compose.no-after-start.yml):
# builds the image and starts it in a throwaway compose project, then checks
#   - the OCUTALON namespace, databases, mappings and CallIn service (CHECK),
#   - Docker's health monitor against docker/healthcheck.sh (matrix row 7),
#   - the version baked into the image (matrix row 8) and the image's own files, owned by root and read-only
#     (the sources, the pinned IPM release and the scripts included),
#   - that the first start's merge runs without errors, and that data survives a plain stop and start
#     and a plain recreate on the same volume, and a stop and start and a recreate that make iris-main
#     reapply the merge, which then runs without errors.
# The project is unique, publishes no host port and receives no keys: the test adds a decoy key file
# of its own, which the throwaway override must drop. The one bot token it may hold is the CI override's dummy (live_key_count).
# An EXIT trap removes the project with its volume and image. Every wait ends by an overall deadline, so even a failing run ends
# within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t01
live_add_file "$root/docker/tests/compose.no-after-start.yml"
LIVE_IMAGES+=("$P-version-ok" "$P-version-bad")

# --- helpers ---

# Ready = IRIS running and this start's merge recorded. iris-main records a merge by copying the
# merge file next to iris.cpf as *.last_merge, after the actions ran, so the record equals the image's file.
iris_ready() {
  dc exec -T iris sh -c 'iris qlist | grep -q "\^running" && cmp -s /opt/ocutalon/merge.cpf /durable/iris/*.last_merge' >/dev/null 2>&1
}

wait_ready() { wait_until "$1" iris_ready; } # wait_ready <max seconds>

# iris-main skips a merge file that is unchanged since the one it applied last. Either of these makes
# the next start apply the merge again over the existing databases and mappings:
#   forget_last_merge removes the record of the last merge;
#   change_last_merge edits the record, as a new image with a changed merge file would differ from it,
#   keeping the record's read-only mode.
forget_last_merge() { dc exec -T iris sh -c 'rm -f /durable/iris/*.last_merge' >/dev/null 2>&1; }
change_last_merge() {
  dc exec -T iris sh -c 'f=$(ls /durable/iris/*.last_merge) && chmod u+w "$f" && printf "; changed\n" >> "$f" && chmod 444 "$f"' >/dev/null 2>&1
}

check_script() {
  cat <<'EOS'
Write !,"CHK|ns-exists|",##class(%SYS.Namespace).Exists("OCUTALON")
Write !,"CHK|ns-interop|",##class(%Library.EnsembleMgr).IsEnsembleNamespace("OCUTALON")
Set sc=##class(Config.Namespaces).Get("OCUTALON",.np) Write !,"CHK|ns-globals|",$Get(np("Globals")) Write !,"CHK|ns-routines|",$Get(np("Routines"))
For db="OCUTALON_CODE","OCUTALON_DATA","OCUTALON_PRIVATE","OCUTALON_PUBLIC" { Kill dp Set sc=##class(Config.Databases).Get(db,.dp) Write !,"CHK|db-dir|",db,"|",$Get(dp("Directory")) Set d=##class(SYS.Database).%OpenId($Get(dp("Directory"))) Write !,"CHK|db-resource|",db,"|",$Select($IsObject(d):d.ResourceName,1:"") }
For db="OCUTALON_CODE","OCUTALON_DATA","OCUTALON_PRIVATE","OCUTALON_PUBLIC" { Write !,"CHK|res-exists|",db,"|",##class(Security.Resources).Exists("%DB_"_db) }
For db="OCUTALON_CODE","OCUTALON_DATA","OCUTALON_PRIVATE","OCUTALON_PUBLIC" { Kill rp Set sc=##class(Security.Resources).Get("%DB_"_db,.rp) Set pm=$Get(rp("PublicPermission")) Write !,"CHK|pub-read|",db,"|",$Select(pm?1.N:pm#2,1:pm["R") Write !,"CHK|pub-write|",db,"|",$Select(pm?1.N:pm\2#2,1:pm["W") }
For g="OcuTalonP.S01","OcuTalonP.S02","OcuTalonBP.S01","OcuTalonBP.S02","AI.Agent.SessionD","AI.Agent.SessionI","IRIS.IF.S01","IRIS.IF.Index","OcuTalonPublic","OcuTalonS01","AI.Agent.Other","IRIS.Other.S01" { Write !,"CHK|gdest|",g,"|",##class(%SYS.Namespace).GetGlobalDest("OCUTALON","^"_g) }
For p="OcuTalon.Web.Public","OcuTalon.Data.Public","OcuTalon.Web.Other","OcuTalon.Data.Other" { Write !,"CHK|pdest|",p,"|",##class(%SYS.Namespace).GetPackageDest("OCUTALON",p) }
Set sc=##class(Security.Services).Get("%Service_CallIn",.sv) Write !,"CHK|callin-enabled|",$Get(sv("Enabled")) Write !,"CHK|callin-authe|",$Get(sv("AutheEnabled"))
Halt
EOS
}

check_expected() {
  cat <<EOX
CHK|ns-exists|1
CHK|ns-interop|1
CHK|ns-globals|OCUTALON_DATA
CHK|ns-routines|OCUTALON_CODE
CHK|db-dir|OCUTALON_CODE|$mgr/ocutalon_code/
CHK|db-dir|OCUTALON_DATA|$mgr/ocutalon_data/
CHK|db-dir|OCUTALON_PRIVATE|$mgr/ocutalon_private/
CHK|db-dir|OCUTALON_PUBLIC|$mgr/ocutalon_public/
CHK|db-resource|OCUTALON_CODE|%DB_OCUTALON_CODE
CHK|db-resource|OCUTALON_DATA|%DB_OCUTALON_DATA
CHK|db-resource|OCUTALON_PRIVATE|%DB_OCUTALON_PRIVATE
CHK|db-resource|OCUTALON_PUBLIC|%DB_OCUTALON_PUBLIC
CHK|res-exists|OCUTALON_CODE|1
CHK|res-exists|OCUTALON_DATA|1
CHK|res-exists|OCUTALON_PRIVATE|1
CHK|res-exists|OCUTALON_PUBLIC|1
CHK|pub-read|OCUTALON_CODE|0
CHK|pub-read|OCUTALON_DATA|0
CHK|pub-read|OCUTALON_PRIVATE|0
CHK|pub-read|OCUTALON_PUBLIC|1
CHK|pub-write|OCUTALON_CODE|0
CHK|pub-write|OCUTALON_DATA|0
CHK|pub-write|OCUTALON_PRIVATE|0
CHK|pub-write|OCUTALON_PUBLIC|0
CHK|gdest|OcuTalonP.S01|^$mgr/ocutalon_private/
CHK|gdest|OcuTalonP.S02|^$mgr/ocutalon_private/
CHK|gdest|OcuTalonBP.S01|^$mgr/ocutalon_private/
CHK|gdest|OcuTalonBP.S02|^$mgr/ocutalon_private/
CHK|gdest|AI.Agent.SessionD|^$mgr/ocutalon_private/
CHK|gdest|AI.Agent.SessionI|^$mgr/ocutalon_private/
CHK|gdest|IRIS.IF.S01|^$mgr/ocutalon_private/
CHK|gdest|IRIS.IF.Index|^$mgr/ocutalon_private/
CHK|gdest|OcuTalonPublic|^$mgr/ocutalon_public/
CHK|gdest|OcuTalonS01|^$mgr/ocutalon_data/
CHK|gdest|AI.Agent.Other|^$mgr/ocutalon_data/
CHK|gdest|IRIS.Other.S01|^$mgr/ocutalon_data/
CHK|pdest|OcuTalon.Web.Public|^$mgr/ocutalon_public/
CHK|pdest|OcuTalon.Data.Public|^$mgr/ocutalon_public/
CHK|pdest|OcuTalon.Web.Other|^$mgr/ocutalon_code/
CHK|pdest|OcuTalon.Data.Other|^$mgr/ocutalon_code/
CHK|callin-enabled|1
CHK|callin-authe|48
EOX
}

run_check() { # run_check <label>: namespace, databases, mappings, service, mount and data directory
  local label=$1 mounts qdir
  check_expected > "$tmp/check.expected"
  check_script | iris_script %SYS > "$tmp/check.actual"
  compare_chk "CHECK $label" "$tmp/check.actual" "$tmp/check.expected"

  mounts=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/durable"}}{{.Type}} {{.Name}}{{end}}{{end}}' "$cid" 2>/dev/null)
  if [ "$mounts" = "volume ${P}_durable" ]; then
    pass "CHECK $label: /durable is the named volume"
  else
    fail "CHECK $label: /durable mount is '$mounts', wanted 'volume ${P}_durable'"
  fi

  qdir=$(dc exec -T iris iris qlist 2>/dev/null | cut -d'^' -f13)
  if [ "$qdir" = /durable/iris/ ]; then
    pass "CHECK $label: qlist data directory is /durable/iris/"
  else
    fail "CHECK $label: qlist data directory is '$qdir', wanted /durable/iris/"
  fi
}


# The newest merge must have run without errors: no line of its process, from its "Merging" line on,
# is an error line (merge_errors).
check_merge_log() { # check_merge_log <label> <count before>
  local label=$1 before=$2 after last lineno pid bad
  after=$(merge_count)
  if [ "$after" != "$((before + 1))" ]; then
    fail "merge $label: messages.log has '$after' Merging lines, wanted $((before + 1))"
    return
  fi
  last=$(dc exec -T iris grep -n 'Merging /opt/ocutalon/merge.cpf' "$mgr/messages.log" 2>/dev/null | tr -d '\r' | tail -n 1)
  lineno=${last%%:*}
  pid=$(printf '%s\n' "$last" | sed -n 's/^[0-9]*:[^ ]* (\([0-9]*\)) .*/\1/p')
  if [ -z "$lineno" ] || [ -z "$pid" ]; then
    fail "merge $label: could not read the newest Merging line ('$last')"
    return
  fi
  bad=$(dc exec -T iris tail -n "+$lineno" "$mgr/messages.log" 2>/dev/null | tr -d '\r' | merge_errors "$pid")
  if [ -n "$bad" ]; then
    echo "$bad" | head -n 5 | sed 's/^/  /'
    fail "merge $label: process $pid logged error lines"
  else
    pass "merge $label: applied by process $pid with no error lines"
  fi
}

# --- health monitor (row 7) ---

# For up to 40 s Docker keeps reporting `starting` while its monitor runs the script at least twice,
# and each run exits 1.
stays_starting() { # stays_starting <label>
  local label=$1 rc seen=0 waited=0 last cur st
  rc=$(script_exit)
  if [ "$rc" != 1 ]; then
    fail "row 7 $label: the script exited $rc inside the container, wanted 1"
    return
  fi
  last=$(health_ends)
  while [ "$waited" -lt 40 ] && [ "$seen" -lt 2 ] && [ "$SECONDS" -lt "$deadline" ]; do
    st=$(health_status)
    if [ "$st" != starting ]; then
      fail "row 7 $label: health status is '$st', wanted 'starting'"
      return
    fi
    cur=$(health_ends)
    if [ "$cur" != "$last" ]; then
      seen=$((seen + 1))
      last=$cur
    fi
    sleep 2
    waited=$((waited + 2))
  done
  if [ "$seen" -lt 2 ]; then
    fail "row 7 $label: the health monitor ran $seen check(s) in 40 s, wanted 2 (status '$(health_status)')"
    return
  fi
  if [ "$(health_last_exit)" != 1 ]; then
    fail "row 7 $label: the monitor's last check exited '$(health_last_exit)', wanted 1 (status '$(health_status)')"
    return
  fi
  pass "row 7 $label: script exits 1 and Docker stays 'starting'"
}

# --- start ---

# The merge-log filter must flag the error lines of its own process, and only those. The ERROR #507
# line is build 154's own record of a merge action that failed.
cat > "$tmp/log.sample" <<'EOL'
10/18/26-18:10:02:276 (2488) 0 [Utility.Event] Merging /opt/ocutalon/merge.cpf into /durable/iris/iris.cpf
10/18/26-18:10:02:709 (2489) 2 [Utility.Event] another process
10/18/26-18:10:02:800 (2488) 1 [Utility.Event] a warning
10/18/26-18:10:02:850 (2488) 1 [Utility.Event] ERROR #507: Action 'CreateMapGlobal' failed, Method Config.MapGlobals:CreateOne(), Error=ERROR #420: Database OCUTALON_NOSUCH does not exist
10/18/26-18:10:02:851 (2488) 2 [Utility.Event] a severe line
10/18/26-18:10:02:852 (2488) 3 [Utility.Event] a fatal line
EOL
if [ "$(merge_errors 2488 < "$tmp/log.sample" | wc -l | tr -d ' ')" = 3 ] \
  && [ "$(merge_errors 2488 < "$tmp/log.sample" | grep -c -e ' \[Utility.Event\] ERROR #507: ' \
    -e ' \[Utility.Event\] a severe line$' -e ' \[Utility.Event\] a fatal line$')" = 3 ]; then
  pass "merge log filter flags the error lines of its own process only"
else
  fail "merge log filter does not isolate the error lines of one process"
fi

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

# The throwaway override must leave the container with no published host port and no keys.
published=$(docker inspect --format '{{len .HostConfig.PortBindings}}' "$cid" 2>/dev/null)
keys=$(live_key_count)
if [ "$published" = 0 ] && [ "$keys" = 0 ]; then
  pass "throwaway container publishes no host port and receives no keys (the CI dummy bot token is no key)"
else
  fail "throwaway container has '$published' published port(s) and '$keys' key variable(s), wanted 0 and 0"
fi

if ! wait_ready 240; then
  dc logs --tail 30 iris 2>&1 | cut -c1-200
  die "IRIS did not reach running with the merge applied within 240 s"
fi
pass "IRIS running with the merge applied"
check_merge_log "first start" 0

run_check "first start"

# --- row 7: Docker's health monitor consumes the script ---

dc exec -T iris rm -f /durable/ocutalon.ready >/dev/null 2>&1
stays_starting "no marker"

dc exec -T iris sh -c 'echo 0.0.9 > /durable/ocutalon.ready' >/dev/null 2>&1
stays_starting "wrong marker"

dc exec -T iris cp /opt/ocutalon/version /durable/ocutalon.ready >/dev/null 2>&1
rc=$(script_exit)
if [ "$rc" != 0 ]; then
  fail "row 7 marker equal to the version: the script exited $rc inside the container, wanted 0"
else
  waited=0
  st=$(health_status)
  while [ "$st" != healthy ] && [ "$waited" -lt 60 ] && [ "$SECONDS" -lt "$deadline" ]; do
    sleep 2
    waited=$((waited + 2))
    st=$(health_status)
  done
  if [ "$st" = healthy ]; then
    pass "row 7 marker equal to the version: script exits 0 and Docker reports 'healthy' (after $waited s)"
  else
    fail "row 7 marker equal to the version: health status is '$st' after 60 s, wanted 'healthy'"
  fi
fi
dc exec -T iris rm -f /durable/ocutalon.ready >/dev/null 2>&1

# --- row 8: the image's version is the manifest's first <Version> ---

want=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/module.xml | head -n 1)
have=$(dc exec -T iris cat /opt/ocutalon/version 2>/dev/null | tr -d '\r\n')
if [ -n "$want" ] && [ "$have" = "$want" ]; then
  pass "row 8 /opt/ocutalon/version is '$want'"
else
  fail "row 8 /opt/ocutalon/version is '$have', src/module.xml says '$want'"
fi

# A second <Version> after the module's own must not change the image's version, and a manifest with
# no version must fail the build.
ctx="$tmp/context"
copy_build_context "$ctx"
awk '{ print } /<Version>/ && !done { print "    <Version>9.9.9</Version>"; done = 1 }' src/module.xml > "$ctx/src/module.xml"
if docker build -q -f "$ctx/docker/Dockerfile" --build-arg "IRIS_IMAGE=$base_image" -t "$P-version-ok" "$ctx" >/dev/null 2>&1; then
  got=$(docker run --rm --entrypoint cat "$P-version-ok" /opt/ocutalon/version 2>/dev/null | tr -d '\r\n')
  if [ -n "$want" ] && [ "$got" = "$want" ]; then
    pass "row 8 the first <Version> wins over a later one"
  else
    fail "row 8 with a later <Version> the image holds '$got', wanted '$want'"
  fi
  grep -v '<Version>' src/module.xml > "$ctx/src/module.xml"
  if docker build -q -f "$ctx/docker/Dockerfile" --build-arg "IRIS_IMAGE=$base_image" -t "$P-version-bad" "$ctx" >/dev/null 2>&1; then
    fail "row 8 a manifest without a version built an image"
  else
    pass "row 8 a manifest without a version fails the build"
  fi
else
  fail "row 8 the control build with a version failed"
fi

# --- the image's own files: owned by root, so the IRIS user can neither change nor re-mode them ---
# Directories 555, the two scripts that run 555, every other file 444. The listing is `type|path|owner|mode`.
# The evaluation set that the throwaway override mounts read-only at /opt/ocutalon/eval (Story 0.10) and the model mock's request
# log that the CI override mounts read-only at /opt/ocutalon/mock-log (Story 0.11) are not the image's: they are left out of the
# listing, and the image itself is checked to hold neither folder.

modes=$(dc exec -T iris find /opt/ocutalon \( -path /opt/ocutalon/eval -o -path /opt/ocutalon/mock-log \) -prune -o -exec stat -c '%F|%n|%u|%a' {} + 2>/dev/null | tr -d '\r' | sort)
bad_modes=$(printf '%s\n' "$modes" | awk -F'|' '
  { want = ($1 == "directory") ? 555 : 444
    if ($2 == "/opt/ocutalon/healthcheck.sh" || $2 == "/opt/ocutalon/after-start.sh") want = 555
    if (($1 != "directory" && $1 != "regular file" && $1 != "regular empty file") || $3 != 0 || $4 != want) print $2 " is " $1 ", owner " $3 ", mode " $4 "; wanted owner 0, mode " want }')
missing=""
for f in version merge.cpf healthcheck.sh after-start.sh after-start.cos ipm/zpm-0.10.10.xml ipm/LICENSE \
  src/module.xml src/bridge/cls/OcuTalon/Bridge/Installer.cls src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls; do
  if ! printf '%s\n' "$modes" | grep -q "^regular file|/opt/ocutalon/$f|"; then missing="$missing $f"; fi
done
if [ -n "$modes" ] && [ -z "$bad_modes" ] && [ -z "$missing" ]; then
  pass "/opt/ocutalon, its sources, scripts and pinned IPM release are root's and read-only, the two scripts executable ($(printf '%s\n' "$modes" | wc -l | tr -d ' ') entries)"
else
  printf '%s\n' "$bad_modes" | head -n 5 | sed 's/^/  /'
  fail "/opt/ocutalon owners and modes are wrong (missing:$missing)"
fi

if docker run --rm --entrypoint sh "$P-iris" -c 'test ! -e /opt/ocutalon/eval' >/dev/null 2>&1; then
  pass "the image holds no /opt/ocutalon/eval: the evaluation set is mounted by the throwaway override only"
else
  fail "the image holds /opt/ocutalon/eval, or the image could not be inspected"
fi

if docker run --rm --entrypoint sh "$P-iris" -c 'test ! -e /opt/ocutalon/mock-log' >/dev/null 2>&1; then
  pass "the image holds no /opt/ocutalon/mock-log: the mock's request log is mounted by the CI override only"
else
  fail "the image holds /opt/ocutalon/mock-log, or the image could not be inspected"
fi

# --- restarts ---

# restart_round <label> <stop|recreate> <plain|forget|change>
# Restarts the container (a new start time) or recreates it (a new container), then the probes and
# CHECK hold. For forget and change the merge also reapplies over the existing databases: one more
# Merging line, and no error line.
restart_round() {
  local label=$1 how=$2 merge=$3 before started old
  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "$label: the run's 540 s deadline has passed"
    return
  fi
  before=$(merge_count)
  case "$merge" in
    forget) forget_last_merge ;;
    change) change_last_merge ;;
  esac
  if [ "$how" = stop ]; then
    started=$(docker inspect --format '{{.State.StartedAt}}' "$cid" 2>/dev/null)
    if ! dc stop iris >/dev/null 2>&1 || ! dc start iris >/dev/null 2>&1; then
      fail "$label: stop or start failed"
      return
    fi
    if [ "$(docker inspect --format '{{.State.StartedAt}}' "$cid" 2>/dev/null)" = "$started" ]; then
      fail "$label: the container's start time did not change"
      return
    fi
  else
    old=$cid
    if ! dc down >/dev/null 2>&1; then
      fail "$label: down failed"
      return
    fi
    if ! dc up -d > "$tmp/up2.log" 2>&1; then
      tail -n 20 "$tmp/up2.log"
      fail "$label: up -d after down failed"
      return
    fi
    cid=$(dc ps -q iris)
    if [ -z "$cid" ] || [ "$cid" = "$old" ]; then
      fail "$label: no new container (was $old, now '$cid')"
      return
    fi
  fi
  if ! wait_ready 90; then
    fail "$label: IRIS was not ready within 90 s"
    return
  fi
  if [ "$merge" != plain ]; then
    check_merge_log "$label" "$before"
  fi
  check_probes "$label"
  run_check "$label"
}

set_probes
check_probes "before restart"

restart_round "after plain stop and start" stop plain
restart_round "after plain recreate" recreate plain
restart_round "after stop and start with a changed merge file" stop change
restart_round "after recreate with the merge record removed" recreate forget

if [ "$fails" -ne 0 ]; then
  echo "test-compose-start: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-compose-start: all checks passed"
