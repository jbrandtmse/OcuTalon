#!/usr/bin/env bash
# Hermetic test of release/demo-load.sh (Story 29.8; matrix rows S1 to S16). No container and no host: one inline Node server on
# 127.0.0.1 (a random port, docker/tests/lib-stub.sh) stands in for the online demo: a splash that prefills a random published account
# (with the busy text and X-OcuTalon-Busy while busy), the sign-in (303 and a cookie, or the busy splash), /ocutalon/, /state, the message,
# Break the feed and approval routes, session/end, ?IRISLogout=end, the status in both forms and the trace pages. It is busy at 6 live
# sessions or at 6 trace sessions, and its trace form at 6 trace sessions. It checks the browser envelope of every POST under
# /ocutalon/api/, writes the phone item's createdAt as the press's startedAt plus the flag's seconds at once (so a late notice needs no
# wait), and records every request (method, path, X-Forwarded-For, session, auth). A flags file, re-read on every request, breaks one
# thing at a time: notice=<s>, fallback=<reason>, inc-fallback=<reason>, not-watching, extra=admit (the sign-in admits past the cap),
# extra=error (the splash answers 500 while busy), signout=fail, ready=false, busy=true, gate=on, hang=turn, early-phone (a notice older
# than the press comes first), extra-turn (a second chat turn with a decision), trace=form (the trace pages ask for an IRIS sign-in),
# trace=500 (the trace pages answer 500), state=500 (/state answers 500 after a sign-in), signin=slow (a sign-in's redirect comes 2 s after
# its session opens), signin=busy|limit|refused (the sign-in answers the busy splash, the address-limit text or a refused form),
# slow-turn=<address>:<s> (the turn of that address's session runs for s seconds), extra=page (while busy, the splash and the sign-in
# answer a busy page with no form, as the host's proxy does). Every run is the real script; the test asserts its exit code, its lines and
# what the stand-in saw. TEST_REVERSE=1 runs the rows in reverse order, and ONLY_ROWS='s2 s4' runs only those rows (each set_flags writes
# a new generation, on which the stand-in drops every session, and empties the record, so no row depends on another's leftovers).
#   S1  case 1 (AC1's shape)   S2  the turn bound        S3  Visual Trace            S4  a late notice
#   S5  fallbacks              S6  the watch does not start    S7  the one more visitor gets in    S8  an error page
#   S9  a failed sign-out      S10 preconditions         S11 usage                   S12 credentials, addresses, output
#   S13 licence readings       S14 a signal              S15 hold                    S16 pins
# Needs Node, curl and jq. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/release/demo-load.sh"

. "$(dirname "$0")/lib-stub.sh"
. "$(dirname "$0")/lib-online.sh"
need_tools node curl jq

started=$SECONDS
flags="$tmp/flags"
record="$tmp/record.jsonl"
: > "$flags"
: > "$record"

gate_user="gate$(hexpw)"
gate_password=$(hexpw)
acct_user="acct$(hexpw | head -c 12)"
acct_password="$(hexpw | head -c 24)&q"

STUB_GATE="$gate_user:$gate_password" STUB_USER="$acct_user" STUB_PW="$acct_password" stub_start "$flags" "$record" << 'STUB' || exit 1
const http = require("http");
const fs = require("fs");
const [flagsFile, recordFile] = process.argv.slice(2);
const GATE = process.env.STUB_GATE || "";
const USER = process.env.STUB_USER || "";
const PW = process.env.STUB_PW || "";
const CAP = 6;

// The flags: one per line, "name" or "name=value", read again on every request.
const readFlags = () => {
  const f = new Map();
  for (const line of fs.readFileSync(flagsFile, "utf8").split("\n")) {
    if (!line) continue;
    const i = line.indexOf("=");
    if (i < 0) f.set(line, "");
    else f.set(line.slice(0, i), line.slice(i + 1));
  }
  return f;
};
const record = (o) => fs.appendFileSync(recordFile, JSON.stringify(Object.assign({ ts: Date.now() }, o)) + "\n");
const iso = (ms) => new Date(ms).toISOString().slice(0, 19) + "Z";
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const sessions = new Map();
let nextId = 0;
let gen = null;
const live = () => [...sessions.values()].filter((s) => !s.ended);
const traceCount = () => live().reduce((n, s) => n + s.trace.size, 0);
const isBusy = (f, form) => f.get("busy") === "true" || (form === "trace" ? traceCount() >= CAP : live().length >= CAP || traceCount() >= CAP);
const end = (s, how) => {
  if (s.ended) return;
  s.ended = true;
  record({ ended: s.id, how });
};

const BUSY_TEXT = "The demo is busy right now. Try again in a few minutes, or install it yourself.";
const BUSY_PAGE = "<!DOCTYPE html><html><head><title>Try OcuTalon</title></head><body><main><p>" + BUSY_TEXT + "</p></main></body></html>";
const LIMIT_TEXT = "Too many new sessions from your network this hour.";
const splash = (busy, refused) =>
  "<!DOCTYPE html><html><head><title>Try OcuTalon</title></head><body><main>" +
  (busy ? "<p class=\"error\">" + BUSY_TEXT + "</p>" : "") +
  "<form name=\"Login\" method=\"post\" action=\"/ocutalon/\">\n" +
  "<div><input id=\"ocu-user\" type=\"text\" name=\"IRISUsername\" autocomplete=\"off\" value=\"" + esc(USER) + "\"" + (refused ? " aria-invalid=\"true\"" : "") + "></div>\n" +
  "<div><input id=\"ocu-pass\" type=\"text\" name=\"IRISPassword\" autocomplete=\"off\" value=\"" + esc(PW) + "\"" + (refused ? " aria-invalid=\"true\"" : "") + "></div>\n" +
  "<button type=\"submit\" name=\"IRISLogin\" value=\"Sign in and start\">Sign in and start</button></form></main></body></html>";

const form = (text) => {
  const o = {};
  for (const p of text.split("&").filter(Boolean)) {
    const i = p.indexOf("=");
    const dec = (x) => decodeURIComponent(x.replace(/\+/g, " "));
    o[dec(i < 0 ? p : p.slice(0, i))] = i < 0 ? "" : dec(p.slice(i + 1));
  }
  return o;
};
const cookieOf = (req) => {
  const m = /(?:^|;\s*)SID=(s[0-9]+)/.exec(req.headers.cookie || "");
  return m ? sessions.get(m[1]) : undefined;
};

