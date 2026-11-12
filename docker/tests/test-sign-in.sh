#!/usr/bin/env bash
# Live test of Story 0.3, signing in to an empty OcuTalon page (matrix rows 1 to 13), and of Story 0.5, the REST skeleton
# and the public status (matrix rows 13 to 19): rebuilds the web bundle, builds the image and starts it in one
# throwaway compose project, then checks
#   - rows 1 and 2 of Story 0.3, from the security tables: the roles, the README account, InvalidLoginAction and the
#     four web applications (check_security);
#   - rows 3 to 13 of Story 0.3 in a real browser, through the Playwright project chromium, which is every spec under web/e2e/
#     outside the folders that have a project of their own (web/playwright.config.ts): what answers without
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
#   - Story 2.6's decision strip (web/e2e/chat/decision.spec.ts D1 to D14, and chat.spec C15): the decision user
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
#     (check_no_key), so every page of it shows the no-key banner, and B6 replies through the real Decide's no-key fallback.
#   - Story 2.11's connection tests (web/e2e/banners/banners.spec.ts B13 to B19): the banners user again, with the page's clock
#     controlled by the test (page.clock) and, in all but B17, the page's API requests refused, failed, answered 503 or held in the
#     browser (page.route); L13 (web/e2e/live/live.spec.ts) holds one poll of the live user the same way. The server is never stopped.
# The project is unique and receives no keys. It publishes its web port only on 127.0.0.1, on the first free port of
# 52800-52819 (or OCUTALON_TEST_WEB_PORT), for the browser. The no-role, trace-only, first-call, live, session, sign-in, chat, panel, decision, notice, rail, thread, links and banners users
# get random passwords that are passed by environment variable and never printed. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, counted from the moment the throwaway lock is held: 540 s by default,
# 1200 s in CI, raised to the unit's floor in ci/units.sh, unit_live_deadline), so even a failing run ends within it; the browser run's
# global timeout is what is left of it minus 20 s. Before the browser run the unit prints "MEASURED live:<unit> suite budget <s> s" and
# after it, whatever the outcome, "MEASURED live:<unit> suite <s> s" (wall-clock seconds), so that the next audit reads both.
# Prints one PASS or FAIL line per check, and after the browser run one "SPEC <file> <n> tests <s>s" line per spec file that ran (the
# list reporter's times summed by file; a file's beforeAll counts in its first test), so that the sign-in units can be balanced
# from CI's own numbers; exits 0 only when all pass.
# The browser specs are split by spec file into three units (the Contest Planner's rulings of 2026-11-05, when the one unit took 1047 s
# in CI, and of 2026-11-07, when it took 1034 s and 1170 s again, both over the 1,000 s line), each on its own stack with the whole setup
# above: live:sign-in runs the Playwright project chromium, live:sign-in-2 (docker/tests/test-sign-in-2.sh, which runs this script with
# --project sign-in-2) runs the project sign-in-2, whose folders web/playwright.config.ts names in SIGN_IN_2_DIRS, and live:sign-in-3
# (docker/tests/test-sign-in-3.sh, --project sign-in-3) runs the project sign-in-3, whose folders and file it names in SIGN_IN_3_DIRS and
# SIGN_IN_3_FILES; the chromium project ignores both. With --project chromium|sign-in-2|sign-in-3 (or --project=...) it runs that project;
# chromium is the default. The texts below that name the chromium project name the project run.
# With --part k/n (or --part=k/n) it runs part k of n of the spec files of the project run on its own fresh stack, with the whole
# setup above, so that a stage can run the unit in calls that each fit the foreground cap. A part is a run of whole spec files, in
# path order, cut by the project's tests the way ci/iris.sh shard --part cuts its classes (web/scripts/e2e-part.mjs, which reads
# Playwright's own listing, so a new spec file joins a part with no change); the parts taken in order run every spec file once. It
# prints "PART k/n: <f> of <F> spec files, <t> of <T> tests: <files>" before anything starts, runs only those files
# (--test-list), and passes only when the run's passed and skipped tests add up to the part's <t>. A bad value (not k/n with
# 1 <= k <= n, n above the number of spec files, a part that holds no file) or an unknown argument exits 2, and a listing that
# cannot be made exits 1, both before the lock, the bundle build or any stack. Without an argument it runs the whole unit.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or
# later, and the browser: npx --prefix web playwright install chromium.
set -u
script_dir=$(cd "$(dirname "$0")" && pwd)

