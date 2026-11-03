---
title: 'Story 12.9: Telegram is included'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: '4e8fede7d85df71838a4e6ad8fe5eb5b27e2ccb8'
baseline_commit: '4e8fede7d85df71838a4e6ad8fe5eb5b27e2ccb8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, AD-19 with its telegramIncluded sub-bullet, AD-22, AD-23, AD-29, AD-32 and AD-33)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only lines 118, 174, 369, 874 and 881)'
warnings: ['multiple-goals', 'oversized']
deferred:
  - 'DW-591 root cause not reproduced: lane-a@Channel in one stack passed forward (508 s) and reversed (499 s) before the fix and again after it. The fix removes the one state that reproduces the symptom (RunnerFixture.NotRunningNow: an item whose Enabled row is 0 but whose runtime flag says enabled and has no job); if CI shows the flake again, the new failure text (StateOf) names the row, the flag and the jobs of the item.'
  - 'docker/tests/test-boundaries.sh rule keys fails on a line of the orchestrator ledger, _bmad-output/implementation-artifacts/deferred-work.md:3379 (the routed DW-591 note: "evidence_attempt1_41545446452" reads as a key). It is in HEAD, not in this change; the owner of that file shortens the token.'
  - summary: >-
      Test.Web.GuideApi TestRunAgain ("steps 3 to 5 reset; the watch still counts") failed in two fresh runs of shard lane-b part 2/2 in this stage (DW-453, wontfix-accepted, reopen_if red again in a fresh shard).
    evidence: |-
      Both failing runs were at the end of the implement stage on unchanged code: the class passes alone on a fresh stack and on a warm stack after its three Web predecessors; the lane-b parts passed earlier in the stage. Test.Web.GuideApi, Demo.Guide and Data.GuideState are not in this diff. The cause is unknown (a state left by one of the earlier classes of part 2 is the open question). Settling it takes a bisect of part 2's classes, or the same part run on the baseline commit.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls TestRunAgain
    severity: medium (unverified)
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

**Routed to this story after the spec gate (Rule 17 (1b), lead edit):**
- [ ] DW-591. CI flake on two heads (404351eb, e9bfda24; green on reruns and locally): `OcuTalon.Test.Channel.TelegramChat`'s setup fails in CI's `shard:lane-a@Channel` (the whole shard in one stack, after `TelegramApi` and `TelegramApproval`) with `ERROR #5001: Not every item of OcuTalon.Production runs 120 seconds after OcuTalon.Production||TriageAgent was started again: TelegramIn` (also DiagnosisAgent and ChatAgent): `TelegramIn` is the only item not running after `RunnerFixture`'s agent restarts, and the class then takes about 398 s. Since this story changes `TelegramIn`'s state on every stack (parking, `Included()` at 1), make the restart readiness check hold for `TelegramIn`: find why it is not running there (a stopped or disabled item counted as "should run", a long poll that outlives the wait, or a leftover from the class before) and fix it in Lane A's test code (`Test/Channel/**`, `Test/Agent/RunnerFixture.cls` is Lane A too; report it), with a test or check that would have gone red. Run the whole `lane-a@Channel` shard in one stack, forward and reversed (no `--part`), as CI does, at least once.

