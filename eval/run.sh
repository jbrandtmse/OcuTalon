#!/usr/bin/env bash
# The evaluation run (Stories 9.2, 9.3, 9.5, 9.7, 9.8 and 9.10; AD-22, AD-19, AD-29, AD-30; CON-3; REL-5). It is the script of the evaluation job of
# .github/workflows/lane-a.yml and runs the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash eval/run.sh                                      the push run, on the CI mock
#   OCUTALON_RUN_TAG=<tag> bash eval/run.sh --release-candidate                  a release candidate, on the real model
#   OCUTALON_RUN_TAG=<tag> bash eval/run.sh --release-candidate --on-mock        the same sequence on the CI mock: no key, no spend
#   OCUTALON_RUN_TAG=<tag> bash eval/run.sh --release-candidate --on-mock --key-path   the key-path rehearsal, with a key in the environment
#                                                                                      (eval/key-proof.sh runs it with a fake key)
#   bash eval/run.sh --override "<reason>"                                       the author's override of a blocked result
# Any other argument prints a usage line and exits 2, before any call to the container tool. Every mode but --override sources ci/iris.sh
# (which sources ci/units.sh and docker/tests/lib-live.sh), starts a throwaway of its own that is built from this checkout, and reaches the
# container only through the functions of those files (stack_start, stack_ready, check_session, iris_script, dc exec). It never pulls the
# base image, never runs warm, and its exit trap removes its project, its volume, its images and its lock. It exports OCUTALON_EVAL=1 for
# its own process only: that switch enables EvalIn in this throwaway, and no workflow, compose file or class default sets it (owner
# condition U-131).
# Variables:
#   OCUTALON_RUN_TAG          the run tag of ci/iris.sh (default local-<epoch>-<pid>)
#   OCUTALON_EVAL_WAIT        the seconds each run may take, after it has sent its cases, to have every case decided: a whole number
#                             from 1 to 3600 (default 180, and 900 with --release-candidate); anything else exits 2. The turn cases are
#                             decided while they are sent (each ask waits up to EvalIn's TURNWAIT, and a Busy turn is asked again), so this
#                             wait does not bound them
#   OCUTALON_EVAL_REPORT_DIR  the folder that receives the report files (default: a new folder from mktemp -d below
#                             ${RUNNER_TEMP:-${TMPDIR:-/tmp}})
#   ANTHROPIC_API_KEY         --release-candidate without --on-mock, and --release-candidate --on-mock --key-path: the model key, which must
#                             be set and not empty in the environment of this script, or the script exits 2 before any call to the container
#                             tool. The key reaches only the iris service of the throwaway, by the interpolation of
#                             eval/compose.release-candidate.yml (AD-19). The script never prints it, never writes it to a file and never
#                             puts it in a session. In every other mode (the push run, --override and --on-mock without --key-path) the
#                             script unsets it before anything else, whatever the caller's environment holds, so that neither compose, npm
#                             nor IRIS ever sees it
# The push run (no argument):
#   1. the throwaway starts and the production runs with every item (RunnerFixture.ReadyReason() is empty); the runners' keys are
#      pointed at the mock with RunnerFixture.PointKeys(), as the live units do;
#   2. run 1, the set: OcuTalon.Eval.Report.Run over /opt/ocutalon/eval/, saved in the container as set.json and set.md;
#   3. run 2, the test-only cases of eval/mock-wrong/, which the mock answers wrongly on purpose: saved as mock-wrong.json and
#      mock-wrong.md. Both runs print a first CHK line before they call Report.Run, because iris_script runs a session again when it
#      printed no CHK line, and that early line keeps it from starting a second run;
#   3b. run 3, the demo gate, only when run 1 diagnosed the demo incident (else it fails without running): OcuTalon.Eval.Gate.Demo runs the demo
#      incident 10 times through IncidentManager's evaluation path and saves
#      demo.json; then Gate.Attempt reads set.json and demo.json and saves attempt.json. The checks are structural (the mock's one diagnosis
#      is the demo's right answer): 10 runs, 10 passed, no fallback, valid parameters and a diagnosis time for each. The attempt's
#      targets are printed as an INFO line and never fail the run;
#   4. the files are copied out into the report folder, the Markdown texts are printed and appended to $GITHUB_STEP_SUMMARY when
#      that is set, and "REPORT <folder>" is printed before the closing line "eval/run: all checks passed" (or "... check(s) failed").
# The checks print one PASS or FAIL line each: each run started and finished (a disabled EvalIn fails with the director's text, and so
# does a removal of the run's watches that failed: the run did not start or did not finish), no run left an eval watch row behind (the
# line CHK|leftwatches| counts the watch rows of owner eval after Report.Run, which removes the run's watches), the set has no
# problem, the set has at least one case scored by the injection rule, the set's Markdown has the Injections score line and the section
# "Injection cases" with a bullet for mail-suspicious-request, the set has at least one all-clear case and one command case scored (the
# turn cases of Story 9.7: the lines CHK|allclear| and CHK|commands| carry "<right> of <total>", and a total that is empty, not a number
# or 0 fails), the number of incident case lines of run 1 (the seventh field of CHK|case| is the case's kind) equals the number of top-level
# eval/*/case.json of kind incident and is above 0, and the demo incident's line (Report DEMOCASE, CHK|democase|) has fallback 0 and a got of the form
# causeCategory/elementAtFault/fixKind whose first two parts are not empty (Story 9.6: the incident cases are diagnosed through IncidentManager; the
# other incident lines are printed with an INFO line of their fallbacks, each case with its reason (CHK|fallback|), and checked for nothing more
# than the run having no problem, because the
# mock's one diagnosis answers a repair-and-resend of OrderDate, which Decide accepts only for a sample body that holds that field), the
# set's Markdown has the score lines All-clear and Command and the section "Turn cases" with a bullet for
# allclear-orders-failing and one for command-run-shell, the set has at least one injection case with a watch and every such watch is
# unchanged (the line CHK|watches| carries "<unchanged> of <total>", and a total that is empty, not a number or 0, or an unchanged
# count that is not the total, fails: it is a structural check, not a score), the set's Markdown has the bullet of
# mail-stop-watching-orders with "watch: unchanged", and the mock-wrong run has no problem, at least one case, and every case
# decided (not a fallback) with the scenario's answer and not right. The SM-1, SM-2, injection, all-clear and command results are
# printed and never checked: a score below its target is reported and fails nothing (on the mock the turn cases get the default chat
# script, so both turn scores are 0: the all-clear cases never call check_status, and the command case runs list_productions and gets
# the default reply, which lacks the key phrase). Exits 1 when any check fails, 0 otherwise.
# The release-candidate run (--release-candidate, Story 9.5; REL-5):
#   1. without --on-mock the key is checked first, then the throwaway starts with eval/compose.release-candidate.yml layered last (the shell's key
#      by interpolation, no base-URL override, no mock header), and the readiness check requires every item running, every runner's key present, an
#      empty OCUTALON_MODEL_BASE_URL, no mock header and the model claude-haiku-5-5 for the three runners. With --on-mock the throwaway is the push
#      run's, with PointKeys, and no key is needed (a key in the environment is unset);
#      With --on-mock --key-path (the key-path rehearsal, Story 9.10, owner decision U-168) the key is checked first as well, and it goes through the
#      override into the throwaway, with ci/compose.ci.yml layered again after it, so that every model request still goes to the CI mock and carries
#      the key's length in the mock's log. The readiness check requires the Always tier of the rehearsal (ReadyReason empty, the records, the
#      runners' keys, the Provider placeholder in the entries, the key's length in the IRIS process, the model); PointKeys and RestoreKeys are never
#      called. Before the exit lines the run proves the key is stored and shown nowhere (the key proof, below);
#   2. attempt k (k = 1; then 2 and 3 when attempt 1 did not meet every target) is the set over /opt/ocutalon/eval/ (set-k.json and .md), the demo
#      gate (demo-k.json) and Gate.Attempt (attempt-k.json) with its targets SM-1, SM-2, the demo gate, NFR-3, NFR-4, the model and no problem;
#   3. Gate.Result applies REL-5's rule (pass at the first attempt, or at 2 of 3) and saves release-candidate.json and .md (ocutalon.evalResult/1),
#      with the commit, branch and tree state that the script read before the stack was built;
#   4. the files are copied out into the report folder, and the result's Markdown is printed and appended to $GITHUB_STEP_SUMMARY only when it holds
#      neither key-like text nor the value of the key in the environment (otherwise a NOTE line says it is not printed). Without --on-mock a finished
#      run (verdict pass or blocked, no structural failure) also copies the pair to eval/release-candidate.json and .md; with --on-mock the pair is
#      release-candidate-on-mock.* in the report folder only, and eval/ is not touched. Neither form runs eval/mock-wrong/. The thinking-history smoke
#      test is not run (Story 30.1);
#   5. the pair that was written is scanned with the key-like patterns of docker/tests/lib-keys.sh, the definition that
#      docker/tests/test-boundaries.sh also reads: "PASS <name>: the result pair holds no key-like text", or, on a match, a FAIL line that names
#      file:line (never the text) and tells the author not to commit the pair, and exit 4 with both files kept.
# The key proof (--on-mock --key-path only; Story 9.10, owner condition U-166 (b)). After the result is printed and before the exit lines, one line
# "PASS key proof <label>: ..." or "FAIL key proof <label>: ..." for each of nine scans for the key's value: globals (every node of every global of
# every mounted database that is not read-only), stores (Test.Agent.KeyScan.Find), trace (the headers and bodies of every Interoperability
# namespace), mock log (at least one /v1/ request, each with a key of the key's length), container logs (streamed, never written), container files
# (below /durable, /tmp and /opt/ocutalon/mock-log), run files (this run's work folder and the report folder), eval files (below eval/) and web bundle
# (src/ocutalon/csp/ of the checkout and its two copies inside the throwaway: the image's and the one the web application serves). Each scan runs a
# positive control that must find something, and fails when it cannot read what it scans (a file, or a folder that cannot be listed). A hit names a place and never the value; the value is read only from the environment (awk ENVIRON,
# $SYSTEM.Util.GetEnviron, printenv inside the container). The last line is counts only: "PASS key proof counts: iris environment 1, container logs 0,
# result files 0, trace 0, web bundle 0" (the key is in the iris container's environment exactly once and in nothing else; the key proof of
# eval/key-proof.sh adds the run's output). Any FAIL ends the run with exit 1.
# Exit codes: 0 pass (and a finished --on-mock run), 1 a structural failure (a session that printed nothing, a run that did not start or
# finish, a file that was not saved, a verdict of incomplete, a failed key proof: nothing is written in eval/), 2 a refused argument or key,
# 3 blocked, 4 the result pair holds key-like text (the files are kept; do not commit them).
# --override "<reason>" records the author's override of a blocked result: it rewrites eval/release-candidate.json (verdict overridden,
# override {reason, at}) and eval/release-candidate.md (the line "Verdict: blocked" becomes "Verdict: overridden (blocked; the author overrode
# it)" and a section Override is appended). It refuses, with exit 2 and both files unchanged, a result that is missing or is not blocked, a
# result already overridden, and a reason that is blank, has a line break, is not printable ASCII, is over 500 characters or holds key-like text.
# After it has written, it scans both files like step 5 (exit 4 on a match). It needs Node, and it starts no container.
# Before a stack starts (every mode), the script runs the preflight and builds the web bundle in a subshell with the key unset (DW-434): no npm
# process ever has the key. The stack's own compose calls keep it, because compose interpolates every file on every call.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

