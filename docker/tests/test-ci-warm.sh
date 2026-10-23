#!/usr/bin/env bash
# Pins of the warm throwaway (Story 32.4; AD-22): ci/warm.sh, the OCUTALON_WARM mode of ci/iris.sh, and the lock and teardown that go
# with them. Prints one PASS or FAIL line per check; exits 0 only when all pass.
#
# bash docker/tests/test-ci-warm.sh            hermetic (the hosted `checks` job runs it). It starts no container and needs bash, git and
#                                              the Docker CLI only: it has its own TMPDIR and lock folders, and stubs docker, dc,
#                                              iris_script, preflight and bash where a check needs it. Each scanner first flags a
#                                              synthetic bad sample. The checks:
#   - the CI rule: no workflow names OCUTALON_WARM or ci/warm.sh, and no code line under ci/ assigns or exports OCUTALON_WARM;
#   - the fresh checks stay fresh: `live` refuses OCUTALON_WARM=1 with exit 2 before a PORT line or a preflight, `group` and `all`
#     drop it with one WARM ignored line and no unit sees it, a bad value gives exit 2 for class, shard, live, group and all, and the
#     fresh branch of run_classes still preflights, takes the lock, starts the stack and prints the same STACK and READY lines;
#   - a warm run: with no stack, another checkout, a stopped stack, a missing stored manifest or a changed non-class input (the mock's
#     files included) it refuses (exit 1) and starts nothing; with nothing changed it reloads 0 and 0 once for a whole shard and
#     calls neither stack_start, stack_ready nor live_start;
#   - warm_reload over synthetic trees: changed, added, removed and renamed classes give the right import, delete and compile lists
#     and the right "WARM reloaded n, deleted m" line; every class is compiled after a delete or a failed reload; a compile error
#     exits 1 with the marker set; a class imported but not compiled is deleted once it leaves the tree; a failed import is tried
#     again; a failed delete is tried again; a session that prints nothing, prints no compile result, or fails the compile with no
#     error text fails and says so;
#   - the lock: the derived pair claims warm-iris.lock with lib-live's protocol (the content grammar, LOCK waiting and busy with
#     exit 75, a foreign lock untouched), a held throwaway-iris.lock does not block it and lib-live's own claim still takes
#     throwaway-iris.lock beside it, the release removes only its own lock, and a drifted derivation fails closed;
#   - warm up, up again, up with no lock folder, up beside a held lock, a failed and a killed up (no project, no lock, no state);
#   - warm down, status, and the state they read, also run as commands (bash ci/warm.sh status|down).
#
# bash docker/tests/test-ci-warm.sh --live      the developer machine only, never CI: real stacks, with the lane variables of Rule 21
#                                              (OCUTALON_LOCK_DIR, OCUTALON_TEST_WEB_PORT, OCUTALON_LOCK_OWNER, OCUTALON_LOCK_WAIT)
#                                              and OCUTALON_RUN_TAG=<T>, with no warm stack in the lane. T is the warm tag and <T>f the
#                                              fresh one. Steps: up and up again; a fresh class beside the warm stack takes
#                                              throwaway-iris.lock without waiting; a warm class and shard on the one project;
#                                              untracked ZzWarm<k> probe classes (new, changed, renamed, subclassed, a removed
#                                              superclass that must fail the compile, all removed); down. The tree is byte-identical
#                                              afterwards (git status --short). About 4 minutes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-scan.sh"
. "$root/ci/iris.sh"
. "$root/ci/warm.sh"

fails=0

# check <label> <output> <exit code> <wanted exit code> <regex>...: PASS when the exit code is the wanted one, each regex matches a
# line of the output, and no !regex does.
check() {
  local label=$1 out=$2 rc=$3 want=$4 re bad=""
  shift 4
  if [ "$rc" -ne "$want" ]; then bad="$bad [exit $rc, wanted $want]"; fi
  for re in "$@"; do
    case $re in
      '!'*) if printf '%s\n' "$out" | grep -Eq -- "${re#!}"; then bad="$bad [unwanted /${re#!}/]"; fi ;;
      *) if ! printf '%s\n' "$out" | grep -Eq -- "$re"; then bad="$bad [missing /$re/]"; fi ;;
    esac
  done
  if [ -z "$bad" ]; then
    pass "$label"
  else
    fail "$label:$bad (output: $(printf '%s' "$out" | tr '\n' '|' | head -c 500))"
  fi
}

# --- the live mode ---

# probe_class <kind> ...: the text of an untracked probe class of the live mode.
probe_target() { # probe_target <class> <answer>
  printf 'Class %s\n{\n\nClassMethod Answer() As %%Integer\n{\n\tQuit %s\n}\n\n}\n' "$1" "$2"
}
probe_test() { # probe_test <class> <target class> <answer> [<class that must be gone>]
  printf 'Class %s Extends %%UnitTest.TestCase\n{\n\nMethod TestAnswer()\n{\n' "$1"
  printf '\tDo $$$AssertEquals(##class(%s).Answer(), %s, "the warm stack runs the current class")\n' "$2" "$3"
  if [ -n "${4:-}" ]; then
    printf '\tDo $$$AssertEquals(##class(%%Dictionary.ClassDefinition).%%ExistsId("%s"), 0, "the old class is not defined")\n' "$4"
    printf '\tDo $$$AssertEquals(##class(%%Dictionary.CompiledClass).%%ExistsId("%s"), 0, "the old class is not compiled")\n' "$4"
  fi
  printf '}\n\n}\n'
}
probe_child() { # probe_child <class> <super class>
  printf 'Class %s Extends %s\n{\n\n}\n' "$1" "$2"
}

warm_projects() { # warm_projects <tag>: the number of compose projects of the tag
  docker ps -a --filter label=com.docker.compose.project --format '{{.Label "com.docker.compose.project"}}' \
    | sort -u | grep -Ec -- "^ocutalon-[a-z0-9-]+-$1-[0-9]{10}-[0-9]+\$"
}

