#!/usr/bin/env bash
# release/rehearse.sh <command> [--version <v>] --rc <n> [--candidate <ref>] [--record <file>] [--dry-run]
#
# The clean-machine rehearsal, install half (Story 11.3; FR-55, NFR-11, NFR-22, REL-6; AD-19, AD-22, AD-23, AD-25). A release gate that
# runs by hand and in Story 11.5's sequence; it is no CI unit. It copies a release candidate to a clean host as a git bundle, clones it
# there, puts the author's .env beside it, runs install.sh, signs in from a second (driver) host at the address that install.sh printed,
# times the first start, and writes the result into the candidate's record. The timed runs of the demo path and their bounds come with
# Story 11.11, so a real rehearsal cannot pass yet: its result is "not run". This build has no clean host, no driver host and no real
# key, so the script is proved on throwaways with --dry-run, whose result is "dry run" and never a pass.
#
# Commands:
#   plan     prints the candidate, its version and sha, how each host is reached (configured, local or stand-in), the phases and the
#            record path; starts nothing
#   install  the steps hosts, copy, install and sign-in (see below); keeps the state and, in a dry run, the throwaway project and its lock
#   report   scans the output and the section for values (the secrets step), writes the "## Clean-machine rehearsal" section of the record
#            and prints RECORD <file> and RESULT <result>
#   down     in a dry run removes the tag's projects, volumes, images and lock (ci/iris.sh teardown), then the state; in real mode the clean
#            host keeps its install, and only the state is removed. It may always run
#   run      install, report, then always down; each phase is its own process of this script
# Options (taken by plan, install and run; the state keeps them for report): --rc <n> (a positive whole number, required), --version <v>
# (it must equal <Version> in the candidate's src/module.xml; required unless --dry-run or --candidate is given), --candidate <ref> (a
# local branch in real mode; the default is release/<v>-rc<n>, or HEAD in a dry run), --record <file> (default
# release/records/<v>/rc<n>.md; a test passes a file outside the repository), --dry-run (stand-ins for both hosts).
# The phases need OCUTALON_RUN_TAG (lower-case letters, digits and hyphens, 3 or more, no "slot"); run defaults it to reh-<epoch>. The
# state is ${TMPDIR:-/tmp}/ocutalon-rehearsal-<tag>/. install on a tag that has a state, and report with no finished install, are refused.
#
# The configuration (real mode only; a dry run never reads it): OCUTALON_RELEASE_CONFIG, else ${XDG_CONFIG_HOME:-$HOME/.config}/ocutalon/
# release.conf, outside the repository. KEY=value lines, no expansion but a leading ~/ in a path key: REHEARSAL_CLEAN_SSH (user@host),
# REHEARSAL_CLEAN_KEY, REHEARSAL_CLEAN_WEB (the clean host's name or address as the driver host reaches it; no scheme and no port),
# REHEARSAL_DRIVER_SSH (user@host, or
# local), REHEARSAL_DRIVER_KEY (not for local), REHEARSAL_ENV_FILE (mode 600, outside the repository); optional REHEARSAL_CLEAN_PORT,
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
#            password, sent as a curl config on stdin, and the page holds <app-root
#   secrets  (report) no value of the env file or of the configuration (a value of 8 characters or more; for the configuration, each
#            value as the script uses it and the host of each user@host too), and nothing key-like, is in the output of the phases,
#            install.sh's output or the section
# The section of the record (the order is fixed; each line starts at column 1):
#   ## Clean-machine rehearsal
#   Result: fail | dry run | not run | pass
#   Mode: dry run | rehearsal
#   Candidate: <v> rc<n>, branch <branch> at <sha>[, a stand-in of <sha> with the built web bundle added]
#   Clean host: <OS>, <CPU>, <memory> GiB memory; Node.js absent|present
#   Driver host: <OS>, <CPU>, <memory> GiB memory
#   Run: <UTC start> to <UTC end>
#   Note: ...                                   (a dry run only)
#   | Step | Result | Detail |                  rows hosts, copy, install, sign-in, secrets, demo path runs (pass, fail or not run)
# Result: fail when any step failed; otherwise "dry run" in a dry run; otherwise "not run" while any step is not run (the timed runs, until
# Story 11.11), else pass. Output: PASS/FAIL lines, PHASE lines, RECORD <file> and RESULT <result>.
# Exit codes: 0 only for a real pass; 1 for fail or not run (also a failed start); 3 for a dry run; 2 for a refusal (usage, configuration,
# candidate or phase order; nothing started); 75 when the lane's throwaway lock is busy (a dry run). Only exit 0 with "Result: pass" passes.
# A dry run needs docker compose, the IRIS base image and the mock image of ci/iris.sh, and the lane's variables of docker/tests/lib-live.sh
# (OCUTALON_LOCK_DIR, OCUTALON_LOCK_OWNER, OCUTALON_TEST_WEB_PORT); the model is the CI mock, never a key. Needs bash 3.2 or later and git.
set -u
umask 077

