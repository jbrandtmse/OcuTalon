#!/usr/bin/env bash
# Live test of the web bundle's folder (Story 0.5, matrix row 23; DW-5): the bundle is served from the durable
# csp/ocutalon-web/ and nothing of it is served without a sign-in under /csp/ocutalon/, the folder of the default
# application that the non-Health image creates for the namespace (the Health image creates none). Builds the image
# and starts it in one throwaway compose project, then checks (every probe asks a URL of its own, because the web
# gateway keeps the answer to a URL)
#   - after the first start: /csp/ocutalon/index.html and /csp/ocutalon/<main>.js answer 404 with no session;
#   - with OcuTalon's old files seeded into the durable csp/ocutalon/ folder, beside zz-keep.txt and assets/zz/keep.txt,
#     as an upgraded volume would hold them: index.html answers 200 where the default application /csp/ocutalon
#     exists (the exposure that the move closes) and 404 where it does not;
#   - after a restart: both answer 404 on either image, OcuTalon's files are gone from the old folder, the two zz files
#     remain, and, signed in, /ocutalon/ and /ocutalon/<main>.js answer 200, the script equal to the one in
#     csp/ocutalon-web/ byte for byte.
# The project is unique, publishes its web port only on 127.0.0.1 (first free port of 52800-52819, or
# OCUTALON_TEST_WEB_PORT) and receives no keys. An EXIT trap removes the project with its volume and images. Every wait
# ends by an overall deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per probe; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0; the
# non-Health image is iris-community:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t05
live_web_port || exit 1

web=/durable/iris/csp/ocutalon-web
old=/durable/iris/csp/ocutalon
readme_user=ocutalon
readme_password=ocutalon

# host_sha256: the SHA-256 of stdin, with the tool that this host has.
host_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# The web gateway keeps the answer to a URL, a 404 and a 200 alike, also after the file changes (measured October 19).
# So every probe asks a URL that no earlier probe asked, by a counter in the query string, and its answer comes from
# IRIS and not from the gateway.
probes=0

# probe <label> <wanted status> <path> [<cookie jar>]
probe() {
  local url="http://127.0.0.1:$web_port$3" code
  probes=$((probes + 1))
  case $3 in
    *\?*) url="$url&probe=$probes" ;;
    *) url="$url?probe=$probes" ;;
  esac
  if [ -n "${4:-}" ]; then
    code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' -b "$4" "$url")
  else
    code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' "$url")
  fi
  if [ "$code" = "$2" ]; then
    pass "$1: GET $3 answers $2"
  else
    fail "$1: GET $3 answers '$code', wanted $2"
  fi
}

# --- build and start ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready within 400 s"
fi
pass "the first start ended ready"

main=$(dc exec -T iris sh -c "ls $web" | tr -d '\r' | grep -E '^main-[A-Za-z0-9]+\.js$' | head -n 1)
[ -n "$main" ] || die "the bundle holds no main-*.js in $web"
pass "the bundle is in $web, main script $main"

if [ -z "$(container_sha256 "$web/index.html")" ]; then
  die "$web/index.html is missing"
fi
if [ -z "$(container_sha256 "$old/index.html")" ]; then
  pass "the first start leaves no index.html in $old"
else
  fail "the first start left an index.html in $old"
fi

# --- before seeding: nothing is served under /csp/ocutalon/ ---

probe "before seeding" 404 /csp/ocutalon/index.html
probe "before seeding" 404 "/csp/ocutalon/$main"

# --- seeding: the old bundle, as an upgraded volume holds it ---

if dc exec -T iris sh -c "mkdir -p $old/assets/zz && cp -a $web/. $old/ && printf keep > $old/zz-keep.txt && printf keep > $old/assets/zz/keep.txt" >/dev/null 2>&1 \
  && [ -n "$(container_sha256 "$old/index.html")" ] && [ -n "$(container_sha256 "$old/$main")" ] && [ -n "$(container_sha256 "$old/zz-keep.txt")" ]; then
  pass "OcuTalon's files and two zz files are seeded into $old"
else
  die "the old bundle could not be seeded into $old"
fi

