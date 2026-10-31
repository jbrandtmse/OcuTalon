#!/usr/bin/env bash
# The author's load run (Story 29.8; AD-13, AD-25): signs N scripted visitors in to the online demo, each from its own source address,
# drives the demo path within a stated bound of model turns, times each incident notice on the server's clock, has one more visitor read
# the status, open the splash and press Sign in, and signs everyone out. It measures what the demo carries: how many visitors run the path
# at once, whether each notice still arrives within NFR-7's 60 seconds, and whether the one more visitor sees "Demo busy" and never an
# error page. The procedure for the Contest Planner (release check H25) is in release/demo-host-checks.md.
#   bash release/demo-load.sh <base-url> --visitors N --max-turns M [--trace] [--hold S]
# <base-url> is the demo's origin, for example https://demo.example. --visitors is 1 to 8. --max-turns is required, 0 to 999: a driven
# visitor's run starts 2 model turns (its watch turn and its incident's diagnosis), so the first min(N, floor(M/2)) visitors drive the
# demo path and the rest only sign in. --trace opens Visual Trace for every visitor and needs M >= 2N. --hold is 0 to 600 seconds (default
# 0; at most 90 with --trace): after the one more visitor, every visitor polls the state for that long, so that another check can run
# while the demo is full. The one more visitor reads busy only when the run fills the demo: N is the visitor cap (6) without --trace,
# and 3 with --trace (6 trace connections); with any other N the line EXTRA FAIL status=free says so.
#
# Inputs (environment variables, all optional):
#   OCUTALON_GATE_USER, OCUTALON_GATE_PASSWORD   basic authentication for the access gate. They reach curl only through a temporary
#                                                configuration file readable by the owner alone, never through a command line, and are
#                                                never printed.
#   OCUTALON_LOAD_INTERFACES                     N+1 distinct source addresses (curl --interface), separated by white space or commas,
#                                                in visitor order; the last is the one more visitor's. For a host behind a proxy.
#   OCUTALON_LOAD_FORWARDED_FOR                  N+1 distinct addresses, each sent as X-Forwarded-For. Only for a local stack whose
#                                                proxy address is this machine's: a real proxy overwrites the header.
#   Never both lists. With neither, N is at most 4 (5 new sessions an hour per address, the one more visitor's included).
#   OCUTALON_LOAD_UNITS_COMMAND                  a command, split on white space and run with no shell evaluation, that prints the
#                                                connections and the licence units as two integers on its first line. It runs before the
#                                                run, after each sign-in, after each visitor's Visual Trace pages, after the one more
#                                                visitor and after the sign-out. Any other output reads "?" and fails nothing.
#   OCUTALON_LOAD_WATCH_TEXT                     the watch message. The default is the guide's watch prompt, sent as the guide's own
#                                                (fromGuide true); any other text is sent with fromGuide false.
#
# Each visitor, in this order: signs in (the splash prefills the published demo account, which is read from the page and never printed);
# drives the demo path (the watch message, Break the feed once its turn is done, the notice on the simulated phone, the approval of its
# request, the incident resolved); or, signed in only, polls the state until the drivers end; with --trace, opens one page in each Visual
# Trace application the run links to. Nothing that starts a model turn is ever sent twice; a 409 not_watching from Break the feed, which
# starts nothing, is retried every 2 s for 20 s.
#
# Output. Results go to standard output and progress to standard error. Visitors are named by number: no line holds the base URL, an
# address, a credential or the published account.
#   LOAD visitors=N max-turns=M trace=on|off hold=S
#   VISITOR <n> PASS|FAIL signin=<ok|busy|limit|refused|error> path=<driven|signed-in> turns=<k> notice=<s|-> fix=<state|-> trace=<k|busy|->
#            fallback=<none|reasons> units=<c>/<u>[,<c>/<u>] signout=<ok|failed|->   (and why=<first failure> on a FAIL)
#   EXTRA PASS|FAIL status=<busy|free|error> splash=<busy|form|error> signin=<busy|admitted|error>
#   UNITS before=<c>/<u> load=<c>/<u> after=<c>/<u>      (or UNITS n/a without a units command)
#   TURNS FAIL used <k> of at most <M>                   (only when the visitors' observed turns exceed M)
#   a Markdown table with one row per visitor and one for the one more visitor, for the 1.0.0 release notes, then
#   Model turns used: <k> of at most <M>.
#   demo-load: <p> passed, <f> failed
# A visitor passes when it signed in and out and, when driven, Break the feed answered 200, the notice came within 60 s, no turn or incident
# fell back with no_key, timeout, rate_limited or daily_cap, and the incident ended resolved or closed; with --trace, when both pages
# answered 200 with no IRIS sign-in field and the trace form was not busy before either. The one more visitor passes only when the status
# is busy, the splash is the busy page and the sign-in is refused as busy. A visitor that never signed in shows signout=-.
#
# It sends only GET and POST requests, each with a 30 s limit; every page request carries a unique t query; POSTs under /ocutalon/api/
# carry the browser envelope. It ends every session it opens, also on INT, TERM and HUP (exit 130), and removes its work folder.
#
# Exit codes: 0 every check passed; 1 a check failed; 2 a usage error, a missing tool (bash 3.2 or later, curl, jq), a 401 or 407 or no
# answer to the first request, or a first status that is not ready or already busy (nothing else is sent after a 2); 130 after a signal.
set -u
export LC_ALL=C

