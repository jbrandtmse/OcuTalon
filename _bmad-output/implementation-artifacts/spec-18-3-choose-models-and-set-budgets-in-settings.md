---
title: 'Story 18.3: Choose models and set budgets in Settings'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: '2537a6cc2c14e227afccccb9b6506ce9211f8f9c'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-18-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A model test request leaves a Decision row and a Usage row with ItemId test.<ref>, and nothing outside Bridge.Settings is shown to filter such rows from the Recent decisions list, the usage totals, the daily cap or the digest cost line.
    evidence: |-
      Bridge.Settings.TestRequest (Lane A, Story 17.4) makes the request; the Decision and Usage rows are Decide's. No view or aggregate was read in this story, so whether they skip or count the rows is unverified. If they count them, a Test press adds a priced row to the day's cost and to the decision lists.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Settings.cls (TestRequest), Decide, the Recent decisions and cost readers
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** The Settings page still shows "This part of OcuTalon isn't built yet." for Models and Budgets. `POST /v1/settings/models` answers 501, nothing sends the model Test, the price and second-model APIs have no caller, the local cost-cap banner has no "Budgets" action, the no-model-key banner keeps the step 1 text, and the catalog's `fallbackReason.timeout` / `.rateLimited` texts are inexact (DW-100).

**Approach:** Lane A built every bridge API (Stories 17.3, 17.4) and the Budgets save (`SettingsOps` `budgets` section). This story adds what is missing and calls those APIs as built:
- a `models` save kind in `SettingsOps` (CheckModel, SetPrice, SetModel);
- a `TestModel` verb that `SettingsOps` sends to `Decide` synchronously, plus its route;
- the Models and Budgets sections, on one shared refusal helper (DW-948);
- the banner changes, the accepted DW-100 wording, and the README provider text.

## Boundaries & Constraints

**Always:**
- Every save is one `SaveSettings` (origin `web_admin`) to `SettingsOps`, and every Test is one `TestModel` (origin `web_admin`). Both routes sit under `/v1/settings/`, so `IsSettingsUrl` gates them (admin only).
- Bridge values change only through `OcuTalon.Bridge.Settings` (`CheckModel`, `SetModel`, `SetPrice`, `TestRequest`, `TestAnswer`, `Check`/`Set`), called as built. Prices are read from `OcuTalon.Bridge.Data.Price` (AD-33: the other lane reads).
- The `models` save keeps AD-19's order: validate the shape; run every `CheckModel` before any write; write prices inside one transaction (a `SetPrice` refusal rolls back and writes no audit entry); then run each `SetModel` with its `Settings` audit entry. A later failure puts back what was written (`SetModel`/`SetPrice` with `old`) and audits each put-back. A refused value changes nothing and writes no audit entry. Values that are unchanged are dropped.
- No key value ever reaches the page, an API answer, an audit entry or a log (NFR-11). The page shows only key variable *names*.
- The page lists only providers marked `supported`. A supported provider whose key is not set stays focusable with `aria-disabled`. Its reason, "No key set. Add {variable} to .env.", is linked by `aria-describedby` (UX-DR133). That provider's models can't be chosen.
- New user-facing strings ship only as ruled (PUBLIC TEXT below). Fixed-string tests pin each one.
- Tests restore every value they change: models, second models, prices, budgets, Config Store entries, rows and key variables. Production tests run on a lane-D throwaway.

