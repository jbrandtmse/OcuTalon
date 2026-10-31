#!/usr/bin/env bash
# Hermetic test of release/demo-host-check.sh and release/demo-host-checks.md (Story 29.3; matrix rows 1 to 16), and, for row 15 (Story
# 29.8), of release/demo-load.sh's files and of the check list's H25. No container and no
# host: one inline Node server on 127.0.0.1 (a random port, docker/tests/lib-stub.sh) stands in for the demo host. It is the proxy and
# the password guard of AD-25 as the lead's ruling U-158 reads it (a sign-in body is a bounded urlencoded POST body whose decoded names
# all come from IRISSessionToken, IRISUsername, IRISPassword and IRISLogin; any other field whose decoded name matches
# (IRIS|Cache)(Old|Repeat)?Password case-insensitively is refused, a sign-in body's one IRISPassword excepted), in front of a fake IRIS
# that answers each probe of host_probes (docker/tests/lib-online.sh) with its <iris> field, the sign-in POSTs and the allowed reads as
# the live online-demo unit measured them, and the busy and maintenance pages from the repository's own files. A flags file, read again
# on every request, breaks one rule at a time ("faults"), so that no run needs a restart. The gate credentials are random per run and
# never printed. Every run is the real script; the test asserts its exit code, the named PASS, FAIL or SKIP lines and, for a fault, the
# exact set of FAIL lines (the fault's check id and no other).
#   row 1   a correct host: every check passes, exit 0; the stand-in saw no method but GET and POST, and the sign-out of every session
#   row 2   the allowed reads; faults: the splash blocked, the broker file blocked
#   row 3   the blocked paths: all let through to IRIS in one run
#   row 4   DW-214: every form at every path, let through (one run for all 56, two single ones)
#   row 5   the guard: one fault per rule
#   row 6   DW-226: the two sign-in POSTs reach IRIS; a guard that requires all four names fails guard-signin-3
#   row 7   no false all-clear in each family: 401 and 404 answers fail, an answer IRIS gives alone is SKIP ambiguous, a mark that an
#           allowed answer carries fails block-mark
#   row 8   a closed gate and no credentials: exit 2 before any check
#   row 9   an open gate: gate-closed fails; no credentials: SKIP
#   row 10  the status JSON    row 11  --demo-status    row 12  --zone
#   row 13  busy    row 14  maintenance (DW-240)
#   row 15  both release scripts (demo-host-check.sh and, Story 29.8, demo-load.sh) and the check list hold no host detail; the check
#           list's rows H1 to H25 hold one of the three statuses
#   row 16  a host that refuses the password-change pages with 404 (the Planner's settings pass, no answer of IRIS counts as a block)
# Needs Node, curl and jq. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/release/demo-host-check.sh"
checklist="$root/release/demo-host-checks.md"

. "$(dirname "$0")/lib-stub.sh"
. "$(dirname "$0")/lib-online.sh"
need_tools node curl jq

started=$SECONDS
flags="$tmp/flags"
record="$tmp/record.jsonl"
probes="$tmp/probes"
: > "$flags"
: > "$record"

gate_user="gate$(hexpw)"
gate_password=$(hexpw)
mark="edge-$(hexpw | head -c 12)"
next_reset=$(node -e 'console.log(new Date(Math.floor(Date.now() / 1000) * 1000 + 2 * 3600 * 1000).toISOString().replace(/\.\d+Z$/, "Z"))')

# The stand-in's table of IRIS's own answers: "<method> <target> <iris>" for every line of host_probes. The same request must have one
# answer, since the stand-in finds a probe by its method and target.
host_probes | while IFS= read -r line; do
  host_probe_args "$line" && printf '%s %s %s\n' "$probe_method" "$probe_target" "$probe_iris"
done > "$probes"
conflicts=$(sort -u "$probes" | awk '{ k = $1 " " $2; if (k in a && a[k] != $3) print k; a[k] = $3 }' | head -n 3)
if [ -z "$conflicts" ]; then
  pass "setup: every request of host_probes has one answer of IRIS ($(wc -l < "$probes" | tr -d ' ') probes)"
else
  fail "setup: host_probes lists two answers of IRIS for the request(s) $conflicts"
fi

STUB_GATE="$gate_user:$gate_password" STUB_MARK="$mark" STUB_BROKER="$(host_broker_file)" STUB_MARKER="$(host_trace_signin_marker)" STUB_NEXT="$next_reset" \
  stub_start "$flags" "$record" "$probes" "$root/docker/busy.html" "$root/docker/maintenance.html" "$root/logo/web" << 'STUB' || exit 1
const http = require("http");
const fs = require("fs");
const path = require("path");
const [flagsFile, recordFile, probesFile, busyFile, maintFile, logoDir] = process.argv.slice(2);
const GATE = process.env.STUB_GATE || "";
const MARK = process.env.STUB_MARK || "";
const BROKER = process.env.STUB_BROKER || "";
const SIGNIN_MARKER = process.env.STUB_MARKER || "";
const NEXT = process.env.STUB_NEXT || "";
const LAST = "2026-10-25T08:00:00Z";
const LIMIT = 4096;
const FOUR = ["IRISSessionToken", "IRISUsername", "IRISPassword", "IRISLogin"];

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
const record = (o) => fs.appendFileSync(recordFile, JSON.stringify(o) + "\n");

// What IRIS alone answers to each refusal probe: "<method> <target>" -> "<status>:<form|noform>".
const iris = new Map();
for (const line of fs.readFileSync(probesFile, "utf8").split("\n")) {
  const [m, t, a] = line.split(" ");
  if (m && !iris.has(m + " " + t)) iris.set(m + " " + t, a);
}

