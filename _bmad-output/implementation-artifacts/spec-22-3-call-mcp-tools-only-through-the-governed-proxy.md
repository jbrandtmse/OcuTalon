---
title: 'Story 22.3: Call MCP tools only through the governed proxy'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-8-classify-mcp-calls-by-fingerprint-in-the-gate.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-9-bound-mcp-attach-and-listing-with-a-timeout.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-9-task0-mcp-hang.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Stories 22.8 and 22.9, the gate classifies an MCP call, but an allowed call still runs through AI Hub's MCP client. That client has no deadline and no hook to cut the result (S9), so the result is never cut to the step's 10,000 tokens. Nothing checks at call time that the tool is still the one the admin classified. The gate checks no `OcuTalon_MCP_<server>` permission, and no IRIS audit entry records the call. Its step label is the generic "Running a tool".

**Approach:**
- Add the governed proxy tool `call_mcp_tool(server, tool, arguments)` in a new toolset of `OcuTalon.Tools`. It runs through OcuTalon's own bounded client, which extends 22.9's `OcuTalon.Mcp.Client` with `tools/list` and `tools/call`.
- Just before `tools/call`, the proxy lists the tool, refuses a changed fingerprint unrun, cuts the result through `OcuTalon.Tools.Result` and writes one audit entry.
- A request's composed manager offers the proxy only when an MCP server is attached.
- The gate classifies a direct proxy call by its (server, tool) arguments, exactly as it classifies the native MCP call. It checks the server's resource and rewrites every allowed native MCP call into the proxy.

## Boundaries & Constraints

**Always:**
- **Lanes (U-177).** Lane A files only:
  - the bridge's `Policy/Gate.cls`, `Context.cls`, `Adapter/Agent.cls` and `Adapter/StepBuffer.cls`;
  - footprint extensions `Ext/Classification.cls` and `Ext/McpServers.cls`;
  - `Mcp/**`, `Tools/**`, `ci/mock/scenarios/A/**` and `ci/mock/test/constants.test.mjs` (the Names pin);
  - the generated tools section of `docs/security-overview.md`;
  - `Test/{Mcp,Bridge,Tools,Agent,Install}/**`, Lane A rows only.
- **AD-2.** The bridge names no OcuTalon class. The proxy's toolset and the server's resource reach the bridge only through the `McpServersClass` and `ClassificationClass` extensions (AD-31). The tool name `call_mcp_tool` is a bridge constant (`Gate.#MCPPROXY`), and a test pins it equal to `Tools.Names.#CALLMCPTOOL`.
- **AD-6.** Callback code (the gate, the proxy tool and the classes they call) names `%AI` on no code line, runs no Python, starts no job and never uses a tool manager.
- **Fail closed.** The gate keeps failing closed. The proxy refuses unrun, with a plain sentence, when any of these holds: the online demo; an unknown server, an unknown tool or a missing entry; a `url` that is neither `https://` nor loopback `http://` (`McpOps.AddressAllowed`'s rule); a timeout; a malformed answer; a changed fingerprint; a classification that is no longer the one the gate allowed.
- **Secrets.** The entry's `secret://` reference is resolved only in memory, at call time, into the request header. No secret value, URL, argument value or result text is ever logged, audited, traced, stored or returned. Error text that could carry them only picks a reason word (35.1's rule).
- **Untrusted results.** An MCP result is never trusted output. Every allowed proxy call taints the turn (AD-10 rule 3; quarantine 3a follows). A result can approve, classify, change settings or add servers only through the gate, which already refuses all of these.
- **Online demo.** The proxy is never offered, because no server can exist there. A direct call is refused with the demo sentence before any outbound request. Built-ins are unchanged, and `Test.Bridge.Gate`, `Test.Agent.Runners` TestToolInventory and the demo-path tests stay green.

