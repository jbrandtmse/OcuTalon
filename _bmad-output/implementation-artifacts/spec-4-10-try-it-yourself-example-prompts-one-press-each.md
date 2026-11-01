---
title: 'Story 4.10: "Try it yourself" example prompts, one press each'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge who has finished the demo guide, or who opens an empty chat, has to think of what to ask to try abilities the guide does not show. The owner decided on 2026-11-01 (relayed by the Contest Planner under delegation; the owner: "Yes to both questions.") that the demo view offers a few example prompts, each sent with one press.

**Approach:**
- **One shared row.** A new component, the "Try it yourself" row, holds four chips. It renders only in the demo view (Story 4.9's `DemoView.on()`), in two places: after the finish state's "More to try" line and after the empty chat's last line.
- **A press is an ordinary turn.** A press sends the chip's text through `ChatOutbox.send(text)`, the composer's own path: never `fromGuide`. While a turn is in flight, or the allowance is used up, the chips are `aria-disabled` and a press sends nothing.
- **Mock and docs.** Each chip's exact text gets a new prompt scenario under `ci/mock/scenarios/B/`. E2e cases on the CI mock run in `live:sign-in`. EXPERIENCE.md and DESIGN.md gain the row with markers.

## Boundaries & Constraints

**Always:**
- **The texts, verbatim, in a framework-free module.** `web/src/app/chat/try-it-view.ts` exports `TRY_IT_TEXTS`:
  - `label: 'Try it yourself'`;
  - `prompts`, in this order: `'Which productions are running?'`, `'Is anything wrong right now?'`, `'What was that failure earlier?'`, `'What can you do?'`.

  These five are the only new public strings, and they are written into EXPERIENCE.md. Straight ASCII.
- **Where.** The row is `app-try-it-row` (`web/src/app/chat/try-it-row.ts`). It renders nothing unless `DemoView.on()`, and it never reads `demoMode`.
  - **Empty chat:** in `app-empty-chat`'s `.empty`, after the last `<p class="line">`.
  - **Finish state:** in `demo-guide.ts`'s `.finish`, after `<p class="more">` and before Run again.
- **Markup.**
  - A `<div role="group">` labelled (`aria-labelledby`) by a visible `<p>` "Try it yourself". The label is never a heading, because the page's heading lists are pinned. Its id is unique per instance (a module counter), because both rows can be on the page at once.
  - Then one native `<button type="button">` per prompt, named by its text alone: no `aria-label` and no icon.
  - No element of the row carries the class `line`, `more`, `headline` or `chip`. Tests read `app-empty-chat .line` and `.finish .more`.
- **A press.** If a turn is in flight or the allowance is used up, nothing happens. Otherwise `this.outbox.send(text)`, with one argument. That is the composer's path:
  - a new clientId each time;
  - `fromGuide` false;
  - it counts against the server's allowance;
  - a 429 `allowance` or an online-demo 503 refusal takes the outbox's typed-message path (the text goes back to an empty composer).

  No `Announcer` call, no `.focus(` call, no key binding, no `ApiClient`.
- **"In flight"** is `turnInFlight(chat, outbox)` in `try-it-view.ts` (pure). It is true when:
  - an outbox entry's status is `sending` or `sent` (posted, but the store doesn't hold it yet); or
  - a store `chat.message` has state `queued` or `running`.

  A `failed` entry is not in flight.
- **Disabled.** While a turn is in flight or `AllowanceState.active()` is set:
  - every chip has `aria-disabled="true"`. It is never `disabled`, so it stays focusable and keeps the focus a press gave it. This is the page's rule for the composer, the guide's Send and the mailbox chips.
  - While the allowance is used up, every chip is also `aria-describedby` the composer's existing reason paragraph. `composer.ts` exports `COMPOSER_REASON_ID = 'composer-allowance-reason'` and uses it for its own `reasonId`. No new reason text.
- **Look.** The actionable chip of DESIGN.md: the `.button` base class, plus the row's own class. That class reads `--space-target-min` as `min-height`, `0 var(--space-3)` padding, and the `--sample-email-chip-background`, `-foreground`, `-border` and `-radius` tokens, with `-background-hover` on `:hover:not([aria-disabled='true'])`.
  - The chips wrap (`flex-wrap`, `gap: var(--space-2)`). They are centred in the empty chat and start-aligned in the finish.
  - The label is in `--type-body-sm-*` and `--ink-muted`.
  - No `transition`, no fixed `height`, and width queries only through `LAYOUT_QUERIES`.
- **Focus.**
  - The finish's row host carries `data-guide-focus="tryIt"`, and `demo-guide.ts`'s `FINISH_PARTS` gains `'tryIt'`. So a chip that held focus when Run again replaces the finish hands it on like the finish's other parts.
  - In the empty chat a press removes the empty chat. The chat panel's existing focus rule then puts focus on the main region. Nothing new moves focus.
