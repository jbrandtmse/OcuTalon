---
title: 'Story 2.3: Route every command by verb, with origin checks'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: '679df0fa18a6557352cba533aa281350aa65afaa'
baseline_commit: '679df0fa18a6557352cba533aa281350aa65afaa'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The gate checks a tool's Dismiss against the command's SessionRef and never compares it with the active bridge context's OwnerRef, so a tool that filled SessionRef from model-supplied arguments could dismiss another session's incident.
    evidence: |-
      The spec fixes this reading (SQL bullet: SessionRef is set by the submitting code from its authenticated context, never from request input), and no tool in src calls Commands.Submit yet, so the bad outcome is not reachable today. Three review layers raised it independently.
      Settled by Story 1.10 (the first tool submitter): a test that begins a context with OwnerRef A, submits a Dismiss whose SessionRef is B, and expects a refusal; if the submitter cannot guarantee SessionRef = OwnerRef, add the cross-check to CommandsIn (an AD-1 amendment, Rule 20).
    location: >-
      src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls (Carry, tool Dismiss branch)
    severity: medium (unverified)
  - summary: >-
      Submit's ProcessInput kills the calling job's session id (the job-local SessionId) on exit, so later event-log rows written by a tool's job after a Submit may carry no SessionId and drop out of the turn's Visual Trace thread.
    evidence: |-
      Ens.BusinessService.ProcessInput kills $$$JobSessionId in preProcessInput and again at Exit (irislib/Ens/BusinessService.cls:79,100), and CommandsIn runs in the caller's own process through Submit. The behaviour dates from Story 0.6's Submit and was the same with the stub, so it is not caused by this story; Join sets only the service's own %SessionId.
      Settled by a throwaway check: inside an AgentRunner-like operation job with $$$JobSessionId set, call Commands.Submit, then log an event and read its SessionId. The remedy, if real, belongs to Trace.Join (Story 2.9) or to the runner restoring the id.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/Commands.cls (Submit) and the Ens.BusinessService it creates
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Core.CommandsIn` is still Epic 0's stub. Every command that `Commands.Submit` sends gets the error "not implemented", so nothing reaches an owner. Nothing checks which origin may send which verb, so once owners exist a tool, or content arriving through one, could reach a governance command.

**Approach:** Build `CommandsIn` as the production's one command gate (AD-1):
- It finds each verb's one owner in a fixed table and refuses any verb its origin may not send.
- It sends the command synchronously in the right trace session and returns the owner's `CommandResult`.
- When the owner is a stub or fails, it returns a plain-English `CommandResult` instead of an error.

Tests route every verb and check every origin rule against test owners in `OcuTalon.Test.Core`. A throwaway-only class checks the real production path: Visual Trace, the turn's thread, and the five stub owners.

## Boundaries & Constraints

**Always:**
- **One gate (AD-1, AD-33).** `Commands.Submit` stays the way in, unchanged; it already sets `Origin`. `CommandsIn` sends each verb only to the owner item its table names. The verb is matched by its exact class name.

  | Verb | Owner item | Origins it accepts |
  | --- | --- | --- |
  | `SetReminder`, `CancelReminder`, `ListReminders` | `ReminderOps` | all six |
  | `StartWatch`, `StopWatch` | `WatchOps` | all six |
  | `Dismiss` | `IncidentManager`, as an `IncidentCommand` with `Verb` "dismiss" | all six (from `tool`, only an incident the session can see) |
  | `SetDemoMode` (every settings verb, now and later) | `SettingsOps` | `system`, `web_admin` |
  | `Pair` | `SessionOps` | `telegram` |
  | `Unpair`, `EndSession` | `SessionOps` | all but `tool` |

  - The six origins are `Msg.Enum` `ORIGIN`.
  - Any other class gets a refusal. That includes `IncidentCommand` itself and an origin outside the enumeration.
- **Origin `tool` (AD-1, FR-24, NFR-14).**
  - A tool may send only: `SetReminder`, `CancelReminder`, `ListReminders`, `StartWatch`, `StopWatch`, and `Dismiss` of an incident that `Ownership.Incident(ref, command.SessionRef)` returns. That is a noticed incident of the session's own, or, on a local install, an `instance` incident of a production the session watches (AD-4).
  - While a bridge context is active in the process, `CommandsIn` treats the command as origin `tool`, whatever its `Origin` says, as `Submit` does.
  - Step 3's memory verbs join the tool list when they exist.
- **A refusal changes nothing.** Nothing is sent to any owner. The caller gets status OK and a `CommandResult` with `Ok` 0, an `Outcome` code and a plain-English `Message`.
- **Pass-through (AD-1).** The owner receives the command object itself, so `IdempotencyKey`, `SessionRef` and `Origin` arrive unchanged. The dismissal's `IncidentCommand` copies all three, plus `IncidentRef`. The owner's `CommandResult` is returned to the caller as it is.
- **Never an exception.** Once `CommandsIn` has answered, `Submit`'s status is OK and `result` is a `CommandResult`. A stub owner, an owner error, a timeout, a missing or wrong-class answer, or an error thrown inside `CommandsIn` each become a plain-English failure result. An error status from `Submit` means only that the command never reached `CommandsIn`: `Submit`'s own refusals, or a production that isn't running.
- **Visual Trace (AD-26, NFR-20).**
  - The command and the owner's answer are production messages.
  - Inside a turn, the command joins the turn's thread: before sending, `CommandsIn` sets `..%SessionId` to the bridge context's `ThreadSessionId` (when it is set) and `..%SuperSession` to the context's `SuperSession`. It never calls `Trace.Join`.
  - Outside a context, the command starts a session of its own. Its `SuperSession` is the `TraceRef` of the `Session` row that the command's `SessionRef` names, or empty when there is no such row.
- **SQL (AD-13 as amended).** The only read `CommandsIn` adds is the existing `Ownership.Incident` (row kind `incident`). There is no new prepare, no new row kind, and no embedded SQL. The owner `Ref` it passes is the command's `SessionRef`, which the submitting code set from its authenticated context and never takes from request input.
- **Code (Rule 14, conventions).** Source stays ASCII. Comments state the contract. Use `%Status` throughout. The fixed texts are class parameters of `CommandsIn`.

**Never:**
- Never build an owner. `ReminderOps` (Epic 8), `SettingsOps` (4.1), `SessionOps` (10.3, 16.4), and Lane A's `WatchOps` and `IncidentManager` (Epic 5) keep their stubs and `STUB`.
- Never change a REST route (the dismiss route is Story 6.4's), `Submit`'s signature or origin logic, a message class, or a table.
- Never check IRIS roles in `CommandsIn`: role checks stay with the admin-checked entry points (Design Notes 6). Never publish a live event, write the audit log, or call `Trace.Join`.
- Never edit a Lane A path (`Watch/**`, `Install/**` other than `Install/Step/Web.cls`, `Test/Install/**`) or `docker/merge.cpf`. In `docker/tests/test-production.sh` (Lane B's), edit only row 17 (`:16-17` and `:185-195`), never Epic 1's ruled fixture check at `:274-295`.
- Never run `OcuTalon.Test.Core.CommandsInProduction` on slot B. It needs the running production, and it fails there by design.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Route | Each of the 10 verbs, with an origin it accepts | Sent to its owner item (table above), with the same object, key, session and origin. The owner's `CommandResult` is returned as it is, with status OK | — |
| Dismiss | `Dismiss` (`IncidentRef`, key, session, origin) | `IncidentManager` gets an `IncidentCommand` with `Verb` "dismiss" and the four values copied | — |
| Tool, allowed | Origin `tool`: the five reminder and watch verbs | Routed | — |
| Tool, own incident | `tool` `Dismiss` of a noticed own incident, or a watched `instance` one (local) | Routed | — |
| Tool, unseen incident | `tool` `Dismiss` of another session's incident, an unnoticed one, an `eval` one, an unknown or empty `Ref`, or an empty `SessionRef` | `Outcome` `not_found`, `MESSAGENOTFOUND`, nothing sent | — |
| Tool, governance | `tool` `SetDemoMode`, `Pair`, `Unpair`, `EndSession` | `not_allowed`, `MESSAGENOTFROMTOOL`, nothing sent | — |
| Admin only | `SetDemoMode` from `web_user`, `telegram` or `timer` | `not_allowed`, `MESSAGEADMINONLY`, nothing sent. From `system` or `web_admin`: routed | — |
| Telegram only | `Pair` from any origin but `telegram` | `not_allowed`, `MESSAGETELEGRAMONLY`, nothing sent | — |
| Context wins | Payload origin `web_admin`, bridge context active | Treated as `tool`: `SetDemoMode` refused with `MESSAGENOTFROMTOOL` | — |
| Unknown | An `IncidentCommand`, a verb class not in the table, a non-command, or an origin outside the enumeration | `unknown_command` (or `not_allowed` for the bad origin), nothing sent | — |
| Stub owner | The owner answers code 5003, or `<Ens>ErrBPTerminated` whose text holds `#5003` | Status OK. `Ok` 0, `Outcome` `not_built`, `MESSAGENOTBUILT` | — |
| Owner failure | Any other error status, a timeout, no answer, or an answer that isn't a `CommandResult` | Status OK. `Ok` 0, `failed`, `MESSAGEFAILED` | — |
| Thrown inside | An error thrown inside `CommandsIn` | Status OK, `failed`, one `$$$LOGERROR` row | — |
| In a turn | Context with `ThreadSessionId` T and `SuperSession` S | The request header and the owner's answer are in session T, with `SuperSession` S | No `ThreadSessionId`: a session of its own, still with S |
| Outside a turn | No context, `SessionRef` of a `Session` row | A session of its own, with `SuperSession` = that row's `TraceRef` | No row, or an empty `SessionRef`: no `SuperSession` |

</intent-contract>

## Code Map

**Lane B (edit)**
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- the stub:
  - :1 is the class comment ("A stub until Story 2.3").
  - :7 is `Parameter STUB = 1`.
  - :9-12 is `OnProcessInput`, which answers `$$$NotImplemented`.
  - It is adapterless and pool 0. `Submit` creates it in the caller's own process (`Ens.Director.CreateBusinessService`), so the caller's bridge context is visible inside `OnProcessInput`.
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls:6-33` -- `Submit`: it sets `Origin` (`tool` in a context, :21-28), then `ProcessInput(command, .result)`. Only the doc comment :6 changes (the status contract). The signature is pinned at `Test/Contract/Ac.cls:327`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:24` -- the `CommandsIn` row has `"stub": 1`, which becomes 0. `Test.Install.Production.TestStubsAnswer` (`Test/Install/Production.cls:121-157`, Lane A, read-only) asserts that the `STUB` parameter equals the oracle.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- the shared fixture helper: `Session(user)` :11, `Incident(ownerRef, noticedAt, namespace, production)` :65, `Check(sessionRef, namespace, production)` :50, `Clean(refs)` :178. It gains `RemoveMessages`.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls:425-458` -- the private `RemoveMessages(refs)`. It deletes the headers, bodies and event-log rows by `SuperSession`, inside OCUORDERS (it switches with `New $NAMESPACE`). It calls only classes that resolve in both namespaces. It moves to `Fixture` (Rule 2), and :52 `OnAfterAllTests` calls the moved method.

**Contracts (read-only)**
- `Msg/Command.cls` -- `Origin`, `IdempotencyKey`, `SessionRef`; `RESPONSECLASSNAME` `CommandResult`.
- `Msg/Command/*.cls` -- the 10 verbs: `SetReminder`, `CancelReminder` (`ReminderRef`), `ListReminders`, `StartWatch`/`StopWatch` (`Namespace`, `Production`), `Dismiss` (`IncidentRef`), `SetDemoMode` (`DemoMode`), `Pair` (`CodeHash`, `ChatRef`), `Unpair` (`ChatRef`), `EndSession`.
- `Msg/IncidentCommand.cls` -- extends `Msg.Command`. `VERBS` "dismiss,closeForReplay,closeQuiet", `Verb`, `IncidentRef`.
- `Msg/CommandResult.cls` -- `Ok`, `Message`, `Outcome`, `Ref`, `DueAt`, `Data`.
- `Msg/Enum.cls:39` -- `ORIGIN`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `Active()` :68, `Current()` :74 (`ThreadSessionId` :32, `SuperSession` :35, `OwnerRef`), `Begin(request, superSession)` :45, `Put` :86.
- `Data/Ownership.cls:122` -- `Incident(ref, sessionRef, .sc)`, `""` when unseen. `LocalFlag` reads `onlineDemo`.
- `Data/Session.cls:26` -- `RefIndex` (`RefIndexOpen(ref)`), `TraceRef` :14.
- The stub owners keep their stubs: `Core/SessionOps.cls`, `Core/SettingsOps.cls`, `Schedule/ReminderOps.cls` (operations, 5003), and Lane A's `Watch/Ops.cls` (operation) and `Watch/IncidentManager.cls` (a process: `<Ens>ErrBPTerminated` carrying 5003, measured at `docker/tests/test-production.sh` row 16).
- `Web/Api.cls:39,41` -- `MESSAGESERVERERROR` and `MESSAGENOTBUILT`. Their words are reused, not referenced: Core may not reference Web (dependency rule).

**Patterns to follow**
- `Test/Data/OwnershipProbe.cls` -- a test subclass that reaches a product seam. `CommandsInProbe` follows it.
- `Test/Core/Commands.cls` -- ends the bridge context before and after, and counts runs with `^OcuTalonTest(<class>,"n")`. Its header says that no production runs on the slot, which stays true.
- `Test/Install/Production.cls:136-149` -- `Ens.Host.GetShadowInstance("class||<class>")` makes a handler callable with no production. It is measured for `CommandsIn`'s own class.
- `Test/Demo/Production.cls:228,333` -- `Guard`/`Running()`: a throwaway-only class fails every test with its reason when the production doesn't run.
- `Test/Web/Api.cls:43,59` -- save and restore `onlineDemo` through `Data.Public.Settings`.

**IRIS reference**
- `irislib/Ens/BusinessService.cls`:
  - `ProcessInput` :44-86 calls `OnProcessInput` and keeps `pOutput` on an error. On an error it also logs through `onOutsideErr` (:113-129), once per distinct text.
  - `preProcessInput` :97-101 clears `%SessionId`/`%SuperSession` first.
  - `SendRequestSync` :138-175 uses `..%SessionId`/`..%SuperSession` for the new header (AD-26, S6).
- `irislib/Ens/MessageHeader.cls:70-72` -- `NewRequestMessage`: an empty session id gets the header's own id.

**Tests that pin the old shapes**
- `docker/tests/test-production.sh:16-17` (header) and `:185-195` (row 17) expect `Submit` to answer code 5003 and an Error row "Not implemented" for `CommandsIn`. In Lane B's footprint; this story rewrites row 17 (task below, ruled at spec validation).
- `Test.Install.Production` `TestStubsAnswer` (via the oracle row above). `test-production.sh` rows 14, 16 and 18 read the same oracle: `CommandsIn` has pool 0, so row 16's sweep and row 18 never include it, and row 14 only creates it.

## Tasks & Acceptance

**Execution:**
- **Task 0** (implement stage; record each result under `## Verification`). On tag `e2s23i`, run `ci/iris.sh build`, then `ci/iris.sh class OcuTalon.Test.Core.CommandsInProduction`. Record three results:
  - that `OcuTalon.Production` runs in the class's throwaway (the class's guard);
  - for each of the five stub owners, whether the synchronous send leaves a response header (the owner's answer), or only the request header with its error;
  - that the joined command's request header has `SessionId` = the context's `ThreadSessionId`.

  `TestTraceAndThread` asserts the answer in the form measured. If the production does not run in a class or shard throwaway, HALT with an `intent gap` naming AD-22: the class could not run in CI.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- build the gate. Rewrite the class comment, and delete `STUB` and the stub handler.
  - **The table.** One fixed table inside the class, with one entry per verb class: the owner item and the origins it accepts (Boundaries). Add `Parameter TOOLVERBS` with the six verbs a tool may send, and `Parameter TIMEOUT = 120` (seconds).
  - **`OnProcessInput(pInput, Output pOutput)`.** Wrap the whole body in `Try`/`Catch`. A catch logs `$$$LOGERROR` and answers `failed`. Always quit OK with `pOutput` set to a `CommandResult`. In order:
    1. Not a `Msg.Command`, or a class not in the table: `unknown_command` with `MESSAGEUNKNOWN`.
    2. Work out the effective origin: `tool` if `Bridge.Context.Active()`, otherwise `pInput.Origin`.
    3. If the origin is `tool` and the verb isn't in `TOOLVERBS`: `not_allowed` with `MESSAGENOTFROMTOOL`.
    4. If the verb's origins don't include the origin: `MESSAGEADMINONLY` for a `SettingsOps` verb, `MESSAGETELEGRAMONLY` for `Pair`, otherwise `MESSAGENOTALLOWED`. All three take `Outcome` `not_allowed`.
    5. If the origin is `tool` and the verb is `Dismiss`: `Ownership.Incident(IncidentRef, SessionRef, .sc)` must return a row, or the answer is `not_found` with `MESSAGENOTFOUND`.
    6. Set the trace session (Boundaries).
    7. Build the request: the command itself, or the dismissal's `IncidentCommand`.
    8. `..Send(owner, request, .response)`.
    9. Map the answer:
       - OK with a `CommandResult`: return it as it is;
       - a status carrying 5003 (in `GetErrorCodes`, or `#5003` in its text): `not_built`;
       - anything else: `failed`.
  - **`Send(target, request, Output response) As %Status [ Private ]`.** The class's one send: `..SendRequestSync(target, request, .response, ..#TIMEOUT)`. It is the seam the test probe overrides.
  - **The texts** (exact; veto U-19, Ruled at spec validation item 2):
    - `MESSAGENOTFROMTOOL` "That can't be done from the chat. Nothing was changed."
    - `MESSAGEADMINONLY` "Only an OcuTalon admin can change settings. Nothing was changed."
    - `MESSAGETELEGRAMONLY` "A pairing completes only from Telegram. Nothing was changed."
    - `MESSAGENOTALLOWED` "OcuTalon can't take that command from here. Nothing was changed."
    - `MESSAGENOTFOUND` "This session has no such incident. Nothing was changed."
    - `MESSAGEUNKNOWN` "OcuTalon doesn't know that command. Nothing was changed."
    - `MESSAGENOTBUILT` "This part of OcuTalon isn't built yet. Nothing was changed."
    - `MESSAGEFAILED` "Something went wrong inside OcuTalon, so the command may not have finished."
  - Why: AD-1's one gate, AD-26's thread, and the AC's "never an exception".
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls` -- update only the doc comment of `Submit`. The status is OK once `CommandsIn` has answered, and `result` is then always a `CommandResult` whose `Ok` says whether the command was carried out. An error status means the command never reached `CommandsIn`. Don't touch the body.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` -- set `CommandsIn`'s `"stub"` to 0.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsOwner.cls` (new; extends `Ens.BusinessOperation`, no Test methods) -- the test owner.
  - `OnMessage(request, Output response)` records the call under `^OcuTalonTest("CommandsRouting", run, n)`: the target, the request class, `Origin`, `IdempotencyKey`, `SessionRef`, and the verb and `IncidentRef` of an `IncidentCommand`.
  - It answers according to the run's mode:
    - `ok`: a `CommandResult` with `Ok` 1, `Outcome` "test", and `Message` = the target;
    - `stub-op`: `$$$ERROR($$$NotImplemented)`;
    - `stub-bp`: `$$$ERROR($$$EnsErrBPTerminated, …)` carrying it, as a process stub does;
    - `error`: another error status;
    - `none`: OK with no response;
    - `wrong`: an `Ens.StringResponse`;
    - `throw`: a thrown error.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProbe.cls` (new; extends `CommandsIn`) -- it overrides only `Send`. The override records the target, `..%SessionId` and `..%SuperSession`, then passes the request to a shadow instance of `CommandsOwner`. It adds nothing to the product, and the product never refers to it.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` (new, `%UnitTest`, safe on slot B) -- calls `OnProcessInput` on a shadow instance of the probe.
  - `OnBeforeAllTests`/`OnAfterAllTests` end the bridge context, save and restore `onlineDemo`, clean their own `^OcuTalonTest("CommandsRouting")` runs, and call `Fixture.Clean(refs)` for their rows.
  - The tests:
    - `TestRoutes`: each of the 10 verbs, with an origin it accepts, reaches exactly its owner item, with the same class and key, session and origin values. The test owner's result comes back as the same object. `Dismiss` arrives as an `IncidentCommand` "dismiss" with the four values.
    - `TestOriginRules`: every verb by every origin, plus "zz" and "", against the test's own oracle (written out in the test, never read from `CommandsIn`). Each accepted pair is routed. Each refused one gets `not_allowed` with its text, and the owner records nothing.
    - `TestToolGovernanceRefused` (AD-1, AD-22): `SetDemoMode`, `Pair`, `Unpair`, `EndSession` and an `IncidentCommand` from `tool` are refused, and nothing is sent.
    - `TestContextMeansTool`: with a context active, a command whose `Origin` is `web_admin` and verb is `SetDemoMode` is refused as from the chat. After the context ends, it is routed.
    - `TestToolDismissOwnIncident`: uses fixture sessions A and B, with B watching `ZZNS`/`Zz.Production` and `onlineDemo` off.
      - Accepted: A's own noticed incident, and a noticed `instance` incident of the watched production (for B).
      - Refused with `not_found`: B's incident sent as A, an unnoticed one, an `eval` one, an unknown `Ref`, "" and an empty `SessionRef`.
      - The same `instance` incident with `onlineDemo` on: `not_found`.
    - `TestStubOwner`: `stub-op` and `stub-bp` each give `not_built` with `MESSAGENOTBUILT` and `Ok` 0, and `OnProcessInput`'s status is OK.
    - `TestOwnerFailure`: `error`, `none` and `wrong` each give `failed` with `MESSAGEFAILED`. `throw` gives `failed` and status OK; the test deletes the one event-log row the catch wrote, matched by ID above the maximum before the call and by source class `OcuTalon.Core.CommandsIn`.
    - `TestUnknownCommand`: an `IncidentCommand` "closeQuiet", an `Ens.StringRequest`, and a verb with origin "zz" each get a refusal, and nothing is sent.
    - `TestThread`: in a context with `ThreadSessionId` 424242 and `SuperSession` "zzss<n>", the probe sees `%SessionId` 424242 and `%SuperSession` "zzss<n>". With no `ThreadSessionId` it sees `%SessionId` "" and the same `SuperSession`.
    - `TestSuperSessionFromSession`: with no context and a fixture session, `%SuperSession` is its `TraceRef`. With an empty, unknown or `instance` `SessionRef` it is "".
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` (new, `%UnitTest`, THROWAWAY AND CI ONLY) -- every test goes through `Commands.Submit` against the running `OcuTalon.Production` and its five stub owners.
  - A guard fails every test, with the reason, when the production isn't running.
  - The fixture sessions come from `Test.Data.Fixture`, and the class removes its own headers with `Fixture.RemoveMessages` (by the fixture `TraceRef`s and the run's `zzss` values).
  - The tests:
    - `TestStubOwnersAnswerPlainEnglish` (Integration AC): each owner gets one verb with an origin it accepts:
      - `SetReminder` (`web_user`) → `ReminderOps`;
      - `StartWatch` (`web_user`) → `WatchOps`;
      - `SetDemoMode` (`system`, with `DemoMode` equal to the current `demo.mode`, so a real `SettingsOps` would change nothing) → `SettingsOps`;
      - `EndSession` (`web_user`) → `SessionOps`;
      - `Dismiss` (`web_user`) → `IncidentManager`.

      Each gives status OK and a `CommandResult` with `Ok` 0, `not_built` and `MESSAGENOTBUILT`.
    - `TestTraceAndThread`: a `ListReminders` from `web_user` for fixture session A has one request header from `CommandsIn` to `ReminderOps`. Its body is a `ListReminders` with the submitted `IdempotencyKey`, its `SuperSession` is A's `TraceRef`, and the owner's answer is the form Task 0 measured. Then, in a context with `OwnerRef` A, `ThreadSessionId` = that header's `SessionId` and `SuperSession` = A's `TraceRef`, a second `ListReminders` has its request header in that same session.
    - `TestGovernanceRefusedFromTool` (AD-22): inside a context, `SetDemoMode`, `Pair`, `Unpair` and `EndSession` through `Submit` each give `not_allowed`. The test asserts that the count of headers from `CommandsIn` to `SettingsOps` and to `SessionOps` is unchanged, and that `demo.mode` is unchanged.
    - `TestToolDismissReachesIncidentManager`: inside a context, a `Dismiss` of A's own noticed fixture incident gives `not_built` (it reached the stub). The same `Dismiss` of another session's incident gives `not_found` with no header.
  - Each owner's story rewrites its stub row here: 4.1, 5.1, 5.5, 8.4, 10.3, 16.4.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- add `RemoveMessages(superSessions As %DynamicArray, namespace As %String = {$Namespace}) As %Status`. It is the body moved from `Test.Demo.Production`, with the namespace as an argument and the same "only classes that resolve in both namespaces" rule in its comment.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls` -- `RemoveMessages` delegates to `Fixture.RemoveMessages(refs, ..#NAMESPACE)`. Its behaviour is unchanged.
- `docker/tests/test-production.sh` row 17 (ruled at spec validation; Lane B's file, row 17 only, never Epic 1's `:274-295`):
  - expect `CHK|submit-user|1|0|not_built|web_user` and `CHK|submit-tool|1|0|not_built|tool` (status OK, `result.Ok`, `result.Outcome`, the origin);
  - keep `submit-zz`;
  - replace `commandsin-logged` with `CHK|commandsin-sent|1`: a header from `CommandsIn` to `ReminderOps` with body class `OcuTalon.Msg.Command.ListReminders` after the first `Submit`;
  - reword `:16-17` to say that `CommandsIn` answers both with `ReminderOps`' plain-English `not_built` result.

**Acceptance Criteria:**
- **Routing.** Given a command that `Commands.Submit` sends with an origin its verb accepts, when `CommandsIn` receives it, then:
  - it goes to its one owner: reminder verbs to `ReminderOps`, watch verbs to `WatchOps`, `SetDemoMode` to `SettingsOps`, `Pair`, `Unpair` and `EndSession` to `SessionOps`, and `Dismiss` to `IncidentManager` as an `IncidentCommand` "dismiss";
  - `CommandsIn` waits for the owner's synchronous answer and returns its `CommandResult` unchanged;
  - the owner receives the `IdempotencyKey` unchanged (`TestRoutes`; `TestTraceAndThread`'s stored body).
- **Visual Trace and the thread.** Given the running production, when `Submit` runs:
  - outside a turn, the command and the owner's answer are messages of one session whose `SuperSession` is the session's `TraceRef`;
  - inside a turn, they are in the turn's thread, from the context's `ThreadSessionId`, with no call to `Trace.Join` (`TestTraceAndThread`; `TestThread`, `TestSuperSessionFromSession`).
- **Origin `tool`.** Given a command with origin `tool`, or any command while a bridge context is active, then:
  - only `SetReminder`, `CancelReminder`, `ListReminders`, `StartWatch`, `StopWatch` and `Dismiss` of an incident the session can see are routed;
  - every other verb is refused with a plain-English `CommandResult`, and no owner receives anything: `SetDemoMode`, `Pair`, `Unpair`, `EndSession`, an unknown command, or another session's or unseen incident (`TestOriginRules`, `TestToolGovernanceRefused`, `TestContextMeansTool`, `TestToolDismissOwnIncident`, `TestGovernanceRefusedFromTool`, `TestToolDismissReachesIncidentManager`).
- **Settings and pairing origins.** Given `SetDemoMode` from any origin but `system` or `web_admin`, or `Pair` from any origin but `telegram`, when `CommandsIn` checks it, then it is refused with the plain-English result and nothing is sent (`TestOriginRules`).
- **Stub owners (Integration AC: consumer `Commands.Submit`).** Given each of the five owners still an Epic 0 stub, when `Submit` sends it a command, then the caller gets status OK and a `CommandResult` with `Ok` 0, `Outcome` `not_built` and "This part of OcuTalon isn't built yet. Nothing was changed." — never an error status and never an exception. An owner error, a timeout or a missing answer gives `failed` the same way (`TestStubOwnersAnswerPlainEnglish`, `TestStubOwner`, `TestOwnerFailure`).
- **Built, not stub.** Given the production oracle, when `Test.Install.Production` runs, then `CommandsIn` carries no `STUB` and the oracle row says `stub` 0 (`TestStubsAnswer`).

### Review Findings

Code review 2026-10-22 (four layers, full-opus tier): 31 rows, 25 entries after grouping (high 0, medium 4, low 18, false 3). Each entry gives severity, fix-risk, footprint and disposition (Rule 15).

- [x] [Review][Patch] DW-73: inside a bridge context, a tool `Dismiss` is checked against the command's `SessionRef` alone, so a `SessionRef` naming another session reaches `IncidentManager` with that session's incident (medium; fix-risk low, one fail-closed check; in-story) [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:137]. A `SessionRef` that isn't the context's `OwnerRef` is `not_found` and nothing is sent; `TestContextDismissSeesOwnIncidentOnly` gains that case. This only narrows AD-1's "one of the session's own incidents" (AD-4), so no AD text changes.
- [x] [Review][Patch] `Submit`'s doc comment says `CommandsIn` owns the role checks, but `CommandsIn` makes none (medium; fix-risk low, comment only; in-story) [src/ocutalon/cls/OcuTalon/Core/Commands.cls:14]. An endpoint author (Story 4.1, step 2) could rely on a second check that doesn't exist.
- [x] [Review][Patch] "demo.mode is as it was", and the current mode that the `SettingsOps` row sends, are read through `Setting.Get`'s 60-second per-process cache, so the second read can never differ from the first (low; fix-risk low; in-story) [src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls:158]. Read the row itself.
- [x] [Review][Patch] `TestTraceAndThread`'s "a session of its own" asserts `SessionId '= ""`, which `Ens.MessageHeader.NewRequestMessage` always makes true (low; fix-risk low; in-story) [src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls:123]. Assert that `SessionId` is the request header's own ID.
- [x] [Review][Patch] `TestTraceAndThread` compares the stored key with the submitted object's own property, so a key rewritten in place on that object would still pass (low; fix-risk low; in-story) [src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls:121]. Compare with the literal key.
- [x] [Review][Patch] `Send`'s comment says no caller outside the class sends, but any code can call the inherited public `SendRequestSync` on a `CommandsIn` (row 16 of `test-production.sh` does) (low; fix-risk low; in-story) [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:152]. The comment should say only that `Carry` sends through it, after the checks.
- [x] [Review][Defer] AD-1's `Submit` sub-bullet (amended 2026-10-19, Story 0.6) says "role checks stay with the admin-checked endpoints and `CommandsIn`". Design Notes 6 reads that as the origin rules, and `CommandsIn` makes no role check (medium; fix-risk med; out-of-footprint: the spine) [_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:105] — deferred: the code matches AD-1's governing bullet, AD-19 (the terminal command "requires the OcuTalon admin role") and the epic AC ("only the admin-checked terminal command and admin-checked endpoints can change settings"). Only the 0.6 parenthetical names `CommandsIn`. Settling it is an AD wording decision (amend the parenthetical, or add a role check to `CommandsIn`), which is a veto-window item: ledgered as DW-75 (`decision-pending`, owner `burndown`) for the lead to route to the orchestrator.
- [x] [Review][Defer] `ProcessInput` kills the caller's job-local session id (Edge Case Hunter) [src/ocutalon/cls/OcuTalon/Core/Commands.cls:31] — deferred: this is DW-74, routed to Story 2.9; an occurrence is appended.

Rejected:
- low `TIMEOUT` (120 s) is longer than a tool's turn (bridge timer at most 110 s, 60 s by default) and a gateway's 60 s: wontfix-theoretical. Every owner is a stub that answers at once, and Tasks and Design Notes 8 set 120 s. It becomes real when a built owner reached by a tool or REST caller can take longer than that caller's deadline; the owner's story tunes it (4.1 first).
- low A refusal leaves no message and no event-log row: by-design (Design Notes 9). A refusal changes nothing, so AD-1's Prevents line holds.
- low Nothing ties `Routes` to the verb classes: wontfix-accepted, reopen_if a verb class under `OcuTalon.Msg.Command` ships without a `Routes` row. The gap fails closed (`unknown_command`), and the verb's own tests show it.
- low `CommandsInProduction.Sent` counts every `CommandsIn` header in the namespace: wontfix-theoretical. Nothing else submits commands in a throwaway; it becomes real when a production item submits commands on its own (a timer verb).
- low The effective origin isn't written back onto the forwarded command: by-design (Boundaries: `Origin` arrives unchanged). `Submit` already stamps `tool` inside a context.
- low A failed `Ownership.Incident` read answers `not_found`: wontfix-accepted, because it fails closed. `Rows` also answers an error status for an empty or literal `SessionRef`, which the matrix requires to be `not_found`, so mapping an error to `failed` isn't a direct correction. reopen_if a `Rows` read error is seen on the dismiss path.
- low `IsStub` matches any `#5003` text: wontfix-theoretical, since it is the spec's stub contract. It becomes real when a built owner can return 5003 (for example a built `SessionOps` calling a step-3 stub); that owner's story then also checks the owner's `STUB`.
- low `CleanRuns` would delete an overlapping run's records: wontfix-theoretical. Two runs of one class in one namespace at once is what Rule 18 (3) forbids.
- low No test checks that `Fixture.RemoveMessages` deletes anything: wontfix-accepted. It is a verbatim move plus a namespace argument, used on throwaways. reopen_if a throwaway shows `zz` SuperSession headers after `CommandsInProduction` or `Test.Demo.Production`.
- low `$ListLength(table) = 10`, `routed + refused = 80` and `routed > 0` can't fail because of a `CommandsIn` defect: they are loop guards (as review row V3), and the per-pair assertions pin the ACs.
- false "`%Extends(ListReminders) = 1` can't fail": it fails if `CommandsSubVerb` stops extending a verb, which would make `TestSubclassOfVerbIsUnknown` vacuous.
- false "The Routing AC's key clause has no `mutation:` line": Rule 19 asks for one per AC, and the Routing AC's key mutation was observed (`TestRoutes`).
- low `Test.Core.Commands` and `CommandsContext` now leave `CommandsIn` headers behind in throwaway shards: wontfix-accepted. The tests count only deltas, the throwaway is torn down, and headers whose SuperSession is "" can't be scoped for removal. reopen_if a test counts OCUTALON headers absolutely. Their class comments describe the slot, and they stay true.
- low A header on the `IncidentManager` path lies outside the session's SuperSession and stays behind: wontfix-accepted. Lane A's stub process makes it, not the gate. The gate's request carries the SuperSession: its response header does, and `NewResponseMessage` copies it; `Sent` would also count a second request. reopen_if Epic 5's `IncidentManager` leaves headers without a SuperSession (AD-26).
- false "QA's `CommandsSubVerb` breaks 'never change a message class or a table'": it changes no product message class and no product table. It is a test class that is never saved, and `test-storage.sh` and `Test.Data.Tables` pass with it.
- low The Auto Run Result says 10 tests and leaves out QA's files, which are uncommitted: the fix would edit the spec under review. QA's additions are recorded under Verification, and the lead commits them.
- low Line references into `docker/tests/test-production.sh` are now 3 lines off, because row 17's rewrite moved Epic 1's fixture check down 3 lines: no code change; noted for the lead.

## Spec Change Log

- 2026-10-22, spec validation (lead):
  - The plan's blocking question is ruled (decide). `docker/tests/test-production.sh` is a Lane B path (`docker/**`). Epic 1 holds a ruled extension only for its fixture check at `:274-295`, so this story rewrites row 17 itself. The plan prompt had wrongly excluded the whole file.
  - The task the plan quoted is added verbatim under Tasks & Acceptance, and the frontmatter status is set to `ready-for-dev` with no re-plan.
  - The veto-window items are ruled as planned (inbox veto item).
  - The Rule 5 wording is amended in `epics.md` (tier 1).
  - The former `## Clarification Needed` section is folded into Design Notes, "Ruled at spec validation".

## Review Triage Log

### 2026-10-22 - Review pass
- verdicts: 40 findings - high 0, medium 3, low 32, false 1, maybe-false 4
- groups: row 17 baseline (B5, E13, V7; medium) is patched; the Submit doc claim (E12) is patched; the tool Dismiss owner (B1, E1, V9) and the job-local session id (E9) are deferred; every other row is rejected.
- findings (B = Blind Hunter, E = Edge Case Hunter, V = Verification Gap, I = Intent Alignment):
  - `[maybe-false]` `[defer]` B1: tool Dismiss is checked against the command's SessionRef, not the context's OwnerRef - the spec fixes this reading (SessionRef is set by the authenticated submitter) and no tool submits yet; in `deferred:` with what settles it (Story 1.10).
  - `[low]` `[reject]` B2: the effective origin `tool` is not written back to the forwarded command - the spec requires `Origin` to arrive unchanged, and `Submit` already stamps `tool` in a context; only a caller that bypasses `Submit` (against AD-1) sees another value.
  - `[low]` `[reject]` B3: the status of `Ownership.Incident` is dropped - a failed read answers `not_found`, so it fails closed; telling an empty or `instance` Ref from a broken read needs more than a direct correction.
  - `[low]` `[reject]` B4: `IsStub` matches any `#5003` text - the spec's stub contract is code 5003 or `#5003` in the text; a built owner with an unrelated 5003 is not reachable until an owner is built.
  - `[medium]` `[patch]` B5: row 17's `commandsin-sent` has no baseline - patched: the count is read before and after the first `Submit` and the check is `after>before`.
  - `[low]` `[reject]` B6: exact-class routing has no subclass test - a subclass test needs a persistent test message class and a table, to pin a Decided-in-stage property that no AC states; reopen_if `Route` is changed to match by `%Extends`.
  - `[low]` `[reject]` B7: the catch block is not itself guarded - it fails only if the event-log write throws, a double fault.
  - `[low]` `[reject]` B8: a missing or wrong-class owner answer logs nothing - Design Notes 9 rules that only an error thrown inside `CommandsIn` is logged.
  - `[low]` `[reject]` B9: `Fixture.RemoveMessages` swallows delete errors - a verbatim move of `Test.Demo.Production`'s helper, used on throwaways only.
  - `[maybe-false]` `[defer]` E1: same claim as B1.
  - `[low]` `[reject]` E2: same claim as B3.
  - `[low]` `[reject]` E3: no `TraceRef` fallback when a context has an empty `SuperSession` - the spec sets `%SuperSession` to the context's value and the runner supplies it at `Begin`.
  - `[low]` `[reject]` E4: same claim as B2.
  - `[low]` `[reject]` E5: same claim as B4.
  - `[low]` `[reject]` E6: same claim as B7.
  - `[low]` `[reject]` E7: a tool command with an empty `IdempotencyKey` is routed - AD-1 puts the key on the submitter and the repeat check on the owner; the spec gives the gate no key check.
  - `[low]` `[reject]` E8: `Dismiss` from the five other origins has no visibility check - the spec table limits the check to `tool`; the REST route (Story 6.4) and `IncidentManager` own the rest.
  - `[maybe-false]` `[defer]` E9: `ProcessInput` kills the caller's job-local session id - the kill is in the platform code that `Submit` has run since Story 0.6, not caused by this story; in `deferred:` with what settles it.
  - `[low]` `[reject]` E10: an empty-string SuperSession would delete every unscoped header - no caller passes one (fixture `TraceRef`s are asserted non-empty by `TestSuperSessionFromSession`; the others are `zzss<n>`), and the helper runs on throwaways only.
  - `[low]` `[reject]` E11: same claim as B9.
  - `[low]` `[patch]` E12: `Submit`'s doc says an error status means only Submit's refusals or a production that is not running - patched: the comment now names a production that is shutting down or has `CommandsIn` disabled (`preProcessInput` returns an error for both).
  - `[medium]` `[patch]` E13: same claim as B5.
  - `[low]` `[reject]` V1: no test produces an owner timeout or runs the real `Send` against a slow owner - all five owners are stubs that answer at once; a timeout is an error status and takes the `failed` path that `TestOwnerFailure` pins; reopen_if the first built owner can sleep (Story 8.4): add a shortened-`TIMEOUT` test.
  - `[low]` `[reject]` V2: the `demo.mode` unchanged assertion cannot fail while `SettingsOps` is a stub - the spec asks for it, and the two header-delta assertions beside it pin the AC.
  - `[low]` `[reject]` V3: three sanity counts in `CommandsRouting` (10, 80, `routed>0`) cannot fail from a `CommandsIn` defect - they guard the loops against running empty; the pinning assertions are per pair.
  - `[false]` `[reject]` V4: AC sub-bullets lack a mutation line - Rule 19 asks one demonstrated mutation per AC, and each of the six ACs has at least one of the 13 observed mutations.
  - `[low]` `[reject]` V5: the refused-command mutation was observed on slot B only - the planned table names `TestToolGovernanceRefused` as the expected red, and it went red there.
  - `[low]` `[reject]` V6: row 17 has no mutation line - row 17 is a rewritten existing check, not an AC's pinning test; the stub-owner AC is pinned by `TestStubOwnersAnswerPlainEnglish`, and row 17 runs in the `live production` pass.
  - `[medium]` `[patch]` V7: same claim as B5.
  - `[low]` `[reject]` V8: `Fixture.RemoveMessages` has no assertion that it removed anything - a leftover header in a throwaway harms no assertion.
  - `[maybe-false]` `[defer]` V9: same claim as B1.
  - `[low]` `[reject]` I1: the six origins are literals in the table, not read from `Msg.Enum ORIGIN` - the spec table spells "all six", and `TestOriginRules` pins every pair against its own oracle.
  - `[low]` `[reject]` I2: no test checks which `Origin` the owner sees when a context is active - same claim as B2.
  - `[low]` `[reject]` I3: a real owner's success answer across `SendRequestSync` is tested nowhere - every owner is a stub; reopen_if the first built owner (Story 8.4) rewrites its row in `CommandsInProduction`.
  - `[low]` `[reject]` I4: the live in-turn test cannot tell the context's `SuperSession` from the session's `TraceRef` - they are equal there; `TestThread` uses distinct values.
  - `[low]` `[reject]` I5: the live pass-through checks are narrower than the stand-in's - the stand-in pins the same values with object identity.
  - `[low]` `[reject]` I6: no test produces a timeout - same claim as V1.
  - `[low]` `[reject]` I7: "thrown inside" is simulated from `Send` only - the catch wraps the whole body, so the source of the throw does not change the contract the test pins.
  - `[low]` `[reject]` I8: the live checks send one verb per stub owner, and row 17 only to `ReminderOps` - the routing table is pinned by `TestRoutes` for all ten verbs.
  - `[low]` `[reject]` I9: stub detection is broader than the literal intent - same claim as B4.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- AD-1: the one gate, verbs by owner, the tool allow-list, origin rules, the `IdempotencyKey` pass-through, and "role checks stay with the admin-checked endpoints and CommandsIn" (note 6).
- AD-4: "the session's own incidents" through the ownership API, including watched `instance` incidents locally.
- AD-13 as amended: no new unchecked path. `Ownership.Incident` is reused, and its owner `Ref` is never request input.
- AD-15: `IncidentManager` alone acts on incidents, and a REST or chat dismissal reaches it as an `IncidentCommand` through `CommandsIn`.
- AD-18: the reminder verbs.
- AD-19: `SettingsOps` is the only settings writer, reached with origin `system` or `web_admin`.
- AD-22: governance refused from `tool` in CI, `%UnitTest` under `Test.Core`, and the live class on throwaways.
- AD-26: the thread join through `ThreadSessionId`, and `SuperSession` = `TraceRef`.
- AD-29 and AD-33: Lane B owns `CommandsIn` and the oracle's lane B rows; Lane A's items are addressed only by name.
- Conventions rows: Messages, Enumerations (Origin), Logging and errors, Tests.
- None of the ACs contradicts an AD Rule. The one wording difference (listing reminders) is amended in `epics.md` (Ruled at spec validation, item 3).

**Decided in-stage** (small and reversible, within the intent):
1. **The status contract.** `Submit` answers OK whenever `CommandsIn` answered. The project's convention (`$$$ThrowOnError` inside methods) turns an error status into a thrown error at the caller, so "never an exception" means status OK with a failure result. This is what makes `test-production.sh` row 17 go stale; this story rewrites it (Ruled at spec validation, item 1).
2. **`ListReminders` is accepted from `tool`.** AD-1 lists "set, cancel or list reminders" (`ListReminders`; AD-29), and Story 1.10's list tool needs it. The AC now says so (Ruled at spec validation, item 3).
3. **Exact-class routing.** A subclass of a verb, `IncidentCommand` itself (`closeForReplay` and `closeQuiet` go straight to `IncidentManager` from `BreakFeedIn` and `Checks`), or any other class is refused as unknown. A gate that routes only what its table names can't be widened by a new class.
4. **The origin rules are exactly the AC's.** Every pair the AC doesn't restrict is accepted (for example `EndSession` from `timer`). A later owner can refuse within its own verb.
5. **A context makes the origin `tool` at the gate too.** This mirrors `Submit` in the same process (adapterless services run in the caller's job), so code that bypasses `Submit` still can't reach a governance verb from a tool. It only narrows what is accepted.
6. **No role check in `CommandsIn`.** The AC says the origin rule leaves "only the admin-checked terminal command and admin-checked endpoints" able to change settings, so the role checks are theirs (Story 4.1's `Admin.SetDemoMode`, step 2's settings endpoints). AD-1's "and CommandsIn" is read as its origin rules.
7. **A stub is recognised by its status.** Epic 0's stub contract is code 5003, or a process stub's `<Ens>ErrBPTerminated` carrying `#5003` (measured at `test-production.sh` row 16). Only then does the text say "Nothing was changed". Any other owner failure gets the honest "may not have finished".
8. **`TIMEOUT` is 120 s.** `SetDemoMode` (Story 4.1) creates OCUORDERS and starts its production. A REST dismiss and the reminder verbs answer fast. 4.1 may tune it.
9. **No event-log row for refusals or owner failures.** A refused tool call shows in Visual Trace as the agent step and its result (Lane A's `AgentSteps`). A failing owner logs its own error, and the trace shows its error answer. Only an error thrown inside `CommandsIn` is logged.
10. **The test owners sit behind `Send`.** That method is the product's one send and the only seam the probe overrides, as `Test.Data.OwnershipProbe` does for `Rows`. The unit class runs on slot B with no production. The real Interoperability path is the live class's job.
11. **Session for `SuperSession`.** It is opened by `Session.RefIndexOpen`, which is object access to the command's own session row, not an owned-record read. So it doesn't go through `Rows`.
12. **The table is an XData block.** `CommandsIn` holds its table as the JSON XData `Routes` (verb, owner, origins), read with `%Dictionary.CompiledXData` as `Test.Core.ProductionItems` does, by the literal class name so a subclass finds it. A command's verb is its class name below the package `OcuTalon.Msg.Command.`; only that exact name is looked up, so a subclass, a nested package or `IncidentCommand` is unknown. `TOOLVERBS` holds the same short verb names.
13. **`$$$LOGERROR` names the running class.** The row that the catch writes carries the class of the object that ran `OnProcessInput`: `OcuTalon.Core.CommandsIn` in the production, the probe's class in `TestOwnerFailure`. The test matches the probe's class and the method `OnProcessInput`, not the product's class name, and deletes that one row.
14. **Who records what in the routing tests.** The probe keeps the objects and the trace session of its last send (`LastRequest`, `LastResponse`, `SeenSessionId`, `SeenSuperSession`) and hands the run number, the answer mode and the target to the owner, which writes the call record under `^OcuTalonTest("CommandsRouting", run, n)` (the spec had the probe record the target; the owner has it from the probe, with the same effect). Object identity ("the same object") is checked on the probe's properties, not through the global.
15. **`TestGovernanceRefusedFromTool` also asserts the refusal text.** The origins table is a second layer behind `TOOLVERBS`, so a verb added to `TOOLVERBS` alone is still `not_allowed`, with the admin or pairing text instead. The chat text ("That can't be done from the chat") is what shows that the tool-verb check refused it.
16. **The owner's answer is a response header.** From Task 0: a stub owner leaves a response header (Type 2, IsError 1) from the owner to `CommandsIn`, so `TestTraceAndThread` and `TestStubOwnersAnswerPlainEnglish` assert one such header in the request's session.
17. **`Test.Demo.Production`.** `OnAfterAllTests` calls `Fixture.RemoveMessages(refs, ..#NAMESPACE)` directly. The private `RemoveMessages` stays as the one-line delegate for `Record`, which cleans after its batch.
18. **Row 17's `commandsin-sent`.** The count of `CommandsIn` to `ReminderOps` headers with body `OcuTalon.Msg.Command.ListReminders` is read before and after the first `Submit`, and the check is that the count grew, so a header from an earlier message cannot satisfy it. The tool-path `Submit` is checked through its `Outcome`.

**Integration ACs (Rule 1).** `CommandsIn` is reached by its consumer `Commands.Submit`, the entry point every later caller uses. Against the running production, the observable effect is the owner's answer (a plain-English `not_built` result from each stub owner) and the messages in Visual Trace (`TestStubOwnersAnswerPlainEnglish`, `TestTraceAndThread`).

**Consumed-by:**
- 1.10 (Lane A): the reminder tools, through `Submit` with origin `tool`.
- 4.1: `Admin.SetDemoMode` (origin `system`) → `SettingsOps`.
- 5.1 (Lane A): the watch tools → `WatchOps`.
- 5.5 (Lane A): `IncidentManager` handles the dismissal `IncidentCommand` and the chat dismiss tool.
- 6.4: `POST /incidents/:ref/dismiss` → `Submit`.
- 8.3 and 8.4: `ReminderOps`.
- 10.3: `SessionOps` pairing and unpairing, and `DELETE /pairing`.
- 12.4 and 12.5 (Lane A): `TelegramIn` `Pair` and `Unpair` with origin `telegram`.
- 16.4: Sign out → `EndSession`.

Each owner's story rewrites its row of `CommandsInProduction`.

**Consumes:**
- `Commands.Submit` and `Bridge.Context` (Story 0.6);
- the verb classes, `CommandResult` and `IncidentCommand` (Story 0.4);
- the stub owners and the oracle (Story 0.6);
- `Ownership.Incident` and `Test.Data.Fixture` (Story 2.2);
- the `Session` row's `TraceRef`.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `CommandsIn` replaces its own stub.
- `CommandsInProbe` follows `OwnershipProbe`.
- `RemoveMessages` moves from `Test.Demo.Production` into `Test.Data.Fixture`, which both classes call.
- Copy, with its reason: the `MESSAGENOTBUILT` and `MESSAGEFAILED` wording repeats `Web.Api`'s `MESSAGENOTBUILT`/`MESSAGESERVERERROR`, because Core may not reference `OcuTalon.Web`.

**Ledger (Rule 17).** This story owns no entries.

**Ruled at spec validation (no open question remains; the implement stage builds on these).**
1. **`test-production.sh` row 17 (decide).** The file is Lane B's (`docker/**`). Epic 1's ruled extension covers only its fixture check at `:274-295`. So this story rewrites row 17 (`:16-17`, `:185-195`) to the plain-English `not_built` contract (the task under Tasks & Acceptance). A conflict with Epic 1's edit at integrate-forward is a plain union. Rejected: (b), passing the owner's error status through, which goes against the "never an exception" AC; and (c), waiting for Epic 1, which would stall every command consumer for nothing.
2. **The eight `CommandResult` texts and decisions 3 and 5 (veto, inbox U-19).** They are kept as planned. The texts are class parameters, so a reversal is one parameter each. Exact-class routing and "a context means `tool`" only narrow what a command may do.
3. **Rule 5, tier 1 (applied and reported).** Story 2.3's second AC in `epics.md` now reads "setting, listing or cancelling a reminder", marked `[AMENDED 2026-10-22, Story 2.3 spec validation, Rule 5 tier 1, Epic 2 runner]`, following AD-1's Rule and Story 1.10's list tool.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message. Every throwaway command is `OCUTALON_RUN_TAG=e2s23i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`, with one piece per call and `timeout: 600000`. End with `teardown` on the same tag. A `LOCK busy` exit 75 is Epic 1's contention: wait and run it again.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`) as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (loop) `iris_execute_tests`, one class per message, on slot B. Expected: all pass, and slot B holds no fixture row afterwards.
  - `OcuTalon.Test.Core.CommandsRouting`
  - `OcuTalon.Test.Core.Commands`
  - `OcuTalon.Test.Core.CommandsContext`
  - `OcuTalon.Test.Msg.Contracts`
  - `OcuTalon.Test.Contract.Ac`
  - `OcuTalon.Test.Data.Ownership` (`Fixture` changed)
- (loop) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, one call each. Expected: exit 0, with `ALLOW_UNCHECKED` unchanged.
- (loop) throwaway: `build`.
- (loop) throwaway: `class OcuTalon.Test.Core.CommandsInProduction`. Expected: passes, and Task 0 is recorded from the first run.
- (loop) throwaway: `class OcuTalon.Test.Install.Production`. Expected: passes (`TestStubsAnswer` with `CommandsIn` stub 0).
- (loop) throwaway: `class OcuTalon.Test.Demo.Production`. Expected: passes (`RemoveMessages` moved).
- (loop) throwaway: `teardown`.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) throwaway, one call each: `shard lane-b` (28 classes, the two new ones included), `shard lane-a`, `live production` (row 17 as this story's task rewrites it), `live production-restart`, then `teardown`. Expected: every class and check passes.
- **Never on slot B:** `CommandsInProduction` (no production there), `Test.Demo.Production`, `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` (Rule 21).

**Planned mutations (Rule 19).** For each, the implement stage applies the mutation, records `mutation: … → …` here, and restores a byte-identical tree.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Routing | `StartWatch` routed to `ReminderOps` | `TestRoutes` |
| Key pass-through | the dismissal's `IncidentCommand` built without `IdempotencyKey` | `TestRoutes` |
| Thread | `CommandsIn` ignores `ThreadSessionId` | `TestThread`; `TestTraceAndThread` |
| SuperSession | no `TraceRef` lookup outside a context | `TestSuperSessionFromSession`; `TestTraceAndThread` |
| Tool | `SetDemoMode` added to `TOOLVERBS` | `TestToolGovernanceRefused`; `TestGovernanceRefusedFromTool` |
| Context means tool | the effective origin read from the payload only | `TestContextMeansTool` |
| Own incident | the tool `Dismiss` check skipped | `TestToolDismissOwnIncident`; `TestToolDismissReachesIncidentManager` |
| Settings origin | `SetDemoMode` accepted from `web_user` | `TestOriginRules` |
| Pairing origin | `Pair` accepted from `web_user` | `TestOriginRules` |
| Changes nothing | a refused command still sent | `TestToolGovernanceRefused` (the owner records a call) |
| Stub owner | `CommandsIn` returns the owner's error status | `TestStubOwner`; `TestStubOwnersAnswerPlainEnglish` |
| Owner failure | an answer that isn't a `CommandResult` returned as it is | `TestOwnerFailure` |
| Built | `STUB` left on `CommandsIn` | `TestStubsAnswer` |

**Task 0 results** (implement stage, tag `e2s23i`, first run of `ci/iris.sh class OcuTalon.Test.Core.CommandsInProduction`, read from deliberately failing `MEASURE` assertions that were removed afterwards):
1. `OcuTalon.Production` runs in the class's throwaway: the guard passed and all four tests ran.
2. Each of the five stub owners leaves a response header as well as the request header. For ReminderOps, WatchOps, SettingsOps, SessionOps and IncidentManager alike, the synchronous send leaves the request header `CommandsIn` to the owner (Type 1, Status 8 Error, IsError 0) and a response header from the owner to `CommandsIn` (Type 2, Status 9 Completed, IsError 1, carrying the owner's error), both in one session. `TestTraceAndThread` and `TestStubOwnersAnswerPlainEnglish` assert that form: one response header, `IsError` 1, from the owner to `CommandsIn`, in the request's session and SuperSession. (For `IncidentManager`, a process, the response header is id 12 and id 11 is not in the session's SuperSession; nothing asserts on it.)
3. The joined command's request header has `SessionId` = the context's `ThreadSessionId`: the second `ListReminders` in a context with `ThreadSessionId` = the first header's `SessionId` has its request and response headers in that session, with SuperSession = A's `TraceRef`.

**Implement-stage results.**
- Slot B (`ocutalon-slot-b`, build 154U): `iris_doc_load` of `src/bridge/cls` and `src/ocutalon/cls` compiled with 0 errors. `CommandsRouting` 10 of 10, `Test.Core.Commands` 4 of 4, `CommandsContext` 2 of 2, `Msg.Contracts` 6 of 6, `Contract.Ac` 6 of 6, `Data.Ownership` 10 of 10. Slot B holds no fixture row afterwards (no `zz` session, incident or check; no `^OcuTalonTest("Fixture")`; the routing runs are removed and the log rows of the throw test deleted).
- `test-class-rules.sh`, `test-boundaries.sh` and `test-ci-config.sh` exit 0; `ALLOW_UNCHECKED` is unchanged.
- Throwaway `e2s23i`: `CommandsInProduction` passed (and it was red for each mutation below that only it can see); `Test.Install.Production` passed (`TestStubsAnswer` with `CommandsIn` stub 0); `Test.Demo.Production` passed (`RemoveMessages` moved). `ci/iris.sh classes lane-b` lists 28 classes, `CommandsRouting` and `CommandsInProduction` among them. Then `teardown` on `e2s23i` (0 left).
- Review pass (lead, after the layers; tag `e2s23i`, torn down with 0 left): the loop lines were run again on the patched tree (slot B compile 0 errors and the six classes green; the three static scripts exit 0; throwaway `CommandsInProduction`, `Test.Install.Production` and `Test.Demo.Production` pass). The once lines passed: `ci/checks.sh` exit 0; `shard lane-b` 28 classes passed; `shard lane-a` 9 classes passed; `live production` all checks passed, including row 17 with its 4 values (`submit-user`, `submit-tool`, `submit-zz`, `commandsin-sent`); `live production-restart` all checks passed.

**Observed mutations (Rule 19).** Each applied to `CommandsIn.cls`, observed, and restored to a byte-identical file (`shasum` 0e06fc0d...). A throwaway-only test was observed on a throwaway; a mutation marked "slot B" on slot B.
- mutation: `StartWatch` routed to `ReminderOps` -> `TestRoutes` red (slot B: "StartWatch goes to WatchOps").
- mutation: the dismissal's `IncidentCommand` built without `IdempotencyKey` -> `TestRoutes` red (slot B: "Dismiss: the key arrives unchanged").
- mutation: `ThreadSessionId` ignored -> `TestThread` red (slot B: "in the thread session of the context"); `TestTraceAndThread` red (throwaway: "the second is in the same session as the first", "and so is its answer").
- mutation: no `TraceRef` lookup outside a context -> `TestSuperSessionFromSession` red (slot B); `TestTraceAndThread` and `TestStubOwnersAnswerPlainEnglish` red (throwaway: no header carries A's `TraceRef`).
- mutation: `SetDemoMode` added to `TOOLVERBS` -> `TestToolGovernanceRefused` red (slot B: "SetDemoMode from a tool says so"); `TestGovernanceRefusedFromTool` red (throwaway: "SetDemoMode from a tool: and the text says it can't be done from the chat"). The origins table still refuses it, as a second layer, so only the text shows the change; hence the text assertion in `TestGovernanceRefusedFromTool` (Decided in-stage 15).
- mutation: effective origin read from the payload only -> `TestContextMeansTool` red (slot B, four assertions).
- mutation: the tool `Dismiss` check skipped -> `TestToolDismissOwnIncident` red (slot B: every refusal case); `TestToolDismissReachesIncidentManager` red (throwaway: "it is not_found", "and no header went to IncidentManager").
- mutation: `SetDemoMode` accepted from `web_user` -> `TestOriginRules` red (slot B: "SetDemoMode from 'web_user' sends nothing", "is not_allowed", "says why").
- mutation: `Pair` accepted from `web_user` -> `TestOriginRules` red (slot B).
- mutation: a refused tool command still sent -> `TestToolGovernanceRefused` red (slot B: "nothing was sent to any owner").
- mutation: `CommandsIn` returns the owner's error status -> `TestStubOwner` red (slot B: "stub-op: the status is OK", "stub-bp: ..."); `TestStubOwnersAnswerPlainEnglish` red (throwaway: five "the status is OK" failures).
- mutation: an answer that isn't a `CommandResult` returned as it is -> `TestOwnerFailure` red (slot B: "wrong: the answer is a CommandResult"; the first version of the test failed with a property error, so the test now asserts the class first).
- mutation: `STUB` left on `CommandsIn` -> `Test.Install.Production:TestStubsAnswer` red (run on slot B at method level: "CommandsIn: OcuTalon.Core.CommandsIn does not carry STUB").
- The throwaway reds for the thread, tool-verb, own-incident and owner-status mutations came from one combined run (those four applied together); the `TraceRef` mutation had its own run. Each failing assertion names its own mutation.

**QA additions (Rule 19; QA stage, slot B `ocutalon-slot-b` build 154U, throwaway tag `e2s23q`).** The audit of the six ACs and the 14 matrix rows against the tests found four unpinned or unfalsifiable points; no product code changed.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/CommandsSubVerb.cls` (new helper, no Test methods, never saved): a `ListReminders` subclass for `TestSubclassOfVerbIsUnknown`.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` (changed; 12 tests, were 10):
  - new `TestContextDismissSeesOwnIncidentOnly`: inside a context, a `Dismiss` that says `web_user` is `not_found` for another session's incident and routed for the session's own. Before it, no test saw the Dismiss check being driven by the context: `TestToolDismissOwnIncident` sends `Origin` `tool` with no context, and the live tests go through `Submit`, which already stamps `tool`;
  - new `TestSubclassOfVerbIsUnknown` (matrix "Unknown", "a verb class not in the table"; Boundaries "matched by its exact class name"): a subclass of `ListReminders` is `unknown_command`, nothing sent;
  - `TestThread` gains a context with `ThreadSessionId` 0: no thread, a session of its own, still with the `SuperSession`. With the unset (empty) value alone, the `> 0` guard could be dropped without a red;
  - `TestOriginRules`, `TestToolDismissOwnIncident` and `TestUnknownCommand` now assert that `OnProcessInput` answers status OK for every refusal (`not_allowed`, `not_found`, `unknown_command`). `unknown_command` is unreachable through `Submit`, so only the unit class can pin its status.
- Each mutation was applied to `CommandsIn.cls`, loaded on slot B, observed red, restored; `shasum` of the file after each restore was `0e06fc0d...`, as before, and `git status --short` showed only the two QA test files.
- mutation: the tool `Dismiss` check keyed on the payload `Origin` instead of the effective origin (`command.Origin = "tool"`) -> `TestContextDismissSeesOwnIncidentOnly` red ("not_found for another session's incident inside a context", "nothing is sent", "to IncidentManager"); the other 11 tests, `TestContextMeansTool` and `TestToolDismissOwnIncident` included, stayed green.
- mutation: `Route` matches a verb by `%Extends` instead of the exact class name -> `TestSubclassOfVerbIsUnknown` red ("a subclass of a verb is unknown_command", "and it says so", "nothing was sent"); the other 11 stayed green.
- mutation: a `ThreadSessionId` guard of `'= ""` instead of `> 0` -> `TestThread` red ("a ThreadSessionId of 0 is no thread: the send starts a session of its own"); the empty-value assertion beside it stayed green, which is why the 0 case was added.
- mutation: a refusal answers an error status (`unknown_command`, `not_allowed` and `not_found` each) -> `TestOriginRules`, `TestToolDismissOwnIncident`, `TestUnknownCommand`, `TestSubclassOfVerbIsUnknown` and `TestContextDismissSeesOwnIncidentOnly` red (the "status is OK" assertions).
- Checked on tests left unchanged (each pinning test already had a line or none for these rows):
  - mutation: `IsStub` without the `#5003` text match (code match only) -> `TestStubOwner` red for `stub-bp` ("stub-bp: not_built", "and it says so"); `stub-op` stays green. A process stub's status carries the code `<Ens>ErrBPTerminated` alone (measured on slot B), so the text match is the only reason `stub-bp` is `not_built`.
  - mutation: the catch writes no `$$$LOGERROR` row -> `TestOwnerFailure` red ("throw: one event-log row from the service").
  - mutation: `Join` takes the `SuperSession` from the command's `SessionRef` when no `Session` row exists -> `TestSuperSessionFromSession` red ("with no SuperSession for session 'zzmissing...'" and `'instance'`).
  - mutation: `Join` takes the `SuperSession` from the `Session` row's `TraceRef` inside a context -> `TestThread` red ("with the SuperSession of the context", "which still carries the SuperSession").
  - mutation: the dismissal's `IncidentCommand` built without `SessionRef` and `Origin` -> `TestRoutes` red ("Dismiss: the session arrives unchanged", "Dismiss: the origin arrives unchanged").
- Results after the restore: slot B `CommandsRouting` 12 of 12, `Test.Data.Tables` 6 of 6, `Test.Msg.Contracts` 6 of 6, `Test.Msg.Catalog` 22 of 22, and slot B holds no fixture row, no `zz` session or incident, no `CommandsIn` event-log row, no context, and `onlineDemo` as it was. `bash ci/checks.sh` passes (`test-storage.sh` included, for the new persistent helper). Throwaway `e2s23q`: `shard lane-b` passed (28 classes), forward and `--reverse`; then `teardown` (0 left). `CommandsInProduction` is unchanged and passed in both shard runs.
- Not added, with the reason: a test that `CommandsIn` calls `Send` with `TIMEOUT` (the probe overrides `Send`; a timeout is an error status that takes the `failed` path `TestOwnerFailure` pins; reopen when Story 8.4 builds an owner that can sleep) and the "no `Trace.Join`" half of the thread AC (`Trace.Join` is Story 2.9, so there is nothing to call or to spy on yet).

**Code review (Rule 19; review stage, slot B `ocutalon-slot-b` build 154U, throwaway tag `e2s23r`).** The patches are listed under Review Findings.
- mutation: the tool `Dismiss` cross-check removed from `Carry` (a context's `SessionRef` no longer compared with its `OwnerRef`) -> `TestContextDismissSeesOwnIncidentOnly` red on slot B ("a Dismiss that names session B is not_found inside session A's context, though B can see the incident", "and nothing is sent for it"). It was restored from a copy: `shasum` 444c97d9... before and after, and `git status --short` and `git diff --stat` unchanged; then green again.
- Results on the patched tree: on slot B, the six changed classes compile with 0 errors and `CommandsRouting` passes 12 of 12; slot B holds no `ZZNS` incident or check and no probe log row. `bash ci/checks.sh` exits 0. On throwaway `e2s23r`: `shard lane-b` passes (28 classes, `CommandsInProduction` and `CommandsRouting` among them); `live production` passes every check, including row 17's 4 values; `teardown` leaves 0.

**Shared surfaces:**
- the oracle's `CommandsIn` row (`Test.Install.Production`; `test-production.sh` rows 14, 16 and 18 read it and skip pool-0 items);
- `test-production.sh` row 17 (this story's task; Epic 1 edits `:274-295` of the same file, so a conflict at integrate-forward is a plain union);
- the message headers, bodies and event-log rows of OCUTALON on throwaways (the live class removes its own; row 16 counts by delta);
- `Test.Data.Fixture` (new `RemoveMessages`, used by `Test.Demo.Production`);
- the `lane-b` shard's class list (two new `%UnitTest` classes);
- (QA) the helper `OcuTalon.Test.Core.CommandsSubVerb`, a persistent test message class that projects the table `OcuTalon_Test_Core.CommandsSubVerb` and is never saved (`Test.Data.Tables` and `test-storage.sh` were run with it);
- `onlineDemo` (saved and restored) and the test process's bridge context (ended before and after).

Every test added or changed passes on a fresh environment, in either order. The `%UnitTest` classes create and remove their own rows through `Test.Data.Fixture`, keep their records under their own `^OcuTalonTest` subtree, and restore every setting they change.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `CommandsIn` is the production's one command gate. It looks up each verb's owner and accepted origins in the `Routes` table (exact class name under `OcuTalon.Msg.Command.`), makes the origin `tool` whenever a bridge context is active, limits a tool to the six `TOOLVERBS` and to a `Dismiss` of an incident `Ownership.Incident` returns, joins the turn's thread or starts a session whose `SuperSession` is the command's session `TraceRef`, sends once through the private `Send`, and answers a plain-English `CommandResult` for every refusal, stub owner (`not_built`), owner failure (`failed`) and thrown error. Status is always OK once it has answered. `STUB` is gone from `CommandsIn`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`: the gate (table, origin rules, trace session, send, answer mapping, eight text parameters).
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls`: `Submit`'s doc comment states the status contract (body unchanged).
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls`: `CommandsIn` oracle row `stub` 0.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsOwner.cls`, `CommandsInProbe.cls` (new): the test owner and the probe that overrides `Send`.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` (new): ten slot-safe tests of routing, origin rules, tool limits, stubs, failures, thread and `SuperSession`.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` (new): four throwaway-only tests through `Commands.Submit` against the running production and its five stub owners.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`, `Test/Demo/Production.cls`: `RemoveMessages` moved into `Fixture` and `Test.Demo.Production` delegates to it.
- `docker/tests/test-production.sh`: row 17 only (`:16-17` and the row), now the plain-English `not_built` contract with a before-and-after `commandsin-sent` count.

**Review.** Four layers reported 40 findings (high 0, medium 3, low 32, false 1, maybe-false 4); the log above has one row each.
- Patches applied (2 groups): row 17's `commandsin-sent` now compares the count before and after the first `Submit` (medium; raised by three layers); `Submit`'s doc comment names a production that is shutting down or has `CommandsIn` disabled (low).
- Deferred (2, in the frontmatter `deferred:` list, both medium and unverified): the tool `Dismiss` is checked against the command's `SessionRef`, not the context's `OwnerRef` (settled by Story 1.10, the first tool submitter); `ProcessInput` kills the caller's job-local session id on exit (platform behaviour since Story 0.6; settled by a throwaway check, remedy with `Trace.Join`, Story 2.9).
- Rejected (32 rows, each with its reason in the log): spec-bound behaviour (origin forwarded unchanged, `SessionRef` trusted from the authenticated submitter, no event-log row for owner failures, the `#5003` stub contract, no key check at the gate, no visibility check for non-tool `Dismiss`); fail-closed or double-fault cases (the `Ownership.Incident` status, a throwing log write); throwaway helper hardening (`Fixture.RemoveMessages`); sanity-count and stub-bound assertions; coverage that needs a built owner (a real timeout, a real success answer; reopen when Story 8.4 builds the first owner); one false claim (every AC has a recorded mutation).

**Follow-up review recommended: false.** This pass patched one medium group and one low; no high.

**Verification.**
- Slot B (`ocutalon-slot-b`, build 154U): both source trees compile with 0 errors; `CommandsRouting` 10, `Test.Core.Commands` 4, `CommandsContext` 2, `Msg.Contracts` 6, `Contract.Ac` 6 and `Data.Ownership` 10 pass, twice (before the review and on the patched tree); slot B holds no fixture row.
- `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` exit 0 (`ALLOW_UNCHECKED` unchanged); `ci/checks.sh` exit 0.
- Throwaway `e2s23i` (torn down, 0 left): `CommandsInProduction`, `Test.Install.Production` (`TestStubsAnswer` with stub 0) and `Test.Demo.Production` pass; `shard lane-b` (28 classes) and `shard lane-a` (9 classes) pass; `live production` passes with row 17's four values; `live production-restart` passes.
- Matrix Test Audit: every row of the I/O & Edge-Case Matrix is covered by a test that ran and passed (`CommandsRouting` on slot B for the decision rows; `CommandsInProduction` and row 17 on the throwaway for the live rows).
- Thirteen planned mutations were applied, each observed red and reverted (recorded under `## Verification`).

**Residual risks.**
- No built owner exists, so a real owner's success answer across `SendRequestSync` and a real timeout are untested until Story 8.4 and the other owner stories rewrite their rows in `CommandsInProduction`.
- The two deferred items above.
- `TestOriginRules` takes about 22 s on slot B (80 shadow instances); on the CI runner it is about three times that.
