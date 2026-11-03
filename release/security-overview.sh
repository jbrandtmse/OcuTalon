#!/usr/bin/env bash
# release/security-overview.sh [--write]
# The callable unit of the security overview (Story 14.1; REL-1, AD-10, AD-23, AD-24). Run it from the root of a checkout (the candidate's tree,
# for the release sequence's step overview and for Story 11.14). It runs, one at a time and each on its own fresh lane throwaway of ci/iris.sh:
#   1. ci/iris.sh live security-overview [--write]   regenerates docs/security-overview.md from the product and compares it with the committed
#                                                    file (with --write it writes the file instead)
#   2. ci/iris.sh class OcuTalon.Test.Install.SecurityOverview
#                                                    the tests of the generator, of the tool list against every running runner and of the
#                                                    privilege list against the security records
#   3. ci/iris.sh teardown                           always, also after a failure
# The run tag is the caller's OCUTALON_RUN_TAG with -ovw-<pid> after it (ovw-<pid> alone without one), so a teardown removes only what this run
# started. A caller sets the lane lock folder (OCUTALON_LOCK_DIR) and the lock owner (OCUTALON_LOCK_OWNER) as the prefix of the call.
# Output: what the steps print, then one line, PASS overview <detail> or FAIL overview <detail> (the first DRIFT line, FAIL line or failed CLASS line of the steps), or
# WAIT overview <detail> when the lane's throwaway lock is busy.
# Exit: 0 pass, 75 the lane lock is busy (nothing was decided; call it again), 1 anything else, 2 a bad argument.
# Needs bash 3.2 or later, docker compose and the build 154 base image (ci/iris.sh). No real key, bot or model is used: the stack is the CI mock's.
set -u

write=""
case ${1:-} in
  '') ;;
  --write) write="--write" ;;
  *)
    echo "FAIL overview unknown argument '$1': the only option is --write"
    exit 2
    ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
if [ ! -f ci/iris.sh ] || [ ! -f docker/tests/test-security-overview.sh ]; then
  echo "FAIL overview run it from the root of a checkout that has ci/iris.sh and docker/tests/test-security-overview.sh"
  exit 1
fi

OCUTALON_RUN_TAG="${OCUTALON_RUN_TAG:+$OCUTALON_RUN_TAG-}ovw-$$"
export OCUTALON_RUN_TAG
log=$(mktemp "${TMPDIR:-/tmp}/ocutalon-overview.XXXXXX") || exit 1
rc=0

# step <what> <command...>: runs a command, keeps its output in the log and shows it; sets rc to its exit code.
step() {
  local what=$1 code
  shift
  echo "---- overview: $what"
  "$@" < /dev/null 2>&1 | tee -a "$log"
  code=${PIPESTATUS[0]}
  return "$code"
}

finish() {
  local line
  bash ci/iris.sh teardown < /dev/null > /dev/null 2>&1
  if [ "$rc" -eq 0 ]; then
    rm -f "$log"
    echo "PASS overview the generated sections equal a fresh generation, and the overview tests pass"
    exit 0
  fi
  if [ "$rc" -eq 75 ]; then
    rm -f "$log"
    echo "WAIT overview the lane's throwaway lock is busy"
    exit 75
  fi
  line=$(grep -m 1 -E '^(DRIFT |FAIL |CLASS .* failed)' "$log")
  rm -f "$log"
  echo "FAIL overview ${line:-a step ended with exit $rc}"
  exit 1
}

trap 'rc=130; finish' INT TERM HUP

# shellcheck disable=SC2086
step "the committed sections against a fresh generation" bash ci/iris.sh live security-overview $write
rc=$?
if [ "$rc" -eq 0 ]; then
  step "the tests" bash ci/iris.sh class OcuTalon.Test.Install.SecurityOverview
  rc=$?
fi
finish
