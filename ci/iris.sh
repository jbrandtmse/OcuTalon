#!/usr/bin/env bash
# The IRIS test recipe (Story 0.7): runs the IRIS units on the CI runner and on a developer machine, piece by piece or by group,
# always in throwaway compose projects (docker/tests/lib-live.sh) with the CI override (ci/compose.ci.yml). It never names a
# developer instance or a slot, and it never pushes, saves or caches an image. The IRIS base image is never pulled: it must already
# be on the machine. The mock's public image (Story 0.11; node, pinned by digest) is pulled once per machine by preflight and kept.
#
#   ci/iris.sh list                       the check scripts, the web scripts, the shards and the groups with their units
#   ci/iris.sh groups                     the group names, one per line (the matrix of .github/workflows/ci.yml)
#   ci/iris.sh classes [shard]            the test classes of a shard (of every shard), one per line, in name order
#   ci/iris.sh port                       the web port that the browser units would publish: 52810 + n (runners 0 to 9), 52819 - n (10 to 19), or auto
#   ci/iris.sh build                      checks the base image and builds the web bundle from this checkout
#   ci/iris.sh shard <name> [--reverse]   one throwaway; every test class of the shard's areas through %UnitTest.Manager, in
#                                         name order (reversed with --reverse); one "CLASS <name> passed|failed <s>s" line each
#   ci/iris.sh class <Class>              the same for one test class
#   ci/iris.sh live <name>                docker/tests/test-<name>.sh with the run tag; it first prints "PORT ..." with the web port
#                                         and, for a browser unit (a name in BROWSER_UNITS of ci/units.sh), first installs Chromium
#   ci/iris.sh group <name>               the units of a group in order, each in its own process and project; one
#                                         "UNIT <unit> passed|failed <s>s" line each; exit 1 naming the failed units
#   ci/iris.sh teardown                   removes only the projects, volumes, networks and images of the tag (ocutalon-<label>-<tag>-<epoch>-<pid>)
#   ci/iris.sh all                        every group in turn
# OCUTALON_RUN_TAG (lower-case letters, digits and hyphens, at least 3 characters, no "slot") names the run: the pieces of one run
# share it and `teardown` needs it. It defaults to local-<epoch>-<pid>, which makes each call its own run. In CI the web port of
# the browser units follows the number n at the end of RUNNER_NAME: 52810 + n for n from 0 to 9 and 52819 - n for n from 10 to 19
# (52809 down to 52800), so runners 1 to 19 never share a port on one host. Otherwise (n of 20 or more, no number, no RUNNER_NAME, as
# on a developer machine) the browser units probe for the first free port of 52800-52819, which a fixed-port runner of the same host
# may be about to publish. A set OCUTALON_TEST_WEB_PORT always wins.
# Exit 2 for a bad argument or tag, 1 for a failed unit, a missing base image, a failed pull of the mock's image or a failed start.
# Needs bash 3.2 or later, docker compose, and the base image IRIS_IMAGE (default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root" || exit 1
. "$root/ci/units.sh"
. "$root/docker/tests/lib-live.sh"

usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$root/ci/iris.sh" >&2
}

# --- the run tag and the web port ---

