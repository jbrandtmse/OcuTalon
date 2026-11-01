#!/usr/bin/env bash
# release/rehearse.sh <command> [--version <v>] --rc <n> [--candidate <ref>] [--record <file>] [--runs <n>] [--plant <bound id>] [--dry-run]
#
# The clean-machine rehearsal (Stories 11.3 and 11.11; FR-55, NFR-3, NFR-7 to NFR-11, NFR-22, REL-6, P30, UX-DR102; AD-15, AD-19, AD-22, AD-23, AD-25).
# A release gate that runs by hand and in Story 11.5's sequence; it is no CI unit. It copies a release candidate to a clean host as a git
# bundle, clones it there, puts the author's .env beside it, runs install.sh, signs in from a second (driver) host at the address that
# install.sh printed, times the first start, then times the demo path (the REL-2 specs, web/e2e/demo-path/) against the install and checks
# every bound, and writes the result into the candidate's record. This build has no clean host, no driver host and no real key, so the script
# is proved on throwaways with --dry-run, whose result is "dry run" and never a pass; the real 20 runs are Story 38.2's. A real rehearsal
# cannot pass yet either: its tell-now row is "not run" until Story 11.12 adds the repeats and the tell-now item.
#
# Commands:
#   plan     prints the candidate, its version and sha, how each host is reached (configured, local or stand-in), the phases and the
#            record path; starts nothing
#   install  the steps hosts, copy, install and sign-in (see below); keeps the state and, in a dry run, the throwaway project and its lock
#   runs     one timed run of the demo path (see below); needs a passed install; run 2 and later (Run again and the replay rule) come with
#            Story 11.12 and are refused
#   exec [<namespace>]
#            runs the script on its standard input in an iris session of the install, through host_run clean: "cd ocutalon-rehearsal/candidate
#            && docker compose exec -T iris iris session IRIS -U <namespace>" (the namespace matches [A-Z][A-Z0-9]*, default OCUTALON). Its
#            output goes to standard output, not to output.log. It needs a passed install. It is the one channel the specs and the collector
#            read the install through; with OCUTALON_REHEARSAL_RUN=<k> in the environment it counts its calls in runs/<k>/exec.count
#   report   scans the output and the section for values (the secrets step), checks every run's marks against the bounds (bounds_eval), prints
#            a FAIL line for each miss, writes the "## Clean-machine rehearsal" section of the record and prints RECORD <file> and RESULT
#            <result>. It rebuilds the section from the state, so it may run again; with --plant <bound id> (dry run only) the one bound's limit
#            is 0, to show a missed bound
#   down     in a dry run removes the tag's projects, volumes, images and lock (ci/iris.sh teardown), then the state (runs/ with it); in real
#            mode the clean host keeps its install, and only the state is removed. It may always run
#   run      install, runs (until --runs runs exist, a run fails or runs refuses), report (with --plant), then always down; each phase is its
#            own process of this script
# Options (taken by plan, install and run; the state keeps them for report): --rc <n> (a positive whole number, required), --version <v>
# (it must equal <Version> in the candidate's src/module.xml; required unless --dry-run or --candidate is given), --candidate <ref> (a
# local branch in real mode; the default is release/<v>-rc<n>, or HEAD in a dry run), --record <file> (default
# release/records/<v>/rc<n>.md; a test passes a file outside the repository), --runs <n> (the runs a rehearsal needs: 20 or more in real mode,
# the default; 1 to 20 in a dry run, default 1), --dry-run (stand-ins for both hosts). --plant <bound id> is taken by report and run, in a dry
# run only (the ids of the Bounds table below that have a limit). In real mode plan, install and run refuse (exit 2, nothing started) a driver
# that is not local (REHEARSAL_DRIVER_SSH: the specs drive the browser on this machine), a tree of web/e2e, web/playwright.config.ts,
# web/package.json or web/package-lock.json that differs from the candidate commit (the record's Specs line is then the candidate's), and
# --runs below 20.
# The phases need OCUTALON_RUN_TAG (lower-case letters, digits and hyphens, 3 or more, no "slot"); run defaults it to reh-<epoch>. The
# state is ${TMPDIR:-/tmp}/ocutalon-rehearsal-<tag>/. install on a tag that has a state, and report with no finished install, are refused;
# runs and exec with no state, or after a failed install step, are refused (exit 2).
#
# The configuration (real mode only; a dry run never reads it): OCUTALON_RELEASE_CONFIG, else ${XDG_CONFIG_HOME:-$HOME/.config}/ocutalon/
# release.conf, outside the repository. KEY=value lines, no expansion but a leading ~/ in a path key: REHEARSAL_CLEAN_SSH (user@host),
# REHEARSAL_CLEAN_KEY, REHEARSAL_CLEAN_WEB (the clean host's name or address as the driver host reaches it; no scheme and no port),
# REHEARSAL_DRIVER_SSH (user@host, or local; a real rehearsal needs local), REHEARSAL_DRIVER_KEY (not for local), REHEARSAL_ENV_FILE
# (mode 600, outside the repository); optional REHEARSAL_CLEAN_PORT,
# REHEARSAL_DRIVER_PORT, REHEARSAL_KNOWN_HOSTS. The same file can hold Story 11.5's DEMO_ keys, which this script ignores. Every remote
# action is host_run of release/lib-release.sh: ssh with the key, BatchMode and StrictHostKeyChecking=yes (add each host's key to
# known_hosts, or name a file in REHEARSAL_KNOWN_HOSTS). Remote paths are relative to the login folder (ocutalon-rehearsal/). No value of
# the env file or the configuration is printed or recorded, and no value of the env file is put on a command line: the env file reaches
# the clone only as the standard input of one remote cat, and ssh's own messages are not shown. ssh's own arguments name the configured
# destination, key file and port.
#
# The steps, one PASS line or one line "FAIL run install step <step> bound <bound>: <detail>" each; the steps after a failed step are "not
# run" (the secrets step of report always runs):
#   hosts    both hosts answer; the clean host has git and Docker and no container or volume of the compose project (COMPOSE_PROJECT_NAME,
#            else ocutalon), and in real mode no Node.js; the driver host has curl. Each host is recorded by operating system, CPU
#            architecture and memory only
#   copy     the candidate branch as a git bundle, copied through stdin and cloned; the clone's HEAD is the candidate commit
#   install  the env file becomes the clone's .env through stdin; install.sh runs there. The seconds of that call are the first start,
#            install included; the bound is "ready within <OCUTALON_INSTALL_WAIT or 900> s"
#   sign-in  the driver host signs in at the printed address (localhost replaced by the clean host's address) with the printed user and
#            password, sent as a curl config on stdin, and the page holds <app-root. The web origin (http://<host>:<port>) and the printed user
#            are kept in the state for runs
#   secrets  (report) no value of the env file or of the configuration (a value of 8 characters or more; for the configuration, each
#            value as the script uses it and the host of each user@host too), and nothing key-like, is in the output of the phases,
#            install.sh's output or the section
#
# The timed run (runs; one run per call, bounded by OCUTALON_E2E_TIMEOUT_MS, default 480000). It takes the run's server start (UTC, milliseconds)
# through exec, runs "npm --prefix web run e2e:demo-path" on this machine against the install's origin (OCUTALON_URL), with OCUTALON_E2E_JSON,
# OCUTALON_E2E_MARKS (the page marks), OCUTALON_E2E_IRIS_EXEC (this script's exec: every IRIS read of the specs goes through host_run clean),
# OCUTALON_DEMO_PATH_MODEL (mock in a dry run, real in real mode), OCUTALON_RUN_TAG and OCUTALON_REHEARSAL_RUN=<k>; then web/scripts/
# demo-path-summary.mjs --only-telegram-skips on the report, then the collector (read-only ObjectScript through exec). Files, under
# <state>/runs/<k>/: report.json, e2e.log (also in output.log), summary.log, marks.page, marks.server, verdict, exec.count. Output: PASS or FAIL
# lines ("FAIL run <k> step <step> bound -: <reason>" for a failed spec, naming its step; a run that read nothing through exec fails with step
# run) and one "RUN <k> <bound>=<seconds> ..." line ("-" for a value that could not be measured).
# One clock per value: server values subtract two production message headers (milliseconds) or two rows' times of the install's IRIS; page
# values subtract two marks of one page (Date.now() on this machine, e2e/support/rehearsal.ts: step1_sent, step1_decision_seen,
# step1_reply_seen, approve_pressed, approval_result_seen). A server value is never subtracted from a page value. A missing mark fails the run's
# step ("FAIL run <k> step <step> bound -: missing mark(s) ...").
# The Bounds table (report; id, step, from and to, limit, rule). "19 of 20" allows floor(N/20) runs to miss it:
#   notice           incident  press to the notice's delivery (server)               60 s  19 of 20
#   pick-up          incident  first failure to the FailureBatch (server)            15 s  every run
#   settle-end       incident  first failure to the diagnosis request (server)       30 s  every run (the request follows the settle rule at once)
#   diagnosis        incident  diagnosis request to its answer (server)              20 s  every run
#   delivery         incident  the answer to the SimPhoneOut notice (server)          5 s  every run
#   median           incident  the median of notice against the typical 35 s         -     recorded
#   decision         watch     step1_sent to step1_decision_seen (page)              10 s  19 of 20
#   first-reply      watch     step1_sent to step1_reply_seen (page)                 -     recorded
#   approval-result  approval  approve_pressed to approval_result_seen (page)         2 s  19 of 20 (an upper bound: from the press)
#   reminder         reminder  due to fired (server; due in whole seconds)           10 s  every reminder
#   reminder-result  reminder  the reminder's phone message minus the result's       -     recorded, signed
#   largest-request  run       max LargestRequestTokens (server)                 100,000  every run, under
#   tell-now         tell-now  -                                                    5 s  not run until Story 11.12
# A miss prints "FAIL run <runs> step <step> bound <id> <limit>[ in 19 of 20][ (planted)]: <detail>" naming every missing run (ascending,
# comma-separated); a met bound reads "pass" in real mode and "dry run" in a dry run (the mock's timings are plumbing only).
#
# The section of the record (the order is fixed; each line starts at column 1):
#   ## Clean-machine rehearsal
#   Result: fail | dry run | not run | pass
#   Mode: dry run | rehearsal
#   Candidate: <v> rc<n>, branch <branch> at <sha>[, a stand-in of <sha> with the built web bundle added]
#   Specs: the REL-2 specs (web/e2e/demo-path) at <full sha>
#   Clean host: <OS>, <CPU>, <memory> GiB memory; Node.js absent|present
#   Driver host: <OS>, <CPU>, <memory> GiB memory
#   Run: <UTC start> to <UTC end>
#   Note: ...                                   (a dry run only)
#   | Step | Result | Detail |                  rows hosts, copy, install, sign-in, secrets, demo path runs, then one row per bound id above
#   ### Runs                                    the table of every run's values (a "###" line does not start a section)
# Result: fail when any step or bound failed; otherwise "dry run" in a dry run; otherwise "not run" while any row is not run (fewer runs
# than --runs, or the tell-now row), else pass. Output: PASS/FAIL lines, PHASE lines, RECORD <file> and RESULT <result>.
# Exit codes: 0 only for a real pass; 1 for fail or not run (also a failed start); 3 for a dry run; 2 for a refusal (usage, configuration,
# candidate, real-mode guard or phase order; nothing started); 75 when the lane's throwaway lock is busy (a dry run). Only exit 0 with
# "Result: pass" passes.
# A dry run needs docker compose, the IRIS base image and the mock image of ci/iris.sh, and the lane's variables of docker/tests/lib-live.sh
# (OCUTALON_LOCK_DIR, OCUTALON_LOCK_OWNER, OCUTALON_TEST_WEB_PORT); the model is the CI mock, never a key. The runs phase needs Node.js with
# web/node_modules and the Playwright browser on this machine. Needs bash 3.2 or later and git.
set -u
umask 077

