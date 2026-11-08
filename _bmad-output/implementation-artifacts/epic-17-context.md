# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day (and whenever asked) OcuTalon sends one short digest: vital signs, a coverage list where every entry is passed, failed or not checked with a reason, what needs the user, what was saved for later, and the previous day's model cost. The all-clear is computed by code from check results, never written by the model. Alongside it, an admin picks the provider and model for each agent (triage, diagnosis, chat), edits prices, sets budgets, a daily cost cap and a time zone, and sets a second model that gets one retry before the fallback route. This is what makes OcuTalon's "everything passed" trustworthy and its spending controllable. Fix-forward stories added after the online-demo walks keep the digest honest and visible there: no own chat turns in "needs you", no false system-log alarm after a restart.

## Stories

- Story 17.2: Retry once on a second model before falling back
- Story 17.3: Run each agent on a supported provider
- Story 17.4: Apply model, price, budget and zone changes through the bridge
- Story 17.5: Check the vital signs and every coverage entry
- Story 17.6: Send the daily digest at the set time and on request
- Story 17.7: Give an all-clear only when every check passed
- Story 17.8: Only Decide moves a conversation's link
- Story 17.9: Epic 17 burn-down (model Test as connection test, shared live-read helper, guide tables)
- Story 17.10: The digest shows in the web chat, and the online demo's digest is visible
- Story 17.11: Epic 17 burn-down: the online-demo digest names no host path, address, user or key
- Story 17.12: "Needs you" never counts the person's own chat messages
- Story 17.13: The system-log vital sign is not a false alarm after a restart

(Story 17.1 moved to Story 33.1.)

## Requirements & Constraints

