#!/usr/bin/env bash
# Hermetic test of the demo-path gate (Story 0.8; REL-2): a red demo path turns the unit red, and a red unit turns its group, so the
# `iris (browser)` job and the `ci` run, red. It runs the real docker/tests/test-demo-path.sh, the real
# web/scripts/demo-path-summary.mjs and the real ci/iris.sh group in a scratch copy of the tree, with the stack replaced: the
# parts of lib-live.sh that need Docker (live_start, live_web_port, live_first_start, dc, start_log) are redefined after the real
# file is sourced, `npm` copies a prepared Playwright JSON report and exits with a chosen code, `docker` answers only
# `image inspect` (the preflight reads the mock's image from the copy of ci/compose.ci.yml), and the other units of the browser group are stubs; `npx`, `npm` and the stub units append each call to one
# sequence, and an unexpected `docker` or `npm` call fails the run that made it. It checks that
#   - the unit exits 0 only when Playwright and the step summary both pass, prints the FIRST-START line before the STEP lines and
#     the Playwright log indented, never reads a skipped step as passed, waits 900 s for the first start (so a start ready after
#     720 s can still warn), and gives the run the deadline's remaining seconds, the stack's URL and the report path;
#   - the unit exits 1, with the reason on a line, for a skipped or failed @floor test (Playwright exits 0 for a skip), a skip that
#     names no story, a spec file that maps to no step, a missing step spec, a Playwright exit 1 beside a green report, and a
#     missing report;
#   - a first start over 12 minutes warns and the specs still run, a first start that never ends ready fails the unit before any
#     spec runs, and a deadline with under 60 s left fails it before the browser starts;
#   - `ci/iris.sh group browser` runs live:demo-path and live:sign-in in that order, installs Chromium before
#     the script of each browser unit (BROWSER_UNITS) and before no other, exits 0 when both pass, and exits 1 with
#     `UNIT live:demo-path failed` and `GROUP browser failed: live:demo-path` when the demo path is red, whether Playwright failed
#     or only skipped the floor test;
#   - `ci/iris.sh live bundle-folder` installs no browser, and `ci/iris.sh live floor` installs Chromium, then Firefox and WebKit,
#     before its script (the names of FIREFOX_WEBKIT_UNITS, which are all in BROWSER_UNITS).
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs bash and Node; starts no container and no browser.
set -u

# The scratch tree holds a stand-in web bundle, which the group run must keep, whatever the caller's shell exports.
unset LIVE_REBUILD_WEB

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
cp docker/tests/test-demo-path.sh "$tree/docker/tests/test-demo-path.sh"
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
dc() { :; }
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
echo "npm $*" >> "$GATE_LOG/sequence"
echo "OCUTALON_URL=$OCUTALON_URL" > "$GATE_LOG/npm.env"
echo "OCUTALON_E2E_JSON=$OCUTALON_E2E_JSON" >> "$GATE_LOG/npm.env"
echo "OCUTALON_E2E_TIMEOUT_MS=$OCUTALON_E2E_TIMEOUT_MS" >> "$GATE_LOG/npm.env"
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
    file('01-page.spec.ts', [floorTest, unbuilt('the chat panel and the composer', '2.5'), unbuilt('the demo guide lists the steps', '4.7')]),
    file('02-watch.spec.ts', [unbuilt('the watch prompt gets its reply', '4.7')]),
    file('03-reminder.spec.ts', [unbuilt('the reminder prompt is confirmed', '4.7')]),
    file('04-incident.spec.ts', [unbuilt('one incident card awaits approval', '11.1')]),
    file('05-approval.spec.ts', [unbuilt('Approve on the simulated phone', '11.1')]),
    file('06-trace.spec.ts', [unbuilt('the trace link opens Visual Trace', '4.7')]),
  ];
}
const write = (name, list) => writeFileSync(join(out, `${name}.json`), JSON.stringify({ suites: list, errors: [], stats: {} }));

