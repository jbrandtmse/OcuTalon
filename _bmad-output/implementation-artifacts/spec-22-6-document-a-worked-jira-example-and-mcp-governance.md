---
title: 'Story 22.6: Document a worked Jira example and MCP governance'
type: 'feature'
created: '2026-11-13'
status: 'done'
baseline_revision: '1548802e8679103dd73119d7de18eb48f9a8ea66'
baseline_commit: '1548802e8679103dd73119d7de18eb48f9a8ea66'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-3-call-mcp-tools-only-through-the-governed-proxy.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-4-hold-risky-and-unclassified-mcp-calls-for-approval.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A server tool that has the name of a tool of only some agents (for example the Diagnosis agent's read_event_log) is refused by those agents' runners and not by the others, so Mcp.Server RefusedTools and the mcp.toolShadowsBuiltIn notice may follow whichever runner reported last (inference).
    evidence: |-
      Adapter/Agent.cls AttachServers L338 and OfferServers L699 take the refused names from the manager being built (ToolNames), and every runner (ChatAgent, the diagnosis and triage runners) attaches every server (Mcp.Attach.Servers lists all rows). Mcp.Ops.RecordAttach keeps the latest report per server. Not measured; no story owns it.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:AttachServers
    severity: medium
---

<intent-contract>

## Intent

**Problem:** OcuTalon now governs MCP tools (22.2, 22.8, 22.9, 22.3, 22.4), but nothing tells an admin how to connect a server, and the security overview still opens its MCP section with "This release can't connect to MCP servers." The bridge guide's MCP bullet describes the attach that 22.9 replaced. The ledger adds three items:
- DW-950: the bridge guide lacks the approved turn-tool sentence.
- DW-1221: no text states the measured time limit.
- DW-1228: a server tool named `call_mcp_tool` is refused on no path today. On a request's manager the server's tools are added before the proxy, so the server's tool can shadow the governed proxy (code reading, and 22.10 Task 0(5): the first tool registered wins).

**Approach:**
- **The worked example.** A new `docs/mcp-jira-example.md` covers adding a Jira MCP server with a `secret://` IRIS Wallet credential, classifying its tools, running a read-only search, approving a held risky call, the governance rules, and the time limits.
- **The security overview.** Its MCP section, Data line and audit lines are rewritten, and the generator adds the per-server resource sentence to the privileges section.
- **The bridge guide.** It gains the DW-950 sentence and a current McpServers bullet.
- **Doc checks.** The `overviewdoc` rule and the bridge guide's `turntools` rule pin the new text.
- **DW-1228.** A narrow fix in `Bridge/Adapter/Agent.cls`: the proxy is registered before the first server's tools, and `call_mcp_tool` counts as a built-in name. A test pins both.
- **The source-poll part moves out (split, V2).** The source poll ("new tickets assigned to me") and the digest's Jira entry depend on 22.5, 22.11 and 21.5, none of which is built yet, so they move to a new Story 22.12.

## Boundaries & Constraints

**Always:**
- **Lanes (U-177).** Lane A files only:
  - `docs/mcp-jira-example.md` (new), `docs/security-overview.md` and `docs/bridge-guide.md`;
  - `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` and `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls`;
  - `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` and `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` (its doc only);
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` (new Test methods only);
  - `docker/tests/test-release-sequence.sh` (the `overviewdoc` rule only) and `docker/tests/test-bridge-guide.sh` (the `turntools` rule only).
- **Text.** Ship only the text of `## Public text`, verbatim. Every product sentence that the docs quote is already in the code or accepted:
  - the catalog: `toolCall.requestOnServer`, `mcp.toolShadowsBuiltIn`;
  - `Gate.MCPLABEL` and `Mcp.Ops` `MESSAGENAME`;
  - Story 21.4's approved T4, T5 and T8, and the epics' radio labels.
- **Honesty.** No text claims a hard MCP deadline. The time-limits paragraph is the same, word for word, in the worked example and in the overview. It states the per-read limits, the measured 31 s and 36 s, and the mid-request residual (AD-21 S11).
- **Ruling F(2).** No text describes the changed-tool replay path: an approved request whose tool changed before it ran, `mcp.replayToolChanged`. The call-time check before every call (22.3, 22.8) may be described.
- **Shared sentences.** The classification sentence and the Read-only sentence are the same, word for word, in the worked example and in the overview's MCP section.
- **Online demo.** Every doc says MCP servers are off there. The DW-1228 fix runs only when a server is recorded, so on the demo, which records none, nothing changes. `Test.Mcp.Attach` `TestDemoOffersNoProxy` stays green.
- **DW-1228's invariants.**
  - On a request's manager, `call_mcp_tool` is always the governed proxy.
  - A request with no MCP server whose probe answered and whose tools were added offers no proxy. This is 22.3's rule, unchanged.
  - A server whose tools list contains `call_mcp_tool` keeps its other tools.

**Never:**
- Edit `GUIDE.md`, `README.md`, `release/**`, `web/**`, `src/ocutalon/cls/OcuTalon/Demo/Features.cls`, `Mcp/Ops.cls` or any Lane B file or test. GUIDE.md lines and the More to try item are proposals only (`## Contended edits`).
- Describe source polls, the digest's source entries or the "Use as a source" form (Story 22.12, V2).
- Name a real third-party server, URL, account or token. The example address is `example.com`.
- Change `Mcp.Client`'s limits, or claim a total or hard deadline.
- Delete, skip or shorten a test (the switch-gated `overviewdoc` controls are replaced, not dropped: Tasks).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Proxy-named server tool | the mock lists `zz_lookup` and a tool named `call_mcp_tool`; a request's manager is composed (shadow runner) | the request's `call_mcp_tool` is the governed proxy: a `call_mcp_tool {server, tool: zz_lookup}` call runs `Mcp.Proxy` (one `MCP` `called` entry), and the mock logs no `tools/call` named `call_mcp_tool`; `zz_lookup` is still offered | none |
| Proxy-named tool reported | the same server attaches | the report lists `call_mcp_tool` in `refused`; `Mcp.Server.RefusedTools` holds it; `Tools(server)` gives it status `refused`; admins get one `mcp.toolShadowsBuiltIn` {server, tool} notice; its row's fingerprint is empty | none |
| Agent's own name | the mock lists a tool named like one of the agent's own tools | refused as today (`TestShadow` unchanged) | none |
| No answering server | probe fails, or `AddTool` fails for every server | the request's manager offers no proxy and no MCP tool (22.3's rule) | one warning, as today |
| Online demo | demo flag on | no server is listed, probed or offered, and no proxy is offered | none |
| Docs | `docs/security-overview.md`, `docs/mcp-jira-example.md`, `docs/bridge-guide.md` | the `overviewdoc` and `turntools` rules pass; each fault fixture gives its own complaint | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `AttachServers` L323. `builtin = ..ToolNames(agent.ToolManager)` L338 is passed to `AttachOne`, and `ReportOf` L398-399 pushes a name found in `builtin` into `refused`.
  - `OfferServers` L698-735+. `builtin = ..ToolNames(manager)` L699. `manager.AddTool(spec)` L712 runs before `OfferProxy(manager)` L728-729, which is called once, after the first server was added. A `0` from it makes `BuildTurnManager` build a manager with no MCP server (the class doc of `OfferServers`).
  - `ToolNames` L445-457. `ProxyManager` L766-786, the replay manager, is unchanged.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` -- `MCPPROXY` (the name `call_mcp_tool`, a bridge constant, so AD-2 holds), `IsProxyCall` L405-408, `Reroute` L425-431 (every allowed native MCP call is renamed to `call_mcp_tool`, which is why a shadowed proxy matters), `MCPLABEL` L141 "Running {tool} on {server}".
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- class doc L8-30. The `refused` sentence L10-11 gains the proxy name. The `ServerOf` paragraph L27-30 still says "counts as unclassified: it is held"; ruling F(1) (22.4) made it DENIED, and the doc is corrected to match.
- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls` (read only; contended) -- `RecordAttach` handles any `refused` name generically: a row with an empty fingerprint (L421-424) and `Notify` `mcp.toolShadowsBuiltIn` L445. No edit is needed.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`:
  - `TestShadow` L268 (the attach-report sibling) and `TestTurnShadow` L1088 (the request-manager sibling);
  - `TestDirectCall` L1262 and `TestProxyRewrite` L1104 (a call through `call_mcp_tool` with `zz_lookup`);
  - `TestDemoOffersNoProxy`;
  - helpers `Register(extra, live)` L1658, `Entry` L1670, `Leaks` L1930.
  - `Test.Mcp.Mock.Start(.port, extra, …)` (Mock.cls L9-10, L64) adds one tool per name in `extra`.
  - The class takes about 165 s alone on the warm stack (22.4).
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls`:
  - `ONLINESTATEMENT` L35, the fixed-sentence precedent; `PrivilegesText` L397-431 (the Roles table, then "### With demo mode on" L413).
  - `Install/Step/Mcp.cls` `RESOURCEPREFIX` L13 and `PERMISSION`, and `Install/Step/Users.cls` `#SERVICEROLE`.
- `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls` -- `TestFixKindRows` L274 (the ONLINESTATEMENT pin L314-316), `TestRoleRowsDeclaredBy` L364, `TestAscii` L491.
- `docs/security-overview.md`:
  - the generated regions L5-112;
  - "Approval and audit" audit types L148-154 and the Pairing/MCP/Tool sentence L156;
  - the Data line "In calls to configured MCP servers, which this release can't make." L188;
  - "## MCP tools" L201-212;
  - the Online demo line L225 ("allow-listed MCP traffic when the demo has them") stays unchanged: still true, and Epic 29's surface.
- `docs/bridge-guide.md` -- the TurnTools bullet L316 and the McpServers bullet L317, both ruled lines pinned by `docker/tests/test-bridge-guide.sh` `turntools` L641-695 (the pinned copies at L647-650).
- `docker/tests/test-release-sequence.sh` `overviewdoc`:
  - the header comment L32-38;
  - `ovw_section`, `ovw_phrases` and `OVW_LIMITS` L2166-2188;
  - `ovw_doc_problems` L2193-2264: the two `git grep call_mcp_tool` switch blocks L2222-2228 and L2257-2259;
  - `ovw_doc_problems_no_mcp` L2278-2285;
  - `t_overviewdoc` L2287+: the switch controls L2316-2326 and L2343-2350.
  - The checker forbids `://` and IP addresses in the overview, so the worked-example link is relative.
- Measured facts:
  - `Mcp/Client.cls` `PROBESECONDS = 2` L22 (connect, the answer, the initialize and each `tools/list`) and `CALLSECONDS = 20` L25, set per read: `Open` L135-137.
  - The 31.1 s and 36.1 s are from 22.10 Task 0 item 6, lane D warm throwaway `e22s10pw`, one byte a second, recorded in spine AD-21 S11 L97.