live_checks() {
  local t=${OCUTALON_RUN_TAG:-} tf lockd=${OCUTALON_LOCK_DIR:-} k before after out rc projects
  local tdir=src/ocutalon/cls/OcuTalon/Data/Public tests=src/ocutalon/cls/OcuTalon/Test/Data c1 c2 child
  if [ -z "$t" ] || [ -z "$lockd" ] || [ ! -d "$lockd" ]; then
    echo "test-ci-warm --live needs OCUTALON_RUN_TAG (the warm tag) and OCUTALON_LOCK_DIR (an existing lane folder), with the other lane variables of Rule 21"
    return 2
  fi
  tf="${t}f"
  if [ -e "$lockd/warm-iris.lock" ] || [ "$(warm_projects "$t")" -ne 0 ]; then
    echo "FAIL live: a warm stack of the lane (or of tag $t) is up: run ci/warm.sh down first"
    return 1
  fi
  k=$(date +%s)
  c1=OcuTalon.Data.Public.ZzWarm${k}Target
  c2=OcuTalon.Data.Public.ZzWarm${k}Target2
  child=OcuTalon.Test.Data.ZzWarm${k}Child
  before=$(git status --short)
  live_cleanup_all() {
    trap - EXIT INT TERM HUP
    rm -f "$tdir/ZzWarm${k}Target.cls" "$tdir/ZzWarm${k}Target2.cls" "$tests/ZzWarm${k}Probe.cls" "$tests/ZzWarm${k}Child.cls"
    OCUTALON_RUN_TAG=$t bash ci/warm.sh down > /dev/null 2>&1
    OCUTALON_RUN_TAG=$tf bash ci/iris.sh teardown > /dev/null 2>&1
  }
  trap live_cleanup_all EXIT
  trap 'exit 130' INT TERM HUP

  # 1. up, and up again
  out=$(OCUTALON_RUN_TAG=$t bash ci/warm.sh up 2>&1)
  rc=$?
  check "live 1: up starts one stack, holds warm-iris.lock for it" "$out" "$rc" 0 \
    "^LOCK acquired warm-iris project=ocutalon-warm-$t-[0-9]{10}-[0-9]+\$" "^WARM up project ocutalon-warm-$t-.* tag $t ready [0-9]+s\$"
  projects=$(warm_projects "$t")
  if [ "$projects" -eq 1 ] && grep -q "project=ocutalon-warm-$t-" "$lockd/warm-iris.lock" 2> /dev/null; then
    pass "live 1: exactly one project of the warm tag runs, and the lane folder holds warm-iris.lock naming it"
  else
    fail "live 1: $projects project(s) of tag $t, lock '$(cat "$lockd/warm-iris.lock" 2> /dev/null)'"
  fi
  out=$(OCUTALON_RUN_TAG=$t bash ci/warm.sh up 2>&1)
  rc=$?
  check "live 1: up again says that the stack is already up, with no new project" "$out" "$rc" 0 "^WARM up: project ocutalon-warm-$t-.* is already up\$" '!^LOCK'
  [ "$(warm_projects "$t")" -eq 1 ] || fail "live 1: up again changed the number of projects of tag $t"

  # 2. a fresh run beside the warm stack takes throwaway-iris.lock without waiting
  out=$(OCUTALON_RUN_TAG=$tf bash ci/iris.sh class OcuTalon.Test.Agent.Constants 2>&1)
  rc=$?
  check "live 2: a fresh class beside the warm stack takes throwaway-iris.lock with no wait, and passes" "$out" "$rc" 0 \
    '^LOCK acquired throwaway-iris project=' '!^LOCK waiting' "^STACK OcuTalon.Test.Agent.Constants: project ocutalon-class-$tf-" \
    '^CLASS OcuTalon.Test.Agent.Constants passed' '!WARM'
  [ -e "$lockd/warm-iris.lock" ] || fail "live 2: the fresh run released the warm lock"

  # 3 and 4. warm runs on the one project
  out=$(OCUTALON_WARM=1 OCUTALON_RUN_TAG=$t bash ci/iris.sh class OcuTalon.Test.Agent.Constants 2>&1)
  rc=$?
  check "live 3: a warm class reloads nothing, starts nothing, takes no lock, and passes" "$out" "$rc" 0 \
    '^WARM reloaded 0, deleted 0$' '^READY OcuTalon.Test.Agent.Constants [0-9]+s \(warm\)$' '^CLASS OcuTalon.Test.Agent.Constants passed' '!^LOCK' '!^PORT'
  [ "$(warm_projects "$t")" -eq 1 ] || fail "live 3: a warm run changed the number of projects of tag $t"
  out=$(OCUTALON_WARM=1 OCUTALON_RUN_TAG=$t bash ci/iris.sh shard lane-a 2>&1)
  rc=$?
  check "live 4: a warm shard lane-a passes on the same project" "$out" "$rc" 0 '^WARM reloaded 0, deleted 0$' '^SHARD lane-a passed' '!FAIL'
  [ "$(printf '%s\n' "$out" | grep -c '^WARM reloaded')" -eq 1 ] || fail "live 4: a warm shard printed more than one WARM reloaded line"

  # 5. probes: a class of a mapped package and a test class that uses it
  warm_class() { OCUTALON_WARM=1 OCUTALON_RUN_TAG=$t bash ci/iris.sh class "$@" 2>&1; }
  probe_target "$c1" 41 > "$tdir/ZzWarm${k}Target.cls"
  probe_test "OcuTalon.Test.Data.ZzWarm${k}Probe" "$c1" 41 > "$tests/ZzWarm${k}Probe.cls"
  out=$(warm_class "OcuTalon.Test.Data.ZzWarm${k}Probe")
  rc=$?
  check "live 5: new classes are loaded, compiled, and run" "$out" "$rc" 0 '^WARM reloaded 2, deleted 0$' "^CLASS OcuTalon.Test.Data.ZzWarm${k}Probe passed"
  probe_target "$c1" 42 > "$tdir/ZzWarm${k}Target.cls"
  probe_test "OcuTalon.Test.Data.ZzWarm${k}Probe" "$c1" 42 > "$tests/ZzWarm${k}Probe.cls"
  out=$(warm_class "OcuTalon.Test.Data.ZzWarm${k}Probe")
  rc=$?
  check "live 5: a changed class answers its new value" "$out" "$rc" 0 '^WARM reloaded 2, deleted 0$' "^CLASS OcuTalon.Test.Data.ZzWarm${k}Probe passed"
  rm -f "$tdir/ZzWarm${k}Target.cls"
  probe_target "$c2" 42 > "$tdir/ZzWarm${k}Target2.cls"
  probe_test "OcuTalon.Test.Data.ZzWarm${k}Probe" "$c2" 42 "$c1" > "$tests/ZzWarm${k}Probe.cls"
  out=$(warm_class "OcuTalon.Test.Data.ZzWarm${k}Probe")
  rc=$?
  check "live 5: a renamed class is deleted: the old class is neither defined nor compiled" "$out" "$rc" 0 \
    '^WARM reloaded 2, deleted 1$' '^WARM compiled every class' "^CLASS OcuTalon.Test.Data.ZzWarm${k}Probe passed"
  probe_child "$child" "$c2" > "$tests/ZzWarm${k}Child.cls"
  out=$(warm_class "OcuTalon.Test.Data.ZzWarm${k}Probe")
  rc=$?
  check "live 5: a subclass is loaded and compiled" "$out" "$rc" 0 '^WARM reloaded 1, deleted 0$' "^CLASS OcuTalon.Test.Data.ZzWarm${k}Probe passed"
  rm -f "$tdir/ZzWarm${k}Target2.cls"
  out=$(warm_class "OcuTalon.Test.Data.ZzWarm${k}Probe")
  rc=$?
  check "live 5: a removed superclass fails the compile of its subclass, as on a fresh stack, and no class runs" "$out" "$rc" 1 \
    '^WARM reloaded 0, deleted 1$' '^WARM compiled every class .*: after a delete$' "^FAIL WARM compile: OcuTalon\\.Test\\.Data\\.ZzWarm${k}Child: " '!^CLASS' '!^READY'
  rm -f "$tests/ZzWarm${k}Child.cls" "$tests/ZzWarm${k}Probe.cls"
  out=$(warm_class OcuTalon.Test.Agent.Constants)
  rc=$?
  check "live 5: with every probe removed the rest are deleted, every class compiles, and the class passes" "$out" "$rc" 0 \
    '^WARM reloaded 0, deleted 2$' '^WARM compiled every class' '^CLASS OcuTalon.Test.Agent.Constants passed'
  out=$(warm_class OcuTalon.Test.Agent.Constants)
  rc=$?
  check "live 5: the next warm run has nothing to reload" "$out" "$rc" 0 '^WARM reloaded 0, deleted 0$' '!compiled every class'

  # 6. down
  out=$(OCUTALON_RUN_TAG=$t bash ci/warm.sh down 2>&1)
  rc=$?
  check "live 6: down removes the project and releases the lock" "$out" "$rc" 0 \
    "^LOCK released warm-iris project=ocutalon-warm-$t-" "^TEARDOWN tag $t: 1 project\\(s\\) removed" "^WARM down tag $t\$"
  if [ ! -e "$lockd/warm-iris.lock" ] && [ "$(warm_projects "$t")" -eq 0 ] && [ ! -e "${TMPDIR:-/tmp}/ocutalon-warm-$t" ]; then
    pass "live 6: the lock, the project and the state are gone"
  else
    fail "live 6: the lock, a project of tag $t or the state is left"
  fi
  live_cleanup_all
  after=$(git status --short)
  if [ "$before" = "$after" ]; then
    pass "live: the tree is byte-identical before and after (git status --short)"
  else
    fail "live: git status --short changed: before '$before', after '$after'"
  fi
  if [ "$fails" -ne 0 ]; then
    echo "test-ci-warm: $fails live check(s) failed"
    return 1
  fi
  echo "test-ci-warm: all live checks passed"
}

case ${1:-} in
  --live)
    live_checks
    exit $?
    ;;
  '') ;;
  *)
    echo "usage: bash docker/tests/test-ci-warm.sh [--live]"
    exit 2
    ;;
esac

# --- the hermetic mode ---

# Nothing of the caller's environment may reach a check.
unset OCUTALON_WARM OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_LOCK_DIR OCUTALON_LOCK_OWNER OCUTALON_LOCK_WAIT \
  OCUTALON_LOCK_SLEEP_MIN OCUTALON_LOCK_SLEEP_MAX OCUTALON_LIVE_DEADLINE IRIS_IMAGE OCUTALON_PULL_PAUSE
work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cw.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
export TMPDIR="$work/tmp"
mkdir -p "$TMPDIR" "$work/bin"
state_of() { warm_state_dir "$1"; }

# --- the CI rule ---

warm_in_workflow() { grep -nH -e 'OCUTALON_WARM' -e 'ci/warm\.sh' "$@" | cut -d: -f1,2; }
warm_assigned_in_ci() {
  grep -nHE '(^|[^A-Za-z0-9_])(export[[:space:]]+OCUTALON_WARM|OCUTALON_WARM=)' "$@" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | cut -d: -f1,2
}
printf 'jobs:\n  x:\n    steps:\n      - run: OCUTALON_WARM=1 bash ci/iris.sh class A\n' > "$work/bad-workflow.yml"
printf 'jobs:\n  x:\n    steps:\n      - run: bash ci/warm.sh up\n' > "$work/bad-workflow2.yml"
printf 'jobs:\n  x:\n    steps:\n      - run: bash ci/iris.sh group shards\n' > "$work/good-workflow.yml"
printf 'x() {\n  export OCUTALON_WARM=1\n}\n' > "$work/bad-ci.sh"
printf 'x() {\n  OCUTALON_WARM=1 bash ci/iris.sh class A\n}\n' > "$work/bad-ci2.sh"
printf '# OCUTALON_WARM=1 ci/iris.sh class A is documented here\nx() {\n  unset OCUTALON_WARM\n  case ${OCUTALON_WARM:-} in 1) ;; esac\n}\n' > "$work/good-ci.sh"
if [ -z "$(warm_in_workflow "$work/bad-workflow2.yml")" ]; then
  fail "the CI rule: the workflow scanner does not flag a workflow that runs ci/warm.sh"
else
  scan_rule "the CI rule: no workflow names OCUTALON_WARM or ci/warm.sh" warm_in_workflow "$work/bad-workflow.yml" "$work/good-workflow.yml" \
    "$(scan_files .github/workflows)"
