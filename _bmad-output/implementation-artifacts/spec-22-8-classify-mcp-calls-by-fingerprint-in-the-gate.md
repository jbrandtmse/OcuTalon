---
title: 'Story 22.8: Classify MCP calls by fingerprint in the gate (part 1: the turn map, the gate''s MCP classification, removed servers, the in-turn clear and ToolsReadOnly)'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-2-classify-mcp-tools-by-server-and-name.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The gate classifies an MCP call only through the do-nothing `Classify(source, name)` of the `ClassificationClass` extension, which OcuTalon never sets. So an admin's classification (Story 22.2's `ToolClassification` rows) never reaches the gate. A read-only MCP tool can never be read-only, nothing checks that the tool is still the one the admin classified, and a call to a removed server's tool is held for approval instead of denied. `Decide.ToolsReadOnly` (U-282) also ignores attached MCP servers (DW-724).

**Approach:** Before `Chat`, the runner fingerprints each MCP tool from the serving manager's `%Discover()` and keeps the map in the bridge context. The gate asks a new extension method, `ClassifyMcp(source, name, fingerprint)`, which OcuTalon's new `OcuTalon.Mcp.Classification` (named in Decide's `ClassificationClass`) answers from the rows. A missing fingerprint, a missing row, `unclassified` or a changed fingerprint counts as unclassified. `read-only` is safe with readOnly 1, and `risky` is risky. A toolref that names no registered server is denied at once. A change found when the turn's map is built is cleared through `McpOps.ClearChanged`. `ToolsReadOnly` asks the new `McpServers.ToolsReadOnly(server)` for each listed server.

## Boundaries & Constraints

**Always:**
- Lane A files only (U-177): the bridge's `Context.cls`, `Adapter/Agent.cls` and `Policy/Gate.cls`. Footprint extensions: `Ext/Classification.cls`, `Ext/McpServers.cls` and `Process/Decide.cls`. Also `Mcp/**`, the Decide item in `Production.cls`'s Lane A region, `Test/{Mcp,Bridge}/**` and the Lane A Decide row in `Test/Install/Production.cls`.
- The bridge names no OcuTalon class (AD-2, AD-31). Callback code (the gate, and the classes it calls) names `%AI` on no code line and runs no Python (AD-6).
- The gate fails closed: an extension that throws, is not usable or gives a malformed answer means unclassified (held), never safe. An error from `ClearChanged` or from the turn-start check is one redacted warning and never changes a decision.
- An MCP classification is never trusted output (`trustedOutput` 0), so an allowed MCP call always taints the turn.
- Built-in tools are classified exactly as before. This holds on the online demo, and `Test.Bridge.Gate` and the demo-path tests stay green.

**Never:**
- Build `call_mcp_tool` or the gate's rewrite into it (22.3), the approval replay of an MCP call or `Approval.Cancel` on removal (22.4), source polls (22.5), the docs (22.6) or the attach and listing timeout (DW-1013, proposed 22.9).
- Edit `Core.SettingsOps`, `Core.CommandsIn`, `Web.*`, `web/**`, `Test/Contract/**` or any Lane B test. Write a Config Store entry or a wallet secret. Add a route, table, column, resource or grant.
- Read MCP annotations such as `readOnlyHint`. Use a real MCP server. Delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Map built | turn/decide/diagnose request; an `mcp:` spec in `Attached` | context node `mcp` holds `(toolref, name) -> Context.ToolFingerprint(description, parameters)` for every `%Discover()` entry whose `tool_ref` starts `mcp:`; not a FIELD; `Begin`/`End` clear it | `%Discover` throws: one warning, no map (all MCP calls unclassified) |
| Read-only | row `read-only`, its `Fingerprint` = map's | gate: `safe`, readOnly 1, trustedOutput 0, by `extension`; allowed in a user turn and in an untrusted or tainted turn; the turn is tainted after it | none |
| Risky | row `risky`, same fingerprint | `risky`: held (HELD) in a user turn, UNTRUSTED in an untrusted or tainted one | none |
| Unclassified | no row, or a row `unclassified` | unclassified: held / UNTRUSTED | none |
| Not in map | map has no `(toolref, name)` (no map; tool added after the map) | unclassified, even if the row says `read-only` | none |
| Changed (turn start) | classified row, map fingerprint differs | the runner's turn-start check calls `ClearChanged(server, tool, new)` once: row `unclassified` with the new fingerprint, Tool audit `unclassified`, one `mcp.toolChanged` per admin session; the gate then sees it unclassified | `ClearChanged` error: one warning; the gate still answers unclassified |
| Changed (gate) | the same mismatch reaches `ClassifyMcp` from the gate (turn-start clear failed) | unclassified; `ClearChanged` tried again; no second notice for one transition | as above |
| Removed / unregistered | toolref names no `Mcp.Server` row, or is not `mcp:remote:@{config:AI.MCP.OcuTalon_<name>}` | denied with `UNREGISTERED` before any privilege, provenance, hold or replay step: no approval row, no `turn.step`, no taint; the mock logs no `tools/call` | none |
| Extension fails | `ClassifyMcp` throws or the class is unusable | FAILED with one warning (as today) | fail closed |
| Bridge alone | default `ClassificationClass` | `ClassifyMcp` delegates to `Classify(source, name)`: `{classification, readOnly 0, registered 1}`; a missing fingerprint is still unclassified | none |
| ToolsReadOnly (DW-724) | `McpServersClass` lists servers | `Decide.ToolsReadOnly(runner)` is 1 only when its toolsets are read-only and `ToolsReadOnly(server)` is 1 for every listed server; no server: as before | any error or exception: 0 |
| Host ToolsReadOnly | `Mcp.Attach.ToolsReadOnly(server)` | 1 only when the row's `AttachStatus` is `attached` and every row not in `RefusedTools` is `read-only` (an attached server with no such row: 1); unavailable, never attached, unknown or empty: 0 | error: 0 |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `Decision` L158: classification L165, then privilege L166, untrusted L169 and replay/hold L170-174. The unregistered denial goes right after L165.
  - `ClassificationOf` L311: the MCP branch is L314. `FromExtension` L406 keeps `Classify` for class sources (L329).
  - Class doc L12-13, L28-30 ("an MCP tool" in the untrusted list) and L58-59 to restate. Sentences L72-84. `Source` L223 and `IsMcp` L526 stay unchanged (AC 8 of 22.2).
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `GRANT` node pattern L117-167 (outside FIELDS; `Begin` L70 and `End` L87 kill the global). 22.2 adds `ToolFingerprint(description, parameters)` over `ArgumentsHash` L172.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `ComposeTurnTools` L468 is the map's call site, after `BuildTurnManager` L482. That runs after `Context.Begin` L650 and covers the skills case at L503-506, where the agent's own manager serves.
  - `Attached` L123 (the mcp: specs); `AttachOne` L313 is the attach-time fingerprint (22.2, `GetToolStatuses`).
  - `BaseChars` L1155 already lists `%Discover()` per Converse. The class doc L23-31 is to extend. A `tool` request (replay) composes nothing L469.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `Classify` L15; the base gains `ClassifyMcp`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `Servers` L21, `OnAttach` L28; the base gains `ToolsReadOnly(server)`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` L11 -- `ClassFor("ClassificationClass" | "McpServersClass", "", "Decide", .sc)`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `ToolsReadOnly` L622, `ToolsetsReadOnly` L640, caller L691; class doc L114, `Retryable` doc L546.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` -- `ENTRYPREFIX` L11 and `Servers` L13 (the toolref form). `Mcp/Server.cls` `NAMEPATTERN` L12. 22.2's `Mcp/ToolClassification.cls` and `Mcp/Ops.cls` `ClearChanged(server, tool, fingerprint)`.
- `src/ocutalon/cls/OcuTalon/Production.cls` L20-25 -- the Decide item (Lane A region).
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` L904 -- the Decide oracle row.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls`:
  - MCP tests use `mcp:zzserver`: L405-463, TestMcpShadow L619, TestExtension L645, TestTaintFollowsTrustedOutput L1299-1325, TestRagNearMisses L1395-1398 and TestHeldRowNamesSourceAndRunner L1943.
  - `ZzGateClassification.cls` is the fixture.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` -- TestAccessorInAnotherJob L46-58 (L56 pins `ClassificationClass`), TestExtensionBases L180-214, TestContext L221.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls` -- TestToolsReadOnly L3471. `Test/Bridge/CodeRules.cls` -- `CALLBACKBASES` L73, `CALLBACKHELPERS` L82.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`:
  - Shadow runner `ZzTurnRunner` and adapter `Test/Bridge/ZzTurnAdapter.cls` (`TwoConfigs` L32, `AttachedSpecs` L25).
  - Helpers: `Use` L402, `Register` L428, `Spec` L477, `Leaks`, and TestAttach L104-139 (gate on the real toolref).
  - The mock `Test/Mcp/Mock.cls` gets the description override from 22.2.
- `irislib/%AI/ToolMgr.cls` (read only) -- `AddTool` L279 (string, JSON string and `%DynamicObject` specs), `%Discover` L460 and `GetToolStatuses` L492 each list again. `irislib/%AI/Tool/Resolver.cls` -- the URI and JSON forms (DW-174).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (DW-174) -- on the lane's warm throwaway, with scratch classes in package `ZzT8` (removed afterwards, as 35.1's Task 0 did), record in `_bmad-output/implementation-artifacts/evidence/22-8-task0-mcp-forms.md`:
  - For the loopback mock, compare `%Discover()` and `GetToolStatuses()`: whether each has `tool_ref`, `description` and `parameters`, and whether `Context.ToolFingerprint` agrees between them. If they disagree, or `%Discover()` has no `tool_ref`, build the map from `GetToolStatuses()` entries whose status is empty or `available`, and record why.
  - For each form, through a recording policy: the `toolref`, `call` and `metadata` that `%CanExecute` gets, and whether a shadowing copy runs. The forms are the remote form (measured in 35.1, evidence L93-99), the JSON configuration form (`AddTool` with a JSON string and with a `%DynamicObject`, pointing at the mock), and stdio (only through a scratch script in the container that speaks MCP; otherwise record it as unmeasured, with why, (inference)).
  - Rule: if a form reaches `%CanExecute` for an MCP tool with a `toolref` that does not start `mcp:`, extend `Gate.Source` to recognise it by the measured marker, before `origin_class`, and pin it in `Test.Bridge.Gate`. Otherwise `Source` stays unchanged.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `SetMcpTools(catalog As %DynamicArray) As %Status`: writes node `mcp` from each entry with an `mcp:` `tool_ref` (fingerprint `ToolFingerprint(description, parameters)`), replacing any earlier map; an error with no context. `McpFingerprint(source, name) As %String` returns "" when there is none. Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `ClassifyMcp(source, name, fingerprint) As %DynamicObject`. It answers `{"classification": safe|risky|"", "readOnly": 1|0, "registered": 1|0}`, or "" for none. The default is `{"classification": ..Classify(source, name), "readOnly": 0, "registered": 1}`. The doc states the contract: it is called inside the callback (AD-6), and a host may clear a changed tool from it.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ToolsReadOnly(server As %String) As %Boolean`, which returns 0 by default. The doc: 1 only when every tool of the server that a runner can call is classified read-only.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- in `ComposeTurnTools`, after a successful compose and when `Attached` holds an `mcp:` spec, a private `MapMcpTools()`:
  - It takes `%Discover()` (or Task 0's fallback) of `..Agent.ToolManager` and calls `Context.SetMcpTools`.
  - It then calls `ClassifyMcp` of `ClassificationClass` once per MCP tool. That is the turn-start check, outside every callback, and its answer is ignored.
  - Each failure is one redacted warning, and the request goes on.
  - Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - The MCP branch of `ClassificationOf` asks `ClassifyMcp(source, name, Context.McpFingerprint(source, name))`. `registered` exactly 0 gives `{classification "", readOnly 0, trustedOutput 0, by "", unregistered 1}`. An empty fingerprint gives unclassified. A valid answer gives `Classified(c, (c = safe) && readOnly = 1, 0, "extension")`. Anything else is unclassified.
  - `Decision` denies `unregistered` with the new `UNREGISTERED` sentence (see Public text) right after classification.
  - Restate the class doc (MCP readOnly, the unregistered step, the map).
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Classification.cls` (new, extends `OcuTalon.Bridge.Ext.Classification`) -- `ClassifyMcp`:
  - The server is `<name>` of exactly `mcp:remote:@{config:AI.MCP.`+`Attach.#ENTRYPREFIX`+`<name>}`, with `<name>` matching `Server.NAMEPATTERN`. Another form, or no `Mcp.Server` row, gives `registered` 0.
  - Then the `ToolClassification` row (server, name). No row, or `unclassified`, gives "".
  - A non-empty fingerprint that differs from a `read-only` or `risky` row gives "" and calls `Mcp.Ops.ClearChanged(server, name, fingerprint)` in a Try (error: one warning).
  - `read-only` gives `{safe, 1, 1}`; `risky` gives `{risky, 0, 1}`.
  - It reads only, apart from the clear. `Classify` stays the base default ("").
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` -- only if 22.2's `ClearChanged` does not do so already: re-read the row under its lock and change nothing when it is already `unclassified` with that fingerprint, so concurrent clears send one notice.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` -- `ToolsReadOnly(server)` per the matrix (rows read through SQL or the indexes; no write).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `ToolsReadOnly(runner)`:
  - It also requires that every server `McpServersClass` lists (`ClassFor` on Decide; `Servers`) gives `ToolsReadOnly(server)` = 1.
  - Any error or exception gives 0.
  - Update the docs at L114, L546 and L618-621.
- [ ] `src/ocutalon/cls/OcuTalon/Production.cls` and `Test/Install/Production.cls` -- the Decide setting `<Setting Target="Host" Name="ClassificationClass">OcuTalon.Mcp.Classification</Setting>` and its oracle entry.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add to `CALLBACKHELPERS` the classes that the gate's call now reaches: `OcuTalon.Mcp.Ops`, `.ToolClassification`, `.Server`, `.Attach`, `OcuTalon.Bridge.Audit`, `OcuTalon.Core.NoticesIn`, plus any further class `ClearChanged` calls. Update the doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` and `ZzGateClassification.cls`:
  - Tests that expect a classified MCP tool set the map with `Context.SetMcpTools`.
  - New rows: read-only MCP allowed in untrusted and tainted turns and tainting; a missing fingerprint; `registered` 0 gives UNREGISTERED with no row and no step, replay included; a malformed answer is unclassified; built-ins unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` -- L56 becomes `OcuTalon.Mcp.Classification|1`; base defaults of `ClassifyMcp` (delegation) and `ToolsReadOnly` (0); `SetMcpTools`/`McpFingerprint`, and cleared by `Begin` and `End`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls` -- `TestToolsReadOnlyMcp` with a fixture `McpServersClass` (all read-only: 1; one not read-only: 0; `Servers` error: 0; none: as before).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Classification.cls` (new) -- every host row of the matrix, plus `Attach.ToolsReadOnly`. Fixture rows go through 22.2's `McpOps` methods where they exist. Every fixture is removed, and the class asserts that none is left.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` -- integration with the shadow runner, `McpServersClass` `Mcp.Attach`, `ClassificationClass` `Mcp.Classification` and the mock:
  - `TestReadOnlyTurn`: zz_lookup classified `read-only`; a composed turn; `ExecuteTool` in an untrusted context runs it (the mock logs `tools/call`), while zz_delete_ticket is denied.
  - `TestChangedInTurn`: the mock's override changes zz_lookup's description; the next composed turn leaves the row `unclassified` with the new fingerprint, writes one Tool audit entry and one notice per fixture admin session, and the call is held.
  - `TestRemovedServer`: the server is removed through `McpOps` after the turn's map is built; the call is denied UNREGISTERED and the mock logs no `tools/call`.
  - `Leaks` empty.

**Acceptance Criteria:**
- [RULED 2026-11-11, Contest Planner ruling on Story 22.4's veto, condition 2(a), applied here because 22.8 implements first] Given Story 22.2's `OcuTalon.Bridge.Context.ToolFingerprint`, when this story is done, then the fingerprint is SHA-256 hex (64 characters) over a canonical form (sorted keys) of the server id, the tool name, the input schema AND the description; the attach report, `ToolClassification.Fingerprint` and the turn map all use it; 22.2's tests that pin a 44-character value are updated to 64; and a test that changes ONLY a tool's description (same name, same schema) shows the classification cleared and the call held or denied. On an existing dev install every classified row reads as changed once and is cleared (no release carries 22.2's old form).
- [RULED 2026-11-11, Contest Planner condition (1)] Given a tool classified `read-only` whose server then changes that tool's description (and, in a second case, its input schema) under the same name, when the next request calls it, then the call's fingerprint no longer matches the classification's, the row is `unclassified` (audited, one `mcp.toolChanged` notice per admin session), and the call is held for approval in a user's turn and denied in an untrusted or tainted turn; it never runs as read-only. (Rug-pull test, in `Test.Mcp.Attach` or `Test.Bridge.Gate`, with a named mutation: skip the call-time fingerprint comparison -> red.)
- Given a runner turn composed with a registered server whose zz_lookup an admin classified `read-only`, when the model's call reaches the gate in an untrusted turn, then it runs and taints the turn, and zz_delete_ticket (unclassified) is denied.
- Given a classified tool whose description the server changed after the build, when the next turn's map is built, then the row is `unclassified` with the new fingerprint, one Tool audit entry and one `mcp.toolChanged` notice per admin session exist, and a call to it in a user's turn is held.
- Given a server removed through `McpOps` while a runner still lists its tools, when a call to one of them reaches the gate (a replay included), then it is denied with `UNREGISTERED`, no approval row or step exists, and the server gets no `tools/call`.
- Given `McpServersClass` lists a server with any tool that is not read-only (or one it cannot vouch for), when a decide or diagnose times out, then `Decide` does not retry it (`ToolsReadOnly` 0); with no server, the retry rule is unchanged.
- Given an online-demo install, when its built-in tools are called, then every gate decision is as before (`Test.Bridge.Gate` and the demo-path tests stay green).
- Given Task 0's evidence file, when the reviewer reads it, then each MCP form is measured or marked unmeasured with why, and the gate recognises every measured form as MCP before `origin_class`.

## Spec Change Log

- 2026-11-11 (runner): the Contest Planner's 22.4 ruling, condition 2(a), redefines the fingerprint (SHA-256 hex over server id, tool name, input schema and description); added here as an AC because 22.8 implements before 22.4 and compares fingerprints at call time. Source `<coordination>/prompts/epic-22-rulings-224.md`.

- 2026-11-11 (runner, rulings applied): the Contest Planner's rulings (verbatim under Design Notes) are applied. Veto items accepted as AD-10 allows, with condition (1) added as an AC (call-time fingerprint match, rug-pull test) and condition (2) routed to Story 22.6's gate. `UNREGISTERED` approved verbatim: the implement stage uses it (not `FAILED`). Unknown or removed servers denied, not held: accepted. Spine S4-S7 written (AD-10 "MCP classification by fingerprint", AD-31 extension bullet).

- 2026-11-11 (runner, spec gate): the split proposal is accepted (unattended decide U5): Story 22.9 "Bound MCP attach and listing with a timeout" is inserted in epics.md, planned after this story, and DW-1013 is re-owned to it. The Veto items, the proposed `UNREGISTERED` text and spine updates S4-S7 go to the Contest Planner (via the orchestrator) before the implement stage; this story implements only after Story 22.2 is committed.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: the bridge names no host class.
- AD-6: callback code has no `%AI` and no Python; the turn-start check runs outside callbacks.
- AD-8: the retry rule.
- AD-10: the gate; the map; unclassified counts as risky; only read-only tools run in tainted turns; no trusted MCP output.
- AD-17: audit through `ClearChanged`.
- AD-21: MCP listing, changes and removal.
- AD-22: the loopback mock.
- AD-25: the online demo.
- AD-29: lanes.
- AD-31: the `ClassificationClass` and `McpServersClass` contracts.
- AD-32: the `mcp.toolChanged` notice.
- AD-33: `McpOps` is the sole writer.

**Decided in-stage:**
1. One extension call per MCP check, `ClassifyMcp`, which answers the classification, readOnly and registration together, so that an admin's change between two calls cannot mix them. The default delegates to `Classify`, so a bridge-alone extension keeps working (Rule 2: extends the base, no copy).
2. A removed or unknown server is denied, not held: a hold could be approved and replayed against a server that is gone. Registration comes from the host's rows. The bridge alone (default) never denies.
3. The map is built in `ComposeTurnTools` from the manager that serves the request, so the skills case is covered. A `tool` request (replay) has no map, so its MCP call is unclassified, which a grant does not need.
4. A change is found at turn start, outside callbacks. The runner asks `ClassifyMcp` for each MCP tool, so the row write, audit and notices normally happen in the runner's job. The gate's own call repeats the clear only if that failed. `ClearChanged` runs only for a classified row and a non-empty fingerprint.
5. A missing fingerprint means unclassified, whatever the row says (AD-10: "missing from the map").
6. `read-only` maps to safe with readOnly 1. So a read-only MCP tool now runs in an untrusted or tainted turn (AD-10 rule 3, runner note 1). It still taints, because MCP output is never trusted.
7. `ToolsReadOnly(server)` is fail-safe. An unavailable or never-attached server gives 0, because no runner's attach state is known to Decide. Refused tools are ignored, because they never run.
8. The bridge guide's extension bullets for the two new methods are left to Story 22.6 (it documents 22.8). The guide's current lines stay true, and no pinned line changes.

**Extend, don't copy (Rule 2):**
- `ClassifyMcp` extends `Classify`, and `SetMcpTools`/`McpFingerprint` follow `Context`'s grant node.
- The fingerprint is 22.2's `ToolFingerprint`, not a second hash.
- `ToolsReadOnly(server)` extends `McpServers`.
- `Decide.ToolsReadOnly` is extended, not copied.
- The turn-start check reuses `ClassifyMcp` rather than adding a hook.

**Integration ACs (Rule 1):**
- Consumer: the real runner adapter (shadow runner) with `Mcp.Attach`, `Mcp.Classification` and the mock. Its gate allows, holds or denies per AC 1-3 (`Test.Mcp.Attach`).
- Consumer: `Decide.TryRetry` reads `ToolsReadOnly` (AC 4, `Test.Bridge.Decide`).

**Consumes:**
- 22.2: `ToolClassification` rows with `Fingerprint`, `Context.ToolFingerprint`, `McpOps.ClearChanged` and its remove command, the mock's description override, and the notice seam.
- 35.1: `Mcp.Attach`, the mock, the shadow-runner fixtures.
- 3.2: the gate; 17.2 R2: `ToolsReadOnly`.

**Consumed-by:**
- 22.3: the proxy rewrite applies only to calls that this classification allows, and a direct `call_mcp_tool` is classified through `ClassifyMcp` with the server's toolref form.
- 22.4: held MCP calls; a replay has no map.
- 22.5: a poll is a `tool` request with no map, so 22.5 must give the poll's call a fingerprint (for example, from its own listing) or every poll is unclassified.
- 22.6: documents `ClassifyMcp`, `ToolsReadOnly` and `UNREGISTERED`.
- 22.9 (proposed): the bounded listing that `MapMcpTools` also calls.

**Ledger inbox (Rule 17):**
- DW-174: addressed by Task 0 and its gate rule.
- DW-724: addressed by the `Decide.ToolsReadOnly`, `Ext.McpServers` and `Mcp.Attach` tasks, and AC 4.
- Declined DW-1013: moved whole, with the 2026-11-09 amendment line, to the proposed Story 22.9 (split below). It is independent of classification (the adapter's `AddTool` and listing), needs its own throwaway Task 0 (a mock that accepts and never answers, which can block a native `$ZF` call) and may need an OcuTalon probe. `MCPDescriptor` takes no timeout key (L16-59).

**Split proposal (runner note 6; for the runner's ruling).** This spec plans part 1. Proposed **Story 22.9, "Bound MCP attach and listing with a timeout"** (the second child of the original 22.2), planned after 22.8. It receives DW-1013, the `[AMENDED 2026-11-09 … DW-1013]` line, the "accept and never answer" mock mode and the clear-error text (`mcp.serverUnavailable` if it reaches admins). Nothing is dropped.

**Footprint extensions (U-177, Lane A):** `Bridge/Ext/Classification.cls`, `Bridge/Ext/McpServers.cls`, `Bridge/Process/Decide.cls`.

**Spine updates for the lead (Rule 20):**
- S4 (AD-31): `ClassificationClass` gains `ClassifyMcp(source, name, fingerprint) As %DynamicObject` (`classification`, `readOnly`, `registered`; default from `Classify`, readOnly 0, registered 1). OcuTalon names `OcuTalon.Mcp.Classification` on Decide.
- S5 (AD-31, AD-8): `McpServersClass` gains `ToolsReadOnly(server) As %Boolean` (default 0). `Decide.ToolsReadOnly` requires it for every listed server (DW-724).
- S6 (AD-10 rule 1): the context node `mcp` holds the turn's map, built in `ComposeTurnTools` from the serving manager. A tool missing from the map is unclassified. An admin's `read-only` is safe with readOnly 1 and never trusted output.
- S7 (AD-10, AD-21 Changes): a toolref whose server the host does not register is denied with `UNREGISTERED` before every other step, replays included. A changed fingerprint is found at turn start (and again at the gate) and cleared through `McpOps.ClearChanged`.


**Contest Planner rulings (verbatim)** [RULED 2026-11-11 ~13:40Z, Contest Planner under the owner's delegation, relayed by the orchestrator; source `<coordination>/prompts/epic-22-rulings-222-228-229.md`]:

> # Rulings, Epic 22 spec gate: 22.2, 22.8, 22.9 (2026-11-11 ~13:40Z; Contest Planner under the owner's delegation; verbatim terms)
> SPLIT ACCEPTED (22.8, 22.9 new; order 22.2, 22.8, 22.9, 22.3-22.7; DW-1041 respected). No More to try or README line (no UI, MCP off on the demo); 22.6's governance doc carries the public explanation later.
> PUBLIC TEXT 1-9: APPROVED verbatim.
> VETO 22.2: ACCEPTED: ToolClassification (no URL, secret or user), McpOps present on the demo refusing every MCP verb, the admin notices.
> CONDITION on the run-time resource OcuTalon_MCP_<server> and its U grant: state in the spec exactly which process creates the resource and grant, and with what privilege. The service role (and McpOps' job) must NOT gain %Admin_Secure, %All or any security-administration privilege to do it. Acceptable: the installer step declares them at start, or one fixed privileged entry point that can only create/grant/remove OcuTalon_MCP_* resources and is unit-tested to refuse any other name. If the design needs a broader privilege on a production job, STOP for a ruling before implementing.
> VETO 22.8: ACCEPTED as AD-10 already allows it, with two conditions:
> (1) the tool's fingerprint must match its classification at call time (a changed fingerprint makes it Unclassified, so it's held or denied as such); test that a rug-pull (same name, changed schema or description) is caught.
> (2) 22.6's governance doc must say plainly that a Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads. Bring that sentence to the Planner at 22.6's gate.
> Unknown/removed servers denied, not held: ACCEPTED.
> VETO 22.9: ACCEPTED (2 s initialize probe to admin-registered servers only, the 60 s rest, no MCP server on the agent's own manager, side effects as listed).
> RESIDUAL: (a). Accept it now; 22.6 documents it; the AD-21 amendment (OcuTalon lists and offers MCP tools through its own bounded client) becomes a NEW story in Epic 22's backlog, after 22.7.
> GRAPH: lift 36.1's epic-22 wait entirely, plain-union rule for the Checks and BackgroundCheck files 22.5 also touches, marker [AMENDED 2026-11-11, Contest Planner ruling: footprint only, not a real dependency].
> NEXT-FREE-LANE ORDER: (1) the memory-documents-remember phrase fix (DW-1123, ~30 min), (2) 36.1, then the step-5 chain (36.2, 37.1, 24, 23.4, 23.8; 23.3's plan to the Planner first), (3) 25.3.
> ORCHESTRATOR U7 spine wording S1-S11: fine under these conditions.

**How this spec meets the 22.8 conditions** (runner, 2026-11-11): (1) the gate checks at EVERY MCP call, through `ClassifyMcp`, that the call's fingerprint (the turn map's, from the listing of the manager that serves this request) equals the fingerprint the row's classification was given for; any mismatch is unclassified, so the call is held in a user's turn or denied in an untrusted/tainted one. A rug-pull test (same tool name, changed description, and separately changed input schema, between two requests) shows the row cleared and the call held or denied. A change inside one request, between the listing and the call, is caught by Story 22.3's governed proxy, which re-lists the tool with its own client just before `tools/call` and refuses a changed fingerprint (added to Story 22.3's block in epics.md by this ruling). (2) The sentence that a Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, is Story 22.6's, brought to the Planner at 22.6's gate (noted in 22.6's block). `UNREGISTERED` (text 9) is approved verbatim.

## Veto items

- **Gate posture.** A tool an admin classified Read-only (fingerprint unchanged) now runs in an untrusted or tainted turn (before, every MCP call there was denied). Its result taints. A removed or unknown server's tool is now denied rather than held.
  - Online demo: no MCP server can exist, so nothing changes.
- **Shared production setting.** Decide's `ClassificationClass` becomes `OcuTalon.Mcp.Classification`. It classifies no class-sourced tool (its `Classify` returns ""), so built-ins are unchanged.
  - Online demo: present. Every MCP toolref is unregistered there.
- **Extension contracts (AD-31 amendment).** `ClassifyMcp` and `McpServers.ToolsReadOnly` (S4, S5).
- No new privilege, resource, grant, table, column, retention, outward action or web dependency.

## Public text

**New, proposed** (model-facing gate sentence, a parameter of `OcuTalon.Bridge.Policy.Gate`, shown after AI Hub's "Tool access denied: " and in the trace). The implement stage uses it only after the runner records it accepted. Until then, the call is denied with `FAILED`:

| Parameter | Text |
| --- | --- |
| `UNREGISTERED` | "this tool's MCP server is not registered, so nothing was run." |

**Already given verbatim:** the key `mcp.toolChanged` (accepted in 35.1), sent by `ClearChanged`, and the gate sentences `HELD`, `UNTRUSTED` and `FAILED`.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`. Use the warm stack: `OCUTALON_RUN_TAG=e22s8iw ci/warm.sh up` once (check `ci/warm.sh status` first), `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s8iw` on each class call, and `ci/warm.sh down` at the end, even after a failure. Run one call at a time in the foreground with `timeout: 600000`, one class per call.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Decide` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.CodeRules` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Classification` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: passed (needs the production; warm stack)
- (loop) `ci/iris.sh class OcuTalon.Test.Install.Production` -- expected: passed
- (loop) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

No `(once)` lines. The full suite is left to CI (`shard:lane-a@Bridge` in `shards-9`; the Mcp and Install areas in `shards-2` and `shards`), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- Decide's extension settings (`Test.Bridge.Ext` L56, the `Test.Install.Production` oracle);
- the gate's MCP decisions (`Test.Bridge.Gate`'s `mcp:zzserver` rows, `Test.Mcp.Attach` TestAttach);
- the `Ext.Classification` and `Ext.McpServers` bases (`Test.Bridge.Ext` TestExtensionBases);
- `Decide.ToolsReadOnly` (`Test.Bridge.Decide` TestToolsReadOnly, which reads the `Mcp.Server` rows);
- `CALLBACKHELPERS` (`Test.Bridge.CodeRules`);
- the `ToolClassification` and `Mcp.Server` rows and admin notices (the `Leftovers` checks of `Test.Mcp`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to record (Rule 19):** each mutation should turn the named test red.

| Mutation | Test that goes red |
| --- | --- |
| `ClassificationOf` ignores an empty fingerprint | the Gate missing-fingerprint row |
| Drop the `readOnly` pass-through | `TestReadOnlyTurn` |
| Skip the unregistered denial | `TestRemovedServer` and the Gate replay row |
| Skip the fingerprint compare in `ClassifyMcp` | `TestChangedInTurn` |
| Remove the turn-start check | `TestChangedInTurn` (no notice before a call) |
| Drop the MCP part of `ToolsReadOnly` | `TestToolsReadOnlyMcp` |
| Remove the production setting | `Test.Install.Production` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
