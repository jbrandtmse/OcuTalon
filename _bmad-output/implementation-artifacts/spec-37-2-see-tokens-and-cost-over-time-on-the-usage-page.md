---
title: 'Story 37.2: See tokens and cost over time on the Usage page'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: 'de23e9297b05b8136f0e08348c133667345a907c'
baseline_commit: 'de23e9297b05b8136f0e08348c133667345a907c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-37-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A day, group or bucket with no cost reads "<$0.0001" (formatCost of 0), so an empty day in the Day grouping suggests a tiny spend that did not happen.
    evidence: |-
      `formatCost(0)` returns the shipped "<$0.0001" and the Usage tables render it for every zero-cost row, including the zero-fill days of the Day grouping and a row whose model has no price. The AC says costs follow `formatCost`, so the page is as specified, but the PUBLIC TEXT table has no string for an exact zero (for example "$0"), and a new public string needs the Planner's ruling.
    location: >-
      web/src/app/usage/usage-page.ts cost(); web/src/app/chat/decision-view.ts formatCost
    severity: medium
  - summary: >-
      Story 0.22's block in epics.md (:1564-1565 and :1584) and the derived epic-0-context.md still say three More to try headings and that usage joins "Safety and settings" with no fourth heading.
    evidence: |-
      The Planner's ruling of 2026-11-10 ~19:10Z (prompts/epic-25-rulings-252.md section 3) adds the fourth group "Usage and history". The code, EXPERIENCE.md, the registry and the tests now say four; the planning text of another epic's story block was not in this story's scope (Rule 5, ask first), and epic-0-context.md is recompiled from epics.md.
    location: >-
      _bmad-output/planning-artifacts/epics.md:1564-1565 and :1584; _bmad-output/implementation-artifacts/epic-0-context.md
    severity: medium
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