fi
if [ -z "$(warm_assigned_in_ci "$work/bad-ci2.sh")" ]; then
  fail "the CI rule: the ci/ scanner does not flag a line that sets OCUTALON_WARM for a command"
else
  scan_rule "the CI rule: no code line under ci/ assigns or exports OCUTALON_WARM" warm_assigned_in_ci "$work/bad-ci.sh" "$work/good-ci.sh" "$(scan_files ci)"
fi

# --- the fresh checks stay fresh ---

# cli <env assignments...> -- <ci/iris.sh arguments...>: ci/iris.sh in a process, with a base image that does not exist, so that a
# command that gets past the OCUTALON_WARM check ends at the preflight (exit 1) and never starts a stack. Sets cli_out, cli_rc.
cli() {
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  cli_out=$(env -u OCUTALON_WARM -u OCUTALON_RUN_TAG -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME IRIS_IMAGE=ocutalon-no-such-image:0 \
    ${envs[@]+"${envs[@]}"} bash "$root/ci/iris.sh" "$@" 2>&1)
  cli_rc=$?
}
cli OCUTALON_WARM=1 OCUTALON_RUN_TAG=abc-1 -- live compose-start
check "live refuses OCUTALON_WARM=1 with exit 2 before a PORT line or a preflight" "$cli_out" "$cli_rc" 2 \
  '^FAIL live units never run warm: unset OCUTALON_WARM$' '!^PORT' '!base image'
cli OCUTALON_RUN_TAG=abc-1 -- live compose-start
check "live without OCUTALON_WARM still reaches its preflight (the control of the refusal)" "$cli_out" "$cli_rc" 1 '^PORT ' '^FAIL the base image'
cli OCUTALON_WARM=0 OCUTALON_RUN_TAG=abc-1 -- live compose-start
check "OCUTALON_WARM=0 is fresh: live reaches its preflight" "$cli_out" "$cli_rc" 1 '^PORT ' '^FAIL the base image'
bad_value_ok=1
for argv in "class OcuTalon.Test.Agent.Constants" "shard lane-a" "live compose-start" "group image" "all"; do
  # shellcheck disable=SC2086
  cli OCUTALON_WARM=yes OCUTALON_RUN_TAG=abc-1 -- $argv
  if [ "$cli_rc" -ne 2 ] || ! printf '%s\n' "$cli_out" | grep -qx 'FAIL OCUTALON_WARM must be 1 (warm), or 0 or unset (fresh)'; then
    bad_value_ok=0
    fail "a bad OCUTALON_WARM value for '$argv': exit $cli_rc, output $(printf '%s' "$cli_out" | tr '\n' '|' | head -c 200)"
  fi
done
if [ "$bad_value_ok" -eq 1 ]; then pass "OCUTALON_WARM=yes gives exit 2 and the FAIL line for class, shard, live, group and all"; fi

# group and all: every unit's process sees no OCUTALON_WARM, and one WARM ignored line is printed. `bash` is a stub that prints
# what each unit's process would see.
unit_env_run() { # unit_env_run <function and arguments...>
  (
    export OCUTALON_WARM=1 OCUTALON_RUN_TAG=abc-1
    preflight() { :; }
    ensure_web_bundle() { return 0; }
    bash() { echo "UNIT-PROCESS $2 $3 warm=${OCUTALON_WARM-unset}"; return 0; }
    "$@"
  ) 2>&1
}
out=$(unit_env_run cmd_group shards)
rc=$?
check "group with OCUTALON_WARM=1: one WARM ignored line, and each unit sees no OCUTALON_WARM" "$out" "$rc" 0 \
  '^WARM ignored: group shards runs every unit on a fresh stack$' '^UNIT-PROCESS shard lane-a warm=unset$' '^UNIT-PROCESS shard lane-b warm=unset$' '!warm=1'
if [ "$(printf '%s\n' "$out" | grep -c '^WARM ignored')" -eq 1 ]; then pass "group prints its WARM ignored line once"; else fail "group printed WARM ignored more than once"; fi
out=$(unit_env_run cmd_all)
rc=$?
check "all with OCUTALON_WARM=1: one WARM ignored line, and every group's process sees no OCUTALON_WARM" "$out" "$rc" 0 \
  '^WARM ignored: all runs every unit on a fresh stack$' '^UNIT-PROCESS group install-fresh warm=unset$' '^UNIT-PROCESS group image warm=unset$' '!warm=1'
if [ "$(printf '%s\n' "$out" | grep -c '^WARM ignored')" -eq 1 ]; then pass "all prints its WARM ignored line once"; else fail "all printed WARM ignored more than once"; fi

# The fresh branch of run_classes: preflight, live_start, the build and start, and the same STACK and READY lines as before.
calls=$work/fresh.calls
: > "$calls"
out=$(
  unset OCUTALON_WARM
  OCUTALON_RUN_TAG=cw-f
  preflight() { echo preflight >> "$calls"; }
  live_start() { echo "live_start $1" >> "$calls"; P=ocutalon-class-cw-f-1700000000-1; tmp=$work/fresh-tmp; mkdir -p "$tmp"; deadline=$((SECONDS + 100)); }
  dc() { echo "dc $1 $2 $3 $4" >> "$calls"; return 0; }
  live_track_image() { :; }
  iris_script() { cat > /dev/null; printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' 'CHK|case|OcuTalon.Test.Agent.Constants|1|0.01|1'; }
  cmd_class OcuTalon.Test.Agent.Constants
)
rc=$?
check "the fresh branch of run_classes prints the STACK and READY lines of a fresh stack" "$out" "$rc" 0 \
  '^STACK OcuTalon.Test.Agent.Constants: project ocutalon-class-cw-f-1700000000-1$' '^READY OcuTalon.Test.Agent.Constants [0-9]+s$' \
  '^CLASS OcuTalon.Test.Agent.Constants passed' '^RUN OcuTalon.Test.Agent.Constants passed \(1 classes\)' '!WARM' '!warm'
if [ "$(tr '\n' '|' < "$calls")" = "preflight|live_start class|dc up -d --build --wait|" ]; then
  pass "the fresh branch calls preflight, live_start and dc up, in that order"
else
  fail "the fresh branch made the calls '$(tr '\n' '|' < "$calls")'"
fi

# --- the warm tag and the state ---

out=$(env -u OCUTALON_RUN_TAG bash ci/warm.sh up 2>&1)
check "ci/warm.sh without OCUTALON_RUN_TAG gives exit 2 and says so" "$out" $? 2 "^ci/warm.sh needs OCUTALON_RUN_TAG: the warm stack's tag\$"
out=$(OCUTALON_RUN_TAG=Bad_Tag bash ci/warm.sh up 2>&1)
check "ci/warm.sh with a bad tag gives exit 2 and the tag rule" "$out" $? 2 "^FAIL OCUTALON_RUN_TAG 'Bad_Tag' must match"
out=$(OCUTALON_RUN_TAG=my-slot-tag bash ci/warm.sh status 2>&1)
check "ci/warm.sh with a tag that holds 'slot' gives exit 2" "$out" $? 2 "^FAIL OCUTALON_RUN_TAG 'my-slot-tag' must match"
out=$(OCUTALON_RUN_TAG=abc-1 bash ci/warm.sh nosuchcommand 2>&1)
check "ci/warm.sh with an unknown command prints its usage and exits 2" "$out" $? 2 'ci/warm.sh up' '!^WARM'

# The docker stub of the checks: a running iris container when STUB_RUNNING=1, the projects of STUB_PROJECTS for a listing, and a log.
docker_stub() {
  echo "docker $*" >> "$work/docker.calls"
  case "$*" in
    *status=running*) if [ "${STUB_RUNNING:-0}" = 1 ]; then echo abc123; fi ;;
    "ps -a --filter label="*) printf '%s\n' ${STUB_PROJECTS:-} ;;
    "ps -a --format "*) for n in ${STUB_PROJECTS:-}; do printf '%s-iris-1\n' "$n"; done ;;
  esac
  return 0
}

# fixture_state <tag> <project> [<root>] [<manifest source dir>]: the state folder of a warm stack that was built from the tree.
fixture_state() {
  local tag=$1 proj=$2 r=${3:-$root} src=${4:-$root} d
  d=$(state_of "$tag")
  rm -rf "$d"
  mkdir -p "$d"
  (cd "$src" && warm_manifest) > "$d/manifest"
  printf '%s\n' "$proj" > "$d/project"
  printf '%s\n' "$r" > "$d/root"
  printf '2026-10-23T00:00:00Z\n' > "$d/since"
  printf '%s\n' "$root/docker-compose.yml" "$d/decoy.yml" "$root/docker/tests/compose.throwaway.yml" "$root/ci/compose.ci.yml" "$d/warm.yml" > "$d/files"
}

