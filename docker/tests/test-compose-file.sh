#!/usr/bin/env bash
# Static inspection of docker-compose.yml, docker-compose.dev.yml, ci/compose.ci.yml, docker/Dockerfile, .dockerignore and
# .env.example. Starts no container. Prints one PASS or FAIL line per check; exits 0 only when every check passes.
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

# The judges' file names no file of ci/ (CON-3).
no_ci_reference() { ! code "$compose" | grep -qi 'ci/\|compose\.ci'; }

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
check "compose: no non-comment line names a file of ci/" no_ci_reference
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
check "dockerfile: CMD deletes the ready marker before IRIS starts, then runs the after-start script through iris-main" \
  has_line "$dockerfile" '^CMD \["--before", "rm -f /durable/ocutalon\.ready", "--after", "/opt/ocutalon/after-start\.sh"\]$'
check "dockerfile: the sources, the pinned IPM release and the scripts are copied" \
  bash -c "grep -q '^COPY src/ /opt/ocutalon/src/\$' '$dockerfile' && grep -q '^COPY docker/ipm/ /opt/ocutalon/ipm/\$' '$dockerfile' && grep -q '^COPY docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos /opt/ocutalon/\$' '$dockerfile'"
check "dockerfile: the version comes from the copied manifest" has_line "$dockerfile" '/opt/ocutalon/src/module\.xml'

# A source tree without the web bundle fails the build, in the same RUN as the version and before the modes are set.
bundle_guard_before_chmod() {
  local guard chmod_at
  guard=$(code "$dockerfile" | grep -n 'test -f /opt/ocutalon/src/ocutalon/csp/index\.html.*web bundle missing: run npm --prefix web run build.*exit 1' | head -n 1 | cut -d: -f1)
  chmod_at=$(code "$dockerfile" | grep -n 'chmod 444' | head -n 1 | cut -d: -f1)
  [ -n "$guard" ] && [ -n "$chmod_at" ] && [ "$guard" -lt "$chmod_at" ] \
    && [ "$(code "$dockerfile" | awk -v g="$guard" 'NR < g && /^USER / { n++ } END { print n + 0 }')" -eq 1 ]
}
check "dockerfile: a tree without src/ocutalon/csp/index.html fails the build, before the modes are set and the last USER" bundle_guard_before_chmod
check "module: the bundle is copied to the durable csp/ocutalon-web/ folder" \
  grep -q '<FileCopy Name="ocutalon/csp/" Target="${dataDir}csp/ocutalon-web/"/>' src/module.xml
check "healthcheck.sh: POSIX sh" test "$(head -n 1 docker/healthcheck.sh)" = '#!/bin/sh'
check "after-start.sh: bash" test "$(head -n 1 docker/after-start.sh)" = '#!/bin/bash'

# --- docker/merge.cpf and line endings ---

merge_directories_relative() {
  [ "$(grep -c 'Directory=' docker/merge.cpf)" -eq 4 ] && ! grep -q 'Directory="\{0,1\}/' docker/merge.cpf
}

# Files that the image copies, or that a script runs, keep LF in every checkout.
files_keep_lf() {
  local f
  for f in docker/Dockerfile docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos \
    docker/ipm/zpm-0.10.10.xml docker/ipm/LICENSE docker/tests/test-compose-file.sh docker/tests/lib-live.sh \
    src/module.xml src/bridge/cls/OcuTalon/Bridge/Installer.cls src/ocutalon/cls/OcuTalon/Install/Registry.cls \
    .dockerignore .env.example; do
    [ "$(git check-attr eol -- "$f" | sed 's/.*: //')" = lf ] || return 1
  done
}

# A binary under src/ (the committed web bundle's images and fonts) is detected, not forced to text.
src_binaries_not_forced_text() {
  local f
  for f in src/ocutalon/csp/favicon.ico src/ocutalon/csp/media/font.woff2 src/ocutalon/cls/OcuTalon/Install/Registry.cls; do
    [ "$(git check-attr text -- "$f" | sed 's/.*: //')" = auto ] || return 1
  done
}

check "merge.cpf: four database directories, all relative" merge_directories_relative
check "gitattributes: the copied and executed files keep LF" files_keep_lf
check "gitattributes: files under src/ are text only when git detects text, so a binary is never rewritten" src_binaries_not_forced_text

