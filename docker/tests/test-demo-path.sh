#!/usr/bin/env bash
# Live test of Story 0.8, the demo-path test (REL-2; UJ-1 and AD-23): builds the image and starts it in one fresh throwaway
# compose project with the CI override, as a judge's first start leaves it, then
#   - times that first start and prints FIRST-START engine=<arch> build=<s>s ready=<s>s (the figure that the README quotes), and
#     WARN when it is ready after more than 12 minutes (a decision for the author, AD-23, not a failure);
#   - takes the audit mark, then runs the Playwright project demo-path in a real browser: the eight step specs
#     web/e2e/demo-path/0<n>-<id>.spec.ts, one ordered journey of the README account on the real components: UJ-1's six (Story 11.1: the
#     watch, the reminder, Break the feed, Approve on the simulated phone and the trace), then 07 and 08 (Story 11.10: Run again, the
#     refusal on the mock only, the rejection and the replay, then the two sample emails), with the model keys pointed at the CI mock
#     (by the specs themselves; 08 puts them back). OCUTALON_DEMO_PATH_MODEL (Story 11.7) picks the model the specs check against: `mock` (also when
#     unset) checks the outcomes and the mock's texts; `real` checks each decision by its shape only and makes the specs leave the
#     keys alone, so a dry run of it on this stack prints `MODEL real: a dry run on the CI mock` and points the keys here first,
#     through RunnerFixture.PointKeys, before the audit mark (FAIL and stop when that does not answer OK); any other value goes to
#     the specs, which fail before their first step;
#     Step 1's @floor test signs in with the README account and waits for the page to load its snapshot. Only the Telegram parts
#     (web/e2e/demo-path/telegram-*.spec.ts) are declared skipped, and each skip names the story that turns it on;
#   - prints the step summary of web/scripts/demo-path-summary.mjs --only-telegram-skips: one STEP line per step (passed, partly
#     skipped, skipped or failed) and a DEMO-PATH line. A skipped step is never reported as passed; a failed test, a skip of a
#     numbered step file, a skip that names no story, a @floor test that did not pass, a missing step spec and an unknown spec
#     file fail the unit;
#   - reads the IRIS audit log since the mark (AD-17, FR-9), polling up to OCUTALON_AUDIT_POLL seconds (60 by default, within the
#     deadline), and checks that it holds the answered Approval entry of the README session's request (approved, from the phone) and
#     the resend's Action entry that names that request, that each entry's data holds exactly Bridge.Audit.Shape of its type
#     (with the common members) and no more, and that docker/tests/lib-keys.sh finds no key-like text in either.
# The stack holds only what the first start creates: no fixture user, no seeded event, no rebuilt bundle (ci/iris.sh build made
# it), no model key. The specs send their model requests to the CI mock. The project is unique and publishes its web port only on 127.0.0.1, on the
# first free port of 52800-52819 (or OCUTALON_TEST_WEB_PORT). An EXIT trap removes the project with its volume and images.
# Every wait ends by an overall deadline (OCUTALON_LIVE_DEADLINE, 540 s by default and 1200 s in CI); within it, the first start
# waits up to 900 s for the start's log to end ready and up to 60 s more for Docker to report healthy. The browser run ends 80 s
# before the deadline, which leaves the summary and the audit poll their time.
# Prints one PASS or FAIL line per check; exits 0 only when every check passes.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), Node 24.15 or later,
# and the browser: npx --prefix web playwright install chromium.
set -u

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-keys.sh"
live_start t08
live_web_port || exit 1

# --- the first start, timed ---

if ! live_first_start 900; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready"
fi
pass "the first start ended ready"

# --- the demo path: the step specs, then the step summary ---

# A dry run of the real-model switch on the CI mock: the specs of `real` never point the runners' keys (a real key must not be
# touched), so this unit does, once, before anything is marked or run.
if [ "${OCUTALON_DEMO_PATH_MODEL:-mock}" = real ]; then
  echo "MODEL real: a dry run on the CI mock"
  keys_ok=$(printf '%s\n' 'Set sc=##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()' 'Write !,"CHK|keys|",$System.Status.IsOK(sc)' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|keys|//p' | head -n 1)
  if [ "$keys_ok" != 1 ]; then
    die "MODEL real: the runners' keys could not be pointed at the CI mock"
  fi
fi

# The audit mark: the UTC time just before the browser steps, in the format of the audit log's UTCTimeStamp.
audit_mark=$(printf '%s\n' 'Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()' 'Halt' | iris_script OCUTALON | sed -n 's/^CHK|mark|//p' | head -n 1)
if [ -z "$audit_mark" ]; then
  fail "audit: the mark could not be taken before the browser steps"
fi

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 100 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
e2e_log="$tmp/e2e.log"
report="$tmp/demo-path.json"
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_E2E_JSON="$report" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 80) * 1000)) \
  npm --prefix web run e2e:demo-path > "$e2e_log" 2>&1
e2e_status=$?
sed 's/^/  /' "$e2e_log"
if grep -q "Executable doesn't exist" "$e2e_log"; then
  echo "  the browser is missing: run npx --prefix web playwright install chromium"
