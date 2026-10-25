#!/usr/bin/env bash
# Live test of the demo-mode switch (Story 4.1; AD-1, AD-3, AD-17, AD-19, AD-23): the command do ##class(OcuTalon.Core.Admin).SetDemoMode(0|1),
# typed in a terminal of the namespace OCUTALON, changes the setting, audits the change and adds or removes OCUORDERS, and what reads
# the setting follows. It switches OCUORDERS, so it runs on a throwaway stack of its own. Builds the image and starts it in one
# throwaway compose project (demo mode on, as the Docker install seeds it), then:
#   1. signs the README account in, posts one chat message and waits for its reply, and records /state's chat and rail (S0), the
#      Demo step's surfaces (F0) and the number of Settings audit entries. The two fixture users are created first, so that F0 holds
#      their roles too;
#   2. control: a tell-now Notification sent into Notify from a host made with CreateBusinessService leaves a header to SimPhoneOut;
#   3. a user without OcuTalonAdmin, and irisowner (the session's OS login, %All without OcuTalonAdmin), run the command: the
#      refusal line is printed, no header goes to SettingsOps, and the setting and the surfaces are unchanged (step 7 checks the
#      audit log, whose entries become readable only about a minute after they are written);
#   4. an OcuTalonAdmin holder (no %All) runs SetDemoMode(0): the off line is printed, the row is "0", the surfaces equal F0 less
#      OCUORDERS, and the off checks of the Demo step pass. The Demo step ran in the SettingsOps job (Story 4.1, Task 0);
#   5. from 61 s after step 4 returned, every /state answer reports demoMode false (polled every 2 s), the chat and rail equal S0,
#      POST /v1/demo/break-feed still answers 501 not_built, a new tell-now Notification leaves no header to SimPhoneOut, and the
#      page shows no demo badge (web/e2e/demo-switch/badge.spec.ts with OCUTALON_E2E_DEMO_MODE=0);
#   6. the admin runs SetDemoMode(1): the on line is printed, the row is "1", the on checks pass, the Orders production runs with its
#      two jobs, and the surfaces equal F0;
#   7. within 180 s the audit log holds one OcuTalon/Settings/Settings entry for the admin with value "0" and one with "1", both
#      from the channel system, and no other Settings entry (none names the refused users);
#   8. from 61 s after step 6, /state reports demoMode true with the chat and rail equal S0, a tell-now Notification leaves a header
#      to SimPhoneOut again, and the page shows the demo badge.
# The project is unique, publishes its web port only on 127.0.0.1 (first free port of 52800-52819, or OCUTALON_TEST_WEB_PORT) and
# receives no keys. The fixture users get random passwords that are passed by environment variable and never printed. An EXIT trap
# removes the project with its volume and images. Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 1200 s by default
# here and in CI), so even a failing run ends within it.
# Prints one PASS or FAIL line per check, and INFO lines for the measured durations; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later and
# the browser: npx --prefix web playwright install chromium.
set -u

: "${OCUTALON_LIVE_DEADLINE:=1200}"
export OCUTALON_LIVE_DEADLINE
. "$(dirname "$0")/lib-live.sh"
live_start demo-switch
live_web_port || exit 1

readme_user=ocutalon
readme_password=ocutalon
adminuser=ZzSwAdmin
adminpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
plainuser=ZzSwPlain
plainpassword="Zz$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
base="http://127.0.0.1:$web_port"
jar="$tmp/jar"

# The texts of the terminal (Story 4.1, Design Notes V2), written out here and never read from the product.
text_on="Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change."
text_off="Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change."
text_refused="Only an OcuTalon admin can change settings. Nothing was changed."

# --- helpers ---

# sign_in: the README account signs in with the cookie jar (a copy of test-bundle-folder.sh's two lines, because lib-live.sh is shared).
sign_in() {
  : > "$jar"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" -d "IRISUsername=$readme_user" -d "IRISPassword=$readme_password" --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/"
}

api_get() { curl -s --max-time 30 -b "$jar" -c "$jar" "$base/ocutalon/api/v1/$1"; }

# api_post <path> <json>: prints the status code; the body is in $tmp/post.body.
api_post() {
  curl -s --max-time 30 -b "$jar" -c "$jar" -o "$tmp/post.body" -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" -d "$2" "$base/ocutalon/api/v1/$1"
}

