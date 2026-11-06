# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day at the set time, and whenever the user asks, OcuTalon sends one short digest: the vital signs, a coverage list where every entry is passed, failed or not checked (with a reason), what needs the user, what was saved for later, and the previous day's model cost. Only code decides whether an all-clear is given, so a quiet digest really means everything watched was checked and passed. The epic also lets an admin pick each agent's provider and model, set prices, budgets and the instance time zone through the bridge, and name a second model for one retry before the fallback. Stories 17.2 to 17.6 and 17.8 are done. What remains is Story 17.7 (the all-clear rule and its evaluation cases), then the epic's burn-down.

## Stories

- Story 17.2: Retry once on a second model before falling back (done)
- Story 17.3: Run each agent on a supported provider (done)
- Story 17.4: Apply model, price, budget and zone changes through the bridge (done)
- Story 17.5: Check the vital signs and every coverage entry (done)
- Story 17.6: Send the daily digest at the set time and on request (done)
- Story 17.7: Give an all-clear only when every check passed
- Story 17.8: Only Decide moves a conversation's link (done)

## Requirements & Constraints

- **The all-clear rule:**
  - "Everything I checked passed." appears only when every coverage entry passed, and it lists what was checked.
  - Otherwise the failed and not-checked entries are named first. "Everything else I checked passed." follows only when some other entry passed.
  - "Your IRIS system is healthy" appears only when every vital sign passed. Otherwise the failing sign is named ("Not every vital sign passed: {whatFailed}.").
- **Nothing watched:** with no watched productions and no sources, the digest reports the vital signs and says OcuTalon isn't watching any productions yet. It never gives a system-wide all-clear.
- **The model never gives an all-clear.** Suppose the mocked model is told to claim everything is fine while a check fails. The guard removes the reserved sentences and the closed list of banned phrases ("all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about"), and the digest carries no all-clear.
- **The step 2 cases**, each run as an automated test and also as an evaluation case:
  - a watched production with an item in error: no all-clear, and its entry is named first;
  - a check that didn't run because the heartbeat stopped: no all-clear, and its entry is named first;
  - everything passing: an all-clear that lists what was checked.
- **How the evaluation cases score:** on the all-clear flag and on the named entries. The success target is zero all-clears while any entry failed or was not checked, across the evaluation set, the tests and real use.
- **The morning digest with every fixture check passing** (the UJ-2 flow): the vital-sign figures, the production summary "(all running, no errors, no backlog)", "Your IRIS system is healthy" and "Everything I checked passed." all come from code.

## Technical Decisions

- **One source for the all-clear.** The all-clear flag and the reserved sentence's catalog key come only from `OcuTalon.Checks.Render`. A digest's rows come only from `Checks.Coverage.Build`.
  - When the session watches a production, a background check or a source, `Render` runs over every row.
  - When it watches none, `Render` runs over an empty array, which gives `checks.nothingWatched` and never an all-clear. The vital signs are then reported in their own part.
  - The healthy sentence needs every vital-sign row (the `vitals` output of `Coverage.Build`) to have passed.
- **`Render`'s rules:**
  - An element with no `entry` is no result, and a pass needs a check time.
  - Rows are ordered failed, then not checked, then passed.
  - `whatFailed` is built only from rows that didn't pass (the failed ones first), so an all-clear can never come from the rows themselves.
  - Check the "everything else passed" key name against `Catalog.Watch`: the Conventions call it `checks.notEverythingRestPassed`, while the notification contract calls it `checks.everythingElsePassed`.
- **The guard** is `OcuTalon.Checks.ReplyGuard`, the bridge's `ReplyFilterClass`. It runs exactly once on every model-written text leaving `Decide`, including the digest's saved-for-later summary.
  - It matches case-insensitively, with either apostrophe, on whole words, and takes the phrase's punctuation with it.
  - It keeps the rest of the text and never adds any.
  - On an error it returns empty text, so `Decide` falls back. The digest then goes out with `digest.savedNoSummary`.
- **The notification:** one `Notification` of kind `digest`.
  - `CatalogKey` is the all-clear key from `Render`.
  - `Slots` is `{"parts", "lines", "rows"}`. The parts come in this order: greeting, vital signs, what was checked plus the reserved sentence, needs you, saved for later, cost.
  - Producers never render text. Only the `*Out` operations render, through `Catalog.Render`.
  - The `Sent` row records `CatalogKey`, `Slots` and `AllClear`.
