---
title: 'Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API'
type: 'feature'
created: '2026-10-29'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, AD-14, AD-19, AD-22, AD-23, AD-29 and AD-33)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The Telegram installer step is an empty stub. Nothing switches `TelegramIn` and `TelegramOut` from `Included()` and `TELEGRAM_BOT_TOKEN`, and nothing records `off` when Telegram stays off. CI has no way to make a start with no bot token, because its override always sets the dummy (DW-367). The mock has no Lane A Telegram scenarios, and its reset restarts the update ids, so a poller that keeps its offset would drop the next updates (DW-370).

**Approach:** Fill the Telegram step in place as the one switch. At every start it writes the `Enabled` System Default Setting rows of both items: 1 only when `Included()` returns 1 and the token is not empty, and 0 otherwise. When it leaves them disabled, it records `off`. Also: add Lane A's five Telegram scenarios; make a CI start with no token use an explicit empty token; and keep the mock's ids counting across a reset. `Included()` keeps its test-only body.

## Boundaries & Constraints

**Always:**
- The step is the one Telegram switch (AD-23). It writes the rows `(OcuTalon.Production, TelegramIn|TelegramOut, *, Enabled)` at every start, as structural values (AD-19), through `OcuTalon.Install.Step.Production.WriteDefault`. The registry runs it before `Production`. The production's XData keeps `Enabled="false"`.
- "Set" means not empty. The `TELEGRAM_BOT_TOKEN=` line of `.env.example` is no token.
- The step reads only whether the token is present. It never stores, returns or logs the token, and never puts it in a row, a description or a `%Status` text (AD-14, AD-19, NFR-11).
- The step records `off` through `StatusMark.RecordTelegram("off", "")` only when it leaves the items disabled. When the items are enabled, the mark belongs to `TelegramIn` (AD-14).
- No test starts or restarts a production while a stub item is enabled. Tests pin the enable branch at the rows that the start reads.
- Every test puts back what it changed: the rows, the mark, `^OcuTalonTest("TelegramIncluded")` and the mock's Bot API side.
- Tests use only the CI mock and its dummy token. ObjectScript and mock code follow Rule 14.

**Never:**
- No change to:
  - `Included()`'s body (`docker/tests/test-readme.sh` reads it, and Story 12.7 changes it);
  - `Channel/Telegram/In.cls` or `Out.cls` (Story 12.2 builds them);
  - `Production.cls` or the registry's order;
  - `ci/compose.ci.yml`, `web/` or the README.