reh_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
reh_caller_pwd=$PWD
cd "$reh_root" || exit 1
. "$reh_root/release/lib-release.sh"
. "$reh_root/docker/tests/lib-keys.sh"

REH_ROWS="hosts copy install sign-in secrets runs notice pick-up settle-end diagnosis delivery median decision first-reply approval-result reminder reminder-result largest-request tell-now"
REH_BOUND_ROWS="notice pick-up settle-end diagnosis delivery median decision first-reply approval-result reminder reminder-result largest-request tell-now"
REH_PLANTABLE="notice pick-up settle-end diagnosis delivery decision approval-result reminder largest-request"
REH_RUNS_REAL=20
REH_DIR=ocutalon-rehearsal
REH_STANDIN_BRANCH=rehearsal/stand-in
report_plant=""
REH_NOTE_DRY="A dry run on throwaway stand-ins for the clean host and the driver host, with the CI mock in place of the model. It is not a rehearsal pass; the real rehearsal is Story 38.2's."

# The probes that host_run runs: key=value lines. They ask for the system, the CPU and the memory, and never for a host name.
IFS= read -r -d '' PROBE_MACHINE <<'EOS' || true
echo "os=$(uname -s)"
echo "arch=$(uname -m)"
if [ -r /etc/os-release ]; then
  echo "name=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -n 1)"
else
  echo "name=$(sw_vers -productVersion 2>/dev/null)"
fi
if [ -r /proc/meminfo ]; then
  echo "mem=$(awk '/^MemTotal:/ { printf "%.0f", $2 * 1024 }' /proc/meminfo)"
else
  echo "mem=$(sysctl -n hw.memsize 2>/dev/null)"
fi
EOS
IFS= read -r -d '' PROBE_CLEAN <<'EOS' || true
echo "git=$(command -v git >/dev/null 2>&1 && echo 1 || echo 0)"
echo "docker=$(docker info --format '{{.ServerVersion}}' >/dev/null 2>&1 && echo 1 || echo 0)"
p=${COMPOSE_PROJECT_NAME:-ocutalon}
echo "containers=$(docker ps -a -q --filter "label=com.docker.compose.project=$p" 2>/dev/null | wc -l | tr -d ' ')"
echo "volumes=$(docker volume ls -q --filter "label=com.docker.compose.project=$p" 2>/dev/null | wc -l | tr -d ' ')"
echo "node=$(command -v node >/dev/null 2>&1 && echo 1 || echo 0)"
EOS
PROBE_CLEAN="$PROBE_CLEAN$PROBE_MACHINE"
IFS= read -r -d '' PROBE_DRIVER <<'EOS' || true
echo "curl=$(command -v curl >/dev/null 2>&1 && echo 1 || echo 0)"
EOS
PROBE_DRIVER="$PROBE_DRIVER$PROBE_MACHINE"

