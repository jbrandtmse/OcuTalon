#!/usr/bin/env bash
# Live test of the storage round trip (Story 0.7, DW-11; AD-5): builds the image and starts it in one throwaway compose project,
# then, after the install has loaded and compiled the package,
#   - exports every compiled OcuTalon class that has a storage definition (a class that the compiler generated, such as the
#     MessagesReceived classes of a business process, is not one) into a temporary folder in the container, and compares each
#     class's Storage block with the block of the image's source file (/opt/ocutalon/src), so that a committed block that the
#     compiler would change is found: a block with a slot missing, or one that was edited by hand. The set of compared classes must
#     equal the set of source files that carry a Storage block, so that neither a stored class without a committed block nor a block
#     of a class that is not compiled passes;
#   - the control: a copy of OcuTalon.Bridge.Process.Decide with the third slot removed from its block is loaded and compiled, and
#     its export must differ from the copy (the compiler gives the slot back), and the original, loaded again, must export equal
#     to its file. A comparison that cannot see a difference would pass anything.
# The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t07rt

decide_class=OcuTalon.Bridge.Process.Decide
decide_src=/opt/ocutalon/src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls

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

# The Storage blocks of a class file: from a line that starts a block to its closing brace.
dc exec -T iris sh -c 'cat > /tmp/rt-blocks.awk' <<'EOA'
/^Storage / { p = 1 }
p { print }
p && /^\}/ { p = 0 }
EOA

# blocks_state <file a> <file b>: in the container, SAME when the Storage blocks of the two files are identical, DIFF when they
# differ, EMPTY when the first has no block, and MISSING when a file cannot be read.
blocks_state() {
  dc exec -T iris sh -c '
    [ -r "$1" ] && [ -r "$2" ] || { echo MISSING; exit 0; }
    awk -f /tmp/rt-blocks.awk "$1" > /tmp/rt-a.blk
    awk -f /tmp/rt-blocks.awk "$2" > /tmp/rt-b.blk
    if [ ! -s /tmp/rt-a.blk ]; then echo EMPTY; elif cmp -s /tmp/rt-a.blk /tmp/rt-b.blk; then echo SAME; else echo DIFF; fi
  ' sh "$1" "$2" < /dev/null | tr -d '\r'
}

# --- the compiled classes with a storage definition, exported ---

cat > "$tmp/export.txt" <<'EOS'
Do ##class(%File).CreateDirectoryChain("/tmp/rt")
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT DISTINCT parent->Name FROM %Dictionary.CompiledStorage WHERE parent->Name %STARTSWITH 'OcuTalon.' AND (parent->GeneratedBy IS NULL OR parent->GeneratedBy = '') ORDER BY 1")
Set n=0
While rs.%Next() { Set c=rs.%GetData(1) Set sc=$SYSTEM.OBJ.ExportUDL(c_".cls","/tmp/rt/"_c_".cls") Set n=n+1 Write !,"CHK|stored|",c,"|",$SYSTEM.Status.IsOK(sc) }
Write !,"CHK|exported|",n
Halt
EOS
iris_script OCUTALON < "$tmp/export.txt" > "$tmp/export.out"
exported=$(sed -n 's/^CHK|exported|//p' "$tmp/export.out")
sed -n 's/^CHK|stored|\(.*\)|\([01]\)$/\1/p' "$tmp/export.out" | sort > "$tmp/compiled.txt"
failed_exports=$(sed -n 's/^CHK|stored|\(.*\)|0$/\1/p' "$tmp/export.out")
if [ -n "$exported" ] && [ "$exported" -gt 0 ] && [ -z "$failed_exports" ] && [ "$(wc -l < "$tmp/compiled.txt" | tr -d ' ')" = "$exported" ]; then
  pass "$exported compiled classes with a storage definition were exported"
else
  fail "the export of the compiled classes with a storage definition failed (exported '$exported'; failed: $(printf '%s' "$failed_exports" | tr '\n' ' '))"
fi

# The committed side: the class of every source file of the image that carries a Storage block.
dc exec -T iris sh -c "grep -rl '^Storage ' /opt/ocutalon/src --include=*.cls" 2>/dev/null | tr -d '\r' \
  | sed -e 's#^/opt/ocutalon/src/[^/]*/cls/##' -e 's#\.cls$##' -e 's#/#.#g' | sort > "$tmp/committed.txt"
