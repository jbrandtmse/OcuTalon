---
title: 'Story 17.12: "Needs you" never counts the person''s own chat messages'
type: 'bugfix'
created: '2026-11-08'
status: 'done'
baseline_revision: 'b51badfd2690df2206070029ea3359044519a267'
baseline_commit: 'b51badfd2690df2206070029ea3359044519a267'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      NeedsYou.List reads the newest 1000 decide Decisions (DECISIONMAX) before it skips own-turn ones, so a session with more than 1000 newer own-turn Decisions in the window could hide an older real tell-now item and give count 0.
    evidence: |-
      Ownership.Decisions(sessionRef, DECISIONMAX) is newest first and capped; the own-turn skip runs after the read. Before this story those Decisions were counted (a false positive), now they are skipped, so the cap can no longer over-count. Reaching it needs over 1000 chat messages newer than the real item inside one digest window (the demo allowance is 50 messages an hour). reopen_if: a session is seen with over 1000 decide Decisions inside one digest window, or Ownership gains a read that excludes turn Decisions.
    location: >-
      src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls:62
    severity: low
---

<intent-contract>

## Intent

**Problem:** On the v1.0.4 demo, after three chat questions, "Send my digest now" printed "3 things need you: Send my digest now; What is the capital of France according to my documents?; How do I rotate the Results certificate?" (DW-979, D3, HIGH for 1.0.5 by the Contest Planner's ruling under the owner's delegation). The user-turn triage Decisions (outcome tellnow, reason "A request from the user; the user is answered directly") were already answered. `OcuTalon.Digest.NeedsYou.List` counts every unhandled tell-now or act decide Decision in the window, so it counts them too. Because the digest's all-clear needs a count of 0, these Decisions also block the all-clear.

**Approach:** `NeedsYou.List` leaves out every Decision that belongs to the person's own turn. A Decision belongs to the person's own turn when its `ItemId` is the `ItemId` of one of the session's `Turn` rows (`Ownership.TurnOfItem`). This is the same rule `Checks.Beat` already uses for the heartbeat snapshot. Real tell-now and act items, incidents awaiting approval and failed check rows still count exactly as they do today. Story 12.12's window and Got it handling stay as they are. Every channel renders the one composed list, so the fix reaches the Telegram digest and the web digest card at the same time. No string changes.

## Boundaries & Constraints

**Always:**
- The exclusion holds whatever the Decision's outcome (tellnow or act), its RecordedAt (inside or outside the window, or empty), its handled marker, its Fallback flag and the turn's Channel (web, telegram) or FromGuide. Such a Decision is never counted and never named.
- It keys on the session's own turns only. A Decision whose ItemId is no turn of this session still counts as it does today, and so does a Decision with an empty ItemId (`TestEmptyItemId`).
- It reads only through the ownership API (`Ownership.TurnOfItem(decision.ItemId, sessionRef, .sc)`). If that read fails, `List` returns its error status and the empty result, as its contract already says. It never counts a Decision silently and never drops one silently.
- The owner `eval` path is unchanged: it holds the failed rows alone and returns before any Decision is read.
- Every test creates and removes its own rows through `Test.Data.Fixture` (`Keep`/`Clean`; a Turn row is kept by its Ref). Every test passes on a fresh stack, in either order.

