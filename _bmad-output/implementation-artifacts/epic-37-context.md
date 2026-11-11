# Epic 37 Context: Step 6's contracts: approver roles named, and the Usage page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 37 is step 6's contract epic. It groups the first Lane A story and the first Lane B story of step 6 so that the step's feature epics (25 and 26) can build in parallel, and each story keeps its home lane's files. This dispatch builds only Story 37.2, Lane B's Usage page. A signed-in user sees their own tokens and cost over a chosen range, grouped by day, agent, channel or model, and each day's largest model request against the 100,000-token limit. The page shows what OcuTalon costs, and it shows a request that comes close to the size limit. Story 37.1 (Lane A: approver roles, role-check stubs, the photo caption) waits on Epic 36 and is not built now.

## Stories

- Story 37.1: Fix step 6's contracts: approver roles and the photo caption (context only; not in this dispatch)
- Story 37.2: See tokens and cost over time on the Usage page

## Requirements & Constraints

- **The view:** tokens and cost by day, agent, channel and model. In every grouping, a range's totals equal the sum of the decision and turn costs in that range. Each day shows its largest model request against the 100,000-token limit, the request-size ceiling that every turn and decision records.
- **Token kinds:** input, output, cache-read and cache-write, all four. Input already includes cached input.
- **Compaction rows** count under their own agent (`compaction`) and are marked as estimated (`Estimated` true). Their tokens are not reported by AI Hub, so they are estimates.
- **Evaluation rows** (owner `eval`) never appear.
- **Isolation:** a user sees only the usage rows of their own session. Another session's rows never appear. On a local install, the IRIS user's durable session owns the rows. The page is for any signed-in user, not admins only.
- **Empty range:** the page shows "No model use in this period."
- **Accessibility:** the page works by keyboard alone, every control has a label, and text contrast meets WCAG 2.1 AA. Nothing relies on colour alone. Text resizes to 200% without loss, and the layout stacks below 1024 CSS px.
- **Tests:** add automated tests and a Playwright spec under `web/e2e/`. Use fixture usage rows across days, agents, channels and models. For each grouping, show that:
  - each total equals the sum of its rows;
  - the chart and the table agree;
  - another session's rows never appear;
  - the page works by keyboard with labelled controls.
- **Texts:** every user-facing text must be plain language. Any text the UX doesn't already give is proposed for approval before it ships.
- **Re-plan of 2026-11-09:** each judge-visible feature in this re-plan also gets a "More to try" item and a README "New since 1.0.0" line. Both texts are PUBLIC TEXT for the Contest Planner's approval.
- **Release:** the story ships in the first daily release after it merges.

## Technical Decisions

- **Spine update in the same change:** add only this story's own step-6 rows: the usage read, in the REST table and the ownership tables, and the header navigation's Usage entry.
  - Do not add the History read or its entry; they come with Story 25.2. The header shows no History entry until 25.2 merges.
  - Do not add the file upload route, the private file table or the Roles routes; they come with Stories 25.3, 25.4, 25.5 and 37.1.
  - The step-6 asks from Lane A's Story 37.1 come with the stories that build them, not with this story.
  - Mark the amendments in the spine's `[ADDED <date>, Story 37.2]` form.
- **Data source:** use `OcuTalon.Bridge.Data.Usage`, which is Lane A's and read-only for Lane B.
  - The runner writes one row per agent turn, with: `DecisionRef`, `ItemId`, `Kind`, `OwnerRef`, `RecordedAt` (UTC), agent, channel, model, model-request count, the four token counts, the largest estimated request size, cost and `Estimated`.
  - Decision and turn totals are sums of these rows. OcuTalon keeps no copies of bridge records. Cost is computed from the bridge's price table.
  - If you need a property the table doesn't have, ask Lane A for it. Never edit the class.
- **Reads go through `OcuTalon.Data.Ownership`** (Lane B). Web and Core never query bridge tables directly.
  - The signed-in user has no SQL privilege. Unchecked prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`, and a CI allow-list enforces this.
  - A new owner-scoped read must therefore use `Ownership.Rows`:
    - the caller's `SessionRef` comes from the CSP session, never from request input;
    - the SQL text is fixed per row kind and never built from caller-supplied text;
    - the owner check sits in the `WHERE` clause;
    - a second-session test shows that it returns none of another session's rows.
  - No endpoint accepts a `SessionRef` from the client.
  - `TurnCost` and `RunCost` already exist on Ownership.
- **REST:** the usage read belongs under `/api/v1/` on `OcuTalon.Web.Api`, behind the existing envelope (401 `signed_out`, 403 `no_role`).
- **Times:** store times as UTC ISO 8601 to the second, and render them only through `OcuTalon.Data.Time`. The spine does not say which zone sets the day boundary for usage grouping. The daily cost cap's day ends at midnight in the instance zone (`OcuTalon.Bridge.Time`).
- **Retention:** `Bridge.Purge(daysToKeep)` deletes usage rows older than the retention window. The online demo's reset erases all usage rows.
- **Ownership:** Lane B owns `web/`, `OcuTalon.Web`, `OcuTalon.Data.Ownership` and the Lane B test packages (`OcuTalon.Test.<Area>`). Stay inside Lane B's files.

## UX & Interaction Patterns

- **Navigation:** open the page from the header navigation. Its Usage entry joins Chat, Settings (admins only) and Documents. Use the `header-nav-item` component with `aria-current="page"` on the current page's item. Its styles: muted ink, ink when current, a 2px bottom bar in the action colour.
- **Page title:** "Usage · OcuTalon". Keep the main-page heading structure: an `h2` per region.
- **Controls and content:**
  - a range control;
  - a grouping control (day, agent, channel or model);
  - the `usage-chart`: token bars in `chart-tokens` (#1A6F6D; dark mode #45B9B3) and the cost line in `chart-cost` (#102A45; dark mode #AAB6C8), with `border`-coloured gridlines. Each series is labelled directly as well as in the legend.
  - a table beneath the chart, with a row for every bar and every point;
  - each day's largest request shown against the 100,000-token limit.
- **Number formats:**
  - Tokens use digit separators.
  - USD shows "<$0.0001" below that amount, 4 decimals under $0.01, 3 under $1, and 2 otherwise ($0.0006, $0.042, $1.24).
  - Costs and counts use tabular figures. No text is under 12px, and only values to compare use the mono face.
- **Empty state:** "No model use in this period." (the "usage empty" catalog key).

## Cross-Story Dependencies

- **37.2 and 37.1:** after the 2026-11-10 amendment, Story 37.2 adds only its own spine rows. It no longer waits for 37.1. Epic 37's edge on Epic 36 now applies to Story 37.1 alone.
- **Downstream:** Story 25.2 (the History read and the header's History entry) depends on 37.2. Stories 25.4 and 25.5 depend on 37.1.
- **Other systems:**
  - Usage rows come from Lane A's runner (AD-20).
  - The online demo's daily cap and gateway spend are separate and unchanged; they are read through `Bridge.Budget.State()`.
