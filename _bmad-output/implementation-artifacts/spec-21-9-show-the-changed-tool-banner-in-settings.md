---
title: 'Story 21.9: Show the changed-tool banner in Settings'
type: 'feature'
created: '2026-11-13'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-4-add-remove-and-classify-mcp-servers-and-tools-in-settings.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When an MCP server changes a classified tool's description or inputs, McpOps (`ClearChanged`) makes the tool Unclassified and sends each admin the `mcp.toolChanged` chat notice. Settings > Tools and MCP servers then shows the tool as one more Unclassified row, the same as a newly discovered tool, so the admin cannot tell which tool changed. The banner the UX accepted (`settings.toolChangedBanner`) is never shown.

**Approach:** Lane A's `Mcp.Ops.Tools(server)` says which unclassified tools McpOps cleared after a fingerprint change (a `changed` member; the cross-lane ask, Veto V1-V3, which 21.9 does not build). 21.9 passes it through `ListMcpServers` and the GET, and the section shows one warning banner per changed tool, in the accepted wording, above the tools table. A classification save clears the flag, and the banner goes.

## Boundaries & Constraints

**Always:**
- Lane B only, in 21.4's section and route (Rules 1/2): `SettingsOps.ListMcp`, `api-types.ts`, `mcp-view.ts`, `mcp-section.ts` and their tests. No new route, command, service, catalog key or text.
- The banner text is the Core catalog's `settings.toolChangedBanner`, word for word: "{tool} on {server} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below." (EXPERIENCE "Settings and requests (step 4)" :1009; `Msg/Catalog/Core.cls` :768; Story 35.2's proposal, accepted). The page decides nothing (AD-12). A banner shows only for a tool whose GET row has `changed` exactly `true`; a missing or false member means no banner.
- All new web code goes in the lazy MCP chunk (`mcp-view.ts`, `mcp-section.ts`). The initial bundle is 998.08 kB of its 1 MB cap (DW-1282) and does not grow by one byte: no import of the MCP files from the page, and no new key in the generated `msg/catalog.ts` `PAGE_TEXTS`.
- Online demo: the section shows only T1 (21.4), so the banner never shows there and no MCP endpoint runs.
- Every test added or changed creates and removes its own `zz` servers, tool rows and `^||ZzOps` nodes, and passes on a fresh environment, in either order. No real MCP server: fixture rows and `Test.Mcp.Mock`-free Lane A probes only.

