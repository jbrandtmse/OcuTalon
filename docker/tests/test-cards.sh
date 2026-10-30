#!/usr/bin/env bash
# Live test of the incident card and the approval request card in the chat (Stories 6.1 and 6.2; FR-8, FR-24, AD-11, AD-12): builds the
# image and starts it in one throwaway compose project, creates the fixture user ZzCards, then drives Chromium through the Playwright
# project cards (web/e2e/cards/): 6.1's incident-card.spec.ts (I2 to I11: the same ref through its states, Show details, the snapshot,
# the incident-kind notifications, the browser zone, the focus when a card compacts, the open variants, the online demo, New messages and
# the texts) and 6.2's approval-card.spec.ts (A2 to A10: Approve, two requests and a Reject, the busy rule, the press that lost the race,
# the 1280x600 layout, another session's request, the replies that are not an answer, a closed incident and the headline cap). I1 and A1,
# the two cases that also run in Firefox and WebKit, are in the floor unit; the endings of an incident (C1 to C10) are in the answers unit.
# The stack holds what the first start creates and one fixture user, ZzCards (OCUTALON_CARDS_USER, with the user role), whose session
# the specs seed rows into and publish on; the stack starts with no model key. The specs reach the IRIS container with docker exec,
# which OCUTALON_E2E_IRIS_CONTAINER names. No test stops IRIS or its web server.
# It does not rebuild the web bundle: ci/iris.sh build makes it, as for the demo-path unit. The project is unique and publishes its web
# port only on 127.0.0.1, on the first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). The fixture user gets a random password that
# is passed by environment variable and never printed. An EXIT trap removes the project with its volume and images, so the user goes
# with the stack on every outcome.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held), so even a failing run ends within it; the browser run's global timeout is what is left of it minus 20 s.
# Prints one PASS or FAIL line per check, and an INFO line for the measured duration; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later, the
# built web bundle and the browser: npx --prefix web playwright install chromium (ci/iris.sh live cards installs it).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start cards
live_web_port || exit 1

cardsuser=ZzCards
cardspassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"

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
check_no_key "cards"

# --- the fixture user ---

created=$(live_fixture_user "$cardsuser" "$cardspassword" "OcuTalonUser" "cards fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user $cardsuser (role OcuTalonUser) is created"
else
  die "the fixture user $cardsuser could not be created ('$created')"
fi

# --- the browser: the project cards ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's password is replaced
# before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$cardspassword/<redacted>/g; s/^/  /"; }
browser_started=$SECONDS
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_CARDS_USER="$cardsuser" \
  OCUTALON_CARDS_PASSWORD="$cardspassword" \
  OCUTALON_E2E_IRIS_CONTAINER="$cid" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e:cards > "$e2e_log" 2>&1
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 30
  pass "the cards project's cases (6.1's I2-I11 and 6.2's A2-A10) pass in Chromium ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  a browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "the cards project's cases (6.1's I2-I11 and 6.2's A2-A10) failed in Chromium (exit $e2e_status)"
fi
echo "INFO the browser run took $((SECONDS - browser_started)) s"

if [ "$fails" -ne 0 ]; then
  echo "test-cards: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-cards: all checks passed"