# state_line: "<demoMode>|<hash of chat and rail>" of the README session's /state, or "error|".
state_line() {
  api_get state | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const h=require("crypto").createHash("sha256").update(JSON.stringify([j.chat,j.rail])).digest("hex").slice(0,16);console.log(String(j.demoMode)+"|"+h)}catch(e){console.log("error|")}})'
}

# chat_done: the number of chat turns of /state whose state is done.
chat_done() {
  api_get state | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j.chat.filter(i=>i.type==="chat.message"&&i.payload.state==="done").length)}catch(e){console.log(0)}})'
}

has_done_turn() { [ "$(chat_done)" -ge 1 ]; }

# setting_row: the demo.mode row's value, or <none>.
setting_row() {
  printf '%s\n' \
    'Set r=##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode") Write !,"CHK|row|",$Select($IsObject(r):r.Value,1:"<none>")' \
    'Halt' | session_value OCUTALON row
}

# settingsops_headers: the request headers from CommandsIn to SettingsOps.
settingsops_headers() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1","CommandsIn","SettingsOps") Do rs.%Next() Write !,"CHK|n|",rs.%GetData(1)' \
    'Halt' | session_value OCUTALON n
}

# settings_audit_total: the OcuTalon/Settings/Settings entries visible in the audit log.
settings_audit_total() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventSource = ? AND EventType = ? AND Event = ?","OcuTalon","Settings","Settings") Do rs.%Next() Write !,"CHK|n|",rs.%GetData(1)' \
    'Halt' | session_value %SYS n
}

# settings_audit_rows <user> <value> [<channel>]: the Settings entries whose data names the user and, when value and channel are not
# empty, the value and the channel.
settings_audit_rows() {
  printf '%s\n' \
    'Set q=$Char(34)' \
    "Set u=q_\"user\"_q_\":\"_q_\"$1\"_q" \
    "Set v=\"$2\"" \
    "Set c=\"${3:-}\"" \
    'If v'"'"'="" { Set v=q_"value"_q_":"_q_v_q } Else { Set v=u }' \
    'If c'"'"'="" { Set c=q_"channel"_q_":"_q_c_q } Else { Set c=u }' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventSource = ? AND EventType = ? AND Event = ? AND EventData [ ? AND EventData [ ? AND EventData [ ?","OcuTalon","Settings","Settings",u,v,c) Do rs.%Next() Write !,"CHK|n|",rs.%GetData(1)' \
    'Halt' | session_value %SYS n
}

# notify_probe: sends a tell-now Notification into Notify and prints "<11 when both sends were OK>|<new headers to WebChatOut>|<new headers to
# SimPhoneOut>", after
# Notify has routed it. The SessionRef is no session, so WebChatOut drops the card and nothing reaches the chat.
notify_probe() {
  printf '%s\n' \
    'Set q="SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1"' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,q,"Notify","WebChatOut") Do rs.%Next() Set w0=rs.%GetData(1)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,q,"Notify","SimPhoneOut") Do rs.%Next() Set p0=rs.%GetData(1)' \
    'Set sc=##class(Ens.Director).CreateBusinessService("SimMailboxIn",.svc)' \
    'Set m=##class(OcuTalon.Msg.Notification).%New() Set m.SessionRef="zzswitch",m.Kind="tellnow",m.CatalogKey="notice.tellNowFallback",m.Slots="{}"' \
    'Set sc2=svc.SendRequestAsync("Notify",m)' \
    'Set end=$ZHorolog+40,w1=w0 For { Set rs=##class(%SQL.Statement).%ExecDirect(,q,"Notify","WebChatOut") Do rs.%Next() Set w1=rs.%GetData(1) If (w1>w0)||($ZHorolog>end) { Quit } Hang 1 }' \
    'Hang 3' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,q,"Notify","SimPhoneOut") Do rs.%Next() Set p1=rs.%GetData(1)' \
    'Write !,"CHK|probe|",$SYSTEM.Status.IsOK(sc)_$SYSTEM.Status.IsOK(sc2),"|",w1-w0,"|",p1-p0' \
    'Halt' | session_value OCUTALON probe
}

