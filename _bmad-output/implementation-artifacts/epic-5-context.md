# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds and grouped by the settle rule into one diagnosed incident, which moves through a fixed state table and is noticed with what broke. The heartbeat checks each watched production every minute, and OcuTalon never gives a false all-clear. All of that is built. The one remaining story, 5.11, is a fix-forward. Since Epic 4's demo guide merged in, the real `FailurePoller` and `IncidentManager` turn real failing Orders messages into real, noticed incidents, and the guide's tests don't clean those up. 5.11 makes those tests hold again, so the integrated branch stays green and each case's guide shows the step its own rows say.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident
- Story 5.10: Epic 5 burn-down
- Story 5.11: The demo guide's tests hold now that incidents are real

## Requirements & Constraints

**Story 5.11 (DW-305). Two criteria, both red twice in CI, so this is not a flake:**
1. **Clean up after the real press.** The floor case that presses Break the feed for real is M4 in `web/e2e/floor/guide.spec.ts`. When it ends, no incident or failure group that its press caused may remain for the FLOOR session. That includes one the real `IncidentManager` records or notices after the case's batch clean-up has run. The next case's guide must open at the step its own rows say. The cases that went red are M7 ("the page opens at step 3") and M9 ("while step 5 is current the box is the secondary style").
2. **Earlier tests' incidents stay invisible.** Some tests compute a new watching session's guide: `Test.Live.GuideRefresh` in the lane-b shard, or any floor case. No incident left by earlier tests that sent real failing Orders messages may be visible to that session, whichever test made it. The cases that went red are `TestHookPublishesOnChange` and `TestEventsBodyServesTheGuide`.
- The ruling that created 5.11: the guide tests and their support code clean up the incidents that a real press or untagged failures leave. Fix it in the tests, not in product behaviour. Paths that another epic also edits go to the orchestrator.

## Technical Decisions

**How an incident becomes visible to a session (the ownership rules):**
- Every REST read and the guide go through one ownership API, `OcuTalon.Data.Ownership`. It takes the caller's `SessionRef` from the CSP session.
- A session sees its own incidents. On a local install, it also sees the `instance` incidents of every production it watches, and their approval requests.
- Only incidents whose `NoticedAt` is set are visible. Until the notice, the snapshot, the guide and Break the feed's availability all leave the incident out.
- `Session.Recipients(ownerRef, incidentRef)` gives the sessions that receive an incident: the owning session; for an `instance` incident, every session watching that production; none for owner `eval`. The notice and the `incident` events go to each recipient's stream.
- (inference, as built) The visibility filter matches on the incident's `OwnerRef` (a `SessionRef` or `instance`), `Namespace` and `Production`. It ignores the incident's state, so closed incidents stay visible too.
- On a local install, each IRIS user has one durable session. (inference) So every floor case signed in as the same user shares one FLOOR session, and whatever one case leaves, the next case sees.

**Scope (AD-4):**
- A failure tagged with a session's `TraceRef` as its `SuperSession` belongs to that session, on any install. An untagged failure has scope `instance`.
- Break the feed tags each of its 50 orders with the session's `TraceRef`, so a press makes the session's own incident.
- A test that sends untagged failing Orders messages makes an `instance` incident. Every session watching Orders can see it.
- On the online demo, only Orders can be watched, so `instance` scope never arises there.

**What gets picked up and noticed:**
- `FailurePoller` polls every 3 s, and only watched productions. It reads above `WatchMark`, starting no earlier than the earliest watch's `CreatedAt`.
- A failure is a header with `Status` 8, or an event-log row of type 2 or 6 with no `SessionId`.
- `IncidentManager` skips a failure it already holds.
- Settle rule: the notice step starts after 10 s without a new same-cause failure, or 30 s after the first failure, whichever comes first. Diagnosis follows. A typical notice comes 30 to 35 s after the press (NFR-7 allows 60 s). So an incident can be created and noticed well after a test's clean-up has run.
- The notice (Story 5.8) sets `NoticedAt` for two results:
  - a fallback (refusal, timeout, any other fallback): the incident is open with variant `fallback`;
  - a usable diagnosis with no fix in the fixed set, `unknown` included: open with variant `no_fix`.
