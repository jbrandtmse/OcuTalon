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
#     when they are not.
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

if [ "$fails" -ne 0 ]; then
  echo "test-lib-live: $fails check(s) failed"
  exit 1
fi
echo "test-lib-live: all checks passed"
