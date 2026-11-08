# Story 0.16: the S11 Embedded Python callback crash, re-verified with a minimal reproduction

- **Date:** 2026-11-07, 21:30 to 21:42 UTC. Requested by the Contest Planner (about 21:10Z). Evidence only: no product code, no test suite and no public text changed. Nothing was filed anywhere; the Planner drafts any report and the owner posts it.
- **Verdict:** **REPRODUCED on both builds, 9 of 9 crossing runs died, 6 of 6 one-sided runs survived, per build.** One process that runs embedded Python both outside and inside an AI Hub tool callback (`%AI.ToolMgr.ExecuteTool`) is killed with signal 11, in either direction, at the first call that crosses. The trigger is not specific to any module. Even `##class(%SYS.Python).Import("json")` outside, followed by a trivial `[Language = python]` method inside a tool, crashes. Build 109 behaves exactly like build 154. S11's rule (in one process, Python runs only inside callbacks or only outside them) still holds.
- **DW-792:** the keyword argument **does arrive** when it is passed in the documented form, a `%DynamicObject` as the last argument with `args...`. The form 19.2 used, a local array with string subscripts passed as `kw...`, is silently ignored. So DW-792's premise ("`%SYS.Python` passes no keyword argument on build 154") is wrong. The `kw(...)...` form was the problem, not `%SYS.Python`. It is the same on build 109.

## Targets

| | Build 154 | Build 109 |
| --- | --- | --- |
| `$ZV` | `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:05:18 EDT` | `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2027.1.0AI (Build 109U) Fri Oct 30 2026 16:32:20 EDT` |
| Python (`%SYS.Python.GetPythonVersion()`) | `3.12.3 (main, Aug 31 2026, 10:18:26) [GCC 13.3.0]` | `3.12.3 (main, Aug 31 2026, 10:18:26) [GCC 13.3.0]` |
| CPU arch (`uname -m` in the container; `docker info` Architecture) | `aarch64` | `aarch64` |
| Base image (`IRIS_IMAGE` of `docker/Dockerfile`) | `ocutalon-iris-base:2026.3.0AI.154.0` (id `sha256:4e3907db2004`, the same image as `irishealth-community:2026.3.0AI.154.0`) | `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0` (id `sha256:78bfd01c5b6a`) |
| Stack | lane-A throwaway, compose project `ocutalon-repro-e0s16-<epoch>-<pid>`, files `docker-compose.yml` + `docker/tests/compose.throwaway.yml` (no host port, no env file, so no key), image built from this branch (OcuTalon 1.0.2, start log `AFTER-START end ... ready 1.0.2`) | the same, built with `IRIS_IMAGE` set to build 109's image (`AFTER-START end ... ready 1.0.2`) |
| Docker engine | 29.7.2, linux/aarch64 (Docker Desktop on Apple silicon) | the same |

