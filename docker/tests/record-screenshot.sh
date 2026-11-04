#!/usr/bin/env bash
# Records the README's screenshot of one whole decision in Visual Trace. Not a CI unit and not a check: nothing runs it but a person, and its
# name is not test-*.
#   bash docker/tests/record-screenshot.sh vt-decision    rewrites docs/images/vt-decision.png (Story 31.3)
# Any other argument exits 2 before anything starts. It starts one throwaway project of its own (docker/tests/lib-live.sh, the throwaway and
# CI overrides, the web port on 127.0.0.1 only, the model keys at the CI mock, no real key), waits for the first start to end ready, and
# ends with an EXIT trap that removes the project with its volume and images.
# The browser run (npm --prefix web run e2e:capture, playwright.capture.config.ts) plays the demo-path steps 1 to 5 on that stack, then
# web/e2e-capture/vt-decision.spec.ts opens the incident's diagnosis in Visual Trace and writes the diagram to OCUTALON_CAPTURE_OUT. The spec
# fails, and writes nothing, unless the page draws the whole decision with at least two AgentStep messages, every lane fits in the shot, and
# the SVG's text names no mock, test, CI, host, port or secret.
# The file replaces docs/images/vt-decision.png only when it starts with the PNG signature and is under 300,000 bytes. Prints
# "CAPTURE agent-steps=<n> messages=<m> size=<w>x<h>" and "record-screenshot: docs/images/vt-decision.png written (<bytes> B)".
# Exits 0 only when the file was written, and 1 when it refuses or fails.
# Needs docker compose, the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0), the web bundle (ci/iris.sh build),
# Node 24.15 or later, and the browser: npx --prefix web playwright install chromium.
set -u

if [ "$#" -ne 1 ] || [ "$1" != vt-decision ]; then
  echo "usage: record-screenshot.sh vt-decision" >&2
  exit 2
fi

. "$(dirname "$0")/lib-live.sh"
live_start r31v
live_web_port || exit 1

target=docs/images/vt-decision.png

if ! live_first_start 900; then
  start_log | tail -n 30 | cut -c1-200
  dc logs --tail 20 iris 2>&1 | cut -c1-200
  die "the first start did not end ready"
fi

remaining=$((deadline - SECONDS))
if [ "$remaining" -lt 100 ]; then
  die "only $remaining s are left of the deadline: too little for the browser run"
fi
shot="$tmp/vt-decision.png"
e2e_log="$tmp/e2e.log"
OCUTALON_URL="http://127.0.0.1:$web_port" \
  OCUTALON_CAPTURE_OUT="$shot" \
  OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 30) * 1000)) \
  npm --prefix web run e2e:capture > "$e2e_log" 2>&1
e2e_status=$?
sed 's/^/  /' "$e2e_log"
if grep -q "Executable doesn't exist" "$e2e_log"; then
  echo "  the browser is missing: run npx --prefix web playwright install chromium"
fi
if [ "$e2e_status" -ne 0 ]; then die "the capture failed (Playwright exit $e2e_status): nothing was written"; fi
line=$(grep -m 1 '^CAPTURE ' "$e2e_log" || true)
if [ -z "$line" ]; then die "the capture printed no CAPTURE line: nothing was written"; fi
[ -s "$shot" ] || die "the capture wrote no file: nothing was written"
if [ "$(head -c 8 "$shot" | od -An -tx1 | tr -d ' \n')" != 89504e470d0a1a0a ]; then die "the capture is not a PNG: nothing was written"; fi
bytes=$(wc -c < "$shot" | tr -d ' ')
if [ "$bytes" -ge 300000 ]; then die "the capture is $bytes B, not under 300,000 B: nothing was written"; fi
cp "$shot" "$target" || die "$target could not be written"
echo "$line"
echo "record-screenshot: $target written ($bytes B)"
exit 0
