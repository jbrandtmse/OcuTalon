---
title: 'Story 16.11: The splash promises Telegram only when the release includes it'
type: 'bugfix'
created: '2026-10-31'
status: 'done'
baseline_revision: 'a1047eef21a0eedb7ed4ac58bf2effa8e994993b'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, lines 128-157; AD-13, 396-447; AD-29, its catalog bullet at 951)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (read only Story 16.11, lines 5007-5025)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo, the splash's "Before you start" list says "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram." A signed-in visitor finds no Telegram and no QR code: Telegram arrives with Epic 12. The splash cannot follow `OcuTalon.Channel.Telegram.In.Included()` (AD-3's allow-list bars the public package from naming that class), and a public key carrying it would amend AD-19, which is the owner's call.

**Approach:** The orchestrator's ruling (veto U-197), option (C): the splash leaves out the Telegram line and shows, unconditionally, the chat-only allowance line "Each session can send {limit} messages an hour in the chat.", from a new catalog key of its own beside `splash.limitLine`. `splash.telegramLine` and `splash.limitLine` keep their current text for Story 12.7, which adds the "Telegram included" case (the orchestrator routes it there). No gate, no new public key, no AD change.

## Boundaries & Constraints

**Always:**
- The new catalog key's text is exactly "Each session can send {limit} messages an hour in the chat.", slot `limit` of kind `count`, with the same `source` form as its neighbours; the splash's copy of it is a `Parameter` that matches the catalog word for word (the public-text check pins it). No user-facing text written in code.
- `splash.telegramLine` and `splash.limitLine` stay in the catalog, unchanged.
- The "Before you start" list renders, in order: the reset line, the own line, the chat-only allowance line (only when `messageAllowance` is set, as today), the shell line.
- Tests go into the splash's existing test classes and pin both: no Telegram line in the list, and the chat-only allowance line; the splash's existing tests, the catalog tests and the public-text checks stay green. Every test creates and removes the state it asserts on (Rule 19).

