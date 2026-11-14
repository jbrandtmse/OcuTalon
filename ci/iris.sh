#!/usr/bin/env bash
# The IRIS test recipe (Story 0.7): runs the IRIS units on the CI runner and on a developer machine, piece by piece or by group,
# always in throwaway compose projects (docker/tests/lib-live.sh) with the CI override (ci/compose.ci.yml). It never names a
# developer instance or a slot, and it never pushes, saves or caches an image. The IRIS base image is never pulled: it must already
# be on the machine. The mock's public image (Story 0.11; node, pinned by digest) is pulled once per machine by preflight and kept.
#
#   ci/iris.sh list                       the check scripts, the web scripts, the shards and the groups with their units
#   ci/iris.sh groups                     the group names, one per line (the matrix of .github/workflows/ci.yml)
#   ci/iris.sh classes [shard]            the test classes of a shard (of every shard), one per line, in name order; a shard
#                                         here and in `shard` may be a piece, <shard>@<Area>,... or <shard>@rest (shard_unit_areas
#                                         of ci/units.sh), which keeps only those areas of the shard
#   ci/iris.sh port                       the web port that the browser units would publish: 52810 + n (runners 0 to 9), 52819 - n (10 to 19), or auto
#   ci/iris.sh build                      checks the base image, sweeps the runner's web port (see the sweep paragraph below) and builds the web
#                                         bundle from this checkout; in the lane-a jobs ipm-install and ipm-install-p (GITHUB_JOB) it also takes
#                                         the job's start stamp
#   ci/iris.sh shard <name> [--reverse] [--part k/n]
#                                         one throwaway; every test class of the shard's areas through %UnitTest.Manager, in
#                                         name order (reversed with --reverse); one "CLASS <name> passed|failed <s>s" line each.
#                                         --part k/n runs only the k-th of n contiguous parts of that ordered list (sizes differ
#                                         by at most one, the first count-mod-n parts are the larger) and titles the run
#                                         "<name> part k/n"; k from 1 to n, n at most the shard's class count, else exit 2
#   ci/iris.sh class <Class>[:<Method>]   the same for one test class, or for one Test... method of it (the CLASS line names the spec)
#   ci/iris.sh live <name>                docker/tests/test-<name>.sh with the run tag; it first prints "PORT ..." with the web port
#                                         and, for a browser unit (a name in BROWSER_UNITS of ci/units.sh), first installs Chromium,
#                                         and Firefox and WebKit as well for a name in FIREFOX_WEBKIT_UNITS (the floor unit)
#                                         The arguments after <name> go to the script; only test-sign-in.sh, test-sign-in-2.sh and test-sign-in-3.sh read any: --part k/n, --project sign-in-3
#                                         (and test-sign-in.sh's --project chromium|sign-in-2)
#                                         On a self-hosted CI runner (GITHUB_ACTIONS=true and RUNNER_ENVIRONMENT=self-hosted) the unit's
#                                         Playwright run keeps the trace of a failing test only (OCUTALON_E2E_TRACE=retain-on-failure) and
#                                         the unit's exit code is kept; see the trace paragraph below
#   ci/iris.sh group <name>               the units of a group in order, each in its own process and project; one
#                                         "UNIT <unit> passed|failed <s>s" line each; exit 1 naming the failed units
#   ci/iris.sh teardown                   removes only the projects, volumes, networks and images of the tag (ocutalon-<label>-<tag>-<epoch>-<pid>),
#                                         and the tag's warm state and warm-iris.lock (ci/warm.sh); in the jobs ipm-install and ipm-install-p it first
#                                         prints `MEASURED <job> N s` (since the stamp of `build`) and, over REL-4's 2100 s, `over REL-4` (log and step summary)
#   ci/iris.sh all                        every group in turn
# OCUTALON_RUN_TAG (lower-case letters, digits and hyphens, at least 3 characters, no "slot") names the run: the pieces of one run
# share it and `teardown` needs it. It defaults to local-<epoch>-<pid>, which makes each call its own run. In CI the web port of
# the browser units follows the number n at the end of RUNNER_NAME: 52810 + n for n from 0 to 9 and 52819 - n for n from 10 to 19
# (52809 down to 52800), so runners 1 to 19 never share a port on one host. Otherwise (n of 20 or more, no number, no RUNNER_NAME, as
# on a developer machine) the browser units probe for the first free port of 52800-52819, which a fixed-port runner of the same host
# may be about to publish. A set OCUTALON_TEST_WEB_PORT always wins.
# Sweep (Story 25.7, DW-1335): only one job runs on a runner at a time, so `build` removes every throwaway compose project that publishes
# the runner's fixed web port, after the base image check and before the bundle step, when GITHUB_ACTIONS=true, RUNNER_ENVIRONMENT=self-hosted
# and OCUTALON_TEST_WEB_PORT (after setup_tag) is a number of 52800-52819. A holder is selected by host port (docker ps -a --filter publish=)
# and removed by project, through the down line of teardown (the leftover's port-less mock goes with it). Only a compose project named like a
# live_start project (ocutalon-<label>-<tag>-<epoch>-<pid>, no "slot") is removed; every other holder is kept. It never fails the job and
# never runs in group, live, shard or class. One line per outcome: `SWEEP off: <reason>`, `SWEEP 127.0.0.1:<p>: no leftover`,
# `SWEEP removed project <P> (it published 127.0.0.1:<p>)`, `SWEEP kept <name> project=<P|none>: <reason>`, `SWEEP FAIL <what>`.
# It needs every runner of a CI host to have a fixed or preset port: a runner in auto mode on the same host could hold this port with a
# live stack, which the sweep would remove.
# Exit 2 for a bad argument or tag, 1 for a failed unit, a missing base image, a failed pull of the mock's image or a failed start.
# OCUTALON_WARM=1 ci/iris.sh class|shard ... runs on the warm throwaway of the tag (ci/warm.sh up) after reloading the changed
# classes, with no new start, and exits 1 when that stack is missing, stopped or stale or the reload fails; live, group and all never
# run warm. A value of OCUTALON_WARM other than 1, 0 or empty exits 2.
# Traces (Story 11.27, DW-550, DW-774): a trace never leaves the CI host. Live units write traces only when GITHUB_ACTIONS=true and
# RUNNER_ENVIRONMENT=self-hosted (web/playwright.config.ts checks the runner again) and the trace root is valid: OCUTALON_TRACE_DIR, else
# $HOME/ocutalon-traces, an absolute folder outside GITHUB_WORKSPACE and outside this checkout, created with umask 077. After a unit,
# every trace*.zip under web/test-results moves to <root>/<OCUTALON_RUN_TAG>/<its path below web/test-results> (which begins with
# <unit>/), and every .playwright-artifacts-* folder is deleted; a trace that cannot be moved, or that is found while traces are off, is
# deleted, so that the failure artifact upload (ci.yml) never holds one. The sweep runs in CI only. `group` first deletes the root's run
# folders (names that pass the run-tag rule) older than 7 days. Log lines name only <tag>/<unit>, never the host path.
# Retries (Story 32.6, DW-550, DW-774): a live page whose snapshot GET of /state has no answer by half of its bound reloads once, inside the
# same bound, and prints `RETRY <spec>:<line> <step>` (web/e2e/support/bounds.ts reportRetry). `live` points OCUTALON_E2E_RETRY_LOG at
# web/test-results/<unit>-retries.txt (removed before the unit starts), where each retry also appends its line, because a passing test's
# stdout does not reach the job log. After the unit it prints those lines, then the retry-time `DIAG <text>` lines that a retry appended after
# its RETRY line (printable ASCII, at most 300 characters; DW-911, Story 32.7), then `RETRIES <n> in live:<unit>` when n is above 0 (n counts
# only the RETRY lines; the exit code is the unit's). `group` prints `RETRIES <total> in group <name>[ (<unit> <n>, ...)]` before its GROUP line on every run, 0 included, and when
# GITHUB_STEP_SUMMARY is set and the total is above 0 it appends that line and every RETRY line with its unit to the step summary.
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

