---
title: 'Story 37.2: See tokens and cost over time on the Usage page'
type: 'feature'
created: '2026-11-09'
status: 'in-progress'
baseline_revision: '51ce312dc31c7f5111a2734b71446b18434d6500'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-37-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A user cannot see what OcuTalon costs over time, nor spot a model request close to the 100,000-token size limit. The usage rows exist (one per agent turn, AD-20), but no page or route reads them by range (FR-52, step 6).

**Approach:** Add one owner-scoped read, `GET /api/v1/usage?days=1|7|30`, that sums the caller's own session's usage rows into buckets by instance-zone day, agent, channel, model and the estimated flag, through a new `Ownership.Rows` kind. Add a Usage page, reached from a new Usage entry in the header navigation, that groups those buckets by day, agent, channel or model in an inline SVG chart and a table. Each day also shows its largest request against the limit. Add this story's own spine rows, one More to try item and one README line.

## Boundaries & Constraints

**Always:**
- Every read goes through `OcuTalon.Data.Ownership` (AD-4, AD-13). The `SessionRef` comes from `Ownership.SessionRef(.sc)`, never from the request. The SQL is one fixed text in `Statement` with the owner check in `WHERE`. Rows of owner `eval` or `instance` are never read.
- Totals are sums of the rows, built by the existing `Ownership.Sum`, so they equal what `TurnCost` and `RunCost` total for the same rows. A NULL `CostUSD` counts as 0, as `Sum` counts it.
- The day boundary is midnight in the instance zone, through `OcuTalon.Data.Time` (`ToLocal`, `FromLocal`), the same day as `Ownership.HeartbeatToday` and the daily cap's (AD-18, AD-20).
- The chart is inline SVG in Angular, with no new dependency. It is drawn in the `--chart-tokens`, `--chart-cost` and `--usage-chart-gridline` tokens, which already exist in light and dark.
- Visible strings are exactly the ones `## Design Notes` → PUBLIC TEXT records, after the Planner's ruling. The tokens and cost are described per turn and per decision, never per step.
- Changes to the contended files are plain-union additive blocks, except the ones listed under Design Notes → CONTENDED CHANGES.
- Lane B files only (AD-29). `OcuTalon.Bridge.Data.Usage` and every `src/bridge/**` class are read, never edited (U-177).