- **Unusable replies** (refusal, empty, cut off, error, timeout, rate limit after back-off, over budget) never become answers or actions. Item → tell now flagged "fallback" with its reason; incident → grouped by fixed rules, no cause or fix; chat turn → a plain "couldn't answer, and why". Every fallback is a decision message visible in Visual Trace. With a second model set, retry once on it first.
- **Model requests**: never `temperature`, `top_p` or `top_k`. Output cap 8,000 tokens in the family's own key. Effort only for Anthropic. Cache block always present.
- **Providers**: Anthropic (default Claude Haiku 5.5, plus Sonnet 5.5), OpenAI, Gemini, Bedrock. Each key lives only in its own environment variable and never appears in an entry, saved session, setting, log, audit entry or API answer. With no Anthropic key, use the first supported provider whose key is set. With no key at all, start anyway and fall back with `no_key`. A provider counts as supported only after its demo-path run passes.
- **Changes apply within a minute with no restart**, are audited, and survive restarts and upgrades (seed values owned by `SettingsOps`). Refuse any value containing `@{` or outside the allow-list with a plain reason, and change nothing.
- **Budgets**: token budget per decision; daily cost cap, off by default on a local install, with the day ending at midnight in the instance zone. Going over takes the fallback route and names the budget.
- **Digest**: default 08:00 in the instance zone. A digest missed while IRIS was down is sent once, never repeated. Its five parts come in a fixed order: vital signs; coverage; needs you; saved for later (count plus summary); previous day's cost (Usage owned by the session or `instance`, never `eval`). At most 150 words when all passed and nothing needs the user.
- **Coverage**: vital signs (instance responding; database free space; journal space; licence use; errors in the instance's own system log since the last digest), each watched production (running state, items in error or disabled, failed messages, backlog), each background check, and an empty sources section until step 4. An entry is checked only if its check ran successfully throughout the window. Thresholds default to free space below 10%, licence above 90%, and a backlog above 100 messages or older than 10 minutes. Admins can change them.
- **Needs you**: failed checks, open approval requests, and tell-now and act items that arrived on a channel, are not marked handled (Got it), and fall inside the window. The person's own chat or user turns never count, on any channel.
- **System-log vital sign**: start-up noise after a container restart must pass, and a real later error must still fail with its count and time. Story 17.13 first measures fresh builds 154 and 109 in a throwaway stack (never the demo host), then reports the narrowest fix to the Contest Planner, who rules on it before anything is implemented.
- **Online demo**: no scheduled digest. A visitor gets one only by asking, and it shows in the visitor's own web chat. The digest text never names a host path, IP address, user name or key. REL-2 (the demo path) stays green.
- **Process rules**: every new test pin is shown red with a mutation. Any new or changed user-facing string, and any `docs/bridge-guide.md` wording change, goes to the Contest Planner as public text before it is committed.

## Technical Decisions

- **`Decide` alone classifies replies**, into one `FallbackReason`. Never sent: `no_key`, `daily_cap`, `budget`, `too_large`. Then `timeout`, then `rate_limited`/`error`, then `refusal`/`cut_off`/`empty`/`invalid`. Anything it can't tell apart is `unusable`. Non-Anthropic providers report no refusal or cut-off, so they fall to `unusable`.
- **Second-model retry**:
  - Each agent has a retry runner item (`TriageAgentRetry`, `DiagnosisAgentRetry`, `ChatAgentRetry`) with its own Config Store entry `AI.LLM.OcuTalon<Agent>Retry`, which `Install.Step.Provider` writes. The first runner's `RetryItem` setting names its retry item; empty means no second model.
  - Never retried: `daily_cap`, `budget`, `too_large`, `ToolsRun`, `SessionBroken`, a model Test (`ItemId` starting `test.`), and a timed-out `turn`. A timed-out decide or diagnose is retried only when its agent's tools are all read-only.
  - Timing: the retry waits `T2 = min(TimerSeconds, 110 - T1)` and is sent only if `T2 >= 12`. Retry entries derive from `Timeouts.RetryTimer`. The whole decision stays at or under 110 s.
  - Recording: there is one `Decision` row, which records the answering model, and both attempts' Usage rows sum into its totals.
- **One arbiter for the conversation link**: only `Decide` moves the link, when it accepts an on-time, untainted reply. Runners (`SaveRetried`, `SaveLinked`) only record their session. A late or superseded reply counts its cost and moves nothing. A retry's seed is the stored conversation up to and including the current user message, with nothing from the first attempt.
- **Session config is built in code, never stored**, from `Bridge.Data.ModelFamily` (cap key, effort key). GPT-5-class models take `extra_params.max_completion_tokens`. `ProviderConfig` holds the provider, the `@{env:...}` placeholder, `base_url` and `http_config`, never the model. The model is the runner's `Model` setting.
- **Provider table**: `OcuTalon.Bridge.Providers`, in the fixed order anthropic, openai, gemini, bedrock. Prices live in `Bridge.Data.Price`. `ConfigStore.Merge` lets through only the provider, the model and `@{env:<that provider's variable>}`. It refuses other env vars, `base_url`, headers, `secret://` and any other `@{` form.
- **Bridge settings API** (`OcuTalon.Bridge.Settings`): `Providers()`, `Values()`, `Check`/`Set` for `DecisionTokenBudget`, `DailyCostCapUSD` and `InstanceZone`, and `CheckModel`/`SetModel` for an agent's model and second model. The model **Test** is a connection test for every runner: any non-empty reply within the timer passes, with no reply-class validation. Its usage is recorded under owner `instance`, and it never returns the key.
- **Status reads**: budget state only through `Bridge.Budget.State()`, key presence only through `Bridge.Keys.Status(agent)`.
- **Time**: `Decide`'s `InstanceZone` host setting is the single run-time zone source. Read it through `Bridge.Time.Zone()` and write it through `Bridge.Time.SetZone()`, which refuses names that are not IANA zones. `Data.Time` is the only converter outside the bridge, `Bridge.Time` the only one inside it, and a test compares them across a daylight-saving change.
- **Product settings** (`digest.time`, `checks.thresholds.*`) are seeded in `OcuTalon.Data.Setting` and read through `Data.Setting.Get`, which caches for 60 s.
- **Checks and coverage**:
  - Results come only from `OcuTalon.Checks`. Each background-check run writes one `Digest.Data.CheckRun` row.
  - `Checks.Coverage.Build(sessionRef, fromUtc, toUtc, rows, lines)` is the one row builder. It reads vitals and productions only through `OcuTalon.Watch.Reader`, under the service user's privileges.
  - Not-checked reasons: `paused` (a heartbeat gap), `missed` (runs more than 3 minutes apart), `stale`, or the run's own `error`/`timeout`/`unreachable`. `Coverage.Live` and `Process.Run` share one live-read helper.
- **All-clear**: the flag and the reserved sentence come only from `Checks.Render`, which returns `checks.allPassed`, `checks.notEverything`, `checks.notEverythingRestPassed` or `checks.nothingWatched`. "Your IRIS system is healthy" appears only when every vital sign passed. `Checks.ReplyGuard`, the reply filter, strips all-clear and banned wording from model text.
- **Digest process**:
  - `OcuTalon.Digest.Process` handles a forwarded `Tick` or a `SendDigest` command.
  - A session is due when the latest `digest.time` has passed, that time is after the session's `CreatedAt`, and no scheduled `Sent` row exists for it. The due check runs under a lock.
  - `SendDigest` (origin `tool` or `web_admin`, idempotent) answers `ok` at once and composes asynchronously. Either kind of digest starts the next window.
  - The window starts at the newest `Sent.SentAt`, or 24 h back for the first digest. `Digest` alone writes `Sent`.
  - The saved-for-later summary is one model request through `Decide`: quoted stored summaries, read-only tools, cut to length in code, then passed through the reply filter. If that request is unusable, the digest still goes out with the count only.
  - Test ticks must never make other sessions due or leave future-dated `Sent` rows.
- **Notification contract**:
  - A digest is one `Notification` of kind `digest`. Its Slots are `{parts, lines, rows}`, each entry a `{key, slots}` rendered only through `Msg.Catalog.Render`.
  - Digest keys are `digest.*` in `Catalog.Watch`. The cost slot type is `dailyCost` (two decimals).
  - `TelegramOut` and `WebChatOut` share one channel-aware digest helper (`Channel.DigestText`). Telegram output stays byte-identical.
  - `NeedsYou` is the one list that every channel renders.
- **Item provenance**: text the user writes has provenance `user`, and everything else is `untrusted`. Use this, not wording, to keep the person's own turns out of "needs you".

## UX & Interaction Patterns

- **Reserved sentences**: "Everything I checked passed." only when all checks passed, listing what was checked. Otherwise the failed and not-checked entries come first, then "Everything else I checked passed." if others passed. With nothing watched, the digest says OcuTalon isn't watching any productions yet. The banned phrases ("all good", "everything is fine", "no issues", ...) never appear.
- **Telegram digest**: one plain-text message with a time-of-day greeting. Lines start "Passed:", "Failed:" or "Not checked:". Cost has two decimals. No Markdown.
- **Got it**: Got it on tell-now notices marks the notice handled, and the first press wins. Only the paired chat's press counts. The message is edited in place to "Marked as handled at {time}" with its button removed.
- **Web chat digest**: a plain-text notice card with the digest's own class and icon. It keeps its line breaks and survives a reload. The Simulated phone shows no digest.

## Cross-Story Dependencies

- Builds on Epic 33: Story 33.1's names and stubs, and Story 33.2's `SendDigest` and Got it verbs, the settings save path and the `dailyCost` slot. Builds on Epic 12 (`TelegramOut`/`TelegramIn`) and Epic 14 (the security overview's generated privilege list, for 17.5). It also shares footprint with Epics 15 and 30 (installer steps, bridge, `Checks`, `Catalog.Watch`, `eval/`).
- Lane B's Stories 18.2 (digest routing in `Notify`) and 18.4 (handled markers, web and phone copies) come later. Until they merge, tests use fixture markers or fixture notifications.
- Story 12.12 fixed the `NeedsYou` window and Got it handling, which Story 17.12 must keep unchanged while excluding the person's own turns.
- Story 17.2 → 17.8: the arbiter must keep 17.2's late-retry tests passing.
- Story 17.5 → 17.13: the system-log vital sign's severity count lives in `Watch.Reader` and the "system log" entry of `Checks.Coverage`.
- Stories 17.6 and 17.10 → 17.11 and 17.12: changes go through the shared digest text helper and `NeedsYou`, so every channel stays consistent.
- Story 17.12 comes before 17.13. Both target release 1.0.5.
- Epic 17 merges only once `release/1.0.0-rc1` exists, and ships in the next daily release after it merges.
