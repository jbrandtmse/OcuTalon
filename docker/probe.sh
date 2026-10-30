#!/usr/bin/env bash
# The online demo's probe (Story 16.6; FR-59, AD-13, AD-19, AD-25). One invocation is one check; the demo host's scheduler runs it
# every 15 minutes, directly against IRIS and from an address other than the public proxyAddress, so that its sign-in is exempt from
# the busy refusal and from the per-address limit (AD-13). It never goes through the proxy.
#
# One run, in this order; the first step that ends the run decides its outcome, and every answer passes the busy rule first (HTTP 503,
# or the header X-OcuTalon-Busy: 1 in any case, ends the run as busy):
#   1. GET /ocutalon/public/status; a body with "busy":true is busy.
#   2. GET /ocutalon/ on a fresh cookie jar: the splash is served when the answer is 200 and the page holds the splash's title and a
#      password field; anything else is no_splash (the local sign-in page, a 404, nothing listening, a timeout).
#   3. One sign-in form POST to /ocutalon/ on the splash's jar (user name, password, the submit value, and the session token when the
#      splash form carries one), then one GET of /ocutalon/ after a redirect. The application's shell means signed in; the form
#      coming back is auth_failed; anything else is no_decision.
#   4. POST /ocutalon/api/v1/messages with the fixed message and the browser envelope (JSON, X-OcuTalon-Request: 1, a matching Origin);
#      any answer but 202 is no_decision.
#   5. GET /ocutalon/api/v1/events every 2 s, up to 120 s after the 202, for the turn's decision: a chat.message event of this run's
#      clientId in the state done that carries a decision object. A fallback reason of daily_cap is capped, any other decision is
#      healthy, and no decision is no_decision.
#   6. POST /ocutalon/api/v1/session/end with the envelope, on every path of a run that signed in (an EXIT trap backs it up).
# No API call is made before the sign-in succeeded or after the sign-out. The password reaches curl on its standard input and nowhere
# else; the cookie jar lives in a private temporary folder that is removed at exit; no resume cookie is kept between runs.
#
# Configuration: environment variables only, and this file names none of their values.
#   OCUTALON_PROBE_URL             the origin of IRIS: the http or https scheme, a host and an optional port, no path (one trailing
#                                  slash is dropped, and so is the scheme's default port, 80 or 443, as in the Host header). It is
#                                  also the Origin of every POST.
#   OCUTALON_DEMO_USER, OCUTALON_DEMO_PASSWORD   the published demo account (AD-19's names).
#   OCUTALON_PROBE_ALERT_COMMAND   the host's alert command.
#   OCUTALON_PROBE_RESET_COMMAND   the host's reset command.
#   OCUTALON_PROBE_STATE_DIR       the state folder; created when it is missing.
# Each command variable is split on white space into words, with no shell evaluation. The alert command gets two more arguments, the
# outcome and the run's log line; the reset command gets none, runs in the foreground, and its exit status goes into the log line.
# A failing alert command prints one line on stderr and changes nothing else.
# For tests only (the host never sets them): OCUTALON_PROBE_MESSAGE replaces the fixed message, and OCUTALON_PROBE_DECISION_WAIT is
# a whole number of seconds from 1 to 120 that shortens the wait for the decision (it is 120 when unset).
#
# Outcomes, effects and exit codes (one label per run):
#   healthy, capped        no alert; the count of counted failures is cleared                          exit 0
#   busy                   alert; the count is unchanged; one is added to today's busy count           exit 1
#   no_splash              alert; the count is unchanged                                              exit 1
#   auth_failed, no_decision   alert; the count plus one; at two the reset command runs once and the count is cleared   exit 1
# A configuration error (a missing variable, a URL that is not an origin, a wait outside 1-120) makes no request, writes nothing,
# prints one line on stderr naming the variable, and exits 2. A run that receives INT, TERM or HUP signs out and exits 130, with no
# log line, alert or count update. Each request may take 5 s to connect and 20 s in all, so a run's own requests end within about
# 5 minutes; the probe sets no time limit on the host's alert and reset commands.
#
# State folder: probe.log (one appended line per run, also printed on stdout: <UTC time> <outcome> count=<n>[ fallback=<reason>]
# [ reset=<exit status>]), counted-failures (the count, written whole through a rename), busy-per-day (one "YYYY-MM-DD <n>" line per
# UTC day). Inside a run: classify, sign out, update the counts, run the reset when it is due, append the log line, then alert.
#
# Needs bash 3.2 or later, curl and POSIX utilities (date, sed, grep, tr, mkdir, mv, mktemp). No jq, Python or Node: the JSON is read
# by key tokens on IRIS's compact output, in which a quote inside a string is always escaped.
set -u

