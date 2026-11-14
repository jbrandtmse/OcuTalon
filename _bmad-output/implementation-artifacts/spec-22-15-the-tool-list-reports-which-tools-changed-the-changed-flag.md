---
title: "Story 22.15: The tool list reports which tools changed (the `changed` flag)"
type: 'feature'
created: '2026-11-14'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-4-add-remove-and-classify-mcp-servers-and-tools-in-settings.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `McpOps.Tools(server)` gives each tool `name`, `classification` and `status` only. A tool that McpOps made Unclassified after its fingerprint changed (`ClearChanged` -> `ClearRow`) looks the same as a new tool, so Settings can't show the changed-tool banner (Story 21.9).

**Approach:** Add one stored boolean, `Mcp.ToolClassification.Changed`. `ClearRow` sets it, `Classify` resets it, and `Tools(server)` reports it as `changed`, a JSON boolean. Lane C does this in Lane A's files under the Contest Planner's Lane A exception V1 (rulings file, "~22:40Z Nov 14"), limited to the `changed` member, ClearRow/ClearChanged, Classify/ClassifyTool and their tests.

## Boundaries & Constraints

**Always:**
- `Property Changed As %Boolean [ InitialExpression = 0 ];` on `OcuTalon.Mcp.ToolClassification`, storage `<Value name="N">Changed</Value>` (the next free slot) in the same globals. There is no migration.
- A row stored before the upgrade has `Changed` = "", and `Tools(server)` reads it as `changed: false`. The member is always a JSON boolean (`%Set("changed", value, "boolean")`), never "" or null.
- `changed` is true only when `Changed` is 1 AND the classification is `unclassified`.
- `ClearRow`, in its branch that clears a CLASSIFIED tool, sets `Changed = 1` in the same save. A row that is already unclassified and only takes a new fingerprint keeps its `Changed`.
- `Classify` (ClassifyTool, any of the three words) sets `Changed = 0` with its save. Its audit-failure undo puts the previous `Changed` back with the previous classification.
- A new row (`KeepRow`) starts at 0, the initial value. The refused branch is unchanged.
- AD-21 gets the ruled S1 text word for word (below), with its marker.

**Never:** any other change to `Mcp/**` or `Bridge/**`; new public text; a change to Settings' web code (that is Story 21.9).

## I/O & Edge-Case Matrix

| Scenario | State | Expected |
|----------|-------|----------|
| Cleared classified tool | read-only row, new fingerprint at attach | `Changed` 1, classification unclassified, `Tools` gives `changed: true` |
| Unclassified row, new fingerprint | unclassified row, Changed 0 or 1 | fingerprint updated, `Changed` unchanged |
| Admin classifies | Changed 1 | `Changed` 0; `changed: false` |
| Classify audit fails | Changed 1 | the undo restores the classification AND `Changed` 1 |
| Pre-upgrade row | Changed "" | `changed: false` (JSON boolean) |
| New tool | KeepRow | `Changed` 0; `changed: false` |
| Changed 1 but classified | data drift | `changed: false` |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls`: the class doc lists the properties (:5-8); `Fingerprint` :29, `ChangedAt` :32 and the storage `<Value>` list.
- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls`:
  - `Tools(server)`: its SELECT and `tools.%Push`, and the doc above it;
  - `Classify` and its undo;
  - `ClearChanged`/`ClearRow` (the classified branch);
  - `KeepRow`;
  - the class doc's Tools and ClearChanged bullets.
  - Read the current line numbers on this branch.
