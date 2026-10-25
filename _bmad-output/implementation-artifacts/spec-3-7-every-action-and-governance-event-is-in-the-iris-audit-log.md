---
title: 'Story 3.7: Every action and governance event is in the IRIS audit log'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '9472b108217949721fb09e5f87c014fe276d2298'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-17, the AD-11 "States" bullet, the AD-23 "Who owns the steps" bullet, and the Consistency Conventions rows "Redaction", "Identifiers" and "Approval requests")'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Bridge.Audit.Write` writes whatever it is given, unredacted, and nothing calls it: no Approval API change reaches the IRIS audit log, there is no fixed data shape per type for the other lanes to write, and nothing tells an admin when instance-wide auditing is off, so FR-9 can fail quietly (DW-10).

**Approach:**
- `Bridge.Audit` gains `Record(type, data)`, the one writer for product code. It checks the type's one fixed shape, builds the description itself and writes through `Write`, which now redacts every entry.
- The five Approval state methods write an `Approval` entry for every change they make. Each entry names the IRIS user, session and channel on whose authority the change happened.
- The `Audit` step warns when instance-wide auditing is off and records that status. It never changes the setting.
- A reusable read-back helper in `OcuTalon.Test.Bridge` reads entries the moment they are written.

## Boundaries & Constraints

**Always:**
- **The shapes.** Every entry's data has the common members `irisUser`, `sessionRef` and `channel`, plus its type's members below, and no other member. Values are strings unless noted.

  | Type | Type members |
  | --- | --- |
  | `Action` | `action`, `target`, `result`, `counts` (an object whose values are numbers; `{}` when the action counts nothing), `approvalRef` |
  | `Approval` | `ref`, `kind`, `change`, `from`, `to`, `outcome`, `target`, `ownerRef` |
  | `Pairing` | `change`, `reason` |
  | `Settings` | `setting`, `from`, `to` |
  | `MCP` | `change`, `server` |
  | `Tool` | `source`, `tool`, `classification`, `readOnly` (the number 0 or 1) |

- **What `Record` refuses.** `Record` refuses the following before writing anything, with an error that names the type and the member, never the value:
  - a missing or extra member, or a value of the wrong JSON type;
  - an `irisUser`, `action`, `setting`, `server`, `source` or `tool` that is empty;
  - a `channel` outside `Bridge.Msg.Enum` `CHANNEL`;
  - a `sessionRef` or `approvalRef` that is neither empty nor a 22-character Ref, a `ref` that is not a Ref, or an `ownerRef` that is not empty, a Ref, `instance` or `eval`;
  - a `kind` outside `APPROVALKIND`, or a `from` or `to` outside `APPROVALSTATE`;
  - an Approval `change` outside `answered,expired,cancelled,started,finished`;
  - a Pairing `change` outside `linked,unlinked,rejected`;
  - an MCP `change` outside `added,removed`;
  - a `classification` outside `safe,risky,unclassified`.

  `Shape(type)` returns the type's members followed by the common ones.
- **Description and redaction.**
  - `Record` builds the description from the shape, never from free text:
    - `Action`: "<action>: <result>";
    - `Approval`: "Approval <ref> <change>: <to>";
    - `Pairing`: "Pairing <change>";
    - `Settings`: "Setting <setting> changed";
    - `MCP`: "MCP server <server> <change>";
    - `Tool`: "Tool <tool> of <source>: <classification>".
  - A `Settings` entry whose `setting` `Redact.SensitiveKey` flags has `from` and `to` replaced by `Redact`'s `REDACTED`. This happens on a copy, so the caller's object is unchanged.
  - `Write` passes the data's JSON and the description through `Redact.Text`, then calls `$SYSTEM.Security.Audit(OcuTalon, type, type, …)`.
  - When IRIS does not write the entry, `Write` returns an error that says so (no entry of type <type> was written: instance-wide auditing is off or the event is disabled or missing). Measured: IRIS returns 0 in each case.
  - `Write` keeps its pinned signature and accepts any dynamic object: it is the raw writer under `Record`, which `docker/tests/test-audit.sh` row 11 calls.
- **The Approval entries.** After the unlock, from the job that made the change, each change writes one `Approval` entry and then fires its event as before:
  - `ref`, `kind` and `ownerRef` come from the row;
  - `target` is `ToolName` (tool_call) or `IncidentRef` (fix);
  - `from` and `to` are the states;
  - `outcome` is `approved` or `rejected` for `answered`, FinishExecution's result for `finished`, and empty otherwise.
