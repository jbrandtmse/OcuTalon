#!/usr/bin/env bash
# Hermetic test of ci/changes.sh (Story 0.7, matrix rows 9 to 12; Story 32.2): the classifier and the comparison base that decide
# which jobs skip their steps, and the decision of each IRIS group. It runs the script on synthetic repositories with fake answers
# of the runs API (OCUTALON_CI_RUNS_FILE), a push payload of its own (GITHUB_EVENT_PATH) and a file of changed paths
# (--paths-from); it starts nothing and reaches no network. Every call sets GITHUB_EVENT_PATH itself, so the payload of the job
# that runs this test never leaks in.
#   - row 9, the web classifier: web is true for each web input and false for other paths, so a change to DESIGN.md runs web;
#   - the group classifier: the script of each live unit (group_units) runs exactly its own group; the web-only set runs every group
#     but production; a change to ci/ or the workflow runs all six, and each product source is claimed by a pattern; each declared
#     non-input and each bookkeeping path runs no group; a path that nothing claims or declares runs all six, naming the path;
#   - row 10, the base: the first commit of the history with a green push run (HEAD itself on a re-run of a green run); no
#     base, web true and every group running, on a pull request, with no run, with no green run in the history, with a run that is not
#     a push, and when the answer cannot be read or holds no run list;
#   - row 11, red and then bookkeeping: C0 green, C1 code and red, B1 bookkeeping only: B1's base is C0, so B1 runs the red
#     commit's groups again and no other;
#   - a push to main (Story 0.8, REL-2): no base, web true and every group running with a reason that names main, although a green
#     base and only bookkeeping changed; every call of the script sets GITHUB_REF itself, so the ref of the job that runs this test
#     never leaks in;
#   - the push payload: a force push (forced, a before that is not an ancestor of HEAD, a before that is unknown), a payload that
#     is missing, not JSON or without a boolean forced or a 40-hex before, and a paths file that cannot be read, each run every group;
#   - row 12, the outputs: base, web, reason and, with --group, run are appended to $GITHUB_OUTPUT, with the full base in the skip
#     reason, and the GROUP lines are printed only; an output file that cannot be written fails the script; a bad group exits 2.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
changes="$root/ci/changes.sh"
. "$root/ci/units.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cc.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

repo="$tmp/repo"
git init -q "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# commit <message> <path>...: changes each path and commits; sets $sha.
n=0
commit() {
  local message=$1 path
  shift
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    n=$((n + 1))
    echo "change $n" >> "$repo/$path"
    g add -A
  done
  g commit -q -m "$message"
  sha=$(g rev-parse HEAD)
}

# runs <file> <conclusion:sha[:event]>...: a runs API answer.
runs() {
  local file=$1
  shift
  jq -n --args '{workflow_runs: [$ARGS.positional[] | split(":") | {conclusion: .[0], head_sha: .[1], event: (.[2] // "push")}]}' "$@" > "$file"
}

# The ref of the push that classify simulates: a feature branch, so that no case depends on the environment's GITHUB_REF.
classify_ref=refs/heads/OCT-epic0

# The payload of a push to a new ref that is not forced. push_event holds it for the calls that name GITHUB_EVENT_PATH themselves;
# classify_payload is the payload text of classify: "-" leaves GITHUB_EVENT_PATH unset and "@<path>" names that path.
zeros=0000000000000000000000000000000000000000
default_payload='{"forced": false, "before": "'$zeros'"}'
classify_payload=$default_payload
push_event="$tmp/push-event.json"
printf '%s\n' "$default_payload" > "$push_event"

