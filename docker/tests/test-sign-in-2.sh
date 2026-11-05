#!/usr/bin/env bash
# Live unit live:sign-in-2, the second half of the sign-in unit's browser specs (the Contest Planner's ruling of 2026-11-05: live:sign-in
# took 1047 s in CI, over the 1,000 s line, and was split by spec file into two units). It is docker/tests/test-sign-in.sh with
# --project sign-in-2: the same build, start, security rows, fixture users and seeded events on its own throwaway, then the Playwright
# project sign-in-2, the spec files of the folders that web/playwright.config.ts names in SIGN_IN_2_DIRS (live/, phone/, rail/, reminder/,
# session/ and settings/), which the chromium project of live:sign-in does not run. Every argument goes to test-sign-in.sh, so --part k/n
# (or --part=k/n) cuts this project's spec files as it cuts the chromium project's, and a second --project exits 2.
exec bash "$(dirname "$0")/test-sign-in.sh" --project sign-in-2 "$@"
