---
title: 'DW-1482 (in Story 0.38): Telegram approval answers and Got it check the account state'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: '494ec3a7335541ed4e9e308fe17a97eb6942153c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-38-telegram-and-email-turns-check-the-person-s-role-at-use-time.md'
warnings: ['release-blocker-for-1.0.13']
deferred:
  - summary: >-
      A disabled or expired user with a still-live web or phone session (the web job's own user) is not refused by Answerable, because a web job cannot read another account's state.
    evidence: |-
      Answerable skips the account read when the session's IrisUser is the job's own user; the web job holds no system-namespace privilege, and the plain check made Test.Core.AnswersInWebRoles red (11 failures). The ruling's scope is Telegram; IRIS authenticates the web request's user itself.
    location: >-
      src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls Answerable
    severity: medium
  - summary: >-
      No test runs the real approval API through the Telegram production job with a session of a user other than the job's.
    evidence: |-
      Test.Channel.TelegramAccount and Test.Core.AnswersAccount use shadow instances and the ApprovalDouble; Test.Core.AnswersTelegramProduction uses sessions of the job's own user. The job privilege to read Security.Users is the same one 0.38's MayChat already relies on.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Core/AnswersTelegramProduction.cls
    severity: medium (unverified)
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

- Channel confirmation (build, DW-1482). Answers: web and phone (Web.Api through AnswersIn FromPage, channels web and phone) and Telegram (AnswersIn FromTelegram) all pass AnswersIn OnProcessInput rule 6, so `Live.Payload.Approval Answerable` carries the one account check for all three, with the exemption of the next bullet for a web request's own user (and the approval payload's `answerable` follows it); email has no approval answers (a reply to an email is never an answer; Channel.Email.In starts turns only, and AnswersIn's CHANNELS are web, phone, telegram); Slack has none by design. The Got it press (Telegram tell-now and page) is the separate gate in `Channel/Telegram/In.cls` GotIt, which asks `Core.Access.AccountUsable` itself. No chat role is newly required of approvers: an approver needs the request's RequiredRole, as before.
- A web job cannot read another account's state (no privilege on %SYS), so Answerable does not read the account of the job's own user (`$Username`, a web request's user, whom IRIS signed in with that account just now); the Telegram production job's user is never a session's user, so Telegram answers are always read.
- AnswersIn Refusal gains `"account": true` for an account refusal (kind stays ""), which is how Telegram In records the Channel.Refused for an account refusal only (a role refusal records none, as before).

## Verification

Lane D: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804`, tags `e382i` (fresh) / `e382iw` (warm). Run ONLY the touched and neighbouring classes (no full shards): Test.Core.Access, the answer classes named in AC4, the new tests; each run about 150 s.

Observed (build, DW-1482; warm stack e382iw, one class per call; every mutation reverted `cmp`-identical to its pre-mutation copy):
- mutation: AC1 (Approve refused for a disabled and an expired holder): remove the account check in `Live.Payload.Approval` `Answerable` -> `Test.Core.AnswersAccount` red (19 failures) and `Test.Channel.TelegramAccount` red (the approve test).
- mutation: AC1 (one `Channel.Refused` telegram not_user): remove the `Refused` call in `Channel.Telegram.In` `Press` -> `Test.Channel.TelegramAccount` red.
- mutation: AC2 (Got it submits nothing): remove the account check in `Channel.Telegram.In` `GotIt` -> `Test.Channel.TelegramAccount` red for the disabled and the expired user, tell-now and page.
- mutation: AC3 (MayChat uses AccountUsable): `MayChat` calls `Usable` again -> `Test.Core.Access` `TestAccountUsable` red.
- mutation: AC3 (the answers of AccountUsable): `AccountUsable` always 1 -> `Test.Core.Access` `TestAccountUsable` and `TestAccountState` red.
- mutation: web-job exemption (the own user of a web request is not read): remove it -> `Test.Core.AnswersInWebRoles` red (11 failures).
Passed after the final revert: Test.Core.Access, Test.Core.AnswersAccount, Test.Channel.TelegramAccount, Test.Core.AnswersIn, Test.Core.AnswersTelegram, Test.Core.AnswersInWebRoles, Test.Web.ViewerApi, Test.Live.Payloads, Test.Web.Api, Test.Channel.TelegramApproval, Test.Channel.TelegramIn, Test.Channel.TelegramInTurn, Test.Channel.TelegramFile, Test.Channel.TelegramSwitch.

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 31 findings — high 0, medium 7, low 23, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Spec Auto Run Result still said ready-for-dev beside status in-review — finalize writes the Auto Run Result and status together
  - `[medium]` `[patch]` (blind) Answerable compared IrisUser with $Username case-sensitively; a case mismatch would refuse every web answer — compared with $ZConvert(...,"U") on both sides
  - `[medium]` `[patch]` (blind) docs claim web and phone get the account check, but the web job's own user is exempt — AnswersIn rule 6 comment and the Design Notes bullet now name the exemption; residual risk recorded
  - `[low]` `[reject]` (blind) api-to-Core.Access seam in production code serves the test double — fails closed (a double without AccountUsable refuses); a separate seam parameter is more complexity than the harm
  - `[low]` `[reject]` (blind) AccountUsable is a pass-through wrapper over Usable — the spec asks for exactly this public method; its try/catch keeps the never-throws contract
  - `[low]` `[reject]` (blind) GotIt records a Refused when the session row is missing — a still-paired chat whose Delivery row exists but whose session row is gone is unreachable; nothing is submitted either way
  - `[low]` `[reject]` (blind) unbounded Refused per repeated press — same as 0.38's file refusals (one Refused per refused item); the spec says one Channel.Refused
  - `[low]` `[reject]` (blind) tests lack expires-today cases at Telegram and no mutation for the role-refusal-no-Refused rule — expires-today is pinned in Test.Core.Access and Test.Core.AnswersAccount; the role rule is not an AC and is pinned by TestOtherPressesLeaveNoRefused
  - `[medium]` `[defer]` (edge) own-user exemption: a disabled user with a still-live web session is not caught — web job cannot read the system namespace (measured red in AnswersInWebRoles); outside the Telegram scope of the ruling; recorded as a residual risk
  - `[medium]` `[patch]` (edge) case-differing username defeats the exemption — same patch as the blind finding
  - `[low]` `[reject]` (edge) exemption applies in any job whose $Username equals the session user — the Telegram production job runs as _Ensemble, never a person's session user; a web-context test adds complexity
  - `[low]` `[reject]` (edge) every payload build reads the account per approval — one Security.Users open of one user, and web payload builds are exempt (own user)
  - `[low]` `[reject]` (edge) repeated presses flood Intake with Refused — same as the blind finding (0.38 design)
  - `[low]` `[patch]` (edge) Refused blanks the session ids before the press's own answer is sent — Refused now runs after AnswerPress (TelegramAccount pins answer then Intake)
  - `[low]` `[reject]` (edge) GotIt: missing session recorded as an account refusal — same as the blind finding
  - `[false]` `[reject]` (edge) slots may not be an object in Press — AnswersIn.FromTelegram always sets slots to an object on an OK status, and FixSlots and PressText already use it unguarded
  - `[low]` `[reject]` (edge) an api double without AccountUsable refuses silently — same as the blind finding on the seam
  - `[medium]` `[patch]` (edge) claim that web and phone get the check holds only for another user's session — documentation patched, same as the blind finding
  - `[low]` `[patch]` (gap) the 'request stays pending' assertions cannot fail behind the ApprovalDouble — the two vacuous assertions removed; pending is pinned by Calls() = 0 (nothing reached the answer API)
  - `[medium]` `[defer]` (gap) no test runs the real approval API in the Telegram production job with a non-$Username session — the same job privilege assumption 0.38's MayChat already carries; recorded in deferred
  - `[low]` `[reject]` (gap) 'other presses leave no Refused' control is weak; missing-session branch untested — not in an AC; the branch is unreachable (see the blind finding)
  - `[low]` `[reject]` (gap) AC4 and the guard on Refused have no mutation line — AC4 has no new pinning test; the guard is pinned by TestOtherPressesLeaveNoRefused
  - `[low]` `[reject]` (gap) midnight flake in the expires-today cases — negligible
  - `[low]` `[reject]` (gap) production code branches on a test double — same as the blind finding on the seam
  - `[low]` `[reject]` (gap) exemption pinned only from the web side — its mutation (remove the exemption) is red in AnswersInWebRoles, listed under Verification
  - `[low]` `[reject]` (intent) tests use probe-driven substitutes instead of the real production job — the intent's own Verification names unit classes; the real-job gap is the deferred item above
  - `[low]` `[reject]` (intent) api mapping in product code serves a double — same as the blind finding on the seam
  - `[medium]` `[defer]` (intent) web job's own user exempt, not named in the intent — same as the edge finding; recorded
  - `[low]` `[reject]` (intent) new account member on Refusal and unusable output on Answerable — needed to record Refused for an account refusal only; internal contract, no public text
  - `[low]` `[reject]` (intent) FromRow payload answerable now reflects the account state — intended: the payload's answerable follows the one gate
  - `[low]` `[reject]` (intent) the spec file was edited — Design Notes and Verification are outside the intent contract; the intent contract is untouched

## Auto Run Result

Status: done
Blocking condition: none

Summary: a disabled or expired IRIS user can no longer answer an approval (Approve or Reject, Telegram via AnswersIn FromTelegram, and web and phone through the same rule 6) or press Got it on Telegram. Core.Access gains the public AccountUsable (MayChat calls it; Usable stays the one system-namespace reader). Live.Payload.Approval Answerable refuses an unusable account before it asks MayAnswer; the web job's own user is not read (a web job holds no privilege to). A refused Telegram answer sends nothing to AnswerOps, is answered with the existing not_allowed handling, and leaves one Channel.Refused (telegram, not_user). The Got it press checks the account after the Delivery checks and submits neither GotIt nor AckPage. Approvers get NO new chat-role requirement (they need the request's RequiredRole, as before); only the account-state check is added. No new public text.

Files changed: src/ocutalon/cls/OcuTalon/Core/Access.cls (AccountUsable), Core/AnswersIn.cls (account refusal flag), Live/Payload/Approval.cls (Answerable), Channel/Telegram/In.cls (Press, GotIt, FromTelegram seam), Test/Core/Access.cls, AccessProbe.cls, ApprovalDouble.cls, AnswersAccount.cls, AnswersAccountProbe.cls, AnswersAccountTelegramProbe.cls, Test/Channel/TelegramAccount.cls, TelegramInProbe.cls (new and changed tests), and this spec.

Review: 31 findings; patches applied (case-insensitive own-user compare, exemption documentation, Refused after the press's answer, two vacuous assertions removed); deferred 2 (see frontmatter); every other finding rejected with its reason in the Review Triage Log. Follow-up review recommended: false (no high patched, one medium patched).

Verification: warm stack e382iw, one class per call, all passed after the final patches: Test.Channel.TelegramAccount, Test.Core.AnswersAccount, Test.Core.Access, Test.Core.AnswersIn, Test.Core.AnswersTelegram, Test.Core.AnswersInWebRoles, Test.Web.Api, Test.Web.ViewerApi, Test.Channel.TelegramApproval, Test.Channel.TelegramIn, Test.Channel.TelegramInTurn, Test.Channel.TelegramFile (Test.Live.Payloads and Test.Channel.TelegramSwitch passed before the patches, which do not touch them). Mutations observed red and reverted cmp-identical are listed under Verification.

Residual risks: the two deferred items above.