**Never:**
- No Lane A file (nothing under `Install/Step/`, nothing under `Channel/Telegram/`), no call to `Included()`, no reference to `^OcuTalonTest` outside the tests, no new public setting key, no AD amendment.
- No new test class and no new CI unit; no change to the splash's inline style or script (AD-13's hashes stay), the footer, or the local sign-in page.
- No other wording change, the allowance banner included (DW-501, routed to Story 12.7).
- No absolute local path in any tracked file, this spec included (`docker/tests/test-boundaries.sh` scans every tracked file).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Online demo, allowance set | flag on, `messageAllowance` 50 | facts list: reset, own, `<li>Each session can send 50 messages an hour in the chat.</li>`, shell; nothing inside `<ul class="facts">` says "Telegram" or "QR" | No error expected |
| No allowance | flag on, `messageAllowance` "" | no allowance line of either form, and no Telegram line | No error expected |
| Flag off | local install | the local sign-in page renders unchanged | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` -- Lane B. `Parameter TELEGRAMLINE` (:55) and `LIMITLINE` (:57). `OnLoginPage`'s facts list (:196-203): the Telegram item at :199, written unconditionally; the limit item at :200-201, `$Replace(..#LIMITLINE, "{limit}", <HTML-escaped messageAllowance>)`, only when `messageAllowance` is set. The class comment (:17-20, "its own texts are parameters, each equal to a splash.* catalog key") and `OnLoginPage`'s comment (:135-136, "no allowance leaves out the limit line") stay true unchanged.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:499-508` -- `splash.telegramLine`, `splash.limitLine`. The renderer reads the XData on every call and never caches it (`Msg/Catalog.cls:77`), so a warm reload sees the new key.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` -- `TestTexts` pairs (:29-30); `TestPage` (:147-148 pin both old lines); `TestEdgeValues` (:404 and :412 match the chat-only line as well; :413 asserts `<li>Have Telegram?`); `OnBeforeOneTest` (:604-619) sets `messageAllowance` 50 and `OnAfterOneTest` restores every key; helpers `Page` (:664), `Count` (:651). In the rendered page, `!` is `$Char(10)` (see :140).
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- XData `Classified`, Splash's `compared` map (`TELEGRAMLINE`, `LIMITLINE` at :158-159); the count 41 is asserted at :39 and :82. An own parameter missing from the lists, or a listed one the class lacks, fails `TestEveryParameterIsClassified`.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- header :3 ("94 keys"); `TestEntries` :80-82 (94); `TestEveryKeyOnEveryChannel` :121 (message "116 keys"); XData `Keys` (:1039-1040) and `Fixtures` (:1271-1272). `Problems` requires key `^[a-z][A-Za-z]*\.[a-z][A-Za-z0-9]*$` and an ASCII `source`. The new entry has no `one` form, so `OneForms` (8) is unchanged.
- `web/e2e-online/splash.spec.ts` -- `TELEGRAM_LINE`, `LIMIT_LINE` (:52-53); S2 asserts both visible (:218-219); S2's header bullet (:22-23). It runs in `live:online-demo` (group `install-fresh`). The Before you start card is `<section aria-labelledby="ocu-before-h">`, so `getByRole('region', { name: 'Before you start', exact: true })` finds it (S2 finds the Visual Trace card the same way).
- `web/scripts/catalog.mjs` / `web/src/app/msg/catalog.ts` -- an allowlist of the keys the page renders, with no `splash.*` key: no change. `catalog.test.mjs` "has a current catalog.ts" stays green.
- Read only, the reasons for the ruling: `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls:332-370` (AD-3's allow-list scan, so no `Included()`), and `docker/tests/test-boundaries.sh` (no `^OcuTalonTest` outside the tests and `In.cls`; no local machine path in any tracked file).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- right after `splash.limitLine`, add `"splash.limitLineChat": {"text": "Each session can send {limit} messages an hour in the chat.", "slots": {"limit": "count"}, "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"}`. Leave `splash.telegramLine` and `splash.limitLine` as they are -- the chat-only text gets its own key.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` -- replace `Parameter TELEGRAMLINE` and `Parameter LIMITLINE` with `Parameter LIMITLINECHAT = "Each session can send {limit} messages an hour in the chat.";`. In `OnLoginPage`, delete the Telegram `Write` (:199) and write the limit item from `..#LIMITLINECHAT`, with the same `{limit}` replacement, escaping and `If limit '= ""` rule. Nothing else changes -- AC 1.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- in Splash's `compared` map, replace the `TELEGRAMLINE` and `LIMITLINE` lines with `"LIMITLINECHAT": "splash.limitLineChat"`. Change 41 to 40 in both assertions and their messages (:39, :82) -- AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- add `"splash.limitLineChat"` after `"splash.limitLine"` in XData `Keys`. Add `"splash.limitLineChat": {"slots": {"limit": 50}, "text": "Each session can send 50 messages an hour in the chat."}` after `splash.limitLine`'s line in XData `Fixtures`. Change 94 to 95 (:3, :80 twice, :82) and 116 to 117 (:121) -- a shared-surface update, AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` -- matrix rows 1 and 2:
  - `TestTexts`: replace the `TELEGRAMLINE` and `LIMITLINE` pairs with `LIMITLINECHAT` and its exact text.
  - `TestPage`: replace :147-148. Take `facts` = the text between `<ul class="facts">` and `</ul>`, then assert: 4 `<li>`; no "Telegram"; no "QR"; and `"<li>Your chat, phone, mailbox and orders are yours alone.</li>"_$Char(10)_"<li>Each session can send 50 messages an hour in the chat.</li>"_$Char(10)_"<li>OcuTalon can't run shell commands, and every action it takes is recorded in the IRIS audit log.</li>"`, in that order (the reset line before them is already pinned).
  - `TestEdgeValues` :413: with `messageAllowance` "", assert the same `facts` holds 3 `<li>`, the own line, and no "Telegram".
- `web/e2e-online/splash.spec.ts` -- delete `TELEGRAM_LINE`. Set `LIMIT_LINE` to `'Each session can send 50 messages an hour in the chat.'`. In S2, replace the Telegram assertion with the Before you start region: `li` count 4, `not.toContainText('Telegram')`, `not.toContainText('QR')`. Keep the `LIMIT_LINE` visibility check. Add "no Telegram line" to S2's header bullet -- the real page (Rule 3).

**Acceptance Criteria:**
- AC 1: Given the online-demo flag on and an allowance of 50, when the splash renders "Before you start", then the list is the reset line, "Your chat, phone, mailbox and orders are yours alone.", "Each session can send 50 messages an hour in the chat." and the shell line, in that order, and none of them says "Telegram" or "QR". This holds in process and in a real browser on the `online-demo` throwaway's flag-on start.
- AC 2: Given the catalog, when `Test.Web.PublicTexts` and `Test.Msg.Catalog` run, then `LIMITLINECHAT` equals `splash.limitLineChat`, the key renders "Each session can send 50 messages an hour in the chat." on every channel, and `splash.telegramLine` and `splash.limitLine` still render their current texts word for word.
- AC 3: Given the splash, public-text and catalog test classes, when run on a fresh stack in either order, then every one passes, and the flag-off sign-in page tests (`Test.Web.SignIn`, `Test.Web.Splash.TestShowFollowsTheFlag`) pass unchanged (matrix row 3).

## Spec Change Log

- 2026-10-31, lead (runner B), re-plan after plan round 1 (blocked: AD-3 bars the splash from `Channel.Telegram.In`; a `telegramIncluded` public key would amend AD-19). The orchestrator ruled option (C) (veto U-197): no gate; the splash drops the Telegram line and shows the chat-only allowance line unconditionally, from its own catalog key; touch no Lane A file and do not call `Included()`; the "Telegram included" case moves to Story 12.7 (the orchestrator routes it). The intent block was rewritten to that ruling; the round-1 design below (the public key, the Public step, the Lane A tests) is superseded and must not be built. The deferred allowance-banner item was filed by the lead as DW-501, routed to Story 12.7.

## Review Triage Log

### 2026-10-31 - Review pass
- verdicts: 10 findings - high 0, medium 1, low 4, false 5, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: `splash.telegramLine` and `splash.limitLine` stay in the catalog with no marker - the intent keeps them unchanged for Story 12.7; the XData is JSON and holds no comments, and a marker field would change the catalog's shape. Not a defect of this change.
  - `[low]` `[reject]` Blind: the order assertion joins the lines with a literal line feed - the spec (Tasks) names this exact form, and `Write ... !` ends lines with one line feed throughout the page tests; a position-based order check is more than a correction.
  - `[low]` `[reject]` Blind: the "Telegram" and "QR" absence checks are case-sensitive - the spec's matrix words them as these exact strings; the four-line count and the exact-order assertion bound the list.
  - `[false]` `[reject]` Blind: no real-browser check of the three-line (no allowance) case - the online demo starts with the allowance set, so the browser cannot show it; the spec names `TestEdgeValues` as the pin of matrix row 2.
  - `[false]` `[reject]` Blind: `banner.allowance` still says "chat or Telegram" - the intent excludes it by name (DW-501, routed to Story 12.7).
  - `[low]` `[patch]` Verification-gap: S2 (the browser half of AC 1) has no `mutation:` line - applied the Telegram-item mutation, `live online-demo` went red on S2 only, reverted, clean run green; line written.
  - `[low]` `[patch]` Verification-gap: the new key's catalog text and `splash.telegramLine` have no mutation of their own - both applied, `Test.Web.PublicTexts` and `Test.Msg.Catalog` went red, reverted; lines written.
  - `[medium]` `[patch]` Verification-gap (order mutation, found by running it): the "in that order" assertion in `TestPage` could not fail because the concatenation sat unparenthesised on the right of `[` (ObjectScript evaluates left to right), so shell-before-allowance still passed - parenthesised the expected text, re-ran the mutation (red), reverted it, the class is green.
  - `[false]` `[reject]` Verification-gap: AC 3 has no mutation line - AC 3 is a run-condition AC (fresh stack, either order) that the Verification section leaves to the lead's `shard lane-b` forward and `--reverse` runs; no test of this story pins it.
  - `[false]` `[reject]` Verification-gap: the spec's `## Auto Run Result

Status: done
Blocking condition: none

**Summary:** The splash's "Before you start" list no longer has a Telegram line, and the allowance line is, unconditionally (when `messageAllowance` is set), the chat-only text from the new catalog key `splash.limitLineChat`. `splash.telegramLine` and `splash.limitLine` stay in the catalog unchanged. No Lane A file, no `Included()`, no new public key.

**Files changed:**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: the new key `splash.limitLineChat` beside `splash.limitLine`.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`: `TELEGRAMLINE` and `LIMITLINE` replaced by `LIMITLINECHAT`; the Telegram `Write` deleted; the allowance item reads `LIMITLINECHAT`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls`: `TestTexts`, `TestPage` (four lines, no Telegram, no QR, exact order) and `TestEdgeValues` (three lines, no Telegram).
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`: Splash's `compared` map and its count, 41 to 40.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: the key in `Keys` and `Fixtures`; counts 94 to 95 and 116 to 117.
- `web/e2e-online/splash.spec.ts`: S2 checks the Before you start list (four items, no Telegram, no QR) and the chat-only limit line.

**Review findings:** 10 reported, 3 patched (2 low, 1 medium: the order assertion in `TestPage` could not fail until parenthesised), 0 deferred, 7 rejected (5 false, 2 low) with the reasons in the triage log above. Follow-up review recommended: false (one medium patched, no high).

**Verification performed:** warm runs of `Test.Web.Splash`, `Test.Web.PublicTexts`, `Test.Msg.Catalog` and `Test.Web.SignIn` passed (the last three unchanged since their pass, the first rerun after the final patch); `npm --prefix web run lint` passes; `node --test web/scripts/catalog.test.mjs` 52 of 52; `bash ci/checks.sh` all scripts passed; `ci/iris.sh live online-demo` passed (50 specs, S2 on the new list; the unit prints one "No such file" line from its busy-jar step in an untouched script, and its checks all pass). Each mutation line above was applied, observed red and reverted. All throwaway and warm stacks of tags e16s11i and e16s11iw are removed; the lane-b lock folder is empty.

**Residual risks:** the lead's fresh-environment check (`shard lane-b` forward and `--reverse`) and the other CI groups are not run here. The allowance banner still says "chat or Telegram" (DW-501, routed to Story 12.7).
