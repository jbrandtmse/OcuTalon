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
#   - first_start_report and live_first_start (Story 0.8): the FIRST-START line's format, the WARN line only over 720 s, and the
#     order of the start with `dc`, `docker` and `wait_started_ready` stubbed: build, then the image check, then `up -d --no-build`,
#     then the wait; a failed step returns 1 and names its seconds, and starts nothing after it;
#   - ensure_web_bundle: no Node is needed when the bundle and the dependencies are there, and its absence is named
#     when they are not;
#   - compare_surfaces (Story 0.10): equal surfaces pass, with or without --drop-orders; a line that does not name OCUORDERS and is
#     gone or new, an OCUORDERS line left behind, an empty file and an unknown option fail;
#   - live_start (Story 0.7): the project name carries OCUTALON_RUN_TAG, a bad or short tag is refused with exit 2, the
#     deadline follows OCUTALON_LIVE_DEADLINE (default 540 s), and the compose files end with the throwaway and CI overrides;
#   - the throwaway lock: claimed atomically with Rule 12's content and "LOCK acquired", waited for with "LOCK waiting" and
#     taken when the holder lets go, given up with exit 75 naming the holder, released with "LOCK released" only when it is
#     this run's, a foreign lock kept, no lock when OCUTALON_LOCK_DIR names no folder (also where the main checkout has one),
#     and the folder derived from the main checkout; and through live_start itself: the lock is held when the first thing after
#     the claim runs, names the project, is deleted by the exit trap, a lock that another run holds makes live_start exit 75
#     before anything starts, and after a wait for the lock the deadline and acquired_at count from the moment it is held;
#   - live_key_count (Story 10.3, Story 12.1): the CI dummy bot token and an empty one count 0, a model key and any other bot token
#     count 1; live_no_bot_token adds the compose file that sets the token to the empty value, last.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Takes about 15 s: the waits sleep 3 s each.
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

# --- first_start_report and live_first_start (Story 0.8) ---

out=$(first_start_report 12 57 aarch64)
if [ "$out" = "FIRST-START engine=aarch64 build=12s ready=57s" ]; then
  pass "first start report: one FIRST-START line with the engine, the build and the ready seconds, and no WARN"
else
  fail "first start report: the line is '$out'"
fi
out=$(first_start_report 30 720 x86_64)
if [ "$out" = "FIRST-START engine=x86_64 build=30s ready=720s" ]; then
  pass "first start report: 720 s is not over 12 minutes, so no WARN"
else
  fail "first start report: 720 s gave '$out'"
fi
out=$(first_start_report 30 721 x86_64)
if [ "$out" = "FIRST-START engine=x86_64 build=30s ready=721s
WARN first start 721 s is over 12 minutes: raise it to the author (AD-23)" ]; then
  pass "first start report: 721 s adds the WARN line after the FIRST-START line"
else
  fail "first start report: 721 s gave '$out'"
fi

# first_start_probe <failing dc subcommand, or ->: live_first_start with stubs. `dc` and `docker` record their calls in
# $tmp/first-calls; the stubs set SECONDS, so that the build ends at 30 s and the start (the `up` and the wait together) takes the
# seconds in $FIRST_READY, or the wait fails after 100 s when FIRST_READY is "never". The probe prints the calls, the output, the
# exit code, cid and the two figures.
first_calls="$tmp/first-calls"
first_start_probe() {
  (
    FAILING=$1
    P=ocutalon-t08x-1-1
    cid=""
    first_build_s=""
    first_ready_s=""
    : > "$first_calls"
    dc() {
      echo "dc $*" >> "$first_calls"
      [ "$FAILING" != "$1" ] || return 1
      case $1 in
        build) SECONDS=30 ;;
        up) SECONDS=32 ;;
        ps) echo cid-of-the-first-start ;;
      esac
    }
    docker() {
      case $1 in
        info)
          echo engine-query >> "$first_calls"
          [ "$FAILING" != info ] || return 1
          echo x86_64
          ;;
        image)
          echo image-check >> "$first_calls"
          [ "$FAILING" != image ]
          ;;
      esac
    }
    live_track_image() { echo track >> "$first_calls"; }
    wait_started_ready() {
      echo "wait $1" >> "$first_calls"
      if [ "$FIRST_READY" = never ]; then
        SECONDS=130
        return 1
      fi
      SECONDS=$((30 + FIRST_READY))
    }
    SECONDS=0
    live_first_start 900
    echo "RC=$?"
    echo "CID=$cid BUILD=$first_build_s READY=$first_ready_s"
  ) 2>&1
}
calls_of() { tr '\n' '|' < "$first_calls"; }

