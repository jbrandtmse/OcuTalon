#!/usr/bin/env bash
# Hermetic test of install.sh (Story 10.1). Starts no container and reads no real Docker: a stub docker and a stub sleep come first on a
# private PATH, with the few tools the script needs, so a machine's own docker is never reached. Each case gets its own judge folder
# (install.sh and .env.example copied in), its own stub answers (the files of one data folder: the images that `docker image ls` lists,
# what `docker image inspect` says of them, the daemon's architecture, the Compose version, one health line per poll with the last one
# repeated, the exit code of `compose up -d` and the port line), and a clean environment. The stub logs every call, and the IRIS_IMAGE
# that `compose up -d` sees. install.sh runs under the bash that runs this test; with OCUTALON_TEST_BASH_MAJOR=3 (the macOS job, which
# runs /bin/bash) the test fails unless that bash has the major version 3.
# Rows, as in the matrix of the spec:
#   - images: Health first; only non-Health (its own reference is the build argument); prefixes and look-alikes; ties go to the first
#     reference in LC_ALL=C order; mixed CPUs; no image; wrong CPU; architecture names (aarch64, x86_64);
#   - an existing base: never re-tagged, named by ID match (Health, non-Health, neither), refused with the fix on the wrong CPU;
#   - the checks, all before any change: no docker, daemon unreachable, no Compose plugin, Compose older than 2.24 (DW-2) or unreadable,
#     Compose 2.24 or later accepted, no .env.example, a tag that fails;
#   - .env: created byte for byte from .env.example, an existing one is never touched and never printed;
#   - waiting: already healthy prints at once, unhealthy keeps waiting, the published port is the one printed, a timeout and a stopped
#     container (exited, dead, none) exit 1 with the logs command and the README section, `up -d` failing exits 1, the folder of the
#     script is the working folder, and the two overrides take whole seconds only;
#   - across all cases: every docker call is on the allow-list, no sudo, every sleep is at most 15 s; and install.sh holds
#     OCUTALON_INSTALL_WAIT:-900, is ASCII with LF line endings, is executable (git mode 100755 when git tracks it), and its text holds no
#     forbidden docker word.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
script="$root/install.sh"

fails=0
pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
# check <label> <command...>: passes when the command succeeds.
check() {
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ins.XXXXXX") || exit 1
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

echo "BASH ${BASH_VERSION%%(*}"
if [ -n "${OCUTALON_TEST_BASH_MAJOR:-}" ]; then
  check "bash: the major version is $OCUTALON_TEST_BASH_MAJOR" test "${BASH_VERSINFO[0]}" = "$OCUTALON_TEST_BASH_MAJOR"
fi

if [ ! -f "$script" ]; then
  fail "install.sh does not exist"
  echo "test-install-script: $fails check(s) failed"
  exit 1
fi

TAG=2026.3.0AI.154.0
BASE="ocutalon-iris-base:$TAG"
HEALTH_ID=aaaaaaaaaaaa
NON_HEALTH_ID=bbbbbbbbbbbb
ID_X=cccccccccccc
ID_Y=dddddddddddd
zeros=$(printf '%052d' 0)

# --- the private PATH and the stubs ---

toolbin="$tmp/tools"
mkdir "$toolbin"
for t in sort cp cat sed tail head grep awk tr wc cmp mkdir rm date basename dirname env ls touch; do
  p=$(command -v "$t") && ln -s "$p" "$toolbin/$t"
done
real_sleep=$(command -v sleep)

stubs="$tmp/stubs"
mkdir "$stubs"
cat > "$stubs/docker" <<'EOS'
#!/bin/sh
d=$STUB_DIR
printf '%s\n' "$*" >> "$d/calls"
case $1 in
  version)
    if [ -f "$d/daemon-down" ]; then exit 1; fi
    cat "$d/server-arch"
    ;;
  compose)
    shift
    case $1 in
      version)
        if [ -f "$d/no-compose" ]; then exit 1; fi
        cat "$d/compose-version"
        ;;
      up)
        printf 'IRIS_IMAGE=%s\n' "${IRIS_IMAGE-unset}" >> "$d/up-env"
        echo "stub: compose up"
        if [ -f "$d/up-sleep" ]; then "$STUB_REAL_SLEEP" "$(cat "$d/up-sleep")"; fi
        exit "$(cat "$d/up-exit")"
        ;;
      ps)
        n=$(cat "$d/polls" 2>/dev/null || echo 0)
        n=$((n + 1))
        echo "$n" > "$d/polls"
        line=$(sed -n "${n}p" "$d/health")
        if [ -z "$line" ]; then line=$(tail -n 1 "$d/health"); fi
        if [ "$line" != NONE ]; then printf '%s\n' "$line"; fi
        ;;
      port)
        if [ ! -f "$d/port" ]; then exit 1; fi
        cat "$d/port"
        ;;
      *)
        echo "stub: unexpected compose call" >&2
        exit 64
        ;;
    esac
    ;;
  image)
    shift
    case $1 in
      ls) cat "$d/images" ;;
      inspect)
        if [ "$2" != --format ]; then
          echo "stub: image inspect without --format" >&2
          exit 99
        fi
        fmt=$3
        row=$(awk -v t="$4" '$1 == t { print; exit }' "$d/inspect")
        if [ -z "$row" ]; then
          echo "Error: No such image: $4" >&2
          exit 1
        fi
        full=$(printf '%s\n' "$row" | awk '{ print $2 }')
        arch=$(printf '%s\n' "$row" | awk '{ print $3 }')
        case $fmt in
          '{{.Architecture}}') echo "$arch" ;;
          '{{.Id}} {{.Architecture}}') echo "$full $arch" ;;
          *)
            echo "stub: unknown format" >&2
            exit 98
            ;;
        esac
        ;;
      *)
        echo "stub: unexpected image call" >&2
        exit 64
        ;;
    esac
    ;;
  tag)
    if [ -f "$d/tag-fails" ]; then exit 1; fi
    ;;
  *)
    echo "stub: unexpected docker call" >&2
    exit 64
    ;;
