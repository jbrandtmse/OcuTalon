---
title: 'Story 25.2: Filter past decisions and incidents on the History page'
type: 'feature'
created: '2026-11-10'
status: 'done'
baseline_revision: '20b768a855ea6ff52ab4c808c9a69a0fa5f29599'
baseline_commit: '20b768a855ea6ff52ab4c808c9a69a0fa5f29599'
planned_against: 'Story 37.2 at OCT-epic37 7ef82a4671cb4ceec2a0ae2192e3d8f657488a1a (not merged)'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-25-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A user cannot look back at what OcuTalon decided on their messages or at the incidents it handled. The decisions (`OcuTalon.Bridge.Data.Decision`, Kind `decide`) and incidents (`OcuTalon.Data.Incident`, with Story 23.6's stored summary) exist, but no page or route reads them with filters or paging (FR-53, FR-30, step 6).

**Approach:** Add two owner-scoped reads, `GET /api/v1/history/decisions` (filters `outcome`, `channel`, `day`, `fallback`; `page`) and `GET /api/v1/history/incidents` (`page`), served by `OcuTalon.Web.History`, forwarded from `Web.Api`'s map the way Story 37.2 forwards `/v1/usage`. They read through new `Ownership.Rows` kinds. Add a History page (`#/history`), reached from a new History entry in the header navigation between Documents and Usage. It has two tabs, Decisions and Incidents, keeps its filters in the address and pages the lists. It reuses the rail's decision row, the incident state chip and headline, and the shared trace link. Add the story's own step-6 spine rows, a More to try item, a `Demo.Features` id and a README bullet.

## Boundaries & Constraints

**Always:**
- Every read goes through `OcuTalon.Data.Ownership` (AD-4, AD-13). The `SessionRef` comes from `Ownership.SessionRef(.sc)` and never from the request. Each kind's SQL is one constant text in `Statement`, with the owner check in `WHERE`. Optional filters are bound values in that constant text (`? = '' OR …`). Nothing is concatenated from a parameter.
- Decisions are the session's own rows of Kind `decide` (`OwnerRef = ?`). Incidents are exactly those the existing `INCIDENTVISIBLE` admits. Rows of owner `eval` or `instance` are never read as a session's decisions (`Rows` refuses those owners).
- The page never reads production messages (AD-27). Bridge tables and Lane A classes are read and never edited (AD-31, AD-33, U-177).
- Every trace URL comes from `OcuTalon.Web.TraceLink` (AD-26):
  - A decision's URL is built through `Live.Payload.Decision.FromRow` plus `TraceLink.Add`, as the rail builds it.
  - An incident's URL targets its `TraceHeaderId` (the diagnosis session) through `TraceLink.Url`.
- A day is an instance-zone local date through `OcuTalon.Data.Time` (`FromLocal`), as in Story 37.2 and the Notes route.
- Untrusted text (the item summary, reasons and summary lines) renders as text only (AD-13).
- Visible strings are exactly the ones in Design Notes → PUBLIC TEXT, as the Planner rules them.
- Contended files change only as Design Notes → CONTENDED FILES says.
- Lane B files only.

**Never:**
- No file-upload route, private file table or Roles rows. Those belong to 25.3, 25.4/25.5 and 37.1.
- No new role, grant, privilege, resource, stored table, column, index, live-event type or retention change. Never widen `OcuTalonUser`.
- No `%Prepare` outside `Ownership.Rows`, no embedded SQL and no `%ExecDirect`.
- No `SessionRef`, `OwnerRef`, user name or database row id accepted or returned.
- No infinite scroll. Tabs never switch by themselves. No new web dependency.
- No test deleted, skipped, tagged off or shortened.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Decisions, no filter | OcuTalonUser, `GET /api/v1/history/decisions` | 200 `{"page":1,"pages":P,"decisions":[…]}`. At most 25 per page, newest `RecordedAt` first, then newest ID. P = max(1, ceil(total/25)). Each item has only the keys `ref, outcome, reasons, fallback, fallbackReason, itemSummary, recordedAt, channel, traceUrl, confidence, costUSD`. The last two appear when set; `channel` is `""` when the decision has no usage row; `traceUrl` appears only when built | No error expected |
| Outcome filter | `outcome=ignore\|digest\|tellnow\|act` | `tellnow` matches `Outcome='tellnow'` or any fallback. The others match `Fallback=0 AND Outcome=?`. So the filter agrees with the chip (`outcomeOf`: a fallback shows Tell now) | — |
| Fallback filter | `fallback=yes\|no` | `yes` matches `Fallback=1`; `no` matches `Fallback=0` | — |
| Day filter | `day=YYYY-MM-DD` | Rows with `RecordedAt` in [FromLocal(day T00:00:00), FromLocal(next day T00:00:00)) | — |
| Channel filter | `channel=` a `Msg.Enum` CHANNEL value | Decisions with a usage row of the same owner whose `Channel` matches (the source of `Ownership.DecisionChannel`). A decision with no usage row (no model call) matches only when no channel filter is set | — |
| Filters combined, page 2 | e.g. `outcome=act&channel=mailbox&page=2` | Only rows matching every filter, rows 26 to 50 | — |
| Page past the end | `page` > P | 200 with an empty list and `pages:P`. The page then replaces its address with page P | — |
| Bad parameter | `outcome=foo`, `outcome=`, `channel=x`, `fallback=1`, `day=2026-13-01`, `day=11/10/2026`, `page=0`, `page=01`, `page=abc`, `page=10000`, `page=` | Nothing is read | 404 `not_found` with `MESSAGENOTFOUND` (the Notes and Usage precedent) |
| Unknown parameter | `foo=1` | Ignored | — |
| Incidents | `GET /api/v1/history/incidents[?page=n]` | 200 `{"page","pages","incidents":[…]}`. 25 per page, newest `NoticedAt` first, then newest ID. Each has only the keys `ref, state, fallback, count, itemNoun, firstAt, noticedAt, closedAt, summary, traceUrl`. `summary` is `Watch.Summary.Text(ref,"web")` as text, or `""` when none is stored. `closedAt` is `""` while open. `traceUrl` appears only when built | `page` as above; a summary that cannot be rendered gives `""`, never a 500 |
| Instance incidents | Local install; an `instance` incident of a production the session's production check watches | Listed (`INCIDENTVISIBLE`). On the online demo (`LocalFlag` 0) it is never listed | — |
| Isolation | Rows of session B, `eval`, `instance` decisions, rows with no owner, un-noticed incidents | Never in A's lists or totals; the same for B | — |
| Signed out / no role | No CSP session / no OcuTalonUser | — | 401 `signed_out` / 403 `no_role` |
| Failed read | `SessionRef` or `Rows` error | — | 500 `server_error`; the page shows "Couldn't load your history." and Retry |
| Empty | No rows; or rows, but none match | "No decisions yet." / "No decisions match these filters." (any filter set) / "No incidents yet." | — |

</intent-contract>

## Code Map

Line numbers are on this branch (`ddedbd6a`), unless marked "37.2" (OCT-epic37 `7ef82a46`).

**Backend (Lane B; edit):**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`. Edit these:
  - `Rows` :949 (the one allow-listed unchecked prepare; `class=""` returns `{"total"}`).
  - `Statement` :1001: the kinds to model on are `decisions` :1036, `noteDecisions` :1193, `incidents`/`recentIncidents` :1064-1070 and `memoryTotal` :1184.
  - `INCIDENTVISIBLE` :73 (binds `o a o`); `LocalFlag` :936.
  - `DecisionChannel` :807 (the channel rule this story's SQL mirrors).
  - `Decisions` :387 and `RecentIncidents` :401 (siblings).
  - 37.2 adds `Usage` :190-247 (a range through `Data.Time`) and kind `usage` :1128.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - UrlMap :216-256; Documents map :255 (37.2 adds `/v1/usage` at :258).
  - Header doc bullets :76, :87-88 (37.2).
  - `Fail` :1339, `MESSAGENOTFOUND` :149, `ServerError` :330, `PayloadObject` :1265, `RailBody` :1246 (the rail's decision payloads), `Notes` :1776 (the bad-`day` 404 precedent).
- 37.2 `src/ocutalon/cls/OcuTalon/Web/Usage.cls`: the model for `Web/History.cls`. It is `Extends OcuTalon.Web.Api`, has its own UrlMap, and its `Read` :25-36 validates its parameter, reads through Ownership, then writes.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls` `FromRow` :78 (read only; the DW-129 trace target). `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls`: `Viewer` :33, `Url` :41, `Add` :60.
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls`: `Ids` :40-49. 37.2 appends `usage` last at :49 with the doc line :11.

**Read only (Lane A; never edit):**
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`: Outcome, Reasons, Fallback, FallbackReason, TraceSessionId, RecordedAt, OwnerRef. There is no Channel column.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`: Channel :28, DecisionRef.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls`: OUTCOME :6.
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls`: CHANNEL is Enum :24 (`web,phone,mailbox,telegram,email,webhook,slack,system,heartbeat`).
- `src/ocutalon/cls/OcuTalon/Data/Incident.cls`: State :21, NoticedAt :27, Count :30, FirstAt :36, ItemNoun :42, Fallback :57, TraceHeaderId :66, ClosedAt :69, Summary :94.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls` `Text(ref, channel, .sc)` :122. It does no ownership check, so call it only on rows read through Ownership. Story 23.6 is merged (sprint-status :331 `done`; `b896ef39`).

**Web (Lane B; edit):**
- `web/src/app/header/header-nav.ts` :20-26. 37.2 adds Usage :21-26, `flex-wrap` :35 and doc :7-14.
- `web/src/app/settings/settings-view.ts` `pageOf` :138-146 (37.2 adds `'usage'`).
- `web/src/app/app.config.ts` :22-26 (eager routes; 37.2 `usage` :25).
- `web/src/app/api/api-client.ts`: `BASE` :34; 37.2 `usage()` :178-181. 37.2 adds `web/src/app/api/usage-types.ts`.
- `web/src/app/rail/rail-view.ts`: `decisionRow` :269 is private, so export it; `RailRow` :105.
- `web/src/app/rail/status-rail.ts`: `formatAt` :51 is private, so export it.
- `web/src/app/rail/decision-row.ts` `DecisionRow`: the disclosure with the sibling trace link.
- `web/src/app/incidents/incident-view.ts`:
  - `INCIDENT_TEXTS` :34; `stateText` :190.
  - Export `stateOf` :185 and `headlineOf` :218. `headlineOf` reads only `ctx.messageTime` and `ctx.nowMs`.
- `web/src/app/incidents/incident-card.ts`: the inline state chip :69-71 and its CSS `.chip*` :208-237. Extract these.
- `web/src/app/shared/trace-link.ts` `TraceLink` :94-223 (sign-in help variant, new-tab text); `shared/trace-help.ts`.
- `web/src/app/chat/outcome-chip.ts`, `chat/fallback-flag.ts`, `chat/decision-view.ts` `outcomeOf` :170, `chat/page-time.ts` `pageWhen` :183.
- `web/src/app/rail/memory-card/memory-card-view.ts` `nextTab` :76 (arrow-key tabs). Its siblings are `memory-card.ts:50-64` and `devices/device-panel.ts:60-79`.
- `web/src/app/documents/documents-page.ts`: the header-reached page model. It reads query params with `toSignal(route.queryParamMap)` :212 and writes them with `router.navigate([], {queryParams, queryParamsHandling:'merge', replaceUrl})` :307. Its pure view is `documents-view.ts`.
- 37.2 `web/src/app/usage/usage-page.ts` and `usage-view.ts`:
  - The page/view split, the `failed` and Retry pattern :450-469, and no loading text.
  - `USAGE_TEXTS.channels` :35-44 (ruled channel labels; import them, never copy).
- `web/src/app/guide/more-to-try-view.ts`:
  - Texts :23-84; `MoreToTryAction` :98; registry :112-122; groups :133; header comment :3 ("its nine items").
  - 37.2 adds the `usage` item last :110 and `'usage'` :87.
- `web/src/app/guide/more-to-try.ts`: 37.2's `@else if (item.action === 'usage')` link :74-75 and `case 'usage'` :248.
- `web/src/styles/base.css` `.visually-hidden` :130; `styles/tokens.css` `--space-10` (40px) :112.

**Tests and config:**
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `Session` :22, `Check` :70, `Incident` :87 (its default OpenVariant `fix` is not in the enum; set fields explicitly), `Decision` :141, `Usage` :160, `Clean` :369.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` `TestIsolationEveryRowKind` :481 (a hand list of kinds).
- 37.2 `Test/Data/OwnershipUsage.cls` (extends `OcuTalon.Test.Bridge.ZoneCase`) and `Test/Web/UsageApi.cls`: the sibling tests. They use stand-in requests through `Test.Web.Api.Written`, with `BUCKETKEYS`.
- `Test/Web/DocumentsApi.cls` :96-101 (37.2 filters its Map count by URL); `Test/Web/Api.cls` `TestRoutes` :958 (36 Routes; Maps are not counted).
- 37.2 `web/e2e/api/usage.spec.ts`: the real-HTTP model. It uses `signInOverHttp`, `fixtureUser('LIVE'|'PANEL')`, `OCUTALON_TRACEONLY_USER` for 403, `sessionRefOfUser`, and seeding through `irisScript`.
- `web/e2e/support/iris.ts`: `fixtureUser` :71, `irisScript` :105, `seedDecision(s)` :531/:558, `seedIncident` :1018, `cleanFixtureRows` :693. `web/e2e/support/trace.ts`: `stubTraces`, `helpSeen`.
- Shared specs:
  - `web/e2e/frame/frame.spec.ts`: Tab order F3/F7, and 37.2's "F3: at 1024px the header holds the four navigation links on one line".
  - `web/e2e/settings/settings.spec.ts` :68 and `web/e2e/documents/documents.spec.ts` :338: the nav lists.
  - `web/e2e/guide/more-to-try.spec.ts`: `ITEMS`, `controlOf`, K3 and 37.2's K3b. The last number is K27 (:1550), so the next is K28.
- `web/scripts/`:
  - `ux-strings.test.mjs`: `IMPORTED` :42-74 and `SOURCES` :174.
  - `floor-sources.test.mjs`: `KEY_HANDLERS` :103-115, the arrow list :147, bindings :156, `FIXED_HEIGHTS` :220, scrollers :304 and the `tabs` allowed map :373-376.
  - `settings-view.test.mjs` :88-102; `more-to-try-view.test.mjs` (`RULED`, `ACTION_OF` :97, `GROUP_OF` :99-109); `more-to-try-sources.test.mjs` (`<a` :48, `moreItem` :75).
  - `sources-docs.test.mjs` :43-56 (count words from the registry length) and :99-140 (EXPERIENCE's numbering by panel order).
  - `api-client-sources.test.mjs` :98-105.
- `docker/tests/test-class-rules.sh` `ALLOW_UNCHECKED` :51-53 is unchanged. `ci/units.sh` :18-24: Test.Data and Test.Web join `lane-b` with no edit. The new `web/e2e/history/` joins chromium (`live:sign-in`) with no edit (`web/playwright.config.ts` :52,61-62).

**Planning (edit; this story's rows only):**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
  - `### Ownership tables` cross-area table: on this branch it ends before 37.2's rows. 37.2 :1429-1430.
  - `### REST surface (release 1)` :1553-1596: 37.2's last row is :1591.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: More to try :242-262 (37.2 adds Item 9 :254). History is at :59, :77, :358, :399 and :1062. The UX text is unchanged except the More to try entry.
- `README.md` "New since 1.0.0" :42-53, and the count :40.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (implement, before any edit): re-check this spec against Story 37.2 as merged on the feature branch: the header nav, the `Ownership.Rows` kinds, the REST and ownership spine rows, the More to try registry, `Demo/Features`, README and EXPERIENCE. Record any drift in the Spec Change Log. Also re-read `sprint-status.yaml` for 37-2 `done` and run `git log --oneline --grep "37.2"` on the base.
- [x] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the kinds `historyDecisions`, `historyDecisionTotal`, `historyIncidents` and `historyIncidentTotal` to `Statement`, appended after 37.2's `usage` block. Add `HistoryDecisions(sessionRef, outcome, channel, day, fallback, page, Output pages, Output sc)` and `HistoryIncidents(sessionRef, page, Output pages, Output sc)`, documented in the class doc beside 37.2's `Usage` line.
  - The decision WHERE is: `d.OwnerRef = ? AND d.Kind = 'decide' AND (? = '' OR (d.Fallback = 1 AND ? = 'tellnow') OR (d.Fallback = 0 AND d.Outcome = ?)) AND (? = '' OR d.Fallback = ?) AND (? = '' OR (d.RecordedAt >= ? AND d.RecordedAt < ?)) AND (? = '' OR EXISTS (SELECT 1 FROM OcuTalon_Bridge_Data.Usage u WHERE u.OwnerRef = d.OwnerRef AND u.DecisionRef = d.Ref AND u.Channel = ?))`.
  - The page form adds `ORDER BY d.RecordedAt DESC, d.ID DESC LIMIT ? OFFSET ?`.
  - Incidents use `INCIDENTVISIBLE` with `ORDER BY i.NoticedAt DESC, i.ID DESC LIMIT ? OFFSET ?`.
  - The page size is the class parameter `HISTORYPAGE = 25`.
  - `day` becomes a window through `Data.Time.FromLocal`. An unreadable `day` is an error status (the route validates first).
  -- Rationale: the one read path (AD-4, AD-13), the existing allow-listed prepare, the same shape as 37.2's `Usage`. `LIMIT ? OFFSET ?` with binds was measured to work on build 154 (Design Notes).
- [x] `src/ocutalon/cls/OcuTalon/Web/History.cls` (new) -- `Extends OcuTalon.Web.Api`. Its UrlMap has `GET /decisions` → `Decisions` and `GET /incidents` → `Incidents`. It validates exactly per the I/O matrix and answers a bad value with `..Fail(404,"not_found",..#MESSAGENOTFOUND)`. It reads through Ownership with `SessionRef(.sc)` and writes the allow-listed keys only.
  - Decisions: `Live.Payload.Decision.FromRow` → `PayloadObject` → `TraceLink.Viewer`/`Add`, then a copy of only the allow-listed keys, plus `channel` from `Ownership.DecisionChannel`.
  - Incidents: built directly from the row. `itemNoun` has the same shape as `Live.Payload.Part.ItemNoun`. `traceUrl` is `TraceLink.Url(TraceHeaderId, $Namespace, , , .viewer)`. `summary` is `Watch.Summary.Text(ref, "web", .sc)` when `Summary '= ""`, and a failed render gives `""`.
  -- Rationale: the 37.2 forwarding pattern; one trace builder (AD-26).
- [x] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- add `<Map Prefix="/v1/history" Forward="OcuTalon.Web.History"/>` after 37.2's `/v1/usage` map, and append one header doc bullet after 37.2's usage bullet.
- [x] `web/src/app/api/history-types.ts` (new) and `web/src/app/api/api-client.ts` -- add `historyDecisions(filters: HistoryFilters & {page})` and `historyIncidents(page)`. They send only the set parameters, and their result types are `HistoryDecisionsResponse` and `HistoryIncidentsResponse`. Append them after 37.2's `usage()`.
- [x] `web/src/app/history/history-view.ts` (new, pure, erasable TS, type-only imports plus the imported `*_TEXTS`, the way 37.2's `usage-view.ts` imports shared labels) -- holds:
  - `HISTORY_TEXTS`.
  - `paramsOf(queryParamMap-like)` → `{tab, outcome, channel, day, fallback, page}`, which drops invalid values.
  - `queryOf(state)`, which writes only the set values (`tab` only for `incidents`, `page` only when above 1).
  - `OUTCOMES`, `CHANNELS` (the Msg.Enum order, with `USAGE_TEXTS.channels` labels), `FALLBACKS`.
  - `emptyText(state)`, `pageText(page, pages)`, `incidentTimes(row, when)` and `summaryLines(text)`.
- [x] `web/src/app/history/history-page.ts` (new) -- `HistoryPage`, OnPush, mirroring 37.2's `UsagePage` for load, `asked` and `failed`/Retry, with no loading text. Its structure:
  - `<main class="history" tabindex="-1">`, a hidden `<h1>` "History", and a `role="tablist"` labelled by the h1. It has two `role="tab"` buttons (`aria-selected`, `aria-controls`, roving tabindex, Arrow keys through `nextTab`) and two `role="tabpanel"`, each with a hidden `h2`.
  - Decisions panel: native `<select>`s Outcome, Channel and Fallback, a native `<input type="date">` Date, each with `<label for>`, and "Clear filters" when any filter is set. Then a `<ul>` of `<app-decision-row>` fed by the exported `decisionRow(payload, formatAt(now))`, with the channel label inserted as meta part 2 when set, tracked by `ref`. Each row has `min-height: var(--space-10)`.
  - Incidents panel: a `<ul>` of rows. Each row has the state chip and Fallback flag first, the headline (`headlineOf`), the "Noticed …" / "Closed …" times, the summary lines (or the no-summary text) and `<app-trace-link>` when `traceUrl` is set.
  - A pager `<nav aria-label>` with Previous page, "Page n of N" and Next page, never shown when there is a single page.
  - A filter, tab or page change navigates with `queryParams` (`replaceUrl:false` for user changes, so Back works; `true` when it corrects an invalid or past-the-end value). A filter change resets `page`, and a tab change drops the decision filters' `page`.
  -- Rationale: UX-DR127/129/130/147; extend, don't copy.
- [x] `web/src/app/incidents/incident-state-chip.ts` (new) and `web/src/app/incidents/incident-card.ts` -- extract the inline chip span and its `.chip*` CSS into `IncidentStateChip` (`[chip]`, `[text]`), rendering the same span and classes. The card uses it, and nothing else in the card changes. In `incident-view.ts`, export `stateOf` and `headlineOf` with no behaviour change. -- Rationale: Rule 2 (no copied chip CSS).
- [x] `web/src/app/rail/rail-view.ts` and `web/src/app/rail/status-rail.ts` -- export `decisionRow` and `formatAt` with no behaviour change.
- [x] `web/src/app/app.config.ts` and `web/src/app/settings/settings-view.ts` -- add the route `{ path: 'history', component: HistoryPage, title: HISTORY_TEXTS.title }` before 37.2's `usage` route, and give `pageOf` a `'history'` branch for `/history`.
- [x] `web/src/app/header/header-nav.ts` -- add the `History` link (`routerLink="/history"`, `aria-current` from `page.page() === 'history'`) between Documents and Usage (EXPERIENCE :77 order). Update 37.2's doc comment and `header.ts`'s "four navigation links" comment to five.
- [x] DW-1102 (routed to this story by 37.2's code review and merge gate; epics.md 25.2 `[ADDED 2026-11-10, DW-1102 …]` AC): `web/src/app/header/header.ts` -- in the stacked band (`@media ${LAYOUT_QUERIES.stacked}`) apply the measured spacing-only fit K (Design Notes → HEADER FIT): `.header` inline padding `var(--space-2)` (12 → 8px); the LEFT `.side` only (`.side:not(.right)`, or restore `.right`'s gap after it) `gap: var(--space-1)` (12 → 4px), `--header-nav-gap: 0px` (4 → 0) and `--header-nav-item-inline: var(--space-1)` (6 → 4px, the drawer band's own nav values); `.home` `gap: var(--space-2)` (mark to wordmark 12 → 8px). Nothing else in the header changes (no hidden link, no label, font, group or behaviour change: any such change is a PLANNER REPORT first). Update the header comment (:90-96) and `header-nav.ts`'s comment to the new values and the four-link floor user. Acceptance: at 640x360@2 the floor user's header (Chat, Documents, History, Usage) is 77px and sticky, writes 77px, no sideways scroll; `live:floor` G4 and G5 green in Chromium, Firefox and WebKit. -- Rationale: 37.2 left about 19px; History needs about 65px; K was measured to leave about 18px.
- [x] `web/src/app/guide/more-to-try-view.ts` and `more-to-try.ts` -- add `MORE_TO_TRY_TEXTS.items.history` (PUBLIC TEXT), the action `'history'`, and the registry entry `{ id: 'history', …, action: 'history', group: 'Usage and history' }` appended last (the Planner's ruling: the fourth heading that 37.2 adds, usage then history). Extend 37.2's usage link branch so it serves both page links (one `<a>`, path from the action) and add `case 'history'` to the navigate switch. The header comment's count word follows the registry.
- [x] `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Ids` appends `history` unconditionally after `usage`. Update the doc line so it no longer says "usage … last".
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipHistory.cls` (new; extends `OcuTalon.Test.Bridge.ZoneCase` like 37.2's `OwnershipUsage`) -- tests every I/O matrix row at the Ownership level:
  - each filter, alone and combined;
  - outcome `tellnow` with a fallback row whose stored Outcome is not `tellnow`;
  - channel through the usage rows, and a row with no usage row;
  - the day edges in two zones;
  - paging (26 rows → page 2 holds 1; `pages` 2; past the end empty);
  - order;
  - isolation (B, eval, instance, no owner, un-noticed incident; an instance incident visible locally only through a watching `Check`, and invisible with `onlineDemo` 1);
  - the refusals.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- add the four kinds to `TestIsolationEveryRowKind`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/HistoryApi.cls` (new; mirrors 37.2's `UsageApi`) -- covers:
  - Dispatch: exactly one Map for `/v1/history`; `/v1/historyx` is no route; History's routes are `GET /decisions` and `GET /incidents`; POST is no route; 403 `no_role` without the role.
  - Every bad value in the matrix → 404 with the exact body.
  - Shape: the exact top keys, and every item's keys within the allow-list (`DECISIONKEYS`, `INCIDENTKEYS`). The body holds no `SessionRef`, `$Username`, fixture tag, `"id"`, `ownerRef`, `itemId`, `traceHeaderId` or `kind`.
  - Isolation, the summary text, and no session → 500.
- [x] `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls` -- add `,history` after `usage` in every `TestIds` expectation. `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- no edit when, as at 37.2, its Map pin filters on `/v1/documents`; otherwise apply 37.2's URL filter.
- [x] `web/e2e/api/history.spec.ts` (new; real HTTP, mirrors 37.2's `api/usage.spec.ts`) -- the SECURITY tests listed in Design Notes. Seed through `irisScript` with `Test.Data.Fixture` `Decision`, `Usage` and `Incident` (with a stored `Summary`) and clean up in `finally`. Extend `support/iris.ts`'s `seedDecision(s)`/`seedIncident` where they fit, and otherwise add `web/e2e/support/history.ts`.
- [x] `web/e2e/history/history.spec.ts` (new) -- covers (also: a decision with no usage row shows no channel text at all, no "Unknown" and no labelled dash, the Planner's condition):
  - the page from the header nav: title, `aria-current`;
  - the tabs: `aria-selected`, ArrowRight/ArrowLeft, Enter/Space, never switching by themselves;
  - every filter changes the address, and a reload and a copied link keep it;
  - the empty texts;
  - paging (26 decisions);
  - a row's disclosure expands its reasons in place (`aria-expanded`, no dialog), and the trace link is a sibling of the button. It has `target="_blank"` and its name includes "(opens in a new tab)". On a local install before the help is seen it is "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"` (`stubTraces`, `helpSeen`);
  - the Incidents tab's chips, headline, times, summary and trace link;
  - rows at least 40px tall (boundingBox);
  - a second session's fixture rows never appear (a PANEL session seeded at the same time);
  - keyboard only.
- [x] Shared tests (Rule 19) -- update these:
  - `frame.spec.ts`: the Tab order gains History before Usage, and 37.2's 1024px test (F3) becomes five links (its title and its `toHaveText` list gain History; measured: it fits unchanged, 56px, one line). `web/e2e/floor/layout.spec.ts` G4/G5 are NOT edited: they must pass unchanged with the History link and the fit K (DW-1102).
  - `settings.spec.ts:68` → `['Chat','Settings','Documents','History','Usage']`; `documents.spec.ts:338` → `['Chat','Documents','History','Usage']`.
  - `more-to-try.spec.ts`: `ITEMS`, `controlOf`, K3's href for the history item, the group-heading oracle (K27) gains history under "Usage and history", and the new **K28** "the link of the History item opens the History page". K16 and K17 (the compact band at 1280x650 and 1280x600) must stay green unchanged (the Planner's condition).
  - `settings-view.test.mjs`: `pageOf` `history` cases, the same set as 37.2's usage cases.
  - `more-to-try-view.test.mjs`: `RULED`, `GROUP_OF` gets `history: 'Usage and history'`, and an assertion that history is last in that group and in the registry.
  - `more-to-try-sources.test.mjs`: the counts follow the extended link branch.
  - `ux-strings.test.mjs`: `IMPORTED` gets `['history/history-view.ts', ['HISTORY_TEXTS']]`, the `ux`/`ac` sources, and a `ruled` block "Story 25.2 rulings at the spec gate" (2026-11-10, Contest Planner: PUBLIC TEXT approved as proposed).
  - `floor-sources.test.mjs`: the history page in `KEY_HANDLERS`, the arrow list and bindings, the `tabs` allowed map (reason: UX-DR130 Decisions/Incidents tabs), and the scroller list only if it adds a scroller.
  - `web/scripts/history-view.test.mjs` (new): `paramsOf`/`queryOf` round trips, invalid values dropped, `emptyText`, `pageText`.
- [x] `README.md` -- append the History bullet last in "New since 1.0.0" and update :40's count word. `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- add the More to try entry under 37.2's "Usage and history" heading, after usage, with the next item number, plus "Item N's control is a link to the History page.", and update the "There are … items" count word. Both carry `[ADDED <date>, Story 25.2, Contest Planner ruling …]`.
- [x] `ARCHITECTURE-SPINE.md` -- append the three rows in Design Notes → SPINE ROWS after 37.2's rows. Refresh `updated:`, run `memlog.py append --type decision` and lint (Rule 20).

- [x] [CI] iris (shards-10) live:sign-in, ci run 42966931010 job 130346188773 on 284e8904: `web/e2e/usage/usage.spec.ts:328` U8 failed at :339 "at 305px the header navigation still holds every link" (expected `['Chat','Documents','Usage']`; the History link is now in the nav) -- a shared-surface pin (Rule 19) of 37.2 that this story's History link changes. Fix: update the pin at :339, and ALSO U1 at `usage.spec.ts:197` ("…and no Settings or History", same literal list: History now shows, so its message and list change), preferably by reading the expected list from one shared source instead of a literal (e.g. a small exported list in `web/e2e/support/` that the nav specs share, or deriving it from the nav source as the other nav specs do); grep every spec that pins the header link list (`git grep -n "'Chat', *'" web/e2e`: frame, documents, settings, history, usage, floor) and make each consistent. The U8 305px case must still hold with four links (every link visible and inside the window); if the 305px window cannot hold History without hiding or overflowing, STOP with a clarification (never hide a link; never change the header beyond the ruled fit K). Verify on a lane-C fresh stack: the part holding `usage/usage.spec.ts` and the part holding `history/history.spec.ts` (`live sign-in --part k/20`, via `e2e-part.mjs`), `live sign-in-3 --part 1/2` (more-to-try), node (`npm --prefix web test`). Write the mutation line (Rule 19) for the changed pin.

- [x] [CI] iris (shards-10) live:sign-in, ci run 42981966109 on f21137d1: `web/e2e/history/history.spec.ts:419` H12 failed at :466 -- after Retry the 25 incidents loaded (:465 passed) but `page.getByText("Couldn't load your history.")` still counted 1. Lead's reading (verify, do not assume): `refused()` sets `failed` and calls `announcer.announce(HISTORY_TEXTS.error)`; the shared `Announcer` queues messages (AnnounceQueue with setTimeout) and speaks through the CDK LiveAnnouncer, whose hidden live-region element keeps the text. So a page-wide `getByText` can match the live region after the visible error is gone, and an announcement queued before the Retry may even be spoken after the retry succeeded (a stale error announced to a screen-reader user). Fix so that a successful Retry clears the error everywhere it shows, on BOTH tabs: (a) the visible failed region must be gone (it is, via `arrived()` -> `failed.set(false)`; pin it scoped to `[data-part="history-failed"]`), and (b) a queued-but-unspoken error must not be spoken after a later answer has arrived (cancel or supersede it through the existing Announcer API if it offers one, or by an equivalent small change in `history-page.ts` -- never edit the shared Announcer's behaviour for other pages without need; if the Announcer offers no way and a change there is needed, keep it additive). Update the assertions at history.spec.ts :375-379 (Decisions), :461-466 (Incidents) and :488 so they check the failed REGION (and, separately, that no stale announcement is made after the successful retry, if testable deterministically), never a page-wide text that the live region also holds. Run `history/history.spec.ts` (live sign-in --part 13/20) at least TWICE on fresh lane-C stacks to rule out a race, plus node tests; write the mutation line (Rule 19).

**Acceptance Criteria:**
- Given a signed-in user on any page, when they press History in the header navigation, then `#/history` opens titled "History · OcuTalon", with History marked `aria-current="page"` between Documents and Usage, and the tabs Decisions and Incidents are read from `/api/v1/history/*`, which read only OcuTalon's and the bridge's tables (Decision, Usage and Incident, plus Turn and BackgroundCheck through the reused `FromRow` and `INCIDENTVISIBLE`) through `Ownership`, never a production message. The spine's REST and ownership tables carry this story's three rows.
- Given the Decisions tab with fixture decisions across outcomes, channels, days and fallback, when the user sets any combination of the four filters, then only matching decisions show, newest first, 25 to a page with Previous/Next, each row at least 40px with the outcome chip first. The address holds the filters, so a reload or a pasted link shows the same list, and with no match the panel reads "No decisions match these filters.".
- Given a decision row, when the user presses its button, then the reasons expand in place (`aria-expanded="true"`, no dialog), and its trace link, a sibling of the button, opens the decision's trace target (the rail's, built by `TraceLink`) in a new tab and says so.
- Given the Incidents tab, when it loads, then each incident shows its state chip, headline, noticed (and closed) time, its stored 23.6 summary as text (or the no-summary text), and a trace link to its diagnosis session.
- Given two signed-in sessions with their own fixture decisions and incidents (plus eval and instance rows), when each reads either tab or route with any filters, then it sees only its own rows (and on a local install the instance incidents of productions it watches), never the other's. The tabs use `aria-selected` and work by keyboard alone.
- Given the History item in More to try, when the user presses its control "Open the History page", then the History page opens. `Demo.Features` lists `history` after `usage`.
- (DW-1102) Given the floor user (not an admin, demo mode) at 640x360 (200%), when the header shows Chat, Documents, History and Usage, then the header stays sticky (at most a quarter of the window), hides no link and needs no sideways scroll, with only the stacked band's spacing changed (fit K), and `live:floor` layout G4 and G5 pass unchanged.

### Review Findings

Code review 2026-11-11 (first review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, full-opus tier). 28 raw findings, 8 entries after grouping (high 0, medium 3, low 5), 15 rows rejected. Every patch is applied; nothing is left open in this story.

- [x] [Review][Patch] (medium; fix-risk low: a guard and a bound, pinned in the browser) The Date filter took days the server cannot read, and Chromium's date input reports a value for each digit of a typed year (measured: 0002, 0020, 0202, 2026), so typing a date added four history entries and three 404 reads, each announced as "Couldn't load your history.", and a pasted `day=1800-01-01` failed for good instead of being cleaned (blind+edge+auditor) [web/src/app/history/history-view.ts:89, web/src/app/history/history-page.ts:589] -- `isDay` takes no day before 1841 (IRIS dates start at 1840-12-31: `Data.Time.FromLocal` measured on slot C), and `pickDay` ignores a non-empty value `isDay` refuses. Pinned by `history.spec.ts` H13 and `history-view.test.mjs`.
- [x] [Review][Patch] (medium; fix-risk low: a stubbed test) The Incidents panel's own branches were never rendered in a browser: the Fallback flag, the "Incident pages" pager, the panel's failed read and Retry, and a closed incident's no-summary text (verification-gap) [web/src/app/history/history-page.ts:194] -- new `history.spec.ts` H12 (the incidents route stubbed in the browser).
- [x] [Review][Patch] (medium; fix-risk low: the sibling card's formatter, a shipped format) An incident row's Noticed and Closed times had no zone name beside its headline, which is in the instance zone, against EXPERIENCE Formats ("A page time that sits beside message text (in incident ... cards) adds the browser's zone abbreviation when it differs from the instance's") and the incident card's own top time (blind+edge) [web/src/app/history/history-page.ts:470] -- `pageWhenBeside(iso, now, zone)`, as the card; pinned by H14 (Europe/Berlin against the UTC stack).
- [x] [Review][Patch] (low; fix-risk low: test lines only) A corrected address (past the last page, or a hand-edited value) replacing its history entry was never checked, so a Back trap would pass (verification-gap) [web/e2e/history/history.spec.ts:H3] -- H3 presses Back after each correction.
- [x] [Review][Patch] (low; fix-risk low: test lines only) A filter or tab change going back to page 1, and an emptied date input clearing the day, were never checked (verification-gap+blind) [web/e2e/history/history.spec.ts:H2,H3] -- H3 changes the outcome and the tab from page 2; H2 empties the date.
- [x] [Review][Patch] (low; fix-risk low: a deletion) `cleanHistory` only called `cleanFixtureRows`, and both specs called both, so every clean-up ran twice (blind) [web/e2e/support/history.ts:95] -- the wrapper is gone; the specs call `cleanFixtureRows` once.
- [x] [Review][Patch] (low; fix-risk low: text of a test) `Test.Web.HistoryApi`'s doc said TestBadParams proves "nothing is read" (no assertion does), and an `api/history.spec.ts` message said "sees none of the other incidents" on an assertion of its own incidents (blind) [src/ocutalon/cls/OcuTalon/Test/Web/HistoryApi.cls:6, web/e2e/api/history.spec.ts:228] -- both say what the assertion checks.
- [x] [Review][Defer] (low; fix-risk med: a product call on zones) The Date filter is an instance-zone day (this spec's Always rule) while a decision row's time is a page time in the browser's zone, so on the online demo a visitor in another zone can see a filtered decision stamped on the day before or after (blind+edge) [web/src/app/history/history-page.ts:441] -- deferred: spec-bound here (`by-design` for this story); the root cause, two zones on one surface, is DW-574 (routed, burndown, the Planner's "one zone per card" call); occurrence appended.

Rejected:
- (blind) `load()` blanks the list on every change -- low: the spec mirrors 37.2's UsagePage ("no loading text", "shows nothing before the first answer"); the page-turn focus move covers the keyboard.
- (blind) H11 reaches controls with `focus()`, not Tab -- low: native select, input and buttons are tab stops by construction; the one roving tabindex (the tabs) is pinned by H7.
- (blind) the Auto Run Result is stale after QA, and the QA section's date -- the fix edits the spec under review.
- (blind) EXPERIENCE does not describe the built page -- false: the spec rules the UX text unchanged except the More to try entry.
- (blind) ADs cited differently (AD-18 in `OwnershipHistory`) -- false: AD-18 binds the time-zone conversions the day-edge tests exercise; the spine row cites the read path's ADs.
- (edge) `day=9999-12-31` passes `DayParam` and is 500 (and the class doc's 404 claim) -- low: unreachable in use (already rejected at implement); a typed year now stops at a readable day.
- (edge) a five-digit year left in the date input -- low: the input shows it, the list is unfiltered; unlikely, and a fix adds a branch.
- (edge) Retry's button leaves on success, so focus drops to the body -- low: the 37.2 sibling keeps focus on Retry by design (a Retry that fails again keeps it); a fix adds a branch on both pages.
- (edge) the channel label and the channel filter can disagree for a decision with two channels -- false: all usage rows of one decision belong to one turn (implement triage).
- (edge) the count and the page are two reads -- low: theoretical; a past-the-end answer is corrected by the page.
- (auditor) `Ownership.cls` gains three methods and three parameters, mid-class -- low: each is a new member (a plain union at merge); no conflict at the merge of 37.2; moving them is churn.
- (auditor) `otherTab` instead of `nextTab` -- low: a two-line toggle of two tabs, not a copy; `nextTab` is typed to the Memory card's four tabs.
- (auditor) `itemNoun` is omitted when there is no noun -- low: the allow-list ("only the keys") holds; the key follows `Live.Payload.Part.ItemNoun`'s shape, pinned by `TestIncidentsShape`.

### Review Findings (rework 1 re-review, 2026-11-11)

Code review of the rework (`22e03497..HEAD` plus the working tree; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at the session's model, no override). 16 raw rows, 4 entries after grouping (high 0, medium 0, low 4), 5 rows rejected. Checklist item `[CI]` usage.spec.ts U8/U1 (ci run 42966931010): fixed. U1, U8, D13, H1, F3 and S1 read `web/e2e/support/header-nav.ts`, which matches `header-nav.ts` (four links for a user, five for an admin). No literal link list is left in `web/e2e`. U8 at 305px shows all four links inside the window (`live sign-in --part 19/20` green on the final tree). Every patch is applied, and nothing is left open in this story.

- [x] [Review][Patch] (low; fix-risk low: comment only) The helper's doc said "a link added to the header changes one list", but F3's box order and F7's Tab walk name each link themselves (blind) [web/e2e/support/header-nav.ts:2] -- the comment now says it is the list for specs that pin the whole link list, and that tests reaching each link by name name their own links.
- [x] [Review][Patch] (low; fix-risk low: one assertion line) U8's "inside the window" check covered only the width, so a link pushed below the 700px window still passed, and the Verification line claimed more (edge) [web/e2e/usage/usage.spec.ts:346] -- each link's box must also lie within the window's height. Pinned by the mutation below (`margin-top: 700px` on `.nav` -> U8 red at the new line).
- [x] [Review][Patch] (low; Rule 19, closed in-pass) The rework's mutation edited the expected list, not the code under test. H1 (AC1's pin) and U8's fit were never seen red under a mutation of the header (auditor+verification-gap) [web/src/app/header/header-nav.ts] -- shown in this pass and recorded under `## Verification` (code review, rework 1).
- [x] [Review][Patch] (low; verification record) F3, S1, D13 and H1 had green runs only on the tree before the review patches, and the task's `live sign-in-3 --part 1/2` (more-to-try) had not been run (blind+verification-gap+auditor) [spec Verification] -- every part was run green on the final tree in this pass (see `## Verification`).

Rejected:
- (blind, edge) `NAV_LINKS_ADMIN` assumes Settings sits second, so a link added before Chat would misplace it silently -- false: F3 and S1 compare the list with the real header, so a misplaced Settings turns them red.
- (blind; auditor observation) U1's "no History link inside `main.usage`" has no requirement or mutation, and would block a later Usage-to-History link -- low: it holds for the shipped page and restates 37.2's "no History item" now that the header holds History. A later story that adds such a link updates the check. Deleting it would shorten a test, which the project block forbids. It is not a 25.2 AC pin, so no mutation line is owed.
- (edge) Scoping U1 to `main.usage` lets a stray History link elsewhere on the page pass -- false as a defect: the More to try History item (AC6) is a correct History link outside `main.usage`, so a page-wide count of one is not an invariant. The header's link is pinned by the list.
- (verification-gap) D13 was never seen red under a mutation -- low: D13 is the same `toHaveText(NAV_LINKS_USER)` form that went red in U1, U8 and H1. Rule 19 asks for one mutation per AC, and AC1's is H1.
- (auditor) The `Shared surfaces:` line does not name U1/U8 or the new helper -- rejected: the fix edits the planning line of the spec under review. The shared list now lives in `web/e2e/support/header-nav.ts`.

### Review Findings (rework 2 re-review, 2026-11-11)

Code review of the rework (`20b768a8..HEAD`; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at the session's model, no override). 27 raw rows, 12 entries after grouping (high 0, medium 4, low 8). Checklist item `[CI]` history.spec H12 :466 (ci run 42981966109): fixed. H9, H12 and H13 assert the failed region `[data-part="history-failed"]`, H9 and H12 also the live region, and a later answer withdraws the error (`Announcer.retract`, additive: every other `Announcer` caller under `web/src` calls only `announce()`, and `announcer.ts` is still the only file that injects the CDK `LiveAnnouncer`). Rule 3 holds (history.spec in a real browser on a real stack).

- [x] [Review][Patch] (medium; fix-risk low: one test, the repo's own clock helpers) H15 depended on wall-clock time it did not control: the third read, two polls, a double rAF and two clicks had to finish inside the live region's 1 s gap, so a slow runner turned it red (all four layers) [web/e2e/history/history.spec.ts:H15] -- H15 now installs Playwright's clock before sign-in, stops it (`freeze`, support/clock.ts) before the first read, and moves it only in 20 ms steps (`stepUntil`) while it waits for what the page shows; the gap cannot pass while the test waits for the host. Probe: 2.5 s of real delay before the third answer and 2 s before the second Retry left H15 green (5.3 s); reverted, identical. Mutation line under `## Verification` (code review, rework 2).
- [x] [Review][Patch] (low; fix-risk low: comment only) The class doc said an answer withdraws the announcement unconditionally; a text spoken joined with others is not emptied (blind) [web/src/app/history/history-page.ts:83] -- it now says "when it still waits or was spoken alone".
- [x] [Review][Patch] (low; fix-risk low: header text) The spec file's header said H9, H12 and H15 "read no row"; each reads the seeded rows after its failure (blind+verification-gap) [web/e2e/history/history.spec.ts:27] -- "to fail a read".
- [x] [Review][Patch] (low; fix-risk low: three assertions) `toHaveText(new RegExp(ERROR))` left the full stop of the oracle a wildcard (auditor) [web/e2e/history/history.spec.ts:H9,H12,H15] -- `toContainText(ERROR)`.
- [x] [Review][Defer] (medium; fix-risk low) H15's second Retry has no page-side signal that the second failure was handled; a reversed order would pass without the queued case (blind+edge+verification-gap) -- `routed owner=burndown` DW-1122. Observed in order in this pass's no-retract mutation run (2 announcements).
- [x] [Review][Defer] (medium; fix-risk low) `Announcer.retract`'s `lastSpoken` guard, which keeps it from emptying another page's announcement, has only a source-regex pin (blind+verification-gap) -- `routed owner=burndown` DW-1121.
- [x] [Review][Defer] (medium; fix-risk low; out-of-footprint) `UsagePage` announces its failed read the same way and never withdraws it (blind+auditor) [web/src/app/usage/usage-page.ts:474] -- `routed owner=burndown` DW-1120.
- [x] [Review][Close] (low) The 300 ms wait in `expectNoStaleError` (H9, H12) catches a regression only when the error was spoken alone before the answer (verification-gap) -- `wontfix-accepted`: green is deterministic on the fixed tree (`announce('')` clears the CDK's pending text synchronously) and the queued case is H15's; reopen_if a no-retract mutation leaves H9 or H12 green on a run whose error was queued.
- [x] [Review][Close] (low) An error spoken joined or counted is not emptied after the answer (auditor+verification-gap) -- `wontfix-accepted` as in the rework 2 triage; reopen_if a screen-reader probe hears the error after an answer that followed two or more quick failed Retries.
- [x] [Review][Close] (low) A History page left within the gap after a failure and opened again leaves the old queued error, which the new page cannot withdraw (edge) -- `wontfix-accepted`: needs a page change inside 1 s of a failure; reopen_if a probe hears "Couldn't load your history." after an answer on a page opened again within 1 s of a failure.
- [x] [Review][Close] (low) A retract within the CDK's 100 ms keeps the queue's record of a spoken text, so the next message may wait up to 1 s (edge) -- `wontfix-accepted`: a delay, nothing wrong is spoken; reopen_if a message after a quick Retry answer is measured late by more than 1 s.
- [x] [Review][Close] (low) The spine's "Announcements and focus" row does not name `retract` (auditor) -- `wontfix-accepted` for this story (the lead owns spine writes, Rule 20); reopen_if a second page calls `Announcer.retract`.

Not filed (outside the rework's range, no HIGH): AC5's keyboard tabs have no `mutation:` line (verification-gap; predates rework 2).

## Spec Change Log

- 2026-11-11 ~08:35Z (lead, rework iteration 2 of 3, trigger=ci): CI red on f21137d1 (ci 42981966109): story -- history.spec H12 error text still found after a successful Retry (the [CI] item); flakes -- live:sign-in row 8 (DW-1081 occurrence), lane-a@Watch GoodMessages (DW-675 occurrence); infra -- lane-a ipm-install path A CPF merge exit 7 (lane-a run 42981966175; the orchestrator files it). No rework for the flakes or infra.

- 2026-11-11 ~06:35Z (lead, rework iteration 1 of 3, trigger=ci): CI red on 284e8904 (ci 42966931010): (a) story — usage.spec.ts U8 pins the old three-link nav (the [CI] item under Tasks & Acceptance); (b) flake — lane-b@rest Test.Web.GuideApi TestOnlyTheMarkerChanges/TestRunAgain, ledgered DW-1094 (occurrence appended, no rework). The branch was integrated forward onto feature c241f87c (41.15, 0.25) before this rework. Feature's 23.5 (partnerWarning) may land later and collide on the More to try count lines; that is handled at the next integrate round (counts fourteen: partnerWarning under "Incidents and fixes", history last under "Usage and history").

- 2026-11-10 (lead, spec gate): Design Notes gained the lead note on DW-941. The PUBLIC TEXT, SECURITY and MORE TO TRY GROUP sections go to the Contest Planner; the rulings are written here before implement.
- 2026-11-11 ~01:45Z (lead, re-dispatch after 37.2 merged as 878da0d2): DW-1102 routed to this story (AC added at 37.2's merge gate); measured the compact header (Design Notes → HEADER FIT) and planned the spacing-only fit K as a Tasks & Acceptance item; F3 updated to five links; G4/G5 unchanged. Lead pre-check of Task 0: 37.2 shipped the fourth heading "Usage and history" (`more-to-try-view.ts:158`, usage in it :146, EXPERIENCE :260/:265), `/v1/usage` forwarding (`Web/Api.cls:266`), `Demo.Features` usage last; the registry is at twelve, history makes thirteen. The implement stage still does Task 0 in full.
- 2026-11-10 ~19:15Z (lead): the Planner's rulings written in verbatim (Design Notes, "Planner rulings at the spec gate"). PUBLIC TEXT approved as proposed, with the no-channel condition. SECURITY accepted; real-HTTP case 7 (page beyond the last → 200, empty list) added. GROUP changed to the fourth heading "Usage and history" (37.2 adds it; 25.2 appends history; K16/K17 stay green, else fallback "Safety and settings"). Tasks, Shared tests and the registry task updated to match.

- 2026-11-11 (implement, Task 0): re-checked against Story 37.2 as merged on this branch (HEAD includes merge 878da0d2; sprint-status 37-2 `done`; `git log --grep "37.2"` shows 878da0d2). No drift in any name the spec uses: header nav (Chat, Settings, Documents, Usage), `Ownership.Usage` and kind `usage`, `Web.Usage` and the `/v1/usage` Map, the More to try registry (twelve items, usage last in "Usage and history", `MORE_TO_TRY_GROUPS` with the fourth heading), `Demo.Features` (usage last), the README Usage bullet, EXPERIENCE (Item 11 under "Usage and history", count word "twelve"), the spine's 37.2 rows. Line numbers in the Code Map moved; everything was re-located by name. `Test.Web.DocumentsApi` filters its Map count by URL, so it needed no edit. One 37.2 test pinned the usage item as the last registry entry and last numbered item (`web/scripts/usage-docs.test.mjs`) and one pinned the incident card's inline chip markup and CSS (`web/scripts/incident-sources.test.mjs`): both follow this story's changes (usage is now second to last, and the chip is `IncidentStateChip`). The README History bullet carries no `[ADDED ...]` marker, as 37.2's Usage bullet carries none (the README is the judges' page); EXPERIENCE's entries carry theirs.

- 2026-11-11 (implement, spine): the three spine rows are written and `updated:` is refreshed; `lint_spine.py` gives the baseline 10 low findings and no `ad_id`, `ad_fields` or new `placeholder` finding. `memlog.py append --type decision` failed with FileNotFoundError: the spine folder has no `.memlog.md` (the folder holds only ARCHITECTURE-SPINE.md and ARCHITECTURE-NOTES.md). Nothing was created for it; the lead decides (Rule 20: no memlog, no append).

## Review Triage Log

### 2026-11-11 — Review pass
- verdicts: 36 findings — high 0, medium 3, low 22, false 11, maybe-false 0
- findings:
  - `[low]` `reject` (blind) the channel filter matches any usage row but the label is the first non-empty one — all usage rows of one decision belong to one turn and so to one channel; the spec names `DecisionChannel` as the filter's source; no multi-channel decision is reachable.
  - `[medium]` `patch` (blind) Previous page and Next page destroy the focused pager while the page loads, so keyboard focus drops to the body — `step()` now focuses the page's main region first; H3 asserts it, the mutation (focus call removed) turns H3 red; `announce-focus-sources.test.mjs` counts the call.
  - `[false]` `reject` (blind) no loading state — Decided in-stage 9 and PUBLIC TEXT row 25: none, as 37.2.
  - `[false]` `reject` (blind) the error state is shared across tabs and stays until the next answer — the ruled 37.2 pattern; `arrived()` clears it on the next answer.
  - `[low]` `reject` (blind) one `DecisionChannel` read per row — at most 25 indexed reads per page; the spec names the method.
  - `[low]` `reject` (blind) the count and the page are two reads — a row recorded in between can only shift one page; theoretical, and a past-the-end answer is corrected by the page.
  - `[false]` `reject` (blind) planning-doc dates ahead of today — the UTC date at the time of the run is 2026-11-11 (`date -u`); the spec says the rows carry the implement stage's UTC date.
  - `[false]` `reject` (blind) header spacing outside scope — it is the spec's DW-1102 task, measured spacing-only fit K.
  - `[low]` `reject` (blind) tab panels without `tabindex="0"` — each panel holds focusable filters or rows; the Memory card sibling has the same shape; not in the spec.
  - `[false]` `reject` (blind) the hidden panel and `outcomeSelect` focus in `clear()` — the Clear filters button exists only on the Decisions tab, so the target exists whenever it runs.
  - `[low]` `reject` (blind) client `isDay` accepts dates the server's zone refuses — year 9999 or a zone gap only; the page shows its error and Retry; a server check of the next day's start was tried and its test could not be shown to fail on the lane's zone, so it was reverted.
  - `[false]` `reject` (blind) no doc says instance incidents are listed on a local install — the README bullet makes no claim about them and the spine row says so.
  - `[low]` `reject` (edge) `DayParam` checks only the day's start (`9999-12-31` reaches Ownership and is 500) — same as the client `isDay` row: unreachable in use.
  - `[low]` `reject` (edge) `isDay` range versus the server — same as above.
  - `[low]` `reject` (edge) a five-digit year in the date input is dropped while the input shows it — unlikely, and the fix adds a branch.
  - `[low]` `reject` (edge) channel filter and label can disagree — same as the first row.
  - `[low]` `reject` (edge) count and page not one transaction — same as the count row.
  - `[low]` `reject` (edge) a closed incident whose summary cannot be rendered reads "No summary was written for this incident." — that is PUBLIC TEXT row 19, ruled for exactly this case.
  - `[false]` `reject` (edge) `failed` not reset when a load starts — the ruled pattern keeps it until the next answer, where `arrived()` clears it.
  - `[low]` `reject` (edge) `Test.Data.Ownership.ReadAll` dies with an invalid OREF if a probe count read fails — a failing read already fails the test; a clearer message is cosmetic.
  - `[low]` `reject` (edge) claim: every unreadable day is 404 — same as the `DayParam` row.
  - `[low]` `reject` (edge) claim: the label always equals the filtered channel — same as the first row.
  - `[medium]` `patch` (verification-gap) the incident `fallback: true` and its flag are never asserted — `TestIncidentsShape`'s open incident now has `Fallback` 1 and the `open|1` assertion; the mutation (no `Fallback`) turns the class red.
  - `[medium]` `patch` (verification-gap) H3's single-page "no pager" assertion can pass in the loading window — H3 waits for the five rows first.
  - `[low]` `patch` (verification-gap) H6 reads the meta text with a non-waiting call — H6 waits for the five rows first.
  - `[low]` `patch` (verification-gap) AC7 (DW-1102) has no `mutation:` line — fit K reverted, `live floor` G4 and G5 red, line written.
  - `[low]` `patch` (verification-gap) AC5's isolation mutation was not run against `api/history.spec.ts` — run (red), line completed.
  - `[false]` `reject` (verification-gap) further mutations for AC1 to AC4 and AC6 — one demonstrated mutation per AC is the bar, and each has one.
  - `[low]` `reject` (verification-gap) H7's fixed 1.5 s wait — a negative assertion ("never switches by itself") has no readiness signal to wait for.
  - `[low]` `reject` (verification-gap) H7 and H10 count one "No summary yet" row — the rows are the test's own tagged fixtures, seeded in `beforeAll`, cleaned in `afterAll`, one worker.
  - `[low]` `reject` (verification-gap) `TestDispatch` asserts differently with and without the role in the test process — the sibling `UsageApi` has the same pair.
  - `[false]` `reject` (verification-gap) the `ux-strings` and `floor-sources` edits add no runtime coverage — an observation, no defect.
  - `[low]` `reject` (verification-gap) one extra query per row — same as the per-row row.
  - `[false]` `reject` (verification-gap) `web/test-results/**` files exist — gitignored run output, not part of the change.
  - `[low]` `reject` (intent-alignment) a failed `Rows` read is not tested at the route — `TestNoSession` covers the 500 path that `ServerError` serves for both failures.
  - `[false]` `reject` (intent-alignment) reuse by extraction is a wider footprint than "reuses" — the spec's Tasks name each extraction and export.

### 2026-11-11 — Review pass (rework 1, follow-up)
- verdicts: 13 findings — high 0, medium 2, low 9, false 2, maybe-false 0 (the intent-alignment layer reported no finding, only readings)
- findings:
  - `[low]` `reject` (blind) titles and messages still name the link counts or positions -- F3's "five links", S1's "Chat and Settings" and H1's "between Documents and Usage" are true of the header; not a defect.
  - `[low]` `patch` (blind) nothing ties the two lists to the header and the helper comment overstated "one list" -- `NAV_LINKS_ADMIN` is now the user list with Settings after Chat, and the comment says so; the specs run against the real header, so a drift is red (it was, in this CI run).
  - `[low]` `reject` (blind) the reworded messages no longer name the links -- the list is one click away in the helper and the assertion prints the received and expected arrays.
  - `[low]` `patch` (blind) U1's `main.usage` scope couples to a class and passes if absent -- the same patch as the next row (a count of 1 on `main.usage` first); U8 already queries `main.usage`.
  - `[medium]` `patch` (edge) U1's History check is vacuous when `main.usage` is missing -- `toHaveCount(1)` on `main.usage` added before the scoped link check; `--part 19/20` green.
  - `[false]` `reject` (edge) U8 at 305px with four links is unverified in the diff -- U8 passed on a fresh stack (`--part 19/20`, 19 passed) with each link visible and inside the window.
  - `[low]` `patch` (edge) the two lists are hand-written copies -- the same patch as the second row.
  - `[low]` `patch` (edge) the same claim as the second row, against the spec's "one shared source" -- the admin list now derives from the user list.
  - `[false]` `reject` (edge) the diff has no mutation line -- the diff excludes the spec; the Rework 1 block in `## Verification` has it.
  - `[low]` `patch` (gap) F3 and S1 (`NAV_LINKS_ADMIN`) have no `mutation:` line -- the line now names F3 red and S1 red.
  - `[medium]` `patch` (gap) U1's History check can pass without observing anything -- the same root cause as the fifth row.
  - `[low]` `reject` (gap) U1's title says "and no Settings" with no separate assertion -- the exact-list `toHaveText` covers it; wording only.
  - `[low]` `patch` (gap) two independent literals -- the same patch as the second row.

### 2026-11-11 — Review pass (rework 2, H12 error after Retry)
- verdicts: 20 findings — high 0, medium 7, low 10, false 3, maybe-false 0 (the intent-alignment layer reported readings only)
- findings:
  - `[medium]` `patch` (blind) `Announcer.retract`'s emptying branch is guarded only by a source regex -- a mutation line was added and observed: the `announce('')` call removed turns H9 and H12 red (the behavioural pin); the regex pin stays.
  - `[low]` `reject` (blind) a joined or counted announcement is not emptied -- `wontfix-accepted`: documented in the `retract` doc comment, needs the error spoken joined with other texts before an answer; reopen_if a screen-reader probe hears the error after an answer that followed two or more quick failed Retries.
  - `[low]` `reject` (blind) a repeated failure queues a second copy -- same root as the previous row, `wontfix-accepted`: `retract` removes every waiting copy, so only copies that were flushed together before the answer remain.
  - `[medium]` `patch` (blind) H15 is timing-sensitive and `<= 1` also passes with no announcement -- H15 now waits for the first announcement (`announcements(page, ERROR)` is 1) and asserts exactly 1 at the end; slow-runner sensitivity (the answer must land inside the 1 s gap) stays as a residual risk, and it fails red, never green.
  - `[low]` `reject` (blind) the 300 ms wait in `expectNoStaleError` is a race -- H9 and H12 were observed red under both the no-retract and the no-empty mutations, and the queued half is H15's.
  - `[low]` `patch` (blind) the spec file header still said H9 and H12 stub the routes -- it names H15 now.
  - `[low]` `reject` (edge) a joined or burst error stays after the answer -- the same as the second row.
  - `[low]` `reject` (edge) several failed Retries then an answer leave a joined error -- the same as the third row.
  - `[false]` `reject` (edge) `announce('')` could wipe a text another caller made -- `Announcer` is the only file that injects the CDK `LiveAnnouncer` (grep over `web/src`).
  - `[low]` `reject` (edge) a page left while failed keeps a queued error -- `wontfix-accepted`, the announcement on failure is unchanged and an unanswered failure is not made worse; reopen_if a probe hears the error after the page is left within 1 s.
  - `[medium]` `patch` (edge) the real third read can lose the race with the gap in H15 -- the same patch as the fourth row.
  - `[false]` `reject` (edge) the `not.toContainText` passes when the live element is absent -- the element exists from the first announcement, and H15 now asserts that announcement; H9 and H12 went red under the mutations.
  - `[medium]` `patch` (edge) `Announcer.retract` has only a source-regex pin -- the same patch as the first row.
  - `[low]` `reject` (edge) the spec's claim that a later answer withdraws the announcement is broader than the code -- the fix is to edit the spec; the limit is the second row's.
  - `[medium]` `patch` (edge) the third mutation line is caught by a source regex only -- the same patch as the first row.
  - `[medium]` `patch` (gap) H15's precondition is unobserved -- the same patch as the fourth row.
  - `[low]` `reject` (gap) the fixed 300 ms wait checks a negative after an arbitrary delay -- the same as the fifth row.
  - `[medium]` `patch` (gap) no mutation line deletes the emptying branch -- the line was added with its observed red (H9 and H12).
  - `[low]` `reject` (other, gap) a joined or counted announcement is not emptied -- the same as the second row.
  - `[false]` `reject` (other, gap) the negative text assertion passes on a missing element -- the same as the twelfth row.

## Design Notes

### Planner rulings at the spec gate (verbatim) [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, spec gate of Story 25.2, relayed by the orchestrator]

1. PUBLIC TEXT: a to n APPROVED as proposed, including the README bullet (m) unhedged ("filtered by ... channel" holds for every decision that has a channel; DW-941 stays in the burn-down). CONDITION for the gap: a decision with no channel shows NO channel cell text at all; no "Unknown" and no dash with a label.
2. SECURITY: ACCEPTED as specced (two GETs /api/v1/history/decisions and /incidents for any OcuTalonUser; the caller's own session's decide rows and the existing INCIDENTVISIBLE rule; constant statements through the allow-listed prepare with bound filters; the body allow-lists as listed; no new privilege, role, grant, resource, table, column, index, live-event type or retention). Tests as listed satisfy the standing route rule. ADD one case: page beyond the last page (e.g. page=9999 with 26 rows) returns 200 with an empty list, not an error. (If you'd rather 404, say so and the Planner rules.)
3. MORE TO TRY GROUP: CHANGED. A FOURTH heading, "Usage and history", holding usage then history.
   - It becomes the LAST entry of MORE_TO_TRY_GROUPS. 37.2 (merges first) makes the change: its usage item's group becomes "Usage and history"; it appends the heading to the constant; it updates the group-heading e2e's written oracle (the Planner called it K25; on feature 0.22 renamed it K27) and EXPERIENCE (a new `    - Heading "Usage and history".` entry, numbered by panel order, marker "[AMENDED 2026-11-10, Contest Planner ruling: a fourth group for the step-6 pages]"). This SUPERSEDES the 37.2 group ruling ("Safety and settings", last).
   - 25.2 then appends history to that group. Nothing earlier is renumbered.
   - CONDITION: the compact-band tests (K16, K17 at 1280x650 and 1280x600) must stay green with the fourth heading. If they can't, report it and keep both items last in "Safety and settings" as the fallback; don't change the band logic for this.
   - Demo.Features gets ",history" after "usage".

("a to n" in the relay are the PUBLIC TEXT table's "New (needs ruling)" rows; the ruled README bullet is row 31.)

**Planned against Story 37.2 at OCT-epic37 `7ef82a46` (not merged).** Its spec, spine rows, header nav, `Web.Usage`, `Ownership.Usage`/kind `usage`, More to try item, `Demo.Features`, README and EXPERIENCE changes were read with `git show 7ef82a46:<path>`. This story is a delta on those names. Task 0 re-checks them on the merged feature branch.

**Architecture decisions (Rule 6):**
- AD-4: the ownership API is the only read path; no client `SessionRef`; instance incidents through the existing visibility rule.
- AD-13: the envelope, 401/403/404/500; GET needs no request header; text only.
- AD-20: Decision and Usage rows; channel lives on Usage.
- AD-26: one trace builder; a decision's target as the rail's; an incident's diagnosis session.
- AD-27: History reads tables, never messages; retention unchanged at 90 days.
- AD-29: Lane B files.
- AD-31: bridge records read only, no copies.
- AD-33: new reads go into the ownership and REST tables in the same change.
- The Consistency Conventions: the enums, public Refs, UTC ISO, the REST error codes, camelCase.
- No AC contradicts an AD.

**Rule 1/2.** The new routes and Ownership methods have one consumer in this story: the History page. Its Integration AC is the second AC, proven by `web/e2e/history/history.spec.ts` against the real routes. The extracted `IncidentStateChip` is consumed by `incident-card.ts` (unchanged look, pinned by the existing card specs) and the History page.
- Consumed-by: Story 25.2's History page. No later story is named yet.
- Consumes: 37.2's header nav, `Ownership.Rows` dispatch, `/v1/usage` forwarding pattern, `USAGE_TEXTS.channels` and the `failed`/Retry pattern; `Live.Payload.Decision.FromRow`, `TraceLink`, `Watch.Summary.Text` (23.6); `DecisionRow`/`decisionRow`/`formatAt`, `headlineOf`/`stateOf`, `nextTab`, `TraceLink` component, `OutcomeChip`, `FallbackFlag`.
- Siblings extended, not copied:
  - `Web.History` mirrors `Web.Usage`'s structure (one class per forwarded page area, as `Web.Documents` and `Web.Usage` are).
  - `HistoryDecisions`/`HistoryIncidents` extend the `decisions`/`recentIncidents` statements with filters and an offset. They are new kinds because the existing ones are used by the rail and chat with a fixed TOP.
  - Decision rows reuse the rail's builder and component.
  - Incident rows reuse the state map and headline. They do not use `incidentView`, whose closed card drops the diagnosis link and needs the chat's decision store.
  - The incident JSON is built from the row, not through `Live.Payload.Incident.FromRow`, because FromRow reads failure groups and approval requests that the History row does not show and the allow-list would drop.

**Ledger inbox:** DW-1102 (routed 2026-11-11 by 37.2's code review and merge gate) is addressed by the DW-1102 task under Tasks & Acceptance and its epics.md AC.

**Story 23.6 is merged** on this branch (sprint-status :331 `done`, merge `b896ef39`, `Watch/Summary.cls`, `IncidentManager.cls:1109`). The tests therefore use fixture incidents whose `Summary` holds a stored summary object, rendered by the real `Watch.Summary.Text`. That satisfies the AC's "summary fields" clause through the real renderer.

**AC evidence already met (not rebuilt):**
- Retention keeps decisions and incidents for the purge task's days: `Bridge/Purge.cls:28`, `IncidentManager.cls:1356`.
- Outcome chips are icon plus label and unfocusable: `chat/outcome-chip.ts:28-73`.
- The trace link's new-tab wording and sign-in-help variant: `shared/trace-link.ts:94-223`, `shared/trace-view.ts:17-36`.

**Measured (Task 0 of the plan, slot C `ocutalon-slot-c`, OCUTALON, build 154, read-only queries):**
- `SELECT ID FROM %Dictionary.ClassDefinition WHERE ID %STARTSWITH 'OcuTalon.Data.' ORDER BY ID LIMIT ? OFFSET ?` with `[3, 2]` returned rows 3 to 5 of the unpaged order. So `LIMIT ? OFFSET ?` with binds works.
- The full decision statement above, with `LIMIT ? OFFSET ?` and every optional filter bound, prepared and ran (0 rows for an unknown owner).

**Decided in-stage:**
1. Page size 25, offset paging with `page`. 1-based, digits with no leading zero, at most 9999. A page past the end gives an empty list, and the page corrects its address. There is no spine paging convention; `page` and `pages` are new keys.
2. The date filter is one instance-zone day, `day=YYYY-MM-DD`, through a native date input: the Notes `day` and 37.2 day precedent. A range picker is not built.
3. The channel options are the full `Msg.Enum` CHANNEL list in enum order, with 37.2's ruled labels.
4. A decision's channel is its usage rows' channel (`DecisionChannel`). The Decision table has no channel column, and messages may not be read (AD-27). A decision that no model call served (for example a `no_key` or `budget` fallback) has no channel. Its meta line leaves the channel out, and it matches only when no channel filter is set. Flagged for the Planner: closing this fully needs a Lane A `Decision.Channel` column, which is a schema change and a veto item, outside this story.
5. The outcome filter agrees with the chip: `tellnow` includes every fallback.
6. A list of disclosure rows, not a `<table>`. A disclosure that expands in place inside a table row breaks the table's semantics. DESIGN's "History table" (rows ≥40px, chip first) is met visually.
7. `ref` stays in both item shapes, as the `track` key, so that an expanded row never carries over to another decision across pages. It is the public 22-character Ref that `/v1/state` and the live events already give the same session, and never a row id.
8. Incident summaries show in full (incidents are few), not behind a disclosure.
9. No loading text, as 37.2 has none. The error is "Couldn't load your history." with Retry.
10. Unknown query parameters are ignored. The page drops invalid address values before it asks.
11. The History link goes between Documents and Usage (EXPERIENCE :77: "then History and Usage (step 6)").

12. An optional filter is tested with `? IS NULL`, not `? = ''` (the Tasks and Matrix text): an empty bound value is NULL in dynamic SQL on build 154 (measured: with `""` bound, `? = ''` is never true and every filtered statement returned no row; `? IS NULL` is true). The statements are otherwise the spec's. `Ownership.HISTORYDECISIONS` holds the one WHERE text for the page and the count.
13. The Tab, pager and filter details the spec leaves open: filters stay in the address across a tab change and only the page resets; Previous page and Next page are `aria-disabled` (never `disabled`, so focus stays) at an end; Clear filters moves focus to the Outcome select, because its button leaves with the filters; a duplicate value of a known parameter (`outcome=a&outcome=b`) is 404, as a bad value is; the date input's change sets the filter and an emptied input clears it.
14. `history-view.ts` takes the shared labels as arguments (`outcomeOptions(labels)`, `channelOptions(labels)`), as `groupRows` takes the agent names, because a view module imports only types; the page passes `CHAT_TEXTS` chip words and `USAGE_TEXTS.channels`. `OUTCOMES`, `CHANNELS` and `FALLBACKS` are the route's values.
15. `headlineOf` takes `Pick`s of the payload and context it reads (a type narrowing, no behaviour change), so the History row calls it with the row's three fields and the clock.
16. The History keyboard test's filter step uses `selectOption`: a native select's ArrowDown opens the list on macOS and changes the value on Linux, so the key is the browser's, not the page's.

**Lead note at the spec gate (2026-11-10):** Decided in-stage 4's gap is the same root cause as the ledger's DW-941 (routed, owner `burndown`: a decision with no model call has no channel because the bridge `Decision` row has no `Channel`; the fix is a Lane A column). This story neither owns nor closes DW-941 and does not depend on it being decided (it is `routed`, not `decision-pending`); the History page states the gap honestly by leaving such a decision's channel out. If DW-941 lands first, the channel EXISTS clause can switch to the column in a later story.

**HEADER FIT (DW-1102; measured 2026-11-11 by the lead's Task 0, Chromium, the built bundle with `/state` stubbed, floor user ZzFloor in demo mode, `admin: false`; the floor user has 3 links today, so History makes 4: Chat, Documents, History, Usage; script and screenshots in the lead's scratch `e25s2fit/`):**

| State at 640x360@2 | Header | Sticky | Row slack | Narrowest sticky width (h 360) |
|---|---|---|---|---|
| Baseline (3 links, 37.2's values) | 77px | sticky | +19.45px | 625 (static at 620) |
| History added, no change | 121px | static (`scrolls`, writes 0px: the G4/G5 red) | −45.69px | — |
| nav gap 0, link padding 4 only | 121px | static | −17.69px | — |
| F: nav 2, link 4, side 4 (smallest fit) | 77px | sticky | +0.31px | 640 (too fragile) |
| **K: nav 0, link 4, left side gap 4, header inline padding 8, mark-to-wordmark 8** | **77px** | **sticky, writes 77px** | **+18.31px** | **625 (static at 620), as today** |

K is spacing-only (no link hidden, no label, font, group or behaviour change); every link stays at least 37.9x32 CSS px (WCAG 2.5.8); `scrollWidth` = `clientWidth` everywhere. The one visible effect: 4px instead of 12px between the wordmark, the "Demo mode" pill and the switch, and link texts 8px apart (as in the drawer band at 1024-1279px). K at the other floor sizes (floor user with History): 1000x800 and 1023x768 48px sticky, one row; 320x180 145px `scrolls` (G4's quarter control still holds); 320x900 145px sticky; 305x600 no sideways scroll. The README admin at 640x360 (five links) is 121px static before and after (113px with K), as 37.2 recorded: no floor case covers it and scrolling with the page is the header's designed fallback. Drawer band at 1024x768, admin, five links: 56px, one line, account button ends at 1012, no sideways scroll: F3's checks hold with no change.

**HEADER RISK (updated).** If the floor run (any browser) shows G4 or G5 red with K, do not tighten further ad hoc and never hide a link: stop with `## Clarification Needed` (the lead sends a PLANNER REPORT). At 1024px five links fit (measured above).

**CONTENDED FILES (each edit is a plain union):**
- `Web/Api.cls`: one Map line after `/v1/usage`, and one doc bullet appended.
- `Data/Ownership.cls`: four `Statement` blocks appended after `usage`, two methods appended, one class-doc line.
- `Demo/Features.cls`: one `Ids` line after `usage`, plus 37.2's doc line reworded. That reword is a non-append edit, because "last" moves.
- `web/src/app/header/**`: one link inserted between Documents and Usage. This is an insert, not an append, because the UX order requires it. Plus two comment words.
- `web/src/app/api/**`: one new types file, and two methods appended after `usage()`.
- `web/src/app/guide/more-to-try*.ts`: the texts entry, the action union member and the registry entry appended last. 37.2's link branch generalized: a non-append edit of 37.2's lines. The count word follows the registry.
- README: the bullet appended last; the count word at :40.
- EXPERIENCE: the entry appended under its heading; the count word.
- The spine: three rows appended after 37.2's.
- Epic 23's and Epic 41's edits to these files are unaffected: no shared lines except the count words, which follow the registry.

### PUBLIC TEXT (ruled: approved as proposed [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, spec gate of Story 25.2, relayed by the orchestrator])

Every row below marked "New (needs ruling)" is APPROVED as proposed, the README bullet (row 31) unhedged. CONDITION: a decision with no channel shows NO channel cell text at all: no "Unknown" and no dash with a label (Decided in-stage 4 already leaves the channel out of the meta line; the implement stage pins it with a test).

| # | Where (file; location) | String (verbatim) | Status |
|---|---|---|---|
| 1 | `history-view.ts` `HISTORY_TEXTS.title`; route title | "History · OcuTalon" (`'History · OcuTalon'`) | Given: AC 1, UX-DR22 |
| 2 | `header-nav.ts`; link between Documents and Usage | "History" | Given: EXPERIENCE :59, :77; UX-DR21 |
| 3 | `history-page.ts`; hidden `h1` (also names the tablist) | "History" | Given: EXPERIENCE :59 |
| 4 | tab labels, and each tab panel's hidden `h2` | "Decisions", "Incidents" | Given: EXPERIENCE :1062; AC |
| 5 | filter labels (`<label for>`) | "Outcome", "Channel", "Date", "Fallback" | New (needs ruling); the words of FR-53 |
| 6 | Outcome options | "Any outcome", then "Ignore", "Digest", "Tell now", "Act" | "Any outcome" is new (needs ruling); the four labels are given (EXPERIENCE :290-294), imported |
| 7 | Channel options | "Any channel", then "Web chat", "Simulated phone", "Simulated mailbox", "Telegram", "Email", "Webhook", "Slack", "System", "Heartbeat" | "Any channel" is new (needs ruling); the labels were ruled at 37.2 (`USAGE_TEXTS.channels`), imported |
| 8 | Fallback options | "All decisions", "Fallback only", "Without fallback" | New (needs ruling) |
| 9 | Date | native date input, no text of its own | — |
| 10 | button, shown when any filter is set | "Clear filters" | New (needs ruling) |
| 11 | decision row | chip labels and meanings, "Fallback" flag, fallback sentences, time, confidence, cost, " · " separator | Shipped strings reused (rail `DecisionRow`) |
| 12 | decision row meta, part 2 | the channel label (row 7) | Ruled at 37.2 |
| 13 | disclosure button's accessible name | its content: chip label plus the item's summary (data), described by the outcome's meaning | Shipped (rail) |
| 14 | trace link | "Trace" + hidden " (opens in a new tab)"; before the help is seen on a local install: "Open in Visual Trace (shows sign-in help first)" with `aria-haspopup="dialog"` | Shipped (`TRACE_TEXTS`); given EXPERIENCE :219-220 |
| 15 | incident row chip and headline | "Open", "Awaiting approval", "Fixing", "Resolved", "Closed"; "{count} {noun} failed since {time}" / "{count} {noun} failed" | Shipped (`INCIDENT_TEXTS`) |
| 16 | incident row times | "Noticed {time}", "Closed {time}" | New (needs ruling) |
| 17 | incident summary | the stored summary's lines (23.6 catalog, `summary.*`) | Shipped (23.6) |
| 18 | no summary, while not closed | "No summary yet. OcuTalon writes one when the incident closes." | New (needs ruling); true per FR-30 and `IncidentManager.cls:1109` |
| 19 | no summary, closed | "No summary was written for this incident." | New (needs ruling); a closed incident whose summary failed to build (`Watch/Summary.cls` Build) |
| 20 | pager | "Previous page", "Next page", "Page {page} of {pages}" | New (needs ruling) |
| 21 | pager `nav` `aria-label` | "Decision pages", "Incident pages" | New (needs ruling); not "Pages", which names the header nav |
| 22 | empty, filters set | "No decisions match these filters." | Given: EXPERIENCE :399, AC, UX-DR147 |
| 23 | empty, no filter | "No decisions yet." | New (needs ruling) |
| 24 | empty incidents | "No incidents yet." | New (needs ruling) |
| 25 | loading | none: the panel stays empty until the answer | As 37.2 |
| 26 | error, and its button | "Couldn't load your history." / "Retry" | Error is new (needs ruling; 37.2's ruled pattern "Couldn't load your usage."); "Retry" ruled at 37.2 |
| 27 | More to try label | "Look back at past decisions" | New (needs ruling) |
| 28 | More to try look-for | "On the History page, filter the Decisions tab by outcome, channel, date or fallback, and open a decision to read its reasons, with a link to its trace. The Incidents tab lists your incidents with their state and, once an incident has closed, its summary. If it reads "No decisions yet.", run the guide first." | New (needs ruling) |
| 29 | More to try control (a link to `#/history`) | "Open the History page" | New (needs ruling); mirrors 37.2's "Open the Usage page" |
| 30 | EXPERIENCE More to try | `- Item N. Label "Look back at past decisions". Look for: "<row 28>" Control: "Open the History page".` plus "Item N's control is a link to the History page." and the count word | New (needs ruling); N is the next number after usage's |
| 31 | README "New since 1.0.0", appended last | `- **A History page.** Open History in the header to look back at the decisions OcuTalon made on your messages, filtered by outcome, channel, date and fallback, each with its reasons and a link to its trace, and at your incidents with their state and, once closed, their summary. On the online demo you see only your own session's decisions and incidents. Try it: More to try, *Look back at past decisions*.` | New (needs ruling); the shape of 37.2's ruled bullet |
| 32 | README :40 / registry comment / EXPERIENCE count | the count word one higher than after 37.2 | Mechanical (`sources-docs.test.mjs`) |

### SECURITY (ruled: accepted as specced, one case added [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, spec gate of Story 25.2, relayed by the orchestrator])

Accepted as specced. ADDED case: a page beyond the last page (e.g. `page=9999` with 26 rows) returns 200 with an empty list, not an error (real-HTTP test 7 below; it matches the I/O matrix row "Page past the end").

**Routes** (new; both are GET, so they need no `X-OcuTalon-Request` header):

`GET /api/v1/history/decisions`
- `outcome`: absent, or one of `ignore`, `digest`, `tellnow`, `act`.
- `channel`: absent, or one of `web`, `phone`, `mailbox`, `telegram`, `email`, `webhook`, `slack`, `system`, `heartbeat`.
- `day`: absent, or `YYYY-MM-DD` that `Data.Time.FromLocal` reads.
- `fallback`: absent, `yes` or `no`.
- `page`: absent, or 1 to 9999 with no leading zero.
- Any other value of a known parameter, the empty string included, gives 404 `not_found`. Unknown parameters are ignored.

`GET /api/v1/history/incidents`
- `page`: as above.

`GET /api/v1/history` and any other subpath give 404, and other methods have no route.

**Who may call:** any user with the OcuTalon user role (`OcuTalonUser`), behind the AD-13 envelope: 401 `signed_out`, 403 `no_role`. The routes are not admin-only, and the user role is not widened.

**Rows returned:** only the caller's own CSP session's rows (`Ownership.SessionRef`).
- Decisions: `OwnerRef` = that session, Kind `decide`. Never another session's, never `eval`, `instance` or ownerless rows (`Rows` refuses those owners, and the SQL has `OwnerRef = ?`).
- Channel: the EXISTS subquery reads only usage rows of the same owner.
- Incidents: exactly `INCIDENTVISIBLE`, that is noticed incidents (`NoticedAt` set) that are either the session's own, or, on a local install only (`LocalFlag` 1), owner `instance` of a namespace and production that one of this session's own `BackgroundCheck` rows of Kind `production` watches. On the online demo only its own. Never `eval`, never another session's.
- The summary text is rendered only for rows already admitted.

**Read path:**
- Four new constant statements in `Ownership.Statement`, run by the existing allow-listed unchecked prepare in `Ownership.Rows`. No edit to `ALLOW_UNCHECKED`.
- `Live.Payload.Decision.FromRow`, `DecisionChannel` (kind `turnUsage`) and `TraceLink`.
- New privilege, role, grant, resource, table, column, index, live-event type or retention: none.

**Body:**
- Decisions: `{"page","pages","decisions":[{ref, outcome, reasons, fallback, fallbackReason, itemSummary, recordedAt, channel, traceUrl?, confidence?, costUSD?}]}`.
- Incidents: `{"page","pages","incidents":[{ref, state, fallback, count, itemNoun, firstAt, noticedAt, closedAt, summary, traceUrl?}]}`.
- `ref` is the public Ref (Decided 7). There is no row id, `ownerRef`/`SessionRef`, user name, `itemId`, `kind`, `traceHeaderId`, `traceNamespace`, `model`, token counts or incident `namespace`/`production`.

**Real-HTTP tests (`web/e2e/api/history.spec.ts`):**
1. Signed out (an anonymous context) on both routes: 401 `signed_out`, no `www-authenticate`.
2. The LIVE fixture user (OcuTalonUser only) gets 200 on both, with exactly the seeded rows per filter (each filter alone and two combined; page 2 of 26).
3. A second session (PANEL) gets its own rows and none of LIVE's, and LIVE gets none of PANEL's, for both routes, with and without filters. Seeded `eval` rows never appear.
4. Every invalid value in the matrix gives 404 `not_found`.
5. Key allow-list: the sorted top keys, and every item's sorted keys, are within the lists above. The serialized body contains neither user name, neither session Ref, nor any `"id"`, `ownerRef`, `itemId` or `traceHeaderId`.
6. `OCUTALON_TRACEONLY_USER` gets 403 `no_role`.
7. [ADDED by the Planner's ruling] A page beyond the last page: with 26 seeded decisions, `page=9999` (and `page=3`) gives 200 `{"page":9999,"pages":2,"decisions":[]}` (the same for incidents), never an error.

### MORE TO TRY GROUP (ruled: CHANGED [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, spec gate of Story 25.2, relayed by the orchestrator])

Ruled: a FOURTH heading, **"Usage and history"**, the LAST entry of `MORE_TO_TRY_GROUPS`, holding usage then history. Story 37.2 (merges first) makes the change: its usage item's group becomes "Usage and history", it appends the heading to the constant, it updates the group-heading e2e's written oracle (K27 on feature) and EXPERIENCE (a new `    - Heading "Usage and history".` entry, numbered by panel order). This supersedes 37.2's earlier group ruling ("Safety and settings", last) and this spec's proposal.

Story 25.2 then APPENDS history to that group, last: its registry row with `group: 'Usage and history'`, one `GROUP_OF` line, and its EXPERIENCE entry under the "Usage and history" heading. Nothing earlier is renumbered. E2E: **K28**. `Demo.Features` gets `,history` after `usage`.

CONDITION: the compact-band tests K16 and K17 (1280x650 and 1280x600) must stay green with the fourth heading and the history item. If they cannot, do not change the band logic: report it (`## Clarification Needed` from the implement stage) and the fallback is both items last in "Safety and settings".

Task 0 confirms on the merged feature that 37.2 shipped the heading as ruled; if it did not (for example 37.2 kept usage in "Safety and settings"), that is drift for the Spec Change Log and a `## Clarification Needed`, never a 25.2 edit of 37.2's heading.

(Proposal at the gate, superseded: "Safety and settings", last; alternative "Incidents and fixes".)

### SPINE ROWS (this story's own; AD-33, the amended first AC)

`<date>` in these rows and in the README/EXPERIENCE `[ADDED …]` notes is the implement stage's UTC date, YYYY-MM-DD, written when the rows land.

- **Ownership tables, cross-area table** (`| Class or API | Lane | Built in |`), appended after 37.2's: `| \`OcuTalon.Data.Ownership.HistoryDecisions(sessionRef, outcome, channel, day, fallback, page, .pages, .sc)\` and \`HistoryIncidents(sessionRef, page, .pages, .sc)\`, with the \`Ownership.Rows\` kinds \`historyDecisions\`, \`historyDecisionTotal\`, \`historyIncidents\` and \`historyIncidentTotal\` (AD-4, AD-13, AD-27): the session's own \`OcuTalon.Bridge.Data.Decision\` rows of Kind \`decide\` (Lane A's table, read only; channel through the same owner's \`Usage\` rows) and the incidents \`INCIDENTVISIBLE\` admits, 25 to a page, newest first, read by the history routes [ADDED <date>, Story 25.2] | B | Story 25.2 |`
- **Same table**: `| The header navigation's History entry (\`web/src/app/header/header-nav.ts\`, between Documents and Usage, for every signed-in user) and the History page (\`web/src/app/history/\`, \`#/history\`), which reads only \`GET /api/v1/history/decisions\` and \`/incidents\` [ADDED <date>, Story 25.2] | B | Story 25.2 |`
- **REST surface**, after 37.2's usage row: `| \`GET /api/v1/history/decisions?outcome=&channel=&day=&fallback=&page=\` and \`GET /api/v1/history/incidents?page=\` | \`OcuTalon.Web.History\`, forwarded from \`Web.Api\`'s map: the CSP session's own decisions (filters per the enums, an instance-zone \`day\` through \`Data.Time\`, \`fallback\` \`yes\`/\`no\`) and visible incidents (with the 23.6 summary as text) through \`Ownership.HistoryDecisions\`/\`HistoryIncidents\`, 25 a page: 200 with \`page\`, \`pages\` and the list; any other value of a known parameter is 404 \`not_found\`; a failed read is 500 \`server_error\`; any user with the OcuTalon user role, behind the AD-13 envelope [ADDED <date>, Story 25.2] |`

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s2i` and the warm tag is `e25s2iw`.

Compile checks may also use the dev slot: profile `ocutalon-slot-c`, namespace `OCUTALON`, passed on every MCP call, with one `iris_execute_tests` per message. IRIS runs only on slot C and on lane-C throwaways.

Run one command per tool call, each sized to about 150 s; one test class per call is always safe. A call moved to the background is waited for in bounded foreground polls. Tear down only your own tags, and run `ci/warm.sh down` at the end, also after a failure. Scratch goes under the session scratchpad's `e25s2impl/`.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e25s2iw ci/warm.sh up` once. Then one class per call: `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s2iw ci/iris.sh class OcuTalon.Test.Data.OwnershipHistory`, then the same for `OcuTalon.Test.Web.HistoryApi`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Demo.Features`, `OcuTalon.Test.Web.DocumentsApi`, and the sibling `OcuTalon.Test.Data.OwnershipUsage` once 37.2 is merged -- each `CLASS … passed`.
- (loop) `node --test web/scripts/history-view.test.mjs web/scripts/settings-view.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/sources-docs.test.mjs web/scripts/ux-strings.test.mjs web/scripts/floor-sources.test.mjs` -- all pass.
- (loop) e2e:
  - First `$LANE OCUTALON_RUN_TAG=e25s2i ci/iris.sh build`.
  - Find the part holding `api/history.spec.ts`: `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"` and `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`. Choose n so that the part holds at most two spec files (setup is about 93 s). Then run `$LANE OCUTALON_RUN_TAG=e25s2i ci/iris.sh live sign-in --part k/n` -- the part passes.
  - The same for `history/history.spec.ts`, `frame/frame.spec.ts` and `documents/documents.spec.ts` (chromium), `settings/settings.spec.ts` (`e2e:sign-in-2`, `live sign-in-2 --part`) and `guide/more-to-try.spec.ts` (`e2e:sign-in-3`, `live sign-in-3 --part`).
  - Finally `$LANE OCUTALON_RUN_TAG=e25s2i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- the same 10 low `placeholder` findings as the baseline (plan scratch `e25s2plan/lint-before.json`), and no `ad_id`, `ad_fields` or new `placeholder` finding.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- each passes.
- (once) `bash ci/checks.sh`, in batches of its `CHECK_SCRIPTS` if one call cannot hold it -- every block passes, including `test-class-rules.sh` (no new unchecked prepare), `test-boundaries.sh` (ASCII, Rule 14), `test-readme.sh` and `test-ci-config.sh`.
- The full IRIS shards and groups are left to CI.

**Shared surfaces:**
- the header navigation's entries and Tab order (`settings.spec.ts:68`, `documents.spec.ts:338`, `frame.spec.ts` F3/F7, and 37.2's 1024px test);
- `pageOf`'s pages;
- the More to try registry, its count words and group lists (`RULED`, `ACTION_OF`, `GROUP_OF`; `more-to-try.spec.ts` `ITEMS`, `controlOf`, K3; `more-to-try-sources` counts; README :40; EXPERIENCE's count and numbering; the registry comment);
- `Demo/Features.cls` `Ids` / `guide.features` (`Test.Demo.Features`);
- the README "New since 1.0.0" list and `sources-docs.test.mjs`'s counts;
- the `ux-strings` and `floor-sources` lists;
- the REST route map (the spine REST table, the `Web.Api` UrlMap Map pins in `DocumentsApi`/`UsageApi`);
- the spine's cross-area table;
- `TestIsolationEveryRowKind`'s kind list;
- the incident card's chip markup.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19), one per AC, each observed red and reverted byte-identical (2026-11-11, implement stage; the file was compared with `cmp` against a copy after each revert):**
- mutation: the `historyDecisions` owner check made `(d.OwnerRef = ? OR 1 = 1)` -> `OwnershipHistory` TestIsolation red (also TestPaging and TestDayEdges), and `api/history.spec.ts` (3) red (the isolation test, `live sign-in --part 2/20`, 1 failed of 10); reverted, `cmp` identical;
- mutation: the outcome clause's fallback branch removed (`? IS NULL OR ? IS NULL OR (d.Fallback = 0 AND d.Outcome = ?)`) -> `OwnershipHistory` TestFilters red (the outcome `tellnow` and the `tellnow` with fallback `yes` assertions);
- mutation: `queryOf` not writing `outcome` -> `history-view.test.mjs` (round trip, writes only the values that are set, canonical address, merge query) red, and `history.spec.ts` H2 (the reload and copied-link test) red;
- mutation: the DecisionRow replaced by `<span>{{ row.title }}</span>` with no button -> `history.spec.ts` H4 (the disclosure test) red, with H8 and H11;
- mutation: the incident row's `summary` lines dropped (`summaryLines(...).slice(0, 0)`) -> `history.spec.ts` H7 (the Incidents tab test) red;
- mutation: the History link moved after Usage in `header-nav.ts` -> `frame.spec.ts` Tab order (F3 list and F7) red, 3 tests;
- mutation: the registry entry's action changed from `'history'` to `'usage'` -> `more-to-try.spec.ts` K28 red (and K3's href assertion);
- mutation (DW-1102): the stacked band's fit K reverted (header padding `var(--space-3)`, `.side` gap and `--header-nav-gap` and `--header-nav-item-inline` 6px as before, `.home` gap dropped) -> `live floor` red in `layout.spec.ts` G4 and G5 only (2 failed, 105 passed); reverted, `cmp` identical, and with fit K `live floor` (Chromium, Firefox, WebKit) passed 107 tests, G4 and G5 included; nothing in `layout.spec.ts` was edited;
- mutation: the `Previous page`/`Next page` focus move to the main region removed from `step()` -> `history.spec.ts` H3 red (its `toBeFocused` assertion), the bundle rebuilt for the mutation and again after the revert; `cmp` identical;
- mutation: the open fixture incident of `HistoryApi.TestIncidentsShape` without `Fallback` 1 -> `Test.Web.HistoryApi` red (the `open|1` assertion); restored, green.

**QA stage (2026-11-10, run tags `e25s2q`; lane C; every mutation observed red and reverted, `cmp` against a copy and `git status --short` / `git diff --stat` identical after each revert):**

Tests added or changed by QA (gaps only):
- (QA) `web/scripts/history-docs.test.mjs` (new, node --test; found by `npm --prefix web test`): the README History bullet word for word, once, after the Usage bullet; EXPERIENCE's history item (label, look-for and control from the registry, directly after the usage item under "Usage and history", the story marker, the "Item N's control is a link to the History page." sentence); the three spine rows (ownership API, header entry and page, REST), the REST row against `Web.History`'s URL map. These AC1 texts were pinned by no test before.
- (QA) `web/e2e/api/history.spec.ts` (changed): a third test, "a page past the last is 200 with an empty list and the page count, on both routes" (Planner case 7 for the incidents route, which had none, and for an empty day), as the LIVE fixture user with no seeded row.
- (QA) `web/e2e/floor/browsers.spec.ts` (changed): E4, tag `@browsers`, so it runs in Chromium, Firefox and WebKit through the floor projects that exist (no new project): Next page and Previous page on the History page, answers stubbed in the browser (25 decisions then 1, held 400 ms), keyboard Enter on the focused pager button, focus lands on `main.history`. It closes the implement stage's residual risk (the page-turn focus move was proven in Chromium only). `web/scripts/playwright-projects.test.mjs` (changed) lists E4 among the `@browsers` ids; `docker/tests/test-floor.sh` comments and PASS/FAIL words say E1 to E4.
- Audited and found covered, nothing added: every I/O matrix row at Ownership level (`OwnershipHistory`) and at the route (`HistoryApi`, `api/history.spec.ts`); the Planner's no-channel condition is pinned by `history.spec.ts` H6 (meta text holds only the time, no channel word, no "Unknown") and by `HistoryApi.TestDecisionsShape` (channel `""`); real-HTTP case 7 for decisions was in `api/history.spec.ts` (page 3 and 9999), for incidents it is the QA test above (and `HistoryApi.TestIncidentsShape` at class level).

Mutations (QA, in addition to the implement stage's):
- mutation (AC1, the spine's rows): the REST row of `ARCHITECTURE-SPINE.md` deleted -> `history-docs.test.mjs` "has the REST row, naming exactly the routes that Web.History serves" red (1 failed of 9); restored, 9 passed, `cmp` identical;
- mutation (Planner case 7, both routes): `Web.History` answering 404 when `page` > `pages` (a line after each `Ownership.History*` read) -> `api/history.spec.ts` the first test red (page 3 "is not an error") and the QA test red (decisions, `day=` empty, page 2); with the incidents route alone mutated, only the QA test red ("incidents page 2: not an error"); reverted, `cmp` identical;
- mutation (the Planner's no-channel condition): `history-page.ts` giving a decision with no channel the label "Unknown" -> `history.spec.ts` H6 red ("no channel word, no Unknown and no label"; `live sign-in --part 14/20`, 2 failed of 11 with H3 below); reverted, `cmp` identical;
- mutation (AC3's keyboard path, QA test E4): the `main` focus call removed from `step()` in `history-page.ts` (the implement stage's H3 mutation) -> `browsers.spec.ts` E4 red in all three engines (`live floor`: 3 failed, 107 passed: `[floor]`, `[floor-firefox]`, `[floor-webkit]`), and `history.spec.ts` H3 red; the bundle rebuilt for the mutation and again after the revert; reverted, `cmp` identical.

**Code review (2026-11-11, run tag `e25s2c`, lane C; each mutation observed red and reverted, `cmp` against a copy and `git status --short` / `git diff --stat` identical after the revert; the bundle rebuilt for the mutation and again after it):**
- mutation: `FIRST_YEAR` in `history-view.ts` set to 1 -> `history-view.test.mjs` "takes no day before 1841" red (1 failed of 22); reverted, `cmp` identical;
- mutation (three at once, each aimed at one new test): the `pickDay` guard removed, the incident row's `<app-fallback-flag />` removed, and `pageWhenBeside` replaced by `pageWhen` in `history-page.ts` -> `live sign-in --part 13/20` 3 failed, 11 passed: H12 red (the Fallback flag by the chip), H13 red ("one history entry": 4 entries), H14 red (no " CET" after the Noticed time); reverted, `cmp` identical.
- Green on the final tree: `live sign-in --part 13/20` (`history/history.spec.ts`, 14 passed), `live sign-in --part 2/20` (`api/history.spec.ts` with `body-limit` and `memory`, 11 passed), `npm --prefix web test` (1893 passed), `npm --prefix web run lint`, `ci/iris.sh build` (the production bundle), `test-boundaries.sh`; `Test.Web.HistoryApi` (doc line only) compiled on slot C.

**Rework 1 (CI, run 42966931010 on 284e8904): the nav pins of the shared surfaces read one list, `web/e2e/support/header-nav.ts` (`NAV_LINKS_USER`; `NAV_LINKS_ADMIN` is it with Settings after Chat), in U1, U8, D13, H1, F3 and S1.**
- mutation: History removed from `NAV_LINKS_USER` -> `live sign-in --part 19/20` U1 and U8 red (17 passed), `--part 12/20` F3 red (20 passed), `live sign-in-2 --part 6/6` S1 red (25 passed); each reverted, `git status --short` and `cmp` identical.
- Green on the final tree, fresh lane-C stacks: `live sign-in --part 19/20` (19 passed, U8's four links visible and inside the 305px window), and on the tree before the review patches `--part 13/20` (history), `--part 12/20` (frame), `--part 10/20` (documents) and `live sign-in-2 --part 6/6` (settings), all `all checks passed`; `npm --prefix web test` (1896) and `npm --prefix web run lint`.

**Code review, rework 1 (2026-11-11, run tag `e25s2c2`, lane C, fresh stacks; the bundle rebuilt with `ci/iris.sh build` for each mutation and after the revert; `header-nav.ts` compared with `cmp` against a copy, and `git status --short` / `git diff --stat` identical after the revert):**
- mutation (AC1, code under test): the History link moved after Usage in `web/src/app/header/header-nav.ts` -> `live sign-in --part 13/20` H1 red (1 failed, 13 passed), and `live sign-in --part 19/20` U1 and U8 red at the link list (2 failed, 17 passed); reverted, `cmp` identical.
- mutation (U8's fit at 305px, the review patch): `margin-top: 700px` added to `.nav` in `header-nav.ts` -> `live sign-in --part 19/20` U8 red at "Chat is inside the window's height" (1 failed, 18 passed); reverted, `cmp` identical. (`flex-wrap: nowrap` on `.nav` left U8 green: the four links fit one 305px row.)
- Green on the final tree, all `all checks passed`: `live sign-in --part 19/20` (19 passed), `--part 13/20` (history, 14), `--part 12/20` (frame, 21), `--part 10/20` (documents, 23), `live sign-in-2 --part 6/6` (settings, 26), `live sign-in-3 --part 1/2` (more-to-try, 128); `npm --prefix web run lint` passed.

**Rework 2 (CI, run 42981966109 on f21137d1): the history error is asserted on its own region (`[data-part="history-failed"]`), and a later answer withdraws the failure's announcement (`Announcer.retract`, additive).** Measured cause: a Retry answered within 100 ms of the failure left the live region empty at the answer and holding "Couldn't load your history." 1.5 s later (the CDK sets a text 100 ms after it is handed one), so a stale error was spoken after the answer and a page-wide text search counted it.
- mutation: `history-page.ts` no longer calling `announcer.retract` on the answer after a failure -> `live sign-in --part 13/20` H9, H12 and H15 red (3 failed, 12 passed); reverted, `cmp` identical, the bundle rebuilt.
- mutation: `AnnounceQueue.retract` removing nothing (the `splice` dropped) -> `live sign-in --part 13/20` H15 red alone (1 failed, 14 passed), and `announce-queue.test.mjs` retract tests red (3 failed of 24); reverted, `cmp` identical, the bundle rebuilt.
- mutation: `Announcer.retract` handing the live region the text instead of the empty text -> `announce-focus-sources.test.mjs` "hands every message to the queue" red (1 failed of 18); reverted, `cmp` identical.
- mutation (review patch): `Announcer.retract` without its `void this.live.announce('', 'polite')` call -> `live sign-in --part 13/20` H9 and H12 red at `expectNoStaleError` (2 failed, 13 passed); reverted, `cmp` identical, the bundle rebuilt.
- Green on the final tree, fresh lane-C stacks, twice: `live sign-in --part 13/20` (history, 15 passed each run, H15 now asserting the first failure announced and exactly one announcement of the error); `npm --prefix web test` (1910 passed); `npm --prefix web run lint`.

**Code review, rework 2 re-review: H15 runs on the page's clock (Playwright `page.clock`, stopped by `freeze` before the first read and moved by `stepUntil` in 20 ms steps), so the live region's 1 s gap passes only when the test moves it.**
- mutation (H15 changed; AC pin for the withdrawn announcement): `history-page.ts` no longer calling `announcer.retract` on the answer after a failure -> `live sign-in --part 13/20` H9, H12 and H15 red (3 failed, 12 passed; H15 "Expected: 1, Received: 2"); reverted, `cmp` identical, the bundle rebuilt.
- probe (not a mutation, the hermeticity claim): 2.5 s of real delay before the third answer and 2 s of real wait before the second Retry -> H15 green (15 passed); reverted, `cmp` identical.
- Green on the final tree, fresh lane-C stacks: `live sign-in --part 13/20` 15 passed (twice, see `## Decisions` of the review), `npm --prefix web test` (1910 passed), `npm --prefix web run lint`.

QA runs, green on the unmutated tree: `live sign-in --part 2/20` (`api/history.spec.ts` 3 tests with `body-limit` and `memory`, 11 passed), `live floor` (110 passed: 107 plus E4 in each of Chromium, Firefox and WebKit, G4 and G5 unedited), `npm --prefix web test` (1892 passed), `npm --prefix web run lint`, `test-boundaries.sh`, `test-ci-config.sh`, `test-class-rules.sh`. Rule 8: `history-docs.test.mjs` matches `scripts/*.test.mjs`; the API test is in the chromium project's `api/` folder and E4 in `e2e/floor/`, both inside their projects' globs and tagged for the default run.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 25.2 adds the History page (`#/history`, a header link between Documents and Usage) with Decisions and Incidents tabs, filters held in the address, 25-row paging, and the two owner-scoped reads `GET /api/v1/history/decisions` and `/incidents` (`Web.History`, forwarded from `Web.Api`) over four new `Ownership.Rows` kinds. It reuses the rail's decision row, the extracted `IncidentStateChip`, `headlineOf` and the shared trace link. It also lands the More to try item (thirteenth, in "Usage and history"), `Demo.Features` `history`, the README bullet, the EXPERIENCE item, the spine rows, and DW-1102's spacing-only header fit K.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `HISTORYPAGE`, `HISTORYDECISIONS`, `HistoryDecisions`, `HistoryIncidents` and the four `Statement` kinds.
- `src/ocutalon/cls/OcuTalon/Web/History.cls` (new) and `Web/Api.cls` (one Map): the routes.
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls`: `history` after `usage`.
- `web/src/app/history/*`, `api/history-types.ts`, `api/api-client.ts`, `app.config.ts`, `settings/settings-view.ts`: the page, view and client.
- `web/src/app/incidents/incident-state-chip.ts` (new), `incident-card.ts`, `incident-view.ts`, `rail/rail-view.ts`, `rail/status-rail.ts`: the extraction and exports.
- `web/src/app/header/header-nav.ts` and `header.ts`: the History link and fit K.
- `web/src/app/guide/more-to-try*.ts`: the history item and the generalized link branch.
- Tests: `Test/Data/OwnershipHistory`, `Test/Web/HistoryApi`, `Test/Data/Ownership`, `Test/Demo/Features`, `web/e2e/api/history.spec.ts`, `web/e2e/history/history.spec.ts`, `web/e2e/support/*`, the shared e2e specs and the node tests listed in the diff.
- `README.md`, `EXPERIENCE.md`, `ARCHITECTURE-SPINE.md`: the story's own rows and entries.

**Review.** 36 findings: high 0, medium 3, low 22, false 11. Patches applied (6 entries): the page-turn focus move (medium), the incident `fallback` assertion (medium), H3's wait for rows (medium), H6's wait for rows (low), and the missing `mutation:` lines for AC5 and DW-1102 (low). Nothing deferred. Every rejected finding and its reason is in the Review Triage Log.

**Follow-up review recommended: true.** Three medium entries were patched. The unverified risk: the page-turn focus move is proven in Chromium only (`history.spec.ts` runs in the chromium project), not in Firefox or WebKit.

**Verification.**
- Slot-C classes through the warm stack: `OwnershipHistory`, `HistoryApi`, `Test.Data.Ownership`, `Test.Demo.Features`, `DocumentsApi`, `OwnershipUsage` and `UsageApi` passed (the 37.2 siblings included).
- Node: the seven `(loop)` test files (203 tests) and `npm --prefix web test` (1883) pass. `npm run lint` and `npm run build` pass; the build keeps its existing budget warnings.
- e2e on fresh lane-C stacks after the last patch: `api/history.spec.ts` (part 2/20, 10 passed), `history/history.spec.ts` (part 14/20, 11 passed), `live floor` (107 passed in Chromium, Firefox and WebKit, G4 and G5 unedited). `frame`, `documents`, `settings` and `more-to-try` passed in the implement pass and are unchanged since (no patch touched a file they cover).
- `bash ci/checks.sh`: all scripts passed. `lint_spine.py`: the baseline 10 low `placeholder` findings, nothing new.
- Mutations: each recorded in `## Verification`, each observed red and reverted byte-identical.

**Residual risks and notes.**
- Decided in-stage 12 (implement): on build 154 an empty bound value is NULL in dynamic SQL, so the filter statements test `? IS NULL` where the spec text said `? = ''`.
- The spine memlog append (`memlog.py append --type decision`, Rule 20) did not run: the spine folder has no `.memlog.md`. The lead records the decision.
- DW-941 (a decision no model call served has no channel) is unchanged and stays with the burn-down.

**Rework 1 (CI red, run 42966931010 on 284e8904).** The History link made U1 and U8 of `usage.spec.ts` stale (they pinned the header links without History). The specs that pin the header links (U1, U8, D13, H1, F3, S1) now read `web/e2e/support/header-nav.ts` (new; `NAV_LINKS_ADMIN` is `NAV_LINKS_USER` with Settings after Chat), and U1's "no History link" check is scoped to the Usage page (`main.usage`, count 1 first). The header is unchanged; U8's 305px case holds four visible links inside the window. Review of this pass: 13 findings, high 0, medium 2 (one root cause, patched), low 9; patches 8 entries, no deferral, rejected rows carry their reasons in the Review Triage Log. Follow-up review recommended: false (no high patched). Verification: the lane-C parts and node run in `## Verification`, `npm --prefix web test` 1896 passed, `npm --prefix web run lint` passed, mutation observed red and reverted identical.

**Rework 2 (CI red, run 42981966109 on f21137d1, H12).** Measured cause: the CDK live region takes a text 100 ms after it is handed one, so a Retry answered inside that window left the region empty at the answer and holding "Couldn't load your history." 1.5 s later, and a page-wide `getByText` counted it. A stale error was also spoken after the answer. Fix: `HistoryPage.arrived()` withdraws the failure's announcement through the new, additive `Announcer.retract` (and `AnnounceQueue.retract`); H9, H12 and H13 assert the failed region `[data-part="history-failed"]`; H9 and H12 also assert the live region no longer holds the error; H15 pins the queued-behind-the-gap case. Files: `web/src/app/shared/announce-queue.ts`, `announcer.ts`, `web/src/app/history/history-page.ts`, `web/e2e/history/history.spec.ts`, `web/scripts/announce-queue.test.mjs`, `announce-focus-sources.test.mjs`.
- Review: 20 findings, high 0, medium 7 (patched, three root causes: the emptying branch's mutation line, H15's precondition and exact count, one shared root), low 10, false 3. Patches applied: H15 waits for the first announcement and asserts exactly one, the emptying branch's mutation line (observed red), the test header. Deferred: none. Rejected, with reasons: in the Review Triage Log (a joined or counted announcement is a documented limit, `wontfix-accepted`).
- Follow-up review recommended: false (no high patched).
- Verification: `live sign-in --part 13/20` green twice on fresh lane-C stacks (15 passed each) after the last patch, `npm --prefix web test` (1910 passed), `npm --prefix web run lint`; the mutation lines are in Rework 2 under Verification. Tag `e25s2r2` torn down.
- Residual risks: H15 needs the Retry answered inside the 1 s gap after the first error (about 200 ms locally), and fails red, never green, on a very slow runner; a failure spoken joined with other texts before an answer is not withdrawn; `UsagePage` has the same announce-on-failure pattern and is untouched.

Status: done
Blocking condition: none
