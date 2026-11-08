---
title: 'Story 17.10: The digest shows in the web chat, and the online demo''s digest is visible'
type: 'bugfix'
created: '2026-11-07'
status: 'in-progress'
baseline_revision: 'c390d57f1326d22b445db88fcd1cfbae49395f52'
baseline_commit: '686baec753690d78b69dd1dd616404947856dce1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** "Send my digest now" promises a digest that never shows up in the web chat, on any install, because `WebChatOut` records a digest as a Delivery row with no text and the page draws no card for it. On the online demo, the morning run also composes a digest for every visitor session that has a resume hash, which makes a model call when something was saved for later.

**Approach:** Move `TelegramOut`'s digest rendering into one shared helper that takes the channel. `WebChatOut` uses it with "web" to record and publish a plain-text digest card. The snapshot query and the web chat show that card, and the morning run skips online-demo sessions. Telegram's output stays byte-identical, pinned by a golden test written before the move.

## Boundaries & Constraints

**Always:**
- The card text is the shared `digest.*` and `checks.*` catalog texts, rendered through `Msg.Catalog.Render` with channel `web`. It has the same pieces in the same order as Telegram, one piece per line. There are no new strings, and the card has no title, heading or label.
- Telegram's digest text stays byte for byte as it is today. A golden test is added and run green before the move, and run green again after it. `Test.Channel.TelegramDigest` passes, unedited.
- The helper is a MOVE of `DigestText`, `Pieces`, `Piece` and `AFTERLINES`, not a copy. After the move, neither `TelegramOut` nor `WebChatOut` keeps its own copy.
- Routing is unchanged: `Digest.Process` `Own`/`Deliver` and Notify. A local user with Telegram paired gets the digest in both places (accepted).
- The online demo is `Data.Public.Settings` `onlineDemo` on. On it, the scheduled (morning) run queues no Compose for any session. A session with a resume hash is an online-demo visitor and is skipped. A session without one has ended and is skipped as before. Local installs are unchanged. A visitor's `SendDigest` still composes and sends, with the model summary only when something was saved for later.
- Tests use the CI mock only. New mock scenarios are new files under `ci/mock/scenarios/B/`. No existing scenario file is edited.

**Never:**
- No change to `Channel/SimPhone/Out.cls` (the simulated phone shows no digest), to the full UX digest card ("What I checked ({n})", Story 18.4), or to the payload classes and `web/src/app/live/payloads.ts`.
- In `Digest/Process.cls`, nothing outside `Ticked` and the class comment's due-rule sentence at :7-8 changes (Epic 12 edits :32, :596, :668-695 and :872-880).
- In `Channel/Telegram/Out.cls`, only the DigestText/Pieces/Piece/AFTERLINES region and the call site at :176-177 change.
- These files are not edited: `Test/Channel/TelegramDigest.cls`, `web/e2e/support/floor.ts`, `web/playwright.config.ts`, `web/e2e/support/diagnose.ts`, `ci/iris.sh`, `web/e2e/heartbeat-card.spec.ts`, `release/*`, `eval/run.sh` and the IPM scripts.
- No real model key and no real Telegram bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Web digest card | A digest Notification for a session reaches WebChatOut, with parts that include an after-lines part (for example `digest.saved`) and two lines | One Delivery row of channel web, kind `digest`, a new Ref as ChannelMessageId, Text = the pieces joined with LF: the parts up to the checked sentence, then the lines, then the rest. DecisionRef as sent, DueAt "", FallbackReason "". One `notification` event whose payload has kind `digest`, the whole text and an empty whyNow. The row is in `RecentNotices` | None |
| No after-lines part | Parts are only the greeting, vitals and checked parts | The lines come last | None |
| Render error | A part or line has an unknown key, or the Slots have no `parts` or no `lines` array | An error status. No row and no event | The status is returned (Ensemble records it) |
| Telegram golden (Integration AC: TelegramOut consumes the helper) | The same Slots fixtures sent to TelegramOut's `OnNotification` | `Send` gets exactly the golden text, with no markup. The text is identical before and after the move | A render error sends nothing |
| Web consumer (Integration AC: WebChatOut consumes the helper) | The same Slots fixtures sent to WebChatOut | Row Text = `DigestText.Text(slots, "web")` = the written-out expected text | As above |
| Browser, local install | A digest Notification for the notice user through Notify (N16) | One notice card with class `digest`, the inbox icon, the text with its line breaks (innerText lines), and no heading, strip, caption or Why now. After a reload the same card shows from the snapshot | None |
| Online demo, morning | `onlineDemo` 1. One session with a resume hash and one without, both created before `digest.time`. A tick after `digest.time` | No Compose is queued. With `onlineDemo` 0, both sessions get one | None |
| Online demo, asked | `onlineDemo` 1. A `SendDigest` (origin tool) for the session with the resume hash | One requested Compose (empty DueAt) and the Ok/sending answer | None |
| Online demo path (REL-2) | The visitor of steps 2 to 5 types "Send my digest now." | The turn is done (chip Act on the mock), and one digest card appears in that visitor's chat. Its first line is a greeting and its last line is "Yesterday's cost: $n.nn.". The simulated phone gets no digest note | The unit fails |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (Lane A, not contended)
  - :113-114 `AFTERLINES`.
  - :176-177: the digest branch of `OnNotification`, which becomes `Set text = ##class(OcuTalon.Channel.DigestText).Text(request.Slots, ..#TEXTCHANNEL, .sc)`.
  - :213-259 `DigestText` / `Pieces` / `Piece` move out.
  - The class comment :26-31 stays true as it is, so it is not edited.
  - `Send` :482 is public. `Target` :263 and `Recorded` :299 are private, and a subclass may override them (as `Test.Digest.ProcessProbe` overrides private seams).
- New `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls`: `ClassMethod Text(slots As %String, channel As %String, Output sc As %Status) As %String`, with private `Pieces(elements, before, channel)` and `Piece(element, channel)` and `Parameter AFTERLINES` (moved verbatim, error text included).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` (Lane B)
  - Class doc :1-23.
  - `CARDKINDS` :31.
  - `OnNotification` :57-70, where :64 renders `CatalogKey` (a checks key for a digest) and :66 is `Delivery.Record` + `Announce`.
  - `FallbackReasonOf` :104.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` (Lane B): class doc :40, `RecentNotices` doc :412-414, and the `recentNotices` query :910 (add `'digest'` to the Kind IN list).
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls`
  - `Ticked` :197-219. :204 reads `online`, and :209 `If online && (ResumeHash = "") Continue` skips only ended sessions.
  - `Resends` :218 stays (it sends a stored digest to the channels it missed, with no model call).
  - `Own` :882 and `Requested` :391 are read-only.
  - Notify's rule (`Core/Rule/Notify.cls` :42-52) already sends a digest to WebChatOut.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Notification.cls` :46-66 (read-only): for any kind but tellnow, `FromRow` keeps the whole text, and it attaches the decision when there is a DecisionRef.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` :434-606 (read-only): no digest key has a `web` text, so the web and Telegram texts are the same today.
- Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls`
    - Class doc :1-28.
    - `TestOtherKindsRecordOnly` :296-300: :298 lists `digest` and :299 pins `CARDKINDS`.
    - Helpers: `Out` :461, `Notification` :469, `Notifications` :487, `Newest` :493, `Rows`/`LastRow`, and `AssertRecordOnly` :434.
    - Lane B, area Core, shard lane-b, group `image`.
  - `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` `TestRecentNotices` :826-859. The :853-859 loop reads `CARDKINDS`, so the digest joins it. Area Data, group `image`.
  - `src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls`
    - Class doc :19-20.
    - `TestEndedOnlineDemo` :290-306 asserts the old rule (one Compose for the session with a resume hash).
    - Helpers: `Session(createdLocal, resumeHash)` :90, `Host` :102, `Tick` :111.
    - The SendDigest pattern is at :187-200.
    - Area Digest, piece lane-a@rest, group `shards-2`.
  - Probes to copy the pattern from: `Test/Digest/ProcessProbe.cls` and `Test/Bridge/ZoneCase.cls` (it fixes the zone).