- No real bot, no call to `api.telegram.org`, no real token, and no read of `.env`.
- The step prints no `WARN` line and adds no user-facing text. The rows' descriptions are admin notes, as EvalIn's is.
- No new live unit, and no new start in CI.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Not included, no token | `Apply(0, 0)` | Both rows are `0`. The mark is `off`. | — |
| Not included, token set (a release cut before 12.7) | `Apply(0, 1)` | Both rows are `0`. The mark is `off`. | — |
| Included, no token (FR-21) | `Apply(1, 0)` | Both rows are `0`. The mark is `off`. | — |
| Included, token set | `Apply(1, 1)`; the mark was `on`/`ocutalon_ci_bot` before | Both rows are `1`. The mark is unchanged. | — |
| `Run()` reads the switch | `Run()` with the seam at 0, then at 1, in the stack's own environment | Both rows are `1` exactly when the seam is 1 and `TELEGRAM_BOT_TOKEN` is not empty, else `0`. No row value, row description or status text holds the token. | — |
| The rows are structural | A row set to `1` by hand, then `Run()` with the seam at 0 | The row is `0` again. | — |
| CI start with Telegram off | A fresh throwaway start: seam unset, dummy token | `STEP Telegram OK`. Both rows are `0`. The mark row exists and says `off`. `TelegramIn` and `TelegramOut` have no job. The mock lists no Bot API call. | — |
| CI start with no token (DW-367) | Seam at `1`; mark `on` before; `TELEGRAM_BOT_TOKEN` set to `""` by a layered compose file | The start ends ready. `check_no_key` passes. The variable is set and empty, and `TokenSet()` is 0. Both rows are `0`. The mark is `off`. Every enabled item runs, and the disabled items have no job. The mock lists no Bot API call. | — |
| Update scenarios | `POST /_mock/telegram/updates {"scenario": "telegram-private-update"}`, then `telegram-group-update` and `telegram-button-update`; then `getUpdates` | The `updateIds` in the answers increase. `getUpdates` lists the three updates with those ids: a `message` in a private chat, a `message` in a `group` chat, and a `callback_query` from a private chat. | — |
| Reply scenarios | `/replies {"scenario": "telegram-conflict"}`, then `getUpdates`; `telegram-rate-limited`, then `sendMessage` twice | `getUpdates` answers 409 with `error_code` 409 and a description that starts with "Conflict". The first `sendMessage` answers 429 with `error_code` 429 and `parameters.retry_after` 2. The second gets the 200 default. | — |
| Calls read back | After each group above | `/_mock/telegram/calls` lists each call in order, with its method and parameters. The mock's log shows the path `/bot[redacted]/<method>` and the token's length, and never the token. | — |
| Reset keeps counting (DW-370) | Ids up to `n`; `reset`; queue one update; `getUpdates` with `offset` `n+1` | The new update's id is `n+1`, and `getUpdates` returns it rather than dropping it. A `sendMessage` after the reset gets a `message_id` above the earlier ones. | — |
| `/updates` refuses a bad scenario | An unknown name; a `sendMessage` scenario; `scenario` together with `updates`; a `getUpdates` scenario that holds no update | A 400 Bot API error that names the rule. | Nothing is queued. |
| A direct-call test owns the Bot API side (DW-370) | `TelegramPollerReason("TelegramIn")`; the same for an item with a live job (`Decide`) | `""` for `TelegramIn`. For `Decide`, a reason that names the item. `TestTelegramBotApi` and `Test.Channel.TelegramMock` fail with that reason, and send nothing, whenever it is not empty. | — |
| `live_key_count` | `TELEGRAM_BOT_TOKEN` empty | Counts 0. The decoy token, the dummy with one character added or removed, and the dummy in other letter case still count 1. | — |

</intent-contract>

## Code Map

