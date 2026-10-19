#!/usr/bin/env bash
# Live test of Story 0.3, signing in to an empty OcuTalon page (matrix rows 1 to 13): rebuilds the web bundle, builds the
# image and starts it in one throwaway compose project, then checks
#   - rows 1 and 2, from the security tables: the roles, the README account, InvalidLoginAction and the three web
#     applications (check_security);
#   - rows 3 to 13 in a real browser, through the Playwright specs in web/e2e/sign-in/: what answers without a session,
#     the sign-in page, a wrong password, the password toggle, the README sign-in, the tokens and fonts, one sign-in
#     group, Sign out, a user without the OcuTalon user role, and a deep link.
# The project is unique and receives no keys. It publishes its web port only on 127.0.0.1, on the first free port of
# 52800-52819 (or OCUTALON_TEST_WEB_PORT), for the browser. The no-role user gets a random password that is passed by
# environment variable and never printed. An EXIT trap removes the project with its volume and images. Every wait ends
# by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or
# later, and the browser: npx --prefix web playwright install chromium.
set -u

LIVE_REBUILD_WEB=1
. "$(dirname "$0")/lib-live.sh"
live_start t03
live_web_port || exit 1

noroleuser=ZzNoRole
noropassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"

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

# --- the user without a role (row 12) ---

created=$(printf '%s\n' \
  'Set pw=$SYSTEM.Util.GetEnviron("OCUTALON_T03_PW")' \
  "Set sc=##class(Security.Users).Create(\"$noroleuser\",\"\",pw,\"no-role fixture\",\"OCUTALON\",\"\",\"\",0,1,\"t03 fixture\",1,\"\",\"\",,1,1)" \
  'Write !,"CHK|norole-user|",$SYSTEM.Status.IsOK(sc)' \
  'Halt' \
  | OCUTALON_T03_PW="$noropassword" dc exec -T -e OCUTALON_T03_PW iris iris session IRIS -U %SYS 2>/dev/null | tr -d '\r' | sed -n 's/.*\(CHK|norole-user|.*\)$/\1/p' | tail -n 1)
if [ "$created" = "CHK|norole-user|1" ]; then
  pass "the fixture user without roles is created"
else
  die "the fixture user without roles could not be created ('$created')"
fi

# --- rows 3 to 13: the browser ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed fill step can echo what was typed: the fixture's
# password is replaced before anything reaches the terminal.
show_log() { tail -n "$1" "$e2e_log" | sed "s/$noropassword/<redacted>/g; s/^/  /"; }
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_NOROLE_USER="$noroleuser" \
  OCUTALON_NOROLE_PASSWORD="$noropassword" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e > "$e2e_log" 2>&1
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 30
  pass "rows 3-13: the Playwright specs pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tail -n 1))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 3-13: the Playwright specs failed (exit $e2e_status)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-sign-in: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-sign-in: all checks passed"