- **Mock scenarios.** Four new files in `ci/mock/scenarios/B/`, each with `match.prompt` equal to its chip's exact text:
  - `try-it-productions.json`: `[{200, toolUse list_productions {}}, {200, text "The CI mock listed the productions."}]`;
  - `try-it-anything-wrong.json`: `[{200, toolUse check_status {}}, {200, text "The CI mock read the check results."}]`;
  - `try-it-failure-earlier.json`: `[{200, toolUse recent_activity {}}, {200, text "The CI mock read the recent activity."}]`;
  - `try-it-what-can-you-do.json`: `[{200, text "The CI mock answered what OcuTalon can do."}]`.

  No reply text holds a reserved sentence or a banned phrase of `OcuTalon.Checks.ReplyGuard` (AD-28).

**Never:**
- **Out of footprint.** Never touch:
  - `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts` or `web/src/app/rail/telegram-card/**`;
  - `web/e2e/demo-path/0[2-6]-*.spec.ts`, `web/e2e/support/*`, `web/e2e-online/*`, `web/e2e/demo-switch/mailbox.spec.ts` or `web/e2e/answers/close-loop.spec.ts`;
  - `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, `ci/mock/test/*`, `ci/units.sh`, `ci.yml` or any other `ci/**` or `docker/**` file;
  - any server class, including `Tools/RecentActivity.cls`, `Agent/Chat.cls` and Lane A files.
- **Mock files.** Never edit `guide-*.json` or any existing scenario file.
- **Append-only tests.** In `ux-strings.test.mjs` and `guide-view.test.mjs`, never change or delete a line.
- **No new evaluation case, no new CI unit, no new e2e folder.** No change to a group's membership, the iris matrix or a job name.
- **Text.** No public sentence beyond the five strings (a veto item). No "From the demo guide" tag on a chip's message. Nothing is sent without a press, and a press sends once.
- **Escalate, don't adjust.** If a new scenario file needs a change in the mock's loader, index or count tests, HALT with `intent gap` naming it.

## I/O & Edge-Case Matrix

"Demo view" is `DemoView.on()`: the server's `demoMode` and the switch both on. "In flight" and "used up" are as in Always.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1 | Demo view, empty chat | After the empty chat's last line: the group "Try it yourself" with its four buttons in order, each named by its text, `type="button"`, none `aria-disabled`. Nothing is sent | none |
| 2 | Demo view, guide finished | The same row in `.finish`, after "More to try" and before Run again. With an empty chat as well, both rows show, with distinct label ids | none |
| 3 | Switch off, server `demoMode` false, or snapshot loading or failed | No row anywhere | none |
| 4 | Press a chip in the empty chat (click, Enter or Space), nothing in flight, allowance free | **(Integration)** Through `ChatPanel`'s normal send:<br>- exactly one `POST /messages` `{clientId, text: <exact chip text>, fromGuide: false}`;<br>- the empty chat gives way, and focus is on the main region (the focus rule);<br>- the user message shows the exact text with no "From the demo guide" caption.<br>On the CI mock, the reply lands with the scenario's text and its decision strip, whose line 1 ends in the trace link. For chips 1-3 the turn decision has one tool step, ok (Listing the productions / Reading the check results / Reading recent activity). Chip 4 has none | A refusal (429 allowance, online 503) follows the typed-message path |
| 5 | Chip 2, session watching nothing | The reply's `app-check-rows .sentence` is the code-built "I'm not watching any productions yet, so I can't say. Ask me to watch one." The reply text holds no reserved sentence or banned phrase (AD-28) | none |
| 6 | Chip 3, session with no incident | Chat's second request carries one tool result: `{"ok":true,"hours":24,"incidents":[],"message":<RecentActivity NONE>}`. The tool step is "Reading recent activity", ok. The reply holds no reserved sentence or banned phrase. The canned text is never asserted as the tool's | none |
| 7 | A finish chip pressed, then the page's poll held (turn in flight) | Every chip `aria-disabled="true"` with no description. A second press (Enter on the focused chip) posts nothing, and focus stays on it. Once the reply lands, the chips are enabled again | none |
| 8 | Allowance used up (`status` `allowance` active) | Every chip `aria-disabled="true"`, `aria-describedby="composer-allowance-reason"`, whose text is the composer's reason. Click or Enter posts nothing | none |

</intent-contract>

## Code Map

**New:**
- `web/src/app/chat/try-it-view.ts`: `TRY_IT_TEXTS` and `turnInFlight(chat: readonly LiveItem[], outbox: readonly OutboxEntry[]): boolean`.
  - Framework-free: type-only imports, erasable TypeScript only, like `chat-view.ts` and `shared/check-sentence.ts`, so that Node imports it.
  - Siblings: `header/demo-view-texts.ts` (a texts module) and `chat-view.ts:407` `isFreshChat` (a pure reader of the same two lists).
- `web/src/app/chat/try-it-row.ts`: `app-try-it-row`, OnPush, standalone. It injects `DemoView`, `LiveState`, `ChatOutbox` and `AllowanceState`.
  - Siblings it extends:
    - `guide/demo-guide.ts:583-591` `send()`: the allowance guard and the guard against a repeat press, minus `fromGuide`;
    - `chat/composer.ts:137-148` `send()`: the allowance guard and `outbox.send`;
    - the mailbox's chip row, `mailbox/simulated-mailbox.ts:119-131,264-268` (`.chips` flex-wrap);
    - `shared/server-button.ts:62-73` `.button-chip`, the actionable-chip look on the `sample-email-chip` tokens. A copy of its six declarations; see Decided 6.
- `ci/mock/scenarios/B/try-it-{productions,anything-wrong,failure-earlier,what-can-you-do}.json`: as in Always.
  - Siblings: `B/guide-reminder.json` (`[toolUse, text]`, matched by prompt) and `B/guide-watch.json` (`[text]`).
  - The loader (`ci/mock/scenarios.mjs:236-304`) refuses a repeated prompt, and a prompt that contains another. None of the four contains another, or the two guide prompts.
  - `ci/mock/test/*` pins no count: `scenarios.test.mjs:120` says so, and `server.test.mjs:674,685` count from the committed folder.
- `web/scripts/try-it-view.test.mjs`, `web/scripts/try-it-sources.test.mjs`, `web/e2e/chat/try-it.spec.ts`: Tasks.

**Edited:**
- `web/src/app/chat/empty-chat.ts:24-39`: add `<app-try-it-row />` after the third `<p class="line">`, inside `.empty`, and import `TryItRow`. The doc comment names the row.
- `web/src/app/guide/demo-guide.ts`:
  - `:42` `FINISH_PARTS` gains `'tryIt'`;
  - `:177-178`: `<app-try-it-row data-guide-focus="tryIt" />` between `.more` and `.run-again`;
  - `imports` gains `TryItRow`;
  - the class doc comment (`:89-90`) names the row.
- `web/src/app/chat/composer.ts:104`: `export const COMPOSER_REASON_ID = 'composer-allowance-reason';`, and `reasonId = COMPOSER_REASON_ID`.

**How a chip's turn runs** (read only):
- `ChatOutbox.send` (`chat-outbox.ts:62-72`) posts at once.
- `Conversation` sends Decide twice, decide then turn (`Core/Conversation.cls:11-12`).
- The mock matches a prompt anywhere in the newest user message with text (`mock.mjs:440-444`). A prompt match has no countdown, so it answers `replies[min(k, last)]` (`mock.mjs:33-36`, `:452-463`; AD-22). So the triage request (k 0) and Chat's first request (k 0) both get `replies[0]`.
  - Triage's turn on a tool-use or plain-text reply is a fallback decision. The turn still runs: `demo-path/03-reminder.spec.ts:13-14` and `Test/Schedule/ReminderChat.cls:294-306` show this for `guide-reminder`.
  - Chat calls the tool, and its request carrying the tool_result (k 1) gets `replies[1]`.

**E2e helpers** (read only):
- `web/e2e/reminder/chat.spec.ts:44-97`: the pattern to copy for the RAIL user:
  - `pointKeys` with `SessionMark` in `beforeAll`;
  - `DropSince`, `restoreKeys` and `WaitRecords` in `afterAll`;
  - `ReminderFixture.RemoveTurns(s.Ref)` and a 0-turns check in `afterEach`.
- `support/devices.ts:180-189` (`pointKeys`, `restoreKeys`); `support/iris.ts` (`fixtureUser('RAIL')`, `irisScript`, `chk`, `quoted`); `support/floor.ts` (`replyOf`, `composerOf`, `loadedAfter`, `mainOf`); `support/api.ts` (`changeSnapshot`, `holdPoll`, which needs `page.clock.install()` before load, and `MESSAGES`); `sign-in/helpers` `signIn`.
- `chat/chat.spec.ts:50-56` `watchPosts`, and `:935-947` C15's strip and trace-link assertions.
- `guide/guide.spec.ts:28-40` `guideOf` (a finished view: all steps done, `finished: true`) and `:75` `liveEvents` (how a case rewrites its polls).
- `demo-switch/view.spec.ts:266`: the `allowance` status shape `{condition:'allowance', active:true, slots:{limit:20, time:'2037-07-01T12:00:00Z'}}`.
- IRIS test helpers, called through `irisScript`:
  - `OcuTalon.Test.Agent.RunnerFixture`: `StepsOf(decisionRef)` (kind, label, status, summary), `ToolNames(entry)`, `ToolResults(entry)`;
  - `OcuTalon.Test.Contract.Mock`: `LogMark()` and `LogSince(mark, .entries)`, used as `Test/Tools/RecentActivityTurn.cls:89-111` does.
  - Column and parameter names come from the class files: `Data/Turn.cls` (`ClientId`, `TurnDecisionRef`, `SessionRef`, `State`, `ReplyText`), `Tools/RecentActivity.cls:32` `NONE`, `Checks/ReplyGuard.cls:19,22` `RESERVED` and `BANNED`, and `Tools/WatchTools.cls:48,52` the step labels.

**Shared surfaces to keep green** (read; no edit planned):
- `chat/chat.spec.ts` C1, `demo-path/01-page.spec.ts:64-75`, `guide/guide.spec.ts:182-188`, `demo-switch/badge.spec.ts:53-59` and `view.spec.ts:186`: they read `app-empty-chat .line`.
- `floor/layout.spec.ts:505-563`: G4 and G5 in the empty chat.
- `floor/guide.spec.ts` M9-M14: the finish's parts and Run again focus.
- Floor keyboard, scan and words; `web/e2e-online/allowance/messages.spec.ts` (read only).

**UX** (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`):
- `EXPERIENCE.md`: `:222-236` "Demo guide and controls", `:273-278` Chat › Empty chat panel, `:604-610` the finish-state list (More to try at `:609`);
- `DESIGN.md`: `:728` (actionable chips), `:805` (Empty chat panel) and `:847` (Sample email chip).

## Tasks & Acceptance

**Execution** (in dependency order):
- [ ] **Task 0 (measure, on the first fresh sign-in run of the new file; inference until then).** Record:
  - (a) that the RAIL session's chat is empty when the file starts, with no turn, no watch and no incident;
  - (b) that each chip's turn ends `done`, with the scenario's reply and no fallback reply (the triage decision is a fallback, as for the guide prompts);
  - (c) chip 3's tool result.

  If (b) fails for the `[toolUse, text]` shape, HALT with a clarification naming the observed requests (the mock log). Never change the mock's code or tests, and never switch to 5.13's triage-first shape without a ruling.
- [ ] `ci/mock/scenarios/B/try-it-*.json` (4 new): as in Always; `name` equals the file name.
- [ ] `web/src/app/chat/try-it-view.ts` (new): `TRY_IT_TEXTS` and `turnInFlight`. Rule 14: the comments state the contract.
- [ ] `web/src/app/chat/composer.ts`: export `COMPOSER_REASON_ID` and use it.
- [ ] `web/src/app/chat/try-it-row.ts` (new): the group, label and buttons. It renders only `@if (demoView.on())`. Computeds: `inFlight`, `used` (`allowance.active() !== undefined`), `blocked` and `describedBy` (`COMPOSER_REASON_ID` only while used up). `press(text)` as in Always. Styles as in Always.
- [ ] `web/src/app/chat/empty-chat.ts` and `web/src/app/guide/demo-guide.ts`: the placements and `FINISH_PARTS`, as in the Code Map.
- [ ] `web/scripts/try-it-view.test.mjs` (new, `node --test`). It imports `try-it-view.ts` and `guide/guide-view.ts`, and reads the four B files and `ReplyGuard.cls`:
  - (a) `TRY_IT_TEXTS` equals the five strings, prompts in order. No prompt is a guide prompt (`GUIDE_TEXTS.promptWatch`, `promptReminder`).
  - (b) Each prompt is the `match.prompt` of exactly its named B file. Each file's tool calls are as in Always (chip 3: `recent_activity` with `{}`), its last reply is text, and no reply text holds a `RESERVED` or `BANNED` phrase, ignoring case.
  - (c) `turnInFlight`: false for empty lists, for a `failed` entry only, and for `done` turns only; true for a `sending` or `sent` entry, and for a `queued` or `running` turn.
- [ ] `web/scripts/try-it-sources.test.mjs` (new; the shape of `demo-view-sources.test.mjs`, on `source-files.mjs` `sourceFiles` and `code`):
  - (a) `try-it-row.ts` reads `demoView.on()`, never `demoMode`. Its one `outbox.send(` call has one argument (no `fromGuide`, no `true`). It has no `Announcer`, no `.focus(`, no `ApiClient`/`HttpClient`, no `(keydown`, and every `<button` has `type="button"`.
  - (b) `empty-chat.ts`'s template has `<app-try-it-row` after its last `class="line"`. `demo-guide.ts`'s has it after `class="more"` and before `run-again`, with `data-guide-focus="tryIt"`, and `FINISH_PARTS` lists `'tryIt'`.
- [ ] `web/scripts/ux-strings.test.mjs` (add lines only):
  - in `IMPORTED`, `['chat/try-it-view.ts', ['TRY_IT_TEXTS']]`;
  - in `SOURCES.ux`, after `'Run again'`, the five strings.
- [ ] `web/e2e/chat/try-it.spec.ts` (new). Project chromium, unit `live:sign-in`, user RAIL. `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`.
  - **Hooks:** the hooks of `reminder/chat.spec.ts`, copied (Decided 10). `beforeEach` and `afterEach` both remove the RAIL session's turns, and `afterEach` asserts 0 turns.
  - **Precondition of every pressing case,** through `irisScript`: the RAIL session has no turn, no watch and no incident. Otherwise it fails, naming what it found.
  - **Y1** (routed, `changeSnapshot` chat `[]` and a finished guide; matrix 1, 2, 3):
    - two groups "Try it yourself", with distinct label ids;
    - the empty chat's follows its last `.line` and the finish's follows `.more` and precedes Run again (compared with `compareDocumentPosition`);
    - each holds the four buttons in order (`getByRole('button', { name, exact: true })`, `type="button"`, no `aria-disabled`).
    - Then a new page with `addInitScript` sessionStorage `ocutalon.demoView.off`=`1`: no group. Then `changeSnapshot` `demoMode` false: no group. No `POST /messages` at any point.
  - **Y2** (routed allowance and chat `[]`; matrix 8): each chip has `aria-disabled="true"`, and its `aria-describedby` is `composer-allowance-reason`, whose text equals `app-composer .reason`. A click and an Enter on chip 1 post nothing.
  - **Y3** (chip 1, a click in the real empty chat; matrix 4):
    - exactly one POST, `{text: 'Which productions are running?', fromGuide: false}`;
    - `main.main` is focused;
    - the user message shows the exact text and no "From the demo guide";
    - `replyOf(page, clientId)` contains "The CI mock listed the productions." within 30 s;
    - its `app-decision-strip` has an `app-outcome-chip`, and `.line1 .meta > :last-child` is `APP-TRACE-LINK` with an `a[href]` to the trace page;
    - `StepsOf` on the Turn's `TurnDecisionRef` gives exactly one tool step, "Listing the productions|ok".
  - **Y4** (chip 2, Space on the chip after a Tab from the chat list; matrix 4, 5):
    - one POST with the exact text;
    - the reply's `app-check-rows .sentence` is the nothing-watched sentence;
    - its text holds no `RESERVED` or `BANNED` phrase (read through `irisScript` `$Parameter`);
    - one tool step, "Reading the check results|ok".
  - **Y5** (chip 3 from a routed finished guide, with the page's real chat empty; matrix 4, 7):
    - Before load: `page.clock.install()`, and the page's polls drop `guide.state` events, so that the routed finish stands.
    - Click the finish's chip 3: one POST. Then `holdPoll`: every chip in the finish is `aria-disabled="true"` with no `aria-describedby`.
    - Enter on the focused chip: still one POST, and focus still on it.
    - `release()`: the reply lands, and the chips lose `aria-disabled`.
    - One tool step, "Reading recent activity|ok".
  - **Y6** (chip 4 by keyboard; matrix 4): focus the chat list, Tab to chip 4 (chip 1 comes first after the list), Enter.
    - One POST "What can you do?";
    - the reply contains "The CI mock answered what OcuTalon can do.", with a strip and a trace link;
    - no tool step.
  - **Y7** (chip 3 in the real empty chat, a session with no incident; matrix 6):
    - `LogMark` before the click;
    - after the reply, the Chat requests since the mark that offer `recent_activity` number 2, and the second carries one tool result;
    - parsed, it has `ok` true, `hours` 24, an empty `incidents` and `message` equal to `$Parameter("OcuTalon.Tools.RecentActivity","NONE")`;
    - the reply text holds no `RESERVED` or `BANNED` phrase.
- [ ] Search `web/e2e/**`, `web/scripts/**` and, read only, `web/e2e-online/**`, for pins of the empty chat's content, the finish's content, Tab sequences through main, and button counts in main. Fix only in-footprint pins of the old shape. If an off-limits file needs a change, escalate.
- [ ] **`EXPERIENCE.md`.** Each change carries the marker `[ADDED 2026-11-01, Story 4.10, owner decision relayed by the Contest Planner under delegation; the owner: "Yes to both questions."]`:
  - **"Demo guide and controls":** a bullet, **Try it yourself.** In the demo view only.
    - A row labelled "Try it yourself" with the four chips, quoted verbatim in order, after the finish state's "More to try" line and after the empty chat panel's last line.
    - Native buttons named by their text, in the sample email chips' look.
    - A press sends the text once as the user's own message, exactly as if typed: no "From the demo guide" tag, the same decision strip, reply and trace link as any turn, and it counts against the message allowance. Nothing is sent without a press.
    - While a turn is in flight, or the message allowance is used up, the chips are `aria-disabled` and a press sends nothing. While the allowance is used up, they are described by the composer's reason.
  - **The finish-state list** (after "More to try"): "the Try it yourself row (Demo guide and controls)".
  - **"Empty chat panel"** (after its demo line): "in the demo view, then the Try it yourself row".
- [ ] **`DESIGN.md`**, with the same marker:
  - at `:728`, "currently, only the sample email chips" becomes "the sample email chips and the Try it yourself chips", with the old text quoted in an `[AMENDED ...]` marker;
  - a **Try it yourself row** bullet after Sample email chip (`:847`): the label in `{typography.body-sm}` and `{colors.ink-muted}`, then bordered actionable pills on `{components.sample-email-chip}` with no icon, wrapping; centred in the empty chat, start-aligned in the finish; no animation.

**Acceptance Criteria:**
- **AC1.** Given the demo view is on, when the guide's finish state shows or the chat is empty, then the "Try it yourself" row shows, with the four chips in order and verbatim: after "More to try" in the finish, and after the last line in the empty chat. Given the demo view is off, or the install is not in demo mode, then no chip shows.
- **AC2 (Integration).** Given a chip, when I press it in the empty chat or the finish state, then `ChatPanel`'s normal send (`ChatOutbox`) posts its exact text once, with `fromGuide` false. On the CI mock that produces a turn whose user message has no "From the demo guide" tag, and whose reply carries its decision strip and trace link, as any turn's does. Nothing is sent without a press.
- **AC3.** Given a turn is in flight, or the allowance is used up, when the chips render, then they are `aria-disabled` and a press sends nothing. With the allowance used up they are described by the existing allowance reason. They are native buttons, reachable by keyboard and named by their text.
- **AC4.** Given chip 2 in a session that watches nothing, when its turn replies, then the check sentence under the reply is the code-built one and the reply holds no all-clear wording (AD-28).
- **AC5.** Given chip 3 in a session with no incident, when its turn replies, then `recent_activity`'s code-built "nothing in the last 24 hours" answer is the tool result the model received, and the reply holds no all-clear wording.
- **AC6.** Given the CI mock, when it loads, then each chip's exact text has its own new `B/` prompt scenario. No existing scenario, `guide-*.json` included, is changed, and there is no new evaluation case.
- **AC7.** Given this story merges, when the UX documents are read, then EXPERIENCE.md's "Demo guide and controls" (with the finish state and the empty chat) and DESIGN.md carry the row with the 2026-11-01 marker, and `ux-strings.test.mjs` finds the five strings in EXPERIENCE.md.
- **AC8.** Given the change, when it merges, then it stays inside the footprint and adds no CI unit or e2e folder, and CI is green on every workflow.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, status final):
- **AD-28** (L915): chip 2's answer stays code-built. `check_status` puts results in `HostData`, `Conversation` renders the key and rows, and the guard strips model all-clears. No scenario text says all clear, and the e2e asserts the code-built sentence. The same rule backs chip 3's code-built answer.
- **AD-22** (L731): prompt scenarios live under `B/` and match when the message contains the exact text, with the reply rule `replies[min(k, last)]` for unarmed matches. These new files are Lane B's.
- **AD-12** (L381): the guide stays server-derived. Chips change no progress, and Y5 keeps its routed finish by dropping `guide.state` from its polls.
- **AD-20** (L631): the allowance is the server's. A chip's turn is an ordinary POST, so it counts.
- **AD-1** (L102), **AD-4** (L158): the message goes through `WebChatIn` like any typed one, and the body names no session.
- **AD-29** (L925), **AD-33** (L1025): lane B and home-lane files only.
- **Conventions:**
  - L1088, Announcements and focus: no new speaker or focus move;
  - L1111, Angular: standalone, signals, DESIGN tokens;
  - L1115, Tests.
- No AC contradicts an AD's Rule. No NFR trips Rule 5.

**Integration ACs (Rule 1):** matrix rows 4-7 (AC2, AC4, AC5) run the consumers on a real stack (`live:sign-in`) with the CI mock:
- `ChatPanel`'s empty chat (`EmptyChat`) and `DemoGuide`'s finish render `TryItRow`;
- a press goes through `ChatOutbox` to the real `WebChatIn`, `Conversation`, `Decide`, `Chat` and tools, and back over the real live stream.

**Consumed-by:** this story's two hosts, the empty chat and the finish state. No later story is planned to consume the row. A later demo-only prompt row reuses `TryItRow` and `TRY_IT_TEXTS`, and never copies them.

**Consumes:**
- Story 4.9: `DemoView.on()`, the switch's stored key;
- Story 4.7: the finish state, `.more` and `FINISH_PARTS`;
- Story 4.4: the empty chat's demo line;
- Story 2.5: `ChatOutbox`, the composer and the focus rule;
- Story 16.9: `AllowanceState` and the composer's reason;
- Story 5.13: `recent_activity`;
- Story 5.7: `check_status`, `Checks.Render` and `ReplyGuard`;
- Story 0.11: the mock;
- Story 8.6: the RAIL pointKeys pattern.

**Rule 2 (extend, don't copy):**
- `TryItRow.press` follows the guide's `send()` and the composer's `send()`. It differs only in passing no `fromGuide` and in using a broader in-flight guard.
- `turnInFlight` sits beside `isFreshChat`. `COMPOSER_REASON_ID` is exported, not repeated as a literal.
- `try-it-view.test.mjs` (b) extends `guide-view.test.mjs:210-218`'s "scenarios key the exact text" pattern. `try-it-sources.test.mjs` extends `demo-view-sources.test.mjs`.
- Two copies are justified:
  - (1) The six chip style declarations from `server-button.ts:62-73`. Component styles are scoped, `controls.css` (out of footprint) keeps no pill, and `ServerButton` doesn't fit (Decided 6).
  - (2) `reminder/chat.spec.ts`'s hooks. A spec file can't import another without running its tests, and `support/*` is off limits.

**Ledger (Rule 17):** the inbox is empty; this story owns no entry.

**Epic context:** the committed `epic-4-context.md` was reused as the dispatch directs. Its mtime is older than the UX files only because Stories 4.8 and 4.9 edited them.

**Decided in-stage** (unattended: small, reversible, within the intent):
1. **The scenario shape is `[toolUse, text]` (chip 4: `[text]`), not 5.13's `[tellnow, toolUse, text]`.**
   - Why: a prompt match has no countdown (`mock.mjs:33-36`; the countdown is keyed by a marker's label). So triage and Chat's first request both get `replies[0]`, and a triage-first file would make Chat reply with the triage JSON.
   - The guide prompts' proven shape gives a fallback triage decision, then the real tool call and the reply. Task 0 confirms it on the stack.
2. **Files and names.** The texts and the pure reader are in `chat/try-it-view.ts`; the component is `chat/try-it-row.ts` (`app-try-it-row`), because it sends through the chat. The scenarios are `B/try-it-*.json`.
3. **"Disabled" is `aria-disabled`,** as on the composer, the guide's Send, Break the feed and the mailbox chips. A pressed finish chip keeps its focus (a native `disabled` would drop it to the body), and a press does nothing.
4. **In flight** is as in Always. The composer itself stays usable during a turn (NFR-6); only the chips wait.
5. **The reason is the composer's existing paragraph,** reached by its exported id. The AC says "the existing allowance line says why", and a new line would be new public text.
6. **The look is the actionable chip on the sample-email-chip tokens, with no icon.** A new DESIGN token would need `web/src/styles/tokens.css`, which is out of footprint.
   - `ServerButton` (variant `chip`) is not used: its contract is a call with a busy state that ends on the call's answer. A chat send's state is the message's own (Sending, Not sent, Retry sending).
   - DESIGN.md's "currently, only the sample email chips" is amended, so the document stays true.
7. **The row gates itself on `DemoView.on()`,** so every placement is demo-view only by one rule. The guide's own gate makes the finish's check redundant, but harmless.
8. **A labelled group, not a heading:** the heading lists are pinned (`chat.spec` C1, `main` level-2 count). Label ids are per instance, because the routed Y1 shows both rows.
9. **Focus.** No new focus move. The empty chat's press falls to the panel's focus rule (main region), and Y3 pins it. The finish row is a finish part (`tryIt`), so Run again's focus rule treats it like the finish's links.
10. **The e2e home is `live:sign-in`, in `web/e2e/chat/try-it.spec.ts`, as the RAIL user.**
    - The chromium project already runs mock-pointed chat specs (`reminder/chat.spec.ts`), and RAIL's session is held empty by convention.
    - The `browser` group (about 26 min) has the most room among the groups that hold a chat-capable unit.
    - A new file in an existing folder needs no edit of `playwright-projects.test.mjs`.
11. **The canned mock texts are "The CI mock ..." sentences** that claim nothing about health, like the existing scenarios. They are CI-only, not public text.
12. **Y5's finish is routed,** because a real finished run is the demo path's and the floor's. The press, the turn and the reply are real. `holdPoll` makes the in-flight window deterministic.

**Veto items:** none.
- The five strings are the approved story block's.
- Nothing touches security, roles, stored data, a dependency, an AD or a PRD guarantee.

**Expected CI cost (inference):**
- `live:sign-in` gains 7 cases: about 70-120 s locally. That is the runners' restart twice, five mock turns of about 5-10 s each, and routed cases of about 3 s.
- On CI that is about 2-4 min on `browser`: about 26 to about 28-30 min. That stays under the 40-minute job limit, under REL-4's 35 minutes for the run, and under sign-in's 1200 s CI deadline (the whole unit is about 750-800 s on CI by the browser group's ratio, so about 900-1000 s after).
- If CI's `live:sign-in` passes 1000 s, the lead reports it to the orchestrator; it is not rebalanced here.

## Verification

`<B>` means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=<stage>'`, run from the worktree root.
- **Tags:** fresh `e4s10i`; QA `e4s10q`; review `e4s10r`. There is no warm stack: no server class changes, and a change under `ci/mock` refuses one anyway.
- **Slot B is not needed.** If an IRIS MCP call is ever made, use `server` `ocutalon-slot-b` and namespace `OCUTALON`, checked first with `iris_server_info`.
- **One command per foreground call** (`timeout: 600000`), and one `iris_execute_tests` per message.
- **Flakes** (one rerun): DW-349, DW-376, DW-396, DW-414, DW-333, DW-415, DW-462, DW-471, DW-497.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, `try-it-view`, `try-it-sources`, `ux-strings`, `guide-view`, `demo-view-sources`, `announce-focus-sources`, `floor-sources`, `shell-styles` and `playwright-projects` included.
- `npm --prefix web run lint` -- expected: exit 0.
- `bash docker/tests/test-mock.sh` -- expected: all the mock's node tests pass. The committed set loads with no problem, and no count pin moves.
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh build` -- run before any live unit, and again after any `web/` change.
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live sign-in --part 1/3` -- expected: PASS. Its PART line lists `chat/try-it.spec.ts` (path order puts `chat/` in part 1; inference until the line shows it). If it doesn't, run the part that does. About 6 min; record the time and Y1-Y7.
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live floor` -- expected: PASS in all three projects, covering G4 and G5 with the taller empty chat, the keyboard, the scan, the words, and M9-M14. About 6.5 min.

`(once)`:
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live sign-in --part 2/3`, then `--part 3/3` (one per call) -- expected: PASS. Together the three parts run every chromium file once; record the times.
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live demo-path` -- expected: PASS (UJ-1; step 1's empty chat with the row; the finish at step 6).
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live demo-switch` -- expected: PASS in both modes. The row shows only in the demo view and the structure cases are unchanged.
- `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh live online-allowance` -- expected: PASS (the online demo's allowance with the row present).
- `bash docker/tests/test-web-build.sh` -- expected: passes.
- `bash ci/checks.sh` -- expected: exit 0.
- `git diff --stat df9902bd629aed054c8900d5196b04c2242af6a9 -- ci/mock/scenarios ci/mock/*.mjs ci/mock/test` -- expected: only the four new `B/try-it-*.json` files.
- At the end, also after a failure: `<B> OCUTALON_RUN_TAG=e4s10i ci/iris.sh teardown`.

**Planned mutations (Rule 19).** Apply each one, rebuild where `web/` changed, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Record each as `mutation: … → …`.
- **AC1:**
  - `try-it-row.ts` renders `@if (true)` instead of `demoView.on()` → Y1 (a group with the switch off) and `try-it-sources` (a);
  - swap two prompts in `TRY_IT_TEXTS` → `try-it-view` (a) and Y1.
- **AC2:** `outbox.send(text, true)` → Y3 (`fromGuide` true, the "From the demo guide" caption) and `try-it-sources` (a).
- **AC3:**
  - `turnInFlight` always false → Y5 (no `aria-disabled` while held; a second POST) and `try-it-view` (c);
  - the allowance guard removed → Y2 (a POST).
- **AC4:** `try-it-anything-wrong.json` drops its `toolUse` reply (text only) → Y4 (no check sentence).
- **AC5:** `try-it-failure-earlier.json` calls `check_status` instead of `recent_activity` → Y7 (no recent_activity request) and `try-it-view` (b).
- **AC6:** one word of a prompt changed in `TRY_IT_TEXTS` only → `try-it-view` (b) "keys the exact text".
- **AC7:** one word of a chip text changed in EXPERIENCE.md → `ux-strings` "finds each ux and design string in its document".

**Shared surfaces:**
- the empty chat's content (`app-empty-chat .line` readers: chat C1, demo-path 01, guide Q, demo-switch badge and view);
- the finish's content and focus parts (floor guide M9-M14; `FINISH_PARTS`);
- the empty chat's height (floor G4 and G5);
- the Tab stops and buttons in main (floor keyboard and scan);
- the UX string inventory (`ux-strings` `IMPORTED` and `SOURCES.ux`);
- the mock's scenario set and index (`ci/mock/test/*`, which count from the folder, so no pin);
- the guide's mock-scenario pins (`guide-view.test.mjs:210-218`, unchanged);
- the Playwright project lists (`playwright-projects.test.mjs`: chromium is not pinned by file, so no edit);
- the demo-view source rules (`demo-view-sources.test.mjs`, which `demoView.on()` satisfies, unchanged);
- the RAIL session (held empty: every case removes its turns, and afterAll drops the AI sessions);
- the runners' keys (pointed for the file, restored with `WaitRecords` before `trace/links.spec.ts`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