# --- the arguments, and the part's spec files ---

part=""
part_given=0
project=chromium
project_given=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --project | --project=*)
      if [ "$1" = --project ]; then
        if [ "$#" -lt 2 ]; then
          echo "test-sign-in: --project needs one value, chromium, sign-in-2 or sign-in-3 (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
          exit 2
        fi
        value=$2
        shift 2
      else
        value=${1#--project=}
        shift
      fi
      if [ "$project_given" -eq 1 ]; then
        echo "test-sign-in: --project is given once, and again as '$value' (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
        exit 2
      fi
      case $value in
        chromium | sign-in-2 | sign-in-3) ;;
        *)
          echo "test-sign-in: unknown project '$value': use chromium, sign-in-2 or sign-in-3 (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
          exit 2
          ;;
      esac
      project=$value
      project_given=1
      ;;
    --part)
      if [ "$part_given" -eq 1 ]; then
        echo "test-sign-in: --part is given once, and again as '${2:-}' (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
        exit 2
      fi
      if [ "$#" -lt 2 ]; then
        echo "test-sign-in: --part needs one value k/n (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
        exit 2
      fi
      part=$2
      part_given=1
      shift 2
      ;;
    --part=*)
      if [ "$part_given" -eq 1 ]; then
        echo "test-sign-in: --part is given once, and again as '${1#--part=}' (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
        exit 2
      fi
      part=${1#--part=}
      part_given=1
      shift
      ;;
    *)
      echo "test-sign-in: unknown argument '$1' (usage: test-sign-in.sh [--project chromium|sign-in-2|sign-in-3] [--part k/n])"
      exit 2
      ;;
  esac
done

# The unit of the project: its npm script, the label of its throwaway and the name of its summary.
case $project in
  chromium)
    e2e_script=e2e
    unit_label=t03
    unit_name=test-sign-in
    ;;
  sign-in-2)
    e2e_script=e2e:sign-in-2
    unit_label=t03b
    unit_name=test-sign-in-2
    ;;
  sign-in-3)
    e2e_script=e2e:sign-in-3
    unit_label=t03c
    unit_name=test-sign-in-3
    ;;
esac

part_label=""
part_tests=""
part_files=""
if [ "$part_given" -eq 1 ]; then
  cd "$script_dir/../.." || exit 1
  part_listing=$(mktemp "${TMPDIR:-/tmp}/ocutalon-part.XXXXXX") || exit 1
  part_errors="$part_listing.err"
  if ! npm --silent --prefix web run "$e2e_script" -- --list --reporter=json > "$part_listing" 2> "$part_errors"; then
    tail -n 30 "$part_listing" | cut -c1-300
    tail -n 30 "$part_errors" | cut -c1-300
    rm -f "$part_listing" "$part_errors"
    echo "FAIL the $project project's spec files could not be listed"
    exit 1
  fi
  part_out=$(node web/scripts/e2e-part.mjs "$part" "$part_listing")
  part_status=$?
  rm -f "$part_listing" "$part_errors"
  [ "$part_status" -eq 0 ] || exit "$part_status"
  part_line=$(printf '%s\n' "$part_out" | sed -n 1p)
  part_files=$(printf '%s\n' "$part_out" | sed 1d)
  part_label=$(printf '%s\n' "$part_line" | sed -E 's/^PART ([0-9]+\/[0-9]+):.*/\1/')
  part_tests=$(printf '%s\n' "$part_line" | sed -E 's/^PART [0-9]+\/[0-9]+: [0-9]+ of [0-9]+ spec files, ([0-9]+) of [0-9]+ tests.*/\1/')
  case $part_label$part_tests in
    *[!0-9/]* | "")
      echo "test-sign-in: cannot read the part and its test count from '$part_line'"
      exit 1
      ;;
  esac
  echo "$part_line"
fi
chromium_specs="the specs of the $project project"
[ -z "$part_label" ] || chromium_specs="of these rows, those in the spec files of part $part_label of the $project project"
summary=$unit_name
[ -z "$part_label" ] || summary="$unit_name part $part_label"

LIVE_REBUILD_WEB=1
. "$script_dir/lib-live.sh"
live_start "$unit_label"
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

