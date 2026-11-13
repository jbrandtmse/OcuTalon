#!/usr/bin/env bash
# Scans the files of docker/, the root Dockerfile, the compose files, src/, the text sources of web/, the repository-root files of the image,
# install.sh (the install script, Story 10.1), .github/, ci/ and the release scripts (release/*.sh, Story 11.3) for the boundaries that no other test pins:
#   - ASCII only (the built page under src/ocutalon/csp/, which only a release candidate tracks, is not source and is left out of this rule alone);
#   - no image push, save or export, no registry sign-in and no --cache-to (CON-1, REL-4);
#   - `docker compose config` only with --quiet and `docker inspect` only with --format, because
#     both print the values that env_file passes in (AD-22);
#   - the test-only global ^OcuTalonTest appears nowhere in the product (outside the OcuTalon/Test classes and
#     docker/tests/) except in the one read of ^OcuTalonTest("TelegramIncluded") in Channel/Telegram/In.cls, so the
#     judges' install never has it set (AD-29, Story 0.4);
#   - Data.Session's ForEval and DropEval, the evaluation session rows, are called in the product only by Eval/In.cls (EvalIn) and named in
#     Data/Session.cls only where they are defined (AD-4, AD-33; the Contest Planner's condition (i) of Story 41.14).
# And in every file that git tracks or has not ignored (the pipeline's folders and the agent files included, a binary skipped,
# .env and .env.<x> other than .env.example never read), CON-5:
#   - no local machine path: a home or volume folder with a name below it, a /private/tmp, /private/var or /private/etc path,
#     a macOS per-user temporary folder (/var/folders/<x>, the form TMPDIR takes), or a Windows user folder with a name below it;
#   - no key-like string (the patterns are those of docker/tests/lib-keys.sh).
# Starts nothing. Each scanner first runs on a synthetic file that breaks its rule and on one that
# keeps it, so a scanner that can no longer flag anything fails. A failing scan prints file:line only,
# never the text of the line. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-scan.sh"
. "$root/docker/tests/lib-keys.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bd.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- scanners: print file:line for each offending line of the files given ---

non_ascii() { LC_ALL=C grep -nH '[^[:print:][:space:]]' "$@" | cut -d: -f1,2; }
# ascii_scope <files, one per line>: the files the ASCII rule reads. A release candidate's tree tracks the built page under src/ocutalon/csp/, with its
# images and fonts; the other rules still read it.
ascii_scope() { grep -v '^src/ocutalon/csp/' <<< "$1"; }

# key_like (the key-like patterns) comes from docker/tests/lib-keys.sh, the one definition that eval/run.sh also reads.