FIRST_READY=200 out=$(first_start_probe -)
if printf '%s\n' "$out" | grep -qx 'FIRST-START engine=x86_64 build=30s ready=200s' && printf '%s\n' "$out" | grep -qx 'RC=0' \
  && printf '%s\n' "$out" | grep -qx 'CID=cid-of-the-first-start BUILD=30 READY=200' && ! printf '%s\n' "$out" | grep -q '^WARN' \
  && [ "$(calls_of)" = "dc build|track|image-check|dc up -d --no-build|dc ps -q iris|wait 900|engine-query|" ]; then
  pass "live_first_start: it builds, then checks the image, then starts without building, then waits, and prints the figures from the start's own seconds"
else
  fail "live_first_start: wrong order or figures ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=721 out=$(first_start_probe -)
if printf '%s\n' "$out" | grep -qx 'FIRST-START engine=x86_64 build=30s ready=721s' \
  && printf '%s\n' "$out" | grep -qx 'WARN first start 721 s is over 12 minutes: raise it to the author (AD-23)' && printf '%s\n' "$out" | grep -qx 'RC=0'; then
  pass "live_first_start: a start that is ready after 721 s still succeeds, with the WARN line"
else
  fail "live_first_start: a slow start did not warn and succeed ($(printf '%s' "$out" | tr '\n' '|'))"
fi
FIRST_READY=never out=$(first_start_probe -)
if printf '%s\n' "$out" | grep -qx 'RC=1' && printf '%s\n' "$out" | grep -q 'not ready after waiting 100 s' && ! printf '%s\n' "$out" | grep -q '^FIRST-START' \
  && [ "$(calls_of)" = "dc build|track|image-check|dc up -d --no-build|dc ps -q iris|wait 900|" ]; then
  pass "live_first_start: a start that never ends ready returns 1, names the seconds it waited and prints no figure"
else
  fail "live_first_start: a failed wait was not reported ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=200 out=$(first_start_probe build)
if printf '%s\n' "$out" | grep -qx 'RC=1' && printf '%s\n' "$out" | grep -q 'the image build failed after' && [ "$(calls_of)" = "dc build|" ]; then
  pass "live_first_start: a failed build returns 1 and starts nothing"
else
  fail "live_first_start: a failed build was not reported ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=200 out=$(first_start_probe image)
if printf '%s\n' "$out" | grep -qx 'RC=1' && printf '%s\n' "$out" | grep -q 'the build left no image ocutalon-t08x-1-1-iris' \
  && [ "$(calls_of)" = "dc build|track|image-check|" ]; then
  pass "live_first_start: a build that leaves no image returns 1, because starting it would build again"
else
  fail "live_first_start: a build without an image was not reported ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=200 out=$(first_start_probe up)
if printf '%s\n' "$out" | grep -qx 'RC=1' && printf '%s\n' "$out" | grep -q 'docker compose up failed after' \
  && [ "$(calls_of)" = "dc build|track|image-check|dc up -d --no-build|" ]; then
  pass "live_first_start: a failed start returns 1 and does not wait"
else
  fail "live_first_start: a failed start was not reported ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=200 out=$(first_start_probe ps)
if printf '%s\n' "$out" | grep -qx 'RC=1' && printf '%s\n' "$out" | grep -q 'no iris container in project ocutalon-t08x-1-1 after' \
  && [ "$(calls_of)" = "dc build|track|image-check|dc up -d --no-build|dc ps -q iris|" ]; then
  pass "live_first_start: a start with no iris container returns 1 and does not wait"
else
  fail "live_first_start: a start with no container was not reported ($(printf '%s' "$out" | tr '\n' '|'); calls $(calls_of))"
fi
FIRST_READY=200 out=$(first_start_probe info)
if printf '%s\n' "$out" | grep -qx 'FIRST-START engine=unknown build=30s ready=200s' && printf '%s\n' "$out" | grep -qx 'RC=0'; then
  pass "live_first_start: an engine that docker info cannot name is printed as unknown, and the start still succeeds"
else
  fail "live_first_start: an unnamed engine was not printed as unknown ($(printf '%s' "$out" | tr '\n' '|'))"
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
for bad in Upper_Case has-slot-in-it 'a b' ab; do
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

# --- live_start and the throwaway lock: claimed before anything starts, released by the exit trap ---

