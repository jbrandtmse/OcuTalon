# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 6 gives a signed-in user a look back at, and more ways into, OcuTalon. A History page lets them filter past attention decisions and see past incidents with their state and summary. Files and photos can be sent from the web app or Telegram. Approver and viewer roles decide who may answer each kind of approval request. The Usage page that used to be this epic's first story now lives in Epic 37 (Story 37.2), so that step 6's two feature epics (25 and 26) don't wait on each other's merge. The epic is in Lane B's files, runs in the pool (runner C in this run), and ships in the first daily release after it merges.

## Stories

- Story 25.1: moved to Story 37.2 (the Usage page, on another branch, not yet merged)
- Story 25.2: Filter past decisions and incidents on the History page (the only story planned in this run)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram
- Story 25.4: Assign approver and viewer roles in Settings
- Story 25.5: Answer only with the right approver role, and say why otherwise

## Requirements & Constraints

- **History (decisions):** decisions can be filtered by outcome, channel, date and fallback. Each decision opens to show its reasons and a link to its trace.
- **History (incidents):** incidents are listed with their state and summary. From step 6 the incident summary written when an incident closes appears here.
- **History outlives the message purge.** It reads OcuTalon's and the bridge's own decision and incident tables, never production messages. Retention keeps bridge decisions and incidents for the purge task's day count (90 by default).
- **Isolation:** a user sees only what the ownership API lets their session see. Another session's decisions or incidents must never appear. An `instance` incident on a local install belongs to every session that watches that production.
- **Accessibility floor:** the page works by keyboard alone, every control is labelled, text contrast meets WCAG 2.1 AA, and no cue relies on colour alone.
- **Testing:** automated tests plus a Playwright spec under `web/e2e/`, with fixture decisions and incidents across two sessions. Fixture incidents carry summary fields wherever the real summary isn't available.
- Later stories in the epic, for orientation only: files are limited to 10 MB and refused with a clear message; file bytes never travel in a production message; a viewer is read-only and every state-changing route refuses them with 403.

## Technical Decisions

- **The ownership API is the only read path.** `OcuTalon.Data.Ownership` (Lane B) applies the caller's `SessionRef` and re-checks owner or scope. No endpoint accepts a `SessionRef` from the client. The signed-in user holds no SQL grant, so the API's queries skip the SQL privilege check and enforce ownership in the query itself. A CI check allows those unchecked prepares only in named methods (`Ownership.Rows` among them), so new history queries belong there and not in ad-hoc prepares.
- **Bridge records are read-only to OcuTalon.** Web and Core read `OcuTalon.Bridge.Data` (the `Decision` rows: outcome, reasons, `Fallback`, `FallbackReason`, `TraceSessionId`) through the ownership API and keep no copies.
- **Trace links:** every trace URL comes from the one builder, `OcuTalon.Web.TraceLink`. A decision's target is the session holding its decision message (`Decision.TraceSessionId`). An incident's target is its diagnosis session.
- **Incident summary:** `IncidentManager` composes it in code (`Watch.Summary`) on every move into `closed` and stores it on the incident row. Incident states are open, awaiting approval, fixing, resolved and closed, with the open variant stored beside the state.
- **Spine and contracts (AD-29, AD-33):** each story adds its own step-6 spine rows (Contest Planner ruling, 2026-11-10; the step-pairing rule no longer applies). Story 37.2 adds the usage read and the header navigation's Usage entry; Story 25.2 adds the history read in the REST and ownership tables and the header navigation's History entry; the file upload route, the private file table and the Roles routes come only with Stories 25.3, 25.4/25.5 and 37.1. Story 25.2 builds on 37.2's header and ownership names. Any new route, table or event type goes into the ownership tables in the same change, and only the owning lane edits a class.
- **Web envelope:** API routes live under `/ocutalon/api/v1`. A request without a session gets 401 `signed_out`, and a user without the OcuTalon role gets 403 `no_role`. State-changing calls need JSON, `X-OcuTalon-Request: 1` and a matching `Origin`. Untrusted text, model text included, renders as text only.

## UX & Interaction Patterns

- Reached from the header navigation (History and Usage join in step 6), with `aria-current="page"`. The page title is "History · OcuTalon". The page has a hidden `h1` and an `h2` per region.
- Two tabs, Decisions and Incidents. They use `aria-selected`, work by keyboard and never switch by themselves.
- History table: rows at least 40px tall, with the outcome chip (Ignore, Digest, Tell now, Act) in the first column. Chips are icon plus label, distinct without colour, and can't take focus.
- The filters persist in the address, so a reload or a shared link keeps them. The list pages and never scrolls without end.
- A decision row's disclosure is an `aria-expanded` button that expands its reasons in place, never as a dialog. Its trace link is a sibling of the button, not inside it. The link is underlined and opens in a new tab, saying "(opens in a new tab)". On local and IPM installs, until the sign-in popover has been seen in the session, the link reads "Open in Visual Trace (shows sign-in help first)", with `aria-haspopup="dialog"`.
- Incidents show a state chip (static pill per state), headline, times, summary and a trace link.
- Empty filter result: "No decisions match these filters."

## Cross-Story Dependencies

- **Story 37.2 (Epic 37, not yet merged):** Story 25.2's implementation waits for it to merge (the header navigation and the ownership names 25.2 extends). Story 25.2's spec can be written ahead of that merge, against 37.2's spec and spine rows.
- **Story 37.1:** fixes the step-6 role names and the stubs for `Approval.MayAnswer` and role assignment, which Stories 25.4 and 25.5 call.
- **Story 23.6 (Lane A):** the source of the incident summary that Story 25.2 lists.
- **Epic 26** depends on this epic. Story 26.2 needs Story 25.3's file-store call and the CI mock's `getFile`. Story 26.4 needs Story 25.5's `not_allowed` result from `AnswersIn`. Story 25.3 needs Epic 20 (the Documents page's **Add documents**). Story 25.4 needs Epics 16 and 18 (the online demo account and a Settings section).
