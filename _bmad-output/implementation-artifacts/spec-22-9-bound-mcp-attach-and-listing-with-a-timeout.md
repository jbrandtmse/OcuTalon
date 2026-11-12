---
title: 'Story 22.9: Bound MCP attach and listing with a timeout'
type: 'feature'
created: '2026-11-11'
status: 'done'
baseline_revision: '89ece732b9262afc8273df52d52aa41827435624'
baseline_commit: '89ece732b9262afc8273df52d52aa41827435624'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-9-task0-mcp-hang.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-2-classify-mcp-tools-by-server-and-name.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-8-classify-mcp-calls-by-fingerprint-in-the-gate.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A server that sends a status line and headers (for example an event stream) and then stalls or errors before the body ends is reported unreachable by Client.Probe, although it answered with an HTTP status.
    evidence: |-
      Client.Probe answers "" only when request.Post returns OK and an HttpResponse exists. If Post returns an error after the headers arrived (a read timeout on the body), the probe says unreachable and the server is left off the manager and rested. Unverified: it depends on whether %Net.HttpRequest keeps HttpResponse.StatusCode when the body read times out. A mock mode that sends a status line and headers and then stalls would settle it; a possible fix is to count a response whose StatusCode is above 0 as an answer.
    location: >-
      src/ocutalon/cls/OcuTalon/Mcp/Client.cls (Probe)
    severity: medium (unverified)
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

### Review Findings

Code review 2026-11-12 (full mode; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor at the session tier; 40 rows, 15 entries after grouping, 17 rows rejected). Verdicts: high 0, medium 8, low 7.

- [x] [Review][Patch] (med, fix-risk low, in-story) A status line followed by a stalled body read as unreachable (DW-1204; blind+acceptance+verification-gap) -- `Probe` now counts a response that carries a status (`StatusCode > 0`) as an answer; `TestStalledBody` expects `""` [src/ocutalon/cls/OcuTalon/Mcp/Client.cls:46]
- [x] [Review][Patch] (med, fix-risk low, in-story) `Endpoint` refused addresses that registration accepts (`[::1]`, a query straight after the host, a fragment; blind) -- a bracketed IPv6 host, `/` before a bare query, the fragment dropped; `TestEndpoint` extended [src/ocutalon/cls/OcuTalon/Mcp/Client.cls:56]
- [x] [Review][Patch] (med, fix-risk low, in-story) AI Hub's AddTool error text (it holds the secret and the address, measured) was no longer pinned out of logs and reports, because the probe now stops the down server before AddTool (verification-gap) -- `Leaks` and `AddressShows` in `TestAddToolFailsInRequest`, new `TestAddToolFailsAtBuild`; `TestUnavailable`'s message no longer claims AI Hub's text [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] (med, fix-risk low, in-story) The recovery report was checked for its status only, and its step had no mutation line (verification-gap) -- `TestSilentInRequest` asserts the third report equals the build's (tools, refused, fingerprints) [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] (med, fix-risk low, in-story) The build's warning (matrix 'Build, silent') was never asserted (verification-gap) -- `TestSilentAtBuild` counts one warning naming the server [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] (med, fix-risk low, in-story, Rule 19 hermeticity) The 'inside the rest' steps raced the 3 s rest on a loaded host (verification-gap) -- `ZzTurnAdapter.RestLeft`; the step runs only while more than 0.5 s of the rest is left, else a log message says it was not checked [src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnAdapter.cls]
- [x] [Review][Patch] (low, in-story) `TestOwnManagerHasNoServer` did not check its calls' outcomes (blind+acceptance) -- the own tool is found, the server's tool gives `ToolNotFound` [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] (low, in-story) The warnings said "did not answer" also when the probe answered and AddTool failed, or the entry was missing (blind) -- "is not available (<reason>)" [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:360,683]
- [x] [Review][Patch] (low, in-story) `Mock.Status` kept an earlier Location (blind+edge) -- a call without a location clears it [src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls:114]
- [x] [Review][Patch] (low, in-story) Dead helper `ZzTurnAdapter.MapOwn` (edge) -- removed [src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTurnAdapter.cls]
- [x] [Review][Patch] (low, in-story) `Leaks`' unused manager argument and its stale reason (edge+acceptance+verification-gap) -- removed [src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls]
- [x] [Review][Patch] (low, in-story) An exception's text in a test message (acceptance; Always rule) -- `exception.Name` [src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls]
- [x] [Review][Patch] (low, in-story) `TestRedirectNotFollowed` did not check its second mock's cleanup (verification-gap) -- asserted [src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls]
- [x] [Review][Defer] (med, by-design, DW-1210) A server down or silent at the build is not recorded, so the runner job never offers it before the next build (edge) -- deferred: spec-bound (matrix row 'Build, silent'), pre-existing since 35.1 [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:AttachOne]
- [x] [Review][Defer] (med, by-design, DW-1211) Per-job transition reports against one shared `Mcp.Server` row (blind+edge) -- deferred: spec-bound (Always rule, Design Notes decided 5); the wrong direction is the safe one [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:OfferServers]

