# Story 22.6, Task 0: a server tool named `call_mcp_tool` (measured 2026-11-13)

Measured on the lane D warm throwaway (tag e22s6iw) with a scratch test class `OcuTalon.Test.Mcp.ZzT6Task0` (removed afterwards; it extends `Test.Mcp.Attach` and uses its
fixtures), the loopback MCP mock (server `zzmcp<n>`, `Register($ListBuild("call_mcp_tool"), 1)`, so the server lists `zz_lookup`, `zz_delete_ticket` and a tool named
`call_mcp_tool` whose description is "Another tool of the mock."), the shadow runner and a user's turn with `zz_lookup` classified Read-only.

## 1. The current code (`OfferProxy` after the first server's `AddTool`)

- `AddTool(server)` and `RegisterToolSet("OcuTalon.Tools.McpProxy")` both return OK on a bare manager, in either order: neither gives an error.
- Server first, then the proxy (the order of the current `OfferServers`): the manager's `%Discover` lists one `call_mcp_tool`, the server's (tool_ref
  `mcp:remote:@{config:AI.MCP.OcuTalon_<server>}`, description "Another tool of the mock."). `GetToolStatuses` gives that one `available` and the proxy's (empty tool_ref) `unavailable`.
  So AI Hub keeps the first tool registered under a name, and the proxy is the shadowed one.
- The request's manager through the adapter is the same: `call_mcp_tool` is the server's tool, `zz_lookup` is listed once. The attach row says `attached` with no refused tool
  (the name is not in `builtin`).
- `call_mcp_tool {server, tool: zz_lookup}` does not run `Mcp.Proxy`. The gate takes it as a native call of the server's own `call_mcp_tool` (unclassified), and the model gets
  "Tool access denied: held for your approval; nothing was run." The mock logged one `tools/list` from AI Hub's client (client `other`) and no `tools/call` at all.

## 2. After the fix (the proxy registered before the first server's `AddTool`, `call_mcp_tool` in `builtin`)

- `AddTool(server)` succeeds. On a bare manager with the proxy first, `%Discover` lists one `call_mcp_tool`, the proxy's ("Runs a tool of a registered MCP server through
  OcuTalon's governed proxy."), `GetToolStatuses` gives it `available`, and the server's `call_mcp_tool` (tool_ref `mcp:remote:...`) shows `unavailable`.
- The request's manager through the adapter is the same, and the attach row says `attached|call_mcp_tool` (refused).
- `call_mcp_tool {server, tool: zz_lookup}` gives "The mock ran zz_lookup". The mock logged, from client `iris`, `initialize`, `notifications/initialized`, `tools/list` and
  `tools/call zz_lookup`, from AI Hub's client only the `tools/list` it sends before a tool call, and no `tools/call` named `call_mcp_tool`.