**Never:**
- Edit Lane A files (U-177): `src/bridge/**` and the Lane A test areas. The one exception is the `Test/Watch/NoticeText.cls:270` literal, which the U-177 grant (ruled 2026-11-08, Design Notes) allows.
- Edit `Channel/WebChat/Out.cls`, `web/src/app/chat/**` (importing `fallbackReasonText` is fine) or `web/e2e/chat/notice.spec.ts`. Edit nothing in `Core/CommandsIn.cls`, `Web/Api.cls` or `Test/Web/{Api,BodyLimit}.cls` beyond the named additions.
- Show or accept a key on the page. List an unsupported provider on the page or in the README. Add a key variable to `.env.example`.
- Re-implement a bridge check. Use `Ens.Director.UpdateProduction`. Restart the production.
- Edit `ARCHITECTURE-SPINE.md`, `EXPERIENCE.md`, `release/**` or `eval/run.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| GET body | admin opens Settings | `SettingsOps.Values()` adds `prices: {model: {input, output, cacheRead, cacheWrite}}`, one entry per model of each `supported` provider that has a Price row. `bridge.agents` and `providers` are as built. No key value | -- |
| Model change | `agents.TriageAgent` = anthropic / claude-sonnet-5-5, key set | `CheckModel` passes, then `SetModel(..,0,.old)`. One audit entry: `TriageAgent.model`, `anthropic/claude-haiku-5-5` to `anthropic/claude-sonnet-5-5`. 200 `done` | -- |
| Second model | `secondProvider`/`secondModel` set, or both "" (clear) | `SetModel(..,1)`. Audit `TriageAgent.secondModel` ("" when none) | -- |
| Model refused | provider keyless or unsupported, or a model not listed | 400 `bad_settings` with fields `["TriageAgent"]` (`"TriageAgent.second"` for a second model). Nothing set, no audit | -- |
| Price change | `prices.claude-haiku-5-5.input` = "1.25" | `SetPrice` with the changed keys only. Audit `price.claude-haiku-5-5.input` | -- |
| Price refused | the second of two models' prices is refused | the transaction rolls back: the first model keeps its price. 400 fields `["prices.<model>"]`. No audit, no `SetModel` | -- |
| Bad models body | an agent or model missing or extra, a non-string or non-number, `@{` | 400 `bad_settings`, the offending names. Nothing written | -- |
| Set fails late | `SetModel` fails after a price was written | the price and earlier models are put back, each put-back is audited. 500 | logged |
| Test answered | `POST /v1/settings/models/test {"agent":"TriageAgent"}`, mock answers | 200 `{"answered":true,"seconds":n,"reason":""}`. Page: "Answered in {seconds} s" (one decimal), with the busy pattern while waiting | -- |
| Test fallback | no key (a fresh throwaway) | 200 `{"answered":false,"reason":"no_key"}`. Page: "Didn't answer: no model key is set" | -- |
| Test wait cap | Decide has not answered within `TESTWAIT` (45 s) | `SettingsOps` answers `answered:false, reason:"timeout"` itself (`TestAnswer` would say `error`) | -- |
| Test bad body | not `{"agent": string}`, or an agent that `TestRequest` refuses | 400 `bad_settings` `["agent"]` | non-admin: 403 `not_admin` |
| Budgets | save DecisionTokenBudget / DailyCostCapUSD | as built (`budgets` section): 200, applied, audited. Refused: 400 field error | -- |
| Cost-cap banner | local `dailyCap` condition | for an admin, the "Budgets" action opens `#/settings/budgets` in the same tab. A non-admin gets no action | -- |
| No-key banner | `noModelKey` condition | step 2 text, with "How to set a key" | -- |
| DW-100 | a `timeout` / `rate_limited` fallback anywhere | the accepted wording: no fixed seconds, no "retries ran out" | -- |
| DW-948 | a refused or failed save in any section | one shared helper classifies it: 403 denied; 400 with named known fields; otherwise a form error | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Settings.cls` (read only): class doc :1-40 is the contract. `Providers` :75, `Values` :95 (`agents`), `CheckModel` :218, `SetModel` :256 (`old` = {provider, model[, retryItem]}), `SetPrice` :310 (keys :364; no check-only form), `TestRequest` :372, `TestAnswer` :405.
- `src/bridge/cls/OcuTalon/Bridge/Providers.cls` (read only): Table :22 (only `anthropic` is supported), `KeySet` :79 (reads this process's environment).
- `src/bridge/cls/OcuTalon/Bridge/Data/Price.cls` (read only): `ModelIndexOpen`, the seven price properties.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - `OnMessage`/`Carry` :120-147 (dispatch by class).
  - XData Sections :779 (add `{"slug":"models","kind":"models","fields":[]}`).
  - `Values` :825 (skip kind `models`; add `prices`).
  - `Save` :851 (route kind `models` before the field loop).
  - Siblings to extend: `SaveBridge` :977, `PutBack` :1027, `Refused` :882, `AuditData` :179.
  - Seams `BridgeCheck`/`BridgeSet` :1057-1066: add `BridgeCheckModel`, `BridgeSetModel`, `BridgeSetPrice` and `BridgeTest` the same way.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`: XData Routes :187-210, SaveSettings row :201. `TIMEOUT` 120 :41.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSettings.cls`: the pattern for the new `TestModel.cls`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: UrlMap :188 (`/v1/settings/models` -> `NotBuilt`), `SaveSection` :781, `Answer` :818, `BadSettings`, `NotBuilt` :865. `SendDigest` :1486 is the sibling of the test route.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: `fallbackReason.timeout` :181, `.rateLimited` :206, `banner.noModelKey` :295, `bannerAction.budgets` :352 (exists).
- `web/scripts/catalog.mjs` `LISTED_KEYS` :61-82 (add `bannerAction.budgets`). Then `npm --prefix web run catalog` regenerates `web/src/app/msg/catalog.ts`.
- `web/src/app/banners/banner-view.ts`: `BANNERS` costCap :76, `ActionTarget` :49, `BannerAction` :131, `hrefOf` :189, view :219.
- `web/src/app/banners/banner-stack.ts`: `FORMAT` :25, the action template (`target=_blank`). The admin flag is `live.snapshot()?.admin` (as `header-nav.ts:65`).
- `web/src/app/settings/`:
  - `settings-page.ts`: the `@switch` :59-90 (`@default` = not built), `keep*` updaters :272.
  - `settings-view.ts`: `SETTINGS_TEXTS`, the pure rules.
  - The section siblings: `check-thresholds-section.ts` (form pattern) and `time-zone-section.ts` (bridge section, select).
  - The refusal block, repeated in `check-thresholds` :218, `time-zone` :217, `daily-digest` :280/:309 and `demo-mode` :229 (403 only).
- `web/src/app/chat/decision-strip.ts:22` `fallbackReasonText(reason)`: import it, don't edit.
- `web/src/app/api/api-client.ts` :56 `saveSettings`, :64 `sendDigest`. `api-types.ts` :168 `SettingsBody` (`providers: unknown[]`).
- `README.md` :211-220 "Set a model key". `docker/tests/test-readme.sh` `KEY_FACTS` :739, `FIXED_SENTENCE` :206, and the public-text rule :907 (no provider other than Anthropic may be named).
- Tests that hold the old texts (DW-100 and the banner):
  - `Test/Msg/Catalog.cls` :1291-1337, :1431, :1468.
  - `Test/Core/ConversationTurns.cls` :932.
  - `Test/Watch/NoticeText.cls` :270 (Lane A).
  - `Test/Digest/Compose.cls` :524 (Lane A: a prefix check that the proposed wording keeps).
  - `web/scripts/{catalog,heartbeat-card-view,incident-view,decision-view,banner-view,ux-strings}.test.mjs`.
  - `web/e2e/{heartbeat-card.spec.ts,chat/chat.spec.ts,chat/decision.spec.ts,answers/close-loop.spec.ts,banners/banners.spec.ts}`.
- Other test pins:
  - `Test/Web/Api.cls` :953 `TestRoutes`; `Test/Web/BodyLimit.cls` :14 `POSTROUTES`.
  - `Test/Web/SettingsApi.cls` `TestNonAdminIs403Everywhere` :94, `TestGetShape` :137, `TestBridgeRoutesAre501` :332 (its 501 now covers channels only).
  - `Test/Core/SettingsSave.cls` `TestValues` :414.
  - `Test/Core/SettingsCommands.cls` :38 (the verb list).
  - `web/catalog.test.mjs:146` (Budgets not listed yet).
  - `web/e2e/settings/settings.spec.ts` S1 :81-95 (expects Models and Budgets to be not built).
- Lane A patterns to follow (read only):
  - `Test/Bridge/ModelChange.cls` (header :1-28: key variable set in-process, `PointKeys` after `SetModel`, the restore order).
  - `Test/Bridge/SettingsApply.cls` `TestModelTestEachAgent` :325.
  - `Test/Agent/RunnerFixture.cls` `PointKeys` :515, `Run` :437, `ReadyReason` :365.
  - `Test/Agent/KeyScan.cls` `SetEnv`/`HasEnv`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Msg/Command/TestModel.cls` (new) -- `Property Agent As %String(MAXLEN = 32)`. The doc names the contract.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- add ONE Routes row, `{"verb": "TestModel", "owner": "SettingsOps", "origins": "web_admin"}`, right after the SaveSettings row. Add one doc clause. This is a contended append (Epic 41 appends at the end of the list).
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - the `models` section kind and `SaveModels`, as in Boundaries and the Matrix;
  - `Values().prices`;
  - `TestModel`: `TestRequest`, then `SendRequestSync("Decide", request, .response, ..#TESTWAIT)`, timed with `$ZH`, then `TestAnswer`. Answer Ok 1, outcome `tested`, with Data `{answered, seconds, reason}`. An expired wait gives reason `timeout`. A refused agent gives outcome `refused` with Data `{"fields":["agent"]}`;
  - the four new seams;
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - route `/v1/settings/models` -> `SaveModels` (calls `SaveSection("models")`);
  - add `POST /v1/settings/models/test` -> `TestModel`, right after the models route;
  - put the handlers after `NotBuilt`, not at the end of the class (Epic 41 appends there);
  - `TestModel` takes exactly the body `{"agent": string}`. It answers 200 with Data's three members, 400 `bad_settings` for a bad body or a refused agent, and 500 otherwise.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- the step 2 `banner.noModelKey` text. The DW-100 texts ship only as ruled. Then run `npm --prefix web run catalog`.
- `web/scripts/catalog.mjs` -- list `bannerAction.budgets`.
- `web/src/app/banners/banner-view.ts`, `banner-stack.ts` -- an action target `budgets` that is admin-only (the `admin` input, `#/settings/budgets`). It opens in the same tab: no `target=_blank`, no external-link icon, no new-tab words.
- `web/src/app/settings/refusal.ts` (new) + `settings-view.ts` `refusalKind(status, fields, known)` (pure) -- (DW-948) the one classifier. Move `check-thresholds`, `time-zone`, `daily-digest` (save and send) and `demo-mode` (403) onto it. The sections keep only their own focus and announce lines.
- `web/src/app/settings/models-section.ts` (new):
  - one group per agent (legend "Triage agent", "Diagnosis agent" or "Chat agent") with a Provider radio group, a Model select, a Second model select ("None" plus the models of every supported provider with a key), a Test `<app-server-button>` and its result line;
  - a Prices group per listed model, with Input, Output, Cache read and Cache write;
  - one **Save changes**, using the section pattern (saved and failed texts, field errors mapped from `TriageAgent`, `TriageAgent.second` and `prices.<model>`, dirty state, denied).
  - Pure rules in `settings-view.ts`: `modelsView`, `modelsBody`, `isModelsDirty`, `testResultText` (the reason text comes from `fallbackReasonText`).
- `web/src/app/settings/budgets-section.ts` (new) -- two text fields and their help text, saving `{DecisionTokenBudget, DailyCostCapUSD}` through `saveSettings('budgets', ...)`, using the section pattern.
- `web/src/app/settings/settings-page.ts`, `settings-view.ts` -- add the `@case` for `models` and `budgets` and the `keepModels`/`keepBudgets` updaters. Remove the not-built branch and `notBuilt`, since every section is built now. Add the new texts to `SETTINGS_TEXTS`.
- `web/src/app/api/api-client.ts`, `api-types.ts` -- `testModel(agent)` and the types `ModelsBody`, `ModelTestAnswer`, `ProviderRow`, `AgentModels` and `Prices`.
- `README.md` -- "Set a model key": the provider paragraph of the ruled PUBLIC TEXT, keeping `FIXED_SENTENCE` and steps 1-4. `docker/tests/test-readme.sh` -- add the new facts to `KEY_FACTS`.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` -- the four doubles, recording calls as `BridgeSet` does.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsModels.cls` (new; in-process probe, like `SettingsSave`) -- every Matrix row from "Model change" to "Set fails late". It checks that the order is every `CheckModel`, then the prices, then `SetModel`, and that unchanged values are skipped.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsModelsLive.cls` (new; extends `Test.Core.InProduction`; throwaway and CI only) -- AC 3 and AC 2 against the real bridge and production:
  - AC 3 drives a `SettingsOpsProbe` whose doubles pass through to the real `Bridge.Settings`, in the test's process. `CheckModel` reads the key variable in its own process, and a throwaway's jobs have none (see the `ModelChange` header).
  - `TestModelAnswers` goes through `Commands.Submit` to the real `SettingsOps` job, after `PointKeys`.
  - The restore follows `ModelChange`'s order. Copying its teardown is allowed because the class is Lane A's (Rule 2, stated reason).
- `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` -- `TestModelTestRoute` (Test fallback and bad body; a non-admin gets 403). Add both routes to `TestNonAdminIs403Everywhere` and the prices to `TestGetShape`. `TestBridgeRoutesAre501`: only channels stays 501.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsSave.cls` `TestValues` (prices); `Test/Core/SettingsCommands.cls` (TestModel from `tool` and `web_user` is refused); `Test/Web/Api.cls` `TestRoutes` (27 routes); `Test/Web/BodyLimit.cls` `POSTROUTES` (append `/v1/settings/models/test`).
- The old-text tests in the Code Map -- update them to the ruled text. The Lane A literal changes only under the grant.
- `web/scripts/settings-view.test.mjs`, `banner-view.test.mjs`, `catalog.test.mjs`, `ux-strings.test.mjs` -- the pure rules (including `refusalKind`), the admin-only Budgets action, the listed key, and a source for every new string.
- `web/e2e/settings/settings.spec.ts`:
  - S1: no section shows the not-built text.
  - S13 (Models): a supported provider without a key on a CI stack is `aria-disabled` and described by "No key set. Add ANTHROPIC_API_KEY to .env.", and the page holds no key-shaped text. A real Test shows "Didn't answer: no model key is set". A stubbed 200 with `seconds` 1.2 shows "Answered in 1.2 s". A price save shows the saved text, the GET returns it, and the price is put back.
  - S14 (Budgets): save, GET, put back, and a refused value shows the field error.
  - Use `getByRole` with exact names, scoped to each agent's group.
- `web/e2e/banners/banners.spec.ts` -- the step 2 no-key text. Budgets shows for an admin and goes to `#/settings/budgets`; a non-admin gets no action.

- Task 0 (lead, spec gate; product default 5, measure): before fixing `TESTWAIT`, read the lane-D throwaway's CSP/Web Gateway server response timeout (the gateway's configuration in the container; `iris_execute_command` or the gateway's config file) and record the measured value with its source in this spec's Design Notes. If it is under 55 s, set `TESTWAIT` at least 10 s below it and say so; if it cannot be read, keep 45 s and label it (inference) in the Design Notes and in the Test's code comment-free contract.

**Acceptance Criteria:**
- **AC 1.** Given an admin opens Models, when the page loads, then each of the three agents shows its provider and model. Only supported providers are listed. A provider without a key is `aria-disabled` and described by "No key set. Add {variable} to .env.", and its models can't be chosen. No key value is in the page or the GET body. Pinned by S13 and `TestGetShape`.
- **AC 2.** Given an admin presses **Test** for an agent, when the route answers, then the button followed the busy pattern, and the line reads "Answered in {seconds} s" or "Didn't answer: {plain reason}". The route answer comes from `TestRequest`/`TestAnswer` through `SettingsOps` and `Decide`. Pinned by `SettingsModelsLive` `TestModelAnswers` (PointKeys and the mock: answered, seconds > 0), `SettingsApi` `TestModelTestRoute`, and S13.
- **AC 3 (Integration, Rule 1).** Given `SettingsOps` saves TriageAgent's model, a second model and a price (consumer `SettingsOps` on the real `Bridge.Settings`, with the key variable set in the test's process as `ModelChange` does), when the next decide runs after `PointKeys`, then:
  - `Bridge.Settings.Values()` and `Values().prices` show the new values;
  - the decide's Decision row has the new model;
  - one `Settings` audit entry per change is read back from the IRIS audit log;
  - everything is put back afterwards.