esac
EOS
cat > "$stubs/sleep" <<'EOS'
#!/bin/sh
printf '%s\n' "$1" >> "$STUB_DIR/sleeps"
if [ "${STUB_SLEEP:-0}" -gt 0 ]; then "$STUB_REAL_SLEEP" "$STUB_SLEEP"; fi
EOS
cat > "$stubs/sudo" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exit 1
EOS
chmod 755 "$stubs/docker" "$stubs/sleep" "$stubs/sudo"

# --- the cases ---

# new_case <name> [nodocker]: a fresh case folder $c with the judge folder, the stubs and the default answers (an arm64 daemon, Compose
# 2.40.3, no image, a healthy container, port 52773, `up -d` exits 0). $d is its data folder.
new_case() {
  c="$tmp/$1"
  d="$c/data"
  mkdir -p "$c/judge" "$c/bin" "$d"
  cp "$script" "$c/judge/install.sh"
  cp "$root/.env.example" "$c/judge/.env.example"
  cp "$stubs/sleep" "$stubs/sudo" "$c/bin/"
  if [ "${2:-}" != nodocker ]; then cp "$stubs/docker" "$c/bin/docker"; fi
  : > "$d/calls"
  : > "$d/images"
  : > "$d/inspect"
  echo arm64 > "$d/server-arch"
  echo 2.40.3 > "$d/compose-version"
  echo 'running healthy' > "$d/health"
  echo 0.0.0.0:52773 > "$d/port"
  echo 0 > "$d/up-exit"
  RUN_CWD=""
  RUN_SCRIPT=""
}

# add_image <reference> <id> <architecture>: a loaded image, as `docker image ls` lists it and as `docker image inspect` answers for its id.
add_image() {
  printf '%s %s\n' "$1" "$2" >> "$d/images"
  if ! grep -q "^$2 " "$d/inspect"; then printf '%s sha256:%s%s %s\n' "$2" "$2" "$zeros" "$3" >> "$d/inspect"; fi
}

# add_base <id> <architecture>: the base name exists and holds that image.
add_base() {
  printf '%s %s\n' "$BASE" "$1" >> "$d/images"
  printf '%s sha256:%s%s %s\n' "$BASE" "$1" "$zeros" "$2" >> "$d/inspect"
}

