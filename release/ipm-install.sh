#!/usr/bin/env bash
# The first install run of the IPM package (Story 15.1; AD-2, AD-3, AD-22, AD-23, AD-29; FR-57, REL-4): proves in throwaway stacks of
# a clean build 154 instance, an instance like an admin's with IPM 0.10.10 in %SYS and enabled for USER only, that the package's
# first run creates OCUTALON and gives the next command, and that `iris merge` of the package's CPF file is the alternative. It is
# the ipm-install job of .github/workflows/lane-a.yml and runs the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash release/ipm-install.sh [a|r|b|p]
# It sources ci/iris.sh (which sources ci/units.sh and docker/tests/lib-live.sh) and runs nothing of them but the throwaway recipe:
# a project of its own from release/ipm/Dockerfile (no merge file, after-start script or version file; release/ipm/compose.ipm.yml),
# the CI override, the throwaway lock and the teardown on exit. Stories 15.2 and 15.3 extend the functions snapshot, residue and
# run. The checks:
#   Path A, two package runs:
#   1. the precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER; OCUTALON does not exist yet;
#   2. `zpm "load /opt/ocutalon-ipm/src"` in USER stops after Initialize: the output shows Initialize FAILURE, no Reload START and no
#      STEP line, and its last line, with ANSI codes removed, is exactly the stop sentence after `ERROR! `;
#   3. the run created the four OCUTALON databases (public Read on %DB_OCUTALON_PUBLIC only), OCUTALON with Interoperability and
#      AD-3's seven mappings, mapped %IPM into OCUTALON from the database where %IPM resolves in USER, and mapped IPM's repository
#      definitions (^IPM.Repo.DefinitionD, S and I) into OCUTALON from the database where each resolves in USER (U-232), as they are;
#      OCUTALON_DATA holds no ^IPM.Repo.Definition* node; the services are those of the baseline;
#   4. nothing of OcuTalon is left: no OcuTalon class, routine or module record in USER, %SYS or OCUTALON, no ^OcuTalon global
#      in USER or %SYS, no OcuTalon role, no user ocutalon and no /ocutalon web application;
#   5. a first run in %SYS, made on the fresh instance before check 2, is refused by IPM because src/module.xml declares
#      SystemRequirements with Interoperability enabled (U-231): the last line is exactly `ERROR! This module requires an
#      interoperability-enabled namespace. %SYS is not interoperability-enabled.`, no Initialize START line is printed, and the
#      configuration, the services and the residue are those of the precondition (nothing is created or left behind). Then the same
#      command again in USER gives the same stop, the same configuration and no residue, and the same install through
#      %IPM.Main.Shell() in USER returns the stop sentence as an error status (the stop is not reported as a success), leaves
#      transactions neither suspended nor open in the session, and leaves no residue;
#   6. IPM answers in OCUTALON (%IPM.Main.Shell("version") returns OK), so the next command can start there;
#   Path B, `iris merge`:
#   7. on a fresh instance from the same image, `iris merge IRIS /opt/ocutalon-ipm/src/cpf/ocutalon.cpf` exits 0 and gives the same
#      OCUTALON namespace, Interoperability flag, databases, resources and OCUTALON mappings as path A, minus the %IPM mappings
#      and the repository mappings, and the services are unchanged.
# Story 15.2 adds the second run:
#   Path A, after check 6, the same install command in OCUTALON:
#   8. the output shows Initialize to Activate SUCCESS and, between Configure START and Configure SUCCESS, one `STEP <name> OK` line
#      per name of Registry.Order(), in that order; the production runs with no item missing and no runner without a model,
#      ^Ens.AutoStart is OcuTalon.Production, the module is recorded with 0 dependencies, the services are the baseline's, the
#      configuration is the first run's (the snapshot of check 3: OCUTALON, its databases, resources and mappings, USER's mappings), USER
#      and %SYS hold no OcuTalon class, routine, module record or global, and PasswordValidationRoutine is still empty;
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
# U-176 adds, after the second run's checks, failed reinstalls from test-only scratch copies of the package folder in the container (the
# shipped package has no switch that fails a step or a compile; the source tree is not edited). Each run's output is kept like every run's:
#   16. a reinstall whose Audit step fails (the scratch copy's Audit.Run returns an error): IPM reports Configure FAILURE and ends with
#      ERROR! and the step's text, no Activate SUCCESS; the STEP lines are the order up to Audit, and the line after Audit's own is the one
#      line of Registry.Ipm naming Audit, saying the new code is installed and to run the same command again; a status mark seeded before
#      is read back by value, and the configuration (OCUTALON, its four databases,
#      resources and mappings, USER's mappings, the services) and the residue check are those of the second run;
#   17. the real folder again: every check of the second run (checks 8 to 14) passes again, the module is back at the real version and the
#      seeded mark is still there;
#   18. a reinstall whose Compile fails (a scratch copy with a class that does not compile and a changed Registry.Order()): IPM reports the
#      failure and no step runs, and the previous version keeps running: the production runs with nothing missing, Registry.Order() answers as
#      before, the module version is unchanged, the scratch class is absent, the mark is kept and the configuration is unchanged.
# Story 15.3 adds the durability checks and Story 9.1's IPM case:
#   19. Story 9.1's IPM case, after every full install (path A's second run, the recovery run of check 20, path B's second run and
#       the reinstall of check 25): the default setting OcuTalon.Production||EvalIn||*||Enabled is 0, CreateBusinessService("EvalIn")
#       fails with a text containing `is disabled`, the production's TestingEnabled is 0, and EvalIn has no Alive job while other
#       items have theirs;
#   20. part r seeds a session with a turn, a live reminder (due in one day) and a lost approval before the forced failure; after the
#       recovery run the session and its turn are read back unchanged, the reminder has one waiter, the approval has one hold, and
#       every item's job differs from before the failed reinstall;
#   Path B, after check 15's install and Story 9.1's case, on the same stack, in this order:
#   21. a production stop and start alone from a session (DW-80), with no installer run: ReconcileIn logs exactly one new Info row,
#       a lost reminder has one waiter and one more start header, from HeartbeatIn, a lost approval has one hold, and the live reminder
#       keeps its waiter and its one start from ReminderOps;
#   22. a first instance restart (docker compose restart iris) with a second lost pair seeded: the production runs with nothing
#       missing, ^Ens.AutoStart is OcuTalon.Production, the container has no /opt/ocutalon/version (no after-start script), ReconcileIn
#       logs exactly one new row, the new pair is re-armed once and the other rows are unchanged;
#   23. a second instance restart: the same, and every row has exactly one waiter or hold with the start counts and hold ids of
#       check 22, so nothing was re-armed twice;
#   24. after the restarts: the session and its turn are unchanged, the live reminder fires once (state fired, no waiter, one
#       ReminderTimer to Notify header), the approval is rejected through Approval.Answer and its hold ends, and the other lost
#       rows are still pending with one waiter or hold;
#   25. the install command with the next version (a scratch copy of the package folder with the patch number raised, loaded in
#       OCUTALON): Initialize to Activate SUCCESS and one STEP OK per step in order, the raised module version, a new job id for
#       every item, no new ReconcileIn row, the configuration and the foreign setting unchanged, and the data and the waiters intact.
#       Story 36.7 (DW-1320): the scratch copy's bundle index.html also gets a comment line, and main-ZZSTALE0.js and zz-admin-note.txt are
#       planted in csp/ocutalon-web/ before the install. Afterwards the module's Root is MEASURED: it is the scratch folder, and the Web step's
#       BuildFolder() is its ocutalon/csp/ (a real IPM install must resolve the root that FileCopy read; if it does not, the run stops
#       with that finding and no workaround). The stale file is gone, the note stays, and the served index.html equals the copy's.
# Story 19.2 (U-294) adds the Python requirement and the model:
#   30. after path A's second run: the install fetched fastembed 0.9.0 through requirements.txt (the module root's file, staged beside
#       src/module.xml by stage_requirements), the output has STEP Memory OK and no WARN Memory line, and <mgr>/fastembed/ holds the model
#       once (one models--Qdrant--all-MiniLM-L6-v2-onnx folder, which the Memory step downloaded in a worker);
#   31. check 25's reinstall downloads nothing new: the folder's file list and sizes are the same before and after, and so are the two Python
#       resources in <mgr>/python (Story 19.6).
# Story 19.6 (U-294) adds the licence-measured pin set and the PDF and Word reading:
#   32. after path A's second run and after part p's install: docker/licences/gate.py check passes on <mgr>/python against the constraints
#       file of the architecture (staged by stage_licence_gate), so every installed distribution is under an allowed licence and is pinned at
#       its installed version, and gate.py notices writes a non-empty file that names every one of the 36 distributions. Story 19.8 (DW-829)
#       adds to check 32, from check_python_pins: certifi, charset_normalizer, idna, requests, typing_extensions and urllib3 import their pinned
#       copies (each __file__ is under <mgr>/python with the sha256 of the pinned dist-info's RECORD, each __version__ is the pin), so that
#       a stale copy of IPM's own dependencies fails the check; the folder's distributions before and after the install differ only in
#       those six moving to the pins and the pins OcuTalon adds, and IPM's own packages (oras.provider and the rest) import as before; zpm
#       "list" answers and the module's early RemoveStaleCopies Invoke gets the module root, the -bypass-py-deps flag and the lifecycle command as
#       arguments. Path A then runs the same install command again: it replaces nothing and the checks hold; then, with a stale copy of
#       idna planted, `zpm "reload ocutalon"` and a load with -bypass-py-deps (no pip step runs in either) remove nothing, and IPM's own
#       packages and zpm "list" still work (DW-856). Part p, after its uninstall, shows that the uninstall
#       leaves the Python folder's distributions in place, IPM still lists and still installs from the local repository;
#   33. after the same two installs: OcuTalon.Docs.Extract.Read of Test.Docs.Samples' 3-page PDF and its headings .docx answers ok with page
#       and heading markers, so the Python resources and the extraction category reached the IPM install. Check 30 also names pdfplumber
#       0.11.10 and python-docx 1.1.2.
# Story 15.4 adds part p, the exact release artifact installed from an IPM repository on a fresh instance with no Node.js:
#   The artifact is OCUTALON_IPM_ARTIFACT (the .tgz that the release sequence's ipm step made), or, when that is unset, the module that
#   path A's second run installed, packaged with `zpm "package ocutalon -only"` (TIME package) and checked with lib-release's
#   ipm_artifact_check, with the layout of what packed it: root for OCUTALON_IPM_ARTIFACT (the ipm step loads the root manifest), src for
#   the module of path A (this script loads src/module.xml); ARTIFACT <name> <bytes> bytes is printed and a problem line fails the part.
#   26. the container has no node and no npm;
#   27. the artifact is unpacked into a local filesystem repository (a repository added in USER with its output discarded), and
#       `zpm "install ocutalon"` in USER ends with the stop line and the snapshot of check 3, repository mappings included;
#   28. the same command in OCUTALON passes the checks of the second run (Initialize to Activate SUCCESS, every STEP OK in order, the
#       production running, autostart, 0 dependencies, Story 9.1's IPM case), /ocutalon/ serves the sign-in page and ocutalon/ocutalon
#       signs in;
#   29. `zpm "uninstall ocutalon"` in OCUTALON removes OCUTALON's three repository mappings and nothing else of the configuration, and a
#       hash of USER's three definition globals, taken inside the container and never printed, is the same right after the uninstall
#       as right before it and as before the first command (U-232).
# The argument chooses the paths: none runs A, the reinstalls (checks 16 to 20), B and part p (the job), `a` path A (checks 1 to 6, 8 to 14
# and 19) only, `r` path A's first and second run and the reinstalls (checks 16 to 20), `b` path A's first run (the reference of path B's
# comparison) and path B (checks 7, 15, 19 and 21 to 25), `p` part p alone (checks 26 to 29; with no OCUTALON_IPM_ARTIFACT it first
# installs the package from the folder and packages it).
# Every run's and the merge's full output is printed between `OUTPUT begin <name>` and `OUTPUT end <name>`, ANSI codes kept; the
# checks read it with the codes removed. `TIME <step> <s>s` lines give the durations. Prints one PASS or FAIL line per check, and
# exits 1 when any fails. The trap of live_start removes the project, its volume and its images, and releases the lock.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
mode=${1:-all}
case $mode in
  all | a | r | b | p) ;;
  *)
    echo "usage: bash release/ipm-install.sh [a|r|b|p]"
    exit 2
    ;;
esac
. "$root/ci/iris.sh"
. "$root/docker/tests/lib-online.sh"
# lib-release.sh (ipm_unpack, ipm_artifact_check) sets umask 077 when sourced; this script keeps the caller's.
umask_before=$(umask)
. "$root/release/lib-release.sh"
umask "$umask_before"

SCRIPT=release/ipm-install.sh
SRC=/opt/ocutalon-ipm/src
INSTALL="zpm \"load $SRC\""
STOP='OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.'
REFUSAL='This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.'

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

# registry_order: Registry.Order() of the installed code in OCUTALON, as a comma list.
registry_order() {
  printf '%s\n' 'Write !,"CHK|order|",$ListToString(##class(OcuTalon.Install.Registry).Order(),",")' 'Halt' | chk order
}

