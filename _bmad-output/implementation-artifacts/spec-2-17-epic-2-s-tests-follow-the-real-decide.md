---
title: 'Story 2.17: Epic 2''s tests follow the real Decide'
type: 'bugfix'
created: '2026-10-25'
status: 'done'
baseline_revision: 'f1909ae999ffeda3f3c5e3fd8d8bcfdfdafda04c'
baseline_commit: 'f1909ae999ffeda3f3c5e3fd8d8bcfdfdafda04c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The branch now carries Epic 1's real `Decide`, merged in 39e8042 with the fixes of dc776e9. Epic 2's production and live tests still assert what Epic 0's stub answered: the reason `unusable`, with no decision kept. So three units are red on the merged tree: `shard:lane-b`, row 20 of `live:production-restart`, and `live:sign-in`, where 14 cases failed and 78 never ran. On a stack with no model key, the real `Decide` answers `no_key`. It also records one fallback Decision row per request and publishes a `decision` event for each.

**Approach:**
- Every stale assertion changes to the outcome Task 0 measured on the merged tree: the reply text, the reason, the decision refs and rows, the events, the card and the strip.
- Every Epic 2 acceptance criterion stays pinned by a test that can fail, with one demonstrated mutation per changed pin.
- The comments that still call `Decide` a stub are corrected.
- `live:sign-in` stays inside its deadline.
- No product code changes: Task 0 found no integration defect in Epic 2's code.

## Boundaries & Constraints

**Always:**
- **The expected values are the measured ones** (Task 0 on the merged tree `7747e5e`, keyless throwaway). For a user's message, through the production:
  - The Turn ends `done`, Attempt 1, Tainted 0, with `conversation.turnFallback|no_key|` (key, reason, empty ReplyText).
  - `TriageDecisionRef` and `TurnDecisionRef` are both set and differ, and `ShownDecisionRef()` is `TurnDecisionRef`.
  - Each ref names one Decision row under the turn's ItemId, owned by the session: kind `decide` and kind `turn`, outcome `tellnow`, `Fallback` 1, `no_key`. Neither row has Reasons, Confidence, Model or cost, and neither has a Usage row. Its `TraceSessionId` is the Item's trace session.
  - The stream holds `chat.message` queued, running and done, once each, and exactly two `decision` events, whose refs are the triage ref and the turn ref.
  - The done event carries `catalogKey` `conversation.turnFallback`, `fallbackReason` `no_key`, and `decision` as the turn decision (`ref` = TurnDecisionRef, kind `turn`, `fallback` true, `fallbackReason` `no_key`). Its `turnCost.costUSD` is 0.
  - The Outbound carries Slots `{"fallbackReason":"no_key"}` and DecisionRef = TurnDecisionRef. WebChatOut's Delivery row carries the same DecisionRef.
  - On the page:
    - the reply reads "I couldn't answer that: no model key is set. Nothing was changed.";
    - the strip shows Tell now, Fallback and `<$0.0001`, with no confidence, then the trace link after the separator;
    - the reason line is "No model key is set.";
    - one button, "Decision details". Its details hold Tokens `Input 0 · Output (includes thinking) 0 · Cache read 0 · Cache write 0`, Agent steps 0, a Duration, the Decision message (a 22-character ref) and Cost `<$0.0001`. They show no Model row.
- **An untrusted mail Item gives:**
  - one Decision row of kind `decide`: `tellnow`, Fallback 1, `no_key`, owned by the session;
  - an ItemDecision `tellnow|1|no_key|<that Ref>`;
  - a Notification `notice.tellNowFallback` with slots `{"whatHappened":"zz Dana: Invoice","reason":"no_key"}` and the DecisionRef;
  - one card, `tellnow|web|no_key|<that Ref>|` (kind, channel, reason, DecisionRef, ApprovalRef), with the text "zz Dana: Invoice\nWhy now: no model key is set";
  - one `decision` event, then one `notification` event whose `whyNow` reads "Why now: no model key is set" and whose `decisionRef` and `decision.ref` are the row's Ref.
- **A seeded turn resumed by a reconcile or a restart** gets the same outcome: `no_key`, both refs set. A turn left running ends on Attempt 2, and a queued turn on Attempt 1.
- **The tests that change:**
  - Server (`shard:lane-b`):
    - `ConversationProduction`'s three red tests;
    - `RoutingProduction.TestUntrustedItemReachesTheWebChat`;
    - `ThreadProduction.TestStubFallsBackAfterTheRestore`, renamed `TestRealDecideAfterTheRestore`.
  - Row 20 of `test-production-restart.sh`.
  - Web:
    - `api.spec.ts` Story 2.4's rows;
    - `chat.spec.ts`: `FALLBACK`, C2 to C4, C7, C9 to C11 and C15;
    - `links.spec.ts` V1 and V2, red on the merged tree once the 14 cases ran (Task 0);
    - `banners.spec.ts` B6 and its `decideIsStub()` guard;
    - `notice.spec.ts` N10's Why-now line;
    - a new seeded `decision.spec.ts` D14.
  - The headers and comments named in the Code Map.
- **The no-decision fallback strip stays pinned.** This is the chip, the flag and the reason alone, with no cost and no Details. Conversation's own `unusable` path, and DW-126, still produce it on the merged tree. C15 used to pin it through the stub; D14 now pins it with a seeded fallback turn that has no decision rows.
- **Hermeticity.**
  - `Test.Data.Fixture.AdoptTurns` also records each adopted turn's two Decision rows (when they exist and the session owns them), so `Clean` removes the rows that the real Decide wrote for fixture sessions.
  - `TestUntrustedItemReachesTheWebChat` adopts its Item's decide row.
  - D14 removes its seeded rows in `finally` (`cleanFixtureRows(turnRows(...))`).
- **Fail fast in the chat cases.** One local helper in `chat.spec.ts` replaces the repeated reply-text wait.
  - It waits up to 20 s for the reply's `.text` to exist (the turn is done), then expects the sentence with a 2 s timeout.
  - So a wrong sentence fails in about 2 s, never 20 s, and can't starve the unit's deadline again.
- **Time.** `live:sign-in` passes inside its local 540 s deadline. Task 0 measured 421 s for the whole call, with two failing cases.

