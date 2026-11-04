---
title: 'Story 6.1: Show each incident as one card in the chat'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '9b400ec4795b1d4600491de524917231344cba68'
baseline_commit: '9b400ec4795b1d4600491de524917231344cba68'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
warnings: ['oversized']
deferred:
  - summary: "Cross-lane: /state's incident entries carry only Live.Payload.Incident.FromRow's row-backed fields; groups, requests, evidence and traceTargets are absent from the snapshot, so a reloaded (or Seq-skip resynced) card has no request cards, results or Show details evidence until the next incident event."
    evidence: "Live/Payload/Incident.cls FromRow leaves the four parts 'for the caller to fill'; Web/Api.cls ChatItems calls FromRow alone; the parts' data lives in Lane A tables that Epic 5 (Story 5.4, unmerged) defines. Story 0.5's decision was one builder for events and the snapshot. At Epic 5's merge, /state must build the parts with the same builder as IncidentManager (inside FromRow, or a Lane A builder Web.Api calls)."
    location: 'src/ocutalon/cls/OcuTalon/Web/Api.cls ChatItems; src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls FromRow'
    severity: 'med'
  - summary: "Cross-lane: the values of Incident.CauseCategory and Incident.Element are not fixed by any contract in this tree. The card humanizes a snake_case category (data_format_change -> 'Data format change') and shows Element as published; the UX's evidence line reads 'order date' while eval/orders-date-format records elementAtFault 'OrderDate'."
    evidence: "Msg.Enum has no cause-category enumeration; eval/orders-date-format/case.json expects causeCategory data_format_change and elementAtFault OrderDate; EXPERIENCE.md L276 shows 'Data format change · order date'. Story 5.4 (Epic 5, unmerged) defines DiagnosisPayload; confirm at Epic 5's merge that Element is published in reader form."
    location: 'web/src/app/incidents/incident-view.ts'
    severity: 'low'
---

<intent-contract>

## Intent

**Problem:** The page keeps each `incident` event and the snapshot's noticed incidents in its live store, but the chat draws nothing for them (`chat-view.ts`: "Incident entries render nothing yet (Story 6.1)"). A judge can't see what broke or what OcuTalon proposes.

**Approach:** Render one incident card per incident `Ref` in the chat panel, from the `IncidentPayload` the store already holds (keyed `incident:<ref>`, replaced in place). The card shows, top to bottom: the state chip with its time, the headline, the cause, the evidence line, the proposed fix, an inline Show details evidence panel, and a footer with the diagnosis decision's strip. The bar follows the state, a closed card compacts, and the chat announces a new incident and each state change once. `WebChatOut`'s rule that incident-kind notifications record their `Delivery` row only becomes an explicit, named contract.

## Boundaries & Constraints

**Always:**
- The card reads only `OcuTalon.Live.Payload.Incident`'s fields (Story 0.5). It reads the footer's decision from the store's `decisions` by `decisionRef`, and trace URLs only from the served `traceUrl` (`Web.TraceLink`). The page never builds a URL, never decides a state, and never merges two payloads: each payload is the full view.
- The state chip shows the payload's `state` (AD-15's table is `IncidentManager`'s). Unknown states, variants and categories render without breaking the card.
- Every part whose fields are absent is left out, never shown empty. A snapshot payload has no `groups`, `requests`, `evidence` or `traceTargets` (deferred item 1).
- Text is bound by interpolation, never as HTML (AD-13). Fixed strings live in `INCIDENT_TEXTS` (non-ASCII written as the escapes `\u2026` and `\u00B7`, Rule 14), each with a source in `ux-strings.test.mjs`. Styles use `DESIGN.md` tokens only.
- Announcements go only through `Announcer`, from the chat panel (`chat-announcements.ts`), never from a card component. The first look, and any snapshot taken at page load, is silent. Focus moves only through `shared/focus-rule.ts`.
- Message-text times use instance time, with " ET" on the online demo. Page times use the browser's zone, and add its short zone name beside message text when the offsets differ (UX-DR123).