const decodeOnce = (s) => s.replace(/%([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
const decodeStable = (s) => {
  for (let i = 0; i < 10; i++) {
    const d = decodeOnce(s);
    if (d === s) break;
    s = d;
  }
  return s;
};
const normalize = (p) => {
  const out = [];
  for (const seg of p.split("/")) {
    if (seg === "..") { if (out.length > 1) out.pop(); }
    else if (seg !== ".") out.push(seg);
  }
  return out.join("/");
};
const STATIC = /\.(js|css|png|gif|jpg|jpeg|svg|ico|woff2?|ttf|map)$/i;

// The IRIS application of a path, whose session a sign-out must end there (IRIS's own knowledge, not the script's host_app).
const appOf = (p) =>
  p.startsWith("/ocutalon/trace/ocutalon/") ? "/ocutalon/trace/ocutalon/" : p.startsWith("/ocutalon/trace/ocuorders/") ? "/ocutalon/trace/ocuorders/" : p.startsWith("/ocutalon/api/") ? "/ocutalon/api/" : "/ocutalon/";

let nextSession = 0;
const issue = (res, headers, p) => {
  const id = "s" + ++nextSession;
  record({ issued: id, app: appOf(p) });
  headers["Set-Cookie"] = "CSPSESSIONID-SP-TEST=" + id + "; path=/; HttpOnly";
  return id;
};

const formHtml = '<html><body><form method="post"><input type="password" name="IRISPassword"></form></body></html>';
const plainHtml = "<html><body>IRIS</body></html>";
const splashHtml = (refused) =>
  '<!doctype html><html><head><title>Try OcuTalon</title></head><body><form method="post" action="/ocutalon/">' +
  '<input type="text" name="IRISUsername" ' + (refused ? 'aria-invalid="true" ' : "") + '><input type="password" name="IRISPassword" ' + (refused ? 'aria-invalid="true"' : "") + '>' +
  '<input type="submit" name="IRISLogin" value="Sign in"></form></body></html>';

const names = (str, decode) =>
  str.split("&").filter(Boolean).map((p) => {
    const n = p.split("=")[0];
    return decode ? decodeOnce(n.replace(/\+/g, " ")) : n;
  });

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const f = readFlags();
    const body = Buffer.concat(chunks).toString("latin1");
    const url = req.url;
    const qi = url.indexOf("?");
    const rawPath = qi < 0 ? url : url.slice(0, qi);
    const query = qi < 0 ? "" : url.slice(qi + 1);
    const send = (status, headers, text) => {
      record({ m: req.method, u: req.url.length > 300 ? req.url.slice(0, 300) : req.url, c: req.headers.cookie || "", s: status });
      const h = Object.assign({}, headers);
      if (!(text instanceof Buffer)) text = Buffer.from(text, "latin1");
      h["Content-Length"] = text.length;
      res.writeHead(status, h);
      res.end(text);
    };
    // mark_allowed[=<status|splash|broker|signin3|signin4>]: that allowed answer (the status read by default) carries the block mark.
    const markOn = (where, hdrs) => {
      if (MARK && f.has("mark_allowed") && (f.get("mark_allowed") || "status") === where) hdrs["X-Edge-Block"] = MARK;
      return hdrs;
    };
    const refuse = (kind) => {
      const status = Number(f.get(kind + "_status") || f.get("block_status") || 403);
      const h = { "Content-Type": "text/plain" };
      let text = "Blocked";
      if (f.has("refuse_form")) text += " " + formHtml;
      if (MARK) {
        if (f.has("mark_in_body")) text += " " + MARK;
        else h["X-Edge-Block"] = MARK;
      }
      return send(status, h, text);
    };

    // 1. The access gate.
    if (GATE && !f.has("nogate") && !f.has("gate_open")) {
      const want = "Basic " + Buffer.from(GATE).toString("base64");
      if (req.headers.authorization !== want) return send(401, { "WWW-Authenticate": 'Basic realm="gate"' }, "gate");
    }
    // Sign-outs end the session of the cookie.
    if (url.includes("IRISLogout=end")) return send(200, {}, "");

    const decoded = decodeStable(rawPath);
    const norm = normalize(decoded);
    const lower = norm.toLowerCase();
    const state = f.get("state") || "normal";

    // 2. The maintenance and busy pages.
    if (state === "maintenance" && (norm === "/ocutalon" || norm.startsWith("/ocutalon/"))) {
      const bare = /^\/ocutalon\/(OcuTalon-Logo-[a-z]+-[0-9]+\.png)$/.exec(norm);
      const brand = /^\/ocutalon\/assets\/brand\/(OcuTalon-Logo-[a-z]+-[0-9]+\.png)$/.exec(norm);
      const logo = (bare && !(f.get("maint_missing_logo") === bare[1])) ? bare[1] : (brand && !(f.get("maint_no_brand") === brand[1]) ? brand[1] : "");
      if (logo) {
        let png = fs.readFileSync(path.join(logoDir, logo));
        if ((bare && f.get("maint_alter_bare") === logo) || (brand && f.get("maint_alter_brand") === logo)) png = Buffer.concat([png, Buffer.from("x")]);
        return send(200, { "Content-Type": "image/png" }, png);
      }
      if (bare || brand) return send(404, {}, "missing");
      let page = fs.readFileSync(maintFile, "latin1");
      if (f.has("maint_altered")) page = page.replace("Resetting", "Resettinq");
      return send(503, { "Content-Type": "text/html" }, page);
    }
    if (state === "busy") {
      if (norm === "/ocutalon/public/status") {
        const h = { "Content-Type": "application/json", "Cache-Control": "no-store" };
        const busy = !f.has("busy_off");
        if (busy) h["X-OcuTalon-Busy"] = "1";
        return send(200, h, JSON.stringify({ ready: true, nextReset: NEXT, busy, lastReset: LAST, lastResetKind: "scheduled" }));
      }
      if (norm.startsWith("/ocutalon/api/")) {
        if (f.has("busy_api_page")) return send(503, { "Content-Type": "text/html" }, fs.readFileSync(busyFile, "latin1"));
        if (f.has("busy_api_drop")) { req.socket.destroy(); return; }
        return send(503, { "Content-Type": "application/json" }, '{"error":"busy"}');
      }
      if (norm === "/ocutalon" || norm.startsWith("/ocutalon/")) {
        if (f.has("busy_plain")) return send(200, { "Content-Type": "text/html" }, splashHtml(false));
        if (f.has("busy_iris")) return send(200, { "Content-Type": "text/html", "X-OcuTalon-Busy": "1" }, splashHtml(false).replace("</form>", "<p>busy</p></form>"));
        let page = fs.readFileSync(busyFile, "latin1");
        if (f.has("busy_altered")) page = page.replace("Install it yourself", "Install it yourselF");
        return send(503, { "Content-Type": "text/html" }, page);
      }
    }

    // 3. The proxy: what it lets through to IRIS. A let-through target reaches IRIS whatever the rules say (a fault).
    const lets = (f.get(req.method === "POST" ? "letpost" : "let") || "").split("|").filter(Boolean);
    const letThrough = lets.includes(url);
    if (!letThrough) {
      if (f.has("fault_splash") && req.method === "GET" && rawPath === "/ocutalon/") return refuse("block");
      if (f.has("fault_broker") && lower.startsWith("/csp/broker/")) return refuse("block");
      if (lower.includes("passwordchange.cls")) return refuse("pw");
      const ocutalon = norm === "/ocutalon" || norm.startsWith("/ocutalon/");
      const hook = norm === "/ocutalon/hook" || norm.startsWith("/ocutalon/hook/");
      const broker = norm.startsWith("/csp/broker/") && STATIC.test(norm);
      if (hook || !(ocutalon || broker)) return refuse("block");

      // 4. The password guard on IRIS paths.
      const ct = (req.headers["content-type"] || "").toLowerCase();
      const chunked = (req.headers["transfer-encoding"] || "").toLowerCase().includes("chunked");
      const multipart = ct.startsWith("multipart/");
      const pattern = f.has("g_case") ? /^(IRIS|Cache)(Old|Repeat)?Password$/ : f.has("g_legacy") ? /^iris(old|repeat)?password$/i : /^(iris|cache)(old|repeat)?password$/i;
      const decode = !f.has("g_nodecode");
      if (!f.has("g_query") && names(query, decode).some((n) => pattern.test(n))) return refuse("guard");
      if (multipart && !f.has("g_multipart")) return refuse("guard");
      if (chunked && !f.has("g_chunked")) return refuse("guard");
      const inspect = ct.startsWith("application/x-www-form-urlencoded") && !(chunked && f.has("g_chunked"));
      if (inspect) {
        const bn = names(body, decode);
        const hits = bn.filter((n) => pattern.test(n));
        if (hits.length > 0) {
          let ok = req.method === "POST" && !chunked && (f.has("g_size") || body.length <= LIMIT) && hits.length === 1 && hits[0] === "IRISPassword";
          if (ok && !f.has("g_extra")) ok = bn.every((n) => FOUR.includes(n));
          if (ok && f.has("g_exact4")) ok = FOUR.every((n) => bn.includes(n)) && bn.length === 4;
          if (!ok) return refuse("guard");
        }
      }
    }

    // 5. IRIS: the sign-in POSTs the checks send, the allowed reads, then each probe's own answer.
    const h = { "Content-Type": "text/html" };
    const bodyNames = names(body, true).sort().join(",");
    if (req.method === "POST" && rawPath === "/ocutalon/" && bodyNames === "IRISLogin,IRISPassword,IRISUsername") {
      if (f.has("signin_plain")) return send(200, h, plainHtml);
      issue(res, h, rawPath);
      return send(200, markOn("signin3", h), splashHtml(true));
    }
    if (req.method === "POST" && rawPath === "/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen" && bodyNames === "IRISLogin,IRISPassword,IRISSessionToken,IRISUsername") {
      if (f.has("signin_plain")) return send(200, h, plainHtml);
      issue(res, h, rawPath);
      return send(200, markOn("signin4", h), "<html><body>" + SIGNIN_MARKER + '><input type="text" name="IRISUsername"/><input type="password" name="IRISPassword"/></form></body></html>');
    }
    // A probe's request may carry a query that its table target does not (curl -G adds F3's and F4's), so the table is read by the
    // path alone too; the allowed reads carry the unique t parameter and keep their own answers below.
    const answer = iris.get(req.method + " " + url) || (/(^|&)t=[0-9]+(&|$)/.test(query) ? undefined : iris.get(req.method + " " + rawPath));
    if (answer) {
      const [status, form] = answer.split(":");
      if (form === "form") issue(res, h, rawPath);
      return send(Number(status), h, form === "form" ? formHtml : plainHtml);
    }
    if (req.method === "GET" && rawPath === "/ocutalon/public/status") {
      const hh = { "Content-Type": "application/json", "Cache-Control": f.has("status_nocache") ? "max-age=0" : "no-store" };
      markOn("status", hh);
      const s = { ready: true, nextReset: NEXT, busy: false, lastReset: LAST, lastResetKind: "scheduled" };
      if (f.has("status_extra")) s.extra = 1;
      if (f.has("status_missing")) delete s.busy;
      if (f.has("status_type")) s.ready = "yes";
      if (f.has("status_kind")) s.lastResetKind = "bogus";
      if (f.has("status_past")) s.nextReset = "2020-01-01T00:00:00Z";
      return send(200, hh, JSON.stringify(s));
    }
    if (req.method === "GET" && rawPath === "/ocutalon/") {
      issue(res, h, rawPath);
      return send(200, markOn("splash", h), splashHtml(false));
    }
    if (req.method === "GET" && rawPath === BROKER) return send(200, markOn("broker", { "Content-Type": f.has("broker_html") ? "text/html" : "image/png" }), "PNG");
    return send(404, h, plainHtml);
  });
});
server.listen(0, "127.0.0.1", () => console.log(server.address().port));
STUB
url="http://127.0.0.1:$stub_port"

