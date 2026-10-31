#!/usr/bin/env bash
# Hermetic test of the demo-path gate (Story 0.8; REL-2): a red demo path turns the unit red, and a red unit turns its group, so the
# `iris (browser)` job and the `ci` run, red. It runs the real docker/tests/test-demo-path.sh, the real
# web/scripts/demo-path-summary.mjs and the real ci/iris.sh group in a scratch copy of the tree, with the stack replaced: the
# parts of lib-live.sh that need Docker (live_start, live_web_port, live_first_start, dc, start_log) are redefined after the real
# file is sourced, `npm` copies a prepared Playwright JSON report and exits with a chosen code, `docker` answers only
# `image inspect` (the preflight reads the mock's image from the copy of ci/compose.ci.yml), and the other units of the browser group are stubs; `npx`, `npm` and the stub units append each call to one
# sequence, and an unexpected `docker` or `npm` call fails the run that made it. The audit log is replaced too: the `dc exec` of
# the unit's iris_script answers the canned CHK lines of the file GATE_AUDIT names. It checks that
#   - the unit exits 0 only when Playwright and the step summary both pass and the audit entries are there, prints the FIRST-START
#     line before the STEP lines and the Playwright log indented, never reads a skipped step as passed, waits 900 s for the first
#     start (so a start ready after 720 s can still warn), and gives the run the deadline's remaining seconds less 80, the stack's
#     URL and the report path; it takes the audit mark before Playwright and reads the log after it;
#   - with OCUTALON_DEMO_PATH_MODEL=real (Story 11.7) the unit prints `MODEL real: a dry run on the CI mock` and points the runners' keys
#     (the stub logs it as `point`) before the audit mark and before Playwright, and fails with no spec run when that does not answer OK;
#     the default and `mock` point nothing and print no MODEL line, and any other value goes through to Playwright untouched; `npm`
#     records the value it got, or that it got none;
#   - the unit exits 1, with the reason on a line, for a skipped or failed @floor test (Playwright exits 0 for a skip), a skipped
#     test of a numbered step file (only the Telegram parts may skip), a skip that names no story, a spec file that maps to no
#     step, a missing step spec, a Playwright exit 1 beside a green report, and a missing report;
#   - the unit exits 1 with one FAIL line for each audit entry that is missing (the answered Approval entry, the resend's Action
#     entry), that holds more or fewer members than its shape, or that holds key-like text; it reads the audit log after a red
#     demo path too;
#   - a first start over 12 minutes warns and the specs still run, a first start that never ends ready fails the unit before any
#     spec runs, and a deadline with under 100 s left fails it before the browser starts;
#   - `ci/iris.sh group browser` runs live:demo-path and live:sign-in in that order, installs Chromium before
#     the script of each browser unit (BROWSER_UNITS) and before no other, exits 0 when both pass, and exits 1 with
#     `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path` when the demo path is red, whether Playwright failed
#     or only skipped the floor test;
#   - `ci/iris.sh live bundle-folder` installs no browser, and `ci/iris.sh live floor` installs Chromium, then Firefox and WebKit,
#     before its script (the names of FIREFOX_WEBKIT_UNITS, which are all in BROWSER_UNITS).
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs bash and Node; starts no container and no browser.
set -u

# The scratch tree holds a stand-in web bundle, which the group run must keep, whatever the caller's shell exports; and each run
# names its own model value (OCUTALON_DEMO_PATH_MODEL) or none.
unset LIVE_REBUILD_WEB OCUTALON_DEMO_PATH_MODEL

repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-dpg.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL node is not installed: the step summary of the demo path needs it"
  exit 1
fi

# --- the scratch tree: the real scripts, the replaced stack ---

tree="$tmp/tree"
log="$tmp/log"
out="$tmp/out"
mkdir -p "$tree/ci" "$tree/docker/tests" "$tree/web/node_modules" "$tree/src/ocutalon/csp" "$tree/bin" "$log" "$tmp/reports"
cp ci/iris.sh ci/units.sh ci/compose.ci.yml "$tree/ci/"
cp docker/tests/lib-live.sh "$tree/docker/tests/lib-live-real.sh"
cp docker/tests/test-demo-path.sh docker/tests/lib-keys.sh "$tree/docker/tests/"
ln -s "$repo/web/scripts" "$tree/web/scripts"
: > "$tree/src/ocutalon/csp/index.html"

