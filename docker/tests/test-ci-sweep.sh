#!/usr/bin/env bash
# Pins of the sweep of a runner's web port (Story 25.7, DW-1335; AD-22): `ci/iris.sh build` removes every throwaway compose project that
# publishes the runner's fixed web port, on a self-hosted CI runner only. Prints one PASS or FAIL line per check; exits 0 only when all pass.
#
# bash docker/tests/test-ci-sweep.sh            hermetic (the hosted `checks` job runs it). It starts no container and calls no real docker:
#                                              `docker` is an executable stub first on PATH (live_bounded runs `timeout 10 docker`, which
#                                              bypasses a shell function) that reads a table of name|project|port|state and records every
#                                              call. Each case runs the real cmd_build of a sourced ci/iris.sh with preflight and
#                                              ensure_web_bundle stubbed, then the real live_web_port. The cases:
#   - a leftover on the runner's own port (derived from RUNNER_NAME, and a preset one) goes down as a whole project, port-less mock
#     included, with teardown's files and `down -v --rmi local --remove-orphans`, before the bundle step, and the port then binds; a stack
#     on another port and a port-less project are never named; a project with two holders comes down once;
#   - nothing on the port; auto mode, a local run, a hosted runner and a bad preset print `SWEEP off: ...` and make no docker call;
#   - a compose project that is not a throwaway (slot, other name), a slot-shaped name and a non-compose container are kept and logged;
#   - a removal that does not take (one `rm -f -v` of that container, then SWEEP FAIL when it stays) and a listing that fails never fail
#     the build;
#   - registration (Rule 8): ci-sweep is in CHECK_SCRIPTS only, and this script is executable; --live refuses GITHUB_ACTIONS=true.
#
# bash docker/tests/test-ci-sweep.sh --live    the developer machine only, never CI: real containers of its own. It needs a reachable
#                                              daemon and the mock's image (never pulled), picks two free ports A and B of 52806-52819,
#                                              plants three throwaway projects (A: iris on 127.0.0.1:A plus a port-less mock, B the same on
#                                              B, C port-less), runs the real job start for A (CI env, OCUTALON_TEST_WEB_PORT=A) and asserts
#                                              that A's project is gone, B and C still run, B still publishes B, the mock image stays and
#                                              live_web_port binds A. Its EXIT trap downs exactly its three projects. About 20-40 s.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/ci/iris.sh"

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
    fail "$label:$bad (output: $(printf '%s' "$out" | tr '\n' '|' | head -c 600))"
  fi
}

# --- the live mode ---

