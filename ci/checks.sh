#!/usr/bin/env bash
# The hosted `checks` job (Story 0.7): runs every script of CHECK_SCRIPTS (ci/units.sh) from the repository root, each to its end,
# and prints one block per script. A script that fails does not stop the others. Exits 1, naming each failed script, when any
# failed. It starts no container and is never skipped.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
. "$root/ci/units.sh"

failed=""
for name in $CHECK_SCRIPTS; do
  script="docker/tests/test-$name.sh"
  echo "==== check $name ($script)"
  start=$SECONDS
  if [ -f "$script" ]; then
    bash "$script"
    rc=$?
  else
    echo "FAIL $script does not exist"
    rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    echo "==== $name passed $((SECONDS - start))s"
  else
    echo "==== $name failed (exit $rc) $((SECONDS - start))s"
    failed="$failed $name"
  fi
done

if [ -n "$failed" ]; then
  echo "checks: failed:$failed"
  exit 1
fi
echo "checks: all scripts passed"
