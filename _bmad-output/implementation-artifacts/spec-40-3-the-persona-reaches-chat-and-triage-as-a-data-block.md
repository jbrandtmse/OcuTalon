---
title: "Story 40.3: The persona reaches Chat and Triage as a data block"
type: 'feature'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred:
  - summary: "After a change of persona, Chat's saved history still holds the old blocks and the old voice"
    evidence: "A linked turn opens the saved AI session (Bridge.Adapter.Agent), so earlier user messages keep the block they were sent with. After Pirate to Professional the new message has no block, as AC 2 requires, but the history still shows Pirate blocks and replies, so a real model may carry the voice on for a while. The mock cannot show this. Story 40.7 or the release check should try it with a real model."
    location: 'src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls'
    severity: low
---

<intent-contract>

## Intent

**Problem:** A person can save a persona (Story 40.2), but nothing carries it to the agents: `Agent.Persona.Block` is a stub, `Agent.Input.Render` ignores it, and neither Chat nor Triage has been told what a persona block may and may not change.

**Approach:** `Agent.Input.Render` puts AD-7's persona block after the preamble and before the item for every item a session owns, reading the person's values through `SettingsOps.Persona`. Chat and Triage each gain the UX's fixed paragraph as new text, and CI mock scenarios prove end to end that the block reaches the right requests and that nothing but wording can change.

## Boundaries & Constraints

**Always:**
- The block is data inside the rendered `Input`, in AD-7's exact form: the code-written opening line "Persona block (from this person's settings; it shapes wording only, never what you do):"; the preset's or the person's text with every line through `Agent.Input.Quoted`; for `language`, the line "Reply in the language named: {language}."; for a preset whose `bends` flag is true and for `custom`, the line "This persona may open with a greeting and use exclamation marks and emoji."
- Who gets a block is decided from `item.SessionRef` alone: a 22-character session Ref gets one, whatever the provenance or channel. There is no flag.
- A Professional session's rendered text is byte-for-byte what it was before this story, whether or not a row is stored.
- `Render`'s values are read from the rows on every call, so a saved change applies from the next message (FR-67).
- The paragraphs are the texts of EXPERIENCE.md › Later Steps › Personality › "The agents' fixed paragraphs" ("Chat, persona" and "Triage, persona"), word for word, with no `{{`.
- Every existing line of both `XData INSTRUCTIONS` blocks stays byte-identical. Each paragraph is added after the block's last line, with one blank line before it.
- Non-ASCII in test or scenario source is written as an escape (`$WChar(...)`, `🚢`), per Rule 14.