# The cleanup runs at EXIT, after sweep_live has returned: its folder and project names are globals.
sweep_d=""
sweep_pa=""
sweep_pb=""
sweep_pc=""
sweep_live() {
  local t=${OCUTALON_RUN_TAG:-sweep} img a="" b="" port i out rc epoch pidn names holders
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "test-ci-sweep --live runs on a developer machine only, never in CI"
    return 2
  fi
  if ! live_tag_ok "$t"; then
    echo "FAIL OCUTALON_RUN_TAG '$t' $LIVE_TAG_RULE"
    return 2
  fi
  if ! docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
    echo "FAIL live: no reachable Docker daemon"
    return 1
  fi
  img=$(mock_image)
  if [ -z "$img" ] || ! docker image inspect --format '{{.Id}}' "$img" >/dev/null 2>&1; then
    echo "FAIL live: the mock's image is not on this machine (it is never pulled): $img"
    return 1
  fi
  for port in $(seq 52819 -1 52806); do
    if port_in_use "$port"; then continue; fi
    if [ -n "$(docker ps -a --filter "publish=$port" --format '{{.Names}}' 2>/dev/null)" ]; then continue; fi
    if [ -z "$a" ]; then a=$port; elif [ -z "$b" ]; then b=$port; break; fi
  done
  if [ -z "$b" ]; then
    echo "FAIL live: no two free ports in 52806-52819"
    return 1
  fi
  epoch=$(date +%s)
  pidn=$$
  sweep_pa="ocutalon-sweepa-$t-$epoch-$pidn"
  sweep_pb="ocutalon-sweepb-$t-$epoch-$pidn"
  sweep_pc="ocutalon-sweepc-$t-$epoch-$pidn"
  sweep_d=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-sweep.XXXXXX") || return 1
  live_cleanup_sweep() {
    trap - EXIT INT TERM HUP
    for i in a b c; do
      if [ -f "$sweep_d/$i.yml" ]; then
        case $i in a) names=$sweep_pa ;; b) names=$sweep_pb ;; *) names=$sweep_pc ;; esac
        docker compose -p "$names" -f "$sweep_d/$i.yml" down -v -t 0 --remove-orphans >/dev/null 2>&1
      fi
    done
    rm -rf "$sweep_d"
  }
  trap live_cleanup_sweep EXIT
  trap 'exit 130' INT TERM HUP
  # plant <file> <port or empty>: a compose file with a mock service and, with a port, an iris service that publishes it.
  plant() {
    {
      printf 'services:\n'
      if [ -n "$2" ]; then
        printf '  iris:\n    image: %s\n    init: true\n    command: ["sleep", "300"]\n    ports:\n      - "127.0.0.1:%s:52773"\n' "$img" "$2"
      fi
      printf '  mock:\n    image: %s\n    init: true\n    command: ["sleep", "300"]\n' "$img"
    } > "$1"
  }
  plant "$sweep_d/a.yml" "$a"
  plant "$sweep_d/b.yml" "$b"
  plant "$sweep_d/c.yml" ""
  for i in a b c; do
    case $i in a) names=$sweep_pa ;; b) names=$sweep_pb ;; *) names=$sweep_pc ;; esac
    if ! out=$(docker compose -p "$names" -f "$sweep_d/$i.yml" up -d --pull never 2>&1); then
      fail "live: planting $names failed: $(printf '%s' "$out" | tr '\n' '|' | head -c 400)"
      return 1
    fi
  done
  for i in $(seq 1 20); do
    if port_in_use "$a"; then break; fi
    sleep 1
  done
  if ! port_in_use "$a"; then
    fail "live: port $a is not in use 20 s after the plant"
    return 1
  fi
  holders=$(docker ps -a --filter "publish=$a" --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | sort -u)
  if [ "$holders" != "$sweep_pa" ]; then
    fail "live: the holders of $a are '$(printf '%s' "$holders" | tr '\n' ' ')', not exactly $sweep_pa: no sweep was run"
    return 1
  fi
  out=$(
    export GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted OCUTALON_TEST_WEB_PORT=$a
    unset GITHUB_JOB RUNNER_NAME OCUTALON_RUN_TAG OCUTALON_WARM
    preflight() { :; }
    ensure_web_bundle() { return 0; }
    cmd_build
    LIVE_PORT_WAIT=0
    tmp=$sweep_d/lw
    mkdir -p "$tmp"
    LIVE_FILES=()
    live_web_port
    echo "LWP rc=$? web_port=${web_port:-}"
  )
  rc=$?
  check "live: the real job start for $a removes its project, logs it, and builds" "$out" "$rc" 0 \
    "^SWEEP removed project $sweep_pa \\(it published 127\\.0\\.0\\.1:$a\\)$" '^BUILD ' "^LWP rc=0 web_port=$a$"
  if [ -z "$(docker ps -a --filter "label=com.docker.compose.project=$sweep_pa" --format '{{.Names}}' 2>/dev/null)" ]; then
    pass "live: nothing of the project of $a is left, its port-less mock included"
  else
    fail "live: a container of $sweep_pa is left"
  fi
  if [ -n "$(docker ps --filter "label=com.docker.compose.project=$sweep_pb" --filter "publish=$b" --format '{{.Names}}' 2>/dev/null)" ]; then
    pass "live: the project on $b still runs and still publishes $b"
  else
    fail "live: the project on $b does not run or does not publish $b any more"
  fi
  if [ -n "$(docker ps --filter "label=com.docker.compose.project=$sweep_pc" --format '{{.Names}}' 2>/dev/null)" ]; then
    pass "live: the port-less project still runs"
  else
    fail "live: the port-less project does not run any more"
  fi
  if docker image inspect --format '{{.Id}}' "$img" >/dev/null 2>&1; then
    pass "live: the mock's image is still on the machine"
  else
    fail "live: the mock's image is gone"
  fi
  if [ "$fails" -ne 0 ]; then
    echo "test-ci-sweep: $fails live check(s) failed"
    return 1
  fi
  echo "test-ci-sweep: all live checks passed"
}