const stateOf = (s, f) => {
  const chat = [];
  const phone = [];
  const checks = [];
  const fb = f.get("fallback") || null;
  const ifb = f.get("inc-fallback") || null;
  const [slowAddr, slowSec] = (f.get("slow-turn") || ":").split(":");
  const hang = f.get("hang") === "turn" || (slowAddr !== "" && s.addr === slowAddr && Date.now() < s.msgAt + Number(slowSec) * 1000);
  if (s.msg) {
    const payload = { ref: "m1", clientId: s.msg.clientId, text: s.msg.text, fromGuide: s.msg.fromGuide, state: hang ? "running" : "done" };
    if (!hang) {
      payload.decision = { ref: "d1", kind: "decide", fallback: fb !== null, fallbackReason: fb };
      payload.fallbackReason = fb;
      payload.traceUrl = "/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen?HeaderId=1";
      checks.push({ ref: "c1", kind: "orders", traceUrl: "/ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen?HeaderId=2" });
    }
    chat.push({ type: "chat.message", payload });
    if (f.has("extra-turn") && !hang) {
      chat.push({ type: "chat.message", payload: { ref: "m2", text: "again", fromGuide: false, state: "done", decision: { ref: "d3", kind: "decide", fallback: false, fallbackReason: null } } });
    }
  }
  if (s.started !== null) {
    chat.push({ type: "incident", payload: { ref: "i1", state: s.resolved ? "resolved" : "awaiting_approval", decisionRef: "d2", fallback: ifb !== null, fallbackReason: ifb } });
    if (f.has("early-phone")) phone.push({ ref: "p0", direction: "out", text: "An earlier notice", approvalRef: "ap0", createdAt: iso(s.started - 30000) });
    phone.push({ ref: "p1", direction: "out", text: "Orders needs you", approvalRef: "ap1", createdAt: iso(s.noticeAt) });
  }
  return { chat, phone, rail: { decisions: [], checks }, onlineDemo: true };
};

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const f = readFlags();
    if (f.get("gen") !== gen) {
      gen = f.get("gen");
      sessions.clear();
    }
    const body = Buffer.concat(chunks).toString("latin1");
    const qi = req.url.indexOf("?");
    const path = qi < 0 ? req.url : req.url.slice(0, qi);
    const query = qi < 0 ? "" : req.url.slice(qi + 1);
    const s = cookieOf(req);
    const xff = req.headers["x-forwarded-for"] || "";
    let auth = "off";
    if (GATE && f.get("gate") === "on") {
      auth = req.headers.authorization === "Basic " + Buffer.from(GATE).toString("base64") ? "ok" : req.headers.authorization ? "bad" : "none";
    }
    const log = { m: req.method, u: req.url, xff, sid: s ? s.id : "", auth };
    const send = (status, headers, text) => {
      log.s = status;
      record(log);
      const h = Object.assign({}, headers);
      const buf = Buffer.from(text, "latin1");
      h["Content-Length"] = buf.length;
      res.writeHead(status, h);
      res.end(buf);
    };
    const json = (status, obj) => send(status, { "Content-Type": "application/json" }, JSON.stringify(obj));
    if (auth !== "off" && auth !== "ok") return send(401, { "WWW-Authenticate": "Basic realm=\"gate\"" }, "gate");
    if (req.method !== "GET" && req.method !== "POST") return send(405, {}, "method");

    if (query.includes("IRISLogout=end")) {
      if (s) {
        if (path.startsWith("/ocutalon/trace/ocutalon/")) s.trace.delete("ocutalon");
        else if (path.startsWith("/ocutalon/trace/ocuorders/")) s.trace.delete("ocuorders");
        else end(s, "logout");
      }
      return send(200, { "Content-Type": "text/html" }, "<html><body>signed out</body></html>");
    }
    if (path === "/ocutalon/public/status" && req.method === "GET") {
      const trace = query.includes("for=trace");
      const busy = isBusy(f, trace ? "trace" : "plain");
      const h = { "Content-Type": "application/json", "Cache-Control": "no-store" };
      if (busy) h["X-OcuTalon-Busy"] = "1";
      return send(200, h, JSON.stringify({ ready: f.get("ready") !== "false", nextReset: iso(Date.now() + 7200000), busy, lastReset: "2026-10-25T08:00:00Z", lastResetKind: "scheduled" }));
    }
    if (path === "/ocutalon/" && req.method === "GET") {
      if (s && !s.ended) return send(200, { "Content-Type": "text/html" }, "<html><body><app-root></app-root></body></html>");
      const busy = isBusy(f, "plain");
      if (busy && f.get("extra") === "error") return send(500, { "Content-Type": "text/html" }, "<html><body>error</body></html>");
      if (busy && f.get("extra") === "page") return send(503, { "Content-Type": "text/html" }, BUSY_PAGE);
      return send(200, busy ? { "Content-Type": "text/html", "X-OcuTalon-Busy": "1" } : { "Content-Type": "text/html" }, splash(busy, false));
    }
    if (path === "/ocutalon/" && req.method === "POST") {
      const b = form(body);
      const busy = isBusy(f, "plain");
      const sf = f.get("signin");
      if (busy && f.get("extra") === "page") return send(503, { "Content-Type": "text/html" }, BUSY_PAGE);
      if ((busy && f.get("extra") !== "admit") || sf === "busy") return send(200, { "Content-Type": "text/html", "X-OcuTalon-Busy": "1" }, splash(true, false));
      if (sf === "limit") return send(200, { "Content-Type": "text/html" }, splash(false, false).replace("<main>", "<main><p class=\"error\">" + LIMIT_TEXT + "</p>"));
      if (b.IRISUsername !== USER || b.IRISPassword !== PW || b.IRISLogin !== "Sign in and start" || sf === "refused") return send(200, { "Content-Type": "text/html" }, splash(false, true));
      const id = "s" + ++nextId;
      const ns = { id, addr: xff, ended: false, trace: new Set(), msg: null, msgAt: 0, started: null, noticeAt: 0, resolved: false };
      sessions.set(id, ns);
      record({ issued: id, addr: xff });
      const redirect = () => send(303, { Location: "/ocutalon/", "Set-Cookie": "SID=" + id + "; path=/; HttpOnly" }, "");
      if (sf === "slow") return setTimeout(redirect, 2000);
      return redirect();
    }
    if (path.startsWith("/ocutalon/trace/") && req.method === "GET") {
      const app = path.startsWith("/ocutalon/trace/ocutalon/") ? "ocutalon" : "ocuorders";
      if (!s || s.ended || f.get("trace") === "form") return send(200, { "Content-Type": "text/html" }, "<html><body><input type=\"password\" name=\"IRISPassword\"></body></html>");
      if (f.get("trace") === "500") return send(500, { "Content-Type": "text/html" }, "error");
      if (!s.trace.has(app) && traceCount() >= CAP) return send(503, { "Content-Type": "text/html" }, "busy");
      s.trace.add(app);
      return send(200, { "Content-Type": "text/html" }, "<html><body>trace</body></html>");
    }
    if (path.startsWith("/ocutalon/api/")) {
      if (!s || s.ended) return json(401, { error: { code: "signed_out", message: "Sign in first." } });
      if (req.method === "POST") {
        const ok = (req.headers["content-type"] || "").startsWith("application/json") && req.headers["x-ocutalon-request"] === "1" && req.headers.origin === "http://" + req.headers.host;
        log.env = ok ? "ok" : "bad";
        if (!ok) return json(403, { error: { code: "bad_envelope", message: "The browser envelope is missing." } });
        log.b = body.length > 300 ? body.slice(0, 300) : body;
      }
      if (path === "/ocutalon/api/v1/state" && req.method === "GET") return f.get("state") === "500" ? json(500, { error: { code: "server_error", message: "failed" } }) : json(200, stateOf(s, f));
      if (path === "/ocutalon/api/v1/messages" && req.method === "POST") {
        let m;
        try { m = JSON.parse(body); } catch (e) { return json(400, { error: { code: "bad_message", message: "bad" } }); }
        if (!s.msg) {
          s.msg = m;
          s.msgAt = Date.now();
        }
        return json(202, { clientId: m.clientId });
      }
      if (path === "/ocutalon/api/v1/demo/break-feed" && req.method === "POST") {
        if (f.has("not-watching") || !s.msg) return json(409, { error: { code: "not_watching", message: "Ask OcuTalon to watch Orders first." } });
        s.started = Math.floor(Date.now() / 1000) * 1000;
        s.noticeAt = s.started + Number(f.get("notice") || 5) * 1000;
        return json(200, { state: "sent", startedAt: iso(s.started) });
      }
      if (path === "/ocutalon/api/v1/approvals/ap1/answer" && req.method === "POST") {
        const b = JSON.parse(body || "{}");
        if (s.started === null || b.action !== "approve" || b.channel !== "phone") return json(400, { error: { code: "bad_answer", message: "bad" } });
        s.resolved = true;
        return json(200, { result: "done" });
      }
      if (path === "/ocutalon/api/v1/session/end" && req.method === "POST") {
        if (f.get("signout") === "fail") return json(500, { error: { code: "server_error", message: "failed" } });
        end(s, "api");
        return send(204, {}, "");
      }
    }
    return send(404, { "Content-Type": "text/plain" }, "not found");
  });
});
server.listen(0, "127.0.0.1", () => console.log(server.address().port));
STUB
url="http://127.0.0.1:$stub_port"
closed_port=$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')