fi
node web/scripts/demo-path-summary.mjs --only-telegram-skips "$report" > "$tmp/summary.log" 2>&1
summary_status=$?
cat "$tmp/summary.log"
if [ "$e2e_status" -eq 0 ] && [ "$summary_status" -eq 0 ]; then
  pass "the demo path: Playwright and the step summary both passed"
else
  fail "the demo path: Playwright exit $e2e_status, the step summary exit $summary_status"
fi

# --- the audit log: the approval's answered entry and the resend's action entry ---

# audit_script: the ObjectScript that reads the audit log since the mark and prints, as CHK lines, the README session, and for the answered
# Approval entry (approved, from the phone, of that session) and for the Action entry that names its request: how many match, whether the
# first one's data holds exactly Bridge.Audit.Shape of its type, and its data as JSON.
audit_script() {
  sed "s/@MARK@/$audit_mark/" << 'EOF'
Set s=##class(OcuTalon.Data.Session).ForUser("ocutalon",.sc)
Write !,"CHK|session|",s.Ref
Set log="OcuTalon.Test.Bridge.AuditLog",audit="OcuTalon.Bridge.Audit"
Set entries=$ClassMethod(log,"Entries","@MARK@","OcuTalon","Approval","Approval")
Set found=0,ref="",shapeOk=0,json=""
For i=0:1:entries.%Size()-1 { Set d=entries.%Get(i).data  If $IsObject(d) { If (d.sessionRef=s.Ref)&&(d.change="answered")&&(d.outcome="approved")&&(d.channel="phone") { Set found=found+1  If found=1 { Set ref=d.ref,json=d.%ToJSON(),shape=$ClassMethod(audit,"Shape","Approval"),shapeOk=(d.%Size()=$ListLength(shape))  For j=1:1:$ListLength(shape) { If 'd.%IsDefined($List(shape,j)) { Set shapeOk=0 } } } } } }
Set actions=$ClassMethod(log,"Entries","@MARK@","OcuTalon","Action","Action")
Set afound=0,ajson="",ashapeOk=0
For i=0:1:actions.%Size()-1 { Set d=actions.%Get(i).data  If $IsObject(d) { If (ref'="")&&(d.sessionRef=s.Ref)&&(d.approvalRef=ref) { Set afound=afound+1  If afound=1 { Set ajson=d.%ToJSON(),shape=$ClassMethod(audit,"Shape","Action"),ashapeOk=(d.%Size()=$ListLength(shape))  For j=1:1:$ListLength(shape) { If 'd.%IsDefined($List(shape,j)) { Set ashapeOk=0 } } } } } }
Write !,"CHK|approval-found|",found,!,"CHK|approval-shape|",shapeOk,!,"CHK|approval-ref|",ref,!,"CHK|approval-data|",json
Write !,"CHK|action-found|",afound,!,"CHK|action-shape|",ashapeOk,!,"CHK|action-data|",ajson
Halt
EOF
}

# audit_read reads the log once into $tmp/audit.chk; audit_value <name> prints one value of it; audit_entries_found says whether both entries are there.
audit_read() { audit_script | iris_script OCUTALON > "$tmp/audit.chk"; }
audit_value() { sed -n "s/^CHK|$1|//p" "$tmp/audit.chk" | head -n 1; }
audit_has() { [ "$(audit_value "$1")" -ge 1 ] 2> /dev/null; }
audit_entries_found() {
  audit_read
  audit_has approval-found && audit_has action-found
}

if [ -n "$audit_mark" ]; then
  poll=${OCUTALON_AUDIT_POLL:-60}
  left=$((deadline - SECONDS))
  if [ "$poll" -gt "$left" ]; then poll=$left; fi
  if [ "$poll" -lt 0 ]; then poll=0; fi
  audit_entries_found || wait_until "$poll" audit_entries_found || true
  if audit_has approval-found; then
    pass "audit: the answered Approval entry (approved, from the phone) of the README session is in the log"
    printf '%s\n' "$(audit_value approval-data)" > "$tmp/audit-approval.json"
    if [ "$(audit_value approval-shape)" = 1 ]; then
      pass "audit: the Approval entry holds exactly its shape and the common members"
    else
      fail "audit: the Approval entry does not hold exactly Bridge.Audit.Shape(Approval) and the common members"
    fi
    if [ -z "$(key_like "$tmp/audit-approval.json")" ]; then
      pass "audit: no key-like text in the Approval entry"
    else
      fail "audit: the Approval entry holds key-like text"
    fi
  else
    fail "audit: no answered Approval entry (approved, from the phone) of the README session since the mark within $poll s"
  fi
  if audit_has action-found; then
    pass "audit: the resend's Action entry that names the approval request is in the log"
    printf '%s\n' "$(audit_value action-data)" > "$tmp/audit-action.json"
    if [ "$(audit_value action-shape)" = 1 ]; then
      pass "audit: the Action entry holds exactly its shape and the common members"
    else
      fail "audit: the Action entry does not hold exactly Bridge.Audit.Shape(Action) and the common members"
    fi
    if [ -z "$(key_like "$tmp/audit-action.json")" ]; then
      pass "audit: no key-like text in the Action entry"
    else
      fail "audit: the Action entry holds key-like text"
    fi
  else
    fail "audit: no Action entry that names the approval request since the mark within $poll s"
  fi
fi

if [ "$fails" -ne 0 ]; then
  echo "test-demo-path: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-demo-path: all checks passed"
