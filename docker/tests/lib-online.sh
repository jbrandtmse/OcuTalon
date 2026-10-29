# Helpers shared by the live units that start the online demo's real stack with the online-demo flag on and test start values
# (test-online-demo.sh and test-online-session.sh, Story 16.4). Sourced after lib-live.sh, not run: it defines functions and nothing else.
# A unit calls, in this order:
#   live_start <label>, live_web_port         (lib-live.sh)
#   online_values                             sets demo_user, readonly_user, readonly_user_caps, demo_password, readonly_password, anchor and
#                                             last_reset: the passwords are random hex per run, the anchor is two hours ahead of the start
#   base="http://127.0.0.1:$web_port"         the helpers below read base, tmp and the probe counter
#   online_override                           writes the compose override to this run's temporary folder and adds it to the stack; the
#                                             passwords reach compose by ${VAR} interpolation, so they are in no file
# and then uses redact (replaces every password of the run, and the control user's and the resume reference's when the unit sets
# control_password and resume_ref), next_probe (sets probes to a number that no request of this run used, also across subshells: the
# counter lives in a file), logout_all and online_signin. No password is ever printed. Every request that signs in ends with
# ?IRISLogout=end on its application and on /ocutalon/, each with its own cookie jar, so that no form leaves a licence connection held;
# every page request carries a unique probe=<n> query parameter, because the web gateway keeps the answer to a URL (test-bundle-folder.sh).

# hexpw: 32 random hex characters.
hexpw() { LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32; }

# The test values of one run (see the header). The reset anchor is two hours ahead of the unit's start, to the minute (Story 16.8): the
# next reset is the anchor itself, so no real reset or reset-soon period falls inside a run.
online_values() {
  demo_user=DemoVisitor
  readonly_user=TraceReader
  readonly_user_caps=TRACEREADER
  demo_password=$(hexpw)
  readonly_password=$(hexpw)
  anchor=$(node -e 'const t = Math.floor(Date.now() / 60000) * 60000 + 2 * 3600 * 1000; console.log(`${new Date(t).toISOString().slice(0, 19)}Z`);')
  last_reset=2026-10-25T08:00:00Z
  proxy_start=192.0.2.10
  probe_file="$tmp/probe.n"
  echo 0 > "$probe_file"
}

# redact: stdin with every password of the run (and the control user's, and the resume reference, when set) replaced by <redacted>.
redact() {
  local expr="s/$demo_password/<redacted>/g; s/$readonly_password/<redacted>/g"
  if [ -n "${control_password:-}" ]; then expr="$expr; s/$control_password/<redacted>/g"; fi
  if [ -n "${resume_ref:-}" ]; then expr="$expr; s/$resume_ref/<redacted>/g"; fi
  sed "$expr"
}

# online_override: the test start values as a compose override in this run's temporary folder (quoted where compose would otherwise read a
# timestamp), added to the stack. The proxy address is one that no request of the run comes from.
online_override() {
  export OCUTALON_TEST_DEMO_PASSWORD="$demo_password" OCUTALON_TEST_READONLY_PASSWORD="$readonly_password"
  printf '%s\n' \
    'services:' \
    '  iris:' \
    '    environment:' \
    '      OCUTALON_ONLINE_DEMO: "1"' \
    "      OCUTALON_DEMO_USER: $demo_user" \
    '      OCUTALON_DEMO_PASSWORD: ${OCUTALON_TEST_DEMO_PASSWORD}' \
    "      OCUTALON_READONLY_USER: $readonly_user" \
    '      OCUTALON_READONLY_PASSWORD: ${OCUTALON_TEST_READONLY_PASSWORD}' \
    '      OCUTALON_RESET_INTERVAL_HOURS: "4"' \
    "      OCUTALON_RESET_ANCHOR: \"$anchor\"" \
    "      OCUTALON_LAST_RESET: \"$last_reset\"" \
    '      OCUTALON_LAST_RESET_KIND: scheduled' \
    "      OCUTALON_PROXY_ADDRESS: $proxy_start" \
    '      OCUTALON_CONNECTION_CAP: "8"' \
    '      OCUTALON_CONNECTION_RESERVE: "2"' \
    '      OCUTALON_MESSAGE_ALLOWANCE: "50"' \
    '      OCUTALON_DAILY_COST_CAP_USD: "20"' > "$tmp/online-demo.yml"
  live_add_file "$tmp/online-demo.yml"
}

# next_probe sets probes to a number that no request of this run used, also across the subshells of $(...): the counter lives in a file.
next_probe() {
  probes=$(($(cat "$probe_file") + 1))
  echo "$probes" > "$probe_file"
}

# logout_all <jar> <application path>: ends the session of the jar on the application and on /ocutalon/, each with a unique probe.
logout_all() {
  next_probe
  curl -s --max-time 30 -o /dev/null -b "$1" -c "$1" "$base$2?IRISLogout=end&probe=$probes"
  next_probe
  curl -s --max-time 30 -o /dev/null -b "$1" -c "$1" "$base/ocutalon/?IRISLogout=end&probe=$probes"
}

# online_signin <jar> <forwarded address or ""> <resume cookie value or ""> [<user> <password>]: the splash GET and the sign-in POST of the
# account (by default the demo account) on the jar, with X-Forwarded-For when an address is given and the resume cookie when a value is
# given. It prints the POST's HTTP status, and leaves the POST's headers in <jar>.h, the final page in <jar>.b and, after a redirect, the
# first /ocutalon/ GET's headers in <jar>.g.
online_signin() {
  local jar=$1 forwarded=$2 cookie=$3 user=${4-$demo_user} password=${5-$demo_password} code
  local args=(-s --max-time 30 -c "$jar" -b "$jar")
  if [ -n "$forwarded" ]; then args+=(-H "X-Forwarded-For: $forwarded"); fi
  if [ -n "$cookie" ]; then args+=(-b "OcuTalonResume=$cookie"); fi
  rm -f "$jar.h" "$jar.g" "$jar.b"
  next_probe
  curl "${args[@]}" -o /dev/null "$base/ocutalon/?probe=$probes"
  next_probe
  code=$(curl "${args[@]}" -D "$jar.h" -o "$jar.b" -w '%{http_code}' --data-urlencode "IRISUsername=$user" --data-urlencode "IRISPassword=$password" \
    --data-urlencode 'IRISLogin=Sign in' "$base/ocutalon/?probe=$probes")
  case $code in
    3??)
      next_probe
      curl "${args[@]}" -D "$jar.g" -o "$jar.b" "$base/ocutalon/?probe=$probes"
      ;;
  esac
  printf '%s' "$code"
}