Rejected:
- (spec edit) The spec's frontmatter `deferred`, Triage Log and Auto Run Result still call DW-1204 unverified (blind, acceptance x2, verification-gap): build-auto's sections; DW-1204 is resolved above and reported to the lead.
- (false) Stale shadowing docs in `AttachServers`/`ReportOf` (blind): every composed manager adds the agent's own tools before the servers, so AI Hub shadows the server's copy there; the docs' reason holds.
- (low) The recovery report takes `builtin` from the request's manager (blind): the Tasks line says so; it needs a server tool named like the one turn tool (`documents`).
- (spec-bound) `ToolInventory` lists no MCP tool (blind): matrix row 'Replay or inventory'; the security statement covers built-in tools only.
- (low) Two Servers entries with one config (edge): OcuTalon's `Servers` derives configs from unique `Mcp.Server` names; a guard for another host.
- (low) `ReportOf` throwing after `Record` (edge): the next request's recovery report corrects it; needs a manager that just accepted AddTool and cannot list.
- (low) `McpReported` set before `OnAttach` fails (edge): the failure is one warning; the fix adds a return path to `ReportAttach`.
- (low) A skills agent's servers report attached (edge): Design Notes decided 6, a bridge-only case.
- (low) System-wide `%Net.HttpRequest` defaults (proxy, username) reach the probe (edge): OcuTalon sets none; guards for a site setting.
- (low) "2 s" understates a probe that nears each phase's limit (edge, blind): each phase's timeout ends the probe; stacking needs a server that answers every phase just under 2 s.
- (low) `Attach` does not refuse an `mcp:` spec (acceptance): no caller passes one; a guard.
- (low) `TestReadOnlyTurnSkills` and `TestMapFailures` rewritten (acceptance): forced by Design Notes decided 4 and 6, recorded under the implementation notes.
- (false) Plain `http://` to any host (acceptance): `Mcp.Ops.AddressAllowed` refuses it at registration, so no entry holds one.
- (false) AC 3 not driven through the replay (acceptance): `CallTool` runs `adapter.Agent.ToolManager.ExecuteTool`, the call `Replay.cls` L98 makes; the outcome half is patched above.

## Spec Change Log

- 2026-11-12 (runner, lane change): Epic 22 moved to lane D (slot `ocutalon-slot-d`, lock folder `lane-d`, port 52804) by the Contest Planner's ruling; the Verification lane variables now name lane D. Nothing else changed.

- 2026-11-11 (runner, rulings applied): the Contest Planner's rulings (verbatim under Design Notes) are applied: veto items accepted; residual (a), with Story 22.10 filed after 22.7 for the AD-21 amendment; spine S8-S11 written.

- 2026-11-11 (runner, spec gate): validated. The Veto items, spine updates S8-S11 and the mid-request residual (options (a)/(b) under Design Notes) go to the Contest Planner (via the orchestrator) before the implement stage; this story implements only after Stories 22.2 and 22.8 are committed.

## Review Triage Log

