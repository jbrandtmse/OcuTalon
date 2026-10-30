#!/usr/bin/env bash
# Read-only check of the online demo host against AD-25 (Story 29.3): the Contest Planner runs it against the host, from any machine.
#   bash release/demo-host-check.sh <base-url> [--state normal|busy|maintenance] [--demo-status FILE|-] [--zone FILE|-]
# <base-url> is the host's origin, for example https://demo.example. The default state is normal. At most one input may be "-" (standard
# input). The settings the Planner uses, and what each run covers, are in release/demo-host-checks.md.
#
# What it checks (the id of a check is stable; a line is PASS, FAIL or SKIP, then the id, then a text):
#   normal       allow-*      the splash, /ocutalon/public/status and one static /csp/broker/ file are served;
#                gate-closed  a request without the gate credentials is refused (401 or 407);
#                status-*     the status JSON: its five keys and types, no-store, the reset kind, a next reset in the future;
#                block-*      the paths the proxy blocks, and block-pw-*, the password-change page in every spelling the Planner
#                             measured (DW-214);
#                guard-*      the password guard: the eleven S17 forms, the oversize and extra-name sign-in bodies, a password name in a
#                             query string or in a body for the JSON API, and guard-signin-3 and guard-signin-4, the splash's and the
#                             trace sign-in page's own sign-in POSTs, which must reach IRIS and come back refused by IRIS (DW-226);
#                block-mark   the block mark is carried by no allowed answer;
#                demo-status-* the output of the host's `ocutalon-demo status` command, piped in with --demo-status, against AD-25
#                             and the status JSON;
#                zone         the IRIS container's TZ, piped in with --zone, is US Eastern;
#   busy         the status read and busy-*: the busy page in place of IRIS's busy answer, except under /ocutalon/api/;
#   maintenance  maint-*: the maintenance page and the four logos, beside the page and under /ocutalon/assets/brand/.
# A block check (block-*, block-pw-*, guard-F*, guard-extra, guard-big, guard-query, guard-api) passes only when the status is one of the
# block statuses, the body holds no IRIS form field, and the block mark is present when one is set. When IRIS alone would give the same
# answer to that request (docker/tests/lib-online.sh, host_probes), and no mark is set, the check cannot tell the host from IRIS: it is
# SKIP ... ambiguous. A 401 or 407 never counts as a block. With a mark set, an allowed answer that carries it fails block-mark.
#
# Inputs (environment variables, all optional):
#   OCUTALON_GATE_USER, OCUTALON_GATE_PASSWORD   basic authentication for the access gate. They reach curl only through a temporary
#                                                configuration file readable by the owner alone, never through the command line, and are
#                                                never printed.
#   OCUTALON_CHECK_BLOCK_STATUS                  the statuses that the proxy and the guard refuse with, separated by spaces (default
#                                                403; 401 and 407 are usage errors).
#   OCUTALON_CHECK_BLOCK_MARK                    a text that only the proxy's refusals carry, in a header or the body.
#
# It sends only GET and POST requests with dummy values (user zz-host-check, passwords dummy-old and dummy-new, token dummy-token):
# public reads, and requests that the host must refuse. Neither published account's name or password is ever used, nothing is retried,
# and each request has a 30 s limit. A request that opens an IRIS session is followed by a sign-out of that session. The dummy sign-ins
# leave failed-sign-in entries in the host's audit log.
# `ocutalon-demo status` and the TZ of the IRIS container are the Planner's to read on the host; this script runs neither and takes
# their output from a file or standard input.
#
# Exit codes: 0 every check ran and passed; 1 a check failed; 2 a usage error, a missing tool (bash 3.2 or later, curl, jq), or the
# host or the gate refusing the first credentialed request (nothing else runs); 3 nothing failed, but a check was skipped.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
lib="$root/docker/tests/lib-online.sh"

die2() {
  printf 'demo-host-check: %s\n' "$1" >&2
  exit 2
}

usage() {
  printf 'demo-host-check: %s\n' "$1" >&2
  printf 'usage: bash release/demo-host-check.sh <base-url> [--state normal|busy|maintenance] [--demo-status FILE|-] [--zone FILE|-]\n' >&2
  exit 2
}

# --- the tools ---

