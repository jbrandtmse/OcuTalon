#!/usr/bin/env bash
# Hermetic test of docker/after-start.sh (matrix rows 8 to 10, and the shell side of rows 1 and 7), and of the
# merge retry: a merge that fails with ERROR #453: is retried once, after a pause, on a fresh copy, with one
# `STEP merge RETRY 1 after #453` line; any other failure, a near-miss number and a copy failure are not retried.
# A fake `iris` on PATH records its calls and what it sees, and answers `merge` (one result per call, from a
# list) and `session` from the environment; a fake `mv` and a fake `sleep` record their arguments (the sleep
# does not wait). Temporary directories stand in for /durable and the image.
# The script runs on the host, under the host's bash (3.2 on macOS).
# Prints one PASS or FAIL line per check; exits 0 only when every check passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/docker/after-start.sh"
bashbin=/bin/bash
[ -x "$bashbin" ] || bashbin=bash

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-as.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/durable" "$tmp/image"
cat > "$tmp/bin/iris" <<'FAKE'
#!/bin/sh
case "$1" in
  merge)
    echo "$*" >> "$FAKE_CALLS"
    if [ -f "$FAKE_MARKER" ]; then echo "merge-saw-marker" >> "$FAKE_CALLS"; fi
    if cmp -s "$3" "$FAKE_MERGE_FILE"; then echo "merge-file-matches" >> "$FAKE_CALLS"; fi
    echo "$3" >> "$FAKE_MERGE_ARG"
    n=0
    if [ -f "$FAKE_MERGE_COUNT" ]; then n=$(cat "$FAKE_MERGE_COUNT"); fi
    n=$((n + 1))
    echo "$n" > "$FAKE_MERGE_COUNT"
    tok=$(echo "$FAKE_MERGE_SEQ" | awk -v n="$n" '{print $n}')
    case "$tok" in
      453)
        echo "IRIS Merge of $3 into /durable/iris/iris.cpf"
        echo "ERROR #453: Cannot quiesce the system for namespace reactivation"
        echo "IRIS Merge failed"
        exit 7
        ;;
      E5001)
        echo "ERROR #5001: merge failed on purpose"
        exit 7
        ;;
      E4530)
        echo "ERROR #4530: near miss of the quiesce number"
        exit 7
        ;;
      "")
        echo "fake iris: no merge result left for call $n"
        exit 99
        ;;
      *)
        exit "$tok"
        ;;
    esac
    ;;
  session)
    echo "$*" >> "$FAKE_CALLS"
    if [ -f "$FAKE_MARKER" ]; then echo "session-saw-marker" >> "$FAKE_CALLS"; fi
    echo "$OCUTALON_IMAGE_VERSION" > "$FAKE_ENV_VERSION"
    echo "$OCUTALON_PUBLIC_CLASSES" > "$FAKE_ENV_CLASSES"
    cat > "$FAKE_STDIN"
    cat "$FAKE_TRANSCRIPT"
    exit "${FAKE_SESSION_RC:-0}"
    ;;
  *)
    exit 64
    ;;
esac
FAKE
cat > "$tmp/bin/mv" <<'FAKE'
#!/bin/sh
echo "mv $*" >> "$FAKE_CALLS"
exec /bin/mv "$@"
FAKE
cat > "$tmp/bin/sleep" <<'FAKE'
#!/bin/sh
echo "sleep $*" >> "$FAKE_CALLS"
echo "FAKE-SLEEP $*"
exit 0
FAKE
chmod 755 "$tmp/bin/iris" "$tmp/bin/mv" "$tmp/bin/sleep"

# The files of the image.
printf '0.1.0\n' > "$tmp/image/version"
printf '[Actions]\n' > "$tmp/image/merge.cpf"
printf 'Halt\n' > "$tmp/image/after-start.cos"
mkdir -p "$tmp/image/src/ocutalon/cls/OcuTalon/Data/Public" "$tmp/image/src/ocutalon/cls/OcuTalon/Web/Public/Sub" \
  "$tmp/image/src/ocutalon/cls/OcuTalon/Data/Private"
