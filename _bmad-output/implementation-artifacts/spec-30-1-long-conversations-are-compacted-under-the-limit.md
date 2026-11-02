---
title: 'Long conversations are compacted under the limit'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '662af722025263d2fcb02291433064c43c306e95'
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
- `Bridge/Process/Decide.cls` -- (ours; lines as of `60eedf07`).
  - `MAXTIMER` (:107), `MAXREQUESTTOKENS` (:114), `COMPACTTOKENS` (:117), `TimerSeconds` (:171).
  - `OnRequest`'s precheck, send and timer (:274-281, `SetTimer` :281). `OnResponse`'s re-send delay with `RemainingMs` (:344-354, :349). `Resend` (:368-382: `RemainingMs` :373, `SetTimer` :381). `SentRequest` (:396-402, unchanged rule). `RemainingMs` (:406-411).
  - `Precheck` (:835-868): limit normalization (:853-860, to become the shared `RequestLimit`) and `tooLarge` (:866). `EstimateTokens` (:880-891): it adds the history at :888. It gains an Output with the history's characters.
  - The class doc on the estimate and the flag (:21-31) says "The runner ignores it until Story 30.1" (:30). Update it.
  - Read only for this story: the reply check of Stories 5.12 and 30.6 and DW-544 (`CheckReply` :607, `RefusalText` and its helpers :640-806, the invalid-reply warning in `Conclude` :1021, `Interpret`/`Judge` :1101-1194, class doc :52-54). The timer, the precheck bound and `RequestLimit` touch none of it.
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
- `Test/Bridge/Decide.cls` -- `TestCompactFlag` (:2097), `TestTimerFallback` (:2273), and the precheck tests (`TestPrecheckOrder` :1766, `TestResendTooLargeSendsNothing` :2430). No test asserts that the runner ignores the flag (the text is only in `Decide.cls` :30, `Msg/Request.cls` :53, `Eval/Gate.cls` :64 and `eval/run.sh` :84).
- `Test/Bridge/ReplyCheck.cls` -- the reply-check tests of 5.12, 30.6 and DW-544 (regression only). `Test/Agent/Decide.cls` -- the live timer and re-send tests on `decide` requests (`TestTimer`, about 105 s for the class; regression only: `TimerFor` keeps `TimerSeconds` for them).
- `Test/Agent/Constants.cls` (:55-73) -- `TestCompactionPrompt` pins the prompt.
- `Eval/Gate.cls` -- `SMOKE` "not run" (:64-65), `Result` sets `thinkingHistorySmoke` (:333), `Text` (:415). `Test/Eval/Gate.cls` pins it (:463, :524).
- `Test/Eval/KeyProof.cls` -- the sibling pattern: a `%UnitTest` class that is also the helper `eval/run.sh` calls (`Scan` :182, `Print` :231).
- `eval/run.sh` -- the header note (:83-84), modes (:121-134), `verdict_run` and its context `cx` (:339-354, :345), the release-candidate sequence (:656-740).
- `docker/tests/test-eval-set.sh` -- pins of `eval/run.sh` and the job (:1111-1119, :1453-1456).
- `Bridge/Budget.cls` -- `State` (:41-92), `UsageSpent` (:137-154, a scan by `RecordedAt`), `UnpricedModels` (:177-191). `Test/Bridge/Budget.cls` `AddRow` (:646). For DW-93.

## Tasks & Acceptance

