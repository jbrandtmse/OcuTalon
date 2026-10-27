---
title: "The demo guide's tests hold now that incidents are real"
type: 'bugfix'
created: '2026-10-27'
status: 'done'
baseline_revision: 'b2f834088c671f7084d635c38bbfaa1b798f7b66'
baseline_commit: 'b2f834088c671f7084d635c38bbfaa1b798f7b66'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'Fixture.Check rows carry no CreatedAt, so with no WatchMark FailurePoller starts each reading at its poll time and a batch that lands between two polls is never read: a test that expects a real incident from a fixture watch passes or fails by timing'
    evidence: 'Test.Data.Fixture.Check L65-77 sets no CreatedAt (Task 0: the row read back with CreatedAt empty); Watch.Mark.Start L52-58 then returns the poll time; FailurePoller.Poll saves no mark when it took nothing (L87). This is why the floor guide cases passed locally (a fast batch) and failed in CI (a batch spread over about 8 s).'
    location: 'src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls'
    severity: 'low'
    footprint: 'out-of-footprint (contended: Test/Data/Fixture.cls)'
---

<intent-contract>

## Intent

**Problem:** Since Epic 4's demo guide merged into Epic 5, the real `FailurePoller` and `IncidentManager` turn the failing Orders messages that tests send into real incidents. M4's real press makes an incident for the FLOOR session. On the no-key floor stack it is noticed (open, fallback) about 10 s after the batch, and M4's clean-up leaves it in place. So M7 opens at step 4 and M9's box is inactive. The real progress lines also replace M4's sent line. In lane-b, failing Orders messages left behind by their senders become `instance` incidents as soon as a later session watches Orders, and they are noticed within seconds. So a new `Test.Live.GuideRefresh` session sees step 3 done and Break the feed inactive (DW-305; CI runs 40525019781 and 40535207067, both with M4, M7 and M9 red).

**Approach:** Test-only changes. Every test that sends real failing Orders messages keeps `FailurePoller` off them while it runs: it holds the Orders `WatchMark` ahead. When it ends, it puts the mark at its clean-up time, so none of its failures is ever read, removed or not, and later failures are read as before. The holders are M4 (through two new `support/guide.ts` helpers), `Test.Demo.BreakFeedProduction` and `Test.Demo.Production`. They use two new class methods of `Test.Demo.Production`. No product code and no contended file changes.

## Boundaries & Constraints

**Always:**
- **The hold.** `Test.Demo.Production.HoldFailures() As %Status` writes the one `OcuTalon.Data.WatchMark` row keyed by its `NAMESPACE` and `PRODUCTION` (it creates the row when there is none): `MarkAt` = `Watch.Mark.Shift(now stamp, HOLDSECONDS)` (new `Parameter HOLDSECONDS = 600`) and `Seen` "". `Mark.Start` then begins every reading after anything the holder sends.
- **The release.** `ReleaseFailures() As %Status` writes the same row with `MarkAt` = `Mark.Shift(now stamp, ##class(OcuTalon.Watch.Mark).#OVERLAP)` and `Seen` "". The next reading starts at the release time, and failures sent later are read as before.
  - Both run in OCUTALON and share one private writer.
  - They touch no other row and call no production item.
  - Stamps are `YYYY-MM-DD HH:MM:SS.sss` UTC, as `Mark.Normal` gives them.
- **When to release.** A holder releases only after its batches are complete: M4 after `settleBatch`, and the two classes after their `RemoveMessages`. Every test of those classes already waits for its own batch.
- **M4.**
  - It takes the hold before it seeds anything. Its `finally` releases whenever the hold was taken, in this order: `settleBatch` (if pressed), release, `cleanFixtureRows`, `dropBreakFeed`.
  - Every existing assertion keeps its meaning.
  - One assertion is added at the end of the body: the press made no incident and no failure group (matrix row 1).
- **The two classes.**
  - `OnBeforeAllTests` holds once the guards pass (`Missing` is "") and records it in a `Held` property.
  - `OnAfterAllTests` releases when `Held`, after the `RemoveMessages` calls and before `Fixture.Clean`.
  - `Test.Demo.Production` also holds again in `OnBeforeOneTest`, because its new tests release in the middle of a test.
- **The install-start contract.** Every new `Test.Demo.Production` test begins with `If '..Guard() Quit`. Nothing in the hooks asserts when `Missing` is set. This keeps the contract of `docker/tests/test-install-start.sh` L326-339: with no OCUORDERS, every test fails with the reason and none is skipped.
- Comments state the contract (Rule 14), and source uses ASCII escapes. Times are UTC strings.
- SQL goes through `%SQL.Statement` with the privilege check, never embedded SQL (`ci/checks.sh` class-rules).

