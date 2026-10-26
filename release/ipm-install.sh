#!/usr/bin/env bash
# The first install run of the IPM package (Story 15.1; AD-2, AD-3, AD-22, AD-23, AD-29; FR-57, REL-4): proves in throwaway stacks of
# a clean build 154 instance, an instance like an admin's with IPM 0.10.10 in %SYS and enabled for USER only, that the package's
# first run creates OCUTALON and gives the next command, and that `iris merge` of the package's CPF file is the alternative. It is
# the ipm-install job of .github/workflows/lane-a.yml and runs the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash release/ipm-install.sh
# It sources ci/iris.sh (which sources ci/units.sh and docker/tests/lib-live.sh) and runs nothing of them but the throwaway recipe:
# a project of its own from release/ipm/Dockerfile (no merge file, after-start script or version file; release/ipm/compose.ipm.yml),
# the CI override, the throwaway lock and the teardown on exit. Stories 15.2 and 15.3 extend the functions snapshot, residue and
# run. The checks:
#   Path A, two package runs:
#   1. the precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER; OCUTALON does not exist yet;
#   2. `zpm "load /opt/ocutalon-ipm/src"` in USER stops after Initialize: the output shows Initialize FAILURE, no Reload START and no
#      STEP line, and its last line, with ANSI codes removed, is exactly the stop sentence after `ERROR! `;
#   3. the run created the four OCUTALON databases (public Read on %DB_OCUTALON_PUBLIC only), OCUTALON with Interoperability and
#      AD-3's seven mappings, and mapped %IPM into OCUTALON from the database where %IPM resolves in USER; the services are those
#      of the baseline;
#   4. nothing of OcuTalon is left: no OcuTalon class, routine, global or module record in USER, %SYS or OCUTALON,
#      no OcuTalon role, no user ocutalon and no /ocutalon web application;
#   5. the same command again in USER, and in %SYS, gives the same stop, the same configuration and no residue;
#   6. IPM answers in OCUTALON (%IPM.Main.Shell("version") returns OK), so the next command can start there;
#   Path B, `iris merge`:
#   7. on a fresh instance from the same image, `iris merge IRIS /opt/ocutalon-ipm/src/cpf/ocutalon.cpf` exits 0 and gives the same
#      OCUTALON namespace, Interoperability flag, databases, resources and OCUTALON mappings as path A, minus the %IPM mappings,
#      and the services are unchanged.
# Every run's and the merge's full output is printed between `OUTPUT begin <name>` and `OUTPUT end <name>`, ANSI codes kept; the
# checks read it with the codes removed. `TIME <step> <s>s` lines give the durations. Prints one PASS or FAIL line per check, and
# exits 1 when any fails. The trap of live_start removes the project, its volume and its images, and releases the lock.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
. "$root/ci/iris.sh"

SCRIPT=release/ipm-install.sh
SRC=/opt/ocutalon-ipm/src
INSTALL="zpm \"load $SRC\""
STOP='OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.'

# --- the functions that Stories 15.2 and 15.3 extend ---

strip_ansi() { sed $'s/\033\\[[0-9;]*[A-Za-z]//g'; }

# The last line of a run's plain output that is not a blank or the terminal prompt that follows the command.
final_line() {
  awk '{ line[NR] = $0 } END {
    n = NR
    while (n > 0 && (line[n] ~ /^[ \t]*$/ || line[n] ~ /^[%A-Za-z0-9]+>[ \t]*$/)) n--
    if (n > 0) print line[n] }' "$1"
}

