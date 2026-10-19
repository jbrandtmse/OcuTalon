#!/usr/bin/env bash
# Scans the files of docker/, the compose files, src/, the text sources of web/ and the repository-root files of
# the image for the boundaries that no other test pins:
#   - ASCII only;
#   - no local machine path and no key-like string in a tracked file;
#   - no image push and no registry sign-in;
#   - `docker compose config` only with --quiet and `docker inspect` only with --format, because
#     both print the values that env_file passes in (AD-22);
#   - the test-only global ^OcuTalonTest appears nowhere in the product (outside the OcuTalon/Test classes and
#     docker/tests/) except in the one read of ^OcuTalonTest("TelegramIncluded") in Channel/Telegram/In.cls, so the
#     judges' install never has it set (AD-29, Story 0.4).
# Starts nothing. Each scanner first runs on a synthetic file that breaks its rule and on one that
# keeps it, so a scanner that can no longer flag anything fails. A failing scan prints file:line only,
# never the text of the line. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bd.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- scanners: print file:line for each offending line of the files given ---

non_ascii() { LC_ALL=C grep -nH '[^[:print:][:space:]]' "$@" | cut -d: -f1,2; }

local_path() {
  { grep -nHE '/Use[r]s/|/Volume[s]/|/privat[e]/|[A-Za-z]:\\(Use[r]s|Windows)' "$@"
    grep -nHE '/hom[e]/[A-Za-z]' "$@" | grep -v '/home/irisowner'
  } | cut -d: -f1,2
}

key_like() {
  grep -nHE -e 'sk-ant-[A-Za-z0-9_-]{8,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' "$@" | cut -d: -f1,2
}