**The switch**
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls:1-11`: the stub, filled in place (it is in Epic 15's contended `Install/**`). `Install/Registry.cls:12-15` `Order()` runs it after `Audit` and before `Production`.
- `Install/Step/Production.cls`, the EvalIn switch to follow:
  - `PRODUCTION` :27; `SetEval` :261 writes a structural row; `WriteDefault` :268 calls the bridge's one writer.
  - `Runners()` reads an item's effective `Enabled` with `Ens.Config.DefaultSettings.%GetSetting(production, item, class, "", "Enabled", .v)`.
- `Channel/Telegram/In.cls:20`: `Included()`. Read only; its body stays.
- `Data/StatusMark.cls:53-87`:
  - `RecordTelegram(state, botUserName)`;
  - `TelegramState(.botUserName)`, which is `off` when there is no mark;
  - `Record(mark, "")`, which deletes a mark (for restoring one that was absent).
- `Test/Data/Fixture.cls:177-184`: `SetTelegramIncluded(value)`, which returns the old value.
- `Production.cls:15-17`: `TelegramIn` and `TelegramOut` in lane A's region, `Enabled="false"`. Read only.
- `Test/Install/Production.cls`: the oracle rows :613-614 (enabled 0, stub 1) stay as they are; :404-428 shows how a test saves and restores a row.
- Readers of the mark (read only):
  - `Web/Api.cls:673-690` (the pairing routes answer 404 while Telegram is not included) and `:766-769` (the Telegram block of `/state`);
  - `web/src/app/rail/telegram-card/telegram-card.ts` (shows "not set up" for `off` and `rejected`);
  - `web/e2e/rail/rail.spec.ts:463-497` (R11: "not set up", and no banner).

**The mock**
- `ci/mock/mock.mjs`:
  - the header :9-23; the `tg` state :234;
  - `telegramControl` :322-391: `reset` :328-337 restarts both counters; `updates` :345-361; the `scenario` lookup of `replies` :366-374;
  - `pendingUpdates` :394-397.
- `ci/mock/scenarios.mjs:16-22` and `:162-`: the telegram scenario form and `checkTelegramReplies`. Read only.
- `ci/mock/test/telegram.test.mjs`:
  - the `bot` and `control` helpers;
  - :139-170, the defaults; :165-168 pins "a reset restarts the counter";
  - :172-200, the update queue.
- `ci/mock/test/scenarios.test.mjs:125-131`: the committed scenario files must load with no problem.
- `ci/mock/scenarios/A/`: Lane A's folder. A scenario's name is kebab-case and equals its file name.
- `Test/Contract/Mock.cls` (Lane B's):
  - `TestTelegramBotApi` :348-390 expects `update_id` 1, `message_id` 1 and exactly 3 calls after its reset;
  - public helpers: `TelegramMissingReason` :394, `BotCall` :403 (throws on any status but 200), `Control` :417 (returns a Boolean only), `Calls` :429, `LogMark` :471 and `LogSince` :484;
  - private: `NewRequest` :586.

**CI**
- `docker/tests/lib-live.sh`:
  - `live_add_file` :152 and `live_pop_file` :611;
  - `check_items_run` :631-647;
  - `live_ci_bot_token` :649-651;
  - `live_key_count` :656-666: counts any `TELEGRAM_BOT_TOKEN` that is set and is not the dummy, an empty one included;
  - `check_no_key` :668-677.
- `docker/tests/test-lib-live.sh:682-734`: the `live_key_count` rows; :718 pins "an empty bot token counts 1".
- `docker/tests/test-production-restart.sh`: the header :1-30; `check_eval` :50-66; the first start :78-95; row 19's two recreates :97-119 (with `OCUTALON_EVAL=1`, then without).
- `ci/units.sh:14-21`: `shard_areas`. `lane-a@rest` (in `shards-2`) takes any new area. `docker/tests/test-ci-config.sh` works out the area checks itself (it holds no literal area list).
- `.env.example` has `TELEGRAM_BOT_TOKEN=` (empty), and `docker-compose.yml` passes `.env` as the `env_file`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls`: fill it in place.
  - `Run()` returns `Apply(##class(OcuTalon.Channel.Telegram.In).Included(), TokenSet())`.
  - `TokenSet()` is 1 when `$SYSTEM.Util.GetEnviron("TELEGRAM_BOT_TOKEN")` is not empty, and 0 otherwise. It returns nothing else.
  - `Apply(included, tokenSet)` writes both rows: 1 only when both arguments are 1, else 0. Each row's description says that the step writes it at every start, from `Included()` and whether `TELEGRAM_BOT_TOKEN` is set. On the disabled path, `Apply` also records `off`.
  - The first failure is the step's status.
  - Replace the stub's doc comment with this contract (AD-23, AD-14).
- `ci/mock/mock.mjs` (DW-370):
  - `reset` clears the updates, the replies and the calls, and no longer restarts `nextUpdateId` or `nextMessageId`.
  - `POST /_mock/telegram/updates` also takes `{"scenario": "<name>"}`, alone, naming a telegram `getUpdates` scenario. The mock queues the `body.result` objects of the scenario's 200 replies with the next update ids, replacing any `update_id` in the file, and answers as it does for the list form. Refusals are as in the matrix.
  - Update the header lines 12 and 16.
- `ci/mock/scenarios/A/telegram-private-update.json`, `telegram-group-update.json` and `telegram-button-update.json` (new). Each has `match: {"telegram": "getUpdates"}` and one 200 reply `{"ok": true, "result": [<one update, with an update_id>]}`. The updates are:
  - a text `message` in a private chat;
  - a `message` in a chat of type `group`;
  - a `callback_query` from a private chat whose `data` names no request (`ocutalon-ci-unknown-press`).

  Use fixture ids and names only, never a real person's.
- `ci/mock/scenarios/A/telegram-conflict.json` and `telegram-rate-limited.json` (new):
  - `getUpdates`: 409 `{"ok": false, "error_code": 409, "description": "Conflict: terminated by other getUpdates request; make sure that only one bot instance is running"}`;
  - `sendMessage`: 429 `{"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 2", "parameters": {"retry_after": 2}}`.
- `ci/mock/test/telegram.test.mjs`:
  - change :165-168 to "a reset keeps the counter";
  - add a test (DW-370): a reset keeps the update ids counting, and `getUpdates` at the offset a poller holds returns the next update;
  - add a test: `/updates {"scenario"}` queues the updates of a fixture `getUpdates` scenario with the next ids;
  - add a test for each refusal.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls`: extend the helpers, don't copy them.
  - New `BotReply(token, method, body, Output statusCode)`: returns the parsed body whatever the status, and throws only when the mock can't be reached. `BotCall` becomes `BotReply` plus its throw on any status but 200.
  - `Control` gains a trailing `Output answer`.
  - New public `TelegramPollerReason(item = "TelegramIn")`: `""` when the item has no live job, else a reason that names it.
  - `TestTelegramBotApi` (DW-370): it first checks `TelegramPollerReason()`. It then expects the `update_id` that `Control("updates", ..., .answer)` returned, and a positive `message_id`.
  - Update the method's doc comment and the class doc's lines.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramSwitch.cls` (new): the tests of the switch.
  - Covers every `Apply` row of the matrix; `Run()` with the seam at 0 and at 1, in the stack's own environment, with the check that nothing holds the token; and the structural row.
  - Reads each row with `%GetSetting`, as `Runners()` does.
  - Saves both rows, the mark and the seam as found, and puts them back (OnBeforeAllTests and OnAfterAllTests).
  - Never calls `Ens.Director`. Runs anywhere.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramMock.cls` (new): the Integration AC. Runs in throwaways and CI only.
  - It first checks `TelegramMissingReason` and `TelegramPollerReason`; when either gives a reason, it fails with it and sends nothing.
  - It then covers the update, reply, calls, reset and owner rows of the matrix, through `BotReply`, `Control`, `Calls`, `LogMark` and `LogSince`.
  - It resets the mock's Bot API side before and after.
- `docker/tests/lib-live.sh` (DW-367):
  - `live_key_count` counts `TELEGRAM_BOT_TOKEN` only when it is not empty and is not the dummy.
  - New `live_no_bot_token`: writes `$tmp/no-bot-token.yml`, which sets `services.iris.environment.TELEGRAM_BOT_TOKEN: ""`, and adds it with `live_add_file`. `live_pop_file` removes it.
  - Update the header comment and `check_no_key`'s comment.
- `docker/tests/test-lib-live.sh`: flip :718 to "an empty bot token counts 0". Add a row: `live_no_bot_token` adds one file, last, that sets the iris service's token to the empty value.
- `docker/tests/test-production-restart.sh`:
  - New `check_telegram_off <label> <tokenset>`. In one terminal session it checks:
    - both rows are `0`;
    - the mark row exists and says `off`;
    - `TokenSet()` equals `<tokenset>`;
    - a direct `%Net.HttpRequest` to the mock's `/_mock/telegram/calls` answers `200` with no call.
  - After the first start, run `check_telegram_off "first start" 1`.
  - Before row 19's `OCUTALON_EVAL=1` recreate, in one terminal session: `##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)` and `##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")`. Then call `live_no_bot_token`.
  - After that start: check inside the container that `TELEGRAM_BOT_TOKEN` is set and empty, printing no value; then run `check_no_key "row 19, no token"`, `check_items_run "row 19, no token"` and `check_telegram_off "row 19, no token" 0`.
  - Before the second recreate: `SetTelegramIncluded(0)`, then `live_pop_file`. After that start, run `check_telegram_off "row 19, no variable" 1`.
  - Update the header: row 19 also covers Story 12.1.
- `ci/units.sh`: append `Channel` to `lane-a`'s areas. This is Epic 12's own entry, and it runs in `shards-2` through `lane-a@rest`.

**Acceptance Criteria:**
- Given Telegram included through the seam and an empty `TELEGRAM_BOT_TOKEN`, when OcuTalon starts in CI, then the start ends ready, the step leaves both items disabled and records `off`, the mock lists no Bot API call, every enabled item runs and the no-key check passes (FR-21, AD-23, DW-367).
- Given a CI start whose release does not include Telegram, with the dummy token set, when it ends, then both rows are `0`, the mark says `off`, `TelegramIn` and `TelegramOut` have no job, and the mock lists no Bot API call (REL-1, AD-23).
- Given the Telegram step, when `Included()` returns 1 and the token is set, then both rows are `1` and the step leaves the mark alone; and in every other case both rows are `0` and the mark is `off` (AD-23, AD-14).
- Given the mock with Lane A's scenarios, when IRIS queues each one through the control endpoint and calls the Bot API as the Telegram service will, then each answers as the matrix says, the calls read back in order, and the log holds only the token's length (FR-22, AD-22, NFR-11).
- Given a reset of the mock's Bot API side, when a test queues an update, then its id continues the count and a poller's kept offset still receives it; and a test that resets the Bot API side fails, naming the item, while `TelegramIn` has a live job (DW-370).
- Given this story merged, when the README check, `/state` and the pairing routes run, then `Included()` keeps its test-only body, `/state` hides Telegram and the pairing routes answer 404 (`test-readme.sh` and `Test.Web.PairingApi`, unchanged; FR-58).
- Given CI's `browser` group, when the demo path and `sign-in` run, then REL-2's specs pass with Telegram's parts not run, and R11 shows "Telegram not set up" with no banner (unchanged; CI; UX-DR17, UX-DR56).

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-23: the one Telegram switch, the registry's order, and that a failed step stops the start.
- AD-14: the token comes only from the environment; who records the Telegram state.
- AD-19: bot tokens come from the environment; structural values are rewritten at every start.
- AD-3: the production class holds structure only, and switches are System Default Settings.
- AD-22: the CI override, the mock and the scenario files; new mock behaviour is Lane B's, asked for under AD-33.
- AD-29: the lanes; the `Included()` seam; `STUB`; the Telegram epic stays inside Lane A's files.
- AD-33: only the owning lane edits a class.

**Why rows and not the definition.** The step follows EvalIn's switch (AD-23, AD-3). A System Default Setting row for `Enabled` overrides the XData flag, so the definition stays as the class says. Because the row is rewritten at every start, it follows that start's environment: if the token is removed later, Telegram is off at the next start. `live production-restart` row 19 measures this for EvalIn. For a pool-1 item the `Enabled` setting is resolved the same way (inference); Story 12.2 is the first to see such an item run.

**Why no enabled stub runs.** `TelegramIn` is an `Ens.InboundAdapter` service, and its stub answers "not implemented" at every call interval. (Inference: that writes an error row at each poll, which `check_clean_start` refuses, and Story 11.5's release check refuses an enabled stub.) So this story pins the enable branch at the rows that the start reads, through the same `%GetSetting` call that `Install.Step.Production.Runners()` uses, and no test restarts the production while a row is 1. Seeing the item run arrives with Story 12.2's built `TelegramIn`.

**DW-367 (decided).**
- In CI, a start with no bot token is a start whose `TELEGRAM_BOT_TOKEN` holds the empty value, which is what a judge's `.env` copied from `.env.example` holds. `live_no_bot_token` layers it after the CI override.
- A start without the override would also lose the model mock and the endpoint overrides, so it could not show that every other feature works.
- So `live_key_count` counts an empty token as no key: the value holds no secret.
- The first such start is row 19's existing `OCUTALON_EVAL=1` recreate, so CI gains no start.
- Story 12.7, which makes `Included()` return 1 everywhere, reuses `live_no_bot_token` for its no-token start.

**DW-370 (decided).**
- The mock's ids behave like the Bot API's: update ids and message ids keep counting for the mock's lifetime. `reset` clears only the queues, the replies and the calls, so a poller's kept offset never drops a later test's updates.
- A test queues an update scenario as an inbound update (`/updates {"scenario"}`), which gets a fresh id. A scripted `getUpdates` reply keeps its file's id, so it is only for a test with no poller.
- A test reads its ids from the queue's answer, and its calls after its own reset.
- A test that resets the Bot API side owns it. It first calls `TelegramPollerReason()`, and fails naming `TelegramIn` when that item has a live job.
- Through Story 12.6, no CI start runs `TelegramIn`: `Included()` is 0 at every start, and a Lane A test that runs it must stop it before it returns.
- Story 12.7 turns `TelegramIn` on at every start. It must then stop it around these tests, or give them their own bot. The check makes that impossible to miss.

**Integration ACs (Rule 1).** Three consumers read what this story adds:
- The start's `Production` step reads the rows. In `test-production-restart.sh`, the items have no job and every other item runs.
- `/state` and the card read the mark (R11, unchanged).
- IRIS's Bot API calls read the scenarios (`Test.Channel.TelegramMock`).

**Consumed-by:**
- Story 12.2: `TelegramIn`'s first enabled start through the switch; the update scenarios and the 409; ids that keep counting across resets.
- Stories 12.4 and 12.5: the private and group updates.
- Story 12.6: the 429, for `TelegramOut`'s retry.
- Story 12.7: the button update; `Included()` returning 1; `live_no_bot_token`; the check on `TelegramIn`'s job.

**Consumes** (all used against the real mock and a real start):
- `StatusMark.RecordTelegram` and `TelegramState` (Story 10.3);
- `Channel.Telegram.In.Included()` (Epic 0);
- `Install.Step.Production.WriteDefault` (the bridge accessor);
- `Test.Data.Fixture.SetTelegramIncluded`;
- the mock's Bot API side and `Test.Contract.Mock`'s helpers (Story 10.3).

**Extend, don't copy (Rule 2):**
- The step follows `SetEval` and calls `WriteDefault`, so there is no second writer.
- `BotCall` calls `BotReply`, which holds its old body, and `Control` gains an output.
- `/updates {"scenario"}` reuses the scenario lookup of `/replies` and the id assignment of `/updates`.
- `live_no_bot_token` follows the generated-file pattern of `$tmp/compose.tz.yml` and `port.yml`.
- `check_telegram_off` follows `check_eval`.
- One exception: `TelegramSwitch` saves and restores its two rows itself. `Test.Install.Production`'s `RowId` and `RestoreRow` are private and keyed to EvalIn's one row, and the copy is a few lines.

**Footprint:**
- **Epic 12's own:** `Test/Channel/TelegramSwitch.cls` and `Test/Channel/TelegramMock.cls` (new); the five new `ci/mock/scenarios/A/telegram-*.json` files.
- **Contended (Epic 15, `Install/**`):** `Install/Step/Telegram.cls`, filled in place as its stub says. The registry's order is unchanged. This needs the orchestrator's ruling at the spec gate.
- **Shared by region:** `ci/units.sh` (`Channel` appended to `lane-a`, Epic 12's own entry).
- **Cross-lane: Lane B's files, not contended.** These are the edits the epic context lists for DW-367 and DW-370 as "to settle when the story is planned":
  - `ci/mock/mock.mjs` and `ci/mock/test/telegram.test.mjs`;
  - `Test/Contract/Mock.cls`;
  - `docker/tests/lib-live.sh`, `docker/tests/test-lib-live.sh` and `docker/tests/test-production-restart.sh`.

  Three ADs bear on them: AD-29 keeps the Telegram epic inside Lane A's files; AD-33 lets only the owning lane edit a class; and AD-22 makes new mock behaviour Lane B's, asked for under AD-33. This plan makes that ask here, for the orchestrator's ruling at the spec gate.
- **Fallback if the orchestrator refuses:**
  - DW-370 by "reset the offset": a Lane A test helper clears `TelegramIn`'s kept offset with each reset, and the update scenarios are queued as replies only, with no change to the mock or `Contract.Mock`.
  - DW-367's live start is asked of Lane B.
- **Spine:** AD-22's as-built shard list ("`lane-a`: Agent, Bridge, Checks, Fix, Install, Tools, Digest and Watch") gains `Channel`. This is a factual as-built correction for the lead (Rule 20), like the one after Epic 1 added Tools and Digest.

**Owned ledger:** Both entries are addressed and none is declined.
- DW-367: the `lib-live.sh`, `test-lib-live.sh` and `test-production-restart.sh` tasks, and the "CI start with no token" and `live_key_count` rows.
- DW-370: the `mock.mjs`, `telegram.test.mjs`, `Contract.Mock` and `TelegramMock` tasks, and the "Reset keeps counting" and "A direct-call test owns the Bot API side" rows.

**Decided in-stage:**
1. The switch is two structural System Default Setting rows written through `WriteDefault`, as EvalIn's is. The XData flag stays `false`.
2. "Set" means not empty.
3. The step records `off` only on the disabled path. On the enabled path the mark is `TelegramIn`'s (AD-14).
4. `Run()` is `Apply(Included(), TokenSet())`. Tests drive `Apply` with all four combinations, whatever the environment, and run `Run()` in the stack's own environment.
5. No enabled stub runs in this story. The rows are the pinned surface.
6. DW-367 is settled by an explicit empty value; see above.
7. DW-370 is settled by ids that keep counting, update scenarios queued as inbound updates, and a direct-call test that checks first that no `TelegramIn` job is live.
8. The scenario names start with `telegram-`. The 429 has `retry_after` 2, so a retry can be told apart from a 1-second default. The 409 uses the Bot API's own text.
9. The new area `Channel` is appended to `lane-a`.
10. `Contract.Mock`'s helpers are extended (`BotReply`, `Control`'s output, `TelegramPollerReason`), not copied.
11. The step prints no `WARN` line, because that would be public-facing text that the UX and the PRD don't specify.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=12 stage=implement'`, run from the worktree root.
- Run one command per tool call, in the foreground, with `timeout: 600000`. Never put two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to the end in foreground calls of under 170 s each, and never start a second copy.
- IRIS tests run only on throwaways, never on `ocutalon-slot-a`.
- A warm run refuses any change under `ci/mock/`. After such a change, run `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh down`, then `up`.

**Commands:**
- (loop) `bash docker/tests/test-mock.sh`. Expected: every node test passes.
- (loop) `bash docker/tests/test-lib-live.sh`. Expected: all checks pass.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh up`, once per stage. Expected: the stack is ready.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s1iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramSwitch`, `OcuTalon.Test.Channel.TelegramMock`, `OcuTalon.Test.Contract.Mock`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live production-restart`, on a fresh stack (about 90 to 120 s locally). Expected: every PASS line, including the new Telegram lines.
- (once) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s1iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Web.PairingApi`, `OcuTalon.Test.Web.Api`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh down`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: both classes pass in both orders.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh shard lane-b@Contract`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live production`, then `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live compose-start`, one per call. These consumers of `live_key_count` are unchanged. Expected: passed.
- (once) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash docker/tests/test-readme.sh`, one per call. Expected: each passes, and every test class runs once.
- (once) Write the story's changed and new paths (`git diff --name-only HEAD` plus `git ls-files --others --exclude-standard`) to a file in the stage's scratchpad folder. Then run `bash ci/changes.sh ci.yml --paths-from <that file>`. Expected: exit 0, with one `GROUP` line per group.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh teardown`, also after a failure, and `ci/warm.sh down` if it has not run.
- CI runs every group on fresh instances on each push (Rule 23). The `browser` group (REL-2's demo path, and `sign-in` with R11), both install groups, `image` (`shard:lane-b`), `shards` and `shards-2` (`lane-a@rest`, now with `Channel`) are left to CI.

**Shared surfaces:**
- **Two new structural System Default Setting rows** (`TelegramIn` and `TelegramOut`, `Enabled`), written at every start. `Test.Install.Production` reads only EvalIn's row, the live scripts read only rows they name, and no test counts the production's rows. `Test.Fix.Snapshot` compares rows before and after inside one test, and only a start writes these rows.
- **The Telegram mark**, which now exists with `off` after every start that leaves Telegram off. Its readers already see `off` when there is no mark, so the value they read is unchanged: `/state` (`Test.Web.Api`, `Test.Web.PairingApi`), `rail.spec.ts` R11 and `Test.Demo.Guide`.
- **`ci/units.sh`'s `lane-a` areas** (with `Channel` added): `test-ci-config.sh` (it works out its checks), `ci/iris.sh classes lane-a` and the class list of `shards-2`.
- **The mock's scenario list** (5 new `telegram-*` files): `scenarios.test.mjs` row 15, and the health counts, which are computed from the tree.
- **The mock's Telegram control endpoint**:
  - a reset now keeps the counters, which changes `telegram.test.mjs` :165-168 and `Test.Contract.Mock.TestTelegramBotApi`;
  - `/updates` now also takes `{"scenario"}`.
- **`live_key_count`'s rule for an empty token**: `test-lib-live.sh` :718, and every live script's `check_no_key`. CI starts hold the dummy, so their counts are unchanged.
- **`Test.Contract.Mock`'s helpers**: `BotCall` now goes through `BotReply`, and `Control` has a new optional output. Today only the class itself calls them.
- **The production's item list and enabled flags** are unchanged (`Test.Install.Production`, `Test.Core.ProductionItems`, `check_items_run`).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each one, sees red, reverts the change byte for byte, and records `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| No token (FR-21) | `Apply` ignores `tokenSet` | `TelegramSwitch` `Apply(1, 0)`; `production-restart` row 19's rows |
| Not included (a release before 12.7) | `Apply` ignores `included` | `TelegramSwitch` `Apply(0, 1)`; `production-restart`'s first-start rows |
| Records `off` | The disabled path records nothing | `TelegramSwitch`; `production-restart` row 19's mark (it was `on` before) |
| The mark is `TelegramIn`'s when enabled | `Apply` records `off` on both paths | `TelegramSwitch` `Apply(1, 1)` |
| Structural | `Run` writes the rows only when they are absent | `TelegramSwitch`'s structural test |
| No leak | The row description carries the token | `TelegramSwitch`'s `Run` check |
| No Bot API call at a start | `Run` makes one `getMe` call | `production-restart`'s first-start calls (`200` with 1 call) |
| Update scenarios | `telegram-group-update.json`'s chat type becomes `private` | `TelegramMock`'s update test |
| Reply scenarios | `telegram-rate-limited.json` loses `parameters` | `TelegramMock`'s reply test |
| DW-370: the counter | `reset` sets `tg.nextUpdateId = 1` again | `TelegramMock`'s reset row; `telegram.test.mjs`'s reset test |
| `/updates {"scenario"}` | The mock keeps the file's `update_id` | `telegram.test.mjs`'s scenario test |
| DW-370: the poller check | `TelegramPollerReason` always returns `""` | `TelegramMock`'s check row (`Decide`) |
| DW-367: the count | `live_key_count` counts an empty token again | `test-lib-live.sh`'s row; `production-restart` row 19's `check_no_key` |
| DW-367: the file | `live_no_bot_token` writes the dummy | `production-restart` row 19's "set and empty" check and `TokenSet` 0; `test-lib-live.sh`'s row |
| `Included()` unchanged | `Included()` returns 1 | `test-readme.sh` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned and halted after planning (`Halt after planning.`). The spec passed the READY FOR DEVELOPMENT gate after one repair pass (explicit labels for the live checks, the `Run()` row's wording, and the boundary on new text). Before implementation, the orchestrator rules at the spec gate on the contended edit (`Install/Step/Telegram.cls`, Epic 15) and the Lane B edits listed under Design Notes, Footprint (AD-22, AD-29, AD-33).