**Execution:**
- [x] Task 0: `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzTask0.cls` (temporary; deleted before the finalize commit, or its useful parts moved into the new tests) -- measure first, with `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh class OcuTalon.Test.Bridge.ZzTask0` on a fresh throwaway on the mock (lane B's variables, never the slot). Record the facts in this spec's `## Verification`, "Task 0 facts".
  - (a) `GetContext()` after a text turn and after a tool-call turn (`chat.json`): the roles, how content, tool calls, tool results and their ids are keyed, and whether a system message is in the array.
  - (b) `ForkAndSummarize(provider, "", k, Prompt(), 0)` with `summary`: the fork's `GetContext()` (the summary and action-log messages, their role and place); that the last `k` messages are kept; that the original is unchanged. After `%Save` and release, `OpenSession(forkId)`'s next request carries `max_tokens` 8000 (mock log). The mock's summarizer request: system text, transcript form, `output_config`, and its size against `TranscriptChars`.
  - (c) `summary-off-schema` throws (`<%AICore>InternalError`). `summary-rate-limited` with the summarizer settings: one request, then a throw.
  - (d) DW-93: with 100,000 Usage rows (about 1,100 recorded today, the rest over 90 days; `AddUsage` or one SQL insert loop), the median of 5 calls of `Budget.State()` and of `Decide.Precheck` for a short turn. Then delete the rows.
  - (e) The mock answers a chat request that carries `thinking.block_binding` and the `anthropic-beta` header (the smoke's shape). If it refuses one, stop that part with `## Clarification Needed`: new mock behaviour is Lane B's (AD-22).
  - If (a)-(c) contradict this spec's rules, adapt only within them: every failure goes to the seeded path. If an off-schema reply does not throw and its fork passes `Check`, HALT `intent gap` naming AD-20 (S18's finding no longer holds).
- [x] `src/bridge/cls/OcuTalon/Bridge/Compaction.cls` -- add `SUMMARIZERSECONDS` 20, `SEEDTURNS` 20, `SEEDPART` 2000, `SEEDCHARS` 80000, `SEEDHEAD`, and these pure helpers -- the rules of rows 1-7 and 11:
  - `Cut(context, Output older) As %Integer` (`k`, 0 when nothing older);
  - `Check(context) As %Boolean`;
  - `Seed(context) As %String`;
  - `TranscriptChars(older) As %Integer` (the JSON length of the summarized messages);
  - `SummaryChars(context) As %Integer` (the fork's head system messages);
  - `SummarizerSettings(settings) As %DynamicObject` (a copy with the overrides).
- [x] `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- `FromEstimate(request, model, inputChars, outputChars, Output row) As %Status` beside `FromStats`. It reuses `StepBuffer.Tokens` and `Price.CostFor`. No storage change.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- these changes, and the docs (:21-31 and the methods), leaving the reply check (5.12, 30.6, DW-544) as it is:
  - `RequestLimit(text, Output warning)`, taken out of `Precheck` and used by the adapter too;
  - `EstimateTokens` gives the history's characters;
  - `Precheck` uses the post-compaction bound for a turn that will be flagged and continues a linked conversation;
  - `TimerFor(request, compact)`, used by `OnRequest`, `RemainingMs` and `Resend`.
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- the compaction step in `AnswerLinked` (one private method, for example `Compact`), with its warning and its usage row. Also:
  - `ChatInput` takes an optional seed that replaces `request.SeedText`;
  - `SessionRotated` is set to 1 when compaction moved the link;
  - a private `CutOf(context)` calls `Compaction.Cut`, so that the seam can override it;
  - the class doc is updated.
  - Rationale: AD-6, AD-20.
- [x] `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls` -- the `Compact` doc: the runner now compacts a flagged turn that continues its conversation. Doc only.
- [x] `ci/mock/scenarios/A/summary-rate-limited.json` (new: 429, `Retry-After` 1) and `ci/mock/scenarios/A/compaction-loop.json` (new: three `zz_result_text` steps of 40,000 characters, then text) -- rows 5 and 10.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Compaction.cls` (new) -- rows 1-11, one method each or grouped, on the mock with a shadow `ZzRunner`. It is self-contained: owners, links, sessions, Usage rows and settings rows are put back in `OnAfterOneTest`, also after a failure. `ZzCutAdapter.cls` and `ZzCutRunner.cls` (new, the `ZzThrow*` pattern): `CutOf` returns a cut that starts at a tool result.
- [x] `src/ocutalon/cls/OcuTalon/Test/Agent/Compaction.cls` (new, through the running production; the `RequestSize` pattern) -- AC 1 to AC 3 and row 12.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls` -- `TimerFor` (row 12's cases, `MAXTIMER` cap) and the precheck bound (with and without a link, history below and above `SEEDCHARS`, a `fresh` turn). Update any test doc that says the runner ignores the flag (none found at `60eedf07`).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `SESSIONCALLS` also flags `forkandsummarize`; a new test flags `.summarize(` in every non-test class (none allowed), with its scanner checks -- AC 4.
- [x] `src/ocutalon/cls/OcuTalon/Test/Eval/ThinkingSmoke.cls` (new; the `KeyProof` pattern), with `ZzSmokeAdapter`, `ZzSmokeRunner` and `ZzSmokeChat` (new; `OcuTalon.Agent.Chat` with `TOOLSETS` `OcuTalon.Tools.Reminders` only) -- AC 5. The class has:
  - `Run(Output problems) As %Boolean`;
  - `Print`, which writes `CHK|smoke|passed|failed` and problem counts, never reply text or settings;
  - `TestOnTheMock`.
- [x] `src/ocutalon/cls/OcuTalon/Eval/Gate.cls` -- `Result` takes `context.thinkingHistorySmoke` when it is set, else `SMOKE`, and documents the values passed, failed and not run. The verdict is unchanged. `src/ocutalon/cls/OcuTalon/Test/Eval/Gate.cls` -- a context value reaches the JSON and the Markdown line; none gives "not run".
- [x] `eval/run.sh` -- in `--release-candidate` without `--on-mock` only, once after the attempts: run `ThinkingSmoke.Print(ThinkingSmoke.Run(.p))` through `iris_script` and pass the value in `cx`. The push run and `--on-mock` keep "not run". Update the header note (:83-84). `docker/tests/test-eval-set.sh` -- pin that branch, that it is skipped for `--on-mock` and the push run, and the new note.
- [x] `_bmad-output/implementation-artifacts/spec-30-1-long-conversations-are-compacted-under-the-limit.md` `## Verification` "Task 0 facts" (d) -- DW-93, for the lead, from the measurement: at 250 ms or less (median `Precheck`), no code change, and the lead writes `wontfix-accepted` with the measurement and `reopen_if=a Precheck median above 250 ms on a field instance, or a Usage table above 100,000 rows`. Above 250 ms, the implement stage stops that part with `## Clarification Needed`: an index is a stored-data change plus Lane B's pin, and a cache changes when the cap engages.

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
- AC 6 (regression): Given this story's changes, when the existing tests run, then `Test.Agent.RequestSize`, `Test.Bridge.Conversation`, `Test.Bridge.Runner`, `Test.Bridge.Decide`, `Test.Bridge.ReplyCheck`, `Test.Agent.Decide`, `Test.Bridge.Usage`, `Test.Bridge.Purge` and `Test.Agent.Constants` pass unchanged in intent, and `bash eval/key-proof.sh` still passes.

## Spec Change Log

- 2026-11-02 (re-open, part 2 of U-207; lead spec gate): set back to `draft` for a re-plan. Reasons: (1) `Bridge/Process/Decide.cls` and its tests changed after this spec was planned (d4793d2d): Story 5.12 (3682d6b6, d103aec0), Story 30.6 (8937f0e0, 7d184ae3) and DW-544's fix-forward (3d0cabd3); every Decide.cls task, Code Map line and test reference must be re-checked against the current code (and against Story 5.7's Decide changes, already in the base). (2) DW-483 joined this story's ledger inbox (Decide's invalid-reply retry: measure first; veto item). (3) DW-386, DW-448 and DW-541 were re-owned to the burn-down story 30.7 at this gate (outside compaction's intent; this spec already declines DW-386/DW-448), so they leave this story's inbox.

## Review Triage Log

### 2026-11-02 — Review pass
- verdicts: 29 findings — high 0, medium 1, low 24, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1 / Edge 1 / Gap 1: after a compaction, `OnResponse` and `Resend` recompute the flag from the smaller history, so the re-send window counts from `TimerSeconds` (60 s) while the alarm of the first send was 80 s — conservative (never a re-send past the alarm), met only by a 429 or similar failure in the last 20 s of a compacted turn; the fix needs a new Decide context property (a stored-data change on a persistent class, excluded by the intent), so it is more than a direct correction. reopen_if: a compacted turn's re-send is refused with time left on the alarm in a recorded run. Named under residual risks.
  - `[low]` `[patch]` Blind 2 / Edge 5: `Check`/`CallIds` raise a subscript error on a tool_use block with no id or a tool_result block with no tool_use_id — fixed in `Compaction.Check` (empty ids are skipped on the call side and fail on the result side) and pinned by two new `TestCheckRules` cases.
  - `[low]` `[reject]` Blind 3: the thinking-history smoke checks little on the real model (the forcing shape is the spec's labelled inference, and the mock cannot tell the header apart) — Design Notes 9 and Task 0 (e) accept this; a failed or silent smoke is recorded, not a gate.
  - `[low]` `[reject]` Blind 4 / Edge 9: `TurnJob` start is unchecked and a timed-out job is not stopped before cleanup — a job that fails to start or hangs is not seen in everyday use, the smoke only records `failed`, and the guards add branches.
  - `[false]` `[reject]` Blind 5: a literal api_key would travel as a Job argument — AD-19 puts only an `@{env:...}` placeholder in a Config Store entry and `ConfigStore.Details` returns it as stored, so the argument holds the placeholder, never a key.
  - `[low]` `[reject]` Blind 6: `SummarizerProvider` copies AI Hub's provider setup and its branches are untested — the copy is justified in Design Notes (AI Hub's method is Internal and Private); the branch it takes in the product (ProviderConfig) is the one under test.
  - `[low]` `[patch]` Blind 7: test helpers `Summarizers` and `RequestTokens` are copied in `Test.Agent.Compaction` — it now calls the public ones of `Test.Bridge.Compaction` (design note 26). The inline variants in `ThinkingSmoke.CheckLog` (a different return shape) stay.
  - `[false]` `[reject]` Blind 8: Decide extends the alarm even when no summarizer call will happen — decided in-stage 4: Decide cannot see the history's turns, and the 20 s are slack at worst.
  - `[low]` `[reject]` Blind 9: `SUMMARIZECALLS` misses `$method` dispatch — theoretical; the scanner pins literal dotted calls like the sibling scans.
  - `[low]` `[reject]` Edge 2 / Edge 3 / Intent 4: when `GetContext` throws the turn runs on the history as it is (one warning) — a stored session whose history cannot be read cannot be chatted either, so the over-the-limit send is not reachable; recorded as design note 17.
  - `[low]` `[reject]` Edge 4: a seed after an already compacted history leaves out the earlier summary — row 11 defines the seed as the stored user and assistant texts only; two failed compactions in a row are rare and the newest 20 exchanges are kept.
  - `[low]` `[reject]` Edge 6: the seed drops leading assistant lines when it holds exactly 20 exchanges — a history starts with a user message (Check/Cut rely on it), so no leading assistant text exists.
  - `[low]` `[reject]` Edge 7: `Compaction.Seed` is outside the Try — it is pure over arrays of strings and raises nothing for any stored history.
  - `[low]` `[reject]` Edge 8: a re-send after a seeded fallback whose Chat failed attempts the compaction again, with another summarizer request — bounded by the re-send count, and the guarded path moves the link first, so only the seeded path repeats.
  - `[low]` `[reject]` Gap 2 (part): the untested fallback seams (fork save fails, `Point` fails, `GetContext` throws, provider error) — each ends on the same fallback line as the pinned ones; a seam for each adds classes for no new behaviour.
  - `[medium]` `[patch]` Gap 2 (reopen): the failed reopen after the fork was saved had no test — `ZzReopenAdapter`/`ZzReopenRunner` and `TestReopenFails` added, mutation red (design note 25).
  - `[low]` `[reject]` Gap 1: no test sends a reply-failure through `OnResponse` for a flagged continuing turn — pins the recompute of the first finding, which is rejected.
  - `[low]` `[reject]` Gap 3: `ThinkingSmoke.Print` is never run by a test — it is one `Write` of `Line`, which `TestPrint` pins; the shell side reads the line and records `failed` for a missing one.
  - `[low]` `[reject]` Gap 4: the `anthropic-beta` header assertion is vacuous on the mock — Task 0 (e) measured that the mock logs the header name for every request; the `block_binding` field carries the pin (its mutation is red).
  - `[low]` `[reject]` Gap 5: `TestUsageEstimate` could pass with an empty price on both sides — `TestGuardedCompaction` asserts a non-empty cost in the same class.
  - `[low]` `[patch]` Gap 6: no mutation line for AC 2's input clause and AC 4's `ForkAndSummarize` scan — both demonstrated red and recorded.
  - `[low]` `[reject]` Gap 7: the non-mock branch of the smoke is first executed on the real model — it cannot run here (no real key, ever); a failure is recorded as `failed`.
  - `[low]` `[reject]` Gap 8: hermeticity notes (a day-mark kill, deletes by mark, seeded price rows) — the same pattern as `Test.Agent.RequestSize`; no cross-test dependence found.
  - `[low]` `[reject]` Intent 2: the day's spend including the compaction row is not asserted — `Usage.Totals` is asserted, and the spend scan sums every Usage row by time.
  - `[false]` `[reject]` Intent 3: the runner and Decide read the limit at different times — the tests restart Decide after changing the row (the RequestSize pattern); the shared method normalizes both.
  - `[low]` `[reject]` Intent 1: the guarded path is not exercised through Decide's own flag in-process — `Test.Agent.Compaction` runs it through the production.
  - `[false]` `[reject]` Intent 5: row 12 asserted at `TimerFor` only — `OnRequest` and the running production's alarm (60, 80, 80) are asserted too.
  - `[low]` `[reject]` Edge 4b / Gap (assertion): `CheckLog` `HasThinkingBlock` is close to vacuous on the mock because mock replies carry no thinking block — recorded as inference in Design Notes 9; on the real model it is the check that bites.
  - `[low]` `[reject]` Gap 2 (`RecordCompaction` warning branches) — a warning-only path that never changes the compaction.

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
  - Epic 41's optional Stories 41.10 and 41.11 (AD-21 "At compaction") may later report a guarded compaction's summary through a HostSink event. That needs an AD-31 amendment decided at Epic 41's re-open; this story adds no hook for it.

**Extend, don't copy (Rule 2).**
- `Usage.FromEstimate` sits beside `FromStats` and shares `Price.CostFor` and `StepBuffer.Tokens`.
- `Decide.RequestLimit` is taken out of `Precheck`, so the adapter does not copy it.
- The seed copies the form of Lane B's `Conversation.Recap`. It is a copy because AD-2 forbids the bridge to name `Core`, AD-33 makes the class Lane B's, and the source differs: the stored history, not `Turn` rows.
- The summarizer's provider-name resolution mirrors AI Hub's `setupProviderFromSettings`, which is Internal and Private.
- The seams follow `ZzThrowAdapter`/`ZzThrowRunner`. The smoke follows `Test.Eval.KeyProof`.

**Decided in-stage.**
1. Redact and key-proof work stays out (the intent's Never line). The lead re-owned DW-386 and DW-448 (and DW-541) to Story 30.7 at the 2026-11-02 spec gate. This spec does no work for any of the three.
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
12. Re-plan against `60eedf07`: since `d4793d2d`, Decide changed only in its reply check (5.12's evidence-reference rule, 30.6's invalid-reply warning, DW-544's "an unexpected property"). `OnRequest`, `OnResponse`, `Resend`, `SentRequest`, `RemainingMs`, `Precheck` and `EstimateTokens` are unchanged, apart from line moves. So `TimerFor`, the precheck bound and `RequestLimit` compose with them as planned. A `too_large` or `daily_cap` precheck fallback still logs no reply-check warning. The `diagnose` timer (NFR-7) is unchanged, because `TimerFor` changes only flagged `turn`s. No other Code Map file changed, except `Test.Agent.Constants` (its tool-name count; the prompt test moved to :55-73).

13. (implement stage) The mock's log keeps the size of a request's system text and not the text, so "the summarizer request's system text starts `OCUTALON-COMPACTION-V1`" is pinned by the log line itself: `selectedBy` `summarizer` (or a `summary-*` scenario) and `system.chars` equal to `Length(Prompt())` (948), which the mock reads the prefix from. Likewise "turn 3's request starts with the summary" is pinned by the first message being turn 2's user message and the system text being 595 characters longer than before: the summary rides in the system text (Task 0 (b)).
14. (implement stage) `compaction-loop.json` asks for `zz_result_text` with 40,000, 39,990 and 39,980 characters, not three times 40,000: AI Hub's loop detection answers a repeated identical call with a user message of its own ("You appear to be repeating tool calls..."), which carries no mock marker, so the mock answers 500 on the fourth request. The three results are still about 10,000 tokens each, the cap of one step.
15. (implement stage) `Decide.TimerFor(request, compact)` is an instance method (it reads `TimerSeconds`). `Decide.Flagged(request, estimate)` is the rule that `SentRequest` already had (a turn above `COMPACTTOKENS`), moved into a method that `SentRequest`, `Precheck` and the timer share; the rule is unchanged. `RemainingMs(request, estimate)` takes the estimate that `Resend`'s precheck just worked out, or works it out when `OnResponse` weighs a re-send. After a compaction moved the link the history is short, so a re-send is no longer flagged and counts from `TimerSeconds`: its timer is never longer than the first one.
16. (implement stage) `Decide.EstimateTokens` gained two trailing Output arguments, `history` and `chars` (the history's characters and the whole sum), so that `Precheck` weighs the post-compaction bound without a second read; `RequestLimit(text, Output warning)` returns the warning text and `Precheck` logs it through `Redact.Text`, as before.
17. (implement stage) When the stored history cannot be read (`GetContext()` throws), the adapter logs one warning and runs the turn on the session as it is: no cut and no seed can be made without the history.
18. (implement stage) The seed's head line (`SEEDHEAD`) is "This conversation so far, as recorded (the user's messages and the assistant's replies, the oldest left out when it is long):", the lines start `User: ` and `Assistant: `, and a seed over `SEEDCHARS` loses its oldest lines (not whole exchanges) until it fits. The text is for the model, never shown to a person.
19. (implement stage) The provider of the summarizer gets a fixed warning text when it cannot be built ("the provider cannot be built from the settings of the runner"): the error of `Expand`, `%FromJSON` or `Create` may name the settings, which the spec forbids in a warning. A failed `ForkAndSummarize` keeps AI Hub's error text, cut and redacted by `StepBuffer.Part`.
20. (implement stage) The adapter now calls `ConversationLink.Point` in two places (`SaveLinked` and the switch to a fork); `Test.Bridge.CodeRules` pinned one and now pins two. `Test.Bridge.Conversation`'s `NewHost`, `NewTurn`, `Send` (now a class method) and `LinkOf` are public so that `Test.Bridge.Compaction` reuses them (Rule 2); its tests are unchanged.
21. (implement stage) `Gate.Result` takes the context's `thinkingHistorySmoke` only when it is `passed` or `failed` (anything else gives `not run`), so the result document never holds another value. `eval/run.sh` records a smoke that printed no figure as `failed` with a NOTE line, and a failed smoke changes neither the verdict nor the exit code. `Print` writes `CHK|smoke|passed|<problems>` or `CHK|smoke|failed|<problems>`, the number of problems being the second figure.
22. (implement stage) The smoke's classes `ZzSmokeAdapter`, `ZzSmokeRunner` and `ZzSmokeChat` are in the package `OcuTalon.Test.Eval` with `Test.Eval.ThinkingSmoke`. Each turn runs in a job started with `Job` from `Run` (the test classes are outside the runner-and-adapter rule `TestRunnerStartsNoJob`). The mock is detected by `RunnerFixture.GuardReason()` being empty (the CI override's environment); otherwise the run uses the Config Store entry of ChatAgent. Task 0 was measured on a warm throwaway, not a fresh one: the base image, build and mock are the same.
23. (implement stage) `Compaction.Check` also fails a history whose first non-system message is not a user message (a tool or assistant message), a result with no call id, and a result whose call is missing or comes later, so a tool result first fails twice; the first-message test is pinned by the assistant-first case.
24. (review patch) `Compaction.Check` returns 0 for a tool_use block with no id or a tool_result block with no tool_use_id, instead of raising a subscript error that the fallback would have caught and reported under the wrong step. The block forms are pinned in `TestCheckRules`.
25. (review patch) The reopen of a saved fork is pinned by a seam like `ZzCutAdapter`: `ZzReopenAdapter`/`ZzReopenRunner` refuse to open any AI session other than the one named in the process-private global `^||ZzReopenOnly`, and `TestReopenFails` (row 4's reopen case) asserts the seeded fallback, the warning step "opening the fork again", the original link until the Chat completes, and a fork that stays saved and unlinked. Failures of the fork's save, of `Point`, of `GetContext` and of `SummarizerProvider` take the same fallback line and have no seam of their own.
26. (review patch) `Test.Agent.Compaction` reuses `Test.Bridge.Compaction`'s `Summarizers` and `RequestTokens` instead of its own copies.

**V1. An addition to AD-20's fallback triggers (veto window: amending an AD, U7). For the lead.**
- AD-20 names two triggers: an exception from `ForkAndSummarize` and a failed check.
- This spec adds the over-the-limit guards, because NFR-3 and AD-8 say a request over the limit is never sent, and AD-20 is silent on these cases:
  - a summarizer request whose estimate passes the limit (a history of about 400,000 characters, DW-125);
  - a first request still over the limit (the fork or the as-is session);
  - a failed save or reopen of the fork.
- Recommendation: keep. Spine line (Rule 20, light path), in AD-20's Fallback bullet: "…or a summarizer request or first request that would pass the request-size limit, or a fork that cannot be saved and reopened…".

- **Lead ruling (spec gate 2026-11-02, U7 step 1: comply, no AD amendment).** Implement the three over-the-limit guards exactly as planned: each takes AD-20's seeded fallback. AD-20 is silent on these cases and does not limit the seed to its two named triggers; AD-8 and NFR-3 require that no request over the limit is sent. So the guards comply with both ADs as written, and the spine text is NOT changed in this story (AD-20 is cited by merged stories' specs, so under the unattended doctrine any change to its text is the owner's, through an attended `bmad-architecture` Update after the run). The proposed AD-20 sentence above and the spine notes below are recorded in the ledger for that Update. Reviewers: these guards are not an AD-20 violation.

**R1. NFR-3 residual (for the lead; the frontmatter's `deferred` item; not planned around).**
- AD-20's 94,000 bound needs a first request of at most 40,000 tokens. This spec guards at the limit. A fork whose kept turn was tool-heavy, a flagged turn with nothing older, or a large input can therefore start between 40,000 and the limit, and its loop can pass 100,000.
- Options:
  - (a) Refuse such a fork, or an as-is session above 40,000, in favour of the seed. That loses the kept turn's tool results and the user's last paste.
  - (b) Decide refuses a tool-capable turn whose non-history part is above about 46,000 (`too_large`).
  - (c) Accept, with `reopen_if`: the mock or a recorded run logs a request above 100,000.
- (a) and (b) change what the product does: they are for the owner. DW-130 is addressed for the compacted case (row 10).

**Declined and re-owned.**
- DW-386 and DW-448: re-owned to Story 30.7 (the lead, 2026-11-02), with U-184's and U-185's conditions. Notes for 30.7 on DW-448:
  - No OcuTalon class has a `%Stream.Global*` property.
  - `%AI.Agent.Session.ContextData` is a `%Stream.GlobalCharacter` with `COMPRESS` 1: zstd for a first block of 1,024 characters or more, flagged in the header node, not in the chunk.
  - User text sits in `$List` elements of `%String(MAXLEN="")` properties, and an element with any character above 255 is stored as 16-bit.
- Declined DW-483 (lead, spec gate 2026-11-02: accepted; the entry becomes `decision-pending` for the decision sheet, `note=human=`: the measurement needs host Decision rows and a real-key run): its kept condition (U-191) builds the retry only if `diagnose` still falls back on `invalid` in more than about 1 in 50 after 5.12, measured on host Decision rows and Story 9.5's real-key run. This run has neither: no real key, ever, and the demo host is off limits. The CI mock's invalid rate is whatever its scenarios script, so a Task 0 here would measure nothing. A retry is also a behaviour change in Decide's reply path, outside compaction. The lead re-owns it (for example to the first real-key release-candidate run's evidence) or closes it.
- Addressed: DW-93 by Task 0 (d) and the lead item, DW-125 by rows 6-7 and AC 2, DW-130 by rows 1 and 10 and AC 1, with R1.

**Spine notes for the lead (Rule 20).**
- Lead (spec gate 2026-11-02): none of these is written into the spine in this unattended run (U7, U14: a runner never amends an AD; AD-20, AD-8, AD-6 and AD-22 are cited by merged stories). They describe behaviour the ADs allow as written, and they go to the ledger for an attended spine Update after the run.
- AD-20: V1's text. The fork is reopened through `OpenSession` before `Chat`. A compaction sets `SessionRotated`. The seed's bound (`SEEDCHARS`, 80,000 characters). The 20 s go only to a flagged turn that continues a linked conversation.
- AD-8: `too_large` for such a turn is judged on the post-compaction bound.
- AD-6: the adapter bullet "`%Save`s an AI session only after a completed `Chat`" gains "or a compaction fork, after its check (AD-20)".
- AD-22: the smoke's home (`Test.Eval.ThinkingSmoke`, through `eval/run.sh --release-candidate` on the real model; "not run" in push and `--on-mock` runs).

**Files outside "Ours":** `eval/run.sh` and `docker/tests/test-eval-set.sh` (Lane A's, Epic 9's; not contended). Before editing an existing file, re-check `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic11` (Epic 11 may touch either lane's files).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s1i`, the warm tag `e30s1iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`; never in the background. Each command below finishes inside one call. Never two IRIS test runs in one message.

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
  - `OcuTalon.Test.Bridge.ReplyCheck`
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
  - `OcuTalon.Test.Agent.Decide` (about 105 s; the timer and re-send paths that `TimerFor` rewires)
- (once) `bash ci/checks.sh`. Expected: every script passes (boundaries, storage, class rules).
- (once) `bash docker/tests/test-mock.sh`. Expected: passes with the two new scenarios.
- (once) `bash docker/tests/test-eval-set.sh`. Expected: passes.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i bash eval/run.sh`. This is the push run, about 105 s. Expected: all checks passed, and the result says "not run".
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i env -u ANTHROPIC_API_KEY bash eval/key-proof.sh`. About 126 s. Expected: `eval/key-proof: all checks passed`.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh shard lane-a --part k/8` for k = 1 to 8, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`, fresh. Expected: passed (`Test.Contract.Ac` runs there).
- (once) `<lane> OCUTALON_RUN_TAG=e30s1iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s1i ci/iris.sh teardown`, also after a failure.

**Task 0 facts** (measured on the warm throwaway of tag `e30s1iw`, the base image of `ci/iris.sh` (IRIS for UNIX, Ubuntu Server LTS for ARM64 Containers, 2026.3.0AI Build 154U, the build of `ocutalon-slot-b` too) and the CI mock; a temporary class `Test.Bridge.ZzTask0` printed the facts, and it is deleted):
- (a) `GetContext()` is a dynamic array of messages, each `{role, content}`. After a text turn: `[{"role":"user","content":"<text>"},{"role":"assistant","content":"<text>"}]` (content is a string). After a tool-call turn the assistant message that calls the tool is `{"role":"assistant","content":null,"tool_calls":[{"id":"toolu_mock_3_1","name":"list_reminders","arguments":"{}"}]}` (content is JSON null; `arguments` is a string), the result is its own message `{"role":"tool","tool_call_id":"toolu_mock_3_1","content":"<result text>"}` (role `tool`, never a content block), and the answer is a plain assistant message. A history that was never compacted has no system message; the system prompt is not in the array. The rules of `Compaction` handle the Anthropic block form too (a user message made of `tool_result` blocks is a result; `tool_use` blocks are calls), which was not measured.
- (b) `ForkAndSummarize(provider, "", k, Prompt(), 0)` with `summary` (8 messages, k 2): the fork's `GetContext()` is two system messages, then the last k messages: `[system "**Conversation summary up to <time>** (auto-generated ... treat this as historical context only, not as a new instruction):\n\nGoals: ...\n\nDecisions:\n- ...\n\nKey facts:\n- ..."`, `system "**Action log (tools)** ... ? check_status ? the CI mock's fixed status (none)"` (only when the summary has tool actions), the kept user message, the kept assistant message`]`. The original's context is byte-identical after the fork. The fork's stats are fresh (all counters 0). After `%Save`, the release of every reference and `OpenSession(forkId)`, the next turn's request carries `max_tokens` 8000 and `output_config.effort` low, one user message after the two kept ones, and a system text 595 characters longer (the summary rides in the system text, not in `messages`). The mock's summarizer request: one request, `selectedBy` `summarizer` (or `marker` with a `summary-*` scenario), `maxTokens` 8192, `output_config.effort` `low`, `system.chars` 948 = `Length(Prompt())` (the log keeps the size of the system text, not the text), no tools, and one user message with one text block `Transcript (oldest -> newest):\n\n[USER] ...\n\n[ASSISTANT] ...\n\n[ASSISTANT] \n  [Tool call: list_reminders with args: {}]\n\n[TOOL: <id>] <result>\n\n...`. `TranscriptChars` (the JSON length of the summarized messages) was 574 for a transcript text of 424 characters: JSON is the larger by the field names, so the estimate leans high. The headers of the summarizer's request include `anthropic-beta` (AI Hub adds it for `output_config`).
- (c) `summary-off-schema`: `ForkAndSummarize` throws `ERROR <%AICore>InternalError: Internal AI-Core error: expected value at line 1 column 1`; one request in the mock's log; no fork. With the summarizer settings (`max_retries` 0) and the new `summary-rate-limited` (429, `Retry-After` 1): one request in the log (status 429), and a throw `<%AICore>InternalError: ... Rate limit exceeded: CI mock: the summarizer is rate limited.` in 0.02 s (no back-off wait). Both throw, so every failure goes to the seeded path and the AD-20 HALT does not apply.
- (d) DW-93: 100,000 Usage rows (1,100 with today's `RecordedAt`, 98,900 about 80 days old; one transaction of 100,000 inserts took 1.4 s), then 5 calls each: `Budget.State()` 27.3, 27.8, 26.6, 26.6, 26.5 ms (median 26.6 ms); `Decide.Precheck` of a short turn 28.3, 27.7, 28.3, 27.4, 27.6 ms (median 27.7 ms). The median `Precheck` is about 28 ms, far under the 250 ms threshold: no code change. For the lead: `wontfix-accepted` with this measurement and `reopen_if=a Precheck median above 250 ms on a field instance, or a Usage table above 100,000 rows`. The rows were deleted afterwards, and the table counted 0 rows.
- (e) The mock accepts a chat request with `thinking` `{"type":"adaptive","block_binding":{"prefix_mismatch_behavior":"error"}}` (from `extra_params.thinking` of the session config; AI Hub puts it at the top level of the request body, which the mock's log keeps in full) and a provider `anthropic-beta` header (`http_config.custom_headers`): status 200, the scenario's reply. The header name is in the log's `headerNames` of every request, with or without the custom header, so the header check cannot tell the forcing apart on the mock; the `thinking.block_binding` field can, and the smoke's mutation (the adapter drops it) is red.


**Shared surfaces:**
- **Decide's timer and precheck for a flagged turn that continues its conversation:** `Test.Bridge.Decide` (the precheck and timer tests), `Test.Agent.Decide` (`decide` requests: unchanged) and `Test.Agent.RequestSize` `TestTooLarge`. Its history of about 8,000 characters is below `SEEDCHARS`, so its full estimate still applies (inference: check it).
- **The runner's linked path:** `Test.Bridge.Conversation` and `Test.Bridge.Runner` (`Compact` 0 by default: no change).
- **`SessionRotated` on a compaction:** the Decide carry tests (unchanged), and `Test.Eval.Run`'s rotation count (eval cases are `fresh`: no compaction).
- **Usage rows per item:** any test that counts one row for a flagged continuing turn (only the new tests).
- **`SESSIONCALLS` (+`forkandsummarize`) and the no-`Summarize` rule:** `Test.Bridge.CodeRules` itself.
- **`Eval.Gate.Result`'s context:** `Test.Eval.Gate`. **`eval/run.sh`'s release-candidate branch:** `docker/tests/test-eval-set.sh`.
- **Mock scenarios (+2):** `ci/mock/test/scenarios.test.mjs` (a required-name list, unchanged).
- **CI time:** the new classes (`Test.Bridge.Compaction`, `Test.Agent.Compaction`, `Test.Eval.ThinkingSmoke`) run in `shards-2` (`lane-a@rest`), already 36.6 minutes on part 1's head `81f230eb`, where the CI trigger fired. Record each new class's time for the lead, who owns the split. Do not edit `ci/units.sh` or `docker/tests/test-ci-config.sh` (contended, Epic 11).
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

**Pinning mutations, recorded (implement stage; each applied from a backup of my own, the red observed on the class named, then restored byte-identically: the md5 of the file and `git diff --stat` were the same as before).**
- mutation: row 1 / row 10 / AC 1: `Adapter.Agent` `AnswerLinked` `request.Compact && 0` (the adapter ignores `Compact`) -> red in `Test.Bridge.Compaction` (`TestGuardedCompaction`: no summarizer request; `TestFourIterations`: the first request 77,876 tokens and the fourth 108,057; the seeded and switch rows), and in `Test.Agent.Compaction` (`TestGrowsIntoCompaction`: no summarizer request, two Usage rows missing, turn 1's filler in the request)
- mutation: row 1: `Compaction.Cut` returns `k` + 1 -> red in `Test.Bridge.Compaction` (`TestGuardedCompaction`: the cut keeps four messages, the request holds more; `TestCutRules`; `TestAfterTheSwitch`)
- mutation: row 2: `Compaction.Cut` no longer returns 0 when only system messages come before the last user turn (`If 0 Quit 0` for the nothing-older test) -> red in `Test.Bridge.Compaction` (`TestNothingOlder`: a compaction row and a moved link; `TestCutRules`)
- mutation: rows 3 and 5: a throw of `ForkAndSummarize` propagates (`Condense` and `Compact` rethrow instead of falling back) -> red in `Test.Bridge.Compaction` (`TestSummarizerOffSchema` and `TestSummarizerRateLimited`: the turn is answered with the AI Hub error status and no reply). With only `Compact`'s catch changed the class stays green, because `Condense` catches the throw first (the fallback has two layers)
- mutation: row 4: the fork check is skipped (`If 0 Quit` in place of `If '..ForkIsSafe(fork) Quit`) -> red in `Test.Bridge.Compaction` (`TestCheckFails`: the turn is not seeded and logs no warning)
- mutation: row 5: `max_retries` 1 in `SummarizerSettings` -> red in `Test.Bridge.Compaction` (`TestSummarizerRateLimited`: not exactly one summarizer request; `TestSettingsRules`)
- mutation: rows 6 and 7: the three over-the-limit guards removed (`If 0` for the as-is size, the summarizer's size and the first-request size) -> red in `Test.Bridge.Compaction` (`TestSummarizerOverLimit` and `TestHistoryOverLimit`: a summarizer request, no seed, a request above 41,000 tokens)
- mutation: row 8: a fresh turn opens the linked session (`AnswerLinked` reads the link whatever the mode) -> red in `Test.Bridge.Compaction` (`TestNotCompactable`: a fresh turn makes a summarizer request and a compaction row)
- mutation: row 9: `Point` only after `Chat` (the `Point` of `SwitchTo` removed) -> red in `Test.Bridge.Compaction` (`TestAfterTheSwitch`: the link still names the old session after a tainted, a failed and a thrown turn)
- mutation: row 11: `Check` skips the first-message test (`If 0 Return 0`) -> red in `Test.Bridge.Compaction` (`TestCheckRules`: an assistant message first passes). A tool result first still fails through the orphan rule, so the first-message rule is pinned by the assistant-first case
- mutation: AC 2: `Precheck` uses the full estimate (`If 0 && ...` before the post-compaction bound) -> red in `Test.Bridge.Decide` (`TestFlaggedBound`: a history of 170,000 characters is too_large) and in `Test.Agent.Compaction` (`TestHistoryOverTheLimit`: the short turn is a too_large fallback)
- mutation: AC 3 / row 12: `TimerFor` returns `TimerSeconds` -> red in `Test.Bridge.Decide` (`TestTimerFor`: 60, not 80, and 100, not 110; the OnRequest and re-send timers) and in `Test.Agent.Compaction` (`TestGrowsIntoCompaction`: the alarm of turns 2 and 3 is 60)
- mutation: AC 1: the `compaction` Usage row is not saved (the `%Save` of `RecordCompaction` removed) -> red in `Test.Bridge.Compaction` (`TestGuardedCompaction`: one row, not two) and in `Test.Agent.Compaction` (`TestGrowsIntoCompaction`: no compaction row, three Usage rows)
- mutation: AC 4: a line `session.Summarize(provider, 10)` in `Bridge.Compaction` -> red in `Test.Bridge.CodeRules` (`TestNoSummarizeInPlace`: a class calls Summarize on a session)
- mutation: AC 5: `ZzSmokeAdapter` sends `{"type":"adaptive"}` (drops `block_binding`) -> red in `Test.Eval.ThinkingSmoke` (`TestOnTheMock`: every chat request lacks `thinking.block_binding.prefix_mismatch_behavior` error)
- mutation: AC 5: `Gate.Result` ignores the context value (`Set smoke = ""`) -> red in `Test.Eval.Gate` (`TestSmokeInTheResult`: passed and failed do not reach the JSON or the Markdown line)
- mutation: row 4 (reopen): `SwitchTo` ignores the error of `OpenSession` (`If 0 Quit` in place of `If $$$ISERR(sc) Quit`) -> red in `Test.Bridge.Compaction` (`TestReopenFails`: the seeded turn makes no model request, and one session is saved, not two)
- mutation: AC 2 (the input alone passes the limit): `Precheck`'s bound drops the non-history part (`Tokens(0 + $Select(...))` in place of `Tokens(chars - history + $Select(...))`) -> red in `Test.Bridge.Decide` (`TestFlaggedBound`: a history of 60,000 characters with an input of 110,000, and 100,000 with 170,000, are not too_large)
- mutation: AC 4 (only the adapter calls `ForkAndSummarize`): a line `older.ForkAndSummarize(provider, "", 1, "", 0)` in `Bridge.Compaction` -> red in `Test.Bridge.CodeRules` (`TestSessionsOnlyThroughTheComposer`: a class but the adapter calls ForkAndSummarize)
- mutation (test-eval-set.sh, rc-flow, in the script's own variants): `bad-smoke-on-mock`, `bad-smoke-not-recorded`, `bad-smoke-failure-fails`, `bad-smoke-before-attempts` and `bad-smoke-in-push-run` are each flagged for their reason by `bash docker/tests/test-eval-set.sh`.

**Run times of the new and changed test classes** (on a fresh throwaway of tag `e30s1i` unless noted; the figure is the `CLASS ... passed <s>s` line, the start of the stack not counted; for the lead's CI repack):
- `Test.Bridge.Compaction` (new): 3.15 s (2 to 10 s on the warm throwaway)
- `Test.Agent.Compaction` (new): 9.20 s (the stack start took 121 s)
- `Test.Eval.ThinkingSmoke` (new): 1.72 s
- `Test.Bridge.Decide` (changed, three tests added): 8.69 s
- `Test.Agent.RequestSize` (regression): 13.46 s; `Test.Agent.Decide` (regression): 108.34 s
- warm throwaway (tag `e30s1iw`): `Test.Bridge.CodeRules` 2.75 s, `Test.Eval.Gate` 3.64 s, `Test.Bridge.Conversation` 7.27 s, `Test.Bridge.Runner` 15.54 s, `Test.Bridge.ReplyCheck` 0.16 s, `Test.Bridge.Usage` 0.10 s, `Test.Bridge.Purge` 0.19 s, `Test.Agent.Constants` 0.04 s
- after the review patches (fresh `e30s1i` unless noted): `Test.Agent.Compaction` 9.08 s; warm `Test.Bridge.Compaction` 4.08 s to 7.44 s (one test added), `Test.Bridge.Decide` 7.73 s.
- shards on the fresh throwaway (wall time with the stack start): lane-a parts 1 to 8: 452 s, 163 s, 155 s, 174 s, 395 s, 448 s, 296 s, 358 s; lane-b part 1/2: 292 s. Lane-b part 2/2 failed twice (544 s, 546 s) on `Test.Web.GuideApi` `TestRunAgain` alone ("steps 3 to 5 reset; the watch still counts"), and the class passes by itself on a fresh throwaway (0.97 s). This is DW-453, a known flake in Lane B's web class that this story does not touch (its `reopen_if` in the ledger is met by these two runs, for the lead). No class of this story is in lane-b.
- the three new classes run in `shards-2` (`lane-a@rest`) in about 14 s of test time together; the stack start is the shard's once. `eval/key-proof.sh`: passed (the `--release-candidate --on-mock --key-path` rehearsal runs the new `eval/run.sh`).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The runner compacts a flagged turn that continues its conversation (`Adapter.Agent.Compact`, in `AnswerLinked` before `Converse`): the older messages are summarized with `ForkAndSummarize` (low-effort summarizer, no retries), the link moves to the fork only after `Compaction.Check`, the save and the reopen, and any failure or over-the-limit request falls back to a fresh session with a code-written seed. Decide gives such a turn 20 more seconds (`TimerFor`) and judges `too_large` on the post-compaction bound (`Precheck`, `RequestLimit`). A `compaction` Usage row prices the summarizer's request. The thinking-history smoke test runs in `eval/run.sh --release-candidate` on the real model only and its figure reaches `Gate.Result`.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: the compaction step and its pieces; `ChatInput` takes a seed; `CutOf` seam.
- `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`: constants and the pure helpers `Cut`, `Check`, `Seed`, `TranscriptChars`, `SummaryChars`, `SummarizerSettings`.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`: `FromEstimate`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `RequestLimit`, `Flagged`, `TimerFor`, `RemainingMs`, `EstimateTokens` outputs, the `Precheck` bound.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`: `Compact` doc.
- `src/ocutalon/cls/OcuTalon/Eval/Gate.cls`, `eval/run.sh`, `docker/tests/test-eval-set.sh`: the smoke figure and its pins.
- `ci/mock/scenarios/A/summary-rate-limited.json`, `compaction-loop.json`: two new mock scenarios.
- Tests: new `Test.Bridge.Compaction`, `Test.Agent.Compaction`, `Test.Eval.ThinkingSmoke` and the seams `ZzCutAdapter/Runner`, `ZzReopenAdapter/Runner`, `ZzSmokeAdapter/Runner/Chat`; changed `Test.Bridge.Decide`, `CodeRules`, `Conversation` (helpers made public), `Test.Eval.Gate`.

**Review.** 29 findings: patches applied 4 (1 medium: the failed-reopen test and seam; 3 low: `Check` with an empty id, the shared test helpers, the two missing mutation lines), items deferred 0 (the frontmatter's R1 item stands), rejected 25 with their reasons in the triage log (4 false, 21 low). Follow-up review recommended: false (no high patched, one medium patched).

**Verification.** Warm and fresh classes of `## Verification` all passed after the patches (`Test.Bridge.Compaction/Decide/ReplyCheck/CodeRules/Conversation/Runner/Usage/Purge`, `Test.Eval.ThinkingSmoke/Gate`, `Test.Agent.Constants`, fresh `Test.Agent.Compaction/RequestSize/Decide`). Once-lines: `bash ci/checks.sh` passed, `test-mock.sh` (118 pass, 0 fail) and `test-eval-set.sh` passed, the push run `eval/run.sh` passed, `eval/key-proof.sh` passed, lane-a parts 1 to 8 passed, lane-b part 1/2 passed. Lane-b part 2/2 failed twice on `Test.Web.GuideApi` `TestRunAgain` (DW-453, Lane B's web class, untouched here; it passes alone on a fresh throwaway; none of this story's classes are in lane-b): the lead decides whether DW-453's `reopen_if` is met. Task 0 measured DW-93 at about 28 ms median `Precheck` at 100,000 Usage rows, under the 250 ms threshold.

**Residual risks.**
- Re-send window after a compaction: the flag is recomputed from the smaller history, so a re-send counts from `TimerSeconds` and not from the 80 s alarm (conservative; fix needs a stored Decide property, a veto-window item).
- R1 (the NFR-3 residual) and V1 (AD-20 fallback triggers) stand as the spec records them; no spine change was made.
- The real-model smoke is untried on a real provider (no key); the forcing shape is labelled inference.
- `compaction-loop` uses 40,000, 39,990 and 39,980 characters because identical repeated tool calls trigger AI Hub's loop nudge, which the mock does not answer.
