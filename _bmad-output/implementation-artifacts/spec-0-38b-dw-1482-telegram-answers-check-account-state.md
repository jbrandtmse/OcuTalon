---
title: 'DW-1482 (in Story 0.38): Telegram approval answers and Got it check the account state'
type: 'bugfix'
created: '2026-11-17'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-38-telegram-and-email-turns-check-the-person-s-role-at-use-time.md'
warnings: ['release-blocker-for-1.0.13']
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1482. A disabled or expired IRIS user whose Telegram chat is still paired can answer an approval (Approve/Reject buttons, `AnswersIn.FromTelegram`) and press Got it (tell-now `GotIt`, page `AckPage`), because those paths check roles only (`Bridge.Approval` `HoldsRole`/`MayAnswer`, via `Live.Payload.Approval.Answerable`), never the account state that Story 0.38's `Core.Access` reads.

**Approach:** add the ACCOUNT-STATE part only (Enabled, not past ExpirationDate), through the same `Core.Access` logic `MayChat` uses: expose it as one public method (for example `Core.Access.AccountUsable(irisUser)`, which `MayChat` then calls instead of the private `Usable`; `Usable` stays the one %SYS reader). No new chat-role requirement for approvers: an approver needs `RequiredRole` today, not OcuTalonUser, and that stays (the commit message says so).

## Boundaries & Constraints

