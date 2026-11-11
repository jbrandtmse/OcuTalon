# Story 22.9, Task 0: an MCP server that accepts the connection and never answers

Measured 2026-11-11 by the plan stage on lane A's warm throwaway (run tag e22s9pw, build 154U, ARM64, IRIS Community licence), never on a slot. Scratch
class `ZzT9.Probe` (removed afterwards, with its globals; the throwaway was torn down): a loopback server on `%IO.ServerSocket` (127.0.0.1 only,
queue size 0, keep-alive -1, as the 35.1 mock) that answers the first N requests like the mock and then accepts each later connection, reads the
request and never answers until it is told to stop; and measurement jobs, each in its own process, timing AI Hub's calls on a bare
`%AI.ToolMgr` with a plain `mcp:remote:http://127.0.0.1:<port>/mcp` spec (no credential). AI Hub's client is `rmcp` over `reqwest`. Anything not
measured is labelled (inference).

## (1) The platform gives no bound

| # | What | Server | Result |
|---|------|--------|--------|
| 1 | `AddTool` | never answers (N 0) | blocked in the native call (process state `ZF`) for **632 s**, until the server closed the connection; then the error `<%AICore>McpError … MCP protocol handshake failed … error sending request for url (…), when send initialize request` (the adapter's `ReasonOf` gives `unreachable`) |
| 2 | `%Discover()` after a good `AddTool` | answers `initialize` and the notification, then never answers | blocked **551 s**, until the server closed; then threw `<%AICore>ToolExecutionFailed: … Failed to list tools from MCP client …` |
| 3 | `ExecuteTool` of a **built-in** tool (`zz_turn_set` of `OcuTalon.Test.Bridge.ZzTurnToolset`) on a manager that also holds an MCP server that stopped answering | as 2 | blocked **300 s**, until the server closed; then the built-in ran and returned its value |
| 4 | `ExecuteTool("zz_none")` (no such tool) on a manager holding an answering MCP server | answers | one `tools/list` to the server, then `ToolNotFound` |

- No timeout of AI Hub or rmcp ended any of the three calls in 5 to 10.5 minutes, far beyond `Decide.#MAXTIMER` (110 s). The client sockets carry
  TCP keep-alive (`ss` showed a keep-alive timer), which a server that is alive but silent answers, so the kernel never ends them either.
- `%AI.ConfigStore.MCPDescriptor` takes no timeout key: its schema is `transport`, `command`, `args`, `env`, `url` and `auth` only
  (`irislib/%AI/ConfigStore/MCPDescriptor.cls` L16-82) and `AllowUnrecognizedDetails` is 0 (L16). `%AI.ToolMgr` has no timeout argument
  (`AddTool` L279, `%Discover` L460, `GetToolStatuses` L492 and `ExecuteTool` L509 are each one `$ZF(-6)` call into the native library).

## (2) What contacts the server, and when

- `AddTool` sends `initialize` and `notifications/initialized` (2 requests) and lists nothing.
- Every `%Discover()`, every `GetToolStatuses()` and every `ExecuteTool` of any tool, built-in or not, sends one `tools/list` to every MCP server
  on that manager. In run 2 an immediate `%Discover()` after `AddTool` made its own `tools/list`, and so did each later one (at +2, +10, +40 and
  +70 s on an answering server): there is no listing cache.
- So a manager that holds a silent server blocks its job at the next listing or tool call, in any request, including a request of kind `tool`
  that runs a built-in (the replay) and a `ToolInventory` request.

## (3) The job cannot be freed from inside IRIS

- `$SYSTEM.Process.Terminate(pid)` of a job blocked in `AddTool` returned 1, and the job was still alive 10 s later (state `ZF`). When the server
  then closed the connection, the job ended 0.5 s later. A job inside the native call ends only when the call returns.

## (4) An ObjectScript probe is bounded

`%Net.HttpRequest` POST of a JSON-RPC `initialize` (no credential) to `/mcp`, `OpenTimeout` 2 and `Timeout` 2:

| Server | Result |
|--------|--------|
| never answers | `ERROR #5922: Timed out waiting for response` after **2.011 s** |
| answers | HTTP 200 after 0.001 s |
| nothing listens (refused) | `ERROR #6059: Unable to open TCP/IP socket` at once |

- An `https://` server needs a client SSL configuration for `%Net.HttpRequest` (`irislib/%Net/HttpRequest.cls` L1662, `HttpSSLNoConfig`):
  OcuTalon's is `OcuTalonClient` (`OcuTalon.Install.Step.SSL`, OS trust store). Whether `OpenTimeout` also bounds the TLS handshake is
  unmeasured (inference: the TLS handshake happens inside the `Open` that the timeout bounds).
- The default User-Agent of `%Net.HttpRequest` is `Mozilla/4.0 (compatible; InterSystems IRIS;)` (`irislib/%Net/HttpRequest.cls` L68).

## (5) Other facts

- The throwaway's Community licence refused a `Job` (`$ZChild` 0 after its 10 s timeout) while about ten scratch jobs were alive, so stuck child
  jobs are not a safe way to bound a call (they cannot be ended, (3), and they use up the process allowance).

## Verdict

The platform gives no bound and a blocked job cannot be interrupted, so the bound must keep AI Hub's native client away from a server that does
not answer: a bounded ObjectScript probe before every `AddTool`, and no MCP server on any manager that a request lists or runs a tool on without
such a probe (the agent's own manager). What no probe can bound is a server that stops answering after its probe passed, during the same
request (the request's `%Discover()`, `Chat`'s listings and each tool call): measured above, that holds the runner job until the server closes
the connection.
