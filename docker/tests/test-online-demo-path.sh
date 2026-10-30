#!/usr/bin/env bash
# Live test of REL-2's online run and the isolation of the online demo's visitors (Story 29.4; AD-4, AD-11, AD-12, AD-13, AD-15, AD-26;
# FR-40): builds the image and starts it in one throwaway compose project with the online-demo flag on and the test start values of
# docker/tests/lib-online.sh (the units of test-online-demo.sh, test-online-session.sh and test-online-allowance.sh share them). In this order:
#   - the start: the log ends ready, and the public flag is on;
#   - the model keys of the three runners are pointed at the CI mock (keys_point of lib-online.sh): without them every decision is the no_key
#     fallback, and no incident would raise an approval request;
#   - the browser step: the project online-demo-path of web/playwright.config.ts (web/e2e-online/demo-path/) as the demo account:
#       step 1 (the splash and the sign-in), step 6 (the trace link opens Visual Trace at the turn, signed in, with its agent steps and the
#       cost), and "second visitor" (A and B each watch Orders and A presses Break the feed: A's incident, notice and approval request reach
#       only A, B's page, /state and /events get nothing, B's answer to A's request is refused, and A answers on its simulated phone);
#   - the report check (with no arguments): the JSON report holds exactly three passed cases (step 1, step 6, the second visitor) and seven
#     skipped ones, each with its own skip text: steps 2 to 5 wait for Story 11.1 and the paired chat and message search cases for Story
#     31.4. A case that is skipped without its text, or one that is missing or extra, fails the unit. With arguments (a mutation run:
#     -g <title>) only those cases run and the set check is skipped;
#   - MEASURED lines: the browser step's seconds and the unit's seconds.
# Every wait ends by the overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default; run the unit with a longer one when the machine is slow);
# the browser run's global timeout is what is left of it minus 20 s. The project is removed by the EXIT trap, and no password is printed.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs docker compose, the build 154 base image (IRIS_IMAGE), Node 24.15 or
# later, the built web bundle and Chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-demo-path
live_web_port || exit 1

base="http://127.0.0.1:$web_port"
online_values
resume_ref=
online_override

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log" | redact
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200 | redact
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"

# --- the start ---

check_session "the online-demo flag is on" OCUTALON \
  "CHK|flag|1" \
  'Write !,"CHK|flag|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")' \
  'Halt'

# --- the keys ---

if [ "$(keys_point)" = 1 ]; then
  pass "the runners' model keys point at the CI mock"
else
  die "the runners' model keys could not be pointed at the CI mock"
fi

# --- the browser step ---

e2e_log="$tmp/e2e.log"
e2e_json="$tmp/e2e.json"
show_log() { tail -n "$1" "$e2e_log" | redact | sed 's/^/  /'; }
run_e2e() {
  local left=$((deadline - SECONDS))
  OCUTALON_URL="$base" \
    OCUTALON_DEMOACCOUNT_USER="$demo_user" \
    OCUTALON_DEMOACCOUNT_PASSWORD="$demo_password" \
    OCUTALON_READONLYACCOUNT_USER="$readonly_user" \
    OCUTALON_READONLYACCOUNT_PASSWORD="$readonly_password" \
    OCUTALON_E2E_IRIS_CONTAINER="$cid" \
    OCUTALON_E2E_TIMEOUT_MS=$(((left - 20) * 1000)) \
    OCUTALON_E2E_JSON="$e2e_json" \
    npm --prefix web run e2e:online-demo-path -- "$@" > "$e2e_log" 2>&1
}

