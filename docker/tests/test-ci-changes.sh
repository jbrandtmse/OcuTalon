#!/usr/bin/env bash
# Hermetic test of ci/changes.sh (Story 0.7, matrix rows 9 to 12): the classifier and the comparison base that decide
# which jobs skip their steps. It runs the script on synthetic repositories with fake answers of the runs API
# (OCUTALON_CI_RUNS_FILE) and with a file of changed paths (--paths-from); it starts nothing and reaches no network.
#   - row 9, the classifier: web is true for each web input and false for other paths; iris is true unless every path is
#     under _bmad/ or under _bmad-output/ outside planning-artifacts/ux-designs/, so a change to DESIGN.md runs both;
#   - row 10, the base: the first commit of the history with a green push run (HEAD itself on a re-run of a green run); no
#     base, and both flags true, on a pull request, with no run, with no green run in the history, with a run that is not a
#     push, and when the answer cannot be read or holds no run list;
#   - row 11, red and then bookkeeping: C0 green, C1 code and red, B1 bookkeeping only: B1's base is C0, so B1 runs;
#   - a push to main (Story 0.8, REL-2): no base, web and iris true and a reason that names main, although a green base and only
#     bookkeeping changed; every call of the script sets GITHUB_REF itself, so the ref of the job that runs this test never leaks in;
#   - row 12, a skipped job: web and iris are false, the reason names the base, and the four outputs are also appended to
#     $GITHUB_OUTPUT; an output file that cannot be written fails the script.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
changes="$root/ci/changes.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cc.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

repo="$tmp/repo"
git init -q "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# commit <message> <path>...: changes each path and commits; sets $sha.
n=0
commit() {
  local message=$1 path
  shift
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    n=$((n + 1))
    echo "change $n" >> "$repo/$path"
    g add -A
  done
  g commit -q -m "$message"
  sha=$(g rev-parse HEAD)
}

# runs <file> <conclusion:sha[:event]>...: a runs API answer.
runs() {
  local file=$1
  shift
  jq -n --args '{workflow_runs: [$ARGS.positional[] | split(":") | {conclusion: .[0], head_sha: .[1], event: (.[2] // "push")}]}' "$@" > "$file"
}

# The ref of the push that classify simulates: a feature branch, so that no case depends on the environment's GITHUB_REF.
classify_ref=refs/heads/OCT-epic0

# classify <runs file or -> <event> [extra arguments]: runs the script in the repository; the four outputs are in out_*.
classify() {
  local runs_file=$1 event=$2
  shift 2
  : > "$tmp/github-output"
  (
    cd "$repo" || exit 1
    GITHUB_EVENT_NAME=$event GITHUB_REF=$classify_ref GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$tmp/github-output" \
      OCUTALON_CI_RUNS_FILE=$runs_file bash "$changes" ci.yml "$@"
  ) > "$tmp/stdout" 2> "$tmp/stderr"
  rc=$?
  out_base=$(sed -n 's/^base=//p' "$tmp/stdout")
  out_web=$(sed -n 's/^web=//p' "$tmp/stdout")
  out_iris=$(sed -n 's/^iris=//p' "$tmp/stdout")
  out_reason=$(sed -n 's/^reason=//p' "$tmp/stdout")
}

expect() { # expect <label> <base> <web> <iris>
  if [ "$rc" -eq 0 ] && [ "$out_base" = "$2" ] && [ "$out_web" = "$3" ] && [ "$out_iris" = "$4" ]; then
    pass "$1"
  else
    fail "$1 (rc=$rc base='$out_base' web='$out_web' iris='$out_iris', wanted base='$2' web='$3' iris='$4'; $out_reason)"
  fi
}

commit "c0" README.md web/package.json
c0=$sha
runs "$tmp/green-c0.json" "success:$c0"

# --- row 9: the classifier, with the paths given ---