cat > "$tree/docker/tests/lib-live.sh" <<'EOF'
# The real lib-live.sh, with what needs Docker replaced.
. "$(dirname "${BASH_SOURCE[0]}")/lib-live-real.sh"
live_start() {
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  cd "$root" || exit 1
  P="ocutalon-$1-gate"
  fails=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-dpg-unit.XXXXXX") || exit 1
  trap 'rm -rf "$tmp"' EXIT
  deadline=$((SECONDS + ${GATE_DEADLINE:-540}))
}
live_web_port() { web_port=52899; }
live_first_start() {
  echo "$1" > "$GATE_LOG/first.max"
  if [ "${GATE_FIRST:-ready}" = never ]; then
    echo "first start: not ready after waiting 905 s"
    return 1
  fi
  first_start_report 2 "${GATE_READY:-150}" x86_64
}
dc() {
  if [ "${1:-}" = exec ]; then
    local script
    script=$(cat)
    case "$script" in
      *PointKeys*)
        echo "point" >> "$GATE_LOG/audit.order"
        echo "CHK|keys|${GATE_POINT:-1}"
        ;;
      *)
        echo "read" >> "$GATE_LOG/audit.order"
        if [ -n "${GATE_AUDIT:-}" ]; then cat "$GATE_AUDIT"; fi
        ;;
    esac
  fi
}
start_log() { :; }
EOF

for unit in sign-in bundle-folder floor answers; do
  printf '#!/usr/bin/env bash\necho "ran %s" >> "$GATE_LOG/sequence"\nexit "${GATE_UNIT_RC:-0}"\n' "$unit" > "$tree/docker/tests/test-$unit.sh"
done

printf '#!/bin/sh\n[ "$1" = image ] && [ "$2" = inspect ] && exit 0\necho "$*" >> "$GATE_LOG/docker.unexpected"\nexit 1\n' > "$tree/bin/docker"
printf '#!/bin/sh\necho "npx $*" >> "$GATE_LOG/sequence"\nexit 0\n' > "$tree/bin/npx"
cat > "$tree/bin/npm" <<'EOF'
#!/bin/sh
if [ "$*" != "--prefix web run e2e:demo-path" ]; then
  echo "$*" >> "$GATE_LOG/npm.unexpected"
  exit 99
fi
echo "called" >> "$GATE_LOG/npm.calls"
echo "npm" >> "$GATE_LOG/audit.order"
echo "npm $*" >> "$GATE_LOG/sequence"
echo "OCUTALON_URL=$OCUTALON_URL" > "$GATE_LOG/npm.env"
echo "OCUTALON_E2E_JSON=$OCUTALON_E2E_JSON" >> "$GATE_LOG/npm.env"
echo "OCUTALON_E2E_TIMEOUT_MS=$OCUTALON_E2E_TIMEOUT_MS" >> "$GATE_LOG/npm.env"
if [ -n "${OCUTALON_DEMO_PATH_MODEL+set}" ]; then
  echo "OCUTALON_DEMO_PATH_MODEL=$OCUTALON_DEMO_PATH_MODEL" >> "$GATE_LOG/npm.env"
else
  echo "OCUTALON_DEMO_PATH_MODEL unset" >> "$GATE_LOG/npm.env"
fi
echo "Running tests using 1 worker"
if [ -n "${GATE_NPM_OUT:-}" ]; then echo "$GATE_NPM_OUT"; fi
if [ -n "${GATE_REPORT:-}" ]; then cp "$GATE_REPORT" "$OCUTALON_E2E_JSON"; fi
exit "${GATE_NPM_RC:-0}"
EOF
chmod +x "$tree/bin/docker" "$tree/bin/npx" "$tree/bin/npm" "$tree/docker/tests/test-sign-in.sh" "$tree/docker/tests/test-bundle-folder.sh" "$tree/docker/tests/test-floor.sh" "$tree/docker/tests/test-answers.sh"

# The reports have the shape of Playwright 1.64.1's JSON report: a skip's text in annotations, a tag without its @, one top-level
# suite per spec file, and the file of a declaration in not-built.ts for every unbuilt part.
cat > "$tmp/mkreports.mjs" <<'EOF'
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const out = process.argv[2];
mkdirSync(out, { recursive: true });

