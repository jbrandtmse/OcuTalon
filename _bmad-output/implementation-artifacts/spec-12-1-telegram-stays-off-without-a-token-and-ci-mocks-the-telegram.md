---
title: 'Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: '7f0a6fdbe4f2ec53bc034b2de603d40ec86c2e01'
baseline_commit: '7f0a6fdbe4f2ec53bc034b2de603d40ec86c2e01'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, AD-5, AD-14, AD-19, AD-22, AD-23, AD-29 and AD-33)'
warnings: ['oversized']
deferred:
  - summary: >-
      The kept-offset location (`$$$EnsStaticAppData("TelegramIn", "offset")`) is pinned only against the helper that writes it.
    evidence: |-
      `TelegramMock.TestResetClearsKeptOffset` sets, reads and clears the node through `BotApi` alone; `TelegramIn` is still the stub and keeps no offset, so a Story 12.2 poller that stored its offset elsewhere would leave every test here green and DW-370's Lane A half doing nothing. Story 12.2's tests must prove that its poller's offset node is `BotApi.Offset()`'s node.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The Telegram installer step is an empty stub. Nothing switches `TelegramIn` and `TelegramOut` from `Included()` and `TELEGRAM_BOT_TOKEN`, and nothing records `off` when Telegram stays off. CI has no way to make a start with no bot token, because its override always sets the dummy (DW-367). The mock has no Lane A Telegram scenarios, and its reset restarts the update ids, so a poller that keeps its offset would drop the next updates (DW-370).

**Approach:** Fill the Telegram step in place as the one switch. At every start it writes the `Enabled` System Default Setting rows of both items: 1 only when `Included()` returns 1 and the token is not empty, and 0 otherwise. When it leaves them disabled, it records `off`. Also: add Lane A's five Telegram scenarios as new files under `ci/mock/scenarios/A/`, queued through the mock's existing control endpoint as replies per method; make a CI start with no token use an explicit empty token, in Lane A's allowed `docker/tests` layer; and meet DW-370 from Lane A's side, with a Lane A test helper under `Test/Channel/**` that resets the mock's Bot API side and clears the update offset `TelegramIn` keeps in the same call, so a poller never drops updates after a reset. The mock's code, its node tests and `Test.Contract.Mock` do not change (the orchestrator's spec-gate ruling of 2026-10-30, under AD-22 and AD-33). `Included()` keeps its test-only body.

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
  - `ci/compose.ci.yml`, `web/` or the README;
  - Lane B's mock code and its tests: `ci/mock/*.mjs`, `ci/mock/test/**` and `Test/Contract/Mock.cls` (AD-22: new mock behaviour is Lane B's, asked for under AD-33; orchestrator ruling 2026-10-30). Lane A's Telegram test helpers live in `Test/Channel/**`. A criterion that still needs new mock behaviour is reported as a Lane B ask, never built here.