case ${1:-} in
  --live)
    sweep_live
    exit $?
    ;;
  '') ;;
  *)
    echo "usage: bash docker/tests/test-ci-sweep.sh [--live]"
    exit 2
    ;;
esac

# --- the hermetic mode ---

work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cs.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# The stub: name|project|port|state rows in $STUB_TABLE; every call is appended to $STUB_CALLS.
cat > "$work/bin/docker" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$STUB_CALLS"
drop_project() { awk -F'|' -v p="$1" '$2 != p' "$STUB_TABLE" > "$STUB_TABLE.new" && mv "$STUB_TABLE.new" "$STUB_TABLE"; }
drop_name() { awk -F'|' -v n="$1" '$1 != n' "$STUB_TABLE" > "$STUB_TABLE.new" && mv "$STUB_TABLE.new" "$STUB_TABLE"; }
case ${1:-} in
  ps)
    n=$(grep -c '^ps ' "$STUB_CALLS")
    if [ "${STUB_PS_FAIL:-0}" = 1 ]; then exit 1; fi
    if [ -n "${STUB_PS_FAIL_FROM:-}" ] && [ "$n" -ge "$STUB_PS_FAIL_FROM" ]; then exit 1; fi
    shift
    fmt=""
    filt=""
    while [ $# -gt 0 ]; do
      case $1 in
        --filter) filt=$2; shift ;;
        --format) fmt=$2; shift ;;
      esac
      shift
    done
    tn='{{.Names}}'
    tl='{{.Label "com.docker.compose.project"}}'
    ts='{{.Status}}'
    while IFS='|' read -r name proj port state; do
      [ -n "$name" ] || continue
      case $filt in
        publish=*) [ "$port" = "${filt#publish=}" ] || continue ;;
        label=com.docker.compose.project) [ -n "$proj" ] || continue ;;
      esac
      line=${fmt//"$tn"/$name}
      line=${line//"$tl"/$proj}
      line=${line//"$ts"/$state}
      printf '%s\n' "$line"
    done < "$STUB_TABLE"
    ;;
  compose)
    proj=""
    prev=""
    for a in "$@"; do
      if [ "$prev" = -p ]; then proj=$a; fi
      prev=$a
    done
    if [ "${STUB_DOWN_KEEPS:-0}" != 1 ]; then drop_project "$proj"; fi
    ;;
  rm)
    eval "last=\${$#}"
    if [ "${STUB_RM_KEEPS:-0}" != 1 ]; then drop_name "$last"; fi
    ;;
esac
exit 0
EOS
chmod +x "$work/bin/docker"
PATH="$work/bin:$PATH"
if [ "$(command -v docker)" != "$work/bin/docker" ]; then
  echo "FAIL the docker on PATH is not this test's stub ($(command -v docker)): no case was run"
  exit 1
fi

# run_case <name> <table text> [VAR=value ...]: the real cmd_build and then the real live_web_port, in a subshell with the CI variables
# unset and then those given. Sets out (the output), rc (the build's exit code), calls (the stub's call log) and table (what is left).
run_case() {
  local d="$work/case-$1" a
  rm -rf "$d"
  mkdir -p "$d/tmp" "$d/lw"
  printf '%s' "$2" > "$d/table"
  : > "$d/calls"
  shift 2
  out=$(
    unset GITHUB_ACTIONS RUNNER_ENVIRONMENT RUNNER_NAME OCUTALON_TEST_WEB_PORT OCUTALON_RUN_TAG OCUTALON_WARM GITHUB_JOB
    export TMPDIR="$d/tmp" STUB_TABLE="$d/table" STUB_CALLS="$d/calls"
    for a in "$@"; do export "$a"; done
    preflight() { :; }
    ensure_web_bundle() { echo "BUNDLE step"; return 0; }
    port_in_use() { awk -F'|' -v p="$1" '$3 == p { f = 1 } END { exit !f }' "$STUB_TABLE"; }
    cmd_build
    echo "BUILD-RC $?"
    LIVE_PORT_WAIT=0
    tmp="$d/lw"
    LIVE_FILES=()
    web_port=""
    live_web_port
    echo "LWP rc=$? web_port=$web_port"
  ) 2>&1
  rc=$(printf '%s\n' "$out" | sed -n 's/^BUILD-RC //p')
  calls=$(cat "$d/calls")
  table=$(cat "$d/table")
}

ci_env="GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted"

pa=ocutalon-demo-path-43593749725-1-browser-1794600000-123
pb=ocutalon-floor-9-1-shards-1794600000-7
pc=ocutalon-class-abc-1-1794600000-9
table_a="$pa-iris-1|$pa|52814|Up 3 minutes
$pa-mock-1|$pa||Up 3 minutes
$pb-iris-1|$pb|52813|Up 1 minute
$pc-mock-1|$pc||Up 1 minute
"
down_re="^compose -p $pa -f .*/docker-compose\\.yml -f .*/docker/tests/compose\\.throwaway\\.yml -f .*/ci/compose\\.ci\\.yml down -v --rmi local --remove-orphans\$"

# line_of <regex>: the first line number of the output that matches.
line_of() { printf '%s\n' "$out" | grep -En -- "$1" | head -n 1 | cut -d: -f1; }

# 1. A leftover on the runner's own port.
run_case own "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4
check "leftover on own port: the project comes down, SWEEP removed is logged, the build exits 0 and the port then binds" "$out" "${rc:-9}" 0 \
  "^SWEEP removed project $pa \\(it published 127\\.0\\.0\\.1:52814\\)\$" '^BUNDLE step$' '^BUILD ' '^LWP rc=0 web_port=52814$' '!SWEEP FAIL' '!SWEEP kept'
check "leftover on own port: one down with teardown's files and options, and no rm" "$calls" 0 0 "$down_re" '!^rm '
if [ "$(printf '%s\n' "$calls" | grep -c -E -- "$down_re")" -eq 1 ] && [ "$(printf '%s\n' "$calls" | grep -c '^compose ')" -eq 1 ]; then
  pass "leftover on own port: exactly one compose call"
else
  fail "leftover on own port: the compose calls were '$(printf '%s' "$calls" | tr '\n' '|')'"
fi
if [ "$(line_of '^SWEEP removed project')" -lt "$(line_of '^BUNDLE step$')" ] && [ "$(line_of '^BUNDLE step$')" -lt "$(line_of '^BUILD ')" ]; then
  pass "leftover on own port: the SWEEP line comes before the bundle step and the BUILD line follows"
else
  fail "leftover on own port: the order of the lines is wrong: $(printf '%s' "$out" | tr '\n' '|')"
fi
check "leftover on own port: the 52813 project survives and the port-less project is never named" "$calls" 0 0 "!52813" "!$pb" "!$pc"
if printf '%s\n' "$table" | grep -q "^$pb-iris-1|" && printf '%s\n' "$table" | grep -q "^$pc-mock-1|" && ! printf '%s\n' "$table" | grep -q "^$pa"; then
  pass "leftover on own port: the table keeps the 52813 and port-less projects and loses the leftover with its mock"
else
  fail "leftover on own port: the table is '$(printf '%s' "$table" | tr '\n' '|')'"
fi

# A project with two holders of the port comes down once.
run_case two "$pa-iris-1|$pa|52814|Up
$pa-iris-2|$pa|52814|Up
" $ci_env RUNNER_NAME=ocutalon-ci-4
if [ "$(printf '%s\n' "$calls" | grep -c '^compose ')" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^SWEEP removed project')" -eq 1 ]; then
  pass "two holders: a project that holds the port twice comes down once and is logged once"
else
  fail "two holders: calls '$(printf '%s' "$calls" | tr '\n' '|')', output '$(printf '%s' "$out" | tr '\n' '|')'"
fi

# 2. Nothing on the port.
run_case none "" $ci_env RUNNER_NAME=ocutalon-ci-4
check "nothing on the port: no leftover is logged, nothing comes down, the build exits 0" "$out" "${rc:-9}" 0 \
  '^SWEEP 127\.0\.0\.1:52814: no leftover$' '^BUNDLE step$' '^BUILD ' '^LWP rc=0 web_port=52814$'
check "nothing on the port: the only docker call is the listing" "$calls" 0 0 '^ps -a --filter publish=52814 --format ' '!^compose' '!^rm '

# 3. A preset port.
run_case preset "$(printf '%s-iris-1|%s|52805|Up\n' "$pa" "$pa")
" $ci_env RUNNER_NAME=ocutalon-ci-20 OCUTALON_TEST_WEB_PORT=52805
check "preset port: a leftover on 52805 is removed" "$out" "${rc:-9}" 0 \
  "^SWEEP removed project $pa \\(it published 127\\.0\\.0\\.1:52805\\)\$" '^LWP rc=0 web_port=52805$'

# 4. Auto mode.
run_case auto20 "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-20
check "auto mode: runner 20 with no preset prints SWEEP off and makes no docker call" "$out" "${rc:-9}" 0 '^SWEEP off: no fixed web port$' '^BUILD ' '!^SWEEP removed'
[ -z "$calls" ] && pass "auto mode: runner 20 made no docker call" || fail "auto mode: runner 20 made calls: $(printf '%s' "$calls" | tr '\n' '|')"
run_case autonone "$table_a" $ci_env
check "auto mode: no runner name prints SWEEP off and makes no docker call" "$out" "${rc:-9}" 0 '^SWEEP off: no fixed web port$' '^BUILD '
[ -z "$calls" ] && pass "auto mode: no runner name made no docker call" || fail "auto mode: no runner name made calls: $(printf '%s' "$calls" | tr '\n' '|')"

# 5. A local run.
local_table="$(printf '%s-iris-1|%s|52803|Up\n' "$pa" "$pa")
"
for variant in "unset" "hosted" "norunnerenv"; do
  case $variant in
    unset) run_case "local-$variant" "$local_table" OCUTALON_TEST_WEB_PORT=52803 ;;
    hosted) run_case "local-$variant" "$local_table" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted OCUTALON_TEST_WEB_PORT=52803 ;;
    norunnerenv) run_case "local-$variant" "$local_table" GITHUB_ACTIONS=true OCUTALON_TEST_WEB_PORT=52803 ;;
  esac
  check "local run ($variant): SWEEP off, no docker call, the project is kept" "$out" "${rc:-9}" 0 '^SWEEP off: not a self-hosted CI runner$' '^BUILD '
  if [ -z "$calls" ] && printf '%s\n' "$table" | grep -q "^$pa-iris-1|"; then
    pass "local run ($variant): no docker call and the project is kept"
  else
    fail "local run ($variant): calls '$(printf '%s' "$calls" | tr '\n' '|')', table '$(printf '%s' "$table" | tr '\n' '|')'"
  fi