: > "$tmp/image/src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls"
: > "$tmp/image/src/ocutalon/cls/OcuTalon/Web/Public/Login.cls"
: > "$tmp/image/src/ocutalon/cls/OcuTalon/Web/Public/Sub/Page.cls"
: > "$tmp/image/src/ocutalon/cls/OcuTalon/Data/Private/Secret.cls"
: > "$tmp/image/src/ocutalon/cls/OcuTalon/Web/Public/notes.txt"
mkdir -p "$tmp/image/empty-src"

# The session transcripts the fake iris prints.
cat > "$tmp/transcript.ok" <<'EOT'
%SYS>
OCUTALON>
STEP readiness nothing to clear
STEP ipm installed 0.10.10 (was none)
STEP package loaded (not installed)
STEP Bridge.Installer OK 0.0s
STEP SSL OK 0.0s
STEP Ready OK 0.0s
RESULT OK 0.1.0
OCUTALON>
EOT
cat > "$tmp/transcript.ssl" <<'EOT'
STEP Bridge.Installer OK 0.0s
STEP SSL FAILED ERROR #5001: SSL failed on purpose
RESULT FAILED 0.1.0
EOT
cat > "$tmp/transcript.noresult" <<'EOT'
STEP Bridge.Installer OK 0.0s
EOT
cat > "$tmp/transcript.other" <<'EOT'
STEP Bridge.Installer OK 0.0s
RESULT OK 9.9.9
EOT

