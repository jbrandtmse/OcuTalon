# Scaffolding shared by the hermetic tests that stand a local Node server in for a host (test-probe.sh and test-online-host.sh;
# Story 29.3). Sourced, not run, by a script that has set -u: it makes the script's temporary folder, installs the cleanup trap, and
# defines the tools check, pass and fail (counting in fails), stub_start, and the credential shim (curl_shim and shim_checks, Story 29.8).
# Never source it together with lib-live.sh, whose pass and fail it would replace.
#   tmp         a new folder, removed on exit
#   stub_pid    the pid of the server stub_start started (killed on exit), stub_port its port on 127.0.0.1
#   fails       the number of failed checks

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-stub-test.XXXXXX") || exit 1
stub_pid=""
stub_port=""
fails=0
cleanup() {
  if [ -n "$stub_pid" ]; then kill "$stub_pid" 2> /dev/null; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

# need_tools <tool>...: exits 1 with a FAIL line for the first tool that is not installed.
need_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      echo "FAIL $tool is not installed"
      exit 1
    fi
  done
}

# stub_start [<argument>...]: runs the Node program on standard input with the arguments (process.argv.slice(2)) on 127.0.0.1, port 0,
# in the background, and waits until it has printed its port on its first line. Sets stub_pid and stub_port; fails (status 1, a FAIL
# line, the first bytes of its stderr) when no port comes in 5 s. Environment variables set on the call reach the program.
stub_start() {
  local _
  cat > "$tmp/stub.js"
  : > "$tmp/stub.port"
  node "$tmp/stub.js" "$@" > "$tmp/stub.port" 2> "$tmp/stub.err" < /dev/null &
  stub_pid=$!
  stub_port=""
  for _ in $(seq 1 50); do
    stub_port=$(head -n 1 "$tmp/stub.port" 2> /dev/null)
    if [ -n "$stub_port" ]; then break; fi
    sleep 0.1
  done
  case $stub_port in
    '' | *[!0-9]*)
      echo "FAIL the stub server did not start: $(head -c 300 "$tmp/stub.err")"
      return 1
      ;;
  esac
  return 0
}

# curl_shim <folder> [strip-interface]: writes an executable curl in <folder> (put the folder first in the PATH of the script under test)
# that logs each call to the file SHIM_LOG and then runs the real curl, SHIM_REAL. A call logs three kinds of line: ARGV (every argument
# in brackets; one write per call, so that parallel calls do not interleave), ENV (the number of OCUTALON_GATE_* variables in its environment) and CFG 600 or CFG other (the mode of the file that
# follows -K). With strip-interface the ARGV line still shows --interface <value>, and the pair is dropped before the real curl runs
# (the test addresses are not addresses of this machine).
curl_shim() {
  local strip=0
  if [ "${2:-}" = strip-interface ]; then strip=1; fi
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo "strip=$strip"
    cat << 'SHIM'
msg="ARGV"
for a in "$@"; do msg="$msg [$a]"; done
msg="$msg
ENV $(env | grep -c '^OCUTALON_GATE_')"
prev=""
for a in "$@"; do
  if [ "$prev" = -K ]; then
    if [ -n "$(find "$a" -perm 600 2> /dev/null)" ]; then msg="$msg
CFG 600"; else msg="$msg
CFG other"; fi
  fi
  prev=$a
done
printf '%s\n' "$msg" >> "$SHIM_LOG"
if [ "$strip" = 1 ]; then
  n=$#
  i=0
  skip=0
  while [ "$i" -lt "$n" ]; do
    a=$1
    shift
    if [ "$skip" = 1 ]; then
      skip=0
    elif [ "$a" = --interface ]; then
      skip=1
    else
      set -- "$@" "$a"
    fi
    i=$((i + 1))
  done
fi
exec "$SHIM_REAL" "$@"
SHIM
  } > "$1/curl"
  chmod 755 "$1/curl"
}

# shim_checks <log> <label> <secret>...: from the log of curl_shim, prints a PASS or FAIL line each for: no secret on any command line,
# no OCUTALON_GATE_* variable in any curl's environment, and every -K file of mode 600. A run must log at least shim_min calls (20 by
# default; a caller sets the variable for a larger run) and read the mode 600 configuration in more than that many calls. At least one
# secret is required.
shim_min=20
shim_checks() {
  local log=$1 label=$2 argv_n cred_argv env_bad cfg_ok cfg_bad s secrets=()
  shift 2
  if [ $# -eq 0 ]; then
    fail "$label: shim_checks needs at least one secret"
    return 0
  fi
  for s in "$@"; do secrets+=(-e "$s"); done
  argv_n=$(grep -c '^ARGV' "$log")
  cred_argv=$(grep -cF ${secrets[@]+"${secrets[@]}"} "$log")
  env_bad=$(grep '^ENV ' "$log" | grep -vc '^ENV 0$')
  cfg_ok=$(grep -c '^CFG 600' "$log")
  cfg_bad=$(grep -c '^CFG other' "$log")
  if [ "$argv_n" -gt "$shim_min" ] && [ "$cred_argv" = 0 ]; then
    pass "$label: the secrets are on none of the $argv_n command lines"
  else
    fail "$label: $cred_argv of $argv_n command lines hold a secret"
  fi
  if [ "$env_bad" = 0 ] && [ "$argv_n" -gt "$shim_min" ]; then
    pass "$label: no curl inherits OCUTALON_GATE_USER or OCUTALON_GATE_PASSWORD"
  else
    fail "$label: $env_bad curl call(s) inherit a gate variable"
  fi
  if [ "$cfg_ok" -gt "$shim_min" ] && [ "$cfg_bad" = 0 ]; then
    pass "$label: the gate's curl configuration is mode 600 in all $cfg_ok calls that read it"
  else
    fail "$label: $cfg_ok calls read a mode 600 configuration, $cfg_bad another mode"
  fi
}
