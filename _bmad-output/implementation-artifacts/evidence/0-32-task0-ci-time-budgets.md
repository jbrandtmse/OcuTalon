# Story 0.32, Task 0: the CI time budgets against their green medians

Measured 2026-11-12 from CI job logs with read-only `gh`. Rule: margin = budget / green median; a budget under 1.4 is raised to
1.4 x its median (deadlines rounded up to 60 s, waits to 30 s), with the rulings of DW-1082 and DW-1195 applied as worded, the
cap of about 12 changed budgets, and every value finite and at most 2,340 s. The code's values equal the new-value columns
below (LIVE_FIRST_START_WAIT and the install-upgrade and install-start literals, `unit_live_deadline` in ci/units.sh).

## Method

- Runs read: the `ci` push runs of 2026-11-11 and 2026-11-12 on any branch, newest first: 43234781487, 43227065531, 43218921197,
  43206845957, 43202138313, 43201190985, 43200877872, 43172109907, 43160772937, 43159935962, 43159105606, 43153698989, 43151061323,
  43149397990, 43148782668, 43143022182, 43136084417 (17 runs, 16 iris job logs each). Per budget the 10 newest of them whose job
  holding the unit concluded `success` and printed the unit's pass line were used (n in the tables; every row has n = 10, and
  the oldest run any row uses is 43153698989). A run that is red in another job still counts for a unit whose own job is green.
  lane-a runs read for the job durations (jobs only, no logs; 43202138310's listing failed and is left out): 43234781475,
  43227065502, 43218922253, 43206845590, 43201190573, 43200877871, 43172863784, 43172123556, 43172110020, 43160772958, 43159935971.
- The `file:line` labels of the R rows are the lines of the baseline scripts (before this story's edits).
- U: the seconds of `UNIT live:<u> passed <s>s`. All units run with the CI env's deadline of 1200 s.
- S: the Playwright `N passed (X.Ym)` line (the longest one when a unit runs Playwright twice). Budget per run =
  D - (time of the last log line before the Playwright output block - time of `---- UNIT ... begins`) - 20 s (80 s for demo-path).
  The CI log prints the browser output in one block after the run, so the line before the block ends the setup.
  live:demo-switch prints no duration, so its two mode runs are bounded by the gap before each `PASS demo mode` line.
- R: the timestamp gap from the last log line before the start command to the end of the wait; where `PARK done <s>s` follows the
  end is that line's time minus its seconds. The CI log is filtered to PASS, MEASURED and a few other lines, so every gap is an
  upper bound (the image build, the stop and the checks that sit between two printed lines are inside it), marked `<=` and
  giving a margin marked `>=`. Rows without a `PARK` line (row 19 of production-restart, row 7's failing step, memory-offline
  and compose-start) use the gap before their next PASS line.
- The first start is one budget (`LIVE_FIRST_START_WAIT`): the largest per-unit median is 346 s (test-sign-in-3.sh), so
  1.4 x 346 = 484 s, rounded up to 30 s = 510 s, under the 720 s of AD-23's WARN. Cross-check: demo-path's `FIRST-START ready=`
  over the same 10 runs is 321, 355, 361, 293, 318, 312, 299, 276, 275 and 289 s (median 306 s), which sits under the upper
  bound, and the largest single gap seen is 412 s.
- Budgets count `wait_until`'s poll seconds while MEASURED lines report wall-clock, so a passing wait can print more seconds
  than its budget; comparing budgets with wall-clock medians errs on the safe side.
- `LIVE_PORT_WAIT` (90 s): no `PORT free` or `waited ... for port` line occurs in any of the 17 runs, so the wait was never needed
  (n = 0); it stays.

## Changed budgets (11 of the cap of about 12)

| # | budget | before | after | why |
|---|---|---|---|---|
| 1 | live:install-start deadline | 1200 | 1440 | 1.20 -> 1.44 |
| 2 | live:install-upgrade deadline | 1200 | 1440 | 1.18 -> 1.41 |
| 3 | live:sign-in deadline | 1200 | 1500 | 1.16 -> 1.45; suite budget 832 -> 1132 s (DW-1195: at least 950 s) |
| 4 | live:sign-in-2 deadline | 1200 | 1500 | 1.15 -> 1.44; suite budget 841 -> 1141 s |
| 5 | live:sign-in-3 deadline | 1200 | 1500 | 1.12 -> 1.40; suite budget 822 -> 1122 s |
| 6 | first start, 23 scripts (`LIVE_FIRST_START_WAIT`) | 400 | 510 | 1.16 -> 1.48 (largest per-unit median) |
| 7 | test-install-upgrade.sh row 6 | 200 | 300 | ruled (DW-1082), 0.91 -> 1.37 |
| 8 | test-install-upgrade.sh row 7 failing step | 200 | 300 | DW-1082 occurrence, at least 300 s; 0.98 -> 1.48 |
| 9 | test-install-upgrade.sh row 7 next good image | 200 | 330 | DW-1082 occurrence; 0.93 -> 1.53 |
| 10 | test-install-start.sh row 3 | 200 | 300 | 0.95 -> 1.43 |
| 11 | test-install-start.sh row 4 restart | 200 | 270 | 1.05 -> 1.41 |

Every other budget of the inventory has at least 1.4 (the lowest: live:floor's unit deadline 1.47, the first-start waits of
test-online-allowance.sh and test-online-demo.sh 1.39 and 1.38 as separate rows, which the one first-start budget lifts to 1.77
and 1.76). Row 7 of test-install-upgrade.sh sits at 1.48 and 1.53; row 6 stays at the ruled 1.37 (below 1.4 by the ruling, with a
deferred entry in the spec).

## Tables

### U: unit deadlines (CI `OCUTALON_LIVE_DEADLINE` 1200 s)

| budget | current | source | runs | median | margin before | action | new | margin after |
|---|---|---|---|---|---|---|---|---|
| live:answers | 1200 | `UNIT ... passed <s>s` | 10 | 552 s | 2.17 | none (at least 1.4) | 1200 | 2.17 |
| live:audit | 1200 | `UNIT ... passed <s>s` | 10 | 366.5 s | 3.27 | none (at least 1.4) | 1200 | 3.27 |
| live:build-inputs | 1200 | `UNIT ... passed <s>s` | 10 | 20 s | 60.00 | none (at least 1.4) | 1200 | 60.00 |
| live:bundle-folder | 1200 | `UNIT ... passed <s>s` | 10 | 360 s | 3.33 | none (at least 1.4) | 1200 | 3.33 |
| live:cards | 1200 | `UNIT ... passed <s>s` | 10 | 494.5 s | 2.43 | none (at least 1.4) | 1200 | 2.43 |
| live:compose-start | 1200 | `UNIT ... passed <s>s` | 10 | 233 s | 5.15 | none (at least 1.4) | 1200 | 5.15 |
| live:demo-path | 1200 | `UNIT ... passed <s>s` | 10 | 669.5 s | 1.79 | none (at least 1.4) | 1200 | 1.79 |
| live:demo-switch | 1200 | `UNIT ... passed <s>s` | 10 | 612 s | 1.96 | none (at least 1.4) | 1200 | 1.96 |
| live:documents | 1200 | `UNIT ... passed <s>s` | 10 | 426.5 s | 2.81 | none (at least 1.4) | 1200 | 2.81 |
| live:floor | 1200 | `UNIT ... passed <s>s` | 10 | 817.5 s | 1.47 | none (at least 1.4) | 1200 | 1.47 |
| live:heartbeat-restart | 1200 | `UNIT ... passed <s>s` | 10 | 450.5 s | 2.66 | none (at least 1.4) | 1200 | 2.66 |
| live:install-script-live | 1200 | `UNIT ... passed <s>s` | 10 | 376.5 s | 3.19 | none (at least 1.4) | 1200 | 3.19 |
| live:install-start | 1200 | `UNIT ... passed <s>s` | 10 | 999 s | 1.20 | floor in `unit_live_deadline` | 1440 | 1.44 |
| live:install-upgrade | 1200 | `UNIT ... passed <s>s` | 10 | 1020.5 s | 1.18 | floor in `unit_live_deadline` | 1440 | 1.41 |
| live:memory-offline | 1200 | `UNIT ... passed <s>s` | 10 | 585 s | 2.05 | none (at least 1.4) | 1200 | 2.05 |
| live:online-allowance | 1200 | `UNIT ... passed <s>s` | 10 | 515.5 s | 2.33 | none (at least 1.4) | 1200 | 2.33 |
| live:online-demo | 1200 | `UNIT ... passed <s>s` | 10 | 759 s | 1.58 | none (at least 1.4) | 1200 | 1.58 |
| live:online-demo-path | 1200 | `UNIT ... passed <s>s` | 10 | 521 s | 2.30 | none (at least 1.4) | 1200 | 2.30 |
| live:online-session | 1200 | `UNIT ... passed <s>s` | 10 | 519.5 s | 2.31 | none (at least 1.4) | 1200 | 2.31 |
| live:online-visitors | 1200 | `UNIT ... passed <s>s` | 10 | 504 s | 2.38 | none (at least 1.4) | 1200 | 2.38 |
| live:production | 1200 | `UNIT ... passed <s>s` | 10 | 390 s | 3.08 | none (at least 1.4) | 1200 | 3.08 |
| live:production-restart | 1200 | `UNIT ... passed <s>s` | 10 | 424 s | 2.83 | none (at least 1.4) | 1200 | 2.83 |
| live:reminder-restart | 1200 | `UNIT ... passed <s>s` | 10 | 729.5 s | 1.64 | none (at least 1.4) | 1200 | 1.64 |
| live:security-overview | 1200 | `UNIT ... passed <s>s` | 10 | 341.5 s | 3.51 | none (at least 1.4) | 1200 | 3.51 |
| live:session-data | 1200 | `UNIT ... passed <s>s` | 10 | 402 s | 2.99 | none (at least 1.4) | 1200 | 2.99 |
| live:sign-in | 1200 | `UNIT ... passed <s>s` | 10 | 1033.5 s | 1.16 | floor in `unit_live_deadline` | 1500 | 1.45 |
| live:sign-in-2 | 1200 | `UNIT ... passed <s>s` | 10 | 1042 s | 1.15 | floor in `unit_live_deadline` | 1500 | 1.44 |
| live:sign-in-3 | 1200 | `UNIT ... passed <s>s` | 10 | 1068 s | 1.12 | floor in `unit_live_deadline` | 1500 | 1.40 |
| live:storage-roundtrip | 1200 | `UNIT ... passed <s>s` | 10 | 424.5 s | 2.83 | none (at least 1.4) | 1200 | 2.83 |

### S: browser suite budgets (D - setup - 20 s; demo-path D - setup - 80 s)

| budget | current | source | runs | median suite | margin before | action | new | margin after |
|---|---|---|---|---|---|---|---|---|
| live:demo-path suite | 810 s (setup 310 s) | Playwright `N passed (X.Ym)` | 10 | 357 s | 2.27 | none (at least 1.4) | 810 s | 2.27 |
| live:sign-in suite (`globalTimeout`) | 832 s (setup 348 s) | Playwright `N passed (X.Ym)` | 10 | 675 s | 1.23 | D raised to 1500 (DW-1195: at least max(950, 1.4 x 675 = 945)) | 1132 s | 1.68 |
| live:sign-in-2 suite (`globalTimeout`) | 841 s (setup 339 s) | Playwright `N passed (X.Ym)` | 10 | 696 s | 1.21 | D raised to 1500 (DW-1195: at least max(950, 1.4 x 696 = 975)) | 1141 s | 1.64 |
| live:sign-in-3 suite (`globalTimeout`) | 822 s (setup 358 s) | Playwright `N passed (X.Ym)` | 10 | 681 s | 1.21 | D raised to 1500 (DW-1195: at least max(950, 1.4 x 681 = 954)) | 1122 s | 1.65 |
| live:floor suite | 848 s (setup 332 s) | Playwright `N passed (X.Ym)` | 10 | 471 s | 1.80 | none (at least 1.4) | 848 s | 1.80 |
| live:online-demo suite | 851 s (setup 329 s) | Playwright `N passed (X.Ym)` | 10 | 294 s | 2.90 | none (at least 1.4) | 851 s | 2.90 |
| live:answers suite | 866 s (setup 314 s) | Playwright `N passed (X.Ym)` | 10 | 225 s | 3.85 | none (at least 1.4) | 866 s | 3.85 |
| live:cards suite | 854 s (setup 326 s) | Playwright `N passed (X.Ym)` | 10 | 162 s | 5.27 | none (at least 1.4) | 854 s | 5.27 |
| live:online-session suite | 862 s (setup 318 s) | Playwright `N passed (X.Ym)` | 10 | 120 s | 7.18 | none (at least 1.4) | 862 s | 7.18 |
| live:online-allowance suite | 881 s (setup 299 s) | Playwright `N passed (X.Ym)` | 10 | 198 s | 4.45 | none (at least 1.4) | 881 s | 4.45 |
| live:online-demo-path suite | 868 s (setup 312 s) | Playwright `N passed (X.Ym)` | 10 | 150 s | 5.79 | none (at least 1.4) | 868 s | 5.79 |
| live:online-visitors suite | 864 s (setup 316 s) | Playwright `N passed (X.Ym)` | 10 | 144 s | 6.00 | none (at least 1.4) | 864 s | 6.00 |
| live:demo-switch suite, mode run 1 | 760 s (setup 420 s) | gap before the `PASS demo mode` line (upper bound; no duration line) | 10 | <= 11 s | >= 70.53 | none (at least 1.4) | 760 s | >= 70.53 |
| live:demo-switch suite, mode run 2 | 668 s (setup 512 s) | gap before the `PASS demo mode` line (upper bound; no duration line) | 10 | <= 81 s | >= 8.28 | none (at least 1.4) | 668 s | >= 8.28 |

### R: ready waits (poll seconds; the median is a log-gap upper bound, build included)

| budget | current | source | runs | median | margin before | action | new | margin after |
|---|---|---|---|---|---|---|---|---|
| first start in test-answers.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 308 s | >= 1.30 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.66 |
| first start in test-audit.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 324 s | >= 1.23 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.57 |
| first start in test-bundle-folder.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 308 s | >= 1.30 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.65 |
| first start in test-cards.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 320 s | >= 1.25 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.59 |
| first start in test-demo-switch.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 316 s | >= 1.27 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.61 |
| first start in test-floor.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 322 s | >= 1.24 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.58 |
| first start in test-documents.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 327 s | >= 1.22 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.56 |
| first start in test-heartbeat-restart.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 310 s | >= 1.29 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.65 |
| first start in test-install-start.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 330 s | >= 1.21 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.55 |
| first start in test-install-upgrade.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 316 s | >= 1.26 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.61 |
| first start in test-memory-offline.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 310 s | >= 1.29 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.65 |
| first start in test-online-allowance.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 288 s | >= 1.39 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.77 |
| first start in test-online-demo.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 289 s | >= 1.38 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.76 |
| first start in test-online-demo-path.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 301 s | >= 1.33 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.69 |
| first start in test-online-session.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 306 s | >= 1.31 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.67 |
| first start in test-online-visitors.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 310 s | >= 1.29 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.64 |
| first start in test-production.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 313 s | >= 1.28 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.63 |
| first start in test-production-restart.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 307 s | >= 1.30 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.66 |
| first start in test-reminder-restart.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 309 s | >= 1.29 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.65 |
| first start in test-security-overview.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 325 s | >= 1.23 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.57 |
| first start in test-session-data.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 324 s | >= 1.24 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.58 |
| first start in test-sign-in.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 337 s | >= 1.19 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.51 |
| first start in test-sign-in-2.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 328 s | >= 1.22 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.55 |
| first start in test-sign-in-3.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 346 s | >= 1.16 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.48 |
| first start in test-storage-roundtrip.sh (`wait_started_ready`) | 400 | gap, `PARK done` or next line | 10 | <= 335 s | >= 1.19 | one budget `LIVE_FIRST_START_WAIT` | 510 | >= 1.52 |
| test-bundle-folder.sh:120 restart | 200 | gap, `PARK done` or next line | 10 | <= 29 s | >= 7.01 | none (at least 1.4) | 200 | >= 7.01 |
| test-documents.sh:318 restart | 400 | gap, `PARK done` or next line | 10 | <= 30 s | >= 13.48 | none (at least 1.4) | 400 | >= 13.48 |
| test-heartbeat-restart.sh:97 restart 1 | 300 | gap, `PARK done` or next line | 10 | <= 26 s | >= 11.74 | none (at least 1.4) | 300 | >= 11.74 |
| test-heartbeat-restart.sh:132 restart 2 | 300 | gap, `PARK done` or next line | 10 | <= 25 s | >= 12.13 | none (at least 1.4) | 300 | >= 12.13 |
| test-install-start.sh:164 row 2 | 200 | gap, `PARK done` or next line | 10 | <= 65 s | >= 3.08 | none (at least 1.4) | 200 | >= 3.08 |
| test-install-start.sh:295 row 3 | 200 | gap, `PARK done` or next line | 10 | <= 210 s | >= 0.95 | raised | 300 | >= 1.43 |
| test-install-start.sh:457 row 4 | 200 | gap, `PARK done` or next line | 10 | <= 33 s | >= 5.98 | none (at least 1.4) | 200 | >= 5.98 |
| test-install-start.sh:665 row 4 restart | 200 | gap, `PARK done` or next line | 10 | <= 191 s | >= 1.05 | raised | 270 | >= 1.41 |
| test-install-upgrade.sh:170 row 6 | 200 | gap, `PARK done` or next line | 10 | <= 219 s | >= 0.91 | raised (ruled: DW-1082 row 6 is exactly 300 s) | 300 | >= 1.37 |
| test-install-upgrade.sh:205 row 7 failing step (log) | 200 | gap, `PARK done` or next line | 10 | <= 203 s | >= 0.98 | raised (DW-1082: at least 300 s) | 300 | >= 1.48 |
| test-install-upgrade.sh:256 row 7 next good image | 200 | gap, `PARK done` or next line | 10 | <= 216 s | >= 0.93 | raised | 330 | >= 1.53 |
| test-memory-offline.sh:215 restart | 400 | gap, `PARK done` or next line | 10 | <= 20 s | >= 19.61 | none (at least 1.4) | 400 | >= 19.61 |
| test-online-demo.sh:1860 row 13 restart | 200 | gap, `PARK done` or next line | 10 | <= 23 s | >= 8.58 | none (at least 1.4) | 200 | >= 8.58 |
| test-online-visitors.sh:165 row 7 restart | 300 | gap, `PARK done` or next line | 10 | <= 26 s | >= 11.75 | none (at least 1.4) | 300 | >= 11.75 |
| test-production-restart.sh:188 row 19 (1) | 200 | gap, `PARK done` or next line | 10 | <= 31 s | >= 6.46 | none (at least 1.4) | 200 | >= 6.46 |
| test-production-restart.sh:212 row 19 (2) | 200 | gap, `PARK done` or next line | 10 | <= 28 s | >= 7.17 | none (at least 1.4) | 200 | >= 7.17 |
| test-production-restart.sh:262 row 20 | 300 | gap, `PARK done` or next line | 10 | <= 24 s | >= 12.27 | none (at least 1.4) | 300 | >= 12.27 |
| test-production.sh:400 digest restart | 300 | gap, `PARK done` or next line | 10 | <= 23 s | >= 13.28 | none (at least 1.4) | 300 | >= 13.28 |
| test-reminder-restart.sh:221 restart 1 | 300 | gap, `PARK done` or next line | 10 | <= 92 s | >= 3.27 | none (at least 1.4) | 300 | >= 3.27 |
| test-reminder-restart.sh:298 restart 2 | 400 | gap, `PARK done` or next line | 10 | <= 215 s | >= 1.86 | none (at least 1.4) | 400 | >= 1.86 |
| test-compose-start.sh:226 first start merge | 240 | gap, `PARK done` or next line | 10 | <= 114 s | >= 2.11 | none (at least 1.4) | 240 | >= 2.11 |
| test-compose-start.sh:374 restarts | 90 | gap, `PARK done` or next line | 10 | <= 22 s | >= 4.07 | none (at least 1.4) | 90 | >= 4.07 |
| test-install-script-live.sh:157 plain up healthy | 600 | gap, `PARK done` or next line | 10 | <= 23 s | >= 26.26 | none (at least 1.4) | 600 | >= 26.26 |
## Report-only rows (nothing here is changed; each row under 1.4 is a `deferred:` entry of the spec, for the Planner)

### Workflow job timeouts against the job's green median (10 newest green jobs)

| workflow job | timeout | median | max | timeout / median | timeout / max |
|---|---|---|---|---|---|
| ci checks | 20 min (1200 s) | 962 s | 1015 s | 1.25 | 1.18 |
| ci install-macos | 10 min (600 s) | 39 s | 45 s | 15.4 | 13.3 |
| ci web | 15 min (900 s) | 80 s | 102 s | 11.3 | 8.8 |
| ci iris (16 groups, below) | 40 min (2400 s) | 1446 to 1800 s | 2050 s | 1.33 to 1.66 | 1.17 |
| lane-a standalone-bridge | 25 min (1500 s) | 494 s | 604 s | 3.04 | 2.48 |
| lane-a evaluation | 30 min (1800 s) | 1022 s | 1172 s | 1.76 | 1.54 |
| lane-a ipm-install | 35 min (2100 s) | 1859 s | 2098 s | 1.13 | 1.00 |
| lane-a ipm-install-p | 35 min (2100 s) | 1741 s | 1893 s | 1.21 | 1.11 |

### Each iris group's unit seconds plus the job's overhead against 2,400 s

| iris group | n | group unit seconds (median) | job (median) | job (max) | 2400 / median | 2400 / max |
|---|---|---|---|---|---|---|
| install-fresh | 10 | 1531 s | 1542 s | 1701 s | 1.56 | 1.41 |
| install-upgrade | 10 | 1535 s | 1570 s | 1686 s | 1.53 | 1.42 |
| production | 10 | 1692 s | 1729 s | 2050 s | 1.39 | 1.17 |
| browser | 10 | 1433 s | 1446 s | 1656 s | 1.66 | 1.45 |
| shards | 10 | 1729 s | 1765 s | 1901 s | 1.36 | 1.26 |
| shards-2 | 10 | 1747 s | 1732 s | 2048 s | 1.39 | 1.17 |
| image | 10 | 1566 s | 1604 s | 1703 s | 1.50 | 1.41 |
| shards-3 | 10 | 1425 s | 1463 s | 1704 s | 1.64 | 1.41 |
| shards-4 | 10 | 1632 s | 1672 s | 1883 s | 1.44 | 1.27 |
| shards-5 | 10 | 1757 s | 1794 s | 2019 s | 1.34 | 1.19 |
| shards-6 | 10 | 1707 s | 1708 s | 1972 s | 1.41 | 1.22 |
| shards-7 | 10 | 1468 s | 1506 s | 1771 s | 1.59 | 1.36 |
| shards-8 | 10 | 1582 s | 1619 s | 1771 s | 1.48 | 1.36 |
| shards-9 | 10 | 1576 s | 1612 s | 1706 s | 1.49 | 1.41 |
| shards-10 | 10 | 1763 s | 1800 s | 1993 s | 1.33 | 1.20 |
| shards-11 | 10 | 1762 s | 1777 s | 1922 s | 1.35 | 1.25 |

The floors raise only the caps of five units, not their run time. Where a group holds a floored unit (install-fresh: install-start;
install-upgrade: install-upgrade; shards-4, shards-5 and shards-10: the sign-in units), the worst case of its units can pass the 40
minutes; a real hang there ends at the job's own cap. Raising a job cap is a RELEASE TOOL hunk and the Planner's call.

### Playwright's 45 s per-test timeout (the slowest test of each project, median over the 10 newest runs)

online-allowance 35.5 s (1.27), online-demo 32.7 s (1.38), sign-in-3 31.6 s (1.42), online-session 29.4 s (1.53), answers
28.5 s (1.58), cards 22.1 s (2.04), floor-webkit 14.4 s, floor-firefox 12.8 s, sign-in-2 11.5 s, online-demo-path 8.2 s,
chromium 4.3 s. Tests that set a longer timeout of their own are above 45 s by design (demo-path 54.5 s, online-visitors 144 s).
The 45 s sits in web/playwright.config.ts, outside this story.

## Decisions taken at implement

- The row 7 failing step is a `wait_started_log` with no `PARK`, so its median is the gap before `PASS row 7: the log names SSL as failed`.
- test-compose-start.sh's `wait_ready 90` is bounded by the largest gap among its four restart checks (22 s median).
- Task 0's table shows no budget the plan did not foresee beyond the above; the five floors the plan expected are confirmed.
