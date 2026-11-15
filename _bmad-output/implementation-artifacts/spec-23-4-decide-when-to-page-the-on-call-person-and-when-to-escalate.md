---
title: 'Story 23.4: Decide when to page the on-call person and when to escalate to the backup'
type: 'feature'
created: '2026-11-15'
status: 'done'
baseline_revision: 'd0fb1e1d3d2077257ece724d92385dbc33a91184'
baseline_commit: 'd0fb1e1d3d2077257ece724d92385dbc33a91184'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-3-name-the-setting-change-behind-an-incident-and-offer-its-rol.md'
warnings: [oversized]
deferred:
  - summary: >-
      The AC14 template branch (the @if/@else of web/src/app/settings/on-call-section.ts) has no demonstrated mutation; only the text constant was mutated.
    evidence: |-
      web/e2e/settings/on-call.spec.ts O1 pins that the telegramOnly line shows when pagesBuilt is true, but it needs a live sign-in part and was not run with a template mutation in this story.
    location: >-
      web/src/app/settings/on-call-section.ts
    severity: low
  - summary: >-
      Test.Watch.PagingLive TestEscalationAsk asserts the not_built answer of the escalation SetReminder and goes red when Story 24.3 builds the escalation timer.
    evidence: |-
      ReminderOps answers Kind escalation with Ok 0 not_built until 24.3 (Test.Schedule.Reminders TestEscalationNotBuilt pins the same); 24.3 replaces the probe fixture and this assertion (Consumed-by).
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Watch/PagingLive.cls
    severity: low
  - summary: >-
      web/e2e/api/incident-page.spec.ts (AC11's real-HTTP pin) has no demonstrated mutation.
    evidence: |-
      The spec was type-checked and, when the local part run fits the call size, run once; a mutation (the person in the state, or the incident listed for a second session) was not demonstrated.
    location: >-
      web/e2e/api/incident-page.spec.ts
    severity: low
---

<intent-contract>

## Intent

**Problem:** An incident tells only the sessions that watch its production, so nobody answers when they are away. The on-call keys (36.2), the On call section (36.4), `AckPage` and `Msg.Escalation` exist, but `OcuTalon.Data.Page` does not, `IncidentManager` answers `AckPage` and `Msg.Escalation` with error 5001, and `TelegramOut` sends nothing for kind `page`.

**Approach:** `IncidentManager` (the paging owner, AD-15) pages the configured on-call person once at an incident's first notice, records it in a new `Data.Page` row, asks `ReminderOps` for an escalation timer, and handles `Msg.Escalation` (page the backup once), `AckPage` (stop escalation) and the close (cancel the timer). `TelegramOut` delivers the page with a Got it button, and `TelegramIn` turns a press from the paired chat into `AckPage`. On an online-demo install, code refuses all of it.

## Boundaries & Constraints

**Always:**
- `IncidentManager`'s job is the only writer of `Data.Page`, through the new `Watch.Paging`. A page needs no approval.
- One page row and one `page` Notification per paged person per incident, whatever the number of watching sessions. Unique `(IncidentRef, Role)`. Each person is paged at most once per incident, after any number of restarts.
- Paging, escalation and acknowledgement each re-read the rows, so a late, repeated or post-restart message changes nothing it shouldn't.
- With `onlineDemo` 1, `Watch.Paging` refuses by code, before reading any on-call key: no row, no Notification, no timer ask, no audit, even when on-call values are set. On the demo `AckPage` answers `not_found` and `Msg.Escalation` does nothing.
- No on-call value (user name, address) goes into a production message, a log line, a trace or an audit entry. The page's `Slots` carry none. `Watch.Paging.Text` resolves `{backup}` and `{person}` at render time from the rows and the keys. No Telegram chat id or display name appears anywhere.
- Every text comes from catalog keys: the five APPROVED `page.*` texts verbatim, plus the NEW keys listed in `## Design Notes` (b) once the Planner accepts them.
- IRIS Managed Alerts are never changed. No OcuTalon class writes alert configuration, except an approved rollback_setting or undo_rollback that puts back the user's own earlier value (Planner ruling DW-1380, 2026-11-15).

**Never:**
- Edit `Core/Rule/Notify.cls`, `EmailOut`, `Schedule/ReminderOps.cls`, `Data/Reminder.cls`, `Core/CommandsIn.cls`, `Core/SettingsOps.cls`, `Web/Api.cls`, `web/src/app/settings/**` or any Lane B contract of AD-29's list. Those belong to 24.3, 36.x or Lane C.
- Hold a timer in `IncidentManager`. AD-5's list of long timers does not grow.
- Create a Session row to page someone (no `Session.ForUser`).
- Page for an evaluation case (owner `eval`), for a later request, or more than once per incident.
- Build web cards, email delivery, the web Got it route, or the real escalation timer. Those are 24.3 and 24.4.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Page at notice | On-call user U (paired session S) and backup B configured; an incident's first notice (with fix, fallback or no fix) to 3 watching sessions | 1 `Data.Page` (Role `oncall`, Person U, Channels from `oncall.primary.channels`, SentAt); 1 Notification kind `page`, SessionRef S, DecisionRef the page Ref, key `page.onCall`; 1 `SetReminder` (Kind `escalation`, IncidentRef, PageRef, DelaySeconds minutes*60, origin `system`); 1 `Action` audit `page`; the incident event carries `page.state` `paged` | A failed send or ask logs one Type 3 warning (no on-call value in it). The incident notice stands |
| No backup, or backup = on-call person | As above without a usable backup | Key `page.onCallAlone` (NEW); no `SetReminder` | none |
| Address-only person | `oncall.primary.email` only | Row with Person = the address; Notification SessionRef `instance` (24.3 routes it to EmailOut); timer asked | Until 24.3: no Telegram, no web card |
| Not configured | No on-call user or address (a backup alone included) | Nothing: no row, Notification, ask or audit | none |
| Online demo | `onlineDemo` 1 and on-call values set | Nothing, as in Not configured | Refusal by code |
| Escalation due | `Msg.Escalation` for an unacknowledged on-call page of an open incident | 1 backup row + Notification `page.backup`; no further escalation ask; `page.state` `escalated` | none |
| Escalation repeated / after restart / after ack / after close / for a backup page | Any of these | Nothing changes; at most one backup row | none |
| Acknowledged | `AckPage` (Ref, Channel web/phone/telegram) from the paged person's session, page unacknowledged | `handled` (Ok 1): AcknowledgedAt, AcknowledgedChannel set; `CancelReminder` (system) when EscalationRef is set; one `handled` Notification to the page's session; audit `page_acknowledged`; `page.state` `acknowledged` | Bad Channel or Ref, unknown page, another session, online demo: `not_found` (Ok 0), nothing changed |
| Acknowledged again | Second `AckPage` or Telegram press | `already_handled` (Ok 1), nothing changed | none |
| Close before due | Incident moves to closed with an unacknowledged page that has EscalationRef | `CancelReminder` (system) | A failed cancel is one warning; a later Escalation still changes nothing |
| Telegram press | Got it on the page message from the paired chat | `AckPage` origin `telegram`, Channel `telegram`; the message is edited in place to its text + "Marked as handled at {time}", with no button | A press from another chat, or an unpaired one, submits nothing |
| Purge | Closed incident older than `daysToKeep` | Its page rows are deleted with it | none |

</intent-contract>

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with a top-level folder.

**The paging owner (`Watch/IncidentManager.cls`, 2,008 lines; Lane D-contended)**
- `OnRequest` 299-313 is a `%IsA` chain. `AckPage` and `Msg.Escalation` fall to the 5001 at 312. `Command` 1607 and `Verdict` 1635 build a synchronous `CommandResult`.
- `Deliver` 1405-1414 handles every first notice: fallback, unknown or no-fix from `Notice` 870, `NoFix` 1398, and with-fix from `Proposed` 1024. Its `slots` are the notice's: count, itemNoun, time, and cause (string or settingChange object). Hook here once, after `Move` returns OK. Not in `Tell` (one copy per session).
- `Notification` 1417-1428. `Move` 1432-1447. `Apply` 1453-1470: the close is `to = CLOSED` at 1462. `Tell` 1882-1908 publishes the event; with no notification it only publishes. `SendNotice` 1860-1863 is the seam the probe overrides.
- `Purge` 1815-1833 and `PurgeOne` 1835-1857: add the `Data.Page` delete beside FixRun's at 1847.
- Eval runs through `EvalCase`/`EvalDeliver` 1913-1990 and never reaches `Deliver`.
- The sync-ask precedent is `SendRequestSync` at 1340.
- The production slot comes from `Fix.Kind.ProductionName(incident)`, as `Watch/Notice.cls:266` does.
- Online demo: `Watch/Reader.cls:181-184` `OnlineDemo()`, already used at IM:1478.

**Contracts that exist (36.1/36.2; read only, never edit)**
- `Msg/Command/AckPage.cls`: `Ref` (22) and `Channel`. It extends `Msg.Command` (Origin, SessionRef, IdempotencyKey).
- `Core/CommandsIn.cls:378` routes AckPage from `web_user,web_admin,telegram` to IncidentManager; only code 5003 counts as a stub (140, 286). SetReminder and CancelReminder accept origin `system` (lines 336-384).
- `Msg/Escalation.cls`: `IncidentRef`, `PageRef`.
- `Msg/Command/SetReminder.cls`: Kind (18), IncidentRef (21), PageRef (24), DelaySeconds. `CancelReminder` has `ReminderRef` only.
- `Schedule/ReminderOps.cls:101-103` answers Kind `escalation` with Ok 0 `not_built` and stores nothing, pinned by `Test/Schedule/Reminders.cls:674` `TestEscalationNotBuilt`. So EscalationRef stays "" until 24.3, when `CommandResult.Ref` (`Msg/CommandResult.cls:15`) carries it.
- `Core/Commands.cls` `Submit(command, "system", .result)` is the one way in (AD-1). `Fix/Kind/Email.cls` is the precedent of a production host submitting as `system`.
- `Msg/Enum.cls:30` already has `page` and `handled`. `Core/Rule/Notify.cls:71-82` is the generic route: WebChatOut always, SimPhoneOut in demo mode, TelegramOut when paired. WebChatOut and SimPhoneOut record a bare Delivery row for `page` (not in their card kinds).
- On-call keys and defaults: `Core/SettingsOps.cls:936-943`. Read with `Data/Setting.cls:39` `Get(key, default)`, which has a 60 s per-process cache for non-public keys.
- `pagesBuilt` = `%Dictionary.CompiledClass.%ExistsId("OcuTalon.Data.Page")` (`SettingsOps.cls:2782`). It is rendered at `web/src/app/settings/on-call-section.ts:64-66` and pinned at `web/e2e/settings/on-call.spec.ts:111-112` (O1 takes the server's value).
- Sessions: `Data/Session.cls` `IrisUserIndex` (76), `ForUser` (84; it creates rows, so do not use it). Paired: `Data/Pairing.cls`. `Data/Delivery.cls:176-182` `FindByRef`, `Data/Ownership.cls:659` `DeliveryByRef`.
- `Core/SessionOps.cls:255-281` `GotIt` is the sibling for the acknowledgement. Its messages are `MESSAGEHANDLED` 69, `MESSAGEALREADYHANDLED` 71 and `MESSAGENOTICENOTFOUND` 73.
- `Data/Handled.cls` `Marked(ref)` is the sibling for `Page.Marked`.
- `src/bridge/cls/OcuTalon/Bridge/Ids.cls:7` `NewRef()` gives 128 random bits, so a page Ref is unguessable. `Bridge/Approval.cls:300` `IsRef`.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:91` `Record("Action", {action, target, result, counts, approvalRef, irisUser, sessionRef, channel})`. The shape sibling is `Fix/Kind/Email.cls:307-318`.

**Telegram (Lane A files of this lane; not contended)**
- `Channel/Telegram/Out.cls`:
  - `KINDS` 105, `GOTITKINDS` 117, `GOTITACTION` 122 (`gotit`), `HANDLEDKEY` 125.
  - `OnNotification` 196-226: the `summary` branch calling `Watch.Summary.Text` is the model for `page`. `GotItKeyboard` 260-264.
  - `EditHandled` 352-380 reads `Handled.Marked` and edits with no `reply_markup`, which removes the button.
- `Channel/Telegram/In.cls`:
  - `Press` 404-430; the `gotit` branch is 408-412.
  - `GotIt` 433-444 checks the pairing's session and the Delivery row's chat prefix, then submits through `Outcome` 625. `OnlineDemo()` 764.
- Test helpers: `Test/Channel/LiveCase.cls` `ButtonPress` 652, `WaitCalls` 476, `Handled` 857, and `Test.Contract.Mock.Calls()`.
  - The sibling is `Test/Channel/TelegramDigest.cls` `TestGotItEdits` 595, `TestGotItPairedChat`, `TestGotItOtherChat`, `TestHandledEdit`.
  - The no-identity pins are `Test/Channel/TelegramApproval.cls:240,468`.
- Mock: `ci/mock` `BOT_METHODS` includes `editMessageText` (pinned in `ci/mock/test/scenarios.test.mjs:261`). Press through `/_mock/telegram/updates`; read through `/_mock/telegram/calls`. No scenario file is needed.

**Rows, payload, catalog**
- `Data/FixRun.cls` (Lane A, `IncidentRefIndex` 62, purged in `PurgeOne`) and `Data/SettingChange.cls` are the table siblings: `DEFAULTGLOBAL ^OcuTalonP.<Short>`, `Ref` EXACT MAXLEN 22 unique, UTC `%String(MAXLEN=20)` times, committed storage.
- `Data/FailureGroup.cls` `OfIncident` is the object-access read that `/state` needs (AD-13).
- `Live/Payload/Incident.cls`: properties 6-69, `FromRow` 83. `Live/Payload/Part/SettingChange.cls` is the part sibling.
- `Msg/Catalog/Watch.cls`: append the `page.*` entries after the last entry. `button.gotIt` 426 and `handled.marked` 431-436 ("Marked as handled at {time}") already exist. Slot types are in `Msg/Catalog.cls:7-23`: use `count` for `{minutes}` (the `minutes` type adds its own unit) and `text` for `{backup}`/`{person}`.
- `Watch/Summary.cls` `Text(incidentRef, channel, .sc)` is the precedent of a Lane A helper that an `*Out` calls to render.

**Lists a new table joins**
- `src/short-names.tsv` (FixRun row 23), checked by `docker/tests/test-storage.sh:79,155` and `docker/tests/test-class-rules.sh:341-344,632-645`.
- `Test/Data/Tables.cls` XData Registry 709-885 (`TestEveryTableIsRegistered` 46-63).
- `Test/Install/PrivateData.cls`; `Test/Install/Retention.cls`; `Test/Watch/Lifecycle.cls` `TestPurge` 1082-1150.

**Tests to reuse or extend**
- `Test/Watch/Lifecycle.cls` helpers `Host` 1337, `Owner` 1345, `Watch` 1353, `Incident` 1359, `Command` 1518, `SentCount` 397. Isolation is in `OnBeforeOneTest`/`OnAfterOneTest` 100-118.
- `Test/Watch/IncidentProbe.cls`: `SendNotice` 284 records into `Sent`. `Test/Data/Fixture.cls` provides `Incident` 116, `Session` 22, `Pairing` 280, `Delivery` 250 and `Clean` 410.
- `Test/Watch/Notices.cls` is the running-production precedent (throwaway and CI only). `Test/Watch/OrdersDefinition.cls` and 23.3's `Test/Watch/Rollback.cls` (`PutTarget`) show how to change OCUORDERS's saved definition with `UpdateProduction`.
- `Test/Msg/Catalog.cls`: `TestEntries` 74-98 (Watch 133), XData `Keys` 1107 and `Fixtures` 1607, `SLOTTYPES` 25.
- `Test/Live/Payloads.cls:93`: 37 classes; per-class contracts around 1377 and 1579.
- `docker/tests/test-production-restart.sh`: phases are appended per story (Stories 2.2, 2.4, 12.1). It runs in CI group `production`.
- `web/e2e/cards/approval-card.spec.ts` is 23.3's real-HTTP `/state` pattern (LIVE `OcuTalonUser` plus a second session).

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (measure first; record under `## Design Notes` › Measured; label anything unmeasured "(inference)"). Run on a fresh lane-B throwaway, inside the first `Test.Watch.PagingLive` cases:
  - (a) Add an `Ens.Alert` item of class `Ens.Alerting.AlertManager` and `AlertOnError` 1 on `OrdersFromPartner` to OCUORDERS's saved definition, then `UpdateProduction`. Break three orders. Record:
    - whether `Ens_Alerting.ManagedAlert` rows appear, how many and how fast;
    - whether the AlertManager needs any other setting;
    - that removing the item and restoring `AlertOnError` leaves the definition and the job list as before.
  - (b) A page sent through the real IncidentManager reaches TelegramOut and the mock in a `ci/iris.sh class` stack of the Watch area (TelegramIn/Out jobs alive, fixture pairing). If it does not, the Telegram cases move to `OcuTalon.Test.Channel.TelegramPage` (decided in-stage and recorded).
  - (c) `Commands.Submit(SetReminder escalation, "system")` from IncidentManager's job answers `not_built` with no deadlock, and how long it takes.
  - (d) After an `AckPage`, record what WebChatOut and SimPhoneOut log for a page copy that has only a bare Delivery row: any warning, and its text. Any Type 3 line goes to `## Design Notes` as a 24.3 item.
- [x] `Data/Page.cls` (NEW) -- Persistent, `^OcuTalonP.Page`. Columns exactly as AD-15 lists them. `RefIndex` unique, `IncidentRoleIndex On (IncidentRef, Role)` unique. Add `OfIncident(ref)` (object access, AD-13), `Marked(ref)` (AcknowledgedAt, as `Handled.Marked`) and a committed storage block -- AD-5, AD-15, AD-33.
- [x] `Watch/Paging.cls` (NEW) -- the decisions and row writes, called only from IncidentManager's job:
  - `Notice(incident, slots)` decides and records the on-call page, or returns nothing. `OnlineDemo()` is checked first.
  - The person is the user when set, else the address. The session is the user's paired session, else their first session row, else `instance`. Configured, the same-person rule and the key choice are as in the Matrix.
  - `Escalate(message)` decides and records the backup page.
  - `Acknowledge(command)` returns outcome and message: the SessionOps constants, read by reference.
  - `Closing(incident)` gives the EscalationRefs to cancel.
  - `PagePayload(incidentRef)` gives `{state, pagedAt, acknowledgedAt, channel}`.
  - `Text(notification, channel, .sc)` renders a page:
    - it resolves `{backup}` (the role's current `oncall.backup.user`, else `.email`) and `{person}` (the on-call row's Person);
    - for an unknown cause it renders `page.causeUnknown` into `{cause}`;
    - for channel `email` it picks the `*Email*` variant, so that 24.3's EmailOut can call it as TelegramOut does.
  - Audit goes through `Bridge.Audit` only, with action `page` or `page_acknowledged`, target the page Ref, a result, and no person.
- [x] `Watch/IncidentManager.cls` -- hooks only, each 1-2 lines:
  - `OnRequest`: `AckPage` goes to a paging method that answers through `Verdict`; `Msg.Escalation` goes to one with no answer.
  - `Deliver`: after `Move` returns OK, call the page method.
  - `Apply`: after a move into closed, call the cancel method.
  - `PurgeOne`: delete the page rows.
  - Then ONE appended block at the end of the file: the paging methods (send the Notification through `SendNotice`, ask or cancel through a new seam `SendCommand(command, .result)` wrapping `Commands.Submit(..., "system")`, publish with `Tell` with no notification), each wrapped so that a paging failure is one Type 3 warning and never fails the notice, the close or the purge -- AD-15, AD-1, AD-5.
- [x] `Live/Payload/Part/Page.cls` (NEW) and `Live/Payload/Incident.cls` -- `page` {state, pagedAt, acknowledgedAt, channel}, absent with no page and on the online demo. Set in `FromRow` by object access. Regenerate `web/src/app/live/payloads.ts` (`npm --prefix web run payloads`) -- AD-12, AD-13.
- [x] `Msg/Catalog/Watch.cls` -- append the five APPROVED `page.*` entries verbatim, and the NEW entries once accepted (`## Design Notes` (b)). Slot types: count, itemNoun noun, production text, time time, cause cause, minutes count, backup/person text. -- AD-32.
- [x] `Channel/Telegram/Out.cls` -- `page` joins `KINDS` and `GOTITKINDS`. Add a `page` branch beside `summary` that calls `Watch.Paging.Text`. `EditHandled` falls back to `Page.Marked` when `Handled.Marked` is empty. -- AD-14.
- [x] `Channel/Telegram/In.cls` -- in the existing `gotit` branch, when the pressed chat's Delivery row has Kind `page`, submit `AckPage` (Ref, Channel `telegram`) with the same pairing and chat checks. Otherwise keep `GotIt`. The callback action list does not change -- AD-14, AD-1.
- [x] `Test/Watch/IncidentProbe.cls` -- add a `SendCommand` override that records each command and answers from a fixture (`not_built` by default, or Ok 1 with Ref `ZzProbeEscalation0001`): the escalation-timer fixture until 24.3.
- [x] `Test/Watch/Paging.cls` (NEW, warm) -- every Matrix row through the probe and Fixture rows. Each case sets and restores the on-call keys and `onlineDemo`. Includes the audit read-back (polled, S8), purge, payload and `Text` (no on-call value in Slots, the trace or the audit).
- [x] `Test/Watch/PagingLive.cls` (NEW, throwaway or CI; the running production, the CI mock):
  - Task 0;
  - a real break of OCUORDERS that pages through Telegram;
  - Got it pressed from the paired chat (edit in place, button gone), from another chat (nothing), and twice (nothing);
  - an `AckPage` from the web channel edits the Telegram copy;
  - a fixture `Msg.Escalation` pages the backup once;
  - the close cancels;
  - Managed Alerts as AC8;
  - real-HTTP `GET /api/v1/settings` as the README admin gives `pagesBuilt` true (DW-1277);
  - no chat id, display name or on-call value in the audit, the log or the messages.
- [x] `docker/tests/test-production-restart.sh` -- append one self-contained phase. Before row 20's kill, seed with Fixture three incidents with on-call pages: unacknowledged and open, acknowledged, and closed, with on-call keys set. After the restart, send each page's `Msg.Escalation` twice through a fixture. Expect exactly one backup row, for the first, and none for the others. Rows are removed afterwards -- AD-5, NFR-16.
- [x] `docker/tests/test-class-rules.sh` -- a new rule `no-alert-config`: no product code line (`src/` outside the Test package) names `AlertOnError`, `AlertGracePeriod`, `AlertRetryGracePeriod`, `QueueCountAlert`, `QueueWaitAlert`, `InactivityTimeout`, `AlertGroups`, `Ens.Alerting.` or the item name `Ens.Alert` -- FR-28.
- [x] `web/e2e/settings/on-call.spec.ts` -- O1 asserts that the not-yet line is absent and that `pagesBuilt` is true outright, no longer taken from the server's value (DW-1277).
- [x] `web/e2e/api/incident-page.spec.ts` (NEW) -- real HTTP. As the LIVE `OcuTalonUser` watching a seeded instance incident with a seeded page, `GET /api/v1/state` lists `page` with state and times and no person. A second session lists no such incident -- Rule 3.
- [x] `src/short-names.tsv`, `Test/Data/Tables.cls` (registry row), `Test/Msg/Catalog.cls` (count, Keys, Fixtures), `Test/Live/Payloads.cls` (class count and contract), `Test/Watch/Lifecycle.cls` `TestPurge` -- the shared-surface pins.

**Review patches (pass 1; R1-R6, from the Review Triage Log; each test change gets its `mutation:` line in `## Verification`, Rule 19):**
- [x] R1 `Watch/IncidentManager.cls` `Followed` -- its own Try/Catch so a failure after the acknowledgement is saved is one Type 3 warning and `Acknowledged` still answers `handled`. A probe fixture makes a follow-up step throw; `Test.Watch.Paging` pins that the answer stays `handled` with the row acknowledged.
- [x] R2 `Watch/Paging.cls` `Closing` -- skip an on-call page whose incident already has a backup page (its timer has fired). `Test.Watch.Paging` pins it (no cancel after an escalation; the AC5 case is unchanged).
- [x] R3 `docker/tests/test-production-restart.sh` -- send the escalations of the unacknowledged page's incident last (the acknowledged and the closed incident's first), keeping the 90 s wait and the pause.
- [x] R4 `Test/Watch/Paging.cls` -- add cases: a first notice whose cause is a setting change (page slots carry the object, the rendered page text carries the setting-change sentence); non-default `oncall.primary.channels` and `oncall.backup.channels` copied to their rows; `Text(..., "email")` for `page.onCall` and for the alone key (the exact `page.onCallEmail` and `page.onCallEmailAlone` renderings); `Escalate` with another incident's page Ref adds nothing; the `response = ""` assertion of the Escalate helper removed or made meaningful.
- [x] R5 `Test/Watch/PagingLive.cls` -- positive controls so the trace, event and log assertions cannot pass on empty text (the trace holds the page Ref, the backup's Ref and the AckPage marker; the event text holds the incident Ref and `paged`); `TestManagedAlertsBesidePaging` asserts the ManagedAlert's source is `OrdersFromPartner` and reads it after the page was found; `TestPageReachesTelegram` clears or sets its own on-call keys. Demonstrate one mutation for the trace pin on a fresh stack.
- [x] R6 Doc wording in `Data/Page.cls` and `Watch/Paging.cls` headers: the person is in no Ens message body or header, log line, audit entry or payload; the rendered channel text and its Delivery row name the backup or the person (approved deviation 1).

**Acceptance Criteria:**
- AC1: Given on-call U and backup B configured and three sessions watching, when an incident's first notice is sent (with fix, fallback or no fix), then exactly one page row and one `page` Notification (key `page.onCall`, DecisionRef the page Ref, SessionRef U's session) exist, one escalation `SetReminder` of origin `system` with DelaySeconds = `oncall.escalationMinutes` x 60 was asked, and one `Action` audit `page` names the page Ref with no person (`Test.Watch.Paging`).
- AC2: Given no on-call person (a backup alone included), or `onlineDemo` 1 with every on-call key set, when a notice is sent, then no page row, Notification, `SetReminder` or audit entry exists, and the notice and its copies are unchanged (`Test.Watch.Paging` `TestOnlineDemoRefusesByCode`).
- AC3: Given an unacknowledged on-call page of an open incident, when `Msg.Escalation` arrives (the fixture), then the backup gets one row (Role `backup`) and one `page.backup` Notification, and no `SetReminder` is asked for it. Repeating the message, or sending it after an acknowledgement, after a close, or for the backup's page, adds nothing.
- AC4: Given a page, when `AckPage` arrives through `CommandsIn` from the paged person's session, then the row records AcknowledgedAt and the channel, `CancelReminder` (system) is asked when EscalationRef is set, one `handled` Notification goes to the page's session, and the answer is `handled`. A second `AckPage` answers `already_handled` and changes nothing. Another session's `AckPage` answers `not_found`.
- AC5: Given an unacknowledged page with EscalationRef set (probe fixture), when the incident closes, then `CancelReminder` is asked once, and a later `Msg.Escalation` changes nothing.
- AC6: Given a page sent to a paired user (`PagingLive`), when TelegramOut delivers it, then the mock records one `sendMessage`: plain text equal to `Catalog.Render("page.onCall", ...)` with the backup's name resolved, a `gotit:<pageRef>` button, no Markdown. When Got it is pressed from the paired chat, then IncidentManager records channel `telegram` and the mock records `editMessageText` with the text, a blank line and "Marked as handled at {time}", with no `reply_markup`. A press from another chat, and a second press, change nothing.
- AC7: Given seeded pages and a real container kill and restart (`live:production-restart`), when each page's `Msg.Escalation` arrives twice after the start, then only the unacknowledged page of the open incident gets a backup row, exactly one.
- AC8: Given OCUORDERS with an AlertManager fixture and on-call configured, when a break pages, then every alert setting of every item reads as before, a `ManagedAlert` row for `OrdersFromPartner` exists after the page, and `no-alert-config` passes on the tree.
- AC9: Given a closed incident with page rows older than `daysToKeep`, when the Watch area's `Purge` runs, then its page rows are gone and newer ones stay (`Test.Watch.Lifecycle` `TestPurge`).
- AC10 (Integration, Rule 1; DW-1277): Given `Data.Page` compiled, when the README admin reads `GET /api/v1/settings` over real HTTP, then `pagesBuilt` is true, and the On call section in the browser shows, in place of "OcuTalon doesn't send pages yet", the line "OcuTalon pages the on-call person in their paired Telegram chat only. It doesn't page by email or escalate to the backup." (Planner ruling 2026-11-15, deviation 2 CHANGED; 24.3 replaces it) (`PagingLive`; `web/e2e/settings/on-call.spec.ts` O1).
- AC11 (Rule 3): Given a watched incident with a page, when the LIVE `OcuTalonUser` reads `GET /api/v1/state`, then the incident lists `page` {state, pagedAt, acknowledgedAt, channel} and no person. A second session does not list it (`incident-page.spec.ts`).
- AC12: Given any test above, then no message, log line, trace or audit entry holds a chat id, a display name, `oncall.*.user` or `oncall.*.email`.

- AC13 (Planner ruling 2026-11-15, veto 1 CONDITION): the paged person (user name or email address) never appears in the Ens trace (message bodies and headers OcuTalon writes), the audit (`page` / `page_acknowledged` carry references only), `GET /api/v1/state`, the `incident` event, or the logs (event log / OcuTalon logs). Pin EACH of the five with its own assertion on a real page (a distinctive fixture person name searched for), each with a mutation that turns it red (e.g. putting the person into the audit description).
- AC14 (Planner ruling 2026-11-15, deviation 2 CHANGED): replace the On call section's "OcuTalon doesn't send pages yet" line with, verbatim: "OcuTalon pages the on-call person in their paired Telegram chat only. It doesn't page by email or escalate to the backup." Shown when `pagesBuilt` is true (the not-yet line stays only for `pagesBuilt` false). Pin it in the web catalog/ux-strings tests and in `web/e2e/settings/on-call.spec.ts` O1 (Lane C's two-line change granted); mutation: the old line or no line turns it red. No release-check tool.
- AC15 (Planner ruling DW-1380, 2026-11-15): a test pins that no OcuTalon class other than the approved `rollback_setting` / `undo_rollback` path writes alert configuration (source scan of the product classes for writes to alert settings / Managed Alerts configuration, with the two rollback kinds as the only allowed writers through `Fix.Executor`), with a mutation (a planted write in another class turns it red).

