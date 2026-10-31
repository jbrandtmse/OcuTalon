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
#   4. nothing of OcuTalon is left: no OcuTalon class, routine or module record in USER, %SYS or OCUTALON, no ^OcuTalon global
#      in USER or %SYS, no OcuTalon role, no user ocutalon and no /ocutalon web application;
#   5. the same command again in USER, and in %SYS, gives the same stop, the same configuration and no residue, and the same
#      install through %IPM.Main.Shell() in USER returns the stop sentence as an error status (the stop is not reported as a
#      success), leaves transactions neither suspended nor open in the session, and leaves no residue;
#   6. IPM answers in OCUTALON (%IPM.Main.Shell("version") returns OK), so the next command can start there;
#   Path B, `iris merge`:
#   7. on a fresh instance from the same image, `iris merge IRIS /opt/ocutalon-ipm/src/cpf/ocutalon.cpf` exits 0 and gives the same
#      OCUTALON namespace, Interoperability flag, databases, resources and OCUTALON mappings as path A, minus the %IPM mappings,
#      and the services are unchanged.
# Story 15.2 adds the second run:
#   Path A, after check 6, the same install command in OCUTALON:
#   8. the output shows Initialize to Activate SUCCESS and, between Configure START and Configure SUCCESS, one `STEP <name> OK` line
#      per name of Registry.Order(), in that order; the production runs with no item missing and no runner without a model,
#      ^Ens.AutoStart is OcuTalon.Production, the module is recorded with 0 dependencies, the services are the baseline's, USER and
#      %SYS hold no OcuTalon class, routine, module record or global, and PasswordValidationRoutine is still empty;
#   9. the install checks: the public package and global resolve to OCUTALON_PUBLIC and the private globals to OCUTALON_PRIVATE,
#      `STEP PrivateData OK`, the bundle's index.html is in the /ocutalon application's Path, onlineDemo is 0 and ready is 1;
#   10. web and REST: /ocutalon/ serves the sign-in page and not the online demo's, ocutalon/ocutalon signs in, /state has onlineDemo
#      and demoMode false and no guide, phone or mailbox, demo/break-feed answers 404, OCUORDERS does not exist, and a chat message
#      (the keys pointed at the CI mock) ends in a turn whose decision has no fallbackReason;
#   11. one module whose name starts with ocutalon, the bridge installer and the bridge example compiled, the example neither running
#      nor the autostart production;
#   12. SetDemoMode(1) then (0) in a terminal session: SettingsOps' lines, OCUORDERS and its two databases and mappings, the Orders
#      production running there, then everything gone, the other namespaces and USER's mappings unchanged;
#   13. a production start outside the Production step (Ens.Director from a session) is reconciled exactly once by ReconcileIn;
#   14. Registry.Run("ipm") ends with STEP Reconcile OK, and ReconcileIn reconciles nothing of that start.
#   Path B, after check 7:
#   15. `zpm "enable -map -ns OCUTALON"` in %SYS, a foreign password-validation routine and a foreign OCUORDERS, then the install
#      command in OCUTALON: every STEP is OK, WARN Demo names the kept namespace, and the foreign setting, routine, OCUORDERS, its
#      databases and the services are unchanged.
# The argument chooses the paths: none runs A and B (the job), `a` path A only, `b` path A's first run (the reference of path B's
# comparison) and path B.
# Every run's and the merge's full output is printed between `OUTPUT begin <name>` and `OUTPUT end <name>`, ANSI codes kept; the
# checks read it with the codes removed. `TIME <step> <s>s` lines give the durations. Prints one PASS or FAIL line per check, and
# exits 1 when any fails. The trap of live_start removes the project, its volume and its images, and releases the lock.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
mode=${1:-all}
case $mode in
  all | a | b) ;;
  *)
    echo "usage: bash release/ipm-install.sh [a|b]"
    exit 2
    ;;
esac
. "$root/ci/iris.sh"
. "$root/docker/tests/lib-online.sh"

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