# --- the arguments ---

mode=push
onmock=0
keypath=0
override_reason=
if [ $# -eq 0 ]; then
  :
elif [ $# -eq 1 ] && [ "$1" = --release-candidate ]; then
  mode=rc
elif [ $# -eq 2 ] && [ "$1" = --release-candidate ] && [ "$2" = --on-mock ]; then
  mode=rc
  onmock=1
elif [ $# -eq 3 ] && [ "$1" = --release-candidate ] && [ "$2" = --on-mock ] && [ "$3" = --key-path ]; then
  mode=rc
  onmock=1
  keypath=1
elif [ $# -eq 2 ] && [ "$1" = --override ]; then
  mode=override
  override_reason=$2
else
  echo 'usage: bash eval/run.sh [--release-candidate [--on-mock [--key-path]] | --override "<reason>"]'
  exit 2
fi

# The model key stays in the environment only for the real release candidate and the key-path rehearsal (AD-19). Every other mode drops it first,
# whatever the caller holds, so that no child (compose, npm, an IRIS session) ever sees it.
if [ "$keypath" -eq 0 ] && { [ "$mode" != rc ] || [ "$onmock" -eq 1 ]; }; then
  unset ANTHROPIC_API_KEY
fi

. "$root/docker/tests/lib-keys.sh"

# scan_pair <name> <json> <md>: step 5 of the header. The key-like scan of the two files of a result pair (paths from the root, or absolute): prints
# the PASS line and returns 0, or prints the FAIL line (file:line only, never the text) and returns 1.
scan_pair() {
  local name=$1 json=$2 md=$3 hits
  hits=$(key_like "$json" "$md" | paste -s -d, -)
  if [ -z "$hits" ]; then
    echo "PASS $name: the result pair holds no key-like text"
    return 0
  fi
  echo "FAIL $json and $md hold key-like text at $hits: do not commit them; remove both, find where the text came from, and run again"
  return 1
}

# --- --override: the author's override of a blocked result file ---

# override_result <reason>: see the header. Exit 2 with a FAIL line for every refusal; the files are written last and only when every check holds.
override_result() {
  local reason=$1 json="$root/eval/release-candidate.json" md="$root/eval/release-candidate.md" at program
  if [ -z "$(printf '%s' "$reason" | LC_ALL=C tr -d '[:space:]')" ]; then
    echo "FAIL the override reason is blank"
    exit 2
  fi
  if [ "$(printf '%s' "$reason" | LC_ALL=C tr -d '[:print:]' | wc -c | tr -d ' ')" -ne 0 ]; then
    echo "FAIL the override reason must be one line of printable ASCII"
    exit 2
  fi
  if [ "$(printf '%s' "$reason" | LC_ALL=C wc -c | tr -d ' ')" -gt 500 ]; then
    echo "FAIL the override reason is over 500 characters"
    exit 2
  fi
  if [ -n "$(printf '%s\n' "$reason" | key_like -)" ]; then
    echo "FAIL the override reason holds key-like text"
    exit 2
  fi
  if ! command -v node > /dev/null 2>&1; then
    echo "FAIL node is not installed"
    exit 2
  fi
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  program=$(cat << 'EOF'
const fs = require('node:fs');
const [jsonFile, mdFile, reason, at] = process.argv.slice(1);
const refuse = (why) => {
  console.log('FAIL ' + why);
  process.exit(2);
};
if (!fs.existsSync(jsonFile)) refuse('eval/release-candidate.json does not exist: there is no result to override');
if (!fs.existsSync(mdFile)) refuse('eval/release-candidate.md does not exist: the result has no text to override');
let result;
try {
  result = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
} catch {
  refuse('eval/release-candidate.json is not valid JSON');
}
if (result === null || typeof result !== 'object' || Array.isArray(result)) refuse('eval/release-candidate.json is not a JSON object');
if (result.verdict !== 'blocked') refuse('the verdict of eval/release-candidate.json is not blocked: only a blocked result can be overridden');
if (result.override !== null) refuse('eval/release-candidate.json is already overridden');
const markdown = fs.readFileSync(mdFile, 'utf8');
const lines = markdown.split('\n');
if (lines.filter((line) => line === 'Verdict: blocked').length !== 1) refuse('eval/release-candidate.md has not exactly one line "Verdict: blocked"');
result.verdict = 'overridden';
result.override = { reason, at };
const changed = lines.map((line) => (line === 'Verdict: blocked' ? 'Verdict: overridden (blocked; the author overrode it)' : line)).join('\n');
const text = changed + '\n## Override\n\n' + reason + '\n\nRecorded at ' + at + '.\n';
fs.writeFileSync(jsonFile, JSON.stringify(result));
fs.writeFileSync(mdFile, text);
console.log('OVERRIDE recorded in eval/release-candidate.json and eval/release-candidate.md');
EOF
  )
  node -e "$program" "$json" "$md" "$reason" "$at" || exit $?
  scan_pair override eval/release-candidate.json eval/release-candidate.md || exit 4
  exit 0
}

if [ "$mode" = override ]; then override_result "$override_reason"; fi

# --- the key of a release candidate (AD-19) ---

# The key must be in this script's own environment, exported and not empty. Its value is never printed or stored.
if [ "$mode" = rc ] && { [ "$onmock" -eq 0 ] || [ "$keypath" -eq 1 ]; } && [ -z "$(printenv ANTHROPIC_API_KEY 2> /dev/null)" ]; then
  if [ "$keypath" -eq 1 ]; then
    echo "FAIL ANTHROPIC_API_KEY is not set in the environment of this run: --key-path needs a key there (eval/key-proof.sh builds a fake one)"
  else
    echo "FAIL ANTHROPIC_API_KEY is not set in the environment of this run: a release-candidate run needs the model key there (or use --on-mock)"
  fi
  exit 2
fi

limit=${OCUTALON_EVAL_WAIT:-}
if [ -z "$limit" ]; then
  if [ "$mode" = rc ]; then limit=900; else limit=180; fi
fi
case $limit in
  '' | *[!0-9]*)
    echo "FAIL OCUTALON_EVAL_WAIT '$limit' must be a whole number of seconds from 1 to 3600"
    exit 2
    ;;
esac
limit=$((10#$limit))
if [ "$limit" -lt 1 ] || [ "$limit" -gt 3600 ]; then
  echo "FAIL OCUTALON_EVAL_WAIT '$limit' must be a whole number of seconds from 1 to 3600"
  exit 2
fi

. "$root/ci/iris.sh"
setup_tag
export OCUTALON_EVAL=1

report_dir=${OCUTALON_EVAL_REPORT_DIR:-}
if [ -z "$report_dir" ]; then
  report_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ocutalon-eval.XXXXXX") || exit 1
else
  mkdir -p "$report_dir" || exit 1
fi

CONTAINER_REPORTS=/tmp/ocutalon-eval
EVAL_FOLDER=/opt/ocutalon/eval/

# The outcome that the mock's scenario eval-tellnow-ignored answers to the test-only case (ci/mock/scenarios/A/eval-tellnow-ignored.json).
MOCK_WRONG_ANSWER=ignore

# eval_run <name> <case folder in the container> <title>: one run in its own IRIS session. The session runs Report.Run, prints the
# CHK lines of the run, and saves the report as <name>.json and <name>.md in the container. The lines are in $tmp/<name>.chk.
eval_run() {
  local name=$1 folder=$2 title=$3 begun=$SECONDS
  printf '%s\n' \
    'Write !,"CHK|started|1"' \
    "Set sc=##class(OcuTalon.Eval.Report).Run(\"$folder\",\"\",$limit,.report)" \
    'Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?",##class(OcuTalon.Data.Ownership).#EVAL) Do rs.%Next() Write !,"CHK|leftwatches|",+rs.%GetData(1)' \
    'If $SYSTEM.Status.IsError(sc) { Write !,"CHK|error|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  ") Halt }' \
    'Set problems=##class(OcuTalon.Eval.Report).Problems(report)' \
    'Write !,"CHK|problems|",problems.%Size()' \
    'For i=0:1:problems.%Size()-1 { Write !,"CHK|problem|",$Translate(problems.%Get(i),$Char(13,10),"  ") }' \
    'Write !,"CHK|democase|",##class(OcuTalon.Eval.Report).#DEMOCASE' \
    'Write !,"CHK|cases|",report.cases.%Size()' \
    'For i=0:1:report.cases.%Size()-1 { Set c=report.cases.%Get(i) Write !,"CHK|case|",c.case,"|",c.%Get("right"),"|",$Translate($Select($IsObject(c.got):c.got.causeCategory_"/"_c.got.elementAtFault_"/"_c.got.fixKind,1:c.got),"|"_$Char(13,10),"   "),"|",c.%Get("fallback"),"|",c.%Get("kind") }' \
    'For i=0:1:report.fallbacks.%Size()-1 { Set f=report.fallbacks.%Get(i) Write !,"CHK|fallback|",f.case,"|",$Translate(f.reason,"|"_$Char(13,10),"   ") }' \
    'For g="items","incidents" { Set s=report.scores.%Get(g) Write !,"CHK|",g,"|",s.right," of ",s.total,"|",$Select(s.%GetTypeOf("met")="null":"not measured",s.%Get("met"):"met",1:"not met") }' \
    'Set s=report.scores.injections Write !,"CHK|injections|",s.right," of ",s.total' \
    'Set s=report.scores.allClear Write !,"CHK|allclear|",s.right," of ",s.total' \
    'Set s=report.scores.commands Write !,"CHK|commands|",s.right," of ",s.total' \
    'Set w=0,u=0 For i=0:1:report.injectionChecks.%Size()-1 { Set k=report.injectionChecks.%Get(i) If $IsObject(k.%Get("watch")) { Set w=w+1 If k.watch.unchanged Set u=u+1 } } Write !,"CHK|watches|",u," of ",w' \
    "Set sc=##class(OcuTalon.Eval.Report).Save(report,\"$title\",\"$CONTAINER_REPORTS/\",\"$name\")" \
    'Write !,"CHK|saved|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/$name.chk"
  echo "RUN $name $((SECONDS - begun))s"
  sed 's/^/  /' "$tmp/$name.chk"
}

# demo_run <name>: the demo gate in its own IRIS session: Gate.Demo runs the demo incident OcuTalon.Eval.Gate RUNS times through
# IncidentManager's evaluation path, the session prints CHK|demogate|<passed>|<runs>|<pass> and a line
# CHK|demo|<n>|<pass>|<cause>/<element>/<fix kind>|<fallback>|<parameters valid>|<diagnosis ms>|<reason> for each run, and saves the gate as
# <name>.json. The early CHK line keeps iris_script from starting the runs a second time. The lines are in $tmp/<name>.chk.
demo_run() {
  local name=$1 begun=$SECONDS
  printf '%s\n' \
    'Write !,"CHK|started|1"' \
    "Set sc=##class(OcuTalon.Eval.Gate).Demo(\"$EVAL_FOLDER\",$limit,.gate)" \
    'Write !,"CHK|demorun|",$SYSTEM.Status.IsOK(sc)' \
    'If $SYSTEM.Status.IsError(sc) { Write !,"CHK|error|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  ") Halt }' \
    'Write !,"CHK|demogate|",gate.passed,"|",gate.runs,"|",gate.pass' \
    'For i=0:1:gate.results.%Size()-1 { Set r=gate.results.%Get(i) Write !,"CHK|demo|",r.run,"|",r.pass,"|",$Translate(r.causeCategory_"/"_r.elementAtFault_"/"_r.fixKind,"|"_$Char(13,10),"   "),"|",r.fallback,"|",r.parametersValid,"|",r.durationMs,"|",$Translate(r.reason,"|"_$Char(13,10),"   ") }' \
    "Set sc=##class(OcuTalon.Eval.Report).WriteFiles(\"$CONTAINER_REPORTS/\",\"$name\",gate.%ToJSON())" \
    'Write !,"CHK|saved|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/$name.chk"
  echo "RUN $name $((SECONDS - begun))s"
  sed 's/^/  /' "$tmp/$name.chk"
}

# attempt_run <name> <set name> <demo name> <number>: one attempt in its own IRIS session: it reads <set name>.json and <demo name>.json,
# calls Gate.Attempt, prints CHK|met|, CHK|below| (the labels of the targets not met) and a line CHK|target|<label>|<met> for each target,
# and saves the attempt as <name>.json. The lines are in $tmp/<name>.chk.
attempt_run() {
  local name=$1 set_name=$2 demo_name=$3 number=$4
  printf '%s\n' \
    'Write !,"CHK|started|1"' \
    "Set sd=##class(%DynamicAbstractObject).%FromJSONFile(\"$CONTAINER_REPORTS/$set_name.json\")" \
    "Set dd=##class(%DynamicAbstractObject).%FromJSONFile(\"$CONTAINER_REPORTS/$demo_name.json\")" \
    "Set at=##class(OcuTalon.Eval.Gate).Attempt(sd,dd,$number)" \
    'Write !,"CHK|met|",at.met' \
    'Set below="" For i=0:1:at.below.%Size()-1 { Set below=below_$Select(i:",",1:"")_at.below.%Get(i) } Write !,"CHK|below|",$Translate(below,"|"_$Char(13,10),"   ")' \
    'For n="sm1","sm2","demoGate","nfr3","nfr4","model","clean" { Set t=at.targets.%Get(n) Write !,"CHK|target|",t.label,"|",t.met }' \
    "Set sc=##class(OcuTalon.Eval.Report).WriteFiles(\"$CONTAINER_REPORTS/\",\"$name\",at.%ToJSON())" \
    'Write !,"CHK|saved|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/$name.chk"
  echo "RUN $name"
  sed 's/^/  /' "$tmp/$name.chk"
}

# verdict_run <attempts> <name> <commit> <branch> <tree clean 0|1> <on mock 0|1>: Gate.Result over attempt-1.json to attempt-<attempts>.json
# with the context, saved as <name>.json and <name>.md; prints CHK|verdict|, CHK|attempts| (run and met) and CHK|saved|. The lines are in
# $tmp/<name>.chk.
verdict_run() {
  local count=$1 name=$2 commit=$3 branch=$4 clean=$5 mock=$6
  printf '%s\n' \
    'Write !,"CHK|started|1"' \
    'Set as=[]' \
    "For k=1:1:$count { Do as.%Push(##class(%DynamicAbstractObject).%FromJSONFile(\"$CONTAINER_REPORTS/attempt-\"_k_\".json\")) }" \
    "Set cx={\"commit\":\"$commit\",\"branch\":\"$branch\",\"treeClean\":$clean,\"onMock\":$mock}" \
    'Set rs=##class(OcuTalon.Eval.Gate).Result(as,cx)' \
    'Write !,"CHK|verdict|",rs.verdict' \
    'Write !,"CHK|attempts|",rs.attemptsRun,"|",rs.attemptsMet' \
    "Set sc=##class(OcuTalon.Eval.Gate).Save(rs,\"$CONTAINER_REPORTS/\",\"$name\")" \
    'Write !,"CHK|saved|",$SYSTEM.Status.IsOK(sc)' \
    'Halt' | iris_script OCUTALON > "$tmp/$name.chk"
  echo "RUN $name"
  sed 's/^/  /' "$tmp/$name.chk"
}

# chk_value <name> <key>: the value of the first CHK|<key>| line of the run.
chk_value() {
  sed -n "s/^CHK|$2|//p" "$tmp/$1.chk" | head -n 1
}

# run_started <name>: 0 when the run started, which is also a pass; otherwise it prints the FAIL line and returns 1.
run_started() {
  local name=$1
  if [ ! -s "$tmp/$name.chk" ]; then
    fail "$name: the IRIS session printed nothing"
    return 1
  fi
  if [ "$(chk_value "$name" run)" != 1 ]; then
    fail "$name: the run did not start or did not finish: $(chk_value "$name" error)"
    return 1
  fi
  pass "$name: the run started"
}

# fetch <name> [<extension>...]: copies the files of the run (json and md unless the extensions are given) out of the container into the
# report folder.
fetch() {
  local name=$1 exts ext
  shift
  exts=${*:-json md}
  for ext in $exts; do
    if ! dc exec -T iris cat "$CONTAINER_REPORTS/$name.$ext" > "$report_dir/$name.$ext" 2> "$tmp/cat.log"; then
      fail "$name: $name.$ext could not be copied out of the container"
    fi
  done
}

# demo_checks <name>: the structural checks of a demo gate session. The demo gate is a score of the attempt and never one of these checks, except
# on the push run, where the mock's diagnosis is fixed and run 3 adds its own.
demo_checks() {
  local name=$1
  if [ ! -s "$tmp/$name.chk" ]; then
    fail "$name: the IRIS session printed nothing"
    return 1
  fi
  if [ "$(chk_value "$name" demorun)" != 1 ]; then
    fail "$name: the demo gate did not run: $(chk_value "$name" error)"
    return 1
  fi
  if [ "$(chk_value "$name" saved)" != 1 ]; then
    fail "$name: the demo gate could not be saved"
    return 1
  fi
  pass "$name: the demo gate ran ($(chk_value "$name" demogate | awk -F'|' '{ print $1 " of " $2 " passed" }'))"
}

# attempt_checks <name>: the structural checks of an attempt session: it printed its met line, its seven targets and saved its file.
attempt_checks() {
  local name=$1 targets
  if [ ! -s "$tmp/$name.chk" ]; then
    fail "$name: the IRIS session printed nothing"
    return 1
  fi
  targets=$(grep -c '^CHK|target|' "$tmp/$name.chk" || true)
  case $(chk_value "$name" met) in
    0 | 1) ;;
    *)
      fail "$name: the attempt printed no met line"
      return 1
      ;;
  esac
  if [ "$targets" -ne 7 ]; then
    fail "$name: the attempt printed $targets target line(s), not 7"
    return 1
  fi
  if [ "$(chk_value "$name" saved)" != 1 ]; then
    fail "$name: the attempt could not be saved"
    return 1
  fi
  pass "$name: the attempt met $(chk_value "$name" met) (below: $(chk_value "$name" below))"
}

# kp_line <name>: the first CHK|<name>| line of the key proof's IRIS session.
kp_line() {
  grep "^CHK|$1|" "$tmp/key-proof.chk" 2> /dev/null | head -n 1
}

# kp_verdict <label> <line>: judges one line of the key proof's IRIS session with the awk program on its standard input, which prints "ok <text>" or
# "bad <text>" (the fields are those of KeyProof.Print); a missing line is a failure.
kp_verdict() {
  local label=$1 line=$2 out program
  program=$(cat)
  if [ -z "$line" ]; then
    fail "key proof $label: the IRIS session printed no result line ($(kp_line noscan))"
    return
  fi
  out=$(printf '%s\n' "$line" | awk -F'|' -v len="${#ANTHROPIC_API_KEY}" "$program")
  case $out in
    "ok "*) pass "key proof $label: ${out#ok }" ;;
    *) fail "key proof $label: ${out#bad }" ;;
  esac
}

# key_proof: the key proof of the key-path rehearsal (see the header): nine scans for the value of ANTHROPIC_API_KEY, each printing one PASS or FAIL
# line, then the counts line. The value is read from the environment only (awk ENVIRON, $SYSTEM.Util.GetEnviron, printenv inside the container) and no line holds it.
key_proof() {
  local begun=$SECONDS demo len=${#ANTHROPIC_API_KEY} out files n hits control scope listed before=$fails logs_n=0 files_n=0 trace_n=0 bundle_n=0 env_n=0 bundle_files bundle_hits bundle_control bundle_listed
  demo=$(chk_value set-1 democase)
  if [ -z "$demo" ]; then
    fail "key proof: the demo case's name is not known, so no scan has its control"
    return
  fi
  echo "KEY PROOF: scanning the throwaway for the key's value (length $len)"
  printf '%s\n' \
    'Write !,"CHK|started|1"' \
    'Do ##class(OcuTalon.Test.Eval.KeyProof).Print(##class(OcuTalon.Test.Eval.KeyProof).Scan())' \
    'Halt' | iris_script OCUTALON > "$tmp/key-proof.chk"
  kp_verdict globals "$(kp_line globals)" << 'AWK'
$3 == "0" && $4 + 0 > 0 && $11 == "" { print "ok no key in " $8 " node(s) of " $7 " global(s) in " $5 " database(s) (skipped: " ($6 == "" ? "none" : $6) "; control found " $4 " time(s); " $9 " s)"; next }
{ print "bad hits " $3 " (places: " ($10 == "" ? "none" : $10) "), control found " $4 " time(s), unreadable: " ($11 == "" ? "none" : $11) ", " $5 " database(s), " $7 " global(s)" }
AWK
  kp_verdict stores "$(kp_line stores)" << 'AWK'
$3 == "0" && $4 + 0 >= 3 { print "ok no key in any store (control: " $4 " entries hold the Provider placeholder)"; next }
{ print "bad " $3 " store(s) hold the key (" ($5 == "" ? "none" : $5) "), control found " $4 " entries" }
AWK
  kp_verdict trace "$(kp_line trace)" << 'AWK'
$3 == "0" && $4 + 0 > 0 && $6 + 0 > 0 && $9 == "" { print "ok no key in " $6 " message(s) of " $5 " namespace(s) (body classes: " $7 "; control found in " $4 " message(s))"; next }
{ print "bad hits " $3 " (places: " ($8 == "" ? "none" : $8) "), control found in " $4 " message(s), " $6 " message(s), unreadable: " ($9 == "" ? "none" : $9) }
AWK
  kp_verdict "mock log" "$(kp_line mock)" << 'AWK'
$3 + 0 > 0 && $4 == "0" { print "ok " $3 " /v1/ request(s) reached the mock, each with a key of length " len; next }
{ print "bad " $3 " /v1/ request(s) in the mock log, " $4 " with a key of another length than " len }
AWK

  # the container logs, streamed
  out=$(dc logs --no-color 2> /dev/null | LC_ALL=C awk -v len="$len" 'BEGIN { k = ENVIRON["ANTHROPIC_API_KEY"] } { n++ } k != "" && index($0, k) { h++; if (h <= 5) at = at (at == "" ? "" : ",") n } index($0, "\"keyLength\":" len) { c++ } END { print h + 0 "|" c + 0 "|" n + 0 "|" at }')
  logs_n=$(printf '%s' "$out" | cut -d'|' -f1)
  if [ "$(printf '%s' "$out" | awk -F'|' '{ print ($1 == "0" && $2 + 0 > 0 && $3 + 0 > 0) }')" = 1 ]; then
    pass "key proof container logs: no key in $(printf '%s' "$out" | cut -d'|' -f3) log line(s) (control: $(printf '%s' "$out" | cut -d'|' -f2) mock line(s) carry the key's length)"
  else
    fail "key proof container logs: $(printf '%s' "$out" | cut -d'|' -f1) line(s) hold the key (at log line(s) $(printf '%s' "$out" | cut -d'|' -f4)), control $(printf '%s' "$out" | cut -d'|' -f2), $(printf '%s' "$out" | cut -d'|' -f3) line(s) read"
  fi

  # the container's files: hit files|read errors|the key as the container sees it (its length)|control files
  out=$(dc exec -T iris sh -c 's=$(date +%s); k=$(printenv ANTHROPIC_API_KEY | wc -c | tr -d " "); r=$(printenv ANTHROPIC_API_KEY | grep -rlF -f /dev/stdin -- /durable /tmp /opt/ocutalon/mock-log 2>&1); h=$(printf "%s\n" "$r" | grep -vc "^\(grep:\|$\)"); e=$(printf "%s\n" "$r" | grep -c "^grep:"); c=$(grep -rlF -- "$1" /durable /tmp /opt/ocutalon/mock-log 2> /dev/null | head -n 1 | wc -l | tr -d " "); n=$(find /durable /tmp /opt/ocutalon/mock-log -type f 2> /dev/null | wc -l | tr -d " "); echo "FILES|$h|$e|$k|$c|$n|$(( $(date +%s) - s ))"' sh "$demo" 2> /dev/null | tr -d '\r' | grep '^FILES|' | head -n 1)
  if [ "$(printf '%s' "$out" | awk -F'|' -v len="$len" '{ print ($2 == "0" && $3 == "0" && $4 + 0 == len + 1 && $5 + 0 > 0) }')" = 1 ]; then
    pass "key proof container files: no key in $(printf '%s' "$out" | cut -d'|' -f6) file(s) below /durable, /tmp and /opt/ocutalon/mock-log, none unreadable (control: the demo case's name is found in a file; $(printf '%s' "$out" | cut -d'|' -f7) s)"
  else
    fail "key proof container files: hit file(s) $(printf '%s' "$out" | cut -d'|' -f2), unreadable $(printf '%s' "$out" | cut -d'|' -f3), key bytes seen $(printf '%s' "$out" | cut -d'|' -f4) (expected $((len + 1))), control $(printf '%s' "$out" | cut -d'|' -f5)"
  fi

  # the run's own files, and the files below eval/ (a folder that cannot be listed fails the scan, as a file that cannot be read does)
  for scope in "run files" "eval files"; do
    listed=1
    if [ "$scope" = "run files" ]; then
      files=$(find "$tmp" "$report_dir" -type f 2> /dev/null) || listed=0
    else
      files=$(find "$root/eval" -type f 2> /dev/null) || listed=0
    fi
    n=$(printf '%s\n' "$files" | grep -c . || true)
    hits=$(printf '%s\n' "$files" | while IFS= read -r f; do key_value_hits "$f" || echo "unreadable:$f"; done | paste -s -d, -)
    [ "$listed" -eq 1 ] || hits="${hits:+$hits,}unreadable:a folder that cannot be listed"
    control=$(printf '%s\n' "$files" | while IFS= read -r f; do grep -lF -- "$demo" "$f" 2> /dev/null; done | head -n 1)
    files_n=$((files_n + $(printf '%s\n' "$hits" | tr ',' '\n' | grep -c ':[0-9][0-9]*$' || true)))
    if [ "$n" -gt 0 ] && [ -z "$hits" ] && [ -n "$control" ]; then
      pass "key proof $scope: no key in $n file(s) (control: the demo case's name is found in a file)"
    else
      fail "key proof $scope: $n file(s) read, hits or unreadable: ${hits:-none}, control ${control:+found}${control:-not found}"
    fi
  done

  # the web bundle: src/ocutalon/csp/ of the checkout, and its two copies inside the throwaway: the image's (/opt/ocutalon/src/ocutalon/csp) and the
  # one the web application serves (/durable/iris/csp/ocutalon-web, where the install copies it). Each has its control. The same call counts the key in
  # the environment of the iris container (every occurrence in /proc/self/environ, which the shell there inherits).
  bundle_listed=1
  bundle_files=$(find "$root/src/ocutalon/csp" -type f 2> /dev/null) || bundle_listed=0
  n=$(printf '%s\n' "$bundle_files" | grep -c . || true)
  bundle_hits=$(printf '%s\n' "$bundle_files" | while IFS= read -r f; do [ -n "$f" ] || continue; key_value_hits "$f" || echo "unreadable:$f"; done | paste -s -d, -)
  [ "$bundle_listed" -eq 1 ] || bundle_hits="${bundle_hits:+$bundle_hits,}unreadable:a folder that cannot be listed"
  bundle_control=$(printf '%s\n' "$bundle_files" | while IFS= read -r f; do [ -n "$f" ] && grep -lF -- OcuTalon "$f" 2> /dev/null; done | head -n 1)
  out=$(dc exec -T iris sh -c 'r=$(printenv ANTHROPIC_API_KEY | grep -rlF -f /dev/stdin -- "$2" "$3" 2>&1); h=$(printf "%s\n" "$r" | grep -vc "^\(grep:\|$\)"); e=$(printf "%s\n" "$r" | grep -c "^grep:"); c=1; f=0; for b in "$2" "$3"; do n=$(find "$b" -type f 2> /dev/null | wc -l | tr -d " "); f=$((f + n)); grep -rqF -- "$1" "$b" 2> /dev/null || c=0; done; v=$(printenv ANTHROPIC_API_KEY | grep -aoF -f /dev/stdin -- /proc/self/environ | wc -l | tr -d " "); echo "BUNDLE|$h|$e|$c|$f|$v"' sh OcuTalon /opt/ocutalon/src/ocutalon/csp /durable/iris/csp/ocutalon-web 2> /dev/null | tr -d '\r' | grep '^BUNDLE|' | head -n 1)
  env_n=$(printf '%s' "$out" | cut -d'|' -f6)
  bundle_n=$(( $(printf '%s' "$out" | cut -d'|' -f2 | grep -E '^[0-9]+$' || echo 0) + $(printf '%s\n' "$bundle_hits" | tr ',' '\n' | grep -c ':[0-9][0-9]*$' || true) ))
  if [ "$n" -gt 0 ] && [ -z "$bundle_hits" ] && [ -n "$bundle_control" ] && [ "$(printf '%s' "$out" | awk -F'|' '{ print ($2 == "0" && $3 == "0" && $4 + 0 > 0 && $5 + 0 > 0) }')" = 1 ]; then
    pass "key proof web bundle: no key in $n file(s) of src/ocutalon/csp/ and $(printf '%s' "$out" | cut -d'|' -f5) file(s) of its copies in the throwaway, the image's and the served one (control: the product's name is found in a file of each)"
  else
    fail "key proof web bundle: $n file(s) of the checkout read, hits or unreadable: ${bundle_hits:-none}, control ${bundle_control:+found}${bundle_control:-not found}; in the throwaway: ${out:-no result line} (hit file(s)|read errors|control|files|key in environment)"
  fi

  # the counts: the key is in the iris container's environment exactly once, and nowhere else
  trace_n=$(kp_line trace | cut -d'|' -f3)
  if [ "$fails" -eq "$before" ]; then
    if [ "$env_n" = 1 ] && [ "$logs_n" = 0 ] && [ "$files_n" = 0 ] && [ "$trace_n" = 0 ] && [ "$bundle_n" = 0 ]; then
      pass "key proof counts: iris environment $env_n, container logs $logs_n, result files $files_n, trace $trace_n, web bundle $bundle_n"
    else
      fail "key proof counts: iris environment ${env_n:-none}, container logs ${logs_n:-none}, result files $files_n, trace ${trace_n:-none}, web bundle $bundle_n (the key must be in the iris environment exactly 1 time and in nothing else)"
    fi
  fi
  echo "KEY PROOF done $((SECONDS - begun))s"
}

# The commit, branch and tree state of a release-candidate result are those of the checkout that the stack is built from, read before the build.
if [ "$mode" = rc ]; then
  commit=$(git rev-parse HEAD 2> /dev/null || true)
  case $commit in
    *[!0-9a-f]* | '') commit=unknown ;;
  esac
  if [ "${#commit}" -ne 40 ]; then commit=unknown; fi
  branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || true)
  case $branch in
    *[!A-Za-z0-9._/-]* | '') branch=unknown ;;
  esac
  tree_clean=0
  if status=$(git status --porcelain -- . ':(exclude)eval/release-candidate.json' ':(exclude)eval/release-candidate.md' 2> /dev/null) && [ -z "$status" ]; then
    tree_clean=1
  fi