- **AC 4.** Given the Budgets section, when an admin saves the token budget or the cap, then the page shows the saved text, the values apply to the next decision, and they are audited. The server half is already met (Design Notes). The page is pinned by S14. For an admin, the cost-cap banner's "Budgets" opens this section (`banner-view.test.mjs` and `banners.spec.ts`).
- **AC 5.** Given no model key, when the banner shows, then it reads "OcuTalon has no model key, so every decision uses fixed rules. Add a key for a supported provider (for example, ANTHROPIC_API_KEY) to the .env file and restart OcuTalon." with "How to set a key". Pinned by `Test.Msg.Catalog`, `catalog.test.mjs` and `banners.spec.ts`.
- **AC 6 (DW-100).** Given the accepted wording, when any timeout or rate-limit fallback is rendered, then the timeout text names no number of seconds and the rate-limit text does not say retries ran out. Every test that pinned the old text pins the new one.
- **AC 7.** Given the README, when this story merges, then "Set a model key" names Anthropic as the supported provider and says the key comes from its own variable, listed in `.env.example` without a value and never from the settings page. It names no other provider and does NOT carry the default-model sentence for another provider's key (dropped by the Planner's ruling, planner-2026-11-08-18.3). Pinned by `test-readme.sh`.

## Spec Change Log
- 2026-11-08, rulings (Contest Planner under the owner's delegation, relayed by the orchestrator, key planner-2026-11-08-18.3): PUBLIC TEXT rows 1-21 approved as written (1-6 verbatim); row 22 approved without its last sentence; U-177 grant for `Test/Watch/NoticeText.cls:270` only; EXPERIENCE.md :170, :784, :789 amended by the lead to rows 20 and 21 with marker `[AMENDED 2026-11-08, Story 18.3, DW-100, Contest Planner ruling]`; spine REST row :1510 rewritten and the models/test row added by the LEAD at story close (not a stage edit); AD-19's nested-body note waits for an attended Update.
- 2026-11-08, spec gate (lead, Epic 18 runner): added Task 0 (measure the gateway response timeout behind `TESTWAIT`, product default 5); applied the AMENDMENT NOTE to epics.md (Budgets AC: `Bridge.Settings.Set`, not `Ens.Director.UpdateProduction`; tier 1, reported). PUBLIC TEXT, the U-177 grant for `Test/Watch/NoticeText.cls:270` and the SPINE/UX notes went to the orchestrator; no implement before the ruling.

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 33 findings - high 0, medium 8, low 21, false 3, maybe-false 1 (nine rows repeat an earlier row and share its route; the four rows of the intent-alignment layer are its descriptive divergences)
- findings:
  - `[low]` `[reject]` Blind 1, SettingsOps (PoolSize 1) is held up to 45 s by a Test, so a save queued behind it waits - the spec's contract is that SettingsOps sends the request to Decide synchronously; a Test answers in seconds on a mock or a key, and the button follows the shared busy pattern; a separate item or pool is a Production.cls change outside the story.
  - `[low]` `[patch]` Blind 2, the 45 s wait is shorter than the bridge's timer and the request is not cancelled, and the class comment said the test "writes and audits nothing" - the comment is corrected in `Core/SettingsOps.cls` and `Msg/Command/TestModel.cls` (no setting, no audit entry; the Decision and Usage rows are Decide's). A late Decide row after an expired wait is Lane A's design (17.4).
  - `[maybe-false]` `[defer]` Blind 3, Test rows (ItemId test.<ref>) may show in Recent decisions, the usage totals, the cap or the digest cost - needs a read of those views, which are Lane A's; recorded in `deferred:` as medium (unverified).
  - `[medium]` `[patch]` Blind 4, the real BridgeTest has no test for the expired wait, the refused agent or the failed send - added `Test.Core.SettingsOpsNoReply` and `SettingsModels` `TestRealModelTestWait`; the mutation (the expired-wait override removed) turns it red.
  - `[low]` `[reject]` Blind 5, a save is refused when a Price row appears or disappears between page load and save - the form error says nothing was changed and a reload shows the rows; a Price row changes only by a code change.
  - `[low]` `[patch]` Blind 6, the Test line stays beside a model that a save changed - `models-section.ts` clears the line of each agent whose provider or model changed (pinned by S13c, not observed locally).
  - `[low]` `[reject]` Blind 7, `keepBudgets` keeps the typed text - the same pattern as the other sections' keep updaters (they keep what was sent), and the server canonicalises on the next load.
  - `[false]` `[reject]` Blind 8, the live specs change shared settings and could affect parallel specs - `web/playwright.config.ts` has `fullyParallel: false` and `workers: 1`, and each case restores its values in `finally`.
  - `[low]` `[reject]` Blind 9, stale text in the `Web/Api.cls` class comment, `chat/decision-strip.ts:21` and the UX mockup `states.html` - the first is a contended file, the second is on the story's do-not-edit list and the third is the UX owner's; none is shown to a user.
  - `[low]` `[patch]` Blind 10, TestModel is missing from the message contract tables - added to `Test.Msg.Contracts`; `Test.Contract.Ac` is the epics-AC table and lists no later verb.
  - `[medium]` `[reject]` Edge 1, a stale Models form sends every field and can revert another admin's change - the sibling sections send all their fields the same way and the server drops what is unchanged against the current value; two admins on one instance saving within one page load is not a path the stories cover (wontfix-theoretical).
  - `[low]` `[reject]` Edge 2, ServerButton restores the Test button after 10 s while a Test can run 45 s - the shared busy pattern is what AC 2 names, it shows its notice, and ServerButton has no timeout input (adding one is a shared-component change).
  - `[low]` `[reject]` Edge 3, the single SettingsOps job blocks saves during a Test - same as Blind 1.
  - `[low]` `[patch]` Edge 4, the Test line is stale after the model changes - same as Blind 6.
  - `[false]` `[reject]` Edge 5, an OK answer with no body is reported as a timeout - Ens.Host's SendRequestSync leaves the status OK and the response empty exactly when the wait expires, and Decide always answers with a Result.
  - `[low]` `[reject]` Edge 6, prices written in an open transaction can be read before a rollback - the spec's decision 3 (SetPrice inside a transaction is the check, as SaveProduct does); the window is the length of two writes.
  - `[low]` `[reject]` Edge 7, a put-back can be refused when the old provider's key is gone - a key variable is read at process start, so it cannot disappear within one save (wontfix-theoretical).
  - `[low]` `[reject]` Edge 8, `keepBudgets` keeps the typed text - same as Blind 7.
  - `[low]` `[reject]` Edge 9, the `decision-strip.ts` comment is stale - same as Blind 9.
  - `[low]` `[reject]` Edge 10, the busy pattern is not single-flight for 45 s - same as Edge 2.
  - `[medium]` `[patch]` Gap 1, the real BridgeTest's expired-wait branch is covered by no test - same as Blind 4.
  - `[medium]` `[patch]` Gap 2, the page's model, second-model and provider choices and the agent field errors have no pinning test - added e2e S13c (stubbed GET with a key, stubbed POST): the posted body, the cleared Test line and the two field errors; not observed locally (DW-938 pattern).
  - `[medium]` `[patch]` Gap 3, the new page modules have no executed test host and some pins carry no mutation - the DW-948 adoption and the banner stack's admin wiring are now pinned by `settings-refusal-sources.test.mjs` and the `prices` mutation was observed (both recorded in Verification); the Playwright cases keep "not observed locally".
  - `[medium]` `[patch]` Gap 4, S13's keyless branches could run no check on a stack with a key, and the SettingsApi guard reads the test process - S13 now asserts the control that a CI stack holds no key and checks unconditionally (`lib-live.sh` keeps the decoy key out of the container); the SettingsApi guard stays, since it only skips when the process holds a key.
  - `[medium]` `[patch]` Gap 5, "the answer holds no key" in `TestModelTestAnswers` cannot fail - replaced by the assertion that the answer has exactly its three members.
  - `[medium]` `[patch]` Gap 6, the Decision assertion in `TestModelTestAnswers` is not scoped to the test's row - it now reads rows above the highest ID before the Submit.
  - `[low]` `[reject]` Gap other 1, the `Web.Api.TestModel` 500 branches are reached by no test - they answer only for an error status or a missing result from a SettingsOps that is up; the route's 200, 400 and 403 are pinned.
  - `[low]` `[reject]` Gap other 2, `decision-strip.ts:21` still quotes the old text in a comment - same as Blind 9.
  - `[low]` `[reject]` Gap other 3, `SettingsModels` expects the Price rows of exactly two models - the failure is loud, and the models are the supported provider's table.
  - `[low]` `[reject]` Intent 1, the tests drive SettingsOps through a probe or through the bridge rather than through REST - the spec names that shape (`SettingsModels` in-process, `SettingsModelsLive` on the real bridge, `SettingsApi` for the routes).
  - `[low]` `[reject]` Intent 2, B3b gets the admin state by rewriting the snapshot - the live fixture user holds OcuTalonUser only; the admin flag is the snapshot's (AD-12) and `banner-view.test.mjs` pins the rule.
  - `[low]` `[reject]` Intent 3, the demo-mode section and the digest send use refusalOf for the 403 only - the spec says "demo-mode (403 only)"; their other answers keep their own text.
  - `[false]` `[reject]` Intent 4, the `banner.noModelKey` source annotation still says "step 1" - it names the EXPERIENCE heading of the row, which is unchanged.

