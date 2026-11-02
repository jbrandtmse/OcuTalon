---
title: 'Long conversations are compacted under the limit'
type: 'feature'
created: '2026-10-31'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'NFR-3 in the loop: AD-20 bounds the fourth request at 94,000 tokens only when the first request is at most 40,000. Compaction keeps the last user turn whole, so a fork whose kept turn was tool-heavy (up to about 62,000 tokens), a flagged turn with nothing older to summarize, or a turn whose own input is large can still send a first request between 40,000 and the limit, and the later requests of its tool loop can pass 100,000.'
    evidence: 'AD-20 Rule (the 40,000 + 3 x 10,000 + 3 x 8,000 arithmetic; nothing aborts inside the loop, S4); this spec guards every request the runner shapes at the limit, not at 40,000 (Design Notes R1).'
    severity: medium
    location: 'src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls (the compaction step)'
---

<intent-contract>

## Intent

**Problem:** Decide flags a `turn` above 40,000 tokens for compaction (Story 1.9), but the runner ignores the flag, so a long conversation is sent whole: its tool loop can pass 100,000 tokens (DW-130), and once its stored history alone passes the request-size limit every turn answers `too_large` and the conversation is stuck (DW-125).

**Approach:** The runner compacts a flagged turn that continues its conversation, in its own job before `Chat`: it cuts the stored history so the last user turn stays whole, calls `ForkAndSummarize` with the compaction prompt and a low-effort summarizer, and switches the link to the fork only after a check. Any failure, or a request that would still pass the limit, rotates to a fresh session seeded with a code-written summary. Decide gives such a turn 20 more seconds, and judges `too_large` on the request the runner will send. A compaction `Usage` row prices the summarizer's request. A thinking-history smoke test joins the release-candidate run on the real model.

## Boundaries & Constraints

**Always:**
- Compaction runs only in `Adapter.Agent`'s linked path (`AnswerLinked`), in the runner's job, under the conversation lock, after the session is opened and before `Converse` starts the step buffer. No callback calls it, and no AI Hub call runs inside a callback (AD-6).
- It runs only for a request with `Compact` 1 that continues a linked conversation (an opened session). Untrusted, `fresh`, `decide`, `diagnose` and first turns are never compacted, whatever `Compact` says.
- The guarded path is `session.ForkAndSummarize(provider, "", k, ##class(OcuTalon.Bridge.Compaction).Prompt(), 0)`. `k` counts the messages from the newest user message that is not a tool result to the end of `GetContext()`, read outside every callback. With no message before that one but system messages, nothing is compacted.
- The link moves to the fork only after `Compaction.Check` passes on the fork's `GetContext()`: the first non-system message is a user message that is not a tool result, and every tool result follows the tool call it answers. Then, in this order: the fork is `%Save`d, every reference to the original session is released, the fork is opened again with `OpenSession` (a newly composed config), and `ConversationLink.Point` names it. `Chat` runs in the reopened fork.
- Seeded fallback: any exception from `ForkAndSummarize`, a failed check, a failed save or reopen, a summarizer request whose estimate passes the limit, or a first request that would still pass the limit gives a fresh AI session (`NewSession`). It is seeded with `Compaction.Seed` of the original session's stored user and assistant texts, through `ChatInput`, and is saved and linked after a completed, untainted `Chat`, like a `fresh` turn.
- A compaction failure is one warning (runner item, OwnerRef, DecisionRef, which step failed, redacted text). It never becomes the reply's `FailureText` or the turn's `FallbackReason` (AD-8).
- The summarizer provider is `%AI.Provider.Create` with the runner's own provider settings (`..ProviderConfig` expanded as AI Hub expands it, with the provider name resolved as AI Hub resolves it), plus `extra_config.output_config.effort` `low`, `http_config.request_timeout_secs` 20, and the full retry block `{"max_retries": 0, "attempt_timeout_secs": 20, "initial_backoff_ms": 500, "max_backoff_ms": 2000}` (AD-8: never a partial block). The settings object exists only in memory. It is never logged, stored, put in a warning or a reply. No sampling parameter is set (AD-7).
- One `Usage` row per summarizer call (returned or thrown): `Agent` `compaction`, `Estimated` 1, `RequestCount` 1. Its `InputTokens` and `LargestRequestTokens` are `StepBuffer.Tokens` of the prompt's length plus `Compaction.TranscriptChars` of the summarized messages. `OutputTokens` is `Tokens` of the stored summary's length (0 after a throw). Its cost is `Price.CostFor` at the session's model. It carries the request's `DecisionRef`, `ItemId`, `Kind`, `OwnerRef` and `Channel`, so `Usage.Totals` and the day's spend count it (AD-20).
- Decide sets the timer of a turn it flags that continues a linked conversation (`IsLinked`, not `fresh`, the link names a session) to `TimerSeconds + Compaction.#SUMMARIZERSECONDS` (20), at most `MAXTIMER` (110). `RemainingMs` and `Resend` count from the same total. Every other request keeps `TimerSeconds`.
- `Precheck` judges `too_large` for such a turn on `Tokens(chars - history + min(history, Compaction.#SEEDCHARS))`, where `history` is the stored history it added: the most the runner will send after compaction or rotation. Every other request keeps the full estimate. The flag still uses the full estimate. The runner reads the same limit (Decide's `RequestTokenLimit`, normalized by one shared method).
- Bridge classes name no other OcuTalon package (AD-2). `Bridge.Compaction`'s helpers are pure: they take dynamic arrays and objects and make no `%AI` call.
- No stored-data change: no new property or index on any persistent or message class.
- Tests run on throwaway stacks only. The mock gets only new scenario files under `ci/mock/scenarios/A/`. The thinking-history smoke never runs on a real provider in this run (no real key, ever).

**Never:**
- `Session.Summarize` in place, `Fork` without summarizing, or a compaction outside the adapter.
- A request the runner shapes (the summarizer's or the turn's first) above the limit.
- Changing `Request.Compact`'s rule in `SentRequest`, the compaction prompt's text, `Timeouts.Derive`, or any runner's session config outside the smoke's own test adapter.
- Touching Lane B's classes (`Core.Conversation` and its recap, `Data.Ownership`, `web/**`) or `Test.Web.SessionEvents.ReferenceHits`. Never touching `.github/workflows/lane-a.yml` (Epic 13's), `ci/units.sh`, or a contended file of the project block.
- Redact or key-proof work: DW-386 and DW-448 are declined to the burn-down story (Design Notes).
- Running `eval/run.sh --release-candidate` without `--on-mock`.