- In `docker/tests/lib-live.sh`, change only this story's own functions and layers (`live_key_count`'s empty-token rule, the new `live_no_bot_token`), never `iris_script` (Epic 29's Story 29.4 may edit it).
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
| Update scenarios | `POST /_mock/telegram/replies {"scenario": "telegram-private-update"}`, then `getUpdates`; the same for `telegram-group-update` and `telegram-button-update` | Each `getUpdates` answers 200 with its scenario's one update: a `message` in a private chat, a `message` in a `group` chat, and a `callback_query` from a private chat. | — |
| Reply scenarios | `/replies {"scenario": "telegram-conflict"}`, then `getUpdates`; `telegram-rate-limited`, then `sendMessage` twice | `getUpdates` answers 409 with `error_code` 409 and a description that starts with "Conflict". The first `sendMessage` answers 429 with `error_code` 429 and `parameters.retry_after` 2. The second gets the 200 default. | — |
| Calls read back | After each group above | `/_mock/telegram/calls` lists each call in order, with its method and parameters. The mock's log shows the path `/bot[redacted]/<method>` and the token's length, and never the token. | — |
| Reset with the kept offset (DW-370, from Lane A's side) | `TelegramIn`'s kept offset at `n+1` after ids up to `n`; the Lane A helper resets the mock's Bot API side; one update queued through `/updates` (it gets id 1); `getUpdates` with the offset the helper left | The helper has cleared the kept offset in the same call as the reset, so `getUpdates` returns the new update rather than dropping it. | — |
| A direct-call test owns the Bot API side (DW-370) | The Lane A helper's poller check, for `TelegramIn` and for an item with a live job (`Decide`) | `""` for `TelegramIn`. For `Decide`, a reason that names the item. `Test.Channel.TelegramMock` fails with that reason, and sends nothing, whenever it is not empty. | — |
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

**The mock: Lane B's, read only (ruling of 2026-10-30)**
- `ci/mock/mock.mjs`:
  - the header :9-23 describes the Bot API side and its control routes;
  - `reset` :328-337 clears the updates, the replies and the calls, and restarts `nextUpdateId` and `nextMessageId` at 1. This is why the kept offset is cleared with every reset;
  - `/updates` :345-361 queues updates with the next ids, replacing any `update_id` given;
  - `/replies` with `{"scenario"}` :366-374 queues a `telegram` scenario's replies for its method. Anything else in the same body is a 400;
  - a queued reply answers before the update queue (:578) and is sent as written, its `update_id` included;
  - `pendingUpdates` :394-397: `getUpdates` drops the queued updates below its offset. With no offset it drops none.
- `ci/mock/scenarios.mjs:16-22` (the telegram form) and `checkReply` :108-150: a telegram reply holds only `status`, `headers`, `delayMs` and a `body` that is a JSON object. A name is kebab-case, equals its file name and is unique across `A/` and `B/`. No `telegram-*` name exists yet.
- `ci/mock/test/scenarios.test.mjs:125-131` (row 15) loads every committed file and wants no problem. The scenario counts are computed from the tree (`server.test.mjs:665`, `telegram.test.mjs:370`), so the five new files need no other change.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls`:
  - the parameters `TELEGRAMBASE` :53 (`http://mock:8080`), `TELEGRAMBASEVAR` :56 and `TELEGRAMTOKENVAR` :58;
  - the public helpers to call: `TelegramMissingReason(base, token)` :394, `BotCall(token, method, body)` :403 (throws on any status but 200), `Control(route, body)` :417 (1 when the mock answered 200), `Calls()` :429, `LogMark()` :471 and `LogSince(mark, .entries)` :484;
  - private, so not callable: `LogHolds` :570 and `NewRequest` :586;
  - `TestTelegramBotApi` :348-390 resets the mock, then expects `update_id` 1, `message_id` 1 and exactly its own 3 calls (DW-370's residual).

**The kept offset and the poller check**
- `irislib/Ensemble.inc:134`: `$$$EnsStaticAppData` is `^Ens.AppData`. `irislib/Ens/Adapter.cls:93-99` (`ClearStaticAppData`) calls it the store for persistent adapter values, such as the SQL inbound adapter's `%LastId`; it survives restarts. `$$$EnsRuntimeAppData` (:133) is cleared at each item start, so it would lose the offset.
- `Install/Step/Production.cls:98-121` `NotRunning()`: the `Ens.Job:Enumerate` loop (`State` "Alive", `DEADSTATUSES` :42) that the poller check follows.
- `ci/iris.sh:131-149` `is_test_case`: a class with no `Method Test...` is not a test class, so a helper class in `Test/Channel/` joins no shard run.

**CI**
- `docker/tests/lib-live.sh`:
  - `live_add_file` :152 and `live_pop_file` :611;
  - `check_items_run` :631-647;
  - `live_ci_bot_token` :649-651;
  - `live_key_count` :656-666: counts any `TELEGRAM_BOT_TOKEN` that is set and is not the dummy, an empty one included;
  - `check_no_key` :668-677.
- `docker/tests/test-lib-live.sh:682-734`: the `live_key_count` rows; :718 pins "an empty bot token counts 1".
- `docker/tests/test-production-restart.sh`: the header :1-30; `check_eval` :50-66; the first start :78-95; row 19's two recreates :97-119 (with `OCUTALON_EVAL=1`, then without).
- `ci/units.sh:14-21`: `shard_areas`. `lane-a@rest` (in `shards-2`) takes any new area. `docker/tests/test-ci-config.sh` works out its area checks itself and holds no literal area list or class count.
- `.env.example` has `TELEGRAM_BOT_TOKEN=` (empty), and `docker-compose.yml` passes `.env` as the `env_file`.

## Tasks & Acceptance

**Execution:**
- `ci/mock/scenarios/A/telegram-private-update.json`, `telegram-group-update.json` and `telegram-button-update.json` (new). Write the five scenario files before `ci/warm.sh up`, because a warm stack refuses any change under `ci/mock/`.
  - Each has `match: {"telegram": "getUpdates"}` and one reply `{"status": 200, "body": {"ok": true, "result": [<one update>]}}`, whose update has `"update_id": 1`.
  - The updates are a text `message` in a chat of type `private`; a `message` in a chat of type `group`; and a `callback_query` from a private chat whose `data` names no request (`ocutalon-ci-unknown-press`).
  - Use fixture ids and names only, never a real person's.
- `ci/mock/scenarios/A/telegram-conflict.json` and `telegram-rate-limited.json` (new):
  - `getUpdates`: 409 `{"ok": false, "error_code": 409, "description": "Conflict: terminated by other getUpdates request; make sure that only one bot instance is running"}`;
  - `sendMessage`: 429 `{"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 2", "parameters": {"retry_after": 2}}`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls`: fill it in place.
  - `Run()` returns `Apply(##class(OcuTalon.Channel.Telegram.In).Included(), TokenSet())`.
  - `TokenSet()` is 1 when `$SYSTEM.Util.GetEnviron("TELEGRAM_BOT_TOKEN")` is not empty, and 0 otherwise. It returns nothing else.
  - `Apply(included, tokenSet)` writes both rows: 1 only when both arguments are 1, else 0. Each row's description says that the step writes it at every start, from `Included()` and whether `TELEGRAM_BOT_TOKEN` is set. On the disabled path, `Apply` also records `off`.
  - The first failure is the step's status.
  - Replace the stub's doc comment with this contract (AD-23, AD-14).
- `src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls` (new): Lane A's helpers for the mock's Bot API side (DW-370). It has no `Test` methods, and it includes `Ensemble`.
  - `Offset()`: the offset that `TelegramIn` keeps, `$Get($$$EnsStaticAppData("TelegramIn", "offset"))`, or `""` when there is none. `SetOffset(offset)` sets it, or kills it for `""`; a test calls it to stand in for the poller.
  - `PollerReason(item = "TelegramIn")`: `""` when the item has no `Alive` job (`Ens.Job:Enumerate`). Otherwise a reason that names the item and says that a reset would take its updates.
  - `Reset(poller = "TelegramIn") As %Status`. When `PollerReason(poller)` is not empty, it returns an error with that reason, and it sends nothing and clears nothing. Otherwise, in the one call, it kills the kept offset and resets the mock through `Test.Contract.Mock.Control("reset")`. It returns an error when the mock did not answer 200.
  - `BotReply(token, method, body, Output statusCode) As %DynamicObject`: POST `/bot<token>/<method>` to `Test.Contract.Mock`'s `TELEGRAMBASE`, with the JSON body (none when `""`). It returns the parsed body and the status, whatever the status. It throws only when the mock can't be reached, with a text that names the method and never the token.
  - The class doc states each helper's contract and the offset's location (Rule 14).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramSwitch.cls` (new): the tests of the switch.
  - Covers every `Apply` row of the matrix; `Run()` with the seam at 0 and at 1, in the stack's own environment, with the check that nothing holds the token; and the structural row.
  - Reads each row with `%GetSetting`, as `Runners()` does.
  - Saves both rows, the mark and the seam as found, and puts them back (OnBeforeAllTests and OnAfterAllTests).
  - Never calls `Ens.Director`. Runs anywhere.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramMock.cls` (new): the Integration AC. Runs in throwaways and CI only.
  - Every test first checks `Test.Contract.Mock.TelegramMissingReason(base, token)` and `BotApi.PollerReason()`. When either gives a reason, the test fails with it and sends nothing.
  - Every test starts and ends with `BotApi.Reset()`, which must return OK. That leaves the mock empty and no kept offset.
  - Update rows: for each update scenario, `Control("replies", {"scenario": <name>})`, then `getUpdates`. Use `Test.Contract.Mock.BotCall` where the answer is 200, and `BotApi.BotReply` only where it is not.
  - Reply rows: the 409, then the 429, then the second `sendMessage`'s 200 default.
  - Calls rows: `Calls()` lists the group's calls in order, with their methods and parameters. Between `LogMark()` and `LogSince()`, every line whose path starts with `/bot[` is `/bot[redacted]/<method>` with the token's length, and no line holds the token. `LogHolds` is private, so search the entries.
  - Reset row: queue two updates through `Control("updates", ...)`; `getUpdates` at offset 0 returns ids 1 and 2; `SetOffset(3)`; `BotApi.Reset()`; `Offset()` is `""`; queue one update, which gets id 1; `getUpdates` with the offset the helper left (none) returns it.
  - Poller-check rows: `PollerReason()` is `""`; `PollerReason("Decide")` names `Decide`. Then `SetOffset(5)` and one queued update; `Reset("Decide")` returns an error naming `Decide`; `Offset()` is still 5, and `getUpdates` at offset 0 still returns the queued update.
- `docker/tests/lib-live.sh` (DW-367):
  - `live_key_count` counts `TELEGRAM_BOT_TOKEN` only when it is not empty and is not the dummy.
  - New `live_no_bot_token`: writes `$tmp/no-bot-token.yml`, which sets `services.iris.environment.TELEGRAM_BOT_TOKEN: ""`, and adds it with `live_add_file`. `live_pop_file` removes it.
  - Update the header comment and `check_no_key`'s comment. Change nothing else; never `iris_script`.
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
- Given the mock with Lane A's scenarios, when IRIS queues each one as replies through the control endpoint and calls the Bot API as the Telegram service will, then each answers as the matrix says, the calls read back in order, and the log holds only the token's length (FR-22, AD-22, NFR-11).
- Given a test that resets the mock's Bot API side through `Test.Channel.BotApi.Reset`, when it then queues an update and calls `getUpdates` with the offset the helper left, then the update comes back, because the reset cleared `TelegramIn`'s kept offset in the same call; and while the poller item has a live job, the helper refuses with a reason that names it, and resets and clears nothing (DW-370, Lane A's half).
- Given this story merged, when the README check, `/state` and the pairing routes run, then `Included()` keeps its test-only body, `/state` hides Telegram and the pairing routes answer 404 (`test-readme.sh` and `Test.Web.PairingApi`, unchanged; FR-58).
- Given CI's `browser` group, when the demo path and `sign-in` run, then REL-2's specs pass with Telegram's parts not run, and R11 shows "Telegram not set up" with no banner (unchanged; CI; UX-DR17, UX-DR56).

## Spec Change Log

- 2026-10-30, spec gate (runner, from the orchestrator's rulings; re-plan of the mock part only). Q1: filling `Install/Step/Telegram.cls` in place is allowed (a file-level footprint extension into Epic 15's `Install/**`). Q2: `docker/tests/lib-live.sh`, `test-lib-live.sh` and `test-production-restart.sh` are allowed (DW-367 stays as planned); `ci/mock/mock.mjs`, `ci/mock/test/telegram.test.mjs` and `Test/Contract/Mock.cls` must not change (comply with AD-22 and AD-33, U7 step 1): DW-370 is met from Lane A's side (a `Test/Channel/**` helper resets the Bot API side and clears `TelegramIn`'s kept offset together), the update scenarios are queued as replies, and Lane A's helpers live in `Test/Channel/**`. Q3: the spine is left alone; DW-420 records AD-22's as-built `Channel` for the orchestrator. The intent block's Approach, Never list and the update, reset and poller-check rows were changed to match; the `/updates` refusal row was removed. Status reset to `draft` for the re-plan.

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 34 findings - high 0, medium 3, low 28, false 2, maybe-false 1
- findings:
  - `[low]` `[patch]` TestPollerCheck needs a live `Decide` job and has no explicit precondition (blind, edge, verification-gap, intent: one root cause, four rows) - patched: the test fails with a message naming the missing production when `PollerReason("Decide")` is empty, and the refusal assertions run only in the `Else` branch.
  - `[low]` `[reject]` `live_key_count` counts an empty `ANTHROPIC_API_KEY` but not an empty bot token (blind, edge: two rows) - the spec limits the change to the empty-token rule (DW-367); the model key's rule is out of this story's intent.
  - `[low]` `[reject]` `BotApi.BotReply` repeats `BotCall`'s request (blind) - the copy is named and justified in the spec's Design Notes (Rule 2); the unification is the Lane B ask.
  - `[low]` `[reject]` `Reset` kills the offset before the mock answers, so a non-200 leaves the offset gone (blind, edge: two rows) - the spec states the order; the offset is test state with no consumer until 12.2, and the error status is returned.
  - `[low]` `[reject]` Untested claims in `Telegram.cls` (a `WriteDefault` failure, the registry order, a whitespace-only token, an always-empty status text on an OK status) (blind, verification-gap: three rows) - "set means not empty" is a decision in the spec; the registry order is pinned by `Test.Install.Registry`; the row, description and mark parts of the leak check are falsifiable (mutation demonstrated).
  - `[low]` `[patch]` `check_telegram_off` hard-codes the mark name (blind, edge: two rows) - patched: it reads `StatusMark`'s `#TELEGRAMMARK`.
  - `[low]` `[patch]` Fixed `Hang 0.2` before reading the mock's log (blind, edge, verification-gap: three rows) - patched: `TestCallsAndLog` polls `LogSince` up to 5 s until the four Bot API lines are in.
  - `[low]` `[patch]` `Safe()` drops all text after the token (blind) - patched: the token is replaced with `[token]`, so the diagnostics stay.
  - `[low]` `[reject]` No node test for the new scenario files (blind) - `scenarios.test.mjs` row 15 already loads and validates every committed file, and a change to `ci/mock/test/**` is Lane B's; `TelegramMock` pins the content.
  - `[maybe-false]` `[reject]` `PollerReason` counts only `Alive`, not a job in `Starting` (edge) - it follows `Install.Step.Production.NotRunning()`; no CI start runs `TelegramIn` until Story 12.7, whose own change would need the check; a low if true.
  - `[low]` `[reject]` A live `TelegramOut` or another Bot API caller would add calls to `TestCallsAndLog` (edge) - `TelegramOut` is not a poller and sends only on a message; no Bot API caller runs at any start through 12.6.
  - `[low]` `[reject]` `BotReply` has no guard for a non-JSON body or a base with no port (edge, blind: two rows) - `TELEGRAMBASE` is a fixed constant with a port, and the mock answers JSON.
  - `[medium]` `[patch]` Row 19's empty-token start has no recorded mutation and no proof that the seam survives the recreate (verification-gap, two rows) - demonstrated: `Apply` ignoring `tokenSet` turns `production-restart` red at row 19 (the rows are 1), which also proves the seam survives; the line is in `## Verification`.
  - `[medium]` `[patch]` `TestCallsAndLog` and three of the five scenario files have no mutation line (verification-gap) - demonstrated: the private, button, conflict and rate-limited files each turn their test red; the lines are in `## Verification`. The duplication with Lane B's `TestTelegramBotApi` is by design (it is the ruling's reading of AC 4).
  - `[medium]` `[defer]` The kept-offset node is pinned only against the helper (verification-gap, intent: two rows) - nothing reads the node until Story 12.2; deferred with the evidence to carry into 12.2's tests.
  - `[false]` `[reject]` The stored `off` mark could change `/state` or the card (verification-gap) - `StatusMark.TelegramState` returns `off` for no mark and for a stored `off`, so readers see the same value; `Test.Web.Api` and `Test.Web.PairingApi` ran green.
  - `[low]` `[reject]` `TestRun` takes the seam-1 path only when the stack holds a token (verification-gap) - the spec says `Run()` runs in the stack's own environment; the enable path is pinned by `TestApply` in any environment.
  - `[low]` `[reject]` `TestRun`'s `TokenSet()` assertion recomputes the same expression (verification-gap) - a one-line contract check; the rows are what pins the behavior.
  - `[low]` `[reject]` The "prepared" session reads back what it wrote (verification-gap) - the mutation run of row 19 shows the seam and mark survive the recreate.
  - `[low]` `[reject]` Enabled items never run in any test; `Run()` is not tested through the registry; `TelegramMock` is throwaway-only; the empty token is a helper, not a CI mode; the poller check uses `Decide` as the live item (intent: five rows) - each is the spec's stated design (Design Notes "Why no enabled stub runs", the Task list, the Lane B ask); the docker start runs the real step.
  - `[false]` `[reject]` `Run()` is not exercised in a real start (intent) - `production-restart` runs the real step in three real starts.

## Design Notes

**Spec-gate rulings (orchestrator, 2026-10-30; binding on the re-plan).**
1. `Install/Step/Telegram.cls`: allowed, filled in place as the one switch, through `Install.Step.Production.WriteDefault`, with the registry's order unchanged. Report it as a footprint extension into Epic 15's `Install/**`.
2. Lane B files, split. Allowed: `docker/tests/lib-live.sh` (only this story's own functions and layers; never `iris_script`, which Epic 29's Story 29.4 may edit), `docker/tests/test-lib-live.sh`, `docker/tests/test-production-restart.sh`. Not allowed (comply, U7 step 1): any change to `ci/mock/*.mjs`, `ci/mock/test/**` or `Test/Contract/Mock.cls`. So: the update scenarios are new files under `ci/mock/scenarios/A/`, queued as replies; DW-370 is answered from Lane A's side by a helper under `Test/Channel/**` that resets the mock's Bot API side and clears `TelegramIn`'s kept offset in the same call (the plan fixes where that offset is kept, for Story 12.2 to use); Lane A's test helpers, the poller check included, live in `Test/Channel/**`, extending or reusing `Test.Contract.Mock`'s public helpers by calling them, never by editing them. DW-367's no-token start stays in the allowed `docker/tests` layer.
3. If any criterion or ledger entry still needs new mock behaviour after this, name it under `## Design Notes` as "Lane B mock ask (AD-22, AD-33)", with what it needs and why; the runner files it in the ledger for the decision sheet. Do not plan around it with new mock code.
4. The spine stays as it is; DW-420 records that AD-22's as-built `lane-a` list gains `Channel`, which the orchestrator writes at the merge gate.

**Governing ADs:**
- AD-23: the one Telegram switch, the registry's order, and that a failed step stops the start.
- AD-14: the token comes only from the environment; who records the Telegram state.
- AD-19: bot tokens come from the environment; structural values are rewritten at every start.
- AD-3: the production class holds structure only, and switches are System Default Settings.
- AD-5: the kept offset is state that survives restarts.
- AD-22: the CI override, the mock and the scenario files; Lane A extends the mock only by adding files under `ci/mock/scenarios/A/`, and new mock behaviour is Lane B's, asked for under AD-33.
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

**DW-370 (re-judged after the ruling: met in part).**
- **Met from Lane A's side: the updates dropped after a reset.**
  - `TelegramIn` keeps the next offset to confirm (the last handled `update_id` plus 1) at `$$$EnsStaticAppData("TelegramIn", "offset")`, that is `^Ens.AppData("TelegramIn", "offset")`, and nowhere else. No node means no offset.
  - `Test.Channel.BotApi.Reset` kills that node in the same call that resets the mock. After the mock's ids restart at 1, the poller polls with no offset and gets the new updates, rather than confirming them away.
  - The helper refuses to reset while the poller item has a live job. So a Lane A test never resets under a live `TelegramIn`, and never takes its updates or its calls.
  - A scripted `getUpdates` reply keeps its file's `update_id` (1). After the helper's reset that id is new to the poller, so a test queues one update source per reset.
- **Not met: one client.**
  - `Test.Contract.Mock.TestTelegramBotApi` (Lane B's) resets the mock with neither the check nor the offset, and expects `update_id` 1, `message_id` 1 and exactly its own 3 calls. That holds while no poller runs in its stack. It breaks once `TelegramIn` polls at CI starts, from Story 12.7: the poller can take the update the test queued, and its `getUpdates` calls join the list.
  - A reset made outside the helper restarts the ids under a kept offset, and the helper can't reach it.
  - The mock's Bot API side stays one queue, one call list and one pair of counters for every client.
  - Through Story 12.6, no CI start runs `TelegramIn`, because `Included()` is 0 at every start, and a Lane A test that runs it must stop it before it returns. From Story 12.7, `TelegramIn` runs at every CI start, so `Test.Channel.TelegramMock` fails its own check until 12.7 stops the poller around it or the ask below lands. The check makes that impossible to miss.

**Lane B mock ask (AD-22, AD-33):**
- **What:** keep the Bot API side's state per token: the updates, the replies, the calls and the counters, keyed by the `/bot<token>/` segment, with the control routes naming the token. A direct-call test with its own dummy token then shares nothing with `TelegramIn`. Without that, `Test.Contract.Mock.TestTelegramBotApi` must stop `TelegramIn` around itself (or fail with a reason, as Lane A's check does), and read its ids from the mock's answers (`updateIds`) instead of expecting 1.
- **Why:** a live `TelegramIn` and a direct-call test can't share one queue and one call list, and Lane A's helper reaches only Lane A's resets.
- **First needed by:** Story 12.7. It makes `Included()` return 1, so `TelegramIn` polls the mock at every CI start, `shard:lane-b` in the `image` group included.
- **With it:** `Test.Channel.BotApi.BotReply` repeats `Test.Contract.Mock.BotCall` without its throw (Rule 2, below). If `BotCall` gained a status output, or `NewRequest` became public, the copy could go. That is Lane B's choice, so the runner can file it with the same ask.

**Integration ACs (Rule 1).** Four consumers read what this story adds:
- The start's `Production` step reads the rows. In `test-production-restart.sh`, the items have no job and every other item runs.
- `/state` and the card read the mark (R11, unchanged).
- IRIS's Bot API calls read the scenarios (`Test.Channel.TelegramMock`).
- `Test.Channel.TelegramMock` uses `Test.Channel.BotApi` against the real mock.

**Consumed-by:**
- Story 12.2:
  - `TelegramIn`'s first enabled start through the switch;
  - the update scenarios and the 409;
  - the kept offset at `$$$EnsStaticAppData("TelegramIn", "offset")`. `TelegramIn` keeps the next offset there and nowhere else. It uses that one value both to confirm updates and to skip the ids it has handled, and reads it when it starts polling, so a reset made while it is stopped takes effect at its next start;
  - `Test.Channel.BotApi`'s `Reset`, `PollerReason`, `BotReply`, `Offset` and `SetOffset`, for its tests.
- Stories 12.4 and 12.5: the private and group updates, and `BotApi`.
- Story 12.6: the 429, for `TelegramOut`'s retry, through `BotReply`.
- Story 12.7: the button update; `Included()` returning 1; `live_no_bot_token`; the poller check; and the residual named in the Lane B ask.

**Consumes** (all used against the real mock and a real start):
- `StatusMark.RecordTelegram` and `TelegramState` (Story 10.3);
- `Channel.Telegram.In.Included()` (Epic 0);
- `Install.Step.Production.WriteDefault` (the bridge accessor);
- `Test.Data.Fixture.SetTelegramIncluded`;
- the mock's Bot API side and `Test.Contract.Mock`'s public helpers and parameters (Story 10.3), all called, none changed;
- the platform's `Ens.Job:Enumerate` query and `$$$EnsStaticAppData`.

**Extend, don't copy (Rule 2):**
- The step follows `SetEval` and calls `WriteDefault`, so there is no second writer.
- `BotApi` and `TelegramMock` call `Test.Contract.Mock`'s `TelegramMissingReason`, `BotCall`, `Control`, `Calls`, `LogMark`, `LogSince` and its `TELEGRAM*` parameters. They copy none of them.
- One copy: `BotApi.BotReply` repeats `BotCall`'s request, about 8 lines, without the throw on a status other than 200. `BotCall` throws on the 409 and the 429 that this story must read, `NewRequest` is private, and the ruling keeps `Test.Contract.Mock` unchanged (AD-33). The unification is Lane B's (see the ask).
- `PollerReason`'s job query follows `Install.Step.Production.NotRunning()`. It is not a call, for two reasons. `NotRunning` answers a different question (which enabled items have no live job), and it sits in Epic 15's contended `Install/**`. The query is a few lines.
- `TelegramSwitch` saves and restores its two rows itself. `Test.Install.Production`'s `RowId` and `RestoreRow` are private and keyed to EvalIn's one row, and the copy is a few lines.
- `live_no_bot_token` follows the generated-file pattern of `$tmp/compose.tz.yml` and `port.yml`. `check_telegram_off` follows `check_eval`.
- The scenario files follow Story 10.3's telegram form, as in `scenarios.test.mjs:218-233`.

**Footprint:**
- **Epic 12's own:** `Test/Channel/BotApi.cls`, `Test/Channel/TelegramSwitch.cls` and `Test/Channel/TelegramMock.cls` (new); the five `ci/mock/scenarios/A/telegram-*.json` files (new, in Lane A's scenario folder; no collision with Epic 9's `eval-*` or Epic 13's `bridge-example-*`).
- **`Install/Step/Telegram.cls`:** filled in place, a footprint extension into Epic 15's `Install/**` (ruling Q1). The registry's order is unchanged.
- **Allowed extensions (ruling Q2):** `docker/tests/lib-live.sh` (only `live_key_count`'s empty-token rule, the new `live_no_bot_token` and their comments; never `iris_script`), `docker/tests/test-lib-live.sh` and `docker/tests/test-production-restart.sh`.
- **Shared by region:** `ci/units.sh` (`Channel` appended to `lane-a`, Epic 12's own entry). Epic 9 appends `Eval` to the same line, so the merge is one line.
- **Nothing else.** `ci/mock/*.mjs`, `ci/mock/test/**` and `Test/Contract/Mock.cls` are read only.
- **Spine:** no change. DW-420 records that AD-22's as-built `lane-a` list gains `Channel`, and the orchestrator writes it at the merge gate.

**Owned ledger:**
- DW-367: addressed, by the `lib-live.sh`, `test-lib-live.sh` and `test-production-restart.sh` tasks and the "CI start with no token" and `live_key_count` rows.
- DW-370: addressed in part, by the `BotApi` and `TelegramMock` tasks and the "Reset with the kept offset" and "A direct-call test owns the Bot API side" rows. The residual is the one-client mock and `Test.Contract.Mock.TestTelegramBotApi`, under "Not met" above, filed as the Lane B mock ask; Story 12.7 needs it first.

**Decided in-stage** ("re-plan" marks the choices new in this re-plan):
1. The switch is two structural System Default Setting rows written through `WriteDefault`, as EvalIn's is. The XData flag stays `false`.
2. "Set" means not empty.
3. The step records `off` only on the disabled path. On the enabled path the mark is `TelegramIn`'s (AD-14).
4. `Run()` is `Apply(Included(), TokenSet())`. Tests drive `Apply` with all four combinations, whatever the environment, and run `Run()` in the stack's own environment.
5. No enabled stub runs in this story. The rows are the pinned surface.
6. DW-367 is settled by an explicit empty value; see above.
7. (re-plan) DW-370 is met from Lane A's side by `BotApi.Reset`. It refuses under a live poller, and otherwise clears the kept offset and resets the mock in one call. The residual goes to Lane B as an ask.
8. The scenario names start with `telegram-`. The 429 has `retry_after` 2, so a retry can be told apart from a 1-second default. The 409 uses the Bot API's own text.
9. The new area `Channel` is appended to `lane-a`.
10. (re-plan) The kept offset lives at `$$$EnsStaticAppData("TelegramIn", "offset")`, the platform's per-item store for persistent adapter values. It needs no new OcuTalon global, mapping, short name or table, so no AD-33 table row and no spine change, and it survives restarts (AD-5). It holds the next offset to confirm; no node means none.
11. The step prints no `WARN` line, because that would be public-facing text that the UX and the PRD don't specify.
12. (re-plan) The update scenarios are scripted `getUpdates` replies with `update_id` 1. The mock sends a reply as written, so a test queues one update source per helper reset.
13. (re-plan) The helpers are one class, `Test.Channel.BotApi`, with no `Test` methods. `Reset` and `PollerReason` take the poller item as an argument (default `TelegramIn`), so that a test can see the refusal with `Decide`, an item with a live job.
14. (re-plan) `TelegramMock` calls `BotCall` where the answer is 200 and `BotReply` only where it is not. It checks the log for the token in `LogSince`'s entries, because `LogHolds` is private.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=12 stage=implement'`, run from the worktree root.
- Run one command per tool call, in the foreground, with `timeout: 600000`. Never put two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll such a run to the end in foreground calls of under 170 s each, and never start a second copy.
- IRIS tests run only on throwaways, never on `ocutalon-slot-a`.
- A warm run refuses any change under `ci/mock/`. Add the scenario files first. After any later change there, run `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh down`, then `up`.

**Commands:**
- (loop) `bash docker/tests/test-mock.sh`. Expected: every node test passes; `scenarios.test.mjs` row 15 loads the five new files with no problem.
- (loop) `bash docker/tests/test-lib-live.sh`. Expected: all checks pass.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh up`, once per stage. Expected: the stack is ready.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s1iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramSwitch`, then `OcuTalon.Test.Channel.TelegramMock`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live production-restart`, on a fresh stack (about 90 to 120 s locally). Expected: every PASS line, including the new Telegram lines.
- (once) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s1iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Contract.Mock` (after `TelegramMock` on the same stack), `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Web.PairingApi`, `OcuTalon.Test.Web.Api`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1iw ci/warm.sh down`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: both test classes pass in both orders (`BotApi` is no test class).
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh shard lane-b@Contract`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live production`, then `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh live compose-start`, one per call. These consumers of `live_key_count` are unchanged. Expected: passed.
- (once) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash docker/tests/test-readme.sh`, one per call. Expected: each passes, and every test class runs once.
- (once) Write the story's changed and new paths (`git diff --name-only HEAD` plus `git ls-files --others --exclude-standard`) to a file in the stage's scratchpad folder. Then run `bash ci/changes.sh ci.yml --paths-from <that file>`. Expected: exit 0, with one `GROUP` line per group.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e12s1i ci/iris.sh teardown`, also after a failure, and `ci/warm.sh down` if it has not run.
- (once) `git status --short -- ci/mock/mock.mjs ci/mock/scenarios.mjs ci/mock/server.mjs ci/mock/health.mjs ci/mock/test src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` prints nothing (the ruling: Lane B's mock code, its tests and `Test.Contract.Mock` are unchanged).
- CI runs every group on fresh instances on each push (Rule 23). The `browser` group (REL-2's demo path, and `sign-in` with R11), both install groups, `image` (`shard:lane-b`), `shards` and `shards-2` (`lane-a@rest`, now with `Channel`) are left to CI.

**Shared surfaces:**
- **Two new structural System Default Setting rows** (`TelegramIn` and `TelegramOut`, `Enabled`), written at every start. `Test.Install.Production` reads only EvalIn's row, the live scripts read only rows they name, and no test counts the production's rows. `Test.Fix.Snapshot` compares rows before and after inside one test, and only a start writes these rows.
- **The Telegram mark**, which now exists with `off` after every start that leaves Telegram off. Its readers already see `off` when there is no mark, so the value they read is unchanged: `/state` (`Test.Web.Api`, `Test.Web.PairingApi`), `rail.spec.ts` R11 and `Test.Demo.Guide`.
- **`ci/units.sh`'s `lane-a` areas** (with `Channel` added): `test-ci-config.sh` (it works out its checks), `ci/iris.sh classes lane-a` and the class list of `shards-2`.
- **The mock's scenario list** (5 new `telegram-*` files): `scenarios.test.mjs` row 15, and the counts, which are computed from the tree.
- **The mock's Bot API state** (unchanged code): `TelegramMock` resets it at the start and the end of each test, and so does `Test.Contract.Mock.TestTelegramBotApi`, so the two pass in either order on one stack. In CI they run in different shards.
- **The kept offset** `^Ens.AppData("TelegramIn", "offset")` (new): nothing reads it until Story 12.2, and `BotApi.Reset` leaves it absent.
- **`live_key_count`'s rule for an empty token**: `test-lib-live.sh` :718, and every live script's `check_no_key`. CI starts hold the dummy, so their counts are unchanged.
- **The production's item list and enabled flags** are unchanged (`Test.Install.Production`, `Test.Core.ProductionItems`, `check_items_run`).
- The mock's control endpoint and `Test.Contract.Mock` do not change.
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
| DW-370: the offset cleared with the reset | `BotApi.Reset` leaves the kept offset | `TelegramMock`'s reset row (`getUpdates` at offset 3 returns no update) |
| DW-370: the poller check | `PollerReason` always returns `""` | `TelegramMock`'s check row (`Decide`) |
| DW-370: no reset under a live poller | `Reset` skips `PollerReason` | `TelegramMock`'s refusal row (the queued update is gone, and `Offset()` is `""`) |
| DW-367: the count | `live_key_count` counts an empty token again | `test-lib-live.sh`'s row; `production-restart` row 19's `check_no_key` |
| DW-367: the file | `live_no_bot_token` writes the dummy | `production-restart` row 19's "set and empty" check and `TokenSet` 0; `test-lib-live.sh`'s row |
| `Included()` unchanged | `Included()` returns 1 | `test-readme.sh` |

**Mutations demonstrated (implement stage; each applied, red observed, reverted byte for byte, and green again on the same stack).**
- mutation: `Apply` ignores `tokenSet` (`Select(included: 1, 1: 0)`) -> `TelegramSwitch.TestApply` red at `Apply(1, 0)` (rows 1, mark not off).
- mutation: `Apply` ignores `included` (`Select(tokenSet: 1, 1: 0)`) -> `TelegramSwitch.TestApply` red at `Apply(0, 1)`, and `TestRun` and `TestStructural` red.
- mutation: the disabled path records nothing -> `TelegramSwitch.TestApply` red ("the mark is off", "the mark has a row").
- mutation: `Apply` records `off` on both paths -> `TelegramSwitch.TestApply` red at `Apply(1, 1)` ("the mark is left as it was").
- mutation: `Run` writes nothing when the rows exist -> `TelegramSwitch.TestRun` (seam at 1) and `TestStructural` red.
- mutation: the row description carries the token -> `TelegramSwitch.TestRun` red ("no row value, description, status text or mark holds the token").
- mutation: `Apply` ignores `tokenSet` (live) -> `production-restart` red at row 19, no token ("every enabled item runs" and "Telegram is off": the rows are 1 and the mark stays on, so the seam survives the recreate).
- mutation: `Run` makes one Bot API call (`getMe`) -> `production-restart` red at the three `check_telegram_off` lines (the calls value: 1 call).
- mutation: `telegram-group-update.json`'s chat type `private` -> `TelegramMock.TestUpdateScenarios` red ("a text message in a group chat").
- mutation: `telegram-rate-limited.json` without `parameters` -> `TelegramMock.TestReplyScenarios` red ("429 with retry_after 2").
- mutation: `telegram-private-update.json`'s chat type `group`, `telegram-button-update.json`'s `data` changed, `telegram-conflict.json`'s status `200` -> `TelegramMock.TestUpdateScenarios` red for the private and button scenarios and `TestReplyScenarios` red for the 409.
- mutation: `telegram-rate-limited.json`'s status `200` -> `TelegramMock.TestCallsAndLog` red ("the first sendMessage is limited"), and `TestReplyScenarios` red.
- mutation: `BotApi.Reset` leaves the kept offset -> `TelegramMock.TestResetClearsKeptOffset` red ("has cleared the kept offset").
- mutation: `BotApi.PollerReason` always `""` -> `TelegramMock.TestPollerCheck` red (names the item; refusal).
- mutation: `BotApi.Reset` skips `PollerReason` -> `TelegramMock.TestPollerCheck` red (refusal, offset kept, queued update).
- mutation: `live_key_count` counts an empty token (`+x`) -> `test-lib-live.sh` red ("an empty bot token counts 0").
- mutation: `live_no_bot_token` writes a non-empty token -> `test-lib-live.sh` red ("live_no_bot_token does not add the empty-token file").
- mutation: `Included()` returns 1 -> `test-readme.sh` red (`product-links`).

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `Install/Step/Telegram.cls` is the one Telegram switch: `Run()` is `Apply(Included(), TokenSet())`; `Apply` writes both `Enabled` rows through `WriteDefault` (1 only when included and the token is not empty), and records `off` only when it leaves them disabled. Five Lane A scenario files; `Test.Channel.BotApi` (the offset at `$$$EnsStaticAppData("TelegramIn", "offset")`, the poller check, `Reset`, `BotReply`); `Test.Channel.TelegramSwitch` and `Test.Channel.TelegramMock`; `live_no_bot_token` and the empty-token rule of `live_key_count`; `production-restart` row 19 covers the no-token start; `Channel` joins `lane-a`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls`: the switch (footprint extension into Epic 15's `Install/**`, ruling Q1).
- `src/ocutalon/cls/OcuTalon/Test/Channel/BotApi.cls`, `TelegramSwitch.cls`, `TelegramMock.cls`: new.
- `ci/mock/scenarios/A/telegram-{private-update,group-update,button-update,conflict,rate-limited}.json`: new.
- `docker/tests/lib-live.sh`, `test-lib-live.sh`, `test-production-restart.sh`: DW-367 (ruling Q2).
- `ci/units.sh`: `Channel` appended to `lane-a`.

**Review.** 34 findings: high 0, medium 3, low 28, false 2, maybe-false 1. Patches applied: 6 entries (Decide precondition, mark constant, log poll, `Safe`, and two mutation demonstrations); deferred 1 (the kept-offset location, for Story 12.2); the rest rejected with reasons in the triage log. Patched by verdict: medium 2, low 4, so the follow-up recommendation is true.

**Verification.** `test-mock.sh` 117 of 117; `test-lib-live.sh` all checks; warm `TelegramSwitch`, `TelegramMock`, `Contract.Mock`, `Install.Production`, `Install.Registry`, `Web.PairingApi`, `Web.Api` passed; fresh `shard lane-a@Channel` forward and reverse passed; `shard lane-b@Contract` passed; `live production-restart`, `live production` and `live compose-start` passed; `test-ci-config.sh`, `test-ci-changes.sh`, `test-readme.sh`, `ci/changes.sh` and `ci/checks.sh` passed; the Lane B files are untouched. Fifteen-plus pinning mutations were demonstrated red and reverted byte for byte (listed in `## Verification`).

**Residual risks.** The log-redaction assertions of `TestCallsAndLog` have no mutation of their own (the redaction is Lane B's mock code, which this story does not change). `TestPollerCheck` needs a running production in the stack and fails with an explicit message otherwise. The Lane B mock ask and the one-client residual of DW-370 stand as in the Design Notes. The kept-offset location is proven only when Story 12.2 builds `TelegramIn`.