# classify <runs file or -> <event> [extra arguments]: runs the script in the repository; the outputs are in out_*, the groups
# that ran in out_ran (space separated, in matrix order) and the number of GROUP lines in out_lines.
classify() {
  local runs_file=$1 event=$2 event_path="$tmp/event.json"
  shift 2
  case $classify_payload in
    -) event_path="" ;;
    @*) event_path=${classify_payload#@} ;;
    *) printf '%s\n' "$classify_payload" > "$event_path" ;;
  esac
  : > "$tmp/github-output"
  (
    cd "$repo" || exit 1
    if [ -n "$event_path" ]; then export GITHUB_EVENT_PATH=$event_path; else unset GITHUB_EVENT_PATH; fi
    GITHUB_EVENT_NAME=$event GITHUB_REF=$classify_ref GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$tmp/github-output" \
      OCUTALON_CI_RUNS_FILE=$runs_file bash "$changes" ci.yml "$@"
  ) > "$tmp/stdout" 2> "$tmp/stderr"
  rc=$?
  out_base=$(sed -n 's/^base=//p' "$tmp/stdout")
  out_web=$(sed -n 's/^web=//p' "$tmp/stdout")
  out_run=$(sed -n 's/^run=//p' "$tmp/stdout")
  out_reason=$(sed -n 's/^reason=//p' "$tmp/stdout")
  out_ran=$(sed -n 's/^GROUP \([^ ]*\) run=true: .*/\1/p' "$tmp/stdout" | tr '\n' ' ' | sed 's/ $//')
  out_lines=$(grep -c '^GROUP ' "$tmp/stdout")
}

# sorted <names>: the names one per line in name order, as one line.
sorted() { printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

# expect <label> <base> <web> <groups that ran: all, none or names>
expect() {
  local want=$4 ran
  case $want in
    all) want=$IRIS_GROUPS ;;
    none) want="" ;;
  esac
  want=$(sorted $want)
  ran=$(sorted $out_ran)
  if [ "$rc" -eq 0 ] && [ "$out_base" = "$2" ] && [ "$out_web" = "$3" ] && [ "$ran" = "$want" ] && [ "$out_lines" = 6 ]; then
    pass "$1"
  else
    fail "$1 (rc=$rc base='$out_base' web='$out_web', groups that ran '$ran' of $out_lines GROUP lines, wanted base='$2' web='$3' groups '$want'; $out_reason)"
  fi
}

commit "c0" README.md web/package.json
c0=$sha
runs "$tmp/green-c0.json" "success:$c0"

# --- row 9: the classifier, with the paths given ---

# The groups that a web change runs: every group but production, whose units never check the built web bundle.
web_groups="install-fresh install-upgrade browser shards image"

paths_case() { # paths_case <label> <web> <groups that run: all, none or names> <path>...
  local label=$1 web=$2 groups=$3 f="$tmp/paths.txt"
  shift 3
  printf '%s\n' "$@" > "$f"
  classify "$tmp/green-c0.json" push --paths-from "$f"
  expect "classifier: $label" "$c0" "$web" "$groups"
}

# claimed_case <label> <web> <path>: every group runs because its own pattern claims the path, not through the unclassified fallback.
claimed_case() {
  local grp unclaimed=""
  paths_case "$1" "$2" all "$3"
  for grp in $IRIS_GROUPS; do
    grep -qx "GROUP $grp run=true: 1 input path(s) of $grp changed since $c0" "$tmp/stdout" || unclaimed="$unclaimed $grp"
  done
  if [ -z "$unclaimed" ]; then pass "classifier: $1: claimed by the pattern of each group"; else fail "classifier: $1: not claimed by the pattern of$unclaimed"; fi
}

# unclassified_case <label> <web> <first path> <path>...: every group runs, and its reason names the unclassified path.
unclassified_case() {
  local label=$1 web=$2 first=$3 grp unnamed=""
  shift 3
  paths_case "$label" "$web" all "$@"
  for grp in $IRIS_GROUPS; do
    grep -q "^GROUP $grp run=true: [0-9]* unclassified path(s) changed since $c0, the first $first: every group runs\$" "$tmp/stdout" || unnamed="$unnamed $grp"
  done
  if [ -z "$unnamed" ]; then pass "classifier: $label: the reason of each group names the unclassified path"; else fail "classifier: $label: the reason of$unnamed does not name $first"; fi
}