marker="$tmp/durable/ocutalon.ready"
log="$tmp/durable/ocutalon-after-start.log"
fails=0

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
check() { # check <label> <command...>: passes when the command succeeds
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

# run_script <transcript> <merge results> <session exit> <old marker text or NONE> [source directory] [merge file]
# <merge results> is a space-separated list, one token per merge call: 453 (the real three-line #453 output, exit 7),
# E5001 and E4530 (one ERROR line, exit 7), or a plain exit code with no output.
# Runs the script once. Leaves its exit status in $rc, its output in $tmp/stdout.
run_script() {
  local src=${5:-$tmp/image/src}
  local mergefile=${6:-$tmp/image/merge.cpf}
  rm -f "$tmp/calls" "$tmp/stdin" "$tmp/stdout" "$tmp/env-version" "$tmp/env-classes" "$tmp/merge-arg" "$tmp/merge-count"
  : > "$tmp/calls"
  rm -f "$marker" "$marker".tmp.*
  if [ "$4" != NONE ]; then
    printf '%s\n' "$4" > "$marker"
    printf 'stale\n' > "$marker.tmp.1"
  fi
  PATH="$tmp/bin:$PATH" \
    FAKE_CALLS="$tmp/calls" FAKE_MARKER="$marker" FAKE_STDIN="$tmp/stdin" FAKE_TRANSCRIPT="$1" \
    FAKE_ENV_VERSION="$tmp/env-version" FAKE_ENV_CLASSES="$tmp/env-classes" \
    FAKE_MERGE_FILE="$tmp/image/merge.cpf" FAKE_MERGE_ARG="$tmp/merge-arg" \
    FAKE_MERGE_COUNT="$tmp/merge-count" FAKE_MERGE_SEQ="$2" FAKE_SESSION_RC="$3" \
    ANTHROPIC_API_KEY=canary-key-1f9d TELEGRAM_BOT_TOKEN=canary-token-7c2e \
    OCUTALON_VERSION_FILE="$tmp/image/version" OCUTALON_READY_MARKER="$marker" \
    OCUTALON_MERGE_FILE="$mergefile" OCUTALON_SRC_DIR="$src" \
    OCUTALON_SESSION_SCRIPT="$tmp/image/after-start.cos" OCUTALON_AFTER_START_LOG="$log" \
    TMPDIR="${run_tmpdir:-${TMPDIR:-/tmp}}" \
    "$bashbin" "$script" > "$tmp/stdout" 2>&1
  rc=$?
}

no_marker() { [ ! -e "$marker" ]; }
no_tmp_files() { ! ls "$marker".tmp.* >/dev/null 2>&1; }
log_has() { grep -q -- "$1" "$log"; }
stdout_has() { grep -q -- "$1" "$tmp/stdout"; }
calls_have() { grep -q -- "$1" "$tmp/calls"; }
calls_lack() { ! grep -q -- "$1" "$tmp/calls"; }
merge_before_session() {
  local m s
  m=$(grep -n '^merge ' "$tmp/calls" | head -n 1 | cut -d: -f1)
  s=$(grep -n '^session ' "$tmp/calls" | head -n 1 | cut -d: -f1)
  [ -n "$m" ] && [ -n "$s" ] && [ "$m" -lt "$s" ]
}
count_is() { # count_is <file> <pattern> <n>: the pattern matches exactly n lines of the file
  [ "$(grep -c -- "$2" "$1")" -eq "$3" ]
}
line_of() { # line_of <file> <pattern> [first|last]: the number of the first or last line that matches
  if [ "${3:-first}" = last ]; then grep -n -- "$2" "$1" | tail -n 1 | cut -d: -f1; else grep -n -- "$2" "$1" | head -n 1 | cut -d: -f1; fi
}
before() { # before <n1> <n2>: both are line numbers and n1 comes first
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]
}
copies_ok() { # copies_ok <n>: n merges, each of its own copy, and no copy is left
  local paths c
  paths=$(cat "$tmp/merge-arg" 2>/dev/null)
  [ "$(printf '%s\n' "$paths" | grep -c .)" -eq "$1" ] || return 1
  [ "$(printf '%s\n' "$paths" | sort -u | grep -c .)" -eq "$1" ] || return 1
  for c in $paths; do
    [ "$c" != "$tmp/image/merge.cpf" ] || return 1
    [ ! -e "$c" ] || return 1
  done
}
no_retry() { # no RETRY line in the log or on stdout, and no sleep
  ! grep -q '^STEP merge RETRY' "$log" "$tmp/stdout" && count_is "$tmp/calls" '^sleep ' 0
}
no_secret_printed() { ! grep -q 'canary-' "$tmp/stdout" "$log"; }

# --- the success path ---

run_script "$tmp/transcript.ok" 0 0 0.0.9
check "success: exit 0" test "$rc" -eq 0
check "success: the marker holds the image's version" test "$(cat "$marker" 2>/dev/null)" = 0.1.0
check "success: the marker was written through a temporary file in its directory and renamed" \
  grep -q "^mv -f $marker.tmp.[0-9]* $marker\$" "$tmp/calls"
check "success: no temporary file is left" no_tmp_files
check "success: the log and the marker are all that /durable holds" test "$(ls "$tmp/durable" | tr '\n' ' ')" = "ocutalon-after-start.log ocutalon.ready "
check "success: the merge ran before the session" merge_before_session
check "success: the merge ran on IRIS with a copy of the merge file, not the file itself (iris merge skips a file with an unchanged record)" \
  bash -c "grep -q '^merge IRIS ' '$tmp/calls' && grep -q '^merge-file-matches\$' '$tmp/calls' && [ \"\$(cat '$tmp/merge-arg')\" != '$tmp/image/merge.cpf' ]"