# Non-comment logical lines (a trailing backslash joins the next line).
risky_docker_calls() {
  awk '
    function check(line, where) {
      if (line ~ /^[[:space:]]*#/) return
      if (line ~ /docker[ ]+(push|login|logout)([ ]|$)/ || line ~ /docker[ ].*[ ]--push([ =]|$)/) print where
      if (line ~ /docker[ ]+(image[ ]+|container[ ]+)?(save|export)([ ]|$)/ || line ~ /docker[ ].*[ ]--cache-to([ =]|$)/) print where
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

# Product class text that names Data.Session's ForEval or DropEval outside Eval/In.cls, other than their own definition lines in Data/Session.cls. The OcuTalon/Test
# classes are the tests and are skipped, and so is a comment line; only class, routine and include files are read.
eval_session_callers() {
  awk '
    FILENAME !~ /\.(cls|mac|int|inc)$/ || FILENAME ~ /\/OcuTalon\/Test\// || FILENAME ~ /OcuTalon\/Eval\/In\.cls$/ { next }
    /^[ \t]*(\/\/|;|#;)/ { next }
    {
      line = $0
      if (FILENAME ~ /OcuTalon\/Data\/Session\.cls$/ && line ~ /^ClassMethod (ForEval|DropEval)\(/) next
      if (line ~ /(^|[^A-Za-z0-9_])(ForEval|DropEval)([^A-Za-z0-9_]|$)/) print FILENAME ":" FNR
    }
  ' "$@"
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

files=$(scan_files docker Dockerfile docker-compose.yml docker-compose.dev.yml .dockerignore .env.example .gitattributes install.sh src web .github ci 'release/*.sh' docs/security-overview.md | while IFS= read -r f; do
  if in_scope "$f"; then echo "$f"; fi
done)
all_files=$(scan_files)
if [ -z "$files" ] || [ -z "$all_files" ]; then
  echo "FAIL no files in scope"
  exit 1
fi

# The files that must be scanned by the rules of $files, and by the rules of $all_files.
scope_ok=1
for f in src/module.xml src/bridge/cls/OcuTalon/Bridge/Installer.cls src/ocutalon/cls/OcuTalon/Install/Registry.cls \
  docker-compose.dev.yml Dockerfile docker/after-start.sh docker/after-start.cos docker/ipm/zpm-0.10.10.xml docker/ipm/LICENSE docker/tests/lib-live.sh \
  web/package.json web/package-lock.json web/angular.json web/src/index.html web/src/app/app.ts web/src/styles/tokens.css web/src/signin/signin.css \
  web/scripts/tokens.mjs web/e2e/sign-in/helpers.ts web/src/signin/signin.js src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls \
  .github/workflows/ci.yml .github/workflows/lane-a.yml ci/iris.sh ci/compose.ci.yml install.sh \
  release/lib-release.sh release/rehearse.sh release/upgrade-harness.sh release/standalone-bridge.sh release/demo-host-check.sh release/demo-load.sh \
  docs/security-overview.md; do
  if ! grep -qxF -- "$f" <<< "$files"; then
    echo "  not scanned: $f"
    scope_ok=0
  fi
done
for f in README.md GUIDE.md CLAUDE.md _bmad/custom/skill-rules.md _bmad-output/implementation-artifacts/sprint-status.yaml \
  eval/orders-date-format/case.json eval/orders-date-format/snapshot.json; do
  if ! grep -qxF -- "$f" <<< "$all_files"; then
    echo "  not scanned for paths and keys: $f"
    scope_ok=0
  fi
done
if [ "$scope_ok" -eq 1 ]; then
  echo "PASS scope: src/, the text sources of web/, the dev compose file, the scripts, install.sh, .github/, ci/, release/*.sh, docs/security-overview.md and the IPM release are scanned; every tracked or new file is scanned for paths and keys, README.md and GUIDE.md among them"
else
  echo "FAIL scope: a file that must be scanned is not"
  fails=$((fails + 1))
fi

# --- synthetic samples, assembled so that this script does not contain what it flags ---

d="docker"
printf 'caf\303\251\n' > "$tmp/ascii.bad"
printf 'plain text\twith a tab\n' > "$tmp/ascii.good"
printf 'cd %s%s/someone/x\n' "/Us" "ers" > "$tmp/path.bad"
printf 'cd %s%s/Data/x\n' "/Volu" "mes" > "$tmp/path.bad2"
printf 'cd %s%s/var/folders/x\n' "/priv" "ate" > "$tmp/path.bad3"
printf 'cd C:%s%s\\someone\\x\n' '\' "Users" > "$tmp/path.bad4"
printf 'cd %s%s/someone/x\n' "/ho" "me" > "$tmp/path.bad5"
printf 'TMPDIR=%s%s/ab/cd1234/T/\n' "/var/fol" "ders" > "$tmp/path.bad6"
{
  printf 'cd /durable/iris and /home/irisowner\n'
  printf 'a generic home folder is %s%s/<name>/ or %s%s/ alone\n' "/Us" "ers" "/Volu" "mes"
  printf 'a Windows user folder is C:%s%s\\<name>\\\n' '\' "Users"
} > "$tmp/path.good"
printf 'k=%s%s\n' "sk-ant-" "aaaaaaaaaaaaaaaa" > "$tmp/key.bad"
printf 'ANTHROPIC_API_KEY=\nsk-ant- is a prefix, so are github_pat_ and dop_v1_\n%s %s\n' 123456789 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > "$tmp/key.good"
printf 't=%s%s%s\n' 123456789 ":" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > "$tmp/key2.bad"
printf 'k=%s%s\n' "github_pat_" "AAAAAAAAAAAAAAAAAAAAAAAA" > "$tmp/key3.bad"
printf 'k=%s%s\n' "dop_v1_" "0123456789abcdef0123456789abcdef" > "$tmp/key4.bad"
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
printf '%s save -o x.tar registry.example/x\n' "$d" > "$tmp/docker.bad12"
printf '%s export abc > x.tar\n' "$d" > "$tmp/docker.bad13"
printf '%s buildx build --cache-to type=local,dest=x .\n' "$d" > "$tmp/docker.bad14"
printf '%s image save registry.example/x\n' "$d" > "$tmp/docker.bad15"
printf '%s container export abc\n' "$d" > "$tmp/docker.bad16"
{
  printf '# %s push is only a comment\n' "$d"
  printf '%s inspect --format x abc\n' "$d"
  printf '%s compose -f f.yml config --quiet\n' "$d"
  printf '%s exec -T iris sh -c "export X=1"\n' "$d"
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

mkdir -p "$tmp/es/OcuTalon/Core" "$tmp/es/OcuTalon/Data" "$tmp/es/OcuTalon/Eval" "$tmp/es/good/OcuTalon/Data"
printf 'ClassMethod Run()\n{\n\tSet row = ##class(OcuTalon.Data.Session).ForEval(.sc)\n}\n' > "$tmp/es/OcuTalon/Core/Bad1.cls"
printf 'ClassMethod Run()\n{\n\tQuit ##class(OcuTalon.Data.Session).DropEval(ref)\n}\n' > "$tmp/es/OcuTalon/Core/Bad2.cls"
printf 'ClassMethod Run()\n{\n\tQuit $ClassMethod("OcuTalon.Data.Session", "ForEval")\n}\n' > "$tmp/es/OcuTalon/Core/Bad3.cls"
printf 'ClassMethod ForEval(Output sc As %%Status) As OcuTalon.Data.Session\n{\n\tQuit ..DropEval(ref)\n}\n' > "$tmp/es/OcuTalon/Data/Session.cls"
printf 'ClassMethod Run()\n{\n\tSet row = ##class(OcuTalon.Data.Session).ForEval(.sc)\n\tQuit ##class(OcuTalon.Data.Session).DropEval(row.Ref)\n}\n' > "$tmp/es/OcuTalon/Eval/In.cls"
printf '/// Data.Session.ForEval makes the row.\nClassMethod ForEval(Output sc As %%Status) As OcuTalon.Data.Session\n{\n\tQuit ""\n}\nClassMethod DropEval(ref As %%String) As %%Status\n{\n\tQuit $$$OK\n}\n' > "$tmp/es/good/OcuTalon/Data/Session.cls"

scan_rule "ascii: only printable ASCII, spaces and tabs" non_ascii "$tmp/ascii.bad" "$tmp/ascii.good" "$(ascii_scope "$files")"

# The built page is left out of the ASCII rule, and nothing beside it is. The files are made here, because only a candidate's tree holds the page.
ac="$tmp/ascii-scope"
mkdir -p "$ac/src/ocutalon/csp/media" "$ac/src/ocutalon/cspx" "$ac/src/ocutalon/cls"
printf '\211PNG\r\n\032\n' > "$ac/src/ocutalon/csp/media/logo.png"
printf 'caf\303\251\n' > "$ac/src/ocutalon/csp/main.js"
printf 'caf\303\251\n' > "$ac/src/ocutalon/cspx/near.txt"
printf 'caf\303\251\n' > "$ac/src/ocutalon/cls/Bad.cls"
printf 'plain\n' > "$ac/src/ocutalon/cls/Good.cls"
ascii_scan() { (cd "$ac" && fails=0; scan_rule "scope" non_ascii "$tmp/ascii.bad" "$tmp/ascii.good" "$(ascii_scope "$(printf '%s\n' src/ocutalon/csp/main.js src/ocutalon/csp/media/logo.png src/ocutalon/cls/Good.cls "$@")")" > /dev/null; echo "$fails"); }
got="$(ascii_scan)/$(ascii_scan src/ocutalon/cls/Bad.cls)/$(ascii_scan src/ocutalon/cspx/near.txt)"
if [ "$got" = "0/1/1" ]; then
  echo "PASS ascii scope: the built page passes, text and binary alike, and a non-ASCII file anywhere else under src/ still fails"
else
  echo "FAIL ascii scope: wanted 0/1/1 (the page alone, a class, a folder with a like name), got $got"
  fails=$((fails + 1))
fi

# The path scanner has more than one bad shape: a home folder, a volume, a private folder, a Windows user folder, a Linux home and a
# macOS per-user temporary folder.
paths_ok=1
for n in 2 3 4 5 6; do
  if [ -z "$(local_path "$tmp/path.bad$n")" ]; then
    echo "FAIL paths: the scanner does not flag sample $n"
    fails=$((fails + 1))
    paths_ok=0
  fi
done
if [ "$paths_ok" -eq 1 ]; then
  scan_rule "paths: no local machine path (a name below a home or volume folder, /private/tmp, a Windows user folder)" local_path "$tmp/path.bad" "$tmp/path.good" "$all_files"
fi
scan_rule "keys: nothing key-like" key_like "$tmp/key.bad" "$tmp/key.good" "$all_files"

# The other key shapes are separate alternatives of the same scanner: a bot token, a fine-grained GitHub token and a DigitalOcean token.
keys_ok=1
for n in 2 3 4; do
  if [ -z "$(key_like "$tmp/key$n.bad")" ]; then
    echo "FAIL keys: the scanner does not flag sample $n"
    fails=$((fails + 1))
    keys_ok=0
  fi
done
if [ "$keys_ok" -eq 1 ]; then
  echo "PASS keys: the bot-token, GitHub token and DigitalOcean token shapes are flagged"
fi

# scan_files lists every file that git tracks or has not ignored, a file with a non-ASCII name included, and never an .env file
# other than .env.example. The files are made here, so that the result does not depend on what this repository holds.
sf="$tmp/scan-files"
git init -q "$sf"
for n in a.txt .env .env.local .env.example "caf$(printf '\303\251').txt"; do printf 'x\n' > "$sf/$n"; done
listed=$(cd "$sf" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$tmp/xdg" scan_files | LC_ALL=C sort | tr '\n' ' ')
if [ "$listed" = ".env.example a.txt caf$(printf '\303\251').txt " ]; then
  echo "PASS scan_files: a file with a non-ASCII name is listed, and .env and .env.local are not"
else
  echo "FAIL scan_files: the list is wrong (${listed:-empty})"
  fails=$((fails + 1))
fi

# scan_rule hands a file whose name holds a space or a glob character to the scanner as one file, so its lines are scanned.
mkdir -p "$tmp/spaced"
printf 'k=%s%s\n' "sk-ant-" "aaaaaaaaaaaaaaaa" > "$tmp/spaced/a key [1].txt"
spaced=$(fails=0; scan_rule "spaced" key_like "$tmp/key.bad" "$tmp/key.good" "$tmp/spaced/a key [1].txt"; echo "FAILS=$fails")
if printf '%s\n' "$spaced" | grep -q 'a key \[1\]\.txt:1' && printf '%s\n' "$spaced" | grep -qx 'FAILS=1'; then
  echo "PASS scan_rule: a file whose name holds a space or a glob character is scanned"
else
  echo "FAIL scan_rule: a file whose name holds a space or a glob character is not scanned"
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
    test_global "$tmp/testglobal.bad1" "$tmp/OcuTalon/Channel/Telegram/In.cls" "$files"
fi

evalsession_ok=1
for bad in Core/Bad1.cls Core/Bad2.cls Core/Bad3.cls Data/Session.cls; do
  if [ -z "$(eval_session_callers "$tmp/es/OcuTalon/$bad")" ]; then
    echo "FAIL evaluation sessions: the scanner does not flag $bad"
    fails=$((fails + 1))
    evalsession_ok=0
  fi
done
if [ -n "$(eval_session_callers "$tmp/es/OcuTalon/Eval/In.cls")" ]; then
  echo "FAIL evaluation sessions: the scanner flags Eval/In.cls"
  fails=$((fails + 1))
  evalsession_ok=0
fi
if [ "$evalsession_ok" -eq 1 ]; then
  scan_rule "evaluation sessions: Data.Session.ForEval and DropEval are called only by Eval/In.cls" \
    eval_session_callers "$tmp/es/OcuTalon/Core/Bad1.cls" "$tmp/es/good/OcuTalon/Data/Session.cls" "$files"
fi

controls_ok=1
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  if [ -z "$(risky_docker_calls "$tmp/docker.bad$n")" ]; then
    echo "FAIL docker calls: the scanner does not flag sample $n"
    fails=$((fails + 1))
    controls_ok=0
  fi
done
if [ "$controls_ok" -eq 1 ]; then
  scan_rule "docker calls: no push, save, export or sign-in, no --cache-to, config only with --quiet, inspect only with --format" \
    risky_docker_calls "$tmp/docker.bad1" "$tmp/docker.good" "$files"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-boundaries: $fails rule(s) failed"
  exit 1
fi
echo "test-boundaries: all rules passed"