# warm_cli <tag> <warm: 1|0> <path stub: 1|0> <args...>: `bash ci/iris.sh` in a process with a stub docker first on the PATH and the
# lock folder $work/locks-cli. Sets cli_out, cli_rc, and the stub's calls in $work/cli.calls.
mkdir -p "$work/locks-cli"
printf '#!/bin/sh\necho "docker $*" >> "%s"\ncase "$*" in\n  *status=running*) [ "${STUB_RUNNING:-0}" = 1 ] && echo abc123 ;;\nesac\nexit 0\n' "$work/cli.calls" > "$work/bin/docker"
chmod +x "$work/bin/docker"
warm_cli() {
  local tag=$1
  shift
  : > "$work/cli.calls"
  cli_out=$(env -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME OCUTALON_WARM=1 OCUTALON_RUN_TAG="$tag" OCUTALON_LOCK_DIR="$work/locks-cli" PATH="$work/bin:$PATH" \
    ${STUB_RUNNING:+STUB_RUNNING=$STUB_RUNNING} bash "$root/ci/iris.sh" "$@" 2>&1)
  cli_rc=$?
}
warm_cli cw-none class OcuTalon.Test.Agent.Constants
check "a warm run with no warm stack fails with exit 1, starts nothing and takes no lock" "$cli_out" "$cli_rc" 1 \
  '^FAIL WARM no warm stack for tag cw-none: run ci/warm.sh up first$' '!^LOCK' '!^STACK' '!^CLASS'
if [ ! -s "$work/cli.calls" ] && [ -z "$(ls "$work/locks-cli")" ]; then pass "no warm stack: no docker call and no lock file"; else fail "no warm stack: docker was called or a lock was made: $(cat "$work/cli.calls")"; fi
fixture_state cw-gone ocutalon-warm-cw-gone-1700000000-1
STUB_RUNNING=0 warm_cli cw-gone class OcuTalon.Test.Agent.Constants
check "a warm run whose stack is not running fails with exit 1 and says how to restart it" "$cli_out" "$cli_rc" 1 \
  '^FAIL WARM the warm stack ocutalon-warm-cw-gone-1700000000-1 is not running: run ci/warm.sh down, then ci/warm.sh up$' '!^STACK' '!^CLASS'
fixture_state cw-other ocutalon-warm-cw-other-1700000000-1 "$work/another-checkout"
STUB_RUNNING=1 warm_cli cw-other class OcuTalon.Test.Agent.Constants
check "a warm run on a stack built from another checkout fails with exit 1" "$cli_out" "$cli_rc" 1 \
  '^FAIL WARM the warm stack of tag cw-other was built from another checkout$' '!^STACK' '!^CLASS'
fixture_state cw-stale ocutalon-warm-cw-stale-1700000000-1
sed 's#^[0-9a-f]* docker/Dockerfile$#0000000000000000000000000000000000000000 docker/Dockerfile#' "$(state_of cw-stale)/manifest" > "$work/manifest.stale"
cp "$work/manifest.stale" "$(state_of cw-stale)/manifest"
STUB_RUNNING=1 warm_cli cw-stale class OcuTalon.Test.Agent.Constants
check "a warm run after a change of the Dockerfile is refused, and nothing runs" "$cli_out" "$cli_rc" 1 \
  '^FAIL WARM stale: docker/Dockerfile changed since warm up, and only classes reload: run ci/warm.sh down, then ci/warm.sh up$' '!^CLASS' '!^READY'
if ! grep -q 'exec' "$work/cli.calls"; then pass "a stale warm run opens no IRIS session"; else fail "a stale warm run opened an IRIS session"; fi

# Nothing changed: no start of any kind, and the verdict of the class comes from the session.
calls=$work/nothing.calls
: > "$calls"
fixture_state cw-n ocutalon-warm-cw-n-1700000000-1
out=$(
  export OCUTALON_WARM=1 OCUTALON_RUN_TAG=cw-n
  stack_start() { echo stack_start >> "$calls"; }
  stack_ready() { echo stack_ready >> "$calls"; }
  live_start() { echo live_start >> "$calls"; }
  preflight() { echo preflight >> "$calls"; }
  docker() { docker_stub "$@"; }
  STUB_RUNNING=1
  iris_script() {
    echo iris_script >> "$calls"
    cat > /dev/null
    printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' 'CHK|case|OcuTalon.Test.Agent.Constants|1|0.0123|2'
  }
  cmd_class OcuTalon.Test.Agent.Constants
)
rc=$?
check "a warm run with nothing changed reloads 0 and 0, and the verdict is the session's" "$out" "$rc" 0 \
  '^STACK OcuTalon.Test.Agent.Constants: warm project ocutalon-warm-cw-n-1700000000-1$' '^WARM reloaded 0, deleted 0$' \
  '^READY OcuTalon.Test.Agent.Constants [0-9]+s \(warm\)$' '^CLASS OcuTalon.Test.Agent.Constants passed 0.01s$' '^RUN OcuTalon.Test.Agent.Constants passed' '!^LOCK'
if [ "$(tr '\n' '|' < "$calls")" = "iris_script|" ]; then
  pass "a warm run with nothing changed never calls preflight, stack_start, stack_ready or live_start, and opens one session (the class)"
else
  fail "a warm run with nothing changed made the calls '$(tr '\n' '|' < "$calls")'"
fi
if [ "$(printf '%s\n' "$out" | grep -c '^WARM reloaded')" -eq 1 ]; then
  pass "a warm class run prints exactly one WARM reloaded line"
else
  fail "a warm class run printed $(printf '%s\n' "$out" | grep -c '^WARM reloaded') WARM reloaded lines"
fi

# A warm shard reloads once for the whole shard, however many classes it runs.
calls=$work/shard.calls
: > "$calls"
fixture_state cw-sh ocutalon-warm-cw-sh-1700000000-1
shard_classes=$(test_classes $(shard_areas lane-a) | grep -c .)
out=$(
  export OCUTALON_WARM=1 OCUTALON_RUN_TAG=cw-sh
  stack_start() { echo stack_start >> "$calls"; }
  live_start() { echo live_start >> "$calls"; }
  docker() { docker_stub "$@"; }
  STUB_RUNNING=1
  run_class() { echo "CLASS $1 passed 0.00s"; }
  cmd_shard lane-a
)
rc=$?
check "a warm shard prints one WARM reloaded line, runs each class, and starts nothing" "$out" "$rc" 0 \
  '^STACK lane-a: warm project ocutalon-warm-cw-sh-1700000000-1$' '^READY lane-a [0-9]+s \(warm\)$' "^SHARD lane-a passed \\($shard_classes classes\\)" '!^LOCK'
if [ "$shard_classes" -gt 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^WARM reloaded')" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^CLASS ')" -eq "$shard_classes" ] \
  && [ ! -s "$calls" ]; then
  pass "a warm shard of $shard_classes classes reloads once, not once per class"
else
  fail "a warm shard of $shard_classes classes printed $(printf '%s\n' "$out" | grep -c '^WARM reloaded') WARM reloaded lines and $(printf '%s\n' "$out" | grep -c '^CLASS ') CLASS lines, calls '$(tr '\n' '|' < "$calls")'"
fi

# --- warm_reload over synthetic trees ---

mk_tree() { # mk_tree <dir>: a tree with the layout of the repository, small enough to read
  local d=$1 c
  mkdir -p "$d/docker/tests" "$d/ci/mock/test" "$d/src/ocutalon/cls/OcuTalon/Data/Public" "$d/src/bridge/cls/OcuTalon/Bridge" "$d/src/ocutalon/csp"
  printf 'FROM scratch\nCOPY src/ /opt/ocutalon/src/\nCOPY docker/merge.cpf docker/healthcheck.sh /opt/ocutalon/\n' > "$d/docker/Dockerfile"
  printf 'merge\n' > "$d/docker/merge.cpf"
  printf 'health\n' > "$d/docker/healthcheck.sh"
  printf '*\n' > "$d/.dockerignore"
  printf 'services:\n' > "$d/docker-compose.yml"
  printf 'services:\n' > "$d/docker/tests/compose.throwaway.yml"
  printf 'services:\n' > "$d/ci/compose.ci.yml"
  printf 'server\n' > "$d/ci/mock/server.mjs"
  printf 'test\n' > "$d/ci/mock/test/server.test.mjs"
  printf '<Module/>\n' > "$d/src/module.xml"
  printf 'bundle\n' > "$d/src/ocutalon/csp/index.html"
  for c in ocutalon/cls/OcuTalon/A ocutalon/cls/OcuTalon/B ocutalon/cls/OcuTalon/Sub ocutalon/cls/OcuTalon/Data/Public/Pub bridge/cls/OcuTalon/Bridge/C; do
    printf 'Class x\n' > "$d/src/$c.cls"
  done
}
tree=$work/tree
mk_tree "$tree"
tree_classes=5

