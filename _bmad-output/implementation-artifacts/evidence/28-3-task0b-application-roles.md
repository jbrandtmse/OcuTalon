# Story 28.3 Task 0b: application roles on `/mcp/ocutalon` (Planner ruling G3)

Measured 2026-11-16, 19:35 to 19:55 UTC, by the Task 0b stage on a lane-C warm throwaway (`ci/warm.sh up`, tag `e28s3tbw`, torn down after; base image `ocutalon-iris-base:2026.3.0AI.154.0`, `$ZV` "IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U)", ARM developer machine; worktree head `475436019`). Slot C was not used. Nothing was added under `src/`: the scratch classes were loaded into the throwaway only (`docker cp`, then `$SYSTEM.OBJ.LoadDir`). No password or key is recorded here; the fixture passwords were invented for the throwaway and died with it.

**Verdict: `application_roles_work`.** IRIS adds the application role only after the caller has signed in, the service's own resource check still refuses every caller without U on `OcuTalon_MCPServer`, and a user whose only role holds just `OcuTalon_MCPServer:U` runs the service code with the application role, reads its own session through the ownership API, writes its audit entry and cannot write. Outside `/mcp/ocutalon` the same user reads none of the three databases.

## Method

Security objects created in `%SYS` (all scratch, throwaway only):

| Object | Definition |
| --- | --- |
| resource `OcuTalon_MCPServer` | no public permission |
| role `OcuTalonMCPApp` (application role, granted to no user) | `%DB_OCUTALON_CODE:R`, `%DB_OCUTALON_DATA:R`, `%DB_OCUTALON_PRIVATE:R` |
| role `OcuTalonMCPClient` | `OcuTalon_MCPServer:U` only |
| role `ZzT0bReads` | the three database R grants, not the resource |
| user `zzt0bplain` | `OcuTalonUser` only |
| user `zzt0bdbonly` | `ZzT0bReads` only |
| user `zzt0bclient` | `OcuTalonMCPClient` only |
| web application `/mcp/ocutalon` | the spec's `ServiceApp()` properties (namespace OCUTALON, `Enabled` 1, `AutheEnabled` 32, `GroupById` "", `SessionScope` 2, `Timeout` 900, `CookiePath` "/mcp/ocutalon/", `ServeFiles` 0, ...) except `DispatchClass` `ZzT0b.Service` and `MatchRoles` `:OcuTalonMCPApp` (the application-role form: no match role, target role added to every user in the application) |
| web application `/zzt0b/probe` | password only, namespace OCUTALON, dispatch `ZzT0b.Rest`, no application roles (the "another web application" control) |

Scratch classes (namespace OCUTALON):

