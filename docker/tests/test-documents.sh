#!/usr/bin/env bash
# Live unit of the documents (Stories 19.4 and 19.7; AD-1, AD-5, AD-21, AD-23, DW-739): builds the image and starts it in one throwaway compose project, signs the README
# account in, and drives the REAL routes /v1/documents over HTTP, the way the page does, so that CommandsIn, DocumentOps, the Embedder worker and OcuTalonKB.Docs
# are all real (no double, no page.route):
#   1. the texts that Story 19.4's rulings fix are in the files that ship them (docs/bridge-guide.md, docs/security-overview.md), and the texts that DW-719's
#      owner ruling fixes (Story 19.7: two lines of EXPERIENCE.md), word for word;
#   2. POST /v1/documents with a Markdown runbook ({name, content} with the bytes in base64) answers 200 {"result":"done","ref"}; the list shows the document
#      ready within 120 s; OcuTalon.Test.Docs.Live (TestFound) finds its passages, with their document and section, in OcuTalonKB.Docs, and a search through AI Hub's
#      knowledge base returns the passage of the certificate first with a score over the floor;
#   2b. the chat, through the real POST /v1/messages and the CI mock (the runners' keys pointed at it, then put back): a question the runbook covers is
#      answered; a covered search whose reply also says "None of your documents cover that." leaves with the sentence taken out (citations exist, DW-720 b);
#      an unrelated question gets the sentence as it is (no citation, DW-720 a); a reply that is only the sentence while citations exist never reaches the chat;
#   3. the iris container restarts (AD-5): after the restart the list still shows the document ready and TestFound passes again;
#   4. a 10,485,760-byte .pdf (made here, in the unit's temporary folder, and never kept: no PDF of that size is committed) is accepted by the real route (200, the
#      size check D8 of the page specs used to make) and ends failed with the reason wrong_type (it has no PDF signature); a .txt with a NUL ends failed with the
#      reason unreadable;
#   4b. (Story 19.7) the PDF runbook, the Word runbook and an encrypted PDF of OcuTalon.Test.Docs.Samples (printed as base64 by the stack, nothing written to
#      disk) are posted as {name, content}: each answers 200 {result: done, ref}, and the list shows ready, ready and failed with the reason encrypted;
#   5. DELETE of all six answers 200, the list is empty, and OcuTalon.Test.Docs.Live (TestGone) finds no row and no knowledge-base row of any document.
# Prints one PASS or FAIL line per check and INFO lines for the measured seconds; exits 0 only when all pass. The project is unique, publishes its web port only on
# 127.0.0.1 (first free port of 52800-52819, or OCUTALON_TEST_WEB_PORT) and receives no keys. An EXIT trap removes the project with its volume and images. Every
# wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 1200 s by default here and in CI).
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), curl, node and base64.
set -u

: "${OCUTALON_LIVE_DEADLINE:=1200}"
export OCUTALON_LIVE_DEADLINE
. "$(dirname "$0")/lib-live.sh"
live_start documents
live_web_port || exit 1

root=$(cd "$(dirname "$0")/../.." && pwd)
readme_user=ocutalon
readme_password=ocutalon
base="http://127.0.0.1:$web_port"
jar="$tmp/jar"
started=$SECONDS

# --- helpers ---

# sign_in: the README account signs in with the cookie jar (a copy of test-demo-switch.sh's helper, because lib-live.sh is shared).
sign_in() {
  : > "$jar"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "$base/ocutalon/"
  curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" -d "IRISUsername=$readme_user" -d "IRISPassword=$readme_password" --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/"
}

# api_send <method> <path> [<body file>]: prints the status code; the body is in $tmp/api.body.
api_send() {
  local method=$1 path=$2 file=${3:-}
  if [ -n "$file" ]; then
    curl -s --max-time 120 -b "$jar" -c "$jar" -o "$tmp/api.body" -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" --data-binary "@$file" "$base/ocutalon/api/v1/$path"
  else
    curl -s --max-time 120 -b "$jar" -c "$jar" -o "$tmp/api.body" -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" "$base/ocutalon/api/v1/$path"
  fi
}