if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  die2 "bash 3.2 or later is required"
fi
for tool in curl jq cmp grep sed tr head mktemp; do
  command -v "$tool" > /dev/null 2>&1 || die2 "$tool is not installed"
done
[ -f "$lib" ] || die2 "docker/tests/lib-online.sh is missing"
. "$lib"

# --- the arguments and the environment ---

base=""
state=normal
demo_status_src=""
zone_src=""
while [ $# -gt 0 ]; do
  case $1 in
    --state)
      [ $# -ge 2 ] || usage "--state needs a value"
      state=$2
      shift 2
      ;;
    --demo-status)
      [ $# -ge 2 ] || usage "--demo-status needs a file or -"
      demo_status_src=$2
      shift 2
      ;;
    --zone)
      [ $# -ge 2 ] || usage "--zone needs a file or -"
      zone_src=$2
      shift 2
      ;;
    -*) usage "unknown option $1" ;;
    *)
      [ -z "$base" ] || usage "more than one base URL"
      base=$1
      shift
      ;;
  esac
done
[ -n "$base" ] || usage "the base URL is missing"
case $state in normal | busy | maintenance) ;; *) usage "--state is normal, busy or maintenance" ;; esac
case $base in */) base=${base%/} ;; esac
if ! printf '%s\n' "$base" | grep -Eq '^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$'; then
  usage "the base URL is an origin: a scheme, a host and an optional port, no path and no user name"
fi
if [ "$demo_status_src" = - ] && [ "$zone_src" = - ]; then usage "at most one input may be - (standard input)"; fi

gate_user=${OCUTALON_GATE_USER:-}
gate_password=${OCUTALON_GATE_PASSWORD:-}
if [ -n "$gate_user" ] || [ -n "$gate_password" ]; then
  if [ -z "$gate_user" ] || [ -z "$gate_password" ]; then usage "OCUTALON_GATE_USER and OCUTALON_GATE_PASSWORD are set together or not at all"; fi
  case $gate_user in *:*) usage "OCUTALON_GATE_USER holds a colon" ;; esac
  case $gate_user$gate_password in *$'\n'* | *$'\r'*) usage "the gate credentials hold a line break" ;; esac
  case $base in http://*) printf 'demo-host-check: warning: the gate credentials go over plain http\n' >&2 ;; esac
fi
block_status=${OCUTALON_CHECK_BLOCK_STATUS:-403}
block_status=$(printf '%s' "$block_status" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')
[ -n "$block_status" ] || usage "OCUTALON_CHECK_BLOCK_STATUS is empty"
for s in $block_status; do
  case $s in
    401 | 407) usage "OCUTALON_CHECK_BLOCK_STATUS holds $s: an authentication challenge is never a block" ;;
    [1-5][0-9][0-9]) ;;
    *) usage "OCUTALON_CHECK_BLOCK_STATUS holds '$s', which is no HTTP status" ;;
  esac
done
mark=${OCUTALON_CHECK_BLOCK_MARK:-}
case $mark in *$'\n'* | *$'\r'*) usage "OCUTALON_CHECK_BLOCK_MARK holds a line break" ;; esac

umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-host-check.XXXXXX") || die2 "no temporary folder"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# The inputs are read before any request, so that a bad one is a usage error with nothing sent.
read_input() { # <source> <destination file>
  if [ "$1" = - ]; then
    cat > "$2"
  else
    [ -f "$1" ] && [ -r "$1" ] || die2 "cannot read $1"
    cat "$1" > "$2"
  fi
}
if [ -n "$demo_status_src" ]; then read_input "$demo_status_src" "$work/demo-status.json"; fi
if [ -n "$zone_src" ]; then read_input "$zone_src" "$work/zone.txt"; fi

# The repository's own pages and logos, for busy and maintenance.
busy_page="$root/docker/busy.html"
maintenance_page="$root/docker/maintenance.html"
logo_dir="$root/logo/web"
logo_names="OcuTalon-Logo-light-640.png OcuTalon-Logo-light-1280.png OcuTalon-Logo-dark-640.png OcuTalon-Logo-dark-1280.png"
case $state in
  busy) [ -f "$busy_page" ] || die2 "docker/busy.html is missing" ;;
  maintenance)
    [ -f "$maintenance_page" ] || die2 "docker/maintenance.html is missing"
    for name in $logo_names; do [ -f "$logo_dir/$name" ] || die2 "logo/web/$name is missing"; done
    ;;
