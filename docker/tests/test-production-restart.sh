#!/usr/bin/env bash
# Live test of the Production step across restarts (Story 0.6, matrix rows 19 and 20): builds the image and starts it in one
# throwaway compose project with the after-start script active and no model key, then
#   - row 19, the EvalIn switch (Story 0.7, row 14: the CI override passes OCUTALON_EVAL through): recreates the container with
#     OCUTALON_EVAL=1 in the environment of `docker compose up`, with no extra compose file, and then without it. With the
#     variable the start ends ready with STEP Production OK, CreateBusinessService("EvalIn") succeeds and the System Default
#     Setting row (OcuTalon.Production, EvalIn, any class, Enabled) is 1. Without it the service is refused as disabled and the
#     row is 0;
#   - row 20, an unclean stop: kills the instance with docker kill -s KILL and starts the container again. The next start ends
#     ready with STEP Production OK, the production is Running again, and every item runs as in the first start (the job
#     check of test-production.sh, row 14). The kill leaves the production Troubled, and the step recovers it: before the
#     kill ^Ens.Suspended, where RecoverProduction names the production it suspends, is empty, and after the next start it
#     names OcuTalon.Production (measured on build 154: a clean stop and CleanProduction leave it empty, so a step that
#     cleans the production instead of recovering it would lose its queued messages and fail this check).
#     Story 2.2 adds the snapshot: before the kill and again after the next start, the epoch, the chat and the rail that
#     Web.Api.StateBody builds for a session seeded with a turn, a check and a pending approval (Test.Data.Fixture) and a
#     pending reminder set through ReminderOps (Test.Schedule.ReminderFixture) are printed, and the two must be equal and hold
#     the four fixture refs. Journaling must be enabled
#     (%SYS.Journal.System.GetState() 0), and the journal is synced before the kill, so that the kill cannot lose the seeded
#     rows. The Test.Data.Fixture rows are removed afterwards; the reminder and its waiter go with the project.
#     Story 2.4 adds the turn queue: before the kill a second fixture session holds a turn that was left running (Attempt 1)
#     and a queued turn, each with its text; after the next start, within 60 s, both are done with the fallback reply
#     conversation.turnFallback (the real Decide has no model key and answers no_key), the running one on its second attempt,
#     each with both decision Refs set, the first turn's triage row and the second turn's turn row the fallback (tellnow,
#     Fallback, no_key), and the session's stream holds exactly one done chat.message for each, the first turn's Seq below
#     the second's. The rows are removed afterwards.
#     Story 12.1 adds the Telegram switch to row 19: the first start (the seam off, the CI dummy token) leaves both Telegram rows
#     0 and the mark off, with no job for TelegramIn and TelegramOut and no Bot API call at the mock. The OCUTALON_EVAL=1 start
#     runs with the seam at 1, the mark on and TELEGRAM_BOT_TOKEN set and empty (live_no_bot_token, which is what a .env copied
#     from .env.example holds): it ends ready, the no-key check passes, both rows are 0, the mark is off, and every enabled item
#     runs. The last start has the seam off, the mark on and the dummy token again, and leaves the rows 0 and the mark off.
# The first start also has to be a start with no model key that wrote no error to the event log.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its volume and
# images. Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t06r
unset OCUTALON_EVAL

# check_start <label>: this start's log lists STEP Production OK and ends with RESULT OK.
check_start() {
  log_steps > "$tmp/steps.log"
  if grep -qx 'STEP Production OK' "$tmp/steps.log" && tail -n 1 "$tmp/steps.log" | grep -q '^RESULT OK '; then
    pass "$1: the log has STEP Production OK and ends with RESULT OK"
  else
    sed 's/^/  /' "$tmp/steps.log" | tail -n 8
    fail "$1: the log has no STEP Production OK, or does not end with RESULT OK"
  fi
}