# The probes with their ids, for the rows that pick probes: "<id> <iris> <method> <target> [<body>]".
host_probes > "$tmp/probes.full"
closed_port=$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')

# The status fixture of `ocutalon-demo status` that matches the stand-in's /status, and the zone.
last_reset=2026-10-25T08:00:00Z
write_status_fixture() { # <file> <jq filter applied to the good fixture>
  jq -n --arg last "$last_reset" --arg next "$next_reset" '{runningVersion: "1.0.0", goldenVersion: "1.0.0", lastReset: $last, lastResetKind: "scheduled", nextReset: $next, pendingVersion: null, access: "restricted"}' | jq "$2" > "$1"
}
write_status_fixture "$tmp/ds.json" .
write_status_fixture "$tmp/ds-public.json" '.access = "public"'
printf 'America/New_York\n' > "$tmp/zone.txt"

# set_flags [<flag>...]: the stand-in's flags for the next runs, "name" or "name=value" each.
set_flags() { printf '%s\n' ${1+"$@"} > "$flags"; }

# run_script [VAR=value | -u:VAR]... -- [<script argument>...]: one run of the script against the stand-in with the gate credentials and
# the block mark set (-u:VAR removes a variable); leaves the exit code in rc, standard output in $tmp/out and standard error in $tmp/err.
# Standard input is run_stdin when set. The runs' seconds add up in run_seconds.
run_seconds=0
runs=0
run_script() {
  local e=() t0=$SECONDS
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    e+=("$1")
    shift
  done
  shift
  (
    unset OCUTALON_CHECK_BLOCK_STATUS
    export OCUTALON_GATE_USER=$gate_user OCUTALON_GATE_PASSWORD=$gate_password OCUTALON_CHECK_BLOCK_MARK=$mark
    for w in ${e[@]+"${e[@]}"}; do
      case $w in
        -u:*) unset "${w#-u:}" ;;
        *) export "$w" ;;
      esac
    done
    bash "$script" "${run_base:-$url}" ${1+"$@"} > "$tmp/out" 2> "$tmp/err" < "${run_stdin:-/dev/null}"
  )
  rc=$?
  run_seconds=$((run_seconds + SECONDS - t0))
  runs=$((runs + 1))
}
full=(--demo-status "$tmp/ds.json" --zone "$tmp/zone.txt")

# ids_of <PASS|FAIL|SKIP>: the ids of the lines of that kind, sorted, one line.
ids_of() { grep "^$1 " "$tmp/out" | cut -d' ' -f2 | LC_ALL=C sort | tr '\n' ' '; }
# norm <id>...: the ids sorted, one line.
norm() { printf '%s\n' "$@" | grep -v '^$' | LC_ALL=C sort | tr '\n' ' '; }

# diff_ids "<ids>" "<ids>": the ids of the first list that are not in the second (cut to 300 characters).
diff_ids() {
  local id out=""
  for id in $1; do
    case " $2 " in *" $id "*) ;; *) out="$out $id" ;; esac
  done
  printf '%s' "${out# }" | cut -c1-300
}

# expect_run <label> <exit code> "<FAIL ids>" "<SKIP ids>": the exit code, exactly those FAIL ids and exactly those SKIP ids.
expect_run() {
  local label=$1 want_rc=$2 got_fail got_skip want_fail want_skip stray
  got_fail=$(ids_of FAIL)
  got_skip=$(ids_of SKIP)
  want_fail=$(norm $3)
  want_skip=$(norm $4)
  stray=$(grep -vcE '^(PASS|FAIL|SKIP) [^ ]+ |^demo-host-check: ' "$tmp/out")
  if [ "$rc" = "$want_rc" ] && [ "$got_fail" = "$want_fail" ] && [ "$got_skip" = "$want_skip" ] && [ "$stray" = 0 ]; then
    pass "$label (exit $rc)"
  else
    fail "$label: exit $rc (wanted $want_rc), FAIL not wanted [$(diff_ids "$got_fail" "$want_fail")], FAIL wanted and missing [$(diff_ids "$want_fail" "$got_fail")], SKIP not wanted [$(diff_ids "$got_skip" "$want_skip")], SKIP wanted and missing [$(diff_ids "$want_skip" "$got_skip")], $stray stray line(s)"
  fi
}
# line_has <PASS|FAIL|SKIP> <id> <text>: the output holds that line, and the text is in it.
line_has() { grep "^$1 $2 " "$tmp/out" | grep -qF -- "$3"; }