# The script of each live unit runs exactly the group that holds the unit, and no other group.
for grp in $IRIS_GROUPS; do
  for unit in $(group_units "$grp"); do
    case $unit in
      live:*) paths_case "the script of $unit runs only $grp" false "$grp" "docker/tests/test-${unit#live:}.sh" ;;
    esac
  done
done

# The web inputs: web runs, and so does every group but production.
paths_case "web/** runs web and every group but production" true "$web_groups" web/src/app/app.ts
paths_case "the web-only set runs web and every group but production" true "$web_groups" web/src/app/app.ts logo/web/x.png _bmad-output/planning-artifacts/ux-designs/DESIGN.md web/e2e/demo-path/01-page.spec.ts
paths_case "the UX design documents run web and the web groups (DESIGN.md is not bookkeeping)" true "$web_groups" _bmad-output/planning-artifacts/ux-designs/DESIGN.md
paths_case "logo/** runs web and the web groups" true "$web_groups" logo/mark.svg
paths_case "a web change next to documentation runs the web groups" true "$web_groups" web/src/app/app.ts docs/guide.md
paths_case "the Live payload classes run web and every group (src/)" true all src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls
paths_case "the generated sign-in assets run web and every group (src/)" true all src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls
paths_case "an agent class runs web and every group (the mock's tests read its MOCKKEY)" true all src/ocutalon/cls/OcuTalon/Agent/Chat.cls
paths_case "the tool names run web and every group (the mock's tests read them)" true all src/ocutalon/cls/OcuTalon/Tools/Names.cls
paths_case "the compaction prompt runs web and every group (the mock's tests read its PREFIX)" true all src/bridge/cls/OcuTalon/Bridge/Compaction.cls
paths_case "a bridge example class runs web and every group (the mock's tests read its MOCKKEY)" true all src/bridge/cls/OcuTalon/BridgeExample/Agent/Echo.cls
paths_case "another tools class runs every group, not web" false all src/ocutalon/cls/OcuTalon/Tools/Result.cls
paths_case "another public class runs every group, not web" false all src/ocutalon/cls/OcuTalon/Web/Public/Status.cls
paths_case "a test class runs every group, shards among them" false all src/ocutalon/cls/OcuTalon/Test/Core/X.cls

# The CI recipe and the workflow are inputs of every group.
claimed_case "ci/units.sh" true ci/units.sh
claimed_case "ci/changes.sh" true ci/changes.sh
claimed_case "ci/iris.sh" true ci/iris.sh
claimed_case "a mock scenario (ci/**)" true ci/mock/scenarios/A/x.json
claimed_case "the workflow" true .github/workflows/ci.yml
claimed_case "the root .gitignore (the web build's clean checkout depends on it)" true .gitignore
claimed_case "the root .gitattributes" true .gitattributes

# Each product source is claimed by a pattern of every group, the browser group among them.
claimed_case "src/bridge" false src/bridge/cls/OcuTalon/Bridge/Other.cls
claimed_case "src/cpf" false src/cpf/x.cpf
claimed_case "src/module.xml" false src/module.xml
claimed_case "docker/Dockerfile" false docker/Dockerfile
claimed_case "docker/merge.cpf" false docker/merge.cpf
claimed_case "docker/after-start.cos" false docker/after-start.cos
claimed_case "docker/ipm/**" false docker/ipm/x.xml
claimed_case "docker-compose.yml" false docker-compose.yml
claimed_case "docker-compose.dev.yml" false docker-compose.dev.yml
claimed_case ".dockerignore" false .dockerignore
claimed_case "eval/**" false eval/x.json
claimed_case "a live test helper (docker/tests/lib-live.sh)" false docker/tests/lib-live.sh
claimed_case "the throwaway compose file" false docker/tests/compose.throwaway.yml

