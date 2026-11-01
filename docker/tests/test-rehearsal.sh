#!/usr/bin/env bash
# Hermetic self-test of the clean-machine rehearsal (Stories 11.3 and 11.11; release/rehearse.sh, release/lib-release.sh, env_file_hits of
# docker/tests/lib-keys.sh), with no container, no network call and no model. It sources the two release files and pins, in its own
# temporary folder:
#   - config: release_config_read and every refusal of the Config row, with no value in a refusal and no expansion of a value;
#   - host-run: host_run through a stub ssh that logs its argv and the size of its standard input: the options, the destination, --, the
#     port and known-hosts cases, a local driver, no env-file value in any argv, and a dry mode that never calls the stub;
#   - parsers: parse_install, machine_line (no host name), hosts_verdict, signin_config, the clean-host probe run on stub docker, git and
#     node, and standin_files (the stand-in's compose files);
#   - results: the FAIL line grammar, the Result rules and the exit codes;
#   - record: record_write (create with the heading, replace, append, another section byte for byte, no duplicate);
#   - env-hits: env_file_hits finds a planted value, names the variable, and never prints the value;
#   - dry-section: the record section of a dry run (Result, Mode, the stand-in candidate, the note) and of a real run
#   - stub-runs: the copied script, run for real in a synthetic git repository against stub hosts (the clean host a stub ssh, the driver
#     this machine with a stub curl): a hosts failure, a clone HEAD mismatch, a failed install.sh, and every step passing then report
#     (twice), a planted value, phase order and the Candidate refusals;
#   - bounds: bounds_eval on synthetic runs/1..20 folders: every bound's pass and miss, the run lists, the median, a missing mark, a failed
#     verdict, the planted bound (dry run only) and the Result rules over the merged rows;
#   - timed-runs: runs on stub hosts with a stub npm: a passing run and its files, a failing report, a run that reads nothing through exec,
#     the second run's refusal, the order refusals, the real-mode guards, exec's argv and its refusals, report --plant in real mode;
#   - real-tree: plan on this checkout starts nothing, a version that is not the candidate's and a report with no state exit 2;
#   - dry-report: report and report --plant on a dry state with a run: the plant reaches the evaluation through the command;
#   - dry-down: down of a dry run's state on a stub docker: the saved image names removed, the lane lock released only when its content
#     is the saved one, and the state removed;
#   - static: no sourcing of a variable path but the three libraries, no cat of an env file, umask 077, mode 100755, ASCII, strict host
#     keys and no docker push, login, save or export; the collector heredoc writes nothing.
# Each rule with a break first runs on a synthetic break (the rule pattern of test-upgrade-harness.sh): a check that can no longer fail
# makes its rule fail. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/release/lib-release.sh"
. "$root/release/rehearse.sh"
. "$root/docker/tests/lib-keys.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-rh.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN OCUTALON_RELEASE_CONFIG OCUTALON_REHEARSAL_SSH OCUTALON_INSTALL_WAIT
bad=0

eq() { # eq <label> <got> <want>
  if [ "$2" != "$3" ]; then
    echo "  $1: got '$2', wanted '$3'"
    bad=1
  fi
}
has() { # has <label> <text> <part>
  case $2 in
    *"$3"*) ;;
    *)
      echo "  $1: the text lacks '$3'"
      bad=1
      ;;
  esac
}
matches() { # matches <label> <text> <ere>
  if ! printf '%s\n' "$2" | grep -Eq -- "$3"; then
    echo "  $1: the text does not match '$3'"
    bad=1
  fi
}
lacks() { # lacks <label> <text> <part>
  case $2 in
    *"$3"*)
      echo "  $1: the text holds '$3'"
      bad=1
      ;;
  esac
}

fails_total=0
rule() { # rule <name> <check function> [<break function>]
  local name=$1 check=$2 brk=${3:-} out
  if [ -n "$brk" ]; then
    if ( "$brk"; "$check" ) > /dev/null 2>&1; then
      echo "FAIL $name: the check passes on the synthetic break $brk"
      fails_total=$((fails_total + 1))
      return
    fi
  fi
  if out=$("$check" 2>&1); then
    echo "PASS $name"
  else
    printf '%s\n' "$out" | head -n 14
    echo "FAIL $name"
    fails_total=$((fails_total + 1))
  fi
}

# --- the configuration ---

mkconf() { # mkconf <dir>: a good configuration in <dir>: release.conf, env (mode 600), clean.key, driver.key; the values name no real host
  mkdir -p "$1"
  printf 'key\n' > "$1/clean.key"
  printf 'key\n' > "$1/driver.key"
  printf 'ANTHROPIC_API_KEY=planted-env-value-123456\nSHORT=abc\n' > "$1/env"
  chmod 600 "$1/env"
  cat > "$1/release.conf" <<EOC
# a comment
OTHER_KEY=ignored-value
DEMO_HOST=demo-ignored
REHEARSAL_CLEAN_SSH=cleanuser@clean-host-7.invalid
REHEARSAL_CLEAN_KEY=$1/clean.key
REHEARSAL_CLEAN_WEB=clean-web-9.invalid
REHEARSAL_DRIVER_SSH=driveruser@driver-host-3.invalid
REHEARSAL_DRIVER_KEY=$1/driver.key
REHEARSAL_ENV_FILE=$1/env
EOC
  chmod 600 "$1/release.conf"
}

mkconf_local() { # mkconf_local <dir>: the good configuration with a local driver (a real rehearsal drives the browser on this machine)
  mkconf "$1"
  grep -v '^REHEARSAL_DRIVER_KEY=' "$1/release.conf" | sed 's/^REHEARSAL_DRIVER_SSH=.*/REHEARSAL_DRIVER_SSH=local/' > "$1/release.conf.new"
  mv "$1/release.conf.new" "$1/release.conf"
  chmod 600 "$1/release.conf"
}

conf_without() { # conf_without <dir> <key>: release.conf of the dir without that key's line
  grep -v "^$2=" "$1/release.conf" > "$1/release.conf.new"
  mv "$1/release.conf.new" "$1/release.conf"
}

t_config() {
  local bad=0 d=$tmp/cfg1 out rc k
  mkconf "$d"
  release_config_read "$d/release.conf" > "$tmp/good.out"
  rc=$?
  eq "a good configuration reads" "$rc" 0
  eq "the clean host is set" "$REHEARSAL_CLEAN_SSH" "cleanuser@clean-host-7.invalid"
  eq "the env file is set" "$REHEARSAL_ENV_FILE" "$d/env"
  eq "a key without the prefix is ignored" "${OTHER_KEY:-unset}" unset
  eq "an optional key stays unset" "${REHEARSAL_CLEAN_PORT:-unset}" unset

  out=$(release_config_read "$d/none.conf")
  rc=$?
  eq "a missing file is refused" "$rc" 2
  has "the refusal names the file kind" "$out" "configuration file"

  for k in CLEAN_SSH CLEAN_KEY CLEAN_WEB DRIVER_SSH DRIVER_KEY ENV_FILE; do
    mkconf "$tmp/cfg-$k"
    conf_without "$tmp/cfg-$k" "REHEARSAL_$k"
    out=$(release_config_read "$tmp/cfg-$k/release.conf")
    rc=$?
    eq "a missing REHEARSAL_$k is refused" "$rc" 2
    has "the refusal names REHEARSAL_$k" "$out" "REHEARSAL_$k"
    lacks "the refusal prints no host value" "$out" "clean-host-7"
    lacks "the refusal prints no other host value" "$out" "driver-host-3"
  done

  mkconf "$tmp/cfg-local"
  conf_without "$tmp/cfg-local" REHEARSAL_DRIVER_KEY
  sed -i.bak 's/^REHEARSAL_DRIVER_SSH=.*/REHEARSAL_DRIVER_SSH=local/' "$tmp/cfg-local/release.conf" && rm -f "$tmp/cfg-local/release.conf.bak"
  release_config_read "$tmp/cfg-local/release.conf" > /dev/null
  eq "a local driver needs no key" "$?" 0

  mkconf "$tmp/cfg-unknown"
  printf 'REHEARSAL_BOGUS=secret-bogus-value\n' >> "$tmp/cfg-unknown/release.conf"
  out=$(release_config_read "$tmp/cfg-unknown/release.conf")
  eq "an unknown REHEARSAL_ key is refused" "$?" 2
  has "the refusal names the key" "$out" "REHEARSAL_BOGUS"
  lacks "the refusal does not print its value" "$out" "secret-bogus-value"

  mkconf "$tmp/cfg-group"
  chmod 640 "$tmp/cfg-group/env"
  out=$(release_config_read "$tmp/cfg-group/release.conf")
  eq "an env file readable by group is refused" "$?" 2
  has "the refusal names the env file" "$out" "env file"
  chmod 604 "$tmp/cfg-group/env"
  release_config_read "$tmp/cfg-group/release.conf" > /dev/null
  eq "an env file readable by others is refused" "$?" 2

  mkconf "$tmp/cfg-repo"
  (
    release_lib_root=$(cd "$tmp/cfg-repo" && pwd -P)
    out=$(release_config_read "$tmp/cfg-repo/release.conf")
    echo "$? $out"
  ) > "$tmp/repo-cfg.out"
  has "a configuration file inside the repository is refused" "$(cat "$tmp/repo-cfg.out")" "2 REFUSED config: the configuration file is inside the repository"
  mkconf "$tmp/cfg-repoenv"
  (
    mkdir -p "$tmp/cfg-repoenv/inner"
    release_lib_root=$(cd "$tmp/cfg-repoenv/inner" && pwd -P)
    cp "$tmp/cfg-repoenv/env" "$release_lib_root/env"
    sed -i.bak "s#^REHEARSAL_ENV_FILE=.*#REHEARSAL_ENV_FILE=$release_lib_root/env#" "$tmp/cfg-repoenv/release.conf"
    out=$(release_config_read "$tmp/cfg-repoenv/release.conf")
    echo "$? $out"
  ) > "$tmp/repo-env.out"
  has "an env file inside the repository is refused" "$(cat "$tmp/repo-env.out")" "2 REFUSED config: the env file is inside the repository"

  mkconf "$tmp/cfg-sub"
  printf 'REHEARSAL_CLEAN_SSH=$(touch %s/marker)\n' "$tmp/cfg-sub" >> "$tmp/cfg-sub/release.conf"
  release_config_read "$tmp/cfg-sub/release.conf" > /dev/null
  eq "a command substitution in a value is not run" "$([ -e "$tmp/cfg-sub/marker" ] && echo ran || echo none)" none
  eq "it stays literal" "$REHEARSAL_CLEAN_SSH" "\$(touch $tmp/cfg-sub/marker)"

  mkconf "$tmp/cfg-home"
  mkdir -p "$tmp/hdir"
  printf 'k\n' > "$tmp/hdir/mykey"
  sed -i.bak 's#^REHEARSAL_CLEAN_KEY=.*#REHEARSAL_CLEAN_KEY=~/mykey#' "$tmp/cfg-home/release.conf" && rm -f "$tmp/cfg-home/release.conf.bak"
  (HOME=$tmp/hdir release_config_read "$tmp/cfg-home/release.conf" > /dev/null; echo "$REHEARSAL_CLEAN_KEY") > "$tmp/home.out"
  eq "a leading ~/ of a path key is the home folder" "$(cat "$tmp/home.out")" "$tmp/hdir/mykey"

  eq "the default path follows XDG_CONFIG_HOME" "$(XDG_CONFIG_HOME=/x release_config_path)" "/x/ocutalon/release.conf"
  eq "OCUTALON_RELEASE_CONFIG wins" "$(OCUTALON_RELEASE_CONFIG=/y/z.conf release_config_path)" "/y/z.conf"
  [ "$bad" -eq 0 ]
}
# The break: a file in the repository is no longer refused.
b_config() { release_in_repo() { return 1; }; }

# --- host_run ---

mkstub() { # mkstub <dir>: a stub ssh that logs its argv and the size of its standard input into $STUB_LOG, and answers by command
  mkdir -p "$1"
  cat > "$1/ssh" <<'EOS'
#!/usr/bin/env bash
args=("$@")
n=${#args[@]}
cmd=${args[$((n - 1))]}
dest=${args[$((n - 2))]}
inp=$(mktemp)
cat > "$inp"
size=$(wc -c < "$inp" | tr -d ' ')
{
  echo "CALL dest=$dest stdin=$size"
  for a in "$@"; do echo "ARG $a"; done
  echo "END"
} >> "$STUB_LOG"
case $dest in
  clean*)
    case $cmd in
      *'command -v git'*) cat "$STUB_CLEAN_PROBE" ;;
      *'cat > ocutalon-rehearsal/candidate.bundle'*) (cd "$STUB_REMOTE" && sh -c "$cmd" < "$inp") ;;
      *'git clone'*)
        out=$(cd "$STUB_REMOTE" && sh -c "$cmd")
        rc=$?
        if [ -n "${STUB_CLONE_SHA:-}" ]; then printf '%s\n' "$STUB_CLONE_SHA"; else printf '%s\n' "$out"; fi
        rm -f "$inp"
        exit $rc
        ;;
      *'cat > .env'*) (cd "$STUB_REMOTE" && sh -c "$cmd" < "$inp") ;;
      *'bash install.sh'*)
        sleep "${STUB_SLEEP:-0}"
        cat "$STUB_INSTALL_OUT"
        rm -f "$inp"
        exit "${STUB_INSTALL_RC:-0}"
        ;;
      *'docker compose exec'*)
        if grep -q 'CHK|done|1' "$inp"; then
          cp "$inp" "${STUB_COLLECTOR_IN:-/dev/null}"
          cat "${STUB_COLLECTOR_OUT:-/dev/null}"
        elif grep -q 'CHK|now|' "$inp"; then
          echo "CHK|now|${STUB_NOW:-2026-11-01 10:00:00.000}"
        else
          echo "CHK|x|1"
        fi
        ;;
      *echo*hi*) echo hi ;;
      *)
        echo "stub: unexpected clean command" >&2
        rm -f "$inp"
        exit 97
        ;;
    esac
    ;;
  driver*)
    case $cmd in
      *'command -v curl'*) cat "$STUB_DRIVER_PROBE" ;;
      *'curl -K -'*)
        cp "$inp" "$STUB_CURL_CFG"
        echo "${STUB_DRIVER_PAGE:-<html><app-root></app-root></html>}"
        ;;
      *)
        echo "stub: unexpected driver command" >&2
        rm -f "$inp"
        exit 97
        ;;
    esac
    ;;
  *) exit 98 ;;
