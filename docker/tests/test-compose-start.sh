#!/usr/bin/env bash
# Live test: builds the image and starts it in a throwaway compose project, then checks
#   - the OCUTALON namespace, databases, mappings and CallIn service (CHECK),
#   - Docker's health monitor against docker/healthcheck.sh (matrix row 7),
#   - the version baked into the image (matrix row 8) and the image's own files, owned by root and read-only,
#   - that the first start's merge runs without errors, and that data survives a plain stop and start
#     and a plain recreate on the same volume, and a stop and start and a recreate that make iris-main
#     reapply the merge, which then runs without errors.
# The project is unique, publishes no host port and receives no keys: the test adds a decoy key file
# of its own, which the throwaway override must drop. An EXIT trap removes the project with its volume
# and image. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

P="ocutalon-t01-$(date +%s)-$$"
base_image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
mgr=/durable/iris/mgr
fails=0
cid=""
deadline=$((SECONDS + 540))

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-live.XXXXXX") || exit 1

# A key source that only compose.throwaway.yml's env_file reset keeps out of the container.
printf 'ANTHROPIC_API_KEY=decoy\nTELEGRAM_BOT_TOKEN=decoy\n' > "$tmp/decoy.env"
printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$tmp/decoy.env" > "$tmp/decoy.yml"

dc() { docker compose -p "$P" -f docker-compose.yml -f "$tmp/decoy.yml" -f docker/tests/compose.throwaway.yml "$@"; }