- Web:
  - `web/src/app/chat/chat-view.ts`: header :8-10, `NoticeKind` :139, `NoticeView` doc :141-143, `noticeOf` doc :211-212, and its filter :220. `strip` stays tellnow-only (:242).
  - `web/src/app/chat/notice-card.ts`: class comment :8-25, the template class bindings :31, `.request .text { white-space: pre-line }` :80-82, and `icon` :118-125. The `inbox` icon exists (`icon/icon.ts` :138).
  - `web/e2e/chat/notice.spec.ts`
    - Helpers: `open` :41, `cardOf` :38, `unique` :35, `today` :51, `CARD_MS`.
    - The reminder case N5 :158 shows the icon, bar and text assertions. N7 :199 shows the reload.
    - N3's "digest" is an item outcome, not this kind, and is unaffected.
    - Project chromium, unit live:sign-in, group `browser`.
  - `web/e2e/support/iris.ts` `sendNotification` :652 (kind, catalogKey, slots object).
- Online demo:
  - `web/e2e-online/demo-path/demo-path.spec.ts`: the serial block of steps 2 to 5 is at :150-230, and its visitor is `pageOf()`.
  - `web/e2e/support/demo-path.ts` (read-only): `sendThroughComposer(page, prompt, false)` :203 (it expects chip Act on the mock) and `phoneNotes` :60.
  - `docker/tests/test-online-demo-path.sh`: the report check :105-175 wants exactly seven passed cases and 10 in all (:130, :135, :146, :172-175), and the header is :16-18.
  - Unit live:online-demo-path, group `image`.