# step_names <file>: the names of the STEP lines between Configure START and Configure SUCCESS in the plain output, as a comma list,
# a name that did not end OK shown as name(status). The line that Registry.Ipm writes after a failed step (STEP <name> FAILED: ...) is not a step.
step_names() {
  awk '/Configure START/ { on = 1; next } /Configure SUCCESS/ { on = 0 }
    on && /^STEP / && $3 != "FAILED:" { printf "%s%s", sep, ($3 == "OK") ? $2 : $2 "(" $3 ")"; sep = "," }' "$1"
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
  grep -q '^CHK|namespace|USER$' "$1" || fail "demo switch: the session that lists the instance's namespaces printed no USER ($(basename "$1"))"
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

# check_ipm_case <label>: Story 9.1's IPM case (check 19) on the running production: EvalIn's default setting row is 0, EvalIn is refused as
# disabled, the production's TestingEnabled is 0, and EvalIn (pool size 0) has no Alive job while other items have theirs (lib-live item_jobs).
check_ipm_case() {
  check_session "$1: Story 9.1's IPM case: EvalIn's default row is 0, EvalIn is refused as disabled and TestingEnabled is 0" OCUTALON \
    "CHK|row|0
CHK|refused|1
CHK|testing|0" \
    'Write !,"CHK|row|",##class(Ens.Config.DefaultSettings).%OpenId("OcuTalon.Production||EvalIn||*||Enabled").SettingValue' \
    'Set sc=##class(Ens.Director).CreateBusinessService("EvalIn",.svc) Write !,"CHK|refused|",($SYSTEM.Status.IsError(sc)&&($SYSTEM.Status.GetErrorText(sc)["is disabled"))' \
    'Write !,"CHK|testing|",+##class(Ens.Config.Production).%OpenId("OcuTalon.Production").TestingEnabled' \
    'Halt'
  item_jobs "$tmp/jobs-ipm-case.tsv"
  if [ -s "$tmp/jobs-ipm-case.tsv" ] && ! cut -f1 "$tmp/jobs-ipm-case.tsv" | grep -qx EvalIn; then
    pass "$1: Story 9.1's IPM case: EvalIn has no Alive job, and $(grep -c . "$tmp/jobs-ipm-case.tsv") other items have theirs"
  else
    fail "$1: Story 9.1's IPM case: EvalIn has an Alive job, or no item has one (items with jobs: $(cut -f1 "$tmp/jobs-ipm-case.tsv" | tr '\n' ' '))"
  fi
}

# check_run_ok <run name> <label>: the install command's output $tmp/<run name>.txt is Initialize to Activate SUCCESS with one STEP OK line
# per step of Registry.Order(), in that order; the production runs with nothing missing, is the autostart production, and the module has no
# dependency; Story 9.1's IPM case holds. Nothing here compares with a reference configuration.
check_run_ok() {
  local name=$1 label=$2 f order got phase ok=1
  f="$tmp/$name.txt"
  order=$(registry_order)
  got=$(step_names "$f")
  for phase in Initialize Reload Validate Compile Configure Activate; do
    grep -q "$phase SUCCESS" "$f" || { echo "  no '$phase SUCCESS' line"; ok=0; }
  done
  if grep -q 'FAILURE' "$f" || grep -q '^ERROR!' "$f"; then ok=0; fi
  if [ "$ok" = 1 ] && [ -n "$order" ] && [ "$got" = "$order" ]; then
    pass "$label: Initialize to Activate SUCCESS, and one STEP OK line per step of Registry.Order(), in that order ($(echo "$order" | tr ',' '\n' | grep -c .) steps)"
  else
    echo "  steps wanted: $order"
    echo "  steps got:    $got"
    fail "$label: the output is not Initialize to Activate SUCCESS with one STEP OK line per step of the order"
  fi
  check_session "$label: the production runs with nothing missing, is the autostart production, and the module has no dependency" OCUTALON \
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
  check_ipm_case "$label"
}

# check_second_run [<run name> [<label>]]: matrix row "Second run, path A". The output is in $tmp/<run name>.txt (default
# second-ocutalon, label "second run"); the snapshot it takes is $tmp/<run name>.snap.
check_second_run() {
  local name="${1:-second-ocutalon}" label="${2:-second run}"
  check_run_ok "$name" "$label"
  take_snapshot "$name" "$label"
  same_services "$label" base "$name"
  same_config "$label" first "$name"
  check_no_residue "$label" USER %SYS
  check_session "$label: PasswordValidationRoutine is still empty" %SYS "CHK|pwd|" \
    'Do ##class(Security.System).Get(,.p) Write !,"CHK|pwd|",$Get(p("PasswordValidationRoutine"))' 'Halt'
}

# check_install [<run name> [<label>]]: matrix row "Install checks", on the output of the run (default second-ocutalon, label "install checks").
check_install() {
  local f="$tmp/${1:-second-ocutalon}.txt" label="${2:-install checks}"
  check_session "$label: the public package and global are in OCUTALON_PUBLIC, the private globals in OCUTALON_PRIVATE" OCUTALON \
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
    pass "$label: the output has STEP PrivateData OK"
  else
    fail "$label: the output has no STEP PrivateData OK"
  fi
  check_session "$label: index.html is in the /ocutalon application's Path" %SYS \
    "CHK|index|1
CHK|samepath|1" \
    'Set d=$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/" Write !,"CHK|index|",+##class(%File).Exists(d_"index.html")' \
    'Do ##class(Security.Applications).Get("/ocutalon",.ap) Write !,"CHK|samepath|",+(##class(%File).NormalizeDirectory($Get(ap("Path")))=##class(%File).NormalizeDirectory(d))' \
    'Halt'
  check_session "$label: onlineDemo is 0 and ready is 1, and the public settings sit in the public database" OCUTALON \
    "CHK|onlineDemo|0
CHK|ready|1
CHK|settings-dest|ocutalon_public" \
    'Write !,"CHK|onlineDemo|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
    'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
    'Set d=##class(%SYS.Namespace).GetRoutineDest("OCUTALON","OcuTalon.Data.Public.Settings.1","INT") Write !,"CHK|settings-dest|",$Piece(d,"/",$Length(d,"/")-1)' \
    'Halt'
}

# stage_requirements: puts the repository root's requirements.txt beside src/module.xml in the container, as it sits beside module.xml in the
# published package, so that IPM installs the Python requirements of the module root (Story 19.2, U-294). The folder is the image's, owned by
# root and read-only, so root writes the file. The image is built from the allow-listed context of release/ipm/Dockerfile, which holds only src/.
stage_requirements() {
  dc exec -T -u root iris sh -c "cat > $SRC/requirements.txt && chmod 444 $SRC/requirements.txt" < requirements.txt || die "requirements.txt could not be staged in the container"
}

# stage_licence_gate: puts docker/licences/gate.py, allowed.txt and the constraints file of the container's architecture (uname -m) into a scratch
# folder of the container, as root and read-only (Story 19.6, U-294). The image is built from the
# allow-listed context of release/ipm/Dockerfile, which holds only src/, so the files are staged the way requirements.txt is.
LICENCES=/tmp/ocutalon-licences

# manager_directory: the container's manager directory (with the closing slash) from a %SYS session, tried up to 6 times, 5 seconds apart, because
# a busy host can answer a session late right after the stack is up.
manager_directory() {
  local try=1 mgr=""
  while [ -z "$mgr" ] && [ "$try" -le 6 ]; do
    mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | session_value %SYS mgr)
    [ -n "$mgr" ] || sleep 5
    try=$((try + 1))
  done
  printf '%s' "$mgr"
}
stage_licence_gate() {
  local arch name
  arch=$(dc exec -T iris uname -m 2> /dev/null | tr -d '\r')
  case $arch in
    x86_64) arch=x64 ;;
    aarch64) arch=arm64 ;;
    *) die "no Python constraints file for the container's architecture '$arch'" ;;
  esac
  LICENCE_CONSTRAINTS="$LICENCES/constraints-$arch.txt"
  dc exec -T -u root iris mkdir -p "$LICENCES" || die "the licence gate could not be staged in the container"
  for name in gate.py allowed.txt "constraints-$arch.txt"; do
    dc exec -T -u root iris sh -c "cat > $LICENCES/$name && chmod 444 $LICENCES/$name" < "docker/licences/$name" || die "docker/licences/$name could not be staged in the container"
  done
  dc exec -T -u root iris chmod 555 "$LICENCES" || die "the licence gate folder could not be made read-only"
}

# IPM's own Python packages (its ORAS dependencies) and the six distributions of them that OcuTalon pins (Story 19.8, DW-829): the modules
# whose import is recorded before and after the install.
PY_SIX="certifi charset_normalizer idna requests typing_extensions urllib3"
PY_IPM="attr attrs jsonschema jsonschema_specifications oras oras.provider referencing rpds"

# python_imports: one CHK|imp|<module>|<1 or 0> line for each module of IPM's own packages and of the six, from a %SYS session: whether the
# import works.
python_imports() {
  local mods="" m
  for m in $PY_IPM $PY_SIX; do mods="$mods\"$m\","; done
  printf '%s\n' "For m=${mods%,} { Set ok=1 Try { Do ##class(%SYS.Python).Import(m) } Catch { Set ok=0 } Write !,\"CHK|imp|\",m,\"|\",ok }" 'Halt' | iris_script %SYS
}

# python_state <python folder> <file in the container>: writes one line for each entry of the folder: "D <dist-info folder> <md5 of its RECORD,
# or ->" and "T <other top-level item>".
python_state() {
  dc exec -T iris python3 - "$1" "$2" << 'EOP'
import hashlib, os, sys
target, out = sys.argv[1:3]
lines = []
for entry in sorted(os.listdir(target)):
    if entry.endswith(".dist-info"):
        try:
            digest = hashlib.md5(open(os.path.join(target, entry, "RECORD"), "rb").read()).hexdigest()
        except OSError:
            digest = "-"
        lines.append("D %s %s" % (entry, digest))
    else:
        lines.append("T %s" % entry)
open(out, "w").write("\n".join(lines) + "\n")
EOP
}

# snapshot_python_before: records the distributions that <mgr>/python holds now, just before the install command that installs the requirements
# (the image's own packages, and IPM's own dependencies once IPM is loaded): the dist-info names for check 32's gate, the folder's entries and
# the imports of IPM's packages for check_python_pins (Story 19.8). It prints the dist-infos it found.
snapshot_python_before() {
  local mgr
  mgr=$(manager_directory)
  [ -n "$mgr" ] || die "the manager directory could not be read, so the Python folder could not be recorded"
  dc exec -T iris sh -c "ls '${mgr}python' 2> /dev/null | grep '[.]dist-info\$' > /tmp/ocutalon-python-before.txt; true" || die "the Python folder could not be recorded"
  python_state "${mgr}python" /tmp/ocutalon-python-before.state || die "the Python folder's entries could not be recorded"
  python_imports | dc exec -T iris sh -c 'cat > /tmp/ocutalon-imports-before.txt' || die "the imports of IPM's packages could not be recorded"
  echo "NOTE python before the install, <mgr>/python holds: $(dc exec -T iris cat /tmp/ocutalon-python-before.txt | tr -d '\r' | sed 's/[.]dist-info$//' | tr '\n' ' ')"
}

