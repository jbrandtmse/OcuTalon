# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds and grouped by the settle rule into one incident. The incident gets a plain-English cause, the element at fault, a proposed fix and evidence, and moves through fixed states. OcuTalon never gives a false all-clear. Stories 5.1 to 5.11 have built all of that. Epic 5 is re-opened for one launch-risk hotfix, Story 5.12, which must merge into the feature branch today, before the online demo goes public. On the demo host, correct diagnoses were refused as `invalid` because one evidence reference was longer than the 32-character limit on `DiagnosisPayload.Evidence`. It happened to one in six diagnoses in the load run, and later to 2 in 10. The visitor got the fallback notice with no fix and could not finish the demo path. 5.12 makes those replies pass, so Break the feed always ends with a fix the visitor can approve.

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

## Requirements & Constraints

Story 5.12 is the only open story.

- **Accept long references.** `DiagnosisPayload.Evidence` accepts each reference up to 128 characters. A reply with a reference over 32 and at most 128 characters passes `Decide`'s check, records no fallback, and gives the with-fix notice: cause, fix, dry run and approval request.
- **Prompt and class agree.** The diagnosis prompt (`OcuTalon.Agent.Diagnosis`) still asks for short references and states the new limit: at most 128 characters each.
- **Replay the host's replies.** Two tests replay, through the same check, the two replies the host recorded, and both pass. Each fixture is copied byte for byte from Story 5.12's block in `epics.md`:
  - 11:45:50Z: the sixth reference is 42 characters;
  - 12:01:54Z: the first reference is 33 characters.

  Neither fixture holds any host detail.
- **Audit every reply class.** Cover the attention decision (`DecisionPayload`), the diagnosis, the chat turn's command reply, and any other class with a `MAXLEN` that its prompt names. Every length a prompt states must match its class. No free text the model writes may be held in a property tighter than 32 characters. The fixed value lists (`outcome`, `causeCategory`, `fixKind`) are exempt. The spec lists each limit it widens, and gives the reason for each limit it keeps.
- **Trace the check's error.** When a reply is refused as `invalid`, the decision's trace also records the check's own error text: which property failed and why. That text is internal:
  - it never reaches the page, a notice, the phone or the model;
  - it names no key or secret.

  A test pins it with a reply that breaks one rule.
- **Footprint and gates.** Touch only the payload class, the prompt classes, Decide's fallback trace, their tests and the fixture. CI is green on every workflow, and the evaluation set on the mock passes unchanged.
- **Out of scope:** one retry on an `invalid` reply. It would add a model call inside the 20-second diagnosis budget, so it is a measured follow-up for Epic 30, which the Contest Planner decides. The step 2 retry on a second model is also separate.
- **Timing.** The notice comes at most 60 s after the press in 19 of 20 runs. The diagnosis takes at most 20 s of that, and a typical diagnosis needs one model request.

## Technical Decisions

- **Reply checking.** Diagnosis and Triage each answer with one JSON object. It is checked against the `%JSON.Adaptor` class named in the runner's `ReplyClass` setting: `OcuTalon.Watch.Msg.DiagnosisPayload` for `DiagnosisAgent`, and `OcuTalon.Bridge.Msg.DecisionPayload` for Triage. Only the bridge decides that a reply is unusable. JSON that fails the check is `invalid`.
- **The fallback route.** Any fallback has outcome `tellnow`, `Fallback` true and its `FallbackReason`. It triggers no fix or approval request, and its decision message is flagged as a fallback in Visual Trace. The incident is grouped by the fixed rules and gets the fallback notice.
- **Check order.** `Decide` runs the reply filter on each property named in the class's `FILTERED` list, then validates again. The reply filter is `OcuTalon.Checks.ReplyGuard`, from Story 5.7. Every stored model text is filtered before anything is recorded.
- **The fix check comes last.** It is the kind's parameter check, `OcuTalon.Fix.Kind.Check`, run against the keys of the sample body in the request's evidence pack. It reads that pack through `OcuTalon.Bridge.ReplyCheck`, which `Decide.Interpret` begins and clears on every exit. With no pack, every fix is refused. (inference) So a replay test must give the check a pack whose sample body holds `OrderDate`. Otherwise the reply fails for a reason other than length.
- **Agents.** The agents are `%AI.Agent` subclasses with static `XData INSTRUCTIONS`. A CI check fails any INSTRUCTIONS block that contains `{{`. Diagnosis runs on `claude-haiku-5-5` at effort `high`, with no sampling parameters.
- **What the trace holds.** Decision and reply messages carry `Outcome`, `Reasons`, `Confidence`, `Fallback` and `FallbackReason`. Agent steps go through the bridge's redactor and are emitted by `Decide` as `AgentStep` messages. A fallback also carries the steps buffered by a failed Chat. Model keys and bot tokens never appear in Visual Trace, logs or audit entries. (inference) Keep the check's error text off everything the page or a notice reads, including the `decision` and `incident` events and the stored reasons the user sees.
- **The mock and the evaluation set.** The mock picks a diagnosis's default script by the agent's `MOCKKEY`, `diagnosis`. Lane A adds mock behaviour only as files under `ci/mock/scenarios/A/`. The evaluation set runs on the mock on every push. It goes through the product path (`EvidencePack.Build`, `Decide`, `IncidentManager`) with owner `eval`.
- **Conventions:**
  - Tests are `%UnitTest` classes named `OcuTalon.Test.<Area>`. Agent, Bridge and Watch are areas of the `lane-a` shard.
  - Only the owning lane edits a class. Epic 5 is Lane A.
  - Times are UTC ISO 8601 to the second.

## UX & Interaction Patterns

- An `invalid` fallback shows the UX's generic reason: "the model's reply couldn't be used". The check's error text never appears to a user. It lives only in the trace, and everything a user reads stays plain English.
- On the demo path, a usable data-format diagnosis must give the with-fix notice: the count, the start time, the cause, the fix summary, the dry run and an Approve or Reject request. A fallback blocks the visitor until they dismiss the incident.

## Cross-Story Dependencies

- 5.12 builds on these stories, all done and on the feature branch:
  - 1.6: the `invalid` classification and the fallback flag in the trace;
  - 1.5: agent steps;
  - 5.4: `DiagnosisPayload`, `Agent.Diagnosis` and the evidence pack;
  - 5.7: the reply guard;
  - 5.8: the fallback notice;
  - 7.1: the fix-kind check through `ReplyCheck`;
  - 7.2: the with-fix notice with its dry run and `Raise`.
- Epic 30 owns the possible retry on `invalid`, which the Contest Planner decides after measuring.
- Story 5.11 (the guide tests' incident clean-up) is done and imposes nothing on 5.12.
