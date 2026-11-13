#!/usr/bin/env bash
# Live unit of the online demo's per-session documents and memories (Story 19.5; AD-3, AD-4, AD-21, AD-25; FR-14, FR-15, FR-41, FR-42, DW-892): builds the image
# and starts it in one throwaway compose project with the online-demo flag on and the test start values of docker/tests/lib-online.sh (a copy of the start of
# test-online-session.sh, because lib-live.sh and lib-online.sh are shared), and drives the REAL routes over HTTP with two cookie jars, K and C, the way two
# visitors do, so that CommandsIn, DocumentOps, the Embedder worker, MemoryOps, the per-turn knowledge base and SessionOps are all real. Curl only, no browser.
#   1. fresh: before any visitor (the state the host's golden copy is captured from) OcuTalon.Test.Docs.SessionLive Facts("") is 0|0|0|0|0: no session table,
#      class or global, no Document row and no memory;
#   2. K and C sign in; each POSTs a Markdown runbook to /v1/documents (K "Results runbook.md", C "Partner runbook.md", the same text apart from its name) and the
#      document is ready within 120 s (DW-892: the demo route answers 200, not 501); each GET /v1/documents lists only its own document;
#   3. each saves the same memory through the chat (the mock's memory-save), the AI sessions the turns saved are dropped so that the mock reads the next marker;
#   4. K and C send a documents-runbook turn at the same moment (two background curls, both awaited) and then a memory-recall-meaning turn at the same moment: the
#      tool results the mock's log shows the model for each turn hold only that visitor's own document source and own memory Ref;
#   5. K signs out (POST /v1/session/end answers 204) while C stays: OcuTalon.Test.Docs.SessionLive (TestSignedOut, TestStayed) finds K's tables, classes,
#      globals, Document rows and memories gone and C's intact, the whole stack holding only C's, a second OcuTalon.Docs.DropSession and Memory.DropSession OK
#      and a turn for K making nothing; C's list still shows its document ready and C's next documents-runbook turn still reads only C's document.
# Prints one PASS or FAIL line per check and one SESSION-DATA line with the seconds; exits 0 only when all pass. The project is unique, publishes its web port only
# on 127.0.0.1 and receives no keys. An EXIT trap removes the project with its volume and images. Every wait ends by the overall deadline (OCUTALON_LIVE_DEADLINE,
# 900 s by default here). Needs docker compose, the build 154 base image (IRIS_IMAGE), curl, node, base64 and the built web bundle.
set -u

: "${OCUTALON_LIVE_DEADLINE:=900}"
export OCUTALON_LIVE_DEADLINE
. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start session-data
live_web_port || exit 1

root=$(cd "$(dirname "$0")/../.." && pwd)
base="http://127.0.0.1:$web_port"
started=$SECONDS
online_values
online_override

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log" | redact
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200 | redact
  die "the first start did not end ready within $LIVE_FIRST_START_WAIT s"
fi
pass "the first start ended ready"

# --- helpers ---

LIVE_CLASS=OcuTalon.Test.Docs.SessionLive

# api <jar> <method> <path> [<body file> [<out file>]]: prints the status; the body is in the out file ($tmp/api.body by default). A GET carries a unique probe.
api() {
  local jar=$1 method=$2 path=$3 file=${4:-} out=${5:-$tmp/api.body}
  if [ "$method" = GET ]; then
    next_probe
    path="$path?probe=$probes"
  fi
  if [ -n "$file" ]; then
    curl -s --max-time 120 -b "$jar" -c "$jar" -o "$out" -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" --data-binary "@$file" "$base/ocutalon/api/v1/$path"
  else
    curl -s --max-time 120 -b "$jar" -c "$jar" -o "$out" -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" "$base/ocutalon/api/v1/$path"
  fi
}

# state_epoch <jar>: the epoch of the jar's /state ("" when it does not answer 200).
state_epoch() {
  local code
  code=$(api "$1" GET state "" "$tmp/state.body")
  if [ "$code" = 200 ]; then node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).epoch||"")}catch(e){console.log("")}' "$tmp/state.body"; fi
}

# session_ids <epoch>: "<Session row id>|<Ref>" of the Session row of the epoch.
session_ids() {
  printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT ID, Ref FROM OcuTalon_Data.Session WHERE Epoch = ?\",\"$1\") If rs.%Next() { Write !,\"CHK|ids|\",rs.%Get(\"ID\"),\"|\",rs.%Get(\"Ref\") }" 'Halt' | session_value OCUTALON ids
}

