#!/usr/bin/env bash
# The key proof (Story 9.10, owner condition U-166 (b); AD-19, AD-22). It runs in the evaluation job of .github/workflows/lane-a.yml, after
# eval/run.sh, and the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash eval/key-proof.sh
# It builds a fake model key at run time (the shape of a real one, so that redaction and the key-like patterns treat it as one: a vendor prefix, a
# version, a marker and 40 random letters and digits, 66 characters in all, put together from fragments so that no file holds it) and runs
#   bash eval/run.sh --release-candidate --on-mock --key-path
# with it as ANTHROPIC_API_KEY. The key goes through eval/compose.release-candidate.yml into the iris container of a throwaway whose model requests
# all go to the CI mock, and eval/run.sh proves before its teardown that the key is in no global, store, trace message, container log, container
# file, file of the run or file below eval/ (eight "PASS key proof <label>" lines). This script then checks what the run cannot check about itself:
#   1. the run exited 0, and its captured output holds the eight PASS key proof lines, "VERDICT blocked" and "eval/run: all checks passed", and no
#      line that holds the key;
#   2. no file below eval/, no file of the checkout written during the run (outside .git/) and no file of the report folder holds the key;
#   3. git status --porcelain -- eval/ is what it was before the run;
#   4. the teardown of the run's tag, run again after the exit, removes 0 projects and finds 0 leftover containers and 0 leftover volumes.
# The output of the run is printed only when its capture is clean; otherwise only the numbers of the lines that hold the key are printed. The key's
# value is passed to eval/run.sh's environment only: it is never an argument, never printed and never written to a file other than the private
# capture of the run's output, which is scanned and removed with its folder when the script ends.
# Variables:
#   OCUTALON_RUN_TAG   required: the run tag of ci/iris.sh. The script exits 2 without it, before anything runs. It is the tag of the evaluation job,
#                      so the job's own teardown step covers this run as well. The lane variables (OCUTALON_LOCK_DIR, OCUTALON_LOCK_OWNER,
#                      OCUTALON_TEST_WEB_PORT) are passed through
#   ANTHROPIC_API_KEY  any value that the caller holds is unset first, and is never used
#   RUNNER_TEMP, TMPDIR  where the private work folder is made (mktemp -d)
# Exit codes: 0 every check passed, 1 a check failed, 2 no run tag. The last line is "eval/key-proof: all checks passed" or
# "eval/key-proof: <n> check(s) failed".
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-keys.sh"
export -f key_value_hits

unset ANTHROPIC_API_KEY
if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
  echo "FAIL OCUTALON_RUN_TAG is not set: the key proof needs the run tag of the job (its teardown removes what this run started)"
  exit 2
fi

fails=0
pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ocutalon-key-proof.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/report" || exit 1
capture="$work/capture.txt"

# The fake key: fragments, put together here and nowhere else.
part_a=sk-
part_b=ant-
part_c=api03-
part_d=ocutalonfake-
random=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2> /dev/null | head -c 40)
if [ "${#random}" -ne 40 ]; then
  echo "FAIL the random part of the fake key could not be made"
  exit 1
fi
fake="${part_a}${part_b}${part_c}${part_d}${random}"
if [ "${#fake}" -ne 66 ]; then
  echo "FAIL the fake key is not 66 characters long"
  exit 1
fi

# --- 1. the run ---

echo "INFO pre-clear: removing what the tag $OCUTALON_RUN_TAG may have left"
bash ci/iris.sh teardown 2>&1 | sed 's/^/INFO /'

status_before=$(git status --porcelain -- eval/ 2> /dev/null)
touch "$work/stamp"
sleep 1
begun=$SECONDS
ANTHROPIC_API_KEY=$fake OCUTALON_EVAL_REPORT_DIR="$work/report" bash eval/run.sh --release-candidate --on-mock --key-path > "$capture" 2>&1
run_status=$?
echo "INFO the run ended with exit code $run_status after $((SECONDS - begun)) s"

# --- 2. what the run printed ---

