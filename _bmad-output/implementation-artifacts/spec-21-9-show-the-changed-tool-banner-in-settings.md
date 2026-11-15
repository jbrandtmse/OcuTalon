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
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-15-the-tool-list-reports-which-tools-changed-the-changed-flag.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When an MCP server changes a classified tool's description or inputs, McpOps (`ClearChanged`) makes the tool Unclassified and sends each admin the `mcp.toolChanged` chat notice. Settings > Tools and MCP servers then shows the tool as one more Unclassified row, the same as a newly discovered tool, so the admin cannot tell which tool changed. The banner the UX accepted (`settings.toolChangedBanner`) is never shown.

**Approach:** Story 22.15 (Lane C under the Lane A exception V1) made `Mcp.Ops.Tools(server)` say which tools McpOps cleared after a fingerprint change: a `changed` member, a JSON boolean. 21.9 passes it through `ListMcp` and the GET, and the section shows one warning banner per changed tool that is not refused, in the accepted wording, above the tools table. A classification save clears the flag, and the banner goes.

## Boundaries & Constraints

**Always:**
- Lane B only, in 21.4's section and route (Rules 1/2): `SettingsOps.ListMcp`, `api-types.ts`, `mcp-view.ts`, `mcp-section.ts` and their tests, plus one as-built note on the spine's REST row (Task "Spine"). No new route, command, service, catalog key or text.
- The banner text is the Core catalog's `settings.toolChangedBanner`, word for word: "{tool} on {server} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below." (EXPERIENCE "Settings and requests (step 4)" :1009; `Msg/Catalog/Core.cls` :818-825; Story 35.2's proposal, accepted; reuse ruled fine, ~02:00Z Nov 14 item 3). The page decides nothing of its own (AD-12): a banner shows only for a tool whose GET row has `changed` exactly `true` AND whose `status` is not `refused` (the Contest Planner's ruling "21.9 banner and refused tools", ~03:15Z Nov 15). A missing or false `changed` means no banner.
- All new web code goes in the lazy MCP chunk (`mcp-view.ts`, `mcp-section.ts`). The initial bundle stays under the Planner's 921 kB target (DW-1282; `web/scripts/initial-bundle.test.mjs` `MAX_INITIAL_BYTES` :21; 878.98 kB measured after 36.5) and does not grow by one byte: no import of the MCP files from the page, and no new key in the generated `msg/catalog.ts` `PAGE_TEXTS`.
- Online demo: the section shows only T1 (21.4), so the banner never shows there and no MCP endpoint runs.
- Every test added or changed creates and removes its own `zz` servers, tool rows and `^||ZzOps` nodes, and passes on a fresh environment, in either order. No real MCP server: fixture rows and Lane A's real `ClearChanged` through `Test.Mcp.OpsProbe` only.

**Never:**
- Any Lane A edit (`Mcp/**`, `Test/Mcp/**`, `src/bridge/**`). The flag is 22.15's and is on this branch; 21.9 only reads it.
- A banner derived from `classification`, `ChangedAt` or the audit log; a banner for a refused tool; a filter of refused rows in `ListMcp` (the server reports both members as they are, DW-1355 by design); a close button, action link or live-region announcement on the banner; a GUIDE.md or README change (22.6 documents the MCP settings); an edit to `web/scripts/catalog.mjs` or `msg/catalog.ts` (21.10's, and in the initial bundle).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Changed tool | Server `zzA`: `zz_changed` classified `read-only`, then cleared by `ClearChanged(zzA, zz_changed, <new fingerprint>)`; `zz_new` a new unclassified row; `zz_risky` risky | GET `tools[]` rows gain `changed`: `zz_changed` `true`, the others `false` (JSON booleans). The section shows one banner, "zz_changed on zzA changed its description or inputs, ...", above the tools table; `zz_changed`'s radiogroup has Unclassified checked. The same clear sent each admin session one `mcp.toolChanged` notice with slots `{tool: zz_changed, server: zzA}` | -- |
| Changed, then refused | `zz_shadow` classified, cleared (`Changed` 1), then the server's `RefusedTools` names it (a later attach that refuses it keeps `Changed`: `KeepRow` :756-759) | GET row `changed: true`, `status: refused` (passed through as 22.15 gives it). No banner names it; the row shows "Refused: a built-in tool has this name" (21.4) | -- |
| Changed, server unavailable | a cleared tool whose status is `unavailable` | One banner (only `refused` is skipped) | -- |
| New tool only | `zz_new` unclassified, never cleared | No banner | -- |
| Classified after the change | The admin picks Read-only or Risky on `zz_changed` | On the 200: "Saved", the banner goes at once; after a reload the GET says `changed` `false` (`Classify` reset) and no banner shows | A failed save puts the old value back (21.4) and the banner stays |
| Several changed | Two cleared tools, on one or two servers | One banner per tool, in the tools array's order (server, then name) | -- |
| Older answer | A GET row without `changed` (a fulfilled test answer) | No banner | -- |
| Online demo | `onlineDemo` 1 | T1 only (21.4); no banner | -- |

</intent-contract>

## Code Map

Line numbers are this worktree's at `09b8dd201` (branch `OCT-epic21-s219`: 21.4 and 21.10 done, 22.15 on it, 21.5 not on it). 21.5 moves the web and `SettingsOps` lines when it lands (Design Notes "Contended edits"); 22.11 moves `Mcp/Ops.cls` lines. Implement re-reads them.

- Lane A, read only (22.15's flag; contract in Design Notes "The flag contract"):
  - `src/ocutalon/cls/OcuTalon/Mcp/ToolClassification.cls` -- class doc :8-9 (`Changed`: 1 from `ClearChanged` until an admin classifies; 0 for a new row; empty before the property existed, reported false); `Property Changed As %Boolean [ InitialExpression = 0 ]` :37; storage `<Value name="7">Changed</Value>` :62-64.
  - `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- class doc :31-32 (Tools' four members), :37-38 (ClearChanged marks, Classify resets); `Classify` :417-442 (`Changed = 0` :429, the audit-failure undo restores it :437); `Tools` :580-606 (doc :580-583, SELECT with `Changed` :593, the status :599, `%Set("changed", (+Changed = 1) && (classification = "unclassified"), "boolean")` :602); `ClearChanged` :651-670; `ClearRow` :673-689 (`Changed = 1` in the classified branch only :679-683); `KeepRow` :744-761 (a new row :747-753; the refused branch keeps `Changed` :756-759, the source of DW-1355); `Notify` :765-790 sends `mcp.toolChanged` {tool, server} :786.
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/OpsProbe.cls` -- inherits the real `ClearChanged`/`ClearRow`; `Shadow` :19; `Notices()` :30, `NoticeCount(session, key)` :43; `AdminSessions` :59-70 (`^||ZzOps("admins")` set: that list, so an empty value means no notice).
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Ops.cls` -- `TestClassify` :328 (the `ClassifyTool` sibling for `TestListChanged`'s save), `TestAuditFails` :366, `TestRecordAttachRows` :458 (the refused branch, :466), `TestChangedTool` :644 (through `RecordAttach`), `TestClearChanged` :677. `src/ocutalon/cls/OcuTalon/Test/Mcp/Tools.cls` `TestToolsChanged` :62.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- the class doc's ListMcpServers paragraph :100-101; `ListMcp` :2373-2410: its doc :2373-2378 names the tool members, and the push :2401 copies them one by one, so `changed` must be added there with type `boolean`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` :818-825 -- `settings.toolChangedBanner` (slots `tool`, `server`, type text). Read only.
- `web/src/app/api/api-types.ts` :399-405 -- `McpToolRow` (doc :399). `McpSettings` :407-411. `api-client.ts` `mcpSettings()` :116 unchanged.
- `web/src/app/settings/mcp-view.ts` -- module doc :1-15; `MCP_TEXTS` :26-69 (`offOnDemo` :27 is the sibling: a catalog text held verbatim; `toolStatus.refused` :62); `classificationName` :99-101 (the replacer pattern); `toolKey` :114; `withClassification` :162-167 (unchanged; its "puts the old value back" test compares whole objects).
- `web/src/app/settings/mcp-section.ts` -- component doc :41-54; imports `Icon` :8 and the view functions :14-27; the Tools group :176-226 (heading :177, the checkbox :178-181); styles :230+; `pick` :571-600 (`next` :584-587, `error` :588-598).
- `web/src/app/banners/banner-stack.ts` :93-170 -- the page's status banner (warning variant: `.banner` :117-131, the warning tokens `--status-banner-warning-*` :138-143, `.mark` :150-153; `triangle-alert`, 4px left accent). Read only; it is in the initial bundle and bound to the live state.
- `web/src/app/settings/settings-page.ts` :308 -- `import('./mcp-section')` on first open (the lazy chunk). Read only.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-21 :884 (settings page's tool list, `changed` flag), :887 (`Tools(server)`, S1), :890 (Fingerprints at attach, S1): all already written by 22.15, read only. The REST row `GET /api/v1/settings/mcp` :1805 lists the tool members `{server, name, classification, status}`: 21.9 adds the as-built note.
- Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Core/SettingsMcp.cls` -- header :1-10; `OnAfterOneTest` :41-48; `TestList` :50-84 (:79 asserts 4 members: becomes 5); `MakeServer(name, status, refused)` :139-147; `MakeTool` :150-159; `List()` :180.
  - `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` :1835 -- the rendered `settings.toolChangedBanner` for `lookup`/`Tickets`. Read only.
  - `web/scripts/mcp-view.test.mjs` -- imports :14-16, `catalogText(key)` :20-24, the fixed-strings block :34+, `withClassification` :189+.
  - `web/scripts/ux-strings.test.mjs` -- inventory row `settings/mcp-view.ts` :72; `SOURCES.ux` :183, the Story 21.4 block :262+.
  - `web/scripts/initial-bundle.test.mjs` -- `MAX_INITIAL_BYTES = 921_000` :21. Read only.
  - `web/e2e/settings/mcp.spec.ts` -- header :7-27, `openMcp` :43, `tools()` :51, B3 :139-163 (the pick sibling), `listBody` :246 (no `changed`: stays so).
  - `web/e2e/support/mcp.ts` -- `seedMcpServer` :19, `dropMcpServer` :40, `irisScript`/`chk` :1.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (before any edit; record under Design Notes "Measured"):
  - (a) **Contract check of 22.15** (read the code; no Lane A edit). Confirm, each at its file:line, that the flag is as Design Notes "The flag contract" says: the member name `changed` and the property `Mcp.ToolClassification.Changed` (:37, storage value 7); a JSON boolean (`Ops.cls` :602, `%Set(..., "boolean")`); true only while unclassified (`&& (classification = "unclassified")` :602); an empty `Changed` reads false (`+` on the value :602; class doc :9). Also confirm the spine already holds S1 (AD-21 :887 and :890, each with `[AMENDED 2026-11-14, Story 21.9 and the Epic 22 flag story, Contest Planner rulings V1-V3]`); 21.9 writes no AD-21 text. **STOP** `blocked` with `22.15 flag contract differs (21.9 Task 0 (a))` only if a name, the type, the unclassified-only rule or the empty-value rule differs, or the S1 text is missing. Edit nothing then. Also confirm 22.15 is merged to feature before 21.9 merges (ruling ~22:40Z: "21.9 implements on top of it, after 22.15 merges"); this branch carries 22.15's commits, so 21.9 never merges ahead of it.
  - (b) Whether 21.5 has landed in the shared files (Design Notes "Contended edits"). If it has, re-read the listed regions before editing, and keep both stories' lines.
  - (c) `cd web && npm run build` before any web edit: record the "Initial total" (about 879 kB expected; under 921 kB) and the size of the MCP lazy chunk.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `ListMcp`: each tools row gains `changed`, set with `%Set("changed", tool.changed, "boolean")` on the pushed object, so the JSON says `true`/`false`. Copy it as `Tools` gives it, for every status (no refused filter here). Update its doc :2373-2378 and the class doc's ListMcpServers paragraph (:100-101) with the member.
- [ ] `web/src/app/api/api-types.ts` -- `McpToolRow` gains `changed?: boolean` (doc: true while McpOps' fingerprint check has made the tool Unclassified and no admin has classified it since; it can be true for a refused tool; optional so an older answer reads as false).
- [ ] `web/src/app/settings/mcp-view.ts` -- `MCP_TEXTS.toolChanged` = the catalog text verbatim (with `{tool}` and `{server}`). Add three functions, and add their lines to the module doc:
  - `changedTools(tools)`: the rows whose `changed === true` AND whose `status !== 'refused'` (ruling ~03:15Z Nov 15), in the given order.
  - `toolChangedText(tool, server)`: the filled sentence, with function replacers, like `classificationName`.
  - `withoutChange(settings, server, tool)`: `{ ...settings, tools }` with that row's `changed` set to false (the spread keeps 21.5's `sources` if it has landed).
- [ ] `web/src/app/settings/mcp-section.ts` -- in the Tools group, after the heading and before the checkbox, one banner per `changedTools(settings().tools)` row:
  - `<div class="banner" data-banner="tool-changed" [attr.data-tool] [attr.data-server]>` with `<app-icon name="triangle-alert" [size]="20" />` and the text. No role, no close button, no link.
  - Styles: DESIGN's warning status banner, using the `--status-banner-warning-*` tokens and a 4px left accent (copy reason: Design Notes).
  - The banners are not filtered by "Unclassified only".
  - In `pick`'s `next`, apply `withoutChange` for the tool. The error path is unchanged, so a failed save keeps the banner.
  - Update the component doc :41-54.
- [ ] Spine REST row `GET /api/v1/settings/mcp` (:1805): after the tools shape, add "each tool row also carries `changed` (AD-21's `Tools(server)` member, passed through) [AMENDED 2026-11-15, Story 21.9: record of V3, approved ~02:00Z Nov 14]". No other spine edit. Run `lint_spine.py` (baseline 10 low).
- [ ] Tests (ObjectScript): `src/ocutalon/cls/OcuTalon/Test/Core/SettingsMcp.cls`:
  - `TestList` :79: 5 members (server, name, classification, status, changed), and every fixture row's `changed` is `0`.
  - New `TestListChanged` (Matrix "Changed tool", "Changed, then refused" and "Classified after the change"):
    - Fixture rows on server `a` (`MakeServer(a, "attached", "")`): `zz_changed` classified read-only, `zz_shadow` read-only, `zz_new` unclassified, `zz_risky` risky.
    - Set `^||ZzOps("admins") = ""` and call `##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(a, "zz_shadow", "zzfp2_"_..Number)`; then set the server row's `RefusedTools = $ListBuild("zz_shadow")` and save it (the fixture form of a later attach that refuses it).
    - Set `^||ZzOps("admins") = $ListBuild("zzadmin"_..Number)`, then `ClearChanged(a, "zz_changed", "zzfp2_"_..Number)`.
    - `List`: `zz_changed` has `changed` 1 and status available; `zz_shadow` has `changed` 1 and status refused (passed through; the page skips it); `zz_new` and `zz_risky` 0. `result.Data` contains `"changed":true` (a JSON boolean).
    - `NoticeCount("zzadmin"_n, "mcp.toolChanged")` is 1, and its slots name `zz_changed` and `a`.
    - Then `ClassifyTool` (`risky`, origin `web_admin`) for `zz_changed` through `OpsProbe.Shadow("CommandsIn")`. After it, `List` gives `zz_changed` `changed` 0.
    - Kill `^||ZzOps` in `OnAfterOneTest`. Update the header :1-10.
- [ ] Tests (web):
  - `web/scripts/mcp-view.test.mjs`:
    - `MCP_TEXTS.toolChanged` equals `catalogText('settings.toolChangedBanner')`.
    - `changedTools` keeps only `changed === true` rows that are not refused, in order. Both ruled cases: a row with `changed: true, status: 'refused'` (changed, then reported refused) is left out; a row with `changed: true, status: 'available'` is kept. Also kept: `changed: true, status: 'unavailable'`. Left out: `changed: false`, a missing `changed`, and an unclassified row with no `changed`.
    - `toolChangedText('lookup', 'Tickets')` equals the catalog test's rendered text (`Test/Msg/Catalog.cls` :1835), and a `$&` in a name is kept literally.
    - `withoutChange` changes only the named row of the named server, keeps every other member of the settings, and does not change its input.
  - `web/scripts/ux-strings.test.mjs` -- the banner text under `SOURCES.ux` (EXPERIENCE :1009 holds it verbatim), in the Story 21.4 block or a 21.9 comment line beside it.
  - `web/e2e/support/mcp.ts` -- `clearChangedTool(server, tool, refused = false)`: one `irisScript` that sets `^||ZzOps("admins")=""` (no admin notice) and calls `##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, tool, "zzfp2")`, checking the status (`CHK|clear|1`); with `refused`, the same script then adds the tool to the server row's `RefusedTools` and saves it (`CHK|refuse|1`).
  - `web/e2e/settings/mcp.spec.ts` -- new **B14** (21.5 takes B11-B13), and its line in the header:
    - Seed `zzb14<tag>` with `zz_changed` read-only, `zz_shadow` read-only, `zz_new` unclassified and `zz_steady` risky, then `clearChangedTool(name, 'zz_changed')` and `clearChangedTool(name, 'zz_shadow', true)`.
    - Open the section. Exactly one banner in the Tools region, `[data-banner="tool-changed"][data-tool="zz_changed"]`, with the full sentence, and its icon. No banner for `zz_new` or `zz_shadow` (refused). `zz_changed`'s radiogroup has "Unclassified (counts as risky)" checked.
    - Pick Risky: "Saved", and the banner is gone. Reload: still no banner.
    - `dropMcpServer` in `finally`.

**Acceptance Criteria:**
- Given a tool whose description or inputs changed, which Lane A's `ClearChanged` made Unclassified, when an admin opens Settings > Tools and MCP servers, then a banner in the accepted wording of `settings.toolChangedBanner` names the tool and its server, its radiogroup shows Unclassified, and the same change sent each admin session the `mcp.toolChanged` notice card (FR-48, UX-DR145; B14, `TestListChanged`).
- Given a tool that was marked changed and is then reported refused (`changed: true`, status `refused`), when the section opens, then no banner names it, while a changed tool that is not refused still has its banner (Contest Planner ruling ~03:15Z Nov 15, DW-1355; `mcp-view.test.mjs` `changedTools`, B14, `TestListChanged`).
- Given a newly discovered Unclassified tool that no fingerprint change touched, when the section opens, then no banner names it (B14, `TestListChanged`, `mcp-view.test.mjs`).
- Given a banner, when the admin classifies that tool and the save succeeds, then the banner goes at once and stays gone after a reload (B14, `TestListChanged`).
- Given the web build after this story, when `npm run build` and `initial-bundle.test.mjs` run, then the initial total equals Task 0 (c)'s and stays under 921 kB, and the banner code is only in the MCP lazy chunk.

## Spec Change Log

### 2026-11-15 - Refresh after 22.15, and the refused-tool ruling (plan stage, spec gate)
- Trigger: Story 22.15 built the `changed` flag (branch `OCT-epic22-s2215`, green, not yet merged; this branch `OCT-epic21-s219` at `09b8dd201` is built on it), and the Contest Planner's binding ruling "21.9 banner and refused tools" (~03:15Z Nov 15).
- Code Map and Tasks: every file:line re-verified against `09b8dd201`. Moved: `ListMcp` :2341-2377 -> :2373-2410 (push :2369 -> :2401, class doc :94 -> :100-101); `McpToolRow` :358-364 -> :399-405; `mcpSettings()` :98 -> :116; `pick` :242-271 -> :571-600 (`next` :255 -> :584); `settings-page.ts` :279 -> :308; Core catalog :768 -> :818; catalog test :1757 -> :1835; `SettingsMcp` header :1-13 -> :1-10; OpsProbe `Notices`/`NoticeCount` :25-46 -> :30/:43, `Shadow` :14 -> :19; `ux-strings` row :70 -> :72; e2e header :7-25 -> :7-27, `listBody` :245 -> :246; `support/mcp.ts` `dropMcpServer` :39 -> :40; Lane A's lines all re-read with the flag in place. Unchanged: `MCP_TEXTS` :26-69, `toolKey` :114, `withClassification` :163, the Tools group :176-226, `banner-stack.ts` :93-170, `TestList` :50-84.
- Task 0 (a): was a stop gate waiting for the flag; now a read check of 22.15's contract (name, JSON boolean, unclassified-only, empty reads false, each with file:line) and of S1 in the spine. It stops only if they differ.
- Spine: S1 is already in via 22.15 (AD-21 :887, :890, plus :884 from 22.15's review). 21.9's S1 work is removed; Task 0 (a) checks it. Added one as-built note on the REST row :1805 (the GET's tool rows carry `changed`), a record of V3, not a new rule.
- Refused ruling folded in: the `changedTools` rule is `changed === true` AND status not `refused`; a new Matrix row and AC; the node test has both ruled cases with a mutation; B14 adds a cheap refused tool (one helper flag, one more seed tool); `TestListChanged` pins that `ListMcp` passes `changed: true` through for the refused row (the skip is the page's, per the ruling).
- Renames: the e2e case is B14, because 21.5 has B11-B13; the ObjectScript test is `TestListChanged`, because `Test.Mcp.Ops` already has 22.15's `TestChangedTool`.
- Bundle: the cap is now the Planner's 921 kB target (`initial-bundle.test.mjs`, 36.5), not 998.08 kB of 1 MB; Verification names the test.
- Contended edits rewritten: 21.5's shared regions listed; 21.10 has landed (no overlap); Lane D is on 22.11 (`Mcp/Ops.cls`, which 21.9 does not edit).
- Veto items V1-V3: closed as approved (~02:00Z Nov 14 item 3; S1 ~05:30Z item 2; 22.15 charter ~22:40Z). No new veto item.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-21: `Tools(server)` is the settings page's tool list (:884, :887) and now carries `changed` (S1, written by 22.15). A changed fingerprint makes a tool unclassified, marks it and notifies admins (:890).
- AD-12: the page decides nothing of its own; it shows the server's members. The refused skip combines two server-given members (`changed`, `status`) by the Planner's ruling, the same way 21.5's `canBeSource` reads `classification` and `status`.
- AD-13: no new route; the GET's envelope is unchanged.
- AD-25: the online demo shows T1 only.
- AD-29/AD-33: Lane A alone edits `Mcp/**`; 22.15 did the flag under the ruled exception V1, and 21.9 edits none of it.
- AD-32: the chat notice is Lane A's, already sent; the page holds the banner's catalog text verbatim, as 21.4 holds T1 (21.4 Decided 11).
No AC contradicts an AD Rule.

**The flag contract (22.15, on this branch; Task 0 (a) checks it):**
- `OcuTalon.Mcp.ToolClassification.Changed`, `%Boolean`, `InitialExpression = 0`, storage `<Value name="7">` in the same globals, no migration (`ToolClassification.cls` :37, :62-64; V2).
- `Ops.ClearRow` sets it to 1 in the classified branch only (:679-683); an already-unclassified row that takes a new fingerprint keeps it.
- `Ops.Classify` sets it to 0 for any of the three words (:429); the audit-failure undo restores it (:437).
- `KeepRow`: a new row starts at 0 (:747-753); the refused branch keeps it (:756-759).
- `Ops.Tools(server)`: member `changed`, always a JSON boolean, `(+Changed = 1) && (classification = "unclassified")` (:602; doc :580-583). An empty `Changed` (a pre-upgrade row) reads false.
- Consequence (DW-1355, by design in 22.15): a tool marked changed and later refused reads `changed: true` with `status: refused`. 21.9's banner skips it (ruling ~03:15Z Nov 15).
- Lane A pins (22.15's): `Test.Mcp.Ops` `TestClearChanged` :677, `TestClassify` :328, `TestAuditFails` :366, `TestRecordAttachRows` :458, `TestChangedTool` :644; `Test.Mcp.Tools` `TestToolsChanged` :62 (the pre-upgrade row).

**Decided in-stage (small, reversible):**
- (1) The banner text lives in `MCP_TEXTS` verbatim, with a test equal to the catalog text, like 21.4's T1 (Decided 11). The alternative, the generated `PAGE_TEXTS` through `renderPageText`, would grow the initial bundle and edit 21.10's `catalog.mjs`.
- (2) Placement: at the top of the Tools group, so "classified below" points at the table. The banners show whatever the filter says.
- (3) One banner per changed tool. DESIGN's banners stack; a changed tool is rare.
- (4) The banner goes on the save's 200, not on the pick, so a failed save keeps it. `withClassification` is unchanged, which keeps its whole-object restore test green.
- (5) Picking Unclassified again on a changed tool is 21.4's no-op (same value). The banner stays until the admin picks Read-only or Risky; its text asks for exactly that.
- (6) No live region, close or action: the banner is state, not an event. The "Saved" announcement already reports the change.
- (7) `changed` is optional in `McpToolRow`, and only `=== true` counts. B7-B10's fulfilled `listBody` stays as it is.
- (8) B14 makes the change with Lane A's real `ClearRow` through `OpsProbe.ClearChanged`, with an empty admin list. Writing the column directly would bypass it, and a real notice to every admin session would reach other tests' chats (shared surface). `TestListChanged` pins the notice with `NoticeCount`.
- (9) The lead's instruction: the committed `epic-21-context.md` is reused, although the planning files are newer by mtime. The story block, EXPERIENCE :1009 and AD-21 were read directly.
- (10) No GUIDE.md or README line. 22.6 documents the MCP settings, and 21.4's T9 already says the tools count as risky until classified.
- (11) The refused skip is in `changedTools` (the page), not in `ListMcp`: the ruling names the banner, and 22.15 kept the server's report as it is (DW-1355 by design). `ListMcp` passes `changed` through for every status, which `TestListChanged` pins.
- (12) Only `refused` is skipped. An `unavailable` tool that was cleared keeps its banner: it is still Unclassified and still counts as risky once the server is back, and the ruling names refused only.
- (13) The refused fixture is a direct edit of the server row's `RefusedTools` after the real clear (in `TestListChanged` and in `clearChangedTool`), not a `RecordAttach` report, which would also sync and delete the other fixture rows. Lane A's `TestRecordAttachRows` already pins that the refused branch keeps `Changed`.
- (14) The e2e case is B14 and the ObjectScript test `TestListChanged`, to avoid 21.5's B11-B13 and 22.15's `Test.Mcp.Ops` `TestChangedTool`.
- (15) The REST row note (:1805) is an as-built record of V3: `ListMcp` passes `Tools`' elements, and V3 approved `changed` on them. It is not a new rule. 21.5 appends to the same row.

**Contended edits (Rule 11):**
- 21.5 (lane C, on `OCT-epic21` at `1ecb7150d`, not on this branch; it lands on feature before or after 21.9, and whoever lands second re-reads the regions and keeps both stories' lines). Shared regions:
  - `Core/SettingsOps.cls`: the class doc's ListMcpServers paragraph (:100-101; 21.5 adds the sources clause) and `ListMcp`'s doc (:2373-2378; 21.5 adds `sources`) and its last lines (21.5 adds `SourceRows` and `sources` to `Data` after the loop; 21.9 edits only the tools push :2401).
  - `api-types.ts`: `McpToolRow` and the `McpSettings` block next to it (:399-411; 21.5 adds `McpSourceRow`, `McpSourceBody`, a required `sources`, and rewrites the `McpSettings` doc). 21.9's `withoutChange` spreads the settings, so it keeps `sources`.
  - `mcp-view.ts`: the module doc (:1-15) and its import line (:16; 21.5 adds `intervalText`); `MCP_TEXTS` (:26-69; both add keys); the end of the file after `withClassification` (21.5 changes its return to spread the settings; both add functions).
  - `mcp-section.ts`: the component doc (:41-54; both add lines after the radiogroup bullet); the view-function import list (:14-27); the Tools group (:176-226: 21.5 adds a Source column and a source form after the table; 21.9 adds banners between the heading and the checkbox); the styles block (:230+). `pick` (:571-600) is 21.9's only.
  - `Test/Core/SettingsMcp.cls`: the header (:1-10), `OnAfterOneTest` (:41-48; 21.5 adds a fixture clean, 21.9 the `^||ZzOps` kill), `TestList` (:50-84; 21.5 adds a `sources` assertion, 21.9 changes :79), the new methods after `TestList`, and `List()` (:180; 21.5 adds a `sessionRef` argument).
  - `web/scripts/mcp-view.test.mjs` (imports :14-16; new describe blocks), `web/scripts/ux-strings.test.mjs` (`SOURCES.ux`; 21.5 adds its block at the end of the ux list), `web/e2e/settings/mcp.spec.ts` (the header list :7-27, the import line :5, cases at the end: 21.5's B11-B13, 21.9's B14), `web/e2e/support/mcp.ts` (new helpers at the end; 21.5 also edits `dropMcpServer` and `leftovers`).
  - The spine REST row `GET /api/v1/settings/mcp` :1805 (both append a note).
- 21.10 (landed on this branch): `BridgeSink`, the cards, `msg/catalog.ts`, `catalog.mjs`. No overlap.
- Lane D's 22.11: `Mcp/Ops.cls`. 21.9 does not touch it (it reads `Tools` only); its lines may move, and implement re-reads them.

**Integration ACs (Rule 1):** 21.9 introduces no service, module or shared component. The consumer chain is pinned against real instances: `ClearRow` and `Classify` (Lane A, real code through `OpsProbe`) -> `SettingsOps.ListMcp` -> GET -> the section's banner (`TestListChanged`, B14).

**Consumes:** `Mcp.Ops.Tools(server)` `changed` and `status` (22.15, 22.2); `McpOps.ClearChanged`/`ClearRow` and `ClassifyTool` (Lane A); `ListMcpServers` and `Web.McpSettings` GET (21.4); `settings.toolChangedBanner` (35.2). **Consumed-by:** none (no service).

**Extend, don't copy (Rule 2):**
- The section, the view module, `ListMcp`, `SettingsMcp`, `mcp.spec.ts` and `support/mcp.ts` are 21.4's, extended.
- `toolChangedText` follows `classificationName`.
- Copy with a reason: the banner's dozen style lines repeat `banner-stack.ts`'s warning variant (:117-131, :138-143, :150-153). That component is the page's live-state stack, in the initial bundle. A shared global class would grow the initial styles, and moving the component into the lazy chunk is out of scope. The tokens are shared, so the look cannot drift.

**Ledger inbox:** `LEDGER slice 21-9-show-the-changed-tool-banner-in-settings` was empty at planning (`owned_ledger=0`). DW-1355 (22.15, `by-design`, "reopen via 21.9's spec if the banner must skip status refused") is answered here by the ruling: the banner skips refused tools; the Lane A behaviour stays as built.

**Measured:** (Task 0 records here.)

## Veto items

| # | Item | Status | Online demo |
| --- | --- | --- | --- |
| V1 | The `changed` flag in Lane A (cross-lane ask) | Closed: approved ~02:00Z Nov 14 item 3; built by 22.15 under the Lane A exception (charter ~22:40Z Nov 14). 21.9 makes no Lane A edit | none |
| V2 | Stored-data shape `Mcp.ToolClassification.Changed` (`%Boolean`, initial 0, value 7, no migration) | Closed: approved ~02:00Z Nov 14 item 3; built by 22.15 (with the empty-value condition of ~05:30Z item 2) | none |
| V3 | AD-21 amendment S1 | Closed: S1 approved verbatim ~05:30Z Nov 14 item 2; written into the spine by 22.15 (:887, :890). 21.9's REST row note (:1805) records it | -- |

No open veto item. 21.9 adds no new public text, no stored-data change and no cross-lane edit (spec gate, 2026-11-15).

## Public text

Reused verbatim, accepted (no new text): `settings.toolChangedBanner`, "{tool} on {server} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below." (EXPERIENCE :1009, Core catalog :818-825, 35.2's proposal; reuse ruled fine ~02:00Z Nov 14). Also 21.4's "Unclassified (counts as risky)", "Refused: a built-in tool has this name" and "Saved". Online demo: none (T1 only).

## Verification

**How to run (lane C):**
- Run from the worktree root after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s9iw`, fresh `e21s9i` (QA `e21s9qw`/`e21s9q`, review `e21s9rw`/`e21s9r`).
- One command per foreground call, `timeout: 600000`, each sized to about 150 s; one test class per call (a large class one method per call). Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`.
- SettingsOps runs in the production, so after a mutation of `ListMcp`, run `ci/warm.sh down` then `up`. Tear down only this stage's tags.

**Shared surfaces:**
- The GET tool element: 4 -> 5 members. `SettingsMcp:TestList` :79 changes; `e2e/api/mcp.spec.ts` only types it; `listBody` in `e2e/settings/mcp.spec.ts` stays without it.
- `McpToolRow`. The `MCP_TEXTS` inventory (`ux-strings.test.mjs`).
- The Tool audit entries a real `ClearRow` writes, keyed by the test's own `zz` server.
- `^||ZzOps` nodes, which each test kills. The fixture server row's `RefusedTools`, on the test's own `zz` server.
- Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s9iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s9iw ci/iris.sh class OcuTalon.Test.Mcp.Tools` (once; confirms Task 0 (a)'s read) -- pass.
- `... class OcuTalon.Test.Core.SettingsMcp` (loop) -- pass. Mutations (Rule 19):
  - `ListMcp` leaves out `changed` -> `TestListChanged` red.
  - `ListMcp` copies it as a number (no `"boolean"`) -> red (`"changed":true`).
  - `ListMcp` sets `changed` from `classification = "unclassified"` -> red (`zz_new`).
  - `ListMcp` drops `changed` (or the row) for a refused tool -> red (`zz_shadow` must pass through).
- `... class OcuTalon.Test.Web.McpSettingsApi`, then `... class OcuTalon.Test.Msg.Catalog` (once each, one per call) -- pass.
- `node --test web/scripts/mcp-view.test.mjs web/scripts/ux-strings.test.mjs` (loop) -- pass. Mutations:
  - `changedTools` without the refused check -> red (the changed-then-refused row is kept).
  - `changedTools` keeps every unclassified row -> red.
  - One word of `MCP_TEXTS.toolChanged` changed -> red (`catalogText`).
  - `withoutChange` changes every row of the server -> red.
- `node --test web/scripts/initial-bundle.test.mjs` (once, after the web edits; about 20 s cold) -- pass (initial total at most 921 kB).
- `node --test web/scripts/` (once, the whole folder) -- pass.
- `cd web && npx tsc -p tsconfig.e2e.json --noEmit` (once) -- clean.
- `cd web && npm run build` (once) -- clean. "Initial total" equals Task 0 (c)'s, and only the MCP lazy chunk grew.
- `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh build` (once).
- `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh live sign-in-2 --part k/n` (once; the part whose PART line lists `settings/mcp.spec.ts`, n sized to about 150 s) -- pass. Mutations:
  - The banner's `@for` over every unclassified tool -> B14 red (`zz_new` banner).
  - The banner's `@for` over `changed === true` rows without `changedTools` -> B14 red (`zz_shadow` banner).
  - `withoutChange` not applied on the 200 -> B14 red (the banner stays after "Saved").
- `<vars> OCUTALON_RUN_TAG=e21s9iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s9i ci/iris.sh teardown` (once each, also after a failure).
- `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` (once each) -- pass.
- `python3 .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, after the REST row note) -- 10 low (the baseline).

**Manual checks:**
- (once) `grep -rn "mcp-view\|mcp-section" web/src/app --include='*.ts'` -- only `settings-page.ts`'s dynamic `import('./mcp-section')` and doc comments, so no static import pulls the banner into the initial bundle.
- (once) `git diff --stat <22.15's tip> -- src/ocutalon/cls/OcuTalon/Mcp src/ocutalon/cls/OcuTalon/Test/Mcp src/bridge` -- empty (no Lane A edit by 21.9).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Planned only. Spec gate passed 2026-11-15 after the refresh: the flag is on the branch (22.15), V1-V3 closed as approved, no open veto item, and the refused-tool ruling folded in. Implement starts with Task 0 (a)'s read check of 22.15's contract, and 21.9 merges only after 22.15 has merged.
- Ledger inbox: empty; DW-1355 answered by the ruling.