if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready within $LIVE_FIRST_START_WAIT s"
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
part_args=()
if [ -n "$part_label" ]; then
  printf '%s\n' "$part_files" > "$tmp/part.list"
  part_args=(-- --test-list "$tmp/part.list")
fi
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's
# password is replaced before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$noropassword/<redacted>/g; s/$tracepassword/<redacted>/g; s/$firstpassword/<redacted>/g; s/$livepassword/<redacted>/g; s/$sessionpassword/<redacted>/g; s/$signinpassword/<redacted>/g; s/$chatpassword/<redacted>/g; s/$panelpassword/<redacted>/g; s/$decisionpassword/<redacted>/g; s/$noticepassword/<redacted>/g; s/$railpassword/<redacted>/g; s/$threadpassword/<redacted>/g; s/$linkspassword/<redacted>/g; s/$bannerspassword/<redacted>/g; s/^/  /"; }
suite_unit=${unit_name#test-}
echo "MEASURED live:$suite_unit suite budget $((remaining - 20)) s"
suite_began=$SECONDS
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
  npm --prefix web run "$e2e_script" ${part_args[@]+"${part_args[@]}"} > "$e2e_log" 2>&1
e2e_status=$?
echo "MEASURED live:$suite_unit suite $((SECONDS - suite_began)) s"
# Each spec file's seconds, in run order: the list reporter's line of each test that ran ends with its time, (525ms), (1.8s) or (1.2m).
LC_ALL=C awk '
  {
    line = $0
    gsub(/\033\[[0-9;]*m/, "", line)
    if (!match(line, /[A-Za-z0-9_.\/-]+\.spec\.ts:[0-9]/)) next
    file = substr(line, RSTART, RLENGTH - 2)
    sub(/^e2e\//, "", file)
    if (!match(line, /\([0-9.]+(ms|s|m|h)\)$/)) next
    text = substr(line, RSTART + 1, RLENGTH - 2)
    unit = text
    sub(/^[0-9.]+/, "", unit)
    value = text + 0
    if (unit == "ms") value /= 1000
    else if (unit == "m") value *= 60
    else if (unit == "h") value *= 3600
    if (!(file in seconds)) order[++files] = file
    seconds[file] += value
    tests[file]++
  }
  END { for (i = 1; i <= files; i++) printf "SPEC %s %d tests %.0fs\n", order[i], tests[order[i]], seconds[order[i]] }
' "$e2e_log"
# A test list that matches nothing exits 0, so a part passes only when its passed and skipped tests are the part's.
part_ran=""
if [ "$e2e_status" -eq 0 ] && [ -n "$part_label" ]; then
  plain=$(LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' "$e2e_log")
  part_passed=$(printf '%s\n' "$plain" | sed -n -E 's/^ *([0-9]+) passed( \(.*\))?$/\1/p' | tail -n 1)
  part_skipped=$(printf '%s\n' "$plain" | sed -n -E 's/^ *([0-9]+) skipped$/\1/p' | tail -n 1)
  part_ran=$(( ${part_passed:-0} + ${part_skipped:-0} ))
fi
if [ "$e2e_status" -eq 0 ] && [ -n "$part_ran" ] && [ "$part_ran" -ne "$part_tests" ]; then
  show_log 30
  fail "part $part_label ran $part_ran of its $part_tests tests"
elif [ "$e2e_status" -eq 0 ]; then
  show_log 30
  # N10 logs its elapsed time (P30); a passing run shows it too.
  grep -a '^N10: ' "$e2e_log" | sed 's/^/  /' || true
  pass "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8, Story 2.5's C1-C14, Story 2.6's D1-D14 and C15, Story 2.7's N1-N15, Story 2.8's R1-R19, Story 2.9's T1-T4, Story 2.13's V1-V16, Story 2.10's B1-B12 and Story 2.11's B13-B19: $chromium_specs pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tail -n 1))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 3-13, Story 0.5's rows 13-19, Story 2.2's L1-L13 and S1-S8, Story 2.5's C1-C14, Story 2.6's D1-D14 and C15, Story 2.7's N1-N15, Story 2.8's R1-R19, Story 2.9's T1-T4, Story 2.13's V1-V16, Story 2.10's B1-B12 and Story 2.11's B13-B19: $chromium_specs failed (exit $e2e_status)"
fi

if [ "$fails" -ne 0 ]; then
  echo "$summary: $fails check(s) failed (project $P)"
  exit 1
fi
echo "$summary: all checks passed"