# upload_body <name> <file>: writes $tmp/upload.json, {"name": <name>, "content": <the file's bytes in base64>}.
upload_body() {
  { printf '{"name":"%s","content":"' "$1"; base64 < "$2" | tr -d '\n'; printf '"}'; } > "$tmp/upload.json"
}

# upload_b64 <name> <base64>: writes $tmp/upload.json, {"name": <name>, "content": <the base64 text>}.
upload_b64() {
  printf '{"name":"%s","content":"%s"}' "$1" "$2" > "$tmp/upload.json"
}

# sample_b64 <method>: the base64 of the bytes of OcuTalon.Test.Docs.Samples:<method>(), printed by the stack (nothing is written to disk).
sample_b64() {
  printf '%s\n' "Set s=##class(OcuTalon.Test.Docs.Samples).$1() Do s.Rewind() Write !,\"CHK|b64|\",\$System.Encryption.Base64Encode(s.Read(s.Size),1)" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|b64|//p' | head -n 1 | tr -d '\r'
}

# body_field <field>: the field of $tmp/api.body, as text ("" when there is none).
body_field() {
  node -e 'let s=require("fs").readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(s);const v=j[process.argv[2]];console.log(v===undefined||v===null?"":v)}catch(e){console.log("")}' "$tmp/api.body" "$1"
}

# doc_state <ref>: "<state>|<reason>" of the document in GET /v1/documents, or "gone".
doc_state() {
  api_send GET documents > /dev/null
  node -e 'let s=require("fs").readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(s);const d=(j.documents||[]).find(x=>x.ref===process.argv[2]);console.log(d?`${d.state}|${d.reason||""}`:"gone")}catch(e){console.log("error")}' "$tmp/api.body" "$1"
}

doc_count() {
  api_send GET documents > /dev/null
  node -e 'let s=require("fs").readFileSync(process.argv[1],"utf8");try{console.log((JSON.parse(s).documents||[]).length)}catch(e){console.log("error")}' "$tmp/api.body"
}

# doc_is <ref> <state|reason>: succeeds when the document has the state and reason (for wait_until).
doc_is() { [ "$(doc_state "$1")" = "$2" ]; }

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

# check_live <chk file> <what> <skips>: passes when the class ran, had test methods, failed no assertion and threw nothing, and skipped exactly <skips> assertions
# (the test that this step does not drive; a case that skips an assertion has the status 2).
check_live() {
  local status methods skipped failed
  status=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\2/p' "$1" | head -n 1)
  methods=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\3/p' "$1" | head -n 1)
  skipped=$(grep -c '^CHK|assert|2|' "$1")
  failed=$(grep -c '^CHK|assert|0|\|^CHK|error|' "$1")
  if { [ "$status" = 1 ] || [ "$status" = 2 ]; } && [ "${methods:-0}" -gt 0 ] && [ "$failed" = 0 ] && [ "$skipped" = "$3" ]; then
    pass "OcuTalon.Test.Docs.Live passed $2 ($methods test methods, $skipped skipped)"
  else
    sed -n 's/^CHK|\(assert\|error\)|/  /p' "$1" | cut -c1-300
    fail "OcuTalon.Test.Docs.Live did not pass $2 (status '$status', $methods methods, $failed failed, $skipped skipped, wanted $3)"
  fi
}

# mark <node> <ref>: sets ^OcuTalonTest("Docs", <node>) to the ref, or kills both nodes with no ref.
mark() {
  if [ -n "${2:-}" ]; then
    printf '%s\n' 'Kill ^OcuTalonTest("Docs")' "Set ^OcuTalonTest(\"Docs\",\"$1\")=\"$2\"" 'Write !,"CHK|marked"' 'Halt' | iris_script OCUTALON > /dev/null
  else
    printf '%s\n' 'Kill ^OcuTalonTest("Docs")' 'Write !,"CHK|marked"' 'Halt' | iris_script OCUTALON > /dev/null
  fi
}

# table_rows: the number of rows of OcuTalonKB.Docs.
table_rows() {
  printf '%s\n' 'Write !,"CHK|rows|",##class(OcuTalon.Docs.Store).Count()' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|rows|//p' | head -n 1
}

