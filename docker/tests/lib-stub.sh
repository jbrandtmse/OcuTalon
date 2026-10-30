# Scaffolding shared by the hermetic tests that stand a local Node server in for a host (test-probe.sh and test-online-host.sh;
# Story 29.3). Sourced, not run, by a script that has set -u: it makes the script's temporary folder, installs the cleanup trap, and
# defines the tools check, pass and fail (counting in fails) and stub_start. Never source it together with lib-live.sh, whose pass and
# fail it would replace.
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
