---
title: 'Story 40.5: A `setting` approval in the bridge, and OcuTalon''s proposal tool'
type: 'feature'
created: '2026-11-05'
status: 'done'
baseline_revision: '1f1b53757543aa468c67d9096213dadd2572ec1c'
baseline_commit: '1f1b53757543aa468c67d9096213dadd2572ec1c'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      Web/Api.cls AnswerResponse picks the not-approver 403 text by `kind = "fix"`, so a not-allowed answer to a setting request gets the tool-call wording.
    evidence: |-
      Web/Api.cls:580 `$Select(kind = "fix": MESSAGENOTAPPROVER, 1: MESSAGENOTAPPROVERTOOL)`. Nothing raises a setting request until Story 40.6, and the intent forbids any Web/Api.cls edit in 40.5.
    location: >-
      src/ocutalon/cls/OcuTalon/Web/Api.cls:580
    severity: low
---

<intent-contract>

## Intent

**Problem:** The bridge refuses a `setting` approval request today: `Approval.Validate` sends every kind other than `tool_call` through the fix rules (`FixKind`, `FixParameters` and `FixTargets` are required). The Chat agent also has no tool for suggesting a persona. So OcuTalon cannot offer a change of voice as a request the person answers.

**Approach:**
- Bridge side: give `Approval.Validate` its own `setting` rules, make `Reconcile` redeliver a lost `setting` outcome the way it does a fix's, and fix the comments that say "fix only". The hold already sends `ApprovalOutcome` for every kind except an approved `tool_call`.
- OcuTalon side: add the `propose_persona` toolset to Chat. In a user's untainted turn it submits `ProposePersona` through `CommandCall`. On the online demo it answers `not_available`.
- Chat's instructions gain the UX's proposal paragraph, the security overview gains one generated row, and the tests that pin Chat's tool list are updated.

## Boundaries & Constraints

**Always:**
- The bridge stays host-free (AD-2, AD-31): no `OcuTalon.<non-Bridge>` reference on a code line in `src/bridge/`. `ResultTarget` is only an item-name string.
- A `setting` row goes through the same `Raise`, hold, `Answer`, expiry, first-answer-wins and audit path as every other request (AD-11). On approve, reject or expire it gets an `ApprovalOutcome` to `ResultTarget`, with no `tool` request to `Decide` (no replay and no model).
- The tool submits only through `OcuTalon.Tools.CommandCall.Run`, so it gets origin `tool`, `SessionRef` set to the context's `OwnerRef`, and key `<ItemId>:<position>`. Its declarations are class parameters of the provider: safe, not read-only, trusted output, and step label "Suggesting a persona".
- Chat's new paragraph is EXPERIENCE.md line 1045 ("Chat, proposals (Story 40.5)"), verbatim. It is appended after the persona paragraph with one blank line between them, and every existing `XData INSTRUCTIONS` line stays byte-identical.
- ObjectScript source stays ASCII (Rule 14).

