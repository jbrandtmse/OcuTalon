#!/usr/bin/env bash
# Live test of the page's accessibility floor (NFR-25; Stories 2.12 and 2.14): builds the image and starts it in one throwaway
# compose project, then drives a real browser through the Playwright project floor, which is every spec under web/e2e/floor/:
#   - Story 2.12's announcements (announcements.spec.ts A1 to A7): the page speaks through one polite live region and says each event
#     once, and nothing else is a live region;
#   - Story 2.12's focus (focus.spec.ts P1 to P4): live content never moves focus, and the one focus rule puts it back when the element
#     that held it is replaced or removed;
#   - Story 2.14's keyboard (keyboard.spec.ts K1 to K6): the skip links, Esc on the topmost layer, no single-key shortcut, a focus ring
#     that no scroller or edge clips, every control named, and the inactive conversation link that explains itself;
#   - Story 2.14's words (words.spec.ts W1 to W4): every link underlined, text at 200% without loss, reduced motion, and the errors
#     linked to their buttons.
# The stack holds what the first start creates and one fixture user, the floor user ZzFloor (OCUTALON_FLOOR_USER, with the user role),
# whose session the specs seed turns, reminders, decisions and conditions into and publish on, and whose /events poll they hold for one
# update; the stack starts with no model key (check_no_key), so its page shows the no-key banner. The chat posts of A6, P1 and W4 are
# answered in the browser and never reach the server, so no turn of these specs replies inside another case's window. The specs reach
# the IRIS container with docker exec, which OCUTALON_E2E_IRIS_CONTAINER names. No test stops IRIS or its web server.
# It does not rebuild the web bundle: ci/iris.sh build makes it, as for the demo-path unit. The project is unique and publishes its web
# port only on 127.0.0.1, on the first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). The floor user gets a random password that
# is passed by environment variable and never printed. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held), so even a failing run ends within it; the browser run's global timeout is what is left of it minus 20 s.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later, the
# built web bundle, and the browser: npx --prefix web playwright install chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
live_start floor
live_web_port || exit 1

flooruser=ZzFloor
floorpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"

# --- build and start ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"
check_no_key "floor"

# --- the floor user ---

created=$(live_fixture_user "$flooruser" "$floorpassword" "OcuTalonUser" "floor fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user $flooruser (role OcuTalonUser) is created"
else
  die "the fixture user $flooruser could not be created ('$created')"
fi

# --- the browser: the project floor ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's password is replaced
# before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$floorpassword/<redacted>/g; s/^/  /"; }
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_FLOOR_USER="$flooruser" \
  OCUTALON_FLOOR_PASSWORD="$floorpassword" \
  OCUTALON_E2E_IRIS_CONTAINER="$cid" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e:floor > "$e2e_log" 2>&1
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 30
  pass "Story 2.12's A1-A7 and P1-P4 and Story 2.14's K1-K6 and W1-W4: the specs of the floor project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tail -n 1))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "Story 2.12's A1-A7 and P1-P4 and Story 2.14's K1-K6 and W1-W4: the specs of the floor project failed (exit $e2e_status)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-floor: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-floor: all checks passed"
