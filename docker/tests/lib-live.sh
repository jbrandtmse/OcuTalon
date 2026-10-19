# Helpers shared by the live tests (test-compose-start.sh, test-install-start.sh, test-install-upgrade.sh).
# Sourced, not run: it defines functions and nothing else. A live test calls live_start first.
#
# live_start <label> sets, for the caller:
#   P            a unique compose project name, ocutalon-<label>-<epoch>-<pid>
#   root, tmp    the repository root (the working directory) and a private temporary directory
#   base_image   the IRIS base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0)
#   mgr          the manager directory in the container
#   fails, cid   the failure count and the iris container's id
#   deadline     the second (of $SECONDS) at which every wait gives up, 540 s after the start
#   LIVE_FILES   the compose files of dc: the judges' file, a decoy key file and the throwaway override
#   LIVE_IMAGES  extra image ids or names that the cleanup removes
# and installs a cleanup trap that removes the project with its volume and images and the temporary directory.
# The project publishes no host port and receives no keys: the decoy key file is dropped by the override.

live_start() {
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  cd "$root" || exit 1
  P="ocutalon-$1-$(date +%s)-$$"
  base_image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
  mgr=/durable/iris/mgr
  fails=0
  cid=""
  deadline=$((SECONDS + 540))
  LIVE_IMAGES=()
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-live.XXXXXX") || exit 1

  # A key source that only compose.throwaway.yml's env_file reset keeps out of the container.
  printf 'ANTHROPIC_API_KEY=decoy\nTELEGRAM_BOT_TOKEN=decoy\n' > "$tmp/decoy.env"
  printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$tmp/decoy.env" > "$tmp/decoy.yml"
  LIVE_FILES=("$root/docker-compose.yml" "$tmp/decoy.yml" "$root/docker/tests/compose.throwaway.yml")

  trap live_cleanup EXIT
  trap 'exit 130' INT TERM HUP
}

# The tests' own compose files are added after the throwaway override.
live_add_file() { LIVE_FILES+=("$1"); }

dc() {
  local args=() f
  for f in "${LIVE_FILES[@]}"; do args+=(-f "$f"); done
  docker compose -p "$P" "${args[@]}" "$@"
}

# Records the image that the service's last build produced, so that the cleanup removes it
# even after a later build has taken its tag.
live_track_image() {
  local id
  id=$(docker image inspect --format '{{.Id}}' "$P-iris" 2>/dev/null)
  if [ -n "$id" ]; then LIVE_IMAGES+=("$id"); fi
}

live_cleanup() {
  dc down -v --rmi local >/dev/null 2>&1
  if [ "${#LIVE_IMAGES[@]}" -gt 0 ]; then docker image rm -f "${LIVE_IMAGES[@]}" >/dev/null 2>&1; fi
  rm -rf "$tmp"
}

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
die() { # a failure after which nothing else can run
  echo "FAIL $1"
  echo "$(basename "$0" .sh): aborted"
  exit 1
}

# wait_until <max seconds> <command...>: tries the command every 3 s until it succeeds, the time is up or
# the run's deadline has passed.
wait_until() {
  local waited=0 max=$1
  shift
  while [ "$waited" -lt "$max" ] && [ "$SECONDS" -lt "$deadline" ]; do
    if "$@"; then
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  return 1
}

# Error lines of process <pid>, from a messages.log excerpt on stdin: severity 2 or 3, or an `ERROR #`
# line of any severity (build 154 logs a failed merge action at severity 1).
merge_errors() { awk -v pid="($1)" '$2 == pid && ($3 == 2 || $3 == 3 || / ERROR #[0-9]/) { print }'; }

merge_count() { dc exec -T iris grep -c 'Merging /opt/ocutalon/merge.cpf' "$mgr/messages.log" 2>/dev/null | tr -d '\r'; }

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

# --- Docker's health monitor ---

