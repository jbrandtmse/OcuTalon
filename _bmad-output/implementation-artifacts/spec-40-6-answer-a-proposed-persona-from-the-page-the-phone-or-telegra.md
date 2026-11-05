---
title: 'Story 40.6: Answer a proposed persona from the page, the phone or Telegram'
type: 'feature'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon's `propose_persona` tool (40.5) reaches `SettingsOps.Propose`, which still answers `not_built` for valid values. Nothing raises the `setting` request, notifies anyone or acts on its `ApprovalOutcome`. The page would also draw a setting request as "Repair and resend", because nothing renders its old and new values.

**Approach:**
- `SettingsOps` raises the `setting` request (40.5's bridge contract) and sends one `approval.persona` notice to the owner's channels.
- On the outcome it applies the stored new value, or reports it stale, and sends the answered and result notices itself (AD-11, AD-32).
- `WebChatOut` shows the persona notices as chat cards, the approval payload carries old/new as the dry run's `before`/`after`, and the card and the rail draw the UX's setting card.
- The four inbox entries are closed: DW-570 (owner binding), DW-571 (403 text), DW-669 (PUT body bounds) and DW-709 (preset strings in the UX inventory).

## Boundaries & Constraints

**Always:**
- The values come only from the server: the session is the bridge context's owner (DW-570) or the CSP session's. On approval `SettingsOps` writes only the row's stored `new` values, re-read through the Approval API (`StartExecution`), never a value from a message or a model.
- The persona is written as `SavePersona` writes it: Settings audit entry first (`setting` `persona`, `from`/`to` in `AuditForm`, never the custom text), then the three `person.<S>.persona.*` keys in one transaction.
- Every notice is an `OcuTalon.Msg.Notification` with `SessionRef` = the row's `OwnerRef` and `ApprovalRef` = the row's Ref, sent to `Notify`. For one outcome the answered notice goes before the result notice, because `TelegramOut` edits the newest Delivery row of the Ref.
- Public text comes only from these sources:
  - EXPERIENCE.md :1031 (card), :1028 (pending note) and :692 (the approver sentence);
  - the 40.1 catalog keys `approval.persona`, `persona.applied`, `persona.stale` and `answered.*`;
  - the owner-kept API text "Only an approver can answer this request." (U-114);
  - existing `CommandsIn`/`SettingsOps` messages.
  No text claims the reply guard covers other languages.
- ObjectScript and TypeScript source stays ASCII (Rule 14). Contended files get only self-contained edits (Design Notes, Footprint).

**Never:**
- Any bridge file (`src/bridge/**`): the `setting` kind, the hold and Reconcile are 40.5's and stay as built. Also never `BridgeSink.cls`, `Live/Publish.cls`, `Test/Live/Payloads.cls` (Epic 39), `Agent/Triage.cls`, `Checks/**`, `Msg/Enum.cls`, `Msg/Catalog/**`, `web/e2e/support/**`, `docker/**`.
- A new catalog key, payload class or property, live event type or `Delivery` column.
- The real Telegram bot or a model key: Telegram runs only against the CI mock.
- A second persona writer: the route and the tool still only submit commands.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Propose | `ProposePersona` `{preset: pirate}` for session S (local install, S on Professional), inside S's bridge context | One `setting` row: OwnerRef S, ResultTarget `SettingsOps`, TraceRef = S's `TraceRef`, DryRun `{"key":"person.S.persona","ownerRef":S,"old":{"preset":"professional","language":"","custom":"","text":"Professional (default)"},"new":{"preset":"pirate","language":"","custom":"","text":"Pirate"}}`. One Notification: kind `approval`, key `approval.persona`, Slots `{"old":"Professional (default)","new":"Pirate"}`, ApprovalRef = the Ref. Answer: Ok 1, Outcome `proposed`, Ref = the Ref, Message the pending note. No key and no Settings audit written | No error expected |
| Display text | new `language` "Spanish"; new `custom` "Talk like a lighthouse keeper."; current `language` "Portuguese (Brazil)" | `text` is the preset's `Agent.Persona` name, the language name for `language`, or the custom text for `custom`. The object keeps `preset`, `language`, `custom` as validated (unused values ""). Slots `old`/`new` = the `text`s | No error expected |
| Propose refused | bad values; online demo; no session row | As today: bad_preset, bad_language, bad_custom, custom_not_offered, `not_available`, `no_session`. No row, no notice | refusal |
| Another session (DW-570) | inside A's context: SessionRef B, "" or A in other case | `CommandsIn` answers `not_allowed` with `MESSAGENOTFROMTOOL`. Nothing reaches `SettingsOps` | refusal |
| Raise fails | `Approval.Raise` returns an error | Ok 0, `failed`, `CommandsIn.MESSAGEFAILED`. No notice; the error is logged | logged |
| Approved, unchanged | `ApprovalOutcome` approved; row state approved; current values = `old` | `StartExecution`; one Settings audit entry (persona, from `professional`, to `pirate`, irisUser = row.AnsweredBy, sessionRef S, channel = row.AnsweredChannel); then the three keys; `FinishExecution` `done`. Notices in order: kind `answered` `answered.approved` {channel, time} from the row, then kind `result` `persona.applied` {} | No error expected |
| Approved, stale | current values differ from `old` in preset, language or custom (an empty stored preset reads as `professional`) | Nothing written or audited; `FinishExecution` `failed`; `answered.approved` then `persona.stale` | No error expected |
| Rejected / expired | outcome `rejected` / `expired`, row in that state | Nothing written. One kind `answered` notice: `answered.rejected` {channel, time} / `answered.expired` {time: ExpiresAt}. No result notice, no row change | No error expected |
| Can't start / can't write | `StartExecution` refuses (past expiry), or the audit/key write fails | Nothing written (a write rolls back); `FinishExecution` `failed`; the answered notice only; logged | logged |
| Not ours / repeat | unknown Ref; Kind not `setting`; ResultTarget not `SettingsOps`; DryRun key not `person.<OwnerRef>.persona` or `ownerRef` not OwnerRef; outcome not approved/rejected/expired; row.State not the outcome (a repeat) | Dropped with one warning: nothing written, no notice, no row change | logged |
| Payload | `Live.Payload.Approval.FromRow` of a setting row: old/new objects; old/new strings (40.5 fixtures); old/new missing | `dryRun.before` / `after` = the objects' `text`, the strings, or "" (no error); every fix field empty, `eitherWay` false | No error expected |
| Card | page payload kind `setting`, pending, before "Professional (default)", after "Pirate", with or without the notice text | Title "Change how OcuTalon talks to you" (no period). Lines "Now: Professional (default)", "Proposed: Pirate", "Nothing changes unless you approve.". Buttons named "Approve: change how OcuTalon talks to you" / "Reject: ...". No dry-run block and no fixed-targets line. Answered: the note goes and the status line is the one every request has. The rail and phone title is the same | No error expected |
| 403 (DW-571) | page answer to a setting request refused `not_allowed` | 403 `not_allowed` "Only an approver can answer this request." from its own parameter (never the fix text) | refusal |
| PUT bounds (DW-669) | `professional` + 100 KB custom (and language); `custom` + 1,001-unit custom; `language` + 41-character language | 200 and the SetPersona has `Custom`/`Language` ""; 400 `bad_custom` / `bad_language` with `SettingsOps`' message and no SetPersona sent. A 1,000-unit custom and a 40-character language are forwarded | refusal |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (Epic 40's):
  - `Carry` L86-94 (an `ApprovalOutcome` falls to `unknown_command` today).
  - `SavePersona` L196-234 (the audit-then-transaction write to extract), `Propose` L238-246 (`not_built`), `HasSession` L250, `PersonaProblem` L270, `AuditForm` L294, `PersonaKey` L301, `Stored` L141.
  - `AuditData` L127-138 (channel only from origin via `CHANNELS`), `WriteAudit` L148 (a seam), `Result` L366.
  - Class comment L1-38 lists the outcomes; `not_built` for ProposePersona must go.
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls` -- `Preset(id)` L71 gives `name` (L17-53: "Professional (default)", ..., "Another language"). Read only.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- READ ONLY:
  - `Raise(row, .ref, sinkClass, sessionId, superSession)` L102; `$TLevel > 0` is refused.
  - `ValidateSetting` L249-278; `SETTINGKEYS` L77.
  - `StartExecution(ref)` L436 (approved to executing only before ExpiresAt).
  - `FinishExecution(ref, result)` L446 (executing to done/failed; approved to failed with `failed`).
  - Data row: `Bridge.Data.ApprovalRequest`, `RefIndexOpen`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- READ ONLY sibling:
  - `Outcome` L1162-1171 (drop unless `row.State = outcome.Outcome`) and `AnswerNotice` L1176-1188 (keys, slots).
  - `RaiseRequest` near L963 (Raise with sessionId/superSession) and `SendNotice` L1324 (`SendRequestAsync("Notify", n, 0)`).
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` (Epic 34 contended): Dismiss check L78-82; SendDigest check L83 (the shape to copy); `TOOLVERBS` comment L32-33; `MESSAGENOTFROMTOOL` L40.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (Epic 34 contended):
  - `AnswerResponse` L580 (`$Select(kind = "fix": ..., 1: ...TOOL)`), `MESSAGENOTAPPROVERTOOL` L112.
  - `PutPersona` L1245-1281 with doc L1235-1244, and `PersonaBody` L1286-1304: Epic 40's block at the class end.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- `ToolCallCard` L73-79 (kind approval/result, ApprovalRef, the five `BridgeSink` keys read by `$Parameter`); class comment L12-16; `OnNotification` L59-70.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` -- `FromRow` L86-110 parses `DryRun` into `Part.DryRun` (`Before`/`After` strings), with no kind branch. `Watch.Notice.Reading` gives "" for a setting.