esac
rm -f "$inp"
exit 0
EOS
  chmod 755 "$1/ssh"
  cat > "$1/clean.probe" <<'EOS'
git=1
docker=1
containers=0
volumes=0
node=0
os=Linux
arch=x86_64
name=Ubuntu 24.04.1 LTS
mem=16777216000
nodename=stub-host-secret-1
EOS
  cat > "$1/driver.probe" <<'EOS'
curl=1
os=Darwin
arch=arm64
name=26.0.1
mem=68719476736
nodename=driver-secret-2
EOS
  cat > "$1/install.out" <<'EOS'
OcuTalon install
Docker is running on x64, and Docker Compose is v2.40.0.
Found .env. It was not changed.

OcuTalon is ready after 1 min 5 s.

  Open:      http://localhost:52801/ocutalon/
  User:      ocu-user
  Password:  ocu-pass-1
EOS
}

mkbin() { # mkbin <dir>: stub curl and npm for a local driver: curl keeps its config and prints the page, npm plays the browser run
  mkdir -p "$1"
  cat > "$1/curl" <<'EOS'
#!/bin/sh
cat > "$STUB_CURL_CFG"
echo "${STUB_DRIVER_PAGE:-<html><app-root></app-root></html>}"
exit 0
EOS
  cat > "$1/npm" <<'EOS'
#!/bin/sh
echo "$*" >> "$STUB_NPM_LOG"
printf '%s\n' "URL=$OCUTALON_URL" "MODEL=$OCUTALON_DEMO_PATH_MODEL" "TIMEOUT=$OCUTALON_E2E_TIMEOUT_MS" "RUN=$OCUTALON_REHEARSAL_RUN" "TAG=$OCUTALON_RUN_TAG" "KEY=${ANTHROPIC_API_KEY-unset}" "EXEC=$OCUTALON_E2E_IRIS_EXEC" "MARKS=$OCUTALON_E2E_MARKS" > "$STUB_NPM_ENV"
cp "${STUB_NPM_REPORT:?}" "$OCUTALON_E2E_JSON"
cat "${STUB_NPM_MARKS:?}" >> "$OCUTALON_E2E_MARKS"
if [ -z "${STUB_NPM_NOEXEC:-}" ]; then
  printf 'Write !,"CHK|x|1"\nHalt\n' | sh -c "$OCUTALON_E2E_IRIS_EXEC" > /dev/null
fi
echo "stub npm: 1 test file ran"
exit "${STUB_NPM_RC:-0}"
EOS
  chmod 755 "$1/curl" "$1/npm"
  # A passing Playwright report of the eight steps (the shape demo-path-summary.mjs reads), and one whose approval step failed.
  node -e '
    const steps = ["page","watch","reminder","incident","approval","trace","failure-paths","quiet-outcomes"];
    const build = (failed) => ({ suites: steps.map((id, i) => ({
      file: `0${i + 1}-${id}.spec.ts`,
      specs: [{ title: id + " works", tags: i === 0 ? ["floor"] : [], tests: [{ annotations: [], results: [{ status: id === failed ? "failed" : "passed", annotations: [] }] }] }],
    })), errors: [] });
    const fs = require("node:fs");
    fs.writeFileSync(process.argv[1], JSON.stringify(build("")));
    fs.writeFileSync(process.argv[2], JSON.stringify(build("approval")));
  ' "$1/report.pass.json" "$1/report.fail.json"
  printf 'step1_sent 1000\nstep1_decision_seen 3100\nstep1_reply_seen 3300\napprove_pressed 9000\napproval_result_seen 9600\n' > "$1/marks.page"
  cat > "$1/collector.out" <<'EOS'
CHK|mark|press|100000
CHK|mark|first_failure|101000
CHK|mark|pickup|103900
CHK|mark|settle_end|113600
CHK|mark|diagnosis_end|114400
CHK|mark|delivered|114600
CHK|reminder|150000|151000
CHK|late|0|1
CHK|mark|reminder_msg|200000
CHK|mark|result_msg|214000
CHK|tokens|1520
CHK|done|1
EOS
}

t_host_run() {
  local bad=0 d=$tmp/hr log out argv
  mkstub "$d/stub"
  mkconf "$d/cfg"
  log=$d/stub.log
  : > "$log"
  (
    export STUB_LOG=$log
    export OCUTALON_REHEARSAL_SSH=$d/stub/ssh
    release_config_read "$d/cfg/release.conf" > /dev/null
    REHEARSAL_MODE=real
    printf 'abc' | host_run clean 'echo hi'
    host_run driver 'curl --version' < /dev/null > /dev/null 2>&1
  ) > "$d/out" 2>&1
  argv=$(cat "$log")
  has "the clean host is called with its key" "$argv" "ARG -i
ARG $d/cfg/clean.key"
  has "BatchMode is on" "$argv" "ARG -o
ARG BatchMode=yes"
  has "only the named key is used" "$argv" "ARG IdentitiesOnly=yes"
  has "the connection times out" "$argv" "ARG ConnectTimeout=15"
  has "the destination follows --" "$argv" "ARG --
ARG cleanuser@clean-host-7.invalid
ARG echo hi"
  has "the standard input reaches the host" "$argv" "CALL dest=cleanuser@clean-host-7.invalid stdin=3"
  has "the driver is another destination" "$argv" "CALL dest=driveruser@driver-host-3.invalid stdin=0"
  has "host keys are checked strictly, whatever the ssh configuration says" "$argv" "ARG -o
ARG StrictHostKeyChecking=yes"
  lacks "host key checking is never switched off" "$argv" "StrictHostKeyChecking=no"
  lacks "nor set to accept a new key" "$argv" "accept-new"
  lacks "no known-hosts option without the key" "$argv" "UserKnownHostsFile"
  lacks "no port option without the key" "$argv" "ARG -p"

  : > "$log"
  (
    export STUB_LOG=$log
    export OCUTALON_REHEARSAL_SSH=$d/stub/ssh
    release_config_read "$d/cfg/release.conf" > /dev/null
    REHEARSAL_MODE=real
    REHEARSAL_CLEAN_PORT=2222
    REHEARSAL_KNOWN_HOSTS=$d/cfg/clean.key
    host_run clean 'echo hi' < /dev/null
  ) > "$d/out2" 2>&1
  argv=$(cat "$log")
  has "a known-hosts file is passed as an option" "$argv" "ARG UserKnownHostsFile=$d/cfg/clean.key"
  has "the port follows -p" "$argv" "ARG -p
ARG 2222
ARG --"

  # The env file goes in as standard input and never into an argument.
  : > "$log"
  (
    export STUB_LOG=$log STUB_REMOTE=$d/remote
    export OCUTALON_REHEARSAL_SSH=$d/stub/ssh
    mkdir -p "$d/remote/ocutalon-rehearsal/candidate"
    release_config_read "$d/cfg/release.conf" > /dev/null
    REHEARSAL_MODE=real
    host_run clean '{ cd ocutalon-rehearsal/candidate && umask 077 && cat > .env; } 2>&1' < "$d/cfg/env"
  ) > "$d/out3" 2>&1
  argv=$(cat "$log")
  has "the env file's size reaches the host as stdin" "$argv" "stdin=$(wc -c < "$d/cfg/env" | tr -d ' ')"
  lacks "no env value in any argument" "$argv" "planted-env-value-123456"
  eq "the stdin reached the host intact" "$(cmp "$d/cfg/env" "$d/remote/ocutalon-rehearsal/candidate/.env" && echo same)" same

  # A local driver runs sh -c on this machine, in the local folder, and the stub is not called.
  : > "$log"
  mkdir -p "$d/localdir"
  out=$(
    export STUB_LOG=$log
    export OCUTALON_REHEARSAL_SSH=$d/stub/ssh
    release_config_read "$d/cfg/release.conf" > /dev/null
    REHEARSAL_MODE=real
    REHEARSAL_DRIVER_SSH=local
    REHEARSAL_LOCAL_DIR=$d/localdir
    printf 'xyz' | host_run driver 'pwd; cat'
  )
  has "a local driver runs in the local folder" "$out" "/localdir"
  has "its standard input passes through" "$out" "xyz"
  eq "a local driver never calls the stub" "$(wc -c < "$log" | tr -d ' ')" 0

  # Dry mode: sh -c in the stand-in folders, and the stub is never called.
  : > "$log"
  mkdir -p "$d/standin/clean" "$d/standin/driver"
  out=$(
    export STUB_LOG=$log
    export OCUTALON_REHEARSAL_SSH=$d/stub/ssh
    REHEARSAL_MODE=dry
    REHEARSAL_STANDIN=$d/standin
    STANDIN_PROJECT=proj-x STANDIN_FILES=a:b STANDIN_IMAGE=img-y STANDIN_WAIT=77
    ANTHROPIC_API_KEY=should-not-pass
    export ANTHROPIC_API_KEY
    host_run clean 'pwd; echo "$COMPOSE_PROJECT_NAME $COMPOSE_FILE $IRIS_IMAGE $OCUTALON_INSTALL_WAIT [${ANTHROPIC_API_KEY:-}]"' < /dev/null
    host_run driver 'pwd' < /dev/null
  )
  has "the clean stand-in runs in its folder" "$out" "/standin/clean"
  has "the clean stand-in carries the throwaway's compose environment" "$out" "proj-x a:b img-y 77 []"
  has "the driver stand-in runs in its folder" "$out" "/standin/driver"
  eq "a dry run never calls the stub ssh" "$(wc -c < "$log" | tr -d ' ')" 0
  [ "$bad" -eq 0 ]
}
# The break: host_run in dry mode calls the stub ssh.
b_host_run() {
  eval "$(declare -f host_run | sed 's/^host_run/orig_host_run/')"
  host_run() { REHEARSAL_MODE=real REHEARSAL_CLEAN_SSH=${REHEARSAL_CLEAN_SSH:-d@h} orig_host_run "$@"; }
}

# --- the parsers ---

t_parsers() {
  local bad=0 f=$tmp/pi.out p out
  mkstub "$tmp/pp"
  cp "$tmp/pp/install.out" "$f"
  parse_install "$f"
  eq "install.sh's output parses" "$?" 0
  eq "the printed address" "$PI_URL" "http://localhost:52801/ocutalon/"
  eq "the printed port" "$PI_PORT" "52801"
  eq "the printed user" "$PI_USER" ocu-user
  eq "the printed password" "$PI_PASSWORD" ocu-pass-1
  eq "the ready text is kept" "$PI_READY" "OcuTalon is ready after 1 min 5 s."
  for p in Open User Password; do
    grep -v "^  $p:" "$f" > "$tmp/pi-$p.out"
    parse_install "$tmp/pi-$p.out"
    eq "a missing $p: line fails" "$?" 1
    eq "it names $p:" "$PI_MISSING" "$p:"
  done
  printf '  Open:      http://localhost/ocutalon/\n  User: u\n  Password: p\n' > "$tmp/pi-noport.out"
  parse_install "$tmp/pi-noport.out"
  eq "an address with no port fails" "$?" 1
  : > "$tmp/pi-empty.out"
  parse_install "$tmp/pi-empty.out"
  eq "an empty output names all three lines" "$PI_MISSING" "Open: User: Password:"

  out=$(machine_line "$(printf 'os=Linux\narch=x86_64\nname=Ubuntu 24.04.1 LTS\nmem=16777216000\nnodename=stub-host-secret-1\n')")
  eq "a Linux machine line" "$out" "Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory"
  lacks "the machine line holds no host name" "$out" "stub-host-secret"
  lacks "the machine line holds not this machine's host name either" "$out" "$(uname -n)"
  out=$(machine_line "$(printf 'os=Darwin\narch=arm64\nname=26.0.1\nmem=68719476736\nnodename=driver-secret-2\n')")
  eq "a Darwin machine line" "$out" "macOS 26.0.1, arm64, 64.0 GiB memory"
  lacks "the Darwin line holds no host name" "$out" "driver-secret"
  eq "an unreadable probe says so" "$(machine_line "")" "unknown system, unknown CPU, unknown memory"

  local good bad1 drv
  good=$(printf 'git=1\ndocker=1\ncontainers=0\nvolumes=0\nnode=0\nos=Linux\narch=x86_64\n')
  drv=$(printf 'curl=1\nos=Darwin\n')
  hosts_verdict real "$good" "$drv" > /dev/null
  eq "a clean pair passes" "$?" 0
  out=$(hosts_verdict real "${good/git=1/git=0}" "$drv")
  eq "no git fails" "$?" 1
  has "it says git" "$out" "git is not installed"
  out=$(hosts_verdict real "${good/docker=1/docker=0}" "$drv")
  eq "no Docker fails" "$?" 1
  has "it says Docker" "$out" "Docker is not installed"
  out=$(hosts_verdict real "${good/containers=0/containers=2}" "$drv")
  eq "a container fails" "$?" 1
  has "it says container" "$out" "container or volume exists"
  out=$(hosts_verdict real "${good/volumes=0/volumes=1}" "$drv")
  eq "a volume fails" "$?" 1
  out=$(hosts_verdict real "${good/node=0/node=1}" "$drv")
  eq "Node.js fails a real run" "$?" 1
  has "it says Node.js" "$out" "Node.js is installed"
  hosts_verdict dry "${good/node=0/node=1}" "$drv" > /dev/null
  eq "Node.js does not fail a dry run" "$?" 0
  out=$(hosts_verdict real "$good" "${drv/curl=1/curl=0}")
  eq "no curl on the driver fails" "$?" 1
  has "it says curl" "$out" "curl is not installed"
  hosts_verdict real "garbage" "$drv" > /dev/null
  eq "a reply that is not understood fails" "$?" 1
  hosts_verdict real "${good/containers=0/containers=x}" "$drv" > /dev/null
  eq "a count that is not a number fails" "$?" 1
  hosts_verdict real "$(printf '%s\n' "$good" | grep -v '^containers=')" "$drv" > /dev/null
  eq "a reply with no containers count fails" "$?" 1
  hosts_verdict real "$(printf '%s\n' "$good" | grep -v '^volumes=')" "$drv" > /dev/null
  eq "a reply with no volumes count fails" "$?" 1

  # The clean-host probe itself, on stub docker, git and node: it counts the compose project's containers (also stopped ones) and volumes.
  local pb=$tmp/probe-bin probe
  mkdir -p "$pb"
  cat > "$pb/docker" <<'EOS'
#!/bin/sh
a=" $* "
case $a in *" info "*) echo 27.0.1; exit 0 ;; esac
case $a in *" label=com.docker.compose.project=$STUB_P "*) ;; *) exit 0 ;; esac
case $a in
  *" ps -a "*) printf 'c1\nc2\n' ;;
  *" volume ls "*) printf 'v1\n' ;;
