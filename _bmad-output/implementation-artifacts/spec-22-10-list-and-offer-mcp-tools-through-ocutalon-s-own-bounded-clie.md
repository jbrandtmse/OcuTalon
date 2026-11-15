---
title: "Story 22.10: List and offer MCP tools through OcuTalon's own bounded client"
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-9-bound-mcp-attach-and-listing-with-a-timeout.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-3-call-mcp-tools-only-through-the-governed-proxy.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-9-task0-mcp-hang.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/22-3-task0-proxy.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/35-1-task0-mcp-attach.md'
warnings: ['oversized', 'deferred: owner decision after the contest']
deferred: []
---

<intent-contract>

## Intent

**Problem:** AI Hub's MCP client still lists every MCP server. Each request's manager holds the servers whose 2 s probe passed, and AI Hub lists each of them at every listing and before every tool call, with no deadline (22.9's evidence: 300-632 s). So a server that passes the probe and then stops answering in the same request holds the runner job until the server closes the connection (spine S11, the residual Story 22.9 left). OcuTalon's own client has only a per-read deadline. Measured at planning: a server that sends one header line or one body byte per second held `Client.Probe` 31 s against its 2 s bound, and `Client.CallTool` 36 s against 20 s (DW-1221).

**Approach:**
- OcuTalon lists each server with its own client, `OcuTalon.Mcp.Client`. It offers the listed tools on the request's manager through a bridge-owned plain `%AI.Tool` provider, so no MCP server is ever added to an AI Hub manager.
- The gate recognises an offered tool by its metadata and governs it exactly as before: classification by fingerprint, the permission check, holds, the rewrite to `call_mcp_tool`, and audit.
- Every exchange of OcuTalon's client gets one total deadline.

## Boundaries & Constraints

**Always:**
- **Lane A files only (U-177).** These files:
  - `Mcp/{Client,Attach,Proxy}.cls`;
  - the bridge's `Ext/McpServers.cls`, `Adapter/Agent.cls`, the new `Adapter/McpOffer.cls`, `Policy/Gate.cls` and `Adapter/StepBuffer.cls`;
  - `Test/Mcp/{Client,Attach,Mock,ZzServers,Proxy,ProxyJob,Approval}.cls`, the new `Test/Mcp/Offer.cls`, and `Test/Bridge/{Gate,Ext,ZzTurnAdapter,CodeRules}.cls`;
  - the residual text under `docs/` only, if Story 22.6 wrote it.
- **No AI Hub MCP client.** No `mcp:` spec is added to any `%AI.ToolMgr`: not at the build, a request, a replay, a poll or an inventory. AI Hub's MCP client is never used for listing or calling.
- **The listing.** A listing is `initialize`, then `notifications/initialized`, then the `tools/list` pages (at most `MAXPAGES`):
  - one total deadline, `LISTSECONDS` (5 s), covers all of them;
  - it runs outside every callback (AD-6);
  - it goes only to an admin-registered server whose `url` passes `McpOps.AddressAllowed`;
  - it carries the entry's credential header, resolved in memory at that moment through 22.3's `Proxy.Header`;
  - it never runs on the online demo.
- **A failed listing.** A timeout, a refused or failed TLS connection, a non-2xx status, a malformed answer, or a `nextCursor` after page `MAXPAGES` fails the listing. Then the server offers no tools, is reported `unavailable` on a transition (22.9's per-job rule), and rests `RESTSECONDS` (60 s).
- **One total deadline per exchange of `Mcp.Client`.**
  - It covers the connection, the TLS handshake, the write and every read. The connection and handshake are also bounded by 2 s (`CONNECTSECONDS`, today's `PROBESECONDS`).
  - `tools/call` gets `CALLSECONDS` (20 s) in total. A proxy run is therefore at most `LISTSECONDS` + `CALLSECONDS` (25 s).
  - Reads drain what has arrived (`Read x#n:0`), then wait for one more character with the remaining time (`Read x#1:<remaining>`). Measured, under Design Notes: a timed read restarts its timeout when a packet arrives.
- **Transport.**
  - `https` uses `Install.Step.SSL.#NAME` (`VerifyPeer` 1) with SNI, and checks the host name through `%Net.HttpRequest.CheckSSLCN`. Plain `http` goes only where `AddressAllowed` permits it (loopback).
  - It follows no redirect.
  - It sends the same `User-Agent` as today (`Mozilla/4.0 (compatible; InterSystems IRIS;)`).
  - It decodes UTF-8 and accepts a `Content-Length`, chunked or close-delimited body of at most `MAXBODY` characters.
  - It reads a `text/event-stream` body only up to its first complete message with `id` 1.
- **The offer.** Each request gets one `OcuTalon.Bridge.Adapter.McpOffer` per server.
  - Its `%Discover()` is a callback, so it returns only the specs it holds and does no I/O.
  - Each spec has `name`, `description`, `parameters` (the tool's `inputSchema` as given), `requires_auth` true, and `metadata` `{origin_class: "OcuTalon.Bridge.Adapter.McpOffer", toolref}`. It has no `instructions`.
  - `%Invoke` never contacts a server. It answers `Gate.#FAILED`.
- **Names.**
  - The proxy toolset is registered on a request's manager before any offer, and only when at least one tool is offered.
  - These names are not offered:
    - a name the manager already holds, or `call_mcp_tool`: these are refused in the report, which sends `mcp.toolShadowsBuiltIn` (DW-1228);
    - a name an earlier server already offers: it goes neither to `tools` nor to `refused`, as today.
- **Identity.** Each server's toolref stays `mcp:remote:@{config:AI.MCP.OcuTalon_<server>}`. It is the server id in `ToolFingerprint(toolref, name, description, inputSchema)`, in the turn map, in a held row's `ToolSource` and in replays. So existing classification rows and pending approvals keep matching.
- **The gate decides exactly as before.** The `mcp:` toolref branch stays. The report keeps 35.1's shape (`status`, `reason`, `tools`, `refused`, `fingerprints`). The map is still `Context.SetMcpTools(catalog, servers)`.
- **Secrets.** No URL, secret, argument value or server error text goes into a log line, report, catalog, metadata, step, audit entry or test output.
- **Online demo.** Nothing is listed, offered or requested: `Attach.Servers()` gives `[]`, and `Attach.ListTools` answers `failed` before any request.

**Never:**
- Edit `Mcp/Ops.cls` (contended: 21.4, then 22.5), `Core.*`, `Web.*`, `web/**`, `Channel/**`, `Msg/Catalog*`, `Checks/**`, `GUIDE.md`, `README.md`, `Test/Contract/**` or any Lane B test.
- Add a route, table, column, resource, grant, privilege, setting, Config Store key or catalog key. Write a Config Store entry or a wallet secret.
- Use AI Hub's MCP client, a child job, `$SYSTEM.Process.Terminate`, or `%Net.HttpRequest` for an MCP exchange.
- Change 22.2's `RecordAttach` or its notices, 22.8's `ClassifyMcp`, 22.4's replay route, or 22.3's proxy order (re-list, fingerprint compare, call, cut, audit).
- Use a real MCP server.
- Delete, skip, tag off or shorten a test without moving its pin.
- Make `Test.Mcp.Attach` slower. New tests go in `Test.Mcp.Offer`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Build, answers | registered mock server answers | one listing from client `iris`; report `attached` with `tools`, `refused` and `fingerprints` from the listing; the agent's own manager lists no MCP tool | none |
| Build, fails | silent, trickling, refused port, non-2xx, no entry, bad `url` | `BuildAgent` OK within `LISTSECONDS` + 1 s; report `unavailable` (`unreachable` for no answer in time or no connection, else `failed`); the server is still recorded and rests | one warning naming the server and the reason word |
| Request, answers | listing OK | the proxy toolset, then one offer with the listed tools (built-in, `call_mcp_tool` and earlier-server names left out); map from the listing; turn-start `ClassifyMcp` as today | none |
| Request, silent or trickling | listing fails | the request goes on within `LISTSECONDS` + 1 s without the server's tools; one `unavailable` report on a transition; rest | as Build, fails |
| Mid-request | the server answered the request's listing, then goes silent before the model's call | the allowed call is rewritten to `call_mcp_tool`, whose re-list gives up: `MCPTIMEOUT` within `LISTSECONDS` + 1 s, one `MCP` `refused` audit (`timeout`). A built-in tool called in the same request returns at once, and the server gets no request from it | reason word only |
| Trickling call | `tools/call` answers one byte a second (DW-1221) | `MCPTIMEOUT` within `CALLSECONDS` + 1 s | as above |
| Down at build, back later | listing failed at the build; the server answers after the rest | the next request offers its tools, and this job reports `attached` (DW-1210) | none |
| Reserved name | the server lists `call_mcp_tool` and a built-in's name | neither is offered, both are in `refused`, and a rewritten call runs the real proxy (DW-1228) | none |
| Gate parity | an offered tool's call, for each 22.8/22.3/22.4 row: read-only, risky, unclassified, unregistered, no permission, changed fingerprint | the same decision and sentence as the `mcp:` toolref form of that call; a held row keeps `ToolSource` `mcp:…` and the fingerprint, and replays through `Agent.ProxyManager` | none |
| Offer reached unrewritten | `ExecuteTool(<offered name>)` with no rewrite | `Gate.#FAILED` text; no request to the server | none |
| Online demo | demo flag on, an `Mcp.Server` row present, mock running | no listing, offer, proxy or request at the build or in a request; built-ins unchanged | none |
| None registered | `Servers` gives `[]` | nothing: no listing, report or warning | none |

</intent-contract>

## Code Map

Line anchors are as of `6050472b4e223e50231a0668f6925bc9f2715cda`. Stories 22.5, 22.6 and 22.7 may land before this one, so re-grep the symbols.

- `src/ocutalon/cls/OcuTalon/Mcp/Client.cls`:
  - Parameters `PROBESECONDS` L22, `CALLSECONDS` L25, `MAXPAGES` L28, `MAXBODY` L31.
  - `Probe` L43 (to be removed).
  - `ListTool(url, header, tool, .definition, .session)` L60: stops at the first match; `notfound`.
  - `CallTool` L104.
  - `Open` L127: `%Net.HttpRequest`, `OpenTimeout`/`Timeout`/`WriteTimeout`, `FollowRedirect` 0, `OcuTalonClient`.
  - `Exchange` L157: the shared request; `Mcp-Session-Id`; maps code 5922 to `timeout`.
  - Helpers: `SetCredential` L194, `SessionOf` L206, `Decode` L214, `BodyOf` L230, `FirstMessage` L255 (SSE), `Endpoint` L285.
- `irislib/%Net/HttpRequest.cls` (read only):
  - L2075-2086: the read loop restarts its timeout after any partial read. This is why the transport is replaced.
  - L1664: the TLS `Open` form, `/TLS=<config>||<host>` for SNI.
  - L2417: `CheckSSLCN(server, .certificate)`, the host-name check to reuse.
  - L68: the default `User-Agent`.
- `irislib/%AI/ToolMgr.cls` L286-298 (read only): `AddTool` of a plain `%AI.Tool` registers it as a provider.
- `irislib/%AI/Agent/SubAgent.cls` L49-94 (read only): the precedent for a hand-written `%Discover`/`%Invoke`.
- `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls`:
  - `Run` L78; L81-86 resolve the entry, `url`, `AddressAllowed` and `Header`, which this story extracts into one shared method;
  - L88 `ListTool`, L90-97 the fingerprint compare;
  - `Header` L108, `Reason` L139.
- `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls`:
  - `Servers` L31 (`[]` on the demo), `Probe` L46 (replaced), `ProxyToolSet` L65, `Toolref` L79, `TOOLREFSTART`/`TOOLREFEND` L27-29.
- `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `REASONS` L36, `Probe` L47 (replaced), `ProxyToolSet` L59.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - Class doc L23-55 and state L148-161: `Attached`, `McpClass`, `McpOf`, `McpReported`, `McpRest`, `SkillsWarned`. `RESTSECONDS` L126.
  - Build: `BuildAgent` L277, `AttachServers` L323 (the report-only manager at L339), `AttachOne` L358 (spec L365, **`reporter.AddTool(spec)` L372**).
  - Reports: `ReportOf` L388 (reads `GetToolStatuses`), `Answers` L415 (calls `Probe`), `Record` L428, `ReasonOf` L437, `ToolNames` L445, `ReportAttach` L460.
  - Per request: `ComposeTurnTools` L558, `HasMcp` L573, `MapMcpTools` L585 (reads `..Agent.ToolManager.%Discover()` at L588 and keeps `mcp:` `tool_ref` entries), `BuildTurnManager` L625 (skills branch L634-641), `ComposeManager` L660, `OfferServers` L697 (**`manager.AddTool(spec)` L712**), `OfferProxy` L744.
  - Replay and inventory: `ProxyManager` L766, `Inventory` L1560.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `FAILED` L111; `MCPPROXY` L135.
  - `Check` L186-201; `Source(toolref, metadata, name)` L349, which recognises MCP by toolref only; `RagCall` L356.
  - `Decision` L204; `FromMcp` L607; `Reroute` L425; `ProxyArguments` L413 (`McpServerOf(source)`); `Hold` L256; `IsMcp` L767.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `SetMcpTools(catalog, servers)` L154 reads `tool_ref`, `name`, `description` and `parameters` of each entry. `McpServerOf` L244. `ToolFingerprint` L361 (the server id is the toolref).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` L192 and `McpLabel` L205, which handle an `mcp:` class, a rerouted note or the proxy name.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Mock.cls`:
  - Modes: `Describe` L95, `Shape` L101, `Silence` L108, `Status` L121, `Stall` L132, `Call` L144, `Pages` L150, `Session` L156.
  - `Requests` L168: `client` is `iris` by the User-Agent (L266); `auth`.
  - Tool list L344-349. There is no trickle mode.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Attach.cls` (about 165 s warm):
  - It pins AI Hub listing in TestAttach L171 (L200: matched header from AI Hub), TestShadow L268, TestTurnManager L230, TestSilentInRequest L736, TestOwnManagerHasNoServer L879, TestProxyRewrite L1104 (L1139), TestTwoNativeCalls L1330 (L1365), TestAddToolFails{InRequest,AtBuild} L814/L845.
  - Helpers `OtherRequests` L1902, `Leaks` L1940, `Spec` L1722, `Names`/`Listed` L1833/L1850.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/Client.cls`:
  - Probe tests L72-215: TestSilent, TestAnswers, TestRefused, TestNotUsable, TestStatusIsAnAnswer, TestEndpoint, TestNoAuthorization, TestRedirectNotFollowed, TestStalledBody, TestStalledBodyKeepsStatus, TestAttachProbe.
  - TestListTool L233, TestListToolPages L267, TestCallToolSilent L369, TestHttpsVerifiesTheServer L423.
- `src/ocutalon/cls/OcuTalon/Test/Mcp/ZzServers.cls` L19-28 (Probe modes 0-4); `Test/Bridge/ZzTurnAdapter.cls` L122-135 (records `source="mcp"` names); `Test/Bridge/Ext.cls` TestExtensionBases, TestMcpBases L299.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` L83 `CALLBACKHELPERS` (`Mcp.Client`, `Mcp.Proxy` and `Mcp.Attach` are already listed).
- `Test.Mcp.ProxyJob` L88/L140 and `Test.Mcp.Approval` L123 assert "no native `tools/call`".
- `ci/units.sh` L20/L143: `Test.Mcp.*` runs in `shard:lane-a@rest`, so a new `Test.Mcp.Offer` needs no registration.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement stage, on the lane D warm throwaway). Can a test stand up a loopback TLS listener whose certificate the test's client configuration trusts, under another host name?
  - Build it with a server and a client SSL configuration and a self-signed credential, created and removed only through `Security.SSLConfigs` and `%SYS.X509Credentials` in `%SYS`, on the throwaway only. `OcuTalonClient` itself is never changed.
  - If it can, the transport takes the client configuration name as an internal argument (the product passes only `OcuTalonClient`), and `Test.Mcp.Client` pins the host-name check: a wrong host is `unreachable`, the right host answers.
  - If it cannot, record why in this spec. The pin is then structural: the open uses `/TLS=OcuTalonClient||<host>`, and a failed `CheckSSLCN` is `unreachable`. Add a `deferred:` item (medium) naming the missing listener.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Client.cls`:
  - **Transport.** Replace `%Net.HttpRequest` with one private HTTP/1.1 POST over the `|TCP|` device, which `Exchange` uses. It meets the Always rules for the deadline and the transport. A status line or header section over 16 KB, or a body over `MAXBODY`, is `failed`. It never throws, logs or returns a URL or header.
  - **`ListTools(url, header, Output tools As %DynamicArray, ByRef session, seconds = LISTSECONDS) As %String`.** It answers `""` with every listed entry that has a string `name` (`name`, `description`, `inputSchema` as given), or `unreachable`, `timeout` or `failed`.
  - **`ListTool`** keeps its signature and `notfound`. It shares `ListTools`' page loop and deadline.
  - **`CallTool`** keeps its signature. Its deadline is total.
  - **Parameters.** Add `LISTSECONDS` 5; rename `PROBESECONDS` to `CONNECTSECONDS` (2).
  - **Probe.** Remove `Probe`, because nothing calls it any more.
  - Rationale: DW-1221; the listing becomes the liveness check.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Proxy.cls` -- extract `Run`'s L81-86 (the entry, the `url`, `AddressAllowed` and `Header`) into one method, for example `Target(server, Output url, Output header) As %String`, that `Run` and `Attach.ListTools` share. The order and outcome words of `Run` are unchanged. Rule 2: extend, don't copy.
- [ ] `src/ocutalon/cls/OcuTalon/Mcp/Attach.cls`:
  - `ListTools(server, config, Output tools) As %String` replaces `Probe`.
  - On the online demo it answers `failed` with no request.
  - Otherwise it calls `Proxy.Target`, then `Client.ListTools`. It maps `timeout` and `unreachable` to `unreachable`, and anything else to `failed`.
  - Update the header.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/McpServers.cls` -- `ListTools(server, config, Output tools As %DynamicArray) As %String` replaces `Probe`. The default answers `failed` with `[]`, so a host that lists servers but does not list them offers nothing (fail closed). Its doc states the contract:
  - outside every callback, at the build and per request;
  - it returns within about 6 s;
  - it answers `""` or a `REASONS` word;
  - each entry is `{name, description, inputSchema}`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/McpOffer.cls` (new; extends `%AI.Tool`) -- implements the Always rules for the offer:
  - properties `Server`, `Toolref` and the specs;
  - a builder from a listing that takes the names to leave out and gives the offered, refused and catalog entries;
  - `Parameter OFFERCLASS` = its own class name, which the gate reads;
  - a header that states the contract.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - **The build** (`AttachServers`/`AttachOne`): no report-only manager and no `AddTool`.
    - Record every listed server (its server, config and toolref), whatever its listing gave (DW-1210).
    - Then `Answers` → `ListTools`, and report from the listing.
    - `ReportOf` builds the report from the listing:
      - names in the own manager or `call_mcp_tool` go to `refused`;
      - earlier servers' names are left out;
      - `fingerprints` use `ToolFingerprint(toolref, name, description, inputSchema)`.
  - **Per request** (`OfferServers`):
    - list each server that is not resting, with 22.9's warning, rest and transition reports;
    - then, if any tool is offered: `OfferProxy` first, then `AddTool(<McpOffer>)` for each server;
    - keep the listing's catalog entries (`{tool_ref, name, description, parameters}`) for `MapMcpTools`. It passes them, not `..Agent.ToolManager.%Discover()`, to `SetMcpTools`.
    - When the proxy cannot be registered: one warning, no offer (22.3's rule).
  - **Keep.** `HasMcp` means "a server is recorded". The skills branch, `ProxyManager`, `Inventory` and `RESTSECONDS` are unchanged.
  - **Docs.** Restate the class doc (L23-55).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` -- `Source`: when `metadata.origin_class` is `McpOffer.#OFFERCLASS`, the source is `metadata.toolref` if `IsMcp` gives 1, else `""`, which is denied `FAILED`. This check comes before `RagCall` and `origin_class`. Every MCP step downstream already keys on the source. Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- a step whose class is `OFFERCLASS` is labelled like an `mcp:` call (`Running {tool} on {server}`, the server from the step's metadata `toolref`). Change it only if a test shows the label is otherwise lost.
- [ ] `docs/` -- if Story 22.6's text on the 2 s probe or the mid-request residual is there (grep "residual", "stops answering", "probe"), replace it with Public text 1. Any other docs sentence this story makes untrue is a `## Clarification Needed`.
- [ ] Tests:
  - **`Test/Mcp/Mock.cls`:**
    - `Trickle(port, phase, hold)`, where phase is `headers` or `body`: one line or byte a second;
    - `Extra(port, name)`: one more listed tool by that name;
    - both off by default and cleared by `Stop`/`Forget`.
  - **`Test/Mcp/Offer.cls` (new):** every matrix row through the shadow runner and the mock. `Leaks` everywhere. Sized under 120 s warm; split into `OfferTimes` if needed.
  - **`Test/Mcp/Client.cls`:**
    - every Probe test's pin moves to `ListTools`. The exception is "any status is an answer", which now reads "a 401, 403 or 503 listing is `failed`";
    - `ListTools` pagination and `MAXPAGES`;
    - trickling headers and body against `LISTSECONDS` and `CALLSECONDS`;
    - SSE that stays open after its message.
  - **Reworked, each test keeping its pin** (no new test methods, no added run time): `Test/Mcp/Attach.cls`, `Proxy.cls`, `ProxyJob.cls` and `Approval.cls`.
    - A count of AI Hub's `tools/list` becomes "no request from client `other`".
    - `source="mcp"` names become offered names.
    - `TestShadow` and its bare-manager `AddServer` become "a built-in's name is refused from the listing and not offered".
    - `TestAddToolFails{InRequest,AtBuild}` become a `ListTools` that fails through a `ZzServers` mode.
    - In `ZzServers`, the Probe modes 1-4 become ListTools modes: delegate, throw, junk word, and `""` with a fixed list. `ZzTurnAdapter` records offered names.
  - **`Test/Bridge/Gate.cls`:** a parity table for the offered form against the `mcp:` form.
  - **`Test/Bridge/Ext.cls`:** the `ListTools` default.
  - **`Test/Bridge/CodeRules.cls`:** admit `McpOffer` only as the scan requires.

**Acceptance Criteria:**
- **The story's AC.** Given a registered server that answers its listing and then stops answering within the same request, when the runner lists its tools (the next request) or the model calls one of them, then:
  - OcuTalon's client does both;
  - each gives up within its bound (`LISTSECONDS` + 1 s, `MCPTIMEOUT`) with no server text;
  - the turn goes on, and a built-in tool called in that request returns at once;
  - the mock logs no request from any client but `iris`.
- **No AI Hub MCP client.** Given any test of `Test.Mcp.*`, when it runs, then the mock logs no request whose `client` is `other`, and no manager's `%Discover()` or `GetToolStatuses()` holds an entry with `source` `mcp` or a `tool_ref`.
- **Governance unchanged.** Given the existing `Test.Bridge.Gate`, `Test.Mcp.Approval`, `Test.Mcp.Proxy`, `Test.Mcp.ProxyJob` and `Test.Mcp.Attach`, when they run (assertions updated only as in the Tasks), then they pass. The gate, classification by fingerprint, holds, replay, the cut and the `MCP` audit entries apply to an offered tool exactly as before.
- **Classifications survive the upgrade.** Given a tool classified at the fingerprint that the attach report recorded before this story, when OcuTalon's listing fingerprints it, then the two are equal and the classification still applies, with no `mcp.toolChanged`.
  - The "before" value is the fingerprint that the baseline code's report records for the mock's `zz_lookup` and `zz_delete_ticket`. Capture it on the baseline before any change, and keep it in the test as a literal. Tests never add an `mcp:` spec to a manager to compute it.
- **The real runner job (Rule 1).** Given the production's runner job (`Test.Mcp.ProxyJob`) and the mock, when a chat turn's model calls an offered read-only tool, then it runs through `call_mcp_tool` with one `called` audit entry, and the mock logs only `iris` requests.
- **No credential leaks.** Given a fixture entry with a `secret://` header, when listings and calls run (OK, refused, timed out), then the mock sees the resolved header (`auth` `matched`). The secret and the mock's URL appear in no log line, report, row, catalog, metadata, step, audit entry or test output.
- **Lead step, before the merge (U7).** Given the spine, when this story merges, then AD-21, AD-10 and AD-31 read as `## Spine amendment` below says.

## Spec Change Log

- 2026-11-13 (runner, Planner ruling H for 22.10): **deferred: owner's decision after the contest.** The AD-21 re-architecture is DECLINED for the contest window (AD-21 stays as it is). This spec is kept unchanged as the proposal for the owner. DW-1228 goes to a test under the current design (Story 22.6); DW-1221 is recorded as a measured known limit in AD-21's S11 residual and in the guide's MCP section (Story 22.6). Do not implement this spec.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: the bridge names no host class. `McpOffer` is the bridge's; the listing comes through `McpServersClass`.
- AD-6: no `%AI` call or I/O in callbacks (`%Discover`, `%Invoke`, the gate). Listing happens while the request composes.
- AD-10: classification, permission, hold, rewrite and cut.
- AD-17: audit.
- AD-19: `secret://`.
- AD-21: amended (below).
- AD-22: the loopback mock.
- AD-25: the online demo.
- AD-29: lanes.
- AD-31: `McpServersClass`.
- AD-8: Decide's 60 s timer.

**Task 0 (measured at planning; lane D warm throwaway `e22s10pw`, build 154, scratch classes `ZzT10.*`; torn down):**
1. `AddTool(<plain %AI.Tool instance>)` calls no `%Discover`. AI Hub calls the provider's `%Discover` once per manager `%Discover()`, once per `GetToolStatuses()`, and once at the first `ExecuteTool`.
2. The catalog keeps `parameters` as given, with keys sorted (`pattern`, `oneOf` and `additionalProperties` kept). It reports `source` `local` and `provider` `unknown`. It honours `requires_auth`, and passes `metadata` through as given, an `origin_class` set by the provider included.
3. `%CanExecute` gets `toolref` = the tool's name, `call` = `{arguments, id, name}` (no `tool_ref`; a spec's own `toolref` field is ignored and connects nothing), and `metadata` = the spec's metadata plus `requires_auth`.
4. A policy that renames the call to another tool runs that tool. The policy runs a second time with the new name, and the first provider's `%Invoke` is not called.
5. Two providers with one name: the first registered wins, and the second shows as `unavailable` ("shadowed"). An offer named `call_mcp_tool` that is registered before `OcuTalon.Tools.McpProxy` shadows the proxy (DW-1228 is real); registered after it, it is shadowed.
6. DW-1221, against a scratch server that sends one header line or body byte a second:
   - `Client.Probe` took 31.1 s and `Client.CallTool` 36.1 s;
   - a single `Read x#32000:3` returned after 31.06 s, because its timeout restarts when a packet arrives;
   - a loop of `Read x#32000:0` and then `Read x#1:<remaining>` stopped at exactly 3.00 s and 4.00 s.

**Decided in-stage:**
1. **Offer by provider.** A bridge-owned plain `%AI.Tool` provider, one per server per request (the `%AI.Agent.SubAgent` precedent), measured in Task 0 (1)-(4). A `%AI.Policy.Discovery` `%Resolve` was not chosen, because it would make a third policy slot carry tools.
2. **Recognised by metadata.** An offered call is recognised by `metadata.origin_class` and `metadata.toolref` (Task 0 (2), (3)). The `mcp:` toolref branch of the gate stays, so its tests and any native form stay governed.
3. **The listing is the probe.** `McpServers.Probe`, `Attach.Probe` and `Client.Probe` are removed: a listing with its own `initialize` within 5 s is a stronger liveness check. The rule "any HTTP status is an answer" no longer holds: a listing needs a result, so a 401 server offers nothing and reads `unavailable`/`failed`.
4. **Bounds.**
   - `LISTSECONDS` 5 covers a whole listing, all pages included. Before, it was 2 s per step and per page, up to about 24 s (DW-1221's occurrence).
   - `CALLSECONDS` 20 is now total; the connection gets 2 s.
   - The worst proxy run is 25 s, inside Decide's 60 s timer. The worst compose is n × 5 s for n failing servers, each of which then rests 60 s.
   - A healthy remote server lists within 5 s (inference).
5. **Own transport.** The transport is OcuTalon's own, over the TCP device, because `%Net.HttpRequest` restarts its timeout on every partial read (irislib L2075-2086, measured in Task 0 (6)). It reuses `%Net.HttpRequest.CheckSSLCN` for the host name, and copies none of its code.
6. **Not offered.** `call_mcp_tool` and the manager's names are refused, and the proxy is registered first (DW-1228, Task 0 (5)). An earlier server's name is left out, as AI Hub's shadowing did before.
7. **Every server recorded.** The build records every server, so a server that was down at the build is listed again by the first request after its rest (DW-1210).
8. **Too many pages.** A `nextCursor` after `MAXPAGES` fails the listing. A partial set reported `attached` would make `RecordAttach` delete the rows of the unlisted tools.
9. **SSE.** An SSE body is read only up to its first complete `id` 1 message, because a Streamable HTTP server may keep the stream open after it.
10. **One listing per request, no cache.** This is as often as AI Hub listed before. The map stays fresh, and the proxy still re-lists before its call.
11. **No instructions note.** Specs carry no `instructions` (AI Hub added a note that the text came from an external server). This adds no model-facing text. The description is the server's own text, as before, and every result still taints (veto item 3).
12. **New tools.** A tool that a server adds after the build is offered from the next request as unclassified (held). It gets its row, and appears in Settings, at the next build, as today.
13. **User-Agent unchanged.** The mock's `client` rule therefore still works.
14. **Fingerprints match.** Task 0 (2): AI Hub's catalog keeps the schema as given, and `ToolFingerprint` sorts keys. 22.3's proxy already compares its own listing's fingerprint with the attach report's, and its tests pass. A schema that AI Hub's catalog rewrote some other way would show as changed once (unclassified, the safe direction) (inference).
15. **No split.** About 8 source files and 12 test classes, against the default of 6. Listing, offering and recognition cannot ship apart: each one alone leaves AI Hub's client in the path. The transport is the AC's "bounded" for a server that trickles. Most test edits are assertion changes.

**DW-1210 and DW-1211 (as the lead asked):**
- DW-1210 is changed by this design (decided 7): a server that was down at the build is retried after its rest.
- DW-1211 is not changed. Reports stay per runner job (22.9 decided 5), because a shared view needs cross-job state. The wrong direction is still the safe one (the row may say `unavailable` while other jobs offer the server).

**Ledger inbox (Rule 17):**
- DW-1221 is addressed by the Client task and the matrix rows "Request, silent or trickling" and "Trickling call".
- DW-1228 is addressed by the Agent and McpOffer tasks and the matrix row "Reserved name".

**Extend, don't copy (Rule 2):**
- `ListTools` and `ListTool` share one page loop, extending 22.3's `ListTool`.
- `Proxy.Target` is extracted from `Run` for `Attach.ListTools`.
- `ReportOf` keeps its role, with the listing as its input.
- `OfferServers` keeps 22.9's rest and its transition reports.
- The offer follows `%AI.Agent.SubAgent`.
- The host-name check is `%Net.HttpRequest.CheckSSLCN`.
- The tests reuse `Test.Mcp.Attach`'s helpers and the Mock.

**Integration ACs (Rule 1):** `McpOffer` and `McpServers.ListTools` are new. Their consumers are:
- the real runner adapter (shadow runner) and the production's runner job (`Test.Mcp.ProxyJob`);
- the gate, `Mcp.Proxy` and `Mcp.Ops.RecordAttach`, through the attach report;
- all against the loopback mock (the ACs above).

**Consumes:**
- 22.9: the rest, the transition reports, `Mcp.Client`.
- 22.3: `call_mcp_tool`, `Proxy.Header`, `ListTool`/`CallTool`, the rewrite.
- 22.8: `SetMcpTools`, `ClassifyMcp`.
- 22.4: `ProxyManager`, held rows.
- 22.2: `RecordAttach`, `ToolFingerprint`, notices.
- 35.1: the report and `McpServersClass`.

**Consumed-by:**
- 22.5/22.11: `PollCall`'s listing stays on `Mcp.Client`, which now has the total deadline.
- 22.6: the docs text this story replaces.

**Contended edits:** none. `Mcp/Ops.cls` is not needed (`RecordAttach` is unchanged). No `Core/*`, `Channel/**`, `Msg/Catalog*`, `Checks/Process.cls`, `GUIDE.md` or `README.md` edit. `Bridge/Adapter/Agent.cls` and `Policy/Gate.cls` are shared in-epic with 22.5, 22.11 and 22.7, which come first.

**Findability, routes, CI:** no UI and no route. `new_units:` none: `Test.Mcp.Offer` joins `shard:lane-a@rest` by its area, with no live unit.

## Spine amendment (for the orchestrator, U7)

This is the amendment the story's second AC asks for. The orchestrator writes it into the spine; this stage does not. The wording is proposed verbatim.

**AD-21:**
- **Binds:** unchanged.
- **Prevents:** append "; an MCP server holding a runner job past its deadline".
- **Rule:**
  - The heading "**MCP servers (step 4): AI Hub lists, OcuTalon calls (S9).**" becomes "**MCP servers (step 4): OcuTalon lists, offers and calls (S9, S19).**". The rest of that bullet is unchanged.
  - **Listing**, replaced: "The runner never adds an MCP server to an AI Hub tool manager, and AI Hub's MCP client is never used. At the build and in each request it asks `McpServersClass.ListTools(server, config)`. OcuTalon lists the server with its own Streamable HTTP client (`OcuTalon.Mcp.Client`: `initialize`, `notifications/initialized` and the `tools/list` pages, within one 5 s deadline, with the entry's credential header resolved in memory). A request offers the listed tools through one `OcuTalon.Bridge.Adapter.McpOffer` per server: a plain `%AI.Tool` provider whose `%Discover()` returns each tool's name, description and input schema (as `parameters`) with `metadata` `{origin_class, toolref}`, and whose `%Invoke` never contacts the server. The proxy toolset is registered before any offer. A tool whose name is a built-in's or `call_mcp_tool` is refused, with admins notified; one named like an earlier server's tool is not offered. Each server's toolref `mcp:remote:@{config:AI.MCP.OcuTalon_<server>}` remains its identity in fingerprints, rows and replays. The model sees the tools natively, so listing never taints a turn."
  - **Measured attach facts (35.1):** keep as written, and append "[AMENDED 2026-11-12, Story 22.10: history; since Story 22.10 no manager holds an `mcp:` spec]".
  - **Transport**, its second sentence becomes: "OcuTalon's client refuses plain HTTP to any other host (`McpOps.AddressAllowed`), verifies the certificate (`OcuTalonClient`, VerifyPeer) and the host name (`%Net.HttpRequest.CheckSSLCN`), follows no redirect, and a certificate it does not trust makes the listing fail (`unavailable`)."
  - **Calling**, its first sentence becomes: "The gate rewrites every allowed MCP call, an offered tool's included, into the governed proxy tool `call_mcp_tool(server, tool, arguments)`."
    - Add: "Each exchange of OcuTalon's client has one total deadline (5 s for a listing, 20 s for `tools/call`, 2 s for the connection), never a per-read one (S19)."
  - **Changes**, its first clause becomes: "a tool the server adds after the runner's build is offered from the next request as unclassified (held for approval), and gets its row, and appears in Settings, when the runner item restarts".
  - **Bounded attach and listing (S8, S10):** append "[AMENDED 2026-11-12, Story 22.10] The probe is the listing: `Probe` is replaced by `ListTools`, a failed listing reports `unavailable` and rests the server 60 s per runner job, and requests list a server that failed at the build after its rest."
  - **The mid-request residual (S11):** replace it with "**Closed by Story 22.10 (S19).** No AI Hub manager holds an MCP server, so a server that stops answering mid-request blocks no native call. OcuTalon's listing and call give up at their total deadlines, measured against a server that answers one byte a second."
  - **S19 (new record):** Task 0 (1)-(6) of this spec, in one sentence each.

**AD-10, consistency:**
- Rule 1: after "An MCP call is recognised first, by a `toolref` starting `mcp:`", add "or, for a tool that OcuTalon's listing offers (Story 22.10), by `metadata.origin_class` `OcuTalon.Bridge.Adapter.McpOffer` with an `mcp:` `metadata.toolref`, which is then its source".
- Rule 1 and "MCP classification by fingerprint": "from `ToolManager.%Discover()`" and "from the serving manager's `%Discover()`" become "from the request's own listing".
- The S14 record: append "[AMENDED 2026-11-12, Story 22.10: AI Hub's client no longer lists; no manager holds an MCP server]".

**AD-31:** `McpServersClass`'s `Probe(server, config) As %String` (default `""`) is replaced by `ListTools(server, config, Output tools As %DynamicArray) As %String`:
- the default is `failed` with no tools;
- each tool is `{name, description, inputSchema}`;
- it is called outside callbacks, at the build and per request.
- OcuTalon's implementation: `OcuTalon.Mcp.Attach.ListTools` over `Mcp.Client.ListTools`.

**Done stories whose specs cite this part of AD-21:** 35.1, 35.2, 22.2, 22.8, 22.9, 22.3, 22.4 and 14.2 (the security overview's MCP section). Ready-for-dev specs that rely on it: 22.5 and 22.7. 22.6 is not yet planned.

## Veto items

1. **Outward requests.** OcuTalon's client now does the listing that AI Hub did: `initialize`, `notifications/initialized` and `tools/list`, with the entry's resolved credential header, to admin-registered servers only. This happens at each build and in each request while a server is registered, within 5 s. It replaces 22.9's unauthenticated probe and AI Hub's own listing; the `User-Agent` is unchanged.
   - Online demo: never sent.
2. **Security posture.** An MCP exchange uses OcuTalon's own HTTP/1.1 client over the TCP device, not `%Net.HttpRequest`. It uses TLS with `OcuTalonClient` (VerifyPeer), SNI and a host-name check (`CheckSSLCN`), follows no redirect, allows plain HTTP to loopback only, and has a total deadline per exchange.
   - Online demo: unused.
3. **What the model sees.** MCP tools are offered from OcuTalon's own listing (the name, the server's description and the schema), without AI Hub's note that the text came from an external server. Results still taint every turn.
   - Online demo: no MCP tools.
4. **Behaviour.**
   - A server's tool named `call_mcp_tool` is refused, and admins get the existing `mcp.toolShadowsBuiltIn`.
   - A listing that needs more than 10 pages, or answers 401/403, leaves the server `unavailable`.
   - Online demo: no change.
5. **Architecture.** The AD-21, AD-10 and AD-31 amendment above (veto 9).
6. Nothing new among: privilege, role, grant, resource, table, column, retention, route, setting or third-party dependency.

## Public text

None new, except Public text 1, which is used only if Story 22.6's docs text on the probe or the residual exists.

| # | Where | Text |
|---|---|---|
| 1 | `docs/` (replaces 22.6's probe and residual sentences) | "OcuTalon lists and calls each MCP server's tools with its own client, and gives up on a server that has not finished answering within 5 seconds for a listing or 20 seconds for a call. A server that fails to answer is left out for a minute, and admins are told that it is unavailable, so a server that stops answering cannot hold up OcuTalon's runners for longer than that." |

Existing text reused: `Gate.FAILED`, 22.3's `MCPTIMEOUT`, `MCPFAILED` and `MCPCHANGED`, `mcp.serverUnavailable` and `mcp.toolShadowsBuiltIn`. The warnings are log lines with no user audience.

## Verification

Each `ci/iris.sh` call carries the lane's variables: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Check `ci/warm.sh status` first.
- Run `OCUTALON_RUN_TAG=e22s10iw ci/warm.sh up` once. Then pass `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s10iw` on each class call.
- Run `ci/warm.sh down` at the end, even after a failure.
- One class per foreground call, with `timeout: 600000`, each about 150 s at most.
- Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call.

**Commands:**
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Client` -- expected: `CLASS … passed`
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Offer` -- expected: passed (under 120 s warm)
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Proxy` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.ProxyJob` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Approval` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Gate` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Ext` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.CodeRules` -- expected: passed
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Loopback`, `OcuTalon.Test.Mcp.Classification`, `OcuTalon.Test.Mcp.Ops`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Bridge.TurnTools`, `OcuTalon.Test.Install.SecurityOverview` -- expected: passed, one per call
- (loop) `ci/iris.sh class OcuTalon.Test.Mcp.Attach` -- expected: passed (alone in its call, about 165 s warm; no slower than before)
- (loop) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-ci-config.sh` -- expected: exit 0

There are no `(once)` lines. CI runs the full suite (`shard:lane-a@rest`, `shard:lane-a@Bridge`, `live:demo-path`), and the lead runs Rule 19's fresh-environment check.

**Shared surfaces:**
- the mock's request log and its new `Trickle`/`Extra` modes;
- the composed manager's tool list (MCP tools now `source` `local` with offer metadata);
- `ZzTurnAdapter`'s recorded names;
- `ZzServers`' modes;
- the `Ext.McpServers` base (`Probe` replaced by `ListTools`);
- the attach reports and `Mcp.Server` rows;
- `Mcp.Client`'s parameters (`PROBESECONDS` renamed).

Search the test trees for each one. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to demonstrate (Rule 19; write a `mutation:` line for each):**

| Mutation | Test that goes red |
| --- | --- |
| `OfferServers` adds the `mcp:` spec instead of the offer | `Test.Mcp.Offer` no-`other`-client test, and the mid-request row |
| The exchange reads `Read x#n:<remaining>` (no drain and wait) | `Test.Mcp.Client` trickle rows |
| `LISTSECONDS` applied per page | `Test.Mcp.Client` slow-pages row |
| The proxy is registered after the offers, and `call_mcp_tool` is not refused | `Test.Mcp.Offer` reserved-name row |
| `Gate.Source` ignores the offer metadata | `Test.Bridge.Gate` parity table, and `Test.Mcp.Offer` request row |
| `McpOffer.%Invoke` calls `Proxy.Call` | `Test.Mcp.Offer` unrewritten row |
| `Attach.ListTools` ignores the demo flag | `Test.Mcp.Offer` demo row |
| The build does not record a server whose listing failed | `Test.Mcp.Offer` down-at-build row |
| `CheckSSLCN` skipped | the Task 0 TLS test (a wrong-host row). If Task 0 found no listener, write no line: the deferred item stands |
| `ReportOf` fingerprints with the server's name instead of its toolref | `Test.Mcp.Offer` classifications-survive row |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