# start_lock_probe <env assignments...>: live_start with a lock folder of its own. The web bundle check is stubbed to say whether the
# lock was held when it ran, which is the first thing that live_start does after the claim.
startlock="$tmp/start-locks"
mkdir -p "$startlock"
start_lock_probe() {
  (
    unset OCUTALON_LIVE_DEADLINE OCUTALON_LOCK_WAIT OCUTALON_LOCK_OWNER OCUTALON_LOCK_SLEEP_MIN OCUTALON_LOCK_SLEEP_MAX
    export OCUTALON_RUN_TAG=abc-1 OCUTALON_LOCK_DIR="$startlock" "$@"
    ensure_web_bundle() {
      if [ -f "$startlock/throwaway-iris.lock" ]; then echo "BUNDLE lock-held"; else echo "BUNDLE no-lock"; fi
    }
    live_start t07z
    echo "HELD=$(cat "$startlock/throwaway-iris.lock" 2>/dev/null)"
    echo "P=$P"
    echo "LEFT=$((deadline - SECONDS))"
  ) 2>&1
  echo "RC=$?"
}
out=$(start_lock_probe OCUTALON_LOCK_OWNER='epic=0 stage=qa')
p_name=$(printf '%s\n' "$out" | sed -n 's/^P=//p')
if printf '%s\n' "$out" | grep -q "^LOCK acquired throwaway-iris project=$p_name\$" && printf '%s\n' "$out" | grep -qx 'BUNDLE lock-held' \
  && printf '%s\n' "$out" | grep -Eq "^HELD=epic=0 stage=qa project=$p_name acquired_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\$" \
  && printf '%s\n' "$out" | grep -q "^LOCK released throwaway-iris project=$p_name\$" && printf '%s\n' "$out" | grep -qx 'RC=0' \
  && [ -n "$p_name" ] && [ ! -e "$startlock/throwaway-iris.lock" ]; then
  pass "live_start: it claims the lock before anything starts, names its project in it, and the exit trap deletes it"
else
  fail "live_start: the lock was not claimed before the bundle check, did not name the project, or was left behind ($(printf '%s' "$out" | tr '\n' '|'); left: $(ls "$startlock" | tr '\n' ' '))"
fi
foreign='epic=9 stage=qa project=ocutalon-foreign-9-9 acquired_at=2026-10-19T00:00:00Z'
echo "$foreign" > "$startlock/throwaway-iris.lock"
out=$(start_lock_probe OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1)
if printf '%s\n' "$out" | grep -qx 'RC=75' && printf '%s\n' "$out" | grep -q '^LOCK busy.*project=ocutalon-foreign-9-9' \
  && ! printf '%s\n' "$out" | grep -q '^BUNDLE' && ! printf '%s\n' "$out" | grep -q '^P=' && [ "$(cat "$startlock/throwaway-iris.lock")" = "$foreign" ]; then
  pass "live_start: while another run holds the lock it exits 75 before anything starts and leaves that lock as it was"
else
  fail "live_start: it did not give up with exit 75 before the bundle check, or it touched the lock of another run ($(printf '%s' "$out" | tr '\n' '|'))"
fi
rm -f "$startlock/throwaway-iris.lock"

# A run that waits for the lock: its deadline and its acquired_at count from the moment it holds the lock, not from its start.
# The holder lets go after 3 s; a stamp taken after 2 s must not be later than acquired_at.
echo "$foreign" > "$startlock/throwaway-iris.lock"
( sleep 2; date -u +%Y-%m-%dT%H:%M:%SZ > "$tmp/stamp-2s"; sleep 1; rm -f "$startlock/throwaway-iris.lock" ) &
releaser=$!
out=$(start_lock_probe OCUTALON_LIVE_DEADLINE=100 OCUTALON_LOCK_WAIT=20 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1)
wait "$releaser"
left=$(printf '%s\n' "$out" | sed -n 's/^LEFT=//p')
acquired=$(printf '%s\n' "$out" | sed -n 's/^HELD=.* acquired_at=//p')
stamp=$(cat "$tmp/stamp-2s" 2>/dev/null)
if printf '%s\n' "$out" | grep -q '^LOCK waiting' && printf '%s\n' "$out" | grep -qx 'RC=0' && [ -n "$left" ] && [ "$left" -ge 99 ] \
  && [ -n "$acquired" ] && [ -n "$stamp" ] && ! [[ "$acquired" < "$stamp" ]]; then
  pass "live_start: after a wait for the lock, the deadline and acquired_at count from the moment the lock is held"
else
  fail "live_start: after a wait the deadline leaves '$left' s of 100, or acquired_at '$acquired' is before '$stamp' ($(printf '%s' "$out" | tr '\n' '|'))"