esac
exit 0
EOS
  printf '#!/bin/sh\nexit 0\n' > "$pb/git"
  printf '#!/bin/sh\nexit 0\n' > "$pb/node"
  chmod 755 "$pb/docker" "$pb/git" "$pb/node"
  probe=$(cd "$pb" && env -u COMPOSE_PROJECT_NAME PATH="$pb:/usr/bin:/bin:/usr/sbin:/sbin" STUB_P=ocutalon sh -c "$PROBE_CLEAN" 2> /dev/null)
  has "the probe finds git" "$probe" "git=1"
  has "the probe finds Docker" "$probe" "docker=1"
  has "the probe counts the containers of project ocutalon" "$probe" "containers=2"
  has "the probe counts its volumes" "$probe" "volumes=1"
  has "the probe finds Node.js" "$probe" "node=1"
  matches "the probe gives the system" "$probe" '^os=[A-Za-z]'
  matches "the probe gives the CPU" "$probe" '^arch=.'
  matches "the probe asks for the memory" "$probe" '^mem='
  out=$(hosts_verdict real "$probe" "$drv")
  eq "a probed host with a leftover stack fails" "$?" 1
  has "it names the leftover" "$out" "(2 container(s), 1 volume(s))"
  probe=$(cd "$pb" && env PATH="$pb:/usr/bin:/bin:/usr/sbin:/sbin" COMPOSE_PROJECT_NAME=other STUB_P=ocutalon sh -c "$PROBE_CLEAN" 2> /dev/null)
  has "another COMPOSE_PROJECT_NAME counts its own project only" "$probe" "containers=0"
  probe=$(cd "$pb" && env PATH="$pb:/usr/bin:/bin:/usr/sbin:/sbin" COMPOSE_PROJECT_NAME=other STUB_P=other sh -c "$PROBE_CLEAN" 2> /dev/null)
  has "and finds that project's containers" "$probe" "containers=2"

  # The stand-in's compose files: lib-live's temporary files move into the state, the worktree's files become the clone's.
  out=$(standin_files /t /r /c /s /r/docker-compose.yml /t/decoy.yml /r/docker/tests/compose.throwaway.yml /r/ci/compose.ci.yml /t/port.yml /x/other.yml)
  eq "the stand-in's COMPOSE_FILE" "$out" "/c/docker-compose.yml:/s/decoy.yml:/c/docker/tests/compose.throwaway.yml:/c/ci/compose.ci.yml:/s/port.yml:/x/other.yml"

  out=$(signin_config "http://127.0.0.1:52801/ocutalon/" "ocu\"talon" 'p\w')
  has "the config signs in as the printed user" "$out" 'data-urlencode = "IRISUsername=ocu\"talon"'
  has "the config escapes a backslash" "$out" 'data-urlencode = "IRISPassword=p\\w"'
  eq "the config has three transfers" "$(printf '%s\n' "$out" | grep -c '^url = ')" 3
  [ "$bad" -eq 0 ]
}
# The break: machine_line adds this machine's host name.
b_parsers() {
  eval "$(declare -f machine_line | sed 's/^machine_line/orig_machine_line/')"
  machine_line() { printf '%s %s\n' "$(orig_machine_line "$@")" "$(uname -n)"; }
}

# --- results ---

t_results() {
  local bad=0 r=$tmp/results.txt
  eq "the FAIL line grammar" "$(fail_line hosts - "git is not installed")" "FAIL run install step hosts bound -: git is not installed"
  eq "a bound goes in the line" "$(fail_line install "ready within 900 s" "install.sh exited 1")" "FAIL run install step install bound ready within 900 s: install.sh exited 1"
  printf 'hosts|pass|x\ncopy|pass|x\ninstall|pass|x\nsign-in|pass|x\nsecrets|pass|x\n' > "$r"
  eq "a real run whose steps pass is not run (no timed run)" "$(rehearsal_result real "$r")" "not run"
  eq "a dry run is a dry run" "$(rehearsal_result dry "$r")" "dry run"
  local row
  for row in runs notice pick-up settle-end diagnosis delivery decision approval-result reminder largest-request; do printf '%s|pass|x\n' "$row" >> "$r"; done
  for row in median first-reply reminder-result; do printf '%s|recorded|x\n' "$row" >> "$r"; done
  eq "a real run with the tell-now row not run is not run" "$(rehearsal_result real "$r")" "not run"
  printf 'tell-now|not run|x\n' >> "$r"
  eq "an explicit not-run tell-now row is not run too" "$(rehearsal_result real "$r")" "not run"
  grep -v '^tell-now|' "$r" > "$r.new"
  mv "$r.new" "$r"
  printf 'tell-now|pass|x\n' >> "$r"
  eq "a real run with every row met is a pass" "$(rehearsal_result real "$r")" pass
  eq "a dry run never passes" "$(rehearsal_result dry "$r")" "dry run"
  printf 'pick-up|fail|x\n' >> "$r"
  grep -v '^pick-up|pass' "$r" > "$r.new"
  mv "$r.new" "$r"
  eq "a missed bound fails a real run" "$(rehearsal_result real "$r")" fail
  eq "a missed bound fails a dry run" "$(rehearsal_result dry "$r")" fail
  grep -v '^pick-up|' "$r" > "$r.new"
  mv "$r.new" "$r"
  printf 'pick-up|pass|x\n' >> "$r"
  printf 'copy|fail|x\n' >> "$r"
  grep -v '^copy|pass' "$r" > "$r.new"
  mv "$r.new" "$r"
  eq "a failed step fails a real run" "$(rehearsal_result real "$r")" fail
  eq "a failed step fails a dry run" "$(rehearsal_result dry "$r")" fail
  eq "an empty result is not run" "$(rehearsal_result real /dev/null)" "not run"
  eq "exit for pass" "$(rehearsal_exit pass)" 0
  eq "exit for fail" "$(rehearsal_exit fail)" 1
  eq "exit for not run" "$(rehearsal_exit "not run")" 1
  eq "exit for dry run" "$(rehearsal_exit "dry run")" 3
  [ "$bad" -eq 0 ]
}
b_results() { rehearsal_exit() { echo 0; }; }

# --- the record writer ---

t_record() {
  local bad=0 rec=$tmp/rec/1.0.0/rc2.md sec=$tmp/sec.md other before after
  printf '## Clean-machine rehearsal\n\nResult: dry run\nMode: dry run\n' > "$sec"
  rm -rf "$tmp/rec"
  record_write "$rec" "$sec" "# OcuTalon 1.0.0 rc2"
  eq "a missing file and its folder are created with the heading" "$(head -n 1 "$rec")" "# OcuTalon 1.0.0 rc2"
  eq "the section is there once" "$(grep -c '^## Clean-machine rehearsal$' "$rec")" 1
  rm -rf "$tmp/rec"
  record_write "$rec" "$sec"
  eq "the default heading is read from the path" "$(head -n 1 "$rec")" "# OcuTalon 1.0.0 rc2"
  record_write "$tmp/rec/other.md" "$sec"
  eq "the default heading of another path" "$(head -n 1 "$tmp/rec/other.md")" "# OcuTalon candidate record"

  printf '\n## Upgrade harness\n\nResult: pass\n| a | b |\n\n## Release checklist\n\nResult: not confirmed\n' >> "$rec"
  other=$(sed -n '/^## Upgrade harness$/,$p' "$rec")
  before=$(printf '%s\n' "$other" | cksum)
  printf '## Clean-machine rehearsal\n\nResult: fail\nMode: rehearsal\n' > "$sec"
  record_write "$rec" "$sec" "# OcuTalon 1.0.0 rc2"
  eq "the section is replaced, not duplicated" "$(grep -c '^## Clean-machine rehearsal$' "$rec")" 1
  eq "the new text is in the file" "$(grep -c '^Result: fail$' "$rec")" 1
  eq "the old text is gone" "$(grep -c '^Result: dry run$' "$rec")" 0
  after=$(sed -n '/^## Upgrade harness$/,$p' "$rec" | cksum)
  eq "the other sections are kept byte for byte" "$after" "$before"
  record_write "$rec" "$sec"
  eq "still one section after a third write" "$(grep -c '^## Clean-machine rehearsal$' "$rec")" 1

  # The other writer's direction: the upgrade harness replaces its own section and keeps this one byte for byte (the library is shared).
  printf '## Upgrade harness\n\nResult: fail\nMode: tag\n' > "$tmp/sec.harness.md"
  before=$(sed -n '/^## Clean-machine rehearsal$/,/^## Upgrade harness$/p' "$rec" | sed '$d' | cksum)
  record_write "$rec" "$tmp/sec.harness.md" "# OcuTalon 1.0.0 rc2"
  eq "the harness section is replaced once" "$(grep -c '^## Upgrade harness$' "$rec")" 1
  eq "the harness section holds the new text" "$(sed -n '/^## Upgrade harness$/,/^## Release checklist$/p' "$rec" | grep -c '^Result: fail$')" 1
  eq "the rehearsal section is kept byte for byte" "$(sed -n '/^## Clean-machine rehearsal$/,/^## Upgrade harness$/p' "$rec" | sed '$d' | cksum)" "$before"
  eq "the checklist section after it is kept" "$(grep -c '^Result: not confirmed$' "$rec")" 1

  # The section in the middle of the file ends at the next heading, and a blank line separates them.
  printf '# OcuTalon 1.0.0 rc3\n\n## Clean-machine rehearsal\n\nResult: old\n\n## Upgrade harness\n\nResult: pass\n' > "$tmp/rec/mid.md"
  record_write "$tmp/rec/mid.md" "$sec"
  eq "a middle section is replaced" "$(grep -c '^Result: old$' "$tmp/rec/mid.md")" 0
  eq "the next section follows after a blank line" "$(grep -B1 '^## Upgrade harness$' "$tmp/rec/mid.md" | head -n 1)" ""
  eq "the next section keeps its text" "$(grep -c '^Result: pass$' "$tmp/rec/mid.md")" 1

  # A file with another section only gets this one appended.
  printf '# OcuTalon 1.0.0 rc4\n\n## Upgrade harness\n\nResult: pass\n' > "$tmp/rec/app.md"
  record_write "$tmp/rec/app.md" "$sec"
  eq "a section is appended after the others" "$(grep -n '^## ' "$tmp/rec/app.md" | sed 's/^[0-9]*://' | tr '\n' ',')" "## Upgrade harness,## Clean-machine rehearsal,"
  eq "the path is record_path" "$(record_path 1.0.0 3)" "release/records/1.0.0/rc3.md"
  [ "$bad" -eq 0 ]
}
# The break: the writer always appends.
b_record() {
  record_write() {
    local file=$1 section=$2
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || printf '%s\n\n' "${3:-# OcuTalon candidate record}" > "$file"
    printf '\n' >> "$file"
    cat "$section" >> "$file"
  }
}

# --- env_file_hits ---

t_env_hits() {
  local bad=0 d=$tmp/eh out rc
  mkdir -p "$d"
  printf '# comment\nANTHROPIC_API_KEY=planted-env-value-123456\nexport QUOTED="quoted-secret-value-9"\nSHORT=abc\nEMPTY=\n' > "$d/env"
  printf 'nothing here\nthe value planted-env-value-123456 is here\nSHORT=abc and EMPTY\nquoted-secret-value-9\n' > "$d/log"
  printf 'clean line\n' > "$d/clean"
  out=$(env_file_hits "$d/env" "$d/log" "$d/clean")
  rc=$?
  eq "it returns 0" "$rc" 0
  has "a planted value is found and named" "$out" "$d/log:2 ANTHROPIC_API_KEY"
  has "a quoted value is found and named" "$out" "$d/log:4 QUOTED"
  lacks "the value is never printed" "$out" "planted-env-value"
  lacks "the quoted value is never printed" "$out" "quoted-secret"
  lacks "a short value is not read" "$out" "SHORT"
  lacks "an empty value is not read" "$out" "EMPTY"
  lacks "a clean file has no hit" "$out" "$d/clean"
  out=$(printf 'x planted-env-value-123456\n' | env_file_hits "$d/env" -)
  has "the standard input is read as -" "$out" "-:1 ANTHROPIC_API_KEY"
  env_file_hits "$d/env" "$d/none" > /dev/null
  eq "an unreadable file returns 1" "$?" 1
  env_file_hits "$d/none" "$d/log" > /dev/null
  eq "an unreadable env file returns 1" "$?" 1
  [ "$bad" -eq 0 ]
}
# The break: the scan prints the value it found.
b_env_hits() {
  env_file_hits() { grep -n 'planted-env-value' "$2"; }
}

# --- the record section of a dry run ---

t_dry_section() {
  local bad=0 st=$tmp/dsec out sec
  mkdir -p "$st"
  state=$st
  : > "$st/options"
  env_set "$st/options" version 1.0.0
  env_set "$st/options" rc 1
  env_set "$st/options" mode dry
  env_set "$st/options" branch rehearsal/stand-in
  env_set "$st/options" cand_sha 1111111111111111111111111111111111111111
  env_set "$st/options" base_sha 2222222222222222222222222222222222222222
  env_set "$st/options" started 2026-11-01T10:00:00Z
  env_set "$st/options" ended 2026-11-01T10:05:00Z
  printf 'Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory; Node.js absent\n' > "$st/machine.clean"
  printf 'macOS 26.0.1, arm64, 64.0 GiB memory\n' > "$st/machine.driver"
  printf 'hosts|pass|ok\ncopy|pass|ok\ninstall|pass|ok\nsign-in|pass|ok\nsecrets|pass|ok\n' > "$st/results"
  sec=$st/section.md
  section_build "$sec"
  out=$(cat "$sec")
  eq "the section opens with its title" "$(head -n 1 "$sec")" "## Clean-machine rehearsal"
  has "a dry run reads Result: dry run" "$out" "Result: dry run"
  has "and Mode: dry run" "$out" "Mode: dry run"
  has "the candidate is a stand-in of the ref's commit with the bundle added" "$out" "Candidate: 1.0.0 rc1, branch rehearsal/stand-in at 1111111111111111111111111111111111111111, a stand-in of 2222222222222222222222222222222222222222 with the built web bundle added"
  has "the dry-run note is there" "$out" "Note: A dry run on throwaway stand-ins"
  has "it says it is not a rehearsal pass" "$out" "It is not a rehearsal pass"
  has "the timed runs are not run" "$out" "| demo path runs | not run | no timed run yet; the runs phase follows a passed install |"
  has "the Specs line is the base commit's" "$out" "Specs: the REL-2 specs (web/e2e/demo-path) at 2222222222222222222222222222222222222222"
  env_set "$st/options" mode real
  env_set "$st/options" branch release/1.0.0-rc1
  section_build "$sec"
  out=$(cat "$sec")
  has "a real run with the timed runs missing reads not run" "$out" "Result: not run"
  has "and Mode: rehearsal" "$out" "Mode: rehearsal"
  lacks "and holds no dry-run note" "$out" "Note:"
  rm -rf "$st"
  [ "$bad" -eq 0 ]
}
# The break: the dry run reads as a rehearsal.
b_dry_section() {
  opt() { if [ "$1" = mode ]; then echo real; else env_get "$state/options" "$1"; fi; }
}

