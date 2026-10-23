#!/usr/bin/env bash
# Live test of install.sh (Story 10.1): the real script, in a throwaway compose project, then the manual path the README gives.
# The project is lib-live.sh's (no host port but one on 127.0.0.1, no keys, no restart, a model mock), so the judges' project and the
# shared base image are never touched. The base name of this run is $P-base:<tag> (IRIS_IMAGE), never ocutalon-iris-base:<tag>, and the
# script's Health image is a second name of the shared base's id, $P-src/irishealth-community:<tag>: the test only adds and removes
# its own two names, never an image id and never the shared name.
#   1. $P-src/irishealth-community:<tag> is added on the id of the shared base image.
#   2. The real install.sh runs with COMPOSE_PROJECT_NAME, COMPOSE_FILE and IRIS_IMAGE set for the throwaway project. It must exit 0,
#      name the Health image, give $P-base the shared base's id, print a URL on the published port, and the printed user and password
#      must sign in there (the page's <app-root).
#   3. A second run must print the ready block at once (no progress line), say the base exists, and keep the same container.
#   4. The project goes down without -v, $P-base is removed without -f (the shared name keeps its id), and the README's manual
#      command re-makes it: docker tag <the loaded Health image> <base>.
#   5. A plain docker compose up -d (the same environment, no script) reaches healthy on the same volume (its CreatedAt is unchanged).
# Cleanup: the two $P- names are removed without -f, .env is removed only when this run created it, then lib-live.sh removes the project
# with its volume and images and releases the throwaway lock. The shared base's id is checked at the start, after step 4 and at the end.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose, the base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0) and curl.
set -u

. "$(dirname "$0")/lib-live.sh"
live_start t10
live_web_port || exit 1

TAG=2026.3.0AI.154.0
test_base="$P-base:$TAG"
src_ref="$P-src/irishealth-community:$TAG"
env_created=0

own_cleanup() {
  # Only the two names of this run, and never with -f: a name that is already gone is not an error here.
  docker image rm "$test_base" "$src_ref" >/dev/null 2>&1
  if [ "$env_created" = 1 ]; then rm -f "$root/.env"; fi
}
trap 'own_cleanup; live_cleanup' EXIT

shared_id() { docker image inspect --format '{{.Id}}' "$base_image" 2>/dev/null; }

base_id=$(shared_id)
if [ -z "$base_id" ]; then die "the base image $base_image is not loaded"; fi

compose_files=""
for f in "${LIVE_FILES[@]}"; do compose_files="$compose_files${compose_files:+:}$f"; done

# run_script: runs the real install.sh for this project. Sets script_out and script_rc, and shows the end of the output.
run_script() {
  local left=$((deadline - SECONDS))
  if [ "$left" -gt 900 ]; then left=900; fi
  if [ "$left" -lt 10 ]; then left=10; fi
  script_out=$(env COMPOSE_PROJECT_NAME="$P" COMPOSE_FILE="$compose_files" IRIS_IMAGE="$test_base" OCUTALON_INSTALL_WAIT="$left" \
    bash "$root/install.sh" 2>&1)
  script_rc=$?
  printf '%s\n' "$script_out" | tail -n 25 | sed 's/^/  | /'
}

script_has() { printf '%s\n' "$script_out" | grep -qF -- "$1"; }
progress_lines() { printf '%s\n' "$script_out" | grep -c '^Waiting, '; }
container_id() { dc ps -q iris 2>/dev/null; }
volume_created() { docker volume inspect --format '{{.CreatedAt}}' "${P}_durable" 2>/dev/null; }
plain_healthy() { [ "$(dc ps --all --format '{{.State}} {{.Health}}' iris 2>/dev/null)" = "running healthy" ]; }

# --- 1. the Health image of this run ---

if [ ! -e "$root/.env" ]; then env_created=1; fi
if docker tag "$base_image" "$src_ref"; then
  pass "$src_ref is a second name of the shared base's id"
else
  die "could not tag $src_ref"
fi

# --- 2. the real script ---

run_script
if [ "$script_rc" -eq 0 ]; then pass "install.sh exits 0 and the stack is healthy"; else die "install.sh exited $script_rc"; fi
if script_has "Image: IRIS for Health"; then pass "install.sh names the IRIS for Health image"; else fail "install.sh does not name the IRIS for Health image"; fi
if [ "$(docker image inspect --format '{{.Id}}' "$test_base" 2>/dev/null)" = "$base_id" ]; then
  pass "$test_base holds the shared base's id"