# check_licences <label> (check 32): the licence gate on what IPM installed into <mgr>/python, and the notices it writes. What IPM installed is
# every distribution of the folder except one that snapshot_python_before found there and whose name is no pin of the constraints file (the
# image's own Python packages and IPM's own dependencies: the gate is not theirs); a pin that was there already counts as installed, and an
# older copy of a pinned name that is still there fails the gate.
check_licences() {
  local label=$1 mgr out rc named scratch=/tmp/ocutalon-installed
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the licence gate did not run"
    return
  fi
  dc exec -T iris python3 - "${mgr}python" /tmp/ocutalon-python-before.txt "$LICENCE_CONSTRAINTS" "$scratch" << 'EOP' | tr -d '\r' | sed 's/^/  /'
import os, re, shutil, sys
target, before_file, constraints, scratch = sys.argv[1:5]
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()
pins = {}
for line in open(constraints):
    line = line.strip()
    if line and not line.startswith("#"):
        name, _, version = line.partition("==")
        pins[norm(name)] = version
before = set(open(before_file).read().split())
shutil.rmtree(scratch, ignore_errors=True)
os.makedirs(scratch)
kept = 0
for entry in sorted(os.listdir(target)):
    if not entry.endswith(".dist-info"):
        continue
    name, _, version = entry[: -len(".dist-info")].rpartition("-")
    if entry in before and norm(name) not in pins:
        print("NOTE %s was in the folder before the install and is no pin: not gated" % entry[: -len(".dist-info")])
        continue
    os.symlink(os.path.join(target, entry), os.path.join(scratch, entry))
    kept += 1
print("NOTE %d distributions gated" % kept)
EOP
  out=$(dc exec -T iris python3 "$LICENCES/gate.py" check "$scratch" "$LICENCE_CONSTRAINTS" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: the licence gate passes on what IPM installed ($(printf '%s\n' "$out" | tail -n 1 | tr -d '\r'))"
  else
    printf '%s\n' "$out" | tr -d '\r' | grep -e FAIL | cut -c1-300 | sed 's/^/  gate: /'
    fail "$label: the licence gate fails on what IPM installed (exit $rc)"
  fi
  named=$(dc exec -T iris sh -c "python3 $LICENCES/gate.py notices '$scratch' /tmp/ocutalon-notices.txt > /dev/null 2>&1; python3 - '$LICENCE_CONSTRAINTS' /tmp/ocutalon-notices.txt" 2> /dev/null << 'EOP' | tr -d '\r'
import re, sys
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()
pins = [l.strip().split("==") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
lines = set(norm(l.strip()) for l in open(sys.argv[2], encoding="utf-8", errors="replace"))
named = sum(1 for name, version in pins if norm(name + " " + version) in lines)
print("%d/%d" % (named, len(pins)))
EOP
)
  if [ -n "$named" ] && [ "${named%/*}" = "${named#*/}" ] && [ "${named%/*}" -gt 0 ] 2> /dev/null; then
    pass "$label: gate.py notices writes a file that names all ${named#*/} distributions at their pinned versions"
  else
    fail "$label: the notices name '$named' of the pinned distributions"
  fi
}

# check_imports <label> (check 32, Story 19.8, DW-829): certifi, charset_normalizer, idna, requests, typing_extensions and urllib3 import the pinned
# copies. An OCUTALON session's Embedded Python imports each and prints __version__ ("" when it has none) and __file__; the container's python3
# then requires that __file__ is under <mgr>/python, that the RECORD of the pinned dist-info <name>-<pin>.dist-info lists it with the sha256 of
# the file (urlsafe base64, unpadded), and that __version__, when there is one, is the pin. The hash alone is not enough: urllib3's __init__.py is
# the same in 2.6.3 and 2.8.0. One NOTE line for each module.
check_imports() {
  local label=$1 mgr imports out rc
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the import check did not run"
    return
  fi
  imports=$(printf '%s\n' \
    'Set b=##class(%SYS.Python).Import("builtins") For m="certifi","charset_normalizer","idna","requests","typing_extensions","urllib3" { Try { Set mod=##class(%SYS.Python).Import(m) Write !,"CHK|import|",m,"|",b.getattr(mod,"__version__",""),"|",b.getattr(mod,"__file__","") } Catch { Write !,"CHK|import|",m,"||" } }' \
    'Halt' | iris_script OCUTALON)
  out=$(dc exec -T iris python3 - "${mgr}python" "$LICENCE_CONSTRAINTS" "$imports" 2>&1 << 'EOP'
import base64, csv, hashlib, os, re, sys
target, constraints, imports = sys.argv[1:4]
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()
def vnorm(version):
    return ".".join(str(int(part)) if part.isdigit() else part for part in version.split("."))
pins = {}
for line in open(constraints):
    line = line.strip()
    if line and not line.startswith("#"):
        name, _, version = line.partition("==")
        pins[norm(name)] = version
seen = {}
for line in imports.splitlines():
    parts = line.strip().split("|", 4)
    if len(parts) == 5 and parts[:2] == ["CHK", "import"]:
        seen[parts[2]] = (parts[3], parts[4])
root = os.path.realpath(target)
stale = []
for name in ["certifi", "charset_normalizer", "idna", "requests", "typing_extensions", "urllib3"]:
    pin = pins.get(norm(name))
    version, path = seen.get(name, ("", ""))
    why = []
    rel = "-"
    if not path:
        why.append("not imported")
    else:
        rel = os.path.relpath(os.path.realpath(path), root)
        if rel.startswith(".."):
            why.append("not under mgr/python")
        else:
            record = None
            for entry in os.listdir(target):
                base = entry[: -len(".dist-info")] if entry.endswith(".dist-info") else None
                if base is not None and norm(base.rpartition("-")[0]) == norm(name) and vnorm(base.rpartition("-")[2]) == vnorm(pin):
                    record = os.path.join(target, entry, "RECORD")
            digest = base64.urlsafe_b64encode(hashlib.sha256(open(os.path.realpath(path), "rb").read()).digest()).rstrip(b"=").decode()
            listed = [row for row in csv.reader(open(record)) if row and row[0] == rel] if record else []
            if record is None:
                why.append("no pinned dist-info")
            elif not listed or listed[0][1] != "sha256=" + digest:
                why.append("not the file of the pinned RECORD")
        if version and vnorm(version) != vnorm(pin):
            why.append("version %s, pin %s" % (version, pin))
    print("NOTE import %s %s %s %s%s" % (name, version or "-", rel, "stale" if why else "pinned", " (" + ", ".join(why) + ")" if why else ""))
    if why:
        stale.append(name)
print("STALE " + ",".join(stale) if stale else "ALL PINNED")
sys.exit(1 if stale else 0)
EOP
)
  rc=$?
  printf '%s\n' "$out" | tr -d '\r' | grep '^NOTE' | sed 's/^/  /'
  if [ "$rc" -eq 0 ]; then
    pass "$label: certifi, charset_normalizer, idna, requests, typing_extensions and urllib3 import their pinned copies (version and RECORD hash)"
  else
    fail "$label: the import check fails for $(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^STALE //p')"
  fi
}

# check_python_moves <label> [<state file of the install>] (check 32, Story 19.8): the folder <mgr>/python now against what snapshot_python_before
# recorded. The only differences allowed are the stale copies of pinned names (the six) gone and the pins in their place, and the pins that the
# install adds: every other dist-info is there with the same RECORD, every top-level item is still there, the import record names the same modules
# before and after (an empty one fails), and every module of IPM's packages that imported before imports now. Writes the current state to
# /tmp/ocutalon-python-after.state.
check_python_moves() {
  local label=$1 mgr out rc now
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the folder comparison did not run"
    return
  fi
  python_state "${mgr}python" /tmp/ocutalon-python-after.state || { fail "$label: the Python folder's entries could not be recorded"; return; }
  now=$(python_imports)
  out=$(dc exec -T iris python3 - "$LICENCE_CONSTRAINTS" /tmp/ocutalon-python-before.state /tmp/ocutalon-python-after.state /tmp/ocutalon-imports-before.txt "$now" 2>&1 << 'EOP'
import re, sys
constraints, before_file, after_file, imports_before, imports_after = sys.argv[1:6]
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()
def vnorm(version):
    return ".".join(str(int(part)) if part.isdigit() else part for part in version.split("."))
pins = {}
for line in open(constraints):
    line = line.strip()
    if line and not line.startswith("#"):
        name, _, version = line.partition("==")
        pins[norm(name)] = version
def load(path):
    dists, tops = {}, set()
    for line in open(path):
        parts = line.split()
        if parts and parts[0] == "D":
            dists[parts[1]] = parts[2]
        elif parts and parts[0] == "T":
            tops.add(parts[1])
    return dists, tops
def split(entry):
    name, _, version = entry[: -len(".dist-info")].rpartition("-")
    return norm(name), name, version
bd, bt = load(before_file)
ad, at = load(after_file)
problems, moved, added = [], [], []
for entry, digest in sorted(bd.items()):
    key, name, version = split(entry)
    pin = pins.get(key)
    if pin is not None and vnorm(version) != vnorm(pin):
        moved.append("%s %s -> %s" % (name, version, pin))
        if entry in ad:
            problems.append("%s is still in the folder" % entry)
        if not any(split(e)[0] == key and vnorm(split(e)[2]) == vnorm(pin) for e in ad):
            problems.append("%s %s is not in the folder" % (name, pin))
    elif entry not in ad:
        problems.append("%s is gone" % entry)
    elif ad[entry] != digest:
        problems.append("%s changed" % entry)
for entry in sorted(ad):
    if entry not in bd:
        key, name, version = split(entry)
        if key in pins and vnorm(pins[key]) == vnorm(version):
            added.append(entry)
        else:
            problems.append("%s was added and is no pin" % entry)
for item in sorted(bt - at):
    problems.append("top-level item %s is gone" % item)
def imports(text):
    return dict(re.findall(r"CHK\|imp\|([^|]+)\|(\d)", text))
ib, ia = imports(open(imports_before).read()), imports(imports_after)
if not ib or set(ib) != set(ia):
    problems.append("the import record of IPM's packages is empty or not the same list before and after (%d and %d modules)" % (len(ib), len(ia)))
for module, ok in sorted(ib.items()):
    if ok == "1" and ia.get(module) != "1":
        problems.append("%s imported before the install and does not now" % module)
print("NOTE python folder: %d distributions before, %d after; %d moved to the pins%s; %d pinned distributions added" % (len(bd), len(ad), len(moved), (": " + ", ".join(moved)) if moved else "", len(added)))
print("NOTE imports before and after: %s" % ", ".join("%s %s>%s" % (m, ib[m], ia.get(m, "-")) for m in sorted(ib)))
for problem in problems:
    print("PROBLEM " + problem)
sys.exit(1 if problems else 0)
EOP
)
  rc=$?
  printf '%s\n' "$out" | tr -d '\r' | grep -e '^NOTE' -e '^PROBLEM' | cut -c1-400 | sed 's/^/  /'
  if [ "$rc" -eq 0 ]; then
    pass "$label: the Python folder differs from before the install only by the six moving to the pins and the pins added, and IPM's own packages import as before"
  else
    fail "$label: the Python folder differs from before the install by more than the six moving to the pins and the pins added, or an IPM package no longer imports"
  fi
}

# check_ipm_alive <label> <module pattern> (check 32, Story 19.8): IPM still works in OCUTALON: zpm "list" answers without an error and shows the
# pattern (a module name; "." for any text).
check_ipm_alive() {
  local out
  out=$(printf '%s\nHalt\n' 'zpm "list"' | dc exec -T iris iris session IRIS -U OCUTALON 2>&1 | tr -d '\r' | strip_ansi)
  printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | head -n 12 | cut -c1-200 | sed 's/^/  zpm list: /'
  if printf '%s\n' "$out" | grep -q -e "$2" && ! printf '%s\n' "$out" | grep -q -e '^ERROR' -e 'FAILURE' -e '<[A-Z]*>'; then
    pass "$1: zpm \"list\" answers in OCUTALON without an error"
  else
    fail "$1: zpm \"list\" gave an error or no answer"
  fi
}

# check_invoke_args <label> (check 32, Story 19.8): the installed module's Reload Invoke of RemoveStaleCopies gets the module root, the
# -bypass-py-deps flag and the lifecycle command as its arguments: with a root set on the module, the first argument is that root, the second is
# 0 and the third is empty when IPM's parameters hold neither, and the second is 1 and the third is the command (install here) with
# pParams("BypassPyDeps") and pParams("cmd") set, as the -bypass-py-deps modifier and the install command set them (DW-856).
check_invoke_args() {
  check_session "$1: the Reload Invoke of RemoveStaleCopies gets the module root, the -bypass-py-deps flag (0, and 1 when set) and the lifecycle command (empty, and install when set)" OCUTALON \
    "CHK|args|1|/zz/root/|0||1|install|Reload|Before" \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon"),n=0 If $IsObject(m) { Set m.Root="/zz/root" Set key="" For { Set inv=m.Invokes.GetNext(.key) Quit:key=""  If inv.Method="RemoveStaleCopies" { Set n=n+1 Kill p,a Do inv.GetArgsArray(.p,.a) Set a1=a(1),a2=a(2),a3=a(3) Set p("BypassPyDeps")=1,p("cmd")="install" Kill a Do inv.GetArgsArray(.p,.a) Write !,"CHK|args|",n,"|",a1,"|",a2,"|",a3,"|",a(2),"|",a(3),"|",inv.Phase,"|",inv.When } } }' \
    'Halt'
}

# check_python_pins <label> (check 32, Story 19.8, DW-829): the imports of the six, the folder against what it held before, IPM's answer and the
# Invoke's arguments, on what the install left.
check_python_pins() {
  local started=$SECONDS
  check_imports "$1"
  check_python_moves "$1"
  check_ipm_alive "$1" ocutalon
  check_invoke_args "$1"
  echo "TIME python-pins $((SECONDS - started))s"
}

# check_reinstall (check 32, Story 19.8): the install command again in OCUTALON, from the same folder: it ends in Activate SUCCESS without an
# error and replaces nothing (no STEP Python line), and the checks of check_python_pins hold, with the folder the same as before it.
check_reinstall() {
  local f="$tmp/reinstall-same.txt" started=$SECONDS
  snapshot_python_before
  run reinstall-same OCUTALON "$INSTALL"
  if grep -q 'Activate SUCCESS' "$f" && ! grep -q 'FAILURE' "$f" && ! grep -q '^ERROR!' "$f"; then
    pass "reinstall: the install command again ends in Activate SUCCESS without an error"
  else
    fail "reinstall: the install command again did not end in Activate SUCCESS"
  fi
  if ! grep -q '^STEP Python ' "$f"; then
    pass "reinstall: the early step replaced nothing (no STEP Python line)"
  else
    grep '^STEP Python ' "$f" | sed 's/^/  /'
    fail "reinstall: the early step replaced a distribution on the second install"
  fi
  check_python_pins "reinstall"
  check_licences "reinstall"
  echo "TIME reinstall-checks $((SECONDS - started))s"
}

# plant_stale_copy <mgr> <state file>: puts a decoy stale distribution into <mgr>/python, a dist-info folder idna-0.0.1 whose RECORD names the
# idna package that IPM's own packages import, and writes the folder's entries to the state file. idna is pinned, so a step that removes
# stale copies without a pip step behind it would remove the package of the pinned idna that is in use.
plant_stale_copy() {
  dc exec -T iris python3 - "$1python" << 'EOP' || return 1
import os, sys
info = os.path.join(sys.argv[1], "idna-0.0.1.dist-info")
os.makedirs(info, exist_ok=True)
open(os.path.join(info, "RECORD"), "w").write("idna/__init__.py,,\nidna-0.0.1.dist-info/RECORD,,\n")
open(os.path.join(info, "METADATA"), "w").write("Name: idna\nVersion: 0.0.1\n")
EOP
  python_state "$1python" "$2"
}

# check_nothing_removed <label> <run name>: after a run in which IPM's pip step does not run (check_pip_skipped): the run reached the end of its
# Reload phase without a failure, the early step wrote no STEP Python line, the Python folder holds exactly what it held with the decoy planted
# (the pinned idna included), IPM's own packages import as they did, the six still import their pinned copies (the base image also holds
# older copies in a user folder, so a missing pinned copy would still import), and zpm "list" answers.
check_nothing_removed() {
  local label=$1 f="$tmp/$2.txt" mgr now
  if grep -q 'Reload SUCCESS' "$f" && ! grep -q 'FAILURE' "$f" && ! grep -q '^ERROR!' "$f"; then
    pass "$label: the run ends its Reload phase without an error"
  else
    grep -e 'Reload' -e 'FAILURE' -e '^ERROR!' "$f" | head -n 6 | cut -c1-200 | sed 's/^/  /'
    fail "$label: the run did not end its Reload phase, or ended with an error"
  fi
  if ! grep -q '^STEP Python ' "$f"; then
    pass "$label: the early step replaced nothing (no STEP Python line)"
  else
    grep '^STEP Python ' "$f" | sed 's/^/  /'
    fail "$label: the early step replaced a distribution although IPM's pip step did not run"
  fi
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the folder comparison did not run"
    return
  fi
  python_state "${mgr}python" /tmp/ocutalon-python-skip-after.state || { fail "$label: the Python folder's entries could not be recorded"; return; }
  if dc exec -T iris diff /tmp/ocutalon-python-skip-planted.state /tmp/ocutalon-python-skip-after.state > "$tmp/skip.diff" 2>&1; then
    pass "$label: the Python folder holds exactly what it held before the run (the stale copy and the pinned idna included)"
  else
    sed 's/^/  folder: /' "$tmp/skip.diff" | head -n 12
    fail "$label: the run removed or changed something in the Python folder"
  fi
  now=$(python_imports)
  if [ -n "$now" ] && [ "$now" = "$skip_imports" ] && printf '%s\n' "$now" | grep -q 'CHK|imp|idna|1' && printf '%s\n' "$now" | grep -q 'CHK|imp|requests|1' \
    && printf '%s\n' "$now" | grep -q 'CHK|imp|oras.provider|1'; then
    pass "$label: IPM's own packages and the six import as before the run"
  else
    printf '%s\n' "$now" | grep '|0$' | sed 's/^/  not imported: /'
    fail "$label: an import record is empty, or differs from the one before the run, or idna, requests or oras.provider no longer imports"
  fi
  check_imports "$label"
  check_ipm_alive "$label" ocutalon
}

# check_pip_skipped <label> (check 32, Story 19.8, DW-856): the early step removes a stale copy only when IPM's pip step runs in the same
# lifecycle. With a decoy stale idna in <mgr>/python, `zpm "reload ocutalon"` (the pip step runs for install, load and update only) and a load
# with -bypass-py-deps each remove nothing, and IPM's own packages and zpm "list" still work. The decoy goes at the end.
check_pip_skipped() {
  local label=$1 mgr started=$SECONDS skip_imports
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the runs without a pip step did not run"
    return
  fi
  if ! plant_stale_copy "$mgr" /tmp/ocutalon-python-skip-planted.state; then
    dc exec -T iris rm -rf "${mgr}python/idna-0.0.1.dist-info"
    fail "$label: the stale copy could not be planted, so the runs without a pip step did not run"
    return
  fi
  skip_imports=$(python_imports)
  run skip-reload OCUTALON 'zpm "reload ocutalon"'
  check_nothing_removed "reload (pip skipped)" skip-reload
  run skip-bypass OCUTALON "zpm \"load -bypass-py-deps $SRC\""
  check_nothing_removed "load -bypass-py-deps" skip-bypass
  dc exec -T iris rm -rf "${mgr}python/idna-0.0.1.dist-info" || fail "$label: the stale copy that was planted could not be removed again"
  echo "TIME pip-skipped $((SECONDS - started))s"
}

# check_extract <label> (check 33): the PDF and Word reading works in the installed package.
check_extract() {
  check_session "$1: Docs.Extract.Read answers a PDF and a Word file, in a worker of the extraction category" OCUTALON \
    "CHK|pdf|1|page
CHK|docx|1|heading" \
    'Set a=##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).Pdf3(),"pdf") Write !,"CHK|pdf|",a.ok,"|",a.markers' \
    'Set a=##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).DocxHeadings(),"docx") Write !,"CHK|docx|",a.ok,"|",a.markers' \
    'Halt'
}

# check_memory [<run name> [<label>]] (check 30): the Python requirement and the model, on the output of the run (default second-ocutalon).
check_memory() {
  local f="$tmp/${1:-second-ocutalon}.txt" label="${2:-install checks}"
  if grep -q '^STEP Memory OK' "$f" && ! grep -q '^WARN Memory ' "$f"; then
    pass "$label: the output has STEP Memory OK and no WARN Memory line"
  else
    grep '^WARN Memory ' "$f" | cut -c1-300
    fail "$label: the output has no STEP Memory OK, or has a WARN Memory line"
  fi
  check_session "$label: IPM installed fastembed 0.9.0, pdfplumber 0.11.10 and python-docx 1.1.2 from requirements.txt, and the model sits once in <mgr>/fastembed/" OCUTALON \
    "CHK|fastembed|0.9.0
CHK|pdfplumber|0.11.10
CHK|python-docx|1.1.2
CHK|models|1
CHK|hasmodel|1" \
    'Write !,"CHK|fastembed|",##class(%SYS.Python).Import("importlib.metadata").version("fastembed")' \
    'Write !,"CHK|pdfplumber|",##class(%SYS.Python).Import("importlib.metadata").version("pdfplumber")' \
    'Write !,"CHK|python-docx|",##class(%SYS.Python).Import("importlib.metadata").version("python-docx")' \
    'Set n=0,d=$ZSearch($SYSTEM.Util.ManagerDirectory()_"fastembed/models--*") While d'"'"'="" { Set n=n+1 Set d=$ZSearch("") } Write !,"CHK|models|",n' \
    'Write !,"CHK|hasmodel|",+##class(OcuTalon.Memory.Embedder).HasModel($SYSTEM.Util.ManagerDirectory()_"fastembed/")' \
    'Halt'
}

# memory_fingerprint: a checksum of the file list and sizes of <mgr>/fastembed/ in the container, and the number of its files; empty when
# the manager directory cannot be read.
memory_fingerprint() {
  local mgr
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  [ -n "$mgr" ] || return 0
  dc exec -T iris sh -c "cd '${mgr}fastembed' && { find . -printf '%p %s\n' | sort | md5sum | cut -c1-12; find . -type f | wc -l; }" 2> /dev/null | tr -d '\r' | tr '\n' ' '
}

# resources_fingerprint: the checksums of the two Python resources in <mgr>/python of the container; empty when they cannot be read.
resources_fingerprint() {
  local mgr
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  [ -n "$mgr" ] || return 0
  dc exec -T iris sh -c "md5sum '${mgr}python/ocutalon_extract.py' '${mgr}python/ocutalon_memory.py'" 2> /dev/null | tr -d '\r' | awk '{ printf "%s ", $1 }'
}

# check_signin <label> [logout]: the sign-in page is served and not the online demo's, and ocutalon/ocutalon signs in; the session stays
# in the jar $ocu_jar unless the second argument is logout.
check_signin() {
  local code
  ocu_jar="$tmp/jar.ocu"
  : > "$ocu_jar"
  next_probe
  rm -f "$tmp/signin.page"
  curl -s --max-time 30 -b "$ocu_jar" -c "$ocu_jar" -o "$tmp/signin.page" "$base/ocutalon/?probe=$probes"
  if grep -q 'Sign in to OcuTalon' "$tmp/signin.page" && ! grep -q 'Try OcuTalon in two minutes' "$tmp/signin.page"; then
    pass "$1: GET /ocutalon/ serves the sign-in page and not the online demo's"
  else
    fail "$1: GET /ocutalon/ does not serve 'Sign in to OcuTalon' (or serves the online demo's page)"
  fi
  code=$(online_signin "$ocu_jar" "" "" ocutalon ocutalon)
  if grep -q '<app-root' "$ocu_jar.b"; then
    pass "$1: ocutalon/ocutalon signs in (the app root is served, sign-in status $code)"
  else
    fail "$1: ocutalon/ocutalon does not sign in (status $code)"
  fi
  if [ "${2:-}" = logout ]; then logout_all "$ocu_jar" /ocutalon/; fi
}

# check_web: matrix row "Web and REST". The chat check points the keys at the CI mock before and back after, also on a failure.
check_web() {
  local code facts turn
  check_signin web
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

# one_new_row <before> <label> <what>: ReconcileIn's Info rows, <before> of them when <what> began, rise to exactly <before>+1 within 60 s and
# stay there for 15 s more (the shared count of the checks that start the production outside the Production step). Prints the PASS or FAIL
# line.
one_new_row() {
  local before=$1 after n
  wait_until 60 reconcile_rows_above "$before" || true
  after=$(reconcile_rows)
  sleep 15
  n=$(reconcile_rows)
  if [ "$after" = "$((before + 1))" ] && [ "$n" = "$after" ]; then
    pass "$2: ReconcileIn logged one new Info row after $3, and no second one after three more polls ($before -> $after -> $n)"
  else
    fail "$2: ReconcileIn's Info rows went $before -> $after, then $n; wanted one more and then no more"
  fi
}

# stop_start: stops the production and starts it again from a terminal session of OCUTALON (no installer run), printed as run <name>.
stop_start() {
  run "$1" OCUTALON "$(printf '%s\n' 'Do ##class(Ens.Director).StopProduction(30,0)' 'Set sc=##class(Ens.Director).StartProduction("OcuTalon.Production") Write !,"CHK|start|",$SYSTEM.Status.IsOK(sc)')"
}

# check_start_outside: matrix row "Start outside the step".
check_start_outside() {
  local before
  before=$(reconcile_rows)
  stop_start stop-start
  one_new_row "$before" "start outside the step" "a session's start"
}

# check_start_by_step: matrix row "Start by the step".
check_start_by_step() {
  local before after
  before=$(reconcile_rows)
  run by-step OCUTALON 'Set sc=##class(OcuTalon.Install.Registry).Run("ipm") Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)'
  sleep 15
  after=$(reconcile_rows)
  if grep -q '^STEP Reconcile OK' "$tmp/by-step.txt" && ! grep -q 'FAILED' "$tmp/by-step.txt" && [ -n "$before" ] && [ "$after" = "$before" ]; then
    pass "start by the step: Registry.Run(\"ipm\") ends with STEP Reconcile OK, and ReconcileIn logged no new Info row in 15 s ($before -> $after)"
  else
    fail "start by the step: STEP Reconcile OK missing or a step failed, or ReconcileIn's Info rows went $before -> $after"
  fi
}

# --- failed reinstalls (Story 15.2, owner decision U-176): test-only copies of the package inside the throwaway ---
#
# The seam is in the test only. scratch_copy makes a writable copy of the package folder in the container and applies the lines it is
# given; the shipped package has no switch that makes a step or a compile fail, and the source tree is never edited. IPM refuses to
# load a lower version over a higher one, so the copy of the failed step keeps the real version, and only the copy of the failed compile
# raises it (its patch number by one), which makes "the module version is unchanged" a check that can fail.

SCRATCH_STEP=/tmp/ocutalon-scratch-step
SCRATCH_COMPILE=/tmp/ocutalon-scratch-compile
SEED_MARK=zzReinstallSeed
SEED_VALUE=kept-by-the-reinstall
FORCED_TEXT="forced failure of the Audit step by the scratch copy of the test"
BROKEN_MACRO=ZzNoSuchMacroInTheScratchCopy
REAL_VERSION=
RAISED_VERSION=

# scratch_copy <folder> <shell line>...: see above; the lines run in the container, in the order given, after the copy.
scratch_copy() {
  local dir=$1
  shift
  { printf '%s\n' 'set -e' "rm -rf $dir" "cp -R --no-preserve=mode $SRC $dir" "chmod -R u+w $dir" "$@"; } | dc exec -T iris sh -s
}

# module_version: the version the module ocutalon is recorded with.
module_version() {
  printf '%s\n' 'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|version|",$Select($IsObject(m):m.VersionString,1:"<none>")' 'Halt' | chk version
}

# seed_mark_value: the value of the seeded status mark, which a reinstall must keep.
seed_mark_value() {
  printf '%s\n' 'Write !,"CHK|mark|",##class(OcuTalon.Data.StatusMark).Get("'"$SEED_MARK"'")' 'Halt' | chk mark
}

# same_config <label> <snapshot name> <snapshot name>: the two configuration snapshots (services, OCUTALON, its four databases, resources
# and mappings, USER's mappings) are identical.
same_config() {
  if diff "$tmp/$2.snap" "$tmp/$3.snap" > "$tmp/snap.diff"; then
    pass "$1: OCUTALON, its four databases, resources and mappings, USER's mappings and the services are those of snapshot $2 ($(grep -c . "$tmp/$3.snap") lines)"
  else
    sed 's/^/  snapshot: /' "$tmp/snap.diff"
    fail "$1: the configuration changed"
  fi
}

# command_failed <file> <label> <text> [<phase>]: the install command reported the failure: IPM's <phase> FAILURE (default Configure), an
# ERROR! line with the text, and no success line for Activate or the phase.
command_failed() {
  local f=$1 phase=${4:-Configure}
  if grep -q "$phase FAILURE" "$f" && grep -q -- "^ERROR! .*$3" "$f" && ! grep -q 'Activate SUCCESS' "$f" && ! grep -q "$phase SUCCESS" "$f"; then
    pass "$2: IPM reports $phase FAILURE and an ERROR! line with the text, and no Activate SUCCESS line"
  else
    grep -- '^ERROR!' "$f" | sed 's/^/  /'
    fail "$2: the output is not $phase FAILURE then ERROR! with '$3', or a success line stands in it"
  fi
}

# audit_run: 1 when OcuTalon.Install.Step.Audit.Run() returns OK, forced when it returns the scratch copy's error, otherwise other: tells which Audit class is installed.
audit_run() {
  printf '%s\n' 'Set sc=##class(OcuTalon.Install.Step.Audit).Run() Write !,"CHK|audit|",$Select($SYSTEM.Status.IsOK(sc):1,$SYSTEM.Status.GetErrorText(sc)["'"$FORCED_TEXT"'":"forced",1:"other")' 'Halt' | chk audit
}

# check_failed_step: the reinstall from the scratch copy whose Audit step fails. The output is in $tmp/reinstall-fail.txt.
check_failed_step() {
  local f="$tmp/reinstall-fail.txt" order want got line next
  order=$(registry_order)
  want=$(printf '%s' "$order" | sed 's/,Audit,.*/,Audit(FAILED)/')
  got=$(step_names "$f")
  command_failed "$f" "failed step" "$FORCED_TEXT"
  if [ -n "$order" ] && [ "$got" = "$want" ]; then
    pass "failed step: the STEP lines are those of the order up to Audit, and Audit FAILED stops the run"
  else
    echo "  steps wanted: $want"
    echo "  steps got:    $got"
    fail "failed step: the STEP lines are not the order up to a failed Audit"
  fi
  line=$(printf '%s\n' 'Write !,"CHK|line|",##class(OcuTalon.Install.Registry).FailureLine("Audit")' 'Halt' | chk line)
  next=$(awk '/^STEP Audit FAILED / { getline nxt; print nxt; exit }' "$f")
  if [ -n "$line" ] && [ "$next" = "$line" ] && [ "$(grep -cxF -- "$line" "$f")" = 1 ] && [ "$(grep -c 'the new OcuTalon code is installed' "$f")" = 1 ]; then
    pass "failed step: one more line follows the step's own, naming Audit, saying the new code is installed and to run the same command again"
  else
    echo "  wanted the line after STEP Audit FAILED: '$line'"
    echo "  got:                                     '$next'"
    fail "failed step: the line after the failed step is not the one install line"
  fi
  if [ "$(audit_run)" = forced ]; then
    pass "failed step: the new code is installed (the Audit class in OCUTALON is the scratch copy's)"
  else
    fail "failed step: the installed Audit class is not the scratch copy's (Run gives '$(audit_run)')"
  fi
  if [ "$(seed_mark_value)" = "$SEED_VALUE" ]; then
    pass "failed step: the seeded status mark is still there, read back by value"
  else
    fail "failed step: the seeded status mark reads '$(seed_mark_value)', wanted '$SEED_VALUE'"
  fi
  take_snapshot reinstall-fail "failed step"
  same_config "failed step" second-ocutalon reinstall-fail
  check_no_residue "failed step" USER %SYS
}

# check_recovery: the real folder again. The same checks as the second run, then the module and the seeded data.
check_recovery() {
  check_second_run reinstall-recover "recovery run"
  check_durable_recovery
  check_install reinstall-recover "recovery run: install checks"
  check_web
  check_package
  check_demo_switch
  check_start_outside
  check_start_by_step
  if [ "$(audit_run)" = 1 ] && [ "$(module_version)" = "$REAL_VERSION" ]; then
    pass "recovery run: the Audit class is the real one again (Run returns OK) and the module is recorded with version $REAL_VERSION"
  else
    fail "recovery run: Audit.Run gives '$(audit_run)' or the module version is '$(module_version)', wanted OK and $REAL_VERSION"
  fi
  if [ "$(seed_mark_value)" = "$SEED_VALUE" ]; then
    pass "recovery run: the seeded status mark is still there"
  else
    fail "recovery run: the seeded status mark reads '$(seed_mark_value)', wanted '$SEED_VALUE'"
  fi
  same_config "recovery run" second-ocutalon reinstall-recover
}

# check_failed_compile <order>: the reinstall from the scratch copy with a class that does not compile. The output is in
# $tmp/reinstall-compile.txt; <order> is Registry.Order() before it.
check_failed_compile() {
  local f="$tmp/reinstall-compile.txt" order=$1
  command_failed "$f" "failed compile" "" Compile
  if grep -q "$BROKEN_MACRO" "$f"; then
    pass "failed compile: the output names the scratch class's undefined macro as the cause"
  else
    fail "failed compile: the output does not name $BROKEN_MACRO, so the failure may not come from the scratch class"
  fi
  if ! grep -q '^STEP ' "$f"; then
    pass "failed compile: no installer step ran"
  else
    fail "failed compile: an installer step ran"
  fi
  check_session "failed compile: the previous version keeps running: the production runs with nothing missing, Registry.Order() answers as before, the module version is unchanged, and the scratch class is not there" OCUTALON \
    "CHK|running|1|OcuTalon.Production
CHK|notrunning|
CHK|unresolved|
CHK|order|$order
CHK|version|$REAL_VERSION
CHK|broken|0|0
CHK|mark|$SEED_VALUE" \
    'Set r=##class(Ens.Director).IsProductionRunning(.n) Write !,"CHK|running|",r,"|",$Get(n)' \
    'Write !,"CHK|notrunning|",##class(OcuTalon.Install.Step.Production).NotRunning()' \
    'Write !,"CHK|unresolved|",##class(OcuTalon.Install.Step.Production).UnresolvedRunners("OcuTalon.Production")' \
    'Write !,"CHK|order|",$ListToString(##class(OcuTalon.Install.Registry).Order(),",")' \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|version|",$Select($IsObject(m):m.VersionString,1:"<none>")' \
    'Write !,"CHK|broken|",+##class(%Dictionary.ClassDefinition).%ExistsId("OcuTalon.Install.ZzScratchBroken"),"|",+##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Install.ZzScratchBroken")' \
    'Write !,"CHK|mark|",##class(OcuTalon.Data.StatusMark).Get("'"$SEED_MARK"'")' \
    'Halt'
  take_snapshot reinstall-compile "failed compile"
  same_config "failed compile" second-ocutalon reinstall-compile
  check_no_residue "failed compile" USER %SYS
}

# reinstall_failures: owner decision U-176, after the second run and its checks. A reinstall whose Audit step fails (a scratch copy of the
# package whose Audit.Run returns an error), the real folder again, and a reinstall whose Compile fails.
reinstall_failures() {
  local order broken
  REAL_VERSION=$(module_version)
  RAISED_VERSION=$(printf '%s' "$REAL_VERSION" | awk -F. 'NF == 3 { print $1 "." $2 "." $3 + 1 }')
  if [ -z "$RAISED_VERSION" ]; then
    fail "reinstall: the module version '$REAL_VERSION' is not major.minor.patch"
    return
  fi
  echo "REINSTALL a forced step failure, the real folder again, and a failed compile"
  order=$(registry_order)
  check_session "reinstall: the status mark is seeded" OCUTALON "CHK|seed|1" \
    'Write !,"CHK|seed|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record("'"$SEED_MARK"'","'"$SEED_VALUE"'"))' 'Halt'
  seed_durable 86400
  item_jobs "$tmp/jobs-recover-before.tsv"

  scratch_copy "$SCRATCH_STEP" \
    "sed -i 's|^\\tSet sc = ##class(OcuTalon.Bridge.Installer).CheckAudit()\$|\\tQuit \$SYSTEM.Status.Error(5001, \"$FORCED_TEXT\")\\n&|' $SCRATCH_STEP/ocutalon/cls/OcuTalon/Install/Step/Audit.cls" \
    "grep -c 'forced failure' $SCRATCH_STEP/ocutalon/cls/OcuTalon/Install/Step/Audit.cls" > "$tmp/scratch-step.out" 2>&1
  if [ "$(tail -n 1 "$tmp/scratch-step.out" | tr -d '\r')" != 1 ]; then
    cat "$tmp/scratch-step.out"
    fail "reinstall: the scratch copy of the Audit step could not be made"
    return
  fi
  run reinstall-fail OCUTALON "zpm \"load $SCRATCH_STEP\""
  check_failed_step

  run reinstall-recover OCUTALON "$INSTALL"
  check_recovery

  broken=$(printf 'Class OcuTalon.Install.ZzScratchBroken\n{\n\nClassMethod Run() As %%String\n{\n\tQuit $$$%s\n}\n\n}' "$BROKEN_MACRO")
  scratch_copy "$SCRATCH_COMPILE" \
    "sed -i 's|<Version>$REAL_VERSION</Version>|<Version>$RAISED_VERSION</Version>|' $SCRATCH_COMPILE/module.xml" \
    "grep -c '<Version>$RAISED_VERSION</Version>' $SCRATCH_COMPILE/module.xml" \
    "sed -i 's|\"PrivateData\", \"Ready\")|\"Ready\")|' $SCRATCH_COMPILE/ocutalon/cls/OcuTalon/Install/Registry.cls" \
    "grep -c '^	Quit \$ListBuild(.*\"Production\", \"Reconcile\", \"Ready\")\$' $SCRATCH_COMPILE/ocutalon/cls/OcuTalon/Install/Registry.cls" \
    "cat > $SCRATCH_COMPILE/ocutalon/cls/OcuTalon/Install/ZzScratchBroken.cls <<'EOC'
$broken
EOC" > "$tmp/scratch-compile.out" 2>&1
  if [ "$(grep -v '^$' "$tmp/scratch-compile.out" | tail -n 1 | tr -d '\r')" != 1 ]; then
    cat "$tmp/scratch-compile.out"
    fail "reinstall: the scratch copy with the broken class could not be made"
    return
  fi
  run reinstall-compile OCUTALON "zpm \"load $SCRATCH_COMPILE\""
  check_failed_compile "$order"
}

# --- path B (Story 15.2): a foreign password-validation routine and a foreign OCUORDERS ---

# foreign_orders: one line, "<globals>/<routines>|<OCUFOREIGN databases exist>|<OCUORDERS databases exist>", of the foreign OCUORDERS.
foreign_orders() {
  printf '%s\n' \
    'Kill p Set sc=##class(Config.Namespaces).Get("OCUORDERS",.p) Write !,"CHK|foreign|",$Get(p("Globals")),"/",$Get(p("Routines")),"|",+##class(Config.Databases).Exists("OCUFOREIGN_CODE"),+##class(Config.Databases).Exists("OCUFOREIGN_DATA"),"|",+##class(Config.Databases).Exists("OCUORDERS_CODE"),+##class(Config.Databases).Exists("OCUORDERS_DATA")' \
    'Halt' | session_value %SYS foreign
}

# --- durability and reinstalls of an installed package (Story 15.3; AD-5, AD-23; FR-6, NFR-16, NFR-17) ---
#
# "Re-armed exactly once" is read from state, with the test methods of the fixtures called and never edited: a reminder's waiters
# (ReminderFixture WaitingCount) and its ReminderStart headers (StartHeaders), an approval's live hold (Approval.LiveHold) and its hold
# instances (Test.Bridge.Approval HoldCount), and ReconcileIn's Info rows (reconcile_rows). Rows with no waiter (RX, AX, RY, AY) are
# seeded directly, so that the one re-arm of each is countable: a clean restart keeps a live waiter, and Reconcile re-arms only a lost one.
#   RL  a live reminder (set through the product), RX and RY lost reminders, all in one session with a turn; AX and AY lost approvals,
#   fixture rows with an owner of their own.

SEED_USER=ZzIpmDurable
SESS_REF=
TURN_REF=
RL=
RX=
AX=
RY=
AY=
CONV0=
P_RL=
P_RX=
P_AX=
P_RY=
P_AY=
rl_due_s=0
rows_bad=
restart_rows_before=0

# rem_probe <ref>: "<state>|<waiting ReminderTimers>|<ReminderStart headers>|<source of the last start header, - for none>".
rem_probe() {
  printf '%s\n' \
    'Set ref="'"$1"'",RF="OcuTalon.Test.Schedule.ReminderFixture",row=##class(OcuTalon.Data.Reminder).RefIndexOpen(ref),h=$ClassMethod(RF,"StartHeaders",ref),n=h.%Size(),l=$Select(n:h.%Get(n-1),1:{}) Write !,"CHK|rem|",$Select($IsObject(row):row.State,1:"<no row>"),"|",$ClassMethod(RF,"WaitingCount",ref),"|",n,"|",$Select(n:l.source,1:"-")' \
    'Halt' | chk rem
}

# hold_probe <ref>: "<id of the live ApprovalHold or nothing>|<ApprovalHold instances of the ref>".
hold_probe() {
  printf '%s\n' \
    'Set ref="'"$1"'" Write !,"CHK|hold|",##class(OcuTalon.Bridge.Approval).LiveHold(ref),"|",##class(OcuTalon.Test.Bridge.Approval).HoldCount(ref)' \
    'Halt' | chk hold
}

# notify_count <ref>: the ReminderTimer-to-Notify request headers in the trace sessions of the reminder's start headers.
notify_count() {
  printf '%s\n' \
    'Set F="OcuTalon.Test.Data.Fixture",RF="OcuTalon.Test.Schedule.ReminderFixture",h=$ClassMethod(RF,"StartHeaders","'"$1"'"),k=0' \
    'For i=0:1:h.%Size()-1 { Set b=$ClassMethod(F,"Between",$ClassMethod(F,"SessionHeaders",h.%Get(i).sessionId),1,"ReminderTimer","Notify") Set k=k+b.%Size() } Write !,"CHK|notify|",k' \
    'Halt' | chk notify
}

# approval_state <ref>: the State of the approval row.
approval_state() {
  printf '%s\n' 'Write !,"CHK|astate|",##class(OcuTalon.Test.Bridge.ApprovalRows).Prop("'"$1"'","State")' 'Halt' | chk astate
}

# conv_probe: the seeded session and its turn, read back by value.
conv_probe() {
  printf '%s\n' \
    'Set s=##class(OcuTalon.Data.Session).RefIndexOpen("'"$SESS_REF"'"),t=##class(OcuTalon.Data.Turn).RefIndexOpen("'"$TURN_REF"'") Write !,"CHK|conv|",s.IrisUser,"|",s.TraceRef,"|",s.CreatedAt,"|",t.SessionRef,"|",t.State,"|",t.CreatedAt,"|",t.ItemId,"|",t.Text' \
    'Halt' | chk conv
}

# seed_val <name>: the value of the CHK|<name>| line of the last seeding.
seed_val() { sed -n "s/^CHK|$1|//p" "$tmp/seed.chk" | head -n 1; }

# seed_durable <seconds until RL is due>: the session ZzIpmDurable with one done turn, RL, RX and AX; the probes are recorded.
seed_durable() {
  local started=$SECONDS
  rl_due_s=$((SECONDS + $1 - 10))
  printf '%s\n' \
    'Set s=##class(OcuTalon.Test.Data.Fixture).Session("'"$SEED_USER"'"),t=##class(OcuTalon.Test.Data.Fixture).Turn(s,##class(OcuTalon.Data.Time).NowUtc(),"done","zz ipm durable turn") Write !,"CHK|session|",s,!,"CHK|turn|",t' \
    'Set o=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(s,"zz ipm live reminder",'"$1"') Write !,"CHK|rl|",o.ref,"|",+o.ok' \
    'Set x=##class(OcuTalon.Test.Data.Fixture).Reminder(s,##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(),86400),"pending") Write !,"CHK|rx|",x' \
    'Set sc=##class(OcuTalon.Test.Bridge.ApprovalRows).Save(##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call"),"pending",86400,,.a) Write !,"CHK|ax|",a,"|",+$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/seed.chk"
  SESS_REF=$(seed_val session)
  TURN_REF=$(seed_val turn)
  RL=$(seed_val rl | cut -d'|' -f1)
  RX=$(seed_val rx)
  AX=$(seed_val ax | cut -d'|' -f1)
  echo "SEED session $SESS_REF turn $TURN_REF RL $RL RX $RX AX $AX"
  P_RL=$(rem_probe "$RL")
  P_RX=$(rem_probe "$RX")
  P_AX=$(hold_probe "$AX")
  CONV0=$(conv_probe)
  echo "TIME seed $((SECONDS - started))s"
  if [ -n "$SESS_REF" ] && [ -n "$TURN_REF" ] && [ -n "$RL" ] && [ -n "$RX" ] && [ -n "$AX" ] && [ "$(seed_val rl | cut -d'|' -f2)" = 1 ] \
    && [ "$(seed_val ax | cut -d'|' -f2)" = 1 ] && [ "$P_RL" = "pending|1|1|ReminderOps" ] && [ "$P_RX" = "pending|0|0|-" ] && [ "$P_AX" = "|0" ] \
    && [ "$(approval_state "$AX")" = pending ] && [ "${CONV0#*|}" != "$CONV0" ] && [ "$(printf '%s' "$CONV0" | cut -d'|' -f4)" = "$SESS_REF" ]; then
    pass "seed: a session with a done turn, a live reminder (one waiter, one start from ReminderOps), a lost reminder and a lost approval (no waiter, no hold)"
  else
    echo "  RL '$P_RL' RX '$P_RX' AX '$P_AX' conv '$CONV0'"
    fail "seed: the session, the turn, RL, RX or AX could not be seeded as planned"
  fi
}

# seed_pair: the second lost pair, RY and AY, in the seeded session; the probes are recorded.
seed_pair() {
  printf '%s\n' \
    'Set s="'"$SESS_REF"'",y=##class(OcuTalon.Test.Data.Fixture).Reminder(s,##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(),86400),"pending") Write !,"CHK|ry|",y' \
    'Set sc=##class(OcuTalon.Test.Bridge.ApprovalRows).Save(##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call"),"pending",86400,,.a) Write !,"CHK|ay|",a,"|",+$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/seed.chk"
  RY=$(seed_val ry)
  AY=$(seed_val ay | cut -d'|' -f1)
  echo "SEED RY $RY AY $AY"
  P_RY=$(rem_probe "$RY")
  P_AY=$(hold_probe "$AY")
  if [ -n "$RY" ] && [ -n "$AY" ] && [ "$P_RY" = "pending|0|0|-" ] && [ "$P_AY" = "|0" ]; then
    pass "seed: a second lost pair, RY and AY, with no waiter and no hold"
  else
    echo "  RY '$P_RY' AY '$P_AY'"
    fail "seed: RY or AY could not be seeded as planned"
  fi
}

# --- comparing rows: each want_* adds a line to rows_bad, report_rows prints one PASS or FAIL ---

want_eq() { # want_eq <what> <got> <wanted>
  if [ "$2" != "$3" ]; then rows_bad="${rows_bad}
  $1: got '$2', wanted '$3'"; fi
}
report_rows() { # report_rows <label> <what held>
  if [ -z "$rows_bad" ]; then
    pass "$1: $2"
  else
    printf '%s\n' "${rows_bad#?}"
    fail "$1: a row differs (the lines above name it with its waiting|starts|source or hold|count)"
  fi
  rows_bad=
}
want_same_rem() { # a row compared with an empty record is a failure: the record itself could not be read
  if [ -z "$3" ]; then want_eq "$1 (the recorded state|waiting|starts|source)" "" "a value"; else want_eq "$1 (state|waiting|starts|source)" "$(rem_probe "$2")" "$3"; fi
}
want_same_hold() {
  if [ -z "$3" ]; then want_eq "$1 (the recorded hold|count)" "" "a value"; else want_eq "$1 (hold|count)" "$(hold_probe "$2")" "$3"; fi
}
want_rearmed_rem() { # want_rearmed_rem <name> <ref> <probe before>: one waiter and one more start, from HeartbeatIn
  want_eq "$1 (state|waiting|starts|source)" "$(rem_probe "$2")" "$(printf '%s' "$3" | awk -F'|' '{ printf "%s|1|%d|HeartbeatIn", $1, $3 + 1 }')"
}
want_rearmed_hold() { # want_rearmed_hold <name> <ref> <probe before>: a live hold and one more hold instance
  local got
  got=$(hold_probe "$2")
  if [ -z "${got%%|*}" ] || [ "${got#*|}" != "$(printf '%s' "$3" | awk -F'|' '{ print $2 + 1 }')" ]; then
    rows_bad="${rows_bad}
  $1 (hold|count): got '$got', wanted a live hold and $(printf '%s' "$3" | awk -F'|' '{ print $2 + 1 }') hold instance(s)"
  fi
}
want_alive_rem() { want_eq "$1 (state|waiting)" "$(rem_probe "$2" | cut -d'|' -f1,2)" "pending|1"; }
want_alive_hold() { # a live hold and exactly one hold instance
  local got
  got=$(hold_probe "$2")
  if [ -z "${got%%|*}" ] || [ "${got#*|}" != 1 ]; then rows_bad="${rows_bad}
  $1 (hold|count): got '$got', wanted a live hold and 1 hold instance"; fi
}

# rl_due_ok: RL, when it is due, still waits or has fired exactly once (a waiter that is waking may look lost to a Reconcile, so its start
# headers are not read once it is due).
rl_due_ok() {
  local got
  got=$(rem_probe "$RL")
  case $got in
    pending\|1\|*) return 0 ;;
    fired\|0\|*) [ "$(notify_count "$RL")" = 1 ] ;;
    *) return 1 ;;
  esac
}
# want_rl: RL is what it was after the seeding while it is not due; once due, rl_due_ok.
want_rl() {
  if [ "$SECONDS" -lt "$rl_due_s" ]; then
    want_same_rem RL "$RL" "$P_RL"
  elif ! wait_until 30 rl_due_ok; then
    rows_bad="${rows_bad}
  RL (state|waiting|starts|source, due): got '$(rem_probe "$RL")', wanted a waiter or one fired notification"
  fi
}

