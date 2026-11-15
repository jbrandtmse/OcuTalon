---
title: 'DW-1388: B13 empties the list before the reopened page asks for it'
type: 'chore'
created: '2026-11-15'
status: 'done'
baseline_revision: '76829fcc93f29b40a9604c15d2aefaceee59e522'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-5-set-up-source-polls-and-answer-tool-call-approval-requests.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-9-show-the-changed-tool-banner-in-settings.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-32-6-a-live-page-s-state-wait-under-ci-load-either-finds-its-caus.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1388, raised to HIGH by the Contest Planner; lane C):** `web/e2e/settings/mcp.spec.ts` B13 (L479-604, Story 21.5's source form) fails in CI with `TimeoutError: locator.click: Timeout 60000ms exceeded` at L600. It was waiting for the button "Remove the source Existing" in the "Your sources" region.

**Cause: a race in the test, not in the UI.** Step (d) (L596-603) runs in this order:

1. `await reopen()` (L597). `reopen` (L511-514) is `page.reload()` plus a wait for the level-2 heading "Tools and MCP servers".
2. `removal = 404` (L598).
3. `gone = true` (L599).
4. `await removeButton().click()` (L600).

The heading does not belong to the MCP section. It is the Settings page's own `<h2>` (`settings-page.ts` L60). It renders as soon as `GET /v1/settings` sets the page `loaded` (L386). The MCP section is a lazy chunk: an effect imports it (L307-308) and `ngComponentOutlet` mounts it (L97). Only then does its constructor call `load()` (`mcp-section.ts` L599-601, L613-631), which sends `GET /settings/mcp` (`api-client.ts` L117-118). So when the heading is visible, that GET may not yet have reached the test's route.

The B13 GET route (L484-490) reads `gone` at the moment the request reaches it. When the GET arrives after L599 has run, the route answers a list with no sources. The "Existing" row then never renders, and the click waits out its 60 s.

**Evidence: all four hits fail the same way.** Each CI artifact's `error-context.md` page snapshot shows the freshly reloaded section with B13's own mocked list, which proves the B13 route answered:

- the server `zzb13`;
- the tools `zz_a` and `zz_b`, each with "Use as a source";
- under "Your sources", only "No sources yet.";
- no `[data-error="sources"]` message (so the 404 Remove was never sent), no "Saved" and no dialog.

The UI did exactly what the answer told it. The test had already switched the mock's list to empty.

**Approach (test only, one file):** flip `gone` inside B13's `DELETE /sources/zzsrc13` route, at the moment it answers the 404, and delete L599. This is the pattern B10 already uses in the same file (L353-355). Every list fetched before the Remove is answered then holds the source. Every list fetched after it, including the reload that the UI sends on the 404 (`mcp-section.ts` L843), lacks it. The order now follows from the request flow and no longer depends on timing.

## Boundaries & Constraints

**Always:**
- Footprint: `web/e2e/settings/mcp.spec.ts` (Story 21.5, lane C) and this spec. Nothing else. At merge, the ledger's status line for DW-1388 is written as bookkeeping, per the run's DW process.
- B13 keeps every assertion, its title, its `test.setTimeout(240_000)` and its order of steps. Only where `gone` becomes true changes.
- A wait in the test is always on state or on a network answer, never a sleep. The fix adds no wait at all.
- Comments state the contract, not the history.

**Never:**
- Change `web/src/**`. The UI is not at fault (see Design Notes). If implement finds that the UI does lose or delay a row it was given, it stops with `## Clarification Needed`, because a UI change is a Veto item.
- Raise a timeout, add `test.retry`, `waitForTimeout` or `test.slow`, or add a retry loop.
- Touch `ci/iris.sh`, `docker/tests/*` or `web/playwright.config.ts`. The repeat harness below is a scratch shim, never committed.
- Start a stack outside lane C's lock, or use a dev slot (Rule 21).

## I/O & Edge-Case Matrix

The `gone` column shows the value the B13 GET route reads when the request reaches it.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Reopen before the 404 Remove (step d) | `reopen()`, then `removal = 404`. The section's GET arrives at any time after the heading. | `gone` is false, so the list holds "Existing" and the click finds "Remove the source Existing". | none |
| 2 The 404 Remove | Click, then `DELETE /sources/zzsrc13`. | The route sets `gone = true`, then fulfills the 404. The UI shows `NOT_FOUND` under the sources and reloads the list. | none |
| 3 The reload after the 404 | The UI's `reload()` GET (`mcp-section.ts` L843), sent after the 404 answer. | `gone` is true, so the list has no sources: "No sources yet.", and the row has count 0 (L602-603). | none |
| 4 Earlier Removes (500, 403, 409) | Steps (c), L579-594. | The DELETE route leaves `gone` false. Behavior is as today. | none |
| 5 Late GET (repro injection M1) | Each `GET /settings/mcp` is held 2 s before the B13 route sees it. | Old test: red at L600 every run, with the CI signature. Fixed test: green. | none |

</intent-contract>

## Code Map

- `web/e2e/settings/mcp.spec.ts`:
  - The header doc for B13 is at L29-31.
  - Constants: `SERVER_FAILED` and `failure` at L265-266, `sources()` at L377, `NOT_FOUND` at L383.
  - `sourceListBody` is at L459, and `refused` comes just before B13.
  - B13 runs from L479 to L604:
    - the state variables `gone`, `save` and `removal` are at L481-483;
    - the GET route of `**/settings/mcp` is at L484-490 and reads `gone` on entry;
    - the POST route of `/sources` is at L491-497;
    - the DELETE route of `/sources/zzsrc13` is at L498-504;
    - `reopen` is at L511-514;
    - step (c) is at L568-594;
    - step (d) is at L596-603, with `gone = true` at L599 and the failing click at L600.
  - B10 (L338-374) is the model: it sets `gone = true` inside its DELETE route (L353-355).
- `web/src/app/settings/settings-page.ts`:
  - The panel's `<h2>` is at L60. It is inside `@case ('loaded')` (L48), which `request()` sets (L379-386).
  - The MCP section is mounted by `ngComponentOutlet` at L97, and the effect that imports `./mcp-section` is at L303-310.
- `web/src/app/settings/mcp-section.ts`:
  - The constructor calls `load()` (L599-601). `load` (L613-631) and the quiet `reload` (L635-648) each send one GET.
  - The template draws the "Your sources" rows with `@for ... track source.ref` (L344-379).
  - `removeSource` (L822-846) reloads after a 200 (L831) or after a refused Remove (L843), but not after 403 or 409 (L837-838).
- `web/src/app/api/api-client.ts`: `mcpSettings` is at L117-118 and `removeMcpSource` at L145-146.
- `docker/tests/test-sign-in.sh`:
  - The arguments are `--project` and `--part` only. Any other argument exits 2 (L131-133).
  - With `--part`, the Playwright call is `npm --prefix web run e2e:sign-in-2 -- --test-list <file>` (L382-386), and the part's count check is at L459-466. Without `--part`, the call is `npm --prefix web run e2e:sign-in-2` with no other argument (L434).
- `docker/tests/test-sign-in-2.sh`: this is `test-sign-in.sh --project sign-in-2 "$@"`.
- `web/scripts/e2e-part.mjs`: it computes part k of n from Playwright's JSON listing.

## Tasks & Acceptance

**Task 0 (set-up and measurement, before the edit; record each result under `## Verification`). Each item is (inference) until measured:**
1. **Node setup.** This worktree has no `web/node_modules`, so run `cd web && npm ci` first. Then `npx --prefix web playwright install chromium` if `ci/iris.sh live` reports the browser missing.
2. **The part.** Run `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json > "$SCR/list.json"`, then `node web/scripts/e2e-part.mjs 18/24 "$SCR/list.json"`, and repeat for neighbouring k until the PART line lists `settings/mcp.spec.ts`. Record that k. It is expected to be 18, as at 21.9, because no spec file has been added under the sign-in-2 folders since 21.9 (`git log --diff-filter=A 927667702..HEAD` is empty). Test counts may still have moved.
3. **Shim timings.** Write the scratch npm shim (see `## Verification`). Then run one call with `B13_REPEAT=1` on the unchanged tree. Record:
   - the set-up seconds (from the lock to `MEASURED live:sign-in-2 suite budget`);
   - B13's own seconds (from the list reporter's line).
   
   Size `B13_REPEAT` for the later calls so that set-up plus N times B13 stays under about 480 s, inside the 600 s foreground cap.