health_status() { docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null; }
health_is_healthy() { [ "$(health_status)" = healthy ]; }
health_ends() { docker inspect --format '{{range .State.Health.Log}}{{.End}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | grep . | tail -n 1; }
health_last_exit() { docker inspect --format '{{range .State.Health.Log}}{{.ExitCode}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | grep . | tail -n 1; }
started_at() { docker inspect --format '{{.State.StartedAt}}' "$cid" 2>/dev/null; }
restart_count() { docker inspect --format '{{.RestartCount}}' "$cid" 2>/dev/null; }

script_exit() { dc exec -T iris /opt/ocutalon/healthcheck.sh >/dev/null 2>&1; echo $?; }

# The ready marker's content, or "" when there is none.
marker() { dc exec -T iris cat /durable/ocutalon.ready 2>/dev/null | tr -d '\r\n'; }

# --- the after-start log (/durable/ocutalon-after-start.log) ---

start_log() { dc exec -T iris cat /durable/ocutalon-after-start.log 2>/dev/null | tr -d '\r'; }

# This start's log is complete: its first line is the begin line of a script that started at or after the
# container's start time, and its last line is the end line. The script rewrites the log at every start, so a
# previous start's log never passes: its begin stamp is older than this container start.
start_log_complete() { # start_log_complete <container start stamp, UTC to the second>
  local ends begin
  ends=$(dc exec -T iris sed -n '1p;$p' /durable/ocutalon-after-start.log 2>/dev/null | tr -d '\r')
  begin=$(printf '%s\n' "$ends" | sed -n '1s/^AFTER-START begin \([0-9T:Z-]*\)$/\1/p')
  [ -n "$begin" ] || return 1
  [ "$(printf '%s\n' "$begin" "${1}Z" | sort | head -n 1)" = "${1}Z" ] || return 1
  printf '%s\n' "$ends" | tail -n 1 | grep -q '^AFTER-START end '
}

container_start_stamp() { started_at | cut -c1-19; }

# wait_started_log <max seconds>: waits for this start's log to end. Prints nothing; returns 1 on timeout.
wait_started_log() {
  local stamp
  stamp=$(container_start_stamp)
  [ -n "$stamp" ] || return 1
  wait_until "$1" start_log_complete "$stamp"
}

# wait_started_ready <max seconds>: waits for this start's log to end with `ready`, then for Docker to report
# `healthy`. Returns 1 when either does not happen in time, when the start ended `not ready`, or when the
# container started again in between.
wait_started_ready() {
  local before after
  before=$(started_at)
  wait_started_log "$1" || return 1
  start_log | tail -n 1 | grep -q '^AFTER-START end [0-9T:Z-]* ready ' || return 1
  wait_until 60 health_is_healthy || return 1
  after=$(started_at)
  [ "$before" = "$after" ]
}

# --- the build context ---

# The sources of the Dockerfile's COPY lines, as written (a trailing slash marks a directory).
dockerfile_copy_sources() { awk '$1 == "COPY" { for (i = 2; i < NF; i++) if ($i !~ /^--/) print $i }' docker/Dockerfile | sort; }

# The files that the Dockerfile's COPY lines name, a directory source expanded to its files, one per line.
copied_files() {
  local src
  dockerfile_copy_sources | while IFS= read -r src; do
    if [ -d "${src%/}" ]; then
      find "${src%/}" -type f
    else
      echo "$src"
    fi
  done | sort
}

# copy_build_context <dir>: the Dockerfile and the files that its COPY lines name, at their repository paths.
copy_build_context() {
  local dir=$1 f
  mkdir -p "$dir/docker"
  cp docker/Dockerfile "$dir/docker/Dockerfile"
  for f in $(copied_files); do
    mkdir -p "$dir/$(dirname "$f")"
    cp "$f" "$dir/$f"
  done
}

# --- IRIS session checks ---

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

# check_session <label> <namespace> <expected CHK lines> <script line>...
# Runs the script lines in the namespace of the running container and compares their CHK lines with the
# expected ones. The script comes as arguments, not on stdin, so that a failure is counted in the caller.
check_session() {
  local label=$1 ns=$2
  printf '%s\n' "$3" > "$tmp/expected.chk"
  printf '%s\n' "${@:4}" | iris_script "$ns" > "$tmp/actual.chk"
  compare_chk "$label" "$tmp/actual.chk" "$tmp/expected.chk"
}

# session_value <namespace> <name> < script: the value of the CHK|<name>| line that the script prints.
session_value() {
  iris_script "$1" | sed -n "s/^CHK|$2|//p" | head -n 1
}

# Data and private probes: a global in OCUTALON_DATA and one in OCUTALON_PRIVATE, to show that a restart,
# a start that reapplies the merge and an upgrade keep data and keep each global in its database.
set_probes() {
  local out
  out=$(printf '%s\n' \
    "Set ^OcuTalonS01Probe=\"probe-data-$P\",^OcuTalonP.S01Probe=\"probe-private-$P\"" \
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
CHK|probe-data|probe-data-$P
CHK|probe-private|probe-private-$P
CHK|probe-data-in-data-db|probe-data-$P
CHK|probe-private-in-private-db|probe-private-$P
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

# --- versions and the after-start log ---

# bump_patch <version> <n>: the version with its patch number raised by n.
bump_patch() { echo "$1" | awk -F. -v n="$2" '{ print $1 "." $2 "." ($3 + n) }'; }

# The image's version: the first <Version> of the manifest.
manifest_version() { sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "${1:-src/module.xml}" | head -n 1; }

# The after-start log reduced to what a test pins: the STEP and RESULT lines, without timings.
log_steps() { start_log | grep -E '^(STEP|RESULT) ' | sed 's/ OK [0-9.]*s$/ OK/'; }

# The lines of a complete run, in order: the lines before the registry's steps, the steps of the registry in
# the order AD-23 fixes (written out here, not read from the registry), and the result. The phase lines of the
# script are given as arguments: readiness, ipm, ipm-map, public-classes and package, then the version.
expected_run() { # expected_run <readiness> <ipm> <ipm-map> <public-classes> <package> <version>
  printf '%s\n' 'STEP merge OK' "STEP readiness $1" "STEP ipm $2" "STEP ipm-map $3" "STEP public-classes $4" "STEP package $5"
  printf '%s\n' 'STEP Bridge.Installer OK' 'STEP Public OK' 'STEP Roles OK' 'STEP Users OK' 'STEP Web OK' 'STEP SSL OK' \
    'STEP Tasks OK' 'STEP Demo OK' 'STEP Provider OK' 'STEP Audit OK' 'STEP Telegram OK' 'STEP Production OK' \
    'STEP Reconcile OK' 'STEP PrivateData OK' 'STEP Ready OK'
  printf '%s\n' "RESULT OK $6"
}

# check_log <label> <expected file>: the log's STEP and RESULT lines are exactly the expected ones, in order.
check_log() {
  local label=$1
  log_steps > "$tmp/actual.log"
  if diff "$2" "$tmp/actual.log" > "$tmp/log.diff" 2>&1; then
    pass "$label: the log lists every phase and step in order, ending in RESULT OK"
  else
    sed 's/^/  /' "$tmp/log.diff" | head -n 20
    fail "$label: the log differs from the expected phases and steps"
  fi
}

# live_pop_file removes the compose file that live_add_file added last.
live_pop_file() { unset 'LIVE_FILES[${#LIVE_FILES[@]}-1]'; }