# class_script <class>[:<Method>]: the IRIS session that runs one test class (or one method of it) from the installed package and prints its result as CHK lines:
# one case line per class, an error line for a failed case or method that has an error text, and an assert line for every assertion
# that did not pass (failed or skipped) in every method. Each Write carries its own postcondition, so a condition gates only that
# Write and never the loops after it. ^UnitTestRoot must name an existing folder, because the manager checks the root even for a run
# with no load.
class_script() {
  printf '%s\n' \
    'Set ^UnitTestRoot="/tmp/"' \
    "Write !,\"CHK|compiled|\",##class(%Dictionary.CompiledClass).%ExistsId(\"${1%%:*}\")" \
    'Set before=$Order(^UnitTest.Result(""),-1)' \
    "Do ##class(%UnitTest.Manager).RunTest(\":$1\",\"/noload/nodelete/norecursive\")" \
    'Set id=$Order(^UnitTest.Result(""),-1) Set inst="" If id>before Set inst=##class(%UnitTest.Result.TestInstance).%OpenId(id)' \
    'Write !,"CHK|new|",$IsObject(inst)' \
    'If $IsObject(inst) { Set k1="" For { Set su=inst.TestSuites.GetNext(.k1) Quit:k1=""  Set k2="" For { Set tc=su.TestCases.GetNext(.k2) Quit:k2=""  Write !,"CHK|case|",tc.Name,"|",tc.Status,"|",tc.Duration,"|",tc.TestMethods.Count()  Write:(tc.Status=0)&&(tc.ErrorDescription'"'"'="") !,"CHK|error|",tc.Name,"|",$Translate(tc.ErrorDescription,$Char(13,10),"  ")  Set k3="" For { Set tm=tc.TestMethods.GetNext(.k3) Quit:k3=""  Write:(tm.Status=0)&&(tm.ErrorDescription'"'"'="") !,"CHK|error|",tm.Name,"|",$Translate(tm.ErrorDescription,$Char(13,10),"  ")  Set k4="" For { Set ta=tm.TestAsserts.GetNext(.k4) Quit:k4=""  Write:ta.Status'"'"'=1 !,"CHK|assert|",ta.Status,"|",tm.Name,"|",$Translate(ta.Description,$Char(13,10),"  ") } } } } }' \
    'Halt'
}

