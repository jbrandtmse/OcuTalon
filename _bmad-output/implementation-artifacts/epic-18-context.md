# Epic 18 Context: An admin changes settings in the web app (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An admin opens the Settings page and changes the instance's time zone, the daily digest's time and channels, each agent's provider, model, prices and second model, and the budgets. Each change applies within a minute without a restart and is recorded in the audit log, and non-admins can't open the page. Users also get the digest on every channel: a digest card in the web chat, and plain text on the Simulated phone and in Telegram. A **Got it** control on tell-now notices marks a notice handled, so "needs you" holds only what still needs the user. Story 18.1 moved to Story 33.2, which built the page shell, the save path and the step 2 contracts. This epic fills in the remaining sections and the digest and Got it surfaces.

## Stories

- Story 18.2: Set the time zone and the daily digest at run time
- Story 18.3: Choose models and set budgets in Settings
- Story 18.4: Read the digest on every channel and mark notices as handled

## Requirements & Constraints

- **Save rules.** Every save applies within 60 seconds with no IRIS or production restart, writes a `Settings` audit entry, and shows the fixed confirmation and error texts.
  - A refused value changes nothing and writes no audit entry.
  - Tests read each kind of change back from the IRIS audit log.
- **Time zone.** A changed zone affects:
  - message times;
  - reminder phrasing ("Thursday at 10");
  - the digest time;
  - every model request's local-time preamble.

  It does not move pending reminders' stored UTC due times, and page times stay in the browser's zone.
- **Daily digest.** `digest.time` (default 08:00) and `digest.channels` (`web`, `phone`, `telegram`) take effect from the next digest.
  - **Send my digest now** in Settings submits `SendDigest` with origin `web_admin` and follows the busy pattern.
- **Channels section.** It shows Telegram's state: not set up (with the README link), on, or paused until a given time. The bot token is never shown or entered there.
- **Keys.**
  - A provider without a key reads "No key set. Add {variable} to .env." and can't be chosen.
  - No key value ever reaches the page, an audit entry, a log or an API answer.
  - Model keys come only from environment variables.
- **Budgets.**
  - The daily cost cap is off by default on a local install.
  - For admins, the "Budgets" action on the local cost-cap banner opens the Budgets section.
  - The no-model-key banner uses the step 2 text and the "How to set a key" link.
- **Public text.** Any new or changed user-facing string, catalog text or README claim is public text. It needs the author's acceptance (the Contest Planner's under the delegation) before it ships, and the fixed-strings test covers every new label. Two cases are already known:
  - **DW-100 (Story 18.3):** propose new wording for `fallbackReason.timeout` (no fixed seconds) and `fallbackReason.rateLimited` (no "retries ran out" when a tool ran and nothing was re-sent).
  - **The README's provider section:** it names only providers marked supported.
- **Ledger items this epic owns:**
  - **Story 18.2:**
    - DW-34: `Data.Time` must follow `Bridge.Time.Zone()`, and fall back to the OS zone on a TZ-unset non-UTC host.
    - DW-643: `FromLocal` must take fold 0, the first instant of the repeated fall-back hour, whatever the job converted before.
    - DW-815: the residual is folding the coverage lines past a limit into a count. That needs a new catalog line, which is public text.
    - DW-820: `Notify` routes kind `digest` by `digest.channels`. Then delete `Digest.Process.Own` and Digest's direct sends.
  - **Story 18.3:** DW-100.
  - **Story 18.4:** DW-695's residual. Add a `Data.Handled` `Purge(daysToKeep)`. The end-of-session delete is already built.
- **REL-2 and web tests.** The demo-path test stays green. A Playwright test covers the Settings page (as the README account), a fixture digest card and **Got it**.
- **Telegram in CI.** Tests use the CI Telegram mock. A real bot is used only in the Contest Planner's hands-on pass.

## Technical Decisions

