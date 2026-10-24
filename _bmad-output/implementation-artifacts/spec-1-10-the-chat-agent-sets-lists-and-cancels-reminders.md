---
title: 'Story 1.10: The chat agent sets, lists and cancels reminders'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: '1e05e8214391cde716e78185082fd3015bc38255'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, AD-2, AD-4, AD-6, AD-7, AD-9, AD-10, AD-18, AD-22, AD-29 and AD-33, and the Agent step labels, Tool results, Times, Identifiers and Tests rows of Consistency Conventions)'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      A JSON true given as delaySeconds reaches SetReminder as 1, so it sets a reminder one second ahead instead of being refused as not a whole number.
    evidence: |-
      AI Hub decodes the JSON value of an argument before the method runs (Task 0 (c)): true becomes 1, and "60", 60.0 and 1e3 become digits, so all pass the whole-number test (1.N).
      The tool cannot tell a decoded true from 1. The schema says integer, so a model has no reason to send a boolean, and a one-second reminder is a harmless misreading.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls (SetReminder)
    severity: low
  - summary: >-
      The tools pass the model's strings on without a bound, so a value longer than the command's field may fail when the real CommandsIn saves the message, and the model is told that the service did not answer.
    evidence: |-
      SetReminder.LocalDueAt is MAXLEN 19, Text 1000 and CancelReminder.ReminderRef 22, and delaySeconds has no upper bound (the whole-number check is 1.N). The double receives the object in process and never saves it, so no test here can see the effect.
      Closed as accepted, not scheduled (the owner checks everything but the delay's shape, decision 5). reopen_if: with Story 2.3's real CommandsIn, a localDueAt of 20 characters such as 2026-10-29T10:00:00Z, or a delaySeconds of 20 digits, gives NOTSENT instead of the owner's plain-English refusal.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls (SetReminder, CancelReminder)
    severity: low
  - summary: >-
      list_reminders is declared TrustedOutput, but it returns the text of reminders that the model wrote in earlier turns, possibly from untrusted content.
    evidence: |-
      The AC declares TRUSTEDOUTPUTLISTREMINDERS 1, and DW-136 asks only whether set and cancel become trusted. The reminder Text is model-authored (set_reminder's argument), so a later turn that lists it gets it back as trusted output.
      Unverified: it depends on how Epic 3's gate defines trusted output and taint. What would settle it: Story 3.1/3.3 decide whether a tool result that carries stored model-authored text is exempt from taint.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls (TRUSTEDOUTPUTLISTREMINDERS), src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls (Listed)
    severity: medium (unverified)
  - summary: >-
      Chat's ceiling of 4 iterations (AD-20) may be too low for a turn that lists and then cancels several reminders one call at a time, which would end as an unusable turn after the cancels were done.
    evidence: |-
      list, cancel, cancel, cancel and the final text are 5 model responses. Unverified: a real model may cancel several reminders in one response (the tools allow parallel calls), and the mock's scenarios stop at 3 iterations.
      What would settle it: a live run of a "cancel all my reminders" turn with three or more pending reminders (Story 8.4's live checks). Raising the ceiling amends AD-20's arithmetic (an AD change for the owner's veto window).
    location: >-
      src/ocutalon/cls/OcuTalon/Agent/Chat.cls (MaxIterations)
    severity: medium (unverified)
  - summary: >-
      The command key is only <ItemId>:<position>, so an owner that treats a repeated key as a repeat of the same command may answer a different command from the earlier one's result when a turn is run again with other tool calls.
    evidence: |-
      The position is the same on every run only when the model repeats the same calls, which the scripted mock guarantees. Unverified: it depends on how Story 8.4's owner de-duplicates (by key alone, or by key and verb and payload).
      What would settle it: Story 8.4's design, which should compare the verb and the fields on a reused key, or refuse the reuse.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls (Run), src/bridge/cls/OcuTalon/Bridge/Context.cls (CommandCount)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:**
- **Chat has no tools.** `OcuTalon.Agent.Chat` declares no `TOOLSETS`, so a user who asks "Remind me in 1 minute to stretch." gets words and nothing happens. The reminder tool names exist only as constants (`OcuTalon.Tools.Names`).
- **No tool submits a command yet.** Nothing turns a tool call into an `OcuTalon.Msg.Command` verb with origin `tool`, the session's `SessionRef` and an `IdempotencyKey` (AD-1), and nothing answers the model with the owner's `CommandResult`.
- **Every real tool step reads "Running a tool"** in Visual Trace, because no shipped tool class declares a step label and nothing fails one that lacks it (DW-85).
- **Lane A holds four copies of the process-zone save and restore** in its tests (`Test.Agent.Render`, `Test.Bridge.Time`, `.Usage`, `.Budget`), and this story adds zone tests (DW-32).

**Approach:**
- **Three tools on Chat.** A new toolset, `OcuTalon.Tools.Reminders`, offers `set_reminder`, `list_reminders` and `cancel_reminder`, all methods of one new tool class, `OcuTalon.Tools.ReminderTools`, which extends `OcuTalon.Tools.Result`. Each tool declares its step label and its classification as class parameters.
- **One way to submit.** A small helper, `OcuTalon.Tools.CommandCall`, fills the verb's common fields from the bridge context and submits it through Epic 0's `OcuTalon.Core.Commands.Submit`. It shapes the `CommandResult` into a dynamic object for the model, with due times in the instance zone through `OcuTalon.Data.Time`.
- **Tested against a double.** `CommandsIn` is a stub until Lane B's Story 2.3, and `ReminderOps` until Epic 8. So the tests put a recording test double, `OcuTalon.Test.Tools.CommandsDouble`, behind the `CommandsIn` item, drive real turns through the CI mock, and read what the double received and what the model got back.
- **The two ledger items.** Step labels for every shipped tool (the watch fixture included), with a CodeRules scan (DW-85). One abstract zone base for Lane A's tests (DW-32).

## Boundaries & Constraints

**Always:**
- **The toolset (AD-7, AD-18).**
  - `OcuTalon.Tools.Reminders Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.ReminderTools ]`, on the pattern of `OcuTalon.Tools.Watch`.
  - Its `Definition` XData names exactly three tools, with the names of `OcuTalon.Tools.Names`: `set_reminder` (method `SetReminder`), `list_reminders` (`ListReminders`) and `cancel_reminder` (`CancelReminder`), all of class `OcuTalon.Tools.ReminderTools`.
  - It holds no `Requirement` element. The class parameters below are the one declaration.
  - `OcuTalon.Agent.Chat` gains `Parameter TOOLSETS = "OcuTalon.Tools.Reminders";`. Its `INSTRUCTIONS` do not change.
- **The tool class (AD-4, AD-9, AD-10).** `OcuTalon.Tools.ReminderTools Extends OcuTalon.Tools.Result`.
  - **The tools:**
    - `SetReminder(text, delaySeconds = "", localDueAt = "")`;
    - `ListReminders()`;
    - `CancelReminder(reminderRef)`.

    Each is a public class method that returns `As %DynamicObject` through `..Return(`. No tool takes a session, owner or origin argument.
  - **What the model reads:** each method's doc comment is its description, and each argument carries a `DESCRIPTION`. Together they tell the model the two due forms of `set_reminder`:
    - `delaySeconds` for a relative time ("in 10 minutes");
    - `localDueAt` for a day and time ("Thursday at 10"): a local date and time `YYYY-MM-DDThh:mm:ss` without a zone, worked out from the "Local time" line of the message.

    They also say that `cancel_reminder` takes the `ref` that `list_reminders` gave. No description or `DESCRIPTION` text starts with an SQL verb (`ToolCodeClean` flags such a string).
  - **Step labels:** one parameter per tool, by the step-label rule (`STEPLABEL` plus the tool's name in upper case, with `_` and `-` removed):
    - `STEPLABELSETREMINDER = "Setting a reminder"`;
    - `STEPLABELLISTREMINDERS = "Listing your reminders"`;
    - `STEPLABELCANCELREMINDER = "Cancelling a reminder"`.
  - **Classification:** declared for each tool by the same NAME rule, all explicit:

    | Tool | `CLASSIFICATION<NAME>` | `READONLY<NAME>` | `TRUSTEDOUTPUT<NAME>` |
    | --- | --- | --- | --- |
    | `set_reminder` | `safe` | 0 | 0 |
    | `cancel_reminder` | `safe` | 0 | 0 |
    | `list_reminders` | `safe` | 1 | 1 |

    Nothing reads these parameters until Epic 3's gate. Until then the three tools run in any turn.
  - **The due forms:** `SetReminder` sets `Text`, and `DelaySeconds` and `LocalDueAt` as the model gave them. It never sets `DueAt`.
    - A `delaySeconds` that is neither empty nor a whole number (pattern `1.N`) gets `{"ok": false, "message": <BADDELAY>}`, and nothing is submitted.
    - Every other check (empty text, a time already past, not exactly one due form, an unreadable `localDueAt`) belongs to the owner (Story 8.4), and its refusal reaches the model unchanged.
  - **The other two verbs:** `CancelReminder` sets `ReminderRef` from `reminderRef`. `ListReminders` sets no field of its own.
- **`OcuTalon.Tools.CommandCall` (new, a plain class; AD-1, AD-4, AD-6, AD-18).**
  - **`Run(command, Output result) As %DynamicObject`.** It returns `""` once the owner has answered, and puts the `CommandResult` in `result`.
    - **The context:** it needs an active bridge context whose `OwnerRef` is a session's Ref (22 base64url characters) and whose `ItemId` is not empty. Otherwise it submits nothing and returns `{"ok": false, "message": <NOSESSION>}`. So `instance`, `eval`, an empty owner and no context are all refused.
    - **The fields:** it sets `SessionRef` to the context's `OwnerRef`, and takes n as the context's `CommandCount` plus 1, writing n back with `Context.Put`. It sets `IdempotencyKey` to `<ItemId>:<n>`, and calls `OcuTalon.Core.Commands.Submit(command, "tool", .result)`. `Submit` sets the origin `tool`, because a context is active.
    - **A failure:** an error status, or a result that is not an `OcuTalon.Msg.CommandResult`, logs one Type 3 warning. The warning names the verb's class and holds the status text passed through `OcuTalon.Bridge.Redact.Text`. `Run` then returns `{"ok": false, "message": <NOTSENT>}`.
  - **`Answer(result) As %DynamicObject`:**
    - `ok`, a JSON boolean, from `Ok`;
    - `message`, the owner's `Message` unchanged;
    - and only when they are not empty: `ref`, from `Ref`; `due`, which is `Data.Time.ForMessage(DueAt)`; and `dueLocal`, which is `Data.Time.ToLocal(DueAt)`.

    The UTC time is never shown to the model.
  - **`Listed(result) As %DynamicObject`:**
    - **A refusal** (`Ok` 0) is `Answer(result)`.
    - **Otherwise** it reads `result.Data` (the list contract below) and gives `{"ok": true, "zone": Data.Time.Zone(), "reminders": [{"ref", "text", "due", "dueLocal"}, ...]}`, in the order of `Data`.
    - **A `Data` that cannot be read** is never an empty list: it logs one Type 3 warning and gives `{"ok": false, "message": <NOTREAD>}`.
  - **The model-facing texts** are ASCII class parameters: plain sentences for the model, never shown to the user as written.
    - `NOSESSION = "Reminders belong to the conversation of a signed-in session, and this call has none, so nothing was done."`
    - `NOTSENT = "The reminder service did not answer, so nothing was done."`
    - `NOTREAD = "The reminder list could not be read, so it is not known which reminders are pending."`
    - `BADDELAY = "delaySeconds must be a whole number of seconds, so nothing was done."` (in `ReminderTools`)
  - **The callback rule:** `CommandCall` names no AI Hub class and runs no Python (AD-6). It never names `OcuTalon.Data.Reminder`, its table or its globals, nor `OcuTalon.Schedule`.
- **The list contract** (the `Data` of `ListReminders`' `CommandResult`; recorded for Lane B's Story 8.4):
  - **The shape:** `{"reminders": [{"ref": "<Ref>", "text": "<Text>", "dueAt": "<UTC YYYY-MM-DDThh:mm:ssZ>"}, ...]}`;
  - **What it holds:** the command's session's `pending` reminders only, the earliest due first.
- **The bridge context (AD-1, AD-6).** `OcuTalon.Bridge.Context` gains `Property CommandCount As %Integer [ InitialExpression = 0 ]`. It is added to `FIELDS`, and `Begin` sets it to 0. Its doc says that a host's tools number the commands that they submit in one call with it. The doc names no other OcuTalon package (AD-2).
- **The watch fixture (DW-85).** `OcuTalon.Tools.WatchFixture` gains `STEPLABELREADFAILEDMESSAGES = "Reading the failed messages"`, `STEPLABELREADEVENTLOG = "Reading the event log"` and `STEPLABELREADITEMSETTINGS = "Reading the item settings"`. Nothing else in it changes.
- **The test double (`OcuTalon.Test.Tools.CommandsDouble Extends Ens.BusinessService`).** Its `OnProcessInput` does three things.
  - **It records each command:** it appends `$ListBuild(<verb class>, Origin, SessionRef, IdempotencyKey, <JSON of every property that is not empty, with its value>)` to `^OcuTalonTest("CommandsDouble", "calls", n)`, n counting from 1 in `^OcuTalonTest("CommandsDouble", "calls")`.
  - **It answers by verb:**
    - **`SetReminder`:** `Ok` 1, `Outcome` `created`, `Message` "The CI double set the reminder.", and its parameters `SETREF` (`zzReminderDouble000001`) and `SETDUEAT` (`2027-03-04T15:00:00Z`; in another year, so that `ForMessage` gives a dated form that does not depend on today's date) as `Ref` and `DueAt`;
    - **`CancelReminder`:** `Ok` 1, `Outcome` `cancelled`, `Message` "The CI double cancelled the reminder.", and the command's `ReminderRef` as `Ref`;
    - **`ListReminders`:** `Ok` 1, `Outcome` `listed`, an empty `Message`, and a `Data` of the list contract, read with SQL from the `OcuTalon_Data.Reminder` rows whose `SessionRef` is the command's and whose `State` is `pending`, by `DueAt` and then `Ref`;
    - **any other verb:** `Ok` 0, `Outcome` `not_handled`.
  - **It follows the modes that a test sets:**
    - `^OcuTalonTest("CommandsDouble", "refuse", <verb class short name>) = <message>` answers `Ok` 0, `Outcome` `refused`, and that `Message`;
    - `^OcuTalonTest("CommandsDouble", "data") = <text>` answers `ListReminders` with that `Data`;
    - `^OcuTalonTest("CommandsDouble", "fail") = 1` returns an error status.

  The test that sets a mode kills `^OcuTalonTest("CommandsDouble")`.
- **The swap (AD-22, Rule 21).** `Test.Agent.RunnerFixture` gains `UseItemClass(item, className, Output saved)` and `RestoreItemClass(item, saved)`.
  - **How:** they change the item's `ClassName` in the stored configuration (`Ens.Config.Production`), update the running production, and wait until every item runs. They go through the same path as `ChangeSettings`, which gains an optional class name, so the code is not copied.
  - **Where:** throwaways and CI only.
  - **When:** `Test.Tools.Reminders` puts the double behind `CommandsIn` at its first test and puts the stub back in `OnAfterAllTests`, also after a failure.
- **The mock (AD-22).** These new marker scenarios go under `ci/mock/scenarios/A/`, on the pattern of `steps-two-tools.json`. Each ends with the text reply shown.

  | Scenario | The tool replies, in order | The final text |
  | --- | --- | --- |
  | `reminder-set-relative` | `set_reminder` `{"text": "stretch", "delaySeconds": 60}` | `The CI mock set the reminder.` |
  | `reminder-set-local` | `set_reminder` `{"text": "load the new certificate", "localDueAt": "2026-10-29T10:00:00"}` | `The CI mock set the reminder.` |
  | `reminder-set-two` | one response with two `set_reminder` calls, `{"text": "stretch", "delaySeconds": 60}` and `{"text": "drink water", "delaySeconds": 120}` | `The CI mock set the reminders.` |
  | `reminder-list` | `list_reminders` `{}` | `The CI mock listed the reminders.` |
  | `reminder-cancel` | `list_reminders` `{}`, then `cancel_reminder` `{"reminderRef": "zzReminderStretch00001"}` | `The CI mock cancelled the reminder.` |

  If Task 0 (c) measures other argument names, the scenarios use those.
- **The zone base (DW-32).** `OcuTalon.Test.Bridge.ZoneCase Extends %UnitTest.TestCase [ Abstract ]`, with no `Test` method, so `ci/iris.sh` runs no class of it.
  - **What it holds:** `Property SavedZone`, `ClassMethod CurrentZone()` (the process zone, -1 for none) and `ClassMethod PutZone(saved)` (-1 becomes ""). `OnBeforeOneTest` saves the zone and `OnAfterOneTest` puts it back.
  - **Who extends it:** `Test.Agent.Render`, `Test.Bridge.Time`, `Test.Bridge.Usage`, `Test.Bridge.Budget` and the new `Test.Tools.Reminders`. They drop their own `SavedZone` and zone lines. A class that overrides a hook calls `##super(testname)`.
  - **Lane B's copies** (`Test.Data.Time`, `Test.Msg.Catalog`) stay as they are.
- **Logs and text.** Every new warning is Type 3 and passes `Redact.Text`. All new text in `src/` and `ci/` is ASCII (Rule 14).
- **Tests (Rule 19).** Every test puts back what it made:
  - its `Reminder` fixture rows, by `Ref`;
  - `^OcuTalonTest("CommandsDouble")`;
  - its `Decision`, `Usage` and `AgentStep` rows, by `ItemId`;
  - the AI sessions that its user turns saved, with their links (`SessionMark`, `DropSince`);
  - the context of an in-process call;
  - the process zone;
  - the `CommandsIn` item, through `RestoreItemClass`;
  - and the runners' keys, through `RestoreKeys`.

  Every user turn has an owner of its own.

**Never:**
- **The owner's work.** The tools never read or write the `Reminder` table and never call `ReminderOps` or anything in `OcuTalon.Schedule`. They never convert a time except through `OcuTalon.Data.Time`, and never return a pre-encoded JSON string.
- **Epic 3's work.** No tool-level check of provenance or taint: one gate decides every tool call (AD-10), and Epic 3 builds it.
- **Lane B's files.** Not one of them changes:
  - `OcuTalon.Core.*` (`Commands.Submit` is called; `CommandsIn` is read and swapped at run time only);
  - `OcuTalon.Msg.*`, `OcuTalon.Data.*` and `OcuTalon.Schedule.*`;
  - `Production.cls`;
  - `Test/{Core,Data,Msg,Contract,Web,Live,Demo}/**`;
  - the mock's code and its tests;
  - `ci/**` outside `ci/mock/scenarios/A/`.
- **Lane B's scenarios.** No scenario is keyed by the guide prompt: prompt scenarios belong to Lane B under `B/` (Story 8.4).
- **No new structures:** no new production item, table, global, event type, catalog key or test area, and no change to `ci/units.sh`, `BridgeExample` or `release/`.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Declarations (in process) | `Chat`'s `TOOLSETS`, the toolset's `%Discover()` (or its XData, Task 0 (d)), the parameters of `ReminderTools` | 1. **The names:** `TOOLSETS` is `OcuTalon.Tools.Reminders`, which offers exactly the three names of `Tools.Names`, each once, with `ReminderTools` as the provider.<br>2. **The labels:** each tool's label (`StepBuffer.LabelFor`) is its parameter, not the generic one.<br>3. **The classification:** as in the Boundaries table.<br>4. **The inputs:** `text`, `delaySeconds` and `localDueAt` for set; none for list; `reminderRef` for cancel. None names a session, owner or origin. | n/a |
| Set, relative (live, through `Decide`) | A user turn "Remind me in 1 minute to stretch. [[mock:reminder-set-relative]]" | 1. **The double:** it recorded one `SetReminder`, with origin `tool`, `SessionRef` = the `OwnerRef`, key `<ItemId>:1`, `Text` `stretch` and `DelaySeconds` 60, and no other field.<br>2. **The model:** the second request's tool result is `{"ok":true,"message":...,"ref":SETREF,"due":...,"dueLocal":...}`, with `due` and `dueLocal` from `Data.Time` for `SETDUEAT`.<br>3. **The answer:** the reply is the scenario's text (not a fallback).<br>4. **Visual Trace:** the decision's steps are model, tool ("Setting a reminder", whose summary names `set_reminder`) and model.<br>5. **The table:** the `Reminder` row count is unchanged. | OK |
| Set, day and time (live) | The input "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-set-local]]", rendered by `Agent.Input.Render` for a user item at a fixed Monday (`2026-10-26T14:00:00Z`) | 1. **The model's input:** the first request's user message starts with that preamble line.<br>2. **The command:** `LocalDueAt` `2026-10-29T10:00:00`, `DelaySeconds` empty, `Text` `load the new certificate`, and no `DueAt`. | OK |
| Set, refused (in process) | A context for owner A, with the double in `refuse` mode for `SetReminder` | `{"ok":false,"message":<the double's message>}`, with no `ref` or due time. | n/a |
| Cancel (live) | A pending row `zzReminderStretch00001` of owner A. A's turn "Cancel my reminder to stretch. [[mock:reminder-cancel]]". | 1. **The double:** `ListReminders` with key `:1`, then `CancelReminder` with `ReminderRef` `zzReminderStretch00001` and key `:2`.<br>2. **The model:** request 2's tool result lists that row; request 3's is the cancel answer.<br>3. **Visual Trace:** the steps carry "Listing your reminders" and "Cancelling a reminder". | OK |
| Cancel, refused (live) | The same, with the double refusing `CancelReminder` with "That reminder has already fired." | 1. **The model:** request 3's tool result is exactly `{"ok":false,"message":"That reminder has already fired."}`.<br>2. **The answer:** the reply is the scenario's text, its `Decision` is not a fallback, and the tool step's status is `ok`. | OK |
| List (live) | Rows of owner A: pending ones due `2027-03-04T15:00:00Z` and, sooner, `2027-03-02T09:00:00Z`, one fired, one cancelled. A pending row of owner B. All in 2027, so that `due` does not depend on today's date. A's turn "Which reminders do I have? [[mock:reminder-list]]". | 1. **The rows:** request 2's tool result holds A's two pending rows only, the sooner one first, each with its `ref`, its `text`, a `due` of `Data.Time.ForMessage` and a `dueLocal` of `Data.Time.ToLocal`.<br>2. **The zone:** `zone` is `Data.Time.Zone()`.<br>3. **The rest:** nothing of B, nor the fired or cancelled rows. | OK |
| List in a zone (in process) | Process zone `America/New_York`. Owner A's pending rows due `2026-10-31T14:30:00Z` and `2026-11-02T15:30:00Z` (either side of the change from daylight-saving time). | 1. **The times:** `dueLocal` is `2026-10-31T10:30:00` and `2026-11-02T10:30:00`, and `zone` is `America/New_York`.<br>2. **Not from the table:** with the double's `data` mode set to a reminder that no row holds, the tool returns exactly that reminder. | n/a |
| List, unreadable (in process) | The double's `data` is `not json`, then `{"items":[]}` | `{"ok":false,"message":<NOTREAD>}` both times, never an empty list, and one warning each. | n/a |
| Keys (live, straight to `ChatAgent`) | `reminder-set-two`. The same user turn (the same `ItemId`, owner and `DecisionRef`) is sent twice. | 1. **Each round:** two `SetReminder` commands, with the keys `<ItemId>:1` and `<ItemId>:2`.<br>2. **Round 2:** it records the same two keys as round 1. | OK |
| No session (in process) | Each tool with no context, and with a context whose `OwnerRef` is `instance`, `eval` or empty, or whose `ItemId` is empty | `{"ok":false,"message":<NOSESSION>}`, and the double records nothing. | n/a |
| Submit fails (in process) | The double in `fail` mode | `{"ok":false,"message":<NOTSENT>}`, and one Type 3 warning that names the verb's class. | n/a |
| Bad delay (in process) | `delaySeconds` `abc`, `1.5` or `-5` | `{"ok":false,"message":<BADDELAY>}`, and nothing is submitted. | n/a |
| Runners (live) | Chat's requests, and `ChatAgent`'s `ToolInventory` | 1. **The requests:** each offers exactly `cancel_reminder,list_reminders,set_reminder`.<br>2. **The inventory:** each tool's provider is `ReminderTools` and its code is clean.<br>3. **The cache marker:** as Task 0 (e) measured. | OK |
| The scans | The product classes | 1. **Step labels (DW-85):** every tool of every shipped tool class of `OcuTalon.Tools` has a label of its own, the watch tools included; the probe tool, which has none, is flagged first.<br>2. **The `Reminder` table:** no class of `OcuTalon.Tools` names `OcuTalon.Data.Reminder`, its table or global, or `OcuTalon.Schedule`; a sample that does is flagged first.<br>3. **Return:** `ReminderTools` returns only through `..Return(`.<br>4. **The callback rule:** it covers `CommandCall`, `Bridge.Redact` and the Lane B classes that the tools call. | n/a |
| The zone base (DW-32) | `ZoneCase` with "no zone" and with a named zone. The four folded classes. | 1. **The base:** `PutZone(CurrentZone())` puts back "no zone" (-1) and a named zone.<br>2. **The folded classes:** each extends `ZoneCase` and declares no `SavedZone` of its own. | n/a |

</intent-contract>

## Code Map

- **AI Hub (read only, `irislib/`):**
  - **`%AI/ToolSet.cls`:** `%Discover()` (:119) and `%Invoke` (:146) are generated from the `Definition` XData. A class with no XData falls back to method scanning.
  - **`%AI/Tool/Generator.cls`:**
    - `GenerateDiscover` (:19-120): only public, non-`%`, non-abstract methods that originate in the class are tools;
    - the description is the method's doc comment (:43-58);
    - an argument's `DESCRIPTION` type parameter becomes its schema description (:79-89), and an argument with no default is required (:90).
- **Epic 0 contracts (Lane B, read only):**
  - **The verbs:**
    - `Msg/Command.cls:9-15`: `Origin`, `IdempotencyKey` (MAXLEN 128) and `SessionRef`;
    - `Msg/Command/SetReminder.cls:6-15`: `Text`, `DueAt`, `DelaySeconds` and `LocalDueAt`;
    - `Msg/Command/CancelReminder.cls:6`: `ReminderRef`;
    - `Msg/Command/ListReminders.cls`: the inherited fields only.
  - **The answer:** `Msg/CommandResult.cls:6-21`: `Ok`, `Message`, `Outcome`, `Ref`, `DueAt` and `Data` (JSON).
  - **The way in:** `Core/Commands.cls:14-33`: `Submit` sets the origin `tool` when `Bridge.Context.Active()`, then `CreateBusinessService("CommandsIn")` and `ProcessInput`.
  - **The stubs:** `Core/CommandsIn.cls:7-12` ("not implemented" until Story 2.3) and `Schedule/ReminderOps.cls` (a stub until Epic 8).
  - **The `CommandsIn` item:** `Production.cls:52` (Lane B's region, `PoolSize="0"`), whose class Lane B's `Test/Core/ProductionItems.cls:24` checks.
  - **The table:** `Data/Reminder.cls`: `Ref` (a unique index), `SessionRef`, `Text`, `DueAt`, `State` (`pending`, `fired` or `cancelled`), `Late` and `CreatedAt`; SQL `OcuTalon_Data.Reminder`; the global `^OcuTalonP.Reminder` (:6).
  - **The times:** `Data/Time.cls`: `ToLocal` (:22), `ForMessage` (:34) and `Zone` (:52).
  - **The preamble:** `Agent/Input.cls`: `Render(item, now)` (:15) and `Preamble` (:37).
  - **The names:** `Tools/Names.cls:6-10`: `set_reminder`, `list_reminders` and `cancel_reminder`.
  - **The other lane's spike:** `docker/tests/test-production.sh:185-193` (Lane B) submits `ListReminders` to the stub under a context. It is unaffected.
- **The bridge (Lane A):**
  - **`Context.cls`:** `FIELDS` (:11), `Begin` (:50-65), `Current` (:80) and `Put` (:92).
  - **`Adapter/StepBuffer.cls`:** `LabelFor` (:154-166), with the NAME rule, and `GENERICLABEL` (:22).
  - **`Policy/StepAudit.cls:14-27`:** a tool step's class is `metadata.origin_class`.
  - **`Adapter/Agent.cls`:** `AnswerLinked` (:317) and `Converse` (:361), where the context is active around `Chat`.
  - **`Redact.cls:43`:** `Text`.
  - **`Ids.cls:7`:** `NewRef`.
- **OcuTalon (Lane A):**
  - **`Tools/Result.cls:35`:** `Return`.
  - **The patterns:** `Tools/Watch.cls` (the toolset) and `Tools/WatchFixture.cls:9-24` (the methods).
  - **The agents:** `Agent/Chat.cls`, with no `TOOLSETS` and `MaxIterations` 4 (:13), and `Agent/Diagnosis.cls:13`, the `TOOLSETS` pattern.
- **The mock (Lane B's code; Lane A adds files under `A/` only):**
  - **`ci/mock/mock.mjs:13-27`:** a marker wins over a guide prompt, and the reply index is the number of assistant messages after the newest user text. The replies are scripted, and a tool result is never echoed.
  - **`ci/mock/scenarios.mjs:11-15`:** the scenario format.
  - **`ci/mock/test/constants.test.mjs:82`:** checks the tool names of `mockkey` scenarios only.
- **CI:** `ci/iris.sh:112-119`, `is_test_case`: a class with no `Method Test`, or an `Abstract` one, is not run.
- **Tests (Lane A, `src/ocutalon/cls/OcuTalon/Test/`):**
  - **`Agent/RunnerFixture.cls`:**
    - `Send` (:211), `NewRequest` (:225), `Ask` (:243), `ReadyReason` (:255), `DecisionOf` (:264), `StepsOf` (:284), `DeleteSteps` (:298) and `Run` (:327);
    - `PointKeys` and `RestoreKeys` (:405, :412), `UseItemSetting` (:563) and `ChangeSettings` (:500-530, the path to extend);
    - `SessionMark` and `DropSince` (:788, :795), `FindRequests` (:843), `Messages` (:855), `ToolNames` (:875), `ToolResults` (:894) and `Warnings` (:962).
  - **`Agent/Runners.cls`:**
    - `TestRequestsUnderTheModelRules` (:250-286, Chat at :282);
    - `TestToolInventory` (:288-328: `expected("ChatAgent")` at :295, the provider check at :323);
    - `AssertRequests` (:454-485, the marker at :466-474) and `OfferedTools` (:487).
  - **`Agent/Instructions.cls`:** `TestToolsets` (:83-111, "Chat has no toolset" at :86).
  - **`Agent/RequestSize.cls`:** the pattern of a live class: the hooks (:52-91) and `Prepare` (:239).
  - **`Tools/Result.cls`:** the in-process context: `Begin` (:333), `NewRequest` (:405), `Guard` (:421) and `Decoded` (:397).
  - **`Bridge/CodeRules.cls`:**
    - the header (:1-30), `CALLBACKBASES` and `CALLBACKHELPERS` (:34-37);
    - `TestCallbackRule` (:91-125), `TestToolsReturnThroughResult` (:252-308, the provider loop at :287-303), `TestToolCodeScan` (:350), `ToolCodeClean` (:402), `ToolProblem` (:523) and `ClassExtends` (:561);
    - the pattern of the reminder table scan: `TestToolsReturnThroughResult`, with `Source.Matches`.
  - **`Bridge/Source.cls`:** `Text` (:9), `CodeLines` (:16) and `Matches` (:47).
  - **The pattern of a shared record:** `Bridge/ProbeSink.cls:26-29` and `RunnerFixture.SinkCalls` (:706).
  - **The zone copies:** `Agent/Render.cls:17-36`, `Bridge/Time.cls:16-29`, `Bridge/Usage.cls:39-52` and `Bridge/Budget.cls:62-63, 78-101`.
  - **`Bridge/Ext.cls:230-240`:** what `Begin` starts the fields at.
  - **The unlabelled probe tool:** `Bridge/ProbeTool.cls`. **The labelled sample:** `Bridge/StepsNote.cls`.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **The target.** Throwaway tag `e1s10a` with the CI mock. Slot A (`ocutalon-slot-a`, namespace `OCUTALON`, after `iris_server_info` shows build 154) is only for compiles and for facts that need no production.
- **(a) The swap.** `RunnerFixture.UseItemClass("CommandsIn", "OcuTalon.Test.Tools.CommandsDouble")`:
  - **What to measure:** that `CreateBusinessService("CommandsIn")`, from the test job and from `ChatAgent`'s job, then creates the double, and that `RestoreItemClass` gives the stub back ("not implemented"); and the time of each swap.
  - **The fallback:** if `UpdateProduction` does not apply the class, the helpers stop and start the production around the swap, and the cost is recorded.
  - **Stop:** if neither applies it, stop with status `blocked` and the condition `TOOLING: the CommandsIn double cannot be put behind the item, measured <fact>`.
- **(b) A command from inside a tool.** A live `reminder-set-relative` turn:
  - **What to measure:**
    - `Submit` from the tool, inside AI Hub's callback in `ChatAgent`'s job, returns the double's answer, with no hang and no error, and the context is active (the origin is `tool`);
    - the runner's reply and the `AgentStep` messages stay in the decision's session (`RunnerFixture.SessionOf`).
  - **Stop:** otherwise stop with status `blocked` and the condition `intent gap: AD-1 (a safe tool submits through CommandsIn), measured <fact>`.
- **(c) The arguments.** For the inputs of the five scenarios, what each method argument receives: an omitted one, a JSON number into `%Integer`, and the argument names that the schema exposes. `delaySeconds` is `%Integer` unless this shows that `%String` is needed. The scenarios use the exposed names.
- **(d) The scan's source.** Whether a toolset's `%Discover()` gives each `<Tool>` entry's provider class. If it does not, the label scan reads the provider and the name from the `Definition` XData's `<Tool>` elements.
- **(e) Chat's request.** `RequestSize.AgentChars("OcuTalon.Agent.Chat")` with the tools, the tool names that the mock logs, and whether Chat's last tool carries the cache marker. `AssertRequests` expects for Chat what this shows.
- **(f) The fixture rows.** A `Reminder` row can be saved and deleted by the test, in the throwaway.
- **Other facts.** If any fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Context.cls`:** `CommandCount` (the property and `FIELDS`), 0 at `Begin`, and the doc. Rationale: AD-1, AD-6.

**OcuTalon.**
- **`src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls`** (new; needs the context field above): `Run`, `Answer`, `Listed`, `NOSESSION`, `NOTSENT` and `NOTREAD`, with the `Ensemble` include for `$$$LOGWARNING`. Rationale: AD-1, AD-4, AD-18.
- **`src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls`** (new; calls `CommandCall`): the three tools, their labels, classification, descriptions and `BADDELAY`. Rationale: AD-1, AD-4, AD-9, AD-10, AD-18, FR-34.
- **`src/ocutalon/cls/OcuTalon/Tools/Reminders.cls`** (new; `DependsOn` the tool class): the toolset. Rationale: AD-7.
- **`src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls`:** the three labels (DW-85). Rationale: AD-9.
- **`src/ocutalon/cls/OcuTalon/Agent/Chat.cls`:** `TOOLSETS` and the class doc. Rationale: AD-7.

**CI.**
- **`ci/mock/scenarios/A/reminder-set-relative.json`, `reminder-set-local.json`, `reminder-set-two.json`, `reminder-list.json` and `reminder-cancel.json`** (new): as in Boundaries. Rationale: AD-22.

**Tests.**
- **`Test/Bridge/ZoneCase.cls`** (new), and **`Test/Agent/Render.cls`, `Test/Bridge/Time.cls`, `Usage.cls` and `Budget.cls`:** the fold. Each class extends `ZoneCase`, drops its own `SavedZone` and zone hooks, and calls `##super` where it keeps a hook. `Test.Bridge.Time` gains `TestZoneCase` (the zone base row). Rationale: DW-32, Rule 2.
- **`Test/Tools/CommandsDouble.cls`** (new): as in Boundaries. Rationale: AD-1, AD-22.
- **`Test/Agent/RunnerFixture.cls`:** `UseItemClass` and `RestoreItemClass` through `ChangeSettings` (an optional class name), and the header. Rationale: Rule 2.
- **`Test/Tools/Reminders.cls`** (new; extends `ZoneCase`; needs the double and the two helpers above). The live tests follow `Test.Agent.RequestSize` (`Prepare` with `ReadyReason`, `PointKeys` once, then the swap once), and the in-process tests follow `Test.Tools.Result` (a context begun in the test process). The tests:
  - `TestDeclarations`;
  - `TestSetRelative`, `TestSetLocal` and `TestSetRefused`;
  - `TestCancel` and `TestCancelRefused`;
  - `TestList`, `TestListInZone` and `TestListUnreadable`;
  - `TestKeys`;
  - `TestNoSession`, `TestSubmitFails` and `TestBadDelay`.

  `OnAfterOneTest` and `OnAfterAllTests` put back everything that Boundaries lists. Rationale: Rule 19.
- **`Test/Bridge/CodeRules.cls`:**
  - **The helpers:** `CALLBACKHELPERS` gains `OcuTalon.Tools.CommandCall`, `OcuTalon.Bridge.Redact`, `OcuTalon.Core.Commands`, `OcuTalon.Core.CommandsIn` and `OcuTalon.Data.Time`.
  - **New `TestToolsHaveStepLabels` (DW-85):** every tool of every class of `OcuTalon.Tools` that extends `%AI.Tool` (toolsets and providers; `Result` left out) gets a label from `StepBuffer.LabelFor(<provider>, <name>)` that is not `GENERICLABEL`. `Test.Bridge.ProbeTool` is flagged first, and `StepsNote` passes.
  - **New `TestToolsLeaveRemindersToTheirOwner`:** the reminder table scan, with its samples.
  - **Changed:** `TestToolsReturnThroughResult` also expects `ReminderTools`, and `TestToolCodeScan` finds `ReminderTools` and `CommandCall` clean.
  - **One helper** lists the tool classes for both scans. And the header.

  Rationale: AD-6, AD-9, AD-10, Rule 2.
- **`Test/Agent/Runners.cls`:**
  - Chat's literal `cancel_reminder,list_reminders,set_reminder`;
  - `TestToolInventory` expects the reminder names for `ChatAgent`, and a provider for each name (the watch fixture or `ReminderTools`);
  - `AssertRequests` takes each agent's expected marker (Task 0 (e));
  - the header.
- **`Test/Agent/Instructions.cls`:** `TestToolsets`: Chat has `OcuTalon.Tools.Reminders`. A fresh tool manager discovers its three tools, each once. `ExecuteTool` with no context gives the `NOSESSION` object for each. And the header.
- **`Test/Bridge/Ext.cls`:** `Begin` starts `CommandCount` at 0.
- **Coverage.** These tests prove every matrix row.

**Acceptance Criteria:**
- **AC1, the tools on Chat (FR-34, AD-4, AD-7, AD-9, AD-10, AD-18).**
  - **Given** Chat's toolsets,
  - **when** the package compiles,
  - **then:**
    - Chat offers exactly `set_reminder`, `list_reminders` and `cancel_reminder`, the names of `OcuTalon.Tools.Names`, from `OcuTalon.Tools.Reminders`;
    - each is a method of `OcuTalon.Tools.ReminderTools` and declares its step label as a class parameter;
    - none takes a session argument (the `SessionRef` comes from the bridge context);
    - each returns a dynamic object through `OcuTalon.Tools.Result`.

  (`Test.Tools.Reminders.TestDeclarations`; `Test.Agent.Instructions.TestToolsets`; `Test.Agent.Runners` `TestRequestsUnderTheModelRules` and `TestToolInventory`; `Test.Bridge.CodeRules.TestToolsReturnThroughResult`)
- **AC2, the classification (FR-7, AD-10).**
  - **Given** `ReminderTools`' parameters,
  - **when** they are read by the step-label NAME rule,
  - **then:**
    - set and cancel are `safe`, not read-only and not trusted output;
    - list is `safe`, read-only and `TrustedOutput`;
    - until Epic 3's gate lands, nothing denies them: they run in a user's turn with no gate.

  (`Test.Tools.Reminders.TestDeclarations`; the live tests of AC3, AC5 and AC6 run them)
- **AC3, set (Integration AC: the Chat agent's runner calls the tool, and the model API reads its answer; FR-34, AD-1, AD-18).**
  - **Given** a user turn "Remind me in 1 minute to stretch." or "Remind me Thursday at 10 to load the new certificate." (marker scenarios under `ci/mock/scenarios/A/`),
  - **when** the Chat agent calls `set_reminder`,
  - **then:**
    - the tool submits one `SetReminder` through `OcuTalon.Core.Commands.Submit`, with origin `tool`, the `Text`, exactly the one due form that the model gave (`DelaySeconds`, or `LocalDueAt` worked out from the preamble's local time), the session's `SessionRef` and the key `<ItemId>:<position>`;
    - the model's next request carries the owner's `CommandResult` as the tool's answer: `ok`, `message`, and the reminder's `ref` and due time in the instance zone, or the plain-English refusal;
    - the tool writes no `Reminder` row.

  (`Test.Tools.Reminders` `TestSetRelative`, `TestSetLocal` and `TestSetRefused`; `Test.Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner`)
- **AC4, only the fixed fields (AD-1, AD-29).**
  - **Given** each tool,
  - **when** it submits,
  - **then:**
    - the command sets only the fields that Story 0.4 fixes for its verb (`Text`, `DelaySeconds`, `LocalDueAt`; `ReminderRef`; none for `ListReminders`) and `Origin`, `IdempotencyKey` and `SessionRef`;
    - no tool sets `DueAt`.

  (the double's records in `TestSetRelative`, `TestSetLocal`, `TestCancel` and `TestList`)
- **AC5, cancel (FR-34, AD-1).**
  - **Given** a pending reminder of the session and the turn "Cancel my reminder to stretch." (a scenario that lists, then cancels by `Ref`),
  - **when** the Chat agent calls `cancel_reminder`,
  - **then:**
    - the tool submits `CancelReminder` with that `Ref` as its `ReminderRef` and its own key;
    - the `CommandResult`, a plain-English refusal included, reaches the model unchanged as the tool's answer.

  (`TestCancel`, `TestCancelRefused`)
- **AC6, list (FR-34, AD-1, AD-4, AD-18).**
  - **Given** fixture pending, fired and cancelled `Reminder` rows in two sessions, and the double answering `ListReminders` from them the way `ReminderOps` will (the list contract),
  - **when** the list tool runs in one session's turn,
  - **then:**
    - it submits `ListReminders` through `Commands.Submit` and never reads the `Reminder` table;
    - it returns only that session's pending reminders, each with its `ref`, its text and its due time in the instance zone through `OcuTalon.Data.Time`;
    - an answer it cannot read is a failure, never an empty list.

  (`TestList`, `TestListInZone`, `TestListUnreadable`; `Test.Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner`)
- **AC7, the double (FR-3, FR-34, AD-1, AD-9).**
  - **Given** the `CommandsIn` test double in `OcuTalon.Test.Tools`, which records each command and answers with a fixture `CommandResult`,
  - **when** the tool tests run against the mock,
  - **then:**
    - every command carries origin `tool`, the session's `SessionRef` and its `IdempotencyKey`;
    - a re-sent turn submits the same keys;
    - each tool call is an agent step in Visual Trace with its label;
    - a refusal from the double reaches the model as the owner's plain-English reason, and the turn ends in a normal reply (decision 9).

  (`TestSetRelative`, `TestCancel`, `TestKeys`, `TestCancelRefused`)
- **AC8, nothing without a session's turn, and plain failures (decisions 4, 5 and 8).**
  - **Given** a reminder tool,
  - **when** it runs with no bridge context, or with a context whose `OwnerRef` is not a session's Ref or whose `ItemId` is empty; or when its submit fails; or, for `set_reminder`, with a `delaySeconds` that is not a whole number,
  - **then:**
    - without a session's turn, it submits nothing and answers `NOSESSION`;
    - after a failed submit, it answers `NOTSENT` and logs one warning that names the verb;
    - with such a `delaySeconds`, it answers `BADDELAY` and submits nothing.

  (`TestNoSession`, `TestSubmitFails`, `TestBadDelay`)
- **AC9, step labels (DW-85; AD-9).**
  - **Given** every shipped tool class of `OcuTalon.Tools`,
  - **when** `Test.Bridge.CodeRules` scans them,
  - **then:**
    - every tool that each offers has a step label of its own, the watch fixture's three tools included;
    - a tool with none fails the scan.

  (`Test.Bridge.CodeRules.TestToolsHaveStepLabels`)
- **AC10, one zone base (DW-32).**
  - **Given** Lane A's test classes that change the process zone,
  - **when** they run,
  - **then:**
    - they save and restore it only through `OcuTalon.Test.Bridge.ZoneCase`, which puts back a named zone and "no zone";
    - none keeps a copy of its own.

  (`Test.Bridge.Time.TestZoneCase`; the four folded classes and `Test.Tools.Reminders` pass)

## Spec Change Log

## Review Triage Log

### 2026-10-23 — Review pass
- verdicts: 44 findings — high 0, medium 11, low 22, false 2, maybe-false 9
- findings:
  - Blind Hunter
    - `[low]` `[reject]` NOTSENT says "nothing was done" although a lost reply may follow an applied command, and a retry takes a new key — the text is the spec's (Boundaries), and a submit that errors after the owner applied the command needs a fault in a synchronous in-process call that nothing shows; the retry's key is AD-1's.
    - `[maybe-false]` `[reject]` the tools do not bound their strings against the command's MAXLENs — it depends on how Story 2.3's real `CommandsIn` saves the message; if true it is low (a failed reminder with a misleading reason, for an over-long value the schema asks the model not to send). Probe ledgered in `deferred` with `reopen_if`.
    - `[low]` `[reject]` `Answer` leaves out `due` and `dueLocal` when the owner's `DueAt` cannot be read — the spec has them "only when not empty" (decision 19), and the owner's `DueAt` is a UTC time by contract. The behaviour is now pinned by `TestAnswerShapes`.
    - `[maybe-false]` `[defer]` list is `TrustedOutput` but returns text that the model wrote in earlier turns — the AC declares it, and whether the gate treats stored model-authored text as trusted is Epic 3's; if true it is medium (unverified), ledgered in `deferred` for Story 3.1/3.3.
    - `[maybe-false]` `[defer]` Chat's ceiling of 4 iterations against list, several cancels and the text — AD-20 fixes 4; whether a real model serialises the cancels is unmeasured; if true it is medium (unverified), ledgered in `deferred`.
    - `[maybe-false]` `[defer]` the key `<ItemId>:<position>` is not tied to the command, so a re-run with other calls reuses `:1` for another verb — AD-1's key; what the owner does with a reused key is Story 8.4's; if true it is medium (unverified), ledgered in `deferred`. Grouped with the Intent Alignment row on idempotency and the Edge Case claim on the `Context` doc.
    - `[low]` `[reject]` every live test swaps `CommandsIn` for the double, so the shipping stub's path is untested, and the list contract has two implementations written here — the spec's approach 3; the stub's error is the `$$$ISERR` branch that `TestSubmitFails` pins, and the contract goes to Story 8.4 as DW-135.
    - `[low]` `[reject]` the label scan checks "not generic", not "of its own", and its floor `tools '< 12` is hard-coded — AC9 words it as "not the generic label"; the floor is a lower bound that more tools never trip.
    - `[medium]` `[patch]` the zone fold is partial: `Test.Bridge.Decide` still saves and restores the zone inline and `TestZoneCase` checks a fixed list — verified (`Decide.TestRecordedAtIsUtc`): AC10 says none keeps a copy; fixed by folding `Decide` onto `ZoneCase` and scanning Lane A's test packages in `TestZoneCase`. Lane B's two copies stay, as the spec has it. Grouped with the Edge Case claim and the Verification Gap row on `Decide`.
    - `[low]` `[reject]` the 2027 due time stops giving "another year" after 2026 — the values are the intent contract's, and every expectation is computed by `ForMessage`, so nothing goes red and nothing is wrongly green.
  - Edge Case Hunter
    - `[maybe-false]` `[reject]` `localDueAt`, `text` and `reminderRef` over the MAXLEN reach `Submit` unchecked — same root cause as the Blind Hunter's bounds row; probe in `deferred`.
    - `[low]` `[reject]` `Answer` shows no `due` with `ok: true` when `DueAt` is unreadable, where `Listed` fails — the owner's `DueAt` is UTC by contract; decision 19; pinned by `TestAnswerShapes`.
    - `[maybe-false]` `[reject]` `delaySeconds` has no upper bound — same root cause as the bounds row; probe in `deferred`.
    - `[maybe-false]` `[defer]` Chat's `MaxIterations` stays 4 — same root cause as the Blind Hunter's iteration row.
    - `[low]` `[reject]` `UseItemClass` when the item already has the double (a killed earlier run) saves the double as the class to restore — a throwaway lasts one call, so the state needs a killed process in a reused stack, and the fix adds a guard.
    - `[medium]` `[patch]` the statuses of `RestoreItemClass` and `RestoreKeys` are ignored in `OnAfterAllTests` — verified: a restore that did not happen left the double behind `CommandsIn` with no failure. Fixed: `OnAfterAllTests` returns both statuses and checks the class of a new `CommandsIn` service (assertions there are not logged by the manager). Grouped with the Verification Gap row on the swap.
    - `[low]` `[reject]` `Prepare` sets `Pointed` and `Swap` before their calls succeed, so later tests skip the retry — the first failure names the cause, and the flags are set first so that the restore runs after a half-applied change.
    - `[medium]` `[patch]` claim: "Lane A holds four zone copies; none keeps a copy" — `Test.Bridge.Decide` keeps one; fixed with the Blind Hunter's zone row.
    - `[false]` `[reject]` claim: a negative `delaySeconds` gets the wrong reason (`-5` is refused as not a whole number) — the matrix row lists `-5` among the values that get `BADDELAY`.
    - `[low]` `[reject]` claim: the `CommandResult` reaches the model "unchanged" although `Answer` drops `Outcome` and `Data` and re-expresses `DueAt` — the spec defines `Answer`'s fields; the owner's `Message` is unchanged.
    - `[maybe-false]` `[defer]` claim: the position is "the same on every run of the call" — true for the same calls; see the key row.
  - Verification Gap Reviewer
    - `[medium]` `[patch]` `Listed`'s refusal branch (`Ok` 0 for `ListReminders`) is never exercised — verified by the removal: nothing went red. Fixed: `TestListRefused` (mutation recorded).
    - `[medium]` `[patch]` `Run`'s branch for an answer that is no `CommandResult` is never reached — verified (`<INVALID OREF>` in `Answer` when the check is removed). Fixed: the double's `empty` mode and `TestSubmitEmpty`. The `Catch` for a thrown error is not reachable from the double: the business service turns a thrown error into an error status, which `TestSubmitFails` covers.
    - `[medium]` `[patch]` the warning's `Redact.Text` is not pinned — verified (the bare status text left every test green). Fixed: the double's `fail` value carries the text, and `TestSubmitRedacted` uses a key-shaped value made at run time.
    - `[medium]` `[patch]` the strict-read guards of `Listed` and the omit-when-empty guards of `Answer` have no failing case. Fixed: three more unreadable `Data` values in `TestListUnreadable` (no `text`, an entry that is no object, a good entry before a bad one) and `TestAnswerShapes`.
    - `[medium]` `[patch]` `TestZoneCase` does not drive the base's hooks. Fixed: it calls `OnBeforeOneTest` and `OnAfterOneTest`, for a named zone and for no zone.
    - `[medium]` `[patch]` `Test.Bridge.Decide` keeps its own zone copy and `TestZoneCase`'s list is closed — fixed with the Blind Hunter's zone row.
    - `[medium]` `[patch]` the `CommandsIn` swap is never asserted to be undone — fixed with the Edge Case row on the restore statuses.
    - `[low]` `[patch]` AC8: only `TestNoSession` has its own `mutation:` line — the lines for the failed-submit tests and for `BADDELAY` are written (Verification).
    - `[low]` `[patch]` AC10: one `mutation:` line, for `PutZone` only — the lines for the hooks and for the scan are written (Verification).
    - `[low]` `[reject]` AC2: one `mutation:` line for six parameters — one demonstrated mutation per AC is the bar (Rule 19), and `READONLYLISTREMINDERS` is one.
    - `[medium]` `[patch]` `Test.Tools.Reminders.StartsWithSqlVerb` feeds `AssertNotTrue` with no positive control — it could not fail if it always gave 0. Fixed: two controls in `TestDeclarations`; the always-0 mutation goes red.
    - `[low]` `[reject]` `TestSetLocal`'s preamble assertions pin text, and `localDueAt` is scripted — the matrix row asks for the preamble line in the first request; how a real model works out the date cannot be pinned with a mock.
    - `[low]` `[reject]` `TestZoneCase` assumes that the instance has no `TZ` set — a throwaway has none (Task 0), `Test.Agent.Render.TestPreambleZone` makes the same assumption, and a fix would stop the test from reading "no zone".
  - Intent Alignment Auditor
    - `[low]` `[reject]` with the shipping stub of `CommandsIn`, every Chat tool call ends in NOTSENT, and no test runs that path unswapped — the intent's approach 3 (tested against a double); it is the `TestSubmitFails` branch, and Story 2.3 replaces the stub.
    - `[low]` `[reject]` the list contract is checked against code of the same story — DW-135 hands it to Story 8.4.
    - `[low]` `[reject]` the model's side is scripted: `localDueAt` and the cancelled ref are constants in the scenarios — the mock's nature (Task 0 (c)); a real model is Story 8.4's live check.
    - `[false]` `[reject]` how AI Hub treats a non-integer `delaySeconds` is unmeasured — Task 0 (c) measured `1.5`, `-5` and `abc` through the tool manager: they reach the method and get `BADDELAY`.
    - `[maybe-false]` `[defer]` idempotency: the keys are present and deterministic, but no test shows that a re-run creates no duplicate — the owner's (Story 8.4); see the key row.
    - `[low]` `[reject]` the classification parameters are read as `$Parameter`s only — nothing reads them until Epic 3 (AC2).
    - `[low]` `[reject]` the watch labels are checked as "not generic" and only `OcuTalon.Tools.` is scanned — AC9 words it so.
    - `[low]` `[reject]` the cache marker on Chat's last tool depends on the length of the descriptions — measured (3,567 characters against the 512-token threshold), a wide margin.
    - `[low]` `[reject]` `PutZone(-1)` gives "" and not -1 — the spec's definition ("-1 becomes \"\""), decision 23.
    - `[low]` `[reject]` `IsSessionRef`'s `A` matches Unicode letters on a Unicode build — the OwnerRef is made by `Ids.NewRef`; the check only keeps out `instance`, `eval` and the empty owner.
- patches applied (8 entries, all medium): `TestListRefused`; `TestSubmitEmpty` and the double's `empty` mode; `TestSubmitRedacted` and the double's `fail` text; the three unreadable `Data` values and `TestAnswerShapes`; the hook drive in `TestZoneCase`; the fold of `Test.Bridge.Decide` and the scan in `TestZoneCase`; the checked restore in `OnAfterAllTests`; the controls of `StartsWithSqlVerb`. Beside them: the `mutation:` lines (two low), and `Test.Bridge.Decide.TestEstimateTokens`, which the fold's run found red because it asserted that Chat has no tool (decision 25).

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-1:** a safe tool submits an `OcuTalon.Msg.Command.<Verb>` through `Commands.Submit` and `CommandsIn`, and returns the owner's synchronous `CommandResult`. It never writes domain tables. Its key is the turn's `ItemId` plus the call's position.
- **AD-2:** the `Context` change names no OcuTalon package. The tools may use the bridge (the allowed direction).
- **AD-4:** the `SessionRef` comes from the context, never from an argument, and the owner scopes the list.
- **AD-6:** the callback rule binds `ReminderTools`, `CommandCall` and what they call inside AI Hub's callback.
- **AD-7:** Chat's static `TOOLSETS` names its conversation toolset.
- **AD-9:** step labels are class parameters by the NAME rule; `StepAudit` records each call.
- **AD-10:**
  - the classification is declared as class parameters for the gate;
  - list is `TrustedOutput`;
  - the results pass through `Result`;
  - one gate decides every call, so no tool checks provenance itself.
- **AD-18:**
  - the reminder tools live in `OcuTalon.Tools` and submit Epic 0's verbs, which `ReminderOps` handles;
  - `OcuTalon.Data.Time` is the only converter outside the bridge;
  - the preamble states the local time and zone.
- **AD-22:** the scenarios go under `A/`, and the tests are in shard `lane-a`.
- **AD-29:** the verbs keep Story 0.4's fields, and a Lane A need of Lane B's contract is asked for (the list contract).
- **AD-33:** `ReminderOps` and the `Reminder` table are Lane B's. The tools never touch them, and the tests write fixture rows only.

No acceptance criterion contradicts an AD's Rule. The interval "until Epic 3's gate lands they run as safe tools" is the AC's own; AD-10's gate is Epic 3's.

**Decided in-stage:**
1. **One tool class, three tools.** One class holds the three tools, with per-tool parameters by the step-label NAME rule (`STEPLABEL<NAME>`, `CLASSIFICATION<NAME>`, `READONLY<NAME>`, `TRUSTEDOUTPUT<NAME>`).
   - **Why:** DW-85 asks for `STEPLABEL<NAME>`, the AC asks for the classification as class parameters, and one NAME rule keeps Epic 3's reader the same as `LabelFor`.
   - **Method names:** they are the tool names in CamelCase, so a class's own discovery and its toolset give the same parameter.
2. **The classification vocabulary** is AD-10's `safe` and `risky`, with read-only and trusted output as separate flags, every one declared explicitly. Only list is `TrustedOutput`, as the AC words it (see the lead's items).
3. **The position** is the call's number among the turn's tool calls that submit a command.
   - **How:** it is counted in the new `Context.CommandCount`, which `Begin` sets to 0.
   - **Why:** a re-sent turn starts again at 1, two calls in one response get 1 and 2, and no measurement of when AI Hub logs a tool step is needed.
   - **The key:** `<ItemId>:<n>`. Base64url never holds `:`.
4. **No turn of a session, no command.** A context whose `OwnerRef` is not a session's Ref (`instance`, `eval`, empty), or whose `ItemId` is empty, gets `NOSESSION`, and nothing is submitted. Without this, a reminder would be owned by no session, and an empty `ItemId` would give a key that collides across turns.
5. **The tools stay thin.** They pass the model's arguments unchanged. The one exception is a `delaySeconds` that is not a whole number, which an integer property would turn into a wrong time silently. The owner refuses everything else (Story 8.4).
6. **What the model gets.** `ok`, `message`, `ref`, `due` (`ForMessage`, the house style of a time) and `dueLocal` (`ToLocal`). The list adds `zone`, and never shows a UTC time. A list that cannot be read is a failure, never "none pending" (no false all-clear).
7. **The list contract** `{"reminders":[{"ref","text","dueAt"}]}` is fixed here, because `Data`'s shape is unspecified and the AC needs the double to answer "the way `ReminderOps` will". It goes to the veto window and to Story 8.4 (the Clarification Record).
8. **A failed submit** answers `NOTSENT` and logs a warning. The step status stays `ok`. A thrown error would put AI Hub's error text, with its codes, in front of the model.
9. **"Reaches the reply" is observed at the model's input.** The mock's replies are scripted and never echo a tool result. So the pin is the refusal's `Message`, unchanged, in the next request's tool result, and a turn that ends in a normal `Reply`: no fallback, no error and a step status of `ok`. The real model then words its reply from that answer.
10. **The double sits behind the `CommandsIn` item** for the test class, through the stored configuration (`UseItemClass`), and is put back after.
    - **Why there:** `Submit` names the item, and the tool runs in `ChatAgent`'s job.
    - **What it records:** `^OcuTalonTest("CommandsDouble", ...)`, the pattern of `ProbeSink`'s shared mode.
11. **The re-send test goes to `ChatAgent` directly.** `Decide` answers a repeated item from its recorded decision, with no model call. It re-sends only a turn in which no tool ran (AD-8). So the same request sent twice to the runner is what a re-send of a turn with tools would do.
12. **The watch fixture gets labels.** So the label scan has no exemption. An exemption would also cover Story 5.4's readers, which replace the class in place under the same name.
13. **The callback rule covers more classes.** `CALLBACKHELPERS` gains `CommandCall`, `Bridge.Redact` and Lane B's `Core.Commands`, `Core.CommandsIn` and `Data.Time`, because the tools call them inside AI Hub's callback. The scan only reads them (see the lead's items).
14. **`ZoneCase` is an abstract base with no `Test` method**, which `ci/iris.sh`'s `is_test_case` skips. Its `CurrentZone` and `PutZone` are class methods, so `TestZoneCase` checks them without disturbing its own saved zone. The save and the restore happen for every test: `Render` saved once per class before, and it restored after every test already, so the effect is the same.
15. **No `ReadOnly` requirement in the reminder toolset.** The class parameters are the one declaration, so the two cannot drift. The watch toolset keeps its requirement (Story 1.1).
16. **No change to Chat's instructions.** The tools' descriptions tell the model the two due forms. They are text for the model, never shown to the user as written, like Story 1.9's note.
17. **Markers, never the guide prompt.** Lane B's Story 8.4 keys a scenario under `B/` by the guide prompt's exact text. A marker wins over a prompt in the mock's order, so this story's tests can send that exact text.
18. **The lock folder** in Verification is written as `<main checkout>/.worktrees/.coordination/locks/lane-a`, because a local path in a tracked file fails `docker/tests/test-boundaries.sh` (CON-5).
19. **The list is read strictly, and an empty list is a real answer.** `Listed` reads `Data` as JSON with a `reminders` array. An entry without a `ref`, a `text` or a `dueAt` that `Data.Time` can convert makes the whole list unreadable (`NOTREAD`), because a half-read list could hide a pending reminder. `{"reminders":[]}` is the empty list: the owner says none is pending. `Answer` leaves out `due` or `dueLocal` when `Data.Time` gives "" for the owner's `DueAt`, rather than show an empty string.
20. **A failed submit still takes its position.** `Run` writes the position back to the context before it submits, as the spec words it, so the keys of one call stay `:1`, `:2`, `:3` even when one submit fails. A call that is refused before it reaches `Run` (`BADDELAY`, `NOSESSION`) takes none.
21. **Results are compared field by field.** AI Hub writes the keys of a tool result in alphabetical order (`{"message":...,"ok":...}`), whatever order the tool built them in. "Exactly" in the matrix therefore means the same fields, types and values and no other field (`Test.Tools.Reminders.AssertObject`), not the same text.
22. **The test class keeps the swap as JSON text.** An unset property of type `%DynamicObject` reads as an empty object, so `$IsObject` is always true and the first version of `Prepare` never swapped. `Swap` is a string, empty while the double is not behind the item.
23. **`ZoneCase` pins one convention.** A process that has had no zone reads -1; after `TimeZone("")` it reads "". `PutZone(-1)` gives the process "", and `TestZoneCase` asserts that, because the effect of -1 and "" is the same (UTC) and only the convention can be pinned (mutation AC10).
24. **A boolean `delaySeconds` is read as 1.** AI Hub decodes a JSON `true` into 1 before `SetReminder` runs, so it passes the whole-number test. The schema says integer, so the model has no reason to send it; ledgered in `deferred` rather than guarded (the tool cannot tell it from 1).
25. **Chat's agent part counts its tools.** `RequestSize.AgentChars` for Chat is now the system prompt and the JSON of the Reminders toolset's tools, as it is for Diagnosis and Watch. `Test.Bridge.Decide.TestEstimateTokens` asserted that Chat had no tool, and the review found it red; it now expects the tool JSON. The plan's shared-surface search did not name `AgentChars`.
26. **A restore that did not happen fails the class.** `%UnitTest.Manager` logs no assertion made in `OnAfterAllTests` (no test method is current), so `Test.Tools.Reminders.OnAfterAllTests` returns the status of `RestoreItemClass` and `RestoreKeys`, and an error when a new service of the `CommandsIn` item is not of the class that the item had. A returned error fails the class (observed).
27. **`Test.Bridge.Decide` is folded onto `ZoneCase`,** and `Test.Bridge.Time.TestZoneCase` scans Lane A's test packages (Agent, Bridge, Tools, Install, Digest) for a class that calls the process zone without extending the base, after it drives the base's two hooks. Lane B's copies (`Test.Data.Time`, `Test.Msg.Catalog`) are outside the scan, as the spec has it.
28. **The double gains two modes,** for the review's gaps: `empty` (an OK status and no result) and a `fail` value that is the status text (1 stays the default text).

**Integration ACs (Rule 1):**
- **AC3, AC5 and AC6:** the Chat agent's runner (AI Hub's tool manager in `ChatAgent`) calls the tools on the model's `tool_use`, and the model API (the CI mock) reads each answer in the turn's next request, which its log shows.
- **The commands:** no real consumer in this story; the first will be Story 8.4 (`ReminderOps`).
- **The classification parameters:** no consumer in this story; the first will be Story 3.1 (the gate), with Story 3.3's reminder criterion.

**Consumed-by:**
- **Story 8.4 (Lane B):** `ReminderOps` handles the three verbs from these tools. It answers `ListReminders` with the list contract and refuses with plain-English reasons that the tools pass back. Its `B/` guide-prompt scenarios call `set_reminder`, and its REL-2 reminder step builds on them.
- **Story 3.1:** the gate classifies by `CLASSIFICATION<NAME>`, `READONLY<NAME>` and `TRUSTEDOUTPUT<NAME>`, generalising `StepBuffer.LabelFor`'s lookup rather than copying it, and reports `turn.step` with these labels.
- **Story 3.3:** the reminder tools' classification criterion, and the taint of set and cancel (see the lead's items).
- **Story 5.4:** the real watch readers keep their labels, and the scan holds them.
- **Any later command tool** (`start_watch`, `stop_watch`, `dismiss_incident`): it submits through `CommandCall`.

**Consumes:**
- **Story 1.9:** `Tools.Result`, the exact tool lists of `Test.Agent.Runners`, and the CodeRules tool scans.
- **Story 1.5:** `StepAudit`, `StepBuffer.LabelFor` and `RunnerFixture.StepsOf`.
- **Story 1.8:** linked user turns, owners of their own, `SessionMark` and `DropSince`.
- **Stories 1.3 and 1.6:** `Decide`, `DecisionOf`, and the fallback fields of the answer.
- **Epic 0:** `Tools.Names`, the reminder verbs, `CommandResult`, `Commands.Submit`, the `CommandsIn` item, the `Reminder` table, `Data.Time`, `Agent.Input` and the mock's marker scenarios.

**Extend, don't copy (Rule 2):**
- **The siblings followed:**
  - `Reminders` follows `Watch`, and `ReminderTools` follows `WatchFixture`;
  - the scenarios follow `steps-two-tools.json` and `result-cap.json`;
  - `Test.Tools.Reminders` follows `Test.Agent.RequestSize` (live) and `Test.Tools.Result` (in process).
- **Extended:**
  - `RunnerFixture.ChangeSettings` gains an optional class name for `UseItemClass`, beside `UseItemSetting`;
  - one CodeRules helper lists the tool classes for the Return scan and the label scan;
  - the label scan calls `StepBuffer.LabelFor` and does not restate its rule;
  - the reminder table scan reuses `Source.Matches`.
- **New, with no sibling:** `CommandCall` (the first tool that submits a command) and `CommandsDouble` (the first double of `CommandsIn`, with `ProbeSink`'s shared-record pattern).
- **The fold:** DW-32 is `ZoneCase`.

**Ledger (Rule 17):**
- **DW-32** is addressed: the fold, its Task and AC10.
- **DW-85** is addressed: the labels, the scan, its Task and AC9.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and for facts that need no production. No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh` or the scripts, with `OCUTALON_RUN_TAG=e1s10a OCUTALON_LOCK_OWNER='epic=1 stage=implement' OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801`.
  - QA uses the tag `e1s10q` (`stage=qa`), and review uses `e1s10r` (`stage=code-review`).
  - One stack at a time, one command per call, each with `timeout: 600000`.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each with the variables above):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, the class rules (ASCII, the bridge refs) and the CI config included. About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Tools.Reminders`;
  - `.Bridge.CodeRules`, `.Bridge.Time`, `.Bridge.Usage`, `.Bridge.Budget` and `.Bridge.Ext`;
  - `.Agent.Render`, `.Agent.Runners` and `.Agent.Instructions`.

  Expected: `CLASS ... passed` for each, about 1 to 2 minutes a call.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s10a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass, and the five new scenarios load with no problem.
- **(once)** `bash ci/iris.sh shard lane-a`. Expected: every class passes. This takes in the Chat classes that the story does not edit (`Bridge.Conversation`, `Bridge.Runner`, `Agent.Conversation`, `Agent.RequestSize`, `Agent.Decide`, `Agent.Steps`, `Tools.Result`). The only SKIP is the existing `TestStepHelpers`.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passes, `Test.Core.ProductionItems`, `Test.Core.Commands`, `Test.Core.CommandsContext` and `Test.Contract.Ac` included.
- **(once)** `bash release/standalone-bridge.sh`. Expected: every check `PASS` (the bridge loads alone with the new context field).
- **(once)** `bash ci/iris.sh live demo-path`. Expected: PASS, with `@floor` passed.
- **(once)** `bash ci/iris.sh teardown`. Expected: nothing of `e1s10a` is left.

**Shared surfaces:**
- **Chat's tool list.**
  - **The tests that assert it:**
    - `Test.Agent.Runners` (the literal list of `AssertRequests` for Chat, `TestToolInventory`'s expected names and providers, Chat's cache marker);
    - `Test.Agent.Instructions.TestToolsets` ("Chat has no toolset");
    - the mock's tool-name check (row 16, `mockkey` scenarios only, unchanged).
  - **Chat's request size** grows by the tool catalog: the band of `Test.Bridge.Conversation`, and `Test.Agent.RequestSize`'s sizes (both from `EstimateTokens` at run time).
  - **Search the test trees** for `TOOLSETS`, `ChatAgent`, `OcuTalon.Agent.Chat`, `CacheMark` and `WatchFixture`.
- **`Context` `FIELDS`** gains `CommandCount`: `Test.Core.CommandsContext` (Lane B) compares its snapshots with each other, `Test.Bridge.ProbeTool` iterates the fields, and `Test.Bridge.Ext` checks `Begin`.
- **`CALLBACKHELPERS`:** the count of `TestCallbackRule`.
- **The tool providers of `OcuTalon.Tools`:** `TestToolsReturnThroughResult` and `TestToolCodeScan`.
- **Chat's agent part (`RequestSize.AgentChars`):** `Test.Bridge.Decide.TestEstimateTokens` (found in review; search the test trees for `AgentChars` and `EstimateTokens`).
- **The watch tools' step labels:** any test that reads a watch tool's step label (none today; search for `Running a tool`).
- **The four folded zone classes'** hooks.
- **Production state while `Test.Tools.Reminders` runs:**
  - the `CommandsIn` item's class (Lane B's `Test.Core.ProductionItems` and `Test.Core.Commands`, and `test-production.sh`'s row 17 in its own throwaway);
  - the runners' keys;
  - the `Reminder` fixture rows;
  - `^OcuTalonTest("CommandsDouble")`;
  - the saved AI sessions and links.
- **The mock's scenario set:** five new files, which the mock's tests check.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | Chat's `TOOLSETS` is empty | `Tools.Reminders.TestDeclarations`, `Agent.Instructions.TestToolsets`, `Agent.Runners.TestRequestsUnderTheModelRules` |
| AC1 | `STEPLABELSETREMINDER` is removed | `Tools.Reminders.TestDeclarations`, `TestSetRelative` (the step label), `Bridge.CodeRules.TestToolsHaveStepLabels` |
| AC2 | `READONLYLISTREMINDERS` is 0 | `Tools.Reminders.TestDeclarations` |
| AC3 | `SetReminder` passes `delaySeconds` into `LocalDueAt` | `TestSetRelative` |
| AC3 | `Answer` drops `ref` | `TestSetRelative` |
| AC3 | the tool saves a `Reminder` row itself | `TestSetRelative` (the row count), `Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner` |
| AC4 | `SetReminder` also sets `DueAt` | `TestSetRelative`, `TestSetLocal` (the recorded fields) |
| AC5 | `CancelReminder` leaves `ReminderRef` empty | `TestCancel` |
| AC5 | `Answer` replaces a refusal's message with its own | `TestCancelRefused`, `TestSetRefused` |
| AC6 | `Listed` passes the UTC `dueAt` as `dueLocal` | `TestListInZone` |
| AC6 | `ListReminders` reads the rows of the table instead of `Data` | `TestListInZone` (the double's own reminder), `Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner` |
| AC6 | an unreadable `Data` gives an empty list | `TestListUnreadable` |
| AC7 | `Begin` does not set `CommandCount` to 0 | `TestKeys` (round 2's keys) |
| AC7 | the key leaves out the position | `TestKeys` |
| AC8 | `Run` submits with `OwnerRef` `instance` | `TestNoSession` |
| AC9 | `WatchFixture` loses `STEPLABELREADEVENTLOG` | `Bridge.CodeRules.TestToolsHaveStepLabels` |
| AC10 | `PutZone` passes -1 on as it is | `Bridge.Time.TestZoneCase` |

### Measured in implementation (Task 0; throwaway tag `e1s10a`, build 154, the CI mock)

- **(a) The swap.**
  - `RunnerFixture.UseItemClass("CommandsIn", "OcuTalon.Test.Tools.CommandsDouble")` took 0.015 s and saved `{"className":"OcuTalon.Core.CommandsIn"}`. `UpdateProduction` applied the class at once, so the fallback (stop and start the production) was not needed.
  - `CreateBusinessService("CommandsIn")` then created the double in the test job, and the command of a live turn was recorded from `ChatAgent`'s job (origin `tool`).
  - `RestoreItemClass` took 0.011 s, and `CreateBusinessService("CommandsIn")` then gave `OcuTalon.Core.CommandsIn` again, whose `ProcessInput` answers `ERROR #5003: Not implemented`. `PointKeys` took 3.2 s.
- **(b) A command from inside a tool.** A live `reminder-set-relative` turn through `Decide` took 0.245 s. `Submit` from `SetReminder`, inside AI Hub's callback in `ChatAgent`'s job, returned the double's answer with no hang and no error, and the double recorded origin `tool`, so the context is active there. The runner's `Reply` header (`ChatAgent` to `Decide`), the three `AgentStep` headers, the request and the answer are all in the decision's session (`SessionOf`), not in a session of the `Submit`. The decision is not a fallback.
- **(c) The arguments.**
  - **The schema names:** `text` (required), `delaySeconds` (integer), `localDueAt` for set; none for list; `reminderRef` (required) for cancel. The scenarios use these names, so none changed.
  - **What a method receives:** an omitted optional argument is its default (""). `delaySeconds` as `%Integer` takes a JSON `60` as 60, and `"60"`, `60.0` and `1e3` pass the whole-number test (`1.N`). `1.5`, `-5` and `"abc"` arrive as such and get `BADDELAY`. `null` and `""` arrive empty. A JSON `true` arrives as 1 (decision 24). A missing `text` arrives as "" (the owner refuses it). `delaySeconds` stays `%Integer`.
  - **The key order:** the mock's log shows a tool result with its keys in alphabetical order, whatever order the tool built them in (decision 21).
- **(d) The scan's source.** The toolset's `%Discover()` gives for each tool its `name`, its `provider` (`OcuTalon.Tools.ReminderTools`), `metadata.origin_class` and `tool_provider` (the toolset). The label scan reads `provider` and `name` from `%Discover()`, for toolsets and providers alike; it needs no parse of the `Definition` XData.
- **(e) Chat's request.**
  - `RequestSize.AgentChars("OcuTalon.Agent.Chat")` is 3,567 characters with the tools (Diagnosis 2,053; Triage 1,245); `Decide.EstimateTokens` for the first turn is 1,365.
  - The mock logged `cancel_reminder,list_reminders,set_reminder` in each request. The last tool, `set_reminder`, carries `{"type":"ephemeral"}`, the other two and the system block carry none. So `AssertRequests` expects the marker on Chat's last tool, as on Diagnosis's.
- **(f) The fixture rows.** In the throwaway a `Reminder` row saved (status OK) and `DELETE FROM OcuTalon_Data.Reminder WHERE Ref = ?` deleted it (SQLCODE 0).
- **Other facts.** The throwaway's `TZ` is unset: `Data.Time.Zone()` is `UTC` and the process zone reads -1; after `$SYSTEM.Process.TimeZone("")` it reads "", and `TimeZone(-1)` gives -1 again (decision 23). With `America/New_York` set in the process, `Data.Time.Zone()` reads `America/New_York`. No fact contradicts an AC.

### Mutations demonstrated (Rule 19)

Each was applied to the file named, run in a throwaway, seen red and reverted; the file was byte-identical afterwards (SHA-256 compared). Tests are in `OcuTalon.Test`.

- mutation: Chat's `TOOLSETS` is "" -> `Tools.Reminders` (`TestDeclarations` and the live tests), `Agent.Instructions.TestToolsets`, `Agent.Runners.TestRequestsUnderTheModelRules` and `TestToolInventory` went red.
- mutation: `STEPLABELSETREMINDER` removed -> `Tools.Reminders.TestDeclarations`, `TestSetRelative` (the step label) and `Bridge.CodeRules.TestToolsHaveStepLabels` went red.
- mutation: `READONLYLISTREMINDERS` is 0 -> `Tools.Reminders.TestDeclarations` went red.
- mutation: `SetReminder` passes `delaySeconds` into `LocalDueAt` -> `Tools.Reminders.TestSetRelative` (also `TestSetLocal`, `TestSetRefused`, `TestKeys`) went red.
- mutation: `Answer` drops `ref` -> `Tools.Reminders.TestSetRelative` (also `TestCancel`) went red.
- mutation: the tool saves a `Reminder` row itself (a fresh `Ref` each call) -> `Tools.Reminders.TestSetRelative` ("the tool wrote no Reminder row") and `Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner` went red. With a fixed `Ref` the second save fails on the unique index, so the first run of the mutation did not go red: the mutation must use a new `Ref` each time.
- mutation: `SetReminder` also sets `DueAt` -> `Tools.Reminders.TestSetRelative`, `TestSetLocal` (the recorded fields; also `TestKeys`, `TestSetRefused`) went red.
- mutation: `CancelReminder` leaves `ReminderRef` empty -> `Tools.Reminders.TestCancel` went red.
- mutation: `Answer` replaces a refusal's message with its own -> `Tools.Reminders.TestCancelRefused` and `TestSetRefused` went red.
- mutation: `Listed` passes the UTC `dueAt` as `dueLocal` -> `Tools.Reminders.TestListInZone` (also `TestList`, `TestCancel`) went red.
- mutation: `ListReminders` reads the rows of the table instead of `Data` -> `Tools.Reminders.TestListInZone` ("with a Data that no row holds") and `Bridge.CodeRules.TestToolsLeaveRemindersToTheirOwner` went red.
- mutation: an unreadable `Data` gives an empty list -> `Tools.Reminders.TestListUnreadable` went red.
- mutation: `Begin` does not set `CommandCount` to 0 -> `Bridge.Ext.TestContext` went red. `TestKeys` stayed green, as the spec's table expected it to go red: `Begin` kills the whole context first, and `Run` adds 1 to a missing count, so a missing 0 changes no key. The count at `Begin` is pinned by `Test.Bridge.Ext`.
- mutation: `Run` does not write the position back to the context -> `Tools.Reminders.TestKeys` (round 1: both keys `:1`; also `TestBadDelay`, `TestCancel`, `TestSubmitFails`) went red.
- mutation: the key leaves out the position -> `Tools.Reminders.TestKeys` (also `TestCancel`, `TestList`, `TestBadDelay`) went red.
- mutation: `Run` submits with `OwnerRef` `instance` (the session check removed) -> `Tools.Reminders.TestNoSession` went red.
- mutation: `WatchFixture` loses `STEPLABELREADEVENTLOG` -> `Bridge.CodeRules.TestToolsHaveStepLabels` went red.
- mutation: `ZoneCase.PutZone` passes -1 on as it is -> `Bridge.Time.TestZoneCase` went red.

### Mutations demonstrated in review (Rule 19)

Applied to the file named, run in a throwaway, seen red and reverted; each file was byte-identical afterwards (SHA-256 compared). The first five were applied together in one run of the class (each named test went red, and no other test did).

- mutation: `Listed` without its refusal branch (`If 'result.Ok Quit ..Answer(result)` removed) -> `Tools.Reminders.TestListRefused` went red.
- mutation: `Run` without the check that the answer is a `CommandResult` -> `Tools.Reminders.TestSubmitEmpty` went red (`<INVALID OREF>` in `Answer`).
- mutation: `Run` logs the status text without `Redact.Text` -> `Tools.Reminders.TestSubmitRedacted` went red.
- mutation: `Listed` without the check of the `text` of an entry -> `Tools.Reminders.TestListUnreadable` went red (the entry with no text, and the good entry before a bad one).
- mutation: `Answer` sets `due` and `dueLocal` whatever `Data.Time` gives -> `Tools.Reminders.TestAnswerShapes` went red.
- mutation: `OnAfterAllTests` of `Test.Tools.Reminders` skips `RestoreItemClass` -> the class failed with the error that the `CommandsIn` item runs `CommandsDouble` after the restore (alone, in its own run).
- mutation: the `1.N` check of `SetReminder` removed -> `Tools.Reminders.TestBadDelay` went red (with the next one, in one run).
- mutation: `Test.Tools.Reminders.StartsWithSqlVerb` always 0 -> `Tools.Reminders.TestDeclarations` went red (its control).
- mutation: `ZoneCase.OnAfterOneTest` does nothing -> `Bridge.Time.TestZoneCase` went red (the hooks).
- mutation: `Test.Bridge.Decide` back on `%UnitTest.TestCase` with its inline zone copy -> `Bridge.Time.TestZoneCase` went red (the scan and the list).

### Run in this stage (tag `e1s10a`)

- `bash ci/checks.sh`: all scripts passed. `bash docker/tests/test-mock.sh`: 94 tests passed, the five new scenarios included. `bash ci/iris.sh build`: exit 0.
- `bash ci/iris.sh class` passed for `Test.Tools.Reminders`, `Test.Bridge.CodeRules`, `.Time`, `.Usage`, `.Budget`, `.Ext`, `Test.Agent.Render`, `.Runners`, `.Instructions`, and for the Chat classes `Test.Bridge.Conversation`, `.Runner`, `Test.Agent.Conversation`, `.RequestSize`, `.Decide`, `.Steps`, `Test.Tools.Result` and the Lane B classes `Test.Core.Commands`, `.CommandsContext` and `Test.Contract.Ac`. `bash release/standalone-bridge.sh`: every check `PASS`.

### Run on the reviewed tree (tag `e1s10a`, one throwaway at a time)

- (loop) `bash ci/checks.sh`: all scripts passed. `bash ci/iris.sh build`: exit 0. `bash ci/iris.sh class` passed for `Test.Tools.Reminders`, `Test.Bridge.CodeRules`, `.Time`, `.Usage`, `.Budget`, `.Ext`, `Test.Agent.Render`, `.Runners` and `.Instructions`, and, after the fold, for `Test.Bridge.Decide`. `bash ci/iris.sh teardown`: nothing left.
- (once) `bash docker/tests/test-mock.sh`: 94 tests, 94 passed. `bash ci/iris.sh shard lane-a`: 38 classes passed, and the only SKIP is the existing `TestStepHelpers`. `bash ci/iris.sh shard lane-b`: 24 classes passed, `Test.Core.Commands`, `Test.Core.CommandsContext` and `Test.Contract.Ac` included (`Test.Core.ProductionItems` is not a class that `ci/iris.sh` runs, so it is not in the shard). `bash release/standalone-bridge.sh`: 12 checks `PASS`. `bash ci/iris.sh live demo-path`: PASS, `@floor` 1 of 1 passed. `bash ci/iris.sh teardown`: nothing of `e1s10a` left.
- Beside the list: `bash ci/iris.sh shard lane-a --reverse`: 38 classes passed.

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **Public-facing text** (category 5), which the UX does not specify. These are the step labels that Visual Trace shows, and that the page's turn indicator will show from Epic 3:
  - "Setting a reminder", "Listing your reminders" and "Cancelling a reminder";
  - "Reading the failed messages", "Reading the event log" and "Reading the item settings".

  They follow the UX's one example, "Checking the Orders production…".
- **A cross-lane contract for Lane B's Story 8.4, not yet planned** (category 8; in a parallel run, the orchestrator routes it).
  - **The contract:** `ReminderOps` answers `ListReminders` with `CommandResult.Data` = `{"reminders":[{"ref","text","dueAt"}]}`: the command's session's pending reminders, the earliest due first, with `dueAt` in UTC.
  - **The recommendation:** add it to Story 8.4 as an AC bullet.

**For the lead (rulings recommended, not blocking):**
- **Spine lines (Rule 20):**
  - **A Consistency Conventions row, "Tool classification":** a built-in tool declares `CLASSIFICATION<NAME>` (`safe` or `risky`), `READONLY<NAME>` and `TRUSTEDOUTPUT<NAME>` by the NAME rule of the step labels, else the same names without `<NAME>` for the class;
  - **AD-1:** the key is `<ItemId>:<n>`, where n counts the turn's command-submitting tool calls (`Context.CommandCount`);
  - **AD-18 or AD-29:** the `ListReminders` `Data` shape above.
- **The taint of set and cancel, for Story 3.3.** The AC declares `TrustedOutput` for list only. So once Epic 3's taint rule lands, every turn that sets or cancels a reminder is tainted: it is never saved, and the next turn starts fresh with a recap. Their output is built by code from `ReminderOps`' `CommandResult`, which fits AD-10's definition of trusted output. The recommendation is that Story 3.3 decide whether set and cancel declare `TRUSTEDOUTPUT<NAME>` 1. This story declares 0, as the AC words it.
- **Lane B classes in a Lane A scan.** `CALLBACKHELPERS` now names `Core.Commands`, `Core.CommandsIn` and `Data.Time`, because the reminder tools run them inside AI Hub's callback. Lane B's Story 2.3 (`CommandsIn`) must keep them free of `%AI` and Python, or `Test.Bridge.CodeRules` goes red at the merge. Worth one line to Lane B.
- **AC7's "reaches the reply"** is observed at the model's input (decision 9), because the mock never echoes a tool result. This restates an observable and keeps the intent (Rule 5, the first tier).

**Lead's rulings at the spec gate (2026-10-23, Epic 1 runner, unattended):**
- **Veto window, kept as planned:** the six step labels (inbox U-47).
- **The `ListReminders` `Data` shape** is ledgered as DW-135, routed to Story 8.4 (the orchestrator adds the bullet after this epic merges; Epic 8 starts after that). No AD text changes.
- **Spine:** the Consistency Conventions row "Tool classification" is added as recommended. The key's counting (AD-1) stays in this spec.
- **Set and cancel declare `TRUSTEDOUTPUT` 0**, as the AC words it; whether they become trusted output is ledgered as DW-136, routed to Story 3.3.
- **Decided:** decision 9 (AC7 observed at the model's input), the direct re-sent-turn key test, and one story for the tools and DW-32 and DW-85. Epic 2's `Core.CommandsIn` and `Core.Commands` hold no `%AI` or Python today (checked on its branch).

## Auto Run Result

Status: done
Blocking condition: none

**Implement and review stage (2026-10-23).**
- **Summary.** Chat now offers `set_reminder`, `list_reminders` and `cancel_reminder` (`OcuTalon.Tools.Reminders`, methods of `ReminderTools`). Each submits Epic 0's verb through `OcuTalon.Tools.CommandCall.Run` and `Commands.Submit`, with origin `tool`, the session's `SessionRef` and the key `<ItemId>:<n>` (`Context.CommandCount`), and the model reads the owner's `CommandResult` (`Answer`, `Listed`). Every shipped tool has a step label (DW-85, with a CodeRules scan) and the Lane A zone tests share one base (DW-32, `ZoneCase`).
- **Files changed.**
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls`: the `CommandCount` field.
  - `src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls`, `ReminderTools.cls`, `Reminders.cls` (new): the helper, the three tools and the toolset.
  - `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls`, `Agent/Chat.cls`: the three watch labels, Chat's `TOOLSETS`.
  - `ci/mock/scenarios/A/reminder-*.json` (five, new): the marker scenarios.
  - `Test/Tools/Reminders.cls`, `CommandsDouble.cls`, `Test/Bridge/ZoneCase.cls` (new): the tests, the recording double of `CommandsIn` and the zone base.
  - `Test/Agent/RunnerFixture.cls`, `Runners.cls`, `Instructions.cls`, `Render.cls`; `Test/Bridge/CodeRules.cls`, `Ext.cls`, `Time.cls`, `Usage.cls`, `Budget.cls`, `Decide.cls`: `UseItemClass` and `RestoreItemClass`, Chat's tool list, the label and reminder-table scans, the fold onto `ZoneCase`, and `Decide`'s agent-part assertion for Chat's tools.
- **Review.** Four layers, 44 findings: 11 medium, 22 low, 9 maybe-false, 2 false, none high (the Review Triage Log has every row).
  - **Patches applied (8 entries, all medium; no intent gap and no bad spec):** a test of the owner's refusal of a list, one of an answer with no `CommandResult` (a new `empty` mode of the double), one that pins the redaction of the warning, three more unreadable-list cases and a test of `Answer`'s shape, the hooks of `ZoneCase` driven by `TestZoneCase`, `Test.Bridge.Decide` folded onto `ZoneCase` with a scan of Lane A's test packages for a copy, the restore of the `CommandsIn` item checked at the end of the class, and controls for the SQL-verb helper. Every patched test has a mutation that went red (Verification). Two low rows were patched in the spec (`mutation:` lines).
  - **Found on the way:** `Test.Bridge.Decide.TestEstimateTokens` asserted that Chat has no tool and went red; it now expects the tool JSON (decision 25).
  - **Deferred (5 items in the frontmatter):** a JSON `true` read as `delaySeconds` 1 (low); unbounded strings against the command's MAXLENs (low, with a `reopen_if`); list's `TrustedOutput` over stored model-authored text (medium, unverified, for Story 3.1/3.3); Chat's 4 iterations against several single cancels (medium, unverified); the key not tied to the verb (medium, unverified, for Story 8.4).
  - **Rejected (low or false), with the reason in the log:** the `NOTSENT` wording and the retry key (the spec's text, AD-1), `Answer` without a time for an unreadable `DueAt` (decision 19, now pinned), the untested shipping stub and the list contract written here (the intent's approach, DW-135), the label scan's "not generic" wording and floor, the 2027 date, `UseItemClass` after a killed run, the order of `Prepare`'s flags, `-5` as `BADDELAY` (the matrix lists it), `Answer` dropping `Outcome` and `Data`, AC2's single mutation, the preamble test, the ambient `TZ`, the cache marker's margin, `PutZone(-1)` giving "", and `IsSessionRef` on a Unicode build.
- **Follow-up review recommended: true.** Eight medium entries were patched (the threshold is two). The unverified risk is in the patches themselves: the fold of `Test.Bridge.Decide`, the scan in `TestZoneCase` and the failing status of `OnAfterAllTests` were each shown by a mutation, but no second reviewer has read them.
- **Verification.** Task 0 facts and the mutations are under Verification. The reviewed tree passed `ci/checks.sh`, `ci/iris.sh build`, the (loop) classes, `docker/tests/test-mock.sh` (94), `shard lane-a` (38 classes, forward and reversed), `shard lane-b` (24), `release/standalone-bridge.sh` (12 checks) and `live demo-path` (`@floor` passed); the throwaway `e1s10a` was torn down.
- **Residual risks.**
  - The real `CommandsIn` (Story 2.3) and `ReminderOps` (Story 8.4) do not exist: the tools are proved against the double, so the list contract (DW-135) and the owner's refusals are untested against their producer. Lane B's `Core.Commands` and `Core.CommandsIn` must stay free of `%AI` and Python, or `Test.Bridge.CodeRules` goes red at the merge.
  - A real model's choice of the due form and its date arithmetic is not measured (the mock scripts it).
  - A reviewer layer reported that it listed a folder under `irislib/` through the worktree's link to the main checkout (read only, nothing opened or changed). `HEAD` stayed `1e05e82` through every subagent, and nothing was pushed.

**Plan stage (2026-10-23, halted after planning as the dispatch asked).**
- **Sources.** The cached `epic-1-context.md`; Story 1.9's spec (done) for continuity; Story 1.10's block in `epics.md` with its two ledger bullets; Epics 3 and 8's reminder criteria; and the spine's AD-1, AD-4, AD-9, AD-10, AD-18, AD-29 and AD-33 with the Conventions.
- **The standard.** The spec meets the READY FOR DEVELOPMENT standard.
- **No runtime.** Nothing was measured or run against a runtime in this stage. Task 0 holds the measurements, with their stop conditions.
- **Warnings.**
  - `multiple-goals`: the reminder tools, the step-label scan (DW-85) and the zone fold (DW-32) could ship apart. The ledger routed both items to this story.
  - `oversized`.
- **The ledger inbox.** DW-32 and DW-85 are addressed by Tasks and by AC10 and AC9.
- **The Clarification Record** lists two items for the veto window and four for the lead. None blocks implementation.
- **Footprint.** Every file the plan edits is in Epic 1's footprint: `src/bridge/**`, `src/ocutalon/cls/OcuTalon/{Agent,Tools}/**`, `Test/{Agent,Bridge,Tools}/**` and `ci/mock/scenarios/A/**`. No contended path is edited. `Core/Commands.cls` is called, and `CommandsIn`'s class is swapped at test run time only, in throwaways.