## Design Notes

**Architecture decisions (Rule 6):**
- AD-1: the `TestModel` verb goes through `CommandsIn`.
- AD-2: OcuTalon calls the bridge, never the reverse.
- AD-4: the session Ref.
- AD-7: three agents, configured by settings.
- AD-8: a model test is never retried; the timer stays at or under 110 s.
- AD-12: the page decides nothing; the snapshot's `admin` flag.
- AD-13: the admin gate.
- AD-17: one audit writer.
- AD-19: keys come from the environment; `SettingsOps` is the one writer, with the save order; the bridge settings APIs.
- AD-20: budgets and prices.
- AD-29 and AD-33: lanes (U-177), and Lane B reading `Data.Price`.
- AD-32: the catalog texts.

**Already met (evidence, not rebuilt):**
- The Budgets save:
  - XData `budgets` (`SettingsOps.cls:782`);
  - `Test.Web.SettingsApi` `TestBridgeRoutesAre501` (budgets part);
  - Lane A's `Test.Bridge.SettingsApply` `TestIntegrationSettingsOps` and `TestBudgetNextDecision`.
- The cap is off by default on a local install: `Install/Step/Public.cls:81` seeds 0; `Test.Install.Public`.
- The model change merges the entry and restarts the runner, and applies to the next request: `Test.Bridge.ModelChange` `TestSetModelNextRequest`, `TestSecondModel`.
- `.env.example` already lists `ANTHROPIC_API_KEY` with no value. It is the only supported provider's variable.