done

# 6. A bad preset.
for bad in 52773 60000 abc 528140 ""; do
  run_case "bad-$bad" "$(printf '%s-iris-1|%s|%s|Up\n' "$pa" "$pa" "${bad:-52814}")
" $ci_env RUNNER_NAME=ocutalon-ci-4 OCUTALON_TEST_WEB_PORT="$bad"
  if [ -z "$bad" ]; then
    check "bad preset (empty): the derived port 52814 is used, as with no preset" "$out" "${rc:-9}" 0 "^SWEEP removed project $pa "
    continue
  fi
  check "bad preset '$bad': SWEEP off names the value, the build exits 0, live_web_port still refuses it" "$out" "${rc:-9}" 0 \
    "^SWEEP off: .*'$bad'" '^BUILD ' '^FAIL live_web_port' '^LWP rc=1 '
  [ -z "$calls" ] && pass "bad preset '$bad': no docker call" || fail "bad preset '$bad': calls: $(printf '%s' "$calls" | tr '\n' '|')"
done

# 7. Holders that are not throwaways.
pslot=ocutalon-slot-x
pslot2=ocutalon-slot-a-1794600000-5
pother=other-proj-1794600000-1
pdev=ocutalon-dev-stack
pshort=ocutalon-demo-123-45
run_case notaway "$pslot-iris-1|$pslot|52814|Up
$pslot2-iris-1|$pslot2|52814|Up
$pother-iris-1|$pother|52814|Up
$pdev-iris-1|$pdev|52814|Up
$pshort-iris-1|$pshort|52814|Up
plain-container||52814|Up
" $ci_env RUNNER_NAME=ocutalon-ci-4
check "not a throwaway: each holder gets a SWEEP kept line with its reason, and the build exits 0" "$out" "${rc:-9}" 0 \
  "^SWEEP kept $pslot-iris-1 project=$pslot: not a throwaway project\$" \
  "^SWEEP kept $pslot2-iris-1 project=$pslot2: not a throwaway project\$" \
  "^SWEEP kept $pother-iris-1 project=$pother: not a throwaway project\$" \
  "^SWEEP kept $pdev-iris-1 project=$pdev: not a throwaway project\$" \
  "^SWEEP kept $pshort-iris-1 project=$pshort: not a throwaway project\$" \
  '^SWEEP kept plain-container project=none: not a compose project$' '^BUILD ' '!^SWEEP removed'