4. **The race, reproduced (old test).** On the unchanged test, add injection M1 as a scratch edit (see Acceptance 1). Run `B13_REPEAT=2`. Expected: 2 of 2 red at L600 with `locator.click: Timeout 60000ms exceeded` waiting for "Remove the source Existing". The `error-context.md` should show "No sources yet." and no `[data-error="sources"]`, as in CI. Remove M1 again, byte for byte.

**Execution:**
- [ ] `web/e2e/settings/mcp.spec.ts`, B13's DELETE route (L498-504): in the `DELETE` branch, before `await route.fulfill(removal);`, add:
  ```ts
      // A 404 says the source is already gone: every list asked for after this answer lacks it, and every list asked for before it holds it.
      if (removal.status === 404) {
        gone = true;
      }
  ```
- [ ] Same file, step (d): delete L599 `gone = true;`. L597-598 and L600-603 stay as they are, and the step's comment (L596) stays.
- [ ] This spec: the Task 0 records, the mutation lines and the repeat counts go under `## Verification`.

**Acceptance Criteria:**
1. Given step (d) of B13, when the reopened section's list GET reaches the route at any time after the heading shows (immediately, or held 2 s), then the list holds "Existing", the 404 Remove shows `NOT_FOUND`, and the list loaded after it is empty.
   - mutation M1 (Rule 19, the repro injection; a scratch edit, removed byte for byte): right after B13's three `page.route` calls (after L504), add a route that runs first, because Playwright runs the last-registered handler first:
     ```ts
       await page.route(`**${MCP}`, async (route) => {
         if (route.request().method() === 'GET') {
           await new Promise((resolve) => setTimeout(resolve, 2_000));
         }
         await route.fallback();
       });
     ```
     - Old test plus M1: red at L600 in every run (Task 0 item 4).
     - Fixed test plus M1: green in every run (`B13_REPEAT` of at least 3), and B13 still ends inside its 240 s.
