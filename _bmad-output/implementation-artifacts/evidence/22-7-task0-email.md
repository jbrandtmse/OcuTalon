# Story 22.7, Task 0: the approved send from FixExecutor's job, what the card makes of an email row, the array argument, the callback rule, an email run in Interrupt and Sweep, and the stub

Measured 2026-11-13, about 05:50 to 06:50 UTC, on one lane-D warm throwaway (run tag `e22s7iw`, started with `ci/warm.sh up`, ready in 112 s; the lead runs `ci/warm.sh down`). Scratch class `OcuTalon.Test.Fix.ZzT7Task0` (one method, `Item2`) was loaded for item 2 and removed afterwards; the other items are measured by the tests this story ships, named below. No real mail: the only mail server is the CI mock's SMTP stub (`mock:1025`).

## Verdict

**The stop rule does not fire.** Every answer is the one the spec assumed, with one finding for Story 21.11 (item 2): the stored dry run of an email row reaches the Live approval payload with `dryRun.to` as the text `2@%Library.DynamicArray` and no subject or text. It raises no error.

## 1. `Commands.Submit(SendEmail, "system")` from FixExecutor's job reaches EmailOut with origin system

- Test: `Test.Fix.Email:TestSeededApprovedRowSendsOnce`. A seeded approved row (kind `fix`, FixKind `email`, FixTargets `1,2`, FixParameters and DryRun with two recipients, no incident, ResultTarget `FixExecutor`) is handed to the real `FixExecutor` item as an `OcuTalon.Bridge.Msg.ApprovalOutcome` (`approved`) from the `SimMailboxIn` service.
- Result: the row ends `done`; the stub holds **1 mail**, to both recipients, with the row's subject; `Data.Delivery` holds **one row with the row's `ApprovalRef`**; the FixRun has an empty IncidentRef, Total 1, Resent 1, no reason.
- That the origin was `system` follows from two facts: `Core.Commands.Submit` takes the origin the caller names only when no bridge context is active (otherwise it forces `tool`), and EmailOut's `tool` path sends only to the one own address, while this mail went to two other addresses; and only the `system` path makes the claim row with an `ApprovalRef`. So no bridge context is active in that job.
- The same path is exercised by the unseeded flow (`TestRiskyTurnApprovedSendsOnce`: the gate's hook raises the row, `Approval.Answer` approves it, `ApprovalHold` sends the outcome): 1 mail, 1 claim row, the row `done`. This is DW-1164: the real `EmailOut` system path accepted a row that the product raised, with `FixParameters.recipients` as an array.

## 2. `Live.Payload.Approval.FromRow` and `Core.BridgeSink` `approval.raised` on an email row

Measured with `Fix.Kind.Email.Raise` (the default `HostSinkClass`, which is `Core.BridgeSink`) for an owner session with a mailbox, two recipients, subject `A subject`, text of two lines:

- `Raise` answered OK with a Ref and no refusal; `approval.raised` fired through the sink; **no error and no Type 2 or 3 log line** were written.
- `FromRow` returned a payload (no exception). Its JSON: `{"ref":"...","kind":"fix","state":"pending","fixKind":"email","dryRun":{"to":"2@%Library.DynamicArray","simulated":false,"eitherWay":false},"raisedAt":"...","expiresAt":"..."}`.
  - `fixKind` is `email`.
  - `dryRun.to` is the text of an object reference (`2@%Library.DynamicArray`), because `Part.DryRun.To` is a `%String` and the row's `to` is an array. `subject` and `text` are not in the payload at all (`Part.DryRun` has no such property). `incidentRef` is empty.
- The session's Live stream got one `approval` event with that payload (the same text).
- No `Data.Delivery` row for the approval exists (0): the web, phone and Telegram cards for a request with no incident are not produced by anything in this story.
- **For Story 21.11 (residual):** `Live/Payload/Approval.cls` and `Live/Payload/Part/DryRun.cls` (Lane B) must give an email row its own branch (the recipients as text, `subject`, `text`), as `partner_warning` has; until then the card would show the garbage `to`. This story does not edit them.

## 3. An argument of type `%DynamicArray` reaches the tool method as an array from the mock's `toolUse` input

- Test: `Test.Fix.Email:TestRiskyTurnApprovedSendsOnce` and `TestSafeTurn` (scenarios `send-email-other` and `send-email-own`, `toolUse.input.recipients` a JSON array). For the risky turn the stored `FixParameters` has `recipients` of JSON type `array` holding the one address (asserted with `%GetTypeOf`), and for the safe turn the SendEmail reaches the stub to the saved address.
- `Test.Agent.Instructions:TestToolsets` also runs `send_email` through a fresh `%AI.ToolMgr` with `{"recipients": ["..."], ...}` and gets NOSESSION from the tool body, so the array is bound to the `%DynamicArray` argument there too.

## 4. `CALLBACKHELPERS` with `OcuTalon.Core.SettingsOps` and `OcuTalon.Fix.Kind.Email`

- `OcuTalon.Core.SettingsOps` and `OcuTalon.Fix.Kind.Email` were added to `CALLBACKHELPERS`, and `TOOLVERBS` got `SendEmail`; `ci/iris.sh class OcuTalon.Test.Bridge.CodeRules` passed (1 class, 6 s).
- **Green: the Email kind validates addresses with `SettingsOps.IsAddress`.** The test counts the helpers it scanned against the length of `CALLBACKHELPERS`, so both new classes were compiled and scanned (no `%AI` on a code line, no Python). No copy of the address pattern is made.

## 5. `Fix.Run` `Interrupt` and `Sweep` with an email run that has no incident and no `EndedAt`

- Test: `Test.Fix.Email:TestInterruptedRunHasNoResult`: two executing email requests, each with a FixRun with no incident and no `EndedAt`; one started in 2020 (before the production's start), one now.
- `Interrupt` (unchanged): marks the old run (`Interrupted` above 0) and closes its request through `FinishExecution` with the result `interrupted`, which leaves the row `failed`; the run that started after the production's start is left, and its request stays `executing`. No problem is reported.
- `Sweep` before the change to `Fix.Run` (the mutation that removes the new guard): it returned **1 FixResult** (empty `IncidentRef`, for IncidentManager) and wrote the generic Action entry (the kind's name as action, an empty target), not the email kind's. With the guard: **0 FixResults**; the marked run is ended `interrupted` and the email kind's Action entry (action `email`, target `EmailOut`, result `interrupted`, the request's Ref) is written; the other run is left alone (no `ResentAt`); a second `Sweep` returns none.

## 6. The warm stack reaches the stub as `EmailLive` does

- `OCUTALON_TEST_PLAIN_SMTP=1` and `OCUTALON_MODEL_BASE_URL=http://mock:8080/v1/` in the IRIS container; the stub is host `mock`, SMTP 1025, control 8080 under `/_mock/smtp/`.
- `Test.Channel.EmailLive` (unchanged) passed on this stack (44 s), `Test.Channel.EmailOut` passed (11 s), and every send of `Test.Fix.Email` first asserts that EmailOut's `SMTPServer` row is `mock`.
