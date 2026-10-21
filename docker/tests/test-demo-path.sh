#!/usr/bin/env bash
# Live test of Story 0.8, the demo-path test (REL-2; UJ-1 and AD-23): builds the image and starts it in one fresh throwaway
# compose project with the CI override, as a judge's first start leaves it, then
#   - times that first start and prints FIRST-START engine=<arch> build=<s>s ready=<s>s (the figure that the README quotes), and
#     WARN when it is ready after more than 12 minutes (a decision for the author, AD-23, not a failure);
#   - runs the Playwright project demo-path in a real browser: the six step specs web/e2e/demo-path/0<n>-<id>.spec.ts. Step 1's
#     @floor test signs in with the README account and waits for the page to load its snapshot; every part of a step that no
#     story has built yet is declared skipped, and its skip names the story that turns it on;
#   - prints the step summary of web/scripts/demo-path-summary.mjs: one STEP line per step (passed, partly skipped, skipped or
#     failed) and a DEMO-PATH line. A skipped step is never reported as passed; a failed test, a skip that names no story, a
#     @floor test that did not pass, a missing step spec and an unknown spec file fail the unit.
# The stack holds only what the first start creates: no fixture user, no seeded event, no rebuilt bundle (ci/iris.sh build made
# it), no model key. No test sends a model request. The project is unique and publishes its web port only on 127.0.0.1, on the
# first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI); within it, the first start
# waits up to 900 s for the start's log to end ready and up to 60 s more for Docker to report healthy.
# Prints one PASS or FAIL line per check; exits 0 only when every check passes.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later,
# and the browser: npx --prefix web playwright install chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t08
live_web_port || exit 1

# --- the first start, timed ---

if ! live_first_start 900; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready"
fi
pass "the first start ended ready"

# --- the demo path: the step specs, then the step summary ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
report="$tmp/demo-path.json"
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_E2E_JSON="$report" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e:demo-path > "$e2e_log" 2>&1
e2e_status=$?
sed 's/^/  /' "$e2e_log"
if grep -q "Executable doesn't exist" "$e2e_log"; then
  echo "  the browser is missing: run npx --prefix web playwright install chromium"
fi
node web/scripts/demo-path-summary.mjs "$report" > "$tmp/summary.log" 2>&1
summary_status=$?
cat "$tmp/summary.log"
if [ "$e2e_status" -eq 0 ] && [ "$summary_status" -eq 0 ]; then
  pass "the demo path: Playwright and the step summary both passed"
else
  fail "the demo path: Playwright exit $e2e_status, the step summary exit $summary_status"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-demo-path: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-demo-path: all checks passed"