setup_tag() {
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
    OCUTALON_RUN_TAG="local-$(date +%s)-$$"
  fi
  if ! live_tag_ok "$OCUTALON_RUN_TAG"; then
    echo "FAIL OCUTALON_RUN_TAG '$OCUTALON_RUN_TAG' $LIVE_TAG_RULE"
    exit 2
  fi
  export OCUTALON_RUN_TAG
  if [ -z "${OCUTALON_TEST_WEB_PORT:-}" ]; then
    case ${RUNNER_NAME:-} in
      *-*)
        n=${RUNNER_NAME##*-}
        case $n in
          '' | *[!0-9]*) ;;
          *)
            if [ $((10#$n)) -le 9 ]; then
              export OCUTALON_TEST_WEB_PORT=$((52810 + 10#$n))
            elif [ $((10#$n)) -le 19 ]; then
              export OCUTALON_TEST_WEB_PORT=$((52819 - 10#$n))
            fi
            ;;
        esac
        ;;
    esac
  fi
}

# The image: line of the mock service in ci/compose.ci.yml, read with awk (never `docker compose config`).
mock_image() {
  awk '
    /^[^ #]/ { ins = 0 }
    /^services:/ { ins = 1; next }
    ins && /^  [A-Za-z0-9_.-]+:/ { cur = $1; sub(/:$/, "", cur); next }
    ins && cur == "mock" && $1 == "image:" { print $2; exit }
  ' "$root/ci/compose.ci.yml"
}

# Runs before any stack starts. The IRIS base image must be on the machine: it is never pulled. The mock's image is public, pinned
# by digest and pulled once per machine, kept by every teardown: when it is missing, preflight pulls it up to 3 times, pausing
# OCUTALON_PULL_PAUSE seconds (default 10) and then three times that between the tries, and fails before any stack starts when
# every try fails (Docker Hub's anonymous limit or an outage). A present image is never pulled.
preflight() {
  local image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0} ref pause try=1 out=""
  if ! docker image inspect --format '{{.Id}}' "$image" >/dev/null 2>&1; then
    echo "FAIL the base image $image is not on this machine (or Docker is not running): load it first, it is never pulled"
    exit 1
  fi
  ref=$(mock_image)
  if [ -z "$ref" ]; then
    echo "FAIL ci/compose.ci.yml names no image for the mock service; no stack was started"
    exit 1
  fi
  if docker image inspect --format '{{.Id}}' "$ref" >/dev/null 2>&1; then return 0; fi
  pause=${OCUTALON_PULL_PAUSE:-10}
  case $pause in '' | *[!0-9]*) pause=10 ;; esac
  pause=$((10#$pause))
  while [ "$try" -le 3 ]; do
    echo "PULL the mock image $ref (try $try of 3)"
    if out=$(docker pull "$ref" 2>&1); then return 0; fi
    if [ "$try" -lt 3 ]; then
      sleep "$pause"
      pause=$((pause * 3))
    fi
    try=$((try + 1))
  done
  printf '%s\n' "$out" | tail -n 3
  echo "FAIL the mock image $ref could not be pulled after 3 tries (Docker Hub); no stack was started"
  exit 1
}

# --- the test classes ---

class_of() { # class_of <file>: the class name of a file below src/<tree>/cls/
  printf '%s\n' "$1" | sed -e 's#^src/[^/]*/cls/##' -e 's#\.cls$##' -e 's#/#.#g'
}

# is_test_case <file>: a class that is not abstract and has a Method Test...
is_test_case() {
  grep -q '^Method Test' "$1" || return 1
  awk '/^Class / { collecting = 1 }
       collecting && /^\{/ { exit abstract }
       collecting && /[[,][ \t]*Abstract[ \t]*[],]/ { abstract = 1 }
       END { exit abstract }' "$1"
}

# test_classes <area>...: the test classes of the areas in either source tree, one per line, in name order.
test_classes() {
  local area f
  for area in "$@"; do
    for f in src/*/cls/OcuTalon/Test/"$area"/*.cls; do
      [ -f "$f" ] || continue
      if is_test_case "$f"; then class_of "$f"; fi
    done
  done | LC_ALL=C sort
}

all_areas() {
  local shard
  for shard in $SHARDS; do shard_areas "$shard"; done | tr ' ' '\n'
}

# --- one test class in the running throwaway ---

# class_script <class>: the IRIS session that runs one test class from the installed package and prints its result as CHK lines:
# one case line per class, an error line for a failed case or method that has an error text, and an assert line for every assertion
# that did not pass (failed or skipped) in every method. Each Write carries its own postcondition, so a condition gates only that
# Write and never the loops after it. ^UnitTestRoot must name an existing folder, because the manager checks the root even for a run
# with no load.
class_script() {
  printf '%s\n' \
    'Set ^UnitTestRoot="/tmp/"' \
    "Write !,\"CHK|compiled|\",##class(%Dictionary.CompiledClass).%ExistsId(\"$1\")" \
    'Set before=$Order(^UnitTest.Result(""),-1)' \
    "Do ##class(%UnitTest.Manager).RunTest(\":$1\",\"/noload/nodelete/norecursive\")" \
    'Set id=$Order(^UnitTest.Result(""),-1) Set inst="" If id>before Set inst=##class(%UnitTest.Result.TestInstance).%OpenId(id)' \
    'Write !,"CHK|new|",$IsObject(inst)' \
    'If $IsObject(inst) { Set k1="" For { Set su=inst.TestSuites.GetNext(.k1) Quit:k1=""  Set k2="" For { Set tc=su.TestCases.GetNext(.k2) Quit:k2=""  Write !,"CHK|case|",tc.Name,"|",tc.Status,"|",tc.Duration,"|",tc.TestMethods.Count()  Write:(tc.Status=0)&&(tc.ErrorDescription'"'"'="") !,"CHK|error|",tc.Name,"|",$Translate(tc.ErrorDescription,$Char(13,10),"  ")  Set k3="" For { Set tm=tc.TestMethods.GetNext(.k3) Quit:k3=""  Write:(tm.Status=0)&&(tm.ErrorDescription'"'"'="") !,"CHK|error|",tm.Name,"|",$Translate(tm.ErrorDescription,$Char(13,10),"  ")  Set k4="" For { Set ta=tm.TestAsserts.GetNext(.k4) Quit:k4=""  Write:ta.Status'"'"'=1 !,"CHK|assert|",ta.Status,"|",tm.Name,"|",$Translate(ta.Description,$Char(13,10),"  ") } } } } }' \
    'Halt'
}

# run_class <class>: prints "CLASS <class> passed|failed <s>s" and, indented, each failed or skipped assertion and each error.
# Returns 1 when the class is not compiled, left no result, ran no test or failed.
run_class() {
  local class=$1 out started=$SECONDS
  local compiled="" casename="" status="" dur="" methods="" details="" verdict kind a b c d desc
  out=$(class_script "$class" | iris_script OCUTALON)
  while IFS='|' read -r _ kind a b c d; do
    case $kind in
      compiled) compiled=$a ;;
      case)
        casename=$a
        status=$b
        dur=$c
        methods=$d
        ;;
      assert)
        desc=$c${d:+|$d}
        if [ "$a" = 2 ]; then details="$details
  SKIP $b: $desc"; else details="$details
  FAIL $b: $desc"; fi
        ;;
      error) details="$details
  ERROR $a: $b${c:+|$c}${d:+|$d}" ;;
    esac
  done <<EOT
$out
EOT
  if [ "$compiled" != 1 ]; then
    verdict=failed
    details="$details
  the class is not compiled in the installed package (or the IRIS session printed nothing)"
  elif [ -z "$casename" ]; then
    verdict=failed
    details="$details
  the run left no result for the class"
  elif [ "${methods:-0}" -eq 0 ]; then
    verdict=failed
    details="$details
  the class ran no test"
  elif [ "$status" = 0 ]; then
    verdict=failed
  else
    verdict=passed
  fi
  if [ -z "$dur" ]; then dur=$((SECONDS - started)); fi
  # IRIS writes the duration with a decimal point: format it in the C locale, whatever the caller's locale is.
  ( LC_ALL=C; printf 'CLASS %s %s %.2fs\n' "$class" "$verdict" "$dur" )
  if [ -n "$details" ]; then printf '%s\n' "${details#?}"; fi
  [ "$verdict" = passed ]
}

# run_classes <label> <title> <class>...: one throwaway, then every class in the order given. The project is torn down on exit.
run_classes() {
  local label=$1 title=$2 started=$SECONDS bad=0 n=0 c ready total word=RUN
  shift 2
  case $label in shard-*) word=SHARD ;; esac
  preflight
  live_start "$label"
  echo "STACK $title: project $P"
  if ! dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    echo "FAIL $title: the stack did not become ready"
    exit 1
  fi
  live_track_image
  ready=$((SECONDS - started))
  echo "READY $title ${ready}s"
  for c in "$@"; do
    n=$((n + 1))
    run_class "$c" || bad=$((bad + 1))
  done
  total=$((SECONDS - started))
  if [ "$bad" -gt 0 ]; then
    echo "$word $title failed ($bad of $n classes) ${total}s"
    exit 1
  fi
  echo "$word $title passed ($n classes) ${total}s"
}

# --- the subcommands ---

cmd_list() {
  echo "checks: $CHECK_SCRIPTS"
  echo "web: $WEB_SCRIPTS"
  local shard group
  for shard in $SHARDS; do echo "shard $shard: $(shard_areas "$shard")"; done
  for group in $IRIS_GROUPS; do echo "group $group: $(group_units "$group")"; done
}

cmd_classes() {
  local shard
  if [ $# -gt 0 ]; then
    shard_areas "$1" >/dev/null || {
      echo "unknown shard '$1'; shards: $SHARDS"
      exit 2
    }
    test_classes $(shard_areas "$1")
  else
    test_classes $(all_areas)
  fi
}

cmd_port() {
  setup_tag
  echo "${OCUTALON_TEST_WEB_PORT:-auto}"
}

cmd_build() {
  setup_tag
  preflight
  LIVE_REBUILD_WEB=1 ensure_web_bundle || exit 1
  echo "BUILD the web bundle is built from this checkout"
}

cmd_shard() {
  local name="" reverse=0 arg classes
  for arg in "$@"; do
    case $arg in
      --reverse) reverse=1 ;;
      -*)
        usage
        exit 2
        ;;
      *) name=$arg ;;
    esac
  done
  if [ -z "$name" ] || ! shard_areas "$name" >/dev/null; then
    echo "unknown shard '$name'; shards: $SHARDS"
    exit 2
  fi
  setup_tag
  classes=$(test_classes $(shard_areas "$name"))
  if [ -z "$classes" ]; then
    echo "FAIL shard $name: no test class found below src/*/cls/OcuTalon/Test/<area>/"
    exit 1
  fi
  if [ "$reverse" -eq 1 ]; then classes=$(printf '%s\n' "$classes" | LC_ALL=C sort -r); fi
  # shellcheck disable=SC2086
  run_classes "shard-$name" "$name$([ "$reverse" -eq 1 ] && echo ' (reversed)')" $classes
}

cmd_class() {
  local class=${1:-}
  if [ -z "$class" ] || ! test_classes $(all_areas) | grep -qxF -- "$class"; then
    echo "unknown test class '$class': it must be a non-abstract class with a Method Test... in a Test/<Area>/ folder"
    exit 2
  fi
  setup_tag
  run_classes "class" "$class" "$class"
}

live_known() { # live_known <name>: the name is a live unit of some group
  local group unit
  for group in $IRIS_GROUPS; do
    for unit in $(group_units "$group"); do
      [ "$unit" = "live:$1" ] && return 0
    done
  done
  return 1
}

cmd_live() {
  local name=${1:-}
  if [ -z "$name" ] || ! live_known "$name" || [ ! -f "docker/tests/test-$name.sh" ]; then
    echo "unknown live unit '$name'; see: ci/iris.sh list"
    exit 2
  fi
  setup_tag
  echo "PORT the web port of the browser units: ${OCUTALON_TEST_WEB_PORT:-auto}"
  preflight
  case " $BROWSER_UNITS " in
    *" $name "*) npx --prefix web playwright install chromium || exit 1 ;;
  esac
  bash "docker/tests/test-$name.sh"
}

cmd_group() {
  local name=${1:-} units unit kind arg started rc failed="" total=$SECONDS
  if ! units=$(group_units "$name"); then
    echo "unknown group '$name'; groups: $IRIS_GROUPS"
    exit 2
  fi
  setup_tag
  preflight
  ensure_web_bundle || exit 1
  for unit in $units; do
    kind=${unit%%:*}
    arg=${unit#*:}
    echo "---- UNIT $unit begins"
    started=$SECONDS
    bash "$root/ci/iris.sh" "$kind" "$arg"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "UNIT $unit passed $((SECONDS - started))s"
    else
      echo "UNIT $unit failed $((SECONDS - started))s"
      failed="$failed $unit"
    fi
  done
  if [ -n "$failed" ]; then
    echo "GROUP $name failed:$failed ($((SECONDS - total))s)"
    exit 1
  fi
  echo "GROUP $name passed ($((SECONDS - total))s)"
}

cmd_all() {
  local group failed=""
  setup_tag
  for group in $IRIS_GROUPS; do
    bash "$root/ci/iris.sh" group "$group" || failed="$failed $group"
  done
  if [ -n "$failed" ]; then
    echo "ALL failed:$failed"
    exit 1
  fi
  echo "ALL passed"
}

# teardown: removes only what carries the tag. A name qualifies when it is ocutalon-<label>-<tag>-<epoch>-<pid> (the project name of
# live_start) or that name followed by -, _ or : and a suffix (container, volume, network, image), and it holds no "slot"; the
# preloaded base image and another run's resources never match. A tag must not end another run's tag.
cmd_teardown() {
  local tag=${OCUTALON_RUN_TAG:-} pattern projects p name c v n i
  if [ -z "$tag" ]; then
    echo "teardown needs OCUTALON_RUN_TAG: the tag of the run to remove"
    exit 2
  fi
  if ! live_tag_ok "$tag"; then
    echo "FAIL OCUTALON_RUN_TAG '$tag' $LIVE_TAG_RULE"
    exit 2
  fi
  pattern="^ocutalon-[a-z0-9-]+-$tag-[0-9]{10}-[0-9]+([-_:]|\$)"
  c=0
  v=0
  n=0
  i=0
  projects=$(docker ps -a --filter label=com.docker.compose.project --format '{{.Label "com.docker.compose.project"}}' | sort -u | grep -E -- "$pattern" | grep -v slot)
  for p in $projects; do
    docker compose -p "$p" -f "$root/docker-compose.yml" -f "$root/docker/tests/compose.throwaway.yml" -f "$root/ci/compose.ci.yml" \
      down -v --rmi local --remove-orphans >/dev/null 2>&1
  done
  for name in $(docker ps -a --format '{{.Names}}' | grep -E -- "$pattern" | grep -v slot); do
    if docker rm -f -v "$name" >/dev/null 2>&1; then c=$((c + 1)); fi
  done
  for name in $(docker volume ls --format '{{.Name}}' | grep -E -- "$pattern" | grep -v slot); do
    if docker volume rm -f "$name" >/dev/null 2>&1; then v=$((v + 1)); fi
  done
  for name in $(docker network ls --format '{{.Name}}' | grep -E -- "$pattern" | grep -v slot); do
    if docker network rm "$name" >/dev/null 2>&1; then n=$((n + 1)); fi
  done
  for name in $(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E -- "$pattern" | grep -v slot); do
    if docker image rm -f "$name" >/dev/null 2>&1; then i=$((i + 1)); fi
  done
  echo "TEARDOWN tag $tag: $(printf '%s\n' "$projects" | grep -c .) project(s) removed, $c leftover container(s), $v leftover volume(s), $n leftover network(s), $i leftover image(s)"
}

# Sourced (by docker/tests/test-ci-config.sh), it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
case $cmd in
  list) cmd_list ;;
  groups) printf '%s\n' $IRIS_GROUPS ;;
  classes) cmd_classes "$@" ;;
  port) cmd_port ;;
  build) cmd_build ;;
  shard) cmd_shard "$@" ;;
  class) cmd_class "$@" ;;
  live) cmd_live "$@" ;;
  group) cmd_group "$@" ;;
  teardown) cmd_teardown ;;
  all) cmd_all ;;
  *)
    usage
    exit 2
    ;;
esac
