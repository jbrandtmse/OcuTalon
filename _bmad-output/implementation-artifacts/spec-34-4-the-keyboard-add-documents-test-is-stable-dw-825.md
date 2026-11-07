---
title: 'Story 34.4: The keyboard add-documents test is stable (DW-825)'
type: 'bugfix'
created: '2026-11-06'
status: 'ready-for-dev'
baseline_revision: '80c93ef39f25cd869fbbeb86756767b36f94bac4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/34-4/cause.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** D5 in `web/e2e/documents/documents.spec.ts` ("Add documents works by keyboard, and a .png is refused with its reason") now and then waits 30 s for a `filechooser` event after Enter on the focused Add documents button and times out (DW-825; red on 3 heads in about 6 h, each green on one rerun). The cause is recorded in `evidence/34-4/cause.md`: Playwright 1.64.1 turns file-chooser interception on fire-and-forget when the first `filechooser` listener is added, and D5 adds it in the same tick as the Enter press, so the key can reach Chromium first. The product is not at fault.

**Approach:** A test-only fix in D5: register a `filechooser` listener at the start of the case, before the page is opened, so interception is on long before the press; keep `page.waitForEvent('filechooser')` after the press as the required proof that Enter opened the chooser; and use the early listener to assert that Enter opened exactly one chooser. Every other pin stays as it is.

## Boundaries & Constraints

**Always:**
- D5 still proves, in this order: Tab reaches Add documents (`toBeFocused`); Enter on it opens the file chooser (the `waitForEvent('filechooser')` registered before the press is awaited, and its chooser is the only way the file is set); the .png goes through the real route and comes back 400 with `bad_document wrong_type`; its row reads the wrong-type text, has no Remove button, and the refusal is announced exactly once (the poll to 1, then still 1 after the 2.5 s wait).
- A comment at the early listener states the contract (why it is registered before the page opens), citing DW-825. Comments state the contract, never review history (Rule 14). Non-ASCII in code only as escapes.
- D5 keeps its title, so its listing and its `SPEC` line in the harness are unchanged.

**Never:**
- No product code (`web/src/**`), no harness, config, CI or fixture change; the footprint is `web/e2e/documents/documents.spec.ts` only (an append to `web/e2e/support/*` is allowed but not needed, see Design Notes).
- No timeout added, raised or removed anywhere (D5's waits keep the fixtures' defaults); a longer timeout is not a fix.
- No pin of D5 deleted, loosened or moved after a step it guarded; no `test.fail`, retry, `test.slow` or skip; no other case (D1-D4, D6-D13) changed.
- The file must not be set through `fileInput(page).setInputFiles` in D5 (that would bypass the chooser Enter opened).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Keyboard add, interception armed | Listener registered before the page opens; Tab, then Enter on Add documents | One `filechooser` event after the press; `.png` set through it; route answers 400 `bad_document wrong_type`; row shows the wrong-type text, no Remove, announced once; chooser count 0 before Enter and 1 at the end | No error expected |
| Enter opens no chooser (a real defect) | The button's click no longer opens the picker | D5 fails at `page.waitForEvent('filechooser')` (default wait, unchanged) | Red names the waitForEvent call: a real page defect |
| Enter opens two choosers | The control opens the picker twice | D5 fails at the exactly-one count assertion | Red names the chooser count |

</intent-contract>

## Code Map

