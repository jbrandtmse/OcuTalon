# Story 22.3, Task 0: can the gate reroute a native MCP call into the governed proxy, and can the runner job read the wallet?

Measured 2026-11-12 by the implement stage on lane D's warm throwaway (run tag e22s3iw, build 154U, ARM64), never on a slot. Scratch classes `ZzT3.*`
(a gate policy that records every `%CanExecute` and rewrites the call by mode, a toolset with a `call_mcp_tool` method that records that it ran, and a
subclass of `OcuTalon.Test.Mcp.Attach` that reuses its fixtures: the loopback mock, the wallet secret and the Config Store entry), removed afterwards with
their globals. Each run: a bare `%AI.ToolMgr` that holds the mock's server (`mcp:remote:@{config:AI.MCP.OcuTalon_<name>}`) and the scratch toolset, the
scratch policy as its authorization policy, then `ExecuteTool("zz_lookup", {"id":"1"})`. Anything not measured is labelled (inference).

## (1) The rewrite

| Variant (what the policy does in its first run) | What runs | Second run of the policy | The model's tool result |
|--|--|--|--|
| A. Nothing (record only) | AI Hub's client: the mock logged `tools/list` and `tools/call` for `zz_lookup`, both from `client` other | none | `{"timing":…,"value":{"content":"The mock ran zz_lookup"}}` |
| B. `call.%Set("name","call_mcp_tool")` and `call.%Set("arguments",{server,tool,arguments})` (an object) | **the proxy's method** (`ZzT3.Tools.CallMcpTool` ran once with server, tool and the original arguments); the mock logged **no `tools/call`** (only the `tools/list` that AI Hub sends before every tool call, as 22.9's evidence (2) measured) | yes, once: `toolref` = `call_mcp_tool`; `call` = `{"arguments":{"arguments":{"id":"1"},"server":…,"tool":"zz_lookup"},"id":"call_id","name":"call_mcp_tool"}` (no `tool_ref` member; keys come back sorted); `metadata` = `{"origin_class":"<the toolset's tool class>","requires_auth":false}` | `{"timing":…,"value":"proxy ran zz_lookup"}`, the proxy's own value |
| C. B, and also `call.%Set("toolref","iris:ZzT3.Set")` | as B | as B (the member is not part of the call: it changes nothing) | as B |
| C2. B, and also `call.%Set("tool_ref","iris:ZzT3.Set")` | as B | as B (the second run's call has no `tool_ref` at all: AI Hub finds the tool again by its new name) | as B |
| D. B with the new arguments set as JSON text | as B | as B (AI Hub hands the second run an object) | as B |

- The first run's `call` is `{"arguments":{…},"id":"call_id","name":"zz_lookup","tool_ref":"mcp:remote:@{config:AI.MCP.OcuTalon_<name>}"}` with `arguments` an object, and its
  `metadata` is `{"requires_auth":true}` (no `origin_class`).
- The proxy toolset's schema lists `arguments` as `{"type":"object"}` with its description (a `%DynamicObject` formal argument), `server` and `tool` as strings, all three required.
- The proxy's own tool is a different tool of the manager, so the rewrite needs the toolset registered on the same manager (here `RegisterToolSet`).
- AI Hub's `tools/list` before the call is not avoidable by the rewrite: the manager holds the server for listing (AD-21: "AI Hub lists, OcuTalon calls"; 22.10 moves the listing). The AC's
  "no AI Hub request" therefore means no `tools/call` and no `initialize` from AI Hub's client for the call; the tests count `tools/call` from a client other than `iris`.

## (2) The wallet secret in the runner job

- The production's runner jobs run as user `_Ensemble` with the roles `%All,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,%EnsRole_ProdPrivs_OCUTALON` (ProcessQuery of the live ChatAgent job). The service user
  `OcuTalonService` (login disabled) is the logical user of the gate's `CheckUserPermission`, not the user of a job.
- In a process with the same `%All` role (an `irisowner` session; a role cannot be dropped from `%All`, so the service role alone could not be emulated),
  `%ConfigStore.Configuration.GetDetails(fqn, .details, 0, 1)` (secrets resolved: what AI Hub's own `%AI.Utils.ConfigStore.Lookup` calls) resolved the entry's `auth.value` `secret://…#token` to the wallet value, and
  `%Wallet.KeyValue.GetSecretValue(<collection>.<name>)` returned the same value (the fixture secret has Usage CUSTOM, as 21.4's will). Neither printed the value.
- AI Hub's own attach resolves the same reference inside the runner job (35.1's evidence), through the same `%Wallet` API with the job's roles.
- Not measured: the call executed inside a runner job itself (the unit tests run in a session process). (inference: the same result, since the job holds `%All`.) No grant is added by this story.

## (3) The rule

Variant B makes the proxy run in place of AI Hub's `tools/call`. The gate implements the rewrite with it (name and arguments set, no `toolref` member), and fallback F1 is not used. The second run of the
policy is the proxy call itself: the gate marks the rewrite (like `RagRewrite`) so that the second run reports no second step.

## (4) What the audit policy sees (found while building the step records)

With variant B, a scratch audit policy (`%LogExecution`) got `call` = `{"id":"call_id","name":"zz_lookup","arguments":"{\"id\":\"1\"}"}` (the model's name, the arguments as JSON text, no `tool_ref`) and `metadata` =
`{"origin_class":"<the proxy tool's class>","requires_auth":false}`: the original call with the metadata of the tool that ran. So the step record of a rewritten call carries the tool's own name and
the proxy's class, and the gate has to note the rewrite (Context NoteRerouted) for the record to name the server. The scratch audit class was removed with the others.