# residue [<namespace>...]: the OcuTalon residue of the instance, one CHK|residue|<where>|<what>|<count> line each, in
# $tmp/residue.chk, and the number of lines it prints in $residue_want.
#   for each namespace (default USER, %SYS and OCUTALON when it exists): the OcuTalon* class definitions, compiled classes and
#   routine objects, and the ocutalon module record; for the namespaces but OCUTALON also the ^OcuTalon* globals; with no namespace
#   given, also instance-wide the OcuTalon* roles, the user ocutalon and the /ocutalon* web applications.
residue() {
  local ns where scope=("$@")
  : > "$tmp/residue.chk"
  residue_want=0
  if [ "${#scope[@]}" -eq 0 ]; then scope=(USER %SYS OCUTALON); fi
  for ns in "${scope[@]}"; do
    if [ "$ns" = OCUTALON ] && ! grep -q '^CHK|ns|' "$tmp/last-snapshot" 2>/dev/null; then continue; fi
    where=$ns
    residue_want=$((residue_want + 4))
    printf '%s\n' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|'"$where"'|classes|",rs.%GetData(1)' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|'"$where"'|compiled|",rs.%GetData(1)' \
      'Set n=0,r="OcuTal" For { Set r=$Order(^rOBJ(r)) Quit:$Extract(r,1,6)'"'"'="OcuTal"  Set:$Extract(r,1,8)="OcuTalon" n=n+1 } Write !,"CHK|residue|'"$where"'|routines|",n' \
      'Write !,"CHK|residue|'"$where"'|module|",+##class(%IPM.Storage.Module).NameExists("ocutalon")' \
      'Halt' | iris_script "$ns" >> "$tmp/residue.chk"
    if [ "$ns" != OCUTALON ]; then
      residue_want=$((residue_want + 1))
      printf '%s\n' \
        'Set n=0,g="^OcuTal" For { Set g=$Order(^$GLOBAL(g)) Quit:$Extract(g,1,7)'"'"'="^OcuTal"  Set:$Extract(g,1,9)="^OcuTalon" n=n+1 } Write !,"CHK|residue|'"$where"'|globals|",n' \
        'Halt' | iris_script "$ns" >> "$tmp/residue.chk"
    fi
  done
  if [ "$#" -eq 0 ]; then
    residue_want=$((residue_want + 3))
    printf '%s\n' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Roles WHERE Name %STARTSWITH ?","OcuTalon") Do rs.%Next() Write !,"CHK|residue|instance|roles|",rs.%GetData(1)' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Users WHERE Name = ?","ocutalon") Do rs.%Next() Write !,"CHK|residue|instance|user|",rs.%GetData(1)' \
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Security.Applications WHERE Name %STARTSWITH ?","/ocutalon") Do rs.%Next() Write !,"CHK|residue|instance|webapps|",rs.%GetData(1)' \
      'Halt' | iris_script %SYS >> "$tmp/residue.chk"
  fi
}

# check_no_residue <label> [<namespace>...]: residue prints every count (13 outside OCUTALON, 17 with it, with no namespace given), and
# every count is 0.
check_no_residue() {
  local label=$1
  shift
  residue "$@"
  if [ "$(grep -c . "$tmp/residue.chk")" -eq "$residue_want" ] && ! grep -v '|0$' "$tmp/residue.chk" | grep -q .; then
    if [ "$#" -eq 0 ]; then
      pass "$label: no OcuTalon class, routine or module record in USER, %SYS or OCUTALON, no ^OcuTalon global in USER or %SYS, and no OcuTalon role, user or web application ($(grep -c . "$tmp/residue.chk") counts, all 0)"
    else
      pass "$label: no OcuTalon class, routine, module record or ^OcuTalon global in $* ($(grep -c . "$tmp/residue.chk") counts, all 0)"
    fi
  else
    grep -v '|0$' "$tmp/residue.chk" | sed 's/^/  residue: /'
    fail "$label: OcuTalon residue (a count above 0), or $(grep -c . "$tmp/residue.chk") counts printed instead of $residue_want"
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

# --- the second run (Story 15.2) ---

# chk <name> < script: the value of the CHK|<name>| line that the script prints, run in the namespace OCUTALON.
chk() { session_value OCUTALON "$1"; }

# step_names <file>: the names of the STEP lines between Configure START and Configure SUCCESS in the plain output, as a comma list,
# a name that did not end OK shown as name(status).
step_names() {
  awk '/Configure START/ { on = 1; next } /Configure SUCCESS/ { on = 0 }
    on && /^STEP / { printf "%s%s", sep, ($3 == "OK") ? $2 : $2 "(" $3 ")"; sep = "," }' "$1"
}

# api <path>: GET of /ocutalon/api/v1/<path> with the cookie jar $ocu_jar.
api() { next_probe; curl -s --max-time 30 -b "$ocu_jar" -c "$ocu_jar" "$base/ocutalon/api/v1/$1&probe=$probes"; }

# state_facts: "<onlineDemo>|<demoMode>|<which of guide, phone and mailbox the body has>" of /state, or "error" when it is no JSON.
state_facts() {
  api "state?x=1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(String(j.onlineDemo)+"|"+String(j.demoMode)+"|"+["guide","phone","mailbox"].filter(k=>k in j).join(","))}catch(e){console.log("error")}})'
}

# turn_verdict <events file> <client id>: "done <chat fallbackReason> <decision fallbackReason>" (absent, empty or the value; n/a when the
# turn has no decision) when the turn is done, otherwise "waiting".
turn_verdict() {
  node -e '
const fs = require("fs");
const [file, clientId] = process.argv.slice(1);
let body;
try { body = JSON.parse(fs.readFileSync(file, "utf8")); } catch { console.log("unreadable"); process.exit(0); }
const mine = (body.events || []).filter((e) => e.type === "chat.message" && e.payload && e.payload.clientId === clientId);
const done = mine.find((e) => e.payload.state === "done");
const reason = (o) => (o && "fallbackReason" in o ? (o.fallbackReason === "" ? "empty" : o.fallbackReason) : "absent");
console.log(done ? `done ${reason(done.payload)} ${done.payload.decision ? reason(done.payload.decision) : "n/a"}` : "waiting");' "$1" "$2"
}

# chat_turn: the README account (the jar $ocu_jar) posts a message and polls the events up to 45 times, 2 s apart; prints
# "<POST status> <verdict of the turn>".
chat_turn() {
  local client code n=0 verdict=waiting
  client="zz-ipm-$(date +%s)"
  next_probe
  code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$ocu_jar" -c "$ocu_jar" -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" \
    --data "{\"clientId\":\"$client\",\"text\":\"zz ipm install hello\",\"fromGuide\":false}" "$base/ocutalon/api/v1/messages?probe=$probes")
  while [ "$n" -lt 45 ]; do
    n=$((n + 1))
    api "events?after=0&afterInstance=0" > "$tmp/turn.events"
    verdict=$(turn_verdict "$tmp/turn.events" "$client")
    case $verdict in done*) break ;; esac
    sleep 2
  done
  printf '%s %s' "$code" "$verdict"
}