# A path that no unit reads runs no group, whatever the web job does with it.
paths_case "the web build script runs web, and no group" true none docker/tests/test-web-build.sh
paths_case "the mock's test script runs web, and no group" true none docker/tests/test-mock.sh
paths_case "a check script runs no group" false none docker/tests/test-boundaries.sh
paths_case "a .gitignore below the root runs no group (docs/)" false none docs/.gitignore
paths_case "the second workflow runs no group" false none .github/workflows/lane-a.yml
paths_case "docs runs no group" false none docs/guide.md docs/x.md
paths_case "release runs no group" false none release/x.sh
paths_case "the README runs no group" false none README.md
paths_case "CLAUDE.md runs no group" false none CLAUDE.md
paths_case "the agent settings run no group" false none .claude/settings.json
paths_case "the example environment runs no group" false none .env.example
paths_case "the manual recording tool runs no group" false none docker/tests/record-eval.sh
paths_case "the licence and notice files run no group" false none LICENSE NOTICE LICENSE-THIRD-PARTY.txt
paths_case "a live script next to documentation runs only its group" false production docker/tests/test-production.sh docs/x.md

# Bookkeeping runs no group; the UX design documents are not bookkeeping.
paths_case "_bmad/ alone is bookkeeping" false none _bmad/custom/skill-rules.md
paths_case "_bmad-output/ alone, outside the design documents, is bookkeeping" false none _bmad-output/implementation-artifacts/sprint-status.yaml _bmad-output/planning-artifacts/epics.md
paths_case "bookkeeping with one code path runs every group" false all _bmad/custom/parallel.yaml docker/after-start.sh
paths_case "no path at all runs no group" false none

# A path that nothing claims and nothing declares runs every group.
unclassified_case "a new top-level folder" false newdir/x.txt newdir/x.txt
unclassified_case "a top-level script" false install.sh install.sh
unclassified_case "a script in an unknown docker folder" false docker/other/x.sh docker/other/x.sh
unclassified_case "a helper script in docker/tests" false docker/tests/helper.sh docker/tests/helper.sh
unclassified_case "an unclassified path among declared ones" false newdir/x.txt docs/guide.md _bmad/custom/parallel.yaml newdir/x.txt release/x.sh
unclassified_case "an unclassified path next to a claimed one" false newdir/x.txt docker/tests/test-production.sh newdir/x.txt

# --- row 10: the base ---

commit "c1 code" docker/Dockerfile
c1=$sha
commit "c2 code" src/module.xml
c2=$sha
runs "$tmp/green-c1.json" "success:$c1" "success:$c0"
classify "$tmp/green-c1.json" push
expect "base: the newest green commit of the history, not an older one" "$c1" false all
if [ -n "$out_reason" ] && printf '%s\n' "$out_reason" | grep -q "$(printf '%.12s' "$c1")"; then
  pass "skip line: the reason names the base"
else
  fail "skip line: the reason '$out_reason' does not name the base"
fi
runs "$tmp/green-c0-only.json" "success:$c0"
classify "$tmp/green-c0-only.json" push
expect "base: an older green commit, the diff since it holds code" "$c0" false all

runs "$tmp/mixed.json" "failure:$c2" "success:$c0"
classify "$tmp/mixed.json" push
expect "base: a red run is never a base" "$c0" false all

runs "$tmp/green-head.json" "success:$c2" "success:$c0"
classify "$tmp/green-head.json" push
expect "base: a re-run of a green HEAD has itself as the base, and nothing changed, so no group runs" "$c2" false none

classify "$tmp/green-c1.json" pull_request
expect "base: a pull request has no base and runs everything" "" true all
if printf '%s\n' "$out_reason" | grep -q 'pull_request'; then pass "pull request: the reason names the event"; else fail "pull request: the reason '$out_reason' does not name the event"; fi

echo '{"workflow_runs":[]}' > "$tmp/none.json"
classify "$tmp/none.json" push
expect "base: with no run there is no base and everything runs" "" true all

runs "$tmp/elsewhere.json" "success:0000000000000000000000000000000000000001"
classify "$tmp/elsewhere.json" push
expect "base: a green commit outside HEAD's history is no base" "" true all

