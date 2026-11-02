---
title: 'Story 12.9: Telegram is included'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, AD-19 with its telegramIncluded sub-bullet, AD-22, AD-23, AD-29, AD-32 and AD-33)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only lines 118, 174, 369, 874 and 881)'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Stories 12.1 to 12.8 built Telegram and proved it on the CI mock. But `OcuTalon.Channel.Telegram.In.Included()` still returns 0 outside tests, so no install can pair a phone. Several other gaps follow from that:
- The README has no Telegram section.
- Story 11.2's harness holds its pairing family back.
- Story 16.3's R2c is still `notBuilt`.
- The online demo's banners promise Telegram on an instance that has no bot (DW-501, DW-506).

**Approach (Part A, planned in full):**
- `Included()` returns 1 unless the test-only seam is 0.
- The same change adds the README's `## Telegram` section and the item-1 sentence.
- It repairs every test that assumed "not included".
- CI and throwaway stacks park the Telegram items after each start, so every test still finds no live poller.
- The harness's pairing family is turned on: the restart check from 1.0.0, and the upgrade check once the previous release includes Telegram.
- R2c is turned on.

**Part B** covers the public key `telegramIncluded`, the splash and the banners (U-219 option (a')). It is planned below as a gated block, and is proposed as sibling Story 12.10 (Design Notes, "Proposed split").

## Boundaries & Constraints

**Always:**
- `Included()` keeps one read of the seam, in the exact form `Quit $Get(^OcuTalonTest("TelegramIncluded")) '= 0`. That is the form `docker/tests/test-boundaries.sh:68` exempts. The judges' install never sets the seam.
- The Telegram install step stays the one switch: `TelegramIn` and `TelegramOut` are enabled only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is set. Otherwise they stay disabled and the mark is `off` (AD-23).
- The bot token never reaches a setting, row, log, status text, output line or the page.
- CI mock only, with no real bot. Nothing calls api.telegram.org.
- README:
  - add the new `## Telegram` section, and append the sentence to item 1's line;
  - rewrite no other line, because Story 10.5 and Story 31.3 edit the README later;
  - claim only what Epic 12 built.
- Every test that is added or changed saves and restores what it sets (the seam, the marks, the Enabled rows, the items), and passes on a fresh environment in either order.
- Text is plain and comes from the catalog. Source files are ASCII.

**Never:**
- Edit any of these: `ci/mock/*.mjs`, `ci/mock/test/**`, `OcuTalon.Test.Contract.Mock`, `.github/workflows/*`, CI job names, the iris matrix, or `ci/units.sh`. Add no test area, and move no unit between groups.
- Edit `docs/security-overview.md`, which is Epic 14's (Design Notes list what it must not claim).
- Depend on Story 31.4, touch the online demo host, or touch any bot setting.
- Edit any Lane B file except the ones listed under Design Notes, "Edits outside Lane A". Amend no AD.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| The default (AC1) | The seam is absent, 0, 2, or 1 | `Included()` is 1, 0, 1, 1 | The seam is restored |
| A start with a token (AC1) | `test-production-restart.sh`'s first start, with `LIVE_TELEGRAM=started` and the seam absent | Both Enabled rows are 1. `TelegramIn` and `TelegramOut` each have a job. The mark is `on` with `ocutalon_ci_bot`. The mock recorded a `getMe` | The stack is parked afterwards |
| A start without a token (AC1) | The same script's `live_no_bot_token` start, with the seam absent | Rows 0, the mark `off`, no Bot API call | - |
| A parked stack (AC3) | Any fresh or warm `ci/iris.sh` stack, or a live unit after `wait_started_ready` | Rows 0, no job of either item, the mark `off`, and the mock's Bot API side reset (calls and kept offset). `/state` has `telegram.included` true and `state` `off` | A build without `BotApi.Park` prints `PARK skipped` and passes. A park that fails fails the start with its reason |
| Rail and endpoints (AC1) | README account on a parked stack | Five rail sections, Telegram first: "Telegram not set up" and "How to set it up", linking to README `#telegram`. `POST /v1/pairing/code` with no seam answers 409 `not_available` with `MESSAGETELEGRAMOFF`, not 404 | - |
| README (AC2) | `docker/tests/test-readme.sh` | No `SKIP #telegram` line. `#telegram` is covered. The `telegram-section` rule passes | A broken copy of each rule is flagged |
| Harness restart (AC4) | `pairing` on. In the upgrade phase, a chat is paired through the mock on the candidate | The `pairing` row passes: after the restart the chat is still paired, and one notification sent after the restart reaches it (a mock `sendMessage` to that chat within 10 s) | A fail line fails the result |
| Harness upgrade (AC4) | The previous build reports `Included()` 0 (today's pinned c9f1288) | The `pairing` row carries the note "the upgrade part joins from the release after 1.0.0" | - |
| Harness upgrade (AC4) | The previous build reports `Included()` 1 (stubbed offline) | The chat is paired on the previous build, then checked after the upgrade the same way | - |
| R2c (AC5) | `online-demo` unit, R2b's fixture pairing "Zz chat"; the test sets the mark `on` with `ocutalon_ci_bot` | The card shows "Telegram paired", a middle dot, "Zz chat", and "Unpair" | The mark is restored in `finally` |

</intent-contract>

## Code Map

**Lane A (Epic 12's footprint, or an allowed extension):**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`:
  - the class doc :5;
  - `Included()` :690-695 (the doc at :690-691).
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls`:
  - `Apply(included, tokenSet)` :57-69 (rows and mark);
  - `TokenSet()` :50;
  - `Run()` :27. Unchanged.
- `src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls`:
  - `PollerReason` :46-56;
  - `Reset` :60 (it refuses while `TelegramIn` is live);
  - `SetOffset`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
  - `Disable(items, rows)` :217-233 (public: it disables, waits for no job, and puts the rows back);
  - `WaitJobs`;
  - `WAITJOB` 30 :59;
  - `Notification`/`ToNotify` (private, moved here in 12.7).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramSwitch.cls`: the header :1-12, `TestRun` :98, `TestStructural` :126.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Move(chatId, name, .queuedAt)` :365-380, `Send` :347, `Replies(chatId, .texts)` :383-393. These are public and reset nothing, so a live production's `TelegramIn` handles what they queue.
- `docker/tests/lib-live.sh`:
  - `wait_started_ready` :378-387;
  - `live_no_bot_token` :622;
  - `iris_script` :312-325.
- `docker/tests/test-lib-live.sh`: the stubbed `live_first_start` rows :330-395 are the pattern.
- `docker/tests/test-production-restart.sh`:
  - first start :116-132 (`check_telegram_off "first start" 1` at :132);
  - `check_telegram_off` :81-90;
  - the seam starts :136-179;
  - header :27-29.
- `release/upgrade-harness.sh` (Lane A's `release/`; an extension):
  - `HARNESS_ON`/`HARNESS_OFF`/`HARNESS_ROWS`/`PAIRING_OFF_TEXT` :52-57;
  - `record_rows` :348-378, `record_result` :381-386;
  - stubs :768-771;
  - `phase_seed` :983-1036 (on the previous build; `seed_pairing` at :1024);
  - `phase_upgrade` :1282-1342 (`check_watch_upgrade` :1137-1168 seeds `ref2` into `upgrade.env`, the precedent; `check_pairing_upgrade` at :1340);
  - `phase_restart` :1346-1425 (reads `upgrade.env` :1351, restarts :1353, `signin` :1372, `check_pairing_restart` :1423);
  - the plan line :1524;
  - `wait_started_ready` calls :697, :1306, :1358.
- `docker/tests/test-upgrade-harness.sh`: the header :13; `write_results` `pairing` :439; the off row :476; the dry run's 10 rows :493; "off or fail leaves pass" :509-512.
- `README.md`: item 1 :24; `## Set a model key` :127-136 (the step form to mirror); `## Sign in` :138; `## Stop, start and update` :151.
- `docker/tests/test-readme.sh`:
  - `ITEM1` :116 (and any self-test that embeds the old item text);
  - `telegram_mode` :659-667 (the new body reads "included" by itself);
  - the rule pattern `rule_begin`/`st_append`/`finish` and `chk_block` (`use-cases` :378);
  - `RULES`.

**Lane B or other owners (edited only as Design Notes list):**
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` `SetTelegramIncluded` :198-205 (`was` is `+$Get(...)`, so 0 when unset).
- `web/e2e/support/iris.ts` :1073-1082 (doc "0 when it was not set"; the code is unchanged).
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` `TestTelegramIncluded` :125-136.
- Specs that assume "not included":
  - `web/e2e/rail/rail.spec.ts`: :103 and :114-115 (R1: four sections, no Telegram), :127 (four focusable headings), :168, :186 and :203 (R3/R4 `.first()` is "Approval requests");
  - `web/e2e/demo-path/01-page.spec.ts` :102 and :118;
  - `web/e2e/api/api.spec.ts` :144-151 (`included: false`).
- `web/e2e-online/resume.spec.ts`: R2's `.first()` heading :167, and R2c `notBuilt` :190. `web/e2e/api/pairing.spec.ts` :42-44 has the file-local mark writer to mirror.
- `ci/iris.sh` (not contended; an extension): `stack_ready <title> <start> [<check>]` :258-270 (the check runs after up and prints its own FAIL); `run_classes` :274-298.
- `ci/warm.sh` `up`.

**Read only:**
- `Web/Api.cls`: `telegram` block :769-778; the pairing guard :681 (404 while not included); the code route :693 (409 while the state is not `on`).
- `web/src/app/rail/rail-view.ts` :333 (`telegramShown = store.telegram.included`) and :58 (`TELEGRAM_ANCHOR`).
- `telegram-card-view.ts` :8-24 (paired only while the state is `on`) and its texts :34-47.
- `ci/compose.ci.yml` :21-22 (dummy token and the mock base).
- `Data/StatusMark.cls` `TELEGRAMSTATES` :51 (`off,on,rejected`).
- `.env.example` :4.
- **Unchanged because the stacks are parked:**
  - `Test/Contract/Mock.cls` `TestTelegramBotApi` :348-392 (DW-421);
  - `Test/Web/Api.cls` `TestStateBody` :166;
  - rail R11 :473-487;
  - the Lane A live classes behind `LiveCase.ReadyReason` :99-108.
- **Not affected (inference: the skeleton renders before the snapshot, while `included` is still false):** `web/e2e/live/live.spec.ts:223` and `resume.spec.ts:157`, which count 4 skeleton groups.

## Tasks & Acceptance

**Execution (Part A):**
- [ ] A0. Task 0 (implement, right after A1, A3 and A4): on a fresh lane-A throwaway, measure `live_park_telegram`'s seconds. Prove the parked state: rows 0, no job of either item, the mark `off`, and an empty mock call list. Record both under Verification.
- [ ] A1. `Channel/Telegram/In.cls`: change `Included()` to `Quit $Get(^OcuTalonTest("TelegramIncluded")) '= 0`. Update its doc and the class doc :5: the release includes Telegram; the seam can only turn it off, and only in tests.
- [ ] A2. `Test/Channel/TelegramSwitch.cls`:
  - add `TestIncluded` (absent gives 1, 0 gives 0, 2 gives 1, 1 gives 1; the seam is restored);
  - in `TestRun`, add the absent-seam case (rows 1 with a token);
  - update the header.
- [ ] A3. `Test/Channel/BotApi.cls`: add `ClassMethod Park() As %Status`, which puts the stack into the state a start with no token leaves:
  - `LiveCase.Disable("TelegramIn,TelegramOut", "")`;
  - then `Install.Step.Telegram.Apply(In.Included(), 0)`, for rows 0 and the mark `off`;
  - then `Reset()`;
  - the first failure is the status, and the token never appears in it (Rule 2: it reuses the three, with no copy).
- [ ] A4. `docker/tests/lib-live.sh`: add `live_park_telegram`:
  - it runs `BotApi.Park` through `iris_script` and prints `PARK done <s>s`;
  - it prints `PARK skipped` when `OcuTalon.Test.Channel.BotApi||Park` is not a compiled method (an older build);
  - it prints `FAIL ... Telegram could not be parked: <reason>` and returns 1 on failure.

  `wait_started_ready` calls it after a ready start unless `LIVE_TELEGRAM=started`. Update the header. Pin it in `docker/tests/test-lib-live.sh` with stubs: called after a ready start; not called with `LIVE_TELEGRAM=started`; skipped on an old build; a failure fails the wait.
- [ ] A5. `ci/iris.sh` `run_classes`: on a fresh stack, pass `live_park_telegram` as `stack_ready`'s check. In `ci/warm.sh`, `up` parks after its ready. Each is a footprint extension.
- [ ] A6. `docker/tests/test-production-restart.sh`:
  - the first start's wait runs with `LIVE_TELEGRAM=started`;
  - row :132 becomes a "Telegram on" check: rows 1/1, a job of each item, the mark `on|ocutalon_ci_bot`, and a `getMe` in the mock's calls;
  - then `live_park_telegram`, before the existing rows (which still expect off);
  - update the header :27-29.
- [ ] A7. `Test/Data/Fixture.cls` `SetTelegramIncluded`: `was` becomes the effective value, `+$Get(^OcuTalonTest("TelegramIncluded"), 1)`. Fix its doc and the doc of `web/e2e/support/iris.ts:1074-1076`: "1 when it was not set". Without this, every `was = Set(1)` ... `Set(was)` pair would write 0 back.
- [ ] A8. `Test/Msg/Contracts.cls` `TestTelegramIncluded`: absent gives 1 and 2 gives 1. Its doc line now reads "Included() is 1 unless the test-only global is 0". Touch nothing else.
- [ ] A9. The specs:
  - `rail.spec.ts`: R1 expects five sections with Telegram first, "Telegram not set up" and a "How to set it up" link whose URL ends `#telegram`; :127 counts 5; R3/R4 select the approvals heading by name;
  - `01-page.spec.ts` :102/:118: five sections, Telegram first and not set up;
  - `api.spec.ts`: `included: true`, and `state` stays `off`. It adds that `POST /v1/pairing/code` with no seam answers 409 `not_available`.

  Then search `web/e2e`, `web/e2e-online` and `src/ocutalon/cls/OcuTalon/Test` for other assertions of four rail sections, of a first heading, or of the Telegram section's absence, and repair them the same way. If a spec that needs a repair is on a contended path (Design Notes), stop with `## Clarification Needed` naming it.
- [ ] A10. `README.md`:
  - append the sentence " You can approve it in Telegram on your phone, without a laptop or the Management Portal." to item 1's line (:24);
  - add `## Telegram` after `## Sign in`, with the text under Design Notes, "Proposed public texts".
- [ ] A11. `docker/tests/test-readme.sh`: update `ITEM1`, and any self-test that copies the old item. Add the rule `telegram-section`, in `RULES`, built like `use-cases` (Rule 2). It checks that the section `## Telegram` contains `@BotFather`, `/newbot`, `/setjoingroups`, `TELEGRAM_BOT_TOKEN=`, `docker compose up -d --force-recreate` and "its own bot", and it flags a broken copy for each.
- [ ] A12. `release/upgrade-harness.sh`:
  - `pairing` moves to `HARNESS_ON` and `HARNESS_OFF` becomes empty;
  - the whole run sets `LIVE_TELEGRAM=started` (the previous build has no `Park`, and the candidate's Telegram must be on);
  - **`seed_pairing`**: when the previous build's `Included()` is 1, it pairs a chat through the mock (`TelegramPageFixture.Move`) and saves the chat and session to `seed.env`; otherwise it does nothing;
  - **`check_pairing_upgrade`**: when the seed exists, it checks the pairing as below; otherwise it writes `RECORD pairing note the upgrade part joins from the release after 1.0.0`;
  - **the restart part**: it pairs a chat on the candidate at the end of `phase_upgrade` and saves it to `upgrade.env` (the `ref2` precedent). `check_pairing_restart` passes when the `Pairing` row still names the session after the restart, and one notification sent through `Notify` after the restart reaches the chat as a mock `sendMessage` within 10 s;
  - one helper does both checks;
  - the helper sends the notification through a public class method on `TelegramPageFixture` that reuses `LiveCase`'s `Notification`/`ToNotify` (make them class methods; no copy);
  - update `PAIRING_OFF_TEXT`'s use, the header and the plan line.

  In `docker/tests/test-upgrade-harness.sh`, flip :439, :476, :493 and :509-512 (pairing is a pass row; a fail line fails the result), and add stubbed cases for both upgrade branches.
- [ ] A13. `web/e2e-online/resume.spec.ts`:
  - R2 :167 selects "Approval requests, 1" by name;
  - R2c replaces `notBuilt`: on R2b's fixture pairing, it saves the raw `telegramState` mark and writes `on` with `ocutalon_ci_bot` (a file-local copy of `pairing.spec.ts:42-44`'s writer, about 6 lines);
  - it expects the rail's card to show "Telegram paired", a middle dot and "Zz chat", plus "Unpair";
  - it restores the mark in `finally`.

**Acceptance Criteria (Part A):**
- **AC1.** Given the judges' image, which never sets the seam: when it starts with `TELEGRAM_BOT_TOKEN` set, then `Included()` is 1, both Telegram items run and poll the bot (the mock in CI), and `/state` reports `telegram.included` true. When it starts without a token, then the items stay disabled, the mark is `off`, the rail shows "Telegram not set up" with "How to set it up" opening the README's `#telegram`, and the pairing endpoints answer instead of 404 (FR-21, FR-22, FR-58).
- **AC2.** Given the same change, when `docker/tests/test-readme.sh` runs, then it passes with no `SKIP #telegram`:
  - the README has `## Telegram`, covering BotFather, groups off, `TELEGRAM_BOT_TOKEN` in `.env` and a restart, and one bot per OcuTalon;
  - item 1 ends with the appended sentence;
  - the card's and the banner's link targets resolve (UX-DR98).
- **AC3.** Given any CI or throwaway stack, when its start is ready, then the Telegram items are parked as in the matrix, and every test added or changed passes on a fresh environment, in either order.
- **AC4.** Given Story 11.2's harness, when it runs on the 1.0.0 candidate, then the `pairing` row passes on the restart check, including a notification after the restart. The upgrade part joins by itself once the previous build includes Telegram (FR-60, NFR-16, NFR-17).
- **AC5.** Given Story 16.3's online case, when the `online-demo` unit runs, then R2c passes with no `notBuilt` (FR-14, FR-15, FR-20).

**Execution (Part B, gated: built in this story only if the runner rejects the split; otherwise it is Story 12.10's. DW-501 and DW-506 are addressed here):**
- [ ] B1. `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` :9 (Lane B; the extension named for the ruling): add `telegramIncluded` to `KEYS`, so there are 14 keys.
- [ ] B2. `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls`:
  - on both paths, the online demo (`Run` :39-62) and a local install (`RunLocal` :65-71), write `telegramIncluded` = "1" when `In.Included()` and `Install.Step.Telegram.TokenSet()` are both 1, else "0";
  - the value is structural (AD-19, U-219 (a'));
  - update the class doc: "the twelve other public keys", and the local "no other public key".
- [ ] B3. `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls` :194-200 (Lane B; ruling):
  - restore `TELEGRAMLINE` and `LIMITLINE`, equal to `splash.telegramLine` and `splash.limitLine`;
  - when `Get("telegramIncluded")` is "1", the list is: reset, own, the Telegram line, `LIMITLINE` (when the allowance is set), shell;
  - otherwise it is today's list.
- [ ] B4. The tests:
  - `Test/Install/Public.cls` (the key on both paths, with and without a token);
  - `Test/Data/PublicSettings.cls` (14 keys);
  - `Test/Web/Splash.cls` (key "1" and "0", restored);
  - `Test/Web/PublicTexts.cls` (both texts compared with the catalog);
  - `docker/tests/test-online-demo.sh` :163 (the key list);
  - `web/e2e-online/splash.spec.ts`:
    - S2 sets the key to "0" through the accessor and restores it, then keeps its assertions. The throwaway's start has the dummy token, so its key is "1"; parking does not change the key.
    - A new S2b sets "1" through the accessor, sees both Telegram lines, and restores the key.
- [ ] B5. DW-501 and DW-506, the banners:
  - **The flag:** `web/src/app/banners/banner-view.ts` `BannerInput` gains `telegram: boolean`. `banner-stack.ts:197` sets it from `store.telegram.included && store.telegram.state !== 'off'`, the key's own condition as `/state` already serves it. `allowanceReason` (:35) takes the same flag.
  - **The texts:** while the flag is false, the page uses `banner.allowanceChat` and `banner.resetSoonChat` (Design Notes, "Proposed public texts").
  - **New keys:** in `Msg/Catalog/Core.cls`, right after each sibling; `web/scripts/catalog.mjs`'s list and the regenerated `web/src/app/msg/catalog.ts`; `Test/Msg/Catalog.cls`'s counts; `ruled` entries in `web/scripts/ux-strings.test.mjs`.
  - **Specs:** `banners.spec.ts` :120, :359 and :501, `web/e2e-online/allowance/messages.spec.ts:35`, `web/e2e-online/reset.spec.ts:48`, `web/e2e/floor/announcements.spec.ts:224`, `banner-view.test.mjs` and `catalog.test.mjs` take the chat forms. One banner case route-mocks `state: 'on'` and keeps the Telegram forms.

**Acceptance Criteria (Part B):**
- Given a start where `Included()` is 1 and a bot token is set, when the online demo's splash renders, then `telegramIncluded` is "1". The list shows "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send 50 messages an hour in the chat or Telegram.". With no token (or the seam at 0), the key is "0" and no splash line mentions Telegram (FR-14, FR-20, AD-3, AD-19).
- Given the signed-in online-demo page, when the allowance or reset-soon banner shows, then it mentions Telegram only while `telegram.included` is true and the state is not `off` (DW-501, DW-506).

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- **AD-23:** the Telegram step is the one switch, and is unchanged.
- **AD-19:**
  - the token comes only from the environment;
  - Part B's key follows the amended sub-bullet: written by `Public` on every start, read only by the splash;
  - the banners do not read the key: they use the same condition from `/state`.
- **AD-3:** the splash reads only `Data.Public.Settings`.
- **AD-22:** throwaways and the mock only. Parking keeps one test's poller from taking another's updates (its "Prevents" line).
- **AD-29 and AD-33:** Lane A files, plus the ruled edits below.
- **AD-32:** its "Prevents" line (no Telegram notice without Approve and Reject) is met since Story 12.7, so the switch may follow.
- **Contradictions and tripwires:** no AC contradicts an AD's Rule, and no NFR is unmeasurable.
- **An observation for the runner:** AD-19's first bullet says the online demo's IRIS holds "a dummy bot token". Under U-219 (a') the host must set no `TELEGRAM_BOT_TOKEN`, not even a dummy, until Story 31.4. Otherwise the key turns "1" with no gateway behind it. No repository file sets one; this is host configuration.

**Proposed split (the runner decides):**
- **Story 12.9 (this spec, Part A):** the switch, the README, the test repairs and parking, the harness, and R2c.
- **Story 12.10, "The online demo's texts follow Telegram" (Part B):** the key, the splash, the banners, DW-501 and DW-506.
- **Why:**
  - Part B touches Lane B classes that the lead said not to edit (`Splash.cls`), and six paths contended by Epics 31 and 40.
  - Part A alone makes nothing less true: the splash already promises no Telegram (16.11), and the banners' Telegram wording is DW-501/506 as it stands today.
  - With the split, the runner re-owns DW-501 and DW-506 to Story 12.10.

**Decided in-stage:**
1. **The form of `Included()`** (`'= 0`): it keeps the seam as an off switch, so the 404 and hidden branches that Lane B tests pin stay testable. It also keeps `test-boundaries.sh`'s exemption unchanged.
2. **CI stacks are parked (DW-370/DW-421's sharp edge):**
   - With `Included()` at 1, every CI start (dummy token) enables `TelegramIn`.
   - Without parking, `BotApi.Reset`/`LiveCase.ReadyReason`/`TelegramPageFixture.Start` refuse in about 10 Lane A classes and both Telegram specs, and Lane B's `Contract.Mock.TestTelegramBotApi` (which may not be edited; DW-421 is still escalated) loses its updates.
   - Parking restores the pre-switch stack state exactly: rows 0 and the mark `off`, as with the seam at 0 and only `Included()` changed.
   - The real "token, so on" start is proved live by A6, and offline by `TelegramSwitch`.
3. **The harness's upgrade part is built now** and joins by itself when the previous build reports `Included()` 1. Without it, no story would add it at the next release.
4. **The restart pairing is seeded at the end of `phase_upgrade`** (the `ref2` precedent), so `phase_restart` needs no extra sign-in.
5. **R2c sets the mark `on`** server-side (the parked stack has no poller), rather than route-mocking `/state`. So the card's paired view comes from the server's own pairing.
6. **`## Telegram` goes after `## Sign in`**, and it mirrors `## Set a model key`'s steps.
7. **Part B's banner condition** is `included && state !== 'off'`, the key's condition as the step records it. A `rejected` token still says Telegram, as the key does.

**Edits outside Lane A (for the runner's ruling):**
- `Test/Data/Fixture.cls` (A7, one line and its doc).
- `web/e2e/support/iris.ts` (A7, doc only).
- `Test/Msg/Contracts.cls` (A8; contended, Epic 40).
- `rail.spec.ts`, `01-page.spec.ts` and `api.spec.ts` (A9).
- `resume.spec.ts` (A13; Story 16.3's file: the AC names its case).
- `ci/iris.sh` and `ci/warm.sh` (A5).
- **Part B:**
  - `Data/Public/Settings.cls` (the fixed key, the extension the lead named);
  - `Web/Public/Splash.cls` and its tests;
  - the banner files, `Msg/Catalog/Core.cls` and the web catalog files.

**Contended overlaps (the contended-paths list of 2026-11-02):**
- **Part A:** `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` (Epic 40).
- **Part B:**
  - `Msg/Catalog/Core.cls` (Epic 40; Epic 31's 31.5 appends at the end, so the new keys go next to their siblings, not at the end);
  - `Test/Msg/Catalog.cls` (Epics 40 and 31);
  - `web/scripts/catalog.mjs`, `catalog.test.mjs` and `ux-strings.test.mjs`, `web/src/app/msg/catalog.ts` and `web/e2e/floor/announcements.spec.ts` (Epic 31).
- **No overlap:**
  - `release/upgrade-harness.sh` and `web/e2e-online/resume.spec.ts` are on no list;
  - `ci/units.sh` is untouched;
  - `README.md` overlaps only Epic 10's declared 10.5 plan (a new section, merging after Epic 12). This story adds one section and one sentence, and rewrites no line.

**Proposed public texts (for the runner's veto ruling):**
- **`banner.allowanceChat`** (used when the key's condition is false): "You've used this session's {limit} messages for the hour. You can send more at {time}." This is EXPERIENCE.md:174's form, with slots.
- **`banner.resetSoonChat`**: "The demo resets in 5 minutes. Your session will be cleared."
- **The README `## Telegram` section** (A10):

  > Telegram is optional. With a bot of your own, OcuTalon sends its notices, reminders and approval requests to your phone, and you can approve or reject a fix from the chat. Without a bot token, everything else works and the page shows "Telegram not set up".
  >
  > 1. In Telegram, open @BotFather, send `/newbot` and follow its steps. It gives you the bot's token.
  > 2. Turn groups off for the bot: send `/setjoingroups` to @BotFather, choose your bot, then Disable. OcuTalon answers only private chats.
  > 3. In `.env`, set `TELEGRAM_BOT_TOKEN=<your token>`. Git ignores `.env`, so the token is never committed.
  > 4. Restart OcuTalon: `docker compose up -d --force-recreate`.
  > 5. On the page, the Telegram card shows a QR code. Scan it with your phone's camera, then tap Start in Telegram.
  >
  > Each OcuTalon needs its own bot. If another process polls the same bot, OcuTalon pauses Telegram and tries again after 5 minutes.

**`docs/security-overview.md` (Epic 14, not on this branch; not edited here).** This story makes these likely statements untrue for 1.0.0:
- "In this release the only channel is OcuTalon's own web page". A local install with a token adds Telegram, inbound and outbound.
- "bot tokens are resolved only inside AI Hub's provider". `TelegramIn`/`TelegramOut` read the token from the environment at call time.
- Any claim that no data goes to a third party other than the model provider. Notice texts, approval statuses and pairing replies go to the Telegram Bot API.
- Any claim that only the web page or the simulated phone can answer an approval. A paired chat can.
- Any claim that OcuTalon stores no person's identity. Each live pairing keeps the chat id and display name in its `Pairing` row.

**Runner rulings at the spec gate (2026-11-02, Epic 12 runner, runner A):**
- **Split rejected (decide):** Part A and Part B are both built in this story. Splitting would not remove any contended or Lane B edit (both parts must merge with Epic 12), it would add a full pipeline round on 1.0.0's critical path, and the orchestrator's dispatch keeps DW-501 and DW-506 on Story 12.9. Part B's gate is therefore open: B1-B5 and Part B's acceptance criteria are this story's. The `oversized` warning stands; the implement stage works A then B.
- **Banner texts (veto U-227):** `banner.allowanceChat` = "You've used this session's {limit} messages for the hour. You can send more at {time}." and `banner.resetSoonChat` = "The demo resets in 5 minutes. Your session will be cleared.", as proposed above. The Contest Planner may reverse them before rc1.
- **README `## Telegram` text (veto U-228):** as proposed above; the implement stage checks every claim against the built behaviour (Stories 12.1-12.8) and may only tighten the wording.
- **Decided in-stage items 1-7:** accepted (the `'= 0` seam, parking every CI and throwaway stack after its ready start, the harness's self-joining upgrade part, the seeded restart pairing, R2c's server-side mark, the section's place, Part B's banner condition).
- **Host observation (AD-19's dummy bot token):** reported to the orchestrator for the Contest Planner (host configuration; no repository change).
- **Edits outside Lane A and contended overlaps:** sent to the orchestrator for a ruling (cross-epic, U14); the rulings are recorded below when they arrive.

**Integration ACs (Rule 1).**
- **Part A:** the rail card and the banner (consumers) link to the README's `#telegram` (the `product-links` rule). The harness consumes `TelegramIn`/`TelegramOut` through a real restart (AC4).
- **Part B:** `OcuTalon.Web.Public.Splash` (consumer) reads `telegramIncluded` and shows its two lines (the B4 splash tests and S2b).

**Consumes:**
- `Install.Step.Telegram` (`Apply`, `TokenSet`), `Data.Public.Settings`, `/state`'s `telegram` block (Lane B);
- `TelegramPageFixture`, `LiveCase` and `BotApi` (12.1-12.7);
- the catalog keys `splash.telegramLine`/`splash.limitLine`.

**Consumed-by:**
- **Story 31.4:** the key turns "1" with a token on the demo host, with no code change.
- **Story 31.3:** the Telegram allowance cases.
- **Story 38.3:** the real-bot pass.
- **The harness at the release after 1.0.0:** the upgrade part.

**Owned ledger (Rule 17):** DW-501 and DW-506 are addressed by B5. With the split, the runner re-owns both to Story 12.10.

**Extend, don't copy (Rule 2):**
- `BotApi.Park` composes `LiveCase.Disable`, `Step.Telegram.Apply` and `BotApi.Reset`.
- `live_park_telegram` follows `live_no_bot_token`.
- The harness checks reuse `TelegramPageFixture.Move`/`Replies`, and `LiveCase`'s notification builders, made class methods.
- The `telegram-section` rule extends `use-cases`'s `chk_block`.
- R2c's 6-line mark writer copies `pairing.spec.ts`'s file-local one, because a shared helper would go in `web/e2e/support/`.

**Cost (inference until A0):**
- Parking adds one disable wait (`TelegramIn` long-polls for 5 s) of about 5-10 s to each stack start.
- R2c adds about 5 s.
- The harness's pairing adds about 30 s to `upgrade` and `restart`, against a 540 s deadline.

## Verification

`<lane>` stands for Rule 21's lane-A variables: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=12 stage=implement'`. The fresh tag is `e12s9i` and the warm tag `e12s9iw`. Every command runs in the foreground with `timeout: 600000`, one per call.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: exit 0, no `SKIP #telegram`, and `PASS telegram-section`.
- (loop) `bash docker/tests/test-upgrade-harness.sh` -- expected: exit 0.
- (loop) `bash docker/tests/test-lib-live.sh` -- expected: exit 0, with the four park rows.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s9iw ci/warm.sh up` once, after A4/A5. Then one call each:
  - `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s9iw ci/iris.sh class OcuTalon.Test.Channel.TelegramSwitch`;
  - the same for `OcuTalon.Test.Msg.Contracts`;
  - the same for `OcuTalon.Test.Channel.TelegramMock`.

  Expected: each passes. `ci/warm.sh down` at the stage's end, also after a failure.
- (once) `bash ci/checks.sh` -- expected: every block passes.
- (once) `<lane> OCUTALON_RUN_TAG=e12s9i ci/iris.sh shard lane-a@Channel --part 1/2`, then `--part 2/2` (use `k/3` if a part nears 8 minutes). Expected: all classes pass, with a `PARK done` line.
- (once) `<lane> OCUTALON_RUN_TAG=e12s9i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`. Expected: all pass, `Contract.Mock` included.
- (once) `<lane> OCUTALON_RUN_TAG=e12s9i ci/iris.sh live production-restart` -- expected: passes, with the "Telegram on" row.
- (once) `<lane> OCUTALON_RUN_TAG=e12s9i ci/iris.sh build`, then `live sign-in --part 1/2` and `--part 2/2`, then `OCUTALON_LIVE_DEADLINE=900 ... live demo-path`, `live online-demo` and `live floor`. Expected: each passes, and the demo-path summary has no new skip.
- (once) The harness: `OCUTALON_RUN_TAG=e12s9h release/upgrade-harness.sh build`, then `settings`, `seed`, `upgrade`, `restart`, `report` and `down`, one per call. Expected: the `pairing` row passes, with the upgrade note.
- (once) Write the changed paths to a scratchpad file. Run `bash ci/changes.sh ci.yml --paths-from <file>` and record the groups. Then `<lane> OCUTALON_RUN_TAG=e12s9i ci/iris.sh teardown`.
- (once) `git status --short -- ci/mock ci/units.sh .github docs src/ocutalon/cls/OcuTalon/Test/Contract src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Msg web/src` -- expected: it prints nothing for Part A. Part B adds its named files.

**Mutations (Rule 19; one per AC, recorded with the result):**
- AC1: `Included()` reverted to `= 1` -> `TelegramSwitch.TestIncluded` and A6's "Telegram on" row go red.
- AC2: the `## Telegram` heading renamed -> `test-readme.sh` `product-links` and `telegram-section` go red.
- AC3: `wait_started_ready` no longer calls `live_park_telegram` -> `test-lib-live.sh`'s park row and `TelegramMock` on a fresh stack go red.
- AC4: `check_pairing_restart` skips the notification -> the `test-upgrade-harness.sh` case with a missing `sendMessage` goes red.
- AC5: the mark is not set -> R2c goes red.

**Shared surfaces:**
- the rail's section list (five, with Telegram first);
- `/state`'s `telegram.included`;
- the pairing endpoints (no 404 by default);
- the Telegram install step's live state on every CI and throwaway stack (now parked);
- the README's item 1 and its link inventory (`#telegram`);
- the harness's row table (`pairing` passes);
- `SetTelegramIncluded`'s return value;
- **Part B also:** the public key list (14), the splash list, and the two banner texts.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
