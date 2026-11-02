---
title: "Story 40.1: Fix the persona's names, contracts and preset texts"
type: 'feature'
created: '2026-11-01'
status: 'draft'
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
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls`: one `Parameter` line appended after `RELEASE1` (the last parameter), plus one appended `///` line at the end of the class comment; no other line changes.
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

- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- read-only source. Preset table at about line 983-990 (under "The Persona card", section marker `[ADDED 2026-10-31, ...]` at line 965); persona approval card line 1000; catalog texts at Message Catalog › Personality notices, lines 884-892 (marker line 886); component list line 339 (marker `[ADDED 2026-10-31, as above]`).
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-29's "The personality epics" bullet (line 936, sub-bullets to line 947, ending "**Releases:**"); AD-33's cross-area table (lines 1267-1295; the `ApprovalOutcome` for kind `setting` to `SettingsOps` row is line 1295); REST surface (`GET`, `PUT /api/v1/persona` row, line 1420); AD-32's key rule (line 1022: keys are `<prefix>.<name>`, every prefix in one class).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:318` `ReadEntries` -- sibling pattern for reading a compiled JSON XData block (`%Dictionary.CompiledXData` then `%FromJSON`); private and Lane B's, so Persona copies the 5-line read.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- the shape of a class that holds only a JSON XData block (`[ MimeType = application/json ]`).
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- 12 string parameters plus `RELEASE1`; the mock regex `^Parameter ([A-Z0-9]+) = "([^"]*)";` reads every one but `RELEASE1`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls:27` `TestToolNames` -- asserts exactly 12 parameters besides `RELEASE1`: the shared surface this story changes.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls:248` `TestNoTemplates` -- the INSTRUCTIONS `{{` check (read-only here; its helpers are `[ Private ]`).
- `ci/mock/test/constants.test.mjs:33` `readAll()` -- reads `Agent/*.cls` (MOCKKEY; a class without one is skipped) and `Tools/Names.cls`; line 123's test requires every file read to match `WEB_INPUT_PATTERN` (`Agent/[^/]+\.cls` is covered).
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls`, `Msg/Command.cls` (common fields `Origin`, `IdempotencyKey`, `SessionRef`), `Data/Setting.cls` (`Key` MAXLEN 128, `Value` MAXLEN 1000) -- read-only, for the names recorded in the spine.
- `ci/units.sh:17` -- area `Agent` is in shard `lane-a` (CI piece `shards-2`), so a new `OcuTalon.Test.Agent.*` class joins CI with no list change.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- append, as the last sub-bullet of AD-29's personality-epics bullet (after "**Releases:**"), "**Epic 40's names**" with the marker, listing: the verbs `SetPersona` (`Preset`, `Language`, `Custom`; origin `web_user` only) and `ProposePersona` (the same fields plus the common `Origin`, `IdempotencyKey`, `SessionRef`; origin `tool` only), both routed by `CommandsIn` to `SettingsOps`; `Msg.Enum` `PERSONAPRESET` = `professional,starship,pirate,kindfriend,language,custom` and `APPROVALKIND` gaining `setting`; the keys `person.<SessionRef>.persona.preset|language|custom`; the catalog keys in `Catalog.Core` with their texts verbatim from EXPERIENCE.md › Message Catalog › Personality notices (`approval.persona`, slots `old` and `new`, and the two result keys AS AMENDED — see Auto Run Result); Lane A's `OcuTalon.Agent.Persona` and the tool name `propose_persona`. Append two rows to AD-33's cross-area table after line 1295: `OcuTalon.Agent.Persona` (`XData PRESETS`, `Presets()`, `Preset(id)`, `Block(sessionRef)`; AD-7), read by `Agent.Input` (40.3) and `SettingsOps` (40.6), Lane A, Story 40.1 (Block stub), Story 40.3; and `OcuTalon.Msg.Command.SetPersona`, `.ProposePersona` (AD-1), sent by the web layer and by `OcuTalon.Tools` (40.5) through `Commands.Submit`, handled by `SettingsOps`, Lane B, Story 40.2 -- AC 1.
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls` -- new class (no superclass): `XData PRESETS [ MimeType = application/json ]` (array of six objects, field order `id`, `name`, `description`, `text`, `bends`); `Presets() As %DynamicArray` (reads the compiled block each call); `Preset(id) As %DynamicObject` (`""` for an unknown id); `Block(sessionRef As %String) As %String` returning `""`. The class comment states the contract (AD-7, CON-2), never history -- AC 2.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- append `Parameter PROPOSEPERSONA = "propose_persona";` after `RELEASE1`, and one `///` line at the end of the class comment saying that names after `RELEASE1` belong to later releases and are not in it -- AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls` -- `TestToolNames`: 13 parameters besides `RELEASE1`, `RELEASE1` still lists exactly 12, `PROPOSEPERSONA` is `propose_persona` and is not in `RELEASE1`; update its header lines -- shared surface.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls` -- new test class: `TestPresets` (each matrix row against a test-held verbatim copy of the UX table, e.g. an `XData UX` block; exact key set per entry), `TestNoTemplates` (scanner sample, then every compiled `PRESETS` block of an `OcuTalon.*` class, at least one), `TestBlock` -- AC 2.
- `ci/mock/test/constants.test.mjs` -- append one `test('Story 40.1: ...')` asserting `readAll().toolNames` includes `propose_persona` -- AC 2 (Integration AC).