**Never:**
- Build or edit a Lane A class: `Live.Payload.Incident` and its parts, `Data.Incident`, `IncidentManager`, `Msg.Catalog.Watch`, `Test/Watch/**`.
- Edit `web/src/app/live/**` (Epic 16; `payloads.ts` is generated), `Data/Ownership.cls`, `Test/{Web,Data}/**`, `docker/**`, `ci/mock/**` or any other contended path. No new e2e unit, fixture user or `docker/tests` edit.
- Add to `live sign-in`. It stands at 452-463 s of its 540 s local deadline, and Epic 4 ruled that it gains no case.
- Build the approval request cards, dry run, Approve/Reject, results, Dismiss, fallback or no-fix notices, or failure groups (Stories 6.2-6.4). Don't build the 1280×600 layout check (6.2), the phone's notice or the rail's focus jump (6.3).
- Change `/state` or `Web/Api.cls`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| New incident | `incident` event `{ref R, state awaiting_approval, count 50, noticeCount 50, firstAt, lastAt, itemNoun, cause, fixSummary, causeCategory, element, decisionRef, evidence, traceTargets}` | One card for R. Its chip reads "Awaiting approval", with the time. Below come the headline "50 orders failed since 14:12" (no final period), the cause sentence, the evidence line "Data format change · order date · 50 failures grouped into this incident" (fixture `causeCategory` `data_format_change`, `element` "order date"), "I can repair and resend all 50.", the Show details row, and the footer strip with its trace link (`traceTargets.diagnosis.traceUrl`). The bar is attention. Announced once: "Incident: 50 orders failed since 14:12. Approval needed." | No error expected |
| Same Ref again | a later event for R: `count 52, noticeCount 50, state fixing`, one `requests[]` entry in state `executing` with `result.total 50` | Still exactly one card for R, updated in place: "52 orders failed since 14:12", then "2 more since the notice". The chip reads Fixing, the bar is info-ink, and "Repairing and resending 50 orders…" shows. Announced once as "Incident: 52 orders failed since 14:12. Fixing." (V1) | — |
| Resolved, then closed | state `resolved`, then `closed` | Resolved: success-ink bar. Closed: border-strong bar, compacted to the chip row, the headline and the Show details row; the cause, evidence line, fix, "more" line, fixing line and footer are gone. Each change is announced once | — |
| Open variants | state `open` with `openVariant` `rejected`, `expired`, `fallback` or `no_fix`, or `fallback: true` | Attention bar, "Open" chip. `fallback: true` adds the Fallback flag beside the chip. No evidence line when both `causeCategory` and `element` are empty. At first sight, a fallback or no-fix incident is announced "Incident: {headline}. No fix proposed." | — |
| Snapshot | a noticed incident row of the session, an unnoticed row, another session's row | After load, one card for the noticed row only (`FromRow` fields; no parts). Nothing is announced | Absent parts are left out |
| More since the notice | `count` > `noticeCount` | "{count − noticeCount} more since the notice" under the headline. None when `count` ≤ `noticeCount` or either is absent | — |
| After close | a closed R, then an event with a new Ref R2 (same cause) | Two cards: R stays compacted, R2 is new and announced | — |
| Show details | press "Show details" | `aria-expanded` turns true. The panel opens inline right below that row: Cause ("Data format change · order date"), Sample failed message (header id, `mono-sm`), Error (`sampleError`, `mono-sm`), Failures by item (one `mono-sm` line per `evidence.items` entry), "Held as an IRIS Workflow task until someone answers." (only while a request is `pending`), and the links "Sample message" and "First failure" (their `traceUrl`s, in the Orders namespace's trace app). Pressing again closes it. The panel stays open across updates of the card | A row with no data is left out; with no row at all there is no Show details |
| Incident-kind notification | a `Notification` of kind `incident`, `approval`, `answered` or `result` for the session, through Notify | `WebChatOut` records its `Delivery` row only (channel web, kind, approval and decision Refs; no text, no ChannelMessageId, no event). The page shows no notice card | — |
| Times | online demo on; browser zone ≠ instance zone | Headline: instance time with " ET" ("since 14:12 ET"); ForMessage's dated forms for other days. The top time is the page time of `lastAt`, with the day when it isn't today, plus the browser zone's short name ("15:12 CET") | An unreadable time renders empty, never "Invalid Date" and never a throw |
| No decision in store | `decisionRef` not among the store's decisions | The footer shows only the diagnosis trace link (when served); no chip, cost or Details | — |
| No item noun | `itemNoun` absent | "message" or "messages" by count (AD-15's default noun) | — |

</intent-contract>

## Code Map

**Read-only contracts and evidence (never edit):**
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls`, `Live/Payload/Part/Incident*.cls`, `Part/ItemNoun.cls`, `Part/TraceTarget.cls`: the payload (Lane A). `FromRow` (L65) sets only the row-backed fields.
- `web/src/app/live/payloads.ts:257` `IncidentPayload` and its part interfaces (generated; `TraceTarget.traceUrl` L103).
- `web/src/app/live/live-store.ts:42,95,145-152`: `incident` lives in `chat`, keyed `incident:<ref>`, replaced in place. `scripts/live-store.test.mjs:156-164` already pins one entry per Ref (contended Epic 16; read only).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:548-590` `ChatItems`: the snapshot merges `Ownership.RecentIncidents` (noticed, visible) as `{type:"incident", payload: FromRow}`. `Test/Web/Api.cls:322-420` pins noticed, unnoticed, instance and foreign rows (contended; unchanged).
- `src/ocutalon/cls/OcuTalon/Web/TraceLink.cls:58` `Add`: `traceUrl` on any nested object with `traceHeaderId` + `traceNamespace`. The OCUORDERS app is served only in demo mode, and the floor stack is in demo mode (`e2e/floor/guide.spec.ts:12`).
- `src/ocutalon/cls/OcuTalon/Data/Time.cls:30-49` `ForMessage`: the oracle for the headline's message time ("14:12", "Thursday at 14:12" for 1-6 days either way, "Oct 9 at 14:12", "Dec 30, 2025 at 10:00"). The renderer adds " ET" on the online demo.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:81` `Incident` (default `OpenVariant` "fix", which is no enum value) and `:331` `Clean(refs)` (contended; use only).
- `eval/orders-date-format/case.json`: `causeCategory` `data_format_change`, `elementAtFault` `OrderDate`.
- `web/src/styles/tokens.css:381-437`: `--incident-card-*`, `--incident-state-*-{background,foreground}`, `--evidence-panel-*`.
- UX: `EXPERIENCE.md` L276-291 (components), L429 (announcements), L413-418 (focus), L643-656 (lifecycle); `DESIGN.md` L795-826; `mockups/states.html` A1-A7 (illustrative).

**To change or reuse:**
- `web/src/app/chat/chat-view.ts`: `chatView` skips incidents; `noticeOf` keeps tellnow/reminder only (must stay so for AC3).
- `web/src/app/chat/chat-panel.ts`: the `@for` over entries, `FOCUS_RULE` (`[data-part][data-key]`), `Target.part`, `noteArrivals`, `instanceZone`, and `this.live.snapshot()?.onlineDemo`.
- `web/src/app/chat/chat-announcements.ts`: `chatAnnouncements(heard, entries, format)`, `landed`, `ChatHeard`.
- `web/src/app/chat/notice-card.ts`: the sibling card (bar, `data-part`, `tabindex="-1"`, `DecisionStrip` use).
- `web/src/app/chat/decision-strip.ts:190-202`: inputs `decision`, `cost`, `fallbackReason`, `reasons`, `newest`, `traceUrl`. Also `chat/fallback-flag.ts`.
- `web/src/app/shared/trace-link.ts`: `app-trace-link` with `url`, `text` and `appearance`.
- `web/src/app/chat/page-time.ts`: `pageTime`, `pageTimeBeside` (zone suffix), `pageWhen` (day forms, `calendarDay`, `WHEN_TEXTS`).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls:20-50`: `CARDKINDS`, and the non-card branch of `OnNotification`.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls:163-183` `TestOtherKindsRecordOnly`.
- `web/scripts/ux-strings.test.mjs`: `IMPORTED` (L41-56) and `SOURCES` (`ux`, `ac`, `ruled` L142-380).
- `web/scripts/chat-view.test.mjs:32,370`, which assert that incidents render nothing (a shared surface).
- `web/scripts/announce-focus-sources.test.mjs`: card components announce nothing, and focus moves only via the focus rule.
- e2e: `web/e2e/support/iris.ts` (`publishReminder` L118, `seedDecision` L480, `sendNotification` L594, `cleanFixtureRows` L613, `seedIncident` L817, `quoted`); `web/e2e/support/floor.ts` (`CARD_MS`, `unique`, `mainOf`); `web/e2e/floor/announcements.spec.ts` (reading the Announcer region); `web/e2e/chat/notice.spec.ts` (bar width and colour via `tokenColor`).

## Tasks & Acceptance

**Execution:**
1. `web/src/app/chat/page-time.ts` -- add two functions:
   - `messageTime(iso, nowMs, instanceZone, onlineDemo)`: ForMessage's forms, in the instance zone, with a 24-hour two-digit clock and English day and month names, followed by a space and "ET" (a new `WHEN_TEXTS` entry) when `onlineDemo`.
   - A page time with the day and the zone suffix (`pageWhen`'s form plus `pageTimeBeside`'s suffix rule).

   Factor the suffix out of `pageTimeBeside` instead of copying it, and reuse `calendarDay` and `WHEN_TEXTS`. -- The headline and the top time need them, and the page has no instance-time formatter.
2. `web/src/app/incidents/incident-view.ts` (new; erasable TS, type-only imports, so Node runs it as is) -- export the following:
   - `INCIDENT_TEXTS` (Design Notes › Texts).
   - `incidentView(payload, ctx)`, where ctx holds `decisions`, the time functions (passed in) and `nowMs`. It gives everything the card draws: `stateText` (or none), `bar` (`attention|fixing|resolved|closed`), `fallback`, `time`, `headline`, `more`, `causeSentence`, `evidenceLine`, `fixSentence`, `fixingLine`, `compact`, `decision`, `strip` inputs, `diagnosisUrl`, and `panel` rows (or none).
   - `announcementOf(previous, payload, headline)`: the notice text at first sight (awaiting_approval → Approval needed; fallback or `openVariant` fallback/no_fix → No fix proposed; otherwise the V1 state form), the V1 state form on a state change, and nothing otherwise.

   The rules are those of the matrix and Design Notes (Decided 2-12). -- One tested view model, the pattern of `decision-view.ts`.
3. `web/src/app/incidents/evidence-panel.ts` (new) -- `app-evidence-panel`: the panel rows on `--evidence-panel-*`. Labels are in Inter and values in `mono-sm` where the matrix says so. The links are `app-trace-link` with `text` "Sample message" / "First failure". -- 6.2 reuses it below its approval row.
4. `web/src/app/incidents/incident-card.ts` (new) -- `app-incident-card`:
   - The root is an `article` with `data-part="incident"`, `data-key`, `tabindex="-1"`, `aria-labelledby` the headline.
   - The chip row holds the state pill, `app-fallback-flag` and the time.
   - The headline is an `h3` with `tabindex="-1"` and the headline token.
   - Then come the more line, the cause, the evidence line, the fix and the fixing line.
   - The actions row holds the Show details ghost button (chevron, `aria-expanded`, `aria-controls`), and the evidence panel follows directly after it.
   - The footer holds `app-decision-strip` (`reasons` on, `newest` off, the decision's own `costUSD`, the incident's `fallbackReason` when `fallback`, `traceUrl` the diagnosis target's), or the trace link alone when no decision is found.
   - The 4px left bar uses `--incident-card-accent-bar[-fixing|-resolved|-closed]`. Full width, with text at most `--chat-panel-text-max`. It announces nothing.
5. `web/src/app/chat/chat-view.ts` -- add `IncidentEntryView {entry: 'incident', key: 'incident:<ref>', incident}` to `ChatEntryView`, in store order. Update the module doc. -- The panel renders it.
6. `web/src/app/chat/chat-panel.ts` -- render `<app-incident-card>` for incident entries, passing the store's `decisions`, `instanceZone` and `onlineDemo`. Add part `incident` to `Target` and `noteArrivals`, so a new card is an arrival the New messages button focuses. Pass the incident reads to `chatAnnouncements` through its format. -- The integration point.
7. `web/src/app/chat/chat-announcements.ts` -- extend the record to keep each incident's state, and add the incident texts via `announcementOf`. An incident counts as landed when present. -- One place announces each event.
8. `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- add `Parameter INCIDENTKINDS = "incident,approval,answered,result"`, documented as kinds whose web form is the incident card: they record their Delivery row only, never a card. The behaviour is unchanged. Also update the class doc. -- The contract 6.2-6.4 rely on.
9. `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls` -- add `TestIncidentKindsRecordOnly`: the parameter's value, and per kind one row with channel/kind/approval/decision, no text, no message id and no event. Narrow `TestOtherKindsRecordOnly` to `fallback,allowance,pairing,status,digest`. Update the header.
10. `web/scripts/incident-view.test.mjs` (new), `web/scripts/page-time.test.mjs`, `web/scripts/chat-view.test.mjs`, `web/scripts/chat-announcements.test.mjs` -- unit-test every matrix row and Decided rule: the texts written out, `messageTime` against ForMessage's four forms and " ET", the suffix, count-of-one forms, absent parts, unknown state/variant/category, the fixing count, the "Held as" condition, and the announcement table. Replace the "renders nothing for incidents" assertions.
11. `web/scripts/ux-strings.test.mjs` -- import `incidents/incident-view.ts` `INCIDENT_TEXTS`. Give each new string its source: `ux` for EXPERIENCE-held ones, `ac` 'Story 6.1: Show each incident as one card in the chat' for "Incident: {headline}. No fix proposed.", and `ruled` 'Story 6.1 veto item V1 (...)' for the V1 list.
12. `web/e2e/support/iris.ts` -- add `publishIncident(user, payload)`, which returns the Seq: `Live.Payload.Incident.%New()`, `%JSONImport(quoted(JSON.stringify(payload)))`, then `Live.Publish.Publish(s.Ref,"incident",p,.q)`. It follows `publishReminder` (Task 0 below).
13. `web/e2e/floor/incident.spec.ts` (new) -- the browser cases I1-I8 (Verification). Each case uses `unique` markers and refs of its own, and removes its rows with `cleanFixtureRows` in a `finally`.

**Acceptance Criteria:**
- AC1: Given a fixture `incident` event for the session published through `Live.Publish`, when the page applies it and then a second event with the same `ref`, then the chat holds exactly one card for that ref, showing the second payload (I1, I2).
- AC2: Given a noticed and an unnoticed incident row of the session, when the page loads, then the chat shows one card for the noticed row only, built from its row fields, and announces nothing (I4).
- AC3: Given a `Notification` of each kind `incident`, `approval`, `answered` and `result` for the session through Notify, when `WebChatOut` handles it, then it records exactly its Delivery row (no text, no event) and the page shows no notice card, while a tell-now sent after them shows its card (`TestIncidentKindsRecordOnly`, I5).
- AC4: Given an awaiting-approval incident with every field, when its card renders, then it shows top to bottom the chip with its time, the headline with no final period, the cause sentence, the evidence line, the fix without "Approve?", the Show details row and the footer strip with the diagnosis trace link, each with the exact text of the matrix (I1, `incident-view.test`).
- AC5: Given the browser in Europe/Berlin and the stack in UTC, when a card renders, then its top time ends with the browser zone's short name and its headline time has none; given the online demo, then the headline time ends " ET" (I6, `page-time.test`).
- AC6: Given an incident that moves through awaiting_approval, fixing, resolved and closed, or any open variant, when the card updates, then its bar is attention, info-ink, success-ink and border-strong (attention for every open variant), fixing shows "Repairing and resending 50 orders…", and closed compacts to the chip row, the headline and (when the panel has rows) Show details (I2, I8).
- AC7: Given the page loaded, when a new incident arrives, then the Announcer says "Incident: {headline}. Approval needed." (or "… No fix proposed." for a fallback or no-fix), once; when a known card's state changes, it says the V1 state form once; a count-only change, an unchanged update and the first look say nothing (I1, I2, I4, I8).
- AC8: Given any card with evidence, when I press Show details, then the panel opens inline right below the Show details row with the matrix's rows, raw values in `mono-sm`, and the two trace links into `/ocutalon/trace/ocuorders/`; "Held as an IRIS Workflow task until someone answers." shows only while a request is pending; pressing again closes it (I3).
- AC9: Given `count` 52 and `noticeCount` 50, when the card renders, then the headline reads 52 with "2 more since the notice"; given a closed incident, when an event with a new ref arrives, then a second card appears (I2).
- AC10: Given focus on the footer's Details button, when the incident closes and the card compacts, then focus moves to the card itself through the focus rule (I7).
- AC11: Given payloads without `groups`, `requests`, `evidence`, `traceTargets`, `itemNoun` or a known `state`, when the card renders, then it leaves out the parts they feed and still renders (`incident-view.test`; I4).
- AC12 (owner decision U-108, applied by the runner after implement): Given an evidence item with one failure, when the Show details panel renders, then its item line reads "{item}: 1 failure, at {time}" (one time, the item's failure time), never "1 failures" and never "first X, last X"; given an item with more failures, then it reads "{item}: {count} failures, first {first}, last {last}". A unit test pins both forms, and `ux-strings`' ruled entry carries the new one-failure form.
  - [x] [Owner] U-108 condition: change `INCIDENT_TEXTS.itemLineOne` to `{item}: 1 failure, at {time}` and fill `{time}` in `incident-view.ts` (the page time `pageWhen` already gives item times); update `incident-view.test.mjs` (the one-failure line and the texts table) and the `ruled` entry in `ux-strings.test.mjs` ('Story 6.1 veto item V1 ... kept with U-108's condition'); the many-failure test stays. Write the Rule 19 `mutation:` line for it. (Applied by the code review, 2026-10-27; `incident.spec.ts` asserts no one-failure line, so it needed no change.)

### Review Findings

Code review 2026-10-27 (`bmad-code-review`, full mode, four layers at full-opus): 27 rows, 11 entries after grouping (high 0, med 4, low 7), 9 rejected entries (13 rows). Each entry: severity / fix-risk / footprint / spec-status, then its Rule 15 disposition.

- [x] [Review][Patch] AC12 (owner decision U-108) was not implemented: the one-failure item line still read "1 failure, first X, last X" [web/src/app/incidents/incident-view.ts:49] — med / low (one template and one branch, unit-pinned) / in-story / clear. Fixed: `itemLineOne` is "{item}: 1 failure, at {time}" (the item's one time, `pageWhen`); `incident-view.test` pins the one-failure form (same day and another day) and the many-failure form; the `ruled` entry is V1 kept with U-108's condition.
- [x] [Review][Patch] `incident.spec.ts` depended on the wall clock: I6 went red from 23:00 to 24:00 UTC (22:00 under CEST), when Berlin is already on the next date, and a run crossing 00:00 UTC turned every headline's "since 14:12" into a day form [web/e2e/floor/incident.spec.ts:31] — med (Rule 19 hermeticity) / low (test-only; `banners.spec.ts`'s `page.clock.setFixedTime` pattern) / in-story / clear. Fixed: one `DAY` for every time of the spec, and a `beforeEach` fixes the page's clock at 14:30 UTC on that date.
- [x] [Review][Patch] I2's and I5's whole-chat incident-card counts assumed no other noticed incident row on the shared FLOOR session [web/e2e/floor/incident.spec.ts:203] — med (Rule 19 hermeticity) / low (test-only) / in-story / clear. Fixed: both count against a baseline read after the page opens.
- [x] [Review][Patch] The evidence panel's label and value rows were flat `div`s, so assistive technology got no label-value structure; the sibling `decision-details.ts` uses `dl`/`dt`/`dd` [web/src/app/incidents/evidence-panel.ts:19] — low / low (markup only, class selectors kept) / in-story / clear. Fixed: the rows are a `dl` of `div` groups (`dt` label, `dd` values).
- [x] [Review][Patch] Rule 2: `TestIncidentKindsRecordOnly` repeated `TestOtherKindsRecordOnly`'s loop and its eight assertions, with only "split from" as the reason [src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls:167] — low (weak reason) / low / in-story / clear. Fixed: both call the private helper `AssertRecordOnly(session, kinds, what)`; the class passed, and the AC3 mutation was demonstrated again against it.
- [x] [Review][Patch] `publishIncident` threw "could not be published" with no reason when `%JSONImport` refused a payload [web/e2e/support/iris.ts:150] — low / low (one diagnostic line) / in-story / clear. Fixed: the import's error text comes back as a `CHK|error|` line, which the thrown message carries.
- [x] [Review][Patch] Two stale texts: the `PART`/`KEY` comment of `chat-panel.ts` named no incident card, and `incident-sources.test`'s scan test said "three components" for two [web/src/app/chat/chat-panel.ts:42] — low / low / in-story / clear. Fixed.
- [x] [Review][Patch] AC3's page half (`chat-view.test` "leaves out a notification of the incident kinds") had no `mutation:` line; I5 alone cannot go red on either half [web/scripts/chat-view.test.mjs:54] — low (Rule 19: pin exists, line missing) / low / in-story / clear. Closed in the pass: mutation demonstrated and recorded under `## Verification`.
- [x] [Review][Patch] AC9's second clause (a new ref after a closed one gives a second card) had only an unrecorded floor assertion (I2) [web/scripts/chat-view.test.mjs:49] — low (Rule 19) / low / in-story / clear. Closed in the pass: a `chat-view.test` case pins two entries in store order; mutation demonstrated and recorded.
- [x] [Review][Patch] The footer's "diagnosis trace link alone" branch (the matrix's "No decision in store" row) had no browser assertion, only a source match [web/src/app/incidents/incident-card.ts:110] — low / low (two assertions) / in-story / clear. Fixed: I3 asserts no strip and the link's served `traceUrl`.
- [x] [Review][Defer] After a page load an incident card's footer never finds its diagnosis decision: the snapshot seeds the store's decisions from the rail, which holds kind-`decide` decisions only, and the incident's `decisionRef` is its `diagnose` decision; I1/I7 pass because they seed a `decide`-kind decision [web/src/app/incidents/incident-view.ts:296] — deferred: med / med / out-of-footprint (`live-store.ts` and `Ownership.cls` are Epic 16's, `/state` and the payload are closed to this story) / clear; `escalated owner=burndown` as DW-294 (sibling of DW-292), for the decision sheet.

Rejected (not worth fixing, or false):
- `low` The card's day words go stale after midnight (its `view` reads `Date.now()` untracked) and the spoken headline can then differ from the card's (blind-hunter, edge-case-hunter, verification-gap). Only a page open across midnight with no new event for that card; the next event or a reload recomputes; `status-rail.ts` reads its clock the same way; the fix adds a ticking clock input.
- `low` An evidence item with no name or no readable time gives a broken mono line (blind-hunter, edge-case-hunter). `IncidentEvidenceItem` always carries them from the producer; the fix adds guard branches for a payload no producer makes.
- `low` The announcer builds a full card view per incident on every entries change (blind-hunter). A handful of string operations once a second while a turn runs; no user-visible cost named.
- `low` A cause or fix ending in "?", "!" or an ellipsis gets an added "." (blind-hunter, edge-case-hunter). Spec-bound (Decided 12: drop one final ".", add "."); the texts are catalog or diagnosis sentences.
- `low` A fallback or no-fix incident first seen in a closed, resolved or unknown state is announced "No fix proposed." (edge-case-hunter). Spec-bound (Decided 10's first-sight rule); an incident is first published open or awaiting approval.
- `false` Two ref-less incident payloads give duplicate track keys (edge-case-hunter). The live store keys incidents `incident:<ref>` and replaces in place, so the chat never holds two such entries; a real payload always has its Ref.
- `low` A panel that loses every row and later gets them back reopens by itself (edge-case-hunter). No producer drops every row: the cause row is row-backed and payloads are full views.
- `low` The footer strip ignores a fallback flag on the decision itself, unlike `noticeOf` (edge-case-hunter). Spec-bound (Task 4: the incident's `fallbackReason` when `fallback`); a diagnosis that falls back makes the incident a fallback.
- `false` `OnNotification` never reads `INCIDENTKINDS`, so an incident kind added to `CARDKINDS` would go unnoticed (edge-case-hunter). `TestIncidentKindsRecordOnly` goes red on exactly that change (demonstrated twice); Task 8 and Decided 15 fix the parameter as a named contract with no behaviour change.

## Spec Change Log

- 2026-10-27, runner (after implement, before QA): owner decision U-108 (answer 2026-10-27T06:47:31Z#330): V1's texts kept, with one condition: the one-failure item line reads "{item}: 1 failure, at {time}". Added as AC12 and an `[Owner]` task; the code-review stage applies it as a patch. U-109 (V2) kept, no change.

## Review Triage Log

### 2026-10-27 — Review pass
- verdicts: 36 findings — high 0, medium 2, low 32, false 2, maybe-false 0
- findings:
  - Blind Hunter (10):
    - `[low]` `[reject]` INCIDENTKINDS is not read by `OnNotification` — Task 8 and Decided 15 specify a named parameter with no behaviour change; `TestIncidentKindsRecordOnly` pins the value and the record-only behaviour; branching on it adds code for no behaviour.
    - `[low]` `[reject]` absent `count` reads "0 messages failed" — a real payload always carries `count` (row-backed); the fix adds a guard branch for a payload no producer makes.
    - `[low]` `[reject]` ref-less payloads share the key `incident:` — `Ref` is the incident's identity and always set; a guard is more than a direct correction.
    - `[low]` `[reject]` the relative day goes stale past midnight — only an open page across midnight; the next payload or reload recomputes; the fix needs a clock input in the card.
    - `[low]` `[reject]` literal `22px` and `1px` in styles — `fallback-flag.ts` and `outcome-chip.ts` use the same `min-height: 22px`; the border colour is a token.
    - `[false]` `[reject]` the h3's `tabindex="-1"` is a stray stop — Decided 13 requires it (6.4's Dismiss focuses the compacted headline); `-1` is no tab stop.
    - `[low]` `[reject]` no component-level tests — the web has no Angular test host; the floor cases I1-I10 drive the components in a browser.
    - `[low]` `[reject]` some matrix edges unasserted (item times in Berlin, empty instance zone, re-send after reload) — not reachable on the floor stack or by a real payload; no user-visible defect named.
    - `[low]` `[reject]` `ux-strings` sources padded — each string has a source as the spec requires; "Open", "Error" and "Awaiting approval" are held by EXPERIENCE.md.
    - `[low]` `[patch]` spec bookkeeping: the garbled "Approve?" mutation line is rewritten; the `Status:` line is rewritten at finalize.
  - Edge Case Hunter (17):
    - `[low]` `[reject]` item line with an absent time or name or count (3 rows: itemLines time; itemLines name; headline count) — `IncidentEvidenceItem` always carries them; guards add branches for no producer.
    - `[low]` `[reject]` fixing line "0 messages" with no count — same as the absent `count`.
    - `[low]` `[reject]` "Held as" while a request is pending on a resolved or closed incident — 6.2 defines request states; no producer makes the combination now.
    - `[low]` `[reject]` "Why?." from cause or fix text ending in "?" or "!" — Decided 12 specifies "drop one final '.', add '.'"; the texts are sentences from the catalog or the model.
    - `[low]` `[reject]` a fixSummary with "Approve it?" — Decided 12 strips the trailing "Approve?" the message form carries; other forms are not published.
    - `[low]` `[reject]` duplicate key of ref-less entries — same as the Blind Hunter's ref row.
    - `[false]` `[reject]` a null payload throws in `chatView` — the store only holds typed events; `IncidentPayload` is required by the generated type; no producer sends null.
    - `[low]` `[reject]` stale day past midnight — same as the Blind Hunter's row.
    - `[low]` `[reject]` the panel reopens by itself when its rows return — a panel row never disappears from a card that had it (payloads are full views).
    - `[low]` `[reject]` an intermediate state replaced twice between looks is never announced — the announcer says the state at each look; Decided 10 gives "announces when `state` changes" per look.
    - `[low]` `[reject]` a closed incident first seen later is announced "Closed." — Decided 10 sets the state form for any other state at first sight.
    - `[low]` `[reject]` `instanceZoneOf` repeats a throw on an empty zone — the snapshot always carries the zone; the throw is caught per call.
    - `[low]` `[reject]` INCIDENTKINDS deletion and claim rows (3 rows) — same as the Blind Hunter's INCIDENTKINDS row.
    - `[low]` `[reject]` AC11 "absent count shown as 0" — same as the absent `count` row.
  - Verification Gap (9):
    - `[medium]` `[patch]` AC5's " ET" is unpinned through the page wiring (`onlineDemo` to `incidentContext`) — added `I9` (a snapshot with `onlineDemo`: the headline and the announcement end " ET"); mutation `ChatPanel.onlineDemo` always false went red in I9.
    - `[medium]` `[patch]` the New messages focus for an incident card (`noteArrivals`) is unpinned — added `I10`; mutation: part `user` went red in I10.
    - `[low]` `[patch]` AC1 and AC10 had no demonstrated mutation — both demonstrated in the review pass (two floor runs) and recorded in `## Verification`; AC10 uses the lost `tabindex` because a lost `data-part` reddens every case.
    - `[low]` `[reject]` I5 stays green if only one side regresses — each side has its own pin (`TestIncidentKindsRecordOnly`, `chat-view.test`); I5 is the end-to-end agreement of the two.
    - `[low]` `[reject]` I5 and I4 assume an empty FLOOR chat — the floor project runs serially with `workers: 1` and every seeding case cleans in `finally`.
    - `[low]` `[reject]` `itemTime` and `topTime` mapping half-pinned — I6 pins the top time's suffix; swapping the item time's formatter has no visible effect in the zones the cases use.
    - `[low]` `[reject]` `headlineNoTime` is an unplanned text — recorded as Decided 16: the headline without its clause, no new claim.
    - `[low]` `[reject]` `ux-strings` source for `headlineNoTime` is a substring match — same as the previous row.
    - `[low]` `[reject]` source-text assertions are guards, not behaviour — they are labelled as guards in their headers and add no claim of behaviour.
  - Intent Alignment Auditor: no findings (descriptive; readings A3, B1, C1, D1 and E1 are the planned ones).

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-4** (L155): the snapshot reads incidents through `Ownership` (`RecentIncidents`: noticed, own or a watched instance's). No route takes a SessionRef. This story adds no read.
- **AD-12** (L330, incident payload L338): full views keyed by `Ref`, applied idempotently (the store's `incident:<ref>`); snapshot plus events. `traceUrl` is added only by `Web.TraceLink`.
- **AD-13** (L345): untrusted and model text bound as text; no `innerHTML`.
- **AD-14** (L396): each `*Out` records its `Delivery` row; `WebChatOut` stays the web chat's operation.
- **AD-15** (L408): `IncidentManager` alone writes incidents, decides `state` and `openVariant` and publishes `incident`. The page shows `state`, never a request's. The ownership read hides an incident until `NoticedAt`.
- **AD-26** (L737): trace targets are the diagnosis session (footer), the sample and the first failure (Orders namespace).
- **AD-29** (L777): Lane B builds against Story 0.5's fixed payload, with fixtures through `Live.Publish`, and builds no Lane A class.
- **AD-32** (L853): incident notices are kind `incident`; `answered` and `result` carry `ApprovalRef`. The web chat's copy of all four kinds is the card, so there is no notice card.
- **AD-33** (L865): one publisher per event type (`incident`: IncidentManager; `notification`: WebChatOut). This story adds none.
- **Conventions:** Enumerations (L917: display names live only in the catalog and the web app), Times (L920), Live events (L922), Notice cards (L924), Announcements and focus (L926; 6.1 is named), Angular (L939), Tests (L943: floor cases only in `live:floor`).
- No AC contradicts an AD's Rule, and no NFR trips Rule 5. NFR-24 (raw values only in Show details) is met by the panel. "Times rendered only through Data.Time" governs server rendering. The page's own renderer is `page-time.ts`, and `messageTime` mirrors `ForMessage` (Decided 3).

**Decided in-stage** (small, reversible, within the intent):
1. **Browser cases in `web/e2e/floor/incident.spec.ts`**, run by `live floor` as the FLOOR user.
   - `live sign-in` is at 452-463 s of 540 s, and Epic 4 ruled that it gains no case.
   - A new unit or fixture user needs a `docker/tests` edit (contended: Epics 10, 13, 15).
   - The floor folder joins with no script edit (`playwright-projects.test.mjs`).
   - Floor took 350 s at Story 4.7, and these cases add about 50-70 s (inference). I1 is tagged `@browsers`, the rest run in Chromium only.
2. **The top time is `lastAt`.** The payload has no `NoticedAt`, and `firstAt` already stands in the headline.
3. **The headline time is a message time**, mirrored from `Data.Time.ForMessage` in `page-time.ts`, plus " ET" on the online demo (UX-DR123: the headline is message text; mockup A7 shows none on a local install). The sibling `pageWhen` differs ("tomorrow at", the browser zone, the browser's clock format), so it is extended through shared helpers, not reused as is.
4. **The footer decision** is the store's decision with `ref === decisionRef`. When it is absent, only the diagnosis trace link shows. There is no snapshot member: the live store replaces chat items whole, so a member would vanish at the first event, and `live/**` is contended. The strip shows reasons (first line), because Story 5.4 says the incident card's strip shows the diagnosis reasons.
5. **Show details lives in an incident-level actions row** after the fix and fixing lines. Story 6.2 moves it to the right end of a request card's approval row, and 6.4 adds Dismiss to this row for cards with no request (the mockup A5 row).
6. **Category text**: replace `_` with spaces, collapse spaces, upper-case the first character ("data_format_change" → "Data format change"). `element` is shown as published (deferred item 2).
7. **The evidence line** shows only when `causeCategory` or `element` is set (a fallback has none, mockup A5). It joins the set ones and the grouping with " \u00B7 ", which `incident-view.ts` holds itself: a Node-run view module imports only types, so it can't import `CHAT_TEXTS` (" \u00B7 " already has its `format` source in `ux-strings`).
8. **The fixing count** is the first `requests[]` entry in state `executing` with a `result.total`. Otherwise it is `noticeCount`, and otherwise `count`.
9. **A closed card** keeps the chip row, the headline and the Show details row. The cause, evidence line, fix, more line, fixing line and footer go (6.4 adds the results).
10. **Announcements:**
    - At first sight, awaiting_approval → "… Approval needed."; `fallback` or `openVariant` `fallback`/`no_fix` → "… No fix proposed."; any other state → the V1 state form, so no announcement claims an approval that doesn't exist.
    - A known card announces only when `state` changes.
    - 6.2-6.4 fold their answered and result texts into the same update's text.
11. **Panel rows:**
    - "Held as an IRIS Workflow task until someone answers." shows only while some request is `pending`, so it never claims a task that doesn't exist.
    - Show details exists only when the panel has a row.
    - The panel's open state survives updates, because the card is tracked by key.
    - Item times are `pageWhen` page times.
12. **Small rules:**
    - Cause and fix sentences: trim, drop one final ".", then add "." (the fix as "I can {fixSummary}.").
    - With no `itemNoun`, the noun is "message"/"messages" (AD-15's default).
    - An unknown `state` shows no chip and the attention bar.
    - Unknown variants are ignored (`Fixture.Incident`'s "fix").
    - The evidence links carry their own text ("Sample message", "First failure"), so the panel has no two links both named "Trace".
13. **The headline is an `h3` with `tabindex="-1"`.** The chat's hidden heading is the `h2`, and 6.4's Dismiss focuses the compacted headline. The card root has `tabindex="-1"` so the focus rule and New messages can focus it.
14. **No `/state` change.** The snapshot already carries noticed incidents through `Ownership` (Story 2.2, pinned in `Test.Web.Api`). The missing parts are Lane A's builder (deferred item 1). The card renders without them.
15. **WebChatOut** gets a named parameter and its own test, with no behaviour change. The four kinds already took the record-only branch.

**Decided in-stage (implement):**
16. `INCIDENT_TEXTS.headlineNoTime` ("{count} {noun} failed"): the headline when `firstAt` is absent or unreadable, so it never reads "since" with nothing after it. It is the headline template without its time clause (no new claim; `ux-strings` sources it from EXPERIENCE.md's headline) and is not reachable with a real `IncidentManager` payload, whose `firstAt` is always set.
17. Review pass: reviewer findings closed `reject` (see the triage log) include `INCIDENTKINDS` not being read by `OnNotification` (Task 8 and Decided 15 fix it as a named parameter with no behaviour change) and the headline's "0" for an absent `count` (not reachable from a real payload).

**Veto-window choices** (the runner files them):
- **V1: public texts not written in the UX.** The question is what the new labels and texts read. Choice: the mockup's labels, ruled in `ux-strings` as 'Story 6.1 veto item V1':
  - "Cause", "Sample failed message", "Error", "Failures by item", "Sample message" and "First failure" (`mockups/states.html` A1);
  - the item lines "{item}: {count} failures, first {first}, last {last}" and "{item}: 1 failure, first {first}, last {last}";
  - the grouping's count of one, "1 failure grouped into this incident";
  - the state-change announcement "Incident: {headline}. {state}." (UX-DR72 says that state changes are announced, but gives no words).

  Rejected: no state-change announcement until 6.2-6.4 (that leaves AC7 unmet, and `closeQuiet` closes silently); new wording outside the UX's notice pattern. Reversing it takes one `INCIDENT_TEXTS` edit plus its `ruled` entry and tests.
- **V2: the sample appears as its IRIS header id plus a trace link, not as a body excerpt.** The question is how "a sample failed message excerpt" shows without an excerpt field. Choice: the header id in `mono-sm` under "Sample failed message", its `sampleError` under "Error", and the "Sample message" link, which opens the whole message. Story 0.5's `IncidentEvidence` (AD-12's field list) has only `sampleHeaderId` and `sampleError`, and AC1 limits the card to those fields; UX-DR78 reads "a sample failed message and its error". Rejected: deriving an excerpt from the error, or reading another field. Reversing it: Lane A appends `SampleExcerpt` to `IncidentEvidence` (AD-29: the owner appends), `payloads.ts` regenerates, and the panel shows it in the same row.

**Texts** (exact; written in code as `\u2026` for the ellipsis and `\u00B7` for the middle dot):
- **States:** "Open", "Awaiting approval", "Fixing", "Resolved", "Closed" (E:643-651).
- **Card:**
  - headline "{count} {noun} failed since {time}";
  - more "{n} more since the notice";
  - grouping "{count} failures grouped into this incident" and V1's count of one;
  - fix "I can {fixSummary}.";
  - fixing "Repairing and resending {count} {noun}…";
  - "Show details";
  - nouns "message"/"messages".
- **Panel:** the V1 labels and item lines; "Held as an IRIS Workflow task until someone answers.".
- **Announcements:** "Incident: {headline}. Approval needed." (E:429), "Incident: {headline}. No fix proposed." (AC), "Incident: {headline}. {state}." (V1).
- **Reused:** "Fallback" through `app-fallback-flag`. The separator " \u00B7 " is held again in `INCIDENT_TEXTS` (Decided 7). The online-demo suffix "ET" goes into `WHEN_TEXTS`.

**Files and footprint classes:**
- footprint: `web/src/app/incidents/{incident-view,incident-card,evidence-panel}.ts` (new); `web/src/app/chat/{chat-view,chat-panel,chat-announcements,page-time}.ts`; `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`; `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls`.
- extension (outside the footprint, owned by no contended epic): `web/scripts/incident-view.test.mjs` (new); `web/scripts/{page-time,chat-view,chat-announcements,ux-strings}.test.mjs`; `web/e2e/floor/incident.spec.ts` (new); `web/e2e/support/iris.ts` (one new helper).
- No shared-by-entry, shared-by-region, contended-new-file or contended-appended-block file is touched.

**Extend, don't copy (Rule 2):**
- `incident-card.ts` is a sibling of `notice-card.ts`. It is a separate component because its anatomy differs; it reuses `DecisionStrip`, `FallbackFlag`, `TraceLink` and `Icon`.
- `incident-view.ts` follows `decision-view.ts` and `chat-view.ts`'s `noticeOf`.
- `messageTime` and the dated, suffixed page time extend `pageWhen` and `pageTimeBeside` through shared private helpers.
- `chatAnnouncements` is extended, not copied.
- `publishIncident` follows `publishReminder`.
- `TestIncidentKindsRecordOnly` is split from `TestOtherKindsRecordOnly`.

**Integration ACs (Rules 1 and 2):**
- The chat panel (the consumer) reads the live store's `incident` events and the snapshot's incidents, and renders one card per Ref in a real browser (AC1, AC2; I1, I2, I4).
- `WebChatOut` (the consumer of Notify's incident-kind notifications, real production) records only the Delivery row, and the page shows no notice card (AC3; I5).

**Consumes:**
- Story 0.5: the `Incident` payload, its parts and `payloads.ts`.
- Story 2.2: `/state`'s incident entries via `Ownership.RecentIncidents` and `FromRow`; the live store's `incident:<ref>`.
- Story 2.6: `DecisionStrip`, `FallbackFlag`.
- Story 2.7: `WebChatOut`, `Delivery`, `sendNotification`.
- Story 2.12: `Announcer`, the focus rule.
- Story 2.13: `app-trace-link`, `Web.TraceLink`.
- Stories 2.5 and 2.7: `page-time.ts`.

**Consumed-by:**
- **6.2:** request cards inside the card. Show details moves into the approval row, the evidence panel is reused below it, and 6.2 adds the 1280×600 check.
- **6.3:** the rail row's focus jump to the card or request card (`data-part`, `tabindex="-1"`), and answered texts folded into the update's announcement.
- **6.4:** result bands, Dismiss in the actions row, the compact headline as focus target, and the fallback and no-fix notices with their groups.
- **Epic 11:** the real `incident` events.

**Ledger inbox:** none for this story.

## Verification

`<B>` means `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=6 stage=implement'`.
- The fresh tag is `e6s1i` and the warm tag `e6s1iw` (`ci/warm.sh up` once; `ci/warm.sh down` at the end, also after a failure). Never warm for `live`.
- One command per foreground call with `timeout: 600000`; one `iris_execute_tests` per message.
- Slot B (`ocutalon-slot-b`, `OCUTALON`, build 154) is for loading and compiling only (`iris_doc_load`, `baseDir` `src/ocutalon/cls`).
- **Task 0 (measured on slot B, 2026-10-27):** `Live.Payload.Incident.%New()` then `%JSONImport` of a camelCase JSON with `itemNoun`, `groups`, `requests[].result`, `evidence.items` and `traceTargets` returns OK, and `%JSONExportToString` gives the same JSON back. So `publishIncident` needs no server helper.
- The floor stack runs in demo mode (`e2e/floor/guide.spec.ts`). I3 first asserts `/state`'s `demoMode` true, so a changed stack fails loudly.

**Browser cases** (`web/e2e/floor/incident.spec.ts`; browser UTC/en-GB unless stated; FLOOR user; the decision seeded before the page opens):
- **I1:** the full awaiting-approval card and its exact texts in order. The bar is 4px in `--attention`, the chip carries its state token, and the footer has the chip Act and a trace link whose href is the diagnosis `traceUrl`. One announcement.
- **I2:** the same Ref goes count 52/fixing, then resolved, then closed. One card throughout, with the bars, lines, compaction and one state announcement per change. Then a new Ref gives two cards.
- **I3:** Show details: `aria-expanded`, the panel position and rows, `mono-sm` values, hrefs under `/ocutalon/trace/ocuorders/`. "Held as…" shows with a pending request and is gone on a card without one. A second press closes the panel.
- **I4:** the seeded noticed row has a card and the unnoticed one has none. The Announcer is silent at load.
- **I5:** the four incident-kind notifications through Notify, then a tell-now: the tell-now card appears and no other notice card does.
- **I6:** in Europe/Berlin, the top time ends with "CET"/"CEST" and the headline doesn't.
- **I7:** focus on the footer Details button; after `closed` it is on the card (`[data-part="incident"]`).
- **I8:** open with `rejected`, `expired`, `no_fix`, and `fallback: true`. The attention bar on all; the Fallback flag and no evidence line on the fallback card; "… No fix proposed." at first sight.
- **I9** (review pass): `/state` says `onlineDemo`; the headline ends " ET" in the card and in the announcement, and the top time stays a page time.
- **I10** (review pass): six cards make the list scroll; scrolled up, a new card shows New messages and the press focuses it.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, the new and edited view, string and source tests included.
- `npm --prefix web run lint` -- expected: exit 0.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s1iw ci/iris.sh class OcuTalon.Test.Core.WebChatOut` -- expected: `CLASS ... passed`, with `TestIncidentKindsRecordOnly` green.
- `<B> OCUTALON_RUN_TAG=e6s1i ci/iris.sh build` -- expected: the image and web bundle build. Run it before a browser run that should see changed web code.
- `<B> OCUTALON_RUN_TAG=e6s1i ci/iris.sh live floor` -- expected: PASS in all three projects, I1-I8 included. Record the time; expected about 420 s (inference) against 540 s.

`(once)`:
- `bash docker/tests/test-web-build.sh` -- expected: the build passes (payload and catalog checks, budgets).
- `<B> OCUTALON_RUN_TAG=e6s1i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e6s1i ci/iris.sh live sign-in` -- expected: PASS with its case count unchanged (the chat and notice specs see the edited panel), at about 452-463 s.
- `<B> OCUTALON_RUN_TAG=e6s1i ci/iris.sh live demo-path` -- expected: PASS; 04's and 05's `11.1` parts stay skipped.
- `bash ci/checks.sh` -- expected: exit 0.

**Shared surfaces:**
- The chat's entry list: incidents now render (`chat-view.test.mjs` L32 and L370).
- The `ux-strings` inventory and SOURCES (new `INCIDENT_TEXTS`).
- `WebChatOut`'s kind lists (`TestOtherKindsRecordOnly`).
- The chat announcer's record (`chat-announcements.test.mjs`).
- The FLOOR session: its chat, stream and guide. `Guide.Compute` reads its incident rows, so I4 removes its rows in `finally`. Published events stay on the stream, but a fresh page load replays none.
- `announce-focus-sources.test.mjs`'s lists: the card makes no announcement and no focus call.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | the card keeps the first payload it rendered (no in-place update) | I2 (the card still reads 50 and Awaiting approval). "Never duplicated" is the store's, pinned by `live-store.test.mjs` L156 (existing; contended file, not mutated) |
| 2 | `chatView` skips an incident whose payload has no `traceTargets` (a snapshot payload) | I4; `chat-view.test` |
| 3 | `WebChatOut.CARDKINDS` gains `incident` | `TestIncidentKindsRecordOnly` |
| 4 | the headline keeps a final period / the fix keeps "Approve?" | `incident-view.test`; I1 |
| 5 | `messageTime` ignores `onlineDemo` / the top time drops the zone suffix | `page-time.test`; I6 |
| 6 | the bar ignores `state` (always attention) | `incident-view.test`; I2 |
| 6 | closed does not compact | `incident-view.test`; I2 |
| 7 | `announcementOf` announces count changes too | `chat-announcements.test`; I2 (two texts) |
| 7 | the first look announces | `chat-announcements.test`; I4 |
| 8 | "Held as…" shown without a pending request | `incident-view.test`; I3 |
| 9 | `more` uses `noticeCount − count` | `incident-view.test`; I2 |
| 10 | the card root loses `data-part` | I7 (focus falls to main) |
| 11 | the view reads `payload.evidence.items` without a guard | `incident-view.test` (absent parts throw) |

**Measured (implement stage, 2026-10-27).**
- `live floor` (tag `e6s1i`): PASS, 109 passed (I1-I8 included, I1 in all three projects), Playwright 5.0 min, 385 s wall from the command to the lock release, against the 540 s deadline. The run before the selector fix (4 failures, all in I1/I2) took 365 s wall.
- Review pass: I9 (the online demo's " ET" through the page) and I10 (New messages focuses an incident card that lands while the list is scrolled up) added; `live floor` 111 passed, 397 s wall (Playwright 5.2 min).
- `(once)` runs after the last patch: `test-web-build.sh` passed; `shard lane-b` passed (58 classes, 191 s); `live sign-in` passed (217 cases, 447 s wall, under its 540 s deadline); `live demo-path` passed (93 s; 04 and 05 `11.1` parts skipped); `bash ci/checks.sh` exit 0 (its boundaries check made the three literal non-ASCII characters of `incident.spec.ts` escapes).
- `npm --prefix web test`: 763 pass. `npm --prefix web run lint`: exit 0. `OcuTalon.Test.Core.WebChatOut` (warm): passed.

**Demonstrated mutations (Rule 19).** Each was applied, observed red, reverted from a backup, and `git diff --stat` was identical after.
- mutation: `WebChatOut.CARDKINDS` gains `incident` -> red `TestIncidentKindsRecordOnly` (AC3)
- mutation: `chatView` skips an incident whose payload has no `traceTargets` -> red `chat-view.test` (AC2)
- mutation: the headline keeps a final period -> red `incident-view.test` (AC4)
- mutation: the fix sentence no longer removes a trailing "Approve?" from `fixSummary` -> red `incident-view.test` (AC4)
- mutation: `messageTime` ignores `onlineDemo` -> red `page-time.test` (AC5)
- mutation: `pageWhenBeside` drops the zone suffix -> red `page-time.test` (AC5)
- mutation: the bar ignores `state` (always attention) -> red `incident-view.test` (AC6)
- mutation: a closed card does not compact -> red `incident-view.test` (AC6)
- mutation: `announcementOf` announces count changes too -> red `chat-announcements.test` (AC7)
- mutation: the first look announces -> red `chat-announcements.test` (AC7)
- mutation: "Held as..." shown without a pending request -> red `incident-view.test` (AC8)
- mutation: `more` uses `noticeCount - count` -> red `incident-view.test` (AC9)
- mutation: the view reads `evidence.items` without a guard -> red `incident-view.test` (AC11)
- mutation: the card keeps the first payload it rendered (`incidentView(this.firstSeen ??= this.incident(), ...)`) -> red `live floor` I2, I3 and I7 (AC1; the review pass, one floor run)
- mutation: `ChatPanel.onlineDemo` always false -> red `live floor` I9 (AC5, the page wiring of " ET")
- mutation: `noteArrivals` gives an incident card the part `user` -> red `live floor` I10 (New messages focus; the same run as the AC1 mutation)
- mutation: the card's `article` loses `tabindex="-1"` -> red `live floor` I7 and I10 (AC10: focus stays off the card; run of its own). The planned mutation (the root loses `data-part`) is not used, because every case that finds the card by `data-part` would go red with it.

**QA stage (2026-10-27, tag `e6s1q`).** AC1-AC11 each had a pinning test and a demonstrated mutation; AC12 is the code-review stage's. The gaps found and closed:
- (QA) `web/scripts/incident-sources.test.mjs` (new, 16 tests): the card's root, headline and Show details attributes (AC10, AC8), the panel directly below the row and only while open (AC8), the footer strip's inputs (AC4), text bound by interpolation and no trace URL built (AC8), no colour literal, and each chip and bar class the view can return reading its own state tokens (AC6; the floor asserts the tokens of only the awaiting-approval and fixing chips).
- (QA) `web/e2e/floor/incident.spec.ts`: I1 now also asserts the footer strip's confidence, its own cost, the first reason line only and the Details button (AC4); new I11, markup in the cause, fix, element, sample error and item name is shown as text in the card and the panel (AC8, AD-13); I5 removes the Delivery and phone rows it made on the shared FLOOR session (`dropPhone`), so later specs do not open a chat with its tell-now card (hermeticity).
- `live floor` after the QA edits: PASS, 112 passed (I11 added), 401 s wall (397 s before), against the 540 s deadline. `npm --prefix web test` 779 pass; lint and `bash ci/checks.sh` exit 0.
- mutation: the card's root loses `tabindex="-1"` -> red `incident-sources.test` "is an article that the focus rule and New messages find" (AC10)
- mutation: the footer strip is bound `[reasons]="false"` -> red `incident-sources.test` (footer inputs) and, in one `live floor` run, I1 in Chromium, Firefox and WebKit (the strip's reason line) (AC4)
- mutation: `.chip-resolved` reads the closed state's tokens -> red `incident-sources.test` (each chip reads its own tokens) (AC6)
- mutation: the panel's lines and the card's cause are bound with `[innerHTML]` -> red `incident-sources.test` (two tests) and `live floor` I11 (AC8; the same run as the `[reasons]` mutation: 4 failed, 108 passed)
Each mutation was applied from a backup, observed red, reverted from that backup, and `git status --short` and `git diff --stat` were identical afterwards.

**Code review (2026-10-27, tags `e6s1r` and warm `e6s1rw`).** AC12 applied (owner decision U-108); `incident.spec.ts` now fixes the page's clock at 14:30 UTC on the spec's one date (`DAY`) in a `beforeEach`, and I2 and I5 count incident cards against a baseline read after the page opens; I3 also asserts the footer's lone diagnosis trace link; `chat-view.test` gained the closed-then-new-ref case; `Test.Core.WebChatOut`'s record-only tests share `AssertRecordOnly`.
- mutation: `itemLinesOf` gives a one-failure item the many-failure form (`count === 1` -> `count === -1`) -> red `incident-view.test` "writes one line per item: one failure with its one time, ..." (AC12)
- mutation: `noticeOf` accepts kind `incident` -> red `chat-view.test` "leaves out a notification of the incident kinds" (AC3, the page's half)
- mutation: `chatView` drops a closed incident's entry -> red `chat-view.test` "keeps a closed incident's card when a new ref comes after it" (AC9, the second card)
- mutation: `WebChatOut.CARDKINDS` gains `incident` -> red `TestIncidentKindsRecordOnly` (AC3, demonstrated again after its assertions moved into `AssertRecordOnly`; warm, and green again on the same stack after the revert)
- After the patches: `npm --prefix web test` 780 pass; `npm --prefix web run lint` exit 0; `bash ci/checks.sh` exit 0 (71 s); `OcuTalon.Test.Core.WebChatOut` passed (warm); `live floor` (fresh, after `ci/iris.sh build`) 112 passed, Playwright 5.2 min, 400 s wall against the 540 s deadline.
Each mutation was applied from a backup, observed red, reverted from that backup, and `git status --short` and `git diff --stat` were identical afterwards.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: each incident Ref is one card in the chat, updated in place from the store's `incident` payload. The card has the state chip with the page time, the headline (instance time, " ET" on the online demo), the more, cause, evidence, fix and fixing lines, an inline Show details evidence panel, and the diagnosis decision's strip as footer. The bar follows the state, a closed card compacts, and the chat announces a new incident and each state change once. `WebChatOut` names its incident kinds as `INCIDENTKINDS` (record-only), with its own test.
- Files changed: `web/src/app/incidents/{incident-view,incident-card,evidence-panel}.ts` (new: view model and texts, card, panel); `web/src/app/chat/{chat-view,chat-panel,chat-announcements,page-time}.ts` (incident entries, rendering, announcements, `messageTime` and `pageWhenBeside`); `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` and `Test/Core/WebChatOut.cls` (`INCIDENTKINDS`, `TestIncidentKindsRecordOnly`); `web/scripts/{incident-view (new),page-time,chat-view,chat-announcements,ux-strings,announce-focus-sources}.test.mjs`; `web/e2e/support/iris.ts` (`publishIncident`); `web/e2e/floor/incident.spec.ts` (new, I1-I10).
- Review (36 findings): patches applied 4 (I9 and I10 added for the online demo's " ET" and the New messages focus, medium x2; the AC1 and AC10 mutations demonstrated, low; a garbled mutation line, low); deferred 0 beyond the plan's two cross-lane items; rejected 32, each with its reason in the triage log (mostly unreachable edge cases of payloads no producer makes, and plan-specified behaviour).
- Follow-up review recommended: true. Two medium patches were applied (both new floor cases, no source change); the unverified risk is the floor's added time (111 cases, 397 s wall) and I10's reliance on six published cards to make the list scroll.
- Verification: `npm --prefix web test` 763 pass; lint exit 0; `OcuTalon.Test.Core.WebChatOut` passed (warm, and inside `shard lane-b`, 58 classes); `live floor` 111 passed, 397 s; `live sign-in` 217 passed, 447 s; `live demo-path` passed; `test-web-build.sh` and `ci/checks.sh` passed. Mutations: 13 unit-level and 4 floor-level demonstrated red and reverted byte-identical.
- Residual risks: the snapshot carries no groups, requests, evidence or trace targets (deferred item 1), so a reloaded card shows no request, evidence or diagnosis link until the next event; `live floor` is at about 397 s of 540 s.