**Never:**
- The MCP replay or `Approval.Cancel` (22.4), source polls (22.5), the hand-written "MCP tools" section of `docs/security-overview.md` and the bridge guide (22.6), the email tool (22.7), or listing and offering through OcuTalon's client (22.10).
- Edit `Core.SettingsOps`, `Core.CommandsIn`, `Web.*`, `web/**`, Channel or Settings code, `Test/Contract/**` or any Lane B test.
- Write a Config Store entry or a wallet secret, or add a route, table, column, resource, grant or privilege.
- Put the proxy in an agent's `TOOLSETS`, read MCP annotations, use a real MCP server, follow redirects, or delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Rewrite | the model calls native `zz_lookup` (read-only, fingerprint matches); the gate allows it | the call runs as `call_mcp_tool {"server":<name>,"tool":"zz_lookup","arguments":{…}}`. The mock logs one `initialize`, one `tools/list` and one `tools/call` from `client` `iris`, and none from AI Hub's client. There is one `turn.step` and one step record, both labelled `Running zz_lookup on <server>`. The turn is tainted. | none |
| Direct call | the model calls `call_mcp_tool` itself | the gate classifies `(server, tool)` through `ClassifyMcp` with the turn map's toolref and fingerprint for that server and tool, exactly as for the native call: read-only runs; risky or unclassified is HELD (user turn) or UNTRUSTED | a server or tool missing from the map counts as unclassified |
| Not registered | `server` names no `Mcp.Server` row | UNREGISTERED (22.8) before any other step; no outbound request | none |
| No permission | the service user lacks `U` on `OcuTalon_MCP_<server>` | denied with the gate's existing privilege sentence; nothing runs | none |
| Rug-pull in a request | after the turn's map is built, the server changes `zz_lookup`'s description (case 2: its input schema) | the proxy's own listing gives a different `ToolFingerprint`; the call is refused unrun with `MCPCHANGED`; the mock logs no `tools/call`; no row write from tool code | none |
| Cut | the tool returns text longer than the step's room | the result is cut by `Tools.Result.Return` and marked `[cut by OcuTalon: …]`; the step total counts it | none |
| Server error or silent | `tools/call` gives JSON-RPC `error`, `isError` true, HTTP non-2xx, or no answer within `CALLSECONDS` | a plain refusal (`MCPFAILED`, or `MCPTIMEOUT` within about `CALLSECONDS` + 1 s); never the server's error text | reason word only |
| Online demo | `onlineDemo` 1, direct call | `MCPDEMO`, before any request; the gate's existing demo behaviour is unchanged | none |
| Audit | every proxy run that reached the server, refused or completed | exactly one IRIS audit entry `MCP` `{change: called|refused, server, tool, outcome}`; no arguments and no result | audit failure: one redacted warning; the result is still returned |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `%CanExecute` L127, `Check` L140 and `Decision` L158 (classification L165, privilege L166, untrusted L169, hold L170-174, taint L186-189).
  - The rewrite precedent is the RAG clamp: `ClampTopK` L242-265, `RewrittenBefore` L272 and `^||OcuTalonBP.RagRewrite` L177-180. A member is changed with `call.%Set`, and AI Hub then runs the policy a second time.
  - `ClassificationOf` L311 (MCP branch L314), `MissingPrivilege` L363 (gives "" for MCP today), `MissingOf` L372-391, `ReportStep` L394-402, `IsMcp` L526 and `MCPPREFIX` L98.
  - The sentences are at L72-84. The header comment L44 and L54 says "the gate's only rewrite".
- `src/bridge/cls/OcuTalon/Bridge/Context.cls`:
  - `ToolFingerprint` L188, `ArgumentsHash` L172.
  - 22.8's node `mcp` (`SetMcpTools`, `McpFingerprint`), which this story extends with each server's toolref.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `BuildTurnManager` L486. 22.9 rewrites its MCP loop, so register the proxy toolset after the first MCP server is added.
  - `Govern` L398, and 22.9's per-request record of (server, spec).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` L155, `ToolParameter` L167, `Records` L104-138 (Redact, then cut).
