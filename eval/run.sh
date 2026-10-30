#!/usr/bin/env bash
# The evaluation run against the CI mock (Stories 9.2, 9.3, 9.7 and 9.8; AD-22, AD-29, AD-30; CON-3). It is the script of the evaluation job of
# .github/workflows/lane-a.yml and runs the same way on a developer machine:
#   OCUTALON_RUN_TAG=<tag> bash eval/run.sh
# It sources ci/iris.sh (which sources ci/units.sh and docker/tests/lib-live.sh), starts a throwaway of its own with the CI override and
# its model mock, and reaches the container only through the functions of those files (stack_start, stack_ready, check_session,
# iris_script, dc exec). It never pulls the base image, never runs warm, and its exit trap removes its project, its volume and its
# lock. It exports OCUTALON_EVAL=1 for its own process only: that switch enables EvalIn in this throwaway, and no workflow, compose
# file or class default sets it (owner condition U-131).
# Variables:
#   OCUTALON_RUN_TAG          the run tag of ci/iris.sh (default local-<epoch>-<pid>)
#   OCUTALON_EVAL_WAIT        the seconds each run may take, after it has sent its cases, to have every case decided: a whole number
#                             from 1 to 3600 (default 180); anything else exits 2. The turn cases are decided while they are sent (each
#                             ask waits up to EvalIn's TURNWAIT, and a Busy turn is asked again), so this wait does not bound them
#   OCUTALON_EVAL_REPORT_DIR  the folder that receives the report files (default: a new folder from mktemp -d below
#                             ${RUNNER_TEMP:-${TMPDIR:-/tmp}})
# The steps:
#   1. the throwaway starts and the production runs with every item (RunnerFixture.ReadyReason() is empty); the runners' keys are
#      pointed at the mock with RunnerFixture.PointKeys(), as the live units do;
#   2. run 1, the set: OcuTalon.Eval.Report.Run over /opt/ocutalon/eval/, saved in the container as set.json and set.md;
#   3. run 2, the test-only cases of eval/mock-wrong/, which the mock answers wrongly on purpose: saved as mock-wrong.json and
#      mock-wrong.md. Both runs print a first CHK line before they call Report.Run, because iris_script runs a session again when it
#      printed no CHK line, and that early line keeps it from starting a second run;
#   4. the four files are copied out into the report folder, both Markdown texts are printed and appended to $GITHUB_STEP_SUMMARY when
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
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

limit=${OCUTALON_EVAL_WAIT:-180}
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

# fetch <name>: copies the report files of the run out of the container into the report folder.
fetch() {
  local name=$1 ext
  for ext in json md; do
    if ! dc exec -T iris cat "$CONTAINER_REPORTS/$name.$ext" > "$report_dir/$name.$ext" 2> "$tmp/cat.log"; then
      fail "$name: $name.$ext could not be copied out of the container"
    fi
  done
}

begun=$SECONDS
stack_start eval
stack_ready "evaluation" "$begun"

keys_begun=$SECONDS
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

# --- run 1: the set ---

eval_run set /opt/ocutalon/eval/ "Evaluation set against the CI mock"
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
