---
title: 'Story 39.5: The Heartbeat checklist card, and Run the heartbeat now'
type: 'feature'
created: '2026-11-06'
status: 'ready-for-dev'
baseline_revision: '2eed481455fa24140e30fde9a10b2eaf498ca441'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 39.2 shipped `GET`/`PUT /api/v1/heartbeat` and `POST /api/v1/heartbeat/run`, and Story 39.7 shipped the `heartbeat` live event. Even so, a person still has no page surface to write a checklist, set when it runs, see what the last beat did and cost, or run it now. The live store also ignores the `heartbeat` event, and no route gives today's heartbeat count and cost.

**Approach:**
- Add a "Heartbeat checklist" rail card under `web/src/app/rail/heartbeat-card/`, built as a sibling of the Persona card. It sits in its own rail section before Persona.
- The card reads `GET /v1/heartbeat` when it is made, and again after every `heartbeat` event the store now keeps.
- It saves with `PUT`, runs with `POST .../run`, and takes the cap and key state from the store's `dailyCap` and `noModelKey` status conditions.
- The GET gains three members, all from Lane B reads: `today` (the session's heartbeat Usage rows in the cap's day), `lastFallbackReason` and `onlineDemo`.

## Boundaries & Constraints

**Always:**
- Lane B files only (U-177). `Checks/**`, `Data/HeartbeatBeat.cls`, `Live/Payload/Heartbeat.cls`, `Agent/Triage.cls`, `Test/Checks/**` and `docker/tests/test-triage-heartbeat.sh` are read only. The `heartbeat` payload and `payloads.ts` stay as generated.
- Every user-facing string is one listed under Design Notes › Public text, word for word. The card's constants live in `HEARTBEAT_TEXTS` and are composed so that each constant is a verbatim UX run or a ruled string, pinned by `ux-strings.test.mjs`. The server's messages are shown as received, except the two unavailable reasons, which the page holds and a node test pins against `Web.Api`.
- Times are rendered with `pageWhen` (the browser's zone), as the rail's rows are. `from`/`to` are shown as stored (instance-zone wall clock). Costs use `formatCost`.
- Every control has a label and works by keyboard (NFR-25). The card is no live region and announces nothing. It moves focus only for the user's own Esc, and through `keepFocus` to its heading when its own read removes the focused element.
- The card uses neither the class `empty` nor `hint`, and no `aria-live`/`role=status|alert|log`, because the demo-path and rail floor tests select those inside the rail.
- No text renders a beat or an Ignore as "all is well" (AD-28): Ignore is "Stayed quiet".
- ASCII only in product files (non-ASCII as `\u` escapes); contract-only comments (Rule 14); no machine path in a committed file.

**Never:**
- No change to `Checks`' run-now rules, the event payload, `Live/Publish.cls` or any Lane A file. No new route, verb, production item, task or timer.
- No edit to a file in Epic 11's or 17's diff (checked 2026-11-06: none of this story's files).
- No change to the demo-path specs beyond the one rail count in `web/e2e/demo-path/01-page.spec.ts`. That edit is subject to the amendment under Auto Run Result.
- No real key and no real bot. No test on slot D.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| GET today | the session has Usage rows with Channel `heartbeat` today (2 Items, 3 rows), one yesterday, one of another session, one on channel `web` | `today` `{"checkIns":2,"costUSD":<sum of the 3 rows>}` | a failed read: 500 `server_error` (as any GET read) |
| GET today, none | no heartbeat Usage row today | `today` `{"checkIns":0,"costUSD":0}` | none |
| GET fallback reason | row `LastFallback` 1, its decision's `FallbackReason` `timeout` | `lastFallbackReason` `"timeout"`; the member is absent when not a fallback or the decision is not the session's | none |
| GET onlineDemo | `onlineDemo` setting on / off | `onlineDemo` true / false (boolean) | none |
| Card off | GET `on` false | "Off. Turn it on to have OcuTalon look at your list every 30 minutes." | none |
| Card on | on, 60, 07:15-21:45, `nextDueAt` set | "Every 1 hour, 07:15 to 21:45 · Next check-in {time}"; all day: "Every 1 hour · Next check-in {time}"; no `nextDueAt`: the part before the separator only | none |
| Last check-in | `lastBeatAt` newer than `lastSkipAt`; outcome ignore/tellnow/digest/act/fallback | "Last check-in {time} · Stayed quiet · {cost} · Trace" (Told you now / Saved for the digest / Offered an action / Couldn't decide: {plain reason}); no outcome yet: "Last check-in {time}" alone; cost and Trace only when present | an unknown outcome shows the time alone |
| Last skip | `lastSkipAt` newer, reason empty/hours/unchanged/cap/nokey/backoff | "Skipped at {time}: " + the UX reason; backoff: "...until {time}" from `backoffUntil` | an unknown reason: no skip line |
| Today line | `today.checkIns` 0 / 1 / 3 | none / "Today: 1 check-in, {cost}" / "Today: 3 check-ins, {cost}" | none |
| Live update | a `heartbeat` event arrives | the store keeps it; the card reads GET again and shows the new state without a reload | a failed read: the section heading alone, read again on the next event |
| Save | Edit, change any value, Save | `PUT` `{on,interval,from,to,checklist}` (all day: both `""`); the server's message "Saved. Applies within a minute. Recorded in the audit log." under Save; the card reads again | 400 `bad_checklist`/`bad_hours`/`bad_interval`/`bad_on` beside its field (aria-invalid, aria-describedby); other errors under Save, the busy notice when there is no message, then a re-read |
| Counter | typing in the checklist | "{n} of 1,000 characters" (UTF-16 units, as `$Length`) | none |
| Run | press "Run the heartbeat now" | `POST /run`; 202: re-read, button disabled with "You can run it again at {time}." until `lastRunNowAt` + 120 s, then enabled again | 409 `cooldown`: disabled to `availableAt`; 409 `cap`/`nokey`/`empty`/`backoff`: the server's message under the button; 5xx: busy notice |
| Unavailable (DW-634) | store status `dailyCap` active (or else `noModelKey` active) | button disabled with "Today's cost limit has been reached." (or "No model key is set."), described by that line | precedence: cap, nokey, cooldown |
| Online demo (DW-781) | GET `onlineDemo` true, `sample` true, `on` false | the Off line, the online-demo note, the sample in Edit's checklist; a Run press first `PUT`s the shown values (sample checklist, on false), shows the server's saved line, then `POST`s run | a failed PUT shows its message and sends no POST |
| Integration (39.2 routes, 39.7 event) | a real stack; the card saves a checklist with a `heartbeat-ignore` marker, `on` false | reload: Edit shows the saved values; Run: 202 and cooldown; then, from the tick's event with no reload: "Last check-in {time} · Stayed quiet · {cost} · Trace" and "Today: 1 check-in, {cost}" | the case cleans its keys, row, decision and usage rows |

</intent-contract>

## Code Map

**Web: the sibling and the files to change**
- `web/src/app/rail/persona-card/persona-card.ts` (468 lines) and `persona-card-view.ts`: the sibling to mirror.
  - The read-on-key effect (`pendingRefs` → `read()`), `keepFocus` with `FOCUS_RULE` to the heading, the disclosure (`aria-expanded`/`aria-controls`) and its Esc `collapse()` (with the `Popovers.hasOpen` guard).
  - Save through `ServerButton` (`[action]`, busy notice), `failureOf` (code → field), `saved`/`failed`, the ids prefix per card, and the styles (`.note`, `.help`, `.field-error`, `.input`).
  - `counterText` is reused as it is: the same UX string and counting rule.
- `web/src/app/rail/rail-view.ts`:
  - `RAIL_TEXTS` gains `heartbeat: 'Heartbeat checklist'`.
  - `SectionId` gains `'heartbeat'`.
  - `railView` pushes the heartbeat section (no count, rows `[]`) before the persona push, which stays last.
  - Add `heartbeatReadKey(store)` (JSON of `store.heartbeat`, `''` when undefined), as `personaReadKey` does.
- `web/src/app/rail/status-rail.ts:83,96-99`: imports and `@else if (section.id === 'heartbeat') { <app-heartbeat-card /> }`, plus the doc.
- `web/src/app/live/live-store.ts`:
  - `LiveStore` gains `heartbeat: HeartbeatPayload | undefined`.
  - `fromSnapshot` sets `undefined`, because `/state` carries none.
  - `applyEvent` gets a `case 'heartbeat'` that replaces it. `COLLECTIONS.heartbeat` is already `{collection:'heartbeat',key:null}`.
- `web/src/app/live/payloads.ts:314`: `HeartbeatPayload` (generated, read only).
- `web/src/app/api/persona-types.ts`, `api-client.ts:184-192`: the shape for `heartbeat-types.ts` and three client methods (`BASE` = `/ocutalon/api/v1`). The interceptor adds the envelope to PUT and POST.
- `web/src/app/chat/page-time.ts:183` (`pageWhen`), `chat/decision-view.ts:72` (`formatCost`), `chat/decision-strip.ts:23` (`fallbackReasonText`: the plain reason, lower case), `chat/chat-view.ts:59` (`CHAT_TEXTS.separator` " · "), `shared/trace-link.ts` (`app-trace-link`, input `url`; text `TRACE_TEXTS.trace` "Trace"), `shared/server-button.ts:10` (`BUSY_NOTICE`).
- `live.store().status['dailyCap'|'noModelKey']?.active`: the same conditions the banners read (`banners/banner-view.ts`).

**Server (Lane B)**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:402-433`:
  - `Heartbeat(sessionRef, .sc)` builds the GET object: FromRow's members, then `checklist` and `sample`.
  - `OnlineDemo()` exists.
  - Add `today`, `lastFallbackReason` and `onlineDemo` here, after `sample`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `Rows` (715) with binds `o`/`a`, and `Statement` (≈754). `runUsage` at 810 is the Usage statement to mirror.
  - `Decision(ref, sessionRef, .sc)` (453) reads the fallback reason.
  - `Sum` (private) is for token totals; do not reuse it for the count.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`: `Channel`, `OwnerRef`, `ItemId`, `CostUSD`, `RecordedAt` (UTC). This is Lane A, read only, and the AD-20 ledger. A heartbeat Item's Usage rows carry Channel `heartbeat`, as `Checks.Beat.DecisionLines` already relies on.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls:41-47`: the cap's day is the instance-zone local date, from `DayStartUtc` (inclusive) to `DayEndUtc` (exclusive). Outside the bridge the same day comes from `Data.Time`: the local date is the first 10 characters of `ToLocal(NowUtc())`, and its bounds are `FromLocal(date_"T00:00:00")` and the next date's (AD-18: `Data.Time` is the only converter outside the bridge, with the same zone source).
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls:64-84` (read only): `SUBJECT`, `RUNNOWSECONDS` 120, and the `SKIP*` values `empty, hours, backoff, cap, nokey, unchanged`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:153` and following (read only for this story): the `MESSAGERUNCAP` and `MESSAGERUNNOKEY` texts the page copies.

**Tests to extend or update**
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsHeartbeat.cls:298` pins the exact default JSON, so it must change.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls`: `TestGetDefaults` (115), `TestGetOnlineDemoSample` (129), `TestGetRowView` (165), `TestRunSendsThenCoolsDown` (406: the real-beat technique, `Beatable`, the marker, waiting for `DecisionOfItem`, `ItemIds` clean-up).
- `web/e2e/persona-card.spec.ts`: the shape of the new browser spec.
  - Its helpers are `withCard`, `rail`/`card` locators and `stored` through `irisScript`, plus `web/e2e/support/persona.ts` (`sessionRef`, `forget`, `prepare`) and `support/iris.ts` (`irisScript`, `chk`, `cleanFixtureRows`).
  - It uses `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`, and PC6 rewrites one member of the real GET.
- Shared-surface tests:
  - `web/scripts/rail-view.test.mjs:145,152` (section id lists);
  - `web/scripts/live-store.test.mjs:314` (pins that the store ignores `heartbeat`, so it must change);
  - `web/scripts/ux-strings.test.mjs:41-60` (`IMPORTED`) and `SOURCES` (`ux`, `ac`, `ruled` tables at ≈167, 510, 530);
  - `web/scripts/floor-sources.test.mjs:109,156,171` (`KEY_HANDLERS`, bindings, `ESC_HOSTS`);
  - `web/scripts/announce-focus-sources.test.mjs:132`;
  - `web/e2e/rail/rail.spec.ts:103,130,477` (six sections, six `h3[tabindex]`);
  - `web/e2e/frame/frame.spec.ts` F1 (headings);
  - `web/e2e/floor/layout.spec.ts` (search for rail heading counts);
  - `web/e2e/demo-path/01-page.spec.ts:103` (`toHaveCount(6)`, "Persona last").
- `web/playwright.config.ts:45,66-75`: a top-level `web/e2e/*.spec.ts` is in project `chromium`, which is unit `live:sign-in`, group `browser`. `rail/` is `sign-in-2` (shards-4).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add `ClassMethod HeartbeatToday(sessionRef, Output sc) As %DynamicObject` and a `Statement` kind `heartbeatUsage`.
  - The statement is `SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat' AND RecordedAt >= ? AND RecordedAt < ?`, with binds `oaa`.
  - The day bounds come from `Data.Time` as the Code Map says.
  - It answers `{"checkIns": <distinct non-empty ItemId>, "costUSD": <sum of CostUSD>}`, both numbers. A failed read is `{}` with an error status.
  - Add it to the class doc's list of reads -- AD-4, AD-20, AD-18.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- in `Heartbeat`, after `sample`:
  - set `today` from `Ownership.HeartbeatToday` (an error goes to `sc`; the GET is then 500, as for a row read);
  - set `lastFallbackReason` (string) only when the row's `LastFallback` is 1 and `Ownership.Decision(row.LastDecisionRef, sessionRef)` is an object with a non-empty `FallbackReason`;
  - set `onlineDemo` (boolean, `..OnlineDemo()`);
  - update the doc. Never add the decision Ref, the ItemId or the SessionRef -- AD-12, AD-19, AD-20.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- doc only: the GET's added members -- AD-12.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsHeartbeat.cls` -- `TestHeartbeatRead`:
  - the exact default JSON gains `"today":{"checkIns":0,"costUSD":0},"onlineDemo":false`;
  - add `TestHeartbeatToday` (matrix rows "GET today" and "GET today, none": insert Usage fixtures for this session today on `heartbeat`, two Items and three rows; one yesterday by `RecordedAt`; one of another session; one on `web`; then remove them);
  - add `TestFallbackReason` (a Decision fixture with `FallbackReason` and a HeartbeatBeat row with `LastFallback` and `LastDecisionRef`; another session's decision gives no member);
  - add the onlineDemo flag both ways, restoring `onlineDemo` -- Rule 19.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls` -- `TestGetDefaults` and `TestGetOnlineDemoSample` also assert `today` and `onlineDemo`. `TestRunSendsThenCoolsDown` also asserts, after the decision is recorded, that the GET's `today.checkIns` is at least 1 and `today.costUSD` equals the sum of the session's heartbeat Usage rows. This is the real-production consumer of `HeartbeatToday`.
- `web/src/app/api/heartbeat-types.ts` (new; mirrors `persona-types.ts`) -- `HeartbeatState`, `HeartbeatPut` and `HeartbeatSaved`, plus the 409 body.
  - `HeartbeatState` is `HeartbeatPayload` and `checklist`, `sample`, `onlineDemo`, `today: {checkIns:number; costUSD:number}`, `lastFallbackReason?`.
  - The 409 body is `{error:{code,message}, availableAt?}`.
- `web/src/app/api/api-client.ts` -- `heartbeat()` (GET), `saveHeartbeat(body)` (PUT), `runHeartbeat()` (POST `.../heartbeat/run`, an empty body), each a one-line doc.
- `web/src/app/live/live-store.ts` -- the `heartbeat` field, its `fromSnapshot` value and the `applyEvent` case; update the module doc -- AD-12.
- `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts` (new; framework-free, as `persona-card-view.ts`) -- `HEARTBEAT_TEXTS` (every card constant of Public text), `RUN_NOW_SECONDS = 120`, `INTERVALS` (30, 60, 120, 240, 480, 1440 with their names), `QUARTER_HOURS` (00:00 to 23:45), and pure functions:
  - `stateLine(state, when)`: the off line, or the on line with or without hours and next check-in;
  - `lastLine(state, format)`: the newer of check-in and skip, as parts, plus the trace URL;
  - `todayLine(today, cost)`: `''` at 0;
  - `cooldownUntil(state, availableAt)`;
  - `unavailable(store)`: `'cap'|'nokey'|''`;
  - `saveBody(form)`;
  - `failureOf(error)`: `checklist|hours|interval|on|save`, the message, `availableAt`.
- `web/src/app/rail/heartbeat-card/heartbeat-card.ts` (new; extends the Persona card's pattern) -- `app-heartbeat-card`:
  - It reads `api.heartbeat()` when made and on each `heartbeatReadKey` change. A failed read shows nothing.
  - Collapsed: the state line, the last line (`app-trace-link` for Trace), the Today line, the online-demo note when `onlineDemo`, an "Edit" disclosure button, and "Run the heartbeat now" with its describing line (cooldown or unavailable reason, else the last run answer).
  - Edit, open: an "On" checkbox; the "Interval" select; an "Active hours" fieldset with an "All day" checkbox and the "From" and "To" selects; the "Checklist" textarea with its help and counter; and Save (a ServerButton). The refusals show beside their fields; Esc collapses (with the Popovers guard).
  - A clock signal re-enables Run at the cooldown's end.
  - Run with `sample` true is PUT then POST (DW-781). Run is disabled at cap or nokey (DW-634).
  - It has no live region and announces nothing.
- `web/src/app/rail/rail-view.ts`, `status-rail.ts` -- the slot, the section and `heartbeatReadKey` (Code Map); update both docs.
- `web/scripts/heartbeat-card-view.test.mjs` (new; mirrors `persona-card-view.test.mjs`):
  - every row of the matrix that the view decides (each outcome, each skip, all day, no next check-in, the Today line at 0, 1 and 3, cooldown from `lastRunNowAt` and from `availableAt`, unavailable precedence, `saveBody` all day, `failureOf` per code);
  - `RUN_NOW_SECONDS` equal to `Checks/Beat.cls` `RUNNOWSECONDS`;
  - the cap and nokey texts equal to `Web/Api.cls` `MESSAGERUNCAP` and `MESSAGERUNNOKEY`, read from the class files;
  - the `SKIP*` values equal to `Beat.cls`'s.
- `web/e2e/heartbeat-card.spec.ts` (new; mirrors `persona-card.spec.ts`; the README account, its heartbeat keys, `HeartbeatBeat` row and the decision and Usage rows of its beats removed before and after every case) -- HC cases:
  - HC1: the section heading, before Persona; the default state line and the empty-checklist skip line after a forced skip, or the on line when there is no row.
  - HC2: Edit by keyboard alone: change every value; Save; the saved line; `stored` keys; a reload shows them.
  - HC3: a checklist with `{{` is refused beside the checklist (aria-invalid, describedby); nothing stored.
  - HC4 (Integration): save a checklist with `[[mock:heartbeat-ignore:<key>]]`, on false; Run gives 202 and the button is disabled with the cooldown line; within 90 s and with no reload, the "Stayed quiet" check-in line with cost and a Trace link, and "Today: 1 check-in, {cost}".
  - HC5: a second Run within 2 minutes is disabled, and after a reload still is (from `lastRunNowAt`).
  - HC6: `/state` rewritten with `dailyCap` active gives the cap reason; with `noModelKey` the nokey reason; both disabled with no POST.
  - HC7: GET rewritten (`onlineDemo` true, `sample` true, the sample, on false) gives the Off line, the note and the sample in Edit; Run sends PUT then POST in that order, and the stored checklist is the sample (the POST is fulfilled 202 by the route, so no fallback beat runs).
  - HC8: GET rewritten with each outcome and skip in turn shows the UX lines, including "Couldn't decide: the model didn't answer within 60 seconds".
  - HC9: Esc in the open Edit collapses it and focuses Edit.
- `web/e2e/demo-path/01-page.spec.ts:103` -- **only after the amendment below is applied:** `toHaveCount(7)`, the message reading seven sections with Persona last. Nothing else in any demo-path spec changes -- REL-2.
- Shared-surface updates:
  - `web/e2e/rail/rail.spec.ts` (103, 130, 477: seven, with the R1 headings filter leaving Heartbeat out as it leaves Persona out);
  - `web/e2e/frame/frame.spec.ts` F1;
  - `web/e2e/floor/layout.spec.ts` if it counts rail headings;
  - `web/scripts/rail-view.test.mjs` (the section lists gain `'heartbeat'` before `'persona'`, `RAIL_TEXTS.heartbeat`, `heartbeatReadKey`);
  - `web/scripts/live-store.test.mjs:314` (the store now keeps the latest heartbeat payload and nothing else changes);
  - `web/scripts/floor-sources.test.mjs` (the card's Esc host and binding);
  - `web/scripts/announce-focus-sources.test.mjs` (one focus move: Edit after Esc);
  - `web/scripts/ux-strings.test.mjs` (`IMPORTED` gains `HEARTBEAT_TEXTS`; `SOURCES` gets each string under `ux`, or under `ruled` with the lead's ruling id for the strings marked new).

**Acceptance Criteria:**
- Given a signed-in person, when the page loads, then the rail shows the "Heartbeat checklist" section, a heading of level 3 before Persona, with `app-heartbeat-card` from `web/src/app/rail/heartbeat-card/` as its body and one slot in `rail-view.ts`; it shows the state, the last check-in or skip, and the Today line in the UX's texts (FR-63, FR-65).
- Given `GET /api/v1/heartbeat`, when the session has heartbeat Usage rows today, then `today` counts their distinct Items and sums their cost for the cap's day only, and `lastFallbackReason` and `onlineDemo` are present as specified.
- Given a `heartbeat` event in a poll, when the store applies it, then the card shows the new state without a page reload (AD-12).
- Given Edit, when the person changes the values with the keyboard and presses Save, then `PUT /api/v1/heartbeat` is sent and the server's saved line shows, or the refusal shows beside its field (FR-63, NFR-25).
- Given "Run the heartbeat now", when pressed, then `POST /api/v1/heartbeat/run` is sent; during the cooldown the button is disabled with "You can run it again at {time}."; and while `dailyCap` or `noModelKey` is active it is disabled with the ruled reason (FR-66, DW-634).
- Given the online demo, when a visitor opens the card, then it is off, the note shows, Edit holds the sample, and Run saves the sample before it runs (FR-63, FR-66, DW-781).
- Given `web/e2e/heartbeat-card.spec.ts` on the CI mock, when it runs, then it covers the states, the refusal, the cooldown, the unavailable reasons and the demo variant, and HC4 runs against the real routes and the real tick; the demo-path specs change only by the one amended count (REL-2).

## Spec Change Log

- 2026-11-06 (lead, after the plan halt): epics.md Story 39.5's REL-2 clause amended as the plan recommended (unattended ruling, veto U-295): the Playwright specs change no demo-path spec except the rail's section count in `web/e2e/demo-path/01-page.spec.ts`, six to seven headings, Heartbeat checklist before Persona. Status set to ready-for-dev without a re-plan; the Public text table goes to the Contest Planner before implement.

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-12: the store keeps the `heartbeat` event and the card re-reads on it; the payload stays generated.
- AD-13: the envelope on PUT and POST, through the existing interceptor; the session only.
- AD-18 (Agent heartbeat › Run now, Online demo, Event): the 2-minute rule, the skip reasons, the sample checklist on the demo.
- AD-19: the per-person values through 39.2's routes; no new key.
- AD-20: today's cost from Usage rows, in the cap's day.
- AD-25: on the online demo the card works over polling alone, with no new path.
- AD-28: no all-clear text.
- AD-29: Lane B; U-177.
- AD-33: SettingsOps publishes nothing; Checks stays the event's publisher.
- Web conventions: the times rule (the page uses the browser's zone), the UX's "an h3 per rail section and card headline" (EXPERIENCE › Titles and headings).

**U-268:** this story cites neither AD-1 nor AD-14 and relies on neither the tool list nor digest routing. It uses 39.2's routes as they are.

**Decided in-stage:**
- Today's count and cost: the session's Usage rows with Channel `heartbeat`, recorded in the daily cap's day (`Data.Time`, the same zone source as `Bridge.Budget`).
  - The count is distinct ItemIds, so it counts beats that reached the model; an Act's read-only turn shares the beat's Item and adds cost, not a check-in.
  - All of this is Lane B: an `Ownership` read and a `SettingsOps.Heartbeat` member. No Lane A change.
  - A beat whose request never left (no Usage row) is not counted (inference: rare; no spend).
- The fallback reason comes from the GET (the session's own decision through `Ownership.Decision`), because the event carries none. The card re-reads the GET on every event, so it has one source (the Persona card's pattern).
- `onlineDemo` joins the GET, mirroring Persona's server-driven `customOffered`, so a test can rewrite one member instead of `/state`.
- The newer of `lastBeatAt` and `lastSkipAt` decides between the check-in line and the skip line. A pending beat shows "Last check-in {time}" alone.
- The Today line is hidden at 0 check-ins, because `formatCost(0)` would read "<$0.0001".
- All day: the On line leaves out ", {from} to {to}". `from`/`to` are shown as stored, in the instance zone.
- Unavailable precedence is cap, then nokey, then cooldown (AD-18's skip order). The empty checklist leaves Run enabled, and its 409 message shows after the press.
- DW-781: Run with `sample` true PUTs the shown values (the sample, the heartbeat still off) and shows the server's saved line, then POSTs. Nothing is saved at page load, so no audit entry is written without a press. No new text.
- Run saves the GET's values, never unsaved edits in an open Edit.
- The section sits before Persona, so "Persona last" holds in every existing test.

**Extend, don't copy (Rule 2):**
- `HeartbeatCard` and its view mirror `PersonaCard` and `persona-card-view.ts`: the read-on-key effect, the disclosure and Esc, `ServerButton`, `failureOf`, `keepFocus`.
- `counterText` is imported from the persona view, not copied.
- `heartbeat-types.ts` mirrors `persona-types.ts`.
- The browser spec mirrors `persona-card.spec.ts` and its support helpers.
- `HeartbeatToday` mirrors `RunCost`'s statement.
- A shared card base was rejected: the two cards share patterns, not markup or state.

**Integration ACs:**
- HC4 (browser, real stack): the card consumes 39.2's PUT, GET and run and 39.7's event. It saves, reads back after a reload, runs (202, cooldown), then shows the tick-recorded outcome and Today from the event with no reload.
- `HeartbeatApi.TestRunSendsThenCoolsDown`: the real production's beat is counted by `today`.

**Consumes:**
- 39.2: `GET`/`PUT /v1/heartbeat` and `POST /v1/heartbeat/run`, the ruled 409 texts and `SettingsOps.Heartbeat`.
- 39.7: the `heartbeat` event and `HeartbeatPayload`.
- 31.1: the live client and `/state`, with its `status` conditions.
- 40.4: the Persona card's pattern.

**Consumed-by:** none in this epic. 39.5 is the epic's last story before the close; the release pass does a run-now on the demo host.

**Ledger inbox:**
- DW-634 is addressed by the matrix row "Unavailable" and AC5: it reuses 39.2's ruled 409 texts.
- DW-781 is addressed by the matrix row "Online demo" and AC6 (save before Run, on press).

**Split:** not recommended. The server part is one read and three members (≈40 lines plus tests), and the card cannot meet its AC without them.

**CI placement:** `web/e2e/heartbeat-card.spec.ts` is in Playwright project `chromium`, which is unit `live:sign-in`, group `browser`. No job is renamed and no group is added.
- Added time (inference until measured): about 9 cases at about 5 to 10 s each, plus HC4's tick wait of up to 90 s, which is about 2.5 min locally and about 3 to 4 min on CI.
- The `browser` group is near its budget. If CI measures it over, the cheaper move is to rename the file to `web/e2e/rail/heartbeat-card.spec.ts`, which joins `sign-in-2` in `shards-4`, the group with the most room. That rename changes the AC's path, so it is the lead's call.

**Footprint:**
- In Epic 39's paths: `web/src/app/{rail,api}/**`, `web/e2e/heartbeat-card.spec.ts`, `Core/SettingsOps.cls`, `Web/Api.cls`, `Test/{Core,Web}/**`.
- `footprint_extensions` (in no open epic's diff, checked 2026-11-06): `web/src/app/live/live-store.ts`, `web/src/app/rail/status-rail.ts`, `Data/Ownership.cls`, `web/scripts/*.test.mjs` (the new file and the counts), `web/e2e/{rail/rail.spec.ts,frame/frame.spec.ts,floor/layout.spec.ts}` (counts), and `web/e2e/demo-path/01-page.spec.ts` (one count, pending the amendment).

### Public text

Every string the card shows, verbatim. "UX" means EXPERIENCE.md › Later Steps › Personality › The Heartbeat checklist card. `{time}` is `pageWhen`, `{cost}` is `formatCost`, and " · " is `CHAT_TEXTS.separator`.

| Where | Text | Source |
| --- | --- | --- |
| Section heading (h3) | Heartbeat checklist | UX Title |
| State, off | Off. Turn it on to have OcuTalon look at your list every 30 minutes. | UX Off |
| State, on | Every {interval}, {from} to {to} · Next check-in {time} | UX On |
| State, on, all day | Every {interval} · Next check-in {time} | UX On, without the hours part (no new words) |
| Interval names | 30 minutes / 1 hour / 2 hours / 4 hours / 8 hours / 24 hours | UX On ("30 minutes, 1 hour, 2, 4, 8 or 24 hours"); "2 hours", "4 hours", "8 hours" are spelled out: list for the delegate |
| Last check-in | Last check-in {time} · Stayed quiet · {cost} · Trace | UX Last check-in (ignore) |
| Outcomes | Told you now / Saved for the digest / Offered an action / Couldn't decide: {plain reason} | UX Last check-in; {plain reason} is the page catalog's existing `fallbackReason.*` |
| Skip prefix | Skipped at {time}: | UX Skips |
| Skip reasons | your checklist is empty. / outside your active hours. / nothing has changed since the last quiet check-in. / the day's cost cap is reached. / no model key is set. / waiting after a failed check-in, until {time}. | UX Skips |
| Today | Today: {n} check-ins, {cost} | UX Today |
| Today, one | Today: 1 check-in, {cost} | **new** (the singular of UX Today) |
| Checklist help | Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed. | UX Checklist help |
| Counter | {n} of 1,000 characters | UX (reused `counterText`) |
| Button | Run the heartbeat now | UX Button |
| Cooldown | You can run it again at {time}. | UX Button › Cooldown |
| Unavailable, cap (DW-634) | Today's cost limit has been reached. | 39.2's ruled 409 `cap` message (Contest Planner) |
| Unavailable, no key (DW-634) | No model key is set. | 39.2's ruled 409 `nokey` message |
| Run 409, shown as received | Your checklist is empty. / The last beat failed, so the next one waits until {time}. / (cap and nokey above) | 39.2's ruled 409 messages (server's text) |
| Saved (server's) | Saved. Applies within a minute. Recorded in the audit log. | UX Saved |
| Refusals (server's) | Use up to 1,000 characters, without {{ or @{. / Couldn't save. Nothing was changed. | existing (39.2) |
| Busy | Couldn't reach OcuTalon. Try again. Nothing was changed. | existing (`BUSY_NOTICE`) |
| Online-demo note | On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap. | UX Online-demo note |
| Sample (server's) | Tell me if an Orders incident is still open or waiting for my approval. / Remind me of anything due in the next hour. / Ignore everything else. | UX Sample checklist |
| Disclosure button | Edit | UX Later-step components ("an Edit disclosure") |
| Save button | Save | existing |
| On/off checkbox label | On | existing (U-269 T6, under `ux`) |
| Interval label | Interval | **new** (UX names "the interval") |
| Active hours legend | Active hours | **new** (UX names "active hours") |
| Hours labels | From / To | **new** |
| All-day checkbox | All day | **new** |
| Checklist label | Checklist | **new** (UX names "the checklist") |
| Trace link | Trace (and TraceLink's existing accessible name) | existing (`TRACE_TEXTS`) |

No aria-label of new text: controls are named by their visible labels, the Run button is described by its line, and the card by its section heading.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`.
- Each command is a foreground call with `timeout: 600000`, one per call, never two at once.
- Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`, id FE850E91) is used only to load and compile.
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`, `npm --prefix web run lint`, `npm --prefix web run build`: one call each. Expected: exit 0.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s5implw ci/warm.sh up`, once. Then `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s5implw ci/iris.sh class OcuTalon.Test.Core.SettingsHeartbeat`. Expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s5impl ci/iris.sh class OcuTalon.Test.Web.HeartbeatApi`, fresh, with production. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e39s5impl ci/iris.sh build`. Then, each on a fresh stack and one per call:
  - `ci/iris.sh live sign-in --part 1/3`, `--part 2/3` and `--part 3/3` (chromium: `heartbeat-card.spec.ts`, `frame.spec.ts`, `persona-card.spec.ts`);
  - `ci/iris.sh live sign-in-2 --part 1/2` and `--part 2/2` (`rail/rail.spec.ts`);
  - `ci/iris.sh live floor`;
  - `ci/iris.sh live demo-path`.

  Expected: passed. Record each heartbeat-card SPEC line's seconds.
- (once) `<lane> OCUTALON_RUN_TAG=e39s5impl ci/iris.sh shard lane-b@Web` and `shard lane-b@Core --part 1/2`, then `--part 2/2`, fresh. Expected: passed.
- (once) `git diff --exit-code HEAD -- src/ocutalon/cls/OcuTalon/Checks src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls src/ocutalon/cls/OcuTalon/Live web/src/app/live/payloads.ts src/ocutalon/cls/OcuTalon/Test/Checks docker/tests/test-triage-heartbeat.sh`. Expected: exit 0. Also `git diff --stat HEAD -- web/e2e/demo-path` shows only `01-page.spec.ts`, 1 to 2 lines.
- (once) `<lane> OCUTALON_RUN_TAG=e39s5implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s5impl ci/iris.sh teardown`, also after a failure.

Pinning mutations to apply, observe red, revert byte-identical and record (Rule 19), one per AC:
- AC1: drop the heartbeat push in `railView` → `rail-view.test.mjs`, HC1.
- AC2: `HeartbeatToday` without the Channel condition → `SettingsHeartbeat.TestHeartbeatToday`.
- AC3: `applyEvent` without the `heartbeat` case → `live-store.test.mjs`, HC4.
- AC4: `failureOf` maps `bad_checklist` to `save` → `heartbeat-card-view.test.mjs`, HC3.
- AC5: `unavailable` ignores `dailyCap` → the view test, HC6.
- AC6: Run skips the PUT when `sample` → HC7.
- AC7: HC4 is the Integration pin, covered by AC3's mutation.

**Shared surfaces:**
- the rail's sections (`railView` ids 6 → 7, `RAIL_TEXTS`, `SectionId`) and every test that counts or orders rail headings: `rail-view.test.mjs`, `rail/rail.spec.ts` R1 and R10-area counts, `frame/frame.spec.ts` F1, `floor/layout.spec.ts`, and `demo-path/01-page.spec.ts` (amendment);
- the `LiveStore` shape (`live-store.test.mjs`);
- the GET body (`SettingsHeartbeat.TestHeartbeatRead`'s exact JSON, `HeartbeatApi` GET tests);
- the UX strings inventory (`ux-strings.test.mjs`);
- the floor key and Esc hosts (`floor-sources.test.mjs`) and focus moves (`announce-focus-sources.test.mjs`);
- the README account's heartbeat keys, `HeartbeatBeat` row and the decision and Usage rows of its beats (Recent decisions is asserted by the rail and demo-path specs, so every HC case removes them);
- `BROWSER_UNITS` and CI groups: unchanged (the spec joins project chromium, which is `live:sign-in`, group `browser`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan-stage halt, resolved by the lead (2026-11-06):** the halt read: intent gap -- Story 39.5's AC "they don't change the demo-path specs (REL-2)" contradicts its own rail-card AC together with EXPERIENCE.md's rule "an h3 per rail section and card headline". `web/e2e/demo-path/01-page.spec.ts:103` asserts exactly six level-3 headings in the rail (`toHaveCount(6)`, "Telegram first and Persona last"), so any rail section with its h3 turns it red unless that one count changes. Story 40.4 changed the same line from five to six for Persona; its AC had no such clause. The other reading, a card title that is not a heading, breaks the UX heading rule and the rail's pattern. Recommended amendment (Rule 5, apply-and-report tier, intent unchanged: the demo path keeps running and passing): in epics.md Story 39.5, read "and they don't change the demo-path specs (REL-2), except the rail's section count in `web/e2e/demo-path/01-page.spec.ts` (six to seven headings, Heartbeat checklist before Persona, so Persona stays last)". With that amendment applied the spec is otherwise complete, so the lead can set `status: ready-for-dev` without a re-plan. Before implement: the public texts marked **new** under Design Notes › Public text (Today singular, Interval, Active hours, From, To, All day, Checklist, and the spelled-out "2 hours", "4 hours", "8 hours") go to the owner's delegate; their ruling id becomes their `ruled` key in `ux-strings.test.mjs`.

**Planning notes.** I reused the epic context `epic-39-context.md`. Since it was compiled, `epics.md` gained only the DW-781 bullet and the spine only the Enumerations `heartbeat` name, and both are read here. Continuity comes from 39.2 (done, 312498d6) and 39.7. The footprint was checked against `origin/OCT-epic11` and `origin/OCT-epic17` on 2026-11-06: no overlap. No IRIS call was made and no file other than this spec was written.