if [ -s "$tmp/committed.txt" ] && [ "$(comm -3 "$tmp/compiled.txt" "$tmp/committed.txt" | wc -l | tr -d ' ')" = 0 ]; then
  pass "the compiled classes with a storage definition are the $(wc -l < "$tmp/committed.txt" | tr -d ' ') classes with a committed Storage block"
else
  comm -23 "$tmp/compiled.txt" "$tmp/committed.txt" | sed 's/^/  compiled and not committed: /' | head -n 10
  comm -13 "$tmp/compiled.txt" "$tmp/committed.txt" | sed 's/^/  committed and not compiled: /' | head -n 10
  fail "the set of compiled classes with a storage definition differs from the set of committed Storage blocks"
fi

# --- each Storage block equals the committed one ---

n=0
bad=""
while IFS= read -r class; do
  [ -n "$class" ] || continue
  src=$(dc exec -T iris sh -c "ls /opt/ocutalon/src/*/cls/$(printf '%s' "$class" | tr . /).cls 2>/dev/null | head -n 1" < /dev/null | tr -d '\r')
  state=$(blocks_state "/tmp/rt/$class.cls" "${src:-/nonexistent}")
  n=$((n + 1))
  if [ "$state" != SAME ]; then bad="$bad $class($state)"; fi
done < "$tmp/compiled.txt"
if [ "$n" -gt 0 ] && [ "$n" = "$exported" ] && [ -z "$bad" ]; then
  pass "the Storage block of each of $n compiled classes, exported after the install, equals its committed block"
else
  for c in $bad; do echo "  differs: $c"; done | head -n 20
  fail "the exported Storage block differs from the committed one, or not every export was compared ($n of '$exported'): $bad"
fi

# --- the control: the comparison sees a block with a slot missing ---

dc exec -T iris cat "$decide_src" | tr -d '\r' > "$tmp/decide.orig"
awk '/^<Value name="3">$/ { skip = 1 } !skip { print } skip && /^<\/Value>$/ { skip = 0 }' "$tmp/decide.orig" > "$tmp/decide.mutated"
if [ -s "$tmp/decide.orig" ] && ! cmp -s "$tmp/decide.orig" "$tmp/decide.mutated"; then
  pass "control: the copy of Decide has its third slot removed from the Storage block"
else
  die "control: the mutation did not change the copy of Decide"
fi
dc exec -T iris mkdir -p /tmp/ctl /tmp/rt-ctl
dc cp "$tmp/decide.mutated" iris:/tmp/ctl/Decide.cls >/dev/null 2>&1 || die "control: the copy could not be put into the container"
check_session "control: the copy is loaded and compiled, and exported" OCUTALON \
  "CHK|load|1
CHK|export|1" \
  'Write !,"CHK|load|",$SYSTEM.OBJ.Load("/tmp/ctl/Decide.cls","ck-d")' \
  "Write !,\"CHK|export|\",\$SYSTEM.OBJ.ExportUDL(\"$decide_class.cls\",\"/tmp/rt-ctl/Decide.mutated.cls\")" \
  'Halt'
state=$(blocks_state /tmp/rt-ctl/Decide.mutated.cls /tmp/ctl/Decide.cls)
if [ "$state" = DIFF ]; then
  pass "control: the export of the copy differs from the copy (the compiler gave the slot back), so the comparison sees a difference"
else
  fail "control: the export of the copy is '$state' against the copy, wanted DIFF"
fi
check_session "control: the original is loaded again, compiled, and exported" OCUTALON \
  "CHK|load|1
CHK|export|1" \
  "Write !,\"CHK|load|\",\$SYSTEM.OBJ.Load(\"$decide_src\",\"ck-d\")" \
  "Write !,\"CHK|export|\",\$SYSTEM.OBJ.ExportUDL(\"$decide_class.cls\",\"/tmp/rt-ctl/Decide.original.cls\")" \
  'Halt'
state=$(blocks_state /tmp/rt-ctl/Decide.original.cls "$decide_src")
if [ "$state" = SAME ]; then
  pass "control: the original, loaded again, exports a Storage block equal to its file"
else
  fail "control: the export of the original is '$state' against its file, wanted SAME"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-storage-roundtrip: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-storage-roundtrip: all checks passed"
