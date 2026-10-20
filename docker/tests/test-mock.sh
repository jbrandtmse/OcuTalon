#!/usr/bin/env bash
# Tests of the CI model mock (Story 0.11; AD-22): runs the node:test files of ci/mock/test/ from the repository root. Each file
# starts its own server on a free local port and removes its own fixture folders, and no test sends a request anywhere else.
# It starts no container and needs only Node 24 (the web job sets it up). Takes under 15 seconds.
# Prints node's own report; exits with node's status, or 1 when Node is missing.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL node is not installed (Node 24 or later is needed)"
  exit 1
fi
node --version
node --test ci/mock/test/*.test.mjs
