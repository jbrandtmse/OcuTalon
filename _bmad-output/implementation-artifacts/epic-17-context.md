# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day at the set time, and whenever the user asks, OcuTalon sends one short digest: the vital signs, a coverage list where every entry is passed, failed or not checked (with a reason), what needs the user, what was saved for later, and the previous day's model cost. Only code decides whether an all-clear is given. The epic also lets an admin choose each agent's provider and model, set prices, budgets and the instance time zone through the bridge, and name a second model for one retry before the fallback. Stories 17.2 to 17.8 are done. Only Story 17.9 remains: the burn-down. It makes the settings model Test a plain connection test, puts the checks' live-read logic in one helper, and tidies the bridge guide's reference tables.

## Stories

- Story 17.2: Retry once on a second model before falling back (done)
- Story 17.3: Run each agent on a supported provider (done)
- Story 17.4: Apply model, price, budget and zone changes through the bridge (done)
- Story 17.5: Check the vital signs and every coverage entry (done)
- Story 17.6: Send the daily digest at the set time and on request (done)
- Story 17.7: Give an all-clear only when every check passed (done)
- Story 17.8: Only Decide moves a conversation's link (done)
- Story 17.9: Epic 17 burn-down

## Requirements & Constraints

- **The settings model Test is a connection test for every runner (DW-771).** This includes the diagnosis agent's runner.
  - It passes on any non-empty reply that arrives within the timer through that runner's provider, model and key.
  - It never validates the reply against the runner's reply class.
  - A test must show the diagnosis Test passing on a mock reply that fails `DiagnosisReply` validation. Today the fixed test input ends in fallback `invalid` for diagnosis, because the diagnosis payload needs an evidence pack. The Story 17.4 live test hid this with a `[[mock:diagnosis-unknown]]` marker.
- **The Test's visible answer is fixed by the UX:** "Answered in 1.2 s" or "Didn't answer: {plain reason}", where the reason is a fallback reason. The key never appears.
- **The Test keeps its existing rules:**
  - It is never retried on the second model. Its `ItemId` starts with `test.`.
  - Its usage is recorded under owner `instance`.
  - It sets no sampling parameters and never returns the key.
- **One live-read helper (DW-786).** `Checks.Coverage.Live` and `Checks.Process.Run` must share one helper for:
  - the `not_checked` reason chain;
  - the cut rule;
  - the state text;
  - the failure wording, including its capital letter.
  The copy was forced while Epic 39 held `Process.cls`. Epic 39 has merged, so `Process`'s private `Finding` can now be made callable. The existing tests of both must stay green, so the digest's coverage rows and the checks' results cannot drift apart.
- **Bridge guide tables (DW-728).** `docs/bridge-guide.md` must name `RetryItem` and `RetryOf` in its Settings and Messages reference tables, as well as in the "Second-model retry" section.
  - No other wording changes. Any other change is public text that the Contest Planner approves before it is pushed.
  - The ledger lists other one-attempt wording in the guide: the `TimerSeconds` row, the `DecisionTokenBudget` row (checked per attempt, so a retried decision can use up to twice the budget), the Timeouts section, the fallback route and the `DecisionResponse.Model` row. Changing any of these is the same kind of approval-gated public text.
  - DW-773 is reopened if this pass edits the guide's Settings intro while it still says only `ToolClassification` and `ApprovalRole` are read live. Since Story 17.4, `DecisionTokenBudget`, `RequestTokenLimit`, `DailyCostCapUSD` and `InstanceZone` also apply with no restart.
- **Public-text guard (DW-755, held at close).** No README, guide, settings page or release text may say that a provider other than Anthropic runs decisions until a live proof exists.
- **Flakes.** A flake such as `test-mock.sh`'s one-off 400 (DW-799) gets one rerun and an occurrence line in the ledger, recording the failing row and request.

## Technical Decisions

- **Bridge settings APIs.** `OcuTalon.Bridge.Settings` is the only way `SettingsOps` changes bridge values.
  - `TestRequest(agent, *request)` builds one request of the agent's own kind (`decide`, `diagnose` or `turn`), with provenance `untrusted`, owner `instance`, a fresh `ItemId` and fixed code-written input. `SettingsOps` sends it to `Decide` synchronously.
  - `TestAnswer(response, durationMs)` returns `{answered, seconds, reason}`.
  - Every method refuses a value that holds `@{` or is off the allow-list, with a plain-English reason, and changes nothing.
  - The bridge timer stays at or under 110 s.
- **Second-model retry (as built).**
  - The first runner's host setting `RetryItem` names its retry runner item (`<Agent>Retry`). An empty setting means no second model.
  - A retried request carries `RetryOf`, naming the first runner item.
  - Only `Decide` moves a conversation's link, when it accepts a reply.
- **Coverage.** `Checks.Coverage.Build` is the only builder of the digest's rows and lines, and `Checks.Render` is the only source of the all-clear key.
  - The coverage rows keep release 1's shape: `{result, entry, finding, checkedAt}`.
  - A not-checked row's finding is a short code-written phrase taken from `Checks` class parameters.
- **Digest catalog keys (as built; AD-32 was corrected on 2026-11-06).** `Checks.Render` returns one of `checks.allPassed`, `checks.notEverything`, `checks.notEverythingRestPassed` or `checks.nothingWatched`. All other digest keys live in `Catalog.Watch` under the prefix `digest.`.
- **Dependency direction.** `OcuTalon.Checks` may write `Digest.Data.CheckRun` and call `Schedule.Heartbeat.Gaps`. `OcuTalon.Digest` may call `Checks.Coverage.Build` and `Checks.Render`.
- **Testing.** Tests use the CI model mock (`ci/mock/`, with scenarios under `ci/mock/scenarios/A/`). The IRIS units for Bridge, Checks and Digest run in CI's `lane-a` shard.

## Cross-Story Dependencies

- Story 17.9 builds on:
  - Story 17.4's `TestRequest` and `TestAnswer`;
  - Story 17.5's `Coverage.Live`;
  - Story 17.2's guide section.
- Epics 39 and 40 have merged, which frees `Process.cls` and `docs/bridge-guide.md`.
- Epic 30 is still in progress (its burn-down, Story 30.7, is in backlog) and shares the `Checks` footprint.
- Lane B's Epic 18 is in backlog. It owns the settings page that shows the Test answer (Story 18.3), plus `Notify`'s digest route and the Got it marker.
- Epic 17 merges only once `release/1.0.0-rc1` exists, and it ships in the first daily release after 1.0.0.