# --- row 1: a correct host ---

set_flags
: > "$record"
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 1: a correct host (normal state, gate credentials, block mark, --demo-status, --zone) passes every check" 0 "" ""
if grep -q 'plain http' "$tmp/err"; then pass "row 1: gate credentials over plain http draw a warning on standard error"; else fail "row 1: no plain-http warning for gate credentials"; fi
pass_count=$(grep -c '^PASS ' "$tmp/out")
pw_count=$(grep -c '^PASS block-pw-' "$tmp/out")
probe_count=$(host_probes | wc -l | tr -d ' ')
if [ "$pw_count" = 56 ] && [ "$pass_count" -ge $((probe_count + 20)) ]; then
  pass "row 1: $pass_count checks pass, among them the 56 DW-214 probes (42 and 14 with a query string)"
else
  fail "row 1: $pass_count checks pass, $pw_count of them block-pw-* (wanted 56)"
fi
missing=""
for id in allow-splash allow-status allow-broker gate-closed status-json status-keys status-types status-nostore status-kind status-next guard-signin-3 guard-signin-4 \
  block-mark demo-status-json demo-status-keys demo-status-types demo-status-match demo-status-version demo-status-access zone; do
  grep -q "^PASS $id " "$tmp/out" || missing="$missing $id"
done
while IFS= read -r line; do
  id=${line%% *}
  grep -q "^PASS $id " "$tmp/out" || missing="$missing $id"
done < "$tmp/probes.full"
if [ -z "$missing" ]; then
  pass "row 1: the named checks and every probe of host_probes have a PASS line"
else
  fail "row 1: no PASS line for:$missing"
fi
methods=$(jq -r '.m // empty' "$record" | LC_ALL=C sort -u | tr '\n' ' ')
if [ "$methods" = "GET POST " ]; then pass "row 1: the stand-in saw GET and POST and no other method"; else fail "row 1: the stand-in saw the methods '$methods'"; fi
# signouts_ok <label>: every session the stand-in opened since the record was cleared was signed out with its own cookie on the
# application the stand-in opened it on (?IRISLogout=end there) and on /ocutalon/; prints the applications it saw.
signouts_ok() {
  local label=$1 id app outs n_app n_root unended="" n=0 apps
  while read -r id app; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    outs=$(jq -r --arg id "$id" 'select(.u? and .s == 200 and (.u | contains("IRISLogout=end")) and (.c | test("=" + $id + "(;|$)"))) | .u' "$record")
    n_app=$(printf '%s\n' "$outs" | grep -c "^${app}?IRISLogout=end")
    n_root=$(printf '%s\n' "$outs" | grep -c '^/ocutalon/?IRISLogout=end')
    if [ "$app" = /ocutalon/ ]; then
      [ "$n_root" -ge 2 ] || unended="$unended $id@$app"
    else
      [ "$n_app" -ge 1 ] && [ "$n_root" -ge 1 ] || unended="$unended $id@$app"
    fi
  done << EOF
$(jq -r 'select(.issued?) | .issued + " " + .app' "$record")
EOF
  apps=$(jq -r 'select(.issued?) | .app' "$record" | LC_ALL=C sort -u | tr '\n' ' ')
  if [ "$n" -gt 0 ] && [ -z "$unended" ]; then
    pass "$label: the stand-in saw the sign-out of each of the $n sessions it opened, on its own application and on /ocutalon/ (applications: ${apps% })"
  else
    fail "$label: $n sessions opened, not signed out on their application and on /ocutalon/:$unended"
  fi
}
signouts_ok "row 1"
if jq -r 'select(.issued?) | .app' "$record" | grep -qx /ocutalon/trace/ocutalon/; then
  pass "row 1: a trace application's session is among them (guard-signin-4)"
else
  fail "row 1: no trace application's session was opened, so the sign-out on a trace application is not checked"
fi
leaks=$(grep -cF -e "$gate_password" -e "$gate_user" "$tmp/out" "$tmp/err" | grep -v ':0$' | head -n 1)
if [ -z "$leaks" ]; then pass "row 1: the gate credentials are in neither standard output nor standard error"; else fail "row 1: the gate credentials were printed ($leaks)"; fi

# --- row 2: the allowed paths ---

set_flags fault_splash
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 2: the splash blocked fails allow-splash and nothing else" 1 "allow-splash" ""
set_flags fault_broker
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 2: the broker file blocked fails allow-broker and nothing else" 1 "allow-broker" ""
set_flags broker_html
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 2: a page answered in place of the broker file fails allow-broker and nothing else" 1 "allow-broker" ""

# --- row 3: the blocked paths ---

block_ids="block-csp-sys:/csp/sys/ block-csp-user:/csp/user/ block-api-mgmnt:/api/mgmnt/ block-api-monitor:/api/monitor/metrics block-api-atelier:/api/atelier/ block-ui:/ui/ block-mcp:/mcp/ block-mcp-ocutalon:/mcp/ocutalon block-hook:/ocutalon/hook block-dotdot:/ocutalon/../csp/sys/"
lets=""
want=""
for pair in $block_ids; do
  lets="$lets|${pair#*:}"
  want="$want ${pair%%:*}"
done
set_flags "let=${lets#|}"
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 3: each blocked path let through to IRIS fails its block-* check" 1 "$want" ""
named=1
for pair in $block_ids; do
  line_has FAIL "${pair%%:*}" "${pair#*:}" || named=0
done
if [ "$named" = 1 ]; then pass "row 3: each FAIL line names its path (the dot-dot path as sent)"; else fail "row 3: a FAIL line does not name its path"; fi

# --- row 4: DW-214, every spelling of the password-change page ---

pw_paths="trace-ocutalon:/ocutalon/trace/ocutalon/ trace-ocuorders:/ocutalon/trace/ocuorders/ root:/ocutalon/ api:/ocutalon/api/ public:/ocutalon/public/ broker:/csp/broker/"
pw_forms="canon:%25CSP.PasswordChange.cls lower:%25csp.passwordchange.cls upper:%25CSP.PASSWORDCHANGE.CLS mixed:%25CsP.PaSsWoRdChAnGe.cls c43:%25%43SP.PasswordChange.cls c43h:%25%43SP.Password%43hange.cls double:%2525CSP.PasswordChange.cls"
pw_all=""
pw_lets=""
for pp in $pw_paths; do
  for ff in $pw_forms; do
    pw_all="$pw_all block-pw-${pp%%:*}-${ff%%:*}:${pp#*:}${ff#*:}"
    case ${pp%%:*} in trace-*) pw_all="$pw_all block-pw-${pp%%:*}-${ff%%:*}-q:${pp#*:}${ff#*:}?x=1" ;; esac
  done
done
want=""
for pair in $pw_all; do
  pw_lets="$pw_lets|${pair#*:}"
  want="$want ${pair%%:*}"
