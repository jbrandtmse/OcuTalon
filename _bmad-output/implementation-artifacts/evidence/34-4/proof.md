# Story 34.4 (DW-825): the proof on lane D's throwaway (lead, 2026-11-07)

Stack: one fresh sign-in unit throwaway (`docker/tests/test-sign-in.sh`'s whole setup: bundle, image, first start, fixture users,
seeded events), lane D (`OCUTALON_LOCK_DIR=.../locks/lane-d`, `OCUTALON_TEST_WEB_PORT=52804`, tag `e34s4prf`, project
`ocutalon-t03-e34s4prf-1794024017-75576`), torn down by the unit's EXIT trap. The browser run was narrowed to D5 by a scratch copy of the
unit script (not in the repository): `playwright test --project=chromium documents/documents.spec.ts --grep "D5:" --repeat-each=20`.
The OLD D5 is `documents.spec.ts` at 7b811445 (before the fix), the NEW D5 the committed fix (609316e1); the file was swapped in the
tree for the old rounds and restored to HEAD before the new round (`git diff --quiet` checked).

Load (documented, the equivalent of the browser job's): this host (16 cores, macOS arm64) with the other lanes' stacks running
(load average 9-14 before), plus 16 CPU burners (`yes > /dev/null`) for the whole browser part, old and new rounds alike, and during
old round 4 one more throttled Chromium (the stack-free repro below). Load average during the rounds 30-43. (A first attempt with the
burners on from the start failed the IRIS first start, 400 s: infra, no test ran.)

## Result
| Run | Code | Result |
|---|---|---|
| earlier stack (e34s4old), 8 burners | OLD | 20/20 passed |
| e34s4prf old round 1 | OLD | 20/20 passed (1.7 min) |
| e34s4prf old round 2 | OLD | 20/20 passed (1.6 min) |
| e34s4prf old round 3 | OLD | 20/20 passed (1.6 min) |
| e34s4prf old round 4 | OLD | **1 failed, 19 passed** — repeat 7, 31.2 s |
| e34s4prf new round | NEW | **20/20 passed** (1.6 min), same stack and load, right after |

The old failure is DW-825's CI signature exactly:
```
✘   7 [chromium] › e2e/documents/documents.spec.ts:139:5 › D5: Add documents works by keyboard, and a .png is refused with its reason (31.2s)
TimeoutError: page.waitForEvent: Timeout 30000ms exceeded while waiting for event "filechooser"
  > 146 |   const chooser = page.waitForEvent('filechooser');
TimeoutError: page.waitForResponse: Timeout 30000ms exceeded while waiting for event "response"
  >  69 | const posted = (page: Page): Promise<Response> => page.waitForResponse(...)
```
Unit summary: `SPEC documents/documents.spec.ts 100 tests 413s`; the unit's own check passed on the new round (`all checks passed`).

## Throttled, stack-free (the same mechanism, made frequent)
`filechooser-race-repro.mjs` under `taskpolicy -b` (macOS background QoS: the Playwright client and its Chromium starved, as on a busy
CI host): MODE=old **31/40 missed**, MODE=armed **0/40 missed**.

## Reading
The real page's miss rate here is about 1 in 100 (1/100 old D5 runs over the two stacks); CI saw 3 hits in about 6 hours. The armed D5
removes the race itself (interception is on before sign-in), so its rate is 0 whatever the load: 0/20 here, 0/680 armed repro runs
across loads, while the old order missed 7/390 unthrottled and 31/40 throttled.

## Smoke and fresh check (after code review, second fresh stack)
Stack `ocutalon-t03-e34s4smk-1794025649-48229` (lane D, port 52804), the same narrowed unit: old D5 x5 then **new D5 x20: 20/20 passed**
(1.9 min; `SPEC documents/documents.spec.ts 25 tests 105s`, `all checks passed`). The `taskpolicy -b` wrapper tried here did not slow the
test workers (per-test times unchanged), so this run adds no old-code evidence; the old x5 passed. Live new-D5 total: 40/40.