# --- .dockerignore ---

dockerignore_is_allow_list() {
  # The first rule is '*', and the only exceptions are the files the Dockerfile copies.
  [ "$(code .dockerignore | head -n 1)" = '*' ] || return 1
  ! code .dockerignore | grep -v '^\*$' \
    | grep -v -x -e '!docker/merge.cpf' -e '!docker/healthcheck.sh' -e '!docker/after-start.sh' -e '!docker/after-start.cos' \
      -e '!docker/ipm/zpm-0.10.10.xml' -e '!docker/ipm/LICENSE' -e '!src' \
    | grep -q .
}

# Every exception the Dockerfile's COPY lines need is in the list, and none is missing.
dockerignore_names_every_exception() {
  local rule
  for rule in '!docker/merge.cpf' '!docker/healthcheck.sh' '!docker/after-start.sh' '!docker/after-start.cos' \
    '!docker/ipm/zpm-0.10.10.xml' '!docker/ipm/LICENSE' '!src'; do
    code .dockerignore | grep -qx -e "$rule" || return 1
  done
}

check "dockerignore: allow-list of the copied files only" dockerignore_is_allow_list
check "dockerignore: every copied file or directory is allowed" dockerignore_names_every_exception

# --- docker-compose.dev.yml ---

dev=docker-compose.dev.yml

# The override holds the project name and the one variable, and nothing else.
dev_file_is_exact() {
  [ "$(code "$dev")" = "name: ocutalon-dev
services:
  iris:
    environment:
      OCUTALON_DEV: \"1\"" ]
}

dev_no_mock() { ! code "$dev" | grep -qi 'mock'; }
dev_no_container_name() { ! code "$dev" | grep -q "^[[:space:]]*container_name:"; }

check "dev: the file holds only the project name and OCUTALON_DEV \"1\"" dev_file_is_exact
check "dev: top-level name ocutalon-dev" has_line "$dev" '^name:[[:space:]]*ocutalon-dev[[:space:]]*$'
check "dev: OCUTALON_DEV is \"1\" for the iris service" has_line "$dev" '^[[:space:]]*OCUTALON_DEV:[[:space:]]*"1"[[:space:]]*$'
check "dev: no non-comment line says mock" dev_no_mock
check "dev: no container_name" dev_no_container_name
check "dev: config parses together with the judges' file (--quiet)" docker compose -f "$compose" -f "$dev" config --quiet

# --- ci/compose.ci.yml ---

ci=ci/compose.ci.yml

