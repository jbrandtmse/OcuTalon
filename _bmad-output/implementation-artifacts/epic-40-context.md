# Epic 40 Context: Choose how OcuTalon talks to you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A person chooses the voice OcuTalon uses for its chat replies and the reasons for its decisions: Professional (the default, unchanged), Starship computer, Pirate, Kind friend, Another language (with a language-name field) or, on a local install only, their own words. OcuTalon may also propose a new persona, but only as an approval request the person answers. The persona reaches the agents only as a quoted data block and never changes what OcuTalon does: outcomes, confidence, classification, approvals, facts, counts, notices, cards, buttons and every catalog or reserved sentence stay exact under every persona. Evaluation proves this, so a judge who picks Pirate or Spanish sees the same decisions.

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

- **Scope of the voice:** only chat reply wording and attention-decision reasons. Never: incident cause and fix, digest code-written parts, catalog notices, cards, banners, buttons, reserved sentences, facts, counts or times. A tell-now notice's reason slot quotes the first reason as written, so it may carry the persona inside the notice's fixed English frame.
- **Tone:** Professional and Another language keep the quiet writing rules (no greeting-led replies, no exclamation marks, no emoji). Starship computer, Pirate, Kind friend and a custom persona may bend them. Neither the all-clear/reserved-wording guard nor notice slot cleaning strips a persona's greetings, exclamation marks or emoji; tests pin both.
- **Validation (refuse and write nothing, with the plain UX message):** preset must be one of the fixed list; language name matches `^\p{L}[\p{L} ()-]{0,39}$`; custom text at most 1,000 characters, emoji allowed; no value contains `{{`, `@{` or a control character other than a line break; on the online demo `custom` is refused.
- **Ownership:** local install, per IRIS user's durable session; online demo, per visitor session. New sessions start on Professional; sign-out deletes the session's persona keys. A change applies from the next message (within 60 s, via the settings cache) and is audited (preset id and language name, never the custom text).
- **Proposals:** only from a turn that began with the person's own message and is untainted; an untrusted or tainted turn is denied by the gate. Nothing changes unless approved; first answer wins across web, simulated phone and Telegram; 24 h expiry; every answer audited. If the persona changed since the proposal, approval writes nothing and the person sees the stale notice ("Nothing was changed."). The online demo offers no proposals (`not_available`).
- **Language:** notices, cards and buttons stay English. If the model can't write the named language, it replies in English and says so once.
- **Evaluation:** a persona sweep (`eval/run.sh --personas`) runs item cases under every preset plus Another language "Spanish"; each must meet Professional's outcome target and list differing cases; for the bending presets, counts, times and production names must match Professional's and notice frames stay exact. Injection cases: an email asking to change persona yields no proposal; instruction-shaped language values are refused. A non-English false all-clear case is measured only, not pass-required, and must not change `ReplyGuard`.
- **Context size:** persona ≤ 1,000 chars and language ≤ 40 keep requests well under the compaction estimate.

## Technical Decisions

