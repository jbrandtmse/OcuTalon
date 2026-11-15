---
title: "Story 25.8: Epic 25 burn-down: the web gap-fill (Usage withdraws its stale error, and a viewer gets no file-reply add or Documents drop)"
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: '810f5adcbaa75a582e2be7ba1960ff0c2f1027db'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Five small web gaps were left where Epic 25's stories meet. The Usage page announces its failed read and never withdraws it, so a queued error can still be spoken after a successful Retry (DW-1120). The `lastSpoken` guard of `Announcer.retract` has only a source-regex pin (DW-1121). History's H15 presses Retry a second time without waiting for any sign that the page handled the refused read (DW-1122). A viewer still sees **Add to documents** on an older file reply, which the server refuses with 403 `read_only` (DW-1386). A viewer still gets the Documents page's drag outline, and a dropped file is swallowed with no message (DW-1387).

**Approach:** Usage withdraws its error through `Announcer.retract` on the next answer, as History does. The guard moves into the framework-free `AnnounceQueue`, where a node test pins it behaviourally. History and Usage count their handled failures in a `data-failures` attribute, which gives H15 and the new Usage test a page-side precondition. `FileReply` hides the add button for a viewer, and the Documents page binds `FileDrop`'s `[active]` to `!viewer()`. Everything uses the snapshot's `viewer` flag (Story 25.4), which Story 26.4 keeps.

## Boundaries & Constraints

**Always:**
- Lane A changes only the files listed in AD-33's Story 25.8 bullet, which is the Code Map below. The ownership tables don't change.
- The viewer test is `isViewer(this.live.snapshot())` (`shared/viewer-view.ts`). Do not add a new role check.
- The Announcer's speaking path stays as it is: the queue's cadence, its joining, "{n} new updates", the 1 s gap and the three-in-2-s limit. The only writers of the live region are `speak(text)` and the new `clear()`.
- `retract(text)` empties the region only when `text` was the last text spoken, alone and not joined with others, and it is not empty.
- New web code stays in lazy chunks where it can. The initial bundle stays at or under 921,000 bytes (`initial-bundle.test.mjs`).
- Every test that is added or changed creates its own state, removes it, and passes in either order. Each AC's pinning test has a demonstrated mutation in `## Verification`.
- Source keeps ASCII escapes, and comments state the contract only (Rule 14).

**Never:**
- No new user-visible string, no change to any route, IRIS class or role, and no widening of the user role. `data-failures` is a test anchor, never text.
- No message or replacement control for the hidden button or the inactive drop. The drop is left to the browser's own handling, as the chat already does for a viewer.
- Do not plan anything that needs Story 26.4's new roles.
- Never touch `ocutalon-aihub-test`, any `ocupilot*` container, `iris-community-edition`, or another lane's slot or stacks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Usage: queued error withdrawn (DW-1120) | Frozen page clock. Read 1 fails, and ERROR ("Couldn't load your usage.") is spoken alone. Retry, read 2 fails while inside the 1 s gap, so ERROR waits in the queue. Retry, read 3 answers | The table shows. After 1.5 s more on the page clock, ERROR has been announced exactly once and the live region is empty | none |
| Usage: retry still failing | Retry fails again with no answer (U14) | Each failure is still announced (U14 unchanged) | none |
| Guard: other text spoken (DW-1121) | The queue spoke "A." alone; `retract("B.")` | The region keeps "A.", and `clear` is not called | none |
| Guard: own text spoken alone | The queue spoke "A." alone; `retract("A.")` | `clear` is called once, so the region is empty. A second `retract("A.")` does nothing | none |
| Guard: joined text | "A. B." was spoken as one text; `retract("A.")` | The region keeps "A. B." | none |
| H15 precondition (DW-1122) | The second Retry fails | Before the third press, `[data-part="history-failed"]` shows `data-failures="2"` and ERROR has still been announced only once | none |
| Viewer file reply (DW-1386) | A real viewer whose snapshot holds a `read 1, addable 1` document turn and a photo turn with a saved caption | Both `app-file-reply` mount. No **Add to documents** shows. **Saved to memory** shows once. A POST of the ref to `/v1/documents` is 403 `read_only` | none |
| Viewer Documents drop (DW-1387) | A real viewer on `#/documents`. A `dragover`, then a `drop`, of a transfer that carries a PDF | Neither event is cancelled (`defaultPrevented` false). No `dragging` class, and no POST to `/v1/documents` | none |
| User Documents drop | A user who is not a viewer (D6) | The outline shows and the drop is taken, as before | none |