# facts [<sessionRef> [<id>]]: SessionLive Facts, "tables|classes|globals|documents|memories".
facts() {
  printf '%s\n' "Write !,\"CHK|facts|\",##class($LIVE_CLASS).Facts(\"${1:-}\",\"${2:-}\")" 'Halt' | session_value OCUTALON facts
}

# upload_body <name> <file>: writes $tmp/upload.json, {"name": <name>, "content": <the file's bytes in base64>}.
upload_body() {
  { printf '{"name":"%s","content":"' "$1"; base64 < "$2" | tr -d '\n'; printf '"}'; } > "$tmp/upload.json"
}

# doc_listing <jar>: "<ref>:<state>" of each document of the jar's GET /v1/documents, comma-separated.
doc_listing() {
  api "$1" GET documents "" "$tmp/docs.body" > /dev/null
  node -e 'try{console.log((JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).documents||[]).map(d=>d.ref+":"+d.state).join(","))}catch(e){console.log("error")}' "$tmp/docs.body"
}

# doc_ready <jar> <ref>: succeeds when the jar's list shows the document ready (for wait_until).
doc_ready() { [ "$(doc_listing "$1")" = "$2:ready" ]; }

# chat_state <jar> <clientId>: the state of the chat turn of /state with that clientId ("" when it is not listed).
chat_state() {
  api "$1" GET state "" "$tmp/chat.$2.body" > /dev/null
  node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const m=(j.chat||[]).find(i=>i.type==="chat.message"&&i.payload.clientId===process.argv[2]);console.log(m?m.payload.state:"")}catch(e){console.log("")}' "$tmp/chat.$2.body" "$2"
}

# turn_done <jar> <clientId>: succeeds when that turn is done (for wait_until).
turn_done() { [ "$(chat_state "$1" "$2")" = done ]; }

# post_turn <jar> <clientId> <text>: posts the message; prints the status (202).
post_turn() {
  printf '{"clientId":"%s","text":"%s","fromGuide":false}' "$2" "$3" > "$tmp/message.$2.json"
  api "$1" POST messages "$tmp/message.$2.json" "$tmp/post.$2.body"
}

# mock_mark: the mock log's mark (Test.Contract.Mock LogMark).
mock_mark() {
  printf '%s\n' 'Write !,"CHK|mark|",##class(OcuTalon.Test.Contract.Mock).LogMark()' 'Halt' | session_value OCUTALON mark
}

# seen <mark> <needle>: SessionLive Seen, "<sources>|<memory refs>" that the model was given in the turns that carry the needle.
seen() {
  printf '%s\n' "Write !,\"CHK|seen|\",##class($LIVE_CLASS).Seen($1,\"$2\")" 'Halt' | session_value OCUTALON seen
}

# session_mark / drop_sessions <mark> <session ref>...: the mark of the saved AI sessions, and the removal of the sessions saved after it (RunnerFixture) and of the
# turns of the named sessions with what the product made for them (ReminderFixture RemoveTurns), so that the next turn starts a conversation of its own: the mock
# reads the first [[mock:...]] marker of the history it is sent, and a fresh turn is seeded with the earlier ones. Prints 1 on success.
session_mark() {
  printf '%s\n' 'Write !,"CHK|smark|",##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()' 'Halt' | session_value OCUTALON smark
}
drop_sessions() {
  local mark=$1 ref lines=()
  case "$mark" in
    '' | *[!0-9]*) return 1 ;;
  esac
  shift
  for ref in "$@"; do lines+=("Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(\"$ref\")"); done
  printf '%s\n' ${lines[@]+"${lines[@]}"} "Write !,\"CHK|dropped|\",\$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince($mark))" 'Halt' | session_value OCUTALON dropped
}

