#!/usr/bin/env bash
# Hermetic test of docker/healthcheck.sh (matrix rows 1 to 6).
# A fake `iris` on PATH logs its arguments and prints a recorded build 154 qlist line,
# and temporary files stand in for the version file and the ready marker.
# Prints one PASS or FAIL line per row; exits 0 only when every row passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/docker/healthcheck.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-hc.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
cat > "$tmp/bin/iris" <<'FAKE'
#!/bin/sh
echo "$*" >> "$HC_IRIS_LOG"
if [ "$1" = qlist ]; then
  cat "$HC_QLIST_FILE"
else
  exit 64
fi
FAKE
chmod 755 "$tmp/bin/iris"

printf '%s\n' 'IRIS^/usr/irissys^2026.3.0AI.154.0com^down, last used Thu Sep 24 18:31:12 2026^iris.cpf^1972^52773^0^^IRISHealth^^^/usr/irissys^1972' > "$tmp/qlist.down"
printf '%s\n' 'IRIS^/usr/irissys/^2026.3.0AI.154.0com^running, since Sun Oct 18 14:37:45 2026^iris.cpf^1972^52773^0^ok^IRISHealth^^^/durable/iris/^1972' > "$tmp/qlist.running"

# Use dash when present: it is the image's /bin/sh.
if command -v dash >/dev/null 2>&1; then
  shell=dash
else
  shell=sh
fi

: > "$tmp/iris.log"
fails=0

# run_hc <qlist file> <version file text or ""> <marker text, or NOMARKER for no marker file>
# Text is written exactly as given (printf '%b'), so callers control the trailing newline.
run_hc() {
  rm -f "$tmp/version" "$tmp/marker"
  printf '%b' "$2" > "$tmp/version"
  if [ "$3" != NOMARKER ]; then
    printf '%b' "$3" > "$tmp/marker"
  fi
  PATH="$tmp/bin:$PATH" \
    HC_IRIS_LOG="$tmp/iris.log" HC_QLIST_FILE="$1" \
    OCUTALON_VERSION_FILE="$tmp/version" OCUTALON_READY_MARKER="$tmp/marker" \
    "$shell" "$script" >/dev/null 2>&1
}

# expect <row label> <expected: zero|nonzero> <exit status>
expect() {
  local ok=0
  if [ "$2" = zero ] && [ "$3" -eq 0 ]; then ok=1; fi
  if [ "$2" = nonzero ] && [ "$3" -ne 0 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS $1 (exit $3)"
  else
    echo "FAIL $1 (exit $3, wanted $2)"
    fails=$((fails + 1))
  fi
}

run_hc "$tmp/qlist.down" '0.1.0\n' '0.1.0\n'
expect "row 1 IRIS down" nonzero $?

run_hc "$tmp/qlist.running" '0.1.0\n' NOMARKER
expect "row 2 no marker" nonzero $?

run_hc "$tmp/qlist.running" '0.1.0\n' '0.0.9\n'
expect "row 3 other version" nonzero $?

run_hc "$tmp/qlist.running" '0.1.0\n' '0.1.0\n'
expect "row 4 ready" zero $?

run_hc "$tmp/qlist.running" '' ''
expect "row 5 empty version" nonzero $?

# Row 6: rows 1 to 5 called the fake iris, and every call was `qlist` and nothing else.
calls=$(wc -l < "$tmp/iris.log" | tr -d ' ')
other=$(grep -vxc 'qlist' "$tmp/iris.log")
if [ "$calls" -ge 5 ] && [ "$other" -eq 0 ]; then
  echo "PASS row 6 no session (iris called $calls times, only qlist)"
else
  echo "FAIL row 6 no session (iris called $calls times, $other not qlist)"
  fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
  echo "test-healthcheck: $fails row(s) failed"
  exit 1
fi
echo "test-healthcheck: all rows passed"