done
set_flags "let=${pw_lets#|}"
: > "$record"
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 4: all 56 DW-214 probes let through fail their block-pw-* checks, and nothing else fails" 1 "$want" ""
signouts_ok "row 4: the let-through probes"
if [ "$(jq -r 'select(.issued?) | .app' "$record" | grep -c '^/ocutalon/trace/')" -ge 2 ] && jq -r 'select(.issued?) | .app' "$record" | grep -qx /ocutalon/trace/ocuorders/; then
  pass "row 4: sessions of both trace applications are among them"
else
  fail "row 4: the let-through probes opened no session of /ocutalon/trace/ocuorders/"
fi
named=1
for pair in $pw_all; do
  line_has FAIL "${pair%%:*}" "${pair#*:}" || named=0
done
if [ "$named" = 1 ]; then pass "row 4: each of the 56 FAIL lines names its path"; else fail "row 4: a FAIL line does not name its path"; fi
for pair in block-pw-root-lower:/ocutalon/%25csp.passwordchange.cls block-pw-trace-ocuorders-double-q:/ocutalon/trace/ocuorders/%2525CSP.PasswordChange.cls?x=1 \
  block-pw-broker-c43h:/csp/broker/%25%43SP.Password%43hange.cls; do
  set_flags "let=${pair#*:}"
  run_script -- ${full[@]+"${full[@]}"}
  expect_run "row 4: only ${pair%%:*} let through fails block-pw-* for it and no other check" 1 "${pair%%:*}" ""
done

# --- row 5: the guard, one fault per rule ---

guard_fault() { # <label> <flag> <FAIL ids>
  set_flags "$2"
  run_script -- ${full[@]+"${full[@]}"}
  expect_run "row 5: $1 fails $3 and nothing else" 1 "$3" ""
}
guard_fault "a guard that lets multipart through" g_multipart "guard-F8 guard-F9"
guard_fault "a guard that lets chunked bodies through" g_chunked "guard-F10"
guard_fault "a guard that does not URL-decode names" g_nodecode "guard-F6 guard-F7"
guard_fault "a case-sensitive pattern" g_case "guard-case"
guard_fault "a pattern without the legacy Cache names" g_legacy "guard-F2 guard-F4"
guard_fault "a guard that ignores the query string" g_query "guard-F3 guard-F3-state guard-F3-trace-ocutalon guard-F3-trace-ocuorders guard-F4 guard-F5 guard-F7 guard-query"
# (QA) The same fault with the Planner's block statuses (403 404) and no mark: a request that reaches IRIS is answered as IRIS answers it
# (F3's and F4's query, which curl adds, does not hide the probe from the stand-in's table), so IRIS's own 401 and 200 are no block.
set_flags g_query
run_script "OCUTALON_CHECK_BLOCK_STATUS=403 404" -u:OCUTALON_CHECK_BLOCK_MARK -- ${full[@]+"${full[@]}"}
expect_run "row 5 (QA): a guard that ignores the query string, with block statuses 403 404 and no mark, fails the same ids (IRIS's own answers are no block)" 1 \
  "guard-F3 guard-F3-state guard-F3-trace-ocutalon guard-F3-trace-ocuorders guard-F4 guard-F5 guard-F7 guard-query" ""
if grep -q '^FAIL guard-F3-state .* answered 401,' "$tmp/out"; then
  pass "row 5 (QA): the let-through guard-F3-state is answered with IRIS's own 401, as host_probes lists it"
else
  fail "row 5 (QA): guard-F3-state is not answered with IRIS's own 401: $(grep '^FAIL guard-F3-state ' "$tmp/out" | cut -c1-160)"
fi
guard_fault "a guard that accepts a sign-in body with an extra name" g_extra "guard-extra guard-api"
guard_fault "a guard with no size bound" g_size "guard-big"

# --- row 6: DW-226 ---

guard_fault "a guard that requires all four names (the splash's three-field sign-in refused)" g_exact4 "guard-signin-3"
guard_fault "sign-in POSTs answered with a plain page, not IRIS's sign-in page" signin_plain "guard-signin-3 guard-signin-4"

# (QA) guard-signin-4 claims what it observes: IRIS's sign-in page, which a plain GET gives too (Decided in-stage 16), so the proxy let the
# POST through. Its PASS line must not say that IRIS refused the request; guard-signin-3, which sees aria-invalid, may.
set_flags
run_script -- ${full[@]+"${full[@]}"}
if line_has PASS guard-signin-4 "does not show that IRIS refused" && ! line_has PASS guard-signin-4 "was refused by"; then
  pass "row 6 (QA): the PASS line of guard-signin-4 says it saw IRIS's sign-in page and does not claim a refusal by IRIS"
else
  fail "row 6 (QA): the PASS line of guard-signin-4 claims more than it observes: $(grep '^PASS guard-signin-4 ' "$tmp/out" | cut -c1-200)"
fi
if line_has PASS guard-signin-3 "refused by it"; then pass "row 6 (QA): guard-signin-3, which sees aria-invalid, reports IRIS's refusal"; else fail "row 6 (QA): guard-signin-3 does not report IRIS's refusal"; fi

# --- row 7: no false all-clear, in every family ---

set_flags "let=/api/mgmnt/|/csp/sys/|/ocutalon/api/%25CSP.PasswordChange.cls|/ocutalon/public/%25csp.passwordchange.cls" "letpost=/ocutalon/api/v1/messages"
run_script -u:OCUTALON_CHECK_BLOCK_MARK -- ${full[@]+"${full[@]}"}
expect_run "row 7 (a): with no mark, refusal probes let through and answered 401 or 404 (404 is no block status) fail in each family" 1 \
  "block-api-mgmnt block-csp-sys block-pw-api-canon block-pw-public-lower guard-api" ""

# (b): per family, the first probe whose IRIS answer is noform with a status other than 401 or 407; with the status added to the block
# statuses and no mark, it is ambiguous. No guard probe is one: IRIS answers each with a form or 401.
amb_ids=""
amb_lets=""
amb_letposts=""
amb_statuses="403"
guard_ambiguous=0
for family in pw block guard; do
  found=""
  while IFS= read -r line; do
    host_probe_args "$line"
    case $family in
      pw) case $probe_id in block-pw-*) ;; *) continue ;; esac ;;
      block) case $probe_id in block-pw-*) continue ;; block-*) ;; *) continue ;; esac ;;
      guard) case $probe_id in guard-*) ;; *) continue ;; esac ;;
    esac
    case $probe_iris in
      401:* | 407:*) continue ;;
      *:noform)
        found=$probe_id
        amb_ids="$amb_ids $probe_id"
        if [ "$probe_method" = POST ]; then amb_letposts="$amb_letposts|$probe_target"; else amb_lets="$amb_lets|$probe_target"; fi
        amb_statuses="$amb_statuses ${probe_iris%%:*}"
        break
        ;;
    esac
  done < "$tmp/probes.full"
  if [ "$family" = guard ] && [ -z "$found" ]; then guard_ambiguous=1; fi
done
amb_statuses=$(printf '%s\n' $amb_statuses | LC_ALL=C sort -u | tr '\n' ' ')
set_flags "let=${amb_lets#|}" "letpost=${amb_letposts#|}"
run_script "OCUTALON_CHECK_BLOCK_STATUS=$amb_statuses" -u:OCUTALON_CHECK_BLOCK_MARK -- ${full[@]+"${full[@]}"}
expect_run "row 7 (b): a block status that IRIS itself gives a probe that is let through, with no mark, is SKIP ambiguous (exit 3), never PASS" 3 "" "$amb_ids"
if [ "$guard_ambiguous" = 1 ]; then
  pass "row 7 (b): no guard probe can be ambiguous on build 154: IRIS answers each with an IRIS form or a 401, which is no block status"