# reconcile_rows: the number of Info rows that ReconcileIn logged.
reconcile_rows() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 4 AND Text = ?","ReconcileIn",##class(OcuTalon.Install.ReconcileIn).#LOGTEXT) Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)' \
    'Halt' | chk rows
}
reconcile_rows_above() { [ "$(reconcile_rows)" -gt "$1" ]; }

# other_state <file>: the namespaces other than OCUORDERS and its two databases (which list as namespaces) and USER's mappings, one CHK line each, sorted.
other_state() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM Config.Namespaces ORDER BY Name") While rs.%Next() { Write:$Extract(rs.%GetData(1),1,9)'"'"'="OCUORDERS" !,"CHK|namespace|",rs.%GetData(1) }' \
    'For q="MapGlobals","MapPackages","MapRoutines" { Set rs=##class(%ResultSet).%New("Config."_q_":List") Set sc=rs.Execute("USER") While rs.Next() { Write !,"CHK|umap-",q,"|",rs.Get("Name"),"|",rs.Get("Database") } }' \
    'Halt' | iris_script %SYS | sort > "$1"
}

# orders_state: "<namespace exists>|<code db exists>|<data db exists>" of OCUORDERS.
orders_state() {
  printf '%s\n' \
    'Write !,"CHK|orders|",+##class(Config.Namespaces).Exists("OCUORDERS"),"|",+##class(Config.Databases).Exists("OCUORDERS_CODE"),"|",+##class(Config.Databases).Exists("OCUORDERS_DATA")' \
    'Halt' | session_value %SYS orders
}
orders_gone() { [ "$(orders_state)" = "0|0|0" ]; }

# orders_running: 1 when OcuTalon.Demo.Orders.Production runs in OCUORDERS.
orders_running() {
  printf '%s\n' \
    'Write !,"CHK|run|" Set $Namespace="OCUORDERS" Do ##class(Ens.Director).IsProductionRunning(.n) Write +($Get(n)="OcuTalon.Demo.Orders.Production")' \
    'Halt' | session_value %SYS run
}
orders_up() { [ "$(orders_running)" = 1 ]; }

