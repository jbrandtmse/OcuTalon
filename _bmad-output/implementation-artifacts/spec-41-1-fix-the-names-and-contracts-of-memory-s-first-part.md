---
title: "Story 41.1: Fix the names and contracts of memory's first part"
type: 'feature'
created: '2026-11-07'
status: 'done'
baseline_revision: '871a29ef918f4e4f534e37608d49188ff2c3441c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-41-context.md'
warnings: [oversized]
deferred:
  - summary: "Story 41.7's evaluation seeding does not fit the first part's contracts as fixed: EvalIn is to send seeded precedents to PrecedentOps as RecordPrecedent (owner eval, only while OCUTALON_EVAL=1) and remove them after the run, but RecordPrecedent carries only ApprovalRef, Action, Channel and SessionRef (no match key, Summary, outcome then or a noise answer, so 'three noise precedents from the same sender' cannot be expressed), AD-21 says PrecedentOps accepts RecordPrecedent only from AnswerOps, and ForgetPrecedent is accepted from web_user only, so EvalIn has no removal path."
    evidence: "epics.md Story 41.7 AC 2 against ARCHITECTURE-SPINE.md AD-21 (the 'only writer' list, lines 736-740), the RecordPrecedent row (line 1376) and AD-1 (line 117). Not among Story 41.1's ACs; naming EvalIn as an accepted sender would change AD-21's Rule (U7), so this story records nothing for it."
    location: "_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:736"
    severity: med
    footprint: in-epic
  - summary: "AD-21's 'accepts only' list for PrecedentOps names MarkNoise and RecordPrecedent but not ForgetPrecedent, which AD-1 and the new Epic 41 names sub-bullet route to PrecedentOps from web_user."
    evidence: "ARCHITECTURE-SPINE.md lines 736-740 against line 117 (AD-1) and the Epic 41 names sub-bullet and cross-area row this story added. Fixing it edits AD-21's Rule text, which this story's Always boundary forbids; it fits the AD-21 amendment the lead writes at Story 41.2's plan (ForgetPrecedent from web_user listed beside MarkNoise)."
    location: "_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:736"
    severity: med
    footprint: in-epic
---

<intent-contract>

## Intent

**Problem:** Memory's first part is built in two lanes: Lane B's table, operation, verbs and routes (41.2, 41.3, 41.5, 41.6) and Lane A's renderer (41.4, 41.7). So the names they meet on, and `Agent.Input`'s context signature and block forms, have to be fixed once, in the spine and in code, before either lane builds on them.

**Approach:** Check that the spine's ownership tables hold every first-part row, and add the one gap, the verbs `MarkNoise`/`ForgetPrecedent` (an AD-29 "Epic 41's names" sub-bullet plus one cross-area row, both additive). In `OcuTalon.Agent.Input`, add the optional `context` parameter to `Render` (ignored for now) and three block-form constants (two opening lines verbatim from EXPERIENCE.md, plus the quote prefix that `Quoted` then uses). Pin all of it in one new test class, and check (without editing) EXPERIENCE.md's memory UX and its marker.

## Boundaries & Constraints

**Always:**
- Spine edits are additive lines only: exactly one sub-bullet and one table row, each marked `[ADDED 2026-11-07, Story 41.1 ...]`. No AD's Rule text changes, no existing line changes, and the frontmatter (`updated:`) is not touched (other epics edit it).
- `Render(item, now)` gives byte-identical text for every item, with or without a `context`. `Quoted` gives byte-identical text, and every existing caller and test is unchanged.
- The opening-line texts are copied verbatim from EXPERIENCE.md lines 1071-1072 (UX-DR117). Source is ASCII (Rule 14). Comments state the contract, never history.
- Lane A files only (U-177): `Agent/Input.cls` and the new `Test/Agent/RenderContext.cls`, plus the spine rows the AC asks for.