# jobs_changed <label> <jobs before> <jobs after>: item_jobs files; every item that had jobs has other jobs now.
jobs_changed() {
  local same
  same=$(awk -F'\t' 'NR == FNR { a[$1] = $2; next } !($1 in a) { print $1 " (no job after)"; next } a[$1] == $2 { print $1 " (job " $2 ")" }' "$3" "$2")
  if [ -s "$2" ] && [ -s "$3" ] && [ -z "$same" ]; then
    pass "$1: every item has new jobs ($(grep -c . "$2") items)"
  else
    printf '%s\n' "$same" | sed 's/^/  unchanged: /'
    fail "$1: an item kept its jobs (or the jobs before or after could not be read)"
  fi
}

# prod_ready: the production runs and nothing is missing.
prod_ready() {
  [ "$(printf '%s\n' 'Set r=##class(Ens.Director).IsProductionRunning(.n) Write !,"CHK|ready|",+r,"|",$Get(n),"|",##class(OcuTalon.Install.Step.Production).NotRunning()' 'Halt' | chk ready)" = "1|OcuTalon.Production|" ]
}

# --- path B: the checks 21 to 25 ---

# check_restart_alone (check 21, DW-80): the production stops and starts from a session, with no installer run.
check_restart_alone() {
  local before started=$SECONDS
  before=$(reconcile_rows)
  stop_start prod-alone
  one_new_row "$before" "production alone" "a stop and start from a session"
  rows_bad=
  want_rl
  want_rearmed_rem RX "$RX" "$P_RX"
  want_rearmed_hold AX "$AX" "$P_AX"
  report_rows "production alone" "RX has one waiter and one more start from HeartbeatIn, AX has one live hold, and RL keeps its waiter"
  P_RX=$(rem_probe "$RX")
  P_AX=$(hold_probe "$AX")
  echo "TIME restart-alone $((SECONDS - started))s"
}

