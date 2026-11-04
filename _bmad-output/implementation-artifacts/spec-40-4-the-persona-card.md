---
title: 'Story 40.4: The Persona card'
type: 'feature'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 40.8's `GET` and `PUT /api/v1/persona` exist, but the page has no way to show or change a person's persona, so nobody can pick a preset, a language or their own words.

**Approach:** Add a "Persona" section to the status rail: one slot in `rail-view.ts`, a new component under `web/src/app/rail/persona-card/` that reads `GET`, offers the presets in a Change disclosure, sends `PUT`, and shows the server's saved line or refusal beside the field. Two typed client methods go on the one `ApiClient`. No server change.

## Boundaries & Constraints

**Always:**
- Every text is EXPERIENCE.md › Later Steps › Personality's, word for word, or one of the two help sentences that U-278 fixed in `epics.md` Story 40.4. The Language help is the UX help, one space, then "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so." The "Your own words" help is exactly "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. If this persona writes in another language, the model is only told not to say so." No other all-clear wording anywhere, no rewording, no merge.
- The saved line and every refusal are the server's own `message` / `error.message`. The page holds no copy of them.
- Fixed strings sit in a framework-free view module (`PERSONA_TEXTS`, erasable TypeScript, type-only imports) and are bound by interpolation. No literal text in the template. Source stays ASCII (Rule 14).
- Native, labelled controls that work by keyboard: radios (arrow keys), a text input, a textarea, and `app-server-button` for Save (busy, 10 s notice). A refusal is linked to its field (`aria-describedby`, `aria-invalid`). Change is a disclosure (`aria-expanded`, `aria-controls`). Esc collapses it only while focus is inside it, and focus then goes to Change (EXPERIENCE.md Interaction Primitives).
- The card announces nothing. Focus moves only on the user's own press: Esc, and the pending link through `Layout.focusRegion`.
- Smallest footprint in contended files. `rail-view.ts`: one `RAIL_TEXTS` entry, one `SectionId` member, one appended `sections.push`, and the doc line that lists the sections. `api-client.ts`: one `import type` line and one block of two methods at the end of the class. `status-rail.ts`: one import and one `@else if` branch.

**Never:**
- An edit to an Epic 7 file other than the two test files this spec names, and only after the lead's ruling (see Clarification Needed): `web/src/app/approvals/**`, `web/src/app/live/payloads.ts`, `web/src/app/msg/catalog.ts`, `web/src/app/shared/layout-view.ts`, `web/e2e/support/iris.ts`, `web/scripts/{approval-sources,approval-view,catalog,catalog.test,either-way-line-sources,playwright-projects}.*`.
- Any server class, `Checks/ReplyGuard.cls`, `docker/**`, `Install/**`, `src/module.xml`, `module.xml`, `preload/**`, `src/cpf/**`, `release/**`, `ci/units.sh`.
- A new catalog key, a new fixture user, a `role="status"`/live region, `maxlength` on the textarea (a paste must never be cut silently), or a claim that the guard covers other languages.
- The approval card for a `setting` request, proposals, or the rail row's title for one (Stories 40.5 and 40.6).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default | `GET` 200 `{"preset":"professional",...,"customOffered":true,"pendingRef":""}` | The rail's last section is h3 "Persona" (no count). Its title is "Professional (default)" and its detail "Calm, short and plain." Change is collapsed. | No error expected |
| Open Change | Enter on Change | `aria-expanded` true. Shows the intro, then a radio group labelled by the heading and described by the intro: 6 radios named by the UX names, each described by its description, with the current one checked. No online-demo note. | No error expected |
| Language chosen | Another language selected | Below it: "Language" input, prefilled with the stored name, described by the help (UX help + U-278 language sentence) | No error expected |
| Own words chosen (local) | Your own words selected | Below it: a textarea labelled "Your own words", prefilled, described by the U-278 custom sentence and the counter "{n} of 1,000 characters", where n is `value.length` (UTF-16 units, equal to IRIS `$Length`: measured on slot A, emoji = 2) | No error expected |
| Save accepted | Save with Pirate | `PUT {"preset":"pirate","language":"","custom":""}`. The 200 `message` shows under Save. Title and detail become Pirate's. The disclosure stays open. | No error expected |
| Values a preset does not use | Language typed, then Pirate saved | The body sends `language` only for `language` and `custom` only for `custom`; every other value is "" | No error expected |
| Refused language | Save with "Spanish!" | 400 `bad_language`. Its message shows under the Language field, which gets `aria-invalid="true"` and the error id in `aria-describedby`. Title unchanged. | Field keeps the typed text |
| Refused custom | Save with text holding `{{`, or over 1,000 | 400 `bad_custom`. Its message shows under the textarea, linked the same way. | Field keeps the text |
| Other refusal or failure | 400 `bad_preset`/`custom_not_offered`/`bad_persona`, 500, 501 | `error.message` shows under Save. The card re-reads `GET`, so the title shows what is stored. | No claim of its own |
| No readable message | Network error, or a body without `error.message` | `BUSY_NOTICE` ("Couldn't reach OcuTalon. Try again. Nothing was changed.") under Save, then `GET` re-read | As above |
| Slow call | No answer in 10 s | `app-server-button`'s own busy notice. A late answer still shows its line. | ServerButton |
| Pending request | `pendingRef` non-empty | "OcuTalon suggested a change. It waits for your answer in Approval requests." as one link-styled button. A press focuses the request's card in the chat (`[data-part="approval"][data-key=ref]` under `app-chat-panel`) when it is drawn, else `#rail-heading-approvals`. | No error expected |
| Pending changes | The set of pending approval Refs in the live store changes | The card re-reads `GET`, so the line appears and leaves with the request | No error expected |
| Online demo | `customOffered` false | 5 radios (no Your own words) and the Language field. The disclosure shows "On the online demo you can choose a preset or a language. Your choice lasts for this visit." after the intro. | No error expected |
| Read fails | `GET` not 200 | Heading only: no row, no Change. It tries again on the next pending-Refs change. | No false state |
| Esc | Focus inside the open disclosure, Esc | Collapses it. Focus goes to Change. | No error expected |

