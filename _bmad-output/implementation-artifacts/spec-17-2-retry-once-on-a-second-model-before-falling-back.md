---
title: 'Story 17.2: Retry once on a second model before falling back'
type: 'feature'
created: '2026-11-05'
status: 'done'
baseline_revision: 'c98795049c26ea7a8a33fdf7d3da3eace97b43ea'
baseline_commit: 'c98795049c26ea7a8a33fdf7d3da3eace97b43ea'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      ToolsReadOnly judges only the compiled TOOLSETS of an agent, so MCP servers attached at step 4 (AD-21) are invisible to the R2 rule for a timed-out decide or diagnose.
    evidence: |-
      Decide.ToolsReadOnly reads the TOOLSETS parameter and the tool classes' CLASSIFICATION and READONLY parameters; tools that an MCP server adds at run time are known only to a live tool manager (RequestSize notes the same limit). No agent has an MCP server in this release, so nothing is wrong today; once Epic 22/35 attaches servers to Triage or Diagnosis, a timed-out attempt could be retried after a state-changing MCP tool ran.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls ToolsReadOnly
    severity: medium

---

<intent-contract>

## Intent

**Problem:** Today, when the one runner of an agent returns an unusable reply, `Decide` falls back at once. One model's refusal, cut-off, error or timeout then turns a decision, diagnosis or chat reply into a fallback, even though a second model could have answered. Story 33.1 fixed the contract in the spine (AD-6, AD-8, Conventions "Retried turns") and added three disabled retry runner items that have no agent class.

**Approach:** Bring the retry runners to life. Each one gets its agent class, its own Config Store entry and a timeout derivation. A first runner's host setting `RetryItem` turns the retry on. When `RetryItem` is set and the first attempt ends with a retried reason, `Decide` sends the same request once to the retry runner, under the same `DecisionRef`. The retry gets the AD-8 timer split, and `RetryOf` names the first runner. A retried user turn runs in a seeded session that the retry runner never links, and it takes no conversation lock. A compare-and-set `ConversationLink.Point` keeps the conversation the user saw.

## Boundaries & Constraints

**Always:**
- **Which reasons are retried.**
  - Retried exactly once: `timeout`, `rate_limited`, `error`, `refusal`, `cut_off`, `empty`, `invalid`, `unusable` and `no_key`. For `no_key`, the retry runner's own key is checked before sending.
  - Never retried: `daily_cap`, `budget`, `too_large`, a reply with `ToolsRun` 1, a `Broken` (`SessionBroken`) turn, and any request of kind `tool`.
  - Never retried: a retry attempt. Retrying happens once only.
- **The timers (AD-8).** T1 is `TimerFor(request, flagged)` of the first attempt. The retry waits T2 = min(`TimerSeconds`, `MAXTIMER` - T1). It is sent only when T2 >= `MINTIMER`. So the whole decision stays at or under 110 s.
- **The retry request.** It is a clone of the request, with the same `DecisionRef` and `ItemId` and with `RetryOf` set to the first runner item. Once it is sent, `Decide` takes only its reply.
- **One decision.**
  - One `Decision` row, and one answer to the caller.
  - Its totals are the sums of both attempts' `Usage` rows. Its steps continue across both attempts.
  - Its `Model` is the `Model` of the reply that answered.
  - A fallback carries the last attempt's reason. The reasons say so when the retry was skipped because no time was left.
- **The retry runner's session config.** It comes from its own model's family (`Adapter.Agent.Compose`), with no sampling parameters and a cap of 8,000 tokens in that family's key.
- **The retry runner's `timeout_ms`.** Its `timeout_ms` and its entry's `http_config` come from `Timeouts.Derive(Timeouts.RetryTimer(TimerSeconds))`.
- **Where a client's `RetryOf` goes.** A `RetryOf` that a client sets is never honoured:
  - `OnRequest`'s `Held` probe ignores it.
  - `SentRequest` clears it on every first send and on every re-send.
- **A retried linked turn** (kind `turn`, provenance `user`, `RetryOf` set):
  - It takes no conversation lock.
  - It chats in a new AI session. For a continue turn, the session is seeded with `Compaction.Seed` of the stored history of the session that `(OwnerRef, RetryOf)`'s link names. That history is read from the database, without the lock. A `fresh` turn is seeded with `SeedText` instead.
  - After a completed, untainted `Chat`, it saves that session and points `(OwnerRef, RetryOf)`'s link at it unconditionally. The reply then has `SessionRotated` 1.
- **`ConversationLink.Point` is a compare-and-set** for every non-retry writer (`SaveLinked`, `SwitchTo`).
  - It runs under the link row's own lock, never `^OcuTalonBP.Conv`.
  - It moves the link only while the link still names the session that runner opened, or the id the runner read for a fresh turn or no link.
- **Lane and storage rules.**
  - Only `Decide`, `Bridge.Msg.Request`, `AgentRunner`, `Adapter.Agent`, `ConversationLink` and the Test package name `RetryOf`. `Test.Bridge.CodeRules` stays green.
  - Storage is append-only (AD-5). Commit the compiler's `Storage` blocks for `Request` and `Decide`.
  - The bridge names no OcuTalon package (AD-2).
  - Source is ASCII, with comments that state the contract (Rule 14).
- **Tests** use the CI mock only (`ci/mock/scenarios/A/**`, `POST /_mock/countdown`, `OCUTALON_MOCK_KEY_HEADER=1`), on the shipped Anthropic provider path, in throwaway stacks.

