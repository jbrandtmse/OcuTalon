---
title: 'Story 33.2: Open the settings page as an admin'
type: 'feature'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-33-context.md'
warnings:
  - oversized
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 2 has no way to change OcuTalon's settings from the web: an admin needs a terminal, Lane B's step 2 contracts are named but not in the spine or the code, and Epics 17 and 18 cannot start until they are.

**Approach:** Add Lane B's contracts to the spine and create their names in code (the verbs `SendDigest`, `GotIt` and `SaveSettings`, the `Data.Handled` table, `Delivery.FindByRef`, the `handled` notification kind and the `dailyCost` slot type). Build the admin-only page frame with its seven sections, the settings REST routes and the save path through `Commands.Submit` to `SettingsOps`, with working Check thresholds and Demo mode sections.

## Boundaries & Constraints

**Always:**
- Every settings API call from a user without `OcuTalonAdmin` answers 403 `{"error": {"code", "message"}}`, including the routes that answer 501 for an admin. The web check is `OcuTalonAdmin` only (never `%All`, AD-19).
- A save is one command through `Commands.Submit` with origin `web_admin`, `ActingUser` from `$USERNAME` and `SessionRef` from `Ownership.SessionRef` (AD-1, AD-4). No save takes a role, a user or a session from the body.
- `SettingsOps` stays the only run-time writer of `Data.Setting`, and writes only keys on its allow-list (AD-19).
- A section's save is all or nothing for its values. Validate every value before anything is written; a refused value changes nothing and writes no audit entry.
- Each changed value has its own `Settings` audit entry through `Bridge.Audit.Record`: `setting`, `from`, `to`, `irisUser`, `sessionRef`, `channel` (AD-17). No change is ever left without an entry.
- Any value containing `@{` is refused (AD-19). No key or secret reaches the page, the audit entry or a log.
- The page uses the busy pattern through `ServerButton`, and field errors through `aria-describedby`, with submit focusing the first error (UX-DR32, UX-DR36).
- Keep every edit of a contended file small and in its own block (project block). Author `U+00B7` in source as `\u00B7` (Rule 14).