# chat_reply <clientId>: "<state>|<fallbackReason>|<replyText>" of the chat turn of /state with that clientId, or "none||" when it is not listed.
chat_reply() {
  api_send GET state > /dev/null
  node -e 'let s=require("fs").readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(s);const m=(j.chat||[]).find(i=>i.type==="chat.message"&&i.payload.clientId===process.argv[2]);console.log(m?`${m.payload.state}|${m.payload.fallbackReason||""}|${m.payload.replyText||""}`:"none||")}catch(e){console.log("error||")}' "$tmp/api.body" "$1"
}

# chat_done_for <clientId>: succeeds when that turn is done (for wait_until).
chat_done_for() { [ "$(chat_reply "$1" | cut -d'|' -f1)" = done ]; }

# chat_turn <clientId> <text>: posts the message and waits up to 120 s for its reply; prints "<fallbackReason>|<replyText>" (or "no reply").
chat_turn() {
  local code
  printf '{"clientId":"%s","text":"%s","fromGuide":false}' "$1" "$2" > "$tmp/message.json"
  code=$(api_send POST messages "$tmp/message.json")
  if [ "$code" != 202 ]; then echo "POST answered $code"; return 0; fi
  if wait_until 120 chat_done_for "$1"; then
    chat_reply "$1" | cut -d'|' -f2-
  else
    echo "no reply"
  fi
}

# drop_turns <mark>: removes the README account's turns with what the product made for them (ReminderFixture.RemoveTurns), and the AI sessions that the turns
# saved after the mark (RunnerFixture.DropSince), so that the next turn starts a conversation of its own: the mock reads the first [[mock:...]] marker of the
# history it is sent. Prints 1 on success.
drop_turns() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' \
    "Set s=##class(OcuTalon.Data.Session).ForUser(\"$readme_user\",.sc)" \
    'If $IsObject(s) Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(s.Ref)' \
    "Write !,\"CHK|dropped|\",\$IsObject(s)&&\$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince($1))" 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|dropped|//p' | head -n 1
}

# runner_keys <Point|Restore>: points the runners' keys at the CI mock, or puts the placeholder back (RunnerFixture, as the page specs do); prints 1 on success.
runner_keys() {
  printf '%s\n' "Set sc=##class(OcuTalon.Test.Agent.RunnerFixture).${1}Keys()" 'Write !,"CHK|keys|",$System.Status.IsOK(sc)' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|keys|//p' | head -n 1
}

# --- step 1: the texts that the rulings fix ---

RAGSTATEMENT="One tool has no class of its own: \`documents\`, the search over your added documents that AI Hub's knowledge base gives the Chat agent. AI Hub sends no source class with its calls, so the gate classifies this one tool, and no other, by the bridge's classification setting: safe and read-only, but its output is never trusted, so a turn that searches your documents is treated as holding untrusted content. The gate also limits each search to 5 passages. Any other call that arrives without a source class stays unclassified and counts as risky."
FILTERLINE="\`Filter(text, hostData)\` returns the text to use in place of model-written text. For a chat turn, \`hostData\` is the reply's \`HostData\` JSON; otherwise it is empty. It returns the text unchanged by default."
if grep -qF -- "$RAGSTATEMENT" "$root/docs/security-overview.md" && [ "$(grep -cF -- "$RAGSTATEMENT" "$root/docs/security-overview.md")" = 1 ]; then
  pass "docs/security-overview.md holds the fallback sentence of the ruling once, word for word"
else
  fail "docs/security-overview.md does not hold the fallback sentence of the ruling exactly once"
fi
if [ "$(grep -cF -- "$FILTERLINE" "$root/docs/bridge-guide.md")" = 1 ]; then
  pass "docs/bridge-guide.md holds the Filter(text, hostData) line of the ruling once, word for word"
else
  fail "docs/bridge-guide.md does not hold the Filter(text, hostData) line of the ruling exactly once"