check "success: the copy of the merge file is removed" bash -c "[ ! -e \"\$(cat '$tmp/merge-arg')\" ]"
check "success: the old marker was gone before the merge, so no health probe during the merge sees it" calls_lack '^merge-saw-marker$'
check "success: the marker was gone at the session" calls_lack '^session-saw-marker$'
check "success: the session is IRIS in %SYS" calls_have "^session IRIS -U %SYS\$"
check "success: the session reads the session script" cmp -s "$tmp/stdin" "$tmp/image/after-start.cos"
check "success: the image's version reaches the session" test "$(cat "$tmp/env-version")" = 0.1.0
check "success: the public classes reach the session, sorted, from the .cls files of both public packages" \
  test "$(cat "$tmp/env-classes")" = "OcuTalon.Data.Public.Settings,OcuTalon.Web.Public.Login,OcuTalon.Web.Public.Sub.Page"
check "success: the summary lines go to stdout" stdout_has '^STEP Ready OK 0.0s$'
check "success: the log starts with the begin stamp" test "$(head -n 1 "$log" | sed -n 's/^AFTER-START begin [0-9T:Z-]*$/ok/p')" = ok
check "success: the log ends with the end line" test "$(tail -n 1 "$log" | sed -n 's/^AFTER-START end [0-9T:Z-]* ready 0.1.0$/ok/p')" = ok
check "success: the log keeps the session's lines and drops its prompts" \
  bash -c "grep -q '^STEP Bridge.Installer OK' '$log' && ! grep -q '^[%A-Z]*>' '$log'"
check "success: nothing of the environment is printed" no_secret_printed

# A second run rewrites the log.
run_script "$tmp/transcript.ok" 0 0 NONE
check "success without an old marker: the marker is written" test "$(cat "$marker" 2>/dev/null)" = 0.1.0
check "the log is rewritten at every start" test "$(grep -c '^AFTER-START begin' "$log")" -eq 1

run_script "$tmp/transcript.ok" 0 0 NONE "$tmp/image/empty-src"
check "no public packages: the session gets an empty class list" test "$(cat "$tmp/env-classes")" = ""
check "no public packages: the run still succeeds" test "$(cat "$marker" 2>/dev/null)" = 0.1.0

# --- row 8: the merge fails ---

run_script "$tmp/transcript.ok" 7 0 0.1.0
check "row 8 merge fails: exit 0" test "$rc" -eq 0
check "row 8 merge fails: the old marker is removed" no_marker
check "row 8 merge fails: its stale temporary files are removed" no_tmp_files
check "row 8 merge fails: no session is started" calls_lack '^session '
check "row 8 merge fails: the log names the merge and its exit status" log_has '^STEP merge FAILED exit 7$'
check "row 8 merge fails: the log ends with the end line" test "$(tail -n 1 "$log" | sed -n 's/^AFTER-START end [0-9T:Z-]* not ready$/ok/p')" = ok

check "row 8 merge fails: one merge, no retry and no sleep" bash -c "[ \"\$(grep -c '^merge ' '$tmp/calls')\" -eq 1 ]"
check "row 8 merge fails: no RETRY line and no sleep" no_retry

# The merge file of the image cannot be read, so the copy that is merged cannot be made: the same outcome.
run_script "$tmp/transcript.ok" 0 0 0.1.0 "$tmp/image/src" "$tmp/image/no-such-merge.cpf"
check "row 8 merge file missing: exit 0" test "$rc" -eq 0
check "row 8 merge file missing: the old marker is removed" no_marker
check "row 8 merge file missing: no merge and no session is started" bash -c "! grep -q '^merge ' '$tmp/calls' && ! grep -q '^session ' '$tmp/calls'"
check "row 8 merge file missing: the log names the merge" log_has '^STEP merge FAILED exit 1$'
check "row 8 merge file missing: the log says which file could not be copied" log_has "could not copy $tmp/image/no-such-merge.cpf"
check "row G merge file missing: no RETRY line and no sleep" no_retry

# No temporary directory can be made for the copy: the same outcome, and the log names the directory.
run_tmpdir="$tmp/no-such-tmp"
run_script "$tmp/transcript.ok" 0 0 0.1.0
run_tmpdir=""
check "row 8 no temporary directory: exit 0, the old marker removed, no merge and no session" \
  bash -c "[ $rc -eq 0 ] && [ ! -e '$marker' ] && ! grep -q '^merge ' '$tmp/calls' && ! grep -q '^session ' '$tmp/calls'"