# run_install [NAME=value]...: runs the case's install.sh with the bash that runs this test, the case's private PATH and a clean
# environment, from RUN_CWD (default: the judge folder), as RUN_SCRIPT (default: the absolute path of the judge folder's install.sh).
# Sets out (standard output and error together) and rc.
run_install() {
  local cwd=${RUN_CWD:-$c/judge}
  mkdir -p "$cwd"
  out=$(cd "$cwd" && env -i PATH="$c/bin:$toolbin" HOME="$tmp" STUB_DIR="$d" STUB_REAL_SLEEP="$real_sleep" STUB_SLEEP=0 \
    OCUTALON_INSTALL_POLL=1 OCUTALON_INSTALL_WAIT=30 "$@" "$BASH" "${RUN_SCRIPT:-$c/judge/install.sh}" 2>&1)
  rc=$?
}

out_has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
out_has_re() { printf '%s\n' "$out" | grep -qE -- "$1"; }
out_lacks() { ! out_has "$1"; }
out_count() { printf '%s\n' "$out" | grep -c -- "$1"; }
call_count() { grep -c -- "$1" "$d/calls"; }
# no_change: nothing was tagged, written or started in the case.
no_change() {
  [ "$(call_count '^tag ')" -eq 0 ] && [ "$(call_count '^compose up')" -eq 0 ] && [ ! -e "$c/judge/.env" ]
}
no_tag() { [ "$(call_count '^tag ')" -eq 0 ]; }
tagged_once() { # tagged_once <id>: exactly one tag call, from that id to the base name
  [ "$(call_count '^tag ')" -eq 1 ] && grep -qx "tag $1 $BASE" "$d/calls"
}
up_env_is() { [ "$(cat "$d/up-env" 2>/dev/null)" = "IRIS_IMAGE=$1" ]; }
env_is_example() { cmp -s "$c/judge/.env" "$c/judge/.env.example"; }
exit_is() { [ "$rc" -eq "$1" ]; }
ready_block() { # ready_block <port>: the ready block with the address and the account
  out_has "OcuTalon is ready after " && out_has "http://localhost:$1/ocutalon/" && out_has "User:      ocutalon" && out_has "Password:  ocutalon"
}
failure_help() { # the logs command, the README section and the promise that nothing was removed
  out_has "docker compose logs iris" && out_has "Troubleshooting section of README.md" && out_has "Nothing was removed"
}

# --- first run ---

new_case first-health
add_image "registry.example/team/irishealth-community:$TAG" $HEALTH_ID arm64
printf '%s\n' 'running starting' 'running starting' 'running healthy' > "$d/health"
run_install
check "first run, Health: exit 0" exit_is 0
check "first run, Health: names the IRIS for Health image" out_has "IRIS for Health"
check "first run, Health: the base name is tagged once, from the image id" tagged_once $HEALTH_ID
check "first run, Health: .env is a byte for byte copy of .env.example" env_is_example
check "first run, Health: says that the key is empty" out_has "(ANTHROPIC_API_KEY) in it is empty"
check "first run, Health: compose up runs with IRIS_IMAGE set to the base name" up_env_is "$BASE"
check "first run, Health: one progress line for each poll that is not ready" test "$(out_count '^Waiting, ')" -eq 2
check "first run, Health: the progress line holds the elapsed time and the state" out_has_re '^Waiting, [0-9]+ s so far: container running, health check starting$'
check "first run, Health: the ready block holds the port, the account and the elapsed time" ready_block 52773
check "first run, Health: it sleeps the poll interval between polls" test "$(tr '\n' ' ' < "$d/sleeps")" = "1 1 "

new_case both-images
add_image "registry.example/iris-community:$TAG" $NON_HEALTH_ID arm64
add_image "registry.example/irishealth-community:$TAG" $HEALTH_ID arm64
run_install
check "both images: exit 0" exit_is 0
check "both images: Health is the only docker tag source" tagged_once $HEALTH_ID
check "both images: the build argument is the base name" up_env_is "$BASE"
check "both images: says IRIS for Health, not non-Health" out_lacks "IRIS (non-Health), build 154 ("

new_case only-non-health
add_image "iris-community:$TAG" $NON_HEALTH_ID arm64
run_install
check "only non-Health: exit 0" exit_is 0
check "only non-Health: says IRIS (non-Health)" out_has "Image: IRIS (non-Health), build 154 (iris-community:$TAG)"
check "only non-Health: the base name is tagged from it" tagged_once $NON_HEALTH_ID
check "only non-Health: IRIS_IMAGE is the non-Health reference" up_env_is "iris-community:$TAG"