**Never:**
- **No product change.** Change `src/ocutalon/cls/OcuTalon/{Core,Channel,Live,Data,Msg,Web}/**` and `web/src/**` only if a test exposes a real integration defect in Epic 2's code. Then fix it with a test and record it under Design Notes. A defect in Lane A's code is a lead item, never an edit.
- **Do not edit Lane A's or contended files:**
  - `src/bridge/**`;
  - `src/ocutalon/cls/OcuTalon/{Agent,Tools,Install}/**`;
  - `src/ocutalon/cls/OcuTalon/Test/{Bridge,Install,Agent,Tools}/**`;
  - `ci/mock/scenarios/A/**`, `.github/workflows/*`, `docs/**`, `.gitattributes` and `install.sh`;
  - `docker/tests/test-boundaries.sh`, `test-ci-config.sh` and `test-install-script*.sh`;
  - `docker/tests/lib-live.sh`, `ci/iris.sh`, `ci/warm.sh` and `ci/units.sh`.
- **Never bring back a stub `Decide`.** Never swap `DecideDouble` into a test that does not swap it today. Never switch model keys on any stack, and never call `Test.Agent.RunnerFixture.PointKeys`.
- **Leave the probe-level tests and `DecideDouble`'s behaviour unchanged:** `ConversationTurns`, `Intake` and `Routing`. They stay the pins of the error-status path, of every reason, and of an unknown reason becoming `unusable`. Only `DecideDouble`'s header comment changes.
- **Leave DW-126 alone:** a repeated turn for one ItemId ends `unusable`.
- **No public text**, catalog entry, `ci/units.sh` entry, new unit or new group.
- **No assertion on Lane A's internals:** no runner-request counts and no mock log. Assert Lane B's surfaces, plus the Decision record that the real `Decide` keeps.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Chat turn | A message through WebChatIn, keyless stack | The Turn, both rows, the stream, the Outbound and the Delivery as listed under Always | Any other reason or a missing ref fails, naming the field |
| Resume | A reconcile, or a kill and restart, of a running turn and a queued turn | Both `done`, `no_key`, both refs set; Attempts 2 and 1; one done event each, in order | — |
| Untrusted item | A mail Item to Intake | The row, the ItemDecision, the Notification, the card and the two events as listed | — |
| Decide restored | ThreadProduction's swap back from the double | The turn is `no_key`, with two `decision` events on the stream (the HostSink setting is back) | A double left in place answers "zz reply to …": red |
| Page reply | C2 to C11 send | The no-key sentence; C2's log reads Deciding…, Working…, then the sentence | A wrong sentence fails within about 2 s of the turn being done |
| Keyless strip (C15) | A sent message | Chip, flag, `<$0.0001`, the link, "No model key is set.", and "Decision details" with the measured rows | — |
| No-decision strip (D14) | A seeded fallback turn (`unusable`) with no decision rows | Chip, flag and "The model's reply couldn't be used." only: no cost, no confidence, no button | — |
| Rail decision (V2) | The newest done turn of the links user | Its decide row (TriageDecisionRef) is in the rail, linking to the turn's own traceUrl | — |
| No-key start (B6) | Keyless sign-in stack | Runs unconditionally: the banner, then the no-key reply with the Fallback flag | — |

</intent-contract>

## Code Map