# check_second_run: matrix row "Second run, path A". The output is in $tmp/second-ocutalon.txt.
check_second_run() {
  local f="$tmp/second-ocutalon.txt" order got phase ok=1
  order=$(printf '%s\n' 'Write !,"CHK|order|",$ListToString(##class(OcuTalon.Install.Registry).Order(),",")' 'Halt' | chk order)
  got=$(step_names "$f")
  for phase in Initialize Reload Validate Compile Configure Activate; do
    grep -q "$phase SUCCESS" "$f" || { echo "  no '$phase SUCCESS' line"; ok=0; }
  done
  if grep -q 'FAILURE' "$f" || grep -q '^ERROR!' "$f"; then ok=0; fi
  if [ "$ok" = 1 ] && [ -n "$order" ] && [ "$got" = "$order" ]; then
    pass "second run: Initialize to Activate SUCCESS, and one STEP OK line per step of Registry.Order(), in that order ($(echo "$order" | tr ',' '\n' | grep -c .) steps)"
  else
    echo "  steps wanted: $order"
    echo "  steps got:    $got"
    fail "second run: the output is not Initialize to Activate SUCCESS with one STEP OK line per step of the order"
  fi
  check_session "second run: the production runs with nothing missing, is the autostart production, and the module has no dependency" OCUTALON \
    "CHK|running|1|OcuTalon.Production
CHK|notrunning|
CHK|unresolved|
CHK|autostart|OcuTalon.Production
CHK|module|ocutalon|0" \
    'Set r=##class(Ens.Director).IsProductionRunning(.n) Write !,"CHK|running|",r,"|",$Get(n)' \
    'Write !,"CHK|notrunning|",##class(OcuTalon.Install.Step.Production).NotRunning()' \
    'Write !,"CHK|unresolved|",##class(OcuTalon.Install.Step.Production).UnresolvedRunners("OcuTalon.Production")' \
    'Write !,"CHK|autostart|",$Get(^Ens.AutoStart)' \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|module|",$Select($IsObject(m):m.Name_"|"_m.Dependencies.Count(),1:"<none>")' \
    'Halt'
  take_snapshot second "second run"
  same_services "second run" base second
  check_no_residue "second run" USER %SYS
  check_session "second run: PasswordValidationRoutine is still empty" %SYS "CHK|pwd|" \
    'Do ##class(Security.System).Get(,.p) Write !,"CHK|pwd|",$Get(p("PasswordValidationRoutine"))' 'Halt'
}

# check_install: matrix row "Install checks".
check_install() {
  local f="$tmp/second-ocutalon.txt"
  check_session "install checks: the public package and global are in OCUTALON_PUBLIC, the private globals in OCUTALON_PRIVATE" OCUTALON \
    "CHK|web|ocutalon_public
CHK|data|ocutalon_public
CHK|OcuTalonPublic|ocutalon_public
CHK|OcuTalonP.S01|ocutalon_private
CHK|OcuTalonBP.S01|ocutalon_private
CHK|AI.Agent.SessionD|ocutalon_private
CHK|IRIS.IF.S01|ocutalon_private" \
    'Set d=##class(%SYS.Namespace).GetPackageDest("OCUTALON","OcuTalon.Web.Public") Write !,"CHK|web|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Set d=##class(%SYS.Namespace).GetPackageDest("OCUTALON","OcuTalon.Data.Public") Write !,"CHK|data|",$Piece(d,"/",$Length(d,"/")-1)' \
    'For g="OcuTalonPublic","OcuTalonP.S01","OcuTalonBP.S01","AI.Agent.SessionD","IRIS.IF.S01" { Set d=##class(%SYS.Namespace).GetGlobalDest("OCUTALON","^"_g) Write !,"CHK|",g,"|",$Piece(d,"/",$Length(d,"/")-1) }' \
    'Halt'
  if grep -q '^STEP PrivateData OK' "$f"; then
    pass "install checks: the output has STEP PrivateData OK"
  else
    fail "install checks: the output has no STEP PrivateData OK"
  fi
  check_session "install checks: index.html is in the /ocutalon application's Path" %SYS \
    "CHK|index|1
CHK|samepath|1" \
    'Set d=$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/" Write !,"CHK|index|",+##class(%File).Exists(d_"index.html")' \
    'Do ##class(Security.Applications).Get("/ocutalon",.ap) Write !,"CHK|samepath|",+(##class(%File).NormalizeDirectory($Get(ap("Path")))=##class(%File).NormalizeDirectory(d))' \
    'Halt'
  check_session "install checks: onlineDemo is 0 and ready is 1, and the public settings sit in the public database" OCUTALON \
    "CHK|onlineDemo|0
CHK|ready|1
CHK|settings-dest|ocutalon_public" \
    'Write !,"CHK|onlineDemo|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
    'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
    'Set d=##class(%SYS.Namespace).GetRoutineDest("OCUTALON","OcuTalon.Data.Public.Settings.1","INT") Write !,"CHK|settings-dest|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Halt'
}

