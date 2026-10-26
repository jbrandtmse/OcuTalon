#!/usr/bin/env bash
# Live test of the online demo's real start (Story 16.1; AD-13, AD-19, AD-23, AD-24, AD-25): builds the image and starts it in one
# throwaway compose project with the online-demo flag on and test start values, and checks, in this order:
#   - the start (rows 1 to 3): the log's STEP lines are the expected run (Bridge.Installer, Public, Roles, Users, Web, ... Ready), every step
#     OK, RESULT OK and readiness 1; each of the 13 public keys reads back as its start value through Public.Settings and through
#     Setting.Get (a password is compared inside IRIS and printed as 1 or 0); /ocutalon/public/status reports the next reset that NextReset
#     computes, on a 4-hour step of the anchor, with busy false and the last reset as given; Decide's three budget rows;
#   - the public accounts and the password guard (row 4): the roles, the flags, the README account disabled, the guard setting and routine
#     (no staging routine, no password in the source) and the Visual Trace page size 100 in OCUTALON and OCUORDERS for both names;
#   - every password-change form of spike S17 over HTTP (rows 5 and 6), F1 to F11 of the spec, from curl: each is sent for the demo account,
#     the read-only account (name in capitals) and a control user with no public account, and afterwards both public accounts still sign in
#     with their published passwords and not with the attempted one, while the control's password changed exactly for the forms of
#     CHANGE_FORMS (Task 0 measured them on build 154; a change in IRIS's behaviour turns this unit red in either direction); the sign-in
#     page has no old-password or repeat-password field and neither has a trace application's page for %CSP.PasswordChange.cls with no
#     session; F12 posts IRIS's own password-change page of each trace application (served to a signed-in user on build 154) the same way;
#   - the splash with no session (Story 16.2, row 11): the /ocutalon* applications in IRIS are exactly the five, every OcuTalon path that
#     needs a sign-in gives the splash (the h1, no app-root, the splash's exact policy over its own two hashed blocks, and no-store), a
#     sign-in image is served, /ocutalon/public/status answers and /ocutalon/public/x does not, the API answers 401 signed_out and the
#     trace applications' pages give IRIS's sign-in page; the splash form's input names are printed as "MEASURED splash form inputs:"
#     and none is outside the four of the proxy's allow-list;
#   - the visitor's own session (Story 16.3), after the splash checks: row 12, six sign-ins from one forwarded address in the first phase
#     (the proxy address is one that no request comes from) are all exempt and write no counter row; row 4, a sign-in at the OCUTALON
#     trace application sets no resume cookie and creates no Session row, and the same jar's first /ocutalon/ request does; row 6, a
#     sign-in, a real message, a resume with the cookie and a sign-out, after which the resume reference is searched for in the container's
#     logs, the event log, the live events, the audit log and every global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC (counts
#     only; it runs with the password searches, after the browser and after the restart); row 14, the seeded address limit; Task 0's
#     MEASURED lines (the resume Set-Cookie attributes, the browser's Secure cookie, the host's REMOTE_ADDR, CSP session id reuse);
#   - the browser (rows 7 to 12, and the splash's S1 to S12, S2b, S6b and S8b and the REL-2 online run's step 1 of Story 16.2, and Story
#     16.3's R1, R2, R4 and R5): the project online-demo of web/playwright.config.ts (web/e2e-online/) as both public accounts;
#   - the proxied phase (Story 16.3, rows 10 and 11 and Task 0 (c)): the public proxy address is set to the address IRIS sees for this
#     host's requests, a first proxied sign-in must write a counter row (else the check fails naming the derived address), then five
#     sign-ins from one forwarded address are counted and the sixth is refused with the splash's field error, a cookie sign-in resumes,
#     "A, C" counts C, and address-limit.spec.ts (L1) runs the page case; the proxy address is put back and read back on every path;
#   - neither published password is in the container's output, messages.log, the after-start log, the production event log, the live
#     events or the audit log, checked after the browser and again after the restart;
#   - a restart (row 13): the second start's STEP lines are the expected run for a restart, all OK, ready, the guard setting still
#     Check^OcuTalonPasswordGuard and both public accounts still sign in with their published passwords.
# Test start values (a compose override written to this run's temporary folder, never a tracked file): OCUTALON_ONLINE_DEMO=1, the demo
# account DemoVisitor and the read-only account TraceReader with random passwords per run (hex, passed to compose by ${VAR} interpolation so
# that they are in no file, and replaced by <redacted> in every line this script prints), a 4-hour reset step from the anchor
# 2026-10-18T00:00:00Z (quoted in the override, which compose would otherwise read as a timestamp), the last reset 2026-10-25T08:00:00Z (scheduled), the proxy address 192.0.2.10 (TEST-NET: no request of this test is
# proxied), a connection cap of 8 with a reserve of 2, 50 messages an hour, a daily cost cap of 20 USD and no gateway variable.
# Every request that signs in ends with ?IRISLogout=end on its application and on /ocutalon/, each with its own cookie jar, so that no form
# leaves a licence connection held; every page request carries a unique probe=<n> query parameter, because the web gateway keeps the answer
# to a URL (test-bundle-folder.sh). No password is ever printed.
# It does not rebuild the web bundle: ci/iris.sh build makes it, as for the other browser units. The project is unique and publishes its web
# port only on 127.0.0.1, on the first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). An EXIT trap removes the project with its volume
# and images. Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI, counted from the moment the
# throwaway lock is held); the browser run's global timeout is what is left of it minus 20 s, and the browser does not start with under 60 s left.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later, curl, the
# built web bundle and Chromium (npx --prefix web playwright install chromium; ci/iris.sh live installs it).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start online-demo
live_web_port || exit 1

version=$(manifest_version src/module.xml)
ipm_version=0.10.10
base="http://127.0.0.1:$web_port"

hexpw() { LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32; }

demo_user=DemoVisitor
readonly_user=TraceReader
readonly_user_caps=TRACEREADER
control_user=ZzOnlineControl
demo_password=$(hexpw)
readonly_password=$(hexpw)
control_password=$(hexpw)
anchor=2026-10-18T00:00:00Z
last_reset=2026-10-25T08:00:00Z

# The forms of S17 that change a password on build 154, as "<form>@<where>" for every request that does (Task 0 measured them; the unit
# asserts both directions: a listed request changes the control's password, an unlisted one does not). <where> is root (/ocutalon/), state
# (/ocutalon/api/v1/state), trace-ocutalon and trace-ocuorders (the message viewers, posted with the session token of their sign-in page) and
# pwpage-ocutalon and pwpage-ocuorders (F12, IRIS's own password-change page of a trace application). Measured on build 154: every form but
# F11 (names in mixed case) changes it at /ocutalon/, F1 and F3 also at /ocutalon/api/v1/state and at both trace applications, and F12 at both.
CHANGE_FORMS="F1@root F1@state F1@trace-ocutalon F1@trace-ocuorders F2@root F3@root F3@state F3@trace-ocutalon F3@trace-ocuorders F4@root F5@root F6@root F7@root F8@root F9@root F10@root F12@pwpage-ocutalon F12@pwpage-ocuorders"

# No password of the run, current or attempted, is printed: the checks print names, outcomes and counts (a password is compared
# inside IRIS or by curl), and every tail of a log that this script shows passes through redact.
# The resume reference of row 6 is one more such value, once it is known.
resume_ref=
redact() { sed "s/$demo_password/<redacted>/g; s/$readonly_password/<redacted>/g; s/$control_password/<redacted>/g${resume_ref:+; s/$resume_ref/<redacted>/g}"; }

# An attempted (new) password is random too, and is never printed.
new_attempt() { hexpw; }

# --- the test start values: an override in this run's temporary folder; the passwords come from the environment of docker compose ---

