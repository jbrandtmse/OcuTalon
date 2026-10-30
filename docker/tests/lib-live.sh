# Helpers shared by the live tests (test-compose-start.sh, test-install-start.sh, test-install-upgrade.sh,
# test-sign-in.sh, test-floor.sh) and by the static tests that need the build context or the web bundle.
# Sourced, not run: it defines functions and nothing else. A live test calls live_start first.
#
# live_start <label> sets, for the caller:
#   P            a unique compose project name, ocutalon-<label>-<epoch>-<pid>, or ocutalon-<label>-<run tag>-<epoch>-<pid>
#                when OCUTALON_RUN_TAG is set (LIVE_TAG_RULE: lower-case letters, digits and hyphens, at least 3 characters,
#                no "slot"): ci/iris.sh finds and removes the projects of one run by that tag
#   root, tmp    the repository root (the working directory) and a private temporary directory
#   base_image   the IRIS base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0)
#   mgr          the manager directory in the container
#   fails, cid   the failure count and the iris container's id
#   deadline     the second (of $SECONDS) at which every wait gives up: OCUTALON_LIVE_DEADLINE seconds (default 540) after
#                the start, counted from the moment the throwaway lock is held
#   LIVE_FILES   the compose files of dc: the judges' file, a decoy key file, the throwaway override and the CI override
#   LIVE_IMAGES  extra image ids or names that the cleanup removes
# and installs a cleanup trap that removes the project with its volume and images, releases the throwaway lock and removes
# the temporary directory.
# The project receives no keys (the decoy key file is dropped by the override) and publishes no host port,
# unless a test that drives a browser calls live_web_port to publish the web port on 127.0.0.1 in 52800-52819. The only bot token
# in the container is the dummy of ci/compose.ci.yml, or the empty value that live_no_bot_token layers after it; neither is a key
# (live_key_count, check_no_key).
# live_start also makes sure that the web bundle (src/ocutalon/csp/) exists, because the image refuses to build
# without it: see ensure_web_bundle.
#
# live_fixture_user <name> <password> <roles> <full name>   (Story 2.14; test-sign-in.sh and test-floor.sh)
#                creates a user of OCUTALON whose password reaches IRIS by environment variable, so that it is never printed, and
#                prints the line CHK|fixture-user|1 when it was created (CHK|fixture-user|0 or nothing when it was not).
#
# The first start, timed (Story 0.8; AD-23). Only the demo-path unit uses these; the other live scripts keep their inline starts.
#   first_start_report <build s> <ready s> <engine>   prints "FIRST-START engine=<engine> build=<b>s ready=<r>s", and when
#                the ready time is over 720 s (12 minutes) also "WARN first start <r> s is over 12 minutes: raise it to the author (AD-23)"
#   live_first_start <max s>   builds the image (dc build, tracked for the cleanup), starts it without building (dc up -d --no-build),
#                sets cid, waits for a ready, healthy start (up to <max s> for the start's log to end ready, then up to 60 s for
#                Docker to report healthy; both end at the run's deadline), sets first_build_s (the build, which uses this
#                machine's layer cache) and first_ready_s (from the start until Docker reports healthy), and prints
#                first_start_report with the engine's architecture (docker info). Returns 1, saying which step failed and
#                after how many seconds, when one does.
#
# The throwaway lock (Rule 12) serializes throwaway stacks across the epic worktrees of one machine. It exists only when the
# main checkout has the folder <worktree_base>/.coordination/locks (worktree_base from _bmad/custom/parallel.yaml, default
# .worktrees); CI and a sequential run have none and take no lock. live_start claims throwaway-iris.lock there by an atomic
# create before anything starts, with the content "<OCUTALON_LOCK_OWNER, default epic=unknown stage=throwaway> project=<P>
# acquired_at=<UTC>", and prints "LOCK acquired". While another run holds it, it prints "LOCK waiting", tries again every 30 to
# 90 s for up to OCUTALON_LOCK_WAIT seconds (default 240), and then exits 75 with "LOCK busy" naming the holder. The cleanup
# deletes the lock only when its content is this run's, and prints "LOCK released"; a lock that another run took is kept.
# OCUTALON_LOCK_DIR replaces the folder, and OCUTALON_LOCK_SLEEP_MIN and OCUTALON_LOCK_SLEEP_MAX replace the 30 and 90 s.

# The rule of a run tag, shared with ci/iris.sh: at least 3 characters, so that the -<tag>- of a teardown cannot match a short
# word of a label such as the a of lane-a.
LIVE_TAG_RULE="must match [a-z0-9-]+, be at least 3 characters and not hold 'slot'"
live_tag_ok() { # live_tag_ok <tag>: 0 when the tag keeps LIVE_TAG_RULE
  case $1 in
    '' | *[!a-z0-9-]* | *slot*) return 1 ;;
  esac
  [ "${#1}" -ge 3 ]
}

live_start() {
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  cd "$root" || exit 1
  if [ -n "${OCUTALON_RUN_TAG:-}" ] && ! live_tag_ok "$OCUTALON_RUN_TAG"; then
    echo "FAIL OCUTALON_RUN_TAG '$OCUTALON_RUN_TAG' $LIVE_TAG_RULE"
    exit 2
  fi
  P="ocutalon-$1-${OCUTALON_RUN_TAG:+$OCUTALON_RUN_TAG-}$(date +%s)-$$"
  base_image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
  mgr=/durable/iris/mgr
  fails=0
  cid=""
  tmp=""
  LIVE_IMAGES=()
  LIVE_FILES=()
  LIVE_LOCK_FILE=""
  LIVE_LOCK_CONTENT=""

  live_lock_claim
  trap live_cleanup EXIT
  trap 'exit 130' INT TERM HUP
  deadline=$((SECONDS + ${OCUTALON_LIVE_DEADLINE:-540}))

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-live.XXXXXX") || exit 1

  # A key source that only compose.throwaway.yml's env_file reset keeps out of the container.
  printf 'ANTHROPIC_API_KEY=decoy\nTELEGRAM_BOT_TOKEN=decoy\n' > "$tmp/decoy.env"
  printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$tmp/decoy.env" > "$tmp/decoy.yml"
  LIVE_FILES=("$root/docker-compose.yml" "$tmp/decoy.yml" "$root/docker/tests/compose.throwaway.yml" "$root/ci/compose.ci.yml")

  ensure_web_bundle || exit 1
}

# --- the throwaway lock ---