# --- the copied script, run for real on stub hosts ---

mksyn() { # mksyn <dir>: a synthetic repository with a copy of the release files, a version and a placeholder web bundle, on release/1.0.0-rc1
  rm -rf "$1"
  mkdir -p "$1/release" "$1/docker/tests" "$1/src/ocutalon/csp" "$1/web/scripts"
  git init -q "$1"
  git -C "$1" symbolic-ref HEAD refs/heads/release/1.0.0-rc1
  cp "$root/release/rehearse.sh" "$root/release/lib-release.sh" "$1/release/"
  cp "$root/docker/tests/lib-keys.sh" "$1/docker/tests/"
  cp "$root/web/scripts/demo-path-summary.mjs" "$1/web/scripts/"
  printf '<Export><Document><Version>1.0.0</Version></Document></Export>\n' > "$1/src/module.xml"
  printf '<html><app-root></app-root></html>\n' > "$1/src/ocutalon/csp/index.html"
  printf '#!/bin/sh\necho install\n' > "$1/install.sh"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "first"
  git -C "$1" checkout -q -b release/1.0.0-rc2
  git -C "$1" rm -q -r src/ocutalon/csp
  git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "no bundle"
  git -C "$1" checkout -q release/1.0.0-rc1
}

# run_reh <tag> <args...>: the synthetic script with the test's stub hosts; its output, then "status <n>".
run_reh() {
  local tag=$1
  shift
  (
    cd "${REH_FROM:-$syn}" || exit 1
    export TMPDIR=$tmp/runs OCUTALON_RELEASE_CONFIG=$cfgdir/release.conf OCUTALON_REHEARSAL_SSH=$stubdir/ssh
    export STUB_LOG=$stublog STUB_REMOTE=$tmp/remote STUB_DRIVER_PROBE=$stubdir/driver.probe STUB_CURL_CFG=$tmp/curl.cfg
    export STUB_CLEAN_PROBE=${STUB_CLEAN_PROBE:-$stubdir/clean.probe} STUB_INSTALL_OUT=${STUB_INSTALL_OUT:-$stubdir/install.out}
    export PATH=$bindir:$PATH STUB_NPM_LOG=$tmp/npm.log STUB_NPM_ENV=$tmp/npm.env STUB_COLLECTOR_IN=$tmp/collector.in
    export STUB_NPM_REPORT=${STUB_NPM_REPORT:-$bindir/report.pass.json} STUB_NPM_MARKS=${STUB_NPM_MARKS:-$bindir/marks.page}
    export STUB_COLLECTOR_OUT=${STUB_COLLECTOR_OUT:-$bindir/collector.out}
    if [ -n "$tag" ]; then export OCUTALON_RUN_TAG=$tag; else unset OCUTALON_RUN_TAG; fi
    bash "$syn/release/rehearse.sh" "$@" < "${REH_STDIN:-/dev/null}" 2>&1
    echo "status $?"
  )
}

stub_setup() {
  syn=$tmp/syn
  cfgdir=$tmp/stubcfg
  stubdir=$tmp/stubs
  bindir=$tmp/stubbin
  stublog=$tmp/stub-calls.log
  mksyn "$syn"
  mkconf_local "$cfgdir"
  mkstub "$stubdir"
  mkbin "$bindir"
  : > "$tmp/npm.log"
  rm -rf "$tmp/runs"
  mkdir -p "$tmp/runs"
  : > "$stublog"
  rm -rf "$tmp/remote"
  mkdir -p "$tmp/remote"
}

t_stub_runs() {
  local bad=0 out rec sha argv state
  stub_setup
  sha=$(git -C "$syn" rev-parse release/1.0.0-rc1)

  # hosts: an OcuTalon volume on the clean host.
  sed 's/^volumes=0/volumes=1/' "$stubdir/clean.probe" > "$stubdir/clean.volume"
  rec=$tmp/rec-hosts.md
  out=$(STUB_CLEAN_PROBE=$stubdir/clean.volume run_reh rh-hosts run --version 1.0.0 --rc 1 --record "$rec")
  has "a volume on the clean host fails the hosts step" "$out" "FAIL run install step hosts bound -: an OcuTalon container or volume exists"
  has "the later steps are not run" "$out" "NOT RUN copy"
  has "the run exits 1" "$out" "status 1"
  has "the result is fail" "$out" "RESULT fail"
  has "the record says fail" "$(cat "$rec")" "Result: fail"
  has "the copy row is not run" "$(cat "$rec")" "| copy | not run |"
  has "the install row is not run" "$(cat "$rec")" "| install | not run |"
  has "the sign-in row is not run" "$(cat "$rec")" "| sign-in | not run |"
  has "the demo path row is not run" "$(cat "$rec")" "| demo path runs | not run |"
  has "the hosts row fails" "$(cat "$rec")" "| hosts | fail |"
  has "the secrets step still runs after a failed step" "$out" "PASS secrets"
  has "and its row passes" "$(cat "$rec")" "| secrets | pass |"
  has "the machine lines still give only system, CPU and memory" "$(cat "$rec")" "Clean host: Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory; Node.js absent"
  lacks "the record names no stub host" "$(cat "$rec")" "stub-host-secret"
  eq "nothing changed on the hosts" "$(ls "$tmp/remote" | wc -l | tr -d ' ')" 0
  eq "the state is gone after run" "$([ -d "$tmp/runs/ocutalon-rehearsal-rh-hosts" ] && echo there || echo gone)" gone

  # copy: the clone is at another commit.
  rec=$tmp/rec-copy.md
  out=$(STUB_CLONE_SHA=0123456789abcdef0123456789abcdef01234567 run_reh rh-copy run --version 1.0.0 --rc 1 --record "$rec")
  has "a clone HEAD mismatch fails the copy step" "$out" "FAIL run install step copy bound -: the clone is at 0123456789ab and the candidate is ${sha:0:12}"
  has "the install step is not run after it" "$out" "NOT RUN install"
  has "the copy exits 1" "$out" "status 1"
  has "the copy row fails in the record" "$(cat "$rec")" "| copy | fail |"

  # install: install.sh exits 1.
  rec=$tmp/rec-install.md
  printf 'OcuTalon install\nline 2\nline 3\nline 4\nline 5\nline 6\nThe stack did not become healthy.\n' > "$stubdir/install.bad"
  out=$(STUB_INSTALL_OUT=$stubdir/install.bad STUB_INSTALL_RC=1 OCUTALON_INSTALL_WAIT=120 run_reh rh-inst run --version 1.0.0 --rc 1 --record "$rec")
  has "a failed install.sh fails the install step with its bound" "$out" "FAIL run install step install bound ready within 120 s: install.sh exited 1 after"
  has "the last lines of install.sh are indented" "$out" "  The stack did not become healthy."
  lacks "only the last five lines are shown" "$out" "  OcuTalon install"
  has "the sign-in is not run" "$out" "NOT RUN sign-in"
  has "the install row fails in the record" "$(cat "$rec")" "| install | fail |"
  has "the install exits 1" "$out" "status 1"
  has "the caller's OCUTALON_INSTALL_WAIT reaches the remote install.sh" "$(cat "$stublog")" "ARG cd ocutalon-rehearsal/candidate && env OCUTALON_INSTALL_WAIT=120 bash install.sh 2>&1"

  # sign-in: the page after the sign-in holds no <app-root.
  rec=$tmp/rec-signin.md
  out=$(STUB_DRIVER_PAGE='<html>Sign in</html>' run_reh rh-sign run --version 1.0.0 --rc 1 --record "$rec")
  has "a page with no <app-root fails the sign-in step" "$out" "FAIL run install step sign-in bound -: the driver host's page after sign-in holds no <app-root"
  has "the sign-in exits 1" "$out" "status 1"
  has "the result is fail for a failed sign-in" "$out" "RESULT fail"
  has "the sign-in row fails in the record" "$(cat "$rec")" "| sign-in | fail |"
  has "the install row passed before it" "$(cat "$rec")" "| install | pass |"

  # a value in install.sh's last lines fails secrets, and the record holds no row text then.
  rec=$tmp/rec-leak.md
  printf 'OcuTalon install\nThe stack did not start with planted-env-value-123456 in it.\n' > "$stubdir/install.leak"
  out=$(STUB_INSTALL_OUT=$stubdir/install.leak STUB_INSTALL_RC=1 run_reh rh-leak run --version 1.0.0 --rc 1 --record "$rec")
  has "a value in install.sh's tail fails secrets" "$out" "FAIL run install step secrets bound -: ANTHROPIC_API_KEY in"
  lacks "the value is not in the output of the report" "$(printf '%s\n' "$out" | sed -n '/^RECORD/,$p')" "planted-env-value"
  lacks "the record does not hold the value" "$(cat "$rec")" "planted-env-value"
  has "the record withholds the row text" "$(cat "$rec")" "withheld: the secrets step found a value in this run"
  has "the secrets row fails" "$(cat "$rec")" "| secrets | fail |"

  # a value only in install.sh's full output (not in the log or the tail) fails secrets too.
  rec=$tmp/rec-leak2.md
  { echo "debug planted-env-value-123456"; cat "$stubdir/install.out"; } > "$stubdir/install.leak2"
  out=$(STUB_INSTALL_OUT=$stubdir/install.leak2 run_reh rh-leak2 run --version 1.0.0 --rc 1 --record "$rec")
  has "a value in install.sh's full output fails secrets" "$out" "FAIL run install step secrets bound -: ANTHROPIC_API_KEY in 1 line(s)"
  has "and the result is fail" "$out" "RESULT fail"
  lacks "and the record does not hold the value" "$(cat "$rec")" "planted-env-value"

  # a relative --record under run lands in the caller's folder, not in the repository.
  mkdir -p "$tmp/callerdir"
  out=$(REH_FROM=$tmp/callerdir run_reh rh-rel run --version 1.0.0 --rc 1 --record rel-record.md)
  has "run with a relative record finishes" "$out" "RESULT not run"
  eq "the record is in the caller's folder" "$([ -f "$tmp/callerdir/rel-record.md" ] && echo there || echo missing)" there
  eq "and not in the repository" "$([ -e "$syn/rel-record.md" ] && echo there || echo missing)" missing

  # every step passes; install, report (twice) and down as separate processes.
  rec=$tmp/rec-pass.md
  printf '# OcuTalon 1.0.0 rc1\n\n## Upgrade harness\n\nResult: pass\n| kept | text |\n' > "$rec"
  before=$(cat "$rec" | cksum)
  : > "$stublog"
  out=$(STUB_SLEEP=1 run_reh rh-pass install --version 1.0.0 --rc 1 --record "$rec")
  has "install passes" "$out" "PHASE install done"
  has "the hosts step passes" "$out" "PASS hosts both hosts answered"
  has "the copy step passes" "$out" "PASS copy git bundle of"
  has "the install step passes" "$out" "PASS install install.sh reached ready; first start"
  has "the sign-in step passes" "$out" "PASS sign-in the driver host signed in at the printed address"
  lacks "no failed line" "$out" "FAIL"
  has "the install phase exits 0" "$out" "status 0"
  state=$tmp/runs/ocutalon-rehearsal-rh-pass
  eq "the clone is at the candidate commit" "$(git -C "$tmp/remote/ocutalon-rehearsal/candidate" rev-parse HEAD)" "$sha"
  eq "the env file became the clone's .env, byte for byte" "$(cmp "$cfgdir/env" "$tmp/remote/ocutalon-rehearsal/candidate/.env" && echo same)" same
  eq "the .env is mode 600" "$(ls -l "$tmp/remote/ocutalon-rehearsal/candidate/.env" | cut -c1-10)" "-rw-------"
  eq "the state is private" "$(ls -ld "$state" | cut -c1-10)" "drwx------"
  argv=$(cat "$stublog")
  lacks "no env value in any argument of any call" "$argv" "planted-env-value-123456"
  eq "every call checks host keys strictly" "$(grep -c '^ARG StrictHostKeyChecking=yes$' "$stublog")" 5
  lacks "no host key check is switched off" "$argv" "StrictHostKeyChecking=no"
  lacks "no OCUTALON_INSTALL_WAIT is passed when the caller set none" "$argv" "OCUTALON_INSTALL_WAIT"
  eq "the ssh calls are the probe, the copy, the clone, the env and install.sh (the driver is this machine)" "$(grep -c '^CALL ' "$stublog")" 5
  has "the bundle reached the host through stdin" "$argv" "stdin=$(wc -c < "$state/candidate.bundle" | tr -d ' ')"
  has "the sign-in config went by stdin to the driver" "$(cat "$tmp/curl.cfg")" 'data-urlencode = "IRISPassword=ocu-pass-1"'
  has "it signs in as the printed user" "$(cat "$tmp/curl.cfg")" 'data-urlencode = "IRISUsername=ocu-user"'
  has "the printed address is mapped to the clean host's web address" "$(cat "$tmp/curl.cfg")" 'url = "http://clean-web-9.invalid:52801/ocutalon/"'

  out=$(run_reh rh-pass report)
  has "report prints the record" "$out" "RECORD $rec"
  has "a real run with every step passed is not run" "$out" "RESULT not run"
  has "report exits 1 for not run" "$out" "status 1"
  has "the secrets step passes" "$out" "PASS secrets"
  eq "the first section is kept byte for byte" "$(sed -n '/^## Upgrade harness$/,/^| kept | text |$/p' "$rec" | cksum)" "$(printf '## Upgrade harness\n\nResult: pass\n| kept | text |\n' | cksum)"
  eq "the heading is kept" "$(head -n 1 "$rec")" "# OcuTalon 1.0.0 rc1"
  has "the record reads Result: not run" "$(cat "$rec")" "Result: not run"
  has "the record reads Mode: rehearsal" "$(cat "$rec")" "Mode: rehearsal"
  has "the candidate line" "$(cat "$rec")" "Candidate: 1.0.0 rc1, branch release/1.0.0-rc1 at $sha"
  has "the clean host line" "$(cat "$rec")" "Clean host: Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory; Node.js absent"
  matches "the driver host line gives system, CPU and memory (this machine)" "$(grep '^Driver host: ' "$rec")" '^Driver host: .+, .+, ([0-9.]+ GiB|unknown) memory$'
  lacks "and no host name of this machine" "$(cat "$rec")" "$(uname -n)"
  lacks "no dry-run note in a real record" "$(cat "$rec")" "Note:"
  matches "the install row gives the first start, install included" "$(cat "$rec")" 'first start [1-9][0-9]* s, install included'
  has "install.sh's ready text is kept beside it" "$(cat "$rec")" 'OcuTalon is ready after 1 min 5 s.'
  has "the secrets row passes" "$(cat "$rec")" "| secrets | pass |"
  has "the timed runs are not run" "$(cat "$rec")" "| demo path runs | not run | no timed run yet; the runs phase follows a passed install |"
  has "the Specs line follows the candidate line" "$(cat "$rec")" "Specs: the REL-2 specs (web/e2e/demo-path) at $sha"
  lacks "the record holds no stub host" "$(cat "$rec")" "stub-host-secret"
  lacks "the record holds no driver stub host" "$(cat "$rec")" "driver-secret"
  lacks "the record holds no configured host" "$(cat "$rec")" "clean-host-7"
  lacks "the record holds no configured address" "$(cat "$rec")" "clean-web-9"
  lacks "the record holds no env value" "$(cat "$rec")" "planted-env-value"
  lacks "the output log holds no configured host" "$(cat "$state/output.log")" "clean-host-7"
  lacks "the output log holds no env value" "$(cat "$state/output.log")" "planted-env-value"
  eq "no local absolute path in the record" "$(grep -c "$tmp" "$rec")" 0

  out=$(run_reh rh-pass report)
  eq "a second report keeps one section" "$(grep -c '^## Clean-machine rehearsal$' "$rec")" 1
  eq "and the other section too" "$(grep -c '^## Upgrade harness$' "$rec")" 1
  has "a second report exits 1 again" "$out" "status 1"

  # a planted value in the output fails the secrets step and names the variable.
  printf 'leak: planted-env-value-123456\n' >> "$state/output.log"
  out=$(run_reh rh-pass report)
  has "a planted env value fails secrets" "$out" "FAIL run install step secrets bound -: ANTHROPIC_API_KEY in 1 line(s)"
  lacks "the value is not printed" "$out" "planted-env-value"
  has "the report exits 1" "$out" "status 1"
  has "the result is fail" "$out" "RESULT fail"
  has "the secrets row fails" "$(cat "$rec")" "| secrets | fail | ANTHROPIC_API_KEY in 1 line(s) |"
  lacks "the record does not hold the value" "$(cat "$rec")" "planted-env-value"
  : > "$state/output.log"
  printf 'leak: clean-web-9.invalid\n' >> "$state/output.log"
  out=$(run_reh rh-pass report)
  has "a planted configuration value fails secrets and names the key" "$out" "REHEARSAL_CLEAN_WEB in 1 line(s)"
  lacks "the configuration value is not printed" "$out" "clean-web-9"
  # the configuration's values as the script uses them: a quoted value with spaces around =, and the host of a user@host.
  sed 's/^REHEARSAL_CLEAN_WEB=.*/  REHEARSAL_CLEAN_WEB = "quoted-web-5.invalid"/' "$cfgdir/release.conf" > "$cfgdir/release.conf.new"
  mv "$cfgdir/release.conf.new" "$cfgdir/release.conf"
  : > "$state/output.log"
  printf 'leak: quoted-web-5.invalid\nssh: connect to host clean-host-7.invalid port 22\n' >> "$state/output.log"
  out=$(run_reh rh-pass report)
  has "a value of a spaced, quoted line fails secrets" "$out" "REHEARSAL_CLEAN_WEB in 1 line(s)"
  has "the host of a user@host destination fails secrets" "$out" "REHEARSAL_CLEAN_SSH_HOST in 1 line(s)"
  lacks "neither value is printed" "$out" "quoted-web-5"
  lacks "nor the host" "$out" "clean-host-7"
  mkconf_local "$cfgdir"
  : > "$state/output.log"
  printf 'token sk-ant-%s\n' "abcdefghijklmnop" >> "$state/output.log"
  out=$(run_reh rh-pass report)
  has "a key-like text fails secrets" "$out" "key-like text in 1 line(s)"
  lacks "the key-like text is not printed" "$out" "abcdefghijklmnop"

  out=$(run_reh rh-pass down)
  has "down says TEARDOWN" "$out" "TEARDOWN"
  has "down in real mode says the clean host keeps its install" "$out" "the clean host keeps its install"
  eq "down removes the state" "$([ -d "$state" ] && echo there || echo gone)" gone

  # run end to end for a pass of every step: the exit code of a real run that is not run.
  out=$(run_reh rh-run run --version 1.0.0 --rc 1 --record "$tmp/rec-run.md")
  has "run ends with RESULT not run" "$out" "RESULT not run"
  has "run exits 1 for not run" "$out" "status 1"
  has "run ends with the teardown" "$out" "TEARDOWN"
  [ "$bad" -eq 0 ]
}

