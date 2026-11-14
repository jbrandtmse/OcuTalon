# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine so Lane A's Epic 23 and Lane B's Epic 24 build paging, escalation, rollback and the SQL query watch in parallel, record the setting history of every watched production, and let an admin set the on-call person and backup in Settings. The epic only groups stories for merging: each story keeps its home lane's files. Stories 36.1, 36.2, 36.4 and 36.5 are done; 36.4 merges only after burn-down Story 36.6 fixes a silent channel loss in the On call form. Story 36.3 waits on Epic 22.

## Stories

- Story 36.1: Record the setting history of each watched production (done)
- Story 36.2: Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb (done)
- Story 36.3: Link the worked Jira example from the admin docs (backlog; waits on Story 22.6)
- Story 36.4: Set the on-call person and backup in Settings (done; merges after 36.6)
- Story 36.5: Epic 36 burn-down: load the Settings, History and Usage pages lazily (done; separated onto its own branch to merge first)
- Story 36.6: Epic 36 burn-down: keep a stored on-call user's channels when the user list is unavailable (next)

## Requirements & Constraints

- **Keep stored channels when the user list is unavailable (36.6, DW-1308, Planner option (a)):** `GET /api/v1/settings` answers `users: []` both when the roster can't be had (SettingsOps busy or failed) and when the user is gone. When a stored on-call user (primary or backup) is absent from that list, the On call section keeps that person's stored channel boxes, Telegram included, and shows no "no paired chat" line for them. Saving without touching that person sends and keeps the stored Telegram channel. The fix is **web-only**: no server change and no new user-facing text. The server's save-time checks decide (verified): an unknown user (no session row) is refused on `primaryUser`/`backupUser` with nothing saved; Telegram for an unpaired user is refused on the channels field with nothing saved.
- **36.6 tests:** a Playwright test pins that the stored Telegram channel survives a save while the list is unavailable, and a mutation that drops the channel must fail it; a test pins, through the page, that saving a stored user who no longer exists gets the existing unknown-user refusal and saves nothing.
- **On-call section rules (36.4, kept):** each role is nobody, an OcuTalon user or an email address; channels Telegram, email or both (both by default); Telegram only for a user whose session has a paired chat; escalation a whole number 1 to 1440 minutes (default 15). Save confirms "Saved. Applies within a minute. Recorded in the audit log."; a server failure shows "Couldn't save. Nothing was changed."; field errors mark the field and focus the first one; non-admins get 403; the online demo answers 409 `not_available`. No on-call value appears in a command, result, log line or trace; from/to values only in the IRIS audit log.
- **Bundle (36.5, standing):** the initial web bundle stays at most 921 kB (measured 878.98 kB after 36.5), `web/angular.json`'s initial budget stays `maximumError` 1MB; new web code goes into lazy chunks. Settings, History and Usage load lazily; deep links and reloads of `#/settings`, `#/history`, `#/usage` are pinned by Playwright.
- **Admin docs link (36.3):** with Epic 22 merged, link Story 22.6's worked Jira example under `docs/` from the README's admin section and copy its sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky; the link must resolve. Not yet available (22.6 is in backlog).

## Technical Decisions

- **On-call keys:** `oncall.primary.user`/`oncall.backup.user` (IRIS user name with a session, or ""), `oncall.*.email`, `oncall.*.channels` (comma list ordered `telegram,email`, default both; `telegram` accepted only for a user paired at save time; the saved channels must include one the person can be reached on), `oncall.escalationMinutes`. Written only by `SettingsOps`, read through `Data.Setting.Get` (cached, applies within a minute). A role is configured when its user or address is set.
- **Save path:** `POST /api/v1/settings/on-call` (`Web.OnCallSettings`) puts the whole body in `SecretHandoff` and submits a `SaveSettings` whose `Changes` is only `{"handoff": uri}`. Body members: `primaryPerson` (`nobody`/`user`/`email`), `primaryUser`, `primaryEmail`, `primaryChannels`, the backup equivalents and `escalationMinutes`. Refusals (400 `bad_settings`) name fields only, never values.
- **User list path (AD-13 as amended for DW-1278):** the web process never reads product storage globals directly. `SettingsOps` reads the roster in the production job through the `ListOnCallUsers` read verb and returns it via `SecretHandoff`; `GET /api/v1/settings` takes it once. SettingsOps has pool size 1, so a GET during a long command (a model test can hold it ~45 s, over the 20 s command wait) answers `users: []`; this is the case 36.6 handles in the web view (`on-call-view.ts`, where Telegram's state and the sent channels are derived from the list).
- **Delivered contracts other stories build on:** setting history (`Watch.SettingHistory`, `SettingSnapshot`/`SettingChange`, driven from `Checks` on the production-change counter); paging owner `IncidentManager` with `Data.Page` (Story 23.4); the `page` notification kind and `Notify` route, `Msg.Escalation`, the escalation kind on `Reminder`, `AckPage` and `SaveSqlWatch` verbs, on-call keys and `PartnerContact` (Lane B owns and Lane A never edits). `%Ens_ProductionConfig` WRITE ships with Story 23.3's `rollback_setting`, not here.

## UX & Interaction Patterns

- The On call form must never silently change a stored value: what the admin didn't touch is sent as stored. The "no paired chat" line appears only when the list positively shows the user unpaired, not when the list is missing.
- Texts ship verbatim from the accepted Settings texts; any new text needs the author's acceptance first (36.6 adds none). Every control labelled and keyboard-operable.

## Cross-Story Dependencies

- **Merge order:** 36.5 (separated branch) merges first; 36.6 lands before 36.4 merges; 36.3 last, after Epic 22's Story 22.6 supplies the Jira example.
- **Shared Settings files with other lanes:** Epic 21's lazy MCP section (21.4) and Epic 25's Roles section (25.4) change `settings-page.ts`, `settings-view.ts`, `SettingsOps.cls` and the settings tests; whoever pushes second integrates forward.
- **Downstream:** Stories 23.3, 23.4, 23.8, 24.2, 24.3 and 24.4 build on 36.1/36.2's contracts; 24.3's email page reads the on-call address keys at send time. 36.4 also carries ledger items DW-1249 (on-call values in a settings save's trace) and DW-1250 (an email-only person can never acknowledge a page); 36.6's charter covers only DW-1308.
