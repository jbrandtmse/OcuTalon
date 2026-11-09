#!/usr/bin/env bash
# Live unit live:sign-in-3, the third part of the sign-in unit's browser specs (the Contest Planner's ruling of 2026-11-07: after Story 4.11's
# more-to-try tests live:sign-in took 1034 s and 1170 s in CI, over the 1,000 s line, and was split again by spec file). It is
# docker/tests/test-sign-in.sh with --project sign-in-3: the same build, start, security rows, fixture users and seeded events on its own
# throwaway, then the Playwright project sign-in-3, the spec files of the folders and the file that web/playwright.config.ts names in
# SIGN_IN_3_DIRS and SIGN_IN_3_FILES (guide/, heartbeat/, heartbeat-card.spec.ts and memory-noise.spec.ts), which the chromium project of live:sign-in does not
# run. Every argument goes to test-sign-in.sh, so --part k/n (or --part=k/n) cuts this project's spec files as it cuts the chromium
# project's, and a second --project exits 2.
exec bash "$(dirname "$0")/test-sign-in.sh" --project sign-in-3 "$@"