fi
EXPERIENCE="$root/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md"
ADDING='- **Adding:** an **Add documents** button (a file picker, with drag-and-drop as a second way), accepting Markdown, plain text, PDF and Word (.docx) files.'
OWNERSHIP='- On a local install, memories belong to each user and documents are shared by every user of the install (P23).'
if [ "$(grep -cF -- "$ADDING" "$EXPERIENCE")" = 1 ]; then
  pass "EXPERIENCE.md holds DW-719's Adding line once, word for word"
else
  fail "EXPERIENCE.md does not hold DW-719's Adding line exactly once"
fi
if [ "$(grep -cF -- "$OWNERSHIP" "$EXPERIENCE")" = 1 ]; then
  pass "EXPERIENCE.md holds DW-719's local-install ownership line once, word for word"
else
  fail "EXPERIENCE.md does not hold DW-719's local-install ownership line exactly once"
fi
tracked=$(cd "$root" && git ls-files 2> /dev/null)
if [ -z "$tracked" ]; then
  fail "git ls-files listed no file of the repository, so the size check of the tracked PDF and Word files did not run"
else
  big=$(cd "$root" && printf '%s\n' "$tracked" | grep -iE '\.(pdf|docx)$' | while read -r f; do if [ "$(wc -c < "$f")" -gt 1000000 ]; then echo "$f"; fi; done)
  if [ -z "$big" ]; then
    pass "no PDF or Word file over 1 MB is in the repository: the 10 MB .pdf of this unit is generated at test time"
  else
    fail "a large PDF or Word file is tracked: $big"
  fi
fi

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
sign_in

# --- step 2: a Markdown runbook through the real route ---

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
upload_body "Results runbook.md" "$tmp/runbook.md"
code=$(api_send POST documents "$tmp/upload.json")
ref=$(body_field ref)
if [ "$code" = 200 ] && [ "$(body_field result)" = done ] && [ -n "$ref" ]; then
  pass "POST /v1/documents answers 200 {result: done, ref} for the runbook"
else
  cat "$tmp/api.body"
  die "POST /v1/documents answered '$code' for the runbook"
fi
begun=$SECONDS
if wait_until 120 doc_is "$ref" 'ready|'; then
  pass "the list shows the runbook ready after $((SECONDS - begun)) s (CommandsIn, DocumentOps and the Embedder worker)"
else
  die "the runbook is '$(doc_state "$ref")' 120 s after the add, not ready"
fi
echo "INFO the runbook was ready $((SECONDS - begun)) s after the add"
mark live "$ref"
run_class OcuTalon.Test.Docs.Live "$tmp/live1.chk"
check_live "$tmp/live1.chk" "before the restart" 1

# --- step 2b: the chat, through the real message route against the CI mock ---

NONE_SENTENCE='None of your documents cover that.'
if [ "$(runner_keys Point)" = 1 ]; then
  pass "the runners' keys point at the CI mock"
else
  die "the runners' keys could not be pointed at the CI mock"
fi
mark_sessions=$(printf '%s\n' 'Write !,"CHK|mark|",##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|mark|//p' | head -n 1)
covered=$(chat_turn zzdocs-covered 'How do I rotate the Results certificate? [[mock:documents-runbook]]')
[ "$(drop_turns "$mark_sessions")" = 1 ] || fail "the AI sessions of the covered turn could not be dropped"
conflict=$(chat_turn zzdocs-conflict 'How do I rotate the Results certificate? [[mock:documents-none-conflict]]')
[ "$(drop_turns "$mark_sessions")" = 1 ] || fail "the AI sessions of the conflict turn could not be dropped"
unrelated=$(chat_turn zzdocs-none 'How do I reset my password? [[mock:documents-none]]')
[ "$(drop_turns "$mark_sessions")" = 1 ] || fail "the AI sessions of the unrelated turn could not be dropped"
only=$(chat_turn zzdocs-only 'How do I rotate the Results certificate? [[mock:documents-none-only]]')
if [ "$covered" = '|The CI mock answered from the Results runbook: Rotating the certificate.' ]; then
  pass "a question the runbook covers is answered in the chat: '${covered#|}'"
else
  fail "the covered question got '$covered'"