runs "$tmp/pr-run.json" "success:$c1:pull_request"
classify "$tmp/pr-run.json" push
expect "base: a green run that was not a push is no base" "" true all

classify "$tmp/does-not-exist.json" push
expect "base: an answer that cannot be read fails open" "" true all
echo '{"message":"Bad credentials"}' > "$tmp/bad.json"
classify "$tmp/bad.json" push
expect "base: an answer with no run list fails open" "" true all
echo 'not json' > "$tmp/garbage.json"
classify "$tmp/garbage.json" push
expect "base: an answer that is not JSON fails open" "" true all

# --- row 11: red, then bookkeeping ---

commit "c3 code, red" web/src/app/app.ts
c3=$sha
commit "b1 bookkeeping only" _bmad-output/implementation-artifacts/sprint-status.yaml
b1=$sha
runs "$tmp/green-c2.json" "success:$c2"
classify "$tmp/green-c2.json" push
expect "red then bookkeeping: B1's base is the last green commit, so B1 runs the red commit's web groups again" "$c2" true "$web_groups"

commit "b2 bookkeeping only" _bmad/custom/parallel.yaml
runs "$tmp/green-b1.json" "success:$b1" "success:$c2"
classify "$tmp/green-b1.json" push
expect "bookkeeping after a green bookkeeping commit: nothing changed that matters, so web and every group skip" "$b1" false none

# --- a push to main runs everything (REL-2), whatever a green run says ---

classify_ref=refs/heads/main
classify "$tmp/green-b1.json" push
expect "push to main: with a green base and only bookkeeping changed, no base and everything runs" "" true all
if printf '%s\n' "$out_reason" | grep -q 'main'; then pass "push to main: the reason names main"; else fail "push to main: the reason '$out_reason' does not name main"; fi
classify_ref=refs/heads/maintenance
classify "$tmp/green-b1.json" push
expect "push to another branch whose name starts with main: the skip rule applies as before" "$b1" false none
classify_ref=refs/heads/OCT-epic0
classify "$tmp/green-b1.json" push
expect "push to a feature branch with the same base and paths: web and every group skip" "$b1" false none

# --- the push payload: a force push, or a payload that cannot be read, runs everything before any base is looked for ---

# docs-only.txt would skip every group if a base were found, so only the fallback can make them run.
echo docs/x.md > "$tmp/docs-only.txt"
# A commit that is in the repository and not an ancestor of HEAD.
side=$(g commit-tree "$(g rev-parse 'HEAD^{tree}')" -m side)

# fallback_case <label> <word of the reason> <payload text, - or @path>
fallback_case() {
  classify_payload=$3
  classify "$tmp/green-b1.json" push --paths-from "$tmp/docs-only.txt"
  classify_payload=$default_payload
  expect "payload: $1 has no base and runs everything" "" true all
  if printf '%s\n' "$out_reason" | grep -q "$2"; then pass "payload: $1: the reason names the case"; else fail "payload: $1: the reason '$out_reason' does not hold '$2'"; fi
}
fallback_case "a forced push" 'force push' '{"forced": true, "before": "'$c0'"}'
fallback_case "a before that is not an ancestor of HEAD" 'not an ancestor' '{"forced": false, "before": "'$side'"}'
fallback_case "a before that is unknown here" 'unknown here' '{"forced": false, "before": "0123456789abcdef0123456789abcdef01234567"}'
fallback_case "no GITHUB_EVENT_PATH" 'GITHUB_EVENT_PATH is not set' '-'
fallback_case "a payload file that is missing" 'could not be read' "@$tmp/no-such-event.json"
echo 'not json' > "$tmp/event-garbage.json"
fallback_case "a payload that is not JSON" 'could not be read' "@$tmp/event-garbage.json"
fallback_case "a forced that is not a boolean" 'no boolean forced' '{"forced": "false", "before": "'$c0'"}'
fallback_case "a payload with no forced" 'no boolean forced' '{"before": "'$c0'"}'
fallback_case "a payload with no before" '40-hex before' '{"forced": false}'
fallback_case "a before that is not 40 hex characters" '40-hex before' '{"forced": false, "before": "abc123"}'
classify_payload='{"forced": false, "before": "'$c0'"}'
classify "$tmp/green-b1.json" push --paths-from "$tmp/docs-only.txt"
classify_payload=$default_payload
expect "payload: a before that is an ancestor of HEAD is no force push" "$b1" false none
classify "$tmp/green-b1.json" push --paths-from "$tmp/no-such-paths.txt"
expect "paths: a paths file that cannot be read has no base and runs everything" "" true all
if printf '%s\n' "$out_reason" | grep -q 'paths file'; then pass "paths: the reason names the paths file"; else fail "paths: the reason '$out_reason' does not name the paths file"; fi

