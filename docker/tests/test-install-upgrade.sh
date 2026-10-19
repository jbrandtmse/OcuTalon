#!/usr/bin/env bash
# Live test of the upgrade at start (matrix rows 6 and 7, and Story 0.3's row 15): builds the image and starts it in one throwaway
# compose project, then recreates the container from images whose version is raised by a patch number
#   - row 6, an upgrade in place: the installed version and the marker equal the new version, every step
#     runs again, and the probes written under the old version are intact; the README account keeps the password
#     that was set by hand, with its flags, the durable index.html is the new image's, and the roles, the account
#     and the three web applications are still as the first start made them (Story 0.3, row 15);
#   - row 7, a step that fails: an image whose SSL step returns an error. The log names SSL as failed and no
#     later step ran, there is no marker and readiness is empty, the container keeps running without a
#     restart and Docker never reports healthy. The next good image reaches ready.
# The upgrade images are built from a copy of the build context in a temporary directory, through an override
# that names it, so the working tree is never changed. The project is unique, publishes no host port and
# receives no keys. An EXIT trap removes the project with its volume and images. Every wait ends by an overall
# deadline, so even a failing run ends within about 9 minutes.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t02u

v0=$(manifest_version src/module.xml)
ipm_version=0.10.10

# make_image_context <directory> <version> [broken]: the build context of the working tree with the manifest's
# first <Version> replaced, and, when asked, with an SSL step that returns an error.
make_image_context() {
  copy_build_context "$1"
  awk -v v="$2" '!done && /<Version>/ { sub(/<Version>[^<]*<\/Version>/, "<Version>" v "</Version>"); done = 1 } { print }' \
    src/module.xml > "$1/src/module.xml"
  # The bundle of each image differs, so that the durable copy must follow the upgrade.
  printf '<!-- %s -->\n' "$2" >> "$1/src/ocutalon/csp/index.html"
  if [ "${3:-}" = broken ]; then
    cat > "$1/src/ocutalon/cls/OcuTalon/Install/Step/SSL.cls" <<'EOS'
Class OcuTalon.Install.Step.SSL Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.Error(5001, "SSL failed on purpose")
}

}
EOS
  fi
}

# use_image_context <directory>: the next `up --build` builds from that directory.
use_image_context() {
  printf 'services:\n  iris:\n    build:\n      context: %s\n      dockerfile: docker/Dockerfile\n' "$1" > "$tmp/context.yml"
  if [ "${#LIVE_FILES[@]}" -gt 3 ]; then live_pop_file; fi
  live_add_file "$tmp/context.yml"
}

# recreate_with <directory>: builds the image from the directory and recreates the container from it.
recreate_with() {
  use_image_context "$1"
  if ! dc up -d --build > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    die "the build or recreate from $1 failed"
  fi
  live_track_image
  cid=$(dc ps -q iris)
  [ -n "$cid" ] || die "no iris container in project $P"
}

# check_installed <label> <version>: the installed package, the marker and readiness all hold the version.
check_installed() {
  local label=$1 want=$2
  if [ "$(marker)" = "$want" ]; then
    pass "$label: the marker equals $want"
  else
    fail "$label: the marker is '$(marker)', wanted $want"
  fi
  if [ "$(dc exec -T iris cat /opt/ocutalon/version 2>/dev/null | tr -d '\r\n')" = "$want" ]; then
    pass "$label: the image's version file says $want"
  else
    fail "$label: the image's version file does not say $want"
  fi
  check_session "$label: installed package and readiness" OCUTALON "CHK|package|$want
CHK|ready|1" \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|package|",$Select($IsObject(m):m.VersionString,1:"")' \
    'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
    'Halt'
}

# --- the first start, from the working tree's version ---

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the first start did not end ready within 400 s"
fi
check_installed "first start" "$v0"
set_probes
check_probes "under $v0"

# A digest of the README account's password hash, salt and flags: it changes when any of them does, and it is not
# the hash itself.
readme_fingerprint() {
  printf '%s\n' \
    'If ##class(Security.Users).Exists("ocutalon",.u) { Set s=u.Password_"|"_u.Salt_"|"_u.Enabled_"|"_u.ChangePassword_"|"_u.PasswordNeverExpires_"|"_u.AccountNeverExpires Write !,"CHK|fp|",$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256,s)) } Else { Write !,"CHK|fp|<missing>" }' \
    'Halt' | session_value %SYS fp
}

# --- row 15 (part 1): the README account's password is changed by hand under the first version ---

fingerprint_first=$(readme_fingerprint)
changed=$(printf '%s\n' \
  'Kill p Set p("Password")="Zz-changed-by-hand-1"' \
  'Write !,"CHK|changed|",##class(Security.Users).Modify("ocutalon",.p)' \
  'Halt' | session_value %SYS changed)
fingerprint_changed=$(readme_fingerprint)
if [ "$changed" = 1 ] && [ -n "$fingerprint_first" ] && [ "$fingerprint_first" != "<missing>" ] \
  && [ -n "$fingerprint_changed" ] && [ "$fingerprint_changed" != "<missing>" ] && [ "$fingerprint_changed" != "$fingerprint_first" ]; then
  pass "row 15: the README account's password was changed by hand under $v0"
else
  fail "row 15: the README account's password could not be changed ('$changed')"
fi
index_first=$(container_sha256 /durable/iris/csp/ocutalon/index.html)