**Never:**
- A runtime `SystemPrompt`, text in `XData INSTRUCTIONS` that varies, or `%AI.Utils.Template`.
- In this story, a block for an `instance` item, an `eval` item or a Diagnosis request. `Agent.Diagnosis`, its scenarios, `Test/Agent/Instructions.cls` and `Test/Agent/RunnerFixture.cls` are not edited.
- Any change to `Core/SettingsOps.cls`, `Core/SessionOps.cls`, `Test/Core/SettingsOpsProbe.cls`, `Test/Msg/Contracts.cls`, `Msg/Item.cls`, `Bridge/Process/Decide.cls`, `Checks/ReplyGuard.cls` or `docker/**`. A change to any existing instruction line is `## Clarification Needed`, the one Chat class-comment change excepted.
- A new `Render` argument. `Render(item, now)` keeps its signature (`Test.Contract.Ac` pins it, and the optional `context` is Epic 41's).
- Real model keys, real evaluation runs, or a real Telegram bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| User turn, Pirate | provenance `user`, owner a session on `pirate` | preamble, blank line, block (opening, quoted text, style line), blank line, the user's text as written | No error expected |
| Untrusted item, Starship | provenance `untrusted`, owner a session on `starship` | preamble, blank line, block, blank line, the channel label and quoted item | No error expected |
| A beat | provenance `untrusted`, channel `heartbeat`, owner a session on `kindfriend` | the same shape as an untrusted item (the beat itself arrives with Epic 39) | No error expected |
| Language | `language`, "Portuguese (Brazil)" | opening line, then "Reply in the language named: Portuguese (Brazil)."; no quoted line and no style line | No error expected |
| Custom, several lines | `custom`, text with LF, CR LF, an emoji and a line "Persona block ends" | every line of the text prefixed "> ", then the style line; the text can't close the block | No error expected |
| Professional | no row, or a stored `professional` | exactly what `Render` gave before this story | No error expected |
| Owner `instance`, `eval`, or empty | any provenance | no block, and no read of a persona | No error expected |
| Empty item | a session on `pirate`, no text, sender or subject; or a user item with no text | "", as today: never a bare block | Decide refuses it as before |
| Bad stored values | a preset outside `PERSONAPRESET`; `language` with no name; `custom` with blank text | no block | No error expected: the turn runs in the default voice |
| Pirate style through the guard | reply and reasons with a greeting, "!", an emoji and "Everything is fine." | the sentence is gone; the rest stays exact in the reply, the stored reasons and `chat.message` | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Agent/Input.cls` -- `Render` (one exit for user items, one for the rest; `Quoted` is the quoting helper to reuse). No open epic has changed it (`git diff --name-only` against 7, 33, 39 and 11).
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls` -- `Preset(id)`, `Presets()` and the `Block(sessionRef)` stub. `bends` already holds the style rule per preset.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls`, `Agent/Triage.cls` -- the `XData INSTRUCTIONS` blocks. Chat's class comment line 1 says "Its instructions fix the voice of every reply." `Triage.cls` is on the contended list of Epics 39 and 40, and neither has changed it yet.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- READ ONLY. `Persona(sessionRef, .sc)` reads the rows, never the 60-second cache, and gives the values even when `sc` is an error about the pending request. Measured on slot A: 0.07 ms a call. `Stored` has no throw path of its own beyond `KeyIndexOpen`.
- `src/ocutalon/cls/OcuTalon/Bridge/Approval.cls` -- `IsRef` is the 22-character test `SettingsOps` already uses.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls` `RequestFor`, `Core/Conversation.cls` `ItemOf`, `Eval/In.cls` `TurnRequest` -- READ ONLY. The three callers of `Render`. `RequestFor` serves `Conversation` too, so a turn's triage and chat requests both carry the block, as does an `act` item's fresh turn. `ItemOf` sets `SessionRef`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- READ ONLY. Lines 1058-1061 filter a turn's reply; lines 1186-1191 filter each reason, then `$ZStrip(..., "<>WC")`; line 1227 joins the reasons with LF into `Decision.Reasons`. Measured on slot A with `$WChar(128674)` and `$WChar(9875)`: `ReplyGuard.Filter` and that `$ZStrip` keep emoji exactly, also at the end of a line, and `Filter` gives "Ahoy, shipmate! The Orders production sails on! {emoji}".
- `src/ocutalon/cls/OcuTalon/Test/Checks/Turns.cls` -- the pattern for a mock turn: `Ask` (arm the countdown at 1, `Send`, `WaitDone`), `AssertDone` (the done `chat.message`), `TestAllClearOnlyFromCode` (a passed watch row), `OnAfterOneTest` (disarm), `OnAfterAllTests` (`AdoptTurns`).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- the base: `Ready`, `PointKeys`, `Session`, `Watch`, `SendBatch`, `WaitDiagnosed`, row clean-up. `Test/Watch/Diagnose.cls` shows a `[[mock:<name>]]` marker in a failure's text reaching Diagnosis through the pack's `errorPattern`.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` `TestSetPersonaReachesSettingsOps` -- saving a persona with `Commands.Submit(command, "web_user", .result)`.
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls` `SendTo` -- sends an Item to `Intake` from a `SimMailboxIn` host.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- READ ONLY. `FindRequests`, `Messages`, `DecisionOf`; `Test.Contract.Mock` `LogMark`, `LogSince`, `Arm`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls` -- `XData UX` is the test-held copy pattern for UX text. Its `TestBlock` stays valid: no rows give "".
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Seed` for a fixture row. `Set` is `SettingsOps`' alone.
- `ci/mock/mock.mjs` header -- selection: the first `[[mock:<name>:<key>]]` of the newest user message; the armed countdown rule; the log holds the messages in full and reduces the system text to its size, so the paragraphs are checked from the compiled XData, not the log.
- `ci/mock/scenarios/A/checks-false-all-clear.json`, `watch-start-orders.json`, `watch-start-unknown.json`, `decide-ignore.json` -- the shapes to follow. `start_watch`'s input is `{"name": "Orders"}`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Agent/Persona.cls` -- add `BlockFor(preset, language, custom)`: the block's text from the values alone, "" for `professional`, an empty or unknown preset, `language` with a blank name and `custom` with blank text. The opening, language and style lines are parameters of this class. Make `Block(sessionRef)` return "" when `sessionRef` isn't a Ref (`Bridge.Approval.IsRef`), else `BlockFor` of `SettingsOps.Persona`'s values, ignoring `sc` as that method allows. Update the class comment and `Block`'s comment, which call it a stub.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls` -- in `Render`, after the existing "" checks and the preamble, put `Persona.Block(item.SessionRef)` and a blank line between the preamble's blank line and the rest, on both paths, adding nothing when it is "". Add the block to the class comment.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- append the "Chat, persona" paragraph after the block's last line. Replace the comment sentence "Its instructions fix the voice of every reply." with one saying they fix the writing rules, which a persona block may bend only as their persona paragraph says.
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls` -- append the "Triage, persona" paragraph after the block's last line.
- `ci/mock/scenarios/A/persona-status.json` -- new: `tellnow` triage, `check_status`, then "Everything is fine. I looked at the Orders production for you."
- `ci/mock/scenarios/A/persona-command.json` -- new: `tellnow` triage, then the exact text of catalog key `agent.noCommands`.
- `ci/mock/scenarios/A/persona-watch.json` -- new: `tellnow` triage, `start_watch` of Orders, then "I'll watch the Orders production and stay quiet unless something needs you."
- `ci/mock/scenarios/A/persona-watch-unknown.json` -- new: `tellnow` triage, `start_watch` of Nowhere, then the `watch.unknownProduction` sentence with name Nowhere and list Orders.
- `ci/mock/scenarios/A/persona-triage.json` -- new: one reply, `{"outcome":"ignore", ..., "confidence":0.4}`, so no notice or digest row is left behind.
- `ci/mock/scenarios/A/persona-pirate-style.json` -- new: `tellnow` triage whose reasons, and a reply which, hold a greeting, "!", `🚢` and "Everything is fine."
- `src/ocutalon/cls/OcuTalon/Test/Agent/PersonaBlock.cls` -- new, extends `OcuTalon.Test.Bridge.ZoneCase` like `Test.Agent.Render`, needs no production: every matrix row except the guard row, with literal expected texts; the Professional row compared with and without a stored row; the paragraphs against a test-held copy of the UX text (`XData UX`-style), each exactly once in its compiled block, with no `{{`; Diagnosis's block holds no "persona"; Chat's compiled class description no longer says "fix the voice of every reply". Fixture rows through `Setting.Seed`, removed with `SettingsOps.ForgetPerson` and `Fixture.Clean`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/PersonaTurns.cls` -- new, extends `OcuTalon.Test.Watch.Case`, fresh stacks only (the production's jobs keep old code on a warm stack): the tests of AC 3 to AC 7, one session per preset, the persona saved with `Commands.Submit`, each run's marker key `<name>:<number><preset>` so that countdowns and log entries are the test's own.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Persona.cls` -- comments only: `TestBlock` no longer describes a stub. The assertions stay.

**Acceptance Criteria:**
1. Given a session on each of Starship computer, Pirate, Kind friend, Another language and Your own words, when `Agent.Input.Render` renders an item that session owns (its user turn, an untrusted item, a beat-shaped item), then the text holds the block in AD-7's form after the preamble and before the item, and an Another language block has no style line.
2. Given an item owned by `instance`, an `eval` item, or a Professional session, when `Render` renders it, then there is no block, and the Professional text equals the literal text from before this story, with and without a stored row.
3. Given `OcuTalon.Agent.Chat` and `OcuTalon.Agent.Triage`, when the compiled classes are read, then each block holds its paragraph exactly as the UX gives it, once, with no `{{`, every earlier line of each block is unchanged, and Chat's class comment no longer says its instructions fix the voice of every reply.
4. Given a real `SetPersona` for each preset through `Commands.Submit`, when that session's chat turn runs through `WebChatIn`, `Conversation`, `Decide` and the runners against the mock, then the mock's request log shows the block on the turn's triage request and its Chat request for every preset but Professional, the style line only for Starship computer, Pirate, Kind friend and a custom persona, and Professional's requests hold no "Persona block".
5. Given an untrusted item owned by a session, sent to `Intake`, for each preset, when Triage decides it (`persona-triage`), then the logged request holds the block as in AC 4 and the Decision row's outcome and confidence are the script's under every preset.
6. Given a session on Pirate with a watch of Orders, when an incident's Diagnosis runs (a failure whose text carries the existing marker `diagnosis-unknown`), then the logged Diagnosis request holds no "Persona block".
7. Given each preset, when the `persona-command`, `persona-watch`, `persona-watch-unknown` and `persona-status` turns run, then the reply equals the catalog sentence (`agent.noCommands`, `watch.unknownProduction`), the UX sentence for a started watch and "I looked at the Orders production for you.", the status turn's `CheckKey` and check rows are those of the watch's passed row, the reserved wording is gone, and the decision's outcome is the script's.
8. Given `persona-pirate-style` on a Pirate session, when `Decide` runs the reply filter, then "Everything is fine." is removed, and the greeting, the exclamation mark and the emoji are unchanged in `Turn.ReplyText`, in the stored `Decision.Reasons` and in the done `chat.message` event.
9. Given a session on Pirate, when the person saves Kind friend and sends a message, and then saves Professional and sends another, then each newest user message in the log carries the new persona's block, and the last carries none, with no wait between the save and the message.

## Spec Change Log

- 2026-11-04, spec gate, orchestrator ruling on DW-664 (veto U-272): the MED `deferred:` item is removed, since DW-664 holds it; the ruling is in Design Notes. No frozen text changed.
- 2026-11-04, `epics.md` Story 40.7, tier-1 amendment under the same ruling: one new Given block, a measured case for a non-English false all-clear. Original: the story had no such case. No existing AC changed.
- 2026-11-04, `epics.md` Story 40.4, amendment under U-272's answer (kept, with one condition): one new And line, the persona text says replies in other languages have the model's own check only until the language-aware guard lands. Original: the story had no such line. No existing AC changed. This story's own scope is unchanged.

## Review Triage Log

## Design Notes

**Governing decisions:** AD-7 (the persona block, its form, who gets none, the fixed lines), AD-6 (no runtime `SystemPrompt`), AD-14, AD-19 (`SettingsOps` holds the values), AD-22 (the mock and the `eval` owner), AD-28 and AD-31 (the guard as `ReplyFilterClass`), AD-29 (Lane A files).

**What this story relies on from AD-1 and AD-14 (U-268).** From AD-14, only that `Item.SessionRef` is a session's Ref, `instance` or `eval`. From AD-1, only that a test may submit `SetPersona` with origin `web_user`. It relies on no closed list of `tool` origins and on no digest routing, so Story 33.2's additions don't touch it and no clarification is needed.

**Is a digest-kind item one a session owns?** No item of that kind exists to render. On this tree, and on `origin/OCT-epic33`, `OcuTalon.Digest.Process` is a stub until Story 17.6, and a `digest` Notification is not an `Item` and never reaches `Agent.Input`. What does exist:
- An untrusted item that Triage sends to the digest is session-owned, so its triage request gets the block. `Digest.Data.Item` keeps the code-written `Summary`, not the reasons.
- Story 17.6's contract is one fresh, unlinked, untrusted Chat turn per digest. If it renders through `Agent.Input` with the session as owner, the owner rule gives that turn a block with no further work, and the digest's code-written parts stay plain because they never pass through the model.

**Decided in-stage:**
- *How a case's preset reaches `Agent.Input` (the epic context's open point).* An `eval` item gets no block in this story, because no case can name a preset until Story 40.7 builds that field, and `Block("eval")` is "" by the owner rule. This story's share of the answer is `Persona.BlockFor(preset, language, custom)`, which needs no person. `Msg.Item` gains no field. Recommended for 40.7 (inference, not built here): hold the case's values on its `Eval.Data.CaseResult` row, which `Eval.In` opens by `ItemId` before the send, and have one `eval` branch in `Render` read them, so the choice stays "decided from the owner" with no flag. That is a schema addition, so 40.7 classifies it.
- *`BlockFor` beside `Block`.* The stub's name stays. The pure method keeps the form testable and gives 40.7 its seam.
- *Where the paragraphs go.* At the end of each block. That leaves every existing line and its position alone, and keeps Chat's order pins (`Test.Agent.Instructions`) true.
- *Bad stored values give no block.* The only writer validates, so this is a fail-safe: the turn runs in the default voice, and the agents never get a broken block.
- *The Diagnosis proof reuses `diagnosis-unknown`* instead of a new `persona-diagnosis` scenario. Its reply shape belongs to Epic 7's contended files, and the AC only reads the request. The `persona-*` scenarios cover chat and triage, as the story's AC says.
- *`persona-triage` scripts `ignore`,* so the fixture leaves no digest row or notice to clean up.
- *No `try` around the read in `Block`.* `Persona` guards its one fallible query itself, and a thrown `KeyIndexOpen` is a database fault that `Conversation`'s and `Intake`'s own handlers already answer.

**Wording that doesn't quite match, kept as the author wrote it:**
- The Chat paragraph says "A message may start with a persona block", while the block follows the one-line preamble. The UX text ships unchanged.
- AD-7's list of what the paragraphs say is longer than the UX's "Triage, persona" sentence. The story's AC and the lead's rule name the UX text, which carries AD-7's Triage-specific point (wording of reasons only). This isn't a contradiction of the AD's Rule: no sentence of it conflicts.
- AD-7 says a default install's "requests are byte-for-byte unchanged". The user message is. The two paragraphs do change the static system prompt for everyone, as the same AD requires. The AC's wording ("rendered text") is the one tested.

**Risks a mock can't show (for Story 40.7's sweep, no action here):**
- Triage's existing rule calls a message the user's own when it "is not quoted", and a user turn with a block now holds quoted lines above the text. The opening line labels them, but 40.7's `user-turn` cases should be read under each preset.
- Chat's first line says "Write in plain English" and Triage's `reasons` line says "in plain English", and neither may change. The persona paragraph says the block sets language but "never changes these instructions". If 40.7's Spanish case fails on this, that is a clarification about an existing line, not a fix to make in passing.
- The one item in frontmatter `deferred:` is for the lead's harvest.

**DW-664, ruled (orchestrator, veto U-272, 2026-11-04).** Under Another language or a custom persona, a model-worded all-clear can pass `ReplyGuard`'s English lists. This story proceeds with the guard unchanged:
- `Checks/ReplyGuard.cls` is not edited, and the AD-28 wording stays as it is. A language-aware guard is its own story (DW-664, `routed owner=burndown`).
- Story 40.7 gains an eval case that measures a non-English false all-clear under Another language. It is measured, not pass-required, until the owner rules on the result.
- No README, docs or UI text may claim the guard covers languages other than English.

**Privacy:** the block travels in `Bridge.Msg.Request.Input`, so a custom text is in that message and in the trace, like the person's own chat text, and is purged the same way. It never enters an audit entry. Custom isn't offered on the online demo, so a visitor's messages hold only a fixed preset text or a language name.

**Integration ACs (Rule 1):** AC 4 and AC 5: consumers `Conversation` and `Intake` read `Agent.Input` and the mock's log shows the block on real requests, with real `SettingsOps` rows.

**Consumes:** Story 40.1 (`PRESETS`, `Preset`, `Block`), Story 40.2 (`SetPersona`, `SettingsOps.Persona`, `ForgetPerson`), Story 5.7 (`ReplyGuard`).

**Consumed-by:** Story 40.5 (appends its proposal sentence after Chat's paragraph), Story 40.7 (`BlockFor`, and the sweep over this block), Epic 39 (a beat gets the block by the owner rule; its Triage paragraph follows this one), Epic 41 (context blocks go after the persona block and before the item).

**Extend, don't copy (Rule 2):**
- `PersonaBlock` extends `Test.Bridge.ZoneCase`, as `Test.Agent.Render` does.
- `PersonaTurns` extends `Test.Watch.Case`, as `Test.Checks.Turns` does.
- `Test.Checks.Turns.Ask` and `AssertDone` are private to a class whose three tests a subclass would inherit, so `PersonaTurns` carries its own short `Ask` (it arms a keyed marker) and calls the shared fixtures for everything else. That is the reason for the copy.
- The block reuses `Agent.Input.Quoted`, `Persona.Preset` and `SettingsOps.Persona`.

**Ledger inbox (Rule 17):** none. DW-570 and DW-571 are Story 40.6's.

## Verification

All calls run from the worktree root with `timeout: 600000`, one per call, each `ci/iris.sh` and `ci/warm.sh` call prefixed with `<A>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=40 stage=implement'`. Fresh tag `e40s3i`, warm tag `e40s3iw`. Every IRIS MCP call passes `server` `ocutalon-slot-a` and `namespace` `OCUTALON`, and one `iris_execute_tests` call goes in a message on its own. `<BASE>` is `14e709322e43860d4bd3821ab3a5d91a541a6f31`, the commit this plan was made on.

**Commands:**
- (loop) `iris_doc_load` the changed and new classes into slot A and compile -- expected: they compile. `PersonaBlock` needs no production and may run on the slot; `PersonaTurns` runs on a throwaway only.
- (loop) `git diff -U0 <BASE> -- src/ocutalon/cls/OcuTalon/Agent/Triage.cls | grep '^-[^-]' | wc -l` -- expected: 0.
- (loop) `git diff -U0 <BASE> -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls | grep '^-[^-]'` -- expected: one line, the class comment starting `-/// The Chat agent (AD-6, AD-7)`, so nothing in either `XData INSTRUCTIONS` was removed or changed.
- (loop) `git diff --stat <BASE> -- src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls src/ocutalon/cls/OcuTalon/Msg/Item.cls src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls` -- expected: empty.
- (loop) `python3 -c "import re,glob;e=open(glob.glob('_bmad-output/planning-artifacts/ux-designs/*/EXPERIENCE.md')[0]).read();[print(n, re.search(r'\*\*'+n+r', persona:\*\* \"(.*)\"\n',e).group(1) in open('src/ocutalon/cls/OcuTalon/Agent/'+n+'.cls').read()) for n in ('Chat','Triage')]"` -- expected: `Chat True` and `Triage True`, against the source itself rather than the test's copy.
- (loop) `<A> OCUTALON_RUN_TAG=e40s3iw ci/warm.sh up` once per stage, then one per call with `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e40s3iw ci/iris.sh class <Class>` for each of: `OcuTalon.Test.Agent.PersonaBlock`, `.Agent.Persona`, `.Agent.Render`, `.Agent.Instructions`, `.Agent.TriageUserTurn`, `.Agent.Constants`, `.Checks.Guard`, `.Eval.Cases`, `.Contract.Ac`, `.Core.Intake`, `.Core.ConversationTurns`, `.Tools.Reminders` -- expected: `CLASS ... passed` each. `<A> OCUTALON_RUN_TAG=e40s3iw ci/warm.sh down` at the stage's end, also after a failure.
- (loop) `<A> OCUTALON_RUN_TAG=e40s3i ci/iris.sh class OcuTalon.Test.Agent.PersonaTurns` -- expected: `CLASS ... passed` on a fresh stack. Never warm: the production's jobs keep old code there. Each run is about a minute of stack start, plus the turns (inference: under 2 minutes for about 30 turns).
- (loop) `bash docker/tests/test-mock.sh` -- expected: passes, with the six scenario files valid and the health count following the folder.
- (loop) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, one per call -- expected: pass (the two new classes are in area `Agent`, shard `lane-a`, run once; ASCII source; the class rules).
- (once) fresh stacks, one per call, each with `<A> OCUTALON_RUN_TAG=e40s3i`: `ci/iris.sh shard lane-a@Agent`, then `ci/iris.sh shard lane-a@Agent --reverse`, then `ci/iris.sh class <Class>` for each of `OcuTalon.Test.Checks.Turns`, `.Checks.Guard`, `.Bridge.Gate`, `.Eval.Cases`, `.Contract.Mock`, `.Contract.Ac`, `.Core.Intake`, `.Core.ConversationTurns`, `.Tools.Reminders`, and last `ci/iris.sh teardown` -- expected: every class passes. If `lane-a@Agent` nears the cap, use `--part k/2`. A warm stack that has run other shards gave false reds on `Checks.Heartbeat` and `Watch.Incidents` on 2026-11-04, so this final proof is fresh.
- (once) `<A> OCUTALON_RUN_TAG=e40s3i ci/iris.sh live demo-path`, then teardown -- expected: passes, so a default install's demo path is unchanged. If a merge brought `web/` changes, run `ci/iris.sh build` first.
- (once) `bash ci/checks.sh` -- expected: every script passes. It took about 17 minutes on this machine on 2026-11-04, which is past the 10-minute cap, so a call that passes the cap must not be started twice. Read what the first call printed, then run the remaining scripts of `CHECK_SCRIPTS` one per call.
- The rest of shards `lane-a` and `lane-b` and the other live units are left to CI.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):**
- AC 1: `Block` not added on the untrusted path of `Render` -> `PersonaBlock` untrusted-item test red.
- AC 2: `Render` adding the blank line even when the block is "" -> `PersonaBlock` Professional test and `Test.Agent.Render` red.
- AC 3: one word of Triage's paragraph changed -> `PersonaBlock` paragraph test red.
- AC 4: `BlockFor` writing the style line for `language` too -> `PersonaTurns` log test red.
- AC 5: `Block` skipping items with provenance `untrusted` -> `PersonaTurns` item test red.
- AC 6: `Persona.Block` of the owner put in front of the diagnose request's `Input` where `IncidentManager` builds it -> `PersonaTurns` Diagnosis test red. The test also asserts that a Diagnosis request was logged, so "no block" can't pass on an empty list.
- AC 7: one word of the `agent.noCommands` sentence changed in `persona-command.json` -> `PersonaTurns` sentence test red.
- AC 8: `ReplyGuard.BANNED` gaining "ahoy" -> `PersonaTurns` style test red; "everything is fine" removed from `BANNED` -> the same test red.
- AC 9: `Block` reading `Setting.Get` (the 60-second cache) instead of `SettingsOps.Persona` -> `PersonaTurns` next-message test red.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

Shared surfaces: the text of `Agent.Input.Render` for a session on a non-default persona (`Test.Agent.Render`, `Test.Core.Intake`, `Test.Core.ConversationTurns`, `Test.Bridge.Gate`, `Test.Agent.Decide`, `Test.Tools.Reminders`, `Test.Bridge.Api`; each compares against `Render` or a default session, so each stays green unchanged); Chat's and Triage's `XData INSTRUCTIONS` (`Test.Agent.Instructions`, `Test.Agent.TriageUserTurn`, `Test.Agent.Constants`, `Test.Eval.Cases`, `ci/mock/test/constants.test.mjs`, which read them); `Bridge.RequestSize`'s estimate, which counts the longer system prompt (`Test.Agent.RequestSize` computes from it and pins no prompt length); `Agent.Persona.Block` (`Test.Agent.Persona:TestBlock`); the scenario list of `ci/mock/scenarios/A/`, six more (`docker/tests/test-mock.sh`, `ci/mock/test/server.test.mjs`'s health count, which reads the folder); the test classes of area `Agent` in shard `lane-a`, two more (`docker/tests/test-ci-config.sh`). The scanning checks of Rule 19, `Test.Data.Tables:TestSqlNames` and `docker/tests/test-bridge-guide.sh`, are unaffected: this story adds no table, column or enum value. `ci/checks.sh` runs the second.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
