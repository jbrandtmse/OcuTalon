---
title: 'Story 24.4a: Show setting values redacted everywhere, and the setting change in the evidence panel'
type: 'feature'
created: '2026-11-15'
status: 'done'
baseline_revision: 'c42de191d8f4d04912696a79c6503575237156c1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Lane A's Stories 23.2, 23.3 and 23.5 are merged, and with them most of the step-5 display (Design Notes, "Ground truth"). [AMENDED 2026-11-15, re-plan narrowed to 24.4a] Two parts are this story's:
- The evidence panel never lists the setting change that an incident names (AC3).
- [AMENDED 2026-11-15, redactor ruling] A setting's values reach people raw. The rollback and undo dry run (card, phone, Telegram, web chat), their result notices and the incident's setting change carry the value exactly as IRIS holds it, so a setting whose value holds a secret (a URL with a token) shows it everywhere. Two Ens message bodies carry the raw values into the trace: `Fix.Msg.DryRunResult.DryRun` and the notices' `Msg.Notification.Slots` (Design Notes, "Trace and logs").

[AMENDED 2026-11-15, re-plan narrowed to 24.4a] The closed-card undo and the cross-surface pins of the step-5 kinds are Story 24.4b's (Design Notes, "Moved to Story 24.4b").

**Approach:**
- Add the setting-change rows to the evidence panel.
- [AMENDED 2026-11-15, redactor ruling] Redact on the SERVER with the one redactor, `OcuTalon.Bridge.Redact.Text`, wherever a setting's before, after, old or new value is shown: the approval payload's dry run, the incident payload's `settingChange`, and the slot fill of the four notice keys. The dry-run answer carries the redacted values and a hand-off reference to the raw ones, never the raw values. The stored dry run and the value the rollback writes stay raw. `Redact.Text` gains the one missing common secret shape (`key=`). No web redactor.
- [AMENDED 2026-11-15, re-plan rulings, V5 conditions] IncidentManager takes the hand-off reference once, on receipt; a taken entry is deleted, and an entry nobody takes expires.
- [AMENDED 2026-11-15, re-plan narrowed to 24.4a] Pin every AC on its outermost surface: one Playwright spec for the redacted and plain values on the web card, the panel and the phone page; one Telegram method on the CI mock; production tests for the raw restore, the trace and the System Default undo; unit pins for the rest.
- No payload field, route, catalog key, table, column or message property changes.

## Boundaries & Constraints

**Always:**
- The page decides nothing (AD-12). The card reads only the payload's fields (`settingChange`, `gapMinutes`) and renders text by interpolation only.
- Item names, setting names and values appear as the server sends them, in `mono`, in the evidence panel only (UX-DR78).
- The phone and Telegram text is the server's catalog text (AD-32). This story changes no catalog entry.
- Every new fixed string is in `INCIDENT_TEXTS` and in `ux-strings.test.mjs` with its ruling. Code uses ASCII escapes for any non-ASCII character (Rule 14).
- [AMENDED 2026-11-15, redactor ruling] Every setting value a person can see, and every Ens message body or log line that holds one, has gone through `OcuTalon.Bridge.Redact.Text` on the server. The stored `ApprovalRequest.DryRun`, the `SettingChange` row and the value the rollback or undo writes stay raw, byte for byte.
- [AMENDED 2026-11-15, re-plan rulings, V5] A raw value taken from the hand-off lives in local variables only: it is never set onto a message object or saved anywhere but the request row's `DryRun`.
- Test fixtures build every secret-shaped value from fragments (no key-like string in a file). Tests seed fixture rows (`seedApproval`, `seedIncident`, `seedSettingChange`, `publishIncident`, `sendNotification`) and remove them, and the phone messages they made, in `finally`; every hand-off entry a test offers is taken or discarded. They run on lane-D throwaways only.

**Never:**
- [AMENDED 2026-11-15, re-plan narrowed to 24.4a] No edit of a Lane A or bridge file beyond those the redactor ruling grants (`Live/Payload/Incident.cls` `Change`, the slot fill in `Watch/SettingCause.cls`, `Bridge/Redact.cls` for the pattern, and their test classes) and those V5 grants (`Fix/Executor.cls`, `Watch/IncidentManager.cls`, `Fix/Msg/DryRunResult.cls` doc only, the `Test/Watch/Rollback.cls` helper). `Core/SecretHandoff.cls`, `Channel/Telegram/*`, `Msg/Catalog/Watch.cls`, `Watch/Notice.cls` and the kind classes stay unedited. The Rule 19 mutations are applied and reverted byte-identical and never land.
- [AMENDED 2026-11-15, redactor ruling] No second redactor, in the web or anywhere else, and no redaction of the stored dry run, the `SettingChange` row or the value written.
- No new `/api/v1` route, live-event type, payload field, catalog key, table, column, message property or dependency.
- No values of a secret (`credential` true). No name of who made a change.
- [AMENDED 2026-11-15, re-plan narrowed to 24.4a] No change to the incident's state or lifecycle, to the compact card, or to which request cards a card draws (Story 24.4b); A9 stays as it is.
- No edit of `irislib/`, `irissys/`, `_bmad/`, `.claude/`, `CLAUDE.md` or a done story's spec.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Panel lists the change | incident with `settingChange` {item OrdersFromPartner, setting TargetConfigName, oldValue OrdersRouter, newValue OrdersRouterNew, detectedAt 14:08Z}, Show details open | after the Cause row: "Setting change" / "TargetConfigName on OrdersFromPartner" (mono), "Old value" / "OrdersRouter" (mono), "New value" / "OrdersRouterNew" (mono), "Detected" / the page time with its day | No error expected |
| Secret change | `credential` true, blank values | "Setting change" and "Detected" rows only, with no value rows | Values never shown |
| Empty value | `oldValue` "" (the setting was added) | the "Old value" row is left out; "New value" shows | Row omitted |
| No change named | no `settingChange`, or no setting or item in it | no new rows; the panel is as today | Nothing added |
| [AMENDED] Token-bearing value | a non-secret change whose `OldValue` is `https://feed.example.test/orders?token=<t>` | the payload's `oldValue`, the "Old value" row, the rollback card's After, the notices' `{after}` (web chat, phone, Telegram) all read `https://feed.example.test/orders?token=[redacted]`; `<t>` appears nowhere a person, the trace or a log sees | Redact fails closed (its UNCHECKED text) |
| [AMENDED] Plain value | `OrdersRouter` | shown byte for byte on every surface | No error expected |
| [AMENDED] Rollback of a token-bearing value | approved `rollback_setting` of that change | the item's setting is the raw token URL again, byte for byte; the stored dry run holds the raw values; every view is redacted | A failed hand-off take is a dry run that could not be worked out: nothing is raised, nothing stored redacted |
| [AMENDED 2026-11-15, re-plan, V5 condition 1] Hand-off taken | IncidentManager receives a setting kind's dry-run answer | it takes the entry on receipt, before any early exit; the entry is gone (a second take fails) | Take fails: the could-not-be-worked-out route of that path |
| [AMENDED 2026-11-15, re-plan, V5 condition 1; V6] Hand-off never taken | an answer that never reaches IncidentManager (a chat ask that timed out, a stopped production) | the entry is discarded `VALUESSECONDS` after the offer | No error expected |
| [AMENDED 2026-11-15, re-plan, V5 condition 3] Undo of a System Default token value | the undo of a rollback of a System Default Setting change whose current default is a token URL | the undo runs from the stored raw `after`; the item's effective value is the raw token URL, byte for byte | No error expected |

</intent-contract>

## Code Map