# report_check <report>: the cases of the JSON report by their ends. It prints one FAIL line for each defect and nothing when the report
# holds exactly the three passed cases and the seven skipped ones (four of Story 11.1, three of Story 31.4), each skipped case with its
# "Story <id> turns this on" text.
report_check() {
  node -e '
    const fs = require("node:fs");
    const problems = [];
    let report;
    try { report = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { console.log("the report is missing or not JSON: " + e.message); process.exit(0); }
    const cases = [];
    const walk = (suite) => {
      for (const spec of suite.specs ?? []) {
        for (const test of spec.tests ?? []) {
          const results = test.results ?? [];
          const status = results.length > 0 ? results[results.length - 1].status : "notRun";
          const notes = [...(test.annotations ?? []), ...results.flatMap((r) => r.annotations ?? [])]
            .filter((a) => a.type === "skip" || a.type === "fixme").map((a) => a.description).filter((t) => typeof t === "string" && t !== "");
          cases.push({ title: spec.title, status, notes });
        }
      }
      for (const child of suite.suites ?? []) walk(child);
    };
    for (const suite of report.suites ?? []) walk(suite);
    for (const error of report.errors ?? []) problems.push("Playwright reported an error: " + String(error.message ?? error).split("\n")[0]);
    const passed = cases.filter((c) => c.status === "passed").map((c) => c.title);
    const wanted = [/^step 1:/, /^step 6:/, /^second visitor:/];
    for (const re of wanted) {
      const hits = passed.filter((t) => re.test(t));
      if (hits.length !== 1) problems.push("wanted exactly one passed case matching " + re + ", found " + hits.length);
    }
    if (passed.length !== wanted.length) problems.push("wanted " + wanted.length + " passed cases, found " + passed.length + ": " + passed.join(" | "));
    const skipped = cases.filter((c) => c.status === "skipped");
    const bystory = { "11.1": 0, "31.4": 0 };
    for (const c of skipped) {
      const text = c.notes.find((n) => /^Story \d+\.\d+ turns this on$/.test(n)) ?? "";
      const story = (/^Story (\d+\.\d+)/.exec(text) ?? [])[1];
      if (story === undefined || !(story in bystory)) problems.push("the skipped case \"" + c.title + "\" has no \"Story <id> turns this on\" text of 11.1 or 31.4 (" + c.notes.join("; ") + ")");
      else bystory[story] += 1;
    }
    if (bystory["11.1"] !== 4) problems.push("wanted 4 skipped cases of Story 11.1, found " + bystory["11.1"]);
    if (bystory["31.4"] !== 3) problems.push("wanted 3 skipped cases of Story 31.4, found " + bystory["31.4"]);
    for (const c of cases.filter((x) => x.status !== "passed" && x.status !== "skipped")) problems.push("the case \"" + c.title + "\" ended " + c.status);
    if (cases.length !== 10) problems.push("wanted 10 cases in all, found " + cases.length);
    for (const p of problems) console.log(p);
  ' "$1"
}

browser_started=$SECONDS
if [ $((deadline - SECONDS)) -lt 120 ]; then
  fail "the browser step: only $((deadline - SECONDS)) s of the deadline are left"
else
  run_e2e "$@"
  e2e_status=$?
  echo "MEASURED Story 29.4: the browser step took $((SECONDS - browser_started)) s; the unit has run $SECONDS s at this point"
  grep -h '^MEASURED ' "$e2e_log" | redact
  if [ "$e2e_status" -eq 0 ]; then
    show_log 20
    pass "the specs of the online-demo-path project pass ($(grep -Eo '[0-9]+ passed' "$e2e_log" | tr '\n' ' ' | sed 's/ $//'))"
  else
    show_log 80
    if grep -q "Executable doesn't exist" "$e2e_log"; then
      echo "  a browser is missing: run npx --prefix web playwright install chromium"
    fi
    fail "the specs of the online-demo-path project failed (exit $e2e_status)"
  fi
  if [ "$#" -eq 0 ] && [ "$e2e_status" -eq 0 ]; then
    problems=$(report_check "$e2e_json") || problems="the report check could not run"
    if [ -z "$problems" ]; then
      pass "the report holds the three passed cases and the seven skipped ones, four of Story 11.1 and three of Story 31.4, each with its skip text"
    else
      printf '%s\n' "$problems" | redact | sed 's/^/  /'
      fail "the report does not hold exactly the three passed and the seven skipped cases"
    fi
  fi
fi

echo "MEASURED Story 29.4: the unit took $SECONDS s"

if [ "$fails" -ne 0 ]; then
  echo "test-online-demo-path: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-demo-path: all checks passed"