fi
if [ "$conflict" = '|Stop the sender, install the new certificate and send a test result.' ]; then
  pass "a covered search whose reply also says the sentence reaches the chat without it (citations exist)"
else
  fail "the covered search with the sentence got '$conflict', wanted the steps without '$NONE_SENTENCE'"
fi
if [ "$unrelated" = "|$NONE_SENTENCE" ]; then
  pass "an unrelated question is answered with '$NONE_SENTENCE' as it is (no citation)"
else
  fail "the unrelated question got '$unrelated', wanted '$NONE_SENTENCE'"
fi
case "$only" in
  invalid\|*"$NONE_SENTENCE"*) fail "a reply that is only the sentence, with citations, reached the chat: '$only'" ;;
  invalid\|*) pass "a reply that is only the sentence, with citations, never reaches the chat: Decide's invalid path (fallback reason 'invalid')" ;;
  *) fail "the reply that is only the sentence got '$only', wanted a fallback with the reason invalid" ;;
esac
[ "$(drop_turns "$mark_sessions")" = 1 ] || fail "the AI sessions of the turns could not be dropped (mark '$mark_sessions')"
if [ "$(runner_keys Restore)" = 1 ]; then
  pass "the runners' keys are put back"
else
  fail "the runners' keys could not be put back"
fi

# --- step 3: the container restarts (AD-5) ---

if ! docker restart "$cid" > "$tmp/restart.log" 2>&1; then
  cat "$tmp/restart.log"
  die "the iris container did not restart"
fi
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the restart did not end ready within 400 s"
fi
pass "the restart ended ready"
sign_in
if [ "$(doc_state "$ref")" = 'ready|' ]; then
  pass "after the restart the list still shows the runbook ready"
else
  fail "after the restart the runbook is '$(doc_state "$ref")'"
fi
run_class OcuTalon.Test.Docs.Live "$tmp/live2.chk"
check_live "$tmp/live2.chk" "after the restart: the passages are still there and found" 1

# --- step 4: a 10 MB PDF and an unreadable text, made here and never kept ---

head -c 10485760 /dev/zero > "$tmp/big.pdf"
upload_body "big.pdf" "$tmp/big.pdf"
rm -f "$tmp/big.pdf"
code=$(api_send POST documents "$tmp/upload.json")
pdf=$(body_field ref)
if [ "$code" = 200 ] && [ -n "$pdf" ]; then
  pass "POST /v1/documents accepts a 10,485,760-byte .pdf (200): the size check of the real route"
else
  cat "$tmp/api.body" | head -c 300
  fail "POST /v1/documents answered '$code' for the 10 MB .pdf"
fi
rm -f "$tmp/upload.json"
printf 'text\000with a NUL' > "$tmp/nul.txt"
upload_body "nul.txt" "$tmp/nul.txt"
code=$(api_send POST documents "$tmp/upload.json")
nul=$(body_field ref)
if [ "$code" = 200 ] && [ -n "$nul" ]; then
  pass "POST /v1/documents accepts a .txt with a NUL (200)"
else
  fail "POST /v1/documents answered '$code' for the .txt with a NUL"
fi
if [ -n "$pdf" ] && wait_until 120 doc_is "$pdf" 'failed|wrong_type'; then
  pass "the .pdf of zeros ends failed with the reason wrong_type (no PDF signature)"
else
  fail "the .pdf is '$(doc_state "$pdf")', not failed|wrong_type"
fi
if [ -n "$nul" ] && wait_until 120 doc_is "$nul" 'failed|unreadable'; then
  pass "the .txt with a NUL ends failed with the reason unreadable"
else
  fail "the .txt with a NUL is '$(doc_state "$nul")', not failed|unreadable"
fi
if [ "$(doc_count)" = 3 ]; then
  pass "the list holds the three documents"
else
  fail "the list holds $(doc_count) documents, wanted 3"
fi

# --- step 4b: a PDF, a Word file and an encrypted PDF through the real route (Story 19.7) ---

b64_pdf=$(sample_b64 PdfRunbook)
b64_docx=$(sample_b64 DocxRunbook)
b64_enc=$(sample_b64 PdfEncrypted)
if [ -n "$b64_pdf" ] && [ -n "$b64_docx" ] && [ -n "$b64_enc" ]; then
  pass "the stack printed the three sample files as base64"