fwd7="198.51.100.81 198.51.100.82 198.51.100.83 198.51.100.84 198.51.100.85 198.51.100.86 198.51.100.87"
fwd4="198.51.100.91 198.51.100.92 198.51.100.93 198.51.100.94"
ifc7="192.0.2.11 192.0.2.12 192.0.2.13 192.0.2.14 192.0.2.15 192.0.2.16 192.0.2.17"
ifc4="192.0.2.11 192.0.2.12 192.0.2.13 192.0.2.14"
# fwd_n <visitors>: the first visitors+1 addresses of fwd7.
fwd_n() { printf '%s' "$fwd7" | cut -d' ' -f1-$(($1 + 1)); }

# set_flags [<flag>...]: the stand-in's flags for the next runs, in a new generation (the stand-in drops its sessions), and an empty record.
flag_gen=0
set_flags() {
  flag_gen=$((flag_gen + 1))
  printf '%s\n' "gen=$flag_gen" ${1+"$@"} > "$flags"
  : > "$record"
}

# run_load [VAR=value | -u:VAR]... -- [<script argument>...]: one run of the script; leaves the exit code in rc, standard output in
# $tmp/out and standard error in $tmp/err. The environment starts without any OCUTALON_GATE_* or OCUTALON_LOAD_* variable.
run_seconds=0
runs=0
run_load() {
  local e=() t0=$SECONDS
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    e+=("$1")
    shift
  done
  shift
  (
    unset OCUTALON_GATE_USER OCUTALON_GATE_PASSWORD OCUTALON_LOAD_INTERFACES OCUTALON_LOAD_FORWARDED_FOR OCUTALON_LOAD_UNITS_COMMAND OCUTALON_LOAD_WATCH_TEXT
    for w in ${e[@]+"${e[@]}"}; do
      case $w in
        -u:*) unset "${w#-u:}" ;;
        *) export "$w" ;;
      esac
    done
    bash "$script" ${1+"$@"} > "$tmp/out" 2> "$tmp/err" < /dev/null
  )
  rc=$?
  run_seconds=$((run_seconds + SECONDS - t0))
  runs=$((runs + 1))
}

# --- helpers on the output and on the stand-in's record ---

vline() { grep "^VISITOR $1 " "$tmp/out"; }
n_lines() { grep -c "$1" "$tmp/out"; }
rec() { jq -s "$1" "$record"; }                                       # a jq program over all records, slurped
count_post() { rec "[.[] | select(.m? == \"POST\" and (.u | test(\"$1\")))] | length"; } # POSTs whose path matches
methods_seen() { jq -r '.m // empty' "$record" | LC_ALL=C sort -u | tr '\n' ' '; }
sessions_ok() { # <label> <expected number of sessions>: one session per issued id, every one ended
  local issued ended n
  issued=$(jq -r '.issued // empty' "$record" | LC_ALL=C sort | tr '\n' ' ')
  ended=$(jq -r '.ended // empty' "$record" | LC_ALL=C sort -u | tr '\n' ' ')
  n=$(printf '%s\n' "$issued" | wc -w | tr -d ' ')
  if [ "$n" = "$2" ] && [ "$issued" = "$ended" ]; then
    pass "$1: the stand-in opened $n session(s) and saw each one ended"
  else
    fail "$1: opened [$issued], ended [$ended], wanted $2 session(s), each ended"
  fi
}
table_rows() { grep -c '^| [0-9]' "$tmp/out"; }

# --- row S1: case 1 ---

row_s1() {
  local i l ok=1 addrs
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 0 ]; then pass "S1: case 1 (6 visitors, 12 turns) exits 0"; else fail "S1: exit $rc: $(tail -n 3 "$tmp/out" | tr '\n' '|')"; fi
  for i in 1 2 3 4 5 6; do
    l=$(vline $i)
    case $l in
      "VISITOR $i PASS signin=ok path=driven "*" notice=5 fix=resolved "*) ;;
      *) ok=0 ;;
    esac
  done
  if [ "$ok" = 1 ] && [ "$(n_lines '^VISITOR [0-9] PASS')" = 6 ]; then
    pass "S1: six VISITOR PASS lines, each driven with notice=5 and fix=resolved"
  else
    fail "S1: the visitor lines are not six PASS lines of driven visitors: $(grep '^VISITOR' "$tmp/out" | head -n 2 | tr '\n' '|')"
  fi
  if grep -q '^EXTRA PASS status=busy splash=busy signin=busy$' "$tmp/out"; then pass "S1: EXTRA PASS, busy in all three"; else fail "S1: $(grep '^EXTRA' "$tmp/out")"; fi
  if [ "$(table_rows)" = 7 ] && grep -q '^Model turns used: 12 of at most 12\.$' "$tmp/out" && grep -q '^demo-load: 7 passed, 0 failed$' "$tmp/out"; then
    pass "S1: the table has 7 rows, then 'Model turns used: 12 of at most 12.' and the summary"
  else
    fail "S1: table rows $(table_rows); $(grep -E '^(Model turns|demo-load)' "$tmp/out" | tr '\n' '|')"
  fi
  if [ "$(count_post 'api/v1/messages$')" = 6 ] && [ "$(count_post 'demo/break-feed$')" = 6 ]; then
    pass "S1: the stand-in saw 6 message POSTs and 6 Break the feed POSTs"
  else
    fail "S1: message POSTs $(count_post 'api/v1/messages$'), Break the feed POSTs $(count_post 'demo/break-feed$')"
  fi
  if [ "$(methods_seen)" = "GET POST " ]; then pass "S1: the stand-in saw GET and POST and no other method"; else fail "S1: methods '$(methods_seen)'"; fi
  addrs=$(jq -r '.addr // empty | select(. != "")' "$record" | LC_ALL=C sort | tr '\n' ' ')
  if [ "$addrs" = "198.51.100.81 198.51.100.82 198.51.100.83 198.51.100.84 198.51.100.85 198.51.100.86 " ]; then
    pass "S1: one session per visitor address, and none for the one more visitor's"
  else
    fail "S1: sessions by address: [$addrs]"
  fi
  sessions_ok "S1" 6
  if [ "$(rec '[.[] | select(.env? == "bad")] | length')" = 0 ] && [ "$(rec '[.[] | select(.env? == "ok")] | length')" -gt 12 ]; then
    pass "S1: every POST under /ocutalon/api/ carried the browser envelope"
  else
    fail "S1: a POST under /ocutalon/api/ lacked the browser envelope"
  fi
  if [ "$(rec '[.[] | select(.m == "GET" and (.u | test("^/ocutalon/(public/status)?(\\?|$)|/api/v1/state")) and (.u | test("[?&]t=[0-9]+x[0-9]+") | not))] | length')" = 0 ]; then
    pass "S1: every page GET carries a t query"
  else
    fail "S1: a page GET has no t query"
  fi
  if [ "$(rec '[.[] | select(.m == "GET") | .u] | (length > 40) and (length == (unique | length))')" = true ]; then
    pass "S1: no two GETs of the run asked for the same URL"
  else
    fail "S1: $(rec '[.[] | select(.m == "GET") | .u] | length') GETs, $(rec '[.[] | select(.m == "GET") | .u] | unique | length') distinct URLs"
  fi
  # The one more visitor's own address: its status read, splash and sign-in (at least 3 requests) carry the 7th address (S12's interface
  # run checks that every visitor's calls carry its own address).
  if [ "$(rec '[.[] | select(.xff == "198.51.100.87")] | length')" -ge 3 ]; then
    pass "S1: the one more visitor's requests carry its own X-Forwarded-For"
  else
    fail "S1: $(rec '[.[] | select(.xff == "198.51.100.87")] | length') requests carry the one more visitor's address"
  fi
  # The notice is the first phone item at or after the press: an older item is skipped, and its approval is not answered.
  set_flags early-phone
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 1)" -- "$url" --visitors 1 --max-turns 2
  case $(vline 1) in
    "VISITOR 1 PASS signin=ok path=driven "*" notice=5 fix=resolved "*) pass "S1: a phone item older than the press is skipped, the notice is the later item (notice=5)" ;;
    *) fail "S1: with an older phone item first: $(vline 1)" ;;
  esac
}

