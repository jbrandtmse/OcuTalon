# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 2's Lane A feature epic. Once a day, and whenever the user asks, OcuTalon sends one short digest. It holds the vital signs, a coverage list in which every entry is passed, failed or not checked with a reason, what needs the user, what was saved for later, and the previous day's cost. Only code may give an all-clear. On the model side, an admin can run each agent on Anthropic, OpenAI, Gemini or Bedrock, set prices, budgets, a daily cost cap and the time zone through bridge APIs, and name a second model that `Decide` retries once before it falls back. The epic builds on the names and stubs from Epic 33 (Story 33.1 is Lane A's contracts, Story 33.2 is Lane B's verbs and settings page). Story 17.1 moved to Story 33.1.

## Stories

- Story 17.2: Retry once on a second model before falling back
- Story 17.3: Run each agent on a supported provider
- Story 17.4: Apply model, price, budget and zone changes through the bridge
- Story 17.5: Check the vital signs and every coverage entry
- Story 17.6: Send the daily digest at the set time and on request
- Story 17.7: Give an all-clear only when every check passed

## Requirements & Constraints

- **No sampling parameters.** No request sets `temperature`, `top_p` or `top_k`. The output cap is 8,000 tokens, in the key the model family takes: `max_tokens`, or `extra_params.max_completion_tokens` for GPT-5-class models. Effort is set for Anthropic models only. The cache block is always present. Unit tests check the composed config for every listed model, with no network access.
- **Keys stay out of storage.** A key never appears in a Config Store entry, a saved AI session, a production setting, a log, an audit entry or an API answer. It reaches a provider only as an `@{env:VAR}` placeholder.
- **Admin values are checked.** Any admin-submitted value containing `@{`, or off the allow-list, is refused with a plain-English reason and changes nothing. Accepted values are `seed` values, so they survive a restart and an upgrade.
- **The time limit.** The whole decision, retry included, stays at or under the 110-second bridge timer.
- **When changes apply.** A change applies within a minute with no restart. The exception is a model or provider change: the bridge restarts the affected runner itself.
- **Prices.** A price change applies to later usage rows only. Decision and turn totals always equal the sum of their usage rows.
- **Classifying replies.** A provider that doesn't report refusals or cut-offs gets `unusable` for a reply the bridge can't classify. Such a reply is never treated as an answer.
- **Fallbacks.** A fallback never leads to an action, fix or approval request. It is flagged in Visual Trace with its reason.
- **The digest's limit.** A digest in which everything passed and nothing needs the user is at most 150 words when rendered.
- **Check thresholds.** The defaults are: disk or journal free space below 10%, licence use above 90%, and a queue backlog above 100 messages or with its oldest message waiting more than 10 minutes. An admin can change each one.
- **Tests.** They use the CI model mock with scenarios under `ci/mock/scenarios/A/`, on the shipped Anthropic provider path. The digest all-clear cases are also evaluation cases in `eval/`, with owner `eval`. These cases write no `Notification`, `Delivery` or live event.
- **Provider support.** A provider's `supported` flag is set only after the Contest Planner's hands-on pass with real keys at release. That pass is not a story gate.

## Technical Decisions