# instance_restart <n>: docker compose restart of the instance; waits until the production runs with nothing missing, within the run's
# deadline, and records the count of ReconcileIn's rows before it.
instance_restart() {
  local started=$SECONDS
  restart_rows_before=$(reconcile_rows)
  if ! dc restart iris > "$tmp/restart-$1.log" 2>&1; then
    tail -n 20 "$tmp/restart-$1.log"
    die "instance restart $1: docker compose restart iris failed"
  fi
  if ! wait_until "$((deadline - SECONDS))" prod_ready; then
    die "instance restart $1: the production does not run with nothing missing before the run's deadline"
  fi
  echo "TIME restart-$1 $((SECONDS - started))s"
}

# check_restart <n> (checks 22 and 23): after instance_restart <n>. The first restart re-arms the pair seeded before it (RY, AY) once; the
# second changes no row. RX and AX keep what the step before recorded, and RL is as want_rl says.
check_restart() {
  local label="instance restart $1"
  one_new_row "$restart_rows_before" "$label" "the restart of the instance"
  check_session "$label: ^Ens.AutoStart is OcuTalon.Production" OCUTALON "CHK|autostart|OcuTalon.Production" \
    'Write !,"CHK|autostart|",$Get(^Ens.AutoStart)' 'Halt'
  if dc exec -T iris test ! -e /opt/ocutalon/version; then
    pass "$label: the container has no /opt/ocutalon/version, so there is no after-start script"
  else
    fail "$label: the container has /opt/ocutalon/version"
  fi
  rows_bad=
  want_rl
  want_same_rem RX "$RX" "$P_RX"
  want_same_hold AX "$AX" "$P_AX"
  if [ "$1" = 1 ]; then
    want_rearmed_rem RY "$RY" "$P_RY"
    want_rearmed_hold AY "$AY" "$P_AY"
    report_rows "$label" "RY and AY are re-armed once (one waiter and one more start from HeartbeatIn; one live hold), and RL, RX and AX are unchanged"
  else
    want_same_rem RY "$RY" "$P_RY"
    want_same_hold AY "$AY" "$P_AY"
    report_rows "$label" "every row has the one waiter or hold of the step before, with the same start counts and hold ids"
  fi
  P_RY=$(rem_probe "$RY")
  P_AY=$(hold_probe "$AY")
}

