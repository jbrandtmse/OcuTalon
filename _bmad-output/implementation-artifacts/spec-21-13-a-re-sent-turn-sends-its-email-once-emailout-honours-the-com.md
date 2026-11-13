---
title: "Story 21.13: A re-sent turn sends its email once (EmailOut honours the command's idempotency key)"
type: 'bugfix'
created: '2026-11-12'
status: 'done'
baseline_revision: '4671201c71dbdaa6854536c8dfccddac404d0a17'
baseline_commit: '4671201c71dbdaa6854536c8dfccddac404d0a17'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-6-send-email-over-smtp.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `EmailOut` de-duplicates only the system path (by `ApprovalRef`, 21.6 ruling (f)) and the digest path (by `DigestKey`). A `SendEmail` of origin `tool` carries an `IdempotencyKey` (AD-1: the turn's `ItemId` plus the command's position), but `EmailOut` ignores it, so a re-sent chat turn, a replay or a retry after a restart sends the own-address email again (DW-1244, ledger DW-1253). Story 22.7's `send_email` tool cannot merge until this is fixed.

**Approach:** Claim a keyed tool send the way the system path claims an approval, and reuse that code. Under a lock, a `Data.Delivery` row of channel `email` for the session holds a 22-character hash of the key in the existing `DigestKey` column. The same key again sends nothing and answers exactly as the first send did. A send that fails removes its claim, so it can be tried again.

## Boundaries & Constraints