# --- row S2: the bound ---

row_s2() {
  local i l ok=1 gap
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 5
  for i in 1 2; do case $(vline $i) in *" path=driven "*) ;; *) ok=0 ;; esac; done
  for i in 3 4 5 6; do case $(vline $i) in *" path=signed-in "*) ;; *) ok=0 ;; esac; done
  if [ "$rc" = 0 ] && [ "$ok" = 1 ]; then pass "S2: with 5 turns, visitors 1 and 2 drive and 3 to 6 only sign in (exit 0)"; else fail "S2: exit $rc, driven set wrong: $(grep '^VISITOR' "$tmp/out" | cut -c1-70 | tr '\n' '|')"; fi
  if [ "$(count_post 'api/v1/messages$')" = 2 ] && [ "$(count_post 'demo/break-feed$')" = 2 ] && grep -q '^Model turns used: 4 of at most 5\.$' "$tmp/out"; then
    pass "S2: exactly 2 message POSTs and 2 Break the feed POSTs, 'Model turns used: 4 of at most 5.'"
  else
    fail "S2: message POSTs $(count_post 'api/v1/messages$'), Break the feed POSTs $(count_post 'demo/break-feed$'), $(grep '^Model turns' "$tmp/out")"
  fi
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 0
  if [ "$rc" = 0 ] && [ "$(count_post 'api/v1/messages$')" = 0 ] && [ "$(count_post 'demo/break-feed$')" = 0 ] && grep -q '^Model turns used: 0 of at most 0\.$' "$tmp/out"; then
    pass "S2: with 0 turns no message and no Break the feed is sent (exit 0)"
  else
    fail "S2: --max-turns 0: exit $rc, message POSTs $(count_post 'api/v1/messages$')"
  fi
  l=$(grep -c '^VISITOR [0-9] PASS signin=ok path=signed-in ' "$tmp/out")
  if [ "$l" = 6 ]; then pass "S2: all six visitors passed as signed-in only"; else fail "S2: $l signed-in PASS lines"; fi
  # More turns observed than the bound: the run says so and fails.
  set_flags extra-turn
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 2)" -- "$url" --visitors 2 --max-turns 4
  if [ "$rc" = 1 ] && grep -q '^TURNS FAIL used 6 of at most 4$' "$tmp/out" && grep -q '^Model turns used: 6 of at most 4\.$' "$tmp/out"; then
    pass "S2: turns observed beyond the bound print TURNS FAIL used 6 of at most 4 (exit 1)"
  else
    fail "S2: extra turns: exit $rc; $(grep -E '^(TURNS|Model|demo-load)' "$tmp/out" | tr '\n' '|')"
  fi
  # A driver that ends first keeps polling /state until the last driver ends, so its session never idles to its timeout.
  set_flags slow-turn=198.51.100.81:10
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 2)" -- "$url" --visitors 2 --max-turns 4
  gap=$(rec '[.[] | select(.xff? == "198.51.100.82" and .m == "GET" and (.u | test("api/v1/state"))) | .ts] as $t | [range(1; $t | length) | $t[.] - $t[. - 1]] | max // 99999')
  if [ "$(n_lines '^VISITOR [12] PASS signin=ok path=driven ')" = 2 ] && [ "$gap" -lt 7500 ] 2> /dev/null; then
    pass "S2: the driver that ends first polls /state until the slow driver ends (longest pause $gap ms)"
  else
    fail "S2: slow turn: longest pause between visitor 2's state reads $gap ms; $(grep '^VISITOR' "$tmp/out" | cut -c1-120 | tr '\n' '|')"
  fi
}

# --- row S3: Visual Trace ---

row_s3() {
  local pages bad
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd4" -- "$url" --visitors 3 --trace --max-turns 6
  if [ "$rc" = 0 ] && [ "$(n_lines '^VISITOR [0-9] PASS .* trace=2 ')" = 3 ] && grep -q '^EXTRA PASS status=busy splash=busy signin=busy$' "$tmp/out"; then
    pass "S3: three visitors with Visual Trace each open 2 pages, and the one more visitor is busy at 6 trace sessions (exit 0)"
  else
    fail "S3: exit $rc; $(grep -E '^(VISITOR|EXTRA)' "$tmp/out" | cut -c1-90 | tr '\n' '|')"
  fi
  pages=$(rec '[.[] | select(.u? and (.u | test("^/ocutalon/trace/[a-z]+/Ens")))] | length')
  bad=$(rec '. as $a | [range(1; $a | length) | select($a[.].u? and ($a[.].u | test("^/ocutalon/trace/[a-z]+/Ens"))) | select(($a[. - 1].u | test("^/ocutalon/public/status\\?for=trace&t=")) | not)] | length')
  if [ "$pages" = 6 ] && [ "$bad" = 0 ]; then pass "S3: all 6 trace pages follow a /status?for=trace read"; else fail "S3: $pages trace pages, $bad without a trace status read before"; fi
  set_flags
  run_load -- "$url" --visitors 3 --trace --max-turns 5
  if [ "$rc" = 2 ] && [ ! -s "$record" ]; then pass "S3: --trace with 5 turns for 3 visitors is a usage error and nothing is sent"; else fail "S3: --trace --max-turns 5: exit $rc, record $(wc -l < "$record" | tr -d ' ') lines"; fi
  # A fourth visitor meets the busy trace form before its first page.
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 4)" -- "$url" --visitors 4 --trace --max-turns 8
  if [ "$rc" = 1 ] && [ "$(n_lines '^VISITOR [123] PASS .* trace=2 ')" = 3 ] && [ "$(n_lines '^VISITOR 4 FAIL .* trace=busy .* why=the trace form was busy before a page$')" = 1 ]; then
    pass "S3: a fourth visitor at 6 trace sessions fails with trace=busy and the reason (exit 1)"
  else
    fail "S3: four visitors: exit $rc; $(grep -E '^VISITOR' "$tmp/out" | cut -c1-120 | tr '\n' '|')"
  fi
  set_flags trace=form
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 1)" -- "$url" --visitors 1 --trace --max-turns 2
  if [ "$(n_lines '^VISITOR 1 FAIL .* why=a trace page asked for an IRIS sign-in$')" = 1 ]; then
    pass "S3: a trace page that asks for an IRIS sign-in fails the visitor"
  else
    fail "S3: trace form: $(vline 1)"
  fi
  set_flags trace=500
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 1)" -- "$url" --visitors 1 --trace --max-turns 2
  if [ "$(n_lines '^VISITOR 1 FAIL .* why=a trace page answered 500$')" = 1 ]; then
    pass "S3: a trace page that answers 500 fails the visitor"
  else
    fail "S3: trace 500: $(vline 1)"
  fi
}

