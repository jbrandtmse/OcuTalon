---
title: 'Story 17.7: Give an all-clear only when every check passed'
type: 'feature'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 17.6's digest takes its catalog key from `Checks.Render`, but it builds `whatFailed`, the choice of `digest.checkedQuiet` and the healthy sentence from the raw row results, in `Coverage.Build`'s order. So a not-checked entry can be named before a failed one, and a "passed" row that has no check time can still produce "(all running, no errors, no backlog)" or a refused render. No test pins the all-clear rules as one rule set. No test pins the guard against a digest summary that claims everything is fine. And the evaluation set has no digest case: AD-22's `DigestCase` and `DigestResult` don't exist, and EvalIn, Digest, EvalSink and Report don't know the kind `digest`.

**Approach:**
- `Digest` builds every verdict from `Checks.Render`'s output rows: the named entries (failed first, then not checked), the quiet sentence, the failed rows for needs-you, and the healthy sentence (whose vital rows must pass by Render's rule).
- The three step-2 cases are pinned as automated tests and recorded as `eval/` cases of kind `digest`.
- EvalIn sends each digest case to `Digest` as an `OcuTalon.Eval.Msg.DigestCase`. Digest composes from the recorded rows, with no session, and sends EvalSink an `OcuTalon.Eval.Msg.DigestResult`. Report scores the result into the all-clear score.
- A production test shows the guard stripping a mocked summary that claims everything is fine.

## Boundaries & Constraints

**Always:**
- **One verdict for both paths.** The session compose and the eval compose use one shared verdict:
  - The watched rows are the rows after `vitals.rows`.
  - `checkKey` is `Checks.Render.Render(watched, .ordered)`. With no watched row it is `checks.nothingWatched`, and the part is `digest.nothingWatched` alone.
  - `named` holds the entries of `ordered` rows whose `result` is not `passed`, in `ordered`'s order (failed, then not checked). It is `whatFailed`, joined by `Joined`.
  - `failed` holds the `ordered` rows whose `result` is `failed`. It goes to NeedsYou.
  - `checked` holds the watched rows with a non-blank string `entry`, in Build's order. Each is `"the "_entry` in `{checked}`.
  - The part is `digest.checkedQuiet` exactly when `named` is empty.
  - The vitals part is `digest.healthy` only when `Render(vitals.rows, .v)` is `checks.allPassed` and `v` holds as many rows as `vitals.rows`. Otherwise it is `digest.vitalsNotAll`, whose `whatFailed` is the vital entries that did not pass, in Render's order.
  - AllClear is 1 only when `checkKey = checks.allPassed`, the vitals part is `digest.healthy`, and `needs.count = 0`.
- **The session digest is otherwise unchanged:**
  - The Notification's CatalogKey is `checkKey` (AD-28).
  - The Slots `lines` and `rows` are Build's, unchanged (AD-32).
  - The part order, the texts, routing, `Sent` and cost are as Story 17.6 left them.