check "not a throwaway: no down and no rm" "$calls" 0 0 '!^compose' '!^rm '
if [ "$(printf '%s\n' "$table" | grep -c .)" -eq 6 ]; then pass "not a throwaway: all six holders are still in the table"; else fail "not a throwaway: the table is '$(printf '%s' "$table" | tr '\n' '|')'"; fi

# 8. A removal that does not take.
run_case rm1 "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4 STUB_DOWN_KEEPS=1
check "removal does not take: the down leaves the container, one rm -f -v of that container removes it, the project is logged removed" "$out" "${rc:-9}" 0 \
  "^SWEEP removed project $pa " '!SWEEP FAIL' '^BUILD '
if [ "$(printf '%s\n' "$calls" | grep -c '^rm ')" -eq 1 ] && printf '%s\n' "$calls" | grep -qx "rm -f -v $pa-iris-1"; then
  pass "removal does not take: exactly one rm -f -v of the project's container on the port"
else
  fail "removal does not take: calls '$(printf '%s' "$calls" | tr '\n' '|')'"
fi
run_case rm2 "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4 STUB_DOWN_KEEPS=1 STUB_RM_KEEPS=1
check "removal does not take: a container that stays is a SWEEP FAIL, never a failed build" "$out" "${rc:-9}" 0 \
  "^SWEEP FAIL 127\\.0\\.0\\.1:52814 still published by $pa-iris-1\$" '^BUNDLE step$' '^BUILD ' '!^SWEEP removed'