</intent-contract>

## Code Map

- `web/src/app/shared/announce-queue.ts:32-42,77-85,124-128` -- `AnnounceQueueOptions`, `retract` and `say`. Add `clear: () => void` (empties the region). Keep `lastText`, set in `say`. `retract` removes the waiting copies and then, if `text !== '' && lastText === text`, sets `lastText = ''` and calls `clear()`. Update the module doc.
- `web/src/app/shared/announcer.ts:19-51` -- Drop `lastSpoken`. Pass `clear: () => void this.live.announce('', 'polite')`. `retract(message)` becomes `this.queue.retract(message)`. Keep exactly two `this.live.announce(` calls (`announce-focus-sources.test.mjs:64-65`).
- `web/src/app/usage/usage-page.ts:79,418,457-478` -- the failed block, `failed` and `load()`. Add `failures = signal(0)` and `[attr.data-failures]="failures()"` on `usage-failed`. On an error for the current ask, increment `failures` and announce. On an answer for the current ask, if `failed()` was true, set `failed` false, set `failures` to 0 and call `retract(USAGE_TEXTS.error)`. Update the doc comment.
- `web/src/app/history/history-page.ts:147,181,425,543-559` -- both `history-failed` blocks, `failed`, `arrived` and `refused`. Make the same `failures` change. `retract` is already in place (the pattern being extended).
- `web/src/app/chat/file-reply.ts:68-83` -- Inject `LiveState`. Add `viewer = computed(() => isViewer(this.live.snapshot()))` and pass it to `controlsOf`. Add a doc line saying a viewer gets no button and keeps the chip. The component is a lazy chunk; `LiveState` and `viewer-view` are already in the main bundle.
- `web/src/app/chat/file-reply-view.ts:31-34` -- `controlsOf(fileRead, savedCaption, viewer: boolean)`: `add` also needs `!viewer`, and `saved` ignores it.
- `web/src/app/documents/documents-page.ts:57-62` -- `<main ... appFileDrop [active]="!viewer()" (files)=...>`. `viewer` is at `:199`. Keep the `addFiles` early return. Update the doc comment.
- `web/scripts/announce-queue.test.mjs:17-30,287-328` -- `setup()` gains a region model: `speak` sets it, and `clear` empties it and counts. Add the guard cases from the Matrix.
- `web/scripts/announce-focus-sources.test.mjs:60-67` -- Replace the retract regex (`:66`) with pins that `retract` delegates to `this.queue.retract(message)` and that `clear` is `this.live.announce('', 'polite')`. The guard's behaviour is now the queue test's job.
- `web/scripts/viewer-sources.test.mjs:26-41,99-105` -- Add `'chat/file-reply.ts'` to `GUARDED`. In the documents case, add `appFileDrop\s*\[active\]="!viewer\(\)"`.
- `web/scripts/file-reply-view.test.mjs:39-58` -- Give every existing `controlsOf` call `false`. Add the viewer cases.
- `web/e2e/support/clock.ts` -- Move `stepUntil` here from `history.spec.ts:530-536` (Rule 2) and export it.
- `web/e2e/support/files.ts` (new) -- Move `taken` and `chatItem` here from `files/files.spec.ts:51-60,343-358`, and add `fileTransfer(page, name)` (a PDF `File` in a `DataTransfer`).
- `web/e2e/files/files.spec.ts` -- Import those helpers. The tests themselves don't change.
- `web/e2e/history/history.spec.ts:538-575` (H15) -- Import `stepUntil`. After `failed === 2`, use `stepUntil(... data-failures === '2', 500, ...)`, then expect `announcements(ERROR) === 1`. The rest stays the same.
- `web/e2e/usage/usage.spec.ts` -- Add U16, built like H15, after U15 (`:471`). Use `recordAnnouncements`, `page.clock.install()`, sign in, route `USAGE` (reads 1 and 2 return 500, read 3 is real), `freeze`, then hash `#/usage`. The reads are counted by the route; the expectations are in the Matrix. The region is `.cdk-live-announcer-element`. After the first failure its text must be exactly ERROR, so it was spoken alone.
- `web/e2e/sign-in/viewer.spec.ts` -- Add V4 (file reply) and V5 (Documents drop), signed in as `fixtureUser('VIEWER')`. V4 stubs `chat` with `changeSnapshot` (`support/api.ts`) and keeps the real `viewer: true`. Update the header list.
- Read only: `shared/file-drop.ts:13-36` (with `active` false no handler is bound), `chat/chat-panel.ts:397-398` (the precedent, inactive for a viewer), `shared/viewer-view.ts`, `e2e/support/page.ts:56-81`, `e2e/documents/documents.spec.ts:173-190` (D6).

