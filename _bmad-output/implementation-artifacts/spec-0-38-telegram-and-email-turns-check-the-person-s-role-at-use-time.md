---
title: 'Story 0.38: Telegram and email turns check the person''s role at use time, as web chat does'
type: 'bugfix'
created: '2026-11-17'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'depends-on-27.3']
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1284. A Telegram or email message starts a turn on the strength of the pairing (Telegram) or the saved mailbox (email), not of the sender holding a role that may chat at USE time. A viewer, or a person whose OcuTalonUser role was removed after pairing, can start turns that web chat refuses.

**Approach:** extend Story 27.3's use-time check point (the production job in `OcuTalon.Core.Conversation`, when a turn Item arrives) from channel slack to telegram and email, with the SAME role read and the ONE shared predicate (web chat's exact rule) that 27.3 defines; refuse at pair or link time where such a step exists, with existing texts only. The plan stage derives the rest from epics.md Story 0.38, the rulings quoted below, and Story 27.3's in-progress work in `.worktrees/epic-27` (read only).

</intent-contract>

## Boundaries & Constraints

**Always:**
- The ONE predicate is 27.3's `OcuTalon.Core.Conversation` `ClassMethod MayChat(irisUser As %String) As %Boolean` (Bridge.Approval `RolesOf`, then `Web.Public.Shell` `MayChat(roles)`), called with the **session row's own `IrisUser`**. Never a copy, never another role read, never `SessionOps.IrisUser` (it falls back to `$Username`, the production's user).
- No user on the row, an unknown user, roles that cannot be read, or an exception: refused (fail closed), as 27.3.
- A refused message: no Turn, no Decision, no model call, no tool call, no reply sent, no live event; exactly one content-free `OcuTalon.Channel.Slack.Ignored` with Reason `not_user` and no EventId to Intake (Intake already drops it silently). A failed send of that record is one warning that names nothing of the message; the message is still not taken.
- Only existing user-visible texts. The Telegram pair refusal answers the existing `pairing.badCode`; nothing new reaches a person.

**Never:**
- No change to channel `web`, `mailbox` (the online demo's simulated mailbox, UJ-1), `slack` behaviour, or Intake. No change to `Channel/Telegram/In.cls`, `Bridge/Approval.cls`, the catalog, or any Lane A file.
- No new message class, no new role, no grant, no change to which jobs hold `%Admin_Secure:USE` (27.3 Task 0 measured that production jobs can read another user's roles).
- No new `MESSAGE*` parameter in SessionOps (an outcome without one answers an empty Message).

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected | Pinning test (Test.Core.ConversationNotUser) |
|---|---|---|---|---|
| T1 | Telegram viewer | Item channel telegram, session user holds OcuTalonViewer only | refused as Always (no Turn, nothing to Decide or Notify, no Delivery, no chat event, one record Kind `message.im` Reason `not_user`) | TestTelegramViewerRefused |
| T2 | Telegram role removed after pairing | paired chat's session user had OcuTalonUser (first Item makes a Turn); role removed | next Item refused, one record, no second Turn | TestTelegramRoleRemovedAfterPairing |
| T3 | Telegram admin + user | OcuTalonAdmin,OcuTalonUser | Turn and its Decide request, no record | TestTelegramAdminWithUserAllowed |
| T4 | Telegram admin-only | OcuTalonAdmin alone; also Viewer+Admin; also User+Viewer | refused, refused, allowed: the same answers as `Shell.HasRole`/`Shell.MayChat` on the same roles (control) | TestTelegramAdminOnlyFollowsWebChat |
| T5 | Telegram pair, viewer | valid unused code of a session whose user may not chat (viewer-only; also no user on the row) | outcome `not_user`, Ok 0, empty Message; chat not linked, code not marked used, one `rejected` audit entry reason `not_user`, no pairing event; TelegramIn then answers the existing `pairing.badCode` | TestPairViewerRefused |
| T6 | Telegram pair, user | same, user holds OcuTalonUser | `paired` as before (control) | TestPairViewerRefused (control half) |
| E1 | Email, viewer owner | email.owner = session of a viewer-only user; new Mail | EmailIn sends no Item; exactly one Slack.Ignored Kind `other` Reason `not_user` to Intake; answers OK (the adapter records it seen) | TestEmailViewerOwnerRefused |
| E2 | Email, role removed after the mailbox was saved | owner's user had OcuTalonUser (first Mail gives an Item); role removed | next Mail: no Item, one record | TestEmailRoleRemovedAfterSave |
| E3 | Email, admin + user owner | OcuTalonAdmin,OcuTalonUser | one Item as before, no record | TestEmailAdminWithUserAllowed |
| E4 | Email, admin-only owner | OcuTalonAdmin alone | no Item, one record; control `Shell.MayChat` 0 on the same roles | TestEmailAdminOnlyFollowsWebChat |
| E5 | Email record send fails | probe FailSend 1, viewer owner | no Item, status OK, one warning that names no text, address, user or Ref | TestEmailRecordFailureIsOneWarning |
| W1 | Web unchanged | Item channel web of a viewer-only user | taken as before, no record | TestOtherChannelsUnchecked (27.3's, telegram case removed) |
| L1 | Email link step, viewer | a viewer POSTs the mailbox save `/v1/settings/channels` | existing 403 `read_only` (MESSAGEREADONLY) before anything is read; email.owner unchanged | existing Test.Web.ViewerApi TestEveryWriteRouteRefusesAViewer (no change) |

## Code Map

Base: feature `b2768afeb`. 27.3's predicate is NOT on this base; it exists only in `.worktrees/epic-27` (uncommitted, read only). Read there:
- `epic-27: src/ocutalon/cls/OcuTalon/Core/Conversation.cls` -- class doc L7-10 (the slack check), `Parameter CHECKEDCHANNEL = "slack"` L165-166 (doc "Telegram and email join it in a later story"), `INTAKE`/`LOGNOTUSER` L168-172, `Take` L235 `If ..NotUser(item) Quit ..RecordNotUser()` (after `Untrusted`, so file Items are checked too), `NotUser` L266-279 (`If item.Channel '= ..#CHECKEDCHANNEL Quit 0`), `RecordNotUser` L281-291 (Kind `message.im`), `MayChat` L293-300. Lane B (27.3).
- `epic-27: src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- `RolesOf(irisUser, Output roles) As %Boolean` L417-430; HoldsRole now calls it. Lane A. No 0.38 change.
- `epic-27: src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` -- `MayChat(roles = {$Roles})` L159-166, doc "Slack now; Telegram and email later". Lane B.
- `epic-27: src/ocutalon/cls/OcuTalon/Channel/Slack/Ignored.cls` -- REASONS gains `not_user`; KINDS `message.im,message.channel,message.other,app_mention,other`. Lane B.
- `epic-27: src/ocutalon/cls/OcuTalon/Test/Core/ConversationNotUser.cls` -- real %SYS fixture users (`Session(name, roles, .user)`, `RemoveRole`, `DropUser`), `NewProbe` (Test.Core.ConversationProbe shadow), `Item(session, channel, text)`, `AssertRefused(...)`, `Sent`, `Turns`, `ChatEvents`, `Deliveries`, `Warnings`; `TestOtherChannelsUnchecked` L185 pins web AND telegram as unchecked (0.38 must change it).

On this base:
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` -- TARGET Conversation L160; turn Item channel telegram, provenance user (untrusted for a file) L832-833; allowance consumed before the send L54-61/L897; `Pair` L598-614 answers `pairing.badCode` for every outcome but `paired`. Lane A; unchanged.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- `Pair` L156-196: the session-row check `If '$IsObject(...RefIndexOpen(session)) Quit ..Reject("unknown_code", ...)` ~L166; `Reject` L519-526 (audit `rejected` + `$Parameter(MESSAGE<OUTCOME>)`, "" when absent); `IrisUser` L556-560 ($Username fallback: do NOT use for the check). Lane B, shared_by_entry.
- `src/ocutalon/cls/OcuTalon/Channel/Email/In.cls` -- `OnProcessInput` L39-63: opens the owner session row (L42-44), `IsOwnMail` L46, then makes the Item to Intake (channel email, provenance untrusted). Email Items go to **Intake, never Conversation** (`Core/Intake.cls` L1-26). `Send` seam L96-99. Lane B.
- `src/ocutalon/cls/OcuTalon/Channel/Email/Adapter.cls` -- an email is recorded seen when the service took it (status OK); an error status stops the poll (doc ~L23).
- `src/ocutalon/cls/OcuTalon/Channel/SimMailbox/In.cls` -- channel `mailbox` L30: the demo's mailbox; not checked.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` ~L1559-1566 -- the mailbox save sets `email.owner` to the saving admin's session (POST `/v1/settings/channels`, Web/Api.cls L306); a viewer is 403 read_only at `Web.Api.OnPreDispatch` (L340-362).
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailInServiceProbe.cls` -- records target, class and Item fields only. Lane B (Epic 21's probe; Test/Channel runs in the lane-a shard).
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` / `SessionOpsProbe` -- `Probe()` L745, `Pair(probe, hash, chat)` L801; rows via Test.Data.Fixture.

## Tasks & Acceptance

**Execution** (Task 0 first: rebase onto feature once 27.3 has merged; if it has not, STOP with `## Clarification Needed` — do not author 27.3's text here):
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` (Lane B) -- `CHECKEDCHANNEL` becomes the comma list `"slack,telegram"`; `NotUser` tests `$ListFind($ListFromString(..#CHECKEDCHANNEL), item.Channel)`; parameter and class doc say slack and telegram are checked and that email is checked at EmailIn because no email Item reaches Conversation. `RecordNotUser` and `MayChat` unchanged.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` (Lane B) -- in `Pair`, right after the session-row check: read the row's `IrisUser`; `If '##class(OcuTalon.Core.Conversation).MayChat(irisUser) Quit ..Reject("not_user", "not_user", session, channel)`. No MESSAGE parameter; class doc lists outcome `not_user`. The used-code repeat path (links nothing) is unchanged.
- `src/ocutalon/cls/OcuTalon/Channel/Email/In.cls` (Lane B) -- after `IsOwnMail`: `If '##class(OcuTalon.Core.Conversation).MayChat(session.IrisUser)` send one `Channel.Slack.Ignored` (Kind `other`, Reason `not_user`) to TARGET through `Send`, log one fixed content-free warning when it fails, and `Quit $$$OK` with no Item. Class doc updated.
- `src/ocutalon/cls/OcuTalon/Channel/Slack/Ignored.cls`, `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` (Lane B) -- doc only: not_user is also sent for telegram (Conversation) and email (EmailIn); MayChat serves Slack, Telegram and email.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailInServiceProbe.cls` (Lane B) -- also record `kind`, `reason`, `eventId` for a Slack.Ignored.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationNotUser.cls` (Lane B) -- add T1-T6 and E1-E5 with the class's own fixture (reuse, no copied helpers): Telegram through ConversationProbe Items of channel telegram; pairing through `Test.Core.SessionOpsProbe` and Fixture rows (chat, code); email through `EmailInServiceProbe` with `email.owner` set to the fixture session and put back. Change `TestOtherChannelsUnchecked` to web only. Header lists every test.

**Acceptance Criteria:**
- Given a Telegram Item of a session whose user may not chat by `Conversation.MayChat`, when Conversation takes it, then the matrix rows T1-T4 hold. mutation: CHECKEDCHANNEL back to `"slack"` -> TestTelegramViewerRefused red.
- Given a valid pairing code whose session's user may not chat, when the chat sends `/start <code>`, then T5 holds and the reply is the existing `pairing.badCode`. mutation: delete the MayChat line in `SessionOps.Pair` -> TestPairViewerRefused red.
- Given the saved mailbox's owner may not chat, when EmailIn takes a new email, then E1-E5 hold. mutation: delete the MayChat line in `EmailIn.OnProcessInput` -> TestEmailViewerOwnerRefused red.
- Integration (Rule 1/2): consumers EmailIn, SessionOps.Pair and Conversation (telegram) call 27.3's real `Conversation.MayChat` against real IRIS users holding real roles and produce the refusal records above; no mock of the role read in any pin.
- Given a viewer, when they POST the mailbox save, then L1 holds (existing pin). mutation: remove the viewer branch of `Web.Api.OnPreDispatch` -> ViewerApi TestEveryWriteRouteRefusesAViewer red (revert).
- Given CI on this story's head, when it finishes, then every workflow is green.

## Spec Change Log

- 2026-11-17 (lead). **Story 0.38 spec-gate rulings and the item-4 text, Contest Planner ~01:10Z Nov 17 (BINDING)**, quoted in full; to be applied in the build after 27.3 merges and feature is green:

  > # Story 0.38 (DW-1284) spec-gate rulings (Contest Planner, ~01:10Z Nov 17). BINDING.
  > 
  > APPROVED. It is built AFTER 27.3 lands.
  > 
  > - **The predicate:** MayChat(irisUser) is RolesOf followed by Web.Public.Shell MayChat(roles). It is approved as the one shared rule.
  > 
  > 1. **Email check point: APPROVED.** The check is in Channel/Email/In.cls, BEFORE any Item is made.
  >    - Correct AC1 to: "Telegram turns are checked where they reach Core.Conversation; email is checked in EmailIn before an Item is made".
  > 2. **The not_user record: make ONE small channel-neutral class**, for example Channel.Refused, with reason and channel.
  >    - All three channels (Slack, Telegram, email) use it for not_user.
  >    - Slack's Ignored keeps its other reasons.
  >    - Do NOT reuse a Slack-named class for Telegram and email.
  > 3. **Pairing: badCode for not_user is APPROVED,** with no new text. The audit entry gives admins the real reason.
  > 4. **Email mailbox save:** an admin-only user (one who fails MayChat) must NOT be able to save a mailbox whose email would then be refused.
  >    - REFUSE the save at save time.
  >    - This needs one new sentence. Send its text to the Planner FIRST.
  >    - The Planner's suggestion: "This mailbox would belong to an OcuTalon user who can't use the chat, so its email would never be read. Nothing was changed."
  > 5. **Smaller choices.** OK: a refused email is marked seen and not re-read; a refused pairing does not use up the code; the Telegram allowance entry is used.
  >    - **A REFUSED TELEGRAM FILE: NOT OK to download first.**
  >      - Check BEFORE downloading, so no content from a refused user is fetched or stored.
  >      - If the check order makes that impossible: delete the file at once, never store or read it, and pin both behaviours.
  > 
  > **Release note (for later):** state it plainly as a fix: "a user without the chat role could start conversations through Telegram; now refused."
  > 
  > ## Item 4 text: APPROVED verbatim (Contest Planner, ~01:20Z Nov 17). BINDING.
  > "This mailbox would be yours, but you can't use the chat, so its email would never be read. An admin who can use the chat must connect it. Nothing was changed."
  > - It goes under Save in Settings › Channels › Email, as outcome not_user, refused before anything is written.
  > - Pin the exact text.
  > - Pin that nothing is written.

  Orchestrator relay of item 4: the approved text, VERBATIM: "This mailbox would be yours, but you can't use the chat, so its email would never be read. An admin who can use the chat must connect it. Nothing was changed." It shows under Save in Settings › Channels › Email, outcome not_user, refused before anything is written; pin the exact text and pin that nothing is written. Item 2: whichever of 27.3 and 0.38 lands second moves Slack's not_user onto Channel.Refused.

- 2026-11-17 (lead). Chartered by the orchestrator's Planner dispatch (~00:30Z Nov 17). The BINDING rulings, quoted from `<coordination>/prompts/story-273-rulings-20261116.md` (the 26.4 / DW-1284 section and the 27.3 Task 0 ruling):

  > ## 26.4 / DW-1284: Telegram and email get the same USE-TIME check. RAISED IN PRIORITY.
  > - This is an existing gap in released versions: a viewer paired on Telegram can start turns that web chat refuses.
  > - Schedule it right AFTER the Triage confidence A/B, ahead of the LOW items.
  > - Make it a small story with the same shared predicate and the same pins for each channel.
  > - Its release note says plainly that it is a fix.
  > 
  > ## 27.3 viewer fix, Task 0 outcome (Contest Planner, ~00:05Z Nov 17). BINDING.
  > - **OPTION (a) APPROVED.**
  > - **(c) is REFUSED outright:** no %Admin_Secure on an unauthenticated application, ever.
  > - **(b) is not needed.**
  > 
  > Conditions for (a):
  > 1. **Where and how the check runs**
  >    - In the production job, in Core.Conversation, when a turn Item arrives.
  >    - It uses the SAME role read as Bridge/Approval, and the ONE shared predicate: the web chat's exact rule.
  >    - For now it applies to channel `slack` only. The DW-1284 story extends the same check point to Telegram and email.
  > 2. **A refused turn**
  >    - No turn, no reply, no tool call and no model call.
  >    - One content-free record, with reason `not_user`.
  >    - The inbound Item's text goes no further than its message body, and follows normal retention.
  >    - Pin that no reply is SENT, and that no Conversation or turn row is written for it.
  > 3. **All the pins**
  >    - A viewer's DM is refused.
  >    - A role removed after linking is refused on the next DM.
  >    - An admin who is also a user is allowed.
  >    - An admin-only user follows the web chat's rule.
  >    - Linking a viewer is refused at link time. Task 0 confirms that the admin web process can read roles.
  > 4. **The README fix** goes in the same push.
  > 5. **Conversation.cls** is lane B's file, and no running branch touches it.

  Dispatch additions: the predicate is defined ONCE (lane B is introducing it in Core.Conversation in `.worktrees/epic-27`, branch OCT-epic27; use the exact class, method name and signature; whichever lands first defines it and the other merges to identical text); the pins per channel are a viewer's message refused, a role removed after pairing refused on the next message, admin plus user allowed, an admin-only user following web chat's rule, no reply SENT and no Conversation or turn row written, and pairing or linking a viewer refused at pair or link time where a pairing step exists (existing texts only; any NEW text goes to the Planner first). Branch OCT-epic0-dw1284 from feature b2768afeb.

## Review Triage Log

## Design Notes

**Depends on 27.3.** The predicate, `RolesOf`, `Shell.MayChat`, the `not_user` reason and `ConversationNotUser` exist only in lane B's uncommitted 27.3 work. 0.38 implements after 27.3 merges (Task 0), extending its text; it never authors those definitions. Lane B owns `Conversation.cls` and `ConversationNotUser.cls`; the orchestrator coordinates the edit. Consumes: Story 27.3 `Conversation.MayChat` (use-time check), `Channel.Slack.Ignored` reason `not_user`. Consumed-by: none (no new service). Extend, don't copy: every check calls `Conversation.MayChat`; tests extend 27.3's class and fixture.

**Governing ADs:** AD-4 (pairing: SessionOps is the only linker), AD-14 (channels, provenance), AD-24 (roles), AD-26 (the record shows in Visual Trace), AD-29 (lanes: every product file here is Lane B).

**Email has no Conversation check point (deviation, for the Planner).** Email Items go EmailIn -> Intake (untrusted attention decisions: a decide request and, on act, a turn request, both model calls), never to Conversation, so Story 0.38 AC1's "reaching Core.Conversation" cannot hold for email. The check sits at the first production-job point the email reaches, `Channel.Email.In`, which already opens the owner's session row: the Item is never made, so the email's text stays in the mailbox and no decision, turn row or reply follows. Intake was the alternative (same predicate, Item made then dropped); EmailIn is smaller and keeps Intake channel-blind. The epics.md AC wording needs the lead's Rule 5 correction ("reaching Core.Conversation (Telegram) or EmailIn (email)").

**Decided in-stage:**
- `CHECKEDCHANNEL` stays one parameter (same name) holding a comma list; email is not listed because no email Item reaches Conversation.
- The record reuses `Channel.Slack.Ignored` (no new class): Conversation's unchanged `RecordNotUser` (Kind `message.im`, a direct message) for telegram; EmailIn uses the existing Kind `other`.
- A refused email answers OK, so the adapter records it seen and does not re-read it each poll; it does not come back if the role returns.
- The pair refusal does not mark the code used: if the role comes back before expiry the same code pairs.
- A refused Telegram message has already used one allowance entry (TelegramIn consumes before sending); not refunded.
- Email "link step": the mailbox save is admin-only and a viewer is already 403 read_only there (existing text, existing pin L1); no per-person link exists. An admin-only admin may still save the mailbox, and then every email is refused at use time (E4).

**Measure in Task 0 (inference until measured):** `$Parameter` of an undefined `MESSAGENOTUSER` answers "" on the slot (`ocutalon-slot-d`/`OCUTALON`), and no test or contract requires a non-empty CommandResult Message for a Pair outcome. If either fails, STOP with `## Clarification Needed`: the fallback is a new internal `MESSAGENOTUSER` sentence, which is new text for the Planner.

**Ledger inbox (Rule 17, `LEDGER slice 0-38-telegram-and-email-turns-check-the-person-s-role-at-use-time`):** owned_ledger=1. DW-1284 (routed, med) is addressed in full: Telegram/In.cls:184,204,256 paths through Conversation (T1-T4) and SessionOps.Pair (T5); Email/In.cls:37 through EmailIn (E1-E5). Adjudicate `resolved-by` with the diff.

**Known, not changed:** a refused Telegram file is still fetched and stored by TelegramIn before Conversation refuses the turn (normal retention; nothing reads it). Release-note "fix" wording: notes.sh drafts from the story title; the author's edit carries the sentence in epics.md.

## Verification

**Commands** (from the worktree root; one class per call, `timeout: 600000`, about 150 s each; teardown with the same tag after):
- `OCUTALON_RUN_TAG=e038i OCUTALON_LOCK_OWNER='epic=0 stage=<stage>' OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 ci/iris.sh class OcuTalon.Test.Core.ConversationNotUser` -- expected: `CLASS ... passed`.
- Same env, `ci/iris.sh class OcuTalon.Test.Core.SessionOps`, then `OcuTalon.Test.Channel.EmailIn`, then `OcuTalon.Test.Web.ViewerApi` -- expected: passed (unchanged behaviour).
- Fresh environment (Rule 19): `OCUTALON_RUN_TAG=e038iw` with the same env, `ci/iris.sh shard lane-b`, `ci/iris.sh shard lane-a`, then each with `--reverse`, one per call -- expected: every class passed. Then `ci/iris.sh teardown` for each tag.
- `bash ci/checks.sh` -- expected: every script PASS.

**Shared surfaces:** `Test.Core.ConversationNotUser` TestOtherChannelsUnchecked (asserts telegram unchecked; changes to web only); `Channel.Slack.Ignored` records seen by Intake; SessionOps Pair outcomes (Test.Core.SessionOps, SessionOpsProduction); EmailIn's sends (Test.Channel.EmailIn counts Items per Mail). Every test added or changed passes on a fresh environment, in either order.

**Mutations:** one per AC as written in Tasks & Acceptance; record each as `mutation: <change> -> <test> red` here after it is observed, with the tree byte-identical after revert.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). Implementation waits on Story 27.3 landing on feature (Task 0). Deviation for the Planner: email's check point is Channel.Email.In, not Core.Conversation (no email Item reaches Conversation); epics.md AC1 needs the lead's Rule 5 wording correction.