# The override is exactly the mock's wiring (Stories 0.11 and 10.3): the project name; the iris service with OCUTALON_EVAL passed
# through from the environment (default 0), OCUTALON_MODEL_BASE_URL, the CI-only switch OCUTALON_MOCK_KEY_HEADER (owner
# decision 5), the Bot API base OCUTALON_TELEGRAM_API_BASE and the dummy bot token TELEGRAM_BOT_TOKEN, and the read-only log volume;
# the mock service from the public node image pinned by digest, with ci/mock mounted read-only; and the named volume mock-log.
# Nothing else.
ci_file_is_exact() {
  [ "$(code "$ci")" = 'name: ocutalon-ci
services:
  iris:
    environment:
      OCUTALON_EVAL: ${OCUTALON_EVAL:-0}
      OCUTALON_MODEL_BASE_URL: http://mock:8080/v1/
      OCUTALON_MOCK_KEY_HEADER: "1"
      OCUTALON_TELEGRAM_API_BASE: http://mock:8080
      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token
    volumes:
      - mock-log:/opt/ocutalon/mock-log:ro
  mock:
    image: node:24.15.0-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d
    pull_policy: missing
    command: ["node", "/mock/server.mjs", "--log-dir", "/log"]
    volumes:
      - ./ci/mock:/mock:ro
      - mock-log:/log
    healthcheck:
      test: ["CMD", "node", "/mock/health.mjs"]
      interval: 2s
      timeout: 2s
      retries: 15
    stop_grace_period: 2s
volumes:
  mock-log:' ]
}

# The services are iris, and a service named mock (Story 0.11).
ci_services_are_known() {
  local names
  names=$(awk '
    /^services:/ { ins = 1; next }
    /^[^ #]/ { ins = 0 }
    ins && /^  [A-Za-z0-9_.-]+:/ { sub(/:.*/, ""); gsub(/ /, ""); print }
  ' "$ci" | grep -v -x -e iris -e mock)
  [ -z "$names" ]
}

# The non-comment lines of one service block of the CI file (the lines below `  <service>:` up to the next service).
ci_block() {
  code "$ci" | awk -v want="$1" '
    /^[^ ]/ { ins = 0 }
    /^services:/ { ins = 1; next }
    ins && /^  [A-Za-z0-9_.-]+:/ { cur = $1; sub(/:$/, "", cur); next }
    ins && cur == want { print }
  '
}

ci_adds_no_port_or_publishing_key() {
  ! code "$ci" | grep -qE '^[[:space:]]*(ports|env_file|container_name|build|privileged|network_mode|extra_hosts):'
}

# No model key and no variable that looks like a key, a token or a secret, except the one dummy bot token (Story 10.3), which the
# iris block sets once and which is checked below. A line that sets TELEGRAM_BOT_TOKEN is the only line that may name TELEGRAM.
ci_adds_no_key_variable() {
  ! code "$ci" | grep -v -x -e '      OCUTALON_TELEGRAM_API_BASE: http://mock:8080' -e '      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token' \
    | grep -qE 'ANTHROPIC|TELEGRAM|API_KEY|_TOKEN|SECRET|PASSWORD'
}

# image: appears once, in the mock block, as node:<x.y.z>-slim@sha256:<64 hex>.
ci_image_is_the_pinned_node() {
  [ "$(code "$ci" | grep -cE '^[[:space:]]*image:')" -eq 1 ] \
    && [ "$(ci_block mock | grep -cE '^[[:space:]]*image:[[:space:]]*node:[0-9]+\.[0-9]+\.[0-9]+-slim@sha256:[0-9a-f]{64}[[:space:]]*$')" -eq 1 ]
}

# command: appears only in the mock block.
ci_command_only_in_mock() {
  [ "$(code "$ci" | grep -cE '^[[:space:]]*command:')" -eq 1 ] \
    && [ "$(ci_block mock | grep -cE '^[[:space:]]*command:')" -eq 1 ]
}

# The CI-only switch of owner decision 5: the iris block sets OCUTALON_MOCK_KEY_HEADER to "1", once, and nothing else in the
# file mentions it.
ci_sets_mock_key_header_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_MOCK_KEY_HEADER')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_MOCK_KEY_HEADER: "1"')" -eq 1 ]
}

# The Bot API wiring of Story 10.3: the iris block sets OCUTALON_TELEGRAM_API_BASE to the mock, once, and TELEGRAM_BOT_TOKEN to the dummy,
# once, and no other line of the file names either variable.
ci_sets_telegram_base_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_TELEGRAM_API_BASE')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_TELEGRAM_API_BASE: http://mock:8080')" -eq 1 ]
}
ci_sets_telegram_token_for_iris() {
  [ "$(code "$ci" | grep -c 'TELEGRAM_BOT_TOKEN')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token')" -eq 1 ]
}

# The dummy bot token matches neither key pattern of test-boundaries.sh that could apply to it (an Anthropic key and a bot token of
# Telegram's shape), so it can sit in a committed file.
ci_dummy_token_is_no_key() {
  local dummy
  dummy=$(code "$ci" | sed -n 's/^      TELEGRAM_BOT_TOKEN:[[:space:]]*//p')
  [ -n "$dummy" ] && ! printf '%s\n' "$dummy" | grep -qE 'sk-ant-[A-Za-z0-9_-]{8,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}'
}

# Only ci/compose.ci.yml sets the switch (owner decision 5): the file must exist and must not name it, so no surface that ships
# or that a developer starts without the CI override carries the mock-key header (the online demo never does).
mock_key_header_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_MOCK_KEY_HEADER' "$1"; }