**Always:**
- The repeat rule applies to origin `tool` with a non-empty `IdempotencyKey`, after the online-demo check, `Check` and `Authorised`. It is scoped to the command's `SessionRef` (the row's `OwnerRef`), like `ReminderOps.SetReminder`'s key, and only the key decides: the subject, the text and the recipients of a repeat are not compared, because a re-sent turn may word them differently.
- A sent claim for the key answers `Result(1, "sent", MESSAGESENT)`, the first send's answer, and sends nothing.
- A claim that is still pending (its send never finished) or marked failed (an error was thrown after the claim) answers `failed` with `MESSAGEFAILED` and sends nothing.
- A lock that cannot be taken in `CLAIMWAIT` answers `failed` with `MESSAGEFAILED`, writes no claim and sends nothing.
- The claim row is written pending before the send, cleared once the mail is sent, and deleted after a failed send (one of `Sender.Classify`'s classes; that failure answer is unchanged). So no failed tool send leaves a row, as today. It keeps no text and no address.
- A keyed tool claim never carries an `ApprovalRef`, even when the command does, so a tool command cannot reach an approval's claim.
- The key's hash comes from `DigestKeyOf`'s hashing (factored into one helper), with the input `"tool"`, a line feed and the key, so it never equals a digest's key.
- The online demo still answers `not_available` before anything else and writes nothing.

**Never:**
- No new stored column, index, table or global. The lock `^OcuTalon.EmailOut.Key(owner, key)` is a lock name only and is never set.
- No change to `CommandsIn`, `CommandCall` or any 22.7 file, and no change to the system path's or the digest path's behaviour.
- No new public text and no new log line holding a key, an address, a subject or a text.
- No copy of the approval claim block: generalise it.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Repeat | Tool send with key K, which was already sent | Nothing is delivered. The answer is `1\|sent\|The email was sent.` There is still one Delivery row. | none |
| After restart | The same K to a new instance of the operation (a restarted `EmailOut`) | As Repeat (the claim is a table row) | none |
| Other key | Key K2 | Sent: one more mail and one more row | none |
| No key | Tool send with `IdempotencyKey` "" | Sent every time, as today (repeat detection off) | none |
| Failed, then retried | K: the send fails (unreachable, refused or rejected), then K again with the server OK | The first answer is `failed` with its class's sentence and leaves no row. The retry is sent once. | the existing classes |
| Never finished | A pending claim row for the owner and K's hash | `0\|failed\|MESSAGEFAILED`, nothing delivered | none |
| Error after the claim | `Deliver` throws for K, then K again | Both answer `failed`. The claim says `failed`, and the repeat delivers nothing. | the existing catch |
| Lock held | Another process holds K's lock | `0\|failed\|MESSAGEFAILED`, nothing delivered, no claim. Once the lock is free, K is sent once. | none |
| Tool command with an ApprovalRef | Tool, key K, `ApprovalRef` of an executing email fix | Keyed path: the claim has an empty `ApprovalRef`, and that approval's own system send is still sent once | none |
| System path | System send with an `ApprovalRef`, with or without a key | Unchanged (21.6 ruling (f): `already_sent` and the rest) | unchanged |
| Online demo | The flag is on, any key | `not_available`, no row | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls` -- the change:
  - `Handle` L139-174: L148 sends every non-system command unclaimed. L149-173 is the approval claim block (lock L150, `Claimed` L155, the pending claim through `Delivery.Record` L161, the catch marking the claim `failed` L164-171).
  - `Send` L178-202: L183-189 clears or records the row, and L195-199 marks a failed claim (keep that for an approval claim; delete a keyed tool claim).
  - `Claimed` L399-408: an SQL lookup on `ApprovalRef`. Extend it with an owner-and-key lookup (`OwnerRef`, `Channel`, `DigestKey`) and compare the value read again exactly, as `Delivery.DigestEmailSent` L146-156 does, because a `%String` column compares without regard to case.
  - `DigestKeyOf` L301-306: the hash to factor.
  - Class description: the tool and claim bullets, L7-30.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls` -- doc comments only: the class description L8-10 and `DigestKey` L51-53 (it now also holds a keyed tool send's hash), and `FallbackReason` L44-46 (the pending and failed marks also apply to a keyed tool claim). `Record` L65 already takes `digestKey`. Storage, properties and indexes stay as they are; `Test.Data.Tables` L453 pins the column.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SendEmail.cls` L1 -- doc only: a tool send goes out once per `IdempotencyKey` of its session.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` L22-27, L102-105 (read only) -- the pattern this extends: the key is session-scoped, a repeat gets the first result, and an empty key turns detection off.
- `src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls` L36-44 (read only) -- `Run` sets `IdempotencyKey = ItemId:position`, numbering from 1 on every run of a call, so a re-sent turn repeats its keys.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailOut.cls` -- the probe tests:
  - helpers `Command`/`Send` L1088-1110 take no key; extend them;
  - `TestNoDoubleSend` L770 and `TestClaimIsLocked`/`HoldLock` L817-855 are the patterns to follow;
  - `Reset` L1196 deletes the `zzemailout%` rows.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailLive.cls` -- the live tests against the CI SMTP stub (`shard:lane-a@Channel`):
  - `ToolSend` L322-345 sets its own unique key; `Restart` L974; `Mails` L380; `Deliveries`;
  - `Disconnect` L497 deletes the owner's rows, and `..Session("owner")` is a fresh session per test, so a fixed ItemId is safe.
- Read only, by Story 22.7 (`.worktrees/epic-22/.../spec-22-7-*.md`): its safe send goes through `CommandCall.Run` with origin `tool` and the key `ItemId:n`, and expects `{ok:1, outcome:"sent", message:"The email was sent."}`. `Out.cls` and the tests above are read only to it, and `OCT-epic22` has not changed them. So there is no contention.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls`:
  - Turn the approval claim block of `Handle` into one private method that both claim kinds use (the lock name and the lookup are its parameters).
  - Route origin `tool` with a non-empty key to it: the key is `ToolKeyOf(request)`, the owner the `SessionRef`, the claim `Record(owner, CHANNEL, NewRef(), "", "", "", "", "", CLAIMPENDING, .claim, "", key)`, and a sent claim answers `Result(1, "sent", MESSAGESENT)`.
  - Extend `Claimed` with the key lookup. In `Send`, delete a claim with an empty `ApprovalRef` after a failed send.
  - Add `ToolKeyOf`, sharing `DigestKeyOf`'s hash helper.
  - Update the class description.
  - This pays DW-1244 and DW-1253 with no new store.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls` and `src/ocutalon/cls/OcuTalon/Msg/Command/SendEmail.cls` -- the doc comments of the Code Map, no code. They keep the contracts true (Rule 14).
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailOut.cls`:
  - Give `Command` and `Send` an optional `key` argument (default "").
  - Add `TestToolKeySendsOnce`: the matrix rows Repeat, After restart (a new shadow instance), Other key, No key, Failed then retried, Never finished (a seeded pending row with `ToolKeyOf`'s hash), Error after the claim, and Tool command with an ApprovalRef. Assert the probe's `claim` mark: pending during the send and cleared after.
  - Give `HoldLock` an optional key lock and add the Lock held row, in `TestClaimIsLocked` or beside it.
  - Add the header bullets.
  - These are the unit pins of every matrix row.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailLive.cls`:
  - Give `ToolSend` an optional `itemId`. When it is set, the context's request gets that `ItemId` and the command goes through `OcuTalon.Tools.CommandCall.Run` (the real key `ItemId:1`) instead of a key set by hand.
  - Add `TestReSentTurnSendsOnce`, with its header bullet. It is the surface pin of the story.

**Acceptance Criteria:**
- **The surface pin (Rule 19).** `TestReSentTurnSendsOnce`:
  - Given the owner's mailbox and SMTP server connected to the CI stub (`Connect`), when the owner's chat turn with ItemId X sends `zzlive@example.com` its email through `CommandCall.Run`, the same turn is sent again with ItemId X, and once more after `EmailOut` restarts (`Restart(SENDITEM)`), then all three answers are `1|sent|The email was sent.`, the stub holds exactly one mail, and the owner has one Delivery row.
  - A turn with ItemId Y then adds exactly one mail.
  - Mutation: the key lookup removed (`Claimed` never finds a key) turns `TestReSentTurnSendsOnce` and `TestToolKeySendsOnce` red.
- **The system path is unchanged.** Given 21.6's approval-keyed tests, when they run unchanged, then they pass: `Test.Channel.EmailOut` `TestNoDoubleSend`, `TestClaimIsLocked`, `TestSystemApproval`, `TestMessageShape`, `TestFailureClasses` and `TestSignInMessage`, and `Test.Channel.EmailLive` `TestSystemSendIsClaimedByItsApproval`, `TestToolSendReachesTheStub` and `TestSendFailuresByStubMode`.
- **No stored-data change.** Given the change, when `Test.Data.Tables` runs, then it passes unchanged, and `git diff` shows no `Storage`, `Property` or `Index` line changed in any class.

- [x] [Review] Planner ruling K (PUBLIC TEXT, `prompts/gate-rulings-20261112-1810.md` K): the "may have sent" case (`Sender.MayHaveSent`: an SMTP timeout, or a connection lost during DATA) must NOT say the email wasn't sent. For that case only, the answer text is exactly: "The mail server stopped answering while the email was being sent, so it may have gone out. OcuTalon won't send it again." A repeat with the same key gives the same sentence. Certainly-not-received failures keep their existing texts (`MESSAGEFAILED` and the 21.6 Q2-Q4 texts) and free the key. Author the sentence once as a new message parameter beside the existing ones (Rule 14: ASCII, escapes if needed), route it through the same answer path, and pin: the timeout case, the dropped-during-DATA case, a repeat of each (same sentence, nothing sent), and a certainly-not-received failure (old text, key freed, retry sent); `mutation:` lines. Add the sentence to the ux-strings/catalog registry the project keeps for public text, if `EmailOut`'s other answers are listed there. -- DONE: new `MESSAGEMAYHAVESENT` (the approved sentence, verbatim) answers a keyed tool send's may-have-sent failure and its repeat; the claim is marked `maysent` (`CLAIMMAYSENT`, `Claimed` answers `CLAIMMAYHAVESENT`); certainly-not failures keep their texts and free the key; pinned in `TestToolKeyFailureClasses` and `TestTexts`; the sentence is registered in EXPERIENCE.md's accepted-text table (no list in web/scripts holds EmailOut's answers).

### Review Findings

Code review 2026-11-12 (full, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). Verdicts: high 1, medium 1, low 8, false 1 (11 entries). Patched 4; closed terminal 4 (ledger DW-1257..DW-1260); rejected 3. Unresolved high/medium: 0.

- [x] [Review][Patch] HIGH (Rule 6, AD-1): a keyed tool send whose failure may still have reached the server deleted its claim, so a re-sent turn could send the email twice [Out.cls `Send`; Sender.cls `MayHaveSent`] -- blind+edge+auditor. `Sender.Classify` puts a timeout waiting for the answer to the end of the message (`DATATIMEOUT`) and a connection lost during DATA in class unreachable, and `Send` deleted every failed keyed claim, against AD-1's "its owner ignores a repeat, so a re-sent turn can't act twice". Fix: new `Sender.MayHaveSent(sc)` (1 for `SMTPTimeout`, which names no phase so any, and for `SMTPConnectionFailed` during `DATA`); `Send` deletes a keyed claim only when it is 0 and otherwise keeps it marked failed, so a repeat answers `failed` and sends nothing, as an approval's claim does. A failure the server did not take (connect refused, closed before the greeting, login refused, any server error answer) still deletes the claim and the key can be sent again, so the matrix row "Failed, then retried" holds for every one of those and `EmailLive.TestSendFailuresByStubMode` passes unchanged (AC2). Docs made true: `Out` class description and `Send`, `Delivery.FallbackReason`, the spine's AD-14 sentence. Pins: `TestToolKeyFailureClasses` gains probe answers `timeout`, `dropped` (kept, repeat failed) and `lost` (deleted, retry sent). **For the lead:** the code is now narrower than the Always bullet "deleted after a failed send (one of `Sender.Classify`'s classes)" and the Approach's "A send that fails removes its claim" (AD-1 governs; product default 4); record a Spec Change Log line and the spine memlog for the edited AD-14 sentence (lint: the 10 baseline low placeholders only).
- [x] [Review][Patch] MEDIUM (Rule 19 hermeticity): the probe's "pending during the send" mark read the newest channel-email row of the whole instance, so another writer's row could pass or fail `TestToolKeySendsOnce` and `TestNoDoubleSend` [EmailOutProbe.cls `Deliver`] -- verification-gap. Fix: the probe reads the row whose `ChannelMessageId` is exactly the mail's `X-OcuTalon-Ref` (the send's own claim).
- [x] [Review][Patch] LOW: the `SendEmail` doc ("the same key again sends nothing and answers sent") and the spine sentence did not say what a repeat of a failed key does [SendEmail.cls L1; ARCHITECTURE-SPINE.md AD-14] -- blind+edge. Corrected with the HIGH fix.
- [x] [Review][Patch] LOW: `KeyRowId` read `ID` after `%Next()` had returned 0 when no row matched exactly [Test/Channel/EmailOut.cls `KeyRowId`] -- blind+edge. Now answers the matched id or "".
- [x] [Review][Closed by-design DW-1257] Residual risk 2: a pending claim (job stopped during a send) or a claim marked failed (error after the claim, or now a send that may have reached the server) answers `failed` for that key for good. The matrix rows "Never finished" and "Error after the claim" require it; it is at-most-once, as AD-1 asks; a new turn has a new `ItemId`, so only that turn's own re-send is blocked; `Data.Purge` retention frees the row.
- [x] [Review][Closed by-design DW-1258] The key is `ItemId:position` and only the key decides, so a re-run that reorders or rewords its commands is not compared (blind, edge) -- AD-1 as amended (U-215) defines the key and Design Notes decided 2 keeps no text to compare.
- [x] [Review][Closed wontfix-theoretical DW-1259] An exception after `Send` deleted a keyed claim would re-save it as failed (edge) -- only a log macro and `Result()` run after the delete.
- [x] [Review][Closed wontfix-theoretical DW-1260] A `%DeleteId` error leaves the keyed claim pending, so the key answers failed (edge) -- a one-row delete by its own id under the lock; the outcome is fail-safe.

Rejected:
- `false` (blind): "the restart step of `TestToolKeySendsOnce` restarts nothing" -- every `Send` makes a new shadow instance of the operation, which is what the matrix row "After restart" names; the real `Restart` is pinned live by `TestReSentTurnSendsOnce`.
- `low` (blind, auditor): `EmailLive.ToolSend` without an `itemId` still sets a key, so no live test sends a keyless tool email -- real tool commands always carry a key (`CommandCall.Run`), so the live tests now exercise the real path; the keyless path keeps its unit pins (`TestToolKeySendsOnce` "no key" and the 21.6 tests).
- `low` (edge): `%OpenId(KeyRowId(...))` on a miss stops with `<INVALID OREF>` instead of an assertion message -- the test still goes red; diagnostics only.

Rule 3: the real-runtime pin is `EmailLive:TestReSentTurnSendsOnce` (real CommandsIn, CommandCall.Run, EmailOut job and the CI SMTP stub, with a `Restart`); it passed in the whole `EmailLive` class after the patches on a stack brought down and up.

## Spec Change Log

- 2026-11-13 (implement, ruling K): outcome code kept (Ok 0, "failed") for the may-have-sent answer, now with MESSAGEMAYHAVESENT; the sentence applies to keyed tool claims only (an approval's send and an unkeyed tool send keep their class texts, AC2), and the repeat is told apart by the claim mark `maysent` in the existing `FallbackReason` column (no new column).

- 2026-11-13 (lead, rework iteration 1, trigger review-ruling): Planner ruling K: the HIGH fix and U-327's narrowed wording are kept; the may-have-sent case gets its own approved sentence (the [Review] item).

- 2026-11-13 (lead, after code review): the claim is deleted after a failed send only when the server certainly did not take the mail; a send that may have reached it (`Sender.MayHaveSent`: an SMTP timeout, or a connection lost during DATA) keeps the claim marked failed, so a repeat answers `failed` and sends nothing (review HIGH, AD-1's repeat rule). This narrows V1's (U-327) 'deleted after a failed send'; reported to the orchestrator.

- 2026-11-13 (lead, spec gate): V1 ruled KEEP (U-327, Design Notes).

## Review Triage Log

### 2026-11-12 -- Review pass
- verdicts: 21 findings -- high 0, medium 1, low 16, false 4, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the spine edit is dated 2026-11-13 -- the stage prompt and the spec's S-item fix that marker, `[ADDED 2026-11-13, Story 21.13, DW-1244]`.
  - `[low]` `[reject]` Blind: the spine sentence omits the key-only rule, the session scope and the error-after-claim mark, and sits on the 21.6 bullet -- the sentence is the spec's own wording (spec-bound; a fix edits the spec's S-item); the class description, `Delivery` and `SendEmail` doc comments carry the detail.
  - `[low]` `[reject]` Blind: a repeat with other words answers `sent` -- Design Notes decided 2 and the intent ("only the key decides"; "answers exactly as the first send did"); by design.
  - `[low]` `[reject]` Blind and Edge: a pending claim, an error after the claim, or a failed `%DeleteId` blocks the key with `failed` for good -- the matrix rows "Never finished" and "Error after the claim" require it, so that a job stopped during a send fails safe; a `%DeleteId` failure is theoretical (a one-row delete by its own id).
  - `[low]` `[reject]` Blind: `Send` chooses delete or mark by `claim.ApprovalRef = ""` -- the spec's Code Map says so; the AC2 mutation below turns the system tests red when it is inverted.
  - `[low]` `[reject]` Blind: keyed claim rows accumulate, `DigestKey` has no index -- ruled V1 (U-327): no new index, existing retention; the lookup uses the `OwnerRef`/`Channel` index.
  - `[low]` `[reject]` Blind: weak test assertions (`'[ "zzkey"`, no `ToolKeyOf` vs `DigestKeyOf` test, no `%DeleteId` failure test, no concurrency test, no failed-then-retried live test) -- each is covered by a stronger row (length, hash equality through `KeyRows`, the lock test, the unit retry rows) or is theoretical; one exception is patched as P1 below.
  - `[low]` `[reject]` Edge: a failure after the server accepted the mail (timeout after DATA, class unreachable) deletes the claim, so a re-sent turn can send twice -- the intent says every `Sender.Classify` class deletes the claim ("so no failed tool send leaves a row", "that failure answer is unchanged"); a rare residual risk of the intent, listed under residual risks.
  - `[low]` `[reject]` Edge: sent claim not cleared / not deleted on a save or delete error -- as the pending-claim row above: theoretical.
  - `[low]` `[reject]` Edge: a repeat after the mailbox is disconnected or the address changed answers `not_connected` / `refused` -- the intent puts the repeat rule after the online-demo check, `Check` and `Authorised`; by design.
  - `[false]` `[reject]` Edge: two rows with one owner and key make the answer depend on row order -- a failed or pending claim is never deleted and a sent claim is written once, under the lock, after `Claimed` found none, so two rows of one key cannot arise.
  - `[false]` `[reject]` Edge: a tool command with an empty `SessionRef` shares one instance-wide scope -- `Authorised` refuses a tool command with an empty `SessionRef` (`Out.cls` L395) and `TestToolRecipients` pins it.
  - `[low]` `[reject]` Edge: an exception after `Send` deleted the claim could re-save it as failed -- nothing between the delete and the return of `Send` throws (a log call); theoretical.
  - `[medium]` `[patch]` Verification gap: no `EmailOut` unit test sends a keyed tool command that `Authorised` or `Check` refuses, nor one on the online demo, so moving the keyed branch above those checks stays green -- patched (P2): keyed refused rows in `TestToolRecipients` (another address, no subject; nothing delivered or claimed) and a key on the `TestOnlineDemo` sends (no claim written); the mutation "keyed sends skip `Authorised`" turns `TestToolRecipients` red.
  - `[low]` `[reject]` Verification gap: the exact-case recheck in `Claimed` is unpinned -- a case-only collision of two 22-character hashes is negligible, and a seeded upper-cased hash may equal the original.
  - `[low]` `[patch]` Verification gap and Blind: the seeding of another session's claim ignores the `Record` status, so the scoping row could pass with no row -- patched (P1): the status is asserted and the rows of both sessions are counted before the send.
  - `[low]` `[patch]` Verification gap: AC2 and AC3 have no `mutation:` line -- Rule 19 closes it inside the pass: both lines are written below, the AC2 mutation applied and observed red, reverted byte-identical.
  - `[low]` `[reject]` Verification gap: the "restart" row of `TestToolKeySendsOnce` is not distinct from the repeat row -- the real restart is pinned by `TestReSentTurnSendsOnce` (`Restart`); not a vacuous assertion.
  - `[false]` `[reject]` Verification gap: self-containment -- the layer found none; no finding.
  - `[low]` `[reject]` Verification gap: the tests compute the expected `DigestKey` with the product's `ToolKeyOf` (circular) -- the hash helper is shared with the digest path, whose own test pins it; a changed hash only changes the stored value of a keyed claim, never the answer.
  - `[low]` `[reject]` Intent alignment (descriptive): the diff implements reading A (the handler) and pins B and C live; position, a real chat re-submit and the 22.7 tool are not exercised -- reading D waits for Story 22.7, and position is `CommandCall`'s (not changed here).

### 2026-11-13 -- Review pass (rework 1, ruling K)
- verdicts: 15 findings -- high 0, medium 1, low 10, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the spec's `## Public text` still says "None new" -- the fix edits the spec; the Spec Change Log line and the `EXPERIENCE.md` row carry the new text.
  - `[low]` `[reject]` Blind: the spec's Always bullets, matrix and residual risks describe the pre-ruling behaviour -- the fix edits the spec (oversized; the Spec Change Log records the ruling).
  - `[false]` `[reject]` Blind: the class header still says a pending or failed claim answers `MESSAGEFAILED` -- the same bullet names the `maysent` mark and `MESSAGEMAYHAVESENT` two lines later.
  - `[medium]` `[patch]` Blind and Verification gap: nothing pins that an approval's or an unkeyed tool send that may have reached the server keeps its class sentence and `failed` mark (AC2) -- patched: `TestNoDoubleSend` gains the timeout and dropped approvals (sentence, mark, repeat), `TestFailureClasses` gains the timeout and dropped unkeyed rows; two `mutation:` lines, both observed red and reverted byte-identical.
  - `[low]` `[reject]` Blind and Edge: an exception after `Send` saved `maysent` would be overwritten as `failed` in the catch -- only a log macro and `Result()` run after the save; theoretical (as DW-1259).
  - `[low]` `[reject]` Blind: the outcome stays `failed` (Ok 0) while the text says it may have gone out -- by design: the stage prompt keeps the review's outcome code, and `CommandCall`/22.7 are out of scope.
  - `[low]` `[reject]` Edge: a failed save of the `maysent` mark leaves the claim pending, so a repeat answers `MESSAGEFAILED` -- fail-safe (nothing is sent twice); a one-row save by its own id under the lock (as DW-1260).
  - `[low]` `[reject]` Edge: an approval's or an unkeyed send that may have gone out keeps its class sentence -- by design (AC2, the system path is unchanged; an unkeyed send is sent again, so "won't send it again" would be false); now pinned.
  - `[low]` `[reject]` Edge: `Delivery`'s lookup by Ref skips a `maysent` row, so a reply to that mail cannot be matched -- pending and failed rows are skipped the same way; no product path matches a reply to a tool email.
  - `[false]` `[reject]` Edge: `Claimed` could answer the keyed sentence for an approval row marked `maysent` -- nothing writes that mark on an approval's claim (pinned by the new `TestNoDoubleSend` rows).
  - `[low]` `[reject]` Edge: the Boundaries bullet says a failed claim answers `MESSAGEFAILED` -- the fix edits the spec; the Spec Change Log records the ruling.
  - `[low]` `[patch]` Verification gap: the header of `TestToolKeyFailureClasses` still said "marked failed" and "answers failed" -- patched to say maysent and the same sentence.
  - `[false]` `[reject]` Verification gap: the `zzkey-class-timeout` and `zzkey-class-dropped` rows may outlive the test -- `OnBeforeOneTest` and `OnAfterAllTests` call `Reset`, which deletes the email rows of every `zzemailout*` owner.
  - `[low]` `[reject]` Verification gap: the four ruling K mutations all target the keyed path -- covered by the new approval and unkeyed mutations above.
  - `[low]` `[reject]` Intent alignment (descriptive): the ruling widens the contract's "no new public text" and "no failed tool send leaves a row" for the may-have-sent case -- ruled by the Contest Planner (K); `EmailOut` and `Delivery` are the only surfaces changed, the live `CommandsIn` pass-through of `Message` is unchanged.

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: the owner ignores a repeat key, so a re-sent turn can't act twice. This story makes `EmailOut` comply, and AD-1 needs no amendment.
- AD-8: a re-sent turn.
- AD-14: the `EmailOut` and `Delivery` rows.
- AD-19 and AD-25: no secret; the demo refuses first.
- AD-33: `EmailOut` alone writes its email rows.

No AC contradicts an AD.

**Spine S-item (additive, for the lead; Rule 20):** append this to the `EmailOut` sub-bullet of AD-14: "A tool send with an `IdempotencyKey` is claimed like an approval, by its session and a 22-character hash of the key in the row's `DigestKey`. The same key again answers `sent` and sends nothing. A failed send removes its claim, and a send that never finished answers `failed` (Story 21.13)."

**Rule 1/2:** no new service, module or consumer. This story extends existing code:
- `Out.Handle`'s approval claim block and `Out.Claimed` are generalised, not copied;
- `DigestKeyOf`'s hash;
- the existing `Delivery.DigestKey` column;
- `ReminderOps.SetReminder`'s keyed-repeat rule;
- `EmailLive.ToolSend`.

Consumes: 21.6, 21.7 and `CommandCall.Run`. Consumed-by: 22.7, whose `send_email` repeat answers the same `{ok, outcome, message}`.

**Ledger (Rule 17):** DW-1253 (inbox) is addressed by the whole story: Approach, the matrix and both pins. DW-1244 is on OCT-epic22's ledger; the orchestrator reconciles it after the merge. Continuity: 21.12 (done; a README check) shares no code.

**Decided in-stage:**
1. The repeat answers `sent`, not `already_sent`. The AC says "answers as for the first send", and 22.7's tool result stays the same.
2. Only the key decides. A re-sent turn's model may word the email differently, and the rows keep no text, so there is no `reused_key` refusal (it would also need new text).
3. The check runs after `Check` and `Authorised`, so a repeat is answered `sent` only when it would itself be allowed.
4. Claim first, with the system path's code, so that a job stopped during the send fails safe on a replay. A failed tool send deletes its claim instead of keeping it, because nothing was sent and a re-sent turn should be able to send.
5. A key is hashed into the existing 22-character column. Rejected alternatives:
   - a new `CommandKey` column (a stored-data change, and bigger);
   - looking for an earlier `SendEmail` message body by key (no index, and lost at purge, AD-27);
   - a global.
6. The lock comes with the shared block. EmailOut's pool is 1, so it matters only for a shadow instance beside the job.
7. No Task 0: nothing needs measuring.

**Ruling V1 (orchestrator, 2026-11-13, category veto, inbox U-327; the Planner may reverse):** KEEP the reuse of the existing nullable `Data.Delivery.DigestKey` for the 'tool'-prefixed 22-character `IdempotencyKey` hash, a pending claim written before the send and deleted after a failed send; no new column, index, table or global; nothing written on the online demo.

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | Stored data: the existing `Data.Delivery.DigestKey` column (nullable, `MAXLEN` 22, added by 21.7 V8) also holds the 22-character hash of a keyed tool send's `IdempotencyKey`. The claim row is written pending before the send, like the system path's, and deleted after a failed send. No new column, index, table or global; no migration; existing retention; no text or address. | approve | nothing written |

## Public text

None new. Reused: `MESSAGESENT` (the repeat) and `MESSAGEFAILED` (a send that never finished, an error after the claim, a held lock).

## Verification

Run every command from the worktree root.

`<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=implement'`. The warm tag is `e21s13iw` and the fresh tag `e21s13i`.

Run one command per foreground call (`timeout: 600000`), each about 150 s at most. Never put two test runs in one message. Put one `iris_execute_tests` per message, with `server` and `namespace` on every MCP call (Rule 21). Use lane C throwaways only, never a slot or another instance.

**Shared surfaces:**
- the `Data.Delivery` rows of channel `email` (counted by `Test.Channel.EmailOut`, `EmailLive`, `EmailIn` and `Test.Data.Delivery`);
- `Channel.Email.Out`'s class description.

No catalog, route, table shape or count changes. Every test added or changed passes on a fresh environment, in either order: each creates and removes its own sessions, rows, keys and probe state.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s13iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s13iw ci/iris.sh class OcuTalon.Test.Channel.EmailOut` (loop) -- pass. Mutations, each observed red and reverted byte-identical:
  - the key lookup removed -> `TestToolKeySendsOnce`;
  - a failed tool claim kept instead of deleted -> `TestToolKeySendsOnce` (the retry);
  - the key lock not taken -> the Lock held row.
- `... class OcuTalon.Test.Channel.EmailLive:TestReSentTurnSendsOnce` (loop) -- pass. Mutation: the key lookup removed -> red (the stub holds more than one mail).
- `... class OcuTalon.Test.Channel.EmailLive` (once; the whole class is about 65-105 s) -- pass.
- `... class` `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Channel.EmailIn` and `OcuTalon.Test.Core.CommandsStep4` (once each, one per call) -- pass (shared surfaces).
- `<vars> OCUTALON_RUN_TAG=e21s13iw ci/warm.sh down` (once, also after a failure).
- Fresh check (once each, fresh stack, no `OCUTALON_WARM`):
  - `<vars> OCUTALON_RUN_TAG=e21s13i ci/iris.sh class OcuTalon.Test.Channel.EmailOut:TestToolKeySendsOnce`, then `... class OcuTalon.Test.Channel.EmailLive:TestReSentTurnSendsOnce` -- pass;
  - then `<vars> OCUTALON_RUN_TAG=e21s13i ci/iris.sh teardown`.
  - The lead's Rule 19 pre-push shard check covers the order.
- `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` (once each) -- pass.
- `git diff -U0 -- src | grep -E '^[+-]\s*(Property|Index|<Value>|<Data|Storage)'` (once) -- no output.

**Mutation record (implement stage, lane-C throwaways):**
- mutation: the key lookup removed (`SendClaimed` never calls `Claimed` for a keyed tool send) -> `Test.Channel.EmailOut:TestToolKeySendsOnce` red (repeat, restart, other key, scoped, never finished and error-after-claim rows); reverted byte-identical
- mutation: a failed tool claim kept and marked failed instead of deleted -> `Test.Channel.EmailOut:TestToolKeySendsOnce` red (the failed-then-retried rows); reverted byte-identical
- mutation: the key lock not taken -> `Test.Channel.EmailOut:TestToolKeyIsLocked` red (the Lock held row); reverted byte-identical
- mutation: the `If claim.ApprovalRef = ""` test of `Send` inverted (an approval's failed claim is deleted, a keyed tool claim is marked failed; AC2, the system path unchanged) -> `Test.Channel.EmailOut:TestNoDoubleSend` red (and `TestSignInMessage`, `TestToolKeySendsOnce`); reverted byte-identical, green again on the same stack
- mutation: a `Property` line added to `Data.Delivery` (AC3, no stored-data change) -> the Verification command `git diff -U0 -- src | grep -E '^[+-]\s*(Property|Index|<Value>|<Data|Storage)'` prints it; reverted byte-identical
- mutation: keyed tool sends skip `Authorised` (AC1's order: the repeat rule after `Check` and `Authorised`) -> `Test.Channel.EmailOut:TestToolRecipients` red (the keyed refused rows); reverted byte-identical
- mutation (ruling K): the answer of a may-have-sent failure keeps its class's message (the `errorMessage` assignment removed) -> `Test.Channel.EmailOut:TestToolKeyFailureClasses` red (timeout and dropped first answers); reverted byte-identical
- mutation (ruling K): the may-have-sent claim marked failed instead of maysent -> `TestToolKeyFailureClasses` red (mark and repeat rows of timeout and dropped); reverted byte-identical
- mutation (ruling K): `Claimed` does not read the maysent mark -> `TestToolKeyFailureClasses` red (the repeat of timeout and dropped answers the old sentence); reverted byte-identical
- mutation (ruling K): every failed keyed send gets the may-have-sent sentence -> `TestToolKeyFailureClasses` and `TestToolKeySendsOnce` red (unreachable, lost, refused, rejected keep their texts); reverted byte-identical
- mutation (ruling K review): the may-have-sent mark and sentence also applied to an approval's claim (a `MayHaveSent` test before the `ApprovalRef = ""` branch of `Send`) -> `Test.Channel.EmailOut:TestNoDoubleSend` red (timeout and dropped approvals: class sentence, `failed` mark, repeat answer); reverted byte-identical
- mutation (ruling K review): the may-have-sent sentence also applied to an unkeyed tool send (a `MayHaveSent` test before the claim branch of `Send`) -> `TestFailureClasses` and `TestNoDoubleSend` red (timeout and dropped rows); reverted byte-identical
- mutation: the key lookup removed (warm stack down and up, as the production job runs the code) -> `Test.Channel.EmailLive:TestReSentTurnSendsOnce` red (the stub held more than one mail); reverted byte-identical

**QA stage (gap tests, lane-C throwaways, tag e21s13qw; `(QA)` marks the files and lines this stage added):**
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailOut.cls` (QA): new `TestToolKeyFailureClasses`, `TestToolKeyClaimHoldsNothingOfTheSend`, `TestToolKeyClaimIsCaseExact`, `TestSystemSendWithAKeyIsStillClaimedByItsApproval`, `TestToolKeyNeverEqualsADigestKey`; `TestNoPersonalDataInTheLog` now sends keyed commands (twice each) and checks that no log row holds the key. No production file changed.
- Gaps closed (the implement stage's tests stayed green under each mutation below):
  - mutation (QA): a failed keyed tool claim is deleted only for the class unreachable (refused and rejected keep it) -> `Test.Channel.EmailOut:TestToolKeyFailureClasses` red (the refused and rejected retry rows); reverted byte-identical
  - mutation (QA): the claim row stores the IdempotencyKey in `DecisionRef` -> `Test.Channel.EmailOut:TestToolKeyClaimHoldsNothingOfTheSend` red (sent and throw rows; the long keys of `TestToolKeyFailureClasses` and the digest test fail to save as well); reverted byte-identical
  - mutation (QA): `Lock -@lockName` removed from `SendClaimed` -> `TestToolKeyClaimHoldsNothingOfTheSend` red (the lock of the key is not free; the framework also reports the leaked locks); reverted byte-identical
  - mutation (QA): the exact-case recheck in `Claimed` removed -> `TestToolKeyClaimIsCaseExact` red; reverted byte-identical
  - mutation (QA): a send with a key is routed to the keyed path before the system test, whatever its origin -> `TestSystemSendWithAKeyIsStillClaimedByItsApproval` red; reverted byte-identical
  - mutation (QA): `ToolKeyOf` without the word tool and the line feed -> `TestToolKeyNeverEqualsADigestKey` red; reverted byte-identical
  - mutation (QA): `SendClaimed` logs the raw IdempotencyKey -> `TestNoPersonalDataInTheLog` red; reverted byte-identical
- Matrix rows and brief items already pinned with a test that can fail (no gap): Repeat, After restart (live `Restart` and a new shadow instance), Other key, No key, Never finished, Error after the claim, Lock held, Tool command with an ApprovalRef, Online demo (the implement stage's mutations), a key scoped to its session (seeded claim of another session, `TestToolKeySendsOnce`). The system/approval and digest pins pass unchanged: `Test.Channel.EmailOut` whole class (twice, once on a fresh warm stack) and `Test.Channel.EmailLive` whole class (115 s, fresh warm stack) passed. Not pinned (named, not closed): another session's lock does not block this session's key (the tool path allows only the mailbox owner's session, so a second session cannot send).
- Tear down: `OCUTALON_RUN_TAG=e21s13qw ci/warm.sh down` (no container left).
- mutations_demonstrated=7

**Code review stage (lane-C throwaways, tag e21s13cw; each mutation observed red and reverted byte-identical, `git status --short` and `git diff --stat` unchanged):**
- mutation (CR): the `MayHaveSent` test removed from `Out.Send` (every failed keyed claim deleted) -> `Test.Channel.EmailOut:TestToolKeyFailureClasses` red (timeout and dropped rows: claim kept, repeat failed); reverted byte-identical
- mutation (CR): `MayHaveSent` ignores the phase of `SMTPConnectionFailed` (any lost connection counts) -> `Test.Channel.EmailOut:TestToolKeyFailureClasses` red (lost row: no claim left, retry sent); reverted byte-identical
- mutation (CR): the keyed claim written with an empty `FallbackReason` instead of `CLAIMPENDING` -> `Test.Channel.EmailOut:TestToolKeySendsOnce` red (the probe's own-Ref claim mark is not pending); reverted byte-identical
- After the patches: `Test.Channel.EmailOut` passed (warm, twice); the stack brought down and up, then `Test.Channel.EmailLive` (whole class, 116 s, `TestReSentTurnSendsOnce` and the unchanged `TestSendFailuresByStubMode` included), `Test.Data.Tables` and `Test.Channel.EmailIn` passed; `docker/tests/test-class-rules.sh` and `test-boundaries.sh` passed; the Property/Index/Storage diff check printed nothing; the spine lint shows only the 10 baseline low placeholders. Stack torn down.

## Auto Run Result

Status: done
Blocking condition: none

**Summary (rework 1, ruling K).** A keyed tool send whose failure may have reached the server (`Sender.MayHaveSent`) keeps its claim marked `maysent` and answers `0|failed|` plus the approved sentence "The mail server stopped answering while the email was being sent, so it may have gone out. OcuTalon won't send it again."; the same key again answers the same sentence and sends nothing. Certainly-not-received failures keep their class texts and free the key. The outcome code stays `failed` (Ok 0). The sentence is the new parameter `MESSAGEMAYHAVESENT`; `FallbackReason` gains the value `maysent` in the existing column (no new column, index or table).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls`: `MESSAGEMAYHAVESENT`, `CLAIMMAYHAVESENT`, `CLAIMMAYSENT`, `Send` and `Claimed`, `SendClaimed`, class description.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls`: doc comment only.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailOut.cls`: `TestTexts`, `TestToolKeyFailureClasses`, `TestNoDoubleSend` and `TestFailureClasses` rows.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: one accepted-text row for the sentence, marked `[ADDED 2026-11-13, Story 21.13, Contest Planner ruling K]`. No other registry lists `EmailOut`'s answers.

**Review.** 15 findings from four layers: patches applied 2 (medium 1, low 1), items deferred 0, rejected 13 with their reasons in the Review Triage Log.

**Follow-up review recommended:** false (this was a follow-up pass and it patched no high; one medium patched, tests only).

**Verification.** Lane-C warm stack `e21s13iw2`, torn down (0 leftovers): `Test.Channel.EmailOut` passed (implement stage, and again after the review patches), `Test.Channel.EmailLive` (whole class), `Test.Data.Tables` and `Test.Data.Delivery` passed at the implement stage; `Out.cls` is unchanged since. `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` passed; the Property/Index/Storage diff check printed nothing; no non-ASCII byte was added. Mutations of this pass are in `## Verification`.

**Residual risks.**
- A `maysent` claim blocks its key for good, like any pending or failed claim (DW-1257).
- An approval's or an unkeyed send that may have reached the server keeps its class sentence (the system path is unchanged).
- No live test reaches the sentence: the CI stub has no timeout or drop-during-DATA mode.