root=$(cd "$(dirname "$0")/.." && pwd)
lib="$root/docker/tests/lib-online.sh"

die2() {
  printf 'demo-load: %s\n' "$1" >&2
  exit 2
}

usage() {
  printf 'demo-load: %s\n' "$1" >&2
  printf 'usage: bash release/demo-load.sh <base-url> --visitors N --max-turns M [--trace] [--hold S]\n' >&2
  exit 2
}

# --- the tools ---

if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  die2 "bash 3.2 or later is required"
fi
for tool in curl jq grep sed tr head mktemp cp sleep; do
  command -v "$tool" > /dev/null 2>&1 || die2 "$tool is not installed"
done
[ -f "$lib" ] || die2 "docker/tests/lib-online.sh is missing"
. "$lib"

# The guide's watch prompt (web/src/app/guide/guide-view.ts, promptWatch) and the fallback reasons that fail a visitor: the probe's three
# (docker/probe.sh: no_key, timeout, rate_limited) and daily_cap, which means the turn did not use the model.
DEFAULT_WATCH='Watch the Orders production and only tell me if something needs me.'
DEGRADED_REASONS="no_key timeout rate_limited daily_cap"
NOTICE_LIMIT=60

# --- the arguments and the environment ---

base=""
visitors=""
max_turns=""
trace=0
hold=0
while [ $# -gt 0 ]; do
  case $1 in
    --visitors)
      [ $# -ge 2 ] || usage "--visitors needs a value"
      visitors=$2
      shift 2
      ;;
    --max-turns)
      [ $# -ge 2 ] || usage "--max-turns needs a value"
      max_turns=$2
      shift 2
      ;;
    --hold)
      [ $# -ge 2 ] || usage "--hold needs a value"
      hold=$2
      shift 2
      ;;
    --trace)
      trace=1
      shift
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
case $base in */) base=${base%/} ;; esac
origin_ok "$base" || usage "the base URL is an origin: a scheme, a host and an optional port, no path and no user name"

# whole_number <text> <name> <min> <max>: the text is a number (at most 3 digits) in the range; prints it without leading zeros.
whole_number() {
  case $1 in
    '' | *[!0-9]*) usage "$2 is a whole number" ;;
  esac
  [ "${#1}" -le 3 ] || usage "$2 is between $3 and $4"
  local v=$((10#$1))
  if [ "$v" -lt "$3" ] || [ "$v" -gt "$4" ]; then usage "$2 is between $3 and $4"; fi
  printf '%s' "$v"
}
[ -n "$visitors" ] || usage "--visitors is required"
[ -n "$max_turns" ] || usage "--max-turns is required"
visitors=$(whole_number "$visitors" "--visitors" 1 8) || exit 2
max_turns=$(whole_number "$max_turns" "--max-turns" 0 999) || exit 2
if [ "$trace" = 1 ]; then hold_max=90; else hold_max=600; fi
hold=$(whole_number "$hold" "--hold" 0 "$hold_max") || exit 2
if [ "$trace" = 1 ] && [ "$max_turns" -lt $((2 * visitors)) ]; then usage "--trace needs --max-turns of at least 2 per visitor ($((2 * visitors)))"; fi
drivers=$((max_turns / 2))
if [ "$drivers" -gt "$visitors" ]; then drivers=$visitors; fi

# read_addresses <variable name> <text>: reads the N+1 addresses of a list into v_iface or v_fwd (index 1 to N+1, the last the one more
# visitor's); usage error for a wrong count, an entry that is no address, or a repeat.
v_iface=()
v_fwd=()
extra=$((visitors + 1))
read_addresses() {
  local name=$1 text=$2 list a i=0 j seen
  list=$(printf '%s' "$text" | tr ',\t\r\n' '    ')
  set -f
  # shellcheck disable=SC2086
  set -- $list
  set +f
  [ $# -eq "$extra" ] || usage "$name holds $# addresses, wanted $extra (the visitors and one more)"
  for a in "$@"; do
    case $a in
      '' | *[!A-Za-z0-9.:_%-]*) usage "$name holds an entry that is no address or interface name" ;;
    esac
    i=$((i + 1))
    for ((j = 1; j < i; j++)); do
      if [ "$name" = OCUTALON_LOAD_INTERFACES ]; then seen=${v_iface[$j]}; else seen=${v_fwd[$j]}; fi
      [ "$seen" != "$a" ] || usage "$name repeats an address"
    done
    if [ "$name" = OCUTALON_LOAD_INTERFACES ]; then v_iface[$i]=$a; else v_fwd[$i]=$a; fi
  done
}
ifaces=${OCUTALON_LOAD_INTERFACES:-}
forwards=${OCUTALON_LOAD_FORWARDED_FOR:-}
if [ -n "$ifaces" ] && [ -n "$forwards" ]; then usage "OCUTALON_LOAD_INTERFACES and OCUTALON_LOAD_FORWARDED_FOR are never both set"; fi
if [ -n "$ifaces" ]; then
  read_addresses OCUTALON_LOAD_INTERFACES "$ifaces"
elif [ -n "$forwards" ]; then
  read_addresses OCUTALON_LOAD_FORWARDED_FOR "$forwards"
elif [ "$visitors" -gt 4 ]; then
  usage "more than 4 visitors need OCUTALON_LOAD_INTERFACES or OCUTALON_LOAD_FORWARDED_FOR (5 new sessions an hour per address)"
fi

gate_read || usage "$gate_problem"
if [ -n "$gate_user" ]; then
  case $base in http://*) printf 'demo-load: warning: the gate credentials go over plain http\n' >&2 ;; esac
fi

units_words=()
read -r -a units_words <<< "${OCUTALON_LOAD_UNITS_COMMAND:-}"

watch_text=${OCUTALON_LOAD_WATCH_TEXT:-$DEFAULT_WATCH}
if [ "$watch_text" = "$DEFAULT_WATCH" ]; then from_guide=true; else from_guide=false; fi
case $watch_text in *$'\n'* | *$'\r'*) usage "OCUTALON_LOAD_WATCH_TEXT holds a line break" ;; esac

umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-load-run.XXXXXX") || die2 "no temporary folder"
driver_pids=""
waiter_pids=""
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

# The gate credentials: a curl configuration file (mode 600) read with -K, so that they are in no command line (gate_config of
# docker/tests/lib-online.sh).
gate_config "$work"

# --- the results of one visitor: key=value lines in the visitor's folder ---

setv() { printf '%s=%s\n' "$2" "$3" >> "$work/v$1/result"; }
getv() { # <visitor> <key> <default>: the last value of the key
  local v
  v=$(grep "^$2=" "$work/v$1/result" 2> /dev/null | tail -n 1)
  v=${v#*=}
  printf '%s' "${v:-$3}"
}
getall() { # <visitor> <key>: every value of the key, comma separated
  grep "^$2=" "$work/v$1/result" 2> /dev/null | sed 's/^[^=]*=//' | tr '\n' ',' | sed 's/,$//'
}
clean() { # <text>: server-supplied text as safe output (anything outside letters, digits and . _ , : / space - becomes _)
  printf '%s' "$1" | tr -c 'A-Za-z0-9_,.:/ -' '_'
}
vfail() { # <visitor> <text>: records the first failure of the visitor
  [ -n "$(getv "$1" why '')" ] || setv "$1" why "$2"
}
progress() { printf 'demo-load: %s\n' "$1" >&2; }

for ((n = 1; n <= extra; n++)); do
  mkdir "$work/v$n"
  : > "$work/v$n/jar"
  : > "$work/v$n/result"
  echo 0 > "$work/v$n/t"
done
: > "$work/signed"
: > "$work/opened"

# --- requests: every request of the run goes through vcall ---

code=000
hfile=""
bfile=""
no_stop=""
tq=""

# t_next <visitor>: sets tq to a query value that no request of the run used (a counter per visitor, in a file, so that it also holds
# across the background processes).
t_next() {
  local n=0
  read -r n < "$work/v$1/t"
  n=$((n + 1))
  echo "$n" > "$work/v$1/t"
  tq="$1x$n"
}

# vcall <visitor> <GET|GETP|POST> <path> [<curl argument>...]: one request as the visitor, from its own address, on its own cookie jar
# (GETP: a public read, with no jar). Leaves the status in code (000 when there was no answer or the run is stopping), the headers in hfile
# and the body in bfile. GETs carry a unique t query; POSTs under /ocutalon/api/ carry the browser envelope.
vcall() {
  local vn=$1 method=$2 path=$3 d target args=()
  shift 3
  d=$work/v$vn
  code=000
  hfile=$d/h
  bfile=$d/b
  : > "$hfile"
  : > "$bfile"
  if [ -z "$no_stop" ] && [ -e "$work/stop" ]; then return 1; fi
  case $method in
    POST) target=$path ;;
    *)
      t_next "$vn"
      case $path in
        *\?*) target="$path&t=$tq" ;;
        *) target="$path?t=$tq" ;;
      esac
      ;;
  esac
  args=(-s --max-time 30 ${gate_args[@]+"${gate_args[@]}"})
  if [ "$method" != GETP ]; then args+=(-b "$d/jar" -c "$d/jar"); fi
  if [ -n "${v_iface[$vn]:-}" ]; then args+=(--interface "${v_iface[$vn]}"); fi
  if [ -n "${v_fwd[$vn]:-}" ]; then args+=(-H "X-Forwarded-For: ${v_fwd[$vn]}"); fi
  if [ "$method" = POST ]; then
    case $path in
      /ocutalon/api/*) args+=(-H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base") ;;
    esac
  fi
  args+=(-D "$hfile" -o "$bfile" -w '%{http_code}')
  code=$(curl "${args[@]}" ${1+"$@"} "$base$target" < /dev/null 2> /dev/null) || code=000
  if [ -z "$code" ]; then code=000; fi
  return 0
}

# --- licence readings ---

unit_now=-
unit_read() { # sets unit_now to "<connections>/<units>", "?" when the command printed anything else, "-" without a command
  local line c u rest
  unit_now=-
  [ ${#units_words[@]} -gt 0 ] || return 0
  unit_now='?'
  line=$("${units_words[@]}" 2> /dev/null < /dev/null | head -n 1)
  if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+([[:space:]].*)?$'; then
    read -r c u rest <<< "$line"
    unit_now="$c/$u"
  fi
}

# --- pages ---

BUSY_TEXT='The demo is busy right now.'
LIMIT_TEXT='Too many new sessions from your network this hour'
TITLE_TAG='<title>Try OcuTalon</title>'

# page_busy: the last body is the busy page (the text and the title).
page_busy() { grep -qF -- "$BUSY_TEXT" "$bfile" && grep -qF -- "$TITLE_TAG" "$bfile"; }

# classify_page: prints busy, limit, refused or error for the last body of a sign-in that did not reach the shell.
classify_page() {
  if page_busy; then
    echo busy
  elif grep -qF -- "$LIMIT_TEXT" "$bfile"; then
    echo limit
  elif grep -q 'aria-invalid' "$bfile"; then
    echo refused
  else
    echo error
  fi
}

# page_account <file>: sets acct_user and acct_pw to the account that the splash prefills (empty when the page has none).
acct_user=""
acct_pw=""
page_account() {
  local unescape='s/&quot;/"/g; s/&#39;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g'
  acct_user=$(sed -n 's/.*name="IRISUsername"[^>]*value="\([^"]*\)".*/\1/p' "$1" | head -n 1 | sed "$unescape")
  acct_pw=$(sed -n 's/.*name="IRISPassword"[^>]*value="\([^"]*\)".*/\1/p' "$1" | head -n 1 | sed "$unescape")
}