const ENDED = { passed: 'expected', skipped: 'skipped', failed: 'unexpected' };
function spec(title, status, { tags = [], note } = {}) {
  const annotations = note === undefined ? [] : [{ type: 'skip', description: note }];
  return {
    title,
    ok: status !== 'failed',
    tags,
    file: 'demo-path/not-built.ts',
    tests: [
      {
        annotations,
        expectedStatus: status === 'skipped' ? 'skipped' : 'passed',
        projectName: 'demo-path',
        results: [{ status, annotations, errors: [] }],
        status: ENDED[status],
      },
    ],
  };
}
const floor = (status, note) => spec('signs in with the README account and loads the page snapshot', status, { tags: ['floor'], note });
const unbuilt = (title, story) => spec(title, 'skipped', { note: `Story ${story} turns this on` });
const file = (name, specs) => ({ title: `demo-path/${name}`, file: `demo-path/${name}`, column: 0, line: 0, specs, suites: [] });

function suites(floorTest = floor('passed')) {
  return [
    file('01-page.spec.ts', [floorTest, spec('shows the empty chat panel and the composer', 'passed', { tags: ['floor'] })]),
    file('02-watch.spec.ts', [spec('the watch prompt gets its reply', 'passed')]),
    file('03-reminder.spec.ts', [spec('the reminder prompt is confirmed', 'passed')]),
    file('04-incident.spec.ts', [spec('one incident card awaits approval', 'passed')]),
    file('05-approval.spec.ts', [spec('Approve on the simulated phone', 'passed')]),
    file('06-trace.spec.ts', [spec('the trace link opens Visual Trace', 'passed')]),
    file('telegram-page.spec.ts', [unbuilt('the page pairs a Telegram chat', '12.4')]),
    file('telegram-approval.spec.ts', [unbuilt('an approval request is answered from the paired Telegram chat', '12.7')]),
  ];
}
const write = (name, list) => writeFileSync(join(out, `${name}.json`), JSON.stringify({ suites: list, errors: [], stats: {} }));

write('green', suites());
write('floor-skipped', suites(floor('skipped', 'Story 4.7 turns this on')));
write('floor-failed', suites(floor('failed')));
{
  const list = suites();
  list[6].specs.push(spec('the Telegram reminder row appears', 'skipped'));
  write('no-story', list);
}
{
  const list = suites();
  list[3].specs.push(unbuilt('a part that nobody turned on', '11.1'));
  list[5].specs = [unbuilt('the trace link opens Visual Trace', '11.1')];
  write('numbered-skip', list);
}
{
  const list = suites();
  list.push(file('07-extra.spec.ts', [unbuilt('a part', '12.4')]));
  write('unknown-file', list);
}
{
  const list = suites();
  list.splice(2, 1);
  write('missing-spec', list);
}
EOF
if ! node "$tmp/mkreports.mjs" "$tmp/reports"; then
  echo "FAIL the scratch reports could not be written"
  exit 1
fi

# The canned audit log, as the unit's ObjectScript prints it (CHK lines): the answered Approval entry of the README session's request and
# the resend's Action entry that names it. The variants miss the Action entry, hold more or fewer members than the shape (the shape flag
# is the ObjectScript's), or hold key-like text (assembled here, so that this file holds none).
mkdir -p "$tmp/audit"
session=zzSessionRef0123456789
request=zzRequestRef0123456789
approval_json="{\"ref\":\"$request\",\"kind\":\"fix\",\"change\":\"answered\",\"from\":\"pending\",\"to\":\"approved\",\"outcome\":\"approved\",\"target\":\"incident\",\"ownerRef\":\"$session\",\"irisUser\":\"ocutalon\",\"sessionRef\":\"$session\",\"channel\":\"phone\"}"
action_json="{\"action\":\"repair_resend\",\"target\":\"OrderDate\",\"result\":\"done\",\"counts\":{\"total\":50},\"approvalRef\":\"$request\",\"irisUser\":\"ocutalon\",\"sessionRef\":\"$session\",\"channel\":\"phone\"}"
keyed_json="${approval_json%\}},\"leak\":\"sk-ant""-api03-abcdefgh12345678\"}"
# audit_file <name> <approval found> <approval shape> <approval json> <action found> <action shape> <action json>
audit_file() {
  printf '%s\n' "CHK|mark|2030-01-01 00:00:00.000" "CHK|session|$session" "CHK|approval-found|$2" "CHK|approval-shape|$3" "CHK|approval-ref|$request" "CHK|approval-data|$4" \
    "CHK|action-found|$5" "CHK|action-shape|$6" "CHK|action-data|$7" > "$tmp/audit/$1.chk"
}
audit_file good 1 1 "$approval_json" 1 1 "$action_json"
audit_file no-action 1 1 "$approval_json" 0 0 ""
audit_file no-approval 0 0 "" 0 0 ""
audit_file extra-approval 1 0 "$approval_json" 1 1 "$action_json"
audit_file extra-action 1 1 "$approval_json" 1 0 "$action_json"
audit_file keyed-approval 1 1 "$keyed_json" 1 1 "$action_json"
audit_file keyed-action 1 1 "$approval_json" 1 1 "${action_json%\}},\"leak\":\"sk-ant""-api03-abcdefgh12345678\"}"
# The units read the good log unless a run names another one, and do not wait for an entry that is not there.
export GATE_AUDIT="$tmp/audit/good.chk" OCUTALON_AUDIT_POLL=0