**Never:**
- Any Lane A edit (`Mcp/**`, `Test/Mcp/**`, `src/bridge/**`): the flag is Epic 22's (V1). 21.9's implement does not start until it is on this branch (Task 0 (a)).
- A banner derived from `classification`, `ChangedAt` or the audit log; a close button, action link or live-region announcement on the banner; a GUIDE.md or README change (22.6 documents the MCP settings); an edit to `web/scripts/catalog.mjs` or `msg/catalog.ts` (21.10's, and in the initial bundle).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Changed tool | Server `zzA`: `zz_changed` classified `read-only`, then cleared by `ClearChanged(zzA, zz_changed, <new fingerprint>)`; `zz_new` a new unclassified row; `zz_risky` risky | GET `tools[]` rows gain `changed`: `zz_changed` `true`, the others `false` (JSON booleans). The section shows one banner, "zz_changed on zzA changed its description or inputs, ...", above the tools table; `zz_changed`'s radiogroup has Unclassified checked. The same clear sent each admin session one `mcp.toolChanged` notice with slots `{tool: zz_changed, server: zzA}` | -- |
| New tool only | `zz_new` unclassified, never cleared | No banner | -- |
| Classified after the change | The admin picks Read-only or Risky on `zz_changed` | On the 200: "Saved", the banner goes at once; after a reload the GET says `changed` `false` (Lane A's `Classify` reset) and no banner shows | A failed save puts the old value back (21.4) and the banner stays |
| Several changed | Two cleared tools, on one or two servers | One banner per tool, in the tools array's order (server, then name) | -- |
| Older answer | A GET row without `changed` (a fulfilled test answer) | No banner | -- |
| Online demo | `onlineDemo` 1 | T1 only (21.4); no banner | -- |

</intent-contract>

## Code Map

Line numbers are this worktree's at `598919da` (21.4 done). Lane A's lines will move when the flag lands; implement re-reads them.

- Lane A, read only (the flag's home; V1):
  - `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls` -- properties :20-32 (`Classification`, `Fingerprint`, `ChangedAt`), storage :36-64. No `Changed` yet.
  - `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- `Classify` :302-323 (`ChangedAt` :313, the audit-failure undo :318-320); `Tools` :326-348 (doc :326-328, SELECT :338, push :345 `{name, classification, status}`); `ClearChanged` :397-410; `ClearRow` :414-428 (`classified` :418, cleared :420-423, `events("changed")` then the Tool audit); `KeepRow` :484-501 (a new row is unclassified with `ChangedAt` now :492, the same as a cleared row); `Notify` :505-529 sends `mcp.toolChanged` {tool, server}.
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/OpsProbe.cls` -- `ClearChanged` through the real `ClearRow`; `^||ZzOps("admins")` sets the admin list (an empty value: no notice), `Notices()`/`NoticeCount(session, key)` :25-46, `Shadow("CommandsIn")` :14.
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls` -- `TestClassify` :313 (a `ClassifyTool` sent through the probe's `MessageHandler`: the sibling for `TestChangedTool`'s save) and `TestClearChanged` :644.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ListMcp` :2341-2377: its doc :2341-2346 names the tool members, and the push :2369 copies them one by one, so `changed` must be added there with type `boolean`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` :768-775 -- `settings.toolChangedBanner` (slots `tool`, `server`, type text). Read only.
- `web/src/app/api/api-types.ts` :358-364 -- `McpToolRow`. `api-client.ts` `mcpSettings()` :98 unchanged.
- `web/src/app/settings/mcp-view.ts` -- `MCP_TEXTS` :26-69 (`offOnDemo` :27 is the sibling: a catalog text held verbatim); `toolKey` :114; `withClassification` :163 (unchanged; its "puts the old value back" test compares whole objects).
- `web/src/app/settings/mcp-section.ts` -- the Tools group :176-226 (heading :177, the checkbox :178-181); `pick` :242-271 (`next` :255); styles :230+. Imports `Icon` already.
- `web/src/app/banners/banner-stack.ts` :93-170 -- the page's status banner (warning variant: tokens `--status-banner-warning-*`, `triangle-alert`, 4px left accent). Read only; it is in the initial bundle and bound to the live state.
- `web/src/app/settings/settings-page.ts` :279 -- `import('./mcp-section')` on first open (the lazy chunk). Read only.
- Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Core/SettingsMcp.cls` -- `TestList` :50-84 (:79 asserts 4 members: becomes 5); `MakeTool` :150-159; header :1-13.
  - `web/scripts/mcp-view.test.mjs` -- `catalogText(key)` :20-24, the fixed-strings block :34+.
  - `web/scripts/ux-strings.test.mjs` -- inventory row :70; `SOURCES.ux`.
  - `web/e2e/settings/mcp.spec.ts` -- header :7-25, `openMcp` :43, `tools()` region, B3 :139-163 (the pick sibling), `listBody` :245 (no `changed`: stays so).
  - `web/e2e/support/mcp.ts` -- `seedMcpServer` :18, `dropMcpServer` :39, `irisScript`.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-21 :873 and :876 (`Tools(server)`'s members), :879 (fingerprints, `ClearChanged`). Changed only with the flag (S1, V3).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (before any edit; record under Design Notes "Measured"):
  - (a) **Stop gate.** The Lane A flag of V1 is on this branch, as specified: `Mcp.ToolClassification` has `Changed`, `ClearRow` sets it, `Classify` resets it, and `Mcp.Ops.Tools(server)` gives `changed` as a JSON boolean. Check by reading the code and running `class OcuTalon.Test.Mcp.Tools` and `class OcuTalon.Test.Mcp.Ops:TestClearChanged` (warm). If any part is missing, or the name, type or meaning differs, HALT `blocked` with `Lane A flag not on the branch (21.9 V1)`. Edit nothing; 21.9 makes no Lane A edit.
  - (b) Whether 21.5 has landed in the shared files (Design Notes "Contended edits"). If it has, re-read the regions before editing.
  - (c) `cd web && npm run build` before any web edit: record the "Initial total" (expected 998.08 kB) and the size of the MCP lazy chunk.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ListMcp`: each tools row gains `changed`, set with `%Set("changed", <the Tools element's changed>, "boolean")`, so the JSON says `true`/`false`. Update its doc :2341-2346 and the class doc's ListMcpServers paragraph (:94) with the member.
- [ ] `web/src/app/api/api-types.ts` -- `McpToolRow` gains `changed?: boolean` (doc: true while McpOps' fingerprint check has made the tool Unclassified and no admin has classified it since; optional so an older answer reads as false).
- [ ] `web/src/app/settings/mcp-view.ts` -- `MCP_TEXTS.toolChanged` = the catalog text verbatim (with `{tool}` and `{server}`). Add three functions, and add their lines to the module doc:
  - `changedTools(tools)`: the rows whose `changed === true`, in the given order.
  - `toolChangedText(tool, server)`: the filled sentence, with function replacers, like `classificationName`.
  - `withoutChange(settings, server, tool)`: the settings with that row's `changed` set to false.
- [ ] `web/src/app/settings/mcp-section.ts` -- in the Tools group, after the heading and before the checkbox, one banner per `changedTools(settings().tools)` row:
  - `<div class="banner" data-banner="tool-changed" [attr.data-tool] [attr.data-server]>` with `<app-icon name="triangle-alert" [size]="20" />` and the text. No role, no close button, no link.
  - Styles: DESIGN's warning status banner, using the `--status-banner-warning-*` tokens and a 4px left accent (copy reason: Design Notes).
  - The banners are not filtered by "Unclassified only".
  - In `pick`'s `next`, apply `withoutChange` for the tool. The error path is unchanged, so a failed save keeps the banner.
  - Update the component doc :41-54.
- [ ] Tests (ObjectScript): `src/ocutalon/cls/OcuTalon/Test/Core/SettingsMcp.cls`:
  - `TestList` :79: 5 members (server, name, classification, status, changed), and every fixture row's `changed` is `0`.
  - New `TestChangedTool` (Matrix "Changed tool" and "Classified after the change"):
    - Fixture rows: `zz_changed` classified read-only, `zz_new` unclassified, `zz_risky` risky.
    - Set `^||ZzOps("admins") = $ListBuild("zzadmin"_..Number)`, then call `##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(a, "zz_changed", "zzfp2_"_..Number)`.
    - `List`: `zz_changed` has `changed` 1, the others 0, and `result.Data` contains `"changed":true` (a JSON boolean).
    - `NoticeCount("zzadmin"_n, "mcp.toolChanged")` is 1, and its slots name the same tool and server.
    - Then `ClassifyTool` (`risky`, origin `web_admin`) through `OpsProbe.Shadow("CommandsIn")`. After it, `List` gives `changed` 0.
    - Kill `^||ZzOps` in `OnAfterOneTest`. Update the header :1-13.
- [ ] Tests (web):
  - `web/scripts/mcp-view.test.mjs`:
    - `MCP_TEXTS.toolChanged` equals `catalogText('settings.toolChangedBanner')`.
    - `changedTools` keeps only `changed === true` rows (`false`, missing and an unclassified row are left out) in order.
    - `toolChangedText('lookup', 'Tickets')` equals the catalog test's rendered text (`Test/Msg/Catalog.cls` :1757), and a `$&` in a name is kept literally.
    - `withoutChange` changes only the named row of the named server, and does not change its input.
  - `web/scripts/ux-strings.test.mjs` -- the banner text under `SOURCES.ux` (EXPERIENCE holds it verbatim).
  - `web/e2e/support/mcp.ts` -- `clearChangedTool(server, tool)`: one `irisScript` that sets `^||ZzOps("admins")=""` (no admin notice) and calls `##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, tool, "zzfp2")`, checking the status (`CHK|clear|1`).
  - `web/e2e/settings/mcp.spec.ts` -- new B11, and its line in the header:
    - Seed `zzb11<tag>` with `zz_changed` read-only, `zz_new` unclassified and `zz_steady` risky, then `clearChangedTool(name, 'zz_changed')`.
    - Open the section. Exactly one banner in the Tools region, `[data-banner="tool-changed"][data-tool="zz_changed"]`, with the full sentence, and its icon. No banner for `zz_new`. `zz_changed`'s radiogroup has "Unclassified (counts as risky)" checked.
    - Pick Risky: "Saved", and the banner is gone. Reload: still no banner.
    - `dropMcpServer` in `finally`.

**Acceptance Criteria:**
- Given a tool whose description or inputs changed, which Lane A's `ClearChanged` made Unclassified, when an admin opens Settings > Tools and MCP servers, then a banner in the accepted wording of `settings.toolChangedBanner` names the tool and its server, its radiogroup shows Unclassified, and the same change sent each admin session the `mcp.toolChanged` notice card (FR-48, UX-DR145; B11, `TestChangedTool`).
- Given a newly discovered Unclassified tool that no fingerprint change touched, when the section opens, then no banner names it (B11, `TestChangedTool`, `mcp-view.test.mjs`).
- Given a banner, when the admin classifies that tool and the save succeeds, then the banner goes at once and stays gone after a reload (B11, `TestChangedTool`).
- Given the web build after this story, when `npm run build` runs, then the initial total equals Task 0 (c)'s (998.08 kB) and the banner code is only in the MCP lazy chunk.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-21: `Tools(server)` is the settings page's tool list (:873, :876). A changed fingerprint makes a tool unclassified and notifies admins (:872, :879). Adding `changed` to its elements amends this Rule (S1, V3).
- AD-12: the page decides nothing; it shows the server's flag.
- AD-13: no new route; the GET's envelope is unchanged.
- AD-25: the online demo shows T1 only.
- AD-29/AD-33: Lane A alone edits `Mcp/**`; Lane B asks for the property (AD-33 "asks for any property it needs").
- AD-32: the chat notice is Lane A's, already sent; the page holds the banner's catalog text verbatim, as 21.4 holds T1 (21.4 Decided 11).
No AC contradicts an AD Rule.

**The cross-lane ask (C1 of 21.4; V1-V3). What 21.9 needs from Lane A, exactly:**
- `OcuTalon.Mcp.ToolClassification`: new `Property Changed As %Boolean [ InitialExpression = 0 ];` -- "1 while the row is unclassified because McpOps cleared it after a fingerprint change (`ClearRow`), and no admin has classified it since". The storage gains `<Value name="7">Changed</Value>`, with the same globals. Existing rows read as empty, which counts as 0: no migration. A tool cleared before the upgrade shows no banner; its admins already had the chat notice.
- `Ops.ClearRow` sets `row.Changed = 1` in its `classified` branch (:420), in the same save. An already-unclassified row that only takes a new fingerprint keeps its `Changed`.
- `Ops.Classify` sets `row.Changed = 0` with its save, for any of the three words, and its audit-failure undo restores the previous value.
- `KeepRow`: a new row is 0 (the initial value); the refused branch is unchanged.
- `Ops.Tools(server)` selects `Changed`, and each element gains `changed`, a JSON boolean (`%Set(..., "boolean")`). It is true only when `Changed` is 1 and `Classification` is `unclassified`. The doc :326 says so.
- Lane A pins (mutation lines required; Lane A's story writes them):
  - `Test.Mcp.Ops` `TestClearChanged`: 1 after a clear, untouched by the unclassified-row update.
  - `TestClassify`: reset to 0, and restored by the undo.
  - `TestChangedTool`: through `RecordAttach`.
  - `Test.Mcp.Tools` `TestTools`: `changed` true only for a cleared unclassified row, as JSON `true`.
- S1, the spine (written with the flag, Rule 20):
  - AD-21 :876: "each element has `name`, `classification`, `status` and `changed` (true while `McpOps.ClearChanged` has made the tool unclassified after a fingerprint change and no admin has classified it since)".
  - AD-21 :879: "clears a classified tool whose fingerprint changed (`McpOps.ClearChanged`, audited, and marked `Changed` until an admin classifies it)".
- Why a stored column, and why nothing smaller works:
  - (a) The rows cannot tell a cleared tool from a new one. Both are `unclassified`, with a new fingerprint and a fresh `ChangedAt` (`ClearRow` :418-423, `KeepRow` :487-493).
  - Using `ChangedAt` "" for a new row would also fire on an admin's own pick of Unclassified, and on every row that exists at the upgrade.
  - (b) The audit log: "the latest Tool entry for (server, tool) is channel `system`, `unclassified`, at or after `ChangedAt`". Rejected:
    - A product read of `%SYS.Audit` needs a switch to `%SYS`.
    - IRIS's audit indexes lag up to a minute (`Bridge/Audit.cls` :10).
    - The event can be switched off or purged, so the banner would quietly be missing.
    - The audit log is AD-17's evidence record, not a data source.
  - So the smallest reliable change is one boolean column, two assignments and one member.
- Who builds it (the Planner rules; recommended first):
  - Recommended: Epic 22 (Lane A) adds it as one small story, after Lane D's 22.5/22.6/22.7 release `Mcp/Ops.cls`. 21.9 implements once it is merged forward into OCT-epic21 (Task 0 (a)).
  - Alternative: a ruled Lane A exception for 21.9, like DW-1041. That needs a spec amendment of Task 0 (a), "Never" and the Code Map, and the same contract.

**Decided in-stage (small, reversible):**
- (1) The banner text lives in `MCP_TEXTS` verbatim, with a test equal to the catalog text, like 21.4's T1 (Decided 11). The alternative, the generated `PAGE_TEXTS` through `renderPageText`, would grow the initial bundle and edit 21.10's `catalog.mjs`.
- (2) Placement: at the top of the Tools group, so "classified below" points at the table. The banners show whatever the filter says.
- (3) One banner per changed tool. DESIGN's banners stack; a changed tool is rare.
- (4) The banner goes on the save's 200, not on the pick, so a failed save keeps it. `withClassification` is unchanged, which keeps its whole-object restore test green.
- (5) Picking Unclassified again on a changed tool is 21.4's no-op (same value). The banner stays until the admin picks Read-only or Risky; its text asks for exactly that.
- (6) No live region, close or action: the banner is state, not an event. The "Saved" announcement already reports the change.
- (7) `changed` is optional in `McpToolRow`, and only `=== true` counts. B7-B10's fulfilled `listBody` stays as it is.
- (8) B11 makes the change with Lane A's real `ClearRow` through `OpsProbe.ClearChanged`, with an empty admin list. Writing the column directly would bypass it, and a real notice to every admin session would reach other tests' chats (shared surface). `TestChangedTool` pins the notice with `NoticeCount`.
- (9) The lead's instruction: the committed `epic-21-context.md` is reused, although the planning files are newer by mtime. The story block, EXPERIENCE :1009 and AD-21 were read directly.
- (10) No GUIDE.md or README line. 22.6 documents the MCP settings, and 21.4's T9 already says the tools count as risky until classified.

**Contended edits (Rule 11):**
- 21.5 (lane C, in planning; the same section) edits:
  - `ListMcp` (it adds `sources` to `Data`; 21.9 edits only the tools push :2369);
  - `MCP_TEXTS` (both add keys);
  - `mcp-section.ts` (21.5 adds a button in the tool row; 21.9 adds banners above the checkbox);
  - `api-types.ts` (`McpToolRow`);
  - `SettingsMcp.cls` (`TestList`), `mcp-view.test.mjs`, `e2e/settings/mcp.spec.ts` (B6+ vs B11) and `support/mcp.ts` (new helpers).
  - These are placed edits. Whichever lands second re-reads the regions and keeps both.
- 21.10: `BridgeSink`, the cards, `msg/catalog.ts`, `catalog.mjs`. No overlap.
- Lane D (22.5/22.6/22.7): `Mcp/Ops.cls`, `StepBuffer.cls`. 21.9 edits neither; V1's flag lands in `Ops.cls` after them.

**Integration ACs (Rule 1):** 21.9 introduces no service, module or shared component. The consumer chain is pinned against real instances: `ClearRow` and `Classify` (Lane A, real code through `OpsProbe`) -> `SettingsOps.ListMcp` -> GET -> the section's banner (`TestChangedTool`, B11).

**Consumes:** `Mcp.Ops.Tools(server)` `changed` (V1); `McpOps.ClearChanged`/`ClearRow` and `ClassifyTool` (Lane A); `ListMcpServers` and `Web.McpSettings` GET (21.4); `settings.toolChangedBanner` (35.2). **Consumed-by:** none (no service).

**Extend, don't copy (Rule 2):**
- The section, the view module, `ListMcp`, `SettingsMcp`, `mcp.spec.ts` and `support/mcp.ts` are 21.4's, extended.
- `toolChangedText` follows `classificationName`.
- Copy with a reason: the banner's dozen style lines repeat `banner-stack.ts`'s warning variant (:117-130, :138-143, :150-153). That component is the page's live-state stack, in the initial bundle. A shared global class would grow the initial styles, and moving the component into the lazy chunk is out of scope. The tokens are shared, so the look cannot drift.

**Ledger inbox:** `LEDGER slice 21-9-show-the-changed-tool-banner-in-settings` is empty (`owned_ledger=0`). No entry in `slice all` names this banner.

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | Cross-lane ask to Lane A / Epic 22: the `changed` flag (Design Notes, exact contract), built by Epic 22 after 22.5/22.6/22.7 release `Mcp/Ops.cls`; 21.9's implement waits (Task 0 (a)) | approve | none (McpOps and the section are off) |
| V2 | Stored-data shape: `OcuTalon.Mcp.ToolClassification.Changed` (`%Boolean`, initial 0, storage value 7; existing rows read 0; no migration) | approve | none |
| V3 | Amending AD-21 (S1): `Tools(server)` elements gain `changed`; `ClearChanged` marks the row until an admin classifies it | approve | -- |

## Public text

Reused verbatim, accepted (no new text): `settings.toolChangedBanner`, "{tool} on {server} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below." (EXPERIENCE :1009, Core catalog :768, 35.2's proposal). Also 21.4's "Unclassified (counts as risky)" and "Saved". Online demo: none (T1 only).

## Verification

**How to run:**
- Run from the worktree root after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s9iw`, fresh `e21s9i` (QA `e21s9qw`/`e21s9q`, review `e21s9rw`/`e21s9r`).
- One command per foreground call, `timeout: 600000`, each sized to about 150 s; a large class one method per call. Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`.
- SettingsOps runs in the production, so after a mutation of `ListMcp`, run `ci/warm.sh down` then `up`. Tear down only this stage's tags.

**Shared surfaces:**
- The GET tool element: 4 -> 5 members. `SettingsMcp:TestList` :79 changes; `e2e/api/mcp.spec.ts` only types it; `listBody` in `e2e/settings/mcp.spec.ts` stays without it.
- `McpToolRow`. The `MCP_TEXTS` inventory (`ux-strings.test.mjs`).
- The Tool audit entries a real `ClearRow` writes, keyed by the test's own `zz` server.
- `^||ZzOps` nodes, which each test kills.
- Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s9iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s9iw ci/iris.sh class OcuTalon.Test.Mcp.Tools`, then `... class OcuTalon.Test.Mcp.Ops:TestClearChanged` (once each; Task 0 (a)) -- pass.
- `... class OcuTalon.Test.Core.SettingsMcp` (loop) -- pass. Mutations (Rule 19):
  - `ListMcp` leaves out `changed` -> `TestChangedTool` red.
  - `ListMcp` copies it as a number (no `"boolean"`) -> red (`"changed":true`).
  - `ListMcp` sets `changed` from `classification = "unclassified"` -> red (`zz_new`).
- `... class` for `OcuTalon.Test.Web.McpSettingsApi`, `OcuTalon.Test.Msg.Catalog` (once each, one per call) -- pass.
- `node --test web/scripts/` (loop) -- pass. Mutations:
  - `changedTools` keeps every unclassified row -> red.
  - One word of `MCP_TEXTS.toolChanged` changed -> red (`catalogText`).
  - `withoutChange` changes every row of the server -> red.
- `cd web && npx tsc -p tsconfig.e2e.json --noEmit` (once) -- clean.
- `cd web && npm run build` (once) -- clean. "Initial total" equals Task 0 (c)'s (998.08 kB), and only the MCP lazy chunk grew.
- `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh build` (once).
- `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh live sign-in-2 --part k/n` (once; the part whose PART line lists `settings/mcp.spec.ts`, n sized to about 150 s) -- pass. Mutations:
  - The banner's `@for` over every unclassified tool -> B11 red (`zz_new` banner).
  - `withoutChange` not applied on the 200 -> B11 red (the banner stays after "Saved").
- `<vars> OCUTALON_RUN_TAG=e21s9iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh teardown` (once each, also after a failure).
- `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` (once each) -- pass.

**Manual checks:**
- (once) `grep -rn "mcp-view\|mcp-section" web/src/app --include='*.ts'` -- only `settings-page.ts`'s dynamic `import('./mcp-section')` and doc comments, so no static import pulls the banner into the initial bundle.
- (once) `git diff --stat -- src/ocutalon/cls/OcuTalon/Mcp src/ocutalon/cls/OcuTalon/Test/Mcp src/bridge` -- empty (no Lane A edit by 21.9).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Planned only ("Halt after planning."). Implement waits for Lane A's `changed` flag: Task 0 (a) stops it if the flag is not on the branch (Veto V1-V3, the cross-lane ask to Epic 22).
- Ledger inbox: empty.