- Notice routing, unchanged:
  - `Core/Rule/Notify.cls:29-54`: web always, phone when demo mode is on, Telegram when paired.
  - `Channel/SimPhone/Out.cls` and `Channel/Telegram/Out.cls`: buttons for kind `approval` with an ApprovalRef; the in-place `EditAnswered` on kind `answered`.
  - `AnswersIn.TelegramCode` L86-120: an approve press on a setting has no count, so no toast text.
- Web:
  - `web/src/app/approvals/approval-view.ts`: `APPROVAL_TEXTS` L34-60, `ApprovalView` L102-125, `approvalView` L265-294 (a request text replaces the title), `statusOf` L246, `dryRunView`.
  - `web/src/app/approvals/approval-request-card.ts`: the template L106ff, `view` L465.
  - `web/src/app/rail/rail-view.ts`: `approvalTitle` L174-184, `RAIL_TEXTS`.
  - `web/src/app/chat/chat-view.ts`: `noticeOf` L214 already takes approval/result notices with an approvalRef; `liveRequest` L255.
  - `web/src/app/phone/phone-request.ts` L48, L239: uses `approvalTitle` and `approvalView`, no edit expected.
  - `web/src/app/rail/persona-card/persona-card-view.ts` `PRESETS` L43-50.
- `web/scripts/ux-strings.test.mjs`: IMPORTED L40-65 (`RAIL_TEXTS` L44, `APPROVAL_TEXTS` L53); `fromSource` L92-108 (`THEME_OPTIONS`' `matchAll` pattern); SOURCES persona entries L457-466 ("Your own words" L463). The ledger's recipe is in `deferred-work.md` DW-709.
- Tests to extend or read:
  - `Test/Core/SettingsPersona.cls`: probe helpers `Send` L409, `Audits`, `AuditData`, `Session`; `TestProposePlaceholder` L299-309 asserts `not_built`. `Test/Core/SettingsOpsProbe.cls` holds the seams (`WriteAudit`, `Apply`, ...).
  - `Test/Core/CommandsRouting.cls`: `TestContextDismissSeesOwnIncidentOnly` L270 (context set-up L279-282), `TestPersonaVerbsInsideAContext` L187. `Test/Core/SettingsCommands.cls` `TestSendDigestOwnSessionOnly` L121 (the row set to copy).
  - `Test/Core/AnswersInProduction.cls` `TestRoleRefusalsComeBeforeTheOtherChecks` L142-167, `Post` L463, `Request` L442.
  - `Test/Web/PersonaApi.cls` (`Put` L467, `Fixture.Between(...,"CommandsIn","SettingsOps")` L174-179, none-sent L302) and `Test/Web/PersonaApiProbe.cls`.
  - `Test/Core/WebChatOut.cls`, `Test/Core/ToolCallNotices.cls`: pin `ToolCallCard`.
  - `Test/Channel/LiveCase.cls` (read only, abstract): `BeginPairing` L758, `EndPairing` L786, `PairChat` L885, `ButtonPress` L848, `Handled` L857, `EditsTo` L674, `TextsTo` L721, `KeyboardTo` L710, `WaitAnswers` L698.
  - `Test/Channel/TelegramApproval.cls` is the model to follow: `TestLate` L267 (late alerts), `TestApprove` L211 (audit via `Test.Bridge.AuditLog`), `TestEveryCopy` L445 (Telegram edit + `RecentPhone(...).Answer`), `WebSession` L107, `Tidy` L94. Fixture chat ids 84017734101-149 are taken.
  - `Test/Bridge/ApprovalRows.cls` `SettingDryRun` L39 (string old/new), `Test.Data.Fixture.Approval` L108.
- Web tests: `web/scripts/approval-view.test.mjs` (tool-call cases L131-162), `rail-view.test.mjs` L250, `approval-sources.test.mjs` L175-203 (template rules).
- e2e:
  - `web/e2e/persona-card.spec.ts` (PC5 L214: a seeded setting request draws no chat card).
  - `web/e2e/reminder/chat.spec.ts` and `chat/notice.spec.ts`: the chat-turn-with-`[[mock:...]]` pattern.
  - `web/e2e/support/persona.ts` (`prepare`/`forget`, import only).
  - `ci/mock/scenarios/A/persona-propose.json` (40.5: `propose_persona` `{"preset":"pirate"}`, then "The CI mock suggested the persona.").

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- Changes:
  - New parameters: `MESSAGEPROPOSED` = "OcuTalon suggested a change. It waits for your answer in Approval requests." (EXPERIENCE.md :1028) and `RESULTTARGET` = "SettingsOps".
  - Two seams, as `WriteAudit` is:
    - `Method RaiseRequest(row, Output ref) As %Status [Private]` calls `Bridge.Approval.Raise(row, .ref, , ..%SessionId, ..%SuperSession)`.
    - `Method SendNotice(notification) As %Status [Private]` calls `..SendRequestAsync("Notify", notification, 0)`.
  - `Propose`: after the existing checks, it builds `old` from the stored values (`Stored`, an empty preset read as `professional`) and `new` from the validated command (an unused value ""), each `{preset, language, custom, text}` (matrix "Display text").
    - It raises a `setting` row with Kind, OwnerRef, TraceRef (the Session row's), DryRun and ResultTarget.
    - It sends the `approval.persona` notice and answers Ok `proposed` with the Ref and `MESSAGEPROPOSED`.
    - A raise error answers `failed`. A notice send error is logged and the answer is still `proposed`, because the request exists and the rail shows it.
  - `Carry` routes `OcuTalon.Bridge.Msg.ApprovalOutcome` to a new `Outcome(outcome)`. It runs the matrix rows "Approved ..." to "Not ours / repeat", in the `IncidentManager.Outcome` pattern; the answered notice is its `AnswerNotice` keys and slots.
  - Extract `SavePersona`'s audit-then-transaction write into one private `WritePersona(irisUser, sessionRef, channel, origin, preset, language, custom) As %Status`, used by both `SavePersona` (its outcomes unchanged) and `Outcome`. `AuditData` gains a trailing optional `channel` that overrides the origin's.
  - Update the class comment: ProposePersona raises, the outcome handling, the `proposed` outcome; `not_built` removed.
  -- AC 1, 3.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- One new check line after L83:
  - `If (origin = "tool") && (verb = "ProposePersona") && ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit ..Result("not_allowed", ..#MESSAGENOTFROMTOOL)`.
  - The `TOOLVERBS` comment L33 gains "and only for the context owner's own persona".
  - Nothing else in the file -- AC 5 (DW-570).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- Changes:
  - L580 gains one arm: `kind = "setting": ..#MESSAGENOTAPPROVERSETTING`.
  - `Parameter MESSAGENOTAPPROVERSETTING = "Only an approver can answer this request.";` goes in the persona block at the class end, after `SubmitPersona`.
  - `PutPersona`, after `PersonaBody`:
    - `language` is set to "" unless the preset is `language`, and `custom` to "" unless it is `custom`.
    - A used `language` over 40 characters gives `Fail(400, "bad_language", SettingsOps.#MESSAGEBADLANGUAGE)`, and a used `custom` over 1,000 (`$Length`, UTF-16 units, as `PersonaProblem`) gives `Fail(400, "bad_custom", SettingsOps.#MESSAGEBADCUSTOM)`. Neither submits anything.
    - Its doc comment says so.
  -- AC 6 (DW-571), AC 7 (DW-669).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- `ToolCallCard` also accepts `SettingsOps`' three keys, read by `$Parameter` (new `SettingsOps` parameters `KEYPROPOSED` = `approval.persona`, `KEYAPPLIED` = `persona.applied`, `KEYSTALE` = `persona.stale`, which `SettingsOps` itself uses). The class comment names them. Kind `answered` stays Delivery-only -- AC 1.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` -- In `FromRow`, a `setting` row maps `old`/`new` into `Part.DryRun.Before`/`After`: the object's `text`, a string as it is, "" when missing. It reads no fix field and skips `Reading`. The doc comment says so -- AC 2.
- `web/src/app/rail/rail-view.ts` -- `RAIL_TEXTS.changePersona` = 'Change how OcuTalon talks to you'. `approvalTitle` returns it for `kind === 'setting'`. Doc comment updated -- AC 2.
- `web/src/app/approvals/approval-view.ts` -- Changes:
  - `APPROVAL_TEXTS` gains `settingNow: 'Now: {old}'`, `settingProposed: 'Proposed: {new}'` and `settingNote: 'Nothing changes unless you approve.'`.
  - `ApprovalView` gains `setting: {now, proposed, note} | undefined`.
  - For a setting, `approvalView` takes the title from `ctx.title` and ignores the request text. Its `action` is the title with no added period. `dryRun` and `fixedTargets` are empty. `setting` holds the lines, and `note` is "" unless pending (as `nothingYet`).
  - This extends `approvalView`/`dryRunView` (a sibling builder `settingView`) -- AC 2.
- `web/src/app/approvals/approval-request-card.ts` -- one `@if (view().setting; as setting)` block drawing the three lines by interpolation only, in the dry run's place, with existing tokens -- AC 2.
- `web/scripts/ux-strings.test.mjs` -- Changes:
  - Add `ux` SOURCES entries for the four new strings (EXPERIENCE.md :1031).
  - DW-709: a `fromSource` `matchAll` over `persona-card-view.ts` `PRESETS` (`{ id: Q, name: Q, description: Q }`, an exact count of 6) pushes each name and description, and 11 `ux` entries are added ("Your own words" is already there). `PRESETS` is not added to IMPORTED (the ids are not UX text).
  -- AC 2, AC 8.
- `web/scripts/approval-view.test.mjs`, `web/scripts/rail-view.test.mjs` (and `approval-sources.test.mjs` if its template rules list blocks) -- the Card rows: pending with and without notice text, answered (note gone, status kept), and the title in the rail. These are the pins for AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` -- override `RaiseRequest` (record the row's fields to `^OcuTalonTest("SettingsOpsProbe","raised",n,...)`; answer a fixed Ref or the error in `^OcuTalonTest("SettingsOpsProbe","raise")`) and `SendNotice` (record Kind, CatalogKey, Slots, ApprovalRef and SessionRef in order) -- AC 1, 3.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsPersona.cls` -- Changes:
  - `TestProposePlaceholder` becomes `TestProposeRaises`: the matrix rows "Propose", "Display text", "Propose refused" and "Raise fails".
  - New outcome tests on the probe, with real `setting` rows from `Test.Data.Fixture.Approval` (or `ApprovalRows.Save`) in the needed state and real `StartExecution`/`FinishExecution`: `TestOutcomeApplies`, `TestOutcomeStale` (one test per differing field), `TestOutcomeRejectedOrExpired`, `TestOutcomeCannotStart`, `TestOutcomeWriteFails` (audit refused through the probe), `TestOutcomeNotOurs`.
  - Each asserts the keys, the Settings audit calls, the row's final state and the exact notice sequence.
  - Header updated.
  -- AC 1, 3.
- `src/ocutalon/cls/OcuTalon/Test/Core/PersonaAnswers.cls` -- new, `Extends OcuTalon.Test.Channel.LiveCase`, throwaway only, Telegram mock, fixture chats 84017734150-84017734159, sessions `zzpansw...`, the `TelegramApproval` set-up and clean-up pattern. Tests:
  - `TestProposalReachesEveryChannel`: a `ProposePersona` submitted through `Commands.Submit` inside S's bridge context (as `CommandsRouting` does). Then:
    - the answer, the row and the DryRun;
    - the web chat's Delivery row with the rendered text and its `notification` event;
    - the phone message with the ApprovalRef;
    - Telegram's `sendMessage` text (the catalog's) and keyboard `approve:<ref>`/`reject:<ref>`;
    - the live approval payload's `dryRun.before`/`after`.
  - `TestWebFirstWins`: web approves through `AnswersIn.FromPage`. Then:
    - a phone `FromPage` answer is `already_answered` with the web winner;
    - a Telegram press gets "Already answered: approved from the web chat at ..." as an alert;
    - the persona is Pirate;
    - the Telegram copy is edited and the phone copy's `Answer` reads "Approved from the web chat at ...";
    - `persona.applied` reaches web, phone and Telegram;
    - the audit holds exactly one `answered` Approval entry (channel web, the session, the user) and one Settings `persona` entry.
  - `TestTelegramFirstRejects`: a Telegram reject press, then web and phone are late. Every copy reads "Rejected from Telegram at ...", the persona is unchanged, there is no result notice, and there is one `answered` entry.
  - `TestStaleProposal`: SetPersona Kind friend after the proposal, then approve. `persona.stale` reaches the channels, the persona stays Kind friend, and the row is `failed`.
  - `TestSettingPayload`: `FromRow` for object, string and missing old/new.
  -- AC 1, 3, 4.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` -- a `TestProposePersonaOwnSessionOnly` covering the "Another session" row (B, "", case variant: `not_allowed` with the message and no owner call), plus A's own being routed (the `TestSendDigestOwnSessionOnly` rows) -- AC 5.
- `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls` -- `TestRoleRefusalsComeBeforeTheOtherChecks` (or a sibling test) gains a `setting` row: 403 `not_allowed` with "Only an approver can answer this request." -- AC 6.
- `src/ocutalon/cls/OcuTalon/Test/Web/PersonaApi.cls` -- `TestPutDropsUnusedValues` and `TestPutBoundsUsedValues` (the PUT bounds rows, read through `Fixture.Between` on the real production) -- AC 7.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls` -- the three persona keys with an ApprovalRef make cards (row text and event); without an ApprovalRef, or with kind `answered`, they do not -- AC 1.
- `web/e2e/persona-approval.spec.ts` -- new, chromium project (`live sign-in`), README account, `support/persona.ts` `prepare`/`forget` in `finally`:
  - PA1: send "[[mock:persona-propose]] ..." in the chat. The chat shows the setting card (title, "Now: Professional (default)", "Proposed: Pirate", the note, both buttons); the rail lists "Change how OcuTalon talks to you"; the Persona card shows the pending note. Approve, then: the card's status line reads "Approved from the web chat at ..." with no note; the chat shows "Persona updated. It applies from your next message."; GET `/v1/persona` reads `pirate`.
  - PA2: the same with Reject. The status reads "Rejected from the web chat at ... Nothing was changed.", the persona stays Professional, and no applied notice appears.
  -- AC 2, AC 9.

**Acceptance Criteria:**
1. Given a `ProposePersona` for the context owner's own session with valid values, when `SettingsOps` handles it, then it raises one `setting` request with the matrix's DryRun and `ResultTarget` `SettingsOps`, answers `proposed` with the request's Ref, writes no persona key, and sends one `approval.persona` notice that the web chat, the simulated phone and the paired chat each show with Approve and Reject. Invalid values, the online demo and a missing session are refused as before.
2. Given a pending `setting` request, when the page draws it in the chat, the rail or the phone, then the title is "Change how OcuTalon talks to you" and the card shows "Now: {old}", "Proposed: {new}" and "Nothing changes unless you approve." with Approve and Reject. Once answered, it shows the answered status every request has, without the note.
3. Given an `ApprovalOutcome` for a `setting` request, when `SettingsOps` handles it, then:
   - approved with unchanged values: it writes the stored `new`, audits it, records `done` and sends `answered.approved` then `persona.applied`;
   - approved with changed values: it writes nothing, records `failed` and sends `answered.approved` then `persona.stale`;
   - rejected or expired: it sends only the answered notice, which edits each copy in place;
   - an outcome that isn't its own, or a repeat: it is dropped.
4. Given a proposal answered from the web chat, the simulated phone and the paired chat (Telegram mock), when the answers arrive, then the first wins, each late answer shows who answered and where, every copy is edited to the winner's status, and the audit holds exactly one `answered` entry for the request (late answers change nothing and write none) plus, on approval, one Settings `persona` entry.
5. Given a bridge context of session A, when a tool submits `ProposePersona` with another SessionRef, then `CommandsIn` refuses it `not_allowed` and `SettingsOps` receives nothing (DW-570).
6. Given a page answer to a `setting` request that `AnswersIn` refuses `not_allowed`, when the route answers, then it is 403 with the setting's own approver parameter, "Only an approver can answer this request.", never the fix text (DW-571).
7. Given `PUT /v1/persona`, when the body carries values the preset does not use, or a used value over its limit, then the unused values never reach `SetPersona`, and the over-limit value is refused 400 with `SettingsOps`' code and message and nothing submitted (DW-669).
8. Given the UX inventory, when `ux-strings.test.mjs` runs, then the six preset names and descriptions and the four new card strings are inventoried with `ux` sources, and the test passes (DW-709).
9. Integration: given a real Chat turn whose model (CI mock) calls `propose_persona`, when the person approves the card on the page, then the persona card and GET `/v1/persona` show Pirate, and the chat shows `persona.applied`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing decisions:**
- AD-1: tool verbs, origin and `CommandsIn` checks; DW-570 implements "a change to the session's own persona".
- AD-4: the session is the server's.
- AD-11: the `setting` bullet (the owner raises, re-reads with `StartExecution`, writes only the stored value, `failed` when stale, and sends its own notices).
- AD-14: Notify routing; in-place edits through `Delivery`.
- AD-17: the Settings and Approval audit entries; never the custom text.
- AD-19: the `person.<S>.persona.*` keys.
- AD-26: trace sessions; Raise gets the current session.
- AD-29: Lane B story files.
- AD-31: `BridgeSink`'s rules unchanged.
- AD-32: kinds `approval`, `answered` and `result`; producers never render.
- AD-33: `WebChatOut` stays the one publisher of `notification`.
- AD-2 is untouched: no bridge file changes. No AD's Rule is contradicted, so the spine needs no change.

**U-268.** AD-1's SendDigest amendment (33.2) is the model for DW-570: "inside a bridge context a `SessionRef` that is not the context's `OwnerRef` is refused (`not_allowed`) and nothing is sent". The new line is that one, for `ProposePersona`. AD-14's 33.2 additions (digest routing, Got it) are not touched.

**Decided in-stage:**
- *DryRun values.* `old`/`new` are objects `{preset, language, custom, text}`. A display string alone can't tell the language "Pirate" from the Pirate preset, and the stale check compares values. `text` follows the AC: the preset's name, the language, or the custom text.
- *Proposed answer.* The Message is the UX's pending note, so no new sentence is shipped; the tool (40.5) shows the model `proposed`.
- *DW-570 refusal.* `not_allowed` with `MESSAGENOTFROMTOOL`, as SendDigest. The ledger's "not_found" suggestion would use Dismiss's incident sentence. Outside a bridge context nothing changes, as for SendDigest.
- *DW-571 text.* The ledger allows "the plain approver sentence". The owner kept "Only an approver can answer this request." as the API 403 text (U-114). The setting gets its own parameter with that text, so a later change to the tool-call wording can't reach it. Its pin is the mutation to the fix text.
- *Audit of an approved change.* irisUser = the row's `AnsweredBy` and channel = `AnsweredChannel` (web, phone or telegram; Bridge `CHANNEL`), so the entry names who approved and from where (AD-17).
- *Audit per answer (FR-9).* Only an answer that takes effect is audited (the bridge's `answered` entry). A late press changes nothing and writes no entry. So "one entry per answer" is one `answered` entry for the request.
- *Failure paths.* A start refused past expiry or a failed write closes the row `failed` and sends only the answered notice, because there is no accepted sentence for it. Both are rare and logged.
- *Card note.* "Nothing changes unless you approve." shows only while pending, like `nothingYet`; answered cards keep the status line.
- *Payload.* old/new go into `Part.DryRun.Before`/`After`, which already exist, rather than a new property or part. That avoids changing `Test/Live/Payloads.cls`' contracts and count, which Epic 39 has changed.
- *Telegram approve press.* There is no toast, because a setting has no count (`press.approved` is the fix's sentence); the message edit and `persona.applied` follow.
- *Duplicates.* A proposal is not refused when another is pending or when new equals current. Approving one makes the other stale, which the stale path handles.

**Integration ACs (Rule 1/2).** AC 9 (e2e on a real stack) is the consumer test: Chat's `propose_persona` drives the real `SettingsOps` with no double, and the page shows and answers the card. AC 4 tests the Telegram and phone consumers against the real production with the mock bot.
- Consumes:
  - 40.5: the `setting` kind, `ApprovalOutcome` delivery, `propose_persona`, `persona-propose.json`;
  - 40.2: `SettingsOps` validation and keys;
  - 40.1: the catalog keys, `Agent.Persona`;
  - 40.4: the Persona card's pending note;
  - 40.8: `PUT /v1/persona`;
  - Epics 6, 12 and 31: `AnswersIn`, Telegram and phone buttons and edits.
- Consumed-by: 40.7 (its injection case expects no proposal, and its real-model pass may propose one).

**Extend, don't copy (Rule 2):**
- `WritePersona` is extracted from `SavePersona`, which now uses it.
- `Outcome`/answered notice follow `IncidentManager.Outcome`/`AnswerNotice`, written in `SettingsOps` because that file belongs to another owner and lane and builds per-incident notices for many recipients; this is about 15 lines of key choice.
- `ToolCallCard`, `approvalTitle`, `approvalView`, `SettingsOpsProbe`, `CommandsRouting` and `AnswersInProduction` are extended.
- `PersonaAnswers` subclasses `LiveCase`, the shared toolkit.

**Footprint (Rule 11), checked at plan (HEAD 35f7713c):**
- Contended, Epic 34 (not yet changed by it):
  - `Core/CommandsIn.cls`: one new check line after L83, plus the end of one comment line (L33).
  - `Web/Api.cls`: one new `$Select` arm at L580, one parameter added to the persona block at the class end, and edits inside Epic 40's own `PutPersona` doc and body.
- Footprint extensions (no open epic has changed them): `Channel/WebChat/Out.cls`, `Live/Payload/Approval.cls`, `web/scripts/{ux-strings,approval-view,rail-view,approval-sources}.test.mjs` (Epic 39 changes only `payloads`/`live-store` tests there).
- No edit to `web/e2e/support/**` (Epic 11), the bridge or `Msg/Catalog/Watch.cls` (Epic 17), or `Test/Live/Payloads.cls`, `Live/Publish.cls` or `payloads.ts` (Epic 39).
- The implement stage re-checks `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` (17, 34, 11, 39) before its first edit.

**Ledger inbox (Rule 17):** DW-570 → AC 5; DW-571 → AC 6; DW-669 → AC 7; DW-709 → AC 8. None is declined.

## Verification

All calls run from the worktree root with `timeout: 600000`, one per call.
- `<D>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=40 stage=implement'`.
- Fresh tag `e40s6i`, warm tag `e40s6iw`.
- IRIS MCP: `server` `ocutalon-slot-d`, `namespace` `OCUTALON`, after `iris_server_info`; one `iris_execute_tests` per message.
- Classes whose production jobs run changed code (`SettingsOps`, `WebChatOut`) are proved on fresh stacks.
- Web changed, so run `ci/iris.sh build` before any browser unit.

**Commands:**
- (loop) `iris_doc_load` the changed and new classes (absolute `baseDir` `.../src/ocutalon/cls`) into slot D and compile -- expected: they compile.
- (loop) `git diff --stat 35f7713c -- src/bridge src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls src/ocutalon/cls/OcuTalon/Live/Publish.cls src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls src/ocutalon/cls/OcuTalon/Msg web/src/app/live web/e2e/support docker` -- expected: empty.
- (loop) one per call: `node --test web/scripts/approval-view.test.mjs`, `node --test web/scripts/rail-view.test.mjs`, `node --test web/scripts/ux-strings.test.mjs`, `node --test web/scripts/approval-sources.test.mjs`, `node --test web/scripts/phone-request-sources.test.mjs` -- expected: pass.
- (loop) `npm --prefix web run lint`, then `npm --prefix web run build` -- expected: pass.
- (loop) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, one per call -- expected: pass (ASCII; `PersonaAnswers` in area Core, shard lane-b).
- (loop) `<D> OCUTALON_RUN_TAG=e40s6iw ci/warm.sh up` once. Then one per call `<D> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e40s6iw ci/iris.sh class <C>` for `OcuTalon.Test.Core.SettingsPersona`, `.Core.CommandsRouting`, `.Core.SettingsCommands` and `.Core.SettingsOps` -- expected: `CLASS ... passed`. At the stage's end, also after a failure, run `<D> OCUTALON_RUN_TAG=e40s6iw ci/warm.sh down`.
- (loop) fresh, one per call `<D> OCUTALON_RUN_TAG=e40s6i ci/iris.sh class <C>` for `OcuTalon.Test.Core.PersonaAnswers`, `.Web.PersonaApi`, `.Core.AnswersInProduction`, `.Core.WebChatOut`, `.Core.ToolCallNotices`, `.Tools.Persona` -- expected: passed each.
- (loop) `<D> OCUTALON_RUN_TAG=e40s6i ci/iris.sh build`, then `<D> OCUTALON_RUN_TAG=e40s6i ci/iris.sh live sign-in --part k/3` for each part whose `PART` line lists `persona-approval.spec.ts`, `persona-card.spec.ts`, `rail/rail.spec.ts` or `api/persona.spec.ts` (find them with `npm --silent --prefix web run e2e -- --list`) -- expected: the part passes.
- (once) `npm --prefix web test` -- expected: every node test passes.
- (once) fresh, one per call, each with `<D> OCUTALON_RUN_TAG=e40s6i`:
  - `ci/iris.sh shard lane-b@Core`, then again with `--reverse` (use `--part k/2` if a run nears the cap);
  - `ci/iris.sh class OcuTalon.Test.Channel.TelegramApproval`;
  - the remaining `live sign-in` parts;
  - `OCUTALON_LIVE_DEADLINE=700 ci/iris.sh live demo-path`;
  - then `ci/iris.sh teardown`.
  Expected: all pass.
- (once) `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-readme.sh`, one per call -- expected: pass. The rest of `CHECK_SCRIPTS` and of the shards and groups is left to CI.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):**
- AC 1: `Propose` answers before raising (no `RaiseRequest`) -> `SettingsPersona:TestProposeRaises` red; `ToolCallCard` without the persona keys -> `WebChatOut` persona test and `PersonaAnswers:TestProposalReachesEveryChannel` red.
- AC 2: `approvalTitle` without the setting branch -> `rail-view.test.mjs` and PA1 red; `approvalView` honouring the request text for a setting -> `approval-view.test.mjs` red.
- AC 3: the stale comparison removed (always apply) -> `TestOutcomeStale` red; the result notice sent before the answered one -> `TestOutcomeApplies` (sequence) red; the `row.State` repeat guard removed -> `TestOutcomeNotOurs` red.
- AC 4: `Outcome` writing from the outcome without `StartExecution` -> `PersonaAnswers:TestWebFirstWins` red (the row is not `done`).
- AC 5: the new `CommandsIn` line removed -> `CommandsRouting:TestProposePersonaOwnSessionOnly` red.
- AC 6: the setting arm mapped to `MESSAGENOTAPPROVER` -> `AnswersInProduction` setting row red.
- AC 7: the drop of unused values removed -> `PersonaApi:TestPutDropsUnusedValues` red; the 1,000 bound changed to 1,001 -> `TestPutBoundsUsedValues` red.
- AC 8: one preset description word changed in `persona-card-view.ts` -> `ux-strings.test.mjs` red.
- AC 9: `WritePersona` call removed from the approved path -> PA1 red.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Shared surfaces:**
- `SettingsOps.Propose`'s answer (`not_built` becomes `proposed`): `Test.Core.SettingsPersona`, `Test.Tools.Persona` (double, unchanged).
- `ToolCallCard`'s keys: `Test.Core.WebChatOut`, `Test.Core.ToolCallNotices`.
- `approvalTitle` and the card view: `rail-view.test.mjs`, `approval-view.test.mjs`, `approval-sources.test.mjs`, `phone-request-sources.test.mjs`, e2e `persona-card.spec.ts` (PC5/PC8/PC16 seed setting rows; their rail title becomes the setting title) and `rail/rail.spec.ts`.
- The UX inventory (`ux-strings.test.mjs`).
- `CommandsIn`'s refusals (`Test.Core.CommandsRouting`).
- The 403 mapping (`Test.Core.AnswersInProduction`, `web/e2e/answers/answers.spec.ts`).
- `PUT /v1/persona` (`Test.Web.PersonaApi`, `web/e2e/api/persona.spec.ts`).
- The `lane-b` `Core` area's class list and duration: one LiveCase class, which adds to CI's `image` group.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
