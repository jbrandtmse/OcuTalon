# Story 28.3 Task 0: `%AI.MCP.Service` and `iris-mcp-server` on build 154

Measured 2026-11-16, 19:00 to 19:11 UTC, by the plan stage on a lane-C warm throwaway (`ci/warm.sh up`, tag `e28s3pw`, torn down after; base image `ocutalon-iris-base:2026.3.0AI.154.0`, ARM developer machine). Scratch probe classes `ZzT0.*` (a `%AI.MCP.Service` subclass with `RESOURCE = "ZzT0_MCP"`, a plain subclass with no `RESOURCE`, one `%AI.ToolSet` with five probe tools, a `%CSP.REST` probe and an HTTP helper) were loaded into the throwaway only. Fixture users held these roles: `ZzT0Role` (`ZzT0_MCP:U`, `%DB_OCUTALON_CODE:R`, `%DB_OCUTALON_DATA:R`, `%DB_OCUTALON_PRIVATE:R`), `ZzT0NoPriv` (the same without the private database), `ZzT0NoDb` (`ZzT0_MCP:U` only), `OcuTalonUser` alone, and `%All`. Each web application had password authentication only (`AutheEnabled` 32), namespace OCUTALON, no application roles and no sign-in group. No password or key is recorded here.

## 1. Direct HTTP to the web server (`%Net.HttpRequest` to 127.0.0.1:52773 inside the container)

| Caller | `GET <app>/v1/services` |
| --- | --- |
| no `Authorization` header | 401, `{"error":"Unauthorized","code":"UNAUTHORIZED","message":"Authentication required."}`, header `X-AICORE-MCP-SERVICE: <class>` |
| wrong password | 401, the same body |
| user holding `OcuTalonUser` only | 403, empty body, no identity header |
| user holding the resource (with or without database grants) | 502, `{"error":"Bad Gateway","code":"GATEWAY_REQUIRED"}` |
| the same with `X-IRIS-MCP-Server: 1` added | 502 `GATEWAY_REQUIRED` (unchanged) |
| `GET <app>/v1/health`, user holding the resource | 502 `GATEWAY_REQUIRED` |

So IRIS itself refuses anonymous callers and wrong passwords (401), a user without Use on the service's resource (403), and every authenticated request that does not come through `iris-mcp-server`'s own connection (502 `GATEWAY_REQUIRED`): the web server never serves a tool directly. A failed sign-in writes an IRIS `LoginFailure` audit event named `<app> login failure`.

## 2. What a tool needs, and what it can do, as a role-only user

Measured through a `%CSP.REST` probe application (password only, no application roles) whose routes call the same probe tool methods, because the service itself answers 502 on the web path (section 1).

| Probe | `ZzT0Role` (code, data and private R) | `ZzT0NoPriv` (no private R) | `ZzT0NoDb` (no database) |
| --- | --- | --- | --- |
| `$Username`, `$Roles` | the caller and its role only | the caller | 403 before any code |
| `OcuTalon.Bridge.Context.Active()` | 0 | 0 | - |
| session lookup `SELECT TOP 1 Ref FROM OcuTalon_Data.Session WHERE IrisUser = ?` prepared without the privilege check | SQLCODE 0, the caller's own Ref | SQLCODE -400 (the private database) | - |
| `Tools.WatchAnswers.CheckResults(ref)`, `Data.Ownership.RecentIncidents(ref)`, `Tools.WatchAnswers.WatchNames(ref)` | OK | - | - |
| `Tools.CommandCall.TimeLabel`, `Data.Time.Zone`, `Watch.Reader.OnlineDemo`, `Data.Public.Settings.Get("onlineDemo")` | OK | OK | - |
| `Bridge.Audit.Record("MCP", {change: called, ...})` | OK; the entry is in `%SYS.Audit` with `Username` = the caller | OK | - |
| `Set ^OcuTalonP.ZzT0Probe = ...` | `<PROTECT>` on the private database | `<PROTECT>` | - |
| `Tools.CommandCall.Session()` and `Run(ListReminders)` | both answer NOSESSION; nothing is submitted | the same | - |