utc() { TZ=UTC0 date "$@"; }

config_error() {
  printf 'probe: configuration error: %s\n' "$1" >&2
  exit 2
}

# --- the configuration: checked in full before anything is requested or written ---

for name in OCUTALON_PROBE_URL OCUTALON_DEMO_USER OCUTALON_DEMO_PASSWORD OCUTALON_PROBE_ALERT_COMMAND OCUTALON_PROBE_RESET_COMMAND OCUTALON_PROBE_STATE_DIR; do
  if [ -z "${!name:-}" ]; then config_error "$name is not set"; fi
done

url=$OCUTALON_PROBE_URL
case $url in */) url=${url%/} ;; esac
if ! printf '%s\n' "$url" | grep -Eq '^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$'; then
  config_error "OCUTALON_PROBE_URL is not an origin (a scheme, a host and an optional port, no path)"
fi
case $url in http://*:80) url=${url%:80} ;; https://*:443) url=${url%:443} ;; esac

decision_wait=${OCUTALON_PROBE_DECISION_WAIT:-120}
case $decision_wait in
  '' | *[!0-9]*) config_error "OCUTALON_PROBE_DECISION_WAIT is not a whole number of seconds from 1 to 120" ;;
esac
if [ "${#decision_wait}" -gt 3 ] || [ "$((10#$decision_wait))" -lt 1 ] || [ "$((10#$decision_wait))" -gt 120 ]; then
  config_error "OCUTALON_PROBE_DECISION_WAIT is not a whole number of seconds from 1 to 120"