# run_admin <user> <password> <argument>: a terminal session in OCUTALON, as irisowner (OS login) when the user is empty, otherwise
# logged in as the user with $SYSTEM.Security.Login. It runs SetDemoMode(<argument>) and sets
#   admin_login  1 when the login succeeded (1 for irisowner), admin_user the $USERNAME, admin_outcome the result's Outcome and
#   admin_lines  the lines that the command printed, joined by a line feed.
run_admin() {
  local script=() raw="$tmp/admin.raw"
  if [ -n "$1" ]; then
    script+=('Set pw=$SYSTEM.Util.GetEnviron("OCUTALON_SW_PW")' "Set ok=\$SYSTEM.Security.Login(\"$1\",pw)")
  else
    script+=('Set ok=1')
  fi
  script+=('Write !,"CHK|login|",ok' 'Write !,"CHK|user|",$USERNAME' 'Write !,"CHK|begin"' "Set r=##class(OcuTalon.Core.Admin).SetDemoMode($3)" 'Write !,"CHK|end"' 'Write !,"CHK|outcome|",r.Outcome' 'Halt')
  printf '%s\n' "${script[@]}" | OCUTALON_SW_PW="$2" dc exec -T -e OCUTALON_SW_PW iris iris session IRIS -U OCUTALON 2>/dev/null | tr -d '\r' > "$raw"
  admin_login=$(sed -n 's/.*CHK|login|\(.*\)$/\1/p' "$raw" | head -n 1)
  admin_user=$(sed -n 's/.*CHK|user|\(.*\)$/\1/p' "$raw" | head -n 1)
  admin_outcome=$(sed -n 's/.*CHK|outcome|\(.*\)$/\1/p' "$raw" | head -n 1)
  admin_lines=$(awk '/CHK\|begin/ { on = 1; next } /CHK\|end/ { on = 0 } on { sub(/^[A-Za-z0-9%]*>/, ""); if ($0 != "") print }' "$raw")
}

# e2e <mode>: the page specs of web/e2e/demo-switch with the mode the stack is in.
e2e() {
  local left=$(((deadline - SECONDS - 20) * 1000))
  if [ "$left" -lt 60000 ]; then
    fail "demo mode $1: only $((left / 1000)) s are left of the deadline for the browser run"
    return 1
  fi
  if OCUTALON_URL="$base" OCUTALON_E2E_DEMO_MODE="$1" OCUTALON_E2E_TIMEOUT_MS="$left" npm --prefix web run e2e:demo-switch > "$tmp/e2e.log" 2>&1; then
    pass "demo mode $1: the page shows $([ "$1" = 1 ] && echo 'the Demo mode badge' || echo 'no badge and the chat region') ($(grep -Eo '[0-9]+ passed' "$tmp/e2e.log" | tail -n 1))"
  else
    tail -n 40 "$tmp/e2e.log" | sed 's/^/  /'
    fail "demo mode $1: the page specs failed"
  fi
}