**Never:**
- No History entry, history read, file upload route, private file table or Roles rows. Those belong to Stories 25.2 to 25.5 and 37.1.
- No new role, grant, privilege, resource, stored table, stored column, index, live-event type or retention change. Never widen `OcuTalonUser`.
- No `%Prepare` outside `Ownership.Rows`, no embedded SQL and no `%ExecDirect`. `Bridge.Usage.Totals` and `Bridge.Budget` sums are not called from the web.
- No `SessionRef`, owner or user name accepted from the client. No database row id in a response.
- No chart library. No test deleted, skipped, tagged off or shortened.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Read, default range | Signed-in user (OcuTalonUser), `GET /api/v1/usage` | 200 `{"days": [7 local dates, oldest first, today last], "limit": 100000, "buckets": [...]}`. Each bucket is `{"day","agent","channel","model","estimated","inputTokens","outputTokens","cacheReadTokens","cacheWriteTokens","costUSD","largestRequestTokens"}`, one per distinct (day, agent, channel, model, estimated) of the session's rows from the first instant of the first day up to the first instant of tomorrow | No error expected |
| Range values | `days=1`, `7` or `30` | 1 is today; 7 and 30 are today and the 6 or 29 days before | No error expected |
| Bad range | `days=5`, `days=abc`, `days=` | Nothing is read | 404 `not_found`, as the notes route answers a bad `day` (Api.cls `Notes`) |
| Signed out | No CSP session | — | 401 `signed_out` (ApiBase) |
| No role | Signed in without OcuTalonUser | — | 403 `no_role` (OnPreDispatch) |
| Other owners | Rows of another session, `eval`, `instance` or no owner | Never in any bucket | — |
| Day edge | Rows at instance-zone `23:59:59` of day D and `00:00:00` of day D+1 | In two buckets, days D and D+1. A row before the first day's midnight is left out | — |
| Retry runner | Agent `ChatAgentRetry` (also `TriageAgentRetry`, `DiagnosisAgentRetry`) | The bucket keeps the stored agent; the page groups it under its agent ("Chat agent") | — |
| Compaction | Agent `compaction`, `Estimated` 1 | Its own bucket, `estimated: true`; the page shows "Chat summaries" with the estimated marker [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] | — |
| Null cost | Row with no `CostUSD` (model without a price) | Counts as 0 in `costUSD` | — |
| Empty range | No rows in range | 200 with `buckets: []`; the page shows "No model use in this period." and no chart or table | — |
| Failed read | `SessionRef` or `Rows` error | — | 500 `server_error` (`..ServerError(sc)`); the page shows its error text and Retry |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- READ-ONLY (Lane A). Table `OcuTalon_Bridge_Data.Usage`. Properties: `Agent`, `Channel`, `Model`, `OwnerRef`, `InputTokens` (already includes cache read and cache write), `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens`, `LargestRequestTokens` :52 (an estimate, S4), `CostUSD` %Numeric(6) :55 (priced at write time, NULL without a price), `Estimated` :58, and `RecordedAt` %String UTC `YYYY-MM-DDThh:mm:ssZ` :61. Only `OwnerRefIndex` exists; there is no `RecordedAt` index. The compaction row is `FromEstimate` (:146, `Agent="compaction"`, `Estimated=1`).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:152` -- `Parameter MAXREQUESTTOKENS = 100000`. The route reads it for `limit`, never a literal.
- `src/ocutalon/cls/OcuTalon/Production.cls:28-47` -- the agent values: `TriageAgent`, `DiagnosisAgent`, `ChatAgent` and their `…Retry` items. `Bridge/Msg/Enum.cls:24` -- the channel values: `web,phone,mailbox,telegram,email,webhook,slack,system,heartbeat`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `Rows` :949 (`binds`: `o` owner, `a` the next arg; it refuses an empty, `eval` or `instance` owner). `Statement` :1001-1210, one `If kind = …` block per kind. Sibling kind `heartbeatUsage` :1052 (`OwnerRef = ? AND Channel = 'heartbeat' AND RecordedAt >= ? AND RecordedAt < ?`). `HeartbeatToday` :132 (the local-day bounds through `Data.Time`). `RunCost` :112 and `Sum` :182 (a Private method that sums the four token kinds and the cost). `SessionRef` :210. The class doc comment :1-30 lists the reads.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- `NowUtc` :19, `ToLocal` :55, `FromLocal` :71 (the only local-to-UTC converter).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- the UrlMap :218-255 (`<Map Prefix="/v1/documents" Forward="OcuTalon.Web.Documents"/>` :255), the route doc comment ~:85, `OnPreDispatch` :271, `Fail` :1339, and `Notes` :1776 (404 for a bad `day`).
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls` -- the forwarded-route sibling: `Extends OcuTalon.Web.Api`, its own UrlMap, and `List()` :76 (SessionRef, then Ownership, then `..ServerError(sc)`, then `%response.ContentType = ..#CONTENTTYPE`, then `Write ….%ToJSON()`).
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Ids(has)` builds `guide.features`; always-on ids are added on one line. `Test/Demo/Features.cls` `TestIds` :49-60 pins the output.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:160` -- `Usage(decisionRef, ownerRef, fields)` seeds one row (any field can be overridden); `Clean(decisionRef)` removes it.
- `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipMemories.cls` -- the sibling for a new kind's test class (isolation :45, refusals through `Test.Data.OwnershipProbe` :72, bounds :115). `Test/Web/DocumentsApi.cls` is the sibling for a forwarded route's unit test (stand-in request and response).
- `docker/tests/test-class-rules.sh:51-53` -- the allow-list for unchecked prepares (`Ownership:Rows`). A new kind needs no change.
- `web/src/app/app.config.ts:20-24` -- routes (hash routing). A new page goes before `'**'`.
- `web/src/app/settings/settings-view.ts:138-144` -- `pageOf()` returns `'settings' | 'documents' | 'chat'`. `:77` holds `models.agents` (`'Triage agent'`, `'Diagnosis agent'`, `'Chat agent'`), which are shipped strings to import. `header/current-page.ts:25` feeds `aria-current`.
- `web/src/app/header/header-nav.ts:20-26` -- the `<nav aria-label="Pages">` links: Chat, Settings (admins), Documents. `header/header.ts:84-88,303-310` -- the drawer band (1024-1279px), where the header must stay on one line.
- `web/src/app/documents/documents-view.ts` + `documents-page.ts` -- the page sibling: a framework-free `*_TEXTS` and pure-function module, an OnPush component, `<main tabindex="-1">`, an `h1`, regions with `h2`, and a `loaded` flag that gates the empty text.
- `web/src/app/chat/decision-view.ts:23-32,72-92` -- `formatCost` (the "<$0.0001" and 4/3/2 rule) and `formatTokens` (separators), plus the shipped labels `rowTokens` 'Tokens', `rowCost` 'Cost', `tokenInput` 'Input', `tokenOutput` 'Output (includes thinking)', `tokenCacheRead` 'Cache read' and `tokenCacheWrite` 'Cache write'. Import these, never copy them.
- `web/src/app/api/api-client.ts:34,173-176,259-262` -- `BASE`, the `documents()` GET and the `{ params }` pattern. `api/heartbeat-types.ts` is the per-area types file sibling.
- `web/src/styles/tokens.css:38-39,561-563,602-603,784-786,825-826,1007-1009` -- the chart tokens, light and dark. The file is generated from DESIGN.md; never hand-edit it.
- `web/src/app/guide/more-to-try-view.ts` -- `MoreToTryAction` :81, `MoreToTryItem` (with `group?`) :84-92, `MORE_TO_TRY_ITEMS` :96-103 (8 on this branch), the "eight" in the header :2-3 and :94, and `MORE_TO_TRY_TEXTS.items` :21-75. `guide/more-to-try.ts:72-73` renders the `documents` link and `:242-244` handles its press.
- `web/scripts/` -- node unit tests: `more-to-try-view.test.mjs` (`RULED` :33-85, `ACTION_OF` :91, `GROUP_OF` :94), `settings-view.test.mjs:88-102` (`pageOf`), `ux-strings.test.mjs:55-72` (every `*_TEXTS` module, each string with its source) and `decision-view.test.mjs` (the format pins).
- `web/e2e/api/memory.spec.ts:225` -- the real-HTTP sibling: `signInOverHttp`, the LIVE user plus a second session as PANEL (`playwright.request.newContext`), and assertions on its own rows only. `web/e2e/support/iris.ts` (`irisScript` :105, `fixtureUser` :71) and `support/memory.ts:61` (`sessionRefOfUser`).
- `web/e2e/support/scan.ts` -- `scanContrast` and `scanNames` (light and dark).
- `web/playwright.config.ts:46-96` -- new folders `e2e/api/` and `e2e/usage/` join the `chromium` project, which is the `live:sign-in` unit in group `shards-10`.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- the REST table ends at :1588. The "Cross-area classes and APIs" table is at :1363-1428 (columns `| Class or API | Lane | Built in |`). The spine has no header navigation list (E3).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- Add three self-contained additive blocks, and nothing else:
  - in `Statement`, kind `usage` with `binds = "oaa"` and the text `SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND RecordedAt >= ? AND RecordedAt < ? ORDER BY RecordedAt, ID`;
  - a public `ClassMethod Usage(sessionRef As %String, days As %Integer, Output sc As %Status) As %DynamicObject` that builds the local dates (today minus `days-1` through today) and their UTC bounds through `Data.Time`. It reads `Rows("usage", sessionRef, .sc, from, to)`, groups the rows by (local date of `RecordedAt`, `Agent`, `Channel`, `Model`, `Estimated`), and sums each bucket through `..Sum(list, bucket)`. `largestRequestTokens` is the bucket's maximum. It returns `{"days":[…],"buckets":[…]}`, or `{}` plus an error status;
  - one line in the class doc comment naming the read.
  - Do not refactor `HeartbeatToday` (see Rule 2 below).
- `src/ocutalon/cls/OcuTalon/Web/Usage.cls` (new) -- `Extends OcuTalon.Web.Api`, with a UrlMap `<Route Url="" Method="GET" Call="Read"/>`. `Read()` takes `days` (`%request.Get("days")`, 7 when absent). A value other than 1, 7 or 30 is `..Fail(404, "not_found", …)`, with the not-found message the notes route uses. Then `Ownership.SessionRef(.sc)` and then `Ownership.Usage`; either error is `..ServerError(sc)`. It sets `limit` from `##class(OcuTalon.Bridge.Process.Decide).#MAXREQUESTTOKENS` and writes the JSON with `..#CONTENTTYPE`. The doc comment states the contract (no history).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- Add one UrlMap line, `<Map Prefix="/v1/usage" Forward="OcuTalon.Web.Usage"/>`, next to the documents Map, and one doc-comment line in the routes list. These are additive only.
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- Add `usage` as its own line, after `sources`: always on, because the page ships in this package. Update the id-list comment. `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls` -- Every expected id list gains `,usage` last; the "the eight" message becomes "the nine".
- `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipUsage.cls` (new; shard `lane-b@Contract,Core,Data,Live`, group `image`) -- Seed rows with `Test.Data.Fixture.Usage` across 3 local days, the agents `TriageAgent`, `ChatAgent`, `ChatAgentRetry` and `compaction` (`Estimated` 1), the channels `web`, `phone` and `telegram`, two models, one NULL cost, and the day-edge pair at local `23:59:59` and `00:00:00`, with times built by `Data.Time.FromLocal`. The tests:
  - TestBuckets: each bucket equals the hand sum of its rows, the total over buckets equals `RunCost` over the same window, and the largest is the maximum.
  - TestRange: rows outside the window are left out, and the day edge splits.
  - TestIsolation: a second session's, `eval`'s and `instance`'s rows never appear, both ways.
  - TestRefusals: `Rows` kind `usage` with an empty, `eval` or `instance` owner, through `OwnershipProbe`.
  - TestEmpty: `buckets` is `[]` and `days` still lists the range.
  - `Clean` everything in `OnAfterOneTest`.