- Tests (Lane A, inside V1):
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls`: `TestClearChanged`, `TestClassify`;
  - `Test/Mcp/Tools.cls`: `TestTools`;
  - and `Test/Mcp/Classification.cls` if it pins the row's properties.
- Consumers that list members: `Core/SettingsOps.cls` `ListMcp` passes `Tools`' elements through. Check whether it copies by name; 21.9 adds `changed` there, not this story. `Test/Core/SettingsMcp.cls` `TestList` counts members; update it only if this story's change alone makes it fail.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, AD-21: the `Tools(server)` bullet ("each element has `name`, `classification` ... and `status` ...") and the "Fingerprints at attach (S3)" bullet ("clears a classified tool whose fingerprint changed (`McpOps.ClearChanged`, audited), and sends the admin notices").

## Tasks & Acceptance

**Execution:**
- [ ] `ToolClassification.cls`: add `Changed` (%Boolean, InitialExpression 0) with its doc line and storage value.
- [ ] `Ops.cls`:
  - `ClearRow` sets `Changed = 1` in the classified branch only.
  - `Classify` sets `Changed = 0` and its undo restores it.
  - `Tools` selects `Changed` and pushes `changed` as a JSON boolean: `(+changed = 1) && (classification = "unclassified")`, so "" reads false.
  - Update the docs.
- [ ] Tests, each with a `mutation:` line (applied, red, reverted byte-identical):
  - `TestClearChanged`: 1 after clearing a classified row; an unclassified row's update keeps its value.
  - `TestClassify`: reset to 0 for each of the three words; the audit-failure undo restores 1.
  - `TestTools`: `changed` true only for a cleared unclassified row, as JSON `true`. A row whose stored `Changed` is "" (set the global node directly, as a pre-upgrade row) gives `changed` false as JSON `false`, never "" or null. Mutation: push the raw `Changed` value -> red.
  - A new tool (`KeepRow`) is 0.
- [ ] Spine AD-21: replace the two passages with S1, word for word:
  - `Tools(server)` bullet: "...; each element has `name`, `classification` (`unclassified`, `read-only` or `risky`), `status` (`available`, `unavailable` or `refused`) and `changed` (a JSON boolean, true while `McpOps.ClearChanged` has made the tool unclassified after a fingerprint change and no admin has classified it since; stored as `Mcp.ToolClassification.Changed`, a %Boolean with initial value 0 and no migration). The built version (Story 22.2): ..."
  - Fingerprints at attach: "...clears a classified tool whose fingerprint changed (`McpOps.ClearChanged`, audited, and marked `Changed` until an admin classifies it again with `ClassifyTool`), and sends the admin notices..."
  - Append to each bullet: `[AMENDED 2026-11-14, Story 21.9 and the Epic 22 flag story, Contest Planner rulings V1-V3]`.
  - Run `lint_spine.py` (baseline 10 low).

**Acceptance Criteria:** the four of epics.md Story 22.15.

## Spec Change Log

- 2026-11-14 (lead): chartered by the Contest Planner (~22:40Z), with the contract from Story 21.9's spec (V1-V3) and the ~05:30Z condition that a row with Changed = "" reads as false.

## Design Notes

**Contended file:** Lane D's 22.11 also edits `Mcp/Ops.cls`. Whoever pushes second integrates forward; a contradiction is a STOP.

**Public text:** none.

## Verification

Lane C: `OCUTALON_LOCK_DIR=<worktree parent>/.coordination/locks/lane-c`, `OCUTALON_TEST_WEB_PORT=52803`, warm tag `e22s15iw`, fresh tag `e22s15i`.
- `ci/iris.sh class OcuTalon.Test.Mcp.Ops`, `OcuTalon.Test.Mcp.Tools`, `OcuTalon.Test.Mcp.Classification`, `OcuTalon.Test.Mcp.Attach:TestRemovedServer`, `OcuTalon.Test.Core.SettingsMcp`, `OcuTalon.Test.Core.CommandsStep4`, `OcuTalon.Test.Msg.Contracts` and `OcuTalon.Test.Data.Tables` (or the storage pin that lists stored properties), one per call, warm -> pass.
- A fresh check of `Test.Mcp.Ops` and `Test.Mcp.Tools`, forward and reverse.
- `bash docker/tests/test-storage.sh` if it exists, plus `test-class-rules.sh` and `test-boundaries.sh` -> pass.
- `lint_spine.py` -> 10 low.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
