# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds and grouped by the settle rule into one incident. The incident gets a plain-English cause, the element at fault, a proposed fix and evidence, and moves through fixed states. OcuTalon never gives a false all-clear. Stories 5.1 to 5.12 are done. Epic 5 is re-opened under SC-5 for one launch-blocking story, 5.13, and the online demo stays gated until it merges. In the owner's walk-through of the demo, the visitor asked about the earlier failure and OcuTalon could not recall it. There are three reasons. The incident card is an `IncidentManager` notice, not a chat turn, so it never enters Chat's AI session. Chat's toolsets (Reminders, Watching) cannot read past incidents. And `check_status` gives only the latest check, which reads "passed" once the fix has run. Story 5.13 gives Chat a trusted, read-only way to answer from OcuTalon's own records.

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
- Story 5.12: A correct diagnosis is never refused for an over-long evidence reference
- Story 5.13: Ask OcuTalon what happened earlier, and it tells you from its own records

## Requirements & Constraints

Story 5.13 is the only open story.

- **One new tool, `recent_activity`.**
  - It lives in its own class in `OcuTalon.Tools` and is added to the Watching toolset's tool list.
  - It is classified safe and read-only, and declared `TrustedOutput`, so a call never taints the turn or starts a fresh session.
  - Its description tells Chat to call it when the user asks about earlier failures, incidents, approvals or fixes, or about what happened.
- **What it returns.** At most 5 of the session owner's own incidents from the last 24 hours, newest first, each holding only fields that code builds:
  - the production and the item, the failed-message count, and the first and last failure times;
  - the element at fault (shown only when it exactly matches the approved fix's field or an item name), the cause category and the fix kind;
  - the approval's answer (approved, rejected or expired), with its channel and time;
  - the fix result's counts (resent, went through, failed);
  - the incident's state (open, awaiting approval, fixing, resolved or dismissed).
- **Times** are shown in the instance's zone with its zone label, as the catalog's times are (the DW-484 direction).
- **Never in the output:**
  - the model-written cause sentence;
  - any message body or header text.

  Either one would make the output untrusted.
- **Isolation.** On the online demo the tool returns only the session's own incidents, never another visitor's.
- **Nothing in 24 hours.** The tool says so plainly and makes no claim that everything is fine.
- **The demo path.** After Break the feed, the notice, Approve and the result, the user asks "What was that failure earlier?" The reply names the failed count, the element at fault, the approval and the fix result. It contains no all-clear, and the reply guard still applies.
- **Tests:**
  - a gate test that `recent_activity` is read-only and `TrustedOutput`;
  - a test that its output never holds the cause sentence or a message body.
- **Footprint and gates.** Touch only the new tool class, the Watching toolset's tool list, the gate's classification entry, and their tests and mock scenarios. CI is green on every workflow, and the evaluation set passes on the mock.
- **Optional, only if it costs nothing extra:** reminders fired today (trusted) in the same output.

## Technical Decisions

- **Classification.** A built-in tool declares its classification as class parameters of its tool class: `CLASSIFICATION` (`safe` or `risky`), `READONLY` and `TRUSTEDOUTPUT` (1 or 0). A class that holds several tools adds a `<NAME>` suffix for each one. The gate fails closed: an undeclared tool is unclassified and counts as risky. In an untrusted or tainted turn, only safe, read-only calls run. Any allowed call whose tool is not trusted output taints the turn.
- **Trusted output** is built by code from OcuTalon's own records and holds no text from outside a user's untainted turn. The classification convention now names `recent_activity` of `OcuTalon.Tools.RecentActivity` as read-only trusted output, on the same condition as its precedents:
  - `dismiss_incident` (5.9) and `check_status` (5.7) are trusted output because a `Test.Bridge.Gate` test pins each answer to its code-built fields, so a free-text field added later fails it.
  - `recent_activity`'s answer is built by code from the session's own incident, fix-run and approval rows only: production, item, failed count, first and last times, element at fault (only on an exact match with the approved fix's field or an item name), cause category, fix kind, the approval's answer, channel and time, the fix result's counts and the state.
  - It never carries the diagnosis's cause sentence or any message body or header, and `Test.Tools.RecentActivity` pins its answer to those code-built fields.
- **Not Epic 23's incident summary.** That later tool returns the evidence line and the sample error, so it is not trusted output. `recent_activity` must stay off those fields and off the diagnosis's sentences.
- **Data and ownership.**
  - Lane A owns the tables this tool reads: `Incident`, `FailureGroup`, `FixRun`, `ApprovalRequest` and `Decision`. Lane B owns `Session` and the ownership API (`OcuTalon.Data.Ownership`). Only the owning lane edits a class, and Epic 5 is Lane A.
  - Owned records carry `SessionRef` or `OwnerRef`.
  - On a local install, an `instance` incident belongs to every session that watches its production; `Session.Recipients(ownerRef, incidentRef)` resolves those sessions.
  - Reads of incidents leave one out until its `NoticedAt` is set. (inference: do the same here)
- **States.** `IncidentState` is `open`, `awaiting_approval`, `fixing`, `resolved` or `closed`, and `IncidentOpenVariant` (`fallback`, `no_fix`, `rejected`, `expired`) is stored beside it. There is no `dismissed` value. The spec must say how a closed incident is labelled, because Dismiss, `closeQuiet` and `closeForReplay` all close one. (inference)
- **Times.** Stored times are UTC ISO 8601 to the second and are rendered only through `OcuTalon.Data.Time`; on the online demo the renderer adds " ET".
- **Tool results** go through `OcuTalon.Tools.Result` as a dynamic object or plain text, never a pre-encoded JSON string. Results are cut against the step's 10,000-token budget.
- **Naming and labels.**
  - Built-in tool names are defined once in `OcuTalon.Tools.Names`. Other stories that add a tool also add its name to the CI mock's tool-name check (`ci/mock/test/constants.test.mjs`).
  - A step label is a `STEPLABEL` parameter and never holds arguments or model text.
- **The all-clear comes only from code.** `OcuTalon.Checks.ReplyGuard` runs once on every model-written text leaving `Decide` and removes the reserved sentences and the banned all-clear phrases. An all-clear reaches a reply only through `check_status` and `Checks.Render`.
- **Mock and tests.**
  - Lane A adds mock behaviour only as files under `ci/mock/scenarios/A/`. Chat's `MOCKKEY` is `chat`.
  - Tests are `%UnitTest` classes named `OcuTalon.Test.<Area>`; the watch tools' tests sit in `OcuTalon.Test.Watch`, and the new tool's pinning test is `Test.Tools.RecentActivity`.

## UX & Interaction Patterns

- The answer is plain English, built from code-built facts: the count, the element, the approval with its channel and time, and the fix result.
- The reply never uses the banned all-clear phrases: "all good", "everything's fine", "everything is fine", "no issues", "no problems" and "nothing to worry about".
- With nothing in the last 24 hours, the reply says that plainly and makes no health claim.
- Times carry a zone label so that the visitor isn't shown clocks that disagree (DW-484).

## Cross-Story Dependencies

- 5.13 builds on these done stories:
  - 5.1: the Watching toolset;
  - 5.5: the states and variants;
  - 5.7: `check_status` and the reply guard;
  - 5.9: the pinned trusted-output pattern;
  - 7.2 and 7.4: the approval requests and the fix result counts;
  - Epic 3: the approval rows with their answer and channel.
- Epic 23's incident-summary tool is a separate, untrusted tool and comes later.
- DW-484, the agent-written times that carry no zone label, is an Epic 30 ledger entry. 5.13 only follows its direction.
- The online demo's go-live waits on this merge.
