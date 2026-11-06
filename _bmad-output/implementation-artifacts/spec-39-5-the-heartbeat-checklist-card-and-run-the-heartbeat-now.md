---
title: 'Story 39.5: The Heartbeat checklist card, and Run the heartbeat now'
type: 'feature'
created: '2026-11-06'
status: 'done'
baseline_revision: '587b1646fab74f4ba6272d5f7f7bb078e8b91f7c'
baseline_commit: '587b1646fab74f4ba6272d5f7f7bb078e8b91f7c'
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
- Rulings applied by the lead (2026-11-06), each a task:
  - Pin every string of `### Public text` with a fixed-strings test (whole-string equality), the Today singular and plural included. Where `ux-strings.test.mjs` records a ruling for a string, its `ruled` key is `planner-2026-11-06-39.5` (the Contest Planner's ruling under the owner's delegation, relayed by the orchestrator).
  - U-295 (kept, at=2026-11-06T10:29:14Z#900): the ONLY demo-path spec edit is `web/e2e/demo-path/01-page.spec.ts`'s rail-heading count, 6 to 7, plus an assertion that the Heartbeat checklist heading comes before Persona and Persona is last; no other demo-path spec line changes; the full demo-path suite stays green on the story's head.
  - CI placement (orchestrator ruling): `heartbeat-card.spec.ts` stays in `live:sign-in` (browser group) only if browser's clean-run time plus the MEASURED unit time stays under 35 minutes; record the measured unit time in `## Verification`. Otherwise it moves to `web/e2e/rail/heartbeat-card.spec.ts` (sign-in-2, shards-4) and the lead amends the AC path with a marker.

### Review Findings

Code review 2026-11-06 (bmad-code-review, full mode, four layers on the full-opus tier; diff `e6036799` plus the working tree, `_bmad-output/**` left out). 42 raw findings: 1 high, 5 medium, 7 low kept (13 rows), 27 rejected.

- [ ] [Review][Decision] HIGH: on the online demo, Run's save-then-run (DW-781, AC6) answers 409 empty -- `HeartbeatCard.run` PUTs the sample and POSTs at once, but the POST runs in the Checks job (PoolSize 1), whose `Beat.RunNow` reads the checklist through `Beat.Values` and `Data.Setting.Get`'s 60 s per-process cache; the Checks tick runs every minute and calls `Values` for every session (on or off), so the cache holds the empty checklist and the press shows "Saved..." and "Your checklist is empty." and starts the 2-minute cooldown. HC4's own 61 s wait (`APPLY_MS`) exists for this cache; HC7 fulfils the POST with a fake 202, so no test reaches the real chain. The fix is in Lane A (`Checks/Beat.cls` RunNow reading the session's keys fresh) or a product change of the card's run flow; both are outside this Lane B story (U-177). Severity high, fix-risk low (Lane A, about 3 lines plus a Test/Checks case) or med (card-side wait), footprint in-epic (Lane A of Epic 39), spec-status clear. Occurrence appended to DW-781. Unresolved: the story stays in-progress. [web/src/app/rail/heartbeat-card/heartbeat-card.ts:505, src/ocutalon/cls/OcuTalon/Checks/Beat.cls:473]
- [x] [Review][Patch] MED: a real 5xx on Run showed the server's "Something went wrong inside OcuTalon. Try again." instead of the busy notice (matrix row Run: "5xx: busy notice"; that sentence is not in the Public text) -- `runFailed` now shows `BUSY_NOTICE` for any status 500 and up; HC10's 500 stub now carries a message, which must not show. Fix-risk low. [web/src/app/rail/heartbeat-card/heartbeat-card.ts:631]
- [x] [Review][Patch] MED (Rule 19): HC5's "enabled again when the cooldown ends" passed without the cooldown timer (the card's 60 s clock alone re-enabled it inside the 70 s timeout) -- the deadline is now the cooldown's end plus 5 s. Fix-risk low. [web/e2e/heartbeat-card.spec.ts:274]
- [x] [Review][Patch] MED (Rule 19, flake): HC5 had 60 s from its `before` step for sign-in, two `conditionsOff`, a reload and four held assertions -- `LastRunNowAt` is now 30 s back (a 90 s held window); the case timeout is 180 s. Fix-risk low. [web/e2e/heartbeat-card.spec.ts:296]
- [x] [Review][Patch] MED (Rule 19, flake): HC1 and HC8 computed "now plus or minus x" twice, before and after a reload, so a minute boundary between the two calls turned them red with correct code (HC1 also from 00:00 to 00:05 UTC) -- each time is computed once; HC1's skip is 5 s back. Fix-risk low. [web/e2e/heartbeat-card.spec.ts:170, :413]
- [x] [Review][Patch] MED (Rule 19, order): HC4 had to be the file's last case because the status monitor's noModelKey event of the restored keys (within 15 s) landed in the next case -- its afterAll now marks the instance stream before `restoreKeys` and waits up to 30 s for that event, so no later case or file gets it. Fix-risk med (measured green below). [web/e2e/heartbeat-card.spec.ts:640]
- [x] [Review][Patch] LOW: a stored `from` equal to `to` (accepted by `HeartbeatProblem`, all day for `Checks.Beat.InHours`) showed "Every 1 hour, 08:00 to 08:00" -- `stateLine` reads it as all day; a view test row pins it. [web/src/app/rail/heartbeat-card/heartbeat-card-view.ts:149]
- [x] [Review][Patch] LOW: `SettingsOps.Heartbeat`'s doc said only checklist and sample are set when the view cannot be built, and did not name today's read as an error source -- the doc now states the contract. [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:407]
- [x] [Review][Patch] LOW: HC2 changed All day and On by mouse after the reload -- both now by Space, and Save by Enter. [web/e2e/heartbeat-card.spec.ts:229]
- [x] [Review][Patch] LOW: HC4 did not prove "no reload" -- it now sets a page marker before Run and reads it after the outcome, as HC11 does. [web/e2e/heartbeat-card.spec.ts:719]
- [x] [Review][Defer] LOW: HC8, HC10 and HC11 skip within 40 minutes of midnight UTC [web/e2e/heartbeat-card.spec.ts:115] -- deferred: DW-800 wontfix-accepted (a fixed browser clock is the seam, more than 15 lines), reopen_if a regression merges on a run that skipped them.
- [x] [Review][Defer] LOW (Rule 2): `describer` is a 6-line copy of `persona-card.spec.ts:64` [web/e2e/heartbeat-card.spec.ts:445] -- deferred: DW-801 wontfix-accepted (sharing it edits Epic 40's spec), reopen_if a third copy appears.
- [x] [Review][Defer] LOW: the Off line always says "every 30 minutes" whatever interval is saved [web/src/app/rail/heartbeat-card/heartbeat-card-view.ts:26] -- deferred: DW-802 by-design (the ruled Public text, verbatim).

Rejected:
- false: the GET is 500 when today's read fails (matrix row "GET today"); the day bounds come from `Data.Time`, not `Bridge.Time` (AD-18, Code Map); the online-demo note shows whenever `onlineDemo` (Tasks); a newer skip with an unknown reason hides an older check-in (Checks writes the six known reasons and BackoffUntil with backoff only); `demo-path/01-page.spec.ts`'s added order assertion (U-295 allows it); missing mutation lines (Rule 19 asks one per AC, and every AC has one); HC4's cost regex vs `<$0.0001` (the mock's cost is fixed and above it).
- low: `HeartbeatToday`'s guard follows `$ZDateH` (`ToLocal(NowUtc())` is never empty); the identical-payload re-read and the `checkIns >= 1`/all-time SUM checks (triaged in implement, unchanged); null `CostUSD` rows add nothing to Today (a missing price row, as everywhere else in the product); `^OcuTalonBP.UsageCapped` killed on a throwaway stack; the unused `HeartbeatRunRefused` type (the spec lists it); a 409 cooldown whose availableAt is already past by the browser clock; Today across local midnight with no event; the open disclosure after a failed then good read; `Decision` read without its status; OwnerRef collation (generated refs); the IRIS tests' midnight races; HC5 and HC4 at 23:58-00:00 UTC; `reset` clearing `onlineDemo` on the test stack; HC5 not pressing Run twice (HC4 and HC5 together cover the matrix row); HC4's 120 s tick budget against the task's 90 s; the HeartbeatApi cost check's missing `> 0` control (the mock reports usage); the unpinned `todayStatus` line (wontfix-accepted in implement).
- [x] [Review] HIGH (code review 1): on the online demo, save-then-run was refused as `empty` because Checks read the 60-second per-process settings cache -- now fixed in Lane A by Story 39.8 (`Checks.Beat.Values(ref, 1)` in `RunNow`, committed f8045439) -- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls` -- add a case on the real production: a session the tick has already read (wait for one real tick after creating it, or as `Test.Checks.Heartbeat.TestSaveThenRunNow` arranges it), then `PUT /v1/heartbeat` with a non-empty checklist (heartbeat off) and at once `POST /v1/heartbeat/run`: it answers 202, not 409 `empty`; demonstrate its mutation (revert 39.8's `Values(sessionRef, 1)` to `Values(sessionRef)` in `RunNow` on your copy only, observe red, restore byte-identical).
- [x] [Review] DW-812 (LOW, two-way door): `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` `HeartbeatValues` repeats the five-key cache drop that `Checks.Beat.Values(ref, 1)` now does -- replace the copy with a call to it, keeping `HeartbeatValues`' contract; the existing `SettingsHeartbeat` and `HeartbeatApi` GET-after-PUT tests must stay green.

### Review Findings (round 2)

Code review 2026-11-06, round 2 (bmad-code-review, full mode, four layers on the full-opus tier; rework diff `587b1646` plus the working tree). 11 raw findings, 10 after grouping: 0 high, 0 medium, 2 low kept and patched, 8 rejected. Checklist: (1) the round-1 HIGH save-then-run (the `[Review][Decision]` HIGH above and the `[Review]` HIGH, DW-803) is closed: `HeartbeatApi.TestSaveThenRunAfterATick` answers 202 sent on the real production and goes red when 39.8's `Values(sessionRef, 1)` in `RunNow` is reverted; (2) DW-812 is closed: `Values(ref, 1)` drops exactly the five keys the removed loop dropped and returns the same object.

- [x] [Review][Patch] LOW (Rule 19): `TestSaveThenRunAfterATick` started its 50-second window after the session was made and saved, so a real tick that cached the session's keys during a slow first PUT (more than 10 s) could let the entry expire before the run and the mutant pass -- `started` is now taken before `..Session()`, so no cache entry of the new session can be older than the window. Fix-risk low. [src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls:455]
- [x] [Review][Patch] LOW (Rule 14): the class doc's "(the run now reads the stored values ...)" read as change narration -- now "a run now reads the stored values". Fix-risk low. [src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls:17]

Rejected:
- false: `SendTick(..., 0)` returns OK when the 60 s TICKWAIT times out, so "a Tick is sent and answered" cannot fail -- a timeout takes at least 60 s, so the 50-second assertion goes red; no false green; the spec showing `done` while sprint status is `review` (the implement stage sets the spec, the lead sets the sprint key, by the workflow).
- low: a 202 with no heartbeat row or LastItemId quits without the decision check (the 202 is the pinned outcome; a sent run always sets LastItemId, as `TestRunSendsThenCoolsDown` has it); Intake writing rows after a 90 s WAITDECISION timeout (the assertion fails loudly; the stack is a throwaway); the rework Triage Log row on `baseline_commit` (a dated record, true at `dbd37f1d`; the lead moved it for this scoped review); the rework `dev_complete` cycle-log line's missing `files=`/`loc_*` fields (the lead's log, not this stage's); the rework's `[x]` items carry no closing note and the round-1 Decision HIGH stays unticked (this round's checklist line records both closures; a fix would edit earlier review records).

## Spec Change Log

- 2026-11-06 (lead): rework iteration 1 of 3 opened after code review 1 (trigger: HIGH; items: the save-then-run 202 case, DW-812). Story 39.8 carries the Lane A fix.

- 2026-11-06 (lead, after code review 1): the review's HIGH (online-demo save-then-run reads Checks' 60-second per-process settings cache, so AC6 fails on the real stack) needs a Lane A change; split to Story 39.8 (DW-803, with DW-780). This story stays in-progress for ONE rework iteration after 39.8 is committed: add a `HeartbeatApi` case that saves and runs on a session the tick has already read, expecting 202, then a scoped re-review.

- 2026-11-06 (lead, before implement): the Contest Planner's PUBLIC TEXT ruling for 39.5 applied to `### Public text` (Today singular, the labels and interval names approved; DW-634's unavailable texts approved; the skip line's cap fragment becomes "today's cost limit has been reached.", choice (c), EXPERIENCE.md amended with a marker, reusing the catalog's `fallbackReason.dailyCap` wording; 39.2's overview line stays). U-295 kept with conditions; CI placement ruled. Tasks added at the end of Tasks & Acceptance.