**Never:**
- Raising a `setting` request from product code, any handling of `ApprovalOutcome` in `SettingsOps`, notices, the approval card, or `Web/Api.cls`. These are Story 40.6's, as are DW-570, DW-571, DW-669 and DW-709.
- Edits to any of these files: `Agent/Triage.cls`, `Core/CommandsIn.cls`, `Core/SettingsOps.cls`, `Msg/Enum.cls`, `Bridge/Msg/Enum.cls`, `Tools/Names.cls` (`PROPOSEPERSONA` already exists), `Bridge/Policy/Gate.cls`, `Checks/ReplyGuard.cls`, and anything under `web/`.
- A new user-facing sentence. The tool's `not_available` answer reuses the owner's own message.
- Adding `propose_persona` to `RELEASE1`, which the spine keeps it out of.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raise a setting | kind `setting`; `OwnerRef` is a session Ref S; `DryRun` `{"key":"person.S.persona","ownerRef":S,"old":"Professional (default)","new":"Pirate"}`; `ResultTarget` `SettingsOps`; no Fix, Tool, ToolSource, Runner or IncidentRef field | OK. Row is `pending`, `RequiredRole` = Decide's `ApprovalRole` setting, `ExpiresAt` = +24 h. A hold and a task exist, and `approval.raised` fires once | No error expected |
| Setting refused | the setting rules are broken: `OwnerRef` `instance`/`eval`; `DryRun` not an object; one of the four keys missing; an extra key; `key` empty or not a string; `ownerRef` different from `OwnerRef`; `old`/`new` neither a string nor an object; `ResultTarget` empty; any of `FixKind`, `FixParameters`, `FixTargets`, `ToolName`, `ToolArguments`, `ToolSource`, `Runner`, `IncidentRef` set | Error status naming the field. No row, hold or event | refusal |
| Approved | the owner's session answers approve | One `ApprovalOutcome` {ApprovalRef, IncidentRef "", Outcome `approved`} goes to `SettingsOps`, in the hold's session. The hold sends no `OcuTalon.Bridge.Msg.Request`. The Approval audit entry's `target` is the `DryRun` key | No error expected |
| Rejected / expired | answer reject; or the row aged past `ExpiresAt` and the timer fired | One `ApprovalOutcome` `rejected` / `expired` to `SettingsOps`, and no Request | No error expected |
| Lost delivery | an approved/rejected/expired `setting` row with a `ResultTarget`, no live hold and no `ApprovalOutcome` sent; also a row older than `DELIVERYDAYS` | `Reconcile` starts a delivery hold and the outcome reaches `SettingsOps` once; the old row gets none | combined status names the Ref |
| Owner only | setting row owned by S; another session T exists | `Ownership.Approvals(S)` lists it and `Approvals(T)` does not. `AnswersIn` from T answers `not_found` and the row stays `pending`. S's answer is accepted | refusal for T |
| Propose, user turn | context provenance `user`, untainted, owner S, ItemId I; `propose_persona` `{"preset":"pirate"}`; `CommandsDouble` behind `CommandsIn` | One `ProposePersona`: origin `tool`, SessionRef S, key `I:1`, Preset `pirate`. Answer `{"ok":true,"outcome":"proposed","message":<owner's>,"ref":<owner's Ref>}` | No error expected |
| Owner refuses | the double refuses `ProposePersona` with message M | `{"ok":false,"outcome":"refused","message":M}`, with no ref | No error expected |
| No session | no bridge context, or owner `instance` | `{"ok":false,"message":CommandCall.NOSESSION}`; nothing submitted | No error expected |
| Online demo | `onlineDemo` 1, user turn of S | `{"ok":false,"outcome":"not_available","message":CommandsIn.MESSAGENOTALLOWED}`; the double records nothing; `CommandCount` unchanged | No error expected |
| Untrusted / tainted | provenance `untrusted` (also `""`, `User`), or a user turn with `Tainted` 1 | gate denies with `Gate.UNTRUSTED`; the method does not run; no command | denial |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- `Validate` L191-234 (`If kind = "tool_call"` L205, `Else` fix rules L212-222, then IncidentRef/TraceRef L223, owned fields L227, role L230); `IsRef` L243; `Facts` L469-481 (`target` L475); `HoldResponse` L660-704 (the only kind branch is L692, and the outcome is sent at L693-703 for any other kind already); `ReconcileDeliveries` L817-840 (SQL L819 names `fix` only; the DELIVERYDAYS/`OutcomeSent` guard L830 is `= "fix"`). Comments that say "fix only": class header L4-30 (L20, L27-29), `Raise` doc L79-86, `Hold` doc L575-587, `HoldResponse` doc L639-659, `Reconcile` doc L769-778.
- `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls` L1-6 -- class comment only ("an approval of a fix ...").
- `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalOutcome.cls` L1-3 -- comment only ("approved (a fix only)", "IncidentManager for a fix"). Its fields are pinned by `Test/Bridge/Contracts.cls:221-228`; they do not change.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- property comments only: `DryRun` ("keys of DRYRUNKEYS"), `FixKind`/`FixParameters`/`FixTargets` ("empty for a tool_call request"), `ToolSource`/`Runner` ("empty for a fix request"). Storage is unchanged.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls:21` -- READ ONLY: `APPROVALKIND` already holds `setting` (40.2).
- `src/ocutalon/cls/OcuTalon/Tools/Reminders.cls`, `ReminderTools.cls` -- the sibling pair to follow: a toolset `XData Definition` naming provider methods; provider `Extends OcuTalon.Tools.Result`; `STEPLABEL<NAME>`/`CLASSIFICATION<NAME>`/`READONLY<NAME>`/`TRUSTEDOUTPUT<NAME>` (L13-53); return only through `..Return(...)`; helpers `[ Private ]` with output arguments.
- `src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls` -- `Session(.context)` (NOSESSION precheck), `Run(command, .result)`, `Answer(result)` = {ok, message, ref?}. `WatchAnswers.cls:149-153` adds `outcome` to `Answer`.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls:135` -- `OnlineDemo()`. A tool may call it. `Test/Bridge/CodeRules.cls` `GOVERNANCE` L106 forbids `SettingsOps` and `Data.Setting` on tool code lines.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- READ ONLY: `TOOLVERBS` L34 has `ProposePersona`; route L181; `MESSAGENOTALLOWED` L46.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- READ ONLY: `Propose` L238-246 answers `not_built` for valid values (until 40.6) and `not_available` with `CommandsIn.MESSAGENOTALLOWED`. On an `ApprovalOutcome` today, `Carry` answers `unknown_command` (harmless: the hold sends it with no response).
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- class comment L1-6 lists the tools; `TOOLSETS` L17; `XData INSTRUCTIONS` ends with the persona paragraph (L68).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `APPROVALVISIBLE` L63, `Approvals` L303, `Approval` L792. `Core/AnswersIn.cls` rule 3 (header L7-9). READ ONLY.
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- READ ONLY: `ToolRows` finds every agent's toolsets, so no generator change.
- `docs/security-overview.md` L5-25 -- the generated tools table. The new row goes between `list_reminders` (L16) and `read_event_log` (L17). Epic 39's hunk is at L155.
- Tests:
  - `Test/Bridge/Approval.cls` -- throwaway only. Helpers: `Refusals()` L1981-2014, `TestRaiseFix` L243, `TestAnswerApprovesAFix` L845, `TestAnswerRejects` L870, `TestTimerExpires` L1013 (`Age` L2276 + `Install.Step.Reconcile.Run()`), `TestReconcileDeliversWhatLostHoldsOwed` L1884, `RaiseHeld(kind, target)` L2726, `FixtureRow(state, expiresIn, kind)` L2745, `WaitOutcomes` L2821, `AssertOneOutcome` L2838 (hard-codes `IncidentManager` at L2845), `HoldMessages(mark, ref)`, `Answerer()` L2715.
  - `Test/Bridge/ApprovalRows.cls:12` -- `NewRow(kind)` builds fix fields for every kind except `tool_call`.
  - Pattern for `AnswersIn`: `Test/Core/AnswersInProduction.cls`.
  - `Test/Tools/Reminders.cls` -- `Prepare` L974, `Begin` L999, `Turn` L1021, `AssertSteps` L1054, `AssertCall` L1060, `Calls` L1122. Pins: `TestDeclarations` L171 (TOOLSETS literal), `TestSetRelative` L275 (offered tool names). `Test/Tools/CommandsDouble.cls` answers by verb (header L5-27); any other verb gets `not_handled`.
  - `Test/Bridge/Gate.cls` -- `TRUSTEDTOOLS` L117 (checked by `TestFlagsAreListed` L1350); `AssertSafeReadOnlyOnly` runs list L2013-2022 (`RunDenied` L2462), used by L1278 and L1288.
  - `Test/Bridge/CodeRules.cls` -- `TOOLVERBS` L109 (comment L107-108): `TestNoToolReachesAGovernanceCommand` L707 goes red on a tool naming `ProposePersona` until it is listed. `TestToolsHaveStepLabels` L632.
  - `Test/Agent/PersonaBlock.cls` -- `XData UX` L37; `TestParagraphs` L209 asserts that Chat's persona paragraph is the block's last text. That assertion changes.
  - `Test/Agent/Instructions.cls` -- `TestToolsets` L200: TOOLSETS literal L203, expected names L233, per-tool arguments L234-240.
  - `Test/Agent/Runners.cls` -- `REMINDERTOOLS` L73; `TestToolInventory` provider map L312-330 (class comment L26, L43-50).
  - `Test/Watch/Tools.cls:62` (TOOLSETS literal); `Test/Watch/Turns.cls:63` (offered tool names).
  - `Test/Install/SecurityOverview.cls` -- `TestToolRows` L34-56 expects exactly `RELEASE1` (12), and so does its comment.
  - `Test/Agent/Constants.cls` -- READ ONLY: still passes, because `RELEASE1` is unchanged.