- **Lanes.** This is a Lane B epic. It may change Lane B files only: `Core.SettingsOps`, `Data.Time`, `Data.Setting`, `Data.Handled`, `Core.Rule.Notify`, `WebChatOut`, `SimPhoneOut`, `Msg.Catalog.Core`, `Catalog.Render` and `web/`. Lane A owns:
  - `OcuTalon.Bridge.*`;
  - `OcuTalon.Digest.*`, `Checks.*` and `Msg.Catalog.Watch`, which holds the `digest.*` keys;
  - `TelegramOut` and `TelegramIn`.

  Each lane edits only its own region of the `ProductionDefinition` block. Deleting `Digest.Process.Own` (DW-820) touches Lane A's file. Its routing was ruled to Story 18.2.
- **The one writer.** `SettingsOps` is the only run-time settings writer.
  - A save is one `Msg.Command.SaveSettings` (`Slug`, `Changes`, `ActingUser`) with origin `web_admin`.
  - Sections are declared in `SettingsOps`' `XData Sections`.
  - The order is fixed: validate everything, drop unchanged values, then write. Product keys are written in one transaction, each audit entry before its row. Bridge values are written with every `Check` first, then `Set` and its audit entry, putting earlier values back if a later step fails.
  - `GET /api/v1/settings` returns `SettingsOps.Values()`, read from the rows and never through the cache.
- **Bridge settings APIs** (`OcuTalon.Bridge.Settings`, the only way to change bridge values):
  - `Providers()`, with `keySet` and `supported` per provider;
  - `Values()`;
  - `Check` and `Set` for `DecisionTokenBudget`, `DailyCostCapUSD` and `InstanceZone`;
  - `CheckModel` and `SetModel(agent, provider, model, second, *old)`. These merge the Config Store entry with only the provider and `@{env:<var>}`, set the runner's `Model` or the first runner's `RetryItem`, and restart the runner;
  - `SetPrice(model, prices, *old)`;
  - `TestRequest` and `TestAnswer`, which return `{answered, seconds, reason}`.

  Every method refuses `@{` and values off the allow-list with a plain reason. Accepted values are seed values that survive a restart or an upgrade, and the bridge timer stays at or under 110 s.
- **When values apply.** Live bridge settings apply when their row is written, because `Decide` reads them on each use. Product values apply when the 60-second `Setting.Get` cache expires. Model and provider changes apply when the affected runner restarts.
- **Instance zone.** The only source is `Decide`'s host setting `InstanceZone`, read through `Bridge.Time.Zone()` and written through `Bridge.Time.SetZone`, which validates the IANA name and checks for a zoneinfo file.
  - `Data.Time.ToLocal`, `FromLocal` and `ForMessage` call `Bridge.Time.Apply()` first. It applies `$SYSTEM.Process.TimeZone` when the name changes and restores the inherited `TZ` when the name is empty.
  - `$ZTIMEZONE` and Python are not used.
  - A test compares `Data.Time` with `Bridge.Time` across a daylight-saving change, with the zone changed.
- **Digest notification.** It is kind `digest`. `Slots` are `{parts, lines, rows}`, and each `{key, slots}` is rendered through `Catalog.Render` only. `rows` use the shape `{result, entry, finding, checkedAt}`, and the digest cost uses the slot type `dailyCost` (two decimals).
  - `Notify` sends kind `digest` only to the session's `digest.channels`, each only where the session has that channel.
- **Got it.**
  - `Msg.Command.GotIt` (`Ref`, `Channel`) comes from origins `web_user`, `web_admin` and `telegram`, and goes to `SessionOps`.
  - The `Ref` is the notice's `Decision` Ref.
  - The marker is a `Data.Handled` row (unique on `Ref`, so the first press wins), read through `Handled.Marked(ref)`.
  - A `handled` Notification goes to each `*Out` operation, which finds its copy with `Delivery.FindByRef(ref, channel, ownerRef)`.