fi
rm -f "$startlock/throwaway-iris.lock"

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
# OCUTALON_LOCK_DIR naming a folder that does not exist means no lock, even where the main checkout has its own folder.
out=$(OCUTALON_LOCK_DIR="$tmp/no-such-folder" P=ocutalon-nofolder-5-5; live_lock_claim; echo "FILE=[$LIVE_LOCK_FILE]")
if [ "$out" = "FILE=[]" ] && [ -z "$(ls "$main/.worktrees/.coordination/locks")" ]; then
  pass "lock: when OCUTALON_LOCK_DIR names no folder no lock is taken, not even in the main checkout's folder, and nothing is printed"
else
  fail "lock: a lock was taken, or something was printed, when OCUTALON_LOCK_DIR named no folder ($out; $(ls "$main/.worktrees/.coordination/locks" | tr '\n' ' '))"
fi
root=$saved_root
want=$(cd "$main/.worktrees/.coordination/locks" && pwd -P)
if [ -z "$none" ] && [ "$from_worktree" = "$want" ] && [ "$from_main" = "$want" ]; then
  pass "lock: the folder is the main checkout's <worktree_base>/.coordination/locks, from a worktree too, and none without it"
else
  fail "lock: the folder is '$from_worktree' from the worktree and '$from_main' from the main checkout, wanted '$want' (none: '$none')"
fi
unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# --- compare_surfaces (Story 0.10): the verdict of "nothing else changes" ---

# check_verdict <label> <PASS|FAIL> <compare_surfaces arguments...>: the verdict that compare_surfaces gives, with its own pass and
# fail replaced so that a failing verdict does not fail this test.
check_verdict() {
  local label=$1 want=$2 got
  shift 2
  got=$( ( pass() { echo "VERDICT PASS"; }; fail() { echo "VERDICT FAIL"; }; compare_surfaces verdict "$@" ) 2>&1 | grep '^VERDICT ' | tr '\n' ' ')
  if [ "$got" = "VERDICT $want " ]; then
    pass "compare_surfaces: $label"
  else
    fail "compare_surfaces: $label (wanted $want, got '$got')"
  fi
}
surf="$tmp/surf"
mkdir -p "$surf"
printf '%s\n' 'app|/a|USER|32' 'db|OCUORDERS_DATA|/m/ocuorders_data/' 'ns|OCUORDERS|OCUORDERS_DATA|OCUORDERS_CODE' 'role|R' > "$surf/with"
printf '%s\n' 'app|/a|USER|32' 'role|R' > "$surf/without"
printf '%s\n' 'app|/a|USER|32' > "$surf/lost"
printf '%s\n' 'app|/a|USER|32' 'role|R' 'role|Extra' > "$surf/extra"
printf '%s\n' 'app|/a|USER|32' 'role|R' 'app|/csp/ocuorders|OCUORDERS|32' > "$surf/left"
: > "$surf/empty"
check_verdict "the same surfaces less every OCUORDERS line pass" PASS "$surf/with" "$surf/without" --drop-orders
check_verdict "a line that does not name OCUORDERS and is gone fails" FAIL "$surf/with" "$surf/lost" --drop-orders
check_verdict "a line that does not name OCUORDERS and is new fails" FAIL "$surf/with" "$surf/extra" --drop-orders
check_verdict "an OCUORDERS line left behind fails" FAIL "$surf/with" "$surf/left" --drop-orders
check_verdict "equal surfaces pass without --drop-orders" PASS "$surf/with" "$surf/with"
check_verdict "surfaces that differ fail without --drop-orders" FAIL "$surf/with" "$surf/without"
check_verdict "an empty actual file fails" FAIL "$surf/with" "$surf/empty" --drop-orders
check_verdict "an empty expected file fails" FAIL "$surf/empty" "$surf/without"
check_verdict "an unknown option fails" FAIL "$surf/with" "$surf/without" --drop-everything

# --- live_key_count and check_no_key (Story 10.3): the CI dummy bot token is no key, a model key and any other bot token are ---

