#!/usr/bin/env bash
# Hermetic test of docker/probe.sh (Story 16.6; matrix rows 10 to 15). The live rows 1 to 9 are the probe phase of test-online-demo.sh.
# One inline Node HTTP server on 127.0.0.1 (a random port) stands in for IRIS: it serves the status, the splash, the sign-in POST (a
# redirect and a session cookie), the shell, the messages, events and session/end routes, picks its variant of each answer from a flags
# file that the test rewrites before every run, and records every request (method, path, query, the headers the rows look at, the body
# and the cookie it set) as one JSON line. Each run is the real docker/probe.sh with two stub commands that append one line per call to
# a shared record file ("alert <outcome> <line>" or "reset") and its own state folder.
#   row 10  the request discipline of a healthy run, with and without a session token on the splash form;
#   row 11  busy from an HTTP 503 at each step, and from the marker header;
#   row 12  no_splash: the local sign-in page, a 404, nothing listening;
#   row 13  the other endings, the command conventions and the state files;
#   row 14  configuration errors: exit 2, one line naming the variable, no request, nothing written;
#   row 15  the file itself.
# The test password is random per run and is never printed. Starts no container. Needs Node and curl.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
probe="$root/docker/probe.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-probe-test.XXXXXX") || exit 1
stub_pid=""
cleanup() {
  if [ -n "$stub_pid" ]; then kill "$stub_pid" 2> /dev/null; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

fails=0
pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

for tool in node curl; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "FAIL $tool is not installed"
    exit 1
  fi
done

user=DemoVisitor
password=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2> /dev/null | head -c 32)
message="Health check from the online demo's probe. Reply with one short sentence."
flags="$tmp/flags"
requests="$tmp/requests.jsonl"
commands="$tmp/commands"
cmd_env="$tmp/cmd-env"
: > "$flags"
: > "$requests"
: > "$commands"

# --- the stub commands ---

cat > "$tmp/alert.sh" <<'EOF'
#!/bin/sh
code=0
case $1 in --exit=*) code=${1#--exit=}; shift ;; esac
echo "alert $1 $2" >> "$PROBE_TEST_RECORD"
exit "$code"
EOF
cat > "$tmp/reset.sh" <<'EOF'
#!/bin/sh
code=0
case $1 in --exit=*) code=${1#--exit=}; shift ;; esac
echo "reset" >> "$PROBE_TEST_RECORD"
exit "$code"
EOF
chmod 755 "$tmp/alert.sh" "$tmp/reset.sh"

# --- the stub server ---

STUB_USER="$user" STUB_PASS="$password" node - "$flags" "$requests" > "$tmp/port" 2> "$tmp/stub.err" <<'EOF' &
const http = require("http");
const fs = require("fs");
const [flagsFile, recordFile] = process.argv.slice(2);
const user = process.env.STUB_USER;
const pass = process.env.STUB_PASS;
const issued = new Set();
const authed = new Set();
let counter = 0;
let polls = 0;
let client = "";
let lastText = "";
const readFlags = () => new Set(fs.readFileSync(flagsFile, "utf8").split(/\s+/).filter(Boolean));
const shell = "<!doctype html><html><head><title>OcuTalon</title></head><body><app-root></app-root></body></html>";
const splash = (f) => {
  const token = f.has("splash_token") ? '<input type="hidden" name="IRISSessionToken" value="tok-9f2c">' : "";
  return `<!DOCTYPE html><html><head><title>Try OcuTalon</title></head><body><form name="Login" method="post" action="/ocutalon/">${token}<input type="text" name="IRISUsername" value="PrefilledVisitor"><input type="text" name="IRISPassword" value="published"><button name="IRISLogin" value="Sign in and start">Sign in and start</button></form></body></html>`;
};
const local = '<!DOCTYPE html><html><head><title>Sign in &middot; OcuTalon</title></head><body><form method="post"><input name="IRISUsername"><input type="password" name="IRISPassword"></form></body></html>';
const event = (seq, stream, type, payload) => ({ seq, stream, ts: "2026-10-26T10:00:00Z", type, payload });
const decision = (reason) => ({ ref: "d1", kind: "triage", outcome: "reply", fallback: reason !== "", fallbackReason: reason });
const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf8");
    const url = new URL(req.url, "http://stub");
    const f = readFlags();
    const cookie = req.headers.cookie || "";
    const found = /(?:^|; )CSPSESSIONID=([^;]*)/.exec(cookie);
    const sid = found ? found[1] : "";
    const h = req.headers;
    const rec = {
      method: req.method,
      path: url.pathname,
      query: url.search.replace(/^\?/, ""),
      headers: { cookie: h.cookie || "", authorization: h.authorization || "", contentType: h["content-type"] || "", request: h["x-ocutalon-request"] || "", origin: h.origin || "", host: h.host || "" },
      body,
      setCookie: "",
    };
    const send = (code, headers, text) => {
      rec.setCookie = headers["Set-Cookie"] || "";
      fs.appendFileSync(recordFile, JSON.stringify(rec) + "\n");
      res.writeHead(code, headers);
      res.end(text);
    };
    const html = { "Content-Type": "text/html" };
    const json = { "Content-Type": "application/json" };
    const p = url.pathname;
    if (req.method === "GET" && p === "/ocutalon/public/status") {
      polls = 0;
      client = "";
      if (f.has("status_503")) return send(503, html, "busy");
      return send(200, json, JSON.stringify({ ready: true, nextReset: "2026-10-26T12:00:00Z", busy: f.has("status_busy"), lastReset: null, lastResetKind: null }));
    }
    if (req.method === "GET" && p === "/ocutalon/") {
      if (authed.has(sid)) return send(200, html, f.has("shell_other") ? "<!doctype html><html><head><title>Something else</title></head><body>hello</body></html>" : shell);
      if (f.has("splash_hang")) return;
      if (f.has("splash_503")) return send(503, html, "busy");
      if (f.has("splash_404")) return send(404, html, "not found");
      if (f.has("splash_local")) return send(200, html, local);
      counter += 1;
      const id = "s" + counter;
      issued.add(id);
      const headers = { ...html, "Set-Cookie": `CSPSESSIONID=${id}; path=/ocutalon/; HttpOnly` };
      if (f.has("splash_marker")) headers["X-OcuTalon-Busy"] = "1";
      return send(200, headers, splash(f));
    }
    if (req.method === "POST" && p === "/ocutalon/") {
      if (f.has("signin_503")) return send(503, html, "busy");
      const form = new URLSearchParams(body);
      const good = issued.has(sid) && form.get("IRISUsername") === user && form.get("IRISPassword") === pass && !f.has("signin_form_back");
      if (!good) return send(200, html, splash(f));
      authed.add(sid);
      return send(303, { ...html, Location: "/ocutalon/" }, "");
    }
    if (p.startsWith("/ocutalon/api/v1/")) {
      if (!authed.has(sid)) return send(401, json, '{"error":{"code":"signed_out","message":"Sign in first."}}');
      if (req.method === "POST") {
        const ok = /^application\/json/.test(rec.headers.contentType) && rec.headers.request === "1" && rec.headers.origin === "http://" + rec.headers.host;
        if (!ok) return send(400, json, '{"error":{"code":"envelope","message":"The request is not from the page."}}');
      }
      if (req.method === "POST" && p === "/ocutalon/api/v1/messages") {
        if (f.has("msg_503")) return send(503, html, "busy");
        if (f.has("msg_500")) return send(500, json, '{"error":{"code":"server_error","message":"Server error."}}');
        const parsed = JSON.parse(body);
        client = parsed.clientId;
        lastText = parsed.text;
        return send(202, json, JSON.stringify({ clientId: client }));
      }
      if (req.method === "GET" && p === "/ocutalon/api/v1/events") {
        polls += 1;
        if (f.has("events_503_2") && polls === 2) return send(503, html, "busy");
        const events = [
          event(1, "session", "chat.message", { ref: "r1", clientId: client, state: "queued", text: lastText }),
          event(2, "session", "chat.message", { ref: "r1", clientId: client, state: "running", fallbackReason: "", decision: decision("") }),
          event(3, "session", "chat.message", { ref: "r9", clientId: "other-client", state: "done", fallbackReason: "", decision: decision("") }),
          event(7, "instance", "status.conditions", {}),
        ];
        const reason = f.has("decision_daily_cap") ? "daily_cap" : f.has("decision_error") ? "error" : "";
        if (!f.has("events_nodecision") && (polls >= 2 || f.has("decision_first"))) {
          events.push(event(4, "session", "chat.message", { ref: "r1", clientId: client, state: "done", replyText: "ok", fallbackReason: reason, decision: decision(reason) }));
        }
        return send(200, json, JSON.stringify({ epoch: "e1", events }));
      }
      if (req.method === "POST" && p === "/ocutalon/api/v1/session/end") {
        authed.delete(sid);
        return send(204, {}, "");
      }
    }
    return send(404, html, "not found");
  });
});
server.listen(0, "127.0.0.1", () => console.log(server.address().port));
EOF
stub_pid=$!
port=""
for _ in $(seq 1 50); do
  port=$(head -n 1 "$tmp/port" 2> /dev/null)
  if [ -n "$port" ]; then break; fi
  sleep 0.1