reh_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
reh_caller_pwd=$PWD
cd "$reh_root" || exit 1
. "$reh_root/release/lib-release.sh"
. "$reh_root/docker/tests/lib-keys.sh"

REH_ROWS="hosts copy install sign-in secrets runs"
REH_DIR=ocutalon-rehearsal
REH_STANDIN_BRANCH=rehearsal/stand-in
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

# rehearsal_result <real|dry> <results file>: fail when any step failed; otherwise dry run in a dry run; otherwise not run while any step is
# not run, else pass.
rehearsal_result() {
  local mode=$1 results=$2 row r anyfail=0 anynot=0
  for row in $REH_ROWS; do
    r=$(row_result "$results" "$row")
    case $r in
      fail) anyfail=1 ;;
      pass) ;;
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

# fail_line <step> <bound> <detail>: the one line of a failed step.
fail_line() { printf 'FAIL run install step %s bound %s: %s\n' "$1" "$2" "$3"; }

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
  o_dry=0
  while [ $# -gt 0 ]; do
    case $1 in
      --version | --rc | --candidate | --record)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          refuse "$1 needs a value"
          return 2
        fi
        case $1 in
          --version) o_version=$2 ;;
          --rc) o_rc=$2 ;;
          --candidate) o_candidate=$2 ;;
          --record) o_record=$2 ;;
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
  if [ -n "$o_version" ] && ! printf '%s\n' "$o_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.-]+)?$'; then
    refuse "--version '$o_version' is not a version number"
    return 2
  fi
  return 0
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
  release_config_read "$(release_config_path)"
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
  printf '%s\n' "${LIVE_LOCK_FILE:-}" > "$state/standin/lock.file"
  printf '%s\n' "${LIVE_LOCK_CONTENT:-}" > "$state/standin/lock.content"
  {
    printf '%s\n' "$test_base" "$src_ref"
    if [ "${#LIVE_IMAGES[@]}" -gt 0 ]; then printf '%s\n' "${LIVE_IMAGES[@]}"; fi
  } > "$state/standin/images"
  trap - EXIT INT TERM HUP
  rm -rf "$tmp"
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
        if [ "$row" = runs ]; then
          detail="the timed runs come with Story 11.11"
        elif [ "$anyfail" = 1 ]; then
          detail="an earlier step failed"
        else
          detail="the step did not run"
        fi
      fi
      printf '| %s | %s | %s |\n' "$(row_title "$row")" "$r" "$detail"
    done
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

phase_report() {
  local result detail rc
  env_set "$state/options" ended "$(now_utc)"
  step_record secrets pass "no .env or configuration value in the output or the record"
  section_build "$state/section.md"
  if ! detail=$(scan_run); then
    step_fail secrets - "$detail"
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

cmd_plan() {
  local hc hd
  parse_options "$@" || exit 2
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
  echo "PLAN phases install report down (run does all three); steps hosts copy install sign-in secrets"
  echo "PLAN record ${o_record:-$(record_path "$c_version" "$o_rc")}"
  exit 0
}

cmd_install() {
  local rc
  parse_options "$@" || exit 2
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
  local rc
  if [ $# -gt 0 ]; then
    rehearse_usage
    exit 2
  fi
  need_tag report || exit 2
  if [ ! -d "$state" ] || ! phase_done install; then
    refuse "report: the install phase of tag $OCUTALON_RUN_TAG has not finished (or there is no state); run install first"
    exit 2
  fi
  REHEARSAL_MODE=$(opt mode)
  if [ "$REHEARSAL_MODE" = real ]; then real_config || exit 2; fi
  reh_logged phase_report
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
  local me=$reh_root/release/rehearse.sh rc report_rc
  parse_options "$@" || exit 2
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then OCUTALON_RUN_TAG="reh-$(date +%s)"; fi
  export OCUTALON_RUN_TAG
  need_tag run || exit 2
  (cd "$reh_caller_pwd" && bash "$me" install "$@")
  rc=$?
  case $rc in
    2 | 75) exit "$rc" ;;
  esac
  if [ ! -d "$state" ]; then exit "$rc"; fi
  if ! phase_done install; then
    bash "$me" down
    exit "$rc"
  fi
  bash "$me" report
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