- `ci/mock/scenarios/A/reminder-set-relative.json` -- scenario shape (`match.marker`, `replies[].toolUse` / `text`).

## Tasks & Acceptance

**Execution:**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- Changes:
  - In `Validate`, split the `Else` into `ElseIf kind = "fix"` (unchanged rules) and a `setting` branch: `OwnerRef` must pass `IsRef`; `ToolSource`, `Runner`, `ToolName`, `ToolArguments`, `FixKind`, `FixParameters`, `FixTargets` and `IncidentRef` must be empty; `ResultTarget` must be non-empty; `DryRun` must be a JSON object with exactly the keys of a new `Parameter SETTINGKEYS = "key,ownerRef,old,new"`, where `key` is a non-empty string, `ownerRef` is a string equal to `OwnerRef`, and `old` and `new` are each a string or an object. Each refusal goes through `Refuse` and names the field (`DryRun` or the key).
  - In `Facts`, `target` is the `DryRun` key for a `setting` (read in a Try; "" when unreadable).
  - In `ReconcileDeliveries`, the SQL takes `Kind IN ('fix', 'setting')` and the guard at L830 becomes `'= "tool_call"`.
  - Update every comment listed in the Code Map so it states the `setting` contract (AD-11).
  -- AC 1, 2, 3.