done
case $port in '' | *[!0-9]*)
  echo "FAIL the stub server did not start: $(head -c 300 "$tmp/stub.err")"
  exit 1
  ;;
esac
url="http://127.0.0.1:$port"
closed_port=$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')

# --- the helpers ---

n_state=0
state=""
# The probe's temporary folders are made under this folder, so that a test can see that none is left.
work_root="$tmp/work"
mkdir -p "$work_root"
# new_state: a fresh state folder, and an empty command record.
new_state() {
  n_state=$((n_state + 1))
  state="$tmp/state.$n_state"
  mkdir -p "$state"
  : > "$commands"
  : > "$cmd_env"
}
# probe_run <flags> [VAR=value | -u VAR]...: one run of the probe against the stub with the flags; leaves the exit code in rc, stdout in
# $tmp/out and stderr in $tmp/err. A VAR=value replaces the base setting; a -u VAR removes the variable (an inner env does it, so that
# the base setting cannot bring it back). With probe_term=1 the run is sent TERM (or the signal in probe_sig) after its first events poll.
# With probe_limit=<s> a run still going after that many seconds is killed (exit 137), so that a probe that hangs cannot hang the test.
probe_run() {
  local args=() unsets=() cmd term_pid
  printf '%s\n' "$1" > "$flags"
  shift
  while [ $# -gt 0 ]; do
    if [ "$1" = -u ]; then
      unsets+=(-u "$2")
      shift 2
    else
      args+=("$1")
      shift
    fi
  done
  : > "$requests"
  cmd=(env OCUTALON_PROBE_URL="$url" OCUTALON_DEMO_USER="$user" OCUTALON_DEMO_PASSWORD="$password"
    OCUTALON_PROBE_ALERT_COMMAND="$tmp/alert.sh" OCUTALON_PROBE_RESET_COMMAND="$tmp/reset.sh"
    OCUTALON_PROBE_STATE_DIR="$state" OCUTALON_PROBE_DECISION_WAIT=2 PROBE_TEST_RECORD="$commands" PROBE_TEST_ENV="$cmd_env" TMPDIR="$work_root" ${args[@]+"${args[@]}"}
    env ${unsets[@]+"${unsets[@]}"} bash "$probe")
  if [ "${probe_term:-}" = 1 ]; then
    "${cmd[@]}" > "$tmp/out" 2> "$tmp/err" < /dev/null &
    term_pid=$!
    for _ in $(seq 1 100); do
      if [ "$(n_requests GET /ocutalon/api/v1/events)" -ge 1 ]; then break; fi
      sleep 0.1
    done
    kill -"${probe_sig:-TERM}" "$term_pid" 2> /dev/null
    wait "$term_pid"
  elif [ -n "${probe_limit:-}" ]; then
    "${cmd[@]}" > "$tmp/out" 2> "$tmp/err" < /dev/null &
    term_pid=$!
    for _ in $(seq 1 "$((probe_limit * 10))"); do
      kill -0 "$term_pid" 2> /dev/null || break
      sleep 0.1
    done
    kill -KILL "$term_pid" 2> /dev/null
    wait "$term_pid"
  else
    "${cmd[@]}" > "$tmp/out" 2> "$tmp/err" < /dev/null
  fi
  rc=$?
}
time_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z '
# expect_run <label> <exit> <log text after the time>: the exit code, one stdout line that is also the log's last line.
expect_run() {
  local got last lines
  got=$(sed 's/^[^ ]* //' "$tmp/out")
  last=$(tail -n 1 "$state/probe.log" 2> /dev/null)
  lines=$(wc -l < "$tmp/out" | tr -d ' ')
  if [ "$rc" = "$2" ] && [ "$got" = "$3" ] && [ "$lines" = 1 ] && [ "$(cat "$tmp/out")" = "$last" ] && grep -Eq "$time_re" "$tmp/out"; then
    pass "$1 ($3, exit $2)"
  else
    fail "$1: exit $rc (wanted $2), '$got' (wanted '$3'), $lines stdout line(s), log's last line '$(printf '%s' "$last" | sed 's/^[^ ]* //')'"
  fi
}
n_calls() { grep -c "^$1" "$commands"; }
n_requests() { grep -c "^{\"method\":\"$1\",\"path\":\"$2\"" "$requests"; }
stored_count() { cat "$state/counted-failures" 2> /dev/null; }
today=$(TZ=UTC0 date +%Y-%m-%d)

# --- row 10: the request discipline ---

verify_requests() {
  EXPECT_URL="$url" EXPECT_USER="$user" EXPECT_PASSWORD="$password" EXPECT_MESSAGE="$message" EXPECT_TOKEN="$1" node - "$requests" <<'EOF'
const fs = require("fs");
const records = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const { EXPECT_URL: url, EXPECT_USER: user, EXPECT_PASSWORD: password, EXPECT_MESSAGE: message, EXPECT_TOKEN: token } = process.env;
const problems = [];
const bad = (text) => problems.push(text);
const seq = records.map((r) => `${r.method} ${r.path}`);
const head = ["GET /ocutalon/public/status", "GET /ocutalon/", "POST /ocutalon/", "GET /ocutalon/", "POST /ocutalon/api/v1/messages"];
if (JSON.stringify(seq.slice(0, 5)) !== JSON.stringify(head)) bad("the first five requests are " + seq.slice(0, 5).join(" | "));
const polls = records.filter((r) => r.method === "GET" && r.path === "/ocutalon/api/v1/events");
if (polls.length < 1) bad("no events poll");
if (seq.slice(5).join("|") !== polls.map(() => "GET /ocutalon/api/v1/events").concat(["POST /ocutalon/api/v1/session/end"]).join("|")) bad("the requests after the message are " + seq.slice(5).join(" | "));
if (problems.length) {
  console.log("PROBLEMS " + problems.join("; "));
  process.exit(0);
}
const [status, splash, signin, shell, message_post] = records;
const splashCookie = (splash.setCookie.match(/CSPSESSIONID=([^;]+)/) || [])[1] || "";
if (!splashCookie) bad("the splash set no session cookie");
if (status.headers.cookie !== "") bad("the status request carried a cookie");
if (splash.headers.cookie !== "") bad("the splash request was not on a fresh jar");
if (!signin.headers.cookie.includes("CSPSESSIONID=" + splashCookie)) bad("the sign-in POST did not carry the splash's session cookie");
const names = [...new URLSearchParams(signin.body).keys()].sort();
const wanted = ["IRISLogin", "IRISPassword", "IRISUsername"].concat(token ? ["IRISSessionToken"] : []).sort();
if (JSON.stringify(names) !== JSON.stringify(wanted)) bad("the sign-in fields are " + names.join(","));
const form = new URLSearchParams(signin.body);
if (form.get("IRISUsername") !== user || form.get("IRISPassword") !== password || form.get("IRISLogin") !== "Sign in") bad("the sign-in field values are not the account's");
if (token && form.get("IRISSessionToken") !== token) bad("the sign-in did not post the splash's session token");
if (signin.headers.contentType !== "application/x-www-form-urlencoded") bad("the sign-in is not URL-encoded");
if (signin.headers.origin !== url) bad("the sign-in POST has no matching Origin");
records.forEach((r, i) => {
  if (r.headers.authorization !== "") bad(`request ${i} carries an Authorization header`);
  if (/IRIS/i.test(r.query)) bad(`request ${i} has an IRIS field in its query`);
  if (i !== 2 && (r.body.includes(password) || /IRIS(Username|Password|Login)/.test(r.body))) bad(`request ${i} carries credentials outside the sign-in POST`);
  if (r.path.startsWith("/ocutalon/api/") && !r.headers.cookie.includes("CSPSESSIONID=" + splashCookie)) bad(`request ${i} (an API call) has no session cookie`);
  if (r.method === "GET" && !/(^|&)t=\d+(&|$)/.test(r.query)) bad(`request ${i} (a GET) has no t parameter`);
});
const ts = records.filter((r) => r.method === "GET").map((r) => (/(^|&)t=(\d+)/.exec(r.query) || [])[2]);
if (new Set(ts).size !== ts.length) bad("two GETs share a t parameter");
for (const r of [message_post, records[records.length - 1]]) {
  if (r.headers.contentType !== "application/json" || r.headers.request !== "1" || r.headers.origin !== url) bad(`${r.path} lacks the browser envelope`);
}
let sent = {};
try { sent = JSON.parse(message_post.body); } catch { bad("the message body is not JSON"); }
if (!/^probe-\d{8}T\d{6}Z-\d+$/.test(sent.clientId || "") || sent.text !== message || sent.fromGuide !== false || Object.keys(sent).length !== 3) bad("the message body is not the fixed one");
if (records[records.length - 1].body !== "{}") bad("the sign-out body is not {}");
if (!/(^|&)after=0&afterInstance=0&t=\d+$/.test(polls[0].query)) bad("the first poll is " + polls[0].query);
polls.slice(1).forEach((r) => { if (!/(^|&)after=0&afterInstance=7&t=\d+$/.test(r.query)) bad("a later poll is " + r.query); });
console.log(problems.length ? "PROBLEMS " + problems.join("; ") : "OK");
EOF
}

new_state
probe_run "" OCUTALON_PROBE_DECISION_WAIT=120
verdict=$(verify_requests "")
expect_run "row 10: a healthy run" 0 "healthy count=0"
if [ "$verdict" = OK ]; then
  pass "row 10: the order, the cookie, the credentials, the envelope, the t parameters and the cursors of a healthy run"
else
  fail "row 10: $verdict"
fi
if [ ! -s "$commands" ] && [ "$(stored_count)" = 0 ]; then
  pass "row 10: a healthy run calls neither command and stores a count of 0"
else
  fail "row 10: a healthy run called a command ($(wc -l < "$commands" | tr -d ' ') line(s)) or stored '$(stored_count)'"
fi
if [ "$(ls -A "$state" | tr '\n' ' ')" = "counted-failures probe.log " ]; then
  pass "row 10: the state folder holds only the state files (no cookie jar, no resume reference)"
else
  fail "row 10: the state folder holds '$(ls -A "$state" | tr '\n' ' ')'"
fi
if ! grep -qF "$password" "$tmp/out" "$tmp/err" "$state"/* "$commands"; then
  pass "row 10: the password is in no stdout, stderr, state file or command record"
else
  fail "row 10: the password reached the probe's output, a state file or a command record"
fi

new_state
probe_run "splash_token" OCUTALON_PROBE_DECISION_WAIT=120
verdict=$(verify_requests "tok-9f2c")
if [ "$rc" = 0 ] && [ "$verdict" = OK ]; then
  pass "row 10: with a session token on the splash form the sign-in posts exactly the four fields"
else
  fail "row 10: with a token on the splash form: exit $rc, $verdict"
fi

# --- row 11: busy ---

busy_case() { # busy_case <label> <flags> <sign-outs wanted>
  new_state
  probe_run "$2"
  expect_run "row 11: $1" 1 "busy count=0"
  if [ "$(n_calls 'alert busy ')" = 1 ] && [ "$(n_calls reset)" = 0 ] && [ "$(cat "$state/busy-per-day" 2> /dev/null)" = "$today 1" ]; then
    pass "row 11: $1 alerts once, resets nothing and adds one to today's busy count"
  else
    fail "row 11: $1 left $(n_calls alert) alert(s), $(n_calls reset) reset(s), busy-per-day '$(cat "$state/busy-per-day" 2> /dev/null)'"
  fi
  if [ "$(n_requests POST /ocutalon/api/v1/session/end)" = "$3" ]; then
    pass "row 11: $1 posted session/end $3 time(s)"
  else
    fail "row 11: $1 posted session/end $(n_requests POST /ocutalon/api/v1/session/end) time(s), wanted $3"
  fi
}
busy_case "a 503 at the status" status_503 0
busy_case "a busy status" status_busy 0
busy_case "a 503 at the splash" splash_503 0
busy_case "the busy marker on the splash" splash_marker 0
busy_case "a 503 at the sign-in POST" signin_503 0
busy_case "a 503 at the message POST" msg_503 1
busy_case "a 503 at the second events poll" events_503_2 1

# --- row 12: no splash ---

new_state
printf '1\n' > "$state/counted-failures"
for variant in splash_local splash_404; do
  probe_run "$variant"
  expect_run "row 12: $variant" 1 "no_splash count=1"
done
probe_run "" OCUTALON_PROBE_URL="http://127.0.0.1:$closed_port"
expect_run "row 12: nothing listens on the port" 1 "no_splash count=1"
if [ "$(stored_count)" = 1 ] && [ "$(n_calls 'alert no_splash ')" = 3 ] && [ "$(n_calls reset)" = 0 ]; then
  pass "row 12: three no_splash runs alert three times and leave the count at 1"
else
  fail "row 12: count '$(stored_count)', $(n_calls alert) alert(s), $(n_calls reset) reset(s)"
fi
# A splash that never answers: the request's time limit ends the run as no_splash (one 20 s request), long before the next run.
new_state
hang_start=$SECONDS
probe_limit=40 probe_run "splash_hang"
hang_secs=$((SECONDS - hang_start))
expect_run "row 12: a splash that never answers" 1 "no_splash count=0"
if [ "$hang_secs" -lt 35 ] && [ "$(n_calls 'alert no_splash ')" = 1 ]; then
  pass "row 12: a splash that never answers ends the run in ${hang_secs} s (the request's time limit) with one alert"
else
  fail "row 12: a splash that never answers: the run took ${hang_secs} s (exit $rc), $(n_calls alert) alert(s)"
fi

# --- row 13: the other endings, the commands and the state files ---

new_state
probe_run "msg_500"
expect_run "row 13: a 500 at the message POST" 1 "no_decision count=1"
probe_run "events_nodecision"
expect_run "row 13: no decision within the wait" 1 "no_decision count=2 reset=0"
polls=$(n_requests GET /ocutalon/api/v1/events)
if [ "$polls" -ge 2 ] && [ "$polls" -le 3 ]; then
  pass "row 13: a 2 s wait polled the events $polls times (every 2 s, up to the wait)"
else
  fail "row 13: a 2 s wait polled the events $polls times, wanted 2 or 3 (every 2 s, up to the wait)"
fi
if [ "$(n_calls reset)" = 1 ] && [ "$(stored_count)" = 0 ] && [ "$(n_calls alert)" = 2 ]; then
  pass "row 13: the second counted failure ran the reset once and cleared the count"
else
  fail "row 13: $(n_calls reset) reset(s), count '$(stored_count)', $(n_calls alert) alert(s)"
fi
if [ "$(sed -n 1p "$commands" | cut -c1-6)" = "alert " ] && [ "$(sed -n 2p "$commands")" = reset ] && [ "$(sed -n 3p "$commands" | cut -c1-6)" = "alert " ]; then
  pass "row 13: the reset ran before the second alert"
else
  fail "row 13: the command record is not alert, reset, alert"
fi
if [ "$(sed -n 3p "$commands")" = "alert no_decision $(cat "$tmp/out" | tr -d '\n')" ]; then
  pass "row 13: the alert got the outcome and the run's log line"
else
  fail "row 13: the alert's arguments are not the outcome and the log line"
fi

new_state
probe_run "decision_error decision_first"
expect_run "row 13: a decision with the fallback reason error" 0 "healthy count=0 fallback=error"
if [ ! -s "$commands" ]; then pass "row 13: a fallback with another reason alerts nothing"; else fail "row 13: a healthy fallback called a command"; fi

new_state
printf '1\n' > "$state/counted-failures"
probe_run "decision_daily_cap decision_first"
expect_run "row 13: a daily_cap decision" 0 "capped count=0 fallback=daily_cap"
if [ "$(stored_count)" = 0 ] && [ ! -s "$commands" ]; then
  pass "row 13: capped clears the count and alerts nothing"
else
  fail "row 13: capped left count '$(stored_count)' or called a command"
fi

new_state
probe_run "signin_form_back"
expect_run "row 13: the form back after the POST" 1 "auth_failed count=1"
if [ "$(n_requests POST /ocutalon/api/v1/session/end)" = 0 ] && [ "$(n_requests POST /ocutalon/api/v1/messages)" = 0 ]; then
  pass "row 13: with the form back no API call is made"
else
  fail "row 13: an API call followed a failed sign-in"
fi
probe_run "signin_form_back" OCUTALON_PROBE_RESET_COMMAND="$tmp/reset.sh --exit=3"
expect_run "row 13: a reset that exits 3" 1 "auth_failed count=2 reset=3"
if [ "$(stored_count)" = 0 ]; then pass "row 13: the count is cleared although the reset failed"; else fail "row 13: count '$(stored_count)' after the reset"; fi

new_state
printf 'abc\n' > "$state/counted-failures"
probe_run "signin_form_back" OCUTALON_PROBE_ALERT_COMMAND="$tmp/alert.sh --exit=1"
expect_run "row 13: an alert command that exits 1, over an unreadable count" 1 "auth_failed count=1"
if [ "$(wc -l < "$tmp/err" | tr -d ' ')" = 1 ] && grep -qi 'alert' "$tmp/err"; then
  pass "row 13: a failing alert command prints one line on stderr"
else
  fail "row 13: the failing alert command's stderr is '$(head -c 200 "$tmp/err")'"
fi

new_state
printf '08\n' > "$state/counted-failures"
probe_run "signin_form_back"
expect_run "row 13: a stored count with a leading zero is unreadable" 1 "auth_failed count=1"

new_state
probe_term=1 probe_run "events_nodecision" OCUTALON_PROBE_DECISION_WAIT=120
if [ "$rc" = 130 ] && [ "$(n_requests POST /ocutalon/api/v1/session/end)" = 1 ]; then
  pass "row 13: a run sent TERM while it waits for the decision still posts session/end once (exit 130)"
else
  fail "row 13: a run sent TERM: exit $rc, session/end posted $(n_requests POST /ocutalon/api/v1/session/end) time(s)"
fi

new_state
quoted='say "hi" \ back'
probe_run "decision_first" OCUTALON_PROBE_MESSAGE="$quoted"
sent_text=$(node -e 'const r = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)).find((x) => x.path === "/ocutalon/api/v1/messages"); console.log(r ? JSON.parse(r.body).text : "none");' "$requests")
if [ "$rc" = 0 ] && [ "$sent_text" = "$quoted" ]; then
  pass "row 13: a message with a quote and a backslash is sent as valid JSON with the same text"
else
  fail "row 13: a message with a quote and a backslash: exit $rc, the stub parsed '$sent_text'"
fi

new_state
printf '1\n' > "$state/counted-failures"
probe_run "signin_form_back" OCUTALON_PROBE_RESET_COMMAND="$tmp/reset.sh ; touch $tmp/evil"
if [ "$(n_calls reset)" = 1 ] && [ ! -e "$tmp/evil" ]; then
  pass "row 13: a command variable is split into words and never evaluated by a shell"
else
  fail "row 13: $(n_calls reset) reset call(s), a shell evaluated the command: $([ -e "$tmp/evil" ] && echo yes || echo no)"
fi

new_state
printf '2020-01-01 5\n' > "$state/busy-per-day"
probe_run "status_busy"
probe_run "status_busy"
if [ "$(cat "$state/busy-per-day")" = "$(printf '2020-01-01 5\n%s 2' "$today")" ]; then
  pass "row 13: busy-per-day keeps older days and counts today's busy runs"
else
  fail "row 13: busy-per-day is '$(tr '\n' '|' < "$state/busy-per-day")'"
fi

# --- row 14: configuration ---

config_case() { # config_case <label> <stderr text that must be absent, or -> [VAR=value | -u VAR]...
  local label=$1 absent=$2 gone
  shift 2
  new_state
  gone="$tmp/gone.$n_state"
  probe_run "" OCUTALON_PROBE_STATE_DIR="$gone" "$@"
  if [ "$rc" = 2 ] && [ ! -s "$tmp/out" ] && [ "$(wc -l < "$tmp/err" | tr -d ' ')" = 1 ] && [ ! -s "$requests" ] && [ ! -e "$gone" ] && [ ! -s "$commands" ] \
    && { [ "$absent" = - ] || ! grep -qF -- "$absent" "$tmp/err"; } && ! grep -qF "$password" "$tmp/err"; then
    pass "row 14: $label gives exit 2 and one stderr line, with no request and nothing written"
  else
    fail "row 14: $label: exit $rc, stdout $(wc -c < "$tmp/out" | tr -d ' ') byte(s), stderr '$(head -c 160 "$tmp/err")', requests $(wc -l < "$requests" | tr -d ' '), state folder $([ -e "$gone" ] && echo made || echo absent)"
  fi
}
for variable in OCUTALON_PROBE_URL OCUTALON_DEMO_USER OCUTALON_DEMO_PASSWORD OCUTALON_PROBE_ALERT_COMMAND OCUTALON_PROBE_RESET_COMMAND OCUTALON_PROBE_STATE_DIR; do
  new_state
  gone="$tmp/gone.$n_state"
  probe_run "" OCUTALON_PROBE_STATE_DIR="$gone" -u "$variable"
  if [ "$rc" = 2 ] && [ ! -s "$tmp/out" ] && [ "$(wc -l < "$tmp/err" | tr -d ' ')" = 1 ] && grep -qF "$variable" "$tmp/err" && [ ! -s "$requests" ] && [ ! -e "$gone" ] && [ ! -s "$commands" ] && ! grep -qF "$password" "$tmp/err"; then
    pass "row 14: $variable unset gives exit 2 and one stderr line that names it, with no request"
  else
    fail "row 14: $variable unset: exit $rc, stderr '$(head -c 160 "$tmp/err")', requests $(wc -l < "$requests" | tr -d ' ')"
  fi
done
config_case "a URL with a path" secretpathzz OCUTALON_PROBE_URL="$url/secretpathzz/x"
grep -qF OCUTALON_PROBE_URL "$tmp/err" || fail "row 14: a URL with a path: the line does not name OCUTALON_PROBE_URL"
config_case "a URL with a user" secretuserzz OCUTALON_PROBE_URL="http://secretuserzz@127.0.0.1:$port"
config_case "a URL with no scheme" - OCUTALON_PROBE_URL="127.0.0.1:$port"
grep -qF OCUTALON_PROBE_URL "$tmp/err" || fail "row 14: a URL with no scheme: the line does not name OCUTALON_PROBE_URL"
config_case "a wait of 0" - OCUTALON_PROBE_DECISION_WAIT=0
grep -qF OCUTALON_PROBE_DECISION_WAIT "$tmp/err" || fail "row 14: a wait of 0: the line does not name OCUTALON_PROBE_DECISION_WAIT"
config_case "a wait of 121" 121 OCUTALON_PROBE_DECISION_WAIT=121
grep -qF OCUTALON_PROBE_DECISION_WAIT "$tmp/err" || fail "row 14: a wait of 121: the line does not name OCUTALON_PROBE_DECISION_WAIT"
config_case "a wait that is not a number" wordzz OCUTALON_PROBE_DECISION_WAIT=wordzz
grep -qF OCUTALON_PROBE_DECISION_WAIT "$tmp/err" || fail "row 14: a wait that is not a number: the line does not name OCUTALON_PROBE_DECISION_WAIT"
config_case "a TMPDIR that does not exist" nonexistzz TMPDIR="$tmp/nonexistzz/deeper"
grep -qF TMPDIR "$tmp/err" || fail "row 14: a TMPDIR that does not exist: the line does not name TMPDIR"

# A URL with the scheme's default port: curl leaves port 80 out of the Host header, so the Origin of every POST must leave it out too
# (IRIS compares Origin with the scheme and Host). The stub is reached as an HTTP proxy, so that the URL can name port 80 and no name
# is looked up.
new_state
probe_run "decision_first" OCUTALON_PROBE_URL="http://probe.test:80" http_proxy="$url" -u NO_PROXY -u no_proxy
if [ "$rc" = 0 ] && sed 's/^[^ ]* //' "$tmp/out" | grep -qx 'healthy count=0' && [ "$(grep -c '"origin":"http://probe.test"' "$requests")" = 3 ]; then
  pass "row 14: a URL with the default port 80 gives a healthy run, and its three POSTs carry the Origin without the port"
else
  fail "row 14: a URL with the default port 80: exit $rc, '$(sed 's/^[^ ]* //' "$tmp/out")', $(grep -c '"origin":"http://probe.test"' "$requests") POST(s) with the Origin without the port"
fi

new_state
gone="$tmp/made/deeper"
probe_run "decision_first" OCUTALON_PROBE_STATE_DIR="$gone" OCUTALON_PROBE_URL="$url/"
if [ "$rc" = 0 ] && [ -f "$gone/probe.log" ] && sed 's/^[^ ]* //' "$gone/probe.log" | grep -qx 'healthy count=0'; then
  pass "row 14: a missing state folder is created, a trailing slash on the URL is dropped, and the run goes on"
else
  fail "row 14: a missing state folder: exit $rc, log $([ -f "$gone/probe.log" ] && echo present || echo absent)"
fi

# --- (QA) the gaps the first rows leave: the password on every path, a configuration error over a used state folder, the counting
# --- sequences, the UTC day of the busy count, the sign-out on every path and the order of the API calls ---

wrong=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2> /dev/null | head -c 32)

# Stub commands that also dump their whole environment and arguments, so that a password handed down to the host's commands shows.
for kind in alert reset; do
  cat > "$tmp/qa-$kind.sh" <<'EOF'
#!/bin/sh
code=0
case $1 in --exit=*) code=${1#--exit=}; shift ;; esac
KIND_LINE
{ echo "args: $*"; env; } >> "$PROBE_TEST_ENV"
exit "$code"
EOF
done
sed -i.bak 's/^KIND_LINE$/echo "alert $1 $2" >> "$PROBE_TEST_RECORD"/' "$tmp/qa-alert.sh"
sed -i.bak 's/^KIND_LINE$/echo "reset" >> "$PROBE_TEST_RECORD"/' "$tmp/qa-reset.sh"
rm -f "$tmp"/qa-*.bak
chmod 755 "$tmp/qa-alert.sh" "$tmp/qa-reset.sh"
qa_cmds=(OCUTALON_PROBE_ALERT_COMMAND="$tmp/qa-alert.sh" OCUTALON_PROBE_RESET_COMMAND="$tmp/qa-reset.sh")

# leak_lines: the number of lines of the run's stdout, stderr, state files, command record and command environments that hold a password.
leak_lines() {
  { cat "$tmp/out" "$tmp/err" "$commands" "$cmd_env" 2> /dev/null; find "$state" -type f -exec cat {} + 2> /dev/null; } | grep -cF -e "$password" -e "$wrong"
}
# request_leaks: the number of recorded requests that hold a password and are not the sign-in POST.
request_leaks() {
  grep -F -e "$password" -e "$wrong" "$requests" | grep -vc '^{"method":"POST","path":"/ocutalon/"'
}
# verify_bracket <sign-outs wanted>: with a sign-in, every API call comes after the sign-in's redirect GET and the one session/end is the last
# request; with none, the run made no API call at all.
verify_bracket() {
  node - "$requests" "$1" <<'EOF'
const fs = require("fs");
const recs = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const want = Number(process.argv[3]);
const idx = (f) => recs.map((r, i) => (f(r) ? i : -1)).filter((i) => i >= 0);
const apis = idx((r) => r.path.startsWith("/ocutalon/api/"));
const ends = idx((r) => r.method === "POST" && r.path === "/ocutalon/api/v1/session/end");
const signins = idx((r) => r.method === "POST" && r.path === "/ocutalon/");
const problems = [];
if (ends.length !== want) problems.push(`session/end posted ${ends.length} time(s), wanted ${want}`);
if (want === 0) {
  if (apis.length) problems.push(`${apis.length} API call(s) without a sign-in`);
} else {
  if (signins.length !== 1) problems.push(`${signins.length} sign-in POSTs`);
  else if (apis.some((i) => i < signins[0] + 2)) problems.push("an API call came before the sign-in's redirect GET");
  if (ends.length === 1 && ends[0] !== recs.length - 1) problems.push("a request came after the sign-out");
}
console.log(problems.length ? "PROBLEMS " + problems.join("; ") : "OK");
EOF
}

# qa_path <label> <flags> <exit> <text> <sign-outs> [VAR=value]...: one run on a fresh state with the dumping commands. It checks the
# outcome, the sign-out count and order, and that no password is anywhere but in the sign-in POST body.
qa_path() {
  local label=$1 fl=$2 want_rc=$3 want_text=$4 want_so=$5 verdict
  shift 5
  new_state
  probe_run "$fl" "${qa_cmds[@]}" "$@"
  expect_run "QA path, $label" "$want_rc" "$want_text"
  verdict=$(verify_bracket "$want_so")
  if [ "$verdict" = OK ]; then
    pass "QA path, $label: $want_so sign-out(s), and no API call before the sign-in or after the sign-out"
  else
    fail "QA path, $label: $verdict"
  fi
  if [ "$(leak_lines)" = 0 ] && [ "$(request_leaks)" = 0 ]; then
    pass "QA path, $label: no password in stdout, stderr, the state files, the commands' arguments and environment, or any request but the sign-in POST"
  else
    fail "QA path, $label: a password is in $(leak_lines) output line(s) or $(request_leaks) request(s) that are not the sign-in POST"
  fi
}

qa_path "a healthy run" decision_first 0 "healthy count=0" 1
qa_path "a capped run" "decision_daily_cap decision_first" 0 "capped count=0 fallback=daily_cap" 1
qa_path "a healthy run with the fallback error" "decision_error decision_first" 0 "healthy count=0 fallback=error" 1
qa_path "a decision timeout" events_nodecision 1 "no_decision count=1" 1
qa_path "a 500 at the message POST" msg_500 1 "no_decision count=1" 1
qa_path "a 503 at the message POST" msg_503 1 "busy count=0" 1
qa_path "a 503 at the second events poll" events_503_2 1 "busy count=0" 1
qa_path "the form back after the sign-in POST" signin_form_back 1 "auth_failed count=1" 0
qa_path "a wrong password" "" 1 "auth_failed count=1" 0 OCUTALON_DEMO_PASSWORD="$wrong"
qa_path "a page that is neither the shell nor the form after the sign-in" shell_other 1 "no_decision count=1" 0
qa_path "a 503 at the sign-in POST" signin_503 1 "busy count=0" 0
qa_path "no splash" splash_local 1 "no_splash count=0" 0
qa_path "a busy status" status_busy 1 "busy count=0" 0

# A failing reset (over a stored count of 1) and a failing alert hand the password nowhere either.
new_state
printf '1\n' > "$state/counted-failures"
probe_run "signin_form_back" OCUTALON_PROBE_ALERT_COMMAND="$tmp/qa-alert.sh --exit=1" OCUTALON_PROBE_RESET_COMMAND="$tmp/qa-reset.sh --exit=3" OCUTALON_DEMO_PASSWORD="$wrong"
if [ "$rc" = 1 ] && [ "$(sed 's/^[^ ]* //' "$tmp/out")" = "auth_failed count=2 reset=3" ] && [ "$(leak_lines)" = 0 ] && [ "$(request_leaks)" = 0 ] \
  && [ -s "$cmd_env" ] && grep -q '^args: auth_failed ' "$cmd_env"; then
  pass "QA path, a failing reset and a failing alert after a wrong password: no password in the output, the state, the commands' arguments or environment"
else
  fail "QA path, a failing reset and a failing alert: exit $rc, '$(sed 's/^[^ ]* //' "$tmp/out")', $(leak_lines) leaking line(s)"
fi

# A run sent HUP or TERM while it waits for the decision signs out once, last, and holds no password either.
for sig in TERM HUP; do
  new_state
  probe_term=1 probe_sig=$sig probe_run "events_nodecision" "${qa_cmds[@]}" OCUTALON_PROBE_DECISION_WAIT=120
  verdict=$(verify_bracket 1)
  if [ "$rc" = 130 ] && [ "$verdict" = OK ] && [ "$(leak_lines)" = 0 ] && [ "$(request_leaks)" = 0 ]; then
    pass "QA path, a run sent $sig in the decision wait: exit 130, one sign-out as the last request, no password anywhere"
  else
    fail "QA path, a run sent $sig: exit $rc, $verdict, $(leak_lines) leaking line(s)"
  fi
done

# --- a configuration error over a state folder that holds files: no request, no command, and every file byte-identical ---

state_fingerprint() { { ls -A "$state"; find "$state" -type f -exec cat {} +; } 2> /dev/null | cksum; }
cfg_used_case() { # cfg_used_case <label> <variable the line must name> [VAR=value | -u VAR]...
  local label=$1 named=$2 before after
  shift 2
  new_state
  printf '1\n' > "$state/counted-failures"
  printf '2026-10-24 3\n' > "$state/busy-per-day"
  printf '2026-10-26T10:00:00Z auth_failed count=1\n' > "$state/probe.log"
  before=$(state_fingerprint)
  probe_run "" "${qa_cmds[@]}" "$@"
  after=$(state_fingerprint)
  if [ "$rc" = 2 ] && [ ! -s "$tmp/out" ] && [ "$(wc -l < "$tmp/err" | tr -d ' ')" = 1 ] && grep -qF "$named" "$tmp/err" && [ ! -s "$requests" ] \
    && [ ! -s "$commands" ] && [ "$before" = "$after" ] && [ "$(leak_lines)" = 0 ]; then
    pass "QA row 14: $label over a used state folder gives exit 2, no request, no command, and the folder is byte-identical"
  else
    fail "QA row 14: $label over a used state folder: exit $rc, stderr '$(head -c 160 "$tmp/err")', requests $(wc -l < "$requests" | tr -d ' '), folder $([ "$before" = "$after" ] && echo same || echo CHANGED)"
  fi
}
cfg_used_case "a wait of 0" OCUTALON_PROBE_DECISION_WAIT OCUTALON_PROBE_DECISION_WAIT=0
cfg_used_case "a wait of 121" OCUTALON_PROBE_DECISION_WAIT OCUTALON_PROBE_DECISION_WAIT=121
cfg_used_case "a URL with a path" OCUTALON_PROBE_URL OCUTALON_PROBE_URL="$url/x"
cfg_used_case "an unset URL" OCUTALON_PROBE_URL -u OCUTALON_PROBE_URL
cfg_used_case "an unset password" OCUTALON_DEMO_PASSWORD -u OCUTALON_DEMO_PASSWORD
cfg_used_case "an alert command of white space only" OCUTALON_PROBE_ALERT_COMMAND OCUTALON_PROBE_ALERT_COMMAND="   "
cfg_used_case "a reset command of white space only" OCUTALON_PROBE_RESET_COMMAND OCUTALON_PROBE_RESET_COMMAND="   "

new_state
printf 'x\n' > "$tmp/not-a-folder"
probe_run "" "${qa_cmds[@]}" OCUTALON_PROBE_STATE_DIR="$tmp/not-a-folder/sub"
if [ "$rc" = 2 ] && [ ! -s "$tmp/out" ] && [ "$(wc -l < "$tmp/err" | tr -d ' ')" = 1 ] && grep -qF OCUTALON_PROBE_STATE_DIR "$tmp/err" && [ ! -s "$requests" ] && [ ! -s "$commands" ]; then
  pass "QA row 14: a state folder that cannot be created gives exit 2 naming OCUTALON_PROBE_STATE_DIR, with no request and no command"
else
  fail "QA row 14: an uncreatable state folder: exit $rc, stderr '$(head -c 160 "$tmp/err")', requests $(wc -l < "$requests" | tr -d ' ')"
fi

# --- the counting sequence: only auth_failed and no_decision count; busy and no_splash between two of them leave the count; the second counted failure
# --- in a row runs the reset once and clears the count; a healthy run clears it ---

new_state
seq_total=0
seq_step() { # seq_step <label> <flags> <exit> <log text> <alerts so far> <resets so far> <stored count>
  probe_run "$2"
  expect_run "QA sequence, $1" "$3" "$4"
  if [ "$(n_calls alert)" = "$5" ] && [ "$(n_calls reset)" = "$6" ] && [ "$(stored_count)" = "$7" ]; then
    pass "QA sequence, $1: $5 alert(s), $6 reset(s) so far, stored count $7"
  else
    fail "QA sequence, $1: $(n_calls alert) alert(s), $(n_calls reset) reset(s), stored count '$(stored_count)' (wanted $5, $6, $7)"
  fi
}
seq_step "counted failure 1 (auth_failed)" signin_form_back 1 "auth_failed count=1" 1 0 1
seq_step "busy between two counted failures" status_busy 1 "busy count=1" 2 0 1
seq_step "no_splash between two counted failures" splash_local 1 "no_splash count=1" 3 0 1
seq_step "counted failure 2 (no_decision): the reset runs once" events_nodecision 1 "no_decision count=2 reset=0" 4 1 0
seq_step "busy after the reset" status_busy 1 "busy count=0" 5 1 0
seq_step "counted failure 1 again" signin_form_back 1 "auth_failed count=1" 6 1 1
seq_step "healthy clears the count" decision_first 0 "healthy count=0" 6 1 0
seq_step "counted failure 1 after a healthy run" signin_form_back 1 "auth_failed count=1" 7 1 1
seq_step "counted failure 2 (auth_failed): the second reset" signin_form_back 1 "auth_failed count=2 reset=0" 8 2 0
seq_step "counted failure 1 after the second reset" msg_500 1 "no_decision count=1" 9 2 1
seq_step "capped clears the count" "decision_daily_cap decision_first" 0 "capped count=0 fallback=daily_cap" 9 2 0

new_state
printf '5\n' > "$state/counted-failures"
probe_run "signin_form_back"
expect_run "QA sequence, a stored count of 5" 1 "auth_failed count=6 reset=0"
if [ "$(n_calls reset)" = 1 ] && [ "$(stored_count)" = 0 ]; then
  pass "QA sequence, a stored count of 5: the reset ran once and the count is cleared"
else
  fail "QA sequence, a stored count of 5: $(n_calls reset) reset(s), stored count '$(stored_count)'"
fi

# --- the busy count per UTC day: a date shim fixes the clock, and the run's time zone is not UTC ---

shim="$tmp/shim"
mkdir -p "$shim"
real_date=$(command -v date)
if "$real_date" -d @0 +%s > /dev/null 2>&1; then
  printf '#!/bin/sh\nexec "%s" -d "@$FAKE_EPOCH" "$@"\n' "$real_date" > "$shim/date"
else
  printf '#!/bin/sh\nexec "%s" -r "$FAKE_EPOCH" "$@"\n' "$real_date" > "$shim/date"
fi
chmod 755 "$shim/date"
epoch_of() { node -e 'console.log(Date.UTC(...process.argv.slice(1).map(Number)) / 1000)' "$1" "$(($2 - 1))" "$3" "$4" "$5" "$6"; }
day_run() { # day_run <epoch> <time zone>
  probe_run "status_busy" PATH="$shim:$PATH" FAKE_EPOCH="$1" TZ="$2"
}
new_state
printf '2026-10-24 4\n' > "$state/busy-per-day"
day_run "$(epoch_of 2026 10 25 23 59 30)" Pacific/Auckland
day_run "$(epoch_of 2026 10 25 23 59 40)" Pacific/Auckland
if [ "$(cat "$state/busy-per-day")" = "$(printf '2026-10-24 4\n2026-10-25 2')" ] && sed 's/^[^ ]* //' "$tmp/out" | grep -qx 'busy count=0' && grep -q '^2026-10-25T23:59:40Z busy' "$tmp/out"; then
  pass "QA row 4: two busy runs just before the UTC midnight, in a time zone 13 hours ahead, count on the UTC day (2026-10-25 2), time in UTC"
else
  fail "QA row 4: before the UTC midnight busy-per-day is '$(tr '\n' '|' < "$state/busy-per-day")', the log line '$(cat "$tmp/out")'"
fi
day_run "$(epoch_of 2026 10 26 0 0 10)" America/Los_Angeles
if [ "$(cat "$state/busy-per-day")" = "$(printf '2026-10-24 4\n2026-10-25 2\n2026-10-26 1')" ] && grep -q '^2026-10-26T00:00:10Z busy' "$tmp/out"; then
  pass "QA row 4: just after the UTC midnight, in a time zone 7 hours behind, the count rolls over to a new day (2026-10-26 1) and the earlier days stay"
else
  fail "QA row 4: after the UTC midnight busy-per-day is '$(tr '\n' '|' < "$state/busy-per-day")'"
fi
day_run "$(epoch_of 2026 10 26 0 5 0)" America/Los_Angeles
day_run "$(epoch_of 2027 1 1 0 0 5)" UTC
if [ "$(cat "$state/busy-per-day")" = "$(printf '2026-10-24 4\n2026-10-25 2\n2026-10-26 2\n2027-01-01 1')" ] && grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]+' "$state/busy-per-day"; then
  pass "QA row 4: later runs add to the same day, a new year starts a new line, and every earlier day stays a readable line"
else
  fail "QA row 4: busy-per-day ends as '$(tr '\n' '|' < "$state/busy-per-day")'"
fi

# --- the probe's temporary folder: every run above (healthy, busy, no_splash, auth_failed, no_decision, killed, a configuration error) removed its own ---

if [ -z "$(ls -A "$work_root")" ]; then
  pass "the probe's temporary folder (the cookie jar) is removed at the end of every run"
else
  fail "the probe left $(ls -A "$work_root" | wc -l | tr -d ' ') temporary folder(s) under its TMPDIR"
fi

# --- row 15: the file itself ---

if LC_ALL=C grep -q '[^[:print:][:space:]]' "$probe"; then fail "row 15: docker/probe.sh is not ASCII"; else pass "row 15: docker/probe.sh is ASCII"; fi
if [ -x "$probe" ]; then pass "row 15: docker/probe.sh is executable"; else fail "row 15: docker/probe.sh is not executable"; fi
mode=$(cd "$root" && git ls-files -s docker/probe.sh 2> /dev/null | cut -d' ' -f1)
if [ -z "$mode" ] || [ "$mode" = 100755 ]; then
  pass "row 15: docker/probe.sh is tracked with mode 100755 (or not tracked yet: '${mode:-untracked}')"
else
  fail "row 15: docker/probe.sh is tracked with mode $mode"
fi
host_hits=$(grep -nE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{1,4}|localhost|[A-Za-z0-9.-]+:[0-9]{2,5}([^0-9]|$)|https?://[A-Za-z0-9]' "$probe" | cut -d: -f1 | tr '\n' ' ')
if [ -z "$host_hits" ]; then
  pass "row 15: docker/probe.sh holds no IP address, localhost, host:port or URL with a literal host"
else
  fail "row 15: docker/probe.sh holds a host detail on line(s) $host_hits"
fi
cred_hits=$(grep -nE -e '(^|[[:space:]])-u[[:space:]]' -e '--user' -e 'Authorization' -e '--basic' -e '--digest' -e '--netrc' "$probe" | cut -d: -f1 | tr '\n' ' ')
if [ -z "$cred_hits" ]; then
  pass "row 15: docker/probe.sh has no user option, authorization header or netrc"
else
  fail "row 15: docker/probe.sh has a credential option on line(s) $cred_hits"
fi
password_requests=$(grep -c -e '--data-urlencode.*IRISPassword' "$probe")
password_other=$(grep -v -e '--data-urlencode.*IRISPassword' -e '^form_field=' "$probe" | grep -c 'IRISPassword')
if [ "$password_requests" = 1 ] && grep -qF "'IRISPassword@-'" "$probe" && [ "$password_other" = 0 ]; then
  pass "row 15: IRISPassword is a request field once, and it reads standard input"
else
  fail "row 15: IRISPassword is a request field $password_requests time(s), elsewhere $password_other time(s)"
fi
default_wait=$(sed -n 's/^decision_wait=\${OCUTALON_PROBE_DECISION_WAIT:-\([0-9]*\)}$/\1/p' "$probe")
if [ "$default_wait" = 120 ]; then pass "row 15: the wait's default is 120"; else fail "row 15: the wait's default reads '$default_wait'"; fi

if [ "$fails" -eq 0 ]; then
  echo "test-probe: all checks passed"
  exit 0
fi
echo "test-probe: $fails check(s) failed"
exit 1
