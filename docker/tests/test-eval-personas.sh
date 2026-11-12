#!/usr/bin/env bash
# The repository check of the persona sweep's script forms (Story 40.7; AD-19, AD-22). It is a unit of the hosted `checks` job (CHECK_SCRIPTS of
# ci/units.sh), starts nothing, and needs bash and python3. eval/run.sh runs with a stub in place of the container tool that records its calls and fails, in a
# folder of its own, so a form that the script accepts goes on to the preflight, calls the stub and ends with exit 1, and a form that it refuses ends
# with exit 2 before any call. The key is a value that is not a key; it must never appear in a call, in the output or in a file.
#   forms      --personas (with a key in the caller's environment and without one), --release-candidate --personas (with a key) and (Story 0.27)
#              --rules-only, --rules-only main and --rules-only held-out (with a key in the caller's environment and without one: the key is dropped) go on to the tool;
#   key        --release-candidate --personas with the key unset or empty exits 2 and names ANTHROPIC_API_KEY, and calls nothing;
#   refused    --personas extra, --on-mock --personas, --personas --release-candidate and --release-candidate --on-mock --personas exit 2 with a
#              usage line and no call, and so do --rules-only --personas, --rules-only --release-candidate, --rules-only other, --personas --rules-only,
#              --release-candidate --rules-only and --rules-only main held-out;
#   print      the sweep block prints personas.md only after it has checked the file for key-like text and for the key's value (key_like and
#              key_value_hits), as the release candidate's result is;
#   cases      the files of eval/persona-cases/ hold no [[mock: marker and are printable ASCII (the other rules of a case are test-eval-set's).
# Each rule first runs on copy trees of the real script with one edit each (a form accepted that must be refused, the key kept for --personas, the key
# check dropped for --release-candidate --personas, the key printed, a call before the guard, personas.md printed unchecked; for --rules-only: the form missing,
# any word accepted after it, --personas accepted after it, the key kept), which it must flag; only then
# does it read the real tree.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
pass() { echo "PASS $*"; }
fail() {
  echo "FAIL $*"
  fails=$((fails + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ep.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

fake="zz-not-a-key-$RANDOM$RANDOM"
calls="$tmp/stub.calls"
mkdir -p "$tmp/stub"
tool=doc
tool=${tool}ker
printf '#!/bin/sh\necho "$*" >> "%s"\nprintf "%%s" "${ANTHROPIC_API_KEY:-}" >> "%s"\nexit 1\n' "$calls" "$tmp/stub.env" > "$tmp/stub/$tool"
chmod +x "$tmp/stub/$tool"

# run_form <tree> <key: unset|empty|fake> <argument>...: the exit status of the tree's eval/run.sh; its output is in $tmp/out.log, its calls in $calls.
run_form() {
  local tree=$1 key=$2 rc=0 dir="$tmp/run"
  shift 2
  rm -rf "$dir"
  mkdir -p "$dir"
  : > "$calls"
  : > "$tmp/stub.env"
  case $key in
    unset) (cd "$dir" && env -u RUNNER_TEMP -u ANTHROPIC_API_KEY OCUTALON_LOCK_DIR="$dir/no-locks" PATH="$tmp/stub:$PATH" TMPDIR="$dir" OCUTALON_RUN_TAG=eval-guard-check bash "$tree/eval/run.sh" "$@" > "$tmp/out.log" 2>&1) || rc=$? ;;
    empty) (cd "$dir" && env -u RUNNER_TEMP ANTHROPIC_API_KEY= OCUTALON_LOCK_DIR="$dir/no-locks" PATH="$tmp/stub:$PATH" TMPDIR="$dir" OCUTALON_RUN_TAG=eval-guard-check bash "$tree/eval/run.sh" "$@" > "$tmp/out.log" 2>&1) || rc=$? ;;
    *) (cd "$dir" && env -u RUNNER_TEMP ANTHROPIC_API_KEY="$fake" OCUTALON_LOCK_DIR="$dir/no-locks" PATH="$tmp/stub:$PATH" TMPDIR="$dir" OCUTALON_RUN_TAG=eval-guard-check bash "$tree/eval/run.sh" "$@" > "$tmp/out.log" 2>&1) || rc=$? ;;
  esac
  echo "$rc"
}