new_case only-non-health-prefixed
add_image "registry.example/team/iris-community:$TAG" $NON_HEALTH_ID arm64
run_install
check "only non-Health, prefixed: IRIS_IMAGE is the reference as listed" up_env_is "registry.example/team/iris-community:$TAG"

# --- prefixes and look-alikes ---

n=0
for ref in "irishealth-community:$TAG" "one/irishealth-community:$TAG" "a/b/c/irishealth-community:$TAG" "localhost:5000/team/irishealth-community:$TAG"; do
  n=$((n + 1))
  new_case "prefix-$n"
  add_image "$ref" $HEALTH_ID arm64
  run_install
  check "prefix: $ref is a Health candidate" tagged_once $HEALTH_ID
done

new_case look-alikes
add_image "irishealth-community-x:$TAG" $HEALTH_ID arm64
add_image "myiris-community:$TAG" $NON_HEALTH_ID arm64
add_image "x/myiris-community:$TAG" $NON_HEALTH_ID arm64
add_image "iris-community-x:$TAG" $NON_HEALTH_ID arm64
add_image "irishealth-community:2026.2" $ID_X arm64
add_image "iris-community:latest" $ID_Y arm64
run_install
check "look-alikes: never candidates, so it is the no-image row (exit 1)" exit_is 1
check "look-alikes: says no image is loaded" out_has "No IRIS build 154 image is loaded"
check "look-alikes: nothing changed" no_change

new_case tie-first-in-order
add_image "b/irishealth-community:$TAG" $ID_Y arm64
add_image "a/irishealth-community:$TAG" $ID_X arm64
run_install
check "tie: the first reference in LC_ALL=C order is the source" tagged_once $ID_X

new_case tie-skips-other-cpu
add_image "a/irishealth-community:$TAG" $ID_X amd64
add_image "b/irishealth-community:$TAG" $ID_Y arm64
run_install
check "tie: a candidate for another CPU is skipped" tagged_once $ID_Y

# --- CPUs ---

new_case mixed-cpus
add_image "x/irishealth-community:$TAG" $HEALTH_ID amd64
add_image "x/iris-community:$TAG" $NON_HEALTH_ID arm64
run_install
check "mixed CPUs: exit 0" exit_is 0
check "mixed CPUs: uses the non-Health image of this CPU" tagged_once $NON_HEALTH_ID
check "mixed CPUs: IRIS_IMAGE is the non-Health reference" up_env_is "x/iris-community:$TAG"
check "mixed CPUs: says the Health image is for another CPU" out_has "x/irishealth-community:$TAG is for x64, not for this machine's arm64"

new_case no-image
run_install
check "no image: exit 1" exit_is 1
check "no image: names the problem" out_has "No IRIS build 154 image is loaded in Docker"
check "no image: names the archive for this CPU" out_has "IRIS for Health AI Hub build 154 archive for this machine's CPU (arm64; the archives are for arm64 or x64)"
check "no image: gives the load command" out_has "docker load -i <the archive file>"
check "no image: nothing changed" no_change

new_case no-image-x64
echo amd64 > "$d/server-arch"
run_install
check "no image, x64 daemon: names x64" out_has "this machine's CPU (x64;"

new_case wrong-cpu
add_image "x/irishealth-community:$TAG" $HEALTH_ID amd64
add_image "x/iris-community:$TAG" $NON_HEALTH_ID amd64
run_install
check "wrong CPU: exit 1" exit_is 1
check "wrong CPU: names each image's CPU" test "$(out_count "is for x64$")" -eq 2
check "wrong CPU: names the machine's CPU and the archive for it" out_has "archive for arm64 and load it"
check "wrong CPU: gives the load command" out_has "docker load -i <the archive file>"
check "wrong CPU: nothing changed" no_change

new_case arch-names
echo x86_64 > "$d/server-arch"
add_image "x/irishealth-community:$TAG" $HEALTH_ID amd64
run_install
check "architecture names: x86_64 is amd64" tagged_once $HEALTH_ID
new_case arch-names-arm
echo aarch64 > "$d/server-arch"
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
run_install
check "architecture names: aarch64 is arm64" tagged_once $HEALTH_ID

# --- an existing base ---