if [ "$(printf '%s\n' "$calls" | grep -c '^rm ')" -eq 1 ] && ! printf '%s\n' "$calls" | grep -q "$pb"; then
  pass "removal does not take: one rm only, and no other project is named"
else
  fail "removal does not take: calls '$(printf '%s' "$calls" | tr '\n' '|')'"
fi

# 9. A listing that fails.
run_case psfail "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4 STUB_PS_FAIL=1
check "listing fails: SWEEP FAIL, no down, the build goes on and exits 0" "$out" "${rc:-9}" 0 \
  '^SWEEP FAIL could not list what publishes 127\.0\.0\.1:52814$' '^BUNDLE step$' '^BUILD '
check "listing fails: nothing is removed" "$calls" 0 0 '!^compose' '!^rm '
run_case psfail2 "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4 STUB_PS_FAIL_FROM=2
check "listing fails after the down: SWEEP FAIL, no removed line, the build exits 0" "$out" "${rc:-9}" 0 \
  '^SWEEP FAIL could not list what publishes 127\.0\.0\.1:52814$' '^BUILD ' '!^SWEEP removed'

run_case psfail3 "$table_a" $ci_env RUNNER_NAME=ocutalon-ci-4 STUB_DOWN_KEEPS=1 STUB_PS_FAIL_FROM=3
check "listing fails after the rm: SWEEP FAIL, no removed line, the build exits 0" "$out" "${rc:-9}" 0 \
  '^SWEEP FAIL could not list what publishes 127\.0\.0\.1:52814$' '^BUILD ' '!^SWEEP removed'

