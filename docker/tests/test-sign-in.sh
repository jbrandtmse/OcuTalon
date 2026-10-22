#!/usr/bin/env bash
# Live test of Story 0.3, signing in to an empty OcuTalon page (matrix rows 1 to 13), and of Story 0.5, the REST skeleton
# and the public status (matrix rows 13 to 19): rebuilds the web bundle, builds the image and starts it in one
# throwaway compose project, then checks
#   - rows 1 and 2 of Story 0.3, from the security tables: the roles, the README account, InvalidLoginAction and the
#     four web applications (check_security);
#   - rows 3 to 13 of Story 0.3 in a real browser, through the Playwright project chromium, which is every spec under web/e2e/
#     except web/e2e/demo-path/ (that folder is the demo-path unit's, test-demo-path.sh): what answers without
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
#     on and seed turns into (C2 to C7); C1 reads the README account and sends nothing.
# The project is unique and receives no keys. It publishes its web port only on 127.0.0.1, on the first free port of
# 52800-52819 (or OCUTALON_TEST_WEB_PORT), for the browser. The no-role, trace-only, first-call, live, session, sign-in, chat and panel users
# get random passwords that are passed by environment variable and never printed. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
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

# --- rows 1 and 2 ---

check_security "rows 1-2"

# --- the users without the OcuTalon user role (Story 0.3, row 12; Story 0.5, row 18) ---

# create_fixture_user <name> <password> <roles> <comment>: a user of OCUTALON whose password reaches IRIS by environment
# variable, so that it is never printed. Prints the CHK line.
create_fixture_user() {
  printf '%s\n' \
    'Set pw=$SYSTEM.Util.GetEnviron("OCUTALON_T03_PW")' \
    "Set sc=##class(Security.Users).Create(\"$1\",\"$3\",pw,\"$4\",\"OCUTALON\",\"\",\"\",0,1,\"t03 fixture\",1,\"\",\"\",,1,1)" \
    'Write !,"CHK|fixture-user|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' \
    | OCUTALON_T03_PW="$2" dc exec -T -e OCUTALON_T03_PW iris iris session IRIS -U %SYS 2>/dev/null | tr -d '\r' | sed -n 's/.*\(CHK|fixture-user|.*\)$/\1/p' | tail -n 1
}

created=$(create_fixture_user "$noroleuser" "$noropassword" "" "no-role fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user without roles is created"
else
  die "the fixture user without roles could not be created ('$created')"
fi
created=$(create_fixture_user "$traceuser" "$tracepassword" "OcuTalonTraceViewer" "trace-only fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user with the trace role alone is created"
else
  die "the fixture user with the trace role alone could not be created ('$created')"
fi

created=$(create_fixture_user "$firstuser" "$firstpassword" "OcuTalonUser" "first-call fixture")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the fixture user with the user role and no session row is created"
else
  die "the fixture user with the user role could not be created ('$created')"
fi

# Story 2.2's users: the live user and the sign-in user hold the user role; the session user also holds the trace role, so that
# session.spec S5 can sign in at a trace application. Nothing signs the sign-in user in before S4. The chat user is Story
# 2.4's, and the panel user holds the user role for the specs of Story 2.5, which send and seed on its session.
for fixture in "$liveuser|$livepassword|OcuTalonUser|live fixture" "$sessionuser|$sessionpassword|OcuTalonUser,OcuTalonTraceViewer|session fixture" "$signinuser|$signinpassword|OcuTalonUser|sign-in fixture" "$chatuser|$chatpassword|OcuTalonUser|chat fixture" "$paneluser|$panelpassword|OcuTalonUser|panel fixture"; do
  fixture_name=${fixture%%|*}
  fixture_rest=${fixture#*|}
  fixture_password=${fixture_rest%%|*}
  fixture_rest=${fixture_rest#*|}
  fixture_roles=${fixture_rest%%|*}
  fixture_comment=${fixture_rest#*|}
  created=$(create_fixture_user "$fixture_name" "$fixture_password" "$fixture_roles" "$fixture_comment")
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
show_log() { tail -n "$1" "$e2e_log" | sed "s/$noropassword/<redacted>/g; s/$tracepassword/<redacted>/g; s/$firstpassword/<redacted>/g; s/$livepassword/<redacted>/g; s/$sessionpassword/<redacted>/g; s/$signinpassword/<redacted>/g; s/$chatpassword/<redacted>/g; s/$panelpassword/<redacted>/g; s/^/  /"; }
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
  pass "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8 and Story 2.5's C1-C10: the specs of the chromium project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tail -n 1))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8 and Story 2.5's C1-C10: the specs of the chromium project failed (exit $e2e_status)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-sign-in: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-sign-in: all checks passed"