# The collector of the timed run (Story 11.11): read-only ObjectScript, sent through `rehearse.sh exec` after the specs ran. @START@ is the
# run's server start (UTC, milliseconds) and @USER@ the printed user. It runs SELECTs and property reads only and prints CHK| lines:
#   CHK|mark|<name>|<epoch ms>   press, first_failure, pickup, settle_end, diagnosis_end, delivered, reminder_msg, result_msg (server clock:
#                                production message headers in milliseconds; the rows' whole-second times for the two messages)
#   CHK|reminder|<due ms>|<fired ms>   one per fired reminder of the run; CHK|late|<late flags>|<fired reminders>
#   CHK|tokens|<n>               the largest model request's input tokens; CHK|missing|<name>   a source that gave nothing
IFS= read -r -d '' COLLECTOR <<'EOS' || true
Set e="Set t=$ZSTRIP($TRANSLATE(t,""TZ"",""  ""),""<>W""),h=$ZDATETIMEH(t,3,1,,,,,,,""""),r=$SELECT(h="""":"""",1:$FNUMBER(((+$PIECE(h,"","",1)-47117)*86400+$PIECE(h,"","",2))*1000,"""",0))"
Set start="@START@",sz=$PIECE(start,".",1),startZ=$PIECE(sz," ",1)_"T"_$PIECE(sz," ",2)_"Z"
Set ref="",trace=""
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Ref, TraceRef FROM OcuTalon_Data.Session WHERE IrisUser = ? ORDER BY ID","@USER@")
If rs.%Next() Set ref=rs.%Get("Ref"),trace=rs.%Get("TraceRef")
If ref="" Write !,"CHK|missing|session"
Set press=""
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 TimeCreated FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Demo.Msg.SendOrders' AND TimeCreated >= ? ORDER BY ID",start)
If rs.%Next() Set t=rs.%Get("TimeCreated") Xecute e Set press=r
If press="" { Write !,"CHK|missing|press" } Else { Write !,"CHK|mark|press|",press }
Set ns="",fh="",th=""
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Namespace, FirstHeaderId, TraceHeaderId FROM OcuTalon_Data.Incident WHERE OwnerRef = ? AND Namespace = 'OCUORDERS' AND NoticedAt >= ? ORDER BY NoticedAt, ID",ref,startZ)
If rs.%Next() Set ns=rs.%Get("Namespace"),fh=rs.%Get("FirstHeaderId"),th=rs.%Get("TraceHeaderId")
If th="" Write !,"CHK|missing|incident"
Set ffs="",ff=""
If fh'="" Set $NAMESPACE=ns Set hd=##class(Ens.MessageHeader).%OpenId(fh) If $IsObject(hd) Set ffs=hd.TimeProcessed
Set $NAMESPACE="OCUTALON"
If ffs'="" Set t=ffs Xecute e Set ff=r
If ff="" { Write !,"CHK|missing|first_failure" } Else { Write !,"CHK|mark|first_failure|",ff }
Set pk=""
If ffs'="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 TimeCreated FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Watch.Msg.FailureBatch' AND SuperSession = ? AND TimeCreated >= ? ORDER BY ID",trace,ffs) If rs.%Next() Set t=rs.%Get("TimeCreated") Xecute e Set pk=r
If pk="" { Write !,"CHK|missing|pickup" } Else { Write !,"CHK|mark|pickup|",pk }
Set rq="",rqId=""
If th'="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID, TimeCreated FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' AND TargetConfigName = 'Decide' ORDER BY ID",th) If rs.%Next() Set rqId=rs.%Get("ID"),t=rs.%Get("TimeCreated") Xecute e Set rq=r
If rq="" { Write !,"CHK|missing|settle_end" } Else { Write !,"CHK|mark|settle_end|",rq }
Set de=""
If rqId'="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 TimeCreated FROM Ens.MessageHeader WHERE CorrespondingMessageId = ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.DecisionResponse' ORDER BY ID",rqId) If rs.%Next() Set t=rs.%Get("TimeCreated") Xecute e Set de=r
If de="" { Write !,"CHK|missing|diagnosis_end" } Else { Write !,"CHK|mark|diagnosis_end|",de }
Set dl=""
If th'="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 TimeProcessed FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = 'SimPhoneOut' ORDER BY ID",th) If rs.%Next() Set t=rs.%Get("TimeProcessed") If t'="" Xecute e Set dl=r
If dl="" { Write !,"CHK|missing|delivered" } Else { Write !,"CHK|mark|delivered|",dl }
Set late=0,nrem=0,rtext=""
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT DueAt, Late, TraceHeaderId, Text FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State = 'fired' AND CreatedAt >= ? ORDER BY ID",ref,startZ)
While rs.%Next() { Set nrem=nrem+1,late=late+rs.%Get("Late"),rth=rs.%Get("TraceHeaderId"),t=rs.%Get("DueAt") Xecute e Set due=r Set:nrem=1 rtext=rs.%Get("Text") Set fired="" Set r2=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 TimeCreated FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'OcuTalon.Msg.Notification' ORDER BY ID",rth) If r2.%Next() { Set t=r2.%Get("TimeCreated") Xecute e Set fired=r } If fired="" { Write !,"CHK|missing|fired" } Else { Write !,"CHK|reminder|",due,"|",fired } }
If nrem=0 { Write !,"CHK|missing|reminder" } Else { Write !,"CHK|late|",late,"|",nrem }
Set rm="",wt=""
If rtext'="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 CreatedAt FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone' AND CreatedAt >= ? AND Text LIKE ? ORDER BY CreatedAt, ID",ref,startZ,"%"_rtext_"%") If rs.%Next() Set t=rs.%Get("CreatedAt") Xecute e Set rm=r
If rm="" { Write !,"CHK|missing|reminder_msg" } Else { Write !,"CHK|mark|reminder_msg|",rm }
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 CreatedAt FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone' AND CreatedAt >= ? AND Text LIKE '%went through.%' ORDER BY CreatedAt, ID",ref,startZ)
If rs.%Next() Set t=rs.%Get("CreatedAt") Xecute e Set wt=r
If wt="" { Write !,"CHK|missing|result_msg" } Else { Write !,"CHK|mark|result_msg|",wt }
Set tok=""
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(LargestRequestTokens) FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND RecordedAt >= ?",ref,startZ)
If rs.%Next() Set tok=rs.%GetData(1)
If tok="" { Write !,"CHK|missing|tokens" } Else { Write !,"CHK|tokens|",tok }
Write !,"CHK|done|1"
Halt
EOS

# The bounds (Story 11.11), one awk program for bounds_eval and for the RUN line of one run. Its input is runs_feed's lines
# "<run> run", "<run> page <mark> <ms>", "<run> server <kind> ...", "<run> verdict pass" and "<run> verdict fail <step>|<detail>".
# -v mode=eval writes the files bfile (id|step|result|detail), tfile (the ### Runs table) and sfile ("<runs> <passed runs>") and prints the FAIL
# lines; -v mode=run prints the RUN line and the FAIL lines of the missing marks of the one run and exits 1 when a mark is missing. -v passw is
# the result of a met bound (pass, or "dry run" on the mock); -v plant names the one bound whose limit is 0.
IFS= read -r -d '' BOUNDS_AWK <<'EOS' || true
function commas(n,   s, o) {
  s = sprintf("%d", n); o = ""
  while (length(s) > 3) { o = "," substr(s, length(s) - 2) o; s = substr(s, 1, length(s) - 3) }
  return s o
}
function sec(ms) { return sprintf("%.1f s", ms / 1000) }
function shown(id, v) { return (id == "largest-request") ? commas(v) : sec(v) }
function limtext(id,   t) {
  if (id == "largest-request") t = lim[id] " tokens"; else t = (lim[id] / 1000) " s"
  t = id " " t
  if (rule[id] == "19") t = t " in 19 of 20"
  if (id == plant) t = t " (planted)"
  return t
}
function has(k, n, kind) { return (kind == "p") ? ((k SUBSEP n) in pg) : ((k SUBSEP n) in sv) }
function val(k, n, kind) { return (kind == "p") ? pg[k, n] : sv[k, n] }
function joined(cur, add) { return cur (cur == "" ? "" : ",") add }
function medianOf(list, cnt,   i, j, t, a) {
  for (i = 1; i <= cnt; i++) a[i] = list[i]
  for (i = 2; i <= cnt; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
  if (cnt % 2 == 1) return a[(cnt + 1) / 2]
  return (a[cnt / 2] + a[cnt / 2 + 1]) / 2
}
BEGIN {
  N = 0
  lim["notice"] = 60000; lim["pick-up"] = 15000; lim["settle-end"] = 30000; lim["diagnosis"] = 20000; lim["delivery"] = 5000
  lim["decision"] = 10000; lim["approval-result"] = 2000; lim["reminder"] = 10000; lim["largest-request"] = 100000
  if (plant != "") lim[plant] = 0
  nid = split("notice pick-up settle-end diagnosis delivery decision approval-result reminder largest-request", IDS, " ")
  stepof["notice"] = "incident"; stepof["pick-up"] = "incident"; stepof["settle-end"] = "incident"; stepof["diagnosis"] = "incident"; stepof["delivery"] = "incident"
  stepof["decision"] = "watch"; stepof["approval-result"] = "approval"; stepof["reminder"] = "reminder"; stepof["largest-request"] = "run"
  rule["notice"] = "19"; rule["decision"] = "19"; rule["approval-result"] = "19"
  what["notice"] = "from Break the feed to the notice on the phone"
  what["pick-up"] = "from the first failure to the pick-up"
  what["settle-end"] = "from the first failure to the diagnosis request"
  what["diagnosis"] = "from the diagnosis request to its answer"
  what["delivery"] = "from the answer to the notice's delivery"
  what["decision"] = "from the guide's Send to the decision on the page"
  what["approval-result"] = "from the Approve press to the result on the page"
  what["reminder"] = "after its due time"
  what["largest-request"] = "input tokens in the largest request"
  nsteps = split("incident watch reminder approval run", STEPS, " ")
  nmark["incident"] = split("press first_failure pickup settle_end diagnosis_end delivered", M_incident, " ")
  nmark["watch"] = split("step1_sent step1_decision_seen step1_reply_seen", M_watch, " ")
  nmark["approval"] = split("approve_pressed approval_result_seen", M_approval, " ")
}
$2 == "run" { RUN[++N] = $1; next }
$2 == "page" { if (!(($1 SUBSEP $3) in pg)) pg[$1, $3] = $4 + 0; next }
$2 == "verdict" {
  vd[$1] = $3
  rest = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ ?/, "", rest)
  p = index(rest, "|")
  if (p > 0) { vstep[$1] = substr(rest, 1, p - 1); vdet[$1] = substr(rest, p + 1) } else { vstep[$1] = "run"; vdet[$1] = rest }
  next
}
$2 == "server" {
  k = $1; kind = $3
  if (kind == "mark") { if (!((k SUBSEP $4) in sv)) sv[k, $4] = $5 + 0 }
  else if (kind == "reminder") { j = ++nrem[k]; rdue[k, j] = $4 + 0; rfir[k, j] = $5 + 0 }
  else if (kind == "late") { lateN[k] = $4 + 0 }
  else if (kind == "tokens") { tok[k] = $4 + 0; havetok[k] = 1 }
  else if (kind == "missing") { srvmiss[k, $4] = 1 }
  next
}
END {
  nfail = 0; npassed = 0
  for (i = 1; i <= N; i++) {
    k = RUN[i]
    # the missing marks of the run, by step
    for (s = 1; s <= nsteps; s++) miss[k, STEPS[s]] = ""
    for (m = 1; m <= nmark["incident"]; m++) if (!has(k, M_incident[m], "s")) miss[k, "incident"] = joined(miss[k, "incident"], M_incident[m])
    for (m = 1; m <= nmark["watch"]; m++) if (!has(k, M_watch[m], "p")) miss[k, "watch"] = joined(miss[k, "watch"], M_watch[m])
    for (m = 1; m <= nmark["approval"]; m++) if (!has(k, M_approval[m], "p")) miss[k, "approval"] = joined(miss[k, "approval"], M_approval[m])
    if (nrem[k] == 0) miss[k, "reminder"] = joined(miss[k, "reminder"], "reminder")
    else if (srvmiss[k, "fired"]) miss[k, "reminder"] = joined(miss[k, "reminder"], "fired")
    if (!has(k, "reminder_msg", "s")) miss[k, "reminder"] = joined(miss[k, "reminder"], "reminder_msg")
    if (!has(k, "result_msg", "s")) miss[k, "reminder"] = joined(miss[k, "reminder"], "result_msg")
    if (!havetok[k]) miss[k, "run"] = joined(miss[k, "run"], "tokens")
    if (srvmiss[k, "session"]) miss[k, "run"] = joined(miss[k, "run"], "session")
    if (srvmiss[k, "collector"]) miss[k, "run"] = joined(miss[k, "run"], "collector")
    # the values (ms; tokens for largest-request) and whether each could be measured
    ok["notice", k] = has(k, "press", "s") && has(k, "delivered", "s"); if (ok["notice", k]) V["notice", k] = sv[k, "delivered"] - sv[k, "press"]
    ok["pick-up", k] = has(k, "first_failure", "s") && has(k, "pickup", "s"); if (ok["pick-up", k]) V["pick-up", k] = sv[k, "pickup"] - sv[k, "first_failure"]
    ok["settle-end", k] = has(k, "first_failure", "s") && has(k, "settle_end", "s"); if (ok["settle-end", k]) V["settle-end", k] = sv[k, "settle_end"] - sv[k, "first_failure"]
    ok["diagnosis", k] = has(k, "settle_end", "s") && has(k, "diagnosis_end", "s"); if (ok["diagnosis", k]) V["diagnosis", k] = sv[k, "diagnosis_end"] - sv[k, "settle_end"]
    ok["delivery", k] = has(k, "diagnosis_end", "s") && has(k, "delivered", "s"); if (ok["delivery", k]) V["delivery", k] = sv[k, "delivered"] - sv[k, "diagnosis_end"]
    ok["decision", k] = has(k, "step1_sent", "p") && has(k, "step1_decision_seen", "p"); if (ok["decision", k]) V["decision", k] = pg[k, "step1_decision_seen"] - pg[k, "step1_sent"]
    ok["first-reply", k] = has(k, "step1_sent", "p") && has(k, "step1_reply_seen", "p"); if (ok["first-reply", k]) V["first-reply", k] = pg[k, "step1_reply_seen"] - pg[k, "step1_sent"]
    ok["approval-result", k] = has(k, "approve_pressed", "p") && has(k, "approval_result_seen", "p"); if (ok["approval-result", k]) V["approval-result", k] = pg[k, "approval_result_seen"] - pg[k, "approve_pressed"]
    ok["reminder", k] = (nrem[k] > 0 && !srvmiss[k, "fired"])
    if (ok["reminder", k]) { mx = -1e18; for (j = 1; j <= nrem[k]; j++) { d = rfir[k, j] - rdue[k, j]; if (d > mx) mx = d } V["reminder", k] = mx }
    ok["reminder-result", k] = has(k, "reminder_msg", "s") && has(k, "result_msg", "s"); if (ok["reminder-result", k]) V["reminder-result", k] = (sv[k, "reminder_msg"] - sv[k, "result_msg"])
    ok["largest-request", k] = havetok[k] ? 1 : 0; if (ok["largest-request", k]) V["largest-request", k] = tok[k]
    anymiss = 0
    for (s = 1; s <= nsteps; s++) if (miss[k, STEPS[s]] != "") anymiss = 1
    rpass[k] = (vd[k] == "pass" && !anymiss) ? 1 : 0
    if (rpass[k]) npassed++
  }

  if (mode == "run") {
    k = RUN[1]
    line = "RUN " k
    for (a = 1; a <= nid + 2; a++) {
      id = (a <= nid) ? IDS[a] : ((a == nid + 1) ? "first-reply" : "reminder-result")
      text = "-"
      if (ok[id, k]) text = (id == "largest-request") ? sprintf("%d", V[id, k]) : sprintf("%.1f", V[id, k] / 1000)
      line = line " " id "=" text
    }
    print line
    bad = 0
    for (s = 1; s <= nsteps; s++) if (miss[k, STEPS[s]] != "") { bad = 1; printf "FAIL run %s step %s bound -: missing mark(s) %s (%s)\n", k, STEPS[s], miss[k, STEPS[s]], (STEPS[s] == "watch" || STEPS[s] == "approval") ? "left by the page" : "read from the server's records" }
    exit bad
  }

  # the FAIL lines of failed verdicts and of missing marks, by run, in step order
  for (i = 1; i <= N; i++) {
    k = RUN[i]
    if (vd[k] != "pass") printf "FAIL run %s step %s bound -: %s\n", k, (vstep[k] == "" ? "run" : vstep[k]), (vdet[k] == "" ? "the run left no verdict" : vdet[k])
    for (s = 1; s <= nsteps; s++) if (miss[k, STEPS[s]] != "") printf "FAIL run %s step %s bound -: missing mark(s) %s (%s)\n", k, STEPS[s], miss[k, STEPS[s]], (STEPS[s] == "watch" || STEPS[s] == "approval") ? "left by the page" : "read from the server's records"
  }

  # the limited bounds
  for (b = 1; b <= nid; b++) {
    id = IDS[b]
    nmeas = 0; nover = 0; longest = -1e18; lrun = ""; ovl = ""; ovd = ""; unm = ""
    for (i = 1; i <= N; i++) {
      k = RUN[i]
      if (!ok[id, k]) { unm = joined(unm, k); continue }
      nmeas++
      v = V[id, k]
      over = (id == "largest-request") ? (v >= lim[id]) : (v > lim[id])
      if (id == "reminder" && lateN[k] > 0) over = 1
      if (v > longest) { longest = v; lrun = k }
      if (over) { nover++; ovl = joined(ovl, k); ovd = ovd (ovd == "" ? "" : ", ") shown(id, v) " in run " k }
    }
    allowed = (rule[id] == "19") ? int(N / 20) : 0
    status = ""
    detail = ""
    if (N == 0) { print id "|" stepof[id] "|not run|" > bfile; continue }
    if (unm != "") {
      status = "fail"; detail = "no measurement in run " unm " (a mark is missing)"
      if (nover > allowed) detail = detail "; over its limit in run " ovl
    } else if (nover > allowed) {
      status = "fail"
      detail = ovd " " what[id] " (limit " limtext(id) ")"
      printf "FAIL run %s step %s bound %s: %s %s\n", ovl, stepof[id], limtext(id), ovd, what[id]
    } else {
      status = passw
      okc = nmeas - nover
      if (id == "notice" || id == "decision") detail = "within " (lim[id] / 1000) " s in " okc " of " nmeas " runs (19 of 20 needed); longest " sec(longest) " (run " lrun ")"
      else if (id == "approval-result") detail = "within " (lim[id] / 1000) " s of the Approve press in " okc " of " nmeas " runs (19 of 20 needed); longest " sec(longest) " (run " lrun ")"
      else if (id == "pick-up" || id == "settle-end") detail = "within " (lim[id] / 1000) " s of the first failure in every run; longest " sec(longest) " (run " lrun ")"
      else if (id == "diagnosis" || id == "delivery") detail = "within " (lim[id] / 1000) " s in every run; longest " sec(longest) " (run " lrun ")"
      else if (id == "reminder") detail = "every reminder within " (lim[id] / 1000) " s of its due time; latest " sec(longest) " (run " lrun ")"
      else detail = "under " commas(lim[id]) " input tokens in every run; largest " commas(longest) " (run " lrun ")"
      if (nover > 0) detail = detail "; " nover " run(s) over, within the allowance"
      if (id == plant) detail = detail " (planted)"
    }
    print id "|" stepof[id] "|" status "|" detail > bfile
  }

  # the recorded bounds
  cnt = 0; unm = ""
  for (i = 1; i <= N; i++) { k = RUN[i]; if (ok["notice", k]) { cnt++; nl[cnt] = V["notice", k] } else unm = joined(unm, k) }
  if (N == 0) print "median|incident|not run|" > bfile
  else if (cnt == 0) print "median|incident|not run|no notice was measured" > bfile
  else print "median|incident|recorded|median notice " sec(medianOf(nl, cnt)) " against the typical 35 s" > bfile
  cnt = 0; unm = ""; longest = -1e18; lrun = ""
  for (i = 1; i <= N; i++) { k = RUN[i]; if (ok["first-reply", k]) { cnt++; fl[cnt] = V["first-reply", k]; if (V["first-reply", k] > longest) { longest = V["first-reply", k]; lrun = k } } else unm = joined(unm, k) }
  if (N == 0) print "first-reply|watch|not run|" > bfile
  else if (unm != "") print "first-reply|watch|fail|no measurement in run " unm " (a mark is missing)" > bfile
  else print "first-reply|watch|recorded|median " sec(medianOf(fl, cnt)) ", longest " sec(longest) " (run " lrun ")" > bfile
  cnt = 0; unm = ""; text = ""
  for (i = 1; i <= N; i++) {
    k = RUN[i]
    if (!ok["reminder-result", k]) { unm = joined(unm, k); continue }
    cnt++; rr[cnt] = V["reminder-result", k]
    d = rr[cnt]
    if (d < 0) w = sprintf("%.1f s before", -d / 1000); else if (d > 0) w = sprintf("%.1f s after", d / 1000); else w = "in the same second as"
    text = text (text == "" ? "" : "; ") "run " k ": the reminder landed " w " the result message"
  }
  if (N == 0) print "reminder-result|reminder|not run|" > bfile
  else if (unm != "") print "reminder-result|reminder|fail|no measurement in run " unm " (a mark is missing)" > bfile
  else if (N == 1) print "reminder-result|reminder|recorded|" text > bfile
  else {
    mn = rr[1]; mxv = rr[1]
    for (i = 2; i <= cnt; i++) { if (rr[i] < mn) mn = rr[i]; if (rr[i] > mxv) mxv = rr[i] }
    print "reminder-result|reminder|recorded|reminder minus result (negative: the reminder landed first): median " sec(medianOf(rr, cnt)) ", from " sec(mn) " to " sec(mxv) " over " cnt " runs" > bfile
  }
  print "tell-now|tell-now|not run|the demo path has no tell-now item yet; Story 11.12 adds one to each run" > bfile

  # the table and the counts
  print "### Runs" > tfile
  print "" > tfile
  print "| Run | Result | Notice | Pick-up | Settle end | Diagnosis | Delivery | Decision | First reply | Approval result | Reminder | Reminder to result | Largest request |" > tfile
  print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |" > tfile
  for (i = 1; i <= N; i++) {
    k = RUN[i]
    row = "| " k " | " (rpass[k] ? "pass" : "fail") " |"
    ncol = split("notice pick-up settle-end diagnosis delivery decision first-reply approval-result reminder reminder-result largest-request", COLS, " ")
    for (c = 1; c <= ncol; c++) {
      id = COLS[c]
      if (!ok[id, k]) { row = row " - |"; continue }
      v = V[id, k]
      cell = (id == "largest-request") ? commas(v) : sec(v)
      if (id in lim) {
        over = (id == "largest-request") ? (v >= lim[id]) : (v > lim[id])
        if (id == "reminder" && lateN[k] > 0) over = 1
        if (over) cell = cell "*"
      }
      row = row " " cell " |"
    }
    print row > tfile
  }
  print "" > tfile
  print "* over the bound's limit; the bound's rule says how many runs may miss it." > tfile
  print N " " npassed > sfile
}
EOS

# --- pure functions: each takes its inputs as arguments ---

# probe_get <key> <probe text>: the value of a key=value line.
probe_get() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n 1 | tr -d '\r'; }