All web paths are under `web/`. IRIS paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`. HEAD 9514d500 (no code change since 1fc32ac5; line numbers hold).

**To change: the page**
- `src/app/incidents/incident-view.ts`: `INCIDENT_TEXTS` 34-79 (`labelCause` 61); `IncidentContext` 88-108 (`itemTime` 98); `settingCauseOf` 262-272 (built: the cause line of AC3); `panelOf` 362-391 (Cause row 364-367, the setting rows go after it).
- `src/app/incidents/evidence-panel.ts` 17-42: generic rows; no change unless lint asks.

**To change: the server redaction (redactor ruling)**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (bridge, GRANTED): class doc 12-18 (names the patterns); `PatternList` 192-217, the `If kv` key rules 208-215; `KeyPattern` 225-238 (the SENSITIVEKEYS names; `key` is NOT one, and must not become one: `SensitiveKey` suffix-matches, so `monkey`, `cacheKey`, `dedupKey` would turn sensitive, and `TestSensitiveKeys` :50 pins 25 names).
- `Live/Payload/Approval.cls` (Lane B, in footprint): `FromRow` fix branch 144-153, `part.Before` 148 and `part.After` 149 (raw today). The `Kind = "setting"` branch 120-125 (`SettingText` 226-233) is a persona proposal (`Core/SettingsOps.cls:548-553`), not a production setting: not touched.
- `Live/Payload/Incident.cls` (Lane A, GRANTED): `Change` 116-134, `OldValue` 127 and `NewValue` 128 (raw today); doc 114-115.
- `Watch/SettingCause.cls` (Lane A, GRANTED; the slot fill): `RollbackSlots` 271-286 (before/after 277-278, set 283-284), `UndoSlots` 289-310 (298-299, set 307-308), `ResultSlots` 332-350 (after 337, set 347); private `Text` 383-386; class doc 13-14. `{reason}` of `result.settingSavedNotApplied` (338/348) is already redacted upstream (`Fix/Executor.cls:201,637`; `Fix/Run.cls:389`).
- `Watch/Notice.cls` (granted, NOT edited): it only delegates the fill: `AskedSlots` 243 -> `UndoSlots`, `WithFixSlots` 344 -> `RollbackSlots`, `ResultSlots` 446 -> `SettingCause.ResultSlots`.

**To change: V5 (the dry-run answer's hand-off)**
- `Fix/Executor.cls` (Lane A, V5): class doc 1-8 (the DryRun bullet); `OnMessage` 169-178; `DryRun` 181-205 fills `response.DryRun` from `dryRun.%ToJSON()` at 192 (raw before/after of the setting kinds: `RollbackSetting.cls:89-90`, `UndoRollback.cls:52-53`); `Work` 207-225 resolves the kind (`Fix.Kind.ForName`); `TARGETTYPE` "setting" is how the setting kinds are told apart (`Fix/Kind/RollbackSetting.cls:26`; the undo inherits it). Precedent for a detached job: `Core/SettingsOps.cls:2177` (`Job ##class(...).UpdateIn():($Namespace):5`). Lane C's DW-1205 also edits this file (plain union).
- `Watch/IncidentManager.cls` (Lane A, V5): `OnResponse` 319-339 hands a `DryRunResult` to `Proposed` (DRYRUNKEY 330-333, LATERDRYRUNKEY 334-337). `Proposed` 970: early exits BEFORE its parse (incident not open or not asking 976; Reason 977-981; empty Targets 982-985; a refused transition 986-989), parse 991-1000, raise and `StoredDryRun` 1054. The chat ask: `RaiseAsked` 1166, `AskDryRun` 1176 (sync, `ASKSECONDS` 30 at :233, `AskDryRun` 1338-1341), early exits 1182-1189 (Reason, empty Targets), parse 1191, `AskedSlots` 1192, `RaiseFix` 1197. `StoredDryRun` 1345-1360 keeps only `DRYRUNKEYS`. `ResultExtra` 1720-1738 reads `after` from the stored (raw) dry run at 1731; the redaction in `ResultSlots` covers it.
- `Fix/Msg/DryRunResult.cls` (Lane A, doc only): its doc 1-4 already allows "the kind's own transient keys ... which are never stored".
- Read only: `Core/SecretHandoff.cls` (Lane B Core, AD-19): `Put` 26 (a named `$SYSTEM.Event` resource), `Take` 52 (always deletes the resource; a second take fails plainly), `Discard` 77. It has NO lifetime: a named resource lives until it is deleted or the instance shuts down (`irislib/%SYSTEM/Event.cls:78`); the spine's AD-19 hand-off bullet (`ARCHITECTURE-SPINE.md:709`) names only "an expired wait" (Take's `timeoutSec`) and `Discard`. See V6.
- Read only: `Fix/Kind/UndoRollback.cls` `Approved` 108-121 (reads the STORED dry run's `after`, which `Plan` 123 compares for a System Default Setting undo), `Restored` 102-105; `Fix/Kind/RollbackSetting.cls` `Restored` 100-104, `Entry` 219-228 (the write reads the `SettingChange` row, never the dry run).

**Already built (read only, evidence)**
- Approval view `src/app/approvals/approval-view.ts` `settingDryRunView` 278-293; `approval-request-card.ts` dry-run rows 146-175 (`.mono.before` 154, `.mono.after` 160). Phone `src/app/phone/phone-view.ts` `blocksOf` 128. Payload interfaces `src/app/live/payloads.ts` `SettingChange` 145-153 (generated; `npm run build` runs `--check`).
- IRIS: `Live/Payload/Part/DryRun.cls` 28-43 (Before/After MAXLEN 1000), `Part/SettingChange.cls` (Old/NewValue MAXLEN 2000).
- Catalog `Msg/Catalog/Watch.cls`: `rollbackRequest` 1129, `undoRollbackRequest` 1144, `settingChangeCause` 1155, `result.settingRestored` 1165, `result.rollbackUndone` 1182.
- Renderers that take the slots as given: `Channel/SimPhone/Out.cls:83-88` (stores `Data.SimMessage.Text`), `Channel/Telegram/Out.cls:174,212`.
- Payload consumers that read only Item, Field, To, Affected, ItemNoun (unaffected): `Core/AnswersIn.cls:111`, `Channel/Telegram/In.cls:477-481`.
- Leak helpers: `Test/Core/SecretHandoff.cls` `TraceLeaks` 240 (Ens.MessageBodyD/S, MessageHeaderD, Util.LogD), `Test/Agent/RunnerFixture.cls` `LogRowsHolding` 297; model `Test/Core/CommandsStep4.cls` `AssertNoLeak` 473. Message tables: `OcuTalon_Fix_Msg.DryRunResult` (IncidentRef, DryRun), `OcuTalon_Msg.Notification` (IncidentRef, CatalogKey, Slots).

**Tests to extend or add**
- Page: `scripts/incident-view.test.mjs` (setting cause 178-190, panel 380-437); `scripts/ux-strings.test.mjs` `ruled` 813.
- e2e: model `e2e/rail/rail-answer.spec.ts` (`holdPolls`, `dropPhone`, `cleanFixtureRows`, `finally`); `e2e/support/approvals.ts` (`incidentOf` 40-61, `phoneOf`/`messageOf` 87-88, `phoneShows` 121-131); `e2e/support/iris.ts` (`irisScript` 108, `publishIncident` 182, `sendNotification` 684, `cleanFixtureRows` 704, `seedApproval` 776 with `dryRun.before/after`, `seedIncident` 1060, `seedSettingChange` 1101, `dropSettingChange` 1126); `e2e/support/scan.ts` `scanContrast` 149, `scanNames` 49. The sign-in-2 project runs `e2e/rail/` (`playwright.config.ts` 48-50, 88).
- `Test/Bridge/Redact.cls`: `TestPatterns` 71, `TestPlainText` 221-229, `TestIdempotent` 231-246 (a hand-written list), `TestUrlCredentials` 333-343, `Check` 372 (asserts the result and that a second pass changes nothing).
- `Test/Watch/SettingCause.cls` (runs on a slot or a throwaway): fixtures `Change` 68, `Incident` 88, `Snapshot` 55; `TestPayload` 369-388.
- `Test/Watch/Rollback.cls` (throwaway and CI only, fresh): `SaveDefault` 79, `DropDefault` 96 (drops `RetryInterval` and `BusinessPartner`), `Effective` 124, `Stored` 133, `ChangeRows` 202, `Request` 220, `Change` 230-252, `Prepare` 254, `Run` 412-454 (stores `answer.DryRun` as the fixture request's dry run at 423), `TestIncidentNamesTheChange` 578-634 (the real raise through `[[mock:diagnosis-rollback]]`), `TestUndoAfterClose` 636-673, `RollBackDefault` 723-748, `TestUndoSystemDefaultChanged` 750-766, `TestUndoDefaultMovesAfterDryRun` 768-799 (stores `answer.DryRun` at 779), `TestUndoDefaultGone` 903-942 (the `BusinessPartner` System Default pattern: alpha, beta, rollback to alpha). Its `AskDryRun` calls of the setting kinds: 404, 415, 463, 526, 668, 685, 693, 712, 776, 937. `Test/Watch/Case.cls` `AskDryRun` 2257 (`[ Private ]`, so a subclass may override it); `Test/Watch/IncidentProbe.cls` `AskDryRun` 193 and `Test.Fix.Asked`'s doubles 240-248 answer without the Executor (no `values`).
- `Test/Channel/TelegramOut.cls`: `TestButtons` 820 is the model (`Request` 808, `FixtureSlots`, `SentTo`).

## Tasks & Acceptance

**Execution (in dependency order):**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` -- In the `If kv` block, add the bare `key=` shape: a key named exactly `key` (any case), not preceded by a letter, digit, `_`, `.` or `-`, then optional spaces, `=`, optional spaces and a value, as the existing key rule takes a value (a run up to a space, quote, comma, semicolon or ampersand, or a quoted value with its quotes kept); the value becomes `[redacted]`. `:` is not a separator for it. Do not add `key` to SENSITIVEKEYS. Update the class doc's pattern list. -- The ruling's shapes: `user:password@` (207), `token=` and `access_token=` (key rule), `Bearer` (202) are present; plain `key=` (a Google-style `?key=`) is the one missing.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls` -- Add `TestSettingValueShapes`: through `Check`, `https://feed.example.test/orders?token=<t>&format=x` gives `...?token=[redacted]&format=x`; `?access_token=<t>` and `https://svc:<p>@feed.example.test/x` are redacted; the new `?key=<t>&x=1`, `key = <t>`, `KEY=<t>` and `key="a b"` are redacted; `monkey=1`, `keyboard=on`, `cacheKey=1`, `key: value` and a plain `OrdersRouter` are kept. Add a `key=` text to `TestIdempotent`'s list. Update the class doc's bullets. Fixtures from fragments.
- `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls` -- One private helper (e.g. `Shown(value)`) returns `##class(OcuTalon.Bridge.Redact).Text(..Text(value))`. `RollbackSlots`, `UndoSlots` and `ResultSlots` set `before`/`after` from it, after their empty checks (which keep reading the raw value). Setting and target names stay as they are. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls` -- In `Change`, `part.OldValue` and `part.NewValue` are `Redact.Text` of the row's values; an empty value stays empty. Update its doc. At integrate, union with lane B's `Paged` hunk next to `Change` and keep both (Design Notes, "Contention").
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` -- In the fix branch, `part.Before` and `part.After` are `Redact.Text` of `dry.before` and `dry.after` (for every fix kind: suspend's "enabled"/"disabled" and repair dates are unchanged by it). The persona `Kind = "setting"` branch is not touched. Update the class or method doc.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` (V5; the lifetime is V6) -- Add `Parameter VALUESSECONDS = 60` (the longest an untaken entry lives). Add `ClassMethod OfferValues(dryRun As %DynamicObject, seconds As %Integer = {..#VALUESSECONDS}) As %Status`: `SecretHandoff.Put` of the JSON `{"before", "after"}` (raw, with their JSON types); then a detached job (`Job ##class(OcuTalon.Fix.Executor).Expire(uri, seconds):($Namespace)`, as `SettingsOps:2177`) that waits `seconds` and calls `SecretHandoff.Discard(uri)` (no error when it was taken); then sets `before`/`after` to their `Redact.Text` form and adds the transient key `values` with the reference. A failed `Put` or `Job` discards what was offered and is an error. Add `ClassMethod Expire(uri As %String, seconds As %Integer)` (it logs nothing). Add `ClassMethod TakeValues(dryRun As %DynamicObject) As %Status`: a dry run without `values` is left as it is and is OK (test doubles, other kinds); else it removes `values`, takes the reference (`SecretHandoff.Take`, a short wait), and puts the raw `before`/`after` back; a failed take is an error and leaves `before`/`after` redacted (the caller must not store them). In `DryRun`, after `Work` succeeds and the kind's `TARGETTYPE` is `setting`, call `OfferValues` before `response.DryRun` is set; its error is the dry run that could not be worked out (the existing internal-error reason). Update the class doc (the DryRun bullet). -- The ruling: DryRunResult carries the redacted values plus a SecretHandoff reference.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` (V5) -- Take on receipt, before any early exit, so that every answer that reaches IncidentManager ends its entry: in `Proposed`, first (before the incident is opened); in `RaiseAsked`, right after the answer is checked to be a `DryRunResult` (before the Reason and Targets checks). When `result.DryRun` is non-empty, parse it once and call `Fix.Executor.TakeValues` on the parsed object; the rest of the method uses that local object (the slots, `RaiseFix`, `StoredDryRun`), never `result.DryRun` again, and never sets a raw value onto `result`. A failed take (the entry is gone: expired, discarded or never put) is remembered and acted on only where the method would go on to raise, and it takes the EXISTING REFUSAL PATH with the kind's `NOSTART` as the reason (V6 ADDED CONDITION, Spec Change Log; BINDING; it replaces the earlier `Decline(incident, later, 1)` design): in `Proposed`, after its existing incident check (open, or asking for a later round), exactly as a `result.Reason` equal to the ask kind's `NOSTART` ("OcuTalon couldn't change the setting"): one Type 3 warning (LOGPROPOSE or LOGLATER, through `Redact.Text`) and `Decline(incident, later, 0, Notice.NoFixKey(<NOSTART>))`; in `RaiseAsked`, after its Reason and Targets checks, the same refusal outcome and reason as a `Reason` answer with that text, with one LOGASK warning. The redacted value is NEVER stored as raw: nothing is raised and no `DryRun` holding `[redacted]` is stored. A path that raises nothing (the incident moved on, a Reason, empty Targets) drops the answer as today, after the take. `StoredDryRun` then stores the raw values, as today. Update the docs of `Proposed` and `RaiseAsked`.
- `src/ocutalon/cls/OcuTalon/Fix/Msg/DryRunResult.cls` (V5; doc only) -- The doc names the transient `values` reference of the setting kinds, that their `before`/`after` are redacted in the message, and that IncidentManager takes it on receipt. No property or storage change.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingCause.cls` -- Add `TestShownRedacted`: with a fixture change whose old value is a token URL (from fragments) and one with plain values, (a) `Incident.FromRow(...).SettingChange` Old/NewValue are redacted and plain values unchanged, and the stored `SettingChange` row is raw; (b) `Approval.FromRow` of an in-memory `ApprovalRequest` (Kind fix, FixKind `rollback_setting`, then `undo_rollback`) has redacted `DryRun.Before/After`, and `row.DryRun` is unchanged; (c) `RollbackSlots`, `UndoSlots` and `ResultSlots` (`result.settingRestored`, `result.rollbackUndone`) give redacted `before`/`after`, and the catalog's phone text rendered from them holds `[redacted]` and not the token; (d) a 1,000-character token URL exports (Decided 10). Add `TestValuesHandoff` (V5 condition 1): (a) `Fix.Executor.OfferValues` on `{item, field, before: <token URL>, after: "OrdersRouter"}` gives a redacted `before`, an unchanged `after` and a `values` reference (`secret://handoff/...`), and the object's JSON holds no token; (b) `TakeValues` puts the raw values back byte for byte and removes `values`, and a second `SecretHandoff.Take(uri, , 0)` fails (the entry was deleted when taken); (c) `OfferValues` with `seconds` 1 and no take: after `Hang 3`, `SecretHandoff.Take(uri, , 0)` fails (the entry expired); (d) a dry run without `values` is unchanged and OK; (e) `TakeValues` of a reference already taken is an error, leaves no raw value and no `values`; (f) V6 PIN, the real lifetime: add it as its own method `TestValuesExpireDefault`: `..#VALUESSECONDS` is 60, `OfferValues` with the default seconds and no take, `Hang 62`, `SecretHandoff.Take(uri, , 0)` fails (the entry is gone); the method ends inside about 100 s. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls` -- (1) Override `AskDryRun`: call `##super`, and when the answer's `DryRun` holds `values`, return an unsaved clone (`%ConstructClone`) whose `DryRun` is the JSON after `Fix.Executor.TakeValues`, so that every fixture request holds what IncidentManager would store and no entry is left behind; the stored answer in the trace is never changed. (2) Add `TestTokenValueRestoredRaw` (V5 condition 2; AC4, AC5): `Change(a, "Host", <token URL>, <plain URL>, .unused, 0)` through the real raise (`[[mock:diagnosis-rollback]]`, as `TestIncidentNamesTheChange`), then approve and execute the real request (`SendExecute`). Assert: the stored `ApprovalRequest.DryRun` `after` is the raw token URL; `Approval.FromRow` After, the incident payload's OldValue and the `incident.rollbackRequest` and `result.settingRestored` notices' slots and phone text are redacted; `Effective(...)` equals the raw token URL byte for byte; the incident's `DryRunResult` bodies (`OcuTalon_Fix_Msg.DryRunResult` by IncidentRef) hold `[redacted]` and a `values` reference and not `<t>`, and its `Notification` bodies (`OcuTalon_Msg.Notification` by IncidentRef, those two keys) hold `[redacted]` in Slots and not `<t>`; and `TraceLeaks(<t>)` is "", `LogRowsHolding(mark, <t>)` is 0, and no `Live.Event` Payload and no `Data.SimMessage` Text holds `<t>`. (2b) Add `TestTakeMissingNoRequest` (V6 ADDED CONDITION pin): through the real raise, force the discard of the entry between the Executor's answer and IncidentManager's take (the `AskDryRun` override or a test seam may discard the offered `values` reference after `##super`); assert that no `ApprovalRequest` is raised for the incident, no stored `DryRun` of the incident holds `[redacted]`, the incident went down the refusal path with the `NOSTART` reason ("OcuTalon couldn't change the setting"), and the item's setting is unchanged; do it for the first-round path (`Proposed`) and, if it fits in one call, the chat ask (`RaiseAsked`) too. (3) Add `TestUndoSystemDefaultTokenRaw` (V5 condition 3; AC7): on `BusinessPartner` (`EMPTYSETTING`), as `TestUndoDefaultGone`'s second half: System Default alpha, then beta (a Tick after each), the rollback of the beta change (`Run`, alpha on the item), then the System Default becomes `<token URL>` while the item's own value hides it; the undo through `Run` (before alpha, after the raw token URL) runs, and `Effective(item, "Host", "BusinessPartner")` equals the raw token URL byte for byte and `Stored(item)` is as before the rollback. `DropDefault` cleans it. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls` -- Add `TestRedactedValue`: an `incident.undoRollbackRequest` whose slots come from `Watch.Notice.AskedSlots("undo_rollback", <dry run with a token URL>, <incident>)` is sent with `[redacted]` and without the token, and one whose dry run holds plain values is sent with them byte for byte; on its own chat id.
- `web/src/app/incidents/incident-view.ts` -- Add the five strings of Public text to `INCIDENT_TEXTS`. In `panelOf`, right after the Cause row, add the rows from `payload.settingChange`: "Setting change" `{setting} on {item}` in mono; "Old value" and "New value" in mono, each left out when `credential` is true or its value is empty; "Detected" `ctx.itemTime(detectedAt)`, not mono, left out when unreadable. Rows show only when both `setting` and `item` are set. The values are shown as the server sends them (already redacted); the page redacts nothing. Update the module doc.
- `web/scripts/incident-view.test.mjs` -- Pin each panel row of the matrix: rows, order, mono, the secret, an empty value, no change, a server-redacted value shown as given.
- `web/scripts/ux-strings.test.mjs` -- Add one `ruled` entry with the five strings, citing the Planner's V1 ruling. Never an invented source.
- `web/e2e/support/iris.ts` -- Add `askedSlots(kind, dryRun, incidentRef)`: an `irisScript` that returns `Watch.Notice.AskedSlots(kind, dryRun, <the incident row>, .sc).%ToJSON()` (the real server fill), for `sendNotification`. Extend, don't copy: it reuses `irisScript`, `quoted` and `chk`.
- `web/e2e/rail/step5-requests.spec.ts` (new; sign-in-2 project, RAIL user, `workers: 1`) -- Cases F3b, F5, F5b and F7 as the ACs describe (Story 24.4b adds F1 to F4 and F6 to this file); each cleans its rows, setting changes and phone messages in `finally`.

**Acceptance Criteria:**
- AC1 (V4 patterns; was AC9): Given `Redact.Text`, when a text holds a URL `user:password@`, `token=`, `access_token=`, `key=` or `Bearer`, then the secret is `[redacted]`, the rest is kept and a second pass changes nothing; `monkey=`, `keyboard=`, `cacheKey=`, `key:` and plain text are kept. Pin: `TestSettingValueShapes`.
- AC2 (redactor ruling, the views; AD-31 Redaction; NFR-11; was AC6): Given a non-secret setting change whose old value is a token-bearing URL, when it is shown, then the web approval card's rollback After (F3b), the evidence panel's "Old value" (F5b), the phone page's undo request message (F7) and the Telegram text (`TestRedactedValue`) read `...?token=[redacted]` and hold no token, while a plain value is shown byte for byte on the card (F3b), the panel (F5) and Telegram (`TestRedactedValue`). Unit pins: `TestShownRedacted`.
- AC3 (FR-27; UX-DR78, 146; AD-12; UX-DR8, 33, 117; NFR-25; Integration; was AC3 and AC5's panel part): Given a real `SettingChange` row and an incident that names it (`seedIncident` with `settingChangeRef`, first failure 4 minutes after `detectedAt`), when the page loads `/api/v1/state`, then the card shows "The feed broke four minutes after this setting changed: {setting} on {item}, at {time}.", and Show details lists the Setting change, Old value, New value and Detected rows, the first three in mono, with the value rows left out for a credential or an empty value; the card has no unnamed control and no contrast failure (`scanNames`, `scanContrast`) in both the light and the dark scheme, and Tab reaches Show details with a visible focus ring; `payloads.mjs --check` passes and `ux-strings.test.mjs` covers the five strings. Pins: F5 and the `incident-view.test.mjs` panel cases.
- AC4 (redactor ruling, NOT redacted; AD-16; was AC7): Given an approved rollback of a token-bearing value, when it runs, then the item's setting is the raw value again, byte for byte, the stored `ApprovalRequest.DryRun` holds the raw values, and every view of it is redacted. Pin: `TestTokenValueRestoredRaw`.
- AC5 (redactor ruling, trace and logs; V5 condition 2; AD-1, AD-19; was AC8): Given that run, when it has ended, then the run's `DryRunResult` bodies hold `[redacted]` and a hand-off reference and not the token, its `Notification` bodies hold `[redacted]` in Slots and not the token, and no Ens message body, header or event-log row (`TraceLeaks`, `LogRowsHolding`), no stored live event payload and no phone message holds the token. Pin: `TestTokenValueRestoredRaw`.
- AC6 (V5 condition 1; AD-19): Given a setting kind's dry run offered through `OfferValues`, when it is taken, then the raw values come back byte for byte and the entry is deleted (a second take fails); and when it is never taken, then the entry is gone after its lifetime (`VALUESSECONDS`; 1 s in the test). Pin: `TestValuesHandoff`.
- AC7 (V5 condition 3; AD-16): Given the undo of a rollback of a System Default Setting change whose current default is a token URL, when it runs, then it works from the stored raw `after` and the item's effective value is the raw token URL, byte for byte; `TestUndoSystemDefaultChanged` (the byte-for-byte restore pin of DW-1366) stays green. Pin: `TestUndoSystemDefaultTokenRaw`.
- Playwright cases (`step5-requests.spec.ts`): F3b two pending `rollback_setting` requests seeded with dry runs, one whose After is a token URL (the card's After reads `...?token=[redacted]`, no token in the card's text) and one with plain values (shown byte for byte); F5 the setting-change cause line and panel rows with plain values, with the scans in both schemes and the Tab order (AC3); F5b a `seedSettingChange` with a token-URL old value (panel redacted, no token in the card's text); F7 an undo notice whose slots come from `askedSlots` on the phone page (redacted, no token).

### Review Findings

Code review 2026-11-15 (lane D; Tier 1, full mode; four layers: Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor; diff `c42de191..a9c73ee3` over `src web docker`). 23 entries after grouping: high 0, medium 2, low 19, false 2. Patched 5, escalated 1 (DW-1412), closed 17 (DW-1413 among them).

- [ ] [Review][Decision] Redact.Text misses the common URL signature parameters (`sig=`, `signature=`, `X-Amz-Signature=`, `X-Amz-Credential=`, `auth=`) — [medium; fix-risk med; in-story; Blind Hunter + Edge Case Hunter] an Azure SAS or S3 presigned URL in a non-secret setting is shown raw on the card, the panel, the phone and Telegram. The redactor ruling listed user:password, `token=`, `key=` and `Bearer`, and widening the shared redactor (every log) is a security-posture call: `decision-pending owner=burndown` as DW-1412 for the decision sheet. Does not block `done`.
- [x] [Review][Patch] The test global of `Fix.Executor.Lifetime` could lengthen the lifetime without bound, and the product path's 60 s lifetime had no pin [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:257] — [low; Blind Hunter + Edge Case Hunter + Verification Gap + Acceptance Auditor] `Lifetime` now accepts only a whole number from 0 to `VALUESSECONDS` (`$Number(..., "I", 0, VALUESSECONDS)`; anything else gives 60), so the seam can shorten and never lengthen; it is `[ Internal ]` so that the new `Test.Watch.SettingCause:TestValuesLifetime` pins it (no global: 60; 0, 5, 60 kept; 600, 61, -1, 1.5, a word: 60). The seam itself is kept: it is the only way to force the discard before the async take (V6's pin), and a parameter cannot be changed by a test.
- [x] [Review][Patch] The escaped-quote alternative of the bare `key=` rule had no test [src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls:243] — [low; Verification Gap] `TestSettingValueShapes` gains a value in escaped quotes (JSON quoted in a text).
- [x] [Review][Patch] `TestRedactedValue`'s plain half could not see a missing `{before}` (its `OrdersRouter` is a prefix of `OrdersRouterNew`) [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls:851] — [medium; Rule 19 unfalsifiable sub-pin of AC2; Verification Gap] the plain `before` is now `LegacyRouter`.
- [x] [Review][Patch] F7 seeded its `undo_rollback` row with the rollback's shape while the slots used the undo's [web/e2e/rail/step5-requests.spec.ts:195] — [low; Blind Hunter] one `dryRun` (before the token URL, after `OrdersRouterNew`) now seeds the row and fills the slots.
- [x] [Review][Patch] Stale helper docs in `Test.Watch.Rollback` (`Shown`, `FirstHit`'s 300 for 400) and the unused `change` parameter of `RaiseTokenRollback` [src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls:968] — [low; Blind Hunter + Edge Case Hunter] docs corrected, the parameter and its three arguments removed.

Rejected or closed (verdict, reason):
- [low] `wontfix-accepted` (DW-1413) One detached `Expire` process per setting-kind offer, held 60 s even after the take; QA saw the 8th offer of one test fail to start its job. Measured on lane D: the limit is IRIS Community's 8 connections, and only jobs of a licensed process count (7 `Expire` jobs from an `iris session`, then `JOB ...:5` gives `$Test` 0); FixExecutor's own `Expire` jobs (seen in state HANG under the production) run as `_Ensemble` with no `LicenseUserId`, and `InstanceConnections` stays 1, so the product path is not bound by it. When a `JOB` fails, `OfferValues` discards the entry and errors, `DryRun` answers the internal-error Reason with an empty DryRun, and nothing raw is left (no HIGH path). V6 option (a) is ruled. reopen_if: a setting-kind DryRunResult with the internal-error Reason, or a failed Expire JOB, in a running production.
- [low] `by-design` An async answer that waits over 60 s, or a later round's refusal keeping the window marks — V6's ADDED CONDITION is binding: a missing entry takes the existing refusal path with NOSTART; the failure is the safe one.
- [low] `by-design` The bare `key=` rule changes every caller of Redact.Text (the evidence pack, error texts) — the redactor ruling puts the shape in Redact.Text "so logs benefit too".
- [low] `by-design` The approval payload redacts every fix kind while a repair kind's phone slots stay as they were — Decided 8; the non-setting kinds' notice slots are outside this story and the web side is the safer one.
- [low] `by-design` `TestValuesExpireDefault` takes about a minute — V6's PINS require the real 60 s discard.
- [low] `reject` No test that a non-setting kind offers nothing, or of a failed `Job` — no observable harm (a non-setting kind's values round-trip unchanged) and a `Job` failure cannot be forced without another seam; the failure path was read and holds.
- [false] `reject` `OfferValues` on a dry run that already holds `values` would offer redacted text as raw — its only caller is `DryRun`, with the fresh object of the kind's `Work`.
- [low] `wontfix-accepted` A plain value that is JSON text is re-serialized for display (`[1, 2]` shows `[1,2]`) — display only, stored and written values stay raw; the cure edits the shared redactor's JSON branch. reopen_if: a production setting whose value is JSON text is shown reformatted to a user.
- [low] `by-design` The persona proposal branch (`Kind = "setting"`) is not redacted — the spec leaves it untouched (not a production setting).
- [low] `reject` `FirstHit(token)` scans the Ens bodies eagerly in the assertion message — about a second (earlier triage).
- [low] `wontfix-accepted` `Test.Watch.SettingValues` offers with a 4 s lifetime, so on a very slow host an entry could expire before the host call and a `Held` 0 check pass without the take — chosen to stay under the test process's job limit; its mutations went red. reopen_if: a host call of that class takes over 4 s in CI.
- [low] `wontfix-theoretical` `TestShownRedacted` (d) exports a value that shrinks when redacted, so it does not test a value that grows past MAXLEN — needs more than about a hundred token pairs in a 1,000-character value, which no setting has.
- [low] `reject` The leak scans search the whole namespace for one token — they assert absence, so a leftover can only turn them red when something really leaked it.
- [low] `reject` Expiry jobs left by earlier tests could starve `Test.Watch.SettingValues` — measured: it passed (8.7 s) right after `TestValuesHandoff` left three 60 s jobs.
- [false] `reject` `RaiseAsked` now fails a dry run that is JSON but not an object (`[1]`) — no producer sends one (FixExecutor answers an object or nothing).
- [low] `wontfix-theoretical` A started `Expire` job killed before its `Discard` leaves the entry until IncidentManager takes it or the instance restarts — needs an administrator to terminate that process and the answer to be lost as well.
- [low] `reject` The spine's AD-19 hand-off bullet and the Redaction convention are not yet updated — a Rule 20 write for the lead, named in Design Notes; not a code defect.
- [low] `reject` `Test/Watch/SettingValues.cls` (QA) is a new test class outside the named grant — tests only, in this story's area; for the lead's `footprint_extensions:`.

## Spec Change Log

- 2026-11-15 (lead). **V6 RULING, Contest Planner ~22:30Z Nov 15 (BINDING)**, quoted in full:

  > ## V6 RULING (Contest Planner, ~22:30Z). BINDING for 24.4a.
  > OPTION (a) is APPROVED.
  > - FixExecutor starts a detached job that discards the handoff entry after VALUESSECONDS (60 s).
  > - Do not edit SecretHandoff.
  > - IncidentManager takes the entry as soon as an answer arrives, before any early exit.
  > 
  > ADDED CONDITION, the missing-entry rule:
  > - If IncidentManager's Take finds NO entry (expired, discarded or never put), it must NOT store the redacted value as if it were the raw one.
  > - In that case the request is NOT raised. The incident goes down the existing refusal path with the NOSTART reason ("OcuTalon couldn't change the setting"), so an approval can never restore "[redacted]" into a production.
  > 
  > PINS:
  > - Missing entry: force the discard before the take. Assert there is no request and no stored DryRun containing the marker.
  > - 60 s discard: the entry is gone after the 60 s discard.
  > - Normal take: a take within the window succeeds, and the entry is gone at once afterwards.

  Applied: option (a) as planned; the ADDED CONDITION (missing entry -> no request, the incident takes the existing refusal path with `NOSTART`, never a redacted value stored as raw) and its three PINS are binding on the implement stage. Integrated over feature 92937a03 (23.4 and lane B's `Paged` hunk in `Live/Payload/Incident.cls`, auto-merged; `Watch/IncidentManager.cls` also changed on feature): re-check Code Map line numbers at implement.

- 2026-11-15 (plan, re-plan iteration 3, narrowed to 24.4a under the RE-PLAN RULINGS). Intent amended to 24.4a's scope (each change marked `[AMENDED 2026-11-15, re-plan narrowed to 24.4a]` or `[..., re-plan rulings, V5 ...]`): the Problem drops the closed-card bullet and the cross-surface paragraph and points to 24.4b; the Approach drops the compact-card bullet, adds V5's take-on-receipt and expiry, and narrows the pins; Always adds "raw values in locals only" and "every offered entry taken or discarded"; Never names V5's files, forbids `Core/SecretHandoff.cls`, and replaces the compact-card rule with "no change to the compact card (24.4b)"; the matrix drops the three closed-card rows (moved) and gains the hand-off taken, never-taken and System Default undo rows. ACs renumbered for 24.4a: AC1 was AC9, AC2 was AC6, AC3 was AC3 plus AC5's panel part, AC4 was AC7, AC5 was AC8 plus V5 condition 2, AC6 and AC7 are new (V5 conditions 1 and 3); old AC1, AC2, AC4 and AC5's card part moved to 24.4b (Design Notes). Tasks: V5's design made concrete (`OfferValues`, `Expire`, `TakeValues`; the take on receipt before every early exit; the Rollback helper's `AskDryRun` override); `TestValuesHandoff` and `TestUndoSystemDefaultTokenRaw` added; `TestStepFiveRequests`, the compact-card tasks and their web/scripts pins moved. Found during the plan: SecretHandoff has no lifetime, so "expires within SecretHandoff's existing limit" (V5 condition 1) has no existing limit to use: flagged NEW V6, with the recommended 60-second discard job. `multiple-goals` cleared (Decided 18). `baseline_revision` moved to HEAD 9514d500 (no code change since 1fc32ac5).

- 2026-11-15 (lead). **RE-PLAN RULINGS, Contest Planner ~22:00Z Nov 15 (BINDING)**, quoted in full:

  > ## RE-PLAN RULINGS (Contest Planner, ~22:00Z). BINDING.
  > 
  > ### V5: GRANTED
  > Lane D may edit:
  > - Fix/Executor.cls;
  > - Watch/IncidentManager.cls;
  > - Fix/Msg/DryRunResult.cls (doc only);
  > - the Test/Watch/Rollback helper.
  > 
  > Fix/Executor.cls is also changed by lane C's DW-1205, so the plain-union rule applies there.
  > 
  > How it works:
  > - DryRunResult carries the redacted values plus a Core.SecretHandoff reference.
  > - IncidentManager takes the raw values once, for the store.
  > 
  > CONDITIONS. Pin each of these:
  > - The handoff entry is deleted when it is taken.
  > - An entry that is never taken expires within SecretHandoff's existing limit.
  > - After a rollback, the Ens trace message bodies for that run (DryRunResult and Notification) contain the redacted marker and NOT the raw token.
  > - The undo of a System Default still works from the stored raw value, and the byte-for-byte restore pin still holds.
  > 
  > ### V4: CONFIRMED
  > - Web, phone and Telegram show "[redacted]", Redact.Text's existing marker.
  > - The new bare key= shape in Redact.Text is APPROVED, with its pin.
  > 
  > ### SPLIT: YES
  > - **24.4a** goes FIRST and is the 1.0.12 BLOCKER. It covers:
  >   - redaction on every display path;
  >   - V5;
  >   - the V1 panel rows.
  > - **24.4b** follows. It covers V2's closed-card undo and the cross-surface pins. It also targets 1.0.12, but does not block it.
  > - Charter both in epics.md with markers. The orchestrator re-records epics_md_hash at the merge.
  > 
  > ### Contention
  > At integrate, flag lane B's Paged hunk next to Change in Live/Payload/Incident.cls. Union the two and keep both.

  Applied by the lead: `epics.md` splits Story 24.4 into **24.4a** (this spec, renamed from `spec-24-4-...`; redaction on every display path, V5 and the V1 evidence-panel rows; the 1.0.12 blocker) and **24.4b** (V2's closed-card undo and the cross-surface pins; its spec is carved from this plan later), with `[AMENDED/ADDED 2026-11-15, Contest Planner split]` markers. Status reset to `draft` for a re-plan narrowed to 24.4a.

- 2026-11-15 (plan, re-plan iteration 2). Folded in the REDACTOR RULING. Intent amended (marked `[AMENDED 2026-11-15, redactor ruling]` at each change): the Problem names the raw values and the two message bodies; the Approach adds server redaction with `Bridge.Redact.Text`, the hand-off reference in the dry-run answer and the `key=` shape; Always adds the redaction and the raw store and write; Never replaces "no Lane A file" with the granted list (plus NEW V5 once ruled) and adds "no second redactor; nothing stored redacted"; the matrix gains the token, plain and restore rows. AC4 gains V2's two pins; AC6 to AC9 added for the ruling; F3b, F5b and F7 added. V1's five strings, V2 and V3 kept; the implement stage's note (compact from the payload) is in the card task. Found during the trace check: `Fix.Msg.DryRunResult.DryRun` carries the raw values and is needed raw by the store (`UndoRollback.Approved`), so the reference form needs `Fix/Executor.cls` and `Watch/IncidentManager.cls`, beyond the grant: flagged NEW V5.

- 2026-11-15 (lead). **REDACTOR RULING, Contest Planner ~21:30Z Nov 15 (BINDING; supersedes V1's condition; a 1.0.12 BLOCKER)**, quoted in full:

  > ## REDACTOR RULING (Contest Planner, ~21:30Z). BINDING. OPTION 2, EXTENDED, and a 1.0.12 BLOCKER
  > 23.3 shipped the exposure to feature, so it must close before the 1.0.12 cut. It supersedes V1's condition above.
  > 
  > ### One redactor, on the SERVER
  > Use OcuTalon.Bridge.Redact.Text, applied on the server everywhere a setting's before, after, old or new value is SHOWN:
  > 1. **Approval payload.** In Live/Payload/Approval.cls, the rollback's and the undo's Before and After.
  > 2. **Incident payload.** In Live/Payload/Incident.cls, Change, which feeds the new evidence-panel rows.
  > 3. **Notice texts** (web chat, phone page, Telegram). Fill these slots from the REDACTED value; the slot fill is in Watch/Notice and SettingCause:
  >    - incident.rollbackRequest and incident.undoRollbackRequest: {before} and {after};
  >    - result.settingRestored and result.rollbackUndone: {after};
  >    - any summary line that carries a value.
  > 4. **Trace and logs.** Check the Ens trace and the logs. If any message body carries the raw before or after, make it carry a reference or the redacted value instead, and pin that.
  > 
  > ### NOT redacted
  > The stored ApprovalRequest.DryRun and the value the rollback writes stay raw, because execution must restore the exact earlier value.
  > - Pin: a rollback of a token-bearing URL restores it byte for byte, while every view of it is redacted.
  > 
  > ### Pins
  > - A token-bearing URL is redacted on the web card, the phone page, the Telegram text and the evidence panel.
  > - A plain value is unchanged.
  > 
  > ### Grant
  > Lane D may edit Live/Payload/Approval.cls, Live/Payload/Incident.cls, and the slot fill in Watch/Notice and SettingCause, under this ruling.
  > 
  > ### Redact.Text patterns
  > If Redact.Text's patterns miss a common secret shape (URL user:password, token=, key=, Bearer), add the pattern IN Redact.Text itself, so logs benefit too. Write no second redactor in the web.
  > 
  > ### Contention
  > Lane B (23.8, the DW-1396 follow-up) and lane C (DW-1205) are also working in Watch and Fix. The rule is a plain union: whoever pushes second integrates and flags any overlapping hunks.

  The implement stage had blocked on V1's condition (no redactor existed: `RollbackSetting.DryRun` L86-90 stores raw values; `Live/Payload/Approval.cls` L122-123/L148-149 and `Incident.cls` `Change` copy raw; the web interpolates raw). Status reset to `draft` for a re-plan that folds this ruling in.

- 2026-11-15 (lead). **Gate ruled, Contest Planner ~21:00Z Nov 15 (BINDING)**, quoted in full from `<coordination>/prompts/story-244-rulings-20261115.md`:

  > # Story 24.4 rulings (Contest Planner, about 21:00Z on 2026-11-15). BINDING.
  > 
  > 24.4 is APPROVED, with one condition. It targets 1.0.12.
  > 
  > ## V1: the five new page strings, APPROVED verbatim
  > The strings are:
  > - "Setting change"
  > - "{setting} on {item}"
  > - "Old value"
  > - "New value"
  > - "Detected"
  > 
  > CONDITION:
  > - Old value and New value go through the SAME redactor as the rollback dry run's Before and After.
  > - They are left out for a credential or an empty value, as proposed.
  > - Pin it: a non-credential setting whose value holds a secret-shaped string, such as a URL with a token, shows redacted in the panel.
  > 
  > ## V2: APPROVED
  > - A closed incident card draws only a rollback's undo request card.
  > - Add the one-line EXPERIENCE.md addition.
  > - Pin both of these:
  >   - a closed card draws no other request kind;
  >   - "Show in the chat" jumps to the undo request card.
  > 
  > ## V3: GRANTED as a footprint extension
  > - The four web/scripts test files are allowed.
  > - The BUTTONKINDS mutate-and-revert in a test is fine, provided it is never committed.
  > - Leaving DW-1378 out is correct.
  > 
  > ## DW-1388
  > If B13 goes red again, report it to the Planner as a regression.

  Applied by the lead: EXPERIENCE.md's Incident card bullet gains the V2 sentence (with "and no other request card"). Added to Execution (binding): (a) "Old value" and "New value" go through the SAME redactor as the rollback dry run's Before and After (name it in the code; no second redactor), and are left out for a credential or an empty value; pin with a NON-credential setting whose value is secret-shaped (e.g. a URL with a token) that shows REDACTED in the panel, with a mutation (bypass the redactor -> red); (b) pin that a closed card draws NO other request kind (e.g. a pending fix or partner warning on a closed incident draws nothing), with a mutation; (c) pin that the rail's "Show in the chat" jumps to the undo request card on a closed incident, with a mutation; (d) report any B13 (DW-1388) red as a regression.

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 32 findings — high 0, medium 1, low 26, false 5, maybe-false 0
- findings:
  - `[false]` `reject` Intent audit: `Live/Payload/Approval.cls` is not in the Never list's permitted edits — the redactor ruling's Grant names it and the Approach requires the approval payload's dry run to be redacted.
  - `[low]` `reject` Intent audit: the approval part's Before/After are redacted for every fix kind, not only setting kinds — Decided 8 (one rule, no kind list; enabled/disabled, dates and the email subject are unchanged by it).
  - `[low]` `reject` Intent audit: `Fix.Executor.Lifetime` reads `^IRIS.Temp.OcuTalon.Fix("valuesSeconds")`, a test seam in a product class — it is the only way to force the discard between the answer and the take (the V6 pin, binding); nothing sets it in the product, and a message field or parameter would widen the message contract the spec forbids.
  - `[low]` `reject` Intent audit: F7 and Telegram hand-deliver the real `AskedSlots` fill and cover the undo request only — the pins are as the spec and the rulings name them; `TestTokenValueRestoredRaw` covers the other keys through the real raise.
  - `[low]` `reject` Blind Hunter: one idle detached job per dry run for up to 60 s — V6 option (a), ruled by the Planner.
  - `[low]` `reject` Blind Hunter: a setting kind's answer with no `values` reference is taken as taken, so redacted values could be stored — only test doubles omit the reference (the real Executor offers or answers with a reason); the doubles are named by the spec and a stricter check would break them.
  - `[low]` `reject` Blind Hunter: the same seam is instance-wide, so a concurrent dry run during `TestTakeMissingNoRequest` would also expire — the fresh throwaway runs one test at a time and the test kills the global in its own cleanup.
  - `[low]` `patch` Blind Hunter: `Hang 3` and `Hang 62` are fixed sleeps (flake risk) — applied: `WaitGone` polls up to a deadline in `TestValuesHandoff` (c) and `TestValuesExpireDefault`.
  - `[low]` `reject` Blind Hunter: the NOSTART log assertion in `TestTakeMissingNoRequest` is loose — the test also asserts no request, no marker and the `incident.noFix` notice, and the ignore-the-take mutation turns it red.
  - `[low]` `reject` Blind Hunter: the bare `key=` rule takes the next line's word after `key=` and the closing bracket of `(key=secret)` — it takes its value exactly as the existing key rules do (`token=`), which the spec requires.
  - `[false]` `reject` Blind Hunter: long values overflow the panel — `evidence-panel.ts` sets `overflow-wrap: anywhere` on the value lines.
  - `[false]` `reject` Blind Hunter: `{reason}` of `result.settingSavedNotApplied` may quote a value — it is redacted upstream (`Fix/Executor.cls` 214, `Fix/Run.cls` `Plain`).
  - `[medium]` `patch` Verification Gap: the chat ask (`RaiseAsked`) take, refusal and raw store have no test, and the ignore-the-take mutation there stays green — applied: `Test.Watch.SettingCause.TestAskedTakeOnReceipt` through the probe host of `Test.Fix.Asked` (taken: raw stored dry run, redacted notice slots; entry gone: refused with NOSTART, nothing raised or sent); mutation recorded.
  - `[low]` `reject` Verification Gap: the later-round refusal in `Proposed` is untested — rare, shares the first-round branch and its pin; the fix is a second fixture for a path the spec does not name.
  - `[low]` `patch` Verification Gap: only the upper bound of the lifetime is pinned — applied: `TestValuesHandoff` (c2) asserts the entry is held one second into a 5 s lifetime and taken, and `TestValuesExpireDefault` asserts it is held at 50 s and gone between 59 and 75 s; mutation recorded.
  - `[low]` `reject` Verification Gap: `OfferValues`' failed-`Job` cleanup is unpinned — a `Job` failure cannot be forced without another product seam.
  - `[low]` `patch` Verification Gap: the 1 s and 60 s expiry pins sleep a fixed time (flake risk on a loaded runner) — applied with the Blind Hunter row: polling with a deadline.
  - `[low]` `reject` Verification Gap: `TestTakeMissingNoRequest` does not assert that an offer happened — the ignore-the-take mutation is red, and `TestTokenValueRestoredRaw` pins the offer in the trace.
  - `[low]` `reject` Verification Gap: the seam's `Kill` is after the Try, so an aborted test leaves the global set — only a throwaway's `^IRIS.Temp`, discarded with the stack.
  - `[low]` `reject` Verification Gap: `FirstHit(token)` scans the Ens bodies eagerly in the assertion message — a cost of about a second, not a defect.
  - `[low]` `reject` Verification Gap: sub-pins (dark-scheme contrast, `scanNames`, the credential guard, the plain value) have no mutation of their own — Rule 19 asks one mutation per AC, and each AC has one.
  - `[low]` `reject` Verification Gap: `TestSettingValueShapes` has no Bearer case — `TestPatterns` (83-86, 106) pins it and AC1 names it only as an existing shape.
  - `[low]` `reject` Edge Case Hunter: the `key=` lookbehind is ASCII only — a name ending in a non-ASCII letter is over-redacted, a backstop's safe side; the doc now says "an ASCII letter or digit".
  - `[low]` `reject` Edge Case Hunter: `key =>` and `key ==` redact the next token — prose, over-redaction of the safe kind; a guard adds a branch for no reachable value.
  - `[low]` `reject` Edge Case Hunter: `Redact.Text` re-serializes a plain value that is valid JSON (`[1, 2]` reads `[1,2]`) — real, but a setting whose value is a JSON text is rare, the change is display only (the stored and written values are raw), and the cure edits the shared redactor's JSON branch (residual risk, below).
  - `[low]` `reject` Edge Case Hunter: an async answer that waits over 60 s in a busy queue has expired — V6 ruled the lifetime; the failure is the safe one (the NOSTART no-fix route).
  - `[false]` `reject` Edge Case Hunter: another kind's dry run with a `values` key would be stripped and refused — no other kind sets `values` (searched `Fix/`).
  - `[low]` `reject` Edge Case Hunter: `TestTakeMissingNoRequest` leaves the seam's global set when it is aborted before its final `Kill` — the same throwaway-only residue as above; a cleanup hook adds nothing a discarded stack does not.
  - `[false]` `reject` Edge Case Hunter: the `reason` slot of `ResultSlots` is unredacted — redacted upstream (see the Blind Hunter row).
  - `[low]` `reject` Edge Case Hunter: a secret that matches no `Redact` shape stays raw in the trace — the ruling makes `Redact.Text` the one redactor; it is a pattern backstop by design.
  - `[low]` `patch` Edge Case Hunter: the take-failure warning is written without `Redact.Text` — applied in `Proposed` and `RaiseAsked` (the text is a constant today).
  - `[low]` `patch` Edge Case Hunter: the `key=` doc says "a letter" — applied: "an ASCII letter or digit" in the class doc and `BareKeyPattern`'s doc.

## Design Notes

### Ground truth on the feature branch (HEAD 9514d500; 23.2, 23.3, 23.5, 21.10, 21.11, 23.12, 36.1 and 36.2 merged)

| Kind | Raise (Lane A) | The row's dry run, as the `approval` payload carries it | Catalog key (Watch.cls) |
|---|---|---|---|
| roll back | diagnosis `rollback_setting` (Agent/Diagnosis.cls:34; Watch/SettingCause.cls) | `item`, `field`, `before` (now), `after` (old) (Approval.cls:147-150) | `incident.rollbackRequest` 1129 |
| undo | `ProposeFix` `undo_rollback`, also on a closed incident (UndoRollback.cls:26-28; Kind.cls:156-162) | the same keys, before old, after new | `incident.undoRollbackRequest` 1144 |

The incident payload carries `settingChange` and `gapMinutes` (Incident.cls:61-63, 116-134), and the card already draws the cause line from them (`settingCauseOf`). The other step-5 kinds (suspend, resume, reroute, partner warning) are 24.4b's to pin; the approval payload's redaction reaches them too and leaves their values as they are (Decided 8).

### Where a setting value reaches a person (redactor ruling, item 1; file:line)

| Surface | Fill site | Today | After |
|---|---|---|---|
| Web approval card, rail, `/api/v1/state`, answer response, approval live event | `Live/Payload/Approval.cls:148-149` (callers `Core/BridgeSink.cls:198,525`, `Web/Api.cls:830,1535`) | raw | `Redact.Text` |
| Web incident card and evidence panel, incident live event | `Live/Payload/Incident.cls:127-128` (callers `Web/Api.cls:1490`, `Watch/IncidentManager.cls:390,1445`) | raw (blank for a secret) | `Redact.Text` |
| `incident.rollbackRequest` {before} {after} (web chat, phone, Telegram) | `Watch/SettingCause.cls:277-278,283-284` via `Watch/Notice.cls:344` | raw | `Redact.Text` |
| `incident.undoRollbackRequest` {before} {after} | `Watch/SettingCause.cls:298-299,307-308` via `Watch/Notice.cls:243` | raw | `Redact.Text` |
| `result.settingRestored`, `result.rollbackUndone` {after} | `Watch/SettingCause.cls:337,347` via `Watch/Notice.cls:446`, from `Watch/IncidentManager.cls:1731` (the stored dry run's after) | raw | `Redact.Text` |
| `result.settingSavedNotApplied` {reason} | `Watch/SettingCause.cls:338,348` | redacted upstream (`Fix/Executor.cls:201,637`) | unchanged |
| Summary lines (`summary.requestedRollback`, `requestedUndoRollback`, `settingRestored`, `rollbackUndone`, `settingNotChanged`) | `Watch/Summary.cls:159-160,207-208` | no value (time, setting, target) | unchanged |
| Phone message store, Telegram send | `Channel/SimPhone/Out.cls:83-88` (`Data.SimMessage.Text`), `Channel/Telegram/Out.cls:174,212` | rendered from raw slots | rendered from redacted slots; no edit |
| Evidence pack to the model | `Watch/SettingCause.cls:169` | already redacted | unchanged |
| Digest, email, web chat bubbles | `Digest/NeedsYou.cls`, `Channel/Email/Out.cls:304`, `Channel/WebChat/Out.cls:51,82-83` | no value | unchanged |
| Telegram press reply, Telegram answer slots | `Channel/Telegram/In.cls:477-481`, `Core/AnswersIn.cls:111` | Field, Item, To, count only | unchanged |
| Persona proposal card (`Kind = "setting"`) | `Live/Payload/Approval.cls:120-125` | persona parts, not a production setting | unchanged (Decided 8) |

### Trace and logs (redactor ruling, item 4; file:line)

- **`Fix.Msg.DryRunResult.DryRun`** (Ens.Response) carries the raw `before`/`after` of the setting kinds: filled at `Fix/Executor.cls:192` from `RollbackSetting.cls:89-90` and `UndoRollback.cls:52-53`; received by `Watch/IncidentManager.cls` at 330-337 (async, `Proposed` 970) and 1176 (sync, chat ask), stored raw by `RaiseFix` at 1054. It is needed raw downstream (the store; `UndoRollback.Approved` 108-121 gives `Plan` the stored `after` to compare), so it carries the redacted values plus a `SecretHandoff` reference that IncidentManager takes on receipt (V5).
- **`OcuTalon.Msg.Notification.Slots`** carries the raw values for the four keys: approval notices built at `Watch/IncidentManager.cls:1422` (rollback) and on the ask path (undo), result notices at 1684; sent through `Tell` 1896 -> `SendNotice` 1862 -> Notify -> TelegramOut, SimPhoneOut, WebChatOut. Display only: fixed by the slot fill (granted).
- **`OcuTalon.Live.Event.Payload`** (persistent, not a message; `Live/Publish.cls:103-111`) stores the payload JSON: fixed by the payload redaction.
- No raw value in: `Fix.Msg.DryRun.Parameters` (`{"change": ref}`), `Fix.Msg.Execute` (ApprovalRef), `Fix.Msg.FixResult.Reason` (redacted at `Fix/Executor.cls:637`), `Bridge.Msg.ApprovalStart`/`ApprovalOutcome`/Workflow (Ref only), `Bridge.Msg.Request.Input` (the pack, redacted at `SettingCause.cls:169`), `Msg.Command.ProposeFix`/`CommandResult` (no values). The plan entry `{expect, value}` is passed in-process (`RollbackSetting.cls:187`), never in a message. The expiry job's argument is the reference only.
- **Logs and audit:** every log call on these paths already wraps its text in `Redact.Text` (`Watch/IncidentManager.cls` 1007, 1013, 1179-1214, 1566, 1712, 1886-1906; `Fix/Executor.cls` 201, 319-1354; `Fix/Run.cls` 234-389; `Watch/SettingHistory.cls` 44, 48), and their texts hold no value (refusal texts name setting, item and target only). The rollback's Action audit entry (`Fix/Executor.cls:785-831`) and the Approval entries (`src/bridge/cls/OcuTalon/Bridge/Approval.cls:569-619`) hold no value, and `Audit.Write` redacts anyway. No `$$$TRACE` or `$$$LOG` in the kinds, `SettingCause`, `Notice`, `Summary` or `Live`. No log line needs a change; `TestTokenValueRestoredRaw` pins it (`LogRowsHolding`).

### The hand-off's lifetime (V5 conditions; V6)

- An entry ends in one of three ways: IncidentManager takes it on receipt (both receive sites, before any early exit), the Rollback test helper takes it, or the expiry job discards it `VALUESSECONDS` after the offer. Only an answer that never reaches IncidentManager needs the expiry: a chat ask whose `SendRequestSync` gave up after `ASKSECONDS` (30), a production stopped in between, or an error thrown before the take.
- `SecretHandoff` itself has no lifetime (Code Map), and the spine's existing safety, "the route takes back any secret that is left once the submit has returned" (`ARCHITECTURE-SPINE.md:132`), does not fit here: the offerer (FixExecutor) answers before the taker can take. Hence the detached discard job in `Fix/Executor.cls`, with no edit of `SecretHandoff` (V6).

### Decided in-stage

1. The new strings are page constants in `INCIDENT_TEXTS`, as the panel's other labels are ("Cause", "Error"). No catalog key, because the panel is page-only (UX-DR78).
2. Row order: right after Cause. Item and setting names and values in mono; the time not in mono, as the "Failures by item" times show.
3. "Detected", not "Changed": `detectedAt` is when a check saw the change, so the text claims only that.
4. A secret's value rows and an empty value's row are left out, with no new "hidden" text. The target (Host or Adapter) is not shown, because the AC names item, setting, values and time.
5. (Moved to Story 24.4b: `AFTER_CLOSE_KINDS`.)
6. The new e2e spec lives in `e2e/rail/` (sign-in-2, which takes `--part`). `live cards` cannot be cut into calls of about 150 s. The rail user's session is cleaned in `finally`, as in rail-answer.spec.ts (23.12).
7. The redaction sits in `SettingCause` only (one private helper), because `Notice` only delegates the fill; `Watch/Notice.cls` stays unedited although granted. The empty checks keep reading the raw value, and `Redact.Text` never empties a non-empty value.
8. The approval payload redacts `Before`/`After` for every fix kind, not only the two setting kinds: one rule with no kind list, and it leaves "enabled"/"disabled" and dates as they are (Test.Live.Payloads :352, :850, :1154, :1172 stay green). The persona branch is not a production setting and stays as it is.
9. The `key=` shape is a pattern of its own, not a SENSITIVEKEYS name: a name there is suffix-matched in JSON keys, and `monkey`, `cacheKey` or `dedupKey` would turn sensitive across every log; `TestSensitiveKeys` pins 25 names. `=` only, so the prose "key: value" and JSON pairs keep their meaning. It sits in the `If kv` block with the other key rules (string values of JSON reach it through `Nested`). A prose "primary key = Ref" is redacted too (acceptable for a backstop).
10. A redacted value can be longer than the raw one (`token=ab` gives `token=[redacted]`); the payload parts' MAXLEN (1000 and 2000) is not enforced on JSON export, and the kinds refuse values over 1,000 characters (`RollbackSetting` `VALUEMAX`), so no cut is added. `TestShownRedacted` (d) confirms export with a 1,000-character token URL.
11. A failed hand-off take never stores a redacted dry run (that would change what `UndoRollback.Approved` gives `Plan` and lose the raw value); it is treated as a dry run that could not be worked out.
12. The take happens on receipt, before every early exit of `Proposed` and `RaiseAsked`, so that an answer IncidentManager drops (the incident moved on, a Reason, empty Targets) still ends its entry; the parsed raw object is the one the rest of the method uses, so the JSON is parsed once.
13. The Rollback helper is one override of `AskDryRun` in `Test/Watch/Rollback.cls` (all ten setting-kind call sites go through it), returning an unsaved clone: the fixture requests hold raw values, no entry is left, and the trace keeps the redacted answer. `Test.Watch.Case` stays unedited.
14. `TestValuesHandoff` lives in `Test.Watch.SettingCause` (granted; it needs no production, so it runs warm), not in the fresh-only `Test.Watch.Rollback`.
15. Condition 3 uses `BusinessPartner` (a string, MAXLEN 128, which `DropDefault` already cleans and `TestUndoDefaultGone` already drives as a System Default), not `RetryInterval` (numeric). `TestUndoSystemDefaultChanged` keeps its plain values as the byte-for-byte restore pin of DW-1366.
16. The panel's accessibility pins (F5's scans in both schemes, Tab to Show details) stay here with the rows they check; the undo card's focus order moves with V2.
17. The file name `step5-requests.spec.ts` and the case names F3b, F5, F5b and F7 are kept, so 24.4b adds F1 to F4 and F6 to the same file.
18. `multiple-goals` cleared: the panel rows need the redaction (V1's condition), and V5 is the redaction's trace half, so the story ships one thing: setting values shown redacted, including in the new rows.
19. `VALUESSECONDS` 60 (pending V6; a timeout, an implementation detail): twice `ASKSECONDS`, the longest a synchronous ask waits, and well above a queued async answer's normal wait. Too short turns a slow queue into "no fix proposed"; the raw value meanwhile is in memory only.

### Moved to Story 24.4b (re-plan rulings, SPLIT: YES)

- V2's closed-card undo: `incident-card.ts` `requests` draws an `undo_rollback` request card on a compact card (`AFTER_CLOSE_KINDS`, a `ReadonlySet` holding `undo_rollback`, mirroring `Fix.Kind.AskedClosed`).
- The implement stage's compact-state design note: compactness comes from the payload (`stateOf(incident().state)?.chip === 'closed'`), not from `view().compact` (circular, since `drawn` feeds the view); `IncidentContext` gains `drawn?: ReadonlySet<string>` so a compact card's `results` leave the drawn Refs out.
- V2's two pins: a closed card draws no other request kind; the rail's "Show in the chat" jumps to the undo request card.
- The matrix rows "Closed card, undo pending", "Closed card, other kinds" and "Closed card, undo answered".
- Old AC1 (each step-5 kind's own dry run, names, rail title, phone and Telegram), old AC2 (partner warning), old AC4 (answers, bands, phone Reject within 5 s, the closed-card undo) and old AC5's card part (Tab to the undo card's Approve; F6's scans).
- Playwright F1 to F4 (F3's plain rollback and undo rows as cross-surface pins) and F6, and `TestStepFiveRequests` in `Test/Channel/TelegramOut.cls`, with their mutations (old AC1, AC2, AC4).
- The V3 files only 24.4b needs: `approval-sources.test.mjs:316` (the `requests` regex) and `incident-sources.test.mjs` (the drawn Refs reach the context).
- EXPERIENCE.md's V2 sentence (applied by the lead at the 21:00Z rulings) describes 24.4b's behaviour; until 24.4b merges, a closed card draws no request card.

### Governing ADs (Rule 6)

- AD-12: payloads with matching interfaces; the page decides nothing.
- AD-15: the incident's states; untouched here.
- AD-16: the dry run is the row's: the stored dry run stays raw.
- AD-19 and AD-1: a value kept out of messages travels by `SecretHandoff` reference (the step-4 pattern), taken once, with a lifetime (V6).
- AD-31 and the Consistency Conventions' Redaction row: one redactor, `OcuTalon.Bridge.Redact`, as the backstop.
- AD-29 and AD-33: lane files; the redactor ruling's grant and V5 are one-time exceptions.
- AD-32: the server renders the phone and Telegram text; producers never render.
- AD-25: the online demo.
- For the lead (Rule 20): the grant and V5 are one-time AD-33 exceptions ("Story 24.4a changes Lane A's `Live/Payload/Incident.cls` `Change`, `Watch/SettingCause.cls`, `Bridge/Redact.cls`, `Fix/Executor.cls`, `Watch/IncidentManager.cls`, `Fix/Msg/DryRunResult.cls` and their tests, under the redactor and re-plan rulings; the ownership tables don't change"); the Redaction convention gains "a production setting's value shown to a person, or carried in a message, goes through the redactor on the server; the stored dry run and the value written stay raw"; and, once V6 is ruled, AD-19's hand-off bullet (`ARCHITECTURE-SPINE.md:709`) gains the dry-run answer's reference and its lifetime.

### Integration ACs, Consumes, Extend (Rules 1, 2)

- **Integration ACs:** AC3 (a real `SettingChange` row through `Incident.FromRow` and `/api/v1/state` to the panel); AC2's F5b (the same path, redacted), F3b (a seeded request row through `Approval.FromRow` to the card), F7 (the real `AskedSlots` fill through Notify to the phone page) and `TestRedactedValue` (the same fill through TelegramOut to the CI mock); AC4, AC5 and AC7 (the running production end to end).
- **Consumes:** 23.3 (`settingChange`, `gapMinutes`, `incident.settingChangeCause`, the rollback and undo kinds and their slots); `Bridge.Redact.Text`; `Core.SecretHandoff`.
- **Consumed-by:** none (no service introduced; `OfferValues`/`TakeValues` are helpers of the dry-run answer, used by FixExecutor, IncidentManager and the Rollback test helper). Story 24.4b builds on the redacted payload and the spec file.
- **Extend, don't copy:** the rows extend `panelOf`; the redaction reuses `Bridge.Redact.Text` (no second redactor) and `Core.SecretHandoff` (no second hand-off; the expiry only calls its `Discard`); the detached job follows `SettingsOps.UpdateIn`'s `Job`; the Telegram method reuses `TestButtons`' helpers (`Request`, `FixtureSlots`, `SentTo`); the leak checks reuse `TraceLeaks` and `LogRowsHolding`; the System Default test reuses `RollBackDefault`'s and `TestUndoDefaultGone`'s steps (`SaveDefault`, `Tick`, `ChangeRows`, `Fixture`, `Run`); `askedSlots` reuses `irisScript`; the spec reuses `support/approvals.ts` and `support/iris.ts`. No helper is copied.

### Contention (plain-union rule: whoever pushes second integrates and flags)

- Lane B (`OCT-epic23`, Story 23.4's DW-1396 rework; 23.8 is still backlog): `Live/Payload/Incident.cls` adds `Do ..Paged(payload, row)` right after `Do ..Change(payload, row)` and a new `Paged` method directly above `Change`'s doc comment. This story edits `Change`'s doc (114-115) and body (127-128): adjacent hunks, a likely textual conflict on the doc lines. Ruled (re-plan rulings, Contention): at integrate, union the two and keep both, and flag the hunk. `Watch/IncidentManager.cls`: lane B's hunks are at 311, 1413, 1467, 1854 and 2010+; V5's edits are at 970-1000 and 1166-1200: no overlap expected. Lane B also edits `Channel/Telegram/Out.cls`, `Msg/Catalog/Watch.cls`, `Test/Live/Payloads.cls` and `Test/Msg/Catalog.cls`, which this story does not touch (its payload pins are in `Test.Watch.SettingCause` for that reason).
- Lane C (`OCT-epic21-dw1205`): `Fix/Executor.cls` is under the plain union (re-plan rulings, V5); this story's hunks are the class doc's DryRun bullet, `DryRun` 181-205 and three new class methods with one parameter. Lane C also edits `Test/Fix/Asked.cls` and `Test/Fix/PartnerDraft.cls`, not touched here; `Test.Fix.Asked`'s `DryRunResult` doubles (240-248) carry no `values` key, so `TakeValues` leaves them as they are; run it as a regression.

### Size and split (Rule 5)

24.4a is the split's first half. 11 IRIS files (5 source, 1 doc-only, 4 test classes, the bridge redactor) and 5 web files (one source, two unit tests, one e2e helper, one new spec with four cases). Still above the template's token aim (`oversized`); one goal (Decided 18).

### Ledger (Rule 17)

`LEDGER slice 24-4a-show-setting-values-redacted-everywhere-and-the-setting-chan` and `slice 24-4b-show-the-new-fixes-partner-warnings-and-the-closed-card-undo` are empty: no entry to address. Related, not owned: DW-1378 (escalated, owner burndown): a done undo's band reads `settingChange.newValue`, not the dry run's after; the fix needs a new request-part field (Lane A's payload), so this story declines it (after this story that value is redacted on the server too).

### Release and online demo

Target 1.0.12, its blocker. On the online demo the setting history is off (36.1 V4), so no incident names a change, no rollback or undo is raised (ONLINESHARED), and none of the new rows, redacted values or hand-off entries ever shows there. The other cards are as today.

## Public text

**NEW** (V1; page constants in `INCIDENT_TEXTS`, evidence panel only):
- "Setting change"
- "{setting} on {item}"
- "Old value"
- "New value"
- "Detected"

**Existing server text, newly visible by the redactor ruling:** `[redacted]` (`Bridge.Redact` `REDACTED`) inside a shown value on the card, the panel, the phone and Telegram; and, when a value cannot be checked, `[redacted: the text could not be checked]` (`UNCHECKED`). Covered by the ruling (V4).

**Existing, reused verbatim (no change):**
- "Before" and "After": `APPROVAL_TEXTS`; UX-DR77.
- "The feed broke {minutes} after this setting changed: {setting} on {target}, at {time}.": Watch.cls:1155 (23.3's gate; EXPERIENCE.md:1163).
- The texts of `incident.rollbackRequest`, `incident.undoRollbackRequest`, `result.settingRestored` and `result.rollbackUndone` (Watch.cls 1129, 1144, 1165, 1182): unchanged.

## Veto items

- **V1 (APPROVED 21:00Z): public text.** The five evidence-panel strings above; the condition is superseded by the redactor ruling.
- **V2 (APPROVED 21:00Z): card behaviour.** Moved to Story 24.4b (re-plan rulings, SPLIT).
- **V3 (GRANTED 21:00Z): footprint.** 24.4a uses `web/scripts/incident-view.test.mjs` and `ux-strings.test.mjs`; `incident-sources` and `approval-sources` move to 24.4b.
- **GRANTED by the redactor ruling** (Lane A and bridge files):
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls` (`Change`; Lane A).
  - `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls` (`RollbackSlots`, `UndoSlots`, `ResultSlots` and a private helper; Lane A). `Watch/Notice.cls` is granted and not edited.
  - `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (the `key=` pattern and its doc; bridge, Lane A).
  - Their tests in Lane A test classes: `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls` (`TestSettingValueShapes`, `TestIdempotent`'s list, the doc), `src/ocutalon/cls/OcuTalon/Test/Watch/SettingCause.cls` (`TestShownRedacted`, `TestValuesHandoff`), `src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls` (the ruling's restore pin).
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` is named by the grant and is already in Epic 24's `paths_hint` (Lane B).
- **V4 (CONFIRMED 22:00Z): visible marker.** `[redacted]` and `UNCHECKED` reach the card, the panel, the phone and Telegram as part of a value; the bare `key=` shape is approved with its pin.
- **V5 (GRANTED 22:00Z, with conditions).** `Fix/Executor.cls`, `Watch/IncidentManager.cls`, `Fix/Msg/DryRunResult.cls` (doc only) and the `Test/Watch/Rollback` helper. Each condition has its pin and mutation: (1) taken entry deleted and untaken entry expires: AC6, `TestValuesHandoff`; (2) the run's `DryRunResult` and `Notification` bodies hold `[redacted]` and not the token: AC5, `TestTokenValueRestoredRaw`; (3) the System Default undo restores from the stored raw value byte for byte and DW-1366's pin holds: AC7, `TestUndoSystemDefaultTokenRaw` and `TestUndoSystemDefaultChanged`. No message property, table, column or storage changes; `SecretHandoff` is read only.
- **V6 NEW: the hand-off's lifetime (security posture: how a secret is handled; AD-19's wording, Rule 20).** V5's condition 1 says an untaken entry "expires within SecretHandoff's existing limit", but `SecretHandoff` has no lifetime: `Put` creates a named `$SYSTEM.Event` resource that lives until `Take` or `Discard` deletes it or the instance shuts down (`Core/SecretHandoff.cls` 5-10, 52-73; `irislib/%SYSTEM/Event.cls:78`); its only time limit is `Take`'s wait (`timeoutSec`, default 5 s), which the spine calls "an expired wait" (`ARCHITECTURE-SPINE.md:709`). Its callers so far are safe because the offerer discards after the submit returns (spine :132); FixExecutor cannot, because it answers before IncidentManager takes. An answer that never reaches IncidentManager (a chat ask that timed out after 30 s, a stopped production, an error before the take) would leave the raw value in shared memory until a restart.
  - Recommended (planned in Tasks): FixExecutor gives each offer a lifetime of its own: a detached job (`Fix.Executor.Expire`) discards the entry `VALUESSECONDS` (60) after the offer; no `SecretHandoff` edit. Pin: AC6 (c).
  - Alternatives: (b) add an optional lifetime to `SecretHandoff.Put` (Lane B Core, AD-19; every caller could use it; `Test.Core.SecretHandoff` and the spine change); (c) no lifetime: an untaken entry stays in memory until the instance restarts (it is never in a global, message, log or trace), and condition 1's expiry half is dropped.
  - If (b) is ruled, Tasks' `Expire` moves into `SecretHandoff` and AC6 (c) pins it there; if (c), `Expire` and AC6 (c) are dropped. Nothing else changes.
- No new payload field, route, catalog key, table, column, role, grant, dependency or outward action.

## Verification

Every IRIS call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s4iw`; the fresh tag is `e24s4i`. Run IRIS MCP lookups only on `ocutalon-slot-d`/`OCUTALON`.
- Each line below is one foreground call (`timeout: 600000`) that ends inside about 150 s. One test class (or one `Class:Method`) per call. Never two test calls in one message.
- The web suite and each Playwright part are calls of their own. After any `web/` change, `ci/iris.sh build` comes before a browser unit.

**Shared surfaces:**
- `Redact.Text`'s output (used by logs everywhere). Every test that asserts it: `Test.Bridge.Redact` (all methods; `TestSensitiveKeys` :50 pins 25 names, unchanged); `Test.Bridge.Steps` (392, 437, 501), `Test.Bridge.Gate` (1789), `Test.Bridge.Runner` (303, 716, 777), `Test.Bridge.Audit` (233, 267, 361), `Test.Bridge.StepsText`, `Test.Agent.Steps` (253, 302), `Test.Agent.RenderMemory` (290, 383), `Test.Channel.TelegramOut` (`TestButtons` 889-891, `TestToolCallTooLong` 940-948), `Test.Core.BridgeSink` (918, 1159), `Test.Checks.Runs` (1708), `Test.Fix.DryRun` (526), `Test.Watch.Poller` (458), `Test.Watch.Evidence` (189, 213), `Test.Watch.NoticeText` (755, 768), `Test.Eval.Cases` (`FileProblems` 921-926, the fixed point over `eval/**`), `Test.Eval.Record` (560, 869, 1157), `Test.Tools.Reminders` (760), `Test.Demo.PartnerTrigger` (64). No fixture of them holds a bare `key=` (searched: Test classes, docker/tests, ci, web/scripts, web/e2e, eval); the e2e `redactLine` (`web/e2e/support/diagnose.ts:236`) is a separate test helper and unaffected.
- The values of the setting kinds' views (plain values, unchanged by redaction): `Test.Fix.Asked` 177, `Test.Fix.ItemKinds` 406-452, `Test.Watch.Rollback` 421, 609, 617-662, `Test.Watch.SettingCause` `TestPayload` 377-383, `Test.Channel.TelegramApproval` 414-420, `Test.Live.Payloads` 352, 850, 1154, 1172, `Test.Watch.Summary` 790, `Test.Msg.Catalog` 1861-1866, `approval-card.spec.ts` A14 472-494.
- The shape of `DryRunResult.DryRun` for the setting kinds (V5): every setting-kind `AskDryRun` in `Test.Watch.Rollback` (404, 415, 463, 526, 668, 685, 693, 712, 776, 937; through the new override), `Test.Watch.Case` `AskDryRun` 2257, `Test.Watch.IncidentProbe` `AskDryRun` 193 and `Test.Fix.Asked`'s doubles 240-248 (no `values`), and `Test.Eval.Record`'s rollback cases (through IncidentManager).
- `$SYSTEM.Event` hand-off resources: none may remain after a test (each offered entry is taken, discarded or expires inside the test).
- `INCIDENT_TEXTS` and the `ux-strings` inventory and `ruled` table; the panel rows of `incident-view.test.mjs` 380-437.
- The RAIL user's session and phone feed (`rail.spec.ts` R1 to R19 expect them empty); TelegramOut's mock call log (each method its own chat id).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` -- passes.
- (once) `npm --prefix web run build` -- passes, with `payloads.mjs --check`, `catalog.mjs --check` and no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Bridge.Redact` -- `CLASS ... passed`.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Watch.SettingCause` -- passed.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- passed.
- (once) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Fix.Asked`, then (once) the same for `OcuTalon.Test.Fix.ItemKinds`, `OcuTalon.Test.Live.Payloads` and `OcuTalon.Test.Core.SecretHandoff` -- passed (the V5, payload and hand-off regressions).
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh down`.
- (once each, fresh) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh class OcuTalon.Test.Watch.Rollback:TestTokenValueRestoredRaw`, then `...:TestUndoSystemDefaultTokenRaw`, `...:TestUndoSystemDefaultChanged`, `...:TestUndoDefaultGone`, `...:TestIncidentNamesTheChange` and `...:TestUndoAfterClose` -- each passed. A method that cannot end inside about 150 s is left to CI's `shards` group and recorded so.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- passes on a fresh stack.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh build` -- the image and the web bundle.
- (loop) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh live sign-in-2 --part k/N`, for the part that holds `rail/step5-requests.spec.ts`: find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` into the scratch folder, then `node web/scripts/e2e-part.mjs`; choose N so the part ends inside about 150 s (about 93 s of it is setup). Then (once) the part that holds `rail/rail-answer.spec.ts` and `rail.spec.ts`, as the shared-session regression. All pass.
- (once) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-redact-shapes.sh` -- pass.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh teardown`.
- (once, CI) `live:cards` (A9 and A12 to A14 stay green), the `shards` groups (every class of the shared surfaces above, `Test.Fix.DryRun` and the whole `Test.Watch.Rollback`).
- (once, the lead) Fresh-environment check: the `--part` holding the spec, forward and `--reverse` (Rule 19), and `ci/iris.sh shard lane-a --part k/n` and `lane-b --part k/n` holding `Test.Bridge.Redact`, `Test.Watch.SettingCause` and `Test.Channel.TelegramOut`, forward and reversed.

**Mutations (Rule 19; one per AC at least; record each as `mutation: … → …`; revert and check that `git status --short` and `git diff --stat` are unchanged):**
- AC1: remove the new `key=` pattern → `TestSettingValueShapes` red; drop the "not preceded by" guard → its `monkey=1` case red.
- AC2: copy `dry.after` raw in `Approval.cls` → F3b and `TestShownRedacted` (b) red. Copy `change.OldValue` raw in `Incident.cls` → F5b and (a) red. Return `..Text(value)` from the `SettingCause` helper → F7, `TestRedactedValue` and (c) red.
- AC3: make `panelOf` skip the setting rows → F5 and the `incident-view.test.mjs` panel cases red. Drop the new `ruled` entry → `ux-strings.test.mjs` red. Set `.label` in `evidence-panel.ts` to `color: var(--surface)` → F5's dark-scheme `scanContrast` red.
- AC4: have IncidentManager store the dry run without `TakeValues` (redacted values) → `TestTokenValueRestoredRaw`'s stored-raw assertion red. Have `RollbackSetting.Restored` return `Redact.Text(row.OldValue)` → its byte-for-byte assertion red.
- AC5: have `Fix/Executor.cls` `DryRun` keep the raw before/after in the message → `TestTokenValueRestoredRaw`'s `DryRunResult` body assertion and `TraceLeaks` red. Return `..Text(value)` from the `SettingCause` helper → its `Notification` Slots assertion red.
- AC6: take the `$SYSTEM.Event.Delete` out of `SecretHandoff.Take` (line 61; Lane B's file: revert `cmp`-identical, never lands) → `TestValuesHandoff` (b) red. Take the `Job` out of `OfferValues` → (c) red. Take the `Job` out of `OfferValues` → `TestValuesExpireDefault` red (the 60 s discard). V6 missing entry: let IncidentManager go on with the redacted dry run when the take fails (ignore the take's status) → `TestTakeMissingNoRequest` red.
- AC7: have `TakeValues` leave the redacted values in place (remove `values` only) → `TestUndoSystemDefaultTokenRaw` red (the undo skips with `result.settingChangedSince`; the effective value stays alpha).

**Manual checks:** none beyond the commands.

### Implement stage record (2026-11-15, lane D)

Mutations, each applied to a copy-checked file, observed red and restored byte for byte (`cmp` identical); none lands:
- mutation: the `key=` pattern's name made unmatchable (`BareKeyPattern` `key` -> `zzkey`) -> `Test.Bridge.Redact:TestSettingValueShapes` red (the `?key=`, `key = `, `KEY=`, quoted and bracket cases).
- mutation: the "not preceded by" guard of `BareKeyPattern` dropped -> `TestSettingValueShapes` red (`monkey=1`, `cacheKey=1`, `dedup-key=1`, `dedup_key=1`, `a.key=1`, `?monkey=`).
- mutation: `Approval.cls` copies `dry.after` raw -> `Test.Watch.SettingCause:TestShownRedacted` (b) red, and live F3b red.
- mutation: `Incident.cls` copies `change.OldValue` raw -> `TestShownRedacted` (a) red, and live F5b red.
- mutation: the `SettingCause` helper `Shown` returns `..Text(value)` -> `TestShownRedacted` (c), `Test.Channel.TelegramOut:TestRedactedValue`, live F7 and `Test.Watch.Rollback:TestTokenValueRestoredRaw` (the `Notification` Slots, phone text, `TraceLeaks`, live event and phone message checks) red.
- mutation: `panelOf` skips the setting rows -> three new `incident-view.test.mjs` cases red.
- mutation: the new `ruled` entry dropped -> `ux-strings.test.mjs` "has an entry for every inventory string" red.
- mutation: `evidence-panel.ts` `.label` colour set to `var(--surface)` -> live F5's contrast scan red (the light scheme is scanned first and fails first; the dark scan is behind it).
- mutation: `Received` takes no values (removes `values` only) so IncidentManager stores the redacted dry run -> `TestTokenValueRestoredRaw` stored-raw assertions red.
- mutation: `RollbackSetting.Restored` returns `Redact.Text(row.OldValue)` -> `TestTokenValueRestoredRaw` byte-for-byte assertion red.
- mutation: `Fix.Executor.DryRun` skips `OfferValues` (the raw values stay in the message) -> `TestTokenValueRestoredRaw` `DryRunResult` body assertion and `TraceLeaks` red.
- mutation: `Core/SecretHandoff.Take` without its `$SYSTEM.Event.Delete` -> `TestValuesHandoff` (b) red. The pin as first written (a second `Take` fails) stayed green because the first take had consumed the queued message; (b) now also asserts that the entry's event resource is gone (`Held`), and so do (c) and `TestValuesExpireDefault`.
- mutation: the `Job` taken out of `OfferValues` -> `TestValuesHandoff` (c) and `TestValuesExpireDefault` (the 60 s discard) red.
- mutation: IncidentManager ignores the take's status (`Set taken = 1`) -> `TestTakeMissingNoRequest` red (a request is raised, a stored dry run holds the marker, no refusal notice).
- mutation: `TakeValues` leaves the redacted values in place -> `TestUndoSystemDefaultTokenRaw` red (the undo skips as changed again; the effective value stays alpha).

Notes. The missing-entry pin forces the discard with a seam in `Fix.Executor`: `Lifetime` reads `^IRIS.Temp.OcuTalon.Fix("valuesSeconds")` (nothing sets it in the product; 0 is an entry that has already expired when IncidentManager takes it). The chat-ask branch of `RaiseAsked` is pinned by `TestAskedTakeOnReceipt` (review pass, below). Runs that passed: fresh (e24s4i) `Test.Watch.Rollback:TestTokenValueRestoredRaw`, `:TestTakeMissingNoRequest`, `:TestUndoSystemDefaultTokenRaw`, `Test.Watch.SettingCause` (whole class, 67 s, the 60 s pin inside), `Test.Channel.TelegramOut`; live `sign-in-2` parts 17/26 (step5-requests F3b, F5, F5b and F7, with reminder and session specs: 17 passed), 14/26 (rail-answer RA1, RA2 and phone: 8 passed) and 15/26 (rail R1 to R19: 19 passed); warm (e24s4iw, production started with the final code) `Test.Bridge.Redact`, `Test.Watch.SettingCause`, `Test.Channel.TelegramOut`, `Test.Fix.Asked`, `Test.Fix.ItemKinds`, `Test.Live.Payloads`, `Test.Core.SecretHandoff` and `Test.Watch.Rollback:TestUndoSystemDefaultChanged`, `:TestUndoDefaultGone`, `:TestIncidentNamesTheChange`, `:TestUndoAfterClose`; `npm --prefix web test` (2156 pass), `npm --prefix web run lint`, `ci/iris.sh build`, `docker/tests/test-class-rules.sh` and `docker/tests/test-redact-shapes.sh`. Not run: `Test.Watch.Rollback`'s four regression methods fresh, `Test.Fix.DryRun`, the shard groups and `live:cards` (CI).

### Review pass additions (2026-11-15)

- mutation: `RaiseAsked`'s `If 'taken` refusal block made `If 0` (a failed take ignored on the chat ask) -> `Test.Watch.SettingCause:TestAskedTakeOnReceipt` red (the ask is raised, not refused with NOSTART; a request and a Notification follow); reverted, `cmp` identical.
- mutation: `Fix.Executor.Expire` waits `seconds/60` instead of `seconds` -> `TestValuesExpireDefault` (held at 50 s, gone between 59 and 75 s) and `TestValuesHandoff` (c2, held one second into a 5 s lifetime) red; reverted, `cmp` identical. The first-pass pins of the lifetime were upper bounds only.
- New and changed tests of the pass: `TestAskedTakeOnReceipt` (the take on the chat ask, through the probe host of `Test.Fix.Asked`; taken: raw stored dry run, redacted notice slots; entry gone: refused with NOSTART, nothing raised or sent), `TestValuesHandoff` (c) polls with a deadline and (c2) takes within the lifetime, `TestValuesExpireDefault` polls and bounds the discard between 59 and 75 s, `WaitGone` helper. Runs after the patches: warm (e24s4iw) `Test.Watch.SettingCause` (64 s, the 60 s pin inside), `Test.Fix.Asked`, `Test.Bridge.Redact`; fresh (e24s4i) `Test.Watch.Rollback:TestTakeMissingNoRequest`.
- Lead's verification run of the whole list after the implement stage (all passed): `npm --prefix web test` (2156), lint, build; warm `Test.Bridge.Redact`, `Test.Watch.SettingCause`, `Test.Channel.TelegramOut`, `Test.Fix.Asked`, `Test.Fix.ItemKinds`, `Test.Live.Payloads`, `Test.Core.SecretHandoff`, `Test.Fix.DryRun`, `Test.Watch.Incidents`; fresh `Test.Watch.Rollback:` `TestTokenValueRestoredRaw`, `TestTakeMissingNoRequest`, `TestUndoSystemDefaultTokenRaw`, `TestUndoSystemDefaultChanged`, `TestUndoDefaultGone`, `TestIncidentNamesTheChange`, `TestUndoAfterClose`, and `Test.Channel.TelegramOut`; `live sign-in-2 --part 17/26` (F3b, F5, F5b, F7: 17 passed); `test-class-rules.sh` and `test-redact-shapes.sh`. Not run (left to CI): the `shards` groups, `live:cards`, the fresh forward-and-reverse check of Rule 19. B13 (DW-1388) did not run in any part run and went red nowhere.

### QA stage additions (2026-11-15, lane D)

Gaps found against the ACs and the matrix: (1) the take on receipt "before any early exit" had no pin in `Proposed` or `RaiseAsked` (the existing mutations all ignore the take's status, none move the take); (2) the later round's refusal in `Proposed` (the review pass rejected it as untested); (3) the summary line and digest paths had no pin that a token-bearing setting change leaves them value-free; (4) the undo request's Before/After (the token is the undo's Before) had no end-to-end pin through the real runtime, and the phone page checks of 24.4a were negative only (no token) with no positive check that the marker reaches the phone message.

New tests, all in this story's footprint (tests only, no product code): `Test.Watch.SettingValues` (new class, warm, on the probe host of `Test.Fix.Asked`: `TestTakenBeforeAnEarlyExit`, `TestLaterRoundMissingEntry`, `TestSummaryHoldsNoValue`) and `Test.Watch.Rollback:TestUndoRequestTokenRedacted` (fresh; a real rollback, then the undo asked by a real `ProposeFix` to IncidentManager, with the phone messages of both requests read through `PhoneText`).

Mutations, each applied, observed red, reverted and compared with `cmp` against a scratch copy (identical); none lands:
- mutation: `Watch/IncidentManager.cls` `Proposed` takes the values after its early exits (the `Received` call moved to just before `If 'taken`) -> `Test.Watch.SettingValues:TestTakenBeforeAnEarlyExit` red (first round movedon, reason, targets; later round stale, closed, reason, targets: the entry is still held).
- mutation: `RaiseAsked` takes the values after its Reason check (`Received` moved to just before `If 'taken`) -> `TestTakenBeforeAnEarlyExit` red (chat ask, reason and targets).
- mutation: `Proposed`'s refusal made `If 'taken && 'later` (a failed take ignored in a later round only) -> `TestLaterRoundMissingEntry` red (a request holding the redacted dry run is raised, a notice is sent, AskingSince is not the refusal's, no LOGLATER NOSTART warning); the first-round pin `TestTakeMissingNoRequest` takes the `later` 0 branch, which this mutation leaves as it is.
- mutation: `Watch/Summary.cls` adds the raw `after` of the request's dry run as a slot of the `summary.requestedRollback` line -> `TestSummaryHoldsNoValue` red (the token is in the summary's slots, and so is the plain value).
- mutation: `Live/Payload/Approval.cls` `part.Before = dry.before` (raw) -> `Test.Watch.Rollback:TestUndoRequestTokenRedacted` red (the undo request's approval payload shows the token; the live event payload holds it). The earlier mutation of `part.After` could not catch this: the token is the undo's Before.
- mutation: `Watch/SettingCause.cls` `UndoSlots` sets `before` from `..Text(before)` (unredacted) -> `TestUndoRequestTokenRedacted` red (the notice's slots, its text, the undo request's phone message, the Notification body, the trace leak scan, the live event and the phone message all hold the token).

Runs: warm (e24s4qw) `Test.Watch.SettingValues` passed (4 s) with the final files and again after each revert; fresh (e24s4q) `Test.Watch.Rollback:TestUndoRequestTokenRedacted` passed (23 s inside a 153 s call); `bash docker/tests/test-class-rules.sh` passed; `ci/iris.sh classes` lists the new class in a shard; `ci/warm.sh down` ran. The throwaway tests discard every entry they offer (4 s lifetime, because each offer starts a detached job and with a 30 s lifetime the later offers of one test (after about seven) could not start their job: `OfferValues` refused it with "could not be started"), and remove the rows and warnings they make.

Not covered, by design: the digest (`Digest/NeedsYou`) reads only the incident's and the requests' names and times, so it has no value path to pin; the closed-card undo and the cross-surface pins stay Story 24.4b's. B13 (DW-1388) did not run in this stage.

### Code review additions (2026-11-15, lane D)

- mutation: `Fix.Executor.Lifetime` without its upper bound (`$Number(..., "I", 0)`) -> `Test.Watch.SettingCause:TestValuesLifetime` red (600 and 61 kept); reverted, `cmp` identical.
- mutation: `Lifetime`'s fallback `1` for a value it refuses -> `TestValuesLifetime` red (600, 61, -1); and the global's default `1` (`$Get(..., 1)`) -> red ("with no test global the lifetime is 60 seconds"); each reverted, `cmp` identical.
- mutation: the escaped-quote alternative of the bare `key=` rule removed from `Bridge/Redact.cls` `PatternList` -> `Test.Bridge.Redact:TestSettingValueShapes` red (the escaped-quote case); reverted, `cmp` identical.
- mutation: `Watch/SettingCause.cls` `UndoSlots` sets `before` from `after` -> `Test.Channel.TelegramOut:TestRedactedValue` red, now in its plain half too (the text lacks `LegacyRouter`); reverted, `cmp` identical.
- Runs: warm (e24s4crw) `Test.Watch.SettingCause` (whole class, 63 s), `Test.Bridge.Redact`, `Test.Channel.TelegramOut` (whole class), `Test.Watch.SettingValues`, `Test.Watch.Rollback:TestUndoSystemDefaultChanged`; fresh (e24s4cr) `Test.Watch.Rollback:TestTakeMissingNoRequest`, `ci/iris.sh build`, `live sign-in-2 --part 17/26` (F3b, F5, F5b, F7 and 13 more: 17 passed); `npm --prefix web run lint`. B13 (DW-1388) did not run in this stage.

## Auto Run Result

Status: done
Blocking condition: none

Summary: setting values are shown redacted on every display path through the one server redactor, `OcuTalon.Bridge.Redact.Text` (the approval payload's rollback and undo Before/After, the incident payload's `settingChange` Old/NewValue, the slots of `incident.rollbackRequest`, `incident.undoRollbackRequest`, `result.settingRestored` and `result.rollbackUndone`), and the evidence panel lists the setting change (V1's five strings; the value rows are left out for a credential or an empty value). `Redact.Text` gains the bare `key=` shape. The stored dry run, the `SettingChange` row and the value a rollback or undo writes stay raw. The setting kinds' `DryRunResult` carries redacted values and a `Core.SecretHandoff` reference (`Fix.Executor.OfferValues`); `IncidentManager` takes it on receipt, before any early exit, in `Proposed` and `RaiseAsked`, and stores the raw values; a detached job discards an untaken entry after `VALUESSECONDS` (60 s). V6's added condition holds: a take that finds no entry raises no request and takes the existing refusal path with the kind's NOSTART, so a redacted value is never stored as raw.

Files changed:
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`: the bare `key=` pattern and its doc.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: `OfferValues`, `Expire`, `TakeValues`, `IsSettingKind`, `Lifetime` (the test seam of the forced-discard pin), `VALUESSECONDS`, `TAKESECONDS`.
- `src/ocutalon/cls/OcuTalon/Fix/Msg/DryRunResult.cls`: doc only.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: `Received` (the take on receipt), `NoStart`, the refusal on a failed take in `Proposed` and `RaiseAsked`.
- `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls`: the `Shown` helper in the four notice keys' slot fill.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` and `Incident.cls`: Before/After and Old/NewValue through `Redact.Text`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`, `Test/Watch/SettingCause.cls`, `Test/Watch/Rollback.cls`, `Test/Channel/TelegramOut.cls`: the pins (`TestSettingValueShapes`, `TestShownRedacted`, `TestValuesHandoff`, `TestValuesExpireDefault`, `TestAskedTakeOnReceipt`, `TestTokenValueRestoredRaw`, `TestTakeMissingNoRequest`, `TestUndoSystemDefaultTokenRaw`, `TestRedactedValue`, and the `AskDryRun` override).
- `web/src/app/incidents/incident-view.ts`, `web/scripts/incident-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/support/iris.ts`, `web/e2e/rail/step5-requests.spec.ts` (new): the panel rows, their unit pins, the `askedSlots` helper and F3b, F5, F5b, F7.

Review: 32 findings from four layers (high 0, medium 1, low 26, false 5, maybe-false 0). Patches applied: 5 entries (the chat-ask take test, the lifetime's lower bound, polling instead of fixed sleeps, the take-failure warning through `Redact.Text`, the `key=` doc). Deferred: none. Rejected with reasons (26 entries): see the Review Triage Log; the main ones are by-design under a ruling (the 60 s idle job, the 60 s queue limit, the redactor being the one pattern backstop, the seam for the forced-discard pin) and spec-bound scope (all fix kinds' Before/After, the pins as named).

Follow-up review recommended: false (one medium patched, no high; the patches are tests and a log wrapper).

Verification: see `## Verification`, "Implement stage record" and "Review pass additions": the web suite (2156), lint, build with `payloads.mjs --check`; the warm and fresh IRIS classes and methods listed there; `live sign-in-2` parts 17/26, 14/26 and 15/26 (F3b, F5, F5b, F7 and the rail regression); `test-class-rules.sh`, `test-redact-shapes.sh`; 17 mutations observed red and reverted `cmp`-identical, the V6 pins among them (missing entry, 60 s discard, normal take, trace bodies after a rollback) and the token-URL pins on card, phone, Telegram and panel. B13 (DW-1388) did not go red.

Residual risks: (1) `Redact.Text` re-serializes a setting value that is itself a JSON text (`[1, 2]` is shown as `[1,2]`); display only, the stored and written values are raw. (2) The later round's refusal in `Proposed` (`later` 1) shares the first-round branch and has no test of its own. (3) `Fix.Executor.Lifetime` is a test seam in a product class (a `^IRIS.Temp` global that only a test sets). (4) The shards groups, `live:cards` and Rule 19's forward-and-reverse fresh check are left to CI and the lead. (5) The 60 s lifetime means an answer that waits over 60 s in a busy IncidentManager queue is refused as "couldn't change the setting" (the safe side).
