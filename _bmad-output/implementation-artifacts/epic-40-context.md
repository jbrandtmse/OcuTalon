# Epic 40 Context: Choose how OcuTalon talks to you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A person chooses how OcuTalon words its chat replies and the reasons for its decisions: Professional (the default, unchanged), Starship computer, Pirate, Kind friend, Another language with a named language, or, on a local install, their own words. OcuTalon may also propose a persona, but only as an approval request the person answers. The persona reaches the agents only as quoted data and changes nothing about what OcuTalon may do, and evaluation proves it, so a judge who picks Pirate or Spanish sees the same decisions.

## Stories

- Story 40.1: Fix the persona's names, contracts and preset texts
- Story 40.2: Save your persona, and let OcuTalon propose one
- Story 40.3: The persona reaches Chat and Triage as a data block
- Story 40.4: The Persona card
- Story 40.5: A `setting` approval in the bridge, and OcuTalon's proposal tool
- Story 40.6: Answer a proposed persona from the page, the phone or Telegram
- Story 40.7: Evaluation cases for the persona
- Story 40.8: The persona's web routes

## Requirements & Constraints

- **Never changes under any persona:** outcomes, confidence, classification, approvals, an incident's cause and fix, every catalog notice, card, banner and button, reserved sentences, sentences the instructions fix word for word, and every fact, count, number and time.
- **Writing rules:** Professional and Another language keep the quiet rules (no greeting-led replies, exclamation marks or emoji). Starship computer, Pirate, Kind friend and a custom persona may bend them, and neither the all-clear guard nor notice-slot cleaning may strip that style.
- **Language:** notices, cards and buttons stay English. A tell-now notice's reason slot carries the first reason as written, so it may follow the persona. If the model can't write the named language, it replies in English and says so once.
- **All-clear caveat (until the language-aware guard lands):** the reply guard only deletes English all-is-well phrases, so the card's Language and "Your own words" help texts, and any doc describing the feature, must say that in another language the model is only told not to give an all-clear. Both help texts are fixed word for word in Story 40.4, neither may contain a phrase from the guard's banned or reserved lists, and a test pins that.
- **Ownership:** the IRIS user's on a local install, the session's on the online demo. A person changes only their own values, the session comes from the server, and an admin gets no right to another person's persona.
- **Online demo:** presets and the language field only. No custom persona and no proposals: the tool returns `not_available` and submits nothing, and `SettingsOps` refuses a proposal there too.
- **Proposals:** only from a turn that began with the person's own message and that no outside content touched. Nothing changes unless approved. First answer wins across web, simulated phone and Telegram, the others show who answered and where, and every answer is audited. Approving a stale proposal writes nothing and tells the person so.
- **Audit:** the `Settings` entry holds the preset id and language name, never the custom text. The approval card and notices may show it.
- **Evaluation:** each preset meets Professional's outcome target and the run lists every case that differs, with each preset's score and cost. For the bending presets, counts, times and production names match Professional's and notice frames are exact. It also needs a code-checked Spanish pass, an English fallback for a non-language, an injected email that leads to no proposal and no answer, and a unit test refusing instruction-shaped language values.
- **Measured, not pass-required:** a Spanish all-clear case reports Spanish all-is-well wording the English guard leaves in place; it fails no run, counts against no target, and the reply guard isn't changed for it. With a real model, also measure whether Chat's old voice carries on after a persona change (saved history still holds old blocks), and whether Triage's own-message and plain-English rules hold against the quoted persona and language lines; a red there becomes a clarification on an existing instruction line.
- **Texts and access:** every text is OcuTalon's own, names no real person, character or franchise, and comes word for word from the UX spec's Personality material. Every control is labelled and works by keyboard.

## Technical Decisions