# --- row 12: the outputs ---

# Without --group: base, web and reason are appended to GITHUB_OUTPUT, and the GROUP lines are printed only, in matrix order.
classify "$tmp/green-b1.json" push
if [ "$(wc -l < "$tmp/github-output" | tr -d ' ')" = 3 ] && [ "$(sed 's/=.*//' "$tmp/github-output" | tr '\n' ' ')" = 'base web reason ' ] \
  && grep -qx "base=$b1" "$tmp/github-output" && grep -qx 'web=false' "$tmp/github-output" && grep -q '^reason=' "$tmp/github-output"; then
  pass "outputs: without --group, base, web and reason are appended to GITHUB_OUTPUT"
else
  fail "outputs: without --group, GITHUB_OUTPUT does not hold base, web and reason ($(tr '\n' '|' < "$tmp/github-output"))"
fi
if [ "$(sed -n 's/^GROUP \([^ ]*\) .*/\1/p' "$tmp/stdout" | tr '\n' ' ')" = "$IRIS_GROUPS " ] && ! grep -q '^GROUP' "$tmp/github-output" \
  && grep -qx "base=$b1" "$tmp/stdout" && grep -qx 'web=false' "$tmp/stdout" && ! grep -q '^run=' "$tmp/stdout"; then
  pass "outputs: without --group, the outputs are printed, with no run, and one GROUP line per group in matrix order, on stdout only"
else
  fail "outputs: without --group, the printed lines are wrong ($(tr '\n' '|' < "$tmp/stdout"))"
fi

# With --group: base, web, run and reason, in this order; the reason is the group's, with the full base.
classify "$tmp/green-b1.json" push --group production
if [ "$(wc -l < "$tmp/github-output" | tr -d ' ')" = 4 ] && [ "$(sed 's/=.*//' "$tmp/github-output" | tr '\n' ' ')" = 'base web run reason ' ] \
  && grep -qx "base=$b1" "$tmp/github-output" && grep -qx 'web=false' "$tmp/github-output" && grep -qx 'run=false' "$tmp/github-output" \
  && grep -qx "reason=no input changed since $b1" "$tmp/github-output" && ! grep -q '^GROUP' "$tmp/github-output"; then
  pass "outputs: with --group, base, web, run and reason are appended to GITHUB_OUTPUT, and the reason of a skip names the full base"
else
  fail "outputs: with --group, GITHUB_OUTPUT does not hold base, web, run and reason ($(tr '\n' '|' < "$tmp/github-output"))"
fi
if grep -qx "GROUP production run=false: no input changed since $b1" "$tmp/stdout"; then
  pass "outputs: the GROUP line of a skipped group holds the same reason"
else
  fail "outputs: the GROUP line of production is wrong ($(grep '^GROUP production' "$tmp/stdout"))"
fi

