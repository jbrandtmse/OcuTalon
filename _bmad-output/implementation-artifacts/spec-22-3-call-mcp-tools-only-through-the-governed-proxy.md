---
title: 'Story 22.3: Call MCP tools only through the governed proxy'
type: 'feature'
created: '2026-11-11'
status: 'done'
baseline_revision: '55c9a6de1893b04993e2094ff3d6245d43f9328d'
baseline_commit: '55c9a6de1893b04993e2094ff3d6245d43f9328d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-8-classify-mcp-calls-by-fingerprint-in-the-gate.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-9-bound-mcp-attach-and-listing-with-a-timeout.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-9-task0-mcp-hang.md'
warnings: ['oversized']
deferred:
  - summary: >-
      An approved native MCP call that Replay.Run executes is not rewritten into the proxy, so it runs through AI Hub's client with no deadline, no cut, no call-time fingerprint check and no audit entry.
    evidence: |-
      Gate.Decision reroutes only when the context is not a replay (IsMcp(source) && 'replay), and the spec's Never list assigns the MCP replay to Story 22.4. Reported by the edge-case and verification-gap layers; Test.Bridge.Gate TestMcpRewriteAndItsMark pins the non-rewrite. Routed to 22.4 (replay composes the proxy on the own manager and runs call_mcp_tool).
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:Decision (reroute guard)
    severity: medium
  - summary: >-
      The bounded client has no total deadline per request: %Net.HttpRequest Timeout applies per read, so a server that sends bytes slowly can hold the runner job longer than CALLSECONDS.
    evidence: |-
      Exchange sets OpenTimeout/Timeout only; a blocked read cannot be interrupted from ObjectScript and no total clock can be enforced without a lower-level socket loop. The same property holds for 22.9's Probe and AD-21 accepts the residual for this release. A server that trickles one byte per second is the case to measure.
    location: >-
      src/ocutalon/cls/OcuTalon/Mcp/Client.cls:Exchange
    severity: medium
  - summary: >-
      The rewrite mark ^||OcuTalonBP.McpRewrite is a single slot: if AI Hub ran the first policy pass of two native MCP calls before either second pass, the first call's second pass would be treated as a new call (duplicate step, spurious UNTRUSTED for a safe non-read-only tool).
    evidence: |-
      Unverified (maybe-false): ExecuteTool runs the first pass, the tool and the second pass inside one call in one process, so the order is sequential by construction, but the Task 0 evidence measured one call only. What would settle it: a shadow-runner test that executes two native MCP calls back to back in one turn and asserts one step each, or a per-call-id keyed mark.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:Reroute, McpRewrittenBefore
    severity: medium (unverified)
  - summary: >-
      The wallet read at call time was measured in a session with the runner job's roles (_Ensemble, %All), not inside a runner job, so condition (e) rests on an inference.
    evidence: |-
      Evidence 22-3-task0-proxy.md section 2 labels the in-job result (inference). What would settle it: a live check that a Mcp.Proxy call made from a runner job (a real chat turn against the mock with a wallet-backed entry) returns the tool text rather than a credential refusal; the lead's fresh-environment and live checks cover it.
    location: >-
      src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls:Header
    severity: medium (unverified)
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
- [x] **Task 0** (implement stage, lane A's warm throwaway; scratch classes `ZzT3`, removed afterwards). Record each answer in `_bmad-output/implementation-artifacts/evidence/22-3-task0-proxy.md`:
  1. With the shadow runner and the mock, the gate's first pass on a native `zz_lookup` call sets `call.%Set("name","call_mcp_tool")` and `call.%Set("arguments",{server,tool,arguments})`, a second variant also sets `toolref`, and the composed manager holds the proxy toolset. For each variant, record:
     - what runs (the proxy's method, or AI Hub's `tools/call`, by the mock's `client` field);
     - whether the policy runs a second time, and what `toolref`, `call` and `metadata` it then gets;
     - what the model's tool result carries.
  2. Whether the runner job (the service user) can resolve the entry's `secret://` reference from the wallet, and through which API. If it cannot, record the measured error and STOP with an intent gap: no grant is added here.
  3. The rule: if a variant makes the proxy run in place of AI Hub's call, implement the rewrite with it. If none does, STOP with an intent gap naming fallback F1 (Design Notes), unless the runner has recorded F1 as accepted. In that case implement F1 with the `MCPUSEPROXY` sentence.
- [x] `src/ocutalon/cls/OcuTalon/Mcp/Client.cls` -- extend 22.9's client:
  - `Parameter CALLSECONDS = 20`.
  - `ListTool(url, header, tool, .definition) As %String` sends `initialize` and `tools/list`, follows `nextCursor` up to 10 pages, and finds the tool by name.
  - `CallTool(url, header, tool, arguments, .result) As %String` sends `tools/call`.
  - Both share one private request method with `Probe`: `OpenTimeout`/`Timeout`, `FollowRedirect` 0, `OcuTalonClient` for `https`, and `Mcp-Session-Id` kept from `initialize`.
  - Each accepts a JSON body or a single-event `text/event-stream` body. Each answers `""` or a reason word (`unreachable`, `timeout`, `failed`, `notfound`). Neither throws, logs or returns a URL or header.
- [x] `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls` (new, read-only) -- `Call(server, tool, arguments) As %DynamicObject`, in this order:
  1. demo refusal;
  2. `Server.NAMEPATTERN`, the row and the `ToolClassification` row, which must not be `unclassified`;
  3. the entry through `ConfigStore.Details`; the `url` through `Ops.AddressAllowed`;
  4. the header resolved per Task 0;
  5. `ListTool`; `ToolFingerprint(description, inputSchema)` must equal the row's `Fingerprint`, otherwise refuse with `MCPCHANGED`;
  6. `CallTool`;
  7. join the `content` text parts (other part types become `[non-text content omitted]`);
  8. one `Bridge.Audit.Record("MCP", …)`.

  It answers `{text}` or `{refusal}`. It writes no row and never calls `ClearChanged`: the next turn's map clears the row (22.8).
- [x] `src/ocutalon/cls/OcuTalon/Tools/McpProxy.cls` (new `%AI.ToolSet`) and `Tools/McpCall.cls` (new, extends `Tools.Result`):
  - `CallMcpTool(server, tool, arguments As %DynamicObject)` returns `..Return(text)` or the refusal sentence. Its schema descriptions are under Public text.
  - Parameters: `STEPLABELCALLMCPTOOL` (the fallback label), `CLASSIFICATIONCALLMCPTOOL` "risky", `READONLYCALLMCPTOOL` 0 and `TRUSTEDOUTPUTCALLMCPTOOL` 0. These are the static fallbacks, because the gate classifies the proxy per call. Also `CLASSIFYRULECALLMCPTOOL` for the overview's "per call:" row.
- [x] `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- `Parameter CALLMCPTOOL = "call_mcp_tool";`. The comment says it is not a release-1 tool.
- [x] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ProxyToolSet() As %String`, default `""`. The bridge alone has no proxy and lists no server. `Mcp/Attach.cls` overrides it with `OcuTalon.Tools.McpProxy`.
- [x] `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `ClassifyMcp`'s answer gains an optional `resource` (default absent). `Mcp/Classification.cls` sets it to `Install.Step.Mcp.ResourceOf(server)`.
- [x] `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- node `mcp` also keeps server name to toolref, from the adapter's recorded (server, spec) pairs. Add `McpToolref(server) As %String`.
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- after the first MCP server is added to a request's manager, `RegisterToolSet(ProxyToolSet())`. On error: one warning, the MCP tools are removed from that request's offer, and the request goes on. Pass the (server, spec) pairs to the map. Update the class doc.
- [x] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `MCPPROXY` = "call_mcp_tool".
  - A direct proxy call (name `MCPPROXY`, not `mcp:`) is classified as `ClassifyMcp(McpToolref(server), tool, McpFingerprint(toolref, tool))`. No toolref counts as unclassified.
  - `MissingPrivilege` checks `U` on the answer's `resource` for MCP and proxy calls. No resource from the host means no check (bridge alone).
  - After an allow (Task 0's variant), rewrite a native MCP call to the proxy. Mark the rewrite like `RagRewrite`, so the second pass reports no second step and re-taints nothing new.
  - Restate the doc ("two rewrites").
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` gives the `MCPLABEL` text for an `mcp:` call and for a proxy call whose server matches `[A-Za-z0-9_]{1,40}` and whose tool is in the map. Otherwise it gives the proxy's fallback label. Never the arguments.
- [x] `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- `MCPCHANGES` gains `called` and `refused`, with a call shape `change,server,tool,outcome`. `outcome` is a fixed word: `ok`, `cut`, or a refusal or reason word.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `GOVERNANCE` lets a tool name exactly `OcuTalon.Mcp.Proxy` (a negative lookahead after `ocutalon[._]mcp`). Add `Mcp.Proxy`, `Mcp.Client`, `Install.Step.Mcp` (only `ResourceOf`) and `Bridge.ConfigStore` to `CALLBACKHELPERS`. A new test shows that `Mcp.Proxy` names no `%Save`, `Ops.` writer, `ClearChanged`, `SettingsOps` or `Approval`.
- [x] `ci/mock/scenarios/A/mcp-proxy-call.json` (new; mockkey `chat` is not used, marker `mcp-proxy-call`) and `ci/mock/test/constants.test.mjs` -- a script whose `toolUse` is `call_mcp_tool`, and a "the mock reads call_mcp_tool" test. The Names count rises by one.
- [x] The overview and its pins:
  - `Test/Install/SecurityOverview.cls` -- `CheckToolRows` adds `CALLMCPTOOL`. `TestToolsMatchRunners` treats it like `documents`: offered only by a composed request with an MCP server, so it appears in no own-manager inventory.
  - `docs/security-overview.md` -- regenerate only the generated tools section, through `Regenerate`.
- [x] Tests:
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

- 2026-11-12 (implement stage, measured platform fact; for the lead's post-hoc review as a Rule 5 apply-and-report amendment): the I/O matrix row "Rewrite" and the first AC say the mock logs "none from AI Hub's client". AI Hub's client sends its own `tools/list` before every tool call (22.9 evidence) and the rewrite cannot avoid it, so the observable that holds, and is pinned, is: from AI Hub's client only that `tools/list` and no `tools/call`; from client `iris` one `initialize`, the notification, one `tools/list` and one `tools/call`. The intent block is unchanged; the safety property (no call through AI Hub's client) is intact. Proposed wording for the row and the AC: "the mock logs no `tools/call` from AI Hub's client".

- 2026-11-12 (runner, lane change): Epic 22 moved to lane D (slot `ocutalon-slot-d`, lock folder `lane-d`, port 52804) by the Contest Planner's ruling; the Verification lane variables now name lane D. Nothing else changed.

- 2026-11-11 (runner, rulings applied): the Contest Planner's 22.3 rulings (verbatim under Design Notes) are applied: texts 1-10 approved (text 1 slots plain and cut to 64 characters), veto accepted with conditions (a)-(e) added as ACs, F1 pre-approved, spine S12-S14 written.

- 2026-11-11 (runner, spec gate): validated (no split). The Veto items, the Public text table (10 proposed strings, incl. F1's), fallback F1 and spine updates S12-S14 go to the Contest Planner (via the orchestrator) before the implement stage; this story implements only after Stories 22.8 and 22.9 are committed.

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 40 findings - high 0, medium 6, low 27, false 4, maybe-false 3
- findings:
  - Blind Hunter:
    - `[false]` `[reject]` a refused tool or an unavailable server can still be run by a direct proxy call - a refused tool's row has an empty fingerprint, so the fingerprint compare refuses it; an unavailable server is listed fresh and compared like any other.
    - `[low]` `[reject]` the audit says refused when tools/call was sent and timed out or errored - spec-bound: the matrix row gives `refused` with a reason word and the model sentence "no result"; reopen_if a risky tool is seen to act after a timeout.
    - `[medium]` `[defer]` no overall deadline across reads - deferred (Client Exchange; per-read timeouts only, residual accepted by AD-21 for this release).
    - `[maybe-false]` `[defer]` single-slot rewrite mark with parallel calls - deferred as unverified (needs a two-call measurement).
    - `[low]` `[patch]` a rewritten call denied after the rewrite was recorded keeps its rename, note and mark - patched: Gate.Decision now reroutes after the taint Put, last.
    - `[low]` `[patch]` the manager composed again after a failed proxy registration leaves the servers reported attached - patched: OfferServers stops at once when OfferProxy gives 0, before any report.
    - `[false]` `[reject]` IsProxyCall trusts only the tool name - only the proxy toolset carries that name for a non-MCP source, and a server's tool of that name has an MCP source (shadowed by the proxy).
    - `[low]` `[patch]` BodyOf truncates a long string body instead of failing - patched: a string longer than MAXBODY gives "".
    - `[low]` `[reject]` no session DELETE or protocol-version header; notfound beyond page 10 reads as changed - no user-reachable failure; notfound meaning "no longer listed" is the specced reading (wontfix-accepted; reopen_if a server refuses requests for the missing header).
    - `[low]` `[patch]` doc comments misplaced in Test.Mcp.Attach (UseTurn) and Test.Bridge.Gate (BuiltInToolsets) - patched.
    - `[low]` `[reject]` administration docs do not mention the new permission, audit entry and demo behaviour - 22.6 writes the MCP documentation (spec Never list).
  - Edge Case Hunter:
    - `[medium]` `[defer]` no total deadline, unbounded drip - same root cause as the Blind Hunter's, one deferred entry.
    - `[false]` `[reject]` StepBuffer tests the class with the mcp: prefix, not IsMcp - the adapter adds every MCP tool by an `mcp:remote:` spec (OfferServers AddTool(spec)), so the step class always starts with it; LabelFor already used the prefix before this story.
    - `[low]` `[patch]` servers reported attached on a discarded manager - same root cause as the Blind Hunter's, patched once.
    - `[medium]` `[defer]` replay of an approved native MCP call is not rewritten - deferred, routed to 22.4 (spec Never list).
    - `[low]` `[reject]` stale mark with an empty call id or a failed Put - the mark includes the call id and the arguments hash and the id is unique per call; wontfix-theoretical.
    - `[low]` `[reject]` a non-string `resource` skips the permission check - the host's class is OcuTalon's own and always answers a string; wontfix-theoretical.
    - `[low]` `[patch]` over-long string body truncated - same root cause as the Blind Hunter's BodyOf finding.
    - `[low]` `[reject]` an exception after tools/call was sent is audited as failed - needs an exception inside TextOf; wontfix-theoretical.
    - `[low]` `[reject]` a read-only to risky edit between the gate and the call still runs - the window is the milliseconds between the two reads of the same row, and the proxy refuses an unclassified or changed row; wontfix-accepted, reopen_if a test shows a longer window.
    - `[low]` `[reject]` audit says refused for runs that never reached the server (changed row, address, credential) - spec-bound: Design Note 6 audits every run that passed the registered-tool check.
    - `[medium]` `[defer]` approved MCP replays bypass the proxy - same root cause as the replay finding above.
  - Verification Gap:
    - `[medium]` `[patch]` the "text ends with the note" assertion in TestProxyCut cannot fail - patched: an anchored match of the note at the end of the text.
    - `[low]` `[patch]` the audit outcome cut is not checked through the tool - patched: TestProxyCut waits for the entry and asserts called|zz_lookup|cut; mutation recorded.
    - `[low]` `[patch]` the no-auth credential path is untested - AI Hub's MCPDescriptor requires `auth` for a remote entry, so no such entry can exist; patched by removing the dead branch of Proxy.Header (an entry with no auth is now refused as a credential failure) and its comment.
    - `[medium]` `[defer]` replay not rewritten, nothing verifies what runs - same root cause as the replay finding.
    - `[maybe-false]` `[defer]` single slot, only single calls tested - same root cause as the Blind Hunter's.
    - `[low]` `[reject]` the mock scenario is checked only as source text - the spec asks for exactly that pin (constants test); a consumer arrives with a later story.
    - `[low]` `[reject]` label escaping on the web page and no Telegram parse mode are not pinned in this diff - Test.Channel.TelegramOut pins that no parse_mode is sent, and the web page renders the label through React, which escapes; reopen_if a card renders HTML.
    - `[low]` `[patch]` no mutation line for the URL-in-log leak and the control-character translation - patched: both mutations applied, red in TestNothingLeaks and TestMcpStepLabel, reverted; lines written.
    - `[maybe-false]` `[defer]` AC (e) rests on an inference for the runner job - deferred as unverified (evidence section 2).
    - `[low]` `[reject]` no mutation line for the UNTRUSTED denial of a risky tool in an untrusted turn - that branch of Gate.Decision is Story 22.8's code with its own rows; TestDirectCall and TestProxyRewrite also assert it.
    - `[low]` `[reject]` TestHttpsVerifiesTheServer reads the installer's SSL configuration - it asserts the configuration exists and fails loudly if absent; the installer runs in every environment the tests run in.
    - `[false]` `[reject]` TestDemo changes onlineDemo - OnAfterOneTest restores the saved value.
    - `[low]` `[reject]` TestDemo's "no audit entry" has no positive control - TestCalled and TestRefusals assert the entry exists for the same wait.
    - `[low]` `[patch]` Places returns "" when the log mark is empty, so the leak assertions would pass vacuously - patched: it returns a failing text.
    - `[low]` `[reject]` the overview shows Resources none for call_mcp_tool while the gate checks U per server - the resource is per call and 22.6 rewrites the MCP documentation; wontfix-accepted, reopen_if the overview is read as a permission list.
    - `[low]` `[patch]` the Test.Mcp.Client comments claim cases TestListToolBody does not cover - patched: comments say HTTP error status and empty body.
    - `[low]` `[patch]` Test.Mcp.Classification and Test.Bridge.Audit are not in the Verification loop - both ran green after the patches; both lines added to the loop.
    - `[low]` `[reject]` the AC text says "only client iris" while the tests allow AI Hub's tools/list - a measured platform fact (22.9 evidence); recorded in the Spec Change Log for the lead; the safety property holds.
  - Intent Alignment Auditor: 0 findings (descriptive report: the diff implements the rewrite-inside-the-callback reading, tested at the tool-manager level through the shadow runner and at unit level; divergences B (tools/list), C, D, E, F are the rows above).

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

**Implementation notes (implement stage, 2026-11-12):** each decision is small, reversible inside this story and breaks no AD or owner-fixed value.
1. **Task 0 result (evidence `22-3-task0-proxy.md`).** Setting the call's `name` and `arguments` makes the proxy run in place of AI Hub's `tools/call`. AI Hub then runs the policy a second time on the changed call (toolref `call_mcp_tool`, no `tool_ref` member, the proxy tool's metadata). A `toolref` or `tool_ref` member set on the call changes nothing. So the rewrite uses variant B, F1 is not used, and `MCPUSEPROXY` is not shipped (a native call whose server the map cannot name is denied `FAILED`, with one warning, before anything is reported). AI Hub still sends its own `tools/list` before every tool call (22.9's evidence), so "none from AI Hub's client" means no `tools/call`: the tests count `tools/call` from a client other than `iris`.
2. **Wallet.** The runner jobs run as `_Ensemble` with `%All` (measured); `GetDetails(entry, .details, 0, 1)` (the call of `%AI.Utils.ConfigStore.Lookup`) resolves the `secret://` header in a process with `%All` (the job itself was not driven, so the same result in the job is an (inference)). No grant is added. `Mcp.Proxy.Header` supports the three auth types that `MCPDescriptor` accepts: `header`, `bearer` (`Authorization: Bearer`) and `basic` (`Authorization: Basic`); the resolved value lives only in the local variable that is passed to `Client`.
3. **AI Hub's audit policy sees the model's call, not the rewritten one.** `StepAudit` gets the original name and arguments and the metadata of the proxy tool that ran (measured). So the single step record of a rewritten call has the tool's own name and the proxy's class. `Context.NoteRerouted`/`ReroutedServer` (the gate notes each rewrite by tool name, in order) let `StepBuffer.Records` label it `Running {tool} on {server}`; `StepBuffer.InputsOf` shows only `{"server","tool"}` as the inputs of an MCP call and of a proxy call, never the argument values (the AC on step records). No Lane A class outside the spec's list is edited for this.
4. **The map names the recorded servers.** `Context.SetMcpTools(catalog, servers)` takes the adapter's recorded (server, spec) pairs; a proxy call for a server that is not recorded is asked as the empty toolref, so OcuTalon's class answers `UNREGISTERED` (also for a registered server that was not attached in this job), and the bridge alone answers unclassified.
5. **Resource.** `ClassifyMcp`'s `resource` is on every answer for a registered server (also an unclassified one), so a missing `U` is denied with the privilege sentence before any hold or `UNTRUSTED`. The test fixtures grant the permission through `Install.Step.Mcp.Grant`.
6. **Second run of the policy.** The mark is the item, the call's id and the canonical hash of the new arguments (AI Hub hands the arguments back with sorted keys). The marked run reports no step, consumes the mark and is not denied by the taint that the first run set (the replay's exemption); it still checks the classification, the permission and the provenance.
7. **Offer.** `OfferServers` registers `ProxyToolSet()` right after the first server was added (`OfferProxy`); when that fails it warns once and `BuildTurnManager` composes the manager again without any MCP server, because AI Hub has no way to remove a tool from a manager. `Mcp.Attach.ProxyToolSet` answers `""` on the online demo.
8. **Client.** `ListTool` also sends `notifications/initialized` (a Python MCP server refuses requests before it; 22.9's evidence shows that AI Hub sends it too) and takes/gives the session through an optional `session` argument (`ListTool` ByRef, `CallTool` last argument), so the proxy sends one `initialize` per run. `header` is `""` or `{"name","value"}`. The connection and an https handshake are bounded by `PROBESECONDS` also for `CallTool` (measured: a refused port took more than 3 s with an `OpenTimeout` of 20); only the wait for the answer uses `CALLSECONDS`. A body is read up to `MAXBODY` (1,000,000) characters. The worst case of a run is `initialize` 2 s + notification 2 s + `tools/list` 2 s per page + `tools/call` 20 s.
9. **Tool.** `arguments` is optional (a tool with no input); the toolset has no `<Description>` (the tool's own description is the approved text); `CLASSIFYRULECALLMCPTOOL` omits the leading "per call: " because the overview prints it; the hook `ClassifyCALLMCPTOOL` is `[ Internal ]` and answers through `..Return` (the scan allows no other `Quit`), and the gate never calls it. The audit `outcome` words are `ok`, `cut`, `changed`, `notfound`, `timeout`, `unreachable`, `failed`, `address`, `credential`; the `demo` refusal writes no entry.
10. **Audit.** `Audit.Shape(type, change)`: an `MCP` entry with change `called` or `refused` has the members of `SHAPEMCPCALL`; `added` and `removed` keep `SHAPEMCP`. `outcome` must be one lower-case word of at most 24 letters. A run is audited once it names a registered server and a tool (step 2 of `Proxy.Call`).
11. **Tests.** The Mock gained `Call`, `Pages`, `Session` and a `session` log field; `ZzTurnAdapter.CallValue` returns the model-facing result. `Test.Bridge.Gate` puts `McpServersClass` to the base class for the 22.8 rows of the bridge alone (the production's host rewrites an allowed native call) and to `ZzGateServers` for the rewrite rows. `Test.Mcp.Attach.Register` grants the permission. `GOVERNANCE` allows exactly `OcuTalon.Mcp.Proxy` (`(?![._]proxy(?![\w.]))`).
12. **Label rendering.** The label is plain text with markup kept as typed and control characters as spaces; the web page escapes it (React) and `Channel` and `Live` set no Telegram parse mode (searched). Those lanes are not edited here.
13. **Release sequence.** `docker/tests/test-release-sequence.sh` is not changed (22.6 rewrites that section), as the spec says.

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

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
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
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Audit` and `ci/iris.sh class OcuTalon.Test.Mcp.Classification` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Install.SecurityOverview` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Agent.Runners` -- expected: passed (TestToolInventory unchanged)
- (loop) `node --test ci/mock/test/constants.test.mjs`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite (`live:security-overview`, the shards), and the lead runs Rule 19's fresh-environment check.

**Mutation lines (Rule 19; each applied to the file, observed red in the named test on the warm throwaway of lane D, 2026-11-12, and reverted byte for byte):**
- `mutation:` skip the proxy's fingerprint compare (`Proxy.Run`) -> `Test.Mcp.Attach:TestRugPullInRequest` (both cases) and `Test.Mcp.Proxy:TestChangedBeforeTheCall` red.
- `mutation:` no rewrite (drop the `Reroute` call in `Gate.Decision`) -> `TestProxyRewrite` (AI Hub's client logged the `tools/call`) and `Test.Bridge.Gate:TestMcpRewriteAndItsMark` red.
- `mutation:` `Return` bypassed (`McpCall` quits the text) -> `TestProxyCut` red.
- `mutation:` the direct call classified by the static parameters (drop the `FromProxy` line of `ClassificationOf`) -> `Test.Bridge.Gate:TestProxyDirectIsClassifiedAsTheNativeCall` red.
- `mutation:` `MissingPrivilege` ignores the answer's `resource` -> `Test.Bridge.Gate:TestMcpResourcePermission` and `TestDirectCall` red.
- `mutation:` the proxy's demo check removed -> `Test.Mcp.Proxy:TestDemo` red; `Mcp.Attach.ProxyToolSet` offered on the demo -> `TestDemo` red.
- `mutation:` no audit record (`Proxy.Call`) -> `TestProxyRewrite` and `Test.Mcp.Proxy:TestCalled` red.
- `mutation:` the label slot not cut to 64 characters -> `Test.Bridge.Gate:TestMcpStepLabel` red.
- `mutation:` an allowed MCP call does not taint the turn -> `TestProxyRewrite` and `TestMcpRewriteAndItsMark` red.
- `mutation:` the resolved credential written to a log line (`Proxy.Run`) -> `Test.Mcp.Proxy:TestCalled` red (its `OnAfterOneTest` scan of the event log).
- `mutation:` the audit shape of a call gains `arguments` -> `Test.Bridge.Audit:TestMcpCallShape` and `Test.Mcp.Proxy:TestCalled` red.
- `mutation:` a step record shows the arguments of a direct proxy call (`InputsOf`), and, separately, of a rewritten native call -> `TestDirectCall` and `TestProxyRewrite` red; the rewrite not noted (`NoteRerouted`) -> `TestProxyRewrite` red.
- `mutation:` https without the installer's SSL configuration (`Client.Open`) -> `Test.Mcp.Client:TestHttpsVerifiesTheServer` red; the address check removed from `Proxy.Run` -> `Test.Mcp.Proxy:TestRefusals` red.
- `mutation:` the marked second run reports a second step (`ElseIf marked` off) -> `TestMcpRewriteAndItsMark` red.
- `mutation:` the proxy offered before a server was added -> `Test.Mcp.Attach:TestRequestServerDown` red; the manager not composed again when the proxy toolset cannot be registered -> `TestProxyToolSetFails` red.
- `mutation:` a result with `isError` returned as a result -> `Test.Mcp.Client:TestCallTool` and `Test.Mcp.Proxy:TestServerFailures` red; a silent server reported unreachable and not timeout -> `TestCallToolSilent` red; the session not kept -> `TestSession` red; an event stream read as JSON -> `TestListToolBody` red; only the first page read -> `TestListToolPages` red.
- `mutation:` a native call whose server the map cannot name rewritten with an empty server (drop the throw in `ProxyArguments`) -> `TestMcpRewriteAndItsMark` red.
- `mutation:` the governance scan with no exception for the proxy -> `Test.Bridge.CodeRules:TestNoToolReachesAGovernanceCommand` red; with an exception for any class that starts with `OcuTalon.Mcp.Proxy` -> `TestToolCodeScan` red; the proxy clearing a classification -> `TestProxyWritesNothing` red.
- `mutation:` `CALLMCPTOOL` missing from the pinned tool list of `CheckToolRows` -> `Test.Install.SecurityOverview:TestToolRows` red; the scenario `mcp-proxy-call` absent -> `node --test ci/mock/test/constants.test.mjs` red (the "mock reads call_mcp_tool" test), green with it.

- `mutation:` the audit outcome `cut` not computed (`McpCall` passes no room to `Proxy.Call`) -> `Test.Mcp.Attach:TestProxyCut` red ("the audit entry of the cut call says cut"); the note-at-the-end assertion is an anchored match.
- `mutation:` the resolved address written to a log line (`Proxy.Run`) -> `Test.Mcp.Proxy:TestNothingLeaks` red; control characters of a label slot not translated (`StepBuffer.Slot`) -> `Test.Bridge.Gate:TestMcpStepLabel` red.

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

Status: done
Blocking condition: none

**Summary.** Native MCP calls the gate allows now run only through `call_mcp_tool`, OcuTalon's governed proxy: the gate rewrites the call's name and arguments (Task 0 variant: setting `name` and `arguments`; no `toolref` needed; F1 and `MCPUSEPROXY` not used). The proxy lists the tool again just before `tools/call`, refuses a changed fingerprint unrun, resolves the wallet credential in memory, cuts the result through `Tools.Result`, taints the turn and writes one `MCP` `called`/`refused` audit entry (server, tool, outcome). A direct proxy call is classified like the native call; the gate checks `U` on the server's resource. The proxy is offered only by a request's composed manager that holds a server, never on the online demo (`MCPDEMO`, before any request).

**Files changed.**
- Bridge: `Policy/Gate.cls` (proxy constant, direct-call classification, resource check, marked rewrite, label), `Context.cls` (server map, reroute notes), `Adapter/Agent.cls` (offers the proxy after the first server), `Adapter/StepBuffer.cls` (label, inputs without argument values), `Ext/{Classification,McpServers}.cls`, `Audit.cls` (call shape).
- OcuTalon: `Mcp/Client.cls` (`ListTool`, `CallTool`, `CALLSECONDS`), new `Mcp/Proxy.cls`, `Mcp/{Attach,Classification}.cls` (overrides), new `Tools/McpCall.cls` and `Tools/McpProxy.cls`, `Tools/Names.cls`.
- Mock and docs: `ci/mock/scenarios/A/mcp-proxy-call.json`, `ci/mock/test/constants.test.mjs`, the generated tools section of `docs/security-overview.md`.
- Tests: new `Test/Mcp/Proxy.cls` with fixtures `Test/Mcp/{ZzProxy,ZzBrokenProxy}.cls` and `Test/Bridge/ZzGateServers.cls`; extended `Test/Mcp/{Client,Attach,Classification,Mock}.cls`, `Test/Bridge/{Gate,Audit,Ext,CodeRules,ZzGateClassification,ZzTurnAdapter}.cls`, `Test/Install/SecurityOverview.cls`.
- Evidence: `_bmad-output/implementation-artifacts/evidence/22-3-task0-proxy.md`.

**Review findings.** 40 findings: patches applied 10 rows (one medium: an assertion in `TestProxyCut` that could not fail; the rest low: the gate now reroutes after the taint, `OfferServers` stops at once when the proxy cannot be registered, a long string body is refused, the dead no-auth branch of `Proxy.Header` is removed, the cut audit outcome is pinned, two mutation lines, a non-vacuous leak guard, comment fixes, two classes added to the loop); 4 items deferred (replay not rewritten - routed to 22.4; no total read deadline; single-slot rewrite mark with parallel calls, unverified; wallet read inside a runner job, unverified); the rest rejected with reasons in the triage log above (4 false, the others low and spec-bound, theoretical or owned by 22.6).

**Follow-up review recommended:** false (no high patched; one medium patched).

**Verification performed (lane D warm stack, tag e22s3vw, torn down).** Passed: `Test.Mcp.Client`, `Test.Mcp.Proxy`, `Test.Mcp.Attach`, `Test.Bridge.Gate`, `Test.Bridge.CodeRules`, `Test.Bridge.Ext`, `Test.Bridge.Audit`, `Test.Mcp.Classification`, `Test.Install.SecurityOverview`, `Test.Agent.Runners`; `node --test ci/mock/test/constants.test.mjs` (9 pass); `test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh` exit 0. Review-pass mutations (cut audit outcome, address in a log line, label control characters) went red in the named tests and were reverted byte for byte. Not run here: `docker/tests/test-security-overview.sh` and the full CI suite (CI HOLD; the lead runs the fresh-environment check).

**Residual risks.**
- The deferred items above; the wallet read in a runner job is an inference (condition (e) was stopped on only if the read failed; it did not in a `%All` session).
- AI Hub still sends its own `tools/list` before each tool call; the matrix/AC wording "none from AI Hub's client" is recorded in the Spec Change Log for the lead's amendment.
- The step record of a rewritten call is labelled through a per-tool-name note list (`Context.NoteRerouted`), because AI Hub's audit policy sees the model's original name.
- The Telegram plain-text rule is pinned by the existing `Test.Channel.TelegramOut`; the web escape relies on React.
