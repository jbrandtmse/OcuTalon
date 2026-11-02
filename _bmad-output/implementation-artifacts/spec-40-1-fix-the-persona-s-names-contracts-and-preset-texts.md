---
title: "Story 40.1: Fix the persona's names, contracts and preset texts"
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: '3be1c8d908d1c67f9271a9850d29ec30a06950c5'
baseline_commit: '3be1c8d908d1c67f9271a9850d29ec30a06950c5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Epic 40's two lanes build the persona in parallel, so its names (verbs, enumeration values, per-person keys, catalog keys, tool name, the Persona class) and its preset texts must be fixed once, in the spine and in code, before either lane builds on them.

**Approach:** Record Lane B's names as additive AD-29 / AD-33 entries in the spine; create Lane A's `OcuTalon.Agent.Persona` with `XData PRESETS` (the UX table, verbatim), read accessors and a `Block(sessionRef)` stub; append `propose_persona` to `OcuTalon.Tools.Names`; extend the `{{` check to `PRESETS` in a new test class.

## Boundaries & Constraints

**Always:**
- Preset ids, names, descriptions, texts and styles come verbatim from EXPERIENCE.md › Later Steps › Personality (the preset table, about line 983); no invented text (UX-DR117, CON-2).
- ObjectScript and JSON-in-XData source is ASCII; any non-ASCII character is an escape (Rule 14). The preset texts are ASCII today.
- Spine edits are additive lines only: new sub-bullets and new table rows under the 2026-10-31 amendments, each with an `[ADDED 2026-11-01, Story 40.1 ...]` marker; no AD's Rule text changes, and the frontmatter (`updated:`) is not touched (Epic 30 edits it).
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls`: one self-contained block appended after `RELEASE1` (the last parameter): a `///` line stating that the name is not a release-1 tool and `RELEASE1` does not list it, then the one `Parameter` line; no other line changes (the class comment at the top stays as it is).
- `ci/mock/test/constants.test.mjs`: one self-contained `test(...)` block appended at the end; existing tests unchanged.