else
  die "the stack printed no base64 for a sample file (pdf ${#b64_pdf}, docx ${#b64_docx}, encrypted ${#b64_enc} characters)"
fi
upload_b64 "Results runbook.pdf" "$b64_pdf"
code=$(api_send POST documents "$tmp/upload.json")
pdfok=$(body_field ref)
if [ "$code" = 200 ] && [ "$(body_field result)" = done ] && [ -n "$pdfok" ]; then
  pass "POST /v1/documents answers 200 {result: done, ref} for the PDF runbook"
else
  fail "POST /v1/documents answered '$code' for the PDF runbook"
fi
upload_b64 "Lab feed runbook.docx" "$b64_docx"
code=$(api_send POST documents "$tmp/upload.json")
docxok=$(body_field ref)
if [ "$code" = 200 ] && [ "$(body_field result)" = done ] && [ -n "$docxok" ]; then
  pass "POST /v1/documents answers 200 {result: done, ref} for the Word runbook"
else
  fail "POST /v1/documents answered '$code' for the Word runbook"
fi
upload_b64 "locked.pdf" "$b64_enc"
code=$(api_send POST documents "$tmp/upload.json")
encok=$(body_field ref)
if [ "$code" = 200 ] && [ "$(body_field result)" = done ] && [ -n "$encok" ]; then
  pass "POST /v1/documents answers 200 {result: done, ref} for the encrypted PDF"
else
  fail "POST /v1/documents answered '$code' for the encrypted PDF"
fi
rm -f "$tmp/upload.json"
begun=$SECONDS
if [ -n "$pdfok" ] && wait_until 120 doc_is "$pdfok" 'ready|'; then
  pass "the list shows the PDF runbook ready (extracted in the worker, indexed by page)"
else
  fail "the PDF runbook is '$(doc_state "$pdfok")', not ready"
fi
if [ -n "$docxok" ] && wait_until 120 doc_is "$docxok" 'ready|'; then
  pass "the list shows the Word runbook ready (indexed by Heading 1 section)"
else
  fail "the Word runbook is '$(doc_state "$docxok")', not ready"
fi
if [ -n "$encok" ] && wait_until 120 doc_is "$encok" 'failed|encrypted'; then
  pass "the encrypted PDF ends failed with the reason encrypted"
else
  fail "the encrypted PDF is '$(doc_state "$encok")', not failed|encrypted"
fi
echo "INFO the PDF, Word and encrypted files were settled $((SECONDS - begun)) s after their adds"
if [ "$(doc_count)" = 6 ]; then
  pass "the list holds the six documents"
else
  fail "the list holds $(doc_count) documents, wanted 6"
fi

# --- step 5: DELETE all six ---

for r in "$ref" "$pdf" "$nul" "$pdfok" "$docxok" "$encok"; do
  [ -n "$r" ] || continue
  code=$(api_send DELETE "documents/$r")
  if [ "$code" = 200 ] && [ "$(body_field result)" = done ]; then
    pass "DELETE /v1/documents/$r answers 200 {result: done}"
  else
    fail "DELETE /v1/documents/$r answered '$code'"
  fi
done
if [ "$(doc_count)" = 0 ]; then
  pass "the list is empty"
else
  fail "the list holds $(doc_count) documents after the deletes"
fi
if [ "$(table_rows)" = 0 ]; then
  pass "OcuTalonKB.Docs holds no row"
else
  fail "OcuTalonKB.Docs holds $(table_rows) rows after the deletes"
fi
mark gone "$ref"
run_class OcuTalon.Test.Docs.Live "$tmp/live3.chk"
check_live "$tmp/live3.chk" "after the deletes: the document is gone from the list and the table" 1
mark gone ""

echo "INFO live:documents took $((SECONDS - started)) s"
if [ "$fails" -eq 0 ]; then
  echo "test-documents: all checks passed"
  exit 0
fi
echo "test-documents: $fails check(s) failed (project $P)"
exit 1