**Server tests (Lane B, `src/ocutalon/cls/OcuTalon/Test/`)**
- `Core/ConversationProduction.cls`:
  - the header `:1-28`: its lines 4-6 say "the Decide of Epic 0 … every turn ends in the fallback unusable";
  - the doc of `TestTurnThroughProduction` `:58-61`;
  - the assertions `:80` (key, reason, text), `:81` (Attempt, Tainted and the two refs), `:86` (the done event), `:118` (the Outbound, which gains its DecisionRef) and `:128` (the Delivery's DecisionRef);
  - the reconcile assertions `:252` and `:307`, and the doc `:278-280`.
  - Read the decision rows with `##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref)` (index `RefIndex`). Count Usage rows with SQL on `OcuTalon_Bridge_Data.Usage` (Task 0 used it).
  - The `decision` events: `##class(OcuTalon.Test.Core.Observe).Events(session, "decision", 2, ..#WAIT)` (`Observe.cls:46`).
  - The private helpers `WaitEvents` and `Deliveries` stay.
- `Core/RoutingProduction.cls`:
  - the header `:6-8` and the doc `:33-35`;
  - the assertions `:48` (the card), `:49` (its text), `:55` (the event payload: add `decisionRef` and `decision.ref`) and `:76` (the ItemDecision);
  - the Item's decide row is `ItemIdKindIndexOpen(item.ItemId, "decide")`. Adopt it into `..Refs`.
  - `WaitEvents(session, "decision", 1)` at `:273` reads the decision event.
- `Core/ThreadProduction.cls`:
  - header `:5-10`: the swap stays until Epic 11, because a keyless real `Decide` answers every turn `no_key` and sends no agent steps, and the thread tests need the double's replies, steps and decisions;
  - header `:19-20`;
  - the test `:194-208`, renamed. It asserts `no_key`, the turn's two refs, and two `decision` events on the session's stream;
  - `UseDouble` `:287-321` stays as it is.
- `Core/DecideDouble.cls:1-4`: header only. "until Stories 1.3 and 1.5 build the real one" becomes "until Epic 11 removes the swap; the real Decide on a keyless stack answers every turn no_key".
- `Data/Fixture.cls`:
  - `AdoptTurns` `:237-251` also adopts `Decision` rows by `TriageDecisionRef` and `TurnDecisionRef` when `OwnerRef` is the session. It adds each Ref once, the same way it adds turn Refs today;
  - its doc, and the header sentence `:12-13`;
  - `Adopt` `:231` and `Record` `:415` are unchanged.
  - Callers: ConversationProduction `:54`, ThreadProduction `:76` and ConversationTurns `:102`.
- Read only:
  - `Core/Conversation.cls`: `:388` and `:438` keep the refs, `:513` is `ReasonOf`, and `:575-580` set the Outbound's DecisionRef and Slots;
  - `Core/Intake.cls:196-229` (the ItemDecision);
  - `Live/Payload/ChatMessage.cls:94-108` (`SetDecision`);
  - `Live/Payload/Decision.cls:101-108` (the turn's trace target, DW-129);
  - `Data/Turn.cls:75-79` (`ShownDecisionRef`);
  - `Data/Ownership.cls:218-222` (`Decisions`, decide rows only);
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:1-90` (the class doc: Precheck, RecordFallback).

**Live script**
- `docker/tests/test-production-restart.sh`:
  - the header `:20-24` ("the stub Decide answers an error status");
  - row 20's check `:219-228`. It becomes `CHK|turns|done|2|conversation.turnFallback|no_key|done|1|conversation.turnFallback|no_key` plus a new line `CHK|refs|1|1|1|1|tellnow|1|no_key|tellnow|1|no_key`. That line holds: the four refs are non-empty (use `$Length(…)>0`, since a `'` breaks the single-quoted shell string), then the first turn's decide row and the second turn's turn row, each as Outcome, Fallback and FallbackReason.
  - The label names the decisions. Measured green at Task 0.
- `docker/tests/test-sign-in.sh`:
  - header `:24-26` (D1 to D14);
  - `:41` ("B6 turns itself on when the bridge's Decide is built" becomes "B6 replies through the real Decide's no-key fallback");
  - the PASS and FAIL lines `:233` and `:239` (D1-D14).

**Web tests (`web/e2e/`)**
- `api/api.spec.ts`:
  - the doc `:394-399`;
  - `:440`: `fallbackReason: 'no_key'`, plus `decision` (`kind` `turn`, `outcome` `tellnow`, `fallback` true, `fallbackReason` `no_key`) and `turnCost.costUSD` 0;
  - the reload `:463-477`: `fallbackReason: 'no_key'`, and the snapshot turn's `decision.ref` equals the done event's.
- `chat/chat.spec.ts`:
  - the header `:7-9`;
  - `FALLBACK` and its doc `:37-38`: the no-key sentence;
  - a new helper beside `replyOf` `:86`: it waits for the reply's `.text`, then the sentence with a 2 s timeout;
  - the reply waits `:240, 319, 356, 392, 418, 453, 475, 514, 691, 762, 787, 824` use it. C2's `replyLog` poll `:238` stays;
  - C12's doc `:829-834`;
  - C15 `:912-929`, rewritten to the keyless strip (measured values under Always), with a `DOT` (`' · '`) for the tokens line.
- `chat/decision.spec.ts`:
  - header `:7-11` (D1 to D14);
  - D14 goes after D13 (`:524-545`). It uses `seed` `:104`, `turn()` `:72` (with `triage: undefined`, `turn: undefined`, `usage: []`, catalogKey `conversation.turnFallback`, fallbackReason `unusable`, dated `2025-03-08`) and `stripOf` `:95`;
  - it removes its rows with `cleanFixtureRows` and `turnRows` (`support/iris.ts:367`, `:581`).
- `trace/links.spec.ts`:
  - V1 `:190-193`: line 1's meta is `<$0.0001`, the separator and the link (as the notice case at `:215-217` checks it);
  - `itemIdOf` `:227-232` becomes a reader of the turn's ItemId and `TriageDecisionRef`;
  - V2 `:235-268`: `decisionRef` is the turn's TriageDecisionRef, which is asserted non-empty, and the turn's own seeded decision `:239-245` is removed. `other` stays seeded.
- `banners/banners.spec.ts`:
  - header `:18-27`: `:25` "the Keys stub answers 0" goes, and the header says B6's one message is the exception to "holds nothing but what the case seeds";
  - the import `:8`;
  - B6 `:397-399`: no skip, and a doc without "Turns itself on".
- `support/iris.ts:754-763`: `decideIsStub` is deleted. It has no other reader (`grep -rn decideIsStub web`).
- `chat/notice.spec.ts`:
  - N9's doc `:273-276` and N10's `:288-292`: on a keyless stack the precheck gives `no_key` before anything is sent, so the refusal marker stays inert;
  - N10's Why-now line `:309`: `'Why now: no model key is set'`.

## Tasks & Acceptance

**Execution:**
- **Task 0 (done at plan, 2026-10-25; nothing kept).**
  - **Throwaway tag `e2s217p`.**
    - `shard lane-b` ran with an untracked probe class. It printed the measured values under Always. The same three classes failed, as the lead reported: 4 of 43 classes, 103 s.
    - `live sign-in` ran with `FALLBACK` and the api reason patched to the no-key values, and C15 replaced by a dump of the strip. Result: 189 passed, 1 skipped (notice's not-built Story 4.5 case) and 2 failed: V1 (line 1 now has 3 items) and V2 (the turn decision is not a rail row). B6 ran and passed. The call took 421 s, with 5.9 min of Playwright.
    - `live production-restart` ran twice. Unpatched, row 20 failed. With the expected lines above, it passed (3 values), 98 s.
  - **Restoring.** Each patched file was restored from this stage's backup: the `shasum`s matched, and `git status` and `git diff` were clean. The probe file was deleted. `teardown` removed 0 leftovers.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls` -- the three tests assert the measured turn, both rows, the two `decision` events, the done payload's decision and turnCost, and the Outbound's and the Delivery's DecisionRef; headers and docs -- Story 2.4 on its real path.
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls` -- the card, its text, the event, the ItemDecision, the decide row and its decision event, and adopting the row; header and doc -- Story 2.7 on its real path.
- `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls` -- the rename, `no_key`, the refs and the two decision events after the restore; header -- the swap's restore is pinned.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls` -- header sentence only.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `AdoptTurns` also records the decision rows; doc -- hermeticity.
- `docker/tests/test-production-restart.sh` -- row 20's two lines and the header.
- `docker/tests/test-sign-in.sh` -- header and the PASS and FAIL lines (D14, B6).
- `web/e2e/api/api.spec.ts` -- `no_key`, the decision, turnCost and the reload's ref; doc.
- `web/e2e/chat/chat.spec.ts` -- `FALLBACK`, the fail-fast helper, C15, header and docs.
- `web/e2e/chat/decision.spec.ts` -- D14 and the header.
- `web/e2e/trace/links.spec.ts` -- V1's meta, V2's decide row and its comment.
- `web/e2e/banners/banners.spec.ts` and `web/e2e/support/iris.ts` -- B6 always runs, `decideIsStub` goes, and the header.
- `web/e2e/chat/notice.spec.ts` -- N9 and N10 docs, and N10's Why-now line.
- **Sweep.**
  - Search `src/ocutalon/cls/OcuTalon/Test`, `web/e2e`, `web/scripts` and `docker/tests` for `stub Decide`, `Decide of Epic 0`, `Epic 0's`, `Story 1.3`, `stub model`, `fixed fallback`, `unusable`, `decideIsStub` and `Keys stub`. Update each live-path claim. Probe-level text about the double stays.
  - Confirm that nothing else reads `TestStubFallsBackAfterTheRestore`.

**Acceptance Criteria:**
- **The server tests (Stories 2.4, 2.7 and 2.9).**
  - **Given** the merged tree on a keyless throwaway,
  - **when** `ci/iris.sh shard lane-b` runs,
  - **then** `ConversationProduction`, `RoutingProduction` and `ThreadProduction` pass, asserting the turn, rows, events, Outbound, Delivery, card and ItemDecision values under Always;
  - **and** every other class of the shard passes.
- **Row 20.**
  - **Given** a session with a turn left running and a queued turn,
  - **when** `ci/iris.sh live production-restart` kills and restarts the container,
  - **then** both turns end `no_key`, on Attempts 2 and 1, with their four decision refs and their `tellnow|1|no_key` rows, and with one done event each, in order.
- **The browser (Stories 2.4, 2.5, 2.6, 2.7, 2.10 and 2.13).**
  - **Given** the keyless sign-in stack,
  - **when** `ci/iris.sh live sign-in` runs,
  - **then** every case passes inside the 540 s local deadline, among them:
    - the api row, with `no_key`, the turn decision and the reload's same ref;
    - C2 to C11 with the no-key sentence;
    - C15, the strip of the keyless decision;
    - D14, the strip with no decision;
    - B6, with no skip;
    - N10, with the no-key Why-now line;
    - V1 and V2.
- **Falsifiable (Rule 19).**
  - **Given** each changed pin,
  - **when** its planned mutation (Verification) is applied,
  - **then** that pin goes red, and the tree is byte-identical after the revert.
- **The whole merged tree (REL-4).**
  - **Given** the story's final tree,
  - **when** each command under Verification's "(once)" runs,
  - **then** all six IRIS groups pass (`browser` and `shards` as their split units), and so do `bash ci/checks.sh`, `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-mock.sh`, `npm --prefix web test` and `npm --prefix web run lint`.
- **No product change.**
  - **Given** the diff since the story's baseline,
  - **when** it is listed,
  - **then** it touches only test files and the two live scripts. The only exception is an integration defect recorded under Design Notes with its own test.

### Review Findings

Code review (2026-10-25, the story's first `bmad-code-review` pass; four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 29 reported findings, 22 entries after grouping: 0 decision-needed, 9 patch (all applied and verified), 1 defer, 12 rejected. Two verdicts were settled by a measured mutation rather than by reading: the server's turn-cost check was confirmed (it stayed green with no `turnCost`), and the "no Usage row passes on a failed query" claim was disproved.

- [x] [Review][Patch] `[medium]` The `AdoptTurns` pin checks the returned list, not the record that `Clean` reads: dropping `Do ..Adopt(decision)` alone kept it green while every turn left its two Decision rows. The pin now also asserts each row's `^OcuTalonTest("Fixture", ...)` record [src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls:93]
- [x] [Review][Patch] `[low]` The server's turn-cost check (`+last.turnCost.costUSD = 0`) stayed green with no `turnCost` in the done event (measured); it now requires the object and its `costUSD` [src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls:105]
- [x] [Review][Patch] `[low]` Row 20's header said both turns' rows are read; it now names the two rows the refs line reads (the first turn's triage row, the second turn's turn row) [docker/tests/test-production-restart.sh:22]
- [x] [Review][Patch] `[low]` RoutingProduction's header named no adopted decide row; the eval test's bullet and the clean-up sentence now do [src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls:17]
- [x] [Review][Patch] `[low]` C15's "one button" counted only buttons named "Decision details"; it now counts every button of the strip, then names it [web/e2e/chat/chat.spec.ts:946]
- [x] [Review][Patch] `[low]` C15's doc said the Details rows hold no tokens and no steps; it now says 0 tokens and steps, as the case asserts [web/e2e/chat/chat.spec.ts:928]
- [x] [Review][Patch] `[low]` api.spec's doc said the snapshot's turn carries the turn decision and a turn cost of 0, but the reload checked only the decision's ref; the reload now asserts the decision's kind, outcome, fallback and reason and `turnCost.costUSD` 0 [web/e2e/api/api.spec.ts:488]
- [x] [Review][Patch] `[low]` decision.spec's `FALLBACK` doc said the stack's own Decide gives this seeded fallback, which carries reasons and a confidence that the real Decide's fallback never has; it now says it is seeded [web/e2e/chat/decision.spec.ts:84]
- [x] [Review][Patch] `[low]` Three checks this story added had no demonstrated mutation: Routing's decision event, ThreadProduction's two Refs, the server's turn cost (Rule 19 LOW, closed in pass; mutation lines under Verification) [src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls:60]
- [x] [Review][Defer] `[low]` No check counts the Decision rows left after the shards, so a lost adopt (Routing's two, `AdoptTurns`) or D14's `finally` would leak with every test green [src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls:197] — deferred: DW-197 `wontfix-accepted` (a leftover count is a shard-level check, and this story adds no unit; QA measured 0 rows left by SQL)

**Rejected** (one line each):
- `[low]` B6 still waits up to 30 s for its sentence (blind-hunter; acceptance-auditor note): one 30 s wait fits the unit's margin (about 415 of 540 s), the spec scopes the helper to chat.spec, and a copy in banners.spec would be a Rule 2 near-copy.
- `[low]` C15's Decision message is matched by pattern (blind-hunter): D3 pins on the page that the strip shows the turn decision and not the triage one, api.spec and ConversationProduction pin the payload's decision as the turn's, and the spec prescribes "a 22-character ref".
- `[low]` V2 relies on an earlier turn of the same trace day, and re-publishes the turn's decision event (blind-hunter; edge-case-hunter): a run that crosses UTC midnight fails loudly at V2's precondition (never a false green), a second post only narrows that window, and the rail keys rows by Ref, so the extra event changes nothing.
- `[low]` A turn that never reaches done leaves its Decision rows (blind-hunter; edge-case-hunter): only on a run that has already failed, on a throwaway; the earlier triage rejected the same class.
- `[low]` Routing quits before adopting when no card comes (edge-case-hunter): the same, rejected by the earlier triage.
- `[low]` Row 20 does not adopt the four Decision rows of the restart turns (edge-case-hunter): the unit's throwaway is torn down after it, and the header's "rows" are the seeded ones (earlier triage).
- `[false]` A missing `decision` in the done event aborts the test (edge-case-hunter): the comparison fails with the field empty, loudly; no false green.
- `[low]` `AdoptTurns` misses Usage rows and superseded attempt rows (edge-case-hunter): a keyless stack writes no Usage row (asserted) and the real Decide never retries there; the double's rows are recorded by `DecideDouble.Record`.
- `[false]` Row 20's refs line breaks on an empty Ref and hides which (edge-case-hunter): the four `$Length` flags are written before the row fields, so the partial line names the empty Ref.
- `[low]` C2 still polls `replyLog` for 20 s (edge-case-hunter): the spec keeps C2's poll (Code Map), so the fix edits the spec.
- `[false]` "No Usage row" passes when the count query fails (blind-hunter; edge-case-hunter): measured with a table name that does not exist, `%GetData` raises `<METHOD DOES NOT EXIST>` on the failed result, so the check already fails loudly; no change kept.
- `[low]` The decision-then-notification order is not asserted (blind-hunter; acceptance-auditor): BridgeSink publishes in Decide's job before Decide answers Intake, which only then routes the card (AD-31), so no mutation short of a re-architecture can reorder them and the assertion would have no observable red.

## Spec Change Log

## Review Triage Log

### 2026-10-25 — Review pass
- verdicts: 19 rows (31 reported findings, the duplicates across layers grouped into one row each) — high 0, medium 2, low 14, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` V2 can pass without the DW-129 override when its turn is the day's first (Blind 1) — V2 now posts a later turn and asserts the triage decision's own trace session differs from the turn's header; mutation recorded (V2 alone red).
  - `[low]` `[reject]` `rowsOfTurn` fragile pick of the turn (Blind 2; verification-gap self-containment) — V2 now posts its own turn.
  - `[low]` `[patch]` `rowsOfTurn` returned an unused itemId (Blind 3) — the helper is now `triageOfTurn` and returns what V2 reads.
  - `[low]` `[reject]` row 20's refs line opens only t1's triage row and t2's turn row (Blind 4; Edge 1, 2, 9; Intent R-D) — the spec prescribes this exact line, and fixing it edits the spec; the other two Refs are checked as set.
  - `[low]` `[reject]` row 20's header says the rows are removed, yet Decide's rows are not adopted (Blind 5; Edge 3, 10) — the header's rows are the seeded ones, the throwaway is torn down, and the `left` check reads what it claims.
  - `[low]` `[reject]` Routing adopts the decide row after the card wait (Blind 6; Edge 4; verification-gap other) — only on a run that has already failed, on a throwaway; the fix adds a second lookup path.
  - `[low]` `[reject]` TestTurnsRunInOrder has no Refs assertion (Blind 7) — it was not red, is not in the spec's list, and the ordering is its pin.
  - `[low]` `[reject]` B6 sends with no clean-up (Blind 8; verification-gap) — Decided in-stage 3 (the convention of the sending cases); later B cases filter by their own stamp.
  - `[low]` `[reject]` ThreadProduction has no key guard (Blind 9) — every throwaway starts keyless (check_no_key).
  - `[low]` `[reject]` the 20 s plus 2 s helper window (Blind 10) — the spec prescribes it, and the 2 s starts when the reply text exists.
  - `[low]` `[patch]` over-long doc lines in Fixture and ConversationProduction (Blind 11) — rewrapped.
  - `[false]` `[reject]` Edge: INVALID OREF aborts the done-event assertions, Usage SQL, empty Turn in ThreadProduction, Routing Quit on a missing row (Edge 5-8 and the like) — each is a failing run that fails loudly at the cited place, and Turn already asserts the turn.
  - `[low]` `[reject]` AdoptTurns could adopt by OwnerRef (Edge 7) — a crash mid-turn leaves no named row; a throwaway is torn down.
  - `[medium]` `[patch]` AdoptTurns' new adoption had no test and no mutation (verification-gap) — TestTurnThroughProduction asserts that AdoptTurns records the turn and both Decision rows; mutation recorded.
  - `[medium]` `[patch]` Routing's DecisionRef pins had no mutation (verification-gap) — mutation recorded (Intake keeps no DecisionRef: card, event, Notification and ItemDecision red).
  - `[low]` `[reject]` Conversation's row-field and Usage pins have no mutation (verification-gap) — the row is Lane A's record, and a mutation would edit Lane A's Decide; the pin is read-only.
  - `[low]` `[reject]` api reload ref and C15, D14, B6 detail pins have no mutation of their own (verification-gap) — each can fail on a value, sits beside a demonstrated pin on the same surface, and a snapshot-only mutation swamps the unit.
  - `[false]` `[reject]` intent-alignment divergences (C2's poll and C9's visibility keep 20 s; row 20 checks fewer fields than the Always block; the 540 s deadline has no assertion) — the spec keeps C2's poll, row 20's line is prescribed, and the deadline is the script's own.
  - `[false]` `[reject]` spec trailer still reads ready-for-dev (verification-gap) — finalize writes it.

## Design Notes

**Governing ADs (Rule 6).**
- **AD-8:** only `Decide` classifies. Its precheck order puts `no_key` first, and a request that fails it is never sent. A fallback is `tellnow`, `Fallback` true and the reason, with no reasons, confidence or payload, and it triggers nothing. The tests read this record and never re-derive it.
- **AD-30:** two `Decide` requests per turn and one per untrusted Item. Intake builds the ItemDecision from the DecisionResponse, DecisionRef included. Conversation never classifies (its `unusable` mapping stays pinned by the probe tests).
- **AD-32:** the tell-now card is `notice.tellNowFallback` with `{whatHappened, reason}`, and only the renderer writes text.
- **AD-20:** the cost is per decision and per turn, so the strip shows the turn's cost (`<$0.0001` for 0, per the UX formats table) and the details show the decision's.
- **AD-12 and AD-31:** BridgeSink turns `decision.recorded` into a `decision` event on the owner's stream, synchronously in Decide's job. Measured: the decision events come before the done event.
- **AD-26:** the trace thread. V2's link to the turn (DW-129).
- **AD-22:** throwaways only, `ci/iris.sh` as the one recipe, and the six groups unchanged.
- **AD-29 and AD-33:** Lane B's files only; Lane A's are read.

No AC contradicts an AD's Rule. **Rule 5:** no NFR is involved. The 540 s and 1200 s deadlines are test configuration, and N10's 5 s (P30) is measured as before.

**Decided in-stage** (small, reversible, within the intent):
1. **The expected values are Task 0's measurements.** The story's AC says "the `noModelKey` fallback". `noModelKey` is the banner's condition, and the turn's reason is `no_key`, so the tests use `no_key`. No amendment is needed.
2. **C15 asserts the keyless strip with its decision.** The no-decision strip that C15 used to cover moves to a seeded D14, because it is still reachable (Conversation's own `unusable`, DW-126) and the strip's doc promises it.
3. **B6's guard and `decideIsStub` go.** Every sign-in stack is keyless (`check_no_key`), and a silent skip is a pin that can't fail. B6 keeps the convention of the cases that send (C2 to C11): it asserts only on its own clientId and leaves its turn. The banners header says so, and Task 0 ran the later B cases green after it.
4. **ThreadProduction's test is renamed `TestRealDecideAfterTheRestore`.** Its two `decision` events prove that the restore brought back the HostSink setting, not only the class.
5. **The fail-fast reply helper** answers the lead's note that a 20 s wait on a wrong text starved the unit.
6. **N10's Why-now line is exact.** It is the browser pin of Story 2.7's card through the keyless fallback, inside the 5 s bound.
7. **`AdoptTurns` records decision rows,** extending the existing helper (Rule 2), so the real Decide's rows for fixture sessions are cleaned.
8. **No mock key and no `RunnerFixture`.** The keyless path is the one that every throwaway and the sign-in stack runs. The mock's model path is covered by Lane A's tests.
9. **Row 20 gains the refs line**, and the api row gains `decision`, `turnCost` and the reload's ref. That is "whatever decision record the real Decide keeps", at the surface each test already reads.
10. **No split.** About 14 files change, all tests, on one root cause.

**For the lead (your calls).**
- **Footprint.** `Test/Data/Fixture.cls` and `docker/tests/test-sign-in.sh` are inside Epic 2's `paths_hint` (`Test/{Core,Web,Data,Live}/**`, `docker/tests/**`), and neither is on the contended list. No footprint extension.
- **Rule 21 facts to append if you wish** (local ARM, merged tree, tag `e2s217p`):
  - `shard lane-b` 103 s (43 classes, the probe included);
  - `live sign-in` 421 s for the call (192 cases);
  - `live production-restart` 98 to 105 s.
- **Seen, not this story's.** Each tell-now Notification makes Notify's send to `SimPhoneOut` log `ERROR #5003: Not implemented`. That item is still a stub (Story 4.5). It was there before the merge. File it if it is not already known.
- **DW-106** is terminal (`by-design`). This story is the update it promised, so no trailer is needed unless you want `occurrence=2-17-epic-2-s-tests-follow-the-real-decide`.

**Veto-window items:** none. No text, role, setting or stored data changes. U-68 (how the tests are fixed) is chartered as "follow the merged outcome, no stub".

**Ledger (Rule 17).** The inbox is empty. DW-106 is addressed, as above. DW-126 is untouched, by rule.

**Integration ACs (Rule 1).** This test-only story introduces no service, module or shared component, so it has no consumers. The one shared helper it changes, `Fixture.AdoptTurns`, keeps its three existing callers.

**Consumes:**
- Story 1.3's real `Decide`: the precheck and `RecordFallback`, read only.
- `Keys.Absent`.
- Story 2.6's BridgeSink and strip.
- Story 2.7's Intake, OutcomeRouter and WebChatOut.
- Story 2.8's rail.
- Story 2.13's links.
- Story 2.10's banners.

**Consumed-by:** none.

**Extend, don't copy (Rule 2).**
- `AdoptTurns` is extended, with no new method.
- The chat helper replaces twelve copies of one wait.
- `itemIdOf` is extended to return the triage ref, not copied.
- D14 uses decision.spec's `seed`, `turn()` and `stripOf`.

## Verification

**IRIS.** If a stage makes an MCP call:
- name `server: ocutalon-slot-b` and `namespace: OCUTALON`, with `iris_server_info` (build 154) first;
- make one `iris_execute_tests` per message;
- never run the production classes there.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s217<i|q|r> OCUTALON_LOCK_OWNER='epic=2 stage=<stage>' bash ci/iris.sh <piece>`.
- `<main checkout>` is typed only at the prompt.
- Run one piece per foreground call with `timeout: 600000`, and end with `teardown` on the same tag.
- `LOCK busy` (exit 75) means wait 30 to 90 s and retry.
- **Warm runs** use the tag plus `w` (for example `e2s217iw`): `ci/warm.sh up`, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e2s217iw bash ci/iris.sh class <Class>`, and `ci/warm.sh down` at the stage's end, after a failure too.

**Commands:**
- **(loop)**, each in its own call:
  - `npm --prefix web run lint`;
  - `npm --prefix web test`: 565 pass, unchanged.
- **(loop)** Warm, one class per call: `class OcuTalon.Test.Core.ConversationProduction`, `class OcuTalon.Test.Core.RoutingProduction` and `class OcuTalon.Test.Core.ThreadProduction`. Expected: passed.
- **(loop)** Fresh: `live production-restart` (about 100 s) and `live sign-in` (about 420 s, inside 540 s). Expected: all checks pass. With D14, `live sign-in` has 193 cases: 192 passed and 1 skipped (notice's not-built Story 4.5 case).
- **(once)**, each its own call:
  - `group install-fresh`;
  - `group install-upgrade`;
  - `group production`;
  - `live demo-path`;
  - `live sign-in` (these two are `browser`);
  - `shard lane-a`;
  - `live floor` (these two are `shards`; 588 s together locally);
  - `group image`;
  - `shard lane-b --reverse` (the fresh check);
  - `teardown`.

  Then, each its own call: `bash ci/checks.sh`, `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-mock.sh`, `npm --prefix web test` and `npm --prefix web run lint`. Expected: every one exits 0. Record each time.

**Planned mutations (Rule 19).** For each: apply it, observe red, restore from the stage's own backup, and confirm that `git status --short` and the hash of `git diff` are unchanged. The browser mutations run in two batches whose expected reds are disjoint by mechanism.

| Pin | Mutation | Expected red |
| --- | --- | --- |
| ConversationProduction (3 tests), ThreadProduction, row 20 turns line | `Conversation.cls:513` `ReasonOf` always `unusable` | Each test's reason assertion; row 20's `turns` line |
| ConversationProduction refs, Outbound and Delivery; row 20 refs line | `Conversation.cls:438` (keeping TurnDecisionRef) removed | TestTurnThroughProduction's refs, Outbound, Delivery and done-decision assertions; both reconcile tests' refs; row 20's `refs` line |
| RoutingProduction | `Intake.cls:209` reason always `unusable` | The card, its text, the event and the ItemDecision |
| ThreadProduction restore | `UseDouble(0)` restores the class but no settings | `TestRealDecideAfterTheRestore` (no `no_key` and no decision events) |
| Browser batch 1: api, C2 to C11, B6, N10, V2, D14 | `ReasonOf` as above, plus `Intake.cls:209` as above, plus `Live/Payload/Decision.cls:103-108` (the turn override) removed, plus the strip's `meta` showing `formatCost(this.cost() ?? 0)` | api (reason), C2 to C11 and B6 (sentence), N10 (Why now), V2 (href), D14 (cost shown) |
| Browser batch 2: C15, api decision, V1 | `ChatMessage.cls` `SetDecision` quits at once | C15 (no cost, no Details), api (`decision`), V1 (line 1 count) |

The implement stage records each run as `mutation: … -> …` below.

- mutation: `Conversation.Reason` always `unusable` (warm, tag e2s217iw) -> red: ConversationProduction (TestTurnThroughProduction's reason, its done event and its Outbound slots; both reconcile tests' reason lines) and ThreadProduction (TestRealDecideAfterTheRestore's reason).
- mutation: `Conversation.Replied` without `If answer.DecisionRef '= "" Set turn.TurnDecisionRef = ...` (warm) -> red: ConversationProduction (TestTurnThroughProduction's refs, "the turn's decision is the one it shows", the done event's decision, the decision events, the turn row, the Outbound's DecisionRef and the Delivery's; both reconcile tests' refs).
- mutation: `Intake.Take` reason always `unusable` (warm) -> red: RoutingProduction (the card, its text, the event, the Notification and the ItemDecision).
- mutation: ThreadProduction `UseDouble(0)` restores the class but no settings (warm) -> red: TestRealDecideAfterTheRestore, "and two decision events are on the session's stream" only (the turn is still `no_key`, since the precheck needs no HostSink, so the no_key assertion stays green; the decision events are what show the missing setting).
- mutation: `Conversation.Reason` always `unusable` (fresh, tag e2s217i) -> red: row 20's `turns` line (1 of 3 values differ).
- mutation: `Conversation.Replied` without the TurnDecisionRef line (fresh) -> red: row 20's `refs` line (1 of 3 values differ).
- mutation: browser batch 1 (`Conversation.Reason` and `Intake.Take` reasons always `unusable`, `Live/Payload/Decision.FromRow` without the turn's trace override, and the strip's `meta` with `this.cost() ?? 0`) -> red, 19 failed, 171 passed, 2 did not run (the api row's serial followers): api (reason), B6, C2, C3, C4 (six cases), C7, C9, C10, C11 and C15 (sentence), N10 (Why now), V2 (href), D14 (cost shown), and N4, the one other case whose no-decision strip shows the cost.
- mutation: browser batch 2 as planned (`ChatMessage.SetDecision` quits at once) -> red but swamped: 14 failed (api, C15, D1 to D9, D11 to D13), 107 passed, 71 did not run before the unit's Playwright deadline (7.7 min), so V1 never ran. The planned mutation is too wide: every seeded strip needs the decision payload too.
- mutation: browser batch 2, narrowed to `ChatMessage.SetDecision` quitting for `no_key` turns (`If row.FallbackReason = "no_key" Quit` first) -> red, 3 failed, 187 passed, 2 did not run: C15 (no cost, no Details), api (`decision`), V1 (line 1 holds the link alone). Each mutation was reverted from a backup of this stage's own, and `git status --short` and the hash of `git diff` matched before and after every one (no untracked file was touched).
- mutation (review pass): `Fixture.AdoptTurns` loops over no decision Refs (warm, tag e2s217iw) -> red: ConversationProduction TestTurnThroughProduction, "the clean-up records the turn and both of its Decision rows".
- mutation (review pass): `Intake.Take` keeps no DecisionRef (warm) -> red: RoutingProduction, the card's DecisionRef, the event's decision, the Notification's DecisionRef and the ItemDecision's Ref.
- mutation (review pass): V2 posts its own later turn, and `Live/Payload/Decision.FromRow` without the turn's trace override (fresh, tag e2s217i, `live sign-in`) -> red: V2 alone (1 failed, 1 skipped, 191 passed, 5.8 min). Each was reverted from a backup of this stage's own, and `git status --short` and the hash of `git diff` matched before and after.

**QA pass (2026-10-25).** An audit, with one gap closed. Each mutation was reverted from a backup of this stage's own, and `git status --short`, `git diff` and the file hashes matched before and after.
- (QA) gap: `RoutingProduction.TestEvalItemWritesNoDeliveryOrEvent` left a Decision row behind. The real Decide records its decide row for an eval-owned Item too (owner `eval`), and `AdoptTurns` never sees it. The test now asserts that the row exists and adopts it, so that `Clean` removes it. Measured on a warm stack by counting `OcuTalon_Bridge_Data.Decision` rows after `ConversationProduction`, `RoutingProduction` and `ThreadProduction`: 1 row left before the fix, 0 with it.
- (QA) mutation: `RoutingProduction` without the new adopt (warm, tag e2s217qw) -> the class stays green and 1 `eval` Decision row is left (counted by SQL); with the adopt, 0 left. A hermeticity pin, shown by the row count, since a leak is not an assertion.
- (QA) mutation (test-side data, no Lane A source edited): after the production ran, `ConversationProduction.TestTurnThroughProduction` rewrote the triage row (`digest`, Fallback 0, `error`, Reasons, Confidence, Model, cost, TraceSessionId + 1), moved the turn row's Kind, OwnerRef and ItemId, and added a Usage row for it (warm) -> red: every `AssertFallbackRow` pin, "kind, owner, ItemId, and the fallback no_key" (both rows), "no Reasons, Confidence, Model or cost", "in the Item's trace session" and "and no Usage row".
- (QA) mutation: every `"unusable"` in `Core/Conversation.cls` and `Core/Intake.cls` becomes `"error"` (warm; Lane B code) -> red: `ConversationTurns` (TestBusyRequeues, TestCallbackFailureEndsTurn, TestEveryFallbackReason for 'error', 'wrong', 'fallback:zzbogus' and 'fallback:', TestSendFailuresNeverStrandTurn) and `Intake` (TestCallbackFailureSendsTheFallback, TestDecideFailureIsAFallback, every answer and the unknown reason). So the stub-era `unusable` path keeps its pin at the probe level, with `DecideDouble`.
- (QA) mutation: `Web/Api.cls` `ChatItems` builds the snapshot turn with `TurnDecisionRef` set to `TriageDecisionRef` for `no_key` turns (the snapshot only, so the done event is untouched), plus `Live/Payload/Decision.FromRow` setting `Model` for `no_key` rows (fresh, tag e2s217q, `live sign-in`) -> red, 2 failed, 190 passed, 1 skipped, 5.9 min: the api reload ("the snapshot's turn shows the same decision as the done event") and C15 ("the rows of a decision that has no model"). The api reload ref pin is shown red with no Lane A edit.
- (QA) checked, no mutation needed: D14 pins the strip of a fallback with no decision (chip, flag and reason alone, no cost, no Details), and the implement stage's `meta` mutation shows it red (D14 and N4).
- (QA) after the gap fix: `shard lane-b` passed (42 classes, 103 s, fresh, tag e2s217q); `teardown` of e2s217q and e2s217qw left nothing behind.
- (QA) the test files changed: `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls` (the adopt and its assertion). No file was created.

**Code review pass (2026-10-25).** Warm tag e2s217rw, fresh tag e2s217r. Each mutation was reverted from a backup of this stage's own; `git status --short` and the hash of `git diff` matched before and after every one, and each class was green again on the same stack after its revert.
- (CR) mutation: `Fixture.AdoptTurns` without `Do ..Adopt(decision)`, the Ref still returned (warm) -> red: ConversationProduction TestTurnThroughProduction, "and records the Decision row <ref> for Clean" for both rows (the returned-list pin alone stayed green).
- (CR) mutation: `Live/Payload/ChatMessage.SetDecision` without its TurnCost line (warm) -> green with the old `+last.turnCost.costUSD = 0`; red with the patched check: ConversationProduction "and a turn cost of 0".
- (CR) mutation: `Core/BridgeSink.OnEvent` drops `decision.recorded` (warm) -> red: RoutingProduction TestUntrustedItemReachesTheWebChat, "one decision event is published".
- (CR) mutation: `Conversation.Replied` without the TurnDecisionRef line (warm) -> red: ThreadProduction TestRealDecideAfterTheRestore ("with both decision Refs, which differ", "the triage decision's, then the turn decision's") and TestBrokenRetryThroughTheProduction ("the retry's decision is the turn's, in the thread").
- (CR) check: the "no Usage row" query with a table name that does not exist (test-side, warm) -> red: `%GetData` raises `<METHOD DOES NOT EXIST>` on the failed result, so the original check already fails loudly (no change kept).
- (CR) after the patches: warm ConversationProduction, RoutingProduction and ThreadProduction passed; fresh `shard lane-b` passed (42 classes, 104 s); `live sign-in` 192 passed, 1 skipped (5.7 min of Playwright, about 415 s for the call, inside 540 s); `live production-restart` passed (94 s); `teardown` of e2s217r and `ci/warm.sh down` of e2s217rw left nothing behind; `bash ci/checks.sh` and `npm --prefix web run lint` exit 0.

**Shared surfaces:**
- the `decision` events on fixture-session streams (`ConversationProduction` counts them);
- the Decision rows of fixture sessions (`AdoptTurns` now records them for `Clean`);
- the links user's rail (V2 reads the turn's decide row);
- the panel user's chat (C-cases, by clientId);
- the decision user's chat (D14, removed in `finally`);
- the banners user's session (B6's one turn);
- `support/iris.ts` (`decideIsStub` deleted, no other reader);
- `test-sign-in.sh`'s PASS line (no other script pins it).

**Every test added or changed passes on a fresh environment, in either order:**
- each server test makes its own fixture session and adopts what the production made for it;
- each browser case asserts only on its own clientId or refs;
- D14 seeds and removes its own rows;
- the fresh check runs `shard lane-b` forward (in `group image`) and `--reverse`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Epic 2's production and live tests now follow the merged tree's real `Decide`. On a keyless stack a turn ends `no_key` with both decision Refs, two fallback Decision rows, two `decision` events, and the Outbound's and Delivery's DecisionRef. An untrusted Item gives its decide row, ItemDecision, Notification, card and events with the `no_key` reason. The browser cases assert the no-key sentence, the keyless strip (C15) and the no-decision strip (D14, seeded), B6 runs unconditionally, and a fail-fast reply helper keeps `live:sign-in` inside its deadline. No product code changed, and no Lane A or contended file was touched.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProduction.cls`: the three red tests assert the measured turn, rows, events, Outbound and Delivery; adds the `AdoptTurns` pin.
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls`: the card, text, event, Notification, ItemDecision and the adopted decide row.
- `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls`: `TestRealDecideAfterTheRestore`.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls`: header only.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `AdoptTurns` also records each turn's Decision rows.
- `docker/tests/test-production-restart.sh`: row 20's turns line and new refs line.
- `docker/tests/test-sign-in.sh`: header and the PASS and FAIL lines (D14, B6).
- `web/e2e/api/api.spec.ts`, `chat/chat.spec.ts`, `chat/decision.spec.ts`, `chat/notice.spec.ts`, `trace/links.spec.ts`, `banners/banners.spec.ts`, `support/iris.ts`: the web pins, D14, V2's own later turn, and `decideIsStub` removed.
- This spec: mutation lines, the triage log and this result.

**Review.** Four layers, 19 triage rows. Patches applied: 3 low (V2 made deterministic and its unused helper field dropped; long doc lines rewrapped) and 2 medium (an `AdoptTurns` pin with a recorded mutation; Routing's DecisionRef mutation recorded). Deferred: none. Rejected with reasons: 14 rows, recorded in the Review Triage Log (all low or false: the spec prescribes row 20's line and the 20 s plus 2 s helper window, failing-path-only cleanup, and mutations that would edit Lane A's Decide or swamp the unit).

**Follow-up review recommended:** false. Patched entries by verdict: medium 2, low 3, high 0. Every patch was verified after it landed (mutation red, then the full runs below green), so no unverified risk is named.

**Verification (local ARM, merged tree, tags e2s217i and e2s217iw).**
- `npm --prefix web run lint` exit 0; `npm --prefix web test` 565 passed.
- Warm: ConversationProduction, RoutingProduction and ThreadProduction passed.
- `live production-restart` passed (105 s); `live sign-in` 192 passed, 1 skipped, 411 s for the call (5.7 min of Playwright), inside 540 s.
- (once) `group install-fresh` 282 s, `group install-upgrade` 265 s, `group production` 204 s, `live demo-path` 66 s, `shard lane-a` 381 s (41 classes), `live floor` 225 s, `group image` 260 s (includes `shard lane-b`, 105 s), `shard lane-b --reverse` 100 s (42 classes): all passed. `bash ci/checks.sh` 68 s, `docker/tests/test-web-build.sh` 11 s, `docker/tests/test-mock.sh` 2 s: exit 0.
- Mutations (Rule 19) are recorded under Verification, each reverted with the tree byte-identical. Two deviations from the plan: the ThreadProduction restore mutation turns only the decision-events assertion red (the precheck needs no HostSink), and browser batch 2 ran narrowed (`SetDecision` quits for `no_key` turns) because the planned form swamps the Playwright deadline.
- Teardown of tags e2s217i and e2s217iw left nothing behind.

**Residual risks.** C15's Duration row is matched by pattern (`/^\d+\.\d s$/`), not a fixed value. The api reload's decision-ref pin and the Conversation row-field pins have no mutation of their own (see the triage log). The `ERROR #5003: Not implemented` that `SimPhoneOut` logs is Story 4.5's stub, not this story's.