new_case base-health
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
add_base $HEALTH_ID arm64
run_install
check "existing base, Health: exit 0" exit_is 0
check "existing base, Health: no docker tag" test "$(call_count '^tag ')" -eq 0
check "existing base, Health: says IRIS for Health and the existing wording" out_has "Image: IRIS for Health, build 154. The existing $BASE is that image"
check "existing base, Health: IRIS_IMAGE is the base name" up_env_is "$BASE"

new_case base-non-health
add_image "x/iris-community:$TAG" $NON_HEALTH_ID arm64
add_base $NON_HEALTH_ID arm64
run_install
check "existing base, non-Health: no docker tag" test "$(call_count '^tag ')" -eq 0
check "existing base, non-Health: says IRIS (non-Health)" out_has "Image: IRIS (non-Health), build 154. The existing $BASE is that image"
check "existing base, non-Health: IRIS_IMAGE is the non-Health reference" up_env_is "x/iris-community:$TAG"

new_case base-unknown
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
add_base $ID_X arm64
run_install
check "existing base, unknown: exit 0" exit_is 0
check "existing base, unknown: no docker tag" test "$(call_count '^tag ')" -eq 0
check "existing base, unknown: says it matches neither" out_has "Image: the existing $BASE. It matches neither"
check "existing base, unknown: IRIS_IMAGE is the base name" up_env_is "$BASE"

new_case base-unknown-no-candidate
add_base $ID_X arm64
run_install
check "existing base, no candidate loaded: exit 0" exit_is 0
check "existing base, no candidate loaded: no docker tag" no_tag

new_case base-wrong-cpu
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
add_base $ID_X amd64
run_install
check "existing base, wrong CPU: exit 1" exit_is 1
check "existing base, wrong CPU: says what is wrong" out_has "The image $BASE exists, but it is for x64, and this machine's Docker runs arm64."
check "existing base, wrong CPU: names the loaded image in the docker tag fix" out_has "docker tag x/irishealth-community:$TAG $BASE"
check "existing base, wrong CPU: nothing changed" no_change

new_case base-wrong-cpu-none
add_base $ID_X amd64
run_install
check "existing base, wrong CPU, no image loaded: exit 1" exit_is 1
check "existing base, wrong CPU, no image loaded: gives the load and the tag commands" test "$(out_has 'docker load -i <the archive file>' && out_has "irishealth-community:$TAG> $BASE" && echo ok)" = ok
check "existing base, wrong CPU, no image loaded: nothing changed" no_change

# --- the checks that come before any change ---

new_case no-docker nodocker
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
run_install
check "no docker: exit 1" exit_is 1
check "no docker: says to install Docker Desktop or Docker Engine" test "$(out_has 'Docker Desktop (macOS, or Windows with WSL)' && out_has 'Docker Engine (Linux)' && echo ok)" = ok
check "no docker: nothing changed" no_change

new_case daemon-down
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
: > "$d/daemon-down"
run_install
check "daemon unreachable: exit 1" exit_is 1
check "daemon unreachable: says Docker is not running or not reachable" out_has "it is not running, or this user cannot reach it"
check "daemon unreachable: gives the three fixes" test "$(out_has 'Start Docker Desktop' && out_has 'sudo systemctl start docker' && out_has 'docker group' && echo ok)" = ok
check "daemon unreachable: nothing changed" no_change

new_case no-compose
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
: > "$d/no-compose"
run_install
check "no Compose plugin: exit 1" exit_is 1
check "no Compose plugin: says to install the plugin 2.24 or later" test "$(out_has 'Install the Compose plugin, version 2.24 or later' && out_has 'docker-compose-plugin' && echo ok)" = ok
check "no Compose plugin: nothing changed" no_change

for v in 2.23.3 v2.20.2 2.9.0 1.29.2 dev; do
  new_case "compose-old-$v"
  add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
  echo "$v" > "$d/compose-version"
  run_install
  check "Compose $v: refused (exit 1) with the found version and the minimum" test "$(exit_is 1 && out_has "Docker Compose $v is too old" && out_has "2.24 or later" && echo ok)" = ok
  check "Compose $v: nothing changed" no_change
done

for v in 2.24.0 v2.40.3-desktop.1 5.5.0 2.100.0 v2.24.0-rc.1; do
  new_case "compose-ok-$v"
  add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
  echo "$v" > "$d/compose-version"
  run_install
  check "Compose $v: accepted" exit_is 0