**Decided in-stage:**
1. The Test is a new verb, not a `SaveSettings` slug: a test is not a save, and AD-1 sends it through a business service.
2. The models body is nested: `{"agents": {<Agent>: {provider, model, secondProvider, secondModel}}, "prices": {<model>: {input, output, cacheRead, cacheWrite}}}`. Model names hold dots, so flat field names would be ambiguous. Refusal field names: `<Agent>`, `<Agent>.second`, `prices.<model>`.
3. Prices have no check-only API, so `SetPrice` inside a transaction serves as the check. A refusal rolls back, the `SaveProduct` precedent.
4. The page edits four prices (input, output, cacheRead, cacheWrite). The long tier keeps its values, because `SetPrice` keeps keys that are left out.
5. Model names show as their ids (values, like zone names). Provider names: `anthropic` -> "Anthropic"; any other id shows as itself, and today no other provider is listed.
6. The Test checks the agent's *saved* first model (`TestRequest`), and the help line says so.
7. `TESTWAIT` is 45 s. Task 0 measured the lane-D warm throwaway (tag `e18s3iw`): the Web Gateway configuration `/usr/irissys/csp/bin/CSP.ini` in the `iris` container, and its durable copy `/durable/iris/csp/bin/CSP.ini`, both hold `Server_Response_Timeout=60` and `Queued_Request_Timeout=60` in `[SYSTEM]`. 60 s is not under 55 s, so 45 s stays: it is 15 s below the gateway's response timeout and inside `CommandsIn`'s 120 s. An expired wait reports `timeout`.
8. The page formats `seconds` with one decimal.
9. The not-built branch and its text are removed, since no section is unbuilt.
10. An expired `SendRequestSync` wait gives status OK and no response (`Ens.Host` `queueRequestSync`), so `BridgeTest` reads "OK and no response object" as the wait expiring and sets `reason` `timeout`; `TestAnswer` alone would say `error`.
11. `BridgeCurrent` also answers `<Agent>.provider`, `.model`, `.secondProvider` and `.secondModel` (from `Bridge.Settings.Values().agents`) and `price.<model>.<key>` (from the Price row), so the four new seams are the four the spec names and no fifth seam reads the current values.
12. The put-back of a model uses the provider and model that `Values()` showed before the save (the same pair the audit entry names as `from`), not the provider of `SetModel`'s `old`: `old.provider` is the Config Store entry's provider, which can be empty where `Values()` derives it from the model. An empty pair puts back a second model with the clear form (`SetModel(agent, "", "", 1)`).
13. The `models` body must hold exactly the three agents and exactly the models that `Values().prices` lists (`PriceModels`), each with exactly its members, as the Matrix says ("missing or extra"). Prices are compared as numbers, a value that is not a valid number counts as a change so that `SetPrice` refuses it inside the transaction, and the audit entries of the prices are written after the transaction commits (an audit entry cannot be rolled back, and a refusal must leave none). A failed audit entry puts back the prices and models written so far.
14. The Test button tests the saved first model, so the page does not send unsaved choices with it. `Test.Core.SettingsModelsLive` runs the real Test through `Commands.Submit` for TriageAgent only: the default mock scripts of the diagnosis and chat agents take a tool call first, and the fixed test input cannot carry a mock marker.
15. A provider without a key keeps its radio focusable with `aria-disabled` and a click on it is ignored; the options of the Model select of such a provider are `disabled`, and the saved second model stays in the Second model list, not choosable, when its provider has no key.
16. The README keeps its first two sentences, then the ruled paragraph, then "To give it a key:" and steps 1 to 4: the ruled paragraph sits after the first sentences and before the steps, since "To give it a key:" must lead into the steps. The dropped sentence appears nowhere.
17. `web/scripts/announce-focus-sources.test.mjs` (footprint extension, no open branch changes it): its lists of announcing files, files that call `.focus(` and files that wait for a render now name the two new sections, which announce their saved and failed texts and focus their first field in error like the four existing ones.
18. The banner view takes an `admin` input (the snapshot's `admin` flag, set in `banner-stack.ts`), and `BannerAction` has `sameTab` for the Budgets action; the cost-cap row carries the action with `adminAction: true`.

**Ledger (Rule 17):**
- DW-100: addressed by AC 6, once the text is accepted. The proposed wording keeps `Test.Digest.Compose:524`'s prefix ("the model didn't answer within"), so only one Lane A literal changes.
- DW-948 (reopened by this story's design): addressed by `refusal.ts`/`refusalKind`. Models and Budgets use it, and the four existing sections move onto it. No fifth copy.

**U-177 GRANT NEEDED (lead, with the PUBLIC TEXT list, before implement):** `src/ocutalon/cls/OcuTalon/Test/Watch/NoticeText.cls:270` (Lane A) pins `"the model didn't answer within 60 seconds"` in `TestFallback`. AC 6 needs that one literal changed to the ruled text. Without the grant, the DW-100 rows of AC 6 cannot ship, and the rest of the story is unaffected. If the ruling changes the timeout prefix, `Test/Digest/Compose.cls:524` needs the same grant.

**AMENDMENT NOTE (Rule 5, apply-and-report, lead):** epics.md's Budgets AC says "through `Ens.Director.UpdateProduction`". As built, the values are System Default Settings rows that `Bridge.Settings.Set` writes, and `Decide` reads them on each decision with no `UpdateProduction`. The AC cites the wrong API; the intent (applies within a minute, no restart) is met.

**SPINE NOTE (lead):**
- The REST surface row at :1510 still says models answers 501. Add a row for `POST /api/v1/settings/models/test` (TestModel).
- AD-19's "Changes as a JSON object of field to value" now has the `models` kind's nested values.
- EXPERIENCE.md :170, :784 and :789 hold the old fallback wording. Amend them with the ruling.

**Access:** unchanged. Both new routes sit under `/v1/settings/`, so `IsSettingsUrl` gates them, `OcuTalonAdmin` by whole name. `TestModel` accepts `web_admin` only. No role, grant or origin is added for any other caller. There is no VETO ITEM.

**Secrets:** unchanged. Keys stay in environment variables, read only as present or absent (`Providers.KeySet`). The page and the API show variable names only, and `SetModel` writes `@{env:<var>}`.

**Footprint extensions (Rule 11 b):**
- `Msg/Command/TestModel.cls` (new) and `Core/SettingsOps.cls`'s `TestModel`;
- `web/scripts/{catalog.mjs,*.test.mjs}` as listed, and `web/src/app/msg/catalog.ts` (generated);
- `docker/tests/test-readme.sh`;
- `Test/Msg/Catalog.cls`, `Test/Core/ConversationTurns.cls`;
- the `web/e2e` specs named.

None of these is in an open branch's diff (checked 2026-11-08) except `ux-strings.test.mjs` (Epic 19b adds its own block; ours is a separate block).

**Contended files touched:** `Core/CommandsIn.cls` (one row), `Web/Api.cls` (the models route line, one route, and the handlers placed mid-class), `Test/Web/Api.cls` `TestRoutes`, and `Test/Web/BodyLimit.cls` `POSTROUTES` (append). All of these are also on Epic 41's branch and need a plain-union merge.

**Integration ACs and consumers:**
- **Consumes:**
  - `Bridge.Settings` `CheckModel`, `SetModel`, `SetPrice`, `TestRequest` and `TestAnswer` (Stories 17.3 and 17.4), and `Bridge.Data.Price`, exercised on the real instance by AC 3 and AC 2;
  - the `SettingsOps` save path (Story 33.2);
  - `fallbackReasonText` and `ServerButton`.
- **Consumed-by:**
  - Story 18.4's Playwright test (it covers the Settings page);
  - the later Settings sections (Tools and MCP servers, Roles), which use `refusal.ts`.

**PUBLIC TEXT (RULED 2026-11-08, ruling key planner-2026-11-08-18.3, the Contest Planner under the owner's delegation, relayed by the orchestrator: rows 1-21 approved exactly as written, 1-6 confirmed verbatim; row 22 approved WITHOUT its last sentence -- the README paragraph ends at "...and the page never shows one."):**

| # | String | Source | File |
|---|---|---|---|
| 1 | No key set. Add {variable} to .env. | AC 1, verbatim | `settings-view.ts` |
| 2 | Test | AC 2, verbatim | `settings-view.ts` |
| 3 | Answered in {seconds} s | AC 2 ("Answered in 1.2 s" is the fixture) | `settings-view.ts` |
| 4 | Didn't answer: {reason} | AC 2 | `settings-view.ts` |
| 5 | OcuTalon has no model key, so every decision uses fixed rules. Add a key for a supported provider (for example, ANTHROPIC_API_KEY) to the .env file and restart OcuTalon. | AC 5 / EXPERIENCE :924 | `Catalog/Core.cls` |
| 6 | How to set a key; Budgets | EXPERIENCE :924-925 (existing keys) | reused |
| 7 | Triage agent / Diagnosis agent / Chat agent | none -- proposed (FR-39 names the three) | `settings-view.ts` |
| 8 | Provider / Model / Second model / None | none -- proposed | `settings-view.ts` |
| 9 | Anthropic | none -- proposed (provider name) | `settings-view.ts` |
| 10 | A change applies from the agent's next model request. | none -- proposed (AC 3) | `settings-view.ts` |
| 11 | Used once when this agent's reply can't be used. | none -- proposed (second-model help) | `settings-view.ts` |
| 12 | Test sends one short request to the agent's saved model. | none -- proposed | `settings-view.ts` |
| 13 | Couldn't run the test. Try again. | none -- proposed (the route failed) | `settings-view.ts` |
| 14 | Prices / Input / Output / Cache read / Cache write | none -- proposed | `settings-view.ts` |
| 15 | US dollars per million tokens. New prices apply to later model requests; earlier costs stay as they were. | none -- proposed | `settings-view.ts` |
| 16 | Token budget per decision | AC 4's words | `settings-view.ts` |
| 17 | A decision that would use more tokens than this uses fixed rules instead. 0 is off. | none -- proposed | `settings-view.ts` |
| 18 | Daily cost cap (US dollars) | none -- proposed | `settings-view.ts` |
| 19 | When today's model cost reaches the cap, decisions use fixed rules until midnight in the instance's time zone. 0 is off. | none -- proposed | `settings-view.ts` |
| 20 | the model didn't answer within the time allowed | none -- proposed (DW-100; was "...within 60 seconds") | `Catalog/Core.cls` |
| 21 | the model was too busy to answer | none -- proposed (DW-100; was "...busy and retries ran out") | `Catalog/Core.cls` |
| 22 | README, after the first line of "Set a model key": "Anthropic is the supported model provider: in Settings, an admin can choose Claude Haiku 5.5 or Claude Sonnet 5.5 for each agent. Each supported provider's key comes from its own environment variable, which `.env.example` lists without a value; Anthropic's is `ANTHROPIC_API_KEY`. A key is never entered on the settings page, and the page never shows one." (RULED: the last sentence dropped) | AC 7 / FR-39 | `README.md` |


**PUBLIC TEXT ruling for the implement stage (binding):** write every string byte for byte and pin each with a fixed-string assertion (exact comparison, not a pattern); the README sentences kept go into `docker/tests/test-readme.sh`'s KEY_FACTS (or its equivalent fixed-string list) one by one; the dropped sentence must NOT appear anywhere. New strings EXPERIENCE.md does not hold go under `ruled` in `web/scripts/ux-strings.test.mjs`, keyed `'Story 18.3 ruling planner-2026-11-08-18.3 (the Contest Planner under the owner\'s delegation, 2026-11-08, relayed by the orchestrator: the Models and Budgets labels and help lines, the agent and provider names, the Test help and failure texts, and the price labels)'`; rows 20 and 21 now sit in EXPERIENCE.md (amended by the lead) and are sourced `ux`. No other new user-facing string may ship.

**U-177 GRANT (ruled):** exactly ONE Lane A literal may change: `src/ocutalon/cls/OcuTalon/Test/Watch/NoticeText.cls:270` (`TestFallback`), to row 20's text. No other Lane A file. If `Test/Digest/Compose.cls:524` or any other Lane A test turns out to need a change, HALT with an `intent gap` naming it.

These are reused unchanged: "Save changes", "Saved. Applies within a minute. Recorded in the audit log.", "Couldn't save. Nothing was changed.", the busy notice, and the section names Models and Budgets.

## Verification

Lane D variables (`$LANE_D` below):
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=18 stage=<stage>' OCUTALON_RUN_TAG=e18s3<stage letter>w`

Runtime: compile on slot D (`ocutalon-slot-d`, `OCUTALON`) with `iris_doc_load`. Production tests run on one lane-D warm throwaway (the CI mock; never a real key).

**Commands** (one per call, each about 150 s or less):
- `$LANE_D ci/warm.sh up` (setup) -- expected: the stack is ready.
- One `$LANE_D OCUTALON_WARM=1 ci/iris.sh class <C>` per call (loop), for `C` in:
  - `OcuTalon.Test.Core.SettingsModels`
  - `OcuTalon.Test.Core.SettingsModelsLive`
  - `OcuTalon.Test.Web.SettingsApi`
  - `OcuTalon.Test.Core.SettingsSave`
  - `OcuTalon.Test.Msg.Catalog`

  Expected: `CLASS ... passed`.
- The same command (once), for `C` in:
  - `OcuTalon.Test.Core.SettingsCommands`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Web.BodyLimit`
  - `OcuTalon.Test.Core.ConversationTurns`
  - `OcuTalon.Test.Core.SettingsAudit`
  - `OcuTalon.Test.Msg.Contracts`
  - `OcuTalon.Test.Bridge.ModelChange`
  - `OcuTalon.Test.Bridge.SettingsApply`
  - `OcuTalon.Test.Digest.Compose`
  - `OcuTalon.Test.Watch.NoticeText` (after the grant)

  Expected: passed. A class that can't finish in about 150 s is left to CI and named.
- `node --test web/scripts/<x>.test.mjs`, one file per call (loop for `settings-view` and `ux-strings`; once for `banner-view`, `catalog`, `heartbeat-card-view`, `incident-view` and `decision-view`) -- expected: all pass.
- `npm --prefix web run catalog` (once), then `git diff --stat web/src/app/msg/catalog.ts` -- expected: only the changed texts and keys.
- `npm --prefix web run lint` and `npm --prefix web run build` (once) -- expected: exit 0.
- `bash docker/tests/test-readme.sh` and `bash docker/tests/test-boundaries.sh` (once) -- expected: pass.
- `$LANE_D ci/warm.sh down` (teardown).

**Left to CI:**
- Playwright: S1, S13 and S14 (`live:sign-in-2`; the lead's smoke runs `--part 3/3` with `OCUTALON_LIVE_DEADLINE=1200`), `banners.spec.ts`, and the specs whose old text changed (`chromium`, `answers`).
- The full `shard:lane-a` and `shard:lane-b`.
- The fresh-environment check.

`SettingsModelsLive` sits in the Core area, so it needs no `ci/units.sh` change. It adds about 60-90 s to `shard:lane-b` (inference).

**Mutations (Rule 19; apply each, record it, then revert):**
- AC 1: `modelsView` lists a keyless provider as choosable -> `settings-view.test.mjs` red.
- AC 2: `TestModel` drops the `answered` flag -> `SettingsModelsLive` `TestModelAnswers` red.
- AC 3: `SaveModels` skips `SetModel` -> `SettingsModelsLive` red (the Decision model). Prices written outside the transaction -> `SettingsModels` "Price refused" red.
- AC 4: the costCap action loses its admin check -> `banner-view.test.mjs` red.
- AC 5: the step 1 text is put back -> `Test.Msg.Catalog` red.
- AC 6: the old timeout text is put back -> `Test.Msg.Catalog` and `catalog.test.mjs` red.
- AC 7: the "never entered on the settings page" sentence is dropped -> `test-readme.sh` red.
- DW-948: `refusalKind` treats a 400 with no known field as a field error -> `settings-view.test.mjs` red.

**Observed in the implement stage (Rule 19; each mutation applied, run, reverted; the tree was byte-identical after each revert):**
- mutation: AC 1, `modelsView` lists a keyless provider as choosable (`choosable: true`) -> `node --test web/scripts/settings-view.test.mjs` red in three tests (the supported-provider list, the model options, the second-model options).
- mutation: AC 2, `SettingsOps.TestModel` drops the `answered` member -> `SettingsModelsLive` `TestModelAnswers` red ("the model answered", "with the types of the answer"). The running SettingsOps job was restarted after the reload, since a warm reload does not restart a job. Also: the route answers a refused agent as a success (the `refused` outcome line removed from `Web.Api` `TestModel`) -> `SettingsApi` `TestModelTestRoute` red for `NoSuchAgent` and `@{`.
- mutation: AC 3, `SaveModels` skips `SetModel` -> `SettingsModelsLive` `TestSavedModelsApplyToTheNextDecide` red (Values shows the old model, the retry item, the Decision row's model, the mock's model). Prices written outside the transaction (the rollback replaced by a commit) -> `SettingsModels` `TestPriceRefusedRollsBack` red ("the first model keeps its price: the transaction rolled back").
- mutation: AC 4, the cost-cap action loses its admin check (`if (spec.action) {`) -> `banner-view.test.mjs` red in two tests ("are Budgets ... for an admin, and none for anyone else", "are none for the non-admin's cost limit").
- mutation: AC 5 and AC 6, the step 1 no-key text and the old timeout text put back in `Catalog/Core.cls` -> `Test.Msg.Catalog` red (`fallbackReason.timeout`, `banner.noModelKey`, `incident.fallback`, `digest.savedNoSummary`), and `catalog.test.mjs` red ("has a current catalog.ts").
- mutation: AC 7, the sentence "A key is never entered on the settings page, and the page never shows one." dropped from the README -> `test-readme.sh` red (`key-account: missing '...'`).
- mutation: DW-948, `refusalKind` treats every 400 as a field error -> `settings-view.test.mjs` red ("says form for a 400 that names no known field").
- mutation: AC 2 (the wait cap), `SettingsOps.BridgeTest` loses its expired-wait override (the `'$IsObject(response)` block) -> `SettingsModels` `TestRealModelTestWait` red ("a wait that expires answers reason timeout": reason `error`).
- mutation: AC 1 (the GET body), `Values()` loses its `prices` member -> `SettingsApi` `TestGetShape` and `TestModelsSaveRoute` red, `SettingsSave` `TestValues` red.
- mutation: DW-948 (adoption) and AC 4 (the Budgets action's admin wiring), a 403 check of its own put into `budgets-section.ts` -> `settings-refusal-sources.test.mjs` red ("budgets-section.ts reads a refusal through refusalOf and keeps no 400 or 403 check of its own"); `admin: false` in `banner-stack.ts` -> the same file red ("banner-stack.ts reads it from the snapshot"). Both reverted byte-identical.
- mutation: S1, S13, S13b, S13c, S14 and B3b (Playwright): not observed locally (DW-938 pattern); they run in CI (`live:sign-in-2`, `chromium`).

**Per test class on the warm throwaway `e18s3iw` (seconds, as `CLASS ... passed` printed them):** `Test.Core.SettingsModels` 0.12, `Test.Core.SettingsModelsLive` 19.2, `Test.Web.SettingsApi` 1.6, `Test.Core.SettingsSave` 0.64, `Test.Msg.Catalog` 7.6, `Test.Core.SettingsCommands` 0.08, `Test.Web.Api` 1.2, `Test.Web.BodyLimit` 0.07, `Test.Core.ConversationTurns` 0.94, `Test.Core.SettingsAudit` 0.15, `Test.Msg.Contracts` 0.07, `Test.Bridge.ModelChange` 106.7, `Test.Bridge.SettingsApply` 23.9, `Test.Digest.Compose` 0.68, `Test.Watch.NoticeText` 0.50, and (extra) `Test.Core.CommandsRouting` 0.10, `Test.Core.CommandsInProduction` 0.21. Web: `npm --prefix web test` 1577 of 1577, `npm --prefix web run lint` exit 0, `npm --prefix web run build` exit 0 (the bundle-size warnings are the existing ones), `test-readme.sh` and `test-boundaries.sh` pass.

**Shared surfaces:**
- The GET `/v1/settings` body (`prices`): `TestGetShape`, `TestValues`.
- The URL map and the POST route list: `TestRoutes`, `POSTROUTES`, `TestNonAdminIs403Everywhere`.
- The `CommandsIn` Routes table: `SettingsCommands`.
- The catalog's `fallbackReason.timeout` / `.rateLimited` and `banner.noModelKey`: every test in the Code Map's old-text list.
- `PAGE_TEXTS` / `LISTED_KEYS`.
- `BANNERS` (`banner-view.test.mjs`).
- `SETTINGS_TEXTS` and `ux-strings` `SOURCES`.
- The not-built list (S1).
- The instance-wide model, second model, price and budget values, the Config Store entries, and the runners' jobs.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Summary: Story 18.3 is implemented. The Models section (provider, model and second model per agent, a Test button per agent, four prices per listed model, one Save changes) and the Budgets section replace the not-built branch. `SettingsOps` has the `models` save kind (AD-19 order: every CheckModel, then the prices in one transaction, then each SetModel with its audit entry, put-backs audited), `Values().prices` and the `TestModel` verb (sent to Decide synchronously, `TESTWAIT` 45 s, an expired wait is reason `timeout`); the web API has `POST /v1/settings/models` and `/v1/settings/models/test`. The cost-cap banner has an admin-only "Budgets" action (same tab), the no-key banner reads the step 2 text, the DW-100 texts are the ruled ones (one Lane A literal, `Test/Watch/NoticeText.cls:270`, changed under the U-177 grant), `refusal.ts` is the one classifier for all six saving sections (DW-948), and the README has the ruled provider paragraph (last sentence dropped) with its facts in `test-readme.sh`.

Task 0: `Server_Response_Timeout=60` in the throwaway's `CSP.ini` (Design Notes item 7), so `TESTWAIT` stays 45 s.

Files changed (one line each):
- `src/ocutalon/cls/OcuTalon/Msg/Command/TestModel.cls` (new), `Core/CommandsIn.cls` (one route row), `Core/SettingsOps.cls` (models kind, prices, TestModel, four seams), `Web/Api.cls` (two routes, two handlers), `Msg/Catalog/Core.cls` (three ruled texts).
- `web/src/app/settings/{refusal,models-section,budgets-section}.ts` (new), `settings-view.ts`, `settings-page.ts` and the four existing sections (refusal helper), `banners/{banner-view,banner-stack}.ts`, `api/{api-client,api-types}.ts`, `msg/catalog.ts` (generated), `web/scripts/catalog.mjs`.
- `README.md`, `docker/tests/test-readme.sh`.
- Tests: `Test/Core/{SettingsModels,SettingsModelsLive,SettingsOpsNoReply}.cls` (new), `SettingsOpsProbe`, `SettingsSave`, `SettingsCommands`, `ConversationTurns`; `Test/Web/{SettingsApi,Api,BodyLimit}.cls`; `Test/Msg/{Catalog,Contracts}.cls`; `Test/Watch/NoticeText.cls:270` (granted literal); `web/scripts/*.test.mjs` (incl. the new `settings-refusal-sources.test.mjs`); `web/e2e/settings/settings.spec.ts` (S1, S13, S13b, S13c, S14), `banners/banners.spec.ts` (B3, B3b) and the specs whose old text changed.

Review: 33 findings from four layers; patches applied 9 (on 11 finding rows, 7 medium and 4 low: the real BridgeTest wait test, S13c, the unconditional keyless S13, the scoped and non-vacuous `TestModelTestAnswers`, the DW-948 and admin-wiring source test, the prices mutation, the stale Test line, the TestModel contract entry, the corrected comments); deferred 1 (Test rows in the decision and cost views, Lane A, medium unverified); every rejected finding has its reason in the Review Triage Log.

Follow-up review recommended: true. The unverified risk: S13, S13c, S14 and B3b are Playwright cases that have not run (the 150 s rule); a first CI run of `live:sign-in-2`, `chromium` and `banners` pins them. S13c is new in the review pass.

Verification performed (warm throwaway `e18s3iw`, CI mock, one class per call, after the last patch; seconds): `Test.Core.SettingsModels` 0.20, `SettingsModelsLive` 18.9, `Test.Web.SettingsApi` 1.06, `Test.Core.SettingsSave` 0.60, `Test.Msg.Catalog` 8.75, `Test.Core.SettingsCommands` 0.03, `Test.Web.Api` 0.64, `Test.Web.BodyLimit` 0.08, `Test.Core.ConversationTurns` 0.83, `Test.Core.SettingsAudit` 0.17, `Test.Msg.Contracts` 0.04, `Test.Bridge.ModelChange` 107.2, `Test.Bridge.SettingsApply` 23.7, `Test.Digest.Compose` 0.67, `Test.Watch.NoticeText` 0.60: all passed. `npm --prefix web test` 1584 of 1584, `lint` and `build` exit 0, the catalog regenerates identically, `test-readme.sh`, `test-boundaries.sh` and `test-ci-config.sh` pass.

Left to CI: Playwright S1, S13, S13b, S13c, S14 (`live:sign-in-2`, `--part 3/3` with `OCUTALON_LIVE_DEADLINE=1200`), `banners.spec.ts`, the specs whose old text changed (`chromium`, `answers`); the full `shard:lane-a` and `shard:lane-b`; the fresh-environment check.

Residual risks: contended files touched as plain appends (`Core/CommandsIn.cls`, `Web/Api.cls`, `Test/Web/Api.cls`, `Test/Web/BodyLimit.cls`) need a plain-union merge with Epic 41; `web/scripts/ux-strings.test.mjs` has its own block beside Epic 19b's. Footprint extensions beyond the spec's list: `web/scripts/announce-focus-sources.test.mjs`, `web/scripts/settings-refusal-sources.test.mjs`, `Test/Msg/Contracts.cls`, `Test/Core/SettingsOpsNoReply.cls`.
