# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day, and whenever the user asks, OcuTalon sends one short digest: the vital signs, a coverage list where every entry is passed, failed or not checked (with a reason), what needs the user, what was saved for later, and the previous day's model cost. Code alone decides whether an all-clear is given, so a quiet digest really means everything watched was checked and passed. The epic also lets an admin run each agent on a supported provider and model, set prices, budgets and the instance time zone through the bridge, and name a second model for one retry before the fallback. Stories 17.2 to 17.5 and 17.8 are done; 17.6 (sending the digest) and 17.7 (the all-clear and the evaluation cases) remain.

## Stories

- Story 17.2: Retry once on a second model before falling back (done)
- Story 17.3: Run each agent on a supported provider (done)
- Story 17.4: Apply model, price, budget and zone changes through the bridge (done)
- Story 17.5: Check the vital signs and every coverage entry (done)
- Story 17.6: Send the daily digest at the set time and on request
- Story 17.7: Give an all-clear only when every check passed
- Story 17.8: Only Decide moves a conversation's link (done)

## Requirements & Constraints

- **When it is sent:** at `digest.time` (default 08:00 in the instance zone), to the session's `digest.channels`, and on request ("send my digest now" in chat, or from Settings). A digest that fell due while IRIS was down goes once after the restart and is never repeated. A new session's first scheduled digest is at the first `digest.time` after its `CreatedAt`. Either kind of digest starts the next window.
- **Window:** from the session's previous digest, or the last 24 hours for its first.
- **Five parts, in this order:** vital signs; the coverage list with each result; needs you (failed checks first, then tell-now items not yet dealt with by an answered approval request or by **Got it**); saved for later (digest-outcome items since the last digest, with a count and a summary); the previous day's model cost, midnight to midnight in the instance zone, summed from `Usage` rows owned by the session or `instance`, never `eval`.
- When everything passed and nothing needs the user, the digest is at most 150 words.
- **All-clear rule:** "Everything I checked passed." only when every entry passed, listing what was checked. Otherwise the failed and not-checked entries are named first, followed by "Everything else I checked passed." only if other entries passed. "Your IRIS system is healthy" only when every vital sign passed; otherwise the failing sign is named. With no watched productions and no sources, the digest reports the vital signs, says OcuTalon isn't watching any productions yet, and never gives a system-wide all-clear.
- Model text never carries an all-clear: the guard strips the reserved sentences and the closed list of banned phrases, even when the mocked model claims everything is fine while a check fails.
- If the saved-for-later summary request is unusable, the digest still goes, with the count and no summary, and the fallback is recorded in Visual Trace.
- Step 2 test cases (an item in error, a check that didn't run because the heartbeat stopped, everything passing) are automated tests and also evaluation cases scored on the all-clear flag and the named entries.
- No key value ever appears in a Config Store entry, saved session, setting, log, audit entry or API answer.

## Technical Decisions

- **`Digest` item** (`OcuTalon.Digest.Process`, Lane A): a business process that handles one message and ends, keeping no private text in its properties. It takes the `Tick` that `Checks` forwards after each tick's checks, and `OcuTalon.Msg.Command.SendDigest` from `CommandsIn`, answering a `CommandResult`.
- **Due rule on a tick:** a session that has not ended is due when the latest `digest.time` has passed, that time is later than the session's `CreatedAt`, and the session has no scheduled `Sent` row with that `DueAt` or later. Check the due time under a lock before sending. `digest.time` and the thresholds are read through `OcuTalon.Data.Setting.Get`, which has a 60-second cache. Time conversion goes only through `OcuTalon.Data.Time`; times are stored as UTC.
- **Coverage rows** come only from `OcuTalon.Checks.Coverage.Build(sessionRef, fromUtc, toUtc, *rows, *lines[, *vitals])`, built in 17.5. `rows` have the shape `{result, entry, finding, checkedAt}`; `lines` hold one `{key, slots}` per row (`digest.failed`, `digest.notChecked<Reason>`, `digest.passed`); `vitals` holds the five vital-sign rows plus the `digest.healthy` figures. The all-clear catalog key comes only from `OcuTalon.Checks.Render`: it runs over every row when the session watches anything, and over an empty array (`checks.nothingWatched`, never an all-clear) when it watches nothing.
- **Record:** `Digest` alone writes one `OcuTalon.Digest.Data.Sent` row per digest (`Ref`, `SessionRef`, `Kind` scheduled/requested, `DueAt`, `WindowStart`, `SentAt`, `ItemId`, `DecisionRef`, `CatalogKey`, `Slots`, `AllClear`). The newest row is the session's last digest.
- **The digest's model request:** at most one per digest, only when `Digest.Data.Item.Since(sessionRef, windowStart)` is not empty. It is a `turn` to `ChatAgent` through `Decide`: provenance `untrusted`, `SessionMode` `fresh` with no seed (never linked), owner the session, a fresh `ItemId`. Its input is rendered by `OcuTalon.Agent.Input` from an Item (channel `system`, subject "Saved for later") whose text is the saved items' stored summaries, quoted as untrusted data. Only read-only tools run, the guard (`OcuTalon.Checks.ReplyGuard`, the bridge's reply filter) runs, and code cuts the reply to 240 characters. On any fallback, use `digest.savedNoSummary`. The digest's code-written parts never follow the persona.
- **Notification:** one `OcuTalon.Msg.Notification` of kind `digest`. Its `CatalogKey` is the all-clear key, and its `Slots` are `{"parts": [{key, slots}...], "lines": [...], "rows": [...]}`, with `parts` in the order greeting, vital signs, what was checked plus the reserved sentence, needs you, saved for later, cost. Producers never render text; each `*Out` operation renders every `{key, slots}` through `OcuTalon.Msg.Catalog.Render` and nothing else. The keys live in `Catalog.Watch` under `digest.`, plus `checks.allPassed` and `checks.everythingElsePassed`. `digest.cost` uses the slot type `dailyCost` (two decimals). `Notify` routes kind `digest` to the session's `digest.channels`.
- **SendDigest:** the chat's digest tool (a safe action) submits it through `Commands.Submit` with origin `tool` and an idempotency key; Settings submits it with origin `web_admin`. It takes no recipient. Inside a bridge context, `CommandsIn` refuses a `SessionRef` that isn't the context's owner. Add the tool's name to `OcuTalon.Tools.Names` and to the CI mock's scripts.
- **Got it:** a notice's `Ref` is its `Decision`'s `Ref` (`Notification.DecisionRef`). The handled marker is read-only to Lane A, through `OcuTalon.Data.Handled.Marked(ref)` (Lane B table). A `handled` notification reaches each `*Out` operation; `TelegramOut` finds its copy with `OcuTalon.Data.Delivery.FindByRef(ref, channel, ownerRef)` and edits it to "Marked as handled at {time}", removing the button. `TelegramIn` submits **Got it** only for presses from the paired chat, and its button carries an unguessable reference.
- **Telegram rendering:** one plain-text message with no Markdown: a time-of-day greeting, check lines starting "Passed:", "Failed:" or "Not checked:", and the cost with two decimals.
- **Evaluation:** a `digest` case sends `OcuTalon.Eval.Msg.DigestCase` (owner `eval`, `SourceItemId`, the recorded rows) from `EvalIn` to `Digest`. `Digest` composes with those rows in place of `Coverage.Build` (its model request owner `eval`) and sends `EvalSink` an `OcuTalon.Eval.Msg.DigestResult` (`SourceItemId`, `CatalogKey`, `AllClear`, the named entries, `DecisionRef`). It writes no `Notification`, `Delivery` or live event.
- **Dependency direction:** `OcuTalon.Digest` may call `Checks.Coverage.Build` and `Checks.Render`; `Checks` writes `Digest.Data.CheckRun` and calls `Schedule.Heartbeat.Gaps`.
- **Bridge settings (done):** `OcuTalon.Bridge.Settings` holds the provider table, model and second-model changes through `ConfigStore.Merge` (only the provider, the model and `@{env:<var>}` pass), prices, `DecisionTokenBudget`, `DailyCostCapUSD` (0 means off) and `InstanceZone` (through `Bridge.Time.SetZone`). Requests never set `temperature`, `top_p` or `top_k`; the output cap is 8,000 tokens in the key the model family takes.
- Tests use the CI model mock (`ci/mock/`); the IRIS units for Digest, Checks and Eval run in CI's `lane-a` shard.

## UX & Interaction Patterns

- The digest is one message in every channel: prose in Telegram and on the phone, and a `digest-card` on the web whose "What I checked ({n})" disclosure is expanded when anything failed or wasn't checked.
- In UJ-2's morning digest (Flow 2), the vital-sign figures, the production summary ("all running, no errors, no backlog"), "Your IRIS system is healthy" and "Everything I checked passed." all come from code.
- The web and phone copies, and the **Got it** button on the web card and phone, belong to Lane B (Story 18.4); the Telegram copy and its inline **Got it** belong to Story 17.6.

## Cross-Story Dependencies

- Story 17.6 needs Epic 33 (done), which supplies the `SendDigest` and **Got it** verbs, the `Handled` table and reader, the `handled` kind and the `dailyCost` slot. Lane B's Story 18.2 (`Notify`'s routing of kind `digest`) and Story 18.4 (the handled-marker writer, and the web and phone copies) are still in backlog. Until they merge, tests send a fixture notification straight to `TelegramOut`, use fixture markers, and check the submitted command.
- Story 17.7 builds on 17.6's composition. It uses `Checks.Render` and `ReplyGuard`, and its `eval/` cases follow the evaluation pipeline (`EvalIn`, then `Digest`, then `EvalSink`).
- Stories 17.6 and 17.7 overlap Epic 30's footprint (`Checks`, `OcuTalon.Msg.Catalog.Watch`, `eval/`), and Epic 30 is still in progress.
- Downstream: Epic 22 (Story 22.5) fills the coverage list's sources section and uses the digest, and Epic 23 (Story 23.7) uses the `checks.thresholds.*` keys.
- Epic 17 merges only once `release/1.0.0-rc1` exists, and it ships in the first daily release after 1.0.0.