# --- row S4: a late notice ---

row_s4() {
  set_flags notice=61
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 1 ] && [ "$(n_lines '^VISITOR [0-9] FAIL .* notice=61 .* why=notice over 60 s$')" = 6 ]; then
    pass "S4: a notice of 61 s fails each driven visitor with why=notice over 60 s (exit 1)"
  else
    fail "S4: exit $rc; $(grep '^VISITOR' "$tmp/out" | head -n 1 | cut -c1-200)"
  fi
  sessions_ok "S4" 6
  if [ "$(n_lines '^VISITOR [0-9] FAIL .* signout=ok ')" = 6 ]; then pass "S4: every visitor is signed out"; else fail "S4: not every visitor is signed out"; fi
}

# --- row S5: fallbacks ---

row_s5() {
  local r l
  for r in no_key timeout rate_limited daily_cap; do
    set_flags "fallback=$r"
    run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
    l=$(vline 1)
    case $l in
      "VISITOR 1 FAIL "*" fallback=$r "*) pass "S5: a turn that falls back for $r fails the visitor (exit $rc)" ;;
      *) fail "S5: fallback $r: $l" ;;
    esac
  done
  set_flags inc-fallback=no_key
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  l=$(vline 1)
  case $l in
    "VISITOR 1 FAIL "*" fallback=no_key "*) pass "S5: an incident that falls back for no_key fails the visitor" ;;
    *) fail "S5: incident fallback: $l" ;;
  esac
  set_flags fallback=invalid
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  l=$(vline 1)
  case $l in
    "VISITOR 1 PASS "*" fallback=invalid "*) pass "S5: a turn that falls back for invalid passes and the line names it" ;;
    *) fail "S5: invalid: $l" ;;
  esac
  if [ "$rc" = 0 ] && grep -q '^| 1 | yes | driven | 2 | 5 | yes | resolved | - | invalid |' "$tmp/out"; then
    pass "S5: the table row names the fallback invalid (exit 0)"
  else
    fail "S5: exit $rc; table row $(grep '^| 1 ' "$tmp/out")"
  fi
  # Server text outside the safe characters is printed as _: the line keeps its fields and the table row its 11 cells.
  set_flags 'fallback=a|b<c'
  run_load -- "$url" --visitors 1 --max-turns 2
  if [ "$(n_lines '^VISITOR 1 PASS .* fallback=a_b_c ')" = 1 ] && [ "$(grep '^| 1 ' "$tmp/out" | tr -cd '|' | wc -c | tr -d ' ')" = 12 ]; then
    pass "S5: a fallback reason with | and < is printed as a_b_c, and the table row keeps its 11 cells"
  else
    fail "S5: unsafe text: $(vline 1); table row $(grep '^| 1 ' "$tmp/out")"
  fi
}

# --- row S6: the watch does not start ---

row_s6() {
  local t0=$SECONDS l
  set_flags not-watching
  run_load -- "$url" --visitors 1 --max-turns 2
  l=$(vline 1)
  case $l in
    "VISITOR 1 FAIL "*" why=not watching") pass "S6: Break the feed answering 409 not_watching fails with why=not watching" ;;
    *) fail "S6: $l" ;;
  esac
  if [ "$(count_post 'api/v1/messages$')" = 1 ] && [ "$(count_post 'demo/break-feed$')" -ge 5 ] && [ $((SECONDS - t0)) -ge 20 ]; then
    pass "S6: exactly one message POST, Break the feed retried for 20 s ($((SECONDS - t0)) s in all)"
  else
    fail "S6: message POSTs $(count_post 'api/v1/messages$'), Break the feed POSTs $(count_post 'demo/break-feed$'), $((SECONDS - t0)) s"
  fi
}

# --- row S7: the one more visitor gets in ---

row_s7() {
  set_flags extra=admit
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 1 ] && grep -q '^EXTRA FAIL .*signin=admitted$' "$tmp/out"; then pass "S7: a sign-in that admits past the cap is EXTRA FAIL signin=admitted (exit 1)"; else fail "S7: exit $rc; $(grep '^EXTRA' "$tmp/out")"; fi
  sessions_ok "S7" 7
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 2)" -- "$url" --visitors 2 --max-turns 4
  if [ "$rc" = 1 ] && grep -q '^EXTRA FAIL status=free splash=form signin=admitted$' "$tmp/out"; then
    pass "S7: under the cap the one more visitor gets in: EXTRA FAIL status=free splash=form signin=admitted (exit 1)"
  else
    fail "S7: exit $rc; $(grep '^EXTRA' "$tmp/out")"
  fi
  sessions_ok "S7 (under the cap)" 3
}

# --- row S8: an error page ---

row_s8() {
  set_flags extra=error
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 1 ] && grep -q '^EXTRA FAIL .*splash=error' "$tmp/out"; then pass "S8: a 500 splash while busy is EXTRA FAIL splash=error (exit 1)"; else fail "S8: exit $rc; $(grep '^EXTRA' "$tmp/out")"; fi
  # The host's busy page has no form: the one more visitor posts the run's sign-in from its own address and reads busy.
  set_flags extra=page
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 0
  if [ "$rc" = 0 ] && grep -q '^EXTRA PASS status=busy splash=busy signin=busy$' "$tmp/out" && [ "$(rec '[.[] | select(.m? == "POST" and .u == "/ocutalon/" and .xff == "198.51.100.87")] | length')" = 1 ]; then
    pass "S8: a busy page with no form: the one more visitor still posts the sign-in and reads EXTRA PASS (exit 0)"
  else
    fail "S8: busy page with no form: exit $rc; $(grep '^EXTRA' "$tmp/out")"
  fi
}

# --- row S9: a failed sign-out ---