- `OcuTalon.Bridge.*` must not reference `OcuTalon.Core` (layering). The check therefore sits on the Core side of "the Bridge.Approval role check": `Live.Payload.Approval.Answerable` (AnswersIn rule 6, which asks Bridge.Approval MayAnswer) also requires `Core.Access.AccountUsable(session.IrisUser)`; record in Design Notes which channels this covers (it is the one answer gate of AnswersIn: web, phone and Telegram).
- **Approve/Reject via Telegram:** a refused answer sends nothing to AnswerOps (nothing runs), leaves the request pending (the task open), answers the press with the existing not_allowed handling (the fixed refusal text: the existing catalog text of a not_allowed answer; no new string), and leaves one content-free `Channel.Refused` (channel telegram, reason not_user) to Intake, the way 0.38's refusals are recorded.
- **Got it via Telegram (`Channel/Telegram/In.cls` `GotIt`, the AD-33 exception already granted for 0.38's file check):** when the paired session's IRIS user's account is not usable, submit neither GotIt nor AckPage (nothing is marked handled, nothing is resent), answer the press as today, and leave one `Channel.Refused` (telegram, not_user).
- No new public text. Not model-facing. Do not edit the spine.

</intent-contract>

## Tasks & Acceptance

**Acceptance Criteria (each pinned by a test, with a mutation demonstrated red and reverted):**
- AC1: a DISABLED user and an EXPIRED user (real fixture accounts holding the request's RequiredRole, made with the `Test.Data.Fixture` account helpers such as `ChatSession`/`SetAccount`, cleaned even when a test fails) pressing **Approve** on Telegram are refused: no AnswerOps send, the request stays pending, one `Channel.Refused` (telegram, not_user); an ENABLED, unexpired holder (control) is answered. Mutation: remove the account check -> the disabled and expired cases go red.
- AC2: the same two users pressing **Got it** on Telegram (a tell-now notice, and a page if the existing fixtures allow it cheaply) submit nothing: no Handled row, no handled Notification (nothing resent), one `Channel.Refused`; the enabled control is marked handled. Mutation: remove the check -> red.
- AC3: `Core.Access.AccountUsable` answers 0 for disabled, expired, unknown and empty, 1 for enabled/unexpired, and `MayChat` uses it (existing 0.38 pins stay green).
- AC4: the existing answer tests (AnswersIn, AnswersTelegram, AnswersInWebRoles, TelegramApproval, Test.Core.Access, ViewerApi) stay green.

## Spec Change Log

- 2026-11-17 (lead). Chartered inside Story 0.38 by the Contest Planner's ruling (BINDING), quoted in full:

  > # 0.38 / DW-1482 rulings (Contest Planner, 2026-11-17 ~16:20Z; owner_decision via=contest_planner)
  > 
  > Verified: OCT-epic0-dw1284 = 041ccf71a; feature = cbdf9217b.
  > 
  > 1) DW-1484 (feature cbdf9217b shards-10 frame.spec.ts:455): ACCEPTED as a flake; no rerun of cbdf9217b. The merge head's CI must be fully green on its own.
  > 
  > 2) DW-1482: FIX IN 1.0.13, BEFORE the 0.38 merge, on OCT-epic0-dw1284.
  >    - Why: a disabled or expired IRIS user whose Telegram chat is still paired can answer an APPROVAL. That is more sensitive than starting a chat, which 0.38 now refuses.
  >    - Scope: AnswersIn.FromTelegram and the Bridge.Approval role check also check ACCOUNT STATE (Enabled, not expired) at answer time, through the same Core.Access account-state logic MayChat uses. Add the account-state part ONLY. Do not newly require the chat role for approvers, unless approvers already must hold it; the commit message must say which.
  >    - A refused answer runs nothing, leaves the task open, is audited the way 0.38's refusals are, and gives the chat the fixed refusal text.
  >    - Proof: tests for a disabled user and an expired user answering Got it and Approve through Telegram (refused, nothing resent), plus an enabled control. Mutation: remove the check and those tests go red.
  >    - The report must confirm no other channel can answer approvals with the same gap: email answers, if any; Slack has no approvals by design.
  >    - Not model-facing, so no A/B. Review and QA as usual.
  >    - Ledger: resolve DW-1482 by this story at merge.
  >    - Release note: send a one-line DW-1482 note with the 0.38 note in the PART READY report. The orchestrator relays it.
  > 
  > 3) install-macos (GitHub-hosted macos-15, not acquired: GitHub capacity): merging without it on the branch is APPROVED only if it is still queued or cancelled at about 17:00Z AND the DW-1482 fix is in. Conditions:
  >    - every self-hosted job and lane-a green on the FINAL branch head;
  >    - one merge only;
  >    - install-macos MUST be green on the feature merge run before "1.0.13 REQUIRED GREEN". If it fails there, the Planner is told before any rerun.
  >    GitHub-hosted reruns do not fall under DW-1335.
  > 
  > 4) DW-1483 (Heartbeat reverse-order flake): deferred, LOW, owner wrap-up 2026-11-17.
  > 
  > After the merge: the DEFERRED-markers records commit, then "1.0.13 REQUIRED GREEN <merge sha> + records <sha>".
  > 
  > Follow-up (Planner, ~16:25Z):
  > - The gate is now the DW-1482 fix, not macOS.
  > - Do NOT keep re-queuing the branch's macOS job; the DW-1482 push's new run brings a fresh macOS attempt. (Attempt 3 of 44113263311, started ~16:17Z, is left to finish; no further reruns.)
  > - If GitHub cannot acquire a macOS runner on the feature merge run either: report it with the annotation text and WAIT. GitHub capacity alone is not a reason to ship the final release unproven on macOS; the Planner rules then.
  > 
  > Correction (Planner, ~16:30Z): the macOS allowance stands for the DW-1482 head. If GitHub cannot take install-macos on that head, merge with every self-hosted job and lane-a green; install-macos must then be green on the feature merge run before REQUIRED GREEN. Do not hold the merge for GitHub's queue.

## Design Notes

- Other channels (to confirm in the build): web and phone answers go through the same AnswersIn rule 6 (Answerable), so they get the account check too; email has no approval answers (a reply to an email is never an answer); Slack has none by design.

## Verification

Lane D: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804`, tags `e382i` (fresh) / `e382iw` (warm). Run ONLY the touched and neighbouring classes (no full shards): Test.Core.Access, the answer classes named in AC4, the new tests; each run about 150 s.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