esac

# The gate credentials: a curl configuration file (mode 600) read with -K, so that they are in no command line.
gate_args=()
if [ -n "$gate_user" ]; then
  esc_user=$(printf '%s' "$gate_user" | sed 's/\\/\\\\/g; s/"/\\"/g')
  esc_password=$(printf '%s' "$gate_password" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf 'user = "%s:%s"\n' "$esc_user" "$esc_password" > "$work/gate.cfg"
  chmod 600 "$work/gate.cfg"
  gate_args=(-K "$work/gate.cfg")
fi
unset gate_user gate_password esc_user esc_password OCUTALON_GATE_USER OCUTALON_GATE_PASSWORD

# --- reports ---

n_pass=0
n_fail=0
n_skip=0
report() { # <PASS|FAIL|SKIP> <id> <text>
  case $1 in
    PASS) n_pass=$((n_pass + 1)) ;;
    FAIL) n_fail=$((n_fail + 1)) ;;
    SKIP) n_skip=$((n_skip + 1)) ;;
  esac
  printf '%s %s %s\n' "$1" "$2" "$3"
}
pass() { report PASS "$1" "$2"; }
fail() { report FAIL "$1" "$2"; }
skip() { report SKIP "$1" "$2"; }

# --- requests ---

req_n=0
t_n=0
use_gate=1
code=000
hfile=""
bfile=""

jar_has_cookie() { grep -Eq '^(#HttpOnly_|[^#[:space:]])' "$1" 2> /dev/null; }