done

new_case no-env-example
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
rm "$c/judge/.env.example"
run_install
check "no .env.example: exit 1 before any change" test "$(exit_is 1 && out_has 'This folder has no .env.example' && echo ok)" = ok
check "no .env.example: nothing changed" no_change

new_case tag-fails
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
: > "$d/tag-fails"
run_install
check "a tag that fails: exit 1 with a plain message" test "$(exit_is 1 && out_has "Docker could not give the image the name $BASE" && echo ok)" = ok
check "a tag that fails: no compose up" test "$(call_count '^compose up')" -eq 0
check "a tag that fails: no .env" test ! -e "$c/judge/.env"

# --- .env ---

new_case existing-env
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
printf 'SENTINEL_VALUE=keep-this-sentinel-text\n' > "$c/judge/.env"
cp "$c/judge/.env" "$c/env.before"
run_install
check "existing .env: exit 0" exit_is 0
check "existing .env: byte for byte the same afterwards" cmp -s "$c/judge/.env" "$c/env.before"
check "existing .env: the sentinel is in neither output stream" out_lacks "keep-this-sentinel-text"
check "existing .env: says that it was not changed" out_has "Found .env. It was not changed."
check "existing .env: no copy message" out_lacks "Created .env"

new_case existing-env-empty
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
: > "$c/judge/.env"
run_install
check "existing empty .env: stays empty" test ! -s "$c/judge/.env"

# --- waiting ---

new_case already-healthy
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
add_base $HEALTH_ID arm64
printf 'ANTHROPIC_API_KEY=\n' > "$c/judge/.env"
run_install
check "already healthy: exit 0" exit_is 0
check "already healthy: the ready block prints with no progress line" test "$(out_count '^Waiting, ')" -eq 0
check "already healthy: the ready block is complete" ready_block 52773
check "already healthy: no docker tag" no_tag
check "already healthy: one poll" test "$(call_count '^compose ps')" -eq 1
check "already healthy: it never sleeps" test ! -s "$d/sleeps"

new_case custom-port
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 0.0.0.0:52999 > "$d/port"
run_install
check "custom port: the address uses the published port" test "$(ready_block 52999 && out_lacks ':52773/' && echo ok)" = ok
new_case custom-port-ipv6
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
printf '0.0.0.0:52998\n[::]:52998\n' > "$d/port"
run_install
check "custom port, two lines: the first line is taken" ready_block 52998
new_case port-bracket
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo '[::]:52997' > "$d/port"
run_install
check "custom port, IPv6 only: the port after the last colon" ready_block 52997
new_case no-port
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
rm "$d/port"
run_install
check "no published port: exit 1 and says so" test "$(exit_is 1 && out_has 'reports no published web port' && echo ok)" = ok

new_case unhealthy-keeps-waiting
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
printf '%s\n' 'running unhealthy' 'running unhealthy' 'restarting ' 'running healthy' > "$d/health"
run_install
check "unhealthy and restarting keep waiting until healthy" test "$(exit_is 0 && ready_block 52773 && echo ok)" = ok
check "unhealthy: three progress lines" test "$(out_count '^Waiting, ')" -eq 3

new_case never-ready
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 'running starting' > "$d/health"
run_install OCUTALON_INSTALL_WAIT=2 STUB_SLEEP=1
check "never ready: exit 1" exit_is 1
check "never ready: says it was not ready after the wait" out_has_re '^OcuTalon was not ready after [0-9]+ s, the longest this script waits\.$'
check "never ready: the logs command, the README section, and nothing removed" failure_help
check "never ready: a progress line was printed" test "$(out_count '^Waiting, ')" -ge 1

for st in "exited" "dead" "NONE"; do
  new_case "stops-$st"
  add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
  printf '%s\n' 'running starting' "$st" > "$d/health"
  run_install
  check "container stops ($st): exit 1" exit_is 1
  check "container stops ($st): says it stopped" out_has "OcuTalon stopped before it was ready"
  check "container stops ($st): the logs command, the README section, and nothing removed" failure_help
done
new_case stops-at-once
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 'exited ' > "$d/health"
run_install
check "container stopped at the first poll: exit 1 with no progress line" test "$(exit_is 1 && out_count '^Waiting, ' )" = 0