export OCUTALON_TEST_DEMO_PASSWORD="$demo_password" OCUTALON_TEST_READONLY_PASSWORD="$readonly_password"
printf '%s\n' \
  'services:' \
  '  iris:' \
  '    environment:' \
  '      OCUTALON_ONLINE_DEMO: "1"' \
  "      OCUTALON_DEMO_USER: $demo_user" \
  '      OCUTALON_DEMO_PASSWORD: ${OCUTALON_TEST_DEMO_PASSWORD}' \
  "      OCUTALON_READONLY_USER: $readonly_user" \
  '      OCUTALON_READONLY_PASSWORD: ${OCUTALON_TEST_READONLY_PASSWORD}' \
  '      OCUTALON_RESET_INTERVAL_HOURS: "4"' \
  "      OCUTALON_RESET_ANCHOR: \"$anchor\"" \
  "      OCUTALON_LAST_RESET: \"$last_reset\"" \
  '      OCUTALON_LAST_RESET_KIND: scheduled' \
  '      OCUTALON_PROXY_ADDRESS: 192.0.2.10' \
  '      OCUTALON_CONNECTION_CAP: "8"' \
  '      OCUTALON_CONNECTION_RESERVE: "2"' \
  '      OCUTALON_MESSAGE_ALLOWANCE: "50"' \
  '      OCUTALON_DAILY_COST_CAP_USD: "20"' > "$tmp/online-demo.yml"
live_add_file "$tmp/online-demo.yml"

# --- build and start (row 1) ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log" | redact
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200 | redact
  dc logs --tail 20 iris 2>&1 | cut -c1-200 | redact
  die "row 1 the first start did not end ready within 400 s"
fi
pass "row 1 the first start ended ready"

expected_run "nothing to clear" "installed $ipm_version (was none)" "mapped into OCUTALON" "skipped (package not installed)" \
  "loaded (not installed)" "$version" > "$tmp/expected.row1"
check_log "row 1" "$tmp/expected.row1"
check_no_key "row 1"

# --- row 2: every key, through the accessor and through Setting.Get ---

# The lines that print each key through the accessor and through Setting.Get; a password is compared inside IRIS with the start variable.
keys_lines=()
for k in onlineDemo demoUser readonlyUser resetIntervalHours resetAnchor lastReset lastResetKind proxyAddress connectionCap connectionReserve messageAllowance ready; do
  keys_lines+=("Write !,\"CHK|$k|\",##class(OcuTalon.Data.Public.Settings).Get(\"$k\"),\"|\",##class(OcuTalon.Data.Setting).Get(\"$k\")")
done
for pair in demoPassword:OCUTALON_DEMO_PASSWORD readonlyPassword:OCUTALON_READONLY_PASSWORD; do
  keys_lines+=("Set e=\$SYSTEM.Util.GetEnviron(\"${pair#*:}\") Write !,\"CHK|${pair%%:*}|\",((e'=\"\")&&(##class(OcuTalon.Data.Public.Settings).Get(\"${pair%%:*}\")=e)),\"|\",((e'=\"\")&&(##class(OcuTalon.Data.Setting).Get(\"${pair%%:*}\")=e))")
done
check_session "row 2: all 13 keys and readiness read back as their start values through the accessor and through Setting.Get" OCUTALON \
  "CHK|onlineDemo|1|1
CHK|demoUser|$demo_user|$demo_user
CHK|readonlyUser|$readonly_user|$readonly_user
CHK|resetIntervalHours|4|4
CHK|resetAnchor|$anchor|$anchor
CHK|lastReset|$last_reset|$last_reset
CHK|lastResetKind|scheduled|scheduled
CHK|proxyAddress|192.0.2.10|192.0.2.10
CHK|connectionCap|8|8
CHK|connectionReserve|2|2
CHK|messageAllowance|50|50
CHK|ready|1|1
CHK|demoPassword|1|1
CHK|readonlyPassword|1|1" \
  "${keys_lines[@]}" 'Halt'

# next_probe sets probes to a number that no request of this run used, also across the subshells of $(...): the counter lives in a file.
probe_file="$tmp/probe.n"
echo 0 > "$probe_file"
next_probe() {
  probes=$(($(cat "$probe_file") + 1))
  echo "$probes" > "$probe_file"
}

computed_next=$(printf '%s\n' 'Write !,"CHK|next|",##class(OcuTalon.Data.Public.Settings).NextReset()' 'Halt' | session_value OCUTALON next)
next_probe
status_json=$(curl -s --max-time 30 "$base/ocutalon/public/status?probe=$probes")
status_verdict=$(node - "$status_json" "$computed_next" "$anchor" "$last_reset" <<'EOF'
const [, , json, computed, anchor, lastReset] = process.argv;
const problems = [];
let status = {};
try {
  status = JSON.parse(json);
} catch {
  problems.push('the answer is not JSON');
}
const step = 4 * 3600 * 1000;
const next = Date.parse(status.nextReset ?? '');
const now = Date.now();
if (status.ready !== true) problems.push('ready is not true');
if (!computed || status.nextReset !== computed) problems.push('nextReset is not what NextReset() computes');
if (!Number.isFinite(next) || (next - Date.parse(anchor)) % step !== 0) problems.push('nextReset is not on a 4-hour step of the anchor');
if (!(next > now)) problems.push('nextReset is not later than now');
if (next - now > step) problems.push('nextReset is more than 4 hours away');
if (status.busy !== false) problems.push('busy is not false');
if (status.lastReset !== lastReset) problems.push('lastReset differs');
if (status.lastResetKind !== 'scheduled') problems.push('lastResetKind differs');
console.log(problems.length === 0 ? 'ok' : problems.join('; '));
EOF
)
if [ "$status_verdict" = ok ]; then
  pass "row 2: /ocutalon/public/status is ready, its nextReset is NextReset() on a 4-hour step of the anchor (later than now, at most 4 hours away), busy is false and the last reset is as given"
else
  fail "row 2: /ocutalon/public/status: $status_verdict"
fi

# --- row 3: Decide's budget rows ---

check_session "row 3: Decide's budget rows are the cap 20 and an empty spend and date" OCUTALON \
  "CHK|row|DailyCostCapUSD|[20]
CHK|row|GatewaySpendUSD|[]
CHK|row|GatewaySpendDate|[]" \
  'For s="DailyCostCapUSD","GatewaySpendUSD","GatewaySpendDate" { Set id="OcuTalon.Production||Decide||*||"_s Write !,"CHK|row|",s,"|",$Select(##class(Ens.Config.DefaultSettings).%ExistsId(id):"["_##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue_"]",1:"<none>") }' \
  'Halt'

# --- row 4: the public accounts and the guard ---
# The README account is not enabled: on a fresh flag-on volume it is never created, and one that exists is disabled; both read as 0.

check_session "row 4: the accounts, the README account, the guard and the page size pins" %SYS \
  "CHK|acct|$demo_user|OcuTalonTraceViewer,OcuTalonUser|1|0|1|1
CHK|acct|$readonly_user|OcuTalonTraceViewer|1|0|1|1
CHK|readme-enabled|0
CHK|validation|Check^OcuTalonPasswordGuard
CHK|guard-routine|1|0
CHK|guard-holds|OCUTALON_DEMO_PASSWORD|0
CHK|guard-holds|OCUTALON_READONLY_PASSWORD|0
CHK|pin|$demo_user|OCUTALON|100
CHK|pin|$demo_user|OCUORDERS|100
CHK|pin|$readonly_user|OCUTALON|100
CHK|pin|$readonly_user|OCUORDERS|100" \
  "For u=\"$demo_user\",\"$readonly_user\" { Kill o,r If '##class(Security.Users).Exists(u,.o) { Write !,\"CHK|acct|\",u,\"|<missing>\" Continue } For i=1:1:o.Roles.Count() { Set r(o.Roles.GetAt(i))=1 } Set rl=\"\",k=\"\" For { Set k=\$Order(r(k)) Quit:k=\"\"  Set rl=rl_\$Select(rl=\"\":\"\",1:\",\")_k } Write !,\"CHK|acct|\",u,\"|\",rl,\"|\",o.Enabled,\"|\",o.ChangePassword,\"|\",o.PasswordNeverExpires,\"|\",o.AccountNeverExpires }" \
  'If ##class(Security.Users).Exists("ocutalon",.m) { Write !,"CHK|readme-enabled|",m.Enabled } Else { Write !,"CHK|readme-enabled|0" }' \
  'Do ##class(Security.System).Get(,.sp) Write !,"CHK|validation|",$Get(sp("PasswordValidationRoutine"))' \
  'Write !,"CHK|guard-routine|",##class(%Routine).Exists("OcuTalonPasswordGuard.mac"),"|",##class(%Routine).Exists("OcuTalonPasswordGuardNew.mac")' \
  'Set rt=##class(%Routine).%New("OcuTalonPasswordGuard.mac") Set src="" While '"'"'rt.AtEnd { Set src=src_rt.ReadLine()_$Char(10) }' \
  'For p="OCUTALON_DEMO_PASSWORD","OCUTALON_READONLY_PASSWORD" { Set e=$SYSTEM.Util.GetEnviron(p) Write !,"CHK|guard-holds|",p,"|",((e'"'"'="")&&($Find(src,e)>0)) }' \
  "For u=\"$demo_user\",\"$readonly_user\" { For n=\"OCUTALON\",\"OCUORDERS\" { Write !,\"CHK|pin|\",u,\"|\",n,\"|\",\$Get(^|n|EnsPortal.Settings(u,\"VisualTrace\",\"ItemsPerPage\")) } }" \
  'Halt'