# The default application /csp/ocutalon exists on the non-Health image only. Where it does, the seeded files are served
# without a sign-in: the exposure that the move to csp/ocutalon-web/ closes at the next start.
exists=$(printf '%s\n' 'Write !,"CHK|csp-app|",##class(Security.Applications).Exists("/csp/ocutalon")' 'Halt' | session_value %SYS csp-app)
case $exists in
  1) wanted=200; pass "the default application /csp/ocutalon exists on this image (non-Health)" ;;
  0) wanted=404; pass "no default application /csp/ocutalon exists on this image (Health)" ;;
  *) die "the existence of the application /csp/ocutalon could not be read ('$exists')" ;;
esac
probe "seeded, before the restart" "$wanted" /csp/ocutalon/index.html
probe "seeded, before the restart" "$wanted" "/csp/ocutalon/$main"

# --- the restart removes OcuTalon's files from the old folder ---

if ! dc restart iris > "$tmp/restart.log" 2>&1; then
  tail -n 10 "$tmp/restart.log"
  die "the restart failed"
fi
if ! wait_started_ready 200; then
  start_log | tail -n 30 | cut -c1-200
  die "the restart did not end ready within 200 s"
fi
pass "the restart ended ready"

probe "after the restart" 404 /csp/ocutalon/index.html
probe "after the restart" 404 "/csp/ocutalon/$main"
probe "after the restart" 404 /csp/ocutalon/3rdpartylicenses.txt

left=$(dc exec -T iris sh -c "cd $old && find . | sort" | tr -d '\r' | tr '\n' ' ')
if [ "$left" = ". ./assets ./assets/zz ./assets/zz/keep.txt ./zz-keep.txt " ]; then
  pass "$old holds only the two zz files and the folders above them"
else
  fail "$old holds '$left', wanted only ./zz-keep.txt and ./assets/zz/keep.txt"
fi
if [ "$(dc exec -T iris cat "$old/zz-keep.txt" | tr -d '\r')" = keep ] && [ "$(dc exec -T iris cat "$old/assets/zz/keep.txt" | tr -d '\r')" = keep ]; then
  pass "the two zz files keep their content"
else
  fail "a zz file lost its content"
fi
if [ -n "$(container_sha256 "$web/index.html")" ] && [ -n "$(container_sha256 "$web/$main")" ]; then
  pass "the bundle in $web is untouched"
else
  fail "the bundle in $web lost a file"
fi

# --- signed in, the bundle loads from csp/ocutalon-web/ through /ocutalon/ ---

jar="$tmp/jar"
: > "$jar"
curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "http://127.0.0.1:$web_port/ocutalon/"
curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" -d "IRISUsername=$readme_user" -d "IRISPassword=$readme_password" --data-urlencode 'IRISLogin=Sign in' "http://127.0.0.1:$web_port/ocutalon/"
probe "signed in" 200 /ocutalon/ "$jar"
if curl -s --max-time 30 -b "$jar" "http://127.0.0.1:$web_port/ocutalon/" | grep -q '<app-root'; then
  pass "signed in, /ocutalon/ is the application's index.html"
else
  fail "signed in, /ocutalon/ is not the application's index.html"
fi
probe "signed in" 200 "/ocutalon/$main" "$jar"
curl -s --max-time 30 -b "$jar" -o "$tmp/main.js" "http://127.0.0.1:$web_port/ocutalon/$main"
if [ -s "$tmp/main.js" ] && [ "$(host_sha256 < "$tmp/main.js")" = "$(container_sha256 "$web/$main")" ]; then
  pass "signed in, /ocutalon/$main equals $web/$main byte for byte"
else
  fail "signed in, /ocutalon/$main differs from $web/$main"
fi
probe "without a session" 200 "/ocutalon/$main"
if curl -s --max-time 30 "http://127.0.0.1:$web_port/ocutalon/$main" | grep -q 'Sign in to OcuTalon'; then
  pass "without a session, /ocutalon/$main is the sign-in page"
else
  fail "without a session, /ocutalon/$main is not the sign-in page"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-bundle-folder: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-bundle-folder: all checks passed"