- `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls`, `Bridge/Msg/ApprovalOutcome.cls`, `Bridge/Data/ApprovalRequest.cls` -- comments only (a fix or a setting; for a setting the receiver is the value's owner, named as an item). No code or storage change -- AC 2.
- `src/ocutalon/cls/OcuTalon/Tools/PersonaTools.cls` -- new. `Extends OcuTalon.Tools.Result`, with `STEPLABELPROPOSEPERSONA = "Suggesting a persona"`, `CLASSIFICATIONPROPOSEPERSONA = "safe"`, `READONLYPROPOSEPERSONA = 0` and `TRUSTEDOUTPUTPROPOSEPERSONA = 1`. `ClassMethod ProposePersona(preset, language = "", custom = "") As %DynamicObject` runs in this order:
  1. `CommandCall.Session(.context)`. A refusal is returned as it is.
  2. When `Watch.Reader.OnlineDemo()`, it returns `{"ok": false, "outcome": "not_available", "message": CommandsIn.#MESSAGENOTALLOWED}`.
  3. It builds `Msg.Command.ProposePersona` (Preset, Language, Custom as given) and calls `CommandCall.Run`. A refusal is returned as it is.
  4. Otherwise it returns `CommandCall.Answer(result)` with `outcome` = `proposed` when `result.Ok`, else `result.Outcome`.

  The class comment and the method doc comment are model-facing ASCII. They name the six preset ids, say that `language` is used only for `language` and `custom` only for `custom`, and say that the answer `proposed` means a request now waits for the person and nothing has changed. The arguments carry DESCRIPTIONs, and none names a session, owner or origin -- AC 4, 5, 6.
- `src/ocutalon/cls/OcuTalon/Tools/Persona.cls` -- new `%AI.ToolSet`, `DependsOn = OcuTalon.Tools.PersonaTools`, `<ToolSet Name="OcuTalonPersona">` with a description and one `<Tool Name="propose_persona" Class="OcuTalon.Tools.PersonaTools" Method="ProposePersona"/>`, and no `Requirement` -- AC 4.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- `TOOLSETS` gains `,OcuTalon.Tools.Persona`; the class comment and the `TOOLSETS` comment name the persona tool; the EXPERIENCE.md line 1045 text is appended as the last paragraph of `XData INSTRUCTIONS`, after one blank line -- AC 4, 7.
- `docs/security-overview.md` -- insert the row ``| `propose_persona` | `OcuTalon.Tools.PersonaTools` | `OcuTalon.Tools.Persona` | `OcuTalon.Agent.Chat` | Suggesting a persona | safe | no | yes | none |`` after `list_reminders`. `live security-overview` proves it byte for byte; if it reports DRIFT, take the generated row -- AC 8.
- `ci/mock/scenarios/A/persona-propose.json` -- new: `toolUse` `propose_persona` `{"preset":"pirate"}`, then text "The CI mock suggested the persona." -- AC 4.
- `src/ocutalon/cls/OcuTalon/Test/Tools/CommandsDouble.cls` -- answer `ProposePersona` with Ok 1, Outcome `proposed`, the message "The CI double raised the request.", and Ref `Parameter PROPOSEREF = "zzProposalDouble000001"`. Header updated -- AC 4.
- `src/ocutalon/cls/OcuTalon/Test/Tools/Persona.cls` -- new test case:
  - `TestDeclarations` needs no production: the toolset offers exactly `Names.PROPOSEPERSONA` once from `PersonaTools`; the label and the flags are as above; the inputs are `preset`, `language` and `custom`; there is no `Requirement`; Chat's `TOOLSETS` names the toolset.
  - The rest run throwaway only, with the double through `RunnerFixture.UseItemClass` (`Test.Tools.Reminders`' `Prepare`/`Begin` pattern): the matrix rows "Propose, user turn", "Owner refuses", "No session" and "Online demo" (`onlineDemo` saved and put back), plus `TestProposeThroughATurn`, the Integration AC. In that test a `turn` through `RunnerFixture.Run` with `[[mock:persona-propose]]`: the double records one `ProposePersona` (origin `tool`, the owner, key `<ItemId>:1`, Preset `pirate`); the second logged request offers `propose_persona` and carries the tool result `{"ok":true,"outcome":"proposed",...,"ref":PROPOSEREF}`; the steps are model, tool ("Suggesting a persona") and model.
  -- AC 4, 6.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` and `Test/Bridge/ApprovalRows.cls` -- Changes:
  - `NewRow("setting")` gets its own branch: a session-Ref owner, the matrix `DryRun`, and `ResultTarget` `SettingsOps`.
  - `AssertOneOutcome` gets a `target` argument (default `IncidentManager`), so it is extended rather than copied.
  - `Refusals()` gains the "Setting refused" rows.
  - New tests: `TestRaiseSetting`, `TestSettingOutcomes` (approve, reject and expiry, each with one outcome to `SettingsOps`, `HoldMessages` holding no `OcuTalon.Bridge.Msg.Request`, and the audit `target`), `TestReconcileDeliversASettingOutcome` (a lost row, and an old one), and `TestSettingOwnerOnly` (the matrix row "Owner only", with fixture sessions through `Test.Data.Fixture.Session` and `AnswersIn` as `Test.Core.AnswersInProduction` drives it).
  - The tests assert the outcome message and the hold's sends, never the row's later state, because SettingsOps acts on the outcome from 40.6.
  -- AC 1, 2.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` -- `TRUSTEDTOOLS` gains `OcuTalon.Tools.PersonaTools:propose_persona`; `AssertSafeReadOnlyOnly` runs gain `$ListBuild("OcuTalon.Tools.Persona","propose_persona","{""preset"":""pirate""}")` with the candidate session as owner (so a method that ran would submit), and its doc comment names it -- AC 5.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `TOOLVERBS` gains `ProposePersona` and its comment -- AC 4.
- `src/ocutalon/cls/OcuTalon/Test/Agent/PersonaBlock.cls` -- `XData UX` gains `chatProposals` (the line 1045 text). `TestParagraphs` now asserts that the persona paragraph is followed by one blank line and the proposals paragraph, that each occurs once, that the proposals paragraph is the block's last text, and that it holds no `{{`. Header updated -- AC 7.
- Shared-surface pins: `Test/Agent/Instructions.cls`, `Test/Tools/Reminders.cls`, `Test/Watch/Tools.cls`, `Test/Watch/Turns.cls`, `Test/Agent/Runners.cls`, `Test/Install/SecurityOverview.cls`. Changes:
  - Chat's TOOLSETS literal becomes `OcuTalon.Tools.Reminders,OcuTalon.Tools.Watching,OcuTalon.Tools.Persona`.
  - The offered names gain `propose_persona` in sorted place.
  - `Instructions.TestToolsets` expects 9 Chat names, with arguments `{"preset":"pirate"}` (NOSESSION).
  - `Runners.TestToolInventory` maps `propose_persona` to `PersonaTools`.
  - `SecurityOverview.TestToolRows` expects `RELEASE1` plus `PROPOSEPERSONA`, 13 rows.
  - The comments' counts are updated.
  -- AC 4, 8.

**Acceptance Criteria:**
1. Given kind `setting`, a `DryRun` of `{key, ownerRef, old, new}` and a `ResultTarget`, when `Approval.Raise` is called, then the row is `pending` with `RequiredRole` = the bridge's `ApprovalRole` setting, every "Setting refused" row is refused with no row, hold or event, and only the owning session sees it in `Ownership.Approvals` or can answer it through `AnswersIn`.
2. Given a raised `setting` request, when it is approved, rejected or expires (or its delivery was lost and `Reconcile` runs), then `ApprovalHold` sends exactly one `ApprovalOutcome` with that outcome to the `ResultTarget` and no replay `Request`, so no model runs.
3. Given the changed bridge, when `docker/tests/test-class-rules.sh` runs, then its `bridge-refs` check finds no OcuTalon reference in the bridge (AD-2).
4. Given a user turn with no taint, when Chat calls `propose_persona`, then `ProposePersona` reaches `CommandsIn` with origin `tool`, the turn's owner and `<ItemId>:1`, and the model reads `proposed` with the owner's `Ref`; an owner's refusal reaches it unchanged with its outcome; and with no session's turn the answer is NOSESSION with nothing submitted.
5. Given an untrusted turn or a tainted user turn, when `propose_persona` is called through AI Hub, then the gate denies it with `UNTRUSTED`, its method does not run, and nothing is submitted.
6. Given the online-demo flag, when `propose_persona` is called in a user turn, then it returns `not_available` with the owner's `MESSAGENOTALLOWED` text and submits nothing.
7. Given the compiled Chat class, when its `XData INSTRUCTIONS` is read, then the EXPERIENCE.md "Chat, proposals" text is its last paragraph, once, after the persona paragraph, and every earlier line is unchanged.
8. Given the package built in a throwaway, when the security overview is generated, then its tool table names `propose_persona` with source, toolset, agent, label, `safe`, read-only `no`, trusted output `yes`, and `live security-overview` passes with no DRIFT.

## Spec Change Log

## Review Triage Log

### 2026-11-05 — Review pass
- verdicts: 28 findings reported (blind 11, edge-case 10, verification-gap 6, intent-alignment 1), in 21 rows (a finding that several layers or one layer repeated shares a row) — high 0, medium 3 rows, low 18 rows, false 0, maybe-false 0
- findings:
  - `[low]` `patch` Raise doc comment splices the setting clause into the fix clause (blind) — rewritten with `;` separators in Approval.cls.
  - `[low]` `defer` Web/Api.cls 403 wording for a setting request (blind, verification-gap) — intent forbids Web/Api.cls in 40.5; deferred to 40.6's area.
  - `[low]` `reject` ValidateSetting bounds nothing on key/old/new (blind) — the owner validates values (spec Decided in-stage); a bridge cap adds a rule the spec does not name.
  - `[low]` `reject` cancel, re-arm and SettingKey-catch paths untested (blind) — kind-agnostic paths already pinned for the other kinds; fix is more than a direct correction.
  - `[medium]` `patch` TestReconcileDeliversASettingOutcome second Reconcile cannot observe a duplicate; `again` unused (blind, verification-gap) — now waits for the delivery holds to end and asserts `StartsOf(again, ref) = 0`.
  - `[medium]` `patch` TestSettingOwnerOnly acts before the hold is ready, no empty-role guard, no wait for the outcome (blind, edge-case, verification-gap) — now waits for the task, guards an empty role, waits for the hold end and one outcome; owner-clause mutation recorded.
  - `[low]` `reject` preset list hard-coded in PersonaTools, not pinned to Msg.Enum PERSONAPRESET (blind) — the spec fixes the six ids in the doc comment; a pin is added surface.
  - `[low]` `patch` garbled counts in the Instructions test comment (persona toolset named twice) (blind, edge-case) — rewritten; the Runners.cls comment chain is left (Epic 17 changed that comment).
  - `[low]` `reject` Chat instruction does not mention language/custom arguments; no refusal scenario (blind) — the paragraph is verbatim UX text (spec-bound); the tool description carries the arguments.
  - `[low]` `reject` mock scenario text coupled to the turn test (blind) — same pattern as the reminder scenarios.
  - `[low]` `reject` TestToolRows count hard-coded as RELEASE1 plus PROPOSEPERSONA (blind) — decided in-stage; the spine keeps the name out of RELEASE1.
  - `[low]` `reject` bare Else in Validate and ReconcileDeliveries would take a future kind as a setting (edge-case) — APPROVALKIND holds exactly the three kinds today; a new kind needs its own rules in its story.
  - `[low]` `reject` ResultTarget only checked non-empty (edge-case) — as for a fix; the spec says a name string only.
  - `[low]` `reject` repeated delivery holds for 7 days when the target cannot take the outcome (edge-case) — the existing fix behavior (DELIVERYDAYS), not caused by this story.
  - `[low]` `reject` outcome `proposed` when Ok even if the owner's outcome differs; empty outcome when not Ok (edge-case x2) — spec: `outcome` is `proposed` on Ok, else the owner's Outcome.
  - `[low]` `reject` stray language/custom reach the owner (edge-case) — the tool validates nothing; the owner does (spec).
  - `[low]` `reject` AnswerAs, roles-empty and RaiseHeld key fragility (edge-case x3) — test helpers fail loudly; the roles guard was patched with TestSettingOwnerOnly.
  - `[low]` `reject` spec says 9 Chat names, test expects 10 (edge-case) — 9 was the count before this tool; recorded in Design Notes.
  - `[medium]` `patch` ValidateSetting's IncidentRef entry masked by the generic IncidentRef check (verification-gap) — new `Refusals()` row with a valid Ref; mutation recorded.
  - `[low]` `reject` extra mutation lines for the DryRun rules, Facts target and AssertRefused field-only check (verification-gap x2) — one demonstrated mutation per AC is the bar; AC 1 has four.
  - `[low]` `reject` intent-alignment: readings A to D enumerated; the diff implements A and C with the owner behind CommandsIn doubled (descriptive, 4 rows) — no divergence from the intent; the real producer and consumer are 40.6's.

## Design Notes

**Governing decisions:**
- AD-1: a safe tool submits a command through `CommandsIn` with key `<ItemId>:<position>`. `ProposePersona` is a tool verb.
- AD-2: the bridge stays separable.
- AD-6: no `%AI` calls in the tool.
- AD-7: Chat's static instructions and `TOOLSETS`.
- AD-9: the step label.
- AD-10: the gate's provenance and taint rule; the classification comes from class parameters.
- AD-11: the `setting` bullet.
- AD-17: the Approval audit entry.
- AD-29: Lane A files and Epic 40's names.
- AD-31: the host is reached only by item name.
- AD-32: the tool returns an outcome and the owner's message.
- No AD's Rule is contradicted.

**U-268.** This story relies on AD-1 only for `ProposePersona` being in `CommandsIn.TOOLVERBS`. It is already there, beside 33.2's `SendDigest`, and this story does not change it. The story does not rely on the closed tool-origin list as a whole, or on digest routing. `CommandCall.Run` sets `SessionRef` to the context's `OwnerRef`, so the tool can't name another session. `CommandsIn`'s own binding check (DW-570) stays 40.6's. No clarification is needed.

**Decided in-stage:**
- *Setting `DryRun` contract.* Exactly the four AD-11 keys. `ownerRef` must equal the row's `OwnerRef`, which must be a session Ref, so a `setting` row can never be an `instance` row that every watcher sees. `old` and `new` may each be a string or an object, which leaves 40.6 room for display text plus values. The bridge does not compare `old` with `new`: that is the owner's rule.
- *Audit `target`.* For a `setting` it is the `DryRun` key. The shape is unchanged, and the value would otherwise be an empty `IncidentRef`.
- *Reconcile.* A lost `setting` outcome is redelivered on the fix rule (`DELIVERYDAYS`, `OutcomeSent`). AD-11 says "expiry ... as for every request", and a lost outcome would otherwise leave a person's approved change unapplied after a restart.
- *Tool order.* NOSESSION first, because `Test.Agent.Instructions` runs every Chat tool with no context. Then `not_available`, then submit. The `not_available` answer is exactly the owner's answer for that case (`SettingsOps.Propose`), so no new sentence is shipped. `outcome` is `proposed` on `Ok`, so 40.6's own outcome word does not matter to the tool. The owner does all value validation, as for the reminder tools.
- *Trusted output 1.* The answer is built in code from the owner's `CommandResult`, as for `set_reminder`.
- *Two sentences.* The AC says "one sentence", but EXPERIENCE.md line 1045 (the UX item the AC cites) is two sentences. It ships verbatim as one paragraph, as 40.3 shipped the UX persona text.
- *Security overview count.* `TestToolRows` compares against `RELEASE1` plus `PROPOSEPERSONA`, because the spine keeps the name out of `RELEASE1`.
- *Test target.* The bridge tests use the real `SettingsOps` as `ResultTarget`, which AD-11 names, and assert only the outcome message, because 40.6 will act on it. The real-`SettingsOps` turn (today `not_built`) is not pinned, so 40.6 changes no 40.5 assertion except the double's.
- *Tool tests use the double.* Its `ProposePersona` answer is 40.6's contract (Ok, Ref = the request's `ApprovalRef`).
- *Implement-stage decisions.* `ValidateSetting` and `SettingKey` are private helpers of `Approval`, and `ApprovalRows.SettingDryRun(owner)` builds the matrix `DryRun` once for `NewRow` and the owner-only test. The "Setting refused" rows write the row's own OwnerRef as the token `{OWNER}` in a `DryRun` value, which `TestRefused` replaces. `Test.Bridge.Approval.AnswerAs` is a short private copy of `Test.Core.AnswersInProduction.FromPageAs` (that one is private and the class needs a production base). `Instructions.TestToolsets` expects 10 Chat names (the spec's "9" was the count before this tool). In `Test.Agent.Runners` the offered-name literal `REMINDERTOOLS`, the inventory's expected list and one provider-map line changed; the class comment line that lists the tools (Epic 17 changed it) was left as it was. `SecurityOverview.TestProposePersonaRow` is new (see the AC 8 mutation).

