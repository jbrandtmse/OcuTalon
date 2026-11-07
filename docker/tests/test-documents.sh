#!/usr/bin/env bash
# Live unit of the documents (Story 19.4; AD-1, AD-5, AD-21, AD-23, DW-739): builds the image and starts it in one throwaway compose project, signs the README
# account in, and drives the REAL routes /v1/documents over HTTP, the way the page does, so that CommandsIn, DocumentOps, the Embedder worker and OcuTalonKB.Docs
# are all real (no double, no page.route):
#   1. the texts that Story 19.4's rulings fix are in the files that ship them (docs/bridge-guide.md, docs/security-overview.md), word for word;
#   2. POST /v1/documents with a Markdown runbook ({name, content} with the bytes in base64) answers 200 {"result":"done","ref"}; the list shows the document
#      ready within 120 s; OcuTalon.Test.Docs.Live (TestFound) finds its passages, with their document and section, in OcuTalonKB.Docs, and a search through AI Hub's
#      knowledge base returns the passage of the certificate first with a score over the floor;
#   3. the iris container restarts (AD-5): after the restart the list still shows the document ready and TestFound passes again;
#   4. a 10,485,760-byte .pdf (made here, in the unit's temporary folder, and never kept: no PDF of that size is committed) is accepted by the real route (200, the
#      size check D8 of the page specs used to make) and ends failed with the reason not_built; a .txt with a NUL ends failed with the reason unreadable;
#   5. DELETE of all three answers 200, the list is empty, and OcuTalon.Test.Docs.Live (TestGone) finds no row and no knowledge-base row of any document.
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
big=$(cd "$root" && git ls-files 2> /dev/null | grep -iE '\.(pdf|docx)$' | while read -r f; do if [ "$(wc -c < "$f")" -gt 1000000 ]; then echo "$f"; fi; done)
if [ -z "$big" ]; then
  pass "no PDF or Word file over 1 MB is in the repository: the 10 MB .pdf of this unit is generated at test time"
else
  fail "a large PDF or Word file is tracked: $big"
fi

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
if [ -n "$pdf" ] && wait_until 120 doc_is "$pdf" 'failed|not_built'; then
  pass "the .pdf ends failed with the reason not_built (Story 19.7 reads it)"
else
  fail "the .pdf is '$(doc_state "$pdf")', not failed|not_built"
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

# --- step 5: DELETE all three ---

for r in "$ref" "$pdf" "$nul"; do
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