# run_class <class> <chk file>: runs the test class in the stack through the %UnitTest.Manager as ci/iris.sh does, and keeps the CHK lines.
run_class() {
  printf '%s\n' \
    'Set ^UnitTestRoot="/tmp/"' \
    'Set before=$Order(^UnitTest.Result(""),-1)' \
    'Do ##class(%UnitTest.Manager).RunTest(":'"$1"'","/noload/nodelete/norecursive")' \
    'Set id=$Order(^UnitTest.Result(""),-1) Set inst="" If id>before Set inst=##class(%UnitTest.Result.TestInstance).%OpenId(id)' \
    'Write !,"CHK|new|",$IsObject(inst)' \
    'If $IsObject(inst) { Set k1="" For { Set su=inst.TestSuites.GetNext(.k1) Quit:k1=""  Set k2="" For { Set tc=su.TestCases.GetNext(.k2) Quit:k2=""  Write !,"CHK|case|",tc.Name,"|",tc.Status,"|",tc.TestMethods.Count()  Write:(tc.Status=0)&&(tc.ErrorDescription'"'"'="") !,"CHK|error|",tc.Name,"|",$Translate(tc.ErrorDescription,$Char(13,10),"  ")  Set k3="" For { Set tm=tc.TestMethods.GetNext(.k3) Quit:k3=""  Write:(tm.Status=0)&&(tm.ErrorDescription'"'"'="") !,"CHK|error|",tm.Name,"|",$Translate(tm.ErrorDescription,$Char(13,10),"  ")  Set k4="" For { Set ta=tm.TestAsserts.GetNext(.k4) Quit:k4=""  Write:ta.Status'"'"'=1 !,"CHK|assert|",ta.Status,"|",tm.Name,"|",$Translate(ta.Description,$Char(13,10),"  ") } } } } }' \
    'Halt' | iris_script OCUTALON > "$2"
}

# check_live <chk file> <what>: passes when the class ran, had test methods, failed no assertion, threw nothing and skipped none.
check_live() {
  local status methods skipped failed
  status=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\2/p' "$1" | head -n 1)
  methods=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\3/p' "$1" | head -n 1)
  skipped=$(grep -c '^CHK|assert|2|' "$1")
  failed=$(grep -c '^CHK|assert|0|\|^CHK|error|' "$1")
  if [ "$status" = 1 ] && [ "${methods:-0}" -gt 0 ] && [ "$failed" = 0 ] && [ "$skipped" = 0 ]; then
    pass "OcuTalon.Test.Docs.SessionLive passed $2 ($methods test methods)"
  else
    sed -n 's/^CHK|\(assert\|error\)|/  /p' "$1" | cut -c1-300
    fail "OcuTalon.Test.Docs.SessionLive did not pass $2 (status '$status', $methods methods, $failed failed, $skipped skipped)"
  fi
}

# --- step 1: fresh, before any visitor ---

if [ "$(facts)" = '0|0|0|0|0' ]; then
  pass "fresh: no session table, class or global, no Document row and no memory before any visitor"
else
  fail "fresh: the stack holds '$(facts)' (tables|classes|globals|documents|memories) before any visitor, wanted 0|0|0|0|0"
fi
if [ "$(keys_point)" = 1 ]; then
  pass "the runners' keys point at the CI mock"
else
  die "the runners' keys could not be pointed at the CI mock"
fi

# --- step 2: K and C sign in and add a runbook each ---

jar_k="$tmp/jar.k"
jar_c="$tmp/jar.c"
: > "$jar_k"
: > "$jar_c"
online_signin "$jar_k" "" "" > /dev/null
online_signin "$jar_c" "" "" > /dev/null
epoch_k=$(state_epoch "$jar_k")
epoch_c=$(state_epoch "$jar_c")
if [ -z "$epoch_k" ] || [ -z "$epoch_c" ] || [ "$epoch_k" = "$epoch_c" ]; then
  die "K and C did not sign in to two sessions (epochs '$epoch_k' and '$epoch_c')"
fi
ids_k=$(session_ids "$epoch_k")
ids_c=$(session_ids "$epoch_c")
id_k=${ids_k%%|*}
ref_k=${ids_k#*|}
id_c=${ids_c%%|*}
ref_c=${ids_c#*|}
if [ -n "$id_k" ] && [ -n "$id_c" ] && [ "$id_k" != "$id_c" ] && [ -n "$ref_k" ] && [ -n "$ref_c" ]; then
  pass "K and C are two visitors with their own Session rows ($id_k and $id_c)"
else
  die "the Session rows of K and C could not be read ('$ids_k' and '$ids_c')"
fi

cat > "$tmp/runbook.md" << 'EOF'
# Results runbook

This runbook covers the Results production, the lab results feed that the clinic reads every morning.

## Rotating the certificate

1. Stop the item named Results.Sender.
2. Install the new certificate in the SSL configuration named ResultsClient, then restart the item.
3. Send one test result and write the new expiry date in the on-call log.

## Clearing the queue

When the Results queue keeps growing, read why the message at its head fails, fix the cause and resend it.
EOF
doc_refs=""
for who in k c; do
  eval "jar=\$jar_$who"
  if [ "$who" = k ]; then name="Results runbook.md"; else name="Partner runbook.md"; fi
  upload_body "$name" "$tmp/runbook.md"
  code=$(api "$jar" POST documents "$tmp/upload.json")
  ref=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).ref||"")}catch(e){console.log("")}' "$tmp/api.body")
  if [ "$code" = 200 ] && [ -n "$ref" ]; then
    pass "$who: POST /v1/documents answers 200 with a ref (DW-892: the online demo reaches the route's owner)"
  else
    head -c 300 "$tmp/api.body"
    die "$who: POST /v1/documents answered '$code' for '$name'"
  fi
  eval "doc_$who=\$ref"
  begun=$SECONDS
  if wait_until 120 doc_ready "$jar" "$ref"; then
    pass "$who: the document is ready after $((SECONDS - begun)) s, and the list shows it alone"
  else
    die "$who: the list reads '$(doc_listing "$jar")' 120 s after the add, wanted $ref:ready"
  fi