# --- the control user: no public account, the role OcuTalonUser, so that it signs in to the shell ---

created=$(live_fixture_user "$control_user" "$control_password" "OcuTalonUser" "online-demo control")
if [ "$created" = "CHK|fixture-user|1" ]; then
  pass "the control user $control_user (role OcuTalonUser) is created"
else
  die "the control user $control_user could not be created ('$created')"
fi

# --- rows 5 and 6: the password-change forms over HTTP ---

# pct <text>: every byte of the text as %XX.
pct() {
  local s=$1 out="" i
  for ((i = 0; i < ${#s}; i++)); do
    out="$out$(printf '%%%02X' "'${s:i:1}")"
  done
  printf '%s' "$out"
}

# logout_all <jar> <application path>: ends the session of the jar on the application and on /ocutalon/, each with a unique probe.
logout_all() {
  next_probe
  curl -s --max-time 30 -o /dev/null -b "$1" -c "$1" "$base$2?IRISLogout=end&probe=$probes"
  next_probe
  curl -s --max-time 30 -o /dev/null -b "$1" -c "$1" "$base/ocutalon/?IRISLogout=end&probe=$probes"
}

# signin_outcome <user> <password>: a plain sign-in POST to /ocutalon/, on a jar of its own, and what it led to, ended with a sign-out:
#   shell    IRIS accepted it and the page is the application's shell;
#   norole   IRIS accepted it and the page says the account has no OcuTalon user role;
#   refused  the sign-in page with the failed-sign-in error (aria-invalid);
#   other    anything else.
signin_outcome() {
  local jar answer code body outcome
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/?probe=$probes"
  next_probe
  answer=$(curl -s --max-time 30 -c "$jar" -b "$jar" -w '\n%{http_code}' --data-urlencode "IRISUsername=$1" --data-urlencode "IRISPassword=$2" \
    --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/?probe=$probes")
  code=${answer##*$'\n'}
  body=${answer%$'\n'*}
  case $code in
    3??)
      next_probe
      body=$(curl -s --max-time 30 -c "$jar" -b "$jar" "$base/ocutalon/?probe=$probes")
      ;;
  esac
  case $body in
    *'aria-invalid="true"'*) outcome=refused ;;
    *'user role. Ask an OcuTalon admin to add it.'*) outcome=norole ;;
    *'<app-root'*) outcome=shell ;;
    *) outcome=other ;;
  esac
  logout_all "$jar" /ocutalon/
  printf '%s' "$outcome"
}

# page_token <jar> <url>: the IRISSessionToken that the sign-in or password-change page of the url puts in its form (the jar takes the session
# cookie), or nothing. A trace application's form is posted with it, as a browser posts it.
page_token() {
  curl -s --max-time 30 -c "$1" -b "$1" "$2" | sed -n 's/.*name="IRISSessionToken" value="\([^"]*\)".*/\1/p' | head -n 1
}