- `web/e2e/documents/documents.spec.ts` -- D5 at 138-160: `recordAnnouncements(page)` 140, `openDocuments(page)` 141, focus `main.documents` + Tab 142-143, `toBeFocused` 145, **`const chooser = page.waitForEvent('filechooser')` 146** (the first `filechooser` listener: interception is enabled here, in the same tick as the press), `posted(page)` 147, `keyboard.press('Enter')` 148, `(await chooser).setFiles(...)` 149, the 400 / `bad_document wrong_type` pins 150-153, row status / no Remove / announced once 154-159 (the 2.5 s `waitForTimeout` at 158 is the existing window for the exactly-once checks). `posted()` 69, `openDocuments()` 58-66, `fileInput()` 31 (D7/D8 only), `WRONG_TYPE` 21.
- `web/e2e/support/page.ts` -- `recordAnnouncements` 56: the pattern this fix follows (instrumentation armed on the page before `openDocuments` loads it, read later). Read-only.
- `web/e2e/support/fixtures.ts` -- the `test`/`expect` every spec imports; per-test `page` (so a listener on it never leaks to another test) and the default action wait that `waitForEvent` keeps. Read-only.
- `web/src/app/documents/documents-page.ts:46-47` -- the control under test: `<button ... (click)="picker.click()">` and `<input #picker type="file" multiple hidden ...>`; nothing async between them (cause.md). Read-only: no product change.
- `web/node_modules/playwright-core/lib/coreBundle.js` (1.64.1) -- `ChannelOwner.addListener` → `_updateSubscription(event, true)` → `updateSubscription(...).catch(() => {})`, not awaited (cause.md). Read-only evidence.
- `_bmad-output/implementation-artifacts/evidence/34-4/filechooser-race-repro.mjs` -- stack-free model of D5's sequence: `MODE=old` misses about 1.8 % (7 of 390 on a loaded host), `MODE=armed` 0 of 80; 20 iterations take about 3 s. Lead's evidence: run it, do not edit it.
- `docker/tests/test-sign-in.sh` -- the `live:sign-in` unit runs `npm --prefix web run e2e` with only `--project` / `--part`; it has no test filter or repeat option (relevant to the lead's proof, not to implement).
- Only D5 uses `filechooser` in `web/e2e`, `web/e2e-online`, `web/e2e-rehearsal` and `web/e2e-capture` (grep), so no other spec carries the same race.

## Tasks & Acceptance

**Execution:**
- `web/e2e/documents/documents.spec.ts` -- in D5 only: as the first statements of the case (before `recordAnnouncements` and `openDocuments`), declare a chooser counter and register `page.on('filechooser', ...)` that increments it, with a contract comment citing DW-825; just before the existing `waitForEvent('filechooser')`, assert the count is 0 ("no chooser before Enter"); keep lines 146-159 as they are; after the final 2.5 s wait, assert the count is 1 ("Enter opened exactly one chooser"); adjust D5's doc comment (138) to mention "exactly one" if it helps. -- arms interception before the press (the cause) and tightens the Enter-opens-chooser pin without loosening any other.

**Acceptance Criteria:**
- Given D5 as changed, when the case starts, then a `filechooser` listener is registered on `page` before the page is opened (before `recordAnnouncements` / `openDocuments`), with a comment stating why and citing DW-825, and no timeout anywhere in the file differs from the baseline (`git diff` shows no `timeout` change).
- Given the README account on the Documents page with focus on `main.documents`, when Tab and then Enter are pressed, then `toBeFocused` holds on Add documents, the `waitForEvent('filechooser')` registered before the press resolves, the chooser count is 0 before the press and exactly 1 after the case's final 2.5 s wait, and the file reaches the route only through that chooser.
- Given the .png set through that chooser, when the real route answers, then D5 still pins status 400, `bad_document wrong_type`, the row's `WRONG_TYPE` status, no Remove button, and the announcement count 1 by poll and still 1 after 2.5 s: every pin of the baseline D5 is present and unweakened (diff check).
- Given the changed spec, when the stack-free checks run, then `npm --prefix web run lint` exits 0, `npm --prefix web test` passes, and Playwright lists D5 under its unchanged title.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-22 (testing and CI: the browser specs, the lead's proof on a throwaway, never a slot), AD-29 (Lane B's files: the web app's e2e specs), AD-21 (the documents route whose refusal D5 pins; unchanged). Spine rows: Consistency Conventions "Tests" (Playwright specs under `web/e2e/`) and Stack "Playwright 1.64.x" (the version whose `addListener` is fire-and-forget). No AC contradicts an AD's Rule; no spine change.

**Integration ACs (Rule 1):** test-only story; it introduces no service, module or shared component. No consumers in this story, and none later. **Consumes:** the Documents page and `POST /ocutalon/api/v1/documents` as built by Story 34.2 (exercised for real, not mocked). **Consumed-by:** none.

**Extend, don't copy (Rule 2):** no helper is added. The fix is three statements inside D5, the only `filechooser` user in the e2e trees; a shared helper for one caller would be a speculative abstraction. It follows `recordAnnouncements` (`support/page.ts:56`): instrumentation armed before the page loads, read later.

**Ledger inbox (Rule 17):** DW-825 (routed to this story) is addressed by all four ACs; none declined.

**Why the early listener fixes it (from cause.md):** interception is enabled by the first `filechooser` listener, asynchronously. Registered before `openDocuments`, the enable has the whole sign-in and navigation (seconds) to land, so by the Tab and Enter it is on; `waitForEvent` then adds a second listener, which sends no new subscription. The repro's `MODE=armed` is this ordering (0 of 80).

**Shape (5-10 lines, illustrative):**

```ts
let choosers = 0;
// DW-825: interception of file choosers starts when the first listener is added, asynchronously, so it is armed here, before
// the page opens; a chooser opened by the Enter below is then always caught by the waitForEvent and counted.
page.on('filechooser', () => { choosers += 1; });
...
expect(choosers, 'no chooser before Enter').toBe(0);
const chooser = page.waitForEvent('filechooser');
...
expect(choosers, 'Enter opened exactly one chooser').toBe(1);
```

**Decided in-stage:**
1. **The exactly-one assertion is added** (the ruling's "consider"). It is a strengthening, uses the 2.5 s window D5 already has, and catches a double-open the old D5 missed. The zero-before check proves the counted chooser came from the Enter.
2. **No shared helper** (above); the footprint stays one file.
3. **Who demonstrates which mutation.** The implement stage demonstrates the ordering mechanism stack-free with the repro (`MODE=old` misses, `MODE=armed` none) and runs only stack-free checks. D5's own red under each mutation needs a live stack, which this story's arrangement leaves to the lead's run (Verification, lead-owned). The implement stage records both `mutation:` lines as planned; the lead fills in the observed result.

## Verification

**Commands (implement stage, stack-free):**
- (loop) `npm --prefix web run lint` -- expected: exit 0 (`tsc -p tsconfig.e2e.json` over every e2e spec, then `node --check` of the scripts; about 7 s).
- (loop) `npx --prefix web playwright test --config web/playwright.config.ts --list --project=chromium documents/documents.spec.ts` -- expected: `Total: 13 tests in 1 file`, with `D5: Add documents works by keyboard, and a .png is refused with its reason` listed (about 2 s; no stack needed).
- (once) `npm --prefix web test` -- expected: every test passes, 0 fail (1494 tests at the baseline, about 13 s; includes `route-cleanup.test.mjs`, which checks every spec imports the shared fixtures).
- (once) `MODE=old N=300 node _bmad-output/implementation-artifacts/evidence/34-4/filechooser-race-repro.mjs`, then `MODE=armed N=300 node _bmad-output/implementation-artifacts/evidence/34-4/filechooser-race-repro.mjs`, one per call -- expected: `old` reports `missed` of at least 1 (inference from about 1.8 %: about 5 expected, and a 0 has a probability under 1 %; on a 0, run `old` once more and record both), `armed` reports `missed=0`. Each well under a minute.
- (once) `git diff --stat` and `git diff -U0 -- web/e2e/documents/documents.spec.ts` -- expected: only that file; only D5's lines added or changed; no line with `timeout` changed; every baseline D5 assertion still present.

**Shared surfaces:** none. D5 seeds no row; the refused .png never writes an `OcuTalon.Data.Upload` row (refusals are enforced before any write); the listener lives on the test's own `page` and closes with it.

**Standing criterion (Rule 19):** every test added or changed passes on a fresh environment, in either order.

**Mutations (one per AC group; red observed by the lead on the stack, mechanism shown by implement with the repro):**
- AC 1-2 (interception armed before the press): move the early `page.on('filechooser', ...)` back to just before `keyboard.press('Enter')`, in the same tick as the `waitForEvent` (the old order) → the repro's `MODE=old` shows misses where `MODE=armed` shows none, and the lead's repeat run of the mutated D5 shows at least one `page.waitForEvent: Timeout` red. Planned; the lead appends the observed red (test, line, run) here after its run.
- AC 2-3 (a chooser opened by Enter is required): drop `await chooser` and its `setFiles` → no file is set, no POST is made, and D5 goes red at `await answer` (`posted()`'s `page.waitForResponse` times out); with the count assertion kept, a page whose Enter opens no chooser also goes red at `waitForEvent` or at `choosers` toBe(1). Planned; the lead appends the observed red (test, line, run) here after its run.

**Lead-owned proof (verification arrangement (b); not a stage command):**
- On lane D's throwaway (`OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-d`, `OCUTALON_TEST_WEB_PORT=52804`, the lead's own run tag), under a documented load: the new D5 passes 20 of 20 with `--repeat-each=20`; the old D5 (baseline `80c93ef3`) fails at least once under the same repeat and load; then full CI green on every workflow. `test-sign-in.sh` takes no test filter or repeat option, so how D5 alone is run with `--repeat-each=20` is the lead's arrangement; no harness change is in this story's footprint.
- Note for the old-D5 red (inference): at the repro's about 1.8 % miss rate, 20 repeats show at least one miss only about 31 % of the time; the CI rate under the browser job's load is unmeasured. Expect to need heavier documented load or more than one round of 20.
- The two mutation runs above, each on the same stack, then reverted (`git status --short` and `git diff --stat` unchanged).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
