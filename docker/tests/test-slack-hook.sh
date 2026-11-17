#!/usr/bin/env bash
# Live test of the Slack route of the hook application (Story 27.1; AD-1, AD-13, AD-14, AD-17, AD-19, AD-24, AD-26; Contest Planner rulings R1 to R6, R8 and R9): one
# throwaway, started twice on the same volume, posts signed and unsigned requests to POST /ocutalon/hook/slack/events through the real web application and checks what
# the route, SlackIn, Conversation and Intake did. No call is made to slack.com or any other service: the only traffic is curl to the throwaway. The signing secret and the bot
# token are dummy values that live only in shell variables of this script and in a compose override in its temporary folder; neither is ever printed, and a check that fails
# prints counts only. In order:
#   1. (R9) the default stack, with no override: Slack is off, so a signed POST to the route is 404 with no body, SlackIn.On() is 0, and nothing is counted;
#   2. the override with the two dummy values is layered and the stack is recreated on the same volume; it ends ready, every enabled adapterless item (SlackIn included) answers
#      CreateBusinessService, SlackIn.On() is 1, and the README account's session (the one durable session of its user) and an open approval request are seeded; no link is seeded:
#      the link is made through the real settings route (Story 27.3, below);
#   3a. (R3) a signed url_verification is 200 text/plain with the challenge, and the same request unsigned is 401 with no challenge in the answer;
#   4. (R5) rejections with a marker in each body, straight after the unsigned challenge: unsigned, a wrong signature, a timestamp 301 s old and over 65,536 bytes are 401 or 413,
#      and a form body is 400; all are counted in the slot slack (6 with the unsigned challenge), the burst wrote one audit entry, no event id was claimed and no marker is in the
#      event log, the audit log or any log of the container;
#   3-link. (Story 27.3) the README admin signs in with curl: GET /api/v1/settings/channels/slack answers state on and the events path; a signed direct message from the fixture member
#      before the link is Ignored (unlinked) and notes the workspace (T0FIXTURE1) in ^OcuTalonP.SlackW; POST links the member to the README user (200, one Settings entry slackLink.<Ref>,
#      from nothing to the user, and no id in it), and a second POST of the same pair answers the same Ref;
#   3b. (R1, R2, R4, R6) signed events: a linked member's direct message is 200 in under 3 s and, in the end, exactly one Turn of channel slack in the member's session, joined to the
#      session's thread; the same event id with X-Slack-Retry-Num 1 is 200 and still one Turn; a typed "approve" is a second user Turn and leaves the open approval request pending; an
#      unlinked member, the same member id in another team, a bot_id, a message_changed and a channel message are 200 each, add no Turn and leave one Ignored header each, in a trace
#      session of its own;
#      The five ignored events also leave the rows of the link table exactly as they were, the second team's (R2, Contest Planner ruling 2026-11-16) included: the same member id from a second
#      team and an unlinked member id create and change no link row;
#   5. (R8, NFR-11) the leak scan: neither dummy value, no fixture id and no marker of an ignored or rejected request is in the event log, the live events, the audit log, the container's
#      output, messages.log, the after-start log, the globals or the Interoperability message bodies, with a positive control for each scan (the linked message's text is found; the audit holds
#      the link's entry);
#   6. (Story 27.3) the README admin DELETEs the link (200, the row gone, one more Settings entry, from the user to nothing, with no id in either entry), and a further signed direct message from the
#      member is Ignored (unlinked), makes no Turn and leaves the open approval request pending.
#   7. (Contest Planner ruling (a)) the use-time role check, in the production job (Core.Conversation, channel slack only): fixture IRIS accounts that hold OcuTalonUser are linked through the real route and
#      get a Turn each; a viewer-only account, an admin-only account and an account with OcuTalonAdmin and no chat role are refused at link time (400 user_unknown, no audit entry) and are not in the list's
#      users; an admin who also holds OcuTalonUser keeps getting turns; an account that is cut down after it was linked (to the viewer role alone, to OcuTalonAdmin alone, to no role) gets no Turn from its next
#      direct message, no Decide request, no Notify (no reply is sent), no Delivery row and exactly one content-free Ignored with the reason not_user for each, and no marker of a refused message is in the event
#      log, the live events, the audit log or the container's logs.
# The project is unique and publishes its web port on 127.0.0.1 only (OCUTALON_TEST_WEB_PORT or the first free of 52800 to 52819). An EXIT trap removes the project with its volume
# and images. Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), node and curl.
set -u

. "$(dirname "$0")/lib-live.sh"
live_start slackhook

# The dummy values: held in shell variables and in the compose override of this run's temporary folder, never printed. Both start with one prefix, so that one scan finds either.
DUMMY=zzslackdummy-
secret="${DUMMY}sign-$(openssl rand -hex 12)"
token="${DUMMY}token-$(openssl rand -hex 12)"
TEAM=T0FIXTURE1
MEMBER=U0FIXTURE1
OTHERTEAM=T0FIXTURE2
UNLINKED=U0FIXTURE9
LINKEDTEXT=zzslackdm
IGNOREDTEXT=zzslackign
REJECTEDTEXT=zzslackrej
URL=/ocutalon/hook/slack/events

live_web_port || die "no web port for the throwaway"
base="http://127.0.0.1:$web_port"

# sign <timestamp> <file>: Slack's v0 signature of the file's bytes. The secret goes in through the environment of node, never through an argument.
sign() {
  SLACK_DUMMY_SECRET="$secret" node -e '
    const crypto = require("node:crypto"), fs = require("node:fs");
    const [ts, file] = process.argv.slice(1);
    const body = Buffer.concat([Buffer.from("v0:" + ts + ":"), fs.readFileSync(file)]);
    process.stdout.write("v0=" + crypto.createHmac("sha256", process.env.SLACK_DUMMY_SECRET).update(body).digest("hex"));
  ' "$1" "$2"
}