# The roles and the web applications are structural (AD-19): a hand change to one of each is put back by the upgrade.
drifted=$(printf '%s\n' \
  'Kill p Set p("Timeout")=100,p("CorsAllowlist")="https://zz.example.com"' \
  'Write !,"CHK|app|",##class(Security.Applications).Modify("/ocutalon/api",.p)' \
  'Kill r Set r("Resources")=""' \
  'Write !,"CHK|role|",##class(Security.Roles).Modify("OcuTalonTraceViewer",.r)' \
  'Halt' | iris_script %SYS | sed -nE 's/^CHK\|(app|role)\|//p' | tr '\n' ' ')
if [ "$drifted" = "1 1 " ]; then
  pass "row 15: an application and the trace role were changed by hand under $v0"
else
  fail "row 15: the application and the trace role could not be changed by hand ('$drifted')"
fi

# --- row 6: an upgrade in place ---

v1=$(bump_patch "$v0" 1)
make_image_context "$tmp/ctx-v1" "$v1"
recreate_with "$tmp/ctx-v1"
if ! wait_started_ready 200; then
  start_log | tail -n 30 | cut -c1-200
  die "row 6 the upgrade did not end ready within 200 s"
fi
expected_run "cleared" "present $ipm_version" "already mapped" "ok" "loaded (version $v0 to $v1)" "$v1" > "$tmp/expected.row6"
check_log "row 6" "$tmp/expected.row6"
check_installed "row 6" "$v1"
check_probes "row 6 after the upgrade"
if [ "$(health_status)" = healthy ] && [ "$(restart_count)" = 0 ]; then
  pass "row 6: Docker reports healthy, with no restart"
else
  fail "row 6: Docker reports '$(health_status)' after $(restart_count) restart(s), wanted healthy and 0"
fi

# --- row 15 (part 2): the account is as the hand left it, the bundle follows the upgrade, rows 1 and 2 hold again ---

if [ -n "$fingerprint_changed" ] && [ "$(readme_fingerprint)" = "$fingerprint_changed" ]; then
  pass "row 15: the README account's password hash, salt and flags are unchanged by the upgrade"
else
  fail "row 15: the upgrade changed the README account"
fi
index_now=$(container_sha256 /durable/iris/csp/ocutalon/index.html)
if [ -n "$index_now" ] && [ "$index_now" = "$(container_sha256 /opt/ocutalon/src/ocutalon/csp/index.html)" ] && [ "$index_now" != "$index_first" ]; then
  pass "row 15: the durable index.html is the new image's, and not the first version's"
else
  fail "row 15: the durable index.html does not equal the new image's, or did not change"
fi
check_security "row 15 after the upgrade"

# --- row 7: a step fails ---

v2=$(bump_patch "$v1" 1)
make_image_context "$tmp/ctx-v2" "$v2" broken
recreate_with "$tmp/ctx-v2"
if ! wait_started_log 200; then
  start_log | tail -n 30 | cut -c1-200
  die "row 7 the start with a failing step did not end within 200 s"
fi
log_steps > "$tmp/actual.row7"
if grep -q '^STEP SSL FAILED ' "$tmp/actual.row7"; then
  pass "row 7: the log names SSL as failed"
else
  fail "row 7: the log does not name SSL as failed"
fi
if [ "$(sed -n '/^STEP SSL FAILED /,$p' "$tmp/actual.row7" | grep -cE '^STEP (Tasks|Demo|Provider|Audit|Telegram|Production|Reconcile|PrivateData|Ready) ')" = 0 ] \
  && grep -q '^STEP Bridge.Installer OK$' "$tmp/actual.row7" && grep -q '^STEP Web OK$' "$tmp/actual.row7"; then
  pass "row 7: the steps before SSL ran and none after it"
else
  fail "row 7: the steps around SSL are wrong"
fi
if ! grep -q '^RESULT OK ' "$tmp/actual.row7"; then
  pass "row 7: the log has no RESULT OK line"
else
  fail "row 7: the log has a RESULT OK line"
fi
if [ -z "$(marker)" ]; then
  pass "row 7: there is no marker"
else
  fail "row 7: the marker holds '$(marker)'"
fi
check_session "row 7: readiness is empty" OCUTALON "CHK|ready|" \
  'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' 'Halt'
if [ "$(docker inspect --format '{{.State.Running}}' "$cid" 2>/dev/null)" = true ] && [ "$(restart_count)" = 0 ]; then
  pass "row 7: the container is running with RestartCount 0"
else
  fail "row 7: the container is not running, or restarted (RestartCount '$(restart_count)')"
fi
# Docker's monitor keeps reporting `starting` while the marker is missing: watch it for 40 s.
healthy_seen=0
watched=0
while [ "$watched" -lt 40 ] && [ "$SECONDS" -lt "$deadline" ]; do
  if [ "$(health_status)" = healthy ]; then healthy_seen=1; fi
  sleep 4
  watched=$((watched + 4))
done
if [ "$healthy_seen" -eq 0 ] && [ "$watched" -ge 40 ] && [ "$(health_status)" = starting ]; then
  pass "row 7: Docker never reported healthy (status '$(health_status)' after $watched s)"
else
  fail "row 7: Docker reported healthy, the watch ended early ($watched s), or the status is '$(health_status)'"
fi

# The next good image reaches ready.
v3=$(bump_patch "$v1" 2)
make_image_context "$tmp/ctx-v3" "$v3"
recreate_with "$tmp/ctx-v3"
if ! wait_started_ready 200; then
  start_log | tail -n 30 | cut -c1-200
  die "row 7 the next good image did not end ready within 200 s"
fi
check_installed "row 7 the next good image" "$v3"
check_probes "row 7 after the next good image"

if [ "$fails" -ne 0 ]; then
  echo "test-install-upgrade: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-install-upgrade: all checks passed"