## I/O & Edge-Case Matrix

All rows are in-process (`Test.Bridge.Compaction`, a shadow `ZzRunner` host on the CI mock) unless they name the production. "Guarded" means: one summarizer request in the mock's log, the fork linked and saved, and the original session row kept for the purge (30.2).

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | Guarded compaction | Owner with turns 1 and 2 saved (turn 1 about 170,000 characters, `recall-tell`); turn 3 `Compact` 1, `[[mock:recall-tell]]` | Guarded: `ForkAndSummarize` gets `k` = turn 2's messages; the summarizer request's system text starts `OCUTALON-COMPACTION-V1`, carries `output_config.effort` `low`, and its transcript holds turn 1's text. Turn 3's request starts with the summary and then turn 2's user message, and holds none of turn 1's filler. One `compaction` Usage row with the costs above. Reply usable, `SessionRotated` 1 | No error expected |
| 2 | Nothing older | Owner with one saved turn; turn 2 `Compact` 1 within the limit | No summarizer request, no compaction row, the link unchanged, the request sent as it is | No error expected |
| 3 | Summarizer off-schema (AD-20) | As row 1, with `[[mock:summary-off-schema]]` in turn 1's text | `ForkAndSummarize` throws. Seeded: a new session whose first request carries the seed, then turn 3's input. Saved and linked after `Chat`, `SessionRotated` 1. One compaction row with `OutputTokens` 0. Reply usable | One warning. Never a `FailureText` or `FallbackReason` |
| 4 | Check fails | As row 1, with the seam `ZzCutAdapter`, whose cut starts at a tool result | The fork is refused, never saved or linked. Seeded as row 3 | One warning |
| 5 | Summarizer rate-limited (no retries) | As row 1, with `[[mock:summary-rate-limited]]` (new, 429) in turn 1's text | Exactly one summarizer request is logged. Seeded as row 3 | One warning |
| 6 | Summarizer request over the limit | Decide's `RequestTokenLimit` row below the summarizer's estimate (prompt plus transcript) | No `ForkAndSummarize` call, no summarizer request, no compaction row. Seeded | One warning |
| 7 | History over the limit, nothing older (DW-125) | One saved turn of about 170,000 characters; `RequestTokenLimit` 41,000; turn 2 `Compact` 1 | The request as it stands would pass the limit: seeded, with each side of the seed cut at 2,000 characters. Every logged request is at most 41,000 tokens | One warning |
| 8 | Not a compactable request | `Compact` 1 on an untrusted turn, a `fresh` turn, a `decide` request and an owner's first turn | No compaction, no summarizer request, no compaction row | No error expected |
| 9 | Tainted or failed `Chat` after the switch | Row 1, with turn 3's `Chat` tainted (gate scenario), and once with `ZzThrowAdapter`'s `Converse` | The link names the fork as saved before `Chat`. The tainted history is not saved. A thrown `Chat` gives the usual failure reply, `SessionRotated` 1 | As today |
| 10 | Four iterations after compaction (DW-130) | `ZzResultAgent`; turn 2 of about 140,000 characters kept whole; turn 3 `Compact` 1 with `[[mock:compaction-loop]]` (new: three `zz_result_text` steps of 40,000 characters, then text) | Turn 3's first logged request is at most 40,000 tokens, and every one of its 4 requests is under 100,000 (characters / 4). Mutation control: without compaction its fourth request passes 100,000 | No error expected |
| 11 | Pure rules | Arrays in the shape Task 0 records | `Cut`: `k` and the older messages, none when nothing older. `Check`: passes a good fork; fails a tool result first, a result before its call, an orphan result. `Seed`: head line, newest exchanges kept, oldest dropped, each side at most `SEEDPART`, never longer than `SEEDCHARS`, no tool text. `SummarizerSettings`: the overrides above, the runner's other settings kept, no sampling key | `Seed` of no texts is "" |
| 12 | Timer (production) | A flagged turn that continues its conversation; an unflagged turn; a flagged first turn | The first gets `min(TimerSeconds + 20, 110)` seconds; the others `TimerSeconds`. `TimerSeconds` 100 gives 110 | No error expected |

</intent-contract>

## Code Map

Bridge classes are under `src/bridge/cls/OcuTalon/Bridge/`, product and test classes under `src/ocutalon/cls/OcuTalon/`.