# check_eval <label> <enabled 1|0>: EvalIn's row holds the value, and CreateBusinessService("EvalIn") agrees with it.
check_eval() {
  if [ "$2" = 1 ]; then
    check_session "$1: the row is 1 and EvalIn answers CreateBusinessService" OCUTALON \
      "CHK|row|1
CHK|create|1" \
      'Write !,"CHK|row|",##class(Ens.Config.DefaultSettings).%OpenId("OcuTalon.Production||EvalIn||*||Enabled").SettingValue' \
      'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|create|",$SYSTEM.Status.IsOK(sc)' \
      'Halt'
  else
    check_session "$1: the row is 0 and EvalIn is refused as disabled" OCUTALON \
      "CHK|row|0
CHK|refused|1" \
      'Write !,"CHK|row|",##class(Ens.Config.DefaultSettings).%OpenId("OcuTalon.Production||EvalIn||*||Enabled").SettingValue' \
      'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|refused|",($SYSTEM.Status.IsError(sc)&&($SYSTEM.Status.GetErrorText(sc)["is disabled"))' \
      'Halt'
  fi
}

# check_telegram_off <label> <tokenset 1|0>: in one session, both Telegram rows are 0, the mark row exists and says off, TokenSet()
# is the given value, neither Telegram item has a job, and the mock's list of Bot API calls answers 200 with no call. It prints
# no token value.
check_telegram_off() {
  check_session "$1: Telegram is off: both rows 0, the mark off, no job, no Bot API call" OCUTALON \
    "CHK|rows|0|0
CHK|mark|1|off
CHK|tokenset|$2
CHK|jobs|0
CHK|calls|200|0" \
    'Set pf="OcuTalon.Production||",sf="||*||Enabled"' \
    'Write !,"CHK|rows|",##class(Ens.Config.DefaultSettings).%OpenId(pf_"TelegramIn"_sf).SettingValue,"|",##class(Ens.Config.DefaultSettings).%OpenId(pf_"TelegramOut"_sf).SettingValue' \
    'Write !,"CHK|mark|",($Length(##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK))>0),"|",##class(OcuTalon.Data.StatusMark).TelegramState()' \
    'Write !,"CHK|tokenset|",##class(OcuTalon.Install.Step.Telegram).TokenSet()' \
    'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Set sc=rs.Execute(),nj=0 While rs.Next() { If (rs.Get("ConfigName")="TelegramIn")||(rs.Get("ConfigName")="TelegramOut") { Set nj=nj+1 } }' \
    'Write !,"CHK|jobs|",nj' \
    'Set rq=##class(%Net.HttpRequest).%New(),rq.Server="mock",rq.Port=8080,rq.Timeout=10 Set sc=rq.Get("/_mock/telegram/calls")' \
    'Write !,"CHK|calls|",rq.HttpResponse.StatusCode,"|",{}.%FromJSON(rq.HttpResponse.Data).calls.%Size()' \
    'Halt'
}

# check_token_empty <label>: the iris container's TELEGRAM_BOT_TOKEN is set and empty. Prints no value.
check_token_empty() {
  # shellcheck disable=SC2016 # the script is the container shell's, which expands its own variables
  if dc exec -T iris sh -c '[ -n "${TELEGRAM_BOT_TOKEN+x}" ] && [ -z "$TELEGRAM_BOT_TOKEN" ]' >/dev/null 2>&1; then
    pass "$1: TELEGRAM_BOT_TOKEN is set and empty in the container"
  else
    fail "$1: TELEGRAM_BOT_TOKEN is not set and empty in the container"
  fi
}

# restart_snapshot <session ref>: the epoch, the chat and the rail that Web.Api.StateBody builds for the session, as one line of
# JSON ("" when the session or the body is missing).
restart_snapshot() {
  printf '%s\n' \
    "Set row=##class(OcuTalon.Data.Session).RefIndexOpen(\"$1\")" \
    'Set b=##class(OcuTalon.Web.Api).StateBody(row)' \
    'Write !,"CHK|snapshot|",{"epoch":(b.epoch),"chat":(b.chat),"rail":(b.rail)}.%ToJSON()' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|snapshot|//p'
}

# --- the first start, without the variable ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"
check_start "first start"
check_no_key "first start"
check_clean_start "first start"
check_eval "first start, no variable" 0
check_telegram_off "first start" 1

# --- row 19: OCUTALON_EVAL=1, then without it ---

# The Telegram seam at 1 and the mark on, as an earlier start of a release that includes Telegram would leave them, and then a
# start with no bot token: the step must switch Telegram off and record it.
check_session "row 19: the Telegram seam is 1 and the mark is on before the start with no token" OCUTALON \
  "CHK|prepared|on|ocutalon_ci_bot" \
  'Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)' \
  'Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on","ocutalon_ci_bot")' \
  'Write !,"CHK|prepared|",##class(OcuTalon.Data.StatusMark).TelegramState(.bot),"|",bot' \
  'Halt'
live_no_bot_token
if ! OCUTALON_EVAL=1 dc up -d >/dev/null 2>&1; then
  die "row 19 recreate with OCUTALON_EVAL=1 failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 19 the start with OCUTALON_EVAL=1 did not end ready within 200 s"
fi
check_start "row 19, OCUTALON_EVAL=1"
check_eval "row 19, OCUTALON_EVAL=1" 1
check_token_empty "row 19, no token"
check_no_key "row 19, no token"
check_items_run "row 19, no token"
check_telegram_off "row 19, no token" 0

check_session "row 19: the Telegram seam is back to 0 and the mark is on before the start with the dummy token" OCUTALON \
  "CHK|seam|1
CHK|mark|on" \
  'Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(0)' \
  'Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on","ocutalon_ci_bot")' \
  'Write !,"CHK|seam|",(##class(OcuTalon.Channel.Telegram.In).Included()=0)' \
  'Write !,"CHK|mark|",##class(OcuTalon.Data.StatusMark).TelegramState()' \
  'Halt'
live_pop_file
if ! dc up -d >/dev/null 2>&1; then
  die "row 19 recreate without OCUTALON_EVAL failed"
fi
cid=$(dc ps -q iris)
if ! wait_started_ready 200; then
  start_log | tail -n 20 | cut -c1-200
  die "row 19 the start without OCUTALON_EVAL did not end ready within 200 s"
fi
check_start "row 19, no variable"
check_eval "row 19, no variable" 0
check_telegram_off "row 19, no variable" 1

# --- row 20: an unclean stop ---

check_session "row 20: before the kill no production is suspended" OCUTALON \
  "CHK|suspended|" \
  'Write !,"CHK|suspended|",$Get(^Ens.Suspended)' \
  'Halt'
seeded=$(printf '%s\n' \
  'Set F="OcuTalon.Test.Data.Fixture"' \
  'Set s=$ClassMethod(F,"Session","ZzRestartSnapshot")' \
  'Write !,"CHK|session|",s' \
  'Write !,"CHK|refs|",$ClassMethod(F,"Turn",s),",",$ClassMethod(F,"Check",s),",",$ClassMethod("OcuTalon.Test.Schedule.ReminderFixture","Set",s,"zz restart snapshot",86400).ref,",",$ClassMethod(F,"Approval",s)' \
  'Halt' | iris_script OCUTALON)
snapshot_session=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|session|//p')
snapshot_refs=$(printf '%s\n' "$seeded" | sed -n 's/^CHK|refs|//p')
snapshot_before=""
if [ -n "$snapshot_session" ] && [ "$(printf '%s' "$snapshot_refs" | tr ',' '\n' | grep -c .)" = 4 ]; then
  snapshot_before=$(restart_snapshot "$snapshot_session")
  pass "row 20: a session with a turn, a check, a pending reminder and a pending approval is seeded"
else
  fail "row 20: the snapshot's fixture rows could not be seeded ('$seeded')"
fi
seeded_turns=$(printf '%s\n' \
  'Set F="OcuTalon.Test.Data.Fixture"' \
  'Set s=$ClassMethod(F,"Session","ZzRestartTurns")' \
  'Write !,"CHK|session|",s' \
  'Write !,"CHK|refs|",$ClassMethod(F,"Turn",s,"2030-01-01T10:00:01Z","running","zz restart one","zzrestartone",1),",",$ClassMethod(F,"Turn",s,"2030-01-01T10:00:02Z","queued","zz restart two","zzrestarttwo")' \
  'Halt' | iris_script OCUTALON)
turns_session=$(printf '%s\n' "$seeded_turns" | sed -n 's/^CHK|session|//p')
turns_refs=$(printf '%s\n' "$seeded_turns" | sed -n 's/^CHK|refs|//p')
if [ -n "$turns_session" ] && [ "$(printf '%s' "$turns_refs" | tr ',' '\n' | grep -c .)" = 2 ]; then
  pass "row 20: a session with a turn left running and a queued turn is seeded"
else
  fail "row 20: the turn queue's fixture rows could not be seeded ('$seeded_turns')"
fi
check_session "row 20: journaling is enabled and the journal is synced to disk before the kill" OCUTALON \
  "CHK|journal|1" \
  'Try { Set state=##class(%SYS.Journal.System).GetState() Do ##class(%SYS.Journal.System).Sync() Write !,"CHK|journal|",(state=0) } Catch e { Write !,"CHK|journal|0" }' \
  'Halt'
killed_start=$(started_at)
docker kill -s KILL "$cid" >/dev/null 2>&1 || die "row 20 the kill failed"
dc start iris >/dev/null 2>&1
cid=$(dc ps -q iris)
if ! wait_started_ready 300; then
  start_log | tail -n 30 | cut -c1-200
  die "row 20 the start after the kill did not end ready within 300 s"
fi
if [ "$(started_at)" != "$killed_start" ]; then
  pass "row 20: the container was killed and started again, and the start ended ready"
else
  fail "row 20: the container did not start again after the kill"
fi
check_start "row 20"
check_session "row 20: the step recovered the Troubled production, and did not clean it" OCUTALON \
  "CHK|suspended|OcuTalon.Production" \
  'Write !,"CHK|suspended|",$Get(^Ens.Suspended)' \
  'Halt'
check_session "row 20: the production is Running again" OCUTALON \
  "CHK|state|OcuTalon.Production|1" \
  'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"CHK|state|",n,"|",s' \
  'Halt'
check_items_run "row 20"

snapshot_after=""
if [ -n "$snapshot_session" ]; then
  snapshot_after=$(restart_snapshot "$snapshot_session")
fi
snapshot_whole=1
for ref in $(printf '%s' "$snapshot_refs" | tr ',' ' '); do
  case $snapshot_before in *"$ref"*) ;; *) snapshot_whole=0 ;; esac
