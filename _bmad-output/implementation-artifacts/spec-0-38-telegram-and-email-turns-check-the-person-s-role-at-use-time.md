---
title: 'Story 0.38: Telegram and email turns check the person''s role at use time, as web chat does'
type: 'bugfix'
created: '2026-11-17'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1284. A Telegram or email message starts a turn on the strength of the pairing (Telegram) or the saved mailbox (email), not of the sender holding a role that may chat at USE time. A viewer, or a person whose OcuTalonUser role was removed after pairing, can start turns that web chat refuses.

**Approach:** extend Story 27.3's use-time check point (the production job in `OcuTalon.Core.Conversation`, when a turn Item arrives) from channel slack to telegram and email, with the SAME role read and the ONE shared predicate (web chat's exact rule) that 27.3 defines; refuse at pair or link time where such a step exists, with existing texts only. The plan stage derives the rest from epics.md Story 0.38, the rulings quoted below, and Story 27.3's in-progress work in `.worktrees/epic-27` (read only).

</intent-contract>

## Spec Change Log

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

## Auto Run Result

Status: draft
Blocking condition: none