- `Bridge/Adapter/Agent.cls` -- the runner's adapter (ours).
  - `AnswerLinked` (:359-388): the lock, then `OpenSession` (:374) or `NewSession`, then `Converse` (:378), then `SaveLinked` (:379). The compaction step goes between :374 and :378, for `opened` and `request.Compact`.
  - `OpenSession` (:270-290): reopening needs no live reference to the session (the doc at :266-269). `ReleaseSession` (:464): clears `..Agent.Session`.
  - `NewSession` (:250); `SaveLinked` (:448-460): sets `SessionRotated` only for `fresh`.
  - `ChatInput` (:484-492): the order seed, note, input.
  - `BaseChars` (:498-516): the first request's size (prompt, tool catalog, input, `GetContext()` JSON). Reuse it for the fork's and the as-is size.
  - `RecordUsage` (:590-605): the warning pattern for a Usage row. `TimeoutMs` (:242-247): how the adapter reads a Decide setting (`Ext.Accessor ValueFor`).
- `Bridge/Compaction.cls` (:1-39) -- `PREFIX` (:8), `XData Prompt` (:11-22: the seven keys, every tool result in `facts_learned`), `Prompt()` (:26). It gains the constants and the pure helpers. `Test.Contract.Ac` pins only `Prompt`'s signature (:353).
- `Bridge/Process/Decide.cls` -- (ours).
  - `MAXTIMER` (:105), `MAXREQUESTTOKENS` (:112), `COMPACTTOKENS` (:115), `TimerSeconds` (:169).
  - `OnRequest`'s send and timer (:273-279). `OnResponse`'s re-send delay with `RemainingMs` (:340-351, :347). `Resend` (:366-380). `SentRequest` (:394-400, unchanged rule). `RemainingMs` (:404-409).
  - `Precheck` (:648-681): limit normalization (:665-672, to become the shared `RequestLimit`) and `tooLarge` (:679). `EstimateTokens` (:693-704): it adds the history at :701. It gains an Output with the history's characters.
  - The class doc on the estimate and the flag (:18-30) says "The runner ignores it until Story 30.1". Update it.