paths_case() { # paths_case <label> <web> <iris> <path>...
  local label=$1 web=$2 iris=$3 f="$tmp/paths.txt"
  shift 3
  printf '%s\n' "$@" > "$f"
  classify "$tmp/green-c0.json" push --paths-from "$f"
  expect "classifier: $label" "$c0" "$web" "$iris"
}
paths_case "web/** runs web and iris" true true web/src/app/app.ts
paths_case "the Live payload classes run web and iris" true true src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls
paths_case "the generated sign-in assets run web and iris" true true src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls
paths_case "the UX design documents run web and iris (DESIGN.md is not bookkeeping)" true true _bmad-output/planning-artifacts/ux-designs/DESIGN.md
paths_case "logo/** runs web and iris" true true logo/mark.svg
paths_case "ci/** runs web and iris" true true ci/iris.sh
paths_case "the web build script runs web and iris" true true docker/tests/test-web-build.sh
paths_case "the workflow runs web and iris" true true .github/workflows/ci.yml
paths_case "the root .gitignore runs web and iris (the web build's clean checkout depends on it)" true true .gitignore
paths_case "the root .gitattributes runs web and iris" true true .gitattributes
paths_case "a .gitignore below the root runs iris only" false true docs/.gitignore
paths_case "another public class runs iris only" false true src/ocutalon/cls/OcuTalon/Web/Public/Status.cls
paths_case "a live test helper runs iris only" false true docker/tests/lib-live.sh
paths_case "the second workflow runs iris only" false true .github/workflows/lane-a.yml
paths_case "docs runs iris only" false true docs/guide.md
paths_case "_bmad/ alone is bookkeeping" false false _bmad/custom/skill-rules.md
paths_case "_bmad-output/ alone, outside the design documents, is bookkeeping" false false _bmad-output/implementation-artifacts/sprint-status.yaml _bmad-output/planning-artifacts/epics.md
paths_case "bookkeeping with one code path runs iris" false true _bmad/custom/parallel.yaml docker/after-start.sh
paths_case "no path at all skips both" false false

# --- row 10: the base ---

commit "c1 code" docker/Dockerfile
c1=$sha
commit "c2 code" src/module.xml
c2=$sha
runs "$tmp/green-c1.json" "success:$c1" "success:$c0"
classify "$tmp/green-c1.json" push
expect "base: the newest green commit of the history, not an older one" "$c1" false true
if [ -n "$out_reason" ] && printf '%s\n' "$out_reason" | grep -q "$(printf '%.12s' "$c1")"; then
  pass "skip line: the reason names the base"
else
  fail "skip line: the reason '$out_reason' does not name the base"
fi
runs "$tmp/green-c0-only.json" "success:$c0"
classify "$tmp/green-c0-only.json" push
expect "base: an older green commit, the diff since it holds code" "$c0" false true

runs "$tmp/mixed.json" "failure:$c2" "success:$c0"
classify "$tmp/mixed.json" push
expect "base: a red run is never a base" "$c0" false true

runs "$tmp/green-head.json" "success:$c2" "success:$c0"
classify "$tmp/green-head.json" push
expect "base: a re-run of a green HEAD has itself as the base, and nothing changed" "$c2" false false

classify "$tmp/green-c1.json" pull_request
expect "base: a pull request has no base and runs everything" "" true true
if printf '%s\n' "$out_reason" | grep -q 'pull_request'; then pass "pull request: the reason names the event"; else fail "pull request: the reason '$out_reason' does not name the event"; fi

echo '{"workflow_runs":[]}' > "$tmp/none.json"
classify "$tmp/none.json" push
expect "base: with no run there is no base and everything runs" "" true true

runs "$tmp/elsewhere.json" "success:0000000000000000000000000000000000000001"
classify "$tmp/elsewhere.json" push
expect "base: a green commit outside HEAD's history is no base" "" true true

runs "$tmp/pr-run.json" "success:$c1:pull_request"
classify "$tmp/pr-run.json" push
expect "base: a green run that was not a push is no base" "" true true

classify "$tmp/does-not-exist.json" push
expect "base: an answer that cannot be read fails open" "" true true
echo '{"message":"Bad credentials"}' > "$tmp/bad.json"
classify "$tmp/bad.json" push
expect "base: an answer with no run list fails open" "" true true
echo 'not json' > "$tmp/garbage.json"
classify "$tmp/garbage.json" push
expect "base: an answer that is not JSON fails open" "" true true

# --- row 11: red, then bookkeeping ---

commit "c3 code, red" web/src/app/app.ts
c3=$sha
commit "b1 bookkeeping only" _bmad-output/implementation-artifacts/sprint-status.yaml
b1=$sha
runs "$tmp/green-c2.json" "success:$c2"
classify "$tmp/green-c2.json" push
expect "red then bookkeeping: B1's base is the last green commit, so B1 runs the red commit's code again" "$c2" true true

commit "b2 bookkeeping only" _bmad/custom/parallel.yaml
runs "$tmp/green-b1.json" "success:$b1" "success:$c2"
classify "$tmp/green-b1.json" push
expect "bookkeeping after a green bookkeeping commit: nothing changed that matters, so both skip" "$b1" false false

# --- a push to main runs everything (REL-2), whatever a green run says ---

classify_ref=refs/heads/main
classify "$tmp/green-b1.json" push
expect "push to main: with a green base and only bookkeeping changed, no base and everything runs" "" true true
if printf '%s\n' "$out_reason" | grep -q 'main'; then pass "push to main: the reason names main"; else fail "push to main: the reason '$out_reason' does not name main"; fi
classify_ref=refs/heads/maintenance
classify "$tmp/green-b1.json" push
expect "push to another branch whose name starts with main: the skip rule applies as before" "$b1" false false
classify_ref=refs/heads/OCT-epic0
classify "$tmp/green-b1.json" push
expect "push to a feature branch with the same base and paths: both skip" "$b1" false false