# machine_line <probe text>: the operating system, the CPU architecture and the memory, and nothing else (CON-5).
machine_line() {
  local text=$1 os arch name mem label memtext
  os=$(probe_get os "$text")
  arch=$(probe_get arch "$text")
  name=$(probe_get name "$text" | tr -d '\r\n' | LC_ALL=C tr -c '\040-\176' '?' | tr '|' '/')
  mem=$(probe_get mem "$text")
  case $os in
    Darwin) label="macOS${name:+ $name}" ;;
    Linux) label="Linux (${name:-unknown distribution})" ;;
    *) label=$(printf '%s' "${os:-unknown system}" | tr -d '\r\n' | LC_ALL=C tr -c '\040-\176' '?' | tr '|' '/') ;;
  esac
  case $mem in
    '' | *[!0-9]*) memtext="unknown memory" ;;
    *) memtext=$(awk -v b="$mem" 'BEGIN { printf "%.1f GiB memory", b / 1073741824 }') ;;
  esac
  arch=$(printf '%s' "${arch:-unknown CPU}" | tr -d '\r\n' | LC_ALL=C tr -c '\040-\176' '?' | tr '|' '/')
  printf '%s, %s, %s\n' "$label" "$arch" "$memtext"
}

# hosts_verdict <real|dry> <clean probe text> <driver probe text>: prints the reason and returns 1 for the first failure.
hosts_verdict() {
  local mode=$1 clean=$2 driver=$3 c v
  if [ -z "$(probe_get git "$clean")" ] || [ -z "$(probe_get os "$clean")" ]; then
    echo "the clean host's reply was not understood"
    return 1
  fi
  if [ "$(probe_get git "$clean")" != 1 ]; then
    echo "git is not installed on the clean host"
    return 1
  fi
  if [ "$(probe_get docker "$clean")" != 1 ]; then
    echo "Docker is not installed, or not running for this user, on the clean host"
    return 1
  fi
  c=$(probe_get containers "$clean")
  v=$(probe_get volumes "$clean")
  case $c in
    '' | *[!0-9]*)
      echo "the clean host's containers and volumes could not be counted"
      return 1
      ;;
  esac
  case $v in
    '' | *[!0-9]*)
      echo "the clean host's containers and volumes could not be counted"
      return 1
      ;;
  esac
  if [ "$c" -gt 0 ] || [ "$v" -gt 0 ]; then
    echo "an OcuTalon container or volume exists on the clean host ($c container(s), $v volume(s)); a clean host has none"
    return 1
  fi
  if [ "$mode" = real ] && [ "$(probe_get node "$clean")" = 1 ]; then
    echo "Node.js is installed on the clean host; a clean host has none"
    return 1
  fi
  if [ -z "$(probe_get os "$driver")" ]; then
    echo "the driver host's reply was not understood"
    return 1
  fi
  if [ "$(probe_get curl "$driver")" != 1 ]; then
    echo "curl is not installed on the driver host"
    return 1
  fi
  return 0
}

