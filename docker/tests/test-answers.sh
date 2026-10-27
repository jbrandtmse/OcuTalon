#!/usr/bin/env bash
# Live test of answering an approval request from the simulated phone and of every copy of an answer (NFR-9; Story 6.3; FR-8, FR-13, AD-31, AD-32),
# and, since Story 6.4, of the incident and request cards and of every ending of an incident: builds the image and starts it in one throwaway
# compose project, creates the fixture user ZzAnswers, then drives Chromium through the Playwright project answers (web/e2e/answers/): 6.3's
# answers.spec.ts (X1 to X10), 6.1's incident-card.spec.ts (I2 to I11), 6.2's approval-card.spec.ts (A2 to A10) and 6.4's close-loop.spec.ts
# (C1 to C10; the results, rejections, expiry, fallbacks, Dismiss, and the cross-session 404 of the dismiss route, with the IncidentManager
# item behind the fixture double for the spec's run). I1 and A1, the two cases that also run in Firefox and WebKit, stay in the floor unit.
# The cases X1 to X10 of answers.spec.ts:
#   - X1: an incident notice reaches the phone as a message with the catalog's text, the dry run's example in mono, and Approve and Reject
#     side by side; a later request is a message of its own, and a notice with no request has no buttons;
#   - X2: Approve on the phone: both buttons busy, then the answered line with focus on it; the chat's card shows the answer within 2 s of the
#     reply (NFR-9), the rail row leaves, the row is answered from the phone by the session's user with one AnswersIn to AnswerOps header, and
#     the card does not announce an answer that took focus on the phone;
#   - X3: Approve on the card, then the stand-in for IncidentManager's answered notification: within 5 s of the reply (NFR-9) the phone's
#     buttons are replaced in place by "Approved from the web chat at HH:MM.", the same message, the feed not moved;
#   - X4: a press on the phone's stale buttons gets the 409 and its notice, announced once; the row is unchanged (the first answer wins);
#   - X5: the phone's busy rule and its failure notices (a held press, 404, 403, 500);
#   - X6: a press on a rail row focuses the request's card in the chat and scrolls it into view, in the drawer band with the drawer open,
#     or focuses the chat's list when the card is not in the chat;
#   - X7: a pending request on the phone holds its feed when another notification arrives (New messages shows, Approve does not move);
#   - X8: an answer from elsewhere is shown by the card within 2 s of its event (the page poll, NFR-9) and announced once when focus is elsewhere,
#     and not announced when it takes focus on the card's own status;
#   - X9: Reject on the phone: the press names reject and the channel phone, the rejected line replaces the buttons, the card follows and
#     the row is rejected from the phone;
#   - X10: the server's edit moves focus from the phone's replaced Approve to its line, and after a reload the answered message keeps its
#     stored line and the pending one its buttons.
# The stack holds what the first start creates and one fixture user, ZzAnswers (OCUTALON_ANSWERS_USER, with the user role), whose session
# the specs seed requests into and publish on; the stack starts with no model key. The specs reach the IRIS container with docker exec,
# which OCUTALON_E2E_IRIS_CONTAINER names. No test stops IRIS or its web server.
# It does not rebuild the web bundle: ci/iris.sh build makes it, as for the demo-path unit. The project is unique and publishes its web
# port only on 127.0.0.1, on the first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). The fixture user gets a random password that
# is passed by environment variable and never printed. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held), so even a failing run ends within it; the browser run's global timeout is what is left of it minus 20 s.
# Prints one PASS or FAIL line per check, and an INFO line for the measured duration; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later, the
# built web bundle and the browser: npx --prefix web playwright install chromium (ci/iris.sh live answers installs it).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start answers
live_web_port || exit 1

answersuser=ZzAnswers
answerspassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"

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
check_no_key "answers"

# --- the fixture user ---

created=$(live_fixture_user "$answersuser" "$answerspassword" "OcuTalonUser" "answers fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user $answersuser (role OcuTalonUser) is created"
else
  die "the fixture user $answersuser could not be created ('$created')"
fi

# --- the browser: the project answers ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's password is replaced
# before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$answerspassword/<redacted>/g; s/^/  /"; }
browser_started=$SECONDS
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_ANSWERS_USER="$answersuser" \
  OCUTALON_ANSWERS_PASSWORD="$answerspassword" \
  OCUTALON_E2E_IRIS_CONTAINER="$cid" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e:answers > "$e2e_log" 2>&1
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 30
  grep -E "^ *(INFO|ANSWERS)" "$e2e_log" | sed 's/^ *//'
  pass "the answers project's cases (6.3's X1-X10, 6.1's I2-I11, 6.2's A2-A10 and 6.4's C1-C10) pass in Chromium ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  a browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "the answers project's cases (6.3's X1-X10, 6.1's I2-I11, 6.2's A2-A10 and 6.4's C1-C10) failed in Chromium (exit $e2e_status)"
fi
echo "INFO the browser run took $((SECONDS - browser_started)) s"

if [ "$fails" -ne 0 ]; then
  echo "test-answers: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-answers: all checks passed"