# write_signin_body <visitor>: the sign-in form's three fields, in a file of the visitor's folder; clears the account from memory.
write_signin_body() {
  printf 'IRISUsername=%s&IRISPassword=%s&IRISLogin=%s' "$(pct "$acct_user")" "$(pct "$acct_pw")" "$(pct 'Sign in and start')" > "$work/v$1/signin.body"
  acct_user=""
  acct_pw=""
}

# post_signin <visitor>: posts the visitor's sign-in body.
post_signin() {
  vcall "$1" POST /ocutalon/ -H 'Content-Type: application/x-www-form-urlencoded' --data-binary "@$work/v$1/signin.body"
  case $code in
    3??) echo "$1" >> "$work/opened" ;;
  esac
}

# signin_visitor <visitor>: the splash, the sign-in and the first state read; the visitor is signed in once /state answers 200.
signin_visitor() {
  local vn=$1 d=$work/v$1 cls
  vcall "$vn" GET /ocutalon/
  page_account "$bfile"
  if [ -z "$acct_user" ] || [ -z "$acct_pw" ]; then
    cls=$(classify_page)
    setv "$vn" signin "$cls"
    vfail "$vn" "sign-in $cls (the splash answered $code with no sign-in form)"
    return 1
  fi
  write_signin_body "$vn"
  if [ ! -f "$work/account.body" ]; then cp "$d/signin.body" "$work/account.body"; fi
  post_signin "$vn"
  cp "$bfile" "$d/post.b"
  case $code in
    3??) vcall "$vn" GET /ocutalon/ ;;
  esac
  vcall "$vn" GET /ocutalon/api/v1/state
  if [ "$code" = 200 ]; then
    setv "$vn" signin ok
    echo "$vn" >> "$work/signed"
    return 0
  fi
  cp "$d/post.b" "$bfile"
  cls=$(classify_page)
  setv "$vn" signin "$cls"
  vfail "$vn" "sign-in $cls"
  if grep -qx "$vn" "$work/opened"; then signout_visitor "$vn"; fi
  return 1
}

# signout_visitor <visitor>: ends the visitor's session. session/end, then ?IRISLogout=end on both trace applications and on /ocutalon/,
# then /state must answer 401.
signout_visitor() {
  local vn=$1 ok=1 app
  vcall "$vn" POST /ocutalon/api/v1/session/end --data-binary '{}'
  case $code in 2??) ;; *)
    ok=0
    vfail "$vn" "session/end answered $code"
    ;;
  esac
  for app in /ocutalon/trace/ocutalon/ /ocutalon/trace/ocuorders/ /ocutalon/; do
    vcall "$vn" GET "$app?IRISLogout=end"
  done
  vcall "$vn" GET /ocutalon/api/v1/state
  if [ "$code" != 401 ]; then
    ok=0
    vfail "$vn" "the state still answered $code after the sign-out"
  fi
  if [ "$ok" = 1 ]; then setv "$vn" signout ok; else setv "$vn" signout failed; fi
}