- `ZzT0b.Service` extends `%AI.MCP.Service`, `RESOURCE = "OcuTalon_MCPServer"`, `SPECIFICATION = "OcuTalon.Tools.Watch"` (any existing toolset; a subclass with no specification does not compile: `ERROR #644: Parameter 'SPECIFICATION' invalid`). It overrides `AccessCheck` (the `%CSP.REST` gate, which runs before `OnPreDispatch`; not `Final`): it records `$Username` and `$Roles`, calls `##super` (the platform's `%IsAuthorized` resource check), records the outcome, and when authorized runs the probe below. `OnAuthenticate` also records a probe if it is ever reached.
- `ZzT0b.Probe.Run(where)` records `$Username`, `$Roles` and `$Namespace`, then each step in its own `Try` (result "ok ..." or "error <name> ..."): `Data.Public.Settings.Get("onlineDemo")`; the caller's session found as the spec's `OwnerOf` does (`SELECT TOP 1 ID, Ref FROM OcuTalon_Data.Session WHERE IrisUser = ? ORDER BY ID`, `%Prepare(sql, 0)`, never creating); `Data.Ownership.Checks(ref)` (with each row's Ref and SessionRef), `Data.Ownership.RecentIncidents(ref, 5)`, `Tools.WatchAnswers.CheckResults(ref)`; `Bridge.Audit.Record("MCP", {change: called, server: zzt0b, tool: zz_probe, outcome: ok, irisUser, sessionRef, channel: web})`; `Set` on a global in each database (`^OcuTalonP.ZzT0bProbe` private, `^OcuTalon.ZzT0bProbe` data, `^|"^^<code dir>"|ZzT0bProbe` code); a changed `BackgroundCheck` row `%Save()`; and `SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck` with the privilege check. It stores its JSON in `^IRIS.TempZzT0b` (IRISTEMP, public RW), read back by the superuser after each call.
- `ZzT0b.Rest` (`%CSP.REST`, route `GET /probe`) runs the same probe in `/zzt0b/probe`.

Data: as the superuser, `Data.Session.ForUser` made one session row for each fixture user (zzt0bclient's is ID 1), and one `BackgroundCheck` row was saved for zzt0bclient's session and one for zzt0bplain's.

Calls: `%Net.HttpRequest` from an `iris session` inside the container to `127.0.0.1:52773`, each caller with `GET /mcp/ocutalon/v1/services` and `POST /mcp/ocutalon/v1/tool_call` (body `{"tool":"check_status","args":{}}`), `^IRIS.TempZzT0b` cleared before each call. Outside the application: `$SYSTEM.Security.Login(user, password)` in an `iris session` (the terminal path), then reads by extended reference to each database directory and through the namespace.

## 1. Refusals (application role set)

| Caller | `GET .../v1/services` | `POST .../v1/tool_call` | What the hook saw |
| --- | --- | --- | --- |
| no `Authorization` | 401 `{"error":"Unauthorized","code":"UNAUTHORIZED","message":"Authentication required."}`, header `X-AICORE-MCP-SERVICE: ZzT0b.Service` | 401, the same | nothing: `AccessCheck` never ran |
| zzt0bclient, wrong password | 401, the same body | 401 | nothing (IRIS `LoginFailure` "/mcp/ocutalon login failure", "ERROR #952: Invalid password") |
| zzt0bplain (`OcuTalonUser` only) | 403, empty body, no identity header | 403 | `$Roles` "OcuTalonUser,OcuTalonMCPApp" before the check; `authorized` 0 after |
| zzt0bdbonly (three database R, no resource) | 403, empty body | 403 | `$Roles` "OcuTalonMCPApp,ZzT0bReads"; `authorized` 0 |
| zzt0bclient (`OcuTalonMCPClient`) | 502 `{"error":"Bad Gateway","code":"GATEWAY_REQUIRED"}`, identity header | 502, the same | `$Roles` "OcuTalonMCPApp,OcuTalonMCPClient"; `authorized` 1 |

The same ten calls repeated after the extra check below gave the same codes.

So the order is: IRIS password sign-in (a failure is 401 before any application code runs), then IRIS adds the application role, then the service's resource check (`AccessCheck` / `%IsAuthorized`), which looks only at U on `OcuTalon_MCPServer` and refuses everything else with 403, whatever the database grants. The application role holds no U on the resource, so it never admits anyone. Each 403 is decided by the service's code: the request runs with the application role up to that check, and only `AccessCheck` runs (no route, no tool).

Extra check, not the shipped configuration: with `AutheEnabled` 96 (password plus unauthenticated) for a moment, an anonymous caller ran as `UnknownUser` with `$Roles` "OcuTalonMCPApp" and still got 403 on both calls (`authorized` 0). Even with unauthenticated access turned on by mistake, the resource check refuses anonymous callers. `AutheEnabled` was then set back to 32.

`OnAuthenticate` was never reached: the 502 comes first, as in Task 0.

## 2. Inside `/mcp/ocutalon` as the U-only user (zzt0bclient)

Recorded by the `AccessCheck` override after the platform check passed, for both the GET and the POST (identical):

| Step | Result |
| --- | --- |
| `$Username` / `$Roles` / `$Namespace` | zzt0bclient / `OcuTalonMCPApp,OcuTalonMCPClient` / OCUTALON |
| `Data.Public.Settings.Get("onlineDemo")` | ok, 0 |
| `OwnerOf` lookup (private database) | ok, ID 1 and zzt0bclient's own Ref |
| `Data.Ownership.Checks(ref)` | ok, 1 row: zzt0bclient's own check (zzt0bplain's row not returned) |
| `Data.Ownership.RecentIncidents(ref, 5)` | ok, 0 rows (none made) |
| `Tools.WatchAnswers.CheckResults(ref)` | ok, 1 result |
| `Bridge.Audit.Record("MCP", ...)` | ok. In `%SYS.Audit`: `OcuTalon/MCP/MCP`, Username zzt0bclient, Roles "OcuTalonMCPApp,OcuTalonMCPClient", "MCP tool zz_probe of zzt0b called: ok" |
| `Set ^OcuTalonP.ZzT0bProbe` | `<PROTECT> ^OcuTalonP.ZzT0bProbe,/durable/iris/mgr/ocutalon_private/` |
| `Set ^OcuTalon.ZzT0bProbe` | `<PROTECT> ... /ocutalon_data/` |
| `Set` in the code database | `<PROTECT> ^ZzT0bProbe,/durable/iris/mgr/ocutalon_code/` |
| changed `BackgroundCheck` row `%Save()` | error status `<PROTECT>%SaveData+51^OcuTalon.Data.BackgroundCheck.1 ^OcuTalonP.CheckD(1)` |
| SQL `SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck` with the privilege check | SQLCODE -99 "User zzt0bclient is not privileged for the operation" |
| HTTP answer | 502 `GATEWAY_REQUIRED` |

Control (application role removed, `MatchRoles` "" for a moment, then restored): zzt0bclient got **500** `<PROTECT>^%CSP.REST.1 ^|^^/durable/iris/mgr/ocutalon_code/|ZzT0b.Service.1`. Without the application role, the U-only user cannot even load a service class that has its own code in the OcuTalon code database. The application role is what carries the reads.

What could not be observed: no tool method runs on the direct web path (502 `GATEWAY_REQUIRED` from the final `OnPreDispatch`, after `AccessCheck`), and `iris-mcp-server` 2.0.0 cannot list or call tools on this build (Task 0). The probe therefore ran in `AccessCheck`, in the same request and process a tool call would use, after the platform's resource check passed. (inference) A tool reached through `iris-mcp-server` runs with the same `$Roles`, because the gateway reaches the service through the web application (`%AI.MCP.Service`'s own documentation: "accessed by iris-mcp-server via wgproto's HTTP transport", and the CSP dispatcher "importing the security context before Page dispatch"). Story 28.5 should record `$Roles` inside a served call once the gateway works.

## 3. Outside `/mcp/ocutalon` as the U-only user

| Path | zzt0bclient (`OcuTalon_MCPServer:U` only) | Control: zzt0bdbonly (three database R) |
| --- | --- | --- |
| terminal path (`$SYSTEM.Security.Login`), `$Roles` | `OcuTalonMCPClient` | `ZzT0bReads` |
| read `^oddDEF` in the code database (extended reference to the directory) | `<PROTECT> ^oddDEF,/durable/iris/mgr/ocutalon_code/` | `$Data` 11 |
| read `^DeepSee.FolderD` in the data database | `<PROTECT> ... /ocutalon_data/` | 11 |
| read `^OcuTalonP.SessionD` in the private database | `<PROTECT> ... /ocutalon_private/` | 11 |
| read `^|"OCUTALON"|OcuTalonP.SessionD(1)` (through the namespace) | `<PROTECT> ... /ocutalon_private/` | 1 |
| `ZN "OCUTALON"` | `<PROTECT> /durable/iris/mgr/ocutalon_data/` | ok |
| `Data.Public.Settings.Get`, `ZzT0b.Probe.OwnerOf` | `<PROTECT>` each | ok, its own session |
| read `^|"OCUTALON"|OcuTalonPublic` (the public database) | `$Data` 10 (that database is public by design, unchanged) | 10 |
| another web application, `GET /zzt0b/probe/probe` (no application roles) | 403 before any code (nothing recorded) | 200; the probe reads its own session, every write `<PROTECT>` |
| OcuTalon's REST API, `GET /ocutalon/api/v1/state` | 403 `{"error":{"code":"no_role",...}}` from `Web.Api`'s own guard | - |

So outside `/mcp/ocutalon` the role reads none of the three databases.

Context for the security text, not caused by this design: OcuTalon's existing applications `/ocutalon` and `/ocutalon/api` already use application roles (`:%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE`, the databases' default roles) for every signed-in IRIS user, and their code refuses users without `OcuTalonUser` or `OcuTalonViewer`. The MCP application role must not reuse those default `%DB_` roles, because they grant RW and would remove the `<PROTECT>` on writes measured above. It has to be its own R-only role.