- `src/ocutalon/cls/OcuTalon/Test/Web/UsageApi.cls` (new; shard `lane-b@rest`, group `shards-6`) -- Follow `Test.Web.DocumentsApi`'s stand-ins. TestDispatch: the forwarded GET reaches `Read`. TestDays: absent is 7, 1, 7 and 30 are accepted, and 0, 5, 31, `abc` and an empty value are 404 `not_found`. TestShape: the keys, `limit` = `Decide`'s parameter, and a KEY ALLOW-LIST assertion: the body's top-level keys are exactly `days`, `limit`, `buckets`, and every bucket's keys are exactly the eleven listed in the I/O matrix, so no ref, row id, user name or `SessionRef` can appear [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md].
- `web/src/app/api/usage-types.ts` (new) + `web/src/app/api/api-client.ts` -- Add the `UsageResponse` and `UsageBucket` types, and `usage(days: 1 | 7 | 30)` → `GET ${BASE}/usage` with `{ params: { days } }`.
- `web/src/app/usage/usage-view.ts` (new, framework-free; it imports only the framework-free `chat/decision-view.ts` and `settings/settings-view.ts`) -- It holds:
  - `USAGE_TEXTS`, exactly the PUBLIC TEXT strings;
  - `RANGES` = 1, 7, 30, with 7 the default;
  - `GROUPINGS` = day, agent, channel, model;
  - `groupRows(response, grouping)`, which returns one row per group with the four token kinds, `tokens` (Input + Output), `costUSD`, `estimated` (all its buckets estimated) and `includesEstimates` (some). Day lists every date of `days` in order, with 0s for days without use. Agent maps the `…Retry` agents to their agent, `compaction` to "Chat summaries", and an unknown value to itself. Channel uses the channel names. Model uses the stored id. Agent, channel and model are sorted by label, and show only values that have rows in the range: no zero rows for an agent, channel or model the install did not use (Day alone keeps every date, with 0s) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md];
  - `largestByDay(response)`: the days with use, each with the maximum `largestRequestTokens`;
  - `dayLabel(date, today)`: short date per UX "Dates" ("Nov 9", with the year only when it differs), formatted in UTC from the local date string so the browser zone cannot shift it;
  - `chartGeometry(rows, width, height)`: one bar and one point per row, on separate token and cost scales.
- `web/src/app/usage/usage-page.ts` (new) -- An OnPush standalone component, following `documents-page.ts`:
  - `<main tabindex="-1">` with `h1` "Usage";
  - the controls: a native `<select>` labelled "Range" (`<label for>`), and a radio group `<fieldset><legend>Group by</legend>` with Day, Agent, Channel and Model;
  - region `h2` "Tokens and cost": a `<figure>` with an `aria-hidden` SVG (bars in `--usage-chart-tokens-series`, a cost polyline with point markers in `--usage-chart-cost-series`, gridlines in `--usage-chart-gridline`, direct labels "Tokens" and "Cost" at the series ends), a visible HTML legend (a square swatch and "Tokens", a line-and-dot swatch and "Cost"), then the table. Bars and points carry `data-key`, `data-tokens` and `data-cost`. The table has a row per group with the columns {grouping label}, Input, Output (includes thinking), Cache read, Cache write, Tokens and Cost, numbers in `.tabular`, and the estimated markers as words;
  - region `h2` "Largest request per day": a table with the columns Day and "Largest request (estimated)", each cell "{tokens} of {limit} tokens";
  - the states: the empty text when `buckets` is empty; the error text plus a Retry button on a failed GET; nothing before the first answer;
  - a range change fetches again, and a grouping change regroups with no fetch;
  - below 1024px the layout stacks, the table scrolls in its own region, and the page never scrolls sideways.
- `web/src/app/app.config.ts` -- Add `{ path: 'usage', component: UsagePage, title: USAGE_TEXTS.title }` before `'**'`. `web/src/app/settings/settings-view.ts` `pageOf` -- add `'usage'` for `/usage` and update its doc line. `web/src/app/header/header-nav.ts` -- add `<a class="header-nav-item" routerLink="/usage" …aria-current…>Usage</a>` after Documents, shown to every signed-in user. In `header.ts` the drawer-band comment says "four navigation links", and the spacing is tightened only if the 1024px check fails; nothing is ever hidden.
- `web/src/app/guide/more-to-try-view.ts` + `more-to-try.ts` -- Additive:
  - add `'usage'` to `MoreToTryAction`;
  - add `items.usage` texts and one registry entry `{ id: 'usage', …items.usage, action: 'usage', group: 'Safety and settings' }` last, so it is the LAST item of the Safety and settings group (five items there; no fourth heading) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md];
  - add one `@else if (item.action === 'usage')` link branch `<a routerLink="/usage">`, beside the documents branch, and one `case 'usage'` in `press()`;
  - "eight" becomes "nine" in the header comment :2-3 and :94.