# form_request <form> <path> <app path> <user> <old> <new>: sends the form to the path on a jar of its own and signs out. A trace
# application's F1 and F3 carry the session token of its sign-in page; F12 signs in at the application with its form first, then posts
# the password-change page's own form with that page's token.
form_request() {
  local form=$1 path=$2 app=$3 user=$4 old=$5 new=$6 jar url u o p l
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  url="$base$path?probe=$probes"
  case $form in
    F2 | F4 | F9) u=CacheUserName o=CacheOldPassword p=CachePassword l=CacheLogin ;;
    F11) u=irisusername o=IrisOldPassword p=irispassword l=irislogin ;;
    *) u=IRISUsername o=IRISOldPassword p=IRISPassword l=IRISLogin ;;
  esac
  local common=(-s --max-time 30 -o /dev/null -c "$jar" -b "$jar")
  local token="" plain="$u=$user&$o=$old&$p=$new&$l=Sign+in"
  case $path in
    /ocutalon/trace/*)
      if [ "$form" = F12 ]; then
        next_probe
        token=$(page_token "$jar" "$base${app}EnsPortal.MessageViewer.zen?probe=$probes")
        [ -n "$token" ] || fail "row 5: $form for $user at $path: the application's sign-in page gave no session token, so the request cannot sign in"
        next_probe
        curl "${common[@]}" --data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$user" --data-urlencode "IRISPassword=$old" \
          --data-urlencode 'IRISLogin=Login' "$base${app}EnsPortal.MessageViewer.zen?probe=$probes"
        next_probe
        token=$(page_token "$jar" "$url")
        [ -n "$token" ] || fail "row 5: $form for $user at $path: the password-change page gave no session token, so the request cannot sign in"
        next_probe
        curl "${common[@]}" --data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$user" --data-urlencode "IRISOldPassword=$old" \
          --data-urlencode "IRISPassword=$new" --data-urlencode "IRISRepeatPassword=$new" --data-urlencode 'IRISLogin=Login' "$base$path?probe=$probes"
        logout_all "$jar" "$app"
        return 0
      fi
      case $form in
        F1 | F3)
          next_probe
          token=$(page_token "$jar" "$base$path?probe=$probes")
          [ -n "$token" ] || fail "row 5: $form for $user at $path: the application's sign-in page gave no session token, so the request cannot sign in"
          ;;
      esac
      ;;
  esac
  case $form in
    F1 | F2) curl "${common[@]}" ${token:+--data-urlencode IRISSessionToken=$token} --data-urlencode "$u=$user" --data-urlencode "$o=$old" --data-urlencode "$p=$new" --data-urlencode "$l=Sign in" "$url" ;;
    F3 | F4) curl "${common[@]}" -G ${token:+--data-urlencode IRISSessionToken=$token} --data-urlencode "$u=$user" --data-urlencode "$o=$old" --data-urlencode "$p=$new" --data-urlencode "$l=Sign in" "$url" ;;
    F5) curl "${common[@]}" --data-binary '' "$url&$plain" ;;
    F6)
      curl "${common[@]}" --data-raw "IRISUsername=$user&IRIS$(pct OldPassword)=$old&IRIS$(pct Password)=$new&IRISLogin=Sign+in" "$url"
      ;;
    F7) curl "${common[@]}" "$url&IRISUsername=$user&IRIS$(pct OldPassword)=$old&IRIS$(pct Password)=$new&IRISLogin=Sign+in" ;;
    F8 | F9) curl "${common[@]}" -F "$u=$user" -F "$o=$old" -F "$p=$new" -F "$l=Sign in" "$url" ;;
    F10) curl "${common[@]}" -H 'Transfer-Encoding: chunked' --data-raw "$plain" "$url" ;;
    F11) curl "${common[@]}" --data-raw "$plain&IRISRepeatPassword=$new" "$url" ;;
  esac
  logout_all "$jar" "$app"
}

# The password that the control user has now: a form that changes it moves this to the attempted one.
control_now=$control_password

# in_change_forms <form@where>: 0 when the request is listed.
in_change_forms() { case " $CHANGE_FORMS " in *" $1 "*) return 0 ;; esac; return 1; }

# measured: the requests that changed the control's password in this run, for the report.
measured=""

# run_form <form> <where> <path> <app path>
run_form() {
  local form=$1 where=$2 path=$3 app=$4 key new target name published accepted shown outcome_ok outcome_bad
  key="$form@$where"
  for target in demo readonly control; do
    new=$(new_attempt)
    case $target in
      demo) name=$demo_user shown=$demo_user published=$demo_password accepted=shell ;;
      readonly) name=$readonly_user_caps shown=$readonly_user published=$readonly_password accepted=norole ;;
      control) name=$control_user shown=$control_user published=$control_now accepted=shell ;;
    esac
    form_request "$form" "$path" "$app" "$name" "$published" "$new"
    outcome_ok=$(signin_outcome "$shown" "$published")
    outcome_bad=$(signin_outcome "$shown" "$new")
    case $target in
      demo | readonly)
        if [ "$outcome_ok" = "$accepted" ] && [ "$outcome_bad" = refused ]; then
          pass "row 5: $key for the $target account: its published password still signs in ($accepted) and the attempted one does not"
        else
          fail "row 5: $key for the $target account: the published password gives '$outcome_ok' (wanted $accepted) and the attempted one '$outcome_bad' (wanted refused)"
        fi
        ;;
      control)
        if [ "$outcome_bad" = shell ] && [ "$outcome_ok" = refused ]; then
          control_now=$new
          measured="$measured $key"
          if in_change_forms "$key"; then
            pass "row 5: $key changes the control's password, as CHANGE_FORMS says"
          else
            fail "row 5: $key changes the control's password, and CHANGE_FORMS does not list it"
          fi
        elif [ "$outcome_ok" = shell ] && [ "$outcome_bad" = refused ]; then
          if in_change_forms "$key"; then
            fail "row 5: $key leaves the control's password, and CHANGE_FORMS lists it"
          else
            pass "row 5: $key leaves the control's password, as CHANGE_FORMS says"
          fi
        else
          fail "row 5: $key for the control: the current password gives '$outcome_ok' and the attempted one '$outcome_bad' (wanted one shell and one refused)"
        fi
        ;;
    esac
  done
}

for form in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11; do
  run_form "$form" root /ocutalon/ /ocutalon/
  case $form in
    F1 | F3)
      run_form "$form" state /ocutalon/api/v1/state /ocutalon/api/
      run_form "$form" trace-ocutalon /ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen /ocutalon/trace/ocutalon/
      run_form "$form" trace-ocuorders /ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen /ocutalon/trace/ocuorders/
      ;;
  esac
done
# F12: the page %CSP.PasswordChange.cls that each trace application serves to a signed-in user (see row 6).
run_form F12 pwpage-ocutalon /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls /ocutalon/trace/ocutalon/
run_form F12 pwpage-ocuorders /ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls /ocutalon/trace/ocuorders/
echo "MEASURED the requests that changed the control's password:${measured:- none}"

next_probe
login_page=$(curl -s --max-time 30 "$base/ocutalon/?probe=$probes")
case $login_page in
  *'Try OcuTalon in two minutes'*) login_shown=1 ;;
  *) login_shown=0 ;;
esac
if [ "$login_shown" = 1 ] && ! printf '%s' "$login_page" | grep -Eqi 'name="[^"]*(OldPassword|RepeatPassword)'; then
  pass "row 6: the sign-in page has no old-password or repeat-password field"
else
  fail "row 6: the sign-in page is missing, or offers an old-password or repeat-password field"
fi
# With no session a trace application shows IRIS's own sign-in page for %CSP.PasswordChange.cls (build 154 answers 200 and the page holds no
# old-password or repeat-password field). Signed in, build 154 serves IRIS's own password-change page there with 200, not 404 (measured):
# no OcuTalon page offers a change, but IRIS's does, so the guard decides, as F12 above shows for both public accounts.
for app in ocutalon ocuorders; do
  next_probe
  answer=$(curl -s --max-time 30 -w '\n%{http_code}' "$base/ocutalon/trace/$app/%25CSP.PasswordChange.cls?probe=$probes")
  code=${answer##*$'\n'}
  anonymous=${answer%$'\n'*}
  if [ "$code" = 200 ] && printf '%s' "$anonymous" | grep -Eq 'name="?IRISPassword' \
    && ! printf '%s' "$anonymous" | grep -Eqi 'name="?[^" >]*(OldPassword|RepeatPassword)'; then
    pass "row 6: with no session the $app trace application's page for %CSP.PasswordChange.cls is IRIS's sign-in page (200, a password field) with no old-password or repeat-password field"
  else
    fail "row 6: with no session the $app trace application's page for %CSP.PasswordChange.cls is not IRIS's sign-in page (status '$code', or no password field) or offers a password-change field"
  fi
done

# --- Story 16.2, row 11: with no session, every OcuTalon path gives the splash, the status or a sign-in page ---

# splash_get <path>: GETs the path on a jar of its own with a unique probe, leaves the body in $tmp/splash.body, ends the jar's session
# on /ocutalon/ and prints the HTTP status.
splash_get() {
  local jar code sep='?'
  next_probe
  jar="$tmp/jar.$probes"
  : > "$jar"
  case $1 in *\?*) sep='&' ;; esac
  rm -f "$tmp/splash.headers" "$tmp/splash.body"
  code=$(curl -s --max-time 30 -D "$tmp/splash.headers" -o "$tmp/splash.body" -w '%{http_code}' -c "$jar" -b "$jar" "$base$1${sep}probe=$probes")
  logout_all "$jar" /ocutalon/
  printf '%s' "$code"
}

# splash_envelope: reads $tmp/splash.headers and $tmp/splash.body (QA): prints "ok" when the Content-Security-Policy header is the
# splash's policy over the SHA-256 of the body's one <style> and one <script> (exactly one script hash, one style hash, no
# unsafe-inline or unsafe-eval) and Cache-Control is no-store, otherwise what differs.
splash_envelope() {
  node -e '
    const fs = require("fs"), crypto = require("crypto");
    const headers = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/);
    const body = fs.readFileSync(process.argv[2], "utf8");
    const header = (name) => headers.filter((line) => line.toLowerCase().startsWith(name + ":")).map((line) => line.slice(name.length + 1).trim());
    const hash = (text) => crypto.createHash("sha256").update(text, "utf8").digest("base64");
    const styles = [...body.matchAll(/<style>([\s\S]*?)<\/style>/g)], scripts = [...body.matchAll(/<script>([\s\S]*?)<\/script>/g)];
    const problems = [];
    if (styles.length !== 1 || scripts.length !== 1) problems.push("the body has " + styles.length + " style and " + scripts.length + " script blocks");
    const policy = header("content-security-policy");
    if (policy.length !== 1) problems.push(policy.length + " Content-Security-Policy headers");
    const want = "default-src \x27none\x27; script-src \x27sha256-" + hash(scripts[0] ? scripts[0][1] : "") + "\x27; style-src \x27sha256-" + hash(styles[0] ? styles[0][1] : "") + "\x27; img-src \x27self\x27; form-action \x27self\x27; frame-ancestors \x27none\x27; base-uri \x27none\x27";
    if (policy[0] !== want) problems.push("policy is not the splash policy over the body blocks");
    if (/unsafe-/.test(policy.join(" "))) problems.push("policy has an unsafe- keyword");
    if ((policy.join(" ").match(/sha256-/g) || []).length !== 2) problems.push("policy does not hold exactly two hashes");
    if (header("cache-control").join(",") !== "no-store") problems.push("Cache-Control is " + header("cache-control").join(","));
    console.log(problems.length === 0 ? "ok" : problems.join("; "));
  ' "$tmp/splash.headers" "$tmp/splash.body" 2>&1 | tr '\n' ' '
}

check_session "row 11: the /ocutalon* applications in IRIS are exactly the five" %SYS \
  "CHK|apps|/ocutalon,/ocutalon/api,/ocutalon/public,/ocutalon/trace/ocuorders,/ocutalon/trace/ocutalon" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM Security.Applications WHERE Name LIKE ? ORDER BY Name","/ocutalon%") Set l="" While rs.%Next() { Set l=l_$Select(l="":"",1:",")_rs.%Get("Name") } Write !,"CHK|apps|",l' \
  'Halt'

bundle_main=$(dc exec -T iris sh -c "ls /durable/iris/csp/ocutalon-web" 2>/dev/null | tr -d '\r' | grep -E '^main-[A-Za-z0-9]+\.js$' | head -n 1)
if [ -z "$bundle_main" ]; then
  fail "row 11: no main-<hash>.js bundle file in the stack's web folder"
  bundle_main=main.js
fi
for path in /ocutalon/ '/ocutalon/x/y?a=1' /ocutalon/index.html "/ocutalon/$bundle_main"; do
  code=$(splash_get "$path")
  if [ "$code" = 200 ] && grep -q '<h1>Try OcuTalon in two minutes</h1>' "$tmp/splash.body" && ! grep -q '<app-root' "$tmp/splash.body"; then
    pass "row 11: with no session $path gives the splash (200, its h1, no app-root)"
  else
    fail "row 11: with no session $path gives status '$code', not the splash"
  fi
  envelope=$(splash_envelope)
  if [ "$envelope" = "ok " ]; then
    pass "row 11 (QA): $path is answered with the splash's exact policy over its one style and one script (two hashes, no unsafe- keyword) and no-store"
  else
    fail "row 11 (QA): $path's envelope: $envelope"
  fi
  if [ "$path" = '/ocutalon/x/y?a=1' ]; then
    inputs=$(grep -o '<input [^>]*' "$tmp/splash.body" | sed -n 's/.* name="\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ')
    echo "MEASURED splash form inputs: ${inputs% }"
    outside=
    for name in $inputs; do
      case $name in IRISSessionToken | IRISUsername | IRISPassword | IRISLogin) ;; *) outside="$outside $name" ;; esac
    done
    if [ -z "$outside" ] && printf '%s' "$inputs" | grep -q IRISUsername; then
      pass "row 7: the splash form's input names are within IRISSessionToken, IRISUsername, IRISPassword and IRISLogin"
    else
      fail "row 7: the splash form's input names are outside the four of the proxy's allow-list:${outside:- (or the form has no user name field)}"
    fi
  fi
done

next_probe
jar="$tmp/jar.$probes"
: > "$jar"
logo=$(curl -s --max-time 30 -o /dev/null -w '%{http_code} %{content_type}' -c "$jar" -b "$jar" "$base/ocutalon/assets/brand/OcuTalon-Logo-light-640.png?probe=$probes")
logout_all "$jar" /ocutalon/
if [ "$logo" = '200 image/png' ]; then
  pass "row 11: with no session the 1x logo is served as image/png"
else
  fail "row 11: with no session the 1x logo gives '$logo', wanted '200 image/png'"
fi

code=$(splash_get /ocutalon/public/status)
status_keys=$(node -e 'try { console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).sort().join(",")); } catch { console.log("not JSON"); }' "$tmp/splash.body")
if [ "$code" = 200 ] && [ "$status_keys" = busy,lastReset,lastResetKind,nextReset,ready ]; then
  pass "row 11: /ocutalon/public/status gives 200 JSON with its five keys"
else
  fail "row 11: /ocutalon/public/status gives status '$code' and keys '$status_keys'"
fi
code=$(splash_get /ocutalon/public/x)
if [ "$code" = 404 ]; then
  pass "row 11: /ocutalon/public/x gives 404"
else
  fail "row 11: /ocutalon/public/x gives '$code', wanted 404"
fi
for path in /ocutalon/api/v1/state /ocutalon/api/v1/events; do
  code=$(splash_get "$path")
  if [ "$code" = 401 ] && grep -q 'signed_out' "$tmp/splash.body"; then
    pass "row 11: with no session $path gives 401 signed_out"
  else
    fail "row 11: with no session $path gives status '$code' (wanted 401 with signed_out)"
  fi
done
for app in ocutalon ocuorders; do
  for page in EnsPortal.VisualTrace.zen EnsPortal.MessageViewer.zen; do
    code=$(splash_get "/ocutalon/trace/$app/$page")
    if [ "$code" = 200 ] && grep -Eq 'name="?IRISPassword' "$tmp/splash.body" && ! grep -q '<app-root' "$tmp/splash.body" \
      && ! grep -q 'Try OcuTalon in two minutes' "$tmp/splash.body"; then
      pass "row 11: with no session the $app trace application's $page is IRIS's sign-in page (200, a password field, no app-root, not the splash)"
    else
      fail "row 11: with no session the $app trace application's $page gives status '$code', not IRIS's sign-in page"
    fi
  done
done

# --- Story 16.3: the visitor's own session (rows 4, 6, 12 and 14, and Task 0's MEASURED lines) ---

# online_signin <jar> <forwarded address or ""> <resume cookie value or "">: the splash GET and the sign-in POST of the demo account on the
# jar, with X-Forwarded-For when an address is given and the resume cookie when a value is given. It prints the POST's HTTP status, and
# leaves the POST's headers in <jar>.h, the final page in <jar>.b and, after a redirect, the first /ocutalon/ GET's headers in <jar>.g.
online_signin() {
  local jar=$1 forwarded=$2 cookie=$3 code
  local args=(-s --max-time 30 -c "$jar" -b "$jar")
  if [ -n "$forwarded" ]; then args+=(-H "X-Forwarded-For: $forwarded"); fi
  if [ -n "$cookie" ]; then args+=(-b "OcuTalonResume=$cookie"); fi
  rm -f "$jar.h" "$jar.g" "$jar.b"
  next_probe
  curl "${args[@]}" -o /dev/null "$base/ocutalon/?probe=$probes"
  next_probe
  code=$(curl "${args[@]}" -D "$jar.h" -o "$jar.b" -w '%{http_code}' --data-urlencode "IRISUsername=$demo_user" --data-urlencode "IRISPassword=$demo_password" \
    --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/?probe=$probes")
  case $code in
    3??)
      next_probe
      curl "${args[@]}" -D "$jar.g" -o "$jar.b" "$base/ocutalon/?probe=$probes"
      ;;
  esac
  printf '%s' "$code"
}

# set_cookie_value <headers file>: the value of the Set-Cookie of OcuTalonResume in the headers, or nothing. It is the resume reference:
# the caller keeps it in a variable and never prints it.
set_cookie_value() {
  tr -d '\r' < "$1" 2>/dev/null | grep -i '^set-cookie: OcuTalonResume=' | sed 's/^[^=]*=//; s/;.*//' | head -n 1
}

