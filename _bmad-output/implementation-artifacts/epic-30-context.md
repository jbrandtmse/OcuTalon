# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 holds the Lane A parts of the demo-path stories that were moved after the demo path (compaction, scheduled purges, exactly-once replay, once-only findings, honest resend results), plus fix-forwards found along the way. Stories 30.1 to 30.6 and 30.8 are done, and Story 30.7, the burn-down, stays deferred until after the v1.0.0 tag. The epic is re-opened for one fix-forward, Story 30.9, for the 1.0.4 release. On the 1.0.3 demo, every "Remember that ..." chat message, typed or sent by the panel's "Ask it to remember" press, gets a Fallback attention decision ("Tell now · Fallback", "The model's reply couldn't be used."), although the chat turn answers and the memory is saved. A person's own message must get a real attention decision, so the strip never reports a failure that didn't happen.

## Stories

- Story 30.1: Long conversations are compacted under the limit (done)
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got (done)
- Story 30.6: The invalid-reply warning names what failed, never the reply (done)
- Story 30.7: Epic 30 burn-down (deferred after the v1.0.0 tag; not part of this re-open)
- Story 30.8: The redactor and the key proof catch every key shape (done)
- Story 30.9: A 'Remember that ...' chat message gets a usable attention decision (backlog, next)

## Requirements & Constraints

**Story 30.9 (DW-890, fix-forward for 1.0.4, placement approved by the Planner).**

- **The outcome.** Every item gets exactly one attention decision. A person's own message is always answered: tell now or act, never ignore or digest. A "Remember that ..." message, typed or sent by the panel, must get a usable decision made under the user's-own-message rule (tell now), not Fallback.
- **Cause first, from evidence.**
  - The demo's Story 30.6 trace warning says `Decide` refused Triage's reply because it is not one JSON object that `OcuTalon.Bridge.Msg.DecisionPayload` accepts (ERROR #5001).
  - There is no "After the reply filter ran" line, so this is not a length, datatype or enum failure.
  - Demo measurements: 1 agent step, about 66 output tokens, 0.9 s.
  - Confirm the cause by reading the code and by reproducing that reply shape on the CI mock. Write the cause in the spec's Design Notes.
  - The ledger's leads are unverified guesses: the decide agent sees or tries memory tools, or the output schema rejects the reply.
- **The fix.** Fix the cause with the smallest change.
  - Don't raise any timeout or `TimerSeconds`.
  - Don't loosen the reply check for any other reply.
  - Don't change the behaviour of any other outcome.
  - Any change to user-visible wording goes to the Contest Planner.
- **Regression test.** A CI-mock test drives a "Remember that ..." user message through the decision, in both forms, and pins that it decides without Fallback. A named mutation that restores the cause must turn it red.
- **Evaluation case.** Add a new case folder, `eval/<case>/case.json`, shaped like `eval/user-turn-productions/`. It states that a "Remember that ..." item must decide without Fallback. Don't change `eval/run.sh`. Update any test that pins the evaluation set's case count or list.

## Technical Decisions

- **A person's message takes two requests.** The path is `WebChatIn`/`TelegramIn` → `Conversation` → `Decide` (`decide`, provenance `user`, `TriageAgent`) → `Decide` (`turn`, `ChatAgent`).
  - `Conversation` renders the input once, with `OcuTalon.Agent.Input`.
  - Only Chat's turn runs tools, `save_memory` among them. Triage has no tools.
- **Triage.**
  - Agent: `OcuTalon.Agent.Triage`, model `claude-haiku-5-5`, effort `low`.
  - Its `XData INSTRUCTIONS` are static, with no `{{` (a CI check).
  - It answers with one JSON object, checked against the runner's `ReplyClass`, `DecisionPayload`: a `%JSON.Adaptor` class with plain-English reasons and a confidence between 0 and 1.
  - A reply that fails the check is `invalid`, which means fallback: outcome tell now, `Fallback` true, and the generic reason "the model's reply couldn't be used". On a person's turn, a fallback is a reply only.
  - An `invalid` reply is retried once on a second model only when a `RetryItem` is configured.
  - For provenance `user`, `Decide` maps ignore or digest to tell now and says so in the reasons.
- **Shared files.** `Agent.Input` places the persona block and the context blocks (core memory, daily notes) as quoted data before the item. Chat's and Triage's instructions are shared-by-entry files: append your own entry and never rewrite another's.
- **Keep the 30.6 warning as it is.** It is built inside `Decide.Judge`, in `Bridge/Process/Decide.cls`, and quotes none of the reply's content.
- **How the CI mock picks a scenario.** In order:
  1. a `[[mock:<name>]]` marker in the newest user message;
  2. otherwise a guide prompt, when the message contains that prompt's exact text. These scenarios live under `B/` only. One with `mockkey` answers only that agent; one without it answers every agent whose message contains the prompt;
  3. otherwise the agent's `MOCKKEY` default script (`triage`, `chat`).

  Lane A adds only files under `ci/mock/scenarios/A/`. Prompt scenarios and new mock behaviour belong to Lane B and are asked for under AD-33.
- **Tests and CI.**
  - Unit tests are `%UnitTest` classes under `OcuTalon.Test.<Area>`. Bridge and Agent run in `shards-5`.
  - The evaluation set runs on the mock on every push and on Claude Haiku 5.5 for each release candidate.
  - Evaluation runs (owner `eval`) never notify.
- **Standing rules.** Stored data is append-only: never rename, retype or remove a stored property, and never hand-edit a `Storage` block. The spine lint must not get worse than its baseline.

## UX & Interaction Patterns

- **The decision strip.**
  - Line 1: the outcome chip, the fallback flag, the confidence (left out on a fallback), the cost, and Trace.
  - Line 2: the reasons. A fallback's reason is always the first line.
  - A usable decision shows Tell now with its confidence and reasons, and no fallback flag.
- **The panel's remember control.** Demo-guide item 5, "Ask it to remember something", sends its exact text ("Remember that the Results partner's contact is Lee.") as the person's own message, exactly as if typed. It gets the same strip, reply and trace link as a typed message.

## Cross-Story Dependencies

- **Story 30.5 (DW-500).** It set the rule that on any user turn Triage's reasons only classify the turn as the person's own message. 30.9's decision follows that rule and must not break the chip cases.
- **Story 30.6.** Its warning is 30.9's evidence, and both stories touch the same `Decide` code.
- **Memory (Epics 19 and 34).** `save_memory` runs in Chat's turn, and `OcuTalon.Tools` holds the fixed phrase list that marks a memory as `told`. The turn, the save and the recall ("Who do I call about Results?" → Lee) work today and must keep working.
- **Epic 9's evaluation set.** 30.9 adds a case to it. Epic 41, which is merge-gated and lands after 1.0.0, plans its own "Remember that ..." cases for email and webhook items. Those are untrusted, so no memory is saved. Keep the case names distinct.
- **Story 30.7.** It stays deferred and is untouched by this re-open.