capture_hits=$(ANTHROPIC_API_KEY=$fake key_value_hits "$capture" | cut -d: -f2 | paste -s -d, -)
if [ -n "$capture_hits" ]; then
  fail "the captured output holds the key at line(s) $capture_hits; the output is not printed"
else
  pass "the captured output holds no line with the key"
  cat "$capture"
fi
if [ "$run_status" -eq 0 ]; then
  pass "eval/run.sh --release-candidate --on-mock --key-path exited 0"
else
  fail "eval/run.sh --release-candidate --on-mock --key-path exited $run_status"
fi
proofs=$(grep -c '^PASS key proof ' "$capture" || true)
labels=$(grep '^PASS key proof ' "$capture" | sed 's/^PASS key proof \([^:]*\):.*/\1/' | sort | paste -s -d, -)
if [ "$proofs" -eq 8 ] && [ "$labels" = "container files,container logs,eval files,globals,mock log,run files,stores,trace" ]; then
  pass "the capture holds the eight PASS key proof lines"
else
  fail "the capture holds $proofs PASS key proof line(s) (labels: ${labels:-none}), not the eight"
fi
if grep -q '^FAIL key proof ' "$capture"; then fail "the capture holds a FAIL key proof line"; fi
grep -qx 'VERDICT blocked' "$capture" && pass "the capture holds VERDICT blocked" || fail "the capture has no line VERDICT blocked"
grep -qx 'eval/run: all checks passed' "$capture" && pass "the capture holds eval/run: all checks passed" || fail "the capture has no line eval/run: all checks passed"

# --- 3. the files ---

# file_hits <find operands>: file:line for each file that holds the key and unreadable:<file> for each file that cannot be read, joined by commas
file_hits() {
  find "$@" -print0 | ANTHROPIC_API_KEY=$fake xargs -0 bash -c 'for f in "$@"; do key_value_hits "$f" || echo "unreadable:$f"; done' _ | paste -s -d, -
}
eval_files=$(find eval -type f | wc -l | tr -d ' ')
eval_hits=$(file_hits eval -type f)
if [ "$eval_files" -gt 0 ] && [ -z "$eval_hits" ]; then pass "none of the $eval_files file(s) below eval/ holds the key"; else fail "files below eval/ hold the key or cannot be read (read $eval_files file(s)): ${eval_hits:-none}"; fi
written=$(find . -path ./.git -prune -o -type f -newer "$work/stamp" -print | wc -l | tr -d ' ')
written_hits=$(file_hits . -path ./.git -prune -o -type f -newer "$work/stamp")
if [ -z "$written_hits" ]; then pass "none of the $written file(s) of the checkout written during the run holds the key"; else fail "files of the checkout written during the run hold the key or cannot be read: $written_hits"; fi
report_files=$(find "$work/report" -type f | wc -l | tr -d ' ')
report_hits=$(file_hits "$work/report" -type f)
if [ "$report_files" -gt 0 ] && [ -z "$report_hits" ]; then pass "none of the $report_files file(s) of the report folder holds the key"; else fail "the report folder has $report_files file(s), hits or unreadable: ${report_hits:-none}"; fi
status_after=$(git status --porcelain -- eval/ 2> /dev/null)
if [ "$status_after" = "$status_before" ]; then pass "git status --porcelain -- eval/ is as it was before the run"; else fail "git status --porcelain -- eval/ changed during the run"; fi

# --- 4. the teardown ---

teardown=$(bash ci/iris.sh teardown 2>&1)
printf '%s\n' "$teardown" | grep '^TEARDOWN' | sed 's/^/INFO /'
if printf '%s\n' "$teardown" | grep -qE ' 0 project\(s\) removed, 0 leftover container\(s\), 0 leftover volume\(s\)'; then
  pass "the teardown of the tag finds 0 projects, 0 containers and 0 volumes"
else
  fail "the teardown of the tag found something left after the run"
fi

if [ "$fails" -ne 0 ]; then
  echo "eval/key-proof: $fails check(s) failed"
  exit 1
fi
echo "eval/key-proof: all checks passed"