write('green', suites());
write('floor-skipped', suites(floor('skipped', 'Story 4.7 turns this on')));
write('floor-failed', suites(floor('failed')));
{
  const list = suites();
  list[2].specs.push(spec('the reminder row appears', 'skipped'));
  write('no-story', list);
}
{
  const list = suites();
  list.push(file('07-extra.spec.ts', [unbuilt('a part', '4.7')]));
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
expect "unit: a floor test that passed and unbuilt parts that skipped give exit 0 and the PASS line" 0 \
  "PASS the demo path: Playwright and the step summary both passed" \
  "STEP 1 page: partly skipped, 1 passed, 2 skipped (Story 2.5: the chat panel and the composer; Story 4.7: " \
  "STEP 2 watch: skipped, 0 passed, 1 skipped (Story 4.7: " \
  "STEP 6 trace: skipped, 0 passed, 1 skipped (Story 4.7: " \
  "DEMO-PATH 1 of 6 steps ran (1 partly skipped), 7 skipped, 0 failed; floor 1 of 1 passed" \
  "  Running tests using 1 worker" \
  "test-demo-path: all checks passed"
if [ "$(cat "$log/first.max" 2> /dev/null)" = 900 ]; then
  pass "unit: the first start waits 900 s for the start's log, so a start ready after 720 s can still warn (AD-23)"
else
  fail "unit: the first start waits '$(cat "$log/first.max" 2> /dev/null)' s, not 900"
fi
if ! grep -qE '^STEP [0-9] [a-z]+: passed' "$out"; then
  pass "unit: no step whose parts only skipped is read as passed"
else
  fail "unit: a skipped step is read as passed"
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
  && [ "${timeout_ms:-0}" -gt 500000 ] && [ "${timeout_ms:-0}" -le 520000 ]; then
  pass "unit: Playwright runs once, with the stack's URL, a report path, and the deadline's remaining time less 20 s"
else
  fail "unit: the Playwright call is wrong ($(tr '\n' ' ' < "$log/npm.env" 2> /dev/null); calls $(cat "$log/npm.calls" 2> /dev/null | wc -l | tr -d ' '))"
fi

# --- the unit: a red demo path ---

run_unit floor-skipped 0
expect "unit: a skipped floor test fails the unit although Playwright exits 0" 1 \
  "STEP 1 page: skipped, 0 passed, 3 skipped" \
  'FAIL floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) was skipped' \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1" \
  "test-demo-path: 1 check(s) failed"
absent "unit: a skipped floor test draws no PASS for the demo path" "PASS the demo path"

run_unit floor-failed 1
expect "unit: a failed floor test fails the unit, and step 1 reads failed" 1 \
  "STEP 1 page: failed, 0 passed, 2 skipped, 1 failed" \
  'FAIL floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) failed' \
  "FAIL the demo path: Playwright exit 1, the step summary exit 1"

run_unit no-story 0
expect "unit: a skip that names no story fails the unit although Playwright exits 0" 1 \
  '03-reminder.spec.ts "the reminder row appears": its skip names no story' \
  "FAIL the demo path: Playwright exit 0, the step summary exit 1"

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

run_unit green 0 GATE_DEADLINE=45
expect "unit: a deadline with under 60 s left fails the unit before the browser starts" 1 "s are left of the deadline: too little for the browser run"
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
  "UNIT live:demo-path failed" "UNIT live:sign-in passed" "GROUP browser failed: live:demo-path"
absent "group: a red demo path draws no GROUP passed line" "GROUP browser passed"

run_group floor-skipped 0
expect "group: a skipped floor test makes the browser group exit 1 although Playwright exits 0" 1 \
  "UNIT live:demo-path failed" "GROUP browser failed: live:demo-path"

run_group green 0 GATE_UNIT_RC=1
expect "group: a red unit other than the demo path makes the group exit 1 and names it" 1 \
  "UNIT live:demo-path passed" "UNIT live:sign-in failed" "GROUP browser failed: live:sign-in"

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
