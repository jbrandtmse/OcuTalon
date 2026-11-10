# Story 35.1, Task 0: attaching MCP servers to a tool manager

Measured 2026-11-09 on the lane-B warm throwaway (run tag e35s1iw, build 154U, ARM64), as the container's `irisowner` (roles `%All`), with
scratch classes in the package `ZzT0` that were removed afterwards: a scratch mock MCP server on `%IO.ServerSocket`, a scratch tool and
toolset (`zz_lookup`), an authorization policy that allows every call and records what AI Hub hands it, and a discovery policy. Every
measurement used a bare `%AI.ToolMgr` (no agent, no model). The mock listened on a free port of the container's loopback. The MCP client is
AI Hub's native one (`rmcp 3.2.0`, streamable HTTP). Everything not measured is labelled (inference).

## (1) The wire contract of `AddTool("mcp:remote:<url>")`

One `AddTool`, then `%Discover()`, `GetToolStatuses()` and two `ExecuteTool` calls, against the mock, produced these requests, in order (all
`POST /mcp HTTP/1.1`):

| # | JSON-RPC method | Notes |
|---|-----------------|-------|
| 1 | `initialize` (id 0) | params `clientInfo` `rmcp` `3.2.0`, `protocolVersion` `2025-11-25`, empty `capabilities` |
| 2 | `notifications/initialized` | no id; the mock answers `202` with no body |
| 3 | `tools/list` | made by `AddTool` |
| 4, 5 | `tools/list` | one more for `%Discover()` and one for `GetToolStatuses()` (each call lists again) |
| 6, 7 | `tools/call` | one per `ExecuteTool`; params `name`, `arguments` |

- Headers of every request: `Accept: text/event-stream, application/json`, `Content-Type: application/json`, `Content-Length`, `Host`; from
  request 2 on also `Mcp-Protocol-Version`, the version the mock answered `initialize` with (`2025-03-26`, so the client followed the server's
  version). No `Mcp-Session-Id` was sent; the mock never returned one (a server that returns one gets it echoed back: inference, not measured).
- A plain `Content-Type: application/json` reply is accepted for `initialize`, `tools/list` and `tools/call`; the mock needs no SSE framing.
  The reply to a notification is `202` with an empty body.
- A tool entry of `GetToolStatuses()` / `%Discover()` for an MCP tool has the fields `name`, `description`, `instructions` (the description
  plus a fixed note that the text came from an external server), `parameters`, `source` `mcp`, `provider` (the URL, or the resolved URL for a
  `@{config:}` spec), `requires_auth` true, `metadata`, `stateful` false, `tool_ref` (the spec as given) and `status` `available`.