- Accepted text the docs quote:
  - `Msg/Catalog/Core.cls` L602 `toolCall.requestOnServer` and `Watch.cls` L1052 `mcp.toolShadowsBuiltIn`;
  - `Mcp/Ops.cls` L49 `MESSAGENAME`;
  - 21.4's approved T4, T5 and T8 (`OCT-epic21`, `spec-21-4` `## Public text`; Planner rulings B, 2026-11-12) and the epics' radio labels (21.4's AC).

## Tasks & Acceptance

**Execution:**
- [x] **Task 0** (implement stage; lane D warm throwaway `e22s6iw`). Record the answers in `_bmad-output/implementation-artifacts/evidence/22-6-task0-proxy-name.md`:
  1. With the current code, a shadow-runner request whose mock server also lists `call_mcp_tool` (`Register($ListBuild("call_mcp_tool"), 1)`): record what the request's manager offers under that name, which code runs for `call_mcp_tool {server, tool: zz_lookup}`, and whether `AddTool` or `OfferProxy` returns an error.
  2. The same after the fix: `AddTool` succeeds, and the server's `call_mcp_tool` shows `unavailable` in the tool statuses.
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- DW-1228:
  - `AttachServers` and `OfferServers` append `##class(OcuTalon.Bridge.Policy.Gate).#MCPPROXY` to `builtin`, but only when the host names a proxy (a non-empty `ProxyToolSet()`; the bridge alone is unchanged).
  - In `OfferServers`, the proxy toolset is registered on the manager before the first server's `AddTool`. A request in which no server's tools were added still ends with no proxy: `OfferServers` gives 0, so that `BuildTurnManager` builds its manager with no MCP server.
  - Update the method and class docs.
- [x] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- class doc only. The `refused` sentence names the proxy's name too. The `ServerOf` paragraph says, per ruling F(1), that a toolref that gets `""` is denied and never held or run.
- [x] `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` -- new methods, each creating and removing its own `zz` server and rows:
  - `TestProxyNameRefused`, a sibling of `TestShadow`: the report's `refused`, `RefusedTools`, the `refused` status from `Tools(server)`, one `mcp.toolShadowsBuiltIn` notice, the empty fingerprint.
  - `TestProxyNameNotShadowing`, a sibling of `TestTurnShadow` and `TestDirectCall`: the request's `call_mcp_tool {server, tool: zz_lookup}` runs the governed proxy, with one `MCP` `called` entry and the mock's `tools/call` naming `zz_lookup`, never `call_mcp_tool`. `zz_lookup` is still offered, and the no-secret scan passes (`Leaks`).
- [x] `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- new `Parameter MCPSTATEMENT`, the P4 sentence. `PrivilegesText` emits it after the Roles table, built from `Install.Step.Mcp` `RESOURCEPREFIX` and `PERMISSION` and `Install.Step.Users` `SERVICEROLE`, so that it cannot drift. Update the class doc.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls` -- new `TestMcpResourceStatement` (the shape of `TestFixKindRows`' ONLINESTATEMENT pin): the privileges text holds the P4 sentence once, word for word, after the Roles table and before "### With demo mode on".
- [x] `docs/security-overview.md`:
  - the hand-written edits P2, P3 and P5;
  - the generated privileges region regenerated with `ci/iris.sh live security-overview --write` (Verification), never edited by hand.
- [x] `docs/mcp-jira-example.md` -- new, exactly P1.
- [x] `docs/bridge-guide.md` -- the TurnTools bullet L316 becomes P6, and the McpServers bullet L317 becomes P7.
- [x] `docker/tests/test-bridge-guide.sh` -- the `turntools` pinned copies of those two lines (L649-650) become P6 and P7. Update the header comment L26-27.
- [x] `docker/tests/test-release-sequence.sh` `overviewdoc`:
  - **Drop the switch.** Remove both `git grep call_mcp_tool -- src` switch blocks from `ovw_doc_problems`, `ovw_doc_problems_no_mcp`, and the four switch-dependent controls with their two forced-off controls. `src` now always holds the proxy, so the switch can only hide the new checks.
  - **New checks in `ovw_doc_problems`, each with one problem line:**
    1. The MCP tools section holds no "can't connect to MCP servers" and no "When a release adds MCP support".
    2. It links `](mcp-jira-example.md)`.
    3. It holds the classification sentence (P1/P2, held in a new `OVW_MCP_RISKY`) and the Read-only sentence (`OVW_MCP_READONLY`), each word for word.
    4. It holds the time-limits paragraph (`OVW_MCP_LIMITS`) as one whole line.
    5. The Data section holds no "this release can't make".
    6. Outside `OVW_MCP_LIMITS`, the file holds no line with "deadline" (case-insensitive).
    7. No line matches `replayToolChanged|after this request was made|needs a new approval` (F(2)).
  - **New `mcp_doc_problems <file>` for the worked example:**
    - its title line is P1's;
    - it is ASCII only and has no machine path;
    - every `http://` or `https://` in it is followed by a host that ends in `example.com` (`secret://` is no address);
    - it holds `OVW_MCP_RISKY`, `OVW_MCP_READONLY` and `OVW_MCP_LIMITS` word for word, with no other "deadline" line;
    - it has none of the F(2) patterns;
    - it holds the demo-off sentence, and links `](security-overview.md#mcp-tools)`.
  - **`t_overviewdoc`.** It runs both checks on the committed files (empty answers). For each new check, it adds one control: a copy of the committed file with one fault, which gives that check's line. The fault controls cover: the can't-connect sentence put back; the link removed; one word of each shared sentence changed (in each file); the limits paragraph changed; a "hard deadline" line added; a `replayToolChanged` line added; and a non-`example.com` address.
  - **The header comment** L32-38 states the new checks.

**Acceptance Criteria:**
- Given the committed `docs/mcp-jira-example.md`, when the `overviewdoc` rule reads it, then it is P1 word for word, it holds the shared classification, Read-only and time-limits text, and it never mentions source polls, the replay path or a hard deadline. Mutation: change one word of the classification sentence in the worked example -> rule `overviewdoc` red.
- Given the committed `docs/security-overview.md`, when `overviewdoc` reads it, then:
  - its MCP section opens with P2's first paragraph, which links the worked example;
  - it holds the shared sentences;
  - the Data section names MCP calls as live (P3);
  - the audit lines hold P5;
  - the can't-connect sentence is gone.
  Mutation: restore "This release can't connect to MCP servers." as the section's first line -> `overviewdoc` red.
- Given a fresh lane D throwaway, when `ci/iris.sh live security-overview` regenerates the overview, then it shows no drift:
  - the privileges section holds the P4 sentence after the Roles table;
  - the tools table still lists `call_mcp_tool`;
  - `Test.Install.SecurityOverview` passes.
  Mutation: `PrivilegesText` skips MCPSTATEMENT -> `TestMcpResourceStatement` red.
- Given `docs/bridge-guide.md`, when `test-bridge-guide.sh` runs, then the TurnTools bullet ends with the approved DW-950 sentence, and the McpServers bullet is P7, both as ruled lines. Mutation: delete the DW-950 sentence -> `turntools` red.
- Given a registered server whose tools list includes `call_mcp_tool`, when a request's manager is composed and the model calls `call_mcp_tool {server, tool: zz_lookup}`, then the governed proxy runs it (one `MCP` `called` entry), the server never gets a `tools/call` named `call_mcp_tool`, and the server's `call_mcp_tool` is reported refused, with one `mcp.toolShadowsBuiltIn` notice. Mutations:
  - restore `OfferProxy` after `AddTool` -> `TestProxyNameNotShadowing` red;
  - drop `MCPPROXY` from `builtin` -> `TestProxyNameRefused` red.
- Given an online-demo install, when the suite runs, then `TestDemoOffersNoProxy` and `Test.Agent.Runners` `TestToolInventory` stay green, and the replay path (`Test.Mcp.Approval`) is unchanged.
- Given the committed tree, when `overviewdoc` runs, then `docs/mcp-jira-example.md` exists at that path, and its classification sentence equals the overview's `OVW_MCP_RISKY`. These are the path and the sentence that Lane B's Story 36.2 links and copies into GUIDE.md's admin section; no Lane B action is needed in this story. Mutation: rename the file -> `overviewdoc` red.

**Release check** (unchanged): the Contest Planner's hands-on pass at this step's release (REL-7). Its source-poll half moves with V2.

**Ledger and standing items:**
- [x] **DW-950** (ledger): the bridge guide's TurnTools bullet carries the approved sentence (P6). 22.4 replays MCP rows on a proxy-only manager, but any other held call still replays on the agent's own manager (`Replay.cls` L118), so the sentence is still true.
- [x] **DW-1221** (ledger, ruling H): the time-limits paragraph in both docs, pinned, and no hard-deadline text.
- [x] **DW-1228** (ledger, ruling H): it is not refused under the current design (Code Map), so it gets the narrow fix and the two tests above.
- [x] **Online-demo safety** (standing rule): every doc says that MCP is off on the demo; the code change is inert there (`TestDemoOffersNoProxy`).

- [x] **[RULED 2026-11-13, Planner M (4)] text conditions**: (a) P1 reads "No message, log, audit entry or answer holds the secret." (without "trace") until the TraceLeaks retrofit (Story 21.14's condition) passes for MCP secrets; (b) "A request that nobody answers within 24 hours expires." cites the code's expiry setting (`Bridge.Approval` `EXPIRYSECONDS`) in the claims and is pinned; (c) P2's "cut to 200 characters" must match the code at merge (Story 21.10 removes the cut and updates P2 and the worked example in the same commit — the orchestrator puts that DW bullet on 21.10); (d) M1 ("Connect an MCP server", hidden on the demo) — when it ships, the README Usability count becomes "Its More to try panel has seventeen more things to try, fifteen of them on the online demo" and every pin of that count follows in the same commit (README is Epic 0's: bring the change to the lead); (e) every other sentence is true of the code at merge, checked by review. Veto 1-6 APPROVED, including the split of the source part into new Story 22.12 (after 22.11 and 21.5, same release), the DW-1228 fix (proxy registered first, `call_mcp_tool` a refused name) and the S19 spine refinement.

- [x] **[RULED 2026-11-13 ~17:15Z, orchestrator R1 (prompts/epic-22-rulings-20261113-1715.md)] `docker/tests/test-readme.sh`, rule `docs` only (footprint extension)**: P2 replaces the overview sentence that rule `docs` pins, so `ci/checks.sh` fails with "the MCP rules line is not under ... with no heading between". Re-pin only the ruled MCP line, "under `## MCP tools` with no heading between": change `MCP_FRAME` (L1673), the `chk_docs` awk check (L1684-1686), its two controls (L3195-3209) and the header comment (L96) to match P2's committed text. Change nothing else in the file. `bash docker/tests/test-readme.sh docs` (and the whole file) and `ci/checks.sh`'s docs step exit 0; write the `mutation:` line (restore the old sentence in a copy -> rule `docs` red). Epic 21's Story 21.14 edits the same rule; whoever pushes second keeps both sides' pins (the lead handles that at integrate-forward).

- [x] [Review] **R1 patch, re-applied over 21.14 (orchestrator R1)**: the previous pass implemented and verified the R1 item, then saved it as `_bmad-output/implementation-artifacts/set-aside/22-6-r1-test-readme-docs-pin.patch` and reverted the file. Since then this branch integrated feature 62db09e0, which carries Story 21.14's own edits to the same rule `docs`, so the patch no longer applies cleanly. Apply it with `git apply --3way` and resolve by KEEPING BOTH SIDES: 21.14's pins and controls and 22.6's re-pin of the ruled MCP line under `## MCP tools`. If keeping both is not a plain union (one side's pin contradicts the other's text), HALT `blocked` with the exact hunk; never drop a pin. Then tick the R1 item above, keep its `mutation:` line (move it from `## Auto Run Result` into `## Verification`), and run `bash docker/tests/test-readme.sh` and `bash ci/checks.sh`.
- [x] [Review] **VG1 (review, MED)**: the `If registered && 'added Quit 0` branch of `Bridge/Adapter/Agent.cls` `OfferServers` has no test on a proxy-naming host. Add a sibling of `TestAddToolFailsInRequest` in `Test/Mcp/Attach.cls` (a NEW method; never edit an existing helper) on a host that names a proxy: every answering server's `AddTool` fails -> `OfferServers` gives 0 and the manager is rebuilt with no MCP server and no proxy. Write its `mutation:` line.
- [x] [Review] **VG3 (review, MED)**: P3 (the Data bullet), P5's audit lines, the overview's demo-off sentence and the worked example's 24-hour claim have no pin. Add them to `overviewdoc` / `mcp_doc_problems` in `docker/tests/test-release-sequence.sh` with one fault control each; the 24-hour pin cites `Bridge.Approval` `EXPIRYSECONDS` (ruling M(4)(b)) by reading it from the class source, not a copied number. Write the `mutation:` lines.

### Review Findings

#### 2026-11-13 - code-review (first external review; c13b1836..d2bf45cd plus e5967024..working tree, QA's tests included; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all opus)
- verdicts: 31 findings - high 0, medium 2, low 26, false 3, maybe-false 0. Entries after grouping: 7 (medium 1 patched, low 5 patched, low 1 decision-pending). The five Story 21.4 Settings sentences were not checked (VERIFY AT MERGE); every other shipped sentence was checked against this tree by the acceptance auditor and holds (name rule, 24 h expiry, 2 s / 20 s, resource and U grant, audit fields, removal cancels, changed tool unclassified, untrusted turns, call-time check, approval and step texts, 200-character cut, notice, HTTPS rule, readOnlyHint, P4, P7). Rule 3: the docs are exercised by real shell runs (`overviewdoc`, `turntools`, `docs`) and DW-1228 by real IRIS runs against the mock server; no AD Rule is contradicted (Rule 6). Story 21.14's `docs` pins in `test-readme.sh` are intact beside the R1 re-pin.
- [x] `[medium]` `[patch]` VG1 + AA1 (fix-risk low, in-story): AC 1's "P1 word for word" was pinned only for the title, the shared texts, the demo-off, expiry and link sentences; the classification table and the governance bullets could change (for example `add_comment` to Read-only) with `overviewdoc` green. Patched in `docker/tests/test-release-sequence.sh`: new `ovw_mcp_example_lines` (the five table rows, the Read-only rule, the refusal line, the six governance bullets) checked whole-line in `mcp_doc_problems`, with two fault controls (a row's class, a shortened bullet). AA1's other half (the spec's P1 block still holds "trace," that ruling M(4)(a) removed from the shipped file) is rejected: its fix edits the spec, and the ruling records the difference.
- [x] `[low]` `[patch]` VG2 (fix-risk low, in-story): "its MCP section opens with P2's first paragraph" (AC 2) had no check of the opening; patched: `ovw_doc_problems` checks that the section's first line starts with P2's first sentence (`OVW_MCP_OPENING`), one new control, and the can't-connect control now expects both its lines.
- [x] `[low]` `[patch]` BH2 + EC7 + VG-o3 + AA2 (fix-risk low, in-story, doc only): the `Bridge/Adapter/Agent.cls` class doc said a request with no server's tools added "goes on with a manager composed again" (untrue when no probe answered: nothing is registered and nothing recomposed), and the `ComposeManager` doc still gave the old proxied-0 condition; both docs now state the current contract.
- [x] `[low]` `[patch]` VG-o1 (fix-risk low, in-story): `TestProxyNoneAdded` asserted `OcuTalon.Mcp.Attach`'s `ProxyToolSet` while the test runs on `..#PROBEATTACH`; it now asserts the fixture's own (`$ClassMethod(..#PROBEATTACH, "ProxyToolSet")`). `Test.Mcp.Attach` passes whole (186.93 s, lane D warm `e22s6crw`).
- [x] `[low]` `[patch]` BH7 (part; fix-risk low): `v` was not declared `local` in `mcp_doc_problems`; declared (with `line` and `n`).
- [x] `[low]` `[patch]` VG4 (Rule 19, fix-risk low): AC 6 had no `mutation:` line; applied, observed red and reverted on lane D warm `e22s6crw`, line written in `## Verification`.
- `[low]` `[decision-pending]` BH9 -> DW-1286 (owner burndown, decision sheet): the worked example says "the request is canceled" where every other public text and the code say "cancelled"; P1 is ruled verbatim (Planner M(4)), so the one-letter change waits for the Planner.
- `[false]` `[reject]` BH1 + EC6: the `ServerOf` doc ("a toolref that gets "" is denied, and is never held or run") would let a held call through - in this tree's host, a source that `ServerOf` cannot name has no `Mcp.Server` row, so `ClassifyMcp` answers registered 0 and `Gate.Check` denies it with UNREGISTERED at step 2, before any hold (Gate L35-37, L216, L639); the sentence is the Task's ruling F(1) text.
- `[false]` `[reject]` VG-o2: `TestProxyNoneAdded` flakes when the two configs probe twice past the 3 s rest - `ZzTurnAdapter.ComposeTwice` composes once per request (`TurnComposed`), so there is one probe and one warning.
- `[low]` `[reject]` BH3 + EC2: `registered` is set when `ProxyToolSet` is "", so a host with servers and no proxy whose `AddTool` fails composes twice - no shipped host reaches it (the bridge alone and the demo list no server); the extra compose is harmless; reopen_if a host that lists servers and names no proxy ships.
- `[low]` `[reject]` EC1: a server whose `AddTool` succeeds but whose every tool is refused still counts as added, so the proxy is offered with no usable tool - pre-existing since 22.3 (added counted after `AddTool`), and a proxy call for a refused tool is unclassified and denied or held.
- `[low]` `[reject]` BH4: P7 describes the proxy as if every host had one - ruled text (IA4 of the implement review); the bullet describes the extension a host overrides.
- `[low]` `[reject]` AA3: P2 and P7 name "the agent's own tools" as the refused names, while a request's turn-tool names are refused too - incomplete, not false; ruled text (Decided in-stage 1).
- `[low]` `[reject]` AA4: "Each call ... writes an audit entry ... and shows as a step" does not hold for a call the gate denies - reads as a call that runs (AD-17); ruled text (EC7 of the implement review).
- `[low]` `[reject]` AA5: "each listing of its tools" with 2 s holds for OcuTalon's own client only, AI Hub's listing has no deadline - the paragraph's own "not hard deadlines" and its residual sentence cover it; ruled S11 text (BH3 of the implement review).
- `[low]` `[reject]` BH10: the example does not say OcuTalon grants the resource itself - the sentence is true, P4 states the grant; ruled text.
- `[low]` `[reject]` BH5: no two-server test of the reordered `OfferServers` - no AC or matrix row; the `registered` flag is one branch; a second mock is more than a direct fix.
- `[low]` `[reject]` BH6: the `Test/Mcp/Attach.cls` class header does not list the new tests - the class is contended and the spec allows new Test methods only, no existing line.
- `[low]` `[reject]` BH7 (rest) + EC3 + EC4: the example's address check misses bare IPs, scheme-less hosts and upper-case schemes, and globs - the spec names the check (http/https hosts on example.com); BH2 of the implement review.
- `[low]` `[reject]` EC5: the expiry pin assumes whole hours - EXPIRYSECONDS is 86400 and the overview's pin does the same (BH1 of the rework review).
- `[low]` `[reject]` BH8: the 2 s / 20 s, the 39-character rule, MCPLABEL and `toolCall.requestOnServer` are pinned as literals, not read from the code - a guard for a change no story plans (the spec forbids changing `Mcp.Client`'s limits; 22.10 is deferred past the contest); reopen_if a story changes PROBESECONDS, CALLSECONDS, NAMEPATTERN, MCPLABEL or `toolCall.requestOnServer`.
- `[low]` `[reject]` VG3: `WithProxyName`'s Catch is never exercised - no shipped `ProxyToolSet` throws (wontfix-theoretical); reopen_if a host's `ProxyToolSet` can throw.
- `[low]` `[reject]` AA6: Veto item 6 calls its spine refinement "S19", which already names the IPM spike, and AD-21 does not record it yet - a lead action under Rule 20 (record it under a free S-number); no story code changes.
- `[low]` `[reject]` AA7: OcuTalon's probe does not itself refuse a plain-HTTP address to another host; the HTTPS rule is applied at add (`Ops.OnAdd`) and at call (`Proxy`) - the Config Store entry is written only by 21.4's `SaveMcpEntry` (VERIFY AT MERGE item 2); wontfix-theoretical; reopen_if anything else writes `AI.MCP.OcuTalon_*`.

- [x] [Review] **R7-1 (DW-1286, APPROVED by the Planner)**: in `docs/mcp-jira-example.md` L48 change "canceled" to "cancelled" (that one word only), and update any line pin that holds that sentence (`docker/tests/test-release-sequence.sh` `ovw_mcp_example_lines` or `mcp_doc_problems`) in the same pass, with its `mutation:` line if the pin is new or changed.
- [x] [Review] **R7-2 (P2 takes 21.4's approved :212 bullet word for word)**: the integrate-forward (f3ce1fa1) put 21.4's bullet "- Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry for each call it lets run (read-only calls included) and an agent step. A call to a removed server's tool runs nothing and writes no audit entry." in place of 22.6's own P2 bullet in `docs/security-overview.md`. Confirm it is word for word (keep "cut to 200 characters" as it is, per the DW-1266 reading), that 22.6's other P2 bullets stand, and that every overview/worked-example pin still passes; update the spec's Public text P2 to the merged wording. No other text change.
- [x] [Review] **R7-3 (VERIFY AT MERGE, orchestrator ruling)**: against the MERGED code (feature 5de8aec9 with Story 21.4), check each of the five 21.4-dependent sentences of P1/P2 (Add server; the Wallet and Config Store write; removing the entry and the secret; the Tools table and its classification control; an admin adding servers from Settings) and every sentence about MCP server addresses (the query/fragment refusal on the add path only; userinfo; http to a non-loopback host; `SaveMcpEntry` as the only writer of `AI.MCP.OcuTalon_*` and its address validation). Record each with file:line under Design Notes. A false sentence is a HALT `blocked` for a `PUBLIC TEXT:` (never change code to fit the text, never reword ruled text).

#### 2026-11-14 - code-review (rework re-review, iteration 2 of 3, and the VERIFY-AT-MERGE gate; diff 1548802e..093439c8; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all opus)
- verdicts: 17 findings (blind-hunter 9, edge-case-hunter 3, verification-gap 0 gaps + 1 other, acceptance-auditor 4) - high 1, medium 0, low 16, false 0, maybe-false 0. Entries after grouping: 13 (high 1 decision-pending, low 12 rejected or closed). The reviewer also checked each claim against the merged code on its own (no line number taken from the Design Notes).
- [x] `[high]` `[patch]` (resolved by R8-1, R8-2 and R8-3) AA1 -> DW-1324 **PUBLIC TEXT** (fix-risk low: one sentence; in-story; spec-bound, P1 is ruled verbatim): `docs/mcp-jira-example.md:14` "In Settings > Tools and MCP servers, press **Add server** and fill in:" is false of the merged Story 21.4 form. The Name, Address and Secret fields always show under the "Add server" heading, with no toggle (`web/src/app/settings/mcp-section.ts:111-163`). The **Add server** button sits below them and sends them (`:166`). Pressing it first sends an empty form and gets refusals on the fields (`Web/McpSettings.cls:141-151`). `web/e2e/settings/mcp.spec.ts:103-121` fills the fields, then clicks. Story 21.4's AC (`epics.md:7685`) has the same press-then-enter order, which is how the text came to say it. Neither the text nor the code was changed. Suggested true wording: "In Settings > Tools and MCP servers, fill in the fields under **Add server**, then press the **Add server** button:". This waits for a Planner or orchestrator ruling on the text.
- Verified at merge, independently (TRUE unless marked):
  - (a) Add server: the section label is `settings-view.ts:42`. The labels are `mcp-view.ts:38-40`, and the secret help text is `:41`. The name rule is `Mcp/Server.cls:12` (`^[A-Za-z][A-Za-z0-9_]{0,39}$`) and `Mcp/Ops.cls:55`, enforced at `Ops.cls:94` and `Web/McpSettings.cls:143`. The step order is FALSE (above).
  - (b) Wallet and Config Store write: the collection and key are `Ops.cls:259-260`. The entry `AI.MCP.OcuTalon_<server>` with `url` and `secret://<collection>.Key#token` is `:264-266`, and the local copy of the secret is cleared at `:271`. The resource is granted at `:164` and in `Install/Step/Mcp.cls` Grant (`:55-60`). The service user's permission is checked per call at `Bridge/Policy/Gate.cls:589`.
  - (c) Removal: the tool rows, the row and the resource go at `Ops.cls:201-203` (Revoke). The entry, the key and the collection go in DropEntry (`:222`, `:283-286`). If DropEntry fails, that is one warning and the removal stands (`:222`).
  - (d) Tools table: the help line is `mcp-view.ts:36`, the three options are `:67` and `:72-76` (a radiogroup at `mcp-section.ts:202`), the refused text is `mcp-view.ts:62`, the row status is `Ops.cls:344`, and the notice is `:520`.
  - (e) Settings only: the three commands are built only at `Web/McpSettings.cls:81,98,117`. CommandsIn accepts them only from `web_admin` (`Core/CommandsIn.cls:360-362`). Non-admins get 403 at `Web/Api.cls:324-326` and again at `McpSettings.cls:52`. `Ops.cls:586-599` refuses any other sender or origin, a tool context and the online demo.
  - (f) Addresses: AddressAllowed is `Ops.cls:550-571`. It allows https, or http only to a host in LOOPBACKHOSTS (`:45`, checked at `:570`). It refuses userinfo at `:558` and `@{` at `:552`. It runs at add (`Ops.cls:95`, `McpSettings.cls:148`) and at every call (`Mcp/Proxy.cls:84`). A query or fragment is refused on the add path only: the code is `Ops.cls:96` and `McpSettings.cls:150-151` (`:9` is the class comment). AddressAllowed has no such test.
  - (g) Only writer: `SaveMcpEntry` no longer exists. The one `Create` of `AI.MCP.*` is `Ops.cls:266`, inside the private SaveEntry (`:247-274`). Its only caller is Register (`:169`), which runs after OnAdd has validated the name and address (`:94-96`). The other non-test `%ConfigStore.Configuration` writers are `Bridge/ConfigStore.cls:66` (Merge, Shape-limited) and `:104` (Restore). Restore is not Shape-limited, and FullName (`:145`) passes a three-part name through. They are safe because of their callers: `Bridge/Settings.cls:286,296` and `Bridge/Timeouts.cls:127` pass only a runner's LLM entry, and Restore writes back the details Details read from that same entry. `Install/Step/Provider.cls:179,181` writes `AI.LLM` entries. `Ops.cls:284` only deletes.
  - (h) `docs/security-overview.md:221` matches 21.4's bullet byte for byte (`cmp`), including "cut to 200 characters".
- `[low]` `[reject]` BH-a + EC2 (fix-risk low; spec-only): some Design Notes citations are loose. `Ops.cls:617-624` is cited as "change and server only", but Common (`:639-644`) also adds irisUser, sessionRef and channel. `:173` is cited as "nothing logged", but it is a warning with fixed text. "L5 of P1" should be L3. `McpSettings.cls:9` is a class comment. Fixing these edits the spec; the correct lines are in the verdict above.
- `[low]` `[reject]` BH-c + EC3 (spec-only): the "only writer" reasoning credits Shape for Restore. The conclusion holds, for the reason given in (g).
- `[low]` `[reject]` BH-b (spec-only): some claims cite UI strings or class comments. The code evidence is in (a) to (g): Gate `:589`, and Proxy's per-call credential header (`Proxy.cls:86`).
- `[low]` `[wontfix-theoretical]` BH-d (fix-risk med; out-of-footprint, `Mcp/Ops.cls` is contended): a failed DropEntry after a removal leaves the entry and the secret in place, with only a warning. Nothing reproduces it, and the next add of that name drops leftovers first (`Ops.cls:253`). It becomes real if a log shows "the entry or the wallet secret of the removed MCP server could not all be dropped".
- `[low]` `[reject]` BH-e (carried from AA4 and BH4 + EC4; ruled text): example L57 says "Each call of a server's tool writes an audit entry", while the overview now says "for each call it lets run". A denied call writes none (`Mcp/Proxy.cls:52`, `Test.Mcp.Attach` L712). The text is not false if "call" is read as a call that runs. If the Planner rules on DW-1324, it may also align L57 ("Each call of a server's tool that runs writes an audit entry ...").
- `[low]` `[reject]` BH-f + EC1 (spec-only, cosmetic): Rework pass 2's summary says "Patched: 2 entries" and "low 2", but its triage log has three `[patch]` rows.
- `[low]` `[reject]` BH-g: `baseline_commit` moved from c13b1836 to 1548802e in the orchestrator's commit 093439c8. That is the orchestrator's scoping for this re-review. The story's base stays in the cycle log (Rule 17 story_base).
- `[low]` `[reject]` BH-h + AA2 + VG-other (spec-only): the P1 block still says "canceled" and AC 1 says "P1 word for word". Row BH9 still says decision-pending. Row AA7 still names `SaveMcpEntry`. The shipped file governs (Spec Change Log). Ledger DW-1286 (decision-pending, burndown) is now fixed by `docs/mcp-jira-example.md:48`, for the lead to adjudicate.
- `[low]` `[wontfix-accepted]` VG-other (pin gap): `mcp_doc_problems` (`docker/tests/test-release-sequence.sh:2330-2365`) pins parts of P1, not all of it. A whole-P1 pin needs P1 to match the shipped file first, which is a spec edit. reopen_if: `git log -p docs/mcp-jira-example.md` shows a line change that no Spec Change Log line or ruling names.
- `[low]` `[reject]` AA3: the spec frontmatter says `status: done`, while sprint-status says `review`. This review may not change the frontmatter. Sprint-status is synced below.
- `[low]` `[reject]` BH-i (cosmetic): the rework's entries are dated 2026-11-13 local time; the cycle log has 2026-11-14Z.
- `[low]` `[reject]` AA-residual (carried AA7, wontfix-theoretical): the attach check and AI Hub's listing do not re-check the address. Only an out-of-band `%Admin_ConfigStore` edit could reach that. No product code writes the entry except SaveEntry, as (g) shows.
- Rule 3: docs-only diff, so not a user-facing code surface. The form's e2e test (`web/e2e/settings/mcp.spec.ts`) is 21.4's. Rule 19: no test was added or changed, and every AC has a `mutation:` line (verification-gap layer). Rule 6: no AD mismatch (AD-21 S11 and S20, AD-10, AD-11 and AD-17 text unchanged by this diff).
- Exit: one HIGH, so the story does not close. It waits for the PUBLIC TEXT ruling on DW-1324 (sprint-status `in-progress`).

- [x] [Review] **R8-1 (DW-1324, Contest Planner ~07:45Z Nov 14, approved verbatim)**: `docs/mcp-jira-example.md:14` becomes, word for word: "In Settings > Tools and MCP servers, fill in the fields under **Add server**, then press the **Add server** button:" (replacing "In Settings > Tools and MCP servers, press **Add server** and fill in:"). Update the spec's Public text P1 to match.
- [x] [Review] **R8-2 (Planner ~07:45Z, approved)**: in `docs/mcp-jira-example.md:57` replace "Each call of a server's tool writes an audit entry" with "Each call of a server's tool that runs writes an audit entry"; the rest of that sentence stays exactly as it is. Update the spec's Public text P1 to match.
- [x] [Review] **R8-3 (pins)**: pin BOTH lines in `docker/tests/test-release-sequence.sh` (`mcp_doc_problems` / the worked example's line pins), each with one fault control and a `mutation:` line (restore the old line 14 -> its pin red; drop "that runs" from line 57 -> its pin red). Change nothing else. Then resolve DW-1324 in the spec's records (the lead writes the ledger trailer).

## Spec Change Log

- 2026-11-13 (runner, Planner ruling M (4)): gate APPROVED with the text conditions above; Story 22.12 to be inserted in epics.md.
- 2026-11-13 (rework 2, R7-1, DW-1286): the shipped `docs/mcp-jira-example.md` L48 reads "cancelled"; the P1 block under `## Public text` below still reads "canceled" and is left as the ruled original (a spec edit is not this pass's work); the shipped file governs.

- 2026-11-14 (rework 3, R8-1, R8-2, R8-3, DW-1324 resolved): `docs/mcp-jira-example.md` L14 and L57 now read the Planner-approved wording, and the P1 block under `## Public text` carries both (it still reads "canceled" and "trace," where the shipped file differs, per the entries above; the shipped file governs).

## Review Triage Log

### 2026-11-13 - Review pass (first review of the whole story, c13b1836..working tree)
- verdicts: 31 findings - high 0, medium 7, low 18, false 3, maybe-false 3
- findings:
  - `[medium]` `[intent_gap]` BH1 + EC1: the worked example's step 1 sends the admin to "Settings > Tools and MCP servers" and "Add server" with the Name, Address and Secret fields; this tree has none of it (no web/src MCP file; the route only in the spine and a test) - evidence: web/src/app/settings holds no MCP view; Story 21.4 is not merged.
  - `[medium]` `[intent_gap]` EC2: "OcuTalon keeps the secret in the IRIS Wallet and writes the server's Config Store entry, AI.MCP.OcuTalon_Jira" (example) and the overview's Wallet bullet; `Core/SettingsOps.cls` SaveMcpEntry is a stub (Error 5003, "Not built: Story 21.4 builds it") and `Mcp.Ops.OnAdd` writes neither the entry nor the secret.
  - `[medium]` `[intent_gap]` EC3: "Removing the server removes the resource, the entry and the secret." `Mcp.Ops.Unregister` removes the rows, the resource and the grant; `RemoveMcpEntry` is a stub, so the entry and the secret stay.
  - `[medium]` `[intent_gap]` EC4: "The server's tools show in the Tools table once OcuTalon next uses its agents", "Each tool's control offers Unclassified (counts as risky), Read-only and Risky" and the Tools table's "Refused: a built-in tool has this name"; no Tools table, control or that text exists in src or web (the notice text is the catalog's `mcp.toolShadowsBuiltIn`, which words it differently).
  - `[medium]` `[intent_gap]` EC5: "On a local or IPM install, an admin can add MCP servers" (overview P2) and "only from the settings page" (both docs): `AddMcpServer`, `RemoveMcpServer` and `ClassifyTool` are accepted only from `web_admin`, but nothing sends them in this tree, so the capability cannot be used until 21.4 merges.
  - `[low]` `[reject]` BH2: weak doc checks (bare IP in the example, source-poll rule on the example only, "deadline" anywhere) - the spec names each check (http/https hosts, "deadline" outside OVW_MCP_LIMITS); extra guards add complexity for no reachable harm.
  - `[low]` `[reject]` BH3: the time-limits sentence can be read two ways - it is the ruled text, word for word the same in both docs and pinned (spec-bound); a fix edits public text outside this story's authority.
  - `[low]` `[reject]` BH4: the example has no troubleshooting section (probe failure, rotation, an approved request not cancelled on removal) - the spec ships only `## Public text` verbatim; the omission is the ruling, not a defect.
  - `[low]` `[reject]` BH5: the TurnTools bullet does not say what a risky tool does - it is the Planner-approved DW-950 sentence, verbatim (spec-bound).
  - `[low]` `[reject]` BH6: the McpServers bullet gives no defaults - it is P7 verbatim (spec-bound); the class doc holds the defaults.
  - `[false]` `[reject]` BH7: the `ServerOf` doc says "denied" with no Gate change - ruling F(1) (22.4) made it denied; the Code Map names the doc as the stale part, and `McpServers.cls` is a doc-only edit.
  - `[maybe-false]` `[patch]` BH8: no test of the path where the proxy is registered and `AddTool` fails for every answering server (returns 0, the manager is rebuilt without MCP) - same root as VG1 (verified there, see VG1); its second claim (OfferProxy failing on the first server quits without marking it unavailable) is false: the old code also returned 0 and `BuildTurnManager` rebuilt the manager with no MCP server, so the request's tools are the same.
  - `[low]` `[reject]` BH9: `WithProxyName` asks `ProxyToolSet` on every request, and its Catch is a no-op - one class method call per request, and the Catch keeps the host's failure from failing the build; negligible, and a cache is more state.
  - `[low]` `[reject]` BH10: `MCP_FRAME` now holds a heading and the awk order changed - the name is the spec's own (R1 names `MCP_FRAME`); the new control "the MCP tools heading removed" and the heading-between control pin the awk; a `#` line on the frame line itself is the frame.
  - `[low]` `[reject]` EC6: "such as the README account" - README step 3 names the user `ocutalon`, which holds the admin role on an install; P1 is ruled text.
  - `[maybe-false]` `[reject]` EC7: a call the gate denies or holds writes no `MCP` audit entry (only a call that reached the server does) - "each call of a server's tool" reads as a call that runs; would settle it: whether the gate's denial entries (Tool type) already record denials; a rewording would edit ruled text. Low if true.
  - `[medium]` `[patch]` VG1: the `If registered && 'added Quit 0` branch of `OfferServers` has no test on a proxy-naming host (`TestAddToolFailsInRequest` uses `ZzServers`, which names no proxy) and no mutation line - verified: the branch is in the diff and the test host registers no proxy. Moot under the intent_gap cascade; for the re-run: add a sibling of `TestAddToolFailsInRequest` on `..#PROBEATTACH` that fails `AddTool` for every server and asserts no `call_mcp_tool` on the request's manager, plus its `mutation:` line.
  - `[low]` `[defer-class: reject]` VG2: `WithProxyName`'s "only when the host names a proxy" is unpinned on a no-proxy host - the demo and the bridge alone have no server, the branch is one `If`; a one-assertion test on `ZzServers` would close it (reopen_if: a bridge-alone host that registers a server).
  - `[medium]` `[patch]` VG3: P3 (the Data bullet), P5's audit lines, the overview's demo-off sentence and the worked example's 24-hour claim (spec condition M(4)(b): cited to `Bridge.Approval` `EXPIRYSECONDS` and pinned) have no pin in `overviewdoc`/`mcp_doc_problems` and no mutation line - verified: `ovw_phrases` pins only the overview's hours and `mcp_doc_problems` has no EXPIRYSECONDS check. Moot under the cascade; for the re-run: add the four pins with fixture controls and `mutation:` lines.
  - `[low]` `[reject]` VG-o1: AC 6 and the P3/P5 sub-claims lack `mutation:` lines - the P3/P5 part is VG3's; AC 6 (the demo tests stay green) is an unchanged-behavior AC whose pinning tests pre-exist.
  - `[low]` `[reject]` VG-o2: `TestProxyNameNotShadowing`'s `Listed(manager, "call_mcp_tool") = 1` cannot tell a shadowed manager from the right one - true, but the assertions that discriminate (the call's value, the mock's `tools/call` count 0, the one `MCP` entry) carry the AC and went red under both mutations.
  - `[low]` `[reject]` VG-o3: the proxy-registered-then-nothing-added path now returns 0 on a no-proxy host, so `BuildTurnManager` recomposes - the observable tool list is the same and `TestAddToolFailsInRequest` pins it.
  - `[low]` `[reject]` IA1: `docker/tests/test-readme.sh` and `McpServers.cls` are outside the Lane A list - `McpServers.cls` (doc only) is on the list; `test-readme.sh` rule `docs` is the orchestrator's R1 footprint extension.
  - `[low]` `[reject]` IA2: `ovw_doc_problems_no_mcp` and the switch controls were removed - the spec's Task replaces them with positive controls (Decided in-stage 3); no coverage is dropped.
  - `[low]` `[reject]` IA3: the bridge guide edits carry no online-demo sentence - the spec requires it of the overview and the worked example (P1, P2); P6 and P7 are ruled lines.
  - `[low]` `[reject]` IA4: the McpServers bullet states the proxy refusal unconditionally, but the code adds the name only when the host names a proxy - the bullet describes the host extension (the OcuTalon host names one); the bridge alone has no MCP server.
  - `[false]` `[reject]` IA5: demo inertness is "only indirectly" shown - `TestDemoOffersNoProxy` runs green and `ProxyToolSet` is empty on the demo; the docs say MCP is off there.
  - `[false]` `[reject]` IA6: the doc checks prove existence, not truth - true of any text pin; the claims were checked by EC1-EC7 against the code (name rule, expiry 86400, 200-character cut, resource and entry names, 2 s and 20 s limits, audit fields, removal cancels pending requests, changed tool Unclassified, untrusted turns all hold).
  - `[maybe-false]` `[reject]` IA7: the privileges sentence is also hand-added to the committed overview - the generated region is regenerated by `live security-overview --write` and the plain run shows no DRIFT (run on a fresh lane D throwaway this pass).
  - `[low]` `[reject]` IA8: "the replay path is not described" is pinned by three literal phrases only - spec Ruling F(2) names those phrases.
  - `[low]` `[reject]` IA9: the diff changes the build-time attach report as well as the request's manager - the spec's Task names both (`AttachServers` and `OfferServers`), and `TestProxyNameRefused` pins the first.

### 2026-11-13 - Review pass (rework: R1 re-apply, VG1, VG3; diff e5967024..working tree)
- verdicts: 17 findings - high 0, medium 1, low 16, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` BH1 + EC1: the expiry pin computes `$((v / 3600))` hours and a plural "hours" - EXPIRYSECONDS is 86400 (24 hours), the overview's own pin (`ovw_doc_problems`) already does the same, and the pin reads the class source; a guard for a value nobody sets adds complexity.
  - `[low]` `[reject]` BH2: the EXPIRYSECONDS read is copied into `mcp_doc_problems` - two short lines in two checks of one script; a shared helper adds a function for two callers (it already reuses `ovw_code_value`).
  - `[low]` `[reject]` BH3: `MCP_FRAME` now holds a heading - the name is the spec's own (R1 names `MCP_FRAME`); a rename touches more of 21.14's lines.
  - `[low]` `[reject]` BH4: `/^#/` also matches a `#` line - the awk keeps the old rule's own test; the overview has no code fence between the heading and the rules line.
  - `[low]` `[reject]` BH5: the new pins are one-sided (the Online demo section is not pinned for MCP) - spec-bound (VG3 names these pins); more pins are new scope in an oversized story.
  - `[low]` `[patch]` BH6: the header comment of `overviewdoc` ran to 195 columns - re-wrapped in `docker/tests/test-release-sequence.sh` (a comment only).
  - `[medium]` `[patch]` BH7 + VG1: `TestProxyNoneAdded` asserts only the final manager, so it also passes when the probe fails or the server is never offered (verified: the same manager list results; EC read `Client.Probe` and the mock) - patched in `Test/Mcp/Attach.cls`: it counts `OtherRequests()` before and after the request (AI Hub's client reached the server, so AddTool ran) and asserts the one warning that names the server (`LogRowsHolding`); the VG1 mutation re-run is red.
  - `[low]` `[reject]` EC2: the Pairing and demo-off pins match substrings, not whole lines - they are sentences inside a paragraph; the spec asks for "word for word".
  - `[low]` `[reject]` EC3: `TestProxyNoneAdded` on an online-demo host (`ProxyToolSet` empty) - it asserts the host names the proxy first, and `Use` swaps in the test host class, so the demo flag does not reach it; the siblings do the same.
  - `[low]` `[reject]` VG2: the R1 awk reorder has no `mutation:` line of its own - the two controls and the filed R1 mutation pin the heading; the good case checks the reorder.
  - `[low]` `[reject]` VG3: AC 6 (demo and replay path unchanged) has no new `mutation:` line - its pinning tests pre-exist and are unchanged; carried from the first review.
  - `[low]` `[reject]` IA1: the "one warning" of the matrix row is not asserted in `TestProxyNoneAdded` - same root as BH7, fixed by that patch.
  - `[low]` `[reject]` IA2: the Data-bullet control gives two complaint lines - both checks fire on that fault; the control states both.
  - `[low]` `[reject]` IA3: the pins compare constants and docs, which are two copies of one sentence - spec-bound (word for word).
  - `[low]` `[reject]` IA4: the test exercises a substituted host (`ZzProbeAttach`), not a real manager - the sibling tests and the spec (siblings of `TestAddToolFailsInRequest`) use the same fixtures.
  - `[low]` `[reject]` IA5: the `turntools` rule and the DW-950 sentence are not touched by this diff - correct, they are committed and unchanged.
  - `[low]` `[reject]` IA6: the `docs` rule checks structure, not the section's prose - the prose is `overviewdoc`'s.

### 2026-11-13 - Review pass (rework 2: R7-1, R7-2, R7-3; diff 1548802e..working tree)
- verdicts: 16 findings (blind-hunter 5, edge-case-hunter 5, verification-gap 2, intent-alignment 4) - high 0, medium 0, low 13, false 3, maybe-false 0; the rows below group them by root cause and each keeps its layer ids
- findings:
  - `[low]` `[patch]` BH2 + EC3: the R7-3 evidence cites `Mcp/Ops.cls:559-560` (userinfo) and `:571-572` (http to another host) and ends AddressAllowed at `:572`; the file has them at :558, :570 and :571 - patched in Design Notes (a citation the item itself requires).
  - `[low]` `[patch]` EC2 + VG-a: the Rework 2 note said the overview's :221 bullet is pinned by no rule; `test-readme.sh` rule `docs` pins it whole (`L187`, :1681, :1693, :1703) - patched; the note also now records the results.
  - `[low]` `[reject]` BH1 + EC1: the spec's P1 block still reads "canceled" and BH9 still says decision-pending - the fix edits the spec's ruled text; one line in the Spec Change Log now says that the shipped file governs.
  - `[false]` `[reject]` BH3: "a call to a removed server's tool ... writes no audit entry" is unchecked - `Test.Mcp.Attach` `TestRemovedServer` (L700-712) asserts the denied call, no approval request, and that the removal is the only `MCP` audit entry and no `Tool` entry; Proxy's audit is gated on `reached`.
  - `[low]` `[reject]` BH4 + EC4: "an audit entry for each call it lets run" is narrower than the proxy (a reached-but-refused call is audited too), and the example's "Each call of a server's tool writes an audit entry" differs from the overview's removed-server sentence - neither is false (the removed server has no tool to call), the text is ruled verbatim (21.4, P1) and AA4 of the earlier pass is carried; reopen_if a sentence is found false.
  - `[low]` `[reject]` BH5 (part) : `review_loop_iteration` stays 0 - it counts bad_spec loopbacks only.
  - `[low]` `[reject]` EC5 + IA-1: the "cancelled" sentence has no whole-line pin - R7-1 asks to update a pin only if one holds the sentence, the spec is `oversized`, and a pin adds a control and a mutation; reopen_if the sentence is edited with every rule green.
  - `[false]` `[reject]` IA-2: "the R7-2 confirmation is asserted, not shown" - the bullet at `docs/security-overview.md:221` equals the item's text byte for byte (checked), appears once in the overview and once in the spec.
  - `[false]` `[reject]` IA-3: the intent still names `SaveMcpEntry` - 21.4 deleted it; the evidence names `SaveEntry` and says no public sentence names the old one; no text is false.
  - `[low]` `[reject]` IA-4: the evidence also covers the online-demo sentence, beyond the five - harmless, and the sentence is true.
  - `[low]` `[patch]` VG-b (with BH5, the results half): the Rework 2 note recorded no results - patched with the command outcomes (see the Verification note); the layer found no test gap and no non-falsifiable assertion, and no added or changed test.

### 2026-11-13 - Review pass (rework 3: R8-1, R8-2, R8-3; diff HEAD 51eebf4d..working tree, a follow-up pass)
- verdicts: 13 findings - high 0, medium 0, low 11, false 0, maybe-false 0 (two reader notes of the intent layer carry no defect)
- findings:
  - `[low]` `[reject]` BH-a: the `overviewdoc` header comment (about L36-48) does not list the new pins - it names "the classification and governance lines" generically, which still holds; a header edit is not required by R8-3.
  - `[low]` `[reject]` BH-b + EC-b + VG-1 + IA-2: the line pins are whole-file `grep -qxF`, not scoped to a section, so "ruled line 14" is a pin-list position - the same grammar as the ten pins before them (spec-accepted since pass 1); a section-scoped pin would change `mcp_doc_problems` for every line. reopen_if: a ruled line is found moved or duplicated in the example with `overviewdoc` green.
  - `[low]` `[reject]` BH-c + EC-a: "that runs" leaves out that a call that reaches the proxy and is refused also writes an entry (`Mcp/Proxy.cls:52`) - carried from BH4 + EC4 (rework 2): the sentence is true, and the wording is Planner-approved word for word (R8-2), so it is `by-design`.
  - `[low]` `[reject]` BH-d (spec-only): stale spec records (the earlier pass's Exit line, the BH-e row, `review_loop_iteration`, a blank line in the change log, no green-run record) - history is kept as written, the counter counts bad_spec loopbacks only, and this pass's green runs are in `## Auto Run Result`.
  - `[low]` `[reject]` BH-e: Story 21.4's AC (`epics.md:7685`) and UX-DR145 still say press-then-enter - another story's block, out of footprint and outside the intent. reopen_if: a new doc or test quotes that AC for the Add server step.
  - `[low]` `[reject]` EC-b/VG-2 (spec-only): the P1 block still reads "canceled" and "trace," - already in the Spec Change Log; the shipped file governs.
  - `[low]` `[reject]` VG-3: the mutation for R8-2's line is labeled R8-3 in `## Verification` (the pin is R8-3's item); cosmetic.
  - `[low]` `[reject]` IA-1: no check ties line 14 to the form's labels (`web/src/app/settings/mcp-view.ts`) - the form's e2e is Story 21.4's, and this pass is docs and a doc pin only; descriptive note.
  - `[low]` `[reject]` IA-3: the audit bullet is pinned in the example only, not tied to the overview's :221 sentence - the shared-sentence rule names the classification and Read-only sentences only.
  - `[low]` `[reject]` IA-R-A (note): the shipped file differs from the original P1 in the two ruled lines - P1 now carries both, as R8-1 and R8-2 ask.
- Patched: 0. Deferred: 0. Rule 3: docs-only diff, not a user-facing code surface. Rule 19: both new pins have a fault control and a `mutation:` line. Exit: no HIGH, so the story closes.

## Design Notes

**Ruled 2026-11-13 ~19:00Z (orchestrator, prompts/epic-22-rulings-20261113-1715.md, Step 3): VERIFY AT MERGE** (ruling M(4): "true of the code at merge"). The five sentences that describe Story 21.4's Settings surface (Add server; the Wallet and Config Store write; removing the entry and the secret; the Tools table and its classification control; an admin adding servers from Settings) ship as approved text and are NOT checked against this tree: 22.6 does not push or merge before 21.4 merges; then it integrates forward and a review layer checks each of the five against the merged code (a false claim is a STOP with PUBLIC TEXT; code is never changed to fit the text). Every other sentence must be true of this tree.

**Verified at merge (R7-3; rework pass 2026-11-13, merged feature 5de8aec9 with Story 21.4, in this branch since f3ce1fa1). Every sentence is true; none was reworded and no code changed.** Evidence, `docs/mcp-jira-example.md` (P1) unless marked:
1. Add server (L13-L18): the section "Tools and MCP servers" is `web/src/app/settings/settings-view.ts:42`; the button "Add server" is `web/src/app/settings/mcp-view.ts:32` and `mcp-section.ts:112,166`; the labels Name, Address and "Secret (optional)" are `mcp-view.ts:38-40` (`mcp-section.ts:114,131,148`); "Sent to the server with every request. It is kept in the IRIS Wallet and never shown again." is `mcp-view.ts:41`; the name rule is `Mcp/Server.cls:12` (NAMEPATTERN) and `Mcp/Ops.cls:55` (MESSAGENAME).
2. The Wallet and Config Store write (L20, first two sentences): `Mcp/Ops.cls:259-260` creates the Wallet collection and key `OcuTalon_MCP_<server>` / `.Key` holding the secret; `:264-266` writes the entry `AI.MCP.OcuTalon_<server>` (`Mcp/Attach.cls:24` ENTRYPREFIX) with the address and `auth.token` = `secret://<collection>.Key#token`, never the secret; "no message, log, audit entry or answer holds the secret": `Web/McpSettings.cls:16-17` (SecretHandoff, no secret in the command), `Mcp/Ops.cls:16-18,173` (nothing logged), `:617-624` (the audit data holds change and server only). The resource `OcuTalon_MCP_<server>` for the service user: `Install/Step/Mcp.cls:13,55-60,150-151` (Grant) called at `Mcp/Ops.cls:164`.
3. Removing the entry and the secret (L20, last sentence): `Mcp/Ops.cls:203` (Revoke: the pair and the resource) and `:222` with `:278-291` (DropEntry: the entry, the key and the collection). Note: a failed drop is one warning and the removal stands (`:222`); the sentence states the outcome of a removal and is not contradicted.
4. The Tools table and its classification control (L24-L26): "A new server's tools show here once OcuTalon next uses its agents. They count as risky until you classify them." is `mcp-view.ts:36`; the three options "Unclassified (counts as risky)", "Read-only", "Risky" are `mcp-view.ts:67` (`CLASSIFICATION_OPTIONS` :72, a radiogroup at `mcp-section.ts:202`); "Refused: a built-in tool has this name" is `mcp-view.ts:62`; the admin notice for a refused name is `Mcp/Ops.cls:520` (`mcp.toolShadowsBuiltIn`).
5. An admin adding servers from Settings (P1 and P2: "Only admins add or remove a server or classify its tools, only from the settings page"): `Web/Api.cls:323-326` (`not_admin` 403 for a settings URL), `Web/McpSettings.cls:2,52` (admin check on every route), `Mcp/Ops.cls:586-596` (Refusal: origin must be `web_admin` from `CommandsIn`, a tool context is refused), `Mcp/Ops.cls:4-6`.
6. Online demo (L5 of P1, P2 first paragraph): `Web/McpSettings.cls:53` (409 on the demo) and `Mcp/Ops.cls:596-599`.

Every sentence about MCP server addresses (P1 L8, L17; P2 "Servers are reached only over HTTPS (plain HTTP only to this computer, for development)" and the Wallet-reference bullet):
- https, or http only to 127.0.0.1, localhost or [::1]: `Mcp/Ops.cls:45` (LOOPBACKHOSTS) and `:550-571` (AddressAllowed; the loopback test at `:570` refuses http to another host), applied at the add (`:95`) and at every call (`Mcp/Proxy.cls:84`).
- userinfo: `Mcp/Ops.cls:558` (an `@` in the authority is refused); `@{` is refused at `:552`.
- query and fragment: refused on the add path only, `Mcp/Ops.cls:96` (MESSAGEQUERY, `:53`) and `Web/McpSettings.cls:9`; `AddressAllowed`, which `Proxy.cls:84` asks, has no such test (`:550-571`), as the doc's text says nothing about queries.
- the only writer of `AI.MCP.OcuTalon_*`: `SaveMcpEntry` no longer exists (21.4 deleted it); the one writer is now `Mcp/Ops.cls` `SaveEntry` (`:247-274`, `Create` at `:266`, called only from `Register` `:169`, after `OnAdd`'s validation at `:94-96`). The only other `%ConfigStore.Configuration` writers are `Bridge/ConfigStore.cls:66,104` (Merge and Restore, whose Shape accepts only the timeouts and the model fields, never `url`; callers `Bridge/Settings.cls:286,296` and `Bridge/Timeouts.cls:127`) and `Install/Step/Provider.cls:179,181` (AI.LLM). No public sentence names `SaveMcpEntry`.

**Governing ADs (Rule 6):**
- AD-2: the bridge names only its own `Gate.MCPPROXY`.
- AD-10: one gate; the proxy; untrusted turns.
- AD-11: approval, expiry, cancel on removal.
- AD-17: audit types.
- AD-19: `secret://` and the Wallet.
- AD-21: the current AD-21, S9 to S11. "AI Hub lists, OcuTalon calls"; the name refusal; S11's measured known limit, stated and never contradicted.
- AD-22: the mock and the doc checks.
- AD-24: the per-server resource and the privilege profile.
- AD-25: the online demo.
- AD-29: lanes and the docs path for 36.2.
- AD-31: the McpServers extension.

No AC contradicts an AD. The DW-1228 fix makes AD-21's Listing rule ("an MCP tool whose name shadows a built-in is refused") true for the proxy's own name.

**The source part: split out (V2; product default 6).**
- "Sets 'new tickets assigned to me' as a source poll, and shows the digest's Jira entry" needs 22.5 (ready-for-dev, waits for 21.4), 22.11 (not yet in `epics.md`, no spec) and Lane B's 21.5 form. None is built, and 22.11 has no approved text, so writing it now would be guesswork and could not be checked.
- Proposed for the runner to insert after 22.11: **Story 22.12: Document polling a Jira MCP tool as a source**. Its AC is moved verbatim from 22.6: "a worked example ... sets 'new tickets assigned to me' as a source poll, and shows the digest's Jira entry (FR-50, FR-48, UX-DR106)". It extends `docs/mcp-jira-example.md` and depends on 22.5, 22.11 and 21.5. The release check's source half ("new tickets assigned to the user become items with decisions in Visual Trace") goes with it.
- 22.6's first AC keeps "connects a Jira MCP server over HTTPS with its credential as a `secret://` IRIS Wallet reference, classifies its tools ..., and shows ... a held risky call". It is a same-release move of an AC to a not-yet-planned story (veto window 7).

**Order.**
- The worked example describes Story 21.4's Settings section, using only its approved text. Epic 22 merges after 21.4 anyway, because 22.5 waits for 21.4's merge (orchestrator order 22.4 -> 21.4 -> 22.5), so the doc cannot reach the feature branch first.
- 22.6 itself can implement before 21.4. No sentence depends on 21.4's unmeasured secret header form: the docs use T5's approved "Sent to the server with every request." and never say "bearer".

**Decided in-stage:**
1. **"Any built-in tool name".** This is read as the current design: the tools on the manager that the server's tools join (the agent's own tools, the request's turn tools) plus the proxy's name. A name that only another agent uses causes no shadowing. Classification goes by server and name, so such a tool never takes a built-in's classification. The docs say "one of OcuTalon's own tools" (P1) and "one of the agent's own tools" (P2). The cross-runner report inconsistency is filed under `deferred` (inference).
2. **The narrow fix is ordering plus one name.** The order is proxy before the first server's tools, which is AI Hub's measured first-wins rule. No proxy-side name guard is added (smaller). The gate already fails a direct call of a shadowed tool, because the map holds no fingerprint for it.
3. **The overview's switch goes.** `call_mcp_tool` is permanently in `src`, so the switch could only turn checks off. Positive checks replace the four switch controls and the two forced-off controls.
4. **DW-950's sentence.** It was approved in the cycle log with apostrophes and backticks lost. It is rendered with "agent's" and with `ToolClassification` in backticks, which is the guide's convention for setting names; the words are unchanged.
5. **Online demo line of the overview** (L225) is left as it is (true, Epic 29's).
6. **No release-notes text.** The notes list story titles (`release/notes.sh`), and none describes the replay path, so F(2) holds. Epic 22's `notes-areas.txt` line belongs to whoever drafts the release that ships it (`release/**`, Epic 0).

**Extend, don't copy (Rule 2):**
- `MCPSTATEMENT` follows `ONLINESTATEMENT`;
- the new tests are siblings of `TestShadow`, `TestTurnShadow` and `TestDirectCall`, with the same fixtures;
- the doc checks extend `ovw_doc_problems`, `ovw_section` and `ovw_phrases`, and `mcp_doc_problems` reuses them;
- the bridge-guide pins extend `turntools`.

**Integration ACs (Rule 1):** no new service or shared module. The P4 sentence is consumed by `live:security-overview` (the regenerated file must equal the committed one).

**Consumes:**
- 22.2: `RecordAttach` and `Tools(server)`;
- 22.3: `call_mcp_tool`, `MCPLABEL` and the `MCP` audit;
- 22.4: the replay path, which is not described;
- 22.8 and 22.9: the probe and its limits;
- 22.10 Task 0: the 31.1 s and 36.1 s measurements;
- 21.4's approved T4, T5 and T8.

**Consumed-by:**
- 36.2: the docs path and the GUIDE admin sentence;
- 22.12: it extends the worked example;
- 22.7: none.

**Ledger inbox (Rule 17):**
- DW-950: addressed (P6).
- DW-1221: addressed (P1/P2 time limits, pinned).
- DW-1228: addressed (the fix and the tests).

**Footprint:** `Bridge/Ext/McpServers.cls` (doc only) and `docker/tests/test-bridge-guide.sh` are Lane A and are on no contended list.

## Veto items

1. **Public text P1-P7, with proposals G1, G2 and M1** (veto window 5: claims about what the product does).
   - Online demo: none of the docs ships on the demo page, and every one says that MCP is off there. M1 is hidden on the demo.
2. **The split** (window 7): the source poll and the digest's Jira entry, with the release check's source half, move from 22.6 to a new Story 22.12, after 22.11 and 21.5, in the same release (Design Notes).
   - Online demo: n/a.
3. **The request composition change** (DW-1228; window 4, made stronger): the proxy is registered before the first server's tools, and `call_mcp_tool` is a refused name. No privilege, route, table or outward call is added.
   - Online demo: no server is recorded, so the code does not run (`TestDemoOffersNoProxy`).
4. **The generated privileges section gains the P4 sentence** (windows 5 and 2): a statement of the grant that `Install.Step.Mcp` already makes. No grant changes.
   - Online demo: it says there is none.
5. **The ruled bridge-guide lines change** (window 5): the TurnTools bullet gains the sentence approved on 2026-11-08, and the McpServers bullet is new text, replacing the 35.1 ruling's attach description, which 22.9 made untrue.
   - Online demo: n/a.
6. **Spine refinement for the lead (Rule 20, window 9; additive):**
   > S19 (AD-21 Listing; AD-10 proxy): on a request's manager the host's proxy toolset is registered before the first server's tools, and the proxy's name `call_mcp_tool` counts as a built-in name in the attach and offer reports, so a server tool of that name is refused and AI Hub shadows it with the proxy (Story 22.6, DW-1228).

## Public text

All of it is new unless marked (existing). Place: P1 is a new file. P2-P5 go in `docs/security-overview.md` and P6-P7 in `docs/bridge-guide.md`. G1, G2 and M1 are proposals for other lanes, not shipped by this story.

**P1, `docs/mcp-jira-example.md` (new, the whole file):**

````markdown
# A Jira MCP server, step by step

This example adds a Jira MCP server to OcuTalon on your own install, classifies its tools, runs a search and approves a change. Then it explains how OcuTalon governs MCP tools. MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none.

## What you need

- OcuTalon on your own install, and an account that holds the OcuTalonAdmin role, such as the README account.
- A Jira MCP server that OcuTalon can reach over HTTPS, and the token it expects, if it expects one. Plain HTTP works only to this computer, for development.

The tool names below are examples. Your server's names may differ: classify each tool by what it does.

## 1. Add the server

In Settings > Tools and MCP servers, fill in the fields under **Add server**, then press the **Add server** button:

- **Name**: `Jira`. An MCP server's name is a letter followed by up to 39 letters, digits or underscores.
- **Address**: the server's address, for example `https://jira-mcp.example.com/mcp`.
- **Secret (optional)**: the server's token. Sent to the server with every request. It is kept in the IRIS Wallet and never shown again.

OcuTalon keeps the secret in the IRIS Wallet and writes the server's Config Store entry, `AI.MCP.OcuTalon_Jira`, with the address and a `secret://` reference to the secret, never the secret itself. No message, log, trace, audit entry or answer holds the secret. Adding the server also creates its own IRIS resource, `OcuTalon_MCP_Jira`, which OcuTalon's service user must hold for every call of the server's tools. Removing the server removes the resource, the entry and the secret.

## 2. Classify its tools

The server's tools show in the Tools table once OcuTalon next uses its agents, and they count as risky until you classify them. Each tool's control offers Unclassified (counts as risky), Read-only and Risky. For a Jira server:

| Tool (example) | What it does | Classify it |
| --- | --- | --- |
| `search_issues` | searches tickets | Read-only |
| `get_issue` | reads one ticket | Read-only |
| `create_issue` | creates a ticket | Risky |
| `update_issue` | changes a ticket | Risky |
| `add_comment` | comments on a ticket | Risky |

Classify a tool Read-only only when it reads and changes nothing.

An MCP tool that runs operating-system commands or arbitrary code must be classified Risky.

A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads.

If the server offers a tool with the same name as one of OcuTalon's own tools, or one named `call_mcp_tool`, OcuTalon refuses it: the Tools table shows "Refused: a built-in tool has this name", admins get a notice, and the tool is never offered or run.

## 3. Search, then approve a change

In the chat, ask "Find the Jira tickets assigned to me." The search tool is Read-only, so it runs at once. In Visual Trace the call shows as the step "Running search_issues on Jira".

Then ask "Add a comment to OPS-12 saying the feed is fixed." The comment tool is Risky, so nothing runs yet. The chat shows an approval request that reads "Run add_comment on Jira", with its inputs and "No dry run is available for this tool. Approving runs exactly this call once." **Approve** runs exactly that call once, and **Reject** runs nothing. A request that nobody answers within 24 hours expires.

If an admin removes the server while a request for one of its tools is waiting, the request is canceled and nothing runs.

## How OcuTalon governs MCP tools

- Only admins add or remove a server or classify its tools, only from the settings page.
- A new tool, and a tool whose description or inputs changed, is Unclassified, which counts as risky. OcuTalon identifies a tool by its server and its name, and ignores MCP annotations such as `readOnlyHint`.
- Every call goes through one governed tool, `call_mcp_tool`, and passes the same gate as OcuTalon's built-in tools. Before every call, OcuTalon checks that the tool still has the name, description and inputs it was classified with, and runs nothing if it changed.
- In your own turns, a Read-only tool runs at once, and a Risky or Unclassified tool waits for your approval. In a turn that holds content that didn't come from you, such as an email or an MCP tool's result, only Read-only tools run: any other call is denied, and no approval request is raised.
- A tool's results are untrusted content: they can never approve, classify, change a setting or add a server.
- Each call of a server's tool that runs writes an audit entry with the server, the tool and the outcome, never its arguments or its result, and shows as a step in Visual Trace.

The security overview's [MCP tools](security-overview.md#mcp-tools) section lists the same rules.

## Time limits

OcuTalon's time limits for MCP servers are not hard deadlines. A server has 2 seconds to answer OcuTalon's check before a request offers its tools, and each listing of its tools, and 20 seconds to answer a tool call. Each limit applies to each wait for data and starts again whenever the server sends some, so a slow server can hold a request longer: in a test against a server that sent one byte a second, the 2-second check took 31 seconds and a 20-second call 36 seconds. A server that stops answering in the middle of a request, after its check passed, holds that request until it closes the connection.
````

The quoted product text (existing):
- "Tools and MCP servers", "Add server", "Name", "Address", "Secret (optional)", "Sent to the server with every request. It is kept in the IRIS Wallet and never shown again." and "Refused: a built-in tool has this name": 21.4 T5 and T8, approved;
- "Unclassified (counts as risky)", "Read-only", "Risky": the epics' labels;
- "Running {tool} on {server}": `MCPLABEL`;
- "Run {tool} on {server}" and the no-dry-run sentence: `toolCall.requestOnServer`;
- the name rule: `MESSAGENAME`'s words.

`OVW_MCP_RISKY` = "An MCP tool that runs operating-system commands or arbitrary code must be classified Risky."

`OVW_MCP_READONLY` = "A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads." This is the sentence of the 22.8 ruling, for the Planner.

`OVW_MCP_LIMITS` = the "Time limits" paragraph above.

**P2, `docs/security-overview.md`, "## MCP tools":** the whole section, which replaces L203-212.

```markdown
On a local or IPM install, an admin can add MCP servers, and their tools become OcuTalon's tools under the same gate, approval and audit as the built-in ones. The worked example [A Jira MCP server, step by step](mcp-jira-example.md) shows each step. MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none. These rules apply:

- Only admins add or remove a server or classify its tools, only from the settings page.
- Servers are reached only over HTTPS (plain HTTP only to this computer, for development). A server's secret is kept in the IRIS Wallet, and its Config Store entry `AI.MCP.OcuTalon_<server>` holds only a Wallet reference to it, never the secret itself.
- Each server has its own IRIS resource, `OcuTalon_MCP_<server>`, which the service user must hold (the Privileges section).
- A new server's tools arrive unclassified, which counts as risky.
- Tools are identified by server and name and never take a built-in tool's classification. A server's tool with the name of one of the agent's own tools, or the name `call_mcp_tool`, is refused and never offered or run.
- A changed description or input schema makes a tool unclassified again. MCP annotations such as `readOnlyHint` are ignored.
- An MCP tool that runs operating-system commands or arbitrary code must be classified Risky.
- A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads.
- Every call goes through the governed tool `call_mcp_tool` (the Built-in tools table), which checks before the call that the tool still has the name, description and input schema it was classified with, and runs nothing if it changed.
- Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry for each call it lets run (read-only calls included) and an agent step. A call to a removed server's tool runs nothing and writes no audit entry.
- Results are untrusted content.
- Removing a server cancels its pending approval requests.

OcuTalon's time limits for MCP servers are not hard deadlines. A server has 2 seconds to answer OcuTalon's check before a request offers its tools, and each listing of its tools, and 20 seconds to answer a tool call. Each limit applies to each wait for data and starts again whenever the server sends some, so a slow server can hold a request longer: in a test against a server that sent one byte a second, the 2-second check took 31 seconds and a 20-second call 36 seconds. A server that stops answering in the middle of a request, after its check passed, holds that request until it closes the connection.
```

P2 contains no `://` (the overview's URL check counts any `://`, `secret://` included), so its Wallet bullet says "a Wallet reference". The worked example names `secret://`.

Existing bullets kept, some reworded: admins, HTTPS, resource, unclassified, identified by server and name, changed description, gate/approval/audit/step, untrusted results. The old "An MCP tool that runs commands must be classified risky." is replaced by `OVW_MCP_RISKY`.

**P3, `docs/security-overview.md`, Data, "Data leaves the instance only".** This bullet replaces L188:

```markdown
- In calls to the MCP servers an admin has added, never on the online demo: a check that the server answers, the list of its tools, and each tool call with its arguments, which can hold content that OcuTalon read. The results come back as untrusted content.
```

**P4, generated, `Install.SecurityOverview` `MCPSTATEMENT`.** The paragraph after the Roles table:

```markdown
Each MCP server that an admin adds has its own resource, `OcuTalon_MCP_<server>`, with no public permission, and `OcuTalonServiceRole` holds U on it until the server is removed. The gate checks it before every call of that server's tools. On the online demo there is none.
```

**P5, `docs/security-overview.md`, "Approval and audit".** The `MCP` line L153 becomes:

```markdown
- `MCP`: a server added or removed, or a tool called or refused;
```

and L156's second sentence becomes:

```markdown
Pairing, MCP and Tool entries are written only by the features that pair a chat, add or remove an MCP server, call an MCP tool, or classify an MCP tool, so a release without those features writes none of them.
```

**P6, `docs/bridge-guide.md` L316.** The existing TurnTools bullet, unchanged, followed by the DW-950 sentence, approved verbatim by the Planner on 2026-11-08:

```markdown
... It returns none by default. Classify each tool it returns safe (a `ToolClassification` row): a call held for approval runs later on the agent's own tool manager, which does not hold these tools.
```

**P7, `docs/bridge-guide.md` L317 (new; it replaces the 35.1 ruled bullet):**

```markdown
- `OcuTalon.Bridge.Ext.McpServers` (`McpServersClass`): `Servers(servers)` returns the MCP servers to attach, each an object with `server` and `config` (the name of a Config Store entry `AI.MCP.<name>`); `OnAttach(server, report)` receives the report of each attach: `status` (`attached` or `unavailable`), `reason`, the `tools` attached, the `refused` ones (a name that one of the agent's own tools, or the proxy `call_mcp_tool`, already has) and, for an attached server, their `fingerprints`. `Probe(server, config)` says whether a server answers before its tools are offered, and must return within a few seconds; `ProxyToolSet()` names the toolset of the one governed tool, `call_mcp_tool`, through which every MCP call runs; `ServerOf(toolref)` names the server of a toolref; and `ToolsReadOnly(server)` says whether every tool of a server is classified read-only. The agent's own tool manager holds no MCP server: each request gets a manager of its own with the proxy and the servers whose probe answered, an agent that declares skills gets no MCP tools, and an unavailable server never fails the build. It attaches nothing by default.
```

**Proposals for other lanes** (not shipped here; see Contended edits):
- **G1, GUIDE.md "New since 1.0.0", under "#### Your integrations"** (proposed, beside 21.4's approved T9):
  ```markdown
  - **Governed MCP tools.** Every call of an MCP server's tool passes OcuTalon's gate, as a built-in tool's does: a Read-only tool runs at once, in your own turns any other waits for your approval, and each call is audited and shows in Visual Trace. The worked example [A Jira MCP server, step by step](docs/mcp-jira-example.md) shows each step. MCP servers are off on the online demo.
  ```
- **G2, GUIDE.md "For admins and developers"** (Lane B's Story 36.2, per its AC):
  ```markdown
  An MCP tool that runs operating-system commands or arbitrary code must be classified Risky. The worked example [A Jira MCP server, step by step](docs/mcp-jira-example.md) shows how to add a server and classify its tools.
  ```
- **M1, More to try** (Lane B: `web/src/app/guide/more-to-try-view.ts` and `Demo/Features.cls`).
  - Item id `mcp`, `group: 'Safety and settings'`, label "Connect an MCP server".
  - Text: "On your own install, an admin adds an MCP server in Settings, Tools and MCP servers, and classifies each of its tools as Read-only or Risky. Then ask in the chat for something one of its tools does: a Read-only tool runs at once, and any other waits for your approval."
  - Hidden on the demo: `Features.Present` gives `mcp` only when `OcuTalon.Mcp.Ops` is compiled and `onlineDemo` is not 1, as for `webhooks`.

No text from this story describes source polls or the changed-tool replay path. The release notes get no text.

## Contended edits

- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`: Epic 21's 21.4 edits `TestCommands` and `Remove` there. 22.6 only adds two new Test methods (a plain union) and edits no existing line.
- `GUIDE.md` (Epic 0): G1 is proposed for the orchestrator and the Planner. 22.6 does not edit it.
- `GUIDE.md` admin section: G2, for Lane B's Story 36.2 (Epic 36), as its AC says. A proposal for the orchestrator.
- More to try: M1, for a Lane B story that the orchestrator names (suggested: 21.4, which builds the section the item points at). Files: `web/src/app/guide/more-to-try-view.ts` and `src/ocutalon/cls/OcuTalon/Demo/Features.cls`. Not edited.
- `src/ocutalon/cls/OcuTalon/Mcp/Ops.cls`: no edit (the 22.4 -> 21.4 -> 22.5 order is untouched).
- `release/**`, `README.md`: no edit.

## Verification

Every `ci/iris.sh` and `ci/warm.sh` call carries the lane variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Warm mode: run `ci/warm.sh status` first, then `OCUTALON_RUN_TAG=e22s6iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s6iw` on each class call. Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call with `timeout: 600000`, sized to about 150 s. Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: `CLASS ... passed`. Alone in its call: about 165 s before this story, so if the harness moves it to the background, wait with bounded foreground polls.
- (loop) `ci/iris.sh class OcuTalon.Test.Install.SecurityOverview` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.ProxyJob` -- expected: passed (the real runner's request manager)
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Approval` -- expected: passed (the replay is unchanged)
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Ops` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Agent.Runners` -- expected: passed (`TestToolInventory` unchanged)
- (loop) `bash docker/tests/test-release-sequence.sh overviewdoc` -- expected: exit 0
- (loop) `bash docker/tests/test-bridge-guide.sh` -- expected: exit 0, `PASS turntools`
- (loop) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0
- (once) `OCUTALON_RUN_TAG=e22s6i ci/iris.sh live security-overview --write` on a fresh throwaway, then `ci/iris.sh teardown` with the same tag -- expected: `git diff docs/security-overview.md` adds only P4 inside the generated privileges region, beside the hand edits
- (once) `OCUTALON_RUN_TAG=e22s6i ci/iris.sh live security-overview`, then teardown -- expected: pass, no DRIFT line
- (once) `bash docker/tests/test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static` -- expected: exit 0 (named rule subsets; the whole script takes about 170 s)

**Mutation lines (Rule 19; each applied, observed red, reverted byte for byte, `git status --short` and `git diff` identical to before; implement stage, 2026-11-13, lane D warm throwaway `e22s6iw`):**
- `mutation:` one word of the classification sentence changed in `docs/mcp-jira-example.md` ("must be" to "should be") -> rule `overviewdoc` red ("the committed worked example is good: got 'the MCP text lacks the classification sentence word for word'").
- `mutation:` "This release can't connect to MCP servers." put back as the first line of the overview's MCP tools section -> `overviewdoc` red ("the committed overview has a good frame: got 'the MCP tools section still says that the release can't connect to MCP servers'").
- `mutation:` `PrivilegesText` skips `MCPSTATEMENT` -> `Test.Install.SecurityOverview:TestMcpResourceStatement` red (five assertions: the line, once, after the Roles heading, after the last Roles row, before the demo mode section).
- `mutation:` the DW-950 sentence deleted from the TurnTools bullet of `docs/bridge-guide.md` -> `test-bridge-guide.sh` rule `turntools` red ("the guide lacks ruled line 3 of the TurnToolsClass wording").
- `mutation:` `OfferProxy` moved after the first server's `AddTool` in `OfferServers` -> `Test.Mcp.Attach:TestProxyNameNotShadowing` red (the call does not run the proxy, no `tools/call zz_lookup` from client `iris`, no `MCP` audit entry).
- `mutation:` `MCPPROXY` dropped from `builtin` (`WithProxyName` adds nothing) -> `Test.Mcp.Attach:TestProxyNameRefused` red (row, Tools status, notice, notice slots, fingerprint).
- `mutation:` `docs/mcp-jira-example.md` renamed -> `overviewdoc` red ("the worked example is not at docs/mcp-jira-example.md").

**Rework mutation lines (R1, VG1, VG3; rework pass, 2026-11-13, lane D warm throwaway `e22s6qw`; each applied, observed red, reverted byte for byte, `git diff` identical to before):**
- `mutation:` (R1) in a copy-in-place of `docs/security-overview.md`, the `## MCP tools` heading replaced by the old "This release can't connect to MCP servers. When a release adds MCP support, these rules apply:" -> `test-readme.sh` rule `docs` red ("the MCP rules line is not under "## MCP tools" with no other heading between"); 21.14's three pins and controls are kept beside it (union of both sides, no conflict of meaning).
- `mutation:` (VG1) `If registered && 'added Quit 0` in `Bridge/Adapter/Agent.cls` `OfferServers` turned into a comment -> `Test.Mcp.Attach:TestProxyNoneAdded` red ("it lists none of the server's tools and no call_mcp_tool"), and that is the only failure of the class. After the review patch (the test now also asserts that AI Hub's client reached the server in the request and that the build warns once, so a probe that fails cannot pass it), the same mutation was applied again on warm stack `e22s6qw`: `TestProxyNoneAdded` red ("it lists none of the server's tools and no call_mcp_tool"), the only failure of the class; `Agent.cls` restored byte for byte.
- `mutation:` (VG3) `- In calls to the MCP servers an admin has added, never on the online demo: ` shortened in `docs/security-overview.md` -> `overviewdoc` red ("the Data section lacks the MCP bullet word for word").
- `mutation:` (VG3) the `MCP` audit line of the overview cut to "a server added or removed;" -> `overviewdoc` red ("the Approval and audit section lacks the MCP audit line word for word").
- `mutation:` (VG3) " or classify an MCP tool" cut from the Pairing, MCP and Tool sentence of the overview -> `overviewdoc` red ("the Approval and audit section lacks the Pairing, MCP and Tool sentence word for word").
- `mutation:` (VG3) "MCP servers are off on the online demo: nobody can add one there" changed to "are on ... anybody can add one" in the overview -> `overviewdoc` red ("the MCP tools section lacks the sentence that says MCP is off on the online demo").
- `mutation:` (VG3) "within 24 hours expires" changed to "within 48 hours expires" in `docs/mcp-jira-example.md` -> `overviewdoc` red ("the example lacks the sentence that a request expires after 24 hours"; the hours are read from `Bridge.Approval` `EXPIRYSECONDS` in the class source).

**QA stage (2026-11-13, lane D warm throwaway `e22s6qaw`; each mutation applied, observed red, reverted byte for byte, `git status --short` and `git diff` identical to before):**
- (QA) `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`: new `TestProxyNameKeptWithoutProxy` (DW-1228, "the bridge alone is unchanged": on a host that names no proxy, a server's `call_mcp_tool` is no built-in name) and `TestProxyNameRefusedAfterRest` (DW-1228: the request's own report, after a server rested and spoke again, refuses `call_mcp_tool` as the build's did). No existing method or helper was edited; `Test.Mcp.Attach` passes whole (194.52 s).
- `mutation:` (QA) `WithProxyName` adds the proxy's name whether or not `ProxyToolSet` names one -> `Test.Mcp.Attach:TestProxyNameKeptWithoutProxy` red ("the report refuses nothing and attaches call_mcp_tool with the server's other tools").
- `mutation:` (QA) `OfferServers` builds `builtin` without `WithProxyName` -> `Test.Mcp.Attach:TestProxyNameRefusedAfterRest` red ("the request's report says attached and refuses call_mcp_tool again", and the Tools status).
- `mutation:` (QA) `OfferServers` registers the proxy before the probe and the `If registered && 'added Quit 0` guard is commented out (request with no answering server) -> existing `Test.Mcp.Attach:TestTurnServerDown` red (the manager lists `call_mcp_tool`); the two changes are applied together because each alone is caught by the other.
- `mutation:` (QA) `docs/mcp-jira-example.md` loses `](security-overview.md#mcp-tools)` -> `overviewdoc` red ("the example does not link the overview's MCP tools section").
- `mutation:` (QA) `docs/security-overview.md` loses `](mcp-jira-example.md)` -> `overviewdoc` red ("the MCP tools section does not link the worked example").
- `mutation:` (QA) "31 seconds" to "30 seconds" in the time-limits paragraph, in the example and, separately, in the overview -> `overviewdoc` red both times ("the MCP text lacks the time-limits paragraph as one whole line").
- `mutation:` (QA) a "hard deadline" line added to the example, and separately to the overview -> `overviewdoc` red ("a line other than the time-limits paragraph mentions a deadline").
- `mutation:` (QA) a `replayToolChanged` line added to the example, and a "needs a new approval" line to the overview -> `overviewdoc` red ("a line describes the changed-tool replay path").
- `mutation:` (QA) the example's address host `example.com` to `example.org` -> `overviewdoc` red ("an address is not on example.com").
- `mutation:` (QA) "which this release can't make" put back in the overview's Data MCP bullet -> `overviewdoc` red ("the Data section still says that MCP calls are ones this release can't make").
- `mutation:` (QA) the example's demo-off sentence changed to "are on ... anybody can add one" -> `overviewdoc` red ("the example lacks the sentence that says MCP is off on the online demo").
- `mutation:` (QA) the example's title line changed -> `overviewdoc` red ("the first line is not the title").
- `mutation:` (QA) one word of the overview's Read-only sentence, and of its classification sentence, changed -> `overviewdoc` red ("the MCP text lacks the Read-only sentence word for word" / "the classification sentence word for word").
- `mutation:` (QA) a non-ASCII character, and separately a machine path, added to the example -> `overviewdoc` red ("1 line(s) with a character outside ASCII" / "1 line(s) with a machine path").
- `mutation:` (QA) "When a release adds MCP support, these rules apply:" put back in the overview -> `overviewdoc` red ("the MCP tools section still says that the release can't connect to MCP servers").
- `mutation:` (QA) "with the proxy" to "without the proxy" in the McpServers bullet (P7) of `docs/bridge-guide.md` -> `test-bridge-guide.sh` rule `turntools` red ("the guide lacks ruled line 4 of the TurnToolsClass wording").

**Code-review stage (2026-11-13, lane D warm throwaway `e22s6crw`, taken down; each mutation applied, observed red, reverted byte for byte, `git status --short` and `git diff` identical to before):**
- `mutation:` (CR, AC 1) the `add_comment` row of `docs/mcp-jira-example.md` classified Read-only instead of Risky -> `overviewdoc` red ("the committed worked example is good: got 'the example lacks ruled line 5 of its classification and governance text word for word'").
- `mutation:` (CR, AC 2) P2's first sentence ("On a local or IPM install, an admin can add MCP servers, ...") deleted from `docs/security-overview.md` -> `overviewdoc` red ("the committed overview has a good frame: got 'the MCP tools section does not open with the sentence that an admin can add MCP servers on a local or IPM install'").
- `mutation:` (CR, AC 6) the online-demo guard of `OcuTalon.Mcp.Attach` `Servers` (`If ##class(OcuTalon.Mcp.Proxy).OnlineDemo() Quit $$$OK`) commented out -> `Test.Mcp.Attach:TestDemoOffersNoProxy` red (Servers lists the server on the demo, the build records the MCP spec, the native call runs, the server gets requests); restored, the method passes again.
- After the review patches: `bash docker/tests/test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static`, `bash docker/tests/test-bridge-guide.sh` and `bash docker/tests/test-readme.sh docs` exit 0; `ci/iris.sh class OcuTalon.Test.Mcp.Attach` passed (186.93 s).

**Rework 2 (R7-1, R7-2, R7-3; 2026-11-13): no pin was added or changed; the existing pins already hold the text.** The example's "cancelled" sentence is pinned by no rule, and none is added (the spec is `oversized`; the item names no new pin). The overview's :221 bullet is pinned whole by `docker/tests/test-readme.sh` rule `docs` (`L187`, once, under `## MCP tools`), which came with 21.4. `mutation:` none (nothing new to mutate). After the edit, exit 0: `bash docker/tests/test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static`, `test-readme.sh`, `test-bridge-guide.sh`, `test-boundaries.sh`, `test-class-rules.sh`; lane D warm `e22s6vw` (taken down): `Test.Install.SecurityOverview` 12.96 s, `Test.Mcp.Ops` 6.33 s, `Test.Mcp.Attach` 198 s passed; `OCUTALON_RUN_TAG=e22s6v ci/iris.sh live security-overview` fresh: all checks passed, no DRIFT.

**Rework 3 (R8-1, R8-2, R8-3; 2026-11-14; no IRIS runtime; each mutation applied, observed red, reverted byte for byte, `git status --short`, `git diff --stat` and a checksum of `git diff` identical to before):** `docker/tests/test-release-sequence.sh` `ovw_mcp_example_lines` gains the Add server step line as ruled line 14 and carries the audit bullet with "that runs" as ruled line 13 (whole-line pins in `mcp_doc_problems`), with two fault controls in `t_overviewdoc`.
- `mutation:` (R8-1) line 14 of `docs/mcp-jira-example.md` put back to "In Settings > Tools and MCP servers, press **Add server** and fill in:" -> `overviewdoc` red ("the committed worked example is good: got 'the example lacks ruled line 14 of its classification and governance text word for word'"); the new control's own fault gives the same line.
- `mutation:` (R8-3) "that runs" dropped from the audit bullet (L57) of `docs/mcp-jira-example.md` -> `overviewdoc` red ("the committed worked example is good: got 'the example lacks ruled line 13 of its classification and governance text word for word'").

**Shared surfaces:**
- the attach and offer reports' `refused` list and `Mcp.Server.RefusedTools`;
- the order of a request manager's tools (`Test.Mcp.Attach`, `ProxyJob`, `Approval`);
- the generated privileges region (`live:security-overview`, `Test.Install.SecurityOverview`);
- the ruled lines of `docs/bridge-guide.md` (`turntools`; `live:documents` reads only the Filter line, unchanged);
- the `overviewdoc` fixtures.

Every test added or changed passes on a fresh environment, in either order. CI runs the shards and `live:security-overview`, and the lead runs Rule 19's fresh-environment check.

## Auto Run Result

Status: done
Blocking condition: none

Rework pass (iteration 1 of 3) over the three open `[Review]` items, under the orchestrator's rulings (the five Story 21.4 sentences are VERIFY AT MERGE and were not checked against this tree).

- Summary: R1 re-applied over Story 21.14 with `git apply --3way`, a plain union (21.14's `L2114` pin and its three controls are kept beside the `## MCP tools` re-pin); VG1 `TestProxyNoneAdded` (the `If registered && 'added Quit 0` branch of `OfferServers`, on a host that names a proxy); VG3 four overview pins (demo-off sentence, P3 Data bullet, the `MCP` audit line, the Pairing, MCP and Tool sentence) and the worked example's expiry pin (hours read from `Bridge.Approval` `EXPIRYSECONDS`), each with a fault control. The ledger and standing items (DW-950, DW-1221, DW-1228, online-demo safety, the M(4) conditions (a) and (b)) are ticked after confirmation on this tree; M(4)(c) and (d) stay merge-time conditions of Stories 21.10 and M1, unchanged by this pass.
- Files changed: `docker/tests/test-readme.sh` (rule `docs`: `MCP_FRAME`, the awk check, two controls, the header comment), `docker/tests/test-release-sequence.sh` (`overviewdoc`, `mcp_doc_problems`: the new pins and controls, header comment), `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` (new `TestProxyNoneAdded`), and this spec (ticks, mutation lines, triage log).
- Review: four layers, 17 findings. Patched: 2 (BH7 + VG1 medium: `TestProxyNoneAdded` now also asserts that AI Hub's client reached the server and the one warning; BH6 low: comment re-wrap). Deferred: 0 new. Rejected: 15 with their reasons in the triage log (BH1-BH5, EC2, EC3, VG2, VG3, IA1-IA6; BH1 covers EC1).
- Follow-up review recommendation: false (this follow-up pass patched no `high`; patched counts: high 0, medium 1, low 1).
- Verification: `Test.Mcp.Attach` 165.96 s (after the patch; 174.37 s before it), `Test.Install.SecurityOverview` 11.95 s, `Test.Mcp.ProxyJob` 4.23 s, `Test.Mcp.Approval` 79.31 s, `Test.Mcp.Ops` 8.27 s, `Test.Agent.Runners` 40.54 s passed on lane D warm stacks `e22s6qw` (taken down); `test-readme.sh` (whole file), `test-bridge-guide.sh`, `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh`, `test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static` and `bash ci/checks.sh` (32 scripts) exit 0; `OCUTALON_RUN_TAG=e22s6q ci/iris.sh live security-overview` on a fresh throwaway: no DRIFT. The VG1 mutation was re-run after the patch (red, reverted).
- Residual risks: `TestProxyNoneAdded` relies on the real probe counting any HTTP status as an answer (`Mcp/Client.cls`); the five Story 21.4 sentences and M(4)(c)/(d) are checked at merge.

### Rework pass 2 (iteration 2 of 3; R7-1, R7-2, R7-3)

Status: done
Blocking condition: none

- Summary: R7-1 `docs/mcp-jira-example.md` L48 "canceled" to "cancelled" (DW-1286, one word; no pin held the sentence, none added). R7-2 confirmed: the overview's :221 bullet is Story 21.4's bullet word for word (kept "cut to 200 characters"), P2's other bullets stand, and the spec's Public text P2 now carries the merged wording. R7-3 verified at merge: all five Story 21.4 sentences and every MCP-address sentence are true of the merged code; file:line evidence is under Design Notes ("Verified at merge"). No false sentence, no code change, no `PUBLIC TEXT:` needed.
- Files changed: `docs/mcp-jira-example.md` (one word), this spec (ticks, P2 text, evidence, Spec Change Log line, triage log, Rework 2 note).
- Review: four layers, 16 findings. Patched: 2 entries (low: three off-by-one citations; the Rework 2 note's false "pinned by no rule" and missing results). Deferred: 0. Rejected: the rest with reasons in the triage log (P1 spec copy still "canceled", audit-wording readings of ruled text, the unpinned "cancelled" sentence, and three false claims).
- Follow-up review recommendation: false (this follow-up pass patched no `high`; patched counts: high 0, medium 0, low 2).
- Verification: `test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static`, `test-readme.sh`, `test-bridge-guide.sh`, `test-boundaries.sh`, `test-class-rules.sh` exit 0; lane D warm `e22s6vw` (taken down): `Test.Install.SecurityOverview` 12.96 s, `Test.Mcp.Ops` 6.33 s, `Test.Mcp.Attach` 198 s passed; `OCUTALON_RUN_TAG=e22s6v ci/iris.sh live security-overview` on a fresh throwaway: all checks passed, no DRIFT.
- Residual risks: the "cancelled" sentence is held by no pin (reopen_if it is edited with every rule green); the spec's P1 block keeps the old spelling (the shipped file governs).

### Rework pass 3 (iteration 3 of 3; R8-1, R8-2, R8-3)

Status: done
Blocking condition: none

- Summary: R8-1 and R8-2 put the two Planner-approved texts word for word into `docs/mcp-jira-example.md` (L14: fill in the fields under **Add server**, then press the **Add server** button; L57: "that runs"). R8-3 pins both lines in `mcp_doc_problems` with a fault control each. DW-1324 is resolved in the spec's records.
- Files changed: `docs/mcp-jira-example.md` (two lines), `docker/tests/test-release-sequence.sh` (`ovw_mcp_example_lines`: the audit line and the new step line; two controls in `t_overviewdoc`), this spec (ticks, P1 text, change log, triage log, Verification mutations).
- Review: four layers, 13 findings. Patched: 0. Deferred: 0. Rejected: 13, with reasons in the triage log (whole-file pin grammar, "that runs" is true and approved, stale spec records, another story's AC text).
- Follow-up review recommendation: false (this follow-up pass patched no `high`; patched counts: high 0, medium 0, low 0).
- Verification: `bash docker/tests/test-release-sequence.sh overviewdoc overview overviewunit overviewdrift static` (PASS all rules), `test-readme.sh`, `test-boundaries.sh` and `test-ci-config.sh` exit 0, run by the lead after the handoff; both mutations observed red and reverted byte for byte (see `## Verification`). No IRIS runtime was used.
- Residual risks: "that runs" does not mention a reached-but-refused call, which also writes an audit entry (approved wording; the sentence is true); the line pins match anywhere in the file.
