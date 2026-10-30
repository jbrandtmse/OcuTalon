#!/usr/bin/env bash
# The key proof (Story 9.10, owner condition U-166 (b); AD-19, AD-22). It runs in the evaluation job of .github/workflows/lane-a.yml, after
# eval/run.sh, and the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash eval/key-proof.sh
# It builds a fake model key at run time (the shape of a real one, so that redaction and the key-like patterns treat it as one: a vendor prefix, a
# version, a marker and 40 random letters and digits, 66 characters in all, put together from fragments so that no file holds it) and runs
#   bash eval/run.sh --release-candidate --on-mock --key-path
# with it as ANTHROPIC_API_KEY. The key goes through eval/compose.release-candidate.yml into the iris container of a throwaway whose model requests
# all go to the CI mock, and eval/run.sh proves before its teardown that the key is in no global, store, trace message, container log, container
# file, file of the run, file below eval/ or file of the web bundle (nine "PASS key proof <label>" lines and the counts line). This script then
# checks what the run cannot check about itself:
#   0. before anything starts, the model endpoint resolves to the CI mock (the last OCUTALON_MODEL_BASE_URL of eval/compose.release-candidate.yml and
#      ci/compose.ci.yml, the order in which the run layers them, and the caller's own OCUTALON_MODEL_BASE_URL when it is set: both); any other endpoint is
#      refused with exit 2 and the endpoint named (never a key), and nothing is started;
#   1. the run exited 0, and its captured output holds the nine PASS key proof lines, the counts line, "VERDICT blocked" and "eval/run: all checks
#      passed", and no line that holds the key;
#   2. no file below eval/, no file of the checkout written during the run (outside .git/) and no file of the report folder holds the key;
#   3. git status --porcelain -- eval/ is what it was before the run;
#   4. the run's own compose project (named in its output) has no container and no volume left, listed by the tool itself, and the teardown of the
#      run's tag, run again after that, removes 0 projects and finds 0 leftover containers and 0 leftover volumes;
#   5. the proof's pass line, which is counts only: "PASS key counts: iris environment 1, run output 0, container logs 0, result files 0, trace 0, web
#      bundle 0" (the key is in the iris container's environment exactly once, and nowhere else).
# The output of the run is printed only when its capture is clean; otherwise only the numbers of the lines that hold the key are printed. The key's
# value is passed to eval/run.sh's environment only: it is never an argument, never printed and never written to a file other than the private
# capture of the run's output, which is scanned and removed with its folder when the script ends.
# Variables:
#   OCUTALON_RUN_TAG   required: the run tag of ci/iris.sh. The script exits 2 without it, before anything runs. It is the tag of the evaluation job,
#                      so the job's own teardown step covers this run as well. The lane variables (OCUTALON_LOCK_DIR, OCUTALON_LOCK_OWNER,
#                      OCUTALON_TEST_WEB_PORT) are passed through
#   ANTHROPIC_API_KEY  any value that the caller holds is unset first, and is never used
#   OCUTALON_MODEL_BASE_URL  when the caller sets it, it must be the CI mock's (http://mock:8080); anything else is refused with exit 2
#   RUNNER_TEMP, TMPDIR  where the private work folder is made (mktemp -d)
# Exit codes: 0 every check passed, 1 a check failed, 2 no run tag or a model endpoint that is not the CI mock. The last line is "eval/key-proof: all checks passed" or
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

# The model endpoint of the run: the caller's OCUTALON_MODEL_BASE_URL when it is set, and the last one that the compose files set, in the order that
# eval/run.sh --key-path layers them (the override, then the CI file again). Both must be the CI mock's, http://mock:8080 on the compose network. They are
# read from the files, never from the container tool. Only the scheme, host and port of a refused endpoint are named: a user name, path or query never is.
file_endpoint=$(sed -n 's/^[[:space:]]*OCUTALON_MODEL_BASE_URL:[[:space:]]*//p' eval/compose.release-candidate.yml ci/compose.ci.yml 2> /dev/null | tail -n 1 | tr -d '"')
for endpoint in "${OCUTALON_MODEL_BASE_URL:-$file_endpoint}" "$file_endpoint"; do
  case $endpoint in
    http://mock:8080 | http://mock:8080/*) ;;
    *)
      shown=$(printf '%s' "$endpoint" | sed -e 's#^\([A-Za-z][A-Za-z0-9+.-]*://\)[^/]*@#\1#' -e 's#^\([A-Za-z][A-Za-z0-9+.-]*://[^/?\#]*\).*$#\1#' | cut -c1-80)
      echo "FAIL the model endpoint '${shown:-none}' is not the CI mock (http://mock:8080): the key proof refuses to run, and nothing was started"
      exit 2
      ;;
  esac
done

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
if [ "$proofs" -eq 10 ] && [ "$labels" = "container files,container logs,counts,eval files,globals,mock log,run files,stores,trace,web bundle" ]; then
  pass "the capture holds the nine PASS key proof lines and the counts line"
else
  fail "the capture holds $proofs PASS key proof line(s) (labels: ${labels:-none}), not the nine scans and the counts line"
fi
# The proof's pass line: counts only, in a fixed order. The run counts the iris environment, the logs, the result files, the trace and the bundle; this
# script adds the run's output (the lines of the capture that hold the key, none when it got here clean).
output_n=0
if [ -n "$capture_hits" ]; then output_n=$(printf '%s\n' "$capture_hits" | tr ',' '\n' | grep -c .); fi
counts=$(grep '^PASS key proof counts: ' "$capture" | head -n 1 | sed -n 's/^PASS key proof counts: iris environment \([0-9][0-9]*\), container logs \([0-9][0-9]*\), result files \([0-9][0-9]*\), trace \([0-9][0-9]*\), web bundle \([0-9][0-9]*\)$/\1 \2 \3 \4 \5/p')
if [ -z "$counts" ]; then
  fail "the capture holds no counts line of the shape: iris environment N, container logs N, result files N, trace N, web bundle N"
else
  read -r c_env c_logs c_files c_trace c_bundle <<< "$counts"
  if [ "$c_env" = 1 ] && [ "$c_logs$c_files$c_trace$c_bundle" = 0000 ] && [ "$output_n" -eq 0 ]; then
    pass "key counts: iris environment $c_env, run output $output_n, container logs $c_logs, result files $c_files, trace $c_trace, web bundle $c_bundle"
  else
    fail "key counts: iris environment $c_env, run output $output_n, container logs $c_logs, result files $c_files, trace $c_trace, web bundle $c_bundle (the key must be in the iris environment exactly 1 time and in nothing else)"
  fi
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

# The compose project of the run, named by its STACK line: nothing of it may be left, listed by the tool itself before the teardown could remove it.
project=$(sed -n 's/^STACK evaluation: project \([a-z0-9-][a-z0-9-]*\)$/\1/p' "$capture" | head -n 1)
if [ -z "$project" ]; then
  fail "the capture names no compose project of the run, so its leftovers cannot be listed"
else
  leftovers=$(project_leftovers "$project")
  if [ "$leftovers" = "0|0" ]; then
    pass "the compose project of the run has 0 containers and 0 volumes left"
  else
    fail "the compose project of the run has containers|volumes left: ${leftovers:-the tool could not be asked}"
  fi
fi

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