## Spec Change Log

- 2026-11-15 ~14:35Z (lead, Planner gate): APPROVED with conditions (prompts/story-234-rulings-20261115.md). Added AC13 (the person never in trace, audit, /api/v1/state, incident event or logs; each pinned), AC14 (the new Settings line replaces the not-yet line, verbatim), AC15 (no other class writes alert configuration). AC10 and the Boundaries alert line amended; epics.md 23.4 AC amended with marker (DW-1380). All proposed public text approved verbatim. Targets 1.0.12.

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 45 findings — high 0, medium 6, low 38, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) The new Settings line contradicts the on-call help and the backup fields: by-design, AC14's line is the Planner's verbatim ruling (deviation 2 CHANGED) and 24.3 replaces it
  - `[low]` `[reject]` (blind) The on-call text promises a backup page although no timer is armed until 24.3: by-design, Planner deviation 2 ACCEPTED (tests use the fixtures)
  - `[medium]` `[patch]` (blind) An acknowledgement that was saved can be answered as failed because Followed runs inside Acknowledged's Try: real (Followed has no Try of its own); patch R1
  - `[low]` `[reject]` (blind) Only one session of the paged person can acknowledge: by-design, Decided in-stage 2 (AckPage accepted from the session the page was sent to)
  - `[low]` `[reject]` (blind) Page.Channels is recorded and never used: by-design, the spec records it for 24.3's routing (Consumed-by)
  - `[low]` `[reject]` (blind) page.subject and KEYSUBJECT are unused: by-design, 24.3's EmailOut consumes them (Consumed-by, approved text)
  - `[low]` `[patch]` (blind) The 'no person in any record' header wording is broader than the code (the rendered text and its Delivery row name the backup or the person, approved deviation 1): doc wording only; patch R6
  - `[medium]` `[patch]` (blind) The restart phase's negative assertions can pass before the later messages are consumed (i1's escalations are sent first, then a fixed 8 s): real; patch R3 (i1 last)
  - `[low]` `[patch]` (blind) A close can cancel a spent timer and log a spurious warning when the backup's page already exists: real and trivial; patch R2
  - `[low]` `[reject]` (blind) no-alert-config also flags any Ens.Alert* name: by-design, its header already says it matches Ens.Alert and the item name
  - `[medium]` `[patch]` (edge) Followed throws after AcknowledgedAt is saved, so the caller gets failed: same root as the blind finding on Acknowledged; patch R1
  - `[low]` `[reject]` (edge) SessionOf can return another session at acknowledgement time than at send time: by-design (Decided in-stage 2); a person's later session is theirs
  - `[low]` `[reject]` (edge) An exception after Record leaves an orphan page row: wontfix-theoretical, nothing after Record can throw (SessionOf and Slots are guarded) and IncidentManager.Page is wrapped; reopen_if=a throw is observed there
  - `[low]` `[reject]` (edge) Escalate refuses only a closed incident: by-design, the Matrix says escalation after close changes nothing and a resolved incident is not closed
  - `[low]` `[reject]` (edge) oncall.escalationMinutes changed between the pages changes the backup text's N: wontfix-theoretical
  - `[low]` `[reject]` (edge) User name and address of the same person are not recognized as the same: by-design, the same-person rule compares the configured values; no user-to-address map exists at this layer
  - `[low]` `[reject]` (edge) Text reads the on-call keys for a notification stored before the online demo was switched on: wontfix-theoretical, onlineDemo is an install-time property and no page row can exist there
  - `[low]` `[reject]` (edge) A failing page DELETE rolls back the incident's purge: wontfix-theoretical, it mirrors the FixRun DELETE line beside it
  - `[medium]` `[patch]` (edge) Claim: each follow-up failure is one warning and the acknowledgement stands: same root as the Followed finding; patch R1
  - `[low]` `[patch]` (edge) Claim: no on-call value in a production message while the Delivery row keeps the rendered text: same root as the header wording finding; patch R6
  - `[low]` `[reject]` (edge) Claim: escalation of an 'open' incident also pages for resolved or fixing states: same root as the Escalate state finding, by-design
  - `[low]` `[reject]` (edge) Claim: AckPage accepted only from the sent-to session while the row stores none: same root as the one-session finding, by-design
  - `[medium]` `[patch]` (gap) A page for a setting-change cause (object slot, rendered text) has no test: real, no pinning test; patch R4
  - `[low]` `[patch]` (gap) Page.Channels is tested only at its default: real; patch R4
  - `[low]` `[patch]` (gap) Text's email key mapping is tested for the backup page only: real; patch R4
  - `[low]` `[patch]` (gap) Escalate with another incident's page Ref is not tested: real; patch R4
  - `[medium]` `[patch]` (gap) PagingLive's trace, event and log 'holds no name' assertions have no positive control, so an empty trace passes: real (AC13's real-production pin); patch R5
  - `[low]` `[patch]` (gap) AC8 asserts any ManagedAlert row and reads it before the page: real; patch R5 (source OrdersFromPartner, read after paged)
  - `[low]` `[defer]` (gap) The AC14 template branch (@if/@else in on-call-section.ts) was not mutated; only the text constant was: O1 pins it and needs a live sign-in part; deferred, recorded
  - `[low]` `[reject]` (gap) Absence assertions in PagingLive use fixed sleeps: wontfix-accepted, each follows a press or message the same case already awaited; reopen_if=the case flakes. The restart phase is the finding patched under R3
  - `[low]` `[patch]` (gap) PagingLive.TestPageReachesTelegram relies on no on-call keys being set: real; patch R5
  - `[low]` `[patch]` (gap) Test.Watch.Paging's `response = ""` assertion cannot fail: real; patch R4
  - `[low]` `[defer]` (gap) PagingLive.TestEscalationAsk asserts not_built and goes red when 24.3 builds the escalation timer: 24.3 replaces it (Consumed-by); deferred to 24.3
  - `[false]` `[reject]` (gap) Shard membership of Test.Watch.Paging and PagingLive is claimed, not shown: false, docker/tests/test-ci-config.sh passes (the shard units run every class once)
  - `[low]` `[reject]` (gap) AC8's settings-as-before half has no mutation: wontfix-accepted, product code may not write alert settings; its rule is mutated instead (AC15); reopen_if=the rule is relaxed
  - `[low]` `[reject]` (gap) AC10's mutation flips the test's expectation: wontfix-accepted, pagesBuilt is Lane C's read of the compiled class; reopen_if=pagesBuilt stops reading Data.Page
  - `[low]` `[defer]` (gap) AC11's real-HTTP spec incident-page.spec.ts has no demonstrated mutation (type-checked here); deferred to the CI run of live:sign-in and to this pass's local part run when it fits
  - `[low]` `[patch]` (gap) AC12's chat-id and display-name pins in PagingLive have no mutation line: same root as the positive-control finding; patch R5
  - `[low]` `[patch]` (gap) AC13's real-production pins have no mutation: same root as the positive-control finding; patch R5
  - `[low]` `[reject]` (gap) AC15's rule is a name scan and cannot catch a write that names none of the eight words: by-design, AC15 asks for a source scan of the alert-setting names
  - `[low]` `[reject]` (gap) The restart phase leaves the on-call keys set when it fails before its cleanup: wontfix-theoretical, throwaway stack
  - `[low]` `[reject]` (intent) A crash between the row save and the send loses the page (reading B3): by-design, rows are the state and 'at most once per person' is the invariant
  - `[low]` `[reject]` (intent) Names in the Telegram text and its Delivery row (reading C2): by-design, approved deviation 1; same root as the header wording finding
  - `[low]` `[reject]` (intent) No Escalation is produced by the real production until 24.3: by-design, Planner deviation 2
  - `[low]` `[reject]` (intent) TelegramOut and TelegramIn refuse the online demo only implicitly (no row, no Notification): by-design, AC2 pins the refusal at its source
