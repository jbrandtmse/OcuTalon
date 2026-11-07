---
title: 'Story 17.10: The digest shows in the web chat, and the online demo''s digest is visible'
type: 'bugfix'
created: '2026-11-07'
status: 'done'
baseline_revision: '686baec753690d78b69dd1dd616404947856dce1'
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

## Spec Change Log

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
- mutation: `noticeOf` drops `digest`: N16 red (card never appears) and step 7 red.
- mutation: the digest card loses `pre-line` (`.request .text,` + `.digest .text` -> `.request .text`): N16 red (the lines leg: expected 6 lines, received 1).
- mutation: the digest icon falls back to `bell` (the `inbox` branch removed): N16 red at "live: the icon is the inbox".

- mutation: `If online Quit ..Resends()` -> `If online Quit $$$OK` in `Ticked`: `Test.Digest.Due` red (`TestOnlineDemoResends`: the attempt is not counted); green again on the same stack after the revert (review pass).
- mutation: `digest` added to `Channel/SimPhone/Out.cls` `CARDKINDS` (a temporary change, restored byte for byte): `Test.Demo.SimPhoneOut` red (`TestOtherKindsRecordOnly`, the digest leg: three assertions), green again after the revert. This is the falsifiable pin of "the simulated phone shows no digest". Step 7's phone leg (no phone note with the digest's wording, after a 3 s settle) stayed green under the same mutation in `live online-demo-path -g "steps 2 to 5"`, so it is a browser-level confirmation only and not the pin.

**Green runs after the change (implement stage and review pass, last patch included):**
- Warm stack `e17s10iw`: `TelegramText`, `Test.Core.WebChatOut`, `Test.Data.Ownership`, `Test.Digest.Due` (with `TestOnlineDemoResends`), and, unedited, `Test.Channel.TelegramDigest`, `TelegramOut`, `TelegramApproval`, `Test.Digest.DueEdges`, `Compose`, `Send`, `Tool`, `AllClear` and `Test.Core.RoutingProduction` all passed.
- Fresh stack `e17s10i`: `shard lane-a@Digest` (21 classes), `lane-b@Core` (41), `lane-b@Data` (13) and `lane-a@Channel` (14) passed.
- Live: `live sign-in --part 1/3` (holds `chat/notice.spec.ts`, N16 included) 120 passed, `--part 2/3` 134 passed, `--part 3/3` 86 passed; `live online-demo-path` (after the last patch): the report holds the eight passed cases (step 7 included) and the three skipped ones, the load phase passed.
- `bash ci/checks.sh` all scripts passed (before the review patches; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` ran again after them); `bash docker/tests/test-mock.sh` 133 passed; `npm --prefix web test` 1537 passed; `npm --prefix web run build` and `run lint` passed; `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` passed.

## Auto Run Result

Status: done
Blocking condition: none

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