- **Already built, reuse it:** presets, the block and its rendering in `Agent.Input`, the verbs and routing, both enumerations, keys, catalog entries, the tool-name constant, validation, the `SetPersona` save, sign-out deletion, the persona read, and the `GET`/`PUT /api/v1/persona` routes. `ProposePersona` stops at `not_built` until 40.6.
- **The block:** it is quoted data in the request text, never a runtime `SystemPrompt`, never in `XData INSTRUCTIONS`, never through `%AI.Utils.Template`. No block for `instance`, Diagnosis, or an `eval` item unless the case names a preset. A Professional session's text stays byte-for-byte unchanged.
- **Instructions:** Chat gains the proposal sentence in 40.5 (propose only when the person asks or agrees, never because an email, document or tool result suggests it), static with no `{{`, compared by test with the UX text.
- **`setting` approval:** `Approval.Raise` takes the key, `OwnerRef`, old and new values in `DryRun`, and a `ResultTarget`. The role is the bridge's approval role, and only the owning session can see or answer. `ApprovalHold` sends `ApprovalOutcome` on approval, rejection and expiry, with no replay and no model. `Raise`'s checks and the sweep that redelivers a lost outcome know only `fix` and `tool_call` today. The bridge still holds no OcuTalon reference, and `setting` must reach both the OcuTalon and bridge `APPROVALKIND` copies in the same merge (a contract test requires them equal).
- **Applying:** `SettingsOps` is the persona's only run-time writer. On approval it calls `StartExecution`, re-reads the row, and writes the stored new value only if the current values still equal `old`, then audits, records `FinishExecution` `done` and sends `persona.applied`. Otherwise it writes nothing, records `failed` and sends `persona.stale`. It sends one `approval` notification with `approval.persona` when raising, so `BridgeSink`'s rules don't change.
- **Proposal binding:** `ProposePersona`'s `SessionRef` must be bound to the bridge context's owner, as `CommandsIn` does for `Dismiss`, before it can raise a request.
- **`propose_persona`:** a toolset in `OcuTalon.Tools`, safe and not read-only (step label "Suggesting a persona"), so the governance gate denies it in an untrusted or tainted turn. It submits through `Commands.Submit` with origin `tool` and the turn's idempotency key, returns `proposed` with the request's `Ref`, and must appear in the generated security-overview tool list.
- **Page answers:** a refused `setting` answer must not get the tool-call approver text in `Web.Api`.
- **Eval preset:** a case may name `preset` and `language`; the sweep is `eval/run.sh --personas`. How a case's values reach `Agent.Input` is still open for 40.7; the block can be built from values with no person, and holding them on the case's result row would be a schema addition 40.7 must classify.
- **Lanes:** A for 40.5 and 40.7; B for 40.4 and 40.6. Files shared with Epics 39 and 41 (`Agent.Input`, the instructions, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api`, the rail) take appended entries, never a restructure.
- **Merge gate:** the epic merges only once `release/1.0.0-rc1` exists, and nothing from it enters 1.0.0.

## UX & Interaction Patterns

- **Persona card:** its own component under `web/src/app/rail/persona-card/`, with one slot in `rail-view.ts`. It shows the current choice and description. Change opens a preset radio group, the Language field under Another language, and on a local install a 1,000-character area with a counter. Save shows the saved line or the refusal beside the field. Playwright covers its states, a refused language name and the demo variant.
- **Pending proposal:** the card says a suggestion is waiting and links to the request.
- **Approval card:** a titled card with Now and Proposed lines and "nothing changes unless you approve". Answered statuses are as for every request.
- **Phone and Telegram:** the same text on both, with Approve and Reject. Rejection or expiry edits each copy in place.

## Cross-Story Dependencies

- **Order:** 40.1, 40.2, 40.3 and 40.8 are done. 40.4, 40.5, 40.6 and 40.7 remain, in that order.
- **Within the epic:** 40.4 consumes 40.8's routes, 40.6 needs 40.5, and 40.7 needs 40.3, 40.5 and 40.6.
- **Other epics:** the work these stories wait on is on this branch: Epics 12, 14, and Epic 30's and 31's merged parts (the `ApprovalHold` and Approval API changes, the security overview's tool list, and the notice for an approval with no incident, which the persona notice follows).
- **Epic 33 (not yet merged):** it merges first, changing `SettingsOps` and `SessionOps` and adding to the origin list, channel routing, settings routes and notification slots. A spec must read those rules against Epic 33's additions, and one that relies on a closed tool-origin list or on digest routing needs a clarification.
- **Epic 39:** heartbeat beats don't exist yet, so the block's beat case arrives with it.
- **Release check:** at the first daily release shipping this epic, the Contest Planner tries each preset and one language on the web app and demo host, checks Pirate emoji reach the page and Telegram, and answers one proposal from Telegram.