2. Given the 404 Remove, the end assertions still depend on the flip, so the fix does not make them vacuous.
   - mutation M2 (test side): drop the new `gone = true` from the DELETE route. The fixed test goes red at L602 ("and the source leaves the list"), because the reload after the 404 still holds "Existing". Revert byte for byte, and the test is green on the same stack.
   - mutation M3 (optional, UI side; it needs `ci/iris.sh build` before and after): drop `this.reload();` in `removeSource`'s error branch (`mcp-section.ts` L843). The fixed test goes red at L602. Revert byte for byte and rebuild. M3 is skipped if the lane's time is short: B13 already pinned this before the fix, and the fix does not change that pin.
3. Given the fixed test with no injection, under CPU load on lane C's stack, B13 passes at least 30 of 30 (the sum of the batches of the repeat harness).
4. The rest of the file is unchanged in behavior: the `ci/iris.sh live sign-in-2 --part k/24` part that holds `settings/mcp.spec.ts` (B1-B14 and the other files of the part) passes once, with no shim. `npm --prefix web run lint` passes. `git diff --name-only 9b9898a53` lists only `web/e2e/settings/mcp.spec.ts` and this spec, apart from the run's bookkeeping files.

## Spec Change Log

## Design Notes

**Why this is not a UI fault.**
- The section renders whatever its GET returns. `removeSource` reloads only after the DELETE has answered (L831, L843), and the `@for` tracks `source.ref`, so a reload with the same data keeps the row's DOM.
- The CI snapshots show the B13 route's list with no sources and no trace of the 404 Remove. The empty list came from the test's own mock, before the Remove.
- Nothing in `web/` changed between a passing commit and the failing ones: `git diff --quiet <c> HEAD -- web/e2e/settings/mcp.spec.ts web/src/app/settings/` is clean for `a1b4f2e2c` (passed) and for all four failing commits.
- (inference) The onset on the afternoon of Nov 15 comes from runner load. More concurrent lanes and runners slow the lazy chunk's mount relative to the heading.

