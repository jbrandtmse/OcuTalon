#!/usr/bin/env bash
# Hermetic self-test of the clean-machine rehearsal (Story 11.3; release/rehearse.sh, release/lib-release.sh, env_file_hits of
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
#   - stub-runs: the copied script, run for real in a synthetic git repository against stub hosts: a hosts failure, a clone HEAD
#     mismatch, a failed install.sh, and every step passing then report (twice), a planted value, phase order and the Candidate refusals;
#   - real-tree: plan on this checkout starts nothing, a version that is not the candidate's and a report with no state exit 2;
#   - dry-down: down of a dry run's state on a stub docker: the saved image names removed, the lane lock released only when its content
#     is the saved one, and the state removed;
#   - static: no sourcing of a variable path but the three libraries, no cat of an env file, umask 077, mode 100755, ASCII, strict host
#     keys and no docker push, login, save or export.
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
        sleep 1
        cat "$STUB_INSTALL_OUT"
        rm -f "$inp"
        exit "${STUB_INSTALL_RC:-0}"
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
  eq "a real run whose steps pass is not run (the timed runs are not built)" "$(rehearsal_result real "$r")" "not run"
  eq "a dry run is a dry run" "$(rehearsal_result dry "$r")" "dry run"
  printf 'runs|pass|x\n' >> "$r"
  eq "a real run with every row passing is a pass" "$(rehearsal_result real "$r")" pass
  eq "a dry run never passes" "$(rehearsal_result dry "$r")" "dry run"
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
  has "the timed runs are not run" "$out" "| demo path runs | not run | the timed runs come with Story 11.11 |"
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
  mkdir -p "$1/release" "$1/docker/tests" "$1/src/ocutalon/csp"
  git init -q "$1"
  git -C "$1" symbolic-ref HEAD refs/heads/release/1.0.0-rc1
  cp "$root/release/rehearse.sh" "$root/release/lib-release.sh" "$1/release/"
  cp "$root/docker/tests/lib-keys.sh" "$1/docker/tests/"
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
    if [ -n "$tag" ]; then export OCUTALON_RUN_TAG=$tag; else unset OCUTALON_RUN_TAG; fi
    bash "$syn/release/rehearse.sh" "$@" < /dev/null 2>&1
    echo "status $?"
  )
}

stub_setup() {
  syn=$tmp/syn
  cfgdir=$tmp/stubcfg
  stubdir=$tmp/stubs
  stublog=$tmp/stub-calls.log
  mksyn "$syn"
  mkconf "$cfgdir"
  mkstub "$stubdir"
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
  out=$(run_reh rh-pass install --version 1.0.0 --rc 1 --record "$rec")
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
  eq "every call checks host keys strictly" "$(grep -c '^ARG StrictHostKeyChecking=yes$' "$stublog")" 7
  lacks "no host key check is switched off" "$argv" "StrictHostKeyChecking=no"
  lacks "no OCUTALON_INSTALL_WAIT is passed when the caller set none" "$argv" "OCUTALON_INSTALL_WAIT"
  eq "the calls are the probes, the copy, the clone, the env, install.sh and the sign-in" "$(grep -c '^CALL ' "$stublog")" 7
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
  has "the driver host line" "$(cat "$rec")" "Driver host: macOS 26.0.1, arm64, 64.0 GiB memory"
  lacks "no dry-run note in a real record" "$(cat "$rec")" "Note:"
  matches "the install row gives the first start, install included" "$(cat "$rec")" 'first start [1-9][0-9]* s, install included'
  has "install.sh's ready text is kept beside it" "$(cat "$rec")" 'OcuTalon is ready after 1 min 5 s.'
  has "the secrets row passes" "$(cat "$rec")" "| secrets | pass |"
  has "the timed runs are not run" "$(cat "$rec")" "| demo path runs | not run | the timed runs come with Story 11.11 |"
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
  mkconf "$cfgdir"
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
  has "plan names the hosts as configured" "$out" "PLAN hosts clean configured, driver configured"
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
  [ "$bad" -eq 0 ]
}
# The break: a scripts list that holds a file with every violation.
b_static() {
  {
    printf '#!/usr/bin/env bash\n. "$somewhere/x.sh"\ncat "$ENV_FILE"\nssh -o StrictHostKeyChecking=no h\n%s push x\n' docker
    printf 'echo caf\303\251\n'
  } > "$tmp/bad-static.sh"
  SCRIPTS="$tmp/bad-static.sh"
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
rule real-tree t_real
rule dry-down t_dry_down
rule static t_static b_static

if [ "$fails_total" -ne 0 ]; then
  echo "test-rehearsal: $fails_total rule(s) failed"
  exit 1
fi
echo "test-rehearsal: all rules passed"
