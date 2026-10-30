# Helpers shared by the live units that start the online demo's real stack with the online-demo flag on and test start values
# (test-online-demo.sh, test-online-session.sh and test-online-allowance.sh, Stories 16.4 and 16.9). Sourced, not run: it defines
# functions and a few constants and nothing else. The stack helpers need lib-live.sh sourced first; keys_point and keys_restore point the
# runners' model keys at the CI mock, and back. The password-change forms and the host check's probes, at the end of this file
# (Story 29.3), need no stack and no lib-live.sh: the live unit, test-online-host.sh and release/demo-host-check.sh all source them here.
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

# keys_point: points the model keys of the three runners at the mock key variable (Test.Agent.RunnerFixture, which exists in throwaways and
# CI only: a start in the CI override has no key, so every decision would be the no_key fallback) and waits until the runners have recorded
# it; prints 1 when they have. keys_restore puts the entries back to the Provider step's placeholder and prints 1 when they read as that.
keys_point() {
  printf '%s\n' 'Set ok=0 Set fixture="OcuTalon.Test.Agent.RunnerFixture"' \
    'If $ClassMethod(fixture,"GuardReason")="" { Set sc=$ClassMethod(fixture,"PointKeys") Set ok=$SYSTEM.Status.IsOK(sc) If ok Set ok=$ClassMethod(fixture,"WaitRecords") }' \
    'Write !,"CHK|keys|",ok' 'Halt' | session_value OCUTALON keys
}
keys_restore() {
  printf '%s\n' 'Set fixture="OcuTalon.Test.Agent.RunnerFixture" Set sc=$ClassMethod(fixture,"RestoreKeys")' \
    'Write !,"CHK|keys|",$SYSTEM.Status.IsOK(sc)&&$ClassMethod(fixture,"KeysAre",##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER)' 'Halt' | session_value OCUTALON keys
}

# --- the password-change forms and the host check's refusal probes (Story 29.3) ---
# test-online-demo.sh (against real IRIS), test-online-host.sh (against a stand-in) and release/demo-host-check.sh (against a host) all
# take the S17 forms and the refusal probes from here. These functions need nothing of lib-live.sh.

# HOST_FORM_FIELD_RE: an IRIS sign-in or password-change form field in a page (extended regular expression).
HOST_FORM_FIELD_RE='name="?(IRISPassword|IRISOldPassword)'

# The dummy values of the host check's requests: no real account, password or token.
HOST_DUMMY_USER=zz-host-check
HOST_DUMMY_OLD=dummy-old
HOST_DUMMY_NEW=dummy-new
HOST_DUMMY_TOKEN=dummy-token

# host_broker_file: the path of the static /csp/broker/ file that the host check reads, one that IRIS's trace pages load (Task 0 (b)).
host_broker_file() { printf '%s' '/csp/broker/images/cut.png'; }

# host_trace_signin_marker: a text that IRIS's own sign-in page of a trace application holds: its Login form (Task 0 (c)). With a dummy
# session token IRIS answers the four-field POST with that same page, the typed user name not put back, which a plain GET gives too: the
# page shows that the POST reached IRIS, not that IRIS refused it. A proxy's block holds no such form.
host_trace_signin_marker() { printf '%s' '<form name="Login" method="post"'; }