# poll_state <label> <second the switch returned> <wanted demoMode>: asks /state every 2 s from the switch until 12 s after the 61st
# second (and at least 12 s from now), and on until 3 answers from the 61st second have come, within the deadline. Every answer
# carries S0's chat and rail; every answer from the 61st second reports the wanted demoMode.
poll_state() {
  local label=$1 since=$2 want=$3 line mode hash t total=0 late=0 badmode=0 badchat=0 end
  end=$((since + 61 + 12))
  if [ $((SECONDS + 12)) -gt "$end" ]; then end=$((SECONDS + 12)); fi
  while { [ "$SECONDS" -lt "$end" ] || [ "$late" -lt 3 ]; } && [ "$SECONDS" -lt "$deadline" ]; do
    t=$SECONDS
    line=$(state_line)
    mode=${line%%|*}
    hash=${line#*|}
    total=$((total + 1))
    if [ "$hash" != "$s0hash" ]; then badchat=$((badchat + 1)); fi
    if [ "$t" -ge $((since + 61)) ]; then
      late=$((late + 1))
      if [ "$mode" != "$want" ]; then badmode=$((badmode + 1)); fi
    fi
    sleep 2
  done
  if [ "$late" -ge 3 ] && [ "$badmode" -eq 0 ]; then
    pass "$label: all $late answers from 61 s after the switch report demoMode $want ($total answers in all)"
  else
    fail "$label: $badmode of $late answers from 61 s after the switch do not report demoMode $want ($total answers in all)"
  fi
  if [ "$badchat" -eq 0 ]; then
    pass "$label: the chat and the rail equal S0 in all $total answers"
  else
    fail "$label: the chat or the rail differs from S0 in $badchat of $total answers"
  fi
}

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

# --- step 1: demo mode on, a conversation, the baselines ---

roles_admin="OcuTalonAdmin,%Developer,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,OcuTalonUser"
roles_plain="%Developer,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,OcuTalonUser"
[ "$(live_fixture_user "$adminuser" "$adminpassword" "$roles_admin" "demo switch admin")" = "CHK|fixture-user|1" ] || die "the admin fixture user was not created"
[ "$(live_fixture_user "$plainuser" "$plainpassword" "$roles_plain" "demo switch plain")" = "CHK|fixture-user|1" ] || die "the plain fixture user was not created"
pass "the fixture users exist: $adminuser (OcuTalonAdmin, no %All) and $plainuser (no OcuTalonAdmin)"

sign_in
code=$(api_post messages '{"clientId":"zzswitch-1","text":"zz demo switch hello","fromGuide":false}')
if [ "$code" = 202 ]; then
  pass "step 1: the README account's message is accepted (202)"
else
  die "step 1: POST /v1/messages answered '$code'"
fi
if wait_until 90 has_done_turn; then
  pass "step 1: the message has its reply"
else
  die "step 1: no reply to the message within 90 s"
fi
s0=$(state_line)
s0hash=${s0#*|}
if [ "${s0%%|*}" = true ] && [ -n "$s0hash" ]; then
  pass "step 1: /state reports demoMode true (chat and rail S0 = $s0hash)"
else
  die "step 1: /state is '$s0', wanted demoMode true"
fi
demo_surfaces "$tmp/f0.surf"
audit0=$(settings_audit_total)
heads0=$(settingsops_headers)
if [ "$(setting_row)" = 1 ]; then
  pass "step 1: the demo.mode row is 1 (the Docker install's seed); $audit0 Settings audit entries, $heads0 headers to SettingsOps"
else
  die "step 1: the demo.mode row is '$(setting_row)', wanted 1"
fi

# --- step 2: the control, Notify routes a tell-now to SimPhoneOut while demo mode is on ---

probe=$(notify_probe)
case $probe in
  "11|"[1-9]*"|"[1-9]*)
    pass "step 2: with demo mode on a tell-now leaves a header to WebChatOut and one to SimPhoneOut ($probe)" ;;
  *) fail "step 2: the control Notification was '$probe', wanted a header to WebChatOut and to SimPhoneOut" ;;
esac

# --- step 3: refused users change nothing ---

for who in plain owner; do
  if [ "$who" = plain ]; then
    run_admin "$plainuser" "$plainpassword" 0
    label="a user without OcuTalonAdmin"
  else
    run_admin "" "" 0
    label="irisowner (%All, no OcuTalonAdmin)"
  fi
  if [ "$admin_login" = 1 ] && [ "$admin_outcome" = not_allowed ] && [ "$admin_lines" = "$text_refused" ]; then
    pass "step 3: $label ($admin_user) is refused with the exact line"
  else
    echo "  login '$admin_login' user '$admin_user' outcome '$admin_outcome' printed '$admin_lines'"
    fail "step 3: $label was not refused with the exact line"
  fi
done
if [ "$(setting_row)" = 1 ] && [ "$(settingsops_headers)" = "$heads0" ]; then
  pass "step 3: the row and the headers to SettingsOps are unchanged (step 7 checks the audit log)"
else
  fail "step 3: the row is '$(setting_row)', the headers to SettingsOps '$(settingsops_headers)' (were $heads0)"
fi
demo_surfaces "$tmp/s3.surf"
compare_surfaces "step 3: the surfaces equal F0" "$tmp/f0.surf" "$tmp/s3.surf"

# --- step 4: the admin switches demo mode off ---

began=$SECONDS
run_admin "$adminuser" "$adminpassword" 0
off_s=$((SECONDS - began))
t_off=$SECONDS
if [ "$admin_login" = 1 ] && [ "$admin_user" = "$adminuser" ] && [ "$admin_outcome" = off ] && [ "$admin_lines" = "$text_off" ]; then
  pass "step 4: $adminuser prints the off line (outcome off; the Demo step ran in the SettingsOps job and succeeded, off in $off_s s)"
else
  echo "  login '$admin_login' user '$admin_user' outcome '$admin_outcome' printed '$admin_lines'"
  fail "step 4: the admin's SetDemoMode(0) did not print the off line"
fi
echo "INFO Task 0: SetDemoMode(0) took $off_s s end to end, outcome '$admin_outcome'"
if [ "$(setting_row)" = 0 ]; then
  pass "step 4: the demo.mode row is 0"