**Never:**
- Edit a Lane A class or test: `src/bridge/**`, `Digest/**`, `Msg/Catalog/Watch.cls`, Lane A's region of `Production.cls` (U-177).
- Edit `docker/**`, `src/ocutalon/cls/OcuTalon/Install/**`, `src/module.xml`, root `module.xml`, `preload/**`, `src/cpf/**` or `release/**`, or add a test file under `docker/tests/`.
- Build the controls of Models, Budgets, Channels, Daily digest or Time zone, or `Notify`'s digest rule, the **Got it** behaviour or `Send my digest now` (Stories 18.2, 18.3, 18.4, 17.6).
- Add a production item, a role, a resource or a CI group.
- Ship a text that `EXPERIENCE.md`, `epics.md` or a recorded ruling does not give (`ux-strings.test.mjs` refuses it).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Admin opens the page | README account, `#/settings` | Header nav "Chat", "Settings" (current), title "Settings \u00B7 OcuTalon", seven sections in order | No error expected |
| Non-admin, direct address | `OcuTalonUser` only, `#/settings` | No Settings link; denied text and a link back to the chat | `GET /v1/settings` answers 403 `not_admin` |
| Non-admin, any settings call | GET and each of the 7 POST routes | 403 `not_admin` before body, envelope or route | Nothing submitted |
| Save thresholds | Admin changes two of five values | 200; two rows written, two audit entries, saved text shown | No error expected |
| Save with nothing changed | Same values | 200; no write, no audit entry, saved text shown | No error expected |
| Refused value | Non-number, out of range, or `@{` | 400 `bad_settings` with `fields`; field error on each named field, first focused; nothing written, no entry | Text: "Couldn't save. Nothing was changed." |
| Unknown or missing field | Body lacks a field or adds one | 400 `bad_settings`; nothing written | Same text, under the button |
| Failed write or audit | `Setting.Set` or `Record` fails on the 2nd of 5 | 500; every value rolled back | Same text, under the button |
| Demo mode save | Admin switches it | `SetDemoMode` with origin `web_admin`; audit, write, Demo step; saved text | `not_audited` shows the field error |
| Demo step fails | `step_failed` (value stays written, as the terminal path) | 409 `demo_step_failed`; the page shows the text of ruling T9, never "Nothing was changed." | See `For the lead`, L2 |
| Bridge section by API | `POST /v1/settings/budgets` or `/time-zone` on the stubs | `Bridge.Settings.Check` answers 5003 -> outcome `not_built` -> 501; nothing written | Real stub instance, no double |
| No answer for 10 s | Held `POST` | Button restored, `BUSY_NOTICE` shown; a late answer still shows | `ServerButton` as built |
| Leaving unsaved | Dirty section; section link, Chat link or back | Asks first; Stay keeps the values, Leave discards them | Reload or close uses the browser's own `beforeunload` prompt |
| `SettingsOps` from a tool | `SaveSettings`, `SetDemoMode` with origin `tool`, or any origin in a bridge context | `not_allowed`, nothing sent | "That can't be done from the chat. Nothing was changed." |
| `SendDigest` | origin `tool` or `web_admin` | Sent to `Digest`; its `CommandResult` is the answer | Any other origin `not_allowed`; a stub owner `not_built` |
| Integration (Rule 1): page -> API -> save | Browser saves thresholds through the real production | `GET /v1/settings` after the save shows the new values, and `Setting.Get` in a process whose cache entry is 60 s old reads them | No mock |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- anchors: AD-1 tool list (113), AD-13 (404+), AD-14 Notify bullet (about 461) and Delivery bullet (462), AD-19 last bullet (642), AD-32 digest bullet (1041), REST route table (1440-1450), Tables paragraph (1290), cross-area table (row 1309 names 33.2's contracts), erDiagram (1352+).
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ALLOWLIST` (:21), `Carry` (:50, demo only), `AuditData` (:88), `Stored` (:101, private, row read), `WriteAudit` (:107), `Apply` (:114), `Result`. Contended with Epic 40, which renames `AuditData`'s arguments, splits `Carry` and adds `MESSAGESAVED` and `MESSAGENOTSAVED`: do not use those two names.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `TOOLVERBS` (:32), `XData Routes` (end), the admin-only refusal in `Carry` (keys on owner `SettingsOps`), `IsStub`. Contended: append only.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:64` -- `OnMessage` refuses any class but three with an error, which CommandsIn reports as `failed`.
- `src/ocutalon/cls/OcuTalon/Core/Admin.cls` -- terminal path; `Allowed` accepts `%All`, so the web must not reuse it.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Get` (60 s cache), `Set`; `Stored`-style row reads avoid the cache.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls` -- `Record`, `FindByApproval`, `DecisionRef` on every channel's row; `Data/Ownership.cls` `DeliveryFor` (:362) and `Rows`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- class doc, `UrlMap` (:125), `OnPreDispatch` (:145), `Fail(status, code, message, approval, extra)`, `DismissIncident` (:563) and `Unpair` (:709) as the submit pattern, `NotBuilt` (:640), `StateBody` (:741), `BodyText` (:304). `%CSP.REST` passes `OnPreDispatch` the URL below the application (`irislib/%CSP/REST.cls:377`).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- `HasRole` reads `$Roles`, the pattern for the admin check; no Shell change, routing is hash-based.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- slot types in the class doc, `SlotText` (:152), `Cost` (:228), `Find` reads `..#CLASSES`. `Msg/Enum.cls:30` `NOTIFICATIONKIND`. `Msg/Command/SetDemoMode.cls` is the verb pattern.
- `src/bridge/cls/OcuTalon/Bridge/Settings.cls`, `Bridge/Time.cls`, `Bridge/Audit.cls` -- read only; stub signatures in 33.1's spec.
- `web/src/app/app.config.ts` -- wildcard route, hash location. `web/src/app/app.ts` -- skip links and `app-demo-guide` sit outside the router outlet. `web/src/app/header/header.ts` -- `.side` holds the home link, badge and demo switch. `web/src/app/api/api-client.ts`, `api-types.ts` (`StateSnapshot`), `envelope.interceptor.ts` (only 401 and 503 are special, so 403 reaches the caller).
- `web/src/app/shared/server-button.ts`, `busy-state.ts`, `dialogs.ts`, `announcer.ts`; `web/src/app/header/sign-out-dialog.ts` (dialog sibling, first focus on Cancel), `demo-view-switch.ts` (switch sibling); `web/src/app/mailbox/simulated-mailbox.ts` and `mailbox-view.ts` (field error sibling).
- `web/scripts/ux-strings.test.mjs` -- `IMPORTED` and `SOURCES`, the fixed-strings test. A `ruled` entry names its cycle-log ruling.
- Tests to copy: `Test/Core/SettingsOps.cls` and `SettingsOpsProbe.cls` (shadow instance, seams), `Test/Core/CommandsRouting.cls` and `CommandsInProbe.cls`, `Test/Web/DismissApi.cls` and `ApiProbe.cls` (stand-in request, real production), `Test/Bridge/AuditLog.cls` (`Now`, `Wait`, read only), `Test/Contract/Ac.cls` (verb fields :216, class list :249, `Signatures` :291), `Test/Data/Tables.cls` (`Contracts`, `Registry`), `web/e2e/sign-in/helpers.ts`, `web/e2e/support/iris.ts` (`fixtureUser`), `web/e2e/demo-switch/badge.spec.ts`.

## Tasks & Acceptance

**Execution:**
- [ ] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- apply edits P1 to P9 of `### Spine edits`. P1 to P5 are additive sub-bullets marked `[AMENDED 2026-11-04, Story 33.2, orchestrator ruling (U-268)]`, and no existing sentence is rewritten; rows are marked `[ADDED 2026-11-04, Story 33.2]`. Then `lint_spine.py`: no new finding (8 existing `placeholder` findings). Append one `memlog.py append --type decision` line naming the new rows.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Command/SendDigest.cls` -- new verb, base fields only: no recipient, channel or address field of any kind (U-268) -- AC 1.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Command/GotIt.cls` -- new verb: `Ref` `%String(MAXLEN=22)` (the notice's Ref, P3), `Channel` `%String(MAXLEN=32)` -- AC 1.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSettings.cls` -- new verb: `Slug` `%String(MAXLEN=32)` (the section), `Changes` `%String(MAXLEN="")` (JSON object of field to value), `ActingUser` `%String(MAXLEN=160)`. Neither `Section` nor `Values`: this is a persistent message class, and `VALUES` is an SQL reserved word (Conventions, SQL reserved words).
- [ ] `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- append `SendDigest` to `TOOLVERBS`; append routes `SendDigest` (owner `Digest`, origins `tool,web_admin`), `SaveSettings` (owner `SettingsOps`, origins `web_admin,system`), `GotIt` (owner `SessionOps`, origins `web_user,web_admin,telegram`); doc lines. In `Carry`, extend `Dismiss`'s context check to `SendDigest`: inside a bridge context a `SessionRef` that is not the context's `OwnerRef` answers `not_allowed` with the existing `MESSAGENOTFROMTOOL` and sends nothing (U-268; no new text).
- [ ] `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- one line before the class check in `OnMessage`: a `GotIt` answers `$$$ERROR($$$NotImplemented)`, so CommandsIn gives `not_built` until Story 18.4.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` -- append `handled` to `NOTIFICATIONKIND`.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- new `%Persistent`, `DEFAULTGLOBAL "^OcuTalonP.Handled"`: `Ref`, `SessionRef` `%String(COLLATION="EXACT", MAXLEN=22)`, `HandledAt` `%String(MAXLEN=20)`, `Channel` `%String(MAXLEN=32)`; `Index RefIndex On Ref [Unique]`; `ClassMethod Marked(ref) As %String` (the row's `HandledAt`, "" when unmarked). Commit the Storage block. The writer is Story 18.4's.
- [ ] `src/short-names.tsv` -- append `Handled	^OcuTalonP.Handled	OcuTalon.Data.Handled	B`.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Delivery.cls`, `Data/Ownership.cls` -- add `Delivery.FindByRef(ref, channel, ownerRef) As %String`, the newest row of the owner and channel whose `DecisionRef` is `ref`, through a new `Ownership.DeliveryByRef` and one `Rows` kind on `OwnerRefChannelIndex` (no new column, no new index; extends `FindByApproval` and `DeliveryFor`).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- slot type `dailyCost` (US dollars of 0 or more, always two decimals) in the class doc and `SlotText`, reusing `Cost`'s value checks.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- append the seven keys to `ALLOWLIST`; widen `AuditData`'s first argument type to `OcuTalon.Msg.Command`; one dispatch line at the top of `Carry` for `SaveSettings`; then one new block at the end of the class: `XData Sections` (each section, its fields, key or bridge name, kind and default, per `### Sections`), `Save` (Design Notes D5), `Field` validators and `ClassMethod Values() As %DynamicObject` (the GET body, read from rows through `Stored`, plus `Bridge.Settings.Values()`, `Providers()` and `Bridge.Time.Zone()`). Seams `BridgeCheck` and `BridgeSet` around the two `Bridge.Settings` calls for the test subclass. New message parameters are named `MESSAGESECTIONSAVED` and `MESSAGESECTIONREFUSED`.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `IsAdmin()` (private, `$Roles` by whole name, the role `OcuTalon.Core.Admin.#ROLE`); in `OnPreDispatch`, after the user-role check and before the envelope, a URL equal to `/v1/settings` or below it needs `IsAdmin`, else `Fail(403, "not_admin", MESSAGENOTADMIN)`; routes `GET /v1/settings`, and `POST /v1/settings/models`, `/budgets`, `/channels`, `/daily-digest`, `/time-zone`, `/check-thresholds`, `/demo-mode`, with `models` and `channels` on `NotBuilt`; one `SaveSection(section)` that submits and maps outcomes (D6); `SaveDemoMode`; `admin` boolean in `StateBody` after `user`; class doc.
- [ ] `web/src/app/api/api-types.ts`, `api-client.ts` -- `StateSnapshot.admin`, the settings types, `settings()`, `saveSettings(section, values)`.
- [ ] `web/src/app/settings/settings-view.ts` -- new framework-free module: `SETTINGS_TEXTS`, `SETTINGS_SECTIONS` (slug and label, UX order), dirty and validation helpers.
- [ ] `web/src/app/settings/settings-page.ts` -- new page: `main` with `h1` "Settings", a navigation landmark with the section links, `h2` per section, denied view on a 403, load failure with `LOAD_FAILED` and Retry.
- [ ] `web/src/app/settings/check-thresholds-section.ts`, `demo-mode-section.ts` -- the two working sections, each with `ServerButton` **Save changes**; the saved text is shown and announced once; field errors linked and focused.
- [ ] `web/src/app/settings/unsaved-dialog.ts`, `unsaved-guard.ts` -- copy of `SignOutDialog`'s shape (a reason: its buttons and service differ) opened through `Dialogs`; a `canDeactivate` guard; a `beforeunload` listener only while dirty.
- [ ] `web/src/app/app.config.ts` -- routes `settings` and `settings/:section` before the wildcard, with `title`; the wildcard gets title `OcuTalon`.
- [ ] `web/src/app/app.ts`, `web/src/app/header/skip-links.ts` -- show the skip links and `app-demo-guide` on the main page only (D8).
- [ ] `web/src/app/header/header.ts`, new `web/src/app/header/header-nav.ts` -- `nav` with `RouterLink`s "Chat" and, when `admin`, "Settings", D `header-nav-item`, `aria-current="page"`, after the demo view switch; tokens through `scripts/tokens.mjs` if `header-nav-item` is not generated yet.
- [ ] `web/scripts/ux-strings.test.mjs`, `web/scripts/settings-view.test.mjs` (new) -- add `settings/settings-view.ts` to `IMPORTED`; every new string gets its `SOURCES` entry (`ux`, `ac`, or `ruled` citing U-269 for T1 to T8 and T10, U-270 for T9); unit tests of the helpers.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsSave.cls` (new), `SettingsOpsProbe.cls` (seams `BridgeCheck`, `BridgeSet`) -- every matrix row of `SettingsOps`, all-or-nothing on a failure at each position, only changed values audited, allow-list, bridge path against a double and the bare stub.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsAudit.cls` (new) -- reads each kind back from the IRIS audit log with `AuditLog.Wait` and a 180 s limit (S8): a threshold, a digest key, a bridge value (double), demo mode (step stand-in). Throwaway and CI only.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsCommands.cls` (new, not the contended `CommandsRouting`) -- routes and origins of the three verbs; `SaveSettings` from `tool` and inside a bridge context refused; `SendDigest` from every origin; `GotIt` `not_built`. `TestSendDigestTakesNoRecipient`: the class's properties are exactly `Msg.Command`'s, read from `%Dictionary`. `TestSendDigestOwnSessionOnly`: inside a bridge context a foreign `SessionRef` is refused and nothing reaches the owner (U-268).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` (new), `ApiProbe.cls` (a `Roles` seam) -- GET shape with no key material, each route for admin and non-admin, each outcome's status and body, envelope, `@{`, `admin` in `/state`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/NoticeRows.cls` (new) -- `Handled` and `FindByRef`; `Test/Msg/DailyCost.cls` and `Test/Msg/DailyCostCatalog.cls` (new; a `Catalog` subclass with its own `CLASSES`) -- two decimals, zero, rounding, refused values.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` (`TestAllowList`), `Test/Contract/Ac.cls` (3 verbs, 3 signatures, floor), `Test/Data/Tables.cls` (one contract, one registry row), `Test/Msg/Contracts.cls` (kind), `Test/Web/Api.cls:132`, `web/e2e/api/api.spec.ts:134`, `web/e2e/frame/frame.spec.ts:91`, `web/e2e/floor/*` -- update each old shape in the `Shared surfaces` list; search the test trees, `e2e-online` included.
- [ ] `web/e2e/settings/settings.spec.ts` (new, chromium project) -- nav, title, sections, save thresholds and read back, busy, refused, failed (route-held 500), unsaved prompt, non-admin denied and 403 on all eight calls with `fixtureUser('LIVE')`. Restores the values it changes.
- [ ] `web/e2e/demo-switch/z-settings-save.spec.ts` (new; the name runs it last, because `Setting.Get` in a CSP job can hold the old mode for 60 s and the other specs of the folder read it) -- only with `OCUTALON_E2E_DEMO_MODE=1`: the page saves demo mode off, then on, and the saved text shows. It ends on; confirm that is the state `test-demo-switch.sh` expects after `e2e 1` (line 370).

**Acceptance Criteria:**
- Given the spine after this story, when it is read against `### Spine edits`, then each of P1 to P9 is present with its marker, the settings routes and each contract are in the ownership tables, no existing sentence of a Rule, Binds, Prevents or convention row is changed, and `lint_spine.py` reports no new finding.
- Given a signed-in `OcuTalonAdmin`, when the page loads, then the header navigation landmark holds "Chat" and "Settings" as `header-nav-item`s with the current page marked `aria-current="page"`, and Settings opens a page titled "Settings \u00B7 OcuTalon" with section navigation on the left in the order Models, Budgets, Channels, Daily digest, Time zone, Check thresholds, Demo mode.
- Given a signed-in user without `OcuTalonAdmin`, when they use the app or open `#/settings`, then no Settings link shows, the page shows "Only OcuTalon admins can open settings." with a link back to the chat, and `GET /v1/settings` and all seven save routes answer 403 in the error shape.
- Given an admin changed a section's values, when they press **Save changes**, then one `SaveSettings` command (or `SetDemoMode`) reaches `SettingsOps` with origin `web_admin`, each changed value is written and audited with the admin's IRIS user, `SessionRef`, channel `web`, and old and new values, no restart happens, and the section shows "Saved. Applies within a minute. Recorded in the audit log."
- Given a save is pressed, when it is refused or fails, then the button follows the busy pattern, the field error "Couldn't save. Nothing was changed." is linked and focused, and no value changed; except a Demo mode save whose demo step fails (`step_failed`), which keeps the written value and shows T9 (U-270).
- Given unsaved changes, when the admin leaves the section by a link or the browser's back, then the page asks first, and only Leave discards them.
- Given the Check thresholds section, when an admin saves it, then the values land under `checks.thresholds.*`, `GET /v1/settings` shows them at once, and `Setting.Get` in a process with an expired cache entry reads them.
- Given the Demo mode section, when an admin saves it, then the switch goes through `SetDemoMode` and the same `SettingsOps` path as `Core.Admin.SetDemoMode`, and the audit channel is `web`.
- Given `digest.time`, `digest.channels` and the five threshold keys, when `POST /v1/settings/daily-digest` or `/check-thresholds` is called, then `SettingsOps` validates and stores them, and no other class writes them.
- Given `SendDigest`, when it is submitted from `tool` or `web_admin`, then `CommandsIn` sends it to `Digest`; from any other origin it is `not_allowed`.
- Given the tests, when they run, then one reads each kind of settings change back from the IRIS audit log, one submits `SaveSettings` with origin `tool` and expects a refusal, and `ux-strings.test.mjs` covers every new label.
- Given `SendDigest` from origin `tool` or `web_admin`, when it is built or submitted, then it carries no recipient, and a tool cannot name another session: destinations come only from the session's `digest.channels`, so neither the model nor an item can choose where a digest goes. A test pins each half, with its mutation shown (U-268).
- Given Lane A's stub signatures, when a bridge section is saved through the real API, then `SettingsOps` calls `Bridge.Settings` by the spine's names and the answer is 501 with nothing changed.

## Spec Change Log

- 2026-11-04, the lead: U-268's answer and conditions added as acceptance items, with the `SessionRef` check. The orchestrator's rulings recorded under `### Rulings`; the AC on refused and failed saves amended for `step_failed` (U-270). The intent block is unchanged.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-1 (commands, origins), AD-3 (`DEFAULTGLOBAL`, registry), AD-4 (session from the server), AD-5 (append-only storage), AD-13 (REST, envelope), AD-14 (Notify, Delivery), AD-17 (audit), AD-19 (config homes, `SettingsOps`, `@{`), AD-22 (tests), AD-23 (Demo step), AD-29 (lanes, verbs, stubs), AD-32 (catalog), AD-33 (ownership tables). Only two spine edits touch an existing Rule (below). No AC contradicts an AD. No NFR tripwire.

**Ledger inbox (Rule 17):** none for this story.

**Integration ACs (Rule 1):** the matrix's last row, and AC "Given Lane A's stub signatures". `SendDigest`, `GotIt`, `Data.Handled`, `Delivery.FindByRef`, kind `handled` and `dailyCost` have no consumer in this story; the first consumers are Stories 17.6 and 18.2 (`SendDigest`), 18.4 and 17.6 (`GotIt`, `Handled`, `FindByRef`, `handled`) and 17.6 (`dailyCost`).

**Consumed-by:**
- 17.5 -- `checks.thresholds.*` through `Setting.Get`.
- 17.6 -- `SendDigest`, `GotIt`, `Data.Handled.Marked`, `Delivery.FindByRef`, kind `handled`, `dailyCost`.
- 18.2 -- the page frame, `daily-digest` and `time-zone` routes, `SendDigest`.
- 18.3 -- the page frame, `models` and `budgets` routes, section address `#/settings/budgets`.
- 18.4 -- `GotIt`'s owner branch, the `Handled` writer, `handled`.
- 34.2 -- the header navigation.
- 35.2 -- the settings page and routes.

**Consumes:** `Bridge.Settings.Check`, `.Set`, `.Values`, `.Providers`, `Bridge.Time.Zone` (33.1 stubs, called on the real stub instance), the `Digest` item (33.1), `Bridge.Audit.Record`, `Commands.Submit`.

**Extend, don't copy (Rule 2):** `SaveSection` follows `DismissIncident` and shares `Fail`. `AuditData`, `WriteAudit`, `Apply`, `Stored` and `Result` are extended, not copied. `FindByRef` extends `FindByApproval` and `DeliveryFor`. `dailyCost` shares `Cost`'s checks. `UnsavedDialog` copies `SignOutDialog`'s shape because its buttons and result differ. `SettingsOpsProbe` and `ApiProbe` gain seams. `ServerButton`, `Dialogs` and `Announcer` are reused unchanged.

### Sections

What each of the seven sections holds in this story:

| Section (slug) | On the page | Save route | Fields |
|---|---|---|---|
| Models (`models`) | Heading and T4's line; no button | `NotBuilt`, 501 (18.3) | none |
| Budgets (`budgets`) | Heading and T4's line; no button | live, reaches the stub, 501 until 17.4 | `DecisionTokenBudget`, `DailyCostCapUSD` (bridge) |
| Channels (`channels`) | Heading and T4's line; no button | `NotBuilt`, 501 (18.2; email 35.2) | none |
| Daily digest (`daily-digest`) | Heading and T4's line; no button | live | `time` -> `digest.time` (`HH:MM`, 08:00), `channels` -> `digest.channels` (a non-empty, duplicate-free comma list of `web`, `phone`, `telegram`; all three) |
| Time zone (`time-zone`) | Heading and T4's line; no button | live, reaches the stub, 501 until 17.4 | `InstanceZone` (bridge) |
| Check thresholds (`check-thresholds`) | Five number fields, **Save changes** | live | `diskFreePercent` 10, `journalFreePercent` 10, `licenseUsePercent` 90 (whole numbers 1 to 100); `queueMessages` 100, `queueWaitMinutes` 10 (whole numbers 1 to 1000000) |
| Demo mode (`demo-mode`) | One switch, its help line, **Save changes** | live, `SetDemoMode` | `demoMode` (boolean) |

`GET /v1/settings` answers `{"sections": {"check-thresholds": {...}, "daily-digest": {...}, "demo-mode": {"demoMode"}}, "bridge": Values(), "providers": Providers(), "instanceZone": Zone()}`.

### Decided in-stage

- **D1. One generic verb, `SaveSettings`,** not one per section: one route table entry, and 18.2 and 18.3 add sections as rows of `XData Sections`. `SetDemoMode` stays its own verb (AC).
- **D2. The notice's `Ref` is its `Decision`'s Ref** (`Notification.DecisionRef`). A `Notification` has no `Ref` of its own, and every `*Out` already records `DecisionRef` on its `Delivery` row, so no schema change to `Delivery` is needed. Tell-now notices always come from a decision (`Core.Rule.Notice`).
- **D3. `GotIt`'s owner is `SessionOps`:** a new item would change Lane A's production oracle, and the marker is session state. It answers `not_built` until Story 18.4.
- **D4. `Notify`'s digest routing is spine-only here.** Story 18.2's AC builds it. The verbs, `Handled`, `FindByRef`, `handled` and `dailyCost` are created now, because Lane A's Story 17.6 names them and cannot edit Lane B's files.
- **D5. Save order.** Parse and validate every field; drop unchanged values; for product keys, `TSTART`, then for each value `WriteAudit`, `Apply`; `TCOMMIT`; any failure `TROLLBACK` and `not_audited` or `failed`. A failure on a later value can leave an audit entry for an earlier value that was rolled back (inference: whether `TROLLBACK` removes it is unmeasured; implement records what it sees in `SettingsAudit`). An entry with no change is the honest side of that trade; a change with no entry never happens (AD-17). Bridge values: every `Check` first; then each `Set` and its audit entry (`old` comes from `Set`); a later failure `Set`s the earlier values back and audits that.
- **D6. Outcome to HTTP:** Ok 200 `{"result":"done","sections":...}`; `refused` 400 `bad_settings` with `fields`; `not_built` 501; `step_failed` 409 `demo_step_failed`; `not_audited`, `failed`, `unknown_command`, a status error 500 `server_error`. The page shows the field error for all but 2xx, 403, 401 and 409.
- **D7. Fresh reads for the page.** `Values()` reads rows, not `Setting.Get`, so a reload right after a save never shows the old value in a CSP job's cache.
- **D8. Off the main page** the demo guide and the skip links do not render, because their targets are the main page's regions. The Settings page keeps its landmarks and headings.
- **D9. `#/settings` opens Models,** the first section in the UX's order. A section has its own address, which 18.3's banner action needs. An unknown slug opens Models.
- **D10. Page gating** is the `GET` answer: 403 shows the denied view, so a stale snapshot never shows the page. `admin` in `/state` only decides the link.
- **D11. Non-admins see "Chat" alone** in the navigation (epic context).
- **D12. Demo mode on the online demo:** no extra guard. No published account holds `OcuTalonAdmin` (AD-24).
- **D13. The Demo step's time is no busy problem:** measured 1 to 3 s end to end (Story 4.1, ARM), under the 10 s busy limit; CI runners run about three times slower (inference).
- **D14. Threshold ranges** are implementation values chosen here; the PRD fixes only the defaults.

### Rulings

The orchestrator's rulings of 2026-11-04. They replace "planned default" and "needing a ruling" wherever those appear below.

- **T1 to T8, T10:** accepted as proposed (veto U-269).
- **T9, L2:** the default stands: keep the terminal path and show T9 (veto U-270). `epics.md`'s AC is amended to exclude `step_failed`.
- **L1:** the default stands: this story adds the `dailyCost` slot type only and edits no Lane A file. `digest.cost` goes to Story 17.6 as DW-661, superseding 33.1's ruling 4 (veto U-271).
- **L3, contended edits:** proceed. "Epic 33 first" covers small non-append edits in `Core/SettingsOps.cls`, `Core/SessionOps.cls`, `Test/Core/SettingsOpsProbe.cls` and `Test/Msg/Contracts.cls`. Keep each minimal; Epic 40 absorbs them. A conflict that needs a behaviour choice goes back to the lead.
- **A1, A2, P1 to P5:** allowed as additive sub-bullets (U-268, answered (a) at=2026-11-04T12:10:10Z#813), on these conditions:
  1. `SendDigest` takes no recipient; destinations come only from the session's `digest.channels`, so neither the model nor an item chooses where a digest goes.
  2. It stays non-risky only because it reaches the session's own channels. The AD-1 sub-bullet says so: any later external target is a new ruling.
  3. The specs citing AD-1 and AD-14 in Epics 7, 39 and 40 were read before `spec_validated` (below).
- **P6, P7:** may proceed. **P8, P9:** new rows, allowed by the project block's plain-union rule and required by the AC's "ownership tables in the same change".

**The lead's reading of the citing specs (condition 3).** Epic 7 cites AD-1 for items by name only. Epic 39's verbs `SetHeartbeat` and `RunHeartbeat` take `web_user` and are refused from `tool`, which holds; its beat is an Item through `Intake` (AD-14), and its `digest` outcome goes to `DigestStore`, not a kind `digest` notification. Epic 40's `TestToolGovernanceRefused` names the verbs it refuses and no test pins the whole list; its narrowed admin-only refusal keeps `SaveSettings` (origins `web_admin,system`). None relies on the list being closed at its present verbs, or on digest routing. Epic 40's `ProposePersona` and this story's `SendDigest` both append to `TOOLVERBS`: a one-name union at the second merge.

**`SessionRef` is a recipient path (the lead, under condition 1).** The verb has no recipient field, but its base `SessionRef` picks whose channels are used, so a tool naming another session would choose the destination. `Carry` therefore applies `Dismiss`'s context check to `SendDigest`. `web_admin` takes its `SessionRef` from `Ownership.SessionRef` (AD-4).

### Text needing a ruling

Each row is now ruled (`### Rulings`). The `ruled` source in `ux-strings.test.mjs` cites the ruling.

| # | Where it appears | Proposed wording |
|---|---|---|
| T1 | Unsaved prompt, sentence | "You have unsaved changes in this section. Leave without saving?" |
| T2 | Unsaved prompt, buttons (Stay has first focus) | "Stay", "Leave without saving" |
| T3 | Denied view, link back to the chat | "Back to the chat" |
| T4 | Models, Budgets, Channels, Daily digest, Time zone body | "This part of OcuTalon isn't built yet." (the API's existing `MESSAGENOTBUILT`) |
| T5 | Check thresholds labels | "Disk free space below (%)", "Journal free space below (%)", "License use above (%)", "Queue backlog above (messages)", "Oldest queued message waiting over (minutes)" |
| T6 | Demo mode switch label and state | "Demo mode", "On", "Off" |
| T7 | Demo mode help line | "Demo mode adds the demo guide, Break the feed, and the simulated devices." (EXPERIENCE's sentence without its FR reference) |
| T8 | Accessible names of the two navigation landmarks | "Pages", "Settings sections" |
| T9 | Demo mode field message on `step_failed` | "Demo mode is set to {on or off}, but the switch didn't finish. OcuTalon tries again at its next start." |
| T10 | API `error.message` of 403 `not_admin` and 400 `bad_settings` | The UX's "Only OcuTalon admins can open settings." and "Couldn't save. Nothing was changed." (verbatim; listed because the use is new) |

Verbatim, no ruling needed: "Chat", "Settings", "Settings \u00B7 OcuTalon", the seven section names, **Save changes**, the saved text, the field error, the denied text, `BUSY_NOTICE`, `LOAD_FAILED`.

### Watched paths needed

None. `^OcuTalonP.*` is mapped whole to the private database (`docker/merge.cpf:11`, `src/cpf/ocutalon.cpf:11`), so `Data.Handled` needs no install step. `OcuTalonAdmin` exists, the local README account holds it, the routes live in the existing `/ocutalon/api` application and the page uses hash routing, so no security, role or web-application change is needed. Story 17.5's step seeds the keys. The new e2e specs sit under `web/e2e/`, and existing scripts pick them up by folder.

### AD changes (ruled, U-268)

- **A1. AD-1 (P1).** The Rule says `CommandsIn` accepts from origin `tool` "only" a closed list. The AC adds `SendDigest`. A new sub-bullet that leaves the sentence as it is: "From step 2 `CommandsIn` also accepts `SendDigest` from origin `tool` and `web_admin` (Story 17.6's digest tool, a safe action, FR-7). It takes no recipient and reaches only the session's own `digest.channels`, which is the only reason it is not risky: any later external target needs a new ruling."
- **A2. AD-14 (P2).** The Rule says a notification goes to the web chat, the phone and the paired chat "except kind `allowance`". A new sub-bullet: "From step 2, kind `digest` goes only to the session's `digest.channels`, each where the session has it (Story 18.2)."

### For the lead

- **L1. Lane conflict: `digest.cost`.** The 33.1 ruling 4 and the epic context say the key lands with 33.2, but it belongs in `Msg/Catalog/Watch.cls`, which this story may never edit (U-177, project block); `Test.Msg.Catalog` refuses a prefix in both catalog classes, so `Catalog.Core` cannot hold it. Planned default: this story adds the `dailyCost` slot type only and edits no Lane A file, and `digest.cost` is not added. Recommended: route the key to Story 17.6, Lane A's first composer of the cost part, or rule a one-key exception. Either way `Test.Msg.Catalog`'s `SLOTTYPES` (:25) and its branch (:693) gain `dailyCost` with the key.
- **L2. A guarantee the same-path AC cannot keep.** "A refused or failed save changes nothing" does not hold for `step_failed`: `SettingsOps` keeps the written value and re-runs the step at the next start, pinned by `TestStepFails`, and the AC also says the same path as the terminal. Saying "Nothing was changed." there would be false. Planned default: keep the path and show T9. The alternative, restoring the value and re-running the step, can fail too. This is a veto item (weakening a guarantee), raised with T9.
- **L3. Footprint and contended files.** Outside the paths hint (Rule 11 b): `Core/SessionOps.cls` (one line, contended with Epic 40), `Data/Delivery.cls`, `Data/Ownership.cls`, `Msg/Catalog.cls`. Contended edits: `Core/CommandsIn.cls`, `Core/SettingsOps.cls`, `Msg/Enum.cls`, `Test/Data/Tables.cls`, `src/short-names.tsv`, `Data/Ownership.cls`.
- **L4. `Test.Bridge.CodeRules`' own `TOOLVERBS` (:107)** is Lane A's list of verbs a tool may reference. It needs `SendDigest` when Story 17.6 adds the tool; this story leaves it alone.

### Spine edits

| # | Section | Edit |
|---|---|---|
| P1 | AD-1 | New sub-bullet (A1) |
| P2 | AD-14 | New sub-bullet (A2), and a new bullet: **Got it** (`GotIt`, owner `SessionOps`, origins `web_user`, `web_admin`, `telegram`; first press wins; Story 18.4), a notice's `Ref` is its `DecisionRef` (D2), `Data.Handled`, kind `handled` to each `*Out` so that it updates its copy (Telegram's Story 17.6), `Delivery.FindByRef(ref, channel, ownerRef)` |
| P3 | AD-13 | New bullet: the settings routes, the admin check in `OnPreDispatch` before the envelope, 403 `not_admin`, `OcuTalonAdmin` only, `admin` in `/state`, the address `#/settings/<section>` |
| P4 | AD-19 | New bullet: `SaveSettings` (`Slug`, `Changes`, `ActingUser`), `XData Sections`, the save order (D5), the allow-list holding the step 2 keys; `Values()` for the page |
| P5 | AD-32 | New bullet: slot type `dailyCost`, two decimals |
| P6 | REST table (after 1450) | New rows: `GET /api/v1/settings`; `POST /api/v1/settings/<section>` for the seven slugs with their target; `/state` also carries `admin` |
| P7 | Tables paragraph (1290) | Append: from step 2 Lane B owns `Handled` (each tell-now notice's handled marker) |
| P8 | Cross-area table (after 1309) | New rows: `OcuTalon.Msg.Command.SendDigest`, `.GotIt`; `OcuTalon.Data.Handled.Marked`, read by `Digest`; `OcuTalon.Data.Delivery.FindByRef`; kind `handled` to each `*Out`; Notify's kind `digest` (Story 18.2); `dailyCost`. Each B, built here unless named |
| P9 | Data model | `Session ||--o{ Handled : "its handled notices"` |

## Verification

Every `ci/iris.sh` and `ci/warm.sh` call carries `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=33 stage=implement'`, the fresh tag `OCUTALON_RUN_TAG=e33s2i` or the warm tag `e33s2iw`, and `timeout: 600000`. One class or unit per call. Any IRIS MCP call names server `ocutalon-slot-c` and namespace `OCUTALON`. Run `ci/warm.sh up` once with the warm tag, and `ci/warm.sh down` at the end, also after a failure.

**Commands:**
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e33s2iw ci/iris.sh class <Class>`, one call each for `OcuTalon.Test.Core.SettingsSave`, `.Core.SettingsCommands`, `.Core.SettingsAudit`, `.Core.SettingsOps`, `.Web.SettingsApi`, `.Web.Api`, `.Data.NoticeRows`, `.Data.Tables`, `.Msg.DailyCost`, `.Msg.Contracts`, `.Contract.Ac` -- expected: each class passes.
- (loop) `node --test web/scripts/settings-view.test.mjs web/scripts/ux-strings.test.mjs` -- expected: pass.
- (loop) `npm --prefix web run build` -- expected: the tokens, payloads and catalog checks and the build pass.
- (once) `ci/iris.sh build` -- expected: the bundle is rebuilt, before any browser unit.
- (once) `ci/iris.sh live sign-in --part 1/2`, then `--part 2/2` -- expected: pass; `web/e2e/settings/` runs in part 2. If a part nears 8 minutes, use `--part k/3`.
- (once) `ci/iris.sh live demo-switch` -- expected: pass with the new spec at mode 1.
- (once) `ci/iris.sh live floor` -- expected: pass.
- (once) `ci/iris.sh live demo-path` -- expected: pass.
- (once) `ci/iris.sh live production` -- expected: pass.
- (once) `ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2` -- expected: every class passes (DW-453's `GuideApi.TestRunAgain` red is a known flake: re-run it alone).
- (once) `ci/iris.sh shard lane-a --part 1/3`, `2/3`, `3/3` -- expected: every class passes, `Test.Bridge.CodeRules` included.
- (once) `bash docker/tests/test-boundaries.sh`, `test-class-rules.sh`, `test-storage.sh`, `test-ci-config.sh`, one per call -- expected: pass.
- (once) `node --test web/scripts/` -- expected: pass.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: the 8 existing findings and no new one.

**Shared surfaces:** the `/state` key list (`Test.Web.Api`, `web/e2e/api/api.spec.ts`, TS fixtures of `StateSnapshot`); the header's tab order and landmarks (`web/e2e/frame/frame.spec.ts`, `web/e2e/floor/*`, `e2e-online`); `SettingsOps.ALLOWLIST` (`Test.Core.SettingsOps`); `Msg.Enum NOTIFICATIONKIND` (`Test.Msg.Contracts`); the verb lists and signature floor (`Test.Contract.Ac`); the table registry (`Test.Data.Tables`, `src/short-names.tsv`); `ux-strings.test.mjs` `SOURCES`.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests (Rule 19; the stage that adds each writes its `mutation:` line here):** the header and title -> `settings.spec.ts`; 403 on every call -> `Test.Web.SettingsApi` and `settings.spec.ts`, mutation: drop the check in `OnPreDispatch`; save and audit -> `Test.Core.SettingsAudit`, mutation: skip `WriteAudit`; all or nothing -> `Test.Core.SettingsSave`, mutation: remove `TROLLBACK`; tool refusal -> `Test.Core.SettingsCommands`, mutation: add `SaveSettings` to `TOOLVERBS`; `SendDigest` -> the same class, mutation: remove `web_admin`; no recipient (U-268) -> `TestSendDigestTakesNoRecipient`, mutation: add a `Recipient` property to `SendDigest`; own session only (U-268) -> `TestSendDigestOwnSessionOnly`, mutation: drop `SendDigest` from the context check in `Carry`; `dailyCost` -> `Test.Msg.DailyCost`, mutation: use `Cost`'s tiers; `FindByRef` -> `Test.Data.NoticeRows`, mutation: drop the owner check; unsaved prompt -> `settings.spec.ts`, mutation: remove the guard; spine -> `lint_spine.py`, which pins the AD shape only, mutation: remove a `Rule` line -> `ad_fields` (33.1's demonstration); the rows themselves are read by the reviewer.

**Manual checks:** read `### Spine edits` against the spine diff; confirm `git status --short` shows no path under the watched list or a Lane A path.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