**Why the flip moves into the DELETE route, and not a wait in the test.**
- Option A, chosen: flip `gone` at the 404's answer, as B10 does. The state change is ordered by the request flow itself. The 404 is the only answer after which the source should be missing, and the UI's reload can only start after that answer.
- Option B: before L599, wait for the row to be visible. This is also deterministic, but it rests on an argument the reader has to check: no other list GET is in flight after the row shows. That holds today, because `load()` is the only GET of a fresh section.
- Option C: make `reopen` wait for `page.waitForResponse` of the list GET. This fixes every reopen, but the other reopens have no state flip after them, so they are not racy. It adds a predicate over URLs to every step for no gain.
- Option A is the smallest change, and it matches the file's own convention.

**Why M1 is a faithful repro.** CI fails when the section's GET reaches the route after L599. M1 holds every list GET for 2 s before the B13 route sees it, and the heading is always visible before that GET is sent. So under M1 the old test always reads `gone` as true at step (d). The hold changes nothing else in the old test: every other step's click or assertion either waits on the UI, up to 60 s or 10 s, or does not depend on a reload.

**Why the repeat harness is a scratch shim.**
- `ci/iris.sh live <name>` passes its arguments to `docker/tests/test-<name>.sh`, and `test-sign-in.sh` takes only `--project` and `--part`; any other argument exits 2. So `--grep` and `--repeat-each` cannot be passed through `ci/iris.sh`.
- With `--part`, the unit also fails a run whose passed count differs from the part's count (L459-466), so a repeated or filtered run would read as a failure there.
- Story 32.6 solved the same problem with a scratch `npm` first on `PATH`. The shim replaces the unit's one browser call, and every other npm call goes to the real npm. Without `--part`, the unit has no count check and passes on Playwright's exit code.
- This needs no harness change, so the footprint stays one file.

**Lanes.** `mcp.spec.ts` is lane C's (Story 21.5, and B14 is from 21.9). No other lane's file is touched.

## Veto items

None. The change is to the test only: no product code, no public text, no stored data and no architecture change. If implement finds a UI fault after all, it stops with `## Clarification Needed`. That UI change, with its exact behavior, then becomes a Veto item for the Planner.

## Public text

None.

## Verification

Lane C only (Rule 21), never a dev slot. Another lane-C stage may hold the lane's stack, so the lock decides the order. Set these on every `ci/iris.sh` call:

```
<laneC> = OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'
```

Run one `ci/iris.sh` call per foreground Bash call, with `timeout: 600000`. Never raise the cap; split the repeats into batches instead. `$SCR` is the stage's scratchpad.

**The repeat harness: `ci/iris.sh live sign-in-2` with B13 alone, repeated.**
- `ci/iris.sh` has no `--grep` or `--repeat-each`. Write this scratch shim to `$SCR/bin/npm` (mode 755, never committed).
- The shim replaces only the unit's whole-project browser call. It runs B13 alone, `B13_REPEAT` times, beside `B13_BURN` busy loops on the host.
- Call `live` without `--part`, so that the unit's browser call matches the shim exactly and the unit has no part count check.

```bash
#!/usr/bin/env bash
[ "$*" = "--prefix web run e2e:sign-in-2" ] || exec "$REAL_NPM" "$@"
burn=""
trap 'for p in $burn; do kill "$p" 2>/dev/null; done' EXIT
i=0
while [ "$i" -lt "${B13_BURN:-0}" ]; do
  i=$((i + 1))
  sh -c 'while :; do :; done' &
  burn="$burn $!"
done
"$REAL_NPM" --prefix web run e2e:sign-in-2 -- settings/mcp.spec.ts --grep 'B13:' --repeat-each "${B13_REPEAT:-1}"
```

- Invoke it as: `<laneC> OCUTALON_RUN_TAG=e21dw1388i REAL_NPM="$(command -v npm)" B13_REPEAT=<N> B13_BURN=<n> PATH="$SCR/bin:$PATH" ci/iris.sh live sign-in-2`.
- The unit prints `SPEC settings/mcp.spec.ts <N> tests <s>s` and its PASS or FAIL line with `<k> passed`. The unit's log holds the throwaway's passwords (redacted in what it prints). Record only the counts, and keep any `test-results/` output in the scratchpad.
- Load: set `B13_BURN` to the host's core count (`sysctl -n hw.ncpu`). Optionally, run burners in the Docker VM as well: `docker run -d --rm --cpus 1` on an image that is already local, running `sh -c 'while :; do :; done'`, removed afterwards. Record the load used.