- **Second-model retry**
  - **The retry runners.** Each agent has one retry runner: `TriageAgentRetry`, `DiagnosisAgentRetry` and `ChatAgentRetry`. Each is class `AgentRunner`, with its own Config Store entry `AI.LLM.OcuTalon<Agent>Retry`, written by `Install.Step.Provider` before any setting names it.
  - **Turning a retry on.** The first runner's `RetryItem` setting names its retry runner; empty means no retry. The second model is the retry runner's `Model`.
  - **Retried once:** `timeout`, `rate_limited`, `error`, `refusal`, `cut_off`, `empty`, `invalid`, `unusable` and `no_key`.
  - **Never retried:** `daily_cap`, `budget`, `too_large`, an attempt in which a tool ran (`ToolsRun`), and a `SessionBroken` attempt.
  - **The retry timer.** T1 = `TimerFor(request)`. T2 = min(TimerSeconds, 110 − T1). The retry is sent only when T2 ≥ 12. A skipped retry says so in the decision's reasons.
  - **One decision.** The retry keeps the same `DecisionRef`. The one `Decision` row records the model that answered, and both attempts' usage rows sum into the totals.
  - **A retried turn.**
    - It carries `RetryOf`, which names the first runner.
    - It runs in a fresh AI session that the retry runner never links. That session is seeded with `Compaction.Seed` of the first runner's stored conversation, or with `SeedText` when the turn was `fresh`.
    - It takes no conversation lock.
    - After a completed, untainted `Chat`, the retry runner points the first runner's link at its session. `ConversationLink.Point` is a compare-and-set, so a late first attempt never moves the link off the retry's session.
    - Tests must show four cases: (a) a `RetryOf` for the same conversation and `ItemId` skips `Held`; (b) a request without `RetryOf` waits; (c) a `RetryOf` that arrives through the web API is ignored, and the request waits; (d) a `RetryOf` naming another conversation or `ItemId` waits.
    - Only `Decide`, `Bridge.Msg.Request`, `AgentRunner`, `Adapter.Agent`, `ConversationLink` and the tests may name `RetryOf`.
  - **The CI mock key.** With `OCUTALON_MOCK_KEY_HEADER=1`, `Install.Step.Provider` also adds `x-ocutalon-mockkey` to the retry runners' `custom_headers`. A test in which the retry answers arms the mock's countdown (`POST /_mock/countdown`).