# rl_ended: RL's waiter has ended and the reminder is fired.
rl_ended() {
  [ "$(printf '%s\n' 'Set ref="'"$RL"'",ok=##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(ref,2),row=##class(OcuTalon.Data.Reminder).RefIndexOpen(ref) Write !,"CHK|ended|",ok,"|",row.State' 'Halt' | chk ended)" = "1|fired" ]
}
rl_notified() { [ "$(notify_count "$RL")" -ge 1 ] 2> /dev/null; }
hold_ended() { [ -z "$(hold_probe "$AX" | cut -d'|' -f1)" ]; }

# check_after_restarts (check 24): after the restarts the conversation is unchanged, RL fires once, AX is rejected, and the other lost
# rows are still armed.
check_after_restarts() {
  local started=$SECONDS max answer
  max=$((rl_due_s - SECONDS + 150))
  if [ "$max" -lt 30 ]; then max=30; fi
  wait_until "$max" rl_ended || true
  wait_until 30 rl_notified || true
  answer=$(printf '%s\n' 'Set r=##class(OcuTalon.Bridge.Approval).Answer("'"$AX"'","reject","web","ocutalon","",.w) Write !,"CHK|answer|",r' 'Halt' | chk answer)
  wait_until 30 hold_ended || true
  rows_bad=
  want_eq "RL (state|waiting)" "$(rem_probe "$RL" | cut -d'|' -f1,2)" "fired|0"
  want_eq "RL (ReminderTimer to Notify headers)" "$(notify_count "$RL")" 1
  want_eq "AX (Answer)" "$answer" done
  want_eq "AX (state)" "$(approval_state "$AX")" rejected
  want_eq "AX (live hold)" "$(hold_probe "$AX" | cut -d'|' -f1)" ""
  want_same_rem RX "$RX" "$P_RX"
  want_same_rem RY "$RY" "$P_RY"
  want_alive_rem RX "$RX"
  want_alive_rem RY "$RY"
  want_alive_hold AY "$AY"
  want_eq "AY (state)" "$(approval_state "$AY")" pending
  want_same_hold AY "$AY" "$P_AY"
  want_eq "the session and its turn" "$(conv_probe)" "$CONV0"
  report_rows "after the restarts" "RL fired once, AX is answered done and rejected and its hold has ended, RX, RY and AY are still armed, and the session and its turn are unchanged"
  echo "TIME after-restarts $((SECONDS - started))s"
}

# check_foreign <label>: the foreign password-validation setting and routine of path B are unchanged.
check_foreign() {
  check_session "$1: the foreign password-validation setting and routine are unchanged" %SYS \
    "CHK|setting|ZzOther^ZzForeign
CHK|routine|1" \
    'Do ##class(Security.System).Get(,.p) Write !,"CHK|setting|",$Get(p("PasswordValidationRoutine"))' \
    'Write !,"CHK|routine|",+##class(%Routine).Exists("ZzForeign.mac")' \
    'Halt'
}