- `README.md` -- Append the PUBLIC TEXT bullet LAST in "New since 1.0.0" (after :52), and change :40 "eight more things to try" to "nine". `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- :245 "eight" becomes "nine"; add item 9's line after :253 in the list's form; :254 also says item 9's control is a link to the Usage page.
- Spine (the path above) -- Add three rows, each marked `[ADDED 2026-11-10, Story 37.2]`, and nothing else:
  - REST table after :1588: "| `GET /api/v1/usage?days=1`, `7` or `30` (7 when absent) | `OcuTalon.Web.Usage`, forwarded from `Web.Api`'s map: the CSP session's own Usage rows (AD-20) through `Ownership.Usage` (`Ownership.Rows` kind `usage`), from the first instant of the instance-zone local date `days - 1` days before today up to the first instant of tomorrow (`Data.Time`), summed by `Ownership.Sum` into buckets by local date, agent, channel, model and `Estimated`: 200 with `days`, `limit` (`Decide`'s `MAXREQUESTTOKENS`) and `buckets`; any other `days` is 404 `not_found`; a failed read is 500 `server_error`; any user with the OcuTalon user role, behind the AD-13 envelope |";
  - Cross-area table after :1428: "| `OcuTalon.Data.Ownership.Usage(sessionRef, days, .sc)` and the `Ownership.Rows` kind `usage` (AD-4, AD-13, AD-20): the session's own `OcuTalon.Bridge.Data.Usage` rows (Lane A's table, read only) of a range of instance-zone days, read by the usage route | B | Story 37.2 |";
  - and "| The header navigation's Usage entry (`web/src/app/header/header-nav.ts`, after Documents, for every signed-in user) and the Usage page (`web/src/app/usage/`, `#/usage`), which reads only `GET /api/v1/usage` | B | Story 37.2 |".
  - Run the lint before and after.
