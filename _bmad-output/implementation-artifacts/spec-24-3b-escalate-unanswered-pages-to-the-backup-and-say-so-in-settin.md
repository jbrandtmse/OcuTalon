---
title: 'Story 24.3b: Escalate unanswered pages to the backup, and say so in Settings'
type: 'feature'
created: '2026-11-16'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-24-3a-deliver-pages-on-the-on-call-channels-and-take-the-web-ackno.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 24.3a delivers pages and takes the web acknowledgement, but an unanswered page never reaches the backup: `ReminderOps` answers the paging owner's escalation ask with `not_built`. The Settings On call line still describes the pre-24.3 behaviour, GUIDE has no on-call bullet, and DW-1384's escalation-ask test asserts `not_built`.

**Approach:** carry the rest of the old Story 24.3 (epics.md `### Story 24.3b`): the escalation timer in `ReminderOps`/`ReminderTimer` with V1's `Data.Reminder` columns and `Data.Purge` part, re-armed by the startup reconciler exactly once; the approved On call line (Option A, verbatim) with its pins; the approved GUIDE bullet; DW-1384. The plan stage derives the rest from the epic, the parent 24.3 plan and Story 24.3a's spec (its Design Notes list what moved here).

</intent-contract>

## Spec Change Log

- 2026-11-16 (lead). Chartered by the Contest Planner's P5 split of Story 24.3. The BINDING rulings (24.3 gate ~08:30Z and 24.3a Q1/Q2 ~12:30Z, Nov 16), quoted in full from `<coordination>/prompts/story-243-rulings-20261116.md`:

  > # DW-1426 and Story 24.3 rulings (Contest Planner, ~08:30Z on 2026-11-16). BINDING.
  > 
  > ## DW-1426: APPROVED as a small follow-up
  > - Once an undo is answered, announce the EXISTING "Approved/Rejected from…" text and move focus to the incident headline. No new string.
  > - Pin both behaviours, each with a mutation.
  > - It goes into 1.0.12 if it merges before the cut. It is not a cut item.
  > - The earlier ruling (a), "nothing once answered", was about drawing request cards. It was not about announcing the answer.
  > 
  > ## 24.3: NOT in 1.0.12
  > Merge 24.3a only AFTER the 1.0.12 cut. The gate is approved as follows.
  > 
  > ### P5: the split is APPROVED
  > - 24.3a: delivery and the web acknowledgement.
  > - 24.3b: the escalation timer, the On call line, DW-1384 and the GUIDE bullet.
  > - The On call line ships with 24.3b. Until then, DW-1400's line stands.
  > 
  > ### P1: Option A is APPROVED
  > - A page always gets a web chat card, and that card is not counted as a channel.
  > - Telegram and email follow the person's chosen channels exactly, with no fallback.
  > - A person given only as an address gets email only.
  > - An email copy is never marked handled.
  > 
  > Option B is refused.
  > 
  > ### P2: APPROVED
  > A not_paired delivery row that Paging reads.
  > 
  > ### P4: the GUIDE bullet is APPROVED as written
  > - No More-to-try item.
  > - Use the Settings separator GUIDE already uses elsewhere (› or >). Do not introduce a new one.
  > 
  > ### New text 1, the On call line: APPROVED verbatim (Option A version)
  > Keep its pins in ux-strings, on-call-view and O1.
  > 
  > ### Vetoes V1 to V6: APPROVED, with conditions
  > Pin each condition with a mutation.
  > 
  > - (a) V2, page email:
  >   - It goes ONLY to an address an admin set in Settings › On call. Never take an address from an item, the model or a message.
  >   - The body is built only from the fixed page keys: production, failure count, time and the OcuTalon link. No untrusted item or message text goes in verbatim.
  >   - At most one email per page row, and at most one escalation to the backup per page.
  >   - Trace, logs and audit carry ids only.
  >   - It is refused on the online demo in BOTH Notify and EmailOut.
  > - (b) V3, got-it:
  >   - It accepts only the session's OWN page copy.
  >   - Another user's page ref answers 404, exactly like a missing ref, so nothing reveals that it exists.
  >   - It answers 404 on the online demo.
  > - (c) V1, escalation timers:
  >   - They survive a restart and are re-armed exactly once, so a restart never pages twice.
  >   - The Data.Purge part removes only finished escalation rows, and purging the data removes them with it.
  >   - Nothing is written on the online demo.
  > - (d) V4: at merge, send the AD-14, AD-18 and AD-27 amendments as old text and new text.
  > - (e) V5 and V6: the orchestrator coordinates the Lane A and Lane B file overlaps.
  > 
  > ## Lane D order
  > 1. DW-1426 (small; can make 1.0.12).
  > 2. 24.3a: push it, but it merges after the cut.
  > 3. 24.3b.
  > 
  > Any 1.0.12 cut item that is still open comes first.
  > 
  > ## 24.3a Q1 and Q2 (Contest Planner, ~12:30Z Nov 16). BINDING.
  > 
  > ### Q1, the page email: ACCEPTED
  > Use the approved catalog texts as they are, with no link. Conditions:
  > - **Cause:** the diagnosed cause in the email is EXACTLY the sentence shown on the web card and in Telegram, after Bridge.Redact.Text and the same length cap. It is never raw item or message text.
  > - **Name:** the on-call or backup person's name exactly as an admin set it in Settings.
  > - **Pin it:** no item or message text reaches the email body. Add a mutation.
  > 
  > ### Q2: hold 24.3a until 24.3b is green
  > - 24.3a's merge is HELD until 24.3b is green.
  > - The two merge back to back, with no release cut between them.
  > - DW-1400's On call line stays true until then.

## Auto Run Result

Status: draft
Blocking condition: none
