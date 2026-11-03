#!/usr/bin/env bash
# Live test of REL-2's online run and the isolation of the online demo's visitors (Story 29.4; AD-4, AD-11, AD-12, AD-13, AD-15, AD-26;
# FR-40): builds the image and starts it in one throwaway compose project with the online-demo flag on and the test start values of
# docker/tests/lib-online.sh (the units of test-online-demo.sh, test-online-session.sh and test-online-allowance.sh share them). In this order:
#   - the start: the log ends ready, and the public flag is on;
#   - the model keys of the three runners are pointed at the CI mock (keys_point of lib-online.sh): without them every decision is the no_key
#     fallback, and no incident would raise an approval request;
#   - the browser step: the project online-demo-path of web/playwright.config.ts (web/e2e-online/demo-path/) as the demo account, on the CI
#     mock's outcomes (OCUTALON_DEMO_PATH_MODEL=mock, whatever the caller's shell exports):
#       step 1 (the splash and the sign-in), steps 2 to 5 (one visitor's journey through the step functions of web/e2e/support/demo-path.ts,
#       which the web run's 02 to 05 call too: the guide's own Send for the watch and for the reminder, Break the feed and the incident awaiting
#       approval, and Approve on the simulated phone to the result), step 6 (the trace link opens Visual Trace at the turn, signed in, with its
#       agent steps and the cost), and "second visitor" (A and B each watch Orders through the guide's Send and A presses Break the feed:
#       A's incident, notice and approval request reach only A, B's page, /state and /events get nothing, B's answer to A's request is
#       refused, and A answers on its simulated phone);
#   - the report check (with no arguments): the JSON report holds exactly seven passed cases (steps 1 to 6 and the second visitor) and
#     three skipped ones, the paired chat and message search cases of Story 31.4, each with its skip text. A case that is skipped without
#     its text, or one that is missing or extra, fails the unit. With arguments (a mutation run: -g <title>) only those cases run and the
#     set check is skipped;
#   - the load phase (Story 29.8; rows L1 and L2 of its spec), which runs the author's release/demo-load.sh against this throwaway with the
#     keys at the mock: the proxy address is set to the address that IRIS sees for this host's requests (host_address, set_proxy of
#     lib-online.sh), each visitor sends its own X-Forwarded-For, and the address is put back to its start value after the phase. It needs
#     150 s of the deadline left, else it fails saying so, and it waits up to 150 s for the licence units to come back to the reading the
#     unit took after the start. The visitors send the guide's own watch prompt, which the mock answers for the Chat and Triage agents
#     alike (AD-22, U-194). L1: 6 visitors with 10 turns (5 drive the demo path, one only signs in; the one more visitor is refused as
#     busy, by the visitor count): IRIS gains 5 Turn rows and 5 resolved Incident rows, each visitor address has one counter row and the one
#     more visitor's has none, and afterwards the status is not busy and the units are at the reading of the start. L2 (DW-286): 3 visitors
#     with Visual Trace open, with a units command that reads $SYSTEM.License.InstanceConnections() and LUConsumed(): each sign-in reads
#     the baseline, each visitor's two trace pages add 2 connections, the load reads the baseline plus 6, and the sign-out brings the
#     baseline back. It runs whatever the browser step ran (-g "step 1" runs the one case and then the phase). The caller's
#     OCUTALON_LOAD_WATCH_TEXT is cleared, so the load always sends the guide's own prompt.
#   - MEASURED lines: the browser step's seconds, the load phase's readings and seconds, and the unit's seconds.
# Every wait ends by the overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default; run the unit with a longer one when the machine is slow);
# the browser run's global timeout is what is left of it minus 20 s. The project is removed by the EXIT trap, and no password is printed.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs docker compose, the build 154 base image (IRIS_IMAGE), Node 24.15 or
# later, the built web bundle and Chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-online.sh"
live_start online-demo-path
live_web_port || exit 1
root=$(cd "$(dirname "$0")/../.." && pwd)

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