# --- the driven demo path ---

JQ_T='def tm: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;'

# poll_until <seconds> <function>: reads /state every second until the function succeeds on the answer; returns 1 on the limit and when the
# run is stopping.
poll_until() {
  local vn=$1 limit=$2 fn=$3 end
  end=$((SECONDS + limit))
  while :; do
    vcall "$vn" GET /ocutalon/api/v1/state
    if [ "$code" = 200 ] && "$fn" "$vn"; then return 0; fi
    if [ -e "$work/stop" ] || [ "$SECONDS" -ge "$end" ]; then return 1; fi
    sleep 1
  done
}

turn_done() { jq -e '[.chat[]? | select(.type == "chat.message")] | last | .payload.state == "done"' "$bfile" > /dev/null 2>&1; }

notice_seen() { # sets started (a global of the driver) to look for the first phone item at or after it
  local item
  item=$(jq -c --arg s "$started" "$JQ_T"' [.phone[]? | select((.createdAt | type) == "string" and (.createdAt | tm) >= ($s | tm))] | sort_by(.createdAt | tm) | first // empty' "$bfile" 2> /dev/null)
  [ -n "$item" ] || return 1
  phone_item=$item
  return 0
}

incident_ended() {
  local st
  st=$(jq -r '[.chat[]? | select(.type == "incident") | .payload.state] | last // ""' "$bfile" 2> /dev/null)
  if [ -n "$st" ]; then setv "$1" fix "$st"; fi
  case $st in resolved | closed) return 0 ;; esac
  return 1
}

started=""
phone_item=""
# drive_visitor <visitor>: the demo path of one signed-in visitor (runs in a background process). Every failure is recorded with vfail and
# ends the path; nothing that starts a model turn is sent twice.
drive_visitor() {
  local vn=$1 body id end err notice ref st
  id="load-$vn-$RANDOM$RANDOM"
  body=$(jq -cn --arg id "$id" --arg t "$watch_text" --argjson g "$from_guide" '{clientId: $id, text: $t, fromGuide: $g}')
  vcall "$vn" POST /ocutalon/api/v1/messages --data-binary "$body"
  case $code in
    2??) ;;
    *)
      vfail "$vn" "the watch message answered $code"
      return
      ;;
  esac
  progress "visitor $vn sent the watch message"
  if ! poll_until "$vn" 120 turn_done; then
    vfail "$vn" "the watch turn was not done in 120 s"
    return
  fi

  # Break the feed: a 409 not_watching starts nothing and is retried every 2 s for 20 s.
  end=$((SECONDS + 20))
  while :; do
    vcall "$vn" POST /ocutalon/api/v1/demo/break-feed --data-binary '{}'
    if [ "$code" = 200 ]; then
      started=$(jq -r '.startedAt // ""' "$bfile" 2> /dev/null)
      break
    fi
    if [ "$code" = 409 ]; then
      err=$(jq -r '.error.code // ""' "$bfile" 2> /dev/null)
      if [ "$err" != not_watching ]; then
        vfail "$vn" "Break the feed was refused (${err:-409})"
        return
      fi
      if [ -e "$work/stop" ]; then return; fi
      if [ "$SECONDS" -ge "$end" ]; then
        vfail "$vn" "not watching"
        return
      fi
      sleep 2
      continue
    fi
    vfail "$vn" "Break the feed answered $code"
    return
  done
  case $started in
    '' | *[!0-9TZ:.-]*)
      vfail "$vn" "Break the feed gave no start time"
      return
      ;;
  esac
  progress "visitor $vn pressed Break the feed"

  # The notice: the first simulated-phone item at or after the press, timed on the server's clock.
  if ! poll_until "$vn" 120 notice_seen; then
    vfail "$vn" "no notice in 120 s"
    return
  fi
  notice=$(printf '%s' "$phone_item" | jq -r --arg s "$started" "$JQ_T"' (.createdAt | tm) - ($s | tm)')
  setv "$vn" notice "$notice"
  case $notice in
    '' | *[!0-9]*)
      vfail "$vn" "the notice time is unreadable"
      return
      ;;
  esac
  if [ "$notice" -gt "$NOTICE_LIMIT" ]; then vfail "$vn" "notice over $NOTICE_LIMIT s"; fi
  ref=$(printf '%s' "$phone_item" | jq -r '.approvalRef // ""')
  case $ref in
    '' | *[!A-Za-z0-9_-]*)
      vfail "$vn" "the notice holds no approval request"
      return
      ;;
  esac

  # The approval on the phone channel, then the incident's end.
  vcall "$vn" POST "/ocutalon/api/v1/approvals/$ref/answer" --data-binary '{"action":"approve","channel":"phone"}'
  if [ "$code" != 200 ]; then
    vfail "$vn" "the approval answered $code"
    return
  fi
  if ! poll_until "$vn" 120 incident_ended; then
    st=$(getv "$vn" fix '')
    vfail "$vn" "the incident was not resolved in 120 s (${st:-no incident})"
    return
  fi
  progress "visitor $vn: the incident is $(getv "$vn" fix '')"
}

