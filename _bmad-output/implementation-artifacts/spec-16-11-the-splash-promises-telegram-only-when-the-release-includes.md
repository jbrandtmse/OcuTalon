---
title: 'Story 16.11: The splash promises Telegram only when the release includes it'
type: 'bugfix'
created: '2026-10-31'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, lines 128-157; AD-13, 396-447; AD-19, 572-630, its public-settings bullets at 625-628; AD-23, 759-804; AD-29, 925-972, its Lane A bullet at 949 and its Test/catalog bullet at 951; AD-33, 1025-1035)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (read only Story 16.11, lines 5007-5025)'
warnings: ['oversized']
deferred:
  - summary: >-
      The allowance banner (catalog banner.allowance) also promises Telegram on the online demo: "You've used this session's {limit} messages for the hour (messages you send in the chat or Telegram)." Story 16.11 covers the splash only.
    evidence: |-
      src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:268 and web/src/app/msg/catalog.ts:11 carry the text unconditionally; web/e2e-online/allowance/messages.spec.ts:35 and web/e2e/banners/banners.spec.ts:359,501 pin it. With Included() at 0 a visitor who uses up the 50 messages reads "or Telegram" on a page with no Telegram.
    location: src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:268
    severity: low
---

<intent-contract>

## Intent

**Problem:** On the online demo, the splash's "Before you start" list always says "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram." A signed-in visitor finds no Telegram and no QR code, because Telegram arrives only with Epic 12 (Story 12.7 turns `OcuTalon.Channel.Telegram.In.Included()` on).

**Approach:** Give the splash a value that follows `Included()`, through the only door AD-3 leaves open to a page that runs with no roles: one more public setting, `telegramIncluded`. The Public install step writes it at every flag-on start from `Included()`. The splash reads it through `OcuTalon.Data.Public.Settings`. With it unset, the splash leaves out the Telegram line and shows a new catalog line, "Each session can send {limit} messages an hour in the chat." With it at 1, both of today's lines show word for word.

## Boundaries & Constraints

**Always:**
- Copy the three texts word for word: `splash.telegramLine` "Have Telegram? You can scan a QR code inside to get the notices on your own phone.", `splash.limitLine` "Each session can send {limit} messages an hour in the chat or Telegram." (both unchanged) and the new `splash.limitLineChat` "Each session can send {limit} messages an hour in the chat." (slot `limit`, kind `count`, the same `source` as its neighbours). `{limit}` stays the `messageAllowance` public setting, HTML-escaped.
- The splash reads public values only through `OcuTalon.Data.Public.Settings.Get` (AD-3, AD-19). It never references `OcuTalon.Channel.Telegram.In` or `^OcuTalonTest`.
- The list keeps its order: reset line, own line, Telegram line (only when included), limit line, shell line. No allowance means no limit line in either state.
- `telegramIncluded` holds `1` or is removed (`""`). Any stored value other than `1` reads as not included.
- The Public step writes `telegramIncluded` only on the flag-on path, after every start value has been accepted. A refused start writes nothing, and a local start still changes only `onlineDemo`.
- Every test that flips the switch saves and restores both the switch (`OcuTalon.Test.Data.Fixture.SetTelegramIncluded`) and the public keys itself.