# check_web: matrix row "Web and REST". The chat check points the keys at the CI mock before and back after, also on a failure.
check_web() {
  local code facts turn
  ocu_jar="$tmp/jar.ocu"
  : > "$ocu_jar"
  next_probe
  curl -s --max-time 30 -b "$ocu_jar" -c "$ocu_jar" -o "$tmp/signin.page" "$base/ocutalon/?probe=$probes"
  if grep -q 'Sign in to OcuTalon' "$tmp/signin.page" && ! grep -q 'Try OcuTalon in two minutes' "$tmp/signin.page"; then
    pass "web: GET /ocutalon/ serves the sign-in page and not the online demo's"
  else
    fail "web: GET /ocutalon/ does not serve 'Sign in to OcuTalon' (or serves the online demo's page)"
  fi
  code=$(online_signin "$ocu_jar" "" "" ocutalon ocutalon)
  if grep -q '<app-root' "$ocu_jar.b"; then
    pass "web: ocutalon/ocutalon signs in (the app root is served, sign-in status $code)"
  else
    fail "web: ocutalon/ocutalon does not sign in (status $code)"
  fi
  facts=$(state_facts)
  if [ "$facts" = "false|false|" ]; then
    pass "web: /state has onlineDemo false and demoMode false, and no guide, phone or mailbox"
  else
    fail "web: /state is '$facts', wanted 'false|false|'"
  fi
  next_probe
  code=$(curl -s --max-time 30 -b "$ocu_jar" -c "$ocu_jar" -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" -d '{}' "$base/ocutalon/api/v1/demo/break-feed?probe=$probes")
  if [ "$code" = 404 ]; then pass "web: POST demo/break-feed answers 404"; else fail "web: POST demo/break-feed answered '$code'"; fi
  if [ "$(orders_state)" = "0|0|0" ]; then pass "web: OCUORDERS does not exist"; else fail "web: OCUORDERS state is '$(orders_state)'"; fi
  if [ "$(keys_point)" = 1 ]; then
    turn=$(chat_turn)
    case $turn in
      "202 done "*)
        set -- $turn
        if [ "$3" != absent ] && [ "$3" != empty ]; then
          fail "web: the chat turn's reply carries fallbackReason '$3' (the keys point at the CI mock)"
        elif [ "$4" = n/a ]; then
          fail "web: the chat turn is done but carries no decision"
        elif [ "$4" != absent ] && [ "$4" != empty ]; then
          fail "web: the chat turn's decision carries fallbackReason '$4' (the keys point at the CI mock)"
        else
          pass "web: a chat message ends in a done turn whose decision has no fallbackReason"
        fi
        ;;
      *) fail "web: the chat message did not end in a done turn: '$turn'" ;;
    esac
  else
    fail "web: the model keys could not be pointed at the CI mock"
  fi
  if [ "$(keys_restore)" != 1 ]; then fail "web: the model keys could not be restored to the placeholder"; fi
  logout_all "$ocu_jar" /ocutalon/
}

# check_package: matrix row "Package".
check_package() {
  check_session "package: one ocutalon module, the bridge installer and the example compiled, the example neither running nor the autostart production" OCUTALON \
    "CHK|modules|1
CHK|installer|1
CHK|example|1
CHK|notrun|1
CHK|notauto|1" \
    'Set table=##class(%Dictionary.CompiledClass).%OpenId("%IPM.Storage.Module").SqlQualifiedNameQ Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_table_" WHERE Name %STARTSWITH ?","ocutalon") Do rs.%Next() Write !,"CHK|modules|",rs.%GetData(1)' \
    'Write !,"CHK|installer|",+##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Bridge.Installer")' \
    'Write !,"CHK|example|",+##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.BridgeExample.Production")' \
    'Do ##class(Ens.Director).IsProductionRunning(.n) Write !,"CHK|notrun|",+($Get(n)'"'"'="OcuTalon.BridgeExample.Production")' \
    'Write !,"CHK|notauto|",+($Get(^Ens.AutoStart)'"'"'="OcuTalon.BridgeExample.Production")' \
    'Halt'
}

