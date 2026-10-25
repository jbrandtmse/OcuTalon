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
#     needs a sign-in gives the splash (the h1, no app-root), a sign-in image is served, /ocutalon/public/status answers and
#     /ocutalon/public/x does not, the API answers 401 signed_out and the trace applications' pages give IRIS's sign-in page; the
#     splash form's input names are printed as "MEASURED splash form inputs:" and none is outside the four of the proxy's allow-list;
#   - the browser (rows 7 to 12, and the splash's S1 to S10 and the REL-2 online run's step 1 of Story 16.2): the project online-demo of
#     web/playwright.config.ts (web/e2e-online/) as both public accounts;
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
redact() { sed "s/$demo_password/<redacted>/g; s/$readonly_password/<redacted>/g; s/$control_password/<redacted>/g"; }

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
  code=$(curl -s --max-time 30 -o "$tmp/splash.body" -w '%{http_code}' -c "$jar" -b "$jar" "$base$1${sep}probe=$probes")
  logout_all "$jar" /ocutalon/
  printf '%s' "$code"
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

# --- rows 7 to 12: the browser ---

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 60 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
# The browser log is printed on every outcome, and a failed step can echo what was typed: every password is replaced before anything reaches
# the terminal.
show_log() { tail -n "$1" "$e2e_log" | redact | sed 's/^/  /'; }
OCUTALON_URL="$base" \
  OCUTALON_DEMOACCOUNT_USER="$demo_user" \
  OCUTALON_DEMOACCOUNT_PASSWORD="$demo_password" \
  OCUTALON_READONLYACCOUNT_USER="$readonly_user" \
  OCUTALON_READONLYACCOUNT_PASSWORD="$readonly_password" \
  OCUTALON_E2E_IRIS_CONTAINER="$cid" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000)) \
  npm --prefix web run e2e:online-demo > "$e2e_log" 2>&1
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

# --- the published passwords stay out of the logs and the event log (Never) ---

# check_password_not_logged <env variable> <label>: the value of the start variable is in no line of the container's output, of
# messages.log or of the after-start log (only a count is printed), and in no row of the production event log.
check_password_not_logged() {
  local variable=$1 label=$2 value n
  value=$(dc exec -T iris printenv "$variable" 2>/dev/null | tr -d '\r')
  if [ -z "$value" ]; then
    fail "$label: the container has no $variable, so a search of its logs for it proves nothing"
    return
  fi
  n=$( { dc logs --no-color iris 2>&1; dc exec -T iris cat "$mgr/messages.log" /durable/ocutalon-after-start.log 2>/dev/null; } | grep -cF -e "$value")
  if [ "$n" = 0 ]; then
    pass "$label: no line of the container's output, messages.log or the after-start log holds it"
  else
    fail "$label: '$n' line(s) of the container's output, messages.log or the after-start log hold it"
  fi
}
# check_logs_clean <when>: neither published password is in the logs above, in a row of the production event log or of the live
# events (OCUTALON), or in an audit entry (%SYS); only counts are printed. It runs after the browser and again after the restart,
# whose start writes both passwords again and rewrites the after-start log.
check_logs_clean() {
  check_password_not_logged OCUTALON_DEMO_PASSWORD "$1: the demo account's password"
  check_password_not_logged OCUTALON_READONLY_PASSWORD "$1: the read-only account's password"
  check_session "$1: the production event log and the live events hold neither published password" OCUTALON \
    "CHK|eventlog|OCUTALON_DEMO_PASSWORD|0
CHK|eventlog|OCUTALON_READONLY_PASSWORD|0
CHK|liveevent|OCUTALON_DEMO_PASSWORD|0
CHK|liveevent|OCUTALON_READONLY_PASSWORD|0" \
    'For p="OCUTALON_DEMO_PASSWORD","OCUTALON_READONLY_PASSWORD" { Set e=$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?",e) Set n=$Select(e="":"<unset>",rs.%Next():rs.%GetData(1),1:"<no row>") Write !,"CHK|eventlog|",p,"|",n }' \
    'For p="OCUTALON_DEMO_PASSWORD","OCUTALON_READONLY_PASSWORD" { Set e=$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?",e) Set n=$Select(e="":"<unset>",rs.%Next():rs.%GetData(1),1:"<no row>") Write !,"CHK|liveevent|",p,"|",n }' \
    'Halt'
  check_session "$1: no audit entry holds either published password" %SYS \
    "CHK|audit|OCUTALON_DEMO_PASSWORD|0
CHK|audit|OCUTALON_READONLY_PASSWORD|0" \
    'For p="OCUTALON_DEMO_PASSWORD","OCUTALON_READONLY_PASSWORD" { Set e=$SYSTEM.Util.GetEnviron(p) Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?",e,e) Set n=$Select(e="":"<unset>",rs.%Next():rs.%GetData(1),1:"<no row>") Write !,"CHK|audit|",p,"|",n }' \
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