- **Namespace:** a throwaway namespace `REPRO`, with its own database `/durable/repro/` (made in `%SYS` with `SYS.Database.CreateDatabase`, `Config.Databases.Create` and `Config.Namespaces.Create`). Only the two classes of this folder were loaded into it (`$system.OBJ.LoadDir(<dir>,"ck",,1)`: `Imported class: Repro.Tools`, `Imported class: Repro.Py`, `Load finished successfully.`). No OcuTalon class runs in any reproduction step.
- **The lane's lock:** each stack held `throwaway-iris.lock` in the lane-A lock folder (`<lock-dir>/lane-a`) from before its build until after its teardown (`LOCK acquired` / `LOCK released`). One stack at a time: build 154 was torn down before build 109 started.
- **No model:** no model key in the container (the throwaway override's `env_file: !reset []`, and the CI override was not layered), and no model call. `%AI.ToolMgr` needs no provider for `%New`, `AddTool` and `ExecuteTool`: `AddTool` returned 1 and `ExecuteTool` returned the tool's value in every run where the process lived that long.
- **Teardown:** both projects removed with their volume, network and built image (`docker compose down -v`, `docker image rm`). Afterwards `docker ps -a`, `docker volume ls` and `docker image ls` listed nothing named `e0s16`, and the lane-A lock folder was empty.

## Method

- **Each run is a fresh process:** `run.sh <container> "<lines>"` pipes the order's lines, then `write "DONE",!` and `halt`, into `iris session iris -U REPRO`. A run **survived** when `DONE` was printed. It **died** when the session ended before `DONE`, and `messages.log` gained the lines quoted below.
- **Log lines:** for each run, the `messages.log` lines added during the run (`/durable/iris/mgr/messages.log`; line count read before the run, new lines read 2 s after it).
- **The lines** (each `STEP` line prints before the next step starts, so a died run shows how far it got):
  - outside: `write "STEP outside ",##class(Repro.Py).PyPing(),!`
  - ToolMgr: `set tm=##class(%AI.ToolMgr).%New() write "STEP toolmgr ",tm.AddTool(##class(Repro.Tools).%New()),!`
  - inside: `set r=tm.ExecuteTool("PyPing",{}) write "STEP inside ",$select($isobject(r):r.%ToJSON(),1:r),!`
  - import: `set j=##class(%SYS.Python).Import("json") write "STEP import-json ",$isobject(j),!`
- **The orders:** (a) outside; (b) ToolMgr, inside; (c) outside, ToolMgr, inside; (d) ToolMgr, inside, outside; (e) import, ToolMgr, inside.

## Results: build 154

| Order | Run | Result | Last output before the end | `messages.log` |
| --- | --- | --- | --- | --- |
| (a) outside only | 1 | survived | `STEP outside pong thread=MainThread pid=3933` | (none) |
| (a) | 2 | survived | `... pid=3955` | (none) |
| (a) | 3 | survived | `... pid=3991` | (none) |
| (b) inside only | 1 | survived | `STEP inside {"timing":0.032034333,"value":"pong thread=MainThread pid=4013"}` | (none) |
| (b) | 2 | survived | `... pid=4052"}` | (none) |
| (b) | 3 | survived | `... pid=4091"}` | (none) |
| (c) outside, ToolMgr, inside | 1 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:26:421 (4130) 3 [Generic.Event] Process 4130 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` then `11/07/26-21:34:26:422 (4130) 3 [Generic.Event] Parent process will clean up and halt` |
| (c) | 2 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:28:568 (4184) 3 [Generic.Event] Process 4184 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (c) | 3 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:30:718 (4226) 3 [Generic.Event] Process 4226 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (d) ToolMgr, inside, outside | 1 | **died** at outside | `STEP inside {"timing":0.029505667,"value":"pong thread=MainThread pid=4266"}` | `11/07/26-21:34:32:869 (4266) 3 [Generic.Event] Process 4266 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (d) | 2 | **died** at outside | `STEP inside {... pid=4306"}` | `11/07/26-21:34:35:011 (4306) 3 [Generic.Event] Process 4306 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (d) | 3 | **died** at outside | `STEP inside {... pid=4361"}` | `11/07/26-21:34:37:146 (4361) 3 [Generic.Event] Process 4361 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (e) import json, ToolMgr, inside | 1 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:39:291 (4401) 3 [Generic.Event] Process 4401 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (e) | 2 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:41:441 (4441) 3 [Generic.Event] Process 4441 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |
| (e) | 3 | **died** at inside | `STEP toolmgr 1` | `11/07/26-21:34:43:582 (4481) 3 [Generic.Event] Process 4481 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt` |

- **Six extra runs of order (e) on build 154** (21:33:48 to 21:33:59, processes 3652, 3692, 3732, 3772, 3826, 3866): a first pass of the driver used a shell feature that macOS bash 3.2 lacks, so every order it ran was (e). All 6 died at the inside step with the same two `messages.log` lines. They are counted apart, not in the table. The instance's `messages.log` held 15 `caught signal 11` lines at teardown: these 6 plus the 9 in the table.
- **(c) and (e):** in both, `%AI.ToolMgr.%New()` and `AddTool` succeed after Python ran outside. The process dies inside `ExecuteTool`, when the tool method's Python call runs. **(d):** the tool call succeeds, and the process dies at the next direct Python call outside: `STEP outside ` is written, and the method's value never is.

## Results: build 109

| Order | Runs 1, 2, 3 | Result | Processes | `messages.log` (each died run, two lines) |
| --- | --- | --- | --- | --- |
| (a) outside only | survived x3 | `STEP outside pong thread=MainThread pid=<n>` | 3707, 3743, 3765 | (none) |
| (b) inside only | survived x3 | `STEP inside {"timing":0.034443666,"value":"pong thread=MainThread pid=3787"}` (and 0.026, 0.027 s) | 3787, 3826, 3865 | (none) |
| (c) outside, ToolMgr, inside | **died x3** at inside | last `STEP toolmgr 1` | 3918, 3958, 3998 | `11/07/26-21:40:32:614 (3918) 3 [Generic.Event] Process 3918 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` / `... 21:40:32:614 (3918) 3 [Generic.Event] Parent process will clean up and halt`; then 21:40:34:785 (3958) and 21:40:36:933 (3998), the same text |
| (d) ToolMgr, inside, outside | **died x3** at outside | last `STEP inside {...}` | 4040, 4080, 4134 | `11/07/26-21:40:39:075 (4040) 3 [Generic.Event] Process 4040 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt`; then 21:40:41:236 (4080) and 21:40:43:381 (4134), the same text |
| (e) import json, ToolMgr, inside | **died x3** at inside | last `STEP toolmgr 1` | 4174, 4214, 4254 | `11/07/26-21:40:45:541 (4174) 3 [Generic.Event] Process 4174 (JobType=Interactive job (programmer mode),Dumpstyle=0,Directory='/durable/repro/') caught signal 11.` + `Parent process will clean up and halt`; then 21:40:47:686 (4214) and 21:40:49:827 (4254), the same text |

- Every died run on build 109 logged exactly the two lines shown, with its own process number in both places and `JobType=Interactive job (programmer mode)`.

## Against S11

- S11 (`docs/handoff/spike-results/S11.md`, its isolation table) found `pyping, tm, tool:PyPing` → signal 11, `tm, tool:PyPing, pyping` → signal 11 at the outside call, `pyimport:<module>, tm, tool:PyPing` → signal 11, and `tm, tool:PyPing` → ok. That spike's classes also held FastEmbed, KB and work-queue code. Orders (c), (d), (e) and (b) here reproduce those four rows with two classes and no other code. S11's `tm, pyping, tool:PyPing` row (ToolMgr made between the two Python calls) is order (c)'s shape and also died.
- New: build 109 (2027.1.0AI) is affected the same way, and `%SYS.Python.Import` of a standard-library module counts as "Python outside" just as a `[Language = python]` method does.

## DW-792: keyword arguments from ObjectScript

**The documented form, and the source it is cited from:**
- `irislib/%SYS/Python.cls` (this instance's export) has no text about keyword arguments; line 7 points to "Using Embedded Python" in the documentation.
- The system code itself uses the form, and documents it. `irislib/%ML/AutoML/Provider.cls` lines 254-262: the doc comment "Helper method for invoking a python method with keyword args while under I/O capture" (line 254), a method (`%DoTrain`) whose argument is `args As %DynamicObject`, and the calls `..automl.train(df, args...)`. The same file, line 593: `Set ps = ..pstats.Stats(profiler, { "stream": (stream) }...)`. So: a `%DynamicObject` as the last argument, followed by `...`.

**Measured** (fresh `iris session`, `REPRO`, the same on both builds; `j = ##class(%SYS.Python).Import("json")`, newlines shown as `|`):

| Call | Build 154 output | Build 109 output | Keyword arrived |
| --- | --- | --- | --- |
| `j.dumps(l)`, `l = j.loads("[1,2]")` (control) | `[1, 2]` | `[1, 2]` | n/a |
| `set kw={"indent":2}` then `j.dumps(l,kw...)` (documented form) | `[\|  1,\|  2\|]` | `[\|  1,\|  2\|]` | **yes** |
| `kill kw set kw("indent")=2` then `j.dumps(l,kw...)` (19.2's `kw(...)...` form, a local array with a string subscript) | `[1, 2]` | `[1, 2]` | **no, silently ignored** |
| `j.dumps(d)`, `d = j.loads("{""b"":1,""a"":2}")` (control) | `{"b": 1, "a": 2}` | `{"b": 1, "a": 2}` | n/a |
| `set kw={"sort_keys":true}` then `j.dumps(d,kw...)` | `{"a": 2, "b": 1}` | `{"a": 2, "b": 1}` | **yes** (a JSON `true` reaches Python as true) |
| `set kw={"sort_keys":1,"separators":(j.loads("["";"",""=""]"))}` then `j.dumps(d,kw...)` (two keywords, one a Python object) | `{"a"=2;"b"=1}` | `{"a"=2;"b"=1}` | **yes, both** |
| `kill kw set kw("sort_keys")=1` then `j.dumps(d,kw...)` (local array) | `{"b": 1, "a": 2}` | `{"b": 1, "a": 2}` | **no** |

- **Why the local array fails:** `name...` passes a local array's subscripts 1 to n as positional arguments. A local with only a string subscript has no positional arguments, so the call is made with none extra and no error. That fits 19.2's "a `kw(...)...` argument is ignored".
- **Consequence:** the eval-lambda workaround of 19.2 was not needed. 19.6 has since moved those calls into `src/ocutalon/python/ocutalon_memory.py` (DW-792's `resolved-by` trailer). Nothing in the product changes here. If a later story calls a keyword-only Python API from ObjectScript, use `{...}...`.

## Files of this folder

- `Repro.Py.cls`, `Repro.Tools.cls`: the two classes, loaded only into the throwaway's `REPRO` namespace. They sit under `_bmad-output/`, which no loader or test reads as code: the image copies `src/` only (`docker/Dockerfile`, `COPY src/`), `src/module.xml` names resources under `src/`, and the repository's class scans (`docker/tests/test-storage.sh`, `test-class-rules.sh`, `test-pinned-sources.sh`, `test-install-start.sh`, `test-ci-warm.sh`, `test-ci-config.sh`, `ci/mock/test/constants.test.mjs`, `docker/after-start.sh`) all start at `src/` or a named folder under it. `ci/units.sh` classes `_bmad-output/` as bookkeeping (`BOOKKEEPING_PATTERN`).
- `run.sh`: the one-line runner, `bash run.sh <container> "<ObjectScript lines>"`.
- `results.md`: this file.