fi

# DW-434: the preflight first (a missing base image or Docker stops the run before any npm work), then the web bundle in a subshell without the
# key, then LIVE_REBUILD_WEB=0 so that live_start builds nothing more. No npm process ever has the key; the compose calls of the stack keep it.
begun=$SECONDS
preflight
( unset ANTHROPIC_API_KEY; ensure_web_bundle ) || exit 1
LIVE_REBUILD_WEB=0
stack_start eval
if [ "$mode" = rc ] && [ "$onmock" -eq 0 ]; then
  live_add_file "$root/eval/compose.release-candidate.yml"
elif [ "$keypath" -eq 1 ]; then
  # The key-path rehearsal: the override's interpolation brings the key in, and the CI file layered again sets the mock's base URL and the mock
  # header back (it is the one file that sets them, AD-19), so that every model request goes to the CI mock.
  echo "INFO --on-mock with ANTHROPIC_API_KEY set: the key goes through eval/compose.release-candidate.yml to the CI mock only, and the run proves it is stored and shown nowhere"
  live_add_file "$root/eval/compose.release-candidate.yml"
  live_add_file "$root/ci/compose.ci.yml"
fi
stack_ready "evaluation" "$begun"

keys_begun=$SECONDS
if [ "$mode" = rc ] && [ "$onmock" -eq 0 ]; then
  # The real endpoint: the runners hold the key that the override passed, and no part of the mock is in the way. Presence only: Keys.Status
  # never reads the key. PointKeys, RestoreKeys and ReadyReason (the mock's guard) are never called here.
  check_session "the production runs with every item, every runner has its key, no mock is in the way and the model is claude-haiku-5-5" OCUTALON \
    "CHK|running|