done
if [ "$doc_k" != "$doc_c" ]; then pass "each visitor's document has a Ref of its own"; else fail "K and C share the document Ref $doc_k"; fi
f=$(facts)
if [ "$(printf '%s' "$f" | cut -d'|' -f1,2)" = '4|4' ] && [ "$(printf '%s' "$f" | cut -d'|' -f3)" -ge 4 ] 2> /dev/null && [ "$(printf '%s' "$f" | cut -d'|' -f4,5)" = '2|0' ]; then
  pass "each visitor's first document made its own two tables with their classes and globals (OcuTalonKB.S$id_k and OcuTalonKB.S$id_c)"
else
  fail "the tables of the two visitors read '$f' (tables|classes|globals|documents|memories), wanted 4|4|<4 or more>|2|0"
fi

# --- step 3: each saves the same memory through the chat ---

mark_ai=$(session_mark)
for who in k c; do
  eval "jar=\$jar_$who"
  code=$(post_turn "$jar" "zzsd-$who-save" "Remember that the Results partner's contact is Lee. [[mock:memory-save]] zzsd-$who-save")
  if [ "$code" = 202 ] && wait_until 120 turn_done "$jar" "zzsd-$who-save"; then
    pass "$who: the memory-save turn is done"
  else
    fail "$who: the memory-save turn answered '$code' and its state is '$(chat_state "$jar" "zzsd-$who-save")'"
  fi
done
[ "$(drop_sessions "$mark_ai" "$ref_k" "$ref_c")" = 1 ] || fail "the AI sessions of the save turns could not be dropped (mark '$mark_ai')"
if [ "$(facts | cut -d'|' -f5)" = 2 ]; then
  pass "each visitor saved a memory (two rows)"
else
  fail "the memories read '$(facts)', wanted two"
fi

# --- step 4: the two visitors ask at the same moment ---

# concurrent <marker> <suffix>: K and C post the marker's turn at the same moment (two background curls, both awaited) and both turns end done.
concurrent() {
  local marker=$1 suffix=$2 who jar pids="" code
  for who in k c; do
    eval "jar=\$jar_$who"
    (
      code=$(post_turn "$jar" "zzsd-$who-$suffix" "How do I rotate the Results certificate? [[mock:$marker]] zzsd-$who-$suffix")
      echo "$code" > "$tmp/code.$who.$suffix"
    ) &
    pids="$pids $!"
  done
  wait $pids
  for who in k c; do
    eval "jar=\$jar_$who"
    code=$(cat "$tmp/code.$who.$suffix" 2> /dev/null)
    if [ "$code" = 202 ] && wait_until 150 turn_done "$jar" "zzsd-$who-$suffix"; then
      pass "$who: the $marker turn is done"
    else
      fail "$who: the $marker turn answered '$code' and its state is '$(chat_state "$jar" "zzsd-$who-$suffix")'"
    fi
  done
}