- **Providers**
  - **The provider table.** It is `OcuTalon.Bridge.Providers`, a fixed XData table in the order `anthropic`, `openai`, `gemini`, `bedrock`. Each row holds a default model, the selectable models, a key variable and a supported flag.
  - **Key variables:** `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, and `AWS_BEARER_TOKEN_BEDROCK` with `AWS_REGION`.
  - **Defaults.** Anthropic's default model is `claude-haiku-5-5`, and `claude-sonnet-5-5` is also selectable.
  - **Where config lives.** The cap and effort keys per model family come from `Bridge.Data.ModelFamily`. Prices live in `Bridge.Data.Price`.
  - **Resolving a provider when the key is missing.** This happens before the `no_key` check, and only when a runner still uses its agent's default `MODEL` and that provider's key is missing. The runner then uses the first supported provider in table order whose key is set, with that provider's default model. The provider config lives in memory and nothing is written. `Keys.Status` answers for the provider it resolved to. A model the admin chose never resolves away.
- **The bridge settings APIs** (`OcuTalon.Bridge.Settings`)
  - **The methods:** `Providers()`, `Values()`, `Check` and `Set` for `DecisionTokenBudget`, `DailyCostCapUSD` and `InstanceZone`, `CheckModel` and `SetModel(agent, provider, model, second, *old)`, `SetPrice`, `TestRequest`, and `TestAnswer` → `{answered, seconds, reason}`.
  - **`SetModel`** merges the entry through `ConfigStore.Merge`, sets the runner's `Model` (and `RetryItem` for a second model), and restarts the runner.
  - **What `ConfigStore.Merge` accepts.** It accepts only the provider, the model, and `@{env:<that provider's own variable>}`. Any other variable, a `base_url`, a header, a `secret://` value or any other `@{` form is refused.
  - **The Test button.** It sends one minimal request through `Decide`, with owner `instance` and provenance `untrusted`, and never returns the key.
  - **The daily cost cap.** `DailyCostCapUSD` is a `Decide` host setting, where 0 means off, the local default. `Budget.State()` reports the new cap.
- **Time.** The instance zone has one run-time source: `Decide`'s host setting `InstanceZone`.
  - **Reading and writing it.** It is read only through `Bridge.Time.Zone()` and written only through `Bridge.Time.SetZone(name)`.
  - **What `SetZone` refuses.** A name must match the IANA pattern and have a file under `/usr/share/zoneinfo/`, because an unknown zone silently becomes UTC.
  - **Applying it.** `Bridge.Time.Apply()` switches `$SYSTEM.Process.TimeZone` when the zone changes. Never use `$ZTIMEZONE` or Python for this.
  - **The test.** A test compares `Bridge.Time` and `Data.Time` across a daylight-saving change, with a changed zone.
  - **The fallback case.** If Story 33.1 fell back to the process zone, the new zone applies after a restart, and the tests check it after the restart.
- **Coverage**
  - **Recording runs.** `Checks` writes one `OcuTalon.Digest.Data.CheckRun` row per run, beside the `BackgroundCheck` update. Each row holds `CheckRef`, `SessionRef`, `RanAt`, `Result`, `Reason`, `Finding` and `HeaderId`.
  - **The one builder.** `OcuTalon.Checks.Coverage.Build(sessionRef, fromUtc, toUtc, Output rows, Output lines)` builds the coverage. Vital signs are read live through `Watch.Reader` with the `checks.thresholds.*` values. Background checks are read from `CheckRun` rows plus `Schedule.Heartbeat.Gaps`. The sources section stays empty until step 4.
  - **Not-checked reasons.**
    - `paused`: a heartbeat gap overlaps the span.
    - `missed`: there is a gap of more than 3 minutes between two runs, between the start of the span and the first run, or between the last run and the end of the window.
    - `stale`: the latest run is before the span.
    - Otherwise the latest run's own reason or result applies.
  - **Output shapes.** Rows are `{result, entry, finding, checkedAt}`. Lines are `{key, slots}`, using `digest.failed`, `digest.notChecked<Reason>` and `digest.passed`.
  - **Privileges.** Reads go only through `Watch.Reader`, and any privilege they add appears in the security overview's generated list.
  - **Seeding thresholds.** The digest install step seeds the `checks.thresholds.*` keys (`diskFreePercent`, `journalFreePercent`, `licenseUsePercent`, `queueMessages`, `queueWaitMinutes`), `digest.time` (08:00) and `digest.channels` (`web`, `phone`, `telegram`) as `seed` values. Code reads them through `Data.Setting.Get`, which has a 60-second cache.
- **The digest process.** `Digest` is `OcuTalon.Digest.Process`. It handles one message and ends, and keeps no private text.
  - **What it handles.** It takes the `Tick` that `Checks` forwards, and `SendDigest` from `CommandsIn`.
  - **When a session is due:**
    - the latest `digest.time` (in the instance zone) has passed;
    - that latest `digest.time` is later than the session's `CreatedAt`;
    - the session has no scheduled `Sent` row with that `DueAt` or later.

    So a new session's first scheduled digest is at the first `digest.time` after it was created (DW-651).
  - **After a restart.** A digest that fell due while IRIS was down is sent once, never repeated. `Digest` checks the due time under a lock.
  - **The window.** It runs from the newest `Sent.SentAt`, or covers the last 24 hours for a first digest. A digest of either kind starts the next window.
  - **The record.** `Digest` alone writes `OcuTalon.Digest.Data.Sent`: `Ref`, `SessionRef`, `Kind` (`scheduled` or `requested`), `DueAt`, `WindowStart`, `SentAt`, `ItemId`, `DecisionRef`, `CatalogKey`, `Slots` and `AllClear`.
  - **The model request.** `Digest` makes at most one, and only when `Digest.Data.Item.Since(sessionRef, windowStart)` is non-empty.
    - It is kind `turn` to `ChatAgent`, provenance `untrusted`, `SessionMode` `fresh` with no `SeedText`, owned by the session, with a fresh `ItemId`.
    - Its input is rendered by `Agent.Input` from an Item with channel `system` and subject "Saved for later", built from the stored summaries.
    - Only read-only tools run, the guard filters the reply, and code cuts it to 240 characters.
    - On any fallback, the digest uses `digest.savedNoSummary` and still goes out.
  - **Needs you.** This part lists failed checks first, then tell-now items that neither an answered approval request nor **Got it** has dealt with.
  - **Cost.** The previous day runs from midnight to midnight in the instance zone. The cost is summed from `Usage` rows owned by the session or `instance`, never `eval`.
- **The digest notification.** A digest is one `Notification` of kind `digest`.
  - **Its catalog key** is the key that `Checks.Render` returns.
  - **Its `Slots`** are `{"parts":[{key,slots}…],"lines":[…],"rows":[…]}`.
  - **The parts, in order:** greeting, vital signs, what was checked with the reserved sentence, needs you, saved for later, and cost.
  - **The keys** live in `Catalog.Watch` under the prefix `digest.`, plus `checks.allPassed` and `checks.everythingElsePassed`. `digest.cost` uses the slot type `dailyCost`, always two decimals.
  - **Rendering.** Producers never render text. The `*Out` operations render each part through `Catalog.Render`.
- **All-clear.** The flag and the reserved sentence come only from `Checks.Render`, over the rows from `Coverage.Build`.
  - **No watches.** When a session watches nothing, `Checks.Render` runs over an empty array and gives `checks.nothingWatched`, which is never an all-clear.
  - **Vital signs.** "Your IRIS system is healthy" appears only when every vital-sign row passed.
  - **The guard.** `Checks.ReplyGuard` runs once, on every model text that leaves `Decide`, and removes the reserved sentences and the banned phrases.

## UX & Interaction Patterns

- **Tone and format.** The digest is prose in Telegram and on the phone, with a time-of-day greeting. Check lines start "Passed:", "Failed:" or "Not checked:", and the cost is shown with two decimals.
- **Telegram.** The digest is one plain-text message with no Markdown, and its text matches the simulated phone's copy.
- **Reserved sentences.** "Everything I checked passed." appears only when every entry passed, together with what was checked. Otherwise the failed and not-checked entries come first, followed by "Everything else I checked passed." only if other entries passed.
- **Banned phrases.** These are removed: "all good", "everything's fine", "everything is fine", "no issues", "no problems" and "nothing to worry about".
- **The Got it button.** On Telegram tell-now messages it carries an unguessable reference and is accepted only from the paired chat; the first press wins. Whenever the handled marker is set, from any channel, the message is edited in place to "Marked as handled at {time}" and the button is removed.
- **No watches.** With no watched productions and no sources, the digest reports the vital signs and says OcuTalon isn't watching any productions yet.

## Cross-Story Dependencies

- **Before this epic starts:** Epic 33 must have merged. Story 33.1 supplies the names, stubs and setting keys. Story 33.2 supplies the `SendDigest` and **Got it** verbs, the settings save path, `dailyCost` and the handled-marker table.
- **Epic 12 (Telegram).** It must have merged, because the digest goes out through `TelegramOut` and **Got it** comes in through `TelegramIn`.
- **The merge gate.** This epic merges only once `release/1.0.0-rc1` exists.
- **Story-level needs.**
  - Story 17.5 needs Epic 14 (the security overview's privilege list).
  - Stories 17.2 to 17.7 need Epic 30, whose footprint covers the bridge, `Checks`, `Catalog.Watch` and `eval/`.
  - Stories 17.2, 17.3 and 17.5 need Epic 15, whose footprint covers the installer's `Provider` and `Digest` steps.
- **Within this epic.**
  - Story 17.4's APIs build on Story 17.3's provider table and `ConfigStore.Merge` rules.
  - Story 17.6 composes from Story 17.5's coverage.
  - Story 17.7's all-clear covers Story 17.6's digest.
  - Story 17.2's retry runners depend on Story 17.3's family-based session config.
- **Lane B work.** Story 18.2 (`Notify` routing to the digest channels, and `Data.Time`) and Story 18.4 (setting **Got it** markers, and the web and phone copies) are Lane B's. Until they merge, the tests use fixture notifications and markers.
- **The digest tool.** Its name is added to `OcuTalon.Tools.Names` and to the CI mock's scripts. The tool submits `SendDigest` with origin `tool` and an idempotency key.
- **Ledger items.** DW-696: `SendDigest` sent to the disabled `Digest` item answers `failed`, not `not_built`. DW-100 moved to Story 18.3.