- `src/bridge/cls/OcuTalon/Bridge/Ext/{Classification,McpServers}.cls` -- 22.8's `ClassifyMcp` and 22.9's `Probe`.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` L78 -- `Record(type, data)`, `TYPES`, `SHAPEMCP` and `MCPCHANGES`.
- `src/ocutalon/cls/OcuTalon/Mcp/Client.cls` (22.9) -- `Probe`, `PROBESECONDS`, the request setup. Extend it here; do not copy it.
- `src/ocutalon/cls/OcuTalon/Mcp/{Attach,Classification,Ops,Server,ToolClassification}.cls`:
  - `Ops.AddressAllowed` L458 and `Ops.OnlineDemo` L585;
  - `Attach.ENTRYPREFIX`;
  - 22.8's `Classification.ClassifyMcp`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Mcp.cls` -- `ResourceOf(server, .sc)`, `RESOURCEPREFIX`, `PERMISSION` "U".
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls` -- `Details(entry, .details)` L115 (no secret resolved) and `FullName` L143.
- The tools:
  - `src/ocutalon/cls/OcuTalon/Tools/Result.cls` -- `Return` L35, `CUTNOTE` L26.
  - `Tools/Names.cls` -- the parameters; `RELEASE1` L31 stays.
  - `Tools/Memory.cls` / `MemoryTools.cls` -- the toolset and provider pattern (the `STEPLABEL…`, `CLASSIFICATION…`, `READONLY…` and `TRUSTEDOUTPUT…` parameters).
  - `PersonaTools.cls` L32 -- the demo refusal pattern.
  - `Watch/Reader.cls` L175 `OnlineDemo()`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:
  - `GOVERNANCE` L106 matches `ocutalon[._]mcp`, so no tool may name `OcuTalon.Mcp`.
  - `CALLBACKHELPERS` L82, `TestToolsHaveStepLabels` L643, `TestToolCodeScan` L787.
- The pinned tool lists:
  - `Test/Install/SecurityOverview.cls` `CheckToolRows` L62-86 and `TestToolsMatchRunners` L492 (the `documents` turn-tool precedent);
  - `Test/Agent/Runners.cls` L323 `TestToolInventory` (unchanged: the proxy is no tool of an own manager);
  - `ci/mock/test/constants.test.mjs` L50-52 and L86-99.
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- `ToolRows` L88 and `Regenerate` L548. Scope: `Install/Step/Tools.cls` `Toolsets()` L22, every `%AI.ToolSet` under `OcuTalon.Tools.`. `docs/security-overview.md` L5-36 is the generated section; L195 is the hand-written MCP section, which stays as it is.
- `docker/tests/test-release-sequence.sh` L2221 and L2256 -- once `src` contains `call_mcp_tool`, its can't-connect checks are skipped. Expected; 22.6 rewrites that section.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`:
  - `tools/call` L200-238; the description override (22.2) and the silent mode (22.9);
  - `Requests` (`method`, `tool`, `auth`, `answered`, `client`).
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` -- `Entry` L603-617 (the wallet and Config Store fixture), `Register`, `Use`, `Leaks` and `LoggedSecret` L815.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement stage, lane A's warm throwaway; scratch classes `ZzT3`, removed afterwards). Record each answer in `_bmad-output/implementation-artifacts/evidence/22-3-task0-proxy.md`:
  1. With the shadow runner and the mock, the gate's first pass on a native `zz_lookup` call sets `call.%Set("name","call_mcp_tool")` and `call.%Set("arguments",{server,tool,arguments})`, a second variant also sets `toolref`, and the composed manager holds the proxy toolset. For each variant, record:
     - what runs (the proxy's method, or AI Hub's `tools/call`, by the mock's `client` field);
     - whether the policy runs a second time, and what `toolref`, `call` and `metadata` it then gets;
     - what the model's tool result carries.
  2. Whether the runner job (the service user) can resolve the entry's `secret://` reference from the wallet, and through which API. If it cannot, record the measured error and STOP with an intent gap: no grant is added here.
  3. The rule: if a variant makes the proxy run in place of AI Hub's call, implement the rewrite with it. If none does, STOP with an intent gap naming fallback F1 (Design Notes), unless the runner has recorded F1 as accepted. In that case implement F1 with the `MCPUSEPROXY` sentence.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Client.cls` -- extend 22.9's client:
  - `Parameter CALLSECONDS = 20`.
  - `ListTool(url, header, tool, .definition) As %String` sends `initialize` and `tools/list`, follows `nextCursor` up to 10 pages, and finds the tool by name.
  - `CallTool(url, header, tool, arguments, .result) As %String` sends `tools/call`.
  - Both share one private request method with `Probe`: `OpenTimeout`/`Timeout`, `FollowRedirect` 0, `OcuTalonClient` for `https`, and `Mcp-Session-Id` kept from `initialize`.
  - Each accepts a JSON body or a single-event `text/event-stream` body. Each answers `""` or a reason word (`unreachable`, `timeout`, `failed`, `notfound`). Neither throws, logs or returns a URL or header.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls` (new, read-only) -- `Call(server, tool, arguments) As %DynamicObject`, in this order:
  1. demo refusal;
  2. `Server.NAMEPATTERN`, the row and the `ToolClassification` row, which must not be `unclassified`;
  3. the entry through `ConfigStore.Details`; the `url` through `Ops.AddressAllowed`;
  4. the header resolved per Task 0;
  5. `ListTool`; `ToolFingerprint(description, inputSchema)` must equal the row's `Fingerprint`, otherwise refuse with `MCPCHANGED`;
  6. `CallTool`;
  7. join the `content` text parts (other part types become `[non-text content omitted]`);
  8. one `Bridge.Audit.Record("MCP", …)`.

  It answers `{text}` or `{refusal}`. It writes no row and never calls `ClearChanged`: the next turn's map clears the row (22.8).
- [ ] `src/ocutalon/cls/OcuTalon/Tools/McpProxy.cls` (new `%AI.ToolSet`) and `Tools/McpCall.cls` (new, extends `Tools.Result`):
  - `CallMcpTool(server, tool, arguments As %DynamicObject)` returns `..Return(text)` or the refusal sentence. Its schema descriptions are under Public text.
  - Parameters: `STEPLABELCALLMCPTOOL` (the fallback label), `CLASSIFICATIONCALLMCPTOOL` "risky", `READONLYCALLMCPTOOL` 0 and `TRUSTEDOUTPUTCALLMCPTOOL` 0. These are the static fallbacks, because the gate classifies the proxy per call. Also `CLASSIFYRULECALLMCPTOOL` for the overview's "per call:" row.
- [ ] `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- `Parameter CALLMCPTOOL = "call_mcp_tool";`. The comment says it is not a release-1 tool.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ProxyToolSet() As %String`, default `""`. The bridge alone has no proxy and lists no server. `Mcp/Attach.cls` overrides it with `OcuTalon.Tools.McpProxy`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `ClassifyMcp`'s answer gains an optional `resource` (default absent). `Mcp/Classification.cls` sets it to `Install.Step.Mcp.ResourceOf(server)`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- node `mcp` also keeps server name to toolref, from the adapter's recorded (server, spec) pairs. Add `McpToolref(server) As %String`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- after the first MCP server is added to a request's manager, `RegisterToolSet(ProxyToolSet())`. On error: one warning, the MCP tools are removed from that request's offer, and the request goes on. Pass the (server, spec) pairs to the map. Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `MCPPROXY` = "call_mcp_tool".
  - A direct proxy call (name `MCPPROXY`, not `mcp:`) is classified as `ClassifyMcp(McpToolref(server), tool, McpFingerprint(toolref, tool))`. No toolref counts as unclassified.
  - `MissingPrivilege` checks `U` on the answer's `resource` for MCP and proxy calls. No resource from the host means no check (bridge alone).
  - After an allow (Task 0's variant), rewrite a native MCP call to the proxy. Mark the rewrite like `RagRewrite`, so the second pass reports no second step and re-taints nothing new.
  - Restate the doc ("two rewrites").
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` gives the `MCPLABEL` text for an `mcp:` call and for a proxy call whose server matches `[A-Za-z0-9_]{1,40}` and whose tool is in the map. Otherwise it gives the proxy's fallback label. Never the arguments.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- `MCPCHANGES` gains `called` and `refused`, with a call shape `change,server,tool,outcome`. `outcome` is a fixed word: `ok`, `cut`, or a refusal or reason word.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `GOVERNANCE` lets a tool name exactly `OcuTalon.Mcp.Proxy` (a negative lookahead after `ocutalon[._]mcp`). Add `Mcp.Proxy`, `Mcp.Client`, `Install.Step.Mcp` (only `ResourceOf`) and `Bridge.ConfigStore` to `CALLBACKHELPERS`. A new test shows that `Mcp.Proxy` names no `%Save`, `Ops.` writer, `ClearChanged`, `SettingsOps` or `Approval`.
- [ ] `ci/mock/scenarios/A/mcp-proxy-call.json` (new; mockkey `chat` is not used, marker `mcp-proxy-call`) and `ci/mock/test/constants.test.mjs` -- a script whose `toolUse` is `call_mcp_tool`, and a "the mock reads call_mcp_tool" test. The Names count rises by one.
- [ ] The overview and its pins:
  - `Test/Install/SecurityOverview.cls` -- `CheckToolRows` adds `CALLMCPTOOL`. `TestToolsMatchRunners` treats it like `documents`: offered only by a composed request with an MCP server, so it appears in no own-manager inventory.
  - `docs/security-overview.md` -- regenerate only the generated tools section, through `Regenerate`.
