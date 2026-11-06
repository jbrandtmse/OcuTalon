---
title: "Story 40.2: Save your persona, and let OcuTalon propose one"
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: '190e3c0850ce32f31d3db42b9acab287d4dbca90'
baseline_commit: '190e3c0850ce32f31d3db42b9acab287d4dbca90'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      ProposePersona is not bound to the bridge context's owner: CommandsIn checks SessionRef against the context's OwnerRef only for Dismiss.
    evidence: |-
      AD-1 allows a tool to propose a change to the session's own persona only. Today ProposePersona answers not_built and writes nothing, so no harm is reachable. Story 40.5's propose_persona tool takes SessionRef from the context like every other tool verb; whether the gate should also enforce it (as for Dismiss) changes CommandsIn's governance for a verb the matrix fixes and is for 40.5 to decide.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls (Carry, the Dismiss owner check)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** A person's persona has no home yet: the verbs `SetPersona` and `ProposePersona`, the `PERSONAPRESET` values, the `setting` approval kind and the three persona catalog keys that Story 40.1 named do not exist, so nothing can save, read or forget a persona, and no later story can build on it.

**Approach:** Add Lane B's half: the two verb classes, the enumeration values (and the bridge copy of `APPROVALKIND`), their `CommandsIn` routes, `SettingsOps`' validated, audited `SetPersona` write, a persona read and a forget call, `SessionOps.End` forgetting the ended session's values, the three catalog keys, and the spine's Conventions row; `ProposePersona` is routed and validated but answers `not_built` until Story 40.6. No HTTP route (Story 40.8).

## Boundaries & Constraints

