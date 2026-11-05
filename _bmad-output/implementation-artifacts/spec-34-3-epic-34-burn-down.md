---
title: 'Story 34.3: Epic 34 burn-down'
type: 'chore'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-34-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-34-2-add-and-remove-documents-on-a-documents-page.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 34.2 keeps an added file's bytes in the Lane B table `OcuTalon.Data.Upload` until `DocumentOps` takes it, and ruling U-287 kept that design on three conditions that nothing yet meets: an upload that is never taken is never deleted (`CreatedAt` is never read), nothing pins that a refused add writes no row, and `Upload.Take(ref)` gives any caller any session's bytes.

**Approach:** Add a one-hour age purge to `Data.Upload`, called by the Web area's existing `Purge(daysToKeep)` (the daily purge task) and at the start of every documents route call; make `Take` and `Drop` owner-scoped through a new `Ownership` kind; pin the refuse-before-store order with tests; check once, on a throwaway online-demo stack, that the reset's golden restore leaves no upload behind.

## Boundaries & Constraints

**Always:**
- Lane B files only: `Data/Upload.cls`, `Data/Ownership.cls`, `Web/Documents.cls`, `Install/Step/Web.cls` (Lane B by the spine's AD-23 "Who owns the steps"), their tests, the spine (plain unions with `[AMENDED 2026-11-05, Story 34.3]` markers) and the evidence file.
- "Older than one hour" means `CreatedAt` strictly before now minus 3,600 seconds; a row exactly 3,600 seconds old is kept. Whatever `daysToKeep` says (AD-27, like `AddressCounter.Purge`).
- The purge reads and deletes without SQL (the routes run as the signed-in user, who holds no SQL privilege, and only `Ownership.Rows` may prepare unchecked: `docker/tests/test-class-rules.sh` rule `unchecked-prepare`); each row is deleted with `%DeleteId`, which deletes its stream.
- Owner checks compare `SessionRef` exactly (EXACT collation), go through `OcuTalon.Data.Ownership` (AD-4), and answer a row of another session exactly like a missing one.
- Tests that run on a slot create and delete only their own rows; a test that purges at the real clock runs only on a throwaway (Rule 21).
- ASCII only, no local path in any repo file; comments state the contract, never the history.

**Never:**
- Change user-facing text, a route's answers or status codes, `Web.BodyLimit` or its tests (Story 11.22), `SessionOps.cls`, `Test/Data/Tables.cls`, `src/short-names.tsv`, `ci/units.sh`, `web/e2e-online/**`, `web/e2e/support/**` or any Lane A file (`Install/Registry.cls`, `Install/Task/**`, `Test/Install/**`, `Docs/**`, `Memory/**`, `Data/{Document,Memory}.cls`).
- Add a table, property, index, global or storage change to `Data.Upload`; add a CI job, group or test area; add an `AD-n` or rewrite an existing AD sentence.
- Purge a row younger than one hour, or let a route call fail because its sweep failed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boundary | rows created now-3601 s, now-3600 s, now-3599 s; `Upload.Purge(90, now)` and `Purge(0, now)` | the first is deleted, the other two kept, other sessions' rows alike | first delete error returned; a row already gone is not an error |
| Daily task | aged (61 min) and fresh (59 min) uploads; `Install.Step.Web.Purge(90)` and `(0)` | aged deleted, fresh kept, live events and address counter still purged | the first error of the three purges |
| Route sweep | session B's aged upload; session A calls `GET`, `POST` (accepted or refused) or `DELETE` on `/v1/documents` | B's aged row is gone after the call; B's fresh row stays; the call's own answer unchanged | a failed sweep is ignored by the route |
| Refused add | `wrong_type`, `empty`, malformed body, `too_large` for `.md`, `.txt`, `.pdf`, `.docx` (10,485,761 bytes), body of `BODYMAX`+1 (route 413), body over the bound at `OnPreDispatch` (413) | the same 400/413 answers as today, nothing submitted, and the session has no `Upload` row (owner running, so an accepted add would store one) | as today |
| Take by owner | `Take(ref, ownSessionRef)` | the bytes; the row is deleted | |
| Take by another | `Take(ref, otherSessionRef)`, a case variant of the owner's Ref, `""` | `""`; the row stays | |
| Drop scoped | `Drop(ref, otherSessionRef)` / `Drop(ref, own)` | OK and the row stays / OK and the row is deleted | |
| Reset | throwaway online demo: golden copy captured from a fresh start, then uploads added, then the golden copy restored | no `Upload` row and no `^OcuTalonP.Upload*` node after the restore; rows existed before it | evidence records CHK lines |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/Upload.cls` -- `Put` 29-39 (sets `CreatedAt` from `Data.Time.NowUtc`), `Take(ref)` 43-56, `Drop(ref)` 59-65, `DropSession` 68-79 (delete-each-keep-first-error loop to share), storage `^OcuTalonP.UploadD/I/S` 100-104. No index on `CreatedAt` (and none may be added).
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls` -- the sibling: `Purge(daysToKeep)` 136-145 (one hour whatever the days; `WINDOW` 3600 `Final`), `Recent` 42-60 (a no-SQL walk of the class's own global: the pattern for the purge).
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- `NowUtc` :18, `AddSeconds(utc, seconds)` :42 (use it for the cutoff; ISO UTC strings compare in order).
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `Purge(daysToKeep)` 119-130 (calls `Live.Event.Purge` and `AddressCounter.Purge`, returns the first error); class doc 12-13 names its purges. Called by `Install.Registry.Purge` -> `Install.Task.Purge` (Lane A, daily 03:00; read only).
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- `List` 70-87, `Add` 90-115 (BODYMAX check :93, refusals 96-100, all before `Dispatch`), `Remove` 118-140, `Dispatch` 148-172 (owner guard, `Put` :159, `Drop(upload)` :170), class doc 1-19 (states the routes; add the sweep sentence).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- class doc 1-44 (add one bullet), `Document(ref, sessionRef)` 292-300 (the sibling of the new `Upload`), `Rows` 693-737 (Final, the one unchecked prepare; rejects an empty, `instance` or `eval` owner), `Statement` kinds `documents`/`document` 880-887, final `Quit ""` :888 (append the `upload` kind before it).
- `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsProbe.cls` -- `Submit` :50 calls `Take(command.UploadRef)`; `OwnerRunning` :59 (running by default); add the sweep-time seam override here.
- `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- `TestAddRefused` 203-250, `TestUploadRows` 253-303 (already: oversize `.pdf`, `.png`, empty, malformed store nothing; `Take(ref)` :267), `TestBodyBound` 306-329 (413 at the route; no Upload count yet), `TestBodyBounds` 331-371 (`SizedDispatch` through `OnPreDispatch`), helpers `Session` :544, `Call` :553, `CallStream` :562, `Body` :614, `SizedDispatch` :644, `Uploads(session)` :677; header 1-33 lists every test.
- `src/ocutalon/cls/OcuTalon/Test/Core/UploadContract.cls` -- `TestPutAndTake` 81-109 (one-argument `Take`/`Drop` calls to update), `TestDropSession` 112-131, `DeleteFixtures` 134-138, `Count(where)` 141-147; header 1-11.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` -- `TestPurgeAddressCounter` 135-161 and `CounterRow` 164-171 (the sibling test; the class runs only on a throwaway).
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:35` -- `TIMEOUT` 120 s (read only): the route drops its row when no Ok answer comes within it, so a row older than one hour is never one an `AddDocument` in flight still needs.
- Reset check, read only: `docker/tests/test-online-session.sh` 34-65 (online throwaway start: `live_start`, `live_web_port`, `online_values`, `online_override`, `dc up -d --build`, `wait_started_ready 400`), `docker/tests/test-online-demo.sh` 1817-1819 (`dc stop iris`, `dc start iris`, `wait_started_ready 200`), `docker/tests/lib-live.sh` (`dc` :249, `iris_script` :316, cleanup trap), `docker/tests/lib-online.sh` (`online_signin` :97, `redact`); `docker-compose.yml` (volume `durable:/durable`, so the project's volume is `${P}_durable`); `ci/iris.sh teardown` removes volumes named `<project>_...` of the tag.
- Spine (by range): AD-4 :180 (sign-out drops), AD-21 Uploads sub-bullet :692, AD-25 reset :895, AD-27 :939-947 (Rule bullet :945), cross-area row :1354, front matter `updated:` :10.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- append kind `upload` before `Statement`'s final `Quit ""`: class `OcuTalon.Data.Upload`, binds `ao`, `SELECT u.ID FROM OcuTalon_Data.Upload u WHERE u.Ref = ? AND u.SessionRef = ?`; public `Upload(ref, sessionRef, Output sc) As OcuTalon.Data.Upload` in `Document`'s shape (empty ref -> ""); one class-doc bullet -- AD-4's one ownership API (DW-754).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Upload.cls` -- `Take(ref, sessionRef)` and `Drop(ref, sessionRef)` find the row through `Ownership.Upload` (another session's row answers like a missing one; `Drop` stays OK either way); `Parameter KEEP [Final] = 3600`; `Purge(daysToKeep As %Integer, now As %String = "") As %Status` deletes every row whose `CreatedAt` is before `AddSeconds(now or NowUtc, -KEEP)` (a missing `CreatedAt` counts as old), without SQL (walk the data global's ids), with `%DeleteId`, a row deleted meanwhile is not an error, first other error returned; `DropSession` and `Purge` share one private delete loop; class doc updated (writers, readers, the purge) -- DW-752, DW-754.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `Purge` also calls `##class(OcuTalon.Data.Upload).Purge(daysToKeep)`, still tries every purge and returns the first error; its doc and the class doc (12-13) name the upload purge -- DW-752 via the existing daily task (AD-27).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- a private `Sweep()` that calls `Upload.Purge(0, ..SweepNow())` and ignores the status; `SweepNow()` private, returns "" (the probe's seam); `Sweep` is the first statement of `List`, `Add` and `Remove`; `Dispatch` passes `command.SessionRef` to `Drop`; one class-doc sentence on the sweep -- DW-752 "the documents route's next call".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsProbe.cls` -- `Take(command.UploadRef, command.SessionRef)`; override `SweepNow()` to return `^OcuTalonTest("DocumentsProbe", "now")` when set, else ""; header names it.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/UploadContract.cls` -- update `TestPutAndTake` to the two-argument `Take`/`Drop`; add `TestTakeIsOwnerScoped` (Matrix rows Take by owner/another, Drop scoped; the row stays after each refusal), `TestPurgeBoundary` (fixture rows of ZzUploadA and ZzUploadB with `CreatedAt` set to 2001-01-01T00:00:00Z, 00:00:01Z, 00:00:02Z after `Put`; `Purge(90, "2001-01-01T01:00:01Z")` deletes only the first, `Purge(0, ...)` the same, a second call changes nothing; a fresh row is never touched) -- deterministic, slot-safe (only the test's 2001 rows are old enough); header updated.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- `TestUploadRows` takes with the session; add `TestRefusedAddsStoreNothing` (owner running; each refusal of the Matrix row "Refused add", including all four `too_large` families, the route's 413 at `BODYMAX`+1 and the `OnPreDispatch` 413 through `SizedDispatch` for both dispatch classes; after each, `Uploads(a)` is 0 and nothing is submitted; then one accepted add stores exactly one row, proving the check can fail) and `TestSweepOnEveryRoute` (with the probe's `now` set to 2001-01-01T01:00:01Z: a ZzSweep fixture session's rows at 00:00:00Z and 00:00:01Z; after `List`, after a refused `Add`, after an accepted `Add` and after `Remove` of an own fixture document by session A, the first is gone and the second kept, each re-planted; the route's answer unchanged; rows deleted in `OnAfterAllTests`); header updated -- DW-752, DW-753.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` -- `TestPurgeUploads` (`TestPurgeAddressCounter`'s shape): `Purge(90)` and `Purge(0)` each delete an upload created 3,660 s ago and keep one 3,540 s ago (`Data.Time.AddSeconds`), and still purge an aged live event -- the daily task's path at the real clock (throwaway only).
- [ ] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions, each ending `[AMENDED 2026-11-05, Story 34.3]`: AD-21 Uploads (:692): refusals before the row, `Take(ref, sessionRef)`/`Drop(ref, sessionRef)` through `Ownership.Upload`, `Upload.Purge` (one hour, whatever the days) from the Web area's purge and at each documents route call; AD-27 (:945): the Web area also purges `Upload` rows after one hour; AD-25 (:895): the golden copy holds no `Upload` rows either (evidence `34-3-upload-reset.md`); cross-area row (:1354): `Upload.Take(ref, sessionRef)`; `updated:`; then `memlog.py append` and `lint_spine.py` (only the pre-existing `placeholder` findings).
- [ ] Reset check (once, after the code above passes) -- a scratch script in the stage scratchpad (never committed) sourcing `docker/tests/lib-live.sh` and `lib-online.sh`, modelled on `test-online-session.sh` 34-65, tag `e34s3r`: online-demo throwaway ready; CHK that `^OcuTalonP.UploadD` resolves to a database directory under `/durable/` and that no `Upload` row exists; `dc stop iris`; copy `${P}_durable` into a new volume `${P}_golden` (a `docker run --rm --user root --entrypoint sh` of the project's own image, `cp -a`); `dc start iris`, ready; store two uploads through `Upload.Put` (a fixture session's fresh one, and an aged one with `CreatedAt` 2 hours back) and CHK the count is 2; sign in the demo account (`online_signin`) and `GET /ocutalon/api/v1/documents` over HTTP: 200, the aged row gone, the fresh kept (the route sweep on the real runtime); `dc stop iris`; restore the golden copy into `${P}_durable` (empty it, `cp -a` back); `dc start iris`, ready; CHK no `Upload` row and `$Data` 0 for `^OcuTalonP.UploadD`, `UploadI`, `UploadS`; remove `${P}_golden`; `ci/iris.sh teardown` with the tag. Write `_bmad-output/implementation-artifacts/evidence/34-3-upload-reset.md` (ASCII, container paths only, no local path, no password): the steps, the CHK lines, timings, and the note that the demo host's real reset lives outside the repo and this emulates AD-25's documented restore (inference for the host) -- DW-754's recorded evidence.

**Acceptance Criteria:**
- Given an upload that was stored and never taken, when more than one hour has passed and either the daily purge task's Web-area `Purge` runs or any documents route is called, then the row and its stream are gone, while an upload one hour old or younger is kept (`TestPurgeBoundary`, `TestPurgeUploads`, `TestSweepOnEveryRoute`; DW-752).
- Given the owner item running, when an add is refused for its type, emptiness, a malformed body, size (each of the four families) or its body bound (the route's and `OnPreDispatch`'s 413), then the answer is unchanged and no `Upload` row exists for the session (`TestRefusedAddsStoreNothing`; DW-753).
- Given an upload of session A, when `Take` or `Drop` is called with session B's Ref (or a case variant of A's), then nothing is returned or deleted and A's row stays; with A's Ref, `Take` returns the bytes and deletes the row (`TestTakeIsOwnerScoped`; DW-754).
- Given an online-demo throwaway whose golden copy was captured after a fresh start, when uploads are added and the golden copy is restored, then no `Upload` row or `^OcuTalonP.Upload*` node remains, and the evidence file records it (DW-754).
- **Integration (Rule 1):** given aged and fresh uploads, when the Web area's `Purge` (consumer, the daily task's registry path) runs, then only the aged one is gone (`TestPurgeUploads`); when the documents routes (consumer) are called, through the probe and over real HTTP on the throwaway, then only the aged one is gone (`TestSweepOnEveryRoute`, the reset script's GET); when `Upload.Take` (consumer of `Ownership.Upload`) is called with another session's Ref, then it returns nothing (`TestTakeIsOwnerScoped`).
- Every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-3 (private database, `^OcuTalonP.Upload`), AD-4 (ownership API; sign-out drops), AD-5 (uploads survive a restart, so the age purge, not a start, removes orphans), AD-13 (the signed-in user has no SQL privilege; the one unchecked prepare is `Ownership.Rows`), AD-21 (the Uploads contract), AD-22 (throwaways for real-clock purges and the reset check), AD-25 (reset = golden restore; nothing runs at the reset), AD-27 (retention through the purge task's area `Purge(daysToKeep)`; fixed-age purges whatever the days), AD-29 (Lane B files only), AD-33 (`Upload` stays Lane B's; no new table). No AC contradicts an AD Rule; the spine edits record U-287's conditions as unions.

**Decided in-stage:**
1. **Both purge paths (DW-752).** The daily task alone can leave an orphan up to about a day past its hour; the route sweep at every documents call (`GET`, `POST`, `DELETE`) meets the ruling's "the documents route's next call" literally. A `GET` that deletes expired, ownerless-by-age rows is housekeeping, like `AddressCounter`'s purge; it never touches a row under an hour old.
2. **Why one hour is safe.** The route drops its row when the submit fails or no Ok answer comes within `CommandsIn.TIMEOUT` (120 s); an Ok answer means `DocumentOps` already handled the `AddDocument` (it takes the upload while handling it, spine AD-21). So a row older than one hour is never one an `AddDocument` in flight still needs (inference from the code; 19.4 builds the consumer).
3. **No SQL in the purge.** One method serves the task and the routes; the routes cannot run checked SQL and must not prepare unchecked. Rows are few and short-lived, so walking the data global (`AddressCounter.Recent`'s pattern) costs little and needs no `CreatedAt` index (no storage change).
4. **Owner scope through `Ownership` (DW-754).** `Take` and `Drop` gain a required `sessionRef`; the check is a new `Ownership` kind, as AD-4 requires of command handlers. `Drop` is scoped too (governed default: the route drops only its own row anyway). `DropSession` is scoped by definition; `Put` writes the caller's own session. No route reads an upload; the add's 200 body carries the document's ref, never the `UploadRef`. The consumer is not built yet (19.4), so the signature change breaks nothing.
5. **Deterministic boundary.** `Purge` takes an optional `now`; the unit tests use rows dated 2001, so no real row is old enough to be touched and the class stays slot-safe; `TestPurgeUploads` covers the real clock on a throwaway with 61/59 minutes, like its sibling.
6. **DW-753 is tests only.** The delivered `Add` already refuses (413 at :93, 400s at 96-100) before `Dispatch`, and `OnPreDispatch` refuses over-bound bodies before the route; the new test runs with the owner running so an accepted add would store a row.
7. **Reset check emulates AD-25** on a throwaway: the host's scripts are outside the repo; the restore of a durable-volume copy captured after a fresh start is the documented mechanism. No harness file changes.

**Integration ACs (Rule 1):** the last AC. **Consumes:** `Install.Task.Purge` -> `Install.Registry.Purge` -> `Install.Step.Web.Purge` (AD-27); `Ownership.Rows`; `Data.Time.AddSeconds`. **Consumed-by:** Story 19.4 (`DocumentOps` calls `Upload.Take(ref, sessionRef)` with the `AddDocument`'s `UploadRef` and `SessionRef`; an empty answer is a failed row); the daily purge task (`Upload.Purge` through the Web area).

**Extend, don't copy (Rule 2):** `Upload.Purge` follows `AddressCounter.Purge` (fixed age whatever the days) and `AddressCounter.Recent` (no-SQL walk); it shares `DropSession`'s delete loop (one private helper). `Ownership.Upload` follows `Ownership.Document`. `TestPurgeUploads` follows `TestPurgeAddressCounter`. No copy.

**Ledger inbox (Rule 17):** DW-752 -> Upload/Web/Documents/Web step tasks and AC 1; DW-753 -> `TestRefusedAddsStoreNothing` and AC 2; DW-754 -> Ownership/Upload tasks, the reset check and ACs 3-4. None declined. DW-747 (CommandsIn timeout vs late delivery; 19-4) is not this story's.

**Rule 3:** no page or text changes; the route's real HTTP evidence is the reset script's signed-in `GET` and the existing e2e `documents.spec.ts` (D1-D13) re-run below.

**Footprint extensions (Rule 11 b):** `Install/Step/Web.cls`, `Test/Web/Install.cls` (Lane B, not contended), the evidence file. Contended: the spine only (unions).

## Verification

Lane prefix `P` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=34 stage=<stage>'`. Tags: implement fresh `e34s3i`, warm `e34s3iw`, reset check `e34s3r`, QA `e34s3q`, code review `e34s3c`, smoke `e34s3s`. Every command alone, in the foreground, `timeout: 600000`; never two test runs in one message. Slot runs: MCP server `ocutalon-slot-c`, namespace `OCUTALON`, identity checked with `iris_server_info` first. Warm: `P OCUTALON_RUN_TAG=e34s3iw ci/warm.sh up` once; at the stage's end, also after a failure, `P OCUTALON_RUN_TAG=e34s3iw ci/warm.sh down` and `P OCUTALON_RUN_TAG=e34s3i ci/iris.sh teardown`.

Shared surfaces: the `OcuTalon.Data.Upload` table (row counts in `DocumentsApi`, `UploadContract`, `SessionOpsDocuments`; the sweep deletes only rows over an hour old), the signatures of `Upload.Take`/`Drop` (every caller is listed in the Code Map), `Ownership.Statement`'s kinds, and `Install.Step.Web.Purge` (`Test.Web.Install`). Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e34s3iw ci/iris.sh class <C>` for `OcuTalon.Test.Core.UploadContract`, `OcuTalon.Test.Web.DocumentsApi`, `OcuTalon.Test.Web.Install`, `OcuTalon.Test.Core.SessionOpsDocuments`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Web.BodyLimit` -- one per call, `CLASS ... passed`.
- (loop) `bash docker/tests/test-class-rules.sh`; `bash docker/tests/test-storage.sh`; `bash docker/tests/test-boundaries.sh` -- one call each, PASS.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- `"ok": true`, only the pre-existing `placeholder` findings.
- (once) the reset-check script with `P OCUTALON_RUN_TAG=e34s3r OCUTALON_LIVE_DEADLINE=570` -- every CHK ok, evidence written; then `P OCUTALON_RUN_TAG=e34s3r ci/iris.sh teardown`.
- (once) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e34s3iw ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2` -- every class passed.
- (once) `P OCUTALON_RUN_TAG=e34s3i ci/iris.sh build`, then `P OCUTALON_RUN_TAG=e34s3i ci/iris.sh live sign-in --part 1/3`, `--part 2/3`, `--part 3/3` -- one per call, every test passed (`documents/documents.spec.ts` among them; `--part k/2` overruns the local 540 s deadline).
- (once, Rule 19 fresh check) `P OCUTALON_RUN_TAG=e34s3i ci/iris.sh shard lane-b --part 1/2` and `--part 2/2`, then both with `--reverse` -- one per call, every class passed.

**Planned mutations (Rule 19), each recorded as `mutation: <change> -> <test went red>`:** the purge comparison before-cutoff -> at-or-before (`Upload.Purge`) -> `UploadContract` TestPurgeBoundary; `KEEP` 3600 -> 86400 -> TestPurgeBoundary; the `Upload.Purge` call removed from `Install.Step.Web.Purge` -> `Test.Web.Install` TestPurgeUploads; the `Sweep` call removed from `List` (then `Remove`) -> `DocumentsApi` TestSweepOnEveryRoute; `Put` moved before the refusals in `Add` (store right after parsing) -> `DocumentsApi` TestRefusedAddsStoreNothing; `Take` opening by `RefIndexOpen` with no owner check -> `UploadContract` TestTakeIsOwnerScoped; the `upload` statement without `AND u.SessionRef = ?` (binds `a`) -> TestTakeIsOwnerScoped.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (Halt after planning). Ledger inbox DW-752, DW-753 and DW-754 addressed under Tasks & Acceptance; no intent gap. Footprint extensions: Install/Step/Web.cls, Test/Web/Install.cls (Lane B, not contended); contended file touched: the spine (plain unions only).