**Never:**
- DW-483's same-model retry, or any retry that carries the check's error text.
- A second retry, or `Decide` re-sending the retry attempt after `rate_limited`.
- A retry after a precheck refusal (`daily_cap`, `budget` or `too_large`), after a gateway 403, or after a tool ran.
- A cap on `TimerSeconds` (it keeps 12..110).
- A `RetryItem` set at install. No second model is configured by default, so release 1's behaviour is unchanged.
- Building `Bridge.Settings` `SetModel`, `CheckModel` or `Values` (Stories 17.3 and 17.4).
- Provider resolution (Story 17.3).
- A real provider, a real key, or `api.telegram.org`.
- Any destructive run on `ocutalon-slot-a`.
- Edits to a contended path: `Bridge/Msg/Enum.cls`, `Bridge/Ext/**`, `Test/Agent/{Constants,Persona*}.cls`, `ci/units.sh`, `src/short-names.tsv`, the spine.
- Edits to any Lane B class or test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Retry answers | `TriageAgent.RetryItem`=`TriageAgentRetry`, retry `Model` `claude-sonnet-5-5`; decide with `retry-refusal` armed 1 | One request each to `TriageAgent` and `TriageAgentRetry`, same `DecisionRef`, the retry with `RetryOf`=`TriageAgent`. A usable `DecisionResponse`. The row: `Model` `claude-sonnet-5-5`, tokens and cost the sum of 2 `Usage` rows, `AgentStepCount` the sum | none |
| Retry fails | `retry-refusal-then-error` armed 0 (unarmed: `refusal` then `error`) | Fallback `tellnow`, `FallbackReason` `error` (the retry's), exactly one row and one answer, no tool/fix/approval | fallback |
| No second model | `RetryItem` empty (install default) | Exactly release 1: one runner request, fallback with the first reason | fallback |
| Never retried | `DecisionTokenBudget` 1; daily cap reached; `RequestTokenLimit` 1; `daily-cap` 403; reply `ToolsRun` 1; user turn `Invalid input` (Broken) | Fallback at once with that reason (`SessionBroken` 1 for Broken); no request to the retry runner | fallback |
| no_key | First runner's key absent, the retry's present / both absent | Retry sent and answers / fallback `no_key`, nothing sent | fallback |
| Timeout | T=12 (Decide row), `retry-held` armed 1 (first reply delayed 20 s) | Timer fires at ~12 s, retry with T2=min(12,98)=12 answers at ~12-14 s; the first runner's late `Usage` row still lands under the `DecisionRef` | none |
| Rate limited | T=12, `retry-overloaded-late` armed 1 (529 after 10.5 s, then answer) | No re-send fits, so `rate_limited`, then the retry answers; with `overloaded` (all 529) it falls back `rate_limited` after one retry request, not re-sent | fallback |
| No time left (DW-647) | `TimerSeconds` 100 | T2=10<12: no retry; fallback with the first reason, `Reasons` = `RETRYSKIPPED`; the retry entries get `Derive(12)` (`RetryTimer` clamps to `MINTIMER`) | fallback |
| Retried continue turn | User turn, link names S1, first attempt times out while still holding the lock | Retry runs unlocked in new session S2 seeded from S1; link -> S2, `SessionRotated` 1; the late first attempt saves S1' but its CAS `Point` fails; the next turn opens S2 and carries the seed and the retried exchange | none |
| Retried fresh turn | `SessionMode` fresh with `SeedText` | S2 seeded with `SeedText`; link -> S2 | none |
| Client `RetryOf` (DW-650 c) | `POST /api/v1/messages` body with `retryOf`/`RetryOf` while another job holds `(session, ChatAgent)`; also a `Request` with `RetryOf` sent straight to `Decide` | `Decide` answers `Busy` (the turn waits); the request reaching `ChatAgent` has `RetryOf` "" | Busy, never an error |
| Wrong `RetryOf` (DW-650 d) | `Held` for `RetryOf`=`TriageAgent` on runner `ChatAgent`, or another `ItemId`; a runner given a `RetryOf` whose `RetryItem` does not name it | `Held` probes and waits; the runner answers an error status and sends nothing | error status |
| Bad `RetryItem` | Names a missing, disabled or non-`AgentRunner` item, or the first runner itself | One warning naming the setting; no retry; release 1 fallback | warning |
| Mock key header | `OCUTALON_MOCK_KEY_HEADER=1` at install | Each `AI.LLM.OcuTalon<Agent>Retry` has `custom_headers.x-ocutalon-mockkey` = the agent's `MOCKKEY`; without the flag, none | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`. Key anchors:
  - `OnRequest` (:253): `Held` at :271, `Precheck` at :282, the send and `SetTimer` at :286-288.
  - `Held` (:295), `OnResponse` (:327, with the timer key :331 and the re-send :353-361), `Resend` (:375), `SentRequest` (:403), `TimerFor` (:422), `RemainingMs` (:434), `ResendDelay` (:449).
  - `Precheck` (:868), `EstimateTokens` (:928), `Classify` (:962), `Broken` (:996), `Conclude` (:1036; it calls `RecordFallback` at :1072), `RecordFallback` (:1246; its `reasons` argument is the `HELDBEFOREUPDATE` precedent), `NewRow` (:1283; it sets `Model` from `Usage.Totals`).
  - Parameters `RUNNERS` (:111), `MAXTIMER`/`MINTIMER` (:114/:117). The stored state `DecisionRef`/`Resends`/`StepCount`/`StepsSent` is at :221-231, and the `Storage` block at :1406.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`. `SETTINGS "ReplyClass:Basic"`, and `ResolveModel` (:47, which falls back to the agent's `MODEL`).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`. Anchors:
  - `Answer` (:316), `IsLinked` (:353), `AnswerLinked` (:373: lock :378, `SessionOf` :385, save :403).
  - `Converse` (:426), `SaveLinked` (:472, `Point` :476), `Compact` (:495; seed fallback :536), `SwitchTo` (:615, `Point` :628).
  - `SessionConfigFor`/`TimeoutMs` (:242/:252), `NewSession` (:260), `OpenSession` (:280), `ChatInput` (:723, which takes a `seed` argument).
- `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`. `Point` (unconditional today), plus `Lock`/`Unlock`/`SessionOf`.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`. Gets the new `RetryOf` property, at storage slot 15.
- `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`. `Seed(context As %DynamicArray)` (:137) and `#SEEDCHARS`.
- `src/bridge/cls/OcuTalon/Bridge/RequestSize.cls`. `HistoryChars` (:68) reads `%AI_Agent.Session.ContextData` without opening the session. It is the sibling for reading the stored context.
- `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`. `Check` (:29), `Derive` (:42; `{}` below 12), `Apply` (:76), `Entries` (:120, which iterates only `Decide.#RUNNERS`), `Restart` (:152).
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls`. `Absent(agent)` (:61) is keyed by item, so it works for the retry items unchanged.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`. `Totals` (:178): the sums, and `model` from the newest row by ID.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls`. `ValueFor(setting, production, item, .sc, target)` reads `RetryItem` (Host).
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`.
  - `Apply` (:62-77) loops `WriteRunner` with one `timer`.
  - `Details(agentClass, baseUrl, caFile, mockKeyFlag, timer)` (:98) holds the mock header (:103-107) and the timeouts (:111-115).
  - `EntryName(agentClass)` (:137) has no item, so a retry item would collide with `OcuTalon<Agent>`.
  - `WriteRunner` (:144-163) writes `ProviderConfig` `@{config:<name>}`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` (read only). `Runners`, `SeedModels`/`SeedEfforts`/`SeedAllowList` and `UnresolvedRunners` already handle enabled retry items: they seed a `Model` row from the agent's `MODEL`.
- `src/ocutalon/cls/OcuTalon/Production.cls`. The retry items are at :37-45: disabled, with an empty `AgentClass`. The first runners are at :26-36.
- Tests and mock:
  - `Test/Bridge/Decide.cls`: in process, with the `ZzDecide` recorder. Siblings: `TestResendWiring` :2611, `TestResendBoundary` :2694, `TestPrecheckOrder` :1770, `TestBusyRelayed` :2876, and the lock holder `StartHolder`/`StopHolder`/`Hold` :3255-3292.
  - `Test/Bridge/Conversation.cls`: shadow runners through the real `AgentRunner.OnMessage` and the mock. The mock's log shows the messages of each request. Siblings: `TestFirstAndNextTurn` :106, `TestFresh` :329, `TestLockHeldFromOpenToSave` :660, `LockFree` :931. The `Zz*Runner` subclasses override adapter methods.
  - `Test/Bridge/Timeouts.cls`: `TestDerive` :65, `TestApplyDefinedTimer` :205.
  - `Test/Install/Provider.cls`: `TestEntries` :215-259 asserts the retry items have no entry. It must be rewritten.
  - `Test/Install/Production.cls`: oracle rows :657-662, and the doc line :13.
  - `Test/Bridge/CodeRules.cls`: `RETRYOFCLASSES` :145 and `TestOnlyTheRetryPathNamesRetryOf` :356. Its doc says "RetryOf does not exist yet".
  - `Test/Bridge/SettingsStubs.cls`: `TestNothingWritten` asserts zero `RetryItem` System Default rows environment-wide, and snapshots the six entries before and after. So tests must delete their `RetryItem` rows.
  - Live siblings to reuse (not copy):
    - `Test/Agent/Decide.cls`: `TestReplyFallbacks` :490, `TestTimer` :571, `TestRateLimitedResent` :735, `TestPrechecks` :1278, `Prepare` :1460, `Case` :1486, `Arm` :1600, `Put` :1623.
    - `Test/Agent/RunnerFixture.cls`: `RUNNERS` :71, `NewRequest` :330, `Run` :432, `Headers` :377, `PutDefault` :736, `Restart` :115, `FallbackProblems` :877, `FindRequests` :1025, `PointKeys`/`RestoreKeys`/`SetKeys` :510-560.
    - `Test/Contract/Mock.cls`: `Arm` :439, `LogMark`/`LogSince`.
    - `Test/Checks/Turns.cls`: WebChatIn to the real `Conversation`, through `Test.Watch.Case`.
    - `Test/Web/BreakFeedApi.cls` `Post` :147, with `Test.Web.StubRequest.MakeBody` and `Test.Web.Api.Written`. This is the in-process REST call pattern.
  - `ci/mock/mock.mjs`:
    - A marker beats the mock key.
    - The countdown keys on the full marker label. Armed n>0 gives `replies[0]`; after that a request gets `replies[min(1+k,last)]`.
    - A one-reply scenario fails every time.
    - The log records `model`.
  - Existing one-reply scenarios: `refusal`, `max-tokens`, `empty`, `provider-error`, `decide-late` (18 s), `overloaded` (529 first) and `daily-cap`. The format rules are in `scenarios.mjs` `checkScenario`.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (measure, slot A read-only or a warm throwaway): run one linked turn through a shadow runner (the `Test.Bridge.Conversation` pattern) and read the saved session's `ContextData` stream. Record in `## Design Notes` whether it parses to the same message array `GetContext()` returns, which `Compaction.Seed` needs. Also confirm that the mock answers `GET /v1/models/claude-sonnet-5-5`. Record the timing of `retry-overloaded-late` on the developer machine.
- [x] `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`: add `Property RetryOf As %String(MAXLEN = 128)`, the first runner item of a retried attempt. Its doc says that only `Decide` sets it, and that it is cleared on every first send and re-send. Append the storage slot.
- [x] `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: add the host setting `RetryItem` (`SETTINGS` `RetryItem:Basic`). Its doc says that it names this runner's retry item, that empty means no second model, and that a retry runner's own `RetryItem` is never followed.
- [x] `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`:
  - add `RetryTimer(timer)` = max(`MINTIMER`, min(timer, `MAXTIMER` - timer)) for a timer that `Check` accepts, else "";
  - `Entries` also returns, for each first runner of `Decide.#RUNNERS`, the item `<runner>Retry` when it exists in the production with an entry. This is the same name rule as the Provider step's, and it does not depend on `RetryItem`.
  - `Apply` merges `Derive(RetryTimer(timer)).http_config` into those retry entries and `Derive(timer).http_config` into the first runners' entries, and restarts the retry items that have jobs together with the rest. Cites DW-647.
- [x] `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`: `Point(ownerRef, agent, sessionId, expected)`.
  - When `expected` is passed (`$Data`), the link moves only if `SessionOf` still equals `expected` ("" for no link), under the row's own lock, never `^OcuTalonBP.Conv`.
  - The `Output moved` argument says whether it moved.
  - With no `expected`, it moves unconditionally (the retry's point).
  - Doc: the retry's `Point` and the CAS rule.
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - (a) `SaveLinked` and `SwitchTo` pass `expected`: the id opened or read at the start of `AnswerLinked`, and the fork's id after `SwitchTo`.
  - (b) `Answer`: for a request with `RetryOf` set, first check `RetryAllowed(retryOf)`. It is a method that `Zz` runners can override: the item `retryOf`'s `RetryItem` setting (Accessor `ValueFor`, Host) equals this item's config name. Otherwise return an error status naming `RetryOf`, with no Chat.
  - (c) A linked turn with `RetryOf` goes to a new `AnswerRetried`:
    - no lock;
    - the seed is `SeedText` when `fresh`, else `Compaction.Seed` of the stored context of `SessionOf(OwnerRef, RetryOf)`, read per Task 0 with no lock and no save;
    - `NewSession`, then `Converse` with `ChatInput(request, 1, seed)`;
    - after a completed, untainted `Chat`: `%Save`, `Point(OwnerRef, RetryOf, id)` with no expected value, and `SessionRotated` 1;
    - it ignores `Compact`.
  - (d) The session config of a request with `RetryOf` takes `timeout_ms` from `Derive(Timeouts.RetryTimer(TimerSeconds))`.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`. Add the stored properties `RetryRunner` (the retry item sent to, "" until sent) and `FirstSeconds` (T1), with their storage. Then add:
  - `RetryItemOf(runner, kind)`: reads `RetryItem` through Accessor. It gives one warning and "" when the value names:
    - a missing, disabled or non-`AgentRunner` item;
    - the runner itself;
    - for decide or diagnose, an item whose `ReplyClass` fails `CheckSettings`.
  - `Retryable(reason, toolsRun, broken)`: pure, per Always.
  - `RetrySeconds(t1, timer)`: pure, gives T2 or 0 when T2 < `MINTIMER`.
  - Parameter `RETRYSKIPPED`, the reasons line of a skipped retry (see Design Notes).
  - `Held(request, runner, itemId = "")` returns 0 without probing only when `RetryOf` = `runner` and `ItemId` = `itemId` (non-empty). `OnRequest` passes no `itemId`.
  - `SentRequest` sets `RetryOf` "" on every send. A new `RetryRequest` builds the retry clone with `RetryOf` = the first runner.
  - The retry path `Retry(request, reason, reply, .response)`:
    - when no retry item, or `Retryable` fails, or the retry was already sent: `RecordFallback` as today;
    - T2 = 0: `RecordFallback` with `RETRYSKIPPED`;
    - otherwise: `Held(clone, runner, ItemId)` for a linked turn, then `Precheck(clone, retryRunner)` (a reason means `RecordFallback`), then the send with key `reply`, then `SetTimer(T2, "timer")`.
  - `StepCount` gains the failed reply's `AgentStepCount`.
  - Call the retry path from the `OnRequest` precheck (`no_key` only), the timer key (when `RetryRunner` = ""), `Resend`'s `rate_limited` with no time left, and `Conclude`. `Conclude` gets an optional `retry` input. When it is 1 and the reason is retryable, it records nothing and returns the reason. For the retry's reply, `ResendDelay` is never consulted.
  - `ReplyClassOf` reads the runner that answered.
  - `EstimateTokens` counts a continue turn with `RetryOf` as min(`HistoryChars(SessionOf(OwnerRef, RetryOf))`, `SEEDCHARS`) plus the input.
  - `NewRow`/`Conclude` set `Model` from the answering `Reply.Model` when it is not empty.
  - Update the class doc.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:
  - `EntryName(agentClass, item = "")` adds `Retry` for an item whose name ends in `Retry`;
  - `WriteRunner` passes the item;
  - `Details` gets `RetryTimer(timer)` for a retry item;
  - the mock-key header comes from the same `Details`, unchanged. Each entry is still written before its `ProviderConfig` row.
- [x] `src/ocutalon/cls/OcuTalon/Production.cls`: enable the three retry items with `AgentClass` (`OcuTalon.Agent.Triage`/`Diagnosis`/`Chat`), and `ReplyClass` for Triage and Diagnosis (as on their first runners). No `RetryItem` anywhere.
- [x] `ci/mock/scenarios/A/`: add new scenarios, each `{name, match:{marker}, replies}` with `name` equal to the file name.
  - Two replies, the second valid: `retry-refusal`, `retry-max-tokens`, `retry-empty`, `retry-provider-error`, `retry-held` (a valid decide reply after 20 s).
  - `retry-overloaded-late` (529 after 10.5 s, then a valid decide reply).
  - `retry-refusal-then-error`.
  - `retry-diagnosis` (500, then a valid diagnosis payload shaped like `diagnosis.json`'s).
  - `retry-chat` (refusal, then text) and `retry-chat-held` (text after 20 s, then text).
  - The decide replies are copied in shape from `decide-ignore.json`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`, in process: add tests for `Retryable` and `RetrySeconds` (T=60 gives 50; T=100 gives 0; T1=80 gives 12), and for `Held` cases (a), (b) and (d), with `StartHolder`. Add `ZzDecide` wiring tests for:
  - each never-retried reason, `ToolsRun` and `Broken`;
  - `no_key` retried with the retry runner's key checked;
  - a second retry never sent, and the retry's `rate_limited` not re-sent;
  - `RETRYSKIPPED` in the reasons;
  - a bad `RetryItem` giving a warning and no retry;
  - an inbound `RetryOf` ignored by `Held` and cleared by `SentRequest`;
  - `Model` from the answering reply.

  Cites DW-647 and DW-650.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls`: retried-turn tests on shadow runners.
  - With another job holding the first runner's lock, the retry answers. It is not Busy.
  - The seed comes from the stored session (continue) or `SeedText` (fresh). The link moves to the retry's session, with `SessionRotated` 1.
  - A late first `SaveLinked` CAS leaves the link.
  - The next turn's logged messages carry the seeded history.
  - A `RetryOf` that `RetryAllowed` refuses gives an error and no mock request.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Timeouts.cls`: `RetryTimer` values for 12, 55, 60, 98, 99 and 110. `Apply` merges `Derive(RetryTimer(T))` into the retry entries.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/SecondModel.cls` (new, live). It uses the production and the mock, with `Prepare` as `Test.Agent.Decide` does. Each test writes the first runner's `RetryItem` and the retry item's `Model` (`claude-sonnet-5-5`) as System Default rows, restarts them, and deletes the rows in `OnAfterOneTest`. Tests:
  - `TestRetryAnswers`: refusal, `max-tokens`, empty, provider-error, timeout (T=12) and rate-limit (T=12) on decide, each with the retry answering.
  - `TestRetryFails`: the same cases with the retry failing (one-reply scenarios, `decide-late` and `overloaded`, plus `retry-refusal-then-error` for the retry's own reason).
  - `TestNeverRetried`: budget, precheck daily cap, `too_large` and gateway 403. Each falls back with zero requests to the retry runner.
  - `TestNoSecondModel`.
  - `TestDiagnosisRetried`.
  - `TestRetriedTurnKeepsTheConversation`: a user turn, with T=12 and `retry-chat-held`. The late first attempt does not move the link, and the next turn answers from it.
  - `TestRetryOfFromTheWebIsIgnored` (DW-650 c): uses the real `OcuTalon.Web.Api` `POST /v1/messages` handler in process, with a CSP session of the test's own session, or the HTTP endpoint the way `Test.Install.PasswordGuard` reaches it.
  - The Integration AC through `WebChatIn`.

  Every case asserts exactly one Decision row and one answer from `Decide`, plus the headers to each runner.
- [x] `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` (footprint extension, not contended): `SetKeys`/`PointKeys`/`RestoreKeys`/`KeysAre` take an optional runner list, so the retry entries can be pointed and restored. Do not copy them.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls`: rewrite `TestEntries` for six entries.
  - Each `ProviderConfig` names its own entry, and the retry items name `@{config:OcuTalon<Agent>Retry}`.
  - With the flag, the retry entries carry the mock header.
  - The retry entries' timeouts are `Derive(RetryTimer(60))`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: oracle rows with the retry items enabled and their settings. Fix the doc at :13.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`: correct the doc lines that say "RetryOf does not exist yet". Do not change the allow-list.
- [x] Search the test trees and `docker/tests/` for assertions on the shape of the production's enabled runner items or the count of jobs and entries, and update them (Rule 19).

**Acceptance Criteria:**
- Given `RetryItem` names the agent's retry runner, the retry runner has a second model, and `Install.Step.Provider` wrote its `AI.LLM.OcuTalon<Agent>Retry` entry before its `ProviderConfig` row, when the first attempt ends with a retried reason, then `Decide` sends the same request once to the retry runner (same `DecisionRef`, `RetryOf` = the first runner). A usable answer becomes the decision, diagnosis or reply, and its row and answer record the second model plus the sum of both attempts' tokens, cost and steps.
- Given the retry is unusable too, when `Decide` concludes, then the item, incident or turn takes release 1's fallback route with `Fallback` 1 and the retry's reason, and no action, fix or approval request follows.
- Given no `RetryItem`, when a reply is unusable, then the runner headers show exactly one runner request and the fallback is release 1's.
- Given `daily_cap`, `budget`, `too_large` or `ToolsRun`, when `Decide` classifies the attempt, then it falls back at once and no request reaches the retry runner.
- Given a retry request, when it is sent, then it carries no `temperature`, `top_p` or `top_k` (the mock rejects them), its cap is in its family's key, and T1 + T2 <= 110 s.
- Given `TimerSeconds` 100 with a second model, when the first attempt fails, then no retry is sent, the fallback's reasons say the retry was skipped for lack of time, and the retry entries hold `Derive(12)`. This settles DW-647.
- Given a retried user turn, when the next turn of the session runs, then it answers from the conversation the user saw, the retry's seeded session, even after the late first attempt saved its own session.
- Given DW-650's four cases, when tested live and in process, then:
  - (a) a retry with `RetryOf` for the same conversation and `ItemId` skips `Held`;
  - (b) a request without `RetryOf` waits;
  - (c) a `RetryOf` sent through the web API is ignored, and the turn waits;
  - (d) a `RetryOf` naming another conversation or `ItemId` waits.
- Given `OCUTALON_MOCK_KEY_HEADER=1`, when the Provider step runs, then each retry entry's `custom_headers` holds `x-ocutalon-mockkey`, and the retry-answers tests arm `POST /_mock/countdown` for their marker so that the first attempt fails and the retry answers.
- Integration (Rule 1): given a session with a second model on `ChatAgent`, when the user's message goes through `WebChatIn` to the real `Conversation` and `Decide`, and the first attempt is refused (`retry-chat` armed 1), then the Turn is done with the retry's reply and no fallback, and the user's next message is answered with that exchange in its history.


- [x] [Owner] U-281: change the bridge constant `RETRYSKIPPED` to exactly "The second model was not tried, because too little time was left within the decision's 110-second limit." and pin the new text in the fixed-strings test (the test that pins the bridge's reason sentences); mutation: revert the constant's wording -> that test red. (Applied in the code-review stage as a required patch.)
- [x] [Owner] U-282: a test pins that a timed-out first attempt of kind `turn` sends no second request (the mock receives exactly one request for the turn's marker; no retry runner header) and that the user gets the existing chat-turn fallback with reason `timeout` ("I couldn't answer that: ... Nothing was changed."); mutation: `Retryable` retries a timed-out `turn` -> red. (Reuse the R2 test if it already pins both; otherwise add the missing assertion. Applied in QA or code review.)

### Review Findings

Code review 2026-11-05 (Opus tier, four layers; 36 raw findings, 12 entries kept after grouping, 13 rejected). The U-281 item above was applied as the owner's required patch: `RETRYSKIPPED` reads the ruled sentence, `Test.Bridge.Decide` `TestRetrySkipped` pins it, mutation under `## Verification`.

- [x] [Review][Patch] `Test.Install.Provider` was not hermetic: `TestApplyCaFile`, `TestTimerRow` and `TestBadTimer` compared the state after `Run()` with a snapshot of whatever the stack held, so an earlier mutation or test's leftovers turned "the entries and rows are as they were" red (QA's flake). Each now runs the step before taking its snapshot. Reproduced and fixed on `e17s2cw` [src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls:191]
- [x] [Review][Patch] The AD-10 statement of the security overview says `TestToolInventory` checks every running runner, but the three retry runners this story enabled were not checked. `TestToolInventory` now checks `INVENTORYRUNNERS` (all six, each retry runner against its first runner's tools), and `SecurityOverview.TestInventoryStatement` again asserts that list equals every enabled runner [src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls:65]
- [x] [Review][Patch] R2's read-only judgement had unpinned clauses: only the READONLY clause could go red. `ToolsReadOnly` now delegates to the pure `ToolsetsReadOnly`, and `TestToolsetsReadOnly` pins each clause on one-tool fixtures (`Test.Bridge.ZzReadOnlyTool`, `ZzReadOnlySafe`/`Risky`/`Hooked`) [src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:576]
- [x] [Review][Patch] AC5's mutation line named only `SessionConfig.TestNoSampling`, a test that never builds a retry. A retry-only mutation now turns the live `SecondModel` red (line under `## Verification`) [src/ocutalon/cls/OcuTalon/Test/Bridge/SecondModel.cls:609]
- [x] [Review][Patch] `StoredMessages`' delta-record path (a full export, then delta arrays; a later full export starts again) had no deterministic test. `TestStoredMessagesSkipsBadRecords` now covers both orders [src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls:329]
- [x] [Review][Patch] `TestNoSecondModel` relied on there being no `RetryItem` row. It now writes the empty row itself, and `OnAfterOneTest` puts it back [src/ocutalon/cls/OcuTalon/Test/Bridge/SecondModel.cls:246]
- [x] [Review][Patch] `TestRetryBadItem`'s doc claims a disabled retry item, but no case reached the disabled branch. A case with an `Enabled` 0 row for `TriageAgentRetry` now pins it [src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls:3570]
- [x] [Review][Patch] Rule 2: `StoredMessages` repeated `HistoryChars`' read of the stored `ContextData` stream. Both now use `StoredContext` [src/bridge/cls/OcuTalon/Bridge/RequestSize.cls:69]
- [x] [Review][Defer] The retry runner's timeouts come from `RetryTimer(TimerSeconds)`, while Decide waits T2 = min(T, 110 - T1) with T1 = `TimerFor`: for a flagged turn T2 is 30 s against a worst case of about 42 s, and for a `no_key` precheck T2 = T against a shorter entry [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:269] — deferred: an occurrence of DW-647 (same root cause, owned by this story); fix-risk high, because the entries are static per item and the spine fixes their formula
- [x] [Review][Defer] A retry that ends after T2 still moves the link unconditionally (`SaveRetried`). The next turn then continues from an answer the user never saw, and a next turn already running loses its CAS save [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:485] — deferred: DW-725 escalated (the fix contradicts the Conventions' "a retry's point always applies"; it needs an AD-6/AD-8 ruling)
- [x] [Review][Defer] The retry's seed holds the first attempt's refused, cut-off or empty exchange, so the user message appears twice and the history keeps an exchange the user never saw (residual risk 1, Decided-in-stage 18) [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:468] — deferred: DW-726 decision-pending (a product call, because the Conventions specify the stored texts as the seed)
- [x] [Review][Defer] Spine AD-8's retry-entry formula `Derive(min(T, 110 - T))` lacks the `MINTIMER` clamp that the DW-647 AC and `Timeouts.RetryTimer` apply [ARCHITECTURE-SPINE.md AD-8] — deferred: DW-727 routed to 17.4 (the lead writes the clamp into the spine under Rule 20)

Rejected:
- `false` StoredMessages `<MAXSTRING>` on a huge history: compaction at 40,000 tokens and the request-size limit keep a stored history far below 3.6 M characters.
- `false` A provider-reported timeout on a `turn` is retried, against U-282: a failure reply carries `ToolsRun` (`ToolsRan`), and AD-8's U-282 bullet covers only the attempt whose reply never reached Decide.
- `low` The retry's precheck ignores tokens already spent: AD-20's per-decision budget is the pre-send estimate of the request, and every re-send works the same way. Changing that adds state.
- `low` `RetryItem` validation does not check the retry item's agent, model or `Retry` suffix: only Story 17.4's `SetModel` writes the setting, together with the second model, so a hand edit is unlikely, and the fix adds guards.
- `low` `TryRetry`'s Busy branch: it is reachable only with an empty `ItemId`, which the pipeline never sends (adjudicated in implement).
- `low` An unusable retry still saves and moves the link: "after a completed, untainted Chat" is the spec's rule, and release 1's first attempt saves refused exchanges the same way.
- `low` The retry's `SendRequestAsync` error returns a status with no row: this matches the first send and the re-send, and a queue send to an enabled item fails only in a broken production.
- `low` `Timeouts.Entries` skips a retry item whose `ProviderConfig` read fails: this is the documented design, and the read fails only for a missing item or setting.
- `low` `SecondModel.TestNeverRetried`'s budget, `too_large` and precheck daily-cap legs cannot fail through `Retryable`: AC4's observable holds and is pinned in process (`TestRetryable`, `TestRetryNeverCases`), with the gateway-403 mutation recorded.
- `low` The web leg of `TestRetryOfFromTheWebIsIgnored` uses a fixed `Hang`: a positive assertion follows it, and the live mutation recorded by QA turned the test red.
- `low` `TestApplyRetryEntries` asserts an absolute 20: the install default timer of 60 is the fresh-environment baseline, and `RestoreTimer` puts the saved timer back first.
- `low` AC8(b), AC1's sub-clauses and the retry's no-re-send guard have no mutation lines of their own: Rule 19 asks for one mutation per AC, AC8 and AC1 have theirs, and the guard is a task, not an AC.
- `low` The spec contradicts itself (residual risk 2's "45 s", the matrix arming 0, "Not touched: the spine", `status` beside the unticked U-281): fixing these means editing the spec under review. U-281 is now ticked, and the spine edit was the lead's, under U-282.

- [x] [CI] checks: `docker/tests/test-bridge-guide.sh` rule `reference` fails on fa7a154f: "the guide does not name `RetryItem`" and "the guide does not name `RetryOf`" -- https://github.com/jbrandtmse/OcuTalon/actions/runs/42007140091 -- fix: append ONE self-contained section at the very END of `docs/bridge-guide.md` (after "## Where to go next"; contended with Epic 40, so touch nothing else in the file), titled `## Second-model retry`, in the guide's reference style, ASCII only: name the first runner's `Decide` host setting `RetryItem` (empty by default: no retry; set by the model-change API) and the `Request` field `RetryOf` (set by `Decide` on the one retry it sends; a client's value is ignored and cleared), the retried and never-retried reasons as AD-8 and the spine's 2026-11-05 extension give them (a timed-out `turn` is never retried), and the timer split with the sentence `RETRYSKIPPED` gives. Claim only what Story 17.2 built. Then `bash docker/tests/test-bridge-guide.sh` passes (ruling U-286, veto).

Code review 2026-11-05, rework re-review iteration 1 (Opus tier, four layers, diff `4f2cb72a..HEAD`): 28 raw findings, 8 entries kept after grouping (high 0, medium 2, low 6), 7 rejected. The [CI] item is confirmed closed: `bash docker/tests/test-bridge-guide.sh` passes all four rules (reference names `RetryItem` and `RetryOf`) and `bash docker/tests/test-boundaries.sh` passes, both after the patches below. Every patch changes only the appended `## Second-model retry` section.

- [x] [Review][Patch] (medium, fix-risk low) The Config Store sentence said `Timeouts.Apply(timer)` keeps any retry runner's entry at the retry timer, but `Timeouts.Entries` and `IsRetryItem` handle only an item named after a runner of `Decide.#RUNNERS` plus `Retry` whose `ProviderConfig` is `@{config:<name>}`, so a retry runner set up as the guide says (any enabled runner, or an inline row as in step 3) kept a stale `http_config`. The sentence now says the timeouts come from `Timeouts.RetryTimer(timer)`, scopes what Apply writes, and says to write the row yourself otherwise [docs/bridge-guide.md:351]
- [x] [Review][Patch] (low) T1 was never defined, so "with the default 60 the retry waits 50" was wrong for a compacted turn (`TimerFor` adds `Compaction.#SUMMARIZERSECONDS`, T2 = 30) and for a first attempt refused before it was sent (T1 counts as 0). The sentence now defines T1 as AD-8's `TimerFor` does [docs/bridge-guide.md:351]
- [x] [Review][Patch] (low) The setup sentence asked for `ReplyClass` "for a decision" while `RetryItemProblem` refuses a diagnosis retry runner without one too; it now says "for a decision or a diagnosis" [docs/bridge-guide.md:337]
- [x] [Review][Patch] (low) "When the retry completes, the conversation moves" left out the untainted condition (`AnswerRetried` calls `SaveRetried` only after a completed, untainted Chat); added [docs/bridge-guide.md:355]
- [x] [Review][Patch] (low) "A turn whose session is broken" was defined nowhere in the guide; it now names the case `Decide.Broken` tests (a saved conversation's turn whose error holds "Invalid input") [docs/bridge-guide.md:346]
- [x] [Review][Patch] (low) The guide implied a `RetryOf` that the named runner's `RetryItem` does not name is ignored; `Adapter.Agent.Answer` returns an error and sends nothing, and the sentence now says so [docs/bridge-guide.md:338]
- [x] [Review][Defer] (medium) A retry that ends after T2 still moves the conversation, which the guide's sentence describes as built [docs/bridge-guide.md:355] — deferred: occurrence appended to DW-725 (escalated, owner burndown); revise the sentence when DW-725 is ruled
- [x] [Review][Defer] (low) The guide's existing reference sections still describe one attempt: the `TimerSeconds` row, the `DecisionTokenBudget` row (checked per attempt, so a retried decision may use up to twice it), "Timeouts", "The fallback route" and the `DecisionResponse.Model` row [docs/bridge-guide.md:159] — deferred: occurrence appended to DW-728 (routed, owner burndown, U-286 condition 2; the file is contended with Epic 40)

Rejected (re-review):
- `low` U-286 condition 1 (the Contest Planner reviews the exact guide text before it is pushed) has no task in the spec: it is the lead's push gate, not a code defect, and the commit 565bda91 is local only.
- `low` The section departs from the [CI] item's wording ("`Decide` host setting", "set by the model-change API"): by design, the code declares `RetryItem` on `AgentRunner`, and the model-change API is Stories 17.3 and 17.4's, so naming it would claim what 17.2 did not build (the previous pass's intent-alignment note).
- `low` The rework replaced the Auto Run Result's whole-story record and its residual risks: fixing it edits the spec under review; the round-1 record is in git at 4f2cb72a and its open risks are ledgered (DW-724 to DW-727).
- `low` The frontmatter `status: 'done'` and `review_loop_iteration: 0` disagree with the sprint status and the cycle log: frontmatter status is build-auto's machine state, which this stage must not change; the sprint status is synced by this stage.
- `low` "Its tokens, cost and steps are the sums of both attempts" undercounts a first attempt whose timer fired (its steps arrive after the retry is sent): the next paragraph already says a late reply counts its cost and is dropped, and the case needs a read-only decide or diagnose whose timer fired.
- `low` A retry runner with an empty `Model` uses its agent class's model, so the "second model" can equal the first: the sentence "whose `Model` setting is the second model" is true, and the `Model` row of "Settings" gives the default.
- `low` A request sent straight to the retry runner, not through `Decide`, keeps its `RetryOf`: the guide's contract sends requests to `Decide`, and the runner still acts only when the named runner's `RetryItem` names it.
- [x] [Owner] DW-725 (ruled by the Contest Planner under the owner's delegation, 2026-11-05; spine AD-8 "A late reply moves nothing", AD-6 and Conventions "Retried turns" amended): a reply that reaches `Decide` after its timer -- the first attempt's or the retry's -- is counted for cost and dropped and moves nothing. A retried turn's conversation link moves to the retry's session ONLY when the retry answers within its timer `T2` and its turn is not tainted; otherwise the conversation stays on the session it named. Change the unconditional `Point` in the retry path (`SaveRetried` / `AnswerRetried`) so a late retry never points the link (how the runner learns it is late is the implement stage's choice within the spine, e.g. `Decide` has already recorded the decision for the `DecisionRef`, or a deadline the retry request carries; record the choice in Design Notes). Tests (live through `Test.Bridge.SecondModel` or in process, whichever pins it deterministically): (1) a late retry leaves the link unchanged and its cost counted in `Usage`; (2) an on-time retry moves the link; (3) a late first attempt after an on-time retry still does not undo the move (the existing test stays green). Demonstrate a mutation: the retry path points the link regardless of lateness -> test (1) red; write the `mutation:` line under `## Verification`.
- [x] [Owner] U-286 (approved by the Contest Planner with one change): in `docs/bridge-guide.md`'s `## Second-model retry` section, replace the last paragraph's second sentence `When the retry completes and its turn is not tainted, the conversation moves to that session.` with exactly `When the retry answers within its timer and its turn is not tainted, the conversation moves to that session; a retry that answers after its timer moves nothing.` Change nothing else in the file. Then `bash docker/tests/test-bridge-guide.sh` and `bash docker/tests/test-boundaries.sh` pass.

Code review 2026-11-05, rework re-review iteration 2 (Opus tier, four layers, diff `c9879504..HEAD`): 25 raw findings, 6 entries kept after grouping (high 0, medium 1, low 5), 11 rejected. Both [Owner] items are confirmed met:
- DW-725: `SaveRetried` points only while `RetryIsLate` is 0. Tests (1) a late retry leaves the link and saves nothing, with its `Usage` row counted, (2) an on-time retry moves the link, and (3) `TestRetriedContinueTurn` stays green. Each has a demonstrated mutation under `## Verification`.
- U-286: exactly one line of `docs/bridge-guide.md` changed, and it matches the ruled sentence word for word. `test-bridge-guide.sh`, `test-boundaries.sh` and `test-class-rules.sh` pass.
- On the warm throwaway `e17s2c3w`, `Bridge.Conversation`, `Decide`, `SecondModel` (live: on-time retries through the real `Decide` still move the link) and `CodeRules` pass.

- [x] [Review][Patch] (low) The `RetryIsLate` doc said Decide records the row "only when the retry's timer fired (or the decision ended another way)". That contradicted itself, the class header and Design Notes 24. It now says when the row is written and that lateness is read once [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:505]
- [x] [Review][Patch] (low) The rework spliced its triage entry into Task 0's inline code. That split Task 0, left a stray `## Design Notes` heading inside Tasks & Acceptance, and kept the entry out of `## Review Triage Log`. Task 0 is restored byte for byte from `c9879504`, and the entry is moved, unchanged, to the end of the triage log [spec:150]
- [x] [Review][Patch] (low) The DW-725 `mutation:` line described the pre-patch guard (`If ..RetryIsLate(request) Quit`). It was re-run on the committed form and the line rewritten [spec, ## Verification]
- [x] [Review][Patch] (low) The cost clause of DW-725 test (1) had no demonstrated mutation. A late retry answered before `Converse` turns exactly the two cost assertions red; line added [spec, ## Verification]
- [x] [Review][Patch] (low) The on-time direction of the new guard had no mutation. With `RetryIsLate` always 1, test (2) and three retried-turn tests go red; line added [spec, ## Verification]
- [x] [Review][Defer] (medium, fix-risk high) A retry that completes within a few milliseconds of `T2` can still move the link. `SaveRetried` reads lateness once, and three timer orders slip past it, so the link moves while `Decide` drops the reply [src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:490]. The three timer orders:
  - `Decide` (pool 1) has the T2 alarm queued but not yet handled;
  - the alarm fires between the check and the `Point`;
  - the alarm fires after the `Point` but before the reply is queued.
  - deferred: DW-729 escalated, owner burndown, for the decision sheet. It is not HIGH: the implementation follows the spine's split (the runner points, `Decide` judges lateness), the window is the save, point and enqueue time plus `Decide`'s queue latency, and the harm is conversation text, with no tool, cost or safety effect. The real fix is not in-story at med fix-risk. A carried deadline only shifts the race and can invert it: a reply `Decide` accepts would leave the link behind, and the next turn would lack an answer the user saw. Closing it needs one arbiter (`Decide` points when it accepts the reply, or `Decide`'s timer honours a claim), which is an AD-6/AD-8 call.

Rejected (re-review 2):
- `low` `RetryIsLate` misses a decision whose row went to a duplicate in-flight decision of the same `ItemId` and `Kind` (`RecordFallback` returns the winner's row). This is theoretical: it needs one turn's `ItemId` sent to `Decide` twice while the first is still in flight, which `OnRequest`'s duplicate check and the callers prevent. It becomes real if a caller re-sends an in-flight turn.
- `low` The Decision row's save fails, so no row exists: then `Decide` itself errors. This is theoretical (a broken database).
- `low` Part 3 of `TestRetryMovesTheLinkOnlyWhenOnTime` does not repeat part 1's session and `Usage` assertions. It runs the same code path, which part 1 pins.
- `low` The `Decide` side of the signal is pinned only for a `decide` request. `TryRetry` records under `..DecisionRef` whatever the kind (`Decide.cls:638-654`), so the path is the same.
- `low` "Saved no AI session" reads the namespace-wide `^AI.Agent.SessionD` counter. That counter can only false-red, and only if another process saves a session during the class. Test runs are one class at a time, and this is the established `RunnerFixture.SessionMark` pattern.
- `low` A late first attempt with no retry can still rotate the link through `SaveLinked` (fresh or compacted turn). This is outside the rework range and not HIGH: the DW-725 item scopes the change to the retry path, and the Conventions keep "a late first attempt saves its own AI session, as today". Revisit if the ruling is read to cover first attempts.
- `low` The guide now promises more than the code guarantees: by design. The sentence is the owner's exact text, and the residual is DW-729.
- `low` The frontmatter `status: 'done'` disagrees with the sprint status: frontmatter is build-auto's machine state; the sprint status is synced by this stage.
- `low` The rework's Auto Run Result dropped iteration 1's residual-risk line: fixing it edits the spec under review. The line is in git, and its reopen_if is in the iteration-1 triage log.
- `low` The known gaps were not ledgered (deferred 0): the race is now DW-729. The live late-retry case was allowed in process by the DW-725 item, and both halves of the signal are pinned.
- `low` The "Review" line says "each reason is in the Review Triage Log": true now that the entry is moved (grouped with the splice patch).
## Spec Change Log

- 2026-11-05 rework iteration 2 (trigger owner ruling): DW-725 ruled (a late retry moves nothing) and the U-286 guide sentence change; two [Owner] items added; spine AD-6, AD-8 and Conventions "Retried turns" amended with the DW-725 marker. 17.2 is pushed only with both in.

- 2026-11-05 rework iteration 1 (trigger ci): CI red on fa7a154f (checks: test-bridge-guide reference, RetryItem and RetryOf not named in docs/bridge-guide.md); one [CI] item added (ruling U-286).

- 2026-11-05 after implement (lead): owner answers applied to the spec: U-281 REWORD (R1 text), U-282 KEEP with conditions; two `[Owner]` items added under Tasks & Acceptance for the QA / code-review stages; AD-8 extended in the spine.

- 2026-11-05 spec gate (lead): rulings R1 (U-281) and R2 (U-282) added under Design Notes; R2 replaces decided-in-stage 10 (timed-out turns are not retried).

## Review Triage Log

### 2026-11-05 - Review pass
- verdicts: 30 findings - high 0, medium 3, low 26, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: SaveRetried moves the link unconditionally, so a retry that finishes after Decide's retry timer could overwrite a newer link - the unconditional Point is the spec's rule (the retry must win over a late first attempt); under R2 a retried turn's first attempt has already finished, and the window needs a second message inside T2.
  - `[low]` `[reject]` Blind: TryRetry's Held call can never return 1 - the call is the spec's task text; it probes when the ItemId is empty, and a Busy there cannot arise in the pipeline (ItemId is always set).
  - `[low]` `[reject]` Blind: RetryItemOf does not check that the retry item runs the same agent as the first runner - the spec lists the checks (missing, disabled, non-runner, self, ReplyClass); the value is written by Stories 17.3/17.4, not by a user.
  - `[low]` `[reject]` Blind: the retry budget uses the configured T1, not the elapsed time - AD-8 and the DW-647 AC fix T2 = min(TimerSeconds, MAXTIMER - T1); the RETRYSKIPPED text is lead ruling R1.
  - `[low]` `[patch]` Blind: StoredMessages loses the whole history on one bad record - patched: each record parses in its own Try and an unreadable one is skipped; pinned by Conversation TestStoredMessagesSkipsBadRecords.
  - `[medium]` `[defer]` Blind: ToolsReadOnly sees only compiled toolsets, not MCP tools attached later (AD-21) - no MCP server exists in this release, so it is a future-epic hazard; deferred with the evidence.
  - `[low]` `[reject]` Blind: Point hard-codes the row lock name - the class's DataLocation is committed append-only storage and test-storage pins it; a rename is not a realistic change.
  - `[low]` `[reject]` Blind: no unit-level positive test of RetryAllowed on the real adapter - the live SecondModel tests drive the real AgentRunner.Answer with RetryOf and pass.
  - `[low]` `[reject]` Blind: Test.Agent.Models does not list the retry runners - they are the same agent classes and model seeds as the first runners, checked by Test.Install.Production and SecurityOverview.TestToolsMatchRunners.
  - `[low]` `[reject]` Blind: NewRow takes Model from the reply for every decision - the spec's task says so (NewRow/Conclude set Model from the answering Reply.Model when not empty), and TestTotals/TestTurnKeepsReply pin it.
  - `[low]` `[patch]` Edge: StoredMessages - empty piece or malformed record discards the history - same root cause as the Blind finding above; one patch.
  - `[low]` `[patch]` Edge: RetryAllowed does not strip whitespace although Decide does - patched with the same $ZStrip.
  - `[low]` `[patch]` Edge: SaveRetried sets SessionRotated 1 although Point may not have moved the link - patched: Point's moved output decides.
  - `[low]` `[patch]` Edge: Point can return OK with moved 0 after a double create race for an unconditional write - patched: it returns an error status then (only reachable in a three-way race).
  - `[low]` `[reject]` Edge: Busy from TryRetry's Held leaves spent Usage rows with no Decision row - only reachable with an empty ItemId, which does not occur.
  - `[low]` `[reject]` Edge: the retry seed holds the refused exchange the first attempt saved, so the user message appears twice - the spec seeds from the stored history of the linked session; dropping the last message would change specified behaviour. Residual risk, reopen_if the second model's answers show the duplication confuses it.
  - `[false]` `[reject]` Edge: a timed-out turn and a non-read-only decide are not retried although the spec lists timeout - lead ruling R2 of the spec gate (Spec Change Log) replaces that; the code follows R2.
  - `[low]` `[patch]` Edge: Point's doc claims both forms take the row lock - patched: the doc now says that the create path takes none and why that is safe.
  - `[medium]` `[patch]` Verification gap: TryRetry's Held wiring (DW-650 a through Decide) is pinned by no test - patched: Decide TestRetryTurnSkipsHeld, with mutations recorded.
  - `[medium]` `[patch]` Verification gap: no test observes the retry session's timeout_ms (Adapter task d) - patched: Runner TestSessionTimeout pins TimeoutMs(1) and ZzRetryAdapter records the config of Conversation TestRetriedContinueTurn; mutation recorded.
  - `[low]` `[reject]` Verification gap: SwitchTo's compare-and-set failure branch is untested - reaching it needs a compaction scenario with a link moved in between; the branch only returns the existing SwitchTo failure text, and R2 makes the race hard to reach.
  - `[low]` `[reject]` Verification gap: ReplyClassOf of the answering retry runner is untested with a differing ReplyClass - both retry runners carry the first runner's ReplyClass by install; no user path differs.
  - `[low]` `[reject]` Verification gap: row-lock atomicity of Point is not exercised - a deterministic two-process test is costly; the sequential logic is pinned by TestLinkCompareAndSet.
  - `[low]` `[patch]` Verification gap: mutation lines are missing or combined for the no-sampling AC, the never-retried guards, DW-650 (a) and (b), and no restore statement - patched: eight mutations applied, observed red and restored (md5), lines written under Verification.
  - `[low]` `[reject]` Verification gap: TestRetryOfFromTheWebIsIgnored asserts a negative after a fixed Hang 8 - its positive assertion afterwards (a request reached ChatAgent with an empty RetryOf) fails if the turn never proceeds.
  - `[low]` `[reject]` Verification gap: TestNoSecondModel relies on no RetryItem row from an earlier crashed run - OnAfterOneTest and SettingsStubs clean and check the rows; a crash is not an order dependency.
  - `[low]` `[reject]` Verification gap: TestApplyRetryEntries' before-value assertion is conditional - the after-value assertions that matter are unconditional.
  - `[low]` `[reject]` Verification gap: SecondModel's late-first-attempt case is covered by shadow runners only, and the spec matrix is stale against R2 - R2 is logged in the Spec Change Log; the concurrent case is pinned in Conversation.
  - `[low]` `[reject]` Verification gap (other): the SecurityOverview statement says TestToolInventory checks every running runner, while the retry runners are checked by TestToolsMatchRunners - the statement is AD-10 fixed public text; the retry runners are the same agent classes. Reopen_if the statement is next revised.
  - `[low]` `[reject]` Verification gap (other): TryRetry's Busy branch is effectively unreachable - same as the Blind finding on Held.
  - intent-alignment: descriptive, no finding; its divergences (dormant by default, R2 scope for runner-reported timeouts, full Precheck on the retry, Model for every decision) are spec-directed or follow R2.

### 2026-11-05 - Review pass (rework iteration 1, [CI] item: the guide's Second-model retry section)
- verdicts: 9 findings - high 0, medium 0, low 9, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the section is not tied into the Settings tables, "The fallback route" or "Timeouts", and sits after "Where to go next" - the rework item (U-286) fixes the placement at the very end and forbids touching anything else in the file (contended with Epic 40).
  - `[low]` `[patch]` Blind: the section never says how to set `RetryItem` or that the retry runner is configured like any runner - patched: one sentence says to write it as any setting and update the production, and names the runner settings.
  - `[low]` `[patch]` Blind: the timer arithmetic has no practical result - patched: the default 60 s gives a 50 s retry, and a T1 above 98 s means no retry.
  - `[low]` `[patch]` Edge: a turn that timed out after a rate-limit re-send falls back with `rate_limited`, not `timeout` (`Classify`, Decide.cls:1212) - patched: the guide says so.
  - `[low]` `[patch]` Edge: "a timed-out turn is never retried" could be read to cover a provider-reported timeout, which is retried (`timedOut` 0) - patched: the sentence now says "a turn whose timer fired"; same root cause as the row above (the timeout wording).
  - `[low]` `[patch]` Edge: the section does not say that a `rate_limited` reply is re-sent to the same runner first - patched: one sentence, from AD-8 and `Decide.Resend`.
  - `[low]` `[reject]` Edge: the Settings table and "Timeouts" describe release 1's single attempt - they are true while `RetryItem` is empty, and the first paragraph of the new section says what changes when it is set; editing them is forbidden by U-286.
  - `[low]` `[reject]` Verification gap: no `reference` check pins the `RETRYSKIPPED` sentence or the `RETRIED` list in the guide - this pass makes no pinning test change (Rule 19 override), and a new check is more than a direct correction; reopen_if the sentence or the list changes again.
  - `[low]` `[reject]` Verification gap: the open [CI] item has no `mutation:` line - it is a CI-repair item and not an acceptance criterion, and its test changed nothing in this pass; the failing state before the section (the two missing names) is the CI run's red.
  - intent-alignment: descriptive, no finding. It reads the intent as a reference-style prose section only. Its divergences are spec-directed: `RetryItem` is documented as a setting of the runner item that `Decide` reads (the code declares it on `AgentRunner`, not `Decide`), and "set by the model-change API" is omitted because Stories 17.3 and 17.4 build it.

### 2026-11-05 - Review pass (rework iteration 2, DW-725 and U-286)
- verdicts: 20 findings - high 0, medium 0, low 17, false 3, maybe-false 0
- findings:
  - `low` `reject` (blind) The lateness signal is Decide's processing time, so a retry that ends after T2 but before Decide handles the timer still moves the link - a real window, but the ruling defines lateness at Decide ("reaches Decide after its timer"), the window is the queue latency of one timer message, and closing it needs a Request property or a revert path (new state); recorded in Design Notes item 24 and the residual risks.
  - `low` `reject` (blind) The check and the Point are not atomic; the comments say "unconditionally" - the same window as above; the comments state the retry's Point is the non-CAS form, which is true.
  - `low` `patch` (blind) No test covers the premise that Decide records the row under the retry's DecisionRef - the fallback of the main timer path was pinned by `TestTimerFallback` (a mutation turned it red), but the retry's own timer in `TestRetryAfterTimer` did not assert the row's Ref against the DecisionRef the retry carried; assertion added and its mutation demonstrated.
  - `low` `reject` (blind) The edge cases of RetryIsLate are untested (empty DecisionRef, a decision that ended another way) - an empty ref finds no row either way (an equivalent mutant) and a row from any ending means Decide stopped waiting.
  - `low` `reject` (blind) A late drop leaves no log line - the ruling says the reply is counted and dropped; a warning adds a branch for no named reader.
  - `low` `patch` (blind) RetryIsLate is a public instance method - made `[ Private ]`, as its neighbours are.
  - `low` `reject` (edge) The timer fires between the check and the Point - same window as the first row.
  - `low` `reject` (edge) The retry points, then T2 fires before the reply reaches Decide - same window, shorter.
  - `low` `patch` (edge) The RetryIsLate read sits outside the Try of SaveRetried, so a database exception would escape its warn-only contract - moved inside the Try.
  - `low` `reject` (edge) A retry with an empty DecisionRef is "never late" - Decide always sends a DecisionRef; an empty ref cannot match a row.
  - `false` `reject` (edge) A row that exists because the decision ended another way marks a running retry late - any recorded row means Decide has answered the caller without this retry, which is lateness under the ruling.
  - `false` `reject` (edge) A late first attempt with no retry still moves the link (SaveLinked) - release 1 and the amended AD-6 keep it ("a late first attempt saves its own AI session, as today"); the ruling's protection of the retry's session is the existing compare-and-set.
  - `low` `reject` (edge) The guide states the move unqualified while a race exists - U-286 fixes the sentence exactly.
  - `low` `patch` (verification-gap, grouped with the premise row above) The lateness signal is faked in the only test of it - the Decide side is pinned as above; a live case needs a new mock scenario (refusal, then a reply slower than T2), which this pass does not add.
  - `low` `reject` (verification-gap) The race and the empty-DecisionRef clause are unpinned - same window; the empty-ref clause is an equivalent mutant.
  - `low` `reject` (verification-gap, other) No mutation for the reverse direction (`RetryIsLate` always 1) - the DW-725 line names one mutation per AC; the on-time assertions of the same test fail under it.
  - `low` `reject` (verification-gap, other) The ticked [Owner] items run into the next heading - editing the spec's layout is not a fix for this build.
  - `low` `reject` (intent-alignment) The intent block says "unconditionally", the diff gates on lateness - the owner ruling DW-725 amended the spine; the intent block is read-only.
  - `false` `reject` (intent-alignment) The row is a broader signal than T2 - see the row-from-another-ending verdict.
  - `low` `reject` (intent-alignment) The test is in process, not live - the item allowed an in-process test.
- routes: patch 3 entries (the retry-timer Ref assertion with its mutation; RetryIsLate Private; the check inside the Try), defer 0, intent_gap 0, bad_spec 0. Patch verification: `Bridge.Conversation`, `Bridge.Decide`, `Bridge.SecondModel` and `Bridge.CodeRules` pass on `e17s2i3w`; `test-bridge-guide.sh`, `test-boundaries.sh` and `test-class-rules.sh` pass.

## Design Notes

**Governing ADs (Rule 6).** No AC contradicts an AD's Rule.
- AD-2: the bridge names no OcuTalon package.
- AD-5: append-only storage, and the bridge timer <= 110 s.
- AD-6: the pipeline, the conversation link and lock, the `RetryOf` sub-bullet, and `Held`.
- AD-7: family session config, no sampling parameters, and `ResolveModel`.
- AD-8: the reasons, the second-model retry, the timer split, `Timeouts.Derive`, and the late reply.
- AD-19: the Config Store entries written by `Install.Step.Provider` before the setting that names them, and the CI-only mock header.
- AD-20: one Decision row, `Usage` totals, the per-decision budget and the daily cap.
- AD-22: the CI mock and its countdown, and throwaway tests.
- AD-26: the trace.
- AD-29: lanes; the Lane A region of `Production.cls`.
- AD-30: callers and the pipeline.
- Conventions: "Retried turns", "Saved conversations" and "SessionBroken retry".

**Ledger (Rule 17).**
- DW-647 is addressed by the `Timeouts.RetryTimer` task and the "No time left" row, and closed by the `TimerSeconds` 100 AC. `TimerSeconds` is not capped. When T2 < 12 the retry is skipped and the reasons say so. The retry entries derive from `max(12, min(T, 110-T))`, so they never get `{}`.
- DW-650 is addressed by the (a)-(d) AC and the `Held`, `Conversation` and `SecondModel` (c) tasks.

**Decided in-stage.**
1. `RetryOf` is set on every retry clone, of any kind; the adapter acts on it only for a linked turn. First sends and re-sends always clear it. This is the server-side guarantee behind case (c), whatever a client copies upstream.
2. `Held(request, runner, itemId)` is the single rule for the `Held` skip. `OnRequest` never passes `itemId`, so a client's `RetryOf` is ignored. The retry path passes the decision's `ItemId`.
3. The runner refuses a `RetryOf` that its `RetryItem` relation does not name (`RetryAllowed`). This is defence in depth for case (d).
4. The retry attempt is never re-sent by `Decide`; AI Hub's retry block still applies. Its precheck is the resend's (budget and size on its own estimate, the daily cap, and the retry runner's `Keys.Absent`).
5. A bad `RetryItem` is a warning and no retry, never an error status. An error would make `Decide` refuse every request.
6. The retry items are enabled at install with agent and reply classes. Their `Model` is seeded with the agent's `MODEL`, and `RetryItem` stays empty, so a default install is release 1's. Stories 17.3 and 17.4 (`SetModel` with `second=1`) set the second model and `RetryItem`.
7. The entry name comes from the item (`<name>Retry`), because `EntryName(agentClass)` alone would point every retry item at its first runner's entry.
8. `Decision.Model` is the answering reply's `Model`. `Usage.Totals`' newest-row model can be a late first attempt's.
9. `Decide`'s new stored state is `RetryRunner` and `FirstSeconds`, on the existing pattern of `Resends` and `StepsSent` (AD-5 lists that pattern).
10. [SUPERSEDED by lead ruling R2 below] A timer-fired first attempt is retried although `ToolsRun` is unknown: the spine lists `timeout` as retried. This is a residual risk (inference). A tool that a late first attempt runs is still gated: risky tools wait for approval (AD-10).
11. The live tests put `TimerSeconds` on `Decide` only, as `Test.Agent.Decide.TestTimer` does, so the entries keep the derivation for 60.
    - The rate-limit case relies on a 529 after 10.5 s landing between 10 s and 12 s (inference). If it is flaky, use T=20 with a delay of 18.5 s.
12. Test placement:
    - The live class is `Test.Bridge.SecondModel`, in the footprint, in shard `lane-a@rest` (`shards-2`), with no `ci/units.sh` edit.
    - The in-process parts extend `Test.Bridge.Decide` and `Test.Bridge.Conversation`.
    - `Test.Agent.RunnerFixture` is extended, not copied.

**Lead rulings at the spec gate (2026-11-05, runner A, unattended; policy 5086036).**
- R1 (veto U-281, answered REWORD by the Contest Planner 2026-11-05T06:37:23Z#852): `RETRYSKIPPED` reads exactly "The second model was not tried, because too little time was left within the decision's 110-second limit." (the retry is skipped when T2 < MINTIMER, so some time may be left). Keep it as the one constant; no other new user-facing text.
- R2 (veto, inbox U-282), replacing decided-in-stage 10: a timed-out first attempt has an unknown `ToolsRun`, and AD-8 never retries an attempt in which a tool ran (this story's AC: no tool runs twice). So a timed-out first attempt of kind `turn` is NOT retried: it falls back exactly as in release 1, with its timeout reason. A timed-out `decide` or `diagnose` attempt is retried only when every tool its agent can call is read-only (AD-10's read-only tool sets); if any of its tools can change state, or the implement stage cannot establish that from code, it is not retried either. Every other retried reason (a reply that arrived, with `ToolsRun` known) follows AD-8 as written. The matrix and the live timeout cases follow this: `turn` timeout -> no retry, one fallback; `decide`/`diagnose` timeout -> retry. Add the mutation: `Retryable` retries a timed-out `turn` -> the turn-timeout case goes red. Answered KEEP by the Contest Planner (U-282, 2026-11-05T06:37:23Z#853) with conditions: the timed-out turn's fallback is the existing chat-turn fallback with reason `timeout` ("I couldn't answer that: ... Nothing was changed."), a test pins that a timed-out turn sends no second request, and AD-8 records the tightening (spine, [AMENDED 2026-11-05, Story 17.2, ... U-282]).

**For the lead (veto window).** The text of `RETRYSKIPPED`, proposed as "The second model was not tried, because no time was left within the 110-second limit." The spine requires the sentence, but the UX does not word it. It shows in the trace's decision reasons, as `HELDBEFOREUPDATE` does.

**Task 0 results (implement stage, warm throwaway `e17s2iw`, the CI mock).**
- The saved session's `ContextData` stream, after two linked turns, is one record of 5,853 characters: a full export, a JSON object with the keys `version`, `messages`, `checkpoints`, `stats` and `base_system_prompt`. AI Hub's source says later saves may append delta records (each a JSON array of new messages) after the record separator `$Char(30)`; the late first attempt of `TestRetriedContinueTurn` saved such a session, and the reader copes with both.
- The `messages` of the full export are the same JSON as `GetContext().%ToJSON()` of the opened session (checked in `TestRetriedContinueTurn`, 2 messages and then 4), so `Compaction.Seed` of them equals `Compaction.Seed` of `GetContext()`. `RequestSize.StoredMessages(sessionId)` reads them from the database with no lock, no native call and no open session.
- The mock answers `GET /v1/models/claude-sonnet-5-5` with 200 and a model object (`{"type":"model","id":"claude-sonnet-5-5",...}`), given an `x-api-key` header.
- `retry-overloaded-late` at `TimerSeconds` 12 (entries at the block of 60), one developer-machine run: the first request reached the mock at 0 s, the 529 left it at 10.5 s, and AI Hub made no second request (the mock logged one 529 for the attempt). The reply reached Decide with 1.5 s of the timer left, under the 2 s that a re-send needs, so `Conclude` classified `rate_limited`, the retry went out at once to `claude-sonnet-5-5`, and the whole decision was answered 10.52 s after the send. If a slow host stretches the 529 past 12 s, the timer fires instead and a decide request is retried by the timer path; the test asserts only that the retry answered.

**Decided in-stage (implement stage, 2026-11-05).** These add to the list above; item 10 stays superseded by R2.
13. `Ens.BusinessProcess` has a property `Retry`, so the retry path is `TryRetry` (not `Retry`) and the cheap RetryItem probe is `RetryConfigured` (not `RetrySet`). `TryRetry(request, runner, reason, reply, .response, failure = "", timedOut = 0)` is the one place that decides, validates the setting (`RetryItemOf`, one warning for a bad value) and sends.
14. R2 is built as `Retryable(reason, toolsRun, broken, kind, timedOut, readOnly)` and `ToolsReadOnly(runner)`. `ToolsReadOnly` reads the runner's `AgentClass`, each class of its `TOOLSETS`, and each tool the toolset offers; a tool counts only when its class parameters say `CLASSIFICATION` `safe` and `READONLY` 1 and it has no per-call `Classify` hook, and a toolset named by a URI counts as unknown. Triage (no tool) and Diagnosis (three read-only watch tools) qualify; Chat does not. A timed-out `turn` is refused by `Retryable` itself, whatever its tools are; for Chat `ToolsReadOnly` also says no. `ZzDecide` can force `ToolsReadOnly`, so that each layer is tested alone.
15. T1 is 0 when no first attempt was sent (a `no_key` precheck refusal), so that retry gets `min(TimerSeconds, 110)`; otherwise T1 is `TimerFor` of the first attempt.
16. `EstimateTokens` and `Precheck` take the first runner as an argument (`retryOf`) for the retry's estimate, and never read `RetryOf` from the request they are given, so a client's value changes neither the estimate nor `Held`.
17. `ConversationLink.Point` keeps the repository's rule that the link class saves in one place (`TestOnlyTheRunnerWritesLinks`): one `%Save` in `Point`, under an incremental lock on `^OcuTalonBP.ConvLinkD(id)` for an existing row; the adapter now calls `Point` in three places (save, fork, retry), and the test says so. A lost compare-and-set is no error, no warning, and leaves `SessionRotated` at 0.
18. The retry's seed is the stored history of the first runner's session as it stands. A first attempt that completed with a refusal or an empty reply saved its exchange, so that exchange is part of the seed and the retry's own exchange follows it (observed in `TestRetriedTurnKeepsTheConversation`). The spec does not exclude it; it is a residual oddity of the conversation text, not a state problem.
19. Retry entries derive from `Timeouts.RetryTimer(60)` = 50, so a default install has retry entries with a request timeout of 20 seconds (the first runners keep 25).
20. A timed-out `turn` is not retried (R2), so the matrix row "Retried continue turn" with a first attempt that times out while still holding the lock cannot be reached through `Decide`: a first attempt whose reply arrived has released the lock. The lock-free path, the seed, the link move and the late first attempt's lost compare-and-set are tested at the runner (`Test.Bridge.Conversation`, with the first attempt held in a job), and through `Decide` with a refused first attempt (`TestRetriedTurnKeepsTheConversation`, `TestIntegrationWebChat`); the live timeout part of that test asserts the R2 outcome (a timeout fallback, no request to `ChatAgentRetry`, and the late first attempt's exchange saved into the conversation it opened).
21. In the Integration test the triage request of the message carries the scenario marker too and takes the first reply of the countdown, so `retry-chat` is armed at 2. A seed that holds an earlier marker (`[[mock:...]]`) also sets the scenario of the retry, so the retry tests use markers only in the turn that the retry answers.
22. Existing tests whose subject changed shape were updated: `Test.Bridge.Decide` `TestTotals` and `TestTurnKeepsReply` (the Model is the answering reply's), `Test.Bridge.Contracts` (the `Request` contract gains `RetryOf`), `Test.Install.SecurityOverview` (the retry runners are runners: keys pointed for six, the inventory check covers them), `docker/tests/test-production.sh` (the row 16 job pattern matched `TriageAgentRetry`), `Test.Bridge.CodeRules` (the adapter calls `Point` in three places) and `Test.Install.Provider` and `Production`.
23. Mutation results that differ from the plan are written in the mutation lines under `## Verification`.

**Decided in-stage (rework iteration 2, DW-725).**
24. The lateness signal is the Decision row. `Adapter.Agent.RetryIsLate(request)` is 1 when `Bridge.Data.Decision` already holds a row whose `Ref` is the request's `DecisionRef`. `Decide` records that row only when it concludes (a fallback, or an answer), and a retry whose timer `T2` fired is concluded as a fallback before the retry's reply arrives, so a late retry finds the row and an on-time retry does not (it saves and points before its reply reaches `Decide`). No `Request` property is added (storage stays append-only), no deadline is carried, and the runner needs no timer of its own. `SaveRetried` returns at once for a late retry: it saves no AI session, does not point the link and leaves `SessionRotated` 0; the retry's `Usage` row was written by `Chat` and is still counted under the `DecisionRef`. Residual race: lateness is read at one instant, when the runner checks the row. A retry that finishes after `T2` but before `Decide` has processed its timer (a busy `Decide`), the timer firing between the check and the `Point`, and the timer firing after the `Point` but before the reply reaches `Decide`, all still move the link. Closing it needs a deadline in the request (a `Request` property) or a second check with a revert after the write, and was not built.

**Footprint extensions (Rule 11), reported for the lead.** Outside the epic's `paths_hint` list: `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`, `.../Bridge/Data/ConversationLink.cls`, `.../Bridge/RequestSize.cls` (`StoredMessages`; the spec's Code Map names it as the sibling of `HistoryChars`, but its task list did not), `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A region), `.../Test/Agent/RunnerFixture.cls`, `.../Test/Bridge/Contracts.cls`, `.../Test/Install/SecurityOverview.cls`, `docker/tests/test-production.sh`, and the new test helpers `Test/Bridge/ZzRetryAdapter.cls` and `ZzRetryRunner.cls`. None is on the contended list; none is a Lane B class, and `Test/Bridge/ZzDecide.cls` (Lane A) gained a recorder field. Not touched: `Bridge/Msg/Enum.cls`, `Bridge/Ext/**`, `ci/units.sh`, `src/short-names.tsv`, the spine.

**Footprint (Rule 11).**
- Extensions, none contended:
  - `Bridge/Msg/Request.cls`
  - `Bridge/Data/ConversationLink.cls`
  - `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A region)
  - `Test/Agent/RunnerFixture.cls`
- Not touched: `Bridge/Msg/Enum.cls`, `Bridge/Ext/**`, `ci/units.sh`, `src/short-names.tsv`, the spine.
- Story 30.7: no planned file is one that Story 30.7 plans to change. This story does not touch purge, approvals, `Redact`, `KeyProof` or `list_productions`. `Bridge.Purge` keeps reading the link unchanged.

**Extend, don't copy (Rule 2).**
- `AnswerRetried` reuses `NewSession`, `Converse`, `ChatInput(request, 1, seed)` and `Compaction.Seed`.
- The retry send reuses `SentRequest`, `Precheck`, `RecordFallback` and `EmitSteps`.
- `RetryTimer` feeds `Derive`.
- The stored-context reader sits beside `RequestSize.HistoryChars`.
- The live tests reuse `RunnerFixture`, `Contract.Mock.Arm` and the `Test.Watch.Case` WebChatIn harness.

**Integration ACs (Rule 1):** `Conversation` (through `WebChatIn`) consumes a retried turn reply, per the AC above.

**Consumes:**
- 33.1: the retry items and the spine contracts.
- `Data.ConversationLink`, `Compaction.Seed`, `Timeouts.Derive`, `Keys.Absent` and `Usage.Totals`.

**Consumed-by:**
- 17.3: provider resolution applies to the retry runners' entries.
- 17.4: `Settings.SetModel(..., second=1)` sets the retry item's `Model` and the first runner's `RetryItem`, and restarts them. `Values()` reports the second model. `Timeouts.Apply` covers the retry entries.
- 18.x: the Lane B settings page shows the second model through `Values()`.

## Verification

Every `ci/*.sh` call sets the lane's variables on its command line:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`
- `OCUTALON_TEST_WEB_PORT=52801`
- `OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`

The tags are `e17s2iw` (warm) and `e17s2i` (fresh) for implement; QA and code review use their own tags (project block). Use one call each, in the foreground, with `timeout: 600000`. Run `ci/warm.sh down` at the end, also after a failure. Compile checks on `ocutalon-slot-a` use `iris_doc_load` only (`server` and `namespace` `OCUTALON` on every call), and nothing destructive runs there.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s2iw ci/warm.sh up`. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s2iw ci/iris.sh class <C>`, one class per call. Expected: `CLASS <C> passed` for each `<C>`:
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Bridge.Conversation`
  - `OcuTalon.Test.Bridge.Timeouts`
  - `OcuTalon.Test.Bridge.SecondModel`
  - `OcuTalon.Test.Bridge.CodeRules`
  - `OcuTalon.Test.Bridge.SettingsStubs`
  - `OcuTalon.Test.Install.Provider`
  - `OcuTalon.Test.Install.Production`
  - `OcuTalon.Test.Install.ProductionRules`
  - `OcuTalon.Test.Agent.Decide`
  - `OcuTalon.Test.Agent.Models`
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass, with the new scenarios loading.
- (once) `bash docker/tests/test-storage.sh`, then `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `test-bridge-example.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s2i ci/iris.sh live install-start`, then `live production`. Expected: pass; the Provider step writes six entries, and the retry items have jobs. Then `ci/iris.sh shard lane-a@Bridge`, `shard lane-a@Agent` and `shard lane-a@Install`, each in its own call; add `--part k/2` when a call nears 8 minutes. Expected: every class passes. Finish with `ci/iris.sh teardown`.

**Shared surfaces:**
- the production item list and enabled runners: `Test.Install.Production`, `ProductionRules` and `live production`;
- the Config Store entries and `ProviderConfig` rows: `Test.Install.Provider` and the `SettingsStubs` snapshot;
- the `RetryItem` System Default rows: `SettingsStubs` expects 0;
- the `ci/mock/scenarios/A` file set: `scenarios.test.mjs` and `test-bridge-example.sh`.

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19), one per AC, run in the implement stage on the warm throwaway `e17s2iw`.** Each line names the mutation, the test that went red, and says that the file was restored byte for byte (`md5` before and after). `Bridge.X` is `OcuTalon.Test.Bridge.X`.
- mutation: `Retryable` returns 0 for `refusal` (`refusal` out of `RETRIED`) -> `Bridge.SecondModel` `TestRetryAnswers` red (also `TestRetryFails`, `TestRetriedTurnKeepsTheConversation`, `TestIntegrationWebChat`).
- mutation: `SentRequest` stops clearing `RetryOf` (`Set clone.RetryOf = ""` removed) -> `Bridge.Decide` `TestSentRequestRetryOf` red (and `Bridge.SecondModel` `TestRetryOfFromTheWebIsIgnored`, run with the combined mutation of the first implement pass).
- mutation: `OnRequest` passes the request's `ItemId` to `Held` -> `Bridge.Decide` `TestHeldRetryOf` (c) red (the request that carries a `RetryOf` is no longer Busy).
- mutation (DW-650 a): `Held` never skips on `RetryOf` (the `RetryOf` comparison replaced by 0) -> `Bridge.Decide` `TestHeldRetryOf` (a) and `TestRetryTurnSkipsHeld` red.
- mutation (DW-650 a through `TryRetry`): `TryRetry` calls `Held(clone, runner)` without the `ItemId` -> `Bridge.Decide` `TestRetryTurnSkipsHeld` red.
- mutation (never retried: a tool ran): `Retryable` drops the `ToolsRun` test -> `Bridge.Decide` `TestRetryable` and `TestRetryNeverCases` red.
- mutation (retry session config): `Adapter.Agent.Answer` never sets `Retrying` -> `Bridge.Conversation` `TestRetriedContinueTurn` red (the retry's config carries the first runner's `timeout_ms`); `Bridge.Runner` `TestSessionTimeout` pins the values of `TimeoutMs(1)`.
- mutation (no sampling parameters): `ClearSampling` keeps the agent's Temperature -> `Bridge.SessionConfig` `TestNoSampling` red. The retry runner composes its config through the same `Compose` and `ClearSampling`.
- mutation (stored history): `StoredMessages` lets one unreadable record throw -> `Bridge.Conversation` `TestStoredMessagesSkipsBadRecords` red.
Each mutation above was applied to one file, the class named was run on the warm throwaway `e17s2iw`, and the file was restored from a backup and found byte-identical (`md5`); `git status --short` was unchanged after the last one.
- mutation: `Held` ignores the `ItemId` comparison -> `Bridge.Decide` `TestHeldRetryOf` (d) red.
- mutation: `Point` ignores `expected` (`compare` is 0) -> `Bridge.Conversation` `TestRetriedContinueTurn` (the late first attempt moves the link) and `TestLinkCompareAndSet` red.
- mutation: `daily_cap` added to `RETRIED` -> `Bridge.SecondModel` `TestNeverRetried` red (the gateway's 403 reaches the retry runner). The planned mutation on `budget` cannot go red: the retry's own precheck repeats the budget, so no request is sent either way; the `daily_cap` of the gateway has no precheck at the retry, so it is the mutation that tests the rule.
- mutation: `RetrySeconds` drops the `MINTIMER` check -> `Bridge.Decide` `TestRetrySeconds` (T=100) and `TestRetrySkipped` red.
- mutation: `RetryTimer` without the clamp -> `Bridge.Timeouts` `TestRetryTimer` and `TestApplyRetryEntries` red.
- mutation: `NewRow` keeps `Totals.model` (the reply's `Model` is not used) -> `Bridge.Decide` `TestRetryWiring`, `TestTotals` and `TestTurnKeepsReply` red. The live `TestRetryAnswers` stays green under it: in every live case the retry's Usage row is the newest, so `Totals.model` is the second model's anyway; the case where the newest row is the first attempt's is `TestRetryWiring`.
- mutation: `EntryName` ignores the item -> `Install.Provider` `TestEntries`, `TestEntryNames` and others red (the stack was healed by the next unmutated run of the class).
- mutation: the Provider's mock header dropped for retry items -> `Install.Provider` `TestEntries` and `TestApplyCaFile` red.
- mutation: `RetryItemOf` falls back to `<runner>Retry` when `RetryItem` is empty (and `RetryConfigured` is always 1) -> `Bridge.SecondModel` `TestNoSecondModel` red.
- mutation: the failure text of the retry's reply is dropped (`failure = ""` once the retry was sent), so a failed retry is not recorded with its own reason -> `Bridge.SecondModel` `TestRetryFails` red (`retry-refusal-then-error` expects `error`).
- mutation: `RetrySeconds` returns `TimerSeconds` (no `110 - T1` split) -> `Bridge.Decide` `TestRetrySeconds` (T1 80 expects 30 for a timer of 60 and 12 for a timer of 12) and `TestRetryWiring` red.
- mutation: `AnswerRetried` skips the `Point` (`SaveRetried` does not move the link) -> `Bridge.SecondModel` `TestIntegrationWebChat` (the next turn's history) and `TestRetriedTurnKeepsTheConversation` red.
- mutation (R2): `Retryable` retries a timed-out `turn` (the `kind` test is dropped from the `timedOut` branch) -> `Bridge.Decide` `TestRetryable` and `TestRetryAfterTimer` (the turn case, with `ToolsReadOnly` forced to 1) red. `Bridge.SecondModel` stays green under it, because `ToolsReadOnly("ChatAgent")` is 0 and refuses the turn a second time; the two layers are tested apart in process.

**QA stage (2026-11-05, warm throwaway `e17s2qw`, lane A).** Tests added or extended (QA), all in existing classes of the Bridge area (found by `shard lane-a@rest`; no `ci/units.sh` edit):
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls` (QA): `TestLinkPointRefusals` (Point's error returns: empty OwnerRef/agent, and a link row locked by another process, in both forms), `TestRetriedPointFailureKeepsTheReply` (a failed retry Point: `SaveRetried` warns, the reply stands with `SessionRotated` 0, the link keeps S1), `TestRetryAllowedStripsWhitespace` (the real adapter's `RetryAllowed` strips white space), and the helpers `LinkRowId`, `StartRowHolder`, `StopRowHolder`, `RowHolder`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/SecondModel.cls` (QA): `TestRetriedTurnKeepsTheConversation` asserts, for the timed-out turn (U-282), that the mock received exactly one model request for the turn's marker, on the first model; `TestRetryOfFromTheWebIsIgnored` sends a request that carries a `RetryOf` straight to Decide with the lock free and asserts that the request reaching `ChatAgent` has an empty `RetryOf` and is answered as a first attempt.
- U-282 is pinned in three layers: `Bridge.Decide` `TestRetryable` and `TestRetryAfterTimer` (a timed-out turn: `Retryable` 0, nothing sent, no timer, a row with `Fallback` 1 and reason `timeout`), `Bridge.SecondModel` `TestRetriedTurnKeepsTheConversation` (one mock request, headers `1|0` to `ChatAgent`/`ChatAgentRetry`, `FallbackProblems` with `timeout`), and `Test.Core.ConversationTurns` `TestEveryFallbackReason` (the `timeout` reason becomes "I couldn't answer that: ... Nothing was changed."). U-281 is not touched here (the code-review stage rewords `RETRYSKIPPED` and pins it).

Mutations of the QA stage (each applied to one file or, where said, to the edits named, run on `e17s2qw`, restored, and `git status --short` showed only the two QA test files modified afterwards). `Bridge.X` is `OcuTalon.Test.Bridge.X`:
- mutation (Point error return, QA): `Point` returns OK when the row lock is not taken (the `$$$ERROR` of the lock line replaced by `$$$OK`) -> `Bridge.Conversation` `TestLinkPointRefusals` red (the compare-and-set form); `TestLinkCompareAndSet` stays green. The error return of the unconditional form on a lost create race (the last line of `Point`) needs a three-way race and has no deterministic test; the locked-row case reaches the same caller path.
- mutation (`SaveRetried`'s `moved` check, QA): `SaveRetried` sets `SessionRotated` 1 whatever Point said -> `Bridge.Conversation` `TestRetriedPointFailureKeepsTheReply` red. The `&& $Get(moved)` conjunct itself cannot be told from `$$$ISOK(sc)`: `Point` with no `expected` returns an error whenever it did not move, so no test can reach `moved` 0 with an OK status.
- mutation (`RetryAllowed` strip, QA): the `$ZStrip(..., "<>WC")` removed -> `Bridge.Conversation` `TestRetryAllowedStripsWhitespace` red (four padded values).
- mutation (U-282, `Retryable`): the `kind '= "turn"` test dropped from the timed-out branch -> `Bridge.Decide` `TestRetryable` and `TestRetryAfterTimer` red. `Bridge.SecondModel` stays green under it alone (`ToolsReadOnly("ChatAgent")` is 0).
- mutation (U-282, both layers): that edit plus `TryRetry` passing `readOnly` 1 instead of `ToolsReadOnly(runner)` -> `Bridge.SecondModel` `TestRetriedTurnKeepsTheConversation` red on four assertions, among them "a timeout fallback with every guarantee", "after one request, none to the retry runner" and the new "the mock received exactly one model request for the timed-out turn".
- mutation (DW-650 c, a client's `RetryOf` reaches the runner): `SentRequest` stops clearing `RetryOf` -> `Bridge.Decide` `TestSentRequestRetryOf` red and, with the QA assertions, `Bridge.SecondModel` `TestRetryOfFromTheWebIsIgnored` red (before them it stayed green: the earlier run of this mutation had passed only with the first pass's combined edits).
- mutation (DW-650 c, Busy): `OnRequest` passes `request.ItemId` to `Held` -> `Bridge.Decide` `TestHeldRetryOf` (c) red, and live `Bridge.SecondModel` `TestRetryOfFromTheWebIsIgnored` red.
- mutation (DW-650 a): `Held` never skips on `RetryOf` -> `Bridge.Decide` `TestHeldRetryOf` (a) and `TestRetryTurnSkipsHeld` red. mutation (DW-650 d): `Held` ignores the `ItemId` comparison -> `TestHeldRetryOf` (d) red. mutation: `TryRetry` calls `Held(clone, runner)` without the `ItemId` -> `TestRetryTurnSkipsHeld` red.
- mutation (never retried): `Retryable` drops the `ToolsRun` test -> `Bridge.Decide` `TestRetryable` and `TestRetryNeverCases` red; drops the `broken` test -> the same two red (SessionBroken); `RETRIED` gains `daily_cap` -> `TestRetryable` and `TestRetryNeverCases` red, and live `Bridge.SecondModel` `TestNeverRetried` red.
- mutation (a second retry is never sent): the `RetryRunner = ""` guard dropped in `TryRetry` -> `Bridge.Decide` `TestRetryAfterTimer` red.
- mutation (time): `RetrySeconds` drops the `MINTIMER` check -> `TestRetrySeconds` and `TestRetrySkipped` red; `RetrySeconds` drops the `110 - T1` split -> `TestRetrySeconds` and `TestRetryAfterTimer` red; the `Reasons` of a skipped retry set to "" in `TryRetry` -> `TestRetrySkipped` red; `RetryTimer` without the clamp -> `Bridge.Timeouts` `TestRetryTimer` and `TestApplyRetryEntries` red.
- mutation (Model, totals): the answering reply's `Model` not used in `NewRow` -> `Bridge.Decide` `TestRetryWiring`, `TestTotals` and `TestTurnKeepsReply` red.
- mutation (bad `RetryItem`): the "names the runner itself" check dropped -> `TestRetryBadItem` red.
- mutation (`no_key`): `no_key` out of `RETRIED` -> `TestRetryNoKey` and `TestRetryable` red; the retry's precheck given the first runner instead of the retry item -> `TestRetryNoKey` and `TestRetryAfterTimer` red; the key fact forced to 0 -> `TestPrecheckOrder`, `TestOnRequestPrecheck` and `TestBusyRelayed` red.
- mutation (retried linked turn): `Point` ignores `expected` -> `Bridge.Conversation` `TestLinkCompareAndSet` and `TestRetriedContinueTurn` red; `Retrying` never set -> `TestRetriedContinueTurn` red (the retry's `timeout_ms`); `RetryAllowed` always allowed -> `TestRetryOfRefused` red; a retried turn routed to `AnswerLinked` (takes the lock) -> `TestRetriedContinueTurn`, `TestRetriedFreshTurn` red; `SaveRetried` without the `Point` -> `TestRetriedContinueTurn`, `TestRetriedFreshTurn` red, and live `TestRetriedTurnKeepsTheConversation`, `TestIntegrationWebChat` red; a fresh retried turn without `SeedText` -> `TestRetriedFreshTurn` red.
- mutation (live retry rows, `Bridge.SecondModel`): `RETRIED` cut to `error,cut_off,empty,invalid,unusable,no_key` (no `refusal`, `rate_limited`, `timeout`) -> `TestRetryAnswers` red for `retry-refusal`, `retry-held` (timeout) and `retry-overloaded-late` (rate limit), and `TestRetriedTurnKeepsTheConversation`, `TestIntegrationWebChat` red. Three edits at once, told apart by the test that went red: the failure text dropped once the retry was sent -> `TestRetryFails` red (`retry-refusal-then-error`); `RetryItemOf` falling back to `<runner>Retry` and `RetryConfigured` always 1 -> `TestNoSecondModel` red; `daily_cap` in `RETRIED` -> `TestNeverRetried` red.
- mutation (Provider): `EntryName` ignores the item -> `Install.Provider` `TestEntries`, `TestApplyCaFile` red; the mock-key flag emptied for retry items -> `TestEntries`, `TestApplyCaFile` red. mutation (no sampling): `ClearSampling` does nothing -> `Bridge.SessionConfig` `TestNoSampling` red.


**Code-review stage (2026-11-05, warm throwaway `e17s2cw`, lane A).** Each mutation was applied to one file, the named class was run, and the file was restored from a backup and confirmed byte-identical (`md5`). `git status --short` showed the same file set before and after the mutations.
- mutation (U-281): `RETRYSKIPPED` back to the old wording ("...because no time was left within the 110-second limit.") -> `Bridge.Decide` `TestRetrySkipped` red ("in the words the lead ruled (U-281)").
- mutation (R2, CLASSIFICATION clause): the `ToolParameter(..., "CLASSIFICATION") '= "safe"` test dropped from `ToolsetsReadOnly` -> `Bridge.Decide` `TestToolsetsReadOnly` red (risky read-only tool; the mixed list).
- mutation (R2, per-call hook clause): the `Policy.Gate HookFor(...) '= ""` test dropped -> `Bridge.Decide` `TestToolsetsReadOnly` red (the hooked tool). The URI and compiled-class guard is an equivalent mutant: with it replaced by `If 0`, `%New` on a URI or an unknown class throws and the method's `Catch` gives 0, so the test stays green.
- mutation (bad `RetryItem`, disabled): `If 'enabled Quit "it is disabled"` dropped from `RetryItemProblem` -> `Bridge.Decide` `TestRetryBadItem` red (the retry was sent, and no "disabled" warning).
- mutation (AC5, the retry path): `SessionConfigFor` sets `temperature` 0.5 in the config only while `Retrying` -> `Bridge.SecondModel` red: `TestRetryAnswers` (retry-refusal: no answer from the second model), `TestRetriedTurnKeepsTheConversation`, `TestIntegrationWebChat` and `TestDiagnosisRetried`. The mock refuses the sampling parameter, so the live retry assertions pin AC5's no-sampling clause on the retry request itself.
- mutation (stored history, delta records): `StoredMessages` ignores delta records (`If record.%IsA("%Library.DynamicArray")` replaced by `If 0`) -> `Bridge.Conversation` `TestStoredMessagesSkipsBadRecords` red, on both orders. No other test caught it.
- mutation (the statement's coverage): `Test.Agent.Runners` `INVENTORYRUNNERS` cut to the three first runners -> `Install.SecurityOverview` `TestInventoryStatement` red.
- hermeticity (`Install.Provider`): the stack was dirtied with QA's `EntryName` mutation (run, then restored). The old shape of the test, without the new `Run()` before each snapshot, went red on the next unmutated run ("and the entries and rows are as they were", QA's flake). After a second dirtying, the patched test passed.

**Rework iteration 2 (DW-725, warm throwaway `e17s2i3w`, lane A).** The mutation was applied to one file, the class named was run, and the file was restored from my own backup and confirmed byte-identical (`md5` c27eda88c5e45f858bba03c86166c539 before and after; `git status --short` unchanged).
- mutation (DW-725 test 1, re-run by code review on the committed form, warm throwaway `e17s2c3w`): the retry path points the link regardless of lateness (`If '..RetryIsLate(request) {` replaced by `If 1 {` in `Adapter.Agent` `SaveRetried`) -> `Bridge.Conversation` `TestRetryMovesTheLinkOnlyWhenOnTime` red: "a reply with a text and SessionRotated 0", "the link still names S1: the late retry did not point it", "and the late retry saved no AI session", "with SessionRotated 0" and "and the link still names S2, the session of the on-time retry". The on-time assertions and the Usage-row count stay green under it, as they should. (The implement stage ran it on the pre-patch shape, `If ..RetryIsLate(request) Quit` before the `Try`.)
- mutation (DW-725 test 2, the on-time half, code review, `e17s2c3w`): `RetryIsLate` always 1 (`Quit 1`) -> `Bridge.Conversation` `TestRetryMovesTheLinkOnlyWhenOnTime` red ("with SessionRotated 1", "and the link names the retry's new session S2"), and `TestRetriedContinueTurn`, `TestRetriedFreshTurn` and `TestRetriedPointFailureKeepsTheReply` red.
- mutation (DW-725 test 1, the cost clause, code review, `e17s2c3w`): `AnswerRetried` answers a late retry with a made-up reply before `Converse` (no model request) -> `Bridge.Conversation` `TestRetryMovesTheLinkOnlyWhenOnTime` red on exactly "with one model request" and "its model request is counted: one Usage row under the DecisionRef".
- Each code-review mutation was applied to `Adapter/Agent.cls` alone and restored from the stage's own backup (`md5` 7d4e50dec2e376a53a4a81c3a62047a9 before and after each, `git status --short` unchanged); the class passed again on the same stack after the last revert. Test 3 (a late first attempt after an on-time retry) is `TestRetriedContinueTurn`, pinned by the earlier `Point ignores expected` line.
- mutation (the other half of the lateness signal, `Decide` side): the fallback of the retry's timer is recorded under a new ref instead of the decision's `DecisionRef` (`TryRetry`'s last `RecordFallback`) -> `Bridge.Decide` `TestRetryAfterTimer` red ("the row of that fallback has the DecisionRef that the retry request carried"), and `TestTimerFallback` red; file restored from my own backup, `md5` 639ca1d05a2831161911e04d919e7cbc before and after.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Rework iteration 2 closes the two [Owner] items. DW-725: a late retry moves nothing. `Adapter.Agent.RetryIsLate` is true when `Decide` has already recorded the decision of the request's `DecisionRef` (it does so when the retry's timer fires), and `SaveRetried` then saves no AI session and does not point the link; the retry's `Usage` row stays, so its cost is counted. An on-time retry moves the link as before. U-286: the one sentence in `docs/bridge-guide.md` is replaced with the ruled text.

**Files changed.** `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` (the guard), `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls` (`TestRetryMovesTheLinkOnlyWhenOnTime`), `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls` (one assertion in `TestRetryAfterTimer`), `docs/bridge-guide.md` (one sentence), and this spec.

**Review.** 20 findings: patches applied 3 (all low: the retry-timer Ref assertion, `RetryIsLate` private, the read inside the Try), deferred 0, rejected 17 (each reason is in the Review Triage Log).

**Follow-up review recommended: false.** Patched counts: high 0, medium 0, low 3. No high was patched in this follow-up pass.

**Verification.** On the warm throwaway `e17s2i3w`: `OcuTalon.Test.Bridge.Conversation`, `Decide`, `SecondModel` and `CodeRules` pass. The DW-725 mutation (the guard removed) turns `TestRetryMovesTheLinkOnlyWhenOnTime` red, and the Decide-side mutation turns `TestRetryAfterTimer` red; both files restored byte for byte. `bash docker/tests/test-bridge-guide.sh`, `test-boundaries.sh` and `test-class-rules.sh` pass. `ci/warm.sh down` ran.

**Residual risks.** Lateness is read at one instant by the runner, so a retry that ends after `T2` but before a busy `Decide` has processed the timer, or a timer that fires between the check and the `Point`, can still move the link (Design Notes item 24); closing it needs a deadline in the request or a second check with a revert. No live case makes the retry late; the late-retry test is in process.