## Tasks & Acceptance

**Execution:**
- `web/src/app/shared/announce-queue.ts`, `announcer.ts` -- Move the guard as the Code Map says. -- DW-1121: a guard that node can run.
- `web/scripts/announce-queue.test.mjs`, `announce-focus-sources.test.mjs` -- Add the guard cases and swap the regex. -- DW-1121.
- `web/src/app/usage/usage-page.ts` -- Retract on an answer and count failures. -- DW-1120.
- `web/src/app/history/history-page.ts` -- Count failures. -- DW-1122 (the page-side signal).
- `web/e2e/support/clock.ts`, `web/e2e/history/history.spec.ts`, `web/e2e/usage/usage.spec.ts` -- `stepUntil` moves to support, H15 gets its precondition, and U16 is added. -- DW-1122, DW-1120.
- `web/src/app/chat/file-reply-view.ts`, `file-reply.ts`, `web/scripts/file-reply-view.test.mjs`, `viewer-sources.test.mjs` -- The viewer gets no add button, the file joins `GUARDED`, and the node cases are added. -- DW-1386.
- `web/src/app/documents/documents-page.ts` -- `[active]="!viewer()"`, pinned in `viewer-sources.test.mjs`. -- DW-1387.
- `web/e2e/support/files.ts`, `web/e2e/files/files.spec.ts`, `web/e2e/sign-in/viewer.spec.ts` -- Move the helpers and add V4 and V5. -- DW-1386, DW-1387.

**Acceptance Criteria:**
- AC1 (DW-1120): Given the Usage page announced its failed read and a second failure waits in the queue, when a later read answers, then the page withdraws the error through `Announcer.retract`: on the frozen page clock ERROR is announced once and the region is empty (U16).
- AC2 (DW-1121): Given the queue spoke one text, when another text is retracted, then the region keeps the spoken text and `clear` is not called. Only a retract of the text spoken alone empties it (the `announce-queue.test.mjs` "retract guard" cases, which are behavioural).
- AC3 (DW-1122): Given H15's second Retry fails, when the test continues, then it first waits on `data-failures="2"` and on ERROR still being announced only once, so a dropped or reversed second failure turns H15 red.
- AC4 (DW-1386): Given a viewer and an older `addable` file reply, when the reply renders, then there is no **Add to documents** and the Saved to memory chip stays (V4 and the `controlsOf` cases). `chat/file-reply.ts` is in `GUARDED`.
- AC5 (DW-1387): Given a viewer on the Documents page, when files are dragged over it or dropped on it, then no handler takes them, no outline shows and nothing is posted (V5 and the viewer-sources pin). D6 stays green for a user.
- AC6: Given the change, when `npm --prefix web test` runs, then `initial-bundle.test.mjs` (at most 921,000 bytes), `ux-strings.test.mjs` and `lazy-routes.test.mjs` pass. `git diff --stat` shows only the AD-33 file list, with no new user-visible string.

