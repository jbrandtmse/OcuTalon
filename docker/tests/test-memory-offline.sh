#!/usr/bin/env bash
# Live unit of the offline memory vectors (Story 19.2; AD-6, AD-21, AD-23): builds the image and starts it in one throwaway compose project with the
# after-start script active, so that the product is installed, then disconnects EVERY network of the iris container and proves, with the network cut:
#   - the install ended ready with STEP Memory OK and no WARN Memory, nothing downloaded into the manager directory, the model folder baked into the
#     image (FASTEMBED_CACHE_DIR) untouched;
#   - an outbound name lookup and an outbound connection to an address both fail, so a vector below cannot have come from the network;
#   - OcuTalon.Test.Memory.Offline passes (a memory row stored with its embedding is the top VECTOR_COSINE hit for a paraphrase; AI Hub's FastEmbed
#     embeds a document chunk into a test vector-store table from the baked folder and from a copy under the manager directory in a worker);
#   - the install step's Run(), run again offline, returns OK, writes no warning, attempts no download (EnsureModel answers 0) and leaves the
#     baked folder's file list the same;
#   - Story 19.3: before the network is cut, OcuTalon.Test.Memory.Turns runs the memory tools through live turns of the Chat agent against the CI mock
#     (the ChatAgent job is the same across the turns: a tool that embeds from AI Hub's callback does not crash the runner, DW-782); with the network cut,
#     a memory is saved through MemoryOps (Commands.Submit, origin tool, no bridge context) and found by Memory.Search, the iris container is restarted
#     (a restart puts it back on its network, so the network is cut again at once, and the manager directory is checked again for a fastembed folder,
#     so nothing was downloaded in that window) and the memory row is still there and found again by Memory.Search, offline; at the end
#     OcuTalon.Test.Memory.Volume runs (10,000 memories of one owner and 500 of another, and the plan of the recall query reads EmbeddingIdx).
# Prints one PASS or FAIL line per check and, last, MEMORY-OFFLINE engine=<uname -m of the iris container> ok=<0|1>; exits 0 only when all pass.
# The unit reads no web bundle at run time (the image build needs the bundle, as for every live unit). The project is unique, publishes no host port and
# receives no keys. An EXIT trap removes the project with its volume and images. Every wait ends by an overall deadline.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start memory-offline

