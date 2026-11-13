# Story 22.4, Task 0: the replay of an approved MCP call (measured 2026-11-12)

Measured on the lane D warm throwaway (tag e22s4iw), with scratch test classes `OcuTalon.Test.Mcp.ZzT4Task0` and `ZzT4Recorder` (removed afterwards), the loopback MCP mock
(server `zzmcp`, header-checked wallet credential) and the Epic 22 build of this worktree. The scratch built the replay's manager the way `Adapter.Agent.ProxyManager` does: a new
`%AI.ToolMgr` that holds only `OcuTalon.Tools.McpProxy`, a recording authorization policy and `Policy.StepAudit`; a context of kind `tool` with the grant of an executing
`tool_call` row (`Context.Grant`); then `ExecuteTool("call_mcp_tool", {server, tool, arguments})`.

## 1. The gate is reached, with what it gets

`ExecuteTool("call_mcp_tool", ...)` on a manager that holds only the proxy toolset reaches the authorization policy once per call (one `%CanExecute`; no second pass, because the
replay does not change the call). It gets:

- `toolref`: `call_mcp_tool` (the tool's own name; the proxy has no MCP toolref, and `Gate.Source` takes `metadata.origin_class`).
- `call`: `{"arguments": {"arguments": {"id": "1"}, "server": "zzmcp", "tool": "zz_lookup"}, "id": "call_id", "name": "call_mcp_tool"}`.
- `metadata`: `{"origin_class": "OcuTalon.Tools.McpCall", "requires_auth": false}`.

So the source of the replay's call is the proxy's class (not empty), the call is a proxy call (`IsProxyCall`), and the grant's toolref is not on the call: the gate takes it from the
grant (`GrantSource`) when `ServerOf` names the call's server. The step audit runs: one tool step, status `ok`, label `Running zz_lookup on zzmcp` (the label comes from the approved
node, as the replay has no map), inputs `{"server","tool"}` only. The mock saw `initialize`, `notifications/initialized`, `tools/list`, `tools/call` all from client `iris` (matched
header) and nothing from AI Hub's client.

## 2. A refusal by the proxy

When the proxy refuses (the mock changed the tool's description after the hold), `ExecuteTool` neither throws nor returns an error status. It returns a normal answer object whose
`value` is the refusal sentence (`this MCP tool changed since it was classified, so nothing was run; an admin must classify it again.`), the same shape as a result. The step is
recorded `ok`. So a result cannot be told from a refusal by the answer; `Context.ReplayRefusal()` is what tells them apart (it gave `changed`), and the replay reads the
answer's value as FailureText only when a refusal word was noted. The mock logged `initialize`, the notification and `tools/list` and no `tools/call`.

## 3. Property 26 and existing rows

Adding `Property ToolFingerprint` (storage value 26 appended) and compiling keeps rows written in the 25-field layout readable: a row written as the 25-element `$ListBuild` of the
old layout (class slot empty) opened, kept its Ref, Kind and Runner, and `ToolFingerprint` read `""`.