**Never:**
- **No edits to:** product code, `Test/Live/**` (`GuideRefresh`), `Test/{Core,Web,Data,Schedule}/**`, `Test/Data/Fixture.cls`, `web/e2e/demo-path/**`, `web/src/**`, `Demo/Guide*.cls`, `Data/*.cls`, `Live/Publish*.cls`, `docker/**`, `ci/**`.
- No guard that deletes or closes incidents when a case starts.
- No stopping or disabling `FailurePoller` or `IncidentManager`.
- No change to any `Fixture` default.
- No hold or release of another production's mark.
- No blind retry, no longer timeout and no skipped test.
- No assertion weakened in M4, M7, M9 or `BreakFeedProduction`.

## I/O & Edge-Case Matrix

"Mutation H" is `HoldFailures` writing `MarkAt` = now instead of now + `HOLDSECONDS`. "Once" means an interference run under Verification. POLLWAIT is 7 s, enough for at least two polls of the 3 s `CallInterval`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| M4, the real press | Hold first, then the real `POST /v1/demo/break-feed` of the FLOOR session; `finally` as Always | No `FailureBatch`, incident, group, `watch.progress` or notice comes of the press. The box shows only the case's own lines: sent, then the case's own progress line. At the end of the body, `pressIncidents(user, since)` is `{incidents: 0, groups: 0}` | Mutation H → red (this assertion and line 280/282) |
| M7 after M4 | The FLOOR session; epoch start 5 min back | Opens at step 3; the 200-s-old run's stage is `no_notice` | Mutation H → red ("the page opens at step 3") |
| M9 after M4 | Run again; a seeded resolved incident at step 5 | The box has the secondary style | Mutation H → red (`button-inactive`) |
| M4's leftovers | One-off: `dropBreakFeed` skips its `RemoveMessages` call (it still deletes the run rows), so M4's 50 failures stay in OCUORDERS | Later cases' watches never read them (the mark is at the release time): M7 and M9 green | Once |
| `BreakFeedProduction` | Held for the class; the double behind `IncidentManager`; real presses | Every assertion as today. New, in `TestPressSendsFiftyRealFailures` after `AssertBatch`: `Hang 4`, then no request `FailurePoller`→`IncidentManager` among `Fixture.Headers(trace)` | Mutation H → red |
| `Test.Demo.Production`, existing tests | Held per test | As today | — |
| `TestHoldHidesFailures` (new) | After `Guard`, the test itself calls `HoldFailures()` (asserted OK); a fixture watcher of Orders; 3 failing orders tagged with its TraceRef and 1 tagged with a `NewRef` | After POLLWAIT: no Orders incident row whose `FirstAt` is between the test's start and now. `Guide.Compute(watcher)`: `BreakFeed.Active` 1 and step 3 not done | Mutation H → red |
| `TestReleaseHidesLeftovers` (new) | 2 failing orders tagged with a fixture sender's TraceRef and 1 with a `NewRef`. The mark is put 5 s before them (as an earlier reading leaves it), the sender is deleted (`Fixture.Clean`), and 11 s pass (older than the quiet time). Then `ReleaseFailures`, then a new fixture watcher | After POLLWAIT: no incident row in the window. `Ownership.NewestIncident(watcher, NS, PROD, "")` and `IncidentInProgress` are "". `Compute(watcher).BreakFeed.Active` is 1 | `ReleaseFailures` as a no-op → red (Task 0: an `instance` incident, noticed about 2 s after the watch) |
| `TestReleaseKeepsLaterFailures` (new) | `ReleaseFailures`; a fixture watcher; 2 failing orders tagged with its TraceRef | An incident of the watcher appears within 15 s. The test then deletes it at once with `Test.Watch.Case.DropIncidentRows` | `ReleaseFailures` writing now + `HOLDSECONDS` → red |
| `GuideRefresh` (unchanged, contended) | Lane-b order: Demo before Live | Passes | Lane-b shard once. Once: `BreakFeedProduction` skips its OCUORDERS `RemoveMessages` (one-off), then `BreakFeedProduction` and `GuideRefresh` run warm → green |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `web/`.

- `web/e2e/floor/guide.spec.ts`:
  - header L11-22: L17-18 explains M4's clean-up;
  - imports L7-8;
  - M4 L247-309: `try` L253, `button.click()` L275, the sent line and its 1.5 s check L280-282 (red in CI), the progress line L295-303, `finally` L304-308;
  - M7 L322-374: `startEpochAt(-300_000)` L333, open L338-339, `no_notice` L362-367;
  - M9 L473-549, the secondary-style check L490;
  - `inMs` (UTC `…Z` to the second) comes from `support/floor.ts` L46.