else
  fail "step 4: the demo.mode row is '$(setting_row)', wanted 0"
fi
demo_surfaces "$tmp/s4.surf"
compare_surfaces "step 4: the surfaces equal F0 less OCUORDERS" "$tmp/f0.surf" "$tmp/s4.surf" --drop-orders
check_demo_off "step 4"

# --- step 5: what reads the setting follows ---

poll_state "step 5" "$t_off" false
code=$(api_post demo/break-feed '{}')
if [ "$code" = 501 ] && grep -q '"not_built"' "$tmp/post.body"; then
  pass "step 5: POST /v1/demo/break-feed still answers 501 not_built"
else
  fail "step 5: POST /v1/demo/break-feed answered '$code'"
fi
probe=$(notify_probe)
case $probe in
  "11|"[1-9]*"|0") pass "step 5: with demo mode off a tell-now leaves a header to WebChatOut and none to SimPhoneOut ($probe)" ;;
  *) fail "step 5: the Notification was '$probe', wanted a header to WebChatOut and none to SimPhoneOut" ;;
esac
e2e 0

# --- step 6: the admin switches demo mode on ---

began=$SECONDS
run_admin "$adminuser" "$adminpassword" 1
on_s=$((SECONDS - began))
t_on=$SECONDS
if [ "$admin_login" = 1 ] && [ "$admin_user" = "$adminuser" ] && [ "$admin_outcome" = on ] && [ "$admin_lines" = "$text_on" ]; then
  pass "step 6: $adminuser prints the on line (outcome on; the Demo step ran in the SettingsOps job and succeeded, on in $on_s s)"
else
  echo "  login '$admin_login' user '$admin_user' outcome '$admin_outcome' printed '$admin_lines'"
  fail "step 6: the admin's SetDemoMode(1) did not print the on line"
fi
echo "INFO Task 0: SetDemoMode(1) took $on_s s end to end, outcome '$admin_outcome'"
if [ "$(setting_row)" = 1 ]; then
  pass "step 6: the demo.mode row is 1"
else
  fail "step 6: the demo.mode row is '$(setting_row)', wanted 1"
fi
check_demo_on "step 6"
check_orders_jobs "step 6"
demo_surfaces "$tmp/s6.surf"
compare_surfaces "step 6: the surfaces equal F0" "$tmp/f0.surf" "$tmp/s6.surf"

# --- step 7: the audit log names the admin, and nobody else ---

settings_audit_seen() {
  [ "$(settings_audit_rows "$adminuser" 0 system)" = 1 ] && [ "$(settings_audit_rows "$adminuser" 1 system)" = 1 ]
}
if wait_until 180 settings_audit_seen; then
  pass "step 7: one OcuTalon/Settings/Settings entry names $adminuser with value 0 and one with value 1, both from the channel system"
else
  fail "step 7: the audit log holds '$(settings_audit_rows "$adminuser" 0 system)' entry(ies) with value 0 and '$(settings_audit_rows "$adminuser" 1 system)' with value 1 from the channel system for $adminuser within 180 s ('$(settings_audit_rows "$adminuser" 0)' and '$(settings_audit_rows "$adminuser" 1)' from any channel)"
fi
total=$(settings_audit_total)
if [ "$total" = "$((audit0 + 2))" ] && [ "$(settings_audit_rows "$plainuser" '')" = 0 ] && [ "$(settings_audit_rows irisowner '')" = 0 ]; then
  pass "step 7: those are the only two new Settings entries, and none names $plainuser or irisowner"
else
  fail "step 7: the Settings entries are $total (wanted $((audit0 + 2))); $plainuser: $(settings_audit_rows "$plainuser" ''), irisowner: $(settings_audit_rows irisowner '')"
fi

# --- step 8: the page and /state follow ---

poll_state "step 8" "$t_on" true
probe=$(notify_probe)
case $probe in
  "11|"[1-9]*"|"[1-9]*)
    pass "step 8: with demo mode on again a tell-now leaves a header to WebChatOut and one to SimPhoneOut ($probe)" ;;
  *) fail "step 8: the Notification was '$probe', wanted a header to WebChatOut and to SimPhoneOut" ;;
esac
e2e 1

if [ "$fails" -ne 0 ]; then
  echo "test-demo-switch: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-demo-switch: all checks passed"