# check_forms <tree>: the violations of the tree's eval/run.sh, one line each.
check_forms() {
  local tree=$1 rc key args
  if [ ! -f "$tree/eval/run.sh" ]; then
    echo "eval/run.sh: the script is missing"
    return 0
  fi
  for args in '--personas:unset' '--personas:fake' '--release-candidate --personas:fake' '--rules-only:unset' '--rules-only:fake' '--rules-only main:fake' '--rules-only held-out:unset' '--rules-only held-out:fake'; do
    key=${args##*:}
    # shellcheck disable=SC2086
    rc=$(run_form "$tree" "$key" ${args%:*})
    if [ "$rc" -ne 1 ] || [ ! -s "$calls" ]; then
      echo "eval/run.sh: '${args%:*}' (key $key) does not go on to the container tool (exit $rc)"
    elif grep -qF -- "$fake" "$tmp/out.log" "$calls" || grep -rqF --exclude=out.log -- "$fake" "$tmp/run"; then
      echo "eval/run.sh: the key appears in the output, in a call or in a file of '${args%:*}'"
    elif { [ "${args%:*}" = --personas ] || [ "${args%% *}" = --rules-only ]; } && [ -s "$tmp/stub.env" ]; then
      echo "eval/run.sh: '${args%:*}' (key $key) leaves the key in the environment of the container tool"
    fi
  done
  for key in unset empty; do
    rc=$(run_form "$tree" "$key" --release-candidate --personas)
    if [ "$rc" -ne 2 ]; then
      echo "eval/run.sh: --release-candidate --personas with the key $key is not refused with exit 2 (exit $rc)"
    elif [ -s "$calls" ]; then
      echo "eval/run.sh: --release-candidate --personas with the key $key reached the container tool before it was refused"
    elif ! grep -q 'ANTHROPIC_API_KEY' "$tmp/out.log"; then
      echo "eval/run.sh: the refusal of --release-candidate --personas with the key $key does not name ANTHROPIC_API_KEY"
    fi
  done
  for args in '--personas extra' '--on-mock --personas' '--personas --release-candidate' '--release-candidate --on-mock --personas' \
    '--rules-only --personas' '--rules-only --release-candidate' '--rules-only other' '--personas --rules-only' '--release-candidate --rules-only' '--rules-only main held-out'; do
    # shellcheck disable=SC2086
    rc=$(run_form "$tree" fake $args)
    if [ "$rc" -ne 2 ]; then
      echo "eval/run.sh: the arguments '$args' are not refused with exit 2 (exit $rc)"
    elif [ -s "$calls" ]; then
      echo "eval/run.sh: the arguments '$args' reached the container tool before they were refused"
    elif ! grep -q '^usage: ' "$tmp/out.log"; then
      echo "eval/run.sh: the refusal of the arguments '$args' prints no usage line"
    elif grep -qF -- "$fake" "$tmp/out.log"; then
      echo "eval/run.sh: the key appears in the output of the refused arguments '$args'"
    fi
  done
  sed -n '/^# --- the persona sweep/,/^# --- the release-candidate run ---/p' "$tree/eval/run.sh" | awk '
    /key_like "\$report_dir\/\$name\.md"/ { k = 1 }
    /key_value_hits "\$report_dir\/\$name\.md"/ { v = 1 }
    /^ *cat "\$report_dir\/\$name\.md"$/ { n++; if (!(k && v)) bad = 1 }
    END { if (!n || bad) print "eval/run.sh: the persona sweep prints personas.md without checking it for key-like text and the key first" }'
}

# sample <name> <python expression on s>: a copy tree of the real script with one edit; the tree's other folders are the real ones.
sample() {
  local dir="$tmp/sample-$1" edit=$2
  rm -rf "$dir"
  mkdir -p "$dir/eval"
  for d in ci docker src web release; do
    [ -e "$root/$d" ] && ln -s "$root/$d" "$dir/$d"
  done
  python3 - "$root/eval/run.sh" "$dir/eval/run.sh" "$edit" << 'EOF' || return 1
import sys
source, target, edit = sys.argv[1:4]
s = open(source).read()
t = eval(edit)
if t == s:
    sys.exit('the edit changed nothing: ' + edit)
open(target, 'w').write(t)
EOF
  echo "$dir"
}

# flagged <name> <python expression>: PASS when the sample's script is flagged.
flagged() {
  local dir found
  dir=$(sample "$1" "$2") || {
    fail "forms sample $1: $dir"
    return
  }
  found=$(check_forms "$dir")
  if [ -n "$found" ]; then pass "forms sample $1: flagged"; else fail "forms sample $1: not flagged"; fi
}

flagged accepts-extra "s.replace('[ \$# -eq 1 ] && [ \"\$1\" = --personas ]', '[ \$# -ge 1 ] && [ \"\$1\" = --personas ]')"
flagged accepts-on-mock "s.replace('[ \"\$1\" = --release-candidate ] && [ \"\$2\" = --personas ]', '[ \"\$2\" = --personas ]')"
flagged key-kept "s.replace('if [ \"\$keypath\" -eq 0 ] && {', 'if [ \"\$keypath\" -eq 0 ] && [ \"\$personas\" -eq 0 ] && {')"
flagged key-not-needed "s.replace('if [ \"\$mode\" = rc ] && { [ \"\$onmock\" -eq 0 ] || [ \"\$keypath\" -eq 1 ]; } && [ -z', 'if [ \"\$mode\" = rc ] && [ \"\$personas\" -eq 0 ] && { [ \"\$onmock\" -eq 0 ] || [ \"\$keypath\" -eq 1 ]; } && [ -z')"
flagged rules-only-missing "s.replace('elif [ \$# -eq 1 ] && [ \"\$1\" = --rules-only ]; then\n  mode=rulesonly\n', '')"
flagged rules-only-accepts-other "s.replace('{ [ \"\$2\" = main ] || [ \"\$2\" = held-out ]; }', 'true')"
flagged rules-only-accepts-personas "s.replace('[ \"\$2\" = main ] || [ \"\$2\" = held-out ]', '[ \"\$2\" = main ] || [ \"\$2\" = held-out ] || [ \"\$2\" = --personas ]')"
flagged rules-only-key-kept "s.replace('if [ \"\$keypath\" -eq 0 ] && {', 'if [ \"\$keypath\" -eq 0 ] && [ \"\$mode\" != rulesonly ] && {')"
flagged prints-key "s.replace('. \"\$root/docker/tests/lib-keys.sh\"\n', '. \"\$root/docker/tests/lib-keys.sh\"\necho \"key \${ANTHROPIC_API_KEY:-}\"\n', 1)"
flagged calls-before-guard "s.replace('set -u\n\nroot=', 'set -u\n$tool version > /dev/null 2>&1\n\nroot=', 1)"
flagged prints-unchecked "s.replace('      if [ -n \"\$(key_like \"\$report_dir/\$name.md\")\" ]; then', '      if false; then', 1)"

found=$(check_forms "$root")
if [ -z "$found" ]; then
  pass "forms: eval/run.sh goes on with --personas, --release-candidate --personas and --rules-only (alone, main or held-out), refuses the other forms and a missing key, never shows the key or leaves it in the environment of the container tool, and checks personas.md before it prints it"
else
  fail "forms: $found"
fi

# the cases: no mock marker and printable ASCII
bad=
for file in "$root"/eval/persona-cases/*/case.json; do
  [ -f "$file" ] || continue
  if grep -q '\[\[mock:' "$file"; then bad="$bad ${file#"$root"/}(marker)"; fi
  if LC_ALL=C grep -q '[^ -~]' "$file"; then bad="$bad ${file#"$root"/}(non-ASCII)"; fi
done
count=$(ls -d "$root"/eval/persona-cases/*/ 2> /dev/null | wc -l | tr -d ' ')
if [ -z "$bad" ] && [ "$count" -ge 1 ]; then
  pass "cases: the $count file(s) of eval/persona-cases/ hold no mock marker and are ASCII"
else
  fail "cases: $count case folder(s);$bad"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-eval-personas: $fails rule(s) failed"
  exit 1
fi
echo "test-eval-personas: all rules passed"