done
if [ -n "$snapshot_before" ] && [ "$snapshot_whole" = 1 ] && [ "$snapshot_before" = "$snapshot_after" ]; then
  pass "row 20: the snapshot's epoch, chat and rail are identical after the kill, and hold the turn, the check, the reminder and the approval"
else
  printf '%s\n' "  before: $(printf '%s' "$snapshot_before" | cut -c1-300)" "  after:  $(printf '%s' "$snapshot_after" | cut -c1-300)"
  fail "row 20: the snapshot's epoch, chat and rail differ after the kill, or miss a fixture row"
fi
# turns_state <running turn ref> <queued turn ref>: the states of the two turns, as running|queued ('-' for a missing row).
turns_state() {
  printf '%s\n' \
    "Set r=##class(OcuTalon.Data.Turn).RefIndexOpen(\"$1\"),q=##class(OcuTalon.Data.Turn).RefIndexOpen(\"$2\")" \
    'Write !,"CHK|states|",$Select($IsObject(r):r.State,1:"-"),"|",$Select($IsObject(q):q.State,1:"-")' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|states|//p'
}
# turns_published <session> <turn ref> <turn ref>: 1 when the session's stream holds a done chat.message for each of the two
# turns (Conversation publishes it after it saves the row, so a done row alone is not yet the signal).
turns_published() {
  printf '%s\n' \
    "Set e=##class(OcuTalon.Live.Event).Since(\"$1\",0,100,\"session\"),i=e.%GetIterator(),n1=0,n2=0" \
    "While i.%GetNext(,.x) { If x.payload.state=\"done\" { Set:x.payload.ref=\"$2\" n1=n1+1 Set:x.payload.ref=\"$3\" n2=n2+1 } }" \
    'Write !,"CHK|published|",((n1>0)&&(n2>0))' \
    'Halt' | iris_script OCUTALON | sed -n 's/^CHK|published|//p'
}
turn_one=${turns_refs%%,*}
turn_two=${turns_refs##*,}
turns_done() { [ "$(turns_state "$turn_one" "$turn_two")" = "done|done" ] && [ "$(turns_published "$turns_session" "$turn_one" "$turn_two")" = 1 ]; }
if [ -n "$turns_session" ] && wait_until 60 turns_done; then
  pass "row 20: the turn left running and the queued turn are both done and published within 60 s of the start"
else
  fail "row 20: the turns of the queue were not both done and published within 60 s ('$(turns_state "$turn_one" "$turn_two")', published '$(turns_published "$turns_session" "$turn_one" "$turn_two")')"
fi
check_session "row 20: both turns have the no_key fallback reply and their decisions, the first on its second attempt, with one done event each, in order" OCUTALON \
  "CHK|turns|done|2|conversation.turnFallback|no_key|done|1|conversation.turnFallback|no_key
CHK|refs|1|1|1|1|tellnow|1|no_key|tellnow|1|no_key
CHK|events|1|1|1" \
  "Set b=\"$turns_session\",r1=\"$turn_one\",r2=\"$turn_two\"" \
  'Set t1=##class(OcuTalon.Data.Turn).RefIndexOpen(r1),t2=##class(OcuTalon.Data.Turn).RefIndexOpen(r2)' \
  'Write !,"CHK|turns|",t1.State,"|",t1.Attempt,"|",t1.ReplyCatalogKey,"|",t1.FallbackReason,"|",t2.State,"|",t2.Attempt,"|",t2.ReplyCatalogKey,"|",t2.FallbackReason' \
  'Set d1=##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(t1.TriageDecisionRef),d2=##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(t2.TurnDecisionRef)' \
  'Write !,"CHK|refs|",($Length(t1.TriageDecisionRef)>0),"|",($Length(t1.TurnDecisionRef)>0),"|",($Length(t2.TriageDecisionRef)>0),"|",($Length(t2.TurnDecisionRef)>0),"|",d1.Outcome,"|",d1.Fallback,"|",d1.FallbackReason,"|",d2.Outcome,"|",d2.Fallback,"|",d2.FallbackReason' \
  'Set e=##class(OcuTalon.Live.Event).Since(b,0,100,"session"),i=e.%GetIterator(),n1=0,n2=0,s1=0,s2=0' \
  'While i.%GetNext(,.x) { If x.payload.state="done" { If x.payload.ref=t1.Ref { Set n1=n1+1,s1=x.seq } If x.payload.ref=t2.Ref { Set n2=n2+1,s2=x.seq } } }' \
  'Write !,"CHK|events|",n1,"|",n2,"|",(s1<s2)' \
  'Halt'
check_session "row 20: the snapshot's fixture rows are removed" OCUTALON \
  "CHK|left|0" \
  'Do ##class(OcuTalon.Test.Data.Fixture).Clean()' \
  'Write !,"CHK|left|",$Data(^OcuTalonTest("Fixture"))' \
  'Halt'

if [ "$fails" -ne 0 ]; then
  echo "test-production-restart: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-production-restart: all checks passed"