# run_class <class>[:<Method>]: prints "CLASS <spec> passed|failed <s>s" and, indented, each failed or skipped assertion and each error.
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

# --- one throwaway: its start, and the warm mode that reuses one ---

# warm_mode: prints warm for OCUTALON_WARM=1 and fresh when it is unset, empty or 0. Any other value prints the FAIL line and
# returns 2.
warm_mode() {
  case ${OCUTALON_WARM:-} in
    1) echo warm ;;
    '' | 0) echo fresh ;;
    *)
      echo "FAIL OCUTALON_WARM must be 1 (warm), or 0 or unset (fresh)"
      return 2
      ;;
  esac
}

# warm_check: sets WARM_MODE to warm or fresh; a bad OCUTALON_WARM ends the run with exit 2.
warm_check() {
  WARM_MODE=$(warm_mode) || {
    echo "$WARM_MODE"
    exit 2
  }
}

# stack_start <label>: the preflight, then the lock, the project name and the exit trap (live_start).
stack_start() {
  preflight
  live_start "$1"
}

# stack_ready <title> <start second> [<check>]: the STACK line, the build and start of the project, and the READY line. The optional
# check is a command that runs once the project is up and before the READY line: it prints its own FAIL line and returns non-zero
# to end the run (exit 1, so the caller's exit trap tears the project down). A fresh class or shard run passes live_park_telegram
# (docker/tests/lib-live.sh), which parks the Telegram items of the new stack.
stack_ready() {
  local title=$1 started=$2 check=${3:-} ready
  echo "STACK $title: project $P"
  if ! dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))" > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    echo "FAIL $title: the stack did not become ready"
    exit 1
  fi
  if [ -n "$check" ] && ! "$check" "$title"; then exit 1; fi
  live_track_image
  ready=$((SECONDS - started))
  echo "READY $title ${ready}s"
}

# run_classes <label> <title> <class>...: one throwaway, then every class in the order given. The project is torn down on exit.
# With OCUTALON_WARM=1 the classes run on the warm throwaway of the tag instead (ci/warm.sh), which starts nothing.
run_classes() {
  local label=$1 title=$2 started=$SECONDS bad=0 n=0 c total word=RUN
  shift 2
  case $label in shard-*) word=SHARD ;; esac
  warm_check
  if [ "$WARM_MODE" = warm ]; then
    . "$root/ci/warm.sh"
    warm_attach "$title" || exit 1
  else
    stack_start "$label"
    stack_ready "$title" "$started" live_park_telegram
  fi
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
  local areas
  if [ $# -gt 0 ]; then
    areas=$(shard_unit_areas "$1") || {
      echo "unknown shard '$1'; shards: $SHARDS (a piece is <shard>@<Area>,... with areas of the shard, or <shard>@rest)"
      exit 2
    }
    # shellcheck disable=SC2086
    test_classes $areas
  else
    test_classes $(all_areas)
  fi
}

cmd_port() {
  setup_tag
  echo "${OCUTALON_TEST_WEB_PORT:-auto}"
}

# --- the time of the lane-a IPM jobs, from `build` to `teardown`, against REL-4's 35 minutes (Story 0.32, DW-1214) ---
# The jobs ipm-install and ipm-install-p (REL4_JOBS of ci/units.sh) have a timeout-minutes of 45, which only stops a hang; REL-4's 35 minutes
# (REL4_TARGET_SECONDS) stays the target. `build`, the first script of each job, takes a start stamp; `teardown`, the last step (if: always()),
# prints `MEASURED <job> N s` with the seconds since the stamp and, when N is over the target, `over REL-4: ...` to the log and to
# GITHUB_STEP_SUMMARY. N leaves out the job's setup and checkout before `build` and the teardown's own cleanup after the line, so it
# reads a little under the job's duration. Any other job, or a run with no stamp or a stamp that is not a number, prints nothing.
# job_now is the clock (a test replaces it).