## 4. Verdict and what 28.3 changes

**`application_roles_work`.** For the build:

- G3: `OcuTalonMCPClient` holds exactly `OcuTalon_MCPServer:U`, with no database grant and no SQL privilege.
- G1: `/mcp/ocutalon` gets `MatchRoles` `:OcuTalonMCPApp`. The new role `OcuTalonMCPApp` holds exactly R on `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA` and `%DB_OCUTALON_PRIVATE`, no U on `OcuTalon_MCPServer`, no W and no SQL privilege. It is granted to no user and not created on the online demo.
- Order constraint (measured): `Security.Applications` refuses an application whose `MatchRoles` names a role that does not exist ("ERROR #879: Target role ZzT0bNoSuchRole does not exist.", nothing created). So the application role must exist before the Mcp step creates or modifies `/mcp/ocutalon`. Either the Mcp step creates `OcuTalonMCPApp` itself, or the application is applied after `Roles`. The plan's order (`Mcp` before `Roles`) cannot reference a role that `Roles` composes later.
- Suggested pins (inference): a mutation that gives `OcuTalonMCPApp` U on `OcuTalon_MCPServer` turns the `OcuTalonUser`-only fixture's 403 into 502. A mutation that drops `MatchRoles` turns the role holder's 502 into 500 `<PROTECT>`. A mutation that uses the RW `%DB_OCUTALON_*` roles as the application roles lets the in-request write succeed.

## 5. Draft P8 (rewritten, pending the Planner; PUBLIC TEXT)

"OcuTalon's MCP server, `OcuTalon.Mcp.Service` at `/mcp/ocutalon` (password sign-in), offers only the read-only tools above. A user needs the role `OcuTalonMCPClient`, which holds only U on `OcuTalon_MCPServer`. While a request runs in `/mcp/ocutalon`, IRIS adds the application role `OcuTalonMCPApp`, which no user holds and which gives R on OcuTalon's code, data and private databases, with no write and no SQL privilege. Outside that application the role reads none of OcuTalon's databases. Each tool runs as that user, reads only that user's own OcuTalon session and writes an `MCP` audit entry. On the online demo the application, the resource and the roles don't exist."

## Teardown

`ci/warm.sh down` with tag `e28s3tbw` removed the stack, so every scratch object above went with it. No class was added under `src/`.