# check_demo_switch: matrix row "Demo switch", through run so that the output is kept.
check_demo_switch() {
  local text_on text_off
  text_on=$(printf '%s\n' 'Write !,"CHK|text|",##class(OcuTalon.Core.SettingsOps).#MESSAGEON' 'Halt' | chk text)
  text_off=$(printf '%s\n' 'Write !,"CHK|text|",##class(OcuTalon.Core.SettingsOps).#MESSAGEOFF' 'Halt' | chk text)
  other_state "$tmp/other-before.chk"
  run demo-on OCUTALON 'Do ##class(OcuTalon.Core.Admin).SetDemoMode(1)'
  if [ -n "$text_on" ] && grep -qF -- "$text_on" "$tmp/demo-on.txt"; then
    pass "demo switch: SetDemoMode(1) prints SettingsOps' MESSAGEON line"
  else
    fail "demo switch: SetDemoMode(1) did not print the MESSAGEON line"
  fi
  wait_until 120 orders_up || true
  check_session "demo switch: on, OCUORDERS and both databases are under the manager directory, the public package and global are mapped, and the Orders production runs" %SYS \
    "CHK|orders|1|1|1
CHK|dirs|1|1
CHK|web|ocutalon_public
CHK|data|ocutalon_public
CHK|global|ocutalon_public
CHK|run|1" \
    'Write !,"CHK|orders|",+##class(Config.Namespaces).Exists("OCUORDERS"),"|",+##class(Config.Databases).Exists("OCUORDERS_CODE"),"|",+##class(Config.Databases).Exists("OCUORDERS_DATA")' \
    'Set mgr=$SYSTEM.Util.ManagerDirectory() Kill p Do ##class(Config.Databases).Get("OCUORDERS_CODE",.p) Set c=+(##class(%File).NormalizeDirectory(p("Directory"))=##class(%File).NormalizeDirectory(mgr_"ocuorders_code")) Kill p Do ##class(Config.Databases).Get("OCUORDERS_DATA",.p) Write !,"CHK|dirs|",c,"|",+(##class(%File).NormalizeDirectory(p("Directory"))=##class(%File).NormalizeDirectory(mgr_"ocuorders_data"))' \
    'Set d=##class(%SYS.Namespace).GetPackageDest("OCUORDERS","OcuTalon.Web.Public") Write !,"CHK|web|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Set d=##class(%SYS.Namespace).GetPackageDest("OCUORDERS","OcuTalon.Data.Public") Write !,"CHK|data|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Set d=##class(%SYS.Namespace).GetGlobalDest("OCUORDERS","^OcuTalonPublic") Write !,"CHK|global|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Write !,"CHK|run|" Set $Namespace="OCUORDERS" Do ##class(Ens.Director).IsProductionRunning(.n) Write +($Get(n)="OcuTalon.Demo.Orders.Production")' \
    'Halt'
  other_state "$tmp/other-on.chk"
  if diff "$tmp/other-before.chk" "$tmp/other-on.chk" > "$tmp/other.diff"; then
    pass "demo switch: with demo mode on the instance's other namespaces and USER's mappings are unchanged"
  else
    sed 's/^/  other: /' "$tmp/other.diff"
    fail "demo switch: the other namespaces or USER's mappings changed when demo mode went on"
  fi
  run demo-off OCUTALON 'Do ##class(OcuTalon.Core.Admin).SetDemoMode(0)'
  if [ -n "$text_off" ] && grep -qF -- "$text_off" "$tmp/demo-off.txt"; then
    pass "demo switch: SetDemoMode(0) prints SettingsOps' MESSAGEOFF line"
  else
    fail "demo switch: SetDemoMode(0) did not print the MESSAGEOFF line"
  fi
  wait_until 120 orders_gone || true
  if orders_gone; then
    pass "demo switch: off, namespace OCUORDERS and both databases are gone"
  else
    fail "demo switch: after SetDemoMode(0) OCUORDERS state is '$(orders_state)' (namespace|code|data), wanted 0|0|0"
  fi
  other_state "$tmp/other-off.chk"
  if diff "$tmp/other-before.chk" "$tmp/other-off.chk" > "$tmp/other.diff"; then
    pass "demo switch: with demo mode off again the instance's other namespaces and USER's mappings are unchanged"
  else
    sed 's/^/  other: /' "$tmp/other.diff"
    fail "demo switch: the other namespaces or USER's mappings changed when demo mode went off"
  fi
}

# check_start_outside: matrix row "Start outside the step".
check_start_outside() {
  local before after n
  before=$(reconcile_rows)
  run stop-start OCUTALON "$(printf '%s\n' 'Do ##class(Ens.Director).StopProduction(30,0)' 'Set sc=##class(Ens.Director).StartProduction("OcuTalon.Production") Write !,"CHK|start|",$SYSTEM.Status.IsOK(sc)')"
  wait_until 60 reconcile_rows_above "$before" || true
  after=$(reconcile_rows)
  sleep 15
  n=$(reconcile_rows)
  if [ "$after" = "$((before + 1))" ] && [ "$n" = "$after" ]; then
    pass "start outside the step: ReconcileIn logged one new Info row after a session's start, and no second one after three more polls ($before -> $after -> $n)"
  else
    fail "start outside the step: ReconcileIn's Info rows went $before -> $after, then $n; wanted one more and then no more"
  fi
}

