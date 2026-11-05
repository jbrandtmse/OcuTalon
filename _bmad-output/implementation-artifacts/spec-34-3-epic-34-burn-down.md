---
title: 'Story 34.3: Epic 34 burn-down'
type: 'chore'
created: '2026-11-05'
status: 'done'
baseline_revision: '971f837d14cdeac80e2d5c0fc17531b50a744217'
baseline_commit: '971f837d14cdeac80e2d5c0fc17531b50a744217'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-34-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-34-2-add-and-remove-documents-on-a-documents-page.md'
warnings: [oversized]
deferred:
  - summary: >-
      The x64 constraints file is a starting set resolved with the host's pip for the x86_64 platform tags, not an installed x64 set, and it equals the arm64 set.
    evidence: |-
      pip evaluates environment markers against the host interpreter, so a Linux or x86_64-only dependency could be missing or a version could differ; nothing but the first CI x64 image build can settle it. The gate fails that build by name on any missing or differing distribution. The lead records CI's printed set and run id in evidence/34-3-x64-installed-set.md after the push.
    location: >-
      docker/licences/constraints-x64.txt
    severity: medium (unverified)
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
- [x] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- append kind `upload` before `Statement`'s final `Quit ""`: class `OcuTalon.Data.Upload`, binds `ao`, `SELECT u.ID FROM OcuTalon_Data.Upload u WHERE u.Ref = ? AND u.SessionRef = ?`; public `Upload(ref, sessionRef, Output sc) As OcuTalon.Data.Upload` in `Document`'s shape (empty ref -> ""); one class-doc bullet -- AD-4's one ownership API (DW-754).
- [x] `src/ocutalon/cls/OcuTalon/Data/Upload.cls` -- `Take(ref, sessionRef)` and `Drop(ref, sessionRef)` find the row through `Ownership.Upload` (another session's row answers like a missing one; `Drop` stays OK either way); `Parameter KEEP [Final] = 3600`; `Purge(daysToKeep As %Integer, now As %String = "") As %Status` deletes every row whose `CreatedAt` is before `AddSeconds(now or NowUtc, -KEEP)` (a missing `CreatedAt` counts as old), without SQL (walk the data global's ids), with `%DeleteId`, a row deleted meanwhile is not an error, first other error returned; `DropSession` and `Purge` share one private delete loop; class doc updated (writers, readers, the purge) -- DW-752, DW-754.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `Purge` also calls `##class(OcuTalon.Data.Upload).Purge(daysToKeep)`, still tries every purge and returns the first error; its doc and the class doc (12-13) name the upload purge -- DW-752 via the existing daily task (AD-27).
- [x] `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- a private `Sweep()` that calls `Upload.Purge(0, ..SweepNow())` and ignores the status; `SweepNow()` private, returns "" (the probe's seam); `Sweep` is the first statement of `List`, `Add` and `Remove`; `Dispatch` passes `command.SessionRef` to `Drop`; one class-doc sentence on the sweep -- DW-752 "the documents route's next call".
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsProbe.cls` -- `Take(command.UploadRef, command.SessionRef)`; override `SweepNow()` to return `^OcuTalonTest("DocumentsProbe", "now")` when set, else ""; header names it.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/UploadContract.cls` -- update `TestPutAndTake` to the two-argument `Take`/`Drop`; add `TestTakeIsOwnerScoped` (Matrix rows Take by owner/another, Drop scoped; the row stays after each refusal), `TestPurgeBoundary` (fixture rows of ZzUploadA and ZzUploadB with `CreatedAt` set to 2001-01-01T00:00:00Z, 00:00:01Z, 00:00:02Z after `Put`; `Purge(90, "2001-01-01T01:00:01Z")` deletes only the first, `Purge(0, ...)` the same, a second call changes nothing; a fresh row is never touched) -- deterministic, slot-safe (only the test's 2001 rows are old enough); header updated.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- `TestUploadRows` takes with the session; add `TestRefusedAddsStoreNothing` (owner running; each refusal of the Matrix row "Refused add", including all four `too_large` families, the route's 413 at `BODYMAX`+1 and the `OnPreDispatch` 413 through `SizedDispatch` for both dispatch classes; after each, `Uploads(a)` is 0 and nothing is submitted; then one accepted add stores exactly one row, proving the check can fail) and `TestSweepOnEveryRoute` (with the probe's `now` set to 2001-01-01T01:00:01Z: a ZzSweep fixture session's rows at 00:00:00Z and 00:00:01Z; after `List`, after a refused `Add`, after an accepted `Add` and after `Remove` of an own fixture document by session A, the first is gone and the second kept, each re-planted; the route's answer unchanged; rows deleted in `OnAfterAllTests`); header updated -- DW-752, DW-753.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` -- `TestPurgeUploads` (`TestPurgeAddressCounter`'s shape): `Purge(90)` and `Purge(0)` each delete an upload created 3,660 s ago and keep one 3,540 s ago (`Data.Time.AddSeconds`), and still purge an aged live event -- the daily task's path at the real clock (throwaway only).
- [x] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions, each ending `[AMENDED 2026-11-05, Story 34.3]`: AD-21 Uploads (:692): refusals before the row, `Take(ref, sessionRef)`/`Drop(ref, sessionRef)` through `Ownership.Upload`, `Upload.Purge` (one hour, whatever the days) from the Web area's purge and at each documents route call; AD-27 (:945): the Web area also purges `Upload` rows after one hour; AD-25 (:895): the golden copy holds no `Upload` rows either (evidence `34-3-upload-reset.md`); cross-area row (:1354): `Upload.Take(ref, sessionRef)`; `updated:`; then `memlog.py append` and `lint_spine.py` (only the pre-existing `placeholder` findings).
- [x] Reset check (once, after the code above passes) -- a scratch script in the stage scratchpad (never committed) sourcing `docker/tests/lib-live.sh` and `lib-online.sh`, modelled on `test-online-session.sh` 34-65, tag `e34s3r`: online-demo throwaway ready; CHK that `^OcuTalonP.UploadD` resolves to a database directory under `/durable/` and that no `Upload` row exists; `dc stop iris`; copy `${P}_durable` into a new volume `${P}_golden` (a `docker run --rm --user root --entrypoint sh` of the project's own image, `cp -a`); `dc start iris`, ready; store two uploads through `Upload.Put` (a fixture session's fresh one, and an aged one with `CreatedAt` 2 hours back) and CHK the count is 2; sign in the demo account (`online_signin`) and `GET /ocutalon/api/v1/documents` over HTTP: 200, the aged row gone, the fresh kept (the route sweep on the real runtime); `dc stop iris`; restore the golden copy into `${P}_durable` (empty it, `cp -a` back); `dc start iris`, ready; CHK no `Upload` row and `$Data` 0 for `^OcuTalonP.UploadD`, `UploadI`, `UploadS`; remove `${P}_golden`; `ci/iris.sh teardown` with the tag. Write `_bmad-output/implementation-artifacts/evidence/34-3-upload-reset.md` (ASCII, container paths only, no local path, no password): the steps, the CHK lines, timings, and the note that the demo host's real reset lives outside the repo and this emulates AD-25's documented restore (inference for the host) -- DW-754's recorded evidence.

**DW-738 (added by the lead after the Contest Planner's ruling, 2026-11-05; re-validated for this item only):**
- [x] **Task D0 -- the x64 set, measured.** arm64's installed set is measured (`_bmad-output/implementation-artifacts/evidence/34-2-task0-licences.md`, 36 distributions). Measure x64 the same way, never assumed: either `pip install --target` on an x64 throwaway (`docker run --platform linux/amd64` of an x64 Python 3.12 image if one is local; never pull or push the AI Hub image) or, if no x64 runtime is available locally, let the image build print the installed set (the licence gate's listing) in CI's x64 `image` group and record that CI output as evidence after the push (`evidence/34-3-x64-installed-set.md`, run id and job named). Record which way was used.
- [x] **How D0 resolves when no x64 runtime runs locally (lead's ruling for this run):** try an x64 throwaway locally only if a Python 3.12 x64 image is ALREADY present (`docker run --platform linux/amd64`; never pull anything new without need, never pull, tag or push the AI Hub image). Otherwise the gate is built so CI's x64 `image` build prints the installed set and fails on any distribution missing from, or differing from, `constraints-x64.txt`; write `constraints-x64.txt` as a starting set from `pip install --target <dir> --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all:` resolution of the three top-level pins, and state in this spec and in `evidence/34-3-x64-installed-set.md` that the CI build is the x64 confirmation (the lead records CI's printed set as evidence after the push). Never assume the x64 set equals arm64's.
- [x] **Constraints files:** `docker/licences/constraints-arm64.txt` and `docker/licences/constraints-x64.txt` (or the names the build context check accepts), each pinning every distribution of its architecture's measured set to its exact version (`name==version`, one per line, sorted). The top of each file carries a comment stating the rule: "Any version change here re-measures the licences (docker/licences/gate.py on the installed set) and updates the evidence in the same commit."
- [x] **Image build:** the Dockerfile's pip line installs with `-c /opt/ocutalon/licences/constraints-<arch>.txt` beside the three top-level pins, choosing the file by the build's architecture (`TARGETARCH` or `uname -m`); a build on an architecture with no constraints file fails with a clear message. The licence gate still runs on the installed set and still fails outside the allowed families; the gate also fails when an installed distribution is missing from the constraints file or differs in version (so the x64 CI build is the x64 check). Update the build context check and `test-compose-file.sh` for the new files.
- [x] **Tests:** (1) a `docker/tests` check that the evidence table's package-and-version list (arm64: `evidence/34-2-task0-licences.md`; x64: the x64 evidence) equals its constraints file, with a demonstrated mutation (change one version in a constraints file -> red); (2) the gate's planted cases still fail a disallowed licence, plus a planted installed distribution absent from the constraints -> fail.
- [x] **IPM install path:** check whether the IPM package (`src/module.xml`, `module.xml`) installs Python packages; if it does, it uses the same pins; if it does not install them at all, record that in the spec (the lead reports it in the contract). Do not edit `module.xml` versions.

**Acceptance Criteria:**
- Given an upload that was stored and never taken, when more than one hour has passed and either the daily purge task's Web-area `Purge` runs or any documents route is called, then the row and its stream are gone, while an upload one hour old or younger is kept (`TestPurgeBoundary`, `TestPurgeUploads`, `TestSweepOnEveryRoute`; DW-752).
- Given the owner item running, when an add is refused for its type, emptiness, a malformed body, size (each of the four families) or its body bound (the route's and `OnPreDispatch`'s 413), then the answer is unchanged and no `Upload` row exists for the session (`TestRefusedAddsStoreNothing`; DW-753).
- Given an upload of session A, when `Take` or `Drop` is called with session B's Ref (or a case variant of A's), then nothing is returned or deleted and A's row stays; with A's Ref, `Take` returns the bytes and deletes the row (`TestTakeIsOwnerScoped`; DW-754).
- Given an online-demo throwaway whose golden copy was captured after a fresh start, when uploads are added and the golden copy is restored, then no `Upload` row or `^OcuTalonP.Upload*` node remains, and the evidence file records it (DW-754).
- **Integration (Rule 1):** given aged and fresh uploads, when the Web area's `Purge` (consumer, the daily task's registry path) runs, then only the aged one is gone (`TestPurgeUploads`); when the documents routes (consumer) are called, through the probe and over real HTTP on the throwaway, then only the aged one is gone (`TestSweepOnEveryRoute`, the reset script's GET); when `Upload.Take` (consumer of `Ownership.Upload`) is called with another session's Ref, then it returns nothing (`TestTakeIsOwnerScoped`).
- Every test added or changed passes on a fresh environment, in either order.

### Review Findings

Code review 2026-11-05 (first review; four layers: blind, edge case, verification gap, acceptance). 25 findings: 13 patched (medium 1, low 12), 0 decision-needed, 0 deferred, 12 rejected (2 false). No HIGH: every AD the Design Notes cite holds (AD-4 governs per-session reads and commands; an age purge across sessions is AD-27's pattern, like the live events and the address counter). Rule 3: no user-facing surface, exempt.

- [x] [Review][Patch] (medium) The "a row already gone is not an error" clause of the shared delete loop was unpinned (QA's survivor) -- new `TestRowAlreadyGone` plants an index node naming an id with no row and drops the session through `DropSession`; mutation recorded under Verification [src/ocutalon/cls/OcuTalon/Test/Core/UploadContract.cls]
- [x] [Review][Patch] `Upload.Drop` returned `%DeleteId`'s not-found error when a row went between its read and its delete, against its doc -- it now deletes through the shared loop [src/ocutalon/cls/OcuTalon/Data/Upload.cls:71]
- [x] [Review][Patch] The Always constraint "the purge reads and deletes without SQL" had no falsifiable pin (a rewrite with checked SQL would fail silently on the routes) -- new `TestPurgeUsesNoSql`; mutation recorded [src/ocutalon/cls/OcuTalon/Test/Core/UploadContract.cls]
- [x] [Review][Patch] Every `DocumentsApi` test that sets no sweep clock purged the slot's rows at the real clock, against "a test that purges at the real clock runs only on a throwaway" -- the probe's default clock is now `SLOTNOW` (2000-01-01) [src/ocutalon/cls/OcuTalon/Test/Web/DocumentsProbe.cls:59]
- [x] [Review][Patch] The `DocumentsApi` header said the `OnPreDispatch` 413 cases assert no row; they assert that the dispatch stops before any route [src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls:18]
- [x] [Review][Patch] The AC 4 `mutation:` line said the reset mutant was not run, while the run (restore skipped, after-restore CHK red) exists -- line corrected [spec Verification]
- [x] [Review][Patch] The Dockerfile comment omitted the gate's failure on a pin that is not installed [docker/Dockerfile:16]
- [x] [Review][Patch] The x64 evidence claimed the build always prints the installed set; with `-c` pip fails first, by name, on a pin x64 cannot install -- stated, with DW-765 occurrence [_bmad-output/implementation-artifacts/evidence/34-3-x64-installed-set.md]
- [x] [Review][Patch] The x64 evidence did not say that pip judged environment markers on the host [_bmad-output/implementation-artifacts/evidence/34-3-x64-installed-set.md]
- [x] [Review][Patch] The x64 evidence asked for CI's set without saying it replaces the table that `test-compose-file.sh` reads as the pin list [_bmad-output/implementation-artifacts/evidence/34-3-x64-installed-set.md]
- [x] [Review][Patch] The reset evidence lacked the store step, a key to its CHK lines and the cleanup [_bmad-output/implementation-artifacts/evidence/34-3-upload-reset.md]
- [x] [Review][Patch] `NOTFOUND` is the system's `$$$DeleteObjectNotFound` (5810, `%occErrors.inc`), now named in its doc [src/ocutalon/cls/OcuTalon/Data/Upload.cls:32]
- [x] [Review][Patch] DW-747's trailer still gave 19.4 Take's session check, which this story delivers -- trailer appended (owner unchanged, the timeout case stays) [deferred-work.md DW-747]

Rejected:
- false: AD-4 exception for the route sweep -- AD-4 binds per-session reads and commands; purges by age across sessions are AD-27's (live events, address counter), and AD-21/AD-27 record this one.
- false: `TestPurgeUploads` does not show the address counter still purged -- `TestPurgeAddressCounter` runs the same `Install.Step.Web.Purge` in the same class.
- low: the sweep opens every `Upload` row on each documents call -- rows live at most an hour (taken within seconds when DocumentOps runs, 120 s route timeout); `%OpenId` does not read the stream; Design Notes 3 forbid an index. Acceptable.
- low: a failing route sweep leaves no trace -- the Matrix makes the route ignore it; `TestPurgeUsesNoSql` now pins the one silent-failure cause found (SQL under the signed-in user).
- low: the fresh-environment shards ran before the review patches -- the lead's Rule 19 pre-push fresh run, forward and reversed, covers the final tests; the patched classes ran green on the slot.
- low: 2001-dated fixtures could be purged by a concurrent real-clock purge on a shared slot -- one test run per slot at a time, CI runs a fresh instance, and the probe no longer purges at the real clock.
- low: `Owned` drops `Ownership.Upload`'s status -- the shape of `Ownership.Document`; a row left by a failed read is purged within the hour.
- low: a malformed non-empty `CreatedAt` is never purged -- `Put` always writes a valid time.
- low: the spine's REST table does not name the sweep -- AD-21 states it; a plain union only where the story's tasks named it.
- low: the AD-27 union also names the address counter -- accurate, and a plain union.
- low: the evidence files carry no revision -- the commit that adds them is the revision.
- low: `TestSweepOnEveryRoute` compares statuses, not bodies; `Drop`'s scoping has no mutation of its own -- `Purge` writes nothing to the device; Rule 19 asks one mutation per AC and AC 3 has two.

## Spec Change Log

- 2026-11-05 (lead, before implement): DW-738 added by the Contest Planner's ruling (pin the image's transitive Python packages per architecture; evidence equals constraints; gate unchanged in force; IPM path; version-bump rule). Re-validated for this item only.

## Review Triage Log

### 2026-11-05 - Review pass
- verdicts: 36 findings - high 0, medium 3, low 30, false 0, maybe-false 3
- findings:
  - `[low]` `[reject]` Blind: every documents request scans the upload table - Design Notes 3 chose the no-SQL walk because rows are few and live under an hour; no index may be added.
  - `[low]` `[reject]` Blind: a failing sweep is invisible - the Matrix requires a failed sweep to be ignored by the route; the daily task returns the same purge's error.
  - `[low]` `[reject]` Blind: `Owned` drops the status of `Ownership.Upload` - same shape as `Ownership.Document`; an empty answer is a failed row by the spine.
  - `[low]` `[reject]` Blind: `epic-34-context.md` still says `Take(ref)` - a generated cache that recompiles because the spine is newer.
  - `[low]` `[patch]` Blind: the x64 file header says "measured" - reworded to "resolved for x86_64 ... the x64 image build confirms the set".
  - `[low]` `[reject]` Blind: versions pinned, not hashes - DW-738 rules name==version pins; hashes change how packages are verified (a veto item), not this story's.
  - `[medium]` `[patch]` Blind: the architecture switch is only grepped - `constraints_switch_runs` runs the Dockerfile's `case` with a stubbed `uname` (x86_64, aarch64, riscv64).
  - `[low]` `[patch]` Blind: loose ends in `gate_constraints` - the real files are parsed through `gate.py`'s `load_constraints`, the dangling comment is gone, `out` is local.
  - `[low]` `[patch]` Blind: `load_constraints` message unclear - reworded to "is not a name==version pin, or its name is pinned twice".
  - `[low]` `[reject]` Blind: a malformed non-empty `CreatedAt` is never purged - `Put` always writes a valid time; not reachable.
  - `[low]` `[reject]` Blind: the AD-25 sentence omits that the reset is emulated - the sentence is the ruled condition; the evidence states the inference.
  - `[low]` `[reject]` Edge: Drop/Take race with a purge - the purge deletes only rows over an hour old and a Take comes within 120 s of the Put, so they never contend.
  - `[low]` `[reject]` Edge: malformed `CreatedAt` - same as the Blind row above.
  - `[low]` `[reject]` Edge: whole-table scan per route call - same as the first Blind row.
  - `[low]` `[reject]` Edge: an `OnPreDispatch` 413 runs no sweep - it is refused before any route; the Matrix's route sweep names the calls of the routes.
  - `[low]` `[reject]` Edge: a queued command older than one hour loses its upload - Design Notes 2 (inference from `CommandsIn.TIMEOUT`); the spec fixes one hour.
  - `[maybe-false]` `[defer]` Edge: host pip evaluates markers against the host - routed to `deferred` as medium (unverified); the first CI x64 image build settles it.
  - `[maybe-false]` `[defer]` Edge: the x64 file equals the arm64 file while D0 is marked done - same entry; the evidence and the contract name the CI build as the confirmation.
  - `[low]` `[patch]` Edge: the real constraints files never go through `load_constraints` - patched with the Blind `gate_constraints` row.
  - `[low]` `[reject]` Edge: textual version compare (1.0 vs 1.0.0) - the pins are copied from the installed METADATA of the same wheels.
  - `[medium]` `[patch]` Gap: "no CreatedAt counts as old" is unpinned - `TestPurgeBoundary` now plants a row with `CreatedAt` "" and expects it gone; the explicit `= ""` clause was redundant (`cutoff ] ""` is true) and was removed; mutation recorded.
  - `[low]` `[patch]` Gap: the "deleted meanwhile" status is unpinned - `TestPurgeBoundary` asserts that `%DeleteId` of a missing row answers `Upload#NOTFOUND`; mutation recorded.
  - `[medium]` `[patch]` Gap: `AssertNothingStored` after `SizedDispatch` cannot fail - removed from the two `OnPreDispatch` cases, whose 413 and `continue` 0 assertion stays.
  - `[low]` `[patch]` Gap: AC 4 has no mutation line - the reset script ran with the restore skipped; the after-restore CHK went red; recorded.
  - `[low]` `[patch]` Gap: the Dockerfile switch and `-c` wiring are text pins without mutations - the switch now runs; two mutations recorded.
  - `[low]` `[patch]` Gap: the range case does not isolate the strict parse - the file now pins every installed distribution and adds only a range line.
  - `[low]` `[patch]` Gap: the sweep's `Catch` is not exercised - the probe's `SweepNow` can throw (`now` = "throw"); the test covers it; mutation recorded.
  - `[low]` `[reject]` Gap: the first-error order of `Install.Step.Web.Purge` is untested - needs a failing event purge; not a two-way door, no user-reachable failure.
  - `[low]` `[reject]` Gap: `TestPurgeUploads` purges every session at the real clock - throwaway only by the spec and Rule 21.
  - `[low]` `[reject]` Gap: no consumer of `Take(ref, sessionRef)` yet - spec-bound; Story 19.4 is named in Consumed-by.
  - `[low]` `[reject]` Intent: Take is scoped by an argument the caller supplies - spec-bound signature; the consumer passes the command's `SessionRef`.
  - `[low]` `[reject]` Intent: the sweep is tested through a probe subclass and `OnPreDispatch` paths run no sweep - the reset check's signed-in GET runs the real route.
  - `[low]` `[reject]` Intent: other `DocumentsApi` tests sweep at the real clock on a slot - a slot holds no real uploads and only rows over an hour old go.
  - `[low]` `[reject]` Intent: the daily purge is tested at the Web step, not through `Install.Task.Purge` - the task is Lane A's and untouched; the Matrix names the step.
  - `[low]` `[reject]` Intent: the reset check emulates the host's restore - Design Notes 7 and the evidence state it.
  - `[maybe-false]` `[defer]` Intent: DW-738 tests exercise text and files, and the x64 set is unconfirmed - same deferred entry as the Edge x64 rows.

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

**Implementation notes (stage implement, 2026-11-05):**
- Code, tests, evidence and spine unions are done as the Tasks say. `Upload.Purge` walks `^OcuTalonP.UploadD` and deletes with `%DeleteId` (status 5810, a row already gone, is not an error: the macro `$$$DeleteObjectNotFound` is not defined in a class on build 154, so the class carries it as `Parameter NOTFOUND`). `Ownership.Upload` is a `Rows` kind (binds `ao`).
- The reset check was run by the build-auto stage (tag `e34s3r`, 296 s, every CHK ok); `evidence/34-3-upload-reset.md` holds the steps and CHK lines, and the scratch script stays out of the repo.
- **DW-738 D0 decision.** No x64 Python image runs locally (`python:3.12.7-slim` is arm64 only), and nothing was pulled. The x64 set was resolved with the host's pip (`--platform manylinux_2_28_x86_64` and the older/newer manylinux tags, `--python-version 3.12`, `--only-binary=:all:`) for the three top-level pins: 36 distributions at the same versions as the measured arm64 set. `evidence/34-3-x64-installed-set.md` records the method, the table and the gate's verdicts; the CI x64 `image` build is the x64 confirmation (it fails on any distribution missing from, or at another version than, `constraints-x64.txt`); the lead records CI's printed set there after the push. The x64 set is never assumed equal to arm64's: it was resolved, and the gate holds the build to it.
- **DW-738 files.** `docker/licences/constraints-arm64.txt` (from the arm64 evidence table) and `constraints-x64.txt`, each with the rule comment; the Dockerfile picks the file by `uname -m` (x86_64 -> x64, aarch64 -> arm64, anything else fails with a message), installs with `-c`, and `gate.py check <dir> <constraints>` also fails on an installed distribution that is unpinned or at another version, and on a pin that is not installed; `.dockerignore`, `test-lib-live.sh` (build context) and `test-compose-file.sh` follow. The evidence-equals-constraints check and its planted mutations are in `test-compose-file.sh` (a new `docker/tests` script would need a registration in `ci/units.sh`, which `test-ci-config.sh` requires of every `test-*.sh`; none was added, so nothing needs registering).
- **DW-738 IPM install path (for the lead's contract report).** Neither `module.xml` nor `src/module.xml` installs Python packages: they hold only `Resource`, `FileCopy` and `Invoke` entries for classes, the web bundle and the install hooks, with no pip, requirements or Python resource. The packages come only from the image's pip line, so a non-image (IPM-only) install has no fastembed, pdfplumber or python-docx; the pins and constraints apply to the image alone. `module.xml` versions were not touched.

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

**Mutations demonstrated (Rule 19; warm stack `e34s3iw`, each reverted byte-identical, class green again after):**
- mutation: `Upload.Purge` comparison before-cutoff -> at-or-before (`'(row.CreatedAt ] cutoff)`) -> `UploadContract` TestPurgeBoundary red (a row exactly 3,600 s old deleted).
- mutation: `Upload.KEEP` 3600 -> 86400 -> `UploadContract` TestPurgeBoundary red (the 3,601 s rows kept).
- mutation: `Take` opens by `RefIndexOpen` with no owner check -> `UploadContract` TestTakeIsOwnerScoped red.
- mutation: `Ownership` `upload` statement without `AND u.SessionRef = ?` (binds `a`) -> `UploadContract` TestTakeIsOwnerScoped red.
- mutation: `Upload.Purge` call removed from `Install.Step.Web.Purge` -> `Test.Web.Install` TestPurgeUploads red (days 90 and 0).
- mutation: `Sweep` removed from `Documents.List`, then from `Documents.Remove` -> `DocumentsApi` TestSweepOnEveryRoute red (the list, then a remove).
- mutation: `Upload.Put` added in `Documents.Add` right after `ParseBody`, before the refusals -> `DocumentsApi` TestRefusedAddsStoreNothing red (wrong_type, empty, ...).
- mutation: reset check (AC 4): the restore replaced by `true` (the golden copy never restored) -> the check's `after the restore` CHK red, 4 of 4 values (`rows 1`, `data 11`, `index 10`, `stream 11` against 0), 242 s on its own throwaway, torn down; run by the implement stage's review pass, whose output the code review read (corrected 2026-11-05 by code review: this line had said the mutant was not run).
- mutation: DW-738 one version changed in `constraints-x64.txt` (`numpy==2.5.4` -> `2.5.3`) -> `test-compose-file.sh` check "constraints: each architecture's file pins exactly the distributions and versions of its evidence table" red.
- mutation: DW-738 `gate.py check` with the constraints comparison disabled -> `test-compose-file.sh` check "licences: the gate refuses an installed distribution that the constraints lack ..." red.

**QA audit (stage qa, 2026-11-05; slot `ocutalon-slot-c`, no test file changed):** every AC and Matrix row has a pinning test; the implement stage's 10 recorded mutations were reused, and 11 more were demonstrated for pins that had none in this section (each reverted byte-identical, class green again after):
- mutation: `Documents.Dispatch` drops the failed add's row with `Drop(upload, "")` instead of the command's SessionRef -> `DocumentsApi` TestUploadRows red (every failed-submit case left a row).
- mutation: `Sweep` removed from `Documents.Add` -> `DocumentsApi` TestSweepOnEveryRoute red (refused add, accepted add).
- mutation: `Sweep` without its `Try`/`Catch` -> `DocumentsApi` TestSweepOnEveryRoute red (`List returns OK` with the throwing clock).
- mutation: `Upload.Purge` skips a row with no `CreatedAt` -> `UploadContract` TestPurgeBoundary red (an upload with no time counts as old).
- mutation: `Upload.Purge` without the unreadable-time error -> `UploadContract` TestPurgeBoundary red.
- mutation: `gate.py` no longer reports an installed distribution that is not pinned -> `test-compose-file.sh` "licences: the gate refuses an installed distribution that the constraints lack ..." red.
- mutation: `gate.py` ignores a version that differs from the pin -> the same check red.
- mutation: `gate.py` ignores a pin that is not installed -> the same check red.
- mutation: Dockerfile pip line without `-c "$constraints"` -> `test-compose-file.sh` "dockerfile: one pip line installs exactly ..." red.
- mutation: Dockerfile architecture switch lets an unknown architecture fall through to x64 -> `test-compose-file.sh` "dockerfile: the pip line holds every dependency ..." and "the architecture switch ... picks constraints-x64.txt ..." red.
- mutation: Dockerfile gate call without the constraints file -> `test-compose-file.sh` "dockerfile: the licence gate runs right after the install ..." red.
- survivor, not closable from a test: `Upload.DeleteAll` without its `NOTFOUND` clause (a row deleted meanwhile becomes an error) leaves all 7 `UploadContract` tests green. `DeleteAll` is `[ Private ]` (`$ClassMethod` raises `<PRIVATE METHOD>` from a test), no single-process sequence makes a row vanish between the walk and the delete, and the existing assertion pins only the status code `Purge` ignores. Closing it needs a production seam (for example a `Protected` or public `DeleteAll`), which is outside QA's file scope; recorded as an open point.

**Code review (2026-11-05; slot `ocutalon-slot-c`, each mutant reverted byte-identical, class green again after: UploadContract 9 of 9, DocumentsApi 17 of 17):**
- mutation: `Upload.DeleteAll` without its `NOTFOUND` clause -> `UploadContract` TestRowAlreadyGone red ("DropSession is OK although one of its rows is already gone" => ERROR #5810). Closes the QA survivor with no production seam: the test plants an index node of ZzUploadGone that names an id with no row, which `DropSession`'s query reads, so the shared loop meets a row that is already gone (the state a Take or purge leaves between the read and the delete).
- mutation: `Upload.Purge` runs `%SQL.Statement.%ExecDirect` in its walk -> `UploadContract` TestPurgeUsesNoSql red ("Purge names no %sql", "... no %execdirect"): the Always constraint "the purge reads and deletes without SQL".

**Run record (implement stage, 2026-11-05):** loop classes green on the warm stack (UploadContract, DocumentsApi, Web.Install, SessionOpsDocuments, Data.Ownership, Web.BodyLimit); `test-class-rules`, `test-storage`, `test-boundaries`, `test-compose-file`, `test-lib-live` green; `lint_spine.py` only the 8 pre-existing `placeholder` findings; reset check `e34s3r` all CHK ok (296 s) and torn down; `shard lane-b` fresh parts 1/2 and 2/2, forward and `--reverse`, all passed (51, 50, 51, 50 classes); `live sign-in` parts 1/3 (118), 2/3 (107) and 3/3 (111) passed. Part 2/3 first ran into the local 540 s deadline twice on a busy machine (other lanes' stacks, load 6 to 7) with no failed test, and passed with `OCUTALON_LIVE_DEADLINE=585`. The image built on arm64 with the pins, and `gate.py check` inside it printed `the installed set equals constraints-arm64.txt` (36 distributions).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 34.3 meets U-287's three conditions and DW-738. `Upload.Purge` (one hour, whatever the days, no SQL, `%DeleteId`) runs from `Install.Step.Web.Purge` and at the start of `List`, `Add` and `Remove`; `Upload.Take` and `Drop` take a `sessionRef` and go through the new `Ownership.Upload` kind; `TestRefusedAddsStoreNothing` pins refuse-before-store; the reset check on a throwaway online demo showed no `Upload` row after a golden restore. DW-738: per-architecture constraints files, pip `-c` in the Dockerfile chosen by `uname -m`, and `gate.py check <dir> <constraints>` failing on an unpinned, differing or uninstalled distribution. The x64 set is a resolved starting set; the CI x64 `image` build is its confirmation. Neither `module.xml` nor `src/module.xml` installs Python packages (the pins apply to the image only).

**Files changed.** `Data/Upload.cls` (Purge, KEEP, owner-scoped Take/Drop, shared delete loop), `Data/Ownership.cls` (`upload` kind and `Upload`), `Install/Step/Web.cls` (upload purge), `Web/Documents.cls` (Sweep, SweepNow, scoped Drop), tests `UploadContract`, `DocumentsApi`, `DocumentsProbe`, `Web/Install`; `docker/Dockerfile`, `docker/licences/{gate.py,constraints-arm64.txt,constraints-x64.txt}`, `.dockerignore`, `docker/tests/test-compose-file.sh`, `docker/tests/test-lib-live.sh`; the spine (AD-21, AD-25, AD-27 and cross-area unions); evidence `34-3-x64-installed-set.md` and `34-3-upload-reset.md`.

**Review.** 36 findings: patches applied 12 (medium 3, low 9: the x64 header, the executed architecture switch, the `gate_constraints` loose ends and range case, the gate message, the empty-time and deleted-meanwhile pins, the vacuous `OnPreDispatch` assertion, the AC 4 and DW-738 mutations, the throwing sweep seam); deferred 1 entry (x64 set unconfirmed, 3 findings); rejected 21, each with its reason in the Review Triage Log.

**Follow-up review recommended: true.** Three medium findings were patched (two or more), and the patches are unreviewed: the new `constraints_switch_runs` and `gate_constraints` shell checks, the `SweepNow` throw seam and the simplified purge condition.

**Verification.** Loop classes green on the warm stack (UploadContract 7 tests, DocumentsApi, Web.Install, SessionOpsDocuments, Data.Ownership, BodyLimit) before and the four touched ones again after the patches; `test-class-rules`, `test-storage`, `test-boundaries`, `test-lib-live`, `test-compose-file` pass; `lint_spine.py` shows only the 8 pre-existing `placeholder` findings; reset check `e34s3r` all CHK ok and a mutant with the restore skipped red; `shard lane-b` fresh, forward and reversed, both parts, passed (51, 50, 51, 50 classes); `live sign-in` parts 1/3, 2/3, 3/3 passed (118, 107, 111 tests; part 2 needed `OCUTALON_LIVE_DEADLINE=585` on a busy machine); the arm64 image built with the pins and its gate printed `the installed set equals constraints-arm64.txt`. The fresh-environment shards ran before the review patches; the patched tests ran warm.

**Residual risks.** The first x64 CI `image` build may fail on a differing x64 set (the intended gate); the lead records CI's printed set and run id in `evidence/34-3-x64-installed-set.md`. The sweep opens every `Upload` row on each documents call, which is cheap while rows are few and short-lived.
