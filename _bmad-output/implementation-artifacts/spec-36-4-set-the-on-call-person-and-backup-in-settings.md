---
title: 'Story 36.4: Set the on-call person and backup in Settings'
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-2-fix-lane-b-s-step-5-contracts-paging-escalation-and-the-sql.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 36.2 named the on-call keys and the `POST /api/v1/settings/on-call` route in the spine, but nothing writes or shows them, so Stories 23.4 (paging) and 24.3 (page delivery and escalation) have no on-call person to read. As built, a settings save would also put the contact values into a production message body, which holders of the trace role (non-admin accounts included) can read in Visual Trace. That breaks ruling V3 (DW-1249).

**Approach:** Add the admin-only On call section. On the server: a section of kind `oncall` in `SettingsOps` with its own validation, reusing `SaveProduct` for audit-then-write. A new forwarded REST class, `OcuTalon.Web.OnCallSettings`, hands the whole section body to `SettingsOps` through `SecretHandoff`, so no on-call value enters a command, a trace or a log. On the page: an `on-call-section.ts` component. Every text is accepted wording, except one proposed help line (DW-1250) that ships only once accepted.

## Boundaries & Constraints

**Always:**
- Judge each criterion against the delivered code and build only what is missing (Design Notes › Already met).
- `SettingsOps` is the only writer of the seven `oncall.*` keys. It validates every value before anything is written and writes through `SaveProduct`: each changed key's `Settings` audit entry (with from, to, the admin's IRIS user, the session Ref and channel web) and then its row, in one transaction.
- The REST route offers the request body to `SecretHandoff` before the submit and discards it on every path after it. `SaveSettings.Changes` is exactly `{"handoff":"secret://handoff/<name>"}`. No on-call value is ever in a command, a `CommandResult`, a log line (`$$$LOG*`, the console log), a trace or a notice. Refusals carry field names only, and the page renders each field's text.
- Online demo: the route answers 409 `not_available` with `settings.onCallOffOnDemo` before it reads the body or offers anything. `SettingsOps` answers `not_available` too (defence in depth). `GET /v1/settings` holds no `on-call` member, and the page hides the section.
- Ship only accepted texts, verbatim (EXPERIENCE.md › Message Catalog › "Settings (step 5)"). Strings go in `SETTINGS_TEXTS.onCall`, with `web/scripts/ux-strings.test.mjs` SOURCES entries.
- Every IRIS test runs on a lane-B throwaway (`ci/iris.sh`, `ci/warm.sh`), never on slot B. Tests save and restore the `oncall.*` rows they touch.

**Never:**
- No new table, persistent class, message class, role, grant or `ci/units.sh`, `.github/workflows` or `release/**` change. Do not widen `OcuTalonUser`.
- Do not page, email or message anyone. No `Data.Page` and no `Notify` or `EmailOut` change (Stories 23.4 and 24.3).
- Do not edit Lane A files, `Msg/Catalog/*.cls`, `README.md`, `GUIDE.md`, the More to try registry, `Core/SecretHandoff.cls` or `Test/Web/SettingsApi.cls`. In contended files make only the edits under Design Notes › Contended overlaps.
- Never put an on-call value into a `$$$LOG*` text, a status text or a field-error text that the server builds.

## I/O & Edge-Case Matrix