else
  fail "$test_base does not hold the shared base's id"
fi

printed_url=$(printf '%s\n' "$script_out" | sed -n 's/^  Open: *//p' | head -n 1)
printed_user=$(printf '%s\n' "$script_out" | sed -n 's/^  User: *//p' | head -n 1)
printed_password=$(printf '%s\n' "$script_out" | sed -n 's/^  Password: *//p' | head -n 1)
printed_port=${printed_url#http://localhost:}
printed_port=${printed_port%%/*}
if [ "$printed_port" = "$web_port" ]; then
  pass "the printed address is on the published port $web_port"
else
  fail "the printed address '$printed_url' is not on the published port $web_port"
fi

jar="$tmp/jar"
: > "$jar"
curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" "$printed_url"
curl -s --max-time 30 -o /dev/null -c "$jar" -b "$jar" -d "IRISUsername=$printed_user" -d "IRISPassword=$printed_password" --data-urlencode 'IRISLogin=Sign in' "$printed_url"
if curl -s --max-time 30 -b "$jar" "$printed_url" | grep -q '<app-root'; then
  pass "the printed user and password sign in at the printed address"
else
  fail "the printed user and password do not sign in at the printed address"
fi

cid_before=$(container_id)
volume_before=$(volume_created)
if [ -n "$cid_before" ] && [ -n "$volume_before" ]; then
  pass "the iris container and the durable volume exist"
else
  fail "no iris container ('$cid_before') or no durable volume ('$volume_before')"
fi

# --- 3. a rerun ---

run_script
if [ "$script_rc" -eq 0 ]; then pass "the second run exits 0"; else fail "the second run exited $script_rc"; fi
if [ "$(progress_lines)" -eq 0 ] && script_has "OcuTalon is ready after "; then
  pass "the second run prints the ready block at once, with no progress line"
else
  fail "the second run printed $(progress_lines) progress line(s), or no ready block"
fi
if script_has "The existing $test_base is that image"; then
  pass "the second run says the base exists"
else
  fail "the second run does not say the base exists"
fi
cid_after=$(container_id)
if [ "$cid_after" = "$cid_before" ]; then
  pass "the second run keeps the same container"
else
  fail "MEASURED: compose recreated the container on the second up -d (before '$cid_before', after '$cid_after')"
fi

# --- 4. the retag is removed and made again by hand ---

if dc down >/dev/null 2>&1; then pass "the project goes down without -v"; else fail "dc down failed"; fi
if docker image rm "$test_base" >/dev/null 2>&1 && ! docker image inspect --format '{{.Id}}' "$test_base" >/dev/null 2>&1; then
  pass "$test_base is removed without -f"
else
  fail "$test_base could not be removed, or is still there"
fi
if [ "$(shared_id)" = "$base_id" ]; then pass "the shared base keeps its id after the removal"; else die "the shared base's id changed"; fi

if docker tag "$src_ref" "$test_base"; then
  pass "the README's manual command re-makes the base name"
else
  die "the manual docker tag failed"
fi

# --- 5. a plain docker compose up ---

plain_out=$(env COMPOSE_PROJECT_NAME="$P" COMPOSE_FILE="$compose_files" IRIS_IMAGE="$test_base" docker compose up -d 2>&1)
plain_rc=$?
printf '%s\n' "$plain_out" | tail -n 5 | sed 's/^/  | /'
if [ "$plain_rc" -eq 0 ]; then pass "a plain docker compose up -d exits 0"; else fail "a plain docker compose up -d exited $plain_rc"; fi
if wait_until 600 plain_healthy; then
  pass "the plain docker compose up reaches healthy"
else
  fail "the plain docker compose up did not reach healthy"
fi
if [ -n "$volume_before" ] && [ "$(volume_created)" = "$volume_before" ]; then
  pass "it ran on the same volume (CreatedAt is unchanged)"
else
  fail "the durable volume's CreatedAt changed from '$volume_before' to '$(volume_created)'"
fi

if [ "$(shared_id)" = "$base_id" ]; then pass "the shared base keeps its id throughout"; else fail "the shared base's id changed"; fi

if [ "$fails" -ne 0 ]; then
  echo "test-install-script-live: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-install-script-live: all checks passed"