# units_reading: "<connections> <licence units>" of the instance, read through a terminal session (which holds one connection and one
# unit itself, so the baseline of an idle stack reads 1 1). $tmp/units.sh prints it for release/demo-load.sh's units command.
printf '%s\n' '#!/bin/sh' \
  "printf '%s\\n' 'Write !,\"CHK|u|\",\$SYSTEM.License.InstanceConnections(),\" \",\$SYSTEM.License.LUConsumed()' 'Halt' | docker exec -i $cid iris session IRIS -U OCUTALON 2> /dev/null | tr -d '\\r' | sed -n 's/.*CHK|u|//p' | head -n 1" > "$tmp/units.sh"
units_reading() { sh "$tmp/units.sh"; }
units_start=$(units_reading)
echo "MEASURED Story 29.8: the units after the start read '$units_start' (connections, licence units)"

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
    OCUTALON_DEMO_PATH_MODEL=mock \
    npm --prefix web run e2e:online-demo-path -- "$@" > "$e2e_log" 2>&1
}

# report_check <report>: the cases of the JSON report by their ends. It prints one FAIL line for each defect and nothing when the report
# holds exactly the seven passed cases (steps 1 to 6 and the second visitor) and the three skipped ones of Story 31.4, each skipped case
# with its "Story <id> turns this on" text.
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
    const wanted = [/^step 1:/, /^step 2:/, /^step 3:/, /^step 4:/, /^step 5:/, /^step 6:/, /^second visitor:/];
    for (const re of wanted) {
      const hits = passed.filter((t) => re.test(t));
      if (hits.length !== 1) problems.push("wanted exactly one passed case matching " + re + ", found " + hits.length);
    }
    if (passed.length !== wanted.length) problems.push("wanted " + wanted.length + " passed cases, found " + passed.length + ": " + passed.join(" | "));
    const skipped = cases.filter((c) => c.status === "skipped");
    const bystory = { "31.4": 0 };
    for (const c of skipped) {
      const text = c.notes.find((n) => /^Story \d+\.\d+ turns this on$/.test(n)) ?? "";
      const story = (/^Story (\d+\.\d+)/.exec(text) ?? [])[1];
      if (story === undefined || !(story in bystory)) problems.push("the skipped case \"" + c.title + "\" has no \"Story <id> turns this on\" text of 31.4 (" + c.notes.join("; ") + ")");
      else bystory[story] += 1;
    }
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
      pass "the report holds the seven passed cases (steps 1 to 6 and the second visitor) and the three skipped ones of Story 31.4, each with its skip text"
    else
      printf '%s\n' "$problems" | redact | sed 's/^/  /'
      fail "the report does not hold exactly the seven passed and the three skipped cases"
    fi
  fi
fi

# --- the load phase (Story 29.8) ---

# table_counts: "<Turn rows> <Incident rows> <resolved Incident rows>".
table_counts() {
  session_value OCUTALON rows3 << 'OS'
Set a=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Turn") Do a.%Next()
Set b=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Incident") Do b.%Next()
Set c=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Incident WHERE State = 'resolved'") Do c.%Next()
Write !,"CHK|rows3|",a.%GetData(1)," ",b.%GetData(1)," ",c.%GetData(1)
Halt
OS
}

# load_script <forwarded addresses> <units command or ""> <argument>...: runs release/demo-load.sh against this stack, which sends the
# guide's own watch prompt (the mock answers it for both the Chat and the Triage agent, U-194); standard output to $tmp/load.out and
# standard error to $tmp/load.err, the exit code in load_rc.
load_script() {
  local fwd=$1 units=$2
  shift 2
  (
    unset OCUTALON_GATE_USER OCUTALON_GATE_PASSWORD OCUTALON_LOAD_INTERFACES OCUTALON_LOAD_UNITS_COMMAND OCUTALON_LOAD_WATCH_TEXT
    export OCUTALON_LOAD_FORWARDED_FOR="$fwd"
    if [ -n "$units" ]; then export OCUTALON_LOAD_UNITS_COMMAND="$units"; fi
    bash "$root/release/demo-load.sh" "$base" "$@" > "$tmp/load.out" 2> "$tmp/load.err" < /dev/null
  )
  load_rc=$?
}

