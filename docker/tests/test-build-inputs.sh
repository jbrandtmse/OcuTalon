#!/usr/bin/env bash
# Build inputs of the image, observed through Docker. Starts no container.
#   - .dockerignore: from a tree that holds a decoy of everything the repository root can hold
#     (.env, irislib/, irissys/, .git, ...), the build context carries exactly the files that
#     docker/Dockerfile copies;
#   - IRIS_IMAGE: the image named in the environment of `docker compose build` is the image that
#     docker/Dockerfile builds FROM (checked by a label that only that base carries);
#   - the web bundle (Story 0.3, row 20): a build context without src/ocutalon/csp/ fails the build and says
#     "web bundle missing: run npm --prefix web run build".
# Its project and image names carry OCUTALON_RUN_TAG when it is set, like the live tests' (ci/iris.sh teardown finds them by it).
# Needs the docker daemon with BuildKit and the base image ocutalon-iris-base:2026.3.0AI.154.0 (or IRIS_IMAGE).
# Creates and removes its own files and images. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

. "$(dirname "$0")/lib-live.sh"
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
ensure_web_bundle || exit 1

P="ocutalon-t01-bi-${OCUTALON_RUN_TAG:+$OCUTALON_RUN_TAG-}$(date +%s)-$$"
base_image=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
fails=0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bi.XXXXXX") || exit 1

cleanup() {
  docker image rm -f "$P-iris" "$P-base" "$P-nobundle" >/dev/null 2>&1
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

# The files that the Dockerfile's COPY lines name, a directory source expanded to its files, are what the
# context must carry. A directory source is allowed whole: a file that only the probe adds below it, such as
# src/extra/decoy.xml, must be carried too, and a file beside the allowed ones must not be.
copied=$(copied_files)
carried=$(printf '%s\nsrc/extra/decoy.xml\n' "$copied" | sort)

ctx="$tmp/context"
mkdir -p "$ctx/docker/tests" "$ctx/docker/ipm" "$ctx/src/extra" "$ctx/irislib" "$ctx/irissys" "$ctx/.git" "$ctx/_bmad-output"
cp .dockerignore "$ctx/.dockerignore"
if [ -f docker/Dockerfile.dockerignore ]; then
  cp docker/Dockerfile.dockerignore "$ctx/docker/Dockerfile.dockerignore"
fi
for f in .env .env.local .env.example docker-compose.yml docker-compose.dev.yml README.md docker/tests/test-x.sh docker/other.sh \
  docker/ipm/other.xml irislib/x irissys/x .git/config _bmad-output/x src/extra/decoy.xml $copied; do
  mkdir -p "$ctx/$(dirname "$f")"
  echo decoy > "$ctx/$f"
done
# The probe takes the Dockerfile's place, so that the ignore file that applies to docker/Dockerfile applies to it.
printf 'FROM scratch\nCOPY . /ctx\n' > "$ctx/docker/Dockerfile"

if [ -z "$copied" ]; then
  fail "dockerignore: docker/Dockerfile has no COPY source to expect"
elif docker build -f "$ctx/docker/Dockerfile" -o "type=local,dest=$tmp/out" "$ctx" > "$tmp/context.log" 2>&1; then
  sent=$(cd "$tmp/out/ctx" 2>/dev/null && find . -type f | sed 's:^\./::' | sort)
  if [ "$sent" = "$carried" ]; then
    pass "dockerignore: the build context carries only what the Dockerfile copies ($(echo "$carried" | wc -l | tr -d ' ') files)"
  else
    echo "  context holds: $(echo "$sent" | tr '\n' ' ')"
    echo "  Dockerfile copies: $(echo "$carried" | tr '\n' ' ')"
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

# --- the web bundle ---

nobundle="$tmp/nobundle"
copy_build_context "$nobundle"
rm -rf "$nobundle/src/ocutalon/csp"
if [ -f "$nobundle/src/ocutalon/csp/index.html" ] || [ ! -f "$nobundle/src/module.xml" ]; then
  fail "web bundle: the control context is not a context without the bundle"
elif docker build -q -f "$nobundle/docker/Dockerfile" --build-arg "IRIS_IMAGE=$base_image" -t "$P-nobundle" "$nobundle" > "$tmp/nobundle.log" 2>&1; then
  docker image rm -f "$P-nobundle" >/dev/null 2>&1
  fail "web bundle: an image was built from a context without src/ocutalon/csp/"
elif grep -q 'web bundle missing: run npm --prefix web run build' "$tmp/nobundle.log"; then
  pass "web bundle: a build context without src/ocutalon/csp/ fails with 'web bundle missing: run npm --prefix web run build'"
else
  tail -n 15 "$tmp/nobundle.log"
  fail "web bundle: the build failed, but not with the missing-bundle message"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-build-inputs: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-build-inputs: all checks passed"