Body members (all JSON strings except the minutes): `primaryPerson`, `primaryUser`, `primaryEmail`, `primaryChannels`, the four `backup*` members, and `escalationMinutes`. A person is `nobody`, `user` or `email`. "Paired" means one of the user's sessions has a `Data.Pairing` row with that `SessionRef`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Nobody | person `nobody` (its user, email and channels are ignored) | stored `""`, `""`, `telegram,email` | none |
| User, paired | person `user`, user with a session and a pairing, channels `telegram,email`, email `a@x.io` | stored as sent; 200, "Saved. Applies within a minute. Recorded in the audit log." | none |
| User, unpaired | channels `telegram` or `telegram,email` | refused `<role>Channels`; nothing written or audited | page: `onCallNoChannel` on Page by |
| User, email only | unpaired, channels `email`, email set | saved | none |
| Unknown user | person `user`, a user with no session row (or "") | refused `<role>User` | page: `onCallUnknownUser` with {user}, on Person |
| By email | person `email`, valid address (trimmed, at most 254 characters, `SettingsOps.IsAddress`), channels `email` | user stored `""` | none |
| Bad or missing address | person `email` with "" or `nope`; or person `user` with a non-empty invalid address | refused `<role>Email` | page: `badEmail` |
| Unreachable channel | `email` chosen with no address; `telegram` for an address-only person; "" or `sms` or a repeat | refused `<role>Channels` | page: `onCallNoChannel` |
| Minutes | `1`, `1440`, `"15"` saved; `0`, `1441`, `15.5`, `"abc"`, "" refused | refused `escalationMinutes` | page: `onCallBadMinutes` |
| Shape | a missing or extra member, a person outside the three, `@{` in any value, a body that is not an object | 400 `bad_settings` naming the field (or `[]`) | page: form error "Couldn't save. Nothing was changed." |
| Nothing changed | the stored values again | 200 done; no row, no audit entry | none |
| Non-admin | `OcuTalonUser` only, GET or POST | 403 `not_admin`; nothing offered, submitted or changed | page: denied view |
| Online demo | flag `onlineDemo` 1, an admin's POST | 409 `not_available`, `settings.onCallOffOnDemo`; nothing offered, submitted, written or audited; GET has no `on-call` | page: hides the section; a 409 shows `onCallOffOnDemo` |
| Server failure | submit error, a throw, `not_audited`, `failed` | 500; handoff discarded | page: "Couldn't save. Nothing was changed." |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- the only writer.
  - `ALLOWLIST` L100.
  - `AuditData` L222, `Stored` L236, `WriteAudit` L243, `Apply` L250.
  - `HasSession` L681, `OnlineDemo` L692 (Setting.Get("onlineDemo")).
  - `XData Sections` L872-901 (the `channels` row L891-900 ends the array).
  - `Values` L928: the kind skip L933, `channels` L950.
  - `Save` L995: the dispatch lines after `models` and `email`, before the generic Field loop.
  - `Refused` L1028, `Field` L1038 (`int` with min/max; reuse it for the minutes), `SaveProduct` L1082: the diff against `Stored`/default, then audit then `Apply` in one TSTART, the transaction to reuse.
  - `IsAddress` L1845, `TakeSecret` L2281 (HANDOFFWAIT 2 s). The class ends at L2301; append the new methods there.
- `src/ocutalon/cls/OcuTalon/Web/HookSettings.cls` -- the template for `Web.OnCallSettings`: extends `Web.Api`, its own `XData UrlMap` (`Url=""`), `Refusal()` (403 then 409 before the body), and SecretHandoff `Put` with `Discard` on every path.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `<Map ...HookSettings/>` L291 (append the on-call Map after it); class comment L107-108; `IsSettingsUrl` L348 already covers `/v1/settings/on-call` (403 not_admin).
  - Inherited Private helpers: `SettingsBody` L1103, `BadSettings` L1097, `Answer` L1068 (its `not_available` branch has the EMAIL text, so the subclass maps `not_available` itself) and `ServerError` L366.
  - `MESSAGENOTADMIN` L186.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls` -- `Put(secret, .uri)` (any non-empty string), `Take(uri, .secret, timeoutSec)`, `Discard(uri)` L76. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls` -- `IrisUser` with `IrisUserIndex` L76 (eval rows have no IrisUser). `Data/Pairing.cls` -- `SessionRefIndex` L58 (a chat row has a SessionRef only while paired).
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:78` `Record` -- blanks from/to only for `Redact.SensitiveKey` settings. `oncall.*` keys are not sensitive (`Redact.cls:34`), so addresses and user names stay in the entry, as V3 wants.
- Web:
  - `web/src/app/settings/settings-view.ts`: `SETTINGS_TEXTS.sections` L32-41, the `webhooks` block L77-86 (append `onCall` after it), `SETTINGS_SECTIONS` L128-136, `sectionSlug` L139, `refusalKind`/`firstInError` L247-260.
  - `settings-page.ts`: imports L14-21, `@switch` L60-101, `sections` L203, `keep*` L283-315.
  - `check-thresholds-section.ts`: the field, error, focus and announce pattern to copy.
  - `refusal.ts`: `refusalOf`.
  - `api/api-client.ts:66` `saveSettings(section, values)` is reused unchanged. `api/api-types.ts:228` `SettingsSections`.
- Tests to extend:
  - `Test/Core/SettingsSave.cls:431`: TestValues' section list.
  - `Test/Core/SettingsOpsProbe.cls`: the audit recording seam ("record" for real entries).
  - `Test/Core/SettingsWebhooks.cls`: the probe and onlineDemo flag pattern.
  - `Test/Web/HookSettingsApi.cls` + `HookSettingsProbe.cls` (29 lines): the REST test pattern.
  - `Test/Web/SettingsApi.cls:260` `TestSaveThresholds`: through the production, `Test.Bridge.AuditLog.Now/Wait`, cache expiry.
  - `Test/Core/SecretHandoff.cls:177` `Leaks(text)` (^OcuTalon* globals). `Test/Web/WebhookTools.cls` `Columns(table)`.
  - `web/e2e/api/webhooks.spec.ts` (real-HTTP pattern: `README_ACCOUNT`, `signInOverHttp`, `irisScript`, `chk`, `quoted`, `fixtureUser`).
  - `web/e2e/settings/settings.spec.ts` S1 L63-90 (the nav list).
  - `web/scripts/settings-view.test.mjs:59-69`, `settings-refusal-sources.test.mjs:21` (`SAVING`), `announce-focus-sources.test.mjs:120-165`, `ux-strings.test.mjs` (SOURCES `ux` near L197-330).
- Message bodies share the `Ens.MessageBody` extent (`SaveSettings` storage subscript `"SaveSettings"`), so a scan of `^OcuTalon*` alone never sees them. Scan the tables `OcuTalon_Msg_Command.SaveSettings`, `OcuTalon_Msg.CommandResult` and `OcuTalon_Msg.Notification`.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
  - AD-19 on-call keys L721-728, step 5 sections L729-732, "Saving a settings section" L720.
  - SecretHandoff ownership row L1510.
  - REST table L1666-1696.
  - Trace role holds `%Ens_MessageContent` L952-956; non-admin accounts hold it, L972.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - `ALLOWLIST`: append the seven `oncall.*` keys.
  - `XData Sections`: append the row `{"slug": "on-call", "kind": "oncall", "fields": [...]}` with seven keyed fields. Six have `default` "" or `telegram,email`; `escalationMinutes` is `"type": "int", "min": 1, "max": 1440, "default": "15"`.
  - `Save`: add `If section.kind = "oncall" Quit ..SaveOnCall(command, changes)` after the email line.
  - `Values`: skip kind `oncall` in L933. After L950 add `If '..OnlineDemo() Do sections.%Set("on-call", ..OnCallValues())`.
  - Append these methods:
    - `SaveOnCall`, in this order: not_available on the demo (`MESSAGEONCALLOFF`, the accepted text) after a discard of the handoff; changes exactly `{handoff}` else `Refused([])`; `TakeSecret`, failed on error; parse the body; validate as in the I/O matrix (the minutes through `Field`); build `to()`; `Quit ..SaveProduct(command, section, .to)`.
    - `OnCallValues()`: the seven stored values (minutes as a number), `users` [{user, paired}] (distinct non-empty `Data.Session.IrisUser`, sorted), and `pagesBuilt` (`OcuTalon.Data.Page` compiled).
  - Add one paragraph at the end of the class description.
  - Never log a value.