engine=unknown
finish() {
  local ok=0
  if [ "$fails" -eq 0 ]; then ok=1; fi
  echo "MEMORY-OFFLINE engine=$engine ok=$ok"
  if [ "$ok" -ne 1 ]; then
    echo "test-memory-offline: $fails check(s) failed (project $P)"
    exit 1
  fi
  echo "test-memory-offline: all checks passed"
  exit 0
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

# check_class <class> <chk file> <what>: passes when the class ran, passed, had test methods and skipped none; <what> ends the message.
check_class() {
  local casename status methods skips
  casename=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\1/p' "$2" | head -n 1)
  status=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\2/p' "$2" | head -n 1)
  methods=$(sed -n 's/^CHK|case|\([^|]*\)|\([^|]*\)|\([^|]*\)$/\3/p' "$2" | head -n 1)
  skips=$(grep -c '^CHK|assert|2|' "$2")
  if [ -n "$casename" ] && [ "$status" = 1 ] && [ "${methods:-0}" -gt 0 ] && [ "$skips" = 0 ]; then
    pass "$1 passed ($methods test methods, none skipped) $3"
  else
    sed -n 's/^CHK|\(assert\|error\)|/  /p' "$2" | cut -c1-300
    fail "$1 did not pass $3 (case '$casename', status '$status', $methods methods, $skips skipped)"
  fi
}

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
engine=$(dc exec -T iris uname -m 2> /dev/null | tr -d '\r')
[ -n "$engine" ] || engine=unknown

if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready within $LIVE_FIRST_START_WAIT s"
fi
pass "the first start ended ready"

if [ "$(start_log | grep -c '^STEP Memory OK')" = 1 ]; then
  pass "the start's log has STEP Memory OK once"
else
  fail "the start's log does not have STEP Memory OK exactly once"
fi
if start_log | grep -q '^WARN Memory '; then
  fail "the start's log has a WARN Memory line: the image must download nothing"
  start_log | grep '^WARN Memory ' | cut -c1-300
else
  pass "and no WARN Memory line: the baked model folder was enough"
fi

# mgr_folder_check <file> <pass text> <fail text>: PASS when the manager directory holds no fastembed folder (nothing was downloaded there).
mgr_folder_check() {
  printf '%s\n' 'Write !,"CHK|mgr-folder|",##class(%File).DirectoryExists($SYSTEM.Util.ManagerDirectory()_"fastembed")' 'Halt' | iris_script OCUTALON > "$tmp/$1"
  if grep -qx 'CHK|mgr-folder|0' "$tmp/$1"; then
    pass "$2"
  else
    fail "$3"
  fi
}
mgr_folder_check mgr-folder.chk "the manager directory holds no fastembed folder: the install downloaded nothing and the worker reads the baked folder" \
  "the manager directory holds a fastembed folder, or the check printed nothing: the install downloaded the model, or the worker looks there"

# fingerprint <folder>: the file list with sizes, one checksum, and the file count.
fingerprint() { dc exec -T iris sh -c "cd '$1' && find . -printf '%p %s\n' | sort | md5sum | cut -c1-12; find . -type f | wc -l" 2> /dev/null | tr -d '\r' | tr '\n' ' '; }
baked=$(dc exec -T iris printenv FASTEMBED_CACHE_DIR 2> /dev/null | tr -d '\r')
if [ "$baked" = /opt/fastembed ]; then
  pass "FASTEMBED_CACHE_DIR names /opt/fastembed in the container"
else
  fail "FASTEMBED_CACHE_DIR is '$baked', not /opt/fastembed"
fi
before=$(fingerprint /opt/fastembed)

# The memory tools through live turns of the Chat agent against the CI mock, while the mock is still reachable.
run_class OcuTalon.Test.Memory.Turns "$tmp/turns.chk"
check_class OcuTalon.Test.Memory.Turns "$tmp/turns.chk" "with the CI mock reachable (live turns of the Chat agent)"

# Cut every network of the iris container.
networks=$(docker inspect --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$cid")
for network in $networks; do
  docker network disconnect "$network" "$cid" > /dev/null 2>&1 || fail "the network $network could not be disconnected"
done
left=$(docker inspect --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$cid" | tr -d ' ')
if [ -z "$networks" ]; then
  fail "the iris container had no network to disconnect"
elif [ -z "$left" ]; then
  pass "every network of the iris container is disconnected"
else
  fail "the iris container is still connected to: $left"
fi

# Nothing leaves the container: a name lookup fails and a connection to an address fails. The probes run python3 in the container, which must
# work with the networks cut, so that a failing probe means no network and not a broken probe.
if dc exec -T iris python3 -c "import socket" > /dev/null 2>&1; then
  pass "python3 runs in the iris container, so a failing probe means no network"
else
  fail "python3 does not run in the iris container: the network probes prove nothing"
fi
if dc exec -T iris python3 -c "import socket; socket.getaddrinfo('huggingface.co', 443)" > /dev/null 2>&1; then
  fail "an outbound name lookup succeeded: the network is not cut"
else
  pass "an outbound name lookup fails"
fi
if dc exec -T iris python3 -c "import socket; socket.create_connection(('1.1.1.1', 443), timeout=5)" > /dev/null 2>&1; then
  fail "an outbound connection succeeded: the network is not cut"
else
  pass "an outbound connection to an address fails"
fi

# The test class, run in the stack through the %UnitTest.Manager as ci/iris.sh does, and the install step's Run().
run_class OcuTalon.Test.Memory.Offline "$tmp/offline.chk"
check_class OcuTalon.Test.Memory.Offline "$tmp/offline.chk" "with the network cut"

printf '%s\n' \
  'Do ##class(OcuTalon.Install.Step).TakeWarnings()' \
  'Set sc=##class(OcuTalon.Install.Step.Memory).Run()' \
  'Write !,"CHK|attempted|",##class(OcuTalon.Install.Step.Memory).EnsureModel(##class(OcuTalon.Memory.Embedder).ModelFolder())' \
  'Write !,"CHK|step|",$SYSTEM.Status.IsOK(sc)' \
  'Set warnings=##class(OcuTalon.Install.Step).TakeWarnings()' \
  'Write !,"CHK|warnings|",$ListLength(warnings)' \
  'Set position=0 While $ListNext(warnings,position,line) { Write !,"CHK|warning|",$Extract(line,1,300) }' \
  'Halt' | iris_script OCUTALON > "$tmp/step.chk"
if grep -qx 'CHK|step|1' "$tmp/step.chk" && grep -qx 'CHK|warnings|0' "$tmp/step.chk" && grep -qx 'CHK|attempted|0' "$tmp/step.chk"; then
  pass "the Memory step's Run() offline returns OK with no warning, and attempts no download"
else
  sed -n 's/^CHK|warning|/  /p' "$tmp/step.chk"
  fail "the Memory step's Run() offline did not return OK with no warning, or attempted a download"
fi
after=$(fingerprint /opt/fastembed)
if [ -n "$before" ] && [ "$before" = "$after" ]; then
  pass "the baked model folder is unchanged: nothing was downloaded or written ($after)"
else
  fail "the baked model folder changed: '$before' became '$after'"
fi

# Story 19.3: a memory is saved through MemoryOps (Commands.Submit as origin tool, with no bridge context) and found by Memory.Search while the network is cut.
question='who do I call about Results?'
printf '%s\n' \
  'Set ref=##class(OcuTalon.Test.Data.Fixture).Session("zz-mem-offline")' \
  'Set command=##class(OcuTalon.Msg.Command.SaveMemory).%New()' \
  'Set command.SessionRef=ref,command.IdempotencyKey="zzmemoffline000000001:1",command.Text="the contact at the Results partner is Lee"' \
  'Set sc=##class(OcuTalon.Core.Commands).Submit(command,"tool",.result)' \
  'Write !,"CHK|session|",ref' \
  'Write !,"CHK|save|",$SYSTEM.Status.IsOK(sc),"|",result.Ok,"|",result.Outcome,"|",result.Ref' \
  'Set sc=##class(OcuTalon.Memory).Search(ref,"'"$question"'",5,.rows)' \
  'Write !,"CHK|found|",$SYSTEM.Status.IsOK(sc),"|",rows.%Size(),"|",rows.%Get(0).memoryRef' \
  'Halt' | iris_script OCUTALON > "$tmp/offline-save.chk"
session=$(sed -n 's/^CHK|session|//p' "$tmp/offline-save.chk" | head -n 1)
saved=$(sed -n 's/^CHK|save|1|1|saved|//p' "$tmp/offline-save.chk" | head -n 1)
if [ -n "$session" ] && [ -n "$saved" ] && grep -qx "CHK|found|1|1|$saved" "$tmp/offline-save.chk"; then
  pass "a memory saved through MemoryOps with the network cut is found by Memory.Search"
else
  cat "$tmp/offline-save.chk"
  fail "a memory saved through MemoryOps with the network cut was not found by Memory.Search"
fi

# The iris container restarts, still disconnected: a restart puts a container back on its network, so the network is cut again at once.
if ! docker restart "$cid" > "$tmp/restart.log" 2>&1; then
  cat "$tmp/restart.log"
  die "the iris container did not restart"
fi
for network in $(docker inspect --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$cid"); do
  docker network disconnect "$network" "$cid" > /dev/null 2>&1 || fail "the network $network could not be disconnected after the restart"
done
left=$(docker inspect --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$cid" | tr -d ' ')
if [ -z "$left" ] && ! dc exec -T iris python3 -c "import socket; socket.getaddrinfo('huggingface.co', 443)" > /dev/null 2>&1; then
  pass "the restarted iris container has no network and no name lookup"
else
  fail "the restarted iris container is connected to: $left"
fi
# The park of the Telegram items talks to the CI mock, which the cut network does not reach: the items stay as the restart made them.
if ! LIVE_TELEGRAM=started wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the restart did not end ready within 400 s"
fi
pass "the restart ended ready"
mgr_folder_check mgr-folder-restart.chk "after the restart the manager directory still holds no fastembed folder: nothing was downloaded before the network was cut again" \
  "after the restart the manager directory holds a fastembed folder, or the check printed nothing: the restart downloaded the model"
printf '%s\n' \
  'Set sc=##class(OcuTalon.Memory).Search("'"$session"'","'"$question"'",5,.rows)' \
  'Write !,"CHK|found|",$SYSTEM.Status.IsOK(sc),"|",rows.%Size(),"|",rows.%Get(0).memoryRef' \
  'Set row=##class(OcuTalon.Data.Memory).RefIndexOpen("'"$saved"'")' \
  'Write !,"CHK|row|",$IsObject(row)' \
  'Halt' | iris_script OCUTALON > "$tmp/offline-restart.chk"
if grep -qx "CHK|found|1|1|$saved" "$tmp/offline-restart.chk" && grep -qx 'CHK|row|1' "$tmp/offline-restart.chk"; then
  pass "after the restart, offline, the memory is still found by Memory.Search"
else
  cat "$tmp/offline-restart.chk"
  fail "after the restart, offline, the memory was not found by Memory.Search"
fi

# The memory of this check goes, and the recall query at volume runs (the class skips unless the flag is set).
printf '%s\n' \
  'Do ##class(OcuTalon.Test.Memory.Fixture).Purge("'"$session"'")' \
  'Set ^OcuTalonTest("Memory","volume")=1' \
  'Write !,"CHK|flag|1"' \
  'Halt' | iris_script OCUTALON > /dev/null
run_class OcuTalon.Test.Memory.Volume "$tmp/volume.chk"
printf '%s\n' 'Kill ^OcuTalonTest("Memory","volume")' 'Write !,"CHK|flag|0"' 'Halt' | iris_script OCUTALON > /dev/null
check_class OcuTalon.Test.Memory.Volume "$tmp/volume.chk" "with the network cut (10,000 and 500 memories, the plan reads EmbeddingIdx)"

finish