check "row 8 no temporary directory: the log names the merge and the directory" \
  bash -c "grep -q '^STEP merge FAILED exit 1\$' '$log' && grep -q 'could not create a temporary directory in $tmp/no-such-tmp' '$log'"
check "row G no temporary directory: no RETRY line and no sleep" no_retry

# --- the merge retry ---

# Row A: #453, then OK.
run_script "$tmp/transcript.ok" "453 0" 0 0.0.9
check "row A #453 then OK: exit 0" test "$rc" -eq 0
check "row A #453 then OK: two merges" count_is "$tmp/calls" '^merge ' 2
check "row A #453 then OK: each merge has its own copy and every copy is removed" copies_ok 2
check "row A #453 then OK: exactly one RETRY line in the log, in the exact form" count_is "$log" '^STEP merge RETRY' 1
check "row A #453 then OK: the RETRY line reads RETRY 1 after #453" count_is "$log" '^STEP merge RETRY 1 after #453$' 1
check "row A #453 then OK: the RETRY line is on stdout" count_is "$tmp/stdout" '^STEP merge RETRY 1 after #453$' 1
check "row A #453 then OK: the log has the failed output, then RETRY, then OK" \
  bash -c "$(declare -f before line_of); before \$(line_of '$log' '^ERROR #453:') \$(line_of '$log' '^STEP merge RETRY') && before \$(line_of '$log' '^STEP merge RETRY') \$(line_of '$log' '^STEP merge OK ')"
check "row A #453 then OK: the RETRY line comes before the last STEP merge line" \
  bash -c "$(declare -f before line_of); before \$(line_of '$log' '^STEP merge RETRY') \$(line_of '$log' '^STEP merge ' last)"
check "row A #453 then OK: one OK line and no FAILED line" bash -c "[ \"\$(grep -c '^STEP merge OK [0-9]*s\$' '$log')\" -eq 1 ] && ! grep -q '^STEP merge FAILED' '$log'"
check "row A #453 then OK: one pause of 10 s, and no other sleep" bash -c "[ \"\$(grep -c '^sleep 10\$' '$tmp/calls')\" -eq 1 ] && [ \"\$(grep -c '^sleep ' '$tmp/calls')\" -eq 1 ]"
check "row A #453 then OK: the RETRY line is written before the pause" \
  bash -c "$(declare -f before line_of); before \$(line_of '$tmp/stdout' '^STEP merge RETRY') \$(line_of '$tmp/stdout' '^FAKE-SLEEP 10\$')"
check "row A #453 then OK: both merges got the merge file's content" count_is "$tmp/calls" '^merge-file-matches$' 2
check "row A #453 then OK: the pause is between the merges" \
  bash -c "$(declare -f before line_of); before \$(line_of '$tmp/calls' '^merge ') \$(line_of '$tmp/calls' '^sleep ') && before \$(line_of '$tmp/calls' '^sleep ') \$(line_of '$tmp/calls' '^merge ' last)"
check "row A #453 then OK: the session runs" calls_have '^session '
check "row A #453 then OK: the marker holds the version" test "$(cat "$marker" 2>/dev/null)" = 0.1.0
check "row A #453 then OK: the log ends ready" test "$(tail -n 1 "$log" | sed -n 's/^AFTER-START end [0-9T:Z-]* ready 0.1.0$/ok/p')" = ok
check "row A #453 then OK: the failed merge saw no marker either" calls_lack '^merge-saw-marker$'