row_s9() {
  local ids id n ok=1 c
  set_flags signout=fail
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd4" -- "$url" --visitors 3 --max-turns 6
  if [ "$rc" = 1 ] && [ "$(n_lines '^VISITOR [0-9] FAIL .* signout=failed ')" = 3 ]; then
    pass "S9: a session/end answering 500 fails every visitor with signout=failed (exit 1)"
  else
    fail "S9: exit $rc; $(grep '^VISITOR' "$tmp/out" | head -n 1 | cut -c1-200)"
  fi
  ids=$(jq -r '.issued // empty' "$record")
  for id in $ids; do
    n=$(rec "[.[] | select(.sid? == \"$id\" and (.u | test(\"^/ocutalon/\\\\?IRISLogout=end\")))] | length")
    [ "$n" -ge 1 ] || ok=0
  done
  if [ "$ok" = 1 ] && [ -n "$ids" ]; then pass "S9: every jar's ?IRISLogout=end still reached the stand-in"; else fail "S9: a session had no ?IRISLogout=end"; fi
  # A sign-in that opened a session but whose first state read failed is still signed out.
  set_flags state=500
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$(fwd_n 1)" -- "$url" --visitors 1 --max-turns 0
  if [ "$rc" = 1 ] && [ "$(n_lines '^VISITOR 1 FAIL signin=error ')" = 1 ]; then pass "S9: a sign-in whose state read fails is signin=error (exit 1)"; else fail "S9: state 500: exit $rc; $(vline 1)"; fi
  sessions_ok "S9 (state 500)" 2
  # A sign-in that the demo refuses is classified by its page.
  for c in busy limit refused; do
    set_flags "signin=$c"
    run_load -- "$url" --visitors 1 --max-turns 0
    if [ "$rc" = 1 ] && [ "$(n_lines "^VISITOR 1 FAIL signin=$c .* why=sign-in $c\$")" = 1 ]; then pass "S9: a sign-in answered with the $c page is signin=$c (exit 1)"; else fail "S9: signin=$c: exit $rc; $(vline 1)"; fi
  done
}

# --- row S10: preconditions ---

row_s10() {
  local label
  set_flags ready=false
  run_load -- "$url" --visitors 1 --max-turns 0
  if [ "$rc" = 2 ] && grep -qi 'not ready' "$tmp/err" && [ "$(wc -l < "$record" | tr -d ' ')" = 1 ]; then pass "S10: a demo that is not ready is exit 2 after the one status read"; else fail "S10 ready=false: exit $rc, $(head -n 1 "$tmp/err"), $(wc -l < "$record" | tr -d ' ') requests"; fi
  set_flags busy=true
  run_load -- "$url" --visitors 1 --max-turns 0
  if [ "$rc" = 2 ] && grep -qi 'already busy' "$tmp/err" && [ "$(wc -l < "$record" | tr -d ' ')" = 1 ]; then pass "S10: a demo that is busy before any sign-in is exit 2 after the one status read"; else fail "S10 busy: exit $rc, $(head -n 1 "$tmp/err"), $(wc -l < "$record" | tr -d ' ') requests"; fi
  set_flags gate=on
  run_load -- "$url" --visitors 1 --max-turns 0
  if [ "$rc" = 2 ] && grep -qi 'gate refused' "$tmp/err" && [ "$(wc -l < "$record" | tr -d ' ')" = 1 ]; then pass "S10: a closed gate and no credentials is exit 2 after the one request"; else fail "S10 gate: exit $rc, $(head -n 1 "$tmp/err"), $(wc -l < "$record" | tr -d ' ') requests"; fi
  run_load "OCUTALON_GATE_USER=$gate_user" "OCUTALON_GATE_PASSWORD=wrong$gate_password" -- "$url" --visitors 1 --max-turns 0
  if [ "$rc" = 2 ] && grep -qi 'gate refused' "$tmp/err"; then pass "S10: wrong gate credentials are exit 2"; else fail "S10 wrong credentials: exit $rc"; fi
  set_flags
  run_load -- "http://127.0.0.1:$closed_port" --visitors 1 --max-turns 0
  label=$(head -n 1 "$tmp/err")
  if [ "$rc" = 2 ] && printf '%s' "$label" | grep -qi 'unreachable'; then pass "S10: a closed port is exit 2, naming the cause"; else fail "S10 closed port: exit $rc, $label"; fi
}

# --- row S11: usage ---

expect_usage() { # <label> [VAR=value]... -- [<script argument>...]
  local label=$1
  shift
  set_flags
  run_load "$@"
  if [ "$rc" = 2 ] && [ ! -s "$record" ] && grep -q '^usage: ' "$tmp/err"; then pass "S11: $label is a usage error: exit 2 with nothing sent"; else fail "S11: $label: exit $rc, $(wc -l < "$record" | tr -d ' ') requests"; fi
}
row_s11() {
  expect_usage "no base URL" -- --visitors 1 --max-turns 0
  expect_usage "a base URL with a path" -- "$url/x" --visitors 1 --max-turns 0
  expect_usage "--visitors 0" -- "$url" --visitors 0 --max-turns 0
  expect_usage "--visitors 9" "OCUTALON_LOAD_FORWARDED_FOR=$fwd7 198.51.100.88 198.51.100.89 198.51.100.90" -- "$url" --visitors 9 --max-turns 0
  expect_usage "--max-turns missing" -- "$url" --visitors 1
  expect_usage "--max-turns x" -- "$url" --visitors 1 --max-turns x
  expect_usage "--visitors missing" -- "$url" --max-turns 0
  expect_usage "a list of the wrong length" "OCUTALON_LOAD_FORWARDED_FOR=198.51.100.81 198.51.100.82" -- "$url" --visitors 3 --max-turns 0
  expect_usage "a list with a repeat" "OCUTALON_LOAD_FORWARDED_FOR=198.51.100.81 198.51.100.82 198.51.100.81 198.51.100.84" -- "$url" --visitors 3 --max-turns 0
  expect_usage "an interface list of the wrong length" "OCUTALON_LOAD_INTERFACES=192.0.2.11" -- "$url" --visitors 3 --max-turns 0
  expect_usage "an entry that is no address" "OCUTALON_LOAD_FORWARDED_FOR=198.51.100.81 198.51.100.82 198.51.100.83 a;b" -- "$url" --visitors 3 --max-turns 0
  expect_usage "both lists" "OCUTALON_LOAD_FORWARDED_FOR=$fwd4" "OCUTALON_LOAD_INTERFACES=$ifc4" -- "$url" --visitors 3 --max-turns 0
  expect_usage "5 visitors and no list" -- "$url" --visitors 5 --max-turns 0
  expect_usage "--hold 601" -- "$url" --visitors 1 --max-turns 0 --hold 601
  expect_usage "--hold 91 with --trace" -- "$url" --visitors 1 --max-turns 2 --trace --hold 91
  expect_usage "an unknown option" -- "$url" --visitors 1 --max-turns 0 --bogus
  expect_usage "one gate variable alone" "OCUTALON_GATE_USER=$gate_user" -- "$url" --visitors 1 --max-turns 0
  expect_usage "a gate user with a colon" "OCUTALON_GATE_USER=a:b" "OCUTALON_GATE_PASSWORD=$gate_password" -- "$url" --visitors 1 --max-turns 0
  expect_usage "a gate password with a line break" "OCUTALON_GATE_USER=$gate_user" "OCUTALON_GATE_PASSWORD=$gate_password"$'\n'"url = x" -- "$url" --visitors 1 --max-turns 0
}

# --- row S12: credentials, addresses and output ---

