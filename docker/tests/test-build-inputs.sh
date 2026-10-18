#!/usr/bin/env bash
# Build inputs of the image, observed through Docker. Starts no container.
#   - .dockerignore: from a tree that holds a decoy of everything the repository root can hold
#     (.env, irislib/, irissys/, .git, ...), the build context carries exactly the files that
#     docker/Dockerfile copies;
#   - IRIS_IMAGE: the image named in the environment of `docker compose build` is the image that
#     docker/Dockerfile builds FROM (checked by a label that only that base carries).
# Needs the docker daemon with BuildKit and the base image ocutalon-iris-base:2026.3.0AI.154.0 (or IRIS_IMAGE).
# Creates and removes its own files and images. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

P="ocutalon-t01-bi-$(date +%s)-$$"
base_image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
fails=0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bi.XXXXXX") || exit 1

cleanup() {
  docker image rm -f "$P-iris" "$P-base" >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

# --- .dockerignore ---

# The sources of the Dockerfile's COPY lines are what the context must carry.
copied=$(awk '$1 == "COPY" { for (i = 2; i < NF; i++) if ($i !~ /^--/) print $i }' docker/Dockerfile | sort)

ctx="$tmp/context"
mkdir -p "$ctx/docker/tests" "$ctx/src" "$ctx/irislib" "$ctx/irissys" "$ctx/.git" "$ctx/_bmad-output"
cp .dockerignore "$ctx/.dockerignore"
if [ -f docker/Dockerfile.dockerignore ]; then
  cp docker/Dockerfile.dockerignore "$ctx/docker/Dockerfile.dockerignore"
fi
for f in .env .env.local .env.example docker-compose.yml README.md docker/tests/test-x.sh docker/other.sh \
  irislib/x irissys/x .git/config _bmad-output/x src/other.xml $copied; do
  echo decoy > "$ctx/$f"
done
# The probe takes the Dockerfile's place, so that the ignore file that applies to docker/Dockerfile applies to it.
printf 'FROM scratch\nCOPY . /ctx\n' > "$ctx/docker/Dockerfile"

if [ -z "$copied" ]; then
  fail "dockerignore: docker/Dockerfile has no COPY source to expect"
elif docker build -f "$ctx/docker/Dockerfile" -o "type=local,dest=$tmp/out" "$ctx" > "$tmp/context.log" 2>&1; then
  sent=$(cd "$tmp/out/ctx" 2>/dev/null && find . -type f | sed 's:^\./::' | sort)
  if [ "$sent" = "$copied" ]; then
    pass "dockerignore: the build context carries only what the Dockerfile copies ($(echo "$copied" | wc -l | tr -d ' ') files)"
  else
    echo "  context holds: $(echo "$sent" | tr '\n' ' ')"
    echo "  Dockerfile copies: $(echo "$copied" | tr '\n' ' ')"
    fail "dockerignore: the build context differs from the files the Dockerfile copies"
  fi
else
  tail -n 15 "$tmp/context.log"
  fail "dockerignore: the probe build failed"
fi

# --- IRIS_IMAGE ---

mkdir "$tmp/base"
printf 'FROM %s\nLABEL ocutalon.qa.base=%s\n' "$base_image" "$P" > "$tmp/base/Dockerfile"
if ! docker build -q -t "$P-base" "$tmp/base" > "$tmp/base.log" 2>&1; then
  tail -n 15 "$tmp/base.log"
  fail "IRIS_IMAGE: the labelled base image could not be built from $base_image"
elif IRIS_IMAGE="$P-base" docker compose -p "$P" -f docker-compose.yml -f docker/tests/compose.throwaway.yml build > "$tmp/build.log" 2>&1; then
  got=$(docker image inspect --format '{{index .Config.Labels "ocutalon.qa.base"}}' "$P-iris" 2>/dev/null)
  if [ "$got" = "$P" ]; then
    pass "IRIS_IMAGE: docker compose build builds FROM the image named in the environment"
  else
    fail "IRIS_IMAGE: the built image carries label '$got', wanted '$P' (the base was not used)"
  fi
else
  tail -n 15 "$tmp/build.log"
  fail "IRIS_IMAGE: docker compose build failed on the labelled base"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-build-inputs: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-build-inputs: all checks passed"