else
  fail "row 7 (b): a guard probe is now ambiguous: the run above must put it in the guard family's case"
fi
set_flags refuse_form
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 7: a refusal with a block status and the mark whose body holds an IRIS form field fails in every family" 1 "$(cut -d' ' -f1 "$tmp/probes.full" | tr '\n' ' ')" ""
set_flags mark_allowed
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 7 (c): a mark that an allowed answer also carries fails block-mark and nothing else" 1 "block-mark" ""
for pair in splash:allow-splash broker:allow-broker signin3:guard-signin-3 signin4:guard-signin-4; do
  set_flags "mark_allowed=${pair%%:*}"
  run_script -- ${full[@]+"${full[@]}"}
  expect_run "row 7 (c): the mark on the allowed answer of ${pair#*:} fails block-mark and nothing else" 1 "block-mark" ""
  if line_has FAIL block-mark "${pair#*:}"; then pass "row 7 (c): the block-mark FAIL line names ${pair#*:}"; else fail "row 7 (c): the block-mark FAIL line does not name ${pair#*:}"; fi
done
set_flags mark_in_body
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 7: refusals that carry the block mark in the body (no header) pass every check" 0 "" ""

# --- row 8: a closed gate and no credentials ---

set_flags
run_script -u:OCUTALON_GATE_USER -u:OCUTALON_GATE_PASSWORD -- ${full[@]+"${full[@]}"}
if [ "$rc" = 2 ] && grep -q 'gate refused' "$tmp/err" && [ ! -s "$tmp/out" ]; then
  pass "row 8: every request answered 401 with no credentials: 'gate refused' on standard error, exit 2, no check line"
else
  fail "row 8: exit $rc, stderr '$(head -c 150 "$tmp/err")', $(wc -l < "$tmp/out" | tr -d ' ') output line(s)"
fi
run_script OCUTALON_GATE_PASSWORD=wrong-$(hexpw) -- ${full[@]+"${full[@]}"}
if [ "$rc" = 2 ] && grep -q 'gate refused' "$tmp/err" && [ ! -s "$tmp/out" ]; then
  pass "row 8: wrong credentials: 'gate refused', exit 2, no check line"
else
  fail "row 8: wrong credentials: exit $rc, stderr '$(head -c 150 "$tmp/err")'"
fi
run_base="http://127.0.0.1:$closed_port"
run_script -- ${full[@]+"${full[@]}"}
if [ "$rc" = 2 ] && grep -q 'unreachable' "$tmp/err" && [ ! -s "$tmp/out" ]; then
  pass "row 8: a host that does not answer: exit 2, no check line"
else
  fail "row 8: no answer: exit $rc, stderr '$(head -c 150 "$tmp/err")'"
fi
run_base=
# (QA) The first credentialed request of the busy state is the status read and of the maintenance state /ocutalon/: a 401 there ends the run.
for st in busy maintenance; do
  set_flags state=$st
  run_script OCUTALON_GATE_PASSWORD=wrong-$(hexpw) -- --state $st
  if [ "$rc" = 2 ] && grep -q 'gate refused' "$tmp/err" && [ ! -s "$tmp/out" ]; then
    pass "row 8 (QA): the $st state with wrong credentials: 'gate refused', exit 2, no check line"
  else
    fail "row 8 (QA): the $st state with wrong credentials: exit $rc, stderr '$(head -c 150 "$tmp/err")', $(wc -l < "$tmp/out" | tr -d ' ') output line(s)"
  fi
done

# --- row 9: the gate open while access is restricted ---

set_flags gate_open
run_script -- ${full[@]+"${full[@]}"}
expect_run "row 9: a request without the credentials admitted fails gate-closed and nothing else" 1 "gate-closed" ""
set_flags nogate
run_script -u:OCUTALON_GATE_USER -u:OCUTALON_GATE_PASSWORD -- --demo-status "$tmp/ds-public.json" --zone "$tmp/zone.txt"
expect_run "row 9: no credentials against a host with no gate: gate-closed is SKIP (exit 3), access public passes" 3 "" "gate-closed"

# --- row 10: the status JSON ---

set_flags status_extra status_nocache status_kind status_past
run_script -- --zone "$tmp/zone.txt"
expect_run "row 10: a key added, no no-store, a kind outside the two and a next reset in the past fail status-keys, -nostore, -kind and -next" 1 \
  "status-keys status-nostore status-kind status-next" "demo-status"
set_flags status_missing status_type
run_script -- --zone "$tmp/zone.txt"
expect_run "row 10: a key missing and a wrong type fail status-keys and status-types" 1 "status-keys status-types" "demo-status"

# --- row 11: --demo-status ---

set_flags
printf 'this is not json\n' > "$tmp/ds-bad.json"
run_script -- --demo-status "$tmp/ds-bad.json" --zone "$tmp/zone.txt"
expect_run "row 11: input that is not JSON fails demo-status-json" 1 "demo-status-json" ""
write_status_fixture "$tmp/ds-faults.json" '. + {extra: 1} | .pendingVersion = 5 | .lastReset = "2026-10-26T08:00:00Z" | .goldenVersion = "0.9.0" | .access = "public"'
run_script -- --demo-status "$tmp/ds-faults.json" --zone "$tmp/zone.txt"
expect_run "row 11: a key added, a wrong type, a reset time that differs, running not golden and access public fail their demo-status-* checks" 1 \
  "demo-status-keys demo-status-types demo-status-match demo-status-version demo-status-access" ""
write_status_fixture "$tmp/ds-kind.json" '.lastResetKind = "unscheduled"'
run_script -- --demo-status "$tmp/ds-kind.json" --zone "$tmp/zone.txt"
expect_run "row 11: a lastResetKind that differs fails demo-status-match and nothing else" 1 "demo-status-match" ""
write_status_fixture "$tmp/ds-next.json" '.nextReset = "2099-01-01T00:00:00Z"'
run_script -- --demo-status "$tmp/ds-next.json" --zone "$tmp/zone.txt"
expect_run "row 11: a nextReset that differs fails demo-status-match and nothing else" 1 "demo-status-match" ""
run_stdin="$tmp/ds.json"
run_script -- --demo-status - --zone "$tmp/zone.txt"
run_stdin=
expect_run "row 11: --demo-status - reads standard input and passes" 0 "" ""
run_script -- --zone "$tmp/zone.txt"
expect_run "row 11: no --demo-status input is SKIP demo-status (exit 3)" 3 "" "demo-status"

# --- row 12: --zone ---

set_flags
for z in US/Eastern EST5EDT; do
  printf '%s\n' "$z" > "$tmp/zone.$$.txt"
  run_script -- --demo-status "$tmp/ds.json" --zone "$tmp/zone.$$.txt"
  expect_run "row 12: the zone $z passes" 0 "" ""