**Never:**
- Edit `Agent/Chat.cls`, `Agent/Triage.cls`, `Agent/Input.cls` or `Test/Agent/Instructions.cls` (contended with Epics 11 and 30; Input is Story 40.3's).
- Create `Msg.Enum` values, `Msg.Command.*` verbs, `Catalog.Core` keys, `SettingsOps`/`CommandsIn` code, a toolset or any route (Lane B's Story 40.2 and Lane A's Story 40.5 build them).
- Add `propose_persona` to `RELEASE1` (it is not a release-1 tool).
- Make `Block()` read settings or render anything (Story 40.3).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| All presets | `##class(OcuTalon.Agent.Persona).Presets()` | a `%DynamicArray` of 6 objects in `PERSONAPRESET` order `professional,starship,pirate,kindfriend,language,custom`, each with exactly `id`, `name`, `description`, `text`, `bends` | No error expected |
| One preset | `Preset("pirate")` | the pirate object; `bends` 1; `text` the UX text verbatim | No error expected |
| Unknown preset | `Preset("zorblish")`, `Preset("")` | `""` | no throw |
| No-text presets | `Preset(id).text` for `professional`, `language`, `custom` | `""` (no block / code-written language line / the person's own text) | No error expected |
| Bends | `bends` per id | true: `starship`, `pirate`, `kindfriend`, `custom`; false: `professional`, `language` | No error expected |
| Block stub | `Block("")`, `Block("AbCdEf0123456789xyzABC")` | `""` | no throw, no read or write |
| Template token | compiled `XData PRESETS` of every `OcuTalon.*` class | no `{{`; no field holds `@{` or a control character other than a line feed | the scanner first flags a sample with `{{` |
| Mock reads the name | `readAll().toolNames` in `ci/mock/test/constants.test.mjs` | includes `propose_persona` | No error expected |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- read-only source. Personality section marker line 965; "The Persona card" line 980; preset table header line 985, rows 987-992 (columns Id, Name on the card, Description, Style, Text in the block; the starship and pirate texts hold straight double quotes, which JSON escapes as `\"`); persona approval card line 1000; Message Catalog › Personality notices lines 884-893 (marker line 886; `approval.persona` 890, `persona.applied` 891, `persona.stale` 892); component list line 339.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-29's "The personality epics" bullet at line 936, its last sub-bullet "**Releases:**" at line 947 (4-space indent `    - `); the cross-area table under "### Ownership tables" (heading line 1236), lines 1268-1295, whose last row (1295) is the `setting` kind's `ApprovalOutcome` to `SettingsOps`; REST surface row `GET`, `PUT /api/v1/persona` at line 1420; AD-7's persona block 245-268 (PRESETS and `bends`, line 266); AD-22's as-built count "the 12 built-in tool names" at line 743 (read-only here, see Design Notes).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:318` `ReadEntries` -- the sibling compiled-JSON-XData read (`%Dictionary.CompiledXData.%OpenId(class_"||Entries")`, then `%FromJSON(xdata.Data)`).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:9` -- shape of a JSON XData block (`XData Entries [ MimeType = application/json ]`).
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- 12 string parameters (lines 6-28), `RELEASE1` at line 31, closing `}` at 33. The mock reads every `^Parameter ([A-Z0-9]+) = "([^"]*)";` line but `RELEASE1`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls:27-52` `TestToolNames` -- asserts 12 parameters besides `RELEASE1` (line 41) and a 12-name `RELEASE1` (line 44); header lines 6 and 27 say "twelve"/"12". The shared surface this story changes. No in-flight epic branch edits this file (checked at plan time against OCT-epic11, -30, -31).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls:248-282` `TestNoTemplates` -- the INSTRUCTIONS `{{` check (read-only). Its call scanner also fails any `OcuTalon.*` class that names the AI Hub template class on a code line, so neither new class names it outside a comment.
- `ci/mock/test/constants.test.mjs:34-59` `readAll()` -- reads every `Agent/*.cls` (a class without `MOCKKEY`, such as Persona, is skipped) and `Tools/Names.cls`; the file ends at line 133. Epic 11 edits lines 72-85; the append at the end does not touch them.
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:27` (`APPROVALKIND = "fix,tool_call"`), `Msg/Command.cls` (common `Origin`, `IdempotencyKey`, `SessionRef` MAXLEN 22), `Data/Setting.cls` (`Key` MAXLEN 128, `Value` MAXLEN 1000) -- read-only, for the names recorded in the spine.
- `ci/units.sh:17` -- area `Agent` is in shard `lane-a` (CI piece `shards-2`), so a new `OcuTalon.Test.Agent.*` class joins CI with no list change. `Test/Install/ProductionRules.cls:145` lists `OcuTalon.Agent.` as Lane A's.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- (1) insert after line 947 ("**Releases:**"), as the last sub-bullet of AD-29's personality-epics bullet, one line `    - **Epic 40's names** [ADDED 2026-11-01, Story 40.1, AD-29's contract-naming story]: ...` listing: the verbs `SetPersona` (`Preset`, `Language`, `Custom`; origin `web_user` only) and `ProposePersona` (the same fields plus the common `Origin`, `IdempotencyKey`, `SessionRef`; origin `tool` only), both routed by `CommandsIn` to `SettingsOps` (Lane B, Story 40.2); `Msg.Enum` `PERSONAPRESET` = `professional,starship,pirate,kindfriend,language,custom` and `APPROVALKIND` gaining `setting`; the per-person keys `person.<SessionRef>.persona.preset|language|custom` in `OcuTalon.Data.Setting`; the catalog keys in `Catalog.Core` (prefixes `approval` and `persona`, AD-32) with their texts verbatim from EXPERIENCE.md › Message Catalog › Personality notices: `approval.persona` "OcuTalon suggests a new persona for you. Now: {old}. Proposed: {new}. Nothing changes unless you approve.", `persona.applied` "Persona updated. It applies from your next message.", `persona.stale` "Your persona changed after this was suggested. Nothing was changed."; Lane A's `OcuTalon.Agent.Persona` (AD-7) and the tool name `propose_persona` (`OcuTalon.Tools.Names` `PROPOSEPERSONA`, not in `RELEASE1`). (2) Insert after line 1295 two rows of the cross-area table, each ending `[ADDED 2026-11-01, Story 40.1]`: `OcuTalon.Agent.Persona`: `XData PRESETS`, `Presets()`, `Preset(id)`, `Block(sessionRef)` (AD-7), read by `Agent.Input` (40.3) and `SettingsOps` (40.6) | A | Story 40.1 (`Block` stub), Story 40.3; and `OcuTalon.Msg.Command.SetPersona`, `.ProposePersona` (AD-1), sent by the web layer and by `OcuTalon.Tools` (40.5) through `Commands.Submit`, handled by `SettingsOps` | B | Story 40.2. Nothing else in the file changes -- AC 1.
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls` -- new class, no superclass: `XData PRESETS [ MimeType = application/json ]` (a JSON array of six objects in id order, field order `id`, `name`, `description`, `text`, `bends`; the closing `}` of the XData at column 0, every object line indented); `ClassMethod Presets() As %DynamicArray` (reads the compiled block on each call); `ClassMethod Preset(id As %String) As %DynamicObject` (`""` for an unknown or empty id); `ClassMethod Block(sessionRef As %String) As %String` returning `""`. The class comment states the contract (AD-7, CON-2: product constants, data in a block, never instructions), never history -- AC 2.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- after line 31 (`RELEASE1`), append a blank line, `/// The persona proposal tool of the personality epics (AD-7); not a release-1 tool, so RELEASE1 does not list it.` and `Parameter PROPOSEPERSONA = "propose_persona";`, before the closing `}` -- AC 3.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls` -- `TestToolNames`: 13 parameters besides `RELEASE1`, `RELEASE1` still lists exactly 12, `PROPOSEPERSONA` is `propose_persona` and is not in `RELEASE1`; header lines 6 and 27 say so -- shared surface.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls` -- new `%UnitTest.TestCase`: `TestPresets` (matrix rows All presets to Bends, against a test-held copy of the UX table in an XData named `UX`, never `PRESETS`; exact key set per entry), `TestNoTemplates` (the scanner first flags a `{{` sample, an `@{` sample and a tab, and passes a clean text; then every compiled `PRESETS` block of an `OcuTalon.*` class, at least one, field by field), `TestBlock` -- AC 2.
- `ci/mock/test/constants.test.mjs` -- append one `test('Story 40.1: the mock reads propose_persona from OcuTalon.Tools.Names', ...)` asserting `readAll().toolNames` includes `propose_persona` -- AC 3 (Integration AC).

**Acceptance Criteria:**
1. Given the spine after this story, when `grep -n` searches it for `Epic 40's names`, `PERSONAPRESET`, `person.<SessionRef>.persona`, `approval.persona`, `persona.applied`, `persona.stale` and `OcuTalon.Agent.Persona`, then each is found in the new AD-29 sub-bullet or the new AD-33 rows; no line of the spine holds a superseded `result`-prefixed persona key (the grep in Verification); the `setting` `ApprovalOutcome` row and the `/api/v1/persona` route row are present; `git diff --numstat` of the spine shows 0 deleted lines; and the spine lint adds only the two `placeholder`/`low` findings `{old}` and `{new}` to the baseline (Verification).
2. Given the compiled class, when `OcuTalon.Test.Agent.Persona` runs, then every matrix row from "All presets" to "Template token" holds; and the UX comparison command (Verification) finds every PRESETS entry's id, name, description, style and text as one row of EXPERIENCE.md's preset table.
3. Given the CI mock's tool-name check, when `node --test ci/mock/test/constants.test.mjs` runs, then the appended test passes because the mock reads `propose_persona` from `Tools/Names.cls`, and every existing row-16 test still passes; and `OcuTalon.Test.Agent.Constants` passes with 13 names, `RELEASE1` still 12.
4. Given the UX additions, when the implement stage greps EXPERIENCE.md, then the Persona card (lines 980-998), the persona approval card (line 1000) and the persona notices (lines 890-892) sit under their `[ADDED 2026-10-31 ...]` markers (lines 965, 886, 339) -- verified at plan time; no text outside them is introduced.

## Spec Change Log

- 2026-11-02 (lead, unattended ruling `catalog_keys_ad32`, category=decide, Rule 5 apply-and-report "correcting a wrong name the AC cites"): the plan halted `intent gap` on AD-32 — `result.persona.applied` and `result.persona.stale` have two dots (the catalog key pattern allows one) and reuse the `result` prefix that lives in `OcuTalon.Msg.Catalog.Watch`. Amended, texts unchanged: epics.md Story 40.1 AC 1 and Story 40.6 now name `persona.applied` and `persona.stale` (a new `persona` prefix in `Catalog.Core`, Lane B's); EXPERIENCE.md › Message Catalog › Personality notices renamed the same two keys; `approval.persona` kept. Original wording: "the catalog keys `approval.persona`, `result.persona.applied` and `result.persona.stale` in `Catalog.Core`" (epics.md Story 40.1), "sends `result.persona.applied`" / "sends `result.persona.stale`" (Story 40.6), and the EXPERIENCE.md table cells `result.persona.applied` / `result.persona.stale`. Re-plan from `draft` with the new names.
- 2026-11-01 (plan, re-plan iteration 2): the intent contract's `Tools/Names.cls` bullet narrowed to fit the dispatch's binding constraint ("a one-name append only"; any change to a contended file other than one block appended at its end is not allowed). It read: "one `Parameter` line appended after `RELEASE1` (the last parameter), plus one appended `///` line at the end of the class comment; no other line changes." The `///` line now sits in the appended block, above the parameter, and the class comment at the top is untouched. Avoids an edit at the top of a contended file. KEEP: everything else of the predecessor's plan.

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 23 findings - high 0, medium 1, low 19, false 3, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: the spine bullet names `Msg.Enum` `APPROVALKIND` without saying that `OcuTalon.Bridge.Msg.Enum` has its own `APPROVALKIND` (validated in `Bridge/Approval.cls`, pinned in `Test/Msg/Contracts.cls`) - verified: both enums exist; patched in the same added line (`OcuTalon.Msg.Enum` qualified, "in both `OcuTalon.Msg.Enum` and `OcuTalon.Bridge.Msg.Enum`"); numstat stays 3/0, lint unchanged.
  - `[low]` `[reject]` Blind: `Tools/Names.cls` class comment says release-1 tools only - the spec forbids any change to the top comment of this contended file; the appended `///` line states the exception.
  - `[low]` `[reject]` Blind: the persona test compares two repo copies, not EXPERIENCE.md - spec-defined design (test-held `UX` copy); the (once) UX comparison command reads EXPERIENCE.md itself and was run green and red-on-mutation.
  - `[low]` `[reject]` Blind: `TestNoTemplates` skips non-string values and assumes object entries - no PRESETS value is nested or non-string today; a malformed block fails the test run loudly.
  - `[low]` `[patch]` Blind, verification-gap, edge-case: the `TestBlock` header claims `Block()` "reads nothing" but only the return value is asserted - header reworded to what the test asserts.
  - `[low]` `[reject]` Blind: `Presets()` re-parses on each call, and its throw is undocumented - no caller exists until 40.3; caching is premature and the compiled class always has the block.
  - `[low]` `[reject]` Edge: nested values unscanned - same claim as the Blind row on `TestNoTemplates`; theoretical.
  - `[low]` `[reject]` Edge: non-string values not scanned - same root cause as above.
  - `[low]` `[reject]` Edge: `Preset(id)` returning "" then `.bends` on it aborts the test method - the abort is a red test either way.
  - `[false]` `[reject]` Edge: `Preset("Pirate")` / padded ids give "" - the matrix says unknown id gives ""; ids are lower-case constants.
  - `[false]` `[reject]` Edge: duplicate ids make later entries unreachable - `TestPresets` pins the six ids in exact order against the UX copy, so a duplicate fails.
  - `[low]` `[reject]` Edge: `Block` has no input validation - the stub is fixed by the spec; Story 40.3 owns its behaviour.
  - `[false]` `[reject]` Edge: the spine line's `<SessionRef>` may add a lint finding - lint was run: only the expected `placeholder low` lines, `{new}` and `{old}` included.
  - `[low]` `[reject]` Verification-gap: AC 1 and AC 4 have no mutation line - the spec states AC 1 is a document check (grep, numstat, lint) that fails on absence; AC 4 was verified at plan time; fix would edit this build's spec.
  - `[low]` `[reject]` Verification-gap: PRESETS vs EXPERIENCE.md is checked only by a hand-run command - the epic constraint allows exactly one appended mock test, so a second would break the constraint; the command is a (once) Verification line and was run.
  - `[low]` `[reject]` Verification-gap: the mock test only checks the regex read of `Names.cls` - it is the story's Integration AC; the runtime pin is `TestToolNames`.
  - `[low]` `[reject]` Verification-gap (other): `TestToolNames` hard-codes 13 - the old test hard-coded 12; same maintenance cost.
  - `[low]` `[reject]` Intent: a parity check against a copy, not the document (divergence note) - same as the spec-defined design above.
  - `[low]` `[reject]` Intent: `Test/Agent/Constants.cls` edited beyond the intent's list - the spec's Code Map and Tasks list this edit (shared surface).
  - `[low]` `[reject]` Intent: ASCII is not asserted by a test - Rule 14 is source discipline; the diff was checked for non-ASCII bytes (none).
  - `[low]` `[reject]` Intent: `HasBadToken` is a parallel scanner rather than an extension of the old one - spec Design Notes record the reason (private, contended file).
  - `[low]` `[reject]` Intent: the text and bends values for professional/language/custom are interpretations of the table - recorded under "Decided in-stage".
  - `[low]` `[reject]` Intent: `TestNoTemplates` depends on compiled classes in the namespace - same environment assumption as the class under test.

## Design Notes

**Architecture decisions:** AD-7 (persona block; PRESETS constants; the `{{` check reads PRESETS), AD-1 (verbs and origins), AD-11 (`setting` kind), AD-19 (per-person keys), AD-22 (tool names, the mock), AD-29 (contract-naming story; names), AD-32 (catalog keys `<prefix>.<name>`, one class per prefix), AD-33 (ownership-table rows).

**Integration ACs:** in-story consumers: the CI mock's tool-name check (`ci/mock/test/constants.test.mjs`) reads `propose_persona` from source; `OcuTalon.Test.Agent.Persona` reads the compiled `PRESETS` through `Presets()`/`Preset(id)`. `Block()` has no consumer in this story; the first will be Story 40.3.

**Consumed-by:** 40.2 (the spine names: verbs, enumeration, keys, catalog keys); 40.3 (`Block`, `Preset(id).text` and `.bends`); 40.4 (preset ids, names, descriptions on the card); 40.5 (`PROPOSEPERSONA`); 40.6 (`Preset(id).name` for the request's "Now"/"Proposed"); 40.7 (preset ids for the sweep). **Consumes:** none.

**Extend, don't copy:** `Presets()` copies `Msg.Catalog.ReadEntries`'s 5-line compiled-XData read, because that method is private in a Lane B class. The test's `{{` scanner is a one-line copy of `Test.Agent.Instructions.HasTemplateToken` (private, in a contended file); a new class is the dispatch's preferred route.

**Decided in-stage:**
- Names are the table's "Name on the card" column verbatim, so `professional` is "Professional (default)" and `custom` is "Your own words (not on the online demo)". Story 40.6 decides whether "Now:"/"Proposed:" drops the parenthetical (a text it must have accepted).
- `text` is `""` for `professional` (no block), `language` (AD-7's code-written line, rendered by `Block` in 40.3) and `custom` (the person's text); all six entries carry all five fields.
- `custom` has `bends` true (the table's "may bend"; AD-7 gives the style line to a custom persona); `professional` false.
- The `{{` check also refuses `@{` and control characters in PRESETS, the same rule AD-19 applies to a person's values.
- `Test/Agent/Constants.cls` is edited mid-file: no in-flight epic branch (OCT-epic11, -30, -31) changes it (checked at plan time with `git diff $(git merge-base HEAD <branch>) <branch>`).
- The catalog texts' place is EXPERIENCE.md › Message Catalog › Personality notices, to which Later Steps › Personality points ("The persona approval's channel texts are in the Message Catalog").
- The spine sub-bullet quotes the three catalog texts verbatim, so `{old}` and `{new}` add two low `placeholder` lint findings, the same kind as the baseline's eight catalog slots; no other kind is added.
- AD-22's as-built line (spine line 743, "the 12 built-in tool names are defined once in `OcuTalon.Tools.Names`") is left unchanged: it counts the built-in tools, which `RELEASE1` lists (still 12), and `propose_persona` has no tool until Story 40.5. Changing that count is outside this story's additive rows (U-199's precedent: the as-built count is corrected at the merge gate).
- The `Tools/Names.cls` comment line sits in the appended block (Spec Change Log, 2026-11-01).

**Ledger inbox:** none.

## Verification

All `ci/iris.sh` calls run from the worktree root with `timeout: 600000`, one per call, each prefixed with the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=40 stage=implement' OCUTALON_RUN_TAG=e40s1i` (QA and review use their own stage name and tag). IRIS MCP calls name `server` `ocutalon-slot-c` and `namespace` `OCUTALON`, after `iris_server_info` confirms the slot (build 154, port 1992); one `iris_execute_tests` call per message.

**Commands:**
- (loop) `iris_doc_load` the changed and new classes into slot C, then `iris_execute_tests` `OcuTalon.Test.Agent.Persona` -- expected: every assertion passes.
- (loop) `iris_execute_tests` `OcuTalon.Test.Agent.Constants` -- expected: passes with 13 names, `RELEASE1` 12.
- (loop) `node --test ci/mock/test/constants.test.mjs` -- expected: all tests pass, the appended one included.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 | jq -r '.findings[] | "\(.category) \(.severity) \(.detail | sub("possible unfilled template token \\(verify\\): "; ""))"' | sort | uniq -c` -- expected: exactly these lines, every finding `placeholder low` (baseline at plan time, commit 159ed8e2, was the same without the `{new}` and `{old}` lines; `ok` stays false because of the baseline): `1 '{day}'`, `1 '{entry}'`, `1 '{finding}'`, `1 '{n}'`, `1 '{new}'`, `1 '{old}'`, `1 '{reason}'`, `2 '{time}'`, `1 '{what happened}'`.
- (once) `git diff --numstat -- _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- expected: `3	0	...` (one sub-bullet, two rows; 0 deleted); and `grep -c 'result\.persona' <spine>` -- expected `0`.
- (once) UX comparison: `node -e 'const fs=require("fs");const [c,u]=process.argv.slice(1).map(f=>fs.readFileSync(f,"utf8"));const m=/^XData PRESETS \[ MimeType = application\/json \]\n\{\n([\s\S]*?)\n\}$/m.exec(c);const p=JSON.parse(m[1]);if(p.map(x=>x.id).join()!=="professional,starship,pirate,kindfriend,language,custom")throw new Error("ids");for(const x of p){const row="| `"+x.id+"` | "+x.name+" | "+x.description+" | "+(x.bends?"may bend":"keeps the rules")+" | "+(x.text?x.text+" |":"");if(!u.includes(row))throw new Error("not in EXPERIENCE.md: "+x.id)}console.log("PRESETS match EXPERIENCE.md: "+p.length)' src/ocutalon/cls/OcuTalon/Agent/Persona.cls _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- expected: `PRESETS match EXPERIENCE.md: 6` (proved at plan time on a draft of the class, and red on a one-word change of the pirate text).
- (once) `ci/iris.sh class OcuTalon.Test.Agent.Persona`, then `ci/iris.sh class OcuTalon.Test.Agent.Constants`, then `ci/iris.sh class OcuTalon.Test.Agent.Instructions`, one per call, then `ci/iris.sh teardown` -- expected: `CLASS ... passed` each (fresh stacks).
- (once) `bash docker/tests/test-mock.sh`, then `bash ci/checks.sh`, one per call -- expected: PASS (mock tests, class rules, CI config).
- The rest of shard `lane-a` is left to CI (`shards-2`).

**Mutations (Rule 19):** AC 2: one word of the pirate text changed -> `TestPresets` red and the UX comparison red; `{{x}}` in Kind friend's text -> Persona `TestNoTemplates` red; `Block` returns "x" -> `TestBlock` red. AC 3: the `PROPOSEPERSONA` line removed -> the appended mock test red; `PROPOSEPERSONA` added to `RELEASE1` -> `TestToolNames` red. AC 1 is a document check (grep, numstat, lint), no mutation.

Shared surfaces: the tool-name count of `OcuTalon.Tools.Names` (asserted by `Test.Agent.Constants.TestToolNames`, updated here; `ci/mock/test/constants.test.mjs` asserts `>= 11` and distinctness; `Test.Agent.Instructions.TestToolsets`, `Test.Agent.Runners`, `Test.Watch.Tools`, `Test.Tools.Reminders` and `Test.Bridge.CodeRules` name parameters explicitly and are unaffected); the classes of `src/ocutalon/cls/OcuTalon/Agent/` that the mock's `readAll()` reads; the compiled XData blocks named `PRESETS` that the new `TestNoTemplates` scans. Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Epic 40's names are fixed in the spine (one AD-29 sub-bullet, two cross-area rows; 3 lines added, 0 deleted) and in code: `OcuTalon.Agent.Persona` with `XData PRESETS` (the six UX presets), `Presets()`, `Preset(id)` and the `Block()` stub; `PROPOSEPERSONA` appended to `OcuTalon.Tools.Names` (not in `RELEASE1`); the new test class `OcuTalon.Test.Agent.Persona`; `TestToolNames` updated to 13 names (`RELEASE1` still 12); one mock test appended.

**Files changed.**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the "Epic 40's names" sub-bullet and two ownership rows.
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls`: new; presets, accessors, `Block` stub.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls`: appended `PROPOSEPERSONA` block.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls`: new; `TestPresets`, `TestNoTemplates`, `TestBlock`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls`: `TestToolNames` for 13 names.
- `ci/mock/test/constants.test.mjs`: one appended test.

**Review.** 23 findings from four layers: 2 patched (the `Msg.Enum` qualification in the spine bullet, a medium, and the `TestBlock` header wording, a low), 0 deferred, 21 rejected with reasons in the triage log. No high.

**Follow-up review recommended:** false (no high patched, one medium patched).

**Verification.** On slot C (`ocutalon-slot-c`, OCUTALON): `OcuTalon.Test.Agent.Persona` 3/3 and `OcuTalon.Test.Agent.Constants` 3/3; `node --test ci/mock/test/constants.test.mjs` 6/6; spine lint shows only the expected `placeholder low` lines (`{new}`, `{old}` added); spine numstat `3 0`; `grep -c 'result\.persona'` 0; the UX comparison prints `PRESETS match EXPERIENCE.md: 6`. Fresh throwaway stacks: `ci/iris.sh class` passed for Persona, Constants and Instructions; `ci/iris.sh teardown` left nothing; `docker/tests/test-mock.sh` 119/119; `bash ci/checks.sh` all scripts passed. Mutations observed red and reverted (tree matched the backups): `PROPOSEPERSONA` line removed (mock test red), one word of the pirate text changed (UX comparison red), `Block` returning "x" (`TestBlock` red), `{{x}}` in the kind friend text (`TestNoTemplates` and `TestPresets` red). Not run: `PROPOSEPERSONA` added to `RELEASE1`.

**Residual risks.** Story 40.2 must add `setting` to both `APPROVALKIND` enums and update the `Test.Msg.Contracts` pins (named in the spine bullet). AD-22's as-built count of 12 tool names is left for the merge gate (Design Notes).