**Commands:**
- (once) `cd web && npm ci` (Task 0 item 1).
- (once) `<laneC> OCUTALON_RUN_TAG=e21dw1388i ci/iris.sh build`.
- (once) Task 0 items 2-4, on the unchanged tree.
- (once) Make the edit. Then run `npm --prefix web run lint`: exit 0.
- (batches) Fixed test plus M1, `B13_REPEAT>=3`, `B13_BURN=0`: all green.
- (batches) Fixed test, no injection, `B13_BURN=<cores>`: batches sized by Task 0 item 3, until the total is at least 30. Expected: 30 of 30 green.
- (optional) Old test, no injection, under the same load, one or two batches. Record the counts as they come. The local rate is unknown, so no red is required here; M1 is the Rule 19 red.
- (once) M2, then M3 if time allows, as under Acceptance 2. Revert each byte for byte, and check that `git status --short` and `git diff --stat` are as they were before the mutation.
- (once, without the shim) `<laneC> OCUTALON_RUN_TAG=e21dw1388i ci/iris.sh live sign-in-2 --part <k>/24`: pass.
- (once) `git diff --name-only 9b9898a53`: only the test file and this spec (and bookkeeping).
- (once, at the end, also after a failure) `<laneC> OCUTALON_RUN_TAG=e21dw1388i ci/iris.sh teardown`. Then remove `$SCR/bin/npm` and confirm that no burner process or container is left.

**Mutations:** M1, M2 and M3 as under Acceptance Criteria. Record each as `mutation: <change> -> <test that went red or green> ("<assertion message>" or the L600 timeout)`. Revert it byte for byte (`cmp` against a copy), then run green again on the same stack.

