#!/usr/bin/env bash
# Hermetic test of the helpers in lib-live.sh that the live tests rely on for their own correctness (Story 0.2).
# Starts no container: `dc`, `started_at` and `health_status` are replaced by stubs that answer from files, so
# the helpers run on log files and stamps that the test writes.
#   - start_log_complete, wait_started_log, wait_started_ready: a start's log counts only when it began at or after
#     the container's start and ends with the end line, and readiness counts only when that line says ready and
#     Docker reports healthy for the same start, so a previous start's log or health is never taken for this one;
#   - copy_build_context: exactly the files the Dockerfile's COPY lines name, a directory expanded to its files;
#   - log_steps, bump_patch, manifest_version: the reductions the live tests compare;
#   - live_web_port: the first free port of 52800-52819 on 127.0.0.1, the OCUTALON_TEST_WEB_PORT override, a refusal
#     of the ports of the judges' stack, the slots and the other instances, and a clear failure when no port is free
#     (the ports in use are stubbed, nothing listens);
#   - ensure_web_bundle: no Node is needed when the bundle and the dependencies are there, and its absence is named
#     when they are not;
#   - live_start (Story 0.7): the project name carries OCUTALON_RUN_TAG, a bad tag is refused with exit 2, the deadline
#     follows OCUTALON_LIVE_DEADLINE (default 540 s), and the compose files end with the throwaway and CI overrides;
#   - the throwaway lock: claimed atomically with Rule 12's content and "LOCK acquired", waited for with "LOCK waiting" and
#     taken when the holder lets go, given up with exit 75 naming the holder, released with "LOCK released" only when it is
#     this run's, a foreign lock kept, no lock without the folder, and the folder derived from the main checkout.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Takes about 10 s: the negative waits sleep 3 s each.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-live.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ll.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

log_fixture="$tmp/after-start.log"

# dc exec -T iris <command> <args>...: runs the command with the log's container path replaced by the fixture.
dc() {
  [ "$1" = exec ] || return 1
  shift 3
  local args=() a
  for a in "$@"; do
    if [ "$a" = /durable/ocutalon-after-start.log ]; then a=$log_fixture; fi
    args+=("$a")
  done
  "${args[@]}"
}
started_at() { cat "$tmp/started"; }
# Docker's verdict comes from a file; with $tmp/restart-on-health present, the container "starts again" the
# moment its health is read.
health_status() {
  cat "$tmp/health"
  if [ -f "$tmp/restart-on-health" ]; then echo "2026-10-18T10:05:00.000000000Z" > "$tmp/started"; fi
}

container_started() { echo "$1" > "$tmp/started"; } # a Docker-style stamp
set_health() { echo "$1" > "$tmp/health"; }
write_log() { # write_log <begin stamp or NONE> <end line yes|no>
  : > "$log_fixture"
  if [ "$1" != NONE ]; then echo "AFTER-START begin $1" >> "$log_fixture"; fi
  printf 'STEP merge OK 1s\nSTEP Ready OK 0.1s\nRESULT OK 0.1.0\n' >> "$log_fixture"
  if [ "$2" = yes ]; then echo "AFTER-START end 2026-10-18T10:09:00Z ready 0.1.0" >> "$log_fixture"; fi
}

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
accepts() { # accepts <label> <command...>
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}
rejects() { # rejects <label> <command...>
  local label=$1
  shift
  if "$@"; then fail "$label"; else pass "$label"; fi
}

deadline=$((SECONDS + 100))
container_started "2026-10-18T10:00:00.123456789Z"
set_health healthy

# --- start_log_complete: this start's log, never a previous one ---

rm -f "$log_fixture"
rejects "start log: a missing log is not complete" start_log_complete 2026-10-18T10:00:00
: > "$log_fixture"
rejects "start log: an empty log is not complete" start_log_complete 2026-10-18T10:00:00
write_log 2026-10-18T09:59:59Z yes
rejects "start log: a complete log of a start one second before the container's start is a previous start's" \
  start_log_complete 2026-10-18T10:00:00
