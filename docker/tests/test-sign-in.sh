#!/usr/bin/env bash
# Live test of Story 0.3, signing in to an empty OcuTalon page (matrix rows 1 to 13), and of Story 0.5, the REST skeleton
# and the public status (matrix rows 13 to 19): rebuilds the web bundle, builds the image and starts it in one
# throwaway compose project, then checks
#   - rows 1 and 2 of Story 0.3, from the security tables: the roles, the README account, InvalidLoginAction and the
#     four web applications (check_security);
#   - rows 3 to 13 of Story 0.3 in a real browser, through the Playwright project chromium, which is every spec under web/e2e/
#     except web/e2e/demo-path/ and web/e2e/floor/ (those folders are the demo-path unit's, test-demo-path.sh, and the floor unit's,
#     test-floor.sh): what answers without
#     a session, the sign-in page, a wrong password, the password toggle, the README sign-in, the tokens and fonts, one
#     sign-in group, Sign out, a user without the OcuTalon user role, and a deep link;
#   - rows 13 to 19 of Story 0.5, through web/e2e/api/api.spec.ts, on a stack that this script seeds: the README
#     account's session gets two reminder events and the instance stream one status event, and the script passes what
#     it read back (the version, the instance zone, the session's epoch and the marker of the texts) to the specs.
#   - Story 2.2's live path and session (web/e2e/live/ and web/e2e/session/): three more fixture users with the user role, the
#     live user (OCUTALON_LIVE_USER), the session user, who also holds the trace role (OCUTALON_SESSION_USER), and the sign-in
#     user, whom nothing signs in before session.spec S4 (OCUTALON_SIGNIN_USER). The specs reach the IRIS container with
#     docker exec, which OCUTALON_E2E_IRIS_CONTAINER names.
#   - Story 2.4's chat (web/e2e/api/api.spec.ts): a further user with the user role, the chat user (OCUTALON_CHAT_USER), whose
#     session is the one that posts messages, so that the turns it makes touch neither the README account's seeded events nor
#     another spec's snapshot.
#   - Story 2.5's chat panel (web/e2e/chat/chat.spec.ts): the panel user (OCUTALON_PANEL_USER), whose session the specs send
#     on and seed turns into (C2 to C14); C1 reads the README account and sends nothing.
#   - Story 2.6's decision strip (web/e2e/chat/decision.spec.ts D1 to D13, and chat.spec C15): the decision user
#     (OCUTALON_DECISION_USER), whose session the D specs seed turns, decisions and usage rows into and publish on (they send
#     nothing); only C15 sends, as the panel user.
#   - Story 2.7's notice cards (web/e2e/chat/notice.spec.ts N1 to N15): the notice user (OCUTALON_NOTICE_USER), whose session the
#     N specs seed decisions into and send items, item decisions and notifications to; N10 sends an untrusted item through the
#     real production and times the card.
#   - Story 2.8's status rail (web/e2e/rail/rail.spec.ts R1 to R19): the rail user (OCUTALON_RAIL_USER), whose session the R specs
#     seed approval requests, checks, reminders and decisions into, and whose rows they drive through BridgeSink and the live stream.
#   - Story 2.9's Visual Trace links (web/e2e/trace/trace.spec.ts T1 to T4): the thread user (OCUTALON_THREAD_USER, with the user role
#     and the trace role), whose session posts messages through the real production until its trace session holds more than 45
#     items, and whose Visual Trace settings the specs change and put back; the specs open the links in the real Visual Trace pages.
#   - Story 2.13's links on the page (web/e2e/trace/links.spec.ts V1 to V16): the links user (OCUTALON_LINKS_USER, with the user role and
#     the trace role), whose session posts its own turns and receives seeded decisions, checks, reminders and approval requests, so that
#     the specs press the page's trace links, the sign-in help and the Visual Trace menu; V1, V2 and V8 open the real Visual Trace pages,
#     and the other cases give their trace tabs a stand-in page.
#   - Story 2.10's status banners (web/e2e/banners/banners.spec.ts B1 to B12): the banners user (OCUTALON_BANNERS_USER), whose session the
#     specs publish status events on, seed checks and decisions into and send a message from; the stack starts with no model key
#     (check_no_key), so every page of it shows the no-key banner, and B6 turns itself on when the bridge's Decide is built.
#   - Story 2.11's connection tests (web/e2e/banners/banners.spec.ts B13 to B19): the banners user again, with the page's clock
#     controlled by the test (page.clock) and, in all but B17, the page's API requests refused, failed, answered 503 or held in the
#     browser (page.route); L13 (web/e2e/live/live.spec.ts) holds one poll of the live user the same way. The server is never stopped.
# The project is unique and receives no keys. It publishes its web port only on 127.0.0.1, on the first free port of
# 52800-52819 (or OCUTALON_TEST_WEB_PORT), for the browser. The no-role, trace-only, first-call, live, session, sign-in, chat, panel, decision, notice, rail, thread, links and banners users
# get random passwords that are passed by environment variable and never printed. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held), so even a failing run ends within it; the browser run's global timeout is what is left of it minus 20 s.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or
# later, and the browser: npx --prefix web playwright install chromium.
set -u