done
printf 'UTC\n' > "$tmp/zone.$$.txt"
run_script -- --demo-status "$tmp/ds.json" --zone "$tmp/zone.$$.txt"
expect_run "row 12: the zone UTC fails zone" 1 "zone" ""
run_stdin="$tmp/zone.txt"
run_script -- --demo-status "$tmp/ds.json" --zone -
run_stdin=
expect_run "row 12: --zone - reads standard input and passes" 0 "" ""
run_script -- --demo-status "$tmp/ds.json"
expect_run "row 12: no --zone input is SKIP zone (exit 3)" 3 "" "zone"
run_script -- --demo-status "$tmp/ds.json" --zone <(printf 'America/New_York\n')
expect_run "row 12: --zone from a pipe (process substitution, not a regular file) passes" 0 "" ""

# --- usage errors: exit 2, nothing sent ---

: > "$record"
usage_case() { # <label> <env or -> <args...>
  local label=$1
  shift
  run_script "$1" -- "${@:2}"
  if [ "$rc" = 2 ] && [ ! -s "$tmp/out" ] && [ -s "$tmp/err" ]; then pass "usage: $label exits 2 with a message"; else fail "usage: $label: exit $rc, stderr '$(head -c 100 "$tmp/err")'"; fi
}
usage_case "an unknown state" X=1 --state bogus
usage_case "a block status of 401" OCUTALON_CHECK_BLOCK_STATUS="403 401"
usage_case "a block status of 407" OCUTALON_CHECK_BLOCK_STATUS=407
usage_case "a block status that is no status" OCUTALON_CHECK_BLOCK_STATUS="403 abc"
usage_case "two inputs on standard input" X=1 --demo-status - --zone -
usage_case "an option without a value" X=1 --zone
usage_case "a gate user without a password" -u:OCUTALON_GATE_PASSWORD
usage_case "an unreadable input" X=1 --zone "$tmp/no-such-file"
usage_case "a folder as input" X=1 --zone "$tmp"
usage_case "an unknown option" X=1 --bogus
usage_case "two base URLs" X=1 "$url"
run_base="http://zz-user@127.0.0.1:$stub_port"
usage_case "a base URL with a user name" X=1
run_base="$url/ocutalon/"
usage_case "a base URL with a path" X=1
run_base=
if ! grep -q . "$record"; then pass "usage: no request reached the stand-in"; else fail "usage: a usage error sent a request"; fi

# --- row 13: busy ---

set_flags state=busy
run_script -- --state busy
expect_run "row 13: the busy state: the busy page byte for byte, the API never the busy page, /status busy" 0 "" ""
for id in busy-status busy-root busy-deep busy-api; do
  grep -q "^PASS $id " "$tmp/out" || fail "row 13: no PASS line for $id"
done
set_flags state=busy busy_iris
run_script -- --state busy
expect_run "row 13: IRIS's busy splash with X-OcuTalon-Busy is accepted" 0 "" ""
set_flags state=busy busy_plain
run_script -- --state busy
expect_run "row 13: IRIS's ordinary splash without X-OcuTalon-Busy fails busy-root and busy-deep" 1 "busy-root busy-deep" ""
set_flags state=busy busy_api_drop
run_script -- --state busy
expect_run "row 13: no answer from the API path fails busy-api" 1 "busy-api" ""
set_flags state=busy busy_altered
run_script -- --state busy
expect_run "row 13: one altered byte of the busy page fails busy-root and busy-deep" 1 "busy-root busy-deep" ""
set_flags state=busy busy_api_page
run_script -- --state busy
expect_run "row 13: the busy page under /ocutalon/api/ fails busy-api" 1 "busy-api" ""
set_flags state=busy busy_off
run_script -- --state busy
expect_run "row 13: /status with busy false fails busy-status" 1 "busy-status" ""

# --- row 14: maintenance (DW-240) ---

set_flags state=maintenance
run_script -- --state maintenance
expect_run "row 14: the maintenance state: the page, and the four logos beside it and under /ocutalon/assets/brand/, byte for byte" 0 "" ""
logos=$(grep -c '^PASS maint-logo-' "$tmp/out")
if [ "$logos" = 4 ]; then pass "row 14: four logos are checked"; else fail "row 14: $logos logos are checked, wanted 4"; fi
set_flags state=maintenance maint_missing_logo=OcuTalon-Logo-dark-640.png
run_script -- --state maintenance
expect_run "row 14: a logo missing beside the page fails maint-logo-<name>" 1 "maint-logo-OcuTalon-Logo-dark-640.png" ""
set_flags state=maintenance maint_no_brand=OcuTalon-Logo-light-1280.png
run_script -- --state maintenance
expect_run "row 14: a logo missing under /ocutalon/assets/brand/ fails maint-logo-<name>" 1 "maint-logo-OcuTalon-Logo-light-1280.png" ""
set_flags state=maintenance maint_alter_bare=OcuTalon-Logo-light-640.png
run_script -- --state maintenance
expect_run "row 14 (QA): a logo with one byte added beside the page fails maint-logo-<name>" 1 "maint-logo-OcuTalon-Logo-light-640.png" ""
set_flags state=maintenance maint_alter_brand=OcuTalon-Logo-dark-1280.png
run_script -- --state maintenance
expect_run "row 14 (QA): a logo with one byte added under /ocutalon/assets/brand/ fails maint-logo-<name>" 1 "maint-logo-OcuTalon-Logo-dark-1280.png" ""
if line_has FAIL maint-logo-OcuTalon-Logo-dark-1280.png "under /ocutalon/assets/brand/" && ! line_has FAIL maint-logo-OcuTalon-Logo-dark-1280.png "beside the page"; then
  pass "row 14 (QA): the FAIL line names the location of the altered logo only"
else
  fail "row 14 (QA): the FAIL line does not name the altered logo's location: $(grep '^FAIL maint-logo' "$tmp/out" | cut -c1-200)"
fi
set_flags state=maintenance maint_altered
run_script -- --state maintenance
expect_run "row 14: an altered maintenance page fails maint-root and maint-deep" 1 "maint-root maint-deep" ""

# --- row 16: a host whose password-change filter answers 404 ---

set_flags pw_status=404
run_script "OCUTALON_CHECK_BLOCK_STATUS=403 404" -- ${full[@]+"${full[@]}"}
expect_run "row 16: refusals of 404 for the block-pw-* family and 403 for the rest pass with the mark and the Planner's block statuses" 0 "" ""
want=""
while IFS= read -r line; do
  host_probe_args "$line"
  case $probe_id in
    block-pw-*) [ "$probe_iris" = "404:noform" ] && want="$want $probe_id" ;;
    *) [ "$probe_iris" = "403:noform" ] && want="$want $probe_id" ;;
  esac
done < "$tmp/probes.full"
run_script "OCUTALON_CHECK_BLOCK_STATUS=403 404" -u:OCUTALON_CHECK_BLOCK_MARK -- ${full[@]+"${full[@]}"}
if [ -n "$want" ]; then rc16=3; else rc16=0; fi
expect_run "row 16: without the mark no probe fails, and each one that IRIS answers alone with the same status is SKIP ambiguous" "$rc16" "" "$want"
run_script "OCUTALON_CHECK_BLOCK_STATUS=$(printf '403\n404')" -- ${full[@]+"${full[@]}"}
expect_run "row 16: block statuses separated by a line break are read as the same list" 0 "" ""
run_script -- ${full[@]+"${full[@]}"}
if [ "$rc" = 1 ] && [ "$(ids_of FAIL | wc -w | tr -d ' ')" -ge 56 ]; then
  pass "row 16: with the default block status 403 the 404 refusals are no block (the pw family fails)"