# wait_visitor <visitor>: a signed-in-only visitor polls /state every 5 s until the drivers end.
wait_visitor() {
  local vn=$1 i
  while :; do
    vcall "$vn" GET /ocutalon/api/v1/state
    if [ "$code" != 200 ] && [ ! -e "$work/stop" ]; then
      vfail "$vn" "the state answered $code while waiting"
      return
    fi
    for i in 1 2 3 4 5; do
      if [ -e "$work/drivers.done" ] || [ -e "$work/stop" ]; then return; fi
      sleep 1
    done
  done
}

# stop_drivers: tells the background processes to stop and waits up to 10 s for them.
stop_drivers() {
  local i p alive
  : > "$work/stop"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    alive=0
    for p in $driver_pids $waiter_pids; do
      if kill -0 "$p" 2> /dev/null; then alive=1; fi
    done
    [ "$alive" = 1 ] || break
    sleep 1
  done
  for p in $driver_pids $waiter_pids; do kill "$p" 2> /dev/null; done
  wait 2> /dev/null
}

# On INT, TERM or HUP: stop the drivers, sign out every visitor signed in so far, and exit 130.
on_signal() {
  local n
  trap '' INT TERM HUP
  printf 'demo-load: interrupted: signing everyone out\n' >&2
  stop_drivers
  no_stop=1
  for n in $(cat "$work/signed" "$work/opened" 2> /dev/null | sort -un); do signout_visitor "$n"; done
  exit 130
}
trap on_signal INT TERM HUP

# --- after the drivers: the state of a visitor ---

# collect_visitor <visitor>: the observed turns (each chat turn with a decision, each incident with a decisionRef), the fallback reasons
# of the turns and incidents, and the visitor's trace links.
collect_visitor() {
  local vn=$1 d=$work/v$1 k f r
  vcall "$vn" GET /ocutalon/api/v1/state
  if [ "$code" != 200 ]; then
    vfail "$vn" "the state answered $code at the end"
    setv "$vn" turns 0
    setv "$vn" fallback none
    return
  fi
  cp "$bfile" "$d/state.json"
  k=$(jq -r '([.chat[]? | select(.type == "chat.message" and ((.payload.decision | type) == "object"))] | length)
    + ([.chat[]? | select(.type == "incident" and ((.payload.decisionRef // "") != ""))] | length)' "$d/state.json" 2> /dev/null)
  case $k in '' | *[!0-9]*) k=0 ;; esac
  setv "$vn" turns "$k"
  f=$(jq -r '[.chat[]? | select(.type == "chat.message" or .type == "incident") | .payload
    | ((.fallbackReason // empty), (.decision.fallbackReason? // empty))] | map(select(type == "string" and . != "")) | unique | join(",")' "$d/state.json" 2> /dev/null)
  setv "$vn" fallback "${f:-none}"
  for r in $DEGRADED_REASONS; do
    case ",$f," in *",$r,"*) vfail "$vn" "fallback $r" ;; esac
  done
}

# --- Visual Trace ---

# trace_visitor <visitor>: one page in each trace application the run links to; the trace form of the status is read before each page.
trace_visitor() {
  local vn=$1 d=$work/v$1 app url ok=0 busy
  for app in /ocutalon/trace/ocutalon/ /ocutalon/trace/ocuorders/; do
    url=$(jq -r --arg a "$app" '[.. | objects | .traceUrl? // empty | strings | select(startswith($a))] | first // ""' "$d/state.json" 2> /dev/null)
    if [ -z "$url" ]; then
      vfail "$vn" "the state links no trace page under $app"
      continue
    fi
    vcall "$vn" GETP "/ocutalon/public/status?for=trace"
    busy=$(jq -r '.busy' "$bfile" 2> /dev/null)
    if [ "$code" = 200 ] && [ "$busy" = true ]; then
      setv "$vn" tracebusy 1
      vfail "$vn" "the trace form was busy before a page"
      break
    fi
    if [ "$code" != 200 ] || [ "$busy" != false ]; then
      vfail "$vn" "the trace form's status answered $code"
      continue
    fi
    vcall "$vn" GET "$url"
    if [ "$code" != 200 ]; then
      vfail "$vn" "a trace page answered $code"
    elif grep -Eq "$HOST_FORM_FIELD_RE" "$bfile"; then
      vfail "$vn" "a trace page asked for an IRIS sign-in"
    else
      ok=$((ok + 1))
    fi
  done
  setv "$vn" tracepages "$ok"
}

# --- the one more visitor ---

x_status=error
x_splash=error
x_signin=error
extra_visitor() {
  local vn=$extra b
  x_status=error
  x_splash=error
  x_signin=error
  vcall "$vn" GETP /ocutalon/public/status
  if [ "$code" = 200 ]; then
    b=$(jq -r '.busy' "$bfile" 2> /dev/null)
    case $b in true) x_status=busy ;; false) x_status=free ;; esac
  fi
  vcall "$vn" GET /ocutalon/
  if page_busy; then
    x_splash=busy
  elif [ "$code" = 200 ] && grep -qF -- "$TITLE_TAG" "$bfile"; then
    x_splash=form
  fi
  page_account "$bfile"
  if [ -n "$acct_user" ] && [ -n "$acct_pw" ]; then
    write_signin_body "$vn"
  elif [ -f "$work/account.body" ]; then
    cp "$work/account.body" "$work/v$vn/signin.body"
  else
    acct_user=""
    acct_pw=""
    return
  fi
  post_signin "$vn"
  cp "$bfile" "$work/v$vn/post.b"
  if page_busy; then
    x_signin=busy
    return
  fi
  case $code in
    3??) x_signin=admitted ;;
    *)
      vcall "$vn" GET /ocutalon/api/v1/state
      if [ "$code" = 200 ]; then x_signin=admitted; fi
      ;;
  esac
  if [ "$x_signin" = admitted ]; then
    echo "$vn" >> "$work/signed"
    signout_visitor "$vn"
  fi
}

# --- the run ---

# The first request: a 401 or 407 or no answer, a status that is not ready, and a demo that is already busy end the run (exit 2).
vcall 1 GETP /ocutalon/public/status
case $code in
  401 | 407) die2 "gate refused: the host answered $code to the first request (check OCUTALON_GATE_USER and OCUTALON_GATE_PASSWORD)" ;;
  000) die2 "host unreachable: no answer to the first request" ;;
  200) ;;
  *) die2 "the status read answered $code, so the demo is not ready" ;;