## Spec Change Log

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 29 findings — high 0, medium 0, low 7, false 22, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: a viewer's drop leaves the browser's default handling — the intent says so ("left to the browser's own handling", as the chat does for a viewer).
  - `[low]` `[reject]` Blind: support/files.ts header says files.spec.ts uses the helpers — it does use `taken` and `chatItem`; the header is accurate enough and a comment edit is not worth a pass.
  - `[low]` `[reject]` Blind: V5 ends on `waitForTimeout(500)` — a dwell for a negative check on a real HTTP request; removing it would weaken the check.
  - `[low]` `[reject]` Blind: `retract` after `dispose()` can still clear — the Announcer is root-provided and disposed on destroy, so nothing retracts after it.
  - `[false]` `[reject]` Blind: a message pushed with spaces cannot be retracted — `push` trims before queueing, so `lastText` is the trimmed text.
  - `[false]` `[reject]` Blind: the Announcer guard is only regex-pinned — the spec (Code Map) replaces the old regex with delegation pins; the guard's behaviour is the queue test's, and U16 checks the real region.
  - `[low]` `[reject]` Blind and Verification gap: the `data-failures` reset has no test that observes it — a test anchor; every consumer waits only on `'2'` after the first failure; a test would need a second failure after an answer.
  - `[false]` `[reject]` Blind: `FileReply.add()` has no viewer guard — the control is hidden and the server refuses with 403 `read_only` (V4 posts the ref to show it).
  - `[false]` `[reject]` Edge: U16 flaky when the host is slow — the page clock is frozen and moves only on `stepUntil` steps (20 ms each), so the gap cannot pass on a slow host; the same design as H15.
  - `[false]` `[reject]` Edge: an undefined snapshot makes a viewer see the add button or the drop — a file reply exists only in a loaded snapshot; the spec fixes the viewer test as `isViewer(this.live.snapshot())`, and a missing snapshot keeping the controls is the viewer-view rule.
  - `[false]` `[reject]` Edge: Documents drop target active before the snapshot — same rule; V5 waits for the snapshot.
  - `[false]` `[reject]` Edge: V5 has no positive control for a user — D6 (documents.spec.ts) is that control and ran green in part 9/17.
  - `[false]` `[reject]` Edge: a re-spoken identical text and a retract — the region holds the later identical text, so clearing it is right.
  - `[low]` `[reject]` Edge: inline PDF transfer builders remain in files.spec.ts — the spec says those tests do not change.
  - `[false]` `[reject]` Edge: Announcer doc comment is stale — it states the alone-and-not-joined rule, which the queue keeps.
  - `[false]` `[reject]` Edge: a retract of an exact joined or counted text no longer empties the region — this is the intent ("alone, not joined").
  - `[low]` `[patch]` Verification gap: the `messages === 1` clause is not pinned — added two cases (joined text and count text are not recalled by a retract of that exact text); mutation `lastText = text` goes red (2 cases).
  - `[low]` `[patch]` Verification gap: the `text !== ''` guard is not pinned by the empty-message case — added a case on a fresh queue and after a joined text; mutation dropping the guard goes red (1 case).
  - `[false]` `[reject]` Verification gap: AC6 has no `mutation:` line — AC6 adds no test; the spec names the existing gates as its check.
  - `[false]` `[reject]` Verification gap: announce-focus-sources and viewer-sources pins are source text — the spec asks for them; V4, V5 and the queue cases are the behavioural pins.
  - `[false]` `[reject]` Verification gap: V5 relies on a fixed wait — see the Blind row.
  - `[false]` `[reject]` Verification gap: `stepUntil` does not bound `check()` — a failure is a timeout, never a wrong pass; moved code, unchanged.
  - `[false]` `[reject]` Verification gap: U16 and H15 are self-contained — an observation, not a defect.
  - `[false]` `[reject]` Intent audit: the guard is exercised at the queue's model region and the wiring by a regex — described, not a defect; U16 checks the real CDK region.
  - `[false]` `[reject]` Intent audit: V4's 403 is a direct POST — a control by design (spec Design Notes).
  - `[false]` `[reject]` Intent audit: V5 uses synthetic drag events and no test for a user's drop in this story — D6 covers the user.
  - `[false]` `[reject]` Intent audit: before the snapshot loads the controls show — see the Edge rows.
  - `[false]` `[reject]` Intent audit: the old guard also recalled joined or counted text — a deliberate narrowing to "spoken alone".
  - `[false]` `[reject]` Intent audit: the Announcer doc comment still describes the guard — it does so correctly.