# parse_install <file>: install.sh's output. Sets PI_URL, PI_USER, PI_PASSWORD, PI_PORT and PI_READY ("OcuTalon is ready after ...").
# Returns 1, with PI_MISSING naming the lines that are absent (Open:, User:, Password:), when one is missing.
parse_install() {
  PI_URL=$(sed -n 's/^  Open: *//p' "$1" | head -n 1 | tr -d '\r')
  PI_USER=$(sed -n 's/^  User: *//p' "$1" | head -n 1 | tr -d '\r')
  PI_PASSWORD=$(sed -n 's/^  Password: *//p' "$1" | head -n 1 | tr -d '\r')
  PI_READY=$(sed -n 's/^\(OcuTalon is ready after .*\)$/\1/p' "$1" | head -n 1 | tr -d '\r')
  PI_PORT=${PI_URL#http://localhost:}
  PI_PORT=${PI_PORT%%/*}
  PI_MISSING=""
  [ -n "$PI_URL" ] || PI_MISSING="$PI_MISSING Open:"
  [ -n "$PI_USER" ] || PI_MISSING="$PI_MISSING User:"
  [ -n "$PI_PASSWORD" ] || PI_MISSING="$PI_MISSING Password:"
  PI_MISSING=${PI_MISSING# }
  if [ -n "$PI_URL" ]; then
    case $PI_PORT in
      '' | *[!0-9]*)
        PI_PORT=""
        PI_MISSING="$PI_MISSING${PI_MISSING:+ }Open: (with a port)"
        ;;
    esac
  fi
  [ -z "$PI_MISSING" ]
}

# curl_quote <text>: a curl config string value.
curl_quote() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# signin_config <url> <user> <password>: the curl config (curl -K -) of the sign-in: the page for its cookie, the sign-in form, and the page again.
signin_config() {
  local url user pass jar="$REH_DIR/cookies.jar"
  url=$(curl_quote "$1")
  user=$(curl_quote "$2")
  pass=$(curl_quote "$3")
  cat <<EOC
silent
max-time = 30
url = "$url"
output = "/dev/null"
cookie-jar = "$jar"
cookie = "$jar"
next
silent
max-time = 30
url = "$url"
output = "/dev/null"
cookie-jar = "$jar"
cookie = "$jar"
data-urlencode = "IRISUsername=$user"
data-urlencode = "IRISPassword=$pass"
data-urlencode = "IRISLogin=Sign in"
next
silent
max-time = 30
url = "$url"
cookie = "$jar"
EOC
}

# row_title <row id>
row_title() { if [ "$1" = runs ]; then echo "demo path runs"; else echo "$1"; fi; }

# row_result <results file> <row id>: pass, fail or not run.
row_result() {
  awk -F'|' -v s="$2" '$1 == s { r = $2 } END { print (r == "" ? "not run" : r) }' "$1" 2> /dev/null || echo "not run"
}

# rehearsal_result <real|dry> <results file>: fail when any row failed; otherwise dry run in a dry run; otherwise not run while any row is
# not run (fewer runs than --runs, the tell-now row), else pass. A recorded row counts as met.
rehearsal_result() {
  local mode=$1 results=$2 row r anyfail=0 anynot=0
  for row in $REH_ROWS; do
    r=$(row_result "$results" "$row")
    case $r in
      fail) anyfail=1 ;;
      pass | recorded) ;;
      *) anynot=1 ;;
    esac
  done
  if [ "$anyfail" = 1 ]; then
    echo fail
  elif [ "$mode" = dry ]; then
    echo "dry run"
  elif [ "$anynot" = 1 ]; then
    echo "not run"
  else
    echo pass
  fi
}

# rehearsal_exit <result>: the exit code of a result.
rehearsal_exit() {
  case $1 in
    pass) echo 0 ;;
    "dry run") echo 3 ;;
    *) echo 1 ;;
  esac
}

# fail_line <step> <bound> <detail>: the one line of a failed install step.
fail_line() { printf 'FAIL run install step %s bound %s: %s\n' "$1" "$2" "$3"; }
# fail_run_line <run> <step> <bound> <detail>: the one line of a failed run or bound.
fail_run_line() { printf 'FAIL run %s step %s bound %s: %s\n' "$1" "$2" "$3" "$4"; }

tag_ok() {
  case $1 in
    '' | *[!a-z0-9-]* | *slot*) return 1 ;;
  esac
  [ "${#1}" -ge 3 ]
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- the state ---

state_dir() {
  local t=${TMPDIR:-/tmp}
  printf '%s/ocutalon-rehearsal-%s\n' "${t%/}" "$1"
}

opt() { env_get "$state/options" "$1"; }
phase_done() { [ "$(cut -d' ' -f1 "$state/phase.$1" 2> /dev/null)" = done ]; }
phase_mark() { printf '%s %s\n' "$2" "$3" > "$state/phase.$1"; }

# reh_logged <command>...: runs the command with its output appended to the state's output.log.
reh_logged() {
  "$@" 2>&1 | tee -a "$state/output.log"
  return "${PIPESTATUS[0]}"
}

# step_record <step> <pass|fail> <detail>: the step's row (a step run again replaces its row).
step_record() {
  if [ -f "$state/results" ]; then
    grep -v "^$1|" "$state/results" > "$state/results.new"
    mv "$state/results.new" "$state/results"
  fi
  printf '%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | detail_clean)" >> "$state/results"
}
step_pass() {
  echo "PASS $1 $2"
  step_record "$1" pass "$2"
}
step_fail() { # step_fail <step> <bound> <detail>
  fail_line "$1" "$2" "$3"
  step_record "$1" fail "$3"
}

# --- options and the candidate ---

refuse() { echo "REFUSED $*"; }

parse_options() {
  o_version=""
  o_rc=""
  o_candidate=""
  o_record=""
  o_runs=""
  o_plant=""
  o_dry=0
  while [ $# -gt 0 ]; do
    case $1 in
      --version | --rc | --candidate | --record | --runs | --plant)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          refuse "$1 needs a value"
          return 2
        fi
        case $1 in
          --version) o_version=$2 ;;
          --rc) o_rc=$2 ;;
          --candidate) o_candidate=$2 ;;
          --record) o_record=$2 ;;
          --runs) o_runs=$2 ;;
          --plant) o_plant=$2 ;;
        esac
        shift 2
        ;;
      --dry-run)
        o_dry=1
        shift
        ;;
      *)
        refuse "unknown option '$1'"
        return 2
        ;;
    esac
  done
  case $o_record in
    '' | /*) ;;
    *) o_record=$reh_caller_pwd/$o_record ;;
  esac
  case $o_rc in
    '' | 0* | *[!0-9]* | ???????*)
      refuse "--rc must be a positive whole number"
      return 2
      ;;
  esac
  if [ -n "$o_runs" ]; then
    case $o_runs in
      '' | 0* | *[!0-9]* | ????*)
        refuse "--runs must be a positive whole number"
        return 2
        ;;
    esac
  fi
  if [ "$o_dry" = 1 ]; then
    if [ -z "$o_runs" ]; then o_runs=1; fi
    if [ "$o_runs" -gt 20 ]; then
      refuse "--runs must be 1 to 20 in a dry run"
      return 2
    fi
  else
    if [ -z "$o_runs" ]; then o_runs=$REH_RUNS_REAL; fi
    if [ "$o_runs" -lt "$REH_RUNS_REAL" ]; then
      refuse "--runs $o_runs is below $REH_RUNS_REAL; a real rehearsal needs at least $REH_RUNS_REAL runs"
      return 2
    fi
  fi
  if [ -n "$o_plant" ] && ! plant_ok "$o_plant"; then
    refuse "--plant '$o_plant' is not a bound id with a limit ($REH_PLANTABLE)"
    return 2
  fi
  if [ -n "$o_version" ] && ! printf '%s\n' "$o_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.-]+)?$'; then
    refuse "--version '$o_version' is not a version number"
    return 2
  fi
  return 0
}

# plant_ok <id>: 0 when the id is a bound with a limit.
plant_ok() {
  local i
  for i in $REH_PLANTABLE; do
    if [ "$i" = "$1" ]; then return 0; fi
  done
  return 1
}

# resolve_candidate: sets c_ref, c_sha, c_version and c_branch from the options; prints a REFUSED line and returns 2 when it cannot.
resolve_candidate() {
  c_ref=$o_candidate
  if [ -z "$c_ref" ]; then
    if [ "$o_dry" = 1 ]; then
      c_ref=HEAD
    elif [ -n "$o_version" ]; then
      c_ref=release/$o_version-rc$o_rc
    else
      refuse "--version <v> is required unless --dry-run or --candidate is given"
      return 2
    fi
  fi
  if ! c_sha=$(git rev-parse --verify --quiet "$c_ref^{commit}"); then
    refuse "the candidate '$c_ref' is not a commit of this repository"
    return 2
  fi
  c_version=$(git show "$c_sha:src/module.xml" 2> /dev/null | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)
  if [ -z "$c_version" ]; then
    refuse "the candidate '$c_ref' has no <Version> in src/module.xml"
    return 2
  fi
  if [ -n "$o_version" ] && [ "$o_version" != "$c_version" ]; then
    refuse "--version $o_version is not the candidate's version ($c_version in src/module.xml)"
    return 2
  fi
  c_branch=$REH_STANDIN_BRANCH
  if [ "$o_dry" != 1 ]; then
    if ! git cat-file -e "$c_sha:src/ocutalon/csp/index.html" 2> /dev/null; then
      refuse "the candidate '$c_ref' holds no src/ocutalon/csp/index.html; Story 11.5 commits the web bundle on the candidate branch"
      return 2
    fi
    if ! git show-ref --verify --quiet "refs/heads/$c_ref"; then
      refuse "the candidate '$c_ref' is not a local branch; a real rehearsal copies a branch"
      return 2
    fi
    if ! printf '%s\n' "$c_ref" | grep -Eq '^[A-Za-z0-9._/-]+$'; then
      refuse "the candidate branch name holds a character that a remote command cannot carry"
      return 2
    fi
    c_branch=$c_ref
  fi
  return 0
}

# options_write: the resolved plan as key=value lines.
options_write() {
  : > "$state/options"
  env_set "$state/options" version "$c_version"
  env_set "$state/options" rc "$o_rc"
  env_set "$state/options" mode "$([ "$o_dry" = 1 ] && echo dry || echo real)"
  env_set "$state/options" ref "$c_ref"
  env_set "$state/options" base_sha "$c_sha"
  env_set "$state/options" cand_sha "$c_sha"
  env_set "$state/options" branch "$c_branch"
  env_set "$state/options" runs "$o_runs"
  env_set "$state/options" record "${o_record:-$(record_path "$c_version" "$o_rc")}"
  env_set "$state/options" tag "${OCUTALON_RUN_TAG:-none}"
  env_set "$state/options" started "$(now_utc)"
}

need_tag() { # need_tag <phase>: sets state
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
    refuse "$1: it needs OCUTALON_RUN_TAG, the tag of the run"
    return 2
  fi
  if ! tag_ok "$OCUTALON_RUN_TAG"; then
    refuse "OCUTALON_RUN_TAG '$OCUTALON_RUN_TAG' must match [a-z0-9-]+, be at least 3 characters and not hold 'slot'"
    return 2
  fi
  export OCUTALON_RUN_TAG
  state=$(state_dir "$OCUTALON_RUN_TAG")
}

# real_config: reads the configuration of a real run into REHEARSAL_* (return 2 with a REFUSED line when it is unusable).
real_config() {
  release_config_read "$(release_config_path)" || return $?
  real_guards
}

# real_guards: the guards of a real rehearsal (Story 11.11), after the configuration is read and the candidate resolved: the driver is this
# machine (the specs drive the browser here), and the spec tree is the candidate's (HEAD or the working tree must not differ from it).
real_guards() {
  local paths="web/e2e web/playwright.config.ts web/package.json web/package-lock.json" extra
  if [ "${REHEARSAL_DRIVER_SSH:-}" != local ]; then
    refuse "REHEARSAL_DRIVER_SSH must be local: the timed runs drive the browser on this machine"
    return 2
  fi
  if [ -n "${c_sha:-}" ]; then
    # shellcheck disable=SC2086
    extra=$(git ls-files --others --exclude-standard -- $paths 2> /dev/null | head -n 1)
    # shellcheck disable=SC2086
    if ! git diff --quiet "$c_sha" -- $paths 2> /dev/null || [ -n "$extra" ]; then
      refuse "the spec tree ($paths) differs from the candidate commit; the record's Specs line must be the candidate's"
      return 2
    fi
  fi
  return 0
}

# --- the dry run's stand-ins ---

rand_hex() { od -An -N12 -tx1 /dev/urandom | tr -d ' \n'; }

# dry_names_remove <name>...: removes the image names of this run (never with -f, so that an id with other names stays).
dry_names_remove() {
  local n
  for n in "$@"; do
    [ -n "$n" ] || continue
    docker image rm "$n" > /dev/null 2>&1
  done
}

# reh_abort: an install that ended before it saved its state leaves no state.
reh_abort() {
  if [ -n "${state:-}" ] && ! phase_done install; then
    dry_names_remove "${test_base:-}" "${src_ref:-}"
    rm -rf "$state"
  fi
}

# standin_files <tmp> <root> <clone> <compose dir> <file>...: the stand-in's COMPOSE_FILE: a file of lib-live's temporary folder becomes
# the copy in <compose dir>, a file of the worktree becomes the clone's file of the same path, and any other file stays.
standin_files() {
  local t=$1 r=$2 c=$3 d=$4 f cf=""
  shift 4
  for f in "$@"; do
    case $f in
      "$t"/*) f=$d/${f#"$t"/} ;;
      "$r"/*) f=$c/${f#"$r"/} ;;
    esac
    cf="$cf${cf:+:}$f"
  done
  printf '%s\n' "$cf"
}

# dry_prepare: the throwaway project of lib-live (no key, the CI override and the mock, the lane's lock), the image names of
# test-install-script-live.sh, the stand-in candidate and the stand-in env file.
dry_prepare() {
  local src f clone images_tag
  . "$reh_root/ci/iris.sh"
  setup_tag
  preflight
  live_start rehearse
  trap 'live_cleanup; reh_abort' EXIT
  live_web_port || exit 1
  mkdir -p "$state/standin/clean" "$state/standin/driver" "$state/standin/compose"
  images_tag=${base_image##*:}
  test_base="$P-base:$images_tag"
  src_ref="$P-src/irishealth-community:$images_tag"
  if ! docker tag "$base_image" "$src_ref"; then
    echo "FAIL could not tag $src_ref"
    exit 1
  fi
  # The stand-in candidate: the ref's commit, the worktree's built web bundle force-added, one local commit on the stand-in branch.
  src=$state/standin/src
  if ! git clone -q --no-checkout "$reh_root" "$src" > /dev/null 2>&1 || ! git -C "$src" checkout -q -b "$REH_STANDIN_BRANCH" "$c_sha" 2> /dev/null; then
    echo "FAIL the stand-in candidate could not be cloned from $c_ref"
    exit 1
  fi
  rm -rf "$src/src/ocutalon/csp"
  mkdir -p "$src/src/ocutalon"
  cp -R "$reh_root/src/ocutalon/csp" "$src/src/ocutalon/csp"
  git -C "$src" add -f src/ocutalon/csp > /dev/null 2>&1
  git -C "$src" -c user.name=OcuTalon -c user.email=rehearsal@invalid -c commit.gpgsign=false \
    commit -q --allow-empty -m "Stand-in of $c_sha with the built web bundle (dry run)" > /dev/null
  env_set "$state/options" branch "$REH_STANDIN_BRANCH"
  env_set "$state/options" cand_sha "$(git -C "$src" rev-parse HEAD)"
  git -C "$src" bundle create -q "$state/candidate.bundle" "$REH_STANDIN_BRANCH" > /dev/null 2>&1 || {
    echo "FAIL the stand-in candidate could not be bundled"
    exit 1
  }
  rm -rf "$src"
  # The stand-in env file: canaries, so that the self-scan has values to look for.
  (
    umask 077
    printf 'ANTHROPIC_API_KEY=dry-run-canary-%s\nOCUTALON_REHEARSAL_CANARY=%s\n' "$(rand_hex)" "$(rand_hex)" > "$state/standin/env"
  )
  # The compose files of the throwaway, as the clone holds them; the files of the temporary folder move into the state.
  clone=$state/standin/clean/$REH_DIR/candidate
  for f in decoy.env decoy.yml port.yml; do cp "$tmp/$f" "$state/standin/compose/$f"; done
  printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$state/standin/compose/decoy.env" > "$state/standin/compose/decoy.yml"
  left=$((deadline - SECONDS))
  if [ "$left" -gt 900 ]; then left=900; fi
  if [ "$left" -lt 10 ]; then left=10; fi
  REHEARSAL_STANDIN=$state/standin
  STANDIN_PROJECT=$P
  STANDIN_FILES=$(standin_files "$tmp" "$root" "$clone" "$state/standin/compose" "${LIVE_FILES[@]}")
  STANDIN_IMAGE=$test_base
  STANDIN_WAIT=$left
}

# dry_save: keeps the throwaway for report and down: the project, the lock, the image names and ids, and drops lib-live's cleanup.
dry_save() {
  live_track_image
  printf '%s\n' "$P" > "$state/standin/project"
  printf '%s\n' "$STANDIN_FILES" > "$state/standin/files"
  printf '%s\n' "$STANDIN_IMAGE" > "$state/standin/image"
  printf '%s\n' "$STANDIN_WAIT" > "$state/standin/wait"
  printf '%s\n' "${LIVE_LOCK_FILE:-}" > "$state/standin/lock.file"
  printf '%s\n' "${LIVE_LOCK_CONTENT:-}" > "$state/standin/lock.content"
  {
    printf '%s\n' "$test_base" "$src_ref"
    if [ "${#LIVE_IMAGES[@]}" -gt 0 ]; then printf '%s\n' "${LIVE_IMAGES[@]}"; fi
  } > "$state/standin/images"
  trap - EXIT INT TERM HUP
  rm -rf "$tmp"
}

# standin_load: the dry run's stand-in for a later process (runs, exec): what dry_save kept.
standin_load() {
  REHEARSAL_STANDIN=$state/standin
  STANDIN_PROJECT=$(cat "$state/standin/project" 2> /dev/null)
  STANDIN_FILES=$(cat "$state/standin/files" 2> /dev/null)
  STANDIN_IMAGE=$(cat "$state/standin/image" 2> /dev/null)
  STANDIN_WAIT=$(cat "$state/standin/wait" 2> /dev/null)
}

# --- the steps of install ---

step_hosts() {
  local clean driver rc verdict mode
  mode=$(opt mode)
  clean=$(host_run clean "$PROBE_CLEAN" < /dev/null 2> /dev/null)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$clean" ]; then
    step_fail hosts - "the clean host did not answer (exit $rc); run the ssh command by hand to see why"
    return 1
  fi
  driver=$(host_run driver "$PROBE_DRIVER" < /dev/null 2> /dev/null)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$driver" ]; then
    step_fail hosts - "the driver host did not answer (exit $rc); run the ssh command by hand to see why"
    return 1
  fi
  printf '%s; Node.js %s\n' "$(machine_line "$clean")" "$([ "$(probe_get node "$clean")" = 1 ] && echo present || echo absent)" > "$state/machine.clean"
  machine_line "$driver" > "$state/machine.driver"
  if ! verdict=$(hosts_verdict "$mode" "$clean" "$driver"); then
    step_fail hosts - "$verdict"
    return 1
  fi
  step_pass hosts "both hosts answered; git and Docker on the clean host, no OcuTalon container or volume"
}

env_file_path() { if [ "$(opt mode)" = dry ]; then echo "$state/standin/env"; else echo "$REHEARSAL_ENV_FILE"; fi; }

step_copy() {
  local branch sha out rc got size
  branch=$(opt branch)
  sha=$(opt cand_sha)
  if [ ! -f "$state/candidate.bundle" ]; then
    if ! git bundle create -q "$state/candidate.bundle" "$branch" > /dev/null 2>&1; then
      step_fail copy - "git bundle of the candidate branch failed"
      return 1
    fi
  fi
  size=$((($(wc -c < "$state/candidate.bundle") + 1023) / 1024))
  out=$(host_run clean "{ mkdir -p $REH_DIR && cat > $REH_DIR/candidate.bundle; } 2>&1" < "$state/candidate.bundle" 2> /dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail copy - "the bundle could not be copied to the clean host (exit $rc): $(printf '%s\n' "$out" | tail -n 2)"
    return 1
  fi
  out=$(host_run clean "rm -rf $REH_DIR/candidate && git clone -q --branch '$branch' $REH_DIR/candidate.bundle $REH_DIR/candidate 2>&1 && git -C $REH_DIR/candidate rev-parse HEAD" < /dev/null 2> /dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail copy - "git clone of the bundle failed (exit $rc): $(printf '%s\n' "$out" | tail -n 2)"
    return 1
  fi
  got=$(printf '%s\n' "$out" | tail -n 1 | tr -d '\r ')
  if [ "$got" != "$sha" ]; then
    step_fail copy - "the clone is at ${got:0:12} and the candidate is ${sha:0:12}"
    return 1
  fi
  step_pass copy "git bundle of $size KiB; the clone is at the candidate commit"
}

# install_bound: the step's limit, from OCUTALON_INSTALL_WAIT or 900.
install_bound() {
  local w
  if [ "$(opt mode)" = dry ]; then w=${STANDIN_WAIT:-900}; else w=${OCUTALON_INSTALL_WAIT:-900}; fi
  case $w in '' | *[!0-9]*) w=900 ;; esac
  echo "ready within $w s"
}

step_install() {
  local bound out rc t0 t1 first prefix="" tail5 why w
  bound=$(install_bound)
  host_run clean "{ cd $REH_DIR/candidate && umask 077 && cat > .env; } 2>&1" < "$(env_file_path)" > /dev/null 2> /dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail install "$bound" "the env file could not be written to the clone's .env (exit $rc)"
    return 1
  fi
  if [ "$(opt mode)" = real ]; then
    w=${OCUTALON_INSTALL_WAIT:-}
    case $w in '' | *[!0-9]*) ;; *) prefix="env OCUTALON_INSTALL_WAIT=$w " ;; esac
  fi
  t0=$(date +%s)
  host_run clean "cd $REH_DIR/candidate && ${prefix}bash install.sh 2>&1" < /dev/null > "$state/install.out" 2> /dev/null
  rc=$?
  t1=$(date +%s)
  first=$((t1 - t0))
  if [ "$rc" -ne 0 ] || ! parse_install "$state/install.out"; then
    if [ "$rc" -ne 0 ]; then why="install.sh exited $rc after $first s"; else why="install.sh printed no $PI_MISSING line"; fi
    tail5=$(tail -n 5 "$state/install.out")
    fail_line install "$bound" "$why"
    printf '%s\n' "$tail5" | sed 's/^/  /'
    step_record install fail "$why; last lines: $tail5"
    return 1
  fi
  step_pass install "install.sh reached ready; first start $first s, install included; install.sh said \"$PI_READY\""
}

step_signin() {
  local host url cfg out rc
  if [ "$(opt mode)" = dry ]; then host=127.0.0.1; else host=$REHEARSAL_CLEAN_WEB; fi
  url="http://$host:$PI_PORT/ocutalon/"
  printf 'http://%s:%s\n' "$host" "$PI_PORT" > "$state/origin"
  printf '%s\n' "$PI_USER" > "$state/user"
  cfg=$(signin_config "$url" "$PI_USER" "$PI_PASSWORD")
  out=$(printf '%s\n' "$cfg" | host_run driver "umask 077 && mkdir -p $REH_DIR && curl -K -; r=\$?; rm -f $REH_DIR/cookies.jar; exit \$r" 2> /dev/null)
  rc=$?
  case $out in
    *'<app-root'*)
      step_pass sign-in "the driver host signed in at the printed address as the printed user"
      ;;
    *)
      step_fail sign-in - "the driver host's page after sign-in holds no <app-root (curl exit $rc)"
      return 1
      ;;
  esac
}

# --- the phases ---

phase_install() {
  local s rc=0 failed="" began=$SECONDS fname
  trap reh_abort EXIT
  phase_mark install failed 0
  : > "$state/results"
  REHEARSAL_MODE=$(opt mode)
  REHEARSAL_LOCAL_DIR=$state/local
  mkdir -p "$REHEARSAL_LOCAL_DIR"
  if [ "$REHEARSAL_MODE" = dry ]; then dry_prepare; fi
  for s in hosts copy install sign-in; do
    if [ -n "$failed" ]; then
      echo "NOT RUN $s: the step $failed failed"
      continue
    fi
    fname=step_${s//-/}
    if ! "$fname"; then
      rc=1
      failed=$s
    fi
  done
  if [ "$REHEARSAL_MODE" = dry ]; then dry_save; fi
  phase_mark install done "$((SECONDS - began))"
  trap - EXIT
  echo "PHASE install done $((SECONDS - began))s ($rc failed)"
  exit "$rc"
}

# section_build <file>: the record section from the options, the machine files and the results.
section_build() {
  local out=$1 mode result row r detail anyfail=0 line
  mode=$(opt mode)
  result=$(rehearsal_result "$mode" "$state/results")
  for row in $REH_ROWS; do
    if [ "$(row_result "$state/results" "$row")" = fail ]; then anyfail=1; fi
  done
  {
    echo "## Clean-machine rehearsal"
    echo
    echo "Result: $result"
    if [ "$mode" = dry ]; then echo "Mode: dry run"; else echo "Mode: rehearsal"; fi
    line="Candidate: $(opt version) rc$(opt rc), branch $(opt branch) at $(opt cand_sha)"
    if [ "$mode" = dry ]; then line="$line, a stand-in of $(opt base_sha) with the built web bundle added"; fi
    echo "$line"
    echo "Specs: the REL-2 specs (web/e2e/demo-path) at $(opt base_sha)"
    echo "Clean host: $(cat "$state/machine.clean" 2> /dev/null || echo "not read")"
    echo "Driver host: $(cat "$state/machine.driver" 2> /dev/null || echo "not read")"
    echo "Run: $(opt started) to $(opt ended)"
    if [ "$mode" = dry ]; then echo "Note: $REH_NOTE_DRY"; fi
    echo
    echo "| Step | Result | Detail |"
    echo "| --- | --- | --- |"
    for row in $REH_ROWS; do
      r=$(row_result "$state/results" "$row")
      detail=$(awk -F'|' -v s="$row" '$1 == s { sub(/^[^|]*\|[^|]*\|/, ""); d = $0 } END { print d }' "$state/results" 2> /dev/null)
      if [ "$r" = "not run" ] && [ -z "$detail" ]; then
        if [ "$anyfail" = 1 ]; then
          detail="an earlier step failed"
        elif [ "$row" = runs ]; then
          detail="no timed run yet; the runs phase follows a passed install"
        elif [ "$(row_result "$state/results" install)" = pass ]; then
          detail="no timed run yet"
        else
          detail="the step did not run"
        fi
      fi
      printf '| %s | %s | %s |\n' "$(row_title "$row")" "$r" "$detail"
    done
    if [ -s "$state/runs.table" ] && [ ! -e "$state/withheld" ]; then
      echo
      cat "$state/runs.table"
    fi
  } > "$out"
}

# config_values: the configuration's values as this script uses them (quotes and spaces taken off, ~/ expanded), as NAME=value lines,
# with the host of each user@host destination as <NAME>_HOST. Read only by env_file_hits, which never prints a value.
config_values() {
  local k var v
  for k in $REHEARSAL_KEYS; do
    var=REHEARSAL_$k
    v=${!var:-}
    [ -n "$v" ] || continue
    printf '%s=%s\n' "$var" "$v"
    case $k:$v in
      CLEAN_SSH:*@* | DRIVER_SSH:*@*) printf '%s_HOST=%s\n' "$var" "${v#*@}" ;;
    esac
  done
}

# scan_run: the secrets step. Prints the detail of a failure and returns 1; prints nothing and returns 0 when nothing is found.
scan_run() {
  local envf hits cfghits h f kl names="" n rc scanned
  envf=$(env_file_path)
  scanned=("$state/output.log" "$state/section.md")
  if [ -f "$state/install.out" ]; then scanned+=("$state/install.out"); fi
  hits=$(env_file_hits "$envf" "${scanned[@]}")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "the env file or the output could not be read for the scan"
    return 1
  fi
  if [ "$(opt mode)" = real ]; then
    cfghits=$(env_file_hits "$(release_config_path)" "${scanned[@]}")
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "the configuration file could not be read for the scan"
      return 1
    fi
    for f in "${scanned[@]}"; do
      if ! h=$(env_file_hits <(config_values) "$f"); then
        echo "the configuration could not be read for the scan"
        return 1
      fi
      cfghits=$(printf '%s\n%s\n' "$cfghits" "$h")
    done
    hits=$(printf '%s\n%s\n' "$hits" "$cfghits" | grep . | LC_ALL=C sort -u)
  fi
  kl=$(key_like "${scanned[@]}")
  if [ -z "$hits" ] && [ -z "$kl" ]; then return 0; fi
  if [ -n "$hits" ]; then
    names=$(printf '%s\n' "$hits" | awk '{ n[$2]++ } END { for (k in n) print k " in " n[k] " line(s)" }' | LC_ALL=C sort | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  fi
  if [ -n "$kl" ]; then
    n=$(printf '%s\n' "$kl" | grep -c .)
    names="$names${names:+; }key-like text in $n line(s)"
  fi
  echo "$names"
  return 1
}

# The lines of the bounds program for runs: the files marks.page, marks.server and verdict of each run, read in one awk (run number from the
# path). A verdict is "<k> verdict pass" or "<k> verdict fail <step>|<detail>"; a run with no verdict file gets none, which the program fails.
IFS= read -r -d '' FEED_AWK <<'EOS' || true
function runof(path,   n, a) { n = split(path, a, "/"); return a[n - 1] }
FNR == 1 { k = runof(FILENAME) }
FILENAME ~ /marks\.page$/ { print k " page " $0; next }
FILENAME ~ /marks\.server$/ { print k " server " $0; next }
FILENAME ~ /verdict$/ { hv[k] = 1; if (FNR == 1) v1[k] = $0; if (FNR == 2) v2[k] = $0; next }
END {
  for (k in hv) {
    if (v1[k] == "pass") print k " verdict pass"
    else print k " verdict fail " (v2[k] == "" ? "run|the run left no verdict" : v2[k])
  }
}
EOS

# runs_feed <state> <k>...: the lines of the bounds program for the given runs.
runs_feed() {
  local st=$1 k f files=()
  shift
  for k in "$@"; do
    printf '%s run\n' "$k"
    for f in marks.page marks.server verdict; do
      if [ -s "$st/runs/$k/$f" ]; then files+=("$st/runs/$k/$f"); fi
    done
  done
  if [ "${#files[@]}" -gt 0 ]; then awk "$FEED_AWK" "${files[@]}"; fi
}

# runs_ids <state>: the run numbers of the state, ascending.
runs_ids() { ls "$1/runs" 2> /dev/null | grep -E '^[0-9]+$' | sort -n; }

# bounds_eval <state> [<planted id>]: reads every runs/*/marks.page, marks.server and verdict of the state and applies the Bounds table. It
# writes <state>/bounds (id|step|result|detail), <state>/runs.table (the "### Runs" table) and <state>/runs.stat ("<runs> <passed runs>"), and
# prints a FAIL line for each failed verdict, missing mark and missed bound. A met bound reads "pass" in real mode and "dry run" in a dry run.
# The median is taken in awk (insertion sort) because the runs are few.
bounds_eval() {
  local st=$1 plant=${2:-} passw
  if [ "$(env_get "$st/options" mode)" = dry ]; then passw="dry run"; else passw=pass; fi
  : > "$st/bounds"
  : > "$st/runs.table"
  : > "$st/runs.stat"
  runs_feed "$st" $(runs_ids "$st") | awk -v mode=eval -v passw="$passw" -v plant="$plant" -v bfile="$st/bounds" -v tfile="$st/runs.table" -v sfile="$st/runs.stat" "$BOUNDS_AWK"
  [ -s "$st/runs.stat" ] || echo "0 0" > "$st/runs.stat"
  [ -n "$(runs_ids "$st")" ] || : > "$st/runs.table"
  return 0
}

# bounds_merge: the bound rows and the runs row of the state's results, from bounds_eval's files and the verdicts.
bounds_merge() {
  local id step result detail n passed want
  for id in runs $REH_BOUND_ROWS; do
    if [ -f "$state/results" ]; then
      grep -v "^$id|" "$state/results" > "$state/results.new"
      mv "$state/results.new" "$state/results"
    fi
  done
  while IFS='|' read -r id step result detail; do
    [ -n "$id" ] || continue
    printf '%s|%s|%s\n' "$id" "$result" "$(printf '%s' "$detail" | detail_clean)" >> "$state/results"
  done < "$state/bounds"
  read -r n passed < "$state/runs.stat"
  want=$(opt runs)
  case $want in '' | *[!0-9]*) want=1 ;; esac
  if [ "${n:-0}" -eq 0 ]; then
    printf 'runs|not run|\n' >> "$state/results"
  elif [ "$passed" -lt "$n" ]; then
    printf 'runs|fail|%s of %s runs failed the REL-2 specs or left a mark missing\n' "$((n - passed))" "$n" >> "$state/results"
  elif [ "$n" -lt "$want" ]; then
    printf 'runs|not run|%s of %s runs done; run 2 and later come with Story 11.12\n' "$n" "$want" >> "$state/results"
  else
    printf 'runs|pass|%s of %s runs passed the REL-2 specs\n' "$passed" "$n" >> "$state/results"
  fi
}

phase_report() {
  local result detail rc
  env_set "$state/options" ended "$(now_utc)"
  step_record secrets pass "no .env or configuration value in the output or the record"
  rm -f "$state/withheld"
  bounds_eval "$state" "$report_plant"
  bounds_merge
  section_build "$state/section.md"
  if ! detail=$(scan_run); then
    step_fail secrets - "$detail"
    : > "$state/withheld"
    # A value was found: no other row's text is written to the record.
    awk -F'|' '$1 == "secrets" { print; next } { print $1 "|" $2 "|withheld: the secrets step found a value in this run" }' "$state/results" > "$state/results.new" \
      && mv "$state/results.new" "$state/results"
    section_build "$state/section.md"
  else
    echo "PASS secrets no .env or configuration value in the output or the record"
  fi
  result=$(rehearsal_result "$(opt mode)" "$state/results")
  record_file=$(opt record)
  case $record_file in /*) ;; *) record_file=$reh_root/$record_file ;; esac
  if ! record_write "$record_file" "$state/section.md" "# OcuTalon $(opt version) rc$(opt rc)"; then
    echo "FAIL the record could not be written"
    exit 1
  fi
  echo "RECORD $(opt record)"
  echo "RESULT $result"
  rc=$(rehearsal_exit "$result")
  exit "$rc"
}

# --- the commands ---

rehearse_usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$reh_root/release/rehearse.sh" >&2
}

# no_plant: --plant is taken by report and run only.
no_plant() {
  if [ -n "$o_plant" ]; then
    refuse "--plant is taken by report and run"
    return 2
  fi
}

cmd_plan() {
  local hc hd
  parse_options "$@" || exit 2
  no_plant || exit 2
  resolve_candidate || exit 2
  if [ "$o_dry" = 1 ]; then
    hc="stand-in"
    hd="stand-in"
  else
    real_config || exit 2
    hc=configured
    if [ "$REHEARSAL_DRIVER_SSH" = local ]; then hd=local; else hd=configured; fi
  fi
  echo "PLAN candidate $c_ref"
  echo "PLAN version $c_version rc$o_rc at $c_sha"
  echo "PLAN mode $([ "$o_dry" = 1 ] && echo "dry run" || echo rehearsal)"
  echo "PLAN hosts clean $hc, driver $hd"
  echo "PLAN phases install runs report down (run does all four); steps hosts copy install sign-in secrets; runs $o_runs"
  echo "PLAN record ${o_record:-$(record_path "$c_version" "$o_rc")}"
  exit 0
}

cmd_install() {
  local rc
  parse_options "$@" || exit 2
  no_plant || exit 2
  need_tag install || exit 2
  resolve_candidate || exit 2
  if [ "$o_dry" != 1 ]; then real_config || exit 2; fi
  if [ -e "$state" ]; then
    refuse "install: the tag $OCUTALON_RUN_TAG has a state already; use a fresh OCUTALON_RUN_TAG, or run down first"
    exit 2
  fi
  mkdir -p "$state" && chmod 700 "$state" || exit 1
  : > "$state/output.log"
  options_write
  reh_logged phase_install
  rc=$?
  if [ -d "$state" ] && ! phase_done install; then rm -rf "$state"; fi
  exit "$rc"
}

cmd_report() {
  local rc plant=""
  if [ $# -gt 0 ]; then
    if [ "$1" != --plant ] || [ $# -ne 2 ] || [ -z "$2" ]; then
      rehearse_usage
      exit 2
    fi
    plant=$2
  fi
  need_tag report || exit 2
  if [ ! -d "$state" ] || ! phase_done install; then
    refuse "report: the install phase of tag $OCUTALON_RUN_TAG has not finished (or there is no state); run install first"
    exit 2
  fi
  REHEARSAL_MODE=$(opt mode)
  if [ -n "$plant" ]; then
    if [ "$REHEARSAL_MODE" != dry ]; then
      refuse "report: --plant is for dry runs only"
      exit 2
    fi
    if ! plant_ok "$plant"; then
      refuse "report: --plant '$plant' is not a bound id with a limit ($REH_PLANTABLE)"
      exit 2
    fi
  fi
  report_plant=$plant
  if [ "$REHEARSAL_MODE" = real ]; then real_config || exit 2; fi
  reh_logged phase_report
  rc=$?
  exit "$rc"
}

# --- exec and the timed run ---

# need_installed <phase>: sets state; the install phase finished and its four steps passed (else a REFUSED line on standard error, return 2).
need_installed() {
  local st
  need_tag "$1" || return 2
  if [ ! -d "$state" ] || ! phase_done install; then
    refuse "$1: the install phase of tag $OCUTALON_RUN_TAG has not finished (or there is no state); run install first" >&2
    return 2
  fi
  for st in hosts copy install sign-in; do
    if [ "$(row_result "$state/results" "$st")" != pass ]; then
      refuse "$1: the install step $st did not pass; run down and install again" >&2
      return 2
    fi
  done
  return 0
}

# runtime_prepare: the host seam of a later process (exec, runs): the mode, and the stand-in or the configuration.
runtime_prepare() {
  c_sha=
  REHEARSAL_MODE=$(opt mode)
  REHEARSAL_LOCAL_DIR=$state/local
  mkdir -p "$REHEARSAL_LOCAL_DIR"
  if [ "$REHEARSAL_MODE" = dry ]; then
    standin_load
  else
    if [ "${1:-}" = guard ]; then c_sha=$(opt cand_sha); fi
    real_config >&2 || return 2
  fi
}

# namespace_ok <name>: 0 when the whole string is [A-Z][A-Z0-9]* (a newline never matches).
namespace_ok() {
  local LC_ALL=C
  case $1 in
    '' | [!A-Z]* | *[!A-Z0-9]*) return 1 ;;
  esac
  return 0
}

cmd_exec() {
  local ns=OCUTALON k cnt
  if [ $# -gt 1 ]; then
    rehearse_usage
    exit 2
  fi
  if [ $# -eq 1 ]; then ns=$1; fi
  if ! namespace_ok "$ns"; then
    refuse "exec: the namespace must match [A-Z][A-Z0-9]*" >&2
    exit 2
  fi
  need_installed exec || exit 2
  runtime_prepare || exit 2
  k=${OCUTALON_REHEARSAL_RUN:-}
  case $k in
    '' | *[!0-9]*) ;;
    *)
      mkdir -p "$state/runs/$k"
      cnt=$(cat "$state/runs/$k/exec.count" 2> /dev/null || echo 0)
      case $cnt in '' | *[!0-9]*) cnt=0 ;; esac
      echo $((cnt + 1)) > "$state/runs/$k/exec.count"
      ;;
  esac
  host_run clean "cd $REH_DIR/candidate && docker compose exec -T iris iris session IRIS -U $ns" 2> /dev/null
  exit $?
}

# chk_lines: the CHK| lines of an iris session's output, from CHK| on, without carriage returns (the filter of the specs' irisScript).
chk_lines() { tr -d '\r' | awk '{ i = index($0, "CHK|"); if (i > 0) print substr($0, i) }'; }

# exec_chk <script> [<line that proves the script finished>]: the script through this script's exec, at most three tries 5 s apart while it
# printed no CHK| line (or not the proof); prints the CHK| lines and returns 1 when none came.
exec_chk() {
  local script=$1 proof=${2:-} out tries=0 me=$reh_root/release/rehearse.sh
  while [ "$tries" -lt 3 ]; do
    out=$(printf '%s\n' "$script" | env -u OCUTALON_REHEARSAL_RUN bash "$me" exec 2> /dev/null | chk_lines)
    if [ -n "$out" ] && { [ -z "$proof" ] || printf '%s\n' "$out" | grep -qxF "$proof"; }; then
      printf '%s\n' "$out"
      return 0
    fi
    tries=$((tries + 1))
    if [ "$tries" -lt 3 ]; then sleep 5; fi
  done
  [ -n "${out:-}" ] && printf '%s\n' "$out"
  return 1
}

# marks_server_write <chk lines>: marks.server lines from the collector's CHK| lines.
marks_server_write() {
  printf '%s\n' "$1" | awk -F'|' '
    $2 == "mark" { if ($4 ~ /^[0-9]+$/) print "mark " $3 " " $4; else print "missing " $3; next }
    $2 == "reminder" { if ($3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/) print "reminder " $3 " " $4; else print "missing fired"; next }
    $2 == "late" { if ($3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/) print "late " $3 " " $4; next }
    $2 == "tokens" { if ($3 ~ /^[0-9]+$/) print "tokens " $3; else print "missing tokens"; next }
    $2 == "missing" { if ($3 ~ /^[a-z_]+$/) print "missing " $3; next }'
}

# summary_step <reason>: the step id that a failure of demo-path-summary.mjs names (a spec file, or "step <n> <id>"), else run.
summary_step() {
  local id
  id=$(printf '%s\n' "$1" | sed -n 's/.*0[1-8]-\([a-z][a-z-]*\)\.spec\.ts.*/\1/p' | head -n 1)
  [ -n "$id" ] || id=$(printf '%s\n' "$1" | sed -n 's/.*telegram-\([a-z][a-z-]*\)\.spec\.ts.*/\1/p' | head -n 1)
  [ -n "$id" ] || id=$(printf '%s\n' "$1" | sed -n 's/^step [1-8] \([a-z][a-z-]*\).*/\1/p' | head -n 1)
  [ -n "$id" ] || id=run
  printf '%s\n' "$id"
}

# scrub_origin: the clean host's address, which is a configuration value in real mode, becomes "<clean host>" in the text of the specs.
scrub_origin() {
  local host
  if [ "$(opt mode)" = real ]; then
    host=$(sed 's#^http://##; s#:[0-9]*$##' "$state/origin" 2> /dev/null)
  else
    host=""
  fi
  REH_SCRUB=$host awk 'BEGIN { h = ENVIRON["REH_SCRUB"] } { s = $0; out = ""; if (h != "") { while ((i = index(s, h)) > 0) { out = out substr(s, 1, i - 1) "<clean host>"; s = substr(s, i + length(h)) } } print out s }'
}

# phase_runs: run 1 of the timed runs (see the header).
phase_runs() {
  local k=1 dir me origin user model start out script e2e_rc sum_rc execs line step reason fails=0 first_step="" first_reason="" wait_ms
  dir=$state/runs/$k
  me=$reh_root/release/rehearse.sh
  mkdir -p "$dir"
  : > "$dir/marks.page"
  : > "$dir/marks.server"
  echo 0 > "$dir/exec.count"
  origin=$(cat "$state/origin" 2> /dev/null)
  user=$(cat "$state/user" 2> /dev/null)
  if [ -z "$origin" ] || ! printf '%s\n' "$user" | grep -Eq '^[A-Za-z0-9_.-]+$'; then
    fail_run_line "$k" run - "the install left no address or user to run against"
    printf 'fail\nrun|the install left no address or user to run against\n' > "$dir/verdict"
    return 1
  fi
  start=$(exec_chk 'Write !,"CHK|now|",$ZDATETIME($ZTIMESTAMP,3,1,3)
Halt' | sed -n 's/^CHK|now|//p' | head -n 1)
  if ! printf '%s\n' "$start" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+$'; then
    fail_run_line "$k" run - "the server clock could not be read through the exec channel"
    printf 'fail\nrun|the server clock could not be read through the exec channel\n' > "$dir/verdict"
    return 1
  fi
  printf '%s\n' "$start" > "$dir/server.start"
  if [ "$(opt mode)" = dry ]; then model=mock; else model=real; fi
  wait_ms=${OCUTALON_E2E_TIMEOUT_MS:-480000}
  case $wait_ms in '' | *[!0-9]* | 0*) wait_ms=480000 ;; esac
  echo "PHASE runs: run $k of the REL-2 specs against the install (at most $((wait_ms / 1000)) s)"
  (
    cd "$reh_root" && env -u ANTHROPIC_API_KEY -u TELEGRAM_BOT_TOKEN \
      OCUTALON_URL="$origin" OCUTALON_E2E_JSON="$dir/report.json" OCUTALON_E2E_MARKS="$dir/marks.page" \
      OCUTALON_E2E_IRIS_EXEC="bash '$me' exec" OCUTALON_REHEARSAL_RUN="$k" OCUTALON_DEMO_PATH_MODEL="$model" \
      OCUTALON_E2E_TIMEOUT_MS="$wait_ms" \
      npm --prefix web run e2e:demo-path > "$dir/e2e.log" 2>&1
  )
  e2e_rc=$?
  scrub_origin < "$dir/e2e.log" | sed 's/^/  /'
  if [ "$e2e_rc" -ne 0 ] && grep -q "Executable doesn't exist" "$dir/e2e.log"; then
    echo "  the browser is missing: run npx --prefix web playwright install chromium"
  fi
  node web/scripts/demo-path-summary.mjs --only-telegram-skips "$dir/report.json" > "$dir/summary.log" 2>&1
  sum_rc=$?
  scrub_origin < "$dir/summary.log" > "$dir/summary.scrubbed"
  mv "$dir/summary.scrubbed" "$dir/summary.log"
  cat "$dir/summary.log"
  while IFS= read -r line; do
    case $line in
      "FAIL "*)
        reason=${line#FAIL }
        step=$(summary_step "$reason")
        fail_run_line "$k" "$step" - "$reason"
        fails=$((fails + 1))
        if [ -z "$first_step" ]; then
          first_step=$step
          first_reason=$reason
        fi
        ;;
    esac
  done < "$dir/summary.log"
  if [ "$sum_rc" -ne 0 ] && [ "$fails" -eq 0 ]; then
    first_step=run
    first_reason="demo-path-summary.mjs exited $sum_rc and printed no FAIL line"
    fail_run_line "$k" run - "$first_reason"
    fails=1
  elif [ "$e2e_rc" -ne 0 ] && [ "$fails" -eq 0 ]; then
    first_step=run
    first_reason="Playwright exited $e2e_rc although the summary found no failed step"
    fail_run_line "$k" run - "$first_reason"
    fails=1
  fi
  execs=$(cat "$dir/exec.count" 2> /dev/null)
  case $execs in '' | *[!0-9]*) execs=0 ;; esac
  if [ "$execs" -eq 0 ]; then
    fail_run_line "$k" run - "the specs read nothing through the rehearsal's exec channel"
    if [ "$fails" -eq 0 ]; then
      first_step=run
      first_reason="the specs read nothing through the rehearsal's exec channel"
    fi
    fails=$((fails + 1))
  fi
  if [ "$fails" -eq 0 ]; then
    printf 'pass\n' > "$dir/verdict"
  else
    printf 'fail\n%s|%s\n' "$first_step" "$(printf '%s' "$first_reason" | detail_clean)" > "$dir/verdict"
  fi
  # The collector runs also after a failed run: the marks it finds are the run's record.
  script=${COLLECTOR//@START@/$start}
  script=${script//@USER@/$user}
  if out=$(exec_chk "$script" 'CHK|done|1'); then
    marks_server_write "$out" > "$dir/marks.server"
  else
    { marks_server_write "$out"; echo "missing collector"; } > "$dir/marks.server"
  fi
  runs_feed "$state" "$k" | awk -v mode=run "$BOUNDS_AWK"
  local mrc=${PIPESTATUS[1]}
  if [ "$fails" -eq 0 ] && [ "$mrc" -eq 0 ]; then
    echo "PASS run $k demo path: $(grep '^DEMO-PATH' "$dir/summary.log" | head -n 1)"
    return 0
  fi
  return 1
}

cmd_runs() {
  local rc
  if [ $# -gt 0 ]; then
    rehearse_usage
    exit 2
  fi
  need_installed runs || exit 2
  if [ -e "$state/runs/1" ]; then
    refuse "runs: run 1 exists; run 2 and later (Run again and the replay rule) come with Story 11.12"
    exit 2
  fi
  runtime_prepare guard || exit 2
  reh_logged phase_runs
  rc=$?
  exit "$rc"
}

cmd_down() {
  local f c images n
  if [ $# -gt 0 ]; then
    rehearse_usage
    exit 2
  fi
  need_tag down || exit 2
  if [ ! -d "$state" ]; then
    echo "TEARDOWN nothing to remove for tag $OCUTALON_RUN_TAG (no state)"
    exit 0
  fi
  if [ "$(opt mode)" = dry ] || [ -f "$state/standin/project" ]; then
    . "$reh_root/ci/iris.sh"
    cmd_teardown
    images=$state/standin/images
    if [ -f "$images" ]; then
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        case $n in
          sha256:*) docker image rm -f "$n" > /dev/null 2>&1 ;;
          *) docker image rm "$n" > /dev/null 2>&1 ;;
        esac
      done < "$images"
    fi
    f=$(cat "$state/standin/lock.file" 2> /dev/null)
    c=$(cat "$state/standin/lock.content" 2> /dev/null)
    if [ -n "$f" ]; then
      P=$(cat "$state/standin/project" 2> /dev/null)
      LIVE_LOCK_FILE=$f
      LIVE_LOCK_CONTENT=$c
      live_lock_release
    fi
    rm -rf "$state"
    echo "TEARDOWN rehearsal tag $OCUTALON_RUN_TAG: the throwaway and the state are removed (the LOCK line says what became of the lock)"
  else
    rm -rf "$state"
    echo "TEARDOWN rehearsal tag $OCUTALON_RUN_TAG: the state is removed; the clean host keeps its install"
  fi
  exit 0
}

cmd_run() {
  local me=$reh_root/release/rehearse.sh rc report_rc rrc want made=0 iargs=()
  parse_options "$@" || exit 2
  if [ -n "$o_plant" ] && [ "$o_dry" != 1 ]; then
    refuse "--plant is for dry runs only"
    exit 2
  fi
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then OCUTALON_RUN_TAG="reh-$(date +%s)"; fi
  export OCUTALON_RUN_TAG
  need_tag run || exit 2
  # install takes the options but --plant, which report takes.
  while [ $# -gt 0 ]; do
    case $1 in
      --plant) shift 2 ;;
      *)
        iargs+=("$1")
        shift
        ;;
    esac
  done
  (cd "$reh_caller_pwd" && bash "$me" install "${iargs[@]}")
  rc=$?
  case $rc in
    2 | 75) exit "$rc" ;;
  esac
  if [ ! -d "$state" ]; then exit "$rc"; fi
  if ! phase_done install; then
    bash "$me" down
    exit "$rc"
  fi
  if [ "$rc" -eq 0 ]; then
    want=$(opt runs)
    while [ "$made" -lt "$want" ]; do
      bash "$me" runs
      rrc=$?
      if [ "$rrc" -ne 0 ]; then break; fi
      made=$((made + 1))
    done
  fi
  if [ -n "$o_plant" ]; then
    bash "$me" report --plant "$o_plant"
  else
    bash "$me" report
  fi
  report_rc=$?
  bash "$me" down
  exit "$report_rc"
}

main() {
  local cmd=${1:-}
  if [ $# -gt 0 ]; then shift; fi
  case $cmd in
    plan) cmd_plan "$@" ;;
    install) cmd_install "$@" ;;
    runs) cmd_runs "$@" ;;
    exec) cmd_exec "$@" ;;
    report) cmd_report "$@" ;;
    down) cmd_down "$@" ;;
    run) cmd_run "$@" ;;
    *)
      rehearse_usage
      exit 2
      ;;
  esac
}

# Sourced (by docker/tests/test-rehearsal.sh), it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

main "$@"