else
  fail "row 16: with the default block status 403: exit $rc, $(ids_of FAIL | wc -w | tr -d ' ') FAIL line(s)"
fi
set_flags

# --- credentials: on no command line, in no child's environment, and the curl configuration readable by the owner alone ---

# A curl in front of the real one (curl_shim of docker/tests/lib-stub.sh) logs each call's arguments, the number of OCUTALON_GATE_*
# variables in its environment, and the mode of the -K file it is given.
curl_shim "$tmp/shim"
: > "$tmp/shim.log"
set_flags
run_script "PATH=$tmp/shim:$PATH" "SHIM_LOG=$tmp/shim.log" "SHIM_REAL=$(command -v curl)" -- ${full[@]+"${full[@]}"}
expect_run "credentials: a run through a curl that logs its arguments and environment passes every check" 0 "" ""
shim_min=100
shim_checks "$tmp/shim.log" "credentials" "$gate_password" "$gate_user"

# host_probe_args refuses a line whose method is not the one its form is sent with.
if host_probe_args "zz-method 200:form POST /ocutalon/ F3"; then fail "host_probe_args: a POST line for the GET form F3 was accepted"; else pass "host_probe_args: a POST line for the GET form F3 is refused"; fi
for line in "zz-method 200:form POST /ocutalon/ query" "zz-method 200:form GET /ocutalon/ extra" "zz-method 200:form GET /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls F12" "zz-method 404:noform POST /csp/sys/"; do
  if host_probe_args "$line"; then fail "host_probe_args: the line '$line' with the wrong method was accepted"; else pass "host_probe_args: the line '$line' with the wrong method is refused"; fi
done

# --- row 15: the files are safe to publish ---

scan() { # <file> <label>: no host detail in the file
  local f=$1 label=$2 hits text
  text=$(sed 's#https://demo\.example#URL#g' "$f")
  hits=$(printf '%s\n' "$text" | grep -nE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|localhost|[A-Za-z][A-Za-z0-9.-]*:[0-9]{2,5}([^0-9]|$)|https?://[A-Za-z0-9]' | cut -d: -f1 | tr '\n' ' ')
  if [ -z "$hits" ]; then pass "row 15: $label holds no IP address, localhost, host:port or URL with a literal host"; else fail "row 15: $label holds a host detail on line(s) $hits"; fi
}
load_script="$root/release/demo-load.sh"
lib="$root/docker/tests/lib-online.sh"
if [ -f "$script" ] && [ -f "$load_script" ] && [ -f "$checklist" ]; then
  scan "$checklist" "release/demo-host-checks.md"
  for f in "$checklist" "$0"; do
    if LC_ALL=C grep -q '[^[:print:][:space:]]' "$f"; then fail "row 15: $(basename "$f") is not ASCII"; else pass "row 15: $(basename "$f") is ASCII"; fi
  done
  for rel in release/demo-host-check.sh release/demo-load.sh; do
    f="$root/$rel"
    scan "$f" "$rel"
    if LC_ALL=C grep -q '[^[:print:][:space:]]' "$f"; then fail "row 15: $rel is not ASCII"; else pass "row 15: $rel is ASCII"; fi
    code_lines=$(grep -vE '^[[:space:]]*#' "$f")
    run_hits=$(printf '%s\n' "$code_lines" | grep -nE 'ocutalon-demo|(^|[^A-Za-z-])(ssh|scp|nslookup)([^A-Za-z-]|$)' | cut -d: -f1 | tr '\n' ' ')
    if [ -z "$run_hits" ]; then pass "row 15: $rel runs no ocutalon-demo, SSH or DNS command"; else fail "row 15: $rel runs a host command on line(s) $run_hits"; fi
    method_hits=$(printf '%s\n' "$code_lines" | grep -nE '(^|[^A-Za-z])(PUT|DELETE|PATCH)([^A-Za-z]|$)|(-X|--request)[ =]' | cut -d: -f1 | tr '\n' ' ')
    if [ -z "$method_hits" ]; then pass "row 15: $rel uses no PUT, DELETE or PATCH"; else fail "row 15: $rel names another method on line(s) $method_hits"; fi
    cred_hits=$(printf '%s\n' "$code_lines" | grep -nE -e '--user|(^|[[:space:]])-u[[:space:]]|--basic|Authorization' | cut -d: -f1 | tr '\n' ' ')
    if [ -z "$cred_hits" ]; then pass "row 15: $rel has no credential on a command line (the gate reads a configuration file)"; else fail "row 15: $rel has a credential option on line(s) $cred_hits"; fi
    if grep -q '^umask 077' "$f"; then pass "row 15: $rel sets umask 077"; else fail "row 15: $rel does not set umask 077"; fi
    if [ -x "$f" ]; then pass "row 15: $rel is executable"; else fail "row 15: $rel is not executable"; fi
    mode=$(cd "$root" && git ls-files -s "$rel" 2> /dev/null | cut -d' ' -f1)
    if [ -z "$mode" ] || [ "$mode" = 100755 ]; then pass "row 15: $rel is tracked with mode 100755 (or not tracked yet: '${mode:-untracked}')"; else fail "row 15: $rel is tracked with mode $mode"; fi
  done
  if grep -q 'chmod 600' "$lib"; then pass "row 15: the gate configuration is written with chmod 600 (gate_config of lib-online.sh)"; else fail "row 15: the gate configuration is not protected"; fi
else
  fail "row 15: a release script or the check list does not exist"
fi

# --- AC 9: the check list's rows H1 to H25 ---

status_pending="pending"
status_measured="measured 2026-10-30 (Epic 16 deploy); re-check at the release deploy"
status_part="measured in part 2026-10-30 (Epic 16 deploy); rest pending"
bad=""
for n in $(seq 1 25); do
  rows=$(grep -E "^\| H$n \|" "$checklist" 2> /dev/null)
  count=$(printf '%s\n' "$rows" | grep -c .)
  status=$(printf '%s\n' "$rows" | awk -F'|' '{ gsub(/^ +| +$/, "", $(NF-1)); print $(NF-1) }')
  if [ "$count" != 1 ] || { [ "$status" != "$status_pending" ] && [ "$status" != "$status_measured" ] && [ "$status" != "$status_part" ]; }; then
    bad="$bad H$n"
  fi
done
if [ -z "$bad" ]; then
  pass "check list: H1 to H25 are each present once with one of the three statuses (none is a pass)"
else
  fail "check list: no single row with one of the three statuses for:$bad"
fi
if grep -qiE '^\| H[0-9]+ \|.*\|[[:space:]]*(pass|passed|ok)[[:space:]]*\|[[:space:]]*$' "$checklist" 2> /dev/null; then fail "check list: a row is marked as a pass"; else pass "check list: no row is marked as a pass"; fi

echo "MEASURED test-online-host: $runs script runs took $run_seconds s; the test took $((SECONDS - started)) s"
if [ "$fails" -eq 0 ]; then
  echo "test-online-host: all checks passed"
  exit 0
fi
echo "test-online-host: $fails check(s) failed"
exit 1