write_log 2026-10-17T23:59:59Z yes
rejects "start log: a complete log of the day before is a previous start's" start_log_complete 2026-10-18T00:00:00
write_log 2026-10-18T10:00:00Z yes
accepts "start log: a complete log that began in the container's first second is this start's" start_log_complete 2026-10-18T10:00:00
write_log 2026-10-18T10:00:07Z yes
accepts "start log: a complete log that began later is this start's" start_log_complete 2026-10-18T10:00:00
write_log 2026-10-18T10:00:07Z no
rejects "start log: a log of this start without its end line is still running" start_log_complete 2026-10-18T10:00:00
write_log NONE yes
rejects "start log: a log that does not begin with the begin line is not a script's log" start_log_complete 2026-10-18T10:00:00

# --- wait_started_log and wait_started_ready ---

write_log 2026-10-18T09:59:59Z yes
rejects "wait for the start's log: the previous start's complete log is not accepted" wait_started_log 1
write_log 2026-10-18T10:00:07Z yes
accepts "wait for the start's log: this start's complete log is accepted at once" wait_started_log 60

set_health healthy
accepts "wait for readiness: this start's log and Docker's healthy are accepted" wait_started_ready 60

set_health starting
saved_deadline=$deadline
deadline=$((SECONDS + 2))
rejects "wait for readiness: this start's log without Docker's healthy is not accepted" wait_started_ready 60
deadline=$saved_deadline

set_health healthy
printf 'AFTER-START begin 2026-10-18T10:00:07Z\nSTEP SSL FAILED boom\nAFTER-START end 2026-10-18T10:09:00Z not ready\n' > "$log_fixture"
rejects "wait for readiness: a start that ended not ready is not accepted, even while Docker still reports healthy" \
  wait_started_ready 60
write_log 2026-10-18T10:00:07Z yes

set_health healthy
: > "$tmp/restart-on-health"
rejects "wait for readiness: a container that started again meanwhile is not accepted" wait_started_ready 60
rm -f "$tmp/restart-on-health"
container_started "2026-10-18T10:00:00.123456789Z"

# --- the build context ---

expected_files="docker/Dockerfile
docker/after-start.cos
docker/after-start.sh
docker/healthcheck.sh
docker/ipm/LICENSE
docker/ipm/zpm-0.10.10.xml
docker/merge.cpf
$(find src -type f)"
expected_files=$(printf '%s\n' "$expected_files" | sort)
copy_build_context "$tmp/ctx"
copied=$(cd "$tmp/ctx" && find . -type f | sed 's:^\./::' | sort)
if [ "$copied" = "$expected_files" ]; then
  pass "build context: the Dockerfile, its scripts, the IPM files and every file below src/, and nothing else"
else
  echo "  copied:   $(echo "$copied" | tr '\n' ' ')"
  echo "  expected: $(echo "$expected_files" | tr '\n' ' ')"
  fail "build context: the copied files differ from the files the Dockerfile names"
fi
same=1
for f in $expected_files; do cmp -s "$f" "$tmp/ctx/$f" || same=0; done
if [ "$same" -eq 1 ]; then pass "build context: every copied file equals its original"; else fail "build context: a copied file differs from its original"; fi

# --- reductions ---