- A usable data-format diagnosis is stored and **left unnoticed**, so it stays invisible. Story 7.2 will send its with-fix notice, moving the incident to `awaiting_approval`. (inference) So a clean-up must not depend on which diagnosis the mock gives.
- An open incident (fallback, no fix, rejected or expired) never closes on quiet in demo mode. Only Dismiss closes it. A leftover one keeps Break the feed inactive for good.
- `IncidentManager` is the product's only writer of `Incident` and `FailureGroup` rows. Everything else asks it with `IncidentCommand`:
  - `dismiss`, only from a recipient session;
  - `closeForReplay`, only for a resolved incident;
  - `closeQuiet`.
- (inference) Test fixtures already write these rows directly. Criterion 1 says no incident or group may *remain*, which reads as removing them, not only closing them.

**Guide rules. `OcuTalon.Demo.Guide.Compute(SessionRef)` is the only source of guide state.** A step is done only from the session's real state:
- Step 1: an Orders production watch exists.
- Step 2: a reminder exists, pending or fired.
- Step 3: the notice of the session's Orders incident (with fix, fallback or no fix) arrived in the current run, so `NoticedAt` is set.
- Step 4: that incident's approval request has been answered.
- Step 5: the trace-opened marker is set.

Break the feed's state:
- inactive, "not watching", while there is no Orders watch;
- inactive, "incident in progress", while the session's Orders incident is open (including after a rejection, until it is dismissed), awaiting approval or fixing, or while a run under 3 minutes old has no notice;
- active otherwise, including while the incident is resolved.

Other guide rules:
- **Run again** starts a new run epoch. It resets the guide's markers and never the session's data.
- (inference, as built) The current run starts at the epoch's latest `BreakFeedRun`. Without one, it starts at `GuideState.RunStartedAt`. Without that, it covers the whole session. So deleting a case's `BreakFeedRun` rows makes the window wider, and an earlier noticed incident still counts for step 3.
- With demo mode on, `Live.Publish` recomputes the guide after it publishes `incident`, `approval`, `check`, `reminder`, `chat.message`, `pairing` or `breakfeed.progress`. It publishes `guide.state` only when the state changed. So a stray incident event can also publish a `guide.state`.
- `StatusMonitor`'s 15 s tick recomputes the guide for open runs, and so does each marker write.
- The guide's tests drive each step with fixture `BackgroundCheck`, `Reminder`, `Incident`, `ApprovalRequest` and `BreakFeedRun` rows.

**Conventions:**
- Tests are named `OcuTalon.Test.<Area>.<Subject>`.
- Floor specs under `web/e2e/floor/` run only in the `live:floor` unit. `Test.Live` runs in the `lane-b` shard, and each shard is its own compose project.
- Times are UTC ISO 8601 to the second.
- The files 5.11 names are in Lane B's areas (`web/`, `.Live`, `.Demo`, `.Data.Ownership`). `Incident`, `FailureGroup` and `WatchMark` are Lane A's.

## UX & Interaction Patterns

- Step markers come only from `guide.state`, never from a click. The page opens at the current step.
- The Break the feed box:
  - active, it is the attention style, with a "Next step" tag while it is the current step;
  - while step 5 is current, it is the secondary style;
  - inactive, it shows the hint "Finish the current Orders incident first…".

## Cross-Story Dependencies

- Already built in Epic 5:
  - 5.2: the poller and the failure's scope;
  - 5.3: the settle rule and `NoticedAt`;
  - 5.5: the state table, dismiss and `closeQuiet`;
  - 5.8: the fallback and no-fix notices.
- Merged from other epics:
  - Story 2.2: the ownership API's `NoticedAt` filter and `Session.Recipients`;
  - Epic 4: 4.2 (`Guide.Compute`), 4.3 (the real 50-order batch, and `closeForReplay` before a new run), 4.4 (the box) and 4.7 (the step 4 variants and the finish state).
- Story 7.2 will notice data-format incidents too, with the dry run and `Raise`. Clean-ups should already handle that case.
- If 5.11 is dropped, DW-305 goes to an Epic 6 story instead. Epic 6 owns `Test/Live` next.