t_phase_order() {
  local bad=0 out
  stub_setup
  out=$(run_reh "" install --version 1.0.0 --rc 1 --record "$tmp/o.md")
  has "no OCUTALON_RUN_TAG is refused" "$out" "REFUSED install: it needs OCUTALON_RUN_TAG"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-order report)
  has "report with no state is refused" "$out" "REFUSED report: the install phase of tag rh-order has not finished"
  has "with exit 2 too" "$out" "status 2"
  out=$(run_reh rh-order down)
  has "down may always run" "$out" "status 0"
  has "down with no state says so" "$out" "TEARDOWN nothing to remove"
  out=$(run_reh rh-ord2 install --version 1.0.0 --rc 1 --record "$tmp/o.md")
  has "the first install runs" "$out" "status 0"
  out=$(run_reh rh-ord2 install --version 1.0.0 --rc 1 --record "$tmp/o.md")
  has "install again on the same tag is refused" "$out" "REFUSED install: the tag rh-ord2 has a state already"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-ord2 report extra)
  has "report takes no option" "$out" "status 2"
  out=$(run_reh rh-ord2 down)
  has "down after the refusal still runs" "$out" "status 0"
  out=$(run_reh Bad_Tag install --version 1.0.0 --rc 1)
  has "a tag with a bad character is refused" "$out" "REFUSED OCUTALON_RUN_TAG"
  out=$(run_reh rh-ord3 bogus)
  has "an unknown command is a usage error" "$out" "status 2"
  [ "$bad" -eq 0 ]
}
t_candidate() {
  local bad=0 out
  stub_setup
  out=$(run_reh rh-c1 install --version 1.0.0 --rc 0 --record "$tmp/c.md")
  has "--rc 0 is refused" "$out" "REFUSED --rc must be a positive whole number"
  out=$(run_reh rh-c2 install --version 1.0.0 --rc x --record "$tmp/c.md")
  has "--rc x is refused" "$out" "REFUSED --rc must be a positive whole number"
  out=$(run_reh rh-c3 install --version 2.0.0 --rc 1 --candidate release/1.0.0-rc1 --record "$tmp/c.md")
  has "a version that is not the candidate's is refused" "$out" "REFUSED --version 2.0.0 is not the candidate's version (1.0.0 in src/module.xml)"
  out=$(run_reh rh-c4 install --version 1.0.0 --rc 7 --record "$tmp/c.md")
  has "an unknown ref is refused" "$out" "REFUSED the candidate 'release/1.0.0-rc7' is not a commit"
  out=$(run_reh rh-c5 install --version 1.0.0 --rc 2 --record "$tmp/c.md")
  has "a candidate with no web bundle is refused" "$out" "holds no src/ocutalon/csp/index.html; Story 11.5 commits the web bundle on the candidate branch"
  out=$(run_reh rh-c6 install --rc 1 --record "$tmp/c.md")
  has "a real run with no version and no candidate is refused" "$out" "REFUSED --version <v> is required"
  out=$(run_reh rh-c7 install --version 1.0.0 --rc 1 --candidate "$(git -C "$syn" rev-parse HEAD)" --record "$tmp/c.md")
  has "a real candidate that is no branch is refused" "$out" "is not a local branch"
  out=$(run_reh rh-c8 install --version 1.0.0 --rc 1 --bogus)
  has "an unknown option is refused" "$out" "REFUSED unknown option '--bogus'"
  out=$(run_reh rh-c9 install --version 1.0.0 --rc 1 --record)
  has "an option with no value is refused" "$out" "REFUSED --record needs a value"
  eq "no state was started by any refusal" "$(ls "$tmp/runs" | wc -l | tr -d ' ')" 0
  mv "$cfgdir/release.conf" "$cfgdir/release.conf.off"
  out=$(run_reh rh-c10 install --version 1.0.0 --rc 1 --record "$tmp/c.md")
  has "a missing configuration is refused" "$out" "REFUSED config: the configuration file is missing"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-c11 plan --version 1.0.0 --rc 1 --record "$tmp/c.md")
  has "plan has the same refusal" "$out" "status 2"
  mv "$cfgdir/release.conf.off" "$cfgdir/release.conf"
  out=$(run_reh rh-c12 plan --version 1.0.0 --rc 1 --record "$tmp/c.md")
  has "plan on a good real candidate exits 0" "$out" "status 0"
  has "plan names the hosts as configured, the driver as local" "$out" "PLAN hosts clean configured, driver local"
  has "plan names the record" "$out" "PLAN record $tmp/c.md"
  lacks "plan prints no host value" "$out" "clean-host-7"
  eq "plan starts no state" "$(ls "$tmp/runs" | wc -l | tr -d ' ')" 0
  eq "plan calls no host" "$(wc -c < "$stublog" | tr -d ' ')" 0
  grep -v '^REHEARSAL_DRIVER_KEY=' "$cfgdir/release.conf" | sed 's/^REHEARSAL_DRIVER_SSH=.*/REHEARSAL_DRIVER_SSH=local/' > "$cfgdir/release.conf.new"
  mv "$cfgdir/release.conf.new" "$cfgdir/release.conf"
  out=$(run_reh rh-c13 plan --version 1.0.0 --rc 1 --record "$tmp/c.md")
  has "plan names a local driver" "$out" "PLAN hosts clean configured, driver local"
  has "a local driver needs no key" "$out" "status 0"
  mkconf "$cfgdir"
  out=$(run_reh rh-c14 install --version 1.0.0 --rc "$(printf '1\nx')" --record "$tmp/c.md")
  has "an --rc with a second line is refused" "$out" "REFUSED --rc must be a positive whole number"
  out=$(run_reh rh-c15 install --version 1.0.0 --rc 1234567 --record "$tmp/c.md")
  has "an --rc of seven digits is refused" "$out" "REFUSED --rc must be a positive whole number"
  eq "no state was started by these refusals" "$(ls "$tmp/runs" | wc -l | tr -d ' ')" 0
  [ "$bad" -eq 0 ]
}

# --- the bounds ---

mkruns() { # mkruns <state dir> <n> <dry|real>: a state with runs/1..n whose values are within every limit (notice 14.6 s), verdicts pass
  local d=$1 n=$2 k
  rm -rf "$d"
  mkdir -p "$d/runs"
  printf 'mode=%s\nruns=%s\n' "$3" "$n" > "$d/options"
  printf 'hosts|pass|ok\ncopy|pass|ok\ninstall|pass|ok\nsign-in|pass|ok\nsecrets|pass|ok\n' > "$d/results"
  for k in $(seq 1 "$n"); do
    mkdir -p "$d/runs/$k"
    printf 'step1_sent 1000\nstep1_decision_seen 3100\nstep1_reply_seen 3300\napprove_pressed 9000\napproval_result_seen 9600\n' > "$d/runs/$k/marks.page"
    printf 'mark press 100000\nmark first_failure 101000\nmark pickup 103900\nmark settle_end 113600\nmark diagnosis_end 114400\nmark delivered 114600\nreminder 150000 151000\nlate 0 1\nmark reminder_msg 200000\nmark result_msg 214000\ntokens 1520\n' > "$d/runs/$k/marks.server"
    printf 'pass\n' > "$d/runs/$k/verdict"
  done
}

setv() { # setv <state> <run> <page|server> <mark name or line key> <new line>: replaces the line that starts with the key
  local f=$1/runs/$2/marks.$3 key=$4
  grep -Ev "^(mark )?$key " "$f" > "$f.new"
  printf '%s\n' "$5" >> "$f.new"
  mv "$f.new" "$f"
}

# evaluates the state, merges the rows into its results; prints bounds_eval's FAIL lines
evalstate() { # evalstate <state> [<planted id>]
  state=$1
  bounds_eval "$1" "${2:-}"
  bounds_merge
}