# check_start_by_step: matrix row "Start by the step".
check_start_by_step() {
  local before after
  before=$(reconcile_rows)
  run by-step OCUTALON 'Set sc=##class(OcuTalon.Install.Registry).Run("ipm") Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)'
  sleep 15
  after=$(reconcile_rows)
  if grep -q '^STEP Reconcile OK' "$tmp/by-step.txt" && ! grep -q 'FAILED' "$tmp/by-step.txt" && [ "$after" = "$before" ]; then
    pass "start by the step: Registry.Run(\"ipm\") ends with STEP Reconcile OK, and ReconcileIn logged no new Info row in 15 s ($before -> $after)"
  else
    fail "start by the step: STEP Reconcile OK missing or a step failed, or ReconcileIn's Info rows went $before -> $after"
  fi
}

# --- path B (Story 15.2): a foreign password-validation routine and a foreign OCUORDERS ---

# foreign_orders: one line, "<globals>/<routines>|<OCUFOREIGN databases exist>|<OCUORDERS databases exist>", of the foreign OCUORDERS.
foreign_orders() {
  printf '%s\n' \
    'Kill p Set sc=##class(Config.Namespaces).Get("OCUORDERS",.p) Write !,"CHK|foreign|",$Get(p("Globals")),"/",$Get(p("Routines")),"|",+##class(Config.Databases).Exists("OCUFOREIGN_CODE"),+##class(Config.Databases).Exists("OCUFOREIGN_DATA"),"|",+##class(Config.Databases).Exists("OCUORDERS_CODE"),+##class(Config.Databases).Exists("OCUORDERS_DATA")' \
    'Halt' | session_value %SYS foreign
}

# --- the stack ---

setup_tag
preflight
live_start ipm
live_add_file "$root/release/ipm/compose.ipm.yml"
live_web_port || exit 1
base="http://127.0.0.1:$web_port"
probe_file="$tmp/probe.n"
echo 0 > "$probe_file"
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

run shell-user USER 'Set sc=##class(%IPM.Main).Shell("load '"$SRC"'") Write !,"CHK|shell|",$SYSTEM.Status.IsOK(sc),"|",$SYSTEM.Process.TransactionsSuspended(),"|",$TLevel,"|",$SYSTEM.Status.GetOneStatusText(sc)'
shell_chk=$(sed -n 's/.*\(CHK|shell|.*\)$/\1/p' "$tmp/shell-user.txt" | tail -n 1)
if [ "$shell_chk" = "CHK|shell|0|0|0|$STOP" ]; then
  pass "the install through Shell() in USER: an error whose text is the stop sentence, and transactions neither suspended nor open afterwards"
else
  echo "  got: '$shell_chk', wanted 'CHK|shell|0|0|0|$STOP' (IsOK|suspended|TLevel|text)"
  fail "the install through Shell() in USER: not an error with the stop sentence, or transactions left suspended or open"
fi
check_no_residue "the install through Shell() in USER"

check_session "IPM answers in OCUTALON, so the next command can start there" OCUTALON \
  "CHK|version|1" \
  'Set sc=##class(%IPM.Main).Shell("version") Write !,"CHK|version|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'

# --- path A: the second run ---

if [ "$mode" != b ]; then
  run second-ocutalon OCUTALON "$INSTALL"
  check_second_run
  check_install
  check_web
  check_package
  check_demo_switch
  check_start_outside
  check_start_by_step
fi

if [ "$mode" = a ]; then
  if [ "$fails" -ne 0 ]; then
    echo "$(basename "$SCRIPT" .sh): $fails check(s) failed (project $P)"
    exit 1
  fi
  echo "$(basename "$SCRIPT" .sh): all checks passed"
  exit 0
fi

# --- path B: iris merge on a fresh instance ---

echo "PATH B: iris merge of /opt/ocutalon-ipm/src/cpf/ocutalon.cpf on a fresh instance"
started=$SECONDS
dc down -v > "$tmp/down.log" 2>&1
if ! dc up -d --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "the second stack did not become ready"
fi
echo "TIME ready-b $((SECONDS - started))s"
fails_before_load=$fails
check_session "path B: IPM 0.10.10 is loaded in %SYS of the fresh instance" %SYS "CHK|load|1" \
  'Set sc=$SYSTEM.OBJ.Load("/opt/ocutalon-ipm/zpm-0.10.10.xml","ck-d") Write !,"CHK|load|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'
if [ "$fails" -ne "$fails_before_load" ]; then die "IPM could not be loaded on the fresh instance"; fi
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

# --- path B: the install command on the merged instance, with things of its own ---

run enable-ocutalon %SYS 'zpm "enable -map -ns OCUTALON"'
check_session "path B: IPM is enabled for OCUTALON, so the next command can start there" OCUTALON \
  "CHK|version|1" \
  'Set sc=##class(%IPM.Main).Shell("version") Write !,"CHK|version|",$SYSTEM.Status.IsOK(sc)' \
  'Halt'
