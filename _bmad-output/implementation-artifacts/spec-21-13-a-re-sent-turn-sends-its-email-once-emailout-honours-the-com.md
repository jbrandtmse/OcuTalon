---
title: "Story 21.13: A re-sent turn sends its email once (EmailOut honours the command's idempotency key)"
type: 'bugfix'
created: '2026-11-12'
status: 'ready-for-dev'
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

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). Spec verified against the READY FOR DEVELOPMENT standard. Veto V1 (the existing `Delivery.DigestKey` column reused for keyed tool claims; no new column, index or global) is for the Planner. No new public text. The spine S-item (AD-14, additive) is for the lead. No IRIS was used (no Task 0).