# The IRIS session stub: it keeps the script it receives and answers from the script's own array lines, so that the reload's reading
# of the answer is checked against the lists it sent. STUB_EMPTY=1 prints nothing, STUB_IMPORT_FAIL=<text> fails the imports whose file
# holds the text, STUB_COMPILE_FAIL=1 fails the compile with one error on the first class of the list, STUB_COMPILE_NOROWS=1 fails it
# with no error row, STUB_NO_COMPILE=1 prints no compile result, and STUB_DELETE_FAIL=<class> fails the delete of that class.
reload_session_stub() {
  local s n
  s=$(cat)
  n=$(ls "$sessions" | wc -l | tr -d ' ')
  printf '%s\n' "$s" > "$sessions/$((n + 1))"
  if [ "${STUB_EMPTY:-0}" = 1 ]; then return 0; fi
  printf '%s\n' "$s" | awk -v failimp="${STUB_IMPORT_FAIL:-}" -v failcomp="${STUB_COMPILE_FAIL:-0}" -v faildel="${STUB_DELETE_FAIL:-}" \
    -v norows="${STUB_COMPILE_NOROWS:-0}" -v nocomp="${STUB_NO_COMPILE:-0}" '
    function val(line) { sub(/^[^"]*"/, "", line); sub(/".*$/, "", line); return line }
    /^Set d\([0-9]+\)="/ {
      c = val($0)
      if (faildel != "" && c == faildel) print "CHK|delete|" c "|0|delete boom"; else print "CHK|delete|" c "|1|"
    }
    /^Set l\([0-9]+\)="/ {
      f = val($0)
      if (failimp != "" && index(f, failimp) > 0) print "CHK|import|" f "|0|import boom"; else print "CHK|import|" f "|1|"
    }
    /^Set c\("/ { if (!first) { first = val($0) } seen = 1 }
    END {
      if (seen && nocomp != 1) {
        if (failcomp == 1) { print "CHK|compile|0"; print "CHK|error|" first "|compile boom" }
        else if (norows == 1) print "CHK|compile|0"
        else print "CHK|compile|1"
      }
    }'
}

# reload_case <label> <tree> <tag> <env assignments...>: warm_reload in the tree against the state of the tag. Sets rl_out, rl_rc and
# the sessions folder $work/sessions-<label>.
reload_case() {
  local label=$1 dir=$2 tag=$3
  shift 3
  sessions=$work/sessions-$label
  mkdir -p "$sessions"
  rl_out=$(
  {
    cd "$dir" || exit 99
    P=ocutalon-warm-$tag-1700000000-1
    OCUTALON_RUN_TAG=$tag
    for kv in "$@"; do export "${kv?}"; done
    tmp=$(mktemp -d "$TMPDIR/ocutalon-run.XXXXXX")
    iris_script() { reload_session_stub; }
    warm_reload
  } 2>&1
  )
  rl_rc=$?
  rl_last=$(ls "$sessions" | wc -l | tr -d ' ')
}
session_has() { grep -qxF -- "$1" "$sessions/$rl_last" 2> /dev/null; }
session_count() { grep -c -- "$1" "$sessions/$rl_last" 2> /dev/null; }
fixture_state cw-r ocutalon-warm-cw-r-1700000000-1 "$work/tree" "$tree"

reload_case r1 "$tree" cw-r
check "reload: nothing changed reloads 0 and 0 and opens no session" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$' '!compiled every class'
[ "$rl_last" -eq 0 ] || fail "reload: nothing changed opened a session"

printf 'changed\n' >> "$tree/src/ocutalon/cls/OcuTalon/A.cls"
printf 'Class x\n' > "$tree/src/ocutalon/cls/OcuTalon/Data/Public/NewPub.cls"
printf 'Class x\n' > "$tree/src/bridge/cls/OcuTalon/Bridge/D.cls"
reload_case r2 "$tree" cw-r
check "reload: a changed class and two new ones (one in a mapped package) give 'reloaded 3, deleted 0'" "$rl_out" "$rl_rc" 0 '^WARM reloaded 3, deleted 0$' '!compiled every class'
if session_has 'Set l(1)="/opt/ocutalon/warm-src/bridge/cls/OcuTalon/Bridge/D.cls"' \
  && session_has 'Set l(2)="/opt/ocutalon/warm-src/ocutalon/cls/OcuTalon/A.cls"' \
  && session_has 'Set l(3)="/opt/ocutalon/warm-src/ocutalon/cls/OcuTalon/Data/Public/NewPub.cls"' \
  && [ "$(session_count '^Set d(')" -eq 0 ] && session_has 'Set q="cb-d"' && [ "$(session_count '^Set c("')" -eq 3 ] \
  && session_has 'Set c("OcuTalon.A")=""' && session_has 'Set c("OcuTalon.Data.Public.NewPub")=""' && session_has 'Set c("OcuTalon.Bridge.D")=""'; then
  pass "reload: the files are imported from the mounted tree, nothing is deleted, and the imported classes are compiled with their subclasses (cb-d)"
else
  fail "reload: the session for a changed and two new classes is wrong: $(tr '\n' '|' < "$sessions/$rl_last" | head -c 600)"
fi
reload_case r3 "$tree" cw-r
check "reload: the stored manifest follows the imports, so the next run has nothing to do" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$'

rm "$tree/src/ocutalon/cls/OcuTalon/B.cls"
reload_case r4 "$tree" cw-r
classes_now=$(find "$tree/src" -name '*.cls' | wc -l | tr -d ' ')
check "reload: a removed class gives 'reloaded 0, deleted 1' and every class of the tree is compiled" "$rl_out" "$rl_rc" 0 \
  '^WARM reloaded 0, deleted 1$' "^WARM compiled every class \\($classes_now\\): after a delete\$"
if session_has 'Set d(1)="OcuTalon.B"' && session_has 'Set q="c-d"' && [ "$(session_count '^Set c("')" -eq "$classes_now" ] && [ "$(session_count '^Set l(')" -eq 0 ]; then
  pass "reload: the session deletes OcuTalon.B and compiles all $classes_now classes (c-d)"
else
  fail "reload: the session for a removed class is wrong: $(tr '\n' '|' < "$sessions/$rl_last" | head -c 600)"
fi

mv "$tree/src/ocutalon/cls/OcuTalon/A.cls" "$tree/src/ocutalon/cls/OcuTalon/A2.cls"
reload_case r5 "$tree" cw-r
check "reload: a renamed class gives 'reloaded 1, deleted 1' and a full compile" "$rl_out" "$rl_rc" 0 '^WARM reloaded 1, deleted 1$' '^WARM compiled every class .*: after a delete$'
if session_has 'Set d(1)="OcuTalon.A"' && session_has 'Set l(1)="/opt/ocutalon/warm-src/ocutalon/cls/OcuTalon/A2.cls"'; then
  pass "reload: the old name is deleted and the new file is imported"
else
  fail "reload: the session for a renamed class is wrong: $(tr '\n' '|' < "$sessions/$rl_last" | head -c 600)"
fi

printf 'more\n' >> "$tree/src/ocutalon/cls/OcuTalon/Sub.cls"
reload_case r6 "$tree" cw-r STUB_COMPILE_FAIL=1
check "reload: a compile error fails with exit 1, names the class, and leaves the failed marker" "$rl_out" "$rl_rc" 1 \
  '^WARM reloaded 1, deleted 0$' '^FAIL WARM compile: OcuTalon.Sub: compile boom$'
if [ -f "$(state_of cw-r)/failed" ]; then pass "reload: the failed marker is set"; else fail "reload: no failed marker after a compile error"; fi
reload_case r7 "$tree" cw-r
classes_now=$(find "$tree/src" -name '*.cls' | wc -l | tr -d ' ')
check "reload: the run after a failed one compiles every class, and clears the marker when it passes" "$rl_out" "$rl_rc" 0 \
  '^WARM reloaded 0, deleted 0$' "^WARM compiled every class \\($classes_now\\): after a failed reload\$"
if [ ! -f "$(state_of cw-r)/failed" ]; then pass "reload: the failed marker is cleared"; else fail "reload: the failed marker is still set"; fi
reload_case r8 "$tree" cw-r
check "reload: and the run after that compiles nothing" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$' '!compiled every class'

# A class imported but not compiled, then removed from the tree, is deleted.
printf 'Class x\n' > "$tree/src/ocutalon/cls/OcuTalon/Zz.cls"
reload_case r9 "$tree" cw-r STUB_COMPILE_FAIL=1
check "reload: a new class whose compile fails is imported all the same" "$rl_out" "$rl_rc" 1 '^WARM reloaded 1, deleted 0$' '^FAIL WARM compile: OcuTalon.Zz: compile boom$'
if grep -q ' src/ocutalon/cls/OcuTalon/Zz.cls$' "$(state_of cw-r)/manifest"; then pass "reload: the imported file is in the stored manifest"; else fail "reload: the imported file is not in the stored manifest"; fi
rm "$tree/src/ocutalon/cls/OcuTalon/Zz.cls"
reload_case r10 "$tree" cw-r
check "reload: a class imported but never compiled is deleted once it leaves the tree" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 1$' '^WARM compiled every class'
session_has 'Set d(1)="OcuTalon.Zz"' || fail "reload: the session did not delete OcuTalon.Zz"

# An import that fails is tried again.
printf 'Class x\n' > "$tree/src/ocutalon/cls/OcuTalon/Imp.cls"
reload_case r11 "$tree" cw-r STUB_IMPORT_FAIL=Imp.cls
check "reload: a failed import fails the run and names the file" "$rl_out" "$rl_rc" 1 '^FAIL WARM import: /opt/ocutalon/warm-src/ocutalon/cls/OcuTalon/Imp.cls: import boom$'
reload_case r12 "$tree" cw-r
check "reload: the file whose import failed is imported again" "$rl_out" "$rl_rc" 0 '^WARM reloaded 1, deleted 0$' '^WARM compiled every class .*: after a failed reload$'

# A session that prints nothing.
printf 'more\n' >> "$tree/src/ocutalon/cls/OcuTalon/Sub.cls"
reload_case r13 "$tree" cw-r STUB_EMPTY=1
check "reload: a session that prints nothing fails, and says so" "$rl_out" "$rl_rc" 1 '^FAIL WARM the IRIS session of ocutalon-warm-cw-r-1700000000-1 printed nothing$'
reload_case r14 "$tree" cw-r
check "reload: the changed class is imported on the next run, after a failed one" "$rl_out" "$rl_rc" 0 '^WARM reloaded 1, deleted 0$' '^WARM compiled every class'

# Any other input refuses the run, whatever kind of change it is.
stale_ok=1
printf 'changed\n' >> "$tree/docker/merge.cpf"
reload_case s1 "$tree" cw-r
check "reload: a changed merge file refuses the run" "$rl_out" "$rl_rc" 1 \
  '^FAIL WARM stale: docker/merge.cpf changed since warm up, and only classes reload: run ci/warm.sh down, then ci/warm.sh up$' '!^WARM reloaded'
[ "$rl_last" -eq 0 ] || fail "reload: a stale input still opened a session"
printf 'merge\n' > "$tree/docker/merge.cpf"
printf 'x\n' > "$tree/src/ocutalon/csp/new.js"
reload_case s2 "$tree" cw-r
check "reload: a new file of the web bundle refuses the run" "$rl_out" "$rl_rc" 1 '^FAIL WARM stale: src/ocutalon/csp/new.js changed since warm up'
rm "$tree/src/ocutalon/csp/new.js"
mv "$tree/src/module.xml" "$work/module.xml.away"
reload_case s3 "$tree" cw-r
check "reload: a removed module.xml refuses the run" "$rl_out" "$rl_rc" 1 '^FAIL WARM stale: src/module.xml changed since warm up'
mv "$work/module.xml.away" "$tree/src/module.xml"
printf 'changed\n' >> "$tree/ci/compose.ci.yml"
reload_case s4 "$tree" cw-r
check "reload: a changed stack compose file refuses the run" "$rl_out" "$rl_rc" 1 '^FAIL WARM stale: ci/compose.ci.yml changed since warm up'
printf 'services:\n' > "$tree/ci/compose.ci.yml"
reload_case s5 "$tree" cw-r
check "reload: with the inputs restored the run goes on" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$'
printf 'x\n' > "$tree/src/.DS_Store"
reload_case s6 "$tree" cw-r
check "reload: a .DS_Store is no input" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$'
printf 'changed\n' >> "$tree/ci/mock/server.mjs"
reload_case s7 "$tree" cw-r
check "reload: a changed file of the mock that the stack mounts refuses the run" "$rl_out" "$rl_rc" 1 '^FAIL WARM stale: ci/mock/server.mjs changed since warm up' '!^WARM reloaded'
printf 'server\n' > "$tree/ci/mock/server.mjs"
printf 'changed\n' >> "$tree/ci/mock/test/server.test.mjs"
reload_case s8 "$tree" cw-r
check "reload: a change to the mock's own node tests is no input" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 0$'
printf 'test\n' > "$tree/ci/mock/test/server.test.mjs"
mv "$(state_of cw-r)/manifest" "$work/manifest.away"
reload_case s9 "$tree" cw-r
check "reload: a missing stored manifest refuses the run" "$rl_out" "$rl_rc" 1 \
  '^FAIL WARM the stored manifest of tag cw-r is missing: run ci/warm.sh down, then ci/warm.sh up$' '!^WARM reloaded'
[ "$rl_last" -eq 0 ] || fail "reload: a missing stored manifest still opened a session"
mv "$work/manifest.away" "$(state_of cw-r)/manifest"

# Each of these starts from a tree and a state of its own.
own_fixture() { # own_fixture <tag>: a fresh tree, and the state of a warm stack that was built from it
  rm -rf "$work/tree-$1"
  mk_tree "$work/tree-$1"
  fixture_state "$1" "ocutalon-warm-$1-1700000000-1" "$work/tree-$1" "$work/tree-$1"
}
own_fixture cw-q1
rm "$work/tree-cw-q1/src/ocutalon/cls/OcuTalon/B.cls"
reload_case q1 "$work/tree-cw-q1" cw-q1 STUB_DELETE_FAIL=OcuTalon.B
check "reload: a failed delete fails the run, names the class, and counts nothing as deleted" "$rl_out" "$rl_rc" 1 \
  '^WARM reloaded 0, deleted 0$' '^FAIL WARM delete: OcuTalon.B: delete boom$'
if [ -f "$(state_of cw-q1)/failed" ] && grep -q ' src/ocutalon/cls/OcuTalon/B.cls$' "$(state_of cw-q1)/manifest"; then
  pass "reload: after a failed delete the marker is set and the class stays in the stored manifest"
else
  fail "reload: after a failed delete the marker is missing, or the class left the stored manifest"
fi
reload_case q2 "$work/tree-cw-q1" cw-q1
check "reload: the class whose delete failed is deleted again" "$rl_out" "$rl_rc" 0 '^WARM reloaded 0, deleted 1$' '^WARM compiled every class .*: after a delete$'
session_has 'Set d(1)="OcuTalon.B"' || fail "reload: the session did not delete OcuTalon.B again"
own_fixture cw-q3
printf 'changed\n' >> "$work/tree-cw-q3/src/ocutalon/cls/OcuTalon/A.cls"
reload_case q3 "$work/tree-cw-q3" cw-q3 STUB_NO_COMPILE=1
check "reload: a session that prints no compile result fails, and says so" "$rl_out" "$rl_rc" 1 \
  '^WARM reloaded 1, deleted 0$' '^FAIL WARM compile: the IRIS session of ocutalon-warm-cw-q3-1700000000-1 did not report the compile$'
[ -f "$(state_of cw-q3)/failed" ] || fail "reload: no failed marker after a session without a compile result"
own_fixture cw-q4
printf 'changed\n' >> "$work/tree-cw-q4/src/ocutalon/cls/OcuTalon/A.cls"
reload_case q4 "$work/tree-cw-q4" cw-q4 STUB_COMPILE_NOROWS=1
check "reload: a failed compile with no error text still says so, and exits 1" "$rl_out" "$rl_rc" 1 \
  '^WARM reloaded 1, deleted 0$' '^FAIL WARM compile: the compile of ocutalon-warm-cw-q4-1700000000-1 failed and gave no error text$'
[ -f "$(state_of cw-q4)/failed" ] || fail "reload: no failed marker after a compile that failed with no error text"

# --- the lock ---

locks=$work/locks
mkdir -p "$locks"
foreign='epic=9 stage=qa project=ocutalon-warm-foreign-1700000000-9 acquired_at=2026-10-19T00:00:00Z'
claim_run() { # claim_run <project> <env assignments...>: the derived claim in a process of its own (the derivation is installed there only)
  local p=$1
  shift
  (
    export OCUTALON_LOCK_DIR=$locks OCUTALON_LOCK_OWNER='epic=0 stage=qa'
    for kv in "$@"; do export "${kv?}"; done
    P=$p
    warm_lock_install || exit 9
    live_lock_claim
  ) 2>&1
}
rm -f "$locks"/*
out=$(claim_run ocutalon-warm-cw-l-1700000000-1)
rc=$?
check "lock: the derived claim takes warm-iris.lock and prints LOCK acquired warm-iris" "$out" "$rc" 0 '^LOCK acquired warm-iris project=ocutalon-warm-cw-l-1700000000-1$'
if grep -Eq '^epic=0 stage=qa project=ocutalon-warm-cw-l-1700000000-1 acquired_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$locks/warm-iris.lock" && [ ! -e "$locks/throwaway-iris.lock" ]; then
  pass "lock: warm-iris.lock holds '<owner> project=<P> acquired_at=<UTC>', and no throwaway-iris.lock is made"
else
  fail "lock: the content of warm-iris.lock is '$(cat "$locks/warm-iris.lock" 2> /dev/null)', or a throwaway lock was made ($(ls "$locks" | tr '\n' ' '))"
fi
holder=$(cat "$locks/warm-iris.lock")
[ -n "$holder" ] || fail "lock: the first claim made no warm-iris.lock"
out=$(claim_run ocutalon-warm-cw-l-1700000000-2 OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1)
rc=$?
check "lock: while warm-iris.lock is held the claim waits, then exits 75 naming the holder" "$out" "$rc" 75 \
  '^LOCK waiting: warm-iris is held by ' "^LOCK busy: warm-iris is held by 'epic=0 stage=qa project=ocutalon-warm-cw-l-1700000000-1 " '!^LOCK acquired'
if [ "$(cat "$locks/warm-iris.lock")" = "$holder" ]; then pass "lock: the held warm-iris.lock is left as it was"; else fail "lock: a busy claim changed the held lock"; fi
# lib-live's own claim, without the derivation, takes throwaway-iris.lock beside the warm lock, without waiting.
[ -s "$locks/warm-iris.lock" ] || fail "lock: warm-iris.lock is gone before the fresh stack's claim"
out=$(
{
  export OCUTALON_LOCK_DIR=$locks OCUTALON_LOCK_OWNER='epic=0 stage=qa' OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1
  P=ocutalon-class-cw-l-1700000000-3
  live_lock_claim
} 2>&1
)
rc=$?
check "lock: a fresh stack's claim takes throwaway-iris.lock while warm-iris.lock is held, with no wait" "$out" "$rc" 0 '^LOCK acquired throwaway-iris project=' '!^LOCK waiting'
rm -f "$locks/throwaway-iris.lock" "$locks/warm-iris.lock"
# And the other way: a held throwaway-iris.lock does not block the warm claim.
echo "$foreign" > "$locks/throwaway-iris.lock"
out=$(claim_run ocutalon-warm-cw-l-1700000000-4 OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1)
rc=$?
check "lock: a held throwaway-iris.lock does not block the warm claim" "$out" "$rc" 0 '^LOCK acquired warm-iris project=ocutalon-warm-cw-l-1700000000-4$' '!^LOCK waiting'
if [ "$(cat "$locks/throwaway-iris.lock")" = "$foreign" ]; then pass "lock: the held throwaway-iris.lock is left as it was"; else fail "lock: the warm claim changed throwaway-iris.lock"; fi
# The release removes the lock of its own project only.
rm -f "$locks"/*
echo "$foreign" > "$locks/throwaway-iris.lock"
out=$(
{
  export OCUTALON_LOCK_DIR=$locks OCUTALON_LOCK_OWNER='epic=0 stage=qa'
  P=ocutalon-warm-cw-l-1700000000-5
  warm_lock_install || exit 9
  live_lock_claim
  live_lock_release
  echo "AFTER=$(ls "$locks" | tr '\n' ' ')"
} 2>&1
)
rc=$?
check "lock: the release deletes warm-iris.lock (its own) and leaves throwaway-iris.lock" "$out" "$rc" 0 \
  '^LOCK acquired warm-iris project=ocutalon-warm-cw-l-1700000000-5$' '^LOCK released warm-iris project=ocutalon-warm-cw-l-1700000000-5$' '^AFTER=throwaway-iris.lock $'
rm -f "$locks"/*
out=$(
{
  export OCUTALON_LOCK_DIR=$locks OCUTALON_LOCK_OWNER='epic=0 stage=qa'
  P=ocutalon-warm-cw-l-1700000000-6
  warm_lock_install || exit 9
  live_lock_claim > /dev/null
  echo "$foreign" > "$locks/warm-iris.lock"
  live_lock_release
  echo "KEPT=$(cat "$locks/warm-iris.lock")"
} 2>&1
)
check "lock: the release keeps a warm-iris.lock that another project holds" "$out" $? 0 '^LOCK kept: warm-iris is not held by project ocutalon-warm-cw-l-1700000000-6$' "^KEPT=$foreign\$"
rm -f "$locks"/*
# The derivation fails closed.
out=$(
{
  warm_lock_text() { echo 'live_lock_claim() { echo throwaway-iris; }'; }
  warm_lock_install
} 2>&1
)
check "lock: a derivation that still names throwaway-iris fails closed" "$out" $? 1 '^FAIL WARM the warm lock could not be derived from lib-live.sh$'
out=$(
{
  warm_lock_text() { echo 'live_lock_claim() { echo nothing; }'; }
  warm_lock_install
} 2>&1
)
check "lock: a derivation that no longer names warm-iris.lock fails closed" "$out" $? 1 '^FAIL WARM the warm lock could not be derived from lib-live.sh$'
out=$(warm_lock_text)
if printf '%s\n' "$out" | grep -q 'warm-iris.lock' && ! printf '%s\n' "$out" | grep -q 'throwaway-iris' && printf '%s\n' "$out" | grep -q 'live_lock_claim' \
  && printf '%s\n' "$out" | grep -q 'live_lock_release'; then
  pass "lock: the derived text defines live_lock_claim and live_lock_release for warm-iris.lock, and names no throwaway-iris"
else
  fail "lock: the derived text of lib-live.sh is not the warm pair"
fi

# --- up ---

# up_run <tag> <lock dir> [env assignments...]: warm_up with the start stubbed. Sets up_out, up_rc, and the dc calls in $work/dc.calls.
up_run() {
  local tag=$1 lockd=$2
  shift 2
  : > "$work/dc.calls"
  : > "$work/live.calls"
  up_out=$(
    {
      export OCUTALON_RUN_TAG=$tag OCUTALON_LOCK_DIR=$lockd OCUTALON_LOCK_OWNER='epic=0 stage=qa'
      for kv in "$@"; do export "${kv?}"; done
      preflight() { :; }
      ensure_web_bundle() { return 0; }
      docker() { docker_stub "$@"; }
      dc() {
        echo "dc $*" >> "$work/dc.calls"
        if [ "$1" = up ] && [ "${STUB_UP_FAIL:-0}" = 1 ]; then return 1; fi
        return 0
      }
      warm_up
    } 2>&1
  )
  up_rc=$?
}
locku=$work/locks-up
mkdir -p "$locku"
up_run cw-u "$locku"
check "up: one project, the warm lock, the stack's lines and the WARM up line" "$up_out" "$up_rc" 0 \
  '^LOCK acquired warm-iris project=ocutalon-warm-cw-u-[0-9]{10}-[0-9]+$' '^STACK warm: project ocutalon-warm-cw-u-[0-9]{10}-[0-9]+$' \
  '^READY warm [0-9]+s$' '^WARM up project ocutalon-warm-cw-u-[0-9]{10}-[0-9]+ tag cw-u ready [0-9]+s$'
up_project=$(cat "$(state_of cw-u)/project" 2> /dev/null)
if grep -q "^epic=0 stage=qa project=$up_project acquired_at=" "$locku/warm-iris.lock" 2> /dev/null && [ "$(ls "$locku")" = warm-iris.lock ]; then
  pass "up: the lane folder holds warm-iris.lock naming the project, and nothing else"
else
  fail "up: the lane folder holds '$(ls "$locku" | tr '\n' ' ')', the lock is '$(cat "$locku/warm-iris.lock" 2> /dev/null)'"
fi
sd=$(state_of cw-u)
if [ -f "$sd/project" ] && [ -f "$sd/root" ] && [ -f "$sd/since" ] && [ -s "$sd/manifest" ] && [ -f "$sd/decoy.env" ] && [ -f "$sd/decoy.yml" ] && [ -f "$sd/warm.yml" ] \
  && [ "$(cat "$sd/root")" = "$root" ] && [ "$(grep -c . "$sd/files")" -eq 5 ] && [ "$(sed -n '2p' "$sd/files")" = "$sd/decoy.yml" ] && [ "$(sed -n '5p' "$sd/files")" = "$sd/warm.yml" ] \
  && grep -q -- '- ./src:/opt/ocutalon/warm-src:ro' "$sd/warm.yml"; then
  pass "up: the state holds the project, the root, the up time, the manifest and the five compose files (the override mounts ./src read-only)"
else
  fail "up: the state folder is incomplete: $(ls "$sd" | tr '\n' ' ')"
fi
if grep -q '^dc up -d --build --wait' "$work/dc.calls" && ! grep -q '^dc down' "$work/dc.calls"; then pass "up: the project is built and started, and not torn down"; else fail "up: the dc calls were '$(tr '\n' '|' < "$work/dc.calls")'"; fi
holder=$(cat "$locku/warm-iris.lock")
[ -n "$holder" ] || fail "up: the first up made no warm-iris.lock"
STUB_RUNNING=1 up_run cw-u "$locku"
check "up again: the stack is already up, with no new project, no lock line and no dc call" "$up_out" "$up_rc" 0 "^WARM up: project $up_project is already up\$" '!^LOCK' '!^STACK'
if [ ! -s "$work/dc.calls" ] && [ "$(cat "$locku/warm-iris.lock")" = "$holder" ]; then pass "up again: nothing was started and the lock is unchanged"; else fail "up again: dc was called or the lock changed"; fi
# A state whose stack is not running is torn down first, then up starts a new one.
STUB_RUNNING=0 STUB_PROJECTS=$up_project up_run cw-u "$locku" STUB_PROJECTS="$up_project"
check "up with the state of a stack that is not running: down first, then a new stack" "$up_out" "$up_rc" 0 \
  '^LOCK released warm-iris project=' '^TEARDOWN tag cw-u: 1 project\(s\) removed' '^WARM down tag cw-u$' '^LOCK acquired warm-iris project=' '^WARM up project '
rm -rf "$sd"
rm -f "$locku"/*
up_run cw-u2 "$work/no-such-lock-folder"
check "up with no lock folder: no LOCK line, and the stack starts" "$up_out" "$up_rc" 0 '!^LOCK' '^WARM up project ocutalon-warm-cw-u2-'
[ -f "$(state_of cw-u2)/project" ] || fail "up with no lock folder: no state"
rm -rf "$(state_of cw-u2)"
echo "$foreign" > "$locku/warm-iris.lock"
up_run cw-u3 "$locku" OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1
check "up beside a held warm-iris.lock: LOCK waiting, LOCK busy, exit 75, nothing starts" "$up_out" "$up_rc" 75 \
  '^LOCK waiting: warm-iris is held by ' "^LOCK busy: warm-iris is held by '$foreign'" '!^STACK' '!^WARM up'
if [ ! -s "$work/dc.calls" ] && [ ! -e "$(state_of cw-u3)" ] && [ "$(cat "$locku/warm-iris.lock")" = "$foreign" ]; then
  pass "up beside a held lock: no dc call, no state, and the lock is untouched"
else
  fail "up beside a held lock: dc was called, a state was made, or the lock changed"
fi
rm -f "$locku"/*
# A throwaway-iris.lock held by a fresh stack does not stop the warm up.
echo "$foreign" > "$locku/throwaway-iris.lock"
up_run cw-u4 "$locku" OCUTALON_LOCK_WAIT=1 OCUTALON_LOCK_SLEEP_MIN=1 OCUTALON_LOCK_SLEEP_MAX=1
check "up beside a held throwaway-iris.lock: it starts without waiting" "$up_out" "$up_rc" 0 '^LOCK acquired warm-iris project=' '!^LOCK waiting' '^WARM up project '
rm -rf "$(state_of cw-u4)"
rm -f "$locku"/*
# A failed up removes the project, releases the lock and leaves no state.
up_run cw-u5 "$locku" STUB_UP_FAIL=1
check "a failed up exits 1" "$up_out" "$up_rc" 1 '^LOCK acquired warm-iris project=' '^FAIL warm: the stack did not become ready$' '!^WARM up'
if [ -z "$(ls "$locku")" ] && [ ! -e "$(state_of cw-u5)" ] && grep -q '^dc down -v --rmi local' "$work/dc.calls"; then
  pass "a failed up removes the project, releases the lock (no lock file is left in the lane folder) and leaves no state folder"
else
  fail "a failed up left '$(ls "$locku" | tr '\n' ' ')' in the lane folder, the state '$(ls "$(state_of cw-u5)" 2> /dev/null | tr '\n' ' ')', dc calls '$(tr '\n' '|' < "$work/dc.calls")'"
fi
out=$(
{
  warm_lock_text() { echo 'live_lock_claim() { echo throwaway-iris; }'; }
  OCUTALON_RUN_TAG=cw-u6
  OCUTALON_LOCK_DIR=$locku
  preflight() { echo preflight; }
  live_start() { echo live_start; }
  warm_up
} 2>&1
)
check "a drifted lock derivation stops up before anything starts" "$out" $? 1 '^FAIL WARM the warm lock could not be derived from lib-live.sh$' '!^preflight' '!^live_start'

# A killed up: the signal runs the exit trap.
cat > "$work/kill-up.sh" << 'EOS'
echo $$ > "$WORK/kill-up.pid"
. "$ROOT/ci/iris.sh"
. "$ROOT/ci/warm.sh"
preflight() { :; }
ensure_web_bundle() { return 0; }
docker() { return 0; }
dc() {
  case $1 in
    up)
      sleep 30 &
      echo $! > "$WORK/kill-sleep.pid"
      : > "$WORK/kill-up.started"
      wait $!
      ;;
  esac
  return 0
}
warm_up
EOS
rm -f "$work/kill-up.started"
(ROOT=$root WORK=$work OCUTALON_RUN_TAG=cw-k OCUTALON_LOCK_DIR=$locku OCUTALON_LOCK_OWNER='epic=0 stage=qa' bash "$work/kill-up.sh" > "$work/kill-up.out" 2>&1) &
kill_pid=$!
waited=0
while [ ! -f "$work/kill-up.started" ] && [ "$waited" -lt 150 ]; do
  sleep 0.2
  waited=$((waited + 1))
done
kill -TERM "$(cat "$work/kill-up.pid")" 2> /dev/null
wait "$kill_pid"
kill_rc=$?
kill "$(cat "$work/kill-sleep.pid" 2> /dev/null)" 2> /dev/null
if [ "$kill_rc" -eq 130 ] && [ -z "$(ls "$locku")" ] && [ ! -e "$(state_of cw-k)" ]; then
  pass "a killed up exits 130, releases the lock and leaves no state folder"
else
  fail "a killed up exited $kill_rc, left '$(ls "$locku" | tr '\n' ' ')' in the lane folder and the state '$(ls "$(state_of cw-k)" 2> /dev/null | tr '\n' ' ')': $(tr '\n' '|' < "$work/kill-up.out" | head -c 300)"
fi

# --- down and status ---

locdown=$work/locks-down
mkdir -p "$locdown"
dproj=ocutalon-warm-cw-d-1700000000-1
fixture_state cw-d "$dproj"
printf 'epic=0 stage=qa project=%s acquired_at=2026-10-23T00:00:00Z\n' "$dproj" > "$locdown/warm-iris.lock"
down_run() { # down_run <projects the stub lists>: warm_down for tag cw-d
  out=$(
  {
    export OCUTALON_RUN_TAG=cw-d OCUTALON_LOCK_DIR=$locdown STUB_PROJECTS="$1"
    docker() { docker_stub "$@"; }
    warm_down
  } 2>&1
  )
  rc=$?
}
down_run "$dproj"
check "down: the tag's teardown runs, the warm lock is released, the state goes, and WARM down is the last line" "$out" "$rc" 0 \
  "^LOCK released warm-iris project=$dproj\$" '^TEARDOWN tag cw-d: 1 project\(s\) removed' '^WARM down tag cw-d$'
if [ "$(printf '%s\n' "$out" | tail -n 1)" = "WARM down tag cw-d" ] && [ ! -e "$locdown/warm-iris.lock" ] && [ ! -e "$(state_of cw-d)" ]; then
  pass "down: the lock file and the state folder are gone"
else
  fail "down: the lock file or the state folder is left"
fi
down_run ""
check "down again: nothing to remove, and WARM down all the same" "$out" "$rc" 0 '^TEARDOWN tag cw-d: 0 project\(s\) removed' '^WARM down tag cw-d$'
fixture_state cw-d "$dproj"
printf 'epic=0 stage=qa project=ocutalon-warm-cw-dx-1700000000-1 acquired_at=2026-10-23T00:00:00Z\n' > "$locdown/warm-iris.lock"
down_run "$dproj"
if [ -e "$locdown/warm-iris.lock" ] && ! printf '%s\n' "$out" | grep -q '^LOCK released'; then
  pass "down keeps a warm lock that names a project of another tag"
else
  fail "down released the lock of another tag"
fi
rm -f "$locdown"/*

status_run() { # status_run <tag> <running: 1|0>
  out=$(
  {
    export OCUTALON_RUN_TAG=$1 STUB_RUNNING=$2
    docker() { docker_stub "$@"; }
    warm_status
  } 2>&1
  )
  rc=$?
}
fixture_state cw-s ocutalon-warm-cw-s-1700000000-1
status_run cw-s 1
check "status: a running stack is reported with its project, tag and up time" "$out" "$rc" 0 '^WARM up project=ocutalon-warm-cw-s-1700000000-1 tag=cw-s since=2026-10-23T00:00:00Z$'
status_run cw-s 0
check "status: a stack that is not running is none, with exit 1" "$out" "$rc" 1 '^WARM none for tag cw-s$'
status_run cw-s-none 1
check "status: a tag with no state is none, with exit 1" "$out" "$rc" 1 '^WARM none for tag cw-s-none$'

# ci/warm.sh run as a command: the dispatcher itself, with the stub docker first on the PATH and a lane folder of its own.
cmd_run() { # cmd_run <tag> <running: 1|0> <command>
  : > "$work/cli.calls"
  out=$(env -u OCUTALON_WARM -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME OCUTALON_RUN_TAG="$1" STUB_RUNNING="$2" OCUTALON_LOCK_DIR="$work/locks-cli" \
    PATH="$work/bin:$PATH" bash "$root/ci/warm.sh" "$3" 2>&1)
  rc=$?
}
fixture_state cw-c1 ocutalon-warm-cw-c1-1700000000-1
cmd_run cw-c1 1 status
check "ci/warm.sh status, run as a command, reports a running stack and exits 0" "$out" "$rc" 0 \
  '^WARM up project=ocutalon-warm-cw-c1-1700000000-1 tag=cw-c1 since=2026-10-23T00:00:00Z$' '!^LOCK' '!^STACK'
cmd_run cw-c1 0 status
check "ci/warm.sh status, run as a command, says none for a stack that is not running and exits 1" "$out" "$rc" 1 '^WARM none for tag cw-c1$' '!^WARM up'
cmd_run cw-c1 0 down
check "ci/warm.sh down, run as a command, tears the tag down and ends with WARM down" "$out" "$rc" 0 '^TEARDOWN tag cw-c1: 0 project\(s\) removed' '^WARM down tag cw-c1$'
if [ -e "$(state_of cw-c1)" ]; then fail "ci/warm.sh down, run as a command, left the state folder"; else pass "ci/warm.sh down, run as a command, removed the state folder"; fi

if [ "$fails" -ne 0 ]; then
  echo "test-ci-warm: $fails check(s) failed"
  exit 1
fi
echo "test-ci-warm: all checks passed"