**Never:**
- No user-facing string, catalog entry or `docs/` wording changes. If one turns out to be needed, HALT with `intent gap` and a condition that begins `PUBLIC TEXT:` and gives the exact text.
- No edit to `Data/Turn.cls`, `Data/Ownership.cls`, `Data/Handled.cls` or `Data/Purge.cls` (other lanes' classes, AD-33). No edit to `Core/**`, `Agent/{Input,Triage}.cls`, `Channel/**`, `Web/Api.cls`, `Install/Step/*.cls` or `Delivery.*` (contended: Epics 18, 41, 30, 39). If a change there is needed, HALT with `intent gap` and name the lines.
- No edit to `Digest/Process.cls`, and in particular none to Epic 12's hunks (the window and Got it handling). No edit to `Checks/Beat.cls`.
- No identification by wording (Summary or Reasons text), by `TriageDecisionRef` or by the Decision's Kind (see Design Notes).
- No real model key and no real Telegram bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pin (DW-979) | Session S. One web turn, and a decide Decision of S with the turn's ItemId, outcome tellnow, Summary "Send my digest now.", Reasons "A request from the user; the user is answered directly". One real tell-now Decision "Disk alert mail" with a fresh ItemId. No window. | `List(S, [])` gives count 1, names exactly "Disk alert mail", more 0 | none |
| Every kind of own turn | Own-turn Decisions of S: a telegram turn (tellnow), a guide turn (FromGuide 1, act), a fallback (Fallback 1, tellnow), one recorded before the window start, one with no RecordedAt, and one whose Ref is marked handled. Plus the real "Disk alert mail" and an incident awaiting approval, with the window start At(100). | count 2: "Disk alert mail", then the incident. No own-turn Summary is named | none |
| Only own turns | S has three own-turn Decisions (tellnow, tellnow, act) inside the window and nothing else | count 0, names [], more 0 | none |
| Another session's turn | A Decision of S whose ItemId is the ItemId of a turn of another session T | it still counts for S (count 1). The rule is "the person's own turns" | none |
| Digest, every channel (Integration) | S has one own-turn Decision and "Disk alert mail", both inside the window. A digest Compose of S goes through `ProcessProbe` (WindowStart At(100)) | The needs-you part is `digest.needsYouOne` with what = "Disk alert mail". `Channel.DigestText.Text(slots, "telegram")` and `Text(slots, "web")` each hold the line "One thing needs you: Disk alert mail." and neither holds "Send my digest now" | Text's sc is OK |
| Digest with only own turns | S has one own-turn Decision inside the window and nothing else | The digest has no needs-you part | none |
| Online demo, real stack (Rule 3) | Online-demo-path step 7: the visitor's "Send my digest now." (the CI mock triages it act), after the guide's watch and reminder turns | The digest card's text does not contain "Send my digest now" | CI only (unit over the per-call cap) |

</intent-contract>

## Code Map

**The fix:**
- `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls`
  - Class doc :1-14, item 2 (:3-5) to extend.
  - `List` :30-83. The Decision loop :61-70: the outcome filter :65, the window :66, an awaiting incident's own Decision :67, handled :68. The read-error pattern is `If $$$ISERR(sc) Quit` :49 and :62, and the error result :81.

**The rule's sibling (Rule 2):**
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` `DecisionLines` :301-320. At :312 it reads `If $IsObject(..Read("turn", sessionRef, row.ItemId)) Continue`, and `Read("turn")` :340-341 is `Ownership.TurnOfItem`. Its doc is :38 ("without the person's own chat messages").
- Its test is `src/ocutalon/cls/OcuTalon/Test/Checks/Snapshot.cls` :205-216: a fixture Turn, then `Fixture.Decision(..., {"ItemId": (turn.ItemId)})`. The new tests copy this pattern.

**Read-only evidence (other lanes' classes):**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`
  - `TurnOfItem(itemId, sessionRef, .sc)` :292-311: an exact match, scoped to the session. "" for an empty or unknown ItemId and for another session's turn. An error for an owner that is no session.
  - `Decisions` :368-372 returns Kind `decide` only, so a `turn` Decision (the reply) never reaches `NeedsYou`.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls`: `ItemId` :33 (unique index :85), `TriageDecisionRef` :24, `Channel` :18, `FromGuide` :21.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`
  - The turn row is created with `turn.ItemId = item.ItemId` (:189-196) before any Decide call.
  - The triage request is built from `ItemOf(turn)` (:372-382: the ItemId is the turn's, provenance user).
  - `TriageDecisionRef` is set only in `Decided` (:396-405), after Decide answers.
  - Only provenance `user` is taken (:225). `Core/Intake.cls` :125 refuses it, so every user-provenance decide Decision comes from a Conversation turn.
- The channels: `Channel/Telegram/In.cls` :621-628 and `Channel/WebChat/In.cls` :87 send user Items to Conversation. The guide's prompts reach the same turn path (FromGuide only marks them for display, AD-30).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` :1585-1588 forces a user decide's ignore or digest outcome to tellnow. So own turns are tellnow or act, the outcomes that NeedsYou counts.
- Retention: `Data/Purge.cls` :42 deletes Turns with `CreatedAt < cutoff`. `src/bridge/cls/OcuTalon/Bridge/Purge.cls` :34 deletes Decisions with `RecordedAt < cutoff`.

**The one caller and the channels (AC 2 evidence):**
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls`
  - `Verdict` :697 calls the seam `NeedsYou` :877-880, the one call of `NeedsYou.List` in `src/`.
  - The needs-you parts :621-633. allClear needs `needs.count = 0` :702.
- `Channel/Telegram/Out.cls` :174 and `Channel/WebChat/Out.cls` :69 render the Notification's Slots with `Channel.DigestText.Text(slots, channel)` (:17-41). `Channel/SimPhone/Out.cls` shows no digest.
- `Web/Api.cls` `RailBody` :1122 lists the rail's recent decisions, not "needs you". `Checks/Beat.cls` already applies the rule (above).
- Catalog: `Msg/Catalog/Watch.cls` :559-573 (`digest.needsYouOne`: "One thing needs you: {what}.").

**Tests to extend:**
- `src/ocutalon/cls/OcuTalon/Test/Digest/NeedsYou.cls`
  - Header :1-22. Helpers: `Keep` :44, `Session` :49, `At` :57, `Decision` :63 (fields adds members, ItemId included), `Incident` :78, `Handle` :85, `List` :112.
  - `DigestNeeds` :294-327: it handles a Compose in a `ProcessProbe` shadow host and reads the recorded Slots from `$List(record, 5)`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `Turn(sessionRef, createdAt, state, text)` :35 (Channel web, FromGuide 0, a new ItemId; returns the Ref) and `Decision` :141.
- `web/e2e-online/demo-path/demo-path.spec.ts`: step 7 :260-281 (the card's `lines` :268) and the header's step 7 note :88-90. `docker/tests/test-online-demo-path.sh` :138 matches the case by its title `^step 7:`, so the title stays.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls` -- In the Decision loop of `List`, after the outcome, window and incident checks and before the handled check, skip a Decision for which `Ownership.TurnOfItem(decision.ItemId, sessionRef, .sc)` returns a turn. On an error status, leave `List` with that status. Extend item 2 of the class doc: the person's own chat or user turn on any channel (its ItemId is one of the session's turns) is never counted. The file stays ASCII; comments state the contract only (Rule 14) -- DW-979.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Digest/NeedsYou.cls` -- Add a helper `OwnTurn(session, minute, summary, outcome, fields)`. It makes a `Fixture.Turn`, sets its Channel and FromGuide from `fields` when given, keeps the turn's Ref, and returns `..Decision(session, minute, summary, outcome, {"ItemId": (turn.ItemId), "Reasons": ...})`. Add the tests below, one per matrix row, and list them in the class header:
  - `TestOwnTurnNotCounted` (the pin)
  - `TestOwnTurnsEveryKind`
  - `TestOnlyOwnTurns`
  - `TestOtherSessionTurn`
  - `TestDigestOwnTurnChannels`: `DigestNeeds` gains an optional Output of the Slots JSON, and the test renders it with `DigestText.Text` for "telegram" and "web"
  - `TestDigestOnlyOwnTurns`

  Every existing test stays unchanged and green -- DW-979.
- [ ] `web/e2e-online/demo-path/demo-path.spec.ts` -- In step 7, after the card's lines are read, assert that the card text does not contain "Send my digest now" ("the digest names none of the visitor's own chat messages"). Add one sentence to the header's step 7 note. The title stays as it is -- DW-979 (Rule 3).
- [ ] Mutations (Rule 19): apply each one on the warm stack, observe red, restore byte for byte (`cmp` against a backup in `<scratchpad>/e17s12impl/`), and see the class green again. Record each one under Verification:
  - (pinning) delete the new TurnOfItem skip: `TestOwnTurnNotCounted`, `TestOwnTurnsEveryKind`, `TestOnlyOwnTurns` and `TestDigestOwnTurnChannels` go red.
  - (over-exclusion) replace the skip with `If decision.ItemId '= "" Continue`: `TestOwnTurnNotCounted` and `TestOtherSessionTurn` go red ("Disk alert mail" is lost).
  - (scope) replace the `TurnOfItem` call with the unscoped `##class(OcuTalon.Data.Turn).ItemIdIndexOpen(decision.ItemId)`: `TestOtherSessionTurn` goes red, because another session's turn is wrongly taken as this person's.

**Acceptance Criteria:**
- Given a session whose own chat or user turns, on any channel, recorded decide Decisions with outcome tellnow or act, when its digest is composed through `NeedsYou` (the morning digest or "Send my digest now"), then those Decisions are never counted or named, whatever their window or handled marker. Real tell-now and act items, incidents awaiting approval and failed rows count as Story 12.12 leaves them, and 12.12's window and Got it tests pass unedited (FR-35, AD-14).
- Given a user turn plus one real tell-now item, when `NeedsYou.List` runs, then the count is exactly 1 and names only the real item. The pin goes red under the pinning mutation (Rule 19).
- Given the Telegram digest and the web digest card, when they show "needs you", then both render the same composed Slots from the one `NeedsYou` list (`TestDigestOwnTurnChannels`). The spec records that no channel reads "needs you" another way (Design Notes).
- Given the change, when it merges, then no user-facing string is added or changed (`git diff` touches no `Msg/Catalog/*` and no `docs/`).

## Spec Change Log

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 15 findings - high 0, medium 0, low 14, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: up to 1000 TurnOfItem reads per Compose, move the handled check ahead of the read - the order and the per-Decision read are Decided in-stage 2 (same as Checks.Beat); reordering changes no result and departs from the spec's stated order; a bound of tell-now/act Decisions in the window, not a user-visible cost.
  - `[low]` `[reject]` Blind: TestOwnTurnsEveryKind's pre-window and handled rows, and the telegram/guide variants, pass without the skip - those two rows are matrix-required and observably equivalent (another filter already drops them); the rows that can fail (no RecordedAt, act, fallback, in-window) are pinned by the mutation; Channel and FromGuide are deliberately unread by the rule.
  - `[low]` `[reject]` Blind: the error path of the TurnOfItem read has no test - the read only fails when the SQL statement fails (Ownership.Rows), which no fixture can provoke without editing Data/Ownership (other lane); two lines that mirror the existing `If $$$ISERR(sc) Quit` pattern. reopen_if: Ownership gains a test seam for a failing read.
  - `[low]` `[reject]` Blind: the e2e assertion is narrower than its comment and could pass with no needs-you line - the spec task names exactly this assertion; the CI mock triages the message act, so the unfixed code names it in the card (the D3 repro); the greeting and cost lines are already asserted.
  - `[low]` `[reject]` Blind: purge deletes Turns before Decisions, so a surviving own-turn Decision is counted again - the Design Notes record it as within seconds of the cutoff (inference); the fix is in Data/Purge or Bridge/Purge, outside the footprint; the class doc's "whatever its time" is about the window.
  - `[low]` `[defer]` Edge: the 1000-Decision read is capped before the skip, so over 1000 newer own-turn Decisions in one window could hide an older real item - real but practically unreachable (50 messages an hour in the demo); the fix needs a paged or filtered Ownership read (out of footprint); recorded in `deferred:` with reopen_if.
  - `[low]` `[reject]` Edge: one SQL read per Decision, load the session's turn ItemIds once - same as the first row (Decided in-stage 2 rejects a full Ownership.Turns read, which loads every turn of a long session).
  - `[low]` `[reject]` Edge: purge makes the Turn vanish before its Decision - same as the fifth row.
  - `[low]` `[reject]` Edge: no test for TurnOfItem failing in the loop - same as the third row.
  - `[false]` `[reject]` Edge: no test for an empty ItemId - `TestEmptyItemId` (an existing test, unchanged and green) plants a tell-now `act` Decision with ItemId "" and asserts it is listed.
  - `[low]` `[reject]` Edge: Channel and FromGuide never reach the code path, so the every-kind tests are one path - that is the rule (any turn of the session, whatever its channel); the cases pin it against a future channel filter.
  - `[low]` `[reject]` Verification-gap: the error path of the TurnOfItem read is unpinned - same as the third row.
  - `[low]` `[reject]` Verification-gap: two rows of TestOwnTurnsEveryKind cannot fail for the defect - same as the second row.
  - `[low]` `[patch]` Verification-gap: step 7's absence assertion has no mutation line - it runs in CI only, so a local red cannot be shown; patched by writing the `mutation:` line in `## Verification`, labelled CI-only and (inference).
  - `[low]` `[reject]` Intent-alignment: readings A (List), B (composed digest) and C (delivered card); the diff implements A and B in unit tests, and C through the CI-only step 7 assertion; allClear is covered through the count - descriptive only, no divergence beyond what the spec states (matrix row 7 is CI only).

## Design Notes

**How a user-turn Decision is identified.** A Decision is the person's own when `Ownership.TurnOfItem(decision.ItemId, sessionRef)` finds a turn. This is the narrowest reliable test:
- Conversation saves the Turn with the Item's ItemId before it calls Decide (`Conversation.cls` :189-196), and the triage request carries that ItemId (:372-382). Decision rows are unique on (ItemId, Kind) (AD-20).
- `TriageDecisionRef` is less reliable: it is written only after Decide answers (:402). A turn whose attempt went stale, or a save that failed after the row was recorded, leaves a Decision that no turn names.
- Provenance (AD-14: "use this, not wording") is not stored on the Decision. Every user-provenance item goes only to Conversation, which writes a Turn row (Intake refuses user provenance, `Intake.cls` :125). So "has a turn" is exactly "provenance user" for a session's decide Decisions. The owner `eval`'s user-turn cases never reach this read.
- A Decision of Kind `turn` (the reply) can never count, because `Ownership.Decisions` returns Kind `decide` only.

**Paths considered:**
- Web chat, Telegram (`Telegram/In.cls` :625), the guide (FromGuide is display only and the same turn) and the online demo (a visitor's own session and turns) all write Turn rows. Each one is covered.
- A fallback triage of a turn is still keyed by the turn's ItemId.
- Retention: Turns and Decisions are purged on the same day count, by CreatedAt and RecordedAt. A surviving own-turn Decision therefore keeps its turn, except within seconds of the cutoff (inference).

**No channel reads "needs you" another way (AC 2 evidence).**
- `NeedsYou.List` has one caller, `Digest.Process.Verdict` :697 through the seam :877-880.
- Telegram (`Telegram/Out.cls` :174) and the web digest card (`WebChat/Out.cls` :69) render the same Notification Slots through `Channel.DigestText.Text`. The Simulated phone shows no digest.
- `Web/Api.cls` :1122 is the rail's recent decisions, not "needs you". The heartbeat snapshot (`Checks/Beat.cls` :312) already applies this rule.
- A repository-wide search for `NeedsYou`/`needsYou` outside the tests finds only these files and the catalog.

**Governing ADs (Rule 6):**
- AD-14: provenance user is the person's own text, and the rule follows provenance through its Turn, not wording.
- AD-4: the read goes through the ownership API, scoped to the session.
- AD-20: Decisions are unique on (ItemId, Kind) and owned by OwnerRef.
- AD-30: Conversation alone owns the turn queue.
- AD-28: the all-clear comes from code. Leaving answered own turns out lets a truly quiet digest give its all-clear. This removes a false "needs you" and adds no false all-clear, because failed rows, approvals and real items still count.
- AD-32: one Slots contract that every channel renders.
- AD-33: `Data/Turn` and `Data/Ownership` are only read, never edited.
- No AC contradicts an AD.

**Ledger (Rule 17):** DW-979 is addressed by the NeedsYou task, the NeedsYou test task, the matrix rows and ACs 1-2.

**Integration ACs (Rule 1):** no new service, module or shared component. The "Digest, every channel" row is the consumer check: `Digest.Process` composes the list and both channels' renderer shows it.
- Consumes: `Ownership.TurnOfItem` (Story 2.13) and `Ownership.Decisions`.
- Consumed-by: `Digest.Process` (Stories 17.6, 12.12), `Telegram/Out` and `WebChat/Out` through `Channel.DigestText` (Story 17.10).

**Extend, don't copy (Rule 2):** the rule is `Checks.Beat.DecisionLines` :312's one call to the existing shared API, `Ownership.TurnOfItem`. The call is the shared rule, so no new wrapper is added; a wrapper would be one line around one call, and Beat is outside this story's footprint. The new tests extend `Test.Digest.NeedsYou`'s helpers and copy `Test.Checks.Snapshot` :205-216's fixture pattern.

**PUBLIC TEXT:** none.

**Decided in-stage:**
1. The ItemId match through `TurnOfItem`, for the reasons above.
2. One `TurnOfItem` read per candidate Decision, made after the cheap filters. This is bounded by the tell-now or act Decisions in the window, as in Beat. It is not one `Ownership.Turns` read, which loads every turn of a long session.
3. A failed read makes `List` an error (the existing contract). The digest then fails as it does for any other read error, and never counts or drops silently.
4. Rule 3's real-runtime evidence is one absence assertion in the online demo's step 7, the surface where D3 was seen. It runs in CI only (group `image`, `live:online-demo-path`, about 334-389 s, over the 150 s per-call cap). `web/e2e-online/` is outside this story's named footprint, and no contended epic owns it, so it is a Rule 11 (b) footprint extension, reported at completion.
5. The own-turn summaries in the tests are invented ("Send my digest now.", "What is the capital of France?"). They add no product string.

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=17 stage=implement'`.
- Tags: `e17s12iw` (warm) and `e17s12i` (fresh).
- Run one call at a time, in the foreground, with `timeout: 600000`, and size each call to about 150 s. Make one `iris_execute_tests` per message.
- MCP calls go only to `server` `ocutalon-slot-b`, `namespace` `OCUTALON`, after `iris_server_info` shows build 154.

**Commands:**
- (once) `iris_doc_load` of `Digest/NeedsYou.cls` and `Test/Digest/NeedsYou.cls` on `ocutalon-slot-b`. Expected: both compile.
- (once) `OCUTALON_RUN_TAG=e17s12iw ci/warm.sh up`. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s12iw ci/iris.sh class OcuTalon.Test.Digest.NeedsYou`. Expected: `CLASS ... passed`. The mutation runs use this command.
- (once) The same warm command, one class per call, for `OcuTalon.Test.Digest.Compose`, `AllClear`, `EvalCase`, `TelegramText` and `OcuTalon.Test.Checks.Snapshot`. Expected: each passes, unedited.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call. Expected: PASS (ascii, assert-concat).
- (once) `cd web && npx tsc -p tsconfig.e2e.json`. Expected: no error.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s12i ci/iris.sh shard lane-a@Digest`, then the same with `--reverse`, then `OCUTALON_RUN_TAG=e17s12i ci/iris.sh teardown`, each in its own call (`--part k/2` if a call nears 150 s). Expected: every class passes.
- (once) `OCUTALON_RUN_TAG=e17s12iw ci/warm.sh down` at the stage's end, also after a failure.
- (CI) `live:online-demo-path` (group `image`) and the full groups run in CI on push, not locally: the unit is over the per-call cap.

**Shared surfaces:** the needs-you count and names of a digest (and with them the digest's allClear). The other tests that assert them (`Test.Digest.Compose`, `AllClear`, `EvalCase`, `TelegramText` and the existing `NeedsYou` tests) plant Decisions with fresh ItemIds and no matching Turn, so none changes shape. Online-demo-path step 7 gains one assertion and keeps its title.

Every test added or changed passes on a fresh environment, in either order.

**Implementation evidence (Rule 19), run on the warm stack `e17s12iw`:**
- mutation: (pinning) deleted the `TurnOfItem` skip in `Digest/NeedsYou.cls` -> `Test.Digest.NeedsYou` red: `TestOwnTurnNotCounted`, `TestOwnTurnsEveryKind`, `TestOnlyOwnTurns`, `TestDigestOwnTurnChannels` and `TestDigestOnlyOwnTurns` failed; restored byte for byte (`cmp`), class green.
- mutation: (over-exclusion) replaced the skip with `If decision.ItemId '= "" Continue` -> red: `TestOwnTurnNotCounted` and `TestOtherSessionTurn` failed ("Disk alert mail" lost), and so did the older tests that plant Decisions with an ItemId (`TestOrder`, `TestOverflow`, `TestOverflow200`, `TestOverflowEmptyTime`, `TestWindow`, `TestWindowUndated`, `TestProcessWindow`, `TestProcessNoUpperBound`); restored byte for byte (`cmp`), class green.
- mutation: (scope) replaced the `TurnOfItem` call with the unscoped `OcuTalon.Data.Turn` `ItemIdIndexOpen(decision.ItemId)` -> red: `TestOtherSessionTurn` alone failed; restored byte for byte (`cmp`), class green.
- mutation: (CI only, not demonstrated locally: `live:online-demo-path` is over the per-call cap) deleting the `TurnOfItem` skip in `Digest/NeedsYou.cls` -> step 7's `not.toContain('Send my digest now')` goes red, because the CI mock triages that message act and the card would name it (inference). The unit tests above pin ACs 1 to 3; the step 7 assertion is Rule 3's real-runtime evidence.
- `OcuTalon.Test.Digest.NeedsYou`, `Compose` and `AllClear` pass on the warm stack; `cd web && npx tsc -p tsconfig.e2e.json` has no error.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Digest.NeedsYou.List` now skips every decide Decision whose `ItemId` is the `ItemId` of one of the session's turns (`Ownership.TurnOfItem`, session-scoped), so the person's own chat messages are never counted or named in the digest or in its all-clear count. A failed read returns the error status and the empty result. No user-facing string changed.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls`: the TurnOfItem skip in the Decision loop and the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Digest/NeedsYou.cls`: the `OwnTurn` helper, `DigestNeeds` returns the Slots JSON, and six new tests (one per matrix row).
- `web/e2e-online/demo-path/demo-path.spec.ts`: step 7 asserts the card does not contain "Send my digest now" (Rule 11 (b) footprint extension, CI only).
- This spec: Verification evidence, triage log, deferred item.

**Review.** Four layers, 15 findings: patches applied 1 (the step 7 `mutation:` line, low); deferred 1 (the 1000-Decision read cap, low, in `deferred:`); rejected 13 (12 low with their reasons in the triage log, 1 false). No high or medium.

**Follow-up review recommended:** false (no patched high, fewer than two patched medium).

**Verification.** Both classes compiled on the slot (build 154U). Warm stack `e17s12iw`: `Test.Digest.NeedsYou`, `Compose`, `AllClear`, `EvalCase`, `TelegramText`, `Test.Checks.Snapshot` passed; `test-boundaries.sh` and `test-class-rules.sh` passed; `npx tsc -p tsconfig.e2e.json` clean; warm stack down. Fresh `shard lane-a@Digest` forward and `--reverse`: 22 of 22 classes passed each time; fresh tag torn down. Three Rule 19 mutations demonstrated (pinning, over-exclusion, scope) and restored byte for byte. `live:online-demo-path` runs in CI only.

**Residual risks.** Step 7's assertion is unexercised locally (its `mutation:` line is labelled inference). The 1000-Decision cap (deferred) is practically unreachable.