job_now() { date +%s; }

job_start_file() { printf '%s\n' "${TMPDIR:-/tmp}/ocutalon-jobstart-$1"; }

# job_is_rel4: true when GITHUB_JOB is one of REL4_JOBS.
job_is_rel4() {
  local j
  for j in $REL4_JOBS; do
    [ "${GITHUB_JOB:-}" = "$j" ] && return 0
  done
  return 1
}

# job_start_stamp: writes the start stamp of the tag once (a second `build` of the job keeps the first), for a REL-4 job only.
job_start_stamp() {
  local f
  job_is_rel4 || return 0
  f=$(job_start_file "${OCUTALON_RUN_TAG:-}")
  [ -f "$f" ] || job_now > "$f" 2>/dev/null
  return 0
}

# job_wall_report <tag>: the MEASURED line (and the over REL-4 flag) of a REL-4 job that has a stamp; removes the stamp.
job_wall_report() {
  local f start n line
  job_is_rel4 || return 0
  f=$(job_start_file "$1")
  [ -f "$f" ] || return 0
  start=$(cat "$f" 2>/dev/null)
  rm -f "$f"
  case $start in '' | *[!0-9]*) return 0 ;; esac
  n=$(($(job_now) - start))
  echo "MEASURED $GITHUB_JOB $n s"
  if [ "$n" -gt "$REL4_TARGET_SECONDS" ]; then
    line="over REL-4: $GITHUB_JOB took $n s, the target is $REL4_TARGET_SECONDS s"
    echo "$line"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$line" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null; fi
  fi
  return 0
}

# --- the sweep of the runner's web port (Story 25.7) ---

# project_down <project>: brings one throwaway project down with teardown's files and options, volumes and local images included.
project_down() {
  docker compose -p "$1" -f "$root/docker-compose.yml" -f "$root/docker/tests/compose.throwaway.yml" -f "$root/ci/compose.ci.yml" \
    down -v --rmi local --remove-orphans >/dev/null 2>&1
}

# sweep_holders <port>: one "<container>|<compose project or empty>" line per container that publishes the host port; 1 when docker cannot list.
sweep_holders() {
  live_bounded docker ps -a --filter "publish=$1" --format '{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null
}

# sweep_throwaway <project>: 0 when the name is shaped like a live_start project and holds no "slot".
sweep_throwaway() {
  case $1 in *slot*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq -- '^ocutalon-[a-z0-9-]+-[0-9]{10}-[0-9]+$'
}

# runner_sweep: on a self-hosted CI runner with a fixed web port, removes every throwaway project that publishes that port and logs
# each outcome (the SWEEP lines of the header). It always returns 0.
runner_sweep() {
  local p=${OCUTALON_TEST_WEB_PORT:-} rows name proj todo="" left
  if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${RUNNER_ENVIRONMENT:-}" != self-hosted ]; then
    echo "SWEEP off: not a self-hosted CI runner"
    return 0
  fi
  if [ -z "$p" ]; then
    echo "SWEEP off: no fixed web port"
    return 0
  fi
  case $p in
    528[01][0-9]) ;;
    *)
      echo "SWEEP off: OCUTALON_TEST_WEB_PORT '${p:0:40}' is not a port of 52800-52819"
      return 0
      ;;
  esac
  if ! rows=$(sweep_holders "$p"); then
    echo "SWEEP FAIL could not list what publishes 127.0.0.1:$p"
    return 0
  fi
  if [ -z "$rows" ]; then
    echo "SWEEP 127.0.0.1:$p: no leftover"
    return 0
  fi
  while IFS='|' read -r name proj; do
    [ -n "$name" ] || continue
    if [ -z "$proj" ]; then
      echo "SWEEP kept $name project=none: not a compose project"
    elif ! sweep_throwaway "$proj"; then
      echo "SWEEP kept $name project=$proj: not a throwaway project"
    elif ! printf '%s\n' "$todo" | grep -qxF -- "$proj"; then
      todo="$todo$proj
"
    fi
  done <<EOF
$rows
EOF
  for proj in $todo; do
    project_down "$proj"
    if ! rows=$(sweep_holders "$p"); then
      echo "SWEEP FAIL could not list what publishes 127.0.0.1:$p"
      continue
    fi
    left=$(printf '%s\n' "$rows" | awk -F'|' -v q="$proj" '$2 == q { print $1 }')
    if [ -n "$left" ]; then
      for name in $left; do docker rm -f -v "$name" >/dev/null 2>&1; done
      if ! rows=$(sweep_holders "$p"); then
        echo "SWEEP FAIL could not list what publishes 127.0.0.1:$p"
        continue
      fi
      left=$(printf '%s\n' "$rows" | awk -F'|' -v q="$proj" '$2 == q { print $1 }')
    fi
    if [ -n "$left" ]; then
      for name in $left; do echo "SWEEP FAIL 127.0.0.1:$p still published by $name"; done
    else
      echo "SWEEP removed project $proj (it published 127.0.0.1:$p)"
    fi
  done
  return 0
}