mark_log=$(mock_mark)
mark_ai=$(session_mark)
concurrent documents-runbook docs
seen_k=$(seen "$mark_log" zzsd-k-docs)
seen_c=$(seen "$mark_log" zzsd-c-docs)
if [ "$seen_k" = "$doc_k|" ]; then pass "K's documents turn: the tool results hold only K's own document source"; else fail "K's documents turn gave the model '$seen_k', wanted '$doc_k|'"; fi
if [ "$seen_c" = "$doc_c|" ]; then pass "C's documents turn: the tool results hold only C's own document source"; else fail "C's documents turn gave the model '$seen_c', wanted '$doc_c|'"; fi
[ "$(drop_sessions "$mark_ai" "$ref_k" "$ref_c")" = 1 ] || fail "the AI sessions of the documents turns could not be dropped"
mark_log=$(mock_mark)
mark_ai=$(session_mark)
concurrent memory-recall-meaning mem
seen_k=$(seen "$mark_log" zzsd-k-mem)
seen_c=$(seen "$mark_log" zzsd-c-mem)
mem_k=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ?\",\"$ref_k\") If rs.%Next() { Write !,\"CHK|mem|\",rs.%Get(\"Ref\") }" 'Halt' | session_value OCUTALON mem)
mem_c=$(printf '%s\n' "Set rs=##class(%SQL.Statement).%ExecDirect(,\"SELECT Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ?\",\"$ref_c\") If rs.%Next() { Write !,\"CHK|mem|\",rs.%Get(\"Ref\") }" 'Halt' | session_value OCUTALON mem)
if [ -n "$mem_k" ] && [ "$seen_k" = "|$mem_k" ]; then pass "K's memory turn: the tool results hold only K's own memory"; else fail "K's memory turn gave the model '$seen_k', wanted '|$mem_k'"; fi
if [ -n "$mem_c" ] && [ "$seen_c" = "|$mem_c" ]; then pass "C's memory turn: the tool results hold only C's own memory"; else fail "C's memory turn gave the model '$seen_c', wanted '|$mem_c'"; fi
[ "$(drop_sessions "$mark_ai" "$ref_k" "$ref_c")" = 1 ] || fail "the AI sessions of the memory turns could not be dropped"
if [ "$(facts | cut -d'|' -f5)" = 2 ]; then
  pass "the turns saved no further memory: two rows"
else
  fail "the memories read '$(facts)' after the turns, wanted two"
fi

# --- step 5: K signs out while C stays ---

before=$(facts)
code=$(api "$jar_k" POST session/end "")
if [ "$code" = 204 ]; then
  pass "K's POST /v1/session/end answers 204 (the route's success)"
else
  fail "K's POST /v1/session/end answered '$code' (the work before it: $before)"
fi
printf '%s\n' "Kill ^OcuTalonTest(\"Docs\") Set ^OcuTalonTest(\"Docs\",\"sessions\")=\"$ref_k|$ref_c|$id_k|$id_c\"" 'Write !,"CHK|marked"' 'Halt' | iris_script OCUTALON > /dev/null
run_class "$LIVE_CLASS" "$tmp/live.chk"
check_live "$tmp/live.chk" "after K's sign-out: K's data is gone, C's is intact, and a second drop and a turn for K change nothing"
printf '%s\n' 'Kill ^OcuTalonTest("Docs")' 'Write !,"CHK|marked"' 'Halt' | iris_script OCUTALON > /dev/null
if [ "$(doc_listing "$jar_c")" = "$doc_c:ready" ]; then
  pass "C's list still shows its document ready"
else
  fail "C's list reads '$(doc_listing "$jar_c")' after K signed out"
fi
mark_log=$(mock_mark)
mark_ai=$(session_mark)
code=$(post_turn "$jar_c" zzsd-c-after "How do I rotate the Results certificate? [[mock:documents-runbook]] zzsd-c-after")
if [ "$code" = 202 ] && wait_until 150 turn_done "$jar_c" zzsd-c-after; then
  seen_c=$(seen "$mark_log" zzsd-c-after)
  if [ "$seen_c" = "$doc_c|" ]; then pass "after K's sign-out C's documents turn still reads only C's document"; else fail "C's documents turn after the sign-out gave the model '$seen_c', wanted '$doc_c|'"; fi
else
  fail "C's turn after the sign-out answered '$code' and is '$(chat_state "$jar_c" zzsd-c-after)'"
fi
[ "$(drop_sessions "$mark_ai" "$ref_c")" = 1 ] || fail "the AI sessions of C's last turn could not be dropped"
if [ "$(keys_restore)" = 1 ]; then
  pass "the runners' keys are put back"
else
  fail "the runners' keys could not be put back"
fi
logout_all "$jar_c" /ocutalon/ > /dev/null 2>&1

echo "SESSION-DATA $((SECONDS - started)) s"
if [ "$fails" -eq 0 ]; then
  echo "SESSION-DATA ok"
  echo "test-session-data: all checks passed"
  exit 0
fi
echo "test-session-data: $fails check(s) failed (project $P)"
exit 1
