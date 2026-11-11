# Story 22.8, Task 0: the forms of an MCP tool at the gate (DW-174) and the two listings

Measured 2026-11-11 on the lane-A warm throwaway (run tag e22s8iw, build 154U, ARM64), as the container's `irisowner`, with scratch classes in the package
`ZzT8` that were removed afterwards (the classes, the stdio script, the `^IRIS.Temp.ZzT8` nodes and the temporary files; the check after the removal found none).
Every measurement used a bare `%AI.ToolMgr` that held the toolset `OcuTalon.Test.Bridge.StepsTools` (so that the mock's second tool could shadow
`zz_steps_note`), then one MCP spec, then a recording authorization policy (`ZzT8.Rec`) that allows every call and writes what AI Hub hands to
`%CanExecute(toolref, call, metadata)`. The remote and JSON forms pointed at the loopback mock of `OcuTalon.Test.Mcp.Mock` (no key, no real server). The stdio form
ran a 25-line Python 3 script in the container that speaks MCP over newline-delimited JSON (`initialize`, `tools/list`, `tools/call`) and logs each call to a file.
Everything not measured is labelled (inference).

## (1) `%Discover()` and `GetToolStatuses()`

For the remote form (`mcp:remote:<url>`) and the stdio form, each listing holds, for every MCP tool: `tool_ref` (the spec as given), `description` (the server's own),
`parameters` (an object, the server's input schema), `source` `mcp` and `status` `available`.

| Form | `%Discover()` has `tool_ref`, `description`, `parameters` | `GetToolStatuses()` has them | `Context.ToolFingerprint` of one equals that of the other |
|------|------|------|------|
| remote (`mcp:remote:<url>`), two tools | yes | yes | yes, for both tools |
| stdio (`mcp:stdio:python3 <script>`), one tool | yes | yes | yes |

- A tool that a built-in shadows (`zz_steps_note`, listed by the mock and by the stdio server) is in neither `%Discover()` nor as `available` in
  `GetToolStatuses()`, and its copy never ran (the mock logged no `tools/call` for it; the stdio log held only `zz_lookup`).
- Verdict: `%Discover()` has `tool_ref` and agrees with `GetToolStatuses()`, so the turn's map is built from `%Discover()` of the manager that serves the request
  (the fallback to the `available` entries of `GetToolStatuses()` is not needed).

## (2) What `%CanExecute` gets, form by form

| Form | `toolref` | `call` | `metadata` | A shadowing copy ran? |
|------|-----------|--------|------------|-----------------------|
| remote, plain URL | `mcp:remote:http://127.0.0.1:<port>/mcp` | `{"arguments":{...},"id":"call_id","name":"zz_lookup","tool_ref":"<the same toolref>"}` | `{"requires_auth":true}` | no: `zz_steps_note` ran the built-in, the mock got no call for it |
| remote with `@{config:...}` and a `secret://` header | `mcp:remote:@{config:AI.MCP.OcuTalon_<name>}` (the placeholder; measured in Story 35.1, evidence L93-99) | as above | `{"requires_auth":true}` | no (35.1) |
| JSON configuration, as a JSON text or as a `%DynamicObject` (both gave the same) | the configuration text itself, e.g. `{"type":"mcp:remote","url":"http://127.0.0.1:<port>/mcp"}` | `tool_ref` is that text too | `{"requires_auth":true}` | no |
| stdio | `mcp:stdio:python3 <script>` | `tool_ref` is that text | `{"requires_auth":false}` | no: `zz_steps_note` ran the built-in |

- No MCP form carries an `origin_class` in its metadata. The built-in tool that shadows an MCP name arrives with `toolref` = its name and its own `origin_class`,
  as 35.1 measured.
- The JSON configuration form needs a `type` of `mcp:remote` and a top-level `url` (the shapes `{"type":"mcp:remote","config":{"url":...}}` and `{"type":"mcp","config":...}`
  and a `type` that holds the URL were refused by AI Hub: "Missing required field: url", "Unknown MCP type"). A configuration with both `config.url` and `url` also attaches.
  The `@{config:}` placeholder in a JSON configuration was not tried (inference: it resolves as in the string form).

## (3) The gate rule and its result

The rule: if a form reaches `%CanExecute` for an MCP tool with a `toolref` that does not start `mcp:`, extend `Gate.Source` to recognise it by the measured marker,
before `origin_class`.

- Remote (plain URL and `@{config:}`) and stdio start `mcp:`: recognised as before.
- The JSON configuration form does not start `mcp:`, so `Gate.IsMcp` (which `Source`, `RagCall`, `ClassificationOf` and `MissingPrivilege` use) also recognises a
  toolref that is a JSON object whose `type` is a string starting `mcp:` (any letter case). `Source` then returns the toolref, before `origin_class`. The gate's tests
  pin it: `Test.Bridge.Gate` `TestMcpJsonConfiguration`.
- OcuTalon's own class registers only `mcp:remote:@{config:AI.MCP.OcuTalon_<name>}` of a name with an `Mcp.Server` row, so the JSON form and the stdio form are both
  denied with `UNREGISTERED`. OcuTalon attaches no JSON-configured or stdio MCP tool (the adapter refuses the `IrisTools` and `AdditionalTools` settings, and the
  `McpServersClass` attaches `mcp:remote:@{config:...}` only), so these forms are measured here for the gate's sake and are not reachable today.
- Unmeasured: a stdio server that holds a secret in its command line (inference: the command line is the toolref, so it would be redacted and cut like any source in a
  warning, and the gate denies the call before it uses the toolref anywhere else).