fi
decision_wait=$((10#$decision_wait))

read -r -a alert_words <<< "$OCUTALON_PROBE_ALERT_COMMAND"
read -r -a reset_words <<< "$OCUTALON_PROBE_RESET_COMMAND"
if [ "${#alert_words[@]}" -eq 0 ]; then config_error "OCUTALON_PROBE_ALERT_COMMAND is not set"; fi
if [ "${#reset_words[@]}" -eq 0 ]; then config_error "OCUTALON_PROBE_RESET_COMMAND is not set"; fi

user=$OCUTALON_DEMO_USER
password=$OCUTALON_DEMO_PASSWORD
unset OCUTALON_DEMO_PASSWORD
state_dir=$OCUTALON_PROBE_STATE_DIR
default_message="Health check from the online demo's probe. Reply with one short sentence."
message=${OCUTALON_PROBE_MESSAGE:-$default_message}

work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-probe.XXXXXX" 2> /dev/null) || config_error "TMPDIR is not usable for a temporary folder"
chmod 700 "$work"
if ! mkdir -p "$state_dir" 2>/dev/null || [ ! -w "$state_dir" ]; then
  rm -rf "$work"
  config_error "OCUTALON_PROBE_STATE_DIR cannot be created or written"
fi

# --- the run ---

jar="$work/jar"
: > "$jar"
curl_opts=(-s --connect-timeout 5 --max-time 20)
form_field='name="\{0,1\}IRISPassword'
signed_in=0
outcome=
fallback=
reset_status=
tn=0
rc=000

# signout ends the session of a run that signed in (once); cleanup runs it on every exit path, then removes the temporary folder.
signout() {
  [ "$signed_in" = 1 ] || return 0
  signed_in=0
  curl "${curl_opts[@]}" -b "$jar" -c "$jar" -o /dev/null -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' \
    -H "Origin: $url" --data '{}' "$url/ocutalon/api/v1/session/end" > /dev/null 2>&1 < /dev/null
  return 0
}
cleanup() {
  signout
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# get <path> <query or ""> <jar or "">: one GET with a unique t parameter. It leaves the status in rc, the headers in $work/head and
# the body in $work/body (rc is 000 when there was no answer).
get() {
  local query="t=$((tn += 1))"
  if [ -n "$2" ]; then query="$2&$query"; fi
  : > "$work/head"
  : > "$work/body"
  if [ -n "$3" ]; then
    rc=$(curl "${curl_opts[@]}" -b "$3" -c "$3" -D "$work/head" -o "$work/body" -w '%{http_code}' "$url$1?$query" 2> /dev/null < /dev/null) || true
  else
    rc=$(curl "${curl_opts[@]}" -D "$work/head" -o "$work/body" -w '%{http_code}' "$url$1?$query" 2> /dev/null < /dev/null) || true
  fi
  if [ -z "$rc" ]; then rc=000; fi
}

# busy_answer: the last answer is HTTP 503 or carries the busy header.
busy_answer() {
  [ "$rc" = 503 ] && return 0
  tr -d '\r' < "$work/head" | grep -qi '^x-ocutalon-busy:[[:space:]]*1[[:space:]]*$'
}

# scan_events: reads the last events body: raises after_instance to the highest instance seq seen and sets decision_line to the event
# that is this run's turn's decision, or leaves it empty.
scan_events() {
  local ev seq
  decision_line=
  sed 's/{"seq":/\
&/g' "$work/body" > "$work/events"
  while IFS= read -r ev || [ -n "$ev" ]; do
    case $ev in '{"seq":'*) ;; *) continue ;; esac
    case $ev in
      '{"seq":'[0-9]*',"stream":"instance",'*)
        seq=${ev#'{"seq":'}
        seq=${seq%%,*}
        case $seq in
          '' | *[!0-9]*) ;;
          *) if [ "$seq" -gt "$after_instance" ]; then after_instance=$seq; fi ;;
        esac
        ;;
    esac
    case $ev in *'"type":"chat.message"'*) ;; *) continue ;; esac
    case $ev in *'"clientId":"'"$client"'"'*) ;; *) continue ;; esac
    case $ev in *'"state":"done"'*) ;; *) continue ;; esac
    case $ev in *'"decision":{'*) ;; *) continue ;; esac
    decision_line=$ev
  done < "$work/events"
}

run_checks() {
  local token fields=() text deadline

  # 1. The status.
  get /ocutalon/public/status "" ""
  if busy_answer || grep -q '"busy":true' "$work/body"; then outcome=busy; return; fi

  # 2. The splash.
  get /ocutalon/ "" "$jar"
  if busy_answer; then outcome=busy; return; fi
  if [ "$rc" != 200 ] || ! grep -qF '<title>Try OcuTalon</title>' "$work/body" || ! grep -q "$form_field" "$work/body"; then
    outcome=no_splash
    return
  fi
  token=$(sed -n 's/.*name="IRISSessionToken" value="\([^"]*\)".*/\1/p' "$work/body" | head -n 1)

  # 3. The sign-in: the password is the only thing that comes on standard input.
  if [ -n "$token" ]; then fields+=(--data-urlencode "IRISSessionToken=$token"); fi
  fields+=(--data-urlencode "IRISUsername=$user" --data-urlencode 'IRISPassword@-' --data-urlencode 'IRISLogin=Sign in')
  : > "$work/head"
  : > "$work/body"
  rc=$(printf '%s' "$password" | curl "${curl_opts[@]}" -b "$jar" -c "$jar" -D "$work/head" -o "$work/body" -w '%{http_code}' \
    -H "Origin: $url" "${fields[@]}" "$url/ocutalon/" 2> /dev/null) || true
  if [ -z "$rc" ]; then rc=000; fi
  if busy_answer; then outcome=busy; return; fi
  case $rc in
    3??)
      get /ocutalon/ "" "$jar"
      if busy_answer; then outcome=busy; return; fi
      ;;
  esac
  if grep -q '<app-root' "$work/body"; then
    signed_in=1
  elif grep -q "$form_field" "$work/body"; then
    outcome=auth_failed
    return
  else
    outcome=no_decision
    return
  fi

  # 4. The message.
  client="probe-$(utc +%Y%m%dT%H%M%SZ)-$$"
  text=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"clientId":"%s","text":"%s","fromGuide":false}' "$client" "$text" > "$work/message.json"
  : > "$work/head"
  : > "$work/body"
  rc=$(curl "${curl_opts[@]}" -b "$jar" -c "$jar" -D "$work/head" -o "$work/body" -w '%{http_code}' -H 'Content-Type: application/json' \
    -H 'X-OcuTalon-Request: 1' -H "Origin: $url" --data-binary "@$work/message.json" "$url/ocutalon/api/v1/messages" 2> /dev/null < /dev/null) || true
  if [ -z "$rc" ]; then rc=000; fi
  if busy_answer; then outcome=busy; return; fi
  if [ "$rc" != 202 ]; then outcome=no_decision; return; fi

  # 5. The decision of the turn.
  after_instance=0
  deadline=$((SECONDS + decision_wait))
  while :; do
    get /ocutalon/api/v1/events "after=0&afterInstance=$after_instance" "$jar"
    if busy_answer; then outcome=busy; return; fi
    if [ "$rc" = 200 ]; then
      scan_events
      if [ -n "$decision_line" ]; then
        fallback=$(printf '%s\n' "$decision_line" | sed 's/"fallbackReason":"/\
@@/g' | sed -n 's/^@@\([A-Za-z0-9_][A-Za-z0-9_]*\)".*/\1/p' | head -n 1)
        case $decision_line in
          *'"fallbackReason":"daily_cap"'*) outcome=capped; fallback=daily_cap ;;
          *) outcome=healthy ;;
        esac
        return
      fi
    elif [ "$rc" != 000 ]; then
      outcome=no_decision
      return
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then break; fi
    sleep 2
  done
  outcome=no_decision
}