# run <name> <namespace> <terminal command>: runs the command in a terminal session of the namespace, prints the full output between
# OUTPUT lines (ANSI codes kept) and the duration, and leaves the plain output in $tmp/<name>.txt.
run() {
  local name=$1 ns=$2 started=$SECONDS
  printf '%s\nHalt\n' "$3" | dc exec -T iris iris session IRIS -U "$ns" > "$tmp/$name.raw" 2>&1
  run_rc=$?
  tr -d '\r' < "$tmp/$name.raw" > "$tmp/$name.crlf"
  mv "$tmp/$name.crlf" "$tmp/$name.raw"
  strip_ansi < "$tmp/$name.raw" > "$tmp/$name.txt"
  echo "TIME $name $((SECONDS - started))s"
  echo "OUTPUT begin $name"
  cat "$tmp/$name.raw"
  echo "OUTPUT end $name"
}

# snapshot <file>: the configuration, one CHK line per item, sorted, from one %SYS session:
#   service  every service with its enabled and authentication flags
#   ns       the namespace row of OCUTALON, and interop its Interoperability flag
#   db       the OCUTALON* databases with the last part of their directory
#   res      the %DB_OCUTALON* resources with their public permission
#   omap-*   the global, package and routine mappings of OCUTALON, with their database
#   umap-*   the package and routine mappings of USER
snapshot() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name,Enabled,AutheEnabled FROM Security.Services ORDER BY Name") While rs.%Next() { Write !,"CHK|service|",rs.%GetData(1),"|",rs.%GetData(2),"|",rs.%GetData(3) }' \
    'Set rs=##class(%ResultSet).%New("Config.Namespaces:List") Set sc=rs.Execute("OCUTALON") While rs.Next() { Write !,"CHK|ns" For i=1:1:rs.GetColumnCount() { Write "|",rs.GetData(i) } }' \
    'Write:##class(Config.Namespaces).Exists("OCUTALON") !,"CHK|interop|",##class(%Library.EnsembleMgr).IsEnsembleNamespace("OCUTALON")' \
    'Set rs=##class(%ResultSet).%New("Config.Databases:List") Set sc=rs.Execute("OCUTALON*") While rs.Next() { Set d=##class(%File).NormalizeDirectory(rs.Get("Directory")) Write !,"CHK|db|",rs.Get("Name"),"|",$Piece(d,"/",$Length(d,"/")-1) }' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name,PublicPermission FROM Security.Resources WHERE Name %STARTSWITH ? ORDER BY Name","%DB_OCUTALON") While rs.%Next() { Write !,"CHK|res|",rs.%GetData(1),"|",rs.%GetData(2) }' \
    'For q="MapGlobals","MapPackages","MapRoutines" { Set rs=##class(%ResultSet).%New("Config."_q_":List") Set sc=rs.Execute("OCUTALON") While rs.Next() { Write !,"CHK|omap-",q,"|",rs.Get("Name"),"|",rs.Get("Database") } Set rs=##class(%ResultSet).%New("Config."_q_":List") Set sc=rs.Execute("USER") While rs.Next() { Write !,"CHK|umap-",q,"|",rs.Get("Name"),"|",rs.Get("Database") } }' \
    'Halt' | iris_script %SYS | sort > "$1"
}