**Rework iteration 1 (lead, fresh check, 2026-11-03):**
- [x] [Smoke] Parking is not reliable on a fresh stack start: in the lead's fresh check, `ci/iris.sh class OcuTalon.Test.Data.Setting` (tag e12s9fc, lane A) failed before any test ran with `FAIL Telegram could not be parked: ERROR #5001: TelegramOut still has a job 30 s after it was disabled` (`docker/tests/lib-live.sh` live_park_telegram -> `Test.Channel.BotApi.Park` -> `LiveCase.Disable` with its 30 s `WAITJOB`); the same class passed on the next fresh stack, and about ten other fresh starts that day parked fine. CI starts dozens of stacks per run on hosts 1.4-3 times slower, so an intermittent park failure would turn CI red at random. Make the park reliable: measure why `TelegramOut`'s job can outlive 30 s after the disable on a just-started stack (for example a send or a retry in flight, or the operation's own start), and fix it so that a park on a fresh, slow start succeeds every time without hiding a real failure (a longer, bounded wait for the park only, a retry of the disable, or waiting for the items to be idle before parking; the park must still fail loudly when an item truly cannot be stopped). Prove it: a test or check that would have gone red on the 30 s behaviour (a `test-lib-live.sh` case with a slow-stopping stub, or a measured loop of fresh starts), plus at least five consecutive fresh `ci/iris.sh class` starts that park green.
  - **Measured (rework 1, tag e12s9rw, lane A):** a fresh stack's `TelegramIn` and `TelegramOut` both have an alive job when the start reports healthy (`NotRunning()` waits for every enabled item). `EnableConfigItem(item, 0, 1)` then returns with the job already gone: 0.01 to 1.6 s on a fresh stack, and 0.01 to 4.9 s over six disable/enable rounds with the container held to 0.25 CPU (`docker update --cpus`). So CPU slowness alone does not keep a job 30 s. The failure was not reproduced in any fresh start of this rework. Why a job outlived the wait once is (inference): `Ens.Director.UpdateProduction` quits `OK` without stopping the job when the stop does not finish within its 10 s timeout (a warning in the event log, not an error), or when it finds the production not Running; either leaves a job that only another update stops, and the old wait never asked again.
  - **Fix (test infrastructure only):** `LiveCase.Disable` takes a wait and a retry (the tests' stops keep 30 s and no retry); the park (`BotApi.Park`) waits `PARKSECONDS` (90 s) and, through `AwaitStop`, asks the production to update again every `RETRYSECONDS` (10 s) while a job is still there, each update waiting no longer than the wait has left. A job still there at the bound fails the park with the job's id and status and the last update's error in the text (`JobText`), which is the evidence to collect if the failure returns. Pinned by `Test.Channel.TelegramParked` `TestStopAsksAgain` (red without the retry, which the old single wait of 30 s had not), `TestStopWithoutAskingStays`, `TestStopThatNeverEnds`, `TestNoAskWhenGone`, `TestParkWaitsLonger` and, on the real production, `TestRealUpdateAndJobText`. Five fresh `ci/iris.sh class OcuTalon.Test.Data.Setting` starts (and `TelegramParked`'s) parked green (`PARK done` 1 to 5 s) with the first version of the fix and again with the final one; `test-lib-live.sh`, `test-ci-warm.sh` and `test-boundaries.sh` pass.

**Acceptance Criteria (Part B):**
- Given a start where `Included()` is 1 and a bot token is set, when the online demo's splash renders, then `telegramIncluded` is "1". The list shows "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send 50 messages an hour in the chat or Telegram.". With no token (or the seam at 0), the key is "0" and no splash line mentions Telegram (FR-14, FR-20, AD-3, AD-19).
- Given the signed-in online-demo page, when the allowance or reset-soon banner shows, then it mentions Telegram only while `telegram.included` is true and the state is not `off` (DW-501, DW-506).


### Review Findings

Code review (2026-11-03, run e12s9cr; four layers, full-opus): 0 decision-needed, 7 patch (all applied), 4 defer, 14 rejected. HEAD 612aec92.

- [x] [Review][Patch] Row 19's no-token and seam-0 starts were parked before `check_telegram_off`, so the check read the park, not the Telegram step (AC1's no-token half could not fail) [docker/tests/test-production-restart.sh:188] -- both waits now run with `LIVE_TELEGRAM=started`; `live production-restart` green; mutation recorded under Verification (medium; edge-case-hunter+verification-gap)
- [x] [Review][Patch] Nothing tested that a failed park fails `ci/warm.sh up`, or that a failed start is not parked [docker/tests/test-ci-warm.sh:1541] -- two DW-164-block cases; both mutations of `warm_ready_check` observed red (low; verification-gap)
- [x] [Review][Patch] The self-test "the section above Sign in" never moved the section (Sign in comes first, so the copy only lost the section) and could not exercise the order check [docker/tests/test-readme.sh:1231] -- the copy now moves the whole section above Sign in; with the order check disabled the self-test reports "not flagged" (low; edge-case-hunter)
- [x] [Review][Patch] `telegram-demo` matched "pair" inside words such as "repair" or "repaired" [docker/tests/test-readme.sh:795] -- the word now needs a non-letter before it; a "paired chat" broken copy added (low; blind-hunter+edge-case-hunter)
- [x] [Review][Patch] Stale docs after B2: `RunLocal`'s doc, `TestFlagOffWritesOnlyTheFlag`'s and `TestOnlyOneIsOn`'s docs said a local install writes no other public key, and the class header did not list `TestTelegramIncludedKey` [src/ocutalon/cls/OcuTalon/Install/Step/Public.cls:72] (low; blind-hunter+acceptance-auditor)
- [x] [Review][Patch] `BotApi.Park`'s doc said "the state a start with no token leaves" without saying `telegramIncluded` keeps the start's value [src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls:17] (low; blind-hunter)
- [x] [Review][Patch] README step 5 said "Open ... again" right after a container recreate; it now waits for `(healthy)` and says to sign in if asked (U-228 condition 3, tightening) [README.md:159]; the harness notice text no longer says "after the restart" when the upgrade check sends it [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls:430] (low; acceptance-auditor, blind-hunter)
- [x] [Review][Defer] `TelegramPageFixture.Notify` and the harness's pairing readings run only in the release harness's live phases [release/upgrade-harness.sh] -- deferred: DW-614, wontfix-accepted (reopen_if a release run's pairing row fails on Notify or a reading)
- [x] [Review][Defer] `eval/run.sh` starts a CI stack without the park [eval/run.sh:585] -- deferred: DW-615, wontfix-accepted; Epic 30's contended path; no eval case uses Telegram
- [x] [Review][Defer] R2c's file-local mark reader/writer repeats `pairing.spec.ts`'s (Rule 2, spec-forced by A13) [web/e2e-online/resume.spec.ts:189] -- deferred: DW-616, wontfix-accepted (reopen_if a third copy appears)
- [x] [Review][Defer] Step 5's "In the Status section" has no visible "Status" label at 1280 px and wider [README.md:159] -- deferred: DW-617, wontfix-accepted (reopen_if the REL-7 pass cannot find the card)

Owned ledger entries at this review: DW-501 and DW-506 resolved-by this story (B5); DW-591 resolved-by this story (fix in 8bead6ac, root cause unreproduced); DW-453 wontfix-accepted (no link found by QA).

**Rejected:**
- `low` `TelegramParked`'s teardown restores rows, flag and mark but not a job, so on a stack that was not parked it could leave row 1, flag 1 and no job -- every recipe stack is parked before the class runs (ci/iris.sh, ci/warm.sh), so the state is unreachable there; a failed Park in TestPark already fails the class.
- `low` A Park that fails inside TestPark leaves a live TelegramIn for later classes -- the class is already red; a teardown park adds a branch for a failure path only.
- `false` Park with an Enabled row of 0 and a live job times out -- Park disables before Apply writes row 0, and no writer leaves row 0 with a job on a recipe stack.
- `low` `NotRunningText` reads the item list again after the wait (an empty "()" text) or gets the "not running" sentence -- diagnostic text only, in a narrow race; the guard adds a branch.
- `low` Warm stacks are parked only at `up`, not at each attach -- warm mode is a local convenience; tests restore what they change; CI never attaches.
- `low` `live_first_start`'s ready time includes the park (0 to 5 s) -- conservative against the 720 s warning, and a park failure prints its own FAIL line.
- `low` R2c's `restoreMark` in `finally` runs before the sign-out and cleanup, so a throw skips them -- restoring the shared mark first is the better order for other tests; a throw there means IRIS is unreachable anyway.
- `low` (by-design) The banners say Telegram for a `rejected` token while the card says "Telegram not set up" -- Design Notes "Decided in-stage" 7 and U-227 (kept).
- `low` (by-design) AD-19's sub-bullet says "the splash and its banners"; the banners read `/state`, not the key -- the key is read only by the splash (the AD's Rule holds); the banner condition is the ruled item 7.
- `false` Two contended files changed beyond "counts only" (`Test/Msg/Catalog.cls`, `catalog.test.mjs`) -- every changed line is one the two new keys need (count lines and their doc counts, the key list, fixtures, slot maps); no line changed for wording alone.
- `false` Lane B files edited without a ruling (`allowance-state.ts`, `allowance-view.ts`, `allowance-sources.test.mjs`, `Test/Data/Setting.cls`, `frame.spec.ts`) -- none is on the contended list; Rule 11(b) allows them, reported as footprint extensions ("Decided at implement" 5 and 6).
- `low` Changed specs (api row 13/16, rail R1, 01-page, frame F1, banners B5) rely on the parked stack -- the park is part of every recipe stack's ready signal (AD-22, decided); tests that change the mark restore it.
- `false` AC1's live "Telegram on" pin was never seen red -- Rule 19 asks one mutation per AC; AC1 has `TelegramSwitch` and QA's `api.spec`/`rail.spec` reds recorded.
- `reject` (edits the spec under review) The spec's Auto Run Result, `deferred:` DW-453 text, the file count and `review_loop_iteration` disagree with the QA block.