# --- the state ---

count_file="$state_dir/counted-failures"
busy_file="$state_dir/busy-per-day"
log_file="$state_dir/probe.log"

# read_count: the count of counted failures; a missing or unreadable value (not a plain whole number) is 0.
read_count() {
  local v
  v=$(head -n 1 "$count_file" 2> /dev/null)
  case $v in '' | *[!0-9]* | ???????* | 0?*) v=0 ;; esac
  printf '%s' "$v"
}

write_count() {
  if printf '%s\n' "$1" > "$count_file.tmp.$$" && mv -f "$count_file.tmp.$$" "$count_file"; then return 0; fi
  rm -f "$count_file.tmp.$$"
  echo "probe: the count of counted failures could not be written" >&2
}

# add_busy: one more busy run on today's (UTC) line of busy-per-day; older days are kept.
add_busy() {
  local day n
  day=$(utc +%Y-%m-%d)
  n=$(sed -n "s/^$day \\([0-9][0-9]*\\)\$/\\1/p" "$busy_file" 2> /dev/null | head -n 1)
  n=${n:-0}
  {
    grep -v "^$day " "$busy_file" 2> /dev/null
    printf '%s %s\n' "$day" "$((n + 1))"
  } > "$busy_file.tmp.$$" && mv -f "$busy_file.tmp.$$" "$busy_file" && return 0
  rm -f "$busy_file.tmp.$$"
  echo "probe: the busy count could not be written" >&2
}

run_checks
signout

count=$(read_count)
case $outcome in
  healthy | capped)
    count=0
    write_count 0
    ;;
  busy) add_busy ;;
  no_splash) ;;
  auth_failed | no_decision)
    count=$((count + 1))
    write_count "$count"
    if [ "$count" -ge 2 ]; then
      "${reset_words[@]}" > /dev/null 2>&1 < /dev/null
      reset_status=$?
      write_count 0
    fi
    ;;
esac

line="$(utc +%Y-%m-%dT%H:%M:%SZ) $outcome count=$count${fallback:+ fallback=$fallback}${reset_status:+ reset=$reset_status}"
if ! printf '%s\n' "$line" >> "$log_file"; then echo "probe: the log line could not be appended" >&2; fi
printf '%s\n' "$line"

case $outcome in
  healthy | capped) exit 0 ;;
esac
"${alert_words[@]}" "$outcome" "$line" > /dev/null 2>&1 < /dev/null
alert_status=$?
if [ "$alert_status" -ne 0 ]; then echo "probe: the alert command did not succeed (exit $alert_status)" >&2; fi
exit 1