# set_cookie_shape <headers file>: the Set-Cookie line of OcuTalonResume with its value replaced, for the MEASURED lines.
set_cookie_shape() {
  tr -d '\r' < "$1" 2>/dev/null | grep -i '^set-cookie: OcuTalonResume=' | sed 's/^[^:]*: //; s/OcuTalonResume=[^;]*/OcuTalonResume=<value>/' | head -n 1
}

# page_outcome <body file>: shell (the application), refused (the splash with the address-limit error) or other.
page_outcome() {
  if grep -q '<app-root' "$1"; then
    printf shell
  elif grep -q 'Too many new sessions from your network this hour' "$1"; then
    printf limit
  else
    printf other
  fi
}

# jar_epoch <jar>: the epoch of /state for the jar's session, or nothing. The jar is signed out by the caller.
jar_epoch() {
  next_probe
  curl -s --max-time 30 -b "$1" -c "$1" "$base/ocutalon/api/v1/state?probe=$probes" | sed -n 's/.*"epoch":"\([^"]*\)".*/\1/p' | head -n 1
}

# row_field <epoch> <property>: a property of the Session row of the epoch (an epoch is base64url, so it is safe in a literal).
row_field() {
  printf '%s\n' \
    "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?\",\"$1\")" \
    "Set v=\"\" While rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get(\"ID\")) If \$IsObject(r),r.Epoch=\"$1\" { Set v=\$Property(r,\"$2\") Quit } }" \
    'Write !,"CHK|field|",v' \
    'Halt' | session_value OCUTALON field
}

