---
title: 'Story 0.40: The purge test''s sessions are kept out of the daily digest, and the purge text says what is removed'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['release-gate']
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1449. Test.Data.Purge TestCurrentSessionLosesNoRows failed three times in CI (kept sessions gained a SimMessage; the idle session was not purged). The writer is the running production's daily digest: Digest.Process Ticked (L186-203) queues a digest for every Data.Session row created before the due time (Schedule/Covered L233-255), so a tick inside the test gives each back-dated fixture session a digest Delivery (web) and, in demo mode, a SimMessage (phone); Purge.Keeps (L143) then keeps the idle session. In production this is AD-27's documented rule (a user still receiving notices keeps the session), so Keeps does not change.

**Approach:** test isolation plus a product pin and a doc fix, as ruled: each fixture session gets a Digest.Data.Sent row of Kind scheduled with a far-future DueAt (Covered), removed after the test; the L248 assertion and the kept-session assertions carry before/after counts; a product pin (no activity is purged, a recent Delivery is kept); security-overview.md:212 becomes the approved text, pinned by test-release-sequence with a control.

</intent-contract>

## Tasks & Acceptance

- [x] `Test/Data/Purge.cls`: `Covered(ref)` seeds the Sent row in `Session(days)`; `SentRefs` removed in `OnAfterOneTest`; counts in the idle-session messages; new `TestNoActivityGoesRecentDeliveryKept`.
- [x] `docs/security-overview.md:212` replaced verbatim; `docker/tests/test-release-sequence.sh` pins it (the Data section) and its control mutates it.
- [x] Verification on lane D (warm e040): Test.Data.Purge green; lane-b@Data (26 classes) 5 of 5 green, 3 of them at host load 30-32; test-release-sequence 27/27 (overviewdoc with the purge-sentence control and the 90-days control, now expecting both problems because the approved sentences name 90 days); test-class-rules. Deterministic proof (the Planner's ruling): `TestDigestTickInsideThePurge` handles a digest Tick with a shadow `Test.Digest.ProcessProbe` (Only the test's session) inside the purge window: with the Sent row nothing is queued and the idle session is purged; without it one digest is queued (the old failure on demand). Mutation: the Sent row removed right after `Covered` -> the with-row assertion red (fresh throwaway e040n); green otherwise (Purge class, fresh e040p, 250 s under host load ~60).

**Acceptance Criteria:** as epics.md Story 0.40.

## Spec Change Log

- 2026-11-17 (lead). Chartered by the Contest Planner's classification and GO (BINDING), quoted in full:

  > ## CLASSIFIED: TEST ISOLATION (Contest Planner, ~03:30Z Nov 17). BINDING. This supersedes the orchestrator's "product scope" reading.
  > 
  > ### Purge.Keeps is NOT a product bug
  > - AD-27, and Purge.cls's own header at L1–19, state the rule on purpose: a session goes "never by age alone".
  > - A session is kept while any of these holds:
  >   - it has a Turn, Delivery or Decision at or after the cutoff;
  >   - it is current: a watch, a pairing, a pending approval or reminder, a webhook, or a live sign-in.
  > - A user with watches still running is still RECEIVING notices, so keeping their session is correct. The Delivery and Decision checks also protect references.
  > - The docs make no 90-day promise about sessions (security-overview.md:205–212).
  > 
  > ### Lane D's story
  > - **Isolation:** stop the concurrent notice fan-out from reaching the zzpurge fixture sessions. Either put the fixtures in a production or ownership scope that no other class's notices can reach, or use a shard order that doesn't overlap.
  > - **Counts and load:** add the L248 counts, and loop the test under load.
  > - **Product pin:** a test that pins the documented rule.
  >   - An idle session with NO activity of any kind IS purged.
  >   - A session with a recent Delivery is KEPT.
  > 
  > ### DOC MISMATCH: check it in the same story
  > - **The sentence:** security-overview.md:212 says "The chat history and the session records stay in the private database, and no scheduled purge removes them".
  > - **What the code does:** Purge.Run deletes Turns older than 90 days, and deletes sessions that qualify.
  > - **Ask:** report the facts, and send the Planner a CORRECTED sentence in AD-27's terms (turns go after 90 days; a session goes only when nothing current or recent keeps it). This is PUBLIC TEXT, so it goes to the Planner first.
  > 
  > ## Story 0.40 GO (Contest Planner, ~03:25Z Nov 17). BINDING.
  > 
  > ### The writer: FOUND and accepted
  > - The daily digest's Ticked step schedules a digest for every session, sends its phone copy, and Keeps L143 then counts that copy.
  > - That is AD-27's documented behaviour in production.
  > - "link" means ConversationLink.
  > 
  > ### The plan: APPROVED
  > - **Isolation:** for each fixture session, seed a Digest_Data.Sent row with Kind 'scheduled' and a far-future DueAt, then remove it afterwards.
  > - **Also:** the L248 counts, the load loop, and the product pin.
  > 
  > ### security-overview.md:212: APPROVED verbatim, as ONE replacement, and pinned
  > "Chat turns and the record of each notice sent are removed after 90 days. A session record, with its guide progress, simulated messages and finished reminders, is removed only once it is over 90 days old and nothing keeps it: no turn, notice or decision in the last 90 days, no saved memory or document, and no watch, Telegram pairing, webhook, pending approval or reminder, or live sign-in."
  > 
  > ### GO
  > Story 0.40 goes ahead. Keep each stage saveable for the hold.

  Orchestrator relay: the isolation plan (a Digest_Data.Sent row of Kind scheduled with a far-future DueAt per fixture session, removed afterwards), the L248 counts, the load loop and the product pin are APPROVED; security-overview.md:212 is APPROVED VERBATIM as one replacement, pinned. The answer on OwnedRows' link: it is the bridge's ConversationLink (OwnerRef), neither Telegram's pairing nor SlackLink.

## Auto Run Result

Status: done
Blocking condition: none
