# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Incidents get more governed fixes: suspend, resume and reroute, plus setting rollback later. Failures are linked to recent setting changes. The on-call person is paged, with escalation to a backup. Partner delay notices are drafted and sent only after approval. Every incident closes with a summary written by code. Queue backlog and saved SQL query watches report between digests (Could). The next story is 23.12, a judge-visible web fix: rejecting a fix is a featured More to try step, so the status rail must stop listing a request as soon as the user rejects it. Lane D runs it after Story 23.9. It ships in 1.0.8 only if it merges before the cut, otherwise in 1.0.9.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Name the setting change behind an incident and offer its rollback (waits on Story 36.1)
- Story 23.4: Decide when to page the on-call person and when to escalate to the backup (waits on Story 36.2)
- Story 23.5: Draft partner delay notices that are sent only after approval (done)
- Story 23.6: Write an incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Watch a saved SQL query as a read-only SQL user (waits on Story 36.2)
- Story 23.9: Resume a suspended item after its incident closes (done)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (done)
- Story 23.12: Take a rejected request off the status rail at once (next)

## Requirements & Constraints

- **Rejected request leaves the rail (23.12, DW-1159):**
  - After Reject, the rail's Approval requests must drop the request within 5 s of the press. It must not wait for a later poll to bring the `approval` live event.
  - This applies to a Reject pressed on the web page and to one pressed on the phone view.
  - A request the user has not answered stays listed.
  - CI needs a browser test for each case that presses Reject and asserts the request is gone within 5 s.
- **Approval rules that still hold (FR-8):**
  - The first answer wins. Other channels show the result and where it came from within 5 s, and a late press gets an "already answered" reply.
  - A Reject means no action: the user is told and the rejection is recorded. The incident returns to open unless another of its requests is still pending or a fix is still running.
  - On the online demo, only the session that owns a request can answer it.
  - Live updates must reach the page within 2 s (NFR-9). CI checks these bounds against the mock on every run.
- **Fixes and undo:** every fix has a dry run that changes nothing, and it runs only from the approved row. Each undo is one approved action. A suspend or a resent copy that OcuTalon made is attributed to its fix, never reported as a new failure or a new state change.
- **Suspend hold (23.9, done):**
  - An incident that holds an active suspend closes only by Dismiss, or by the quiet close once a resume has ended the hold.
  - After a held incident is dismissed, `Checks` reports the still-disabled item once.
  - The online demo still refuses suspend and resume, and offers only reroute.
- **Partner notices:**
  - They go only to configured contacts, using the exact approved text.
  - On the demo they go to the Simulated mailbox, and no text may imply that a real email was sent.
  - A notice states only an outcome that OcuTalon's own records support. With no Outcome fact, it doesn't say whether the orders went through.
- **Summaries** are composed by code with no model request. Their cost is the sum of the incident's usage rows.

## Technical Decisions

- **Live store (AD-12):**
  - The page loads `/state`, then applies events from polling every 1 to 2 s. The WebSocket is used on local installs only; the online demo polls only.
  - Each event is the full current public view of one entity, keyed by its `Ref`, never a delta. Events are applied idempotently, and a skipped `Seq` reloads the snapshot.
  - The page decides nothing itself, and text is the server's (AD-32).
  - `live-store.ts` is framework-free and pure: it returns a new store and runs under plain Node.
- **Where 23.12's gap sits:**
  - The rail list, its heading count and the header's Status button count all come from `pendingApprovals(store)` (`rail/rail-view.ts`), which filters on `state === 'pending'`.
  - The store's approvals change only through `approval` events, which `Core.BridgeSink.Approved` publishes asynchronously.
  - The press reply goes only into `AnswerPress.local` (`approvals/answer-press.ts`). That class is shared by the chat card (channel `web`) and the simulated phone's request message (channel `phone`).
  - A 200, 409 already-answered or 409 expired reply carries the request's payload (`answerOutcomeOf`).
  - The phone's buttons never follow the store's `approval` event. They follow only the server's edit of the phone message and the phone's own press.
- **Approval ownership:** answers go through AnswersIn → AnswerOps → `Approval.Answer`, and `IncidentManager` alone moves incident state.
- **Back end:** fix kinds live under `OcuTalon.Fix.Kind`; audit goes only through `OcuTalon.Bridge.Audit`; text uses `OcuTalon.Msg.Catalog` keys. Tests are `OcuTalon.Test.Fix`, `.Watch` and `.Checks`, with CI mock scenarios under `ci/mock/scenarios/A/`.
- **Browser test conventions (`web/e2e/`, Playwright):**
  - One worker against one real stack. Browsers run in UTC with the en-GB locale.
  - Each case seeds run-stamped rows through `Test.Data.Fixture` (helpers in `e2e/support/iris.ts` and `approvals.ts`) and removes them in `finally`.
  - Approval events come from `BridgeSink.OnEvent` with fixture rows.
  - A live-update assertion first waits for the page's `data-session-seq` to reach the helper's returned Seq.
  - Folders map to CI units:
    - `rail/` and `phone/` are in the `sign-in-2` unit, whose run time has already forced splits.
    - `answers/` (phone answers, NFR-9 bounds) and `cards/` each have a unit of their own.

## UX & Interaction Patterns

- The rail heading carries a live count, for example "Approval requests (1)", and is announced with that count. An empty list reads "None waiting." Sections never collapse by themselves.
- In the 1024–1279 px band the rail is a drawer behind the Status button, which shows the same count.
- An answered request shows its answer line ("Rejected from the simulated phone at 14:15") in place of its buttons, on every channel.
- After a rejection the guide keeps its step 4 hint.
- Each fix keeps its own dry run and result band on the approval card. The demo guide describes suspend and resume only as working "on your own install".

## Cross-Story Dependencies

- Story 23.12 follows 23.10's last criterion and is not a rework of 23.10. Its prerequisites have merged: 21.2, 0.26 and DW-1123.
- Gaps for 23.12's spec to settle:
  - **"Phone view":** it most likely means a Reject on the simulated phone (channel `phone`). It could also mean a phone-width layout. The epic doesn't say which.
  - **The 5 s bound:** with fixture rows, `Approval.Answer` waits about 5 s before it replies (`e2e/answers/answers.spec.ts`). A fix driven by the reply may therefore miss 5 s measured from the press.
  - **AD-12:** whether the reply's server payload may update the store is a decision for the spec to record.
  - **Approve:** the story names only Reject.
- Story 23.3 waits on Story 36.1. Stories 23.4 and 23.8 wait on Story 36.2. Real email for partner notices through `EmailOut` is parked under Epic 21.