- **DigestCase** (new, `Extends Ens.Request`; the shape is AD-22's). Its properties:
  - `ItemId`, minted by EvalIn: the key of the CaseResult row;
  - `SourceItemId`, the case's name;
  - `RecordedChecks`, the watched rows as JSON array text;
  - `RecordedVitals`, `{rows, figures}` as JSON object text, which may be empty;
  - `RecordedSaved`, saved summaries as JSON array text, which may be empty.

  It has no owner property. Digest uses `Ownership.#EVAL` for everything it does with a case, so no message can point a case at a session.
- **How Digest handles a DigestCase:**
  - No Session lookup, no `Sent()`, no `Channels`, no `Rows` (so no Build and no `Watch.Reader`), no `Cost`, no `Sent` row, no Notification.
  - Rows = the vital rows followed by the recorded checks. An unparsable recorded value counts as `[]` or `{}`.
  - Needs-you is `NeedsYou.List(Ownership.#EVAL, failed)`. For owner `eval`, `List` names only the failed rows: it skips `Ownership.Incidents` and `Decisions`.
  - With `RecordedSaved` non-empty, it makes one summary request, `SummaryRequest` with `OwnerRef` `eval`. `OnResponse` finishes it the same way it finishes a Compose.
  - Then it sends EvalSink one **DigestResult** (new, `Extends Ens.Request`) through a new private seam `SendResult` (async, no answer). Its properties: `ItemId`, `SourceItemId`, `CatalogKey`, `AllClear`, `Named` (JSON array text), `Checked` (JSON array text of the raw entries), `DecisionRef` (the summary's, or ""), `Fallback` and `FallbackReason`.
- **EvalIn and the case files:**
  - EvalIn gains the kind `digest` in `KINDS`. It is not in `TURNKINDS`.
  - `SendDigest(case, name)` refuses a non-array `checks` with the existing `REASONNOCHECKS`. Otherwise it opens the row, then `DispatchDigest` (async to `Digest`, private, overridden by the double). A failed send removes the row.
  - A case file holds `name`, `kind` `digest`, `heldOut` false, `description`, `recordedBy`, `checks` (the watched rows), `vitals` `{rows, figures}`, and optionally `saved`.
  - Its `expectation` is `{allClear, catalogKey, named, checked}`.
  - Folder names start with `digest-`, never `heartbeat-`.
- **EvalSink** accepts a DigestResult and completes its row as it does for a TurnResult: DecisionRef, Fallback, cost and size when a DecisionRef exists, `Outcome` "", state decided.
- **Report:**
  - `CASEKINDS` gains `digest`.
  - `ScoreDigest` marks a case right only when the row is decided with no fallback, a DigestResult of its ItemId exists, and its `CatalogKey`, `AllClear`, `Named` (exact order) and `Checked` (exact order) equal the expectation.
  - A missing expectation field gives the existing `REASONNOEXPECTATION`. A decided row with no DigestResult is not right, and `got` is `NOKEY`.
  - It pushes a `cases[]` entry with `expected` = `catalogKey` and `got` = the result's key, and tallies `allClear`.
- **Text.** No new user-facing text, and no new catalog key. Only these texts are new: the mock scenario's text and the case descriptions, which are CI and developer fixtures (Design Notes).
- ASCII source, with contract-only comments (Rule 14).

**Never:**
- Edit `Checks/Render.cls`, `Checks/ReplyGuard.cls`, `Msg/Catalog/**` or `Test/Msg/Catalog.cls`, any Lane B class or test (U-177), `Watch/Reader.cls` (Epic 7), `eval/run.sh` or any existing `eval/` file, `ci/units.sh`, `Production.cls`, or the spine.
- Run a second guard in Digest. Decide's guard is the only one (AD-28, AD-31).
- Read a destination, an owner or a session from a DigestCase.
- Use real keys or real Telegram.
- Put a mock marker in an `eval/` case outside `eval/mock-wrong/`.
- Build the web or phone digest copy (Story 18.4) or reorder Slots `rows` or `lines`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Item in error (step 2, case 1) | watched: Results passed, Orders failed (Build order), healthy vitals | key `checks.notEverythingRestPassed`, `whatFailed` "Orders production", the rendered part names it before "Everything else I checked passed."; AllClear 0 | none |
| Heartbeat stopped (case 2) | the watched checks `not_checked` "Background checks were paused" (Build over a heartbeat gap) | key `checks.notEverything`, its entries named, no "Everything else"; AllClear 0 | none |
| All passing (case 3) | every watched row passed with a check time, healthy vitals, nothing open | `checks.allPassed`, `digest.checkedQuiet` with every entry, AllClear 1 | none |
| Failed vs not checked | Build order: A not_checked, B failed | `whatFailed` "B and A" | none |
| Pass without a time | a watched row "passed" with `checkedAt` "" | Render: not_checked; `digest.checked`, named; AllClear 0; the part renders | none |
| Vital without a time | one vital "passed" with no `checkedAt` | `digest.vitalsNotAll` names it; AllClear 0 | none |
| Nothing watched | no watched row, healthy vitals, nothing open | parts greeting, `digest.healthy`, `digest.nothingWatched`; key `checks.nothingWatched`; AllClear 0; no "Everything I checked passed." | none |
| Model claims fine | a failing row and a saved item whose mock summary is the 3 reserved + 6 banned phrases + one plain sentence | `digest.saved` summary = `ReplyGuard.Filter` of the mock text (none of the 9 phrases, the sentence kept); AllClear 0; the Telegram rendering has no "Everything I checked passed." | none |
| UJ-2 morning | every fixture row passed, vitals figures 3/60/20, 08:00 | the rendering holds "Good morning.", "Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.", "I checked the ... (all running, no errors, no backlog).", "Everything I checked passed." | none |
| Eval digest case | the three `digest-*` cases through EvalIn | one DigestResult each to EvalSink; rows decided; all three right in `allClear`; no Notification, Delivery, Sent row of owner eval, live event, or header to Notify/`*Out` | bad `checks`: skipped with `REASONNOCHECKS` |
| Eval case with saved | a DigestCase with `RecordedSaved` (probe) | one summary request, OwnerRef `eval`, then a DigestResult with its DecisionRef | send fails: DigestResult with Fallback, reason `unusable` |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/`.

- `Digest/Process.cls` (776 lines):
  - `OnRequest` :137-146 dispatches Tick, SendDigest and Compose; anything else is error 5001.
  - `OnResponse` :157-183 quits unless the request is a Compose (:161) and finishes through `Finish` (:178).
  - `Composed` :406-437: session :412, `Sent` :415, `Channels` :416, `Saved` :418, `OwnerRef` :426. `SummaryRequest` :448 sets no owner.
  - `Finish` :482-566:
    - watched/failed :492-497 (raw);
    - `Render(watched)` :502 (no `.rows`);
    - `missing` :507-510 (raw, Build order), nothing-watched :511-513, `named` :515-519, the parts :520-521;
    - the AllClear line :560.
  - `Vitals` :671-683 (raw results), `Joined` :686.
  - Seams: `Rows` :697, `SendSummary` :716, `Cost` :722, `NeedsYou` :728, `SendNotice` :744, `SendCompose` :750.
  - Properties: `ItemId` and `CallError` only (AD-3).
- `Checks/Render.cls` `Render(results, Output rows)` :36 is pure and orders the rows failed, then not checked, then passed. Keys :18-27: `checks.allPassed`, `checks.notEverythingRestPassed`, `checks.notEverything`, `checks.nothingWatched`. `Row` :82-95 makes a row with no UTC `checkedAt` not_checked. Read only.
- `Checks/ReplyGuard.cls`: `RESERVED` :19, `BANNED` :22, `Filter` :28 (fails closed to ""). Run by Decide's `Conclude` (`src/bridge/.../Bridge/Process/Decide.cls` :211, :424). Read only. Its unit tests are in `Test/Checks/Guard.cls`.
- `Checks/Coverage.cls` `Build` :125. Rows are `{result, entry, finding, checkedAt}`, with the first five rows vital. `vitals` = `{rows, figures{upDays, databasesFull, licenseUse}}` :129.
- `Digest/NeedsYou.cls` `List` :26: failed rows :31-38, `Ownership.Incidents` :40, `Decisions` :53. `Ownership.Rows` refuses `eval`.
- `Msg/Catalog/Watch.cls`: `checks.*` :54-78 (both `checks.notEverythingRestPassed` :61 and `checks.everythingElsePassed` :68 exist), `digest.*` :336-504. Read only.
- `Data/Ownership.cls` `EVAL` :57 (read only).
- Eval (outside the paths_hint, not contended; footprint extensions):
  - `Eval/In.cls`:
    - `KINDS` :74 and `TURNKINDS` :80;
    - `Send` :307, where the incident dispatch :319 is the place for the digest dispatch;
    - siblings `SendIncident` :370 and `DispatchIncident` :437; `Deliver` :653; `REASONNOCHECKS` :124.
  - `Eval/Sink.cls`: `Complete` :49 (turn branch :61), `Refusal` :86, `Known` :94-97, and the class doc :1-21.
  - `Eval/Report.cls` (Epic 19 edits `TOOLCLASSES` :97, a different hunk):
    - `CASEKINDS` :71, `NOKEY` :90, `REASONNOEXPECTATION` :151;
    - `Score` :387, with the branches :405-431;
    - siblings `ScoreTurn` :598 and `TurnOf` :719; `Tally`.
  - `Eval/Msg/TurnResult.cls` is the message sibling. `Eval/Data/CaseResult.cls` `Open` :99, `Pending` :115, `Remove` :143.
- Tests:
  - `Test/Digest/Compose.cls` (ZoneCase):
    - helpers `Host` :175, `Compose` :184, `Handle` :197, `Notice` :204, `Part` :223, `Render` :237, `Watched` :311;
    - `TestPartOrder` :316, `TestQuietDay` :345, `TestNothingWatched` :360, `TestVitalsNotAll` :373, `TestSentRow` :540, `TestAllClearNeedsVitalsAndNothingOpen` :566.
  - `Test/Digest/ProcessProbe.cls`: `Feed` :57, `Healthy` :63, `SendNotice` :247, `SendSummary` :256, `Rows` :266, `Reset` :50.
  - `Test/Digest/CoverageProbe.cls` `FeedRead` :68 and `FeedGaps` :74. `Test/Digest/Coverage.cls` `TestPaused` :236 is the gap recipe, with its `Watch`/`Every`/`Built` helpers.
  - `Test/Digest/Send.cls` (the real production with the mock): `TestSavedSummaryThroughDecide` :435, `Item` :410, `UseItemClass` :295, `Unswap` :91. `Test/Digest/FailRowsDigest.cls` is the sibling for a fed `Rows`.
  - `Test/Channel/TelegramDigest.cls` is the Telegram rendering of a digest (regression).
  - `Test/Eval/Cases.cls` `TestRecordedCases` :112-178 (else branch :166, minimum counts :170-177). `Test/Eval/ZzIn.cls` overrides :24/:37/:48/:89. `Test/Eval/In.cls` `TestSendOrder` :741.
  - `Test/Eval/Report.cls` `TestEveryKindSent` :1112. `Test/Eval/Sink.cls` `TestTurnResult` :275.
  - `Test/Eval/Run.cls` (FRESH):
    - runs in `OnBeforeAllTests` :194, with `RUN1CASES` :80 and `ITEMPATH` :107;
    - `TestRefusals` :697, `TestIsolation` :753, `TestHops` :796 (the exact `EvalIn>` pin :832), `TestUsage` :841 (15 decisions), `Refs` :1249.
- `docker/tests/test-eval-set.sh`: rule header :20-60; the per-kind branches :358-386 (all-clear :358 is the sibling); the `set` rule :470-510; variants ~:1038.
- `ci/mock/scenarios/A/digest-summary.json` is the marker sibling. `checks-false-all-clear.json` is not reusable: its first reply is a triage JSON.

## Tasks & Acceptance

**Execution:**
- [ ] `Eval/Msg/DigestCase.cls` and `Eval/Msg/DigestResult.cls` (new, with storage, and docs naming the writer and readers as `TurnResult` does). These come first because the tasks after them compile against them.
- [ ] `Digest/Process.cls`: one private verdict method shared by `Finish` and the case path. It computes the contract's `checkKey`, `ordered`, `named`, `failed`, `checked`, the vitals part and AllClear. `Vitals` follows Render's rule.
  - `Finish` keeps its parts, routing and `Sent` and takes its values from the verdict. The doc comment is updated.
  - `OnRequest` takes `OcuTalon.Eval.Msg.DigestCase` into a new `Evaluated(case)`. `OnResponse` also finishes a DigestCase into a new `FinishCase`.
  - New private seam `SendResult(result)` sends to `EvalSink`, with an `EVALSINK` parameter.
- [ ] `Digest/NeedsYou.cls` `List`: for `sessionRef = Ownership.#EVAL`, name only the failed rows. Update the doc.
- [ ] `Eval/In.cls`: `DIGESTKIND`, `KINDS` + `digest`, `DIGEST` = "Digest", `SendDigest` and `DispatchDigest`. Update the class doc.
- [ ] `Eval/Sink.cls`: `Known` and `Refusal` take a DigestResult, and `Complete` handles it like a TurnResult. Update the doc.
- [ ] `Eval/Report.cls`: `CASEKINDS` + `digest`, a `Score` branch, `ScoreDigest` and `DigestOf(itemId)`, all appended at the end of the class. Update the doc.
- [ ] `eval/digest-production-error/`, `eval/digest-checks-paused/`, `eval/digest-all-passing/` (new `case.json` files, recorded from the rows of the automated test below, with no `saved`).
- [ ] `ci/mock/scenarios/A/digest-claims-fine.json` (new). It has a marker match and one text reply holding the three reserved sentences, the six banned phrases (`everything’s fine` escaped) and one plain sentence.
- [ ] `docker/tests/test-eval-set.sh`: a `digest` branch. It requires `checks` rows in the all-clear rules' shape, `vitals.rows` (the same shape) and a `figures` object, `expectation.allClear` boolean, `catalogKey` one of the Render keys, `named` and `checked` arrays of strings, and no `turn`, `item` or `heldOut` true. The `set` rule requires the three situations (one `allClear` true; one `checks.notEverythingRestPassed` with a failed row; one with a not_checked "Background checks were paused" row). Add bad variants for each, and update the header.
- [ ] Tests:
  - `Test/Digest/AllClear.cls` (new, ZoneCase, probe compose):
    - each of the three step-2 cases with rows from `CoverageProbe` Build (an errored production through `FeedRead`; a gap through `FeedGaps`; all passing);
    - the key, AllClear, `whatFailed` order and the rendered reserved part;
    - that the case file's recorded rows, expectation and the probe's results agree;
    - the rows Failed vs not checked, Pass without a time, Vital without a time, Nothing watched (strengthened: no "Everything I checked passed." in the rendering), and UJ-2 morning.
  - `Test/Digest/EvalCase.cls` (new, probe):
    - a DigestCase never calls `Rows`, `Cost`, `SendNotice` or `Channels`, and writes no `Sent` row;
    - the DigestResult fields for each case;
    - with `RecordedSaved`: one request with OwnerRef `eval`, finished in `OnResponse`, and the send-failure fallback.
  - `Test/Digest/NeedsYou.cls`: an eval-owner test.
  - `Test/Digest/FedRowsDigest.cls` (new, a `Rows` that answers fixed rows) and `Test/Digest/Send.cls` `TestModelClaimsFine`:
    - the real Decide, guard and mock;
    - the summary equals `ReplyGuard.Filter(scenario text)`, holds none of the nine phrases and keeps the plain sentence;
    - AllClear 0, CatalogKey not `checks.allPassed`;
    - the rendered digest has no reserved all-clear or banned phrase, and "Your IRIS system is healthy" only once, from the `digest.healthy` part.
  - `Test/Eval/ZzIn.cls`: `DispatchDigest` records the case.
  - `Test/Eval/Cases.cls`: a digest branch (sent, fields; Render over `checks` gives `expectation.catalogKey`) and a minimum of 3 digest cases.
  - `Test/Eval/In.cls`: `SendDigest` (row, refusal, failed send) and `TestSendOrder` with a digest entry among the rest.
  - `Test/Eval/Sink.cls` `TestDigestResult`.
  - `Test/Eval/Report.cls` `TestDigestScore` (right; and each of key, AllClear, named order and checked wrong; no result; tallied in allClear).
  - `Test/Eval/Run.cls`:
    - run 6, `Start` over `eval/` with the three digest names;
    - `TestDigestRun`: rows decided, results equal the expectations, Report right;
    - `ITEMPATH` + `Digest`; the `TestHops` pin + `EvalIn>Digest`, plus `Digest>EvalSink` only;
    - `TestRefusals` + run 6; `TestIsolation` covers run 6 and also checks that no `Sent` row was added;
    - `TestUsage` unchanged (no decisions).

- [ ] DW-816 (routed to this story by Story 17.6's code review 3, 2026-11-06, after the spec gate): ticks a test sends a day or more ahead (Epic 39's beat tests at now plus 48 hours) make `Digest` queue scheduled digests for every other session on the stack and leave future-dated `Sent` rows, which suppress that stack's real scheduled digests. Make this story's own tests tick without making other sessions due, and either scope the due check so a test tick cannot reach other sessions or have the tests that send far-ahead ticks remove the `Sent` rows they cause; a test pins that no test leaves a future `Sent` row behind (with its mutation). If the fix needs a change to the ruled due rule, HALT with an intent gap.

**Acceptance Criteria:**
- Given any rows (Build's or recorded), when a digest is composed, then the key, `whatFailed` (failed first, then not checked), the quiet sentence, the healthy sentence and AllClear all come from `Checks.Render`'s output. "Everything I checked passed." appears only when every entry passed, with `{checked}`. "Everything else I checked passed." follows the named entries only when another entry passed.
- Given no watched row, when composed, then the vital signs are reported, the digest says OcuTalon isn't watching any productions yet, and no rendering or flag gives an all-clear.
- Given the mocked summary claims everything is fine while a check fails, when the digest goes through the real production, then the guard has removed every reserved sentence and banned phrase, and the digest has AllClear 0 and no all-clear sentence.
- Given the three step-2 cases, when they run as automated tests and as eval cases, then the first two give no all-clear and name their entry first, and the third gives the all-clear with what was checked. The eval run writes no Notification, Delivery, Sent row or live event, and Report scores all three right.
- Given UJ-2 with every fixture check passing, when the Slots are composed, then the figures, "(all running, no errors, no backlog)", "Your IRIS system is healthy" and "Everything I checked passed." come from code parts, never from the summary slot.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-2 (the reserved owner `eval`), AD-3, AD-5, AD-18, AD-22, AD-28, AD-30, AD-31, AD-32 and AD-33. No AC contradicts an AD's Rule.

**The two "everything else passed" keys (asked by the lead).**
- The code has both, in `Msg/Catalog/Watch.cls`:
  - `checks.notEverythingRestPassed` (:61, "Not everything: {whatFailed}. Everything else I checked passed.") is what `Checks.Render` returns (`KEYRESTPASSED`, `Render.cls` :21) and what the digest carries.
  - `checks.everythingElsePassed` (:68, the sentence alone) is produced by no code. Only tests (`Test/Checks/Guard.cls` :39, `Test/Core/ConversationTurns.cls` :1590) and the catalog fixture name it.
- The Conventions' HostData row is right.
- AD-32's digest bullet is wrong: "plus the existing `checks.allPassed` and `checks.everythingElsePassed`".
- **Proposed spine fix (for the lead, apply-and-report tier):** in AD-32, "The digest notification", replace "plus the existing `checks.allPassed` and `checks.everythingElsePassed`" with "plus the `checks.*` keys that `Checks.Render` returns (`checks.allPassed`, `checks.notEverything`, `checks.notEverythingRestPassed`, `checks.nothingWatched`)".

**Decided in-stage.**
1. **"Named first"** means two things: inside the reserved sentence, `whatFailed` precedes "Everything else I checked passed." (the text of `notEverythingRestPassed`), and Render's order is failed, then not checked. Slots `lines` and `rows` keep Build's order (17.6's contract; AD-28 "rows come only from Build"). How the web card orders them is Story 18.4's.
2. **`whatFailed` stays entries only** (17.6 Decided 3). The Conventions' `{entry} ({finding}, at {time})` form is for a renderer of check rows. A producer's slot can't hold a reader-zone time (AD-32: times in Slots are UTC ISO, rendered by `*Out`). The coverage lines carry each finding and time.
3. **DigestCase has no owner property.** Digest uses `Ownership.#EVAL` itself, so AD-22's "owner eval" holds by construction, and nothing in a message can aim a case at a session.
4. **Digest cases tally into the existing `allClear` score.** They are FR-37's all-clear cases, so no new score and no change to `Gate.SCORES`. `cases[]` uses `catalogKey` for expected and got, as all-clear turns do. `right` carries the whole comparison.
5. **The three eval cases have no `saved`.** On the CI mock, a summary would need a marker, which `test-eval-set.sh` forbids outside `eval/mock-wrong/`, and the score does not read the summary. `RecordedSaved` exists so that AD-22's "model request owner eval" is built and pinned (probe test). `Test.Eval.Run` `TestUsage`'s 15 decisions stay.
6. **No new user-facing text.** No catalog key; EvalIn reuses `REASONNOCHECKS`; Report reuses `REASONNOEXPECTATION` and `NOKEY`. The mock scenario's text is CI-only fixture text, and the case `description`s are developer fixtures like Story 9.7's.
7. **NeedsYou for `eval`** skips the session sources, because `Ownership.Rows` refuses `eval`. One guard in `List`, no copy (Rule 2).
8. **Healthy needs every vital row** to pass by Render's rule, with no row dropped, so a vital row with no check time is named, not passed over.
9. **No Task 0.** Every send here (service to process, process to operation, async with no answer) has a sibling in the code.

**Extend, don't copy (Rule 2):**
- The shared verdict replaces `Finish`'s inline logic. It is used by both paths.
- `SendDigest`/`DispatchDigest` follow `SendIncident`/`DispatchIncident`.
- `DigestResult` follows `TurnResult`; `ScoreDigest`/`DigestOf` follow `ScoreTurn`/`TurnOf`.
- `FedRowsDigest` follows `FailRowsDigest`.
- The test-eval-set branch follows the all-clear branch.
- `Checks.Render` and `Checks.ReplyGuard` (AD-28, AD-31) are consumed unchanged.

**Integration ACs (Rule 1):** EvalIn (producer) → Digest (consumer of DigestCase), which produces a DigestResult → EvalSink completes the row → Report scores it right. All of this is in the real production (`Test.Eval.Run` `TestDigestRun`, plus `bash eval/run.sh`).

**Consumes:** 17.6's compose and seams; 17.5's `Coverage.Build` and `CoverageProbe`; 5.7's `ReplyGuard`; 9.x's EvalIn, EvalSink, CaseResult and Report; 33.1's keys.

**Consumed-by:**
- REL-5's release-candidate run (`eval/run.sh --release-candidate` scores the digest cases on Haiku);
- 18.4, which renders the same parts;
- 22.5, whose source rows join `checks` (later digest cases).

**Contention (Rule 11).**
- `git diff` against the bases, 2026-11-06:
  - Epic 19 changes `Eval/Report.cls` :97 (`TOOLCLASSES`) and `Production.cls` :62. This story appends to `Report.cls` and edits :71/:405-431, a plain union, and does not touch `Production.cls`.
  - Epic 7 and Epic 11 show no diff.
- New files go in contended folders: `eval/digest-*/` and `ci/mock/scenarios/A/digest-claims-fine.json` (no collision).
- No Lane B class or test is touched.
- Footprint extensions: `Eval/{In,Sink,Report}.cls`, `Eval/Msg/Digest{Case,Result}.cls`, `Test/Eval/{Cases,In,Sink,Report,Run,ZzIn}.cls`, and `docker/tests/test-eval-set.sh`.
- Story 30.7: nothing here touches its list.

**Ledger (Rule 17):** the inbox is empty.

## Verification

Lane A variables on every `ci/` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=17 stage=implement'`. Use the warm tag `e17s7iw` (`ci/warm.sh up` alone in its call, `ci/warm.sh down` at the end, also after a failure) and the fresh tag `e17s7i` (`ci/iris.sh teardown` at the end). Every call runs in the foreground with `timeout: 600000`, one class per call.

**Commands:**
- `(loop)` `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s7iw ci/iris.sh class OcuTalon.Test.Digest.<C>` for C in AllClear, EvalCase, Compose, NeedsYou -- expected: `CLASS ... passed`.
- `(loop)` the same for `OcuTalon.Test.Eval.<C>`, C in In, Cases, Sink, Report -- passed.
- `(loop)` `OCUTALON_RUN_TAG=e17s7i ci/iris.sh class OcuTalon.Test.Digest.Send` (fresh: the production job must hold the code) -- passed.
- `(loop)` `OCUTALON_RUN_TAG=e17s7i ci/iris.sh class OcuTalon.Test.Eval.Run` (fresh) -- passed.
- `(loop)` `bash docker/tests/test-eval-set.sh`, `bash docker/tests/test-mock.sh`, `bash docker/tests/test-boundaries.sh`, one per call -- each passes.
- `(once)` `OCUTALON_RUN_TAG=e17s7i ci/iris.sh shard lane-a@Digest`, then `... shard lane-a@Eval` (add `--part k/2` if a piece nears 8 minutes) -- every class passed.
- `(once)` `OCUTALON_RUN_TAG=e17s7i ci/iris.sh class OcuTalon.Test.Channel.TelegramDigest` -- passed (the Telegram rendering after the verdict refactor).
- `(once)` `OCUTALON_RUN_TAG=e17s7i bash eval/run.sh` -- the set has no problem, and its `allclear` score counts the three digest cases right.
- `(once)` `bash docker/tests/test-ci-config.sh` -- passes (new classes are in existing areas).

**Shared surfaces:**
- the case set under `eval/` (read by `Test.Eval.Cases`, `test-eval-set.sh`'s `set` rule, `eval/run.sh` and `Test/Checks/Snapshot.cls`'s `heartbeat-*` rule);
- `Eval.In.KINDS` and `Eval.Report.CASEKINDS` (`Test.Eval.Report` `TestEveryKindSent`, `PersonaSweep`);
- `EvalSink`'s accepted classes;
- `Digest.OnRequest`'s classes (`Test.Digest.Contracts` `TestDigestItem`);
- `Test.Eval.Run`'s `ITEMPATH`, `TestHops` pin and `TestRefusals` counts;
- the `allClear` score total.

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; record one `mutation:` line per AC here):**
- AC1:
  - `named` from the raw watched rows in Build order → `AllClear` `TestFailedBeforeNotChecked` red;
  - `checkedQuiet` from raw results → `TestPassWithoutTime` red;
  - `Vitals` on raw results → `TestVitalWithoutTime` red.
- AC2: the nothing-watched branch sets `checks.allPassed` → `AllClear` `TestNothingWatched` red.
- AC3: `digest-claims-fine` text without the guard (point the test's expectation at the raw text) or `BANNED` minus one phrase → `Send` `TestModelClaimsFine` red.
- AC4:
  - AllClear without the `checkKey` term → `AllClear` case 1 red;
  - `ScoreDigest` ignores `Named` → `Report` `TestDigestScore` red;
  - `Evaluated` calls `SendNotice` → `EvalCase` red;
  - run 6 to Notify → `Run` `TestIsolation` red.
- AC5: the healthy figures replaced by constants → `AllClear` `TestMorningDigest` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