## Design Notes

- **Governing ADs (Rule 6):**
  - AD-13: the viewer bullet, `/v1/state`'s `viewer` and the 403 `read_only`.
  - AD-24: `OcuTalonViewer`.
  - AD-29 and AD-33: lanes, and this story's exception bullet, which this plan added to the spine. The bullet lists the exact files.
  - AD-22: real-runtime tests and throwaways.
  - The Consistency Conventions row "Announcements and focus" is kept: one polite region, and the same cadence.
- **No split for DW-1386 and DW-1387:** both read only the snapshot's `viewer`, which exists since Story 25.4 and which Story 26.4 keeps (`OcuTalonViewer`, epics.md Story 26.4). They need none of 26.4's approver roles. The server refusal they mirror is live today (`Test.Web.ViewerApi`).
- **No new public text:** the fixes hide a button and turn a drop target off. `data-failures` is an attribute and is never rendered as text.
- **Rule 2:**
  - Usage copies History's `arrived` and `refused` retract pattern rather than sharing a helper. It is two call sites of about five lines each, and History's `arrived` also corrects the page number, so a helper would need both shapes.
  - `stepUntil`, `taken` and `chatItem` are moved to support, not copied.
  - The guard extends `AnnounceQueue.retract`.
- **Integration (Rule 1):** no new service. `AnnounceQueue` gains the `clear` option. Consumed-by: `Announcer`, and through it HistoryPage (H9, H12, H15) and UsagePage (U16), which observe it in a real browser. Consumes: the Announcer (Story 2.12), FileDrop (25.3), isViewer (25.4) and FileReply (25.6).
- **Decided in-stage:**
  - **The guard lives in the queue.** `Announcer` uses `inject`, so node cannot load it. The queue's `speak` and `clear` are the region's only writers, so a test of the queue's region model is behavioural. U16's empty-region check covers the real CDK region.
  - **The page-side signal is a failure count.** It is `data-failures` on the failed block, reset by an answer. A boolean would race the press, because rendering waits on the frozen clock.
  - **U16 pins the queued case**, the harm DW-1120 names, and adds the empty-region check.
  - **`controlsOf`'s `viewer` argument is required**, so no caller can leave it out.
  - **A viewer's drop on Documents goes to the browser's own handling**, as FileDrop's contract says and as the chat already does for a viewer.
  - **V4 also posts the ref** and expects 403 `read_only`. This is a real-HTTP check that the hidden control would only have failed.
  - **The working tree was dirty at step 1.** The only change was the lead's own `stage_spawned` line for this spawn in `cycle-log-epic-25.md`, so planning went on.
  - **The spine has no `.memlog.md`, so no memlog append was made.** `lint_spine.py` gives the same result as at HEAD: `ok` false, from 10 low `placeholder` findings that are literal tokens such as `{n}`. None of them comes from the new bullet.
- **Ledger inbox:** DW-1120 is AC1, DW-1121 is AC2, DW-1122 is AC3, DW-1386 is AC4 and DW-1387 is AC5. None is declined.

## Verification

**Runtime:** Lane A throwaways only. Prefix every `ci/iris.sh` call with:

`OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_RUN_TAG=e25s8<x> OCUTALON_LOCK_OWNER='epic=25 stage=<stage>'`

Use one tag per stage (for example `e25s8i`, `e25s8q`, `e25s8r`) and end with `ci/iris.sh teardown`. Each call runs in the foreground with `timeout: 600000`. After any web change, run `ci/iris.sh build` once before the browser units (Rule 21). No slot and no MCP target is needed.