### 2026-11-12 — Review pass
- verdicts: 36 findings — high 0, medium 8, low 20, false 7, maybe-false 1
- findings:
  - `[low]` `[reject]` Blind: a host that lists servers but does not override Probe gets no protection and no warning — decided design (Design Notes decided 1): the default keeps the bridge alone unchanged; OcuTalon's host overrides it; a warning would add complexity for a hypothetical host
  - `[false]` `[reject]` Blind: the class description of a skills agent is stale — the description still holds: a skills agent's request runs on the own manager, which MapMcpTools lists and finds no MCP tool; the new sentence says so
  - `[medium]` `[by-design]` Blind: a server that fails its probe at the build is never retried in that job (also Edge 3, Intent) — the matrix row 'Build, silent' says 'spec not recorded', and the Tasks record a server only after the probe and AddTool; changing it alters AC'd behaviour; noted under the implementation notes
  - `[low]` `[reject]` Blind: ReportOf failing after a passed probe repeats the unavailable report every request — needs GetToolStatuses to throw on a manager that just accepted AddTool; no realistic path; wontfix-theoretical
  - `[low]` `[reject]` Blind: the probe sends no notifications/initialized or session close — the spec fixes the probe at one initialize POST; one orphaned session on a server that keeps sessions is the cost of a stateless liveness check; by-design
  - `[low]` `[reject]` Blind: each request pays a probe per healthy server; DNS and per-read timeout can outlast the bound (also Edge 9) — cost stated in Design Notes (one POST per server per request; n x 2 s); the bound is OpenTimeout and Timeout as the spec says; the https handshake gap that this review found is fixed separately (WriteTimeout)
  - `[low]` `[reject]` Blind: the probe can disagree with AI Hub's client about reachability (proxy, private CA, redirect) — the spec fixes the probe's setup (OcuTalonClient, no redirect); a mismatch fails closed and shows as unavailable; no evidence of a real server in the product
  - `[low]` `[patch]` Blind: Endpoint rejects hosts with an underscore and IPv6 literals; placeholders in the url (also Edge 6, 7, VG other) — patched the underscore (a container or service name) in the authority pattern and TestEndpoint; IPv6 literals stay failed (rare, adds a bracket form); the entry's url holds no placeholder (Details resolves a secret:// only in a header value, never in url)
  - `[medium]` `[patch]` Blind: TestOwnManagerHasNoServer calls a fixture tool and checks only elapsed time (also VG) — patched: the test now asserts that a call of the server's tool (zz_lookup) is not found within the bound and that the inventory lists the agent's own tool
  - `[low]` `[patch]` Blind: Test.Mcp.Client leaves 401/403/5xx, https, redirect, query and default-port parsing untested (also VG 3, 4) — patched: TestStatusIsAnAnswer (401, 403, 503 through the mock's new Status mode) and TestEndpoint (https default port, query, http default port, underscore, https against a plain and a silent mock); the redirect rule has no test (FollowRedirect 0 is the default of a request that never gets a Location from the mock) and no mutation line
  - `[false]` `[reject]` Blind: the silent mock can hand stale connections to later probes in TestSilentInRequest (also VG hermeticity) — the 3.5 s wait after Speak (RESTSECONDS 3 plus 0.5) is far longer than the mock needs to drain a stale connection (it reads and answers in milliseconds, and Serve catches a write to a closed socket); the class passed 7 times in this pass on a loaded host
  - `[low]` `[reject]` Edge 1: a subclass calling Attach with an mcp: spec lands unprobed on the own manager — no subclass in the repo does (OcuTalon's agents attach servers only through McpServers); wontfix-theoretical
  - `[low]` `[reject]` Edge 2: an Attached mcp: spec with no McpOf entry probes class '' — only Record adds an mcp: spec the runner offers, and it always sets McpOf; same precondition as Edge 1
  - `[medium]` `[by-design]` Edge 3: a server down at the build never gets tools until a rebuild — same as Blind 3
  - `[false]` `[reject]` Edge 4: the recovery report uses the request manager's names as builtin — the spec says it: 'BuildTurnManager, MCP loop: before the loop, take builtin = ToolNames(manager)'
  - `[low]` `[reject]` Edge 5: no overall per-request bound for several silent servers — stated in Design Notes (n x 2 s, inside Decide's 60 s timer); each silent server then rests
  - `[low]` `[patch]` Edge 6: the authority pattern rejects IPv6 literals, underscores and a query with no path — see Blind 8: underscore patched; the others are not usable urls for the product
  - `[false]` `[reject]` Edge 7: a placeholder in the entry's url makes the probe say failed — ConfigStore Details resolves no placeholder, and the entry's url is a plain http(s) url; AI Hub reads the same text
  - `[maybe-false]` `[defer]` Edge 8 and Edge 13: a server that sends headers (an event stream) and then stalls or errors is reported unreachable although it answered with a status — would settle it: a mock mode that sends a status line and headers, then stalls, and whether %Net.HttpRequest.Post returns an error with HttpResponse.StatusCode set; deferred as medium (unverified)
  - `[low]` `[reject]` Edge 9: the timeouts are per read, so a server that dribbles bytes outlasts the bound — same as Blind 6; a dribbling server is not the measured failure (accept and never answer)
  - `[low]` `[reject]` Edge 10: the server can go silent between the probe and AddTool — the accepted residual (ruling (a)); Story 22.10 covers it
  - `[false]` `[reject]` Edge 11 and Edge 15: the skills warning is logged on the first request, not at the build — the spec puts it in BuildTurnManager's skills branch ('log one warning per build'), which only runs when a request composes
  - `[low]` `[reject]` Edge 12: a skills agent with class tools fails the request and the MCP loss is silent — the failure message names the agent and the skills reason; the agent class and its MCP servers are a bridge-only case (Design Notes decided 6)
  - `[false]` `[reject]` Edge 14: the recovery report builtin differs from the build's — same as Edge 4; spec text
  - `[medium]` `[patch]` VG 1: the fail-closed rule (a throwing or junk probe) is untested — patched: ZzServers probe modes 2 and 3, TestProbeThrows and TestProbeJunk; mutation lines written and demonstrated
  - `[medium]` `[patch]` VG 2: a request whose probe answers but AddTool fails is untested (matrix row 'Request, back') — patched: ZzServers mode 4 and TestAddToolFailsInRequest; mutation line demonstrated
  - `[medium]` `[patch]` VG 3: any HTTP status counts as an answer is untested — patched: Mock.Status and TestStatusIsAnAnswer; mutation line demonstrated
  - `[medium]` `[patch]` VG 4: the https path and URL parsing of Client.Endpoint are untested — patched: TestEndpoint; its https rows found that the https handshake was not bounded by OpenTimeout/Timeout (18 s against 6 s), so Client.Probe now sets WriteTimeout; two mutation lines demonstrated
  - `[low]` `[patch]` VG 5: the 'no url in a log line or report' half of AC 5 is checked for notices only — patched: AddressShows in TestSilentAtBuild and TestSilentInRequest (event log, row, reports); mutation line demonstrated
  - `[low]` `[reject]` VG 6: the recovery report is not exercised where a request tool shadows a server tool — spec-bound builtin (Edge 4); an edge case, no user-reachable failure found
  - `[medium]` `[patch]` VG 7: TestOwnManagerHasNoServer does not check the outcome of its calls — same as Blind 9
  - `[low]` `[patch]` VG Rule 19: AC 4 (no server registered) has no pinning test or mutation line — patched: TestNoneRegistered with the probe counter, and a mutation line (a probe asked with no server registered)
  - `[low]` `[patch]` VG Rule 19: the other new tests and the recovery-report step have no mutation line — written: probe-throws, junk, AddTool error, none registered, address in the log, WriteTimeout, status, https; the recovery step is pinned by the existing mutation 'unavailable report made unconditional'
  - `[false]` `[reject]` VG Rule 19: TestSilentInRequest acts after fixed sleeps with no readiness signal — the waits are the adapter's own rest (the state under test), not readiness of the mock, which is ready after Start; same as Blind 11
  - `[low]` `[reject]` VG other: the recovery report and Endpoint hosts — duplicates of Edge 4 and Blind 8
  - `[low]` `[reject]` Intent: readings R2 (bound every AI Hub call), R3(a), R4(b), R5 and the rewritten tests — descriptive; the diff implements R1 as the Approach states; the unbounded mid-request call is the ruled residual (a), the default Probe and the matrix's 'spec not recorded' are decided; the rewritten tests follow from the own manager holding no server

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

**Mutations demonstrated (Rule 19, warm stack e22s9iw, each reverted byte-identical and the class green again):**
- mutation: `AttachOne` without the probe (`Set reason = ""`) -> `Test.Mcp.Attach:TestSilentAtBuild` red (22.6 s: "within 10 seconds", "and nothing from AI Hub's client").
- mutation: `OfferServers` without the probe -> `TestSilentInRequest` red (28.7 s; the 10 s bound, the probe count and the reports).
- mutation: the build attaches to `agent.ToolManager` instead of the report manager -> `TestOwnManagerHasNoServer` red (own manager lists the mock's tools, the tool call and the inventory block, the mock gets requests).
- mutation: `Client.Probe` without `OpenTimeout`/`Timeout` -> `Test.Mcp.Client:TestSilent` red ("the probe gives up within 6 seconds", 21 s).
- mutation: `OfferServers` without the rest (`McpRest` not set) -> `TestSilentInRequest` red ("and neither probed nor reported").
- mutation: the unavailable report in `OfferServers` made unconditional (`If 1`) -> `TestSilentInRequest` red ("it probed again and did not report a server that this job reported unavailable already"). The first try of this mutation passed, so the test gained the step "a request after the rest, the server being silent still", which is the only place that a repeated report shows.
- mutation: `Mcp.Attach.Probe` returns `""` -> `TestSilentAtBuild` red (22.6 s).
- mutation: `Answers` catches an exception as `""` (fail open) -> `TestProbeThrows` red ("and no mcp spec is recorded", "the report says unavailable and failed", "AI Hub's client sent the server nothing").
- mutation: `Answers` takes any answer as given (`Set answer = result`) -> `TestProbeJunk` red ("the report says unavailable and failed").
- mutation: `OfferServers` ignores the `AddTool` error (no `ReasonOf` reason) -> `TestAddToolFailsInRequest` red (the report, the warning and the rest assertions).
- mutation: `AttachServers` asks `Answers` before the empty-list quit (a probe with no server registered, AC 4) -> `TestNoneRegistered` red ("nothing was probed and nothing was reported").
- mutation: `Mcp.Attach.Probe` logs the entry's url as a warning -> `TestSilentAtBuild` and `TestSilentInRequest` red ("and the server's address shows in no log line or report"; `TestCommands` also red).
- mutation: `Client.Probe` without `WriteTimeout` -> `Test.Mcp.Client:TestEndpoint` red (an https url against a mock that never completes the handshake: the probe waited until the mock closed, 18 s against a bound of 6).
- mutation: `Client.Probe` counts only a status below 400 as an answer -> `TestStatusIsAnAnswer` red (401, 403 and 503).
- mutation: `Client.Probe` with `Https` 0 -> `TestEndpoint` red ("an https url against a server that speaks plain HTTP is unreachable").

**QA stage (Rule 19; warm stack e22s9qw, lane D; each mutation reverted byte-identical, `git status --short` unchanged):**
- (QA) files: `src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls` (new tests `TestNoAuthorization`, `TestRedirectNotFollowed`, `TestStalledBody`, `TestStalledBodyKeepsStatus`) and `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls` (new modes `Stall`/`Unstall`; `Status` takes an optional Location). No new test class, so no `ci/units.sh` entry.
- (QA) re-demonstrated, not new: the `WriteTimeout` mutation below (the https handshake bound), observed red again at the QA stage.
- mutation: `Client.Probe` without `WriteTimeout` -> `Test.Mcp.Client:TestEndpoint` red (QA re-run: "within 6 seconds" for the https url against the plain mock and "and the probe gives up within 6 seconds, the handshake included"; 41 s against 22 s).
- mutation: `Client.Probe` sends `Authorization: Bearer x` -> `Test.Mcp.Client:TestNoAuthorization` red ("which carries no Authorization header"). `TestAnswers` stayed green under this mutation: it watches only the custom `X-Zz-Key` header, so AC 5's "no credential" half had no pin before.
- mutation: `Client.Probe` with `FollowRedirect` 1 -> `TestRedirectNotFollowed` red ("and the probe did not follow the redirect to the second mock"). The review log said the redirect rule had no test.
- mutation: `McpServers.Probe` default gives `unreachable` instead of `""` -> `Test.Bridge.Ext:TestExtensionBases` red ("and probes nothing: Probe gives an empty string, which is no probe").
- mutation: the skills branch warns on every composed request (the `SkillsWarned` guard removed) -> `Test.Mcp.Attach:TestReadOnlyTurnSkills` red ("and the build warned once").

**DW-1204 settled (QA, measured on the slot and on the warm stack):** a mock that sends `HTTP/1.1 200 OK`, `Content-Type: text/event-stream` and `Content-Length: 1000` and then no body makes `%Net.HttpRequest.Post` return ERROR #5922 "Timed out waiting for response" after `Timeout`, while `request.HttpResponse` is an object with `StatusCode` 200. `Client.Probe` tests `$$$ISOK(sc) && $IsObject(HttpResponse)`, so it answers `unreachable` (2.0 s) although the server answered with a status: the gap is real and contradicts the Always rule "counts any HTTP status within the bound as an answer". A fix that tests `+request.HttpResponse.StatusCode > 0` makes the probe answer `""` (the QA mutation above) and breaks no other test of `Test.Mcp.Client`. Production code was not changed by QA. Resolved in code review: `Client.Probe` counts a response that carries a status as an answer, and `TestStalledBody` expects an empty string (mutation line below).

**Code review (Rule 19; warm stack e22s9cw, lane D; each mutation reverted byte-identical, `git status --short` and `git diff --stat` unchanged):**
- mutation: `Client.Probe` answers only when `Post` returned OK (the DW-1204 fix reverted) -> `Test.Mcp.Client:TestStalledBody` red ("and the status it sent is an answer, although its body never completed").
- mutation: `Client.Endpoint` without the bracketed IPv6 alternative -> `TestEndpoint` red (the two `[::1]` rows).
- mutation: `OfferServers`' recovery report disabled (`If 0`) -> `Test.Mcp.Attach:TestSilentInRequest` red ("and the runner reported the server attached", "with the build's report").
- mutation: `OfferServers`' warning appends AI Hub's error text -> `TestAddToolFailsInRequest` red (the secret and the address show).
- mutation: `AttachOne` logs AI Hub's error text when AddTool fails -> `TestAddToolFailsAtBuild` red (the secret and the address show).
- mutation: `AttachOne` without its warning -> `TestSilentAtBuild` red ("the build logs one warning that names the server and the reason word").
- Final pass after the patches: `Test.Mcp.Client`, `Test.Mcp.Attach` (125 s), `Test.Mcp.Loopback`, `Test.Bridge.Ext`, `Test.Bridge.TurnTools` and `Test.Agent.Runners` passed; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` exit 0; `ci/warm.sh down` left no container, volume or network.

**Implementation notes (runner notes):**
- The recorded MCP spec stays in `Attached` (so `HasMcp`, `AttachedSpecs` and TestAttach's assertion are unchanged); its server and config are in the transient `McpOf(spec)`, the last report status in `McpReported(spec)` and the rest end in `McpRest(spec)`, all keyed by spec so that an empty server name cannot make a null subscript.
- `ReportOf` tests `builtin` first: the build's report manager holds no built-in tool, so AI Hub cannot mark a shadowing tool unavailable there.
- Tests changed beyond the Tasks list, because the own manager no longer holds a server: `TestReadOnlyTurnSkills` (a skills agent is offered no MCP tool; one warning per build) and `TestMapFailures` (the three failure cases now run on the manager a request composes; the unlistable-manager case uses the new `ZzTurnAdapter.MapBroken`). `TestTurnServerDown` and `TestRequestServerDown` now run `Leaks` on the own manager too.
- DW-1038 (flake family of `Test.Mcp.Attach`): every new test makes its own fixtures and state; the bare manager's `AddTool` in `TestShadow` is tried up to three times (`AddServer`); the silent mock's 20 s hold makes a mutation a slow red and never a hang; the new waits are the adapter's own rest (`RESTSECONDS` 3 plus 0.5 s) and no fixed sleep otherwise.
- Measured in the code-review patch pass (Task 0 style, loopback mock, warm stack `e22s9iw`): `%Net.HttpRequest` with `OpenTimeout` and `Timeout` set does not bound an https handshake. The handshake runs in the first write, whose `WriteTimeout` defaults to -1 (indefinitely): a mock that accepted and never completed the handshake held the probe for 18 s (until the mock closed). `Client.Probe` therefore also sets `WriteTimeout` (the property's minimum is 2 s), and `TestEndpoint` pins the https bound.
- `Client.Endpoint` accepts an underscore in the host (a container or service name). IPv6 literals stay unusable (`failed`).
- `Mock.Status(port, line)` (off by default, cleared by `Stop`/`Forget`) answers every request with a given status line; `ZzServers` probe modes: 1 delegates, 2 throws, 3 gives a word that is no reason, 4 answers `""` without asking the server.
- Patch-pass tests added: `TestProbeThrows`, `TestProbeJunk`, `TestAddToolFailsInRequest`, `TestNoneRegistered` (`Test.Mcp.Attach`), `TestStatusIsAnAnswer`, `TestEndpoint` (`Test.Mcp.Client`); `TestOwnManagerHasNoServer` also asserts that a call of the server's tool is not found within the bound and that the inventory lists the agent's own tool; `TestSilentAtBuild` and `TestSilentInRequest` assert that the mock's address shows in no log line, row or report. All are self-contained (own fixtures, `OnBeforeOneTest` state), and each waits on the mock's `Start` readiness or on the adapter's rest only (DW-1038).
- A server that fails its probe at the build is not recorded, so requests do not retry it before the next build (the matrix row "Build, silent": spec not recorded). It is the matrix's own behaviour, not a defect of this story.
- The warm class times: `Test.Mcp.Attach` 94-97 s on a host with load average 12 to 22 (its three new tests add about 16 s: `TestSilentAtBuild` 4.3 s, `TestSilentInRequest` 15.5 s, `TestOwnManagerHasNoServer` 1.2 s), `Test.Mcp.Client` 10.4 s.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Attach and per-request listing of MCP servers are bounded. Before every `AddTool` (at the build and in each request that composes a manager) the runner asks the new `McpServers.Probe(server, config)`; OcuTalon answers with `Mcp.Client.Probe`, one unauthenticated JSON-RPC `initialize` bounded to 2 s for the connection, each write (the https handshake included) and the answer. A server that does not answer is not added, is reported `unavailable` through the attach report (22.2's `RecordAttach` sends `mcp.serverUnavailable`) and rests 60 s per runner job. The agent's own manager never holds an MCP server (the build uses a report-only manager), so a replay or `ToolInventory` never touches a server. With no server registered nothing runs.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: `RESTSECONDS`; the report-only manager at the build; `Answers`, `ReportOf` (extracted), `Record`, `OfferServers`; the skills warning; docs.
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls`: `Probe` (default `""`) and its contract.
- `src/ocutalon/cls/OcuTalon/Mcp/Client.cls` (new): `Probe` and `Endpoint`.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls`: `Probe` through `ConfigStore.Details`.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/{Attach,Mock,ZzServers,Client}.cls`, `Test/Bridge/{ZzTurnAdapter,Ext}.cls`: the mock's `Silence`/`Speak`/`Status` and the new log fields; the probe fixture modes; the new and updated tests.

**Review.** 36 findings from four layers. Patches applied (12 rows, 11 root causes): the https handshake bound (`WriteTimeout`, found while pinning the https path), the underscore in a host, and tests for a throwing and a junk probe, `AddTool` failing in a request, no server registered, any HTTP status as an answer, https and url parsing, the mock's address in logs and reports, and the outcome of the own-manager calls; eight mutation lines written and demonstrated for them. Deferred: 1 (a status line followed by a stalled body may read as unreachable; medium, unverified). By-design: a server down at the build is not retried before the next build (matrix row). Rejected with a reason: the others (see the Review Triage Log).

**Follow-up review recommended: true.** Two or more medium entries were patched, and the production change `Client.Probe` `WriteTimeout` plus the new tests were written after the independent review layers ran. The risk to verify: that the https bound holds against a real TLS server that stalls mid-handshake (measured only against the plain loopback mock, 18 s before the change, under 6 s after).

**Verification.** Warm stack `e22s9iw` (lane D), final pass after the last patch: `Test.Mcp.Client` passed, `Test.Mcp.Attach` passed (91 s), `Test.Mcp.Loopback`, `Test.Bridge.Ext`, `Test.Bridge.TurnTools` and `Test.Agent.Runners` passed; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` exit 0. Fifteen mutation lines under `## Verification` were each demonstrated red and reverted (files byte-identical to a saved copy). `ci/warm.sh down` ran: no leftover container, volume or network.

**Residual risks.** The ruled mid-request residual (a server that stops answering after its probe passed holds the job; Story 22.10). The https bound is measured on loopback only (inference for a real TLS server). `Test.Mcp.Attach` takes 91-117 s on a loaded host (about 20 s of it the new tests).