- `Bridge/RequestSize.cls` -- `HistoryChars` (:67-85): the stored `ContextData` size, read without a native call.
- `Bridge/Data/Usage.cls` -- `Agent` (:23, "or compaction"), `Estimated` (:56). `FromStats` (:110-138) is the sibling of the new `FromEstimate`. `Totals` (:144). No storage change.
- `Bridge/Data/Price.cls` -- `CostFor(model, prompt, cacheRead, cacheWrite, completion, largest, requestCount)` (:58-64). `Bridge/Adapter/StepBuffer.cls` -- `Tokens` (:146-149), `CHARSPERTOKEN` 4 (:19).
- `Bridge/Data/ConversationLink.cls` -- `Point` is the only writer, under the lock. `Bridge/Purge.cls` (read only) marks and deletes unlinked sessions (:6, :70-97), so the old session and an unlinked fork need no cleanup.
- `Bridge/Msg/Request.cls` -- the `Compact` doc (:51-54). Doc only, no storage change. `Bridge/Timeouts.cls` -- `Derive` (:42-58): the retry block's shape.
- `irislib/%AI/Agent/Session.cls` (read only) -- `GetContext` (:284, needs the session attached), `ForkAndSummarize(provider, model, preserveRecent, customPrompt, keepStats)` (:587-605, the original unchanged), `MessageCount` (:448), `Summarize` (:664, never used), `ContextData` (:63, `%Stream.GlobalCharacter`).
- `irislib/EnsLib/AI/Agent/OutboundAdapter.cls` (read only) -- `setupProviderFromSettings` (:243-297): `%AI.Utils.SettingStore.Expand(..ProviderConfig)`, and the provider name from `ProviderName`, else `model_provider`, else the agent's `PROVIDER`. `irislib/%AI/Provider.cls` `Create(name, settings)` (:69).
- `Core/Conversation.cls` (Lane B, read only) -- `Recap` (:625-647; `RECAPTURNS` 20, `RECAPCHARS` 2000, `RECAPHEAD` :82): the model for the seed's form.
- `ci/mock/mock.mjs` (read only) -- summarizer selection: the system text starts with the prefix, and the last `summary-*` marker of the transcript wins, else `summary` (:26-34, :157-171, :422-431). The request log keeps every body field but messages, system and tools in full (:174-183), and header names only. A mock request's first marker wins, so a seeded turn answers with the first marker that the seed quotes.
- `ci/mock/scenarios/A/` -- `summary.json`, `summary-off-schema.json`, `result-cap-steps.json` (the `zz_result_text` pattern), `recall-tell.json`.
- `Test/Bridge/Runner.cls` -- `NewRunner(agentClass, effort, providerConfig, configName, runnerClass)` (:1246) and `ProviderConfig` (:1257): the shadow host on the mock. `Test/Bridge/ZzThrowAdapter.cls` / `ZzThrowRunner.cls`: the seam pattern for `ZzCutAdapter` and the smoke's adapter.
- `Test/Bridge/Conversation.cls` -- the in-process conversation tests (`NewHost` :786) and helpers to reuse.
- `Test/Tools/ZzResultAgent.cls`, `ZzResultTools.cls` -- `zz_result_text`.
- `Test/Agent/RequestSize.cls` -- the live pattern: `Prepare`, `Put` of a Decide setting and restart, `OverTurn` (:217), `SentCompact` (:225). `TestCompactFlag` (:146-178) stays valid: its owner is new, so there is nothing to compact.
- `Test/Agent/RunnerFixture.cls` -- `Run`, `NewRequest`, `UsageIds`, `FindRequests`, `Messages`, `Headers`, `AddUsage` (:1066). `Test/Contract/Mock.cls` -- `LogMark`, `LogSince`.
- `Test/Bridge/CodeRules.cls` -- `CHATCALLS` (:113), `CHATTERS` (:140), `SESSIONCALLS` (:146), `SESSIONMAKERS` (:149), `LINKNAMERS` (:163), `TestSessionsOnlyThroughTheComposer` (:370). `Offenders` (:1054) skips `OcuTalon.Test.*`.
- `Test/Bridge/Decide.cls` -- `TestCompactFlag` (:2097), `TestTimerFallback` (:2273), and the precheck tests (`TestPrecheckOrder` :1766, `TestResendTooLargeSendsNothing` :2430).
- `Test/Agent/Constants.cls` (:54-68) -- `TestCompactionPrompt` pins the prompt.
- `Eval/Gate.cls` -- `SMOKE` "not run" (:64-65), `Result` sets `thinkingHistorySmoke` (:333), `Text` (:415). `Test/Eval/Gate.cls` pins it (:463, :524).
- `Test/Eval/KeyProof.cls` -- the sibling pattern: a `%UnitTest` class that is also the helper `eval/run.sh` calls (`Scan` :182, `Print` :231).
- `eval/run.sh` -- the header note (:83-84), modes (:121-134), `verdict_run` and its context `cx` (:339-354, :345), the release-candidate sequence (:656-740).
- `docker/tests/test-eval-set.sh` -- pins of `eval/run.sh` and the job (:1111-1119, :1453-1456).
- `Bridge/Budget.cls` -- `State` (:41-92), `UsageSpent` (:137-154, a scan by `RecordedAt`), `UnpricedModels` (:177-191). `Test/Bridge/Budget.cls` `AddRow` (:646). For DW-93.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0: `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTask0.cls` (temporary; deleted before the finalize commit, or its useful parts moved into the new tests) -- measure first, with `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh class OcuTalon.Test.Bridge.ZzTask0` on a fresh throwaway on the mock (lane B's variables, never the slot). Record the facts in this spec's `## Verification`, "Task 0 facts".
  - (a) `GetContext()` after a text turn and after a tool-call turn (`chat.json`): the roles, how content, tool calls, tool results and their ids are keyed, and whether a system message is in the array.
  - (b) `ForkAndSummarize(provider, "", k, Prompt(), 0)` with `summary`: the fork's `GetContext()` (the summary and action-log messages, their role and place); that the last `k` messages are kept; that the original is unchanged. After `%Save` and release, `OpenSession(forkId)`'s next request carries `max_tokens` 8000 (mock log). The mock's summarizer request: system text, transcript form, `output_config`, and its size against `TranscriptChars`.
  - (c) `summary-off-schema` throws (`<%AICore>InternalError`). `summary-rate-limited` with the summarizer settings: one request, then a throw.
  - (d) DW-93: with 100,000 Usage rows (about 1,100 recorded today, the rest over 90 days; `AddUsage` or one SQL insert loop), the median of 5 calls of `Budget.State()` and of `Decide.Precheck` for a short turn. Then delete the rows.
  - (e) The mock answers a chat request that carries `thinking.block_binding` and the `anthropic-beta` header (the smoke's shape). If it refuses one, stop that part with `## Clarification Needed`: new mock behaviour is Lane B's (AD-22).
  - If (a)-(c) contradict this spec's rules, adapt only within them: every failure goes to the seeded path. If an off-schema reply does not throw and its fork passes `Check`, HALT `intent gap` naming AD-20 (S18's finding no longer holds).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Compaction.cls` -- add `SUMMARIZERSECONDS` 20, `SEEDTURNS` 20, `SEEDPART` 2000, `SEEDCHARS` 80000, `SEEDHEAD`, and these pure helpers -- the rules of rows 1-7 and 11:
  - `Cut(context, Output older) As %Integer` (`k`, 0 when nothing older);
  - `Check(context) As %Boolean`;
  - `Seed(context) As %String`;
  - `TranscriptChars(older) As %Integer` (the JSON length of the summarized messages);
  - `SummaryChars(context) As %Integer` (the fork's head system messages);
  - `SummarizerSettings(settings) As %DynamicObject` (a copy with the overrides).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- `FromEstimate(request, model, inputChars, outputChars, Output row) As %Status` beside `FromStats`. It reuses `StepBuffer.Tokens` and `Price.CostFor`. No storage change.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- these changes, and the docs (:18-30 and the methods):
  - `RequestLimit(text, Output warning)`, taken out of `Precheck` and used by the adapter too;
  - `EstimateTokens` gives the history's characters;
  - `Precheck` uses the post-compaction bound for a turn that will be flagged and continues a linked conversation;
  - `TimerFor(request, compact)`, used by `OnRequest`, `RemainingMs` and `Resend`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- the compaction step in `AnswerLinked` (one private method, for example `Compact`), with its warning and its usage row. Also:
  - `ChatInput` takes an optional seed that replaces `request.SeedText`;
  - `SessionRotated` is set to 1 when compaction moved the link;
  - a private `CutOf(context)` calls `Compaction.Cut`, so that the seam can override it;
  - the class doc is updated.
  - Rationale: AD-6, AD-20.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls` -- the `Compact` doc: the runner now compacts a flagged turn that continues its conversation. Doc only.
- [ ] `ci/mock/scenarios/A/summary-rate-limited.json` (new: 429, `Retry-After` 1) and `ci/mock/scenarios/A/compaction-loop.json` (new: three `zz_result_text` steps of 40,000 characters, then text) -- rows 5 and 10.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Compaction.cls` (new) -- rows 1-11, one method each or grouped, on the mock with a shadow `ZzRunner`. It is self-contained: owners, links, sessions, Usage rows and settings rows are put back in `OnAfterOneTest`, also after a failure. `ZzCutAdapter.cls` and `ZzCutRunner.cls` (new, the `ZzThrow*` pattern): `CutOf` returns a cut that starts at a tool result.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Agent/Compaction.cls` (new, through the running production; the `RequestSize` pattern) -- AC 1 to AC 3 and row 12.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls` -- `TimerFor` (row 12's cases, `MAXTIMER` cap) and the precheck bound (with and without a link, history below and above `SEEDCHARS`, a `fresh` turn). Update every existing assertion and doc that says the runner ignores the flag.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `SESSIONCALLS` also flags `forkandsummarize`; a new test flags `.summarize(` in every non-test class (none allowed), with its scanner checks -- AC 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Eval/ThinkingSmoke.cls` (new; the `KeyProof` pattern), with `ZzSmokeAdapter`, `ZzSmokeRunner` and `ZzSmokeChat` (new; `OcuTalon.Agent.Chat` with `TOOLSETS` `OcuTalon.Tools.Reminders` only) -- AC 5. The class has:
  - `Run(Output problems) As %Boolean`;
  - `Print`, which writes `CHK|smoke|passed|failed` and problem counts, never reply text or settings;
  - `TestOnTheMock`.
- [ ] `src/ocutalon/cls/OcuTalon/Eval/Gate.cls` -- `Result` takes `context.thinkingHistorySmoke` when it is set, else `SMOKE`, and documents the values passed, failed and not run. The verdict is unchanged. `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls` -- a context value reaches the JSON and the Markdown line; none gives "not run".
- [ ] `eval/run.sh` -- in `--release-candidate` without `--on-mock` only, once after the attempts: run `ThinkingSmoke.Print(ThinkingSmoke.Run(.p))` through `iris_script` and pass the value in `cx`. The push run and `--on-mock` keep "not run". Update the header note (:83-84). `docker/tests/test-eval-set.sh` -- pin that branch, that it is skipped for `--on-mock` and the push run, and the new note.
- [ ] `_bmad-output/implementation-artifacts/spec-30-1-long-conversations-are-compacted-under-the-limit.md` `## Verification` "Task 0 facts" (d) -- DW-93, for the lead, from the measurement: at 250 ms or less (median `Precheck`), no code change, and the lead writes `wontfix-accepted` with the measurement and `reopen_if=a Precheck median above 250 ms on a field instance, or a Usage table above 100,000 rows`. Above 250 ms, the implement stage stops that part with `## Clarification Needed`: an index is a stored-data change plus Lane B's pin, and a cache changes when the cap engages.

**Acceptance Criteria:**
- AC 1 (Integration, NFR-3): Given the running production on the mock, when an owner's conversation grows over three or more turns through Decide until a turn is flagged with older history (turn 1 about 170,000 characters), then:
  - that turn is answered from a compacted session;
  - its `Request.Compact` is 1;
  - a `compaction` Usage row with `Estimated` 1 has its DecisionRef;
  - every Usage row of the conversation has `LargestRequestTokens` under 100,000;
  - every request the mock logged for it is under 100,000 tokens (characters / 4).
- AC 2 (DW-125): Given an owner whose stored history alone passes `RequestTokenLimit` (turns saved at the default limit, then a row of 41,000 and Decide restarted), when the owner sends a short turn, then:
  - it is answered, not `too_large`;
  - every request the mock logged for it is at most 41,000 tokens.
  And a turn whose input alone passes the limit still takes `too_large` and reaches no runner.
- AC 3 (timer): Given Decide's `TimerSeconds` 60, when Decide sends a flagged turn that continues its conversation, then the alarm it sets is 80 seconds, and a short turn's is 60.
- AC 4 (AD-20): Given the product classes, when `Test.Bridge.CodeRules` scans them, then no class calls `.Summarize(` on a session, and only the adapter calls `ForkAndSummarize`.
- AC 5 (smoke, AD-20): Given the CI mock, when `ThinkingSmoke.TestOnTheMock` runs the smoke, then:
  - three turns run, each in a job of its own;
  - turn 2 runs on `ZzSmokeChat`, so its tool names differ from turn 1's;
  - turn 3 is compacted through the guarded path;
  - every chat request carries `thinking.block_binding.prefix_mismatch_behavior` `error` and the `anthropic-beta` header;
  - no logged assistant message holds a thinking block;
  - every turn is usable, and `Run` returns 1.
  And `eval/run.sh --release-candidate` (real model) records `thinkingHistorySmoke` passed or failed, while the push run and `--on-mock` record "not run" (`test-eval-set.sh`).
- AC 6 (regression): Given this story's changes, when the existing tests run, then `Test.Agent.RequestSize`, `Test.Bridge.Conversation`, `Test.Bridge.Runner`, `Test.Bridge.Decide`, `Test.Bridge.Usage`, `Test.Bridge.Purge` and `Test.Agent.Constants` pass unchanged in intent, and `bash eval/key-proof.sh` still passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**
- AD-20: compaction (the cut, the prompt, the check, the fork, the seeded fallback, the summarizer, the `compaction` Usage row), the 20 s, and the release-candidate smoke.
- AD-6: only the runner chats and makes sessions; the link and lock; no native call in a callback; `%Save` and `Point` under the lock.
- AD-8: the fallback reasons; `too_large` before sending; a compaction failure is never a reason; the full retry block.
- AD-7: the composed session config on every reopen; the model; no sampling parameter.
- AD-5: the timer at or under 110; append-only storage (nothing changes).
- AD-2: the bridge names no OcuTalon package.
- AD-10: a tainted turn is never saved.
- AD-27 and Story 30.2's `Bridge.Purge`: old sessions and an unlinked fork are purged.
- AD-19: key placeholders, and no key in a log or a warning.
- AD-22: throwaways, mock scenarios under `A/`, and the release-candidate run.
- AD-33: lane ownership.
- AD-6's adapter bullet says the adapter `%Save`s a session only after a completed `Chat`. AD-20 says the runner `%Save`s the fork after the check, before `Chat`. AD-20 is the specific rule for the fork; every other save stays after a completed `Chat` (spine note below).
- No acceptance criterion contradicts an AD's Rule.

**Integration ACs (Rule 1).** AC 1 and AC 2 are the consumer path: Decide's flag and precheck, then `ChatAgent`'s runner, then a reply in the production.
- Consumes:
  - Story 1.9: `Request.Compact`, `EstimateTokens` and the limit;
  - Story 1.8: the link, the lock, `OpenSession` with a composed config;
  - Story 30.2: `Bridge.Purge` removes unlinked sessions;
  - Story 9.5: `eval/run.sh` and `Eval.Gate`.
- Consumed-by:
  - Story 9.5's release-candidate run reads `thinkingHistorySmoke`, wired here;
  - Lane B's `Core.Conversation` (Epic 2), with no change: its long conversations now keep working;
  - `Data.Ownership.TurnCost` and `RunCost` (Lane B) sum the `compaction` row by DecisionRef, with no change.

**Extend, don't copy (Rule 2).**
- `Usage.FromEstimate` sits beside `FromStats` and shares `Price.CostFor` and `StepBuffer.Tokens`.
- `Decide.RequestLimit` is taken out of `Precheck`, so the adapter does not copy it.
- The seed copies the form of Lane B's `Conversation.Recap`. It is a copy because AD-2 forbids the bridge to name `Core`, AD-33 makes the class Lane B's, and the source differs: the stored history, not `Turn` rows.
- The summarizer's provider-name resolution mirrors AI Hub's `setupProviderFromSettings`, which is Internal and Private.
- The seams follow `ZzThrowAdapter`/`ZzThrowRunner`. The smoke follows `Test.Eval.KeyProof`.

**Decided in-stage.**
1. DW-386 and DW-448 are declined together, for size (see Declined). The compaction core, its tests and the smoke already make the spec oversized and one long implement pass.
2. Compaction runs inside the adapter and puts its pure rules in `Bridge.Compaction`. So `CHATTERS`, `SESSIONMAKERS` and `LINKNAMERS` stay as they are, and `SESSIONCALLS` gains `forkandsummarize`, so that a later class outside the adapter is flagged.
3. The fork is reopened with `OpenSession` before `Chat`, so that the composed config (cap, effort, `timeout_ms`) applies (S2: a session resumed without it loses them). `Point` follows a successful reopen. A fork saved but not reopened stays unlinked, and the purge removes it.
4. "Can compact", for the 20 s and the precheck bound, means a flagged turn that continues a linked conversation (Decide cannot see the history's turns). A conversation with one earlier turn gets the 20 s and no summarizer call. That is harmless.
5. `too_large` for such a turn uses `min(history, SEEDCHARS)`: whatever the runner sends (the as-is session, the fork or the seed) is at most that, because it guards each at the limit. This is Story 1.9's "a request still over the limit".
6. A `compaction` row is written for every summarizer call, a thrown one included, with output 0 then: the request may have been billed (`summary-off-schema`), and the row is an estimate anyway.
7. `SessionRotated` is 1 when compaction moved the link (to the fork or to the seed), because the link names a new AI session. No product class reads it (only Decide carries it).
8. The seed has the form of Lane B's recap: a head line, then `User: ` / `Assistant: ` lines, the newest 20 exchanges, each side cut at 2,000 characters, and at most 80,000 characters.
9. The smoke forces the thinking-history rule with `extra_params.thinking` `{"type":"adaptive","block_binding":{"prefix_mismatch_behavior":"error"}}` in its own test adapter's session config, and the provider header `anthropic-beta: thinking-binding-controls-2026-08-01`. This is (inference): it comes from the Claude API reference, S2's notes do not say how S2 forced the rule, and AI Hub's pass-through of a nested `extra_params.thinking` is unmeasured on a real provider.
   - In real mode the shadow host's provider config is ChatAgent's Config Store entry as stored (`Bridge.ConfigStore.Details`, key placeholder kept, never expanded by the smoke) plus the header. In mock mode it is `Test.Bridge.Runner.ProviderConfig` plus the header.
   - It uses owner `eval` (no cap or session total counts it) and runner name `ZzSmoke`. Its link and sessions are removed before and after.
   - A failed smoke is recorded and does not change the verdict: making it a release gate is the owner's call.
10. DW-93's threshold is 250 ms (median `Precheck` at 100,000 rows). A turn's model call takes seconds, and Decide's timer is 60 s.
11. Test hint: a seeded turn's first mock marker is the oldest one the seed quotes, so give older turns the marker that the seeded turn expects (`recall-tell`).

**V1. An addition to AD-20's fallback triggers (veto window: amending an AD, U7). For the lead.**
- AD-20 names two triggers: an exception from `ForkAndSummarize` and a failed check.
- This spec adds the over-the-limit guards, because NFR-3 and AD-8 say a request over the limit is never sent, and AD-20 is silent on these cases:
  - a summarizer request whose estimate passes the limit (a history of about 400,000 characters, DW-125);
  - a first request still over the limit (the fork or the as-is session);
  - a failed save or reopen of the fork.
- Recommendation: keep. Spine line (Rule 20, light path), in AD-20's Fallback bullet: "…or a summarizer request or first request that would pass the request-size limit, or a fork that cannot be saved and reopened…".

**R1. NFR-3 residual (for the lead; the frontmatter's `deferred` item; not planned around).**
- AD-20's 94,000 bound needs a first request of at most 40,000 tokens. This spec guards at the limit. A fork whose kept turn was tool-heavy, a flagged turn with nothing older, or a large input can therefore start between 40,000 and the limit, and its loop can pass 100,000.
- Options:
  - (a) Refuse such a fork, or an as-is session above 40,000, in favour of the seed. That loses the kept turn's tool results and the user's last paste.
  - (b) Decide refuses a tool-capable turn whose non-history part is above about 46,000 (`too_large`).
  - (c) Accept, with `reopen_if`: the mock or a recorded run logs a request above 100,000.
- (a) and (b) change what the product does: they are for the owner. DW-130 is addressed for the compacted case (row 10).

**Declined.**
- Declined DW-386: moved to the Epic 30 burn-down story (size). The lead re-owns it with U-184's condition (every `key_like` shape of `docker/tests/lib-keys.sh` in `Bridge.Redact`, one test per shape).
- Declined DW-448: moved to the Epic 30 burn-down story (size). The lead re-owns it with U-185's condition. Investigation notes for it:
  - No OcuTalon class has a `%Stream.Global*` property.
  - `%AI.Agent.Session.ContextData` is a `%Stream.GlobalCharacter` with `COMPRESS` 1: zstd for a first block of 1,024 characters or more, flagged in the header node, not in the chunk.
  - User text sits in `$List` elements of `%String(MAXLEN="")` properties, and an element with any character above 255 is stored as 16-bit.
- DW-93, DW-125 and DW-130 are addressed: DW-93 by Task 0 (d) and the lead item, DW-125 by rows 6-7 and AC 2, DW-130 by rows 1 and 10 and AC 1, with R1.

**Spine notes for the lead (Rule 20).**
- AD-20: V1's text. The fork is reopened through `OpenSession` before `Chat`. A compaction sets `SessionRotated`. The seed's bound (`SEEDCHARS`, 80,000 characters). The 20 s go only to a flagged turn that continues a linked conversation.
- AD-8: `too_large` for such a turn is judged on the post-compaction bound.
- AD-6: the adapter bullet "`%Save`s an AI session only after a completed `Chat`" gains "or a compaction fork, after its check (AD-20)".
- AD-22: the smoke's home (`Test.Eval.ThinkingSmoke`, through `eval/run.sh --release-candidate` on the real model; "not run" in push and `--on-mock` runs).

**Files outside "Ours":** `eval/run.sh` and `docker/tests/test-eval-set.sh` (Lane A's, Epic 9's; not contended). Before editing an existing file, re-check `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic11` (Epic 11 may touch either lane's files).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s1i`, the warm tag `e30s1iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll it in loops of under 170 s, and never start a second copy.

Where to run:
- Throwaway stacks only.
- Warm for the in-process classes (`Test.Bridge.*`, `Test.Eval.*`).
- Fresh for `Test.Agent.Compaction` and `Test.Agent.RequestSize`: they need the running production's Decide and ChatAgent, whose jobs keep old code on a warm stack.
- On `ocutalon-slot-b` (`server` `ocutalon-slot-b`, `namespace` `OCUTALON`; check `iris_server_info`, build 154), only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/bridge/cls` and `src/ocutalon/cls`).
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s1iw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s1iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Bridge.Compaction`
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Bridge.CodeRules`
  - `OcuTalon.Test.Bridge.Conversation`
  - `OcuTalon.Test.Bridge.Runner`
  - `OcuTalon.Test.Bridge.Usage`
  - `OcuTalon.Test.Bridge.Purge`
  - `OcuTalon.Test.Eval.ThinkingSmoke`
  - `OcuTalon.Test.Eval.Gate`
  - `OcuTalon.Test.Agent.Constants`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh class <Class>`, fresh, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Agent.Compaction`
  - `OcuTalon.Test.Agent.RequestSize`
- (once) `bash ci/checks.sh`. Expected: every script passes (boundaries, storage, class rules).
- (once) `bash docker/tests/test-mock.sh`. Expected: passes with the two new scenarios.
- (once) `bash docker/tests/test-eval-set.sh`. Expected: passes.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i bash eval/run.sh`. This is the push run, about 105 s. Expected: all checks passed, and the result says "not run".
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i env -u ANTHROPIC_API_KEY bash eval/key-proof.sh`. About 126 s. Expected: `eval/key-proof: all checks passed`.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh shard lane-a --part k/8` for k = 1 to 8, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`, fresh. Expected: passed (`Test.Contract.Ac` runs there).
- (once) `<lane> OCUTALON_RUN_TAG=e30s1iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh teardown`, also after a failure.

**Task 0 facts:** the implement stage records (a) to (d) here, each with the throwaway's build and what was stored.

**Shared surfaces:**
- **Decide's timer and precheck for a flagged turn that continues its conversation:** `Test.Bridge.Decide` (the precheck and timer tests) and `Test.Agent.RequestSize` `TestTooLarge`. Its history of about 8,000 characters is below `SEEDCHARS`, so its full estimate still applies (inference: check it).
- **The runner's linked path:** `Test.Bridge.Conversation` and `Test.Bridge.Runner` (`Compact` 0 by default: no change).
- **`SessionRotated` on a compaction:** the Decide carry tests (unchanged), and `Test.Eval.Run`'s rotation count (eval cases are `fresh`: no compaction).
- **Usage rows per item:** any test that counts one row for a flagged continuing turn (only the new tests).
- **`SESSIONCALLS` (+`forkandsummarize`) and the no-`Summarize` rule:** `Test.Bridge.CodeRules` itself.
- **`Eval.Gate.Result`'s context:** `Test.Eval.Gate`. **`eval/run.sh`'s release-candidate branch:** `docker/tests/test-eval-set.sh`.
- **Mock scenarios (+2):** `ci/mock/test/scenarios.test.mjs` (a required-name list, unchanged).
- **CI time:** the new classes run in `shards-2` (`lane-a@rest`, 30.9 minutes on the feature head). Record their times. If `shards-2` would pass 33 minutes, report it to the lead for a rebalance. Do not edit `ci/units.sh`.
- Every test added or changed passes on a fresh environment, in either order. Each one creates and removes its owners, links, sessions, Usage rows, settings rows and restarts, also after a failure.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| row 1, AC 1 | the adapter ignores `Compact` | Compaction row 1; Agent.Compaction AC 1 (no compaction row, turn 1's filler in the request) |
| row 1 | `k` + 1 (the cut keeps one more message) | Compaction row 1 (the request holds turn 1's last message) or row 11 |
| row 2 | compaction runs with nothing older | Compaction row 2 (a summarizer request logged) |
| rows 3, 5 | a throw of `ForkAndSummarize` propagates as the reply's failure | Compaction rows 3, 5 (a FailureText) |
| row 4 | a failed check still switches the link | Compaction row 4 (the link names the fork) |
| row 5 | `max_retries` 1 in `SummarizerSettings` | Compaction row 5 (two summarizer requests) |
| rows 6, 7 | the over-the-limit guards removed | Compaction rows 6, 7 (a request above the limit logged) |
| row 8 | compaction for a `fresh` turn | Compaction row 8 |
| row 9 | `Point` after `Chat` instead of before | Compaction row 9 (a thrown `Chat` leaves the old link) |
| row 10 | the adapter ignores `Compact` | Compaction row 10 (fourth request at 100,000 or more) |
| row 11 | `Check` passes a tool result first | Compaction row 11 |
| AC 2 | `Precheck` uses the full estimate | Agent.Compaction AC 2 (`too_large`); Bridge.Decide's bound case |
| AC 3, row 12 | `TimerFor` returns `TimerSeconds` | Bridge.Decide row 12; Agent.Compaction AC 3 |
| AC 1 | the `compaction` row is not saved | Compaction row 1; Agent.Compaction AC 1 |
| AC 4 | a product class calls `session.Summarize(` (scanner self-check) | CodeRules |
| AC 5 | `ZzSmokeAdapter` drops `block_binding` | ThinkingSmoke (the forcing field missing) |
| AC 5 | `Result` ignores the context value | Test.Eval.Gate |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (halted after planning, as dispatched).**
- The spec covers Story 30.1's three ACs (with the live smoke and the NFR-3 check), DW-125, DW-130 and DW-93.
- DW-386 and DW-448 are declined together for size, to the Epic 30 burn-down story; the lead re-owns them with U-184's and U-185's conditions.
- Items for the lead's spec gate:
  - **V1:** the over-the-limit guards added to AD-20's fallback triggers (an AD amendment within U7), with its spine line.
  - **R1:** the NFR-3 residual in the loop (a first request between 40,000 and the limit). It is for the owner, with options (a) to (c). It is also the frontmatter's `deferred` item: a decision, not routed work.
  - **DW-93:** the lead writes the trailer from Task 0 (d), by the 250 ms rule.
  - **Spine notes (Rule 20):** AD-20, AD-8, AD-6 and AD-22, as listed under Design Notes.
  - **CI time:** the new classes run in `shards-2` (30.9 minutes on the feature head). The implement stage records their times. A rebalance in `ci/units.sh`, if one is needed, is the lead's.
  - **Lane B needs:** none. If Task 0 (e) shows that the mock refuses the smoke's request shape, that becomes one.
- Files outside "Ours": `eval/run.sh` and `docker/tests/test-eval-set.sh` (Lane A's, from Epic 9; not contended). No contended file is planned.
- Planning used no IRIS instance and no throwaway stack. Nothing was committed.