# reinstall_next (check 25): the install command with the next version, from a scratch copy of the package folder with only <Version>
# raised, on the stack of path B after the restart checks.
reinstall_next() {
  local copy=/tmp/ocutalon-scratch-next ver raised rows started=$SECONDS label="reinstall, next version" memory_before memory_after resources_before resources_after
  ver=$(module_version)
  raised=$(printf '%s' "$ver" | awk -F. 'NF == 3 { print $1 "." $2 "." $3 + 1 }')
  if [ -z "$raised" ]; then
    fail "$label: the module version '$ver' is not major.minor.patch"
    return
  fi
  item_jobs "$tmp/jobs-next-before.tsv"
  rows=$(reconcile_rows)
  memory_before=$(memory_fingerprint)
  resources_before=$(resources_fingerprint)
  scratch_copy "$copy" \
    "sed -i 's|<Version>$ver</Version>|<Version>$raised</Version>|' $copy/module.xml" \
    "printf '<!-- %s -->\\n' $raised >> $copy/ocutalon/csp/index.html" \
    "grep -c '<Version>$raised</Version>' $copy/module.xml" > "$tmp/scratch-next.out" 2>&1
  if [ "$(grep -v '^$' "$tmp/scratch-next.out" | tail -n 1 | tr -d '\r')" != 1 ]; then
    cat "$tmp/scratch-next.out"
    fail "$label: the scratch copy with the next version could not be made"
    return
  fi
  printf '%s\n' \
    'Set d=$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/",n=0' \
    'For f="main-ZZSTALE0.js","zz-admin-note.txt" { Set s=##class(%Stream.FileBinary).%New() Do s.LinkToFile(d_f) Do s.Write("planted by the reinstall check") Do s.%Save() Kill s Set n=n+$Select(##class(%File).Exists(d_f):1,1:0) }' \
    'Write !,"CHK|planted|",n' \
    'Halt' | iris_script OCUTALON > "$tmp/plant.chk"
  if [ "$(cat "$tmp/plant.chk")" = "CHK|planted|2" ]; then
    pass "$label: main-ZZSTALE0.js and zz-admin-note.txt are planted in csp/ocutalon-web/"
  else
    fail "$label: the stale file and the note could not be planted in csp/ocutalon-web/ ($(cat "$tmp/plant.chk"))"
  fi
  run reinstall-next OCUTALON "zpm \"load $copy\""
  check_run_ok reinstall-next "$label"
  check_session "$label: the module's Root is the folder that was loaded, and the Web step's BuildFolder() is its ocutalon/csp/ (measured)" OCUTALON \
    "CHK|root|$copy/
CHK|build|$copy/ocutalon/csp/" \
    'Write !,"CHK|root|",##class(OcuTalon.Install.Step.Web).ModuleRoot()' \
    'Write !,"CHK|build|",##class(OcuTalon.Install.Step.Web).BuildFolder()' \
    'Halt'
  check_session "$label: the stale file is gone, the note stays, and the served index.html is the new folder's" OCUTALON \
    "CHK|stale|0
CHK|note|1
CHK|same|1" \
    'Set d=$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/"' \
    'Write !,"CHK|stale|",+##class(%File).Exists(d_"main-ZZSTALE0.js")' \
    'Write !,"CHK|note|",+##class(%File).Exists(d_"zz-admin-note.txt")' \
    "Write !,\"CHK|same|\",+##class(%File).Compare(d_\"index.html\",\"$copy/ocutalon/csp/index.html\")" \
    'Halt'
  if grep -q '^WARN Web removed old web file main-ZZSTALE0.js$' "$tmp/reinstall-next.txt"; then
    pass "$label: the install output names the removed file (WARN Web removed old web file main-ZZSTALE0.js)"
  else
    fail "$label: the install output has no WARN Web line for main-ZZSTALE0.js"
  fi
  memory_after=$(memory_fingerprint)
  if [ -n "$memory_before" ] && [ "$memory_before" = "$memory_after" ]; then
    pass "$label: <mgr>/fastembed/ is unchanged, so nothing was downloaded again ($memory_after)"
  else
    fail "$label: <mgr>/fastembed/ went from '$memory_before' to '$memory_after'"
  fi
  resources_after=$(resources_fingerprint)
  if [ -n "$resources_before" ] && [ "$resources_before" = "$resources_after" ]; then
    pass "$label: the Python resources in <mgr>/python are unchanged ($resources_after)"
  else
    fail "$label: the Python resources in <mgr>/python went from '$resources_before' to '$resources_after'"
  fi
  if [ "$(module_version)" = "$raised" ]; then
    pass "$label: the module is recorded with version $raised"
  else
    fail "$label: the module version is '$(module_version)', wanted $raised"
  fi
  item_jobs "$tmp/jobs-next-after.tsv"
  jobs_changed "$label" "$tmp/jobs-next-before.tsv" "$tmp/jobs-next-after.tsv"
  sleep 15
  if [ -n "$rows" ] && [ "$(reconcile_rows)" = "$rows" ]; then
    pass "$label: ReconcileIn logged no new Info row, because the Production step made the start ($rows)"
  else
    fail "$label: ReconcileIn's Info rows went $rows -> $(reconcile_rows)"
  fi
  take_snapshot reinstall-next "$label"
  same_services "$label" base-b reinstall-next
  same_config "$label" second-merge reinstall-next
  check_foreign "$label"
  rows_bad=
  want_eq "the session and its turn" "$(conv_probe)" "$CONV0"
  want_alive_rem RX "$RX"
  want_alive_rem RY "$RY"
  want_alive_hold AY "$AY"
  report_rows "$label" "the session and its turn are intact, and RX, RY and AY each have one waiter or hold"
  echo "TIME check-reinstall-next $((SECONDS - started))s"
}

# check_durable_recovery (check 20): after part r's recovery run, the data seeded before the forced failure is intact and armed once.
check_durable_recovery() {
  rows_bad=
  want_eq "the session and its turn" "$(conv_probe)" "$CONV0"
  want_alive_rem RL "$RL"
  want_alive_hold AX "$AX"
  report_rows "recovery run passes 15.3's checks" "the session and its turn are intact, RL has one waiter and AX one live hold"
  item_jobs "$tmp/jobs-recover-after.tsv"
  jobs_changed "recovery run" "$tmp/jobs-recover-before.tsv" "$tmp/jobs-recover-after.tsv"
}

# --- part p (Story 15.4): the exact release artifact, installed from an IPM repository ---

# ipm_precondition <label>: IPM 0.10.10 is loaded in %SYS and enabled for USER only (check 1); a failure stops the run.
ipm_precondition() {
  local before=$fails
  check_session "$1: IPM 0.10.10 is loaded in %SYS and enabled for USER only" %SYS \
    "CHK|load|1
CHK|enable|1" \
    'Set sc=$SYSTEM.OBJ.Load("/opt/ocutalon-ipm/zpm-0.10.10.xml","ck-d") Write !,"CHK|load|",$SYSTEM.Status.IsOK(sc)' \
    'Set sc=##class(%IPM.Main).Shell("enable -map -ns USER -q") Write !,"CHK|enable|",$SYSTEM.Status.IsOK(sc)' \
    'Halt'
  if [ "$fails" -ne "$before" ]; then die "IPM could not be loaded and enabled for USER"; fi
}

# derive_dbs <base snapshot>: ipm_db, the database where %IPM resolves in USER (from the snapshot's mapping), and repo_db, the database
# where USER resolves ^IPM.Repo.DefinitionD (a probe of GetGlobalDest, resolved to the database name).
derive_dbs() {
  ipm_db=$(sed -n 's/^CHK|umap-MapPackages|%IPM|//p' "$1" | head -n 1)
  if [ -z "$ipm_db" ]; then die "precondition: IPM is not mapped into USER"; fi
  repo_db=$(printf '%s\n' \
    'Set d=##class(%SYS.Namespace).GetGlobalDest("USER","^IPM.Repo.DefinitionD") Set sc=##class(Config.Databases).DatabasesByDirectory($Piece(d,"^"),$Piece(d,"^",2),.l) Write !,"CHK|repodb|",$ListGet($Get(l))' \
    'Halt' | session_value %SYS repodb)
  if [ -z "$repo_db" ]; then die "precondition: the database of IPM's repository definitions could not be read"; fi
}

# expect_first_config <label> <snapshot>: the snapshot of a first run in USER (check 3): the Interoperability flag, the four databases, AD-3's
# seven mappings, the %IPM mappings and the three repository mappings.
expect_first_config() {
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
CHK|omap-MapGlobals|IPM.Repo.DefinitionD|$repo_db
CHK|omap-MapGlobals|IPM.Repo.DefinitionI|$repo_db
CHK|omap-MapGlobals|IPM.Repo.DefinitionS|$repo_db
CHK|omap-MapPackages|OcuTalon.Web.Public|OCUTALON_PUBLIC
CHK|omap-MapPackages|OcuTalon.Data.Public|OCUTALON_PUBLIC
CHK|omap-MapPackages|%IPM|$ipm_db
CHK|omap-MapRoutines|%IPM.*|$ipm_db
EOE
  compare_chk "$1: the databases, the Interoperability flag, AD-3's seven mappings, the %IPM mappings and the repository mappings" "$2" "$tmp/expected.chk"
}

# check_no_repo_data <label>: OCUTALON_DATA, read by its directory, holds no ^IPM.Repo.Definition* node (the mapping moved nothing into it).
check_no_repo_data() {
  check_session "$1: OCUTALON_DATA holds no ^IPM.Repo.Definition* node" %SYS "CHK|repodata|0" \
    'Do ##class(Config.Databases).Get("OCUTALON_DATA",.p) Set dir=p("Directory"),n=0' \
    'For g="IPM.Repo.DefinitionD","IPM.Repo.DefinitionS","IPM.Repo.DefinitionI" { Set r="^|""^^"_dir_"""|"_g Set:$Data(@r) n=n+1 }' \
    'Write !,"CHK|repodata|",n' \
    'Halt'
}

# defs_hash: "<nodes>|<hash>" of USER's three repository definition globals, computed in the container. A caller keeps it in a variable
# and never prints it: the definitions' fields stay in the container.
defs_hash() {
  printf '%s\n' \
    'Set h="",n=0 For g="^IPM.Repo.DefinitionD","^IPM.Repo.DefinitionS","^IPM.Repo.DefinitionI" { Set r=g If $Data(@r)#2 { Set n=n+1,h=$SYSTEM.Encryption.SHAHash(256,h_r_@r) } For { Set r=$Query(@r) Quit:r=""  Quit:$Piece(r,"(")'"'"'=g  Set n=n+1,h=$SYSTEM.Encryption.SHAHash(256,h_r_@r) } }' \
    'Write !,"CHK|defs|",n,"|",$SYSTEM.Encryption.Base64Encode(h)' \
    'Halt' | session_value USER defs
}

# artifact_prepare: sets $art to the checked artifact ocutalon-<version>.tgz, or to nothing after a failure. It is OCUTALON_IPM_ARTIFACT
# when that is set; otherwise the module that path A's second run installed in OCUTALON, packaged with `zpm "package ocutalon -only"`
# (TIME package) and copied out. ipm_artifact_check reads it (module name and version, FileCopy, the web bundle byte for byte) in the
# layout of what packed it: root for OCUTALON_IPM_ARTIFACT, src for this script's own package.
artifact_prepare() {
  local ver problems bytes layout=src
  art=""
  ver=$(manifest_version "$root/src/module.xml")
  if [ -n "${OCUTALON_IPM_ARTIFACT:-}" ]; then
    if [ -f "$OCUTALON_IPM_ARTIFACT" ]; then
      layout=root
      art="$(cd "$(dirname "$OCUTALON_IPM_ARTIFACT")" && pwd)/$(basename "$OCUTALON_IPM_ARTIFACT")"
    else
      fail "artifact: OCUTALON_IPM_ARTIFACT names no file"
      return
    fi
  else
    dc exec -T iris mkdir -p /tmp/ocutalon-pkg > /dev/null 2>&1
    run package OCUTALON "zpm \"package ocutalon -only -path /tmp/ocutalon-pkg/ocutalon-$ver\""
    if dc cp "iris:/tmp/ocutalon-pkg/ocutalon-$ver.tgz" "$tmp/ocutalon-$ver.tgz" > /dev/null 2>&1; then
      art="$tmp/ocutalon-$ver.tgz"
    else
      fail "artifact: zpm \"package ocutalon -only\" left no ocutalon-$ver.tgz"
      return
    fi
  fi
  bytes=$(wc -c < "$art" | tr -d ' ')
  echo "ARTIFACT ocutalon-$ver.tgz $bytes bytes"
  problems=$(ipm_artifact_check "$art" "$ver" "$root" "$layout")
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" | sed 's/^/  artifact: /'
    fail "artifact: ocutalon-$ver.tgz does not carry the module and the web bundle ($(printf '%s\n' "$problems" | head -n 1))"
    art=""
    return
  fi
  pass "artifact: ocutalon-$ver.tgz ($bytes bytes) carries the module's name and version and every file of the web bundle"
}

