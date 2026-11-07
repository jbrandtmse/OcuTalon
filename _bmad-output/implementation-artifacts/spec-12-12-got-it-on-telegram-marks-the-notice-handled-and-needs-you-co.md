---
title: 'Story 12.12: Got it on Telegram marks the notice handled, and needs-you counts only what still needs you'
type: 'bugfix'
created: '2026-11-07'
status: 'blocked'
baseline_revision: '71bd67af44df6a945aa1f4283bbacc6df2c79dcb'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-4, AD-14, AD-27, AD-28 and AD-33)'
warnings: ['oversized']
deferred:
  - summary: 'Data.Handled has no Purge(daysToKeep), and OcuTalon.Install.Task.Purge (Lane A) calls none, so on a local install (durable sessions, never ended) Handled rows grow by one per Got it press, and outlive the Decisions that Bridge.Purge removes after 90 days.'
    evidence: 'AD-27 lists the areas Install.Task.Purge calls; Data.Handled is not one. SessionOps.End (this story) deletes them only for an ended online-demo session; a demo reset restores the golden copy.'
    location: 'src/ocutalon/cls/OcuTalon/Data/Handled.cls; src/ocutalon/cls/OcuTalon/Install/Task/Purge.cls (Lane A, outside this footprint)'
    severity: 'low'
---

<intent-contract>

## Intent

**Problem:** Story 17.6 sends tell-now notices to Telegram with a **Got it** button, and the press reaches `SessionOps`, which still answers the 5003 stub: nothing is marked handled, the message is never edited, and the digest's needs-you count only grows, because `Digest.NeedsYou` reads up to 1,000 Decisions with no time window (DW-873). `Data.Handled` also has no end-of-session delete (DW-695).

**Approach:** Build the `GotIt` branch of `SessionOps` for Telegram's press (ruling D1 (a)): check the Ref and the session's own tell-now Decision, write one `Data.Handled` row (the first press wins through its unique `RefIndex`), and send one `handled` Notification to Notify, so `TelegramOut`'s existing `EditHandled` edits the message. `SessionOps.End` deletes the session's Handled rows. `NeedsYou` counts tell-now and act Decisions only when they are unhandled and recorded at or after the digest's `WindowStart`; failed rows and awaiting incidents always count.

## Boundaries & Constraints