**Integration ACs (Rule 1/2).** `TestProposeThroughATurn` (AC 4) runs a real `ChatAgent` turn against the mock: the consumer, Chat, offers the toolset and its call reaches `CommandsIn`. The `setting` kind has no product consumer in this story; the first is Story 40.6 (`SettingsOps` raises and handles the outcome).
- Consumes:
  - 40.1: `Names.PROPOSEPERSONA`.
  - 40.2: `ProposePersona`, its route, `SettingsOps.Propose`, `APPROVALKIND` `setting`.
  - 40.3: Chat's persona paragraph and `TestParagraphs`.
  - Epic 3/6: `CommandCall`, the gate, the Approval API.
- Consumed-by:
  - Story 40.6:
    - It raises with this `DryRun` and `ResultTarget` `SettingsOps`, and handles `ApprovalOutcome` (StartExecution, FinishExecution).
    - It answers `ProposePersona` Ok with `Ref` = the `ApprovalRef`.
    - It renders a setting row: `Live/Payload/Part/DryRun` and `ApprovalRequest.DRYRUNKEYS` are fix-shaped, and `BridgeSink` sends no notice for a setting row.
  - Story 40.7: the injection case, where an email yields no proposal through the AC 5 gate denial and the new paragraph.

**Extend, don't copy (Rule 2).**
- `PersonaTools`/`Persona` follow `ReminderTools`/`Reminders`, and the answer is `CommandCall.Answer` plus `outcome` (as `WatchAnswers.Submitted` does).
- `AssertOneOutcome`, `NewRow`, `Refusals` and `AssertSafeReadOnlyOnly` are extended, not copied.
- `Test.Tools.Persona` needs `Test.Tools.Reminders`' private `Prepare`, `Begin` and `Turn`. It carries short copies, because subclassing would re-run Reminders' 30 tests. That is the reason for the copy.