# Row B: #453 on every try.
run_script "$tmp/transcript.ok" "453 453" 0 0.1.0
check "row B #453 twice: exit 0" test "$rc" -eq 0
check "row B #453 twice: two merges, each of its own removed copy" bash -c "$(declare -f count_is copies_ok); tmp='$tmp'; count_is '$tmp/calls' '^merge ' 2 && copies_ok 2"
check "row B #453 twice: one RETRY line, RETRY 1, in the log and on stdout" \
  bash -c "$(declare -f count_is); count_is '$log' '^STEP merge RETRY' 1 && count_is '$log' '^STEP merge RETRY 1 after #453\$' 1 && count_is '$tmp/stdout' '^STEP merge RETRY 1 after #453\$' 1"
check "row B #453 twice: one pause of 10 s, none after the last try" bash -c "$(declare -f count_is); count_is '$tmp/calls' '^sleep 10\$' 1 && count_is '$tmp/calls' '^sleep ' 1"
check "row B #453 twice: the merge failed with exit 7, after the RETRY line" \
  bash -c "$(declare -f before line_of); grep -q '^STEP merge FAILED exit 7\$' '$log' && before \$(line_of '$log' '^STEP merge RETRY') \$(line_of '$log' '^STEP merge FAILED')"
check "row B #453 twice: both merges got the merge file's content" count_is "$tmp/calls" '^merge-file-matches$' 2
check "row B #453 twice: both #453 outputs are in the log" count_is "$log" '^ERROR #453:' 2
check "row B #453 twice: no session and no marker" bash -c "[ ! -e '$marker' ] && ! grep -q '^session ' '$tmp/calls'"
check "row B #453 twice: the log ends not ready" test "$(tail -n 1 "$log" | sed -n 's/^AFTER-START end [0-9T:Z-]* not ready$/ok/p')" = ok

# Row C: another failure, with no output and with an error line.
run_script "$tmp/transcript.ok" "7 0" 0 0.1.0
check "row C exit 7 without output: one merge, no retry, no sleep, FAILED exit 7, not ready" \
  bash -c "$(declare -f count_is); count_is '$tmp/calls' '^merge ' 1 && grep -q '^STEP merge FAILED exit 7\$' '$log' && [ ! -e '$marker' ]"
check "row C exit 7 without output: no RETRY line and no sleep" no_retry
run_script "$tmp/transcript.ok" "E5001 0" 0 0.1.0
check "row C ERROR #5001: one merge, FAILED exit 7, not ready, exit 0" \
  bash -c "$(declare -f count_is); [ $rc -eq 0 ] && count_is '$tmp/calls' '^merge ' 1 && grep -q '^STEP merge FAILED exit 7\$' '$log' && [ ! -e '$marker' ]"
check "row C ERROR #5001: no RETRY line and no sleep" no_retry
check "row C ERROR #5001: the copy is removed" copies_ok 1

# Row D: a near-miss number.
run_script "$tmp/transcript.ok" "E4530 0" 0 0.1.0
check "row D ERROR #4530: one merge, FAILED exit 7, not ready, exit 0" \
  bash -c "$(declare -f count_is); [ $rc -eq 0 ] && count_is '$tmp/calls' '^merge ' 1 && grep -q '^STEP merge FAILED exit 7\$' '$log' && [ ! -e '$marker' ]"
check "row D ERROR #4530: no RETRY line and no sleep" no_retry

# Row E: #453, then another failure.
run_script "$tmp/transcript.ok" "453 E5001" 0 0.1.0
check "row E #453 then ERROR #5001: exit 0, two merges, each of its own removed copy" \
  bash -c "$(declare -f count_is copies_ok); tmp='$tmp'; [ $rc -eq 0 ] && count_is '$tmp/calls' '^merge ' 2 && copies_ok 2"
check "row E #453 then ERROR #5001: one RETRY line, RETRY 1, in the log and on stdout" \
  bash -c "$(declare -f count_is); count_is '$log' '^STEP merge RETRY' 1 && count_is '$log' '^STEP merge RETRY 1 after #453\$' 1 && count_is '$tmp/stdout' '^STEP merge RETRY 1 after #453\$' 1"