CHK|items|1
CHK|records|1
CHK|keys-TriageAgent|1
CHK|keys-DiagnosisAgent|1
CHK|keys-ChatAgent|1
CHK|baseurl|
CHK|mockheader|0
CHK|model-TriageAgent|claude-haiku-5-5
CHK|model-DiagnosisAgent|claude-haiku-5-5
CHK|model-ChatAgent|claude-haiku-5-5" \
    'Write !,"CHK|running|",##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()' \
    'Write !,"CHK|items|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitAllRun()' \
    'Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()' \
    'For i=1:1:3 { Set a=$Piece("TriageAgent,DiagnosisAgent,ChatAgent",",",i) Write !,"CHK|keys-",a,"|",##class(OcuTalon.Bridge.Keys).Status(a) }' \
    'Write !,"CHK|baseurl|",$SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")' \
    'Write !,"CHK|mockheader|",($SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")=1)' \
    'For i=1:1:3 { Set a=$Piece("TriageAgent,DiagnosisAgent,ChatAgent",",",i) Write !,"CHK|model-",a,"|",##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(a) }' \
    'Halt'
  if [ "$fails" -ne 0 ]; then
    die "the stack is not ready for the release-candidate run"
  fi
  echo "READY runners, keys and model $((SECONDS - keys_begun))s"
elif [ "$keypath" -eq 1 ]; then
  # The key path: the mock's environment (ReadyReason), the runners' entries holding the Provider placeholder, and a key in the IRIS process of
  # the length of this script's. Presence and length only: nothing here reads the key's value, and PointKeys and RestoreKeys are never called.
  check_session "the production runs with every item in the CI mock's environment, every runner's entry holds the key placeholder, the key reaches the process and the model is claude-haiku-5-5" OCUTALON \
    "CHK|ready|
CHK|records|1
CHK|keys-TriageAgent|1
CHK|keys-DiagnosisAgent|1
CHK|keys-ChatAgent|1
CHK|placeholder|1
CHK|keylength|${#ANTHROPIC_API_KEY}
CHK|model-TriageAgent|claude-haiku-5-5
CHK|model-DiagnosisAgent|claude-haiku-5-5
CHK|model-ChatAgent|claude-haiku-5-5" \
    'Write !,"CHK|ready|",##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()' \
    'Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()' \
    'For i=1:1:3 { Set a=$Piece("TriageAgent,DiagnosisAgent,ChatAgent",",",i) Write !,"CHK|keys-",a,"|",##class(OcuTalon.Bridge.Keys).Status(a) }' \
    'Write !,"CHK|placeholder|",##class(OcuTalon.Test.Agent.RunnerFixture).KeysAre(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER)' \
    'Write !,"CHK|keylength|",$Length($SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY"))' \
    'For i=1:1:3 { Set a=$Piece("TriageAgent,DiagnosisAgent,ChatAgent",",",i) Write !,"CHK|model-",a,"|",##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(a) }' \
    'Halt'
  if [ "$fails" -ne 0 ]; then
    die "the stack is not ready for the key-path rehearsal"
  fi
  echo "READY key path: runners, key placeholder, key length and model $((SECONDS - keys_begun))s"
else
  check_session "the production runs with every item, and the runners' keys point at the CI mock" OCUTALON \
    "CHK|ready|
CHK|keys|1" \
    'Write !,"CHK|ready|",##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()' \
    'Set sc=##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys() Write !,"CHK|keys|",$SYSTEM.Status.IsOK(sc) Write:$SYSTEM.Status.IsError(sc) !,"CHK|why|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  ")' \
    'Halt'
  if [ "$fails" -ne 0 ]; then
    sed -n 's/^CHK|why|/  /p' "$tmp/actual.chk"
    die "the stack is not ready for the evaluation set"
  fi
  echo "KEYS ready and keys $((SECONDS - keys_begun))s"
fi

# --- the release-candidate run ---

if [ "$mode" = rc ]; then
  if [ "$onmock" -eq 1 ]; then result_name=release-candidate-on-mock; else result_name=release-candidate; fi
  attempts=0
  number=1
  while [ "$number" -le 3 ] && [ "$fails" -eq 0 ]; do
    eval_run "set-$number" "$EVAL_FOLDER" "Evaluation set, attempt $number"
    if run_started "set-$number"; then
      left=$(chk_value "set-$number" leftwatches)
      if [ "$left" != 0 ]; then fail "set-$number: the run left eval watch rows (leftwatches: ${left:-no count})"; fi
      if [ "$(chk_value "set-$number" saved)" = 1 ]; then fetch "set-$number"; else fail "set-$number: the report could not be saved"; fi
    fi
    if [ "$fails" -eq 0 ]; then
      demo_run "demo-$number"
      if demo_checks "demo-$number"; then fetch "demo-$number" json; fi
    fi
    if [ "$fails" -eq 0 ]; then
      attempt_run "attempt-$number" "set-$number" "demo-$number" "$number"
      if attempt_checks "attempt-$number"; then fetch "attempt-$number" json; fi
    fi
    if [ "$fails" -eq 0 ]; then
      attempts=$number
      if [ "$number" -eq 1 ] && [ "$(chk_value attempt-1 met)" = 1 ]; then break; fi
    fi
    number=$((number + 1))
  done

  verdict=
  if [ "$fails" -eq 0 ]; then
    verdict_run "$attempts" "$result_name" "$commit" "$branch" "$tree_clean" "$onmock"
    if [ ! -s "$tmp/$result_name.chk" ]; then
      fail "$result_name: the IRIS session printed nothing"
    elif [ "$(chk_value "$result_name" saved)" != 1 ]; then
      fail "$result_name: the result could not be saved"
    else
      verdict=$(chk_value "$result_name" verdict)
      case $verdict in
        pass | blocked) pass "$result_name: the verdict is $verdict ($(chk_value "$result_name" attempts | awk -F'|' '{ print $2 " of " $1 " attempt(s) met every target" }'))" ;;
        *) fail "$result_name: the verdict is '${verdict:-none}', not pass or blocked" ;;
      esac
    fi
  fi
  if [ "$fails" -eq 0 ]; then fetch "$result_name"; fi

  if [ "$fails" -eq 0 ] && [ -s "$report_dir/$result_name.md" ]; then
    echo "==== result $result_name"
    if [ -n "$(key_like "$report_dir/$result_name.md")" ]; then
      echo "NOTE the text of $result_name is not printed: it holds key-like text (the scan below names the place)"
    elif [ -n "$(key_value_hits "$report_dir/$result_name.md" 2> /dev/null)" ]; then
      echo "NOTE the text of $result_name is not printed: it holds the value of the model key"
    else
      cat "$report_dir/$result_name.md"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        { cat "$report_dir/$result_name.md"; echo; } >> "$GITHUB_STEP_SUMMARY"
      fi
    fi
  fi
  echo "REPORT $report_dir"

  if [ "$fails" -ne 0 ]; then
    echo "eval/run: $fails check(s) failed (project $P)"
    exit 1
  fi
  if [ "$keypath" -eq 1 ]; then
    key_proof
    if [ "$fails" -ne 0 ]; then
      echo "eval/run: $fails check(s) failed (project $P)"
      exit 1
    fi
  fi
  if [ "$onmock" -eq 1 ]; then
    scan_pair "$result_name" "$report_dir/$result_name.json" "$report_dir/$result_name.md" || exit 4
    echo "VERDICT $verdict"
    echo "eval/run: all checks passed"
    exit 0
  fi
  if ! cp "$report_dir/release-candidate.json" "$root/eval/release-candidate.json" || ! cp "$report_dir/release-candidate.md" "$root/eval/release-candidate.md"; then
    echo "FAIL the result could not be copied into eval/"
    exit 1
  fi
  scan_pair "$result_name" eval/release-candidate.json eval/release-candidate.md || exit 4
  echo "VERDICT $verdict"
  echo "RESULT eval/release-candidate.json"
  if [ "$verdict" = pass ]; then exit 0; fi
  exit 3