- **The evaluation digest case** (new in 17.7):
  - A case of kind `digest` in `eval/` holds recorded check rows. `EvalIn` (enabled only by `OCUTALON_EVAL=1`) sends them to `Digest` as `OcuTalon.Eval.Msg.DigestCase` (owner `eval`, `SourceItemId`, the rows).
  - `Digest` composes with those rows in place of `Coverage.Build`, and its model request has owner `eval`.
  - `Digest` sends `EvalSink` an `OcuTalon.Eval.Msg.DigestResult` (`SourceItemId`, `CatalogKey`, `AllClear`, the named entries, `DecisionRef`) instead of a `Notification`.
  - The run writes no `Notification`, `Delivery` or live event, and no `Usage` row of owner `eval` counts toward the digest's cost.
  - Both message classes are Lane A's and are created in Story 17.7.
  - The existing `allclear-*` cases are step 1 chat (`turn`) cases. The digest cases are separate.
- **Spine changes from 2026-11-06:**
  - Until Story 18.2, `Digest` narrows `Notify`'s generic route itself and sends directly to the outbound items of the session's `digest.channels`.
  - `SendDigest` answers `ok` at once and composes asynchronously. A repeat with the same `IdempotencyKey` (stored on `Sent`) sends nothing new, and a compose or send failure shows in Visual Trace.
  - `BackgroundCheck`'s update trigger calls `Checks.Coverage.RecordRun`, writing one `CheckRun` per `LastRunAt` change. A heartbeat beat writes none.
  - The settings model Test is a connection test for every runner. It never validates the reply against the runner's reply class.
- **No all-clear from heartbeat beats** (Epic 39, merged). A beat has no `BackgroundCheck` row, no coverage entry and no part in an all-clear, and no code renders a beat or an Ignore as "everything is fine".
- **Dependency direction:** `OcuTalon.Digest` may call `Checks.Coverage.Build` and `Checks.Render`. `Checks` writes `Digest.Data.CheckRun` and calls `Schedule.Heartbeat.Gaps`.
- **Where tests run:** they use the CI model mock (`ci/mock/`, scenarios under `ci/mock/scenarios/A/`). The IRIS units for Digest, Checks and Eval run in CI's `lane-a` shard.

## UX & Interaction Patterns

- These catalog texts are fixed by the UX:
  - "I checked {checked} (all running, no errors, no backlog)." when every production entry passed, otherwise "I checked {checked}.";
  - the nothing-watched sentence: "I'm not watching any productions yet, so this digest covers the vital signs only. Ask me to watch one.";
  - the coverage lines, which start "Passed:", "Failed:" or "Not checked:".
- When an entry is not checked, the digest leads with it. For example: "Not checked: Jira (unreachable since 02:10). Everything else I checked passed." The web card's "What I checked" then starts expanded.

## Cross-Story Dependencies

- Story 17.7 builds on Story 17.6's composition and `Sent` record, Story 17.5's coverage rows and `vitals`, and Story 5.7's `ReplyGuard`.
- Lane B's Story 18.2 (`Notify`'s `digest` route) and Story 18.4 (the handled-marker writer, and the web and phone copies) are still in backlog.
- Epic 30 (in progress; its burn-down remains) shares the `Checks`, `Catalog.Watch` and `eval/` footprint.
- **The burn-down** takes Epic 17's ledger entries that are routed to it:
  - DW-786: merge `Checks.Coverage.Live`'s copy of the live-read logic into one `Checks` helper, now that Epic 39 no longer holds `Process.cls`.
  - DW-728: fold `RetryItem` and `RetryOf` into the bridge guide's reference tables, now that Epic 40 has merged. This is public text the Contest Planner approves.
  - DW-771: the connection-test ruling above.
  - DW-799: a `test-mock.sh` flake candidate.
  - DW-755: until another provider has a live proof, no public text may say it runs decisions.
- Epic 17 merges only once `release/1.0.0-rc1` exists, and it ships in the first daily release after 1.0.0.
- Downstream:
  - Epic 22 (Story 22.5) fills the coverage list's sources section.
  - Epic 23 uses the `checks.thresholds.*` keys.