# Each group asked for alone answers as its GROUP line says: a web change runs every group but production.
echo web/src/app/app.ts > "$tmp/web-only.txt"
for grp in $IRIS_GROUPS; do
  classify "$tmp/green-b1.json" push --group "$grp" --paths-from "$tmp/web-only.txt"
  want=true
  case " $web_groups " in *" $grp "*) ;; *) want=false ;; esac
  line=$(sed -n "s/^GROUP $grp run=[a-z]*: //p" "$tmp/stdout")
  if [ "$rc" -eq 0 ] && [ "$out_run" = "$want" ] && [ "$out_reason" = "$line" ] && [ -n "$line" ] && grep -qx "run=$want" "$tmp/github-output"; then
    pass "outputs: --group $grp answers run=$want with its own reason"
  else
    fail "outputs: --group $grp answered run='$out_run' (wanted $want) with reason '$out_reason', its GROUP line says '$line'"
  fi
done
classify "$tmp/green-b1.json" push --group browser --paths-from "$tmp/web-only.txt"
if [ "$out_reason" = "1 input path(s) of browser changed since $b1" ]; then
  pass "outputs: the reason of a group that runs counts its input paths and names the full base"
else
  fail "outputs: the reason of browser is '$out_reason'"
fi
classify "$tmp/green-b1.json" pull_request --group shards
if [ "$out_run" = true ] && [ "$out_lines" = 6 ] && grep -qx 'run=true' "$tmp/github-output" && printf '%s\n' "$out_reason" | grep -q 'pull_request.*everything runs'; then
  pass "outputs: --group on a fallback answers run=true with the fallback's reason"
else
  fail "outputs: --group on a pull request answered run='$out_run' with reason '$out_reason'"
fi

# A bad group exits 2, prints no output and appends nothing.
bad_group_case() { # bad_group_case <label> <word of stderr> <argument>...
  local label=$1 word=$2
  shift 2
  classify "$tmp/green-b1.json" push "$@"
  if [ "$rc" -eq 2 ] && [ ! -s "$tmp/stdout" ] && [ ! -s "$tmp/github-output" ] && grep -q "$word" "$tmp/stderr"; then
    pass "bad group: $label exits 2 and appends nothing"
  else
    fail "bad group: $label (exit $rc; stdout '$(tr '\n' '|' < "$tmp/stdout")'; stderr '$(tr '\n' '|' < "$tmp/stderr")')"
  fi
}
bad_group_case "--group nosuch" "unknown group 'nosuch'; groups: $IRIS_GROUPS" --group nosuch
bad_group_case "--group with no value" 'usage' --group
bad_group_case "--group with an empty value" 'usage' --group ""
bad_group_case "a group that is a prefix of a name" 'unknown group' --group install

# The script reaches the network only when no answer file is given: with none and no repository it fails open. The runs below
# must not write to a job's output file, so one is named in the environment and has to stay empty.
export GITHUB_OUTPUT="$tmp/leaked-output"
: > "$GITHUB_OUTPUT"
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="" GITHUB_EVENT_PATH="$push_event" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY="" GITHUB_API_URL="http://127.0.0.1:9" bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'web=true' "$tmp/stdout" && [ "$(grep -c '^GROUP .* run=true: ' "$tmp/stdout")" = 6 ] && grep -qx 'base=' "$tmp/stdout" && grep -qx 'reason=GITHUB_REPOSITORY is not set: everything runs' "$tmp/stdout"; then
  pass "API failure: with no repository to ask, everything runs"
else
  fail "API failure: the script did not fail open without a repository"
fi
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="" GITHUB_EVENT_PATH="$push_event" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY=o/r GITHUB_API_URL="http://127.0.0.1:9" bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'web=true' "$tmp/stdout" && [ "$(grep -c '^GROUP .* run=true: ' "$tmp/stdout")" = 6 ] && grep -qx 'base=' "$tmp/stdout" && grep -qx 'reason=the runs API failed: everything runs' "$tmp/stdout"; then
  pass "API failure: an API that does not answer fails open, and everything runs"
else
  fail "API failure: the script did not fail open when the API did not answer"
fi