**Always:**
- The GotIt branch reads the Decision only through `OcuTalon.Data.Ownership.Decision(ref, sessionRef, .sc)` (AD-4) and compares its `Ref` exactly afterwards. It accepts the Decision only when its `Outcome` is `tellnow`.
- A refusal (the Ref is not `Bridge.Approval.IsRef`, it names no Decision, it names another session's Decision, the Decision is not tell-now, or the Channel is not a `Msg.Enum` CHANNEL value) writes no row, sends no Notification and answers Ok 0. Already handled answers Ok 1 and changes nothing.
- `HandledAt` is `OcuTalon.Data.Time.NowUtc()`, `Channel` is the command's, and `Ref` is the Decision's own `Ref`.
- The End step goes through a private seam like the other End drops. It is tried whatever the earlier steps did, and a failure (error status or throw) adds 1 to `failed`, so the resume hash is kept.
- Failed check rows and incidents awaiting approval count in needs-you whatever their age. AllClear keeps reading `needs.count` (AD-28).
- No new user-facing string. The SessionOps `MESSAGE*` parameters are model- and log-facing, as the existing ones are. Source is ASCII, and comments state the contract (Rule 14).
- Live Telegram tests run against the CI mock on throwaway stacks only (AD-22). No real bot, chat or token.

**Never:**
- No edit to `Channel/Telegram/Out.cls` (contended with Story 17.10), `Channel/Telegram/In.cls`, `Core/Rule/Notify.cls`, `Channel/WebChat/Out.cls`, `Channel/SimPhone/Out.cls`, `Data/Ownership.cls`, `Msg/**`, `ci/units.sh`, the workflows or any `digest.*` / `handled.*` / `button.*` catalog text.
- No web chat or Simulated phone Got it control, and no handled copy on those channels (Story 18.4).
- No change to the `CommandsIn` route table, and no restructuring of End's existing steps (it is a shared-by-entry file: append one entry).
- No purge-task change (see Design Notes, Declined DW-695 part).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Press (DW-873) | GotIt {Ref of session A's tellnow Decision, Channel telegram, SessionRef A, origin telegram} | One Handled row {Ref, A, NowUtc, telegram}; one Notification {SessionRef A, Kind handled, DecisionRef Ref} to Notify; Ok 1, Outcome `handled` | No error expected |
| Press through Telegram (integration, DW-873) | Paired chat presses Got it under a tell-now message whose Decision is the session's | TelegramIn submits, SessionOps marks, Notify routes, TelegramOut edits the message once to its text, a blank line and `handled.marked` with the marker's time, with no reply_markup | No error expected |
| Second press | Same Ref again, Channel telegram or web | No new row (the first row's HandledAt and Channel are unchanged), no Notification, Ok 1, Outcome `already_handled`; on Telegram no second edit | Unique `RefIndex`: a failed insert whose Ref now exists is read as already handled |
| Refused | Ref "" or "notaref"; an unknown 22-character Ref; session B's tellnow Ref; A's act or ignore Decision; Channel "zz" | No row, no Notification, Ok 0, Outcome `not_found` | No error expected |
| Notice send fails | `SendNotice` returns an error | The row stands, one warning, Ok 1 `handled` | Warning only (the Unlink precedent) |
| Insert fails otherwise | `%Save` fails and the Ref is still not marked | No Notification, Ok 0, Outcome `failed`, one warning | Warning |
| End (DW-695) | EndSession for A, with Handled rows of A and of B | A's rows deleted, B's kept, `ended` | A failed or thrown delete gives `failed`; the other steps still ran; the resume hash is kept; a later End finishes |
| Needs-you window (DW-873) | WindowStart W; unhandled tellnow at W-50m, at W and at W+50m; a handled one at W+20m; act at W-40m; an incident awaiting approval noticed W-90m; a failed row checked W-95m | Counted: the failed row, the tellnow at W, the tellnow at W+50m, the incident (4). Not counted: the old tellnow, the old act, the handled one | No error expected |
| No window | windowStart "" | Every unhandled tellnow/act up to DECISIONMAX counts, as today (the safe over-count) | No error expected |
| Eval case | owner eval | Failed rows alone, as today (FinishCase passes "") | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- the operation. `OnMessage` :66-83 (:71 is the 5003 stub; :72-77 is the class allow-list, the 5001 refusal text and the `$Case` dispatch). `Unlink` :95-136 is the pattern for a notice: a `Notification` built and sent through `SendNotice`, with a failure logged as a warning. `End` :239-257 (the `failed` sum :254, `EndResume` :255). The drop pattern is `EndDocumentsAndMemories` :492-517 with its seams `DropDocuments`, `DropMemories` and `DropUploads` :520-535. `Result` :481, `Warn` :405, `ChannelOf` :443, `SendNotice` :475. The class doc :3-31 lists the commands.
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- `Ref`, `SessionRef` (EXACT), `HandledAt`, `Channel`; `RefIndex` unique :23; `Marked` :26. The doc :1-4 names Story 18.4 as the writer. `Data/Upload.cls` `DropSession` :80-91 is the sibling to mirror (select the IDs, then delete them; a row that is already gone is not an error).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `Decision(ref, sessionRef, .sc)` :507-514 (statement :856-858, `WHERE Ref = ? AND OwnerRef = ?`). `Bridge.Data.Decision.Ref` has the default collation, so compare `decision.Ref = command.Ref` after the read. `Decisions` :369 (`decide` only, newest `RecordedAt` first, :852-854). Read only.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls:287` -- `IsRef` (22 characters of `[A-Za-z0-9_-]`). Read only.
- `src/ocutalon/cls/OcuTalon/Msg/Command/GotIt.cls` -- `Ref`, `Channel`. `Msg/Enum.cls` CHANNEL :36 and NOTIFICATIONKIND :30 (`handled` is in it). Read only.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- the route :202 (keep it). The doc line :184 says "(a stub answer until Story 18.4)". Stub mapping (`IsStub`, :93, :163) is unchanged.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:416-427` -- `GotIt` submits only for the paired chat's own Delivery row. `Outcome` :570 ignores the answer's text. Read only.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls:172,346-373` -- `EditHandled`: `DeliveryByRef`, then `Handled.Marked`, then `editMessageText` with `handled.marked` {time}; a repeat is a no-op. Read only (contended at :200-270).
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls:42-53` -- kind `handled` takes the generic route: WebChatOut, SimPhoneOut on demo, TelegramOut when paired. Read only.
- `Channel/WebChat/Out.cls:61-62` and `Channel/SimPhone/Out.cls:58-59` -- a non-card kind records a bare Delivery row (no text, no event). `Ownership` RecentNotices :910 reads only the card kinds, so nothing new shows on the page or phone. Read only.
- `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls` -- `List` :27-79; the Decision loop :58-66; `DECISIONMAX` :20; incidents :45-57 (no time filter; keep it so).
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls` -- `WindowStart` :382-388 (the newest `SentAt`, else `FIRSTWINDOW` 86,400 s before now). `Queue` :377 sets `compose.WindowStart`. `Finish` :589-662 calls `Verdict` :599. `FinishCase` :484 calls `Verdict` with EVAL. `Verdict` :674-702 calls the `NeedsYou` seam :695. The seam is at :875-878, and the class doc is :35 and :54. No subclass overrides `Verdict` or `NeedsYou` (`Test/Digest/{ProcessProbe,FailRowsDigest,FedRowsDigest}.cls`).
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsProbe.cls` -- captures `Notices`, with `NoticeAnswer`. `Test/Core/SessionOpsDropProbe.cls` is the drop-probe pattern (read only, because Epic 19 may touch it). `Test/Core/SessionOps.cls` `Probe()` :744, `End(probe, origin, session)` :813, and the End tests are the pattern to follow.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsCommands.cls` -- `TestGotItNotBuilt` :150-168 and its header line :12. `NewCommand` :193.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Session(user)` :22, `Decision(owner, kind, recordedAt, fields)` :141, `Clean(refs)` :369. Clean does not delete Handled rows, so tests delete their own by Ref.
- `src/ocutalon/cls/OcuTalon/Test/Digest/NeedsYou.cls` -- the helpers `At`, `Decision`, `Incident`, `Handle`, `Failed`, `Names`, `List` :50-111. Existing tests call `List` with three arguments, and must stay green unedited.
- `src/ocutalon/cls/OcuTalon/Test/Digest/ProcessProbe.cls` -- `Reset`, `Feed`, `Record("notice", n)`, `Clean`, `ForgetChannels`/`PutChannelsBack`, `OwnChannels`. The Compose recipe is `Test/Channel/TelegramDigest.cls` `DigestNotice` :162-184.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramDigest.cls` -- the LiveCase class: `Paired` :119, `Press` :130, `TellNow`/`TellNowText` :138-153, `ToOut` :156, `Rows` :203, `Mark` :242, `Tidy` :100 (deletes `..Marked` ids). `TestGotItPairedChat` :457 uses a Ref with no Decision: the built command refuses it (Ok 0), and the test, which counts submitted commands, stays green. `TestHandledEdit` :524 is the assertion recipe for the edit. `LiveCase.WaitCalls(method, count, seconds)` :476.
- Tests found that expect GotIt's stub (grep `GotIt|not_built|5003` over `Test/`): only `Test/Core/SettingsCommands.cls` `TestGotItNotBuilt`. The others need no change, because they do not assume GotIt is a stub: `Test/Contract/Ac.cls` :227 and :263 (property shape and class list), `Test/Msg/Contracts.cls` :410 (shape), `Test/Core/CommandsRouting.cls` `TestStubOwner`, `CommandsStep3`, `CommandsHeartbeat` (generic stub mapping through probes), `Test/Core/SessionOps.cls` `TestOtherMessagesAreRefused` (uses SetDemoMode), and `Test/Install/Production.cls` `TestStubsAnswer` (SessionOps carries no STUB).
- Digest tests whose tell-now fixtures must stay inside the window: `Test/Digest/Compose.cls` `Decision` :267 (at most 600 minutes before the end of a 24-hour window) and `Test/Channel/TelegramDigest.cls` :266, :316, :338 (NowUtc). Both stay inside.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- add `ClassMethod DropSession(sessionRef As %String) As %Status`. It deletes every row of the session and no other session's, mirroring `Data.Upload.DropSession`: an empty sessionRef is OK, and a row that is already gone is not an error. Correct the class doc: the writer is SessionOps' GotIt branch (Story 12.12; Story 18.4 adds the web and phone controls), and `SessionOps.End` deletes a session's rows. -- DW-695's delete, in the table's own class (Rule 2).
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls`:
  - Replace the 5003 line with the GotIt branch: add GotIt to the class allow-list, the 5001 text and the `$Case`, and add a private `GotIt(command) As CommandResult`. In order it checks the Channel (`Msg.Enum` CHANNEL), `IsRef(command.Ref)`, `Ownership.Decision(command.Ref, command.SessionRef, .sc)` (exact Ref) and `Outcome = "tellnow"`. Any of these failing is `Result(0, "not_found", MESSAGENOTICENOTFOUND)`; a read error is `Failed`.
  - Next comes `Handled.RefIndexExists(ref)`, which answers `Result(1, "already_handled", MESSAGEALREADYHANDLED)`. Otherwise it saves a new Handled row: if the save fails and `RefIndexExists` is now true, the answer is already_handled; if the save fails and it is still false, `Failed`.
  - Then it sends one Notification {SessionRef, Kind "handled", DecisionRef, CatalogKey "", Slots "{}"} through `SendNotice`. A failed send is a warning. The answer is `Result(1, "handled", MESSAGEHANDLED)`.
  - Add three MESSAGE parameters, which are model- and log-facing: "The notice is marked as handled.", "The notice was already marked as handled, so nothing was changed." and "That notice is not known, so nothing was marked."
  - Add `EndHandled(sessionRef) As %Integer` (Try/Catch, 1 on an error status or a throw, with a `Warn`) over a private seam `DropHandled(sessionRef) As %Status` that calls `Handled.DropSession`. Append `+ ..EndHandled(sessionRef)` to End's `failed` sum (:254), before `EndResume`.
  - Update the class and End docs (the GotIt bullet; End's steps). -- DW-873, DW-695.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- doc line :184 only: drop "(a stub answer until Story 18.4)". -- The comment must state the contract (Rule 14). The route table is unchanged.
- `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls` -- `List(sessionRef, failedRows, Output sc, windowStart As %String = "")`. With windowStart not "", the Decision loop skips (Continue, never Quit) a Decision whose `RecordedAt` is not "" and is before windowStart (a string compare of UTC ISO times, as `Process.Saved` does). There is no upper bound. Incidents and failed rows are unchanged. Keep `DECISIONMAX`. Update the class doc: item 2 is "recorded at or after the window's start", and items 1 and 3 count whatever their age. -- DW-873's count.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls` -- `Verdict(owner, rows, vitals, Output verdict, windowStart As %String = "")` passes the window to the seam `NeedsYou(sessionRef, failedRows, Output sc, windowStart As %String = "")`, which passes it to `List`. `Finish` passes `compose.WindowStart`, and `FinishCase` passes "" (eval reads no Decision). Update the doc of item 4 :35 and of `Verdict`'s needs :671. -- It threads the window.
- `src/ocutalon/cls/OcuTalon/Test/Core/GotItProbe.cls` (NEW, test support) -- `Extends OcuTalon.Test.Core.SessionOpsProbe`. It has the property `FailHandled` ("", "error", "throw") and overrides `DropHandled`, recording the call as `^OcuTalonTest("GotItProbe", n) = sessionRef` and then answering as SessionOpsDropProbe's drops do (`##super` for ""). It has no Test methods. -- It extends the existing probe, not a copy (Rule 2).
- `src/ocutalon/cls/OcuTalon/Test/Core/GotIt.cls` (NEW) -- the unit tests over a shadow instance of GotItProbe, on fixture sessions and Decisions. Each test removes its Decisions, sessions and Handled rows by Ref in `OnAfterOneTest`.
  - `TestPressMarksHandled`: one row, with Ref, SessionRef, Channel telegram, and HandledAt matching `^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$` and within 5 s of now; one Notice of kind handled with DecisionRef and SessionRef; `1|handled`.
  - `TestSecondPressNoOp`: a second press with Channel telegram, then one with Channel web: `1|already_handled`, still one row with the first HandledAt and Channel, and still one Notice.
  - `TestOtherSessionRefused`: session B's tellnow Ref, unhandled and then handled by B, is `0|not_found` both times, with B's row unchanged and no Notice.
  - `TestNotTellNowRefused`: act and ignore Decisions.
  - `TestNotARefRefused`: "", "notaref", and an unknown NewRef.
  - `TestBadChannelRefused`: Channel "zz".
  - `TestNoticeFailureStands`: `NoticeAnswer` "error".
  - `TestEndDeletesHandled`: End deletes A's rows and keeps B's (`1|ended`).
  - `TestEndHandledFailureCounts`: for "error" and "throw", End answers failed, the resume hash is kept, the step was tried (the global), A's row is still there, and a later End with `FailHandled` "" answers ended and deletes it.
  - Every refusal asserts that no row and no Notice was made. -- AC1 to AC4 and the matrix.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsCommands.cls` -- replace `TestGotItNotBuilt` with `TestGotItBuilt`: the real SessionOps shadow instance answers a GotIt from web_user whose Ref names no Decision with status OK and `0|not_found` (not 5003), and writes no Handled row. Update header line :12. -- Its pin is the stub's removal.
- `src/ocutalon/cls/OcuTalon/Test/Digest/NeedsYou.cls`:
  - Add `TestWindow`: the matrix row "Needs-you window", with W = `At(100)`, giving count 4 and names in List's order.
  - Add `TestNoWindow`: the same fixtures with windowStart "", so the old tellnow and old act count too.
  - Add `TestProcessWindow`: a ProcessProbe shadow instance handles a Compose (WindowStart `At(100)`, WindowEnd `At(200)`, `OwnChannels` "web", `Feed([])`, channels forgotten and put back) for a session with an unhandled tellnow at `At(50)` and one at `At(150)`. The notice's `digest.needsYouOne` names only the one at 150. `ProcessProbe.Clean` the session.
  - Existing tests stay unedited. -- AC5, and the threading pin.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramDigest.cls` -- add `TestGotItEdits` on a free fixture chat (append ids to `CHATS` and the header range). Steps:
  - Pair the chat. Make a tellnow Decision for the session (`Fixture.Decision(session, "decide", NowUtc, {"Outcome": "tellnow", ...})`, kept) and send `TellNow(session, thatRef)`.
  - Press `gotit:<ref>` and wait for `editMessageText` (`WaitCalls`).
  - Assert one edit to the chat: the message id of the tell-now message, the text `TellNowText()` + blank line + `Render("handled.marked", {"time": Handled.Marked(ref)}, "telegram")`, and no reply_markup.
  - Assert the Handled row {ref, session, telegram}, and the rows `tellnow|...,handled|...`.
  - Press again: no second edit, and still one row.
  - Add the Handled row's id to `..Marked`. Update the header. -- AC1's integration pin (Rule 1), on the CI mock only.

**Acceptance Criteria:**
- Given a paired chat with a tell-now message whose Decision is its session's, when the chat presses Got it, then SessionOps writes one Handled row and sends one handled Notification, and TelegramOut edits that message in place once to its text and "Marked as handled at {time}", with the button gone; the command answers Ok 1 `handled`, not 5003 (DW-873).
- Given that notice already handled, when it is pressed again from telegram or web, then nothing changes, no Notification is sent, no second edit happens, and the answer is Ok 1 `already_handled`.
- Given a GotIt whose Ref is not a reference, names no Decision, names another session's Decision, names a Decision that is not tell-now, or has an unknown Channel, when SessionOps carries it out, then no row, no Notification, Ok 0 `not_found`.
- Given an ended session with Handled rows, when `SessionOps.End` runs, then its rows are deleted and other sessions' rows stay; a failed delete makes End answer failed and keeps the resume hash, and a later End completes (DW-695).
- Given a digest composed with WindowStart W, when needs-you is listed, then unhandled tell-now and act Decisions recorded before W are not counted, those at or after W are, handled ones are not, and failed rows and incidents awaiting approval count whatever their age; no `digest.*` text changes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-1: GotIt is a production command through CommandsIn.
- AD-4: the ownership API reads the Decision. A Ref the session cannot see answers like a missing one. End removes the session's records.
- AD-14: the Got it contract: the verb, first press wins, Handled, kind `handled` to each Out, and FindByRef. This story conflicts with its line "Until Story 18.4, SessionOps answers a GotIt with not_built" (see the Auto Run Result).
- AD-27: retention (see Declined DW-695 part).
- AD-28: AllClear stays code-made from `needs.count`. Awaiting approvals and failed rows are never windowed, so nothing that waits for approval can give an all-clear.
- AD-32: producers never render. The handled Notification carries no text.
- AD-33 and AD-29: SessionOps and Data.Handled are Lane B's, and the Digest files and TelegramDigest are Lane A's. Ruling D1 and the project block assign these files to this story, with no ownership change, and the epic context records the split.

**Consumes:**
- `Data.Ownership.Decision`, `Bridge.Approval.IsRef`, `Data.Handled` (`RefIndexExists`, the unique `RefIndex`), `Data.Time.NowUtc`.
- Notify through `SendNotice`, and TelegramOut's `EditHandled`.
- `Digest.Process` `compose.WindowStart`.

**Consumed-by:**
- TelegramIn's Got it press (this story, through CommandsIn).
- Story 18.4: the web chat's and the Simulated phone's Got it controls reuse the command, the marker and the `handled` Notification.
- `Digest.NeedsYou` (`Handled.Marked`).

**Integration AC:** the TelegramDigest `TestGotItEdits` press-to-edit run on the real production with the CI mock (consumer TelegramIn to SessionOps to Notify to TelegramOut; the effect is the edited message).

**Ledger inbox:**
- DW-873: addressed by the matrix rows Press, Press through Telegram and Needs-you window, and by AC1 and AC5.
- DW-695: addressed by the End matrix row and AC4.
- Declined DW-695 (purge-task part): `OcuTalon.Install.Task.Purge` and AD-27's area list are Lane A's and outside this footprint. A demo reset restores the golden copy, and the online demo's sessions end through End, which now deletes the rows. The local-install growth (one small row per press) is recorded in frontmatter `deferred:` for the harvest.

**Extend, don't copy (Rule 2):**
- `Handled.DropSession` mirrors `Data.Upload.DropSession`.
- `EndHandled`/`DropHandled` follow End's step and seam pattern (`EndSettings`/`Forget`, `DropUploads`) as one appended entry.
- `GotItProbe` extends `SessionOpsProbe`; it is not a copy of `SessionOpsDropProbe`, which Epic 19 may touch.
- The notice follows `Unlink`'s Notification and warning pattern.
- TelegramIn's existing GotIt checks are kept, and SessionOps re-checks ownership itself, because 18.4's web origin has no Delivery check.
- The window is a filter in `List`, not a new Ownership query, because `Data/Ownership.cls` is outside the footprint.

**Web and phone:** they need no guard. For kind `handled`, WebChatOut and SimPhoneOut record a bare Delivery row (no text, no event, no message), and `RecentNotices` reads only the card kinds, so the page and the phone show nothing new.

**Decided in-stage:**
1. Outcomes: `handled` and `already_handled` (Ok 1), `not_found` (Ok 0, for every refusal including a bad Channel, so another session's record is indistinguishable from a missing one, AD-4), and `failed` (Ok 0, an unexpected save error).
2. The refusal checks run before the already-handled check, so another session's handled Ref still answers `not_found`.
3. A failed notice send is a warning, and the marker stands, as for Unlink.
4. The Ref is compared exactly after `Ownership.Decision`, because `Decision.Ref` collates without case.
5. The window's lower bound is inclusive. There is no upper bound: a Decision recorded after WindowEnd and before SentAt would otherwise be in no digest's window, since the next window starts at SentAt.
6. `windowStart` "" means no bound (the safe over-count), and eval passes "". `DECISIONMAX` stays: a window holding more than 1,000 Decisions is already beyond any digest's named five.
7. The handled Notification carries CatalogKey "" and Slots "{}": TelegramOut uses its own `HANDLEDKEY`.
8. The new probe class `Test/Core/GotItProbe.cls` and the CommandsIn doc line are this story's footprint extensions. Both are uncontended.

**Needs-you wording:** "One thing needs you" / "{count} things need you" / "And {n} more on the OcuTalon page." claim no time span, so no `digest.*` text changes (no PUBLIC TEXT question).

## Verification

`<laneB>` stands for `env OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=12 stage=implement'`, where `<lock-dir>` is the main checkout's `.worktrees/.coordination/locks`. The tags are `e12s12iw` (warm) and `e12s12i` (fresh). Run one command per call, in the foreground with `timeout: 600000`. Run `<laneB> OCUTALON_RUN_TAG=e12s12iw ci/warm.sh down` and `<laneB> OCUTALON_RUN_TAG=e12s12i ci/iris.sh teardown` at the end, also after a failure. On slot B (`server` `ocutalon-slot-b`, `namespace` `OCUTALON` on every call; check `iris_server_info` first), use `iris_doc_load` only, to compile the changed classes. Nothing destructive runs there.

**Commands:**
- (loop) `iris_doc_load` of each changed class (path glob with the wildcard before the package directory) on slot B -- expected: it compiles with no error.
- (once) `<laneB> OCUTALON_RUN_TAG=e12s12iw ci/warm.sh up` -- expected: ready.
- (loop) `<laneB> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s12iw ci/iris.sh class <C>`, one class per call, for `OcuTalon.Test.Core.GotIt`, `.Core.SettingsCommands`, `.Core.SessionOps`, `.Core.SessionOpsDocuments`, `.Digest.NeedsYou`, `.Digest.Compose`, `.Digest.AllClear`, `.Digest.EvalCase` and `.Channel.TelegramDigest` -- expected: `CLASS <C> passed`.
- (once) `<laneB> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s12iw ci/iris.sh class <C>` for `OcuTalon.Test.Core.SessionOpsProduction`, `.Core.CommandsRouting`, `.Contract.Ac`, `.Msg.Contracts`, `.Install.Production` and `.Channel.TelegramOut` -- expected: passed.
- (once) `bash docker/tests/test-class-rules.sh`, then `test-boundaries.sh`, `test-storage.sh` and `test-ci-config.sh`, one per call -- expected: each passes.
- (once) fresh, one per call: `<laneB> OCUTALON_RUN_TAG=e12s12i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`; then `shard lane-a@Channel`; then `shard lane-a@rest --part k/4` for k = 1 to 4 -- expected: every class passes, and each call ends inside about 8 minutes (use more parts if one does not).
- (once) `git status --short -- src/ocutalon/cls/OcuTalon/Channel src/ocutalon/cls/OcuTalon/Core/Rule src/ocutalon/cls/OcuTalon/Data/Ownership.cls src/ocutalon/cls/OcuTalon/Msg ci .github` -- expected: it prints nothing.

**ci_groups:**
- `Test.Core.GotIt` and `Test.Core.SettingsCommands` run in shard `lane-b` (area Core), group `image` (about 1,740 s; a unit class adds seconds, under 35 minutes).
- `Test.Digest.NeedsYou` runs in `lane-a@rest`, group `shards-2` (about 1,820 s).
- `Test.Channel.TelegramDigest` runs in `lane-a@Channel`, group `shards-4` (about 1,410 s).
- No `ci/units.sh` change.

**Shared surfaces:**
- the needs-you count's rule (`Test.Digest.NeedsYou`, `Compose`, `AllClear` and `TelegramDigest`'s needs-you lines);
- SessionOps' command answers (GotIt is no longer 5003: `Test.Core.SettingsCommands`; `Test.Contract.Ac` and `Test.Msg.Contracts` are shape-only and unchanged; the CommandsIn not_built tests use probes);
- End's cleanup order and failure count (`Test.Core.SessionOps`, `SessionOpsDocuments` and `SessionOpsProduction`);
- the Handled table (`NeedsYou` and `TelegramDigest` fixtures);
- the telegram Delivery rows of a session (`TelegramDigest` `Rows`), and the web and phone Delivery rows of kind `handled`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; apply, see red, revert, and confirm that `git status --short`/`git diff --stat` are unchanged):**
- mutation: AC1 the Handled save removed from the GotIt branch -> `GotIt` `TestPressMarksHandled` and `TelegramDigest` `TestGotItEdits` go red (no edit: no marker).
- mutation: AC2 the `RefIndexExists` checks removed (a failed save answered `failed`) -> `TestSecondPressNoOp` goes red.
- mutation: AC3 the Decision read through `Bridge.Data.Decision.RefIndexOpen` instead of `Ownership.Decision` -> `TestOtherSessionRefused` goes red. The Outcome check removed -> `TestNotTellNowRefused` goes red.
- mutation: AC4 `+ ..EndHandled(sessionRef)` dropped from the sum -> `TestEndDeletesHandled` and `TestEndHandledFailureCounts` go red.
- mutation: AC5 `List` ignores windowStart -> `TestWindow` goes red. `Finish` passes "" -> `TestProcessWindow` goes red. Incidents filtered by the window -> `TestWindow`'s incident assertion goes red.
- mutation: the stub line restored -> `SettingsCommands` `TestGotItBuilt` goes red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: AD-14's Rule contradicts the story's ACs. AD-14 (spine :478) says "**Got it** (Story 18.4; Story 33.2 creates the names) ... Until Story 18.4, `SessionOps` answers a `GotIt` with `not_built`", and the Structural Seed row (spine :1346) names "Story 18.4 (writer)" for `Data.Handled`. Story 12.12's ACs (ruling D1 (a)) have SessionOps carry out GotIt now and write Handled's first rows. An AD amendment is not the plan stage's to make (Rule 6, U7). Recommended amendment (light path, marker `[AMENDED 2026-11-07, Story 12.12, ruling D1]`): at :478, read "**Got it** (Story 12.12 for Telegram's press; Story 18.4 for the web chat and the Simulated phone; Story 33.2 creates the names)" and replace "Until Story 18.4, `SessionOps` answers a `GotIt` with `not_built`." with "From Story 12.12, `SessionOps` carries out a `GotIt`: it refuses (Ok 0, nothing changed) a Ref that is not the session's own tell-now Decision, writes one `Handled` row (the first press wins through its unique `Ref`) and sends one `handled` Notification, and `SessionOps.End` deletes the session's `Handled` rows; Story 18.4 adds the web chat's and the Simulated phone's controls and their handled copies." At :1346, read "Story 12.12 (writer; Story 18.4 the web and phone controls)". The spec is otherwise complete and self-checked against the READY-FOR-DEVELOPMENT standard: once the amendment lands, set `status: ready-for-dev` with no re-plan. Note for the same commit: the cross-lane edits (AD-33: Lane B's SessionOps and Data.Handled, and Lane A's Digest files) are as the ruling and the epic context assign them, with no ownership change.