### 2026-11-03 - Review pass (rework 1, run e12s9rw)
- verdicts: 28 findings - high 0, medium 6, low 21, false 1, maybe-false 0 (the intent-alignment layer reported readings and no findings: it found the diff implements a longer, bounded, retrying park wait proved by stub-based unit tests plus fresh starts, and that the shell surface is untouched, which the item allows)
- findings:
  - `low` `patch` blind: `Disable`'s `seconds` documented as defaulting when empty but an empty string gave a zero wait -- `If seconds = "" Set seconds = ..#WAITJOB` added
  - `medium` `patch` blind: the retry (a whole-production `UpdateProduction`) ran for every `Disable`, not the park only -- `Disable` takes a `retry` (0 by default); only `BotApi.Park` passes `RETRYSECONDS`; the tests' stops are as before
  - `low` `patch` blind: `Await` could overrun its bound by an update's 10 s timeout -- each update's timeout is the time the wait has left (1 to 10 s)
  - `low` `patch` blind: the update's status was discarded -- `Await` keeps the last error text (`why`); `Disable`'s failure text appends it
  - `low` `reject` blind: no test pins `Park` passing `PARKSECONDS` and the retry, or `Disable` forwarding them -- real, but a hypothetical revert of two arguments; pinning it needs an injection surface in `Disable` and `Park` (more than a direct fix) and the residual risk is stated under Auto Run Result; covered in part by `TestRealUpdateAndJobText` (real `Await` branch) and `TestParkWaitsLonger`
  - `low` `patch` blind: `TestStopWithoutAskingStays` is described as red against the old behaviour and cannot be -- the class doc and the spec now say what it pins (no retry, no update) and that `TestStopAsksAgain` is the test that is red without the retry; mutation lines added
  - `low` `reject` blind: the proof is mostly inference; the root cause is unconfirmed -- already labelled (inference) in the item; the failure text now carries the job, its status and the last update error as the evidence to collect; nothing more to change in code
  - `low` `patch` blind: `TestStopThatNeverEnds` can flake on a slow host (3 s wait, 2 updates asserted) -- wait widened to 5 s, assertion kept at two updates of four
  - `low` `reject` blind: `JobText` repeats the `Ens.Job:Enumerate` loop of `RunnerFixture.Jobs` -- `Jobs` returns ids only; `JobText` needs the status column; a second 5-line loop in test code does not diverge anything named
  - `low` `reject` blind: `review_loop_iteration` and the baseline in the spec -- a fix would edit the spec under review
  - `low` `patch` edge: empty `seconds` gives a zero wait -- same fix as the first row
  - `low` `patch` edge: a failed retry update is invisible -- same fix as the status row
  - `medium` `patch` edge: the retry applies to every `Disable` (teardowns call `UpdateProduction`) -- same fix as the retry row
  - `low` `patch` edge: `nextRetry` was set before a blocking update, so a slow update was followed at once by another -- `nextRetry` is set after the update returns
  - `low` `patch` edge: a blocking update runs past the deadline -- same fix as the overrun row
  - `low` `reject` edge: `JobText` can read `no job now` if the job ends between the deadline check and the text -- the text is diagnostic and a job that ended in between means the stop worked; the cost of capturing the text inside `Await` is a branch for a narrow race
  - `low` `reject` edge: non-numeric or negative `seconds` or `retry` -- only literal parameters and test numbers reach them; no caller can pass such a value
  - `low` `patch` edge: `TestStopThatNeverEnds` can flake -- same fix as the flake row
  - `low` `reject` edge: nothing pins `Park` passing `PARKSECONDS` and a retry -- same claim and verdict as the wiring row
  - `low` `patch` edge: `TestStopWithoutAskingStays` cannot be red against the old behaviour -- same fix as the claim row
  - `medium` `patch` edge: the claim that tests keep their 30 s and the change is park-only was false -- same fix as the retry row: the claim is now true
  - `medium` `reject` vgap: nothing pins `Disable`/`Park` using the new wait (Disable reverted to WaitJobs, retry lost, Park back to 30 s) -- same claim and verdict as the wiring row; the reds of `TestStopAsksAgain` and `TestRealUpdateAndJobText` pin `Await`, not its two call sites
  - `medium` `patch` vgap: the real `UpdateProduction` branch and `JobText` run in no test -- `TestRealUpdateAndJobText` runs the real wait while TelegramIn runs, then parks; mutation `UpdateProductionX` red
  - `low` `patch` vgap: the new tests say they need no stack but their setup touches the stack's rows; no `mutation:` lines for `TestStopWithoutAskingStays` and `TestNoAskWhenGone`; `TestParkWaitsLonger` compares constants -- class doc reworded; two mutation lines added and seen red; the constants test is kept as the pin of the intent (park longer than a test, retry inside a test's wait)
  - `medium` `patch` vgap other: the update is not limited to the park -- same fix as the retry row
  - `low` `patch` vgap other: the bound can overshoot by an update's timeout -- same fix as the overrun row
  - `low` `patch` vgap other: the update's returned status is dropped -- same fix as the status row
  - `false` `reject` vgap other: the failure text changed from the old wording -- no consumer matches the old text: `test-lib-live.sh` passes a literal through a stub, and the text still begins `<item> still has a job <n> s after it was disabled`