# --- running the replaced unit and group ---

# run_unit <report name, or - for none> <npm exit> [NAME=value ...]: the unit's output is in $out and its exit code in $rc.
run_unit() {
  local report=$1 code=$2 file=""
  shift 2
  rm -f "$log"/*
  if [ "$report" != - ]; then file="$tmp/reports/$report.json"; fi
  env GATE_LOG="$log" GATE_REPORT="$file" GATE_NPM_RC="$code" ${1+"$@"} PATH="$tree/bin:$PATH" \
    bash "$tree/docker/tests/test-demo-path.sh" > "$out" 2>&1
  rc=$?
  stubs_called_as_expected "unit ($report, npm exit $code)"
}

# run_group <report name> <npm exit> [NAME=value ...]: the same for `ci/iris.sh group browser`.
run_group() {
  local report=$1 code=$2
  shift 2
  rm -f "$log"/*
  env GATE_LOG="$log" GATE_REPORT="$tmp/reports/$report.json" GATE_NPM_RC="$code" OCUTALON_RUN_TAG=gate-grp ${1+"$@"} PATH="$tree/bin:$PATH" \
    bash "$tree/ci/iris.sh" group browser > "$out" 2>&1
  rc=$?
  stubs_called_as_expected "group ($report, npm exit $code)"
}

# run_live <unit>: the same for `ci/iris.sh live <unit>`, whose stub script and installs are in the sequence.
run_live() {
  rm -f "$log"/*
  env GATE_LOG="$log" OCUTALON_RUN_TAG=gate-live PATH="$tree/bin:$PATH" bash "$tree/ci/iris.sh" live "$1" > "$out" 2>&1
  rc=$?
  stubs_called_as_expected "live $1"
}

# stubs_called_as_expected <run>: fails the run that called the docker or npm stub in a way that no check expects.
stubs_called_as_expected() {
  if [ -e "$log/docker.unexpected" ] || [ -e "$log/npm.unexpected" ]; then
    fail "$1: a stub was called in a way the test did not expect ($(cat "$log/docker.unexpected" "$log/npm.unexpected" 2> /dev/null | tr '\n' ';'))"
  fi
}

# sequence: the calls of npx, npm and the stub units of the last run, in order, joined by |.
sequence() { tr '\n' '|' < "$log/sequence" 2> /dev/null; }

# expect <label> <wanted exit> <fixed text>...: the last run exited as wanted, and each text is on a line of its output.
expect() {
  local label=$1 want=$2 text miss=""
  shift 2
  for text in "$@"; do
    grep -qF -- "$text" "$out" || miss="$miss [$text]"
  done
  if [ "$rc" -eq "$want" ] && [ -z "$miss" ]; then
    pass "$label"
  else
    fail "$label (exit $rc, wanted $want; missing:${miss:- nothing})"
    sed 's/^/  | /' "$out" | head -n 40
  fi
}

# absent <label> <fixed text>...: none of the texts is on a line of the last output.
absent() {
  local label=$1 text found=""
  shift
  for text in "$@"; do
    ! grep -qF -- "$text" "$out" || found="$found [$text]"
  done
  if [ -z "$found" ]; then pass "$label"; else fail "$label (found:$found)"; fi
}

line_of() { grep -nF -- "$1" "$out" | head -n 1 | cut -d: -f1; }

# --- the unit: a green run ---

run_unit green 0
expect "unit: passed web steps and skipped Telegram parts give exit 0, the PASS line and the audit PASS lines" 0 \
  "PASS the demo path: Playwright and the step summary both passed" \
  "STEP 1 page: partly skipped, 2 passed, 1 skipped (Story 12.4: the page pairs a Telegram chat)" \
  "STEP 2 watch: passed, 1 passed, 0 skipped" \
  "STEP 5 approval: partly skipped, 1 passed, 1 skipped (Story 12.7: " \
  "STEP 6 trace: passed, 1 passed, 0 skipped" \
  "DEMO-PATH 6 of 6 steps ran (2 partly skipped), 2 skipped, 0 failed; floor 2 of 2 passed" \
  "  Running tests using 1 worker" \
  "PASS audit: the answered Approval entry (approved, from the phone) of the README session is in the log" \
  "PASS audit: the Approval entry holds exactly its shape and the common members" \
  "PASS audit: no key-like text in the Approval entry" \
  "PASS audit: the resend's Action entry that names the approval request is in the log" \
  "PASS audit: the Action entry holds exactly its shape and the common members" \
  "PASS audit: no key-like text in the Action entry" \
  "test-demo-path: all checks passed"
absent "unit: a green run draws no FAIL line" "FAIL "
if [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "read npm read " ]; then
  pass "unit: the audit mark is taken before Playwright and the log is read after the step summary"
else
  fail "unit: the audit calls ran as '$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)', not 'read npm read'"
fi
if [ "$(cat "$log/first.max" 2> /dev/null)" = 900 ]; then
  pass "unit: the first start waits 900 s for the start's log, so a start ready after 720 s can still warn (AD-23)"
else
  fail "unit: the first start waits '$(cat "$log/first.max" 2> /dev/null)' s, not 900"
fi
if grep -qE '^STEP 1 page: partly skipped' "$out" && grep -qE '^STEP 5 approval: partly skipped' "$out"; then
  pass "unit: a step with a skipped Telegram part reads partly skipped, not passed"
else
  fail "unit: a step with a skipped part is read as passed"
fi
first=$(line_of "FIRST-START engine=x86_64 build=2s ready=150s")
step=$(line_of "STEP 1 page")
if [ -n "$first" ] && [ -n "$step" ] && [ "$first" -lt "$step" ] && ! grep -q '^WARN' "$out"; then
  pass "unit: the FIRST-START line comes before the STEP lines, and a start under 12 minutes draws no WARN"
else
  fail "unit: the FIRST-START line is missing, comes after the STEP lines, or a quick start warned (lines $first and $step)"
fi
timeout_ms=$(sed -n 's/^OCUTALON_E2E_TIMEOUT_MS=//p' "$log/npm.env" 2> /dev/null)
if [ "$(grep -c . "$log/npm.calls" 2> /dev/null)" = 1 ] && [ ! -e "$log/npm.unexpected" ] \
  && grep -qx 'OCUTALON_URL=http://127.0.0.1:52899' "$log/npm.env" && grep -q '^OCUTALON_E2E_JSON=.*/demo-path\.json$' "$log/npm.env" \
  && [ "${timeout_ms:-0}" -gt 440000 ] && [ "${timeout_ms:-0}" -le 460000 ]; then
  pass "unit: Playwright runs once, with the stack's URL, a report path, and the deadline's remaining time less 80 s"
else
  fail "unit: the Playwright call is wrong ($(tr '\n' ' ' < "$log/npm.env" 2> /dev/null); calls $(cat "$log/npm.calls" 2> /dev/null | wc -l | tr -d ' '))"
fi

# --- the unit: the real-model switch (Story 11.7) ---

run_unit green 0 OCUTALON_DEMO_PATH_MODEL=real
expect "unit: the real-model dry run prints its MODEL line, and the same steps and audit checks pass" 0 \
  "MODEL real: a dry run on the CI mock" \
  "PASS the demo path: Playwright and the step summary both passed" \
  "PASS audit: the answered Approval entry (approved, from the phone) of the README session is in the log" \
  "test-demo-path: all checks passed"
if [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "point read npm read " ]; then
  pass "unit: the real-model dry run points the keys first, then takes the audit mark, then runs Playwright (point before npm)"
else
  fail "unit: the calls of the real-model dry run ran as '$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)', not 'point read npm read'"
fi
model_seen() {
  if grep -qx "$2" "$log/npm.env" 2> /dev/null; then
    pass "unit: Playwright gets $2 ($1)"
  else
    fail "unit: Playwright got '$(grep '^OCUTALON_DEMO_PATH_MODEL' "$log/npm.env" 2> /dev/null)', not '$2' ($1)"
  fi
}
model_seen "the real-model dry run checks the real model's way" "OCUTALON_DEMO_PATH_MODEL=real"

run_unit green 0 OCUTALON_DEMO_PATH_MODEL=real GATE_POINT=0
expect "unit: keys that cannot be pointed fail the real-model dry run before any mark or spec" 1 \
  "MODEL real: a dry run on the CI mock" \
  "FAIL MODEL real: the runners' keys could not be pointed at the CI mock"
if [ ! -e "$log/npm.calls" ] && [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "point " ]; then
  pass "unit: no mark is taken and no spec runs after keys that could not be pointed"
else
  fail "unit: Playwright or the audit mark ran after keys that could not be pointed ($(tr '\n' ' ' < "$log/audit.order" 2> /dev/null))"
fi

run_unit green 0
absent "unit: the default model prints no MODEL line and points no keys" "MODEL real"
model_seen "no value is set where the caller set none" "OCUTALON_DEMO_PATH_MODEL unset"
run_unit green 0 OCUTALON_DEMO_PATH_MODEL=mock
if [ "$rc" -eq 0 ] && [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "read npm read " ]; then
  pass "unit: the mock model points no keys: the specs do"
else
  fail "unit: the mock model's calls ran as '$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)' (exit $rc)"
fi
model_seen "the mock model" "OCUTALON_DEMO_PATH_MODEL=mock"
run_unit green 0 OCUTALON_DEMO_PATH_MODEL=zz
if [ "$rc" -eq 0 ] && [ -e "$log/npm.calls" ] && ! grep -q '^MODEL' "$out" && [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "read npm read " ]; then
  pass "unit: another value goes through to the specs, which refuse it before their first step"
else
  fail "unit: another model value was not passed through untouched (exit $rc)"
fi
model_seen "another value goes through untouched" "OCUTALON_DEMO_PATH_MODEL=zz"

# --- the unit: a red demo path ---

run_unit floor-skipped 0
expect "unit: a skipped floor test fails the unit although Playwright exits 0" 1 \
  "STEP 1 page: partly skipped, 1 passed, 2 skipped" \
  'FAIL floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) was skipped' \
  'FAIL 01-page.spec.ts "signs in with the README account and loads the page snapshot": skipped, but every web step runs since Story 11.1 (REL-2); only telegram-*.spec.ts parts may skip' \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1" \
  "PASS audit: the answered Approval entry (approved, from the phone) of the README session is in the log" \
  "PASS audit: the resend's Action entry that names the approval request is in the log" \
  "test-demo-path: 1 check(s) failed"
absent "unit: a skipped floor test draws no PASS for the demo path" "PASS the demo path"
if [ "$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)" = "read npm read " ]; then
  pass "unit: a red demo path still reads the audit log after the step summary"
else
  fail "unit: the audit calls of a red demo path ran as '$(tr '\n' ' ' < "$log/audit.order" 2> /dev/null)', not 'read npm read'"
fi

run_unit floor-failed 1
expect "unit: a failed floor test fails the unit, and step 1 reads failed" 1 \
  "STEP 1 page: failed, 1 passed, 1 skipped, 1 failed" \
  'FAIL floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) failed' \
  "FAIL the demo path: Playwright exit 1, the step summary exit 1"

run_unit no-story 0
expect "unit: a Telegram part whose skip names no story fails the unit although Playwright exits 0" 1 \
  'telegram-page.spec.ts "the Telegram reminder row appears": its skip names no story' \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1"

run_unit numbered-skip 0
expect "unit: a skipped test of a numbered step file fails the unit although Playwright exits 0 and the skip names its story" 1 \
  '04-incident.spec.ts "a part that nobody turned on": skipped, but every web step runs since Story 11.1 (REL-2); only telegram-*.spec.ts parts may skip' \
  '06-trace.spec.ts "the trace link opens Visual Trace": skipped, but every web step runs since Story 11.1 (REL-2); only telegram-*.spec.ts parts may skip' \
  "STEP 4 incident: partly skipped, 1 passed, 1 skipped" \
  "STEP 6 trace: skipped, 0 passed, 1 skipped" \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1"
absent "unit: a step whose parts all skipped is never read as passed" "STEP 6 trace: passed"

run_unit unknown-file 0
expect "unit: a spec file that maps to no step fails the unit" 1 \
  "the report holds 07-extra.spec.ts, which maps to no step" \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1"

run_unit missing-spec 0
expect "unit: a missing step spec fails the unit and names it" 1 \
  "step 3 reminder has no 03-reminder.spec.ts in the report" \
  "STEP 3 reminder: failed, 0 passed, 0 skipped"

run_unit green 1
expect "unit: a Playwright exit 1 fails the unit although the report is green" 1 \
  "FAIL the demo path: Playwright exit 1, the step summary exit 0"

run_unit - 1 GATE_NPM_OUT="Error: browserType.launch: Executable doesn't exist at /somewhere"
expect "unit: no report fails the unit, names the cause and says how to install the browser" 1 \
  "FAIL no usable report: the file cannot be read (ENOENT)" \
  "the browser is missing: run npx --prefix web playwright install chromium" \
  "FAIL the demo path: Playwright exit 1, the step summary exit 1"

# --- the unit: the audit log ---

run_unit green 0 GATE_AUDIT="$tmp/audit/no-action.chk"
expect "unit: no Action entry that names the request fails the unit with one FAIL line, and the Approval entry still passes" 1 \
  "PASS audit: the answered Approval entry (approved, from the phone) of the README session is in the log" \
  "FAIL audit: no Action entry that names the approval request since the mark within 0 s" \
  "test-demo-path: 1 check(s) failed"

run_unit green 0 GATE_AUDIT="$tmp/audit/no-approval.chk"
expect "unit: no answered Approval entry fails the unit, and so does the Action entry that cannot be tied to it" 1 \
  "FAIL audit: no answered Approval entry (approved, from the phone) of the README session since the mark within 0 s" \
  "FAIL audit: no Action entry that names the approval request since the mark within 0 s" \
  "test-demo-path: 2 check(s) failed"

run_unit green 0 GATE_AUDIT="$tmp/audit/extra-approval.chk"
expect "unit: an Approval entry with an extra or a missing member fails the unit with its own FAIL line" 1 \
  "FAIL audit: the Approval entry does not hold exactly Bridge.Audit.Shape(Approval) and the common members" \
  "PASS audit: the Action entry holds exactly its shape and the common members" \
  "test-demo-path: 1 check(s) failed"

run_unit green 0 GATE_AUDIT="$tmp/audit/extra-action.chk"
expect "unit: an Action entry with an extra or a missing member fails the unit with its own FAIL line" 1 \
  "FAIL audit: the Action entry does not hold exactly Bridge.Audit.Shape(Action) and the common members" \
  "PASS audit: the Approval entry holds exactly its shape and the common members" \
  "test-demo-path: 1 check(s) failed"

run_unit green 0 GATE_AUDIT="$tmp/audit/keyed-approval.chk"
expect "unit: key-like text in the Approval entry fails the unit, and the value is never printed" 1 \
  "FAIL audit: the Approval entry holds key-like text" \
  "PASS audit: no key-like text in the Action entry" \
  "test-demo-path: 1 check(s) failed"
absent "unit: the key-like value is not in the output" "api03-abcdefgh"

run_unit green 0 GATE_AUDIT="$tmp/audit/keyed-action.chk"
expect "unit: key-like text in the Action entry fails the unit" 1 \
  "FAIL audit: the Action entry holds key-like text" \
  "PASS audit: no key-like text in the Approval entry" \
  "test-demo-path: 1 check(s) failed"

run_unit green 0 GATE_AUDIT=
expect "unit: a log that cannot be read (no mark, no entry) fails the unit" 1 \
  "FAIL audit: the mark could not be taken before the browser steps"

# --- the unit: the first start and the deadline ---

run_unit green 0 GATE_READY=800
warn=$(line_of "WARN first start 800 s is over 12 minutes: raise it to the author (AD-23)")
first=$(line_of "FIRST-START engine=x86_64 build=2s ready=800s")
if [ "$rc" -eq 0 ] && [ -n "$warn" ] && [ -n "$first" ] && [ "$warn" -eq $((first + 1)) ] && [ -e "$log/npm.calls" ] \
  && grep -qF "PASS the demo path: Playwright and the step summary both passed" "$out"; then
  pass "unit: a first start over 12 minutes warns right after the FIRST-START line, and the specs still run and pass"
else
  fail "unit: a slow first start did not warn and go on (exit $rc; lines $first and $warn)"
fi

run_unit green 0 GATE_FIRST=never
expect "unit: a first start that never ends ready fails the unit with its reason" 1 \
  "first start: not ready after waiting 905 s" \
  "FAIL the first start did not end ready"
if [ ! -e "$log/npm.calls" ]; then pass "unit: no spec runs after a failed first start"; else fail "unit: Playwright ran after a failed first start"; fi

run_unit green 0 GATE_DEADLINE=95
expect "unit: a deadline with under 100 s left fails the unit before the browser starts" 1 "s are left of the deadline: too little for the browser run"
if [ ! -e "$log/npm.calls" ]; then pass "unit: no spec runs when too little of the deadline is left"; else fail "unit: Playwright ran with too little of the deadline left"; fi

# --- the group: ci/iris.sh group browser ---

run_group green 0
order=$(grep '^---- UNIT' "$out" | awk '{ printf "%s ", $3 }')
expect "group: browser passes when its three units pass" 0 \
  "UNIT live:demo-path passed" "UNIT live:sign-in passed" "UNIT live:answers passed" "GROUP browser passed"
absent "group: browser no longer runs live:bundle-folder" "live:bundle-folder"
if [ "$order" = "live:demo-path live:sign-in live:answers " ]; then
  pass "group: browser runs live:demo-path, live:sign-in and live:answers, in that order"
else
  fail "group: the units ran in the order '$order'"
fi
chromium='npx --prefix web playwright install chromium'
# The demo path's Playwright call as the npm stub records it, assembled so that this file never matches test-ci-config.sh's
# rule for the scripts that run Playwright (this one only stubs it).
npm_run='npm --prefix web run'
if [ "$(sequence)" = "$chromium|$npm_run e2e:demo-path|$chromium|ran sign-in|$chromium|ran answers|" ]; then
  pass "group: Chromium is installed before the script of each browser unit, demo-path, sign-in and answers, and before no other"
else
  fail "group: the calls ran as '$(sequence)'"
fi

run_group floor-failed 1
expect "group: a failed demo path makes the browser group exit 1 and names the unit" 1 \
  "UNIT live:demo-path failed" "UNIT live:sign-in passed" "UNIT live:answers passed" "GROUP browser failed: live:demo-path ("
absent "group: a red demo path draws no GROUP passed line" "GROUP browser passed"

run_group floor-skipped 0
expect "group: a skipped floor test makes the browser group exit 1 although Playwright exits 0" 1 \
  "UNIT live:demo-path failed" "GROUP browser failed: live:demo-path"

run_group green 0 GATE_UNIT_RC=1
expect "group: a red unit other than the demo path makes the group exit 1 and names it" 1 \
  "UNIT live:demo-path passed" "UNIT live:sign-in failed" "UNIT live:answers failed" "GROUP browser failed: live:sign-in live:answers ("

# --- the live units: which browsers are installed before the script ---

run_live bundle-folder
if [ "$rc" -eq 0 ] && [ "$(sequence)" = "ran bundle-folder|" ]; then
  pass "live: bundle-folder installs no browser, and runs its script"
else
  fail "live: bundle-folder ran as '$(sequence)' (exit $rc)"
  sed 's/^/  | /' "$out" | head -n 20
fi

run_live floor
if [ "$rc" -eq 0 ] && [ "$(sequence)" = "$chromium|npx --prefix web playwright install firefox webkit|ran floor|" ]; then
  pass "live: floor installs Chromium, then Firefox and WebKit, before its script"
else
  fail "live: floor ran as '$(sequence)' (exit $rc)"
  sed 's/^/  | /' "$out" | head -n 20
fi

fw_units=$(. "$repo/ci/units.sh" && printf '%s' "$FIREFOX_WEBKIT_UNITS")
browser_units=$(. "$repo/ci/units.sh" && printf '%s' "$BROWSER_UNITS")
stray=""
for name in $fw_units; do
  printf '%s\n' $browser_units | grep -qx -- "$name" || stray="$stray $name"
done
if [ -z "$stray" ] && [ -n "$fw_units" ]; then
  pass "units: every name of FIREFOX_WEBKIT_UNITS is in BROWSER_UNITS, and the list is not empty"
else
  fail "units: FIREFOX_WEBKIT_UNITS is empty, or holds names outside BROWSER_UNITS ($stray)"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-demo-path-gate: $fails check(s) failed"
  exit 1
fi
echo "test-demo-path-gate: all checks passed"
