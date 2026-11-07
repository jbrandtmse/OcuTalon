---
title: 'Story 33.2: Open the settings page as an admin'
type: 'feature'
created: '2026-11-04'
status: 'done'
baseline_revision: '170ccd8724977d22ffb82e437d294fc05bc49824'
baseline_commit: '170ccd8724977d22ffb82e437d294fc05bc49824'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-33-context.md'
warnings:
  - oversized
deferred:
  - summary: >-
      `Data.Handled` has no purge or end-of-session delete, and nothing names its owner.
    evidence: |-
      AD-27 has each area declare a purge, and `SessionOps.End` drops session-owned data; the new table keyed by `SessionRef` and the rows `Delivery.FindByRef` reads have neither in the spine text or the code. The writer is Story 18.4's, so its story should add the purge with the first row (unverified: whether the spine's purge list already covers every `^OcuTalonP.*` table).
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Handled.cls
    severity: medium (unverified)
  - summary: >-
      `SendDigest` sent to the `Digest` item while it is disabled answers `failed`, not `not_built`.
    evidence: |-
      `OcuTalon.Production` lists `Digest` with `Enabled="false"` (Lane A's item); `CommandsIn.IsStub` recognises code 5003 only, and a send to a disabled item gives another error. The tests route to a recording owner. No route submits `SendDigest` yet (Stories 17.6 and 18.2), so the first caller should run it against the real production once Lane A enables the item, or map the disabled-item error to `not_built` in `CommandsIn`.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls
    severity: medium (unverified)
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
- [x] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- apply edits P1 to P9 of `### Spine edits`. P1 to P5 are additive sub-bullets marked `[AMENDED 2026-11-04, Story 33.2, orchestrator ruling (U-268)]`, and no existing sentence is rewritten; rows are marked `[ADDED 2026-11-04, Story 33.2]`. Then `lint_spine.py`: no new finding (8 existing `placeholder` findings). Append one `memlog.py append --type decision` line naming the new rows.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Command/SendDigest.cls` -- new verb, base fields only: no recipient, channel or address field of any kind (U-268) -- AC 1.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Command/GotIt.cls` -- new verb: `Ref` `%String(MAXLEN=22)` (the notice's Ref, P3), `Channel` `%String(MAXLEN=32)` -- AC 1.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSettings.cls` -- new verb: `Slug` `%String(MAXLEN=32)` (the section), `Changes` `%String(MAXLEN="")` (JSON object of field to value), `ActingUser` `%String(MAXLEN=160)`. Neither `Section` nor `Values`: this is a persistent message class, and `VALUES` is an SQL reserved word (Conventions, SQL reserved words).
- [x] `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- append `SendDigest` to `TOOLVERBS`; append routes `SendDigest` (owner `Digest`, origins `tool,web_admin`), `SaveSettings` (owner `SettingsOps`, origins `web_admin,system`), `GotIt` (owner `SessionOps`, origins `web_user,web_admin,telegram`); doc lines. In `Carry`, extend `Dismiss`'s context check to `SendDigest`: inside a bridge context a `SessionRef` that is not the context's `OwnerRef` answers `not_allowed` with the existing `MESSAGENOTFROMTOOL` and sends nothing (U-268; no new text).
- [x] `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- one line before the class check in `OnMessage`: a `GotIt` answers `$$$ERROR($$$NotImplemented)`, so CommandsIn gives `not_built` until Story 18.4.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` -- append `handled` to `NOTIFICATIONKIND`.
- [x] `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- new `%Persistent`, `DEFAULTGLOBAL "^OcuTalonP.Handled"`: `Ref`, `SessionRef` `%String(COLLATION="EXACT", MAXLEN=22)`, `HandledAt` `%String(MAXLEN=20)`, `Channel` `%String(MAXLEN=32)`; `Index RefIndex On Ref [Unique]`; `ClassMethod Marked(ref) As %String` (the row's `HandledAt`, "" when unmarked). Commit the Storage block. The writer is Story 18.4's.
- [x] `src/short-names.tsv` -- append `Handled	^OcuTalonP.Handled	OcuTalon.Data.Handled	B`.
- [x] `src/ocutalon/cls/OcuTalon/Data/Delivery.cls`, `Data/Ownership.cls` -- add `Delivery.FindByRef(ref, channel, ownerRef) As %String`, the newest row of the owner and channel whose `DecisionRef` is `ref`, through a new `Ownership.DeliveryByRef` and one `Rows` kind on `OwnerRefChannelIndex` (no new column, no new index; extends `FindByApproval` and `DeliveryFor`).
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- slot type `dailyCost` (US dollars of 0 or more, always two decimals) in the class doc and `SlotText`, reusing `Cost`'s value checks.
- [x] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- append the seven keys to `ALLOWLIST`; widen `AuditData`'s first argument type to `OcuTalon.Msg.Command`; one dispatch line at the top of `Carry` for `SaveSettings`; then one new block at the end of the class: `XData Sections` (each section, its fields, key or bridge name, kind and default, per `### Sections`), `Save` (Design Notes D5), `Field` validators and `ClassMethod Values() As %DynamicObject` (the GET body, read from rows through `Stored`, plus `Bridge.Settings.Values()`, `Providers()` and `Bridge.Time.Zone()`). Seams `BridgeCheck` and `BridgeSet` around the two `Bridge.Settings` calls for the test subclass. New message parameters are named `MESSAGESECTIONSAVED` and `MESSAGESECTIONREFUSED`.
- [x] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `IsAdmin()` (private, `$Roles` by whole name, the role `OcuTalon.Core.Admin.#ROLE`); in `OnPreDispatch`, after the user-role check and before the envelope, a URL equal to `/v1/settings` or below it needs `IsAdmin`, else `Fail(403, "not_admin", MESSAGENOTADMIN)`; routes `GET /v1/settings`, and `POST /v1/settings/models`, `/budgets`, `/channels`, `/daily-digest`, `/time-zone`, `/check-thresholds`, `/demo-mode`, with `models` and `channels` on `NotBuilt`; one `SaveSection(section)` that submits and maps outcomes (D6); `SaveDemoMode`; `admin` boolean in `StateBody` after `user`; class doc.
- [x] `web/src/app/api/api-types.ts`, `api-client.ts` -- `StateSnapshot.admin`, the settings types, `settings()`, `saveSettings(section, values)`.
- [x] `web/src/app/settings/settings-view.ts` -- new framework-free module: `SETTINGS_TEXTS`, `SETTINGS_SECTIONS` (slug and label, UX order), dirty and validation helpers.
- [x] `web/src/app/settings/settings-page.ts` -- new page: `main` with `h1` "Settings", a navigation landmark with the section links, `h2` per section, denied view on a 403, load failure with `LOAD_FAILED` and Retry.
- [x] `web/src/app/settings/check-thresholds-section.ts`, `demo-mode-section.ts` -- the two working sections, each with `ServerButton` **Save changes**; the saved text is shown and announced once; field errors linked and focused.
- [x] `web/src/app/settings/unsaved-dialog.ts`, `unsaved-guard.ts` -- copy of `SignOutDialog`'s shape (a reason: its buttons and service differ) opened through `Dialogs`; a `canDeactivate` guard; a `beforeunload` listener only while dirty.
- [x] `web/src/app/app.config.ts` -- routes `settings` and `settings/:section` before the wildcard, with `title`; the wildcard gets title `OcuTalon`.
- [x] `web/src/app/app.ts`, `web/src/app/header/skip-links.ts` -- show the skip links and `app-demo-guide` on the main page only (D8).
- [x] `web/src/app/header/header.ts`, new `web/src/app/header/header-nav.ts` -- `nav` with `RouterLink`s "Chat" and, when `admin`, "Settings", D `header-nav-item`, `aria-current="page"`, after the demo view switch; tokens through `scripts/tokens.mjs` if `header-nav-item` is not generated yet.
- [x] `web/scripts/ux-strings.test.mjs`, `web/scripts/settings-view.test.mjs` (new) -- add `settings/settings-view.ts` to `IMPORTED`; every new string gets its `SOURCES` entry (`ux`, `ac`, or `ruled` citing U-269 for T1 to T8 and T10, U-270 for T9); unit tests of the helpers.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsSave.cls` (new), `SettingsOpsProbe.cls` (seams `BridgeCheck`, `BridgeSet`) -- every matrix row of `SettingsOps`, all-or-nothing on a failure at each position, only changed values audited, allow-list, bridge path against a double and the bare stub.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsAudit.cls` (new) -- reads each kind back from the IRIS audit log with `AuditLog.Wait` and a 180 s limit (S8): a threshold, a digest key, a bridge value (double), demo mode (step stand-in). Throwaway and CI only.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsCommands.cls` (new, not the contended `CommandsRouting`) -- routes and origins of the three verbs; `SaveSettings` from `tool` and inside a bridge context refused; `SendDigest` from every origin; `GotIt` `not_built`. `TestSendDigestTakesNoRecipient`: the class's properties are exactly `Msg.Command`'s, read from `%Dictionary`. `TestSendDigestOwnSessionOnly`: inside a bridge context a foreign `SessionRef` is refused and nothing reaches the owner (U-268).
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` (new), `ApiProbe.cls` (a `Roles` seam) -- GET shape with no key material, each route for admin and non-admin, each outcome's status and body, envelope, `@{`, `admin` in `/state`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/NoticeRows.cls` (new) -- `Handled` and `FindByRef`; `Test/Msg/DailyCost.cls` and `Test/Msg/DailyCostCatalog.cls` (new; a `Catalog` subclass with its own `CLASSES`) -- two decimals, zero, rounding, refused values.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` (`TestAllowList`), `Test/Contract/Ac.cls` (3 verbs, 3 signatures, floor), `Test/Data/Tables.cls` (one contract, one registry row), `Test/Msg/Contracts.cls` (kind), `Test/Web/Api.cls:132`, `web/e2e/api/api.spec.ts:134`, `web/e2e/frame/frame.spec.ts:91`, `web/e2e/floor/*` -- update each old shape in the `Shared surfaces` list; search the test trees, `e2e-online` included.
- [x] `web/e2e/settings/settings.spec.ts` (new, chromium project) -- nav, title, sections, save thresholds and read back, busy, refused, failed (route-held 500), unsaved prompt, non-admin denied and 403 on all eight calls with `fixtureUser('LIVE')`. Restores the values it changes.
- [x] `web/e2e/demo-switch/z-settings-save.spec.ts` (new; the name runs it last, because `Setting.Get` in a CSP job can hold the old mode for 60 s and the other specs of the folder read it) -- only with `OCUTALON_E2E_DEMO_MODE=1`: the page saves demo mode off, then on, and the saved text shows. It ends on; confirm that is the state `test-demo-switch.sh` expects after `e2e 1` (line 370).

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
- Given `SendDigest` from origin `tool` or `web_admin`, when it is built or submitted, then it carries no recipient, and a tool cannot name another session: destinations are the session's own channels that `digest.channels` names (by default all of them), until Story 18.2 [AMENDED 2026-11-06, Story 17.6, owner ruling via the Contest Planner; it read "destinations come only from the session's `digest.channels`"], so neither the model nor an item can choose where a digest goes. A test pins each half, with its mutation shown (U-268).
- Given Lane A's stub signatures, when a bridge section is saved through the real API, then `SettingsOps` calls `Bridge.Settings` by the spine's names and the answer is 501 with nothing changed.

### Review Findings

Code review of 2026-11-05 (first review; four layers, full tier). 36 rows, 22 entries after grouping: 0 high, 6 medium, 16 low; 13 rejected. Status: done (every patch applied; the two open mediums are ledgered with an owner).

- [x] [Review][Patch] MED: #/settings and #/settings/<section> were two route configs, so the first section link rebuilt the page (a second GET, a loading flash, keyboard focus lost to the body) [web/src/app/app.config.ts:18] -- one route with `settingsMatch` (settings-view.ts); S1 pins focus and one load. fix-risk low.
- [x] [Review][Patch] MED: a browser back answered with Stay overwrote the previous history entry (Angular's default `canceledNavigationResolution: 'replace'`), so a later back skipped that page [web/src/app/app.config.ts:27] -- `withRouterConfig({ canceledNavigationResolution: 'computed' })`; S6c. fix-risk low.
- [x] [Review][Patch] MED (Rule 19): AC 4's "no restart happens" had no pinning test [src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls:157] -- `TestSaveThresholds` asserts `^Ens.Runtime("StartTime")` is unchanged by the save. fix-risk low.
- [x] [Review][Patch] MED (Rule 19 hermeticity): `TestSaveDemoModeAudited` read "the stack's own mode" through this process's 60 s `Setting.Get` cache, so a stale entry would switch demo mode for the whole stack [src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls:197] -- the cache entry is killed first, so the mode is the row's. fix-risk low. Its link to DW-639 (Heartbeat): none found; Heartbeat runs before it in name order, and the Demo step at the stack's own mode touches only OCUORDERS, never OcuTalon.Production's items.
- [x] [Review][Patch] LOW: "Saved" was announced while the saved text was hidden (an edit made during the save) [web/src/app/settings/check-thresholds-section.ts:210, demo-mode-section.ts:221] -- announced only when shown.
- [x] [Review][Patch] LOW: a failed thresholds save (no field named) showed the error under the button with no announcement [web/src/app/settings/check-thresholds-section.ts:226] -- the announcer reads the existing field-error text (no new text).
- [x] [Review][Patch] LOW: the Demo mode switch's accessible name carried its On/Off state ("Demo mode On"), unlike the Demo view switch [web/src/app/settings/demo-mode-section.ts:46] -- the state text is `aria-hidden`; aria-checked carries the state.
- [x] [Review][Patch] LOW: a save answered 403 showed the denied view but left `dirty` set, so Back to the chat opened the unsaved prompt [web/src/app/settings/settings-page.ts:59] -- `deny()` clears it; S4b.
- [x] [Review][Patch] LOW: the in-flight-edit fix of the implement review had no test [web/e2e/settings/settings.spec.ts] -- S5b.
- [x] [Review][Patch] LOW: the load failure and Retry had no test [web/e2e/settings/settings.spec.ts] -- S1f.
- [x] [Review][Patch] LOW (Rule 19): S4's and S7's "nothing changed" read-backs could not fail (the POST never left the browser) [web/e2e/settings/settings.spec.ts] -- removed.
- [x] [Review][Patch] LOW (Rule 19): `TestBridgeRoutesAre501`'s `Rows() = 0` could not fail (no bridge path writes a product row) [src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls:243] -- removed with its doc claim.
- [x] [Review][Patch] LOW: `TestDemoModeAudited`'s doc claimed an unasserted ordering [src/ocutalon/cls/OcuTalon/Test/Core/SettingsAudit.cls:119] -- claim removed.
- [x] [Review][Patch] LOW (Rule 19): S2 (AC 4's saved text, Rule 1's integration row) had no `mutation:` line -- demonstrated and written under `## Verification`.
- [x] [Review][Defer] MED: a demo mode saved on the page does not reach the open main page until a reload [web/src/app/settings/settings-page.ts:239] -- DW-699 decision-pending (product call; a fix needs a refresh design against the 60 s cache, or new text). fix-risk high.
- [x] [Review][Defer] MED: `SendDigest` to the disabled `Digest` item answers `failed` [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:179] -- DW-696 (occurrence appended; owner 17-6).
- [x] [Review][Defer] LOW: `SaveBridge` does not clear `old` before `BridgeSet` -- DW-700 wontfix-theoretical.
- [x] [Review][Defer] LOW: `SaveBridge` compares bridge values as raw strings -- DW-701 wontfix-theoretical.
- [x] [Review][Defer] LOW: audit entries of a rolled-back product save stay -- DW-702 by-design (D5).
- [x] [Review][Defer] LOW: `z-settings-save.spec.ts` runs last by name and needs demo mode on -- DW-703 by-design (spec task).
- [x] [Review][Defer] LOW: the bridge tests assert Lane A's stub answers -- DW-704 by-design (matrix row); 17.4 updates them.
- [x] [Review][Defer] LOW (Rule 2): `UnsavedDialog` copies `SignOutDialog`'s shape -- DW-705 wontfix-accepted, reopen_if a third copy.

Rejected:
- `false` Edge: `SendDigest` from `tool` outside a bridge context skips the own-session check -- `Carry` makes the origin `tool` only while a context is active; the spec's check is the context's, as `Dismiss`'s.
- `false` Edge: the time-zone save reads `Bridge.Time.Zone` but writes through `Bridge.Settings.Set` -- the spine (AD-19 bridge settings APIs) routes `InstanceZone` through `Time.SetZone`, and `Apply` runs at each conversion.
- `false` Gap: `TestAllOrNothingAudit` at position 1 is trivial -- it pins `not_audited` and an empty write when the first audit fails; positions 2 to 5 pin the rollback.
- `false` Auditor info: a failed thresholds save does not move focus -- matrix row "Failed write or audit": the text under the button, which describes the focused button.
- `false` Auditor info: AC 4 "no restart" and DW-695/DW-696 -- the same as the entries above.
- `low` Edge: an out-of-range stored int is shown and refused on save -- only `SettingsOps` writes those rows, with the range check.
- `low` Edge: a bridge value sent as a JSON number is canonicalised (7.50 to 7.5) -- the same number; the bridge's Check judges it.
- `low` Edge: a put-back after a failed audit write audits a reversal of an unaudited change -- a double failure, and the entry records a real Set.
- `low` Gap: a 403 save never reaches the denied view in a test -- covered now by S4b with the dirty fix.
- `low` Blind: the triage log's "7 low patched" disagrees with six entries -- the fix edits the spec's own narrative.
- `low` Auditor: doc lines of the contended `SettingsOps` and `CommandsIn` were edited in place -- ruling L3 covers small non-append edits; the `CommandsIn` task names doc lines.
- `low` Edge: entries of the hunters that repeat a finding above (announce while hidden x2, Digest disabled) -- grouped.
- `low` Gap: AC 1's mutation is Story 33.1's `ad_fields` -- the spine rows were read against `### Spine edits` by the acceptance auditor (plain unions; one changed line, P7's append).

## Spec Change Log

- 2026-11-06 Story 17.6 lead (owner ruling via the Contest Planner): AC at :145 amended in place: the destinations are the session's own channels that digest.channels names (default all), until Story 18.2.

- 2026-11-04, the lead: U-268's answer and conditions added as acceptance items, with the `SessionRef` check. The orchestrator's rulings recorded under `### Rulings`; the AC on refused and failed saves amended for `step_failed` (U-270). The intent block is unchanged.

## Review Triage Log

### 2026-11-04 -- Review pass
- verdicts: 36 findings -- high 0, medium 6, low 19, false 8, maybe-false 3 (the intent-alignment auditor's seven divergences are counted as rows)
- findings:
  - `[false]` `[reject]` Blind: empty digest channels accepted -- `$Length("", ",")` is 1 (checked on the slot), so the loop runs, the list is empty, and the lengths differ; `TestDigestSection` refuses `""` and is green.
  - `[low]` `[reject]` Blind: a rolled-back product save leaves audit entries for earlier values -- D5 states this trade and AD-17 forbids the opposite (a change with no entry); spec-bound.
  - `[false]` `[reject]` Blind: `SendDigest` own-session guard covers `tool` only -- no web route submits `SendDigest` in this story; the future route takes `SessionRef` from `Ownership.SessionRef` as `SaveSection` does (ruling condition 1).
  - `[false]` `[reject]` Blind: encoded or odd settings URLs may skip the admin gate -- the gate and the route map see the same string; an encoded path matches no route; a prefix match on `/v1/settings` only widens the gate.
  - `[medium]` `[patch]` Blind: a save in flight overwrites edits made while it was pending -- fixed: the section keeps an edit made since the request and stays dirty (thresholds and Demo mode).
  - `[low]` `[patch]` Blind: dead code (`BUILT`, `built()`, `thresholdError`) -- removed, with its unit test and the header claim.
  - `[maybe-false]` `[defer]` Blind: `Data.Handled` has no purge or owner -- deferred to Story 18.4 (what would settle it: whether the purge list covers every private table).
  - `[low]` `[reject]` Blind: the spine states the Lane B contracts twice -- fixing it rewrites an existing row of the 33.1 change, which the project block forbids.
  - `[low]` `[patch]` Blind: stale `unknown_command` doc line in `SettingsOps` -- corrected.
  - `[false]` `[reject]` Edge: empty channels -- the same claim as above.
  - `[medium]` `[patch]` Edge: `SaveBridge` is not all-or-nothing when `BridgeSet` or the audit write throws -- fixed with a Try/Catch that puts earlier values back; `TestBridgeSetThrows`.
  - `[low]` `[reject]` Edge: a save that succeeded but whose `Values()` throws answers 500 -- the stubs and the rows cannot throw today; a hardening branch for a future Lane A fault.
  - `[low]` `[reject]` Edge: `dirty` stays true when a save answers 403 -- needs the admin role revoked mid-session; the fix adds a branch.
  - `[low]` `[patch]` Edge: `pageOf` lower-cases the path while the router does not -- made case-sensitive and matrix parameters stripped; test updated.
  - `[medium]` `[patch]` Edge: edits during a pending save are overwritten -- the same fix as above.
  - `[maybe-false]` `[defer]` Edge: `SendDigest` to the disabled `Digest` item answers `failed`, not `not_built` -- deferred; settled by running it once Lane A enables the item.
  - `[low]` `[reject]` Edge: concurrent saves of one section -- two admins on one instance; the audit `from` could be one save stale.
  - `[false]` `[reject]` Edge claim: a failed save shows no linked, focused field error -- the matrix row says a failed write or audit shows the text under the button; only a refused field is linked and focused.
  - `[false]` `[reject]` Edge claim: a bridge save with no change answers 200, not 501 -- the matrix row "Save with nothing changed" answers 200; the 501 row posts a changed value.
  - `[medium]` `[patch]` Gap: no test observes `SaveDemoMode`'s command (user, `SessionRef`, channel web) -- `TestSaveDemoModeAudited` added; mutations in `## Verification`.
  - `[medium]` `[patch]` Gap: the client branch for 409 `demo_step_failed` runs in no test -- `settings.spec.ts` S7b added.
  - `[low]` `[patch]` Gap: the demo guide's absence on the settings page is unasserted -- asserted in S1 (and its presence on the main page).
  - `[low]` `[patch]` Gap: AC pinning tests without `mutation:` lines -- eleven lines added and demonstrated (server, browser and node), including the three the stage had left to the supervisor.
  - `[medium]` `[patch]` Gap: the bridge tests depend on Lane A's stub state (`SaveBridge` read the real `Values()`) -- `BridgeCurrent` seam added; the tests that assert the stub's answer by design stay (the matrix asks for the real stub).
  - `[low]` `[reject]` Gap: `z-settings-save.spec.ts` depends on running last -- the spec names the file order and the folder's other specs read the mode.
  - `[low]` `[reject]` Gap: `TestUnchangedWritesNoEntry` is a one-shot negative check -- it cannot turn a true pass into a failure.
  - `[low]` `[reject]` Gap: the routes ratchet is a source-text test -- S6 is the real pin and has its mutation.
  - `[low]` `[patch]` Gap (other): `SaveBridge` reads current values outside the seam -- the same fix as the stub coupling.
  - `[false]` `[reject]` Gap (other): a `tool` `SendDigest` outside a bridge context routes for any `SessionRef` -- the spec's check is for a bridge context, as `Dismiss`'s is.
  - `[false]` `[reject]` Intent: real `$Roles` is exercised only by the e2e run -- S8 and the admin cases do exercise it; descriptive.
  - `[low]` `[reject]` Intent: no test pins an audit entry for a rolled-back value -- D5.
  - `[low]` `[reject]` Intent: a failed put-back or its audit write is only logged -- a double failure; the log line names the value.
  - `[maybe-false]` `[defer]` Intent: `SendDigest` routing never meets the live production -- the same deferred item as the disabled `Digest`.
  - `[low]` `[reject]` Intent: the demo mode save is covered by the demo-switch unit only -- `TestSaveDemoModeAudited` now covers the route.
  - `[low]` `[reject]` Intent: the page route is not role-gated -- D10 gates by the GET answer.
  - `[low]` `[reject]` Intent: neighbouring source ratchets were widened -- each needed the new files and `beforeunload` while dirty (spec tasks).

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
- **D15. The refusal travels in `CommandResult`.** `SaveSettings` answers Outcome `done` (Ok 1; a save that changes nothing too), `refused` (Ok 0, `Data` = `{"fields": [names]}`, the names of the refused or missing fields, none for an extra field, an unknown section, the demo section or a body that is not an object), `not_built`, `not_audited`, `failed` or `unknown_command`. No property was added to `CommandResult`. `SettingsOps` has the three new message parameters `MESSAGESECTIONSAVED`, `MESSAGESECTIONREFUSED` and `MESSAGESECTIONNOTAUDITED` (developer text that no page shows).
- **D16. Seven routes, five small methods.** `%CSP.REST` cannot pass a literal to a route's method, so `budgets`, `daily-digest`, `time-zone`, `check-thresholds` and `demo-mode` each call a one-line method (`SaveBudgets`, `SaveDailyDigest`, `SaveTimeZone`, `SaveCheckThresholds`, `SaveDemoMode`); `models` and `channels` are on `NotBuilt`. `SaveSection(section)` and `Answer(result, word)` are private. `Api` has three new message parameters: `MESSAGENOTADMIN`, `MESSAGEBADSETTINGS` and `MESSAGEDEMOSTEPFAILED`. `Fail` now accepts an object or array member in `extra` (the `fields` list).
- **D17. Test seams in `Web.Api`.** `HasUserRole()` (the OcuTalon user role check of `OnPreDispatch`, which calls `Shell.HasRole`) and `Roles()` (`$Roles`) are private class methods that `Test.Web.ApiProbe` overrides from `^OcuTalonTest("ApiProbe","roles")`, so that `OnPreDispatch` can be driven with any role set in a process that holds none. `IsAdmin()` reads `Roles()` by whole name; `%All` does not count.
- **D18. Values.** An int field takes a JSON number or a string of 1 to 9 digits and stores its whole-number form; `digest.channels` is stored in the fixed order `web,phone,telegram`; an absent row compares, and audits as `from`, as the field's default (the terminal's `SetDemoMode` audits an absent row's `from` as empty); a bridge field is a string of at most 200 characters after trimming, and `Bridge.Settings.Check` judges it. For a bridge value the current value is `Bridge.Settings.Values()`'s member (`Bridge.Time.Zone()` for `InstanceZone`), only changed values are asked to `Check`, and a `Check` that answers code 5003 gives `not_built` for the whole section.
- **D19. `XData Sections` holds all seven sections' product, bridge and demo fields,** with kind `demo` for Demo mode: `Values()` reads it, and `SaveSettings` refuses it (the switch is `SetDemoMode`'s). Models and Channels have no row.
- **D20. The probe counts outside the transaction.** A `TROLLBACK` also undoes the probe's own `^OcuTalonTest` writes, so `SettingsOpsProbe` keeps the audit, write and Set counters that decide "fail at position n" in `^||OcuTalonSettingsOpsProbe`, a process-private global that a rollback leaves alone.
- **D21. Web shape.** `header/current-page.ts` (`CurrentPage`) tells the app and the header navigation which page is shown, from the address the page opened with and then the router. Only the open section renders, under its own `h2`. Section links carry `aria-current="true"`; the header's carry `aria-current="page"`. `dirty` is a signal of `SettingsPage`, which `unsavedGuard` reads. The source ratchets that list files (`announce-focus-sources`, `demo-view-sources`, `floor-sources`, `leave-sources`) name the new files with their reasons.
- **D22. `ux-strings` sources.** The test refuses a `ruled` entry for a string that EXPERIENCE.md holds, so T2's Stay, T6's On and Off, T8's Pages and T10's two sentences sit under `ux`; T1, T2's Leave without saving, T3, T4, T5, T7 (the UX's sentence without its FR reference, not a substring of it), the settings navigation's name and the unsaved prompt sit under `ruled` U-269; T9 under U-270.
- **D23. Review patches of the implement stage.** The header navigation marks the current page with a bottom border and underlines its links at rest (a `box-shadow` mark replaced the focus halo, and the floor refuses a link that is not underlined at rest). `SaveBridge` reads the bridge's current value through a new seam `BridgeCurrent` (the probe overrides it) and puts earlier values back when a `Set` throws. A save that returns after the user edited the form keeps the edit and the form dirty. `pageOf` is as case-sensitive as the router. `thresholdError` and `BUILT` were removed as unused. `Test.Web.SettingsApi` gains `TestSaveDemoModeAudited` (a demo mode save with the stack's own mode, so the Demo step changes nothing).

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

**Mutations run (Rule 19; stage implement; each applied on the warm stack, observed red, reverted, the file confirmed byte-identical with `cmp`, and the class green again on the same stack):**
- `mutation:` drop the admin check in `OnPreDispatch` (`If 0 && ...`) -> `Test.Web.SettingsApi` `TestNonAdminIs403Everywhere` red (no 403, the dispatch continues).
- `mutation:` skip `WriteAudit` in `SaveProduct` -> `Test.Core.SettingsAudit` `TestThresholdAudited` and `TestDigestKeyAudited` red (no entry in the audit log after 180 s of polling).
- `mutation:` remove `TROLLBACK` (all three) -> `Test.Core.SettingsSave` `TestAllOrNothingApply` red (the rows of the earlier values stay; "left OPEN 11 transactions").
- `mutation:` add `SaveSettings` to `TOOLVERBS` -> `Test.Core.SettingsCommands` `TestRoutesAndOrigins` and `TestSaveSettingsFromToolRefused` red (the tool's refusal now says the admin-only text, not the chat text).
- `mutation:` remove `web_admin` from the `SendDigest` route -> `TestRoutesAndOrigins` red (`SendDigest` from `web_admin` is not routed).
- `mutation:` add a `Recipient` property to `SendDigest` (U-268) -> `TestSendDigestTakesNoRecipient` red (the properties differ from `Msg.Command`'s, and `Recipient` names a destination).
- `mutation:` drop `SendDigest` from the context check in `Carry` (U-268) -> `TestSendDigestOwnSessionOnly` red (a foreign `SessionRef` reaches `Digest`).
- `mutation:` `dailyCost` uses `Cost` -> `Test.Msg.DailyCost` `TestDiffersFromCost` red.
- `mutation:` drop the owner check of `DeliveryByRef` -> `Test.Data.NoticeRows` `TestFindByRef` red.
- `mutation:` remove `canDeactivate: [unsavedGuard]` and the `title` from both settings routes -> `settings.spec.ts` S6 red (a section link no longer asks first) and S1t red (the page keeps the title `OcuTalon`); also `web/scripts/settings-view.test.mjs` "the routes" red (source ratchet, run in the loop).
- `mutation:` in `OnPreDispatch` `If 0 && ..IsSettingsUrl(url) && '..IsAdmin()` -> `settings.spec.ts` S8 red (a user without `OcuTalonAdmin` gets no denied view, because `GET /v1/settings` answers 200).
- `mutation:` `app.ts` renders `<app-demo-guide />` on every page -> `settings.spec.ts` S1 red (the demo guide shows on the settings page).
- `mutation:` the thresholds section's refusal handler does not focus the first field in error (`?.blur()`) -> `settings.spec.ts` S3 red; no `formError.set(true)` on a failed save -> S4 red; `BUSY_TIMEOUT_MS` 60 s -> S5 red (the busy notice does not show within 20 s); the Demo mode section's 409 branch tests for 410 -> S7b red. The five browser mutations above ran together in one `ci/iris.sh live sign-in --part 2/2` on a fresh throwaway; each named case was red and the others of the settings page that do not depend on the mutation were green; all files restored from backup with matching SHA-1, bundle rebuilt.
- `mutation:` `SaveDemoMode` omits `Set command.SessionRef = sessionRef` -> `Test.Web.SettingsApi` `TestSaveDemoModeAudited` red (the entry has no session Ref); submits with origin `system` instead of `web_admin` -> the same test red (channel `system`, not `web`); `SaveSection` omits `Set command.SessionRef` -> `TestSaveThresholds` red.
- `mutation:` `Field` drops the `@{` refusal -> `Test.Core.SettingsSave` `TestBridgeRefused` red (a bridge string with `@{` reaches Check; the numeric, time and channel fields refuse it by their format); `Values` reads `Setting.Get` instead of the row -> `TestValues` red; the time pattern accepts hour 24 -> `TestDigestSection` red; `NotImplemented` always 0 -> `TestBridgeStub` red; the `Catch` of `SaveBridge` sets no outcome -> `TestBridgeSetThrows` red; `SaveBridge` ignores the bridge's current value -> `TestBridgeUnchangedValueIsSkipped` red; no `TROLLBACK` on a failed audit write of `SaveProduct` -> `TestAllOrNothingAudit` red; `Answer` maps `step_failed` to 500 -> `TestAnswerMapping` red.
- `mutation:` a label changed in `SETTINGS_TEXTS` -> `web/scripts/ux-strings.test.mjs` "has an entry for every inventory string" red; `pageOf` lower-cases the path again -> `settings-view.test.mjs` "is the chat for every other address" red.
- `mutation:` (QA) the thresholds section focuses the last refused field instead of `firstInError` -> `settings.spec.ts` S3b red (the first refused field in the form, `licenseUsePercent`, is not focused); the Demo mode section's `(dirtyChange)` binding removed from `settings-page.ts` -> S6b red (a changed switch no longer asks before a section link leaves). Both ran together in one `ci/iris.sh live sign-in --part 2/2` on a fresh throwaway (126 passed, exactly these two red); both files restored from backup with matching SHA-1, `git status --short` unchanged, bundle rebuilt.

- `mutation:` (code review) `SaveSection` restarts the production after the submit (a jobbed `Ens.Director.RestartProduction`, waiting for the new start time) -> `Test.Web.SettingsApi` `TestSaveThresholds` red ("no restart: the production's start time is the same after the save"); AC 4's "no restart happens". Applied on the warm stack, red, restored from backup (`cmp` identical), class green again.
- `mutation:` (code review) the thresholds section never sets `done` -> `settings.spec.ts` S2 red ("the saved text shows"; S5 red too); AC 4's saved text and Rule 1's integration row. Together, in one `ci/iris.sh live sign-in --part 10/12` (the settings file alone) on a fresh throwaway: the two settings routes put back (no matcher) -> S1 red ("the Budgets link keeps the keyboard focus"); `canceledNavigationResolution` back to the default -> S6c red ("goes to the page before the section"); `deny()` without clearing `dirty` -> S4b red ("Back to the chat leaves"); `succeeded()` with `edited` always false -> S5b red ("the edit made meanwhile is kept"). Exactly those six red, ten green; files restored from snapshot (`cmp` identical, `git status --short` and `git diff --stat` unchanged), bundle rebuilt, part 10/12 then `sign-in --part 1/2` (138), `--part 2/2` (132) and `live floor` (107) green.

**QA stage audit (Story 33.2).** Every AC and matrix row has a pinning test with a `mutation:` line above, except "no restart happens" (no test can tell a restart from none without a production-start marker; not added). Two gaps were closed, both in `web/e2e/settings/settings.spec.ts` (QA): S3b (two refused values: both fields marked, the first in the form focused; before it only a single refused field ran in a browser) and S6b (the Demo mode section's unsaved-switch prompt and its return to clean; S6 covered the thresholds form only). Both green on a fresh throwaway (`live sign-in --part 2/2`: 128 passed).

**Manual checks:** read `### Spine edits` against the spine diff; confirm `git status --short` shows no path under the watched list or a Lane A path.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Lane B's step 2 contracts are in the spine (P1 to P9) and in code: the verbs `SendDigest` (no recipient; own-session check inside a bridge context), `GotIt` (`not_built` until Story 18.4) and `SaveSettings`, `Data.Handled`, `Delivery.FindByRef`, kind `handled` and slot type `dailyCost`. The admin-only settings routes (403 `not_admin` before the envelope) and the save path through `Commands.Submit` to `SettingsOps` (`XData Sections`, validation first, one audit entry per changed value, all or nothing) are built, with working Check thresholds and Demo mode sections on a new settings page with a header navigation, an unsaved-changes prompt and section addresses.

**Files changed.** Spine (`ARCHITECTURE-SPINE.md`, P1 to P9; memlog line); `Core/CommandsIn.cls`, `Core/SessionOps.cls`, `Core/SettingsOps.cls`, `Msg/Enum.cls`, `Msg/Catalog.cls`, `Msg/Command/{SendDigest,GotIt,SaveSettings}.cls`, `Data/Handled.cls`, `Data/Delivery.cls`, `Data/Ownership.cls`, `src/short-names.tsv`, `Web/Api.cls`; web: `api/`, `settings/` (page, two sections, view model, unsaved dialog and guard), `header/` (navigation, current page, skip links), `app.ts`, `app.config.ts`; tests: `Test/Core/{SettingsSave,SettingsCommands,SettingsAudit}.cls`, `Test/Web/SettingsApi.cls`, `Test/Data/NoticeRows.cls`, `Test/Msg/{DailyCost,DailyCostCatalog}.cls`, probes and the shared-surface tests, `web/e2e/settings/settings.spec.ts`, `web/e2e/demo-switch/z-settings-save.spec.ts`, `web/scripts/settings-view.test.mjs` and four source ratchets widened for the new files.

**Review.** 36 findings, no high. Patched (6 medium, 7 low): in-flight edits kept on a save's return, `SaveBridge` try/catch and the `BridgeCurrent` seam, `pageOf` case, removed dead code, a stale doc line, `TestSaveDemoModeAudited`, S1 demo-guide assertion, S7b (409), eleven `mutation:` lines. Deferred (2, in the frontmatter): `Data.Handled` purge (Story 18.4) and `SendDigest` to the disabled `Digest` item. Every rejected finding has its reason in the triage log.

**Follow-up review recommended: true.** Two or more medium findings were patched (5 entries: edits in flight, bridge try/catch, demo route test, 409 branch test, bridge seam). The unverified risk is the lane-b shard: `Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved` ("the production runs every item", DW-639) was red in 2 of 4 `shard lane-b --part 2/2` runs of this stage (green alone on a fresh and on the warm stack, and in the other two shard runs); whether the added `TestSaveDemoModeAudited` (a real Demo step with the stack's own mode, in `Test.Web.SettingsApi`, which runs after Heartbeat) or only timing changes its frequency was not measured.

**Verification.** Loop classes (11) green on the warm stack; `node --test web/scripts/` 1317 pass; `npm --prefix web run build`; after the last patch: `ci/iris.sh build`, `live sign-in --part 1/2` (138) and `--part 2/2` (126), `live demo-switch` (24, `z-settings-save` included), `live floor` (107), `live demo-path`, `live production`, `shard lane-b --part 1/2` and `2/2` (second part: red twice on the DW-639 flake, green on the third run), `shard lane-a --part 1/3`, `2/3`, `3/3`, `test-boundaries`, `test-class-rules`, `test-storage`, `test-ci-config`; `lint_spine.py` shows the 8 existing findings. Defects found by the browser units and fixed in-pass: the `/state` key list and home-link locator in `frame.spec.ts`, the busy-notice and saved-text locators (the live announcer repeats them), the current-page mark (a `box-shadow` replaced the focus halo) and links not underlined at rest in the header navigation.

**Residual risks.** DW-639 above. The new `settings.spec.ts` cases S7b and S1t ran only in the final sign-in run. `Test.Web.SettingsApi` and the bridge tests assert the Lane A stubs' answers by design and go red when Story 17.4 replaces them. Not run: `live online-*` units (they run in CI).