# sign_out <jar> <target>: ends the session that an answer opened, on the application of the target and on /ocutalon/ with the same jar.
sign_out() {
  local app=/ocutalon/ i
  case $2 in
    /ocutalon/trace/ocutalon/*) app=/ocutalon/trace/ocutalon/ ;;
    /ocutalon/trace/ocuorders/*) app=/ocutalon/trace/ocuorders/ ;;
    /ocutalon/api/*) app=/ocutalon/api/ ;;
  esac
  for i in "$app" /ocutalon/; do
    t_n=$((t_n + 1))
    curl -s --max-time 30 -o /dev/null ${gate_args[@]+"${gate_args[@]}"} -b "$1" -c "$1" "$base$i?IRISLogout=end&t=$t_n" < /dev/null > /dev/null 2>&1
  done
}

# send <target> [<curl argument>...]: one request on a jar of its own, the path sent as is. Leaves the status in code (000 when there
# was no answer), the headers in hfile and the body in bfile. An answer that sets a cookie is followed by a sign-out.
send() {
  local target=$1 jar
  shift
  req_n=$((req_n + 1))
  jar="$work/jar.$req_n"
  hfile="$work/h.$req_n"
  bfile="$work/b.$req_n"
  : > "$jar"
  : > "$hfile"
  : > "$bfile"
  if [ "$use_gate" = 1 ]; then
    code=$(curl -s --max-time 30 --path-as-is ${gate_args[@]+"${gate_args[@]}"} -b "$jar" -c "$jar" -D "$hfile" -o "$bfile" -w '%{http_code}' ${1+"$@"} "$base$target" < /dev/null 2> /dev/null) || code=000
  else
    code=$(curl -s --max-time 30 --path-as-is -b "$jar" -c "$jar" -D "$hfile" -o "$bfile" -w '%{http_code}' ${1+"$@"} "$base$target" < /dev/null 2> /dev/null) || code=000
  fi
  if [ -z "$code" ]; then code=000; fi
  if jar_has_cookie "$jar"; then sign_out "$jar" "$target"; fi
}

# get_t <path>: a public read with a unique t parameter.
get_t() {
  t_n=$((t_n + 1))
  case $1 in
    *\?*) send "$1&t=$t_n" ;;
    *) send "$1?t=$t_n" ;;
  esac
}

header_has() { tr -d '\r' < "$hfile" | grep -iq -- "$1"; }
body_has() { grep -Eq -- "$1" "$bfile"; }
has_form_field() { grep -Eq "$HOST_FORM_FIELD_RE" "$bfile"; }
has_mark() { [ -n "$mark" ] && grep -qF -- "$mark" "$hfile" "$bfile"; }

# Allowed answers (the ones that passed their check) that carry the block mark.
marked_allowed=""
note_allowed() { # <id>: records the id when the last answer carries the block mark
  if has_mark; then marked_allowed="$marked_allowed $1"; fi
}

# The first credentialed request: a 401 or 407 or no answer ends the run (exit 2).
first_answer() {
  case $code in
    401 | 407) die2 "gate refused: the host answered $code to the first credentialed request (check OCUTALON_GATE_USER and OCUTALON_GATE_PASSWORD)" ;;
    000) die2 "host unreachable: no answer to the first request" ;;
  esac
}

in_block_status() { case " $block_status " in *" $1 "*) return 0 ;; esac; return 1; }

# check_block <id> <iris answer> <what>: the verdict of a refusal probe on the last answer.
check_block() {
  local id=$1 iris=$2 what=$3 why=""
  if ! in_block_status "$code"; then
    why="answered $code, which is not a block status ($block_status)"
  elif has_form_field; then
    why="answered $code, but the body holds an IRIS form field"
  elif [ -n "$mark" ] && ! has_mark; then
    why="answered $code, but without the block mark"
  fi
  if [ -n "$why" ]; then
    fail "$id" "$what $why"
  elif [ -z "$mark" ] && [ "$iris" = "$code:noform" ]; then
    skip "$id" "ambiguous: $what answered $code, and IRIS alone gives that answer; set OCUTALON_CHECK_BLOCK_MARK"
  else
    pass "$id" "$what blocked with $code"
  fi
}

# --- the status JSON ---

iso_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$'
status_file="$work/status.json"

check_status() {
  local f=$status_file
  if [ "$code" = 200 ]; then
    pass allow-status "/ocutalon/public/status answered 200"
    note_allowed allow-status
  else
    fail allow-status "/ocutalon/public/status answered $code"
  fi
  cp "$bfile" "$f"
  if ! jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
    fail status-json "the status is not a JSON object"
    return
  fi
  pass status-json "the status is a JSON object"
  if jq -e '(keys | sort) == ["busy", "lastReset", "lastResetKind", "nextReset", "ready"]' "$f" > /dev/null 2>&1; then
    pass status-keys "the status has exactly ready, nextReset, busy, lastReset and lastResetKind"
  else
    fail status-keys "the status keys are $(jq -c 'keys' "$f" 2> /dev/null)"
  fi
  if jq -e '(.ready | type) == "boolean" and (.busy | type) == "boolean" and ([.nextReset, .lastReset, .lastResetKind] | all(type == "string" or type == "null"))' "$f" > /dev/null 2>&1; then
    pass status-types "ready and busy are booleans; the other keys are strings or null"
  else
    fail status-types "a status value has the wrong type"
  fi
  if header_has '^cache-control:.*no-store'; then pass status-nostore "the status is Cache-Control no-store"; else fail status-nostore "the status has no Cache-Control no-store"; fi
  if jq -e '.lastResetKind == "scheduled" or .lastResetKind == "unscheduled"' "$f" > /dev/null 2>&1; then
    pass status-kind "lastResetKind is scheduled or unscheduled"
  else
    fail status-kind "lastResetKind is $(jq -c '.lastResetKind' "$f" 2> /dev/null), not scheduled or unscheduled"
  fi
  if jq -e --arg re "$iso_re" '(.nextReset | type) == "string" and (.nextReset | test($re)) and ((.nextReset | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) > now)' "$f" > /dev/null 2>&1; then
    pass status-next "nextReset is a UTC time in the future"
  else
    fail status-next "nextReset is $(jq -c '.nextReset' "$f" 2> /dev/null), not a UTC time in the future"
  fi
}

# --- the normal state ---

run_normal() {
  local line

  # The status read, and the gate.
  get_t /ocutalon/public/status
  first_answer
  check_status
  if [ ${#gate_args[@]} -gt 0 ]; then
    use_gate=0
    get_t /ocutalon/public/status
    use_gate=1
    if [ "$code" = 401 ] || [ "$code" = 407 ]; then
      pass gate-closed "a request without the gate credentials answered $code"
    else
      fail gate-closed "a request without the gate credentials answered $code, not 401 or 407: the gate is open"
    fi
  else
    skip gate-closed "no gate credentials given, so the closed gate is not checked"
  fi

  # The allowed reads.
  get_t /ocutalon/
  if [ "$code" = 200 ] && body_has '<title>Try OcuTalon</title>' && has_form_field; then
    pass allow-splash "/ocutalon/ answered 200 with the splash"
    note_allowed allow-splash
  else
    fail allow-splash "/ocutalon/ answered $code, not the splash (its title and an IRIS password field)"
  fi
  get_t "$(host_broker_file)"
  if [ "$code" = 200 ] && ! header_has '^content-type:.*text/html'; then
    pass allow-broker "$(host_broker_file) answered 200"
    note_allowed allow-broker
  else
    fail allow-broker "$(host_broker_file) answered $code$(header_has '^content-type:.*text/html' && printf ' with a page (text/html)')"
  fi

  # The refusal probes: the blocked paths, the password-change page, the guard's refusals.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! host_probe_args "$line"; then
      fail "${line%% *}" "the probe cannot be built"
      continue
    fi
    send "$probe_target" ${probe_args[@]+"${probe_args[@]}"}
    check_block "$probe_id" "$probe_iris" "$probe_method $probe_target"
  done << PROBES
$(host_probes)
PROBES

  # The sign-in POSTs that must reach IRIS and come back refused by IRIS (DW-226).
  host_signin 3
  send "$signin_target" "${signin_args[@]}"
  if [ "$code" = 200 ] && body_has 'aria-invalid="true"'; then
    pass guard-signin-3 "the splash's three-field sign-in reached IRIS and was refused by it"
    note_allowed guard-signin-3
  else
    fail guard-signin-3 "the splash's three-field sign-in answered $code, not IRIS's refusal (200 with aria-invalid)"
  fi
  host_signin 4
  send "$signin_target" "${signin_args[@]}"
  if [ "$code" = 200 ] && has_form_field && grep -qF -- "$(host_trace_refused_marker)" "$bfile"; then
    pass guard-signin-4 "the trace sign-in page's four-field sign-in reached IRIS and was refused by it"
    note_allowed guard-signin-4
  else
    fail guard-signin-4 "the trace sign-in page's four-field sign-in answered $code, not IRIS's sign-in page (200 with its Login form)"
  fi

  if [ -n "$mark" ]; then
    if [ -z "$marked_allowed" ]; then
      pass block-mark "no allowed answer carries the block mark"
    else
      fail block-mark "the block mark is carried by allowed answers:$marked_allowed"
    fi
  fi

  check_demo_status
  check_zone
}

check_demo_status() {
  local f="$work/demo-status.json" want
  if [ -z "$demo_status_src" ]; then
    skip demo-status "no --demo-status input given"
    return
  fi
  if ! jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
    fail demo-status-json "the input is not a JSON object"
    return
  fi
  pass demo-status-json "the input is a JSON object"
  if jq -e '(keys | sort) == ["access", "goldenVersion", "lastReset", "lastResetKind", "nextReset", "pendingVersion", "runningVersion"]' "$f" > /dev/null 2>&1; then
    pass demo-status-keys "the keys are exactly the seven of AD-25"
  else
    fail demo-status-keys "the keys are $(jq -c 'keys' "$f" 2> /dev/null)"
  fi
  if jq -e --arg re "$iso_re" '(.runningVersion | type) == "string" and (.goldenVersion | type) == "string" and (.lastReset | type) == "string" and (.lastReset | test($re))
    and (.nextReset | type) == "string" and (.nextReset | test($re)) and (.lastResetKind == "scheduled" or .lastResetKind == "unscheduled")
    and ((.pendingVersion | type) == "string" or .pendingVersion == null) and (.access == "restricted" or .access == "public")' "$f" > /dev/null 2>&1; then
    pass demo-status-types "the values have the types and values of AD-25"
  else
    fail demo-status-types "a value has the wrong type or an unexpected value"
  fi
  if [ "$(jq -c '[.lastReset, .lastResetKind, .nextReset]' "$f" 2> /dev/null)" = "$(jq -c '[.lastReset, .lastResetKind, .nextReset]' "$status_file" 2> /dev/null)" ]; then
    pass demo-status-match "lastReset, lastResetKind and nextReset equal the status JSON's"
  else
    fail demo-status-match "lastReset, lastResetKind or nextReset differs from the status JSON's"
  fi
  if jq -e '.runningVersion == .goldenVersion' "$f" > /dev/null 2>&1; then
    pass demo-status-version "runningVersion equals goldenVersion"
  else
    fail demo-status-version "runningVersion differs from goldenVersion"
  fi
  if [ ${#gate_args[@]} -gt 0 ]; then want=restricted; else want=public; fi
  if [ "$(jq -r '.access' "$f" 2> /dev/null)" = "$want" ]; then
    pass demo-status-access "access is $want"
  else
    fail demo-status-access "access is $(jq -c '.access' "$f" 2> /dev/null), wanted $want"
  fi
}

check_zone() {
  local zone
  if [ -z "$zone_src" ]; then
    skip zone "no --zone input given"
    return
  fi
  zone=$(tr -d ' \t\r\n' < "$work/zone.txt")
  case $zone in
    America/New_York | US/Eastern | EST5EDT) pass zone "the time zone is $zone" ;;
    *) fail zone "the time zone is '$zone', not US Eastern" ;;
  esac
}

# --- the busy state ---

busy_answer_ok() { # the last answer is docker/busy.html byte for byte, or IRIS's busy splash
  cmp -s "$bfile" "$busy_page" && return 0
  header_has '^x-ocutalon-busy:[[:space:]]*1' && body_has '<title>Try OcuTalon</title>'
}

run_busy() {
  local path id
  get_t /ocutalon/public/status
  first_answer
  if [ "$code" = 200 ] && jq -e '.busy == true' "$bfile" > /dev/null 2>&1; then
    pass busy-status "/ocutalon/public/status answered busy true"
  else
    fail busy-status "/ocutalon/public/status answered $code with busy $(jq -c '.busy' "$bfile" 2> /dev/null)"
  fi
  for path in /ocutalon/ /ocutalon/zz/deep; do
    if [ "$path" = /ocutalon/ ]; then id=busy-root; else id=busy-deep; fi
    get_t "$path"
    if busy_answer_ok; then
      pass "$id" "$path answered the busy page"
    else
      fail "$id" "$path answered $code, which is not the busy page (docker/busy.html, or IRIS's busy splash with X-OcuTalon-Busy)"
    fi
  done
  get_t /ocutalon/api/v1/state
  if [ "$code" = 000 ]; then
    fail busy-api "/ocutalon/api/v1/state gave no answer"
  elif cmp -s "$bfile" "$busy_page" || body_has '<title>Try OcuTalon</title>'; then
    fail busy-api "/ocutalon/api/v1/state answered the busy page ($code); the API's answer must reach the page"
  else
    pass busy-api "/ocutalon/api/v1/state did not answer the busy page ($code)"
  fi
}

# --- the maintenance state ---

run_maintenance() {
  local name bad
  get_t /ocutalon/
  first_answer
  if cmp -s "$bfile" "$maintenance_page"; then
    pass maint-root "/ocutalon/ answered the maintenance page"
  else
    fail maint-root "/ocutalon/ answered $code, which is not docker/maintenance.html"
  fi
  get_t /ocutalon/zz/deep
  if cmp -s "$bfile" "$maintenance_page"; then
    pass maint-deep "/ocutalon/zz/deep answered the maintenance page"
  else
    fail maint-deep "/ocutalon/zz/deep answered $code, which is not docker/maintenance.html"
  fi
  for name in $logo_names; do
    bad=""
    get_t "/ocutalon/$name"
    cmp -s "$bfile" "$logo_dir/$name" || bad="$bad beside the page ($code)"
    get_t "/ocutalon/assets/brand/$name"
    cmp -s "$bfile" "$logo_dir/$name" || bad="$bad under /ocutalon/assets/brand/ ($code)"
    if [ -z "$bad" ]; then
      pass "maint-logo-$name" "$name is served beside the page and under /ocutalon/assets/brand/, byte for byte"
    else
      fail "maint-logo-$name" "$name is not served byte for byte:$bad"
    fi
  done
}

case $state in
  normal) run_normal ;;
  busy) run_busy ;;
  maintenance) run_maintenance ;;
esac

printf 'demo-host-check: %s: %d passed, %d failed, %d skipped\n' "$state" "$n_pass" "$n_fail" "$n_skip"
if [ "$n_fail" -gt 0 ]; then exit 1; fi
if [ "$n_skip" -gt 0 ]; then exit 3; fi
exit 0