- **Who an entry names** (AD-17: the person, not the system user, whenever a person acted). `sessionRef`, when the caller gives none, is the row's `OwnerRef` if that is a Ref, else empty.

  | Change | `irisUser` | `channel` | `sessionRef` |
  | --- | --- | --- | --- |
  | Answer `done` (`answered`), or Answer past expiry (`expired`) | Answer's `irisUser` | Answer's `channel` | Answer's `sessionRef` |
  | Expire (the hold's timer, or a direct call) | the job's `$Username` | `system` | the row's |
  | Cancel | the new optional argument, else `$Username` | the argument, else `system` | the argument, else the row's |
  | StartExecution (`started`), FinishExecution (`finished`) | the row's `AnsweredBy` (the approver), else `$Username` | `AnsweredChannel`, else `system` | the row's |

- **API changes.**
  - `Answer` adds one `not_allowed` check, before any change: a `sessionRef` that is neither empty nor a Ref.
  - `Cancel` becomes `Cancel(ref, sinkClass = "", channel = "", irisUser = "", sessionRef = "")`. Before it locks, it refuses a given channel outside `CHANNEL`, or a sessionRef that is neither empty nor a Ref, with an error that names the argument, and changes nothing.
- **A failed write never undoes a change.** When `Record` fails, the change stands and the event still fires. A `$$$LOGWARNING` names the Ref, the change and the error, and the caller's result is unchanged. A refusal writes no entry.
- **DW-10.** `Install.Step.Audit.Run()`:
  1. still fails when an event is missing or disabled (`CheckAudit`);
  2. reads instance-wide auditing through the new `Bridge.Installer.InstanceAuditing(.enabled)`, a read-only `InSystem` action that changes nothing;
  3. records `on`, `off` or `unknown` (the read failed) in `Data.StatusMark` under the mark `instanceAuditing`, only when the value differs from the stored one, so `RecordedAt` says since when it holds;
  4. when auditing is off, it warns with exactly: `instance-wide auditing is off, so IRIS writes none of OcuTalon's audit entries; OcuTalon does not change this setting: an administrator turns it on in the Management Portal (System Administration > Security > Auditing > Enable Auditing)`. When the read fails, it warns `could not read whether instance-wide auditing is on: <error>`;
  5. returns OK in each of these cases. A warning never fails the start (AD-23).
- **The read-back helper** `OcuTalon.Test.Bridge.AuditLog`:
  - `Now()` returns the mark;
  - `Entries(since, source, type, event, marker, username)` returns `[{at, username, data, description}]`;
  - `Wait(…, count, seconds)` polls until `count` entries are found or `seconds` pass (default 10).
  - It queries `%SYS.Audit` in `%SYS`, constrained only by `UTCTimeStamp >= since` (the IDKEY). Every other condition is tested in ObjectScript. Tests find their own entries by a fresh Ref marker, never by a count of all entries.
- Tests run on throwaways only (`ci/iris.sh`, `ci/warm.sh`). A test that changes instance auditing, an event's Enabled flag or the `instanceAuditing` mark puts it back, also after a failure.

**Never:**
- No audit entry for `Raise`, the gate's held call or a refusal, and no `Action` entry written here: the first ones are Story 30.3's replay and Lane B's Break the feed.
- OcuTalon never changes instance-wide auditing or an event's state outside the bridge installer's existing registration. Only tests do it, on throwaways.
- No edit to a contended path: `docker/tests/test-audit.sh`, Lane B's `Data.StatusMark` (call its API only), `Core/**`, `docs/**`, the README. No `ci/units.sh` change.
- No caller-written free text in a product entry's description, and no member for a chat id, a display name, a key, a token or a password.

## I/O & Edge-Case Matrix

The marker of every row is a fresh Ref. "Read back" means `AuditLog.Wait` from a mark taken just before the call.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Every shape | `Record` of each of the six types with valid members, with the marker as `sessionRef` (`ref` for Approval) | One entry each: source `OcuTalon`, EventType and Event the type, data exactly `Shape(type)` with the given values, the derived description, `at` between the mark and now, Username the test process's `$Username` | -- |
| 2 | Any other shape | A missing member; an extra member `chatId`; `counts` "3"; `readOnly` 2; an Approval `change` of "deleted"; `channel` "sms"; a `classification` of "readonly"; `sessionRef` "zzsession"; an empty `irisUser`; type "Zz"; data that is not an object | Each is refused, naming the type and the member, never the value. No entry carries the marker within 2 s. | Refused before writing |
| 3 | No secret (AC 5) | `Write` with `apiKey`, `accessToken`, `password`, `chatId`, `displayName` and `marker`, and a description holding `Bearer <token>`. `Record` with an Action `result` holding `sk-ant-api03-<random>` and a `target` of `https://zz:<pw>@example.com/x`; a Pairing `reason` that is the JSON text of a Telegram update with `chat.id`, `first_name` and `username`; a Settings entry for `ZzBotToken` with opaque `from` and `to` | Read back, no random secret value appears in any entry's data or description; the markers and the non-secret members remain; the Settings `from` and `to` are `[redacted]` | -- |
| 4 | Answer (AC 2, AC 4) | A held fix answered `approve`, on `web`, by `ocutalon`, with a fresh `sessionRef` | One Approval entry: `answered`, `pending`→`approved`, `outcome` approved, `kind` fix, `target` the IncidentRef, the row's `ownerRef`, `irisUser` ocutalon, the given `sessionRef`, channel `web`; `at` in the window; Username the test process's (not ocutalon) | -- |
| 5 | Other answers | (a) a rejected tool_call; (b) an answer past expiry, then a second answer; (c) a malformed `sessionRef` | (a) `rejected`, `target` the ToolName. (b) `expired` naming the answerer, and the second answer adds no entry. (c) `not_allowed`, no change, no entry | -- |
| 6 | The timer (AC 2) | A re-armed past request expires on the hold's timer in its production job | One `expired` entry: `irisUser` equals the entry's Username (the hold job's user, not the test process's), channel `system`, `sessionRef` the OwnerRef | -- |
| 7 | Cancel | (a) `Cancel(ref, sink)`; (b) `Cancel(ref, sink, "web", "ocutalon", <fresh Ref>)`; (c) channel "fax", or sessionRef "zz" | (a) `cancelled` naming `$Username`, `system` and the OwnerRef; (b) naming the three arguments; (c) an error naming the argument, nothing changed, no entry | -- |
| 8 | Every transition (AC 3) | `TestEveryOtherTransitionIsRefused`'s grid of fixture rows | Each allowed change gives exactly one entry with its `change`, `from`, `to` and `outcome`: Expire names `$Username` and `system`; started and finished name the fixture's `AnsweredBy` and `web`. Each refusal or no-change result gives none | -- |
| 9 | Write fails | `OcuTalon/Approval/Approval` disabled; a held request answered | `done`, the row approved, `approval.answered` fired, one warning naming the Ref, no entry | Warned, change kept |
| 10 | DW-10 | Instance auditing off, then on | Off: `Run()` OK, exactly one warning (the text above), the mark `off`, the setting still off, and `Record` returns the not-written error. On: OK, no warning, the mark `on`, the setting still on | Never changes the setting |
| 11 | One writer (AC 1) | Every non-test OcuTalon class | None but `Bridge.Audit` calls `$SYSTEM.Security.Audit`, `##class(%SYSTEM.Security).Audit` or `Bridge.Audit`'s `Write` | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- the change.
  - `SOURCE` and `TYPES` (:7-10), `Events()` (:13).
  - `Write` (:31-40) gains the redaction and the not-written error; its comment (:24-30) changes.
  - Add `Record`, `Shape`, the shape and enumeration parameters, and the class comment.
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` -- reused unchanged: `Text` (:43), `SensitiveKey` (:56, public) and `REDACTED` (:25).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Answer` (:243-265): its `not_allowed` line is at :274 in `AnswerLocked` (:268-304); it fires after the unlock at :263.
  - `Expire` (:325), `Cancel` (:333), `StartExecution` (:341), `FinishExecution` (:351).
  - `Move` (:364-381) fires at :379. `MoveLocked` (:384-406) returns only `owner`: it returns the row's audit facts instead.
  - `Fire` (:426) is the pattern; `IsRef` (:210) is reused. The class comment (:3-21) and `Answer`'s comment (:229-242, where "accepted for the audit of Story 3.7") change.
  - The bridge logs with `$$$LOGWARNING` (:251).
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls`:
  - `RegisterAudit` and `CheckAudit` (:96-105);
  - `InSystem` (:167-206) gains a read action and an `Output`;
  - add `InstanceAuditing`.
  - `Security.System.Get("SYSTEM",.p)` gives `p("AuditEnabled")` (`test-audit.sh:67`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Audit.cls` (:1-12) -- the DW-10 change.
  - `Install/Step.cls:52` `Warn`.
  - `Install/Registry.cls:41-63` prints each line that `TakeWarnings` returns as `WARN <step> <text>`, to the after-start log, and to the IPM output on an IPM install. So the step's warning, as a test takes it, is the log line.
  - `Install/Step/Demo.cls:85-95` is the warn-and-record pattern.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls` -- read only, Lane B's: `Record(mark, value)` (:21) and `Get(mark)` (:39).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` -- extend it.
  - Class comment (:1-77).
  - `OnAfterOneTest` (:132).
  - The tests:
    - `TestAnswerApprovesAFix` (:812; it already makes a fresh `sessionRef`);
    - `TestAnswerRejects` (:835);
    - `TestAnswerRefusals` (:916; its cases at :928);
    - `TestTimerExpires` (:975);
    - `TestAnswerPastExpiry` (:1005);
    - `TestExpireDoesNotWaitForTheClock` (:1032);
    - `TestCancel` (:1051);
    - `TestEveryOtherTransitionIsRefused` (:1081-1154) with `Expected` (:2071) and `Run` (:2091).
  - The helpers:
    - `RaiseHeld` (:1897);
    - `FixtureRow` (:1916; approved rows have `AnsweredBy` `ocutalon` and channel `web`);
    - `NewRow` (:1392; a fresh OwnerRef);
    - `CallInJob` (:2138).
  - The 18 `"zzsession"` arguments (grep for them) become fresh Refs.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/WebStatus.cls`:
  - `AUDITSECONDS` (:41);
  - the poll (:129, :146-153);
  - `AuditMark` (:504) and `AuditRows` (:514): these use indexed predicates, so they wait for the index. `AuditLog` replaces them.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls` `TestAuditApi` (:72-92) and the class comment (:1-4).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:
  - `TestOnlyRunnersChat` (:168-199) is the model;
  - `Offenders` (:829), `CHATCALLS` and `CHATTERS` (:84-90);
  - the class comment (:1-43).
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- read only: `EventMark` (:182), `Warnings` (:1037), `SinkCalls` (:781) and `ReadyReason` (:306).
- `irissys/%SYS/Audit.cls`, read only:
  - the IDKEY `(UTCTimeStamp, SystemID, AuditIndex)` (:50);
  - `EventData` is `%Binary(MAXLEN=16384)` (:96) and `Description` is 128 (:81);
  - `UpdateIndices` runs every 60 s (:182-185).
- `docker/tests/test-audit.sh` -- contended, read only. Row 11 calls `Write("Action",{"marker":…})`, and the AD-17 block expects `Step.Audit.Run()` to succeed with auditing off.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:304-305` pins `Write(type,data,description)` and `Events()`. The check is a prefix, so `Cancel`'s new trailing arguments pass (:153-159).

## Tasks & Acceptance

**Execution:**
- [ ] `src/bridge/cls/OcuTalon/Bridge/Audit.cls`:
  - `Record`, `Shape`, and the parameters `COMMON`, `SHAPE<TYPE>` and the enumerations;
  - the derived description and the Settings blanking;
  - `Write` redacts the data and the description, and returns the not-written error;
  - the comments state the contract and name `Record` as product code's writer.
  - Why: rows 1 to 3 and 10, AC 1 and AC 5.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - one private helper builds the Approval data by the "who" table and calls `Record`, warning on an error;
  - `MoveLocked` and `AnswerLocked` hand it the row's facts;
  - `Move` and `Answer` write the entry after the unlock and before `Fire`;
  - `Answer`'s `sessionRef` check;
  - `Cancel`'s three optional arguments and their validation;
  - the comments.
  - Why: rows 4 to 9, AC 2 and AC 3.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Installer.cls` -- `InstanceAuditing(Output enabled) As %Status` through a new read-only `InSystem` action; its comment. Why: DW-10, AD-3.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Audit.cls` -- the DW-10 behaviour (Boundaries), a parameter for the mark name, and the class comment. Why: row 10, DW-10.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/AuditLog.cls` (new, no `Test` method) -- `Now`, `Entries` and `Wait`, as in Boundaries. Why: AC 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Audit.cls` (new test class) -- `TestEveryTypeHasOneShape` (row 1), `TestRecordRefusesAnyOtherShape` (row 2) and `TestNoSecretInAnyEntry` (row 3). Why: AC 1 and AC 5.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Audit.cls` (new test class) -- `TestInstanceAuditingOff` and `TestInstanceAuditingOn` (row 10). It saves `AuditEnabled` and the mark in `OnBeforeOneTest` and puts them back in `OnAfterOneTest`. Why: DW-10.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls`:
  - read-back assertions in the tests the Code Map names (rows 4 to 8, through `AuditLog`);
  - the new `TestFailedAuditNeverUndoesAChange` (row 9; it puts the event back in `OnAfterOneTest`);
  - every `"zzsession"` becomes a fresh Ref;
  - the class comment.
  - Why: AC 2 to AC 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `TestOnlyTheAuditWriterAudits` (row 11): samples flagged and passed, then `Offenders` with `OcuTalon.Bridge.Audit` allowed; the scan sees exactly that one class match. Update the comment. Why: AC 1.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls` -- `TestAuditApi` also pins `Shape(type)` for the six types and `Record` refusing an unknown type. It still writes nothing. Why: the shapes are a cross-lane contract.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/WebStatus.cls` -- the mark and the poll use `AuditLog` (with `AUDITSECONDS` as the bound and its username filter), and `AuditMark` and `AuditRows` go. Why: Rule 2, shard time.

**Acceptance Criteria:**
- Given OcuTalon's audit events are registered, when OcuTalon or the bridge writes an entry, then it goes only through `Bridge.Audit` (product code calls `Record`), with source `OcuTalon` and one of the six types, each in its one fixed data shape, and any other shape is refused before anything is written. Rows 1, 2 and 11 hold (FR-9, AD-17).
- Given production jobs run as the Interoperability system user, when an entry is written, then its data names the acting or answering IRIS user, the `SessionRef` and the channel, and the entry carries its time. Rows 4 and 6 hold (FR-9, AD-17).
- Given the Approval API, when `Answer`, `Expire`, `Cancel`, `StartExecution` or `FinishExecution` changes a row, then that change writes exactly one `Approval` entry; a refusal writes none, and a failed write never undoes the change. Rows 5, 7, 8 and 9 hold (FR-9, AD-11, AD-17).
- Given a test answers an approval request, when it reads the IRIS audit log back through `AuditLog`, polling with a bounded timeout, then it finds the approval entry with its time, IRIS user and session. `AuditLog` is reused by `Test.Bridge.Audit`, `Test.Bridge.Approval` and `WebStatus`. Row 4 holds (FR-9, AD-17).
- Given a model key, an access token, a password, and a Telegram chat id and display name in event data, when the entries are read back, then none appears in any entry. Row 3 holds (FR-9, NFR-11, AD-17).
- DW-10: given instance-wide auditing is off (an IPM install into an existing instance; build 154 ships it on), when the `Audit` step runs, then it says so plainly: a log warning (the registry's `WARN Audit` line) and a recorded status (the StatusMark `instanceAuditing`) that the security overview and the README can point to, so FR-9's "every action audited" never fails quietly. OcuTalon never changes the setting (AD-17) (ledger; routed by harvest 2026-10-19). Addressed by row 10 and the `Install.Step.Audit` and `Installer` tasks.
- Given the fresh `shard lane-a`, `shard lane-b`, `live audit`, `live install-start` and `live install-upgrade`, when they run, then every class and check passes.

## Spec Change Log

- 2026-10-25, lead spec gate: AD-17 is not amended. Its rationale's "IRIS writes some rows minutes late" is corrected by measurement in the new Consistency Conventions row "Audit entries" (Rule 20 light path: the shapes, `Record` versus `Write`, the derived description and redaction, the "who" rule, the order after the unlock, the read by `UTCTimeStamp` range, and the `instanceAuditing` mark), not in the AD's text, which a runner does not amend (U14). Ruled in the veto window and kept as planned: the six stored data shapes, the stronger redaction and the `Record`-only rule, `Answer`'s `sessionRef` check, the WARN line, and the new `StatusMark` row `instanceAuditing`.

## Review Triage Log

### 2026-10-25 -- Review pass
- verdicts: 40 findings -- high 0, medium 1, low 24, false 14, maybe-false 1
- findings:
  - Blind Hunter
    - `[false]` `[reject]` stale `Status: ready-for-dev` in Auto Run Result -- the section is rewritten at finalize.
    - `[low]` `[patch]` Step.Audit returned StatusMark.Record's error, failing the start for an informational mark -- now a warning, result OK.
    - `[false]` `[reject]` Audit depends on Approval.IsRef -- the spec's Code Map reuses `IsRef`; both are bridge classes (AD-2).
    - `[low]` `[reject]` Cancel's irisUser is unchecked -- the spec's who-table makes the argument the caller's statement; by design.
    - `[false]` `[reject]` a throw after %Save loses the entry -- CompleteHoldTask catches everything and MoveLocked builds the facts right after the save, so nothing throws between them.
    - `[low]` `[patch]` TestRecordRefusesAnyOtherShape matched the member as a bare substring -- now asserts the quoted member the error emits.
    - `[low]` `[patch]` missing negative cases (22-character Ref with bad characters, 21-character ref) -- two cases added; the non-sensitive Settings path stays untested (low, no failure scenario).
    - `[low]` `[reject]` Install.Audit restores the mark as "" when none existed -- a valid value; no test lists marks.
    - `[low]` `[reject]` AUDITCALLS misses indirect `$ClassMethod` of %SYSTEM.Security -- theoretical; the scan guards against accidental calls.
    - `[low]` `[reject]` AuditLog.Wait polls every 0.2 s -- only a failing wait runs long; WebStatus measured 15 s.
  - Edge Case Hunter
    - `[low]` `[reject]` empty irisUser and empty $Username -- an IRIS job always has a user.
    - `[false]` `[reject]` an OwnerRef outside Ref, instance, eval is refused -- those are Approval's values by design (AD-11).
    - `[low]` `[reject]` Answer with an empty sessionRef names the owner's session -- the spec's who-table rule (the row's OwnerRef when a Ref).
    - `[false]` `[reject]` a throw after save -- same as the Blind Hunter row (CompleteHoldTask catches).
    - `[low]` `[reject]` a crash between unlock and Audited loses the entry -- the spec's decided order (after the unlock, before the event); a crash drops the event too.
    - `[low]` `[reject]` Cancel checks its arguments before the Ref -- the error still names a real fault.
    - `[low]` `[reject]` 128 characters against bytes -- IRIS MAXLEN counts characters.
    - `[maybe-false]` `[reject]` redaction could leave invalid JSON -- Redact.Text re-serializes JSON objects; would only be low.
    - `[low]` `[reject]` non-string type argument -- theoretical.
    - `[low]` `[patch]` StatusMark.Record failure fails the start -- same as the Blind Hunter row (a read throwing <PROTECT> is theoretical).
    - `[false]` `[reject]` a missing AuditEnabled reads as off -- Security.System.Get always returns it.
    - `[low]` `[reject]` Install.Audit cannot restore auditing after a killed process -- throwaway stacks only; theoretical.
    - `[low]` `[reject]` TestTimerExpires needs the hold job's user to differ -- measured `_Ensemble` against `irisowner` on every stack.
    - `[low]` `[reject]` the grid reads entry.data as an object -- every entry read is OcuTalon's own.
    - `[false]` `[reject]` claim: descriptions hold caller text -- the spec derives them from shape members and redacts them.
    - `[low]` `[reject]` claim: 128 characters against bytes -- as above.
    - `[low]` `[reject]` claim: a mark failure fails the start -- patched with the row above.
  - Verification Gap
    - `[medium]` `[patch]` Write's redact-then-cut order and the 128 cut were unpinned -- a long-description case added to TestNoSecretInAnyEntry; mutation (cut first) shown red and recorded.
    - `[low]` `[reject]` the Audit step's "unknown" branch is untested -- needs a seam in InstanceAuditing that the story does not provide; listed as a residual risk.
    - `[low]` `[reject]` sub-behaviours without their own mutation line -- Rule 19 asks one demonstrated mutation per AC, and all are recorded.
    - `[low]` `[reject]` comment says bytes -- same as the Edge Case Hunter row.
    - `[false]` `[reject]` live install-start has no WARN Audit check -- the lead's run counted 0 `WARN Audit` lines on the fresh stack (auditing on).
    - `[false]` `[reject]` layering note on IsRef -- same as the Blind Hunter row.
  - Intent Alignment
    - `[false]` `[reject]` tests read by time, not by the indexed view -- measured and decided (index lag up to 60 s); the Rule is to poll with a bound.
    - `[false]` `[reject]` the warning is asserted in the in-process buffer -- Registry prints `TakeWarnings` as `WARN <step>` (Registry.cls:41-63).
    - `[false]` `[reject]` production callers are not changed -- other lanes' stories; `Answer`'s sessionRef rule is in the contract.
    - `[false]` `[reject]` Cancel's irisUser default -- the contract's who-table.
    - `[low]` `[reject]` long Tool or MCP names are cut at 128 -- the derived description is bounded by IRIS's field.
    - `[low]` `[reject]` the warning test names the private method Audited -- the Ref and the change are asserted.
    - `[false]` `[reject]` WebStatus and Contracts edited -- both are named in Tasks & Acceptance.

## Design Notes

**Architecture decisions:**
- **AD-17** governs.
  - The one writer, the six types and the redactor.
  - The person in the data: for a run's start and end, that is the approver.
  - "Never changes instance-wide auditing".
  - No audit table, read back with a timeout.
  - The role in the data is step 6's, not this release's.
- **AD-11:** every change is audited, and refusals change nothing. **AD-31:** events fire after the unlock as before, with the entry first.
- **AD-23:** a step's warning never changes its result. **AD-3:** the %SYS reads stay in the installers.
- **AD-2:** `Bridge.Audit` uses only bridge classes. **AD-22:** tests run on throwaways. **AD-29 and AD-33:** `StatusMark` is Lane B's table; this story calls only its cross-lane API, as Lane B's Demo step already does.
- No AC contradicts an AD's Rule.
- One factual point for the lead. AD-17's last bullet says IRIS "writes some audit rows minutes late (S8)". Measured: IRIS writes a row at once and indexes it up to 60 s later. The Rule (poll with a timeout) is unchanged.

**Measured at planning** (warm throwaway `e3s7pw`, build 154, torn down afterwards):
- **When an entry is readable.** After `Write`, the row was readable after 0.035 s by `UTCTimeStamp >= mark`. A query on `EventSource`, `EventType` and `Event` found it after 37.5 s, because `%SYS.Audit.UpdateIndices` runs every 60 s. Story 0.4's 53 to 72 s, and most of `WebStatus`'s 78 s, are that index lag.
- **Where to query.** `%SYS.Audit` reads 0 rows from OCUTALON, so queries run in `%SYS`. A fresh throwaway holds about 52,000 rows, so every query is bounded by time.
- **The row's own fields.**
  - `UTCTimeStamp` is `$ZDateTime($ZTimeStamp,3,1,3)` at the write, to the millisecond.
  - Username is the writing process's `$Username` (`irisowner` with `%All` in a `ci/iris.sh` session).
- **When IRIS writes nothing.** With instance auditing off, `$SYSTEM.Security.Audit` returned 0 and wrote no row, and `Write` returned `ERROR #00` with no text. With the event disabled, the same. The setting was restored.
- **Privileges.** A job logged in as a user who holds only `OcuTalonUser` wrote an entry with `$SYSTEM.Security.Audit` (Username: that user), so the write needs no privilege. That user could not run `Bridge.Audit` (`<PROTECT>` on the code database). Lane B's REST answers run with the web application's roles (inference).
- **The redactor.**
  - The six shapes pass `Redact.Text` unchanged.
  - Row 3's samples are redacted: `chat.id`, `first_name` and `username` inside JSON text; a bot token; `password=`; URL credentials; and the `apiKey`, `accessToken`, `password`, `chatId` and `displayName` keys.
  - Free text such as "display name Zz Jane Doe chat 987654321" is not redacted. Hence the structural rules: no identity member, and a derived description.

**Decided in-stage:**
- **`Record` beside `Write`.** `Write` is pinned (`Test.Contract.Ac`) and the contended `test-audit.sh` row 11 writes `{"marker"}` through it. A strict `Write` would need a contended edit, so the shape lives in `Record`, and `CodeRules` keeps product code on `Record`.
- **Raise and refusals are not audited.** The AC names the five methods and "changes a row". The epic context says Raise stays unaudited.
- **The "who" table.** The approver is named on a run's start and end, as Story 7.4 asks for its `Action` entry. The job's user and `system` are named only when no person acted.
- **The write's place.** The entry is written after the unlock and before the event, so the lock window is unchanged. A failed write is warned and never undoes the change. Refusing approvals on an instance with auditing off would break the product; DW-10 reports it instead.
- **The `Answer` check.** A malformed `sessionRef` is `not_allowed`, so a chat id can never land in the audit as "the session". The `Cancel` arguments let `SessionOps.End` and `McpOps` name the person without editing Lane A's file.
- **`Tool` shape.** It has `readOnly`, because Read-only is `safe` plus read-only (UX-DR145). An `Action`'s `counts` carries Story 7.4's resent, completed, failed-again and skipped counts.
- **The mark.** It is named `instanceAuditing`, with the values `on`, `off` and `unknown`, and is written only on a change.
- **Test classes.** `Test.Bridge.Audit` and `Test.Install.Audit` follow `OcuTalon.Test.<Area>.<Subject>`. `Test.Bridge.Contracts` promises to write nothing, so it keeps only the non-writing contract checks. `AuditLog` has no `Test` method, so `ci/iris.sh` does not run it as a test class.

**For the lead.**
- **Rule 20.** Add a Consistency Conventions row "Audit entries" with:
  - the six shapes;
  - `Record` versus `Write`;
  - the derived description;
  - the Settings blanking;
  - the "who" table;
  - the entry written after the unlock and before the event, and a failed write that is warned and kept;
  - the read by `UTCTimeStamp` range.

  Then correct AD-17's S8 rationale (above).
- **The veto window.** No item is owner-only.
  - A new stored format: the six data shapes in IRIS audit entries. The AC mandates them, and no existing data changes.
  - Security posture is strengthened: every entry is redacted, a sensitive setting's values are blanked, and product code writes only through `Record`.
  - `Answer`'s guarantee is tightened (`sessionRef`).
  - A new admin log text: the WARN line, which DW-10 asks for.
  - A new `StatusMark` row, with no schema change.

**Integration ACs:**
- In this story, the Approval API consumes `Record`: the entries are read back from the IRIS audit log by `AuditLog` (rows 4 to 9).
- `Install.Step.Audit` consumes `InstanceAuditing` and `StatusMark.Record`: the observable effects are the WARN line and the mark (row 10).
- `WebStatus` consumes `AuditLog`.

**Consumes:**
- From Story 0.4: `Write`, `Events` and the registration.
- From Story 3.5: the five state methods.
- From Lane B's `StatusMark`: `Record` and `Get`.
- The redactor.

**Consumed-by:**
- **Story 4.1** (`SettingsOps`, `Settings`).
- **Story 4.3** (Break the feed, `Action`).
- **Story 7.4** (resend, `Action` with `counts`).
- **Stories 10.3 and 12.5** (`SessionOps`, `Pairing`).
- **Story 16.4** (`SessionOps.End`: `Cancel` with the person).
- **Stories 22.1 to 22.4** (`McpOps`: `MCP`, `Tool`, an `Action` per MCP call, `Cancel`).
- **Story 30.3** (the replay's `Action`).
- **Story 11.1** (the demo-path read-back: it must read by `UTCTimeStamp` range).
- **Story 14.2** (the overview lists `Shape()` and points to `instanceAuditing`).
- **Story 15.2's `docs/install-ipm.md`, which Lane B's Story 31.3 copies into the README** (the WARN line and the mark).

**Cross-epic:**
- **Epic 13:** the installer registers the same six events, and the new `InstanceAuditing` is read-only. The Approval API now audits wherever it runs; the example holds no request today.
- **Lane B's `AnswersIn` (Stories 6.2 and 12.7)** must pass a 22-character `SessionRef` or "". Anything else is `not_allowed`.

**Rule 2 (extend, don't copy):**
- Extended: `Audit`, `Approval` (`Move`, `MoveLocked`, `Answer`), `Installer.InSystem`, `Step.Audit`, `TestAuditApi`, `CodeRules` (through `Offenders`) and `Test.Bridge.Approval`'s tests and fixtures.
- `Redact` is reused unchanged.
- `WebStatus`'s private `AuditMark` and `AuditRows` are the sibling of `AuditLog`, which replaces them.

**Footprint:**
- Every edit is in `src/bridge/**` (not `BridgeExample`), `Install/Step/Audit.cls` and `Test/{Bridge,Install}/**`.
- No footprint extension. No contended path is edited.

**Ledger inbox:** DW-10 is addressed by row 10, the `Installer` and `Install.Step.Audit` tasks and the DW-10 acceptance bullet.

**Shard time (inference):**
- **The new tests add about 5 to 10 s.** Entries are readable at once, so no test waits for the index.
- **`WebStatus` should drop by about 40 to 70 s** if `AccessDenied` rows are as immediate as OcuTalon's. Only OcuTalon's own were measured. Its bound stays 120 s, so correctness does not depend on this.
- **Expected fresh `lane-a`:** about 350 to 440 s, against the 480 s line. No `ci/units.sh` change.
- **If the measured fresh `lane-a` passes 470 s,** the implement stage stops with a clarification and does not edit `ci/units.sh`. It reports the per-class times and proposes a third Lane A shard holding the `Install` area:
  - `SHARDS="lane-a lane-a2 lane-b"`;
  - `shard_areas`: `lane-a)` "Agent Bridge Tools Digest" and `lane-a2)` "Install";
  - `group_units`' `shards)` line: `shard:lane-a shard:lane-a2 shard:lane-b`.

## Verification

**Targets:**
- `ocutalon-slot-a` (namespace `OCUTALON`) is for `iris_doc_load` compiles only, after `iris_server_info` shows build 154. Pass `server` and `namespace` on every MCP call.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run each command from the worktree root, in the foreground with `timeout: 600000`, one per call.
- The tags: fresh `e3s7i` and warm `e3s7iw` (implement); `e3s7q` and `e3s7qw` (QA); `e3s7r` and `e3s7rw` (review). Each stage puts its own tags and stage name on the line.
- Warm runs reload classes only. The Audit step's start-time behaviour is proved by the fresh `live` units.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes. About 20 s.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7iw bash ci/warm.sh up` -- expected: a ready warm stack (about 60 s). Run it once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s7iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes are `OcuTalon.Test.Bridge.Audit`, `OcuTalon.Test.Install.Audit`, `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Bridge.Contracts`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Bridge.WebStatus` and `OcuTalon.Test.Bridge.Gate`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh shard lane-a` -- expected: every class passes. About 350 to 440 s; run it alone in its call and record the time and `WebStatus`'s time.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh shard lane-b` -- expected: every class passes. About 70 s.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh live audit` -- expected: PASS (row 11 still writes through `Write`, and the step succeeds with auditing off).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh live install-start` -- expected: PASS, with no `WARN Audit` line, since auditing is on.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh live install-upgrade` -- expected: PASS.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s7i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s7i` is left.

**Shared surfaces:**
- **`Answer`** refuses a malformed `sessionRef`. The 18 `"zzsession"` arguments in `Test.Bridge.Approval` change; `Test.Bridge.Gate` passes "" and is unaffected.
- **`Cancel`** gains three trailing optional arguments. No existing caller changes.
- **`Write`** now redacts. Row 11 of `test-audit.sh` is unaffected: its marker holds nothing sensitive.
- **The IRIS audit log** gains an `Approval` entry for every state change in every test. It is append-only, and no test counts all entries (`WebStatus` counts its own fixture user's rows).
- **The `instanceAuditing` StatusMark row** is written at every start where it changed. No test lists all marks.
- **`WebStatus`** loses `AuditMark` and `AuditRows`.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `Test.Bridge.Audit.TestRecordRefusesAnyOtherShape` | `Record` drops its extra-member check |
| AC 1 | `CodeRules.TestOnlyTheAuditWriterAudits` | `Approval` calls `$SYSTEM.Security.Audit` directly |
| AC 2 | `Test.Bridge.Approval.TestAnswerApprovesAFix`, `TestTimerExpires` | the Approval entry takes `irisUser` from `$Username` for an answer; or names the answerer for the timer's expiry |
| AC 3 | `TestEveryOtherTransitionIsRefused` | FinishExecution writes no entry; or `Move` writes its entry before the state check (a refusal writes one) |
| AC 3 | `TestFailedAuditNeverUndoesAChange` | `Answer` returns `not_found` when the write fails |
| AC 4 | `TestAnswerApprovesAFix` | the Approval entry is written with an empty `sessionRef` |
| AC 5 | `Test.Bridge.Audit.TestNoSecretInAnyEntry` | `Write` skips `Redact.Text`; or the Settings blanking is removed |
| DW-10 | `Test.Install.Audit.TestInstanceAuditingOff` | the step returns without the warning or the mark; or it turns auditing on |
| Answer and Cancel | `TestAnswerRefusals`, `TestCancel` | the `sessionRef` check is removed; `Cancel` ignores its `irisUser` argument |

**Mutations run** (Rule 19, warm stack `e3s7iw`; each file restored byte-identical from a scratchpad backup and the class green again):
- mutation: `Record` drops its extra-member check -> `Test.Bridge.Audit.TestRecordRefusesAnyOtherShape` red
- mutation: `Approval` calls `$SYSTEM.Security.Audit` directly -> `CodeRules.TestOnlyTheAuditWriterAudits` red
- mutation: `Answer`'s entry takes `irisUser` from `$Username` -> `TestAnswerApprovesAFix`, `TestAnswerRejects`, `TestAnswerPastExpiry` red
- mutation: `Expire` names `ocutalon` (the answerer) for the timer's expiry -> `TestTimerExpires` (and `TestExpireDoesNotWaitForTheClock`, `TestEveryOtherTransitionIsRefused`) red
- mutation: `FinishExecution` passes an empty change, so it writes no entry -> `TestEveryOtherTransitionIsRefused` red
- mutation: `Move` writes an entry for a refused change -> `TestCancel` and `TestExpireDoesNotWaitForTheClock` red (their refused second call must add no entry)
- mutation: `Answer` returns `not_found` when the write fails -> `TestFailedAuditNeverUndoesAChange` red
- mutation: `Answer` writes the entry with an empty `sessionRef` -> `TestAnswerApprovesAFix`, `TestAnswerPastExpiry`, `TestAnswerRejects` red
- mutation: `Write` skips `Redact.Text` -> `Test.Bridge.Audit.TestNoSecretInAnyEntry` red
- mutation: `Write` cuts the description at 128 before redacting it (a `sk-` key straddling the cut stays unredacted) -> `Test.Bridge.Audit.TestNoSecretInAnyEntry` red (two assertions of the long-description entry)
- mutation: the Settings blanking is removed -> `Test.Bridge.Audit.TestNoSecretInAnyEntry` red
- mutation: the `Audit` step returns before reading auditing, so no warning and no mark -> `Test.Install.Audit.TestInstanceAuditingOff` and `TestInstanceAuditingOn` red
- mutation: the `Audit` step turns instance-wide auditing on -> `Test.Install.Audit.TestInstanceAuditingOff` red
- mutation: `Answer`'s `sessionRef` check is removed -> `TestAnswerRefusals` red
- mutation: `Cancel` ignores its `irisUser` argument -> `TestCancel` red

## Auto Run Result

Status: done
Blocking condition: none

**Implement and review (this pass).**
- **Summary.** `Bridge.Audit` gained `Record` and `Shape` (six fixed shapes, a derived description, Settings blanking) and `Write` now redacts the data and the description (redact, then cut at 128) and returns a plain error when IRIS writes nothing. The five Approval state methods each write one `Approval` entry after the unlock and before the event, naming the person by the who-table; a failed write is warned and the change stands. `Answer` refuses a malformed `sessionRef`; `Cancel` takes `channel`, `irisUser` and `sessionRef`. `Installer.InstanceAuditing` reads instance-wide auditing; the `Audit` step warns and records the `instanceAuditing` mark (DW-10). `Test.Bridge.AuditLog` reads entries by time.
- **Files.** `src/bridge/cls/OcuTalon/Bridge/{Audit,Approval,Installer}.cls`; `src/ocutalon/cls/OcuTalon/Install/Step/Audit.cls`; new `Test/Bridge/{AuditLog,Audit}.cls` and `Test/Install/Audit.cls`; extended `Test/Bridge/{Approval,CodeRules,Contracts,WebStatus}.cls` (`WebStatus` lost `AuditMark` and `AuditRows`).
- **Review.** Four layers, 40 findings: 5 patch rows applied (1 medium, 4 low: the long-description pin, the Step.Audit mark failure, the quoted-member assertion, two extra negative cases), 0 deferred, 35 rejected with their reasons in the triage log. Follow-up review recommended: false (one medium patched).
- **Verification.** `bash ci/checks.sh` passes. On the warm stack every loop class passed (Audit, Install.Audit, Approval, Contracts, CodeRules, WebStatus, Gate). After the last patch, on fresh `e3s7i` stacks: `shard lane-a` 398 s, all 46 classes passed (`WebStatus` 15.5 s, against 78 s before); `shard lane-b` 76 s, 24 passed; `live audit`, `live install-start` (no `WARN Audit` line) and `live install-upgrade` passed. Teardown left nothing tagged `e3s7i` or `e3s7iw`. Fifteen mutations are recorded in `## Verification`, each shown red and restored.
- **Residual risks.** (1) The Audit step's `unknown` branch (the read of the setting fails) and the mark-write warning have no test, because `InstanceAuditing` has no seam to fail. (2) `Shape(type)` returns a `%List`, like `Events()`; `Contracts` pins that. (3) The entry is written after the unlock, so a process death in between loses one entry (and its event), as designed. (4) The "no entry" checks rely on entries being readable at once (measured), with a bounded wait only where a count is expected. (5) `Move` gained four optional arguments and `Answer` a parameter, all private to the class.