**Footprint (Rule 11), re-checked at plan (HEAD 7df5171c).**
- Existing bridge files changed: `Bridge/Approval.cls` (code and comments) and `Bridge/Process/ApprovalHold.cls` (comment), both in Epic 40's footprint; `Bridge/Msg/ApprovalOutcome.cls` and `Bridge/Data/ApprovalRequest.cls` (comments only), which are footprint extensions. Epic 17 has changed none of them, and `Bridge/Msg/Enum.cls` is not touched.
- `docs/security-overview.md`: Epic 39 changed L155. This story adds one row at L17, a one-entry list addition; report it.
- `Test/Watch/{Tools,Turns}.cls` and `Test/Install/SecurityOverview.cls` sit in Epic 17's footprint (unchanged by it) and outside Epic 40's: one-literal edits, reported as footprint extensions.
- No edit to `Triage.cls`, `Msg/Enum.cls`, `CommandsIn.cls` or `Tools/Names.cls`.
- The implement stage re-checks `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` (17, 34, 11, 39) before the first edit.

**Ledger inbox (Rule 17):** none. DW-570, DW-571, DW-669 and DW-709 are 40.6's.

## Verification

All calls run from the worktree root with `timeout: 600000`, one per call. `<D>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=40 stage=implement'`; fresh tag `e40s5i`, warm tag `e40s5iw`. IRIS MCP: `server` `ocutalon-slot-d`, `namespace` `OCUTALON`, and one `iris_execute_tests` per message. `<BASE>` = `7df5171c651bdecafe6b2c923508e8d4d74a66aa`. Fresh runs are needed wherever production jobs execute changed code (the hold, ChatAgent's toolset), because a warm stack's jobs keep old code. Write `persona-propose.json` before `ci/warm.sh up`: a mock change refuses warm runs.

**Commands:**
- (loop) `iris_doc_load` the changed classes into slot D (absolute `baseDir` `.../src/bridge/cls` and `.../src/ocutalon/cls`) and compile -- expected: they compile.
- (loop) `python3 -c "import re,subprocess as s;p='src/ocutalon/cls/OcuTalon/Agent/Chat.cls';x=lambda t:re.search(r'XData INSTRUCTIONS[^{]*\{\n(.*?)\n\}',t,re.S).group(1);o=x(s.run(['git','show','<BASE>:'+p],capture_output=True,text=True).stdout);n=x(open(p).read());u=re.search(r'\*\*Chat, proposals \(Story 40\.5\):\*\* \"(.*)\"\n',open('_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md').read()).group(1);print(n==o+'\n\n'+u)"` -- expected: `True`.
- (loop) `git diff --stat <BASE> -- src/ocutalon/cls/OcuTalon/Agent/Triage.cls src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls src/ocutalon/cls/OcuTalon/Msg/Enum.cls src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls src/ocutalon/cls/OcuTalon/Tools/Names.cls src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls web` -- expected: empty.
- (loop) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-mock.sh`, `bash docker/tests/test-ci-config.sh`, one per call -- expected: pass (`bridge-refs` clean, ASCII, scenario valid).
- (loop) `<D> OCUTALON_RUN_TAG=e40s5iw ci/warm.sh up` once, then one per call `<D> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e40s5iw ci/iris.sh class <C>` for `OcuTalon.Test.Bridge.CodeRules`, `.Agent.PersonaBlock`, `.Agent.Instructions`, `.Agent.Constants`, `.Bridge.Contracts`, `.Msg.Contracts` -- expected: `CLASS ... passed` each. `<D> OCUTALON_RUN_TAG=e40s5iw ci/warm.sh down` at the stage's end, also after a failure.
- (loop) fresh, one per call: `<D> OCUTALON_RUN_TAG=e40s5i ci/iris.sh class <C>` for `OcuTalon.Test.Bridge.Approval`, `.Tools.Persona`, `.Bridge.Gate`, `.Tools.Reminders`, `.Agent.Runners`, `.Install.SecurityOverview`, `.Watch.Tools`, `.Watch.Turns` -- expected: passed each (each about 1 min start plus the class; `Bridge.Approval` about 130 s).
- (once) fresh, one per call, each with `<D> OCUTALON_RUN_TAG=e40s5i`: `ci/iris.sh shard lane-a@Tools`, then `--reverse`; `ci/iris.sh shard lane-a@Agent` (use `--part k/2` if it nears the cap); `ci/iris.sh live security-overview` (expected: PASS, no DRIFT); `OCUTALON_LIVE_DEADLINE=700 ci/iris.sh live demo-path` (run `ci/iris.sh build` first if `web/` changed since the bundle); then `ci/iris.sh teardown` -- expected: all pass.
- The rest of `lane-a`/`lane-b` and the other live units are left to CI.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):**
- AC 1: `setting` branch accepts `OwnerRef` `instance` -> `Test.Bridge.Approval:TestRefused` red; branch removed (setting falls to the fix rules) -> `TestRaiseSetting` red.
- AC 2: `HoldResponse` L692 replaying any approved non-fix kind -> `TestSettingOutcomes` red; `ReconcileDeliveries` SQL back to `fix` only -> `TestReconcileDeliversASettingOutcome` red.
- AC 3: a code line `Set x = ##class(OcuTalon.Core.SettingsOps).%ClassName()` in `Approval.cls` -> `test-class-rules.sh` `bridge-refs` FAIL.
- AC 4: `outcome` taken from `result.Outcome` on Ok, with the double answering `created` -> `Test.Tools.Persona` user-turn test red.
- AC 5: `READONLYPROPOSEPERSONA = 1` -> `Test.Bridge.Gate` untrusted/tainted tests red (the method runs and submits).
- AC 6: the `OnlineDemo()` check removed -> the online-demo test red (the double records a call).
- AC 7: one word of the proposals paragraph changed -> `PersonaBlock:TestParagraphs` red.
- AC 8: `Persona` removed from Chat's `TOOLSETS` -> `SecurityOverview:TestToolRows` red.

Recorded by the implement stage (each applied, observed red, reverted with the file byte-identical by md5):
- AC 1: mutation: ValidateSetting's OwnerRef check `If '..IsRef(...)` replaced by `If 0` (instance/eval pass it) -> `Test.Bridge.Approval:TestRefused` red (the OwnerRef `instance` and `eval` rows name DryRun, not OwnerRef).
- AC 1: mutation: the `setting` branch of `Validate` replaced by one fix rule (setting falls to the fix rules) -> `TestRefused`, `TestRaiseSetting`, `TestSettingOutcomes` and `TestSettingOwnerOnly` red (the setting row is refused for FixKind).
- AC 2: mutation: `HoldResponse` `(row.Kind = "tool_call")` -> `(row.Kind '= "fix")` (every approved non-fix kind replayed) -> `TestSettingOutcomes` (a) red (no outcome; a Request is sent) and `TestReconcileDeliversASettingOutcome` red; fresh run.
- AC 2: mutation: `ReconcileDeliveries` SQL `Kind IN ('fix', 'setting')` -> `Kind = 'fix'` -> `TestReconcileDeliversASettingOutcome` red (the approved, rejected and expired rows get no outcome).
- AC 3: mutation: code line `Set x = ##class(OcuTalon.Core.SettingsOps).%ClassName()` in `Approval.cls` -> `test-class-rules.sh` `bridge-refs` FAIL.
- AC 4: mutation: `PersonaTools` answer `outcome` = `result.Outcome` always, with the double answering `created` -> `Test.Tools.Persona` `TestProposeUserTurn`, `TestProposeFields`, `TestOnlineDemo` (control) and `TestProposeThroughATurn` red.
- AC 5: mutation: `READONLYPROPOSEPERSONA = 1` -> `Test.Bridge.Gate` `TestFlagsAreListed`, `TestUntrustedTurnRunsOnlySafeReadOnly` and `TestTaintedTurnRunsOnlySafeReadOnly` red.
- AC 6: mutation: the `OnlineDemo()` check replaced by `If 0` -> `Test.Tools.Persona:TestOnlineDemo` red.
- AC 7: mutation: "because" -> "when" in the proposals paragraph of Chat -> `PersonaBlock:TestParagraphs` red.
- AC 1: mutation: `"IncidentRef"` removed from `ValidateSetting`'s empty-field loop (the new `Refusals()` row gives a setting a valid 22-character IncidentRef) -> `Test.Bridge.Approval:TestRefused` red (the row is accepted and saved).
- AC 1: mutation: `Ownership.APPROVALVISIBLE` owner clause loosened to `(a.OwnerRef = ? OR a.OwnerRef <> 'instance')` -> `Test.Bridge.Approval:TestSettingOwnerOnly` red (T lists the row, and T's answer is not `not_found`); both files restored byte-identical (md5), run in one fresh stack.
- AC 8: mutation: `Persona` removed from Chat's `TOOLSETS` -> `SecurityOverview:TestToolRows` stayed green (the generator lists every toolset of the Tools package, held or not), so `TestProposePersonaRow` was added (the row's agent column and its table line) -> `TestProposePersonaRow` red.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Shared surfaces:**
- Chat's `TOOLSETS` and offered tool names: `Test.Agent.Instructions`, `Test.Tools.Reminders`, `Test.Watch.Tools`, `Test.Watch.Turns`, `Test.Agent.Runners`, `Test.Install.SecurityOverview`, `docs/security-overview.md`.
- Chat's `XData INSTRUCTIONS`: `Test.Agent.PersonaBlock`, `Test.Agent.Instructions`, `Test.Agent.Constants`, `ci/mock/test/constants.test.mjs`, and `Bridge.RequestSize`'s estimate (`Test.Agent.RequestSize` computes it and pins no length).
- The gate's `TRUSTEDTOOLS` list (`Test.Bridge.Gate`) and `CodeRules.TOOLVERBS`.
- The mock scenario folder, one more file (`test-mock.sh`, `server.test.mjs` health count).
- `Approval.Validate`'s refusals (`Test.Bridge.Approval.Refusals`) and `ReconcileDeliveries`' set.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The bridge validates a `setting` approval request (`ValidateSetting`, `SETTINGKEYS`), audits the DryRun key as `target`, and `Reconcile` redelivers a lost setting outcome; the hold needed no code change. Chat gains the `propose_persona` tool (`Tools.PersonaTools`, `Tools.Persona`), the UX proposals paragraph, one generated security-overview row and a mock scenario.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- setting rules, audit target, Reconcile set, comments.
- `src/bridge/cls/OcuTalon/Bridge/{Process/ApprovalHold,Msg/ApprovalOutcome,Data/ApprovalRequest}.cls` -- comments only.
- `src/ocutalon/cls/OcuTalon/Tools/{PersonaTools,Persona}.cls` -- new tool and toolset.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- TOOLSETS, comments, proposals paragraph.
- `docs/security-overview.md` -- one tool row. `ci/mock/scenarios/A/persona-propose.json` -- new scenario.
- Tests: new `Test/Tools/Persona.cls`; changed `Test/Bridge/{Approval,ApprovalRows,Gate,CodeRules}.cls`, `Test/Tools/{CommandsDouble,Reminders}.cls`, `Test/Agent/{Instructions,PersonaBlock,Runners}.cls`, `Test/Install/SecurityOverview.cls`, `Test/Watch/{Tools,Turns}.cls`.

**Review.** 28 findings in 21 rows: patches applied 5 (3 medium test gaps, 2 low comment fixes), deferred 1 (Web/Api.cls 403 wording, 40.6's area), rejected 15 with reasons in the triage log. Patched by hand (Rule 18): the Raise doc comment, the Instructions test comment, `TestReconcileDeliversASettingOutcome` (waits, `StartsOf`), `TestSettingOwnerOnly` (task wait, role guard, hold-end and outcome waits), and a valid-Ref IncidentRef refusal row.

**Follow-up review recommended: true.** Three medium test patches were made on a first pass (the second Reconcile pass and the owner-only waits in `Test.Bridge.Approval`); they are pinned by one green fresh run and one two-mutation run only.

**Verification.** `(loop)`: slot D load and compile OK; Chat byte-check True; protected-file diff empty; `test-class-rules`, `test-boundaries`, `test-mock`, `test-ci-config` pass; warm CodeRules, PersonaBlock, Instructions, Constants, Bridge.Contracts, Msg.Contracts pass; fresh Approval (126 s, re-run after the patches), Tools.Persona, Bridge.Gate, Tools.Reminders, Agent.Runners, Install.SecurityOverview, Watch.Tools, Watch.Turns pass. `(once)`: `shard lane-a@Tools` forward and `--reverse`, `shard lane-a@Agent`, `live security-overview` (no DRIFT) and `live demo-path` (8 of 8 steps) pass; they ran before the review patches, which changed comments and `Test.Bridge.Approval` only, and after them `Test.Bridge.Approval` (fresh) and `Test.Agent.Instructions` (fresh) were green. Mutations are recorded under `## Verification`. Footprint extensions reported: `Bridge/Msg/ApprovalOutcome.cls`, `Bridge/Data/ApprovalRequest.cls` (comments), `Test/Watch/{Tools,Turns}.cls`, `Test/Install/SecurityOverview.cls`, `Test/Agent/Runners.cls`, `Test/Bridge/CodeRules.cls` (one-name additions, none on a line Epic 17 changed), and one row in `docs/security-overview.md`.

**Residual risks.** The `Test/Agent/Runners.cls` class-comment line that lists Chat's tools (Epic 17 changed it) still omits `propose_persona`. The AC 8 mutation in the spec does not turn `TestToolRows` red (it lists every toolset of the package), so `TestProposePersonaRow` pins the agent column instead. The tool tests run against `CommandsDouble`; the real owner is Story 40.6's.