**Commands:**
- (loop) `npm --prefix web test` -- expected: all pass, the new queue, viewer and file-reply cases and `initial-bundle.test.mjs` included (about 1-2 min).
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `npm --prefix web run build` -- expected: exit 0, initial total at most 921 kB.
- (loop) The browser parts that hold the specs this story changes. Recompute them first, because the new tests move the cut: `npm --silent --prefix web run e2e -- --list --reporter=json > "$TMPDIR/chromium.json"` (a scratch folder outside the repo), then `node web/scripts/e2e-part.mjs k/17 "$TMPDIR/chromium.json"` for k = 1..17. At planning time (335 tests) the parts were:
  - `ci/iris.sh live sign-in --part 17/17` (`usage/usage.spec.ts`)
  - `--part 12/17` (`history/history.spec.ts`)
  - `--part 15/17` (`sign-in/viewer.spec.ts`)
  - `--part 10/17` (`files/files.spec.ts`, `documents/sample.spec.ts`)
  - `--part 9/17` (`documents/documents.spec.ts`)
  - Expected: every part green.
- (once) Retro A1. `grep -rlE "recordAnnouncements|announcements\(|cdk-live-announcer" web/e2e` lists every spec that pins the Announcer. Run each remaining part that holds one, one call each:
  - `live sign-in --part 4/17` (`banners`), `5/17` (`chat/chat`).
  - `live sign-in-2 --part 3/6` (`live/live`, `live/socket`), `4/6` (`phone/approver`), `5/6` (`settings/on-call`), `6/6` (`settings/settings`, `settings/webhooks`). Find these with the `e2e:sign-in-2` listing.
  - `live sign-in-3 --part 1/8` (`guide/guide`), `6/8` (`heartbeat/heartbeat`), `7/8` (`memory-card`), `8/8` (`memory-noise`). Find these with the `e2e:sign-in-3` listing.
  - `live floor` (`announcements`, `approval`, `devices`, `guide`, `incident`, `layout`), split with `--part` if it nears 8 minutes.
  - `live cards`, `live answers`, `live demo-switch` and `live demo-path` (`telegram-page`).
  - The Usage error, the file reply and the Documents drop are pinned only by the loop parts above (`grep "Couldn't load your usage"`, `"Add to documents|app-file-reply|Saved to memory"` and `"DataTransfer|dragging"`).
- (once) Fresh check (Rule 19): every loop part forward, then again in reverse spec order where the unit supports it. Otherwise run each changed test on a fresh stack, and run U16 and H15 alone and after their own files' other cases.

**Shared surfaces:**
- `AnnounceQueueOptions` (constructed only by `Announcer` and `announce-queue.test.mjs`).
- `GUARDED` in `viewer-sources.test.mjs`.
- `controlsOf`'s signature (`file-reply-view.test.mjs`).
- The chromium part cut (`e2e-part.mjs`), which the new tests shift.
- The moved e2e helpers (`files.spec.ts`, `history.spec.ts`).

Every test added or changed passes on a fresh environment, in either order.

**Mutations** (one per AC; observe red, revert, then confirm that `git status --short` and `git diff --stat` are unchanged):
- AC1: delete the retract (and the `failed` reset) in UsagePage's answer path → U16 red (ERROR announced twice, the region holds ERROR).
- AC2: `AnnounceQueue.retract` calls `clear()` for any non-empty text (drop `lastText === text`) → the "retract guard: other text" case red.
- AC3: `HistoryPage.refused` ignores a failure while `failed()` is true → H15 red at `data-failures="2"`. Under the same mutation the old H15 should stay green, which is the hole DW-1122 names. Record whether it did.
- AC4: `file-reply.ts` passes `false` for `viewer` → V4 red. `controlsOf` ignores `viewer` → the `file-reply-view.test.mjs` viewer case red.
- AC5: remove `[active]="!viewer()"` → V5 red (the dragover is cancelled) and the viewer-sources documents case red.
- AC6: no new test. The existing gates (`initial-bundle`, `ux-strings`, `lazy-routes`) are the check.