new_case up-fails
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 1 > "$d/up-exit"
run_install
check "up fails: exit 1" exit_is 1
check "up fails: plain message with the logs command and the README section" test "$(out_has 'Docker Compose could not start OcuTalon' && failure_help && echo ok)" = ok
check "up fails: no poll afterwards" test "$(call_count '^compose ps')" -eq 0

new_case other-folder
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
RUN_CWD="$c/elsewhere"
run_install
check "other folder: exit 0" exit_is 0
check "other folder: .env is created in the script's folder" env_is_example
check "other folder: nothing is written to the working folder" test -z "$(ls -A "$c/elsewhere")"

new_case cdpath
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
mkdir -p "$c/decoy/judge"
RUN_CWD="$c"
RUN_SCRIPT="judge/install.sh"
run_install CDPATH="$c/decoy"
check "relative script path with CDPATH set: exit 0 in the script's own folder" exit_is 0
check "relative script path with CDPATH set: .env is created in the script's folder" env_is_example
check "relative script path with CDPATH set: the CDPATH folder is not used and not printed" test "$(test ! -e "$c/decoy/judge/.env" && out_lacks "$c/decoy" && echo ok)" = ok

new_case read-only-folder
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
chmod 555 "$c/judge"
if [ -w "$c/judge" ]; then
  pass "read-only folder: skipped, because this user can write to a folder of mode 555"
else
  run_install
  check "read-only folder, no .env: exit 1 with the fix" test "$(exit_is 1 && out_has 'This folder is read-only for you' && echo ok)" = ok
  check "read-only folder, no .env: nothing changed" no_change
fi
chmod 755 "$c/judge"

new_case cp-fails
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
printf '#!/bin/sh\nexit 1\n' > "$c/bin/cp"
chmod 755 "$c/bin/cp"
run_install
check "a copy of .env.example that fails: exit 1 with a plain message" test "$(exit_is 1 && out_has 'The file .env could not be created from .env.example' && echo ok)" = ok
check "a copy of .env.example that fails: no compose up and no .env" test "$(call_count '^compose up')-$(test -e "$c/judge/.env" && echo env)" = "0-"

new_case up-takes-time
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 1 > "$d/up-sleep"
run_install
check "the elapsed time counts from the start of compose up (the build is in it)" test "$(exit_is 0 && out_has_re 'OcuTalon is ready after [1-9][0-9]* s\.' && echo ok)" = ok

# --- the two overrides take whole seconds only ---

for bad in abc "" 2.5 -1 0x10 1234567; do
  new_case "poll-$bad"
  add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
  printf '%s\n' 'running starting' 'running healthy' > "$d/health"
  run_install OCUTALON_INSTALL_POLL="$bad"
  check "OCUTALON_INSTALL_POLL='$bad' falls back to 10 s" test "$(cat "$d/sleeps")" = 10
done
new_case poll-leading-zero
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
printf '%s\n' 'running starting' 'running healthy' > "$d/health"
run_install OCUTALON_INSTALL_POLL=007
check "OCUTALON_INSTALL_POLL=007 is 7 s, in base 10" test "$(cat "$d/sleeps")" = 7
for bad in soon ""; do
  new_case "wait-bad-$bad"
  add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
  printf '%s\n' 'running starting' 'running starting' 'running healthy' > "$d/health"
  run_install OCUTALON_INSTALL_WAIT="$bad" OCUTALON_INSTALL_POLL=1 STUB_SLEEP=1
  check "OCUTALON_INSTALL_WAIT='$bad' falls back to the default: two real seconds of waiting do not end the wait" test "$(exit_is 0 && ready_block 52773 && echo ok)" = ok
done
new_case wait-caps-sleep
add_image "x/irishealth-community:$TAG" $HEALTH_ID arm64
echo 'running starting' > "$d/health"
run_install OCUTALON_INSTALL_POLL=10 OCUTALON_INSTALL_WAIT=3 STUB_SLEEP=1
check "the last sleep never goes past the wait" test "$(exit_is 1 && head -n 1 "$d/sleeps")" = 3

# --- across all cases ---