# --- registration (Rule 8) and the live mode's refusal in CI ---

in_list() { printf '%s\n' $1 | grep -qxF -- "$2"; }
reg_bad=""
in_list "$CHECK_SCRIPTS" ci-sweep || reg_bad="$reg_bad [ci-sweep is not in CHECK_SCRIPTS]"
if [ "$(printf '%s\n' $CHECK_SCRIPTS | grep -cxF ci-sweep)" -gt 1 ]; then reg_bad="$reg_bad [ci-sweep is in CHECK_SCRIPTS twice]"; fi
if in_list "$WEB_SCRIPTS" ci-sweep; then reg_bad="$reg_bad [ci-sweep is in WEB_SCRIPTS]"; fi
for reg_g in $IRIS_GROUPS; do
  if in_list "$(group_units "$reg_g")" live:ci-sweep; then reg_bad="$reg_bad [ci-sweep is a live unit of the group $reg_g]"; fi
done
[ -x docker/tests/test-ci-sweep.sh ] || reg_bad="$reg_bad [docker/tests/test-ci-sweep.sh is not executable]"
if [ -z "$reg_bad" ]; then
  pass "registration: ci-sweep is in CHECK_SCRIPTS only (ci/checks.sh runs it with no argument: the hermetic mode), and this script is executable"
else
  fail "registration:$reg_bad"
fi

: > "$work/live.calls"
live_out=$(GITHUB_ACTIONS=true STUB_TABLE="$work/live.table" STUB_CALLS="$work/live.calls" bash docker/tests/test-ci-sweep.sh --live 2>&1)
live_rc=$?
if [ "$live_rc" -eq 2 ] && [ ! -s "$work/live.calls" ]; then
  pass "--live with GITHUB_ACTIONS=true exits 2 and makes no docker call"
else
  fail "--live with GITHUB_ACTIONS=true: exit $live_rc, calls '$(tr '\n' '|' < "$work/live.calls")', output '$(printf '%s' "$live_out" | tr '\n' '|' | head -c 300)'"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-ci-sweep: $fails check(s) failed"
  exit 1
fi
echo "test-ci-sweep: all checks passed"