- `web/e2e/support/guide.ts`:
  - header L7-11;
  - `dropBreakFeed` L24-42 and `settleBatch` L44-67, the siblings the new helpers sit beside;
  - `rowCount` L93-107, the sibling of `pressIncidents` (`rowCount` counts by Ref; `pressIncidents` counts by owner and time);
  - `irisScript`, `chk` and `quoted` come from `support/iris.ts` (L71, L89, L144). One call takes about 0.04 s locally (Task 0).
- `Test/Demo/Production.cls`:
  - class doc L1-22;
  - `NAMESPACE` and `PRODUCTION` L25-28, `WAITSECONDS` L34;
  - `OnBeforeAllTests` L42-52, `OnAfterAllTests` L54-58 (`RemoveMessages` of `Refs`);
  - `NewRef` L222 (pushes into `Refs`), `Guard` L230, `WaitCount` L323, `Send` L343 (the tag must be a 22-character Ref).
- `Test/Demo/BreakFeedProduction.cls`:
  - class doc L1-18: L6-8 calls the item's pool "a stub until Epic 5", which is stale; replace it (Rule 14);
  - `OnBeforeAllTests` L48-71 (guards L56-63, `UseItemClass` L67);
  - `OnAfterAllTests` L80-94 (restore L81-84, `RemoveMessages` L86-89, `Clean` L92);
  - `TestPressSendsFiftyRealFailures` L100-137 (`AssertBatch` L136);
  - `Press` L439, `Watching` L451, `TraceOf` L467, `Guard` L485.