t_bounds() {
  local bad=0 d=$tmp/bd out id
  # twenty runs within every limit, real: every limited row passes, the recorded rows record, only tell-now is not run.
  mkruns "$d" 20 real
  out=$(evalstate "$d")
  eq "twenty runs within every limit print no FAIL line" "$out" ""
  for id in notice pick-up settle-end diagnosis delivery decision approval-result reminder largest-request runs; do
    eq "real: $id passes" "$(row_result "$d/results" "$id")" pass
  done
  for id in median first-reply reminder-result; do eq "real: $id is recorded" "$(row_result "$d/results" "$id")" recorded; done
  eq "the only row that is not run is tell-now" "$(awk -F'|' '$2 == "not run" { print $1 }' "$d/results")" "tell-now"
  eq "so a real run is not run, never a pass" "$(rehearsal_result real "$d/results")" "not run"
  has "the runs row counts the runs" "$(grep '^runs|' "$d/results")" "runs|pass|20 of 20 runs passed the REL-2 specs"
  has "notice names its rule" "$(grep '^notice|' "$d/results")" "within 60 s in 20 of 20 runs (19 of 20 needed); longest 14.6 s (run 1)"
  has "pick-up names its longest" "$(grep '^pick-up|' "$d/results")" "within 15 s of the first failure in every run; longest 2.9 s (run 1)"
  has "the median is recorded against the typical 35 s" "$(grep '^median|' "$d/results")" "median notice 14.6 s against the typical 35 s"
  has "the reminder is signed" "$(grep '^reminder-result|' "$d/results")" "-14.0 s"
  has "the tell-now row names Story 11.12" "$(grep '^tell-now|' "$d/results")" "Story 11.12 adds one to each run"
  has "the runs table has its heading" "$(cat "$d/runs.table")" "### Runs"
  has "and a row for the run" "$(cat "$d/runs.table")" "| 1 | pass | 14.6 s | 2.9 s | 12.6 s | 0.8 s | 0.2 s | 2.1 s | 2.3 s | 0.6 s | 1.0 s | -14.0 s | 1,520 |"
  eq "the runs table has a row for each run" "$(grep -c '^| [0-9]* | pass |' "$d/runs.table")" 20

  # dry: the met rows read dry run, never pass.
  mkruns "$d" 1 dry
  out=$(evalstate "$d")
  for id in notice pick-up settle-end diagnosis delivery decision approval-result reminder largest-request; do
    eq "dry: $id reads dry run" "$(row_result "$d/results" "$id")" "dry run"
  done
  eq "dry: the runs row passes" "$(row_result "$d/results" runs)" pass
  eq "dry: the result is a dry run" "$(rehearsal_result dry "$d/results")" "dry run"

  # pick-up 16.0 s in run 7 only
  mkruns "$d" 20 real
  setv "$d" 7 server pickup "mark pickup 117000"
  out=$(evalstate "$d")
  has "run 7's pick-up misses" "$out" "FAIL run 7 step incident bound pick-up 15 s: 16.0 s in run 7 from the first failure to the pick-up"
  eq "the pick-up row fails" "$(row_result "$d/results" pick-up)" fail
  eq "and the result fails" "$(rehearsal_result real "$d/results")" fail
  lacks "no other bound misses" "$(printf '%s\n' "$out" | grep -v 'bound pick-up')" "FAIL"

  # notice over 60 s in one run of 20 passes, in two it fails and names both
  mkruns "$d" 20 real
  setv "$d" 5 server press "mark press 40000"
  out=$(evalstate "$d")
  lacks "one run over 60 s of 20 is within the allowance" "$out" "bound notice"
  eq "the notice row passes" "$(row_result "$d/results" notice)" pass
  has "and says so" "$(grep '^notice|' "$d/results")" "1 run(s) over, within the allowance"
  mkruns "$d" 20 real
  setv "$d" 3 server press "mark press 40000"
  setv "$d" 9 server press "mark press 40000"
  out=$(evalstate "$d")
  has "two runs over 60 s fail and are listed" "$out" "FAIL run 3,9 step incident bound notice 60 s in 19 of 20: 74.6 s in run 3, 74.6 s in run 9 from Break the feed to the notice on the phone"
  eq "the notice row fails" "$(row_result "$d/results" notice)" fail
  mkruns "$d" 1 real
  setv "$d" 1 server press "mark press 40000"
  out=$(evalstate "$d")
  has "with one run, 19 of 20 allows no miss" "$out" "FAIL run 1 step incident bound notice 60 s in 19 of 20:"

  # decision 10.1 s in two runs, approval result 2.1 s in two runs
  mkruns "$d" 20 real
  setv "$d" 2 page step1_decision_seen "step1_decision_seen 11100"
  setv "$d" 4 page step1_decision_seen "step1_decision_seen 11100"
  out=$(evalstate "$d")
  has "decision 10.1 s in two runs fails" "$out" "FAIL run 2,4 step watch bound decision 10 s in 19 of 20: 10.1 s in run 2, 10.1 s in run 4"
  mkruns "$d" 20 real
  setv "$d" 6 page approval_result_seen "approval_result_seen 11100"
  setv "$d" 8 page approval_result_seen "approval_result_seen 11100"
  out=$(evalstate "$d")
  has "approval result 2.1 s in two runs fails" "$out" "FAIL run 6,8 step approval bound approval-result 2 s in 19 of 20: 2.1 s in run 6, 2.1 s in run 8"
  mkruns "$d" 20 real
  setv "$d" 6 page approval_result_seen "approval_result_seen 11100"
  out=$(evalstate "$d")
  eq "approval result 2.1 s in one run of 20 passes" "$(row_result "$d/results" approval-result)" pass

  # one reminder 11 s late; 10.0 s is within
  mkruns "$d" 20 real
  setv "$d" 11 server reminder "reminder 150000 161000"
  out=$(evalstate "$d")
  has "a reminder 11 s late fails" "$out" "FAIL run 11 step reminder bound reminder 10 s: 11.0 s in run 11 after its due time"
  mkruns "$d" 20 real
  setv "$d" 11 server reminder "reminder 150000 160000"
  out=$(evalstate "$d")
  eq "a reminder 10.0 s late is within" "$(row_result "$d/results" reminder)" pass
  setv "$d" 11 server late "late 1 1"
  out=$(evalstate "$d")
  has "a reminder the product marked late fails" "$out" "FAIL run 11 step reminder bound reminder 10 s:"

  # the largest request: 100000 fails, 99999 passes
  mkruns "$d" 20 real
  setv "$d" 12 server tokens "tokens 100000"
  out=$(evalstate "$d")
  has "100000 tokens fail" "$out" "FAIL run 12 step run bound largest-request 100000 tokens: 100,000 in run 12 input tokens in the largest request"
  setv "$d" 12 server tokens "tokens 99999"
  out=$(evalstate "$d")
  eq "99999 tokens pass" "$(row_result "$d/results" largest-request)" pass
  eq "with no FAIL line" "$out" ""

  # a missing delivered mark, a missing page mark, a collector that gave nothing
  mkruns "$d" 20 real
  grep -v '^mark delivered ' "$d/runs/4/marks.server" > "$d/x" && mv "$d/x" "$d/runs/4/marks.server"
  out=$(evalstate "$d")
  has "a missing delivered mark fails the run's step" "$out" "FAIL run 4 step incident bound -: missing mark(s) delivered"
  eq "the notice row fails" "$(row_result "$d/results" notice)" fail
  eq "the delivery row fails" "$(row_result "$d/results" delivery)" fail
  eq "the runs row fails" "$(row_result "$d/results" runs)" fail
  eq "the result fails" "$(rehearsal_result real "$d/results")" fail
  has "the table marks the run as failed" "$(cat "$d/runs.table")" "| 4 | fail |"
  mkruns "$d" 3 real
  grep -v '^approve_pressed ' "$d/runs/2/marks.page" > "$d/x" && mv "$d/x" "$d/runs/2/marks.page"
  out=$(evalstate "$d")
  has "a missing page mark names the page" "$out" "FAIL run 2 step approval bound -: missing mark(s) approve_pressed (left by the page)"
  mkruns "$d" 2 real
  : > "$d/runs/2/marks.server"
  out=$(evalstate "$d")
  has "no server mark fails the incident step" "$out" "FAIL run 2 step incident bound -: missing mark(s) press,first_failure,pickup,settle_end,diagnosis_end,delivered"
  has "and the reminder step" "$out" "FAIL run 2 step reminder bound -: missing mark(s) reminder,reminder_msg,result_msg"
  has "and the run step" "$out" "FAIL run 2 step run bound -: missing mark(s) tokens"
  mkruns "$d" 1 real
  printf 'missing session\n' >> "$d/runs/1/marks.server"
  out=$(evalstate "$d")
  has "a session that was not found is named" "$out" "FAIL run 1 step run bound -: missing mark(s) session"

  # a failed verdict is the run's FAIL; no verdict file is a failure too
  mkruns "$d" 20 real
  printf 'fail\napproval|05-approval.spec.ts "x": failed\n' > "$d/runs/5/verdict"
  out=$(evalstate "$d")
  has "a failed verdict is printed as the run's FAIL" "$out" "FAIL run 5 step approval bound -: 05-approval.spec.ts \"x\": failed"
  has "the runs row counts the failed run" "$(grep '^runs|' "$d/results")" "runs|fail|1 of 20 runs failed"
  rm -f "$d/runs/6/verdict"
  out=$(evalstate "$d")
  has "a run with no verdict fails" "$out" "FAIL run 6 step run bound -: the run left no verdict"

  # fewer runs than --runs: the runs row is not run
  mkruns "$d" 3 real
  printf 'mode=real\nruns=20\n' > "$d/options"
  out=$(evalstate "$d")
  eq "three runs of twenty: the runs row is not run" "$(row_result "$d/results" runs)" "not run"
  eq "so a real result is not run" "$(rehearsal_result real "$d/results")" "not run"

  # no run: no Runs table, and every bound row not run
  mkruns "$d" 1 real
  rm -rf "$d/runs/1"
  out=$(evalstate "$d")
  eq "a state with no run has an empty Runs table" "$(wc -c < "$d/runs.table" | tr -d ' ')" 0
  eq "and its notice row is not run" "$(row_result "$d/results" notice)" "not run"

  # the median, for odd and even N
  mkruns "$d" 3 real
  setv "$d" 1 server delivered "mark delivered 110000"
  setv "$d" 2 server delivered "mark delivered 130000"
  setv "$d" 3 server delivered "mark delivered 120000"
  out=$(evalstate "$d")
  has "the median of 10, 30 and 20 s is 20.0 s" "$(grep '^median|' "$d/results")" "median notice 20.0 s"
  mkruns "$d" 4 real
  setv "$d" 1 server delivered "mark delivered 110000"
  setv "$d" 2 server delivered "mark delivered 120000"
  setv "$d" 3 server delivered "mark delivered 130000"
  setv "$d" 4 server delivered "mark delivered 140000"
  out=$(evalstate "$d")
  has "the median of 10, 20, 30 and 40 s is 25.0 s" "$(grep '^median|' "$d/results")" "median notice 25.0 s"

  # planted: the one bound's limit is 0, on a dry state
  mkruns "$d" 1 dry
  out=$(evalstate "$d" pick-up)
  has "the planted pick-up misses with its text" "$out" "FAIL run 1 step incident bound pick-up 0 s (planted): 2.9 s in run 1 from the first failure to the pick-up"
  has "the row says planted" "$(grep '^pick-up|' "$d/results")" "(planted)"
  eq "the planted pick-up row fails" "$(row_result "$d/results" pick-up)" fail
  eq "the other rows are untouched" "$(row_result "$d/results" notice)" "dry run"
  eq "the planted result fails" "$(rehearsal_result dry "$d/results")" fail
  eq "which exits 1" "$(rehearsal_exit "$(rehearsal_result dry "$d/results")")" 1
  out=$(evalstate "$d" largest-request)
  has "a planted largest request is 0 tokens" "$out" "bound largest-request 0 tokens (planted):"
  out=$(evalstate "$d")
  eq "a report with no plant reads the same state as a dry run again" "$(rehearsal_result dry "$d/results")" "dry run"

  # the RUN line of one run (the runs phase)
  mkruns "$d" 1 dry
  out=$(runs_feed "$d" 1 | awk -v mode=run "$BOUNDS_AWK")
  eq "the RUN line gives every value in seconds" "$out" "RUN 1 notice=14.6 pick-up=2.9 settle-end=12.6 diagnosis=0.8 delivery=0.2 decision=2.1 approval-result=0.6 reminder=1.0 largest-request=1520 first-reply=2.3 reminder-result=-14.0"
  grep -v '^mark delivered ' "$d/runs/1/marks.server" > "$d/x" && mv "$d/x" "$d/runs/1/marks.server"
  out=$(runs_feed "$d" 1 | awk -v mode=run "$BOUNDS_AWK")
  has "a missing mark is a dash in the RUN line" "$out" "notice=- pick-up=2.9 settle-end=12.6 diagnosis=0.8 delivery=-"
  has "and a FAIL line" "$out" "FAIL run 1 step incident bound -: missing mark(s) delivered"
  runs_feed "$d" 1 | awk -v mode=run "$BOUNDS_AWK" > /dev/null
  eq "which exits 1" "${PIPESTATUS[1]}" 1
  rm -rf "$d"
  [ "$bad" -eq 0 ]
}
# The break: the pick-up limit is ten times too wide, so no run can miss it.
b_bounds() {
  BOUNDS_AWK=$(printf '%s' "$BOUNDS_AWK" | sed 's/lim\["pick-up"\] = 15000/lim["pick-up"] = 150000/')
}

# --- the timed run and the exec channel, on stub hosts and a stub npm ---