# `dc exec -T iris env ... sh -c ...` runs the command here, in a process whose environment the test sets, with the root pointing at a
# fixture tree that holds the CI override.
key_root="$tmp/keyroot"
mkdir -p "$key_root/ci"
printf 'name: ocutalon-ci\nservices:\n  iris:\n    environment:\n      TELEGRAM_BOT_TOKEN: fixture-dummy-token\n' > "$key_root/ci/compose.ci.yml"
key_count() { # key_count <ANTHROPIC_API_KEY or -> <TELEGRAM_BOT_TOKEN or -> [<root>]: the count live_key_count prints
  (
    unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN
    if [ "$1" != - ]; then export ANTHROPIC_API_KEY=$1; fi
    if [ "$2" != - ]; then export TELEGRAM_BOT_TOKEN=$2; fi
    root=${3:-$key_root}
    live_key_count
  )
}
printf 'name: ocutalon-ci\nservices:\n  iris:\n    environment:\n      OCUTALON_EVAL: 0\n' > "$tmp/no-dummy.yml"
mkdir -p "$tmp/keyroot-none/ci"
cp "$tmp/no-dummy.yml" "$tmp/keyroot-none/ci/compose.ci.yml"
if [ "$(root=$key_root live_ci_bot_token)" = fixture-dummy-token ] && [ -z "$(root=$tmp/keyroot-none live_ci_bot_token)" ]; then
  pass "live_ci_bot_token: the dummy is read from ci/compose.ci.yml, and is empty when the file sets none"
else
  fail "live_ci_bot_token does not read the dummy from the CI override"
fi
check_count() { # check_count <label> <want> <ANTHROPIC_API_KEY or -> <TELEGRAM_BOT_TOKEN or -> [<root>]
  local got
  got=$(key_count "$3" "$4" "${5:-}")
  if [ "$got" = "$2" ]; then pass "live_key_count: $1"; else fail "live_key_count: $1 (wanted $2, got '$got')"; fi
}
check_count "no key variable counts 0" 0 - -
check_count "the CI dummy bot token alone counts 0" 0 - fixture-dummy-token
check_count "a model key counts 1" 1 anything -
check_count "a model key with the dummy counts 1" 1 anything fixture-dummy-token
check_count "the decoy bot token counts 1" 1 - decoy
check_count "a bot token of the dummy plus a character counts 1" 1 - fixture-dummy-token-x
check_count "a bot token of the dummy less a character counts 1" 1 - fixture-dummy-toke
check_count "an empty bot token counts 0" 0 - ""
check_count "a model key and the decoy bot token count 2" 2 decoy decoy
check_count "any bot token counts 1 when the CI override sets no dummy" 1 - fixture-dummy-token "$tmp/keyroot-none"
check_count "a case-changed dummy counts 1" 1 - FIXTURE-DUMMY-TOKEN
# live_no_bot_token adds one compose file, last, that sets the iris service's token to the empty value, and live_pop_file takes it off.
LIVE_FILES=(a b)
live_no_bot_token
if [ "${#LIVE_FILES[@]}" -eq 3 ] && [ "${LIVE_FILES[2]}" = "$tmp/no-bot-token.yml" ] \
  && [ "$(cat "$tmp/no-bot-token.yml")" = 'services:
  iris:
    environment:
      TELEGRAM_BOT_TOKEN: ""' ]; then
  pass "live_no_bot_token: adds one file, last, that sets the iris service's TELEGRAM_BOT_TOKEN to the empty value"
else
  fail "live_no_bot_token does not add the empty-token file as the last compose file (${#LIVE_FILES[@]} files)"
fi
live_pop_file
if [ "${#LIVE_FILES[@]}" -eq 2 ] && [ "${LIVE_FILES[1]}" = b ]; then
  pass "live_pop_file: takes the empty-token file off again"
else
  fail "live_pop_file does not take the empty-token file off (${#LIVE_FILES[@]} files)"
fi
LIVE_FILES=()
out=$( ( dc() { echo 0; }; pass() { echo "VERDICT PASS $*"; }; fail() { echo "VERDICT FAIL $*"; }; check_no_key probe ) 2>&1)
if [ "$out" = "VERDICT PASS probe: the container holds no model key and no bot token but the CI dummy" ]; then
  pass "check_no_key: a count of 0 passes"
else
  fail "check_no_key: a count of 0 does not pass ($out)"
fi
out=$( ( dc() { echo 2; }; pass() { echo "VERDICT PASS $*"; }; fail() { echo "VERDICT FAIL $*"; }; check_no_key probe ) 2>&1)
if [ "$out" = "VERDICT FAIL probe: the container holds '2' key variable(s), so a start in it is not a start with no key" ]; then
  pass "check_no_key: a count of 2 fails, and prints the count only"
else
  fail "check_no_key: a count of 2 does not fail as it should ($out)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-lib-live: $fails check(s) failed"
  exit 1
fi
echo "test-lib-live: all checks passed"