## Spec Change Log

- 2026-11-03, lead, rework iteration 1 (trigger smoke/fresh check): the intermittent park failure on a fresh start (TelegramOut still has a job 30 s after it was disabled) re-opens the story; the open item is under Tasks & Acceptance.

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 42 findings - high 0, medium 9, low 25, false 7, maybe-false 1 (including the one the run found itself; plus the intent-alignment layer, which reports readings and no findings: it found the diff implements Part A plus Part B, the ruled reading, and nothing diverges that the spec did not rule)
- findings:
  - Blind Hunter
    - `[low]` `[patch]` AllowanceState.active recomputes on every store update - the flag now comes from its own computed, so `active` changes only with the condition, the refusal, the clock or the flag (`allowance-state.ts`, `allowance-sources.test.mjs`).
    - `[low]` `[reject]` Two definitions of "Telegram on" (the splash key, `Included() && TokenSet()`, against the banners' `included && state !== 'off'`) - Design Notes "Decided in-stage" item 7 and the Contest Planner's U-227 rule the banner condition; they differ only before the first getMe of a start; fixing it edits the spec.
    - `[low]` `[reject]` The harness counts any message to the chat, not the notice - the spec's own check is "a mock sendMessage to that chat within 10 s"; the notice is the only send in that window after a restart.
    - `[low]` `[reject]` Empty or missing session answers read as success in `pairing_move` and `pairing_notify` - the 30 s and 10 s waits that follow fail without a result, so no false pass; a stricter read adds branches.
    - `[false]` `[reject]` DW-591 is fixed only in the test fixture - the routed task names Lane A's test code; the product's `NotRunning()` is unchanged by design.
    - `[low]` `[patch]` Restart, ReadyReason and ChangeSettings read `NotRunningNow` twice for one message - `RunnerFixture.NotRunningText` reads it once.
    - `[medium]` `[patch]` `LiveCase.Disable` matches the English text "already disabled" and its test cannot show the flag cleared - measured: the director answers "already disabled" for a row of 0 and leaves the flag; removing the branch turned no test red. The branch and its test were dropped, `Disable` is as before.
    - `[medium]` `[patch]` The Telegram-on allowance text and composer reason are checked end to end nowhere - `banners.spec.ts` B8 (state on) and B5 (state off) now read `#composer-allowance-reason`; sign-in parts 1 and 2 passed.
    - `[low]` `[reject]` `telegram-strings` matches a literal anywhere in the source file - each string's removal from its source is flagged (recorded mutations); a stricter parse of the views adds complexity for a sentence-level check.
    - `[low]` `[patch]` `writeMark` mixes two meanings - split into `markOn` and `restoreMark`; R2c green on `live online-demo`.
    - `[low]` `[patch]` The `test-readme.sh` header paragraph about `Included()` was garbled - rewritten as before and after.
    - `[low]` `[reject]` The splash and banners name Telegram while the README says the online demo has no bot - host configuration, reported by the runner's observation (the demo host sets no token until Story 31.4); nothing in the repository sets one.
  - Edge Case Hunter
    - `[low]` `[patch]` A failed park with an empty reason passes silently - `live_park_telegram` now gives it a reason; a row in `test-lib-live.sh` pins it.
    - `[low]` `[reject]` `iris_script` has no timeout - every caller shares it and the stack's own deadline bounds it.
    - `[low]` `[reject]` An unreadable `Included()` on the previous build is taken as 0 - an older build without the class has no answer by design; the INFO line names it.
    - `[false]` `[reject]` `seed.env` with no `prev_telegram` key - the harness refuses a phase out of order, so the seed phase has run.
    - `[low]` `[reject]` An unreadable message count before the notice is taken as 0 - the later read fails the same way; same root as the any-message finding.
    - `[low]` `[reject]` A late reply other than the notice satisfies the check - same as the Blind Hunter's finding.
    - `[low]` `[reject]` `phase_settings` and `phase_storage` do not set `LIVE_TELEGRAM=started` - Design Notes at implement item 2: they read no pairing, and the settings project's checks assume a parked stack.
    - `[false]` `[reject]` `SnapshotDefault` reads only the item-specific row - the Telegram step writes that row, as `LiveCase` and `Production.Runners` read it for these items.
    - `[low]` `[patch]` `NotRunningNow` read twice for a message - same fix as above.
    - `[false]` `[reject]` Other tests assert raw `Production.NotRunning()` after a restart - after a park the flag is 0 (`TestPark`); lane-b parts 1 and 2 ran the Agent classes that assert it, and they passed.
    - `[medium]` `[patch]` `Disable` text match - dropped with the branch (see above).
    - `[low]` `[reject]` A late `sendMessage` before `Reset` in `Park` - `TelegramOut` sends only when notified; nothing notifies on a start.
    - `[low]` `[reject]` Same as the two-definitions finding.
    - `[false]` `[reject]` The seam as "0.0" or "00" - the form `'= 0` is the one `test-boundaries.sh` exempts, and the seam is a test switch set to 0.
    - `[false]` `[reject]` `chk_telegram_demo` and sentences that span lines - the README holds one sentence run per line; the rule flags its broken copies.
    - `[low]` `[reject]` `HARNESS_OFF` is dead code with a generic text - kept for the next held-back family; its test is the `held` case.
    - `[low]` `[reject]` Claim: the whole run sets `LIVE_TELEGRAM=started` - same as the phases finding (decided at implement item 2).
    - `[low]` `[reject]` Claim: item 1's sentence differs from A10's text - the Contest Planner's U-228 allows tightening, and the sentence adds "On your own install".
  - Verification Gap
    - `[medium]` `[patch]` Nothing asserts `SetTelegramIncluded` returns 1 for an absent seam - `TelegramSwitch.TestIncluded` asserts it; mutation recorded.
    - `[medium]` `[patch]` `TestDisableTakesALeftoverFlag` cannot fail without the leftover branch - dropped with the branch (measured, see above).
    - `[medium]` `[patch]` The composer and guide reason are pinned only by source regexes - B5 and B8 read the composer's reason in a browser (same root as the Blind Hunter's coverage finding).
    - `[low]` `[patch]` The harness phases' wiring has no offline check - `test-upgrade-harness.sh` rule `pairing` gains four static rows; both mutations recorded red.
    - `[medium]` `[patch]` `TestPark` asserts "no offset" without seeding one, and `TestReadinessFollowsTheRow` relies on the stack's earlier state - `TestPark` seeds an offset, both tests park first.
    - `[medium]` `[patch]` No recorded mutation for AC5, Part B or A7, and no `mutation:` marker - all recorded with `mutation:` lines, each applied, seen red and reverted.
    - `[low]` `[patch]` The park ordering is pinned for only one early exit of `wait_started_ready` - a row for a log that ends not ready joins the one for an unhealthy start; the restarted-container path is not added (low, same ordering).
    - `[maybe-false]` `[defer]` DW-591 is unverified against the real failure - already in `deferred:` (the root cause did not reproduce); what would settle it is a CI recurrence with the new `StateOf` text.
    - `[low]` `[reject]` `PARK skipped` returns success on a build without `Park` - it is the spec's matrix row for an older build.
    - `[low]` `[patch]` Same as the NotRunningNow double read.
    - `[false]` `[reject]` A restored seam stays defined after `SetTelegramIncluded` pairs - `Included()` reads 1 either way, and no test depends on the seam being absent after a restore.
  - Found by the run, not by a layer
    - `[medium]` `[defer]` Test.Web.GuideApi TestRunAgain failed in two fresh lane-b part 2/2 runs at the end of the stage (DW-453, wontfix-accepted, reopen condition met); the class and its code are not in this diff, and it passes alone and on a warm stack - deferred with what would settle it.

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
- **Edits outside Lane A and contended overlaps: all ALLOWED by the orchestrator (2026-11-03, decide, policy 5086036):**
  - `Test/Msg/Contracts.cls` `TestTelegramIncluded` and its doc line (A8): allowed; Epic 40 edits other methods of that file; touch nothing else in it.
  - Catalog-style edits are plain unions: the two `Msg/Catalog/Core.cls` keys beside their siblings, the `Test/Msg/Catalog.cls` counts, the `web/scripts/catalog.mjs` list, the regenerated `web/src/app/msg/catalog.ts`, the `ux-strings.test.mjs` `ruled` entries. Edit only those lines.
  - Epic 31's files: `web/scripts/catalog.test.mjs` (the count lines are a sum-union with Epic 31's; change only what the new keys need) and `web/e2e/floor/announcements.spec.ts:224` (the reset-text expectation only; Epic 31 inserts other lines).
  - Lane B files no open epic touches (Rule 11(b)): `Data/Public/Settings.cls` (KEYS + `telegramIncluded`, 14 keys), `Web/Public/Splash.cls` and its tests, `banner-view.ts` and `banner-stack.ts` with their specs, `Test/Install/Public.cls`, `Test/Data/PublicSettings.cls`, the `web/e2e-online` specs.
  - Other extensions: `release/upgrade-harness.sh`, `docker/tests/test-upgrade-harness.sh`, `docker/tests/test-readme.sh`, `README.md` (one new section and one appended sentence; no line rewritten; Epic 13's 13.3 appends one README item and Epic 10's 10.5 adds a section later: never edit lines they touch), `Test/Data/Fixture.cls`, the `web/e2e/support/iris.ts` doc comment, `rail.spec.ts`, `01-page.spec.ts`, `api.spec.ts`, `web/e2e-online/resume.spec.ts`, `ci/iris.sh`, `ci/warm.sh`, `docker/tests/lib-live.sh`. Parking the two Telegram items after the ready start on CI and throwaway stacks is decided; keep runner 20's `OCUTALON_TEST_WEB_PORT` mapping (and `docker/tests/test-ci-config.sh`) working.
  - Never move test units between CI groups; a new test class goes into the lane-a `Channel` area or the area its folder already maps to.