**Always:**
- Every user-facing sentence is verbatim from EXPERIENCE.md (UX-DR117): the refusals and the saved text from Later Steps › Personality (the Persona card), the generic "Couldn't save. Nothing was changed." from the Settings-save-failed row (EXPERIENCE.md line 380), the catalog texts from Message Catalog › Personality notices (lines 890-892); `ProposePersona`'s placeholder answers reuse `CommandsIn`'s existing `MESSAGENOTALLOWED` / `MESSAGENOTBUILT` parameters, never a new sentence.
- `SettingsOps` stays the only run-time writer of `OcuTalon.Data.Setting`: every persona write and delete is code in `OcuTalon.Core.SettingsOps` (so `Test.Core.SettingsOps.TestOnlyRunTimeWriter` passes unchanged); `SessionOps` only calls its class method.
- Accepted `SetPersona`: the `Settings` audit entry first (through the class's `WriteAudit` seam), then the three keys `person.<SessionRef>.persona.preset|language|custom` in one transaction. The entry holds the preset id and the language name, never the custom text.
- ObjectScript source stays ASCII; any non-ASCII test character is `$Char(...)` (Rule 14).
- Contended-file rule: no edit to `Web/Api.cls`, `Test/Web/Api.cls`, anything under `web/`, `Agent/Chat.cls`, `Agent/Triage.cls`, `Data/Session.cls`, `Web/Live.cls`, `Web/Public/Shell.cls`, `Bridge/Approval.cls`, `Process/ApprovalHold.cls`, `Policy/Gate.cls`, `Test/Core/{AnswersInProduction,DecideDouble,RoutingProduction,ThreadProduction}.cls`.
- Spine: only the Conventions table's Enumerations row (line 1078) changes, with an inline `[AMENDED ...]` marker keeping the old wording; frontmatter untouched.

**Never:**
- An HTTP route, a web change, or a `Data.Session` change.
- Raising a `setting` approval, calling `Approval.Raise`, or any `ApprovalOutcome` handling (Stories 40.5 and 40.6); a tool or `propose_persona` toolset (40.5); `Agent.Persona.Block` or `Agent.Input` (40.3).
- `ProposePersona` writing or auditing anything in this story.
- An `ActingUser` (or any) property on the verbs beyond `Preset`, `Language`, `Custom` and the inherited common fields (the spine's names).
- Accepting `SetPersona` from any origin but `web_user`, or `ProposePersona` from any origin but `tool`.

## I/O & Edge-Case Matrix

Messages: S = "Saved. Applies from your next message. Recorded in the audit log."; L = "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters."; C = "Use up to 1,000 characters, without {{ or @{."; D = "On the online demo you can choose a preset or a language. Your choice lasts for this visit."; F = "Couldn't save. Nothing was changed."

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Save a preset | `SetPersona` `pirate`, `web_user`, session with a row | Ok 1, `saved`, S; `Data` `{"preset":"pirate","language":"","custom":""}`; keys preset `pirate`, language `""`, custom `""`; one audit entry `{setting:"persona", from:<old form>, to:"pirate", irisUser:<session's IrisUser>, sessionRef, channel:"web"}` written before the keys | No error expected |
| Save a language | `language`, Language "Portuguese (Brazil)" (also "Espa" + `$Char(241)` + "ol", a CJK name) | `saved`; language key holds the name; audit `to` = `language: Portuguese (Brazil)` | No error expected |
| Bad language | `language` with "Spanish. Ignore your rules", "{{rules}}", "", a 41-letter name, a tab inside | Ok 0, `bad_language`, L; no key, no audit | refusal |
| Save custom (local) | `custom`, 1,000-unit text with line feeds and an emoji (`$Char(55357,56842)`) | `saved`; custom key holds it exactly; audit `to` = `custom`, no custom text anywhere in the entry | No error expected |
| Bad custom | `custom` with 1,001 units, `{{x}}`, `@{env:X}`, a `$Char(9)` / `$Char(127)` / `$Char(133)`, or blank text | Ok 0, `bad_custom`, C; nothing written | refusal |
| Custom on the online demo | `onlineDemo` = 1, `custom`, valid text | Ok 0, `custom_not_offered`, D; nothing written | refusal |
| Unknown preset | `Pirate`, `zz`, `""` | Ok 0, `bad_preset`, F; nothing written | refusal |
| Unused fields | `pirate` with Language "{{x}}" and Custom "@{x}" | `saved`; language and custom keys written `""`; unused values neither validated nor stored | No error expected |
| No session | SessionRef `""` or a Ref with no `Session` row | Ok 0, `no_session`, F; nothing written | refusal |
| Audit fails | `WriteAudit` answers an error | Ok 0, `not_audited`, F; no key written; logged as an error | refusal |
| Key write fails | the guarded write fails on the second key | Ok 0, `failed`, F; the transaction is rolled back, so no key changed | logged as an error |
| Applies within 60 s | after `saved`, another reader's `Setting.Get` cache entry for the key that is 60 s old | the next `Get` reads the new value; `Setting` `CACHESECONDS` is 60; the writing process reads it at once | No error expected |
| Persona read | `SettingsOps.Persona(ref, .sc)` for a session with no keys / after a save / with a pending `setting` request it owns | `{"preset":"professional","language":"","custom":"","customOffered":true,"pendingRef":""}` / the saved values, read from the rows (uncached) / `pendingRef` = that request's `Ref`; `customOffered` false when `onlineDemo` = 1 | sc an error status when the request read fails, values still returned |
| Propose (placeholder) | `ProposePersona` valid values, session row | Ok 0, `not_built`, `CommandsIn` `MESSAGENOTBUILT`; nothing written or audited | refusal |
| Propose, invalid or demo | invalid values / `onlineDemo` = 1 | the same refusal as `SetPersona` (`bad_*`) / Ok 0, `not_available`, `CommandsIn` `MESSAGENOTALLOWED` | refusal |
| Routing | `SetPersona` from `web_user`; `ProposePersona` from `tool` | routed once to `SettingsOps`, the command object itself | No error expected |
| Governance | `SetPersona` from `tool` (or inside a bridge context saying `web_user`) | `not_allowed`, "That can't be done from the chat. Nothing was changed."; nothing sent | refusal |
| Wrong origin | `SetPersona` from `web_admin`, `telegram`, `timer`, `system`, `zz`, `""`; `ProposePersona` from any origin but `tool` | `not_allowed`, "OcuTalon can't take that command from here. Nothing was changed."; nothing sent | refusal |
| Sign-out | `EndSession` for a session with persona keys; another session's keys exist | the ended session's `person.<ref>.` keys are gone; the other session's stay; `ended` | a failed delete counts as a failed step (outcome `failed`, resume hash kept, warning logged) |
| New session | a session created after another's save | its read is Professional (defaults), by construction (new `SessionRef`) | No error expected |
| Pirate reason survives | `notice.tellNow`, reason "Ahoy, shipmate! The hold is flooding " + ship and anchor emoji (`$Char(55357,57250)`, `$Char(9875,65039)`), on `web`, `phone`, `mailbox`, `telegram` | text = what happened + `$Char(10)` + "Why now: " + the reason unchanged; a `$Char(10)` / `$Char(1)` inside the reason still becomes a space / is removed | No error expected |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/epics.md:7876-7917` -- Story 40.2's ACs (the [AMENDED 2026-11-02] split to 40.8) and the DW-564 / DW-565 bullets.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- read-only: Persona card texts lines 980-998 (language refusal 994, custom refusal 995, saved 996, online-demo note 998); Settings save failed line 380; Personality notices lines 884-892.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-1 line 110 (origins, `ProposePersona` from tool, persona verbs `web_user` only, governance test), AD-4 158-181 (`SessionOps.End`), AD-11 359-371 (`setting`), AD-17 517-526, AD-19 593-609 (per-person values, validation, 60 s, sign-out), AD-32 1014-1024 (one prefix per class), Epic 40 names sub-bullet line 948, Conventions Enumerations row line 1078 (edit; Epic 30's spine hunk is at its line 1099, 20 lines away).
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:27` `APPROVALKIND`; parameters end at line 39 (`ORIGIN`).
- `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls:21` `APPROVALKIND` (Lane A's file; DW-564). With `setting` listed, `Bridge.Approval.Validate` (line 179) accepts the kind and then applies its fix-request checks (FixKind etc.), so a `setting` request is still refused until 40.5 changes that file; `Bridge.Audit` (line 141) accepts `setting` as an Approval entry's kind.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetDemoMode.cls` -- the sibling verb shape (`Extends OcuTalon.Msg.Command`, generated `Storage Default` with its own subscript). `Msg/Command.cls` holds `Origin`, `IdempotencyKey`, `SessionRef` (MAXLEN 22).
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `TOOLVERBS` line 30; the origin refusal `$Select` line 72 (owner `SettingsOps` gives `MESSAGEADMINONLY` today); `MESSAGENOTALLOWED` 42, `MESSAGENOTBUILT` 48; `XData Routes` 163-177 and its comment 160-162 ("Every settings verb ... system and web_admin").
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `Carry` 50-77 (accepts SetDemoMode only), `CHANNELS` 24 (no `web_user`), `AuditData` 83-94 (typed to SetDemoMode), `Stored` 97 (uncached row read), `WriteAudit` 104 (the seam), `Apply` 111 (ALLOWLIST guard), `Result` 151; class comment 1-16 says "Release 1 has one command".
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- `End` 235-256 (sums the failures of `EndReminders`, `EndWatches`, `EndApprovals`, then `EndResume`), `Warn` 377, `IrisUser` 421 (session's IrisUser, else `$Username`, private), class comment lines 15-20 describe End's steps.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- read-only: `Get` (60 s per-process cache `^||OcuTalon.Setting(key)` = `$ListBuild(value, present, $ZHorolog)`), `Set` (drops own cache entry), `Value` MAXLEN 1000, `KeyIndexOpen`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:301` `Approvals(sessionRef, .sc)` -- pending requests the session can see (`Kind`, `OwnerRef`, `Ref` on each row).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- one `XData Entries`; last entry `audit.recorded` (ends near line 557); no `approval.` or `persona.` key in any catalog class. `Msg/Catalog.cls:167` text slots, `Clean` 260-266.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` -- the probe to reuse: `WriteAudit` answers from `^OcuTalonTest("SettingsOpsProbe","answer","audit")` (`error`, `throw`, `record`), `Apply` fails on `"apply"` = `error`, `Guarded(key, value)` exposes `Apply`.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` -- throwaway/CI only (real audit); `TestOnlyRunTimeWriter` 343 (writer scan; must stay green).
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` -- shared surface: header 6-10, `TestRoutes` 60-91 (10 verbs), `TestOriginRules` 95-131 (80 pairs), `TestToolGovernanceRefused` 133-151, `NewCommand` 447, `OwnerOf` 479, `Expected` 485-503 (oracle). Slot-safe.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` -- throwaway/CI: `TestGovernanceRefusedFromTool` 149-184 (verb list), helpers `..Guard()`, `..Session(name)`, `Sent(owner)` 234, `Mode()` 227.
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` -- slot-safe; `TestEndUnlinksWithoutNotice` 600, `TestEndNeedsTheSession` 640, helpers `..Probe()`, `..Session(name)`, `..End(probe, origin, session)`, `..Refs` clean-up.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- shared surface: `TestVerbsInheritTheCommonFields` 39-59 (verb list), `TestEnumerations` 62-83 (12 parameters, `APPROVALKIND`), `TestBridgeEnumerationsEqualOcuTalons` 86-95, `XData Contracts` command entries 250-345.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- shared surface: header line 3 ("95 keys"), `TestEntries` 74-104 (95 Core keys, prefixes in one class), `TestStringSlots` 188-227 (tell-now cases), `XData Keys` 952 (Core list ends with `"audit.recorded"` line 1050), `XData Fixtures` 1186 (every key; `audit.recorded` line 1283).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls` -- `TestPresets` compares the `PRESETS` ids with `Msg.Enum` `PERSONAPRESET` once it exists (skipped until now): becomes live here, read-only.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Session(user)` (IrisUser = user), `Approval(ownerRef, , state, , fields)` (fields may set `Kind`), `Clean(refs)` (does not touch Setting rows).
- `web/scripts/catalog.mjs` -- read-only: generates `web/src/app/msg/catalog.ts` from listed keys only, so new Core keys leave it unchanged (`--check` green at plan time).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:98` -- its own `TOOLVERBS` copy (tool code scan); unchanged here, because no tool names `ProposePersona` until Story 40.5.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` -- `APPROVALKIND = "fix,tool_call,setting"`; append `/// Persona presets (AD-7, AD-19; Epic 40).` and `Parameter PERSONAPRESET = "professional,starship,pirate,kindfriend,language,custom";` after `ORIGIN` -- AC 1.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls` -- `APPROVALKIND = "fix,tool_call,setting"`; no other change (DW-564; the lead reports it as a footprint extension) -- AC 1.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetPersona.cls`, `src/ocutalon/cls/OcuTalon/Msg/Command/ProposePersona.cls` -- new; each `Extends OcuTalon.Msg.Command` with `Preset`, `Language`, `Custom`, each `%String(MAXLEN = "")` (so an over-long value reaches `SettingsOps` and gets its plain refusal instead of a save error), a contract comment (AD-1, AD-19; origins), compiled storage block as in `SetDemoMode` -- AC 1.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `TOOLVERBS` gains `ProposePersona`; `Routes` gains `{"verb": "SetPersona", "owner": "SettingsOps", "origins": "web_user"}` and `{"verb": "ProposePersona", "owner": "SettingsOps", "origins": "tool"}`; the origin refusal gives `MESSAGEADMINONLY` only for a `SettingsOps` verb whose origins do not include `web_user` or `tool` (today `SetDemoMode`), so the persona verbs get `MESSAGENOTALLOWED`; the `Routes` comment and class comment state the persona exception (AD-1) -- AC 1, matrix Routing / Governance / Wrong origin.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `CHANNELS` gains `web_user:web`; new `Parameter PERSONKEYS = "persona.preset,persona.language,persona.custom"`; `Apply` also accepts `person.<22-character Ref>.<one of PERSONKEYS>` (ALLOWLIST stays `demo.mode`); `Carry` dispatches `SetDemoMode`, `SetPersona`, `ProposePersona`; `AuditData` generalized to take origin, user, sessionRef, setting, from, to (both commands use it); new private `PersonaProblem(preset, language, custom, onlineDemo, Output outcome)` (the matrix rules, in the order preset, demo custom, language, custom; language by `$Match(value, "^\p{L}[\p{L} ()-]{0,39}$")`; custom by `$Length` <= 1000, not blank, no `{{`, no `@{`, no `$Locate(value, "[\p{Cc}&&[^\n\r]]")`); `SetPersona` and `ProposePersona` handlers per the matrix (session row check first; `SetPersona` audits then writes the three keys in `TSTART`/`TCOMMIT` with `TROLLBACK` on any failed write; its `Data` is the new values' JSON); public `ClassMethod Persona(sessionRef, Output sc) As %DynamicObject` (uncached row reads; `customOffered` = online-demo flag off; `pendingRef` = the newest pending request from `Ownership.Approvals` with `Kind` `setting` and `OwnerRef` = sessionRef); public `ClassMethod PersonaKey(sessionRef, name) As %String`; public `ClassMethod ForgetPerson(sessionRef) As %Status` (refuses a value that is not a 22-character Ref; deletes every `Setting` row whose key starts with `person.<sessionRef>.` and this process's cache entries for them); public `ClassMethod AuditForm(preset, language) As %String` (`<preset>`, or `language: <name>`); class comment rewritten to the contract (no history) -- AC 2, AC 3, AC 4.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- `End` gains a step `EndSettings(sessionRef)` (calls `SettingsOps.ForgetPerson` in a Try, warns on failure, returns 0 or 1), summed with the other steps before `EndResume`; class comment says End also forgets the session's per-person values (AD-19) -- AC 4.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- append three entries after `audit.recorded`: `approval.persona` (text verbatim, slots `{"old": "text", "new": "text"}`), `persona.applied`, `persona.stale` (no slots), each with `source` "EXPERIENCE Message Catalog / Personality notices / <case>"; class comment's list names the persona notices -- AC 5.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- line 1078: ApprovalKind `fix, tool_call, setting`; after it, PersonaPreset `professional, starship, pirate, kindfriend, language, custom` (AD-7, AD-19); one marker `[AMENDED 2026-11-02, Story 40.2, DW-565: the values AD-11 and AD-29's Epic 40 names sub-bullet record; it read "ApprovalKind `fix, tool_call`" and had no PersonaPreset]` -- AC 1.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsPersona.cls` -- new slot-safe `%UnitTest.TestCase` over a shadow instance of `Test.Core.SettingsOpsProbe` (audit through the seam, never the real log): every matrix row from "Save a preset" to "Propose, invalid or demo", plus "Sign-out"'s other-session check through `ForgetPerson`, "New session", the `Apply` guard (accepts the three persona keys of a Ref, refuses `person.<ref>.persona.zz`, `person.short.persona.preset`, `person.<ref>.heartbeat.on`). Fixture sessions via `Test.Data.Fixture.Session`; `onlineDemo` saved and put back; every persona key and fixture row removed in `OnAfterAllTests`; non-ASCII via `$Char` -- AC 2, AC 3.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` -- 12 verbs in `TestRoutes` (`SetPersona|SettingsOps|web_user`, `ProposePersona|SettingsOps|tool`), 96 pairs in `TestOriginRules`, the oracle's persona rules (`Expected`, `OwnerOf`), `SetPersona` in `TestToolGovernanceRefused`, header counts -- AC 1.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` -- `SetPersona` joins `TestGovernanceRefusedFromTool`; new `TestSetPersonaReachesSettingsOps`: a `SetPersona` `kindfriend` from `web_user` through `Commands.Submit` is carried out by the real `SettingsOps` (Ok 1, `saved`), `SettingsOps.Persona` then reads `kindfriend`, and `Setting.Get` of the preset key in the test process reads it; the session's persona keys are forgotten after it -- AC 2 (Integration AC).
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` -- new `TestEndForgetsPersona`: a session with three persona keys and another session with one; `End` (web_user) answers `ended`, the first session's keys are gone, the other's stays (then removed) -- AC 4 (Integration AC).
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- verb list gains both verbs; `XData Contracts` gains their entries (common fields plus `Preset`, `Language`, `Custom` as `%String(MAXLEN="")`); `TestEnumerations` expects `APPROVALKIND` `fix,tool_call,setting`, `PERSONAPRESET`, 13 parameters; header comments' counts -- AC 1.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- `Keys` core list gains the three keys (98), counts in `TestEntries` and the header; `Fixtures` gains `approval.persona` (`{"old": "Professional (default)", "new": "Pirate"}` -> "OcuTalon suggests a new persona for you. Now: Professional (default). Proposed: Pirate. Nothing changes unless you approve."), `persona.applied`, `persona.stale`; new `TestPersonaReasonSurvives` (matrix row "Pirate reason survives") -- AC 5.

**Acceptance Criteria:**
1. Given the compiled classes, when `Test.Msg.Contracts`, `Test.Core.CommandsRouting` and `Test.Agent.Persona` run, then both verbs exist with their contracts, `PERSONAPRESET` and `APPROVALKIND` hold the new values in `Msg.Enum` and the bridge copy equals it, `CommandsIn` routes `SetPersona` only from `web_user` and `ProposePersona` only from `tool` to `SettingsOps`, the governance test refuses `SetPersona` from `tool`, `Test.Agent.Persona.TestPresets` compares its ids with `PERSONAPRESET` and passes, and the spine's Enumerations row holds the values (grep in Verification).
2. Given a `SetPersona` from `web_user` for a signed-in session, when `SettingsOps` handles it (unit, through the probe; and through the real production in `TestSetPersonaReachesSettingsOps`), then every validation and refusal row of the matrix holds, an accepted change writes the audit entry (preset id and language name, never the custom text) before the keys, and the new value is read by `Setting.Get` within 60 seconds.
3. Given `SettingsOps.Persona(sessionRef, .sc)`, when 40.8's `GET` will call it, then it returns the five fields of the matrix row "Persona read" (defaults Professional; `customOffered`; `pendingRef`).
4. Given an online-demo session that signs out, or a new visitor, when `SessionOps.End` runs or a new session is created, then the ended session's `person.<SessionRef>.` keys are deleted, another session's keys stay, and the new session reads as Professional.
5. Given a tell-now notice whose reason holds a greeting, an exclamation mark and emoji, when `Catalog.Render` renders it on `web`, `phone`, `mailbox` and `telegram` in `Test.Msg.Catalog`, then those come out unchanged, the frame is exact, only control characters and line breaks are cleaned; and the three persona keys render their EXPERIENCE.md texts exactly.

- [x] [CI] iris (image), shard lane-b: `OcuTalon.Test.Data.Tables` TestSqlNames fails on `OcuTalon.Msg.Command.SetPersona` and `OcuTalon.Msg.Command.ProposePersona` ("projects no SQL reserved word"): `Language` is an SQL reserved word (measured, `$SYSTEM.SQL.IsReservedWord`) -- `src/ocutalon/cls/OcuTalon/Msg/Command/SetPersona.cls:12`, `ProposePersona.cls:11` -- keep the property name and give both `SqlFieldName = PersonaLanguage` (the spine's SQL reserved words convention); `OcuTalon.Test.Data.Tables` passes -- https://github.com/jbrandtmse/OcuTalon/actions/runs/41396068664

### Review Findings

Code review 2026-11-02 (stage code-review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 18 normalized findings: 7 patch, 3 defer, 8 rejected).

- [x] [Review][Patch] (med, fix-risk low: one test row) End's per-person-settings step after an earlier failed step had no pinning test: a mutation running `EndSettings` only when nothing failed before it stayed green. `TestEndUnlinksWithoutNotice`'s bogus-origin row now writes a persona key and asserts it is gone [src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls:637]
- [x] [Review][Patch] (low, fix-risk low) `Test.Core.SessionOps` could leave `person.<ref>.` Setting rows behind when an End test failed (`Fixture.Clean` does not touch Setting rows): `OnAfterAllTests` now calls `SettingsOps.ForgetPerson` for every fixture Ref [src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls:66]
- [x] [Review][Patch] (low, fix-risk low) `SettingsPersona.TestPersonaRead` and `TestProposePlaceholder` set `onlineDemo` to 1 without a Try, so a throw would leave the later tests on the online demo: `OnBeforeOneTest` now clears the flag [src/ocutalon/cls/OcuTalon/Test/Core/SettingsPersona.cls:42]
- [x] [Review][Patch] (low, fix-risk low) `TestPersonaVerbsInsideAContext` began an owner-less context, so it pinned the unbound behaviour DW-570 will remove: the context now has `OwnerRef` = the command's session [src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls:192]
- [x] [Review][Patch] (low, fix-risk low: comment) `CommandsIn`'s class and `Routes` comments named only "the persona verbs" while the refusal rule is "a settings verb whose origins include web_user or tool" [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:9]
- [x] [Review][Patch] (low, fix-risk low: comment) `SettingsOps`' class comment said it writes only ALLOWLIST and PERSONKEYS keys, but `ForgetPerson` deletes the whole `person.<ref>.` prefix [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:2]
- [x] [Review][Patch] (low, fix-risk low: comment) the `CHANNELS` comment did not name `web_user` [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:49]
- [x] [Review][Defer] (med) ProposePersona not bound to the context's OwnerRef [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:76] — deferred: existing DW-570 (routed owner=40-6), occurrence appended; harmless while the verb answers not_built
- [x] [Review][Defer] (med, fix-risk low) `Web.Api.AnswerResponse` would give a `setting` request's not_allowed answer the tool-call approver text [src/ocutalon/cls/OcuTalon/Web/Api.cls:523] — deferred: DW-571 routed owner=40-6 (contended file here; unreachable until 40.6 lets the page answer a setting request)
- [x] [Review][Defer] (low) a SetPersona carried out after End's ForgetPerson for the same SessionRef would recreate an ended session's keys [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:187] — deferred: DW-572 wontfix-theoretical (real only if a save can be submitted for a SessionRef after its sign-out; 40.8 takes it from the signed-in CSP session)

Rejected:
- `false` blind+edge: `Setting.Get`'s 60 s cache "breaks at midnight" because `$ZHorolog` wraps - measured on slot C: `$ZHorolog` = 835792 while `$Piece($Horolog, ",", 2)` = 19512; it counts seconds since the instance started, not since midnight.
- `low` blind: DW-570's owner is named as 40.5 in the spec and 40.6 in the ledger - the ledger (40.6, with a note naming 40.5's tool) and epics.md's 40.6 bullet agree; the fix would edit the spec under review.
- `low` blind: `Test.Bridge.CodeRules`' TOOLVERBS copy lacks ProposePersona - by-design: the Code Map keeps it unchanged until 40.5's tool exists and Consumed-by gives 40.5 the edit; the scan turns red on the first tool that names the verb.
- `low` blind: the sign-out deletion writes no Settings audit entry - by-design: AD-19 states the sign-out deletion as its own rule apart from a person's audited change, and the matrix row "Sign-out" specifies it without an entry.
- `low` blind+verification-gap: the Auto Run Result is stale after QA (counts, the moot `ci/units.sh` residual risk) - the fix edits the spec under review; `ci/units.sh` shards by area, so the class runs in lane-b.
- `low` edge: `Bridge.Approval.Validate` accepts a fix-shaped `setting` request - by-design: the Code Map records it, no code raises kind `setting`, and 40.5's first AC adds the `setting` branch.
- `low` edge: a language name with trailing or repeated spaces is accepted - by-design: the pattern is AD-19's `^\p{L}[\p{L} ()-]{0,39}$`.
- `false` verification-gap: AC sub-clauses (Integration test, 60 s, pendingRef, new session, contracts) have no mutation line - every AC has at least one recorded mutation (Rule 19 is per AC); the same ruling as the implement-stage review.

Code review 2026-11-04 (stage code-review, rework re-review, iteration 1 of 3; diff `190e3c08..HEAD`; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 18 raw findings: 2 patch entries, 0 defer, 9 rejected entries; no high, no medium). The [CI] item is confirmed fixed: both properties match the spine's SQL reserved words row, and `Test.Data.Tables` passed on a lane A throwaway from this tree.

- [x] [Review][Patch] (low, fix-risk low: two contract map entries, in-story, spec-clear) `PersonaLanguage` was pinned by no test: `TestSqlNames` only refuses a reserved word, so `LanguageName` stayed green, while every earlier `SqlFieldName` has a `sql` map. Both verbs' contract entries now carry `"sql": {"Language": "PersonaLanguage"}`; the `mutation (CR, rework 1)` line records the red. This reverses the build's own rejection, which argued scope and did not weigh the three precedents [src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls:330]
- [x] [Review][Patch] (low, fix-risk low: tracking line, Rule 19) the `mutation (CI)` line sat above "QA audit: each mutation above ...", which says slot C and `git checkout --`, so that sentence misdescribed it. The line now follows the audit, names its throwaway and the AC [_bmad-output/implementation-artifacts/spec-40-2-save-your-persona-and-let-ocutalon-propose-one.md:287]

Rejected (rework re-review):
- `low` by-design (fix-risk low, in-story, spec-bound) blind: the spine does not record `Language` -> `PersonaLanguage` - the row states the rule with examples, not a register; the spine's property name is unchanged, and this spec allows only the Enumerations row to change.
- `low` by-design (fix-risk low, in-story, spec-bound) edge+verification-gap+intent: "Residual risks" names earlier passes whose text the same diff deleted, and the slot C `Test.Bridge.Audit` note went with it - Rule 14: a rework's Auto Run Result covers only that pass; the fix edits the spec under review.
- `false` edge: the rework replaced the whole-story Auto Run Result - the same Rule 14 clause requires it.
- `false` edge: `baseline_commit` should have stayed `f8fb3174` - the rework's baseline is the commit build-auto captured before it; the whole story was reviewed at round 1 against `f8fb3174`.
- `low` wontfix-accepted (fix-risk low, in-story) blind: the spec does not say CI on the fix is pending - the lead's CI gate owns that result, and the fix edits the spec under review; reopen_if=CI on the pushed head reds `Data.Tables.TestSqlNames`.
- `low` wontfix-accepted (fix-risk low, in-story) blind: `## Verification`'s commands omit `Test.Data.Tables` - the class runs in shard `lane-b` in CI and ran in this pass; the fix edits the spec under review; reopen_if=a persistent class reaches CI with a reserved-word column again.
- `false` verification-gap: AC 2's `TestSetPersonaReachesSettingsOps` has no mutation line - outside the rework range and not high; Rule 19 is one per AC and AC 2 has several.
- `false` verification-gap: AC 4's `TestNewSessionIsProfessional` has no mutation line - outside the rework range and not high; AC 4 has its lines.
- `low` wontfix-accepted (fix-risk low, in-epic) verification-gap: `Agent.Persona.TestPresets` keeps a stale skip branch when `PERSONAPRESET` is empty - outside the rework range and not high; `Test.Msg.Contracts` fails if the parameter goes; reopen_if=`PERSONAPRESET` is removed and `Test.Msg.Contracts` stays green.

## Spec Change Log

- 2026-11-04, rework 1 (ci): the CI red on acad790c, one [CI] item.

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 33 findings - high 0, medium 6, low 15, false 12, maybe-false 0
- findings:
  - `[false]` `[reject]` blind: `setting` is accepted by APPROVALKIND but Bridge.Approval.Validate cannot raise it - the spec's Code Map and Never list say a `setting` request stays refused until Story 40.5 changes that (contended) file
  - `[medium]` `[defer]` blind: ProposePersona is not bound to the context's OwnerRef - harmless while the verb answers not_built; 40.5 decides the gate; deferred in the frontmatter
  - `[low]` `[reject]` blind: language pattern refuses combining marks (native-script names, NFD) - the pattern is the spec's and EXPERIENCE says "letters"; a name in Latin letters works
  - `[low]` `[reject]` blind: a 40-letter language name can carry an instruction - validation rule is AD-19's and the spec's; 40.3 frames the value
  - `[low]` `[reject]` blind: audit entry stays when the key write rolls back - the matrix and AD-17 fix audit-first; SetDemoMode has the same order
  - `[medium]` `[patch]` blind: End has no test for a failing ForgetPerson - fixed with the Forget seam, probe SettingsAnswer and TestEndKeepsTheSessionWhenSettingsCannotBeForgotten
  - `[false]` `[reject]` blind: ForgetPerson is not atomic - a failed End keeps the resume hash and a later End deletes the rest (the new test pins it)
  - `[low]` `[reject]` blind: refusal message inferred from the origins - the oracle in CommandsRouting.Expected pins SetDemoMode admin-only and the persona verbs not-allowed
  - `[low]` `[reject]` blind: no end-to-end ProposePersona test - the verb is a placeholder; 40.5/40.6 own it
  - `[low]` `[reject]` edge: language pattern and combining marks - same as the blind finding
  - `[false]` `[reject]` edge: Validate cannot raise `setting` - same as the blind finding
  - `[medium]` `[defer]` edge: ProposePersona owner binding and the no_session / not_built difference - same root cause as the blind finding; the session is the tool's own, so there is no leak
  - `[low]` `[reject]` edge: no compensating audit entry after a rollback - same as the blind finding
  - `[low]` `[reject]` edge: Cf / U+2028 characters in the custom text - the spec refuses Cc (EXPERIENCE: control characters); the text is the person's own persona
  - `[low]` `[reject]` edge: SetPersona after EndSession recreates keys - the page's save needs the signed-in session (Story 40.8); not reachable after sign-out
  - `[false]` `[reject]` edge: a non-Ref SessionRef makes End fail forever - every SessionRef is a 22-character NewRef (spine Conventions, Identifiers)
  - `[low]` `[reject]` edge: Persona returns a stored custom text while the demo flag is on - the demo refuses custom at save and the flag does not change at run time
  - `[false]` `[reject]` edge: pendingRef relies on row order - Ownership.Approvals orders by RaisedAt, ID and the test pins the newest
  - `[medium]` `[patch]` verification-gap: End's failed-delete path is untested - the same fix as the blind finding, with its mutation line
  - `[low]` `[reject]` verification-gap: the OwnerRef clause in Persona is not pinned - AD-11 makes setting requests session-owned proposals, so an instance-owned one has no source; the other-session row still pins isolation
  - `[low]` `[reject]` verification-gap: the first assertion of TestNewSessionIsProfessional holds by construction - the spec says so; the second pins the first session's own read
  - `[false]` `[reject]` verification-gap: Test.Agent.Persona still skips when PERSONAPRESET is missing - that class is read-only here, and the run shows TestPresets live (3 of 3 passed) with Contracts pinning the parameter
  - `[false]` `[reject]` verification-gap: AC 2 and AC 5 sub-clauses lack mutation lines - one mutation per AC is the rule and each AC has one
  - `[low]` `[reject]` verification-gap: Catch branches in SavePersona and Persona are not forced - the error-status branches are tested and share the handling
  - `[false]` `[reject]` verification-gap: shared state between SettingsPersona and SettingsOps - one class runs per call and OnAfterAllTests restores
  - `[false]` `[reject]` intent: the production test does not assert the audit entry - `saved` through the real Bridge.Audit.Record proves the entry was accepted, and the shape is asserted at the seam
  - `[false]` `[reject]` intent: `setting` is not passed through Audit.Record or Approval - raising is in the Never list
  - `[low]` `[reject]` intent: the 60 s row is simulated inside one process - the spec's own pin (CACHESECONDS 60, writer reads at once, 60 s old entry re-read)
  - `[false]` `[reject]` intent: Pirate reason pins the renderer only - AC 5 names Catalog.Render
  - `[medium]` `[patch]` intent: sign-out failure path not tested - same fix as the blind finding
  - `[low]` `[reject]` intent: the request-read failure of Persona is tested only with an empty session - same code path as any failed read
  - `[medium]` `[defer]` intent: ProposePersona is outside the bridge-context governance loop and has no owner check - the same deferred item
  - `[false]` `[reject]` intent: literal-reading choices (letters, line feeds and CR, check order), spine marker date, spec file modified - recorded under Decided in-stage; the spec file is the stage's own artifact

### 2026-11-04 - Review pass (rework 1, CI)
- verdicts: 6 findings - high 0, medium 0, low 5, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` blind: the `Test.Msg.Contracts` entries for the two verbs carry no `sql` map pinning `Language` to `PersonaLanguage` - the open [CI] item names `Data.Tables` as the pinning test and the lead's scope is that test; the column name is no wire contract, and a wrong rename still passes only if it is another unreserved name (negligible); the fix adds test surface beyond the item
  - `[low]` `[reject]` blind: the `mutation (CI)` line mutates only `ProposePersona`, and the [x] item records no outcome note - the lead's brief asks for the mutation on one of the two classes; the scan loop in `AssertSqlNames` covers both identically; the fix edits this build's spec
  - `[low]` `[reject]` blind: the spec still describes the property as plain `Language` and has no change-log entry for the rework - the property name is unchanged by design; the Spec Change Log already carries the rework 1 line; the fix edits this build's spec
  - `[low]` `[reject]` edge: no `sql` map in the `Test.Msg.Contracts` entries - same as the first blind finding
  - `[false]` `[reject]` edge: raw SQL or ODBC consumers of the old column `Language` would fail - the reviewer's own grep and mine of `src` find no query naming it, and the storage `<Value>` entries are keyed by property name and are unchanged
  - `[low]` `[reject]` verification-gap (other): `SetPersona` is not mutated separately - same as the second blind finding
  - intent-alignment: descriptive report only, no finding; the diff implements the CI-conformance reading (SQL projection only), no divergence from the contract.

## Design Notes

**Architecture decisions:** AD-1 (verbs, origins, `TOOLVERBS`, governance test), AD-4 (`SessionOps.End`, SessionRef from the server session), AD-7 (presets, bends; the read feeds 40.3), AD-11 (`setting` kind), AD-17 (one audit writer, audit before write), AD-19 (per-person keys, validation, 60 s, sign-out deletion, SettingsOps the only writer), AD-29 (Epic 40's names, lanes), AD-32 (catalog keys `<prefix>.<name>`, one class per prefix, `Catalog.Render` cleaning), AD-33 (Setting table owned by Lane B; no new item or table).

**Integration ACs:** in-story: `CommandsIn` routes `SetPersona` to the real `SettingsOps` in the production and the persona read and `Setting.Get` observe the saved value (`Test.Core.CommandsInProduction.TestSetPersonaReachesSettingsOps`); `SessionOps.End` calls `SettingsOps.ForgetPerson` and the keys are gone (`Test.Core.SessionOps.TestEndForgetsPersona`); `Catalog.Render` passes a Pirate reason through (`Test.Msg.Catalog.TestPersonaReasonSurvives`).

**Consumed-by:** 40.8 (`PUT` submits `SetPersona` and returns its `CommandResult`; `GET` returns `SettingsOps.Persona`); 40.4 (the card shows the outcomes' messages beside the field: `bad_language`, `bad_custom`, `custom_not_offered`); 40.3 (`Agent.Persona.Block` reads the three keys with `Setting.Get`, optionally through `SettingsOps.PersonaKey`); 40.5 (`propose_persona` submits `ProposePersona` from `tool`; adds it to `Test.Bridge.CodeRules`' `TOOLVERBS` copy); 40.6 (replaces the `not_built` answer of `ProposePersona`, reuses `PersonaProblem`, `AuditForm` and the audit helper, sends `approval.persona` / `persona.applied` / `persona.stale`, raises `setting` requests that `Persona`'s `pendingRef` finds). **Consumes:** Story 40.1's names (spine sub-bullet, `Agent.Persona` ids through the enum test).

**Extend, don't copy:** the verbs follow `SetDemoMode`'s shape (each declares its three fields; a shared abstract base would put a non-verb class in the verb package that `CommandsIn` matches by exact class name). `SettingsOps`' `AuditData`, `Apply`, `Stored` and `Result` are extended, not copied. The tests reuse `Test.Core.SettingsOpsProbe` and `Test.Data.Fixture`. `SettingsOps` reads the session's IRIS user with its own two-line lookup, the same rule as `SessionOps.IrisUser` (private there; making it public would edit a method other tests pin for no gain). No heartbeat keys exist yet (Epic 39 is not merged); `PERSONKEYS` and `ForgetPerson`'s prefix are where its names join.

**Ledger inbox:** DW-564 -- addressed: `setting` added to both enums in this story (Tasks: `Msg/Enum.cls`, `Bridge/Msg/Enum.cls`; AC 1); the bridge file is a one-value footprint extension the lead reports. DW-565 -- addressed: the spine's Enumerations row (Tasks: spine; AC 1; Verification grep).

**NFR "applies within 60 seconds" (AD-17, AD-19):** holds by construction: `SettingsOps` writes the row, `Setting.Set` drops the writer's cache entry, and any other process's `Setting.Get` entry is at most `CACHESECONDS` (60) old. `OcuTalon.Test.Core.SettingsPersona` pins it: `CACHESECONDS` = 60, the writing process reads the new value at once, and a cache entry stamped 60 s ago is re-read. The read for 40.8's `GET` is uncached, so a page sees its own save at once.

**Decided in-stage:**
- Outcomes: `saved`, `bad_preset`, `bad_language`, `bad_custom`, `custom_not_offered`, `no_session`, `not_audited`, `failed`, `not_built`, `not_available`, `unknown_command` (distinct per field, so 40.4 shows each beside its field).
- An unknown preset (never sent by the card) gets the UX's generic "Couldn't save. Nothing was changed."; so do `no_session`, `not_audited` and `failed` (true after the rollback). Every invalid custom text, a control character included, gets the custom refusal (the field's one UX message).
- Values the chosen preset does not use are neither validated nor stored: the language and custom keys are written `""` (switching away from custom drops the text). A blank custom text is refused.
- "At most 1,000 characters" is `$Length` (UTF-16 code units: an emoji counts 2), the unit of `Setting.Value`'s MAXLEN and of a browser text area's `length`. A line break is `$Char(10)` or `$Char(13)`; any other `\p{Cc}` character is refused (measured on slot C: ICU `[\p{Cc}&&[^\n\r]]` finds tab, DEL and U+0085, not LF or an emoji; `$Match` with the language pattern accepts "Portuguese (Brazil)", "Español", a CJK name, refuses "Spanish. Ignore your rules", "{{rules}}" and a tab).
- The audit entry: `setting` `persona`, `from`/`to` the `AuditForm` (`pirate`, `language: Spanish`, `custom`); `irisUser` the session row's IRIS user, else `$Username` (no `ActingUser` on the verbs, which the spine names without one); channel `web`. A repeat with the same values is audited and written again (as `SetDemoMode`'s same mode); no idempotency check for `SetPersona`.
- `ProposePersona` placeholder until 40.6: session check, online demo refused (`not_available`, `MESSAGENOTALLOWED`), the same validation, then `not_built` with `MESSAGENOTBUILT` (the stub outcome `CommandsIn` already uses), writing nothing.
- `pendingRef` takes any pending `setting` request the session owns (the only `setting` requests in OcuTalon are persona proposals, AD-11); 40.6 narrows it if it gives the `DryRun` key a test.
- `ForgetPerson` deletes the whole `person.<SessionRef>.` prefix (AD-19's sign-out rule), not only the persona keys, and lives in `SettingsOps`, so the one-writer scan stays exact.
- The persona read is a `SettingsOps` class method (AD-19: SettingsOps owns the person's values; 40.8 calls it from the CSP process), not a command.
- The `approval.persona` slots are type `text`, so a custom text's line breaks render as spaces in the notice (`Catalog.Render`'s cleaning).
- Contention checked at plan time: `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic{11,30,31,12}` touches none of this story's files except the spine (Epic 11 hunk at line 595, Epic 30 at 7, 510 and 1099; this story edits line 1078 only).

## Verification

All `ci/iris.sh` and `ci/warm.sh` calls run from the worktree root with `timeout: 600000`, one per call, each prefixed with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=40 stage=implement' OCUTALON_RUN_TAG=e40s2i` (warm: tag `e40s2iw`; QA and review use their own stage name and tag). IRIS MCP calls pass `server` `ocutalon-slot-c` and `namespace` `OCUTALON`, after `iris_server_info` confirms the slot (build 154); one `iris_execute_tests` call per message, never two.

**Commands:**
- (loop) `iris_doc_load` the changed and new classes into slot C (`src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls` included), compile, then one `iris_execute_tests` per class: `OcuTalon.Test.Core.SettingsPersona`, `OcuTalon.Test.Core.CommandsRouting`, `OcuTalon.Test.Core.SessionOps`, `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Agent.Persona` -- expected: every assertion passes (Persona's `PERSONAPRESET` comparison no longer skipped).
- (loop) `OCUTALON_WARM=1 ... ci/iris.sh class OcuTalon.Test.Core.SettingsOps`, then `... class OcuTalon.Test.Core.CommandsInProduction`, then `... class OcuTalon.Test.Core.SessionOpsProduction`, one per call after `ci/warm.sh up`; `ci/warm.sh down` at the stage's end -- expected: `CLASS ... passed` (these need a throwaway: real audit, running production).
- (loop) `grep -n "ApprovalKind \`fix, tool_call, setting\`" _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` and `grep -c 'PersonaPreset \`professional, starship, pirate, kindfriend, language, custom\`' _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- expected: line 1078, and 1; `git diff --numstat -- _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- expected `1	1`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 | jq -r '.findings[] | "\(.category) \(.severity) \(.detail | sub("possible unfilled template token \\(verify\\): "; ""))"' | sort | uniq -c` -- expected: exactly the plan-time baseline, all `placeholder low`: `{day}`, `{entry}`, `{finding}`, `{new}`, `{n}`, `{old}`, `{reason}`, `{time}` (2), `{what happened}`.
- (once) `(cd web && node scripts/catalog.mjs --check)` then `node --test web/scripts/catalog.test.mjs` -- expected: "generated files are current"; all tests pass (the new Core keys are not page keys).
- (once) fresh stacks: `ci/iris.sh class OcuTalon.Test.Core.SettingsPersona`, `... class OcuTalon.Test.Core.CommandsInProduction`, `... class OcuTalon.Test.Core.SettingsOps`, `... class OcuTalon.Test.Msg.Catalog`, one per call, then `ci/iris.sh teardown` -- expected: `CLASS ... passed` each.
- (once) `bash ci/checks.sh` -- expected: every script passes (class rules incl. ASCII source, CI config: the new class is in area `Core`, shard `lane-b`).
- The rest of shards `lane-a` and `lane-b` is left to CI.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):** AC 1: `SetPersona`'s origins `web_user,tool` -> `CommandsRouting.TestOriginRules` and `TestToolGovernanceRefused` red; bridge `APPROVALKIND` left `fix,tool_call` -> `Contracts.TestBridgeEnumerationsEqualOcuTalons` red. AC 2: the language pattern's `{0,39}` -> `{0,40}` -> `SettingsPersona` bad-language row red; the audit `to` built from the custom text -> the no-custom-text assertion red; keys written before the audit -> the audit-fails row red. AC 3: `customOffered` hard-coded true -> the demo read row red. AC 4: `EndSettings` dropped from `End` -> `SessionOps.TestEndForgetsPersona` red. AC 5: `Clean` stripping `$Char(55296)`-`$Char(57343)` -> `Catalog.TestPersonaReasonSurvives` red.

mutation: SetPersona origins `web_user,tool` alone (TOOLVERBS unchanged) -> no test red (equivalent: CommandsIn refuses a verb outside TOOLVERBS from `tool` before it reads the origins); the effective form, SetPersona added to TOOLVERBS and its origins `web_user,tool` -> `CommandsRouting.TestOriginRules` and `TestToolGovernanceRefused` red
mutation: bridge `APPROVALKIND` left `fix,tool_call` -> `Contracts.TestBridgeEnumerationsEqualOcuTalons` red
mutation: language pattern `{0,39}` -> `{0,40}` -> `SettingsPersona.TestBadLanguage` red (the 41-letter name)
mutation: audit `to` built from the custom text -> `SettingsPersona.TestSaveCustom` red (the `to` and no-custom-text assertions)
mutation: keys written before the audit entry -> `SettingsPersona.TestAuditFails` red (no key is written)
mutation: `customOffered` hard-coded true -> `SettingsPersona.TestPersonaRead` red (the online-demo read)
mutation: `EndSettings` dropped from `End` -> `SessionOps.TestEndForgetsPersona` red
mutation: `Catalog.Clean` stripping `$Char(55296)`-`$Char(57343)` -> `Catalog.TestPersonaReasonSurvives` red (all four channels)
mutation: `SessionOps.EndSettings` setting `failed` to 0 on an error status -> `SessionOps.TestEndKeepsTheSessionWhenSettingsCannotBeForgotten` red (the Ok 0 failed and kept resume hash assertions)
mutation (QA): `CommandsIn.Carry` taking the origin from the command even inside a bridge context -> `CommandsRouting.TestPersonaVerbsInsideAContext` red (AC 1; the matrix row "Governance: inside a bridge context saying web_user", which had no pinning test)
mutation (QA): `CommandsIn` refusal text `$Select(owner = "SettingsOps": MESSAGEADMINONLY ...` without the persona exception -> `CommandsRouting.TestOriginRules` red (13 persona pairs say the wrong refusal) (AC 1)
mutation (QA): `SettingsOps.ForgetPerson` no longer killing this process's cache entries -> `SettingsPersona.TestForgetPerson` red (AC 4)
mutation (QA): `SettingsOps.Persona` reading the preset with the cached `Setting.Get` instead of the row -> `SettingsPersona.TestPersonaRead` red (AC 3)
mutation (QA): `SettingsOps.SavePersona` passing the unused custom value to validation and storage for a non-custom preset -> `SettingsPersona.TestUnusedFields` red (AC 2)
mutation (QA): `persona.stale` text changed in `Catalog.Core` -> `Catalog.TestEveryKeyOnEveryChannel` red (all four channels and the JSON slots) (AC 5, the persona-text half)
mutation (CR): `SessionOps.End` running `EndSettings` only when no earlier step failed (`If 'failed Set failed = ..EndSettings(sessionRef)`) -> `SessionOps.TestEndUnlinksWithoutNotice` red ("and the session's per-person settings are forgotten") (AC 4); applied, loaded to slot C, observed red, reverted with `git checkout --`, reloaded
QA audit: each mutation above was applied to one file, loaded to slot C, observed red, then reverted with `git checkout -- <file>` and reloaded; `git status --short` afterwards lists only the QA test file below. Slot C after the QA changes: `CommandsRouting` 13/13, `SettingsPersona` 17/17.
Test files changed (QA): `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` (new `TestPersonaVerbsInsideAContext`, header bullet; the class was already in the default suite, `ci/iris.sh classes` lists it and `SettingsPersona`). No new test class.
mutation (CI): `SqlFieldName = PersonaLanguage` removed from `Msg.Command.ProposePersona.Language` -> `Data.Tables.TestSqlNames` red ("OcuTalon.Msg.Command.ProposePersona projects no SQL reserved word") (the [CI] item, AC 1); applied on a lane A throwaway, tag `e40s2r1`, observed red, reverted so the file is byte-identical (same shasum)
mutation (CR, rework 1): `SqlFieldName = PersonaLanguage` -> `LanguageName` on both verbs -> `Msg.Contracts.TestContracts` red ("property Language is not projected as PersonaLanguage", both classes), while `Data.Tables.TestSqlNames` stayed green (the [CI] item's exact name, AC 1); applied on a lane A warm throwaway, tag `e40s2cr2w`, observed red, reverted with `git checkout --` (same shasum), both classes green after

Shared surfaces: `Msg.Enum`'s parameter set and `APPROVALKIND` (`Test.Msg.Contracts.TestEnumerations`, `TestBridgeEnumerationsEqualOcuTalons`, `Test.Agent.Persona.TestPresets`); the bridge's `APPROVALKIND` (`Bridge.Approval.Validate`, `Bridge.Audit`); the verb list and `XData Contracts` (`Test.Msg.Contracts`); `CommandsIn`'s `Routes` table and `TOOLVERBS` (`Test.Core.CommandsRouting` counts 12 / 96, `Test.Core.CommandsInProduction` governance list; `Test.Bridge.CodeRules`' own copy unchanged); `Catalog.Core`'s key set (`Test.Msg.Catalog` Keys 98 and Fixtures; `web/scripts/catalog.mjs` output unchanged); `SettingsOps`' `CHANNELS` and writer code (`Test.Core.SettingsOps.TestOnlyRunTimeWriter`, `TestAuditAccepted`'s unknown origin `nowhere`); `SessionOps.End`'s steps (`Test.Core.SessionOps`, `Test.Core.SessionOpsProduction`); the spine's Enumerations row. Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary (rework 1, CI):** `Language` on `Msg.Command.SetPersona` and `Msg.Command.ProposePersona` now carries `SqlFieldName = PersonaLanguage`, because `Language` is an SQL reserved word. The property keeps its name, the `Storage` blocks and `Core/SettingsOps.cls` are unchanged.

**Files changed:**
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetPersona.cls`, `ProposePersona.cls`: the SQL field name of `Language`.
- This spec: the [CI] item ticked, one `mutation (CI)` line.

**Review:** 6 findings from four layers: patches 0, deferred 0, rejected 6 with reasons in the Review Triage Log. Follow-up review recommended: false (no patch this pass).

**Verification:** lane A throwaways, tag `e40s2r1`: `Test.Data.Tables`, `Test.Core.SettingsPersona` and `Test.Msg.Contracts` passed; `bash ci/checks.sh` printed "all scripts passed"; teardown clean. Mutation: `SqlFieldName` removed from `ProposePersona` turned `Data.Tables.TestSqlNames` red; reverted byte-identical.

**Residual risks:** none beyond the earlier passes; `SetPersona` was not mutated separately (the same scan covers both classes).