# --- row 12: the outputs ---

classify "$tmp/green-b1.json" push
if [ "$(wc -l < "$tmp/github-output" | tr -d ' ')" = 4 ] && grep -qx "base=$b1" "$tmp/github-output" && grep -qx 'web=false' "$tmp/github-output" \
  && grep -qx 'iris=false' "$tmp/github-output" && grep -q '^reason=' "$tmp/github-output"; then
  pass "outputs: base, web, iris and reason are appended to GITHUB_OUTPUT, and printed"
else
  fail "outputs: GITHUB_OUTPUT does not hold the four lines ($(tr '\n' '|' < "$tmp/github-output"))"
fi

# The script reaches the network only when no answer file is given: with none and no repository it fails open. The runs below
# must not write to a job's output file, so one is named in the environment and has to stay empty.
export GITHUB_OUTPUT="$tmp/leaked-output"
: > "$GITHUB_OUTPUT"
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY="" GITHUB_API_URL="http://127.0.0.1:9" bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'web=true' "$tmp/stdout" && grep -qx 'iris=true' "$tmp/stdout" && grep -qx 'base=' "$tmp/stdout"; then
  pass "API failure: with no repository to ask, everything runs"
else
  fail "API failure: the script did not fail open without a repository"
fi
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY=o/r GITHUB_API_URL="http://127.0.0.1:9" bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'web=true' "$tmp/stdout" && grep -qx 'iris=true' "$tmp/stdout" && grep -qx 'base=' "$tmp/stdout"; then
  pass "API failure: an API that does not answer fails open, and everything runs"
else
  fail "API failure: the script did not fail open when the API did not answer"
fi

if [ ! -s "$tmp/leaked-output" ]; then
  pass "harness: the runs above set GITHUB_OUTPUT empty, so an output file of the environment (the checks job's own) stays empty"
else
  fail "harness: a run above wrote to the output file named in the environment"
fi
unset GITHUB_OUTPUT

# An output file that cannot be written fails the step: an empty output would leave the gates empty, and an empty gate skips.
(
  cd "$repo" || exit 1
  GITHUB_OUTPUT="$tmp" GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/heads/OCT-epic0 bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
rc=$?
if [ "$rc" -ne 0 ] && grep -q '^FAIL ci/changes.sh: cannot append to GITHUB_OUTPUT' "$tmp/stdout"; then
  pass "outputs: an output file that cannot be written fails the step"
else
  fail "outputs: an output file that cannot be written did not fail the step (exit $rc)"
fi

# --- the diff names a path with a non-ASCII name as it is, not quoted, so it still counts as a web input ---

commit "c4 non-ascii web path" "web/src/caf$(printf '\303\251').ts"
classify "$tmp/green-b1.json" push
expect "classifier: a web path with a non-ASCII name runs web and iris" "$b1" true true

# --- the runs API: the request, and the token on the standard input and on no command line ---

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOC'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS"
cat > "$CURL_STDIN"
cat "$CURL_ANSWER"
EOC
chmod +x "$tmp/bin/curl"
(
  cd "$repo" || exit 1
  PATH="$tmp/bin:$PATH" CURL_ARGS="$tmp/curl.args" CURL_STDIN="$tmp/curl.stdin" CURL_ANSWER="$tmp/green-b1.json" \
    GITHUB_OUTPUT="" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/OCT-epic0 GITHUB_REPOSITORY=o/r GITHUB_API_URL=https://api.example.invalid GH_TOKEN=tok-for-the-test \
    bash "$changes" ci.yml
) > "$tmp/stdout" 2>/dev/null
if grep -qx 'https://api.example.invalid/repos/o/r/actions/workflows/ci.yml/runs?event=push&status=success&per_page=100' "$tmp/curl.args" \
  && grep -qx "base=$b1" "$tmp/stdout" && grep -qx 'web=true' "$tmp/stdout" && grep -qx 'iris=true' "$tmp/stdout"; then
  pass "API: the runs of this workflow are asked for by push and success, and the answer gives the base"
else
  fail "API: the request or the base is wrong ($(tr '\n' ' ' < "$tmp/curl.args"); $(tr '\n' ' ' < "$tmp/stdout"))"
fi
if grep -q 'Authorization: Bearer tok-for-the-test' "$tmp/curl.stdin" && ! grep -q 'tok-for-the-test' "$tmp/curl.args"; then
  pass "API: the token goes to curl on its standard input and is on no command line"
else
  fail "API: the token is not on curl's standard input, or is on its command line"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-ci-changes: $fails check(s) failed"
  exit 1
fi
echo "test-ci-changes: all checks passed"