all_calls="$tmp/all-calls"
cat "$tmp"/*/data/calls > "$all_calls"
call_allowed() {
  case $1 in
    "version --format "*) ;;
    "compose version"*) ;;
    "image ls --format "*) ;;
    "image inspect --format "*) ;;
    "tag "*) ;;
    "compose up -d") ;;
    "compose ps --all --format "*) ;;
    "compose port iris 52773") ;;
    *) return 1 ;;
  esac
}
bad_calls=0
n_calls=0
while IFS= read -r line; do
  n_calls=$((n_calls + 1))
  if ! call_allowed "$line"; then
    bad_calls=$((bad_calls + 1))
    echo "  not on the allow-list: $line"
  fi
done < "$all_calls"
check "calls: there are calls to check" test "$n_calls" -gt 0
check "calls: every docker call of every case is on the allow-list ($n_calls calls)" test "$bad_calls" -eq 0
check "calls: no case ran sudo" test -z "$(ls "$tmp"/*/data/sudo-calls 2>/dev/null)"
cat "$tmp"/*/data/sleeps > "$tmp/all-sleeps" 2>/dev/null
too_long=$(awk '$1 + 0 > 15 || $1 !~ /^[0-9]+$/ { n++ } END { print n + 0 }' "$tmp/all-sleeps")
check "sleeps: there are sleeps to check" test -s "$tmp/all-sleeps"
check "sleeps: every logged sleep is a whole number of at most 15 s" test "$too_long" -eq 0

# --- the file itself ---

check "install.sh holds OCUTALON_INSTALL_WAIT:-900" grep -qF 'OCUTALON_INSTALL_WAIT:-900' "$script"
cr=$(printf '\r')
check "install.sh has no CR byte" test -z "$(grep -c "$cr" "$script" | grep -v '^0$')"
check "install.sh is ASCII only" test -z "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$script")"
check "install.sh starts with the bash shebang" test "$(head -n 1 "$script")" = '#!/usr/bin/env bash'
mode=$(git ls-files -s -- install.sh 2>/dev/null | cut -d' ' -f1)
if [ -n "$mode" ]; then
  check "install.sh has git mode 100755" test "$mode" = 100755
else
  check "install.sh is executable (it is not tracked yet)" test -x "$script"
fi
eol=$(git check-attr eol -- install.sh 2>/dev/null | sed 's/.*: //')
check ".gitattributes: install.sh keeps LF on every checkout" test "$eol" = lf
script_tag=$(sed -n 's/^TAG=//p' "$script")
check "install.sh: its TAG is this test's tag and the tag of the compose file's default image" test "$(test "$script_tag" = "$TAG" && grep -qF "IRIS_IMAGE:-ocutalon-iris-base:$script_tag}" "$root/docker-compose.yml" && echo ok)" = ok
sed -n '/^fmt_time() {/,/^}/p' "$script" > "$tmp/fmt_time.sh"
# shellcheck source=/dev/null
. "$tmp/fmt_time.sh"
check "fmt_time: 45 s is '45 s'" test "$(fmt_time 45)" = "45 s"
check "fmt_time: 60 s is '1 min 0 s'" test "$(fmt_time 60)" = "1 min 0 s"
check "fmt_time: 125 s is '2 min 5 s'" test "$(fmt_time 125)" = "2 min 5 s"
code=$(grep -v '^[[:space:]]*#' "$script")
forbidden='docker( (compose|image|volume|container))? +(push|login|logout|pull|save|export|rm|rmi|prune|kill)([[:space:]]|$)|compose +(down|stop|rm|config|convert)([[:space:]]|$)|(image|volume) +rm([[:space:]]|$)|(^|[;&|])[[:space:]]*sudo([[:space:]]|$)|[$][(][[:space:]]*sudo'
check "install.sh text: no forbidden docker word or sudo command" test -z "$(printf '%s\n' "$code" | grep -nE "$forbidden")"
insp=inspect
check "install.sh text: every image inspect call has --format" test -z "$(printf '%s\n' "$code" | grep -E "docker( image)? $insp" | grep -v -e '--format')"
key_shape='sk-ant-[A-Za-z0-9_-]{8,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}'
check "install.sh text: nothing key-shaped" test -z "$(grep -nE "$key_shape" "$script")"

if [ "$fails" -ne 0 ]; then
  echo "test-install-script: $fails check(s) failed"
  exit 1
fi
echo "test-install-script: all checks passed"