# session_rows: the number of Session rows. counter_rows: the number of AddressCounter rows; with an address, those of its hash.
session_rows() {
  printf '%s\n' 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Session") Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' 'Halt' | session_value OCUTALON rows
}
counter_rows() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?\",##class(OcuTalon.Data.Session).Hash(\"$1\")) Do rs.%Next() Write !,\"CHK|rows|\",rs.%GetData(1)" 'Halt' | session_value OCUTALON rows
  else
    printf '%s\n' 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter") Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' 'Halt' | session_value OCUTALON rows
  fi
}

# --- row 14 (live): the seeded address limit ---

check_session "row 14: after the flag-on start the address limit's setting row exists and reads 5" OCUTALON \
  "CHK|limit|5|1" \
  'Write !,"CHK|limit|",##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY),"|",##class(OcuTalon.Data.Setting).KeyIndexExists(##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY)' \
  'Halt'

# --- row 12 (live, first phase): the proxy address is one that no request comes from, so every sign-in is exempt ---

a0=203.0.113.250
counter_before=$(counter_rows)
exempt_ok=0
for i in 1 2 3 4 5 6; do
  jar="$tmp/jar.exempt.$i"
  : > "$jar"
  code=$(online_signin "$jar" "$a0" "")
  outcome=$(page_outcome "$jar.b")
  if [ "$i" = 1 ]; then
    echo "MEASURED resume Set-Cookie attributes (the sign-in POST's answer): $(set_cookie_shape "$jar.h")"
    echo "MEASURED resume Set-Cookie attributes (the first /ocutalon/ GET after it): $(set_cookie_shape "$jar.g")"
  fi
  if [ "$outcome" = shell ] && [ -n "$(set_cookie_value "$jar.h")" ]; then exempt_ok=$((exempt_ok + 1)); fi
  logout_all "$jar" /ocutalon/
done
if [ "$exempt_ok" = 6 ] && [ "$(counter_rows)" = "$counter_before" ] && [ "$(counter_rows "$a0")" = 0 ]; then
  pass "row 12: six sign-ins from one forwarded address, not from the proxy, all give the shell and a cookie, and write no counter row"
else
  fail "row 12: of six exempt sign-ins $exempt_ok gave the shell and a cookie, and the counter holds '$(counter_rows "$a0")' row(s) for the address (before: '$counter_before', now '$(counter_rows)')"
fi

# --- row 4: the trace applications do not attach; the first /ocutalon request of the group's sign-in does ---

# console_lines: the number of OcuTalon.Web.SessionEvents lines in messages.log (OnLogin writes one for an attach that failed). The trace
# application's account has no write access to the private database, so an OnLogin that ran there would fail and write one.
console_lines() { dc exec -T iris grep -c 'OcuTalon.Web.SessionEvents: ' "$mgr/messages.log" 2>/dev/null | tr -d '\r'; }
jar="$tmp/jar.trace"
: > "$jar"
rows_before=$(session_rows)
lines_before=$(console_lines)
next_probe
trace_url="$base/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?probe=$probes"
token=$(page_token "$jar" "$trace_url")
if [ -z "$token" ]; then
  fail "row 4: the trace application's sign-in page gave no session token"
else
  next_probe
  curl -s --max-time 30 -D "$jar.h" -o /dev/null -c "$jar" -b "$jar" --data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$demo_user" \
    --data-urlencode "IRISPassword=$demo_password" --data-urlencode 'IRISLogin=Login' "$base/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?probe=$probes"
  rows_after_trace=$(session_rows)
  lines_after_trace=$(console_lines)
  trace_cookie=$(set_cookie_value "$jar.h")
  next_probe
  curl -s --max-time 30 -D "$jar.g" -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/?probe=$probes"
  rows_after_shell=$(session_rows)
  shell_cookie=$(set_cookie_value "$jar.g")
  echo "MEASURED resume Set-Cookie attributes (the group-carried first /ocutalon/ GET): $(set_cookie_shape "$jar.g")"
  if [ -z "$trace_cookie" ] && [ "$rows_after_trace" = "$rows_before" ] && [ "$lines_after_trace" = "$lines_before" ] && [ -n "$shell_cookie" ] && [ "$rows_after_shell" = $((rows_before + 1)) ]; then
    pass "row 4: the trace application's sign-in runs no OnLogin (no console log line), sets no resume cookie and creates no Session row; the jar's first /ocutalon/ request sets it and creates one"
  else
    fail "row 4: after the trace sign-in the cookie is '${trace_cookie:+set}', the rows $rows_before to $rows_after_trace and the console log's OnLogin lines $lines_before to $lines_after_trace; after /ocutalon/ the cookie is '${shell_cookie:+set}' and the rows $rows_after_shell (wanted none, equal, set, +1)"
  fi
fi
logout_all "$jar" /ocutalon/trace/ocutalon/

# --- row 6 and Task 0 (d): a real message, a resume with the cookie, and the reference kept out of every record ---

jar="$tmp/jar.row6"
: > "$jar"
online_signin "$jar" "" "" > /dev/null
resume_ref=$(set_cookie_value "$jar.h")
epoch_one=$(jar_epoch "$jar")
csp_one=$(row_field "$epoch_one" CspSessionId)
if [ -z "$resume_ref" ] || [ -z "$epoch_one" ]; then
  fail "row 6: the sign-in gave no resume cookie ('${resume_ref:+set}') or no epoch ('$epoch_one')"
else
  client_id="zz-row6-$(date +%s)"
  next_probe
  posted=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" \
    --data "{\"clientId\":\"$client_id\",\"text\":\"zz row six\",\"fromGuide\":false}" "$base/ocutalon/api/v1/messages?probe=$probes")
  turn_done=0
  for _ in $(seq 1 40); do
    next_probe
    if curl -s --max-time 30 -b "$jar" -c "$jar" "$base/ocutalon/api/v1/state?probe=$probes" | node -e 'let d = ""; process.stdin.on("data", (c) => (d += c)).on("end", () => { try { process.exit(JSON.parse(d).chat.some((i) => i.payload && i.payload.clientId === process.argv[1] && i.payload.state === "done") ? 0 : 1); } catch { process.exit(1); } });' "$client_id"; then
      turn_done=1
      break
    fi
    sleep 2
  done
  if [ "$posted" = 202 ] && [ "$turn_done" = 1 ]; then
    pass "row 6: a message was posted (202) and its turn is done, so a production message of the session exists"
  else
    fail "row 6: the message post gave '$posted' and its turn done is '$turn_done'"
  fi
  logout_all "$jar" /ocutalon/
  code=$(online_signin "$jar" "" "$resume_ref")
  epoch_two=$(jar_epoch "$jar")
  csp_two=$(row_field "$epoch_one" CspSessionId)
  if [ "$epoch_two" = "$epoch_one" ] && [ -z "$(set_cookie_value "$jar.h")" ]; then
    pass "row 6: signing in again with the cookie resumes the same session (the same epoch) and sets no new cookie"
  else
    fail "row 6: signing in again with the cookie gave the epoch '$epoch_two' (wanted '$epoch_one') or set a cookie"
  fi
  echo "MEASURED CSP session id reused on resume: $([ -n "$csp_one" ] && [ "$csp_one" = "$csp_two" ] && echo yes || echo no)"
  logout_all "$jar" /ocutalon/
fi