check "row E #453 then ERROR #5001: one pause of 10 s, then FAILED exit 7, not ready" \
  bash -c "$(declare -f count_is); count_is '$tmp/calls' '^sleep 10\$' 1 && count_is '$tmp/calls' '^sleep ' 1 && grep -q '^STEP merge FAILED exit 7\$' '$log' && [ ! -e '$marker' ] && ! grep -q '^session ' '$tmp/calls'"

# Row F: a first-try success.
run_script "$tmp/transcript.ok" "0 7" 0 0.0.9
check "row F first-try success: exit 0, one merge of its own removed copy, the marker written" \
  bash -c "$(declare -f count_is copies_ok); tmp='$tmp'; [ $rc -eq 0 ] && count_is '$tmp/calls' '^merge ' 1 && copies_ok 1 && [ \"\$(cat '$marker')\" = 0.1.0 ]"
check "row F first-try success: no RETRY line and no sleep" no_retry
check "row F first-try success: one OK line" count_is "$log" '^STEP merge OK [0-9]*s$' 1

# --- row 9: the session gives no result ---

run_script "$tmp/transcript.noresult" 0 0 0.1.0
check "row 9 no RESULT line: exit 0" test "$rc" -eq 0
check "row 9 no RESULT line: no marker" no_marker
check "row 9 no RESULT line: the log names the session" log_has '^STEP session FAILED no RESULT line'

run_script "$tmp/transcript.ok" 0 3 0.1.0
check "row 9 session exits non-zero: exit 0" test "$rc" -eq 0
check "row 9 session exits non-zero: no marker, though it printed a good RESULT line" no_marker
check "row 9 session exits non-zero: the log names the session and its status" log_has '^STEP session FAILED exit 3$'

# --- row 10: a result for another version ---

run_script "$tmp/transcript.other" 0 0 0.1.0
check "row 10 other version: exit 0" test "$rc" -eq 0
check "row 10 other version: no marker" no_marker
check "row 10 other version: the log names the result and the image's version" log_has "^STEP session FAILED 'RESULT OK 9.9.9', the image is 0.1.0\$"

# --- the marker cannot be written ---

marker_saved=$marker
marker="$tmp/no-such-dir/ocutalon.ready"
run_script "$tmp/transcript.ok" 0 0 NONE
check "marker not writable: exit 0" test "$rc" -eq 0
check "marker not writable: no marker and no temporary file" bash -c "[ ! -e '$marker' ] && ! ls '$marker'.tmp.* >/dev/null 2>&1"
check "marker not writable: the log names the marker" log_has '^STEP marker FAILED '
check "marker not writable: the log ends not ready" test "$(tail -n 1 "$log" | sed -n 's/^AFTER-START end [0-9T:Z-]* not ready$/ok/p')" = ok
marker=$marker_saved

# --- row 7, the shell side: a step fails ---

run_script "$tmp/transcript.ssl" 0 0 0.1.0
check "row 7 step fails: exit 0" test "$rc" -eq 0
check "row 7 step fails: no marker" no_marker
check "row 7 step fails: the log names the failed step" log_has '^STEP SSL FAILED '
check "row 7 step fails: stdout names the failed step" stdout_has '^STEP SSL FAILED '

# --- an image without a version ---

printf '' > "$tmp/image/version"
run_script "$tmp/transcript.ok" 0 0 0.1.0
check "no version: exit 0, no marker, no session" bash -c "[ $rc -eq 0 ] && [ ! -e '$marker' ] && ! grep -q '^session ' '$tmp/calls'"
check "no version: the log names the version" log_has '^STEP version FAILED'
printf '0.1.0\n' > "$tmp/image/version"

if [ "$fails" -ne 0 ]; then
  echo "test-after-start: $fails check(s) failed"
  exit 1
fi
echo "test-after-start: all checks passed"