esac
if ! jq -e '.ready == true' "$bfile" > /dev/null 2>&1; then die2 "the demo is not ready: the status does not say ready true"; fi
if ! jq -e '.busy == false' "$bfile" > /dev/null 2>&1; then die2 "the demo is already busy: nothing would be measured"; fi

printf 'LOAD visitors=%s max-turns=%s trace=%s hold=%s\n' "$visitors" "$max_turns" "$([ "$trace" = 1 ] && echo on || echo off)" "$hold"

unit_read
u_before=$unit_now

# Sign in, one visitor after the other; a licence reading follows each.
for ((n = 1; n <= visitors; n++)); do
  if [ "$n" -le "$drivers" ]; then setv "$n" path driven; else setv "$n" path signed-in; fi
  if signin_visitor "$n"; then progress "visitor $n signed in"; else progress "visitor $n did not sign in"; fi
  unit_read
  setv "$n" unit "$unit_now"
done

# Drive: the driven visitors in parallel, the signed-in-only ones polling.
for ((n = 1; n <= visitors; n++)); do
  [ "$(getv "$n" signin '')" = ok ] || continue
  if [ "$n" -le "$drivers" ]; then
    drive_visitor "$n" &
    driver_pids="$driver_pids $!"
  else
    wait_visitor "$n" &
    waiter_pids="$waiter_pids $!"
  fi
done
for p in $driver_pids; do wait "$p"; done
: > "$work/drivers.done"
for p in $waiter_pids; do wait "$p"; done

for n in $(cat "$work/signed"); do collect_visitor "$n"; done

# Visual Trace, one visitor after the other; a licence reading follows each visitor's pages.
if [ "$trace" = 1 ]; then
  for n in $(cat "$work/signed"); do
    trace_visitor "$n"
    unit_read
    setv "$n" unit "$unit_now"
  done
fi

# The one more visitor, after every visitor has finished its steps.
extra_visitor
unit_read
setv "$extra" unit "$unit_now"

# Hold: every visitor still signed in polls /state every 5 s, the last poll at least S seconds after the first.
if [ "$hold" -gt 0 ]; then
  held=""
  for n in $(cat "$work/signed"); do
    [ "$(getv "$n" signin '')" = ok ] && [ "$n" -le "$visitors" ] && held="$held $n"
  done
  printf 'HOLD %s s with %s visitors signed in\n' "$hold" "$(printf '%s\n' $held | grep -c .)" >&2
  hold_end=$((SECONDS + hold + 1))
  while :; do
    for n in $held; do
      vcall "$n" GET /ocutalon/api/v1/state
      if [ "$code" != 200 ]; then vfail "$n" "the state answered $code during the hold"; fi
    done
    left=$((hold_end - SECONDS))
    [ "$left" -gt 0 ] || break
    if [ "$left" -gt 5 ]; then left=5; fi
    for ((i = 0; i < left; i++)); do sleep 1; done
  done