- patches (written into Tasks & Acceptance as R1-R6): applied by a fresh subagent; the log rows above name the patch each one triggers.

## Design Notes

### Planner rulings, 2026-11-15 (binding; prompts/story-234-rulings-20261115.md)
- Veto items 1-5 APPROVED, with the CONDITION that the person never appears in the Ens trace, the audit, /api/v1/state, the incident event or the logs (AC13).
- Deviation 1, 3, 5, 6 APPROVED/ACCEPTED as written. Deviation 2 CHANGED: the new Settings line (AC14); no release-check tool; releases are not blocked on 24.3. Deviation 4: DW-1380 accepted as a user-approved restore, AC amended, pinned (AC15).
- Public text APPROVED verbatim: page.onCallAlone, page.onCallEmailAlone (as in this spec), page.causeUnknown "I couldn't work out the cause", the one-minute forms, and the new Settings line.
- Contention: Lane D Watch/** hooks plain union (whoever pushes second integrates and flags overlapping hunks); Lane C's on-call.spec.ts two-line change GRANTED; the Settings line change in `web/src/app/settings/on-call-section.ts` (or wherever the line is rendered) is part of this ruling. shards-8 growth noted; measured time reported at PART READY.

### For the Planner's gate

**(a) Veto items, each with its online-demo behaviour**

1. **Stored data: `OcuTalon.Data.Page`** (`^OcuTalonP.Page`, Lane A, as AD-15 lists it).
   - `Person` holds the user name or the address: contact data at rest, as the setting keys already hold it. It is never in a message, log, trace or audit entry.
   - Unique `(IncidentRef, Role)`.
   - Retention: the rows are purged with their incidents through the Watch area's `Purge(daysToKeep)` (90). They are not tied to a session.
   - Online demo: no row is ever written. This is a refusal by code, pinned by AC2 even with the keys set.
2. **Outward action: a page is a message to a person, with no approval request** (AC, FR-28). In this story it reaches only the paged user's paired Telegram chat and their own web chat or phone as bare delivery records. Email starts with 24.3.
   - Online demo: never (AC2).
3. **Privileges, roles and grants:** none. No new route; `docs/security-overview.md` does not change.
4. **Changed route:** `GET /api/v1/state` and the `incident` event gain `page`, with no person. AC11 tests it over real HTTP.
   - Online demo: absent.
5. **Audit:** new `Action` names `page` and `page_acknowledged`. The target is the page Ref; there is no identity (AD-17).

**(b) PUBLIC TEXT** (key; file `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` unless stated)

APPROVED (Story 36.1 gate, 2026-11-12; `spec-36-1-…md` lines 482-486), used verbatim:
- `page.onCall`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. Press Got it to show you're on it; if nobody does within {minutes} minutes, I'll page {backup}."
- `page.onCallEmail`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. To show you're on it, press Got it on your OcuTalon page; if nobody does within {minutes} minutes, I'll page {backup}. Replying to this email doesn't count."
- `page.backup`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. Press Got it to show you're on it."
- `page.backupEmail`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. To show you're on it, press Got it on your OcuTalon page. Replying to this email doesn't count."
- `page.subject`: "OcuTalon page: {production} incident"
- The paging-ack rules (APPROVED, ruling V5): Got it on the web or the paired Telegram chat; an email page has none; a reply never counts.
- Already in the catalog, reused unchanged: `button.gotIt` "Got it", and `handled.marked` "Marked as handled at {time}" (UX-DR143).
- The `AckPage` result messages reuse `SessionOps`'s existing sentences, so no new text: "The notice is marked as handled.", "The notice was already marked as handled, so nothing was changed." and "That notice is not known, so nothing was marked."

NEW (proposals):
- `page.onCallAlone` (no usable backup): "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. Press Got it to show you're on it."
- `page.onCallEmailAlone`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. To show you're on it, press Got it on your OcuTalon page. Replying to this email doesn't count."
- `page.causeUnknown` (the `{cause}` of a fallback or unknown-cause incident, whose approved text needs a sentence): "I couldn't work out the cause"
- One-minute forms (`one` on slot `minutes`; `oncall.escalationMinutes` may be 1), the same texts with "within {minutes} minutes" replaced by "within one minute":
  - `page.onCall`, `page.onCallEmail`: "…if nobody does within one minute, I'll page {backup}…"
  - `page.backup`, `page.backupEmail`: "…nobody pressed Got it on {person}'s page within one minute…"
- Recommendation: approve all of them. Alternative: drop the one-minute forms and accept "within 1 minutes".

**(c) Contended-file overlaps**
- Lane D, `Watch/**`:
  - `Watch/Paging.cls` is a NEW file.
  - `Watch/IncidentManager.cls` gets in-method hooks: `OnRequest` +2, `Deliver` +1, `Apply` +1, `PurgeOne` +1. Plus ONE block appended at the end of the file (paging methods and the `SendCommand` seam).
  - The hooks are not end-of-file appends, so they need the 23.3-style ruling: plain union, with any overlapping hunk flagged.
- Lane C:
  - Settings: `web/e2e/settings/on-call.spec.ts` O1 (two lines).
  - No `Core/SettingsOps.cls`, `Web/Api.cls` or `web/src/app/settings/**` edit.
- Not contended:
  - `Channel/Telegram/Out.cls` and `In.cls`, `Live/Payload/**`, `Data/Page.cls`;
  - `Msg/Catalog/Watch.cls` (append);
  - `src/short-names.tsv` (one-line append);
  - `Test/Data/Tables.cls`, `Test/Msg/Catalog.cls`, `Test/Live/Payloads.cls`, `Test/Watch/*`;
  - `docker/tests/test-class-rules.sh` (appended rule) and `test-production-restart.sh` (appended phase);
  - `web/e2e/api/incident-page.spec.ts` (NEW), `web/src/app/live/payloads.ts` (generated).
- Lane B's contracts (Notify, ReminderOps, Reminder, CommandsIn, AckPage, Escalation, the on-call keys) are read, never edited.

**(d) Deviations and readings, each with a recommendation**
1. **`{backup}` and `{person}` are resolved at render time** by `Watch.Paging.Text` (the `Watch.Summary.Text` precedent), not carried in `Slots`. This keeps AD-19's rule (36.4 S1(b)): "no on-call value is in a command, a result, a log line or a trace".
   - Recommendation: approve.
   - The alternative (names in Slots) breaks that rule.
2. **Until 24.3 merges, production pages reach only Telegram,** and nothing escalates, because ReminderOps answers `not_built` and nothing sends `Msg.Escalation`. Tests use the AC's fixtures. Meanwhile `pagesBuilt` turns true, so the On call section stops saying "doesn't send pages yet", and its help promises the backup page.
   - Recommendation: accept for the feature branch. Treat "a release with Epic 23 but not 24.3" as a release-check item, owner/Planner: hold paging out of such a patch release, or ship it knowingly.
   - Alternative: gate `pagesBuilt` on 24.3 too. That is a Lane C/B file, so not recommended now.
3. **Findability:** this story adds no More to try item and no GUIDE.md line (36.4 Decided 16 hands them to "23.4 or 24.3"). A judge sees a page only on their own install with a paired bot, and the online demo never pages.
   - Recommendation: 24.3 carries them.
4. **`rollback_setting` (23.3) can restore an alert setting's earlier value.** That is an approved, governed change by the admin, and it names no alert setting, so `no-alert-config` passes. But "OcuTalon never turns Managed Alerts off" could be read as forbidding it.
   - Recommendation: a ledger item for the Planner to decide whether `rollback_setting` should refuse alert settings (new reason text). Not in this story.
5. **A backup with no on-call person pages nobody** (the AC's "no on-call person … no page is sent"). The same person in both roles gets one page, the Alone variant, and no escalation ("each person at most once"). Recommendation: accept.
6. **Acknowledging one page does not mark the incident's other page.** After an escalation, each person's copy is marked by their own Got it. Recommendation: accept.

**(e) CI.** No new unit and no `ci/units.sh` edit.
- `Test.Watch.Paging` and `Test.Watch.PagingLive` join `shard:lane-a@Watch` in `shards-8` (1,570 s planned). They add about 2-4 min (inference).
- The restart phase adds about 30-60 s to `live:production-restart` in `production` (inference).
- `incident-page.spec.ts` runs in the chromium project (`live:sign-in`, `shards-10`). O1 runs in `shards-4`.
- No `release/**` or `.github/workflows` hunk.

### Governing ADs (Rule 6)
- AD-1: AckPage through CommandsIn; asks through `Commands.Submit` as `system`.
- AD-4: page to the person's own session.
- AD-5: rows are the state, no new timer, committed storage.
- AD-12 and AD-13: the payload, read by object access.
- AD-14: TelegramOut and TelegramIn, the paired-chat check, no chat id.
- AD-15: the paging owner and the table.
- AD-17: one audit writer, no identity.
- AD-18: the escalation timer, through ReminderOps.
- AD-19: the on-call keys, no value in a trace.
- AD-22: tests on throwaways, the mock.
- AD-25: the online demo.
- AD-27: purge with incidents.
- AD-29 and AD-33: lanes; one writer of `Data.Page`.
- AD-32: catalog only.

No AC contradicts an AD's Rule. The lead writes in the spine (Rule 20) only what the Planner approves:
- AD-15's paging bullet gains the Alone variant, "first notice only, never eval", `Watch.Paging`, and the `page` payload;
- AD-14 gains the page button reusing `gotit:`, routed by the Delivery row's Kind.

### Already met (evidence on this branch)
- AckPage routing and origins: `CommandsIn.cls:378`, pinned by `Test.Core.CommandsRouting`.
- `page` and `handled` kinds: `Msg/Enum.cls:30`.
- `Msg.Escalation`: `Msg/Escalation.cls`.
- The on-call keys, their validation and the On call section's demo refusal: 36.4 (`SettingsOps.cls:936-943, 994`; `Web/Api.cls:315`).

### Decided in-stage
1. The page's session is the user's paired session, else their first session row (`ORDER BY ID`, as `ForUser` reads), else `instance`. The page is still recorded, and the escalation is still armed.
2. `AckPage` is accepted only from the session the page was sent to. An address-only page has no acknowledging session until 24.3's path.
3. EscalationRef is `CommandResult.Ref` on Ok 1, else "". A cancel is asked only for a set EscalationRef.
4. The Telegram button reuses `gotit:<ref>`, and TelegramIn picks the verb by the Delivery row's Kind. So the callback list and the mock stay unchanged.
5. Every paging step is wrapped, so a paging failure is one Type 3 warning without on-call values and never fails the notice, the close or the purge.

### Measured (Task 0, a fresh lane-B throwaway, `Test.Watch.PagingLive`; no result contradicts the design)
- (a) Managed Alerts beside OcuTalon, on OCUORDERS:
  - An `Ens.Alert` item (`Ens.Alerting.AlertManager`) with `AlertOnError` 1 on OrdersFromPartner is not enough. Three broken orders gave 3 failed `Ens.Alert` headers ("Notification Manager is not defined for production") and no `Ens_Alerting.ManagedAlert` row. The AlertManager needs the production setting `AlertNotificationManager`, naming an item of class `Ens.Alerting.NotificationManager`. It needs no setting of its own (its stored settings are empty).
  - With both items and the setting: `UpdateProduction` took 0.04 s and started the two new jobs and restarted OrdersFromPartner's. Three broken orders gave 3 `ManagedAlert` rows (source OrdersFromPartner, open) within 0.18 s of sending them.
  - The NotificationManager then fails each request (`ErrNoDefaultNotificationOperation`: no default operation or recipients). The `ManagedAlert` row is saved before that, so the alert is there. The failed requests show as extra failed headers (`Ens.Alert` to the NotificationManager) in OCUORDERS.
  - Removing both items, the production setting and `AlertOnError` leaves the saved definition equal to what it was (every item with its class, pool, enabled and stored settings, and the production's settings). The job list is as before, except that OrdersFromPartner's job restarted (its setting changed); both alert jobs are gone.
  - Decided in-stage: the AC8 fixture is those two items and the production setting. Its extra failures make extra incidents, so AC8's test (`TestManagedAlertsBesidePaging`) asserts a page on any incident of the break, and the Telegram test runs without the fixture.
- (b) A real incident's notice reaches TelegramOut and the mock in a `ci/iris.sh class` stack of the Watch area: 11.2 s after the break (the diagnosis through the mock included), for a fixture session paired through the real /start path. TelegramIn and TelegramOut are enabled with `TelegramPageFixture.Start`. The Telegram cases stay in `PagingLive` (no `TelegramPage` class).
- (c) `Commands.Submit(SetReminder escalation, "system")` answers Ok 0, outcome `not_built`, no Ref, in 0.012 s from a test process. From IncidentManager's job the same ask returned without a deadlock: the incident event that the page method publishes after the ask arrived (asserted in `TestRealBreakPagesTelegram`). The ask's own duration in the job is not measured, and 0.012 s is the (inference) figure: the path is Submit, CommandsIn, ReminderOps, whose pool is not IncidentManager's.
- (d) After an `AckPage` of the page, WebChatOut and SimPhoneOut log nothing for a page copy that has only a bare Delivery row (no warning, no error; Notify neither). There is no 24.3 item from this.
- Initial web bundle: `npm --prefix web run build` gives an initial total of 893.24 kB raw (218.75 kB transfer), under the 1 MB cap. The new web code is one template line and one text in the existing settings chunk; no new chunk.
- Times: `Test.Watch.PagingLive` 59.5 s in its class (185 s with the start on a fresh stack), `Test.Watch.Paging` 7 s warm, `Test.Channel.TelegramDigest` 34.7 s and `TelegramOut` 25.3 s on fresh stacks. The restart phase adds one check and a wait of at most 90 s (the run passed with it).

### Implement-stage notes (decided in-stage)
1. The on-call keys are read with `Setting.Fresh`, not `Get` (once for each page decision, so the 60 s cache has no use, and it would hold a value that a save has changed).
2. `Data.Page.Role` has the SQL field name `PageRole`: ROLE is an SQL reserved word (`Test.Data.Tables` `TestSqlNames`).
3. The session of a page is found from its Person (the first `Data.Session` row of that IRIS user, a paired one first), both when the page is sent and when an `AckPage` is checked against it; an acknowledgement needs no Delivery row.
4. A page warning holds the incident's Ref, the step and the error codes, never a text that an on-call value could be in.
5. An on-call page whose backup is no longer another person when it renders is rendered as `page.onCallAlone`.
6. The escalation ask sets no SessionRef and no IdempotencyKey: Story 24.3 decides both.
7. `Test.Data.Tables` also gains the `SettingChangeRef` property of `Data.Incident` in its contract: Story 23.3's pin there was missing and `TestContracts` was red on the branch.
8. Rule 2: `PagingLive` repeats the sign-in and GET steps of `Test.Web.LiveRolesApi` (its helpers are private instance methods of another story's class) and `Test.Watch.Paging` takes its set-up from `Test.Watch.Tell`.

### Integration ACs (Rule 1) and linkage (Rule 2)
- Integration: AC6 (TelegramOut consumes the page and the mock shows it), AC10 (SettingsOps' GET and the browser consume `Data.Page`'s existence), AC11 (`/state` consumers).
- **Consumes:**
  - the on-call keys (36.2/36.4);
  - AckPage and Escalation (36.2), the not_built escalation (36.2);
  - `Commands.Submit`, `Delivery.DeliveryByRef`, `Session`/`Pairing`;
  - `Watch.Notice`'s slots and 23.3's `cause`;
  - `Bridge.Audit`, `Msg.Catalog.Render`.
- **Consumed-by:**
  - 24.3: Notify's page route; `EmailOut` calls `Watch.Paging.Text(n, "email")` and `page.subject`; ReminderTimer sends `Msg.Escalation` and fills EscalationRef; the web Got it submits AckPage. It replaces the probe's `SendCommand` fixture, the test's direct `Msg.Escalation` send and the generic route.
  - 24.4: the cards read `page`.
  - 36.4's section: `pagesBuilt`.

### Extend, don't copy (Rule 2)
- `Acknowledge` follows `SessionOps.GotIt` and reuses its messages by reference.
- `Page.Marked` mirrors `Handled.Marked`. `EditHandled` gains one fallback line, not a second editor.
- The TelegramOut `page` branch mirrors `summary` (`Watch.Summary.Text`).
- `GotItKeyboard` and the `gotit` press branch are reused.
- `Data.Page` follows `FixRun` and its purge.
- `SendCommand` is a seam like `SendNotice`.
- The tests reuse `Lifecycle`, `IncidentProbe`, `Fixture`, `LiveCase`, and 23.3's `PutTarget`.

### Ledger (Rule 17)
- DW-1277 is addressed by AC10: `pagesBuilt` true over real HTTP, and O1 asserting the line absent.
- DW-1251 stays 24.3's. This story sends address-only pages with SessionRef `instance`, which 24.3 routes.

## Verification

Run every command from the worktree root, one per call with `timeout: 600000`, each sized to about 150 s. Never put two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Tags: fresh `e23b4i`, warm `e23b4iw`. End with `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23b4i`.
- IRIS MCP calls name `server` `ocutalon-slot-b` and `namespace` `OCUTALON`. Settings are written only on throwaways.

**Shared surfaces:**
- The catalog key list and counts (`Test.Msg.Catalog`, Watch 133 rises by the accepted keys; Keys, Fixtures).
- The stored-table registry (`src/short-names.tsv`, `Test.Data.Tables`, `test-storage.sh`, `test-class-rules.sh`) and the purge list (`PurgeOne`, `Test.Watch.Lifecycle` `TestPurge`, `Test.Install.Retention`).
- The incident payload (`Test.Live.Payloads` count 37 to 38, `payloads.ts`, `web/scripts/payloads.test.mjs`).
- TelegramOut `KINDS` and `GOTITKINDS`, and the Telegram callback list (unchanged `gotit:`; `TelegramDigest` 467 still pins tell-now).
- The command verbs (unchanged list; AckPage now answered).
- `pagesBuilt` (`Test.Core.SettingsOnCall` 399/476 pass either way; O1 now asserts true).
- The security overview (unchanged; CI `shards-5`).
- The CI mock scenario list (unchanged).
- `test-class-rules.sh` rules.

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) Task 0: `OCUTALON_RUN_TAG=e23b4i ci/iris.sh class OcuTalon.Test.Watch.PagingLive` with only its Task 0 cases written. Expected: passed, with the figures printed.
- (loop) `ci/warm.sh up` once (`OCUTALON_RUN_TAG=e23b4iw`). Then run `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23b4iw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Watch.Paging`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Transitions`;
  - `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Retention`;
  - `OcuTalon.Test.Core.CommandsRouting`, `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Schedule.Reminders`, `OcuTalon.Test.Core.SettingsOnCall`.

  Expected: each prints `CLASS ... passed`.
- (loop) Fresh, because the production's jobs must hold the new code: `OCUTALON_RUN_TAG=e23b4i ci/iris.sh class OcuTalon.Test.Watch.PagingLive`, then `... OcuTalon.Test.Channel.TelegramDigest`, then `... OcuTalon.Test.Channel.TelegramOut`, one call each. Expected: passed.
- (loop) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-storage.sh`, then `node --test web/scripts/payloads.test.mjs`. Expected: pass.
- (once) `OCUTALON_RUN_TAG=e23b4i ci/iris.sh live production-restart`. If the harness moves it to the background, wait for it with bounded foreground polls. Expected: every PASS, the paging phase included.
- (once) `npm --prefix web run payloads -- --check`, then `npm --prefix web run lint`. Expected: pass.
- (once) `ci/iris.sh build`, then the `live:sign-in-2` part that holds `settings/on-call.spec.ts` and the `live:sign-in` part that holds `api/incident-page.spec.ts` (find them with the part listing), one call each. If a part runs over the call size, leave it to CI (`shards-4`, `shards-10`) and say so.
- Left to CI: the full shards, `live:security-overview`.

Proposed pinning mutations (implement records `mutation:` lines, Rule 19):
- AC1: page inside `Tell`, giving three rows.
- AC2: delete the `OnlineDemo()` check, so the demo case pages.
- AC3: drop the unacknowledged check, so the after-ack case pages the backup.
- AC4: drop the session check, so another session acknowledges.
- AC5: drop the `Apply` hook, so no cancel.
- AC6: TelegramIn submits `GotIt` for a page, so the row is unacknowledged.
- AC7: drop the unique `(IncidentRef, Role)` check or the re-read, so there are two backup rows.
- AC9: drop the `PurgeOne` line.
- AC10: rename `Data.Page`'s compiled check, so `pagesBuilt` is false.
- AC12: put the backup's name into Slots, so the trace scan goes red.

**Mutations run (Rule 19), each applied on a warm lane-B throwaway (or the stated stack), observed red and reverted (the tree byte-identical, `cmp`):**
- mutation: AC1, the `Page` call of `IncidentManager.Deliver` removed: `Test.Watch.Paging` `TestPageAtNotice`, `TestEveryNotice`, `TestAloneAndNotConfigured` and `TestFailuresAreWarnings` red (no page row or Notification).
- mutation: AC2, the `OnlineDemo()` line of `Watch.Paging.Notice` removed: `TestOnlineDemoRefusesByCode` red (the demo case pages).
- mutation: AC3, the acknowledged test of `Watch.Paging.Escalate` dropped: `TestEscalation` red ("an escalation after the acknowledgement pages nobody").
- mutation: AC3 and AC7, the backup row's role made unique and its re-read dropped in `Escalate`: `TestEscalation` red (the backup's page is not the one row of its role). On its own, dropping the re-read leaves `TestEscalation` green, because the unique `(IncidentRef, Role)` index still refuses a second row (defence in depth, not a gap).
- mutation: AC4, the session check of `Watch.Paging.Acknowledge` dropped: `TestAcknowledge` red (another session's and no session's AckPage are handled).
- mutation: AC5, the `Unpage` line of `IncidentManager.Apply` removed: `TestCloseCancels` red (no cancel is asked at the close).
- mutation: AC6, `Channel.Telegram.In.GotIt` made to submit `GotIt` for a page (the Kind page branch off): `PagingLive` `TestRealBreakPagesTelegram` red (the message is not edited, nothing is acknowledged, `/state` stays escalated).
- mutation: AC7, the acknowledged test of `Escalate` dropped, on a fresh stack through `ci/iris.sh live production-restart`: the paging phase red (the acknowledged page's incident gets a backup row too: not 2|1|1).
- mutation: AC8, `AlertOnError` planted in `Fix/Kind/Reroute.cls`: `test-class-rules.sh` `no-alert-config` red. The settings-as-before half (`TestManagedAlertsBesidePaging`, the definition read before and after) was not mutated: it needs product code in IncidentManager's job that writes an alert setting, which the rule above refuses to exist.
- mutation: AC9, the page `DELETE` of `IncidentManager.PurgeOne` removed: `Test.Watch.Lifecycle` `TestPurge` red.
- mutation: AC10, `TestSettingsSaysPagesBuilt`'s expected `pagesBuilt` made 0: red (the assertion reads the server's value, which is 1). The server value is `SettingsOps`' read of `%Dictionary.CompiledClass`, a Lane C file, so it was not mutated; the browser half (`on-call.spec.ts` O1) passed in `ci/iris.sh live sign-in-2 --part 4/4` (49 tests, fresh stack, this story's review pass); its mutation is deferred (frontmatter).
- mutation: AC11, the `Paged` call of `Live.Payload.Incident.FromRow` removed: `Test.Watch.Paging` `TestPageAtNotice`, `TestEscalation` and `TestAcknowledge` red (the events carry no page). The real-HTTP spec `web/e2e/api/incident-page.spec.ts` (the browser half) was type-checked (`npm --prefix web run lint`) and passed in `ci/iris.sh live sign-in --part 1/4` (94 tests, fresh stack, this story's review pass); its mutation is deferred (frontmatter).
- mutation: AC12 and AC13 (trace), the backup's name put into the page Notification's slots (`Watch.Paging.Slots`): `TestPersonIsInNoRecord` red ("the Notifications and the commands hold no name or address").
- mutation: AC13 (audit), the person appended to the audit entry's result (`Watch.Paging.Audit`): `TestPersonIsInNoRecord` red ("and no name or address", the audit), and `TestPageAtNotice` red (the result).
- mutation: AC13 (state), the person put into the payload's state (`Watch.Paging.PagePayload`): `TestPersonIsInNoRecord` red (the state's JSON), with the event assertions and `TestPageAtNotice`, `TestEscalation` and `TestAcknowledge`.
- mutation: AC13 (event), the person put into the published incident event only (`IncidentManager.Page`): `TestPersonIsInNoRecord` red ("the incident events hold no name or address") while the state assertion stays green.
- mutation: AC13 (log), the person appended to the page-not-sent warning (`IncidentManager.Paged`): `TestPersonIsInNoRecord` red ("and the event log holds none").
- mutation: AC14, `telegramOnly` made the old not-yet sentence in `web/src/app/settings/settings-view.ts`: `web/scripts/on-call-view.test.mjs` and `web/scripts/ux-strings.test.mjs` red (2 tests).
- mutation: AC15, `AlertOnError` planted in a product class (`Fix/Kind/Reroute.cls`): `test-class-rules.sh` `no-alert-config` red; its synthetic classes (a write in a product class, in another package, in a string; one in a Test class, in comments and a class that names none) are checked by the rule itself.

Review patches (pass 1), mutations run on the warm lane-B stack (`Test.Watch.Paging`) and on a fresh one (`PagingLive`), each observed red, reverted (`cmp` against a copy made before the mutation, `git status --short` and `git diff --stat` unchanged) and green again:
- mutation: R1 (AC4), `Throw exception` added to the Catch of `IncidentManager.Followed`: `Test.Watch.Paging` `TestAcknowledgeSurvivesFollowUp` red (the AckPage is answered failed, not handled, and the failure is two warnings).
- mutation: R2 (AC5), the `IncidentRoleIndexExists(..., backup)` line of `Watch.Paging.Closing` removed: `TestCloseCancels` red ("no cancel is asked for the timer that has fired").
- mutation: R4 (cause), `Watch.Paging.Slots` made to carry the notice's object cause as its JSON text: `TestSettingChangeCause` red (the slots' cause is not an object, and the text lacks the setting-change sentence).
- mutation: R4 (channels), the channels of `Escalate`'s and `Notice`'s `Record` calls made `DEFAULTCHANNELS`: `TestChannelsAreCopied` red (both the on-call and the backup row).
- mutation: R4 (email), the email key of `page.onCallAlone` made `page.onCallEmail` in `Watch.Paging.Text`: `TestEmailVariants` red (the alone text does not render: the slot 'backup' is missing).
- mutation: R4 (other incident's page), the `first.IncidentRef '= incident.Ref` test of `Escalate` removed: `TestEscalation` red ("an escalation that names another incident's page pages nobody").
- mutation: R5 (AC12, AC13 trace), the backup's name put into every page Notification's slots (`Watch.Paging.Slots`), on a fresh stack: `PagingLive` `TestRealBreakPagesTelegram` red ("the messages of paging hold no user, chat id or display name"), green without it. The positive controls (the trace holds both pages' Refs and the AckPage, the events the incident's Ref and `paged`, the state's incident its Ref and `acknowledged`, and a planted log line is found by the same log search) pass in the unmutated run. The `TestManagedAlertsBesidePaging` source and order change and the `TestPageReachesTelegram` key clearing have no separate mutation: the first is the AC8 half that was already not mutable (product code may not write alert settings), the second only removes a dependence on leftover keys.
- R3 (the restart phase's send order) is a script edit only: `bash -n docker/tests/test-production-restart.sh` passes, and its AC7 mutation above stands unchanged; the run itself is `ci/iris.sh live production-restart`, which is not run in this pass.

**Verified (2026-11-15):**
- Fresh lane-B throwaway: `Test.Watch.PagingLive` (all cases, 59.5 s), `Test.Channel.TelegramDigest` and `Test.Channel.TelegramOut` passed; `ci/iris.sh live production-restart` passed with the paging phase.
- Warm lane-B throwaway: `Test.Watch.Paging`, `Lifecycle`, `Transitions`, `Tell`, `Closing`, `Payload`, `Summary`, `Msg.Catalog`, `Live.Payloads`, `Data.Tables`, `Install.Retention`, `Install.PrivateData`, `Core.CommandsRouting`, `Msg.Contracts`, `Schedule.Reminders`, `Core.SettingsOnCall` and `Bridge.CodeRules` passed.
- `bash docker/tests/test-class-rules.sh`, `test-storage.sh` and `test-boundaries.sh` pass; `npm --prefix web test` (2122 tests), `npm --prefix web run lint`, `npm --prefix web run payloads -- --check` and `node web/scripts/catalog.mjs --check` pass.
- Left to CI: the browser parts that hold `settings/on-call.spec.ts` (`live:sign-in-2`, `shards-4`) and `api/incident-page.spec.ts` (`live:sign-in`, `shards-10`), and the full shards.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** IncidentManager now pages the on-call person once at an incident's first notice (`Watch.Paging`, new `Data.Page`), asks ReminderOps for the escalation timer through a `SendCommand` seam, pages the backup once on `Msg.Escalation`, records `AckPage` and cancels the timer at an acknowledgement or a close. TelegramOut sends the page with a Got it button and TelegramIn turns a paired-chat press into `AckPage`. On the online demo `Watch.Paging` refuses by code. The incident payload carries `page`, the On call section shows the Planner's Telegram-only line when `pagesBuilt` is true, and `no-alert-config` pins that no product class writes alert configuration. Task 0's figures are under Design Notes, Measured; the initial web bundle is 893.24 kB raw.

**Files changed.**
- New: `Data/Page.cls`, `Watch/Paging.cls`, `Live/Payload/Part/Page.cls`, `Test/Watch/Paging.cls`, `Test/Watch/PagingLive.cls`, `web/e2e/api/incident-page.spec.ts`.
- Hooks and appended block: `Watch/IncidentManager.cls` (OnRequest, Deliver, Apply, PurgeOne, the paging block with `SendCommand`).
- Telegram: `Channel/Telegram/Out.cls` (page kind, `Page.Marked` fallback) and `In.cls` (page press submits `AckPage`).
- Payload and catalog: `Live/Payload/Incident.cls`, `Msg/Catalog/Watch.cls` (8 `page.*` keys), `web/src/app/live/payloads.ts` (generated).
- Settings web (Planner-granted): `settings-view.ts`, `on-call-section.ts`, `web/scripts/on-call-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/settings/on-call.spec.ts` (O1).
- Tests and scripts: `Test/Watch/IncidentProbe.cls`, `Test/Data/Tables.cls`, `Test/Live/Payloads.cls`, `Test/Msg/Catalog.cls`, `Test/Watch/Lifecycle.cls`, `docker/tests/test-class-rules.sh` (rule `no-alert-config`), `docker/tests/test-production-restart.sh` (paging phase), `src/short-names.tsv`.

**Review (pass 1).** 45 findings from four layers: high 0, medium 6, low 38, false 1. Patched (R1-R6): the follow-up of an acknowledgement is guarded so a saved acknowledgement is never answered as failed; a close skips a spent timer; the restart phase sends the open incident's escalations last; new tests for a setting-change cause, non-default channels, the email variants and another incident's page Ref; positive controls and the ManagedAlert source in `PagingLive`; header wording. Deferred (frontmatter): the AC14 template mutation, `TestEscalationAsk` going red at 24.3, AC11's spec mutation. Rejected with reasons: see the Review Triage Log (by-design rows trace to the Planner's rulings and Decided in-stage 1-5).

**Follow-up review recommendation:** true. Four medium entries were patched (the follow-up guard, the restart ordering, the setting-change cause test and the PagingLive controls). Unverified risk: the restart phase's negative checks rely on the production's FIFO order of messages, and the AC11 and AC14 browser pins have no demonstrated mutation.

**Verification performed.** Warm stack (lane B): `Test.Watch.Paging`, `Lifecycle`, `Transitions`, `Msg.Catalog`, `Live.Payloads`, `Data.Tables`, `Install.Retention`, `Core.CommandsRouting`, `Msg.Contracts`, `Schedule.Reminders`, `Core.SettingsOnCall` passed; after the patches `Paging`, `Lifecycle`, `Transitions` passed again. Fresh stacks: `Test.Watch.PagingLive` (twice), `Channel.TelegramDigest`, `Channel.TelegramOut` passed; `ci/iris.sh live production-restart` passed with the paging phase; `live sign-in --part 1/4` (94 tests, with `incident-page.spec.ts`) and `live sign-in-2 --part 4/4` (49 tests, with `on-call.spec.ts` O1) passed. `test-class-rules.sh`, `test-storage.sh`, `test-boundaries.sh`, `test-ci-config.sh`, `node --test web/scripts/payloads.test.mjs`, `npm --prefix web run payloads -- --check` and `npm --prefix web run lint` passed. Implementer-stage mutations are recorded in `## Verification`. Left to CI: the full shards, `live:security-overview`.

**Residual risks.** AC8's settings-as-before half and AC10's product-side mutation cannot be demonstrated here (their reasons are in `## Verification`). Pages reach only Telegram and nothing escalates in a real production until Story 24.3 (Planner deviation 2).