- `src/ocutalon/cls/OcuTalon/Web/OnCallSettings.cls` -- NEW, extends `Web.Api`, UrlMap `<Route Url="" Method="POST" Call="Save"/>`. `Save`:
  - a non-admin gets 403 `not_admin`; the demo gets 409 `not_available` with `SettingsOps.#MESSAGEONCALLOFF`, both before the body;
  - a body that is not an object gets 400 [];
  - `Put(body.%ToJSON())`, then a `SaveSettings` (slug `on-call`, Changes `{"handoff": uri}`, ActingUser `$USERNAME`, the CSP session's Ref) through a `Submit` seam with origin `web_admin`;
  - `Discard(uri)` after it, on every path;
  - outcome `not_available` gets 409 as above; every other outcome goes to `Answer(result, "")`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- append `<Map Prefix="/v1/settings/on-call" Forward="OcuTalon.Web.OnCallSettings"/>` after L291, and one line in the class comment after L108. `TestRoutes` stays 38, because it counts Route elements only.
- `web/src/app/api/api-types.ts` -- `OnCallValues` and `'on-call'?: OnCallValues` in `SettingsSections`.
- `web/src/app/settings/settings-view.ts`:
  - `sections.onCall: 'On call'`;
  - the `onCall` block of every accepted On call text, keyed as EXPERIENCE.md names them, with `offOnDemo` and, only if accepted, `byEmailHelp`;
  - `{ slug: 'on-call', label }` in `SETTINGS_SECTIONS` after `check-thresholds`;
  - the header comment updated.
- `web/src/app/settings/on-call-view.ts` -- NEW, framework-free rules: `ONCALL_FIELDS` (form order: primaryUser, primaryEmail, primaryChannels, backupUser, backupEmail, backupChannels, escalationMinutes), `personOf(user, email)`, `onCallFormOf(values)`, `onCallBody(form)`, `isOnCallDirty`, `telegramState(person, user, users)` (`enabled`, or `unpaired` with the filled text, or `emailOnly`), `defaultChannels(person, paired)`, `fieldErrorText(name, form)`, and `personOptions(users, storedUser)` (a stored user with no session row stays listed).
- `web/src/app/settings/on-call-section.ts` -- NEW, built like `check-thresholds-section.ts`:
  - help, plus `onCallNotYet` while `!pagesBuilt`;
  - two `fieldset`/`legend` groups ("On-call person", "Backup"), each with a labelled Person select (Nobody, the users, "Someone else, by email"), the "Email address for pages" field (hidden for Nobody) and "Page by" checkboxes "Telegram" and "Email" (hidden for Nobody). A Telegram option that can't be chosen is disabled and described by its text;
  - the minutes field with `onCallMinutesHelp`;
  - Save changes via `ServerButton` and `saveSettings('on-call', ...)`;
  - 200 shows and announces "saved"; a 400 marks each named field with its text and focuses the first in `ONCALL_FIELDS` order; a 403 goes to `denied`; a 409 shows `offOnDemo` in place of the form; anything else shows "failed" under the button;
  - `dirtyChange`, `saved` and `denied` outputs.
- `web/src/app/settings/settings-page.ts`:
  - import and `@case ('on-call')`;
  - `sections` computed without `on-call` when GET has no `sections['on-call']`, and an `on-call` address then opens Models;
  - `onCall` computed and `keepOnCall`.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOnCall.cls` -- NEW, on the `SettingsOpsProbe` with a real `SecretHandoff` uri. Every I/O matrix row at the `SettingsOps` level, among them:
  - `TestTelegramNeedsAPairedChat`;
  - `TestRefusals` (each refused field named, nothing written or audited);
  - `TestSaveAuditsEachChangeWithItsValues`;
  - `TestNothingChanged`;
  - `TestOnlineDemo` (not_available; handoff gone; Values has no on-call);
  - `TestHandoffMissing`;
  - `TestValues` (shape, defaults, users and paired, pagesBuilt);
  - `TestTextOffOnDemo` (the parameter verbatim).
  Fixture sessions, pairings and rows are removed afterwards.
- `src/ocutalon/cls/OcuTalon/Test/Web/OnCallSettingsProbe.cls` -- NEW (the roles seam and a `Submit` seam, as `HookSettingsProbe`). `src/ocutalon/cls/OcuTalon/Test/Web/OnCallSettingsApi.cls` -- NEW:
  - `TestMapAndRoute` (the Api Map line, the class's one route);
  - `TestNonAdmin403`;
  - `TestOnlineDemoRefusesFirst` (409, the text, no Put or submit);
  - `TestBadBody`;
  - `TestSubmitFailsOrThrows` (500, uri discarded);
  - `TestCommandHoldsOnlyTheHandoff`;
  - **`TestValuesOnlyInTheAuditLog`**, the one V3 leak scan (DW-1249). An admin's save of unique `zz` addresses and a fixture user name goes through the real production. Then:
    - the event log rows since the mark, the `SaveSettings`, `CommandResult` and `Notification` tables (`WebhookTools.Columns`) and `Ens.MessageHeader` hold neither address nor the user name;
    - `Test.Core.SecretHandoff.Leaks(address)` is exactly `OcuTalonP.SettingD`;
    - positive control: the IRIS audit entries since the mark hold both addresses and the user name as from/to.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsSave.cls:431` -- expected `daily-digest,check-thresholds,demo-mode,channels,on-call`.
- `web/scripts/on-call-view.test.mjs` -- NEW, the view rules and every `onCall` text verbatim. `settings-view.test.mjs:59-69` -- eight sections, On call after Check thresholds. `settings-refusal-sources.test.mjs` -- append `on-call` to `SAVING`. `announce-focus-sources.test.mjs` -- add `app/settings/on-call-section.ts` to the speakers and to the focus counts (1, "the first field in error takes focus after the user's own Save changes (Story 36.4)"). `ux-strings.test.mjs` -- the on-call strings under `ux` (Decided 7).
- `web/e2e/settings/settings.spec.ts` S1 -- eight links with "On call" after "Check thresholds", the title "eight sections", and `['on-call', 'On call']` in the slug loop.
- `web/e2e/settings/on-call.spec.ts` -- NEW, serial, restores the keys in `afterAll`:
  - O1: the nav, the heading, the help and not-yet lines, the legends, and every control reachable by label and keyboard;
  - O2: choose the README admin (unpaired: Telegram disabled with the filled text) and a by-email backup, with minutes 20. Save shows the saved text; GET and the audit entries (the admin's user and session) match;
  - O3: correct and save again. A bad address plus minutes `0` marks both fields, focuses the address, and changes nothing; fixing both and saving again gives the new values and only the new audit entries;
  - O4: the unsaved prompt (Stay keeps, Leave discards);
  - O5: a routed 500 shows the failed text.
- `web/e2e/api/on-call.spec.ts` -- NEW, real HTTP:
  - H1: the LIVE `OcuTalonUser` gets 403 `not_admin` on GET `/settings` and POST `/settings/on-call`; the rows are unchanged and no new Settings entry names it;
  - H2: the README admin gets 200, `sections['on-call']`, `Data.Setting.Get("oncall.*")` in a fresh `irisScript` process (the 23.4/24.3 read path), and audit entries with from/to, the admin and the session;
  - H3: a bad address is 400 `bad_settings` `["primaryEmail"]`, with nothing changed. The rows are restored in `finally`.
- Spine (Rule 20; only once the runner reports S1's ruling, else unchanged):
  - AD-19 on-call keys gets one bullet on the hand-off and the body members;
  - REST table: one row for `POST /api/v1/settings/on-call`;
  - L1510 gets "and `Web.OnCallSettings` (Story 36.4)";
  - then `memlog.py append`, `lint_spine.py` (`"ok": true` or only the pre-existing DW-351 placeholders), and refresh `updated:`.
- Only if the runner reports `settings.onCallByEmailHelp` accepted: show it under the on-call person's Person select while "Someone else, by email" is chosen, add its SOURCES entry, and append its row to EXPERIENCE.md "Settings (step 5)" with an [ADDED] marker. Otherwise ship nothing, and DW-1250 stays with the runner.

**Acceptance Criteria:**
- AC1. Given an admin opens On call, when they choose the on-call person and the backup, then:
  - each is Nobody, an OcuTalon user or an email address;
  - Page by defaults to Telegram and Email;
  - Telegram can be chosen only for a user whose session is paired, and is otherwise disabled with `onCallTelegramUnpaired` or `onCallTelegramEmailOnly`, and the server refuses it;
  - the minutes default to 15, and `onCallNotYet` shows while `Data.Page` isn't compiled.
- AC2. Given changed values, when the admin presses Save changes, then only this section is saved with "Saved. Applies within a minute. Recorded in the audit log.", and leaving with unsaved changes asks first.
- AC3. (Integration, consumer `Data.Setting.Get`, the read path of 23.4 and 24.3.) Given a saved change, when a fresh process reads `Data.Setting.Get("oncall.*")`, then it returns the new values, `SettingsOps` was the only writer, and each changed key has an IRIS audit entry with from, to, the admin's IRIS user and session.
- AC4. Given an invalid address or minutes that aren't a whole number from 1 to 1440, when the admin saves, then each field shows its accepted error, focus moves to the first in form order, and nothing is saved. A server failure shows "Couldn't save. Nothing was changed."
- AC5. Given a user without OcuTalonAdmin, when they call GET `/v1/settings` or POST `/v1/settings/on-call`, then 403 `not_admin` and nothing changes. Given the online demo, then the POST is 409 `not_available` with `settings.onCallOffOnDemo` before anything is read, nothing is written, and the section is absent from the GET and the page.
- AC6. Given `OcuTalon.Test.Core.SettingsOnCall` and `web/e2e/settings/on-call.spec.ts`, when an admin saves, corrects and saves again, then the stored values, the audit entries and the page states match, and every control is labelled and keyboard-operable.
- AC7. (V3, DW-1249.) Given a saved on-call change, when the leak scan runs, then the addresses and the user name are in the IRIS audit entries and in no message body, trace header, event log row, notice or `^OcuTalon*` global except `OcuTalonP.SettingD`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Ledger inbox (Rule 17):** `owned_ledger=2`.
- DW-1249 is addressed by the hand-off task, `TestValuesOnlyInTheAuditLog`, AC7 and veto item S1.
- DW-1250 is addressed by the conditional help-line task and proposed text P1.

### Governing ADs (Rule 6)
| AD | Here |
| --- | --- |
| AD-1 | The save is one `SaveSettings` through `Commands.Submit` and `CommandsIn` |
| AD-4 | `SessionRef` from the CSP session, never the body |
| AD-12 | The page decides nothing; the server validates and names fields |
| AD-13, AD-24 | Admin-only through `OnPreDispatch`; no role, no grant |
| AD-14 | Telegram only to a paired chat; email never acknowledges (DW-1250) |
| AD-17 | One audit writer, `Bridge.Audit.Record` |
| AD-19 | The on-call keys, section kind `oncall`, `SettingsOps` the only writer, the V3 rule, the SecretHandoff hand-off |
| AD-29, AD-33 | Lane B files only; the ownership row |

No criterion contradicts an AD's Rule. The hand-off refines AD-19's "Saving a settings section" (Changes stays one JSON object), with the spine bullet pending veto item S2.

### Already met (no new work)
- 403 on every `/v1/settings` URL for non-admins (`Web/Api.cls:313,348`); online-demo accounts hold no admin role (`Install/Step/Users.cls:46`).
- Audit entries with user, session and channel (`SettingsOps.AuditData` L222 in `SaveProduct` L1082).
- `Setting.Get` caches for 60 s (`Data/Setting.cls:8,39`).
- "Save changes", the saved and failed texts and the unsaved dialog (`settings-view.ts:42-50`); the unsaved guard (`unsaved-guard.ts:20`, `settings-page.ts` `dirty`).
- `IsAddress` (L1845) and `SecretHandoff` exist.
- Every On call text is accepted and already in EXPERIENCE.md (written by 36.2).

### Integration ACs, Consumed-by, Consumes (Rules 1, 2)
- In-story Integration AC: AC3 (`Data.Setting.Get` in a fresh process, through H2).
- Consumed-by:
  - 23.4 reads `oncall.*.user` and `oncall.*.channels` and `oncall.escalationMinutes` to page.
  - 24.3: `EmailOut` reads `oncall.*.email` at send time, and the escalation timer uses the minutes.
  - 24.2 reuses the `OnCallSettings` hand-off for partner contacts (DW-1249 names the same exposure there).
- Consumes:
  - 36.2's AD-19 keys and route;
  - `SecretHandoff` (21.2, 35.3);
  - `SaveProduct`, `AuditData` and `Field` (33.2);
  - `Data.Session` and `Data.Pairing`;
  - `Bridge.Audit`.

### Extend, don't copy (Rule 2)
- `SaveOnCall` validates the section, then reuses `SaveProduct`, with `Field` for the minutes and `IsAddress` for addresses.
- `Web.OnCallSettings` follows `Web.HookSettings`, which is the same shape: a forwarded class, a refusal before the body, and Put/Discard. It inherits `SettingsBody`, `BadSettings`, `Answer` and `ServerError`.
- The section copies `check-thresholds-section.ts`'s field, error and focus pattern, and uses `refusalOf` and `firstInError`.
- `OnCallSettingsProbe` repeats `HookSettingsProbe`'s two-method roles seam, because a probe must subclass the class it stands in for.
- The leak scan reuses `Leaks`, `WebhookTools.Columns` and `Test.Bridge.AuditLog`.

### Decided in-stage
1. **A forwarded Map and a new class instead of a Route in `Api.cls`.** This keeps `Api.cls` to one appended line. `TestRoutes` stays 38, not the 39 the epic context guessed.
2. **The body names each person's kind** (`primaryPerson`, `backupPerson`). Without it, "Someone else, by email" with an empty address could not be told apart from Nobody (AD-12).
3. **Nobody** stores `""`, `""` and `telegram,email`.
4. **Addresses** are trimmed and checked by `IsAddress`, up to 254 characters.
5. **The same person may be in both roles, and a backup may be set without an on-call person.** Paging rules are 23.4's and 24.3's.
6. **"On call" sits after Check thresholds,** so Demo mode stays last.
7. **The SOURCES entries go under `ux`, not `ruled`.** The runner's wording said `ruled`, but `ux-strings.test.mjs`'s "names the UX first" check fails a `ruled` entry for a slotless string that EXPERIENCE.md already holds, and 36.2 put these texts there.
8. **Hidden on the online demo** because GET has no `on-call` member. The `#/settings/on-call` address then opens Models.
9. **A stored user who has lost their session row stays in the Person list,** so the form shows what is stored; saving then gets `onCallUnknownUser`.
10. **The off-on-demo text** is `SettingsOps.MESSAGEONCALLOFF`, read by the route, with a web copy in `SETTINGS_TEXTS.onCall.offOnDemo`. Both are pinned verbatim.
11. **Users** are listed sorted and deduplicated. A user counts as paired when any of their sessions is.
12. **The one leak-scan test is an IRIS class** that saves through the real production, so it can run warm. The Playwright API spec carries the real-HTTP 403, success and read-path checks.
13. **Real-HTTP isolation (iii) does not apply.** The on-call choice is instance-wide configuration with no owner, and H1 shows a user can't read it.
14. **The `settings.spec.ts` S1 edit is left to CI.** Its file alone runs over the per-call size (about 93 s of setup plus about 35 tests), so CI's `shards-4` (`live:sign-in-2`) checks it; locally, `npm --prefix web run lint` covers it.
15. **`new_units: none`.** The new IRIS classes join existing areas: Core runs in `lane-b@Contract,Core,Data,Live` in the `image` group, and Web in `lane-b@rest` in `shards-6`. `settings/on-call.spec.ts` is in project sign-in-2 (`live:sign-in-2`, `shards-4`), `api/on-call.spec.ts` in chromium (`live:sign-in`, `shards-10`), and the node tests run in the hosted web job.
16. **Findability: no More to try item and no GUIDE.md line.** On a local install the section is already findable in the Settings nav, and its own `onCallNotYet` line says that it sends no page yet. A try-it item would lead a judge to a choice that does nothing they can see. The item and the line belong to the first story that sends a page (23.4 or 24.3). No new text is proposed for this.

### Contended overlaps
| File | 36.4's edit | Kind |
| --- | --- | --- |
| `Core/SettingsOps.cls` (Epic 21: `Field` channels branch, email methods, description L79-87) | `ALLOWLIST` tail; one XData row (a comma after the `channels` row); one dispatch line in `Save`; the L933 condition and one line after L950 in `Values`; a description paragraph after L95; methods at the end | Non-append edits: the ALLOWLIST line, L933 and the channels-row comma. The rest is appended. |
| `web/src/app/settings/settings-view.ts` (Epic 21: `dailyDigest.email`, DIGEST_CHANNELS, `digestChannelBoxes`) | `sections.onCall`, an `onCall` block after `webhooks`, one `SETTINGS_SECTIONS` line, the header comment | Inserted lines away from Epic 21's hunks |
| `web/src/app/settings/settings-page.ts` (Epic 21: import line L20, `[emailShown]`, `emailShown`) | imports, one `@case`, `sections` and `active` computed, `keepOnCall` | Non-append edits: the `sections` field L203 and the `@switch` |
| `web/scripts/settings-view.test.mjs` (Epic 21: imports and the digest tests) | the "sections" test L59-69 | Non-append, in another hunk |
| `Test/Core/SettingsSave.cls` (Epic 21: `TestDigestSection` only) | one expected string L431 | Non-append, one line |
| `Web/Api.cls` (no other epic's diff) | one Map line, one comment line | Appended |
| Spine, EXPERIENCE.md (36.1, Epic 21) | AD-19 bullet, REST row, L1510 words; an EXPERIENCE row only if P1 is accepted | Appended |
| `README.md`, `GUIDE.md`, `Msg/Catalog/Core.cls`, `Test/Core/Routing.cls`, `Test/Web/SettingsApi.cls`, `Data/BackgroundCheck.cls` (Epics 21, 22) | Nothing | — |

### Veto and security items (pending the Planner's ruling; the runner sends them before any implement spawn)
- **S1 (DW-1249): on-call values in a traced message.**
  - Today every settings save carries its values in `SaveSettings.Changes`. Visual Trace's Contents tab shows that to `OcuTalonTraceViewer`, which the online demo's read-only and visitor accounts hold (spine L952-956, L972). So the trace is not admin-only, and V3's "no trace" fails as built.
  - (a) Blank the values in the stored message after the save. This rewrites a persisted message body, and there is still a window when the values are visible.
  - (b) **Recommended:** carry the whole section body out of band through `SecretHandoff`, which is in memory only, with `Changes` = `{"handoff": uri}`. This needs no schema change and follows 21.2's and 35.3's precedent; one leak-scan test proves it.
  - (c) Narrow V3 to accept the trace as admin-only. Its premise is false (see above), and it would weaken a ruled guarantee.
  - Online demo: 409 before the body is read; nothing is offered, submitted or written.
  - This spec implements (b). A ruling of (a) or (c) changes the route's and the test's design, so the runner then resets this spec to `draft` for a re-plan.
- **S2: an AD-19 amendment (Rule 20).** One bullet: the on-call route hands the section body to `SettingsOps` through `SecretHandoff`, so `SaveSettings.Changes` holds only the reference. `SecretHandoff` would then also carry non-secret contact data (in memory, taken once, then deleted). This is written only after S1 is ruled.
- **Already ruled, no new item:**
  - the admin-only user list with its paired flags (V4);
  - the stored keys, no purge and the demo never writing (V2);
  - the route and 409 behaviour (V1);
  - the audit with from/to values (V3).

### Proposed public text (verbatim; none ships until accepted)
- P1 (DW-1250), `settings.onCallByEmailHelp`. It shows under the on-call person's Person select while "Someone else, by email" is chosen: "Someone paged by email can't press Got it, so OcuTalon also pages the backup after the minutes below."
  - Why: email never acknowledges (AD-14; `AckPage` origins are `web_user`, `web_admin` and `telegram`). An OcuTalon user can still press Got it on their web chat copy, so the line is needed only for an address-only on-call person. A backup has no further escalation, so it gets no line.
  - Recommended over declining, because the accepted `onCallHelp` implies that someone could press Got it in time.

### For Story 24.2 (input, not this story's work)
- Partner contacts need the same hand-off. Extend `Web.OnCallSettings` (or generalise it to a shared settings hand-off) instead of copying it, and add a second leak-scan test as V3 says.

## Verification

Every live command uses `<lane-b vars>` = `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'`. The fresh tag is `e36s4i` and the warm tag `e36s4iw`.
- Run one command per call, with `timeout: 600000`, each at most about 150 s, never on slot B, and never two test calls in one message.
- `<scratch>` is the implement stage's own scratch folder, never a tracked path.
- At the end, even after a failure, run `<lane-b vars> OCUTALON_RUN_TAG=e36s4iw bash ci/warm.sh down` and `<lane-b vars> OCUTALON_RUN_TAG=e36s4i bash ci/iris.sh teardown`.

**Commands:**
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s4iw bash ci/warm.sh up`, once per stage -- expected: a ready stack.
- (loop) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s4iw bash ci/iris.sh class <C>`, one call each for `OcuTalon.Test.Core.SettingsOnCall`, `OcuTalon.Test.Web.OnCallSettingsApi`, `OcuTalon.Test.Core.SettingsSave` and `OcuTalon.Test.Web.Api` -- expected: `CLASS ... passed`.
- (loop) `node --test web/scripts/on-call-view.test.mjs`, then the same for `settings-view.test.mjs`, `settings-refusal-sources.test.mjs`, `announce-focus-sources.test.mjs` and `ux-strings.test.mjs`, one call each -- expected: pass.
- (loop) `npm --prefix web run lint` -- expected: pass.
- (once) `npm --prefix web run build` -- expected: pass. Then `<lane-b vars> OCUTALON_RUN_TAG=e36s4i bash ci/iris.sh build` before any browser unit (Rule 21, rebuild the bundle).
- (once) Find the part that holds only the new spec, with no stack: `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json > <scratch>/l2.json`, then `node web/scripts/e2e-part.mjs k/n <scratch>/l2.json`, trying k/n until the PART line names only `settings/on-call.spec.ts`. Do the same with `e2e` for `api/on-call.spec.ts`.
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s4i bash ci/iris.sh live sign-in-2 --part k/n` (that part) -- expected: pass.
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s4i bash ci/iris.sh live sign-in --part k/n` (that part) -- expected: pass.
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s4iw bash ci/iris.sh shard lane-b@Core --part k/4` for k = 1..4, then `shard lane-b@Web --part k/4` for k = 1..4, one call each -- expected: all passed. A part over about 120 s means re-running that piece with a larger n. The known pre-existing `Test.Core.SettingsOps` `TestOnlyRunTimeWriter` failure on 36.1's tables (36.2 deferred) is not this story's red.
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s4i bash ci/iris.sh class OcuTalon.Test.Core.SettingsOnCall`, then the same for `OcuTalon.Test.Web.OnCallSettingsApi`, each on a fresh stack -- expected: passed.
- (once) `npm --prefix web test` and `bash docker/tests/test-ci-config.sh` -- expected: pass (no `ci/units.sh` change).
- (once) Only if S2 is written: `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no finding beyond DW-351's placeholders.

**Shared surfaces:**
- `SettingsOps` `XData Sections` and `ALLOWLIST` (`TestAllowList` is generic).
- The GET body's sections (`SettingsSave.TestValues` L431).
- The settings nav count and order (`settings-view.test.mjs`, `settings.spec.ts` S1).
- `Api` UrlMap (Maps are not counted by `TestRoutes`).
- `SETTINGS_TEXTS` and `ux-strings.test.mjs` SOURCES.
- `settings-refusal-sources` `SAVING`, and the `announce-focus-sources` speakers and focus counts.
- The instance-wide `oncall.*` rows: every test saves and restores them, and the on-call specs run serially.
- No More to try registry change.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; one per AC; the implement stage records each as `mutation: <change> → <red test>`):**
- AC1: accept `telegram` for an unpaired user in `SaveOnCall` → `SettingsOnCall.TestTelegramNeedsAPairedChat`.
- AC2: `on-call-section.ts` never emits `dirtyChange(true)` → `on-call.spec.ts` O4.
- AC3: drop the `oncall.backup.email` field from the XData row → `SettingsOnCall.TestSaveAuditsEachChangeWithItsValues` (and H2).
- AC4: set the minutes field's `min` to 0 → `SettingsOnCall.TestRefusals`.
- AC5: remove the online-demo check from `OnCallSettings.Save` → `OnCallSettingsApi.TestOnlineDemoRefusesFirst`.
- AC6: drop the minutes input's label `for` → `on-call.spec.ts` O1.
- AC7: put the request body into `Changes` instead of the hand-off → `OnCallSettingsApi.TestValuesOnlyInTheAuditLog`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
