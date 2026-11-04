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

- **Never changes under any persona:** outcomes, confidence, classification, approvals, an incident's cause and fix, the digest's code-written parts, every catalog notice, card, banner and button, reserved sentences, sentences the instructions fix word for word, and every fact, count, number and time.
- **Writing rules:** Professional and Another language keep the quiet rules (no greeting-led replies, exclamation marks or emoji). Starship computer, Pirate, Kind friend and a custom persona may bend them, and neither the all-clear guard nor notice-slot cleaning may strip that style.
- **Language:** notices, cards and buttons stay English. A tell-now notice's reason slot carries the first reason as written, so it may follow the persona. If the model can't write the named language, it replies in English and says so once.
- **Ownership:** the IRIS user's on a local install, the session's on the online demo. A person changes only their own values, the session comes from the server, and an admin gets no right to another person's persona.
- **Online demo:** presets and the language field only. No custom persona and no proposals: the tool returns `not_available` and submits nothing.
- **Proposals:** only from a turn that began with the person's own message and that no outside content touched. Nothing changes unless approved. First answer wins across web, simulated phone and Telegram, requests expire after 24 hours, and every answer is audited. Approving a stale proposal writes nothing and tells the person so.
- **Audit:** the `Settings` entry holds the preset id and language name, never the custom text. The approval card and notices may show it.
- **Evaluation:** each preset meets Professional's outcome target and the run lists every case that differs. For the bending presets, counts, times and production names match Professional's and notice frames are exact. It also needs a code-checked Spanish pass, an English fallback for a non-language, and an injected email that leads to no proposal and no answer.
- **Texts and access:** every text is OcuTalon's own, names no real person, character or franchise, and comes word for word from the UX spec's Personality material. Every control is labelled and works by keyboard.

## Technical Decisions

- **Already built, reuse it:** the presets and the `Block` stub, the verbs and their routing, both enumerations, the keys, the catalog entries, the tool-name constant, value validation, the `SetPersona` save, sign-out deletion, and `SettingsOps.Persona`, the read 40.8 returns. `ProposePersona` stops at `not_built` until 40.6.
- **Routes:** session-checked `GET` and `PUT /api/v1/persona` in `OcuTalon.Web.Api`. `PUT` submits `SetPersona` with origin `web_user` and returns the accepted change or the refusal's plain message.
- **The block:** `OcuTalon.Agent.Input` renders it into the request text, after the preamble and before the item and any other context block: the code-written opening line, the text quoted through `Quoted`, the language line for `language`, and the style line only for bending presets and `custom`. It is never a runtime `SystemPrompt`, never in `XData INSTRUCTIONS`, and never passes through `%AI.Utils.Template`.
- **Who gets it:** every item a session owns, decided from the item's owner and provenance with no flag. `Item.SessionRef` holds a session's `Ref`, `instance` or `eval`. No block for `instance`, for `eval` unless the case names a preset, or for Diagnosis. A Professional session's text stays byte-for-byte unchanged, which keeps a default install's requests the same.
- **Instructions:** Chat and Triage each gain one static paragraph with no `{{`, compared by test with the UX text. Chat gains the proposal sentence in 40.5, and its class comment stops claiming the instructions fix every reply's voice.
- **`setting` approval:** `Approval.Raise` takes the key, `OwnerRef`, old and new values in `DryRun`, and a `ResultTarget`. The role is the bridge's approval role, and only the owning session can see or answer. `ApprovalHold` sends `ApprovalOutcome` on approval, rejection and expiry, with no replay and no model. `Raise`'s checks and the sweep that redelivers a lost outcome know only `fix` and `tool_call` today. The bridge still holds no OcuTalon reference.
- **Applying:** `SettingsOps` is the persona's only run-time writer. On approval it calls `StartExecution`, re-reads the row, and writes only the row's stored new value if the current values still equal `old`, then audits, records `FinishExecution` `done` and sends `persona.applied`. Otherwise it writes nothing, records `failed` and sends `persona.stale`. It sends its own `approval`, `answered` and `result` notifications, so `BridgeSink`'s rules don't change.
- **Proposal binding:** `ProposePersona`'s `SessionRef` must be bound to the bridge context's owner, as `CommandsIn` does for `Dismiss`, before it can raise a request.
- **`propose_persona`:** a toolset in `OcuTalon.Tools`, safe and not read-only, so the governance gate denies it in an untrusted or tainted turn. It submits through `Commands.Submit` with the turn's idempotency key and must appear in the generated security-overview tool list.
- **Page answers:** a refused `setting` answer must not get the tool-call approver text in `Web.Api`.
- **Lanes:** each story stays in its home lane's files: A for 40.3, 40.5 and 40.7; B for 40.4, 40.6 and 40.8. Files shared with Epics 39 and 41 (`Agent.Input`, the instructions, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api`, the rail) take appended entries, never a restructure.
- **Merge gate:** the epic merges only once `release/1.0.0-rc1` exists, and nothing from it enters 1.0.0.

## UX & Interaction Patterns

- **Persona card:** its own component under `web/src/app/rail/persona-card/`, with one slot in `rail-view.ts`. It shows the current choice and description. Change opens a preset radio group, the Language field under Another language, and on a local install a 1,000-character area with a counter. Refusals show beside the field.
- **Pending proposal:** the card says a suggestion is waiting and links to the request.
- **Approval card:** shows Now and Proposed lines. Answered statuses are as for every request.
- **Phone and Telegram:** the same text on both, with Approve and Reject. Rejection or expiry edits each copy in place.

## Cross-Story Dependencies

- **Order:** 40.1 and 40.2 are done. 40.8, 40.3, 40.4, 40.5, 40.6 and 40.7 remain, in that order.
- **Within the epic:** 40.4 consumes 40.8's routes, 40.6 needs 40.5, and 40.7 needs 40.3, 40.5 and 40.6.
- **Other epics:** the work these stories wait on is on this branch: Epics 5, 12 and 14, Epic 11's 1.0.0 part, and Epic 30's and 31's merged parts (the `ApprovalHold` and Approval API changes, and the notice for an approval with no incident).
- **Epic 33 (not yet merged):** it merges first, changing `SettingsOps` and `SessionOps` and adding to the origin list, channel routing, settings routes and notification slots. A spec must read those rules against Epic 33's additions, and one that relies on a closed tool-origin list or on digest routing needs a clarification.
- **Epic 39:** heartbeat beats don't exist yet, so the block's beat case arrives with it.
- **Open point:** the planning docs don't say how a case's preset reaches `Agent.Input`, since `eval` items have no person's values. 40.3 and 40.7 must settle it.
- **Release check:** at the first daily release shipping this epic, the Contest Planner tries each preset and one language on the web app and demo host, checks Pirate emoji reach the page and Telegram, and answers one proposal from Telegram.