# The folder of the coordination locks, or nothing when there is none. OCUTALON_LOCK_DIR replaces the derived folder.
live_lock_dir() {
  local common main base
  if [ -n "${OCUTALON_LOCK_DIR:-}" ]; then
    if [ -d "$OCUTALON_LOCK_DIR" ]; then printf '%s\n' "$OCUTALON_LOCK_DIR"; fi
    return 0
  fi
  common=$(cd "$root" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 0
  [ -n "$common" ] || return 0
  main=$(dirname "$common")
  base=$(sed -n 's/^worktree_base:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$root/_bmad/custom/parallel.yaml" 2>/dev/null | head -n 1)
  if [ -d "$main/${base:-.worktrees}/.coordination/locks" ]; then
    printf '%s\n' "$main/${base:-.worktrees}/.coordination/locks"
  fi
  return 0
}

# live_lock_claim: holds throwaway-iris.lock for project $P, or exits 75 when another run holds it for too long.
live_lock_claim() {
  local dir min max limit started pause
  dir=$(live_lock_dir)
  [ -n "$dir" ] || return 0
  min=${OCUTALON_LOCK_SLEEP_MIN:-30}
  max=${OCUTALON_LOCK_SLEEP_MAX:-90}
  limit=${OCUTALON_LOCK_WAIT:-240}
  started=$SECONDS
  LIVE_LOCK_FILE="$dir/throwaway-iris.lock"
  while :; do
    # acquired_at is the time of this try, so that a lock taken after a wait does not look older than it is.
    LIVE_LOCK_CONTENT="${OCUTALON_LOCK_OWNER:-epic=unknown stage=throwaway} project=$P acquired_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if (set -C; printf '%s\n' "$LIVE_LOCK_CONTENT" > "$LIVE_LOCK_FILE") 2>/dev/null; then
      echo "LOCK acquired throwaway-iris project=$P"
      return 0
    fi
    if [ $((SECONDS - started)) -ge "$limit" ]; then
      echo "LOCK busy: throwaway-iris is held by '$(cat "$LIVE_LOCK_FILE" 2>/dev/null)' after $((SECONDS - started)) s"
      LIVE_LOCK_FILE=""
      exit 75
    fi
    echo "LOCK waiting: throwaway-iris is held by '$(cat "$LIVE_LOCK_FILE" 2>/dev/null)'"
    pause=$((min + RANDOM % (max - min + 1)))
    if [ "$pause" -gt $((limit - (SECONDS - started))) ]; then pause=$((limit - (SECONDS - started))); fi
    if [ "$pause" -gt 0 ]; then sleep "$pause"; fi
  done
}

# live_lock_release: deletes the lock when its content is this run's, and only then.
live_lock_release() {
  [ -n "${LIVE_LOCK_FILE:-}" ] || return 0
  if [ "$(cat "$LIVE_LOCK_FILE" 2>/dev/null)" = "$LIVE_LOCK_CONTENT" ]; then
    rm -f "$LIVE_LOCK_FILE"
    echo "LOCK released throwaway-iris project=$P"
  else
    echo "LOCK kept: throwaway-iris is not held by project $P"
  fi
  LIVE_LOCK_FILE=""
}

# The tests' own compose files are added after the throwaway override.
live_add_file() { LIVE_FILES+=("$1"); }

# --- the web bundle ---

# The image copies src/ocutalon/csp/, the Angular bundle that npm --prefix web run build writes (ignored by git on
# development branches). ensure_web_bundle installs the web dependencies when web/node_modules is missing and builds
# the bundle when src/ocutalon/csp/index.html is missing, or always when LIVE_REBUILD_WEB is 1. It needs Node only
# when it has to run npm, and then says so.
ensure_web_bundle() {
  local rebuild=${LIVE_REBUILD_WEB:-0}
  if [ -d web/node_modules ] && [ -f src/ocutalon/csp/index.html ] && [ "$rebuild" != 1 ]; then
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "FAIL web bundle: node and npm are not installed, and the bundle must be built (Node 24.15 or later, then npm --prefix web ci and npm --prefix web run build)"
    return 1
  fi
  if [ ! -d web/node_modules ]; then
    if ! npm --prefix web ci --no-audit --no-fund > "${TMPDIR:-/tmp}/ocutalon-npm-ci.$$.log" 2>&1; then
      tail -n 15 "${TMPDIR:-/tmp}/ocutalon-npm-ci.$$.log"
      rm -f "${TMPDIR:-/tmp}/ocutalon-npm-ci.$$.log"
      echo "FAIL web bundle: npm --prefix web ci failed"
      return 1
    fi
    rm -f "${TMPDIR:-/tmp}/ocutalon-npm-ci.$$.log"
  fi
  if [ ! -f src/ocutalon/csp/index.html ] || [ "$rebuild" = 1 ]; then
    if ! npm --prefix web run build > "${TMPDIR:-/tmp}/ocutalon-npm-build.$$.log" 2>&1; then
      tail -n 15 "${TMPDIR:-/tmp}/ocutalon-npm-build.$$.log"
      rm -f "${TMPDIR:-/tmp}/ocutalon-npm-build.$$.log"
      echo "FAIL web bundle: npm --prefix web run build failed"
      return 1
    fi
    rm -f "${TMPDIR:-/tmp}/ocutalon-npm-build.$$.log"
  fi
  return 0
}

# --- the published web port ---

# The ports that no test may publish: the judges' default, and the ports of the other instances and slots.
LIVE_FORBIDDEN_PORTS="52773 1979 52779 8089 1990 1991 52790 52791 8090 8091"

# 0 when something listens on 127.0.0.1:<port>.
port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# live_web_port: publishes the project's web port on 127.0.0.1 only. The port is OCUTALON_TEST_WEB_PORT when set,
# otherwise the first port of 52800-52819 that nothing listens on. Sets web_port, and adds an override file
# (ports: ["127.0.0.1:<port>:52773"]) after the other compose files. Returns 1, saying why, when the port is
# outside 52800-52819, in use or forbidden, or no port is free.
live_web_port() {
  local port="" candidate forbidden
  if [ -n "${OCUTALON_TEST_WEB_PORT:-}" ]; then
    port=$OCUTALON_TEST_WEB_PORT
    case $port in
      '' | *[!0-9]*)
        echo "FAIL live_web_port: OCUTALON_TEST_WEB_PORT '$port' is not a port number"
        return 1
        ;;
    esac
    for forbidden in $LIVE_FORBIDDEN_PORTS; do
      if [ "$port" = "$forbidden" ]; then
        echo "FAIL live_web_port: port $port belongs to the judges' stack, a slot or another instance; use 52800-52819"
        return 1
      fi
    done
    port=$((10#$port))
    if [ "$port" -lt 52800 ] || [ "$port" -gt 52819 ]; then
      echo "FAIL live_web_port: OCUTALON_TEST_WEB_PORT $port is outside 52800-52819"
      return 1
    fi
    if port_in_use "$port"; then
      echo "FAIL live_web_port: port $port is in use on 127.0.0.1"
      return 1
    fi
  else
    for candidate in $(seq 52800 52819); do
      if ! port_in_use "$candidate"; then
        port=$candidate
        break
      fi
    done
    if [ -z "$port" ]; then
      echo "FAIL live_web_port: ports 52800-52819 are all in use on 127.0.0.1; free one, or set OCUTALON_TEST_WEB_PORT"
      return 1
    fi
  fi
  web_port=$port
  printf 'services:\n  iris:\n    ports:\n      - "127.0.0.1:%s:52773"\n' "$port" > "$tmp/port.yml"
  live_add_file "$tmp/port.yml"
}

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

# first_start_report <build s> <ready s> <engine>: see the header.
first_start_report() {
  echo "FIRST-START engine=$3 build=${1}s ready=${2}s"
  if [ "$2" -gt 720 ]; then
    echo "WARN first start $2 s is over 12 minutes: raise it to the author (AD-23)"
  fi
}

live_cleanup() {
  # An exit between the lock claim and the compose files has no stack to remove, and `dc` cannot expand an empty file list.
  if [ "${#LIVE_FILES[@]}" -gt 0 ]; then dc down -v --rmi local >/dev/null 2>&1; fi
  if [ "${#LIVE_IMAGES[@]}" -gt 0 ]; then docker image rm -f "${LIVE_IMAGES[@]}" >/dev/null 2>&1; fi
  live_lock_release
  if [ -n "${tmp:-}" ]; then rm -rf "$tmp"; fi
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

# live_fixture_user <name> <password> <roles> <full name>: see the header. The user is created in %SYS, for the namespace OCUTALON.
live_fixture_user() {
  printf '%s\n' \
    'Set pw=$SYSTEM.Util.GetEnviron("OCUTALON_T03_PW")' \
    "Set sc=##class(Security.Users).Create(\"$1\",\"$3\",pw,\"$4\",\"OCUTALON\",\"\",\"\",0,1,\"t03 fixture\",1,\"\",\"\",,1,1)" \
    'Write !,"CHK|fixture-user|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' \
    | OCUTALON_T03_PW="$2" dc exec -T -e OCUTALON_T03_PW iris iris session IRIS -U %SYS 2>/dev/null | tr -d '\r' | sed -n 's/.*\(CHK|fixture-user|.*\)$/\1/p' | tail -n 1
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

# live_first_start <max s>: see the header. Needs live_start. The ready time starts when the built image is started and ends
# when this start's log ends `ready` and Docker reports `healthy`, which needs the after-start install and the ready marker.
live_first_start() {
  local max=$1 begun=$SECONDS up_at engine
  if ! dc build > "$tmp/first-build.log" 2>&1; then
    tail -n 30 "$tmp/first-build.log"
    echo "first start: the image build failed after $((SECONDS - begun)) s"
    return 1
  fi
  live_track_image
  first_build_s=$((SECONDS - begun))
  if ! docker image inspect --format '{{.Id}}' "$P-iris" >/dev/null 2>&1; then
    echo "first start: the build left no image $P-iris after $((SECONDS - begun)) s, so the start would build it again"
    return 1
  fi
  up_at=$SECONDS
  if ! dc up -d --no-build > "$tmp/first-up.log" 2>&1; then
    tail -n 30 "$tmp/first-up.log"
    echo "first start: docker compose up failed after $((SECONDS - up_at)) s"
    return 1
  fi
  cid=$(dc ps -q iris)
  if [ -z "$cid" ]; then
    echo "first start: no iris container in project $P after $((SECONDS - up_at)) s"
    return 1
  fi
  if ! wait_started_ready "$max"; then
    echo "first start: not ready after waiting $((SECONDS - up_at)) s (the log is waited for at most $max s and the health for 60 s more, both until the run's deadline)"
    return 1
  fi
  first_ready_s=$((SECONDS - up_at))
  engine=$(docker info --format '{{.Architecture}}' 2>/dev/null)
  first_start_report "$first_build_s" "$first_ready_s" "${engine:-unknown}"
}

# container_sha256 <path>: the SHA-256 of a file in the iris container, or "" when it is missing.
container_sha256() { dc exec -T iris sha256sum "$1" 2>/dev/null | tr -d '\r' | cut -d' ' -f1; }

# container_tree_hashes <dir>: the SHA-256 and relative path of every file below a directory of the iris container,
# sorted by path, one per line.
container_tree_hashes() { dc exec -T iris sh -c "cd '$1' && find . -type f | sort | xargs sha256sum" 2>/dev/null | tr -d '\r'; }

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

# security_app_props <CSPZENEnabled> <CookiePath> <DispatchClass> <MatchRoles> <Path> <PermittedClasses> <ServeFiles>
# [<AutheEnabled> [<GroupById> [<NameSpace> [<EventClass>]]]]: the properties string that check_security reads back for a web
# application, in the order of its key list; the values every application shares are written here. AutheEnabled defaults to 32
# (password), GroupById to OcuTalon, the sign-in group, NameSpace to OCUTALON and EventClass to none (only /ocutalon has one).
security_app_props() {
  printf 'AutheEnabled=%s;AutoCompile=0;CSPZENEnabled=%s;CookiePath=%s;CorsAllowlist=;DispatchClass=%s;Enabled=1;EventClass=%s;GroupById=%s;InbndWebServicesEnabled=0;IsNameSpaceDefault=0;LoginPage=;MatchRoles=%s;NameSpace=%s;Path=%s;PermittedClasses=%s;ServeFiles=%s;SessionScope=2;Timeout=28800;' \
    "${8:-32}" "$1" "$2" "$3" "${11-}" "${9-OcuTalon}" "$4" "${10:-OCUTALON}" "$5" "$6" "$7"
}

# check_security <label>: Story 0.3's matrix rows 1 and 2 on the running container, from the security tables.
#   - OcuTalonUser and OcuTalonAdmin hold no resource; OcuTalonTraceViewer holds exactly Use on four Ens resources and
#     Read on the OCUTALON and OCUORDERS data and code databases, and SQL SELECT on Ens.MessageHeader in OCUTALON and in
#     OCUORDERS (the Demo step's, Story 0.10: the check assumes demo mode on);
#   - user ocutalon holds the three roles, with a password that never expires, no forced change and an account that
#     never expires, enabled; InvalidLoginAction is 0;
#   - the four web applications have exactly the properties of the Web step, the OCUORDERS trace application has the
#     same properties as OCUTALON's in its own namespace, and no application has a CORS list. The bundle folder is the
#     durable csp/ocutalon-web/ (DW-5), and /ocutalon/public is outside the sign-in group, with no password.
check_security() {
  local label=$1 permitted shell_props api_props public_props trace_props orders_props
  permitted='1(1"%CSP.Broker",1"EnsPortal.VisualTrace",1"EnsPortal.SVG.VisualTrace",1"EnsPortal.VisualTraceLegend",1"EnsPortal.SVG.TraceLegend",1"EnsPortal.MessageContents",1"EnsPortal.MessageViewer")'
  shell_props=$(security_app_props 1 /ocutalon/ OcuTalon.Web.Public.Shell ':%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE' /durable/iris/csp/ocutalon-web/ '' 3 32 OcuTalon OCUTALON OcuTalon.Web.SessionEvents)
  api_props=$(security_app_props 1 /ocutalon/ OcuTalon.Web.Api ':%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE' '' '' 0)
  public_props=$(security_app_props 1 /ocutalon/public/ OcuTalon.Web.Public.Status '' '' '' 0 64 '')
  trace_props=$(security_app_props 1 /ocutalon/trace/ocutalon/ '' '' '' "$permitted" 1)
  orders_props=$(security_app_props 1 /ocutalon/trace/ocuorders/ '' '' '' "$permitted" 1 32 OcuTalon OCUORDERS)
  check_session "$label: roles, README account, sign-in policy and applications" %SYS \
    "CHK|role-OcuTalonUser|
CHK|role-OcuTalonAdmin|
CHK|role-OcuTalonTraceViewer|%DB_OCUORDERS_CODE:R,%DB_OCUORDERS_DATA:R,%DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:R,%Ens_MessageContent:U,%Ens_MessageHeader:U,%Ens_MessageTrace:U,%Ens_Portal:U
CHK|trace-sql-select|1
CHK|trace-sql-select-orders|1
CHK|user|OcuTalonAdmin,OcuTalonTraceViewer,OcuTalonUser|1|0|1|1
CHK|invalid-login-action|0
CHK|app|/ocutalon|$shell_props
CHK|app|/ocutalon/api|$api_props
CHK|app|/ocutalon/public|$public_props
CHK|app|/ocutalon/trace/ocutalon|$trace_props
CHK|app|/ocutalon/trace/ocuorders|$orders_props" \
    'For r="OcuTalonUser","OcuTalonAdmin","OcuTalonTraceViewer" { Set sc=##class(Security.Roles).Get(r,.p) Write !,"CHK|role-",r,"|",$Select($SYSTEM.Status.IsOK(sc):$Get(p("Resources")),1:"<missing>") }' \
    'Write !,"CHK|trace-sql-select|",$SYSTEM.SQL.Security.CheckPrivilege("OcuTalonTraceViewer",1,"Ens.MessageHeader","s","OCUTALON")' \
    'Write !,"CHK|trace-sql-select-orders|",$SYSTEM.SQL.Security.CheckPrivilege("OcuTalonTraceViewer",1,"Ens.MessageHeader","s","OCUORDERS")' \
    'If ##class(Security.Users).Exists("ocutalon",.u) { Set rl="" For i=1:1:u.Roles.Count() { Set rl=rl_$Select(rl="":"",1:",")_u.Roles.GetAt(i) } Write !,"CHK|user|",rl,"|",u.Enabled,"|",u.ChangePassword,"|",u.PasswordNeverExpires,"|",u.AccountNeverExpires } Else { Write !,"CHK|user|<missing>" }' \
    'Set sc=##class(Security.System).Get("SYSTEM",.sp) Write !,"CHK|invalid-login-action|",$Get(sp("InvalidLoginAction"))' \
    'Set keys=$ListBuild("AutheEnabled","AutoCompile","CSPZENEnabled","CookiePath","CorsAllowlist","DispatchClass","Enabled","EventClass","GroupById","InbndWebServicesEnabled","IsNameSpaceDefault","LoginPage","MatchRoles","NameSpace","Path","PermittedClasses","ServeFiles","SessionScope","Timeout")' \
    'For app="/ocutalon","/ocutalon/api","/ocutalon/public","/ocutalon/trace/ocutalon","/ocutalon/trace/ocuorders" { Kill p Set sc=##class(Security.Applications).Get(app,.p) Set out="" For k=1:1:$ListLength(keys) { Set key=$List(keys,k) Set out=out_key_"="_$Get(p(key))_";" } Write !,"CHK|app|",app,"|",$Select($SYSTEM.Status.IsOK(sc):out,1:"<missing>") }' \
    'Halt'
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

# live_no_bot_token: adds the compose file that leaves TELEGRAM_BOT_TOKEN set and empty in the iris service, which is what a
# .env copied from .env.example holds: the CI override's other settings (the mock, the endpoint overrides) stay, so a start under
# it shows every other feature working with no bot token. The file is added last, after the CI override; live_pop_file removes it.
live_no_bot_token() {
  printf '%s\n' 'services:' '  iris:' '    environment:' '      TELEGRAM_BOT_TOKEN: ""' > "$tmp/no-bot-token.yml"
  live_add_file "$tmp/no-bot-token.yml"
}

# --- the production's items (Story 0.6) ---

# item_jobs <file> [<namespace>]: the alive jobs of the running production of the namespace (default OCUTALON), one line per item
# that has any: the item's name, a tab and its job ids, comma-separated and in the order the production lists them.
item_jobs() {
  printf '%s\n' \
    'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Set sc=rs.Execute() While rs.Next() { If rs.Get("State")="Alive" { Set j(rs.Get("ConfigName"))=$Get(j(rs.Get("ConfigName")))_","_rs.Get("Job") } }' \
    'Set n="" For { Set n=$Order(j(n)) Quit:n=""  Write !,"CHK|job|",n,"|",$Extract(j(n),2,*) }' \
    'Halt' | iris_script "${2:-OCUTALON}" | awk -F'|' '$1 == "CHK" && $2 == "job" { print $3 "\t" $4 }' | sort > "$1"
}

# check_items_run <label>: the job check of Story 0.6 (matrix row 14) on the running container, against the list of items in
# OcuTalon.Test.Install.Production (Items):
#   - each enabled item with a pool has an Alive job whose status is not error, halted or terminated;
#   - each enabled adapterless service has no job, and CreateBusinessService succeeds for it;
#   - each item the definition disables has no job.
# The items and their kinds come from the oracle, which each lane keeps for its own items, so no count is written here;
# the check fails when the oracle names no item with a pool, or when the three kinds do not add up to the oracle.
check_items_run() {
  check_session "$1: every enabled item runs, the adapterless services answer, the disabled items have no job" OCUTALON \
    "CHK|pooled|missing=
CHK|adapterless|failing=
CHK|disabled|running=
CHK|scanned|1" \
    'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Set sc=rs.Execute() While rs.Next() { Set any(rs.Get("ConfigName"))=1 If rs.Get("State")="Alive",$ListFind($ListFromString("error,halted,terminated"),rs.Get("Status"))=0 { Set alive(rs.Get("ConfigName"))=1 } }' \
    'Set (np,ns,nd)=0,(mp,ms,md)="" Set items=##class(OcuTalon.Test.Install.Production).Items(),it=items.%GetIterator()' \
    'While it.%GetNext(,.x) { Set n=x.name If x.enabled=0 { Set nd=nd+1 If $Data(any(n)) { Set md=md_" "_n } } ElseIf x.pool { Set np=np+1 If $Data(alive(n))=0 { Set mp=mp_" "_n } } Else { Set ns=ns+1 Set sc=##class(Ens.Director).CreateBusinessService(n,.svc) If $SYSTEM.Status.IsError(sc)||$Data(any(n)) { Set ms=ms_" "_n } } }' \
    'Write !,"CHK|pooled|missing=",$ZStrip(mp,"<W")' \
    'Write !,"CHK|adapterless|failing=",$ZStrip(ms,"<W")' \
    'Write !,"CHK|disabled|running=",$ZStrip(md,"<W")' \
    'Write !,"CHK|scanned|",((np>0)&&((np+ns+nd)=items.%Size())),!,"CHK|counts|",np,"|",ns,"|",nd' \
    'Halt'
}

# live_ci_bot_token: the dummy bot token that ci/compose.ci.yml gives the iris service, read from that file (the one place that holds it),
# or nothing when the file sets none.
live_ci_bot_token() {
  awk '/^      TELEGRAM_BOT_TOKEN:/ { print $2; exit }' "$root/ci/compose.ci.yml" 2>/dev/null
}

# live_key_count: how many key variables the iris container's environment holds: ANTHROPIC_API_KEY, and TELEGRAM_BOT_TOKEN when it is
# not empty and is not exactly the CI dummy (live_ci_bot_token), which the CI override sets so that the Telegram service can call the
# mock. An empty token holds no secret and counts 0 (live_no_bot_token sets one). The dummy is compared inside the container, and only
# the count is printed.
live_key_count() {
  # shellcheck disable=SC2016 # the script is the container shell's, which expands its own variables
  dc exec -T iris env CHECK_DUMMY="$(live_ci_bot_token)" sh -c 'n=0
    if [ -n "${ANTHROPIC_API_KEY+x}" ]; then n=$((n + 1)); fi
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
      if [ -z "$CHECK_DUMMY" ] || [ "$TELEGRAM_BOT_TOKEN" != "$CHECK_DUMMY" ]; then n=$((n + 1)); fi
    fi
    echo "$n"' 2>/dev/null | tr -d '\r'
}

# check_no_key <label>: the iris container's environment holds no model key and no bot token but the CI dummy (an empty token is no
# token). A start that succeeds in it is a start with no key (FR-38, AD-6); with a key in the environment it would prove nothing. Only a
# count is printed.
check_no_key() {
  local n
  n=$(live_key_count)
  if [ "$n" = 0 ]; then
    pass "$1: the container holds no model key and no bot token but the CI dummy"
  else
    fail "$1: the container holds '$n' key variable(s), so a start in it is not a start with no key"
  fi
}

# check_clean_start <label>: the event log holds no error and no alert (Type 2 or 6). Call it right after a start and before
# any check that makes a host or a director call fail on purpose, because those write error rows.
check_clean_start() {
  check_session "$1: the start wrote no error and no alert to the event log" OCUTALON \
    "CHK|errors|0" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE Type IN (2,6)") Do rs.%Next() Write !,"CHK|errors|",rs.%GetData(1)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 3 ConfigName,SUBSTRING(Text,1,120) FROM Ens_Util.Log WHERE Type IN (2,6) ORDER BY ID") While rs.%Next() { Write !,"CHK|row|",rs.%GetData(1),"|",rs.%GetData(2) }' \
    'Halt'
  grep -qx 'CHK|errors|0' "$tmp/actual.chk" || sed -n 's/^CHK|row|/  event log: /p' "$tmp/actual.chk"
}

# --- a stop right after a start (DW-28) ---

# A production's start returns before Ens.ScheduleHandler has taken the start's request, and the handler's UpdateProduction
# then waits for the runtime lock that StopProduction holds until its own timeout, so a stop right after a start fails with
# ErrProductionNotQuiescent or ErrJobsNotStopped (DW-28, measured on build 154). settle_scheduler is an ObjectScript line, for
# check_session and iris_script, that ends once the handler's queue is empty and its job is Alive, dequeuing and has no active
# message, or after 10 s, and sets settled to 1 or 0. It runs in the namespace of the production that is about to be stopped.
settle_scheduler='For k=1:1:100 { Set busy=(##class(Ens.Queue).GetCount("Ens.ScheduleHandler")>0),seen=0,rs=##class(%ResultSet).%New("Ens.Job:Enumerate"),x=rs.Execute() While rs.Next() { If rs.Get("ConfigName")="Ens.ScheduleHandler" { Set seen=1 Set:((rs.Get("State")="Alive")&&(rs.Get("Status")="dequeuing")&&(rs.Get("ActiveMessage")=""))=0 busy=1 } } Quit:seen&&(busy=0)  Hang 0.1 } Set settled=(seen&&(busy=0))'

# --- demo mode and the surfaces of the Demo step (Story 0.10) ---

# set_demo_mode <0|1>: writes the demo.mode row in OCUTALON through Data.Setting's object API, with UpdatedAt from Data.Time, so
# that the next start's Demo step reads the value. A test-only writer: the product's writer is SettingsOps (Story 4.1). Passes on
# CHK|demo-mode|1, the status of the save.
set_demo_mode() {
  local out
  out=$(printf '%s\n' \
    'Set row=##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode") If $IsObject(row)=0 { Set row=##class(OcuTalon.Data.Setting).%New() Set row.Key="demo.mode" }' \
    "Set row.Value=\"$1\",row.UpdatedAt=##class(OcuTalon.Data.Time).NowUtc()" \
    'Write !,"CHK|demo-mode|",row.%Save()' \
    'Halt' | iris_script OCUTALON)
  if [ "$out" = "CHK|demo-mode|1" ]; then
    pass "demo.mode set to $1"
  else
    fail "demo.mode could not be set to $1 (got '$out')"
  fi
}

# demo_surfaces <file> [--wide]: writes the sorted surfaces that the Demo step creates or could leave behind, read in %SYS, one
# line each:
#   ns|<name>|<globals>|<routines>          db|<name>|<directory>              res|<name>|<public permission>
#   role|<name>                             roleres|<role>|<resource:permission>
#   app|<name>|<namespace>|<AutheEnabled>   userrole|<user>|<role>
#   sqlpriv|<namespace>|<object>|<privilege>|<grantee>
#   map|<namespace>|pkg|<name>|<database>   map|<namespace>|glo|<name>|<database>   (every namespace)
#   ens|<namespace>, ensrun|<namespace>     from ^%SYS("Ensemble","InstalledNamespace" and "RunningNamespace")
#   hs|<namespace>                          from ^%SYS("HealthShare","Instances")
#   dir|<entry>                             the folders below the manager directory whose name starts with ocu (any case)
#   cspdir|<entry>                          two levels below <data>csp/, the entries that start with ocu
# --wide (the Task 0 measurements only) lists every folder below the manager directory and below <data>csp/, and adds
# cpf|<line> for the lines of the [Namespaces], [Databases] and [Map.*] sections of the instance's CPF file. The folder lines are
# limited to ocu* otherwise, so that the folders IRIS itself creates and removes cannot make a comparison flaky.
demo_surfaces() {
  local file=$1 wide=0
  if [ "${2:-}" = --wide ]; then wide=1; fi
  printf '%s\n' \
    'Set wide='"$wide"',mgr=$SYSTEM.Util.ManagerDirectory(),dat=$SYSTEM.Util.DataDirectory()' \
    'Set rs=##class(%ResultSet).%New("Config.Namespaces:List") Do rs.Execute() While rs.Next() { Write !,"CHK|ns|",rs.Get("Namespace"),"|",rs.Get("Globals"),"|",rs.Get("Routines") Set nsl(rs.Get("Namespace"))="" }' \
    'Set rs=##class(%ResultSet).%New("Config.Databases:List") Do rs.Execute() While rs.Next() { Write !,"CHK|db|",rs.Get("Name"),"|",rs.Get("Directory") }' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name,PublicPermission FROM Security.Resources") While rs.%Next() { Write !,"CHK|res|",rs.%Get("Name"),"|",rs.%Get("PublicPermission") }' \
    'Set rs=##class(%ResultSet).%New("Security.Roles:ListAll") Do rs.Execute("*") While rs.Next() { Set r=rs.Get("Name") Write !,"CHK|role|",r Kill p Set sc=##class(Security.Roles).Get(r,.p) Set rr=$Get(p("Resources")) For i=1:1:$Length(rr,",") { If $Length($Piece(rr,",",i))>0 { Write !,"CHK|roleres|",r,"|",$Piece(rr,",",i) } } }' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name,NameSpace,AutheEnabled FROM Security.Applications") While rs.%Next() { Write !,"CHK|app|",rs.%Get("Name"),"|",rs.%Get("NameSpace"),"|",rs.%Get("AutheEnabled") }' \
    'Set rs=##class(%ResultSet).%New("Security.Users:List") Do rs.Execute("*") While rs.Next() { Set ur=rs.Get("Roles") For i=1:1:$Length(ur,",") { If $Length($Piece(ur,",",i))>0 { Write !,"CHK|userrole|",rs.Get("Name"),"|",$Piece(ur,",",i) } } }' \
    'Set rs=##class(%ResultSet).%New("Security.SQLPrivileges:List") Do rs.Execute() While rs.Next() { Write !,"CHK|sqlpriv|",rs.Get("Namespace"),"|",rs.Get("SQLObject"),"|",rs.Get("Privilege"),"|",rs.Get("Grantee") }' \
    'Set n="" For { Set n=$Order(nsl(n)) Quit:n=""  Set rs=##class(%ResultSet).%New("Config.MapPackages:List") Do rs.Execute(n) While rs.Next() { Write !,"CHK|map|",n,"|pkg|",rs.Get("Name"),"|",rs.Get("Database") } Set rs=##class(%ResultSet).%New("Config.MapGlobals:List") Do rs.Execute(n) While rs.Next() { Write !,"CHK|map|",n,"|glo|",rs.Get("Name"),"|",rs.Get("Database") } }' \
    'Set k="" For { Set k=$Order(^%SYS("Ensemble","InstalledNamespace",k)) Quit:k=""  Write !,"CHK|ens|",k }' \
    'Set k="" For { Set k=$Order(^%SYS("Ensemble","RunningNamespace",k)) Quit:k=""  Write !,"CHK|ensrun|",k }' \
    'Set k="" For { Set k=$Order(^%SYS("HealthShare","Instances",k)) Quit:k=""  Write !,"CHK|hs|",k }' \
    'Set rs=##class(%ResultSet).%New("%File:FileSet") Do rs.Execute(mgr,"*","Name",1) While rs.Next() { Set e=##class(%File).GetFilename(rs.Get("Name")) If rs.Get("Type")="D" { If (wide=1)||($ZConvert($Extract(e,1,3),"L")="ocu") Write !,"CHK|dir|",e } }' \
    'Set rs=##class(%ResultSet).%New("%File:FileSet") Do rs.Execute(dat_"csp/","*","Name",1) While rs.Next() { Set e=##class(%File).GetFilename(rs.Get("Name")) If rs.Get("Type")="D" { If (wide=1)||($ZConvert($Extract(e,1,3),"L")="ocu") { Write !,"CHK|cspdir|",e } Set r2=##class(%ResultSet).%New("%File:FileSet") Do r2.Execute(rs.Get("Name"),"*","Name",1) While r2.Next() { Set e2=##class(%File).GetFilename(r2.Get("Name")) If r2.Get("Type")="D" { If (wide=1)||($ZConvert($Extract(e2,1,3),"L")="ocu") Write !,"CHK|cspdir|",e,"/",e2 } } } }' \
    'If wide=1 { Set stream=##class(%Stream.FileCharacter).%New() Set sc=stream.LinkToFile($Piece($ZU(86),"*",1)) Set sec="" While stream.AtEnd=0 { Set l=stream.ReadLine() If $Extract(l)="[" { Set sec=l } If (sec="[Namespaces]")||(sec="[Databases]")||($Extract(sec,1,5)="[Map.") { Write !,"CHK|cpf|",l } } }' \
    'Halt' | iris_script %SYS | sed 's/^CHK|//' | LC_ALL=C sort > "$file"
}

# compare_surfaces <label> <expected file> <actual file> [--drop-orders]: the two demo_surfaces files are equal. With
# --drop-orders every line that names ocuorders (any case) is removed from the expected file first, and the actual file must hold
# no such line: the surfaces of a start without OCUORDERS equal those of a start with it, less what OCUORDERS owns.
compare_surfaces() {
  local label=$1 expected=$2 actual=$3 drop=${4:-} want="$tmp/surfaces.want" left
  if [ -n "$drop" ] && [ "$drop" != --drop-orders ]; then
    fail "$label: compare_surfaces does not know '$drop'"
    return 1
  fi
  if [ ! -s "$expected" ] || [ ! -s "$actual" ]; then
    fail "$label: a surfaces file is empty (the IRIS session printed nothing)"
    return 1
  fi
  if [ "$drop" = --drop-orders ]; then
    grep -vi 'ocuorders' "$expected" > "$want"
    left=$(grep -ci 'ocuorders' "$actual")
    if [ "$left" -gt 0 ]; then
      grep -i 'ocuorders' "$actual" | head -n 10 | sed 's/^/  left behind: /'
      fail "$label: $left surface line(s) still name OCUORDERS"
      return 1
    fi
  else
    cp "$expected" "$want"
  fi
  if diff "$want" "$actual" > "$tmp/surfaces.diff" 2>&1; then
    pass "$label ($(wc -l < "$actual" | tr -d ' ') surface lines equal)"
  else
    sed 's/^/  /' "$tmp/surfaces.diff" | head -n 20
    fail "$label: the surfaces differ ($(grep -c '^[<>]' "$tmp/surfaces.diff") lines)"
  fi
}

# check_orders_jobs <label>: OrdersFromPartner and OrdersToWarehouse each have an alive job in OCUORDERS, and the adapterless
# PartnerOrdersIn has none. The jobs of the system items of Interoperability (Ens.*) are not the production's.
check_orders_jobs() {
  local label=$1 names
  item_jobs "$tmp/orders.jobs" OCUORDERS
  names=$(awk -F'\t' '$1 !~ /^Ens\./ { print $1 }' "$tmp/orders.jobs" | sort | tr '\n' ' ')
  if [ "$names" = 'OrdersFromPartner OrdersToWarehouse ' ]; then
    pass "$label: OrdersFromPartner and OrdersToWarehouse have an alive job, and PartnerOrdersIn has none"
  else
    fail "$label: the alive jobs of the Orders production are '$names', not OrdersFromPartner and OrdersToWarehouse"
  fi
}

# check_demo_on <label>: Story 0.10's row 1 on the running container, after a start with demo mode on:
#   - demo.mode is 1 and the Demo step owns OCUORDERS;
#   - the namespace OCUORDERS has the globals database OCUORDERS_DATA and the routines database OCUORDERS_CODE, at
#     <mgr>/ocuorders_data/ and <mgr>/ocuorders_code/, whose resources %DB_OCUORDERS_CODE and %DB_OCUORDERS_DATA give no
#     public permission;
#   - in OCUORDERS, OcuTalon.Demo.Orders resolves to OCUTALON_CODE, OcuTalon.Web.Public, OcuTalon.Data.Public and the global
#     ^OcuTalonPublic resolve to OCUTALON_PUBLIC;
#   - Interoperability is enabled, and no HealthShare mapping or instance marker exists for OCUORDERS;
#   - the Orders production runs with OrdersFromPartner and OrdersToWarehouse alive, and OCUORDERS has no autostart production;
#   - /ocutalon/trace/ocuorders has the properties of the trace application, the Interoperability portal application of the
#     namespace (/csp/ocuorders) asks for a password (AutheEnabled 32), and the trace role holds Read on the OCUORDERS
#     databases and SQL SELECT on Ens.MessageHeader in OCUORDERS;
#   - the start's log holds STEP Demo OK.
check_demo_on() {
  local label=$1 permitted orders_props
  permitted='1(1"%CSP.Broker",1"EnsPortal.VisualTrace",1"EnsPortal.SVG.VisualTrace",1"EnsPortal.VisualTraceLegend",1"EnsPortal.SVG.TraceLegend",1"EnsPortal.MessageContents",1"EnsPortal.MessageViewer")'
  orders_props=$(security_app_props 1 /ocutalon/trace/ocuorders/ '' '' '' "$permitted" 1 32 OcuTalon OCUORDERS)
  check_session "$label: demo mode is on and the Demo step owns OCUORDERS" OCUTALON \
    "CHK|demo-mode|1
CHK|owned|1" \
    'Write !,"CHK|demo-mode|",##class(OcuTalon.Data.Setting).Get("demo.mode")' \
    'Write !,"CHK|owned|",##class(OcuTalon.Install.Step.Demo).Owned()' \
    'Halt'
  check_session "$label: OCUORDERS, its databases, resources, mappings, Interoperability and trace grants" %SYS \
    "CHK|ns|OCUORDERS|OCUORDERS_DATA|OCUORDERS_CODE
CHK|db-code|$mgr/ocuorders_code/
CHK|db-data|$mgr/ocuorders_data/
CHK|res-code|0
CHK|res-data|0
CHK|dest-orders|^$mgr/ocutalon_code/
CHK|dest-web-public|^$mgr/ocutalon_public/
CHK|dest-data-public|^$mgr/ocutalon_public/
CHK|dest-global-public|^$mgr/ocutalon_public/
CHK|interop|1
CHK|hs-instance|0
CHK|hs-maps|0
CHK|trace-role-orders|%DB_OCUORDERS_CODE:R,%DB_OCUORDERS_DATA:R
CHK|trace-sql-select-orders|1
CHK|portal-authe|32
CHK|app|/ocutalon/trace/ocuorders|$orders_props" \
    'Set sc=##class(Config.Namespaces).Get("OCUORDERS",.n) Write !,"CHK|ns|OCUORDERS|",$Get(n("Globals")),"|",$Get(n("Routines"))' \
    'Set sc=##class(Config.Databases).Get("OCUORDERS_CODE",.d) Write !,"CHK|db-code|",$Get(d("Directory"))' \
    'Set sc=##class(Config.Databases).Get("OCUORDERS_DATA",.d) Write !,"CHK|db-data|",$Get(d("Directory"))' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT PublicPermission FROM Security.Resources WHERE Name = ?","%DB_OCUORDERS_CODE") Write !,"CHK|res-code|",$Select(rs.%Next():rs.%GetData(1),1:"<missing>")' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT PublicPermission FROM Security.Resources WHERE Name = ?","%DB_OCUORDERS_DATA") Write !,"CHK|res-data|",$Select(rs.%Next():rs.%GetData(1),1:"<missing>")' \
    'Write !,"CHK|dest-orders|",##class(%SYS.Namespace).GetRoutineDest("OCUORDERS","OcuTalon.Demo.Orders.Production.1","INT")' \
    'Write !,"CHK|dest-web-public|",##class(%SYS.Namespace).GetRoutineDest("OCUORDERS","OcuTalon.Web.Public.Shell.1","INT")' \
    'Write !,"CHK|dest-data-public|",##class(%SYS.Namespace).GetRoutineDest("OCUORDERS","OcuTalon.Data.Public.Settings.1","INT")' \
    'Write !,"CHK|dest-global-public|",##class(%SYS.Namespace).GetGlobalDest("OCUORDERS","^OcuTalonPublic")' \
    'Write !,"CHK|interop|",##class(%Library.EnsembleMgr).IsEnsembleNamespace("OCUORDERS")' \
    'Set n=$Data(^%SYS("HealthShare","Instances","OCUORDERS")) Write !,"CHK|hs-instance|",n' \
    'Set n=0 For m="HS","HSMOD","SchemaMap","%pkg.isc" { Set n=n+##class(Config.MapPackages).Exists("OCUORDERS",m) } Write !,"CHK|hs-maps|",n' \
    'Set ok=##class(Security.Roles).Get("OcuTalonTraceViewer",.p) Set want=$ListBuild("%DB_OCUORDERS_CODE:R","%DB_OCUORDERS_DATA:R"),have="" For i=1:1:$Length($Get(p("Resources")),",") { If $ListFind(want,$Piece(p("Resources"),",",i)) { Set have=have_$Select(have="":"",1:",")_$Piece(p("Resources"),",",i) } } Write !,"CHK|trace-role-orders|",have' \
    'Write !,"CHK|trace-sql-select-orders|",$SYSTEM.SQL.Security.CheckPrivilege("OcuTalonTraceViewer",1,"Ens.MessageHeader","s","OCUORDERS")' \
    'Kill p Set sc=##class(Security.Applications).Get("/csp/ocuorders",.p) Write !,"CHK|portal-authe|",$Select($SYSTEM.Status.IsOK(sc):$Get(p("AutheEnabled")),1:"<missing>")' \
    'Set keys=$ListBuild("AutheEnabled","AutoCompile","CSPZENEnabled","CookiePath","CorsAllowlist","DispatchClass","Enabled","EventClass","GroupById","InbndWebServicesEnabled","IsNameSpaceDefault","LoginPage","MatchRoles","NameSpace","Path","PermittedClasses","ServeFiles","SessionScope","Timeout")' \
    'Kill p Set sc=##class(Security.Applications).Get("/ocutalon/trace/ocuorders",.p) Set out="" For k=1:1:$ListLength(keys) { Set key=$List(keys,k) Set out=out_key_"="_$Get(p(key))_";" } Write !,"CHK|app|/ocutalon/trace/ocuorders|",$Select($SYSTEM.Status.IsOK(sc):out,1:"<missing>")' \
    'Halt'
  check_session "$label: the Orders production runs in OCUORDERS, and is not autostart" OCUORDERS \
    "CHK|running|OcuTalon.Demo.Orders.Production
CHK|autostart|" \
    'Set r=##class(Ens.Director).IsProductionRunning(.name) Write !,"CHK|running|",$Select(r:name,1:"<not running>")' \
    'Write !,"CHK|autostart|",$Get(^Ens.AutoStart)' \
    'Halt'
  check_orders_jobs "$label"
  if start_log | grep -qx 'STEP Demo OK [0-9.]*s'; then
    pass "$label: the log holds STEP Demo OK"
  else
    fail "$label: the log holds no STEP Demo OK line"
  fi
}

# check_demo_off <label>: Story 0.10's row 3 on the running container, after a start with demo mode off: demo.mode is 0, and
# OCUORDERS, both databases with their directories, their resources, its mappings, its Interoperability markers and role, every
# web application of the namespace, the trace role's OCUORDERS grants and every SQL privilege of the namespace are gone.
check_demo_off() {
  local label=$1
  check_session "$label: demo mode is off" OCUTALON "CHK|demo-mode|0" \
    'Write !,"CHK|demo-mode|",##class(OcuTalon.Data.Setting).Get("demo.mode")' 'Halt'
  check_session "$label: OCUORDERS and everything it owned are gone" %SYS \
    "CHK|ns|0
CHK|db-code|0
CHK|db-data|0
CHK|dir-code|0
CHK|dir-data|0
CHK|res-code|0
CHK|res-data|0
CHK|role-prodprivs|0
CHK|apps|0
CHK|trace-role-orders|0
CHK|sqlpriv|0
CHK|maps|0
CHK|ens|0
CHK|ensrun|0
CHK|portal-dir|0" \
    'Write !,"CHK|ns|",##class(Config.Namespaces).Exists("OCUORDERS")' \
    'Write !,"CHK|db-code|",##class(Config.Databases).Exists("OCUORDERS_CODE")' \
    'Write !,"CHK|db-data|",##class(Config.Databases).Exists("OCUORDERS_DATA")' \
    'Write !,"CHK|dir-code|",##class(%File).DirectoryExists($SYSTEM.Util.ManagerDirectory()_"ocuorders_code")' \
    'Write !,"CHK|dir-data|",##class(%File).DirectoryExists($SYSTEM.Util.ManagerDirectory()_"ocuorders_data")' \
    'Write !,"CHK|res-code|",##class(Security.Resources).Exists("%DB_OCUORDERS_CODE")' \
    'Write !,"CHK|res-data|",##class(Security.Resources).Exists("%DB_OCUORDERS_DATA")' \
    'Write !,"CHK|role-prodprivs|",##class(Security.Roles).Exists("%EnsRole_ProdPrivs_OCUORDERS")' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE NameSpace = ?","OCUORDERS") Do rs.%Next() Write !,"CHK|apps|",rs.%GetData(1)' \
    'Set ok=##class(Security.Roles).Get("OcuTalonTraceViewer",.p) Write !,"CHK|trace-role-orders|",($Get(p("Resources"))["OCUORDERS")' \
    'Set rs=##class(%ResultSet).%New("Security.SQLPrivileges:List") Do rs.Execute() Set n=0 While rs.Next() { If rs.Get("Namespace")="OCUORDERS" { Set n=n+1 } } Write !,"CHK|sqlpriv|",n' \
    'Set rs=##class(%ResultSet).%New("Config.MapPackages:List") Do rs.Execute("OCUORDERS") Set n=0 While rs.Next() { Set n=n+1 } Write !,"CHK|maps|",n' \
    'Write !,"CHK|ens|",$Data(^%SYS("Ensemble","InstalledNamespace","OCUORDERS"))' \
    'Write !,"CHK|ensrun|",$Data(^%SYS("Ensemble","RunningNamespace","OCUORDERS"))' \
    'Write !,"CHK|portal-dir|",##class(%File).DirectoryExists($SYSTEM.Util.DataDirectory()_"csp/ocuorders")' \
    'Halt'
  if start_log | grep -qx 'STEP Demo OK [0-9.]*s'; then
    pass "$label: the log holds STEP Demo OK"
  else
    fail "$label: the log holds no STEP Demo OK line"
  fi
}
