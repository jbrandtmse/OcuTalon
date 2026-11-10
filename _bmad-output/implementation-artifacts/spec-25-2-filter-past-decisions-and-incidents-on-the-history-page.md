---
title: 'Story 25.2: Filter past decisions and incidents on the History page'
type: 'feature'
created: '2026-11-10'
status: 'ready-for-dev'
baseline_revision: 'ddedbd6aedef926ff039e1f86b11418cd765f9f1'
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
- [ ] Task 0 (implement, before any edit): re-check this spec against Story 37.2 as merged on the feature branch: the header nav, the `Ownership.Rows` kinds, the REST and ownership spine rows, the More to try registry, `Demo/Features`, README and EXPERIENCE. Record any drift in the Spec Change Log. Also re-read `sprint-status.yaml` for 37-2 `done` and run `git log --oneline --grep "37.2"` on the base.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the kinds `historyDecisions`, `historyDecisionTotal`, `historyIncidents` and `historyIncidentTotal` to `Statement`, appended after 37.2's `usage` block. Add `HistoryDecisions(sessionRef, outcome, channel, day, fallback, page, Output pages, Output sc)` and `HistoryIncidents(sessionRef, page, Output pages, Output sc)`, documented in the class doc beside 37.2's `Usage` line.
  - The decision WHERE is: `d.OwnerRef = ? AND d.Kind = 'decide' AND (? = '' OR (d.Fallback = 1 AND ? = 'tellnow') OR (d.Fallback = 0 AND d.Outcome = ?)) AND (? = '' OR d.Fallback = ?) AND (? = '' OR (d.RecordedAt >= ? AND d.RecordedAt < ?)) AND (? = '' OR EXISTS (SELECT 1 FROM OcuTalon_Bridge_Data.Usage u WHERE u.OwnerRef = d.OwnerRef AND u.DecisionRef = d.Ref AND u.Channel = ?))`.
  - The page form adds `ORDER BY d.RecordedAt DESC, d.ID DESC LIMIT ? OFFSET ?`.
  - Incidents use `INCIDENTVISIBLE` with `ORDER BY i.NoticedAt DESC, i.ID DESC LIMIT ? OFFSET ?`.
  - The page size is the class parameter `HISTORYPAGE = 25`.
  - `day` becomes a window through `Data.Time.FromLocal`. An unreadable `day` is an error status (the route validates first).
  -- Rationale: the one read path (AD-4, AD-13), the existing allow-listed prepare, the same shape as 37.2's `Usage`. `LIMIT ? OFFSET ?` with binds was measured to work on build 154 (Design Notes).
- [ ] `src/ocutalon/cls/OcuTalon/Web/History.cls` (new) -- `Extends OcuTalon.Web.Api`. Its UrlMap has `GET /decisions` → `Decisions` and `GET /incidents` → `Incidents`. It validates exactly per the I/O matrix and answers a bad value with `..Fail(404,"not_found",..#MESSAGENOTFOUND)`. It reads through Ownership with `SessionRef(.sc)` and writes the allow-listed keys only.
  - Decisions: `Live.Payload.Decision.FromRow` → `PayloadObject` → `TraceLink.Viewer`/`Add`, then a copy of only the allow-listed keys, plus `channel` from `Ownership.DecisionChannel`.
  - Incidents: built directly from the row. `itemNoun` has the same shape as `Live.Payload.Part.ItemNoun`. `traceUrl` is `TraceLink.Url(TraceHeaderId, $Namespace, , , .viewer)`. `summary` is `Watch.Summary.Text(ref, "web", .sc)` when `Summary '= ""`, and a failed render gives `""`.
  -- Rationale: the 37.2 forwarding pattern; one trace builder (AD-26).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- add `<Map Prefix="/v1/history" Forward="OcuTalon.Web.History"/>` after 37.2's `/v1/usage` map, and append one header doc bullet after 37.2's usage bullet.
