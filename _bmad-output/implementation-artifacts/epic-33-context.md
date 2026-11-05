# Epic 33 Context: Step 2's contracts, and the settings page opens for admins (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic fixes step 2's names in the spine and in code as stubs, and gives admins a settings page where each section saves on its own, applies within a minute without a restart and is audited, so that Epics 17 (digest, second model, providers, budgets) and 18 (settings sections) build in parallel. It exists only so the two contract stories merge together, which breaks the whole-epic pairing deadlock; each story keeps its home lane's files. Stories 33.1 (Lane A: spine, stubs, accepted digest texts) and 33.2 (Lane B: the settings page frame, Check thresholds and Demo mode) are done. What remains is the burn-down, Story 33.3: a demo mode saved on the settings page reaches an already open chat page only after a reload, so the Demo mode section must say so in its own confirmation instead of a live refresh.

## Stories

- Story 33.1: Fix the step 2 contracts in the spine
- Story 33.2: Open the settings page as an admin
- Story 33.3: Epic 33 burn-down

## Requirements & Constraints

- **Burn-down text (33.3).** A successful Demo mode save shows its own confirmation under a new text key, exactly: "Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change."
- **Nothing else changes.** Check thresholds keeps the shared saved text in `settings-view.ts` ("Saved. Applies within a minute. Recorded in the audit log."), and no other section's text changes. No live refresh of the open chat page now; that fix is filed in the ledger for later.
- **Burn-down tests.** The fixed-strings test covers the new key, and a browser test pins that a Demo mode save shows the new text and a Check thresholds save the shared one.
- **Access.** Only `OcuTalonAdmin` can use the page. Non-admins get no Settings link, the address shows "Only OcuTalon admins can open settings." with a link back to the chat, and every settings API call answers 403 as `{"error": {"code", "message"}}`. The online demo's account holds no `OcuTalonAdmin`.
- **Saving.** A save is one command through `Commands.Submit` with origin `web_admin`; `SettingsOps` writes and audits each value (type `Settings`: IRIS user, `SessionRef`, channel, old and new value, never a secret) and it applies within 60 s with no IRIS or production restart. A refused or failed save shows "Couldn't save. Nothing was changed." and changes nothing, except a Demo mode save whose demo step fails: that keeps the written value (as the terminal path does, re-running the step at the next start) and shows its own field message.
- **Origins and values.** A settings command from origin `tool` is refused (`SendDigest` is accepted from `tool` and `web_admin`). Any admin-entered value containing `@{` is rejected. Keys come only from the environment and never appear.

## Technical Decisions

- **Demo mode** switches through the same `SettingsOps` path as `OcuTalon.Core.Admin.SetDemoMode`.
- **Catalog texts.** Lane B's keys go in `Catalog.Core`; the page renders from the generated `web/src/app/msg/catalog.ts`. Wording is plain English with no class names or error codes.
- **How a change applies.** Product values apply by `Setting.Get`'s 60 s cache expiry, bridge host settings by `Ens.Director.UpdateProduction`, model or provider changes by restarting the affected runners inside `Bridge.Settings.SetModel`. Installer seeds are written only when absent.
- **Setting keys** live in `OcuTalon.Data.Setting`, written only by `SettingsOps`, read through `Setting.Get` with defaults: `digest.time` `08:00`; `digest.channels` comma list of `web`, `phone`, `telegram` (all three); `checks.thresholds.diskFreePercent` 10, `journalFreePercent` 10, `licenseUsePercent` 90, `queueMessages` 100, `queueWaitMinutes` 10.
- **Bridge values** change only through `OcuTalon.Bridge.Settings` (`Providers`, `Values`, `Check`/`Set`, `CheckModel`/`SetModel`, `SetPrice`, `TestRequest`, `TestAnswer`) and the zone only through `Bridge.Time.SetZone`; these stay stubs answering "not implemented" until Stories 17.3 and 17.4 merge.
- **Daily digest due rule (amended).** On a tick, a session that has not ended is due only when the latest `digest.time` (instance zone) has passed, that time is later than the session's `CreatedAt`, and the session has no scheduled `Sent` row with that `DueAt` or later. A new session's first scheduled digest is at the first `digest.time` after it was created, so online-demo visitors get no immediate digest. Built and tested in Story 17.6, not here.
- **REST.** State-changing calls need `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`.
- **Ownership.** Lane B owns Core (`SettingsOps`, `CommandsIn`), Msg, `Data.Setting`, `Data.Time`, Web and `web/`; Lane A owns Bridge, Digest, Checks and Agent. The personality epics (39 to 41) also touch `SettingsOps`, `CommandsIn`, `Msg.Enum` and `Web.Api`: append your own entries and don't rewrite theirs.

## UX & Interaction Patterns

- Header navigation shows "Chat" and, for admins, "Settings" (`header-nav-item`, `aria-current="page"`, inside a navigation landmark). The page title is "Settings", a middle dot (U+00B7), then "OcuTalon", with section navigation on the left: Models, Budgets, Channels, Daily digest, Time zone, Check thresholds, Demo mode.
- **Save changes** follows the busy pattern: keeps its label, adds a spinner, gets `aria-busy` and `aria-disabled` (never `disabled`), ignores repeats, restores after 10 s with no answer.
- Field errors are linked by `aria-describedby`, and submit focuses the first error. Leaving a section with unsaved changes asks first.

## Cross-Story Dependencies

- Story 33.3 changes only the Demo mode section's confirmation built by Story 33.2; it adds no contract.
- Later sections build on 33.2's frame: 18.2 (Daily digest, Time zone, channel status), 18.3 (Models, Budgets), 18.4 (digest card, **Got it**), 17.6 (digest sending, Telegram's handled copy). `Digest` and the retry runners stay disabled stubs until 17.6 and 17.2.
- Epics 17 and 18 start only once Epic 33 has merged whole, burn-down included; Story 34.2 needs it too. Epic 33 merges only after the 1.0.0 release branch exists, so no step work enters 1.0.0.