So a tool reached as a role holder runs as that IRIS user, with no bridge context, reads its own session's rows through the ownership API with read grants alone, can write its IRIS audit entry, cannot write any OcuTalon database, and cannot submit a command. Without R on `%DB_OCUTALON_PRIVATE` the session lookup fails; without R on the code database the request is refused (403).

## 3. `iris-mcp-server` in the image

- It ships in the base image: `/usr/irissys/bin/iris-mcp-server`, version `2.0.0` (`--version`), dated 2026-09-24. OcuTalon's repository ships and configures none (no compose service, no config file, no document names it outside the planning artifacts).
- `run --help`: `--status-tool [true|false]` (default enabled; it is a command-line flag, not a TOML key: `[features] status_tool` is refused as an unknown field), `--iris-host`, `--iris-port` (superserver, default 1972), `--iris-endpoint` (repeatable), `--monitor-ipc`.
- TOML keys measured by the parser's own errors: `[[iris]]` with `name` and `endpoints` (required; each `{ path, username, password, bearer }`, where `username`, `password` and `bearer` are the endpoint credentials that must never be set), `[iris.server]` with `host`, `port`, `username`, `password` (both required: "server.password is required"); `[features]` accepts `smart_discovery`, `telemetry`, `vault`, `monitor_ipc`, `force_stateless_via_ws`, `allow_remote_static_tools`, `remote_static_tools_token`; `[[mcp]]` with `transport`, `host`, `port` and `allow_anonymous` (and, from the binary's strings, `allowed_hosts`, `allowed_origins`, `forward_headers`, `max_connections`).
- The bridge login (`[iris.server] username`) connects as a user with no roles at all to the service `%Service_MCPGateway` (enabled, password, resource public U): "Connected to IRIS at 127.0.0.1:1972 with pool size 10". A wrong bridge password is an IRIS `LoginFailure` "%Service_MCPGateway login failure".
- The password is not taken from the environment: `env://NAME`, `env:NAME`, `${NAME}`, `secret://env/NAME` and an unknown scheme `foo://X` are all sent as literal text (login failure each time), a table value is refused ("expected a string"), and `password_env` is an unknown field. The log says "Secret manager: environment variable provider active", but no measured field resolves through it. (inference) a password "from the environment" therefore means writing the config file from an environment variable when the gateway starts.
- With `allow_anonymous = false` on the `[[mcp]]` listener (HTTP, 127.0.0.1): an anonymous client's `initialize` and `tools/list` succeed (the list is empty) and its `tools/call` returns an error result; IRIS answered the gateway's discovery 401.
- With a client `Authorization: Basic` header of a user holding the resource, or of a `%All` user, against both the `RESOURCE` subclass and a plain subclass with no `RESOURCE`, at `/mcp/<name>` or `/<name>/mcp`: discovery fails every time with `[no-identity] /mcp/<name>/v1/services did not identify itself` and "failed identity checking -- refusing to trust its tool catalog (verify this endpoint is configured as an IRIS MCP Service)". `tools/list` is empty and `tools/call` returns "Service unavailable". No IRIS error, `LoginFailure` or `^ERRORS` entry was written. The gateway names discovered tools `<service>_<tool>` (its `instructions`).
- Omitting `endpoints` (auto-discovery) is refused: "missing field `endpoints`".

**Not resolved:** no tool of a `%AI.MCP.Service` subclass could be listed or called through `iris-mcp-server` 2.0.0 on this build, so no successful MCP call exists to build a test on. (inference) the identity header that the service stamps on its answers (seen on the direct web path in section 1) does not reach the gateway over its own IRIS connection; whether a setting, another build, or an InterSystems fix is needed is unknown. Spike S10 recorded a pass at architecture time; this measurement does not reproduce it.