- [ ] `web/src/app/api/history-types.ts` (new) and `web/src/app/api/api-client.ts` -- add `historyDecisions(filters: HistoryFilters & {page})` and `historyIncidents(page)`. They send only the set parameters, and their result types are `HistoryDecisionsResponse` and `HistoryIncidentsResponse`. Append them after 37.2's `usage()`.
- [ ] `web/src/app/history/history-view.ts` (new, pure, erasable TS, type-only imports plus the imported `*_TEXTS`, the way 37.2's `usage-view.ts` imports shared labels) -- holds:
  - `HISTORY_TEXTS`.
  - `paramsOf(queryParamMap-like)` → `{tab, outcome, channel, day, fallback, page}`, which drops invalid values.
  - `queryOf(state)`, which writes only the set values (`tab` only for `incidents`, `page` only when above 1).
  - `OUTCOMES`, `CHANNELS` (the Msg.Enum order, with `USAGE_TEXTS.channels` labels), `FALLBACKS`.
  - `emptyText(state)`, `pageText(page, pages)`, `incidentTimes(row, when)` and `summaryLines(text)`.
- [ ] `web/src/app/history/history-page.ts` (new) -- `HistoryPage`, OnPush, mirroring 37.2's `UsagePage` for load, `asked` and `failed`/Retry, with no loading text. Its structure:
  - `<main class="history" tabindex="-1">`, a hidden `<h1>` "History", and a `role="tablist"` labelled by the h1. It has two `role="tab"` buttons (`aria-selected`, `aria-controls`, roving tabindex, Arrow keys through `nextTab`) and two `role="tabpanel"`, each with a hidden `h2`.
  - Decisions panel: native `<select>`s Outcome, Channel and Fallback, a native `<input type="date">` Date, each with `<label for>`, and "Clear filters" when any filter is set. Then a `<ul>` of `<app-decision-row>` fed by the exported `decisionRow(payload, formatAt(now))`, with the channel label inserted as meta part 2 when set, tracked by `ref`. Each row has `min-height: var(--space-10)`.
  - Incidents panel: a `<ul>` of rows. Each row has the state chip and Fallback flag first, the headline (`headlineOf`), the "Noticed …" / "Closed …" times, the summary lines (or the no-summary text) and `<app-trace-link>` when `traceUrl` is set.
  - A pager `<nav aria-label>` with Previous page, "Page n of N" and Next page, never shown when there is a single page.
  - A filter, tab or page change navigates with `queryParams` (`replaceUrl:false` for user changes, so Back works; `true` when it corrects an invalid or past-the-end value). A filter change resets `page`, and a tab change drops the decision filters' `page`.
  -- Rationale: UX-DR127/129/130/147; extend, don't copy.
- [ ] `web/src/app/incidents/incident-state-chip.ts` (new) and `web/src/app/incidents/incident-card.ts` -- extract the inline chip span and its `.chip*` CSS into `IncidentStateChip` (`[chip]`, `[text]`), rendering the same span and classes. The card uses it, and nothing else in the card changes. In `incident-view.ts`, export `stateOf` and `headlineOf` with no behaviour change. -- Rationale: Rule 2 (no copied chip CSS).
- [ ] `web/src/app/rail/rail-view.ts` and `web/src/app/rail/status-rail.ts` -- export `decisionRow` and `formatAt` with no behaviour change.
- [ ] `web/src/app/app.config.ts` and `web/src/app/settings/settings-view.ts` -- add the route `{ path: 'history', component: HistoryPage, title: HISTORY_TEXTS.title }` before 37.2's `usage` route, and give `pageOf` a `'history'` branch for `/history`.
- [ ] `web/src/app/header/header-nav.ts` -- add the `History` link (`routerLink="/history"`, `aria-current` from `page.page() === 'history'`) between Documents and Usage (EXPERIENCE :77 order). Update 37.2's doc comment and `header.ts`'s "four navigation links" comment to five.
- [ ] `web/src/app/guide/more-to-try-view.ts` and `more-to-try.ts` -- add `MORE_TO_TRY_TEXTS.items.history` (PUBLIC TEXT), the action `'history'`, and the registry entry `{ id: 'history', …, action: 'history', group: 'Safety and settings' }` (the proposed group; a different Planner ruling at the spec gate replaces it, recorded in the Spec Change Log) `` appended last. Extend 37.2's usage link branch so it serves both page links (one `<a>`, path from the action) and add `case 'history'` to the navigate switch. The header comment's count word follows the registry.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Ids` appends `history` unconditionally after `usage`. Update the doc line so it no longer says "usage … last".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipHistory.cls` (new; extends `OcuTalon.Test.Bridge.ZoneCase` like 37.2's `OwnershipUsage`) -- tests every I/O matrix row at the Ownership level:
  - each filter, alone and combined;
  - outcome `tellnow` with a fallback row whose stored Outcome is not `tellnow`;
  - channel through the usage rows, and a row with no usage row;
  - the day edges in two zones;
  - paging (26 rows → page 2 holds 1; `pages` 2; past the end empty);
  - order;
  - isolation (B, eval, instance, no owner, un-noticed incident; an instance incident visible locally only through a watching `Check`, and invisible with `onlineDemo` 1);
  - the refusals.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- add the four kinds to `TestIsolationEveryRowKind`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/HistoryApi.cls` (new; mirrors 37.2's `UsageApi`) -- covers:
  - Dispatch: exactly one Map for `/v1/history`; `/v1/historyx` is no route; History's routes are `GET /decisions` and `GET /incidents`; POST is no route; 403 `no_role` without the role.
  - Every bad value in the matrix → 404 with the exact body.
  - Shape: the exact top keys, and every item's keys within the allow-list (`DECISIONKEYS`, `INCIDENTKEYS`). The body holds no `SessionRef`, `$Username`, fixture tag, `"id"`, `ownerRef`, `itemId`, `traceHeaderId` or `kind`.
  - Isolation, the summary text, and no session → 500.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls` -- add `,history` after `usage` in every `TestIds` expectation. `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls` -- no edit when, as at 37.2, its Map pin filters on `/v1/documents`; otherwise apply 37.2's URL filter.
- [ ] `web/e2e/api/history.spec.ts` (new; real HTTP, mirrors 37.2's `api/usage.spec.ts`) -- the SECURITY tests listed in Design Notes. Seed through `irisScript` with `Test.Data.Fixture` `Decision`, `Usage` and `Incident` (with a stored `Summary`) and clean up in `finally`. Extend `support/iris.ts`'s `seedDecision(s)`/`seedIncident` where they fit, and otherwise add `web/e2e/support/history.ts`.
- [ ] `web/e2e/history/history.spec.ts` (new) -- covers:
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
- [ ] Shared tests (Rule 19) -- update these:
  - `frame.spec.ts`: the Tab order gains History before Usage, and 37.2's 1024px test becomes five links. Measure it first; see Design Notes → HEADER RISK.
  - `settings.spec.ts:68` → `['Chat','Settings','Documents','History','Usage']`; `documents.spec.ts:338` → `['Chat','Documents','History','Usage']`.
  - `more-to-try.spec.ts`: `ITEMS`, `controlOf`, K3's href for the history item, and the new **K28** "the link of the History item opens the History page".
  - `settings-view.test.mjs`: `pageOf` `history` cases, the same set as 37.2's usage cases.
  - `more-to-try-view.test.mjs`: `RULED`, `GROUP_OF` gets `history`, and an assertion that history is last.
  - `more-to-try-sources.test.mjs`: the counts follow the extended link branch.
  - `ux-strings.test.mjs`: `IMPORTED` gets `['history/history-view.ts', ['HISTORY_TEXTS']]`, the `ux`/`ac` sources, and a `ruled` block "Story 25.2 rulings at the spec gate".
  - `floor-sources.test.mjs`: the history page in `KEY_HANDLERS`, the arrow list and bindings, the `tabs` allowed map (reason: UX-DR130 Decisions/Incidents tabs), and the scroller list only if it adds a scroller.
  - `web/scripts/history-view.test.mjs` (new): `paramsOf`/`queryOf` round trips, invalid values dropped, `emptyText`, `pageText`.
- [ ] `README.md` -- append the History bullet last in "New since 1.0.0" and update :40's count word. `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- add the More to try entry under "Safety and settings" (or the heading the Planner rules), with the next item number, plus "Item N's control is a link to the History page.", and update the "There are … items" count word. Both carry `[ADDED <date>, Story 25.2, Contest Planner ruling …]`.
- [ ] `ARCHITECTURE-SPINE.md` -- append the three rows in Design Notes → SPINE ROWS after 37.2's rows. Refresh `updated:`, run `memlog.py append --type decision` and lint (Rule 20).

**Acceptance Criteria:**
- Given a signed-in user on any page, when they press History in the header navigation, then `#/history` opens titled "History · OcuTalon", with History marked `aria-current="page"` between Documents and Usage, and the tabs Decisions and Incidents are read from `/api/v1/history/*`, which read only OcuTalon's and the bridge's tables (Decision, Usage and Incident, plus Turn and BackgroundCheck through the reused `FromRow` and `INCIDENTVISIBLE`) through `Ownership`, never a production message. The spine's REST and ownership tables carry this story's three rows.
- Given the Decisions tab with fixture decisions across outcomes, channels, days and fallback, when the user sets any combination of the four filters, then only matching decisions show, newest first, 25 to a page with Previous/Next, each row at least 40px with the outcome chip first. The address holds the filters, so a reload or a pasted link shows the same list, and with no match the panel reads "No decisions match these filters.".
- Given a decision row, when the user presses its button, then the reasons expand in place (`aria-expanded="true"`, no dialog), and its trace link, a sibling of the button, opens the decision's trace target (the rail's, built by `TraceLink`) in a new tab and says so.
- Given the Incidents tab, when it loads, then each incident shows its state chip, headline, noticed (and closed) time, its stored 23.6 summary as text (or the no-summary text), and a trace link to its diagnosis session.
- Given two signed-in sessions with their own fixture decisions and incidents (plus eval and instance rows), when each reads either tab or route with any filters, then it sees only its own rows (and on a local install the instance incidents of productions it watches), never the other's. The tabs use `aria-selected` and work by keyboard alone.
- Given the History item in More to try, when the user presses its control "Open the History page", then the History page opens. `Demo.Features` lists `history` after `usage`.

## Spec Change Log

- 2026-11-10 (lead, spec gate): Design Notes gained the lead note on DW-941. The PUBLIC TEXT, SECURITY and MORE TO TRY GROUP sections go to the Contest Planner; the rulings are written here before implement.

## Review Triage Log

## Design Notes

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

**Ledger inbox:** no entries are owned by this story.

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

**Lead note at the spec gate (2026-11-10):** Decided in-stage 4's gap is the same root cause as the ledger's DW-941 (routed, owner `burndown`: a decision with no model call has no channel because the bridge `Decision` row has no `Channel`; the fix is a Lane A column). This story neither owns nor closes DW-941 and does not depend on it being decided (it is `routed`, not `decision-pending`); the History page states the gap honestly by leaving such a decision's channel out. If DW-941 lands first, the channel EXISTS clause can switch to the column in a later story.

**HEADER RISK.** Five links at 1024px. 37.2's ruling holds: never hide a link. If the five links do not fit on one line in a header of 64px or less at 1024px (measured in `frame.spec.ts` F3), stop with `## Clarification Needed` and do not restyle the header ad hoc.

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

### PUBLIC TEXT (pending Planner ruling)

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

### SECURITY (pending Planner ruling)

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

### MORE TO TRY GROUP (pending Planner ruling)

Proposed: **"Safety and settings", last (after 37.2's usage item)**. History, like Usage, is a step-6 look-back page reached from the header. Placing it last there is a plain append (the next EXPERIENCE item number). Any other heading would renumber the EXPERIENCE entries after it, including 37.2's (`sources-docs.test.mjs` numbers by panel order).

The alternative is "Incidents and fixes", after "Reject a fix", because the Incidents tab shows the 23.6 summaries. Its cost: Items 2 to 9 become 3 to 10.

The new item adds only its registry row with `group:`, one `GROUP_OF` line, and its EXPERIENCE entry. E2E: **K28**.

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

**Mutations to record (Rule 19), one per AC, each observed red and reverted byte-identical:**
- the `historyDecisions` owner check made `OR 1=1` -> `OwnershipHistory` isolation and `api/history.spec.ts` (3) red;
- the outcome clause's fallback branch removed -> the outcome `tellnow` test red;
- `queryOf` not writing `outcome` -> the `history.spec.ts` reload test red;
- the DecisionRow replaced by plain text with no button -> the disclosure test red;
- `summary` not rendered -> the incidents test red;
- the History link moved after Usage -> `frame.spec.ts` Tab order red;
- the registry entry's action changed -> K28 red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned to the spec gate against Story 37.2 at OCT-epic37 `7ef82a46` (not merged). The implement stage waits for 37.2's merge (`story_waits_stories: {"25.2": "37.2"}`) and starts with Task 0's re-check. The three sections for the Planner are under Design Notes: PUBLIC TEXT, SECURITY and MORE TO TRY GROUP (proposed: "Safety and settings", last). Decided in-stage item 4 is flagged for the Planner: a decision that no model call served has no recorded channel.
