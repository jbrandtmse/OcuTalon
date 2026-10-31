---
title: 'Story 16.11: The splash promises Telegram only when the release includes it'
type: 'bugfix'
created: '2026-10-31'
status: 'ready-for-dev'
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

## Design Notes

**Governing architecture decisions:**
- **AD-3:** the public package may reference only `%CSP`, dynamic objects, the allowed `$SYSTEM` members and the two public packages, and it keeps its own copies of the texts it renders, compared with the catalog. So: no `Included()`, no `^OcuTalonTest`, and the new text is a catalog key plus a `Parameter` copy.
- **AD-13:** the splash's envelope. The page's inline style and script do not change, so the CSP hashes hold.
- **AD-19:** its fixed public keys are not touched. No new key, no amendment.
- **AD-29:** `Splash`, `Msg.Catalog.Core` (Lane B's catalog class, where a story adds its keys) and `Test.Web`/`Test.Msg` are all Lane B's. No Lane A file changes.
- **AD-32:** the one renderer. `Test.Msg.Catalog` renders the new key on every channel.
- **AD-22:** tests run on throwaways only.

**Decided in-stage:**
- (1) The splash drops `TELEGRAMLINE` and `LIMITLINE`. The public package keeps its own copies of the texts it renders (AD-3); a parameter that nothing writes would be dead text. Story 12.7 adds a copy and its write together; git holds the old ones. The catalog keys stay unchanged (intent). The public-text check stays consistent: Splash's `compared` map loses two entries and gains one, 41 to 40.
- (2) The names are `splash.limitLineChat` and `LIMITLINECHAT`, each beside its sibling. Neither is user-facing.
- (3) The new entry's `source` is its neighbours' EXPERIENCE path. EXPERIENCE.md:119 already holds the text word for word (U-196), so this is no new public text.
- (4) The browser check is scoped to the Before you start card. `LIMIT_LINE` is re-pointed rather than a new constant added, and `TELEGRAM_LINE` is deleted. No dead constant is left, which matters because `tsconfig.e2e.json` does not flag unused locals.
- (5) No new test method. The assertions extend `TestPage` and `TestEdgeValues`.

**Integration ACs (Rule 1/2):** this story adds no service, module or shared component. It adds one catalog key, whose only consumer is the splash in this story (AC 1). **Consumes:** `OcuTalon.Data.Public.Settings.Get("messageAllowance")` (Story 16.1). **Consumed-by:** none. Story 12.7 owns the "Telegram included" case and decides whether `splash.limitLineChat` stays.

**Extend, don't copy:** the chat-only write replaces the existing limit write in place, with the same replacement and escaping. The catalog entry copies `splash.limitLine`'s shape. Nothing is near-copied.

**Inbox (Rule 17):** this story owns no ledger entries. DW-501, the allowance banner's "chat or Telegram", is out of scope (routed to Story 12.7).

**Footprint:**
- Inside Epic 16's `paths_hint`: `Web/Public/Splash.cls` and `Test/Web/**`.
- Footprint extensions, as the ruling and the AC direct: `Msg/Catalog/Core.cls` (also in the hints of Epics 18, 21, 24, 27 and 40), `Test/Msg/Catalog.cls`, and `web/e2e-online/splash.spec.ts`.
- Merge hotspot: the key counts in `Test.Msg.Catalog`.

## Verification

**Targets and variables:**
- Run every command from the Epic 16 worktree root (`git rev-parse --show-toplevel`), in the foreground, with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- `LANE_B` below stands for the prefix `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=16 stage=<implement|qa|review>'` (the running stage's name). It goes on every `ci/iris.sh` and `ci/warm.sh` call.
- Tags: implement `e16s11i`/`e16s11iw`; QA `e16s11q`/`e16s11qw`; review `e16s11r`/`e16s11rw`. Each stage tears down only its own tags.
- MCP calls, if any: `server: ocutalon-slot-b`, `namespace: OCUTALON`, after `iris_server_info` shows build 154 and port 1991. One `iris_execute_tests` per message.

**Commands:**
- (loop) `LANE_B OCUTALON_RUN_TAG=e16s11iw bash ci/warm.sh up` -- run once, at the stage's start.
- (loop) `LANE_B OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s11iw bash ci/iris.sh class <Class>` -- one call per class: `OcuTalon.Test.Web.Splash`, `OcuTalon.Test.Web.PublicTexts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Web.SignIn`. Expected: `WARM reloaded`, then `CLASS ... passed`.
- (loop) `LANE_B OCUTALON_RUN_TAG=e16s11iw bash ci/warm.sh down` -- at the stage's end, also after a failure.
- (once) `npm --prefix web run lint` -- `tsc` passes over `e2e-online/`.
- (once) `node --test web/scripts/catalog.test.mjs` -- passes; "has a current catalog.ts" included.
- (once) `bash ci/checks.sh` -- every block passes (`boundaries` and `class-rules` included).
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh build` -- rebuilds the bundle before the browser unit.
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh live online-demo` -- PASS, with S2 on the new list. Measured locally at 364-422 s.
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh teardown` -- leaves nothing tagged `e16s11i`.
- **Left to the lead and CI:** the lead's fresh-environment check (Rule 19: `shard lane-b` forward and `--reverse`) and every other CI group.

**Shared surfaces:**
- The Before you start list: `Test.Web.Splash` `TestPage` and `TestEdgeValues`; `web/e2e-online/splash.spec.ts` S2.
- Splash's own parameters: `Test.Web.Splash` `TestTexts`; `Test.Web.PublicTexts` `Classified` and its two counts (41 to 40).
- The catalog's key list, fixtures and counts: `Test.Msg.Catalog` XData `Keys` and `Fixtures`, 94 to 95 and 116 to 117.
- Unchanged: the web catalog module `web/src/app/msg/catalog.ts`, which `web/scripts/catalog.mjs` generates from an allowlist with no `splash.*` key, and the tests that pin it (`web/scripts/catalog.test.mjs` "has a current catalog.ts", and `docker/tests/test-web-build.sh`'s `catalog.mjs --check`). The `web` job reruns, because `Msg/Catalog/Core.cls` matches `WEB_INPUT_PATTERN`. No CI unit or group changes.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and their mutations** (the implement stage writes each `mutation:` line):
- AC 1: `Test.Web.Splash.TestPage`. Mutation: write a `<li>Have Telegram?</li>` item before the limit item; `TestPage` must go red. S2 is the real-browser check of the same list.
- Matrix row 2: `Test.Web.Splash.TestEdgeValues`. Mutation: drop the `If limit '= ""` guard; it must go red.
- AC 2: `Test.Web.PublicTexts.TestCopiesEqualTheCatalog`. Mutation: drop the final "." of `LIMITLINECHAT`; it must go red. The kept keys are pinned by `Test.Msg.Catalog.TestEveryKeyOnEveryChannel`. Mutation: change one word of `splash.limitLine`; it must go red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