# residue [<label>]: the OcuTalon residue of the instance, one CHK|residue|<where>|<what>|<count> line each, in $tmp/residue.chk.
#   for USER, %SYS and OCUTALON (when it exists): the OcuTalon* class definitions, compiled classes and routine objects, and the
#   ocutalon module record; for USER and %SYS also the ^OcuTalon* globals; instance-wide the OcuTalon* roles, the user ocutalon and
#   the /ocutalon* web applications.
residue() {
  local ns where
  : > "$tmp/residue.chk"
  for ns in USER %SYS OCUTALON; do
    if [ "$ns" = OCUTALON ] && ! grep -q '^CHK|ns|' "$tmp/last-snapshot" 2>/dev/null; then continue; fi
    where=$ns
    printf '%s\n' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|'"$where"'|classes|",rs.%GetData(1)' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|'"$where"'|compiled|",rs.%GetData(1)' \
      'Set n=0,r="OcuTal" For { Set r=$Order(^rOBJ(r)) Quit:$Extract(r,1,6)'"'"'="OcuTal"  Set:$Extract(r,1,8)="OcuTalon" n=n+1 } Write !,"CHK|residue|'"$where"'|routines|",n' \
      'Write !,"CHK|residue|'"$where"'|module|",+##class(%IPM.Storage.Module).NameExists("ocutalon")' \
      'Halt' | iris_script "$ns" >> "$tmp/residue.chk"
    if [ "$ns" != OCUTALON ]; then
      printf '%s\n' \
        'Set n=0,g="^OcuTal" For { Set g=$Order(^$GLOBAL(g)) Quit:$Extract(g,1,7)'"'"'="^OcuTal"  Set:$Extract(g,1,9)="^OcuTalon" n=n+1 } Write !,"CHK|residue|'"$where"'|globals|",n' \
        'Halt' | iris_script "$ns" >> "$tmp/residue.chk"
    fi
  done
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Roles WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|instance|roles|",rs.%GetData(1)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Users WHERE Name = ?","ocutalon") Do rs.%Next() Write !,"CHK|residue|instance|user|",rs.%GetData(1)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE Name %STARTSWITH ?","/ocutalon") Do rs.%Next() Write !,"CHK|residue|instance|webapps|",rs.%GetData(1)' \
    'Halt' | iris_script %SYS >> "$tmp/residue.chk"
}

# check_no_residue <label>: residue prints every count (13 outside OCUTALON, 17 with it), and every count is 0.
check_no_residue() {
  local want=13
  residue
  if grep -q '^CHK|ns|' "$tmp/last-snapshot"; then want=17; fi
  if [ "$(grep -c . "$tmp/residue.chk")" -eq "$want" ] && ! grep -v '|0$' "$tmp/residue.chk" | grep -q .; then
    pass "$1: no OcuTalon class, routine, global, module record, role, user or web application is left in USER, %SYS or OCUTALON ($(grep -c . "$tmp/residue.chk") counts, all 0)"
  else
    grep -v '|0$' "$tmp/residue.chk" | sed 's/^/  residue: /'
    fail "$1: OcuTalon residue (a count above 0), or $(grep -c . "$tmp/residue.chk") counts printed instead of $want"
  fi
}

# take_snapshot <name> <label>: snapshot into $tmp/<name>.snap, and remembers it as the last one.
take_snapshot() {
  snapshot "$tmp/$1.snap"
  cp "$tmp/$1.snap" "$tmp/last-snapshot"
  if ! grep -q '^CHK|service|' "$tmp/$1.snap"; then die "$2: the snapshot session printed no services"; fi
}

# same_services <label> <snapshot a> <snapshot b>: the services lines are identical.
same_services() {
  if diff <(grep '^CHK|service|' "$tmp/$2.snap") <(grep '^CHK|service|' "$tmp/$3.snap") > "$tmp/services.diff"; then
    pass "$1: the services are unchanged ($(grep -c '^CHK|service|' "$tmp/$2.snap") services)"
  else
    sed 's/^/  services: /' "$tmp/services.diff"
    fail "$1: a service changed"
  fi
}

# stops_with_next_command <name> <label>: the run's plain output is the stop of the first run.
stops_with_next_command() {
  local f="$tmp/$1.txt" ok=1
  grep -q 'Initialize FAILURE' "$f" || ok=0
  ! grep -q 'Reload START' "$f" || ok=0
  ! grep -q '^STEP ' "$f" || ok=0
  if [ "$ok" = 1 ] && [ "$(final_line "$f")" = "ERROR! $STOP" ]; then
    pass "$2: Initialize fails, no Reload and no STEP line, and the last line is ERROR! and the stop sentence"
  else
    echo "  last line: '$(final_line "$f")'"
    fail "$2: the run did not stop the way the first run does (Initialize FAILURE, no Reload START, no STEP line, and the exact last line)"
  fi
}

# --- the stack ---