</intent-contract>

## Code Map

- `web/src/app/rail/rail-view.ts` -- framework-free view of the rail. `RAIL_TEXTS` line 27 (`telegramHowTo` is last). `SectionId` line ~94. `railView` (end of file) pushes Telegram, then four `listSection`s: append the `persona` section after them in the Telegram shape (`rows: []`, `empty: ''`, `hint: ''`, heading = spoken = label). Contended with Epic 39, which has no web change yet.
- `web/src/app/rail/status-rail.ts` -- renders `@if (section.id === 'telegram') { <app-telegram-card .../> } @else {...}` (template ~line 103): add `@else if (section.id === 'persona') { <app-persona-card /> }` and the import. `requestCard(ref)` / `CHAT_LIST` and `jump()` (lines 32-33, end) are the jump pattern the pending link follows. Its `FOCUS_RULE` is for rows only.
- `web/src/app/rail/telegram-card/telegram-card.ts`, `telegram-card-view.ts` -- the sibling to extend: OnPush, signals, `inject(ApiClient)`, `app-server-button` (line 84), a framework-free view module with `*_TEXTS`.
- `web/src/app/api/api-client.ts` -- `ApiClient`, the one typed client (spine convention). `BASE`, `events()` is the last method. `api-types.ts` is contended, so the new types go in a new file.
- `web/src/app/shared/server-button.ts` -- `action` input (Observable), `describedBy`, `BUSY_NOTICE` export.
- `web/src/app/shared/layout.ts` -- `focusRegion(selector)`, the user's own move (status-rail's jump uses it).
- `web/src/app/live/live-state.ts` -- `store()` signal. `rail-view.ts` `pendingApprovals(store)` gives the pending requests whose Refs the card watches.
- `web/src/app/mailbox/simulated-mailbox.ts` -- the existing field-error markup (`aria-invalid`, error text beside the field) to mirror. DESIGN `field-error`: `danger-ink`, icon `circle-alert`, `body-sm`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (read only) -- `GetPersona` answers `{"preset","language","custom","customOffered","pendingRef"}`. `PutPersona` answers 200 `{"result":"done","message","preset","language","custom"}` or `{"error":{"code","message"}}` (400 `bad_preset`, `bad_language`, `bad_custom`, `custom_not_offered`, `bad_persona`; 500 `not_saved`, `server_error`; 501 `not_built`). See spec-40-8's matrix.
- `src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls` (read only) -- `Parameter RESERVED` line 19, `Parameter BANNED` line 22, comma-separated. Matching ignores case, treats any whitespace run as a space, and treats U+2019 as an apostrophe.
- `web/scripts/ux-strings.test.mjs` (Epic 7 file) -- `IMPORTED` lines 41-64 must list every exported `*_TEXTS`. Every inventory string needs exactly one `SOURCES` entry: `ux` list lines 156-439, `ac` object lines 449-460. Epic 7's hunk is at lines 516-519 (the end of `ruled`).
- `web/scripts/floor-sources.test.mjs` (Epic 7 file) -- line 155 pins every template key binding (`decision-row.ts down escape` is the sibling). Epic 7's hunks are at lines 7-10 and 458-461.
- `web/scripts/announce-focus-sources.test.mjs` -- `FOCUS_CALLS` (~line 125) counts `.focus(` per file. The rail files must stay silent (line 93).
- `web/scripts/rail-view.test.mjs` lines 140-150 and 566, and `web/e2e/rail/rail.spec.ts` R1 (lines 104-112, 478-480: five sections) -- they pin the section list.
- `web/scripts/telegram-card-view.test.mjs` -- the model for the new node test (dynamic `import()` of the `.ts` file).
- `web/e2e/api/persona.spec.ts` lines 28-50 -- `sessionRef`, `forget`, `prepare` (README account, `ForgetPerson`, `onlineDemo` off, no `setting` rows): move them to a shared helper. `web/e2e/sign-in/helpers.ts` `signInReadme` line 104. `web/e2e/support/iris.ts` (read only, Epic 7's) `seedApproval(user, {kind:'setting'})` line 717, `cleanFixtureRows` line 660, `irisScript`/`chk`/`quoted`.
- `web/playwright.config.ts` -- project `chromium` (testDir `./e2e`) picks up `web/e2e/persona-card.spec.ts`. `playwright-projects.test.mjs` needs no edit. Unit `live:sign-in` (group `browser`) runs it. Path order puts it after `live/` and before `phone/`, so probably part 3 of 3 (estimate).

## Tasks & Acceptance

**Execution:**
- `web/src/app/api/persona-types.ts` -- new: `PersonaState` (the `GET` body), `PersonaPut` (`{preset, language, custom}` strings), `PersonaSaved` (the 200 body). Keeps `api-types.ts` untouched.
- `web/src/app/api/api-client.ts` -- one `import type` line, and at the end of the class `persona(): Observable<PersonaState>` (`GET ${BASE}/persona`) and `savePersona(body: PersonaPut): Observable<PersonaSaved>` (`PUT`, the interceptor adds the envelope).
- `web/src/app/rail/persona-card/persona-card-view.ts` -- new, framework-free. `PERSONA_TEXTS`: intro, `change`, `save`, `language`, `languageHelp` (UX), `languageAllClear` and `customAllClear` (U-278), `customLabel` "Your own words", `counter` "{n} of 1,000 characters", `pending`, `demoNote`. `PRESETS` (id, name, description) in the UX table's order. Pure helpers: `presetOf(id)`, the options for `customOffered`, `languageHelpText()` (help + space + sentence), `counterText(text)`, `saveBody(preset, language, custom)`, and `failureOf(error)` -> `{ where: 'language' | 'custom' | 'save', message }`, with `message` '' when there is none. The component shows `BUSY_NOTICE` for '', because a view module cannot import `server-button.ts` at run time.
- `web/src/app/rail/persona-card/persona-card.ts` -- new component `app-persona-card` (OnPush, signals) as the matrix says. It reads `GET` on creation and whenever the joined pending-approval Refs of `LiveState.store()` change, and keeps form values in signals. Ids per instance. One `.focus(` (Change, after Esc). The pending link calls `Layout.focusRegion`. Styled from DESIGN tokens: title `body-strong`, detail `body-sm`, descriptions `body-sm`, link `action-ink` underlined, targets at least `space-target-min`, no attention colors.
- `web/src/app/rail/rail-view.ts` -- `RAIL_TEXTS.persona: 'Persona'`, `'persona'` in `SectionId`, the appended section, the doc line.
- `web/src/app/rail/status-rail.ts` -- render `<app-persona-card />` for `persona`. Update its doc comment's section list.
- `web/scripts/persona-card-view.test.mjs` -- new node test:
  - The UX strings, names and descriptions, exactly.
  - (a) `languageAllClear`, `customAllClear` and `languageHelpText()` equal the U-278 and UX strings, written out literally.
  - (b) Neither help text contains a `BANNED` or `RESERVED` phrase. The test parses the phrases from `ReplyGuard.cls` (it asserts it found at least 6 and 3), then compares case-folded, whitespace-collapsed, with U+2019 as `'`, as a substring.
  - `counterText` with an emoji (`'\u{1F6A2}'` counts 2), `saveBody` for each preset, and `failureOf` for every code, for no body and for no message.
- `web/scripts/rail-view.test.mjs` -- the section lists gain `persona` last.
- `web/scripts/announce-focus-sources.test.mjs` -- `FOCUS_CALLS`: `'app/rail/persona-card/persona-card.ts': [1, 'Change, after the user's own Esc collapses its disclosure']`.
- `web/scripts/ux-strings.test.mjs` -- RULED at the spec gate (Design Notes), after the lead's integrate-forward:
  - `IMPORTED`: one row after line 63.
  - `ux` entries at the end of the `ux` list for every new string EXPERIENCE.md holds.
  - One `ac` key `'Story 40.4 (U-278: the two help sentences of the Language and Your own words fields)'` with the two sentences.
- `web/scripts/floor-sources.test.mjs` -- RULED at the spec gate (Design Notes): add `'app/rail/persona-card/persona-card.ts down escape'` to the line-155 list.
- `web/e2e/support/persona.ts` -- new: `sessionRef`, `forget`, `prepare`, moved from `persona.spec.ts`.
- `web/e2e/api/persona.spec.ts` -- import them. No case changes.
- `web/e2e/persona-card.spec.ts` -- new, README account via `signInReadme`. `prepare` + `forget` before each case, `forget` and `cleanFixtureRows` in `finally`. Cases:
  - PC1: the defaults.
  - PC2: keyboard only, open Change, arrow to Pirate, Save. Pins the saved line, the new title, the stored key (irisScript), and Pirate again after a reload.
  - PC3: Another language. The help text exactly; "Spanish" saved; then "Spanish!" refused beside the field with `aria-invalid`, and the key still "Spanish".
  - PC4: Your own words. The label; the help exactly; the counter "0 of 1,000 characters", then "5 of 1,000 characters" after "Ahoy!"; saved; a `{{` refusal beside the textarea.
  - PC5: a pending `setting` request via `seedApproval` shows the sentence. Pressing it focuses `#rail-heading-approvals`, since no chat card is drawn.
  - PC6: the demo variant. `page.route` on `GET /persona` passes the real answer with `customOffered` false: 5 radios, the Language field, the note.
  - PC7: Esc inside the open disclosure collapses it, and Change has focus.
- `web/e2e/rail/rail.spec.ts` -- R1 and the Telegram case: six sections, "Persona" last.

**Acceptance Criteria:**
- Given a signed-in person, when the page loads, then the status rail's last section is the "Persona" card from `web/src/app/rail/persona-card/`, slotted in `rail-view.ts`, showing the current choice's UX name and description (FR-67).
- Given Change, when the person picks a preset (with a language name; on a local install with their own words against the counter) and presses Save, then the page sends `PUT /api/v1/persona` and shows the server's "Saved. Applies from your next message. Recorded in the audit log.", or the refusal's message beside the field (FR-67, FR-68).
- Given the Language and Your own words fields, when they render, then their help texts are exactly the UX text plus the U-278 sentences above, and a test pins them and that neither contains a `ReplyGuard` BANNED or RESERVED phrase (DW-664 ruling, U-278).
- Given the card, when it is used with the keyboard alone, then every control has a label, radios move with arrows, Save and Change work with Enter, and Esc collapses the open disclosure to Change (NFR-25, NFR-26).
- Given a pending persona request, when the card renders, then it shows "OcuTalon suggested a change. It waits for your answer in Approval requests." as a link to the request (FR-70).
- Given `customOffered` false (the online demo), when the card is opened, then it offers the presets and the Language field only, and the online-demo note (FR-67, FR-68).
- Given `web/e2e/persona-card.spec.ts` on the sign-in stack, when it runs, then it covers these states, a refused language name and the demo variant, against the real routes (Rule 3).

## Spec Change Log

- 2026-11-04, spec gate (lead): the plan's intent gap on the two Epic 7 test files is ruled by option (b), met because Epic 7 merged; the `## Clarification Needed` section is replaced by the ruling under Design Notes. No frozen text changed.

## Review Triage Log

## Design Notes

**Governing decisions:**
- AD-1: the save is `PUT`, which 40.8 turns into `SetPersona` from `web_user`.
- AD-4 and AD-19: the session comes from the server; the card sends none. Validation and writing are `SettingsOps`'.
- AD-7: preset ids and names. Display names live only in the web app.
- AD-12: the live store, read only.
- AD-13: the envelope, 401, errors as text, no `bypassSecurityTrust*`.
- AD-29: `web/` is Lane B's, and the rail takes appended entries.
- AD-33: the route table.
- Conventions: Angular (standalone, signals, one typed API client, DESIGN tokens), Announcements and focus, REST error shape, Tests (Playwright under `web/e2e/`).
- No AD is contradicted.

**U-268.** The card relies on AD-1 only for `PUT` being a `web_user` submit, and on no closed `tool`-origin list. It does not touch AD-14's routing. Story 33.2's additions do not reach it, and Epic 33 has no `web/` change.

**Integration ACs (Rule 1/2).** The card is a consumer. PC2 to PC5 exercise it against the real routes and the real `SettingsOps` items on the sign-in stack, not a mock. PC6 alone rewrites one field of the real answer (reason below).
- Consumes: Story 40.8's `GET`/`PUT /api/v1/persona`; Story 40.2's refusal texts, through the server.
- Consumed-by: Story 40.6 (its `setting` request reaches the card through `pendingRef`, and the link lands on its chat card once that card exists).

**Extend, don't copy (Rule 2).** The card follows `telegram-card` (component plus framework-free view module, `app-server-button`). The pending link follows `status-rail`'s `jump()` and `requestCard`. The `persona.spec.ts` helpers move to `web/e2e/support/persona.ts` rather than being copied. `web/e2e/support/iris.ts` is Epic 7's, so they don't go there.

**Ledger inbox (Rule 17).** None for this story.

**Decided in-stage:**
- The Persona section goes last in the rail (appended; the UX gives no position).
- The intro and the online-demo note sit inside the Change disclosure. The collapsed card shows only the title, the detail and the pending line (DESIGN L864's row pattern).
- The collapsed card shows no language name: the UX has no text for one, and the Language field shows it.
- Strings EXPERIENCE.md holds verbatim are reused for parts the persona table leaves unnamed: the counter is the heartbeat card's "{n} of 1,000 characters", the textarea's label is "Your own words" (the option's name, and the AC's and U-278's name for the field), and the buttons are "Change" and "Save" (AC words, both in EXPERIENCE.md). The radio group is labelled by the card's heading, so it needs no new legend.
- The saved line and the refusals come from the server, so the page cannot drift from `SettingsOps`. A failure with no message shows the UX's own busy-failure sentence (`BUSY_NOTICE`), and the card re-reads `GET` so the title stays true.
- The body carries only the values the chosen preset uses. Unused ones are stored empty anyway (40.8 matrix).
- No `maxlength`: the counter and the server's refusal handle the limit.
- The pending link is a link-styled button, not an `<a href="#...">`: the app routes by hash. It targets the request's chat card, where Approve and Reject will be (Story 40.6 sends an `approval` notification), and falls back to the Approval requests heading, which the sentence names.
- The card re-reads `GET` when the pending approval Refs change, so the pending line never outlives the request.
- PC6 rewrites `customOffered` on the real answer instead of turning on the real `onlineDemo`. On the sign-in stack, the real flag switches the whole page to the online demo (polling, the session gate, the reset countdown; 12 page files read it). The frame and banner specs fake it the same way. The real online-demo refusal of `custom` stays pinned by `Test.Web.PersonaApi` (Story 40.8).
- The U-278 test reads the lists from `ReplyGuard.cls` instead of holding a copy, so it follows any later change to them. It checks substrings, which is stricter than the guard's word-bounded match.
- No announcement: the UX's announcement table has no persona row, and the rail files are silent by test. The result line follows Save in reading order and is in Save's `describedBy`.
- `BUSY_NOTICE` and `app-server-button` give the 10 s rule. No new busy code.

**Lead ruling at the spec gate (2026-11-04, runner A, category decide).** The plan's intent gap is resolved by its option (b), now met: Epic 7 merged to the feature branch at 417f17c5 (record ac2c4549, 2026-11-04 about 21:3xZ), so `web/scripts/ux-strings.test.mjs` and `web/scripts/floor-sources.test.mjs` are no longer another open epic's in-flight files (Epics 33 and 39 do not change them). The lead integrates `origin/feature/OCT_OcuTalon_MVP` forward into `OCT-epic40` before this story's implement spawn; the implement stage then makes the edits the Tasks mark "ONLY IF RULED" as ordinary edits: the `IMPORTED` row, the `ux` entries, the U-278 `ac` key, and the line-155 binding. Each stays an append (no existing entry changes), and the implement stage re-checks `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for N in 33 and 39 before editing them. The reuse of "{n} of 1,000 characters", "Your own words", "Change" and "Save" is decided as planned: each is author-accepted text already in EXPERIENCE.md, and the 40.4 acceptance criteria name each part (Change, Save, "Your own words", a counter up to 1,000 characters), so no new public text is introduced.

**Footprint:**
- Contended paths touched: `rail-view.ts`, plus `api-client.ts` (`api/**`), as the lead's plan allows.
- Outside the contended list: `status-rail.ts`, `announce-focus-sources.test.mjs`, `rail-view.test.mjs` and `rail.spec.ts`. Report them under `footprint_extensions` if they count as such.
- New files only otherwise.

## Verification

Run every call from the worktree root with `timeout: 600000`, one per call. Prefix each `ci/iris.sh` call with `<A>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=40 stage=implement'`. The fresh tag is `e40s4i`; warm `e40s4iw` is not needed, because no IRIS class changes. The story changes no IRIS code, so it makes no IRIS MCP call. If one is needed, it names `server` `ocutalon-slot-a` and `namespace` `OCUTALON`, after `iris_server_info`, with one `iris_execute_tests` per message.

**Commands:**
- (loop) `node --test web/scripts/persona-card-view.test.mjs` -- passes.
- (loop) `node --test web/scripts/rail-view.test.mjs` -- passes.
- (loop) `node --test web/scripts/ux-strings.test.mjs` -- passes (after the ruling's edit).
- (loop) `node --test web/scripts/announce-focus-sources.test.mjs` -- passes.
- (loop) `node --test web/scripts/floor-sources.test.mjs` -- passes.
- (loop) `node --test web/scripts/playwright-projects.test.mjs` -- passes.
- (loop) `npm --prefix web run lint` -- passes (the e2e types).
- (loop) `npm --prefix web run build` -- passes (the app's types and the generated-file checks).
- (loop) `<A> OCUTALON_RUN_TAG=e40s4i ci/iris.sh build` (the bundle), then `<A> OCUTALON_RUN_TAG=e40s4i ci/iris.sh live sign-in --part 3/3`, then teardown -- the `PART` line lists `persona-card.spec.ts` and `rail/rail.spec.ts`, and the part passes. If a file is in another part, run that part too, one per call.
- (once) `npm --prefix web test` -- every node test passes.
- (once) `<A> OCUTALON_RUN_TAG=e40s4i ci/iris.sh live sign-in --part 1/3` and `--part 2/3`, one per call (`api/persona.spec.ts` with the moved helpers), then `ci/iris.sh live floor`, then `ci/iris.sh live demo-path`, then `<A> OCUTALON_RUN_TAG=e40s4i ci/iris.sh teardown` -- each passes; the demo path stays green with the new section.
- (once) The `ci/checks.sh` scripts that read `web/`, one per call: `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-readme.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-web-build.sh` -- each passes. The rest of `CHECK_SCRIPTS` and the other groups are left to CI.
- The new spec runs in CI's `browser` group inside `live:sign-in`, with no `ci/units.sh` edit. It adds about 7 short cases to a group measured at about 1,580 to 1,830 s.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):**
- AC 1: the `persona` push removed -> `rail-view.test.mjs` and PC1 red.
- AC 2: `savePersona` sends `POST` -> PC2 red. `failureOf` routes `bad_language` to Save -> PC3 red.
- AC 3: one word of `customAllClear` changed -> the node test's exact pin red. "no problems" appended to `languageAllClear` -> the BANNED check red.
- AC 4: the Esc handler removed -> PC7 red.
- AC 5: `pendingRef` ignored -> PC5 red.
- AC 6: the options ignore `customOffered` -> PC6 red.
- AC 7: the test list itself.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

Shared surfaces: the rail's section list goes from 5 to 6 (`rail-view.test.mjs`, `rail.spec.ts` R1 and the Telegram case; the floor specs read headings by id only). The `*_TEXTS` inventory and its `SOURCES` (`ux-strings.test.mjs`). `FOCUS_CALLS` and the key-binding list. The README account's persona keys and `setting` rows on the sign-in stack, which both persona specs clear before and after themselves.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none (the plan's intent gap was ruled at the spec gate; see Design Notes)