# The foreign password-validation routine (DW-212), after the routine of Test.Install.Users MakeForeign, and the foreign OCUORDERS, after
# test-install-start.sh's: databases that OcuTalon did not create.
check_session "path B: a foreign password-validation routine and a foreign OCUORDERS are built" %SYS \
  "CHK|routine|1
CHK|setting|ZzOther^ZzForeign
CHK|built|1" \
  'Set routine=##class(%Routine).%New("ZzForeign.mac") Do routine.WriteLine("ZzForeign ; a fixture, another password-validation routine") Do routine.WriteLine($Char(9)_"Quit") Do routine.WriteLine("ZzOther(user,password) Public {") Do routine.WriteLine($Char(9)_"Quit 1") Do routine.WriteLine("}") Set sc=routine.Save() Set:$SYSTEM.Status.IsOK(sc) sc=routine.Compile("-d") Write !,"CHK|routine|",$SYSTEM.Status.IsOK(sc)&&##class(%Routine).Exists("ZzForeign.mac")' \
  'Set p("PasswordValidationRoutine")="ZzOther^ZzForeign" Set sc=##class(Security.System).Modify("SYSTEM",.p) Kill p Do ##class(Security.System).Get(,.p) Write !,"CHK|setting|",$Get(p("PasswordValidationRoutine"))' \
  'Set mgr=$SYSTEM.Util.ManagerDirectory()' \
  'For n="CODE","DATA" { Set dir=mgr_"ocuforeign_"_$ZConvert(n,"L")_"/" Set ok=##class(%File).CreateDirectoryChain(dir) Set sc=##class(SYS.Database).CreateDatabase(dir) Kill p Set p("Directory")=dir Set sc2=##class(Config.Databases).Create("OCUFOREIGN_"_n,.p) Set built(n)=(ok&&$SYSTEM.Status.IsOK(sc)&&$SYSTEM.Status.IsOK(sc2)) }' \
  'Kill p Set p("Globals")="OCUFOREIGN_DATA",p("Routines")="OCUFOREIGN_CODE" Set sc=##class(Config.Namespaces).Create("OCUORDERS",.p) Write !,"CHK|built|",(built("CODE")&&built("DATA")&&$SYSTEM.Status.IsOK(sc))' \
  'Halt'
take_snapshot enabled-b "path B"
foreign_before=$(foreign_orders)

run second-merge OCUTALON "$INSTALL"
take_snapshot second-merge "path B second run"
order=$(printf '%s\n' 'Write !,"CHK|order|",$ListToString(##class(OcuTalon.Install.Registry).Order(),",")' 'Halt' | chk order)
got=$(step_names "$tmp/second-merge.txt")
if [ -n "$order" ] && [ "$got" = "$order" ] && ! grep -q 'FAILURE' "$tmp/second-merge.txt" && ! grep -q '^ERROR!' "$tmp/second-merge.txt"; then
  pass "path B: every STEP line of the install command is OK, in the order of Registry.Order()"
else
  echo "  steps wanted: $order"
  echo "  steps got:    $got"
  fail "path B: the install command did not end with every STEP OK"
fi
if [ "$(grep -c '^WARN Demo ' "$tmp/second-merge.txt")" = 1 ] && grep -q '^WARN Demo .*OCUORDERS' "$tmp/second-merge.txt"; then
  pass "path B: WARN Demo names the kept namespace OCUORDERS"
else
  grep '^WARN ' "$tmp/second-merge.txt" | sed 's/^/  /'
  fail "path B: no single WARN Demo line that names OCUORDERS"
fi
check_session "path B: the foreign password-validation setting and routine are unchanged" %SYS \
  "CHK|setting|ZzOther^ZzForeign
CHK|routine|1" \
  'Do ##class(Security.System).Get(,.p) Write !,"CHK|setting|",$Get(p("PasswordValidationRoutine"))' \
  'Write !,"CHK|routine|",+##class(%Routine).Exists("ZzForeign.mac")' \
  'Halt'
foreign_after=$(foreign_orders)
if [ -n "$foreign_before" ] && [ "$foreign_before" = "$foreign_after" ]; then
  pass "path B: the foreign OCUORDERS and its databases are unchanged ($foreign_after)"
else
  fail "path B: the foreign OCUORDERS changed, from '$foreign_before' to '$foreign_after'"
fi
same_services "path B second run" base-b second-merge

if [ "$fails" -ne 0 ]; then
  echo "$(basename "$SCRIPT" .sh): $fails check(s) failed (project $P)"
  exit 1
fi
echo "$(basename "$SCRIPT" .sh): all checks passed"