t_timed_runs() {
  local bad=0 out st rec sha d envf
  stub_setup
  sha=$(git -C "$syn" rev-parse release/1.0.0-rc1)
  printf 'Write !,"CHK|x|1"\nHalt\n' > "$tmp/exec.in"

  # order: runs and exec with no state are refused, and so after a failed install.
  out=$(run_reh rh-tm0 runs)
  has "runs with no state is refused" "$out" "REFUSED runs: the install phase of tag rh-tm0 has not finished"
  has "with exit 2" "$out" "status 2"
  out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm0 exec)
  has "exec with no state is refused" "$out" "REFUSED exec: the install phase of tag rh-tm0 has not finished"
  has "with exit 2 too" "$out" "status 2"
  sed 's/^volumes=0/volumes=1/' "$stubdir/clean.probe" > "$stubdir/clean.volume"
  out=$(STUB_CLEAN_PROBE=$stubdir/clean.volume run_reh rh-tm1 install --version 1.0.0 --rc 1 --record "$tmp/rec-tm1.md")
  has "the install fails on a leftover volume" "$out" "status 1"
  out=$(run_reh rh-tm1 runs)
  has "runs after a failed install is refused" "$out" "REFUSED runs: the install step hosts did not pass"
  has "with exit 2 as well" "$out" "status 2"
  out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm1 exec)
  has "exec after a failed install is refused" "$out" "REFUSED exec: the install step hosts did not pass"
  run_reh rh-tm1 down > /dev/null

  # a passed install, the exec channel, then run 1.
  rec=$tmp/rec-timed.md
  out=$(run_reh rh-tm install --version 1.0.0 --rc 1 --record "$rec")
  has "the install passes" "$out" "status 0"
  st=$tmp/runs/ocutalon-rehearsal-rh-tm
  eq "the origin of the clean host is kept for the runs" "$(cat "$st/origin")" "http://clean-web-9.invalid:52801"
  eq "and the printed user" "$(cat "$st/user")" "ocu-user"

  : > "$stublog"
  out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm exec)
  has "exec prints the session's CHK line" "$out" "CHK|x|1"
  has "exec exits 0" "$out" "status 0"
  has "exec goes through the compose exec of the install" "$(cat "$stublog")" "ARG cd ocutalon-rehearsal/candidate && docker compose exec -T iris iris session IRIS -U OCUTALON"
  has "with the script as stdin" "$(cat "$stublog")" "stdin=$(wc -c < "$tmp/exec.in" | tr -d ' ')"
  eq "exec counts nothing without a run number" "$([ -e "$st/runs" ] && echo there || echo none)" none
  eq "exec writes nothing to the output log" "$(grep -c 'CHK|x' "$st/output.log")" 0
  out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm exec USER2)
  has "a namespace is passed to -U" "$(cat "$stublog")" "iris session IRIS -U USER2"
  for d in bad_ns lower 2NS "A B" "" "$(printf 'OCUTALON\nreboot')"; do
    out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm exec "$d")
    has "the namespace '$d' is refused" "$out" "status 2"
  done
  out=$(REH_STDIN=$tmp/exec.in run_reh rh-tm exec A B)
  has "two arguments are refused" "$out" "status 2"
  lacks "no env value in any argv of exec" "$(cat "$stublog")" "planted-env-value-123456"
  out=$(OCUTALON_REHEARSAL_RUN=3 REH_STDIN=$tmp/exec.in run_reh rh-tm exec)
  eq "exec counts its call for the run in the environment" "$(cat "$st/runs/3/exec.count")" 1
  out=$(OCUTALON_REHEARSAL_RUN=3 REH_STDIN=$tmp/exec.in run_reh rh-tm exec)
  eq "and again" "$(cat "$st/runs/3/exec.count")" 2
  rm -rf "$st/runs"

  : > "$tmp/npm.log"
  out=$(run_reh rh-tm runs)
  has "run 1 passes with the summary's line" "$out" "PASS run 1 demo path: DEMO-PATH 8 of 8 steps ran (0 partly skipped), 0 skipped, 0 failed; floor 1 of 1 passed"
  has "and one RUN line" "$out" "RUN 1 notice=14.6 pick-up=2.9 settle-end=12.6 diagnosis=0.8 delivery=0.2 decision=2.1 approval-result=0.6 reminder=1.0 largest-request=1520 first-reply=2.3 reminder-result=-14.0"
  has "the phase exits 0" "$out" "status 0"
  lacks "no FAIL line" "$out" "FAIL"
  d=$st/runs/1
  for f in report.json e2e.log summary.log marks.page marks.server verdict exec.count server.start; do
    eq "run 1 keeps $f" "$([ -e "$d/$f" ] && echo there || echo missing)" there
  done
  eq "the specs read once through exec" "$(cat "$d/exec.count")" 1
  eq "the verdict is pass" "$(cat "$d/verdict")" pass
  eq "the server start is the stub's" "$(cat "$d/server.start")" "2026-11-01 10:00:00.000"
  has "the page marks are the stub's" "$(cat "$d/marks.page")" "approval_result_seen 9600"
  has "the server marks come from the collector" "$(cat "$d/marks.server")" "mark delivered 114600"
  has "the reminder line" "$(cat "$d/marks.server")" "reminder 150000 151000"
  has "the late line" "$(cat "$d/marks.server")" "late 0 1"
  has "the tokens line" "$(cat "$d/marks.server")" "tokens 1520"
  eq "npm is called for the demo-path project of web" "$(cat "$tmp/npm.log")" "--prefix web run e2e:demo-path"
  envf=$(cat "$tmp/npm.env")
  has "Playwright gets the install's origin" "$envf" "URL=http://clean-web-9.invalid:52801"
  has "the real model in real mode" "$envf" "MODEL=real"
  has "the default timeout" "$envf" "TIMEOUT=480000"
  has "the run number" "$envf" "RUN=1"
  has "the tag" "$envf" "TAG=rh-tm"
  has "no model key" "$envf" "KEY=unset"
  has "the exec channel is this script's exec" "$envf" "EXEC=bash '$(cd "$syn" && pwd)/release/rehearse.sh' exec"
  has "the marks file is the run's" "$envf" "MARKS=$d/marks.page"
  has "the collector gets the server start" "$(cat "$tmp/collector.in")" 'Set start="2026-11-01 10:00:00.000"'
  has "and the printed user" "$(cat "$tmp/collector.in")" '"ocu-user"'
  lacks "no placeholder is left" "$(cat "$tmp/collector.in")" "@"
  eq "run 1's output is in the output log" "$(grep -c 'PASS run 1 demo path' "$st/output.log")" 1
  has "the e2e output is in the output log" "$(cat "$st/output.log")" "stub npm: 1 test file ran"

  # a second runs call is refused and starts nothing
  : > "$tmp/npm.log"
  out=$(run_reh rh-tm runs)
  has "run 2 is refused naming Story 11.12" "$out" "REFUSED runs: run 1 exists; run 2 and later (Run again and the replay rule) come with Story 11.12"
  has "with exit 2" "$out" "status 2"
  eq "nothing started" "$(wc -c < "$tmp/npm.log" | tr -d ' ')" 0
  eq "no second run folder" "$([ -e "$st/runs/2" ] && echo there || echo none)" none

  # report: the section holds the rows and the table, replaces itself, and a real run with one of 20 runs is not run
  out=$(run_reh rh-tm report)
  has "report ends with RESULT not run" "$out" "RESULT not run"
  has "and exits 1" "$out" "status 1"
  lacks "no FAIL line for a clean run" "$out" "FAIL"
  has "the Specs line" "$(cat "$rec")" "Specs: the REL-2 specs (web/e2e/demo-path) at $sha"
  has "the runs row counts the runs" "$(cat "$rec")" "| demo path runs | not run | 1 of 20 runs done; run 2 and later come with Story 11.12 |"
  has "a met bound reads pass in real mode" "$(cat "$rec")" "| notice | pass | within 60 s in 1 of 1 runs (19 of 20 needed); longest 14.6 s (run 1) |"
  has "the tell-now row names Story 11.12" "$(cat "$rec")" "| tell-now | not run | the demo path has no tell-now item yet; Story 11.12 adds one to each run |"
  has "the Runs table is in the section" "$(cat "$rec")" "### Runs"
  has "with the run's row" "$(cat "$rec")" "| 1 | pass | 14.6 s | 2.9 s | 12.6 s | 0.8 s | 0.2 s | 2.1 s | 2.3 s | 0.6 s | 1.0 s | -14.0 s | 1,520 |"
  out=$(run_reh rh-tm report)
  eq "a second report keeps one section" "$(grep -c '^## Clean-machine rehearsal$' "$rec")" 1
  eq "and one Runs table" "$(grep -c '^### Runs$' "$rec")" 1
  eq "and one tell-now row" "$(grep -c '^| tell-now |' "$rec")" 1
  eq "install stays once in the output log" "$(grep -c '^PASS install ' "$st/output.log")" 1
  out=$(run_reh rh-tm report --plant pick-up)
  has "--plant in real mode is refused" "$out" "REFUSED report: --plant is for dry runs only"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-tm report --plant bogus)
  has "an unknown bound id is refused" "$out" "status 2"
  out=$(run_reh rh-tm report extra)
  has "report takes only --plant" "$out" "status 2"
  run_reh rh-tm down > /dev/null

  # a failing report: the failed step is named, the collector still ran, and report fails
  rec=$tmp/rec-timed-fail.md
  run_reh rh-tf install --version 1.0.0 --rc 1 --record "$rec" > /dev/null
  st=$tmp/runs/ocutalon-rehearsal-rh-tf
  out=$(STUB_NPM_REPORT=$bindir/report.fail.json run_reh rh-tf runs)
  has "a failed spec fails the run, naming its step" "$out" "FAIL run 1 step approval bound -: 05-approval.spec.ts \"approval works\": failed"
  lacks "there is no PASS line" "$out" "PASS run 1"
  has "the phase exits 1" "$out" "status 1"
  has "the collector still ran" "$(cat "$st/runs/1/marks.server")" "mark delivered 114600"
  has "and the RUN line is printed" "$out" "RUN 1 notice=14.6"
  eq "the verdict is fail" "$(sed -n 1p "$st/runs/1/verdict")" fail
  has "and names the step" "$(sed -n 2p "$st/runs/1/verdict")" "approval|05-approval.spec.ts"
  out=$(run_reh rh-tf report)
  has "report prints the failed run's FAIL again" "$out" "FAIL run 1 step approval bound -: 05-approval.spec.ts"
  has "the result is fail" "$out" "RESULT fail"
  has "report exits 1" "$out" "status 1"
  has "the runs row fails" "$(cat "$rec")" "| demo path runs | fail | 1 of 1 runs failed"
  run_reh rh-tf down > /dev/null

  # a run that reads nothing through exec
  rec=$tmp/rec-timed-noexec.md
  run_reh rh-tn install --version 1.0.0 --rc 1 --record "$rec" > /dev/null
  out=$(STUB_NPM_NOEXEC=1 run_reh rh-tn runs)
  has "a run that read nothing through exec fails" "$out" "FAIL run 1 step run bound -: the specs read nothing through the rehearsal's exec channel"
  lacks "and does not pass" "$out" "PASS run 1"
  has "with exit 1" "$out" "status 1"
  run_reh rh-tn down > /dev/null

  # a missing mark from the collector fails the run too
  rec=$tmp/rec-timed-mark.md
  run_reh rh-tk install --version 1.0.0 --rc 1 --record "$rec" > /dev/null
  grep -v 'delivered' "$bindir/collector.out" > "$bindir/collector.nodelivered"
  out=$(STUB_COLLECTOR_OUT=$bindir/collector.nodelivered run_reh rh-tk runs)
  has "a missing delivered mark fails the run" "$out" "FAIL run 1 step incident bound -: missing mark(s) delivered (read from the server's records)"
  lacks "and the run does not pass" "$out" "PASS run 1"
  has "the RUN line has a dash" "$out" "notice=-"
  run_reh rh-tk down > /dev/null

  # a collector that stops before its done line fails the run
  rec=$tmp/rec-timed-trunc.md
  run_reh rh-tt install --version 1.0.0 --rc 1 --record "$rec" > /dev/null
  grep -v 'CHK|done' "$bindir/collector.out" > "$bindir/collector.nodone"
  out=$(STUB_COLLECTOR_OUT=$bindir/collector.nodone run_reh rh-tt runs)
  has "a collector without its done line fails the run" "$out" "FAIL run 1 step run bound -: missing mark(s) collector"
  lacks "and the run does not pass" "$out" "PASS run 1"
  run_reh rh-tt down > /dev/null

  # the clean host's address never reaches a FAIL line, and a host name that sits in the replacement text still ends
  rec=$tmp/rec-timed-host.md
  run_reh rh-th install --version 1.0.0 --rc 1 --record "$rec" > /dev/null
  sed 's#approval works#approval works at http://clean-web-9.invalid:52801#' "$bindir/report.fail.json" > "$bindir/report.host.json"
  out=$(STUB_NPM_REPORT=$bindir/report.host.json run_reh rh-th runs)
  has "a failure reason is printed" "$out" "FAIL run 1 step approval bound -: 05-approval.spec.ts"
  lacks "without the clean host's address" "$out" "clean-web-9.invalid"
  lacks "in the verdict either" "$(cat "$tmp/runs/ocutalon-rehearsal-rh-th/runs/1/verdict")" "clean-web-9.invalid"
  run_reh rh-th down > /dev/null
  mkdir -p "$tmp/scrub"
  printf 'mode=real\n' > "$tmp/scrub/options"
  printf 'http://host:52801\n' > "$tmp/scrub/origin"
  out=$(state=$tmp/scrub; printf 'goto http://host:52801/x; the host is host\n' | scrub_origin)
  eq "a host name inside the replacement text is replaced once per occurrence" "$out" "goto http://<clean host>:52801/x; the <clean host> is <clean host>"

  # the whole run command: install, runs (the second refused), report, down
  out=$(run_reh rh-trun run --version 1.0.0 --rc 1 --record "$tmp/rec-trun.md")
  has "run does the timed run" "$out" "PASS run 1 demo path"
  has "then reports" "$out" "RESULT not run"
  has "then tears down" "$out" "TEARDOWN"
  has "and exits 1 for not run" "$out" "status 1"
  [ "$bad" -eq 0 ]
}