# Non-comment logical lines (a trailing backslash joins the next line).
risky_docker_calls() {
  awk '
    function check(line, where) {
      if (line ~ /^[[:space:]]*#/) return
      if (line ~ /docker[ ]+(push|login|logout)([ ]|$)/ || line ~ /docker[ ].*[ ]--push([ =]|$)/) print where
      if (line ~ /(docker([ ]+(image|compose)|-compose)|(^|[ ;|&(])dc)[ ]+([^ ]+[ ]+)*push([ ]|$)/) print where
      if (line ~ /docker[ ]+(image[ ]+|container[ ]+)?inspect/) {
        rest = line; sub(/.*inspect/, "", rest)
        if (rest !~ /(^|[ ])(--format|-f)([ =]|$)/ || rest ~ /\{\{[ ]*json[ ]+\.[ ]*\}\}|\.Config\.Env/) print where
      }
      if (line ~ /(docker[ ]+compose|docker-compose|(^|[ ;|&(])dc)([ ].*)?[ ](config|convert)([ ]|$)/) {
        rest = line; sub(/.*[ ](config|convert)/, "", rest)
        if (rest !~ /(^|[ ])(--quiet|-q)([ ]|$)/) print where
      }
    }
    { cur = cur $0
      if (cur ~ /\\$/) { sub(/\\$/, " ", cur); next }
      check(cur, FILENAME ":" FNR); cur = "" }
  ' "$@"
}

# Product text that mentions the test-only global ^OcuTalonTest, other than the one allowed read in
# OcuTalon/Channel/Telegram/In.cls. The OcuTalon/Test classes and the scripts of docker/tests/ are the tests and are
# skipped, and so is a comment line; a preprocessor line such as #define is not a comment and is scanned.
test_global() {
  awk '
    FILENAME ~ /^src\/.*\/OcuTalon\/Test\// || FILENAME ~ /^docker\/tests\// { next }
    /^[ \t]*(\/\/|;|#([^A-Za-z]|$))/ { next }
    {
      line = $0
      if (FILENAME ~ /OcuTalon\/Channel\/Telegram\/In\.cls$/) gsub(/\$Get\(\^OcuTalonTest\("TelegramIncluded"\)\)/, "", line)
      if (line ~ /OcuTalonTest/) print FILENAME ":" FNR
    }
  ' "$@"
}

# scan_rule <label> <scanner> <rule's bad sample file> <rule's good sample file>
scan_rule() {
  local label=$1 scanner=$2 bad=$3 good=$4 hits
  if [ -z "$("$scanner" "$bad")" ]; then
    echo "FAIL $label: the scanner does not flag a line that breaks the rule"
    fails=$((fails + 1))
    return
  fi
  if [ -n "$("$scanner" "$good")" ]; then
    echo "FAIL $label: the scanner flags a line that keeps the rule"
    fails=$((fails + 1))
    return
  fi
  hits=$("$scanner" $files)
  if [ -n "$hits" ]; then
    echo "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL $label"
    fails=$((fails + 1))
  else
    echo "PASS $label"
  fi
}

# --- the files in scope: tracked or not yet ignored, so that a new file is scanned before it is committed ---

# From web/ only the text sources: the vendored fonts, images and licence texts are not scanned.
in_scope() {
  case $1 in
    web/*)
      case $1 in
        *.ts | *.js | *.html | *.css | *.mjs | *.json) return 0 ;;
      esac
      return 1
      ;;
  esac
  return 0
}

files=$(git ls-files -co --exclude-standard -- docker docker-compose.yml docker-compose.dev.yml .dockerignore .env.example .gitattributes src web | while IFS= read -r f; do
  if [ -f "$f" ] && in_scope "$f"; then echo "$f"; fi
done)
if [ -z "$files" ]; then
  echo "FAIL no files in scope"
  exit 1
fi

# All of src/, the dev compose file, the scripts and the pinned IPM release are in scope.
scope_ok=1
for f in src/module.xml src/bridge/cls/OcuTalon/Bridge/Installer.cls src/ocutalon/cls/OcuTalon/Install/Registry.cls \
  docker-compose.dev.yml docker/after-start.sh docker/after-start.cos docker/ipm/zpm-0.10.10.xml docker/ipm/LICENSE docker/tests/lib-live.sh \
  web/package.json web/package-lock.json web/angular.json web/src/index.html web/src/app/app.ts web/src/styles/tokens.css web/src/signin/signin.css \
  web/scripts/tokens.mjs web/e2e/sign-in/helpers.ts web/src/signin/signin.js src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls; do
  if ! printf '%s\n' "$files" | grep -qx -- "$f"; then
    echo "  not scanned: $f"
    scope_ok=0
  fi
done
if [ "$scope_ok" -eq 1 ]; then
  echo "PASS scope: src/, the text sources of web/, the dev compose file, the scripts and the IPM release are scanned"
else
  echo "FAIL scope: a file that must be scanned is not"
  fails=$((fails + 1))
fi

# --- synthetic samples, assembled so that this script does not contain what it flags ---

d="docker"
printf 'caf\303\251\n' > "$tmp/ascii.bad"
printf 'plain text\twith a tab\n' > "$tmp/ascii.good"
printf 'cd %s%s/someone/x\n' "/Us" "ers" > "$tmp/path.bad"
printf 'cd /durable/iris and /home/irisowner\n' > "$tmp/path.good"
printf 'k=%s%s\n' "sk-ant-" "aaaaaaaaaaaaaaaa" > "$tmp/key.bad"
printf 'ANTHROPIC_API_KEY=\nsk-ant- is a prefix\n%s %s\n' 123456789 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > "$tmp/key.good"
printf 't=%s%s%s\n' 123456789 ":" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > "$tmp/key2.bad"
printf '%s push registry.example/x\n' "$d" > "$tmp/docker.bad1"
printf '%s login\n' "$d" > "$tmp/docker.bad2"
printf '%s inspect abc\n' "$d" > "$tmp/docker.bad3"
printf '%s compose -p x -f f.yml config\n' "$d" > "$tmp/docker.bad4"
printf 'dc config\n' > "$tmp/docker.bad5"
printf '%s \\\n  inspect abc\n' "$d" > "$tmp/docker.bad6"
printf '%s compose -p x -f f.yml push\n' "$d" > "$tmp/docker.bad7"
printf '%s buildx build --push -t x .\n' "$d" > "$tmp/docker.bad8"
printf 'x; dc push\n' > "$tmp/docker.bad9"
printf '%s inspect --format "{{.Config.Env}}" abc\n' "$d" > "$tmp/docker.bad10"
printf '%s compose convert\n' "$d" > "$tmp/docker.bad11"
{
  printf '# %s push is only a comment\n' "$d"
  printf '%s inspect --format x abc\n' "$d"
  printf '%s compose -f f.yml config --quiet\n' "$d"
  printf 'dc up -d\n'
} > "$tmp/docker.good"

printf 'ClassMethod Enable()\n{\n\tSet ^OcuTalonTest("TelegramIncluded") = 1\n}\n' > "$tmp/testglobal.bad1"
printf 'ClassMethod Included()\n{\n\tQuit $Get(^OcuTalonTest("TelegramIncluded")) = 1\n\tSet ^OcuTalonTest("TelegramIncluded") = $Get(^OcuTalonTest("TelegramIncluded"))\n}\n' > "$tmp/testglobal.bad2"
printf 'Set g = "^OcuTalonTest"\n' > "$tmp/testglobal.bad3"
printf 'Kill ^OcuTalonTest\n' > "$tmp/testglobal.bad4"
printf 'ClassMethod Run()\n{\n\tIf $Get(^OcuTalonTest("TelegramIncluded")) Quit 1\n}\n' > "$tmp/testglobal.bad5"
printf '#define TgOn Set ^OcuTalonTest("TelegramIncluded") = 1\n' > "$tmp/testglobal.bad6"
mkdir -p "$tmp/OcuTalon/Channel/Telegram"
{
  printf '/// The test-only global ^OcuTalonTest("TelegramIncluded") is set by the tests.\n'
  printf '# ^OcuTalonTest is not set here\n'
  printf '#; ^OcuTalonTest is not set here either\n'
  printf 'ClassMethod Included() As %%Boolean\n{\n\tQuit $Get(^OcuTalonTest("TelegramIncluded")) = 1\n}\n'
  printf 'Set ^OcuTalonP.Setting = 1\n'
} > "$tmp/OcuTalon/Channel/Telegram/In.cls"

scan_rule "ascii: only printable ASCII, spaces and tabs" non_ascii "$tmp/ascii.bad" "$tmp/ascii.good"
scan_rule "paths: no local machine path" local_path "$tmp/path.bad" "$tmp/path.good"
scan_rule "keys: nothing key-like" key_like "$tmp/key.bad" "$tmp/key.good"

# The second key shape is a separate alternative of the same scanner.
if [ -n "$(key_like "$tmp/key2.bad")" ]; then
  echo "PASS keys: the bot-token shape is flagged"
else
  echo "FAIL keys: the bot-token shape is not flagged"
  fails=$((fails + 1))
fi

# The scanner has more than one bad shape: a write, a write that hides behind the allowed read, a mention in a string,
# a kill of the whole global, the allowed read outside Channel/Telegram/In.cls, and a write in a #define.
testglobal_ok=1
for n in 1 2 3 4 5 6; do
  if [ -z "$(test_global "$tmp/testglobal.bad$n")" ]; then
    echo "FAIL test global: the scanner does not flag sample $n"
    fails=$((fails + 1))
    testglobal_ok=0
  fi
done
if [ "$testglobal_ok" -eq 1 ]; then
  scan_rule "test global: ^OcuTalonTest is read only in Channel/Telegram/In.cls and set only by the tests" \
    test_global "$tmp/testglobal.bad1" "$tmp/OcuTalon/Channel/Telegram/In.cls"
fi

controls_ok=1
for n in 1 2 3 4 5 6 7 8 9 10 11; do
  if [ -z "$(risky_docker_calls "$tmp/docker.bad$n")" ]; then
    echo "FAIL docker calls: the scanner does not flag sample $n"
    fails=$((fails + 1))
    controls_ok=0
  fi
done
if [ "$controls_ok" -eq 1 ]; then
  scan_rule "docker calls: no push or sign-in, config only with --quiet, inspect only with --format" \
    risky_docker_calls "$tmp/docker.bad1" "$tmp/docker.good"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-boundaries: $fails rule(s) failed"
  exit 1
fi
echo "test-boundaries: all rules passed"