cleanup() {
  dc down -v --rmi local >/dev/null 2>&1
  docker image rm -f "$P-version-ok" "$P-version-bad" >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
die() { # a failure after which nothing else can run
  echo "FAIL $1"
  echo "test-compose-start: aborted"
  exit 1
}

# --- helpers ---

# Ready = IRIS running and this start's merge recorded. iris-main records a merge by copying the
# merge file next to iris.cpf as *.last_merge, after the actions ran, so the record equals the image's file.
iris_ready() {
  dc exec -T iris sh -c 'iris qlist | grep -q "\^running" && cmp -s /opt/ocutalon/merge.cpf /durable/iris/*.last_merge' >/dev/null 2>&1
}

wait_ready() { # wait_ready <max seconds>
  local waited=0
  while [ "$waited" -lt "$1" ] && [ "$SECONDS" -lt "$deadline" ]; do
    if iris_ready; then
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  return 1
}

# iris-main skips a merge file that is unchanged since the one it applied last. Either of these makes
# the next start apply the merge again over the existing databases and mappings:
#   forget_last_merge removes the record of the last merge;
#   change_last_merge edits the record, as a new image with a changed merge file would differ from it,
#   keeping the record's read-only mode.
forget_last_merge() { dc exec -T iris sh -c 'rm -f /durable/iris/*.last_merge' >/dev/null 2>&1; }
change_last_merge() {
  dc exec -T iris sh -c 'f=$(ls /durable/iris/*.last_merge) && chmod u+w "$f" && printf "; changed\n" >> "$f" && chmod 444 "$f"' >/dev/null 2>&1
}

# Error lines of process <pid>, from a messages.log excerpt on stdin: severity 2 or 3, or an `ERROR #`
# line of any severity (build 154 logs a failed merge action at severity 1).
merge_errors() { awk -v pid="($1)" '$2 == pid && ($3 == 2 || $3 == 3 || / ERROR #[0-9]/) { print }'; }

# Runs an ObjectScript script from stdin in the given namespace and keeps the `CHK|` result lines.
# A session that prints no result line is tried again, at most three tries 5 s apart.
iris_script() { # iris_script <namespace> < script
  local script out try=1
  script=$(cat)
  while :; do
    out=$(printf '%s\n' "$script" | dc exec -T iris iris session IRIS -U "$1" 2>/dev/null | tr -d '\r' | sed -n 's/.*\(CHK|.*\)$/\1/p')
    if [ -n "$out" ] || [ "$try" -ge 3 ]; then break; fi
    try=$((try + 1))
    sleep 5
  done
  if [ -n "$out" ]; then printf '%s\n' "$out"; fi
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

# compare_chk <label> <actual file> <expected file>: every expected line must appear in the actual output.
compare_chk() {
  local label=$1 actual=$2 expected=$3 line prefix bad=0 n=0
  if ! grep -q '^CHK|' "$actual"; then
    fail "$label: the IRIS session printed nothing"
    return 1
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    if ! grep -qxF -- "$line" "$actual"; then
      prefix=${line%|*}
      echo "  $label: wanted '$line', got '$(grep -F -- "$prefix|" "$actual" | head -n 1)'"
      bad=$((bad + 1))
    fi
  done < "$expected"
  if [ "$bad" -eq 0 ]; then
    pass "$label ($n values)"
  else
    fail "$label ($bad of $n values differ)"
  fi
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

probe_data=probe-data-$P
probe_private=probe-private-$P

set_probes() {
  local out
  out=$(printf '%s\n' \
    "Set ^OcuTalonS01Probe=\"$probe_data\",^OcuTalonP.S01Probe=\"$probe_private\"" \
    'Write !,"CHK|probes-set|",$Namespace' \
    'Halt' | iris_script OCUTALON)
  if [ "$out" = "CHK|probes-set|OCUTALON" ]; then
    pass "probes written in OCUTALON"
  else
    fail "probes could not be written in OCUTALON (got '$out')"
  fi
}

# The probes must read back through the namespace and sit in the databases that the mappings name.
check_probes() { # check_probes <label>
  local label=$1
  cat > "$tmp/probes.expected" <<EOP
CHK|probe-data|$probe_data
CHK|probe-private|$probe_private
CHK|probe-data-in-data-db|$probe_data
CHK|probe-private-in-private-db|$probe_private
CHK|probe-private-in-data-db|0
EOP
  printf '%s\n' \
    'Write !,"CHK|probe-data|",$Get(^OcuTalonS01Probe)' \
    'Write !,"CHK|probe-private|",$Get(^OcuTalonP.S01Probe)' \
    "Write !,\"CHK|probe-data-in-data-db|\",\$Get(^|\"^^$mgr/ocutalon_data/\"|OcuTalonS01Probe)" \
    "Write !,\"CHK|probe-private-in-private-db|\",\$Get(^|\"^^$mgr/ocutalon_private/\"|OcuTalonP.S01Probe)" \
    "Write !,\"CHK|probe-private-in-data-db|\",\$Data(^|\"^^$mgr/ocutalon_data/\"|OcuTalonP.S01Probe)" \
    'Halt' | iris_script OCUTALON > "$tmp/probes.actual"
  compare_chk "probes $label" "$tmp/probes.actual" "$tmp/probes.expected"
}

merge_count() { dc exec -T iris grep -c 'Merging /opt/ocutalon/merge.cpf' "$mgr/messages.log" 2>/dev/null | tr -d '\r'; }

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

health_status() { docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null; }
health_ends() { docker inspect --format '{{range .State.Health.Log}}{{.End}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | grep . | tail -n 1; }
health_last_exit() { docker inspect --format '{{range .State.Health.Log}}{{.ExitCode}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | grep . | tail -n 1; }

script_exit() { dc exec -T iris /opt/ocutalon/healthcheck.sh >/dev/null 2>&1; echo $?; }

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
keys=$(dc exec -T iris sh -c 'env | grep -c "^ANTHROPIC_API_KEY=\|^TELEGRAM_BOT_TOKEN="' 2>/dev/null | tr -d '\r')
if [ "$published" = 0 ] && [ "$keys" = 0 ]; then
  pass "throwaway container publishes no host port and receives no keys"
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
mkdir -p "$ctx/docker" "$ctx/src"
cp docker/Dockerfile docker/merge.cpf docker/healthcheck.sh "$ctx/docker/"
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

modes=$(dc exec -T iris sh -c 'stat -c "%n %u %a" /opt/ocutalon /opt/ocutalon/*' 2>/dev/null | tr -d '\r')
want_modes="/opt/ocutalon 0 755
/opt/ocutalon/healthcheck.sh 0 555
/opt/ocutalon/merge.cpf 0 444
/opt/ocutalon/module.xml 0 444
/opt/ocutalon/version 0 444"
if [ "$modes" = "$want_modes" ]; then
  pass "/opt/ocutalon and its files are root's and read-only, the health check executable"
else
  fail "/opt/ocutalon owners and modes are '$(echo $modes)', wanted '$(echo $want_modes)'"
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