# slack_post <file> <timestamp or ""> <signature or ""> [<content type> [<retry number>]]: posts the file's bytes to the route; the answer's body is in $tmp/out.body, and the
# output is "<status> <seconds>".
slack_post() {
  local file=$1 ts=$2 sig=$3 ctype=${4:-application/json} retry=${5:-} args=()
  args=(-s --max-time 30 -o "$tmp/out.body" -w '%{http_code} %{time_total}' -X POST -H "Content-Type: $ctype")
  if [ -n "$ts" ]; then args+=(-H "X-Slack-Request-Timestamp: $ts"); fi
  if [ -n "$sig" ]; then args+=(-H "X-Slack-Signature: $sig"); fi
  if [ -n "$retry" ]; then args+=(-H "X-Slack-Retry-Num: $retry" -H "X-Slack-Retry-Reason: http_timeout"); fi
  curl "${args[@]}" --data-binary @"$file" "$base$URL"
}

# signed_post <file> [<retry number>]: a post that is signed correctly now.
signed_post() {
  local ts
  ts=$(date +%s)
  slack_post "$1" "$ts" "$(sign "$ts" "$1")" application/json "${2:-}"
}

# mkevent <file> <event id> <team> <member> <text> [<more members of the event, as JSON text> [<channel type>]]: an event_callback for a message.
mkevent() {
  printf '{"type":"event_callback","event_id":"%s","team_id":"%s","event":{"type":"message","channel_type":"%s","user":"%s","text":"%s"%s}}' "$2" "$3" "${7:-im}" "$4" "$5" "${6:-}" > "$1"
}