**Never:**
- Never edit `OcuTalon.Channel.Telegram.In` (Lane A, AD-33; Epic 12 edits it live). Call `Included()` only.
- No new test class, no new CI unit, no change to the splash's inline style or script (AD-13's hashes stay), the footer, or the local sign-in page.
- No other wording change, including the allowance banner (see `deferred:`).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Not included | switch 0, Public step's write run, `messageAllowance` 50 | facts list: reset, own, `<li>Each session can send 50 messages an hour in the chat.</li>`, shell; the page holds no "Have Telegram?" and no "Telegram" inside `<ul class="facts">` | No error expected |
| Included | switch 1, the write run, allowance 50 | `<li>Have Telegram? You can scan a QR code inside to get the notices on your own phone.</li>` directly followed by `<li>Each session can send 50 messages an hour in the chat or Telegram.</li>`; no chat-only form | No error expected |
| No allowance | either state, `messageAllowance` "" | no limit line of either form; the Telegram line follows the state | No error expected |
| Stale value | `telegramIncluded` "0" or "x" | rendered as not included | No error expected |
| Flag-on start | `OCUTALON_ONLINE_DEMO=1`, switch 0, then 1 | `Run()` OK; `telegramIncluded` reads "", then "1" | A refused start value leaves `telegramIncluded` as it was |
| Local start | flag unset, `telegramIncluded` "stale" | only `onlineDemo` changes (to 0); the local sign-in page is unchanged | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` -- Lane B. `Parameter TELEGRAMLINE` (:55) and `LIMITLINE` (:57) are the catalog copies; `OnLoginPage` writes the Telegram line unconditionally at :199 and the limit line at :200-201. The class comment (:17-20) says every value comes from `Data.Public.Settings`.
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- Lane B (AD-19). `Parameter KEYS` (:9) is the fixed list; `Get` returns "" for a key never set, `Set(key, "")` removes it.
- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls` -- Lane A (AD-29's "`Public` step"). `Run()` (:37-60): `ClearReady`, then `RunLocal` for any flag value but "1", then `StartValues` (checks all values first), `onlineDemo` 1, then the `VARIABLES` loop. The class comment (:1-15) counts "the twelve other public keys".
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:20-23` -- `Included()`: `$Get(^OcuTalonTest("TelegramIncluded")) = 1`. Read only. Its other callers are `Web/Api.cls:677,766` (`/state`'s `telegram.included`), `Demo/Guide.cls:207` and `Core/Rule/Functions.cls:32`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:177-183` -- `SetTelegramIncluded(value)` sets the switch and returns the old value (0 when unset). Epic 12's tests and `web/e2e/support/iris.ts:1041` use it.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:499-508` -- `splash.telegramLine` and `splash.limitLine` entries; the new key goes right after `splash.limitLine`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls:332-370` -- `TestReferencesOnlyThePublicAllowList`, AD-3's scan of both public packages (`##class`, `$SYSTEM`, dynamic dispatch, supers, types). This is why the splash cannot call `Included()`.
- `docker/tests/test-boundaries.sh:8-9,65-75,255` -- `^OcuTalonTest` may be read only in `Channel/Telegram/In.cls` and set only by tests. This is why the splash cannot read the global.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` -- `TestTexts` list (:29-30), `TestPage` (:147-148 pin both lines), `TestEdgeValues` (:413 asserts `<li>Have Telegram?` stays), `OnBeforeOneTest` (:604-619 saves every `KEYS` key and sets the fixtures), `OnAfterOneTest` (:621-632), `Page("", "", "")` (:664) renders.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls:142-177` -- XData `Classified`, `compared` map for Splash (`TELEGRAMLINE`, `LIMITLINE` at :158-159). An unclassified parameter fails.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- XData `Keys` (:952, `splash.limitLine` at :1040) lists every key; XData `Fixtures` (:1185, `splash.limitLine` at :1272) renders every key.
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:43` -- pins `KEYS` as a literal.
- `src/ocutalon/cls/OcuTalon/Test/Install/Public.cls` -- Lane A. It saves and restores every `KEYS` key and readiness (:91-130), sets start variables with `Use({...})`, and runs `Run()` in process (throwaways and CI only). `TestBadStartValues` (:220-261) and `TestFlagOffWritesOnlyTheFlag` (:263-299) iterate `KEYS`, so they cover the new key unchanged. The header counts "the 13 keys" (:11).
- `web/e2e-online/splash.spec.ts:52-53,218-219` -- S2 pins both lines on the `online-demo` unit's flag-on throwaway, where `Included()` is 0. This file is in no epic's `paths_hint`.
- `web/src/app/msg/catalog.ts` / `web/scripts/catalog.mjs` -- the page module holds an allowlist of keys with no `splash.*` key, so it does not change; `catalog.test.mjs` "has a current catalog.ts" stays green.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- add `"splash.limitLineChat": {"text": "Each session can send {limit} messages an hour in the chat.", "slots": {"limit": "count"}, "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"}` right after `splash.limitLine` -- the third text, from the catalog (AC 3).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- append `telegramIncluded` to `KEYS`, and name it in the class comment if the comment lists keys -- the splash's only door (AD-3, AD-19 as amended).
- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls` -- add a `ClassMethod Telegram() As %Status` that writes `telegramIncluded` through the accessor: `1` when `##class(OcuTalon.Channel.Telegram.In).Included()`, else `""`. Call it from `Run()` after the `VARIABLES` loop, only when `sc` is OK. Update the class comment ("thirteen other public keys", and say `telegramIncluded` comes from `Included()`, not from a variable) -- the start copies the switch (AD-19, AD-23).
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` -- add `Parameter LIMITLINECHAT = "Each session can send {limit} messages an hour in the chat.";` after `LIMITLINE`. In `OnLoginPage`, read `included = (Settings.Get("telegramIncluded") = 1)`. Write the `TELEGRAMLINE` item only when included. Write the limit item from `LIMITLINE` when included, else from `LIMITLINECHAT`, with the same `{limit}` replacement and the same "no allowance, no line" rule. Extend the class comment and `OnLoginPage`'s comment by one clause each -- AC 1, AC 2.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- add `"LIMITLINECHAT": "splash.limitLineChat"` to Splash's `compared` map -- the copy equals the catalog (AC 3).
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- add `"splash.limitLineChat"` after `"splash.limitLine"` in XData `Keys`, and `"splash.limitLineChat": {"slots": {"limit": 50}, "text": "Each session can send 50 messages an hour in the chat."}` after it in XData `Fixtures` -- shared-surface update.
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls` -- extend the `KEYS` literal at :43 with `,telegramIncluded` -- shared-surface update.
- `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls`:
  - `TestTexts`: add `LIMITLINECHAT` with its exact text.
  - `OnBeforeOneTest`: add `$ListBuild("telegramIncluded", "")` to the fixture values, so every test starts not included; the existing save and restore covers the key.
  - `TestPage`: replace :147-148 with the not-included lines (no Telegram item, the chat-only item).
  - `TestEdgeValues` :413: assert the own line stays instead of `Have Telegram?`.
  - Add `TestTelegramNotIncluded` and `TestTelegramIncluded` (matrix rows 1-4). Each one: `Set was = ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(<0|1>)`, `Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Public).Telegram())`, render `..Page("", "", "")`, assert the exact items and their order inside `<ul class="facts">`, then `Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(was)`. Row 3 runs inside each, with `messageAllowance` "". Row 4 (`"0"`, `"x"`) goes in `TestTelegramNotIncluded`.
  - Update the class comment by one line.
- `src/ocutalon/cls/OcuTalon/Test/Install/Public.cls` -- add `TestTelegramFollowsTheSwitch` (matrix rows 5-6): flag-on `Use` with the four account variables. Switch 0, then `Run()` gives `telegramIncluded` "". Switch 1, then `Run()` gives "1". Restore the switch in the method. Change the header's "13 keys" to "14 keys" -- the start path, which the splash tests reach only through `Telegram()`.
- `web/e2e-online/splash.spec.ts` -- in S2, add `const LIMIT_LINE_CHAT = 'Each session can send 50 messages an hour in the chat.'` and assert it visible. Assert `getByText(TELEGRAM_LINE)` has count 0, and the Before you start card holds no text matching `/Telegram/`. Remove `LIMIT_LINE` if nothing uses it any more, so no dead constant is left (`tsconfig.e2e.json` does not set `noUnusedLocals`, so `tsc` will not catch it). Update the S2 header line -- the real page on the online demo's start, where `Included()` is 0 (Rule 3).

**Acceptance Criteria:**
- AC 1: Given a release whose `Included()` returns 0 and a flag-on start, when the splash renders "Before you start", then it shows no Telegram line, and the allowance line reads "Each session can send 50 messages an hour in the chat." (in process and in the real browser on the `online-demo` throwaway).
- AC 2: Given `Included()` returns 1 through the test-only switch and the Public step's write has run, when the splash renders, then it shows "Have Telegram? You can scan a QR code inside to get the notices on your own phone." followed by "Each session can send 50 messages an hour in the chat or Telegram.", word for word.
- AC 3: Given the catalog, when `Test.Web.PublicTexts` and `Test.Msg.Catalog` run, then `TELEGRAMLINE`, `LIMITLINE` and `LIMITLINECHAT` equal `splash.telegramLine`, `splash.limitLine` and `splash.limitLineChat`, and the splash holds no other copy of these texts.
- AC 4: Given every existing splash, public-settings, Public-step and catalog test, when run on a fresh stack in either order, then each passes. `Test.Web.Status.TestReferencesOnlyThePublicAllowList` still passes for `Splash` and `Settings`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing architecture decisions:**
- **AD-3:** the public package may reference only `%CSP`, dynamic objects, `$SYSTEM.License`/`.Status`/`.Encryption` and the two public packages. The splash therefore cannot call `Included()`. The public database holds only the two packages and `^OcuTalonPublic`.
- **AD-19:** public settings live only in `^OcuTalonPublic`, through `Data.Public.Settings`; "the keys are fixed" (a list); one structural step, `Install.Step.Public`, writes them at every start. This plan adds a key, which amends AD-19's Rule. That is the first blocking item below.
- **AD-13:** the splash's envelope. No style or script changes, so the CSP hashes hold.
- **AD-23:** the Public step runs at every start, right after the bridge installer.
- **AD-29 and AD-33:** `Install.Step.Public` and `Test.Install` are Lane A's; `Splash`, `Data.Public.Settings`, `Msg.Catalog.Core` and `Test.Web`/`Test.Data`/`Test.Msg` are Lane B's. `Channel.Telegram.In` is Lane A's (call only). "Only the owning lane edits a class": the second blocking item below.
- **AD-22:** tests run on throwaways.

**Why a start-time copy (and why the story's planned scope cannot hold).** The lead's brief and the epic's dependency note say "Splash.cls and the catalog lines only, call `Included()`". The epic context already flagged this as an open point. Measured in the code:
- `TestReferencesOnlyThePublicAllowList` fails any `##class(OcuTalon.Channel.Telegram.In)` in `OcuTalon.Web.Public`, generators included.
- `test-boundaries.sh` fails any read of `^OcuTalonTest` outside `In.cls` and the tests.
- The visitor has no roles, so code or globals outside `OCUTALON_PUBLIC` would also be refused at run time `(inference: AD-3's "public Read" applies to OCUTALON_PUBLIC only; not measured)`.

That leaves `^OcuTalonPublic`, and its keys are written by Lane A's Public step. `Included()` changes only with the code, which an upgrade brings and every start re-runs. So a copy taken at every start always equals `Included()` on a real host. A test that flips the switch mid-run re-runs the copy (`Public.Telegram()`). This is the difference from `/state`, which reads `Included()` live. Story 12.7 needs no splash change.

**Alternatives rejected:**
- Amend AD-3 so the splash may call `Included()`: this grants the no-role page code outside the public database (veto, privileges), and puts a Lane A class into the public package's closure.
- Have Story 12.7 edit the splash: this breaks AC 2's "through the test-only switch" and 12.7's "no further change".
- Read `^OcuTalonTest` directly: `test-boundaries.sh` forbids it, and it would be a second definition of "included".

**Consumes:** `OcuTalon.Channel.Telegram.In.Included()` (Lane A, read only); `OcuTalon.Data.Public.Settings` (Get/Set). **Consumed-by:** Story 12.7. When it turns `Included()` on, the next start writes `telegramIncluded` 1 and the splash shows both Telegram lines. **Integration AC:** matrix rows 1-2 pin the consumer: `Splash` reads the key that `Public.Telegram()` wrote from the real switch and shows the lines. AC 1's browser check runs on a real flag-on start.

**Extend, don't copy:** `LIMITLINECHAT` follows `LIMITLINE`'s `{limit}` replacement in the same `Write`. `Telegram()` is one accessor call, written like the `VARIABLES` loop's public writes. The two new splash tests reuse `Page`, `OnBeforeOneTest`'s save and restore, and `Fixture.SetTelegramIncluded`. No near-copy.

**Decided in-stage:**
- (1) Key names `splash.limitLineChat`, `LIMITLINECHAT` and `telegramIncluded`. Each sits beside or after its sibling, and none is user-facing.
- (2) `telegramIncluded` is `1` or removed, matching `onlineDemo`'s "1" test.
- (3) The local path does not write it: the splash never renders there, and `TestFlagOffWritesOnlyTheFlag` pins "only onlineDemo changes".
- (4) The real-browser check covers the not-included state only, the launch state. The included state is pinned in process, because turning it on in the `online-demo` unit would need edits to `docker/tests/**` (contended: Epics 13 and 15).
- (5) The new catalog line's `source` is the neighbours' `EXPERIENCE` path. EXPERIENCE.md gains the text through U-196.
- (6) The AC's "0.1.0/0.1.1" reads 1.0.0. Nothing here depends on the release name.

**Declined DW:** none (the inbox was empty).

**Footprint:**
- Inside Epic 16's `paths_hint`: `Web/Public/Splash.cls`, `Data/Public/Settings.cls`, `Test/Web/**` and `Test/Data/**`.
- Outside it: `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls`, Lane B's catalog, which the story names. `web/e2e-online/splash.spec.ts` is in no live epic's glob. These are footprint extensions to report.
- Contended: `Install/Step/Public.cls` (Epic 15 `Install/**`, Epic 11) and `Test/Install/Public.cls` (Epic 30 `Test/{...Install...}/**`, Epic 11). Rule 11 (c) applies; this is the second blocking item.
- No CI unit or group changes. The splash, catalog, settings and public-texts tests sit in `shard:lane-b` (group `image`, 5 units). `Test.Install.Public` sits in `shard:lane-a@Checks,Install,Watch` (group `shards`, 3 units). `splash.spec.ts` runs in `live:online-demo` (group `install-fresh`, 4 units). `Msg/Catalog/Core.cls` matches `WEB_INPUT_PATTERN`, so the `web` job reruns, with no change to `catalog.ts`.

## Verification

**Targets and variables:**
- Run every command from the Epic 16 worktree root (`git rev-parse --show-toplevel`), in the foreground, with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- Lane B: every `ci/iris.sh` and `ci/warm.sh` call is prefixed with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=16 stage=<stage>'`, written below as `LANE_B`.
- Tags: implement `e16s11i`/`e16s11iw`; QA `e16s11q`/`e16s11qw`; review `e16s11r`/`e16s11rw`. Each stage tears down only its own tags.
- MCP calls, if any: `server: ocutalon-slot-b`, `namespace: OCUTALON`, after `iris_server_info` confirms build 154 and port 1991. `Test.Install.Public` runs only in throwaways, never on the slot.

**Commands:**
- (loop) `LANE_B OCUTALON_RUN_TAG=e16s11iw bash ci/warm.sh up` -- once, at the stage's start.
- (loop) `LANE_B OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s11iw bash ci/iris.sh class <Class>` -- one call per class, each `CLASS ... passed` after a `WARM reloaded` line: `OcuTalon.Test.Web.Splash`, `OcuTalon.Test.Web.PublicTexts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Data.PublicSettings`, `OcuTalon.Test.Web.Status`, `OcuTalon.Test.Install.Public`.
- (loop) `LANE_B OCUTALON_RUN_TAG=e16s11iw bash ci/warm.sh down` -- at the stage's end, also after a failure.
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e-online/`.
- (loop) `bash ci/checks.sh` -- every block passes (`boundaries`, `class-rules`, `readme`, `ci-config`).
- (once) `npm --prefix web test` -- passes, `catalog.test.mjs` included.
- (once) `bash docker/tests/test-web-build.sh` -- passes; `catalog.mjs --check` leaves the tree clean.
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh build`, then `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh live online-demo` -- PASS, S2 with the chat-only line and no Telegram line. The fresh start proves the Public step's change. Expected under 8 minutes (CI: about 593 s on the slower x64 hosts).
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh class OcuTalon.Test.Install.Public` -- passes on a fresh stack.
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh shard lane-b --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- every class passes (about 4 minutes each).
- (once) `LANE_B OCUTALON_RUN_TAG=e16s11i bash ci/iris.sh teardown` -- nothing tagged `e16s11i` is left.
- **Left to CI:** install-fresh's other units, install-upgrade, production, browser, shards (lane-a's other classes, floor, online-session), shards-2, and image's other units.

**Shared surfaces:**
- `Data.Public.Settings` `KEYS` (pinned at `Test/Data/PublicSettings.cls:43`; iterated by `Test.Install.Public` and `Test.Web.Splash`).
- The catalog key list and fixtures (`Test.Msg.Catalog` XData `Keys`, `Fixtures`).
- Splash's classified parameters (`Test.Web.PublicTexts` `Classified`).
- The "Before you start" list (`Test.Web.Splash` `TestPage`, `TestEdgeValues`; `web/e2e-online/splash.spec.ts` S2).
- Unchanged: `web/src/app/msg/catalog.ts`; `docker/tests/test-online-demo.sh:163` loops over a fixed subset of keys. No CI group gains a unit.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and their mutations** (the implement stage writes each `mutation:` line):
- AC 1: `Test.Web.Splash.TestTelegramNotIncluded`, and `splash.spec.ts` S2 on the real page. Mutation: write the `TELEGRAMLINE` item unconditionally.
- AC 2: `Test.Web.Splash.TestTelegramIncluded`. Mutation: `included` always 0.
- AC 3: `Test.Web.PublicTexts.TestCopiesEqualTheCatalog`. Mutation: drop the final "." of `LIMITLINECHAT`.
- The start path: `Test.Install.Public.TestTelegramFollowsTheSwitch`. Mutation: `Run()` skips `Telegram()`.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: the ACs cannot be built inside the planned scope ("Splash.cls and the catalog lines only, call Included()") without amending AD-19 (veto) and editing Lane A's Install.Step.Public and Test.Install.Public (AD-33; Rule 11 (c), paths contended with live Epics 15, 30 and 11).

**Questions for the lead and the orchestrator** (evidence in `## Design Notes`, "Why a start-time copy"):
1. **AD-19 amendment (veto: amending an AD).** May AD-19's fixed public keys gain `telegramIncluded`? It would be written by the Public step at every flag-on start from `OcuTalon.Channel.Telegram.In.Included()`, not from a start variable, and read by the splash through `Data.Public.Settings`. Recommended wording, appended to AD-19's "Public settings" bullet: "..., the message allowance per session per hour (shown on the splash), whether the release includes Telegram (`telegramIncluded`, `1` or absent, which the `Public` step copies from `OcuTalon.Channel.Telegram.In.Included()` on every online-demo start, so the splash, which may not reference that class (AD-3), follows the same switch as `/state`), and readiness." Rule 20's light path applies: memlog, lint, re-run the pre-warm.
2. **Footprint and lane (AD-33; Rule 11 (c)).** May runner B edit `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls` and add one method to `src/ocutalon/cls/OcuTalon/Test/Install/Public.cls`? The edit is one `ClassMethod Telegram()` of three lines, one call in `Run()`, and two comment lines. The test is `TestTelegramFollowsTheSwitch`. Both are Lane A files, and the paths are contended with Epic 15 (`Install/**`), Epic 30 (`Test/{...,Install,...}/**`) and Epic 11 ("either lane's files"). If the ruling keeps Lane A's files out, a Lane A story must add `Public.Telegram()` first, and this story declares an edge to it.
3. Footprint extensions to record (no ruling needed): `Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls` and `web/e2e-online/splash.spec.ts`.

The rest of the spec is planned to the READY FOR DEVELOPMENT standard. Once (1) and (2) are ruled as recommended, the lead can set `status: ready-for-dev` and dispatch implement on this spec path, with no re-plan. If (2) is ruled the other way, re-plan.
