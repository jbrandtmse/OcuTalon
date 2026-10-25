# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page. A user chats with OcuTalon and sees each reply with its decision, cost and trace link. The page also has a live status rail and banners, all updated without a reload. Every message gets exactly one reply, and the conversation survives a restart.

Stories 2.1 to 2.16 are done. Since then the branch has merged the feature branch, which brought Epic 1 (Lane A): its real `Decide`, runners and agents replaced Epic 0's stub `Decide`. The one remaining story, fix-forward Story 2.17, makes Epic 2's tests assert what the merged system does. That way the merged tree is green for the right reasons, and every Epic 2 promise is still pinned by a test that can fail.

## Stories

- Stories 2.1 to 2.16 (done): the frame; the session and live updates; routing commands; the turn pipeline; chat; decisions; outcome routing; the rail; Visual Trace; banners; lost contact; the accessibility floor; Visual Trace from the page; keyboard and labels; layout widths; the floor in three browsers
- Story 2.17: Epic 2's tests follow the real Decide

## Requirements & Constraints

- **The red run, one root cause.**
  - Three IRIS groups are red:
    - `image`: `shard:lane-b` fails in `OcuTalon.Test.Core.ConversationProduction`, `RoutingProduction` and `ThreadProduction`.
    - `browser`: `live:sign-in` has 14 failed and 78 not run. Each failure waited 20 s, so the unit ran out of time. `live:demo-path` passed.
    - `production`: `live:production-restart` fails at row 20.
  - Passing: `shards`, `install-fresh`, `install-upgrade`, the hosted checks, and the web node tests (565).
  - Every failing assertion expects the stub's reason `unusable`. Keyless stacks now answer `no_key`.
- **What Story 2.17 must deliver.**
  - Each test asserts the merged outcome: the reply text, the fallback reason, the turn's states and events, and the Decision rows that the real Decide now keeps.
  - Every criterion these tests pinned stays pinned by a test that can fail. Show a red for each.
  - No product change, unless a test exposes a real integration defect. Then fix it, with a test.
  - Restoring a stub Decide for the tests was rejected, because it hides the integration. How the tests are fixed is a veto item (U-68). This is fix-forward 1 of 1 for the epic.
  - All six IRIS groups and the hosted checks pass on the merged tree. Rerun each red unit alone: `bash ci/iris.sh shard lane-b`, `bash ci/iris.sh live sign-in`, `bash ci/iris.sh live production-restart`.
- **Where the stub's outcome is asserted:**
  - **`ConversationProduction`:**
    - `conversation.turnFallback|unusable|` on the turn row and on the done `chat.message`.
    - The Outbound's slots `{"fallbackReason":"unusable"}`.
    - Empty `TriageDecisionRef` and `TurnDecisionRef` ("no decision to keep").
    - The reply's Delivery row with an empty DecisionRef.
    - Both reconcile tests expect `unusable`.
  - **`RoutingProduction.TestUntrustedItemReachesTheWebChat`:**
    - The card's reason `unusable` and its empty DecisionRef.
    - The card text "…Why now: the model's reply couldn't be used", and the same in the event payload.
    - The ItemDecision `tellnow|1|unusable|` with no DecisionRef.
  - **`ThreadProduction.TestStubFallsBackAfterTheRestore`:** expects `unusable` once the double is swapped out. The swap itself (`UseDouble`, through `Ens.Config.Production` and `UpdateProduction`) now restores the real `Decide` with its settings: HostSinkClass `OcuTalon.Core.BridgeSink` and ReplyFilterClass `OcuTalon.Checks.ReplyGuard`.
  - **`docker/tests/test-production-restart.sh` row 20:** `CHK|turns|done|2|conversation.turnFallback|unusable|done|1|…|unusable`.
  - **`web/e2e/api/api.spec.ts`, Story 2.4's row:** `fallbackReason: 'unusable'` in the done event and in the reload's snapshot.
  - **`web/e2e/chat/chat.spec.ts`:** the `FALLBACK` constant (the generic sentence) in C2 to C4, C7, C9 to C11 and C15. C15 also asserts "no decision row": no cost and no Details button.
  - **Stale comments:** headers in these files, and in `DecideDouble`, still call `Decide` Epic 0's stub.
- **Keep unchanged:**
  - The probe-level unit tests (`ConversationTurns`, `Intake`, `Routing`) hand requests to `DecideDouble` through a shadow instance, with no production. They pin every reason, the error status, and an unknown reason becoming `unusable`. Once the production tests follow the real Decide, they are the only pin of the error-status path.
  - Seeded-turn specs (`decision.spec.ts`, chat C12).
- **Newly live:** banners B6 skipped while `decideIsStub()` was true. That helper reads `Decide`'s `STUB` parameter, which the real class no longer has, so B6 now runs.
  - B6 checks the no-key banner from the real `/state`, and a reply "I couldn't answer that: no model key is set. Nothing was changed." with the Fallback flag.
  - It has never run green in CI. Every case that did not run in the red run needs checking too.
- **Time budget:**
  - Before the merge, `live:sign-in` took 413 s locally (190 passed, 2 skipped).
  - Its deadline is 1200 s in CI and 540 s locally.
  - The `browser` job ran 795 s in CI.

## Technical Decisions