# part_p (checks 26 to 29): on a fresh instance with IPM and no Node.js, the artifact in a local filesystem repository is installed with
# `zpm "install ocutalon"` in USER and in OCUTALON, signed in to, then uninstalled; the definitions are unchanged (U-232 condition 1).
part_p() {
  local started=$SECONDS ver ext h0 h1 h2 n
  if [ -z "${art:-}" ]; then
    fail "part p: there is no checked artifact to install"
    return
  fi
  ver=$(manifest_version "$root/src/module.xml")
  echo "PART p: ocutalon-$ver.tgz from a local IPM repository on a fresh instance"
  dc down -v > "$tmp/down.log" 2>&1
  if ! dc up -d --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    die "the part p stack did not become ready"
  fi
  echo "TIME ready-p $((SECONDS - started))s"
  stage_licence_gate
  ipm_precondition "part p"
  take_snapshot p-base "part p"
  derive_dbs "$tmp/p-base.snap"
  if dc exec -T iris sh -c '! command -v node > /dev/null 2>&1 && ! command -v npm > /dev/null 2>&1'; then
    pass "part p: the container has no node and no npm"
  else
    fail "part p: the container has node or npm"
  fi
  ext="$tmp/p-repo/ocutalon-$ver"
  rm -rf "$tmp/p-repo"
  mkdir -p "$tmp/p-repo"
  if ipm_unpack "$art" "$ext" \
    && dc exec -T -u root iris mkdir -p /tmp/ocutalon-repo > /dev/null 2>&1 \
    && dc cp "$ext" "iris:/tmp/ocutalon-repo/ocutalon-$ver" > /dev/null 2>&1 \
    && dc exec -T -u root iris chmod -R a+rX /tmp/ocutalon-repo > /dev/null 2>&1; then
    pass "part p: the artifact is unpacked into /tmp/ocutalon-repo/ocutalon-$ver of the container"
  else
    die "part p: the artifact could not be unpacked into the container"
  fi
  # The repository is added in a session whose output is discarded: the repository definitions are never printed.
  printf '%s\nHalt\n' 'zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/ocutalon-repo/"' | dc exec -T iris iris session IRIS -U USER > /dev/null 2>&1
  h0=$(defs_hash)
  snapshot_python_before
  run p-first USER 'zpm "install ocutalon"'
  take_snapshot p-first "part p first command"
  stops_with_next_command p-first "part p, the install command in USER"
  expect_first_config "part p, the install command in USER" "$tmp/p-first.snap"
  check_no_repo_data "part p, the install command in USER"
  # A filesystem repository keeps the list of its modules (a cache, ^IPM.Repo.Filesystem.Cache*) apart from its definition, in each
  # namespace. The definition that OCUTALON sees is the mapped one, opened by name and left as it is; only the module list of OCUTALON is built.
  check_session "part p, before the same command in OCUTALON: the mapped repository is found there and its module list is built" OCUTALON "CHK|cache|1" \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM %IPM_Repo.Definition WHERE Name = ?","ocutalon-local") Set ok=0' \
    'If rs.%Next() { Set repo=##class(%IPM.Repo.Definition).%OpenId(rs.%GetData(1)) Set ok=$SYSTEM.Status.IsOK(repo.BuildCache(1,0,0)) }' \
    'Write !,"CHK|cache|",ok' \
    'Halt'
  check_no_repo_data "part p, before the same command in OCUTALON"
  run p-second OCUTALON 'zpm "install ocutalon"'
  check_run_ok p-second "part p, the same command in OCUTALON"
  check_licences "part p"
  check_python_pins "part p"
  check_extract "part p"
  check_signin "part p" logout
  take_snapshot p-second "part p second command"
  same_config "part p, the same command in OCUTALON" p-first p-second
  h1=$(defs_hash)
  run p-uninstall OCUTALON 'zpm "uninstall ocutalon"'
  take_snapshot p-uninstall "part p uninstall"
  h2=$(defs_hash)
  uninstall_checks "$h0" "$h1" "$h2"
  check_uninstall_python "part p uninstall"
  run p-again USER 'zpm "install ocutalon"'
  stops_with_next_command p-again "part p, the install command in USER after the uninstall (from the local repository)"
  echo "TIME p-fresh $((SECONDS - started))s"
}

# check_uninstall_python <label> (check 32, Story 19.8, DW-829 condition 3): after the uninstall, the Python folder holds every distribution and
# every top-level item that it held after the install, but the two Python resources that the uninstall's FileCopy removal may take
# (ocutalon_extract.py and ocutalon_memory.py), so the six stay in place; they still import their pinned copies, IPM's own packages import as
# before the install (the import record names the same modules both times, and an empty one fails) and zpm "list" answers.
check_uninstall_python() {
  local label=$1 mgr out rc now started=$SECONDS
  mgr=$(printf '%s\n' 'Write !,"CHK|mgr|",$SYSTEM.Util.ManagerDirectory()' 'Halt' | chk mgr)
  if [ -z "$mgr" ]; then
    fail "$label: the manager directory could not be read, so the folder comparison did not run"
    return
  fi
  python_state "${mgr}python" /tmp/ocutalon-python-uninstalled.state || { fail "$label: the Python folder's entries could not be recorded"; return; }
  now=$(python_imports)
  out=$(dc exec -T iris python3 - /tmp/ocutalon-python-after.state /tmp/ocutalon-python-uninstalled.state /tmp/ocutalon-imports-before.txt "$now" 2>&1 << 'EOP'
import re, sys
after_file, gone_file, imports_before, imports_after = sys.argv[1:5]
def load(path):
    dists, tops = {}, set()
    for line in open(path):
        parts = line.split()
        if parts and parts[0] == "D":
            dists[parts[1]] = parts[2]
        elif parts and parts[0] == "T":
            tops.add(parts[1])
    return dists, tops
ad, at = load(after_file)
ud, ut = load(gone_file)
resources = {"ocutalon_extract.py", "ocutalon_memory.py"}
problems = []
for entry, digest in sorted(ad.items()):
    if entry not in ud:
        problems.append("%s is gone" % entry)
    elif ud[entry] != digest:
        problems.append("%s changed" % entry)
for entry in sorted(set(ud) - set(ad)):
    problems.append("%s was added" % entry)
for item in sorted(at - ut):
    if item not in resources:
        problems.append("top-level item %s is gone" % item)
for item in sorted(ut - at):
    problems.append("top-level item %s was added" % item)
def imports(text):
    return dict(re.findall(r"CHK\|imp\|([^|]+)\|(\d)", text))
ib, ia = imports(open(imports_before).read()), imports(imports_after)
if not ib or set(ib) != set(ia):
    problems.append("the import record of IPM's packages is empty or not the same list before and after (%d and %d modules)" % (len(ib), len(ia)))
for module, ok in sorted(ib.items()):
    if ok == "1" and ia.get(module) != "1":
        problems.append("%s imported before the install and does not now" % module)
print("NOTE after the uninstall: %d distributions (%d after the install); removed top-level items: %s" % (len(ud), len(ad), ", ".join(sorted(at - ut)) or "none"))
for problem in problems:
    print("PROBLEM " + problem)
sys.exit(1 if problems else 0)
EOP
)
  rc=$?
  printf '%s\n' "$out" | tr -d '\r' | grep -e '^NOTE' -e '^PROBLEM' | cut -c1-400 | sed 's/^/  /'
  if [ "$rc" -eq 0 ]; then
    pass "$label: the uninstall leaves the Python folder's distributions in place (only the two Python resources may go), and IPM's own packages import as before"
  else
    fail "$label: the uninstall removed or changed a distribution of the Python folder, or an IPM package no longer imports"
  fi
  check_imports "$label"
  check_ipm_alive "$label" .
  echo "TIME uninstall-python $((SECONDS - started))s"
}

# uninstall_checks <hash before the first command> <hash before the uninstall> <hash after it> (U-232 condition 1; the hashes are
# "<nodes>|<hash>" and are never printed): the uninstall ended without an error, OCUTALON's three repository mappings are gone and the
# rest of the configuration is that of the second command, and USER's definitions are unchanged.
uninstall_checks() {
  local n=${3%%|*} f="$tmp/p-uninstall.txt"
  if ! grep -q 'FAILURE' "$f" && ! grep -q '^ERROR!' "$f"; then
    pass "part p uninstall: zpm \"uninstall ocutalon\" in OCUTALON ends without a FAILURE or ERROR! line"
  else
    grep -e 'FAILURE' -e '^ERROR!' "$f" | sed 's/^/  uninstall: /'
    fail "part p uninstall: the uninstall reported a FAILURE or an ERROR! line"
  fi
  : > "$tmp/snap.diff"
  if [ "$(grep -c '^CHK|omap-MapGlobals|IPM.Repo.Definition' "$tmp/p-second.snap")" = 3 ] \
    && ! grep -q '^CHK|omap-MapGlobals|IPM.Repo.Definition' "$tmp/p-uninstall.snap" \
    && diff <(grep -v '^CHK|omap-MapGlobals|IPM.Repo.Definition' "$tmp/p-second.snap") "$tmp/p-uninstall.snap" > "$tmp/snap.diff"; then
    pass "part p uninstall: OCUTALON's three repository mappings are gone; every other OCUTALON mapping, USER's mappings and the services are unchanged"
  else
    sed 's/^/  snapshot: /' "$tmp/snap.diff"
    grep '^CHK|omap-MapGlobals|IPM.Repo.Definition' "$tmp/p-uninstall.snap" | sed 's/^/  kept: /'
    fail "part p uninstall: the uninstall changed more than OCUTALON's three repository mappings, or left one"
  fi
  if [ "$n" -gt 0 ] 2> /dev/null && [ "$2" = "$3" ] && [ "$1" = "$3" ]; then
    pass "part p uninstall: USER's repository definitions are unchanged: same|$n"
  else
    if [ "$2" != "$3" ]; then
      echo "  definitions: differs|${n:-0} (after the uninstall, against before it)"
    elif [ "$1" != "$3" ]; then
      echo "  definitions: differs|${n:-0} (after the uninstall, against before the first command)"
    fi
    fail "part p uninstall: USER's repository definitions differ, or there are none (differs, or 0 nodes)"
  fi
}

# finish: the result lines and the exit code.
finish() {
  if [ "$fails" -ne 0 ]; then
    echo "$(basename "$SCRIPT" .sh): $fails check(s) failed (project $P)"
    exit 1
  fi
  echo "$(basename "$SCRIPT" .sh): all checks passed"
  exit 0
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
stage_requirements
stage_licence_gate

# --- part p alone: the package is installed from the folder and packaged first when there is no OCUTALON_IPM_ARTIFACT ---

art=""
if [ "$mode" = p ]; then
  if [ -n "${OCUTALON_IPM_ARTIFACT:-}" ]; then
    artifact_prepare
  else
    ipm_precondition "packaging stack"
    run pkg-first USER "$INSTALL"
    run pkg-second OCUTALON "$INSTALL"
    check_session "packaging stack: the package is installed in OCUTALON" OCUTALON "CHK|module|ocutalon" \
      'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|module|",$Select($IsObject(m):m.Name,1:"<none>")' \
      'Halt'
    artifact_prepare
  fi
  part_p
  finish
fi

# --- path A: two package runs ---

ipm_precondition precondition
take_snapshot base "precondition"
if ! grep -q '^CHK|ns|' "$tmp/base.snap" && ! grep -q '^CHK|db|' "$tmp/base.snap"; then
  pass "precondition: OCUTALON and its databases do not exist yet"
else
  die "precondition: OCUTALON or its databases exist before the first run"
fi
derive_dbs "$tmp/base.snap"
check_no_residue "precondition"

run first-sys %SYS "$INSTALL"
take_snapshot first-sys "first run in %SYS"
if [ "$(final_line "$tmp/first-sys.txt")" = "ERROR! $REFUSAL" ] && ! grep -q 'Initialize START' "$tmp/first-sys.txt"; then
  pass "first run in %SYS: IPM refuses the package with its interoperability line before any phase (no Initialize START line)"
else
  echo "  last line: '$(final_line "$tmp/first-sys.txt")'"
  grep -n 'Initialize START' "$tmp/first-sys.txt" | sed 's/^/  found: /'
  fail "first run in %SYS: the last line is not IPM's refusal ERROR! line, or a phase started"
fi
if diff "$tmp/base.snap" "$tmp/first-sys.snap" > "$tmp/snap.diff"; then
  pass "first run in %SYS: OCUTALON, its databases, resources and mappings, USER's mappings and the services are those of the precondition: nothing was created"
else
  sed 's/^/  snapshot: /' "$tmp/snap.diff"
  fail "first run in %SYS: the configuration changed (the refusal left something behind)"
fi
check_no_residue "first run in %SYS"

run first-user USER "$INSTALL"
take_snapshot first "first run in USER"
stops_with_next_command first-user "first run in USER"
expect_first_config "first run in USER" "$tmp/first.snap"
check_no_repo_data "first run in USER"
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
  snapshot_python_before
  run second-ocutalon OCUTALON "$INSTALL"
  check_second_run
  if [ "$mode" = all ]; then artifact_prepare; fi
  if [ "$mode" != r ]; then
    check_install
    check_memory
    check_licences "install checks"
    check_python_pins "install checks"
    check_extract "install checks"
    check_web
    check_package
    check_demo_switch
    check_start_outside
    check_start_by_step
    check_reinstall
    check_pip_skipped "pip skipped"
  fi
  if [ "$mode" != a ]; then reinstall_failures; fi
fi

if [ "$mode" = a ] || [ "$mode" = r ]; then finish; fi

# --- path B: iris merge on a fresh instance ---

echo "PATH B: iris merge of /opt/ocutalon-ipm/src/cpf/ocutalon.cpf on a fresh instance"
started=$SECONDS
dc down -v > "$tmp/down.log" 2>&1
if ! dc up -d --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "the second stack did not become ready"
fi
echo "TIME ready-b $((SECONDS - started))s"
stage_requirements
stage_licence_gate
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
# The OCUTALON view of path B is that of path A without the two %IPM mappings and the three repository mappings, and holds none; USER's
# mappings and the services are not part of the view.
view() { grep -v -e '^CHK|service|' -e '^CHK|umap-' -e '%IPM' -e 'IPM.Repo.Definition' "$1"; }
if view "$tmp/first.snap" > "$tmp/view-a" && view "$tmp/merge.snap" > "$tmp/view-b" && [ -s "$tmp/view-b" ] \
  && diff "$tmp/view-a" "$tmp/view-b" > "$tmp/snap.diff" && ! grep -q -e '%IPM' -e 'IPM.Repo.Definition' "$tmp/merge.snap"; then
  pass "path B: OCUTALON's namespace row, Interoperability flag, databases, resources and mappings are path A's, without the %IPM and repository mappings ($(grep -c . "$tmp/view-b") lines)"
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
order=$(registry_order)
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
check_foreign "path B"
foreign_after=$(foreign_orders)
if [ -n "$foreign_before" ] && [ "$foreign_before" = "$foreign_after" ]; then
  pass "path B: the foreign OCUORDERS and its databases are unchanged ($foreign_after)"
else
  fail "path B: the foreign OCUORDERS changed, from '$foreign_before' to '$foreign_after'"
fi
same_services "path B second run" base-b second-merge
check_ipm_case "path B second run"

# --- path B: the production restarts alone, two instance restarts and the next version (checks 21 to 25) ---

seed_durable 180
check_restart_alone
seed_pair
instance_restart 1
check_restart 1
instance_restart 2
check_restart 2
check_after_restarts
reinstall_next

# --- part p: the artifact from a local IPM repository, on a fresh instance ---

if [ "$mode" = all ]; then part_p; fi
finish
