---
title: 'Story 17.12: "Needs you" never counts the person''s own chat messages'
type: 'bugfix'
created: '2026-11-08'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