**Never:**
- Render any context block, read `context`, call `DailyNote`/`Precedent`, or add a block-composing method. All of that is Story 41.4's.
- Edit EXPERIENCE.md, `Test/Agent/{Constants,Models,Runners,RunnerFixture,Render,PersonaBlock}.cls`, `Test/Contract/Ac.cls`, any Lane B class or test, `ci/units.sh` or `docker/`.
- Create `Msg.Command.*`, `Core.Msg.RecordPrecedent`, `Data.Precedent`, `Data.DailyNote`, `Msg.Enum` values or routes. Those are Lane B's Story 41.2.
- Add the core-memory line "Your core memory (facts you pinned):" (Epic 41's second part, Story 41.12), or invent wording for a precedent row's line.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Context ignored | Items with provenance `user` (channel `web`), `untrusted` (`mailbox`, with sender and subject), `untrusted` (`heartbeat`) and `""`, owned by `""`, `instance`, `eval` and a 22-character Ref that no session or person row holds. Context omitted, `""`, `{}`, `{"sessionStart":1}`, `{"sessionStart":0}`, `"x"`, `[]` | `Render(item, NOW, context)` = `Render(item, NOW)`, byte for byte, non-empty for each item that has text | No error expected |
| Empty with context | An empty Item; a user item of white space; `now` = `"not a time"`; no item (`""`). Each with `{"sessionStart":1}` | `""` | no throw |
| Signature | compiled `OcuTalon.Agent.Input` `Render` | `FormalSpec` exactly `item:OcuTalon.Msg.Item,now:%String="",context:%DynamicObject=""`; `ReturnType` `%Library.String`; class method | No error expected |
| Openings | `NOTESOPENING`, `PRECEDENTSOPENING` | the texts of EXPERIENCE.md lines 1071 and 1072, verbatim; each one line, with no `{{`, no `@{` and no control character | No error expected |
| Quoting | `QUOTEPREFIX`; `Quoted("a"_$C(10)_"b")`; `Quoted("")` | `"> "`; `"> a"_$C(10)_"> b"`, built from `QUOTEPREFIX`; `"> "` | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Agent/Input.cls`: the one renderer (77 lines). Class comment at 1-16. `Render(item, now = "")` at 20-40, doc comment at 20-21. Private `PersonaPart` at 42-51. `Preamble` at 53-62. `Quoted` at 64-75, with the literal `"> "` at line 72. No parameters yet. It is free of other epics' changes.
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls:82-89`: the sibling pattern for code-written lines (`Parameter OPENING`, `LANGUAGELINE`, `STYLELINE`, each with a `///` line saying what it is). `BlockFor` (line 112) composes `..#OPENING_$Char(10)_##class(OcuTalon.Agent.Input).Quoted(text)`, which is the block form that 41.4 repeats. Read-only.
- Callers of `Render` (read-only, unchanged): `Core/Intake.cls:156` (`RequestFor`, used by `Conversation.Request`), `Digest/Process.cls:570`, `Eval/In.cls:647`, `Test/Agent/Decide.cls:392`. Every call passes one or two arguments.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:141-166`: `TestCrossLaneSignatures` compares only the listed leading parameter names ("a method may gain optional parameters at the end"). Its entry at line 339 is `args: "item"`. Lane B's file, read-only. It stays green.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Render.cls` and `PersonaBlock.cls`: the regression classes (literal `"> "` expectations; PersonaBlock seeds person rows). Unchanged. `PersonaBlock.cls:30` (`Parameter OPENING`, a test-held UX copy) and `Test/Checks/Guard.cls:19,49` (`UXBANNED` compared with the class's `BANNED`) are the pattern for the new test's UX copies.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZoneCase.cls`: not used. The new test sets no zone, and it compares two renders made in one process.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. The places this story uses:
  - AD-1 at line 117: `MarkNoise`/`ForgetPrecedent` are accepted from `web_user` only.
  - AD-7 at 289-291: the context blocks' form and place, and the `Render(item, now, context)` signature.
  - AD-21 at 723-753: daily notes, precedents, the one writer, the match key, and where they reach a model.
  - AD-29 at line 994: the "Epic 40's names" sub-bullet, the sibling to insert after. It is the last line of the personality-epics bullet, and line 995 starts "After Epic 0".
  - Ownership tables (present, checked at plan time): production `PrecedentOps` at line 1322; Tables `Precedent` at line 1327; cross-area rows at 1373 (`Render` context), 1374 (`KeyFor`/`Similar`), 1375 (`DailyNote.Build`) and 1376 (`RecordPrecedent`). The table's last row is at 1379 (`SetPersona`), followed by a blank line at 1380.
  - REST rows at 1516-1519 (the four routes), and the data model at 1421.
  - The verbs have no row; that is the gap this story adds.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`. Read-only; contended by Epic 17. Its places:
  - The Personality section runs from line 1010 to 1073, under the marker `[ADDED 2026-10-31 ...]` at line 1012.
  - The Memory card is at lines 1049-1055 and "This was noise" at line 1057.
  - Triage's precedents paragraph is at line 1065 (Story 41.4's).
  - "Code-written lines in `Agent.Input`" starts at line 1067. Lines 1071 and 1072 are this story's. Line 1070 is the core memory (second part).
  - The Message Catalog row "Marked as noise" is at line 940, under the marker at line 933.
- `ci/units.sh:17`: area `Agent` is in shard `lane-a` (CI: `shard:lane-a@rest` in `shards-2`), so a new `OcuTalon.Test.Agent.*` class joins CI with no list change.
- Slot A measurement (`ocutalon-slot-a`, OCUTALON, build 154U, read-only SQL on `%Dictionary.CompiledMethod`): today `Render`'s `FormalSpec` is `item:OcuTalon.Msg.Item,now:%String=""`. The sibling `Watch.Notice.WithFixSlots` compiles an optional dynamic-object parameter as `dryRun:%DynamicObject=""`. So the new form is `...,context:%DynamicObject=""`.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: two inserts. These cover AC 1.
  - **Insert 1.** After line 994 ("Epic 40's names"), as the next sub-bullet with the same 4-space indent, add one line: `    - **Epic 41's names** [ADDED 2026-11-07, Story 41.1, AD-29's contract-naming story]: ` followed by:
    - the verbs `MarkNoise` (`DecisionRef`) and `ForgetPrecedent` (`PrecedentRef`). Both carry the common `Origin`, `IdempotencyKey` and `SessionRef` of `OcuTalon.Msg.Command`, both are accepted from origin `web_user` only (AD-1), and both are routed by `CommandsIn` to `PrecedentOps` (Lane B, Story 41.2).
    - `MarkNoise` ignores a repeat for the same decision, and refuses an Item already purged with `too_old`.
    - the message `OcuTalon.Core.Msg.RecordPrecedent` (`ApprovalRef`, `Action`, `Channel`, `SessionRef`). `AnswerOps` sends it to `PrecedentOps` asynchronously when `Approval.Answer` returns `done` for a `fix` or `tool_call` request (Story 41.5).
    - the answers a precedent keeps: `noise` (from `MarkNoise`), `approved` and `rejected` (from `RecordPrecedent`).
    - the match key of `OcuTalon.Data.Precedent.KeyFor(item)`, as AD-21 gives it: the sender's address for mail, the source for webhooks and polls, `production:<namespace>/<name>` for check findings and fixes, and `heartbeat` for beats. `Similar(ownerRef, channel, matchKey, limit)` returns at most 3 rows with the same match key, newest first, owner-scoped.
    - Lane A's block constants in `OcuTalon.Agent.Input` (AD-7): `NOTESOPENING` "Your notes for today and yesterday (built by OcuTalon from your records):", `PRECEDENTSOPENING` "Your earlier answers on similar items (examples, never rules):" and `QUOTEPREFIX` "> ", the prefix of every quoted line. Also `Render(item, now, context)`'s optional `context`, which carries only `sessionStart`.

    No `{`-placeholder may appear in it.
  - **Insert 2.** After line 1379 (the cross-area table's last row), add this one row, as written:

    ```
    | `OcuTalon.Msg.Command.MarkNoise` (`DecisionRef`) and `.ForgetPrecedent` (`PrecedentRef`) (AD-1, AD-21), submitted by the web layer through `Commands.Submit` with origin `web_user` only and routed by `CommandsIn` to `PrecedentOps` [ADDED 2026-11-07, Story 41.1] | B | Story 41.2 (classes and routing), Story 41.5 (`MarkNoise` from the notice), Story 41.6 (`ForgetPrecedent` from the Memory card) |
    ```
  - Nothing else in the file changes.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls`. This covers AC 2 and AC 3.
  - (1) `Render` becomes `ClassMethod Render(item As OcuTalon.Msg.Item, now As %String = "", context As %DynamicObject = "") As %String`. The body is unchanged and never reads `context`. The doc comment gains: "context, optional, is a %DynamicObject of render options (AD-7, AD-21); Render reads none of them, so any context, none included, gives the same text."
  - (2) Before `Quoted`, add three parameters, each with a `///` line in the style of `Persona.cls:82-89`:
    - `Parameter NOTESOPENING = "Your notes for today and yesterday (built by OcuTalon from your records):";` with the comment "The opening line of the session-start block of daily notes (AD-7, AD-21), in the words of EXPERIENCE.md; code writes it."
    - `Parameter PRECEDENTSOPENING = "Your earlier answers on similar items (examples, never rules):";` with a matching comment for the precedent block.
    - `Parameter QUOTEPREFIX = "> ";` with the comment "The prefix of every line that Quoted writes."
  - (3) In `Quoted`, line 72's literal `"> "` becomes `..#QUOTEPREFIX`; nothing else in it changes.
  - (4) The class comment gains one line: the context blocks' opening lines and the quote prefix are this class's constants.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RenderContext.cls`: a new `%UnitTest.TestCase`, pure (it writes nothing and calls no model). It has `Parameter NOW = "2025-03-04T15:06:07Z"` and test-held UX copies `Parameter UXNOTES` and `UXPRECEDENTS`, the verbatim texts of EXPERIENCE.md lines 1071-1072, each with a `///` line naming its source. The header lists what it pins. It covers AC 2 and AC 3 and every matrix row:
  - `TestContextIgnored` (rows "Context ignored" and "Empty with context").
  - `TestSignature` (reads `%Dictionary.CompiledMethod` `OcuTalon.Agent.Input||Render`).
  - `TestOpenings` (equality with the UX copies; one line; no `{{`, `@{` or control character).
  - `TestQuoting` (`QUOTEPREFIX` is `"> "`; `Quoted` output built from `$Parameter("OcuTalon.Agent.Input","QUOTEPREFIX")`).

  No assertion compares against a `_` concatenation to the right of `[` (`class-rules` assert-concat).
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: no edit; run the check in AC 5.

**Acceptance Criteria:**
1. Given the spine after this story, when `grep -c` counts `Epic 41's names` and `OcuTalon.Msg.Command.MarkNoise`, then each is 1. When `grep -n` lists the first part's rows, it finds `PrecedentOps`, `Precedent` (Tables), the `Render(item, now, context)`, `KeyFor`/`Similar`, `DailyNote.Build` and `RecordPrecedent` rows, and the four REST routes. `git diff --numstat` of the spine is `2	0`, and the lint's findings equal the plan-time baseline.
2. Given the compiled `Agent.Input`, when `OcuTalon.Test.Agent.RenderContext` runs, then `Render(item, now, context)` gives exactly `Render(item, now)`'s text for every item and context of the matrix. Its compiled `FormalSpec` is `item:OcuTalon.Msg.Item,now:%String="",context:%DynamicObject=""` and its return type is `%Library.String`.
3. Given `Agent.Input`'s constants, when `RenderContext` runs and the UX comparison command (Verification) runs, then `NOTESOPENING` and `PRECEDENTSOPENING` are EXPERIENCE.md lines 1071 and 1072, verbatim. `QUOTEPREFIX` is `"> "`, and `Quoted` prefixes every line with it. The command prints four `matches` lines.
4. (Integration) Given the existing consumers, when `OcuTalon.Test.Agent.Render`, `.Agent.PersonaBlock`, `.Core.Intake`, `.Bridge.Api` and `.Contract.Ac` run, then each passes, and `git diff --stat` names none of their files. The consumers are `Core.Intake.RequestFor` (the decide request's `Input`), `Digest.Process`, `Eval.In`, and `Agent.Persona.BlockFor` through `Quoted`.
5. Given EXPERIENCE.md, when the implement stage greps it, then:
   - the Memory card (lines 1049-1055) and "This was noise" (line 1057) sit in Later Steps › Personality (lines 1010-1073), under the `[ADDED 2026-10-31` marker at line 1012;
   - the "Marked as noise" status line (line 940) sits under the marker at line 933;
   - `git diff --stat` shows no change to the file.

   All of this was verified at plan time (UX-DR117).

## Spec Change Log

- 2026-11-08 (spec gate, rulings by the Contest Planner under the owner's delegation, ~07:3xZ):
  - **PUBLIC TEXT, APPROVED word for word** (EXPERIENCE.md:1071-1072): `NOTESOPENING` = "Your notes for today and yesterday (built by OcuTalon from your records):"; `PRECEDENTSOPENING` = "Your earlier answers on similar items (examples, never rules):". Both are pinned with fixed strings (the test-held UX copies `UXNOTES` / `UXPRECEDENTS` and the UX comparison command). No other wording may be introduced.
  - **The `deferred:` item on Story 41.7's eval seeding is decided: AD-21 is AMENDED additively, option (a)** (U7 step 2, light path), marker `[AMENDED 2026-11-08, Story 41.7 (planned at 41.2), Contest Planner ruling under the owner's delegation]`, written by the lead when Story 41.2 is planned, in the same bookkeeping commit as 41.2's spec. Conditions: EvalIn may seed precedent rows only while `OCUTALON_EVAL=1`; each seeded row is marked eval-seeded and is removed through PrecedentOps after the run (ForgetPrecedent's `web_user` rule stays for people); a product session never reads an eval-seeded row (pinned: a person's turn beside an eval run sees none); the Prevents clause and the `web_user` and AnswerOps writers stay unchanged; `lint_spine.py` must pass and `spine_updated` is logged; Epic 19's specs that cite AD-21 need no change. **This story does not write the amendment** (its spine edits stay the two additive lines above); the lead harvests the `deferred:` item as routed to Story 41.7 with this ruling.

## Review Triage Log

### 2026-11-07 — Review pass
- verdicts: 19 findings — high 0, medium 1, low 10, false 8, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: cross-lane rows for `RecordPrecedent`, the `Agent.Input` constants and `KeyFor`/`Similar` missing — rows for `Render` context, `KeyFor`/`Similar`, `DailyNote.Build` and `RecordPrecedent` already exist at spine lines 1373-1376 (AC 1 greps); the answers' enum values are Lane B's `Msg.Enum` work (Story 41.2) and an Enumerations-row edit would change an existing line, which the spec forbids.
  - `[low]` `[reject]` Blind: the openings are checked against test-held copies — the spec decided this (40.1 / DW-567 pattern) and adds the hand-run comparison command against EXPERIENCE.md; the fix is a CI hook in Lane B's `docker/`, out of this story's files. No verb-name check: Lane B classes do not exist until 41.2.
  - `[low]` `[reject]` Blind: `TestContextIgnored` must change when 41.4 reads `sessionStart` — intended; the matrix pins "ignored for now" and 41.4 owns the replacing test. Narrating that in a comment would be history.
  - `[false]` `[reject]` Blind: `Similar` limit vs "at most 3" ambiguity — the sub-bullet repeats AD-21's wording by spec; return shapes and limit handling are left to 41.2.
  - `[false]` `[reject]` Blind: `KeyFor` gaps (address extraction, case, web items) — the spec says "as AD-21 gives it"; the class is Lane B's, 41.2.
  - `[false]` `[reject]` Blind: `MarkNoise`/`ForgetPrecedent` semantics unspecified (`too_old`, unknown ref, repeat vs idempotency key) — behaviour belongs to 41.2's classes; this story fixes names only.
  - `[low]` `[patch]` Blind: `Quoted` doc comment still says `"> "` — patched: the comment now says QUOTEPREFIX; comment-only, tests re-run green.
  - `[medium]` `[defer]` Edge: AD-21's "accepts only" list omits `ForgetPrecedent` while the new bullet and AD-1 route it to `PrecedentOps` — real text tension; the fix edits AD-21's Rule, forbidden here; added to `deferred:` for the lead's AD-21 amendment at 41.2's plan.
  - `[false]` `[reject]` Edge: `Similar` limit undefined above 3 or at 0 — duplicate of the `Similar` row above.
  - `[low]` `[reject]` Edge: non-object `context` ("x", `[]`) unguarded for 41.4 — `Render` never reads `context`, and the matrix pins `"x"` and `[]` as ignored; guarding is 41.4's when it reads the value.
  - `[low]` `[reject]` Edge: test equality depends on a stable instance zone — both renders are made in one process back to back; the spec chose no `ZoneCase` on purpose, and a flip between two calls is not realistic.
  - `[low]` `[reject]` Verification gap: nothing pins that `Quoted` follows `QUOTEPREFIX` — byte-identical today; a pin needs a subclass or a source scan, more than a direct fix; 41.4 is the first to build on the constant.
  - `[low]` `[reject]` Verification gap: openings tied to EXPERIENCE.md only by a hand-run command — same as the second Blind row; spec-decided.
  - `[low]` `[reject]` Verification gap: the owner dimension has no persona-bearing owner — the matrix names owners no row holds; a context-dependent persona path does not exist until 41.4.
  - `[false]` `[reject]` Verification gap: AC 1 and AC 5 have no mutation — the spec states they are document checks (grep, numstat, lint), which Rule 19 does not cover.
  - `[low]` `[reject]` Verification gap: `plain '= ""` depends on the ambient zone — same as the Edge zone row.
  - `[false]` `[reject]` Intent: the sub-bullet goes beyond the verbs — Tasks & Acceptance Insert 1 lists exactly this content; the diff matches it.
  - `[low]` `[reject]` Intent: `TestOpenings` compares test-held copies, not the file — duplicate of the second Blind row.
  - `[false]` `[reject]` Intent: "ignored" is shown by output equality only — the matrix states byte-for-byte output as the expected behaviour.

## Design Notes

**Architecture decisions:**
- AD-7: `Agent.Input` is the one renderer; the context blocks' form and place; the `context` signature.
- AD-21: daily notes, precedents, the one writer, the match key.
- AD-1: the verbs come from origin `web_user` only.
- AD-29: the contract-naming story, the names sub-bullet, and lanes.
- AD-33: the same-change rows.
- AD-22: tests and CI.

No AC contradicts an AD's Rule. The 2026-10-31 amendments are in the spine: AD-7 at line 289, AD-21 at line 710, and AD-33's ownership rows at 1322, 1327 and 1373-1376.

**Integration ACs:**
- In-story consumers are the existing callers in AC 4.
- `context` and the two openings have no consumer in this story. The first is Story 41.4, which renders the blocks. Story 41.3 is the first to pass `{"sessionStart":1}`, from `Conversation`.

**Consumed-by:**
- 41.2: the spine names (verbs, message, answers, `too_old`, match key).
- 41.3: `Render`'s `context`.
- 41.4: `NOTESOPENING`, `PRECEDENTSOPENING`, `QUOTEPREFIX` and `context`.
- 41.5: `MarkNoise`, `RecordPrecedent`.
- 41.6: `ForgetPrecedent`.
- 41.7: everything above, for the eval and injection cases.

**Consumes:** the AD-7 and AD-21 amendments, and Epic 40's `Persona.OPENING` pattern.

**Extend, don't copy:**
- The constants follow `Agent.Persona`'s `OPENING`/`STYLELINE` (same form, kept in `Agent.Input` as the AC places them).
- `QUOTEPREFIX` is used by the existing `Quoted`; no second quoting routine.
- The test's UX copies follow `Test.Checks.Guard.UXBANNED` and `Test.Agent.PersonaBlock.OPENING`.
- No block-composing helper: 41.4 composes `opening_$Char(10)_..Quoted(lines)` as `Persona.BlockFor` does.

**Public text:** nothing is shown in the UI. Two model-request strings are added to code, verbatim:
- "Your notes for today and yesterday (built by OcuTalon from your records):" (EXPERIENCE.md line 1071)
- "Your earlier answers on similar items (examples, never rules):" (EXPERIENCE.md line 1072)

`QUOTEPREFIX` "> " is a format (AD-7, line 267), not text. The spine sub-bullet quotes the same strings. No string lacks a source.

**Decided in-stage:**
- **`QUOTEPREFIX` is added.** The AC fixes the quoting as a constant, and `Quoted`'s output stays byte-identical.
- **Only the two openings are fixed.** The core-memory line (EXPERIENCE.md line 1070) belongs to the second part. EXPERIENCE.md gives no wording for a precedent row's line, so 41.4 renders the fields and escalates any connecting words as PUBLIC TEXT.
- **The text pin.** The pin is a test-held UX copy plus a hand-run comparison command, following 40.1's pattern (its EXPERIENCE.md side was accepted as DW-567). It is not a hosted `docker/tests` script, for two reasons: AD-29 runs Lane A's code checks as `%UnitTest` classes, and `docker/` and `ci/units.sh` are Lane B's or contended.
- **The test extends `%UnitTest.TestCase`, not `ZoneCase`.** It sets no zone, and `ZoneCase` touches the instance-zone row.
- **Where the spine edits go.** The sub-bullet sits after "Epic 40's names", as AD-29's precedent does. The row goes at the end of the cross-area table, the appended-row form. No branch of another epic edits either place (checked at plan time with `git diff HEAD...<branch>` for OCT-epic5, 17, 19, 19b, 30, 32 and 34).
- **`KeyFor`/`Similar` return shapes are left to 41.2.** They are Lane B's class, and 41.4 reads them as built.
- **Open, recorded in `deferred:`.** Story 41.7's eval seeding does not fit `RecordPrecedent`'s four fields, AD-21's one-sender rule, or `ForgetPrecedent`'s origin. The decision belongs to 41.2's or 41.7's plan, or to an AD-21 amendment (U7), not to this story.

**Ledger inbox:** none.

## Verification

Run every command from the worktree root, one per call. Rules for each kind of call:
- **Bash:** `timeout: 600000`, sized to finish in about 150 s.
- **IRIS MCP:** name `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every call, after `iris_server_info` confirms build 154. Use one `iris_execute_tests` call per message, and run stateful classes one at a time. Load with `iris_doc_load`, absolute paths and `baseDir` `<worktree>/src/ocutalon/cls`.
- **`ci/iris.sh`:** prefix each call with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=implement' OCUTALON_RUN_TAG=e41s1impl`. QA and review use their own stage name and an `e41s1` tag.

**Commands:**
- (loop) `iris_doc_load` `Agent/Input.cls` and `Test/Agent/RenderContext.cls`, then `iris_execute_tests` `OcuTalon.Test.Agent.RenderContext`. Expected: every assertion passes.
- (loop) `iris_execute_tests` `OcuTalon.Test.Agent.Render`. Expected: passes unchanged.
- (loop) `iris_execute_tests` `OcuTalon.Test.Agent.PersonaBlock`. Expected: passes unchanged (it seeds person rows and removes them).
- (loop) UX comparison. Expected: four lines ending `matches`. The command:

  ```
  bash -c 'E=_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md; for fp in Agent/Input.cls:NOTESOPENING Agent/Input.cls:PRECEDENTSOPENING Test/Agent/RenderContext.cls:UXNOTES Test/Agent/RenderContext.cls:UXPRECEDENTS; do f=src/ocutalon/cls/OcuTalon/${fp%%:*}; p=${fp##*:}; v=$(sed -n "s/^Parameter $p = \"\(.*\)\";\$/\1/p" "$f"); if [ -n "$v" ] && [ "$(grep -cxF -- "- \"$v\"" "$E")" = 1 ]; then echo "$p matches"; else echo "$p DIFFERS"; fi; done'
  ```

  It was proved at plan time on draft lines, and turned red on a one-word change of `PRECEDENTSOPENING`.
- (once) `iris_execute_tests` `OcuTalon.Test.Contract.Ac`, then `OcuTalon.Test.Core.Intake`, then `OcuTalon.Test.Bridge.Api`, one per message. Expected: each passes as before the change (AC 4).
- (once) `git diff --numstat -- _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. Expected: `2	0` (one sub-bullet, one row). Then the AC 1 greps.
- (once) Spine lint:

  ```
  uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 | jq -r '.findings[] | "\(.category) \(.severity) \(.detail | sub("possible unfilled template token \\(verify\\): "; ""))"' | sort | uniq -c
  ```

  Expected: exactly the plan-time baseline (`ok` stays false because of the baseline), every finding `placeholder low`: `1 '{day}'`, `1 '{entry}'`, `1 '{finding}'`, `1 '{new}'`, `1 '{n}'`, `1 '{old}'`, `1 '{reason}'`, `2 '{time}'`, `1 '{what happened}'`.
- (once) The AC 5 grep. Expected: lines 933 and 1012 are listed. The command:

  ```
  grep -n '^\[ADDED 2026-10-31' _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md; git diff --stat -- _bmad-output/planning-artifacts/ux-designs/
  ```

  `git diff --stat` must print nothing.
- (once) `bash docker/tests/test-class-rules.sh`. Expected: every rule PASS.
- (once) `ci/iris.sh class OcuTalon.Test.Agent.RenderContext`, then `ci/iris.sh class OcuTalon.Test.Agent.Render`, then `ci/iris.sh teardown`, one per call. Expected: `CLASS ... passed` for each class, on fresh stacks.
- The rest runs in CI on every push: the full `lane-a` shard (`shards-2` runs the `Agent` area) and every other tier.

**Mutations (Rule 19):**
- AC 2:
  - `If $IsObject(context) Quit ""` at the top of `Render` turns `TestContextIgnored` red.
  - Dropping `= ""` from `context` turns `TestSignature` red.
- AC 3:
  - "never rules" changed to "never a rule" in `PRECEDENTSOPENING` turns `TestOpenings` red, and the UX comparison prints `DIFFERS`.
  - `QUOTEPREFIX` set to `">> "` turns `TestQuoting` red, and `Test.Agent.Render` too.
- AC 4: an extra blank line after the preamble in `Render` turns `Test.Agent.Render` red.
- AC 1 and AC 5 are document checks (grep, numstat and lint), so they have no mutation.

**Shared surfaces:**
- `Agent.Input.Render`'s `FormalSpec`: `Test.Contract.Ac` compares the prefix `item`, which stays green.
- `Agent.Input.Quoted`'s output: `Test.Agent.Render` and `PersonaBlock`, and `Persona.BlockFor`. It is byte-identical.
- The spine's AD-29 sub-bullets and cross-area table: only the lint reads them.
- No test lists `Agent.Input`'s parameters.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Implement and review pass (2026-11-07):

- Summary: the spine gains the Epic 41 names sub-bullet and the `MarkNoise`/`ForgetPrecedent` cross-area row (`2 0` numstat). `Agent.Input.Render` takes an optional `context` it never reads; `NOTESOPENING`, `PRECEDENTSOPENING` and `QUOTEPREFIX` are added and `Quoted` uses the prefix. The new `Test.Agent.RenderContext` pins the matrix.
- Files changed:
  - `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: two additive lines.
  - `src/ocutalon/cls/OcuTalon/Agent/Input.cls`: `context` parameter, three constants, `Quoted` via `QUOTEPREFIX`, comments.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/RenderContext.cls`: new pure test class, four tests.
- Review: 19 findings (medium 1, low 10, false 8). Patches applied: 1 low (the `Quoted` doc comment). Deferred: 1 medium (AD-21's writer list omits `ForgetPrecedent`; recorded in `deferred:` for the lead's AD-21 amendment). Rejected: 17, each with its reason in the Review Triage Log. The first `deferred:` item (Story 41.7's seeding) is left as the lead ruled.
- Follow-up review recommended: false (no high or medium patched).
- Verification on slot A (`ocutalon-slot-a`, OCUTALON, build 154U): `RenderContext` 4/4, `Test.Agent.Render` 4/4, `PersonaBlock` 10/10 (run again after the last patch); `Test.Contract.Ac` 6/6, `Test.Core.Intake` 9/9, `Test.Bridge.Api` 2/2 (once, after the last patch). The UX comparison prints four `matches` lines. AC 1 greps give 1 and 1, numstat `2 0`. Spine lint equals the plan-time baseline (nine `placeholder low`). The AC 5 grep lists lines 933 and 1012 and `git diff --stat` on `ux-designs/` is empty. `docker/tests/test-class-rules.sh` passes every rule.
- Mutations (Rule 19): `QUOTEPREFIX` = `">> "` turned `TestQuoting` red, and `If $IsObject(context) Quit ""` turned `TestContextIgnored` red (both reverted, tree byte-identical). The other three Verification mutation lines were not run in this pass.
- Not run here: the fresh-stack tier (`ci/iris.sh class ...RenderContext`, `...Render`, teardown) does not fit one 150 s call; it runs in CI (`lane-a` shard).
- Residual risks: `Quoted`'s link to `QUOTEPREFIX` and the openings' link to EXPERIENCE.md are pinned by values and a hand-run command, not by a CI read of the file. After `iris_doc_load`, slot A needed `iris_doc_compile` (`ck`) before the new parameters read correctly.