# host_app <target>: the IRIS application whose session an answer to the target can open, where its sign-out (?IRISLogout=end) goes.
host_app() {
  case $1 in
    /ocutalon/trace/ocutalon/*) printf '%s' /ocutalon/trace/ocutalon/ ;;
    /ocutalon/trace/ocuorders/*) printf '%s' /ocutalon/trace/ocuorders/ ;;
    /ocutalon/api/*) printf '%s' /ocutalon/api/ ;;
    *) printf '%s' /ocutalon/ ;;
  esac
}

# pct <text>: every byte of the text as %XX.
pct() {
  local s=$1 out="" i
  for ((i = 0; i < ${#s}; i++)); do
    out="$out$(printf '%%%02X' "'${s:i:1}")"
  done
  printf '%s' "$out"
}

# password_form <F1..F12> <user> <old> <new> [<token>]: the S17 form for the three values (and a trace sign-in page's session token for
# F1 and F3, when one is given). Sets form_method (GET or POST), form_query (text for the request's query string, empty when none) and
# the array form_args (curl arguments, empty for F7; expand it as ${form_args[@]+"${form_args[@]}"} under set -u on bash 3.2), and nothing else. The values must need no URL encoding where they land in a query string or a
# raw body (F5 to F7, F10, F11): hex or the dummy values of the host check. F1 to F4 are urlencoded, F5 posts nothing, F6 and F7 name
# the fields percent-encoded, F8 and F9 are multipart, F10 is chunked, F11 has the names in mixed case and a repeat password, and F12
# is the password-change page's own form, which always carries the page's session token.
password_form() {
  local form=$1 user=$2 old=$3 new=$4 token=${5-} u o p l plain
  case $form in
    F2 | F4 | F9) u=CacheUserName o=CacheOldPassword p=CachePassword l=CacheLogin ;;
    F11) u=irisusername o=IrisOldPassword p=irispassword l=irislogin ;;
    *) u=IRISUsername o=IRISOldPassword p=IRISPassword l=IRISLogin ;;
  esac
  plain="$u=$user&$o=$old&$p=$new&$l=Sign+in"
  form_method=POST
  form_query=
  form_args=()
  case $form in
    F1 | F2) form_args=(${token:+--data-urlencode IRISSessionToken=$token} --data-urlencode "$u=$user" --data-urlencode "$o=$old" --data-urlencode "$p=$new" --data-urlencode "$l=Sign in") ;;
    F3 | F4)
      form_method=GET
      form_args=(-G ${token:+--data-urlencode IRISSessionToken=$token} --data-urlencode "$u=$user" --data-urlencode "$o=$old" --data-urlencode "$p=$new" --data-urlencode "$l=Sign in")
      ;;
    F5)
      form_args=(--data-binary '')
      form_query=$plain
      ;;
    F6) form_args=(--data-raw "IRISUsername=$user&IRIS$(pct OldPassword)=$old&IRIS$(pct Password)=$new&IRISLogin=Sign+in") ;;
    F7)
      form_method=GET
      form_query="IRISUsername=$user&IRIS$(pct OldPassword)=$old&IRIS$(pct Password)=$new&IRISLogin=Sign+in"
      ;;
    F8 | F9) form_args=(-F "$u=$user" -F "$o=$old" -F "$p=$new" -F "$l=Sign in") ;;
    F10) form_args=(-H 'Transfer-Encoding: chunked' --data-raw "$plain") ;;
    F11) form_args=(--data-raw "$plain&IRISRepeatPassword=$new") ;;
    F12)
      form_args=(--data-urlencode "IRISSessionToken=$token" --data-urlencode "IRISUsername=$user" --data-urlencode "IRISOldPassword=$old"
        --data-urlencode "IRISPassword=$new" --data-urlencode "IRISRepeatPassword=$new" --data-urlencode 'IRISLogin=Login')
      ;;
    *) return 1 ;;
  esac
}

# host_probes: the refusal probes of the host check, one line each: <id> <iris> <method> <target> [<body>].
#   <iris>    IRIS's own answer to the probe signed out with no proxy: <status>:form when the page holds an IRIS form field
#             (HOST_FORM_FIELD_RE) and <status>:noform when not. Measured on build 154 by the Story 29.3 section of test-online-demo.sh,
#             which pins every line, so that a build that answers differently turns that unit red.
#   <target>  the path and query as sent (curl --path-as-is).
#   <body>    a password_form form (F1 to F11), or case (a body whose names are in mixed case only, so that no name has the canonical
#             case), extra (a sign-in body with one more name), big (a sign-in body of more than 64 KiB), query
#             (IRISPassword in the query string), api (a urlencoded body for the JSON API) or F12 (the password-change page's own form).
host_probes() {
  cat << 'PROBES'
block-csp-sys 404:noform GET /csp/sys/
block-csp-user 404:noform GET /csp/user/
block-api-mgmnt 401:noform GET /api/mgmnt/
block-api-monitor 200:noform GET /api/monitor/metrics
block-api-atelier 401:noform GET /api/atelier/
block-ui 404:noform GET /ui/
block-mcp 404:noform GET /mcp/
block-mcp-ocutalon 404:noform GET /mcp/ocutalon
block-hook 200:form GET /ocutalon/hook
block-dotdot 404:noform GET /ocutalon/../csp/sys/
block-pw-trace-ocutalon-canon 200:form GET /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls
block-pw-trace-ocutalon-lower 200:form GET /ocutalon/trace/ocutalon/%25csp.passwordchange.cls
block-pw-trace-ocutalon-upper 200:form GET /ocutalon/trace/ocutalon/%25CSP.PASSWORDCHANGE.CLS
block-pw-trace-ocutalon-mixed 200:form GET /ocutalon/trace/ocutalon/%25CsP.PaSsWoRdChAnGe.cls
block-pw-trace-ocutalon-c43 200:form GET /ocutalon/trace/ocutalon/%25%43SP.PasswordChange.cls
block-pw-trace-ocutalon-c43h 200:form GET /ocutalon/trace/ocutalon/%25%43SP.Password%43hange.cls
block-pw-trace-ocutalon-double 200:form GET /ocutalon/trace/ocutalon/%2525CSP.PasswordChange.cls
block-pw-trace-ocuorders-canon 200:form GET /ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls
block-pw-trace-ocuorders-lower 200:form GET /ocutalon/trace/ocuorders/%25csp.passwordchange.cls
block-pw-trace-ocuorders-upper 200:form GET /ocutalon/trace/ocuorders/%25CSP.PASSWORDCHANGE.CLS
block-pw-trace-ocuorders-mixed 200:form GET /ocutalon/trace/ocuorders/%25CsP.PaSsWoRdChAnGe.cls
block-pw-trace-ocuorders-c43 200:form GET /ocutalon/trace/ocuorders/%25%43SP.PasswordChange.cls
block-pw-trace-ocuorders-c43h 200:form GET /ocutalon/trace/ocuorders/%25%43SP.Password%43hange.cls
block-pw-trace-ocuorders-double 200:form GET /ocutalon/trace/ocuorders/%2525CSP.PasswordChange.cls
block-pw-root-canon 200:form GET /ocutalon/%25CSP.PasswordChange.cls
block-pw-root-lower 200:form GET /ocutalon/%25csp.passwordchange.cls
block-pw-root-upper 200:form GET /ocutalon/%25CSP.PASSWORDCHANGE.CLS
block-pw-root-mixed 200:form GET /ocutalon/%25CsP.PaSsWoRdChAnGe.cls
block-pw-root-c43 200:form GET /ocutalon/%25%43SP.PasswordChange.cls
block-pw-root-c43h 200:form GET /ocutalon/%25%43SP.Password%43hange.cls
block-pw-root-double 200:form GET /ocutalon/%2525CSP.PasswordChange.cls
block-pw-api-canon 401:noform GET /ocutalon/api/%25CSP.PasswordChange.cls
block-pw-api-lower 401:noform GET /ocutalon/api/%25csp.passwordchange.cls
block-pw-api-upper 401:noform GET /ocutalon/api/%25CSP.PASSWORDCHANGE.CLS
block-pw-api-mixed 401:noform GET /ocutalon/api/%25CsP.PaSsWoRdChAnGe.cls
block-pw-api-c43 401:noform GET /ocutalon/api/%25%43SP.PasswordChange.cls
block-pw-api-c43h 401:noform GET /ocutalon/api/%25%43SP.Password%43hange.cls
block-pw-api-double 401:noform GET /ocutalon/api/%2525CSP.PasswordChange.cls
block-pw-public-canon 404:noform GET /ocutalon/public/%25CSP.PasswordChange.cls
block-pw-public-lower 404:noform GET /ocutalon/public/%25csp.passwordchange.cls
block-pw-public-upper 404:noform GET /ocutalon/public/%25CSP.PASSWORDCHANGE.CLS
block-pw-public-mixed 404:noform GET /ocutalon/public/%25CsP.PaSsWoRdChAnGe.cls
block-pw-public-c43 404:noform GET /ocutalon/public/%25%43SP.PasswordChange.cls
block-pw-public-c43h 404:noform GET /ocutalon/public/%25%43SP.Password%43hange.cls
block-pw-public-double 404:noform GET /ocutalon/public/%2525CSP.PasswordChange.cls
block-pw-broker-canon 404:noform GET /csp/broker/%25CSP.PasswordChange.cls
block-pw-broker-lower 404:noform GET /csp/broker/%25csp.passwordchange.cls
block-pw-broker-upper 404:noform GET /csp/broker/%25CSP.PASSWORDCHANGE.CLS
block-pw-broker-mixed 404:noform GET /csp/broker/%25CsP.PaSsWoRdChAnGe.cls
block-pw-broker-c43 404:noform GET /csp/broker/%25%43SP.PasswordChange.cls
block-pw-broker-c43h 404:noform GET /csp/broker/%25%43SP.Password%43hange.cls
block-pw-broker-double 404:noform GET /csp/broker/%2525CSP.PasswordChange.cls
block-pw-trace-ocutalon-canon-q 200:form GET /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls?x=1
block-pw-trace-ocutalon-lower-q 200:form GET /ocutalon/trace/ocutalon/%25csp.passwordchange.cls?x=1
block-pw-trace-ocutalon-upper-q 200:form GET /ocutalon/trace/ocutalon/%25CSP.PASSWORDCHANGE.CLS?x=1
block-pw-trace-ocutalon-mixed-q 200:form GET /ocutalon/trace/ocutalon/%25CsP.PaSsWoRdChAnGe.cls?x=1
block-pw-trace-ocutalon-c43-q 200:form GET /ocutalon/trace/ocutalon/%25%43SP.PasswordChange.cls?x=1
block-pw-trace-ocutalon-c43h-q 200:form GET /ocutalon/trace/ocutalon/%25%43SP.Password%43hange.cls?x=1
block-pw-trace-ocutalon-double-q 200:form GET /ocutalon/trace/ocutalon/%2525CSP.PasswordChange.cls?x=1
block-pw-trace-ocuorders-canon-q 200:form GET /ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls?x=1
block-pw-trace-ocuorders-lower-q 200:form GET /ocutalon/trace/ocuorders/%25csp.passwordchange.cls?x=1
block-pw-trace-ocuorders-upper-q 200:form GET /ocutalon/trace/ocuorders/%25CSP.PASSWORDCHANGE.CLS?x=1
block-pw-trace-ocuorders-mixed-q 200:form GET /ocutalon/trace/ocuorders/%25CsP.PaSsWoRdChAnGe.cls?x=1
block-pw-trace-ocuorders-c43-q 200:form GET /ocutalon/trace/ocuorders/%25%43SP.PasswordChange.cls?x=1
block-pw-trace-ocuorders-c43h-q 200:form GET /ocutalon/trace/ocuorders/%25%43SP.Password%43hange.cls?x=1
block-pw-trace-ocuorders-double-q 200:form GET /ocutalon/trace/ocuorders/%2525CSP.PasswordChange.cls?x=1
guard-F1 200:form POST /ocutalon/ F1
guard-F1-state 401:noform POST /ocutalon/api/v1/state F1
guard-F1-trace-ocutalon 200:form POST /ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen F1
guard-F1-trace-ocuorders 200:form POST /ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen F1
guard-F2 200:form POST /ocutalon/ F2
guard-F3 200:form GET /ocutalon/ F3
guard-F3-state 401:noform GET /ocutalon/api/v1/state F3
guard-F3-trace-ocutalon 200:form GET /ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen F3
guard-F3-trace-ocuorders 200:form GET /ocutalon/trace/ocuorders/EnsPortal.MessageViewer.zen F3
guard-F4 200:form GET /ocutalon/ F4
guard-F5 200:form POST /ocutalon/ F5
guard-F6 200:form POST /ocutalon/ F6
guard-F7 200:form GET /ocutalon/ F7
guard-F8 200:form POST /ocutalon/ F8
guard-F9 200:form POST /ocutalon/ F9
guard-F10 200:form POST /ocutalon/ F10
guard-F11 200:form POST /ocutalon/ F11
guard-case 200:form POST /ocutalon/ case
guard-F12-trace-ocutalon 200:form POST /ocutalon/trace/ocutalon/%25CSP.PasswordChange.cls F12
guard-F12-trace-ocuorders 200:form POST /ocutalon/trace/ocuorders/%25CSP.PasswordChange.cls F12
guard-extra 200:form POST /ocutalon/ extra
guard-big 200:form POST /ocutalon/ big
guard-query 200:form GET /ocutalon/ query
guard-api 401:noform POST /ocutalon/api/v1/messages api
PROBES
}

# host_probe_args <line of host_probes>: sets probe_id, probe_iris, probe_method, probe_target (the path and query as sent, a body's
# query text included) and the array probe_args (curl arguments for the body) for one probe. F1 and F3 at a trace application, and
# F12, carry the dummy session token. Returns 1 for a form it does not know, and for a line whose method is not the one its body is sent
# with (GET for none and query, POST for the other bodies).
host_probe_args() {
  local target body="" token="" pad want=POST
  read -r probe_id probe_iris probe_method target body <<< "$1"
  probe_args=()
  form_query=
  case $body in
    '') want=GET ;;
    case) probe_args=(--data-raw "irisusername=$HOST_DUMMY_USER&IrisOldPassword=$HOST_DUMMY_OLD&irispassword=$HOST_DUMMY_NEW&irislogin=Sign+in") ;;
    extra) probe_args=(--data-raw "IRISUsername=$HOST_DUMMY_USER&IRISPassword=$HOST_DUMMY_OLD&IRISLogin=Sign+in&x=1") ;;
    big)
      pad=$(head -c 66000 /dev/zero | tr '\0' a)
      probe_args=(--data-raw "IRISUsername=$HOST_DUMMY_USER&IRISPassword=$pad&IRISLogin=Sign+in")
      ;;
    query)
      want=GET
      form_query="IRISPassword=$HOST_DUMMY_NEW"
      ;;
    api) probe_args=(--data-raw "text=$HOST_DUMMY_USER&IRISPassword=$HOST_DUMMY_NEW") ;;
    *)
      case $body in
        F1 | F3) case $target in /ocutalon/trace/*) token=$HOST_DUMMY_TOKEN ;; esac ;;
        F12) token=$HOST_DUMMY_TOKEN ;;
      esac
      password_form "$body" "$HOST_DUMMY_USER" "$HOST_DUMMY_OLD" "$HOST_DUMMY_NEW" "$token" || return 1
      want=$form_method
      probe_args=(${form_args[@]+"${form_args[@]}"})
      ;;
  esac
  [ "$want" = "$probe_method" ] || return 1
  probe_target=$target
  if [ -n "$form_query" ]; then
    case $target in
      *\?*) probe_target="$target&$form_query" ;;
      *) probe_target="$target?$form_query" ;;
    esac
  fi
}

# host_signin <3|4>: the dummy-value sign-in POSTs of the guard checks (DW-226): 3 is the splash's three-field form (IRISUsername,
# IRISPassword, and IRISLogin with the splash's own button value) to /ocutalon/ and 4 is IRIS's trace sign-in page's four-field form (with
# IRISSessionToken) to a trace application. Sets signin_target and the array signin_args (curl arguments). Neither is a real sign-in: the
# user, password and token are the dummy values.
host_signin() {
  case $1 in
    3)
      signin_target=/ocutalon/
      signin_args=(--data-urlencode "IRISUsername=$HOST_DUMMY_USER" --data-urlencode "IRISPassword=$HOST_DUMMY_OLD" --data-urlencode 'IRISLogin=Sign in and start')
      ;;
    4)
      signin_target=/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen
      signin_args=(--data-urlencode "IRISSessionToken=$HOST_DUMMY_TOKEN" --data-urlencode "IRISUsername=$HOST_DUMMY_USER" --data-urlencode "IRISPassword=$HOST_DUMMY_OLD"
        --data-urlencode 'IRISLogin=Login')
      ;;
    *) return 1 ;;
  esac
}