**Rework iteration 1 (trigger: a Planner ruling after code review; scope: these items only) [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, prompts/epic-25-rulings-252.md section 3; SUPERSEDES the "Safety and settings" group ruling]:**
- [x] [Ruling] R1: the usage registry row's group becomes `'Usage and history'` (`web/src/app/guide/more-to-try-view.ts`); usage stays the last registry entry.
- [x] [Ruling] R2: append `'Usage and history'` as the LAST entry of `MORE_TO_TRY_GROUPS` (0.22's constant). The heading text is ruled; no other text changes. Story 25.2 will later add its history item to the same group.
- [x] [Ruling] R3: tests follow it: the `GROUP_OF` line for usage in `web/scripts/more-to-try-view.test.mjs` (and its "usage is the last item of Safety and settings" assertion becomes "usage is the last item of Usage and history and the last registry entry"); any unit test that pins `MORE_TO_TRY_GROUPS` or `groupsOf`; and K27's written oracle in `web/e2e/guide/more-to-try.spec.ts` (the four headings in order, usage under the fourth). Add NO new e2e case numbers K25-K28 (K28 is reserved for Story 25.2).
- [x] [Ruling] R4: EXPERIENCE.md: after the Safety and settings items, a new entry `    - Heading "Usage and history". [AMENDED 2026-11-10, Contest Planner ruling: a fourth group for the step-6 pages]`, with the usage entry (Item 9) under it, numbered by panel order; the sentence that names the panel's headings ("three headings ...") names the four, with the same marker. `web/scripts/usage-docs.test.mjs` and any test reading EXPERIENCE's headings follow.
- [x] [Ruling] R5 (condition): the compact-band tests K16 and K17 (1280x650 and 1280x600) stay green with the fourth heading; run the `live sign-in-3` part(s) holding `guide/more-to-try.spec.ts`. If they cannot stay green without changing the band logic, do NOT change the band logic: revert R1-R4 to the previous ruling (usage last in "Safety and settings") and HALT with an intent gap that reports the measurement. Measured: green with the fourth heading shown (see `## Verification`); the band logic is unchanged; no revert.


**Rework iteration 2 (trigger: Planner rulings on DW-1089 and DW-1090; scope: these items only) [RULED 2026-11-10 ~21:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md "Integrate-round rulings"]:**
- [x] [Ruling] R6 (DW-1089): on the Usage page an exact-zero cost shows `$0`; a non-zero amount under $0.0001 keeps `<$0.0001`; every other amount keeps `formatCost`. Apply it in the Usage page's own cost formatting (`web/src/app/usage/**`), never by changing the shared `formatCost` in `chat/decision-view.ts` (its other callers keep their shipped behaviour). Add a unit case for each (exact zero → `$0`; e.g. 0.00004 → `<$0.0001`), with a mutation line, and update any Usage e2e assertion that expected `<$0.0001` for a zero-cost row or day.
- [x] [Ruling] R7 (DW-1090): the More to try usage look-for's SECOND sentence becomes, verbatim: `The tokens and cost come from your chat turns and from the agents' decisions on your messages.` The first and last sentences are unchanged. Update `MORE_TO_TRY_TEXTS.items.usage.lookFor` (straight ASCII apostrophe, escaped as the module does), every test oracle that writes the text out (the RULED copy in `web/scripts/more-to-try-view.test.mjs`, `usage-docs.test.mjs`, `ux-strings.test.mjs` if it holds it), and EXPERIENCE.md's Item 9 entry, with the marker `[AMENDED 2026-11-10, Contest Planner ruling on DW-1090: the look-for counts only the session's own decisions]`. The README bullet stays as ruled.


**Rework iteration 3 (trigger: a CI red on this story's head 9848c3ec, ci run 42907226080, job `iris (shards-3)`, unit `live:floor`; the LAST iteration the cap allows; scope: this item only):**
- [x] [CI] live:floor `web/e2e/floor/layout.spec.ts` at "200%: 640x360 at device scale 2": G4 (:572, "after scrolling to the bottom the header is still at the top": received 2909) and G5 (:647, "the header writes its measured block size to the root (0px against 121)") are red. Cause (lead's reading, to confirm by measurement): the fourth header link (Usage) wraps the compact header's navigation to a taller header (121px) at 640x360, over the quarter-of-the-window line, so the header stops sticking and writes 0. Fix it inside `web/src/app/header/**` so that at 640x360 (and every window the floor's layout cases cover) the header with all four links stays within the size it must keep to stay sticky, as with three links before this story: e.g. tighter navigation spacing or item padding below 1024px, as the drawer band already does. Never hide or drop a link, never add sideways scroll, never change the quarter-of-the-window rule or the floor tests, and keep the 1024px one-line header (frame F3) and the 305px case (more-to-try K22/K23). Run `live:floor` locally (the whole unit, or the floor project's layout cases if the unit splits) on a fresh lane-B stack, plus `frame.spec.ts`'s part and `sign-in-3 --part 1/2`; the floor unit takes ~12 minutes, so start it writing to a file and poll it in bounded calls. If no spacing change keeps the header under the line without hiding a link, HALT with an intent gap naming the measurement.

**Acceptance Criteria:**
- Given this story's change, when the spine is read, then the REST table has the `GET /api/v1/usage` row and the cross-area table has the `Ownership.Usage` and header-navigation Usage rows, each marked `[ADDED 2026-11-10, Story 37.2]`. It has no History, file upload, private file table or Roles row. `lint_spine.py` reports the same 10 low `placeholder` findings at lines 478, 1017 (x2), 1086, 1099 (x2), 1165 (x3) and 1176 as before.
- Given the LIVE fixture user (OcuTalonUser only) signed in, when they press Usage in the header navigation, then `#/usage` opens, titled "Usage · OcuTalon", with `aria-current="page"` on the Usage item and no History item. It shows the Range control, the Group by control, the chart with token bars and a cost line (each labelled directly and in the legend), and beneath the chart a table with one row for every bar and point.
- Given fixture rows across days, agents, channels and models in the caller's session, plus another session's and `eval`'s rows, when each grouping is chosen, then each table row's tokens and cost equal the sum of its rows, and the chart's bars and points equal the table's rows. The compaction rows appear as their own agent, labelled "Chat summaries" and marked estimated; the Agent, Channel and Model groupings show only values with rows in the range. The retry runners' rows count under their agent. No other-session or `eval` row ever counts.
- Given rows on several days, when the page shows the range, then each day with use shows its largest model request (estimated) as "{n} of 100,000 tokens", taken from the route's `limit`.
- Given any row, when its numbers render, then tokens use digit separators and costs follow `formatCost` (for example $0.0006, $0.042, $1.24, and <$0.0001 for a non-zero amount below that), except that an exact-zero cost shows "$0", in tabular figures. [AMENDED 2026-11-10, DW-1089 ruling]
- Given a range with no model use, when the page loads, then it shows "No model use in this period." and no chart or table.
- Given the page, when it is used by keyboard alone, then every control is reachable and operable and has a label. Nothing relies on colour alone. Contrast meets AA in light and dark. Below 1024px the regions stack, and the page never scrolls sideways (also with the text at 200%).
- Given the guide's More to try panel with the `usage` feature, when the visitor presses the Usage item's link, then the Usage page opens by navigation. The registry, the view's header comment, README :40 and EXPERIENCE.md :245 all say nine items. The README's "New since 1.0.0" ends with the Usage line.
- Integration: the Usage page (the consumer) reads `GET /api/v1/usage` on a real stack and shows its seeded rows' sums. The `live:sign-in` e2e specs `api/usage.spec.ts` and `usage/usage.spec.ts` exercise this against a running IRIS, with no mocks.

### Review Findings

Code review 2026-11-10 (bmad-code-review, full mode, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `e6dbfcc4` to the working tree). 35 raw findings: 0 high; 14 entries kept (11 patched, 3 deferred to the ledger), 16 rejected (below). No AD mismatch (AD-4, AD-13, AD-18, AD-20, AD-27, AD-29, AD-31, AD-33 checked); every RULED string and condition is in the code verbatim.

- [x] [Review][Patch] (med) Retry dropped focus to the body and a failed read was never announced: a Retry that fails again left a keyboard or screen-reader user with nothing said and no focus [web/src/app/usage/usage-page.ts:457] -- the failed text and Retry stay until the next answer and each failure is announced (the ruled error text, through the Announcer, as the settings page does); new U14; `announce-focus-sources.test.mjs` lists the page as a speaker.
- [x] [Review][Patch] (med) The route's 500 when `Ownership.Usage` fails (I/O matrix "Failed read") had no test; deleting the branch gave 200 with empty days and buckets [src/ocutalon/cls/OcuTalon/Web/Usage.cls:32] -- `Test.Web.UsageApi` TestFailedRead.
- [x] [Review][Patch] (low) The page's drop of a late answer to an earlier range had no test [web/src/app/usage/usage-page.ts:465] -- new U15.
- [x] [Review][Patch] (low) `Demo.Features` doc still said "sources: last" beside "usage: always, last" [src/ocutalon/cls/OcuTalon/Demo/Features.cls:10]
- [x] [Review][Patch] (low) `api/usage.spec.ts` message said "four buckets" for three [web/e2e/api/usage.spec.ts:99]
- [x] [Review][Patch] (low) `usage.spec.ts` header said "U1 to U9" [web/e2e/usage/usage.spec.ts:12] -- now U1 to U15.
- [x] [Review][Patch] (low) Rule 14 process narration in comments: "(QA)" and "(QA, Story 37.2)" in `Test.Web.UsageApi`, "the Rule 3 evidence for" in `api/usage.spec.ts`, "the last one before this story" in `usage-docs.test.mjs` [src/ocutalon/cls/OcuTalon/Test/Web/UsageApi.cls:12]
- [x] [Review][Patch] (low) `usage-docs.test.mjs` checked the per-turn and never-per-step claims against its own constant (could not fail) [web/scripts/usage-docs.test.mjs:49] -- they now read the README's Usage bullet; mutation recorded.
- [x] [Review][Patch] (low) `Test.Web.DocumentsApi` TestDispatch kept an always-true `map.url` assertion after the loop was narrowed to `/v1/documents` [src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls:102] -- removed (the count of `/v1/documents` Maps still pins it).
- [x] [Review][Patch] (low) Rule 2: TestDayEdge saved and restored the process zone by hand instead of `ZoneCase.CurrentZone`/`PutZone`, which ZoneCase offers to classes outside it [src/ocutalon/cls/OcuTalon/Test/Web/UsageApi.cls:207]
- [x] [Review][Patch] (low) No test showed every navigation link inside a 305px window [web/e2e/usage/usage.spec.ts:337] -- U8 asserts it for LIVE (three links). Not discriminating against the wrap for three links (removing `flex-wrap` left U8 green); the four-link case is `more-to-try.spec.ts` K22/K23, which were red before the wrap. The wrap itself keeps every link visible and reachable: the header has a min-height and no overflow clip, and F3 pins one line at 1024px.
- [x] [Review][Defer] A zero cost reads "<$0.0001" [web/src/app/usage/usage-page.ts:497] -- deferred: DW-1089 (decision-pending, PUBLIC TEXT ruling), occurrence appended.
- [x] [Review][Defer] On a local install the page never counts instance-owned incident decisions, while the ruled look-for says the cost comes from "the agents' decisions on your messages and incidents" [src/ocutalon/cls/OcuTalon/Data/Ownership.cls:190] -- deferred: DW-1090 (decision-pending owner=burndown; spec-bound behaviour, product or ruled-text call for the Planner).
- [x] [Review][Defer] Small private test helpers repeated: `UsageApi.Envelope` = `DocumentsApi.Envelope`; `KeysOf`, `Models`, `LocalDate`/`Date` in both new test classes [src/ocutalon/cls/OcuTalon/Test/Web/UsageApi.cls:298] -- deferred: DW-1091 (wontfix-accepted, reopen_if a third copy or a drift).

Rejected:
- (low) Edge: `today` empty makes `$ZDateH` throw -- `NowUtc` always has the form `ToLocal` reads; the same lines run in `HeartbeatToday`. Theoretical.
- (low) Edge: a zone change between the bounds and the per-row `ToLocal` could put a bucket outside `days` -- theoretical (the instance zone changes mid-read).
- (low) Edge: with a zero last row the "Cost" label sits 16px under the baseline -- it stays in the right margin, apart from the category labels; cosmetic, and the fix adds a branch.
- (false) Edge: `dayLabel` of day 00 -- the server writes `days` and `day` with `$ZDate(...,3)`, always a real date.
- (low) Edge: a run across local midnight shifts the seeded days -- theoretical, as the sibling classes; rejected before in the triage log.
- (low) Blind: the real-HTTP isolation seeds no `instance` row -- `Test.Web.UsageApi` TestIsolation reads through `Read` with onlineDemo off (the local-install case) and the instance row stays out; the SECURITY ruling names eval for the HTTP test.
- (low) VG: "New since 1.0.0 ends with the Usage line" has no pin -- it holds on this branch (README read); a "last" pin breaks at the next story's merge; the fix would be the AC's wording.
- (false) VG: TestDispatch's doc claims both branches in one run -- it states the outcome for a process with and without the role.
- (low) VG: the spine rows' check is a grep -- the AC's mutation is recorded; the spine is a document with no test host.
- (false) VG: digit separators and the route's limit have no `mutation:` line -- one per AC: AC 5 has U13's, AC 4 has `largestByDay`'s (plus U4).
- (low) VG: `clearUsage(LIVE)` relies on `workers: 1` -- judged safe: in the chromium project only `api/memory`, `api/usage`, `documents` (navigation) and `usage` sign in as LIVE, `api/usage.spec.ts` asserts only its own models, and `usage.spec.ts` clears in `beforeEach`; the e2e stack is a throwaway.
- (low) VG: TestDayEdge leaves the InstanceZone row deleted if the process is killed, and other processes see no instance zone for a few seconds -- the zone is process-local, the restore follows a Try/Catch, and the same window exists in about two dozen ZoneCase classes; only lane B's slot and throwaways run it.
- (low) VG: `onlineDemo` is set per test and restored in OnAfterAllTests -- `Test.Web.DocumentsApi`'s existing pattern, lane B's slot only.
- (low) Acceptance: the nav wraps at every width, not only below 1024px -- F3 pins one line at 1024px for the widest header (README admin, demo mode); where links would not fit, a wrap is the graceful case (before, the page scrolled sideways).
- (low) Acceptance: no check ties the look-for's quoted empty text to `USAGE_TEXTS.empty` -- each is pinned to its ruled value in `ux-strings.test.mjs` and `RULED`; a cross-check is new test surface.
- (low) Acceptance: the "Always" list names `--chart-tokens`/`--chart-cost` while the code uses `--usage-chart-*-series` -- the code follows Tasks and the Code Map and both tokens exist; the fix edits the spec.

Code review 2026-11-10, rework re-review (iteration 1 of 3; bmad-code-review, full mode, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `ad602cfb..HEAD` = commit `c64c8d4e`, bookkeeping excluded). 21 raw findings across the layers (most of them duplicates): 0 high, 0 medium; 2 entries kept and patched (both low), 0 deferred, 11 rejected (below), 3 outside the rework range and not HIGH (not filed, per the re-review scope). Every term of the ruling (prompts/epic-25-rulings-252.md section 3) and R1-R5 checked: the heading text, `MORE_TO_TRY_GROUPS` last entry, the usage row's group, the EXPERIENCE heading line and marker verbatim, the four-headings sentence, K27 updated in place with no new K25-K28 number, the band logic unchanged, `Demo.Features` untouched. No AD involved (registry data and tests, Lane B only). Checklist: DW-1089 and DW-1090 still `decision-pending owner=burndown`; DW-1096 still `routed owner=burndown`.
K16/K16b/K17 on `BAND_IDS` (judged): not a weakening. `BAND_IDS` is a superset of `FOUR`, so every room assertion keeps its power and several are exercised more: the column check still holds the three-item Safety list (plus four list entries), the clip check covers four headings (the `.set-heading` mutation turns K16, K16b and K17 red), the window-takes-the-room and scrolled-to-the-last-control checks run at more sizes, and whether the panel starts closed depends on the shortest window and the chat floor, not the item count. K2 and K4 keep `FOUR`.

- [x] [Review][Patch] (low) The comments around the fixture change misstated its reach: `BAND_IDS` was described as the ids of "K16, K16b, K17" and `openRealFinish` as opening "the four ids", while `openRealFinish` (now `BAND_IDS`) is also the fixture of K19, K19b, K20, K21, K21b, the K22 finish case and K23 [web/e2e/guide/more-to-try.spec.ts:69] -- both comments now name the band ids and every case they reach (Rule 14); those cases were inside the green 126 of 126 run.
- [x] [Review][Patch] (low) `sources-docs.test.mjs`'s headings test is titled for Story 0.22 alone but now also pins the fourth-group ruling's marker [web/scripts/sources-docs.test.mjs:172] -- the title names the marker.

Rejected:
- (low) Blind: the room cases do not measure the largest real panel (all ten items) -- the ruling's condition is the fourth heading, which `BAND_IDS` renders; the room logic does not depend on the item count beyond the window's scroll (verification-gap traced it); theoretical.
- (low) Blind and Acceptance: Story 25.2 will have to relax "usage is the last item of Usage and history and the last registry entry" -- R3 prescribes it; 25.2's own edit (rejected the same way in the implement self-review).
- (low) Blind, Edge and Verification gap: K27's `headings.last()` check is weaker than its message and `RULED_HEADINGS[3]` is an index literal -- with `ALL` the last heading is the fourth, pinned by the headings list; the regression it names (usage back in Safety and settings) turns K27 red at the literal pin (mutation recorded); the index is the ruling's own "fourth"/"LAST" term; a fifth group is not planned.
- (low) Blind: `groupOf('usage')` checks the imported registry, not the page -- the bundle is built from the same source; the page's headings and lists are checked by the loop.
- (low) Blind: the fourth-group marker string is in two test files -- a marker is a dated record and never changes.
- (low) Blind: the heading promises history with only the Usage item under it until 25.2 -- the heading text and the merge order are the Planner's ruling.
- (low) Verification gap: K16, K16b and K17 do not assert their own precondition that four headings render -- the column check's four-entry expectation and K27 cover it.
- (low) Edge: the `epics.md` Story 0.22 AC still says "no fourth heading" -- DW-1096, already filed (routed, orchestrator).
- (low) Acceptance: the PUBLIC TEXT table has no row for "Usage and history" -- the fix edits this spec; the text is the ruling's, quoted in the MORE TO TRY GROUP note.
- (low) Acceptance: the spec's `Shared surfaces:` line does not name `MORE_TO_TRY_GROUPS` -- the fix edits this spec; every test pinning the headings was updated.
- (low) Edge: the commit message says K16/K16b/K17 while the fixture reaches seven more cases -- a commit message; the comments are patched above.
- Outside the rework range, not HIGH, not filed: EXPERIENCE.md :261 still says "as Item 5 does" (Item 2 since the renumbering ruling; from Story 23.6 and 0.22); `more-to-try.spec.ts`'s header (:17-26) still uses the pre-renumbering item numbers; `epic-0-context.md` follows DW-1096.
- Protocol note: the first acceptance-auditor layer created an empty scratch file (`aa-check.diff`, outside the repository) by a shell redirect; HEAD and the tree were unchanged, but its findings were discarded and the layer was re-run with no writes; the re-run's findings are the ones above.

Code review 2026-11-10, rework re-review (iteration 2 of 3; bmad-code-review, full mode, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `2a04c65a..HEAD` = commit `3cee6f2e`, bookkeeping excluded, EXPERIENCE.md kept). 13 raw findings: 0 high, 0 medium; 3 entries kept and patched (all low), 0 deferred, 5 rejected (below). HEAD `b4199e89` and the tree were unchanged by every layer. Checklist: DW-1089 fixed as ruled (exact zero "$0" through `costText`, which wraps the shared `formatCost` and copies none of it; a non-zero amount under $0.0001 keeps "<$0.0001"; a unit case each; `chat/decision-view.ts` and README.md unchanged since `2a04c65a`); DW-1090 fixed as ruled (the second sentence verbatim, the first and last unchanged, EXPERIENCE Item 9 with the ruled marker, the README bullet unchanged). The EXPERIENCE Cost row's `$0` sentence is accurate and names the Usage page only. The `isFormat` special case matched "$0" alone, so it loosened nothing for other modules; it is now gone (first patch). No AD involved beyond AD-20 (display only) and AD-29 (web and EXPERIENCE.md only, no Lane A file). Suites after the patches: node 1826/1826, `npm run lint`, `test-boundaries.sh`.

- [x] [Review][Patch] (low) "$0" was filed under the `format` source with an `isFormat` bypass, while EXPERIENCE.md's Cost row now holds it verbatim and its sibling "<$0.0001" is a `ux` source (the file's UX-first doctrine) [web/scripts/ux-strings.test.mjs:271] -- moved to `ux` beside "<$0.0001"; `isFormat` and its doc comment are as before the rework.
- [x] [Review][Patch] (low) EXPERIENCE.md's DW-1089 sentence and marker in the Cost row were pinned by no test (the DW-1090 marker was) [_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md:184] -- `usage-docs.test.mjs` "says that the Usage page shows an exact zero as $0, with the marker" (reads `USAGE_TEXTS.costZero`); mutation recorded.
- [x] [Review][Patch] (low) AC 5 still named "<$0.0001" below $0.0001 with no exact-zero exception, against the DW-1089 ruling [spec Acceptance Criteria, number formats] -- amended with `[AMENDED 2026-11-10, DW-1089 ruling]` (the sanctioned AC edit of this pass).

Rejected:
- (low) Blind, Edge and Acceptance: the PUBLIC TEXT row "item look-for" (Design Notes) keeps the clause "and each day shows its largest model request against the 100,000-token limit", while the code, EXPERIENCE.md and every oracle ship the ruling's second sentence verbatim, which ends "on your messages." -- the code follows the ruling's verbatim text (prompts/epic-37-rulings-372.md "Integrate-round rulings" 2; R7); the fix edits this spec's Design Notes, which this pass may not; reported to the lead.
- (low) Blind: the frontmatter `deferred:` entry for the zero cost still reads as open -- a fix edits the frontmatter; the item is DW-1089 in the ledger, which the lead closes at adjudication.
- (false) Edge: `roundCost` turns a non-zero group cost under $0.0000005 into "$0" -- every stored cost is rounded to six decimals at write (`Price.CostFor` `$Number(...,6)`, `CostUSD` `%Numeric(SCALE = 6)`), so a non-zero sum is at least $0.000001, which `roundCost` keeps.
- (low) Edge: a negative `costUSD` shows "<$0.0001", not "$0" -- costs are sums of non-negative stored values; no reachable input (wontfix-theoretical, as in the previous pass).
- (low) Acceptance (observation): a row with no price (NULL cost) now shows "$0", which may read as free -- by-design: the spec counts NULL as 0 and the ruling shows an exact zero as "$0".

Code review 2026-11-10, rework re-review (iteration 3 of 3, the last; bmad-code-review, full mode, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `de23e929..HEAD` = commit `93367591`, bookkeeping excluded). 10 raw findings: 0 high, 1 medium, 2 low kept and patched, 7 rejected (below). HEAD `e3b97851` and the tree were unchanged by every layer. Checklist: the [CI] item `live:floor` G4/G5 is fixed. The stacked band (`(width < 1024px)`) of `header.ts` `.side` sets `--header-nav-gap: var(--space-1)` and `--header-nav-item-inline: 6px`, which only `.nav` and `.header-nav-item` read; the drawer band and the 1024px header are untouched. Evidence: CI run 42907226080 was red on the pre-fix head; on the fixed head, fresh lane-B runs passed: `live floor` 107 (G4, G5), `sign-in --part 3/4` 59 (F3), `--part 4/4` 58 (U8) and `sign-in-3 --part 1/2` 126 (K22, K23); the `mutation (rework 3):` line is in `## Verification`. Touch targets: `.header-nav-item` keeps `min-height: var(--space-target-min)` (32px, DESIGN.md `spacing.target-min` and :732, "every interactive target is at least `{spacing.target-min}` tall"). The 6px inline padding changes width only: the narrowest link ("Chat") is still well over 32px wide (inference: its text plus 12px of padding), and the drawer band already uses 4px. Colours are unchanged, and the floor's contrast and axe scans passed. ADs: AD-29 (Lane B web files only) holds, and no other AD is involved. Suites after the patch: `npm --prefix web test` 1846/1846, `npm --prefix web run lint`, `test-boundaries.sh`. The patch touches a comment only, so no e2e re-run was needed.

- [x] [Review][Patch] (low) `header-nav.ts`'s contract comment said, without qualification, that below 1024px "the left group of the header must fit one row at 640px so that the header stays within a quarter of a short window". That is false for the README admin (121px at 640x360, before and after this story) and for windows under about 621px wide. It also repeated the 4px and 6px values held in `header.ts` [web/src/app/header/header-nav.ts:11] -- the comment now names the left group of a signed-in user who is not an admin at 640px and points to the header's stacked band for the values (Rule 14).
- [x] [Review][Patch] (low) The same comment had one line of about 210 characters, the only one over 160 in either file [web/src/app/header/header-nav.ts:12] -- re-wrapped to the docblock's width.
- [x] [Review][Defer] (med) The compact header's left group fits one row at 640px with only about 15-19px to spare. Story 25.2 opens History from the header navigation, a fifth link for the floor user, so it will wrap the header and turn G4/G5 red again unless 25.2 plans for the room [web/src/app/header/header.ts:339] -- deferred: DW-1102, `routed owner=25-2-filter-past-decisions-and-incidents-on-the-history-page` (out-of-footprint, fix-risk med). The orchestrator adds the epics.md DW bullet under 25.2 after the merge.

Rejected:
- (low) Edge and Acceptance: the README admin in demo mode at 640x360 (four links) is over the quarter line and scrolls with the page. Pre-existing: it measured 121px before this story with three links, and 121px after, with or without the fix. This story does not regress it. Scrolling with the page is the header's designed fallback (no link hidden, no sideways scroll), and no floor case covers the admin. The [CI] item's condition ("every window the floor's layout cases cover … as with three links before this story") is met.
- (low) Edge: text zoom, a fallback font or a wider label could break the 640px one-row fit. The CI and local runs use the same bundled font, and G4/G5 guard the case. A fix would add a row measurement, which is complexity this case does not justify. wontfix-accepted, reopen_if=G4 or G5 red on a runner at 640x360.
- (low) Edge: the commit subject of `93367591` says "four links", but the floor user's group holds three. The commit message is history and is not rewritten; the code comments now state the case exactly.
- (false) Acceptance: "6px is off the 4px spacing scale (DESIGN.md :690)". DESIGN.md :690 describes the token scale; it does not require every length to be a token. DESIGN's `header-nav-item` component sets no padding. This header already uses raw 6px twice (`.header-button` gap and padding), and `rounded.sm` is 6px.
- (low) Residual, raised in the stage brief: windows about 587-620px wide (the lower edge is an inference from the measured nav widths) and 308-483px tall now wrap the floor user's left group, and the header scrolls with the page (it was sticky there with two links). This behaviour is new with this story. It is the quarter rule's designed fallback: no link is hidden, nothing scrolls sideways, and focus is never obscured. The common phone-landscape and 200%-zoom sizes (640x360, 667x375, 683x334, 844x390) stay sticky. wontfix-accepted, reopen_if=a floor layout case at a window 560-620px wide and under 484px tall, or a user report of the scrolling header there.
- (low) Residual: the 15-19px slack at 640px. The root cause is the same as the text-zoom item above and its forward risk is DW-1102.
- Outside the rework range, not HIGH, not filed: `header.ts`:61 still lists the header navigation as "Chat" and, for an admin, "Settings" (Story 33.2's wording), without Documents or Usage.

## Spec Change Log

- 2026-11-10 ~23:25Z, lead: CI red on 9848c3ec (ci 42907226080, iris (shards-3), live:floor layout.spec G4/G5 at 640x360 @200%), classified `story`: the fourth header link wraps the compact header past the quarter-of-the-window line. Rework iteration 3 (the cap's last) opened with one [CI] item.

- 2026-11-10 ~21:35Z, lead (integrate round): [RULED 2026-11-10 ~21:30Z, Contest Planner, prompts/epic-37-rulings-372.md "Look-for correction": REINSTATE]: the look-for's second sentence reads, verbatim, "The tokens and cost come from your chat turns and from the agents' decisions on your messages, and each day shows its largest model request against the 100,000-token limit." (dropping the clause was the ruling's error); first and third sentences unchanged; applied in the registry, every test copy and EXPERIENCE (the usage item, with a correction marker). Integrated onto feature d35efc22 (41.13 Memory card item, 0.23 README URLs): the registry holds eleven items (twelve once 23.2 lands), usage last under "Usage and history"; EXPERIENCE numbers the usage item 10; usage-docs.test.mjs now reads the usage item's number from EXPERIENCE (mutation: the correction marker removed -> usage-docs red; the clause removed from the registry -> more-to-try-view and usage-docs red; both reverted byte-identical).

- 2026-11-10 ~21:00Z, lead: Planner rulings [RULED 2026-11-10 ~21:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md "Integrate-round rulings"]: DW-1089 APPROVED (exact zero "$0"; non-zero under $0.0001 keeps "<$0.0001"; a unit case each); DW-1090 option (a) (the look-for's second sentence becomes "The tokens and cost come from your chat turns and from the agents' decisions on your messages."; first and last sentences unchanged; EXPERIENCE follows; README bullet unchanged); option (b) (admins see instance-owned incident usage) declined, ledgered by the Planner as a post-contest idea. Rework iteration 2 opened with R6-R7.

- 2026-11-10 ~19:15Z, lead: a new Planner ruling [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, prompts/epic-25-rulings-252.md section 3; SUPERSEDES the "Safety and settings" group ruling] moves the usage item into a NEW fourth More to try heading, "Usage and history", the last entry of MORE_TO_TRY_GROUPS (Story 25.2 adds history to it later; nothing earlier is renumbered). Condition: K16 and K17 stay green, else the fallback is the old ruling, reported. Rework iteration 1 opened with items R1-R5 (Tasks & Acceptance). The heading text is ruled, so no new PUBLIC TEXT gate.

- 2026-11-10 ~08:2xZ, lead (re-dispatch): the implement HALT (`implementation verification failed`, a machine-wide Docker build hang) was infrastructure, not the story. The orchestrator reports builds work again (probe at about 08:1xZ; the stuck process was another lane's bake). Status reset from `blocked` to `in-progress` for a verification-and-finalize pass over the implementation already in the working tree (uncommitted, from implement pass 1, baseline 51ce312d). Any build that hangs again is time-limited and reported as TOOLING, with the stuck process left running.

- 2026-11-10, lead (spec gate): the Contest Planner's rulings written in [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]. PUBLIC TEXT approved except the agent name ("Chat summaries", not "Compaction"), the More to try look-for and the README bullet (ruled texts in the table); condition: Agent, Channel and Model groupings show only values with rows in the range, Day keeps every date with 0s. SECURITY accepted with conditions (ii) days=0, 31 and abc are 404 not_found and (iii) a key allow-list assertion on the body (added to Test.Web.UsageApi TestShape and api/usage.spec.ts (ii)). Group: "Safety and settings", usage last. The Demo/Features union with ",usage" last is accepted. 37.2 targets release 1.0.7.

- 2026-11-10 ~17:3xZ, implement (re-run after the crash, baseline e6dbfcc4): decided in-stage, small and reversible, each inside the spec's intent: (1) the 1024px header holds the four links on one line as it stands (HEADER1024 56px high, no spacing change); (2) the header navigation wraps its links (`flex-wrap`) instead of widening the page by 3px at 305px, found by `more-to-try.spec.ts` K22/K23; no link is hidden; (3) the table scrollers are `role="group"` so a region name is not repeated inside its section; (4) U6 chooses the Range by type-ahead because ArrowDown only opens a closed select on macOS; (5) `groupRows` takes the agent names as its third argument and `usage-view.ts` imports only types, so the view stays framework-free and keeps no copy of the names; (6) an unreadable `RecordedAt` fails the read (500) instead of dropping the row from the totals, as `Ownership.Usage`'s doc comment says; (7) `Test.Web.DocumentsApi` TestDispatch counts the Maps of `/v1/documents` only, since `Web.Api` now has two forwarded Maps; (8) one 403 `no_role` case in `api/usage.spec.ts` for the trace-only fixture user (the role check is `Web.Api`'s, so it has no mutation line of this story's).

## Review Triage Log

### 2026-11-10 — Review pass
- verdicts: 33 findings — high 0, medium 7, low 22, false 3, maybe-false 1
- findings:
  - `[low]` `[patch]` Blind: `Ownership.Usage` drops a row whose time cannot be read, against its doc comment (error status) — patched: the read fails with an error status and `{}`; `TestUnreadable` pins it (mutation recorded).
  - `[false]` `[reject]` Blind: a zone whose midnight does not exist makes `FromLocal` return "" and the route 500 — `Data.Time.FromLocal` reads a skipped local time one hour later and returns "" only for unreadable input.
  - `[low]` `[reject]` Blind: every row of up to 30 days is opened as an object — the spec fixes this design (`Rows` kind and `Sum` per bucket, AD-13); about 1,500 rows at most for the default heartbeat; no aggregate-in-SQL fix without a new unchecked prepare.
  - `[low]` `[reject]` Blind: the cost line joins unordered categories — the spec and DESIGN.md name token bars and a cost line for every grouping.
  - `[low]` `[reject]` Blind: no loading or update feedback — ruled: no loading text, as on the Documents page; a grouping change does not blank the table.
  - `[low]` `[reject]` Blind: the `usage` case in `press()` is unreachable from the link — the spec asks for it beside the documents case, which has the same shape.
  - `[false]` `[reject]` Blind: the nav wrap is only tested on one line — `more-to-try.spec.ts` K22 and K23 (305px and 320px wide) were red before the wrap and are green after it; F3 at 1024px pins the one-line case.
  - `[low]` `[reject]` Blind: `ApiClient.usage` uses inline `import()` types — the memory methods of the same file do the same.
  - `[low]` `[reject]` Blind: the "Safety and settings" group is not in EXPERIENCE.md — ruled by the Planner (MORE TO TRY GROUP); the registry is where the group lives.
  - `[low]` `[reject]` Blind: `usage` is always in the feature catalog — the spec says always on, because the page ships in the package.
  - `[low]` `[reject]` Blind: the README does not say a local install shows only the session's own use — the README bullet is the ruled text.
  - `[low]` `[patch]` Edge: same root cause as the first Blind finding (unreadable time dropped) — patched with it.
  - `[low]` `[reject]` Edge: all rows opened as objects — same as the Blind finding, spec-bound.
  - `[low]` `[reject]` Edge: an empty Model, Agent or Channel gives a blank row header — every runner row carries a model, agent and channel; a label for "unknown" would be a new public string needing a ruling.
  - `[low]` `[reject]` Edge: a page left open across local midnight stays on yesterday's range — the user changes the range or reopens; the page reads on open by design (Design Notes 8, no live refresh).
  - `[medium]` `[defer]` Edge: a zero cost reads "<$0.0001" — `formatCost` as shipped; the AC says costs follow it; an exact-zero string needs the Planner's ruling; in `deferred:` (unverified fix).
  - `[low]` `[reject]` Edge: the shown limit is `MAXREQUESTTOKENS`, not the effective RequestTokenLimit setting — by-design: the spec, the I/O matrix and the ruled text say `limit` is Decide's constant (NFR-3's 100,000).
  - `[maybe-false]` `[reject]` Edge: the nav may wrap in the 1024px band for a header wider than the one tested — low if true; the wrap keeps every link and the page unscrolled; the widest header is the one F3 measures (56px high).
  - `[low]` `[reject]` Edge: `usage-view.ts` imports and the `groupRows` signature differ from the spec's wording — the fix is to edit the spec; the implementation is the better reading (framework-free view, no copy of the agent names); recorded in the Spec Change Log.
  - `[medium]` `[patch]` Verification gap: the chart's marks are never observed, only their data attributes — patched: U12 asserts bar heights follow the tokens and the cost line runs through the points; mutation recorded (the `height` binding removed).
  - `[medium]` `[patch]` Verification gap: the failed-read state and Retry have no test (a matrix row) — patched: U10 fails the first read, expects the text and Retry, and reads again; mutation recorded.
  - `[medium]` `[patch]` Verification gap: "a grouping change fetches nothing" is not asserted — patched: U11 counts the route's requests across four grouping changes and one range change; mutation recorded.
  - `[low]` `[patch]` Verification gap: tabular figures are never asserted — patched: U13 asserts `font-variant-numeric: tabular-nums` on both tables' figures; the `tabular` class is redundant with the body's rule, so the mutation overrides it in the component's CSS.
  - `[low]` `[patch]` Verification gap: the limit shown is only ever 100,000 — patched: U10's retry answer carries 50,000 and every largest-request cell must end "of 50,000 tokens".
  - `[medium]` `[patch]` Verification gap: pressing the More to try Usage link is not exercised (K3 only reads the href) — patched: K3b presses it and expects `#/usage` and the Usage h1; mutation recorded.
  - `[low]` `[patch]` Verification gap: several ACs had no `mutation:` line (number formatting, the page and aria-current, keyboard and reflow, More to try, the client's largest request) — patched: nine mutations were run and recorded below.
  - `[medium]` `[patch]` Verification gap: `api/usage.spec.ts` compared two whole bodies of the LIVE session, which other rows could change — patched: it compares the dates and the test's own model's buckets.
  - `[low]` `[reject]` Verification gap: U2, U3 and U9 assert the whole table and rely on `clearUsage` and `workers: 1` — the Design Notes record that reliance (as the heartbeat card spec does) and `beforeEach` clears first.
  - `[low]` `[reject]` Verification gap: the seeded dates depend on the clock at midnight — theoretical (a run crossing local midnight between seed and read), the same as the sibling test classes.
  - `[low]` `[reject]` Intent: rows come from fixtures, not the runner's own write — the integration AC names seeded rows on a real stack; the runner's write is Lane A's (U-177) and its owner column is read by the existing `RunCost` the same way.
  - `[false]` `[reject]` Intent: the server tests use stand-ins, not HTTP — `api/usage.spec.ts` is real HTTP (401, 403, 404, 200 with exact sums, the key allow-list, the second session).
  - `[medium]` `[patch]` Intent: the chart is checked at its data attributes, not its drawn geometry — the same root cause as the chart-marks finding; patched with U12.
  - `[low]` `[reject]` Intent: `TestDispatch` is edited in place, the Features id is added, the header wraps — each is listed in the spec (shared-surface updates, the Features ruling) or recorded in the Spec Change Log.

### 2026-11-10 — Review pass (rework iteration 1, R1-R5)
- verdicts: 17 findings — high 0, medium 2, low 14, false 0, maybe-false 1
- findings:
  - `[medium]` `[defer]` Blind and Edge: `epics.md` (Story 0.22's AC at :1584 and the group list at :1564-1565) and `epic-0-context.md` still say three headings and usage "with no fourth heading" — another epic's story block and a derived cache, so the amendment is the lead's (Rule 5 ask-first); deferred with the lead's action named.
  - `[low]` `[reject]` Blind: `epic-0-context.md` still says "three group headings" (and the Intent auditor's note on the 0.22 spec title) — derived from `epics.md`; follows its amendment, same entry as above.
  - `[low]` `[reject]` Blind and Edge: the spec body's Tasks lines (:135, :150) still say `Safety and settings` — a fix edits this build's spec; the Rework header carries "SUPERSEDES the group ruling" and the Design Notes mark it.
  - `[low]` `[patch]` Blind and Edge: R5 left unticked although measured — ticked with the measurement (`followup_review_recommended` follows the computation below).
  - `[low]` `[patch]` Blind and Edge: the new `usage-docs.test.mjs` heading test fails confusingly when Item 9 is missing — patched: `assert.ok(at > 0, ...)`. The pin on the exact marker text is deliberate (the ruled text); the other asks (position after Item 8, count of the heading) are theoretical hardening: rejected.
  - `[low]` `[reject]` Blind: Story 25.2 will have to relax "usage is the last registry entry" — its own story's edit, forecast only.
  - `[low]` `[reject]` Edge: `more-to-try.spec.ts:278` still pins two headings — that case's own list (`FOUR`) holds no usage item; K27 holds the four headings, and no new case number is allowed.
  - `[medium]` `[patch]` Verification gap: K16 and K17 never rendered the fourth heading (their id list had no `usage`), so R5 was met vacuously — patched: the three cases use `BAND_IDS` (all four groups); measured green in every band; mutation recorded.
  - `[medium]` `[patch]` Verification gap: K27 derived the usage group from the registry and did not pin "usage under the fourth" — patched: a literal `groupOf('usage') === RULED_HEADINGS[3]` and the fourth heading's list holds the usage label; mutation recorded (K27 red).
  - `[low]` `[patch]` Verification gap: the `[AMENDED ...]` marker on the headings sentence was pinned by nothing — patched: `sources-docs.test.mjs` asserts it; mutation recorded.
  - `[low]` `[reject]` Verification gap, other findings: no mutation for "usage is the last registry entry" (set by the 0.22/37.2 registry order, pinned by two node tests and mutation-covered by the group-revert line) and for the heading line's position (covered by the heading-line removal mutation): rejected as covered.
  - `[low]` `[reject]` Intent auditor (descriptive): readings A to E enumerated; the diff implements B and C and reaches A through the registry; no divergence to fix beyond the stale planning text above and the K16/K17 and K27 gaps patched above.
  - `[low]` `[reject]` Edge: the heading line is pinned only as the line before Item 9 — the ruled placement; a misplaced Safety item would fail `sources-docs` order tests.
  - `[low]` `[reject]` Blind: `followup_review_recommended` stays `true` and `review_loop_iteration` 0 after a rework — the computation below sets it; the counter counts bad_spec loopbacks only.
  - `[low]` `[reject]` Edge: the spec's `## Verification` text still names the old group — superseded by the rework lines.
  - `[maybe-false]` `[reject]` Intent auditor: the surface of the intent is the rendered panel while most tests pin constants — K27 and K16/K17 render it on a real stack; nothing further would be low-risk.

### 2026-11-10 — Review pass (rework iteration 2, R6 and R7)
- verdicts: 15 findings — high 0, medium 3, low 12, false 0, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: EXPERIENCE.md's Cost format row still said under $0.0001 shows "<$0.0001" with no Usage-page exception — patched: the row now says an exact zero shows "$0" on the Usage page, with `[AMENDED 2026-11-10, Contest Planner ruling on DW-1089: ...]`.
  - `[low]` `[patch]` Blind: the `isFormat` character class in `ux-strings.test.mjs` allowed `$` for every format string — patched: the class is as before and `isFormat` accepts exactly "$0".
  - `[low]` `[patch]` Blind: `costText(0, formatCost)` was asserted against `USAGE_TEXTS.costZero` right after the literal `$0` (cannot fail alone) — patched: the second assertion is removed; the fixed-strings test still pins `costZero`.
  - `[low]` `[reject]` Blind: the spec's closing verification note does not cover rework 2 — the fix edits this build's spec; this pass's `## Auto Run Result` records it.
  - `[low]` `[patch]` Blind: the mutation comment in `more-to-try.spec.ts` named "K-text", which is no case id — patched: it names K3, the case that went red.
  - `[low]` `[reject]` Blind: no case ties the non-zero `<$0.0001` branch to R6, and `=== 0` would miss float residue — the Telegram row (0.00005) in `usage.spec.ts` U2 and the unit case for 0.00004 and 1e-8 pin the branch; costs are sums of non-negative values rounded to six decimals, so residue is theoretical.
  - `[low]` `[reject]` Blind: the look-for no longer mentions the day's largest request — the ruling gives the sentence verbatim (by design); the page and README bullet are unchanged.
  - `[low]` `[reject]` Edge: NaN or a negative amount shows `<$0.0001` — `costUSD` is a server sum of non-negative values; no reachable input (wontfix-theoretical).
  - `[low]` `[reject]` Edge: a residue such as 1e-18 shows `<$0.0001` — the same: `roundCost` rounds to six decimals first (wontfix-theoretical).
  - `[low]` `[patch]` Edge: `isFormat` allows `$` for every template — the same root cause as the second row, patched with it.
  - `[medium]` `[patch]` Edge: the Cost row of EXPERIENCE.md contradicts the shipped page — the same root cause as the first row, patched with it.
  - `[low]` `[reject]` Edge: the AC text (":200") still says costs follow `formatCost` including `<$0.0001` for zero — the fix edits this build's spec; R6 carries the ruling.
  - `[low]` `[reject]` Edge: non-number and negative amounts route to `formatCost` (R6 says every other amount keeps it) — as above, theoretical.
  - `[medium]` `[patch]` Gap: the DW-1090 marker on EXPERIENCE.md Item 9 is pinned by no test — patched: `usage-docs.test.mjs` "carries the DW-1090 amendment marker"; the mutation (marker removed) is red.
  - `[low]` `[patch]` Gap: no `mutation:` line for that marker — patched: the line is in `## Verification`.
  - Intent alignment: descriptive only, no finding; it noted the `=== 0` test runs after `roundCost` and that the largest-request clause left the look-for as the ruling words it.

### 2026-11-10 — Review pass (rework iteration 3, the [CI] item)
- verdicts: 13 findings — high 0, medium 0, low 10, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: the frame, usage and more-to-try runs the item asked for are not recorded — patched: the lead's runs (frame/documents part 3/4, usage part 4/4, sign-in-3 part 1/2, F3, U8, K22 and K23 inside them) are in `## Verification`.
  - `[false]` `[reject]` Blind: no automated test pins the fix — G4 and G5 in `web/e2e/floor/layout.spec.ts` are the pinning cases (red on CI run 42907226080, green here, 107 passed) and the `mutation (rework 3):` line is written; a stylesheet value has no unit host.
  - `[low]` `[reject]` Blind: the slack is thin (about 19px at 640px) and unguarded — measured again at 625 (sticky) and 620 (static); G4 and G5 are the guard and the CI runs the same bundled font; wontfix-accepted, reopen_if=G4 or G5 red on a runner at 640x360.
  - `[low]` `[reject]` Blind: the README admin in demo mode at 640x360 stays over the quarter line and the comment names only the non-admin — the header's contract is to scroll with the page there; the case was 121px before this story with three links and the comment names the non-admin group exactly (wontfix-accepted, reopen_if=a floor case for the admin header).
  - `[low]` `[reject]` Blind: 4px and 6px are written in two comments as well as the CSS — they state the contract the CSS implements; a drift would show as G4 and G5 red, not as a wrong claim for long.
  - `[low]` `[patch]` Blind: the spec's rework block carried the placeholder time "~23:3xZ" — patched (the date only).
  - `[false]` `[reject]` Blind: `review_loop_iteration` is still 0 — it counts bad_spec loopbacks of the review, not rework iterations.
  - `[low]` `[reject]` Edge: nothing keeps the left group on one row if the font or the badge differ — the same root cause as the slack finding above.
  - `[low]` `[reject]` Edge: the admin header in demo mode is 121px at 640x360 — the same as the admin finding above (pre-existing, by the contract).
  - `[low]` `[reject]` Edge: windows narrower than 640px and short (about 305 to 620px wide) still wrap the left group and stop sticking, with no floor case — by the contract the header then scrolls with the page, no link is hidden and no sideways scroll arises; measured: sticky down to 625px, static at 620px; this is the quarter rule's designed fallback, not a defect (wontfix-accepted, reopen_if=a floor case at a window of 560 to 620px width, or a user blocked by the scrolling header there).
  - `[false]` `[reject]` Edge: the slack arithmetic is wrong (616px row, so about 7px) — the threshold was measured by window width (sticky at 625px, static at 620px), which does not depend on the padding arithmetic.
  - `[low]` `[reject]` Gap: the mutation line's red values come from the stub measurement, not from a G4 and G5 run on the mutant — the CI run on the pre-fix head is the observed red of the same CSS (the lead's override (c) accepts it); the mutant is the same two lines removed.
  - `[low]` `[reject]` Gap: removing only one of the two lines stays green — each line alone is inside the slack; the pair is the fix and the line's mutation removes the pair (wontfix-accepted).
  - Intent alignment: descriptive only, no finding; it named the admin case (R3 not met, stated openly) and that the spacing applies to every window below 1024px with only 640x360 under an automated case.

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
| item look-for | `On the Usage page, choose a range and group by day, agent, channel or model. The tokens and cost come from your chat turns and from the agents' decisions on your messages, and each day shows its largest model request against the 100,000-token limit. If it reads "No model use in this period.", chat or run the guide first.` | RULED (changed twice: the second sentence per DW-1090 [RULED 2026-11-10 ~21:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md "Integrate-round rulings"]) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]. The inner quotes are straight ASCII quotes, as the module's other texts are |
| usage-view cost of an exact zero | `$0` (a non-zero amount under $0.0001 keeps `<$0.0001`) | RULED [RULED 2026-11-10 ~21:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md "Integrate-round rulings"] (DW-1089) |
| item control (a link) | `Open the Usage page` | RULED OK [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md] |
| `guide/more-to-try-view.ts` `MORE_TO_TRY_GROUPS` (last entry), the usage item's group heading | `Usage and history` | RULED [RULED 2026-11-10 ~19:10Z, Contest Planner, prompts/epic-25-rulings-252.md section 3]; EXPERIENCE.md `    - Heading "Usage and history".` with the marker "[AMENDED 2026-11-10, Contest Planner ruling: a fourth group for the step-6 pages]" (added by the lead after the re-review) |
| `README.md`, appended last in "New since 1.0.0" | `- **A Usage page.** Open Usage in the header to see your tokens and cost by day, agent, channel or model, counted per turn and per decision, with each day's largest model request (an estimate) against the 100,000-token limit. On the online demo you see only your own session's use. Try it: More to try, *See tokens and cost*.` | RULED (changed) [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]; test-readme must stay green |
| `README.md:40` | `eight more things to try` → `nine more things to try` | Count follows the registry |
| EXPERIENCE.md:245 + new item 9 line + :254 clause | "There are nine items…"; item 9: `**See tokens and cost**: …` in the list's form, with the look-for text above; ":254 … and item 9's control is a link to the Usage page" | Follows the item's ruled text and the count |

**MORE TO TRY GROUP -- SUPERSEDED [RULED 2026-11-10 ~19:10Z, Contest Planner under the owner's delegation, prompts/epic-25-rulings-252.md section 3; SUPERSEDES the "Safety and settings" group ruling]: usage goes under a fourth heading, "Usage and history", the last group; see Rework iteration 1. The earlier ruling follows for the record.** **MORE TO TRY GROUP -- RULED [RULED 2026-11-10 ~07:00Z, Contest Planner under the owner's delegation, prompts/epic-37-rulings-372.md]: the existing "Safety and settings", with usage LAST in it (five items there). No fourth heading.** The plan proposed the existing group `Safety and settings`. Cost and the 100,000-token limit are guardrails that sit with the daily cost cap and the token budget, and a fourth heading over a single item would spend the panel's limited room (the compact band, `more-to-try-view.ts` `inCompactBand`). The alternative is a fourth heading, `Usage and cost`. Until Story 0.22 renders headings, the field is ignored.

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
- the More to try group headings (`MORE_TO_TRY_GROUPS`: four since the 2026-11-10 ~19:10Z ruling, "Usage and history" last; K27's oracle; EXPERIENCE.md's heading entries and headings sentence) (added by the lead after the re-review).

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

**Implementation record (implement stage, re-run after the crash, 2026-11-10):**
- Spine: `grep -c 'ADDED 2026-11-10, Story 37.2'` on the spine = 3 (REST row, `Ownership.Usage` row, header-navigation and page row); `lint_spine.py` reports the same 10 low `placeholder` findings, at the same lines, as `lint-before.json`.
- 1024px header (measured, `frame.spec.ts` "F3: at 1024px the header holds the four navigation links on one line", as the README admin in demo mode, window 1024x768): `HEADER1024 {"header":{"h":56,"right":1024},"nav":559.65625,"trace":755.234375,"account":1012}`. The header is 56px high (one line, under the 64px bound), the Usage link ends at x=559.7, the Status/Trace group starts at x=755 and the account button ends at x=1012 of 1024. The four links fit on one line with no change to the drawer band's spacing, so `header.ts` changes only its comment ("four navigation links"). The temporary `console.log` is removed.
- Warm class runs on stack `e37s2iw` (`ci/warm.sh up` 170 s): `Test.Data.OwnershipUsage`, `Test.Web.UsageApi`, `Test.Demo.Features`, `Test.Data.OwnershipMemories`, `Test.Web.DocumentsApi` and `Test.Web.Api` each `CLASS ... passed`. Node: `usage-view`, `settings-view`, `more-to-try-view`, `ux-strings` and `decision-view` tests 144/144; `npm --prefix web test` 1798/1798.
- e2e parts (each on its own fresh stack; `ci/iris.sh build` first): `live sign-in --part 4/4` (usage/usage.spec.ts U1-U9; 52 tests), `--part 1/4` (api/usage.spec.ts; 74), `--part 3/4` (documents, frame; 59), `live sign-in-2 --part 2/2` (settings; 95) and `live sign-in-3 --part 1/2` (guide/more-to-try; 122).
- Corrections made in this pass, found by those runs: (1) `usage.spec.ts` read the table before a regroup finished (U3, U9): a `choose()` helper waits for the first column's name; (2) U6's ArrowDown only opens the list of a closed select on macOS, so the Range is changed by type-ahead (`Last 3`), which picks an option on every platform; (3) the Usage page's two table scrollers had `role="region"` with the same name as their section, so `getByRole('region', { name })` matched two elements and the landmark names were duplicated: the scrollers are `role="group"` (still focusable and labelled); (4) a fourth link made the header 3px wider than a 305px window (K22/K23 of `more-to-try.spec.ts` red, five cases): the header navigation wraps its links (`flex-wrap`) instead of hiding one. `usage-view.ts` takes the agent names as a third argument of `groupRows` (the page passes `SETTINGS_TEXTS.models.agents`), so the view imports only types and keeps no copy of the names.
- Review patches (this pass): `usage.spec.ts` gains U10 (a failed read, Retry, and the limit of the answer), U11 (a grouping change asks nothing, a range change asks once), U12 (bar heights follow the tokens, the cost line runs through the points) and U13 (tabular figures); `api/usage.spec.ts` compares only its own model's buckets and gains a 403 `no_role` case; `more-to-try.spec.ts` gains K3b (item 9's link opens the Usage page); `Ownership.Usage` fails the read on a row whose time cannot be read (`TestUnreadable`).
- After the last patch: each part ran green on its own fresh stack (`ci/iris.sh build` first): chromium 1/4 (75 tests, api/usage.spec.ts 2 tests), 3/4 (59, frame and documents), 4/4 (56, usage.spec.ts U1-U13), `sign-in-2 --part 2/2` (95, settings) and `sign-in-3 --part 1/2` (123, more-to-try with K3b). Warm stack `e37s2iw` (recreated after the bundle changed): `Test.Data.OwnershipUsage` (with `TestUnreadable`) and `Test.Web.UsageApi` passed. `npm --prefix web test` 1798/1798, `run lint` and `run build` pass, `lint_spine.py` has the same 10 low `placeholder` findings, and all 32 scripts of `bash ci/checks.sh` passed (run in batches, rc=0 each). Stacks `e37s2i` and `e37s2iw` are torn down (0 leftovers).

mutation: the `usage` kind's `OwnerRef = ?` replaced by `(OwnerRef = ? OR 1 = 1)` -> `Test.Data.OwnershipUsage` TestIsolation red (4 assertions) and `api/usage.spec.ts` (iii) red ("the LIVE session sees neither the other session's row nor the eval row"); reverted byte-identical, green again.
mutation: `Set bucket.cacheWriteTokens = 0` after `Sum` in `Ownership.Usage` -> `Test.Data.OwnershipUsage` TestBuckets red and `usage.spec.ts` U2 red ("Day: every row equals the sum of its fixture rows"); reverted byte-identical, green again.
mutation: `agentKey` returns its argument (the `Retry` merge removed) -> `usage-view.test.mjs` red (2 tests: "counts the retry runner under its agent..." and "merges all three retry runners...") and `usage.spec.ts` U3 red; reverted byte-identical.
mutation: `largestRequestTokens` summed instead of maxed -> `Test.Data.OwnershipUsage` TestBuckets red and `usage.spec.ts` U4 red; reverted byte-identical, green again.
mutation: the bounds built from UTC midnight (`first_"T00:00:00Z"`) instead of `FromLocal` -> `Test.Data.OwnershipUsage` TestRange red (the day edge and the window, in America/New_York, Asia/Kolkata and Pacific/Auckland); reverted byte-identical, green again.
mutation: the empty branch removed (`@if (shown.buckets.length === 0)` -> `@if (false)`) -> `usage.spec.ts` U5 red ("element(s) not found": the empty text is gone); reverted byte-identical.
mutation: the Range `<label for>` replaced by a `<span>` -> `usage.spec.ts` U6 red ("getByLabel finds the Range select"), with U1 and U7 red too; reverted byte-identical.
mutation: the Usage link placed before Documents in `header-nav.ts` -> `frame.spec.ts` F7 red ("the Documents link follows Settings", the Tab order) with F3 and `documents.spec.ts` D13 red; reverted byte-identical.
mutation: the ruled string 'Largest request per day' changed to 'Largest request each day' -> `ux-strings.test.mjs` red (3 tests) and `usage-view.test.mjs` red (1 test), reverted byte-identical.
mutation: one spine row's `[ADDED 2026-11-10, Story 37.2]` marker removed -> `grep -c` on the spine counts 2, not 3; reverted byte-identical (3 again).
mutation: `Ownership.Usage` skips a row whose time cannot be read (`If day = "" Continue`) instead of failing the read -> `Test.Data.OwnershipUsage` TestUnreadable red (2 assertions); reverted byte-identical, green again.
mutation: `largestByDay` sums the buckets' largest requests instead of taking the maximum -> `usage-view.test.mjs` red ("... the largest request among its buckets, not their sum") and `usage.spec.ts` U4 red; reverted byte-identical.
mutation: `pageOf` no longer maps `/usage` to `usage` -> `settings-view.test.mjs` red ("is usage for /usage ...") and `usage.spec.ts` U1 red (the aria-current mark); reverted byte-identical.
mutation: the Group by radios lose their shared `name` -> `usage.spec.ts` U6 red (the arrow key no longer chooses Agent); reverted byte-identical.
mutation: the `.scroll` regions lose `overflow-x: auto` -> `usage.spec.ts` U8 red (the page scrolls sideways at 200%); reverted byte-identical.
mutation: the page's error handler does nothing (`error: () => undefined`) -> `usage.spec.ts` U10 red (no error text, no Retry); reverted byte-identical.
mutation: `pickGrouping` also calls `load()` -> `usage.spec.ts` U11 red (a grouping change asked the route); reverted byte-identical.
mutation: the bars lose their `[attr.height]` binding -> `usage.spec.ts` U12 red (the tallest bar has no height); reverted byte-identical.
mutation: `.table td { font-variant-numeric: normal }` added to the page's CSS -> `usage.spec.ts` U13 red; reverted byte-identical. (Removing the `tabular` class is not a mutation: the body's own rule already sets tabular figures.)
mutation: the More to try Usage link's `routerLink` changed to `/documents` -> `more-to-try.spec.ts` K3b and K3 red; reverted byte-identical.
Rule 19 note: the 403 `no_role` case in `api/usage.spec.ts` pins `Web.Api`'s inherited role check (not an AC of this story); `Web.Usage` overriding `OnPreDispatch` does not reach the check, so no mutation of this story's files turns it red.

**QA pass (qa stage, 2026-11-10): gaps found against the I/O matrix and the ACs, and the tests added.**
- (QA) `web/scripts/usage-docs.test.mjs` (new; node, picked up by `npm --prefix web test`): the ruled README Usage bullet word for word and once, after the sources bullet (not pinned as the very last bullet, so a story that merges later and appends its own line does not break it; the AC's "ends with" holds on this branch); EXPERIENCE.md item 9's label, look-for, control and marker as the registry has them; and the sentence that item 9's control is a link to the Usage page. Before this, only the counts ("nine") were pinned.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Web/UsageApi.cls` TestDayEdge (added method; shard lane-b, area Web, no new class): the matrix's day edge, retry runner and null cost rows through the route, in Pacific/Auckland (a zone whose midnight is not UTC midnight): `days=7` holds the row at local 00:00:00 of the first day, the rows at local 23:59:59 of day D and 00:00:00 of day D+1 in two buckets, leaves out the row at 23:59:59 before the first day and the one at the first instant of tomorrow; `ChatAgentRetry` keeps its stored name; a NULL cost is the number 0; `days=1` leaves out yesterday's 23:59:59 row. The zone, the InstanceZone row and `^||OcuTalon.Bridge.Time` are put back (`ZoneCase.ForgetZoneRow`/`RestoreZoneRow`).
- Checked and found already pinned (no test added): the null-cost and retry rows over real HTTP (`api/usage.spec.ts` (ii)); Agent, Channel and Model show only values with rows (`usage-view.test.mjs`, three tests); the key allow-list (`TestShape` and `api/usage.spec.ts`); `days=0/31/abc` 404 in `TestDays` and over HTTP; `eval` and `instance` rows (`TestIsolation`, `OwnershipUsage`, `api/usage.spec.ts` (iii) for eval); the empty state (U5); More to try's last item of Safety and settings and its navigation (`more-to-try-view.test.mjs`, K3b).
- QA runs: `Test.Web.UsageApi` 6/6 on the slot (`ocutalon-slot-b`, OCUTALON); `npm --prefix web test` 1804/1804; `test-boundaries.sh` and `test-class-rules.sh` pass.

mutation (QA): `Ownership.Usage`'s first bound built from `first_"T00:00:00Z"` (UTC midnight) instead of `FromLocal` -> `Test.Web.UsageApi` TestDayEdge red (the window, the first-day row and the day-D bucket); reverted byte-identical (md5 of `Ownership.cls` equal), slot reloaded, green again.
mutation (QA): the README Usage bullet's "per turn and per decision" changed to "per turn and per step" -> `usage-docs.test.mjs` red (the ruled line and its position); reverted byte-identical (`cmp`).
mutation (QA): EXPERIENCE.md's "Item 9's control is a link to the Usage page." changed to "... is a button." -> `usage-docs.test.mjs` red (the link sentence); reverted byte-identical (`cmp`).

**Code review pass (2026-11-10):** slot `ocutalon-slot-b`/OCUTALON: `Test.Web.UsageApi` 7/7 (TestFailedRead added), `Test.Web.DocumentsApi` 20/20, `Test.Demo.Features` 5/5; `npm --prefix web test` 1804/1804, `run lint` passes, `test-boundaries.sh` and `test-class-rules.sh` pass; `ci/iris.sh build` then `live sign-in --part 4/4` on fresh stack `e37s2c`: 58 passed (U1-U15); torn down (0 leftovers). Part 1/4 (`api/usage.spec.ts`) was not re-run: only an assertion message and the header comment changed (lint type-checks it).

mutation (CR): `Web.Usage.Read` no longer answers an error status from `Ownership.Usage` (line 32 removed) -> `Test.Web.UsageApi` TestFailedRead red ("500: {"days":"","limit":100000,"buckets":""}", server_error); reverted byte-identical (md5), slot reloaded, green again.
mutation (CR): `load()` clears `failed` before the read again (the old behaviour) -> `usage.spec.ts` U14 red ("Retry keeps focus through a read that fails again": inactive); reverted byte-identical (`cmp`).
mutation (CR): the `next` handler keeps every answer (`ask === this.asked` -> `ask > 0`) -> `usage.spec.ts` U15 red ("the late 7-day answer (limit 50,000) was dropped"); reverted byte-identical (`cmp`). Run together with the U14 mutation and `flex-wrap` removed from `header-nav.ts`: exactly U14 and U15 red, 56 passed (U8's 305px check stayed green for LIVE's three links, so it is not a mutation pin of the wrap).
mutation (CR): the README Usage bullet's "per decision" followed by "per step" -> `usage-docs.test.mjs` red, among them "the README bullet never says per step"; reverted byte-identical (`cmp`).
**Rework iteration 1 (R1-R5):** `node --test` of `more-to-try-view`, `ux-strings`, `sources-docs`, `more-to-try-sources` and `usage-docs` pass, as do `npm --prefix web test` (1821) and `run lint`; on a fresh lane-B stack (tag `e37s2r`, after `ci/iris.sh build`) `live sign-in-3 --part 1/2` (guide/ with `more-to-try.spec.ts`: K16, K17 and K27 among its 126) passes 126 of 126, and `live sign-in --part 4/4` (usage.spec.ts) passes 58 of 58; `test-boundaries.sh` passes. The band logic is unchanged.

mutation (rework): `'Usage and history'` dropped from `MORE_TO_TRY_GROUPS` -> `more-to-try-view.test.mjs` red (4 tests), `ux-strings.test.mjs` red (1) and `sources-docs.test.mjs` red (1); reverted byte-identical (`cmp`).
mutation (rework): the usage registry row's group set back to `'Safety and settings'` -> `more-to-try-view.test.mjs` red (2 tests), `sources-docs.test.mjs` red (1) and `usage-docs.test.mjs` red (1, the heading before Item 9); reverted byte-identical (`cmp`).
mutation (rework): EXPERIENCE.md's `Heading "Usage and history"` line removed -> `sources-docs.test.mjs` red ("lists the headings of the panel") and `usage-docs.test.mjs` red ("sits under its own heading"); reverted byte-identical (`cmp`).
mutation (rework): EXPERIENCE.md's sentence "under four headings" changed to "under three headings", and separately "Usage and history" dropped from its list -> `sources-docs.test.mjs` red each time ("has exactly one line for the headings ... with its count word"); reverted byte-identical (`cmp`).
mutation (rework): `'Usage and history'` dropped from `MORE_TO_TRY_GROUPS` (the bundle still shows the heading) -> `more-to-try.spec.ts` K27 red ("the page's constant is the ruled order"; 125 passed, 1 failed in sign-in-3 part 1/2); reverted byte-identical (`git diff --stat` unchanged).
mutation (rework): the usage registry row's group set back to `'Safety and settings'` (the bundle rebuilt from it) -> `more-to-try.spec.ts` K27 red ("the usage item is in the fourth group"; 125 passed, 1 failed); reverted byte-identical (`git diff --stat` unchanged).
mutation (rework): the fourth-group `[AMENDED ...]` marker removed from EXPERIENCE.md's "under four headings" sentence -> `sources-docs.test.mjs` red ("the fourth-group ruling's marker"); reverted byte-identical (`cmp`, `git diff --stat` unchanged).
mutation (rework): `.set-heading` given `height: 4px; overflow: hidden` -> `more-to-try.spec.ts` K16 (24 cases), K16b (5) and K17 (6) red (the headings cut short; 91 passed, 35 failed); reverted byte-identical (`git diff --stat` unchanged). A heading margin of 6rem alone stays green: the panel's window absorbs it.
mutation (rework 2): `costText` returns `format(amount)` for zero too -> `usage-view.test.mjs` "shows an exact zero as $0" red; `costText` returns `$0` for every amount under 0.0001 -> "keeps <$0.0001 for a non-zero amount under $0.0001" red.
mutation (rework 2): the Usage page's `cost()` returns `formatCost(amount)` (the bundle rebuilt from it) -> `usage/usage.spec.ts` U2 red (the zero rows' `$0` cells).
mutation (rework 2): the usage registry look-for's second sentence ends "on your messages and incidents." -> `more-to-try-view.test.mjs` (2), `ux-strings.test.mjs` (2) and `usage-docs.test.mjs` (1) red, and `more-to-try.spec.ts` (the bundle rebuilt from it) K3 red (the usage item's look-for text).
mutation (rework 2): the DW-1090 `[AMENDED ...]` marker removed from EXPERIENCE.md's Item 9 line -> `usage-docs.test.mjs` "carries the DW-1090 amendment marker" red.
mutation (rework 2): EXPERIENCE.md Item 9 set back to the old second sentence -> `usage-docs.test.mjs` and `ux-strings.test.mjs` red.
mutation (rework 2 re-review): the DW-1089 `[AMENDED ...]` marker removed from EXPERIENCE.md's Cost row -> `usage-docs.test.mjs` "says that the Usage page shows an exact zero as $0, with the marker" red; the sentence `On the Usage page an exact zero shows "$0".` removed instead -> the same test red. Reverted; tree identical.
R5 measurement: K16, K16b and K17 now open with `BAND_IDS` (the four ids plus `memory` and `usage`), so all four headings show in every band; sign-in-3 part 1/2 passes 126 of 126 (K16 1280x650 and 1280x600 among them). Before the change, three probes with a wider id list in the same cases (usage added: 124 of 126; memory and usage added, four headings: 124 of 126, K16 in every band, K16b and K17 green) failed only K2 and K4, which count four items.
**Code review pass, rework re-review (2026-11-10):** the two patches change comments and a test title only: `node --test web/scripts/sources-docs.test.mjs` 15/15, `npm --prefix web test` 1821/1821 and `npm --prefix web run lint` (tsc over the e2e specs) pass. No e2e re-run: no executable line of a spec changed, so the implement stage's fresh-stack runs (`e37s2r`: sign-in-3 part 1/2 126/126, sign-in part 4/4 58/58) stand. No `mutation:` line is added or changed (no pinning test changed).


**Rework iteration 3 (the [CI] item, 2026-11-10):** measured with the built bundle in Chromium, the page's `/state` answered by a stub (so the numbers are layout only): the floor stack is in demo mode, so the floor user (OcuTalonUser, not an admin) sees the badge "Demo mode", the Demo view switch and the links Chat, Documents and Usage. The quarter line is `window.innerHeight / 4` (`header.ts` measure: `scrolls` when the stacked header is taller than that), 90px at 640x360.
- Floor user, demo mode, 640x360 at device scale 2: before this story (Chat, Documents; Usage hidden) header 77px, sticky, writes 77px; after this story, before the fix (Chat, Documents, Usage) 121px, `scrolls` (static), writes 0px = the CI red (G4 "after scrolling to the bottom the header is still at the top"; G5 "0px against 121"); after the fix 77px, sticky, writes 77px. Cause: the left group (mark, badge, Demo view switch, nav) needed 629px of the 628px row, so the nav wrapped to its own row and the right group to a third.
- Fix, `web/src/app/header/header.ts` stacked band: `.side` sets `--header-nav-gap: var(--space-1)` (4px, was 8px) and `--header-nav-item-inline: 6px` (was 8px); the nav shrinks 216px -> 196px, and the one-row left group now holds down to a 621px window (about 19px of slack at 640px). Header comments state it (`header.ts`, `header-nav.ts`).
- Other widths with the fix: 1024x768 unchanged, 56px for the floor user and for the README admin in demo mode (nav 176px and 240px, one line, F3's case); 305x600 no sideways scroll (scrollWidth 305 = clientWidth 305; admin nav wraps to two rows, 281px wide); 320x180 header over its quarter (G4's control) as before.
- README admin in demo mode at 640x360 (Chat, Settings, Documents, Usage, the widest case): 121px before this story with three links and 121px with four, with or without the fix; it is over the quarter line (90px) already on the baseline, so that case scrolls with the page both before and after and no floor case covers it. The fix does not change that figure.
- `$LANE OCUTALON_RUN_TAG=e37s2r3 ci/iris.sh live floor` (fresh stack, `ci/iris.sh build` first): 107 passed in 3.5 min (Chromium, Firefox and WebKit; layout.spec.ts G1-G7 included); `ci/iris.sh teardown` removed the tag (0 left). `npm --prefix web test` 1846/1846. Not run here: the pre-fix floor unit on the local stack (the red is the CI run 42907226080's; the stub measurement above reproduces its 121px and 0px).
mutation (rework 3): the two lines `--header-nav-gap: var(--space-1);` and `--header-nav-item-inline: 6px;` removed from the stacked `.side` of `header.ts` (the bundle rebuilt) -> the 640x360@2 floor-user header measures 121px, static, root property 0px (the G5 "0px against 121" and G4 values of CI run 42907226080; measured with the stub, not by re-running the floor unit); the fixed `header.ts` restored byte-identical (`cmp`), the bundle rebuilt, 77px and sticky again, and the floor unit above green on it.
Rework 3, lead's verification on fresh lane-B stacks (tag `e37s2r3`, `ci/iris.sh build` first; every stack torn down, 0 containers left): `live floor` 107 passed (3.5 min; G4 and G5 included, Chromium, Firefox and WebKit); `live sign-in --part 3/4` (frame.spec.ts with F3, documents.spec.ts) 59 passed; `live sign-in --part 4/4` (usage.spec.ts with U8) 58 passed; `live sign-in-3 --part 1/2` (more-to-try.spec.ts with K22 and K23) 126 passed; `npm --prefix web test` 1846/1846; `npm --prefix web run lint` clean; `bash docker/tests/test-boundaries.sh` passed. Slack re-measured on the built bundle (floor user, demo mode, four links, stub `/state`): the header is 77px and sticky at 640, 630 and 625px wide and 121px and static at 620 and 610px (height 360, device scale 2), so the one-row threshold lies between 620 and 625px and the slack at 640px is about 15 to 19px. Below it the header wraps and scrolls with the page (the quarter rule's fallback); G4's control case at 320x180 is unchanged.


## Auto Run Result

Status: done
Blocking condition: none

Summary: the Usage page and its route are in. `GET /api/v1/usage?days=1|7|30` (`OcuTalon.Web.Usage`, forwarded from `Web.Api`) sums the caller's own session's usage rows into buckets by instance-zone day, agent, channel, model and the estimated flag through `Ownership.Usage` and the new `Ownership.Rows` kind `usage`. The Usage page (`#/usage`, reached from a new header navigation link after Documents) groups those buckets by day, agent, channel or model in an inline SVG chart and a table, with each day's largest request against the limit; More to try has item 9 (a link), `Demo.Features` has `usage`, the README, EXPERIENCE.md and the spine carry this story's rows.

Files changed (the one-line account; the full list is `git show --stat` of the commit):
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- the `usage` kind and `Usage()`; `Web/Usage.cls` (new) and `Web/Api.cls` (one Map) -- the route; `Demo/Features.cls` -- `usage` always on.
- `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipUsage.cls`, `Test/Web/UsageApi.cls` (new), `Test/Demo/Features.cls`, `Test/Web/DocumentsApi.cls` -- class tests and the shared-surface updates.
- `web/src/app/usage/` (new view and page), `api/usage-types.ts` (new), `api/api-client.ts`, `app.config.ts`, `settings/settings-view.ts` (`pageOf`), `header/header-nav.ts` (the link; the links wrap), `header/header.ts` (comment), `header/current-page.ts`, `guide/more-to-try{,-view}.ts` -- the page, its route and entry points.
- `web/e2e/usage/usage.spec.ts` (U1-U13), `web/e2e/api/usage.spec.ts`, `web/e2e/support/usage.ts` (new); updated `frame`, `documents`, `settings` and `guide/more-to-try` specs; `web/scripts/usage-view.test.mjs` (new) and the updated node tests.
- `README.md`, `EXPERIENCE.md` (item 9, nine items) and the spine (three rows marked `[ADDED 2026-11-10, Story 37.2]`).

Review findings: 33 findings from four layers (high 0, medium 7, low 22, false 3, maybe-false 1). Patched: 5 medium entries (chart marks drawn, failed read and Retry, no fetch on regroup, the More to try link press, and the api spec's whole-body compare) and 6 low (unreadable time fails the read, tabular figures, the limit from the answer, nine missing mutation lines, among them). Deferred: 1 (a zero cost reads "<$0.0001"; needs a ruled string). Rejected, each with its reason in the Review Triage Log: 3 false, 1 maybe-false, 19 low (spec-bound or ruled design, theoretical, or a fix that would edit the spec).

Follow-up review recommended: true. Unverified risk: this pass patched 5 medium entries (four new e2e cases U10-U13 plus K3b, and the api spec compare) and the header navigation now wraps (`flex-wrap`) so that four links never widen the page at 305px; a follow-up should read the new cases and the wrapped header at 305 to 1023px once more.

Verification performed: warm class runs `OwnershipUsage`, `UsageApi`, `Demo.Features`, `OwnershipMemories`, `DocumentsApi` and `Web.Api` passed; node tests 144/144 (listed set) and `npm --prefix web test` 1798/1798; `npm --prefix web run lint` and `run build` pass; five e2e parts green on fresh stacks (chromium 1/4, 3/4, 4/4; sign-in-2 2/2; sign-in-3 1/2); spine lint equals the baseline (10 low); all 32 `ci/checks.sh` scripts passed; 20 mutations demonstrated red and reverted byte-identical (the `mutation:` lines above). 1024px header: 56px high, Usage ends at x=559.7, account ends at x=1012 of 1024, one line, no spacing change.

Residual risks: (1) zero-cost display, deferred above; (2) the Usage rows are read as the CSP session's own rows, so on a local install an admin sees their own session's use, not instance-owned rows (as the spec says); (3) the e2e specs rely on `workers: 1` and clearing the LIVE session's rows, as the heartbeat card spec does; (4) the wrapped header was exercised at 305 and 320px by `more-to-try.spec.ts` K22/K23 only.

**Rework iteration 1 (R1-R5) -- this pass only.**

Summary: the Usage item of the More to try panel moved from "Safety and settings" into a new fourth group "Usage and history" (the registry row, `MORE_TO_TRY_GROUPS`, the node tests, K27's written oracle, EXPERIENCE.md's heading entry and its headings sentence, each carrying the ruled marker). The band logic is unchanged; `Demo.Features` is untouched (Story 25.2's change).

Files changed: `web/src/app/guide/more-to-try-view.ts`; `web/scripts/more-to-try-view.test.mjs`, `ux-strings.test.mjs`, `usage-docs.test.mjs`, `sources-docs.test.mjs`; `web/e2e/guide/more-to-try.spec.ts` (K27's oracle and two literal pins; K16, K16b and K17 open with `BAND_IDS`, so all four headings show); `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`; this spec.

Review findings (17 from four layers: high 0, medium 2, low 14, maybe-false 1): patched 2 medium (K16 and K17 never rendered the fourth heading; K27 did not pin usage under the fourth) and 3 low (R5 ticked, the Item 9 guard, the headings sentence's marker pin); deferred 1 medium (the stale three-heading text in `epics.md` and `epic-0-context.md`, the lead's); the rest rejected with reasons in the triage log.

Follow-up review recommended: false (this pass patched no high).

Verification performed: `node --test` of the touched node tests and `npm --prefix web test` (1821) pass; `npm --prefix web run lint` passes; on fresh lane-B stacks (tag `e37s2r`, `ci/iris.sh build` first) `live sign-in-3 --part 1/2` passes 126 of 126 (K16, K16b, K17 with all four headings, and K27) and `live sign-in --part 4/4` (usage.spec.ts) passes 58 of 58; `test-boundaries.sh` passes; mutations demonstrated and recorded under `## Verification`. All stacks torn down.

Residual risks: none new; the planning text of Story 0.22 (deferred above) still says three headings until the lead amends it.

**Rework iteration 2 (R6-R7) -- this pass only.**

Summary: the Usage page shows an exact-zero cost as `$0` through a new `costText` wrapper over the shared `formatCost` (which is unchanged; a non-zero amount under $0.0001 keeps `<$0.0001`), and the More to try usage look-for's second sentence is the ruled one ("...from the agents' decisions on your messages.").

Files changed: `web/src/app/usage/usage-view.ts` (`costText`, `USAGE_TEXTS.costZero`) and `usage-page.ts` (`cost()` calls it); `web/src/app/guide/more-to-try-view.ts` (the look-for); `web/scripts/usage-view.test.mjs`, `more-to-try-view.test.mjs`, `ux-strings.test.mjs`, `usage-docs.test.mjs`; `web/e2e/usage/usage.spec.ts` (zero rows read `$0`), `web/e2e/guide/more-to-try.spec.ts`; EXPERIENCE.md (Item 9 and the Cost row, each with its `[AMENDED 2026-11-10 ...]` marker).

Review findings (15 from four layers: high 0, medium 3, low 12): patched 3 medium (in 2 root causes: the Cost row, the unpinned DW-1090 marker) and 5 low (the `isFormat` scope, a redundant assertion, a mutation comment's case id, the marker's mutation line); rejected 7 low, each with its reason in the triage log; none deferred.

Follow-up review recommended: false (this follow-up pass patched no high).

Verification performed: `node --test` of `usage-view`, `more-to-try-view`, `ux-strings` and `usage-docs` (89 pass); `npm --prefix web test` 1825/1825; `npm --prefix web run lint` clean; `bash docker/tests/test-boundaries.sh` passed; on fresh lane-B stacks (tag e37s2r2, after `ci/iris.sh build`) `live sign-in --part 4/4` (58 passed, with U2 and U3 on `$0`) and `live sign-in-3 --part 1/2` (126 passed, with K3 on the new look-for). Mutations (Rule 19) are in `## Verification`; each was observed red and reverted byte-identical.

Residual risks: the zero-cost entry in the frontmatter `deferred:` (DW-1089) is now resolved by R6 and the lead closes its ledger entry; the AC 5 sentence still names `<$0.0001` for zero (R6 carries the ruling).

Status: done
Blocking condition: none

**Rework iteration 3 (the [CI] item) -- this pass only.**

Summary: at 640x360 (device scale 2) the floor user's header (mark, "Demo mode" badge, Demo view switch, Chat, Documents, Usage) wrapped to 121px, over the quarter-of-the-window line (90px), so it stopped sticking and wrote 0px (G4 and G5 red on CI). The stacked band's `.side` now sets `--header-nav-gap: var(--space-1)` (4px, was 8px) and `--header-nav-item-inline: 6px` (was 8px): the navigation is 196px instead of 216px, the left group stays on one row down to a window of about 621px, and the header is 77px, sticky, writing 77px (it was 77px with two links before this story). No link is hidden or moved; the quarter rule, the floor tests and every text are unchanged. Measurements (before this story 77px; after it, unfixed 121px; fixed 77px; 1024x768 unchanged 56px; 305px no sideways scroll) are under `## Verification`.

Files changed: `web/src/app/header/header.ts` (the two properties and the contract comment), `web/src/app/header/header-nav.ts` (the contract comment), this spec.

Review findings (13 from four layers: high 0, medium 0, low 10, false 3): patched 2 low (the unrecorded runs, a placeholder time); rejected 11, each with its reason in the triage log; none deferred.

Follow-up review recommended: false (this follow-up pass patched no high).

Verification performed: on fresh lane-B stacks (tag `e37s2r3`, `ci/iris.sh build` first) `live floor` 107 passed (G4 and G5 among them), `live sign-in --part 3/4` 59 passed (F3), `live sign-in --part 4/4` 58 passed (U8), `live sign-in-3 --part 1/2` 126 passed (K22, K23); `npm --prefix web test` 1846/1846; `npm --prefix web run lint` clean; `test-boundaries.sh` passed. Mutation (Rule 19) in `## Verification`; the observed red of G4 and G5 is CI run 42907226080 on the identical CSS, and the stub measurement of the mutant reproduces its 121px and 0px. All stacks torn down.

Residual risks: (1) the README admin in demo mode at 640x360 (Chat, Settings, Documents, Usage) is 121px, over the line, as it was before this story with three links, so that header scrolls with the page (the header's contract) and no floor case covers it; (2) windows about 305 to 620px wide and short wrap the left group and the header scrolls with the page, with no case at those sizes; (3) the one-row slack at 640px is about 15 to 19px.

Status: done
Blocking condition: none
