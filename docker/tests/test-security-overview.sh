#!/usr/bin/env bash
# Live unit of the security overview (Story 14.1; AD-10, AD-16, AD-23, AD-24): builds the image and starts it in one throwaway compose
# project with the after-start script active, so that the product is installed, then regenerates docs/security-overview.md inside the
# container with OcuTalon.Install.SecurityOverview.Regenerate and compares the result with the committed file.
#   bash docker/tests/test-security-overview.sh            compare: PASS when the generated sections of the committed file equal a fresh
#                                                          generation, byte for byte (the file outside the sections is never changed);
#                                                          otherwise one "DRIFT tool <name>" line per added, removed or changed tool row
#                                                          (or "DRIFT tools" for a change outside the rows, "DRIFT fix-kinds",
#                                                          "DRIFT privileges"), the diff of each changed region, and exit 1
#   bash docker/tests/test-security-overview.sh --write    writes the regenerated file to docs/security-overview.md instead and
#                                                          compares nothing
# The unit reads no web bundle. The project is unique, publishes no host port and receives no keys. An EXIT trap removes the project with its
# volume and images. Every wait ends by an overall deadline. Prints one PASS or FAIL line per check; exits 0 only when all pass.
# Needs docker compose and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

write=0
case ${1:-} in
  '') ;;
  --write) write=1 ;;
  *)
    echo "FAIL unknown argument '$1': the only option is --write"
    exit 2
    ;;
esac

. "$(dirname "$0")/lib-live.sh"
. "$(dirname "$0")/lib-security-overview.sh"
live_start security-overview

doc=docs/security-overview.md
[ -f "$doc" ] || die "$doc does not exist: it holds the markers that the generator replaces the text between"

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"

if ! wait_started_ready "$LIVE_FIRST_START_WAIT"; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready within $LIVE_FIRST_START_WAIT s"
fi
pass "the first start ended ready"

inside=/tmp/security-overview-in.md
outside=/tmp/security-overview-out.md
dc cp "$doc" "iris:$inside" > /dev/null 2>&1 || die "the committed overview could not be copied into the container"

printf '%s\n' \
  "Set sc=##class(OcuTalon.Install.SecurityOverview).Regenerate(\"$inside\",\"$outside\")" \
  'Write !,"CHK|regenerate|",$SYSTEM.Status.IsOK(sc)' \
  'If $SYSTEM.Status.IsError(sc) Write !,"CHK|error|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(10,13),"  ")' \
  'Halt' | iris_script OCUTALON > "$tmp/regenerate.chk"
if ! grep -qx 'CHK|regenerate|1' "$tmp/regenerate.chk"; then
  sed -n 's/^CHK|error|/  /p' "$tmp/regenerate.chk" | cut -c1-300
  die "Regenerate did not succeed"
fi
pass "OcuTalon.Install.SecurityOverview.Regenerate succeeded"

dc cp "iris:$outside" "$tmp/overview.out" > /dev/null 2>&1 || die "the regenerated overview could not be copied out of the container"
[ -s "$tmp/overview.out" ] || die "the regenerated overview is empty"

if [ "$write" -eq 1 ]; then
  cp "$tmp/overview.out" "$doc" || die "$doc could not be written"
  pass "wrote $doc"
elif cmp -s "$doc" "$tmp/overview.out"; then
  pass "the generated sections of $doc equal a fresh generation"
else
  drift "$doc" "$tmp/overview.out"
  fail "the generated sections of $doc differ from a fresh generation: run bash release/security-overview.sh --write and commit the file"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-security-overview: $fails check(s) failed (project $P)"
  exit 1
fi
echo "test-security-overview: all checks passed"