- **U-227 (banner texts): KEPT** by the Contest Planner (2026-11-03): both texts as written, shown while Telegram is not on, the Telegram-naming banners only while it is on.
- **U-228 (README `## Telegram` text): KEPT with three conditions** (the Contest Planner, 2026-11-03T00:01:41Z#685), which this story must meet:
  1. "Telegram not set up" and every other UI string the README section quotes must match the built page exactly. A check pins each quoted string to the catalog or built text (add it to `docker/tests/test-readme.sh`, next to the `telegram-section` rule), with a mutation line.
  2. No README text about the online demo may claim Telegram, pairing or phone approvals while the demo has no bot (until Story 31.4). The appended "What you can use it for" sentence and the new section must not imply Telegram on the online demo; where the README describes the online demo, it says nothing about Telegram (check every online-demo passage of README.md, and say in the section that it is for a local install).
  3. The owner's REL-7 Telegram pass (Story 38.3) follows the five README steps literally, so each step must be something a person can do exactly as written on a local install (exact commands, exact names of the card and its controls as built), and any step that does not match what happens is fixed before the tag. Tightening the wording at implement is allowed.

**Integration ACs (Rule 1).**
- **Part A:** the rail card and the banner (consumers) link to the README's `#telegram` (the `product-links` rule). The harness consumes `TelegramIn`/`TelegramOut` through a real restart (AC4).
- **Part B:** `OcuTalon.Web.Public.Splash` (consumer) reads `telegramIncluded` and shows its two lines (the B4 splash tests and S2b).

**Decided at implement (small ambiguities, unattended):**
1. **`ToNotify` is split.** `LiveCase.Notification` is a public class method, and `ToNotify` (an instance method with an assertion, which a class method cannot make) is now `SendToNotify` (a class method, no assertion) plus a thin asserted `ToNotify`. `TelegramPageFixture.Notify(sessionRef)` calls the two class methods.
2. **The harness sets `LIVE_TELEGRAM=started` in the seed, upgrade and restart phases**, not in the settings phase: that project's checks (and the demo-switch page project) assume the stack is parked, and its previous build has no `Park` anyway. The settings phase therefore parks the candidate after its upgrade.
3. **Part B's second splash case is S2c**, not S2b: S2b already names the singular-countdown case of `splash.spec.ts`.
4. **R2c is its own test**, with its own session and fixture pairing (a `test.step` inside R2 would not give it a report line); it reads and restores the raw mark through a file-local writer.
5. **`allowanceReason(window)` keeps its signature.** The composer's and the guide's call sites (`demo-guide.ts` is contended) are not touched: `AllowanceState.active()` adds `telegram: telegramOn(store.telegram)` to the window, and `allowanceReason` reads it. This edits `live/allowance-state.ts` and `live/allowance-view.ts`, which no open epic touches.
6. **Other repairs found by the runs** (Lane B files no open epic touches): `Test/Data/Setting.cls` (15 keys with ready), `Test/Msg/Catalog.cls` (Core holds 97 keys), `web/e2e/frame/frame.spec.ts` F1 (five rail headings), `web/scripts/allowance-sources.test.mjs` (the reason's source pattern).
7. **README wording.** The `## Telegram` text is the proposed one, tightened: it says it is for the reader's own install and does not name the online demo; it quotes "Telegram not set up", "Telegram paired", "Unpair", "Approve" and "Reject", which `test-readme.sh` pins to the built page; step 3 says to copy `.env.example` to `.env` first when there is no `.env`; step 5 names the page address and what the card shows after Start, and what to do when it still says "Telegram not set up". Item 1's appended sentence reads "On your own install you can also approve it in Telegram on your phone, without a laptop or the Management Portal ([how to set up Telegram](#telegram))."; the README's online-demo passages say nothing about Telegram.
8. **DW-591 fix.** `RunnerFixture.NotRunningNow` (used by `WaitAllRun`, `Restart`, `ReadyReason` and the change wait) leaves out an item whose System Default Settings Enabled row is 0, because that row overrides the production's flag (AD-3); its failure text (`NotRunningText`, one reading of the item list) adds `StateOf` (row, runtime flag, jobs). `LiveCase.Disable` is as it was: a measurement at review showed that the director answers "already disabled" for an item whose row is 0 and leaves a leftover runtime flag as it is, and that removing a leftover-flag branch turned no test red, so that branch and its test were dropped.

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

**Recorded at implement (Rule 19, each applied, seen red, reverted, tree byte-identical):**
- mutation: AC1: `Included()` set back to `= 1` -> `TelegramSwitch` red (`TestIncluded` absent and 2; `TestRun` absent seam rows and mark). A6's "Telegram on" row is the live pin: it passed on the real change in `ci/iris.sh live production-restart` (re-run after the review patches: green).
- mutation: AC2: `## Telegram` renamed `## Phones` -> `test-readme.sh` red on `telegram-section`, `telegram-strings`, `telegram-demo`, `product-links` and `readme-links`. The rule's own broken copies (heading renamed, section removed, each fact, each step, a sixth step, the section above Sign in) are flagged by it.
- mutation: AC2 (U-228 condition 1): each quoted string reworded in a copy of the README (`Telegram not set up`, `Telegram paired`, `Unpair`, `Approve`), a new quoted string added, a quoted string unquoted, and each of the five strings removed from its source (`rail-view.ts`, `telegram-card-view.ts`, `Msg/Catalog/Watch.cls`) -> `telegram-strings` flags every one.
- mutation: AC2 (condition 2): a sentence about the online demo that names Telegram or pairing, one that names a paired phone beside the demo address, a Telegram sentence outside the section without "your own install", and the item-1 sentence without it -> `telegram-demo` flags every one.
- mutation: AC3: `wait_started_ready` no longer calls `live_park_telegram` -> `test-lib-live.sh` red on "parks the Telegram items once" and "a park that fails fails the wait"; `ci/iris.sh run_classes` without the park check -> `test-ci-warm.sh` red on the three fresh-branch rows.
- mutation: AC4: `pairing_check` no longer waits for the `sendMessage` -> `test-upgrade-harness.sh` rule `pairing` red ("a notice that never reaches the mock fails", "after the restart a notice with no sendMessage at the mock fails"). The phases' wiring: `LIVE_TELEGRAM=started` deleted from `phase_upgrade`, and separately `pair_candidate` deleted from it -> the same rule red on its new static rows.
- mutation: AC5: the `markOn()` call of R2c deleted -> `ci/iris.sh live online-demo` red on R2c alone (`toContainText` of "Telegram paired" fails; 51 passed, 1 skipped); restored -> green (the skip is `address-limit.spec.ts`'s own proxied-phase skip).
- mutation: A7: `SetTelegramIncluded`'s default (`, 1`) removed -> `TelegramSwitch.TestIncluded` red on "the fixture reports the effective value, 1, for an absent seam".
- mutation: DW-591: `RunnerFixture.NotRunningNow` made to skip nothing (`If 0 Continue`) -> `TelegramParked.TestReadinessFollowsTheRow` red (after a 121 s wait). `TestPark` now seeds an offset before the park and asserts it is gone, and both tests park the stack first, so they do not rely on the stack's earlier state.
- mutation: Part B AC1: `Public.SetTelegramIncluded` ignoring `TokenSet()` -> `Test.Install.Public.TestTelegramIncludedKey` red (token not set, both paths); the splash ignoring the key (`Set telegram = 0`) -> `Test.Web.Splash.TestTelegramLines` red on the five-line, order and allowance rows.
- mutation: Part B AC2: `keyOf` ignoring the flag (always the Telegram key) -> `banner-view.test.mjs` red (1 fail of 36). The page-side wiring is pinned in a browser: `banners.spec.ts` B5 (state off: banner and composer reason chat-only) and B8 (state on: banner and composer reason name Telegram); the sign-in unit passed both parts after the patches.
- mutation: rework 1 (park wait): the retry branch of `LiveCase.Await` made unreachable (`If 0 && retry && ...`) -> `TelegramParked` red on `TestStopAsksAgain` (job still there; two updates) and `TestStopThatNeverEnds` (no update asked for).
- mutation: rework 1 (no retry asked for): `retry &&` dropped from that condition -> red on `TestStopWithoutAskingStays` (the wait without a retry updated and ended). The real update renamed (`UpdateProductionX`) -> red on `TestRealUpdateAndJobText` (`<METHOD DOES NOT EXIST>`).
- mutation: rework 1 (gone costs no update): the `has = running` exit removed from the wait -> red on `TestNoAskWhenGone` (an update after the job was gone) and `TestStopAsksAgain`. Each mutation applied, seen red, reverted; `LiveCase.cls` byte-identical to its backup (`cmp`).

**Measured at implement:** A0, `PARK done` 0 to 5 s on fresh and warm stacks (2 s on the first fresh class stack, 1 s in `production-restart`); a fresh stack's READY took 106 to 132 s. The parked state (rows 0, no job of either item, mark off, no mock call, no kept offset) is proved by `production-restart`'s "first start, parked" row and by `Test.Channel.TelegramParked.TestPark`.

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

**QA stage (run tag e12s9qa; the lane-A fresh stacks only):**
- (QA) `docker/tests/test-readme.sh`: the new rule `telegram-facts` (U-228 condition 3, a gap the implement stage left: the section's "after 5 minutes", "In the Status section", the `.env.example` token line, the compose `.env` file and the step 5 address were not pinned to what is built). It pins the minutes to `In.cls` `PAUSESECONDS`, the Status section to `layout-view.ts`'s `status: 'Status'`, step 3 to `.env.example`'s `TELEGRAM_BOT_TOKEN=` and `docker-compose.yml`'s `- path: .env`, and the step 5 address to the one "Sign in" gives. Seven README/source copies and two file copies are its own broken-copy cases. No new test file.
- mutation: U-228 condition 3 (pause): `PAUSESECONDS` 300 -> 600 in `In.cls` -> `test-readme.sh` red on `telegram-facts`; reverted.
- mutation: U-228 condition 3 (pause, README side): "after 5 minutes" -> "after 10 minutes" -> `telegram-facts` red; reverted.
- mutation: U-228 condition 3 (Status): `layout-view.ts` `status: 'Status'` -> `'State'` -> `telegram-facts` red; reverted.
- mutation: U-228 condition 3 (token line): `.env.example` `TELEGRAM_BOT_TOKEN=` -> `TELEGRAM_TOKEN=` -> `telegram-facts` red; reverted.
- mutation: U-228 condition 3 (compose): `docker-compose.yml` `- path: .env` -> `- path: .env.local` -> `telegram-facts` red; reverted.
- mutation: AC1 (rail and endpoints rows, the pins the implement stage recorded no red for): `Included()` set back to `= 1` (the old form) -> `ci/iris.sh live sign-in --part 1/2` red on `api.spec.ts` row 13 (`included: true`) and row 16 (409 `not_available`), `--part 2/2` red on `rail.spec.ts` R1 (five sections); reverted, `git diff` of `In.cls` empty.
- Re-run after the review patches (fresh stacks, all green): `ci/iris.sh live demo-path` with `OCUTALON_LIVE_DEADLINE=900` (28 passed, 8 of 8 steps, 0 skipped, floor 15 of 15, audit rows pass); `ci/iris.sh live floor` (106 passed); the upgrade harness's seven phases `build`, `settings`, `seed`, `upgrade`, `restart`, `storage`, `report` (`RESULT pass`; the `pairing` row passes with 3 checks and the upgrade note; "pairing after the restart: a notification sent through Notify reached the chat as a sendMessage within 10 s").
- mutation: AC1 (no-token half, code review e12s9cr): `Install/Step/Telegram.cls` `Run()` passing 1 instead of `TokenSet()` -> `ci/iris.sh live production-restart` red on "row 19, no token: Telegram is off" (rows, jobs 2) and "every enabled item runs ... the disabled items have no job"; reverted, `git diff` of the class empty; green on the reverted tree.
- mutation: AC3 (warm park, code review): `warm_ready_check` as `warm_start_result && { live_park_telegram || true; }` -> `test-ci-warm.sh` red on "a park that fails fails the up"; as `live_park_telegram; warm_start_result` -> red on that row and "a start that failed is not parked"; reverted, `ci/warm.sh` byte-identical.
- mutation: AC2 (order self-test, code review): `chk_telegram_section`'s order check disabled -> `test-readme.sh` red ("the section above Sign in: not flagged"); with the old self-test the same mutation stayed green.
- DW-453 settled for this story: a fresh `ci/iris.sh shard lane-b --part 2/2` passes (43 classes, `Test.Web.GuideApi` passed, 513 s). Evidence that the story does not cause it: the flake first appeared in Epic 30 (DW-453, 30.3 and 30.4, before `Included()` changed); `TestRunAgain` asserts the `done` flags, which `Demo.Guide.Compute` builds from the session's Checks, reminder, incident, approvals and GuideState rows in OCUORDERS and never from `Included()` (that call only sets `telegramRow`); the same code that failed twice at the end of implement passes in this fresh run. No fix in this footprint; the entry stays wontfix-accepted with `reopen_if` red in CI.

## Auto Run Result

Status: done
Blocking condition: none

**Rework iteration 1 (the `[Smoke]` item: the Telegram park on a fresh, slow start).**

**Summary.** The park now waits `PARKSECONDS` (90 s) and, while a job of the item is still there, asks the production to update again every `RETRYSECONDS` (10 s), each update waiting no longer than the wait has left. A job that is not gone at the bound still fails the park, with the job's id and status and the last update's error in the text. The tests' own stops keep their 30 s and no retry. Measured: the disable returns with the job already gone in 0.01 to 5 s, also with the container held to 0.25 CPU; the failure did not reproduce in the probes or in any fresh start of this rework; the cause (an `UpdateProduction` that quits `OK` without stopping the job) is (inference).

**Files changed.** `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls` (`Disable` with a wait and a retry, `AwaitStop`, `Await`, `JobText`); `src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls` (`PARKSECONDS`, `Park`'s call); `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramParked.cls` (six tests and a stub); this spec.

**Review.** 28 findings: high 0, medium 6, low 21, false 1. Patched: 21 rows (4 medium, 17 low), in 7 causes (empty wait, retry limited to the park, update timeout bounded, update error kept, the real branch and `JobText` tested, the flaky bound widened, test docs and mutation lines). Rejected 7 with their reasons in the triage log, among them the missing pin of `Park`'s and `Disable`'s call sites (a revert of two arguments). Deferred: none new.

**Follow-up review recommended: false.** This was a follow-up pass and no `high` was patched.

**Verification performed.** `Test.Channel.TelegramParked` passes on a fresh stack (the six new tests; 15.8 s); three mutations seen red and reverted, byte-identical; five consecutive fresh `ci/iris.sh class OcuTalon.Test.Data.Setting` starts parked green with the first version of the fix and four more, plus `TelegramParked`'s, with the final one; `bash docker/tests/test-lib-live.sh`, `test-ci-warm.sh` and `test-boundaries.sh` pass.

**Residual risks.** The root cause is unconfirmed. If the park fails again, its text names the job, its status and the last update error. No test pins that `BotApi.Park` passes `PARKSECONDS` and the retry to `Disable`.