cmd_build() {
  setup_tag
  job_start_stamp
  preflight
  runner_sweep
  LIVE_REBUILD_WEB=1 ensure_web_bundle || exit 1
  echo "BUILD the web bundle is built from this checkout"
}

# shard_part <k> <n> <classes>: the k-th of n contiguous parts of the class list (one name per line); the first count-mod-n
# parts hold one class more than the others.
shard_part() {
  local k=$1 n=$2 classes=$3 count size extra start len
  count=$(printf '%s\n' "$classes" | grep -c .)
  size=$((count / n))
  extra=$((count % n))
  if [ "$k" -le "$extra" ]; then
    len=$((size + 1))
    start=$(((k - 1) * len + 1))
  else
    len=$size
    start=$((extra * (size + 1) + (k - extra - 1) * size + 1))
  fi
  printf '%s\n' "$classes" | sed -n "${start},$((start + len - 1))p"
}

cmd_shard() {
  local name="" reverse=0 part="" part_given=0 arg classes part_k part_n count areas
  while [ $# -gt 0 ]; do
    arg=$1
    shift
    case $arg in
      --reverse) reverse=1 ;;
      --part)
        if [ $# -eq 0 ]; then
          echo "--part needs k/n"
          exit 2
        fi
        part=$1
        part_given=1
        shift
        ;;
      --part=*)
        part=${arg#--part=}
        part_given=1
        ;;
      -*)
        usage
        exit 2
        ;;
      *) name=$arg ;;
    esac
  done
  if [ -z "$name" ] || ! areas=$(shard_unit_areas "$name"); then
    echo "unknown shard '$name'; shards: $SHARDS (a piece is <shard>@<Area>,... with areas of the shard, or <shard>@rest)"
    exit 2
  fi
  if [ "$part_given" -eq 1 ]; then
    if ! printf '%s\n' "$part" | grep -Eq '^[0-9]{1,6}/[0-9]{1,6}$'; then
      echo "bad --part '$part': expected k/n with whole numbers"
      exit 2
    fi
    part_k=$((10#${part%/*}))
    part_n=$((10#${part#*/}))
    if [ "$part_k" -lt 1 ] || [ "$part_n" -lt 1 ] || [ "$part_k" -gt "$part_n" ]; then
      echo "bad --part '$part': k must be from 1 to n"
      exit 2
    fi
  fi
  setup_tag
  # shellcheck disable=SC2086
  classes=$(test_classes $areas)
  if [ -z "$classes" ]; then
    echo "FAIL shard $name: no test class found below src/*/cls/OcuTalon/Test/<area>/"
    exit 1
  fi
  if [ "$reverse" -eq 1 ]; then classes=$(printf '%s\n' "$classes" | LC_ALL=C sort -r); fi
  local title="$name$([ "$reverse" -eq 1 ] && echo ' (reversed)')"
  if [ "$part_given" -eq 1 ]; then
    count=$(printf '%s\n' "$classes" | grep -c .)
    if [ "$part_n" -gt "$count" ]; then
      echo "bad --part '$part': n is above the $count class(es) of shard $name"
      exit 2
    fi
    classes=$(shard_part "$part_k" "$part_n" "$classes")
    title="$title part $part_k/$part_n"
  fi
  # shellcheck disable=SC2086
  run_classes "shard-${name%%@*}" "$title" $classes
}

cmd_class() {
  local spec=${1:-} class method="" bad=0
  class=${spec%%:*}
  if [ -z "$class" ] || ! test_classes $(all_areas) | grep -qxF -- "$class"; then bad=1; fi
  case $spec in
    *:*)
      method=${spec#*:}
      class_method_ok "$class" "$method" || bad=1
      ;;
  esac
  if [ "$bad" -eq 1 ]; then
    echo "unknown test class '$spec': it must be a non-abstract class with a Method Test... in a Test/<Area>/ folder, optionally followed by :<Test method of it>"
    exit 2
  fi
  setup_tag
  run_classes "class" "$spec" "$spec"
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

# --- Playwright traces (Story 11.27): kept on the runner's own disk, never in the workspace ---

TRACE_FOLDER_NAME=ocutalon-traces
TRACE_KEEP_DAYS=7

# trace_root: the folder that holds the kept traces (empty when neither OCUTALON_TRACE_DIR nor HOME names one).
trace_root() {
  if [ -n "${OCUTALON_TRACE_DIR:-}" ]; then
    printf '%s\n' "$OCUTALON_TRACE_DIR"
  elif [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/$TRACE_FOLDER_NAME"
  fi
}

# trace_physical <path>: the path with its existing part resolved by pwd -P (the path itself may not exist yet).
trace_physical() {
  local p=$1 rest="" base
  while [ "${p%/}" != "$p" ] && [ "$p" != / ]; do p=${p%/}; done
  while [ ! -d "$p" ]; do
    base=${p##*/}
    rest="/$base$rest"
    p=${p%/*}
    [ -n "$p" ] || p=/
  done
  (cd "$p" 2>/dev/null && printf '%s%s\n' "$(pwd -P | sed 's|/$||')" "$rest")
}

# trace_inside <path> <folder>: 0 when the path is the folder or lies below it (both physical).
trace_inside() {
  case $1/ in "$2"/*) return 0 ;; esac
  return 1
}

# traces_on: prints why traces are off and returns 1, unless this is a self-hosted CI runner and the trace root is an absolute folder
# outside GITHUB_WORKSPACE and the checkout; then it makes the root (umask 077), prints nothing and returns 0.
traces_on() {
  local troot phys ws=""
  if [ "${GITHUB_ACTIONS:-}" != true ]; then
    echo "not a CI run"
    return 1
  fi
  if [ "${RUNNER_ENVIRONMENT:-}" != self-hosted ]; then
    echo "not a self-hosted runner"
    return 1
  fi
  troot=$(trace_root)
  case $troot in
    /*) ;;
    *)
      echo "the trace folder is not an absolute path"
      return 1
      ;;
  esac
  case /$troot/ in
    */../*)
      echo "the trace folder holds .."
      return 1
      ;;
  esac
  phys=$(trace_physical "$troot")
  if [ -z "$phys" ]; then
    echo "the trace folder cannot be resolved"
    return 1
  fi
  if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE" ]; then ws=$(cd "$GITHUB_WORKSPACE" && pwd -P); fi
  if { [ -n "$ws" ] && trace_inside "$phys" "$ws"; } || trace_inside "$phys" "$(cd "$root" && pwd -P)"; then
    echo "the trace folder is inside the workspace or the checkout"
    return 1
  fi
  if ! (umask 077 && mkdir -p "$troot") 2>/dev/null; then
    echo "the trace folder cannot be made"
    return 1
  fi
  return 0
}

# trace_mode: prints retain-on-failure when traces are on (traces_on), else nothing.
trace_mode() {
  if traces_on >/dev/null; then echo retain-on-failure; fi
  return 0
}

# traces_keep <results dir> <unit>: CI only. Moves every trace*.zip under the results folder to <root>/<tag>/<its path below the results
# folder> (mode 600, folders 700) when traces are on, deletes it when they are off or the move fails, and deletes every
# .playwright-artifacts-* folder. Prints one TRACE line for what it kept and one for what it removed; nothing when it found no trace.
traces_keep() {
  local results=$1 unit=$2 on=0 troot="" tag=${OCUTALON_RUN_TAG:-} f rel dest kept=0 removed=0
  [ "${GITHUB_ACTIONS:-}" = true ] || return 0
  [ -d "$results" ] || return 0
  if traces_on >/dev/null && live_tag_ok "$tag"; then
    on=1
    troot=$(trace_root)
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$results"/}
    dest="$troot/$tag/$rel"
    if [ "$on" = 1 ] && [ -f "$f" ] && [ ! -L "$f" ] && (umask 077 && mkdir -p "$(dirname "$dest")") 2>/dev/null && mv -f "$f" "$dest" 2>/dev/null; then
      chmod 600 "$dest" 2>/dev/null
      kept=$((kept + 1))
    else
      rm -f "$f" 2>/dev/null
      if [ "$on" = 1 ]; then rm -f "$dest" 2>/dev/null; fi
      removed=$((removed + 1))
    fi
  done < <(find "$results" \( -type f -o -type l \) -name 'trace*.zip' 2>/dev/null)
  while IFS= read -r f; do
    [ -n "$f" ] && rm -rf "$f"
  done < <(find "$results" -type d -name '.playwright-artifacts-*' -prune 2>/dev/null)
  if [ "$kept" -gt 0 ]; then echo "TRACE kept $kept of $unit under $tag/$unit"; fi
  if [ "$removed" -gt 0 ]; then echo "TRACE removed $removed of $unit (traces are off or could not be moved)"; fi
  return 0
}

# traces_prune: when traces are on, deletes the root's run folders (a name that passes live_tag_ok) older than TRACE_KEEP_DAYS days.
# A folder that is gone or cannot be removed (another job may prune at once) is ignored.
traces_prune() {
  local troot dir n=0
  traces_on >/dev/null || return 0
  troot=$(trace_root)
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    live_tag_ok "${dir##*/}" || continue
    rm -rf "$dir" 2>/dev/null
    n=$((n + 1))
  done < <(find "$troot" -mindepth 1 -maxdepth 1 -type d -mmin "+$((TRACE_KEEP_DAYS * 24 * 60))" 2>/dev/null)
  if [ "$n" -gt 0 ]; then echo "TRACE pruned $n run folder(s) older than $TRACE_KEEP_DAYS days"; fi
  return 0
}

# --- Retries of a live page's snapshot wait (Story 32.6): counted from the file that the unit's Playwright run appends to ---

# retry_log_of <unit>: the file that the unit's retries are appended to (OCUTALON_E2E_RETRY_LOG).
retry_log_of() {
  printf '%s\n' "$root/web/test-results/$1-retries.txt"
}

# retry_lines <unit>: the RETRY lines of the unit's file (the shape that web/e2e/support/bounds.ts retryLine prints); nothing when there is no file.
retry_lines() {
  LC_ALL=C grep -E '^RETRY [A-Za-z0-9._/-]+:[0-9]+ [A-Za-z0-9 ./:_-]+$' "$(retry_log_of "$1")" 2>/dev/null
  return 0
}

# retry_count <unit>: the number of RETRY lines of the unit's file (0 without one).
retry_count() {
  retry_lines "$1" | wc -l | tr -d ' '
}

# retry_diag_lines <unit>: the DIAG lines of the unit's file (printable ASCII, 1 to 300 characters after `DIAG `; the length is cut with awk because
# BSD grep refuses a repeat count above 255): the diagnosis that a retry appends after its RETRY line (DW-911); nothing when there is no file.
retry_diag_lines() {
  LC_ALL=C grep -E '^DIAG [ -~]+$' "$(retry_log_of "$1")" 2>/dev/null | LC_ALL=C awk 'length($0) <= 305'
  return 0
}

# retries_report <unit>: when n, the number of RETRY lines, is above 0 prints the unit's RETRY lines, then its DIAG lines, then
# `RETRIES <n> in live:<unit>`; nothing otherwise. Only RETRY lines are counted.
retries_report() {
  local n
  n=$(retry_count "$1")
  [ "$n" -gt 0 ] || return 0
  retry_lines "$1"
  retry_diag_lines "$1"
  echo "RETRIES $n in live:$1"
}

# retries_summary <group> <total> <detail>: prints `RETRIES <total> in group <group>` (with ` (<detail>)` when the detail is not empty). When
# GITHUB_STEP_SUMMARY is set and the total is above 0 it appends that line and each RETRY line with its unit; the detail is a list of
# `live:<unit> <n>` entries separated by `, `. A summary file that cannot be written is ignored.
retries_summary() {
  local group=$1 total=$2 detail=${3:-} line entries
  line="RETRIES $total in group $group"
  if [ -n "$detail" ]; then line="$line ($detail)"; fi
  echo "$line"
  [ "$total" -gt 0 ] || return 0
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  entries=${detail//, /$'\n'}
  {
    echo "$line"
    printf '%s\n' "$entries" | while IFS= read -r entry; do
      unit=${entry%% *}
      unit=${unit#live:}
      [ -n "$unit" ] || continue
      retry_lines "$unit" | while IFS= read -r l; do echo "- live:$unit: $l"; done
    done
  } 2>/dev/null >> "$GITHUB_STEP_SUMMARY"
  return 0
}

# class_method_ok <class> <method>: the method is named Test<letters and digits> and the class's file declares it as `Method <name>(`.
class_method_ok() {
  local f
  case $2 in Test[A-Za-z0-9]*) ;; *) return 1 ;; esac
  case $2 in *[!A-Za-z0-9]*) return 1 ;; esac
  for f in src/*/cls/"$(printf '%s' "$1" | tr . /)".cls; do
    [ -f "$f" ] && grep -q "^Method $2(" "$f" && return 0
  done
  return 1
}

cmd_live() {
  local name=${1:-} mode rc floor given
  if [ -z "$name" ] || ! live_known "$name" || [ ! -f "docker/tests/test-$name.sh" ]; then
    echo "unknown live unit '$name'; see: ci/iris.sh list"
    exit 2
  fi
  # A file from an earlier run is never counted for this one.
  rm -f "$(retry_log_of "$name")"
  warm_check
  if [ "$WARM_MODE" = warm ]; then
    echo "FAIL live units never run warm: unset OCUTALON_WARM"
    exit 2
  fi
  setup_tag
  echo "PORT the web port of the browser units: ${OCUTALON_TEST_WEB_PORT:-auto}"
  preflight
  case " $BROWSER_UNITS " in
    *" $name "*) npx --prefix web playwright install chromium || exit 1 ;;
  esac
  case " $FIREFOX_WEBKIT_UNITS " in
    *" $name "*) npx --prefix web playwright install firefox webkit || exit 1 ;;
  esac
  shift
  mode=$(trace_mode)
  unset OCUTALON_E2E_TRACE
  if [ -n "$mode" ]; then
    echo "TRACE on"
    export OCUTALON_E2E_TRACE=$mode
  else
    echo "TRACE off: $(traces_on)"
  fi
  # A unit with a floor (unit_live_deadline in ci/units.sh) never runs with a lower deadline; a higher given value stays.
  if command -v unit_live_deadline > /dev/null 2>&1 && floor=$(unit_live_deadline "$name"); then
    given=${OCUTALON_LIVE_DEADLINE:-540}
    case $given in '' | *[!0-9]*) given=0 ;; esac
    if [ "$given" -lt "$floor" ]; then
      export OCUTALON_LIVE_DEADLINE=$floor
      echo "DEADLINE live:$name $floor s"
    fi
  fi
  # The retries of the unit's tests are appended to this file (web/e2e/support/bounds.ts reportRetry).
  export OCUTALON_E2E_RETRY_LOG
  OCUTALON_E2E_RETRY_LOG=$(retry_log_of "$name")
  # Each unit keeps its Playwright results in its own folder (web/playwright.config.ts outputDir), so that a later unit of the job does not clear them.
  OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh" "$@"
  rc=$?
  traces_keep "$root/web/test-results" "$name"
  retries_report "$name"
  exit "$rc"
}

# fresh_only <what>: a command whose units all start fresh stacks. A warm request is dropped with one line, and no unit sees it.
fresh_only() {
  warm_check
  if [ "$WARM_MODE" = warm ]; then echo "WARM ignored: $1 runs every unit on a fresh stack"; fi
  unset OCUTALON_WARM
}

cmd_group() {
  local name=${1:-} units unit kind arg started rc failed="" total=$SECONDS retried=0 retries_detail="" n
  if ! units=$(group_units "$name"); then
    echo "unknown group '$name'; groups: $IRIS_GROUPS"
    exit 2
  fi
  fresh_only "group $name"
  setup_tag
  traces_prune
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
    if [ "$kind" = live ]; then
      n=$(retry_count "$arg")
      if [ "$n" -gt 0 ]; then
        retried=$((retried + n))
        retries_detail="${retries_detail:+$retries_detail, }$unit $n"
      fi
    fi
  done
  retries_summary "$name" "$retried" "$retries_detail"
  if [ -n "$failed" ]; then
    echo "GROUP $name failed:$failed ($((SECONDS - total))s)"
    exit 1
  fi
  echo "GROUP $name passed ($((SECONDS - total))s)"
}

cmd_all() {
  local group failed=""
  fresh_only all
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

# warm_state_dir <tag>: the folder that holds the state of the tag's warm stack (ci/warm.sh).
warm_state_dir() { printf '%s\n' "${TMPDIR:-/tmp}/ocutalon-warm-$1"; }

# warm_lock_release <project pattern>: deletes the lane's warm-iris.lock when the project it names matches the pattern of the tag being
# torn down (a warm stack that was killed before ci/warm.sh down), and keeps a lock of any other project.
warm_lock_release() {
  local dir file held
  dir=$(live_lock_dir)
  [ -n "$dir" ] || return 0
  file="$dir/warm-iris.lock"
  [ -f "$file" ] || return 0
  held=$(sed -n 's/.* project=\([^ ]*\).*/\1/p' "$file" 2>/dev/null | head -n 1)
  if [ -n "$held" ] && printf '%s\n' "$held" | grep -Eq -- "$1"; then
    rm -f "$file"
    echo "LOCK released warm-iris project=$held"
  fi
}

# teardown: removes only what carries the tag. A name qualifies when it is ocutalon-<label>-<tag>-<epoch>-<pid> (the project name of
# live_start) or that name followed by -, _ or : and a suffix (container, volume, network, image), and it holds no "slot"; the
# preloaded base image and another run's resources never match. A tag must not end another run's tag. It also releases the lane's
# warm-iris.lock of the tag and removes the tag's warm state folder.
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
  job_wall_report "$tag"
  pattern="^ocutalon-[a-z0-9-]+-$tag-[0-9]{10}-[0-9]+([-_:]|\$)"
  c=0
  v=0
  n=0
  i=0
  projects=$(docker ps -a --filter label=com.docker.compose.project --format '{{.Label "com.docker.compose.project"}}' | sort -u | grep -E -- "$pattern" | grep -v slot)
  for p in $projects; do
    project_down "$p"
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
  warm_lock_release "$pattern"
  rm -rf "$(warm_state_dir "$tag")"
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