# --- rows 7 to 12: the browser ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed step can echo what was typed: every password is replaced before anything reaches
# the terminal.
show_log() { tail -n "$1" "$e2e_log" | redact | sed 's/^/  /'; }
# run_e2e <spec file or nothing>: the online-demo project's run, with the stack's start values, into $e2e_log. The caller's own variables
# (OCUTALON_ONLINE_PROXIED, OCUTALON_ONLINE_LIMIT_ADDRESS) pass through; the global timeout is what is left of the deadline minus 20 s.
run_e2e() {
  local left=$((deadline - SECONDS))
  OCUTALON_URL="$base" \
    OCUTALON_DEMOACCOUNT_USER="$demo_user" \
    OCUTALON_DEMOACCOUNT_PASSWORD="$demo_password" \
    OCUTALON_READONLYACCOUNT_USER="$readonly_user" \
    OCUTALON_READONLYACCOUNT_PASSWORD="$readonly_password" \
    OCUTALON_E2E_IRIS_CONTAINER="$cid" \
    OCUTALON_E2E_TIMEOUT_MS=$(((left - 20) * 1000)) \
    npm --prefix web run e2e:online-demo -- "$@" > "$e2e_log" 2>&1
}
run_e2e
e2e_status=$?
if [ "$e2e_status" -eq 0 ]; then
  show_log 20
  pass "rows 7 to 12: the specs of the online-demo project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
else
  show_log 80
  if grep -q "Executable doesn't exist" "$e2e_log"; then
    echo "  a browser is missing: run npx --prefix web playwright install chromium"
  fi
  fail "rows 7 to 12: the specs of the online-demo project failed (exit $e2e_status)"
fi
grep -h '^MEASURED' "$e2e_log" | redact

# --- Story 16.3, the proxied phase (rows 10 and 11, Task 0 (c)) ---

# The public proxy address is set to the address that IRIS sees for this host's requests, and put back to the start value on every path.
proxy_start=192.0.2.10
set_proxy() { printf '%s\n' "Do ##class(OcuTalon.Data.Public.Settings).Set(\"proxyAddress\",\"$1\")" "Write !,\"CHK|proxy|\",##class(OcuTalon.Data.Public.Settings).Get(\"proxyAddress\")" 'Halt' | session_value OCUTALON proxy; }
# host_address: the container's default gateway, from /proc/net/route (little-endian hex), which is the source address of a request that the
# host publishes a port for; nothing when the table has no default route.
host_address() {
  dc exec -T iris sh -c "awk '\$2 == \"00000000\" { print \$3; exit }' /proc/net/route" 2>/dev/null | tr -d '\r' | node -e 'const h = require("fs").readFileSync(0, "utf8").trim(); if (/^[0-9A-Fa-f]{8}$/.test(h)) console.log([6, 4, 2, 0].map((i) => parseInt(h.slice(i, i + 2), 16)).join("."));'
}
host_ip=$(host_address)
echo "MEASURED REMOTE_ADDR of the host's requests, derived from the container's default gateway: ${host_ip:-<none>}"
proxied_ok=0
if [ -n "$host_ip" ] && [ "$(set_proxy "$host_ip")" = "$host_ip" ]; then
  precondition="zz-phase2-precondition"
  jar="$tmp/jar.precondition"
  : > "$jar"
  online_signin "$jar" "$precondition" "" > /dev/null
  logout_all "$jar" /ocutalon/
  if [ "$(counter_rows "$precondition")" = 1 ]; then
    proxied_ok=1
    pass "phase 2: one proxied sign-in wrote a counter row for its forwarded address (the proxy address is $host_ip)"
  else
    fail "phase 2: a sign-in from $host_ip with X-Forwarded-For wrote no counter row, so $host_ip is not the address that IRIS sees for this host's requests"
  fi
else
  fail "phase 2: the host's address could not be derived ('${host_ip:-}') or the proxy address could not be set"
fi

if [ "$proxied_ok" = 1 ]; then
  # Row 10: five creations from address A, then a sixth, a cookie sign-in and a list that ends in C.
  addr_a=203.0.113.20
  addr_c=203.0.113.30
  first_ref=
  first_epoch=
  created=0
  for i in 1 2 3 4 5; do
    jar="$tmp/jar.limit.$i"
    : > "$jar"
    online_signin "$jar" "$addr_a" "" > /dev/null
    if [ "$(page_outcome "$jar.b")" = shell ] && [ -n "$(set_cookie_value "$jar.h")" ]; then created=$((created + 1)); fi
    if [ "$i" = 1 ]; then
      first_ref=$(set_cookie_value "$jar.h")
      first_epoch=$(jar_epoch "$jar")
    fi
    logout_all "$jar" /ocutalon/
  done
  # The first creation is aged to 50 minutes: the window is the past hour, so it still counts and the sixth is refused until ten minutes from now.
  aged=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT TOP 1 ID FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ? ORDER BY ID\",##class(OcuTalon.Data.Session).Hash(\"$addr_a\")) Set ok=0 If rs.%Next() { Set r=##class(OcuTalon.Data.AddressCounter).%OpenId(rs.%Get(\"ID\")) Set r.CreatedAt=##class(OcuTalon.Data.AddressCounter).Shift(##class(OcuTalon.Data.Time).NowUtc(),-3000) Set ok=\$SYSTEM.Status.IsOK(r.%Save()) } Write !,\"CHK|aged|\",ok" 'Halt' | session_value OCUTALON aged)
  rows_before=$(session_rows)
  jar="$tmp/jar.limit.6"
  : > "$jar"
  code=$(online_signin "$jar" "$addr_a" "")
  oldest=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT MIN(CreatedAt) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?\",##class(OcuTalon.Data.Session).Hash(\"$addr_a\")) Do rs.%Next() Write !,\"CHK|oldest|\",##class(OcuTalon.Data.AddressCounter).Shift(rs.%GetData(1),3600)" 'Halt' | session_value OCUTALON oldest)
  state_status=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" "$base/ocutalon/api/v1/state?probe=$(next_probe; echo "$probes")")
  refused_page=$(tr -d '\n' < "$jar.b")
  refused_ok=1
  [ "$code" = 200 ] || refused_ok=0
  [ "$(page_outcome "$jar.b")" = limit ] || refused_ok=0
  case $refused_page in *'<time class="tnum" id="ocu-error-time" datetime="'"$oldest"'"></time>.'*) ;; *) refused_ok=0 ;; esac
  case $refused_page in *aria-invalid*) refused_ok=0 ;; esac
  case $refused_page in *' disabled'*) refused_ok=0 ;; esac
  [ -z "$(set_cookie_value "$jar.h")" ] || refused_ok=0
  [ "$state_status" = 401 ] || refused_ok=0
  [ "$(session_rows)" = "$rows_before" ] || refused_ok=0
  logout_all "$jar" /ocutalon/
  if [ "$created" = 5 ] && [ "$refused_ok" = 1 ] && [ -n "$oldest" ] && [ "$aged" = 1 ]; then
    pass "row 10: five sign-ins from one forwarded address give the shell and a cookie each, and the sixth (the oldest creation aged to 50 minutes) gets 200 and the splash with the field error and the time of the oldest creation plus one hour, no marked field, no disabled button, no cookie, no session and no row"
  else
    fail "row 10: created=$created of 5, aged=$aged, the sixth: status '$code', outcome '$(page_outcome "$jar.b")', session state '$state_status', refused_ok=$refused_ok, oldest '$oldest'"
  fi
  jar="$tmp/jar.limit.resume"
  : > "$jar"
  online_signin "$jar" "$addr_a" "$first_ref" > /dev/null
  resumed_epoch=$(jar_epoch "$jar")
  logout_all "$jar" /ocutalon/
  if [ -n "$first_epoch" ] && [ "$resumed_epoch" = "$first_epoch" ] && [ "$(counter_rows "$addr_a")" = 5 ]; then
    pass "row 10: with the first session's cookie the sixth sign-in resumes it (the same epoch) and is not counted or refused"
  else
    fail "row 10: the cookie sign-in at the limit gave the epoch '$resumed_epoch' (wanted '$first_epoch'), and the address has '$(counter_rows "$addr_a")' counter rows"
  fi
  jar="$tmp/jar.limit.list"
  : > "$jar"
  online_signin "$jar" "$addr_a, $addr_c" "" > /dev/null
  list_outcome=$(page_outcome "$jar.b")
  logout_all "$jar" /ocutalon/
  if [ "$list_outcome" = shell ] && [ "$(counter_rows "$addr_c")" = 1 ] && [ "$(counter_rows "$addr_a")" = 5 ]; then
    pass "row 10: a forwarded list that ends in another address counts that address and is allowed; the first address still has exactly five counter rows"
  else
    fail "row 10: the list '$addr_a, $addr_c' gave '$list_outcome', C has '$(counter_rows "$addr_c")' counter row(s) and A has '$(counter_rows "$addr_a")'"
  fi

  # Row 11: the page, from address L of its own.
  remaining=$((deadline - SECONDS))
  if [ "$remaining" -lt 60 ]; then
    fail "row 11: only $remaining s are left of the deadline: too little for the proxied browser case"
  else
    limit_address=203.0.113.40
    OCUTALON_ONLINE_PROXIED=1 OCUTALON_ONLINE_LIMIT_ADDRESS="$limit_address" run_e2e address-limit.spec.ts
    limit_status=$?
    if [ "$limit_status" -eq 0 ] && grep -Eq '(^|[^0-9])1 passed' "$e2e_log" && ! grep -Eq '[0-9]+ skipped' "$e2e_log"; then
      show_log 12
      pass "row 11: the proxied browser case passes ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
    else
      show_log 60
      fail "row 11: the proxied browser case did not run and pass exactly once (exit $limit_status)"
    fi
  fi