# expect_post <label> <wanted status> <file> [<timestamp> <signature> [<content type>]]: posts (signed correctly now when no timestamp is given) and checks the status.
expect_post() {
  local label=$1 want=$2 file=$3 out
  if [ $# -ge 4 ]; then out=$(slack_post "$file" "$4" "$5" "${6:-application/json}"); else out=$(signed_post "$file"); fi
  if [ "${out%% *}" = "$want" ]; then pass "$label: $want"; else fail "$label: wanted $want, got '${out%% *}'"; fi
  LAST_TIME=${out#* }
}

# scalar <namespace> <name> <script line>...: the value of the CHK|<name>| line that the script prints.
scalar() {
  local ns=$1 name=$2
  shift 2
  { printf '%s\n' "$@"; echo 'Halt'; } | session_value "$ns" "$name"
}

turns() {
  scalar OCUTALON turns "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND Channel = 'slack'\",\"$session\") Do rs.%Next() Write !,\"CHK|turns|\",+rs.%GetData(1)"
}
turns_are() { [ "$(turns)" = "$1" ]; }

ignored_headers() {
  scalar OCUTALON ignored "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Channel.Slack.Ignored'\") Do rs.%Next() Write !,\"CHK|ignored|\",+rs.%GetData(1)"
}

# ignored_are <count>: true when the Ignored headers number the count.
ignored_are() { [ "$(ignored_headers)" = "$1" ]; }

# link_rows: every row of the link table as "team/member/session;" in the order of the rows' ids.
link_rows() {
  scalar OCUTALON rows 'Set r="",id="" For { Set id=$Order(^OcuTalonP.SlackLinkD(id)) Quit:id=""  Set o=##class(OcuTalon.Data.SlackLink).%OpenId(id) If $IsObject(o) { Set r=r_o.TeamId_"/"_o.MemberId_"/"_o.SessionRef_";" } } Write !,"CHK|rows|",r'
}

# The README account of a local install signs in with the cookie jar, and the settings routes are called with the browser envelope (a copy of test-documents.sh's helpers,
# because lib-live.sh is shared).
readme_user=ocutalon
readme_password=ocutalon
jar="$tmp/jar"
sign_in() {
  : > "$jar"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" -d "IRISUsername=$readme_user" -d "IRISPassword=$readme_password" --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/"
}

# api_send <method> <path> [<body file>]: prints the status code; the body is in $tmp/api.body.
api_send() {
  local method=$1 path=$2 file=${3:-} args=()
  args=(-s --max-time 60 -b "$jar" -c "$jar" -o "$tmp/api.body" -w '%{http_code}' -X "$method" -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base")
  if [ -n "$file" ]; then args+=(--data-binary "@$file"); fi
  curl "${args[@]}" "$base/ocutalon/api/v1/$path"
}

# json_field <field>: the first string value of the field in $tmp/api.body.
json_field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$tmp/api.body" | head -n 1; }

# --- 1 (R9): the default stack: Slack is off ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200
  die "phase 1: the default start did not end ready within $LIVE_FIRST_START_WAIT s"
fi
pass "phase 1: the default stack started ready"

mkevent "$tmp/off.json" Ev0OFF "$TEAM" "$MEMBER" "$LINKEDTEXT off"
expect_post "phase 1 (R9): a signed POST to the Slack route of a default stack" 404 "$tmp/off.json"
if [ ! -s "$tmp/out.body" ]; then pass "phase 1: and the answer has no body"; else fail "phase 1: the 404 has a body"; fi
expect_post "phase 1 (R9): an unsigned POST to it" 404 "$tmp/off.json" "" ""
check_session "phase 1: Slack is off in the process of the stack, and nothing was counted or claimed" OCUTALON \
  "CHK|on|0
CHK|counted|0
CHK|claimed|0" \
  'Write !,"CHK|on|",##class(OcuTalon.Channel.Slack.In).On()' \
  'Write !,"CHK|counted|",$Data(^OcuTalonP.WebhookC("r","slack"))' \
  'Write !,"CHK|claimed|",$Data(^OcuTalonP.SlackE)' \
  'Halt'

# --- 2: Slack on: the override, a recreate on the same volume, the seed ---

printf 'services:\n  iris:\n    environment:\n      SLACK_SIGNING_SECRET: "%s"\n      SLACK_BOT_TOKEN: "%s"\n' "$secret" "$token" > "$tmp/slack.yml"
live_add_file "$tmp/slack.yml"
if ! dc up -d > "$tmp/up2.log" 2>&1; then
  tail -n 20 "$tmp/up2.log" | sed "s/$secret/<redacted>/g; s/$token/<redacted>/g"
  die "phase 2: the recreate with the Slack override failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 300; then
  start_log | tail -n 20 | cut -c1-200
  die "phase 2: the start with the Slack override did not end ready within 300 s"
fi
pass "phase 2: the stack recreated on the same volume ended ready"
check_items_run "phase 2"
check_session "phase 2: Slack is on in the process of the stack" OCUTALON \
  "CHK|on|1" \
  'Write !,"CHK|on|",##class(OcuTalon.Channel.Slack.In).On()' \
  'Halt'
seed=$(printf '%s\n' \
  'Set s=##class(OcuTalon.Data.Session).ForUser("ocutalon",.sc).Ref' \
  'Set a=##class(OcuTalon.Test.Data.Fixture).Approval(s)' \
  'Write !,"CHK|seed|",s,"|",a,"|",$SYSTEM.Status.IsOK(sc)' \
  'Halt' | session_value OCUTALON seed)
session=$(printf '%s' "$seed" | cut -d'|' -f1)
approval=$(printf '%s' "$seed" | cut -d'|' -f2)
if [ -n "$session" ] && [ -n "$approval" ] && [ "$(printf '%s' "$seed" | cut -d'|' -f3)" = 1 ]; then
  pass "phase 2: the README account's session and an open approval request are seeded, and no link"
else
  die "phase 2: the seed failed ($seed)"
fi
audit_mark=$(scalar OCUTALON mark 'Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()' )

# --- 3a (R3): the challenge ---

printf '{"type":"url_verification","challenge":"zz-challenge-0123"}' > "$tmp/challenge.json"
expect_post "phase 3 (R3): a signed url_verification" 200 "$tmp/challenge.json"
if [ "$(cat "$tmp/out.body")" = "zz-challenge-0123" ]; then pass "phase 3: its answer is the challenge, and nothing else"; else fail "phase 3: the challenge was not echoed as the whole body"; fi
ts=$(date +%s)
code=$(curl -s --max-time 30 -o /dev/null -D "$tmp/out.head" -X POST -H 'Content-Type: application/json' -H "X-Slack-Request-Timestamp: $ts" -H "X-Slack-Signature: $(sign "$ts" "$tmp/challenge.json")" --data-binary @"$tmp/challenge.json" -w '%{http_code}' "$base$URL")
if [ "$code" = 200 ] && tr -d '\r' < "$tmp/out.head" | grep -i '^content-type:' | grep -qi 'text/plain'; then pass "phase 3: the challenge is text/plain"; else fail "phase 3: status '$code' or a content type that is not text/plain"; fi
expect_post "phase 3 (R3): the same challenge unsigned" 401 "$tmp/challenge.json" "" ""
if ! grep -q 'zz-challenge' "$tmp/out.body"; then pass "phase 3: and the unsigned answer holds no challenge"; else fail "phase 3: the unsigned request was answered with the challenge"; fi

# --- 4 (R5): rejections that carry a marker in the body ---

mkevent "$tmp/rejected.json" "Ev0${REJECTEDTEXT}" "T0${REJECTEDTEXT}" "U0${REJECTEDTEXT}" "$REJECTEDTEXT body"
now=$(date +%s)
expect_post "phase 4: an unsigned request" 401 "$tmp/rejected.json" "" ""
expect_post "phase 4: a wrong signature" 401 "$tmp/rejected.json" "$now" "v0=$(printf '%064d' 0)"
stale=$((now - 301))
expect_post "phase 4: a timestamp 301 s old with the right signature" 401 "$tmp/rejected.json" "$stale" "$(sign "$stale" "$tmp/rejected.json")"
{ printf '{"pad":"%s' "$REJECTEDTEXT"; head -c 70000 /dev/zero | tr '\0' x; printf '"}'; } > "$tmp/big.json"
expect_post "phase 4: a body of more than 65,536 bytes" 413 "$tmp/big.json" "" ""
printf 'token=%s&team_id=%s' "$REJECTEDTEXT" "$TEAM" > "$tmp/form.txt"
expect_post "phase 4: a form body" 400 "$tmp/form.txt" "" "" application/x-www-form-urlencoded
check_session "phase 4: the six rejections are counted in the slot slack, one audit entry was written, no event id was claimed and the marker is in no node of the Slack globals" OCUTALON \
  "CHK|counted|6
CHK|audits|1
CHK|claimed|0
CHK|markeringlobals|0" \
  "Set entries=##class(OcuTalon.Test.Bridge.AuditLog).Wait(\"$audit_mark\",\"OcuTalon\",\"Action\",\"Action\",\"slack\",\"\",1)" \
  'Set sum=0 For i=0:1:entries.%Size()-1 { Set sum=sum+entries.%Get(i).data.counts.rejected }' \
  'Write !,"CHK|counted|",sum+$ListGet($Get(^OcuTalonP.WebhookC("r","slack")),2)' \
  'Write !,"CHK|audits|",entries.%Size()' \
  'Write !,"CHK|claimed|",$Data(^OcuTalonP.SlackE)' \
  "Set n=0,r=\"^OcuTalonP.SlackE\" For { Set r=\$Query(@r,1,v) If r=\"\" { Quit } If (r[\"$REJECTEDTEXT\")||(v[\"$REJECTEDTEXT\") { Set n=n+1 } } Write !,\"CHK|markeringlobals|\",n" \
  'Halt'

# --- 3-link (Story 27.3): the admin links the member through the real settings route ---

sign_in
code=$(api_send GET settings/channels/slack)
if [ "$code" = 200 ] && grep -q '"state":"on"' "$tmp/api.body" && grep -q '"path":"/ocutalon/hook/slack/events"' "$tmp/api.body"; then
  pass "phase 3-link: GET of the Slack settings is 200 with state on and the events path"
else
  fail "phase 3-link: GET of the Slack settings is '$code' and does not say state on with the path"
fi
if grep -q '"users":\[[^]]*"ocutalon"' "$tmp/api.body"; then pass "phase 3-link: and it offers the README user"; else fail "phase 3-link: the list does not offer the README user"; fi
mkevent "$tmp/prelink.json" Ev0PRELINK "$TEAM" "$MEMBER" "$IGNOREDTEXT before the link"
expect_post "phase 3-link (R2): a signed direct message from the fixture member before the link" 200 "$tmp/prelink.json"
if wait_until 90 ignored_are 1; then pass "phase 3-link: it is Ignored (one Ignored header), as an unlinked member's"; else fail "phase 3-link: $(ignored_headers) Ignored header(s), wanted 1"; fi
check_session "phase 3-link: SlackIn noted the workspace of the signed event, and no row links the member yet" OCUTALON \
  "CHK|workspace|$TEAM
CHK|rows|" \
  'Write !,"CHK|workspace|",##class(OcuTalon.Data.SlackLink).Workspace()' \
  'Write !,"CHK|rows|",$Order(^OcuTalonP.SlackLinkD(""))' \
  'Halt'
link_mark=$(scalar OCUTALON mark 'Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()')
printf '{"user":"%s","member":"%s"}' "$readme_user" "$MEMBER" > "$tmp/link.json"
code=$(api_send POST settings/channels/slack "$tmp/link.json")
if [ "$code" = 200 ] && grep -q '"result":"done"' "$tmp/api.body"; then pass "phase 3-link: POST links the member to the README user (200 done)"; else fail "phase 3-link: POST answered '$code'"; fi
link_ref=$(json_field ref)
check_session "phase 3-link: the member is linked to the README account's session, and one Settings entry names slackLink.<Ref>, from nothing to the user" OCUTALON \
  "CHK|session|$session
CHK|entries|1
CHK|from||to|$readme_user" \
  "Write !,\"CHK|session|\",##class(OcuTalon.Data.SlackLink).SessionFor(\"$TEAM\",\"$MEMBER\")" \
  "Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(\"$link_mark\",\"OcuTalon\",\"Settings\",\"\",\"slackLink.\",\"\",1,30)" \
  'Write !,"CHK|entries|",e.%Size()' \
  'Set d=e.%Get(0).data Write !,"CHK|from|",d.from,"|to|",d.to' \
  'Halt'
code=$(api_send POST settings/channels/slack "$tmp/link.json")
if [ "$code" = 200 ] && [ -n "$link_ref" ] && [ "$(json_field ref)" = "$link_ref" ]; then pass "phase 3-link: the same pair again is 200 with the same Ref"; else fail "phase 3-link: the repeat answered '$code' with another Ref"; fi

# --- 3b (R1, R2, R4, R6): the events ---

mkevent "$tmp/dm.json" Ev0LINKED "$TEAM" "$MEMBER" "$LINKEDTEXT hello from slack"
out=$(signed_post "$tmp/dm.json")
elapsed=${out#* }
if [ "${out%% *}" = 200 ] && [ ! -s "$tmp/out.body" ] && awk -v t="$elapsed" 'BEGIN { exit !(t < 3.0) }'; then
  pass "phase 3 (R4): a linked member's direct message is 200 with no body in ${elapsed}s, under Slack's 3 s"
else
  fail "phase 3 (R4): status '${out%% *}', ${elapsed}s, body of $(wc -c < "$tmp/out.body" | tr -d ' ') byte(s)"
fi
if wait_until 90 turns_are 1; then
  pass "phase 3: exactly one Turn of channel slack appears in the member's session (Conversation took the Item)"
else
  fail "phase 3: $(turns) Turn(s) of channel slack in the member's session, wanted 1"
fi
check_session "phase 3: the Turn is a user turn of the session and the session has a trace thread" OCUTALON \
  "CHK|turn|slack|$LINKEDTEXT hello from slack
CHK|thread|1" \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT Channel, Text FROM OcuTalon_Data.Turn WHERE SessionRef = ?\",\"$session\") Do rs.%Next() Write !,\"CHK|turn|\",rs.%Get(\"Channel\"),\"|\",rs.%Get(\"Text\")" \
  "Write !,\"CHK|thread|\",(##class(OcuTalon.Data.Session).RefIndexOpen(\"$session\").ThreadSessionId'=\"\")" \
  'Halt'
out=$(signed_post "$tmp/dm.json" 1)
if [ "${out%% *}" = 200 ]; then pass "phase 3 (R4): the same event id with X-Slack-Retry-Num 1 is 200"; else fail "phase 3 (R4): the retry is '${out%% *}'"; fi
sleep 5
if [ "$(turns)" = 1 ]; then pass "phase 3 (R4): and there is still one Turn"; else fail "phase 3 (R4): $(turns) Turn(s) after the retry"; fi

mkevent "$tmp/approve.json" Ev0APPROVE "$TEAM" "$MEMBER" "approve"
expect_post "phase 3 (R6): a linked member types approve" 200 "$tmp/approve.json"
if wait_until 90 turns_are 2; then
  pass "phase 3 (R6): it is a second user Turn, like any typed message"
else
  fail "phase 3 (R6): $(turns) Turn(s), wanted 2"
fi
check_session "phase 3 (R6): the open approval request is still pending and unanswered" OCUTALON \
  "CHK|approval|pending||" \
  "Set r=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(\"$approval\") Write !,\"CHK|approval|\",r.State,\"|\",r.AnsweredAt,\"|\",r.AnsweredAction" \
  'Halt'

before=$(ignored_headers)
rows_before=$(link_rows)
mkevent "$tmp/i1.json" Ev0UNLINKED "$TEAM" "$UNLINKED" "$IGNOREDTEXT unlinked"
mkevent "$tmp/i2.json" Ev0OTHERTEAM "$OTHERTEAM" "$MEMBER" "$IGNOREDTEXT other team"
mkevent "$tmp/i3.json" Ev0BOT "$TEAM" "$MEMBER" "$IGNOREDTEXT bot" ',"bot_id":"B0FIXTURE1"'
mkevent "$tmp/i4.json" Ev0CHANGED "$TEAM" "$MEMBER" "$IGNOREDTEXT edit" ',"subtype":"message_changed"'
mkevent "$tmp/i5.json" Ev0CHANNEL "$TEAM" "$MEMBER" "$IGNOREDTEXT channel" "" channel
for n in 1 2 3 4 5; do
  expect_post "phase 3 (R1, R2): ignored event $n" 200 "$tmp/i$n.json"
done
sleep 5
after=$(ignored_headers)
if [ "$(turns)" = 2 ]; then pass "phase 3: none of the five ignored events became a Turn"; else fail "phase 3: $(turns) Turn(s) after the ignored events, wanted 2"; fi
if [ "$((after - before))" = 5 ]; then pass "phase 3: each left one Ignored header (5 new)"; else fail "phase 3: $((after - before)) new Ignored header(s), wanted 5"; fi
if [ -n "$rows_before" ] && [ "$(link_rows)" = "$rows_before" ]; then
  pass "phase 3 (R2, Contest Planner ruling 2026-11-16): the second team's events, and the unlinked member's, created and changed no link row (the rows are exactly as they were)"
else
  fail "phase 3 (R2): the rows of the link table changed (before: $(printf '%s' "$rows_before" | wc -c | tr -d ' ') characters, after: $(link_rows | wc -c | tr -d ' '))"
fi
check_session "phase 3: the Ignored headers (the five and the one before the link) are SlackIn to Intake, each in a trace session of its own, none in the member's thread" OCUTALON \
  "CHK|route|6
CHK|sessions|6
CHK|inthread|0" \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Channel.Slack.Ignored' AND SourceConfigName = 'SlackIn' AND TargetConfigName = 'Intake'\") Do rs.%Next() Write !,\"CHK|route|\",rs.%GetData(1)" \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(DISTINCT SessionId) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Channel.Slack.Ignored'\") Do rs.%Next() Write !,\"CHK|sessions|\",rs.%GetData(1)" \
  "Set thread=##class(OcuTalon.Data.Session).RefIndexOpen(\"$session\").ThreadSessionId Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Channel.Slack.Ignored' AND SessionId = ?\",thread) Do rs.%Next() Write !,\"CHK|inthread|\",rs.%GetData(1)" \
  'Halt'

# --- 3c (R3): the signature is over the bytes as received: UTF-8 text and a body longer than one read chunk ---

before=$(ignored_headers)
utf8=$(printf 'caf\303\251 \346\227\245\346\234\254 \303\274x')
mkevent "$tmp/u8.json" Ev0UTF8 "$TEAM" "$MEMBER" "$utf8" "" channel
long=$(head -c 40000 /dev/zero | tr '\0' x)
mkevent "$tmp/long.json" Ev0LONG "$TEAM" "$MEMBER" "$long" "" channel
expect_post "phase 3 (R3): a signed event whose text is UTF-8 (two-byte and three-byte characters)" 200 "$tmp/u8.json"
expect_post "phase 3 (R3): a signed event of more than 40,000 bytes (more than one read chunk)" 200 "$tmp/long.json"
if wait_until 90 ignored_are "$((before + 2))"; then
  pass "phase 3: both were accepted as events (one Ignored header each), so their signatures matched the bytes as received"
else
  fail "phase 3: $(($(ignored_headers) - before)) new Ignored header(s) for the UTF-8 and the long event, wanted 2"
fi

# --- 5 (R8, NFR-11): the leak scan ---

# log_hits <text>: the lines of the container's output, messages.log and the after-start log that hold the text.
log_hits() {
  { dc logs --no-color iris 2>&1; dc exec -T iris cat "$mgr/messages.log" /durable/ocutalon-after-start.log 2>/dev/null; } | grep -cF -e "$1"
}
for pair in "the dummy signing secret and bot token:$DUMMY" "the fixture ids:0FIXTURE" "the text of an ignored event:$IGNOREDTEXT" "the body of a rejected request:$REJECTEDTEXT"; do
  n=$(log_hits "${pair#*:}")
  if [ "$n" = 0 ]; then pass "phase 5: no line of the container's output, messages.log or the after-start log holds ${pair%%:*}"; else fail "phase 5: $n line(s) of the container's logs hold ${pair%%:*}"; fi
done
if [ "$(log_hits "$LINKEDTEXT")" = 0 ]; then pass "phase 5: nor the text of the linked message, which only the Turn and its message hold"; else fail "phase 5: a line of the container's logs holds the linked message's text"; fi

zero=
for value in "$DUMMY" "0FIXTURE" "$IGNOREDTEXT" "$REJECTEDTEXT"; do
  zero="$zero${zero:+,}\"$value\""
done
check_session "phase 5: no event-log row, live event or message body of the Interoperability trace holds a secret, a fixture id or a marker (control: the linked message's text is found in a message)" OCUTALON \
  "CHK|log|0
CHK|live|0
CHK|trace|0
CHK|control|1" \
  "Set bad=0 For v=$zero { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?\",v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|log|\",bad" \
  "Set bad=0 For v=$zero { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?\",v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|live|\",bad" \
  "Set bad=0 For v=$zero { Set n=##class(OcuTalon.Test.Eval.KeyProof).TraceHits(v,0,.places,.stats,\"OCUTALON\") Set bad=bad+\$Select(n<0:1,1:n) } Write !,\"CHK|trace|\",bad" \
  "Set n=##class(OcuTalon.Test.Eval.KeyProof).TraceHits(\"$LINKEDTEXT\",0,.places,.stats,\"OCUTALON\") Write !,\"CHK|control|\",(n>0)" \
  'Halt'
check_session "phase 5: no audit entry holds a secret, a fixture id or a marker" %SYS \
  "CHK|audit|0" \
  "Set bad=0 For v=$zero { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?\",v,v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|audit|\",bad" \
  'Halt'
check_session "phase 5: no node of any global holds a secret, an ignored text or a rejected body (control: the linked message's text is found)" OCUTALON \
  "CHK|globals|0
CHK|control|1" \
  "Set bad=0 For v=\"$DUMMY\",\"$IGNOREDTEXT\",\"$REJECTEDTEXT\" { Set n=##class(OcuTalon.Test.Eval.KeyProof).GlobalHits(v,\"\",.places,.stats) Set bad=bad+\$Select(n<0:1,1:n) } Write !,\"CHK|globals|\",bad" \
  "Set n=##class(OcuTalon.Test.Eval.KeyProof).GlobalHits(\"$LINKEDTEXT\",\"\",.places,.stats) Write !,\"CHK|control|\",(n>0)" \
  'Halt'

# --- 6 (Story 27.3): the admin unlinks the member through the real route ---

unlink_mark=$(scalar OCUTALON mark 'Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()')
code=$(api_send DELETE "settings/channels/slack/$link_ref")
if [ "$code" = 200 ] && grep -q '"result":"done"' "$tmp/api.body"; then pass "phase 6: DELETE of the link is 200 done"; else fail "phase 6: DELETE answered '$code'"; fi
code=$(api_send DELETE "settings/channels/slack/$link_ref")
if [ "$code" = 404 ]; then pass "phase 6: and a second DELETE of the same Ref is 404"; else fail "phase 6: the second DELETE answered '$code'"; fi
check_session "phase 6: the link is gone, and one more Settings entry names it, from the user to nothing" OCUTALON \
  "CHK|session|
CHK|rows|
CHK|entries|1
CHK|from|$readme_user|to|" \
  "Write !,\"CHK|session|\",##class(OcuTalon.Data.SlackLink).SessionFor(\"$TEAM\",\"$MEMBER\")" \
  'Write !,"CHK|rows|",$Order(^OcuTalonP.SlackLinkD(""))' \
  "Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(\"$unlink_mark\",\"OcuTalon\",\"Settings\",\"\",\"slackLink.\",\"\",1,30)" \
  'Write !,"CHK|entries|",e.%Size()' \
  'Set d=e.%Get(0).data Write !,"CHK|from|",d.from,"|to|",d.to' \
  'Halt'
check_session "phase 6: no audit entry holds a fixture id (control: the three entries of the link, its repeat and the unlink are there)" %SYS \
  "CHK|audit|0
CHK|control|1" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?","0FIXTURE","0FIXTURE") Do rs.%Next() Write !,"CHK|audit|",rs.%GetData(1)' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ?","slackLink.") Do rs.%Next() Write !,"CHK|control|",(rs.%GetData(1)>=3)' \
  'Halt'
before=$(ignored_headers)
mkevent "$tmp/after.json" Ev0AFTERUNLINK "$TEAM" "$MEMBER" "$IGNOREDTEXT after the unlink"
expect_post "phase 6: a signed direct message from the member after the unlink" 200 "$tmp/after.json"
if wait_until 90 ignored_are "$((before + 1))"; then pass "phase 6: it is Ignored (one more Ignored header), as an unlinked member's"; else fail "phase 6: $(($(ignored_headers) - before)) new Ignored header(s), wanted 1"; fi
sleep 5
if [ "$(turns)" = 2 ]; then pass "phase 6: and it makes no new Turn (still 2)"; else fail "phase 6: $(turns) Turn(s) after the unlink, wanted 2"; fi

# --- 7 (Contest Planner ruling (a)): the use-time role check in the production job ---

# fixture_account <name> <roles>: an IRIS account holding the roles, with a random password that is never printed.
fixture_account() {
  local out
  out=$(live_fixture_user "$1" "Zq9-$(openssl rand -hex 10)" "$2" "slack role fixture")
  if [ "$out" = "CHK|fixture-user|1" ]; then pass "phase 7: the fixture account $1 is made with ${2:-no role}"; else fail "phase 7: the fixture account $1 was not made ('$out')"; fi
}

# set_roles <name> <roles>: the account's roles are replaced (an empty list removes every role).
set_roles() {
  local out
  out=$(scalar %SYS roles "Set p(\"Roles\")=\"$2\" Set sc=##class(Security.Users).Modify(\"$1\",.p) Write !,\"CHK|roles|\",\$SYSTEM.Status.IsOK(sc)")
  if [ "$out" = 1 ]; then pass "phase 7: the roles of $1 are now ${2:-none}"; else fail "phase 7: the roles of $1 were not changed ('$out')"; fi
}

# session_of <name>: the Ref of the account's one durable session (made when it has none).
session_of() { scalar OCUTALON s "Write !,\"CHK|s|\",##class(OcuTalon.Data.Session).ForUser(\"$1\").Ref"; }

turns_of() {
  scalar OCUTALON t "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?\",\"$1\") Do rs.%Next() Write !,\"CHK|t|\",+rs.%GetData(1)"
}
turns_of_are() { [ "$(turns_of "$1")" = "$2" ]; }

# idle: no Turn is queued or running, so that the sends counted next are the ones of the message under test.
idle() { [ "$(scalar OCUTALON q 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE State IN (?, ?)","queued","running") Do rs.%Next() Write !,"CHK|q|",+rs.%GetData(1)')" = 0 ]; }

not_user_count() { scalar OCUTALON n 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Channel_Slack.Ignored WHERE Reason = ?","not_user") Do rs.%Next() Write !,"CHK|n|",+rs.%GetData(1)'; }
not_user_are() { [ "$(not_user_count)" = "$1" ]; }

# sends_to_model_and_notify: the headers whose target is Decide or Notify, and the Delivery rows, as one number each.
sends() {
  scalar OCUTALON x 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName IN (?, ?)","Decide","Notify") Do rs.%Next() Set a=+rs.%GetData(1) Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Delivery") Do rs.%Next() Write !,"CHK|x|",a,"/",+rs.%GetData(1)'
}

# settled: the sends counted by sends() did not change over three seconds, so that the replies of the turns before are all counted.
settled() { local a b; a=$(sends); sleep 3; b=$(sends); [ "$a" = "$b" ]; }

# link_member <user> <member>: the README admin links the member to the user through the real route; the status is printed.
link_member() {
  printf '{"user":"%s","member":"%s"}' "$1" "$2" > "$tmp/link7.json"
  api_send POST settings/channels/slack "$tmp/link7.json"
}

# dm <label> <event id> <member> <text>: a signed direct message from the member.
dm() {
  mkevent "$tmp/dm7.json" "$2" "$TEAM" "$3" "$4"
  expect_post "phase 7: $1" 200 "$tmp/dm7.json"
}

REFUSEDTEXT=zzslackrefused
live_fixture_role OcuTalonViewer > /dev/null
fixture_account zzslkau "OcuTalonAdmin,OcuTalonUser"
fixture_account zzslkvl "OcuTalonUser"
fixture_account zzslkrm "OcuTalonUser"
fixture_account zzslkao "OcuTalonUser"
fixture_account zzslkviewer "OcuTalonViewer"
fixture_account zzslkadminonly "OcuTalonAdmin"
fixture_account zzslkadminviewer "OcuTalonAdmin,OcuTalonViewer"
sess_au=$(session_of zzslkau)
sess_vl=$(session_of zzslkvl)
sess_rm=$(session_of zzslkrm)
sess_ao=$(session_of zzslkao)
for name in zzslkviewer zzslkadminonly zzslkadminviewer; do session_of "$name" > /dev/null; done

# Link time: a viewer, an admin who holds neither chat role and a viewer who is an admin are refused with settings.slackUnknownUser (reason user_unknown), and the list offers only users who may chat.
audit_mark7=$(scalar OCUTALON mark 'Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()')
for name in zzslkviewer zzslkadminonly zzslkadminviewer; do
  code=$(link_member "$name" U0FIXTURE7)
  if [ "$code" = 400 ] && grep -q '"reason":"user_unknown"' "$tmp/api.body"; then pass "phase 7: linking $name (who may not chat) is refused as user_unknown"; else fail "phase 7: linking $name answered '$code'"; fi
done
code=$(api_send GET settings/channels/slack)
if [ "$code" = 200 ] && grep -q '"zzslkau"' "$tmp/api.body" && grep -q '"zzslkvl"' "$tmp/api.body" && ! grep -q -e '"zzslkviewer"' -e '"zzslkadminonly"' -e '"zzslkadminviewer"' "$tmp/api.body"; then
  pass "phase 7: the list offers the users who may chat and none of the three who may not"
else
  fail "phase 7: the list '$code' does not offer exactly the users who may chat"
fi
check_session "phase 7: the three refusals wrote no audit entry and made no link row" OCUTALON \
  "CHK|entries|0
CHK|rows|0" \
  "Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(\"$audit_mark7\",\"OcuTalon\",\"Settings\",\"\",\"slackLink.\",\"\",0,3)" \
  'Write !,"CHK|entries|",e.%Size()' \
  'Set n=0,id="" For { Set id=$Order(^OcuTalonP.SlackLinkD(id)) Quit:id=""  Set n=n+1 } Write !,"CHK|rows|",n' \
  'Halt'

# Qualifying users are linked and get a Turn each (pin 4: an admin who also holds OcuTalonUser; the read of their roles ran in the production job).
member_au=U0FIXTURE4; member_vl=U0FIXTURE5; member_rm=U0FIXTURE6; member_ao=U0FIXTURE8
for pair in "zzslkau:$member_au" "zzslkvl:$member_vl" "zzslkrm:$member_rm" "zzslkao:$member_ao"; do
  code=$(link_member "${pair%%:*}" "${pair#*:}")
  if [ "$code" = 200 ]; then pass "phase 7: ${pair%%:*} is linked"; else fail "phase 7: linking ${pair%%:*} answered '$code'"; fi
done
n=0
for pair in "$sess_au:$member_au" "$sess_vl:$member_vl" "$sess_rm:$member_rm" "$sess_ao:$member_ao"; do
  n=$((n + 1))
  dm "a linked user's direct message (before any change of roles)" "Ev0ROLE$n" "${pair#*:}" "$LINKEDTEXT role $n"
  if wait_until 90 turns_of_are "${pair%%:*}" 1; then pass "phase 7: it makes one Turn (the roles were read in the production job and allow it)"; else fail "phase 7: $(turns_of "${pair%%:*}") Turn(s), wanted 1"; fi
done

# Use time: the accounts are cut down after they were linked, and each next message is refused.
if ! wait_until 120 idle; then fail "phase 7: the turns did not settle within 120 s"; fi
if ! wait_until 60 settled; then fail "phase 7: the sends of the earlier turns did not settle within 60 s"; fi
set_roles zzslkvl "OcuTalonViewer"
set_roles zzslkao "OcuTalonAdmin"
set_roles zzslkrm ""
n=0
refused=0
for pair in "$sess_vl:$member_vl:viewer role alone" "$sess_ao:$member_ao:OcuTalonAdmin alone" "$sess_rm:$member_rm:no role"; do
  n=$((n + 1))
  rest=${pair#*:}
  before_sends=$(sends)
  refused=$((refused + 1))
  dm "a linked user cut down to the ${pair##*:} (pins 1, 3 and 5)" "Ev0CUT$n" "${rest%%:*}" "$REFUSEDTEXT $n"
  if wait_until 90 not_user_are "$refused"; then pass "phase 7: it leaves one Ignored with the reason not_user"; else fail "phase 7: $(not_user_count) not_user record(s), wanted $refused"; fi
  sleep 4
  if [ "$(not_user_count)" = "$refused" ]; then pass "phase 7: and no second record"; else fail "phase 7: $(not_user_count) not_user record(s) after the wait, wanted $refused"; fi
  if turns_of_are "${pair%%:*}" 1; then pass "phase 7: it makes no Turn (the session still has its one)"; else fail "phase 7: $(turns_of "${pair%%:*}") Turn(s), wanted 1"; fi
  if [ "$(sends)" = "$before_sends" ]; then pass "phase 7: nothing goes to Decide (no model call, no tool call) or Notify (no reply is sent), and no Delivery row is written"; else fail "phase 7: the sends to Decide and Notify and the Delivery rows changed ($before_sends, now $(sends))"; fi
done
check_session "phase 7: each not_user record has the fixed kind and no event id, and no Turn row exists for the refused messages" OCUTALON \
  "CHK|route|3
CHK|fixed|3
CHK|marker|0" \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND SourceConfigName = ? AND TargetConfigName = ?","OcuTalon.Channel.Slack.Ignored","Conversation","Intake") Do rs.%Next() Write !,"CHK|route|",rs.%GetData(1)' \
  'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Channel_Slack.Ignored WHERE Reason = ? AND Kind = ? AND (EventId IS NULL OR EventId = ?)","not_user","message.im","") Do rs.%Next() Write !,"CHK|fixed|",rs.%GetData(1)' \
  "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE Text [ ?\",\"$REFUSEDTEXT\") Do rs.%Next() Write !,\"CHK|marker|\",rs.%GetData(1)" \
  'Halt'
dm "an admin who also holds OcuTalonUser, once more" Ev0ROLEAU2 "$member_au" "$LINKEDTEXT role au again"
if wait_until 90 turns_of_are "$sess_au" 2; then pass "phase 7 (pin 4): an admin who also holds OcuTalonUser still gets turns"; else fail "phase 7: $(turns_of "$sess_au") Turn(s) for the admin who holds OcuTalonUser, wanted 2"; fi
zero7="\"$REFUSEDTEXT\",\"zzslk\",\"0FIXTURE\""
check_session "phase 7: no event-log row or live event holds the text of a refused message, a fixture account's name or a fixture id" OCUTALON \
  "CHK|log|0
CHK|live|0" \
  "Set bad=0 For v=$zero7 { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?\",v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|log|\",bad" \
  "Set bad=0 For v=$zero7 { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?\",v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|live|\",bad" \
  'Halt'
for pair in "the text of a refused message:$REFUSEDTEXT" "a fixture member id:0FIXTURE"; do
  n=$(log_hits "${pair#*:}")
  if [ "$n" = 0 ]; then pass "phase 7: no line of the container's output, messages.log or the after-start log holds ${pair%%:*}"; else fail "phase 7: $n line(s) of the container's logs hold ${pair%%:*}"; fi
done
check_session "phase 7: no audit entry holds the text of a refused message or a fixture member id (the entries of the links name the users, which Settings audit entries may)" %SYS \
  "CHK|audit|0" \
  "Set bad=0 For v=\"$REFUSEDTEXT\",\"0FIXTURE\" { Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT COUNT(*) FROM %SYS.Audit WHERE EventData [ ? OR Description [ ?\",v,v) Do rs.%Next() Set bad=bad+rs.%GetData(1) } Write !,\"CHK|audit|\",bad" \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-slack-hook: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-slack-hook: all checks passed"