row_s12() {
  local i a leaks bad_auth n_auth missing lines_without secrets shim_secrets
  curl_shim "$tmp/shim"
  : > "$tmp/shim.log"
  set_flags gate=on
  run_load "OCUTALON_GATE_USER=$gate_user" "OCUTALON_GATE_PASSWORD=$gate_password" "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" "PATH=$tmp/shim:$PATH" "SHIM_LOG=$tmp/shim.log" "SHIM_REAL=$(command -v curl)" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 0 ]; then pass "S12: a run with the gate credentials set passes (exit 0)"; else fail "S12: exit $rc: $(tail -n 3 "$tmp/out" | tr '\n' '|')"; fi
  n_auth=$(rec '[.[] | select(.m?)] | length')
  bad_auth=$(rec '[.[] | select(.m? and .auth != "ok")] | length')
  if [ "$n_auth" -gt 50 ] && [ "$bad_auth" = 0 ]; then pass "S12: every one of the $n_auth requests carried the basic authentication"; else fail "S12: $bad_auth of $n_auth requests lacked the basic authentication"; fi
  shim_min=50
  # The secrets also in the forms a command line could carry them: the account percent-encoded (the sign-in body) and the gate's base64.
  shim_secrets=("$gate_password" "$gate_user" "$acct_password" "$acct_user" "$(pct "$acct_password")" "$(pct "$acct_user")" "$(printf '%s' "$gate_user:$gate_password" | base64 | tr -d '\n')")
  shim_checks "$tmp/shim.log" "S12" "${shim_secrets[@]}"
  secrets=("$url" "127.0.0.1" ":$stub_port" "$gate_user" "$gate_password" "$acct_user" "$acct_password")
  for a in $fwd7; do secrets+=("$a"); done
  leaks=0
  for a in "${secrets[@]}"; do
    if grep -qF -- "$a" "$tmp/out" "$tmp/err"; then leaks=$((leaks + 1)); fi
  done
  if [ "$leaks" = 0 ]; then pass "S12: standard output and standard error hold no base URL, port, address, credential or published account"; else fail "S12: $leaks secret(s) appear in the output"; fi

  # The interface list: each visitor's calls carry its own --interface (the shim logs it and drops it).
  curl_shim "$tmp/shim" strip-interface
  : > "$tmp/shim.log"
  set_flags gate=on
  run_load "OCUTALON_GATE_USER=$gate_user" "OCUTALON_GATE_PASSWORD=$gate_password" "OCUTALON_LOAD_INTERFACES=$ifc7" "PATH=$tmp/shim:$PATH" "SHIM_LOG=$tmp/shim.log" "SHIM_REAL=$(command -v curl)" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 0 ]; then pass "S12: a run with an interface list passes (exit 0)"; else fail "S12 (interfaces): exit $rc: $(tail -n 3 "$tmp/out" | tr '\n' '|')"; fi
  missing=""
  i=0
  for a in $ifc7; do
    i=$((i + 1))
    if ! grep '^ARGV' "$tmp/shim.log" | grep -F "/v$i/h]" | grep -qF "[--interface] [$a]"; then missing="$missing $i"; fi
    if grep '^ARGV' "$tmp/shim.log" | grep -F "/v$i/h]" | grep -F "[--interface] [" | grep -vqF "[--interface] [$a]"; then missing="$missing $i(other)"; fi
  done
  lines_without=$(grep '^ARGV' "$tmp/shim.log" | grep -vcF '[--interface] [')
  if [ -z "$missing" ] && [ "$lines_without" = 0 ]; then pass "S12: each visitor's calls carry its own --interface, and no call lacks one"; else fail "S12: visitors without their own --interface:$missing; $lines_without calls without one"; fi
  shim_checks "$tmp/shim.log" "S12 (interfaces)" "${shim_secrets[@]}"
  shim_min=20
  leaks=0
  for a in $ifc7 "$url" "$gate_password" "$acct_password" "$acct_user"; do
    if grep -qF -- "$a" "$tmp/out" "$tmp/err"; then leaks=$((leaks + 1)); fi
  done
  if [ "$leaks" = 0 ]; then pass "S12: the interface run's output holds no address, base URL, credential or published account"; else fail "S12 (interfaces): $leaks secret(s) appear in the output"; fi
}

# --- row S13: licence readings ---

row_s13() {
  printf '%s\n' '#!/bin/sh' 'echo "3 2"' 'echo "second line 9 9"' > "$tmp/units3.sh"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$tmp/units0.sh"
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" "OCUTALON_LOAD_UNITS_COMMAND=bash $tmp/units3.sh" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 0 ] && [ "$(n_lines '^VISITOR [0-9] PASS .* units=3/2 signout=ok$')" = 6 ] && grep -q '^UNITS before=3/2 load=3/2 after=3/2$' "$tmp/out" && [ "$(grep -c '| 3/2 |' "$tmp/out")" = 7 ]; then
    pass "S13: the readings appear as 3/2 in every line, in the UNITS line and in the table (7 rows)"
  else
    fail "S13: exit $rc; $(grep -E '^(UNITS|VISITOR 1)' "$tmp/out" | cut -c1-200 | tr '\n' '|')"
  fi
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" "OCUTALON_LOAD_UNITS_COMMAND=bash $tmp/units0.sh" -- "$url" --visitors 6 --max-turns 12
  if [ "$rc" = 0 ] && [ "$(n_lines '^VISITOR [0-9] PASS .* units=? signout=ok$')" = 6 ] && grep -q '^UNITS before=? load=? after=?$' "$tmp/out"; then
    pass "S13: a command that prints nothing reads units=? and fails nothing (exit 0)"
  else
    fail "S13: no output: exit $rc; $(grep -E '^(UNITS|VISITOR 1)' "$tmp/out" | cut -c1-200 | tr '\n' '|')"
  fi
  run_load "OCUTALON_LOAD_UNITS_COMMAND=bash $tmp/units3.sh; touch $tmp/evaluated" -- "$url" --visitors 1 --max-turns 0
  if [ ! -e "$tmp/evaluated" ] && grep -q '^UNITS before=? ' "$tmp/out"; then
    pass "S13: the units command is split on white space and evaluated by no shell (the run read '?')"
  else
    fail "S13: the units command was evaluated by a shell, or the run did not read it: $(grep '^UNITS' "$tmp/out")"
  fi
  # The load reading is the run's highest: readings that rise and fall (before 1/1, signed in 5/2, the one more visitor 4/2, after 1/1).
  cat > "$tmp/units-seq.sh" << EOF
#!/bin/sh
n=\$(cat "$tmp/units-n" 2> /dev/null || echo 0)
n=\$((n + 1))
echo "\$n" > "$tmp/units-n"
case \$n in 1) echo "1 1" ;; 2) echo "5 2" ;; 3) echo "4 2" ;; *) echo "1 1" ;; esac
EOF
  rm -f "$tmp/units-n"
  set_flags
  run_load "OCUTALON_LOAD_UNITS_COMMAND=sh $tmp/units-seq.sh" -- "$url" --visitors 1 --max-turns 0
  if grep -q '^UNITS before=1/1 load=5/2 after=1/1$' "$tmp/out" && grep -q '^| 2 (one more) | .* | 4/2 | ' "$tmp/out"; then
    pass "S13: the load reading is the run's highest (5/2), and the one more visitor's row keeps its own reading (4/2)"
  else
    fail "S13: rising and falling readings: $(grep '^UNITS' "$tmp/out"); $(grep '^| 2 (one more)' "$tmp/out")"
  fi
}

# --- row S14: a signal ---