- **The real Decide with no key.** Every throwaway starts with no key on purpose. The CI override sets the mock's base URL and `OCUTALON_MOCK_KEY_HEADER=1`, but no key.
  - **Precheck:** `Keys.Absent(runner)`, read live in Decide's job, gives `no_key`. Nothing is sent: no runner request, no timer, no agent steps, and nothing in the mock's log. `Absent` is also 1 when no production is active or the runner item is missing. If a request were sent anyway, the runner's failure text (`@{env:` … `has no value`) would also classify as `no_key`.
  - **The fallback row:** `RecordFallback` writes one Decision row per (ItemId, kind): outcome `tellnow`, `Fallback` 1, reason `no_key`, and no reasons, confidence, payload or token totals. It then fires `decision.recorded`, and BridgeSink publishes a `decision` event on the session owner's stream.
  - **The answers:**
    - A decide request gets a DecisionResponse with a DecisionRef.
    - A turn gets a new Reply with `Fallback` 1, `no_key` and the DecisionRef, and no text.
  - **What changes for a chat turn:**
    - It ends done with both `TriageDecisionRef` and `TurnDecisionRef` set.
    - For a fallback, the shown decision is the turn's. Its Ref becomes the Delivery row's DecisionRef, and it fills `decision` and `turnCost` in `chat.message`.
  - **What changes for an untrusted Item:** its ItemDecision, Notification and card carry the DecisionRef and `no_key`.
  - **Unchanged:** the request counts (two Decide requests per turn, one per Item).
- **Busy and repeats:**
  - A Busy answer comes only when a user turn's conversation lock is held. With no key, nothing holds it.
  - A repeated decide for an ItemId is answered from the existing row.
  - A repeated turn for an ItemId is refused with an error, which Conversation ends as `unusable`. That is DW-126, which is on the decision sheet, so leave it. Row 20's seeded turns have no rows, so they get `no_key`.
- **With the CI mock (optional):**
  - Lane A's `Test.Agent.RunnerFixture.PointKeys` and `RestoreKeys` point the runners' Config Store entries at the mock key and restart the runners. Call them; never copy or edit them.
  - The default scripts then answer:
    - `triage` answers `digest`. A user's digest becomes `tellnow`, with the "always answered" line.
    - `chat` calls `list_productions` and then replies "The CI mock looked at the productions.". The turn gets Usage rows and agent steps.
  - An unmarked untrusted Item is then triaged `digest`, so no card is made (DW-106).
  - Never switch keys on the shared `live:sign-in` stack. It runs one serial worker, and every spec assumes a keyless stack.
- **Fallback rules:**
  - Only `Decide` classifies a reply. The order: `no_key`, `daily_cap`, `budget` and `too_large` (prechecks; the request is never sent), then `timeout`, `rate_limited`, `error`, `refusal`, `cut_off`, `empty`, `invalid` and `unusable`.
  - `Conversation` never classifies a reply. An error status, no answer, an answer of the wrong class, or a reason outside `FALLBACKREASON` all become `unusable`.
  - **The reply text:** catalog key `conversation.turnFallback`, "I couldn't answer that: {fallbackReason}. Nothing was changed.", rendered only by `Msg.Catalog.Render`.
  - **Reason words (`REASONKEYS`):** `no_key` maps to "no model key is set"; `invalid` and `unusable` map to the generic "the model's reply couldn't be used".
  - **Untrusted-item card:** `notice.tellNowFallback`, "{whatHappened}\nWhy now: {reason}".
  - A fallback never triggers a tool, a fix or an approval.
- **Footprint:**
  - Lane B, this story: `Test.Core`, `docker/tests`, `web/e2e`, `Conversation` and the catalog.
  - Lane A, read only: `OcuTalon.Bridge`, `.Agent`, `.Checks`, `Test.Agent`, `Test.Bridge`, `ci/mock/scenarios/A/`.
  - The contended `ci/iris.sh`, `ci/warm.sh` and `docker/tests/test-ci-config.sh` stay read only.
- **Clean-up:** the real Decide's Decision rows for test items are not fixture rows. `Fixture.Adopt` can record them for `Clean`.

## UX & Interaction Patterns

- A keyless reply reads "I couldn't answer that: no model key is set. Nothing was changed.". The turn indicator still shows "Deciding…", then "Working…", then the reply.
- The reply's strip now has a decision:
  - Line 1: Tell now, the Fallback flag and the turn's cost. A cost of 0 shows as "<$0.0001", and a fallback shows no confidence.
  - The reason sentence "No model key is set." comes first.
  - Then the "Decision details" button.
- C15's strip with no cost and no Details belonged to a fallback with no decision. Confirm on a stack what the strip shows now.
- The no-key banner already showed on every keyless stack, because the old `Keys.Status` stub answered 0.

## Cross-Story Dependencies

- **Criteria that now meet their real path:**
  - Story 2.4: the fallback reply names its reason; the double that forces each reason stays.
  - Story 2.7: its "until Story 1.3 merges" clause has expired, so `RoutingProduction` now covers the real path. N10's 5-second tell-now card holds through the keyless fallback.
  - Story 2.10: the CI test of a start with no key (B6).
  - Story 2.6: the strip of a real fallback decision.
- **Ledger:**
  - DW-106 (Lane B's production tests assert the stub's `unusable`) is this story's root cause.
  - DW-98 (a `decision.recorded` emitted by the bridge reaching the stream) goes to Story 4.3, and DW-128 goes to Story 6.3.
- **Later:** Epic 11 removes `ThreadProduction`'s double swap. It stays valid until then.