- `web/e2e/support/usage.ts` (new) -- Follow `support/memory.ts`:
  - `seedUsage(user, rows)` calls `Test.Data.Fixture.Usage` through `irisScript`, with `RecordedAt` at local noon of N days ago built by `Data.Time.FromLocal` in the script, and returns the decision refs;
  - `clearUsage(user)` deletes the user's session's Usage rows (the heartbeat card spec's direct-SQL precedent; grep `OcuTalon_Bridge_Data.Usage` under `web/e2e/`);
  - `cleanUsage(refs)`.
- `web/e2e/api/usage.spec.ts` (new; `chromium` project, the `live:sign-in` unit, group `shards-10`) -- Real HTTP, following `api/memory.spec.ts`. It asserts only on its own unique model ids, so other rows change nothing:
  - (i) signed out is 401 `signed_out`;
  - (ii) LIVE (OcuTalonUser only) over `signInOverHttp`: `?days=7` is 200 with its seeded buckets summed exactly, `limit` is 100000, and `days` has 7 entries; `?days=0`, `?days=31`, `?days=abc` and `?days=5` are each 404 `not_found`; and a key allow-list assertion on the 200 body (top level exactly `days`, `limit`, `buckets`; each bucket exactly the eleven matrix keys) proves no ref, row id, user name or SessionRef appears [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md];
  - (iii) a second session (PANEL, its own durable session) with its own seeded rows: neither response holds the other's model ids, and an `eval`-owned row seeded beside them never appears;
  - no admin-only route exists, so there is no 403 case;
  - the rows are removed in `finally`.
- `web/e2e/usage/usage.spec.ts` (new; `chromium`, `live:sign-in`, `shards-10`) -- `clearUsage(LIVE)` then seed (in `beforeEach`), and remove the rows after. The fixtures are rows 1 to 5 days ago across three agents plus `ChatAgentRetry` and `compaction`, the channels `web`, `phone` and `telegram`, two unique models, and distinct largest requests. The cases:
  - U1: open from the nav as LIVE; the title, `aria-current`, the nav list `['Chat', 'Documents', 'Usage']` and no History.
  - U2: for each grouping, every table row equals the fixture sum written out in the test, the totals add up, and the chart's bars and points equal the table's rows (count, `data-key`, `data-tokens`, `data-cost`).
  - U3: Chat summaries (the compaction rows) carries "estimated", the retry rows sit under "Chat agent", and a row that includes an estimate is marked.
  - U4: the largest-request table lists each day's maximum as "n of 100,000 tokens".
  - U5: "Today" shows "No model use in this period." and no chart or table.
  - U6: keyboard only. Tab reaches the nav item, the Range select and the Group by radios, both change by keyboard, `getByLabel` finds each control, and the legend and markers are words and shapes, not colour alone.
  - U7: `scanContrast`/`scanNames` are clean in light and dark.
  - U8: at 1000px wide the regions stack, and at 1280px with the root font at 200% the page does not scroll sideways.
  - U9: the second session's rows (PANEL) never show for LIVE.
- Shared-surface test updates (Rule 19; search for each):
  - `web/e2e/settings/settings.spec.ts:68` gets `['Chat', 'Settings', 'Documents', 'Usage']`;
  - `web/e2e/documents/documents.spec.ts:337` gets `['Chat', 'Documents', 'Usage']`;
  - `web/e2e/frame/frame.spec.ts:157-184` gets the Tab order and header boxes with Usage after Documents, and still exactly one navigation landmark;
  - `web/scripts/settings-view.test.mjs` (`pageOf('/usage')`);
  - `web/scripts/more-to-try-view.test.mjs` (`RULED`, `ACTION_OF`, `GROUP_OF`);
  - `web/scripts/ux-strings.test.mjs` (`USAGE_TEXTS` and its sources);
  - `web/e2e/guide/more-to-try.spec.ts` (`ITEMS` and `controlOf`: usage is a link);
  - any spec or test that pins `guide.features` or the README and EXPERIENCE More to try counts.
- `web/scripts/usage-view.test.mjs` (new) -- Cover `groupRows` for all four groupings (sums, order, zero days, the retry merge, the compaction and includes-estimates markers, unknown values), `largestByDay`, `dayLabel` (year, and a UTC-safe date), `chartGeometry` (one bar and one point per row, scales), and `USAGE_TEXTS` equal to the PUBLIC TEXT values.

**Acceptance Criteria:**
- Given this story's change, when the spine is read, then the REST table has the `GET /api/v1/usage` row and the cross-area table has the `Ownership.Usage` and header-navigation Usage rows, each marked `[ADDED 2026-11-10, Story 37.2]`. It has no History, file upload, private file table or Roles row. `lint_spine.py` reports the same 10 low `placeholder` findings at lines 478, 1017 (x2), 1086, 1099 (x2), 1165 (x3) and 1176 as before.
- Given the LIVE fixture user (OcuTalonUser only) signed in, when they press Usage in the header navigation, then `#/usage` opens, titled "Usage · OcuTalon", with `aria-current="page"` on the Usage item and no History item. It shows the Range control, the Group by control, the chart with token bars and a cost line (each labelled directly and in the legend), and beneath the chart a table with one row for every bar and point.
- Given fixture rows across days, agents, channels and models in the caller's session, plus another session's and `eval`'s rows, when each grouping is chosen, then each table row's tokens and cost equal the sum of its rows, and the chart's bars and points equal the table's rows. The compaction rows appear as their own agent, labelled "Chat summaries" and marked estimated; the Agent, Channel and Model groupings show only values with rows in the range. The retry runners' rows count under their agent. No other-session or `eval` row ever counts.
- Given rows on several days, when the page shows the range, then each day with use shows its largest model request (estimated) as "{n} of 100,000 tokens", taken from the route's `limit`.
- Given any row, when its numbers render, then tokens use digit separators and costs follow `formatCost` (for example $0.0006, $0.042, $1.24, and <$0.0001 below that) in tabular figures.
- Given a range with no model use, when the page loads, then it shows "No model use in this period." and no chart or table.
- Given the page, when it is used by keyboard alone, then every control is reachable and operable and has a label. Nothing relies on colour alone. Contrast meets AA in light and dark. Below 1024px the regions stack, and the page never scrolls sideways (also with the text at 200%).
- Given the guide's More to try panel with the `usage` feature, when the visitor presses the Usage item's link, then the Usage page opens by navigation. The registry, the view's header comment, README :40 and EXPERIENCE.md :245 all say nine items. The README's "New since 1.0.0" ends with the Usage line.
- Integration: the Usage page (the consumer) reads `GET /api/v1/usage` on a real stack and shows its seeded rows' sums. The `live:sign-in` e2e specs `api/usage.spec.ts` and `usage/usage.spec.ts` exercise this against a running IRIS, with no mocks.

## Spec Change Log

- 2026-11-10 ~08:2xZ, lead (re-dispatch): the implement HALT (`implementation verification failed`, a machine-wide Docker build hang) was infrastructure, not the story. The orchestrator reports builds work again (probe at about 08:1xZ; the stuck process was another lane's bake). Status reset from `blocked` to `in-progress` for a verification-and-finalize pass over the implementation already in the working tree (uncommitted, from implement pass 1, baseline 51ce312d). Any build that hangs again is time-limited and reported as TOOLING, with the stuck process left running.

- 2026-11-10, lead (spec gate): the Contest Planner's rulings written in [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]. PUBLIC TEXT approved except the agent name ("Chat summaries", not "Compaction"), the More to try look-for and the README bullet (ruled texts in the table); condition: Agent, Channel and Model groupings show only values with rows in the range, Day keeps every date with 0s. SECURITY accepted with conditions (ii) days=0, 31 and abc are 404 not_found and (iii) a key allow-list assertion on the body (added to Test.Web.UsageApi TestShape and api/usage.spec.ts (ii)). Group: "Safety and settings", usage last. The Demo/Features union with ",usage" last is accepted. 37.2 targets release 1.0.7.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-4: ownership, with the SessionRef from the CSP session.
- AD-13: the envelope; the user has no SQL privilege; the unchecked prepare only in `Ownership.Rows` with fixed SQL; a second-session test for every row kind.
- AD-18: the instance zone through `Data.Time`.
- AD-20: usage rows, totals as sums, compaction estimated, `eval` never counted.
- AD-27: retention is unchanged; at most 30 days are read, inside the 90-day default.
- AD-29: Lane B files only; the bridge is read-only.
- AD-31: Web and Core read `Bridge.Data` read-only through the ownership API and keep no copies (spine :1090).
- AD-33: no new item, table or event type; the ownership tables gain this story's rows.
- Conventions: REST (:1163), Times (:1162), Identifiers (:1161, no row ids) and Angular (:1201, inline SVG with no kit).
- No AC contradicts an AD.

**Already delivered (not rebuilt):**
- `formatCost` and `formatTokens` (`chat/decision-view.ts:72-92`, tested in `decision-view.test.mjs:67-182`).
- Tabular figures (`styles/base.css:93,143-145`).
- The chart tokens in light and dark (`tokens.css`, listed above).
- `Ownership.Sum`, `RunCost` and `TurnCost` (`Ownership.cls:85-205`).
- The local-day convention (`Ownership.HeartbeatToday` :132-138, `Bridge.Budget` :47-50).
- `Fixture.Usage` (:160).
- The `group?` registry field (`more-to-try-view.ts:91`).
- The agent names (`settings-view.ts:77`) and token labels (`decision-view.ts:23-32`).

Missing until this story: the route, the `usage` kind, the page, the nav entry, the item and the spine rows.

**Rule 1 / 2, Consumed-by and Consumes:**
- Consumed-by: this story's Usage page (`web/src/app/usage/`), and its e2e specs as the integration AC. No later story is named; Story 25.2's History is a separate read.
- Consumes:
  - `OcuTalon.Bridge.Data.Usage` (AD-20 runner rows; Lane A);
  - `Ownership.Rows`, `Sum` and `SessionRef`;
  - `Data.Time`;
  - `Decide.#MAXREQUESTTOKENS`;
  - `formatCost`, `formatTokens`, the token labels and the agent names.
- Extend, don't copy:
  - `Web.Usage` extends `Web.Api`, like `Web.Documents`;
  - the `usage` kind is `heartbeatUsage`'s sibling;
  - `Ownership.Usage` reuses `Sum` per bucket;
  - the page follows `documents-page.ts`;
  - the e2e helper follows `support/memory.ts`;
  - the test classes follow `OwnershipMemories` and `DocumentsApi`.
- Two deliberate copies, each because the file is contended and allows only plain-union additions:
  - the 5-line local-day-bounds computation of `HeartbeatToday`. Unifying it would change an existing method of `Ownership.cls`, where Epic 23 also edits `recentNotices`;
  - the one-line `documents` link branch in `more-to-try.ts`, which is contended by Epic 41, Epic 23 and Story 0.22.
- Ledger inbox: none.

**Decided in-stage:**
1. **Day boundary.** The day is the instance zone's: local dates come from `Data.Time.ToLocal`, and bounds from `FromLocal` of local midnight. The evidence is `Ownership.HeartbeatToday` :135-138 and `Bridge.Budget.State` :47-50 (the daily cap's day, spine :679). Day labels are calendar dates, so the page applies no browser-zone conversion.
2. **Range options.** Today (1), the last 7 days (7, the default) and the last 30 days (30). Each counts local days and includes today. 30 stays well inside the 90-day retention.
3. **Bad range.** A bad `days` is 404 `not_found`, following the notes route's bad `day` (Api.cls `Notes` :1776), so no new error code goes into the REST conventions row.
4. **Where grouping happens.** The server sums buckets once per range, and the client groups and regroups without a fetch. Every group is a sum of buckets, so the totals still equal the sum of the rows.
5. **Retry runners.** `TriageAgentRetry`, `DiagnosisAgentRetry` and `ChatAgentRetry` group under their agent. They are the same agent's second-model attempt.
6. **NULL cost.** A NULL cost counts as 0, as `Sum` counts it for `TurnCost` and `RunCost`. This is the figure the AC says the totals must equal.
7. **Estimated markers.** The largest request is labelled estimated, because AD-20 and S4 make it an estimate. The bar's tokens are Input + Output, because Input already includes the cache tokens.
8. **No live refresh.** The page reads on open, on a range change and on Retry. AD-33 forbids a new event type here.
9. **The `limit` value.** It comes from `Decide.#MAXREQUESTTOKENS`, which keeps NFR-3's number in one place.
10. **Grouping control.** A radio group, and the Range is a native select. Both are keyboard-native and follow existing patterns (`models-section.ts:65`, `time-zone-section.ts:45-58`).

**CONTENDED CHANGES (non-additive edits in contended files, for the lead):**
- The word "eight" becomes "nine" in `more-to-try-view.ts` :2-3 and :94, README :40 and EXPERIENCE.md :245. The registry count decides the number, and whichever story merges later sets it. The lead brief cites README L30, but on this branch the count is on L40 (L30 is install step 4).
- The new last line in `Demo/Features.Ids` and its comment. This file is not in the contended list, but Epic 23 and Epic 41 items may add ids beside it.

Everything else in the contended files is additive:
- `Api.cls`: one Map line and one comment line;
- `Ownership.cls`: three blocks;
- `more-to-try{,-view}.ts`: one union member, one texts entry, one item, one link branch and one press case;
- README: one bullet appended last;
- EXPERIENCE.md: one item line and one clause.

**Footprint extensions (Rule 11):**
- `web/src/app/app.config.ts` (the route);
- `web/src/app/settings/settings-view.ts` (`pageOf` only);
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` and its test;
- `web/e2e/{settings,documents,frame,guide}/*.spec.ts` (shared-surface updates);
- `web/scripts/*.test.mjs`.

None is contended.

**Risk, the 1024px header.** At 1024px the drawer band holds three links on one line (`header.ts:84-88`). The implement stage measures the header with four links at 1024px as the README admin account in demo mode, which is the widest case, using the existing `frame.spec.ts` header-box assertions. If they do not fit, it tightens nav spacing within `web/src/app/header/**`. If even that cannot keep one line, it escalates with `## Clarification Needed` and never hides a link.

**CI placement (for the lead):**
- `new_units:` none.
- `ci_groups:`
  - `image` gets `Test.Data.OwnershipUsage` (lane-b@Contract,Core,Data,Live; a few seconds, inference);
  - `shards-6` gets `Test.Web.UsageApi` (lane-b@rest; well under a second);
  - `shards-10` gets `web/e2e/api/usage.spec.ts` and `web/e2e/usage/usage.spec.ts` (`live:sign-in`, 1,544 s planned, the most headroom; under a minute added, inference);
  - `shards-5` reruns its updated `more-to-try.spec.ts` (`live:sign-in-3`), and `shards-4` reruns `settings.spec.ts` (`live:sign-in-2`).
- Both shard pieces were planned at about 900 s, so the first CI run checks them.

**SECURITY -- ACCEPTED as specced [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md], with conditions: (i) the real-HTTP tests as listed (401 signed out; LIVE 200 with exact sums; PANEL isolated both ways; an eval row never appears); (ii) `days=0`, `31` and `abc` each give 404 `not_found`; (iii) a key allow-list assertion on the body proves no ref, row id, user name or SessionRef appears; (iv) the user role is not widened, and the 1024px header escalates rather than hiding a link.**
- New route: `GET /api/v1/usage` (query `days` = 1, 7 or 30). It is the only new route.
- Who may call it: any signed-in user with `OcuTalonUser` (the online demo's visitors, local users and admins, who also hold it). It is not admin-only. The existing envelope applies: 401 `signed_out`, 403 `no_role`.
- Rows returned: only the caller's own session's `Bridge.Data.Usage` rows, summed. On the online demo that is the visitor's session (the Ref recorded in the CSP session at sign-in; no fallback). On a local install it is the IRIS user's durable session. Rows of another session, `eval`, `instance` or no owner are never read; instance-owner rows are not shown on a local install either. No refs, row ids, user names or `SessionRef` appear in the body.
- New privilege, role, grant, resource, stored table, stored column, index or retention: none. The read uses the existing allow-listed unchecked prepare in `Ownership.Rows` (fixed SQL with the owner in `WHERE`), so the user role gains no SQL privilege.

**PUBLIC TEXT -- every new or changed user-facing string, verbatim. "Given" cites the source; every proposal is RULED [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]: approved except items 4 (agent name), 10 (look-for) and 12 (README bullet), which carry the ruled text below. The implement stage uses exactly these strings.**

| Where (file) | String | Status |
| --- | --- | --- |
| `header/header-nav.ts` | `Usage` | Given: EXPERIENCE.md:60, :77; UX-DR21 |
| `usage/usage-view.ts` title | `Usage · OcuTalon` | Given: epics.md:9339; UX-DR22 pattern |
| usage-view `h1` | `Usage` | Given: same as the nav label (EXPERIENCE.md:60) |
| usage-view range label | `Range` | PROPOSED -> RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] (the UX gives "a range", EXPERIENCE.md:1055, but no label) |
| usage-view range options | `Today` · `Last 7 days` · `Last 30 days` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view grouping legend | `Group by` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view grouping options and first column header | `Day` · `Agent` · `Channel` · `Model` | Given as words: PRD FR-52 (prd.md:990), epics.md:9339; capitalised |
| usage-view chart region `h2` | `Tokens and cost` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view legend and direct labels; table headers | `Tokens` · `Cost` | Shipped strings reused (`decision-view.ts` rowTokens and rowCost); DESIGN.md:865 names token bars and a cost line |
| usage-view table headers | `Input` · `Output (includes thinking)` · `Cache read` · `Cache write` | Given: EXPERIENCE.md:185 (shipped in decision-view.ts:29-32) |
| usage-view agent names | `Triage agent` · `Diagnosis agent` · `Chat agent` | Shipped strings reused (settings-view.ts:77) |
| usage-view agent name | `Chat summaries` (keeps the `estimated` marker) | RULED (changed from "Compaction") [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view channel names | `Web chat` · `Simulated phone` · `Simulated mailbox` · `Telegram` · `Email` · `Webhook` · `Slack` · `System` · `Heartbeat` | "Simulated phone" and "Simulated mailbox" are given (EXPERIENCE.md:71), "Telegram" and "the web chat" are given (EXPERIENCE.md:188, lower case in sentences); the rest RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]; Agent, Channel and Model groupings show only values with rows in the range |
| usage-view estimated marker (a row that is all estimates, e.g. Chat summaries) | `estimated` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] (the AC says "marked as estimated", epics.md:9344) |
| usage-view marker (a group that includes estimated rows) | `includes estimates` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view largest region `h2` | `Largest request per day` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view largest column header | `Largest request (estimated)` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] (PRD prd.md:245 says the request size is labelled as an estimate) |
| usage-view largest cell | `{tokens} of {limit} tokens` → "12,345 of 100,000 tokens" | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| usage-view empty | `No model use in this period.` | Given: EXPERIENCE.md:394; UX-DR147 |
| usage-view error | `Couldn't load your usage.` and the button `Retry` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] (follows EXPERIENCE.md:363 "Couldn't load your session." + Retry); no loading text, as on the Documents page |
| `guide/more-to-try-view.ts` item label | `See tokens and cost` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| item look-for | `On the Usage page, choose a range and group by day, agent, channel or model. The tokens and cost come from your chat turns and from the agents' decisions on your messages and incidents, and each day shows its largest model request against the 100,000-token limit. If it reads "No model use in this period.", chat or run the guide first.` | RULED (changed) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]. The inner quotes are straight ASCII quotes, as the module's other texts are |
| item control (a link) | `Open the Usage page` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| `README.md`, appended last in "New since 1.0.0" | `- **A Usage page.** Open Usage in the header to see your tokens and cost by day, agent, channel or model, counted per turn and per decision, with each day's largest model request (an estimate) against the 100,000-token limit. On the online demo you see only your own session's use. Try it: More to try, *See tokens and cost*.` | RULED (changed) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]; test-readme must stay green |
| `README.md:40` | `eight more things to try` → `nine more things to try` | Count follows the registry |
| EXPERIENCE.md:245 + new item 9 line + :254 clause | "There are nine items…"; item 9: `**See tokens and cost**: …` in the list's form, with the look-for text above; ":254 … and item 9's control is a link to the Usage page" | Follows the item's ruled text and the count |

**MORE TO TRY GROUP -- RULED [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]: the existing "Safety and settings", with usage LAST in it (five items there). No fourth heading.** The plan proposed the existing group `Safety and settings`. Cost and the 100,000-token limit are guardrails that sit with the daily cost cap and the token budget, and a fourth heading over a single item would spend the panel's limited room (the compact band, `more-to-try-view.ts` `inCompactBand`). The alternative is a fourth heading, `Usage and cost`. Until Story 0.22 renders headings, the field is ignored.

**Lead spec gate (2026-11-10, runner B):**
- RULED 2026-11-10 ~07:00Z (see Spec Change Log): PUBLIC TEXT, SECURITY and MORE TO TRY GROUP are written into the table and sections above and into Tasks & Acceptance. SCOPE is already ruled (the first AC's [AMENDED 2026-11-10] marker in epics.md): this story's own rows only, no History entry.
- Contended, plain union at integrate-forward: `Demo/Features.cls` and `Test/Demo/Features.cls` are also changed on OCT-epic23 (Story 23.6 puts `incidentSummary` first among the constants). Merged, the ids read `incidentSummary,...,sources,usage`, and the count words follow the registry. The same applies to the More to try registry, README :40 and EXPERIENCE.md :245, which Story 23.6 also counts.
- `e2e/usage/usage.spec.ts`'s `clearUsage(LIVE)` relies on `workers: 1` and `fullyParallel: false` (`playwright.config.ts:65-67`), as the heartbeat card spec does. It deletes only the LIVE session's Usage rows on the e2e stack, never on a dev slot.

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=37 stage=implement'`. The fresh tag is `e37s2i`; the warm tag is `e37s2iw`. Compile checks may also use the dev slot: profile `ocutalon-slot-b`, namespace `OCUTALON`, passed on every MCP call, with one `iris_execute_tests` per message.

Run one command per tool call, each sized to about 150 s (one test class per call). A call moved to the background is waited for in bounded foreground polls. IRIS runs only on the slot and on lane-B throwaways. Tear down only the tags you started; `ci/warm.sh down` runs at the end, also after a failure.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e37s2iw ci/warm.sh up` once, then one class per call: `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s2iw ci/iris.sh class OcuTalon.Test.Data.OwnershipUsage`, then the same for `OcuTalon.Test.Web.UsageApi`, `OcuTalon.Test.Demo.Features` and `OcuTalon.Test.Data.OwnershipMemories` (the sibling must still pass) -- each `CLASS … passed`.
- (loop) `node --test web/scripts/usage-view.test.mjs web/scripts/settings-view.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/ux-strings.test.mjs web/scripts/decision-view.test.mjs` -- all pass.
- (loop) e2e:
  - First `$LANE OCUTALON_RUN_TAG=e37s2i ci/iris.sh build`.
  - Find the part holding `e2e/api/usage.spec.ts` and `e2e/usage/usage.spec.ts`: `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"` and `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`, where `$SCRATCH` is `e37s2impl/` of the session scratchpad. Then `$LANE OCUTALON_RUN_TAG=e37s2i ci/iris.sh live sign-in --part k/n` -- the part passes.
  - The same for `frame/frame.spec.ts` and `documents/documents.spec.ts` (chromium), `settings/settings.spec.ts` (`e2e:sign-in-2` and `live sign-in-2 --part`), and `guide/more-to-try.spec.ts` (`e2e:sign-in-3` and `live sign-in-3 --part`).
  - Finally `$LANE OCUTALON_RUN_TAG=e37s2i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- the same 10 low `placeholder` findings at the same lines as the baseline. A copy of the baseline is in the plan's scratch folder `e37s2plan/lint-before.json`.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- each passes.
- (once) `bash ci/checks.sh`, in batches of its `CHECK_SCRIPTS` if one call cannot hold it -- every block passes, including `test-class-rules.sh` (no new unchecked prepare), `test-boundaries.sh` (ASCII, Rule 14), `test-readme.sh` and `test-ci-config.sh` (the new classes are in a shard).
- The full IRIS shards and groups are left to CI.

**Shared surfaces:**
- the header navigation's items and Tab order (`settings.spec.ts:68`, `documents.spec.ts:337`, `frame.spec.ts:157-184`);
- `pageOf`'s pages (`settings-view.test.mjs`);
- the More to try registry, its count and its texts (`more-to-try-view.test.mjs` `RULED`, `ACTION_OF` and `GROUP_OF`; `e2e/guide/more-to-try.spec.ts` `ITEMS` and `controlOf`; the view's header comment; README :40; EXPERIENCE.md :245-254);
- `Demo.Features.Ids` / `guide.features` (`Test.Demo.Features`, and any spec that pins the features list);
- the `ux-strings` source list;
- the REST route list (the spine REST table, the `Web.Api` UrlMap);
- the spine's cross-area table;
- the README "New since 1.0.0" list.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19), one per AC, each observed red and reverted byte-identical:**
- the `usage` kind without its `OwnerRef = ?` (`OR 1=1`) -> `OwnershipUsage` TestIsolation and `api/usage.spec.ts` (iii) red;
- `Sum` skipped for one token kind in a bucket -> TestBuckets and `usage.spec.ts` U2 red;
- the `Retry` merge removed -> `usage-view.test.mjs` and U3 red;
- `largestRequestTokens` summed instead of maxed -> TestBuckets and U4 red;
- the bound built from UTC midnight instead of `FromLocal` -> TestRange's day edge red;
- the empty branch removed -> U5 red;
- the Range `<label for>` removed -> U6 red;
- the nav link placed before Documents -> `frame.spec.ts` Tab order red;
- a ruled string changed by one word -> `ux-strings.test.mjs` red;
- one spine row's `[ADDED 2026-11-10, Story 37.2]` marker removed -> the implement record's `grep -c 'ADDED 2026-11-10, Story 37.2'` on the spine counts 2, not 3.

**Implementation record (implement stage, 2026-11-10):**
- Spine: `grep -c 'ADDED 2026-11-10, Story 37.2'` on the spine = 3 (REST row, `Ownership.Usage` row, header-navigation and page row); `lint_spine.py` reports the same 10 low `placeholder` findings as `lint-before.json` (identical findings, `ok` false before and after).
- Verified in this stage: `node --test` of `usage-view`, `settings-view`, `more-to-try-view`, `ux-strings`, `decision-view` and the whole `npm --prefix web test` green (the e2e-part and playwright-projects tests included); `npm --prefix web run lint` and `run build` pass; `docker/tests/test-boundaries.sh`, `test-readme.sh`, `test-ci-config.sh` and `test-class-rules.sh` pass; on the dev slot (profile `ocutalon-slot-b`) `Test.Data.OwnershipUsage` (5), `Test.Web.UsageApi` (5), `Test.Demo.Features` (5), `Test.Data.OwnershipMemories` (4), `Test.Web.DocumentsApi:TestDispatch` and `Test.Web.Api:TestRoutes` pass.
- NOT run: the warm-stack class runs, the e2e parts and the 1024px header measurement. Docker image builds hang on this machine (a plain `docker build` of `FROM alpine` did not finish in 60 s, with the classic builder as well, while two other epics' builds had been stuck 20+ minutes), so `ci/warm.sh up` never produced a stack; it was stopped and `ci/warm.sh down` ran (0 leftovers). The e2e specs `api/usage.spec.ts` and `usage/usage.spec.ts`, the new `frame.spec.ts` case "F3: at 1024px the header holds the four navigation links on one line" (it prints a `HEADER1024` line) and the updated `settings`, `documents`, `frame` and `guide/more-to-try` specs are written, type-checked (`npm run lint`) and listed by Playwright, but have not run.

mutation: the `usage` kind's `OwnerRef = ?` replaced by `(OwnerRef = ? OR 1 = 1)` -> `Test.Data.OwnershipUsage` TestIsolation red (4 of 5 green), reverted, green again. `api/usage.spec.ts` (iii) not run (no stack).
mutation: `Set bucket.cacheWriteTokens = 0` after `Sum` in `Ownership.Usage` -> `Test.Data.OwnershipUsage` TestBuckets red, reverted, green again. `usage.spec.ts` U2 not run.
mutation: the `Retry` merge removed (`agentKey` returns its argument) -> `usage-view.test.mjs` red ("counts the retry runner under its agent..." and "merges all three retry runners..."), reverted byte-identical. U3 not run.
mutation: `largestRequestTokens` summed instead of maxed -> `Test.Data.OwnershipUsage` TestBuckets red, reverted, green again. U4 not run.
mutation: the bounds built from UTC midnight (`first_"T00:00:00Z"`) instead of `FromLocal` -> `Test.Data.OwnershipUsage` TestRange red (in America/New_York, Asia/Kolkata and Pacific/Auckland: the day edge and the window), reverted, green again.
mutation: the empty branch removed -> NOT observed (needs U5 on a stack).
mutation: the Range `<label for>` removed -> NOT observed (needs U6 on a stack).
mutation: the nav link placed before Documents -> NOT observed (needs `frame.spec.ts` F3 Tab order on a stack).
mutation: the ruled string 'Largest request per day' changed to 'Largest request each day' -> `ux-strings.test.mjs` red (3 tests) and `usage-view.test.mjs` red (1 test), reverted byte-identical.
mutation: one spine row's `[ADDED 2026-11-10, Story 37.2]` marker removed -> `grep -c` on the spine counts 2, not 3; reverted byte-identical (3 again).

## Auto Run Result

Status: blocked
Blocking condition: implementation verification failed: Docker image builds hang on the dev machine (infrastructure), so no throwaway or warm stack can start and the spec's (loop) e2e lines, the warm class runs, the 1024px header measurement and the e2e-bound Rule 19 mutations cannot run.

Evidence (2026-11-10, implement stage):
- `docker run` works, but `docker build`, `buildx bake` (compose build) and `ci/warm.sh up` never finish: a plain `FROM <local image>` build did not finish in 60-90 s with BuildKit or the legacy builder; with `docker-credential-desktop` bypassed through a private DOCKER_CONFIG it still hangs. Other runners' builds (epic-0 bake, 50 min; epic-23 bake, 40+ min) were stuck the same way. `com.docker.build` has run for 17 days. Not fixed from this session: restarting Docker Desktop would stop the shared slots and the other runners' stacks.
- The warm/fresh tags `e37s2iw` and `e37s2i` were torn down (`ci/warm.sh down`: 0 leftovers; lane-b lock folder empty).
- The implementation is complete in the working tree and uncommitted (HEAD is still the baseline). Passed: slot-b class runs `Test.Data.OwnershipUsage` 5/5, `Test.Web.UsageApi` 5/5, `Test.Demo.Features` 5/5, `Test.Data.OwnershipMemories` 4/4, `DocumentsApi:TestDispatch` and `Api:TestRoutes`; `npm --prefix web test` 1798/1798; `npm --prefix web run lint` and `build` pass; `test-boundaries.sh`, `test-readme.sh`, `test-ci-config.sh`, `test-class-rules.sh` pass; spine lint equals the baseline and the spine holds 3 `[ADDED 2026-11-10, Story 37.2]` markers.
- Not run (needs a stack): the new `web/e2e/api/usage.spec.ts` and `web/e2e/usage/usage.spec.ts` and the updated frame, documents, settings and more-to-try specs (never executed; untried: ArrowDown firing `change` on the Range select in U6, `costUSD` JSON number form), the 1024px header measurement (case F3 in `frame.spec.ts` prints a `HEADER1024` line; remove that temporary console.log once measured), the e2e-bound mutations (empty branch, Range `<label for>`, nav before Documents), `bash ci/checks.sh` in full, the review layers and the finalize commit.
- To resume once Docker builds work: re-dispatch on this spec path; set status back to `in-progress` (baseline_revision is recorded), run the (loop) e2e parts, then the review layers.