# load_until <jq test on the record> <visitors> <max turns>: starts the script in the background (FORWARDED_FOR the first visitors+1
# addresses of fwd7) and, once the record passes the test (10 s at most), sends it TERM; waits up to 10 s for it to end, leaving the exit
# code in rc, whether it ended in exited and the seconds since the TERM in term_s.
load_until() {
  local pid i t0
  exited=0
  (
    unset OCUTALON_GATE_USER OCUTALON_GATE_PASSWORD OCUTALON_LOAD_INTERFACES OCUTALON_LOAD_UNITS_COMMAND OCUTALON_LOAD_WATCH_TEXT
    export OCUTALON_LOAD_FORWARDED_FOR="$(fwd_n "$2")"
    exec bash "$script" "$url" --visitors "$2" --max-turns "$3" > "$tmp/out" 2> "$tmp/err" < /dev/null
  ) &
  pid=$!
  for i in $(seq 1 100); do
    [ "$(rec "$1" 2> /dev/null)" = true ] && break
    sleep 0.1
  done
  t0=$SECONDS
  kill -TERM "$pid" 2> /dev/null
  for i in $(seq 1 100); do
    if ! kill -0 "$pid" 2> /dev/null; then exited=1; break; fi
    sleep 0.1
  done
  wait "$pid" 2> /dev/null
  rc=$?
  term_s=$((SECONDS - t0))
}

row_s14() {
  local n0 n1 exited term_s
  if grep -q '^trap on_signal INT TERM HUP$' "$script"; then pass "S14: the script traps INT, TERM and HUP alike"; else fail "S14: the script's signal trap is not on_signal for INT, TERM and HUP"; fi
  set_flags hang=turn
  load_until '[.[] | select(.m? == "POST" and (.u | test("api/v1/messages$")))] | length >= 1' 3 6
  if [ "$exited" = 1 ] && [ "$rc" = 130 ] && [ "$term_s" -le 10 ]; then pass "S14: TERM after the first message POST ends the run with exit 130 in $term_s s"; else fail "S14: exit $rc, exited $exited, $term_s s"; fi
  sessions_ok "S14" 3
  n0=$(wc -l < "$record" | tr -d ' ')
  sleep 1
  n1=$(wc -l < "$record" | tr -d ' ')
  if [ "$n0" = "$n1" ]; then pass "S14: no request comes after the sign-outs"; else fail "S14: $((n1 - n0)) request(s) after the run ended"; fi
  if [ "$(rec '[.[] | select(.m? == "GET" and (.u | test("api/v1/state")) and .s == 401)] | length')" -ge 3 ]; then
    pass "S14: each signed-in visitor's state answers 401 after the sign-out"
  else
    fail "S14: fewer than 3 state reads answered 401"
  fi
  # TERM while a sign-in POST waits for its answer: the session it opened is still signed out.
  set_flags signin=slow
  load_until '[.[] | select(.issued?)] | length >= 1' 1 0
  if [ "$exited" = 1 ] && [ "$rc" = 130 ]; then pass "S14: TERM during a sign-in POST ends the run with exit 130"; else fail "S14 (during a sign-in): exit $rc, exited $exited"; fi
  sessions_ok "S14 (TERM during a sign-in)" 1
  set_flags
}

# --- row S15: hold ---

row_s15() {
  local ids id ok=1 span
  set_flags
  run_load "OCUTALON_LOAD_FORWARDED_FOR=$fwd7" -- "$url" --visitors 6 --max-turns 12 --hold 2
  if [ "$rc" = 0 ] && grep -q '^HOLD ' "$tmp/err"; then pass "S15: --hold 2 exits 0 and prints a HOLD line to standard error"; else fail "S15: exit $rc; $(head -n 3 "$tmp/err" | tr '\n' '|')"; fi
  ids=$(jq -r '.issued // empty' "$record")
  for id in $ids; do
    span=$(rec ". as \$a | [\$a | to_entries[] | select(.value.m? == \"POST\" and .value.u == \"/ocutalon/\") | .key] | last as \$p | [\$a[(\$p + 1):][] | select(.sid? == \"$id\" and .m == \"GET\" and (.u | test(\"api/v1/state\")) and .s == 200) | .ts] | if length < 2 then -1 else (max - min) end")
    [ "$span" -ge 2000 ] 2> /dev/null || ok=0
  done
  if [ "$ok" = 1 ] && [ -n "$ids" ]; then pass "S15: after the one more visitor's sign-in POST every session polls /state for at least 2 s"; else fail "S15: a session did not poll for 2 s (last span $span ms)"; fi
  sessions_ok "S15" 6
}

# --- row S16: pins ---

row_s16() {
  local guide probe reasons r missing="" list
  guide=$(sed -n "s/^  promptWatch: '\\(.*\\)',\$/\\1/p" "$root/web/src/app/guide/guide-view.ts")
  if [ -n "$guide" ] && grep -qF "DEFAULT_WATCH='$guide'" "$script"; then pass "S16: the script's default watch text is the guide's promptWatch"; else fail "S16: the default watch text differs from the guide's ($guide)"; fi
  probe=$(grep 'outcome=degraded' "$root/docker/probe.sh" | grep -v '^ *#' | head -n 1)
  reasons=$(printf '%s\n' "$probe" | grep -o 'fallbackReason":"[a-z_]*' | sed 's/.*"//')
  list=$(sed -n 's/^DEGRADED_REASONS="\(.*\)"$/\1/p' "$script")
  for r in $reasons; do
    case " $list " in *" $r "*) ;; *) missing="$missing $r" ;; esac
  done
  if [ "$(printf '%s\n' $reasons | grep -c .)" -ge 3 ] && [ -z "$missing" ]; then pass "S16: the probe's degraded reasons ($(echo $reasons)) are all in the script's list"; else fail "S16: probe reasons [$reasons], missing from the script:$missing"; fi
  set_flags
  run_load -- "$url" --visitors 1 --max-turns 2
  if [ "$(rec '[.[] | select(.b? and (.b | contains("\"fromGuide\":true")))] | length')" = 1 ] && [ "$(rec '[.[] | select(.b? and (.b | contains("Watch the Orders production and only tell me if something needs me.")))] | length')" = 1 ]; then
    pass "S16: the default watch text goes out with fromGuide true"
  else
    fail "S16: the default message body: $(jq -r 'select(.b?) | .b' "$record" | head -n 1)"
  fi
  set_flags
  run_load "OCUTALON_LOAD_WATCH_TEXT=Watch it now" -- "$url" --visitors 1 --max-turns 2
  if [ "$(rec '[.[] | select(.b? and (.b | contains("\"fromGuide\":false")) and (.b | contains("Watch it now")))] | length')" = 1 ]; then
    pass "S16: another watch text goes out with fromGuide false"
  else
    fail "S16: the custom message body: $(jq -r 'select(.b?) | .b' "$record" | head -n 1)"
  fi
}

# --- the rows, in order or in reverse ---

rows="${ONLY_ROWS:-s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16}"
if [ "${TEST_REVERSE:-}" = 1 ]; then
  rev=""
  for r in $rows; do rev="$r $rev"; done
  rows=$rev
fi
for r in $rows; do "row_$r"; done

if LC_ALL=C grep -q '[^[:print:][:space:]]' "$0"; then fail "test-online-load.sh is not ASCII"; else pass "test-online-load.sh is ASCII"; fi

echo "MEASURED test-online-load: $runs script runs took $run_seconds s; the test took $((SECONDS - started)) s"
if [ "$fails" -eq 0 ]; then
  echo "test-online-load: all checks passed"
  exit 0
fi
echo "test-online-load: $fails check(s) failed"
exit 1