- `ExecuteTool` of an MCP tool on a manager with no authorization policy fails with `ToolAccessDenied` ("requires authorization
  (requires_auth=true) but no authorization policy is configured"): every MCP tool goes through the gate (OcuTalon's manager always has one).
- `AddTool` of one MCP spec on a new manager took 24 ms the first time; see (6).

## (2) `@{config:AI.MCP.OcuTalon_<name>}` with a `secret://` header

- The entry: `%ConfigStore.Configuration.Create("AI", "MCP", "", "OcuTalon_zzt0", {transport: "remote", url, auth: {type: "header", name:
  "X-Zz-Key", value: "secret://ZzT0Coll.ZzT0Sec#token"}})` after `%ConfigStore.DescriptorManager.RebuildRegistry()`. It was accepted.
- The secret: `%Wallet.Collection.Create("ZzT0Coll", {EditResource: "%DB_%DEFAULT", UseResource: "%DB_%DEFAULT"})`, then
  `%Wallet.KeyValue.Create("ZzT0Coll.ZzT0Sec", {Secret: {token: <random>}, RequireTLS: 0, Usage: "CUSTOM"})`. The value was 24 random
  characters from `$System.Encryption.GenCryptRand`, made in the test's process. Both calls returned OK as `irisowner` with `%All`; no
  product grant is involved, and the test deletes the secret, the collection and the entry itself (`Delete` of each; all three were gone
  afterwards). Read through `%AI.Utils.ConfigStore.Lookup` the entry shows the resolved value (that call resolves secrets), so a test must read
  an entry with `%ConfigStore.Configuration.GetDetails(fqn, .details, 0, 0)` (no secret resolution) when it checks what the entry stores.
- `AddTool("mcp:remote:@{config:AI.MCP.OcuTalon_zzt0}")` returned OK in 23 ms. `%Discover()` listed `zz_delete_ticket` and `zz_lookup` with
  `source` `mcp`; `GetToolStatuses()` gave both `available`, `tool_ref` `mcp:remote:@{config:AI.MCP.OcuTalon_zzt0}` (the unexpanded
  placeholder) and `provider` the resolved URL.
- The mock received the resolved header on every request (initialize, notification, tools/list, tools/call): its check against the value it
  was given matched (the mock records a match flag, never the value).
- Neither `GetToolStatuses()`, `%Discover()` nor the gate's records held the secret value (checked by containment in the same run).
- Verdict: the attach through `@{config:}` works on build 154, and the test can write and remove a wallet secret. No intent gap.

## (3) The server is down

`AddTool("mcp:remote:http://127.0.0.1:<port>/mcp")` with the mock stopped (connection refused):

- The status is an ERROR (`<%AICore>McpError`: "MCP protocol error: Failed to add tool spec ...: MCP protocol handshake failed: ... error
  sending request for url ..."), after 14 ms. It is not an OK status with an `unavailable` entry. `GetToolStatuses()` then holds no entry
  of the server at all (only the other tools of the manager). So the adapter reads an unreachable server from the failed `AddTool` status
  (and the status is never recorded for it: `Attach` records a spec only on OK).
- The error text names the spec's URL. With a `@{config:}` spec and the secret header, the error text holds the RESOLVED spec, including the
  header VALUE (the scratch run confirmed by containment that the random secret is in the status text of a down server). So the status
  text of `AddTool` must never be logged, stored, returned in a reason, put in an assertion message or printed: the attach reports code
  words only (`unreachable`, `failed`, `invalid`) and drops the text. (The scratch run printed that text once to the evidence capture; the
  value was a random throwaway made for the run, it was deleted with the wallet entry in the same run, and the capture file was redacted.)
- An entry that does not exist (`@{config:AI.MCP.OcuTalon_zznone}`) or a config name that is not a valid identifier: `AddTool` returns an
  ERROR `SettingLookupFailed` ("SettingStore lookup failed for @{config:...}"), `GetToolStatuses()` is empty. That is a `failed` attach for
  the adapter. A refused connection is told from a failed lookup by the text only in the adapter's classification (it reads the text
  inside the adapter and never stores it): the words "handshake failed" / "error sending request" / "connect" / "timed out" give
  `unreachable`, anything else `failed`.
- Not measured: a server that accepts the connection and never answers (the time `AddTool` would block).

## (4) Shadowing: an MCP tool with the name of a tool already on the manager

The manager held the scratch toolset's tool `zz_lookup` (source `iris`); the mock listed `zz_lookup` and `zz_delete_ticket`; the mock was
attached after the toolset (the order of `OnAfterAgentInit` and of `BuildTurnManager`).

- `AddTool` returned OK. `%Discover()` listed `zz_delete_ticket` (mcp) and `zz_lookup` (iris) only.
- `GetToolStatuses()` listed three entries: `zz_delete_ticket` available (mcp), `zz_lookup` available (iris), and `zz_lookup` with
  `source` `mcp`, `tool_ref` the MCP spec and `status` `unavailable`, with the `reason` "Tool name 'zz_lookup' is also exposed by another
  provider (...); this registration is shadowed and will never be listed or executed." The reason names the spec, so it is never stored.
- `ExecuteTool("zz_lookup")` ran the built-in (the built-in counter went up, the mock logged no `tools/call`), so the MCP copy never runs
  while the built-in is registered first. `zz_delete_ticket` of the same server stays available.
- A discovery policy (`SetDiscoveryPolicy`, `%Resolve` removing entries with `source` `mcp` by name, with `catalog.%Remove(i)`; `%Clear`
  does not exist on `%DynamicArray`) can also hide an MCP tool from `%Discover()`; `ExecuteTool` of a hidden MCP-only tool then fails with
  `ToolNotFound` and the mock logs no call, and `ExecuteTool` of the shadowed name still runs the built-in. The platform therefore refuses
  the shadowing copy by itself and keeps the server's other tools, and no discovery policy and no refused set at the gate is needed:
  Gate.cls is unchanged.
- Verdict: the platform can refuse one tool and keep the others. The adapter reports a tool as refused when the server's entry in
  `GetToolStatuses()` is not `available` and its name is in the built-in set (the names of `%Discover()` before the first attach).

## (5) What the gate sees

The authorization policy records `%CanExecute(toolref, call, metadata)`:

- an MCP call: `toolref` = `mcp:remote:@{config:AI.MCP.OcuTalon_zzt0}` (the unexpanded placeholder; a plain-URL spec gives the URL), `call` =
  `{arguments, id: "call_id", name, tool_ref: <the same toolref>}`, `metadata` = `{"requires_auth": true}`. There is no `origin_class` for an
  MCP call. No record held the secret.
- the shadowing call (`zz_lookup`): `toolref` = `zz_lookup` (the tool's name), `metadata` = `{ReadOnly: "1", origin_class: "ZzT0.Tool",
  requires_auth: false}`, because the call goes to the built-in. The MCP copy never reaches the gate.
- The gate's existing MCP path (`Source()` = the toolref, `FromExtension`) therefore classifies each MCP tool by (toolref, name) and, with
  no extension that says otherwise, as unclassified.

## (6) The cost of the per-request re-add

`AddTool` of one MCP spec on a new `%AI.ToolMgr`, mock up, 10 runs: median 9.2 ms (min 7.8 ms, max 24.8 ms). One spec costs one
`initialize`, one notification and one `tools/list` (three requests) on the server for every request that composes a turn manager
(`BuildTurnManager`, only for a request that gets turn tools), so a request with turn tools and N servers adds about 10 ms x N (inference
for N > 1, measured for 1).

## (7) The loopback bind

- `%IO.ServerSocket.Open(port, timeout)` with the default `ConnectionQueueSize` (1) and `KeepAliveInterval` (0) IGNORES `LocalInterface`
  when a timeout other than -1 is given: the listener was on 0.0.0.0 (`/proc/net/tcp` showed `00000000:<port>`), because the Open variant
  for those property values has no `/BINDTO` (Open of `irislib/%IO/ServerSocket.cls` L257-L330). With `ConnectionQueueSize = 0` and
  `KeepAliveInterval = -1` the variant with `/BINDTO` is used and the listener showed `0100007F:<port>` (127.0.0.1 only). A raw `Open
  "|TCP|<port>":(:<port>:"SWA-D"::32000:32000:1:/CLOSELISTEN:/TCPNOXY:/BINDTO="127.0.0.1"):5` also binds to 127.0.0.1 only. The mock sets both
  properties, and the pin test checks the effect, not the property.
- Non-loopback IPv4 addresses from `$System.INetInfo.GetListOfConfiguredInterfaces()`: one in the throwaway (`172.22.0.3/16` as `address/prefix`;
  the test strips the `/prefix`; IPv6 entries are skipped).
- Bound to 127.0.0.1: a `%IO.Socket` open to 127.0.0.1:<port> was accepted (0.0 s); a connect to the container's 172.22.0.3:<port> was not
  accepted, and gave up after the 2 s timeout. Unbound (no `LocalInterface`): both were accepted. So the pin test can go red.

## Verdicts of the stop rules

| Rule | Result |
|------|--------|
| `@{config:}` cannot attach on build 154 | Not so: it attaches and the header reaches the server |
| a single shadowing tool cannot be refused while keeping the server's other tools | Not so: the platform shadows it and keeps the others |
| the test cannot write a wallet secret for the `secret://` reference | Not so: `%Wallet.Collection` and `%Wallet.KeyValue` create and delete as `irisowner` |

No intent gap. Facts the design rests on: an unreachable server is an ERROR from `AddTool` whose text can hold the resolved secret; a
shadowed MCP tool is an `unavailable` entry of `GetToolStatuses()` and never runs; the loopback bind needs `ConnectionQueueSize` 0 and
`KeepAliveInterval` -1 on `%IO.ServerSocket`.

## Warm times of the Test.Mcp classes

Measured on the same warm throwaway (run tag e35s1iw, build 154U, ARM64) with `OCUTALON_WARM=1 ci/iris.sh class <Class>`, as the CLASS line reports them:

| Class | Warm time |
|-------|-----------|
| `OcuTalon.Test.Mcp.Attach` | 19.6 s |
| `OcuTalon.Test.Mcp.Tools` | 0.01 s |
| `OcuTalon.Test.Mcp.Loopback` | 3.2 s |

The three classes together take about 23 s warm; on a fresh CI stack the model-mock start-up is not part of them, since the shard starts it once. This is well
under the one minute that the spec's CI note expects of the area in `shards-2` (inference for the CI figure; the warm figures are measured).