**Mutation results** (implement stage; each applied, red observed, reverted, and `git status --short` and `git diff --stat` unchanged afterwards):
- mutation: AC1 deleted the retract and the `failed` reset in UsagePage's answer path -> U16 red (ERROR announced twice, the region holds ERROR).
- mutation: AC2 `AnnounceQueue.retract` clears for any non-empty text -> four "retract guard" cases red (27 pass, 4 fail; green again after the revert, 31 pass). Re-run by the lead.
- mutation: AC2 (review patch) `say()` records `lastText = text` for joined and counted texts -> the joined-text and count-text recall cases red (32 pass, 2 fail); `retract` drops `text !== ''` -> the empty-message case on a fresh queue red (33 pass, 1 fail). Reverted; 34 pass.
- mutation: AC3 `HistoryPage.refused` ignores a failure while `failed()` is true -> H15 red at `data-failures="2"`. The old H15 (without the two new lines) stayed green under the same mutation, which is the hole DW-1122 names.
- mutation: AC4 `file-reply.ts` passes `false` for `viewer` -> V4 red; `controlsOf` ignores `viewer` -> the `file-reply-view.test.mjs` viewer case red.
- mutation: AC5 `[active]="!viewer()"` removed -> V5 red (the dragover is cancelled) and the viewer-sources documents case red.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** Usage withdraws its failed-read announcement on the next answer, and the `lastSpoken` guard moved into `AnnounceQueue` (`clear` option), pinned by behavioural node cases. History and Usage count their handled failures in `data-failures`, which H15 and the new U16 wait on. A viewer gets no Add to documents on a file reply, and the Documents drop target is inactive for a viewer. No new user-visible string; initial bundle 890.69 kB (limit 921,000 bytes).

**Files changed:**
- `web/src/app/shared/announce-queue.ts`, `announcer.ts` -- the guard lives in the queue; the Announcer delegates and passes `clear`.
- `web/src/app/usage/usage-page.ts`, `history/history-page.ts` -- `failures` signal and `data-failures`; Usage retracts on an answer.
- `web/src/app/chat/file-reply-view.ts`, `file-reply.ts` -- `controlsOf(..., viewer)`, and `FileReply` reads `isViewer(this.live.snapshot())`.
- `web/src/app/documents/documents-page.ts` -- `[active]="!viewer()"`.
- `web/scripts/announce-queue.test.mjs`, `announce-focus-sources.test.mjs`, `file-reply-view.test.mjs`, `viewer-sources.test.mjs` -- guard cases, delegation pins, viewer cases, `GUARDED` and the drop pin.
- `web/e2e/support/clock.ts`, `support/files.ts` (new), `files/files.spec.ts`, `history/history.spec.ts`, `usage/usage.spec.ts`, `sign-in/viewer.spec.ts` -- moved helpers, H15 precondition, U16, V4, V5.

**Review:** 29 findings from four layers: 0 high, 0 medium; 2 patches applied (low: two verification-gap test cases for the `messages === 1` clause and the `text !== ''` guard), 0 deferred, 27 rejected with the reasons in the triage log. Follow-up review recommended: false (no high patched, fewer than two mediums).

**Verification:** `npm --prefix web test` 2136 pass; `npm --prefix web run lint` exit 0; `npm --prefix web run build` exit 0, initial 890.69 kB; Lane A throwaway (tag e25s8v): `live sign-in` parts 17/17 (16 passed), 12/17 (15), 15/17 (24), 10/17 (21) and 9/17 (23) all green, torn down with 0 leftovers. Mutations for AC1 to AC5 observed red and reverted (recorded in `## Verification`; AC2 re-run by the lead, plus two review-patch mutations). The `(once)` Retro A1 runs and the fresh check are the lead's.

**Residual risks:** the other Announcer-pinning specs (Retro A1) were not run in this stage. The viewer drop falls to the browser's own handling by design.
