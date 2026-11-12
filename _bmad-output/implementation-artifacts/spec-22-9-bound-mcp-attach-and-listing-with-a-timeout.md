---
title: 'Story 22.9: Bound MCP attach and listing with a timeout'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-9-task0-mcp-hang.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-2-classify-mcp-tools-by-server-and-name.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-8-classify-mcp-calls-by-fingerprint-in-the-gate.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** AI Hub's MCP client has no deadline. Task 0 (evidence `22-9-task0-mcp-hang.md`) measured a server that accepts the connection and never answers: `AddTool` blocked for 632 s, `%Discover()` for 551 s, and `ExecuteTool` of a *built-in* tool for 300 s, on a manager that held such a server. Each call stayed blocked until the server closed the connection, and `Terminate` cannot end a job while it is inside the native call. Today the runner's build adds every server to the agent's own manager, which every replay and `ToolInventory` request lists. Each request also adds every server again, with no deadline.

**Approach:**
- Before every `AddTool`, at the build and in each request, the runner asks a new `McpServers` extension method, `Probe(server, config)`. OcuTalon answers it with a bounded ObjectScript JSON-RPC `initialize` (2 s).
- A server that does not answer is not added. It is reported `unavailable` through Story 35.1's attach report, and Story 22.2's `RecordAttach` then sends `mcp.serverUnavailable`. The runner then skips that server for 60 s.
- The agent's own manager never holds an MCP server. The build attaches the servers to a manager used only for the report, so only a request's own probed manager lists them.

## Boundaries & Constraints

**Always:**
- Lane A files only (U-177): `Bridge/Adapter/Agent.cls`, `Bridge/Ext/McpServers.cls` (footprint extension), `Mcp/Attach.cls`, the new `Mcp/Client.cls`, `Test/Mcp/{Attach,Mock,ZzServers}.cls`, the new `Test/Mcp/Client.cls`, and `Test/Bridge/{ZzTurnAdapter,Ext}.cls`.
- The probe:
  - sends no credential and makes no `%AI` or Python call;
  - runs outside every callback (AD-6);
  - is bounded by `OpenTimeout` 2 s and `Timeout` 2 s, and follows no redirect;
  - counts any HTTP status within the bound as an answer.