setup_tag
preflight
live_start ipm
live_add_file "$root/release/ipm/compose.ipm.yml"
echo "STACK ipm install: project $P"
started=$SECONDS
if ! dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "the stack did not become ready"
fi
live_track_image
echo "TIME ready $((SECONDS - started))s"

# --- path A: two package runs ---

check_session "precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER only" %SYS \
  "CHK|load|1
CHK|enable|1" \
  'Set sc=$SYSTEM.OBJ.Load("/opt/ocutalon-ipm/zpm-0.10.10.xml","ck-d") Write !,"CHK|load|",$SYSTEM.Status.IsOK(sc)' \
  'Set sc=##class(%IPM.Main).Shell("enable -map -ns USER -q") Write !,"CHK|enable|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'
if [ "$fails" -ne 0 ]; then die "IPM could not be loaded and enabled for USER"; fi
take_snapshot base "precondition"
if ! grep -q '^CHK|ns|' "$tmp/base.snap" && ! grep -q '^CHK|db|' "$tmp/base.snap"; then
  pass "precondition: OCUTALON and its databases do not exist yet"
else
  die "precondition: OCUTALON or its databases exist before the first run"
fi
ipm_db=$(sed -n 's/^CHK|umap-MapPackages|%IPM|//p' "$tmp/base.snap" | head -n 1)
if [ -z "$ipm_db" ]; then die "precondition: IPM is not mapped into USER"; fi
check_no_residue "precondition"

run first-user USER "$INSTALL"
take_snapshot first "first run in USER"
stops_with_next_command first-user "first run in USER"
cat > "$tmp/expected.chk" <<EOE
CHK|interop|1
CHK|db|OCUTALON_CODE|ocutalon_code
CHK|db|OCUTALON_DATA|ocutalon_data
CHK|db|OCUTALON_PRIVATE|ocutalon_private
CHK|db|OCUTALON_PUBLIC|ocutalon_public
CHK|omap-MapGlobals|OcuTalonP.*|OCUTALON_PRIVATE
CHK|omap-MapGlobals|OcuTalonBP.*|OCUTALON_PRIVATE
CHK|omap-MapGlobals|AI.Agent.Session*|OCUTALON_PRIVATE
CHK|omap-MapGlobals|IRIS.IF.*|OCUTALON_PRIVATE
CHK|omap-MapGlobals|OcuTalonPublic|OCUTALON_PUBLIC
CHK|omap-MapPackages|OcuTalon.Web.Public|OCUTALON_PUBLIC
CHK|omap-MapPackages|OcuTalon.Data.Public|OCUTALON_PUBLIC
CHK|omap-MapPackages|%IPM|$ipm_db
CHK|omap-MapRoutines|%IPM.*|$ipm_db
EOE
compare_chk "first run in USER: the databases, the Interoperability flag, AD-3's seven mappings and the %IPM mappings" "$tmp/first.snap" "$tmp/expected.chk"
grep '^CHK|ns|' "$tmp/first.snap" | head -n 1 | sed 's/^/  namespace row: /'
if grep -q '^CHK|ns|OCUTALON|OCUTALON_DATA|OCUTALON_CODE|' "$tmp/first.snap"; then
  pass "first run in USER: OCUTALON has the globals database OCUTALON_DATA and the routines database OCUTALON_CODE"
else
  fail "first run in USER: the namespace row of OCUTALON is not Globals OCUTALON_DATA and Routines OCUTALON_CODE"
fi
if [ "$(grep -c '^CHK|res|' "$tmp/first.snap")" = 4 ] && grep -q '^CHK|res|%DB_OCUTALON_PUBLIC|1$' "$tmp/first.snap" \
  && [ "$(grep -c '^CHK|res|%DB_OCUTALON_\(CODE\|DATA\|PRIVATE\)|0$' "$tmp/first.snap")" = 3 ]; then
  pass "first run in USER: the four %DB_OCUTALON resources exist and only %DB_OCUTALON_PUBLIC has public Read"