- Mock:
  - `ci/mock/scenarios/A/digest-send-now.json` gives the shape (toolUse `send_digest` {}, then text).
  - The keyed prompt pairs follow `B/guide-reminder.json` / `B/guide-reminder-triage.json` (mockkey `chat` / `triage`).
  - `ci/mock/scenarios.mjs` refuses a prompt that contains another B prompt or repeats one.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` :969 says the digest "reads as prose in Telegram and on the phone (UJ-2), and appears in the web chat as a digest card".
- CI time, measured from `gh run view` jobs on 2026-11-07, 11 complete runs:
  - `browser` 33-39 min (8 of 11 at 35 or more; OCT-epic39 run 42400798775 failed at 39). The feature run 42398754916 took 38.9.
  - `image` 28-31.
  - `shards-4` 23-35.
  - `shards-2` 27.7 on 42398754916.
  - `shards-5` 21.4 on 42398754916.

## Tasks & Acceptance

**Execution (in this order):**
- [ ] `src/ocutalon/cls/OcuTalon/Test/Digest/TelegramOutProbe.cls` (new) and `src/ocutalon/cls/OcuTalon/Test/Digest/TelegramText.cls` (new): the golden test, BEFORE any other source change.
  - The probe extends `Channel.Telegram.Out`. `Send` records each text and markup in a process-private global and answers one sent part. `Target` answers a fixed chatRef/chatId with no Pairing read. `Recorded` writes nothing.
  - `TelegramText` extends `Test.Bridge.ZoneCase` (a fixed zone), with `onlineDemo` off and put back. Through the probe's shadow instance `OnNotification`, it covers:
    - (a) the full digest: greeting, vital signs, checked + `checks.notEverythingRestPassed`, three lines (passed, failed and a not-checked line with fixed, dated UTC times), `digest.needsYouOne`, `digest.saved` and `digest.cost`;
    - (b) parts with no after-lines part (the lines last);
    - (c) an empty lines array;
    - (d) an empty parts array with lines;
    - (e) an unknown key: an error and no Send;
    - (f) Slots with no `lines`: the error text "the digest's Slots have no parts or no lines" and no Send.
  - Each expected text is written out literally, never read from the catalog, and joined with `$Char(10)`.
  - Run it green on the current code and record the run under Verification "Golden runs".
- [ ] `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` (new) and `Channel/Telegram/Out.cls`: the move, with the code unchanged except that the channel is a parameter. TelegramOut calls `Text(request.Slots, ..#TEXTCHANNEL, .sc)`. The class doc says what the helper promises: the order, one piece per line, no Markdown, and only the `*Out` operations call it. Run `TelegramText` green again and record it.
- [ ] `Test/Digest/TelegramText.cls`: add `TestOneHelper`, structural, from `%Dictionary.CompiledMethod`/`ParameterDefinition`.
  - `Channel.Telegram.Out` and `Channel.WebChat.Out` define none of `DigestText`, `Pieces`, `Piece` or `AFTERLINES`.
  - Both implementations name `OcuTalon.Channel.DigestText`.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`:
  - `CARDKINDS = "tellnow,reminder,allowance,digest"`.
  - A digest branch: the text is `DigestText.Text(request.Slots, ..#TEXTCHANNEL, .sc)`, and it is recorded and announced on the card path, with DueAt "" and FallbackReason "".
  - Update the class doc (the digest bullet, and remove digest from "any other kind").
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: add `'digest'` to the `recentNotices` Kind list. Update the docs at :40 and :412-414.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls`:
  - `TestOtherKindsRecordOnly` lists `fallback,pairing,status`, and its pin reads `"tellnow,reminder,allowance,digest"`.
  - Add `TestDigestCard`, covering the matrix rows "Web digest card", "No after-lines part" and "Render error": the row, the event payload JSON, `RecentNotices`, and `Text` equal to the written-out text and to `DigestText.Text(slots, "web")`.
  - Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` `TestRecentNotices`: assert that `digest` is one of `CARDKINDS`, and that a web `digest` row is a card. Update its doc :826-829.
- [ ] `src/ocutalon/cls/OcuTalon/Digest/Process.cls`, `Ticked` (doc :197 and :204-210) and the class comment's due-rule sentence at :7-8 only: on the online demo, queue no scheduled Compose for any session. `Resends` stays. Both docs state the rule (AD-18 as amended 2026-11-07).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls`: replace `TestEndedOnlineDemo` with `TestOnlineDemoSkipped`, covering the matrix rows "Online demo, morning" and "Online demo, asked" (DW-874). Update the class doc bullet.
- [ ] `web/src/app/chat/chat-view.ts`: add `'digest'` to `NoticeKind` and to `noticeOf`'s filter, and update the docs (:8-10, :141-143, :211-212).
- [ ] `web/src/app/chat/notice-card.ts`: `[class.digest]`, the icon `inbox` for kind digest, and `.digest .text { white-space: pre-line }` (shared with `.request .text`). Add a class-comment bullet: the digest card is the digest's text alone, with no strip or caption.
- [ ] `web/e2e/chat/notice.spec.ts`: add N16 (DW-874) for the matrix row "Browser, local install". It sends with `sendNotification(user, {kind: 'digest', catalogKey: 'checks.everythingElsePassed', slots: {parts, lines, rows: []}})`, with a `unique('N16')` marker in `digest.saved`'s summary. It asserts the `.notice.digest` card, the inbox polyline, the 4px bar, `innerText` of `.text` split on LF equal to the expected lines, no heading, `.title`, strip, caption or `.why`, and the same after `page.reload()`. (Placement ruled: `notice.spec.ts`, Q3 (a).)
- [ ] `ci/mock/scenarios/B/digest-send-now-chat.json` and `ci/mock/scenarios/B/digest-send-now-triage.json` (new):
  - prompt "Send my digest now.";
  - mockkey `chat`: replies toolUse `send_digest` {}, then the text "The CI mock says your digest is on its way.";
  - mockkey `triage`: the outcome `act` JSON, as in `guide-reminder-triage.json`.
- [ ] `web/e2e-online/demo-path/demo-path.spec.ts`: add `test('step 7: "Send my digest now." in the chat shows the digest card in the visitor\'s own chat, and the simulated phone gets none', ...)` inside the steps 2 to 5 serial block, after step 5 (DW-874). Use `sendThroughComposer(pageOf(), 'Send my digest now.', false)`, then one `.notice.digest` card within 90 s. By pattern: its first line is `^Good (morning|afternoon|evening)\.$`, it has a line `^I checked ` or the nothing-watched text, and its last line is `^Yesterday's cost: \$\d+\.\d\d\.$`. `phoneNotes` holds no note with that greeting line. Update the header comment.
- [ ] `docker/tests/test-online-demo-path.sh`: the report check wants eight passed cases (add `/^step 7:/`) and 11 in all. Update the header :16-18 and the PASS/FAIL texts.
- [ ] `EXPERIENCE.md` :969: add a marker only: "[NOTE 2026-11-07, Story 17.10, Contest Planner ruling (DW-874, option a): until Story 18.4, the web chat shows the digest as a plain-text notice card and the simulated phone shows none.]"

**Acceptance Criteria:**
- Given the golden fixtures, when `OcuTalon.Test.Digest.TelegramText` runs before the move and again after it, then it passes both times with the same expected texts, and `OcuTalon.Test.Channel.TelegramDigest` passes unedited after the move.
- Given a digest Notification on a local install, when Notify routes it, then the web chat shows one plain-text digest card, live and after a reload. The simulated phone gets no digest message, and a paired Telegram chat still gets the same text as before.
- Given the online demo, when the morning tick passes `digest.time`, then no visitor session gets a digest. When the visitor asks for the digest in the chat, the card appears in that visitor's own chat, and REL-2's online run passes with step 7.
- Given the tests that pin the card kinds and the online-demo scheduled rule, when the suite runs on a fresh stack in either order, then every one passes, and each new pin has a `mutation:` line shown red.

- [x] [CI] iris (image) / shard:lane-b: `OcuTalon.Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved` red twice on 596eb1f7 (ci run 42442077870, job iris (image), attempts 1 and 2): "and the production runs every item: TelegramIn (TelegramIn row 0, runtime flag 1, jobs none)" -- https://github.com/jbrandtmse/OcuTalon/actions/runs/42442077870 -- the same shard is green on 7ccdd0bf (31.4's head, without Epic 17). Find and fix (Rule 19, hermeticity) the test that leaves TelegramIn enabled at run time with no job before Heartbeat's check: `Install.Step.Production.NotRunning()` reads the run-time flag, so a production update or restart that stops TelegramIn's job and does not put it back gives exactly that message. Prime suspects are this story's lane-b tests (`Test.Core.WebChatOut`, `Test.Data.Ownership`) and anything they start, swap or update. Reproduce on a fresh lane-B throwaway, fix with a demonstrated mutation, and show the shard green; if the run logs prove this story's tests cannot affect TelegramIn, record that evidence under Design Notes instead of changing code. Resolved without a code change: the evidence that this story's tests and code cannot affect TelegramIn is under Design Notes, "CI red of 2026-11-08"; the cause of the stuck runtime flag itself is not found (DW-639 stays open).

### Review Findings

Code review 2026-11-08 (bmad-code-review, full mode, four layers, review tier full-opus). 23 layer rows, 8 entries kept, all low; no high or medium. Each entry has severity / fix-risk / footprint / spec-status.

- [x] [Review][Patch] `TestOnlineDemoResends` pinned only the attempt counter, which `Resent` saves before it works out the channels, so its "is given its resend" leg held even when nothing was sent [src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls:340] — low / low (three assertions in a test) / in-story / clear. Patched: it now asserts one Notification to WebChatOut and the Sent row's `Channels|Failed` = `web|`; the mutation line is updated (red on run 715, green on 716).
- [x] [Review][Patch] `TestOnlineDemoResends` gave its host no `%SessionId`, so the routing row that `LogRoute` writes for the resend had an empty SessionId and was never removed by `ProcessProbe.Clean`, which deletes TRACESESSION's rows only [src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls:324] — low / low (one line, the pattern of `ProbeCase` and `Compose`) / in-story / clear. Patched: `host.%SessionId = TRACESESSION`.
- [x] [Review][Patch] WebChatOut's `$Select(request.Kind = "digest": "", 1: ..FallbackReasonOf(request))` was dead code: `FallbackReasonOf` reads the top-level slot that the CatalogKey's entry types fallbackReason, and digest Slots are `{parts, lines, rows}`, so the result is "" anyway. That made `TestDigestCard`'s FallbackReason leg unfalsifiable [src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls:74] — low / low (one-line deletion, same output) / in-story / clear (Decided 2's outcome holds). Patched: the line is back to its baseline form, and `TestDigestCard` now pins `FallbackReasonOf`'s digest result.
- [x] [Review][Patch] `TestDigestCard`'s "the lines come last" leg sat under `If $IsObject(row)` with no assertion before it, so a missing row would have skipped it silently [src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls:346] — low / low (one assertion) / in-story / clear. Patched: an `AssertTrue` comes first.
- [x] [Review][Patch] Rule 14 history narration in comments: the `TelegramText` header ("before and after the digest rendering moved out of TelegramOut") and the `Data.Ownership` class doc ("since Story 17.10") [src/ocutalon/cls/OcuTalon/Test/Digest/TelegramText.cls:4, src/ocutalon/cls/OcuTalon/Data/Ownership.cls:40] — low / low (comments) / in-story / clear. Patched: both now state the contract.
- [x] [Review][Patch] Rule 19: the new card-kind pin in `web/scripts/chat-view.test.mjs` had no recorded red [web/scripts/chat-view.test.mjs:342] — low / low / in-story / clear. Closed in-pass: the `noticeOf` drops `digest` mutation was applied, 2 of 62 went red, it was reverted (restored with `cmp`) and the line is written under Verification.
- [x] [Review][Defer] The online-demo visitor's digest card shows the demo instance's own vital signs (uptime, databases full and their names, journal, licence use) [src/ocutalon/cls/OcuTalon/Checks/Coverage.cls:145] — deferred: DW-896, `by-design`. AD-18's coverage rows carry the vital signs, and the Planner's ruling D2 (a) made the online-demo digest visible. The cost part of the claim is false: no `instance` usage arises on the online demo (AD-4, Orders only, session-tagged), so the cost is the visitor's own. Low / med (the Compose parts live in contended `Process.cls`) / in-epic / spec-bound.
- [x] [Review][Defer] `docker/tests/test-sign-in.sh` still names "N1 to N15" in its header (:26) and "N1-N15" in its PASS/FAIL lines (:398, :404), though `notice.spec.ts` now holds N16 [docker/tests/test-sign-in.sh:26] — deferred: DW-897, `wontfix-accepted` with `reopen_if`. The file is outside Epic 17's footprint and is edited by OCT-epic32 (Story 32.5's sign-in split), so it is contended. Low / low / out-of-footprint / clear.

