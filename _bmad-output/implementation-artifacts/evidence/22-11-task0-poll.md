# Story 22.11, Task 0: the poll run (measured 2026-11-14)

Measured on the lane D warm throwaway (tag e22s11iw) with scratch classes `OcuTalon.Test.Mcp.ZzT11*` (removed afterwards), the loopback MCP mock (server `zzmcp`, header-checked
wallet credential) and the Epic 22 build of this worktree.

## 1. The manager (before any poll code)

Scratch `ZzT11Task0` ran in the test process (no `BuildAgent`, no model key, no AI session): a new `%AI.ToolMgr` that registers only `OcuTalon.Tools.McpProxy`, the gate as its
authorization policy and `Policy.StepAudit`, a context of Kind `decide`, Provenance `untrusted` (the nearest context that needs no grant; the poll's Kind `tool` came with the gate
change), and the map seeded with `Context.SetMcpTools` (one entry per tool, the server named). `ExecuteTool("call_mcp_tool", {server, tool, arguments})` gave:

- a result (zz_lookup, read-only): `{"timing":0.037,"value":"The mock ran zz_lookup"}`; the gate allowed it (untrusted rule satisfied by the classification), the step audit wrote one
  step, status `ok`, label `Running zz_lookup on zzmcp`, inputs `{"server","tool"}` only;
- a gate denial (zz_delete_ticket, risky): `ExecuteTool` THROWS `<%AICore>ToolAccessDenied` whose text holds the gate's UNTRUSTED sentence; the step audit records one step with
  status `denied` and the same label scheme. The poll must catch it and read it as `denied`;