LIVE_REBUILD_WEB=1
. "$(dirname "$0")/lib-live.sh"
live_start t03
live_web_port || exit 1

noroleuser=ZzNoRole
noropassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
traceuser=ZzTraceOnly
tracepassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
firstuser=ZzFirstCall
firstpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
liveuser=ZzLive
livepassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
sessionuser=ZzSession
sessionpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
signinuser=ZzSignIn
signinpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
chatuser=ZzChat
chatpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
paneluser=ZzPanel
panelpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
decisionuser=ZzDecision
decisionpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
noticeuser=ZzNotice
noticepassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
railuser=ZzRail
railpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
threaduser=ZzThread
threadpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
linksuser=ZzLinks
linkspassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
bannersuser=ZzBanners
bannerspassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"

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
check_no_key "sign-in"

# --- rows 1 and 2 ---

check_security "rows 1-2"

# --- the users without the OcuTalon user role (Story 0.3, row 12; Story 0.5, row 18) ---

# Each user is made by live_fixture_user (lib-live.sh), whose password reaches IRIS by environment variable.

created=$(live_fixture_user "$noroleuser" "$noropassword" "" "no-role fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user without roles is created"
else
  die "the fixture user without roles could not be created ('$created')"
fi
created=$(live_fixture_user "$traceuser" "$tracepassword" "OcuTalonTraceViewer" "trace-only fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user with the trace role alone is created"
else
  die "the fixture user with the trace role alone could not be created ('$created')"
fi

created=$(live_fixture_user "$firstuser" "$firstpassword" "OcuTalonUser" "first-call fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user with the user role and no session row is created"
else
  die "the fixture user with the user role could not be created ('$created')"
fi

# Story 2.2's users: the live user and the sign-in user hold the user role; the session user also holds the trace role, so that
# session.spec S5 can sign in at a trace application. Nothing signs the sign-in user in before S4. The chat user is Story
# 2.4's, the panel user holds the user role for the specs of Story 2.5, which send and seed on its session, and the decision user
# holds it for the specs of Story 2.6, which seed decisions into its session, and the notice user holds it for the specs of
# Story 2.7, which seed decisions and send items, item decisions and notifications to its session, and the rail user holds it for the
# specs of Story 2.8, which seed approval requests, checks, reminders and decisions into its session, and the thread user holds the
# user role and the trace role for the specs of Story 2.9, which post messages for its session and open the links in Visual Trace, and
# the links user holds the same two roles for the specs of Story 2.13, which do the same through the links on the page, and the
# banners user holds the user role for the specs of Story 2.10, which publish status events on its session and read the banners.
for fixture in "$liveuser|$livepassword|OcuTalonUser|live fixture" "$sessionuser|$sessionpassword|OcuTalonUser,OcuTalonTraceViewer|session fixture" "$signinuser|$signinpassword|OcuTalonUser|sign-in fixture" "$chatuser|$chatpassword|OcuTalonUser|chat fixture" "$paneluser|$panelpassword|OcuTalonUser|panel fixture" "$decisionuser|$decisionpassword|OcuTalonUser|decision fixture" "$noticeuser|$noticepassword|OcuTalonUser|notice fixture" "$railuser|$railpassword|OcuTalonUser|rail fixture" "$threaduser|$threadpassword|OcuTalonUser,OcuTalonTraceViewer|thread fixture" "$linksuser|$linkspassword|OcuTalonUser,OcuTalonTraceViewer|links fixture" "$bannersuser|$bannerspassword|OcuTalonUser|banners fixture"; do
  fixture_name=${fixture%%|*}
  fixture_rest=${fixture#*|}
  fixture_password=${fixture_rest%%|*}
  fixture_rest=${fixture_rest#*|}
  fixture_roles=${fixture_rest%%|*}
  fixture_comment=${fixture_rest#*|}
  created=$(live_fixture_user "$fixture_name" "$fixture_password" "$fixture_roles" "$fixture_comment")
  if [ "$created" = "CHK|fixture-user|1" ]; then
    pass "the fixture user $fixture_name (roles $fixture_roles) is created"
  else
    die "the fixture user $fixture_name could not be created ('$created')"
  fi
done

# --- Story 0.5, rows 13 and 14: the seeded events ---

# The README account's durable session, two reminder events on its stream, and one status event on the instance
# stream. The script reads back the session's epoch and the instance zone.
marker="zz-$P"
seeded=$(printf '%s\n' \
  'Set s=##class(OcuTalon.Data.Session).ForUser("ocutalon",.sc)' \
  'Write !,"CHK|epoch|",s.Epoch' \
  "For i=1,2 { Set p=##class(OcuTalon.Live.Payload.Reminder).%New() Set p.Ref=\"ZzE2E\"_i Set p.Text=\"$marker-\"_i Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,\"reminder\",p,.q) Write !,\"CHK|seq|\",i,\"|\",q }" \
  'Set t=##class(OcuTalon.Live.Payload.Status).%New() Set t.Condition="noModelKey",t.Active=1 Set sc=##class(OcuTalon.Live.Publish).Publish("instance","status",t,.q) Write !,"CHK|instance-seq|",q' \
  'Write !,"CHK|zone|",##class(OcuTalon.Data.Time).Zone()' \
  'Halt' | iris_script OCUTALON)
seeded_epoch=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|epoch|//p')
seeded_zone=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|zone|//p')
if [ -n "$seeded_epoch" ] && [ -n "$seeded_zone" ] \
  && printf '%s\n' "$seeded" | grep -qx 'CHK|seq|1|1' && printf '%s\n' "$seeded" | grep -qx 'CHK|seq|2|2' \
  && printf '%s\n' "$seeded" | grep -qx 'CHK|instance-seq|1'; then
  pass "the README account's session got two events, and the instance stream one"
else
  printf '%s\n' "$seeded" | cut -c1-200
  die "the events could not be seeded"
fi

# --- Story 0.3, rows 3 to 13, and Story 0.5, rows 13 to 19: the browser ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's
# password is replaced before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$noropassword/<redacted>/g; s/$tracepassword/<redacted>/g; s/$firstpassword/<redacted>/g; s/$livepassword/<redacted>/g; s/$sessionpassword/<redacted>/g; s/$signinpassword/<redacted>/g; s/$chatpassword/<redacted>/g; s/$panelpassword/<redacted>/g; s/$decisionpassword/<redacted>/g; s/$noticepassword/<redacted>/g; s/$railpassword/<redacted>/g; s/$threadpassword/<redacted>/g; s/$linkspassword/<redacted>/g; s/$bannerspassword/<redacted>/g; s/^/  /"; }
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_NOROLE_USER="$noroleuser" \
  OCUTALON_NOROLE_PASSWORD="$noropassword" \
  OCUTALON_TRACEONLY_USER="$traceuser" \
  OCUTALON_TRACEONLY_PASSWORD="$tracepassword" \
  OCUTALON_FIRSTCALL_USER="$firstuser" \
  OCUTALON_FIRSTCALL_PASSWORD="$firstpassword" \
  OCUTALON_LIVE_USER="$liveuser" \
  OCUTALON_LIVE_PASSWORD="$livepassword" \
  OCUTALON_SESSION_USER="$sessionuser" \
  OCUTALON_SESSION_PASSWORD="$sessionpassword" \
  OCUTALON_SIGNIN_USER="$signinuser" \
  OCUTALON_SIGNIN_PASSWORD="$signinpassword" \
  OCUTALON_CHAT_USER="$chatuser" \
  OCUTALON_CHAT_PASSWORD="$chatpassword" \
  OCUTALON_PANEL_USER="$paneluser" \
  OCUTALON_PANEL_PASSWORD="$panelpassword" \
  OCUTALON_DECISION_USER="$decisionuser" \
  OCUTALON_DECISION_PASSWORD="$decisionpassword" \
  OCUTALON_NOTICE_USER="$noticeuser" \
  OCUTALON_NOTICE_PASSWORD="$noticepassword" \
  OCUTALON_RAIL_USER="$railuser" \
  OCUTALON_RAIL_PASSWORD="$railpassword" \
  OCUTALON_THREAD_USER="$threaduser" \
  OCUTALON_THREAD_PASSWORD="$threadpassword" \
  OCUTALON_LINKS_USER="$linksuser" \
  OCUTALON_LINKS_PASSWORD="$linkspassword" \
  OCUTALON_BANNERS_USER="$bannersuser" \
  OCUTALON_BANNERS_PASSWORD="$bannerspassword" \
  OCUTALON_E2E_IRIS_CONTAINER="$cid" \
  OCUTALON_E2E_VERSION="$(manifest_version src/module.xml)" \
  OCUTALON_E2E_ZONE="$seeded_zone" \
  OCUTALON_E2E_EPOCH="$seeded_epoch" \
  OCUTALON_E2E_MARKER="$marker" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e > "$e2e_log" 2>&1
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 30
  # N10 logs its elapsed time (P30); a passing run shows it too.
  grep -a '^N10: ' "$e2e_log" | sed 's/^/  /' || true
  pass "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8, Story 2.5's C1-C14, Story 2.6's D1-D13 and C15, Story 2.7's N1-N15, Story 2.8's R1-R19, Story 2.9's T1-T4, Story 2.13's V1-V16, Story 2.10's B1-B12 and Story 2.11's B13-B19: the specs of the chromium project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tail -n 1))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8, Story 2.5's C1-C14, Story 2.6's D1-D13 and C15, Story 2.7's N1-N15, Story 2.8's R1-R19, Story 2.9's T1-T4, Story 2.13's V1-V16, Story 2.10's B1-B12 and Story 2.11's B13-B19: the specs of the chromium project failed (exit $e2e_status)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-sign-in: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-sign-in: all checks passed"