- [ ] Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls` -- `ListTool` (pagination, notfound, SSE body) and `CallTool` (ok, `isError`, silent → `timeout` within `CALLSECONDS` + 3 s).
  - `Test/Mcp/Proxy.cls` (new) -- every Proxy row of the matrix, the no-secret scan (`LoggedSecret`) and no leftovers.
  - `Test/Bridge/Gate.cls` -- the direct-call rows, the resource check, the rewrite mark and built-ins unchanged.
  - `Test/Mcp/Attach.cls` -- `TestProxyRewrite`, `TestRugPullInRequest` (description, then schema), `TestProxyCut` and `TestDirectCall` through the shadow runner, plus `Leaks`.

**Acceptance Criteria:**
- [RULED 2026-11-11, Contest Planner condition on text 1] Given a tool or server name with markup, control characters or more than 64 characters, when the step label "Running {tool} on {server}" is built and shown, then each slot is plain text (escaped on the web page, sent with no Telegram parse mode) and cut to 64 characters ending with "\u2026".
- [RULED 2026-11-11, condition (a)] Given a fixture server whose Config Store entry carries a `secret://` reference to a test credential, when `call_mcp_tool` runs (called, refused and failed cases), then a grep of the message bodies, the Visual Trace (the session's messages), the event log and the audit entries written during the test finds the test credential nowhere.
- [RULED 2026-11-11, condition (b)] Given an `https://` server, when the proxy calls it, then the request verifies the server certificate (`VerifyPeer` on, no accept-any setting), and a plain `http://` address other than this computer (127.0.0.1, localhost, [::1]) is refused before any request.
- [RULED 2026-11-11, condition (c)] Given a `tools/call` result, when it returns to the turn, then the turn is tainted (AD-10) and the result is cut to the request size limit, marked as cut, before it reaches the model; both are pinned by tests.
- [RULED 2026-11-11, condition (d)] Given any proxy run, when it is audited, then the entry holds the server, the tool and the outcome only, never the arguments or the result.
- [RULED 2026-11-11, condition (e)] Given the runner job cannot read the wallet secret (Task 0 (2)), then the implement stage stops with an intent gap; no grant is added without a ruling.
- Given a read-only MCP tool and a composed turn (a user's turn, and separately an untrusted item's turn, where a risky tool's call is still denied UNTRUSTED and described as an offer), when the model's native call is allowed, then it runs only through `call_mcp_tool` (the mock logs only `client` `iris` requests for it), its result passes `Tools.Result`, one step is labelled with the server and tool, the turn is tainted, and one `MCP` `called` audit entry exists.
- Given a turn whose map was built, when the server changes the tool's description (and, in a second case, its input schema) before the call, then the proxy refuses it unrun with `MCPCHANGED`, the mock logs no `tools/call`, and one `refused` audit entry exists. Mutation: skip the proxy's fingerprint compare → red.
- Given a result longer than the step's room, when it returns, then the model gets it cut and marked, and the step's total stays within 40,000 characters.
- Given a direct `call_mcp_tool` call, when the gate decides it, then its decision equals the native call's for the same (server, tool) in every row: read-only, risky, unclassified, unregistered and no permission.
- Given the service user without `U` on `OcuTalon_MCP_<server>`, when an MCP or proxy call reaches the gate, then it is denied and nothing reaches the server.
- Given an online-demo install, when any request runs, then no request offers `call_mcp_tool`, a direct call is refused with `MCPDEMO` before any outbound request, and the built-ins, `Test.Bridge.Gate`, TestToolInventory and the demo path are unchanged.
- Given any test of this story, when its output, logs, audit entries and step records are searched, then the fixture secret, the mock's URL and the call's argument values appear in none of them.

## Spec Change Log

- 2026-11-11 (runner, rulings applied): the Contest Planner's 22.3 rulings (verbatim under Design Notes) are applied: texts 1-10 approved (text 1 slots plain and cut to 64 characters), veto accepted with conditions (a)-(e) added as ACs, F1 pre-approved, spine S12-S14 written.

- 2026-11-11 (runner, spec gate): validated (no split). The Veto items, the Public text table (10 proposed strings, incl. F1's), fallback F1 and spine updates S12-S14 go to the Contest Planner (via the orchestrator) before the implement stage; this story implements only after Stories 22.8 and 22.9 are committed.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: the bridge names no host class.
- AD-6: callbacks make no `%AI` call and no tool-manager call; the proxy uses its own HTTP client.
- AD-9: steps.
- AD-10: the gate; the proxy; the cut; taint; fingerprints at call time.
- AD-17: one audit writer.
- AD-19: `secret://`.
- AD-21: "AI Hub lists, OcuTalon calls" (Calling, Step 4 build).
- AD-22: the mock, and the Names constants.
- AD-24: the permission check's limits.
- AD-25: the online demo.
- AD-29: lanes.
- AD-31: extensions.

**Decided in-stage:**
1. **Offered only with a server.** The proxy is offered only by a request's composed manager that holds an MCP server. It is not in any agent's `TOOLSETS`. So the online demo and every install without a server offer it nowhere, and the agents' own inventories, the demo path and TestToolInventory are unchanged. 22.4 (replay) and 22.5 (poll) are `tool` requests on the own manager, and they compose the proxy there themselves: Consumed-by below.
2. **The tool is the bridge's constant.** The name `call_mcp_tool` is a bridge constant, because AD-21 fixes it as the proxy contract. The toolset class comes from the host through `McpServers.ProxyToolSet()`.
3. **The resource rides on `ClassifyMcp`.** The permission's resource comes with `ClassifyMcp`'s answer, so one host call per check gives the classification and the resource together.
4. **The proxy never writes the classification row.** A change is refused, and the next turn's map clears the row through `ClearChanged` (22.8). So tool code gets no classification write, and GOVERNANCE is narrowed by one read-only class only.
5. **Bounds.** `CALLSECONDS` 20 for `tools/call` and 22.9's 2 s for `initialize` and `tools/list`. The worst case is about 24 s, inside Decide's 60 s timer (inference: a healthy remote tool answers within 20 s).
6. **The audit record.** It goes to type `MCP` (`called`/`refused`) and never records argument values. One entry per proxy run that passed the gate, and none for a gate denial, which the step audit policy records.
7. **No split.** About 9 source classes and 4 test classes, against the product default of 6. The rewrite, the proxy and the call-time check cannot ship apart: the AC ties them together, and each one alone leaves an uncut path. Task 0 bounds the one unknown.

**Fallback F1 (needs a ruling only if Task 0 finds no rewrite variant):** the gate denies an allowed native MCP call with `MCPUSEPROXY`. The model then calls `call_mcp_tool` itself, and that call is classified identically. This costs one model round trip per MCP call. Nothing runs uncut or ungoverned.

**Extend, don't copy (Rule 2):**
- `ListTool`/`CallTool` extend 22.9's `Mcp.Client`, with one request method shared with `Probe`.
- The fingerprint is 22.2's `ToolFingerprint`.
- The classification is 22.8's `ClassifyMcp`.
- The cut is `Tools.Result`.
- The rewrite follows `ClampTopK`/`RagRewrite`.
- The demo refusal follows `PersonaTools`.
- The turn tool follows `documents` (Story 19.5).

**Integration ACs (Rule 1):** `call_mcp_tool` and `Mcp.Proxy` are new. Their consumers here are the real runner adapter (shadow runner), the gate and the loopback mock (ACs 1-5, `Test.Mcp.Attach`), and the overview generator (`Test.Install.SecurityOverview`).

**Consumes:**
- 22.2: rows, `ToolFingerprint`, `ResourceOf`, the mock.
- 22.8: `ClassifyMcp`, the map, `UNREGISTERED`.
- 22.9: `Mcp.Client`, the composed manager, the (server, spec) record.
- 19.5: the turn-tool precedent.
- 14: the overview generator.

**Consumed-by:**
- 22.4: a replay composes the proxy on the own manager and runs `call_mcp_tool`.
- 22.5: polls call `call_mcp_tool` and must give the poll's call a fingerprint.
- 22.6: documents the proxy, the call-time check, the audit shape and the residual, and rewrites the "MCP tools" section.
- 22.10: lists through `Mcp.Client.ListTool`.

**Ledger inbox (Rule 17):** (none).

**Footprint extensions:** `Bridge/Ext/{Classification,McpServers}.cls`, `Bridge/Adapter/StepBuffer.cls`, `Bridge/Audit.cls`, `ci/mock/test/constants.test.mjs`.

**Spine updates for the lead (Rule 20):**
- S12 (AD-21 Calling): the proxy is offered only by a request's composed manager that holds an MCP server, through `McpServersClass.ProxyToolSet()`. Before `tools/call` it re-lists the tool and refuses a changed fingerprint. `CALLSECONDS` 20. One `MCP` `called`/`refused` audit entry per run. The proxy never writes the classification row.
- S13 (AD-31): `ProxyToolSet()` (default `""`), and `ClassifyMcp`'s optional `resource`.
- S14 (AD-10 rule 2): MCP and proxy calls check `U` on the answer's `resource`. The rewrite mechanism is Task 0's measured variant, recorded with its evidence.


**Contest Planner rulings (verbatim)** [RULED 2026-11-11 ~14:35Z, Contest Planner under the owner's delegation, relayed by the orchestrator; source `<coordination>/prompts/epic-22-rulings-223.md`]:

> # Rulings, Story 22.3 (governed proxy call_mcp_tool) spec gate (Contest Planner, 2026-11-11 ~14:35Z; owner's delegation; verbatim terms)
> PUBLIC TEXT 1-10: APPROVED verbatim. Condition on 1 ("Running {tool} on {server}"): the tool name comes from an outside server, so render both slots as plain text (escaped on the web, no Telegram parse mode) and cut each to 64 characters with "…".
> VETO: ACCEPTED, with conditions:
> (a) The wallet credential read at call time never appears in a message body, Visual Trace, log or audit entry; add a test that greps the trace and logs for the test credential.
> (b) Outbound https calls verify the server certificate (VerifyPeer on); no "accept any certificate"; plain http only to this computer, as text 3 allows.
> (c) A tools/call result is untrusted content: it taints the turn (AD-10) and is cut to the request size limit before it reaches the model. Pin both.
> (d) Audit records the server, tool and outcome only, never arguments or results, as specced.
> (e) If the runner job lacks the wallet read, stop, as specced; no new grant without a ruling.
> F1: PRE-APPROVED as the fallback if Task 0 shows the gate can't reroute the call: the gate denies with MCPUSEPROXY and the model calls call_mcp_tool itself; the extra round trip is acceptable; record it in the spec.
> Spine S12-S14 (orchestrator U7): fine under these conditions.
> ACK 22.2: merge on green (the single fixed Grant/Revoke entry point with no %Admin*; DW-1038 resolved).

**How this spec applies them** (runner, 2026-11-11): texts 1-10 are approved verbatim; the implement stage uses them. Text 1's `{tool}` and `{server}` slots are rendered as plain text (escaped on the web, no Telegram parse mode) and each is cut to 64 characters with "\u2026" (Rule 14: escape in source). Conditions (a)-(e) are acceptance criteria below, each pinned by a test with a demonstrated mutation. F1 is pre-approved: if Task 0 finds no rewrite variant, the gate denies an allowed native MCP call with `MCPUSEPROXY` and the model calls `call_mcp_tool` itself (one extra round trip, accepted); Task 0's STOP on "no variant" no longer applies. The STOP on a missing wallet read (e) stands. Spine S12-S14 written.

## Veto items

1. **A new tool exposed to the model.** `call_mcp_tool` is offered only when an MCP server is attached to the request.
   - Online demo: never offered, and refused with `MCPDEMO` before any request.
2. **Outward requests.** `initialize`, `tools/list` and `tools/call` go only to admin-registered servers, bounded (2/2/20 s), with no redirect, and carry the entry's resolved credential header.
   - Online demo: none.
3. **Security posture.**
   - The `GOVERNANCE` scan admits exactly one read-only class, `OcuTalon.Mcp.Proxy`, to tool code.
   - The runner job resolves a wallet secret at call time (Task 0 (2); no new grant: if the job lacks the privilege, the implement stage stops).
   - Online demo: unchanged.
4. **Audit content.** A new `MCP` change shape, `called`/`refused` with server, tool and outcome; no arguments.
   - Online demo: never written.
5. **Extension contracts.** S13.
6. No new privilege, role, grant, resource, table, column, route, retention or web dependency.

## Public text

New, proposed, all model-facing (parameters; the implement stage uses each only after the runner records it accepted). The label is user-facing (steps).

| File / parameter | Text |
| --- | --- |
| `Gate.MCPLABEL` (step label) | "Running {tool} on {server}" |
| `McpCall.STEPLABELCALLMCPTOOL` | "Running an MCP tool" |
| `McpCall` tool description | "Runs a tool of a registered MCP server through OcuTalon's governed proxy." |
| `server` / `tool` / `arguments` descriptions | "The MCP server's name." / "The tool's name on that server." / "The tool's input, as a JSON object." |
| `McpCall.CLASSIFYRULECALLMCPTOOL` | "per call: the admin's classification of the server's tool at its current fingerprint; unclassified counts as risky" |
| `McpCall.MCPCHANGED` | "this MCP tool changed since it was classified, so nothing was run; an admin must classify it again." |
| `McpCall.MCPFAILED` | "the MCP server could not run this tool, so there is no result." |
| `McpCall.MCPTIMEOUT` | "the MCP server did not answer in time, so there is no result." |
| `McpCall.MCPDEMO` | "MCP tools are not available on the online demo, so nothing was run." |
| `Gate.MCPUSEPROXY` (F1 only) | "call this MCP tool through call_mcp_tool with its server, tool and arguments; nothing was run." |

Already given: `HELD`, `UNTRUSTED`, `FAILED`, `UNREGISTERED`, `CUTNOTE` and the privilege sentence.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Check `ci/warm.sh status` first.
- Run `OCUTALON_RUN_TAG=e22s3iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s3iw` on each class call.
- Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call, with `timeout: 600000`.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Client` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Proxy` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: passed (warm stack, production)
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.CodeRules` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Install.SecurityOverview` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Agent.Runners` -- expected: passed (TestToolInventory unchanged)
- (loop) `node --test ci/mock/test/constants.test.mjs`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite (`live:security-overview`, the shards), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- `Tools.Names` (the mock's count; `CheckToolRows`);
- the overview's generated rows and `docs/security-overview.md`;
- `GOVERNANCE` and `CALLBACKHELPERS`;
- the gate's MCP rows;
- the `Ext.McpServers` and `Ext.Classification` bases (`Test.Bridge.Ext`);
- the `MCP` audit shapes;
- the mock's request log;
- the composed manager's tool list (`TestToolsMatchRunners`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| Skip the proxy's fingerprint compare | `TestRugPullInRequest` |
| No rewrite (allow the native call) | `TestProxyRewrite` (AI Hub's client logged) |
| `Return` bypassed | `TestProxyCut` |
| Direct call classified by the static parameters | the Gate direct-call rows |
| `MissingPrivilege` ignores `resource` | the Gate no-permission row |
| Proxy demo check removed | the `Test.Mcp.Proxy` demo row |
| No audit record | `TestProxyRewrite` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