- a proxy refusal (the mock changed zz_lookup's description): `ExecuteTool` returns a normal answer whose `value` is the refusal sentence ("this MCP tool changed since it was
  classified, ..."), the step is `ok`. `Context.ReplayRefusal()` stayed "" because `Proxy.Noted` notes only for an approved (replay) call: the poll needs the `IsPoll` branch of `Noted`.

So the manager works with no agent: `PollManager` needs none, and a keyless install polls like any other.

## 2, 3, 4. The async answer, the steps, the wire (measured with the poll path built)

Items 2 to 4 were measured in the same scratch runs as item 5 (`ZzT11Delay`), because the Checks -> Decide -> `Bridge.Poll` path had to exist to send a `tool` request; item 1 above ran
before any code.

- **2. The answer.** `Checks.RunSources` sent `SendRequestAsync("Decide", request, 1, "<Ref>|<sentAt>")`; the Reply came back to `Checks.OnResponse` with `%SessionId` the Tick's
  session (`LastRunHeaderId`). While polls waited on a silent mock (`Mock.Call(port, "silent")`, polls of 20 to 24 s), Checks was NOT held: the Tick sent `Checks>Digest` 2 ms after it
  sent the 3 polls, and the next automatic Tick (60 s later in the same stack) was handled normally (`Checks>Digest` at 16:54:00 in the answering run, and 16:56:00 in the stall run,
  while earlier polls had long ended). So AD-18's one-minute Tick holds.
- **3. Steps with no Decision row.** The poll's reply carries its steps; `EmitSteps` sent them to `AgentSteps` under the request's DecisionRef (no `Decision` row exists for it).
  `Operation.Steps` is a no-op that accepts the message: the stored step is the `AgentStep` message header in the Tick's trace. No `Decision` row was written for a poll's ItemId
  (checked in `TestPollRuns`).
- **4. The wire.** One poll, from the mock's log (client `iris` for each): `initialize`, `notifications/initialized`, `tools/list` (the seed: `Proxy.Listed`), then `initialize`,
  `notifications/initialized`, `tools/list`, `tools/call` (the proxy). That is the seed listing, then the proxy's `initialize`, `tools/list` and `tools/call` (approved veto 3),
  and the mock saw nothing from AI Hub's client.

## 5. The triage delay, BEFORE option (a) (10 untrusted Items to Intake, 3 s apart; 3 due sources; one Tick sent with the first Item)

Per decision: the time from the Intake -> Decide request header to the Decide -> Intake response header (`DATEDIFF(ms)` of `TimeCreated`); the `Decision` row's `DurationMs` agreed to within
5 ms. Medians are of the 10 decisions, in ms.

| Mode | median | maximum | decisions with Fallback 1 / timeout | polls' durations (ms, 3 polls) |
| --- | --- | --- | --- | --- |
| baseline (no source row) | 28 | 31 | 0 | none |
| answering (`text`) | 28 | 34 | 0 | 89, 146, 204 |
| `Call(port, "silent")` | 12774.5 | 26247 | 0 | 20170, 22181, 24193 (all `timeout`) |
| `Silence` | 17 | 8060 | 0 | 2016, 4027, 6041 (all `timeout`) |
| `Stall` | 15 | 8098 | 0 | 2022 (`failed`), 4040, 6058 (`timeout`) |

Reading: `silent` adds 12746 ms to the median (limit 10000 ms): the STOP limit is crossed, so the pre-ruled option (a) applies. No decision missed its timeout in any mode. The mock is one
job: while it holds a silent `tools/call` connection (40 s), the next poll's `initialize` waits in its queue and times out after 2 s, so polls 2 and 3 took only 2 s more each. A real
server that accepts connections concurrently would hold each of the 3 polls for about 20 s, 60 s in all (Decide's timer), so the measured `silent` row understates the real worst case.

## 5b. Option (a) applied (pre-ruled by the Contest Planner, ~15:10Z Nov 14): at most one poll in flight

`RunSources` sends no new poll while a source row's Reported holds `inflight` (the send time of a poll whose answer is not recorded yet, younger than `INFLIGHTSECONDS` 150 s; Decide answers
within its timer, 110 s at most, so an older mark is stale). A due source that is not stopped and finds a poll in flight sends nothing and keeps its NextDueAt, so it polls at a later Tick;
a stopped source still records its stopped run at once, since it makes no call. The mark is part of the source row's `Reported` (no new column); the answer's record writes `Reported`
without it, and an answer that is dropped (a repoint since the send) or a send that fails takes it off. Same scratch (`ZzT11Delay`), same 10 Items, 3 due sources, one Tick sent with the first
Item; the stack's own heartbeat Ticks (every 60 s) also ran, and in the answering run one landed in the window and sent the second source's poll after the first was answered.

| Mode | median BEFORE | max BEFORE | timeouts BEFORE | median AFTER | max AFTER | decisions with Fallback 1 / timeout AFTER | polls sent in the window AFTER (durations, ms) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline (no source row) | 28 | 31 | 0 | 28 (the same run) | 31 | 0 | none |
| answering (`text`) | 28 | 34 | 0 | 27 | 82 | 0 | 2 (63, 61) |
| `Call(port, "silent")` | 12774.5 | 26247 | 0 | 5734.5 | 19205 | 0 | 1 (20171, `timeout`) |
| `Silence` | 17 | 8060 | 0 | 16 | 4029 | 0 | 2 (2014, 2018, both `timeout`) |
| `Stall` | 15 | 8098 | 0 | 15 | 4040 | 0 | 1 (2016, `failed`) |

Check 1 (the STOP criteria): the largest median added over the baseline is 5706 ms (`silent`), under the 10000 ms limit, and no decision in any mode missed its timeout (Fallback 0, no
`timeout` reason). Passes.

Check 2 (no source marked stale only because of queuing): a silent poll holds the in-flight mark for at most about 26 s (2 s initialize and list of the seed, 2 s for the proxy's own, 20 s
for the call), so with 3 silent sources due at once the Ticks (60 s apart) poll them one at a time: the first at the Tick, the second at the next Tick, the third at the one after,
which is at most 120 s after they were due, inside the interval + 180 s that coverage allows (interval 5 minutes or more). Pinned by `TestOneInFlightNoQueueStale`
(`Test/Mcp/SourceRun.cls`); its mutation is in the spec's Verification section.

So option (a) passes both checks: the story is not halted.

## Notes

- The scratch classes `OcuTalon.Test.Mcp.ZzT11Task0` and `ZzT11Delay` were removed after the measurements; the warm throwaway (tag `e22s11iw`) was brought down.
- Order of the work: item 1 ran before any poll code; items 2 to 4 and 5 ran as soon as the Checks -> Decide -> `Bridge.Poll` path compiled (items 2 to 4 need that path to send a `tool` request), before the test tasks.
- Item 2's "second Tick handled while a poll waits": measured with real heartbeat Ticks in the same stack (see above); the mock's `Silence` mode was used in item 5, the held `tools/call` in the `silent` mode.