# Only ci/compose.ci.yml sets the Bot API base and gives a bot token a value (Story 10.3): the file must exist, must not name the base and
# must not hold the dummy token. A judge's file may still name TELEGRAM_BOT_TOKEN, as an empty key to fill in (.env.example) or as a
# variable to read.
telegram_wiring_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_TELEGRAM_API_BASE' "$1" && ! grep -q 'ocutalon-ci-dummy-bot-token' "$1"; }

check "ci: the file is exactly the mock's wiring (project name, iris variables and log volume, mock service, log volume)" ci_file_is_exact
check "ci: the iris service sets OCUTALON_MOCK_KEY_HEADER to \"1\", once, and no other line names it" ci_sets_mock_key_header_for_iris
check "ci: the iris service sets OCUTALON_TELEGRAM_API_BASE to the mock, once, and no other line names it" ci_sets_telegram_base_for_iris
check "ci: the iris service sets TELEGRAM_BOT_TOKEN to the dummy, once, and no other line names it" ci_sets_telegram_token_for_iris
check "ci: the dummy bot token matches no key pattern" ci_dummy_token_is_no_key
for f in "$compose" "$dev" "$dockerfile" .env.example docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos \
  docker/tests/compose.throwaway.yml docker/tests/lib-live.sh; do
  check "judges: $f does not name OCUTALON_MOCK_KEY_HEADER (only ci/compose.ci.yml sets it)" mock_key_header_absent "$f"
  check "judges: $f names neither OCUTALON_TELEGRAM_API_BASE nor the dummy bot token (only ci/compose.ci.yml sets them)" telegram_wiring_absent "$f"
done
check "ci: top-level name ocutalon-ci" has_line "$ci" '^name:[[:space:]]*ocutalon-ci[[:space:]]*$'
check "ci: the services are iris, and mock if there is one" ci_services_are_known
check "ci: no ports, env_file, container_name, build, privileged, network_mode or extra_hosts" ci_adds_no_port_or_publishing_key
check "ci: no key variable anywhere, but the one dummy bot token" ci_adds_no_key_variable
check "ci: image appears once, in the mock block, as node:<x.y.z>-slim pinned by a sha256 digest" ci_image_is_the_pinned_node
check "ci: command appears only in the mock block" ci_command_only_in_mock
check "ci: config parses together with the judges' file (--quiet)" docker compose -f "$compose" -f "$ci" config --quiet
check "ci: config parses together with the judges' file and the throwaway override (--quiet)" \
  docker compose -f "$compose" -f docker/tests/compose.throwaway.yml -f "$ci" config --quiet
check "ci: config parses together with the judges' file and docker-compose.dev.yml (--quiet)" \
  docker compose -f "$compose" -f "$dev" -f "$ci" config --quiet

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

# --- the web bundle and the web sources ---

check "git: the built bundle src/ocutalon/csp/ is ignored" git_ignores src/ocutalon/csp/index.html
check "git: the copied brand images are ignored" git_ignores web/public/assets/brand/icon-192.png
check "git: the Playwright results are ignored" git_ignores web/test-results/x
check "git: the Playwright report is ignored" git_ignores web/playwright-report/index.html
check "git: node_modules is ignored" git_ignores web/node_modules/x
check "git: the lock file is not ignored" git_does_not_ignore web/package-lock.json
check "git: the generated token stylesheet is not ignored" git_does_not_ignore web/src/styles/tokens.css
check "git: the generated sign-in assets are not ignored" git_does_not_ignore src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls
check "git: the vendored fonts are not ignored" git_does_not_ignore web/public/assets/fonts/Inter-Regular.woff2

# web/ keeps LF in every checkout, and a binary is detected, not forced to text.
web_attributes() {
  local f
  for f in web/package.json web/angular.json web/src/main.ts web/scripts/tokens.mjs web/src/styles/tokens.css web/public/assets/fonts/Inter-Regular.woff2; do
    [ "$(git check-attr eol -- "$f" | sed 's/.*: //')" = lf ] || return 1
    [ "$(git check-attr text -- "$f" | sed 's/.*: //')" = auto ] || return 1
  done
}
check "gitattributes: web/ is text only when git detects text, with LF" web_attributes

if [ "$fails" -ne 0 ]; then
  echo "test-compose-file: $fails check(s) failed"
  exit 1
fi
echo "test-compose-file: all checks passed"