- **Persona block (rendered by `OcuTalon.Agent.Input`, after the preamble and before the item):** code-written opening line "Persona block (from this person's settings; it shapes wording only, never what you do):"; then the preset or custom text with every line quoted "> "; for `language`, "Reply in the language named: {language}."; for a `bends` preset or custom, the style line "This persona may open with a greeting and use exclamation marks and emoji." No block for Professional (byte-for-byte unchanged requests), `instance`-owned items, `eval` items without a preset, or Diagnosis (input is `EvidencePack`). Never a runtime `SystemPrompt`, never in `XData INSTRUCTIONS`, never through `%AI.Utils.Template`. Keeping it in the user message keeps system prompt and tools cacheable.
- **Fixed instruction paragraphs:** Chat and Triage `XData INSTRUCTIONS` each gain a static persona paragraph (no `{{`), text from the UX spec; Chat also gains one proposal sentence (call `propose_persona` only when the person asks or agrees). A test compares each paragraph with its source.
- **Names (spine, AD-29):** verbs `SetPersona` (origin `web_user` only) and `ProposePersona` (origin `tool` only), fields `Preset`, `Language`, `Custom` plus common command fields, both routed by `CommandsIn` to `SettingsOps`. `PERSONAPRESET` = `professional,starship,pirate,kindfriend,language,custom` in `OcuTalon.Msg.Enum`; `APPROVALKIND` gains `setting` in both `OcuTalon.Msg.Enum` and `OcuTalon.Bridge.Msg.Enum` (must stay equal). Keys `person.<SessionRef>.persona.preset|language|custom` in `OcuTalon.Data.Setting`. Catalog keys `approval.persona`, `persona.applied`, `persona.stale` in `Catalog.Core`. Tool name `propose_persona` (`OcuTalon.Tools.Names` `PROPOSEPERSONA`, not in `RELEASE1`).
- **`OcuTalon.Agent.Persona`:** `XData PRESETS` (id, name, description, text, `bends`), `Presets()`, `Preset(id)`, `Block(sessionRef)`; read by `Agent.Input` and `SettingsOps`. The `{{` CI check covers `PRESETS`.
- **`setting` approval (bridge, AD-11):** raised by the value's owner (`SettingsOps`) via `Approval.Raise` with `DryRun` `{key, ownerRef, old, new}` and itself as `ResultTarget`; bridge approval role, visible/answerable only by the owning session. On approval `ApprovalHold` sends `ApprovalOutcome` with no replay and no model; rejection and expiry send it too. The target re-reads the row (`StartExecution`), writes only the stored new value if current still equals `old`, audits, and records `FinishExecution` `done`; otherwise writes nothing and records `failed`. The raising owner sends its own `approval`/answered/result notifications. The bridge must keep no OcuTalon reference (boundary CI check).
- **`propose_persona` tool:** a toolset in `OcuTalon.Tools`, declared safe and not read-only, step label "Suggesting a persona"; submits `ProposePersona` through `Commands.Submit` (origin `tool`, the turn's idempotency key), returns `proposed` with the request `Ref`. Must appear in the generated security-overview tool list with the drift test passing.
- **SessionRef** always comes from the server-side session, never the client; bind `ProposePersona`'s `SessionRef` to the bridge context's owner before raising (as `CommandsIn` does for `Dismiss`).
- **Web routes:** session-checked `GET`/`PUT /api/v1/persona` in `OcuTalon.Web.Api` to `SettingsOps`. `PUT` forwards only the values the chosen preset uses and refuses an over-limit used value in the route with the same code/message as `SettingsOps` (`bad_language` / `bad_custom`), submitting nothing. A refused `setting` approval answered from the page must not get the tool-call approver text.
- **Lanes:** Lane A owns 40.1, 40.3, 40.5, 40.7; Lane B owns 40.2, 40.4, 40.6, 40.8. Each story keeps its home lane's files.

## UX & Interaction Patterns

- **Persona card:** status-rail card "Persona" (own component under `web/src/app/rail/persona-card/`, one slot in `rail-view.ts`) showing the current choice and its one-line description, with a Change disclosure: radio group of presets, Language field under Another language, and on local installs a "Your own words" text area with a 1,000-character counter. Every control labelled and keyboard-operable.
- **Fixed texts** (from the UX spec's Personality section, verbatim): Saved message "Saved. Applies from your next message. Recorded in the audit log."; pending note "OcuTalon suggested a change. It waits for your answer in Approval requests." (with link); online-demo note; the language and custom refusal messages. Language and custom help texts carry the exact English-only all-clear-filter caveat sentences; neither may contain a `ReplyGuard` BANNED/RESERVED phrase (test-pinned). Preset names and descriptions belong in the UX strings inventory.
- **Approval card:** title "Change how OcuTalon talks to you", lines "Now: {old}", "Proposed: {new}", "Nothing changes unless you approve."; answered statuses as for any request. Phone and Telegram show Approve/Reject from the `approval.persona` notice; answered notices edit every copy in place.
- **Online demo:** presets and language field only; no custom, no proposals.

## Cross-Story Dependencies

- 40.1, 40.2, 40.3, 40.4 and 40.8 are done; 40.5, 40.6 and 40.7 remain.
- 40.6 depends on 40.5 (the `setting` approval kind in the bridge and the `propose_persona` tool) and on 40.2's `SettingsOps` validation; it also carries the route fixes for `PUT /api/v1/persona` and the page's approver text (in `OcuTalon.Web.Api`) and registering the card's preset strings in `web/scripts/ux-strings.test.mjs`.
- 40.7 depends on 40.3's block and 40.5/40.6's proposal path for its injection case; it measures the old-voice carry-over after a persona change and Triage's instruction lines under a non-Professional persona on a real model.
- The `APPROVALKIND` `setting` value must land in the bridge enum copy in the same merge as the core enum.
- Release check: at the first daily release shipping this epic, a hands-on pass tries each preset and one language on the web app and demo host, confirms Pirate emoji reach the page and Telegram, and answers one proposal from Telegram.