- Fail closed: a probe that says no, throws or cannot run means no `AddTool` for that server in that build or request.
- No URL, secret or AI Hub error text goes into a log line, report or test message (35.1's rule). Reports carry only the code words `unreachable` or `failed`.
- Per request, the runner reports a server only on a transition that this runner job sees: unavailable after its last report said attached, or attached again after its last report said unavailable.
- With no server registered (the demo path and the online demo), nothing runs: no probe, no report and no extra cost.

**Never:**
- Edit `Core.SettingsOps`, `Core.CommandsIn`, `Web.*`, `web/**` or a Lane B test.
- Write a Config Store entry or a wallet secret.
- Add a route, table, column, resource, grant, production setting or Config Store key.
- Use a real MCP server.
- Run an AI Hub call in a child job, or `Terminate` a runner job (evidence (3) and (5)).
- Change 22.2's `RecordAttach` or its notices, or 22.8's map or gate.
- Build `call_mcp_tool` (22.3) or the MCP replay (22.4).
- Delete, skip, tag off or shorten a test, or make an existing test slower: the mock's silent mode is off by default.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Build, answers | registered server answers `initialize` | probe `""`, `AddTool` on the build's report manager, report `attached` (tools, refused, 22.2's fingerprints), spec recorded; the agent's own manager lists none of its tools | none |
| Build, silent | accepts, never answers | probe gives up in about 2 s (at most about 4 s); no `AddTool`, spec not recorded; report `unavailable`/`unreachable`; `BuildAgent` OK | one warning naming the server |
| Build, down or no entry | refused port / entry missing / URL not `http(s)://` / `Probe` throws | `unreachable` at once / `failed` / `failed` / `failed`; as above | as above |
| Request, answers | spec recorded, probe `""` | `AddTool` on the request's manager, its tools offered (as today) | none |
| Request, silent | server stopped answering after the build | the request goes on without its tools in about 2 s; one `unavailable`/`unreachable` report from this job; the server rests `RESTSECONDS` (60): later requests skip it with no probe and no report | one warning per failure |
| Request, back | first request after the rest, server answers | tools offered again; if this job last reported `unavailable`, it reports `attached` (same builder as the build) | `AddTool` error: as silent, reason from `ReasonOf` |
| Replay or inventory | a `tool` request or `ToolInventory` while a server is silent | runs on the agent's own manager, which holds no MCP server: it returns at once and the server gets no request | none |
| Skills agent | the agent declares skills, a spec is recorded | its requests keep the own manager, so no MCP tool is offered | one warning per build |
| None registered | `Servers` gives `[]` | nothing: no probe, report or warning | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - Class doc L23-31 (the "AI Hub's listing … throws" sentence is restated) and `Attached` L123.
  - `BuildAgent` L239, which resets `Attached` (reset the new transient state here too).
  - `OnAfterAgentInit` L265.
  - `AttachServers` L282: the class from `ClassFor`, `builtin` from `ToolNames`.
  - `AttachOne` L313: the report loop L328-338 is extracted into the shared builder.
  - `ReasonOf` L348, `ToolNames` L356, `ReportAttach` L371.
  - `Attach` L385 is the own-manager path and stays for non-MCP specs only.
  - `BuildTurnManager` L482: the skills branch L495, and the MCP loop L521-527 with its warning L525.
  - `Inventory` L1302.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls` L98 (read only) -- a replay runs `adapter.Agent.ToolManager.ExecuteTool`, the own manager; this is why that manager must hold no MCP server.
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `Servers` L21, `OnAttach` L28, `REASONS` L17 (unchanged).
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls` -- `Details(entry, .details)` L114 reads an entry with no secret resolved; `FullName` takes `AI.MCP.<name>`.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` -- `ENTRYPREFIX`, `Servers`, `OnAttach`; header L1-6.
- `src/ocutalon/cls/OcuTalon/Install/Step/SSL.cls` L12 -- `#NAME` `OcuTalonClient`, the one client SSL configuration for outbound HTTPS.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Api.cls` L53-63 (Lane B, read only) -- the `%Net.HttpRequest` pattern: `FollowRedirect` 0, `Https`, `SSLConfiguration`, `Timeout`.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`:
  - `Serve` L127, `Connection` L155 (headers L161-170, log L178), `Requests` L74, `Stop`/`Forget`/`End`.
  - `OPENWAIT`/`STOPWAIT` L29-32.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`:
  - Tests: TestAttach L104 (L113 own-manager names, L120-130 header check), TestTurnManager L142, TestUnavailable L160, TestShadow L177, TestTurnServerDown L325, TestRequestServerDown L347.
  - Helpers: `Register` L428, `Remove` L447, `Leftovers` L459, `Use` L402, `Guard` L417, `Row` L483, `Names` L497, `Leaks` L568.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/ZzServers.cls` -- reports into `^||ZzMcp("report", n)`. `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnAdapter.cls` -- `TwoConfigs` L32, `ComposeTwice` L40, `AttachedCount` L19.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` -- TestExtensionBases (L179-214).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `MINTIMER` 12 (L148), `MAXTIMER` 110 (L145), `TimerSeconds` 60 (L239): Decide's timer.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Client.cls` (new; Lane A) -- OcuTalon's minimal MCP HTTP client. Story 22.3 adds `tools/call` to it.
  - `Parameter PROBESECONDS = 2`.
  - `ClassMethod Probe(url As %String, seconds As %Integer = {..#PROBESECONDS}) As %String` answers `""`, `unreachable` or `failed`:
    - It POSTs one JSON-RPC `initialize` (`protocolVersion` `2025-03-26`, empty capabilities, a fixed `clientInfo`) with `Content-Type: application/json` and `Accept: application/json, text/event-stream`.
    - It sets `OpenTimeout` and `Timeout` to `seconds` and `FollowRedirect` 0. It uses `Install.Step.SSL.#NAME` for `https`.
    - It sends no credential.
    - Any HTTP response gives `""`. No response (timeout, refused, TLS) gives `unreachable`. A URL that is not `http://` or `https://` gives `failed`.
  - It never throws, and never logs or returns the URL.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ClassMethod Probe(server As %String, config As %String) As %String`. The default is `""`: no probe, so the bridge alone, which names no server, is unchanged. The doc states the contract:
  - it is called before every attach, at the build and per request, outside every callback;
  - it must return within a few seconds;
  - it answers `""` or a `REASONS` word;
  - a host that lists servers overrides it.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls` -- `Probe(server, config)`: the entry's `url` through `OcuTalon.Bridge.ConfigStore.Details(config)`. A missing entry or `url` gives `failed`; otherwise `Client.Probe(url)`. Update the header.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - **Parameter.** `Parameter RESTSECONDS = 60`.
  - **Transient state**, reset in `BuildAgent`: the class from `AttachServers`; the server and config of each recorded MCP spec; this job's last reported status per server; each server's rest end (`$ZHorolog`).
  - **Private `Answers(server, config) As %String`.** It calls the class's `Probe` in a Try; an exception, or an answer that is neither `""` nor a `REASONS` word, gives `failed`.
  - **Private `ReportOf(manager, spec, builtin)`.** The report builder, extracted from `AttachOne`: a name in `builtin` goes to refused; otherwise an `available` (or empty) status goes to tools; 22.2's fingerprints are added here.
  - **`AttachServers`/`AttachOne`.** The servers go to one new report-only `%AI.ToolMgr` per build, never to `agent.ToolManager`. For each server, after the config check:
    - probe; a failure reports `unavailable` with that reason;
    - otherwise `AddTool` on the report manager; an error reports `ReasonOf`;
    - on OK, record the spec and server, and report `ReportOf`.
  - **`BuildTurnManager`, MCP loop.** Before the loop, take `builtin` = `ToolNames(manager)`. For each recorded spec:
    - while the server rests: skip it;
    - when `Answers` or `AddTool` fails: one warning (the server's name and the reason word, never the URL), rest until now + `RESTSECONDS`, and report `unavailable` unless this job's last report already says so;
    - on success: report `ReportOf` when this job's last report said `unavailable`.
  - **Skills branch.** When a spec is recorded, log one warning per build that the agent's MCP tools are not offered.
  - **Docs.** Update the class doc and the method docs.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`:
  - **`Silence(port, hold As %Integer = 20)` and `Speak(port)`.** While a port is silent, the mock reads and logs each request and answers none. It holds each connection open until `Speak`, `Stop` or `hold` seconds, and then closes it. The loop checks every 0.1 s.
  - **`Requests` gains two fields.** `answered` is 1|0. `client` is `iris` when the `User-Agent` header names InterSystems IRIS (the probe), else `other`.
  - **Cleanup.** The nodes live under `^IRIS.Temp.OcuTalonMcpMock(port)`, and `Stop`/`Forget` clear them. Default off.
  - Update the header.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/ZzServers.cls` -- an opt-in `Probe`: while `^||ZzMcp("probe")` is 1 it counts `^||ZzMcp("probes")` and delegates to `OcuTalon.Mcp.Attach.Probe`. Otherwise it gives `""`, so the existing tests are unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnAdapter.cls` -- `Parameter RESTSECONDS = 3`, so a test can act inside the rest and then wait it out; update the header.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls` (new) -- with the mock, which the test starts and stops:
  - silent: `unreachable` within 6 s;
  - answering: `""`, and the mock logged one `initialize` with `auth` `absent` and `client` `iris`;
  - refused port: `unreachable` within 3 s;
  - `ftp://x` and `""`: `failed`;
  - `Mcp.Attach.Probe` with no entry: `failed`; with a fixture entry pointing at the mock: `""`;
  - no leftovers.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls`:
  - **New `TestSilentAtBuild`** (`Mcp.Attach`): Register, then `Silence`. `BuildAgent` is OK within 10 s; the row reads `unavailable|unreachable`; `AttachedCount` is 1; the mock logged only `client` `iris` requests; `Leaks` is empty.
  - **New `TestSilentInRequest`** (`ZzServers` with probe 1, the fixture server):
    - the build reports `attached`;
    - after `Silence`, `TwoConfigs` is OK within 10 s, lists none of the mock's tools, and adds one `unavailable`/`unreachable` report;
    - a second `TwoConfigs` at once adds no probe and no report;
    - after `Speak`, `Hang 3.5`, `TwoConfigs` lists the mock's tools and adds one `attached` report.
  - **New `TestOwnManagerHasNoServer`**: build with the mock answering.
    - The own manager lists `OWN,zz_turn_set` only.
    - After `Silence`, `ExecuteTool("zz_turn_set")` on the own manager returns within 5 s.
    - `Inventory` has no entry with source `mcp`.
    - The mock got no request after `Silence`.
  - **Update** TestAttach (L113: the own manager has none of the mock's tools; the header check counts only `client` `other` requests), the TestShadow comments, TestRequestServerDown and TestTurnServerDown (doc: the own manager holds no server), and the class header.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` -- TestExtensionBases: `McpServers.Probe` gives `""`.

**Acceptance Criteria:**
- Given a registered server that accepts the connection and never answers, when a runner builds its agent, then the build is OK within 10 s, the server gets no request from AI Hub's client, the agent has none of its tools, and its `Mcp.Server` row says `unavailable` / `unreachable` (Story 35.1's report; 22.2 adds the notice).
- Given a server that answered at the build and then stops answering, when a request composes its manager, then the request goes on within 10 s without the server's tools and this runner reports it `unavailable` once. Requests within `RESTSECONDS` neither probe nor report it. Once it answers after the rest, the next request offers its tools and reports `attached`.
- Given a server attached at the build that stops answering, when a replay or a `ToolInventory` request runs on that runner, then it completes in normal time and the server gets no request.
- Given no registered server (the demo path, the online demo), when any request runs, then no probe and no report is made: `TestBridgeAlone` and `TestFreshInstall` stay green with the mock seeing no request.
- Given any test of this story, when its output, logs and reports are searched, then the fixture secret and the mock's URL appear in none, and the probe's request carries no credential.

## Spec Change Log

- 2026-11-12 (runner, lane change): Epic 22 moved to lane D (slot `ocutalon-slot-d`, lock folder `lane-d`, port 52804) by the Contest Planner's ruling; the Verification lane variables now name lane D. Nothing else changed.

- 2026-11-11 (runner, rulings applied): the Contest Planner's rulings (verbatim under Design Notes) are applied: veto items accepted; residual (a), with Story 22.10 filed after 22.7 for the AD-21 amendment; spine S8-S11 written.

- 2026-11-11 (runner, spec gate): validated. The Veto items, spine updates S8-S11 and the mid-request residual (options (a)/(b) under Design Notes) go to the Contest Planner (via the orchestrator) before the implement stage; this story implements only after Stories 22.2 and 22.8 are committed.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-6: no `%AI` or Python in callbacks; the probe runs at the build and in `SessionConfigFor`.
- AD-8: Decide's timer.
- AD-19: no credential in the probe; secrets stay `secret://`.
- AD-21: "AI Hub lists, OcuTalon calls"; the measured attach facts.
- AD-22: the loopback mock.
- AD-25: the online demo.
- AD-29: lanes.
- AD-31: `McpServersClass`.
- AD-32 and AD-33: the notice and the row, through 22.2's `RecordAttach`.

**Timeout values (decided).**
- `PROBESECONDS` 2: a silent server gives up in 2.011 s (measured), and a loopback answer takes 1 ms. A healthy remote server answers `initialize` in under 1 s (inference).
- `RESTSECONDS` 60: one silent server costs about 2 s (at most about 4 s) once a minute in each runner job.
- Decide's timer is 60 s by default (12 to 110 s), so this stays inside it. Several silent servers at once cost n × 2 s (inference). The worst case is a late reply, which Decide's fallback route takes; the runner is never held.
- The demo path has no server, so it pays nothing. Healthy servers cost one extra POST per server per request.

**Decided in-stage:**
1. The probe lives in the host's extension (`McpServers.Probe`), not in the bridge. An HTTPS probe needs the host's client SSL configuration (`OcuTalonClient`), and the bridge names no host class (AD-2). The default `""` keeps the bridge alone as it is: it names no server.
2. No credential, and any HTTP status counts as an answer. This is a liveness check: a 401 from an authenticating server is an answer.
3. A silent server is `unreachable` (`ReasonOf` already maps "timed out" to that word). No entry, an unusable URL or a throw is `failed`. `REASONS` is unchanged.
4. The agent's own manager holds no MCP server (evidence (2): every listing and every tool call lists each MCP server on the manager). All servers of a build go, in order, to one report-only manager, so shadowing between servers stays as it was.
5. The runner reports per request only on transitions in its own job. The recovery report uses the build's builder.
6. A skills agent gets no MCP tool (before this story it got them from the own manager, unprobed). This is a bridge-only case: OcuTalon's agents declare no skills.
7. Before 22.4, the replay of an approved MCP tool now fails with `ToolNotFound` instead of running through AI Hub's MCP execution, whose result can't be cut (fail closed).
8. The mock's silent hold (20 s) turns a mutation into a slow red, never a hang. Tests assert a 10 s bound against the 2 s probe, which leaves margin for CI load.

**Escalation for the runner's ruling (it does not block implementing this spec):** the residual, measured.
- A server that stops answering after its probe passed, during the same request, blocks the runner job until the server closes the connection. The request's `%Discover()`, `Chat`'s listings and every tool call each list it (evidence (1)-(3)), and nothing in IRIS can interrupt that.
- So "a blocking native call must never run unbounded on a runner job" is met for the attach and the start-of-request listing (the AC), not for a server that fails mid-request.
- The only full bound is an AD-21 amendment (veto item 9): OcuTalon lists through its own bounded client (this story's `Mcp.Client`) and offers the tools to the model without AI Hub's MCP client, as it already calls them (22.3).
- Recommended: (a) accept the residual for this release, have 22.6 document it, and file the amendment as a new story; or (b) rule the amendment into Epic 22 now.

**Extend, don't copy (Rule 2):**
- `ReportOf` is extracted from `AttachOne` (one builder for the build and the recovery).
- `Mcp.Client` is the seed that 22.3's `call_mcp_tool` client extends.
- `Mcp.Attach.Probe` reuses `Bridge.ConfigStore.Details`.
- The probe's request setup copies about 8 lines of `Telegram.Api.Call`: that class is Lane B's, and its contract (a bot token, the Bot API's JSON answer) differs.
- The mock's silent mode extends `Serve`/`Connection`; the tests reuse `Test.Mcp.Attach`'s helpers.

**Integration ACs (Rule 1):**
- Consumer: the real runner adapter (shadow runner) with `McpServersClass` `Mcp.Attach` and the loopback mock. It builds and composes in bounded time without the silent server (ACs 1-3).
- Consumer: `Mcp.Ops.RecordAttach` through `OnAttach` (real) records the row `unavailable` (AC 1).

**Consumes:**
- 35.1: `Mcp.Attach`, the attach report, `ReasonOf`, the mock and the shadow-runner fixtures.
- 22.2: `RecordAttach` and its notices, the fingerprints in the report.
- 22.8: `MapMcpTools` runs on the composed manager, unchanged.
- `Install.Step.SSL`.

**Consumed-by:**
- 22.3: `Mcp.Client` gains `tools/call`.
- 22.4: a replay must run `call_mcp_tool` directly, because the own manager holds no MCP server.
- 22.5: polls are `tool` requests and never reach AI Hub's MCP client.
- 22.6: documents the bound, the rest and the residual.

**Footprint extension:** `Bridge/Ext/McpServers.cls`.

**Spine updates for the lead (Rule 20):**
- S8 (AD-21, Listing): the agent's own manager holds no MCP server. The build attaches each server to a report-only manager after `Probe`. Each request's manager adds only the servers whose probe answered within 2 s. A failure rests the server 60 s per runner job. Per-request reports go out on transitions.
- S9 (AD-31): `McpServersClass` gains `Probe(server, config) As %String` (default `""`). OcuTalon probes with an unauthenticated `initialize` (`OcuTalon.Mcp.Client`).
- S10 (AD-21, measured attach facts): no platform deadline (evidence (1)); every listing and tool call lists each MCP server on the manager; `Terminate` waits for the native call.
- S11 (Deferred): the mid-request residual, pending the ruling above.

**Ledger inbox (Rule 17):** DW-1013 is addressed:
- Task 0 is measured (evidence file). `MCPDescriptor` takes no timeout key, confirmed (L16-82).
- Attach and per-request listing are bounded, with a clear error through the 35.1 report and 22.2's `mcp.serverUnavailable`.
- The residual is escalated above.

**Runner notes:**
- No split: four source classes and three test classes.
- Online demo: no server can be registered, so nothing changes.
- DW-1038: the silent mode is off by default, binds the loopback only (the same `Serve`), and is cleared by `Stop`/`Forget`.


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

**Applied** (runner, 2026-11-11): veto items accepted as listed (the 2 s `initialize` probe to admin-registered servers only, the 60 s rest, no MCP server on the agent's own manager, the side effects). The residual is option (a): accepted now; Story 22.6 documents it; the AD-21 amendment (OcuTalon lists and offers MCP tools through its own bounded client) is the new Story 22.10, inserted after 22.7. Spine S8-S11 written (AD-21 "Step 4 build", AD-31 extension bullet).

## Veto items

- **An outward request.** Before every attach (the build, and each request while a server is registered), OcuTalon sends each registered server one unauthenticated JSON-RPC `initialize` POST, with IRIS's default User-Agent and `OcuTalonClient` for `https`. It goes only to admin-registered servers, which AI Hub already contacts.
  - Online demo: never sent.
- **Behaviour.** Skills agents no longer get MCP tools. A pre-22.4 approved MCP replay fails closed.
  - Online demo: no change.
- **The AD-31 extension contract** (S9).
- No new privilege, resource, grant, table, column, retention, setting or web dependency.

## Public text

None new.
- The warnings are log lines with no user audience. They name the server and the reason word, never a URL or a secret.
- Admins see the accepted `mcp.serverUnavailable` key, sent by 22.2.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Check `ci/warm.sh status` first.
- Run `OCUTALON_RUN_TAG=e22s9iw ci/warm.sh up` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s9iw` on each class call.
- Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call, with `timeout: 600000`.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Client` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: passed (needs the production; warm stack)
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Loopback` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.TurnTools` -- expected: passed
- (loop) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite (the Mcp and Bridge areas of `lane-a`), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- the mock's request log (new fields `answered` and `client`) and its modes;
- the agent's own manager's tool list (`Test.Mcp.Attach` TestAttach and TestShadow; `Test.Agent.Runners` TestToolInventory);
- the attach reports and the `Mcp.Server` rows;
- `ZzTurnAdapter`'s parameters;
- `ZzServers`;
- the `Ext.McpServers` base (`Test.Bridge.Ext`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to record (Rule 19):** each mutation should turn the named test red.

| Mutation | Test that goes red |
| --- | --- |
| No probe in `AttachOne` | `TestSilentAtBuild` (slow, and AI Hub's `initialize` is logged) |
| No probe in `BuildTurnManager` | `TestSilentInRequest` |
| MCP spec added to `agent.ToolManager` | `TestOwnManagerHasNoServer` |
| No timeouts in `Client.Probe` | `Test.Mcp.Client` silent row |
| No rest | `TestSilentInRequest` (probe count) |
| Report on every request | `TestSilentInRequest` (report count) |
| `Mcp.Attach.Probe` returns `""` | `TestSilentAtBuild` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