**CI evidence (plan stage, read from the hits' logs and artifacts; the test and UI files are identical at every hit and at HEAD):**

| Run | Branch, commit | Job, runner | Failure |
|-----|----------------|-------------|---------|
| 43733825684 | feature `475a86e44` | shards-4, ocutalon-ci-16 (machine ocutalon-ci-d) | L600 click, 60 s |
| 43737922579, attempt 1 (the 1.0.11 main push; green on rerun) | main `b2c3f6f68` | shards-4, ocutalon-ci-55 | L600 click, 60 s |
| 43738026674 (the third hit) | feature `b337f61d9` | shards-4, ocutalon-ci-29 | L600 click, 60 s |
| 43738072955, attempt 1 (a fourth hit, found in the scan; green on rerun) | OCT-epic25 `8fee7092f` | shards-4, ocutalon-ci-10 | L600 click, 60 s |

- Each run's `playwright-results-shards-4-1` holds B13's `error-context.md`, and all four snapshots are the same:
  - `zzb13` is listed, with `zz_a` and `zz_b` and their "Use as a source" buttons;
  - "Your sources" shows only "No sources yet.";
  - there is no `[data-error="sources"]`, no "Saved" and no dialog.
- The traces stayed on the runners (Story 11.27) and were not needed.
- The sign-in-2 suite ran 897-967 s in a 1182-1186 s budget, and the rest of the unit was green (245 passed).

**Task 0 records (implement stage, lane C, run tags e21dw1388i*):**
- Item 1: `cd web && npm ci` done (no browser install needed). `ci/iris.sh build` ok.
- Item 2: the part holding `settings/mcp.spec.ts` is `18/24` (PART 18/24: 2 of 24 spec files, 20 of 246 tests: settings/email.spec.ts settings/mcp.spec.ts); 17 and 19 do not hold it.
- Item 3: shim run with `B13_REPEAT=1` on the unchanged tree: one `live sign-in-2` call took 154 s wall clock in all (the set-up about 150 s; the unit's `MEASURED live:sign-in-2 suite budget` of about 1335 s is the unit's own allowance for the whole suite, not a measurement; `MEASURED wait test-sign-in.sh:242 102 s` is the first start's wait), B13 itself 2.8 s (suite 3 s). One batch of 30 therefore costs about 150 s + 30 x 3 s, well inside the cap, so the batches are sized by CPU load rather than time.
- Item 4: old test plus M1 (2 s hold on every `GET /settings/mcp`), `B13_REPEAT=2`, no load: 2 of 2 red, `TimeoutError: locator.click: Timeout 60000ms exceeded` waiting for `getByRole('region', { name: 'Your sources' }).getByRole('button', { name: 'Remove the source Existing' })`. The `error-context.md` snapshot shows `zzb13`, `zz_a` and `zz_b` with "Use as a source", and "Your sources" with "No sources yet.", the CI signature. M1 reverted byte for byte (`cmp` against the backup).

**Implement-stage results (lane C, no dev slot; each stack torn down by its unit):**
- Edit: `web/e2e/settings/mcp.spec.ts` only (B13's DELETE route sets `gone = true` at a 404; the old `gone = true` before the click removed). `npm --prefix web run lint`: exit 0.
- mutation: M1 (2 s hold on every `GET /settings/mcp`), old test -> B13 red 2 of 2 at the "Remove the source Existing" click (`locator.click: Timeout 60000ms exceeded`, snapshot "No sources yet.", no `[data-error="sources"]`).
- mutation: M1, fixed test, `B13_REPEAT=3` -> B13 green 3 of 3 (about 16 s each, far inside its 240 s).
- mutation: M2 (drop the new `gone = true` from the DELETE route) -> B13 red at "and the source leaves the list" (Expected: 0, Received: 1); reverted byte for byte (`cmp`), then green again (30 of 30 below).
- mutation: M3 skipped (optional, UI side; B13 already pinned the reload before the fix).
- Repeats, fixed test, no injection, `B13_BURN=16` (all 16 host cores busy): 30 of 30 green in one batch (the unit's `SPEC ... 30 tests 142s` is its suite timer, and Playwright's `30 passed (3.0m)` is its own run total including worker start). No Docker VM burners. One more no-load run, 1 of 1 green. The old test under load was not run (optional).
- Regression, no shim: `ci/iris.sh live sign-in-2 --part 18/24`: "test-sign-in-2 part 18/24: all checks passed" (20 passed, email.spec.ts 6 and mcp.spec.ts 14).
- `cd web && npm test`: 518 suites, 2124 pass, 0 fail. `bash docker/tests/test-boundaries.sh`: all rules passed.
- Shared surfaces: none (one test's own mock state).

**QA records (QA stage, lane C, run tags e21dw1388q*; no test change was needed):**
- Scope: the same race (a mock state flipped after a reload, before the lazy section's own GET) in `web/e2e/settings/mcp.spec.ts`, and in the sibling settings specs. Verdict per candidate:
  - B13 steps (a)-(c), the three earlier `reopen()` calls (L573, L581, L595 as of `7150eb0f5`): safe. After each, the only flips are `save` and `removal`, and those are read only inside the POST and DELETE routes, which the test's own click starts. `gone` does not change until (d), so a late list GET answers the same list at any time.
  - B13 step (d): fixed. The click needs the row, the row needs the list GET answered (with `gone` false), and the DELETE can only follow the click, so the flip in the DELETE route comes after every GET that the test depends on. The reload GET after the 404 starts only after that answer.
  - B10: safe. It already flips `gone` inside its DELETE route and never reloads.
  - B8, B9 (`gets` counters): safe. The counters are bumped by the requests themselves, and each assertion waits on the UI that the earlier answer made.
  - B3 (L167) and B14 (L656), `page.reload()` with no mock: safe. No route state changes after the reload; B14's `/classify` route is unrouted before it.
  - B1, B2, B4-B7, B11, B12: no reload or no state flip: safe.
  - `web/e2e/support/mcp.ts`: fixtures only (seed, drop, leftovers). It has no `reopen` and no route.
  - Sibling specs, no true race, so nothing to report as a finding: `email.spec.ts` L175, `on-call.spec.ts` L205, `settings.spec.ts` L170, L599 and L834 reload against the real server with no `page.route` state that changes afterwards (the S13c route only decorates a real GET); `deep-link.spec.ts` reloads wait for the section's own GET with `waitForResponse` and flip nothing; `webhooks.spec.ts` WS4 flips `failing = false` only after the load error and Retry are visible, which means the failing GET has been answered (WS3's `mode` is read only by POST).
- Determinism, both orderings of the list GET and the 404 Remove (scratch edits, each reverted byte for byte with `cmp`, shim kept in scratch and deleted; `B13_REPEAT=5`, `B13_BURN=0`; each run 5 of 5 green, about 15 s per B13):
  - mutation: M1 (hold every `GET /settings/mcp` 2 s), fixed test -> green 5 of 5 (the GET comes late, after the Remove button is clicked or not at all needed).
  - mutation: M4 (hold the `DELETE /sources/zzsrc13` 2 s, the GET immediate), fixed test -> green 5 of 5 (the Remove answers late, and the reload GET still follows the answer).
  - Together with the implement stage's 30 of 30 with no injection (GET at its natural time), the fix holds for the GET before and after any step the test takes, and for a DELETE that answers late.
- No new pin: nothing was added to the test, so no new `mutation:` line beyond M1 and M4 above, which are scratch checks of the existing pin.
- Findings outside `mcp.spec.ts`: none.
- Runs: `ci/iris.sh build` ok; two shim runs (M1, M4) as above. Teardown run for each tag; no stack of this stage is up.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 7 findings - high 0, medium 0, low 6, false 1, maybe-false 0 (the edge-case layer reported none)
- findings:
  - `[low]` `[patch]` Auto Run Result still read "ready-for-dev (plan stage)" while the frontmatter said `in-review` (blind-hunter) - rewritten at finalize.
  - `[low]` `[patch]` Verification figures (154 s versus a 1335 s budget, 142 s versus 3.0m) were unexplained (blind-hunter) - each figure now says what it measures.
  - `[low]` `[reject]` The 404 flip is keyed on `removal.status` and B13's header comment does not mention it, B10 not aligned (blind-hunter) - the status key is the spec's design, the route comment states the contract, and a header or B10 edit is outside the one-file, four-line footprint; no named harm.
  - `[false]` `[reject]` AC3 has no `mutation:` line (verification-gap) - AC3 is a repeat-count criterion; the pinning tests are AC1 (M1) and AC2 (M2), both recorded with a red.
  - `[low]` `[reject]` M3 not run (verification-gap) - optional in the spec; B13 already pinned the reload (the reload row 3 assertion), and the fix does not change that pin.
  - `[low]` `[patch]` Stale Auto Run Result (verification-gap) - same root cause as the first row.
  - `[low]` `[reject]` Evidence is local with an injected delay, not from CI; old test under load not run (intent-alignment) - descriptive; CI cannot be run from this stage, M1 reproduces the CI signature and the optional load run of the old test was not required.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: B13 (Story 21.5's source form) raced its own mock: `gone` flipped before the reopened section's list GET reached the route, so the list was empty and the Remove click timed out. The `DELETE /sources/zzsrc13` route now sets `gone = true` when it answers the 404, as B10 does, and the old `gone = true` before the click is removed. Test only; no UI change.
- Files changed: `web/e2e/settings/mcp.spec.ts` (+4 -1) and this spec.
- Review: 7 findings (high 0, medium 0, low 6, false 1); patches applied: 3 spec-prose rows (stale result section twice, unexplained figures); deferred: none; rejected: 4 (one false, three low), each with its reason in the triage log.
- Follow-up review recommended: false (no patched high, no patched medium).
- Verification: see Verification above. Old test plus M1 red 2 of 2; fixed test plus M1 green 3 of 3; M2 red at "and the source leaves the list"; 30 of 30 green under 16 busy cores; `ci/iris.sh live sign-in-2 --part 18/24` all checks passed (20 tests); lint exit 0; `npm test` 2124 pass, 0 fail; `test-boundaries.sh` all rules passed.
- Residual risks: the evidence is local (an injected 2 s hold stands in for CI runner load); M3 and the old test under load were not run.
