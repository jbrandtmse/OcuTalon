# Epic 33 Context: Step 2's contracts, and the settings page opens for admins (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This is step 2's contract epic. Lane A names every new step 2 item, table, setting key and cross-lane API in the architecture spine and lands them in code as compiling stubs. Lane B adds its step 2 contracts and ships the admin-only settings page frame. Each section on that page saves on its own, applies within a minute without a restart and is audited. With both contracts merged, the feature epics (17: digest, second model, providers and budgets; 18: settings sections) can be built in parallel without waiting on each other. Each story keeps its home lane's files. This epic exists only so the two contract stories merge together, which breaks the whole-epic pairing deadlock.

## Stories

- Story 33.1: Fix the step 2 contracts in the spine
- Story 33.2: Open the settings page as an admin

## Requirements & Constraints

- **Time zone first (33.1, Task 0).** Before touching the spine, measure on build 154 whether `OcuTalon.Bridge.Time` and `OcuTalon.Data.Time` can convert in a named zone, daylight-saving time included, inside production jobs that inherited the container's `TZ`, and pick up a changed zone within 60 s without a restart. If nothing works, fall back to the process zone with a restart to apply it: say so in the settings page text and in Visual Trace, and record it as a veto item. Do not stop.
- **Settings page access.** Only users with `OcuTalonAdmin` can use the page. Non-admins get no Settings link. Opening the address directly shows the permission-denied text. Every settings API call from a non-admin answers 403 in the shape `{"error": {"code", "message"}}`.
- **Saving.** A save submits one command through `Commands.Submit` with origin `web_admin`. `SettingsOps` then writes each value and audits it (type `Settings`: IRIS user, `SessionRef`, channel, old and new value; a secret's values are blanked). The change applies within 60 s without restarting IRIS or the production. A refused or failed save changes nothing.
- **Origin `tool`.** A settings command submitted with origin `tool` must be refused, and a test proves it.
- **Values the page must never accept.** Any admin-entered value containing `@{` is rejected. Model keys come only from environment variables and are never stored or shown.
- **Providers.** Supported: Anthropic (Claude Haiku 5.5 is the default, Claude Sonnet 5.5 also selectable), OpenAI, Google Gemini and Amazon Bedrock. Each provider has its own key variable. With no Anthropic key but another supported key set, OcuTalon uses that provider's default model.
- **Defaults.**
  - Digest at 08:00 in the instance zone.
  - Disk or journal free below 10%.
  - Licence use above 90%.
  - Queue backlog above 100 messages, or oldest message waiting over 10 minutes.
  - Daily cost cap off on a local install.
- **Digest texts.** Digest texts the UX doesn't give yet must be proposed as Message Catalog additions, with keys in `OcuTalon.Msg.Catalog.Watch`:
  - a session that watches no productions;
  - a digest whose saved-for-later summary is unavailable;
  - each not-checked reason;
  - the time-of-day greetings.

  No text ships before the author accepts it.
- **Tests.**
  - Read each kind of settings change back from the IRIS audit log. Poll with a timeout, because some rows arrive minutes late.
  - Submit a settings command with origin `tool` and expect a refusal.
  - Cover every new label in the fixed-strings test.
  - CI's checks must stay green: bridge boundary, `%AI` allow-list, storage, storage diff, and duplicate `DEFAULTGLOBAL`.

## Technical Decisions

- **Same-change rule.** Every new item, table, event type and cross-lane API goes into the spine's ownership tables in the same change.
  - Each new table sets `DEFAULTGLOBAL` to `^OcuTalonP.<Short>`, or `^OcuTalonBP.<Short>` in the bridge, and is registered in `src/short-names.tsv`.
  - Storage is append-only, with the compiler's `Storage` block committed.
  - Business processes (for example `Digest`) keep no private text in their properties. The digest summary and its Slots go in private table rows.
- **Stubs.**
  - New production items sit in their own lane's region of the single `ProductionDefinition` (`<!-- lane A: begin/end -->`). They answer "not implemented", carry `Parameter STUB = 1` and stay disabled until their story enables them.
  - Cross-lane APIs are signatures with stub bodies, pinned by the signature oracle `OcuTalon.Test.Contract.Ac`.
- **Second-model retry (33.1 fixes the details).**
  - One extra retry runner item per agent, of class `OcuTalon.Bridge.Operation.AgentRunner`, each with its own Config Store entry in the `AI.LLM.OcuTalon<Agent>` form.
  - A bridge setting names each agent's retry item.
  - The spine must also fix which fallback reasons are retried, and how the retry fits inside the bridge timer. The timer stays at or under 110 s, derived through `Bridge.Timeouts.Derive`.
  - A retried `turn` must never be saved over by a late first attempt, and must never be refused as busy. Today the runner holds `LOCK ^OcuTalonBP.Conv(<link>)`, `Decide` answers `Busy` after a 2 s wait, and the conversation is saved only after a completed, untainted `Chat`. A suggested approach is a throwaway AI session seeded with the recap. Amend the "Saved conversations" convention row in the same change.
- **Provider table.**
  - Each provider row holds its default model, its selectable models, its key's environment variable and a supported flag.
  - The resolution rule runs before `no_key`, with a fixed provider order.
  - Model family settings (cap key and effort key) come from `Bridge.Data.ModelFamily`. GPT-5-class models use `max_completion_tokens`, and effort is sent only to Anthropic models.
  - No request sets sampling parameters.
- **Instance zone.** It has a single run-time source: a bridge value that both `Bridge.Time` and `Data.Time` read. The bridge can't reference OcuTalon packages, which is why both classes exist. A test compares the two across a daylight-saving change.
- **Digest (Lane A).** The spine must fix:
  - the `Digest` item, `OcuTalon.Digest.Process`;
  - coverage storage per check run, enough to tell whether each entry ran successfully throughout the window, missed runs included (heartbeat outages come from `OcuTalon.Schedule.Heartbeat.Gaps(from, to)`);
  - a per-session record of the last digest;
  - the agent and request kind of its one model request;
  - its `Notification`: kind `digest`, keys in `Catalog.Watch`, check rows `{result, entry, finding, checkedAt}`.

  The all-clear comes only from `OcuTalon.Checks.Render`, never from model text. The digest evaluation cases (recorded check results run through `EvalIn` with owner `eval` to `EvalSink`) are added as a case kind in AD-22.
- **Bridge settings APIs that `SettingsOps` calls:**
  - providers and models, with key presence and the supported flag;
  - a model change for one agent;
  - a price edit (`Bridge.Data.Price`);
  - a model test;
  - the allow-list validation for the token budget per decision, the daily cost cap (`DailyCostCapUSD`), each agent's second model and the instance zone.
- **How a change applies.**
  - Product values: by the 60 s cache expiry of `Setting.Get`.
  - Bridge host settings: through `Ens.Director.UpdateProduction`.
  - Config Store and model changes: through one bridge field-merge method, then a restart of the affected runners. `UpdateProduction` alone doesn't apply them.
  - The installer seeds page-editable values once, and after that `SettingsOps` owns them. On the online demo, `DailyCostCapUSD` stays an installer value rewritten on every start.
- **Setting keys.** `digest.time`, `digest.channels` and `checks.thresholds.*` live in `OcuTalon.Data.Setting` (Lane B). Only `SettingsOps` writes them. Readers use `Setting.Get` with the PRD defaults. Code never reads a global directly.
- **Lane B contracts (33.2's spine update):**
  - `GET /api/v1/settings`, plus one admin-checked save route per section;
  - the `SendDigest` verb in `OcuTalon.Msg`, which `CommandsIn` routes to `Digest` (origins `tool` and `web_admin`; it joins AD-1's list of verbs accepted from origin `tool`);
  - the **Got it** command, and a Lane B table holding each tell-now notice's handled marker;
  - a `handled` notification that tells each `*Out` operation to update its copy;
  - a `Delivery` lookup by the notice's `Ref`;
  - `Notify` routing kind `digest` to the digest channels.
- **Demo mode** switches through the same `SettingsOps` path as `OcuTalon.Core.Admin.SetDemoMode`.
- **REST conventions.** State-changing calls need `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`. Error messages are plain English.
- **Ownership.**
  - Lane A owns Bridge, Digest, Checks and Agent.
  - Lane B owns Core (`SettingsOps`, `CommandsIn`), Msg, `Data.Setting`, Web and `web/`.
  - Catalog keys: Lane B's in `Catalog.Core`, Lane A's in `Catalog.Watch`. The page renders from the generated `web/src/app/msg/catalog.ts`.

## UX & Interaction Patterns

- **Header.** Navigation shows "Chat" and "Settings" (`header-nav-item`, `aria-current="page"`, inside a navigation landmark).
- **Page.** Titled "Settings · OcuTalon", with section navigation on the left: Models, Budgets, Channels, Daily digest, Time zone, Check thresholds, Demo mode.
- **Exact texts:**
  - saved: "Saved. Applies within a minute. Recorded in the audit log.";
  - save failed (a field error): "Couldn't save. Nothing was changed.";
  - permission denied: "Only OcuTalon admins can open settings.", with a link back to the chat;
  - a provider with no key: "No key set. Add {variable} to .env.", and it can't be chosen;
  - model test: "Answered in 1.2 s" or "Didn't answer: {plain reason}".
- **Interaction.**
  - **Save changes** follows the busy pattern: it keeps its label, adds a spinner, gets `aria-busy` and `aria-disabled` (never `disabled`), and restores after 10 s with no answer.
  - Field errors are linked by `aria-describedby`.
  - Leaving a section with unsaved changes asks first.
  - Text is plain English, with no class names or error codes. Configuration names a user must type (such as `.env` variables) are allowed.
- **Digest wording.** The digest is one message with its parts in PRD order. In Telegram it reads as prose, with list lines starting "Passed:", "Failed:" or "Not checked:". It opens with a time-of-day greeting and shows cost to two decimals. "Send my digest now" works in the chat and in Settings. **Got it** records "Marked as handled at {time}".

## Cross-Story Dependencies

- Story 33.2 uses the names Story 33.1 fixes. It tests against 33.1's stub signatures until Stories 17.3, 17.4 and 17.6 merge.
- Epics 17 and 18 depend on Epic 33. Epic 33 merges only once `release/1.0.0-rc1` exists.
- Downstream builders:
  - 17.2: second-model retry;
  - 17.3 and 17.4: providers and the bridge settings APIs;
  - 17.6: the digest, `SendDigest` handling, Telegram's handled copy;
  - 17.7: digest evaluation cases;
  - 18.2: the Daily digest and Time zone sections.
- The personality epics (39 to 41) also touch `SettingsOps`, `CommandsIn`, `Msg.Enum` and `Web.Api`. Add your own entries; don't rewrite theirs.