write_log 2026-10-18T10:00:07Z yes
printf '%s\n' "STEP Tasks OK 12.5s" "STEP SSL FAILED boom 3s" "noise" > "$tmp/lines"
cat "$tmp/lines" >> "$log_fixture"
if [ "$(log_steps)" = "STEP merge OK
STEP Ready OK
RESULT OK 0.1.0
STEP Tasks OK
STEP SSL FAILED boom 3s" ]; then
  pass "log_steps: only STEP and RESULT lines, the seconds of an OK line dropped, a FAILED line kept whole"
else
  fail "log_steps: the reduced log differs ($(log_steps | tr '\n' '|'))"
fi

printf '<Module>\n<Version>1.2.3</Version>\n<Version>9.9.9</Version>\n</Module>\n' > "$tmp/module.xml"
if [ "$(manifest_version "$tmp/module.xml")" = 1.2.3 ] && [ "$(bump_patch 1.2.3 2)" = 1.2.5 ]; then
  pass "versions: the first <Version> is the manifest's, and bump_patch raises only the patch number"
else
  fail "versions: manifest_version or bump_patch is wrong"
fi

# --- live_web_port ---

# The ports that the stub reports as in use, one per line; the real probe is replaced.
used_ports="$tmp/used-ports"
port_in_use() { grep -qx "$1" "$used_ports"; }
LIVE_FILES=()
web_port=""

: > "$used_ports"
unset OCUTALON_TEST_WEB_PORT
live_web_port > "$tmp/port.out" 2>&1
if [ "$web_port" = 52800 ] && [ "${#LIVE_FILES[@]}" -eq 1 ] && [ "${LIVE_FILES[0]}" = "$tmp/port.yml" ] \
  && [ "$(cat "$tmp/port.yml")" = 'services:
  iris:
    ports:
      - "127.0.0.1:52800:52773"' ]; then
  pass "web port: with nothing listening it publishes 52800 on 127.0.0.1 only, in an override added to the compose files"
else
  fail "web port: expected 52800 and an override file ('$web_port', $(cat "$tmp/port.yml" 2>/dev/null | tr '\n' ' '))"
fi

printf '%s\n' 52800 52801 52803 > "$used_ports"
LIVE_FILES=()
live_web_port > "$tmp/port.out" 2>&1
if [ "$web_port" = 52802 ]; then
  pass "web port: it picks the first free port, not the first port above the busy ones"
else
  fail "web port: with 52800, 52801 and 52803 in use it picked '$web_port', wanted 52802"
fi

OCUTALON_TEST_WEB_PORT=52815
live_web_port > "$tmp/port.out" 2>&1
if [ "$web_port" = 52815 ] && grep -q '127.0.0.1:52815:52773' "$tmp/port.yml"; then
  pass "web port: OCUTALON_TEST_WEB_PORT is honoured"
else
  fail "web port: the override gave '$web_port'"
fi

for refused in 52773 052773 52790 1979 8089 0 80 99999 52799 52820 abc 52x; do
  OCUTALON_TEST_WEB_PORT=$refused
  web_port=""
  if live_web_port > "$tmp/port.out" 2>&1 || [ -n "$web_port" ]; then
    fail "web port: the override '$refused' was accepted"
  elif grep -q '^FAIL live_web_port' "$tmp/port.out"; then
    pass "web port: the override '$refused' is refused with a message"
  else
    fail "web port: the override '$refused' was refused without a message"
  fi
done

printf '%s\n' 52815 > "$used_ports"
OCUTALON_TEST_WEB_PORT=52815
web_port=""
if live_web_port > "$tmp/port.out" 2>&1 || [ -n "$web_port" ]; then
  fail "web port: the override 52815 was accepted while something listens on it"
elif grep -q '^FAIL live_web_port.*in use' "$tmp/port.out"; then
  pass "web port: an override that is in use is refused with a message"
else
  fail "web port: an override that is in use was refused without saying so"
fi
unset OCUTALON_TEST_WEB_PORT

seq 52800 52819 > "$used_ports"
web_port=""
if live_web_port > "$tmp/port.out" 2>&1 || [ -n "$web_port" ]; then
  fail "web port: it picked a port with all of 52800-52819 in use"
elif grep -q 'all in use' "$tmp/port.out"; then
  pass "web port: with no free port it fails and says so"
else
  fail "web port: with no free port it failed without saying why"
fi

in_range=0
for forbidden in $LIVE_FORBIDDEN_PORTS; do
  if [ "$forbidden" -ge 52800 ] && [ "$forbidden" -le 52819 ]; then in_range=1; fi
done
if [ "$in_range" -eq 0 ] && [ "$LIVE_FORBIDDEN_PORTS" = "52773 1979 52779 8089 1990 1991 52790 52791 8090 8091" ]; then
  pass "web port: none of the ports of the judges' stack, the slots and the other instances is in 52800-52819"
else
  fail "web port: the forbidden ports are wrong, or one is in the range"
fi

# --- ensure_web_bundle ---

mkdir -p "$tmp/nobin" "$tmp/empty-tree" "$tmp/full-tree/web/node_modules" "$tmp/full-tree/src/ocutalon/csp"
: > "$tmp/full-tree/src/ocutalon/csp/index.html"
out=$(cd "$tmp/empty-tree" && PATH="$tmp/nobin" ensure_web_bundle 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q 'node'; then
  pass "web bundle: without the bundle and without Node it fails and names Node"
else
  fail "web bundle: expected a failure that names Node ($out)"
fi
out=$(cd "$tmp/full-tree" && LIVE_REBUILD_WEB=0 PATH="$tmp/nobin" ensure_web_bundle 2>&1)
if [ $? -eq 0 ] && [ -z "$out" ]; then
  pass "web bundle: with the bundle and the dependencies in place Node is not needed"
else
  fail "web bundle: expected success without Node ($out)"
fi

# --- live_start: the project name, the deadline and the compose files ---

# live_start runs in a subshell with the web bundle check and Docker stubbed out; the subshell's exit runs the cleanup trap.
ensure_web_bundle() { return 0; }
start_probe() { # start_probe <env assignments...>: P, the seconds left to the deadline, the files and the exit code
  (
    unset OCUTALON_LIVE_DEADLINE OCUTALON_LOCK_WAIT OCUTALON_LOCK_OWNER OCUTALON_LOCK_SLEEP_MIN OCUTALON_LOCK_SLEEP_MAX
    export "$@"
    live_start t07x
    echo "P=$P"
    echo "LEFT=$((deadline - SECONDS))"
    echo "FILES=${#LIVE_FILES[@]} $(basename "${LIVE_FILES[2]}") $(basename "${LIVE_FILES[3]}")"
  ) 2>&1
  echo "RC=$?"
}
out=$(start_probe OCUTALON_RUN_TAG= OCUTALON_LOCK_DIR="$tmp/no-such-folder")
if printf '%s\n' "$out" | grep -Eq '^P=ocutalon-t07x-[0-9]+-[0-9]+$'; then
  pass "live_start: without a run tag the project is ocutalon-<label>-<epoch>-<pid>"
else
  fail "live_start: the project name without a tag is wrong ($(printf '%s' "$out" | grep '^P='))"
fi
out=$(start_probe OCUTALON_RUN_TAG=abc-1-shards OCUTALON_LOCK_DIR="$tmp/no-such-folder")
if printf '%s\n' "$out" | grep -Eq '^P=ocutalon-t07x-abc-1-shards-[0-9]+-[0-9]+$'; then
  pass "live_start: with a run tag the project is ocutalon-<label>-<tag>-<epoch>-<pid>"
else
  fail "live_start: the project name with a tag is wrong ($(printf '%s' "$out" | grep '^P='))"
fi
for bad in Upper_Case has-slot-in-it 'a b'; do
  out=$(start_probe OCUTALON_RUN_TAG="$bad" OCUTALON_LOCK_DIR="$tmp/no-such-folder")
  if printf '%s\n' "$out" | grep -q '^RC=2$' && ! printf '%s\n' "$out" | grep -q '^P='; then
    pass "live_start: the run tag '$bad' is refused with exit 2"
  else
    fail "live_start: the run tag '$bad' was not refused with exit 2"
  fi
done
out=$(start_probe OCUTALON_RUN_TAG=abc OCUTALON_LOCK_DIR="$tmp/no-such-folder")
left=$(printf '%s\n' "$out" | sed -n 's/^LEFT=//p')
if [ -n "$left" ] && [ "$left" -ge 535 ] && [ "$left" -le 540 ]; then
  pass "live_start: the deadline is 540 s by default"
else
  fail "live_start: the default deadline leaves '$left' s"
fi
out=$(start_probe OCUTALON_RUN_TAG=abc OCUTALON_LIVE_DEADLINE=1200 OCUTALON_LOCK_DIR="$tmp/no-such-folder")
left=$(printf '%s\n' "$out" | sed -n 's/^LEFT=//p')
if [ -n "$left" ] && [ "$left" -ge 1195 ] && [ "$left" -le 1200 ]; then
  pass "live_start: OCUTALON_LIVE_DEADLINE sets the deadline"
else
  fail "live_start: OCUTALON_LIVE_DEADLINE=1200 leaves '$left' s"
fi
if printf '%s\n' "$out" | grep -qx 'FILES=4 compose.throwaway.yml compose.ci.yml'; then
  pass "live_start: the compose files end with the throwaway override and the CI override"
else
  fail "live_start: the compose files are not the judges' file, the decoy, the throwaway override and the CI override"
fi

# --- the throwaway lock ---

lockdir="$tmp/locks"
mkdir -p "$lockdir"
lockfile="$lockdir/throwaway-iris.lock"
export OCUTALON_LOCK_DIR="$lockdir"
claim_probe() { # claim_probe <project> <wait s>: a second run's claim in a subshell, 1 s between tries
  ( P=$1 OCUTALON_LOCK_WAIT=$2 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1 live_lock_claim ) 2>&1
  echo "RC=$?"
}

P=ocutalon-holder-1-1
OCUTALON_LOCK_OWNER='epic=0 stage=implement'
out=$(live_lock_claim)
OCUTALON_LOCK_OWNER=''
unset OCUTALON_LOCK_OWNER
if [ -f "$lockfile" ] && printf '%s\n' "$out" | grep -q '^LOCK acquired' \
  && grep -Eq '^epic=0 stage=implement project=ocutalon-holder-1-1 acquired_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$lockfile"; then
  pass "lock: the first run creates throwaway-iris.lock with Rule 12's content and prints LOCK acquired"
else
  fail "lock: the first run did not create the lock with the expected content ($out; $(cat "$lockfile" 2>/dev/null))"
fi
# live_lock_claim ran in a subshell above, so the state is set again here for the release checks.
LIVE_LOCK_FILE=$lockfile
LIVE_LOCK_CONTENT=$(cat "$lockfile")

out=$(claim_probe ocutalon-second-2-2 2)
if printf '%s\n' "$out" | grep -q '^LOCK waiting' && printf '%s\n' "$out" | grep -q '^LOCK busy.*project=ocutalon-holder-1-1' \
  && printf '%s\n' "$out" | grep -q '^RC=75$' && [ "$(cat "$lockfile")" = "$LIVE_LOCK_CONTENT" ]; then
  pass "lock: a second run prints LOCK waiting, gives up with exit 75 naming the holder, and leaves the lock as it was"
else
  fail "lock: the second run did not wait and exit 75 naming the holder ($out)"
fi

( sleep 2; rm -f "$lockfile" ) &
releaser=$!
out=$(claim_probe ocutalon-third-3-3 20)
wait "$releaser"
if printf '%s\n' "$out" | grep -q '^LOCK waiting' && printf '%s\n' "$out" | grep -q '^LOCK acquired.*project=ocutalon-third-3-3' \
  && printf '%s\n' "$out" | grep -q '^RC=0$'; then
  pass "lock: a waiting run takes the lock when the holder lets go"
else
  fail "lock: the waiting run did not take the lock after the holder let go ($out)"
fi
rm -f "$lockfile"

P=ocutalon-holder-1-1
out=$(live_lock_claim)
LIVE_LOCK_FILE=$lockfile
LIVE_LOCK_CONTENT=$(cat "$lockfile")
out=$(live_lock_release)
if [ ! -e "$lockfile" ] && printf '%s\n' "$out" | grep -q '^LOCK released'; then
  pass "lock: the cleanup deletes its own lock and prints LOCK released"
else
  fail "lock: the cleanup did not delete its own lock ($out)"
fi

out=$(live_lock_claim)
LIVE_LOCK_FILE=$lockfile
LIVE_LOCK_CONTENT=$(cat "$lockfile")
echo 'epic=9 stage=qa project=ocutalon-foreign-9-9 acquired_at=2026-10-19T00:00:00Z' > "$lockfile"
out=$(live_lock_release)
if [ -f "$lockfile" ] && grep -q 'ocutalon-foreign-9-9' "$lockfile" && printf '%s\n' "$out" | grep -q '^LOCK kept'; then
  pass "lock: a lock that another run holds is kept, whatever this run holds"
else
  fail "lock: the cleanup deleted or changed a foreign lock ($out)"
fi
rm -f "$lockfile"
LIVE_LOCK_FILE=""

# An exit between the lock claim and the compose files has no stack to remove: the cleanup runs no compose command (dc is a stub
# that records its calls) and still releases the lock.
docker_calls="$tmp/docker-calls"
: > "$docker_calls"
out=$(
  dc() { echo "dc $*" >> "$docker_calls"; }
  tmp=""
  P=ocutalon-early-4-4
  LIVE_FILES=()
  LIVE_IMAGES=()
  live_lock_claim
  live_cleanup
  echo "RC=$?"
)
if [ ! -e "$lockfile" ] && [ ! -s "$docker_calls" ] && printf '%s\n' "$out" | grep -q '^LOCK released' && printf '%s\n' "$out" | grep -q '^RC=0$'; then
  pass "lock: a cleanup before the compose files exist runs no compose command and releases the lock"
else
  fail "lock: the early cleanup ran a compose command ($(tr '\n' ' ' < "$docker_calls")), or kept the lock ($out)"
fi
rm -f "$lockfile"

export OCUTALON_LOCK_DIR="$tmp/no-such-folder"
out=$(live_lock_claim; echo "FILE=[$LIVE_LOCK_FILE]")
if [ -z "$(ls "$lockdir")" ] && [ "$out" = "FILE=[]" ]; then
  pass "lock: without the folder no lock is taken and nothing is printed"
else
  fail "lock: a lock was taken, or something was printed, without the folder ($out)"
fi
unset OCUTALON_LOCK_DIR

# The folder comes from the main checkout, also when the run is in one of its worktrees.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
main="$tmp/main"
git init -q "$main"
git -C "$main" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m x
git -C "$main" worktree add -q --detach "$tmp/wt" >/dev/null 2>&1
mkdir -p "$main/_bmad/custom" "$tmp/wt/_bmad/custom"
printf 'worktree_base: .worktrees\n' | tee "$main/_bmad/custom/parallel.yaml" > "$tmp/wt/_bmad/custom/parallel.yaml"
saved_root=$root
root=$tmp/wt
none=$(live_lock_dir)
mkdir -p "$main/.worktrees/.coordination/locks"
from_worktree=$(live_lock_dir)
root=$main
from_main=$(live_lock_dir)
root=$saved_root
want=$(cd "$main/.worktrees/.coordination/locks" && pwd -P)
if [ -z "$none" ] && [ "$from_worktree" = "$want" ] && [ "$from_main" = "$want" ]; then
  pass "lock: the folder is the main checkout's <worktree_base>/.coordination/locks, from a worktree too, and none without it"
else
  fail "lock: the folder is '$from_worktree' from the worktree and '$from_main' from the main checkout, wanted '$want' (none: '$none')"
fi
unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

if [ "$fails" -ne 0 ]; then
  echo "test-lib-live: $fails check(s) failed"
  exit 1
fi
echo "test-lib-live: all checks passed"