fi

# The proxy address goes back to its start value, whatever the phase's checks found.
if [ "$(set_proxy "$proxy_start")" = "$proxy_start" ]; then
  pass "phase 2: the proxy address is back to its start value"
else
  fail "phase 2: the proxy address could not be put back to $proxy_start"
fi

# --- the published passwords stay out of the logs and the event log (Never) ---

# log_hits <value>: the number of lines of the container's output, messages.log and the after-start log that hold the value (only the
# count is printed by the callers).
log_hits() {
  { dc logs --no-color iris 2>&1; dc exec -T iris cat "$mgr/messages.log" /durable/ocutalon-after-start.log 2>/dev/null; } | grep -cF -e "$1"
}
# check_password_not_logged <env variable> <label>: the value of the start variable is in no line of the container's output, of
# messages.log or of the after-start log (only a count is printed), and in no row of the production event log.
check_password_not_logged() {
  local variable=$1 label=$2 value n
  value=$(dc exec -T iris printenv "$variable" 2>/dev/null | tr -d '\r')
  if [ -z "$value" ]; then
    fail "$label: the container has no $variable, so a search of its logs for it proves nothing"
    return
  fi
  n=$(log_hits "$value")
  if [ "$n" = 0 ]; then
    pass "$label: no line of the container's output, messages.log or the after-start log holds it"
  else
    fail "$label: '$n' line(s) of the container's output, messages.log or the after-start log hold it"
  fi
}
# ref_script <namespace> < script: iris_script with the resume reference of row 6 in the session's environment as OCUTALON_T16_REF (the
# way live_fixture_user hands a password over), so that the reference is in no script text.
ref_script() {
  local script out try=1
  script=$(cat)
  while :; do
    out=$(printf '%s\n' "$script" | OCUTALON_T16_REF="$resume_ref" dc exec -T -e OCUTALON_T16_REF iris iris session IRIS -U "$1" 2>/dev/null | tr -d '\r' | sed -n 's/.*\(CHK|.*\)$/\1/p')
    if [ -n "$out" ] || [ "$try" -ge 3 ]; then break; fi
    try=$((try + 1))
    sleep 5
  done
  if [ -n "$out" ]; then printf '%s\n' "$out"; fi
}
# check_ref_session <label> <namespace> <expected CHK lines> <script line>...: check_session with ref_script.
check_ref_session() {
  local label=$1 ns=$2
  printf '%s\n' "$3" > "$tmp/expected.chk"
  printf '%s\n' "${@:4}" | ref_script "$ns" > "$tmp/actual.chk"
  compare_chk "$label" "$tmp/actual.chk" "$tmp/expected.chk"
}
# check_records_clean <when> <check_session or check_ref_session> <what> <variable>...: none of the values of the variables (in the
# environment of the session that runs the script) is in a row of the production event log, of the live events (OCUTALON) or in an audit
# entry (%SYS); <what> names them in the labels. Only counts are printed.
check_records_clean() {
  local when=$1 runner=$2 what=$3 names="" events="" audits="" live="" v
  shift 3
  for v in "$@"; do
    names="$names${names:+,}\"$v\""
    events="$events${events:+
}CHK|eventlog|$v|0"
    live="$live${live:+
}CHK|liveevent|$v|0"
    audits="$audits${audits:+
}CHK|audit|$v|0"
  done
  "$runner" "$when: the production event log and the live events hold $what" OCUTALON \
    "$events
$live" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?\",e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|eventlog|\",p,\"|\",n }" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?\",e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|liveevent|\",p,\"|\",n }" \
    'Halt'
  "$runner" "$when: no audit entry holds $what" %SYS \
    "$audits" \
    "For p=$names { Set e=\$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?\",e,e) Set n=\$Select(e=\"\":\"<unset>\",rs.%Next():rs.%GetData(1),1:\"<no row>\") Write !,\"CHK|audit|\",p,\"|\",n }" \
    'Halt'
}
# check_logs_clean <when>: neither published password is in the logs above, in a row of the production event log or of the live
# events (OCUTALON), or in an audit entry (%SYS); only counts are printed. After row 6 the same searches run for the resume reference, and
# a scan of every global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC (production messages included) adds to them. It runs
# after the browser and again after the restart, whose start writes both passwords again and rewrites the after-start log.
check_logs_clean() {
  check_password_not_logged OCUTALON_DEMO_PASSWORD "$1: the demo account's password"
  check_password_not_logged OCUTALON_READONLY_PASSWORD "$1: the read-only account's password"
  check_records_clean "$1" check_session "neither published password" OCUTALON_DEMO_PASSWORD OCUTALON_READONLY_PASSWORD
  if [ -z "$resume_ref" ]; then
    fail "$1: row 6 kept no resume reference, so a search for it proves nothing"
    return
  fi
  if [ "$(log_hits "$resume_ref")" = 0 ]; then
    pass "$1: row 6: no line of the container's output, messages.log or the after-start log holds the resume reference"
  else
    fail "$1: row 6: '$(log_hits "$resume_ref")' line(s) of the container's output, messages.log or the after-start log hold the resume reference"
  fi
  check_records_clean "$1: row 6" check_ref_session "the resume reference" OCUTALON_T16_REF
  check_ref_session "$1: row 6: no node of any global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC holds the resume reference" OCUTALON \
    "CHK|globals|0" \
    'Write !,"CHK|globals|",##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits($SYSTEM.Util.GetEnviron("OCUTALON_T16_REF"))' \
    'Halt'
}
check_logs_clean "after the first start"

# --- row 13: every start, a restart ---

dc stop iris > /dev/null 2>&1
dc start iris > /dev/null 2>&1
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200 | redact
  die "row 13 the restart did not end ready within 200 s"
fi
expected_run "cleared" "present $ipm_version" "already mapped" "ok" "skipped $version" "$version" > "$tmp/expected.row13"
check_log "row 13" "$tmp/expected.row13"
check_session "row 13: ready again, the guard setting unchanged" OCUTALON \
  "CHK|ready|1
CHK|validation|Check^OcuTalonPasswordGuard" \
  'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
  'New $Namespace Set $Namespace="%SYS" Do ##class(Security.System).Get(,.sp) Write !,"CHK|validation|",$Get(sp("PasswordValidationRoutine"))' \
  'Halt'
restart_outcome=$(signin_outcome "$demo_user" "$demo_password")
if [ "$restart_outcome" = shell ]; then
  pass "row 13: after the restart the demo account signs in with its published password"
else
  fail "row 13: after the restart the demo account's sign-in gives '$restart_outcome', wanted shell"
fi
restart_readonly=$(signin_outcome "$readonly_user" "$readonly_password")
if [ "$restart_readonly" = norole ]; then
  pass "row 13: after the restart the read-only account signs in with its published password (no OcuTalon role)"
else
  fail "row 13: after the restart the read-only account's sign-in gives '$restart_readonly', wanted norole"
fi
check_logs_clean "after the restart"

if [ "$fails" -ne 0 ]; then
  echo "test-online-demo: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-demo: all checks passed"