fi

# Sign out.
for ((n = 1; n <= visitors; n++)); do
  if [ "$(getv "$n" signin '')" = ok ]; then
    signout_visitor "$n"
  else
    setv "$n" signout -
  fi
done
unit_read
u_after=$unit_now

# --- the report ---

# The load reading is the highest reading of the run (most connections, then most units): the reading after the one more visitor can
# already be lower, because a trace connection ends by itself within minutes.
u_load=$unit_now
best_c=-1
best_u=-1
for n in $(seq 1 "$extra"); do
  for r in $(getall "$n" unit | tr ',' ' ') $u_before; do
    case $r in
      [0-9]*/[0-9]*)
        c=${r%/*}
        u=${r#*/}
        if [ "$c" -gt "$best_c" ] || { [ "$c" -eq "$best_c" ] && [ "$u" -gt "$best_u" ]; }; then
          best_c=$c
          best_u=$u
          u_load=$r
        fi
        ;;
    esac
  done
done

n_pass=0
n_fail=0
turns_used=0
table=""
trace_mode=off
if [ "$trace" = 1 ]; then trace_mode=on; fi

for ((n = 1; n <= visitors; n++)); do
  signin=$(getv "$n" signin error)
  path=$(getv "$n" path signed-in)
  turns=$(getv "$n" turns 0)
  notice=$(getv "$n" notice -)
  fix=$(clean "$(getv "$n" fix -)")
  fallback=$(clean "$(getv "$n" fallback none)")
  signout=$(getv "$n" signout -)
  why=$(clean "$(getv "$n" why '')")
  units=$(getall "$n" unit)
  if [ -z "${OCUTALON_LOAD_UNITS_COMMAND:-}" ]; then units=; fi
  if [ "$trace" = 1 ]; then
    if [ "$(getv "$n" tracebusy 0)" = 1 ]; then trc=busy; else trc=$(getv "$n" tracepages 0); fi
  else
    trc=-
  fi
  [ "$path" = driven ] || fix=-
  turns_used=$((turns_used + turns))
  if [ -z "$why" ] && [ "$signin" = ok ] && [ "$signout" = ok ]; then verdict=PASS; else verdict=FAIL; fi
  if [ "$verdict" = PASS ]; then n_pass=$((n_pass + 1)); else n_fail=$((n_fail + 1)); fi
  line=$(printf 'VISITOR %s %s signin=%s path=%s turns=%s notice=%s fix=%s trace=%s fallback=%s units=%s signout=%s' "$n" "$verdict" "$signin" "$path" "$turns" "$notice" "$fix" "$trc" "$fallback" "${units:--}" "$signout")
  if [ "$verdict" = FAIL ]; then line="$line why=${why:-unknown}"; fi
  printf '%s\n' "$line"
  if [ "$signin" = ok ]; then signed_in=yes; else signed_in=$signin; fi
  if [ "$notice" = - ]; then within=-; elif [ "$notice" -le "$NOTICE_LIMIT" ]; then within=yes; else within=no; fi
  table="$table$(printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' "$n" "$signed_in" "$path" "$turns" "$notice" "$within" "$fix" "$trc" "$fallback" "${units:--}" "$signout")
"
done

if [ "$x_status" = busy ] && [ "$x_splash" = busy ] && [ "$x_signin" = busy ]; then
  x_verdict=PASS
  n_pass=$((n_pass + 1))
else
  x_verdict=FAIL
  n_fail=$((n_fail + 1))
fi
printf 'EXTRA %s status=%s splash=%s signin=%s\n' "$x_verdict" "$x_status" "$x_splash" "$x_signin"
if [ -n "${OCUTALON_LOAD_UNITS_COMMAND:-}" ]; then
  printf 'UNITS before=%s load=%s after=%s\n' "$u_before" "$u_load" "$u_after"
else
  printf 'UNITS n/a\n'
fi
if [ "$turns_used" -gt "$max_turns" ]; then
  printf 'TURNS FAIL used %s of at most %s\n' "$turns_used" "$max_turns"
  n_fail=$((n_fail + 1))
fi

case $x_signin in
  busy) x_signed="refused (busy)" ;;
  admitted) x_signed="admitted" ;;
  *) x_signed=error ;;
esac
table="$table$(printf '| %s (one more) | %s | - | - | - | - | - | - | - | %s | - |' "$extra" "$x_signed" "$(getv "$extra" unit -)")
"
printf '\n| Visitor | Signed in | Demo path | Model turns | Notice (s) | Within 60 s | Fix | Trace pages | Fallbacks | Connections/units | Signed out |\n'
printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
printf '%s' "$table"
printf '\nModel turns used: %s of at most %s.\n\n' "$turns_used" "$max_turns"
printf 'demo-load: %s passed, %s failed\n' "$n_pass" "$n_fail"
if [ "$n_fail" -gt 0 ]; then exit 1; fi
exit 0