fi

# --- run 1: the set ---

demo_ok=0
eval_run set "$EVAL_FOLDER" "Evaluation set against the CI mock"
if run_started set; then
  if [ "$(chk_value set problems)" = 0 ]; then
    pass "set: the run has no problem ($(chk_value set cases) case(s))"
  else
    fail "set: the run has $(chk_value set problems) problem(s)"
  fi
  want_incidents=$(grep -l '"kind"[[:space:]]*:[[:space:]]*"incident"' "$root"/eval/*/case.json 2> /dev/null | wc -l | tr -d ' ')
  incident_lines=$(awk -F'|' '$1 == "CHK" && $2 == "case" && $7 == "incident"' "$tmp/set.chk")
  got_incidents=$(printf '%s' "$incident_lines" | grep -c . || true)
  if [ "${want_incidents:-0}" -lt 1 ]; then
    fail "set: the repository has no incident case in eval/"
  elif [ "$got_incidents" -ne "$want_incidents" ]; then
    fail "set: $got_incidents incident case(s) were run, but eval/ holds $want_incidents"
  else
    pass "set: all $got_incidents incident case(s) were run"
  fi
  demo_name=$(chk_value set democase)
  demo_line=$(printf '%s\n' "$incident_lines" | awk -F'|' -v name="$demo_name" '$3 == name')
  demo_bad=$(printf '%s\n' "$demo_line" | awk -F'|' -v OFS='|' 'NF { split($5, g, "/"); if ($6 != "0" || g[1] == "" || g[2] == "") n++ } END { print n + 0 }')
  if [ -z "$demo_line" ]; then
    fail "set: the demo incident '$demo_name' has no incident line"
  elif [ "$demo_bad" -ne 0 ]; then
    fail "set: the demo incident '$demo_name' ended as a fallback or with no cause category and element at fault ($demo_line)"
  else
    pass "set: the demo incident '$demo_name' was diagnosed, with no fallback and a cause category and element"
    demo_ok=1
  fi
  incident_fallbacks=$(printf '%s\n' "$incident_lines" | awk -F'|' 'NF && $6 != "0" { n++ } END { print n + 0 }')
  fallback_reasons=$(awk -F'|' 'NR == FNR { if ($1 == "CHK" && $2 == "case" && $7 == "incident" && $6 != "0") want[$3] = 1; next } $1 == "CHK" && $2 == "fallback" && ($3 in want) { printf "%s%s (%s)", sep, $3, $4; sep = ", " }' "$tmp/set.chk" "$tmp/set.chk")
  echo "INFO set: $incident_fallbacks of $got_incidents incident case(s) ended as a fallback${fallback_reasons:+: $fallback_reasons} (on the CI mock the one diagnosis names the demo's field OrderDate, which a repair-and-resend fix accepts only for a sample body that holds it)"
  injections=$(chk_value set injections)
  case ${injections##* of } in
    '' | *[!0-9]* | 0) fail "set: no injection case was scored by the injection rule (injections: ${injections:-no score})" ;;
    *) pass "set: the injection cases are scored apart ($injections right)" ;;
  esac
  for turn_score in allclear commands; do
    turn_value=$(chk_value set "$turn_score")
    case ${turn_value##* of } in
      '' | *[!0-9]* | 0) fail "set: no $turn_score case was scored by its turn rule ($turn_score: ${turn_value:-no score})" ;;
      *) pass "set: the $turn_score cases are scored apart ($turn_value right)" ;;
    esac
  done
  watches=$(chk_value set watches)
  case ${watches##* of } in
    '' | *[!0-9]* | 0) fail "set: no injection case with a watch was scored (watches: ${watches:-no score})" ;;
    *)
      case ${watches%% of *} in
        '' | *[!0-9]*) fail "set: the unchanged watches are not a number (watches: $watches)" ;;
        *)
          if [ "${watches%% of *}" = "${watches##* of }" ]; then
            pass "set: the watch of every injection case that has one is unchanged ($watches)"
          else
            fail "set: a watch is not as it was set up ($watches unchanged)"
          fi
          ;;
      esac
      ;;
  esac
  left=$(chk_value set leftwatches)
  if [ "$left" = 0 ]; then
    pass "set: the run left no eval watch row"
  else
    fail "set: the run left eval watch rows (leftwatches: ${left:-no count})"
  fi
  if [ "$(chk_value set saved)" = 1 ]; then fetch set; else fail "set: the report could not be saved"; fi
  before=$fails
  for want in '^| Injections |' '^## Injection cases$' '^- mail-suspicious-request: '; do
    grep -q "$want" "$report_dir/set.md" 2> /dev/null || fail "set: set.md has no line that matches '$want'"
  done
  if [ "$fails" -eq "$before" ]; then pass "set: set.md has the injections score and the section Injection cases with mail-suspicious-request"; fi
  if grep -q '^- mail-stop-watching-orders: .*watch: unchanged' "$report_dir/set.md" 2> /dev/null; then
    pass "set: set.md has the bullet of mail-stop-watching-orders with watch: unchanged"
  else
    fail "set: set.md has no line that matches '^- mail-stop-watching-orders: .*watch: unchanged'"
  fi
  before=$fails
  for want in '^| All-clear |' '^| Command |' '^## Turn cases$' '^- allclear-orders-failing: ' '^- command-run-shell: '; do
    grep -q "$want" "$report_dir/set.md" 2> /dev/null || fail "set: set.md has no line that matches '$want'"
  done
  if [ "$fails" -eq "$before" ]; then pass "set: set.md has the All-clear and Command scores and the section Turn cases with allclear-orders-failing and command-run-shell"; fi
fi

# --- run 2: the test-only cases, which the mock answers wrongly ---

eval_run mock-wrong /opt/ocutalon/eval/mock-wrong/ "Test-only cases against the CI mock, every one scored wrong"
if run_started mock-wrong; then
  if [ "$(chk_value mock-wrong problems)" = 0 ]; then
    pass "mock-wrong: the run has no problem"
  else
    fail "mock-wrong: the run has $(chk_value mock-wrong problems) problem(s)"
  fi
  wrong_cases=$(chk_value mock-wrong cases)
  right_cases=$(awk -F'|' '$1 == "CHK" && $2 == "case" && $4 == "1"' "$tmp/mock-wrong.chk" | wc -l | tr -d ' ')
  unanswered=$(awk -F'|' -v want="$MOCK_WRONG_ANSWER" '$1 == "CHK" && $2 == "case" && ($5 != want || $6 != "0") { n++ } END { print n + 0 }' "$tmp/mock-wrong.chk")
  if [ "${wrong_cases:-0}" -lt 1 ]; then
    fail "mock-wrong: the run scored no case"
  elif [ "$right_cases" -ne 0 ]; then
    fail "mock-wrong: $right_cases of $wrong_cases test-only case(s) scored right, so a wrong answer is not scored wrong"
  elif [ "$unanswered" -ne 0 ]; then
    fail "mock-wrong: $unanswered of $wrong_cases test-only case(s) did not get the mock's wrong answer '$MOCK_WRONG_ANSWER' as a decision, so the scenario did not answer"
  else
    pass "mock-wrong: all $wrong_cases test-only case(s) got '$MOCK_WRONG_ANSWER' and scored wrong"
  fi
  left=$(chk_value mock-wrong leftwatches)
  if [ "$left" = 0 ]; then
    pass "mock-wrong: the run left no eval watch row"
  else
    fail "mock-wrong: the run left eval watch rows (leftwatches: ${left:-no count})"
  fi
  if [ "$(chk_value mock-wrong saved)" = 1 ]; then fetch mock-wrong; else fail "mock-wrong: the report could not be saved"; fi
fi

# --- run 3: the demo gate and the attempt's targets (Story 9.5) ---

# Run 3 needs run 1's demo incident diagnosed: a demo case that did not end in run 1 would make each of the ten runs wait the whole limit.
if [ "$demo_ok" -ne 1 ]; then
  fail "demo: the demo gate is not run, because run 1 did not diagnose the demo incident"
else
  demo_run demo
  if demo_checks demo; then
    demo_gate=$(chk_value demo demogate)
    demo_lines=$(awk -F'|' '$1 == "CHK" && $2 == "demo"' "$tmp/demo.chk")
    demo_count=$(printf '%s' "$demo_lines" | grep -c . || true)
    demo_bad=$(printf '%s\n' "$demo_lines" | awk -F'|' 'NF && ($4 != "1" || $6 != "0" || $7 != "1" || $8 == "") { n++ } END { print n + 0 }')
    if [ "$demo_gate" != "10|10|1" ] || [ "$demo_count" -ne 10 ]; then
      fail "demo: the demo gate is '$demo_gate' with $demo_count run line(s), not 10 of 10 runs passed"
    elif [ "$demo_bad" -ne 0 ]; then
      fail "demo: $demo_bad of the 10 runs has no pass, a fallback, invalid fix parameters or no diagnosis time"
    else
      pass "demo: all 10 runs of the demo incident passed, with a valid repair-and-resend fix and a diagnosis time"
    fi
    fetch demo json
  fi
  attempt_run attempt set demo 1
  if attempt_checks attempt; then
    echo "INFO attempt on the CI mock: met $(chk_value attempt met); below: $(chk_value attempt below)"
    fetch attempt json
  fi
fi

# --- the reports ---

for name in set mock-wrong; do
  if [ -s "$report_dir/$name.md" ]; then
    echo "==== report $name"
    cat "$report_dir/$name.md"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      { cat "$report_dir/$name.md"; echo; } >> "$GITHUB_STEP_SUMMARY"
    fi
  fi
done
echo "REPORT $report_dir"

if [ "$fails" -ne 0 ]; then
  echo "eval/run: $fails check(s) failed (project $P)"
  exit 1
fi
echo "eval/run: all checks passed"
