#!/usr/bin/env bash
# Static inspection of docker-compose.yml, docker/Dockerfile, .dockerignore and .env.example.
# Starts no container. Prints one PASS or FAIL line per check; exits 0 only when every check passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

compose=docker-compose.yml
dockerfile=docker/Dockerfile
fails=0

check() { # check <label> <command...>: passes when the command succeeds
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    fails=$((fails + 1))
  fi
}

# Non-comment, non-blank lines of a file.
code() { grep -v '^[[:space:]]*\(#\|$\)' "$1"; }

# --- docker-compose.yml ---

only_service_is_iris() {
  local names
  names=$(awk '
    /^services:/ { ins = 1; next }
    /^[^ #]/ { ins = 0 }
    ins && /^  [A-Za-z0-9_.-]+:/ { sub(/:.*/, ""); gsub(/ /, ""); print }
  ' "$compose")
  [ "$names" = iris ]
}

no_mock() { ! code "$compose" | grep -qi 'mock'; }

no_forbidden_key() { # no non-comment line starts with the given key
  ! code "$compose" | grep -q "^[[:space:]]*$1:"
}

no_superserver_port() { ! code "$compose" | grep -q '1972'; }

# start_period as seconds (accepts <n>s, <n>m, <n>h); prints nothing for any other form.
start_period_seconds() {
  code "$compose" | awk '
    $1 == "start_period:" {
      v = $2
      if (match(v, /^[0-9]+s$/)) { print substr(v, 1, length(v) - 1) + 0 }
      else if (match(v, /^[0-9]+m$/)) { print (substr(v, 1, length(v) - 1) + 0) * 60 }
      else if (match(v, /^[0-9]+h$/)) { print (substr(v, 1, length(v) - 1) + 0) * 3600 }
    }'
}

start_period_at_least_600() {
  local s
  s=$(start_period_seconds)
  [ -n "$s" ] && [ "$s" -ge 600 ]
}

has_line() { code "$1" | grep -q "$2"; }

health_timing() {
  has_line "$compose" '^[[:space:]]*interval:[[:space:]]*10s[[:space:]]*$' \
    && has_line "$compose" '^[[:space:]]*timeout:[[:space:]]*5s[[:space:]]*$' \
    && has_line "$compose" '^[[:space:]]*retries:[[:space:]]*3[[:space:]]*$'
}

check "compose: the only service is iris" only_service_is_iris
check "compose: no non-comment line says mock" no_mock
check "compose: no container_name" no_forbidden_key container_name
check "compose: no image tag" no_forbidden_key image
check "compose: no fixed volume or project name below the top level" \
  bash -c "! grep -v '^[[:space:]]*#' '$compose' | grep -q '^[[:space:]][[:space:]]*name:'"
check "compose: no superserver port" no_superserver_port
check "compose: top-level name ocutalon" has_line "$compose" '^name:[[:space:]]*ocutalon[[:space:]]*$'
check "compose: stop_grace_period 60s" has_line "$compose" '^[[:space:]]*stop_grace_period:[[:space:]]*60s[[:space:]]*$'
check "compose: start_period at least 600 s" start_period_at_least_600
check "compose: health check runs /opt/ocutalon/healthcheck.sh" \
  has_line "$compose" 'test:[[:space:]]*\["CMD",[[:space:]]*"/opt/ocutalon/healthcheck.sh"\]'
check "compose: health check interval 10s, timeout 5s, retries 3" health_timing
check "compose: IRIS_IMAGE build argument" has_line "$compose" 'IRIS_IMAGE:[[:space:]]*\${IRIS_IMAGE:-ocutalon-iris-base:2026\.3\.0AI\.154\.0}'
check "compose: pull_policy build" has_line "$compose" '^[[:space:]]*pull_policy:[[:space:]]*build[[:space:]]*$'
check "compose: restart unless-stopped" has_line "$compose" '^[[:space:]]*restart:[[:space:]]*unless-stopped[[:space:]]*$'
check "compose: optional .env file" \
  bash -c "grep -v '^[[:space:]]*#' '$compose' | grep -A1 '^[[:space:]]*-[[:space:]]*path:[[:space:]]*\.env[[:space:]]*\$' | grep -q '^[[:space:]]*required:[[:space:]]*false[[:space:]]*\$'"
check "compose: web port from OCUTALON_WEB_PORT" has_line "$compose" '"\${OCUTALON_WEB_PORT:-52773}:52773"'
check "compose: config parses (--quiet)" docker compose -f "$compose" config --quiet

# --- docker/Dockerfile ---

last_user_is_51773() {
  [ "$(code "$dockerfile" | awk '$1 == "USER" { u = $2 } END { print u }')" = 51773 ]
}

check "dockerfile: IRIS_IMAGE defaults to the retagged build 154 image" \
  has_line "$dockerfile" '^ARG IRIS_IMAGE=ocutalon-iris-base:2026\.3\.0AI\.154\.0$'
check "dockerfile: FROM the IRIS_IMAGE argument" has_line "$dockerfile" '^FROM \${IRIS_IMAGE}$'
check "dockerfile: runs as UID 51773" last_user_is_51773
check "dockerfile: data and merge environment" \
  bash -c "grep -q 'ISC_DATA_DIRECTORY=/durable/iris' '$dockerfile' && grep -q 'ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf' '$dockerfile'"
check "dockerfile: an empty version fails the build" has_line "$dockerfile" 'test -n "\$version"'
check "healthcheck.sh: POSIX sh" test "$(head -n 1 docker/healthcheck.sh)" = '#!/bin/sh'

# --- docker/merge.cpf and line endings ---

merge_directories_relative() {
  [ "$(grep -c 'Directory=' docker/merge.cpf)" -eq 4 ] && ! grep -q 'Directory="\{0,1\}/' docker/merge.cpf
}

# Files that the image copies, or that a script runs, keep LF in every checkout.
files_keep_lf() {
  local f
  for f in docker/Dockerfile docker/merge.cpf docker/healthcheck.sh docker/tests/test-compose-file.sh src/module.xml \
    .dockerignore .env.example; do
    [ "$(git check-attr eol -- "$f" | sed 's/.*: //')" = lf ] || return 1
  done
}

check "merge.cpf: four database directories, all relative" merge_directories_relative
check "gitattributes: the copied and executed files keep LF" files_keep_lf

# --- .dockerignore ---

dockerignore_is_allow_list() {
  # The first rule is '*', and the only exceptions are the files the Dockerfile copies.
  [ "$(code .dockerignore | head -n 1)" = '*' ] || return 1
  ! code .dockerignore | grep -v '^\*$' \
    | grep -v -x -e '!docker/merge.cpf' -e '!docker/healthcheck.sh' -e '!src/module.xml' \
    | grep -q .
}

check "dockerignore: allow-list of the copied files only" dockerignore_is_allow_list

# --- .env.example ---

env_example_has_keys_without_values() {
  grep -qx 'ANTHROPIC_API_KEY=' .env.example \
    && grep -qx 'TELEGRAM_BOT_TOKEN=' .env.example \
    && ! code .env.example | grep -v -x -e 'ANTHROPIC_API_KEY=' -e 'TELEGRAM_BOT_TOKEN=' | grep -q .
}

# git check-ignore exits 0 when ignored, 1 when not ignored, 128 on error.
# The rule that ignores a path must be one of this repository's .gitignore, not a user's global ignore file;
# -v also prints a matching negation, so the ignore itself is checked with -q.
# A tracked path is never reported as ignored unless --no-index is given.
git_ignores() { git check-ignore -q "$1" && git check-ignore -v "$1" 2>/dev/null | grep -q '^\.gitignore:[0-9]*:[^!]'; }
git_does_not_ignore() { git check-ignore -q --no-index "$1"; [ $? -eq 1 ]; }

check "env.example: both keys, no values, nothing else" env_example_has_keys_without_values
check "git: .env is ignored" git_ignores .env
check "git: .env.example is not ignored" git_does_not_ignore .env.example

if [ "$fails" -ne 0 ]; then
  echo "test-compose-file: $fails check(s) failed"
  exit 1
fi
echo "test-compose-file: all checks passed"
