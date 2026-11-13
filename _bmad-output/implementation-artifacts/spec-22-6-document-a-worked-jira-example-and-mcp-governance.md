---
title: 'Story 22.6: Document a worked Jira example and MCP governance'
type: 'feature'
created: '2026-11-13'
status: 'done'
baseline_revision: 'e59670247bdfcd4d5b831574d77e058d5305c3a8'
baseline_commit: 'c13b1836a4885ecbc77a55bffc34f4dce01fd7e0'
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

## Spec Change Log

- 2026-11-13 (runner, Planner ruling M (4)): gate APPROVED with the text conditions above; Story 22.12 to be inserted in epics.md.

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

## Design Notes

**Ruled 2026-11-13 ~19:00Z (orchestrator, prompts/epic-22-rulings-20261113-1715.md, Step 3): VERIFY AT MERGE** (ruling M(4): "true of the code at merge"). The five sentences that describe Story 21.4's Settings surface (Add server; the Wallet and Config Store write; removing the entry and the secret; the Tools table and its classification control; an admin adding servers from Settings) ship as approved text and are NOT checked against this tree: 22.6 does not push or merge before 21.4 merges; then it integrates forward and a review layer checks each of the five against the merged code (a false claim is a STOP with PUBLIC TEXT; code is never changed to fit the text). Every other sentence must be true of this tree.

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

In Settings > Tools and MCP servers, press **Add server** and fill in:

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
- Each call of a server's tool writes an audit entry with the server, the tool and the outcome, never its arguments or its result, and shows as a step in Visual Trace.

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
- Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step.
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