**Rejected** (one line each):
- Blind (triage tags and Auto Run Result disagree; `status: done` with unticked tasks) and Auditor 6: these are build-auto's own spec records, and the fix would edit the spec under review. The frontmatter `status` is machine state.
- Blind and Auditor 4 (the spec's footprint list and the cycle log's `footprint_extensions` disagree): bookkeeping, and the fix edits the spec or the lead's log. The full set is relayed to the lead in the review's Decisions.
- Edge 1 (the live region reads the whole digest): false. It is Decided 3, the same rule as reminder and allowance notices, the UX announcement table does not list the digest, and the text is what the user asked for.
- Edge 3 (empty parts and empty lines give an empty web card): low. It can't be reached, because Compose always pushes the greeting part (`Process.cls:608`), and the fix would add a guard.
- Gap 1 (step 7's phone leg cannot fail): low. The falsifiable pin is `Test.Demo.SimPhoneOut` `TestOtherKindsRecordOnly` (red observed), and the spec's task names the phone check as a greeting-line check; a count-based check would need a live run and could flake on step 5's late notes.
- Gap 3 (the channel argument is unpinned): low. No `digest.*` or `checks.*` key has a `web` text, so "web" and "telegram" can't differ today, and the fix needs a fixture key that doesn't exist. It becomes real when such a key gains a web variant (Story 18.4).
- Gap 4 (step 7 depends on its serial block): false. It uses only its own describe's `beforeAll` visitor, its assertions accept either a watched or an unwatched session, and a step 5 failure is reported as step 5's.
- Gap other and Auditor 1 (N16 sends `catalogKey: 'checks.allPassed'`, not the task's `checks.everythingElsePassed`): low with no harm. A digest's CatalogKey is never rendered, and `checks.allPassed` matches N16's own reserved-sentence part, as AD-28 expects.
- Auditor 2 (`digest` sits in the ChannelMessageId group of `recentNotices`): false. It is Decided 8, pinned by the legacy-row leg with an observed mutation.
- Auditor 3 (several legs have no `mutation:` line): false under Rule 19's one-per-AC scope. Every AC has its demonstrated mutation, and the one new card-kind pin without a red (`chat-view.test.mjs`) was closed above.
- Auditor 5 (the history can't show that the golden ran before the move): false. Runs 702 and 703 are recorded on the slot, and the diff shows the move unchanged except for `channel`, which TelegramOut passes as `TEXTCHANNEL` "telegram".
- Own check (a CI run that crosses `digest.time` now puts a digest card into every open session's chat, so a notice count taken before and after could be off by one): low. The window is one tick a day against a few seconds per counted test, the fix (pinning `digest.time` in CI or filtering the counts) is more than a direct correction, and a flake takes the one-rerun path (compare DW-872).

## Spec Change Log

- 2026-11-08, rework iteration 1 (trigger ci, orchestrator ruling b): re-opened for the one [CI] item under Tasks & Acceptance.

- 2026-11-07, lead spec gate: Q1-Q3 ruled by the Contest Planner (about 20:45Z); AD-18 and AD-33 amended in the spine; N16 placement kept in notice.spec.ts; the Process.cls class comment :7-8 moved into scope (the plan's deferred item withdrawn); status `blocked` -> `ready-for-dev`.

## Review Triage Log

### 2026-11-07 — Review pass
- verdicts: 24 rows (23 findings of the four layers, related ones grouped on a row, and one check of my own) — high 0, medium 1, low 19, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1 / Edge 3 / Gap 2: step 7's phone check passes at once and cannot see a later note — real, but the claim "the simulated phone shows no digest" has its falsifiable pin in `Test.Demo.SimPhoneOut` `TestOtherKindsRecordOnly` (red under `digest` in SimPhone CARDKINDS, observed). Patched anyway as a two-way door: step 7 now waits 3 s and also matches the catalog's own wording (`I checked `, `Everything else I checked passed`, `Yesterday's cost`). That step 7 stays green under that mutation is recorded in Verification.
  - `[low]` `[reject]` Blind 2: step 7 sits in the describe titled "steps 2 to 5" — the spec and the lead place it in that serial block on purpose; the report check keys on the `step 7:` title.
  - `[low]` `[reject]` Blind 3: `DueFor` can error before the online-demo short-circuit — the same ordering as before the story (a bad TickAt returned that error before the session loop too); not caused by the change.
  - `[false]` `[reject]` Blind 4: `TestOnlineDemoSkipped` leaves `onlineDemo` 1 — `OnBeforeOneTest` resets it to "" for the next test and `OnAfterAllTests` restores the class's own start value.
  - `[low]` `[reject]` Blind 5: docs not updated — the spec says the `Telegram.Out` class comment stays true as it is; the spine's AD-18/AD-33 wording is the lead's and is already amended; `TestRecentNotices` doc was updated (:826-829 holds the digest sentence).
  - `[low]` `[reject]` Blind 6: Auto Run Result says ready-for-dev — written at finalize.
  - `[low]` `[reject]` Blind 7: golden "not clean" — the corrected lines were fixture errors in the new test, fixed before any source change against the unchanged class (Decided 9); the golden passed identically before and after the move.
  - `[low]` `[reject]` Blind 8: `TestOneHelper` reads source text — the spec asks for a structural test from `%Dictionary.CompiledMethod`; the behavioural sharing is pinned by `TelegramText` and `TestDigestCard`; the 32000 limit is above the method's size.
  - `[low]` `[reject]` Blind 9: rigid regex in `approval-sources.test.mjs` — the file's other assertions are the same kind; no named harm.
  - `[low]` `[reject]` Blind 10: web digest has no check rows and no test asserts it — by design (Story 18.4); `Slots.rows` is not read by the helper.
  - `[low]` `[reject]` Edge 1: empty parts and empty lines make an empty card — Compose always writes the greeting part; unreachable from the product, and Telegram has the same behaviour for the same Slots.
  - `[false]` `[reject]` Edge 2: a stored digest from before `parts`/`lines` reaches WebChatOut by Resends — the Telegram branch has required the same Slots since Story 17.6, so no such stored digest exists.
  - `[low]` `[reject]` Edge 4: a Compose queued before onlineDemo was switched on still goes out — the switch is a deploy-time setting of the online host; theoretical.
  - `[medium]` `[patch]` Gap 1: `Resends` on the online demo is no longer pinned (Decided 4) — patched: `TestOnlineDemoResends`, mutation `If online Quit $$$OK` observed red then green.
  - `[low]` `[reject]` Gap 3 (missing `mutation:` lines for the render-error legs, the Telegram consumption leg, the row-field leg, the local-install leg and step 7's line patterns) — the spec's list of required mutations is complete and each was observed; these legs are covered by assertions that fail on the obvious break (the unknown-key and no-lines legs fail if sc is ignored, because a row would be recorded); wontfix-accepted, reopen_if a render-error leg is seen to stay green under a mutation.
  - `[low]` `[reject]` Gap 4: the channel argument is unpinned — no digest or checks key has a `web` text (Code Map), so the texts for "web" and "telegram" cannot differ; the channel parameter is the same TEXTCHANNEL that the pinned card kinds use.
  - `[low]` `[reject]` Gap 5: the `$Select` for FallbackReason is unreachable by the fixtures — it is Decided 2 and costs one expression; a digest key has no `fallbackReason` slot.
  - `[low]` `[reject]` Gap 6: step 7 depends on its serial block and N16 on the shared notice user — by design (same visitor; N16 uses a unique marker and its own card lookup).
  - `[low]` `[patch]` Own check: `web/scripts/approval-sources.test.mjs` pinned the old `.request .text` rule — updated to the shared rule; `npm --prefix web test` 1537 passed. And `Channel/DigestText.cls` header named "Lane A moved it out of" (history in a comment) — replaced by the contract.
  - `[false]` `[reject]` Intent audit: reading F (legacy rows) — a choice recorded as Decided 8, not a divergence.
  - `[low]` `[reject]` Intent audit: the Ticked doc comment sits outside the method body — the spec names "Ticked (doc :197 ...)" as in scope.
  - `[low]` `[reject]` Intent audit: the golden fixtures were reconciled against the unchanged class — see Blind 7.
  - `[false]` `[reject]` Intent audit: the Act-chip assertion lives in `sendThroughComposer` — step 7 calls it with the mock expectation, as the spec says.
  - `[low]` `[reject]` Intent audit: the data-level and DOM-level line-break checks are split between `TestDigestCard` and N16/step 7 — matches the matrix rows.

## Design Notes

**Governing ADs (Rule 6):**
- AD-32: the notification contract. Producers never render, and the `*Out` operations render every `{key, slots}` through `Catalog.Render`.
- AD-14: Notify routing, and the digest's own channels.
- AD-12: live events and the snapshot.
- AD-33: one publisher of `notification` (WebChatOut), and lane ownership.
- AD-29: the lanes.
- AD-28: the all-clear only from code. The CatalogKey is unchanged, and the card only renders.
- AD-18: when a digest is due.
- AD-25: the online demo polls.
- AD-4: the card goes to the session's own stream.
- AD-22: the CI mock.
- AD-30: the summary goes through Decide, only when something was saved.

Conflicts: resolved by the Contest Planner's rulings of 2026-11-07 about 20:45Z (see Rulings below). AD-32: the helper is the shared rendering code of the `*Out` operations, and only they call it. I read that as consistent with "only `*Out` operations render". [Lead, spec gate: AD-32's Rule is met as written (the helper is the `*Out` operations' own rendering code, called only by them); no AD-32 change is made, so no further AD amendment is needed.]

**Ledger (Rule 17):** DW-874 is addressed by the WebChatOut, Ownership, web and N16 tasks (the web card), by the `Ticked`/`TestOnlineDemoSkipped` tasks (the morning run), and by step 7 with its mock scenarios (the online card). Its simulated-phone half is out by the Planner's ruling of 2026-11-07 (option a): `SimPhone/Out.cls` CARDKINDS stays.

**Integration ACs (Rule 1).** Consumer TelegramOut reads `DigestText` and sends the byte-identical text (`TelegramText`, the Telegram golden row). Consumer WebChatOut reads it and records and publishes the card (`TestDigestCard`, N16, step 7).
- Consumed-by:
  - TelegramOut (this story: the Telegram digest message);
  - WebChatOut (this story: the web digest card);
  - Story 18.4 (Lane B: the full web digest card and the phone copy, which can call `Text(slots, "phone")`).
- Consumes:
  - Story 17.6's digest Slots (AD-32);
  - Story 0.9's `Catalog.Render`;
  - Story 2.7's `Delivery.Record`, `RecentNotices` and the notice card;
  - Story 17.6's `SendDigest` tool.

**Extend, don't copy (Rule 2).** `OcuTalon.Channel.DigestText` is a MOVE of `TelegramOut`'s `DigestText`/`Pieces`/`Piece`/`AFTERLINES`. `TestOneHelper` pins that no copy is left. WebChatOut's digest branch reuses its card path (`Delivery.Record`, `Announce`). The card's pre-line reuses the request rule's selector, and step 7 reuses `sendThroughComposer`.

**PUBLIC TEXT (for the Planner):** none. The card is the catalog text alone, and its icon is `aria-hidden`. The mock reply text is CI-only. The EXPERIENCE note is internal.

**Rulings (Contest Planner under the owner's delegation, 2026-11-07 about 20:45Z, relayed by the orchestrator):**
- Q1, AD-18: APPROVED as worded. The lead wrote the clause into AD-18's Rule with the marker "[AMENDED 2026-11-07, Story 17.10, Contest Planner ruling under the owner's delegation (DW-874, option a)]": on the online demo (`Data.Public.Settings` `onlineDemo` on) no session is due for the scheduled digest; a visitor gets a digest only by asking (`SendDigest`). `TestEndedOnlineDemo` becomes `TestOnlineDemoSkipped`.
- Q2, AD-33: APPROVED. The lead added the exception bullet "Story 17.10 changes the Lane B files its spec names, under the Contest Planner's ruling of 2026-11-07 (DW-874); the ownership tables don't change" with the same marker. `docker/tests/test-online-demo-path.sh` is reported under `footprint_extensions:`.
- Q3: keep N16 in `web/e2e/chat/notice.spec.ts` as ruled (option a). Story 32.5's sign-in split (OCT-epic32) merges to feature; the runner integrates over it before the story's CI push.

**Decided in-stage:**
1. The helper lives in `OcuTalon.Channel`, the spine's channel edge, whose job is "rendering outbound text". It is a class of class methods. Lane A owns it (it moved from TelegramOut), and WebChatOut reads it. No item, table or event is added, so the ownership tables are unchanged.
2. The digest joins `CARDKINDS` with its own text branch. Its row keeps FallbackReason "", because the key's slots are checks slots and the web card has no strip.
3. The web card has class `digest`, the UX's digest icon `inbox`, the default accent bar and info ink, and pre-line text. The teal bar and the rows are Story 18.4's. The chat announcement stays as it is for non-tell-now notices (the whole text).
4. The online-demo rule is "no scheduled Compose on the online demo". `Resends` still runs, because it resends a digest the visitor asked for and makes no model call.
5. The online "one step" is its own case, `step 7`, in the serial block (the same visitor, no extra sign-in). The unit's report check moves to eight passed cases and 11 in all. This is a footprint extension: `docker/tests/test-online-demo-path.sh`, which no contended epic owns and which is not a frozen release tool.
6. The golden test is in the Digest area (`shards-2`, about 28 min), not in Channel (`shards-4`, up to 35 min). It drives `OnNotification` through a probe, so it passes before and after the move.
7. [Lead, spec gate 2026-11-07] Process.cls's class comment :7-8 is updated in this story after all: it is a separate hunk from Epic 12's :32 edit (24 lines apart), and the lead proves a clean `git merge-file` against `origin/OCT-epic12` before the commit. The plan's `deferred:` item is withdrawn.
8. [Implement] The `recentNotices` query lists `digest` in the `(approval, result, digest) AND ChannelMessageId IS NOT NULL` group, not in the unconditional Kind list. A digest row recorded before this story has no text and no ChannelMessageId, so it stays out of the snapshot instead of reloading as an empty card. A new `TestRecentNotices` leg pins it (a legacy row is not a card).
9. [Implement] The golden fixtures' first run, against the unchanged `Out.cls`, was 4 of 6: two fixture lines had "at" where the catalog renders "on" before a dated time after ", ". The fixture was corrected to the catalog's own rule before any source change, and `Out.cls` was untouched; the texts were then identical before and after the move.
10. [Implement] `web/scripts/approval-sources.test.mjs` pinned the exact `.request .text` rule; it now pins the shared `.request .text, .digest .text` rule. `web/scripts/chat-view.test.mjs` no longer lists `digest` as a kind that renders nothing and gains a digest case.
11. [Review] `Test.Digest.Due.TestOnlineDemoResends` is added: on the online demo the tick still gives a stored digest that missed a channel its resend (Decided 4), which no test pinned.

**CI red of 2026-11-08 (rework 1: ci run 42442077870, head 596eb1f7, job iris (image), unit shard:lane-b, `Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved`: "TelegramIn (TelegramIn row 0, runtime flag 1, jobs none)").** Read from the three job logs (attempt 1 on runner ocutalon-ci-12, attempt 2 on ocutalon-ci-7, and the green run 42441528510 on 7ccdd0bf, runner ocutalon-ci-19) and from throwaways of tag `e17s10r` on the merged tree (HEAD c390d57f). No code or test was changed. DW-639's cause is not found here; what follows shows that Epic 17's diff is not it.
- Class order: the three logs list the same 111 `CLASS` lines in the same order (`cmp` of the extracted names: identical; the lead's "109" was 111). Heartbeat is the 81st, after Contract (4), Core (44), Data (13), Demo (12), Live (4) and Msg (3). `Test.Core.WebChatOut` is the 48th and `Test.Data.Ownership` the 53rd in all three. The per-class seconds agree within 8 s everywhere except Heartbeat (92.6 s and 129.2 s red, 87.6 s green); the class totals are 707.7 s, 758.1 s and 723.2 s.
- Other differences, none of them a lane-b order or tree difference: the runners (three different ones, so not one runner's fault); the web port of the browser units; the Park line of the lane-b stack ("PARK done" 5 s and 6 s red, 2 s green; a throwaway of mine parks in 2 s, and a park is the wait for TelegramIn's 5 s long poll to end, so the duration is not itself a cause (inference)); both red runs and the green one run `live:storage-roundtrip` and `live:build-inputs` first and pass them. No other line differs in kind.
- This story's lane-b tests cannot touch the production: `Test.Core.WebChatOut` and `Test.Data.Ownership` hold no call of `UpdateProduction`, `EnableConfigItem`, `UseItemClass`, `PutDefault`, `WriteDefault`, `RestartProduction`, `TempStopConfigItem`, `Production.Start` or `RunnerFixture` (grep count 0 in both files). The product code of the story that runs in the production (`WebChat.Out`, `DigestText`, `Telegram.Out`, `Data.Ownership`, `Digest.Process`) has no call of those methods either; the only product code that restarts or updates the production is `Install.Step.Production.Start`.
- What TelegramIn does in a full run on the merged tree: a watcher job (a throwaway test class, not committed) logged the runtime flag, the Enabled row and the TelegramIn jobs every 0.2 s through `lane-b@Contract,Core,Data,Demo,Live,Msg,Schedule` (Heartbeat passed, 104 s). TelegramIn changes state once: flag 1 and row 1 with a job at 84.4 s, row 0 at 100.0 s, flag 0 and no job at 104.6 s, all in `Test.Core.PersonaAnswers` (the only lane-b class that enables it, through `LiveCase`, and not changed by Epic 17). It never changes in `WebChatOut` or `Data.Ownership`, and is flag 0, row 0, no job from 104.6 s to the end. `PersonaAnswers` alone also ends with flag 0, row 0 and no job for 15 s afterwards.
- How the state in the red can arise (measured): a state with row 0, flag 1 and no job was made on purpose (`EnableConfigItem(item, 0, 0)`, then the job stopped). `NotRunning()` then names TelegramIn, and the next `UpdateProduction` of any item (the Heartbeat class's own `UseItemClass` swap of Checks) registers TelegramIn again and clears the flag. So at the failing assertion the state was not a leftover that Heartbeat's own set-up update repairs; either TelegramIn was registered with flag 1 by the update itself, or its registered checksum matched the row-0 value while the flag stayed 1 (inference: `Ens.Director.getProductionItems` reads the Enabled row for the flag at one point and for the checksum at a later one, so a write between the two reads would leave exactly that state; 720 `UpdateProduction` calls from a second job during 12 Enable/Disable cycles of TelegramIn did not produce it).
- Not reproduced: Heartbeat alone (the lead, 87 s), `lane-b@Core,Schedule` (51 classes), `lane-b@Contract,Data,Demo,Live,Msg,Schedule` (43), the full `lane-b` (111/111, 804 s), my two shards of `lane-b@Contract,Core,Data,Demo,Live,Msg,Schedule` (Heartbeat green both times), and my Enable/Disable probes (8 phases of the long poll, then 12 cycles under concurrent updates: flag 0 every time). Unreproduced here does not mean absent in CI.
- The class is older than this story: DW-639's ledger lists the same assertion red on 11-03 (e75b90bc), on Epic 33's Story 33.2 locally (2 of 4 runs of `lane-b` part 2/2, which has no `PersonaAnswers` at all), on Epic 34 twice, and on this branch's heads of 17.5, 17.6 and 17.7, each before 17.10 existed. Its diagnostics (Story 39.10) now name the item for the first time: TelegramIn, row 0, runtime flag 1, jobs none, which is the stuck-flag state that `RunnerFixture.NotRunningNow` (Story 12.9, DW-591) already skips in the restart checks and `Install.Step.Production.NotRunning` (which `Heartbeat` reads raw) does not.
- Not done, by the lead's rules: no change to `Install.Step.Production.NotRunning()`, `Test.Schedule.Heartbeat` or any other test (a test-side fix cannot be shown red without the cause, and the pin must not be weakened by a row-aware read); no wait or timeout. Proposal for the owner of Story 39.10 or the burn-down: decide whether `Heartbeat` (lines 180 and 612) reads the production the way the restarts do (`NotRunningNow`), or whether the stuck flag is fixed where it arises (`LiveCase`/`BotApi.Park` re-registering TelegramIn after a disable); either needs the cause, which a loop of the full `lane-b` shard on a loaded runner with the watcher class would give.

**Footprint (Rule 11).**
- Checked with `git diff --name-only HEAD...origin/OCT-epic<N>` for N = 12, 11 and 39 on 2026-11-07. Epic 12 touches `Digest/Process.cls` (hunks :32, :596, :668, :692 and :872, none in `Ticked`) and `Test/Channel/TelegramDigest.cls`, and not `Channel/Telegram/Out.cls`.
- Footprint extensions: `docker/tests/test-online-demo-path.sh`, `src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls` (Epic 17's own) and `EXPERIENCE.md` (a marker).

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`.
- Tags: `e17s10iw` (warm) and `e17s10i` (fresh). QA and review use their own tags.
- Run one call at a time, in the foreground, with `timeout: 600000`.
- Run `ci/warm.sh down` at the stage's end, also after a failure.
- Compile checks run on `ocutalon-slot-b` only (`iris_doc_load`, `server` `ocutalon-slot-b`, `namespace` `OCUTALON`, after `iris_server_info` shows build 154 and port 1991). Never use another instance.
- Run `ci/iris.sh build` once before any browser unit (Rule 21: the bundle after `web/` changes).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s10iw ci/warm.sh up`. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s10iw ci/iris.sh class <C>`, one class per call, for `OcuTalon.Test.Digest.TelegramText`, `OcuTalon.Test.Core.WebChatOut`, `OcuTalon.Test.Data.Ownership` and `OcuTalon.Test.Digest.Due`. Expected: `CLASS <C> passed` for each.
- (once) The same, for classes that must stay green unedited: `OcuTalon.Test.Channel.TelegramDigest`, `TelegramOut` and `TelegramApproval`, `OcuTalon.Test.Digest.DueEdges`, `Compose`, `Send`, `Tool` and `AllClear`, and `OcuTalon.Test.Core.RoutingProduction`. A red in `TelegramDigest` is `## Clarification Needed`, never an edit.
- (once) `bash ci/checks.sh`. Expected: every block passes (`test-class-rules`, `test-boundaries`, `test-ci-config`, `test-ci-changes` included).
- (once) `bash docker/tests/test-mock.sh` and `npm --prefix web test`, one per call. Expected: they pass (the new B scenarios load, no prompt contains another).
- (once) `npm --prefix web run build`, then `npm --prefix web run lint`. Expected: both pass (`payloads.mjs --check` unchanged).
- (loop) `ci/iris.sh live sign-in --part k/3`, for the part whose SPEC lines list `chat/notice.spec.ts`. Expected: it passes, N16 included.
- (once) The other two parts of `ci/iris.sh live sign-in --part k/3`, one per call. Expected: they pass.
- (once) `OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live online-demo-path`. Expected: the report holds the eight passed cases, step 7 included, and the three skipped ones. The load phase passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s10i ci/iris.sh shard lane-a@Digest`, then `shard lane-b@Core`, then `shard lane-b@Data`, then `shard lane-a@Channel`, each in its own call. Use `--part k/n` when a call nears 8 minutes. Then `ci/iris.sh teardown`. Expected: every class passes.

**Golden runs (the implement stage records both):**
- before the move: `OcuTalon.Test.Digest.TelegramText` (6 tests: TestFullDigest, TestNoAfterLines, TestEmptyLines, TestEmptyParts, TestUnknownKey, TestNoLines) green against the UNCHANGED `Channel/Telegram/Out.cls` (identical to the server copy: "up-to-date" on load), on `ocutalon-slot-b` (iris_execute_tests, 6 of 6 passed, run index 702) and on the warm stack: `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s10iw ci/iris.sh class OcuTalon.Test.Digest.TelegramText` -> `CLASS ... passed`. (The first run was 4 of 6: two fixture lines had "at" where the catalog renders "on" before a dated time after ", "; the expected text was fixed to the catalog's own rule, and Out.cls was not touched.)
- after the move: the same six tests with the same expected texts, green on `ocutalon-slot-b` (iris_execute_tests, 6 of 6, run index 703) and on the warm stack (`CLASS OcuTalon.Test.Digest.TelegramText passed`), with `Channel/DigestText.cls` new and `Channel/Telegram/Out.cls` calling `Text(request.Slots, ..#TEXTCHANNEL, .sc)`. `TestOneHelper` was added after the move and is recorded with the mutations below.

**Shared surfaces:**
- WebChatOut `CARDKINDS`: `Test.Core.WebChatOut` :298-299 and `Test.Data.Ownership` :853-859.
- The `recentNotices` query's kinds: `Test.Data.Ownership` `TestRecentNotices` and the snapshot's chat.
- The web `NoticeKind`/`noticeOf` kinds: `notice.spec.ts`. N3's digest is an item outcome and is unaffected.
- The online demo's scheduled digests: `Test.Digest.Due`.
- The online-demo-path report's case set: `test-online-demo-path.sh`.
- The B mock prompts: `ci/mock` scenario checks.
- TelegramOut's method set: `TestOneHelper`.

Every test added or changed passes on a fresh environment, in either order.

**Where the new tests run (CI):**
- `TelegramText`: lane-a@rest, group `shards-2` (about 28 min).
- `TestDigestCard` and the Ownership leg: lane-b, group `image` (28-31 min).
- `TestOnlineDemoSkipped`: lane-a@rest, group `shards-2`.
- step 7: live:online-demo-path, group `image` (+ about 30-60 s, inference).
- N16: live:sign-in, group `browser` (ruled Q3 (a); Story 32.5's sign-in split rebalances the group).

**Mutations to demonstrate (Rule 19).** Apply each one, observe red, and restore the file byte for byte:
- the helper appends the lines after the last part: `TelegramText` (a) is red;
- the helper drops the LF between pieces: `TelegramText` (a) and `TestDigestCard` are red;
- a private copy of `Piece` is put back in WebChatOut: `TestOneHelper` is red;
- `digest` is removed from `CARDKINDS`: `TestDigestCard`, the Ownership digest leg, N16 and step 7 are red;
- WebChatOut renders `CatalogKey` for a digest (no branch): the `TestDigestCard` text is red;
- `'digest'` is removed from the `recentNotices` query: the Ownership leg and N16's reload leg are red;
- `Ticked`'s old line is put back (`If online && (ResumeHash = "") Continue` only): `TestOnlineDemoSkipped` (morning) is red;
- `Requested` queues nothing on the online demo: `TestOnlineDemoSkipped` (asked) is red;
- `noticeOf` drops `digest`: N16 and step 7 are red;
- the digest card loses `pre-line`: N16's lines leg is red;
- the digest icon falls back to `bell`: N16's icon leg is red.

**Mutations observed (implement stage; each applied, observed red, and restored byte for byte with `cmp` against a backup):**
- mutation: the helper appends the lines after the last part (`If 'done && $ListFind` -> `If 0 && $ListFind` in `DigestText.Text`): `TelegramText` red (`TestFullDigest`), warm stack.
- mutation: the helper drops the LF between pieces (`1: $Char(10))_..Piece(` -> `1: "")_..Piece(`, both places): `TelegramText` red (`TestEmptyLines`, `TestEmptyParts`, `TestFullDigest`, `TestNoAfterLines`) and `Test.Core.WebChatOut` red (`TestDigestCard`).
- mutation: a private `Piece` method put back in `WebChat/Out.cls`: `TelegramText` red (`TestOneHelper`).
- mutation: `digest` removed from `CARDKINDS`: `Test.Core.WebChatOut` red (`TestDigestCard`, `TestOtherKindsRecordOnly`), `Test.Data.Ownership` red (`TestRecentNotices`), N16 red (`live sign-in --part 1/3`: 1 failed, 119 passed), step 7 red (`live online-demo-path -g "steps 2 to 5"`: step 7 failed, 4 passed).
- mutation: `WebChatOut` renders the CatalogKey for a digest (`If request.Kind = "digest" {` -> `If 0 {`): `Test.Core.WebChatOut` red (`TestDigestCard`).
- mutation: `'digest'` removed from the `recentNotices` query: `Test.Data.Ownership` red (`TestRecentNotices`) and N16 red at "after the reload: one card".
- mutation (added with the legacy-row leg): `'digest'` moved to the unconditional Kind list of the query (a digest row with no ChannelMessageId becomes a card): `Test.Data.Ownership` `TestRecentNotices` red (checked on `ocutalon-slot-b`; the first version of the leg compared Refs only and passed, so it now compares the count too).
- mutation: `Ticked`'s old line put back (`If online && (ResumeHash = "") Continue`, with the column in the SELECT): `Test.Digest.Due` red (`TestOnlineDemoSkipped`).
- mutation: `Requested` queues nothing on the online demo: `Test.Digest.Due` red (`TestOnlineDemoSkipped`).
- mutation: `noticeOf` drops `digest`: N16 red (card never appears), step 7 red, and `web/scripts/chat-view.test.mjs` red (2 of 62: "shows a tell now, a reminder, an allowance and a digest card ..." and "shows a digest notice (Story 17.10) ..."; code review, restored with `cmp`, 62 of 62 after).
- mutation: the digest card loses `pre-line` (`.request .text,` + `.digest .text` -> `.request .text`): N16 red (the lines leg: expected 6 lines, received 1).
- mutation: the digest icon falls back to `bell` (the `inbox` branch removed): N16 red at "live: the icon is the inbox".

- mutation: `If online Quit ..Resends()` -> `If online Quit $$$OK` in `Ticked`: `Test.Digest.Due` red (`TestOnlineDemoResends`: the attempt is not counted, no Notification is sent again, and the Sent row's Channels and Failed are unchanged; re-demonstrated in code review against the strengthened test on `ocutalon-slot-b`, run 715), green again after the revert (run 716), `Process.cls` restored with `cmp`.
- mutation: `digest` added to `Channel/SimPhone/Out.cls` `CARDKINDS` (a temporary change, restored byte for byte): `Test.Demo.SimPhoneOut` red (`TestOtherKindsRecordOnly`, the digest leg: three assertions), green again after the revert. This is the falsifiable pin of "the simulated phone shows no digest". Step 7's phone leg (no phone note with the digest's wording, after a 3 s settle) stayed green under the same mutation in `live online-demo-path -g "steps 2 to 5"`, so it is a browser-level confirmation only and not the pin.

**QA pass (QA): gap check and mutations.** No test file was added or changed: every acceptance criterion and matrix row already had a pinning test. The render-error legs of the web consumer (`TestDigestCard`) and the Telegram consumption leg (`TelegramText`) had no observed red, so these were demonstrated on `ocutalon-slot-b` (each from a backup in the QA scratch folder, restored with `cmp`, the tree unchanged afterwards):
- mutation (QA): `Set sc = $$$OK` after the digest `Text` call in `WebChat/Out.cls` (a render error is ignored) -> `Test.Core.WebChatOut` red in `TestDigestCard` only (the four render-error legs, "records no row" and "publishes no event"); `TestRenderErrorRecordsNothing` stayed green, so the digest leg is the one that pins it.
- mutation (QA): `Set sc = $$$OK` after the `Text` call in `Telegram/Out.cls` (a render error is ignored) -> `Test.Digest.TelegramText` red (`TestUnknownKey`, `TestNoLines`).
- mutation (QA): `If request.Kind = "digest" {` -> `If 0 {` in `Telegram/Out.cls` (TelegramOut stops consuming the helper) -> `Test.Digest.TelegramText` red (6 of 7: every golden test and the error legs).
- After the three restores, `Test.Digest.TelegramText` (7 of 7) and `Test.Core.WebChatOut` (14 of 14) are green on `ocutalon-slot-b`.

**Green runs after the change (implement stage and review pass, last patch included):**
- Warm stack `e17s10iw`: `TelegramText`, `Test.Core.WebChatOut`, `Test.Data.Ownership`, `Test.Digest.Due` (with `TestOnlineDemoResends`), and, unedited, `Test.Channel.TelegramDigest`, `TelegramOut`, `TelegramApproval`, `Test.Digest.DueEdges`, `Compose`, `Send`, `Tool`, `AllClear` and `Test.Core.RoutingProduction` all passed.
- Fresh stack `e17s10i`: `shard lane-a@Digest` (21 classes), `lane-b@Core` (41), `lane-b@Data` (13) and `lane-a@Channel` (14) passed.
- Live: `live sign-in --part 1/3` (holds `chat/notice.spec.ts`, N16 included) 120 passed, `--part 2/3` 134 passed, `--part 3/3` 86 passed; `live online-demo-path` (after the last patch): the report holds the eight passed cases (step 7 included) and the three skipped ones, the load phase passed.
- `bash ci/checks.sh` all scripts passed (before the review patches; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` ran again after them); `bash docker/tests/test-mock.sh` 133 passed; `npm --prefix web test` 1537 passed; `npm --prefix web run build` and `run lint` passed; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` passed.
- Code review (after its patches, on `ocutalon-slot-b`): `Test.Digest.Due` 11 of 11 (run 712), `Test.Core.WebChatOut` 14 of 14 (run 713), `Test.Digest.TelegramText` 7 of 7 (run 714); `docker/tests/test-class-rules.sh` and `test-boundaries.sh` passed; `web/scripts/chat-view.test.mjs` 62 of 62.

## Auto Run Result

Status: done
Blocking condition: none

**Rework 1 (CI red of 2026-11-08, this pass only).** The one `[CI]` item is checked with evidence and no code change: the Design Notes paragraph "CI red of 2026-11-08" holds the log comparison, the full-run watcher of TelegramIn and the probes. The red is DW-639 (a stuck runtime flag of TelegramIn after its Enabled row went to 0), whose cause is not found; Epic 17's diff cannot reach TelegramIn. Files changed: this spec only (baseline_revision moved to c390d57f). Review: the pass changes no code or test, so the four layers had nothing to read and were not launched; follow-up review recommended: false. Verification: runs of tag `e17s10r` on fresh lane-B throwaways (two shards through Heartbeat and four class probes), all torn down; the temporary test classes were deleted before the commit. Residual risk: CI may be red again on the same flake until DW-639's cause is fixed.

**Summary.** The digest has one shared renderer, `OcuTalon.Channel.DigestText` (a move of TelegramOut's code, with the channel as a parameter). `WebChatOut` records and publishes a plain-text digest card with it, the `recentNotices` query and the web chat show it, and on the online demo the scheduled run queues no Compose. Telegram's text is byte-identical, pinned by the new golden test run green before and after the move.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` (new): the helper.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`: the four members removed, one call site changed.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`: `digest` in `CARDKINDS`, the digest text branch, docs.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `recentNotices` includes digest rows that have a ChannelMessageId; docs.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls`: `Ticked` queues nothing on the online demo; the class comment's due-rule sentence.
- `src/ocutalon/cls/OcuTalon/Test/Digest/TelegramOutProbe.cls`, `TelegramText.cls` (new): the golden test and `TestOneHelper`.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls`, `Test/Data/Ownership.cls`, `Test/Digest/Due.cls`: `TestDigestCard`, the digest and legacy-row legs, `TestOnlineDemoSkipped` and `TestOnlineDemoResends`.
- `web/src/app/chat/chat-view.ts`, `notice-card.ts`: the digest notice kind, the `inbox` icon, pre-line text.
- `web/scripts/chat-view.test.mjs`, `web/scripts/approval-sources.test.mjs`: unit pins for the new kind and the shared rule.
- `web/e2e/chat/notice.spec.ts` (N16), `web/e2e-online/demo-path/demo-path.spec.ts` (step 7), `docker/tests/test-online-demo-path.sh` (eight passed, 11 in all).
- `ci/mock/scenarios/B/digest-send-now-chat.json`, `digest-send-now-triage.json` (new).
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: the marker.

**Review.** Patches applied: 2 (one medium: `TestOnlineDemoResends`; one low: the step 7 phone check, plus the web unit pin and a helper comment I found myself). Deferred: none. Rejected: every other row of the triage log, each with its reason there. Patched counts by verdict: high 0, medium 1, low 1. Follow-up review recommended: false.

**Verification.** See Verification (golden runs before and after the move, the mutations observed, and the green runs): the four new or changed classes and the unedited classes green warm; four fresh shards green; live sign-in parts 1/3, 2/3 and 3/3 and live online-demo-path green; `ci/checks.sh`, `test-mock.sh`, `npm test`, build, lint and `test-boundaries.sh` green. Warm and fresh throwaways of this run were torn down.

**Residual risks.**
- Step 7's phone leg is a browser-level confirmation only; the falsifiable pin of "no digest on the simulated phone" is `Test.Demo.SimPhoneOut` `TestOtherKindsRecordOnly`.
- A local install with Telegram paired gets the digest in both places (accepted in the intent).
- `docker/tests/test-sign-in.sh` still says "N1 to N15" in a header comment; it is not in this story's file list.
- CI time: the `browser` group was 33-39 min on the measured runs, and N16 and step 7 add seconds (inference); Story 32.5's split rebalances it.