else
  grep '^CHK|res|' "$tmp/first.snap" | sed 's/^/  /'
  fail "first run in USER: the %DB_OCUTALON resources are not the four with public Read on the public one only"
fi
same_services "first run in USER" base first
check_no_residue "first run in USER"

run again-user USER "$INSTALL"
take_snapshot again-user "the repeat in USER"
stops_with_next_command again-user "the repeat in USER"
if diff "$tmp/first.snap" "$tmp/again-user.snap" > "$tmp/snap.diff"; then
  pass "the repeat in USER: the configuration and the services are those of the first run"
else
  sed 's/^/  snapshot: /' "$tmp/snap.diff"
  fail "the repeat in USER: the configuration changed"
fi
check_no_residue "the repeat in USER"

run again-sys %SYS "$INSTALL"
take_snapshot again-sys "the run in %SYS"
stops_with_next_command again-sys "the run in %SYS"
if diff "$tmp/first.snap" "$tmp/again-sys.snap" > "$tmp/snap.diff"; then
  pass "the run in %SYS: the configuration and the services are those of the first run"
else
  sed 's/^/  snapshot: /' "$tmp/snap.diff"
  fail "the run in %SYS: the configuration changed"
fi
check_no_residue "the run in %SYS"

check_session "IPM answers in OCUTALON, so the next command can start there" OCUTALON \
  "CHK|version|1" \
  'Set sc=##class(%IPM.Main).Shell("version") Write !,"CHK|version|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'

# --- path B: iris merge on a fresh instance ---

echo "PATH B: iris merge of /opt/ocutalon-ipm/src/cpf/ocutalon.cpf on a fresh instance"
started=$SECONDS
dc down -v > "$tmp/down.log" 2>&1
if ! dc up -d --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "the second stack did not become ready"
fi
echo "TIME ready-b $((SECONDS - started))s"
take_snapshot base-b "path B"
if ! grep -q '^CHK|ns|' "$tmp/base-b.snap" && ! grep -q '^CHK|db|' "$tmp/base-b.snap"; then
  pass "path B: the fresh instance has no OCUTALON"
else
  die "path B: the fresh instance has OCUTALON already"
fi

started=$SECONDS
dc exec -T iris iris merge IRIS "$SRC/cpf/ocutalon.cpf" > "$tmp/merge.raw" 2>&1
merge_rc=$?
echo "TIME merge $((SECONDS - started))s"
echo "OUTPUT begin merge"
cat "$tmp/merge.raw"
echo "OUTPUT end merge"
if [ "$merge_rc" -eq 0 ]; then pass "path B: iris merge exits 0"; else fail "path B: iris merge exits $merge_rc"; fi
take_snapshot merge "path B"
same_services "path B" base-b merge
# The OCUTALON view of path B is that of path A without the two %IPM mappings, and holds none; USER's mappings and the services are
# not part of the view.
view() { grep -v -e '^CHK|service|' -e '^CHK|umap-' -e '%IPM' "$1"; }
if view "$tmp/first.snap" > "$tmp/view-a" && view "$tmp/merge.snap" > "$tmp/view-b" && [ -s "$tmp/view-b" ] \
  && diff "$tmp/view-a" "$tmp/view-b" > "$tmp/snap.diff" && ! grep -q '%IPM' "$tmp/merge.snap"; then
  pass "path B: OCUTALON's namespace row, Interoperability flag, databases, resources and mappings are path A's, without the %IPM mappings ($(grep -c . "$tmp/view-b") lines)"
else
  sed 's/^/  view: /' "$tmp/snap.diff"
  fail "path B: the OCUTALON view differs from path A's"
fi

if [ "$fails" -ne 0 ]; then
  echo "$(basename "$SCRIPT" .sh): $fails check(s) failed (project $P)"
  exit 1
fi
echo "$(basename "$SCRIPT" .sh): all checks passed"