**Acceptance Criteria:**
- Given the spine after this story, when `grep -n` searches it for `Epic 40's names`, `PERSONAPRESET`, `person.<SessionRef>.persona`, `approval.persona` and `OcuTalon.Agent.Persona`, then each is found in the new AD-29 sub-bullet or the new AD-33 rows; the `setting` `ApprovalOutcome` row (line 1295) and the `/api/v1/persona` route row (line 1420) are present; and `git diff` of the spine shows added lines only.
- Given the compiled class, when `OcuTalon.Test.Agent.Persona` runs, then every matrix row from "All presets" to "Template token" holds.
- Given the CI mock's tool-name check, when `node --test ci/mock/test/constants.test.mjs` runs, then the appended test passes because the mock reads `propose_persona` from `Tools/Names.cls`, and every existing row-16 test still passes.
- Given AC 3, when the implement stage greps EXPERIENCE.md, then the Persona card (lines 980-998), the persona approval card (line 1000) and the persona notices (lines 890-892) sit under their `[ADDED 2026-10-31 ...]` markers (lines 965, 886, 339) -- verified at plan time; no text outside them is introduced.

## Spec Change Log

- 2026-11-02 (lead, unattended ruling `catalog_keys_ad32`, category=decide, Rule 5 apply-and-report "correcting a wrong name the AC cites"): the plan halted `intent gap` on AD-32 — `result.persona.applied` and `result.persona.stale` have two dots (the catalog key pattern allows one) and reuse the `result` prefix that lives in `OcuTalon.Msg.Catalog.Watch`. Amended, texts unchanged: epics.md Story 40.1 AC 1 and Story 40.6 now name `persona.applied` and `persona.stale` (a new `persona` prefix in `Catalog.Core`, Lane B's); EXPERIENCE.md › Message Catalog › Personality notices renamed the same two keys; `approval.persona` kept. Original wording: "the catalog keys `approval.persona`, `result.persona.applied` and `result.persona.stale` in `Catalog.Core`" (epics.md Story 40.1), "sends `result.persona.applied`" / "sends `result.persona.stale`" (Story 40.6), and the EXPERIENCE.md table cells `result.persona.applied` / `result.persona.stale`. Re-plan from `draft` with the new names.

## Review Triage Log

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

**Ledger inbox:** none.

## Verification

All `ci/iris.sh` calls run from the worktree root with `timeout: 600000` and the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=40 stage=implement' OCUTALON_RUN_TAG=e40s1i` (QA and review use their own stage name and tag). IRIS MCP calls name `server` `ocutalon-slot-c` and `namespace` `OCUTALON`, after `iris_server_info` confirms the slot; one `iris_execute_tests` call per message.

**Commands:**
- (loop) `iris_doc_load` the changed classes into slot C, then `iris_execute_tests` `OcuTalon.Test.Agent.Persona` -- expected: every assertion passes.
- (loop) `iris_execute_tests` `OcuTalon.Test.Agent.Constants` -- expected: passes with 13 names.
- (loop) `node --test ci/mock/test/constants.test.mjs` -- expected: all tests pass, the appended one included.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no `ad_id`, `ad_fields` or non-placeholder finding; `placeholder` findings only the 8 of the baseline plus the new entry's `{old}`/`{new}` slots.
- (once) `ci/iris.sh class OcuTalon.Test.Agent.Persona`, then `ci/iris.sh class OcuTalon.Test.Agent.Constants`, then `ci/iris.sh class OcuTalon.Test.Agent.Instructions`, one per call, then `ci/iris.sh teardown` -- expected: `CLASS ... passed` each.
- (once) `bash docker/tests/test-mock.sh` and `bash ci/checks.sh`, one per call -- expected: PASS (class rules, CI config).
- The rest of shard `lane-a` is left to CI (`shards-2`).

**Mutations (Rule 19):** Pirate text one word changed -> `TestPresets` red; `{{x}}` in Kind friend's text -> Persona `TestNoTemplates` red; `Block` returns "x" -> `TestBlock` red; `PROPOSEPERSONA` line removed -> the appended mock test red.

Shared surfaces: the tool-name count of `OcuTalon.Tools.Names` (asserted by `Test.Agent.Constants.TestToolNames`, updated here; `ci/mock/test/constants.test.mjs` asserts `>= 11` and distinctness; `Test.Agent.Instructions.TestToolsets` and `Test.Agent.Runners` list names explicitly and are unaffected); the classes of `src/ocutalon/cls/OcuTalon/Agent/` that the mock's `readAll()` reads. Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: AD-32 (catalog keys are `<prefix>.<name>`, and every prefix lives in one class). AC 1 of Story 40.1 (and Story 40.6's AC, EXPERIENCE.md › Message Catalog › Personality notices lines 891-892, and epic-40-context.md) names `result.persona.applied` and `result.persona.stale` as keys of `OcuTalon.Msg.Catalog.Core`. Both break AD-32's Rule as built: (1) a key has one dot, and `OcuTalon.Test.Msg.Catalog` `Problems()` refuses any key that does not match `^[a-z][A-Za-z]*\.[a-z][A-Za-z0-9]*$`; (2) the prefix `result` already lives in Lane A's `OcuTalon.Msg.Catalog.Watch` (seven resend-result keys), and the same test asserts that no prefix is in both classes. Recommended amendment (Rule 5, apply-and-report: a wrong name the ACs cite; every text unchanged): rename them `persona.applied` and `persona.stale` (a new prefix in `Catalog.Core`, whose producer `SettingsOps` is Lane B's) in epics.md Story 40.1 (line 7864) and Story 40.6 (lines 8036-8037) and EXPERIENCE.md lines 891-892; keep `approval.persona` (valid: one dot, an unused prefix); optionally cite the texts' place as EXPERIENCE.md › Message Catalog › Personality notices; then re-run the epic-context pre-warm, reset this spec to `draft` and re-dispatch. The rest of the plan above is complete.