- 2026-11-06 (lead, after the plan halt): epics.md Story 39.5's REL-2 clause amended as the plan recommended (unattended ruling, veto U-295): the Playwright specs change no demo-path spec except the rail's section count in `web/e2e/demo-path/01-page.spec.ts`, six to seven headings, Heartbeat checklist before Persona. Status set to ready-for-dev without a re-plan; the Public text table goes to the Contest Planner before implement.

## Review Triage Log

### 2026-11-06 — Review pass
- verdicts: 30 findings — high 0, medium 8, low 12, false 10, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: one failed read removes the card, Edit and the Saved line — the matrix row "Live update" says a failed read leaves the section heading alone and reads again on the next event; PC11 and PC17 pin the same behavior for Persona.
  - `[low]` `[reject]` Blind: Today can stay stale because the read key is the event payload's JSON — each real beat's payload carries new beat times and cost, so the key moves on every tick; an identical-payload event is not reachable on the real stack, and a timer would add a path the spec excludes.
  - `[low]` `[patch]` Blind: the `nearMidnight` doc says 20 minutes, the code and skip text say 40 — the comment now says 40.
  - `[medium]` `[patch]` Blind: TestHeartbeatToday has no day-boundary rows and builds its day with the implementation's own helpers — it now also inserts rows at `Bridge.Time.DayStartUtc` (counted) and `DayEndUtc` (not counted) and one with no ItemId, and asserts the day start equals `Data.Time.FromLocal`; mutation `<` to `<=` goes red. The rollover race of a test running within a second of local midnight is low and not guarded.
  - `[low]` `[patch]` Blind: the counter borrows Persona's "1,000" with nothing tying it to `CHECKLISTMAX` — `heartbeat-card-view.test.mjs` now pins `counterText('')` to Beat.cls `CHECKLISTMAX`.
  - `[low]` `[reject]` Blind: HeartbeatApi compares the GET with a later SUM — the Decision row the test waits for is recorded after the beat's Usage rows and the marker is an ignore (no Act turn), so no later Usage row arrives; the spec fixes `at least 1`.
  - `[medium]` `[patch]` Blind: no component-level coverage of the sample save-then-run chain, the cooldown logic and the refused PUT — covered at the browser surface by HC10, HC10b and HC7 (a mutation of the PUT step turns HC7 and HC10b red).
  - `[low]` `[patch]` Blind: the `Rows` property comment names the wrong rows — it now says it holds the fixture decisions' Refs.
  - `[false]` `[reject]` Edge: a failed Usage read makes the GET 500 — the matrix row "GET today" says a failed read is 500 server_error, as for any GET read.
  - `[low]` `[reject]` Edge: HeartbeatToday has no Try/Catch at the date range edge (9999-12-31) — not reachable by an instance clock in this product's life.
  - `[false]` `[reject]` Edge: the Today line hides a cost at 0 check-ins — the matrix row "Today line" says none at 0, and the Design Notes give the reason (`formatCost(0)`).
  - `[false]` `[reject]` Edge: a 409 backoff does not hold Run — the matrix row "Run" says 409 cap, nokey, empty and backoff show the server's message under the button; only `cooldown` holds the button.
  - `[false]` `[reject]` Edge: a stored interval or hour outside the selects' lists — `SettingsOps.HeartbeatProblem` refuses any interval outside `Checks.Beat` INTERVALS and any hour that is not a quarter hour, so no stored value is off the lists.
  - `[false]` `[reject]` Edge: an on state with an unlisted interval gives no state line — same evidence; the server accepts the six intervals only.
  - `[false]` `[reject]` Edge: only one of from and to set — the server accepts both empty or both set only.
  - `[low]` `[reject]` Edge: the HeartbeatApi SUM race — same as the Blind row for it.
  - `[low]` `[reject]` Edge: an identical-payload event gives no re-read — same as the Blind row for Today; also see the intent decision recorded under Design Notes (the key is the payload's JSON).
  - `[false]` `[reject]` Edge: the Heartbeat doc says settings are returned all the same, while the GET answers 500 on an error status — the doc sentence is the existing one about the returned object; the 500 is the specified behavior (Api.ReadHeartbeat, unchanged).
  - `[medium]` `[patch]` Gap: no test drives Run's refusal and failure paths or the failed save of the sample — added HC10 (409 cooldown, 409 empty, 500) and HC10b (a refused PUT of the sample sends no POST); HC10b went red under the AC6 mutation.
  - `[medium]` `[patch]` Gap: Save's bad_hours, bad_interval, bad_on and its 500 are unpinned in the browser — added HC3b.
  - `[low]` `[patch]` Gap: Esc inside the drawer band is untested for the new card — added HC9b, the Heartbeat form of PC7b.
  - `[medium]` `[patch]` Gap: HeartbeatToday's day bounds, the empty-ItemId rule and the error propagation are unpinned — the bounds and the empty-ItemId rows are added to TestHeartbeatToday (same patch as the Blind boundary row); the error-propagation line (`Set sc = todayStatus`) stays untested because a failing seam needs production code, which `wontfix-accepted`, reopen_if a second Usage-backed member joins the GET.
  - `[medium]` `[patch]` Gap: HC8's check-in cases can lose to a skip row that the real tick writes for the default-on account — each case now answers `lastSkipAt` null and an empty `lastSkipReason` beneath its own members.
  - `[medium]` `[patch]` Gap: HC5 stamps the cooldown start before the setup runs — it is now stamped in the `before` step, 60 s back, so the held window is not eaten by the sign-in. HC5 also failed in this pass from the noModelKey event that the status monitor publishes after HC4's key restore; HC4 is now the last case of the file.
  - `[low]` `[patch]` Gap: the `Rows` comment — same patch as the Blind row for it.
  - `[low]` `[reject]` Gap: `today.checkIns >= 1` and the all-time SUM — the spec asks for at least 1, and a fresh session holds one day of rows.
  - `[false]` `[reject]` Intent: the pre-save keys off `sample`, not `onlineDemo` — the matrix and Design Notes say `sample` true.
  - `[false]` `[reject]` Intent: a cost shows only when an outcome is known — the matrix row "Last check-in" says no outcome gives the time alone.
  - `[medium]` `[patch]` Intent: a heartbeat Usage row with an empty ItemId is unpinned — same patch as the Gap boundary row.
  - `[low]` `[reject]` Intent: nothing ties the page's `dailyCap` and `noModelKey` keys to the server's status keys — the view test reads them against the `Web.Api` texts and HC6 drives both conditions through the store; the keys are the banners' own.

### 2026-11-06 — Review pass (rework 1, follow-up)
- verdicts: 17 findings — high 0, medium 0, low 9, false 8, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the spec's older verification lines (CR's "doc-only change of `SettingsOps.cls`", the implement results) are stale — they are dated records of earlier passes; this pass's verification is its own block, and a fix would edit the spec.
  - `[false]` `[reject]` Blind: `baseline_revision` moved but `baseline_commit` and `review_loop_iteration` did not — `baseline_commit` is the story base by design and `review_loop_iteration` counts bad_spec loopbacks, of which this pass has none.
  - `[low]` `[reject]` Blind: the under-50-second assertion can fail on a slow runner, and the same-job premise is not asserted — a slow run fails loudly instead of passing wrongly, and Checks has `PoolSize="1"` (`Production.cls:56`); a guard would add a branch for a theoretical case.
  - `[low]` `[reject]` Blind: `DecisionOfItem`'s status unchecked, no clean-up on the early Quits — `TestRunSendsThenCoolsDown` has the same shape; with no `LastItemId` there is no Item to clean.
  - `[low]` `[reject]` Blind: `HeartbeatValues` is a one-line wrapper whose doc restates `Beat.Values` — the task asked to keep `HeartbeatValues`' contract and replace the copy; its callers stay unchanged.
  - `[low]` `[reject]` Edge: the control PUT's status is not a guard — the assertion fails and names the cause; a `Quit` adds a branch for a case the next assertion already reports.
  - `[low]` `[reject]` Edge: `SendTick` is not limited to the test's session — Checks runs every due session in every Checks test of the product; the test stack is a throwaway.
  - `[false]` `[reject]` Edge: the 50-second assertion — same as the Blind row for it.
  - `[low]` `[reject]` Edge: Item clean-up after a non-202 — a refused run starts no beat, so there is no Item.
  - `[low]` `[patch]` Edge: the test's doc and the spec say the Tick is sent "as HeartbeatIn sends it", but `HeartbeatIn` sends asynchronously and `SendTick(..., 0)` synchronously — both now say "synchronously through the HeartbeatIn service (`Test.Watch.Case.SendTick`)"; `HeartbeatApi` passed fresh again.
  - `[false]` `[reject]` Gap: the cache precondition rests on the 50-second assertion and the observed mutation — the mutation went red on exactly this test, and `RunDue` reads the five keys for every session, so the Tick leaves the empty checklist cached.
  - `[false]` `[reject]` Gap: the test does not set `onlineDemo` — the cache defect is independent of the mode (the PUT sets `on` explicitly); the card-level online-demo chain is HC7 and HC10b.
  - `[low]` `[patch]` Gap: DW-812 has no recorded mutation — the mutation was applied (`Values(sessionRef)` in `HeartbeatValues`), `SettingsHeartbeat.TestHeartbeatRead` went red, restored byte-identical; the line is in `## Verification`.
  - `[false]` `[reject]` Intent: no surface renders the Off line, the note or the sample, nor the failed-PUT branch — those rows are pinned by HC7 and HC10b in the earlier passes; this pass's open items are the route-level case and DW-812 only.
  - `[false]` `[reject]` Intent: the Integration row's event, store and Today are not observed by the new test — HC4 and HC11 pin them in the browser; the new test is the real-production consumer of the 39.8 fix.
  - `[low]` `[reject]` Intent: the test uses `mock:decide-ignore` while the Integration row names `heartbeat-ignore` — the markers differ by purpose (a decision on the server path versus the card's HC4 ignore beat); the test only needs a beat the mock answers.
  - `[false]` `[reject]` Intent: the tick is injected by a helper, not by the production's timer — the helper sends a Tick to the same Checks job the timer does, which is what the cache case needs.

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

**Decided in implement:**
- `ux-strings.test.mjs`: the ruled key `planner-2026-11-06-39.5` holds the strings that EXPERIENCE.md does not hold: `Today: 1 check-in, {cost}`, `Interval`, `Active hours`, `All day`, `2 hours`, and the two unavailable reasons `Today's cost limit has been reached.` and `No model key is set.` (capitalized, so not the UX's lower-case skip fragments). The labels `To` and `Checklist` and the names `4 hours` and `8 hours` are under `ux`: EXPERIENCE.md holds those words incidentally ("To stop, ask", "Checklist help", "24 hours"), and the test's rule that a slot-free ruled string may not be held by the UX forces them there.
- The view's functions take the page's time as a function (`stateLine(state, when)`) or a format object (`lastLine(state, format)`: `when`, `cost`, `reason`), so Node runs them. The separator is the view's own constant, pinned equal to `CHAT_TEXTS.separator`.
- A fallback beat reads "Couldn't decide: {plain reason}" whatever its `lastOutcome` (a fallback records outcome tellnow); a check-in with an outcome the card does not know shows the time alone, without cost or Trace; a backoff skip with no readable `backoffUntil` shows no skip line.
- After a 202 the card holds Run for 120 s from the press until the state shows a new `lastRunNowAt`, because the tick's row write and its event can follow the answer; a 409 cooldown holds it to `availableAt`; other 409 messages show under the button and do not hold it.
- The browser spec holds 13 tests: HC1 to HC10 and HC3b, HC9b and HC10b. HC3b, HC10 and HC10b stub the PUT or the run with a refusal or a failure (the matrix rows for the other refusals, the 409s, the 5xx and the failed save of the sample); HC9b is Persona's PC7b for the Heartbeat card. HC4 is the last case of the file: it points the runners' keys at the mock and restores them, which changes the noModelKey reading that the status monitor publishes within 15 s, and that event would otherwise land in a later case that holds Run to the cooldown.
- HC4 waits 61 s after Save before it presses Run: the settings are cached for 60 s in every process (AD-19), the Checks job's tick has read the account's empty checklist, and an early run would answer 409 empty and start the 2-minute cooldown. HC2 sets the three selects with `selectOption` after reaching them by Tab, because the arrow keys open the native menu on some platforms. HC6 rewrites `/state`; HC8 reloads the page for each rewritten GET.

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
| Interval names | 30 minutes / 1 hour / 2 hours / 4 hours / 8 hours / 24 hours | Contest Planner ruling (owner's delegation, 2026-11-06) |
| Last check-in | Last check-in {time} · Stayed quiet · {cost} · Trace | UX Last check-in (ignore) |
| Outcomes | Told you now / Saved for the digest / Offered an action / Couldn't decide: {plain reason} | UX Last check-in; {plain reason} is the page catalog's existing `fallbackReason.*` |
| Skip prefix | Skipped at {time}: | UX Skips |
| Skip reasons | your checklist is empty. / outside your active hours. / nothing has changed since the last quiet check-in. / today's cost limit has been reached. (reuse the catalog's `fallbackReason.dailyCap`, "today's cost limit has been reached", plus the period) / no model key is set. / waiting after a failed check-in, until {time}. | UX Skips; the cap fragment amended by the Contest Planner ruling (owner's delegation, 2026-11-06), choice (c), EXPERIENCE.md marked |
| Today | Today: {n} check-ins, {cost} | UX Today |
| Today, one | Today: 1 check-in, {cost} | Contest Planner ruling (owner's delegation, 2026-11-06): "Today: 1 check-in, {cost}"; 0 and 2 or more use the plural |
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
| Interval label | Interval | Contest Planner ruling (owner's delegation, 2026-11-06) |
| Active hours legend | Active hours | Contest Planner ruling (owner's delegation, 2026-11-06) (the fieldset legend) |
| Hours labels | From / To | Contest Planner ruling (owner's delegation, 2026-11-06) |
| All-day checkbox | All day | Contest Planner ruling (owner's delegation, 2026-11-06) (a checkbox) |
| Checklist label | Checklist | Contest Planner ruling (owner's delegation, 2026-11-06) |
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
  - mutation: the `sections.push({ id: 'heartbeat', ... })` line commented out in `rail-view.ts` → `rail-view.test.mjs` red ("come in order without Telegram: Approval requests, Background checks, Reminders, Recent decisions, Heartbeat checklist, Persona", and 2 more); reverted, `cmp` identical.
- AC2: `HeartbeatToday` without the Channel condition → `SettingsHeartbeat.TestHeartbeatToday`.
  - mutation: `Channel = 'heartbeat'` removed from the `heartbeatUsage` statement in `Data/Ownership.cls` → `Test.Core.SettingsHeartbeat` red (`TestHeartbeatToday`: "two Items today" and the cost sum); reverted, `cmp` identical, green again.
  - mutation: `RecordedAt < ?` changed to `<=` in the same statement → `TestHeartbeatToday` red ("the first instant of the day counts, the first instant of the next day does not, ..." and "the row with no Item adds its cost"); reverted, `cmp` identical, green again.
- AC3: `applyEvent` without the `heartbeat` case → `live-store.test.mjs`, HC4.
  - mutation: the `case 'heartbeat'` two lines deleted in `live-store.ts` → `live-store.test.mjs` red ("keeps the latest heartbeat event (Story 39.5): ..." and "COLLECTIONS"); reverted, `cmp` identical. HC4 (the card's update with no reload) was not run under this mutation.
- AC4: `failureOf` maps `bad_checklist` to `save` → `heartbeat-card-view.test.mjs`, HC3.
  - mutation: `bad_checklist: 'save'` in `FIELD_OF_CODE` → `heartbeat-card-view.test.mjs` red ("shows bad_checklist, bad_hours, bad_interval and bad_on beside their field, with the server's message"); reverted, `cmp` identical.
- AC5: `unavailable` ignores `dailyCap` → the view test, HC6.
  - mutation: the `dailyCap` test replaced by `if (false)` in `unavailable` → `heartbeat-card-view.test.mjs` red ("is the cap first, then the missing key, then nothing"); reverted, `cmp` identical.
- AC6: Run skips the PUT when `sample` → HC7.
  - mutation: `state.sample !== true` changed to `state.sample !== undefined` in `run` (heartbeat-card.ts), bundle rebuilt → `live sign-in --part 3/3` red: HC7 and HC10b (the POST goes out with no PUT first); reverted, `cmp` identical, bundle rebuilt.
- AC7: HC4 is the Integration pin, covered by AC3's mutation.

**QA stage additions (QA):**
- `web/e2e/heartbeat-card.spec.ts` (QA) gains two cases, both in `live:sign-in` with the rest of the file and both before HC4, which stays last (15 tests now):
  - HC11 (QA), matrix row "Live update": a `heartbeat` event published on the session's stream (as Checks publishes it) makes the card read again and show the new check-in line and Today with no reload; a failed read leaves the section heading alone, and the next event reads again. The GET is rewritten so no real tick can change it. The implement stage's triage rejected this gap by citing Persona's PC11 and PC17, which exercise the Persona card, not this one.
  - HC12 (QA), the spec's Always rule on `keepFocus`: a failed save whose re-read also fails takes the card away and focus on Save goes to the Heartbeat heading.
- mutation (AC3, run now): the `case 'heartbeat'` removed from `applyEvent` in `live-store.ts` (and, in the same build, the `keepFocus` call of the card's focus effect replaced by a no-op) → `live sign-in --part 3/3` red on HC4 (the implement stage's missing demonstration), HC11 (no re-read from the event) and HC12 (focus not moved to the heading); 76 passed, 3 failed. Both files restored from a backup, `cmp` identical, `git diff --stat` identical to before, bundle rebuilt.
- QA run, unmutated tree, fresh lane-D stack (tag e39s5qa): `live sign-in --part 3/3` 79 passed (4.9 min); `SPEC heartbeat-card.spec.ts 15 tests 166s`. CI placement: 30.5 min + 166 s is under the 35-minute ceiling.

**Code review additions (CR, lane D, tag e39s5cr, fresh throwaway stacks, all torn down):**
- `npm --prefix web test` 1494 passed; `lint` and `build` exit 0 (the existing budget warnings only).
- `live sign-in --part 3/3` on the patched tree: 79 passed (5.7 min); `SPEC heartbeat-card.spec.ts 15 tests 214s`. CI placement: 30.5 min + 214 s = 34.1 min, under the 35-minute ceiling, so the spec stays in `live:sign-in`.
- `OcuTalon.Test.Core.SettingsHeartbeat` passed (fresh; the doc-only change of `SettingsOps.cls`).
- mutation (AC5, the cooldown's end): the cooldown-end `setTimeout` of `heartbeat-card.ts` made a no-op, and in the same build `runFailed`'s 5xx test made `status >= 5000` -> `live sign-in --part 3/3` red on HC5 ("enabled again when the cooldown ends", the deadline tied to the end) and HC10 ("and not the 500's own message"); 77 passed, 2 failed. Restored from a backup, `cmp` identical, `git status --short` and `git diff --stat` identical to before, bundle rebuilt.


**Rework additions (rework 1, lane D, tags e39s5rwh and e39s5rwhw, torn down):**
- `HeartbeatApi.TestSaveThenRunAfterATick` (new, real production): the person is saved off with an empty checklist, a Tick is sent to Checks through the HeartbeatIn service (`Test.Watch.Case.SendTick`, synchronous, so the Checks job has read the empty checklist), a checklist is saved by `PUT /v1/heartbeat` and `POST /v1/heartbeat/run` follows at once (asserted less than 50 seconds after the Tick started) and answers 202 sent; the beat's decision is waited for before the clean-up.
- mutation (HIGH save-then-run): `Set values = ..Values(sessionRef, 1)` changed to `..Values(sessionRef)` in `RunNow` of `Checks/Beat.cls` (my copy only) -> `OcuTalon.Test.Web.HeartbeatApi` red on `TestSaveThenRunAfterATick` ("the run right after the save is 202 sent, not 409 empty"), the other tests green; restored from a backup, `cmp` identical, `git status --short` and `git diff --stat` identical to before.
- DW-812: `SettingsOps.HeartbeatValues` is now `Quit ##class(OcuTalon.Checks.Beat).Values(sessionRef, 1)`. Unmutated tree: `OcuTalon.Test.Web.HeartbeatApi` passed fresh (8.4 s class time; its `TestGetAfterPut` is the GET-after-PUT pin) and `OcuTalon.Test.Core.SettingsHeartbeat` passed warm.
- mutation (DW-812): `Values(sessionRef, 1)` changed to `Values(sessionRef)` in `SettingsOps.HeartbeatValues` (my copy only) -> `OcuTalon.Test.Core.SettingsHeartbeat` red on `TestHeartbeatRead` ("the saved values, read from the rows and not from the cache" and "it holds the checklist and sample false"); restored from a backup, `cmp` identical, green again on the same warm stack, `git status --short` and `git diff --stat` identical to before.
- code review round 2 (lane D, tag e39s5cr2, torn down): with `started` moved before `..Session()`, `OcuTalon.Test.Web.HeartbeatApi` passed fresh (8.5 s class time); mutation (HIGH save-then-run, re-observed on the changed test): `Values(sessionRef, 1)` changed to `Values(sessionRef)` in `RunNow` of `Checks/Beat.cls` (my copy only) -> `HeartbeatApi` red on `TestSaveThenRunAfterATick` only ("the run right after the save is 202 sent, not 409 empty"; the 50-second assertion held); restored from a backup, `cmp` identical, `git status --short` and `git diff --stat` identical to before. `test-boundaries.sh` and `test-class-rules.sh` passed.

**Verification results (implement stage, lane D, fresh throwaway stacks against the CI mock):**
- `npm --prefix web test` 1494 passed; `lint` and `build` exit 0 (the existing bundle-budget warnings only).
- `OcuTalon.Test.Core.SettingsHeartbeat` passed warm; `OcuTalon.Test.Web.HeartbeatApi` passed fresh; `shard lane-b@Web` (24 classes) passed; `shard lane-b@Core` part 1/2 (21) and part 2/2 (20) passed; `bash ci/checks.sh` passed (all scripts).
- Browser units, each on a fresh stack, with `OCUTALON_LIVE_DEADLINE=900` on the call (Rule 21: a part near 8 minutes dies of the 540 s default deadline): `live sign-in` parts 1/3, 2/3 and 3/3 passed (81, 80 and 80 tests), `live sign-in-2` parts 1/2 and 2/2 passed (74 and 55), `live floor` (107), `live demo-path` and `live online-demo-path` (7 passed) passed.
- Measured `SPEC heartbeat-card.spec.ts 13 tests` on the lane: 183 s on the passing part 3/3 run (99 s, 155 s and 176 s on other runs, the spread being HC4's wait for the real tick). CI placement: 30.5 min + 183 s = 33.6 min, under the 35-minute ceiling, so the spec stays at `web/e2e/heartbeat-card.spec.ts` in `live:sign-in` (group `browser`).
- Lane A files: `git diff --exit-code HEAD` over the read-only paths exits 0; `web/e2e/demo-path` shows `01-page.spec.ts` only, 2 insertions and 1 deletion.

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

Status: done
Blocking condition: none

**Summary.** Story 39.5 adds the Heartbeat checklist card to the rail (before Persona), the live store's `heartbeat` field, three GET members (`today`, `lastFallbackReason`, `onlineDemo`) read from Lane B code, and the browser and node tests. The card reads the GET on creation and on every `heartbeat` event, saves with PUT, runs with POST (the sample is saved first on the online demo), holds Run for the cooldown, the cap and the missing key, and shows every string of the Public text as ruled.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `HeartbeatToday` and the `heartbeatUsage` statement.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`, `Web/Api.cls`: the three GET members; doc.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsHeartbeat.cls`, `Test/Web/HeartbeatApi.cls`: the exact GET JSON, `TestHeartbeatToday` (with the day bounds), `TestFallbackReason`, `TestOnlineDemoFlag`, and the real-beat count.
- `web/src/app/rail/heartbeat-card/heartbeat-card.ts`, `heartbeat-card-view.ts`: the card and its pure rules.
- `web/src/app/api/heartbeat-types.ts`, `api-client.ts`: the types and three methods.
- `web/src/app/live/live-store.ts`, `rail/rail-view.ts`, `rail/status-rail.ts`: the store field and event case, the rail section, `heartbeatReadKey`, the slot.
- `web/scripts/heartbeat-card-view.test.mjs` (new) and the shared-surface updates: `rail-view`, `live-store`, `ux-strings`, `floor-sources`, `announce-focus-sources`.
- `web/e2e/heartbeat-card.spec.ts` (new, 13 tests) and the count updates in `rail/rail.spec.ts`, `frame/frame.spec.ts`; `demo-path/01-page.spec.ts` (7 headings, Heartbeat before Persona, Persona last; the only demo-path edit, U-295).

**Review.** 30 findings: 0 high, 8 medium, 12 low, 10 false. Patched: the day-bound and empty-ItemId rows of `TestHeartbeatToday`, HC3b, HC9b, HC10, HC10b, HC8's quiet base, HC5's stamp, the counter pin, two comments, and HC4 moved to the end of the file. Deferred: none. Rejected with reasons: see the Review Triage Log.

**Follow-up review recommended: true.** Two or more medium entries were patched. The named unverified risk: HC4, HC5 and the status monitor's 15-second publish on a loaded CI runner, because those cases wait on the real tick and the real status event.

**Verification.** See `## Verification` (results and the six mutations). Every unit passed on the final tree; the browser units ran with `OCUTALON_LIVE_DEADLINE=900` per Rule 21. CI placement: `heartbeat-card.spec.ts` measured 183 s, 30.5 min + 3.05 min = 33.6 min under the 35-minute ceiling, so it stays in `live:sign-in` (group `browser`) and no marker is needed.

**Residual risks.** HC8 skips itself within 40 minutes of midnight UTC. HC4 needs the CI mock key and the real tick (about 61 s of wait plus up to 120 s). The browser group's total time now includes this spec's 1.5 to 3 minutes; the first CI run of the head measures it.

### Rework pass 1 (open `[Review]` items only)

Status: done
Blocking condition: none

**Summary.** `HeartbeatApi.TestSaveThenRunAfterATick` (real production) pins the save-then-run case that Story 39.8 fixed: after a Tick has made the Checks job read an empty checklist, a PUT and an at-once run answer 202 sent, not 409 empty. `SettingsOps.HeartbeatValues` now calls `Checks.Beat.Values(ref, 1)` instead of repeating its cache drop (DW-812).

**Files changed.** `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls`, `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`, and this spec.

**Review.** 17 findings: 0 high, 0 medium, 9 low, 8 false. Patched: the Tick-send description in the test's doc and the spec, and the DW-812 mutation line. Deferred: none. Rejected with reasons: the Review Triage Log.

**Follow-up review recommended: false.** This pass patched no high; the work has converged.

**Verification.** `OcuTalon.Test.Web.HeartbeatApi` passed fresh (after the final patch too); `OcuTalon.Test.Core.SettingsHeartbeat` passed warm; `npm --prefix web test` 1494 passed; `test-boundaries.sh` and `test-class-rules.sh` passed. Mutations: the `## Verification` Rework additions.