if [ ! -s "$tmp/leaked-output" ]; then
  pass "harness: the runs above set GITHUB_OUTPUT empty, so an output file of the environment (the checks job's own) stays empty"
else
  fail "harness: a run above wrote to the output file named in the environment"
fi
unset GITHUB_OUTPUT

# An output file that cannot be written fails the step: an empty output would leave the gates empty, and an empty gate skips.
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="$tmp" GITHUB_EVENT_PATH="$push_event" GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/heads/OCT-epic0 bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
rc=$?
if [ "$rc" -ne 0 ] && grep -q '^FAIL ci/changes.sh: cannot append to GITHUB_OUTPUT' "$tmp/stdout"; then
  pass "outputs: an output file that cannot be written fails the step"
else
  fail "outputs: an output file that cannot be written did not fail the step (exit $rc)"
fi

# --- the diff names a path with a non-ASCII name as it is, not quoted, so it still counts as a web input ---

commit "c4 non-ascii web path" "web/src/caf$(printf '\303\251').ts"
c4=$sha
classify "$tmp/green-b1.json" push
expect "classifier: a web path with a non-ASCII name runs web and the web groups" "$b1" true "$web_groups"

# --- the runs API: the request, and the token on the standard input and on no command line ---

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOC'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS"
cat > "$CURL_STDIN"
cat "$CURL_ANSWER"
EOC
chmod +x "$tmp/bin/curl"
(
  cd "$repo" || exit 1
  PATH="$tmp/bin:$PATH" CURL_ARGS="$tmp/curl.args" CURL_STDIN="$tmp/curl.stdin" CURL_ANSWER="$tmp/green-b1.json" \
    GITHUB_OUTPUT="" GITHUB_EVENT_PATH="$push_event" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY=o/r GITHUB_API_URL=https://api.example.invalid GH_TOKEN=tok-for-the-test \
    bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'https://api.example.invalid/repos/o/r/actions/workflows/ci.yml/runs?event=push&status=success&per_page=100' "$tmp/curl.args" \
  && grep -qx "base=$b1" "$tmp/stdout" && grep -qx 'web=true' "$tmp/stdout" && grep -q '^GROUP browser run=true: ' "$tmp/stdout"; then
  pass "API: the runs of this workflow are asked for by push and success, and the answer gives the base"
else
  fail "API: the request or the base is wrong ($(tr '\n' ' ' < "$tmp/curl.args"); $(tr '\n' ' ' < "$tmp/stdout"))"
fi
if grep -q 'Authorization: Bearer tok-for-the-test' "$tmp/curl.stdin" && ! grep -q 'tok-for-the-test' "$tmp/curl.args"; then
  pass "API: the token goes to curl on its standard input and is on no command line"
else
  fail "API: the token is not on curl's standard input, or is on its command line"
fi

# --- row 11, per group: the change of a red run stays in the diff, and only the group that checks it runs again ---

commit "c5 production script, red" docker/tests/test-production.sh
c5=$sha
commit "b3 bookkeeping only" _bmad-output/implementation-artifacts/sprint-status.yaml
runs "$tmp/green-c4.json" "failure:$c5" "success:$c4"
classify "$tmp/green-c4.json" push
expect "red then bookkeeping: the base is the last green commit, so only production runs the red commit's script again" "$c4" false production
others=""
for grp in $IRIS_GROUPS; do
  if [ "$grp" != production ]; then
    grep -qx "GROUP $grp run=false: no input changed since $c4" "$tmp/stdout" || others="$others $grp"
  fi
done
if [ -z "$others" ] && grep -qx "GROUP production run=true: 1 input path(s) of production changed since $c4" "$tmp/stdout"; then
  pass "red then bookkeeping: production runs for its script and the other groups skip with the full base"
else
  fail "red then bookkeeping: the GROUP lines are wrong ($(grep '^GROUP' "$tmp/stdout" | tr '\n' '|'))"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-ci-changes: $fails check(s) failed"
  exit 1
fi
echo "test-ci-changes: all checks passed"