- `Test/Watch/Case.cls` (Epic 5's own):
  - `ClearMark` L801 and `Mark` L807 are the siblings on the same row;
  - `Top(table, namespace)` L534 (public);
  - `DropIncidentRows` L1185 is `[ Private ]` and removes incidents with their groups, diagnose decisions, usage and steps. This story makes it public (doc line: the Demo tests that cause real incidents call it).
- Read-only:
  - `Watch/Mark.cls`: `OVERLAP` L19, `Shift` L40, `Start` L52 (the later of `MarkAt`−2 and the earliest watch's `CreatedAt`, else the poll time).
  - `Watch/FailurePoller.cls`: `Watched` L55, `Poll` L77-128 (the start L83; nothing saved when nothing is new, L87), `Scope` L132 (a tag whose session is gone counts as `instance`).
  - `Data/WatchMark.cls` L1-21: written only by `FailurePoller` in product code; `Test.Watch.Case.ClearMark` already deletes it.
  - `Data/Ownership.cls`: `INCIDENTVISIBLE` L49; `newestIncident` L655-658 and `incidentInProgress` L659-662 (no state filter on the first).
  - `Demo/Guide.cls`: `Compute` L51-178 (`NewestIncident` L84, `IncidentInProgress` L149).
  - `Test/Live/GuideRefresh.cls` (contended): `NS`/`PROD` L18-20; `OnBeforeOneTest` L43-48; L74 and L82 (red); L252 (red).
  - `Test/Data/Fixture.cls` (contended; call only): `Session` L19, `Check` L65 (no `CreatedAt`), `Clean` L331, `Headers` L427, `Between` L450.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls`:
  - Add `HOLDSECONDS`, `HoldFailures`, `ReleaseFailures` and their private writer `PutMark(at)`.
  - Add `Held`, `Watchers` (comma-separated fixture Refs) and `IncidentFloor` properties.
  - Hooks: hold in `OnBeforeAllTests` and `OnBeforeOneTest` (only when `Missing` is ""; the second also sets `IncidentFloor` = `##class(OcuTalon.Test.Watch.Case).Top("OcuTalon_Data.Incident", "OCUTALON")`). Add `OnAfterOneTest`: drop the incidents of the test's watchers and the `instance` incidents above `IncidentFloor` through `Case.DropIncidentRows`, then `Fixture.Clean()`. Release in `OnAfterAllTests` after `RemoveMessages`.
  - Add the three tests of the matrix. Their tags go into `Refs`.
  - Update the class doc (the hold, the release, and who calls them).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls`: remove `[ Private ]` from `DropIncidentRows`; add a doc line. Nothing else.
- `src/ocutalon/cls/OcuTalon/Test/Demo/BreakFeedProduction.cls`:
  - add `Held`;
  - hold in `OnBeforeAllTests` after the guards and before `UseItemClass` (a failed hold sets `Missing` to the reason);
  - release in `OnAfterAllTests` after the two `RemoveMessages` calls;
  - add the new assertion in `TestPressSendsFiftyRealFailures`;
  - update the class doc (stale L6-8).
- `web/e2e/support/guide.ts`:
  - `holdOrdersFailures()` and `releaseOrdersFailures()`: each calls the class method through `irisScript` and throws unless it printed `CHK|…|1`.
  - `pressIncidents(user, since)`: for the user's session, counts the incidents with that `OwnerRef`, `ORDERS.namespace` and `ORDERS.production` whose `FirstAt` is between `since` and now (so the 2030 `FirstAt` of a fixture never counts). It also counts the `FailureGroup` rows whose `FirstAt` is in the same window and whose `IncidentRef` is one of those incidents or no incident at all.
  - Header L7-11.
- `web/e2e/floor/guide.spec.ts`:
  - M4: `since = inMs(0)`, the hold and the release (Always), and the final assertion `expect(await pressIncidents(user, since), 'the press made no incident and no failure group').toEqual({ incidents: 0, groups: 0 })`.
  - Update the header (L17-18) and M4's comment.

**Acceptance Criteria:**
- **The real press leaves nothing (AC1).** Given M4 presses Break the feed for real on the floor stack, when the case ends, then:
  - no incident or failure group of the FLOOR session that its press caused exists, then or later;
  - and the next cases' guides open at the step their own rows say: M7 "the page opens at step 3" and M9 "while step 5 is current the box is the secondary style".
- **M4 shows only its own lines.** Given M4's press, when the run waits for its notice, then the box shows only the case's own lines: the sent line stays for 1.5 s, and then the case's own progress line replaces it. That is M4's L280-303, red at L282 in both CI runs.
- **Earlier senders leave nothing visible (AC2).** Given a test that computes a new watching session's guide (`Test.Live.GuideRefresh` in lane-b, or any floor case), when earlier tests in the same stack sent real failing Orders messages, then no incident of those failures is visible to that session. `GuideRefresh`'s `TestHookPublishesOnChange` and `TestEventsBodyServesTheGuide` pass with the class unchanged.
- **Later failures are still read.** Given a release, when failing Orders messages arrive later, then `FailurePoller` reads them as before and they become an incident.
- **Fresh environment.** Every test added or changed passes on a fresh environment, in either order (Rule 19; the lead's fresh check).

## Spec Change Log

## Review Triage Log

### 2026-10-27 - Review pass
- verdicts: 22 findings - high 0, medium 0, low 19, false 3, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the `BreakFeedProduction` assertion cannot see a leak, because an instance-scoped batch carries no trace - `Press` takes a fixture session whose TraceRef is the SuperSession, so `FailurePoller.Scope` gives that session and the batch carries the trace; Mutation H turned the assertion red
  - `[false]` `[reject]` Blind: `TestReleaseHidesLeftovers` un-holds the poller before it sends, so it may read the sender's failures - no Orders watch exists until after the release, so `FailurePoller.Watched` lists nothing and no poll reads; the no-op release mutation turned the test red
  - `[low]` `[patch]` Blind: M4's `finally` skips the release and clean-up when `settleBatch` throws - nested `try`/`finally` in `guide.spec.ts`, so the release, `cleanFixtureRows` and `dropBreakFeed` each run
  - `[low]` `[reject]` Blind: no safety net or in-flight-poll race for a stale hold - the poll saves the mark only when it took failures, microseconds after it sends them, and the hold expires after 600 s; the class doc names the window; theoretical
  - `[low]` `[reject]` Blind: fixed sleeps (11 s, 4 s, 7 s) - sized by the spec from the 3 s `CallInterval` and the 10 s settle quiet time; Mutation H shows each goes red on a real stack; a one-line comment for the 11 s was added
  - `[low]` `[reject]` Blind: `pressIncidents` mixes clocks, has no namespace filter on groups and a dense one-line condition - the `since` from `inMs(0)` and the group selector are the spec's own (Task `guide.ts`); both containers share the host clock; no named harm
  - `[low]` `[reject]` Edge: an in-flight poll can overwrite the hold - same as the Blind row, theoretical
  - `[low]` `[reject]` Edge: `BreakFeedProduction` holds once, for 600 s - the class runs 20 s warm; spec-bound ("holds once for the class")
  - `[low]` `[patch]` Edge: `finally` skips the release or the clean-up when a helper throws - same root cause as the Blind `finally` row, fixed by the same nesting
  - `[low]` `[reject]` Edge: `settleBatch` gives up while the batch still arrives and the release follows - the 50 failures arrive within 1 s (Task 0); theoretical
  - `[low]` `[reject]` Edge: `since` from the Node clock against IRIS stamps - M4 seeds and loads a page for seconds after taking `since`, so a skew would have to exceed that; the spec fixes `since = inMs(0)`
  - `[low]` `[reject]` Edge: `TestReleaseHidesLeftovers` reads leftovers if another Orders watch exists - fixtures are cleaned after every test and class; the spec's design
  - `[low]` `[reject]` Edge: `IncidentsSince` counts every owner's incidents in the window - the matrix row says "no Orders incident row whose FirstAt is between the test's start and now"; by design
  - `[low]` `[reject]` Edge: `OnAfterOneTest` calls `Fixture.Clean()` with no refs - the spec says `Fixture.Clean()`; by design
  - `[low]` `[reject]` Edge: `Compute` could return an unusable value and the test dereferences it - `Compute` returns an object for a session that exists; the tests would fail loudly with a reason
  - `[false]` `[reject]` Edge: `TestReleaseKeepsLaterFailures` never waits for its failures to fail - an incident of the watcher only appears after the poller read them as failed, so they had failed
  - `[low]` `[reject]` Gap: the release call sites are not pinned by a test - the method is pinned by two mutations; a missing release only keeps the mark ahead up to 600 s, which hides failures and makes no incident; no lane-b or floor test reads the row afterwards
  - `[low]` `[reject]` Gap: absence assertions rest on fixed sleeps - same as the Blind sleep row
  - `[low]` `[patch]` Gap: no `mutation:` line for the pinning tests - the three mutations and two interference runs were run and are recorded under `## Verification`
  - `[low]` `[patch]` Gap (other): the release can fail and skip the clean-up - same root cause as the `finally` rows
  - `[low]` `[reject]` Gap (other): `TestReleaseHidesLeftovers` relies on no other Orders watcher - same as the Edge row
  - `[low]` `[reject]` Gap (other): `pressIncidents` takes `since` from the Node clock - same as the Edge row
- Intent alignment: no finding. It reports Reading A (gate the poller at the mark) with the closed list of three holders as the implemented reading; the floor and `GuideRefresh` outcomes are asserted by the M4 assertion, M7, M9 and the unchanged `GuideRefresh`, which all ran green.


## Design Notes

**Governing ADs:**
- AD-4: the scope of a failure. A tag of a live session makes it that session's; an untagged failure, or one whose tag has no session, is `instance`, and on a local install every watching session sees it.
- AD-15: `FailurePoller` reads above the `WatchMark`; the settle rule; `IncidentManager` alone writes `Incident` and `FailureGroup` rows in product code.
- AD-12: `Guide.Compute` is the guide's only source, and a noticed Orders incident means step 3 is done.
- AD-22: throwaways and CI.
- AD-33: one owner per table. This binds product classes. On throwaways, tests write these rows as `Test.Data.Fixture` (incidents) and `Test.Watch.Case.ClearMark` (marks) already do.

Conventions: "Incident notice" (the fallback notice sets `NoticedAt`), "Background checks" and "Tests". No AC contradicts an AD.

**Services (Rules 1 and 2).** The story introduces no service. It adds test helpers only.
- Consumes:
  - 5.2: `FailurePoller` and `Watch.Mark`;
  - 5.3, 5.4 and 5.8: settle, diagnosis and notice;
  - 2.2: the ownership filter;
  - 4.2 to 4.7: `Guide.Compute`, Break the feed and the floor cases;
  - 0.10: `Test.Demo.Production`;
  - 5.1: `Test.Watch.Case`.
- Consumed-by:
  - the Epic 5 integration (the floor unit and lane-b stay green);
  - any later test that sends real failing Orders messages, which holds and releases the same way (the helpers' docs say so). Epic 6's `Test/Live` and Epic 7's dry-run tests are the likely ones.

**Extend, don't copy:**
- `HoldFailures` and `ReleaseFailures` are new operations on the row whose siblings are `Test.Watch.Case.ClearMark` and `Mark`. They live with the Orders production's helpers because their callers (M4, `BreakFeedProduction`, `Production`) are the Orders senders, which already use that class. `Case` is the abstract base of the lane-a watch tests.
- The clean-up reuses `Case.DropIncidentRows`, made public, and `Case.Top`.
- The TS helpers sit beside `settleBatch` and `dropBreakFeed`.
- `pressIncidents` is not `rowCount`: it selects by owner and time, not by Ref.

**Task 0 (plan stage, 2026-10-27).** The runs used a warm throwaway, tag `e5s11pw`, on lane A with build 154, demo mode on, a local install and no model key. It was torn down afterwards.
- **A press made the way M4 makes it** (`BreakFeedIn`, a fixture watch of Orders):
  - The 50 failures arrived within 1 s, and an incident of the session (n=50) existed 2.6 s after the press.
  - It was noticed 11 s after the press, 10 s after the last failure, as open/fallback `no_key`, with a diagnose `Decision`.
  - M4's clean-up as it stands left it noticed and open, and it was still there 75 s later. **The hypothesis is confirmed, with the timing corrected:** without a key, the notice comes about 10 s after the batch, during M4, not 30 to 35 s.
- **The hold** (mark set 600 s ahead before the press): no incident, group or decision at 14 s or at 26 s. The mark did not move, and nothing appeared after the release.
- **Leftovers.** 3 failing orders were tagged with a session that was then deleted, and the mark was older than them. 12 s later a new fixture session watched Orders:
  - About 2 s after that came an `instance` incident, noticed at once as open/fallback. The watcher's guide showed step 4 with Break the feed inactive (`incident_in_progress`). These are exactly `GuideRefresh`'s CI symptoms.
  - With the mark released at the clean-up time instead: nothing in 16 s, step 3, active.
  - Failures sent after a release made an incident within about 1 s.
- **Deleting an incident mid-settle** (8.6 s): nothing came back in 24 s, with no decision and no incident event. The waiter writes nothing.
- **Lane-b.** A warm run of the whole lane-b shard (84 s), and `BreakFeedProduction` alone, left no incident locally. The double takes the batches during that class. The `instance` incident in CI depends on timing, either leftovers read late or batches queued to the double at the restore (inference). The fix works whichever it was.
- **Why the floor passed locally.** `Fixture.Check` rows carry no `CreatedAt`. With no mark, `Mark.Start` begins at the poll time, so a fast local batch can fall between two polls and never be read. That would explain why the floor cases passed locally (an inference from `Mark.Start`).
- **No filter for the floor unit.** `test-floor.sh` runs `npm --prefix web run e2e:floor` with no arguments, and `docker/**` is contended. So the floor unit has no filter.
- **CI logs.** Both red runs have M4 red too, at L282: the real lines "Waiting for the failures to settle" and "Working out the cause from the failed messages".

**Epic context check:**
- Confirmed:
  - the visibility filter ignores state (`INCIDENTVISIBLE`, `newestIncident`);
  - one durable FLOOR session (AD-4; the helpers use `Session.ForUser`);
  - deleting `BreakFeedRun` rows widens the window (`Compute` L79-84);
  - fixtures write `Incident` rows (`Fixture.Incident`, `Clean`).
- "A clean-up must not depend on which diagnosis the mock gives": met. The hold does not depend on any diagnosis, so nothing is made that would need removing or closing.
- Corrected: "a typical notice comes 30 to 35 s after the press" is about 10 s after the last failure on a no-key stack (the quiet rule).

**Ledger inbox (Rule 17).** DW-305 is addressed in full:
- the floor half by M4's hold and release;
- the lane-b half by the two senders' hold and release.

`GuideRefresh` needs no edit, because the only lane-b classes that send real failing Orders messages are `Test.Demo.BreakFeedProduction` and `Test.Demo.Production`. The search found no other caller of `Partner.Send`, `Test.Demo.Production.Send` or a real `BreakFeedIn` press under `Test/`, except `Test.Watch.*` in lane-a, which cleans up its own incidents. With both holding and releasing, no failure of theirs is ever read, so no lane-b test leaves an Orders incident.

A fact for the orchestrator: if `GuideRefresh` flakes again from a sender added later, the consumer-side change belongs in `Test.Live.GuideRefresh` (contended, Epic 6): hold in `OnBeforeAllTests` L34-41 and release in `OnAfterAllTests` L57-62. That is not planned here.

**Decided in-stage:**
- **M4's own red is in scope.** It has the same cause, red in both runs at L282, and the story's intent is that the guide's tests hold.
- **Hold rather than remove.** M4 never covered a real incident: it was written when `IncidentManager` was a stub. Removing what the press makes would leave M4 racing the real progress events, and on a no-key stack the notice arrives during M4 (Task 0).
- **Release to now plus OVERLAP**, not a deleted or restored mark:
  - a deleted mark is safe only for watches without a `CreatedAt`;
  - a restored older mark re-exposes leftovers (measured);
  - the release time hides every earlier failure and no later one (measured).
- **No guard that deletes incidents when a case starts.** It would hide AC1's pin, because a leak would be deleted before M7 looks. A noticed incident of the session really is step 3 done.
- **`DropIncidentRows` made public** (Epic 5's own file) rather than copied.
- **Not in scope:**
  - Epic 8's real Tick running M4's fixture check row (`NextDueAt` empty) belongs to DW-289's family;
  - the demo-path unit's real press (contended, green).

**Footprint extensions (Rule 11; not contended per the orchestrator):**
- `web/e2e/floor/guide.spec.ts`
- `web/e2e/support/guide.ts`
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls`
- `src/ocutalon/cls/OcuTalon/Test/Demo/BreakFeedProduction.cls`

`Test/Watch/Case.cls` is in Epic 5's own footprint.

## Verification

`<lane>` stands for:

```
env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'
```

- Run one command per call, each with `timeout: 600000`.
- Never put two IRIS test runs in one message.

**Commands:**
- **(loop) Warm stack:** `<lane> OCUTALON_RUN_TAG=e5s11iw ci/warm.sh up`, once per stage. Expected: `WARM up … ready`.
- **(loop) Warm class runs:** `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s11iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Demo.Production` (about 35 s), `OcuTalon.Test.Demo.BreakFeedProduction`, `OcuTalon.Test.Live.GuideRefresh`. Expected: `CLASS … passed`.
- **(loop) Lint:** `npm --prefix web run lint`. Expected: exit 0.
- **(loop) The floor unit:** `<lane> OCUTALON_RUN_TAG=e5s11i perl -e 'alarm 585; exec @ARGV' ci/iris.sh live floor`.
  - It has no filter (Task 0), so this is the whole unit: about 520-540 s with three browsers.
  - Expected: `PASS … the specs of the floor projects pass` and `UNIT live:floor passed`. Record the time.
- **(once) Mutation H:** in `Test.Demo.Production.HoldFailures`, write `MarkAt` = now.
  - Run the floor unit, then `Test.Demo.Production` and `Test.Demo.BreakFeedProduction` warm.
  - Expected red: M4 (the new assertion), M7 L339, M9 L490, `TestHoldHidesFailures`, and the `BreakFeedProduction` assertion.
  - Revert, and check that `git status --short` and `git diff --stat` are byte-identical to before.
- **(once) More mutations:**
  - `ReleaseFailures` as a no-op → `TestReleaseHidesLeftovers` red.
  - `ReleaseFailures` writing now + `HOLDSECONDS` → `TestReleaseKeepsLaterFailures` red.
  - Revert each one byte-identically.
- **(once) Interference runs:**
  - Floor: `dropBreakFeed` without its `RemoveMessages` call (the run rows are still deleted, so no run stays in M7's window) → the floor unit stays green (M7 and M9 included).
  - Lane-b warm: `BreakFeedProduction.OnAfterAllTests` without its OCUORDERS `RemoveMessages`, then `BreakFeedProduction`, then `GuideRefresh`, each in its own call → green.
  - Revert both. Record each as `interference: <where> → green`.
- **(once) Lane-b shard:** `<lane> OCUTALON_RUN_TAG=e5s11i ci/iris.sh shard lane-b`, about 2-3 min. Expected: `SHARD lane-b passed`.
- **(once) Checks:** `bash ci/checks.sh`. Expected: all pass.
- **(once) Teardown:** `<lane> OCUTALON_RUN_TAG=e5s11iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s11i ci/iris.sh teardown`, also after a failure. Confirm that the lane-a lock folder is empty.

**Recorded runs (implement, 2026-10-27; each mutation applied, observed red, reverted byte-identically with `git status --short` and `git diff --stat` unchanged):**
- mutation: `HoldFailures` writes `MarkAt` = now (Mutation H) -> floor unit red: M4 at the new `pressIncidents` assertion (`incidents: 1, groups: 1`), M7 ("no notice brings the prompt back"; the page opened at step 4) and M9 ("while step 5 is current the box is the secondary style"); `Test.Demo.Production` red: `TestHoldHidesFailures` ("no Orders incident was made since the test began"); `Test.Demo.BreakFeedProduction` red: `TestPressSendsFiftyRealFailures` ("FailurePoller sent nothing to IncidentManager: the failures are held")
- mutation: `ReleaseFailures` as a no-op (`Quit $$$OK`) -> `TestReleaseHidesLeftovers` red (4 assertions: the incident since the start, the watcher's newest incident, the incident in progress, Break the feed active) and `TestReleaseKeepsLaterFailures` red (the mark stays held)
- mutation: `ReleaseFailures` writes `MarkAt` = now + `HOLDSECONDS` -> `TestReleaseKeepsLaterFailures` red ("an incident of the watcher appears within 15 s"); the other tests stay green
- interference: `dropBreakFeed` without its `RemoveMessages` call -> floor unit green (99 passed, M7 and M9 included)
- interference: `BreakFeedProduction.OnAfterAllTests` without its OCUORDERS `RemoveMessages`, then `BreakFeedProduction`, then `GuideRefresh` warm, one per call -> green
- Loop and once results: warm `Test.Demo.Production` passed (29 s), `Test.Demo.BreakFeedProduction` passed (20 s), `Test.Live.GuideRefresh` passed (6 s); `npm --prefix web run lint` exit 0; floor unit passed (99 passed in 3.8 min, 344 s from the call, `test-floor: all checks passed`); `ci/iris.sh shard lane-b` passed (58 classes, 196 s); `bash ci/checks.sh` all scripts passed. The stack needed `ci/iris.sh build` once, because the gitignored web bundle in the worktree predated the merge.

**Shared surfaces:**
- **The Orders `WatchMark` row in the lane-b and floor stacks.** After a holder ends, the mark sits at its release time. Watches of Orders that come later read from there, so new failures are read as before. No lane-b or floor test reads that row. `Test.Watch.*` runs in lane-a's own stack and clears the mark itself.
- **`Test.Demo.Production`:**
  - it gains two class methods, three tests and hooks;
  - its public helpers are unchanged (callers: `BreakFeedProduction`, `web/e2e/demo-path/04-incident.spec.ts`, `record-eval.sh`);
  - `test-install-start.sh`'s check (every test fails with the reason when there is no OCUORDERS) must still hold.
- **`Case.DropIncidentRows`:** only its visibility changes.
- **`support/guide.ts`:** three exports are added; existing exports are unchanged.
- Lane-b gains no class (the new tests go into an existing class), and `ci/units.sh` is unchanged.
- Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-27).** The run was planned only and halted after planning, as asked. Nothing was implemented or committed.
- **Task 0** used the warm throwaway `e5s11pw` on lane A. It confirmed the hypothesis, with the timing corrected (the notice comes about 10 s after the batch on a no-key stack), and measured the hold and the release (Design Notes). The stack is torn down and the lane-a lock folder is empty.
- **Footprint.** No contended file and no product file is planned. The four footprint extensions are listed under Design Notes. The `GuideRefresh` half is fixed at its two senders in `Test/Demo/**`, with the reason this is sufficient. The consumer-side fallback is recorded for the orchestrator.
- **Ledger.** DW-305 is addressed in full.

**Implement stage (2026-10-27).**
- **Change.** The Orders `WatchMark` is held 600 s ahead while a test sends real failing Orders messages and put at the release time when its batches are complete. `Test.Demo.Production` gains `HoldFailures`, `ReleaseFailures`, `PutMark`, three tests (`TestHoldHidesFailures`, `TestReleaseHidesLeftovers`, `TestReleaseKeepsLaterFailures`) and the hooks; `BreakFeedProduction` holds and releases for the class and asserts that `FailurePoller` sent nothing to `IncidentManager`; `support/guide.ts` gains `holdOrdersFailures`, `releaseOrdersFailures` and `pressIncidents`; M4 holds first, releases in a nested `finally` and asserts `{incidents: 0, groups: 0}`.
- **Files.** `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls` (hold, release, tests, hooks), `src/ocutalon/cls/OcuTalon/Test/Demo/BreakFeedProduction.cls` (hold, release, assertion, class doc), `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` (`DropIncidentRows` public), `web/e2e/support/guide.ts` (three helpers), `web/e2e/floor/guide.spec.ts` (M4).
- **Review.** 22 findings from three layers (the intent layer reported none): 0 high, 0 medium, 19 low, 3 false. Patches: M4's `finally` nests its three steps (one root cause, four reports), a comment on the 11 s wait, and the `mutation:` lines. Nothing deferred by this pass (the plan's `deferred:` entry is kept). Every other finding is rejected with its reason in the triage log.
- **Verification.** Recorded under `## Verification` (loop, mutations, interference, lane-b shard, checks). Floor unit 99 passed (344 s). Follow-up review recommended: false (no high, no two mediums patched).
- **Residual risks.** The absence assertions use fixed waits (7 s, 4 s); a very slow stack could pass them without proof, which the mutation runs show does not happen on the lane-A stack. The release call sites are pinned only through their effects on the next cases.
- **Footprint.** Only the four extensions and `Test/Watch/Case.cls`. No contended file and no product code. `Test.Live.GuideRefresh` is unchanged. Warm and fresh stacks are torn down and the lane-a lock folder is empty.