# The guards of a real rehearsal and the refusals of the new options.
t_guards() {
  local bad=0 out
  stub_setup
  out=$(run_reh rh-g1 plan --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "a local driver and the committed specs: plan exits 0" "$out" "status 0"
  mkconf "$cfgdir"
  out=$(run_reh rh-g2 plan --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "a driver that is not local is refused in plan" "$out" "REFUSED REHEARSAL_DRIVER_SSH must be local"
  has "with exit 2" "$out" "status 2"
  lacks "without its value" "$out" "driver-host-3"
  out=$(run_reh rh-g3 install --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "and in install" "$out" "REFUSED REHEARSAL_DRIVER_SSH must be local"
  out=$(run_reh rh-g4 run --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "and in run" "$out" "REFUSED REHEARSAL_DRIVER_SSH must be local"
  has "with exit 2 in run" "$out" "status 2"
  eq "nothing was started" "$(ls "$tmp/runs" | wc -l | tr -d ' ')" 0
  eq "and no host was called" "$(wc -c < "$stublog" | tr -d ' ')" 0
  mkconf_local "$cfgdir"

  # the spec tree: a changed file, a new file, a changed config, all against the candidate commit
  mkdir -p "$syn/web/e2e"
  printf 'one\n' > "$syn/web/e2e/a.spec.ts"
  printf '{}\n' > "$syn/web/package.json"
  git -C "$syn" add -A
  git -C "$syn" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "web"
  out=$(run_reh rh-g5 plan --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "the committed spec tree passes" "$out" "status 0"
  printf 'two\n' > "$syn/web/e2e/a.spec.ts"
  out=$(run_reh rh-g6 plan --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "a changed spec file is refused, naming the paths" "$out" "REFUSED the spec tree (web/e2e web/playwright.config.ts web/package.json web/package-lock.json) differs from the candidate commit"
  has "with exit 2" "$out" "status 2"
  git -C "$syn" checkout -q -- web/e2e/a.spec.ts
  printf 'new\n' > "$syn/web/e2e/b.spec.ts"
  out=$(run_reh rh-g7 install --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "a new spec file is refused" "$out" "differs from the candidate commit"
  rm -f "$syn/web/e2e/b.spec.ts"
  printf '{"x":1}\n' > "$syn/web/package.json"
  out=$(run_reh rh-g8 run --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "a changed package.json is refused in run" "$out" "differs from the candidate commit"
  has "with exit 2 in run" "$out" "status 2"
  git -C "$syn" checkout -q -- web/package.json
  out=$(run_reh rh-g9 plan --version 1.0.0 --rc 1 --record "$tmp/g.md")
  has "restored, the plan passes again" "$out" "status 0"

  # --runs: below 20 in real mode, malformed, and the dry range; --plant belongs to report and run
  out=$(run_reh rh-g10 plan --version 1.0.0 --rc 1 --runs 5 --record "$tmp/g.md")
  has "--runs 5 is refused in a real plan" "$out" "REFUSED --runs 5 is below 20"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-g11 install --version 1.0.0 --rc 1 --runs 5 --record "$tmp/g.md")
  has "and in install" "$out" "REFUSED --runs 5 is below 20"
  out=$(run_reh rh-g12 run --version 1.0.0 --rc 1 --runs 19 --record "$tmp/g.md")
  has "and in run" "$out" "REFUSED --runs 19 is below 20"
  out=$(run_reh rh-g13 plan --version 1.0.0 --rc 1 --runs 20 --record "$tmp/g.md")
  has "--runs 20 is accepted" "$out" "status 0"
  for d in 0 x 05 1.5 -3; do
    out=$(run_reh rh-g14 plan --version 1.0.0 --rc 1 --runs "$d" --record "$tmp/g.md")
    has "--runs '$d' is refused" "$out" "REFUSED --runs must be a positive whole number"
  done
  out=$(run_reh rh-g15 plan --rc 1 --dry-run --runs 21)
  has "--runs 21 is refused in a dry run" "$out" "REFUSED --runs must be 1 to 20 in a dry run"
  out=$(run_reh rh-g16 plan --rc 1 --dry-run --runs 20)
  has "--runs 20 is accepted in a dry run" "$out" "status 0"
  out=$(run_reh rh-g17 plan --version 1.0.0 --rc 1 --plant pick-up --record "$tmp/g.md")
  has "--plant is refused by plan" "$out" "REFUSED --plant is taken by report and run"
  out=$(run_reh rh-g18 install --version 1.0.0 --rc 1 --plant pick-up --record "$tmp/g.md")
  has "and by install" "$out" "REFUSED --plant is taken by report and run"
  out=$(run_reh rh-g19 run --version 1.0.0 --rc 1 --plant pick-up --record "$tmp/g.md")
  has "--plant in a real run is refused" "$out" "REFUSED --plant is for dry runs only"
  has "with exit 2" "$out" "status 2"
  out=$(run_reh rh-g20 run --version 1.0.0 --rc 1 --plant bogus --record "$tmp/g.md")
  has "an unknown bound id is refused" "$out" "REFUSED --plant 'bogus' is not a bound id with a limit"
  eq "none of these started a state" "$(ls "$tmp/runs" | wc -l | tr -d ' ')" 0
  [ "$bad" -eq 0 ]
}

# --- the real tree ---

t_real() {
  local bad=0 out marker=$tmp/docker-called
  mkdir -p "$tmp/bin" "$tmp/rt"
  printf '#!/bin/sh\necho called >> "%s"\nexit 1\n' "$marker" > "$tmp/bin/docker"
  chmod 755 "$tmp/bin/docker"
  out=$(PATH="$tmp/bin:$PATH" TMPDIR=$tmp/rt OCUTALON_RUN_TAG=rt-plan bash "$root/release/rehearse.sh" plan --rc 1 --dry-run < /dev/null 2>&1)
  eq "plan --dry-run exits 0" "$?" 0
  has "plan names the stand-ins" "$out" "PLAN hosts clean stand-in, driver stand-in"
  has "plan names the candidate" "$out" "PLAN candidate HEAD"
  has "plan names the dry-run mode" "$out" "PLAN mode dry run"
  has "plan gives the default record path" "$out" "PLAN record release/records/"
  eq "plan called no docker" "$([ -e "$marker" ] && echo called || echo none)" none
  eq "plan started no state" "$(ls "$tmp/rt" | wc -l | tr -d ' ')" 0
  PATH="$tmp/bin:$PATH" TMPDIR=$tmp/rt bash "$root/release/rehearse.sh" plan --version 9.9.9 --rc 1 --dry-run < /dev/null > "$tmp/rt.out" 2>&1
  eq "plan --version 9.9.9 exits 2" "$?" 2
  has "it says the version is not the candidate's" "$(cat "$tmp/rt.out")" "is not the candidate's version"
  TMPDIR=$tmp/rt OCUTALON_RUN_TAG=rt-nostate bash "$root/release/rehearse.sh" report < /dev/null > "$tmp/rt2.out" 2>&1
  eq "report with no state exits 2" "$?" 2
  env -u OCUTALON_RUN_TAG TMPDIR=$tmp/rt bash "$root/release/rehearse.sh" report < /dev/null > "$tmp/rt3.out" 2>&1
  eq "report with no tag exits 2" "$?" 2
  has "and says it needs the tag" "$(cat "$tmp/rt3.out")" "OCUTALON_RUN_TAG"
  [ "$bad" -eq 0 ]
}
# --- down of a dry run, on a stub docker ---

t_dry_down() {
  local bad=0 d=$tmp/dd tag=rh-ddown st locks out log proj
  rm -rf "$d"
  mkdir -p "$d/bin" "$d/locks"
  locks=$d/locks
  log=$d/docker.log
  : > "$log"
  printf '#!/bin/sh\necho "docker $*" >> "%s"\nexit 0\n' "$log" > "$d/bin/docker"
  chmod 755 "$d/bin/docker"
  proj=ocutalon-rehearse-$tag-1700000000-1
  mkdd() { # mkdd <lock content saved>: a dry run's state after install, and the lane lock as lib-live claimed it
    st=$d/tmp/ocutalon-rehearsal-$tag
    rm -rf "$st"
    mkdir -p "$st/standin"
    printf 'mode=dry\n' > "$st/options"
    printf '%s\n' "$proj" > "$st/standin/project"
    printf '%s\n' "$locks/throwaway-iris.lock" > "$st/standin/lock.file"
    printf '%s\n' "$1" > "$st/standin/lock.content"
    printf '%s\n' "$proj-base:tag1" "sha256:abcdef" > "$st/standin/images"
    printf 'epic=11 stage=test project=%s\n' "$proj" > "$locks/throwaway-iris.lock"
  }
  mkdd "epic=11 stage=test project=$proj"
  out=$(PATH="$d/bin:$PATH" TMPDIR=$d/tmp OCUTALON_LOCK_DIR=$locks OCUTALON_RUN_TAG=$tag bash "$root/release/rehearse.sh" down < /dev/null 2>&1)
  eq "down of a dry run exits 0" "$?" 0
  has "it tears the tag down" "$out" "TEARDOWN tag $tag:"
  has "it releases the lane lock" "$out" "LOCK released throwaway-iris project=$proj"
  eq "the lane lock is gone" "$([ -e "$locks/throwaway-iris.lock" ] && echo there || echo gone)" gone
  has "the saved image name is removed" "$(cat "$log")" "docker image rm $proj-base:tag1"
  has "the saved image id is removed" "$(cat "$log")" "docker image rm -f sha256:abcdef"
  eq "the state is gone" "$([ -d "$st" ] && echo there || echo gone)" gone
  has "the last line says what was removed" "$out" "TEARDOWN rehearsal tag $tag: the throwaway and the state are removed"

  mkdd "epic=9 stage=qa project=someone-else"
  out=$(PATH="$d/bin:$PATH" TMPDIR=$d/tmp OCUTALON_LOCK_DIR=$locks OCUTALON_RUN_TAG=$tag bash "$root/release/rehearse.sh" down < /dev/null 2>&1)
  has "a lock whose content is not the saved one is kept" "$out" "LOCK kept"
  eq "and stays in the lane folder" "$([ -e "$locks/throwaway-iris.lock" ] && echo there || echo gone)" there
  rm -rf "$d"
  [ "$bad" -eq 0 ]
}

# report and report --plant on a dry state with a run: the plant reaches the evaluation through the command.
t_dry_report() {
  local bad=0 d=$tmp/drep tag=rh-drep st out rec
  rm -rf "$d"
  mkdir -p "$d"
  st=$d/ocutalon-rehearsal-$tag
  rec=$d/rec.md
  mkruns "$st" 1 dry
  env_set "$st/options" version 1.0.0
  env_set "$st/options" rc 1
  env_set "$st/options" branch rehearsal/stand-in
  env_set "$st/options" cand_sha 1111111111111111111111111111111111111111
  env_set "$st/options" base_sha 2222222222222222222222222222222222222222
  env_set "$st/options" started 2026-11-01T10:00:00Z
  env_set "$st/options" record "$rec"
  printf 'Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory; Node.js absent\n' > "$st/machine.clean"
  printf 'macOS 26.0.1, arm64, 64.0 GiB memory\n' > "$st/machine.driver"
  printf 'done 0\n' > "$st/phase.install"
  mkdir -p "$st/standin"
  printf 'SOME_SETTING=plain\n' > "$st/standin/env"
  out=$(TMPDIR=$d OCUTALON_RUN_TAG=$tag bash "$root/release/rehearse.sh" report < /dev/null 2>&1; echo "status $?")
  has "a dry report with a run reads dry run" "$out" "RESULT dry run"
  has "and exits 3" "$out" "status 3"
  has "a met bound reads dry run, never pass" "$(cat "$rec")" "| pick-up | dry run |"
  out=$(TMPDIR=$d OCUTALON_RUN_TAG=$tag bash "$root/release/rehearse.sh" report --plant pick-up < /dev/null 2>&1; echo "status $?")
  has "the plant reaches the evaluation through report" "$out" "FAIL run 1 step incident bound pick-up 0 s (planted):"
  has "the planted report fails" "$out" "RESULT fail"
  has "and exits 1" "$out" "status 1"
  has "the record says planted" "$(cat "$rec")" "(planted)"
  out=$(TMPDIR=$d OCUTALON_RUN_TAG=$tag bash "$root/release/rehearse.sh" report --plant "notice pick-up" < /dev/null 2>&1; echo "status $?")
  has "a plant of two ids is refused" "$out" "status 2"
  rm -rf "$d"
  [ "$bad" -eq 0 ]
}

# --- static ---

SCRIPTS="release/rehearse.sh release/lib-release.sh"

static_hits() { # static_hits <files...>: one line per violation
  local f
  for f in "$@"; do
    grep -nE '^[[:space:]]*(source|\.)[[:space:]]+"?\$' "$f" | grep -vE 'release/lib-release\.sh|docker/tests/lib-keys\.sh|ci/iris\.sh' | sed "s|^|$f: sourced variable path: |"
    grep -nE 'cat[[:space:]]+"?\$[^|;&)]*[eE][nN][vV]' "$f" | sed "s|^|$f: cat of an env file: |"
    grep -nE 'printenv|set -x|declare -p|(^|[^a-z_])env[[:space:]]*(\||$)' "$f" | sed "s|^|$f: prints the environment: |"
    grep -q '^umask 077$' "$f" || echo "$f: no umask 077"
    [ -x "$f" ] || echo "$f: not executable"
    if [ -n "$(git ls-files --stage -- "$f" 2> /dev/null)" ] && ! git ls-files --stage -- "$f" | grep -q '^100755 '; then echo "$f: not mode 100755 in git"; fi
    LC_ALL=C grep -n '[^[:print:][:space:]]' "$f" | sed "s|^|$f: not ASCII: |"
    grep -nE 'StrictHostKeyChecking=(no|accept-new)' "$f" | sed "s|^|$f: host keys not strict: |"
    grep -nE 'docker[[:space:]]+(image[[:space:]]+|container[[:space:]]+)?(push|login|logout|save|export)([[:space:]]|$)' "$f" | sed "s|^|$f: docker push, login, save or export: |"
  done
}

t_static() {
  local bad=0 out
  out=$(static_hits $SCRIPTS)
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    bad=1
  fi
  # The collector only reads: no global set, no Kill, no save, and no statement that writes rows.
  out=$(printf '%s\n' "$COLLECTOR" | grep -inE '(^|[^A-Za-z])(Set[[:space:]]+\^|Kill|%Save|%Delete|%DeleteId|INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER)([^A-Za-z]|$)' | cut -c1-60)
  if [ -n "$out" ]; then
    printf 'the collector writes: %s\n' "$out"
    bad=1
  fi
  if ! printf '%s\n' "$COLLECTOR" | grep -q 'SELECT'; then
    echo "the collector holds no SELECT"
    bad=1
  fi
  [ "$bad" -eq 0 ]
}
# The break: a scripts list that holds a file with every violation.
b_static() {
  {
    printf '#!/usr/bin/env bash\n. "$somewhere/x.sh"\ncat "$ENV_FILE"\nssh -o StrictHostKeyChecking=no h\n%s push x\n' docker
    printf 'echo caf\303\251\n'
  } > "$tmp/bad-static.sh"
  SCRIPTS="$tmp/bad-static.sh"
  COLLECTOR=$(printf 'Set ^Probe(1)=2\nDo obj.%%Save()\n')
}

rule config t_config b_config
rule host-run t_host_run b_host_run
rule parsers t_parsers b_parsers
rule results t_results b_results
rule record t_record b_record
rule env-hits t_env_hits b_env_hits
rule dry-section t_dry_section b_dry_section
rule stub-runs t_stub_runs
rule phase-order t_phase_order
rule candidate t_candidate
rule bounds t_bounds b_bounds
rule timed-runs t_timed_runs
rule guards t_guards
rule real-tree t_real
rule dry-down t_dry_down
rule dry-report t_dry_report
rule static t_static b_static

if [ "$fails_total" -ne 0 ]; then
  echo "test-rehearsal: $fails_total rule(s) failed"
  exit 1
fi
echo "test-rehearsal: all rules passed"