- **Retention.** Each area declares `Purge(daysToKeep)`, which Lane A's `Install.Task.Purge` calls. No purge reads `Data.Setting`.

## UX & Interaction Patterns

- **Settings navigation.** Sections are listed on the left: Models, Budgets, Channels, Daily digest, Time zone, Check thresholds, Demo mode.
  - Each section saves on its own with **Save changes** and confirms with "Saved. Applies within a minute. Recorded in the audit log."
  - A failed save shows "Couldn't save. Nothing was changed."
  - Leaving a section with unsaved changes asks first.
  - Buttons follow the busy pattern.
- **Model Test.** **Test** answers "Answered in 1.2 s" (fixture) or "Didn't answer: {plain reason}".
- **Digest card** (D `digest-card`): a 4px brand-teal accent bar, the digest text, then a "What I checked ({n})" disclosure of check rows. The disclosure is expanded when any entry failed or wasn't checked.
- **Phone and Telegram digest.** One plain-text message:
  - the parts in the PRD's order and a time-of-day greeting;
  - check lines starting "Passed:", "Failed:" or "Not checked:";
  - the previous day's cost with two decimals;
  - no Markdown, and the reserved sentences exactly as the catalog gives them.
- **Got it.** It appears on the web notice card and on the phone notification. After a press, both copies show "Marked as handled at {time}" within one live update.
- **Digest chip.** The Digest outcome chip's description reads "Saved for the daily digest".

## Cross-Story Dependencies

- **Already built (Epic 33).** Story 33.2 built the page shell, the header navigation, the admin gate with the 403 error shape, the `SaveSettings` path, and the Check thresholds and Demo mode sections in the web app. Server-side `XData Sections` also declares budgets, daily digest and time zone. No Models or Channels section exists yet.
- **Already built (Epic 17, Stories 17.2 to 17.9, on feature).** The bridge settings APIs, the provider table, the second-model retry, `Bridge.Time` with `InstanceZone`, `Digest.Process`, and `Channel.DigestText`, which is the digest text helper.
  - **Story 18.3** must call these as built (model choice with budgets, Test, prices, second model) rather than re-implement them.
- **Partly delivered for Story 18.4 by Story 17.10** (branch `OCT-epic17`, merging to feature this morning):
  - `WebChatOut` gains the kind `digest`. It renders the Slots through the shared helper for channel "web" and records a Delivery row of kind `digest`. It publishes a notification event, and a reload shows the card again.
  - The web chat draws the digest as a notice card with the digest's own class and icon, as plain text. The full UX card with the "What I checked ({n})" disclosure was left out.
  - `SimPhoneOut` shows no digest.
  - The Playwright case is in `web/e2e/chat/notice.spec.ts`.
  - Story 17.10 also changes `Digest/Process.cls` (the online-demo morning run skips demo sessions).
- **Partly delivered for Story 18.4 by Story 12.12 (merged):**
  - `SessionOps` carries out `GotIt`: it validates the Ref and checks that the Decision is the session's own tell-now Decision, writes a `Data.Handled` row, sends a `handled` Notification, and treats a second press as a no-op.
  - Telegram's edit in place happens through `EditHandled` with `handled.marked`.
  - `SessionOps.End` deletes the session's `Handled` rows.
  - `Digest.NeedsYou` counts only unhandled tell-now and act Decisions inside the window.
  - **Left for Story 18.4:** the web chat's and the Simulated phone's **Got it** controls and their handled copies, and the `Data.Handled` purge.
- **Story 18.4's acceptance criteria are judged against this delivered code**, so its plan covers only the gaps.
- **Overlap between Stories 18.2 and 18.4.** Story 18.2's `Notify` routing for kind `digest` (DW-820) feeds Story 18.4's channel rendering. Story 18.4's Playwright test covers the Settings page that Stories 18.2 and 18.3 fill.
