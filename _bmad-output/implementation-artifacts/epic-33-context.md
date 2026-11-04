# Epic 33 Context: Step 2's contracts, and the settings page opens for admins (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic fixes step 2's names in the spine and in code as stubs, and gives admins a settings page where each section saves on its own, applies within a minute without a restart and is audited. With both contracts merged, Epics 17 (digest, second model, providers, budgets) and 18 (settings sections) build in parallel. It exists only so the two contract stories merge together, which breaks the whole-epic pairing deadlock; each story keeps its home lane's files. Story 33.1 (Lane A) is done: the spine, the stubs and the accepted digest texts are in the tree. What remains is Story 33.2 in Lane B's files.

## Stories

- Story 33.1: Fix the step 2 contracts in the spine
- Story 33.2: Open the settings page as an admin

## Requirements & Constraints

- **Access.** Only `OcuTalonAdmin` can use the page. Non-admins get no Settings link, the address shows the permission-denied text, and every settings API call answers 403 as `{"error": {"code", "message"}}`.
- **Saving.** A save is one command through `Commands.Submit` with origin `web_admin`. `SettingsOps` writes each value and audits it through `OcuTalon.Bridge.Audit` (type `Settings`: IRIS user, `SessionRef`, channel, old and new value, never a secret). It applies within 60 s with no IRIS or production restart. A refused or failed save changes nothing.
- **Origins.** A settings command from origin `tool` is refused. `SendDigest` is the exception: it is accepted from `tool` and `web_admin`, and joins the list of verbs accepted from `tool`. Role checks stay in the admin-checked endpoints; `CommandsIn` checks origins only.
- **Refused values.** Any admin-entered value containing `@{` is rejected. Keys come only from the environment and never appear.
- **Tests.**
  - Read each kind of settings change back from the IRIS audit log, polling with a timeout because rows can arrive late.
  - Submit a settings command with origin `tool` and expect a refusal.
  - Cover every new label in the fixed-strings test.

## Technical Decisions

- **The spine update (33.2's contracts).** Each goes into the ownership tables in the same change:
  - `GET /api/v1/settings` and one admin-checked save route per section;
  - `OcuTalon.Msg.Command.SendDigest` and `CommandsIn`'s routing of it to `Digest`, which answers a `CommandResult`;
  - `Notify`'s routing of kind `digest` to the session's `digest.channels`;
  - the **Got it** command, a Lane B table for each tell-now notice's handled marker, a `handled` notification to each `*Out` operation, and a `Delivery` lookup by the notice's `Ref`;
  - the slot type `dailyCost` in `Catalog.Render` (two decimals). The key `digest.cost` ("Yesterday's cost: {cost}.") was held back from `Catalog.Watch` for it and lands with this story.
- **Bridge values.** `SettingsOps` changes them only through `OcuTalon.Bridge.Settings`:
  - `Providers()` and `Values()` to read;
  - `Check`/`Set(name, value, *old)` for `DecisionTokenBudget`, `DailyCostCapUSD` and `InstanceZone`;
  - `CheckModel`/`SetModel`, `SetPrice`, `TestRequest` and `TestAnswer`.

  Each method refuses `@{` or off-allow-list values with a plain-English reason, and `old` feeds the audit entry. Until Stories 17.3 and 17.4 merge these are stubs that answer "not implemented", so test against those signatures.
- **Instance zone.** `Decide`'s host setting `InstanceZone` is the single source (an IANA name, or empty for the container's `TZ`), written only through `Bridge.Time.SetZone`. The run-time approach was measured and works, so no restart fallback is needed. `OcuTalon.Data.Time`'s use of it is Story 18.2's.
- **Setting keys.** Stored in `OcuTalon.Data.Setting`, written only by `SettingsOps`, read through `Setting.Get` with these defaults; Story 17.5's install step seeds them:
  - `digest.time`: `08:00`
  - `digest.channels`: comma list of `web`, `phone`, `telegram`, default all three
  - `checks.thresholds.diskFreePercent`: 10
  - `checks.thresholds.journalFreePercent`: 10
  - `checks.thresholds.licenseUsePercent`: 90
  - `checks.thresholds.queueMessages`: 100
  - `checks.thresholds.queueWaitMinutes`: 10
- **How a change applies.** Product values apply by `Setting.Get`'s 60 s cache expiry, bridge host settings by `Ens.Director.UpdateProduction`, and model or provider changes by a restart of the affected runners (inside `Bridge.Settings.SetModel`). Installer seeds are written only when absent; after that `SettingsOps` owns them.
- **Demo mode** switches through the same `SettingsOps` path as `OcuTalon.Core.Admin.SetDemoMode`.
- **REST.** State-changing calls need `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`.
- **New tables.** Set `DEFAULTGLOBAL` to `^OcuTalonP.<Short>`, register the short name in `src/short-names.tsv`, and commit the compiler's `Storage` block. Storage is append-only.
- **Ownership.** Lane B owns Core (`SettingsOps`, `CommandsIn`), Msg, `Data.Setting`, `Data.Time`, Web and `web/`. Lane A owns Bridge, Digest, Checks and Agent. Lane B's catalog keys go in `Catalog.Core`; the page renders from the generated `web/src/app/msg/catalog.ts`.
- **Shared files.** The personality epics (39 to 41) also touch `SettingsOps`, `CommandsIn`, `Msg.Enum` and `Web.Api`. Append your own entries and don't rewrite theirs.

## UX & Interaction Patterns

- **Header.** Navigation shows "Chat" and, for admins, "Settings" (`header-nav-item`, `aria-current="page"`, inside a navigation landmark).
- **Page.** Titled "Settings · OcuTalon", with section navigation on the left: Models, Budgets, Channels, Daily digest, Time zone, Check thresholds, Demo mode.
- **Exact texts.**
  - Saved: "Saved. Applies within a minute. Recorded in the audit log."
  - Field error: "Couldn't save. Nothing was changed."
  - Denied: "Only OcuTalon admins can open settings.", with a link back to the chat.
- **Save changes** follows the busy pattern: it keeps its label, adds a spinner, gets `aria-busy` and `aria-disabled` (never `disabled`), ignores repeats, and restores after 10 s with no answer.
- **Field errors** are linked by `aria-describedby`, and submit focuses the first error.
- **Unsaved changes.** Leaving a section with unsaved changes asks first.
- **Wording.** Plain English, with no class names or error codes. Configuration names a user must type, such as `.env` variables, are allowed.

## Cross-Story Dependencies

- Story 33.2 uses the names Story 33.1 fixed. Its first consumers are `SettingsOps` calling the `Bridge.Settings` and `Bridge.Time` stubs, and `CommandsIn` routing `SendDigest` to `Digest`.
- `Digest` and the retry runners stay disabled stubs until Stories 17.6 and 17.2 enable them.
- 33.2 builds the page frame and the Check thresholds and Demo mode sections. The rest follow:
  - 18.2: Daily digest, Time zone and channel status;
  - 18.3: Models and Budgets;
  - 18.4: the digest card and the **Got it** button;
  - 17.6: digest sending and Telegram's handled copy.
- Epics 17 and 18 start only once Epic 33 has merged, and Story 34.2 needs it too.
- Epic 33 merges only after the 1.0.0 release branch exists, so no step work enters 1.0.0. The gate names rc1; rc1 was abandoned and rc4 is the cut.