# wait_baseline: waits up to 150 s (and while the deadline allows) for the plain status to read not busy and the units to read as after the
# start (the browser step's trace tabs leave their connections for about 2 minutes). Prints the seconds it waited.
wait_baseline() {
  local waited=0
  while { [ "$(status_read)" != "false none 200" ] || [ "$(units_reading)" != "$units_start" ]; } && [ "$waited" -lt 150 ] && [ $((deadline - SECONDS)) -gt 60 ]; do
    sleep 5
    waited=$((waited + 5))
  done
  echo "$waited"
}

load_phase() {
  local host_ip waited t0 before after i a rows_ok load_lines bc bu k first second
  if ! printf '%s\n' "$units_start" | grep -Eq '^[0-9]+ [0-9]+$'; then
    fail "the load phase: the units after the start could not be read ('$units_start')"
    return
  fi
  host_ip=$(host_address)
  if [ -z "$host_ip" ] || [ "$(set_proxy "$host_ip")" != "$host_ip" ]; then
    fail "the load phase: the host's address could not be derived ('${host_ip:-}') or the proxy address could not be set"
    return
  fi
  echo "MEASURED Story 29.8: the proxy address is the host's, derived from the container's default gateway"
  waited=$(wait_baseline)
  if [ "$(status_read)" = "false none 200" ] && [ "$(units_reading)" = "$units_start" ]; then
    pass "the load phase: the status is not busy and the units read '$units_start' again (waited $waited s)"
  else
    fail "the load phase: after $waited s the status reads '$(status_read)' and the units '$(units_reading)' (the start: '$units_start')"
    return
  fi

  # L1: case 1.
  before=$(table_counts)
  t0=$SECONDS
  load_script "198.51.100.81 198.51.100.82 198.51.100.83 198.51.100.84 198.51.100.85 198.51.100.86 198.51.100.87" "" --visitors 6 --max-turns 10
  echo "MEASURED Story 29.8: L1 took $((SECONDS - t0)) s (exit $load_rc)"
  grep -E '^(VISITOR|EXTRA|TURNS|demo-load)' "$tmp/load.out" | sed 's/^/  /'
  grep -E '^VISITOR' "$tmp/load.out" | sed -n 's/^VISITOR \([0-9]*\) .* notice=\([0-9-]*\) .*/MEASURED Story 29.8: L1 visitor \1 notice \2 s/p'
  if [ "$load_rc" = 0 ]; then pass "L1: the script exits 0"; else fail "L1: the script exits $load_rc: $(tail -n 3 "$tmp/load.err" | tr '\n' '|')"; fi
  if [ "$(grep -Ec '^VISITOR [1-5] PASS signin=ok path=driven turns=2 notice=([0-9]|[1-5][0-9]|60) fix=resolved ' "$tmp/load.out")" = 5 ] \
    && [ "$(grep -c '^VISITOR 6 PASS signin=ok path=signed-in ' "$tmp/load.out")" = 1 ]; then
    pass "L1: five driven visitors pass with a notice within 60 s and the incident resolved, and one signed-in visitor passes"
  else
    fail "L1: the visitor lines are not five driven PASS lines and one signed-in PASS line"
  fi
  if grep -q '^EXTRA PASS status=busy splash=busy signin=busy$' "$tmp/load.out"; then pass "L1: the one more visitor is busy by the visitor count in the status, the splash and the sign-in"; else fail "L1: $(grep '^EXTRA' "$tmp/load.out")"; fi
  after=$(table_counts)
  echo "MEASURED Story 29.8: L1 Turn, Incident and resolved Incident rows: before '$before', after '$after'"
  set -- $before $after
  if [ "$#" = 6 ] && [ $(($4 - $1)) = 5 ] && [ $(($5 - $2)) = 5 ] && [ $(($6 - $3)) = 5 ]; then
    pass "L1: IRIS gained 5 Turn rows, 5 Incident rows and 5 resolved Incident rows"
  else
    fail "L1: the table counts went from '$before' to '$after' (wanted +5 of each)"
  fi
  rows_ok=1
  for i in 1 2 3 4 5 6; do [ "$(counter_rows "198.51.100.8$i")" = 1 ] || rows_ok=0; done
  if [ "$rows_ok" = 1 ] && [ "$(counter_rows 198.51.100.87)" = 0 ]; then pass "L1: each visitor address has one counter row and the one more visitor's has none"; else fail "L1: the counter rows by address are not 1,1,1,1,1,1 and 0"; fi
  if [ "$(status_read)" = "false none 200" ] && [ "$(units_reading)" = "$units_start" ]; then
    pass "L1: afterwards the plain status is not busy and the units read '$units_start'"
  else
    fail "L1: afterwards the status reads '$(status_read)' and the units '$(units_reading)'"
  fi

  # L2: case 2, DW-286.
  waited=$(wait_baseline)
  if [ "$(status_read)" != "false none 200" ] || [ "$(units_reading)" != "$units_start" ]; then
    fail "L2: the baseline was not back after $waited s (the status reads '$(status_read)', the units '$(units_reading)'), so the readings would prove nothing"
    return
  fi
  t0=$SECONDS
  load_script "198.51.100.91 198.51.100.92 198.51.100.93 198.51.100.94" "sh $tmp/units.sh" --visitors 3 --trace --max-turns 6
  echo "MEASURED Story 29.8: L2 took $((SECONDS - t0)) s (exit $load_rc)"
  grep -E '^(VISITOR|EXTRA|UNITS|TURNS|demo-load)' "$tmp/load.out" | sed 's/^/  /'
  grep -E '^(VISITOR|UNITS)' "$tmp/load.out" | sed -n 's/^VISITOR \([0-9]*\) .* units=\([^ ]*\) .*/MEASURED Story 29.8: L2 visitor \1 readings (connections\/units, at sign-in then after its trace pages) \2/p; s/^UNITS /MEASURED Story 29.8: L2 UNITS /p'
  if [ "$load_rc" = 0 ]; then pass "L2: the script exits 0"; else fail "L2: the script exits $load_rc: $(tail -n 3 "$tmp/load.err" | tr '\n' '|')"; fi
  if [ "$(grep -Ec '^VISITOR [1-3] PASS signin=ok path=driven .* trace=2 ' "$tmp/load.out")" = 3 ] && grep -q '^EXTRA PASS status=busy splash=busy signin=busy$' "$tmp/load.out"; then
    pass "L2: three visitors pass with trace=2 and the one more visitor is busy at the trace connections"
  else
    fail "L2: $(grep -E '^(VISITOR|EXTRA)' "$tmp/load.out" | cut -c1-100 | tr '\n' '|')"
  fi
  bc=${units_start%% *}
  bu=${units_start##* }
  rows_ok=1
  for k in 1 2 3; do
    a=$(sed -n "s/^VISITOR $k .* units=\([^ ]*\) .*/\1/p" "$tmp/load.out")
    first=${a%%,*}
    second=${a##*,}
    [ "$first" = "$bc/$bu" ] || rows_ok=0
    [ "${second%%/*}" = $((bc + 2 * k)) ] || rows_ok=0
  done
  if [ "$rows_ok" = 1 ]; then pass "L2: each sign-in reads the baseline, and each visitor's two trace pages add 2 connections (DW-286)"; else fail "L2: the readings per visitor do not rise by 0 at the sign-in and by 2 after the pages (the baseline is '$units_start')"; fi
  if grep -q "^UNITS before=$bc/$bu load=$((bc + 6))/[0-9]* after=$bc/$bu\$" "$tmp/load.out"; then
    pass "L2: the load reads the baseline plus 6 connections, and the sign-out brings the baseline back"
  else
    fail "L2: $(grep '^UNITS' "$tmp/load.out") (the baseline is '$units_start')"
  fi
}

if [ $((deadline - SECONDS)) -lt 150 ]; then
  fail "the load phase: only $((deadline - SECONDS)) s of the deadline are left (it needs 150 s)"
else
  load_started=$SECONDS
  load_phase
  # The proxy address goes back to its start value on every path that reached the phase.
  if [ "$(set_proxy "$proxy_start")" = "$proxy_start" ]; then
    pass "the load phase: the proxy address is back at its start value"
  else
    fail "the load phase: the proxy address could not be put back to its start value"
  fi
  echo "MEASURED Story 29.8: the load phase took $((SECONDS - load_started)) s; the unit has run $SECONDS s at this point"
fi

echo "MEASURED Story 29.4: the unit took $SECONDS s"

if [ "$fails" -ne 0 ]; then
  echo "test-online-demo-path: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-online-demo-path: all checks passed"
